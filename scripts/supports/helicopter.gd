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
##   at speed) or orbits one, at a height above the ground that follows the terrain ahead. It
##   steers its velocity (accelerations limited) and tilts into its acceleration the way a
##   rotor's thrust does, nose down to speed up, flaring nose up to stop.
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
## at (Captain's range for us: 60 to 150 m), the lowest it lets the terrain ahead bring it on
## the way, and the hover height over a landing spot before it goes straight down.
const CRUISE_KMH := 250.0
const LOITER_KMH := 120.0
const CRUISE_AGL_M := 90.0
const MIN_AGL_M := 30.0
const HOVER_AGL_M := 12.0
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
## Within this far of the landing spot (m) the terrain ahead no longer holds it up.
const FINAL_M := 220.0
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
## Terrain following: the ground is sampled this many seconds ahead along the way.
const LOOKAHEAD_S: Array[float] = [0.0, 2.0, 4.0, 7.0, 10.0]
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


# --- Orders (host) ----------------------------------------------------------------------------

## Host: in the air at `xform` (a support arriving: rotors up to speed), moving `speed_kmh`
## along its nose.
func server_start_airborne(speed_kmh := CRUISE_KMH) -> void:
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
	_target = centre
	_orbit_radius = maxf(radius, 50.0)
	_agl = agl
	_speed = speed_kmh / 3.6
	_arrive = false
	_orbit = true
	mode = Mode.FLYING
	_publish_flight()


## Host: land at `spot` (on the ground): approach it, hover, go straight down, touch down
## (landed). Facing `heading` (radians) if given, else the way it comes in.
func server_land_at(spot: Vector3, heading := NAN) -> void:
	if is_down():
		return
	_lift_off_if_landed()
	_target = spot
	_agl = HOVER_AGL_M
	_speed = CRUISE_KMH / 3.6
	_arrive = true
	_orbit = false
	if not is_nan(heading):
		_heading = heading
	mode = Mode.FLYING
	set_meta(&"landing", true)
	_publish_flight()


## Host: off the ground and up to hover height over where it is.
func server_take_off() -> void:
	if mode != Mode.LANDED and mode != Mode.PARKED:
		return
	_lift_off_if_landed()
	_target = global_position
	_agl = HOVER_AGL_M * 1.5
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
	# Height: over the terrain ahead on the way; down the glide slope to the spot when arriving.
	var ahead := -INF
	var vel_h := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	for t: float in LOOKAHEAD_S:
		ahead = maxf(ahead, terrain_y(pos + vel_h * t))
	var want_y := ahead + _agl
	if _arrive and not _orbit:
		var spot_y := terrain_y(_target) if not has_meta(&"landing") else _target.y
		var glide := spot_y + clampf(dist * GLIDE, HOVER_AGL_M, maxf(_agl, HOVER_AGL_M))
		want_y = glide if dist < FINAL_M else maxf(glide, ahead + MIN_AGL_M)
	var climb := clampf((want_y - pos.y) * 0.6, -SINK_MS, CLIMB_MS) * pace
	_steer(Vector3(v_h.x, climb, v_h.z), delta)
	if vel_h.length() > 8.0 * pace:
		_heading = atan2(-vel_h.x, -vel_h.z)
	elif _orbit and dist > 1.0:
		_heading = atan2(-dir.x, -dir.y)
	_attitude(Vector3.UP, delta)
	if has_meta(&"landing") and arrived():
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
	var dv_h := Vector3(dv.x, 0.0, dv.z).limit_length(ACCEL_MS2 * pace * delta)
	var dv_y := clampf(dv.y, -VERTICAL_ACCEL_MS2 * pace * delta, VERTICAL_ACCEL_MS2 * pace * delta)
	linear_velocity += dv_h + Vector3(0.0, dv_y, 0.0)
	_accel = _accel.lerp(dv_h / maxf(delta, 0.001) / pace, minf(delta * 4.0, 1.0))


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
