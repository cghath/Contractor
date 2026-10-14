class_name Ragdoll
extends Node3D
## A downed (unconscious) or dead body, AI or player, falling and lying as a ragdoll (Captain,
## 2026-10-11): bodies that go down beside or on top of each other rest on one another instead of
## clipping through, and the living walk over a pile instead of through it.
##
## The host simulates it: a rigid body per part (torso, head, thighs, shins, upper arms and
## forearms: the parts CharacterModel draws), joined with anatomical limits, starting
## from the pose the body is drawn in as it goes down. Each step it writes the bones to the
## model's replicated ragdoll_net, which every peer draws the body from (and poses its
## hitboxes from, so shots, wounds, blood and charges follow it). Once it has settled it
## freezes: nothing shoves it, and a body falling on it comes to rest on top.
##
## Every other peer builds the same parts as static colliders that follow ragdoll_net, so a
## player (who drives their own movement) walks over bodies on their own machine too.
## Soldier._update_ragdoll starts and stops it: a body down and not carried has one; carried
## over the shoulder it hasn't (putting it down drops it again), nor once it's back up. When
## it goes, the body stands where it lay (rest_spot), not where it fell.
## Dragged (Captain, 2026-10-14), it stays a ragdoll: only the shoulder straps are held, by a
## soft pin (a capped spring-damper force, not a joint, so a snag can't throw the body) to the
## dragger's hands, and the rest trails on the ground: legs drag and catch, arms flop, the head
## lolls within the neck's limits. The body (capsule) stays where it was while the parts move,
## so every peer draws the same pose from ragdoll_net without the body's position sync in the
## way; let go, an AI body moves to where the ragdoll lies (_rebase) and it settles as any other.
## Arms are parts too (upper arm and forearm), with shoulder and elbow limits.

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
	"arm_r": {"mass": 2.5, "box": Vector3(0.1, 0.32, 0.1), "at": Vector3(0, -0.16, 0)},
	"arm_l": {"mass": 2.5, "box": Vector3(0.1, 0.32, 0.1), "at": Vector3(0, -0.16, 0)},
	"fore_r": {"mass": 1.8, "box": Vector3(0.09, 0.3, 0.09), "at": Vector3(0, -0.14, 0)},
	"fore_l": {"mass": 1.8, "box": Vector3(0.09, 0.3, 0.09), "at": Vector3(0, -0.14, 0)},
}
## Joints: [parent, child, angular limits (radians, lower and upper about x, y, z, measured from
## rest, where each child lines up with its parent)]. Thighs swing forward on +x, knees bend on
## -x (CharacterModel's pose_bones and _knee); arms swing on x, a right arm lifts out on +z (a
## left on -z), elbows bend on +x.
## The neck (Captain, 2026-10-14): flexion (chin down, -x) and extension 50 degrees, side
## bend 35 each way, twist 65 each way.
const JOINTS := [
	["torso", "head", Vector3(-0.87, -1.13, -0.61), Vector3(0.87, 1.13, 0.61)],
	["torso", "leg_l", Vector3(-0.5, -0.3, -0.6), Vector3(1.8, 0.3, 0.6)],
	["torso", "leg_r", Vector3(-0.5, -0.3, -0.6), Vector3(1.8, 0.3, 0.6)],
	["leg_l", "shin_l", Vector3(-2.4, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
	["leg_r", "shin_r", Vector3(-2.4, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
	["torso", "arm_r", Vector3(-2.2, -0.9, -0.15), Vector3(2.6, 0.9, 1.6)],
	["torso", "arm_l", Vector3(-2.2, -0.9, -1.6), Vector3(2.6, 0.9, 0.15)],
	["arm_r", "fore_r", Vector3(0.0, -0.6, -0.05), Vector3(2.5, 0.6, 0.05)],
	["arm_l", "fore_l", Vector3(0.0, -0.6, -0.05), Vector3(2.5, 0.6, 0.05)],
]
## Settled: every part slower than this (m/s, rad/s) for SETTLE_S, or SETTLE_MAX_S after it fell.
const SETTLE_SPEED := 0.08
const SETTLE_S := 0.6
const SETTLE_MAX_S := 8.0
## Dragging (the soft pin): the strap point (strap_point, torso space) is pulled to the
## dragger's hands with this stiffness (N/m) and damping (N s/m), the pull capped at
## PIN_MAX_N; a body snagged further than PIN_SNAG_M behind comes along bodily. The torso is
## turned gently head first towards the dragger and kept face up (N m/rad, N m s/rad).
const PIN_K := 4000.0
const PIN_C := 900.0
const PIN_MAX_N := 2600.0
const PIN_SNAG_M := 1.6
const PIN_TURN_K := 150.0
const PIN_TURN_C := 35.0
## The neck while dragged: a little spring toward neutral and damping (N m/rad, N m s/rad,
## against the torso), so the head sways and rolls with the steps but never snaps or bobbles;
## held up (a conscious body) it's much stiffer.
const NECK_K := 1.6
const NECK_C := 0.35
const NECK_HELD_K := 22.0
const NECK_HELD_C := 1.6
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
var _pinned := false            # a dragger holds it by the straps (host)
var _pin_by: Soldier = null     # who (check is_instance_valid: they can be freed)
var _pin_from := Vector3.ZERO   # where the straps were when the take-hold began (world)


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
	r._root_last = soldier.global_transform  # parts built where the body is: carried along from here, even before the first step
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


## Proposed: where a body stands up from its ragdoll (rest_spot): ground found by a ray from this
## far above the hips down to this far below them, walkable up to MAX_SLOPE_Y (normal's y), and
## tried at the hips, then on rings of these radii (metres) round them if a wall is in the way.
const GROUND_ABOVE := 0.6
const GROUND_BELOW := 2.5
const MAX_SLOPE_Y := 0.6
const SPOT_RINGS: Array[float] = [0.35, 0.7]
const SPOT_DIRECTIONS := 8


## Where the body stands up from the ragdoll as it lies now (host and following peers alike, from
## the parts): on the ground under its hips, clear of walls for a standing capsule, facing the
## way it gets up (chest down: towards its head; on its back: towards its feet). Null when no
## safe ground is near, so the body stays where it fell.
func rest_spot() -> Variant:
	if not is_instance_valid(body) or body.model == null or not parts.has("torso") or not body.is_inside_tree():
		return null
	if simulated:
		_carry_along()  # the body put somewhere this frame (a restore, a script) takes the parts along first
	var torso := parts["torso"] as Node3D
	var hips := torso.global_position  # the torso part's pivot is the pelvis (rest_bones)
	var space := body.get_world_3d().direct_space_state
	var candidates: Array[Vector3] = [hips]
	for radius in SPOT_RINGS:
		for i in SPOT_DIRECTIONS:
			var angle := TAU * i / SPOT_DIRECTIONS
			candidates.append(hips + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	for c in candidates:
		var ground: Variant = _ground_below(space, c, hips)
		if ground != null:
			return Transform3D(Basis(Vector3.UP, _stand_yaw(torso)), ground)
	return null


## Ground under `at` that a standing body fits on, reachable from `hips` without passing a wall;
## null if none.
func _ground_below(space: PhysicsDirectSpaceState3D, at: Vector3, hips: Vector3) -> Variant:
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * GROUND_ABOVE, at + Vector3.DOWN * GROUND_BELOW, SoldierMovement.WORLD_MASK)
	var hit := space.intersect_ray(down)
	if hit.is_empty() or (hit.normal as Vector3).y < MAX_SLOPE_Y:
		return null
	var ground: Vector3 = hit.position
	if at != hips:
		var from := hips + Vector3.UP * 0.3
		var across := PhysicsRayQueryParameters3D.create(from, Vector3(ground.x, from.y, ground.z), SoldierMovement.WORLD_MASK)
		if not space.intersect_ray(across).is_empty():
			return null  # a wall between where it lies and there
	var margin := SoldierMovement.ROOM_MARGIN
	var shape := CapsuleShape3D.new()
	shape.radius = SoldierMovement.CAPSULE_RADIUS - margin
	shape.height = SoldierMovement.STANCE_CAPSULE[SoldierMovement.Stance.STAND_HIGH] - margin * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), ground + Vector3.UP * (margin * 2.0 + shape.height * 0.5))
	query.collision_mask = SoldierMovement.WORLD_MASK
	query.exclude = [body.get_rid()]
	return ground if space.intersect_shape(query, 1).is_empty() else null


## The body's yaw getting up, from the torso as it lies: chest down, it pushes up facing its
## head; on its back or side, it sits up facing its feet; slumped upright, it faces where its
## chest does.
func _stand_yaw(torso: Node3D) -> float:
	var to_model := body.model.transform.basis.orthonormalized().inverse()  # the soldier's axes in model space
	var up := torso.global_basis * (to_model * Vector3.UP)
	var chest := torso.global_basis * (to_model * Vector3.FORWARD)
	var face := Vector3(up.x, 0.0, up.z) * (1.0 if chest.y < 0.0 else -1.0)
	if face.length() < 0.3:
		face = Vector3(chest.x, 0.0, chest.z)
	if face.length() < 0.1:
		return body.rotation.y
	return atan2(-face.x, -face.z)


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
		"shin_l": inv * m.part_node(Vitals.SHIN_L).global_transform, "shin_r": inv * m.part_node(Vitals.SHIN_R).global_transform,
		"arm_r": inv * m.part_node(Vitals.UPPER_ARM_R).global_transform, "arm_l": inv * m.part_node(Vitals.UPPER_ARM_L).global_transform,
		"fore_r": inv * m.part_node(Vitals.FOREARM_R).global_transform, "fore_l": inv * m.part_node(Vitals.FOREARM_L).global_transform}


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
		var lo: Vector3 = j[2]
		var hi: Vector3 = j[3]
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
	var by := body.carried_by
	if is_instance_valid(by) and by.carrying == body and by.carry_mode == Soldier.DRAG:
		_root_last = body.global_transform  # the body stays put while dragged: nothing to carry along
		_pin(by)
		_send()
		return
	if _pinned:
		_unpin()
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


## The strap point in torso space: between the shoulder straps, at the top of the chest.
static func strap_point() -> Vector3:
	return (CharacterModel.STRAP_POINTS[0] + CharacterModel.STRAP_POINTS[1]) * 0.5


## Where a dragger's hands hold the straps (world): the drag hold (CharacterModel.drag_hand_points)
## on `by`.
static func hold_point(by: Soldier) -> Vector3:
	var hands := CharacterModel.drag_hand_points()
	return by.global_transform * ((hands[0] + hands[1]) * 0.5)


## Host, each step while `by` drags it: the straps pulled to the hands (rising there through
## the take-hold), the torso turned head first and face up, the neck sprung; the rest is free.
func _pin(by: Soldier) -> void:
	var torso := parts["torso"] as RigidBody3D
	var strap := torso.global_transform * (strap_point() * body.model.body_scale())
	if not _pinned or _pin_by != by:
		if _pinned:
			_unpin()
		_pinned = true
		_pin_by = by
		_pin_from = strap
		if frozen:
			unfreeze()
		for p: PhysicsBody3D in parts.values():
			by.add_collision_exception_with(p)  # the dragger's capsule doesn't stand on the casualty
	for p: RigidBody3D in parts.values():
		p.sleeping = false
	var target := hold_point(by)
	var u := by.drag_grab_u()
	if u < 1.0:
		target = _pin_from.lerp(target, smoothstep(CharacterModel.GRAB_RISE.x, CharacterModel.GRAB_RISE.y, u))
	var off := target - strap
	if off.length() > PIN_SNAG_M:
		# Snagged (a corner, a ledge it can't ride up): it comes along bodily rather than the
		# pull stretching until it throws the body.
		var shift := off - off.normalized() * PIN_SNAG_M * 0.5
		for p: RigidBody3D in parts.values():
			p.global_position += shift
		strap += shift
		off = target - strap
	var arm := strap - torso.global_position
	var point_v := torso.linear_velocity + torso.angular_velocity.cross(arm)
	var force := (off * PIN_K + (by.velocity - point_v) * PIN_C).limit_length(PIN_MAX_N)
	torso.apply_force(force, arm)
	# Head first towards the dragger and face up: a gentle turn, so it trails straight behind
	# the hands and doesn't roll onto its front.
	var spine := torso.global_basis.y.normalized()
	var chest := -torso.global_basis.z.normalized()
	var turn := Vector3.ZERO
	var head_way := Vector3(target.x - torso.global_position.x, 0.0, target.z - torso.global_position.z)
	var flat_spine := Vector3(spine.x, 0.0, spine.z)
	if head_way.length() > 0.1 and flat_spine.length() > 0.1:
		turn += Vector3.UP * flat_spine.normalized().cross(head_way.normalized()).y
	turn += spine * chest.cross(Vector3.UP).dot(spine) * 0.5
	torso.apply_torque(turn * PIN_TURN_K - torso.angular_velocity * PIN_TURN_C)
	_spring_neck(body.vitals.is_up())


## Host: the head eased toward neutral on the torso (at rest it lines up with it), damped
## against the torso's turn, so it lolls and rolls with the drag without bobbing; `held` (a
## conscious body) holds it up.
func _spring_neck(held: bool) -> void:
	var torso := parts["torso"] as RigidBody3D
	var head := parts["head"] as RigidBody3D
	var rel := (torso.global_basis.orthonormalized().inverse() * head.global_basis.orthonormalized()).get_rotation_quaternion()
	var angle := rel.get_angle()
	if angle < 0.0001:
		return
	if angle > PI:
		angle -= TAU
	var bend := torso.global_basis.orthonormalized() * (rel.get_axis() * angle)
	var k := NECK_HELD_K if held else NECK_K
	var c := NECK_HELD_C if held else NECK_C
	var torque := -bend * k - (head.angular_velocity - torso.angular_velocity) * c
	head.apply_torque(torque)
	torso.apply_torque(-torque)


## Host: let go of (the dragger released it, or lost hold): it settles like any other.
func _unpin() -> void:
	if is_instance_valid(_pin_by):
		for p: PhysicsBody3D in parts.values():
			_pin_by.remove_collision_exception_with(p)
	_pinned = false
	_pin_by = null
	_still_s = 0.0
	_age_s = 0.0
	if body.is_ai():
		_rebase()


## Host, an AI body: moves the body (origin on the ground) under the ragdoll's hips, leaving the
## parts where they lie, so what reads the body's position (cover, distances) finds it where it
## was dragged to. A player's own machine owns theirs (they stand up where the ragdoll lay
## anyway: rest_spot).
func _rebase() -> void:
	var hips := (parts["torso"] as Node3D).global_position
	var spot := hips + Vector3.DOWN * 0.15
	if body.is_inside_tree():
		var hit := body.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.3, hips + Vector3.DOWN * 1.5, SoldierMovement.WORLD_MASK))
		if not hit.is_empty():
			spot = hit.position
	body.global_position = spot
	_root_last = body.global_transform
	_send(true)


## Host: whether a dragger holds it by the straps now.
func pinned() -> bool:
	return _pinned


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
	return m.ragdoll_parts()


## The body a ragdoll part belongs to (or null): for anything that hit one.
static func body_of(collider: Object) -> Soldier:
	if collider is Node and (collider as Node).has_meta(&"ragdoll_of"):
		return (collider as Node).get_meta(&"ragdoll_of") as Soldier
	return null
