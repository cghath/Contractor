class_name VehicleDrive
extends Node
## Driving physics and terrain (combined arms A6, cg_brief queue item 2.7; docs/combined_arms.md
## 2.8, 9.2, 9.3): the "Drive" child of every wheeled and tracked vehicle. Numbers in
## data/vehicle_drive.json, every one Proposed; the per-model ones (the real centre of mass, the
## engine's power, the fording depth, the hull roof, the ground pressure, belted seats) merge into
## the model's spec (VehicleSpecs.TOPIC_PATHS).
##
## - Ground (2.8.1): ZoneTerrain.ground_at (roads, pads, river beds and fords, marsh, snow, rock,
##   sand, grass), a bridge's deck (ZoneBridges.deck_at), patches the level lays (add_patch:
##   rubble), else packed dirt (the compound, the range). Each kind has a traction for wheels and
##   tracks, a rolling resistance (scaled on soft ground by the ground pressure) and, for wheels,
##   a speed cap on sand and mud.
## - Power and traction (2.8.2): Vehicle._wheel_forces pulls with drive_force (the engine's power
##   over the speed, no more than accel_ms2 net), each wheel or track station gripping at most its
##   load x Vehicle.GRIP x the ground's traction, so whether it climbs comes from power and traction
##   (the old grade hold is gone). Tracks turn on the spot, more slowly at speed (half by 30 km/h),
##   by the ground's traction.
## - Rollovers (2.8.3): the static tip angle is half the wheel track over the centre of mass's
##   height (tip_deg); the HUD warns at 70% of it; past it for confirm_s the vehicle is rolled over:
##   the crew is hurt (a fall through Vitals, halved in belted seats, worse in open ones), it can't
##   drive, and a tow from a vehicle of half its mass (A8's tow job at its service point, 60 s)
##   rights it (server_start_righting), or it's abandoned. The AI keeps its lateral acceleration
##   and the side slopes it crosses under 60% of what tips it (ai_guard).
## - Thrown tracks: a hard pivot above 10 km/h on rock or rubble, or on a side slope over 20 deg.
## - Bogging: an MRAP on mud, stopped with the throttle open on a slope, is stuck until towed.
## - Water (2.8.4, F-240): deeper than its ford_m the engine stalls at once, is damaged after 5 s and
##   destroyed after 20 s; water over its roof floods the crew compartment and the crew gets out;
##   an amphibious hull holed under its waterline takes water against its bilge pumps and sinks
##   once full (AavWater reads flood_share for its buoyancy); out of the water it drains.
##
## Host authoritative: server_step runs in Vehicle._drive_step; net_state (in the vehicle's
## StateSync) gives every peer and late joiner the ground, the rolled, flooded, stalled and bogged
## states and the water aboard; the zone save keeps them (to_save). A9's AI and the HUD read the
## same through TerrainRoute (can_cross, ford_ok, slope_ok, path_problem).

const PATH := "res://data/vehicle_drive.json"
const NODE_NAME := &"Drive"
const ASPHALT := &"asphalt"
const DIRT := &"dirt"
const GRASS := &"grass"
const SAND := &"sand"
const MUD := &"mud"
const ROCK := &"rock"
const SNOW := &"snow"
const RUBBLE := &"rubble"
## Where there's no ZoneTerrain (the compound, the vehicle range): packed earth.
const DEFAULT_GROUND := DIRT
## The ground under a vehicle is looked up again after it moves this far, or this long.
const GROUND_EVERY_M := 1.0
const GROUND_EVERY_S := 0.25
## Level meta: patches of ground laid over the terrain ([Rect2 (x, z), kind]).
const PATCH_META := &"ground_patches"
## Wet: deeper than this (m) counts as in the water.
const WET_M := 0.05
## The engine stalled in deep water stays dead this long (s) after it's out (it was drowned).
const STALL_RESTART_S := 3.0

## Host: it rolled over / was righted (A9, tests).
signal rolled_over(vehicle: Vehicle)
signal righted(vehicle: Vehicle)

static var _data: Dictionary = {}

var vehicle: Vehicle
## Host state (clients: from net_state).
var rolled := false
var flooded := false
var bogged := false
var stalled := false
var righting := false
var flood_l := 0.0
var holes := 0
var ingest_s := 0.0
## Replicated (host -> every peer): {"g" ground, "r" rolled, "f" flooded, "b" bogged, "s" stalled,
## "rt" righting, "w" the water aboard as a share of what sinks it, "i" seconds the engine's
## been drowning}.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if not _is_host():
			_apply_net()
var _ground := DEFAULT_GROUND
var _ground_pos := Vector3.INF
var _ground_left := 0.0
var _tip_s := 0.0
var _bog_s := 0.0
var _bog_at := Vector3.ZERO
var _dry_s := 0.0
var _right_s := 0.0
var _restart_s := 0.0
var _look_left := 0.0
var _look_sign := 0.0
var _look_stop := ""
## Host: the last thing that stopped the AI driver (A9, tests).
var last_stop := ""
var _publish_left := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	name = NODE_NAME
	vehicle = p_vehicle
	_publish()


func _ready() -> void:
	if not _is_host() and not net_state.is_empty():
		_apply_net()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


## The vehicle's drive node (or null).
static func of(v: Node) -> VehicleDrive:
	return v.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleDrive if v else null


## Whether a model gets one (ground vehicles).
static func wanted(spec: Dictionary) -> bool:
	return String(spec.get("kind", "")) in [Vehicle.WHEELED, Vehicle.TRACKED]


# --- Data (pure) ------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {"ground": {}}
	return _data


static func num(section: String, key: String, fallback: float) -> float:
	return float(((data().get(section, {}) as Dictionary) if data().get(section) is Dictionary else {}).get(key, fallback))


## A ground kind's row ({} for an unknown one: dirt's).
static func ground_row(g: StringName) -> Dictionary:
	var rows: Dictionary = data().get("ground", {})
	return rows.get(String(g), rows.get(String(DEFAULT_GROUND), {"wheeled": 0.8, "tracked": 0.85, "rr": 0.03}))


## The share of the asphalt grip (Vehicle.GRIP) wheels or tracks (`kind`) keep on ground `g`.
static func traction(kind: String, g: StringName) -> float:
	return float(ground_row(g).get("tracked" if kind == Vehicle.TRACKED else "wheeled", 0.8))


## The rolling resistance (a share of the weight) of `spec` on ground `g`: soft ground (sand, mud,
## snow) by the square root of its ground pressure over ref_kpa (wide tracks float, narrow tyres dig in).
static func rolling(spec: Dictionary, g: StringName) -> float:
	var row := ground_row(g)
	var rr := float(row.get("rr", 0.03))
	if bool(row.get("soft", false)):
		var lim: Array = (data().get("power", {}) as Dictionary).get("soft_scale", [0.7, 1.5])
		rr *= clampf(sqrt(ground_kpa(spec) / num("power", "ref_kpa", 150.0)), float(lim[0]), float(lim[1]))
	return rr


## A wheeled model's speed cap on ground `g` (m/s; INF for none or for tracks).
static func speed_cap(spec: Dictionary, g: StringName) -> float:
	var cap := float(ground_row(g).get("cap_kmh", 0.0))
	if cap <= 0.0 or String(spec.get("kind", "")) != Vehicle.WHEELED:
		return INF
	return cap * VehicleSpecs.KMH


static func ground_kpa(spec: Dictionary) -> float:
	return float(spec.get("ground_kpa", 150.0))


## Half the wheel track (m): the outermost wheel's or track's offset.
static func half_track(spec: Dictionary) -> float:
	var hw := 0.0
	for w: Array in spec.get("wheels", []):
		hw = maxf(hw, absf(float(w[0])))
	if hw <= 0.0:
		for b: Array in spec.get("boxes", []):
			hw = maxf(hw, maxf(absf(float(b[0])), absf(float(b[3]))) * 0.8)
	return maxf(hw, 0.3)


## The centre of mass's height over the ground the vehicle stands on (m).
static func com_height(spec: Dictionary) -> float:
	return maxf(VehicleSpecs.vec(spec.get("com"), Vector3(0, 1, 0)).y, 0.1)


## The static tip angle (degrees): half the track over the centre of mass's height (2.8.3).
static func tip_deg(spec: Dictionary) -> float:
	return rad_to_deg(atan2(half_track(spec), com_height(spec)))


## The lateral acceleration (m/s2) that tips it on the flat: g x half track / height.
static func tip_lat_ms2(spec: Dictionary) -> float:
	return _g() * half_track(spec) / com_height(spec)


## The engine's power at the wheels or sprockets (W): power_kw x driveline_eff; a model without
## power_kw drives as before A6 (its mass x accel_ms2 x top speed).
static func power_w(spec: Dictionary) -> float:
	var kw := float(spec.get("power_kw", 0.0))
	if kw <= 0.0:
		return float(spec.get("mass_kg", 1000.0)) * float(spec.get("accel_ms2", 2.0)) * float(spec.get("top_speed_kmh", 40.0)) * VehicleSpecs.KMH
	return kw * 1000.0 * num("power", "driveline_eff", 0.8)


## Power to weight (kW a tonne, at the engine), for the tables.
static func kw_per_t(spec: Dictionary) -> float:
	return float(spec.get("power_kw", 0.0)) / maxf(float(spec.get("mass_kg", 1000.0)) / 1000.0, 0.001)


## 2.8.2's pull (N) of an engine of `p_w` on mass `m` at `v` m/s: P / max(v, min_v), no more than
## gives `accel_cap` x `demand` (the throttle) net after rolling resistance `rr` and the slope
## (`sin_up` > 0 uphill): the gearbox holds a grade at part throttle as the old grade hold did, but
## only as far as the power goes. Traction caps it again at each wheel (Vehicle._wheel_forces);
## drive_net() adds that here.
static func drive_force(p_w: float, m: float, v: float, rr: float, sin_up: float, accel_cap: float, demand := 1.0) -> float:
	var g := _g()
	var cos_s := sqrt(maxf(1.0 - sin_up * sin_up, 0.0))
	var pull := p_w / maxf(absf(v), num("power", "min_v_ms", 2.0))
	return minf(pull, m * (accel_cap * clampf(absf(demand), 0.0, 1.0) + g * maxf(rr * cos_s + sin_up, 0.0)))


## 2.8.2's whole formula: the net force (N) along the slope with traction `mu` (a share of the
## weight): min(pull, mu x m x g x cos) - rr x m x g x cos - m x g x sin.
static func drive_net(p_w: float, m: float, v: float, mu: float, rr: float, sin_up: float, accel_cap: float) -> float:
	var g := _g()
	var cos_s := sqrt(maxf(1.0 - sin_up * sin_up, 0.0))
	return minf(drive_force(p_w, m, v, rr, sin_up, accel_cap), mu * m * g * cos_s) - rr * m * g * cos_s - m * g * sin_up


## The steepest grade (degrees) `spec` climbs on ground `g`, by traction and by its power at
## min_v (the slower of the two limits).
static func climb_deg(spec: Dictionary, g: StringName, packages: Array = []) -> float:
	var kind := String(spec.get("kind", Vehicle.WHEELED))
	var mu := Vehicle.GRIP * traction(kind, g)
	var rr := rolling(spec, g)
	var by_grip := atan(maxf(mu - rr, 0.0))
	var m := mass_kg_of(spec, packages)
	var by_power := asin(clampf(power_w(spec) / num("power", "min_v_ms", 2.0) / (m * _g()) - rr, 0.0, 1.0))
	return rad_to_deg(minf(by_grip, by_power))


static func mass_kg_of(spec: Dictionary, packages: Array = []) -> float:
	return float(spec.get("mass_kg", 1000.0)) + VehicleLogistics.added_t(spec, packages) * 1000.0


## A vehicle's mass with its packages (t): what a bridge carries.
static func mass_t(v: Vehicle) -> float:
	return mass_kg_of(v.spec, v.logistics.packages if v.logistics else []) / 1000.0


## Its military load class (2.8.5): the mass in tonnes with its packages, rounded up.
static func mlc(v: Vehicle) -> int:
	return ceili(mass_t(v) - 0.001)


static func swims(spec: Dictionary) -> bool:
	return spec.get("amphibious", null) is Dictionary


## How deep it can ford (m of water over the ground; INF for one that swims).
static func ford_m(spec: Dictionary) -> float:
	return INF if swims(spec) else float(spec.get("ford_m", AavWater.FORD_M))


## The crew compartment's roof over the ground it stands on (m).
static func roof_m(spec: Dictionary) -> float:
	if spec.has("roof_m"):
		return float(spec.roof_m)
	var top := 0.0
	for b: Array in spec.get("boxes", []):
		top = maxf(top, maxf(float(b[1]), float(b[4])))
	return maxf(top, 1.2)


## Whether seat `i` of `spec` has a belt (data "belted": "all", "all_but_gunner", "none").
static func belted(spec: Dictionary, i: int) -> bool:
	var seats: Array = spec.get("seats", [])
	if i < 0 or i >= seats.size():
		return false
	match String(spec.get("belted", "none")):
		"all":
			return true
		"all_but_gunner":
			return StringName(String((seats[i] as Dictionary).get("kind", ""))) != Vehicle.GUNNER and not bool((seats[i] as Dictionary).get("exo", false))
	return false


static func _g() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


# --- The ground ----------------------------------------------------------------------------------

## The ground at `p` in `level` (any peer): a level patch, a bridge's deck, the zone's terrain, else
## packed dirt.
static func ground_at(level: Node, p: Vector3) -> StringName:
	if level == null:
		return DEFAULT_GROUND
	if level.has_meta(PATCH_META):
		for patch: Array in level.get_meta(PATCH_META):
			if (patch[0] as Rect2).has_point(Vector2(p.x, p.z)) and p.y >= float(patch[2]) and p.y <= float(patch[3]):
				return StringName(String(patch[1]))
	var t: Variant = level.get(&"terrain")
	if t is ZoneTerrain:
		var terrain := t as ZoneTerrain
		if terrain.water and terrain.water.bridges:
			var at := terrain.water.bridges.deck_at(p)
			if at.x >= 0:
				return DIRT if String(terrain.water.bridges.bridges[at.x].type) == ZoneBridges.FOOT else ASPHALT
		return terrain.ground_at(p.x, p.z)
	return DEFAULT_GROUND


## Lays a patch of ground `kind` over `rect` (x, z) between heights `y_range` in `level` (rubble
## where a building came down; the armourdrive suite's test ground), over the patches already laid
## (the newest wins). Every peer that should drive on it lays it.
static func add_patch(level: Node, rect: Rect2, kind: StringName, y_range := Vector2(-INF, INF)) -> void:
	var patches: Array = [[rect, String(kind), y_range.x, y_range.y]]
	patches.append_array(level.get_meta(PATCH_META, []))
	level.set_meta(PATCH_META, patches)


static func clear_patches(level: Node) -> void:
	if level and level.has_meta(PATCH_META):
		level.remove_meta(PATCH_META)


## The ground under this vehicle now (every peer).
func ground() -> StringName:
	return _ground if _is_host() else StringName(String(net_state.get("g", String(DEFAULT_GROUND))))


## This vehicle's traction and rolling resistance on the ground under it now.
func traction_now() -> float:
	return traction(vehicle.kind, ground())


func rolling_now() -> float:
	return rolling(vehicle.spec, ground())


## The wheeled speed cap on the ground under it now (m/s; INF none).
func speed_cap_now() -> float:
	return speed_cap(vehicle.spec, ground())


## The engine's power now (W): its share by the engine's health (engine_floor at none).
func power_now() -> float:
	return power_w(vehicle.spec) * lerpf(num("power", "engine_floor", 0.4), 1.0, vehicle.zone_health(Vehicle.ZONE_ENGINE))


# --- Queries (every peer) ------------------------------------------------------------------------

func is_rolled() -> bool:
	return rolled if _is_host() else bool(net_state.get("r", false))


func is_flooded() -> bool:
	return flooded if _is_host() else bool(net_state.get("f", false))


func is_bogged() -> bool:
	return bogged if _is_host() else bool(net_state.get("b", false))


func is_stalled() -> bool:
	return stalled if _is_host() else bool(net_state.get("s", false))


func is_righting() -> bool:
	return righting if _is_host() else bool(net_state.get("rt", false))


## The water aboard an amphibious hull as a share of what sinks it (0..1).
func flood_share() -> float:
	if not _is_host():
		return float(net_state.get("w", 0.0))
	return clampf(flood_l / maxf(num("ford", "sink_l", 9000.0), 1.0), 0.0, 1.0) if not flooded else 1.0


## Why it can't drive because of the ground or the water ("" when it can).
func blocked() -> String:
	if is_rolled():
		return "Rolled over"
	if is_flooded():
		return "Flooded"
	if is_stalled():
		return "Stalled in deep water"
	if is_bogged():
		return "Bogged down"
	return ""


## The body's side tilt (degrees): how far it leans over to a side.
static func roll_deg(v: Node3D) -> float:
	return rad_to_deg(asin(clampf(absf(v.global_basis.x.y), 0.0, 1.0)))


## The body's tilt from upright (degrees), any way.
static func tilt_deg(v: Node3D) -> float:
	return rad_to_deg(v.global_basis.y.angle_to(Vector3.UP))


## How deep the water is over the ground under `v` (m): over the zone's ground there (afloat or
## not), or over the hull's origin on a bridge's deck or with no heightmap (0 on a deck over a river).
static func ford_depth(v: Vehicle) -> float:
	if v == null or not v.is_inside_tree():
		return 0.0
	var p := v.global_position
	var water := AavWater.water_height(v, p.x, p.z)
	if water == -INF or p.y > water + 0.5:
		return 0.0  # (no water, or well over it: a deck, a slab)
	var lvl := v.level()
	var t: Variant = lvl.get(&"terrain") if lvl else null
	var ground := p.y
	if t is ZoneTerrain:
		var terrain := t as ZoneTerrain
		var on_deck := terrain.water != null and terrain.water.bridges != null and terrain.water.bridges.deck_at(p).x >= 0
		if not on_deck:
			ground = minf(p.y, terrain.height_at(p.x, p.z))
	return maxf(water - ground, 0.0)


# --- Host: the step --------------------------------------------------------------------------------

## Host: one physics step (Vehicle._drive_step, before the wheels): the ground, the tip, the water,
## bogging, thrown tracks, righting.
func server_step(delta: float, throttle: float, steer: float) -> void:
	var p := vehicle.global_position
	_ground_left -= delta
	if _ground_left <= 0.0 or p.distance_squared_to(_ground_pos) > GROUND_EVERY_M * GROUND_EVERY_M:
		_ground_left = GROUND_EVERY_S
		_ground_pos = p
		var g := ground_at(vehicle.level(), p)
		if g != _ground:
			_ground = g
			_publish_left = 0.0
	var tilt := tilt_deg(vehicle)
	if righting:
		_righting_step(delta, tilt)
	elif not rolled and not vehicle.wrecked:
		if tilt > tip_deg(vehicle.spec):
			_tip_s += delta
			if _tip_s >= num("rollover", "confirm_s", 0.75):
				server_roll()
		else:
			_tip_s = 0.0
	_water_step(delta, ford_depth(vehicle))
	if vehicle.kind == Vehicle.WHEELED:
		_bog_step(delta, throttle, tilt)
	elif vehicle.kind == Vehicle.TRACKED and not rolled:
		_throw_step(delta, steer)
	_publish_left -= delta
	if _publish_left <= 0.0:
		_publish_left = 1.0
		_publish()


## Host: it went over: the crew hurt (a fall of fall_m, half in a belted seat, open_mult in an open
## one), it can't drive, the AI driver stops.
func server_roll() -> void:
	if rolled:
		return
	rolled = true
	_tip_s = 0.0
	var fall := num("rollover", "fall_m", 3.2)
	for i in vehicle.seat_count():
		var s := vehicle.occupant(i)
		if s == null or s.vitals.is_dead():
			continue
		var f := fall
		if belted(vehicle.spec, i):
			f *= num("rollover", "belted_mult", 0.5)
		elif vehicle.seat_open(i) or vehicle.exo_seat(i):
			f *= num("rollover", "open_mult", 1.5)
		s.vitals.server_fall(f)
	vehicle.server_stop()
	print("[drive] %s rolled over (%.0f deg past its %.0f deg tip angle)" % [vehicle.display_name(), tilt_deg(vehicle), tip_deg(vehicle.spec)])
	_publish()
	rolled_over.emit(vehicle)


## Host (VehicleLogistics, once the tow is hooked up to a rolled vehicle): the tower's pull stands
## it back up (_righting_step).
func server_start_righting(_tower: Vehicle) -> void:
	if not rolled or righting:
		return
	righting = true
	_right_s = 0.0
	vehicle.sleeping = false
	print("[drive] %s: righting it on the tow" % vehicle.display_name())
	_publish()


## Host: the winch's pull on a rolled vehicle: a torque turning its up toward the sky (no more than
## right_torque_g x its weight's turning moment) and a lift while it's well over; standing within
## upright_deg and settling, it's righted (and stays on the tow). The tow coming off stops it.
func _righting_step(delta: float, tilt: float) -> void:
	_right_s += delta
	var lg := vehicle.logistics
	if lg == null or not lg.towed() or _right_s > num("rollover", "right_max_s", 30.0):
		righting = false
		_publish()
		return
	if tilt < num("rollover", "upright_deg", 12.0) and vehicle.angular_velocity.length() < 0.6:
		righting = false
		rolled = false
		_tip_s = 0.0
		print("[drive] %s righted after %.1f s" % [vehicle.display_name(), _right_s])
		_publish()
		righted.emit(vehicle)
		return
	var up := vehicle.global_basis.y
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		axis = vehicle.global_basis.z  # upside down: over either way
	axis = axis.normalized()
	var m := vehicle.mass
	var box := VehicleCamera.hull_box(vehicle)
	var inertia := m * (box.size.x * box.size.x + box.size.y * box.size.y) / 12.0
	var cap := num("rollover", "right_torque_g", 1.4) * m * _g() * maxf(com_height(vehicle.spec), half_track(vehicle.spec))
	var want := inertia * (2.5 * deg_to_rad(tilt) - 2.0 * vehicle.angular_velocity.dot(axis))
	vehicle.apply_torque(axis * clampf(want, -cap, cap))
	if tilt > 45.0:
		vehicle.apply_central_force(Vector3.UP * m * _g() * 0.45)


func _water_step(delta: float, depth: float) -> void:
	var spec := vehicle.spec
	var amph := swims(spec)
	if not amph:
		var deep := depth > ford_m(spec)
		if deep:
			if not stalled:
				print("[drive] %s: %.2f m of water, over its %.2f m fording depth: the engine stalls" % [vehicle.display_name(), depth, ford_m(spec)])
			stalled = true
			_restart_s = STALL_RESTART_S
			var before := ingest_s
			ingest_s += delta
			if before < num("ford", "damaged_s", 5.0) and ingest_s >= num("ford", "damaged_s", 5.0):
				_engine_to(VehicleModules.DAMAGED_SHARE - 0.01)
				_publish_left = 0.0
			if before < num("ford", "destroyed_s", 20.0) and ingest_s >= num("ford", "destroyed_s", 20.0):
				_engine_to(0.0)
				_publish_left = 0.0
		elif stalled:
			_restart_s -= delta
			if _restart_s <= 0.0:
				stalled = false
				_publish_left = 0.0
	if not amph and depth > roof_m(spec):  # (a swimming hull floods by its holes)
		server_flood()
	if amph:
		if depth > WET_M:
			var inflow := float(holes) * num("ford", "hole_lps", 35.0) - num("ford", "pump_lps", 25.0)
			flood_l = clampf(flood_l + inflow * delta, 0.0, num("ford", "sink_l", 9000.0))
			if flood_l >= num("ford", "sink_l", 9000.0):
				server_flood()
		else:
			flood_l = maxf(flood_l - num("ford", "pump_lps", 25.0) * delta, 0.0)
	if depth <= WET_M:
		_dry_s += delta
		if flooded and _dry_s >= num("ford", "drain_s", 60.0) and flood_l <= 0.0:
			flooded = false
			print("[drive] %s drained" % vehicle.display_name())
			_publish_left = 0.0
	else:
		_dry_s = 0.0


## Host: water over the roof (or a swimming hull full): the crew compartment floods and everyone
## aboard who can gets out (the wading and swimming take over); the bodies stay.
func server_flood() -> void:
	if flooded:
		return
	flooded = true
	_dry_s = 0.0
	if swims(vehicle.spec):
		flood_l = num("ford", "sink_l", 9000.0)
	for s: Soldier in vehicle.occupants():
		if s.vitals.is_up() or (s.is_ai() and not s.vitals.is_dead()):
			vehicle.server_exit(s)
	print("[drive] %s flooded: the crew gets out" % vehicle.display_name())
	_publish()


## Host (Vehicle.server_take_hit): a round through an amphibious hull under its waterline holes it.
func server_hit(out: Dictionary) -> void:
	if not bool(out.get("penetrated", false)) or not swims(vehicle.spec):
		return
	var local := vehicle.to_local(out.get("position", vehicle.global_position))
	if local.y < float(vehicle.spec.get("waterline_m", 1.5)):
		holes += 1
		print("[drive] %s holed under the waterline (%d)" % [vehicle.display_name(), holes])
		_publish_left = 0.0


## Host: the engine's health down to `h` (its module, or its old zone on a model without).
func _engine_to(h: float) -> void:
	if vehicle.modules and vehicle.modules.authored and vehicle.modules.index_of("engine") >= 0:
		vehicle.modules.server_set("engine", minf(vehicle.modules.health_of("engine"), h))
	else:
		vehicle.server_set_zone(Vehicle.ZONE_ENGINE, minf(vehicle.zone_health(Vehicle.ZONE_ENGINE), h))
	print("[drive] %s: the engine drowns (%s)" % [vehicle.display_name(), "destroyed" if h <= 0.0 else "damaged"])


func _bog_step(delta: float, throttle: float, tilt: float) -> void:
	if bogged:
		var lg := vehicle.logistics
		if lg and lg.towed() and vehicle.global_position.distance_to(_bog_at) > num("bog", "bog_tow_m", 4.0):
			bogged = false
			_publish_left = 0.0
		return
	if _ground == MUD and ground_kpa(vehicle.spec) >= num("bog", "ground_kpa", 250.0) and absf(throttle) > 0.3 \
			and vehicle.linear_velocity.length() < num("bog", "bog_kmh", 3.0) * VehicleSpecs.KMH and tilt > num("bog", "bog_slope_deg", 2.0):
		_bog_s += delta
		if _bog_s >= num("bog", "bog_s", 4.0):
			bogged = true
			_bog_at = vehicle.global_position
			print("[drive] %s bogged down in the mud" % vehicle.display_name())
			_publish_left = 0.0
	else:
		_bog_s = 0.0


## Host: a hard pivot at speed on rock or rubble, or on a side slope, may throw the outer track
## (throw_per_s, rolled from the vehicle and the physics frame).
func _throw_step(delta: float, steer: float) -> void:
	var risk := throw_risk(vehicle.spec, _ground, steer, vehicle.forward_speed(), roll_deg(vehicle))
	if risk <= 0.0:
		return
	var roll := float(absi(hash([vehicle.vehicle_id, vehicle.name, Engine.get_physics_frames()])) % 1000000) / 1000000.0
	if roll < risk * delta:
		server_throw_track("track_l" if steer > 0.0 else "track_r")


## The chance a second (2.8.3) that tracks of `spec` steered `steer` at `speed` m/s on ground `g`,
## leaning `side_deg`, throw one: throw_per_s on a hard pivot over throw_kmh on rock or rubble or on
## a side slope over throw_side_deg; else 0.
static func throw_risk(spec: Dictionary, g: StringName, steer: float, speed: float, side_deg: float) -> float:
	if String(spec.get("kind", "")) != Vehicle.TRACKED or absf(steer) < num("tracked", "pivot_steer", 0.9) \
			or absf(speed) < num("tracked", "throw_kmh", 10.0) * VehicleSpecs.KMH:
		return 0.0
	if not bool(ground_row(g).get("throws", false)) and side_deg <= num("tracked", "throw_side_deg", 20.0):
		return 0.0
	return num("tracked", "throw_per_s", 0.005)


## A tracked hull's turn rate (rad/s) commanded at full steer at `speed` m/s on ground `g`
## (Vehicle._wheel_forces: turn_deg_s on the spot, half by half_rate_kmh, by the traction).
static func track_turn(spec: Dictionary, g: StringName, speed: float) -> float:
	return deg_to_rad(float(spec.get("turn_deg_s", 40.0))) * turn_share(g) / (1.0 + absf(speed) / (num("tracked", "half_rate_kmh", 30.0) * VehicleSpecs.KMH))


## The share of its firm-ground turn rate tracks keep on ground `g`: their traction there over
## turn_ref_traction (firm dirt's), at most 1 (turn_deg_s is the firm-ground rate).
static func turn_share(g: StringName) -> float:
	return minf(traction(Vehicle.TRACKED, g) / num("tracked", "turn_ref_traction", 0.85), 1.0)


## Host: a track thrown (the module destroyed: field-repairable, 2.9.3).
func server_throw_track(id: String) -> void:
	if vehicle.modules and vehicle.modules.authored and vehicle.modules.index_of(id) >= 0:
		vehicle.modules.server_set(id, 0.0)
	else:
		vehicle.server_set_zone(Vehicle.ZONE_WHEELS, 0.0)
	print("[drive] %s threw its %s" % [vehicle.display_name(), id.replace("_l", " (left)").replace("_r", " (right)").replace("_", " ")])


# --- Host: the AI driver's care --------------------------------------------------------------------

## Host (Vehicle._drive_step, for the AI driver's input only): the AI keeps its lateral acceleration
## under ai_lat_share of what tips it (lifting off, then braking), and stops short of what it
## mustn't drive onto (TerrainRoute.ahead_problem: a span too light, water too deep, a side slope
## over ai_share of the tip angle, a grade it can't climb), looked at every_s. Stopped, its own
## stuck handling (VehicleAI) backs off and goes round, and SquadDrivers plans another way.
func ai_guard(input: Dictionary, delta: float) -> Dictionary:
	var t := float(input.get("throttle", 0.0))
	if t == 0.0 or rolled:
		return input
	var out := input.duplicate()
	var v := vehicle.forward_speed()
	var lim := tip_lat_ms2(vehicle.spec) * num("rollover", "ai_lat_share", 0.6)
	var lat := absf(vehicle.angular_velocity.dot(vehicle.global_basis.y) * v)
	if vehicle.kind == Vehicle.WHEELED:
		var steer_ang := deg_to_rad(float(vehicle.spec.get("steer_deg", 30.0))) * absf(float(input.get("steer", 0.0))) / (1.0 + absf(v) / Vehicle.STEER_FALLOFF_MS)
		lat = maxf(lat, v * v * tan(steer_ang) / maxf(wheelbase(vehicle.spec), 1.0))
	if lat > lim:
		out.throttle = 0.0
		if lat > lim * 1.2:
			out.brake = true
	_look_left -= delta
	if _look_left <= 0.0 or signf(t) != _look_sign:
		_look_left = num("ai", "every_s", 0.1)
		_look_sign = signf(t)
		var dir := -vehicle.global_basis.z * signf(t)
		_look_stop = TerrainRoute.ahead_problem(vehicle, dir, maxf(v * signf(t), 0.0) * num("ai", "look_s", 1.5) + num("ai", "look_m", 6.0))
	if _look_stop != "":
		last_stop = _look_stop
		out.throttle = 0.0
		out.brake = true
	return out


## Air drag on the hull (N, host): 0.5 x rho x cd x frontal area x v^2 against its way over the
## ground (data "aero"), the frontal area its hull box's width x height.
func aero_force() -> Vector3:
	var vel := vehicle.linear_velocity
	var flat := Vector3(vel.x, 0.0, vel.z)
	var speed := flat.length()
	if speed < 0.5:
		return Vector3.ZERO
	return -flat / speed * aero_drag(vehicle.spec, speed)


## The drag (N) of `spec`'s hull at `speed` m/s.
static func aero_drag(spec: Dictionary, speed: float) -> float:
	var top := 0.0
	var bottom := INF
	var width := 0.0
	for b: Array in spec.get("boxes", []):
		top = maxf(top, maxf(float(b[1]), float(b[4])))
		bottom = minf(bottom, minf(float(b[1]), float(b[4])))
		width = maxf(width, absf(float(b[3]) - float(b[0])))
	var area := width * (top - bottom) if top > bottom else 4.0
	return 0.5 * num("aero", "rho", 1.2) * num("aero", "cd", 0.9) * area * speed * speed


## What's stopping the AI driver now ("" nothing): A9 reads it.
func ai_stop_reason() -> String:
	return _look_stop


## The wheelbase (m): the front and rear wheels' spread.
static func wheelbase(spec: Dictionary) -> float:
	var lo := INF
	var hi := -INF
	for w: Array in spec.get("wheels", []):
		lo = minf(lo, float(w[1]))
		hi = maxf(hi, float(w[1]))
	return hi - lo if hi > lo else 3.0


# --- Net and saving ----------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	net_state = {"g": String(_ground), "r": rolled, "f": flooded, "b": bogged, "s": stalled, "rt": righting,
		"w": snappedf(flood_share(), 0.01), "i": snappedf(ingest_s, 0.1)}


func _apply_net() -> void:
	pass  # the queries read net_state directly


## The HUD's lines (every peer).
func readout_parts(_seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var why := blocked()
	if why != "":
		out.append({"text": why.to_upper(), "style": &"warn"})
	return out


## JSON-safe state for the zone save.
func to_save() -> Dictionary:
	var out := {}
	if rolled:
		out["rolled"] = true
	if flooded:
		out["flooded"] = true
	if bogged:
		out["bogged"] = true
	if flood_l > 0.0:
		out["flood_l"] = snappedf(flood_l, 0.1)
	if holes > 0:
		out["holes"] = holes
	if ingest_s > 0.0:
		out["ingest_s"] = snappedf(ingest_s, 0.1)
	return out


## Puts a to_save() back (an older save without one: on its wheels, dry).
func from_save(d: Dictionary) -> void:
	rolled = bool(d.get("rolled", false))
	flooded = bool(d.get("flooded", false))
	bogged = bool(d.get("bogged", false))
	flood_l = maxf(float(d.get("flood_l", 0.0)), 0.0)
	holes = maxi(int(d.get("holes", 0)), 0)
	ingest_s = maxf(float(d.get("ingest_s", 0.0)), 0.0)
	if bogged and vehicle:
		_bog_at = vehicle.transform.origin
	_publish()
