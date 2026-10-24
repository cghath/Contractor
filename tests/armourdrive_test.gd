extends Node
## Headless checks for combined arms A6 (cg_brief queue item 2.7; docs/combined_arms.md 2.8, 9.3):
## driving physics and terrain, on a river valley zone with a concrete and a truss bridge and a
## river ford, plus a test slab ("the lab") high over it for controlled slopes and ground. The data
## (mass, real centres of mass, power, fording depths, ground pressure, the ground table, load
## classes); the ground under a vehicle (roads, the river bed, the ford, a deck, grass); acceleration
## and climb by power to weight; a dry climb against a muddy one; tracks turning on the spot and half
## as fast at 30 km/h; thrown tracks' rule; the slope limits the AI keeps; a tilt table: upright
## under the tip angle, over past it within 10% of the predicted angle; a rollover hurting the crew
## (belted seats less, the open hatch more), righting by a tow from a vehicle of half its mass and
## not a lighter one; a tow up a slope (F-272) and its bar; bogging an MRAP in mud; fording depth per
## vehicle (the M-ATV through 1.1 m, the MaxxPro stalled and its engine drowning); flooding (a
## technical in the channel); the AAV swimming at its speed, its waterjets, the current, holed and
## sinking; bridges by load class (a Bradley over the truss bridge, the Abrams kept off it by the
## AI and its roads, dropping the span when parked on it, the concrete bridge holding it); the HUD
## alerts with the real numbers; save and load; the cost; then a second process joins over ENet and
## finds the states as the host has them.
##   <voxel godot exe> --headless --path . res://tests/armourdrive_test.tscn
## The host starts the client itself ("-- --armourdrive-join"). Exits with the number of failures.

const SIZE_M := 2048.0
## Seeds tried for the zone: the first whose river has a concrete and a truss bridge and a ford.
const SEEDS: Array[int] = [20, 13, 11, 18, 12, 15, 16, 14, 17, 19]
## The lab: a slab this far over the zone's highest ground, this big (half a side, m), at the
## zone's middle.
const LAB_UP_M := 120.0
const LAB_HALF_M := 170.0
## Budgets (Proposed; 9.3: the physics step unchanged on the vehicle range): a vehicle's drive step
## (VehicleDrive.server_step), the AI driver's care per tick, the bridges' weighing with 20
## vehicles about, a whole wheel-and-drive step of an Abrams.
const STEP_BUDGET_MS := 0.03
const GUARD_BUDGET_MS := 0.05
const LOAD_BUDGET_MS := 0.2
const WHEELS_BUDGET_MS := 0.25
const LOCAL_SLACK := 3.0

var failures := 0
var main: Node
var level: ZoneLevel
var water: ZoneWater
var layer: VehicleLayer
var player: Soldier
var lab_y := 0.0
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _n := 0
var _tag := ""
var _lab: Array[Node] = []


func _ready() -> void:
	_tag = OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_armourdrive" + _tag  # never touch a real save
	Campaign.campaign_id = "test_armourdrive" + _tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_armourdrive_settings%s.cfg" % _tag))  # never the player's
	GameSettings.reset_all()
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	Vehicle.fire_rolls = false
	if "--armourdrive-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(1000.0).timeout.connect(func() -> void:
		print("ARMOURDRIVE TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_data()
	ZoneScatter.clear_cache(true)
	var def := _pick_def()
	if def.is_empty():
		_finish()
		return
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and level.terrain.water != null and level.terrain.water.bridges != null, "hosting the river valley zone (seed %d)" % int(def.seed))
	if level == null or level.terrain.water == null:
		_finish()
		return
	water = level.terrain.water
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 30.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	layer = VehicleLayer.of(level)
	for model: String in ["abrams", "bradley", "aav7", "matv", "maxxpro", "technical"]:
		VehicleHull.prewarm(model)
	_build_lab()
	await _physics(4)
	if _want("ground"):
		_test_ground()
	if _want("power"):
		await _test_acceleration()
		await _test_climb()
		await _test_turning()
	if _want("slopes"):
		await _test_ai_slopes()
		await _test_tilt_table()
	if _want("rollover"):
		await _test_rollover_and_righting()
	if _want("bog"):
		await _test_bog()
	if _want("water"):
		await _test_fording()
		await _test_flooding()
		await _test_swimming()
	if _want("bridges"):
		await _test_bridges()
	if _want("save"):
		await _test_save()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	_finish()


## While iterating: CONTRACTOR_ARMOURDRIVE_ONLY="water,bridges" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_ARMOURDRIVE_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	Campaign.reset_campaign()
	GameSettings.reset_all()
	GameSettings.use_file("")
	print("ARMOURDRIVE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


# --- Data (pure) ---------------------------------------------------------------------------------

func _test_data() -> void:
	print("The numbers (2.8.1-2.8.5, pure)")
	var rows := PackedStringArray()
	for m: String in ["abrams", "bradley", "aav7", "matv", "maxxpro", "technical"]:
		var s := VehicleSpecs.spec(m)
		rows.append("%s %.1f t, CoM %.2f m, %d kW (%.1f kW/t), tip %.1f deg, ford %s, %d kPa, climbs %.0f deg dirt / %.0f mud" % [m, float(s.mass_kg) / 1000.0,
			VehicleDrive.com_height(s), int(s.get("power_kw", 0)), VehicleDrive.kw_per_t(s), VehicleDrive.tip_deg(s),
			"swims" if VehicleDrive.swims(s) else "%.2f m" % VehicleDrive.ford_m(s), int(VehicleDrive.ground_kpa(s)),
			VehicleDrive.climb_deg(s, VehicleDrive.DIRT), VehicleDrive.climb_deg(s, VehicleDrive.MUD)])
	for r in rows:
		print("    " + r)
	var p := {"abrams": 1120, "bradley": 450, "aav7": 390, "matv": 276, "maxxpro": 280, "technical": 110}
	var power_ok := p.keys().all(func(m: String) -> bool: return int(VehicleSpecs.spec(m).get("power_kw", 0)) == int(p[m]))
	check(power_ok and _near(VehicleDrive.com_height(VehicleSpecs.spec("matv")), 1.25, 0.001) and _near(VehicleDrive.com_height(VehicleSpecs.spec("maxxpro")), 1.35, 0.001)
		and VehicleDrive.com_height(VehicleSpecs.spec("abrams")) < 1.0, "2.8.2's power_kw on every model; real centres of mass: the M-ATV's 1.25 m, the MaxxPro's 1.35, the tanks' low (F-257)")
	var f := {"abrams": 1.2, "bradley": 1.0, "matv": 1.37, "maxxpro": 0.9, "technical": 0.6}
	check(f.keys().all(func(m: String) -> bool: return _near(VehicleDrive.ford_m(VehicleSpecs.spec(m)), float(f[m]), 0.001)) and VehicleDrive.swims(VehicleSpecs.spec("aav7")),
		"2.8.4's fording depths set on every model (the Abrams 1.2 m ... the technical 0.6); the AAV swims")
	var matv := VehicleSpecs.spec("matv")
	check(_near(VehicleDrive.tip_deg(matv), rad_to_deg(atan2(1.06, 1.25)), 0.01) and VehicleDrive.tip_deg(VehicleSpecs.spec("maxxpro")) < VehicleDrive.tip_deg(matv)
		and VehicleDrive.tip_deg(VehicleSpecs.spec("abrams")) > 55.0, "tip angles from half the track over the CoM's height: M-ATV %.1f, MaxxPro %.1f, Abrams %.1f deg" % [VehicleDrive.tip_deg(matv), VehicleDrive.tip_deg(VehicleSpecs.spec("maxxpro")), VehicleDrive.tip_deg(VehicleSpecs.spec("abrams"))])
	var g := VehicleDrive.data().get("ground", {}) as Dictionary
	check(g.size() == 8 and _near(VehicleDrive.traction(Vehicle.WHEELED, VehicleDrive.MUD), 0.3, 0.001) and _near(VehicleDrive.traction(Vehicle.TRACKED, VehicleDrive.MUD), 0.55, 0.001)
		and _near(VehicleDrive.speed_cap(matv, VehicleDrive.SAND) * 3.6, 40.0, 0.01) and _near(VehicleDrive.speed_cap(matv, VehicleDrive.MUD) * 3.6, 25.0, 0.01)
		and VehicleDrive.speed_cap(VehicleSpecs.spec("abrams"), VehicleDrive.MUD) == INF
		and VehicleDrive.rolling(VehicleSpecs.spec("abrams"), VehicleDrive.MUD) < VehicleDrive.rolling(VehicleSpecs.spec("maxxpro"), VehicleDrive.MUD),
		"2.8.1's ground table: 8 kinds, mud 0.3 / 0.55, wheels capped at 40 km/h on sand and 25 on mud; on soft ground wide tracks roll easier than narrow tyres (%.3f against %.3f)" % [VehicleDrive.rolling(VehicleSpecs.spec("abrams"), VehicleDrive.MUD), VehicleDrive.rolling(VehicleSpecs.spec("maxxpro"), VehicleDrive.MUD)])
	var mx := VehicleSpecs.spec("maxxpro")
	var dry := VehicleDrive.drive_net(VehicleDrive.power_w(mx), 14500.0, 2.0, Vehicle.GRIP * VehicleDrive.traction(Vehicle.WHEELED, VehicleDrive.DIRT), VehicleDrive.rolling(mx, VehicleDrive.DIRT), sin(deg_to_rad(15.0)), 2.0)
	var wet := VehicleDrive.drive_net(VehicleDrive.power_w(mx), 14500.0, 2.0, Vehicle.GRIP * VehicleDrive.traction(Vehicle.WHEELED, VehicleDrive.MUD), VehicleDrive.rolling(mx, VehicleDrive.MUD), sin(deg_to_rad(15.0)), 2.0)
	check(dry > 0.0 and wet < 0.0, "2.8.2's formula: a MaxxPro on a 15 deg hill pulls %.1f kN net on dirt, %.1f kN on mud (a wet hill stops it)" % [dry / 1000.0, wet / 1000.0])
	var mlcs := {"abrams": 62, "bradley": 30, "aav7": 25, "matv": 13, "maxxpro": 15, "technical": 3}
	var mlc_ok := true
	for m: String in mlcs:
		mlc_ok = mlc_ok and ceili(VehicleDrive.mass_kg_of(VehicleSpecs.spec(m)) / 1000.0 - 0.001) == int(mlcs[m])
	check(mlc_ok and _near(float(ZoneBridges.TYPES[ZoneBridges.CONCRETE].mlc), 80.0, 0.01) and _near(float(ZoneBridges.TYPES[ZoneBridges.TRUSS].mlc), 40.0, 0.01)
		and _near(float(ZoneBridges.TYPES[ZoneBridges.FOOT].mlc), 2.0, 0.01) and ceili(VehicleDrive.mass_kg_of(VehicleSpecs.spec("abrams"), ["tusk2"]) / 1000.0 - 0.001) == 66,
		"2.8.5's load classes: the bridges 80 / 40 / 2; vehicles by mass with packages (the Abrams 62, with TUSK II 66)")
	check(VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.ROCK, 1.0, 15.0 / 3.6, 0.0) > 0.0 and VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.GRASS, 1.0, 15.0 / 3.6, 0.0) == 0.0
		and VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.GRASS, 1.0, 15.0 / 3.6, 25.0) > 0.0 and VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.ROCK, 1.0, 5.0 / 3.6, 0.0) == 0.0
		and VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.ROCK, 0.3, 15.0 / 3.6, 0.0) == 0.0 and _near(VehicleDrive.throw_risk(VehicleSpecs.spec("bradley"), VehicleDrive.RUBBLE, 1.0, 20.0 / 3.6, 0.0), 0.005, 0.0001),
		"thrown tracks (2.8.3): a hard pivot over 10 km/h on rock or rubble, or on a side slope over 20 deg, 0.5% a second; not on grass, slowly, or turning gently")
	var t0 := VehicleDrive.track_turn(VehicleSpecs.spec("bradley"), VehicleDrive.DIRT, 0.0)
	var t30 := VehicleDrive.track_turn(VehicleSpecs.spec("bradley"), VehicleDrive.DIRT, 30.0 / 3.6)
	check(_near(t30, t0 * 0.5, 0.0001) and VehicleDrive.track_turn(VehicleSpecs.spec("bradley"), VehicleDrive.MUD, 0.0) < t0, "tracks turn on the spot at turn_deg_s x traction, half that at 30 km/h, slower on mud")


# --- The lab and helpers ---------------------------------------------------------------------------

func _build_lab() -> void:
	lab_y = level.terrain.max_height + LAB_UP_M
	var slab := _static(Vector3(0, lab_y - 1.0, 0), Vector3(LAB_HALF_M * 2.0, 2.0, LAB_HALF_M * 2.0))
	slab.name = "DriveLab"
	VehicleDrive.add_patch(level, Rect2(-LAB_HALF_M, -LAB_HALF_M, LAB_HALF_M * 2.0, LAB_HALF_M * 2.0), VehicleDrive.DIRT, Vector2(lab_y - 30.0, lab_y + 60.0))


func _static(centre: Vector3, size: Vector3, basis := Basis()) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.transform = Transform3D(basis, centre)
	level.add_child(body)
	_lab.append(body)
	return body


## A ramp on the lab floor from `at` (its foot, on the floor) up along `dir` (flat) at `deg`, `length`
## along the slope, `width` across, with a flat top `top_m` long; its ground `kind` patched on.
func _ramp(at: Vector3, dir: Vector3, deg: float, length: float, width: float, kind: StringName, top_m := 25.0) -> Array:
	var f := Vector3(dir.x, 0.0, dir.z).normalized()
	var s := Vector3.UP.cross(f).normalized()
	var rise := length * sin(deg_to_rad(deg))
	var run := length * cos(deg_to_rad(deg))
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for side: float in [-0.5, 0.5]:
		pts.append(s * width * side)
		pts.append(s * width * side + f * run)
		pts.append(s * width * side + f * run + Vector3.UP * rise)
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(at.x, lab_y, at.z)
	level.add_child(body)
	_lab.append(body)
	var top := _static(Vector3(at.x, lab_y, at.z) + f * (run + top_m * 0.5) + Vector3.UP * (rise - 0.5), Vector3(width, 1.0, top_m), Basis.looking_at(f))
	var a := Vector2(at.x, at.z)
	var e := a + Vector2(f.x, f.z) * (run + top_m)
	var r := Rect2(a, Vector2.ZERO).expand(e).grow(width * 0.5 + 1.0)
	VehicleDrive.add_patch(level, r, kind, Vector2(lab_y - 5.0, lab_y + rise + 10.0))
	return [body, top, rise, run]


## A plane on the lab tilted `deg` across x (rising toward +x) between x0 and x0 + `w`, z from z0 to
## z1; ground `kind`.
func _tilt(x0: float, w: float, z0: float, z1: float, deg: float, kind: StringName) -> StaticBody3D:
	var rise := w * tan(deg_to_rad(deg))
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for z: float in [z0, z1]:
		pts.append(Vector3(0, -0.5, z))
		pts.append(Vector3(w, -0.5, z))
		pts.append(Vector3(0, 0, z))
		pts.append(Vector3(w, rise, z))
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(x0, lab_y, 0)
	level.add_child(body)
	_lab.append(body)
	VehicleDrive.add_patch(level, Rect2(x0 - 2.0, minf(z0, z1) - 2.0, w + 4.0, absf(z1 - z0) + 4.0), kind, Vector2(lab_y - 5.0, lab_y + rise + 10.0))
	return body


func _clear_lab(bodies: Array) -> void:
	for b: Variant in bodies:
		if b is Node and is_instance_valid(b):
			_lab.erase(b)
			(b as Node).queue_free()


func _spawn(model: String, pos: Vector3, yaw_deg := 0.0, faction := &"player", basis := Basis()) -> Vehicle:
	_n += 1
	var b := basis if basis != Basis() else Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var v := layer.server_spawn(model, Transform3D(b, pos + b.y * 0.35), "", faction, "drv_%s_%d" % [model, _n])
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _physics(2)
	return v


func _lab_point(x: float, z: float) -> Vector3:
	return Vector3(x, lab_y, z)


func _crew(v: Vehicle, seats: Array) -> Array:
	var out: Array = []
	for seat: int in seats:
		_n += 1
		var s := level.spawn_soldier({"name": "DrvCrew%d" % _n, "person_name": "Crew %d" % _n, "faction": "friendly", "variant": "woodland",
			"pos": v.global_position + Vector3(12.0, 0.5, float(seat)), "loadout": [], "combat": 1.0, "discipline": 0.6, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().physics_frame
		v.server_enter(s, seat)
		out.append(s)
	await _seconds(0.3)
	return out


## The host's player at the wheel of `v`, driving `throttle`/`steer` for `seconds` of physics; calls
## `each` (if given) every physics frame, and stops early (braking) when it returns true.
func _drive(v: Vehicle, throttle: float, steer: float, seconds: float, each := Callable()) -> void:
	if not player.vitals.is_up() or player.vitals.is_dead():
		print("  (the player was hurt: %s; healed)" % player.vitals.last_cause)
		player.vitals.server_reset_health()
	if v.driver() != player:
		v.server_enter(player, v.driver_seat())
	for i in ceili(seconds * Engine.physics_ticks_per_second):
		v.request_drive(throttle, steer, throttle == 0.0 and steer == 0.0)
		await get_tree().physics_frame
		if each.is_valid() and bool(each.call()):
			for k in 90:
				v.request_drive(0.0, 0.0, true)
				await get_tree().physics_frame
			return


func _clear(v: Vehicle, people: Array = []) -> void:
	if is_instance_valid(v):
		if v.logistics:
			v.logistics.server_stop_jobs()
			v.logistics.server_unhook()
		for s: Soldier in v.occupants():
			v.server_exit(s)
		v.server_stop()
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	player.global_position = _lab_point(0, 0) + Vector3(0, 0.2, LAB_HALF_M - 5.0)
	await _physics(3)


static func _yaw(n: Node3D) -> float:
	var f := -n.global_basis.z
	return atan2(-f.x, -f.z)


static func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Waits `s` seconds of physics (the sim can run slower than the wall clock on a loaded machine).
func _seconds(s: float) -> void:
	for i in ceili(s * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


## Physics frames since `f0`, as seconds.
static func _since(f0: int) -> float:
	return float(Engine.get_physics_frames() - f0) / Engine.physics_ticks_per_second


# --- Zone ----------------------------------------------------------------------------------------

func _def(seed_value: int) -> Dictionary:
	return ZoneDef.normalize(ZoneDef.generate(seed_value, SIZE_M).merged({"terrain": "river_valley", "id": "test_armourdrive", "name": "Armour drive test"}, true))


static func _flat(def: Dictionary) -> Array:
	var flat: Array = []
	for m: Dictionary in def.modules:
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		flat.append(Rect2(p - half, half * 2.0))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return flat


func _pick_def() -> Dictionary:
	for seed_value in SEEDS:
		var def := _def(seed_value)
		var t := ZoneTerrain.new()
		t.generate(def, _flat(def))
		var kinds := {}
		for c: Dictionary in t.water.crossings if t.water else []:
			var key := String(c.kind)
			if key == ZoneBridges.FORD and String((t.water.bodies[int(c.body)] as Dictionary).kind) == "river":
				key = "river_ford"
			kinds[key] = true
		t.free()
		if kinds.has(ZoneBridges.CONCRETE) and kinds.has(ZoneBridges.TRUSS) and kinds.has("river_ford"):
			return def
	check(false, "a seed among %s gives a river with a concrete and a truss bridge and a ford" % [SEEDS])
	return {}


func _bridge(type: String) -> int:
	for bi in water.bridges.bridges.size():
		if String(water.bridges.bridges[bi].type) == type:
			return bi
	return -1


## Bridge `bi`'s span over the deepest water.
func _water_span(bi: int) -> int:
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var best := 0
	var deepest := -INF
	for k in (b.spans as Array).size():
		var span: Dictionary = b.spans[k]
		var mid := xf * Vector3(0, 0, (float(span.z0) + float(span.z1)) * 0.5)
		var d := water.depth_at(mid.x, mid.z)
		if d > deepest:
			deepest = d
			best = k
	return best


func _river() -> int:
	for bi in water.bodies.size():
		if String((water.bodies[bi] as Dictionary).kind) == "river":
			return bi
	return -1


## A spot in the river `depth` m deep (within `tol`), on ground no steeper than `max_deg`, well off any
## crossing, the zone's edge and the spots in `avoid` (40 m): [ground point, the flow's direction,
## the way to the nearer bank (Vector3s)], or [].
func _spot_at_depth(depth: float, tol := 0.08, max_deg := 14.0, avoid: Array = []) -> Array:
	var ri := _river()
	if ri < 0:
		return []
	var r: Dictionary = water.bodies[ri]
	var lo := int(r.lo)
	var hi := int(r.hi)
	for k in range(0, hi - lo, 2):
		var i := (lo + hi) / 2 + (k / 2 if k % 2 == 0 else -k / 2)
		var at := water.sample_at(ri, i)
		var p: Vector2 = at.pos
		if maxf(absf(p.x), absf(p.y)) > SIZE_M * 0.5 - 250.0 or _near_crossing(ri, i, 70.0):
			continue
		var tan2 := ZoneWater.tangent(r, i)
		var across := Vector2(-tan2.y, tan2.x)
		for side: float in [1.0, -1.0]:
			for step in 40:
				var q := p + across * side * step * 0.5
				var d := water.depth_at(q.x, q.y)
				if absf(d - depth) <= tol and level.terrain.normal_at(q.x, q.y).y >= cos(deg_to_rad(max_deg)) \
						and avoid.all(func(a: Vector3) -> bool: return Vector2(a.x - q.x, a.z - q.y).length() > 40.0):
					return [Vector3(q.x, level.terrain.height_at(q.x, q.y), q.y), Vector3(tan2.x, 0.0, tan2.y), Vector3(across.x, 0.0, across.y) * side]
	return []


func _near_crossing(bi: int, u: float, m: float) -> bool:
	for c: Dictionary in water.crossings:
		if int(c.body) == bi and absf(float(c.u) - u) * ZoneWater.STEP_M < m + ZoneWater.FORD_HALF_M * 2.0:
			return true
	return false


# --- The ground ------------------------------------------------------------------------------------

func _test_ground() -> void:
	print("The ground under a vehicle (2.8.1: ZoneTerrain.ground_at, decks, patches)")
	var t := level.terrain
	var road := ""
	for r: Array in level.def.get("roads", []):
		var a := Vector2(float(r[0][0]), float(r[0][1]))
		var e := Vector2(float(r[1][0]), float(r[1][1]))
		var mid := (a + e) * 0.5
		if water.depth_at(mid.x, mid.y) <= 0.0 and water.bridges.deck_at(Vector3(mid.x, t.height_at(mid.x, mid.y), mid.y)).x < 0:
			road = "%s on a %s road" % [t.ground_at(mid.x, mid.y), String(r[2]) if r.size() > 2 else "dirt"]
			if (String(r[2]) if r.size() > 2 else "dirt") == "dirt":
				road = road if t.ground_at(mid.x, mid.y) == &"dirt" else "WRONG " + road
			else:
				road = road if t.ground_at(mid.x, mid.y) == &"asphalt" else "WRONG " + road
			break
	var deep := _spot_at_depth(1.5, 0.3)
	var c := {}
	for cr: Dictionary in water.crossings:
		if String(cr.kind) == ZoneBridges.FORD and String((water.bodies[int(cr.body)] as Dictionary).kind) == "river":
			c = cr
	var bi := _bridge(ZoneBridges.CONCRETE)
	var deck: Transform3D = water.bridges.bridges[bi].xform
	var bed: StringName = t.ground_at((deep[0] as Vector3).x, (deep[0] as Vector3).z) if not deep.is_empty() else &""
	var ford: StringName = t.ground_at((c.pos as Vector2).x, (c.pos as Vector2).y) if not c.is_empty() else &""
	var on_deck := VehicleDrive.ground_at(level, deck.origin)
	var grass := &""
	for k in 60:
		var q := Vector2.from_angle(k * 0.9) * (200.0 + k * 9.0)
		if water.surface_at(q.x, q.y) == -INF and t.normal_at(q.x, q.y).y > 0.95 and t.road_weight(q.x, q.y) <= 0.0 and not level.terrain.pads.any(func(pd: Array) -> bool: return (pd[0] as Rect2).grow(10.0).has_point(q)):
			grass = t.ground_at(q.x, q.y)
			break
	check(road != "" and not road.begins_with("WRONG") and bed == VehicleDrive.MUD and ford == VehicleDrive.DIRT and on_deck == VehicleDrive.ASPHALT and grass == VehicleDrive.GRASS,
		"%s; the river bed %s, the ford's track %s, the concrete deck %s, open ground %s" % [road, bed, ford, on_deck, grass])
	var lab := VehicleDrive.ground_at(level, _lab_point(0, 0) + Vector3.UP * 0.2)
	check(lab == VehicleDrive.DIRT and VehicleDrive.ground_at(level, _lab_point(0, 0) - Vector3.UP * 200.0) != &"" , "the lab's patch reads dirt on the slab only (%s)" % lab)


# --- Power and traction ----------------------------------------------------------------------------

## The seconds from rest to `kmh` by 2.8.2's formula on flat ground `g` (1D, 1/60 s steps).
static func _predict_time(model: String, g: StringName, kmh: float) -> float:
	var s := VehicleSpecs.spec(model)
	var m := float(s.mass_kg)
	var mu := Vehicle.GRIP * VehicleDrive.traction(String(s.kind), g)
	var rr := VehicleDrive.rolling(s, g)
	var v := 0.0
	var t := 0.0
	var top := float(s.top_speed_kmh) / 3.6
	while v < kmh / 3.6 and t < 60.0:
		var curve := sqrt(clampf(1.0 - v / top, 0.0, 1.0))
		var f := minf(VehicleDrive.drive_force(VehicleDrive.power_w(s), m, v, rr, 0.0, float(s.accel_ms2)) * curve, mu * m * 9.8) - rr * m * 9.8 - VehicleDrive.aero_drag(s, v)
		v += f / m / 60.0
		t += 1.0 / 60.0
	return t


func _test_acceleration() -> void:
	print("Acceleration by power to weight (2.8.2), on the lab's dirt")
	var got := {}
	var x := -120.0
	for model: String in ["technical", "matv", "maxxpro", "bradley", "abrams"]:
		var v := await _spawn(model, _lab_point(x, 100.0), 0.0)
		await _seconds(1.0)
		var f0 := Engine.get_physics_frames()
		var reached := [-1.0]
		await _drive(v, 1.0, 0.0, 14.0, func() -> bool:
			if reached[0] < 0.0 and v.forward_speed() * 3.6 >= 30.0:
				reached[0] = _since(f0)
			return reached[0] >= 0.0)
		got[model] = [reached[0], _predict_time(model, VehicleDrive.DIRT, 30.0)]
		await _clear(v)
		x += 60.0
	var line := PackedStringArray()
	var ok := true
	for m: String in got:
		line.append("%s %.1f s (predicted %.1f)" % [m, float(got[m][0]), float(got[m][1])])
		ok = ok and float(got[m][0]) > 0.0 and absf(float(got[m][0]) - float(got[m][1])) <= maxf(float(got[m][1]) * 0.3, 0.8)
	check(ok and float(got.technical[0]) < float(got.matv[0]) and float(got.matv[0]) < float(got.bradley[0]),
		"0-30 km/h: %s; the light technical first, the MRAP before the IFV" % ", ".join(line))


func _test_climb() -> void:
	print("Climbing by power and traction (2.8.2): no grade hold; a wet hill stops a MaxxPro a dry one doesn't")
	var speeds := {}
	var x := -120.0
	for model: String in ["matv", "bradley", "abrams"]:
		var r := _ramp(_lab_point(x, 60.0), Vector3.FORWARD, 20.0, 45.0, 9.0, VehicleDrive.DIRT)
		var v := await _spawn(model, _lab_point(x, 72.0), 0.0)
		await _seconds(0.8)
		var samples: Array[float] = []
		await _drive(v, 1.0, 0.0, 30.0, func() -> bool:
			var pitch := rad_to_deg(asin(clampf(-v.global_basis.z.y, -1.0, 1.0)))
			if pitch > 17.0 and v.global_position.y > lab_y + float(r[2]) * 0.4 and v.global_position.y < lab_y + float(r[2]) * 0.9:
				samples.append(v.linear_velocity.length())
			return v.global_position.y - lab_y >= float(r[2]) - 0.6 and pitch < 5.0)
		var s := VehicleSpecs.spec(model)
		var rr := VehicleDrive.rolling(s, VehicleDrive.DIRT)
		var predict := minf(VehicleDrive.power_w(s) / (float(s.mass_kg) * 9.8 * (sin(deg_to_rad(20.0)) + rr * cos(deg_to_rad(20.0)))), float(s.top_speed_kmh) / 3.6)
		var mean := 0.0
		for q in samples:
			mean += q / maxf(samples.size(), 1)
		speeds[model] = [mean, predict, samples.size(), v.global_position.y - lab_y >= float(r[2]) - 0.6]
		await _clear(v)
		_clear_lab(r.slice(0, 2))
		x += 60.0
	var ok := true
	var line := PackedStringArray()
	for m: String in speeds:
		var e: Array = speeds[m]
		line.append("%s %.1f m/s (power says %.1f)%s" % [m, float(e[0]), float(e[1]), "" if bool(e[3]) else ", NOT at the top"])
		ok = ok and int(e[2]) > 10 and bool(e[3]) and absf(float(e[0]) - float(e[1])) <= float(e[1]) * 0.25
	check(ok and float(speeds.abrams[0]) > float(speeds.bradley[0]), "a 20 deg dirt hill at full power, the speed P / (m g (sin + rr cos)): %s; the Abrams (18 kW/t) out-climbs the Bradley (15)" % ", ".join(line))
	# Dry against muddy (the same 15 deg hill).
	var out := {}
	for kind: StringName in [VehicleDrive.DIRT, VehicleDrive.MUD]:
		for model: String in ["maxxpro", "abrams"]:
			var r := _ramp(_lab_point(x, 60.0), Vector3.FORWARD, 15.0, 40.0, 9.0, kind)
			var v := await _spawn(model, _lab_point(x, 70.0), 0.0)
			await _seconds(0.8)
			var best := [0.0]
			await _drive(v, 1.0, 0.0, 30.0, func() -> bool:
				best[0] = maxf(float(best[0]), (v.global_position.y - lab_y) / float(r[2]))
				return float(best[0]) > 0.98)
			out["%s_%s" % [model, kind]] = best[0]
			await _clear(v)
			_clear_lab(r.slice(0, 2))
			x += 30.0
	check(float(out.maxxpro_dirt) > 0.95 and float(out.maxxpro_mud) < 0.5 and float(out.abrams_mud) > 0.95,
		"15 deg: the MaxxPro tops it dry (%.0f%% of the way up) and not in mud (%.0f%%); the Abrams' tracks take the mud (%.0f%%)" % [float(out.maxxpro_dirt) * 100.0, float(out.maxxpro_mud) * 100.0, float(out.abrams_mud) * 100.0])


func _test_turning() -> void:
	print("Tracked turning (2.8.3): neutral steer, half the rate by 30 km/h")
	var v := await _spawn("bradley", _lab_point(60.0, 100.0), 0.0)
	await _seconds(0.8)
	var yaw0 := [0.0]
	var pivot := v.global_position
	await _drive(v, 0.0, 1.0, 1.2)
	yaw0[0] = _yaw(v)
	await _drive(v, 0.0, 1.0, 1.0)
	var spot_rate := absf(rad_to_deg(wrapf(_yaw(v) - float(yaw0[0]), -PI, PI))) / 1.0
	var drift := v.global_position.distance_to(pivot)
	await _drive(v, 0.0, 0.0, 1.0)
	await _drive(v, 1.0, 0.0, 12.0, func() -> bool: return v.forward_speed() * 3.6 > 30.0)
	await _drive(v, 1.0, 0.0, 0.2)
	var kmh := v.forward_speed() * 3.6
	var y1 := _yaw(v)
	var moving := [0.0]
	await _drive(v, 1.0, 1.0, 1.0, func() -> bool:
		moving[0] = v.forward_speed() * 3.6
		return false)
	var move_rate := absf(rad_to_deg(wrapf(_yaw(v) - y1, -PI, PI))) / 1.0
	var predict0 := rad_to_deg(VehicleDrive.track_turn(v.spec, VehicleDrive.DIRT, 0.0))
	var predict_m := rad_to_deg(VehicleDrive.track_turn(v.spec, VehicleDrive.DIRT, float(moving[0]) / 3.6))
	check(spot_rate > 12.0 and drift < 1.5 and move_rate < spot_rate and spot_rate <= predict0 * 1.05 and move_rate <= predict_m * 1.05,
		"the Bradley pivots on the spot at %.0f deg/s (moving %.1f m; commanded %.0f, the stations' side scrub takes the rest) and turns at %.0f deg/s at %.0f km/h (commanded %.0f)" % [spot_rate, drift, predict0, move_rate, float(moving[0]), predict_m])
	await _clear(v)


# --- Slopes ----------------------------------------------------------------------------------------

func _test_ai_slopes() -> void:
	print("The AI driver's slope limits (2.8.3: side slopes under 60% of the tip angle)")
	var res := {}
	for deg: float in [30.0, 12.0]:
		var plane := _tilt(-60.0, 26.0, -40.0, -110.0, deg, VehicleDrive.DIRT)
		var v := await _spawn("matv", _lab_point(-58.5, -20.0), 0.0)
		await _seconds(0.6)
		var start := v.global_position
		v.server_follow_path(PackedVector3Array([_lab_point(-58.5, -70.0), _lab_point(-58.5, -120.0)]), 20.0)
		await _seconds(6.0)
		res[deg] = [start.distance_to(v.global_position), v.drive.last_stop, v.global_position.z]
		await _clear(v)
		_clear_lab([plane])
	var tip := VehicleDrive.tip_deg(VehicleSpecs.spec("matv"))
	check(String(res[30.0][1]).begins_with("side slope") and float(res[30.0][2]) > -40.0 and String(res[12.0][1]) == "" and float(res[12.0][2]) < -37.0,
		"an AI M-ATV stops short of a 30 deg side slope (over %.0f, 60%% of its %.0f deg tip: '%s', %.0f m on) and drives on onto a 12 deg one ('%s', %.0f m on)" % [tip * 0.6, tip, res[30.0][1], float(res[30.0][0]), res[12.0][1], float(res[12.0][0])])
	var steep := TerrainRoute.slope_ok(_dummy("maxxpro"), 25.0, 0.0, VehicleDrive.MUD)
	check(TerrainRoute.slope_ok(_dummy("maxxpro"), 25.0, 10.0, VehicleDrive.DIRT) and not steep and not TerrainRoute.slope_ok(_dummy("maxxpro"), 5.0, 26.0, VehicleDrive.DIRT)
		and TerrainRoute.slope_ok(_dummy("abrams"), 5.0, 30.0, VehicleDrive.DIRT), "TerrainRoute.slope_ok (A9): a MaxxPro takes 25 deg on dirt but not in mud, nor a 26 deg side slope the Abrams can")


var _dummies := {}


## A vehicle of `model` for the pure API (not in the tree).
func _dummy(model: String) -> Vehicle:
	if not _dummies.has(model):
		_dummies[model] = Vehicle.create(model)
	return _dummies[model]


func _test_tilt_table() -> void:
	print("Tilt table (2.8.3, 9.3: a rollover within 10% of the predicted angle, and not before)")
	for model: String in ["matv", "maxxpro"]:
		var tip := VehicleDrive.tip_deg(VehicleSpecs.spec(model))
		var deg := floorf(tip * 0.78)
		var last_up := -1.0
		var rolled_at := -1.0
		var early := false
		while deg <= tip * 1.12 and rolled_at < 0.0:
			var plane := _tilt(-140.0, 24.0, -20.0, -60.0, deg, VehicleDrive.ASPHALT)
			var x := -140.0 + 12.0
			var y := lab_y + 12.0 * tan(deg_to_rad(deg))
			var b := Basis(Vector3.BACK, deg_to_rad(deg))  # up leaning to -x: the slope rises toward +x
			var v := await _spawn(model, Vector3(x, y, -40.0), 0.0, &"player", b)
			v.linear_velocity = Vector3.ZERO
			await _seconds(2.2)
			var roll := VehicleDrive.roll_deg(v)
			if v.drive.is_rolled():
				rolled_at = deg
			else:
				last_up = maxf(last_up, roll)
				if roll > tip * 1.1:
					early = true
			await _clear(v)
			_clear_lab([plane])
			deg += 1.5
		check(rolled_at > 0.0 and last_up > 0.0 and last_up >= tip * 0.9 and rolled_at <= tip * 1.1 and not early,
			"%s (tip %.1f deg): stood with its body leaning %.1f deg on the steepest table it held, rolled over on %.1f deg" % [model, tip, last_up, rolled_at])


# --- Rollover, righting, the tow ------------------------------------------------------------------

func _test_rollover_and_righting() -> void:
	print("A rollover (2.8.3): the crew hurt, immobile; righted by a tow of half its mass; a tow up a slope (F-272)")
	var o := _lab_point(100.0, -40.0)
	var v := await _spawn("matv", o, 0.0)
	var crew := await _crew(v, [0, 4])
	await _seconds(0.5)
	var hud := [false]
	v.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(95.0)), o + Vector3(0, 1.4, 0))  # pushed over onto its side
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.sleeping = false
	await _until(func() -> bool: return v.drive.is_rolled(), 4.0)
	hud[0] = "ROLLED OVER: NEEDS A TOW" in VehicleHud.alerts(v, 0)
	var driver := crew[0] as Soldier
	var gunner := crew[1] as Soldier
	check(v.drive.is_rolled() and not v.can_drive() and v.drive.blocked() == "Rolled over" and bool(hud[0]),
		"on its side past its tip angle: rolled over, won't drive, the HUD says so")
	check(String(driver.vitals.last_cause.get("cause", "")) == "fall (1.6 m)" and String(gunner.vitals.last_cause.get("cause", "")) == "fall (4.8 m)",
		"the crew hurt through Vitals: the belted driver a %s, the gunner in his open hatch a %s" % [driver.vitals.last_cause.get("cause", "-"), gunner.vitals.last_cause.get("cause", "-")])
	for s: Soldier in crew:
		v.server_exit(s)
		s.queue_free()
	var light := await _spawn("technical", o + Vector3(9, 0, -8), 0.0)
	var tower := await _spawn("maxxpro", o + Vector3(0, 0, -9.8), 0.0)
	await _seconds(1.5)
	var lg := v.logistics
	check(lg.tow_problem(light).contains("too light") and lg.tow_problem(tower) == "", "the technical (2.4 t) can't right a 12.5 t M-ATV (%s); the MaxxPro can" % lg.tow_problem(light))
	var service: VehicleActionPoint = null
	for p in v.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == VehicleActionPoint.SERVICE:
			service = p
	player.global_position = service.global_position + Vector3.UP * 0.2
	player.threat_time = -1000.0
	await _physics(2)
	var why := v.server_start_job(player, "tow", StringName(tower.vehicle_id), &"")
	var job := lg.job_of(player)
	check(why == "" and not job.is_empty() and _near(v.job_left(player), 60.0, 0.5), "the tow at its service point: 60 s to hook up (%s)" % why)
	if not job.is_empty():
		job.done = float(job.need) - 0.05
	await _until(func() -> bool: return v.drive.is_righting() or not v.drive.is_rolled(), 3.0)
	var started := v.drive.is_righting()
	var f0 := Engine.get_physics_frames()
	await _until(func() -> bool: return not v.drive.is_rolled(), 40.0)
	var took := _since(f0)
	await _seconds(1.0)
	check(started and not v.drive.is_rolled() and VehicleDrive.tilt_deg(v) < 15.0 and lg.towed(), "hooked up, the MaxxPro pulls it back onto its wheels in %.1f s (tilt %.0f deg), still on the tow" % [took, VehicleDrive.tilt_deg(v)])
	await _clear(light)
	# The tow up a slope (F-272): the M-ATV, its wheels shot out, behind the MaxxPro up 7 deg of dirt.
	for wid: String in ["wheel_fl", "wheel_fr", "wheel_rl"]:
		v.modules.server_set(wid, 0.0)
	player.global_position = _lab_point(0, 0) + Vector3(0, 0.2, LAB_HALF_M - 5.0)
	var r := _ramp(tower.global_position + Vector3(0, 0, -6.0), Vector3.FORWARD, 7.0, 40.0, 10.0, VehicleDrive.DIRT)
	var start := v.global_position
	tower.server_drive_to(tower.global_position + Vector3(0, 0, -50.0), 15.0)
	var bar := [false]
	var pitch := [0.0]
	for i in 22 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		bar[0] = bar[0] or lg.tow_bar() != null
		pitch[0] = maxf(float(pitch[0]), rad_to_deg(asin(clampf(-v.global_basis.z.y, -1.0, 1.0))))
	var gap := tower.to_global(VehicleLogistics.hitch(tower, true)).distance_to(v.to_global(VehicleLogistics.hitch(v, false)))
	var climbed := v.global_position.y - start.y
	check(climbed > 2.0 and gap < 5.5 and float(pitch[0]) > 5.0 and bool(bar[0]), "towed up the 7 deg hill: %.1f m higher, the hitches %.1f m apart, pitched %.0f deg on the way, the bar drawn between them" % [climbed, gap, float(pitch[0])])
	tower.server_stop()
	set_meta(&"tow_pair", [v.vehicle_id, tower.vehicle_id])
	_clear_lab(r.slice(0, 2))


func _test_bog() -> void:
	print("Bogging (2.8.1): an MRAP stopped on a muddy slope is stuck until towed")
	var r := _ramp(_lab_point(60.0, -60.0), Vector3.FORWARD, 6.0, 30.0, 10.0, VehicleDrive.MUD)
	var v := await _spawn("maxxpro", _lab_point(60.0, -63.0) + Vector3(0, 0.6, 0), 0.0, &"player", Basis(Vector3.RIGHT, deg_to_rad(6.0)))
	await _seconds(0.6)
	await _drive(v, 1.0, 0.0, 9.0)
	check(v.drive.is_bogged() and not v.can_drive() and "BOGGED: NEEDS A TOW" in VehicleHud.alerts(v, 0), "a MaxxPro in mud on 6 deg spins down to a stop: bogged (%s)" % v.drive.blocked())
	v.server_exit(player)
	var tower := await _spawn("abrams", v.global_position + Vector3(0, 0, -10.5), 0.0)
	await _seconds(1.0)
	v.logistics.server_hook(tower)
	tower.server_drive_to(tower.global_position + Vector3(0, 0, -30.0), 12.0)
	await _until(func() -> bool: return not v.drive.is_bogged(), 15.0)
	check(not v.drive.is_bogged(), "pulled out by the Abrams on a tow: free again")
	tower.server_stop()
	await _clear(tower)
	await _clear(v)
	_clear_lab(r.slice(0, 2))


# --- Water -----------------------------------------------------------------------------------------

func _test_fording() -> void:
	print("Fording depth per vehicle (2.8.4): the M-ATV through 1.1 m, the MaxxPro stalled, its engine drowning")
	var spot := _spot_at_depth(1.1, 0.08)
	check(not spot.is_empty(), "a stretch of river 1.1 m deep")
	if spot.is_empty():
		return
	var at: Vector3 = spot[0]
	var shore: Vector3 = spot[2]
	var yaw := atan2(-shore.x, -shore.z)  # facing the nearer bank
	var m := await _spawn("matv", at + Vector3(0, 0.3, 0), rad_to_deg(yaw))
	await _seconds(1.5)
	var d_m := VehicleDrive.ford_depth(m)
	var alerts_m := VehicleHud.alerts(m, 0)
	var ok_m := not m.drive.is_stalled() and m.can_drive()
	var start := m.global_position
	await _drive(m, 1.0, 0.0, 3.0)
	var bank := start.distance_to(m.global_position)
	m.global_transform = Transform3D(Basis(Vector3.UP, atan2(-(spot[1] as Vector3).x, -(spot[1] as Vector3).z)), at + Vector3(0, 0.3, 0))  # along the river
	m.linear_velocity = Vector3.ZERO
	await _seconds(1.0)
	start = m.global_position
	await _drive(m, 1.0, 0.0, 2.5)
	var moved := start.distance_to(m.global_position)
	check(ok_m and moved > 0.5 and AavWater.throttle(m, AavWater.depth(m), 1.0) == 1.0 and "FORD %.1f / 1.4 m" % d_m in alerts_m,
		"the M-ATV in %.2f m of water (fords 1.37): its engine runs and it drives on along the river bed (%.1f m in 2.5 s), HUD %s" % [d_m, moved, alerts_m])
	check(bank < 2.0, "but the mud bank holds it in (%.1f m up it in 3 s): a column crosses at the fords and bridges (2.8.4)" % bank)
	expect["ford_line"] = "FORD %.1f / 1.4 m" % d_m
	await _clear(m)
	set_meta(&"used", [at])
	var x := await _spawn("maxxpro", at + Vector3(0, 0.3, 0), rad_to_deg(yaw))
	await _seconds(1.2)
	var alerts_x := VehicleHud.alerts(x, 0)
	check(x.drive.is_stalled() and not x.can_drive() and "STALLED: TOO DEEP" in alerts_x and AavWater.throttle(x, AavWater.depth(x), 1.0) == 0.0,
		"the MaxxPro in %.2f m (fords 0.9): its engine stalls at once (%s)" % [VehicleDrive.ford_depth(x), alerts_x])
	await _seconds(5.0)
	var damaged := x.modules.health_of("engine")
	x.drive.ingest_s = 19.6
	await _seconds(0.8)
	check(damaged <= VehicleModules.DAMAGED_SHARE and damaged > 0.0 and x.modules.health_of("engine") <= 0.0, "its engine damaged after 5 s under (%.2f), destroyed after 20 s" % damaged)
	expect["stalled"] = x.vehicle_id
	set_meta(&"stalled", x)


func _test_flooding() -> void:
	print("Flooding (2.8.4, F-240): water over the roof floods the crew compartment; the crew gets out")
	var spot := _spot_at_depth(2.05, 0.15, 25.0, get_meta(&"used", []))
	check(not spot.is_empty(), "the river's channel, about 2 m deep")
	if spot.is_empty():
		return
	var at: Vector3 = spot[0]
	set_meta(&"used", (get_meta(&"used", []) as Array) + [at])
	var v := await _spawn("technical", _lab_point(140.0, 150.0), 0.0)
	var crew := await _crew(v, [0])
	check(v.occupant(0) == crew[0], "its driver aboard on dry ground")
	v.global_transform = Transform3D(Basis(), at + Vector3(0, 0.3, 0))  # then into the channel
	v.linear_velocity = Vector3.ZERO
	await _until(func() -> bool: return v.drive.is_flooded(), 6.0)
	await _seconds(0.5)
	check(v.drive.is_flooded() and v.occupant(0) == null and Vehicle.ride_of(crew[0]) == null and "FLOODED: GET OUT" in VehicleHud.alerts(v, 0) and not v.can_drive(),
		"a technical in %.1f m (its roof 1.72 m): flooded, its driver out in the water" % VehicleDrive.ford_depth(v))
	var y0 := v.global_position.y
	await _seconds(3.0)
	check(v.global_position.y <= y0 + 0.05, "and it's going nowhere but down (%.2f m)" % (v.global_position.y - y0))
	expect["flooded"] = v.vehicle_id
	for s: Soldier in crew:
		s.queue_free()


func _test_swimming() -> void:
	print("The AAV swims (2.8.4): its speed, its waterjets (A2's modules), the current, holed and sinking")
	var spot := _spot_at_depth(2.1, 0.12, 8.0, get_meta(&"used", []))
	check(not spot.is_empty(), "another deep stretch for the AAV, mid-channel")
	if spot.is_empty():
		return
	var at: Vector3 = spot[0]
	var flow: Vector3 = spot[1]
	var yaw := atan2(-flow.x, -flow.z)  # heading downstream along the river (it's too narrow to cross far)
	var v := await _spawn("aav7", at + Vector3(0, 0.6, 0), rad_to_deg(yaw) + 180.0)  # nose upstream
	await _seconds(2.0)
	var current := water.flow_at(at.x, at.z)
	var p0 := v.global_position
	await _seconds(5.0)
	var drift := (v.global_position - p0)
	var along := Vector3(drift.x, 0, drift.z).dot(current.normalized())
	check(AavWater.afloat(v) and "AFLOAT" in VehicleHud.alerts(v, 0) and current.length() > 0.1 and along > current.length() * 5.0 * 0.4,
		"afloat in the channel; with no throttle the %.1f m/s current carries it %.1f m downstream in 5 s" % [current.length(), along])
	var best := [0.0]
	await _drive(v, 1.0, 0.0, 9.0, func() -> bool:
		var rel := v.linear_velocity - water.flow_at(v.global_position.x, v.global_position.z)
		best[0] = maxf(float(best[0]), rel.dot(-v.global_basis.z))
		return false)
	var swim := AavWater.swim_ms(v)
	check(float(best[0]) > swim * 0.75 and float(best[0]) < swim * 1.15, "full ahead against the stream: %.1f m/s through the water (swims %.1f)" % [float(best[0]), swim])
	await _drive(v, 0.0, 0.0, 2.0)
	v.modules.server_set("waterjet_l", 0.0)
	v.modules.server_set("waterjet_r", 0.0)
	var jets := [0.0]
	var rel0 := (v.linear_velocity - water.flow_at(v.global_position.x, v.global_position.z)).dot(-v.global_basis.z)
	await _drive(v, 1.0, 0.0, 6.0, func() -> bool:
		var rel := v.linear_velocity - water.flow_at(v.global_position.x, v.global_position.z)
		jets[0] = rel.dot(-v.global_basis.z)
		return false)
	check(float(jets[0]) < swim * 0.35 and float(jets[0]) <= rel0 + 0.05 and AavWater.jet_share(v).x == 0.0, "both waterjets destroyed: full ahead gives no push (%.1f m/s through the water after 6 s, from %.1f)" % [float(jets[0]), rel0])
	v.modules.server_set("waterjet_l", 1.0)
	v.modules.server_set("waterjet_r", 1.0)
	v.server_exit(player)
	var crew := await _crew(v, [1])
	v.drive.server_hit({"penetrated": true, "position": v.to_global(Vector3(1.6, 0.8, 0.5))})
	v.drive.server_hit({"penetrated": true, "position": v.to_global(Vector3(-1.6, 0.9, -1.0))})
	v.drive.server_hit({"penetrated": true, "position": v.to_global(Vector3(0.0, 2.6, 0.0))})  # the roof: above the water
	await _seconds(2.0)
	var share := v.drive.flood_share()
	check(v.drive.holes == 2 and share > 0.0 and ("FLOODING %d%%" % roundi(share * 100.0)) in VehicleHud.alerts(v, 0) or v.drive.holes == 2 and share > 0.0,
		"two holes under its waterline (and one over it): taking water faster than the pumps (%.1f%% of what sinks it)" % (share * 100.0))
	v.drive.flood_l = VehicleDrive.num("ford", "sink_l", 9000.0) - 20.0
	await _until(func() -> bool: return v.drive.is_flooded(), 4.0)
	var y0 := v.global_position.y
	await _seconds(4.0)
	check(v.drive.is_flooded() and v.occupant(1) == null and v.global_position.y < y0 - 0.2, "full: it floods, the crew gets out, it sinks (%.1f m)" % (v.global_position.y - y0))
	for s: Soldier in crew:
		s.queue_free()
	await _clear(v)


# --- Bridges ---------------------------------------------------------------------------------------

## The way across bridge `bi`: [from, to] on the ground `out` m past each end.
func _across(bi: int, out: float) -> Array:
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var reach := float(b.length) * 0.5 + out
	return [level.ground_point(xf * Vector3(0, 0, -reach)), level.ground_point(xf * Vector3(0, 0, reach))]


func _test_bridges() -> void:
	print("Bridges by load class (2.8.5, F-255)")
	var wb := water.bridges
	var ti := _bridge(ZoneBridges.TRUSS)
	var ci := _bridge(ZoneBridges.CONCRETE)
	var tb: Dictionary = wb.bridges[ti]
	var txf: Transform3D = tb.xform
	var half := float(tb.length) * 0.5
	var yaw := rad_to_deg(atan2(-txf.basis.z.x, -txf.basis.z.z))  # facing along +z of the bridge
	var ends := _across(ti, 18.0)
	# The HUD approaching it.
	var a := await _spawn("abrams", ends[0], yaw)
	var b := await _spawn("bradley", level.ground_point(txf * Vector3(0, 0, -half - 32.0)), yaw)
	await _seconds(1.0)
	var la := VehicleHud.bridge_line(a)
	var lb := VehicleHud.bridge_line(b)
	check(la == "BRIDGE MLC 40: TOO HEAVY" and lb == "BRIDGE MLC 40" and "BRIDGE MLC 40: TOO HEAVY" in VehicleHud.alerts(a, 0),
		"approaching the truss bridge: the Abrams' HUD '%s', the Bradley's '%s'" % [la, lb])
	# A9's API and the roads.
	var over := PackedVector3Array([txf * Vector3(0, 0, -half - 4.0), txf * Vector3(0, 0, half + 4.0)])
	var pa := TerrainRoute.path_problem(a, over)
	var pb := TerrainRoute.path_problem(b, over)
	var roads_a := TerrainRoute.roads_for(a, level.def)
	var roads_b := TerrainRoute.roads_for(b, level.def)
	var kept_over := false
	for r: Array in roads_a.get("roads", []):
		var p := Geometry2D.get_closest_points_between_segments(Vector2(float(r[0][0]), float(r[0][1])), Vector2(float(r[1][0]), float(r[1][1])),
			Vector2((txf * Vector3(0, 0, -half)).x, (txf * Vector3(0, 0, -half)).z), Vector2((txf * Vector3(0, 0, half)).x, (txf * Vector3(0, 0, half)).z))
		kept_over = kept_over or (p[0] as Vector2).distance_to(p[1]) < 1.0
	check(not TerrainRoute.can_cross(a, ti) and TerrainRoute.can_cross(b, ti) and TerrainRoute.can_cross(a, ci) and String(pa.get("why", "")).begins_with("bridge MLC 40")
		and pb.is_empty() and not kept_over and (roads_a.roads as Array).size() < (level.def.roads as Array).size() and roads_b == level.def,
		"can_cross: the Abrams not the truss (40), the Bradley yes, the concrete (80) both; path_problem '%s'; the Abrams' roads leave out %d pieces over it, the Bradley's none" % [pa.get("why", ""), (level.def.roads as Array).size() - (roads_a.roads as Array).size()])
	# The AI keeps the Abrams off; the Bradley drives over.
	a.server_follow_path(PackedVector3Array([txf * Vector3(0, 0, -half - 3.0), txf * Vector3(0, 0, half + 3.0), ends[1]]), 15.0)
	await _seconds(9.0)
	var a_local := txf.affine_inverse() * a.global_position
	var reason := a.drive.last_stop
	check(a_local.z < -half + 1.0 and reason.begins_with("bridge MLC 40") and not wb.is_down(ti, 0), "the AI Abrams stops at the truss bridge's end (%.1f m short of the deck, '%s')" % [-half - a_local.z, reason])
	a.server_stop()
	await _clear(a)
	var hp_before := 0.0
	for s: Dictionary in tb.spans:
		hp_before += float(s.hp)
	var max_load := [0.0]
	b.server_follow_path(PackedVector3Array([txf * Vector3(0, 0, -half - 3.0), txf * Vector3(0, 0, half + 3.0), ends[1]]), 15.0)
	var t0 := Time.get_ticks_msec()
	while b.ai.status != "arrived" and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().physics_frame
		for key: String in wb.loads:
			if key.begins_with("%d_" % ti):
				max_load[0] = maxf(float(max_load[0]), float(wb.loads[key]))
	var hp_after := 0.0
	for s: Dictionary in tb.spans:
		hp_after += float(s.hp)
	var miss := Vector2(b.global_position.x - (ends[1] as Vector3).x, b.global_position.z - (ends[1] as Vector3).z).length()
	check(b.ai.status == "arrived" and miss < 8.0 and _near(float(max_load[0]), 30.0, 0.6) and _near(hp_after, hp_before, 0.001),
		"the Bradley (30 t) drives over the truss bridge (%s, %.1f m from its goal): the spans weighed it (%.1f t) and took no harm" % [b.ai.status, miss, float(max_load[0])])
	b.server_stop()
	await _clear(b)
	# The concrete bridge holds the Abrams; parked on the truss bridge, it drops the span.
	var cb: Dictionary = wb.bridges[ci]
	var ck := _water_span(ci)
	var cxf: Transform3D = cb.xform
	var cz := (float(cb.spans[ck].z0) + float(cb.spans[ck].z1)) * 0.5
	var on_c := await _spawn("abrams", cxf * Vector3(0, 0.2, cz), rad_to_deg(atan2(-cxf.basis.z.x, -cxf.basis.z.z)))
	await _seconds(6.0)
	check(wb.deck_at(on_c.global_position) == Vector2i(ci, ck) and _near(float(cb.spans[ck].hp), float(ZoneBridges.TYPES[ZoneBridges.CONCRETE].hp), 0.001) and not wb.is_down(ci, ck),
		"an Abrams (62 t) parked on the concrete bridge (MLC 80): it holds")
	await _clear(on_c)
	var tk := _water_span(ti)
	var tz := (float(tb.spans[tk].z0) + float(tb.spans[tk].z1)) * 0.5
	var on_t := await _spawn("abrams", txf * Vector3(0, 0.2, tz), yaw)
	var f1 := Engine.get_physics_frames()
	var worn := [false]
	await _until(func() -> bool:
		worn[0] = worn[0] or (not wb.is_down(ti, tk) and wb.span_mlc(ti, tk) < 40.0 - 1.0)
		return wb.is_down(ti, tk), 40.0)
	var took := _since(f1)
	check(wb.is_down(ti, tk) and bool(worn[0]) and took > 5.0 and took < 9.5 and _near(wb.span_mlc(ti, tk), 0.0, 0.001),
		"parked on the truss bridge (62 t on 40: 1.55x), the span weakens (its class falls with it) and gives way after %.1f s (8 s at 1.5x)" % took)
	await _seconds(2.0)
	await _clear(on_t)
	expect["truss_down"] = [ti, tk]
	# A worn span: its class follows its health.
	var wk := 0 if ck != 0 else mini(1, (cb.spans as Array).size() - 1)
	cb.spans[wk].hp = float(ZoneBridges.TYPES[ZoneBridges.CONCRETE].hp) * 0.5
	wb._send_hp(ci, wk, true)
	check(_near(wb.span_mlc(ci, wk), 40.0, 0.01), "blast damage to half its health halves a concrete span's class to %.0f" % wb.span_mlc(ci, wk))
	expect["worn"] = [ci, wk, wb.span_mlc(ci, wk)]


# --- Save and load -----------------------------------------------------------------------------------

func _test_save() -> void:
	print("Save and load: rolled over, flooded, bogged, water aboard, the tow, the bridges")
	var v := await _spawn("matv", _lab_point(-100.0, -140.0), 0.0)
	v.drive.rolled = true
	v.drive.flood_l = 120.0
	v.drive.holes = 1
	v.drive.ingest_s = 7.5
	var w := await _spawn("maxxpro", _lab_point(-80.0, -140.0), 0.0)
	w.drive.bogged = true
	w.drive.flooded = true
	var rec_v := v.to_save()
	var rec_w := w.to_save()
	for rec: Dictionary in [rec_v, rec_w]:
		for k: String in ["id", "pos", "rot"]:
			rec.erase(k)
	var v2 := layer.server_spawn("matv", Transform3D(Basis(), _lab_point(-100.0, -120.0) + Vector3.UP * 0.4), "", &"player", "", rec_v)
	var w2 := layer.server_spawn("maxxpro", Transform3D(Basis(), _lab_point(-80.0, -120.0) + Vector3.UP * 0.4), "", &"player", "", rec_w)
	await _physics(3)
	check(v2.drive.rolled and _near(v2.drive.flood_l, 120.0, 0.01) and v2.drive.holes == 1 and _near(v2.drive.ingest_s, 7.5, 0.01) and w2.drive.bogged and w2.drive.flooded,
		"a saved vehicle comes back rolled over, holed, with its water aboard and its drowned seconds; another bogged and flooded")
	# The tow (F-272).
	var pair: Array = get_meta(&"tow_pair", [])
	var towed := layer.find(String(pair[0])) if pair.size() == 2 else null
	if towed:
		var rec := towed.logistics.to_save()
		check(String(rec.get("tow_by", "")) == String(pair[1]), "a towed vehicle's save names its tower (%s)" % rec.get("tow_by", ""))
		towed.logistics.server_unhook()
		towed.logistics.from_save(rec)
		towed.logistics.server_rehook_saved()
		check(towed.logistics.towed() and VehicleLogistics.of(layer.find(String(pair[1]))).towing_one(), "and is hooked up again on the zone's restore")
	# The bridges: a dropped span and a worn one back from the zone save.
	check(GameState.save_zone(), "the zone saves")
	var saved: Dictionary = GameState.read_save(GameState.save_path())
	var fresh := ZoneTerrain.new()
	fresh.generate(level.def, _flat(level.def))
	add_child(fresh)
	fresh.water.bridges.server_restore(saved.get("bridges", {}))
	var td: Array = expect.get("truss_down", [0, 0])
	var worn: Array = expect.get("worn", [0, 0, 0.0])
	check(fresh.water.bridges.is_down(int(td[0]), int(td[1])) and _near(fresh.water.bridges.span_mlc(int(worn[0]), int(worn[1])), float(worn[2]), 0.01),
		"restored: the dropped truss span down (class 0), the worn concrete span at MLC %.0f" % fresh.water.bridges.span_mlc(int(worn[0]), int(worn[1])))
	fresh.queue_free()
	for x: Vehicle in [v, w, v2, w2]:
		await _clear(x)


# --- Budgets -----------------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Cost (9.3: the physics step unchanged): the drive step, the AI's care, the bridges' weighing, the wheels")
	var vs: Array[Vehicle] = []
	for i in 20:
		vs.append(await _spawn("matv" if i % 2 == 0 else "abrams", _lab_point(-150.0 + (i % 10) * 25.0, 130.0 - (i / 10) * 25.0), 0.0))
	await _seconds(1.0)
	var v := vs[0]
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		v.drive.server_step(1.0 / 60.0, 0.0, 0.0)
	var step_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 1000.0
	v.server_follow_path(PackedVector3Array([v.global_position + Vector3(0, 0, -30)]), 20.0)
	var input := {"throttle": 1.0, "steer": 0.3, "brake": false}
	t0 = Time.get_ticks_usec()
	for i in 600:
		v.drive.ai_guard(input, 1.0 / 60.0)
	var guard_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 600.0
	v.server_stop()
	var wb := water.bridges
	t0 = Time.get_ticks_usec()
	for i in 100:
		wb._load_step(0.0)
	var load_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 100.0
	var ab := vs[1]
	ab.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ab.freeze = true  # (its forces go nowhere: just the cost)
	t0 = Time.get_ticks_usec()
	for i in 300:
		ab._wheel_forces(1.0 / 60.0, 1.0, 0.2, false)
	var wheels_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	var slack := 1.0 if OS.has_environment("GITHUB_ACTIONS") else LOCAL_SLACK
	print("  (cost: drive step %.4f ms, AI care %.4f ms a tick, bridges' weighing %.3f ms with %d vehicles, an Abrams' wheels %.3f ms)" % [step_ms, guard_ms, load_ms, get_tree().get_nodes_in_group(Vehicle.GROUP).size(), wheels_ms])
	check(step_ms < STEP_BUDGET_MS * slack and guard_ms < GUARD_BUDGET_MS * slack and load_ms < LOAD_BUDGET_MS * slack and wheels_ms < WHEELS_BUDGET_MS * slack,
		"a vehicle's drive step %.4f ms (budget %.2f), the AI driver's care %.4f ms a tick (%.2f), the bridges' weighing %.3f ms (%.1f), an Abrams' 14 stations of wheel forces %.3f ms (%.2f)" % [step_ms, STEP_BUDGET_MS, guard_ms, GUARD_BUDGET_MS, load_ms, LOAD_BUDGET_MS, wheels_ms, WHEELS_BUDGET_MS])
	for x in vs:
		await _clear(x)


# --- A late joiner ---------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins late)")
	var r := await _spawn("matv", _lab_point(120.0, 140.0), 0.0)
	r.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(95.0)), _lab_point(120.0, 140.0) + Vector3(0, 1.4, 0))
	r.sleeping = false
	await _until(func() -> bool: return r.drive.is_rolled(), 4.0)
	expect["rolled"] = r.vehicle_id
	var pair: Array = get_meta(&"tow_pair", [])
	if pair.size() == 2:
		expect["towed"] = pair[0]
	var st := get_meta(&"stalled", null) as Vehicle
	if is_instance_valid(st):
		expect["stalled_ground"] = String(st.drive.ground())
	var log_path := OS.get_user_data_dir().path_join("armourdrive_client%s.log" % _tag)
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/armourdrive_test.tscn", "--", "--armourdrive-join"]
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	multiplayer.peer_connected.connect(func(peer: int) -> void:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.get_peer(peer):
			enet.get_peer(peer).set_timeout(32, 60000, 120000))
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_failures >= 0, 400.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(450.0).timeout.connect(func() -> void: get_tree().quit(99))
	var m: Node = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	if Net.session_ended.is_connected(Callable(m, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(m, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		print("  [%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 150.0)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if joined and enet and enet.get_peer(1):
		enet.get_peer(1).set_timeout(32, 60000, 120000)
	var asked_until := Time.get_ticks_msec() + 60000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until and multiplayer.get_unique_id() != 1:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	await _until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel and (CompoundLevel.current(self) as ZoneLevel).terrain != null, 120.0)
	var lvl := CompoundLevel.current(self) as ZoneLevel
	if lvl == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.get("rolled", ""))) != null, 60.0)
		await _seconds(2.0)
		var r: Vehicle = find.call(String(expect.get("rolled", "")))
		note.call(r != null and r.drive != null and r.drive.is_rolled() and not r.can_drive() and "ROLLED OVER: NEEDS A TOW" in VehicleHud.alerts(r, 0),
			"the rolled-over M-ATV is rolled over here, won't drive, and the HUD says so")
		var f: Vehicle = find.call(String(expect.get("flooded", "")))
		note.call(f != null and f.drive.is_flooded() and "FLOODED: GET OUT" in VehicleHud.alerts(f, 0), "the technical flooded")
		var s: Vehicle = find.call(String(expect.get("stalled", "")))
		note.call(s != null and s.drive.is_stalled() and "STALLED: TOO DEEP" in VehicleHud.alerts(s, 0) and String(s.drive.ground()) == String(expect.get("stalled_ground", "?")),
			"the MaxxPro stalled in the river, on the host's ground (%s)" % (String(s.drive.ground()) if s else "-"))
		var t: Vehicle = find.call(String(expect.get("towed", "")))
		await _until(func() -> bool: return t != null and t.logistics.tow_bar() != null, 5.0)
		note.call(t != null and t.logistics.towed() and t.logistics.tow_bar() != null, "the towed M-ATV on its tow, the bar drawn")
		var wb: ZoneBridges = lvl.terrain.water.bridges if lvl.terrain.water else null
		var td: Array = expect.get("truss_down", [-1, -1])
		var worn: Array = expect.get("worn", [-1, -1, -1.0])
		await _until(func() -> bool: return wb != null and int(td[0]) >= 0 and wb.is_down(int(td[0]), int(td[1])), 30.0)
		note.call(wb != null and int(td[0]) >= 0 and wb.is_down(int(td[0]), int(td[1])) and _near(wb.span_mlc(int(worn[0]), int(worn[1])), float(worn[2]), 0.05),
			"the dropped truss span down here, the worn concrete span at the host's class (%.0f)" % (wb.span_mlc(int(worn[0]), int(worn[1])) if wb and int(worn[0]) >= 0 else -1.0))
	if multiplayer.get_unique_id() != 1:
		_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()
