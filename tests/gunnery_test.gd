extends Node
## Headless checks for combined arms A4 (cg_brief queue item 2.3; docs/combined_arms.md 2.6, 2.7.4,
## 9.3): gunnery in the real compound. The sights' data and FireControl's ballistic table against
## ShellFlight; the laser's range and its error, its limits, first and last return through smoke;
## the fire control putting real rounds through ShellFlight onto targets 1 and 2 km off, a crossing
## target at 1.5 km, and from a tank driving past at 8 m/s; seeded runs (90% hits with the lead,
## under 40% without); each sight and module fallback (the primary damaged and destroyed, the aux
## sight's stadia, the fire control damaged x3 and destroyed: manual ranging), the stabiliser on,
## off and past its speed; the commander's hand-off slewing the turret (and his own slower lay);
## hatches (exposure to rounds and blasts, spotting through the vision blocks, the MG and TOW-reload
## rules, the AI's rule); the AMP's airburst at the lased range; thermal (the heat tags, smoke, the
## budget); the sight overlay at the ui_test's 10 resolutions; save and load; the costs; then a
## second process joins over ENet and finds the hatches, the lase and the solution as the host has
## them (late join).
##   <voxel godot exe> --headless --path . res://tests/gunnery_test.tscn
## The host starts the client itself ("-- --gunnery-join"). Exits with the number of failures.

## Budgets (Proposed; docs/combined_arms.md 9.3: "Thermal costs under 1 ms a frame").
const THERMAL_BUDGET_MS := ThermalView.BUDGET_MS
const STEP_BUDGET_MS := 0.25
const LASE_BUDGET_MS := 0.5
## The air rigs: shooters and targets frozen this high (nothing in the way out to 2 km).
const RIG_Y := 150.0
## 9.3: the fire control hits a crossing target at 1,500 m on 90% of seeded runs; no lead under 40%.
const MC_RUNS := 200
const MC_HITS := 0.9
const MC_NO_LEAD := 0.4

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var flight: ShellFlight
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _n := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_gunnery" + tag  # never touch a real save
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--gunnery-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(450.0).timeout.connect(func() -> void:
		print("GUNNERY TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	layer = VehicleLayer.of(level)
	flight = ShellFlight.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 0)
	for model: String in ["abrams", "bradley"]:
		VehicleHull.prewarm(model)
	_test_data()
	_test_seeded_runs()
	_test_overlay()
	if _want("lrf"):
		await _test_lrf()
	if _want("fire"):
		await _test_fire_control()
	if _want("modules"):
		await _test_fallbacks()
	if _want("stab"):
		await _test_stabiliser()
	if _want("handoff"):
		await _test_hand_off()
	if _want("hatch"):
		await _test_hatches()
	if _want("amp"):
		await _test_airburst()
	if _want("thermal"):
		await _test_thermal()
	if _want("view"):
		await _test_sight_view()
	if _want("save"):
		await _test_save()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	GameState.delete_save()
	print("GUNNERY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_GUNNERY_ONLY="lrf,fire" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_GUNNERY_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


static func _near(got: float, want: float, share := 0.1) -> bool:
	return absf(got - want) <= absf(want) * share


## A list of numbers (JSON's floats) as whole numbers.
static func _ints(a: Variant) -> Array:
	return (a as Array).map(func(x: Variant) -> int: return roundi(float(x))) if a is Array else []


# --- Data and the computer (pure) -------------------------------------------------------------------

func _test_data() -> void:
	print("Sights, fire control and stabiliser data; the ballistic table")
	var mbt := VehicleSpecs.spec("abrams")
	var ifv := VehicleSpecs.spec("bradley")
	var ids := func(spec: Dictionary) -> Array: return (spec.get("optics", []) as Array).map(func(o: Dictionary) -> String: return String(o.id))
	check(ids.call(mbt) == ["gps", "gas", "citv"] and ids.call(ifv) == ["ibas", "aux", "civ"],
		"the Abrams: GPS, GAS, CITV; the Bradley: IBAS, its aux sight, the CIV (%s / %s)" % [ids.call(mbt), ids.call(ifv)])
	var gps: Dictionary = mbt.optics[0]
	check(_ints(gps.day) == [3, 10] and _ints(gps.thermal) == [3, 6, 13, 25] and _ints(gps.lrf_m) == [200, 8000] and float(gps.lrf_err_m) == 5.0
		and _ints(ifv.optics[0].lrf_m) == [200, 4000] and float(mbt.stab.max_kmh) == 50.0 and float(ifv.stab.max_kmh) == 40.0,
		"2.7.4's table: GPS day 3x/10x, thermal 3x-25x, LRF 200-8,000 m +-5; IBAS to 4,000 m; stabilisers to 50 and 40 km/h")
	check(VehicleSpecs.spec("abrams").hatches.has("2") and VehicleSpecs.spec("bradley").has("roof_hatch"), "hatches: the Abrams' commander; the Bradley's roof hatch")
	var worst := 0.0
	for sid: String in ["m829a3", "m830a1", "m1147", "m791", "m792"]:
		for r: float in [500.0, 1000.0, 2000.0, 3000.0]:
			var a := FireControl.at(StringName(sid), r)
			var b := ShellFlight.flight_to(StringName(sid), r)
			worst = maxf(worst, maxf(absf(float(a.time) - float(b.time)) / float(b.time), absf(float(a.drop) - float(b.drop)) / maxf(float(b.drop), 0.01)))
	check(worst < 0.01, "the ballistic tables match ShellFlight's flight within 1%% (worst %.2f%%)" % (worst * 100.0))
	var st := FireControl.stadia_mil(&"m829a3", 2000.0)
	check(_near(st, atan(9.1 / 2000.0) / FireControl.MIL, 0.12), "the GAS's 2,000 m sabot mark: %.2f mil over the target (9.1 m of drop)" % st)
	check(VehicleGunnery.fuze_modes("m1147") == ["", "delay", "airburst"] and VehicleGunnery.fuze_modes("m830a1") == ["", "air"] and VehicleGunnery.fuze_modes("m829a3") == [""],
		"fuzes: the AMP PD, delay, airburst; the HEAT-MP PD, air; sabot none")
	check(InputMap.has_action(&"lase") and InputMap.has_action(&"designate") and InputMap.has_action(&"hatch") and InputMap.has_action(&"sight_channel")
		and GameSettings.shares_key(&"lase", &"lean_right") and GameSettings.shares_key(&"hatch", &"crouch")
		and Controls.on_pad(&"lase") and Controls.on_pad(&"hatch"), "keys: lase, designate, hatch and sight channel, seated only, on the pad's wheel")


## A round of `sid` from `from` at `vel` flown (ShellFlight's steps) until it reaches `z` going
## -z: its place and time there.
static func _fly_to_z(sid: StringName, from: Vector3, vel: Vector3, z: float) -> Dictionary:
	var k := float(Shells.shell(sid).get("drag", 0.0))
	var pos := from
	var t := 0.0
	var dt := 1.0 / 120.0
	while pos.z > z and t < ShellFlight.MAX_S:
		var v1 := vel + (ShellFlight.GRAVITY - vel * vel.length() * k) * dt
		var to := pos + (vel + v1) * 0.5 * dt
		if to.z <= z:
			var f := (z - pos.z) / minf(to.z - pos.z, -0.0001)
			return {"pos": pos.lerp(to, clampf(f, 0.0, 1.0)), "t": t + dt * f}
		pos = to
		vel = v1
		t += dt
	return {"pos": pos, "t": t}


## 9.3's seeded runs: a tank crossing at 1,500 m (+-100) at 4-15 m/s, tracked 0.5-2 s, lased (+-5 m),
## the computer's error, the gun's and stabiliser's dispersion; the round flown; a hit is on its side
## (7.9 x 2.4 m). The share of hits.
func _mc(lead: bool) -> float:
	var hits := 0
	var sid := &"m829a3"
	var spread := sqrt(0.2 * 0.2 + 0.08 * 0.08) * FireControl.MIL
	for i in MC_RUNS:
		var seed := hash(["gunnery-mc", i])
		var r := 1500.0 + FireControl.roll(seed, 11) * 100.0
		var v := (4.0 + 11.0 * ArmourModel.roll(seed, 12)) * (1.0 if ArmourModel.roll(seed, 13) < 0.5 else -1.0)
		var trk := 0.5 + 1.5 * ArmourModel.roll(seed, 14)
		var sight := Vector3.ZERO
		var muzzle := Vector3(-0.75, -0.65, -3.5)
		var target := Vector3(0.0, 0.0, -r)
		var dir := (target - sight).normalized()
		var rate := Vector2(-v / r * (1.0 + 0.1 * FireControl.roll(seed, 15)), 0.0)
		rate *= 1.0 + FireControl.roll(seed, 16) * FireControl.lead_error(trk)
		if not lead:
			rate = Vector2.ZERO
		var lased := r - 1.8 + FireControl.roll(seed, 17) * 5.0
		var res := FireControl.solve(sid, sight, dir, lased, rate, muzzle)
		var g := VehicleWeapons._scatter(res.dir, 0.1 * FireControl.MIL, seed + 7)
		g = VehicleWeapons._scatter(g, spread, seed + 19)
		var at := _fly_to_z(sid, muzzle, g * float(Shells.shell(sid).muzzle_mps), target.z)
		var p: Vector3 = at.pos
		if absf(p.x - v * float(at.t)) <= 3.95 and absf(p.y) <= 1.2:
			hits += 1
	return float(hits) / float(MC_RUNS)


func _test_seeded_runs() -> void:
	print("Seeded runs: a crossing tank at 1,500 m (9.3)")
	var with := _mc(true)
	var without := _mc(false)
	check(with >= MC_HITS, "with the fire control's lead: %.0f%% hits (%.0f%% wanted)" % [with * 100.0, MC_HITS * 100.0])
	check(without < MC_NO_LEAD, "with no lead: %.0f%% hits (under %.0f%%)" % [without * 100.0, MC_NO_LEAD * 100.0])


# --- The overlay at 10 resolutions ----------------------------------------------------------------

func _test_overlay() -> void:
	print("The sight overlay at the ui_test's 10 resolutions")
	var sizes: Array = (load("res://tests/ui_test.gd") as GDScript).get_script_constant_map().get("SIZES", [])
	var host := Control.new()
	add_child(host)
	var o := VehicleSightOverlay.new()
	host.add_child(o)
	var info := {"name": "GPS", "stab": "DEGRADED", "lrf_state": "MULTIPLE RETURNS", "ret": "last", "lase": {"ok": true, "r": 1874.0},
		"sol": {"on": true, "bs": false, "trk": 1.2}, "lead_mil": 2.1, "loaded": "SABOT", "next": "HEAT", "rounds": "SABOT 14   HEAT 9   HE 8",
		"fuze": "AIRBURST 1874 m", "turret_deg": 12, "hull_deg": 346, "commander": true, "gun_rel_deg": -35.0}
	var bad: Array = []
	for res: Vector2i in sizes:
		var logical := Vector2(res) / GameSettings.ui_scale_for(res, 1.0)
		host.size = logical
		o.set_text(info, "thermal", ThermalView.BLACK_HOT, 25.0)
		await get_tree().process_frame
		var screen := Rect2(Vector2.ZERO, logical)
		var rects: Array = []
		for l: Label in [o._top_left, o._top_mid, o._top_right, o._bottom_left, o._bottom_right, o._prompt]:
			var r := Rect2(l.position, l.get_combined_minimum_size())
			if not screen.encloses(r):
				bad.append("%s: %s off %s" % [res, l.text.split("\n")[0], logical])
			rects.append(r)
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if (rects[i] as Rect2).grow(-1.0).intersects(rects[j]):
					bad.append("%s: overlap %d/%d" % [res, i, j])
	check(sizes.size() == 10 and bad.is_empty(), "every readout on screen and apart at %d resolutions (%s)" % [sizes.size(), bad])
	host.queue_free()


# --- The laser ------------------------------------------------------------------------------------

func _wall(at: Vector3, size := Vector3(60, 60, 1)) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	level.add_child(wall)
	wall.global_position = at
	return wall


func _test_lrf() -> void:
	print("The laser: range, error, limits, first and last return")
	var v := await _spawn("abrams", Vector3(300, RIG_Y + 150, 300), 0.0)
	var crew := await _crew(v, [1])
	var g := v.gunnery
	var from := g.sight_from(1)
	var wall := _wall(from + Vector3(0, 0, -1000.5))
	await _physics(2)
	g.lay_on(from + Vector3(0, 0, -1000.0))
	v.turret.settle()
	await _physics(2)
	var errs: Array = []
	for i in 20:
		var r := g.server_lase(1)
		errs.append(float(r.get("r", 0.0)) - from.distance_to(wall.global_position + Vector3(0, 0, 0.5)))
	var worst := 0.0
	for e: float in errs:
		worst = maxf(worst, absf(e))
	check(bool(g.lase_data.ok) and worst <= 5.01 and errs.any(func(e: float) -> bool: return absf(e) > 1.0),
		"a wall 1,000 m off: 20 lases within +-5 m (worst %.1f m), not all the same" % worst)
	wall.global_position = from + Vector3(0, 0, -7500.5)
	await _physics(2)
	var far := g.server_lase(1)
	check(bool(far.ok) and _near(float(far.r), 7500.0, 0.01), "7,500 m: within the GPS's 8,000 m (%.0f m)" % float(far.get("r", 0.0)))
	wall.global_position = from + Vector3(0, 0, -150.5)
	await _physics(2)
	var near := g.server_lase(1)
	check(not bool(near.ok) and String(near.why) == "NO RETURN" and bool(g.lase_data.fault) and _near(float(g.lase_data.r), 7500.0, 0.01),
		"150 m: under its 200 m gate, NO RETURN; the computer keeps the last range (%s)" % near.get("why", ""))
	# Smoke in front of the wall: first return at the smoke, last at the wall.
	wall.global_position = from + Vector3(0, 0, -600.5)
	var puff := from + Vector3(0, -1.5, -300.0)
	level.spawn_smoke.rpc(puff, "white", 1.2)
	await _seconds(0.6)
	var seen := {}
	for wait: float in [0.0, 6.0]:
		await _seconds(wait)
		var depth := SmokeCloud.depth_between(from, from + Vector3(0, 0, -600))
		g.server_set_return(true)
		var last := g.server_lase(1)
		g.server_set_return(false)
		var first := g.server_lase(1)
		g.server_set_return(true)
		var at_smoke := func(r: Dictionary) -> bool: return bool(r.get("ok", false)) and float(r.r) > 270.0 and float(r.r) < 320.0
		if depth >= SmokeCloud.BLOCK_DEPTH:
			seen["thick"] = true
			check(at_smoke.call(last) and at_smoke.call(first), "a screen 300 m out thick enough to hide the wall (depth %.1f): the laser stops in it (%.0f m)" % [depth, float(last.get("r", 0.0))])
		elif depth >= VehicleGunnery.SMOKE_ECHO:
			seen["thin"] = true
			check(bool(last.ok) and _near(float(last.r), 600.0, 0.02) and at_smoke.call(first) and bool(first.multi),
				"thin smoke 300 m out (depth %.1f): last return %.0f m (the wall), first %.0f m (the smoke), MULTIPLE RETURNS" % [depth, float(last.get("r", 0.0)), float(first.get("r", 0.0))])
		else:
			check(bool(last.ok) and _near(float(last.r), 600.0, 0.02), "smoke too thin to echo (depth %.2f): the wall, %.0f m" % [depth, float(last.get("r", 0.0))])
	check(not seen.is_empty(), "the smoke on the line gave a return (%s)" % [seen.keys()])
	wall.queue_free()
	await _clear(v, crew)


# --- The fire control, live -----------------------------------------------------------------------

## `shooter`'s gunner `gunner` tracks `aim_at` (a Callable: the point now) for `track_s`, lases,
## waits for the gun to lay, fires mount "main", and keeps everything moving (`move`: Callable
## run each physics frame) until the round ends. ShellFlight's result, with "lase".
func _engage(shooter: Vehicle, gunner: Soldier, aim_at: Callable, track_s: float, move: Callable) -> Dictionary:
	var g := shooter.gunnery
	g.lay_on(aim_at.call())
	shooter.turret.settle()
	var t := 0.0
	while t < track_s:
		move.call()
		g.lay_on(aim_at.call())
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var l := g.server_lase(g.gunner_seat())
	for i in 90:
		move.call()
		g.lay_on(aim_at.call())
		await get_tree().physics_frame
		if g.laid(0.03):
			break
	var r := shooter.weapons.server_fire(gunner, "main")
	if not bool(r.ok):
		return {"why": r.why, "lase": l}
	var id := int(r.get("shell", 0))
	for i in 600:
		if flight.results.has(id):
			break
		move.call()
		await get_tree().physics_frame
	var out: Dictionary = flight.results.get(id, {"why": "no result"}).duplicate()
	out["lase"] = l
	return out


func _test_fire_control() -> void:
	print("The fire control: real rounds through ShellFlight (9.3)")
	var none := func() -> void: pass
	for row: Array in [["abrams", 1000.0, &"m829a3"], ["abrams", 2000.0, &"m829a3"], ["bradley", 1200.0, &"m791"]]:
		var v := await _spawn(row[0], Vector3(-400, RIG_Y, 500), 0.0)
		var crew := await _crew(v, [1])
		var target := await _spawn("abrams", Vector3(-400, RIG_Y, 500 - float(row[1])), 180.0, &"hostile")
		target.damage_mult = 0.0001
		var point := target.global_transform * Vector3(0, 1.45, 0.8)
		var res := await _engage(v, crew[0], func() -> Vector3: return point, 1.2, none)
		var sol := v.gunnery.solution()
		check(String(res.get("how", "")) == "vehicle" and res.get("vehicle") == target,
			"%s, %s at a tank %.0f m off: lased %.0f m, laid %.2f mil up, the round on it (%s)" % [row[0], row[2], row[1],
			float((res.get("lase", {}) as Dictionary).get("r", 0.0)), (sol.get("lay", Vector2.ZERO) as Vector2).y / FireControl.MIL, res.get("how", res.get("why", "?"))])
		await _clear(v, crew)
		target.queue_free()
	# A tank crossing at 1,500 m at 10 m/s, tracked 1.2 s.
	var v2 := await _spawn("abrams", Vector3(-600, RIG_Y, 500), 0.0)
	var crew2 := await _crew(v2, [1])
	var cross := await _spawn("abrams", Vector3(-640, RIG_Y, -1000), 90.0, &"hostile")
	cross.damage_mult = 0.0001
	var speed := 10.0
	var mover := func() -> void: cross.global_position += Vector3(speed * get_physics_process_delta_time(), 0, 0)
	var res2 := await _engage(v2, crew2[0], func() -> Vector3: return cross.global_transform * Vector3(0, 1.45, 0.8), 1.2, mover)
	var sol2 := v2.gunnery.solution()
	check(String(res2.get("how", "")) == "vehicle" and res2.get("vehicle") == cross and float(sol2.get("trk", 0.0)) >= 1.0,
		"a tank crossing at 1,500 m, 10 m/s: tracked %.1f s, lead %.1f mil, the round on it (%s)" % [float(sol2.get("trk", 0.0)),
		(sol2.get("lead", Vector2.ZERO) as Vector2).length() / FireControl.MIL, res2.get("how", res2.get("why", "?"))])
	await _clear(v2, crew2)
	cross.queue_free()
	# From a tank driving past at 8 m/s (the stabiliser on), at a tank 1,500 m off.
	var v3 := await _spawn("abrams", Vector3(-800, RIG_Y, 500), 0.0)
	var crew3 := await _crew(v3, [1])
	var still := await _spawn("abrams", Vector3(-760, RIG_Y, -1000), 180.0, &"hostile")
	still.damage_mult = 0.0001
	var drive := func() -> void: v3.global_position += Vector3(8.0 * get_physics_process_delta_time(), 0, 0)
	var point3 := still.global_transform * Vector3(0, 1.45, 0.8)
	var res3 := await _engage(v3, crew3[0], func() -> Vector3: return point3, 1.2, drive)
	check(String(res3.get("how", "")) == "vehicle" and res3.get("vehicle") == still and v3.gunnery.stab_text() == "ON" and v3.gunnery.own_velocity().length() > 7.0,
		"driving past at %.0f m/s, the stabiliser %s: the round on a tank 1,500 m off (%s)" % [v3.gunnery.own_velocity().length(), v3.gunnery.stab_text(),
		res3.get("how", res3.get("why", "?"))])
	await _clear(v3, crew3)
	still.queue_free()


# --- Sights and modules -------------------------------------------------------------------------------

func _test_fallbacks() -> void:
	print("Sights and modules: each fallback (2.2.2)")
	var v := await _spawn("abrams", Vector3(500, RIG_Y, 500), 0.0)
	var crew := await _crew(v, [1, 2])
	var g := v.gunnery
	var s := g.sight_for(1)
	check(String(s.o.id) == "gps" and _ints(s.thermal) == [3, 6, 13, 25] and bool(s.lrf) and g.stab_text() == "ON", "whole: the GPS, thermal to 25x, the laser, STAB ON")
	v.modules.server_set("gunner_sight", 0.3)
	await _physics(2)
	s = g.sight_for(1)
	var l := g.server_lase(1)
	check(String(s.o.id) == "gps" and (s.thermal as Array).is_empty() and _ints(s.day) == [3, 10] and not bool(s.lrf) and not bool(l.ok) and String(l.why) == "FAULT",
		"the GPS damaged: day only, the laser out (LRF %s)" % l.get("why", ""))
	v.modules.server_set("gunner_sight", 0.0)
	await _physics(2)
	s = g.sight_for(1)
	var target := v.global_transform * Vector3(0, 2.0, -2000.0)
	g.lay_on(target)
	v.turret.settle()
	await _seconds(VehicleGunnery.RESOLVE_S + 0.1)
	var info := g.sight_info(1)
	check(String(s.o.id) == "gas" and bool(s.fallback) and _ints(s.day) == [8] and not bool(g.solution().get("on", true)) and v.turret.lay == Vector2.ZERO
		and bool(info.stadia) and (info.get("marks", []) as Array).size() >= 5 and g.stab_text() == "OFF",
		"the GPS destroyed: on the GAS (8x, stadia %s), no solution, the gun on the sight, STAB OFF" % [(info.get("marks", []) as Array).map(func(m: Array) -> int: return roundi(float(m[0])))])
	v.modules.server_set("aux_sight", 0.3)
	await _physics(2)
	check(bool(g.sight_for(1).blur), "the GAS damaged: blurred")
	v.modules.server_reset()
	await _physics(2)
	# The commander's viewer.
	v.modules.server_set("commander_sight", 0.3)
	await _physics(2)
	var c := g.sight_for(2)
	check(String(c.o.id) == "citv" and (c.thermal as Array).is_empty() and _ints(c.day) == [3], "the CITV damaged: thermal lost, its 3x left as a day picture")
	v.modules.server_set("commander_sight", 0.0)
	await _physics(2)
	var why := g.server_hand_off(2, -v.global_basis.z)
	check(g.sight_for(2).is_empty() and why.begins_with("Periscopes only"), "destroyed: periscopes only, no hand-off (%s)" % why)
	v.modules.server_reset()
	await _physics(2)
	# The fire control damaged: the solution's error x3 (the same seed).
	g.lay_on(target)
	v.turret.settle()
	await _physics(2)
	g.lase_data = {"ok": true, "fault": false, "why": "", "r": 2000.0, "first": 2000.0, "last": 2000.0, "multi": false, "seat": 1, "at": Soldier._now(),
		"rate": Vector2.ZERO, "trk": 0.0, "seed": 4242}
	var errs := []
	for x: float in [0.0, 1.0]:
		g.fc["err_mil"] = 0.1 * x
		g._solve()
		errs.append(v.turret.lay)
	v.modules.server_set("fcs", 0.3)
	await _physics(2)
	g._solve()
	var damaged := v.turret.lay
	g.fc["err_mil"] = 0.1
	var e1 := ((errs[1] as Vector2) - (errs[0] as Vector2)).length()
	var e3 := (damaged - (errs[0] as Vector2)).length()
	check(e1 > 0.0 and _near(e3, e1 * 3.0, 0.05) and g.stab_text() == "DEGRADED", "the fire control damaged: its error x3 (%.3f mil against %.3f), STAB DEGRADED" % [e3 / FireControl.MIL, e1 / FireControl.MIL])
	v.modules.server_set("fcs", 0.0)
	await _physics(2)
	g._solve()
	check(not bool(g.solution().get("on", true)) and v.turret.lay == Vector2.ZERO and g.stab_text() == "OFF" and bool(g.sight_for(1).lrf),
		"the fire control destroyed: the sight and its laser work, but there's no solution and no stabiliser")
	await _clear(v, crew)
	# Manual ranging: the fire control out, a tank 2 km off. The sight's centre on it falls short;
	# the GAS's 2,000 m mark on it hits.
	var shots := []
	for hold: bool in [false, true]:
		var mbt := await _spawn("abrams", Vector3(700, RIG_Y, 500), 0.0)
		var mcrew := await _crew(mbt, [1])
		mbt.modules.server_set("fcs", 0.0)
		mbt.modules.server_set("gunner_sight", 0.0)
		var foe := await _spawn("abrams", Vector3(700, RIG_Y, -1500), 180.0, &"hostile")
		foe.damage_mult = 0.0001
		var pt := foe.global_transform * Vector3(0, 1.45, 0.8)
		var over := 0.0
		if hold:
			var r := mbt.gunnery.sight_from(1).distance_to(pt)
			over = tan(FireControl.stadia_mil(&"m829a3", r) * FireControl.MIL) * r
		var res := await _engage(mbt, mcrew[0], func() -> Vector3: return pt + Vector3.UP * over, 1.2, func() -> void: pass)
		shots.append(String(res.get("how", "")) == "vehicle" and res.get("vehicle") == foe)
		await _clear(mbt, mcrew)
		foe.queue_free()
	check(shots == [false, true], "manual ranging, the fire control out at 2 km: the centre held falls short, the GAS's mark held hits (%s)" % [shots])


# --- The stabiliser ---------------------------------------------------------------------------------

## Turns `v`'s hull `deg` a frame for `frames` (moving it `step` a frame) and returns how far the
## gun's line drifted in the world (degrees).
func _turn_hull(v: Vehicle, deg: float, frames: int, step := Vector3.ZERO) -> float:
	var want := v.barrel_direction()
	_moving_jitter = 0.0
	_moving_stab = ""
	for i in frames:
		v.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(deg)) * v.global_basis, v.global_position + step)
		await get_tree().physics_frame
		if i > frames / 2:
			_moving_jitter = maxf(_moving_jitter, v.gunnery.jitter_mil())
			_moving_stab = v.gunnery.stab_text()
	var drift := rad_to_deg(v.barrel_direction().angle_to(want))
	await _physics(2)
	return drift


var _moving_jitter := 0.0
var _moving_stab := ""


func _test_stabiliser() -> void:
	print("The stabiliser: on, off and past its speed (2.7.4)")
	var v := await _spawn("abrams", Vector3(900, RIG_Y, 500), 0.0)
	var crew := await _crew(v, [1])
	var g := v.gunnery
	g.lay_on(v.global_transform * Vector3(0, 2.0, -800))
	v.turret.settle()
	await _physics(3)
	var on := await _turn_hull(v, 0.4, 45)
	check(on < 0.5 and g.stab_text() == "ON", "on: the hull turns 18 degrees, the gun holds its line (%.2f deg off)" % on)
	v.modules.server_set("traverse", 0.4)
	await _physics(2)
	var off := await _turn_hull(v, 0.4, 45)
	check(off > 15.0 and g.stab_text() == "OFF", "the traverse drive damaged: off, the gun turns with the hull (%.1f deg)" % off)
	v.modules.server_reset()
	await _physics(3)
	g.lay_on(v.global_transform * Vector3(0, 2.0, -800))
	v.turret.settle()
	await _physics(3)
	g.lay_on(v.global_transform * Vector3(0, 2.0, -800))
	v.turret.settle()
	await _physics(3)
	var fast := await _turn_hull(v, 0.2, 45, Vector3(0.0, 0.0, -0.3))  # 18 m/s, 65 km/h
	var fast_state := _moving_stab
	var jitter_fast := _moving_jitter
	check(fast > 7.0 and fast_state == "OFF" and jitter_fast > 10.0, "past 50 km/h (65): it can't keep up, the gun drifts %.1f deg, and firing on the move scatters %.0f mil" % [fast, jitter_fast])
	var slow := await _turn_hull(v, 0.2, 45, Vector3(0.0, 0.0, -0.15))  # 9 m/s, 32 km/h, turning
	var j := _moving_jitter
	check(slow < 0.5 and j > float(v.spec.stab.base_mil) * 1.5 and _moving_stab != "OFF",
		"at 32 km/h turning it holds (%.2f deg); its jitter grows with speed and turning (%.2f mil, base %.2f)" % [slow, j, float(v.spec.stab.base_mil)])
	await _clear(v, crew)


# --- The hand-off ------------------------------------------------------------------------------------

func _test_hand_off() -> void:
	print("The commander's viewer and hand-off (2.7.4)")
	var v := await _spawn("abrams", Vector3(1100, RIG_Y, 500), 0.0)
	var crew := await _crew(v, [1, 2])
	var g := v.gunnery
	v.hatches.auto_ai = false
	g.lay_on(v.global_transform * Vector3(0, 2.0, -800))
	v.turret.settle()
	await _physics(2)
	var side := (v.global_basis * Vector3(-1, 0, 0)).normalized()  # 90 degrees left
	g.server_view(2, side)
	var y0 := v.turret.yaw
	var why := g.server_hand_off(2, side, 1200.0)
	var asked := v.turret.target_yaw
	v.server_aim(-v.global_basis.z)  # the gunner's (or his AI's) aim waits while it slews
	await _seconds(1.0)
	var moved := rad_to_deg(wrapf(v.turret.yaw - y0, -PI, PI))
	check(why == "" and _near(moved, 40.0, 0.15) and is_equal_approx(v.turret.target_yaw, asked) and g.slewing(),
		"designate 90 degrees left: the turret slews at full speed (%.0f deg in a second, 40) and the gunner's aim waits" % moved)
	await _until(func() -> bool: return not g.slewing(), 4.0)
	var off := rad_to_deg(g.sight_dir(1).angle_to(side))
	check(off < 1.0 and bool(g.hk.get("done", false)) and String(g.hk.kind) == "target" and _near(float(g.lase_data.r), 1200.0, 0.001),
		"on his line (%.2f deg), his lased 1,200 m handed with it" % off)
	# No gunner: he lays it himself, at COMMANDER_LAY.
	v.server_exit(crew[0])
	await _physics(3)
	var y1 := v.turret.yaw
	g.server_hand_off(2, -v.global_basis.z, 0.0)
	await _seconds(1.0)
	var own := absf(rad_to_deg(wrapf(v.turret.yaw - y1, -PI, PI)))
	check(_near(own, 40.0 * VehicleGunnery.COMMANDER_LAY, 0.15) and g.controller() == crew[1],
		"no gunner: the commander lays it himself at %.0f deg/s (40 / 1.5)" % own)
	await _until(func() -> bool: return not g.slewing(), 5.0)
	v.hatches.server_set(2, true, true)
	why = g.server_hand_off(2, side, 0.0)
	check(why.begins_with("Button up"), "turned out, no viewer: %s" % why)
	await _clear(v, crew)


# --- Hatches ----------------------------------------------------------------------------------------

func _test_hatches() -> void:
	print("Hatches: turned out or buttoned up (2.6)")
	var v := await _spawn("abrams", Vector3(1300, RIG_Y, 500), 0.0)
	var crew := await _crew(v, [2, 3])
	var h := v.hatches
	h.auto_ai = false
	var cmd: Soldier = crew[0]
	var loader: Soldier = crew[1]
	var box_top := v.global_transform * Vector3(0, 2.45, 0)
	check(not h.is_out(2) and not v.seat_open(2) and Warheads.vehicle_occupants(get_tree()).has(cmd), "buttoned up at the start: inside, a blast outside left to the hull")
	# The MGs: the loader's M240 only turned out; the commander's M2 too unless CROWS is fitted.
	check(v.weapons.can_fire(loader, "loader_m240") == "Turn out first" and v.weapons.can_fire(cmd, "commander_m2") == "Turn out first",
		"buttoned up: the loader's M240 and the commander's M2 won't fire (%s)" % v.weapons.can_fire(loader, "loader_m240"))
	v.set_meta(ArmourModel.META_PACKAGES, ["crows"])
	var crows := v.weapons.can_fire(cmd, "commander_m2")
	v.remove_meta(ArmourModel.META_PACKAGES)
	check(crows == "", "with CROWS fitted the M2 fires from inside (%s)" % crows)
	var inside_head := _head(cmd)
	var seen_in := VehicleHatches.spot_x(cmd, v.global_transform * Vector3(0, 2.5, -200))
	var gap := VehicleHatches.spot_x(cmd, v.global_transform * (Basis(Vector3.UP, deg_to_rad(30.0)) * Vector3(0, 2.5, -200)))
	# Turn out: HATCH_S.
	h.server_set(2, true)
	h.server_set(3, true)
	await _seconds(VehicleHatches.HATCH_S * 0.5)
	var midway := h.is_out(2)
	await _seconds(VehicleHatches.HATCH_S * 0.5 + 0.2)
	var head := _head(cmd)
	check(not midway and h.is_out(2) and v.seat_open(2) and head.y > box_top.y + 0.3 and not Warheads.vehicle_occupants(get_tree()).has(cmd),
		"turned out in %.1f s: his head %.2f m over the turret roof, out in the open for a blast" % [VehicleHatches.HATCH_S, head.y - box_top.y])
	check(v.weapons.can_fire(loader, "loader_m240") == "" and v.weapons.can_fire(cmd, "commander_m2") == "", "turned out: both MGs fire")
	var seen_out := VehicleHatches.spot_x(cmd, v.global_transform * (Basis(Vector3.UP, deg_to_rad(30.0)) * Vector3(0, 2.5, -200)))
	check(is_equal_approx(seen_in, VehicleHatches.SPOT_BUTTONED) and gap == INF and seen_out == 1.0 and VehicleHatches.spot_x(loader, v.global_transform * Vector3(0, 2.5, -200)) == 1.0,
		"spotting: buttoned up x%.1f through a vision block, not at all between them; turned out x1" % seen_in)
	# Spotting itself: a man 150 m ahead, seen turned out and buttoned up.
	var foe := _soldier("Gnr_foe_%d" % _n, &"hostile", v.global_transform * Vector3(0, 0.0, -150))
	foe.set_physics_process(false)
	foe.global_position = v.global_transform * Vector3(0, 0.5, -150)
	await _physics(2)
	var t_out := Spotting.spot_seconds(cmd, foe, "", 0.5, false, Soldier._now())
	h.server_set(2, false, true)
	await _physics(2)
	var t_in := Spotting.spot_seconds(cmd, foe, "", 0.5, false, Soldier._now())
	check(_near(t_in / maxf(t_out, 0.0001), VehicleHatches.SPOT_BUTTONED, 0.05), "Spotting: %.1f s turned out, %.1f s buttoned up through the front block (x2.5)" % [t_out, t_in])
	h.server_set(2, true, true)
	await _physics(3)
	# The AI's rule: out after OUT_AFTER_S quiet, in at the first contact.
	h.server_set(2, false, true)
	h.server_set(3, false, true)
	h.auto_ai = true
	h._born = Soldier._now() - VehicleHatches.OUT_AFTER_S - 1.0
	cmd.threat_time = -1000.0
	loader.threat_time = -1000.0
	v.weapons._last_contact = -INF
	await _seconds(1.0 / VehicleHatches.AUTO_HZ + VehicleHatches.HATCH_S + 0.3)
	var went_out := h.is_out(2) and h.is_out(3)
	v.weapons._last_contact = Soldier._now()
	await _seconds(1.0 / VehicleHatches.AUTO_HZ + 0.1)
	check(went_out and not h.is_out(2) and not h.is_out(3), "AI crewmen: out after %d s of quiet, buttoned up at once on contact" % int(VehicleHatches.OUT_AFTER_S))
	h.auto_ai = false
	# A blast beside the loader's hatch: him turned out, not buttoned up.
	h.server_set(2, false, true)  # (the commander inside, out of it)
	h.server_set(3, false, true)
	await _physics(2)
	var blast_at := _head(loader) + v.global_basis * Vector3(-2.0, -0.3, 0.0)
	var hurt_in := Warheads.server_people(level, blast_at, Warheads.data(&"pg7v"), null)
	h.server_set(3, true, true)
	await _physics(2)
	blast_at = _head(loader) + v.global_basis * Vector3(-2.0, -0.3, 0.0)
	var hurt_out := Warheads.server_people(level, blast_at, Warheads.data(&"pg7v"), null)
	check(not loader in hurt_in and loader in hurt_out, "an RPG's burst 2 m beside the loader's hatch: buttoned up nothing, turned out it reaches him")
	h.server_set(2, true, true)
	await _physics(3)
	# Exposure: a round at his head.
	var shooter := _soldier("Gnr_rifle_%d" % _n, &"hostile", v.global_transform * Vector3(-40, 0, 0.8))
	shooter.set_physics_process(false)
	var muzzle := v.global_transform * Vector3(-40, 0, 0.8)
	muzzle.y = _head(cmd).y
	shooter.global_position = muzzle - Vector3(0, 1.6, 0)
	await _physics(2)
	var item := VehicleSpecs.gun_item("m240c")
	var before := cmd.vitals.wound_list().size()
	var hit_out := Ballistics.fire(shooter, muzzle, (_head(cmd) - muzzle).normalized(), item)
	var wounds_out := cmd.vitals.wound_list().size() - before
	h.server_set(2, false, true)
	await _physics(3)
	var in_head := _head(cmd)
	var muzzle_in := Vector3(muzzle.x, in_head.y, muzzle.z)
	before = cmd.vitals.wound_list().size()
	var hit_in := Ballistics.fire(shooter, muzzle_in, (in_head - muzzle_in).normalized(), item)
	var wounds_in := cmd.vitals.wound_list().size() - before
	check(wounds_out > 0 and wounds_in == 0, "a 7.62 round at his head from 40 m: turned out it hits him (%s, %d wounds); buttoned up the turret stops it (%s)" % [
		hit_out.get("result", "?"), wounds_out, hit_in.get("result", "?")])
	await _clear(v, crew + [foe, shooter])
	# The Bradley's TOW reloader stands out of the roof hatch.
	var ifv := await _spawn("bradley", Vector3(1350, RIG_Y, 500), 0.0)
	var icrew := await _crew(ifv, [1, 3])
	ifv.hatches.auto_ai = false
	var w := ifv.weapons
	w.state.tow.rd = 0
	w.server_raise(false)
	var why := w.server_reload_tow(icrew[1])
	await _physics(3)
	var rhead := _head(icrew[1])
	var exposed := ifv.hatches.exposed(3) and ifv.seat_open(3) and rhead.y > (ifv.global_transform * Vector3(0, 2.0, 0)).y + 0.2
	w.state.tow.rd = 1  # (the last one: he comes back in when it's on)
	w.state.tow.rl = Soldier._now()
	await _physics(3)
	check(why == "" and exposed and not ifv.hatches.exposed(3) and not ifv.seat_open(3),
		"the TOW reloader works out of the roof hatch (his head %.2f m over the hull), back inside when it's done" % (rhead.y - (ifv.global_transform * Vector3(0, 2.0, 0)).y))
	await _clear(ifv, icrew)


func _head(s: Soldier) -> Vector3:
	return s.camera.global_position


# --- The AMP's airburst ------------------------------------------------------------------------------

func _test_airburst() -> void:
	print("The M1147 AMP's airburst at the lased range")
	var v := await _spawn("abrams", Vector3(-300, RIG_Y + 100, -300), 0.0)
	var crew := await _crew(v, [1])
	var g := v.gunnery
	var from := g.sight_from(1)
	var wall := _wall(from + Vector3(0, 0, -800.5))
	await _physics(2)
	g.lay_on(from + Vector3(0, 0, -800))
	v.turret.settle()
	await _physics(2)
	v.weapons.state.main.l = "m1147"
	check(g.server_set_fuze("m1147", "airburst"), "the AMP set to airburst")
	var l := g.server_lase(1)
	var ab := g.fuze_for("m1147")
	wall.global_position = from + Vector3(0, 0, -1500.5)  # (what was lased moved off: the round must burst in the air)
	await _physics(2)
	for i in 60:
		await get_tree().physics_frame
		if g.laid(0.03):
			break
	var r := v.weapons.server_fire(crew[0], "main")
	var id := int(r.get("shell", 0))
	await _until(func() -> bool: return flight.results.has(id), 5.0)
	var res: Dictionary = flight.results.get(id, {})
	var flown := float(res.get("flown", 0.0))
	check(bool(l.ok) and _near(float(ab.get("airburst_m", 0.0)), 800.0, 0.01) and String(res.get("how", "")) == "air" and String(res.get("outcome", "")) == "airburst"
		and absf(flown - float(l.r) - 5.0) < 8.0, "lased %.0f m: it bursts in the air %.0f m out (the set range and the fuze's 5 m)" % [float(l.get("r", 0.0)), flown])
	g.server_set_fuze("m1147", "")
	g.lase_data = {}
	g._solve()
	g.server_set_fuze("m1147", "airburst")
	check(_near(float(g.fuze_for("m1147").get("airburst_m", 0.0)), 900.0, 0.001), "with no lase it bursts at battlesight, 900 m")
	g.server_set_fuze("m1147", "")
	wall.queue_free()
	await _clear(v, crew)


# --- Thermal ---------------------------------------------------------------------------------------

func _test_thermal() -> void:
	print("Thermal: heat tags, smoke, the budget")
	var v := await _spawn("abrams", Vector3(-500, RIG_Y, -300), 0.0)
	var crew := await _crew(v, [1])
	var eye := v.gunnery.sight_from(1)
	var men: Array = []
	for i in 40:
		var s := _soldier("Gnr_heat_%d_%d" % [i, _n], &"hostile", eye + Vector3(float(i % 8) * 3.0 - 12.0, -RIG_Y + 0.1, -60.0 - float(i / 8) * 4.0))
		s.set_physics_process(false)
		men.append(s)
	(men[0] as Soldier).vitals.server_kill()
	await _physics(3)
	level.spawn_smoke.rpc(eye + Vector3(0, -RIG_Y, -30), "white", 5.0)
	level.spawn_smoke.rpc(eye + Vector3(10, -RIG_Y, -30), ThermalView.MULTISPECTRAL, 5.0)
	await _physics(3)
	ThermalView.set_mode(ThermalView.WHITE_HOT)
	ThermalView.update(get_tree(), eye, true)
	var cold := ThermalView.last_update_ms
	var live: Soldier = men[1]
	var meshes := live.find_children("*", "GeometryInstance3D", true, false)
	var tinted := not meshes.is_empty() and meshes.all(func(m: Node) -> bool: return (m as GeometryInstance3D).material_overlay != null)
	var clouds := SmokeCloud.active.filter(func(c: SmokeCloud) -> bool: return is_instance_valid(c))
	var plain := clouds.filter(func(c: SmokeCloud) -> bool: return c.colour != ThermalView.MULTISPECTRAL)
	var ms := clouds.filter(func(c: SmokeCloud) -> bool: return c.colour == ThermalView.MULTISPECTRAL)
	check(ThermalView.bucket_of(live) == roundi(ThermalView.SOLDIER_HEAT * ThermalView.HEAT_STEPS) and ThermalView.bucket_of(men[0]) == roundi(ThermalView.DEAD_HEAT * ThermalView.HEAT_STEPS)
		and ThermalView.bucket_of(v) == roundi(ThermalView.COLD_VEHICLE_HEAT * ThermalView.HEAT_STEPS) and tinted,
		"white-hot: the living at %.2f, the dead at %.2f, a cold tank at %.2f; every piece of a man's look carries it (%d; buckets %d %d %d, tinted %s)" % [ThermalView.SOLDIER_HEAT,
		ThermalView.DEAD_HEAT, ThermalView.COLD_VEHICLE_HEAT, meshes.size(), ThermalView.bucket_of(live), ThermalView.bucket_of(men[0]), ThermalView.bucket_of(v), tinted])
	check(not plain.is_empty() and plain.all(func(c: SmokeCloud) -> bool: return not c.visible) and not ms.is_empty() and ms.all(func(c: SmokeCloud) -> bool: return c.visible),
		"ordinary smoke is see-through in thermal, the multispectral screen isn't")
	var times: Array = []
	for i in 20:
		ThermalView.update(get_tree(), eye, true)
		times.append(ThermalView.last_update_ms)
	times.sort()
	var steady := float(times[times.size() / 2])
	var per_frame := steady * ThermalView.UPDATE_HZ / 60.0
	check(steady < THERMAL_BUDGET_MS and cold < THERMAL_BUDGET_MS * 10.0,
		"the cost with %d bodies tagged: %.3f ms an update (%.3f ms a frame at %d Hz; budget %.1f ms), %.2f ms the first time" % [ThermalView.tagged_count, steady, per_frame,
		int(ThermalView.UPDATE_HZ), THERMAL_BUDGET_MS, cold])
	ThermalView.set_mode(ThermalView.OFF)
	var restored := meshes.all(func(m: Node) -> bool: return (m as GeometryInstance3D).material_overlay == null)
	check(restored and plain.all(func(c: SmokeCloud) -> bool: return c.visible) and ThermalView.tagged_count == 0, "off: every look and the smoke as they were")
	for c: SmokeCloud in clouds:
		c.queue_free()
	await _clear(v, crew + men)


# --- The local player's sight ---------------------------------------------------------------------

func _test_sight_view() -> void:
	print("The local player's sight: full screen, powers, channels")
	var v := await _spawn("abrams", Vector3(-600, RIG_Y, -300), 0.0)
	v.server_enter(player, 1)
	await _seconds(0.5)
	var g := v.gunnery
	var sight := VehicleSight.open_for(player, g, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var base := player.camera.fov
	var want3 := rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / 3.0))
	check(sight.up and sight.current and sight.channel == "day" and _near(sight.fov, want3, 0.01) and VehicleSight.zoom_turn(player) < 0.4
		and sight.global_position.distance_to(g.sight_from(1)) < 0.01 and is_instance_valid(sight.overlay) and sight.overlay.visible,
		"up: the GPS at its glass, day 3x (%.1f deg of the base %.0f), the mouse at %.2f, the overlay on" % [sight.fov, base, VehicleSight.zoom_turn(player)])
	sight.step_mag(1)
	await get_tree().process_frame
	var ten := sight.mag()
	var told := sight.cycle_channel()
	await get_tree().process_frame
	var thermal_on := ThermalView.mode == ThermalView.WHITE_HOT and sight.mag() == 3.0 and sight.overlay._post.visible
	sight.step_mag(9)
	await get_tree().process_frame
	var top := sight.mag()
	sight.cycle_channel()
	await get_tree().process_frame
	var black := ThermalView.mode == ThermalView.BLACK_HOT
	sight.cycle_channel()
	await get_tree().process_frame
	check(ten == 10.0 and told.begins_with("Thermal") and thermal_on and top == 25.0 and black and ThermalView.mode == ThermalView.OFF and sight.channel == "day" and sight.mag() == 10.0,
		"zoom to 10x; the channel key: thermal white-hot (3x to 25x), black-hot, back to day (where it was)")
	sight.close()
	await get_tree().process_frame
	check(not sight.up and not sight.current and player.camera.current and not sight.overlay.visible and ThermalView.mode == ThermalView.OFF, "down: the player's own view back")
	v.server_exit(player)
	await _physics(3)
	player.global_position = Vector3(0, 0.1, 0)
	v.queue_free()
	await _physics(2)


# --- Saving -------------------------------------------------------------------------------------

func _test_save() -> void:
	print("Saved with the zone")
	var v := await _spawn("abrams", Vector3(-700, RIG_Y, -300), 0.0)
	var crew := await _crew(v, [1, 2])
	v.hatches.auto_ai = false
	v.hatches.server_set(2, true, true)
	v.gunnery.server_set_fuze("m1147", "airburst")
	v.gunnery.server_set_return(false)
	v.gunnery.lase_data = {"ok": true, "fault": false, "why": "", "r": 1234.0, "first": 1234.0, "last": 1234.0, "multi": false, "seat": 1, "at": Soldier._now(),
		"rate": Vector2.ZERO, "trk": 0.0, "seed": 1}
	var rec: Dictionary = JSON.parse_string(JSON.stringify(v.to_save()))
	rec.erase("pos")
	rec.erase("rot")
	rec.erase("bodies")
	var copy := layer.server_spawn(v.model, Transform3D(Basis(), v.global_position + Vector3(0, 0, 20)), "", &"player", "%s_copy%d" % [v.vehicle_id, _n], rec)
	_n += 1
	copy.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	copy.freeze = true
	await _physics(3)
	var cg := copy.gunnery
	check(cg.fuze == {"m1147": "airburst"} and not cg.ret_last and bool(cg.lase_data.ok) and is_equal_approx(float(cg.lase_data.r), 1234.0) and copy.hatches.out.get(2, false) == true,
		"the copy comes back with the AMP on airburst, first return, 1,234 m lased, the commander's hatch open")
	copy.queue_free()
	await _clear(v, crew)


# --- Budgets ------------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Budgets (Proposed)")
	var v := await _spawn("abrams", Vector3(-900, RIG_Y, -300), 0.0)
	var crew := await _crew(v, [1, 2])
	var g := v.gunnery
	var steps: Array = []
	for i in 30:
		var t0 := Time.get_ticks_usec()
		g._physics_process(1.0 / 60.0)
		steps.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().physics_frame
	steps.sort()
	var step := float(steps[steps.size() / 2])
	var lases: Array = []
	for i in 20:
		var t0 := Time.get_ticks_usec()
		g.server_lase(1)
		lases.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	lases.sort()
	var lase := float(lases[lases.size() / 2])
	check(step < STEP_BUDGET_MS, "the gunnery's step on the host: %.3f ms (budget %.2f ms)" % [step, STEP_BUDGET_MS])
	check(lase < LASE_BUDGET_MS, "a lase and its solution: %.3f ms (budget %.1f ms)" % [lase, LASE_BUDGET_MS])
	await _clear(v, crew)


# --- Replication ----------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	var v := await _spawn("abrams", Vector3(-1100, RIG_Y, -300), 0.0)
	var crew := await _crew(v, [1, 2])
	v.hatches.auto_ai = false
	v.hatches.server_set(2, true, true)
	var g := v.gunnery
	var wall := _wall(g.sight_from(1) + Vector3(0, 0, -1500.5))
	await _physics(2)
	g.lay_on(g.sight_from(1) + Vector3(0, 0, -1500))
	v.turret.settle()
	await _physics(2)
	g.server_set_fuze("m830a1", "air")
	var l := g.server_lase(1)
	await _seconds(0.5)
	g._publish()
	v.hatches._publish()
	expect = {"mbt": String(v.vehicle_id), "r": float(l.get("r", 0.0)), "lay": [v.turret.lay.x, v.turret.lay.y], "head_y": _head(crew[1]).y}
	var log_path := OS.get_user_data_dir().path_join("gunnery_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/gunnery_test.tscn", "--", "--gunnery-join"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_failures >= 0, 200.0)
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
	wall.queue_free()
	await _clear(v, crew)


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
	get_tree().create_timer(190.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 120.0)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.mbt)) != null, 30.0)
		var v: Vehicle = find.call(String(expect.mbt))
		await _until(func() -> bool: return v != null and v.gunnery != null and bool(v.gunnery.lase_view().get("ok", false)) and v.occupant(2) != null, 20.0)
		await _seconds(1.0)
		var l: Dictionary = v.gunnery.lase_view() if v else {}
		var sv: Dictionary = v.gunnery.solution() if v else {}
		var lay: Array = sv.get("lay", [0, 0])
		note.call(v != null and absf(float(l.get("r", 0.0)) - float(expect.r)) < 0.2 and bool(sv.get("on", false))
			and absf(float(lay[0]) - float(expect.lay[0])) < 0.0005 and absf(float(lay[1]) - float(expect.lay[1])) < 0.0005,
			"the lase (%.0f m) and the solution's lay as the host has them (late join)" % float(l.get("r", 0.0)))
		note.call(v != null and String((v.gunnery.net_state.get("fz", {}) as Dictionary).get("m830a1", "")) == "air", "the HEAT-MP's air fuze")
		var cmd := v.occupant(2) if v else null
		note.call(cmd != null and v.hatches.is_out(2) and v.seat_open(2) and absf(cmd.camera.global_position.y - float(expect.head_y)) < 0.3,
			"the commander turned out, his head where the host has it (%.2f / %.2f)" % [cmd.camera.global_position.y if cmd else 0.0, float(expect.head_y)])
		note.call(v != null and v.readout_parts(1).any(func(p: Dictionary) -> bool: return String(p.text).begins_with("LRF ")), "the gunner's readout here gives the range")
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


# --- Helpers ------------------------------------------------------------------------------------

func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player", frozen := true) -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos), "", faction, "gn_%s_%d" % [model, _n])
	if frozen:
		v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		v.freeze = true
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(0.3 if frozen else 1.5)
	return v


func _crew(v: Vehicle, seats: Array) -> Array:
	var out: Array = []
	for seat: int in seats:
		var s := _soldier("%s%d_%d" % [v.model.capitalize(), seat, _n], &"friendly", v.global_position + Vector3(4.0, 0.0, float(seat)))
		await get_tree().physics_frame
		v.server_enter(s, seat)
		out.append(s)
		_n += 1
	await _seconds(0.5)
	return out


func _soldier(callsign: String, faction: StringName, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _clear(v: Vehicle, people: Array) -> void:
	if is_instance_valid(v):
		for s: Soldier in v.occupants():
			v.server_exit(s)
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	await _physics(2)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
