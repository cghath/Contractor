class_name CharacterModel
extends Node3D
## Procedural voxel soldier (see VoxelArt): rigid body parts on joint pivots, animated in
## code. Legs swing with movement speed and the head follows the look pitch. Arms have
## elbows: with nothing held they swing; when GearRig hands them something (set_held),
## two-bone IK puts the right hand on its grip point and the left on its support point.
## Gear mounts on `torso`, `head`, or `hands_anchor` (which pitches with aim).
##
## Stance comes in as a `pose` (see REST_POSE; SoldierMovement fills it in): the model
## eases towards it, and pose_hitboxes / lay_down snap the body's hitboxes to the same pose
## so shots land where the body is drawn.

## Joint positions in body space (feet at the origin, facing -Z).
const TORSO_PIVOT := Vector3(0, 0.9, 0)
const HEAD_PIVOT := Vector3(0, 0.56, 0)          # relative to torso
const SHOULDER := Vector3(0.25, 0.52, 0)         # relative to torso, mirrored for the left
const HIP := Vector3(0.075, 0.9, 0)              # mirrored for the left
## Held weapons pivot here (torso-local) when aiming up or down: about shoulder height.
const HANDS_ANCHOR := Vector3(0, 0.5, 0)
const UPPER_ARM := 0.32                           # shoulder to elbow
const FOREARM := 0.25                             # elbow to palm centre
## Elbows bend towards these (torso-local, before normalising): out, down and back.
const POLE_RIGHT := Vector3(0.7, -1.0, 0.35)
const MAX_SPEED := 6.5
## Hip joint to sole: legs are one rigid part, so a lower stance splays them.
const LEG_LENGTH := 0.9
## The eyes, torso-local: hips to eye level (the camera follows this point).
const EYE := Vector3(0, 0.75, 0)
## Lowered hips: the front (left) leg reaches forward to the ground; the back (right) leg
## kneels, angled back this fraction as far (its shin sinks into the ground like a knee).
const BACK_LEG := 0.55
## Prone: lifted by half the torso depth, and shifted back so the body lies centred on the
## origin (feet behind, head in front) instead of tipping over the feet like a downed body.
const PRONE_LIFT := 0.12
const PRONE_SIDE_LIFT := 0.08                    # extra lift when rolled onto a side
const PRONE_SHIFT := 1.0
const PRONE_LEG_SPREAD := 0.12
## Downed bodies tip over around the feet onto the chest (lay_down).
const DOWNED_LIFT := 0.12
## How fast the drawn body eases into a new pose (per second).
const POSE_EASE := 8.0

## A standing pose. hip: hips above the feet (lower bends the legs); hip_x, hip_z: hips shifted
## sideways and back; pitch: upper body lean (negative leans forward); roll: upper body tilt
## (positive leans left); prone: lying face down; prone_roll: rolled onto a side while
## prone (positive rolls onto the left side).
const REST_POSE := {"hip": 0.9, "hip_x": 0.0, "hip_z": 0.0, "pitch": 0.0, "roll": 0.0, "prone": false, "prone_roll": 0.0}

enum Hold { NONE, BOTH, RIGHT }

## Colour scheme from VoxelArt.VARIANTS. Set before the node enters the tree.
@export var variant := "multicam"
@export_flags_3d_render var render_layers := 1:
	set(value):
		render_layers = value
		if is_node_ready():
			for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
				mesh.layers = value

## What the owner wants the arms doing. GearRig reads it to decide what goes in the hands.
var hold := Hold.NONE
## Head pitch in radians (positive looks up), set by the owner each frame.
var look_pitch := 0.0
## While true the left hand works the magazine well instead of the support point.
var reloading := false
## Lying face down, head forward (see lay_down). Overrides `pose`.
var downed := false
## The stance to show (keys as in REST_POSE). Set every frame by the body that owns it.
var pose: Dictionary = REST_POSE.duplicate()

var torso: Node3D
var head: Node3D
var hands_anchor: Node3D
var _root: Node3D
var _upper: Array[Node3D] = []    # [right, left]
var _forearm: Array[Node3D] = []  # [right, left]
var _leg_left: Node3D
var _leg_right: Node3D
var _held: Node3D
var _grip := Vector3.ZERO     # right hand, in _held's local space
var _support := Vector3.ZERO  # left hand, in _held's local space
var _last_position: Vector3
var _speed := 0.0
var _phase := 0.0
var _time := 0.0
var _shown: Dictionary = {}   # bone -> Transform3D, easing towards the pose


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	torso = _part("torso", _root, TORSO_PIVOT)
	head = _part("head", torso, HEAD_PIVOT)
	hands_anchor = Node3D.new()
	hands_anchor.position = HANDS_ANCHOR
	torso.add_child(hands_anchor)
	for side in [1.0, -1.0]:
		var upper := _part("upper_arm", torso, SHOULDER * Vector3(side, 1, 1))
		_upper.append(upper)
		_forearm.append(_part("forearm", upper, Vector3(0, -UPPER_ARM, 0)))
	_leg_left = _part("leg", _root, HIP * Vector3(-1, 1, 1))
	_leg_right = _part("leg", _root, HIP)
	_last_position = global_position
	_shown = pose_bones(REST_POSE, false)
	var body := get_parent()
	if body:
		for area in _posable_hitboxes(body):
			_rest_of(area)  # recorded before anything moves them


## Puts a body's model and its hitboxes in or out of the downed pose, so shots hit where
## the body is lying. Hitboxes are the body's direct Area3D children with a "body_part"
## meta; when not downed they follow the model's `pose` (crouch, prone, lean).
static func lay_down(body: Node3D, model: CharacterModel, is_downed: bool) -> void:
	model.downed = is_downed
	model.pose_hitboxes(body)


## Snaps the body's hitboxes to this model's pose (or the downed pose): each follows the
## bone it belongs to (upper body, pelvis, left or right leg), from its rest transform.
func pose_hitboxes(body: Node3D) -> void:
	var deltas := {}
	if not downed:
		var bones := pose_bones(pose, false)
		var rest := rest_bones()
		for key: String in ["torso", "pelvis", "leg_l", "leg_r"]:
			deltas[key] = transform * bones.root * bones[key] * (rest[key] as Transform3D).affine_inverse()
	var lying := Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, DOWNED_LIFT, 0))
	for area in _posable_hitboxes(body):
		var rest_xform := _rest_of(area)
		var target: Transform3D = lying * rest_xform if downed else deltas[_bone_of(area)] * rest_xform
		if not area.transform.is_equal_approx(target):
			area.transform = target


## Model-space transforms for a pose: "root" (whole body), and root-local "torso",
## "pelvis", "leg_l" and "leg_r" (joint pivots).
static func pose_bones(p: Dictionary, is_downed: bool) -> Dictionary:
	if is_downed:
		var rest := rest_bones()
		rest["root"] = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, DOWNED_LIFT, 0))
		return rest
	var hip: float = p.get("hip", HIP.y)
	var hip_x: float = p.get("hip_x", 0.0)
	var hip_z: float = p.get("hip_z", 0.0)
	var root := Transform3D.IDENTITY
	var spread := 0.0
	if p.get("prone", false):
		var roll: float = p.get("prone_roll", 0.0)
		var lying := Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, -PI / 2)
		root = Transform3D(lying, Vector3(0, PRONE_LIFT + PRONE_SIDE_LIFT * absf(sin(roll)), PRONE_SHIFT))
		spread = PRONE_LEG_SPREAD
	var bend := acos(clampf(hip / LEG_LENGTH, 0.0, 1.0))
	var roll_by: float = p.get("roll", 0.0)
	var pitch_by: float = p.get("pitch", 0.0)
	var torso_basis := Basis(Vector3.BACK, roll_by) * Basis(Vector3.RIGHT, pitch_by)
	return {
		"root": root,
		"torso": Transform3D(torso_basis, Vector3(hip_x, hip, hip_z)),
		"pelvis": Transform3D(Basis(), Vector3(hip_x, hip, hip_z)),
		"leg_l": Transform3D(Basis(Vector3.BACK, -spread) * Basis(Vector3.RIGHT, bend), Vector3(hip_x - HIP.x, hip, hip_z)),
		"leg_r": Transform3D(Basis(Vector3.BACK, spread) * Basis(Vector3.RIGHT, -bend * BACK_LEG), Vector3(hip_x + HIP.x, hip, hip_z)),
	}


## The bones standing at rest (root-local, root at the origin).
static func rest_bones() -> Dictionary:
	return {
		"root": Transform3D.IDENTITY,
		"torso": Transform3D(Basis(), TORSO_PIVOT),
		"pelvis": Transform3D(Basis(), TORSO_PIVOT),
		"leg_l": Transform3D(Basis(), HIP * Vector3(-1, 1, 1)),
		"leg_r": Transform3D(Basis(), HIP),
	}


## Where the eyes are for a pose, in body space (the camera goes here).
static func eye_position(p: Dictionary) -> Vector3:
	var bones := pose_bones(p, false)
	return bones.root * bones.torso * EYE


## Hands go to `grip` (right) and `support` (left), given in `node`'s local space.
func set_held(node: Node3D, grip: Vector3, support: Vector3) -> void:
	_held = node
	_grip = grip
	_support = support


func clear_held() -> void:
	_held = null


## Global position of a palm (for tests and tools).
func hand_position(right: bool) -> Vector3:
	return _forearm[0 if right else 1].to_global(Vector3(0, -FOREARM, 0))


## Largest palm-to-target distance in metres while holding something; -1 if nothing is held.
func hand_error() -> float:
	if not is_instance_valid(_held):
		return -1.0
	return maxf(hand_position(true).distance_to(_held.to_global(_grip)),
		hand_position(false).distance_to(_held.to_global(_support)))


func _part(model: String, parent: Node3D, pivot: Vector3) -> Node3D:
	var node := VoxelArt.instance(model, variant, render_layers)
	node.position = pivot
	parent.add_child(node)
	return node


static func _posable_hitboxes(body: Node) -> Array[Area3D]:
	var areas: Array[Area3D] = []
	for child in body.get_children():
		if child is Area3D and child.has_meta(&"body_part"):
			areas.append(child)
	return areas


## A hitbox's transform with the body standing, recorded the first time it is seen.
static func _rest_of(area: Area3D) -> Transform3D:
	if not area.has_meta(&"pose_rest"):
		area.set_meta(&"pose_rest", area.transform)
	return area.get_meta(&"pose_rest")


## Which bone a hitbox follows: by its body part, or for parts this doesn't know, by where
## it sits at rest (above the hips: upper body; below: the leg on its side).
static func _bone_of(area: Area3D) -> String:
	if area.has_meta(&"pose_bone"):
		return area.get_meta(&"pose_bone")
	var part: StringName = area.get_meta(&"body_part", Vitals.TORSO)
	var bone := "torso"
	if part == Vitals.PELVIS:
		bone = "pelvis"
	elif part in [Vitals.THIGH_L, Vitals.SHIN_L]:
		bone = "leg_l"
	elif part in [Vitals.THIGH_R, Vitals.SHIN_R]:
		bone = "leg_r"
	elif not part in [Vitals.HEAD, Vitals.FACE, Vitals.NECK, Vitals.TORSO, Vitals.CHEST, Vitals.ABDOMEN,
			Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]:
		var centre := Vector3.ZERO
		var shapes := 0
		for child in area.get_children():
			if child is CollisionShape3D:
				centre += child.position
				shapes += 1
		centre = _rest_of(area) * (centre / maxf(shapes, 1))
		if centre.y < HIP.y - 0.05:
			bone = "pelvis" if absf(centre.x) < 0.03 else ("leg_l" if centre.x < 0.0 else "leg_r")
	area.set_meta(&"pose_bone", bone)
	return bone


func _process(delta: float) -> void:
	# Speed from position change works the same for local, remote and AI bodies.
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var speed := minf(moved.length() / maxf(delta, 0.0001), MAX_SPEED)
	_speed = lerpf(_speed, speed, minf(delta * 10.0, 1.0))
	_time += delta
	_phase += delta * (2.0 + _speed * 1.6)

	var target := pose_bones(pose, downed)
	var blend := minf(delta * POSE_EASE, 1.0)
	for key: String in target:
		_shown[key] = (_shown[key] as Transform3D).interpolate_with(target[key], blend)
	var prone: bool = pose.get("prone", false)
	var stride := clampf(_speed / 4.0, 0.0, 1.0) * (0.55 + 0.25 * clampf((_speed - 4.0) / 2.5, 0.0, 1.0))
	if downed:
		stride = 0.0
	elif prone:
		stride *= 0.35  # crawling: small leg movements
	var swing := sin(_phase) * stride
	_root.transform = (_shown.root as Transform3D).translated(Vector3(0, absf(sin(_phase)) * 0.03 * stride, 0))
	_leg_left.transform = (_shown.leg_l as Transform3D) * Transform3D(Basis(Vector3.RIGHT, swing), Vector3.ZERO)
	_leg_right.transform = (_shown.leg_r as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -swing), Vector3.ZERO)
	torso.transform = (_shown.torso as Transform3D).translated_local(Vector3(0, sin(_time * 2.0) * 0.003, 0))  # breathing
	# Head and weapon keep facing where the owner looks, whatever the upper body's lean.
	var up := (_shown.root as Transform3D).basis * (_shown.torso as Transform3D).basis * Vector3.UP
	var lean := 0.0 if downed else atan2(up.z, up.y)
	head.rotation.x = clampf(look_pitch, -0.7, 0.7) * 0.8 - lean
	hands_anchor.rotation.x = clampf(look_pitch, -0.8, 0.8) * 0.8 - lean

	if is_instance_valid(_held):
		_reach(0, torso.to_local(_held.to_global(_grip)))
		var support := _support
		if reloading:
			# Hand drops under the receiver and works the magazine.
			support = _grip.lerp(_support, 0.35) + Vector3(0, -0.11 + sin(_time * 9.0) * 0.025, 0)
		_reach(1, torso.to_local(_held.to_global(support)))
	else:
		# Free arms swing opposite the legs; forearms bend more on the forward swing.
		for i in 2:
			var arm_swing := swing * 0.8 * (1.0 if i == 0 else -1.0)
			_upper[i].transform.basis = Basis.from_euler(Vector3(arm_swing, 0, 0.05 * (1.0 if i == 0 else -1.0)))
			_forearm[i].transform.basis = Basis.from_euler(Vector3(0.15 + maxf(arm_swing, 0.0) * 0.6, 0, 0))


## Two-bone IK in torso space: put arm `i`'s palm on `target`.
func _reach(i: int, target: Vector3) -> void:
	var shoulder := _upper[i].position
	var to := target - shoulder
	var dist := clampf(to.length(), 0.05, UPPER_ARM + FOREARM - 0.001)
	var dir := to.normalized()
	# Law of cosines: how far along `dir` the elbow sits, and how far off the line.
	var along := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + dist * dist) / (2.0 * dist)
	var off := sqrt(maxf(UPPER_ARM * UPPER_ARM - along * along, 0.0))
	var pole := POLE_RIGHT * Vector3(1.0 if i == 0 else -1.0, 1, 1)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * along + bend * off
	var hand := shoulder + dir * dist
	var upper_basis := _segment_basis(elbow - shoulder)
	_upper[i].transform.basis = upper_basis
	_forearm[i].transform.basis = upper_basis.inverse() * _segment_basis(hand - elbow)


## Basis whose -Y points along `v` (limbs hang along -Y), with as little twist as possible.
static func _segment_basis(v: Vector3) -> Basis:
	var y := -v.normalized()
	var x := Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	if x.length_squared() < 0.0001:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))
