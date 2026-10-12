class_name Ragdoll
extends Node3D
## A downed or dead AI body falling and lying as a ragdoll (Captain, 2026-10-11): bodies that
## go down beside or on top of each other rest on one another instead of clipping through,
## and the living walk over a pile instead of through it.
##
## The host simulates it: a rigid body per bone (torso, head, both thighs and shins: the
## bones CharacterModel draws and poses hitboxes from), joined with anatomical limits, starting
## from the pose the body is drawn in as it goes down. Each step it writes the bones to the
## model's replicated ragdoll_net, which every peer draws the body from (and poses its
## hitboxes from, so shots, wounds, blood and charges follow it). Once it has settled it
## freezes: nothing shoves it, and a body falling on it comes to rest on top.
##
## Every other peer builds the same parts as static colliders that follow ragdoll_net, so a
## player (who drives their own movement) walks over bodies on their own machine too.
## Soldier._update_ragdoll starts and stops it: an AI body down and not carried has one;
## carried or dragged it hasn't (putting it down drops it again), nor once it's back up.
## Arms keep the model's own limp swing (proposed: arm parts later).

## Layer 6 ("ragdolls"): the parts. They meet the world and each other; living soldiers meet
## them (SoldierMovement.UP_MASK) and step up over them.
const LAYER := 1 << 5
const MASK := 1 | LAYER
const GROUP := &"ragdoll_parts"
## Proposed: part masses (kg) and shapes (metres, a male body; scaled by the body's size):
## [box size or sphere radius, centre from the bone's pivot].
const PARTS := {
	"torso": {"mass": 32.0, "box": Vector3(0.34, 0.6, 0.22), "at": Vector3(0, 0.29, 0)},
	"head": {"mass": 5.0, "sphere": 0.11, "at": Vector3(0, 0.13, 0)},
	"leg_l": {"mass": 10.0, "box": Vector3(0.15, 0.45, 0.15), "at": Vector3(0, -0.225, 0)},
	"leg_r": {"mass": 10.0, "box": Vector3(0.15, 0.45, 0.15), "at": Vector3(0, -0.225, 0)},
	"shin_l": {"mass": 5.0, "box": Vector3(0.12, 0.47, 0.13), "at": Vector3(0, -0.235, 0.015)},
	"shin_r": {"mass": 5.0, "box": Vector3(0.12, 0.47, 0.13), "at": Vector3(0, -0.235, 0.015)},
}
## Joints: [parent, child, the child's pivot in the parent's frame at rest, angular limits
## (radians, lower/upper about x, y, z, measured from rest)]. Thighs swing forward on +x, knees
## bend on -x (CharacterModel's pose_bones and _knee).
const JOINTS := [
	["torso", "head", CharacterModel.HEAD_PIVOT, Vector3(-0.6, -0.8, -0.4), Vector3(0.7, 0.8, 0.4)],
	["torso", "leg_l", Vector3(-CharacterModel.HIP.x, 0, 0), Vector3(-0.5, -0.3, -0.6), Vector3(1.8, 0.3, 0.6)],
	["torso", "leg_r", Vector3(CharacterModel.HIP.x, 0, 0), Vector3(-0.5, -0.3, -0.6), Vector3(1.8, 0.3, 0.6)],
	["leg_l", "shin_l", Vector3(0, -CharacterModel.THIGH, 0), Vector3(-2.4, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
	["leg_r", "shin_r", Vector3(0, -CharacterModel.THIGH, 0), Vector3(-2.4, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
]
## Settled: every part slower than this (m/s, rad/s) for SETTLE_S, or SETTLE_MAX_S after it fell.
const SETTLE_SPEED := 0.08
const SETTLE_S := 0.6
const SETTLE_MAX_S := 8.0
## A pose change smaller than this (metres) isn't sent.
const SEND_EPSILON := 0.003

## Turn off for a session (the older suites that check the fixed downed pose).
static var enabled := true

var body: Soldier
var parts: Dictionary = {}  # bone -> RigidBody3D (host) or StaticBody3D (other peers)
var simulated := false      # the host's: rigid bodies
var frozen := false
var _still_s := 0.0
var _age_s := 0.0
var _sent := PackedFloat32Array()
var _root_last: Variant = null  # the body's transform last step (host)


## Host: starts a ragdoll for `soldier` from the pose it's drawn in (or its saved ragdoll pose).
static func start(soldier: Soldier) -> Ragdoll:
	var r := Ragdoll.new()
	r.body = soldier
	r.simulated = true
	r.name = "Ragdoll"
	r.top_level = true
	soldier.add_child(r)
	r.global_transform = Transform3D.IDENTITY
	var start_bones: Dictionary = part_bones(soldier.model) if soldier.model.ragdolled() else r._drawn_bones()
	r._build(start_bones)
	var push := soldier.velocity if soldier.velocity.is_finite() else Vector3.ZERO
	for p: RigidBody3D in r.parts.values():
		p.linear_velocity = push
	return r


## Other peers: static parts that follow the body's ragdoll_net.
static func follow(soldier: Soldier) -> Ragdoll:
	var r := Ragdoll.new()
	r.body = soldier
	r.name = "Ragdoll"
	r.top_level = true
	soldier.add_child(r)
	r.global_transform = Transform3D.IDENTITY
	r._build(part_bones(soldier.model))
	return r


## Stops it (the host clears ragdoll_net) and frees the parts.
func stop() -> void:
	if simulated and is_instance_valid(body) and body.model:
		body.model.ragdoll_net = PackedFloat32Array()
	queue_free()


## The bones as drawn now (model space): where the parts start.
func _drawn_bones() -> Dictionary:
	var m := body.model
	var inv := m.global_transform.affine_inverse()
	return {"torso": inv * m.torso.global_transform, "head": inv * m.head.global_transform,
		"leg_l": inv * m.part_node(Vitals.THIGH_L).global_transform, "leg_r": inv * m.part_node(Vitals.THIGH_R).global_transform,
		"shin_l": inv * m.part_node(Vitals.SHIN_L).global_transform, "shin_r": inv * m.part_node(Vitals.SHIN_R).global_transform}


func _build(bones: Dictionary) -> void:
	var m := body.model
	var s := m.body_scale()
	for key: String in CharacterModel.RAGDOLL_BONES:
		var spec: Dictionary = PARTS[key]
		var part: PhysicsBody3D = RigidBody3D.new() if simulated else StaticBody3D.new()
		part.name = key
		part.collision_layer = LAYER
		part.collision_mask = MASK if simulated else 0
		part.add_to_group(GROUP)
		part.set_meta(&"ragdoll_of", body)
		var shape := CollisionShape3D.new()
		if spec.has("box"):
			var box := BoxShape3D.new()
			box.size = (spec.box as Vector3) * s
			shape.shape = box
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = float(spec.sphere) * s
			shape.shape = sphere
		shape.position = (spec.at as Vector3) * s
		part.add_child(shape)
		if part is RigidBody3D:
			var rb := part as RigidBody3D
			rb.mass = float(spec.mass)
			rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			rb.center_of_mass = shape.position
			rb.continuous_cd = true
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.linear_damp = 0.1
			rb.angular_damp = 1.5
		add_child(part)
		part.global_transform = _world(bones[key], m)
		parts[key] = part
	if not simulated:
		return
	for a: PhysicsBody3D in parts.values():
		for b: PhysicsBody3D in parts.values():
			if a != b:
				a.add_collision_exception_with(b)
	for j: Array in JOINTS:
		var parent: RigidBody3D = parts[j[0]]
		var child: RigidBody3D = parts[j[1]]
		var joint := Generic6DOFJoint3D.new()
		joint.name = "%s_%s" % [j[0], j[1]]
		add_child(joint)
		# The joint's frame is the child's rest place on the parent, so its limits are measured
		# from the rest pose, whatever pose the body falls from.
		joint.global_transform = Transform3D(parent.global_basis, child.global_position)
		var lo: Vector3 = j[3]
		var hi: Vector3 = j[4]
		for axis in 3:
			var setter := [&"set_flag_x", &"set_flag_y", &"set_flag_z"][axis] as StringName
			var param := [&"set_param_x", &"set_param_y", &"set_param_z"][axis] as StringName
			joint.call(setter, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call(param, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lo[axis])
			joint.call(param, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, hi[axis])
		joint.node_a = joint.get_path_to(parent)
		joint.node_b = joint.get_path_to(child)


## A model-space bone as a world transform without the body's scale (physics bodies can't scale).
static func _world(bone: Transform3D, m: CharacterModel) -> Transform3D:
	var t := m.global_transform * bone
	return Transform3D(t.basis.orthonormalized(), t.origin)


## The parts as model-space bones (the body's scale put back).
func _bones() -> Dictionary:
	var m := body.model
	var inv := m.global_transform.affine_inverse()
	var scale := Basis.from_scale(Vector3.ONE * m.body_scale())
	var out := {}
	for key: String in parts:
		var g: Transform3D = (parts[key] as Node3D).global_transform
		out[key] = inv * Transform3D(g.basis * scale, g.origin)
	return out


func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or body.model == null:
		queue_free()
		return
	if not simulated:
		_follow()
		return
	_carry_along()
	if frozen:
		return
	_age_s += delta
	var still := true
	for p: RigidBody3D in parts.values():
		if p.linear_velocity.length() > SETTLE_SPEED or p.angular_velocity.length() > SETTLE_SPEED * 3.0:
			still = false
			break
	_still_s = _still_s + delta if still else 0.0
	_send()
	if _still_s >= SETTLE_S or _age_s >= SETTLE_MAX_S:
		freeze()


## Host: the body itself only moves while it's a ragdoll when something puts it somewhere (a
## restore, a script, a test): the parts go with it, as they lie.
func _carry_along() -> void:
	var now := body.global_transform
	if _root_last == null:
		_root_last = now
		return
	var last: Transform3D = _root_last
	if now.is_equal_approx(last):
		return
	_root_last = now
	var moved := now * last.affine_inverse()
	for p: Node3D in parts.values():
		p.global_transform = moved * p.global_transform
	_send(true)


## Host: holds it where it lies (static: nothing shoves it; falling bodies rest on it).
func freeze() -> void:
	frozen = true
	for p: RigidBody3D in parts.values():
		p.freeze = true
	_send(true)


## Host: lets it move again (a blast, a body landing on it later).
func unfreeze() -> void:
	if not simulated:
		return
	frozen = false
	_still_s = 0.0
	_age_s = 0.0
	for p: RigidBody3D in parts.values():
		p.freeze = false
		p.sleeping = false


func _send(force := false) -> void:
	var packed := CharacterModel.pack_ragdoll(_bones())
	if force or _sent.size() != packed.size() or _moved(packed):
		_sent = packed
		body.model.ragdoll_net = packed


func _moved(packed: PackedFloat32Array) -> bool:
	for i in range(0, packed.size(), 7):
		if Vector3(packed[i], packed[i + 1], packed[i + 2]).distance_to(Vector3(_sent[i], _sent[i + 1], _sent[i + 2])) > SEND_EPSILON:
			return true
	return false


## Other peers: the static parts follow the replicated pose.
func _follow() -> void:
	if not body.model.ragdolled():
		return
	var bones := part_bones(body.model)
	for key: String in parts:
		(parts[key] as Node3D).global_transform = _world(bones[key], body.model)


## The model's ragdoll_net as one model-space transform per part (RAGDOLL_BONES keys).
static func part_bones(m: CharacterModel) -> Dictionary:
	var b := m.ragdoll_bones()
	return {"torso": b.torso, "head": b.head, "leg_l": b.leg_l, "leg_r": b.leg_r,
		"shin_l": (b.leg_l as Transform3D) * (b.knee_l as Transform3D), "shin_r": (b.leg_r as Transform3D) * (b.knee_r as Transform3D)}


## The body a ragdoll part belongs to (or null): for anything that hit one.
static func body_of(collider: Object) -> Soldier:
	if collider is Node and (collider as Node).has_meta(&"ragdoll_of"):
		return (collider as Node).get_meta(&"ragdoll_of") as Soldier
	return null
