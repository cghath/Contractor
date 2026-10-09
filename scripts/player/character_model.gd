class_name CharacterModel
extends Node3D
## Procedural voxel soldier (see VoxelArt): rigid body parts on joint pivots, animated in
## code. Legs swing with movement speed and the head follows the look pitch. Arms have
## elbows: with nothing held they swing; when GearRig hands them something (set_held),
## two-bone IK puts the right hand on its grip point and the left on its support point.
## Gear mounts on `torso`, `head`, or `hands_anchor` (which pitches with aim).

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


func _process(delta: float) -> void:
	# Speed from position change works the same for local, remote and AI bodies.
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var speed := minf(moved.length() / maxf(delta, 0.0001), MAX_SPEED)
	_speed = lerpf(_speed, speed, minf(delta * 10.0, 1.0))
	_time += delta
	_phase += delta * (2.0 + _speed * 1.6)

	var stride := clampf(_speed / 4.0, 0.0, 1.0) * (0.55 + 0.25 * clampf((_speed - 4.0) / 2.5, 0.0, 1.0))
	var swing := sin(_phase) * stride
	_leg_left.rotation.x = swing
	_leg_right.rotation.x = -swing
	_root.position.y = absf(sin(_phase)) * 0.03 * stride
	torso.position.y = TORSO_PIVOT.y + sin(_time * 2.0) * 0.003  # breathing
	head.rotation.x = clampf(look_pitch, -0.7, 0.7) * 0.8
	hands_anchor.rotation.x = clampf(look_pitch, -0.8, 0.8) * 0.8

	if is_instance_valid(_held):
		_reach(0, torso.to_local(_held.to_global(_grip)))
		_reach(1, torso.to_local(_held.to_global(_support)))
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
