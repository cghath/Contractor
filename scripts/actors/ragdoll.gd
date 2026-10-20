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
## Soldier._update_ragdoll starts and stops it: a body down and not carried has one;
## carried or dragged it hasn't (putting it down drops it again), nor once it's back up. When
## it goes, the body stands where it lay (rest_spot), not where it fell.
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
## left on -z), elbows bend on +x. Captain, 2026-10-16 ("propping up so often on the knees ... is
## annoying"; elbows fine): knees bend at most 1.5 (was 2.4) and thighs swing forward 1.35 (was 1.8),
## so a body falls flat or on its side more than it kneels.
const JOINTS := [
	["torso", "head", Vector3(-0.6, -0.8, -0.4), Vector3(0.7, 0.8, 0.4)],
	["torso", "leg_l", Vector3(-0.5, -0.3, -0.6), Vector3(1.35, 0.3, 0.6)],
	["torso", "leg_r", Vector3(-0.5, -0.3, -0.6), Vector3(1.35, 0.3, 0.6)],
	["leg_l", "shin_l", Vector3(-1.5, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
	["leg_r", "shin_r", Vector3(-1.5, -0.05, -0.05), Vector3(0.0, 0.05, 0.05)],
	["torso", "arm_r", Vector3(-2.2, -0.9, -0.15), Vector3(2.6, 0.9, 1.6)],
	["torso", "arm_l", Vector3(-2.2, -0.9, -1.6), Vector3(2.6, 0.9, 0.15)],
	["arm_r", "fore_r", Vector3(0.0, -0.6, -0.05), Vector3(2.5, 0.6, 0.05)],
	["arm_l", "fore_l", Vector3(0.0, -0.6, -0.05), Vector3(2.5, 0.6, 0.05)],
]
## Settled: every part slower than this (m/s, rad/s) for SETTLE_S, or SETTLE_MAX_S after it fell.
const SETTLE_SPEED := 0.08
const SETTLE_S := 0.6
const SETTLE_MAX_S := 8.0
## A pose change smaller than this (metres) isn't sent.
const SEND_EPSILON := 0.003
## Captain, 2026-10-14 ("weird ragdoll": a downed man lying in the air at chest height, legs
## hanging): a settled ragdoll is frozen (static), so when what it came to rest on went (a body
## under it carried off, standing up or gone with the body cap, a wall blown away) it stayed
## where it was, in the air. Every SUPPORT_CHECK_S a frozen one looks under its torso (along it
## at SUPPORT_ALONG of its length each way, and its middle) for anything within SUPPORT_GAP_M
## below the box; with nothing there it lets go and falls again (has_support, _check_support).
const SUPPORT_CHECK_S := 0.5
const SUPPORT_GAP_M := 0.1  # less than a torso's depth: a body lying on another one has support, one left above it hasn't
const SUPPORT_ALONG := 0.4

## Captain, 2026-10-17 ("make them unsettlingly true to life. ragdolls fall realistically"):
## - The shot that dropped him pushes the part it hit (HIT_IMPULSE by round, N s, at the hit
##   point, along the shot) if it landed within HIT_FRESH_S of the fall: he folds the way he
##   was hit, a headshot snaps the head back.
## - No muscle left: the knees give at once (BUCKLE_RAD_S, shins folding back, thighs forward),
##   so a body drops onto its knees and folds rather than toppling stiff like a plank.
## - Limbs swing freely (LIMB_ANGULAR_DAMP; the torso TORSO_ANGULAR_DAMP), and the parts grip and
##   don't bounce (RAGDOLL_FRICTION, no bounce): it lands heavy and stays where it lands.
const HIT_IMPULSE := {&"pistol": 9.0, &"intermediate": 14.0, &"full_power": 22.0, &"fragment": 12.0}
const HIT_FRESH_S := 0.5
const BUCKLE_RAD_S := 3.5
const LIMB_ANGULAR_DAMP := 0.5
const TORSO_ANGULAR_DAMP := 0.9
const RAGDOLL_FRICTION := 0.95
## No kneeling or sitting corpses (Captain, 2026-10-17 screenshot: "sometimes they drop like
## this", bodies settled upright on their knees on a slope): about to freeze with the torso
## still upright (its up within acos(UPRIGHT_DOT) of the world's), it's pushed over at the
## shoulders (TOPPLE_IMPULSE, N s: along the dropping shot, else the way it faces), at most
## TOPPLE_MAX times; then it freezes as it lies.
const UPRIGHT_DOT := 0.6
const TOPPLE_IMPULSE := 30.0
const TOPPLE_MAX := 2

## Cut-off parts (blast-gore, 2026-10-20: a severed limb's physics body stayed and the hidden limb
## still propped the corpse up): a part cut off a body (BodyDeform, Vitals) takes its ragdoll part
## along (CUT_KEY) and everything under it (CUT_BELOW); the part's own stays as a stump as long as
## what's left of it (BodyDeform.stump_of), or goes if hardly any is left (MIN_STUMP). The head
## goes whole. A frozen ragdoll falls again (it may have been resting on what went).
const CUT_KEY := {Vitals.HEAD: "head", Vitals.THIGH_L: "leg_l", Vitals.THIGH_R: "leg_r", Vitals.SHIN_L: "shin_l", Vitals.SHIN_R: "shin_r",
	Vitals.UPPER_ARM_L: "arm_l", Vitals.UPPER_ARM_R: "arm_r", Vitals.FOREARM_L: "fore_l", Vitals.FOREARM_R: "fore_r"}
const CUT_BELOW := {"leg_l": ["shin_l"], "leg_r": ["shin_r"], "arm_l": ["fore_l"], "arm_r": ["fore_r"]}
const MIN_STUMP := 0.15

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
var _support_left := SUPPORT_CHECK_S
var _woke_at: Variant = null  # where the torso was when it last fell again for want of support
var _topples := 0
var _hit_dir := Vector3.ZERO  # the dropping shot's way (flat), for _topple
var cut_away := {}  # ragdoll part key -> true: gone with a cut (no collider, no joint)


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
	r._cut_severed()
	r._root_last = soldier.global_transform  # parts built where the body is: carried along from here, even before the first step
	var push := soldier.velocity if soldier.velocity.is_finite() else Vector3.ZERO
	for p: RigidBody3D in r.parts.values():
		p.linear_velocity = push
	if not soldier.model.ragdolled():  # a fresh fall (not a saved pose put back)
		r._buckle()
		r._take_hit(soldier.vitals.last_hit if soldier.vitals else {})
	return r


## The knees give: shins fold back about the thighs' x, thighs swing forward about the torso's.
func _buckle() -> void:
	var torso := parts.get("torso") as RigidBody3D
	for side: String in ["l", "r"]:
		var leg := parts.get("leg_" + side) as RigidBody3D
		var shin := parts.get("shin_" + side) as RigidBody3D
		if leg and torso:
			leg.angular_velocity += torso.global_basis.x * BUCKLE_RAD_S * 0.5
		if shin and leg:
			shin.angular_velocity += leg.global_basis.x * -BUCKLE_RAD_S


## The dropping shot's push on the part nearest where it hit.
func _take_hit(hit: Dictionary) -> void:
	if hit.is_empty() or Time.get_ticks_msec() / 1000.0 - float(hit.get("time", -INF)) > HIT_FRESH_S:
		return
	var at: Vector3 = hit.position
	var dir: Vector3 = hit.direction
	if not at.is_finite() or dir.length() < 0.01:
		return
	_hit_dir = Vector3(dir.x, 0.0, dir.z)
	var best: RigidBody3D = null
	for p: RigidBody3D in parts.values():
		if best == null or (p.global_transform * p.center_of_mass).distance_to(at) < (best.global_transform * best.center_of_mass).distance_to(at):
			best = p
	if best:
		best.apply_impulse(dir.normalized() * float(HIT_IMPULSE.get(hit.get("round_class", &"intermediate"), 14.0)), at - best.global_position)


## Other peers: static parts that follow the body's ragdoll_net.
static func follow(soldier: Soldier) -> Ragdoll:
	var r := Ragdoll.new()
	r.body = soldier
	r.name = "Ragdoll"
	r.top_level = true
	soldier.add_child(r)
	r.global_transform = Transform3D.IDENTITY
	r._build(part_bones(soldier.model))
	r._cut_severed()
	return r


## The parts the body has lost already (BodyDeform) taken off as the ragdoll starts.
func _cut_severed() -> void:
	var deform := body.model.get_node_or_null(^"BodyDeform") as BodyDeform if body.model else null
	if deform == null:
		return
	for part: StringName in deform.severed():
		cut(part, deform.stump_of(part))


## `part` (a Vitals part) was cut off with `stump` (0..1) of it left: its ragdoll part shrinks to
## the stump (or goes, under MIN_STUMP; the head always), and what hangs below it goes.
func cut(part: StringName, stump := 0.5) -> void:
	var key: String = CUT_KEY.get(part, "")
	if key == "" or cut_away.has(key):
		return
	if part == Vitals.HEAD or stump < MIN_STUMP:
		_remove_part(key)
	else:
		_shorten(key, stump)
	for below: String in CUT_BELOW.get(key, []):
		_remove_part(below)
	if simulated and frozen:
		unfreeze()


## A part gone: no collider, no joint; the host's held where it is (its bone, drawn hidden).
func _remove_part(key: String) -> void:
	if cut_away.has(key) or not parts.has(key):
		return
	cut_away[key] = true
	var p := parts[key] as PhysicsBody3D
	for child in p.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	if not simulated:
		return
	for child in get_children():
		var joint := child as Generic6DOFJoint3D
		if joint and (String(joint.name).begins_with(key + "_") or String(joint.name).ends_with("_" + key)):
			joint.queue_free()
	(p as RigidBody3D).freeze = true


## A part cut part-way: its box is the stump's length, from the joint.
func _shorten(key: String, share: float) -> void:
	var p := parts.get(key) as Node3D
	if p == null:
		return
	for child in p.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size.y *= share
			shape.shape = box
			shape.position.y *= share
			if p is RigidBody3D:
				(p as RigidBody3D).center_of_mass = shape.position
				(p as RigidBody3D).mass = maxf(float(PARTS[key].mass) * share, 0.5)


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
			rb.angular_damp = TORSO_ANGULAR_DAMP if key == "torso" else LIMB_ANGULAR_DAMP
			var mat := PhysicsMaterial.new()
			mat.friction = RAGDOLL_FRICTION
			mat.rough = true
			mat.bounce = 0.0
			rb.physics_material_override = mat
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
	_carry_along()
	if frozen:
		_check_support(delta)
		return
	_age_s += delta
	var still := true
	for key: String in parts:
		var p := parts[key] as RigidBody3D
		if cut_away.has(key):
			continue
		if p.linear_velocity.length() > SETTLE_SPEED or p.angular_velocity.length() > SETTLE_SPEED * 3.0:
			still = false
			break
	_still_s = _still_s + delta if still else 0.0
	_send()
	if _still_s >= SETTLE_S and _age_s < SETTLE_MAX_S and _topple():
		return  # came to rest upright: over it goes (still frozen by SETTLE_MAX_S whatever happens)
	if _still_s >= SETTLE_S or _age_s >= SETTLE_MAX_S:
		freeze()


## Settled upright: pushed over (see TOPPLE_*). True if it was (it falls on, not frozen yet).
func _topple() -> bool:
	var torso := parts.get("torso") as RigidBody3D
	if torso == null or _topples >= TOPPLE_MAX or torso.global_basis.y.dot(Vector3.UP) < UPRIGHT_DOT:
		return false
	_topples += 1
	var way := _hit_dir
	if way.length() < 0.1:
		way = -torso.global_basis.z
		way.y = 0.0
	if way.length() < 0.01:
		way = Vector3.FORWARD
	torso.apply_impulse(way.normalized() * TOPPLE_IMPULSE, torso.global_basis.y * 0.5)
	_still_s = 0.0
	return true


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


## Host, frozen: every SUPPORT_CHECK_S, with nothing under the torso any more it falls again.
## Not twice from the same spot: a torso that settled where it can't find support under its
## middle line (hanging over an edge it rests on) stays.
func _check_support(delta: float) -> void:
	_support_left -= delta
	if _support_left > 0.0:
		return
	_support_left = SUPPORT_CHECK_S
	if has_support():
		return
	var torso := parts.get("torso") as Node3D
	if torso == null or (_woke_at != null and torso.global_position.distance_to(_woke_at) < 0.05):
		return
	_woke_at = torso.global_position
	unfreeze()


## Whether anything (the world, or another body's parts) is within SUPPORT_GAP_M under the
## torso box: straight down from its middle and from SUPPORT_ALONG of its length towards
## each end.
func has_support() -> bool:
	var torso := parts.get("torso") as Node3D
	if torso == null or not torso.is_inside_tree() or torso.get_child_count() == 0:
		return true
	var shape := torso.get_child(0) as CollisionShape3D
	var box := shape.shape as BoxShape3D
	if box == null:
		return true
	var t := shape.global_transform
	var half := box.size * 0.5
	# How far the box reaches down from its middle, as it lies.
	var reach := absf(t.basis.x.y) * half.x + absf(t.basis.y.y) * half.y + absf(t.basis.z.y) * half.z
	var exclude: Array[RID] = [body.get_rid()]
	for p: PhysicsBody3D in parts.values():
		exclude.append(p.get_rid())
	var space := torso.get_world_3d().direct_space_state
	for along: float in [0.0, SUPPORT_ALONG, -SUPPORT_ALONG]:
		var from := t * Vector3(0.0, box.size.y * along, 0.0)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (reach + SUPPORT_GAP_M), MASK, exclude)
		if not space.intersect_ray(query).is_empty():
			return true
	return false


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
	for key: String in parts:
		if cut_away.has(key):
			continue  # gone with a cut: held, it has no collider to land on
		var p := parts[key] as RigidBody3D
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
