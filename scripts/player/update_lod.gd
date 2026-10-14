class_name UpdateLod
extends RefCounted
## Update level of detail (frame rate, 2026-10-14: a group night's host draws dozens of bodies,
## and each worked out its pose, arms, gear and hitboxes every frame wherever it was). A body's
## per-frame work (CharacterModel._process, Soldier._process, GearRig._process) runs every frame
## within NEAR_M of the camera, every 2nd frame out to MID_M, and every MAX_EVERY-th beyond, or
## when the body is off screen (past ALWAYS_M), or lies still as a settled ragdoll. The frames
## between add their time to the next one's delta. Bodies start at a random frame of the cycle,
## so they spread over the frames. The body itself (its node, its capsule, its hitboxes' parent)
## moves every frame regardless: only its limbs' pose lags, by a few hundredths of a second,
## where it's too small or far away to see.
## Off with no camera (a headless host, every suite) or when `on` is false: every frame.
##   var _lod := UpdateLod.new()
##   func _process(delta):
##       delta = _lod.tick(self, delta)
##       if delta < 0.0: return

const NEAR_M := 25.0
const MID_M := 60.0
const ALWAYS_M := 8.0
const MAX_EVERY := 4
static var on := DisplayServer.get_name() != "headless"

var _skip := -1          # frames left to skip (-1: not started yet)
var _skipped_s := 0.0    # the time those frames took


## How often (in frames) the body at `at` is worth updating, seen through `viewport`'s camera:
## 1 near it or with no camera, 2 at middle range, MAX_EVERY far away or off screen.
static func every(at: Vector3, viewport: Viewport) -> int:
	if not on or viewport == null:
		return 1
	var cam := viewport.get_camera_3d()
	if cam == null:
		return 1
	var d2 := cam.global_position.distance_squared_to(at)
	if d2 < ALWAYS_M * ALWAYS_M:
		return 1
	if not cam.is_position_in_frustum(at + Vector3.UP):
		return MAX_EVERY
	if d2 < NEAR_M * NEAR_M:
		return 1
	return 2 if d2 < MID_M * MID_M else MAX_EVERY


## This frame for `node`: -1 to skip it, else the delta to use (this frame's and the skipped
## ones'). `still`: nothing about the body is changing (a settled ragdoll), MAX_EVERY whatever
## the distance.
func tick(node: Node3D, delta: float, still := false) -> float:
	if not on:
		return delta
	if _skip < 0:
		_skip = randi() % MAX_EVERY  # spread out
	if _skip > 0:
		_skip -= 1
		_skipped_s += delta
		return -1.0
	_skip = (MAX_EVERY if still else every(node.global_position, node.get_viewport())) - 1
	var out := delta + _skipped_s
	_skipped_s = 0.0
	return out
