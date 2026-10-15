class_name Helicopter
extends Vehicle
## An AI-flown helicopter (wave 5b V3): the UH-60 Black Hawk the helicopter supports fly
## (HeliCall). Captain: aircraft are AI-flown only. The pilot seats stand for the crew, which
## the helicopter itself simulates: nobody sits in them, and a crew kill (the "crew" hit zone at
## 0) brings it down like a rotor or engine kill. Players and AI ride in the passenger seats.
##
## Everything else is a Vehicle: seats, cargo, the damage model (7.62x54R and launchers hurt it;
## small arms bounce), fire, wrecks, saving and the clients' smooth snapshot interpolation. The
## flight goes through Vehicle's _drive_step seam on the host:
## - PARKED: no orders. It sits on its landing gear like any parked vehicle (the vehicle range,
##   a saved wreck's neighbour), rotors still.
## - FLYING: the autopilot flies to a point (arriving: slowing down to a hover over it; passing:
##   at speed) or orbits one, contour-flying low over the ground and whatever stands on it ahead
##   (_contour). It steers its velocity (accelerations limited) and tilts into its acceleration
##   the way a rotor's thrust does, nose down to speed up, flaring nose up to stop. Landing, it
##   flies a J-hook (hook_plan): past the LZ on one side, a slowing turn back onto a short final,
##   the flare, and settles.
## - LANDING: straight down over a spot, slowing for the touchdown; LANDED: on the ground,
##   held still (frozen) with the rotors turning, until server_take_off.
## - CRASHING: a rotor, engine or crew kill (or a fire) in the air: no lift, spinning, falling.
##   On impact everyone aboard dies and the cargo is lost (Captain: a support is lost with its
##   passengers and cargo), and it burns into a wreck (Vehicle's fire).
## Gravity is off while it flies under power and on when it's parked or falling.
##
## Every peer: the rotors turn at net_flight's rpm (VehicleArt.spin_rotors). Replicated
## (host -> every peer and late joiners) beside Vehicle's state: net_flight {"mode", "rpm",
## "call" (the support it flies, or "")}.
##
## Numbers marked Proposed are tunable; `pace` speeds every flight number up (tests only).

signal landed
## The fatal hit came (it starts to fall, or it was hit on the ground and burns). Once.
signal went_down(heli: Helicopter)
## It hit the ground falling: everyone aboard is dead, the cargo is gone.
signal crashed(heli: Helicopter)

enum Mode { PARKED, FLYING, LANDING, LANDED, CRASHING, CRASHED }

## Proposed flight numbers: cruise and loiter speeds, the height above the ground it cruises
## at, and the hover height over a landing spot before it goes straight down.
## Captain, 2026-10-14 (riding a UH-60M insertion into wadi_farm): "fly in no higher than
## 10m". It contour-flies CRUISE_AGL_M over the ground (under 10 m with room for the terrain
## following's lag), and OBSTACLE_CLEAR_M over anything taller standing in its way (structures
## and trees with colliders, within ROTOR_REACH_M of its track: the rotor), climbing just enough
## and coming back down. CONTOUR_CLIMB of CLIMB_MS is the climb it plans with for what's ahead,
## so it starts up in time. Proposed.
const CRUISE_KMH := 250.0
const LOITER_KMH := 120.0
const CRUISE_AGL_M := 7.0
const HOVER_AGL_M := 3.0
const OBSTACLE_CLEAR_M := 4.0
const ROTOR_REACH_M := 8.0
const CONTOUR_CLIMB := 0.6
## What stands on the ground is looked for this far up from it (m).
const OBSTACLE_SCAN_M := 60.0
## Taking off: up to this height over the ground before it goes (Proposed).
const LIFT_AGL_M := 10.0
## J-hook landing (Captain, 2026-10-14: "heli should do a j hook style landing"). It flies past
## the LZ on a line HOOK_RADIUS_M * 2 to one side, from HOOK_PASS_M short of it, slows and turns
## back round a HOOK_RADIUS_M half circle (HOOK_TURN_MS2 sideways: about 14 degrees of bank, easy
## on the passengers) onto a HOOK_FINAL_M straight final, flares nose up as it stops over the
## spot and settles. Proposed.
const HOOK_RADIUS_M := 70.0
const HOOK_PASS_M := 160.0
const HOOK_FINAL_M := 40.0
const HOOK_TURN_MS2 := 2.5
const HOOK_ARC_POINTS := 12
## A point of the hook counts as reached within this far (m).
const PATH_REACH_M := 6.0
## Slow (m/s) on the final it turns its nose to the final heading at this rate (rad/s).
const FINAL_YAW_RAD_S := 0.5
## Accelerations (m/s2): along the ground speeding up and slowing (the approach plans its
## stop with DECEL), and up or down.
const ACCEL_MS2 := 3.5
const DECEL_MS2 := 2.2
const VERTICAL_ACCEL_MS2 := 4.0
## Climb and sink rates (m/s): in flight, on the way down to land (above and below 4 m).
const CLIMB_MS := 8.0
const SINK_MS := 6.0
const LAND_SINK_MS := 2.5
const TOUCH_SINK_MS := 0.9
## The approach comes down a slope of this much height per metre to go, until hover height.
const GLIDE := 0.12
## It counts as over a spot within this distance (m) and below this speed (m/s).
const OVER_SPOT_M := 2.0
const OVER_SPOT_MS := 1.5
## Touchdown: its origin (the ground under the gear) this close to the surface (m).
const TOUCH_M := 0.3
## Attitude: tilt at most this much; it reaches its attitude in about ATTITUDE_S; at cruise its
## nose is down DRAG_TILT of a metre per second squared per m/s of speed (drag).
const MAX_TILT_DEG := 24.0
const ATTITUDE_S := 0.45
const MAX_ROTATE_RAD_S := 1.6
const DRAG_TILT := 0.03
## Terrain following: the ground is sampled this many seconds ahead along the way (1.0 gives
## the slope it climbs or sinks with, _contour).
const LOOKAHEAD_S: Array[float] = [0.0, 1.0, 2.0, 3.5, 5.0, 7.0, 10.0]
## Rotors (Proposed): turning rpm, and seconds to spin up or down.
const ROTOR_RPM := 260.0
const SPOOL_S := 5.0
## Falling: the spin of a lost tail rotor (rad/s); an impact this fast (m/s) or a touch of the
## ground is the crash.
const CRASH_SPIN_RAD_S := 2.2
const CRASH_FAST_MS := 4.0
## Hit zones whose loss brings it down (with the hull: Vehicle destroys it at 0).
const FATAL_ZONES: Array[StringName] = [Vehicle.ZONE_ROTOR, Vehicle.ZONE_ENGINE, Vehicle.ZONE_CREW]

## Tests: every speed, acceleration and rate times this (1 in play).
static var pace := 1.0

## Replicated (host -> every peer): see the class notes.
var net_flight: Dictionary = {}

## Host: the support this helicopter flies ("resupply", "transport", "extraction",
## "insertion"), or "" for a parked one. A support helicopter isn't kept in the zone save
## unless it's a wreck (to_save / from_save).
var support := ""
var mode := Mode.PARKED

## Host: exits go even in the air (a support called off at once: tests).
var forced_exits := false

var _target := Vector3.ZERO     # FLYING: where to; LANDING: the spot
var _arrive := true              # FLYING: stop over the target (else pass at speed)
var _orbit := false
var _orbit_radius := 0.0
var _agl := CRUISE_AGL_M
var _speed := CRUISE_KMH / 3.6   # m/s
var _heading := 0.0              # yaw (Vehicle._yaw convention)
var _accel := Vector3.ZERO       # smoothed horizontal acceleration (tilt)
var _rpm := 0.0
var _down_sent := false
var _last_shooter: Node = null
var _spin_sign := 1.0
## Landing: the J-hook's points (x, z; where it joined first, the LZ last), each one's speed
## limit (m/s at pace 1: INF for none), the leg it's on, the final's direction, metres to go.
var _path: Array[Vector2] = []
var _path_v: Array[float] = []
var _path_i := 0
var _final_dir := Vector2.ZERO
var _path_left := 0.0


## A new helicopter of `p_model` (a "helicopter" kind in data/vehicles.json), ready for the tree.
static func make(p_model: String, p_scheme := "", p_faction := &"player", id := "") -> Helicopter:
	var h := Helicopter.new()
	h.setup(p_model, p_scheme, p_faction, id)
	return h


## The yaw of `n`'s nose (radians; 0 faces -z).
static func yaw_of(n: Node3D) -> float:
	var f := -n.global_basis.z
	return atan2(-f.x, -f.z)


## Whether `p_model` is flown by this class (VehicleLayer's spawner makes helicopters with it).
static func flies(p_model: String) -> bool:
	return String(VehicleSpecs.spec(p_model).get("kind", "")) == Vehicle.HELICOPTER


func _add_sync() -> void:
	super._add_sync()
	var flight := SceneReplicationConfig.new()
	flight.add_property(^".:net_flight")
	flight.property_set_replication_mode(^".:net_flight", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	flight.property_set_spawn(^".:net_flight", true)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "FlightSync"
	sync.replication_config = flight
	sync.delta_interval = 0.1
	add_child(sync)


func _ready() -> void:
	super._ready()
	if not multiplayer.is_server():
		return
	damaged.connect(_on_damaged)
	destroyed.connect(_on_destroyed)
	if support != "" and not wrecked:
		queue_free.call_deferred()  # a support in flight isn't saved: the zone save had one (from_save)
		return
	_heading = Helicopter.yaw_of(self)
	_publish_flight()


# --- Queries (every peer) -------------------------------------------------------------------

## The flight mode (every peer: the host's, through net_flight).
func flight_mode() -> Mode:
	return mode if multiplayer.is_server() else int(net_flight.get("mode", Mode.PARKED)) as Mode


func is_landed() -> bool:
	return flight_mode() == Mode.LANDED


## Under power in the air (flying or coming down to land).
func is_flying() -> bool:
	var m := flight_mode()
	return m == Mode.FLYING or m == Mode.LANDING


func is_down() -> bool:
	var m := flight_mode()
	return m == Mode.CRASHING or m == Mode.CRASHED or wrecked


## Off the ground: flying, landing or falling.
func is_airborne() -> bool:
	var m := flight_mode()
	return m == Mode.FLYING or m == Mode.LANDING or m == Mode.CRASHING


## Host: hovering over its FLYING target (an arriving flight got there).
func arrived() -> bool:
	if mode != Mode.FLYING or not _arrive or _orbit:
		return false
	var flat := Vector2(global_position.x - _target.x, global_position.z - _target.z)
	return flat.length() < OVER_SPOT_M * 2.0 and Vector2(linear_velocity.x, linear_velocity.z).length() < OVER_SPOT_MS * 2.0


## Height of its origin (the ground under the gear) above the surface below it (m).
func height_agl() -> float:
	return global_position.y - ground_y(global_position)


## The surface's height under `at` (the world: terrain and structures, not this helicopter).
func ground_y(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var exclude: Array[RID] = [get_rid()]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 2.0, at.z), Vector3(at.x, at.y - 400.0, at.z), 1, exclude))
		if not hit.is_empty():
			return (hit.position as Vector3).y
	return terrain_y(at)


## The terrain's height at `at` without colliders (a zone's heightmap, else a raycast from
## high up, else 0): far from anyone, where structures aren't loaded.
func terrain_y(at: Vector3) -> float:
	var lvl := level()
	if lvl and lvl.has_method(&"ground_height"):
		return float(lvl.call(&"ground_height", at.x, at.z))
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var exclude: Array[RID] = [get_rid()]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 600.0, at.z), Vector3(at.x, -200.0, at.z), 1, exclude))
		if not hit.is_empty():
			return (hit.position as Vector3).y
	return 0.0


## Seconds to fly `metres` at cruise (an ETA for the radio).
static func eta_s(metres: float) -> float:
	return metres / (CRUISE_KMH / 3.6 * pace) + 25.0 / pace


## The highest thing at `at` (x, z) under the rotor: the terrain, or what stands on it there
## and `side` metres either side (a Vector3: off its track), where colliders are loaded.
func obstacle_top(at: Vector3, side := Vector3.ZERO) -> float:
	var ground := terrain_y(at)
	var top := ground
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return top
	var exclude: Array[RID] = [get_rid()]
	var offsets: Array[Vector3] = [Vector3.ZERO]
	if side != Vector3.ZERO:
		offsets.append(side)
		offsets.append(-side)
	for off in offsets:
		var p := at + off
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, ground + OBSTACLE_SCAN_M, p.z), Vector3(p.x, ground - 2.0, p.z), 1, exclude))
		if not hit.is_empty():
			top = maxf(top, (hit.position as Vector3).y)
	return top


## Landing: metres still to fly along its J-hook (0 when not flying one).
func path_left_m() -> float:
	return _path_left if not _path.is_empty() else 0.0


## Landing: the final's direction (x, z; its nose at touchdown), or zero.
func final_dir() -> Vector2:
	return _final_dir


## The J-hook from `from` to `spot` (Captain, 2026-10-14), its final heading along `final_dir`
## (x, z; zero: back toward where it comes from, a hook of about 180 degrees). Returns
## {"points": Array[Vector2] (from first, the spot last), "v": Array[float] (speed limits, m/s
## at pace 1), "final": Vector2}. The pass goes down the side `from` is on; a `from` already
## past the pass's start (close in) joins at the turn.
static func hook_plan(from: Vector3, spot: Vector3, final_dir := Vector2.ZERO) -> Dictionary:
	var l := Vector2(spot.x, spot.z)
	var rel := Vector2(from.x, from.z) - l
	var f := final_dir.normalized() if final_dir.length() > 0.01 else rel.normalized()
	if f.length() < 0.5:
		f = Vector2(0.0, -1.0)
	var perp := Vector2(-f.y, f.x)
	var side := perp if rel.dot(perp) >= 0.0 else -perp
	var fin := l - f * HOOK_FINAL_M
	var centre := fin + side * HOOK_RADIUS_M
	var entry := fin + side * HOOK_RADIUS_M * 2.0
	var start := entry + f * (HOOK_PASS_M + HOOK_FINAL_M)
	var turn_v := sqrt(HOOK_TURN_MS2 * HOOK_RADIUS_M)
	var points: Array[Vector2] = [Vector2(from.x, from.z)]
	var v: Array[float] = [INF]
	if (Vector2(from.x, from.z) - start).dot(-f) < -20.0:  # (not past the pass's start yet)
		points.append(start)
		v.append(INF)
	points.append(entry)
	v.append(turn_v)
	for k in range(1, HOOK_ARC_POINTS):
		var a := PI * float(k) / float(HOOK_ARC_POINTS)
		points.append(centre + side * HOOK_RADIUS_M * cos(a) - f * HOOK_RADIUS_M * sin(a))
		v.append(turn_v)
	points.append(fin)
	v.append(turn_v)
	points.append(l)
	v.append(0.0)
	return {"points": points, "v": v, "final": f}


## Seconds to fly a hook_plan `plan` (at pace 1), starting at `v0` m/s: accelerating and
## slowing as the autopilot does, plus the settle onto the spot. Divided by pace.
static func plan_time_s(plan: Dictionary, v0 := CRUISE_KMH / 3.6) -> float:
	var points: Array = plan.points
	var lim: Array = plan.v
	var cruise := CRUISE_KMH / 3.6
	var xs: Array[float] = [0.0]
	var caps: Array[float] = [minf(cruise, v0)]
	var d := 0.0
	for i in points.size() - 1:
		var seg := (points[i] as Vector2).distance_to(points[i + 1])
		var cap := minf(cruise, maxf(float(lim[i]), float(lim[i + 1])))
		var n := maxi(1, ceili(seg / 5.0))
		for k in n:
			d += seg / n
			xs.append(d)
			caps.append(cap if k < n - 1 else minf(cap, float(lim[i + 1])))
	var v := caps.duplicate()
	v[0] = minf(v0, cruise)
	for k in range(1, v.size()):
		v[k] = minf(v[k], sqrt(v[k - 1] * v[k - 1] + 2.0 * ACCEL_MS2 * (xs[k] - xs[k - 1])))
	for k in range(v.size() - 2, -1, -1):
		v[k] = minf(v[k], sqrt(v[k + 1] * v[k + 1] + 2.0 * DECEL_MS2 * 0.95 * (xs[k + 1] - xs[k])))
	var t := 0.0
	for k in range(1, v.size()):
		t += (xs[k] - xs[k - 1]) / maxf((v[k] + v[k - 1]) * 0.5, 1.0)
	return (t + HOVER_AGL_M / TOUCH_SINK_MS + 3.0) / pace


## Seconds from `from` to on the ground at `spot` by a J-hook (an ETA for the radio).
static func eta_land_s(from: Vector3, spot: Vector3, final_dir := Vector2.ZERO) -> float:
	return plan_time_s(hook_plan(from, spot, final_dir))


## Host: seconds until it's down on the J-hook it flies (eta_land_s when it flies none).
func landing_eta_s() -> float:
	if _path.is_empty():
		return Helicopter.eta_land_s(global_position, _target)
	var rest: Array[Vector2] = [Vector2(global_position.x, global_position.z)]
	var lim: Array[float] = [INF]
	for k in range(_path_i + 1, _path.size()):
		rest.append(_path[k])
		lim.append(_path_v[k])
	return Helicopter.plan_time_s({"points": rest, "v": lim}, Vector2(linear_velocity.x, linear_velocity.z).length() / pace)


# --- Orders (host) ----------------------------------------------------------------------------

## Host: in the air where it is (a support arriving: rotors up to speed), moving `speed_kmh`
## along its nose.
func server_start_airborne(speed_kmh := CRUISE_KMH * 0.5) -> void:
	freeze = false
	gravity_scale = 0.0
	_rpm = ROTOR_RPM
	_heading = Helicopter.yaw_of(self)
	linear_velocity = -global_basis.z * speed_kmh / 3.6 * pace
	mode = Mode.FLYING
	_target = global_position
	_publish_flight()


## Host: fly to `point` (x, z) `agl` metres above the ground on the way. `arrive`: slow down
## and hover over it (arrived()); else pass over it at speed.
func server_fly_to(point: Vector3, agl := CRUISE_AGL_M, speed_kmh := CRUISE_KMH, arrive := true) -> void:
	if is_down():
		return
	_lift_off_if_landed()
	_path.clear()
	_target = point
	_agl = agl
	_speed = speed_kmh / 3.6
	_arrive = arrive
	_orbit = false
	mode = Mode.FLYING
	_publish_flight()


## Host: circle `centre` at `radius` metres, `agl` metres up, at `speed_kmh` (a loiter).
func server_orbit(centre: Vector3, radius: float, agl := CRUISE_AGL_M, speed_kmh := LOITER_KMH) -> void:
	if is_down():
		return
	_lift_off_if_landed()
	_path.clear()
	_target = centre
	_orbit_radius = maxf(radius, 50.0)
	_agl = agl
	_speed = speed_kmh / 3.6
	_arrive = false
	_orbit = true
	mode = Mode.FLYING
	_publish_flight()


## Host: land at `spot` (on the ground) by a J-hook (hook_plan): low past it, the hooking turn,
## the final, the flare, a hover and straight down, touch down (landed). Its nose at touchdown
## faces `heading` (radians) if given; else, sent to about the same spot while landing (an LZ
## recheck), it keeps the final it flies; else it hooks back toward where it comes from.
func server_land_at(spot: Vector3, heading := NAN) -> void:
	if is_down():
		return
	var replan := has_meta(&"landing") and not _path.is_empty() and Vector2(spot.x - _target.x, spot.z - _target.z).length() < HOOK_RADIUS_M * 2.0
	_lift_off_if_landed()
	var f := Vector2.ZERO
	if not is_nan(heading):
		f = Vector2(-sin(heading), -cos(heading))
	elif replan:
		f = _final_dir
	var plan := Helicopter.hook_plan(global_position, spot, f)
	_path = plan.points
	_path_v = plan.v
	_final_dir = plan.final
	_path_i = 0
	if replan:  # already on its way round: join where the hook lies ahead, not back at its start
		var vel := Vector2(linear_velocity.x, linear_velocity.z)
		var here := _path[0]
		var k := 1
		while vel.length() > 2.0 and k < _path.size() - 1 and (_path[k] - here).dot(vel) <= 0.0:
			k += 1
		for i in k - 1:
			_path.remove_at(1)
			_path_v.remove_at(1)
	_path_left = 0.0
	for i in _path.size() - 1:
		_path_left += _path[i].distance_to(_path[i + 1])
	_target = spot
	_agl = CRUISE_AGL_M
	_speed = CRUISE_KMH / 3.6
	_arrive = true
	_orbit = false
	mode = Mode.FLYING
	set_meta(&"landing", true)
	_publish_flight()


## Host: off the ground and up to hover height over where it is.
func server_take_off() -> void:
	if mode != Mode.LANDED and mode != Mode.PARKED:
		return
	_lift_off_if_landed()
	_path.clear()
	_target = global_position
	_agl = LIFT_AGL_M
	_arrive = true
	_orbit = false
	mode = Mode.FLYING
	_publish_flight()


## Host: brings it down where it flies (a test, or a crew that can't go on).
func server_shoot_down(shooter: Node = null) -> void:
	_last_shooter = shooter
	_go_down()


func _lift_off_if_landed() -> void:
	remove_meta(&"landing")
	if freeze and not wrecked:
		freeze = false
		gravity_scale = 0.0
		sleeping = false
	if mode == Mode.PARKED or mode == Mode.LANDED:
		gravity_scale = 0.0
		linear_velocity = Vector3.ZERO
		_heading = Helicopter.yaw_of(self)


# --- Seats (host) -------------------------------------------------------------------------------

## The pilot seats are the helicopter's own crew (simulated): nobody takes them.
func server_enter(soldier: Node, index := -1) -> bool:
	if index < 0:
		index = _first_free_passenger()
	if seat_kind(index) == Vehicle.PILOT:
		return false
	return super.server_enter(soldier, index)


## Nobody conscious gets out in the air (they'd be put on the ground below); the dead and
## a support's own unloading on the ground go as Vehicle does.
func server_exit(soldier: Node) -> void:
	var s := soldier as Soldier
	if s and s.vitals.is_up() and is_airborne() and height_agl() > 2.0 and not wrecked and not forced_exits:
		if not s.is_ai():
			_tell(s, "Not while we're flying")
		return
	super.server_exit(soldier)


## Bodies ahead only matter on the ground (a parked one being pushed); in the air there's nothing.
func _wake_bodies_ahead() -> void:
	if mode == Mode.PARKED:
		super._wake_bodies_ahead()


# --- Flight (host, Vehicle's _drive_step seam) --------------------------------------------------

func _drive_step(delta: float) -> void:
	match mode:
		Mode.PARKED:
			gravity_scale = 1.0
			super._drive_step(delta)
		Mode.FLYING:
			_fly(delta)
		Mode.LANDING:
			_land(delta)
		Mode.CRASHING:
			_fall(delta)
		Mode.CRASHED:
			gravity_scale = 1.0


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_spool(delta)
	super._physics_process(delta)


## Nobody sits in the pilot seats: the engines run while the rotors turn (Sfx's engine sound).
func engine_running() -> bool:
	return (_rpm if multiplayer.is_server() else float(net_flight.get("rpm", 0.0))) > 1.0


func _process(delta: float) -> void:
	super._process(delta)
	var rpm := _rpm if multiplayer.is_server() else float(net_flight.get("rpm", 0.0))
	if rpm > 1.0 and hull and is_instance_valid(hull.art):
		VehicleArt.spin_rotors(hull.art, delta, rpm)


func _spool(delta: float) -> void:
	var want := ROTOR_RPM if mode in [Mode.FLYING, Mode.LANDING, Mode.LANDED] and zone_health(Vehicle.ZONE_ROTOR) > 0.0 else 0.0
	if mode == Mode.CRASHING and zone_health(Vehicle.ZONE_ROTOR) > 0.0:
		want = ROTOR_RPM * 0.6
	_rpm = move_toward(_rpm, want, ROTOR_RPM / SPOOL_S * delta)
	if absf(_rpm - float(net_flight.get("rpm", 0.0))) >= 10.0 or (want == 0.0 and _rpm == 0.0 and float(net_flight.get("rpm", 0.0)) != 0.0):
		_publish_flight()


func _fly(delta: float) -> void:
	gravity_scale = 0.0
	if has_meta(&"landing") and _path.size() >= 2:
		_fly_hook(delta)
		return
	var pos := global_position
	var target := _target
	var cruise := _speed * pace
	if _orbit:
		var from := Vector2(pos.x - _target.x, pos.z - _target.z)
		var ang := atan2(from.y, from.x) + 0.35 * _spin_sign
		target = _target + Vector3(cos(ang), 0.0, sin(ang)) * _orbit_radius
	var to := Vector2(target.x - pos.x, target.z - pos.z)
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector2.ZERO
	var speed := cruise
	if _arrive and not _orbit:
		speed = minf(cruise, sqrt(2.0 * DECEL_MS2 * pace * pace * maxf(dist - 0.5, 0.0)) * 0.95)
		if dist < OVER_SPOT_M * 3.0:
			speed = minf(speed, dist * 0.8 * pace)
	var v_h := Vector3(dir.x, 0.0, dir.y) * speed
	# Height: contour flight over what's below and ahead (Captain, 2026-10-14: no higher than 10 m).
	var vel_h := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var contour := _contour(pos, vel_h, _agl)
	_steer(Vector3(v_h.x, _climb_to(contour.x, contour.y, pos.y), v_h.z), delta)
	if vel_h.length() > 8.0 * pace:
		_heading = atan2(-vel_h.x, -vel_h.z)
	elif _orbit and dist > 1.0:
		_heading = atan2(-dir.x, -dir.y)
	_attitude(Vector3.UP, delta)
	if has_meta(&"landing") and arrived():
		mode = Mode.LANDING
		_publish_flight()


## Contour flight: the height (y) to hold at `pos` flying `vel_h` (m/s, flat), `agl` over the
## ground and OBSTACLE_CLEAR_M over what stands on it, starting up early enough for what's
## ahead at the climb it plans with; and how fast that height changes under it (m/s: x the
## height, y the rate).
func _contour(pos: Vector3, vel_h: Vector3, agl: float) -> Vector2:
	var side := Vector3(-vel_h.z, 0.0, vel_h.x).normalized() * ROTOR_REACH_M if vel_h.length() > 0.5 else global_basis.x * ROTOR_REACH_M
	var climb := CLIMB_MS * CONTOUR_CLIMB * pace
	var want := -INF
	var now := 0.0
	var next := 0.0
	for t: float in LOOKAHEAD_S:
		var at := pos + vel_h * t
		var floor_y := maxf(terrain_y(at) + agl, obstacle_top(at, side) + OBSTACLE_CLEAR_M)
		if t == 0.0:
			now = floor_y
		elif t == 1.0:
			next = floor_y
		want = maxf(want, floor_y - climb * t)
	return Vector2(want, next - now)


## The climb (m/s, + up) that takes it to `want_y` from `y`, following the ground's `rate`.
func _climb_to(want_y: float, rate: float, y: float) -> float:
	var lim_up := CLIMB_MS * pace
	var lim_down := SINK_MS * pace
	return clampf((want_y - y) * 0.8 * pace + clampf(rate, -lim_down, lim_up), -lim_down, lim_up)


## Landing: flies the J-hook (_path): toward a point a little way along it from where it is,
## at the speed every point ahead allows (slowing for the turn, stopping over the spot), low
## over the ground until the final, then down the glide slope to hover height over the spot.
func _fly_hook(delta: float) -> void:
	var pos := global_position
	var here := Vector2(pos.x, pos.z)
	while _path_i < _path.size() - 2:
		var a := _path[_path_i]
		var ab := _path[_path_i + 1] - a
		if (here - a).dot(ab) / maxf(ab.length_squared(), 0.01) >= 1.0 or here.distance_to(_path[_path_i + 1]) < PATH_REACH_M:
			_path_i += 1
		else:
			break
	var a0 := _path[_path_i]
	var seg := _path[_path_i + 1] - a0
	var on := a0 + seg * clampf((here - a0).dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
	var vel_h := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var speed_now := vel_h.length() / pace
	# The point it heads for: this far along the hook from where it is.
	var look := clampf(speed_now * 1.2, 10.0, 80.0)
	var carrot := on
	var left := look
	var from := on
	for k in range(_path_i + 1, _path.size()):
		var d := from.distance_to(_path[k])
		if d >= left:
			carrot = from + (_path[k] - from) / maxf(d, 0.001) * left
			left = 0.0
			break
		left -= d
		from = _path[k]
		carrot = from
	# Speed: cruise, the leg's own, and what lets it slow to each point's limit ahead.
	var limit := minf(_speed, maxf(_path_v[_path_i], _path_v[_path_i + 1]))
	var dist := on.distance_to(_path[_path_i + 1])
	for k in range(_path_i + 1, _path.size()):
		if k > _path_i + 1:
			dist += _path[k - 1].distance_to(_path[k])
		limit = minf(limit, sqrt(_path_v[k] * _path_v[k] + 2.0 * DECEL_MS2 * 0.95 * dist))
	_path_left = dist + here.distance_to(on)
	var end := _path[-1]
	var dir := (carrot - here).normalized() if carrot.distance_to(here) > 0.01 else Vector2.ZERO
	if _path_i >= _path.size() - 2 and here.distance_to(end) < OVER_SPOT_M * 3.0:
		dir = (end - here).normalized() if here.distance_to(end) > 0.01 else Vector2.ZERO
		limit = minf(limit, here.distance_to(end) * 0.8)
	var v_h := Vector3(dir.x, 0.0, dir.y) * limit * pace
	# Height: contour flight; on the final, down the glide slope to hover height over the spot.
	var glide := _target.y + clampf(_path_left * GLIDE, HOVER_AGL_M, maxf(_agl, HOVER_AGL_M))
	var want_y := glide
	var rate := 0.0
	if _path_left > HOOK_FINAL_M * 1.5:
		var contour := _contour(pos, vel_h, _agl)
		want_y = maxf(glide, contour.x)
		rate = contour.y
	_steer(Vector3(v_h.x, _climb_to(want_y, rate, pos.y), v_h.z), delta)
	# Nose along the way it goes; slow on the final, round to the final's heading (no snap).
	if vel_h.length() > 4.0 * pace:
		_heading = atan2(-vel_h.x, -vel_h.z)
	else:
		_heading = rotate_toward(_heading, atan2(-_final_dir.x, -_final_dir.y), FINAL_YAW_RAD_S * pace * delta)
	_attitude(Vector3.UP, delta)
	if arrived():
		mode = Mode.LANDING
		_publish_flight()


func _land(delta: float) -> void:
	gravity_scale = 0.0
	var pos := global_position
	var to := Vector3(_target.x - pos.x, 0.0, _target.z - pos.z)
	var v_h := (to * 0.8 * pace).limit_length(3.0 * pace)
	var agl := pos.y - ground_y(pos)
	var sink := (LAND_SINK_MS if agl > 4.0 else TOUCH_SINK_MS) * pace
	_steer(Vector3(v_h.x, -sink, v_h.z), delta)
	_attitude(Vector3.UP, delta)
	if agl <= TOUCH_M:
		_touch_down()


## On the ground: level on it (its normal), held still, rotors turning.
func _touch_down() -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var pos := global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 3.0, 1, exclude))
	var normal: Vector3 = hit.normal if not hit.is_empty() else Vector3.UP
	var ground: Vector3 = hit.position if not hit.is_empty() else pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(_basis_for(normal, Vector3.ZERO), ground)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	mode = Mode.LANDED
	remove_meta(&"landing")
	_path.clear()
	_publish_flight()
	landed.emit()


func _fall(delta: float) -> void:
	gravity_scale = 1.0
	angular_velocity = angular_velocity.lerp(Vector3.UP * CRASH_SPIN_RAD_S * _spin_sign + global_basis.x * 0.3, minf(delta * 2.0, 1.0))
	if height_agl() < 1.2 or (get_contact_count() > 0 and linear_velocity.length() < CRASH_FAST_MS * 3.0):
		_crash()


## The velocity heads for `desired`, accelerations limited; the tilt follows what it took.
func _steer(desired: Vector3, delta: float) -> void:
	var dv := desired - linear_velocity
	var p2 := pace * pace  # speeds go with pace, accelerations with its square
	var dv_h := Vector3(dv.x, 0.0, dv.z).limit_length(ACCEL_MS2 * p2 * delta)
	var dv_y := clampf(dv.y, -VERTICAL_ACCEL_MS2 * p2 * delta, VERTICAL_ACCEL_MS2 * p2 * delta)
	linear_velocity += dv_h + Vector3(0.0, dv_y, 0.0)
	_accel = _accel.lerp(dv_h / maxf(delta, 0.001) / p2, minf(delta * 4.0 * pace, 1.0))


## Turns toward the attitude the rotor's thrust gives: tilted into the acceleration (and the
## drag at speed), nose along the heading.
func _attitude(ground_up: Vector3, _delta: float) -> void:
	var vel_h := Vector3(linear_velocity.x, 0.0, linear_velocity.z) / pace
	var tilt := _accel + vel_h * DRAG_TILT
	var target := _basis_for(ground_up, tilt)
	var dq := target.get_rotation_quaternion() * global_basis.get_rotation_quaternion().inverse()
	if dq.w < 0.0:
		dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
	var angle := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
	var axis := Vector3(dq.x, dq.y, dq.z)
	if axis.length() < 0.00001 or angle < 0.0001:
		angular_velocity = Vector3.ZERO
		return
	angular_velocity = (axis.normalized() * angle / ATTITUDE_S).limit_length(MAX_ROTATE_RAD_S)


## Up along `up` tilted by acceleration `accel` (m/s2, horizontal; at most MAX_TILT_DEG), nose
## along the heading.
func _basis_for(up: Vector3, accel: Vector3) -> Basis:
	var g := 9.8
	var thrust := (up * g + accel)
	var max_h := g * tan(deg_to_rad(MAX_TILT_DEG))
	var h := Vector3(thrust.x, 0.0, thrust.z)
	if h.length() > max_h and up.is_equal_approx(Vector3.UP):
		h = h.normalized() * max_h
		thrust = Vector3(h.x, thrust.y, h.z)
	var y := thrust.normalized()
	var f := Vector3(-sin(_heading), 0.0, -cos(_heading))
	var z := -(f - y * f.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z).orthonormalized()


# --- Going down (host) ---------------------------------------------------------------------------

func _on_damaged(_zone: StringName, hit: Dictionary) -> void:
	var shooter: Variant = hit.get("shooter")
	if is_instance_valid(shooter):
		_last_shooter = shooter
	if is_down():
		return
	for z in FATAL_ZONES:
		if zone_health(z) <= 0.0:
			_go_down()
			return


## Vehicle's fire (a destroyed hull, a fuel fire): in the air it falls.
func _on_destroyed(_v: Vehicle) -> void:
	if is_airborne() and mode != Mode.CRASHING:
		_go_down()
	elif not _down_sent:
		_down_sent = true
		went_down.emit(self)


func _go_down() -> void:
	if mode == Mode.CRASHING or mode == Mode.CRASHED or wrecked:
		return
	if mode == Mode.LANDED or mode == Mode.PARKED or height_agl() < 1.5:
		mode = Mode.CRASHED  # hit on the ground: it burns where it stands (Vehicle's fire)
		server_start_fire()
	else:
		freeze = false
		mode = Mode.CRASHING
		_spin_sign = -1.0 if randf() < 0.5 else 1.0
	_publish_flight()
	if not _down_sent:
		_down_sent = true
		went_down.emit(self)


## Hit the ground falling: everyone aboard is dead, the cargo with them, and it burns.
func _crash() -> void:
	mode = Mode.CRASHED
	gravity_scale = 1.0
	angular_velocity *= 0.2
	for s: Soldier in occupants():
		if not s.vitals.is_dead():
			Harm.note_hit(s, _last_shooter if is_instance_valid(_last_shooter) else null)
			s.vitals.server_kill()
	if cargo_hold:
		cargo_hold.clear_all()
	for z in Vehicle.ZONES:
		_zones[z] = minf(float(_zones[z]), 0.1)
	server_start_fire()
	_publish_flight()
	_publish_state(true)
	crashed.emit(self)


# --- Replication and saving ----------------------------------------------------------------------

func _publish_flight() -> void:
	if not multiplayer.is_server():
		return
	net_flight = {"mode": int(mode), "rpm": snappedf(_rpm, 1.0), "call": support}


## Vehicle's save, plus the support it flies (a support in flight isn't kept: _ready).
func to_save() -> Dictionary:
	var out := super.to_save()
	out["support"] = support
	return out


func from_save(data: Dictionary) -> void:
	super.from_save(data)
	support = String(data.get("support", ""))
	if wrecked:
		mode = Mode.CRASHED


## One line for the state dumps: mode, height, speed, what it flies to.
func describe() -> String:
	var p := global_position
	return "%s %s at (%.0f, %.0f, %.0f), %.0f m up, %.0f km/h, to (%.0f, %.0f), rotor %d%% engine %d%% hull %d%%" % [
		display_name(), Mode.keys()[flight_mode()], p.x, p.y, p.z, height_agl() if is_inside_tree() else 0.0,
		linear_velocity.length() * 3.6 if multiplayer.is_server() else absf(forward_speed()) * 3.6, _target.x, _target.z,
		roundi(zone_health(Vehicle.ZONE_ROTOR) * 100.0), roundi(zone_health(Vehicle.ZONE_ENGINE) * 100.0), roundi(zone_health(Vehicle.ZONE_HULL) * 100.0)]
