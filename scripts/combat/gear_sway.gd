class_name GearSway
extends RefCounted
## Secondary motion for worn gear (Captain, queue 10: semi-realistic movement of armour and
## bags, visual springs). A damped spring in the torso's frame: the torso's acceleration (and
## its turning, for gear that hangs `lever` m behind the spine) pushes the gear the other way,
## the spring brings it back. Looks only: plates and hit shapes never move.
##
##   x'' = -k x - c x' - a_torso        k = (2 pi freq)^2, c = 2 damping sqrt(k)
##
## offset() is how far the gear has swung (torso-local metres, clamped to `reach`); turn()
## is the same as a swing about its top: pitch (forward/back) and roll (side to side).

## A jump of the torso further than this in one frame (m) is a teleport (spawn, ragdoll,
## vehicle): the gear settles where it is instead of being flung.
const TELEPORT_M := 2.0
## The torso's acceleration is capped at this (m/s^2): a dead stop from a run in one frame.
const ACCEL_MAX := 40.0
## How fast the torso's measured acceleration is smoothed (1/s): frame-to-frame noise in the
## animation would shake the gear otherwise.
const ACCEL_SMOOTH := 20.0
## Turning is capped at this (rad/s^2): a mouse flick turns the body in a frame or two, and
## would slam the pack to its reach every time.
const TURN_ACCEL_MAX := 20.0

var freq := 2.4      # Hz: a loaded pack sways slowly, pouches flap faster
var damping := 0.35  # of critical: under 1, it overshoots once or twice and settles
var reach := 0.04    # m: the most it swings
var gain := 1.0      # how much of the torso's acceleration it feels
var lever := 0.0     # m behind the spine: turning swings it sideways
var hang := 0.3      # m from where it hangs to its middle: offset -> angle

var _x := Vector3.ZERO
var _v := Vector3.ZERO
var _accel := Vector3.ZERO
var _last_pos := Vector3.INF
var _last_vel := Vector3.ZERO
var _last_yaw := 0.0
var _last_spin := 0.0


static func make(p_freq: float, p_damping: float, p_reach: float, p_gain := 1.0, p_lever := 0.0, p_hang := 0.3) -> GearSway:
	var s := GearSway.new()
	s.freq = p_freq
	s.damping = p_damping
	s.reach = p_reach
	s.gain = p_gain
	s.lever = p_lever
	s.hang = p_hang
	return s


## Follows the torso at global transform `torso` over `delta` seconds.
func follow(torso: Transform3D, delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := torso.origin
	var yaw := torso.basis.get_euler().y
	if _last_pos == Vector3.INF:
		_last_pos = pos
		_last_yaw = yaw
		return
	var jumped := pos.distance_to(_last_pos) > TELEPORT_M
	var vel := (pos - _last_pos) / delta
	var spin := wrapf(yaw - _last_yaw, -PI, PI) / delta
	var acc := ((vel - _last_vel) / delta).limit_length(ACCEL_MAX)
	_last_pos = pos
	_last_yaw = yaw
	if jumped:
		_last_vel = Vector3.ZERO
		_last_spin = 0.0
		_accel = Vector3.ZERO
		return
	var turn_acc := clampf((spin - _last_spin) / delta, -TURN_ACCEL_MAX, TURN_ACCEL_MAX)
	_last_vel = vel
	_last_spin = spin
	# In the torso's frame; turning swings what hangs behind the spine out to the side.
	var local := torso.basis.inverse() * acc + Vector3(-turn_acc * lever, 0, 0)
	_accel = _accel.lerp(local, clampf(ACCEL_SMOOTH * delta, 0.0, 1.0))
	step(_accel, delta)


## One step of the spring under torso-local acceleration `accel` (m/s^2).
func step(accel: Vector3, delta: float) -> void:
	var k := pow(TAU * freq, 2.0)
	var c := 2.0 * damping * sqrt(k)
	# Small steps keep the spring stable at low frame rates.
	var n := maxi(1, ceili(delta / 0.008))
	var h := delta / n
	for i in n:
		var a := -k * _x - c * _v - accel * gain
		_v += a * h
		_x += _v * h
		if _x.length() > reach:
			_x = _x.limit_length(reach)
			_v *= 0.5


func offset() -> Vector3:
	return _x


## The swing as a rotation about where the gear hangs: back/forward is pitch about x, side to
## side is roll about z (the bottom moves out the way the offset says).
func turn() -> Basis:
	var pitch := atan2(-_x.z, hang)
	var roll := atan2(_x.x, hang)
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)


func reset() -> void:
	_x = Vector3.ZERO
	_v = Vector3.ZERO
	_accel = Vector3.ZERO
	_last_pos = Vector3.INF
