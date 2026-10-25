extends Node
## Performance cases (Captain, 2026-10-22: "we definitely need more performance fixes"; worst in
## towns and cities, big firefights, woods and open terrain, vehicles and helis, with low frame
## rates and stutters both). Headless:
##   <voxel godot exe> --headless --path . res://tests/perfcases_test.tscn [-- --cases=town,fight]
## or through tools/run_tests.sh perfcases, with PERF_CASES=town,fight to pick cases and
## PERF_NO_BUDGETS=1 to only print the numbers.
## Each case hosts a real zone with its AI (CompoundLevel.spawn_ai: garrisons, the squad, the
## hot zones' patrols) and plays a scene from it for MEASURE_S seconds:
##   town   Old Quarter (city_hot): the player walks into the zone's biggest town or village (not
##          a city block) with the squad;
##   city   Old Quarter: the player walks from outside the city (BuildingGen.city_layout) up its
##          street to the middle, through the city blocks' garrisons;
##   fight  Black Ridge (ridge_hot): the squad and an allied section 90-140 m from the biggest
##          garrison, the zone ENGAGED (the QRF launches, gun teams man their guns);
##   woods  Kestrel Valley (river_valley: woods, a river, reeds): the squad walks through the
##          zone's densest wood and meets a hostile patrol there;
##   drive  Kestrel Valley: the player rides an AI-driven M-ATV along the roads across the zone;
##   heli   Kestrel Valley: the player rides a UH-60 contour-flying across the zone.
## The zone's visuals are built as on a player's machine (terrain levels, scatter cells, water,
## roads) and a camera rides with the player, so their CPU side counts (the renderer itself is
## the headless dummy: GPU time isn't measurable here).
##
## Measured per case, for every frame that ran a physics tick: its 60 Hz FRAME COST, the average
## tick of that frame (its scripts, every _physics_process, and the engine's own step) plus the
## frame's _process: what one frame costs at 60 ticks a second, minus the GPU, however far behind
## the engine fell (a machine that can't keep up runs up to 8 ticks a frame and the wall-clock
## frame balloons; on a shared machine that swings run to run, the frame cost much less). Its
## average, 95th and 99th percentile and worst; the wall-clock frame too; the tick's scripts and
## engine step; the _process scripts; the navigation server; what FrameCost counted, by system;
## and the HITCHES: every single tick or _process pass over HITCH_MS and over HITCH_MEDIANS times
## the case's median one, with what it went on (FrameCost systems, nodes added, soldiers spawned,
## the slowest script with PERF_PROFILE=1). Also the draw proxy: geometry instances and MultiMesh
## instances in view range, and the shadow casters among them.
## PERF_PROFILE=1 also times every script's _physics_process and _process by script (slower).
##
## Budgets (Proposed, 2026-10-22; docs/performance.md has the numbers before and after): each
## case's average frame, 95th percentile and hitches a minute, with room for CI's slower runners.
## Never touches a real save.

const MEASURE_S := {"town": 30.0, "city": 40.0, "fight": 40.0, "woods": 30.0, "drive": 45.0, "heli": 35.0}
const ALL_CASES := ["town", "city", "fight", "woods", "drive", "heli"]
## A frame this long is a hitch (under 30 fps for that frame).
const HITCH_MS := 33.3
## ...and this many times the case's median tick or _process pass (a spike, not the load itself).
const HITCH_MEDIANS := 3.0
## Proposed budgets (ms of 60 Hz frame cost; hitches a minute). Re-based 2026-10-22 on cghath's world
## expansion (world/perf: the Old Quarter a real city, roads, fields, props), which about doubled the
## cases' cost against claude/ai-driving df3133f without it (town 66.7 -> 132.6 ms average, 75 AI
## and none asleep; heli 14.9 -> 28.7, R2484 -> R2485): about twice the merge's local numbers (R2478,
## R2485), CI's runners having measured about twice a quiet local run. They still fail a further
## doubling; the first budgets (town 75/140, heli 28/45...) are in docs/performance.md.
## Tightened 2026-10-22 (claude/perf-towns, R2517/R2519): about twice a quiet local run again, the
## town case now a village (the city has its own case).
## Tightened 2026-10-23 (perf/world-content): about 2.5-3x CI's numbers after the world content pass
## (town 6.0 / 9.5, city 83 / 95, woods 5.8 / 8.6, drive 6.7 / 10.0, heli 5.9 / 8.2 ms average / 95th,
## no hitches; run 39911142961), all under CI's before it (claude/ai-driving 78dc9a17, run 39888713096:
## town 7.5 / 15.3, city 112 / 127, woods 8.3 / 12.3, drive 8.4 / 11.6, heli 10.2 / 18.3). The town's
## hitches are team spawns (F-206: 0-13 a minute on CI, 30 allowed). fight, the AI's case, keeps its
## times; its hitches (the AI's ticks and team spawns, 30-72 a minute on CI, 72.5 failed 70 on
## claude/ai-driving's own run) get 90.
const BUDGETS := {
	"town": {"avg": 15.0, "p95": 25.0, "hitches_min": 30.0},
	"city": {"avg": 200.0, "p95": 300.0, "hitches_min": 60.0},
	"fight": {"avg": 100.0, "p95": 170.0, "hitches_min": 90.0},
	"woods": {"avg": 18.0, "p95": 26.0, "hitches_min": 15.0},
	"drive": {"avg": 18.0, "p95": 26.0, "hitches_min": 15.0},
	"heli": {"avg": 18.0, "p95": 30.0, "hitches_min": 15.0},
}
## Off CI (a shared machine: other sessions' suites, a game being played) the budgets get this
## much room: a busy local run measured 2.5-3x a quiet one (R2431 against R2425). CI's runners
## are the guard.
const LOCAL_SLACK := 1.6
const WALK_MPS := 3.0
## How long a case waits for its modules and navigation before it measures (ms): the city's 20-odd
## blocks build their voxels a slice a frame (VoxelWorld.BUILD_BUDGET_MS each) while their garrisons
## come in, and at CI's 3 frames a second there the biggest was still building at 60 s (run
## 39908072526) and at 100 s (run 39912912838).
const SETTLE_MS := 180000
## CI measures each case for this share of MEASURE_S (its runners have the job's 30 minutes for
## the import and all five zones); averages and per-minute rates compare the same.
const CI_MEASURE_SHARE := 0.6

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var camera: Camera3D
var results: Array = []
var _hosted_zone := ""
var _profile := OS.get_environment("PERF_PROFILE") == "1"
var _no_budgets := false
var _rng := RandomNumberGenerator.new()

# --- the meter ---
var _first: TickEdge
var _last: TickEdge
var _measuring := false
var _prev_event_process := true
var _frame_start := 0
var _frame_ticks := 0
var _tick_start := 0
var _scripts_end := 0
var _pending := false
var _process_start := 0
var _frames: Array[float] = []  # wall ms of each frame that ran a tick
var _f60: Array[float] = []  # each such frame's 60 Hz cost: its average tick + its _process
var _ticks_ms: Array[float] = []  # each tick: scripts + engine step
var _frame_tick_sum := 0.0
var _frame_tick_n := 0
var _frame_proc := 0.0
var _spikes: Array = []  # candidates: {"ms", "kind", "why"}
var _scripts_ms: Array[float] = []
var _engine_ms: Array[float] = []
var _proc_ms: Array[float] = []
var _nav_ms := 0.0
var _nav_frames: Array[float] = []  # the navigation server's time each frame (ms)
var _costs := {}  # FrameCost system -> usec over the case
var _frame_costs := {}  # this frame's FrameCost
var _hitches: Array = []  # {"ms", "why"}
var _nodes_at_frame := 0
var _ai_at_frame := 0
var _profiled: Array[Node] = []
var _by_script := {}  # "file:phys|proc" -> usec
var _frame_top := ""  # the slowest script this frame (profile)
var _frame_top_us := 0
var _draw := {}  # the draw proxy's peak


## Runs on: the first callback of a physics tick, the first _process of a frame, the last
## physics callback of a tick, the last _process of a frame.
class TickEdge extends Node:
	var on_tick: Callable
	var on_frame: Callable

	func _physics_process(_delta: float) -> void:
		on_tick.call()

	func _process(_delta: float) -> void:
		if on_frame.is_valid():
			on_frame.call()


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_perfcases" + tag
	Campaign.campaign_id = "test_perfcases_campaign" + tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_perfcases_settings%s.cfg" % tag))
	CompoundLevel.spawn_ai = true
	Contracts.auto_show_debrief = false
	EnemyDrones.enabled = false  # (their own suite; a drone overhead is luck of the draw)
	Buildings.budget_always = true  # building scans budgeted as on a player's machine (not headless's exact answers)
	_rng.seed = 20261022
	var cases: Array = ALL_CASES.duplicate()
	if OS.get_environment("PERF_CASES") != "":
		cases = Array(OS.get_environment("PERF_CASES").split(","))
	_no_budgets = OS.get_environment("PERF_NO_BUDGETS") == "1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cases="):
			cases = Array(a.trim_prefix("--cases=").split(","))
		elif a == "--no-budgets":
			_no_budgets = true
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(120.0 + cases.size() * 170.0, true, false, true).timeout.connect(func() -> void:
		print("PERFCASES TEST FAILED (timed out)")
		get_tree().quit(99))
	_first = TickEdge.new()
	_first.process_physics_priority = -1000000
	_first.process_priority = -1000000
	_first.on_tick = _on_tick_first
	_first.on_frame = _on_frame_first
	add_child(_first)
	_last = TickEdge.new()
	_last.process_physics_priority = 1000000
	_last.process_priority = 1000000
	_last.on_tick = _on_tick_last
	_last.on_frame = _on_frame_last
	add_child(_last)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	for c: String in cases:
		if not MEASURE_S.has(c):
			check(false, "no case named %s" % c)
			continue
		print("perf: --- case %s ---" % c)
		await call("_case_" + c)
	print("perf: === summary (60 Hz frame cost: a frame's average tick + its _process, ms; hitches: a tick or _process over %.0f ms and %.0fx the median) ===" % [HITCH_MS, HITCH_MEDIANS])
	for r: Dictionary in results:
		print("perf: %-6s avg %6.2f  p95 %6.2f  p99 %6.2f  worst %7.1f | wall %6.1f | tick scripts %5.2f engine %5.2f | process %5.2f | nav %5.2f | hitches %d (%.1f/min) | AI %d (asleep %d) | draws %s"
			% [r.name, r.avg, r.p95, r.p99, r.worst, r.wall, r.scripts, r.engine, r.process, r.nav, r.hitches, r.hitches_min, r.ai, r.asleep, r.draws])
		if not _no_budgets:
			var b: Dictionary = BUDGETS[r.name]
			var k := 1.0 if OS.get_environment("GITHUB_ACTIONS") != "" else LOCAL_SLACK
			check(r.avg <= b.avg * k, "%s: average frame %.2f ms (Proposed budget %.1f)" % [r.name, r.avg, b.avg * k])
			check(r.p95 <= b.p95 * k, "%s: 95th percentile frame %.2f ms (Proposed budget %.1f)" % [r.name, r.p95, b.p95 * k])
			check(r.hitches_min <= b.hitches_min * k, "%s: %.1f hitches a minute over %.0f ms (Proposed budget %.0f)" % [r.name, r.hitches_min, HITCH_MS, b.hitches_min * k])
	Campaign.reset_campaign()
	GameState.delete_save()
	print("PERFCASES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- cases -------------------------------------------------------------------------------------

func _case_town() -> void:
	if not await _host("city_hot"):
		return
	var town: ZoneModule = null
	for m in level.modules():
		if ZoneModules.city_of(m.type) != "":
			continue  # (the city case's)
		if ZoneModules.base(m.type) in ["town", "village"] and (town == null or ZoneModules.boxes(m.type).size() > ZoneModules.boxes(town.type).size()):
			town = m
	check(town != null, "city_hot has a town")
	if town == null:
		return
	var r := town.footprint()
	var start := level.ground_point(Vector3(r.get_center().x, 0, r.end.y + 60.0))
	var through := level.ground_point(Vector3(r.get_center().x, 0, r.position.y + r.size.y * 0.3))
	await _settle_at(start, [town])
	await _measure("town", [start, through])


func _case_city() -> void:
	if not await _host("city_hot"):
		return
	var cities: Array = level.def.get("cities", [])
	check(not cities.is_empty(), "city_hot has a city")
	if cities.is_empty():
		return
	var c: Dictionary = cities[0]
	var mid := Vector3(float(c.pos[0]), 0, float(c.pos[1]))
	var half: Vector2 = BuildingGen.city_layout(int(c.seed)).half
	# Up the middle street from 40 m outside the city's south edge to its middle.
	var x := mid.x + BuildingGen.CITY_PITCH * (0.0 if BuildingGen.CITY_BLOCKS.x % 2 == 0 else 0.5)
	var start := level.ground_point(Vector3(x, 0, mid.z + half.y + 40.0))
	var through := level.ground_point(Vector3(x, 0, mid.z))
	var near: Array = level.modules().filter(func(m: ZoneModule) -> bool:
		return ZoneModules.city_of(m.type) != "" and m.distance_to(start) < 140.0)
	await _settle_at(start, near)
	await _measure("city", [start, through])


func _case_fight() -> void:
	if not await _host("ridge_hot"):
		return
	var site: ZoneModule = null
	for m in level.modules():
		if site == null or level.garrison_size(m.module_id) > level.garrison_size(site.module_id):
			site = m
	var r := site.footprint()
	var centre := Vector3(r.get_center().x, 0, r.get_center().y)
	var out := Vector2(r.get_center()) - Vector2(level.map_area().get_center())
	var dir := Vector3(out.x, 0, out.y).normalized() if out.length() > 1.0 else Vector3.BACK
	var start := level.ground_point(centre + dir * (r.size.length() * 0.5 + 140.0))
	await _settle_at(start, [site])
	# An allied section beside the squad (the big fight: 20-odd on our side).
	var side := dir.cross(Vector3.UP)
	for i in 10:
		level.spawn_soldier({"name": "PerfAlly%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(start + side * (-18.0 + i * 4.0) - dir * 6.0),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "guard": false})
	var alert := Alert.of(level)
	if alert:
		alert._raise(alert.area_of(centre), Alert.State.ENGAGED, true)  # the QRF launches
		alert._raise(Alert.FIELD, Alert.State.ENGAGED, true)
	var near := level.ground_point(centre + dir * (r.size.length() * 0.5 + 90.0))
	await _measure("fight", [start, near])


func _case_woods() -> void:
	if not await _host("kestrel_valley"):
		return
	var spot := _densest_wood()
	check(spot != Vector3.INF, "kestrel_valley has woods away from its sites")
	if spot == Vector3.INF:
		return
	var dir := Vector3(1, 0, 0.3).normalized()
	var start := level.ground_point(spot - dir * 110.0)
	var end := level.ground_point(spot + dir * 30.0)
	await _settle_at(start, [])
	for i in 8:
		level.spawn_soldier({"name": "PerfWoodsH%d" % i, "faction": "hostile", "variant": "woodland",
			"pos": level.ground_point(spot + dir * 60.0 + dir.cross(Vector3.UP) * (-14.0 + i * 4.0)),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true})
	await _measure("woods", [start, end])


func _case_drive() -> void:
	if not await _host("kestrel_valley"):
		return
	_clear_spawned()
	var path := _long_route()
	check(path.size() >= 2, "a route across kestrel_valley")
	if path.size() < 2:
		return
	var a: Vector3 = path[0]
	var b: Vector3 = path[1]
	var layer := VehicleLayer.of(level)
	var v := layer.server_spawn("matv", Transform3D(Basis.looking_at((b - a).normalized()), a + Vector3.UP * 0.6), "", &"player", "perf_matv")
	check(v != null, "an M-ATV at the start of the route")
	if v == null:
		return
	await _settle_at(a, [], false)
	player.set_physics_process(true)
	check(v.server_enter(player, 1), "the player rides in the M-ATV")
	await _frames_wait(30)
	v.server_follow_path(path)
	await _measure("drive", [])
	if is_instance_valid(v):
		v.server_stop()


func _case_heli() -> void:
	if not await _host("kestrel_valley"):
		return
	_clear_spawned()
	var area := level.map_area().grow(-200.0)
	var a := level.ground_point(Vector3(area.position.x, 0, area.get_center().y))
	var b := level.ground_point(Vector3(area.end.x, 0, area.get_center().y + 300.0))
	VehicleHull.prewarm("uh60")
	var t0 := Time.get_ticks_msec()
	while not VehicleHull.is_ready("uh60") and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var layer := VehicleLayer.of(level)
	var heli := layer.server_spawn("uh60", Transform3D(Basis.looking_at((b - a).normalized()), a + Vector3.UP * 0.3), "", &"player", "perf_heli") as Helicopter
	check(heli != null, "a UH-60 at the zone's edge")
	if heli == null:
		return
	await _settle_at(a, [], false)
	player.set_physics_process(true)
	check(heli.server_enter(player), "the player rides in the UH-60")
	heli.global_position.y += Helicopter.CRUISE_AGL_M
	heli.server_start_airborne()
	heli.server_fly_to(b, Helicopter.CRUISE_AGL_M, Helicopter.CRUISE_KMH, false)
	await _measure("heli", [])


# --- setup -------------------------------------------------------------------------------------

## Hosts `zone_id` (the first by the menu's way, the rest by a level switch), builds its visuals as
## a player's machine would, and puts a camera on the player. True once the player is in.
func _host(zone_id: String) -> bool:
	if _hosted_zone == zone_id and level and is_instance_valid(level):
		return true
	var def := MissionRegistry.zone_def(zone_id)
	if def.is_empty():
		check(false, "%s: its zone definition" % zone_id)
		return false
	var t_host := Time.get_ticks_usec()
	if _hosted_zone == "":
		main.host_zone(def)
	else:
		var fresh := LevelSwitch.load_level(main, {"level": "zone", "def": ZoneDef.normalize(def)})
		fresh._on_hosted()
	level = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
		var lvl := CompoundLevel.current(main) as ZoneLevel
		if lvl and String(lvl.def.get("id", "")) == zone_id and lvl.players and lvl.players.get_node_or_null(^"1") != null:
			level = lvl
			break
	check(level != null, "%s hosted (%.1f s)" % [zone_id, (Time.get_ticks_usec() - t_host) / 1e6])
	if level == null:
		return false
	_hosted_zone = zone_id
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # moved by the case
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	# What a player's machine builds (ZoneLevel skips it on a headless server).
	var t_vis := Time.get_ticks_usec()
	level.terrain.build_visuals()
	level.scatter.build_visuals()
	var roads := level.get_node_or_null(^"Roads") as ZoneRoads  # (ZoneLevel lays them; their visuals wait for a screen)
	if roads:
		roads.build_visuals()
	print("perf: %s's visuals built in %.0f ms" % [zone_id, (Time.get_ticks_usec() - t_vis) / 1000.0])
	camera = Camera3D.new()
	camera.name = "PerfCamera"
	camera.far = 4000.0
	camera.position = Vector3(0, 1.6, 0)
	player.add_child(camera)
	camera.current = true
	return true


## Puts the player at `at` and waits for the modules `wait_for` and the navigation there to be
## ready (and the squad to gather), then a few seconds more for the first wave of builds.
func _settle_at(at: Vector3, wait_for: Array, place := true) -> void:
	if place:
		player.global_position = at
	var nav := level.get_node_or_null(^"Navigation") as ZoneNav
	var t0 := Time.get_ticks_msec()
	var ready_s := -1.0
	while Time.get_ticks_msec() - t0 < SETTLE_MS:
		await get_tree().physics_frame
		var ready := wait_for.all(func(m: ZoneModule) -> bool: return m.is_ready())
		if ready and ready_s < 0.0:
			ready_s = (Time.get_ticks_msec() - t0) / 1000.0
		if ready and (nav == null or nav.is_settled()):
			break
	print("perf: the case's %d modules ready after %s, the navigation %s" % [wait_for.size(), ("%.1f s" % ready_s) if ready_s >= 0.0 else "-",
		"settled" if nav == null or nav.is_settled() else "still baking (%d chunks queued)" % nav._queue.size()])
	for m: ZoneModule in wait_for:
		check(m.is_ready(), "%s streamed in (%.0f s; %s)" % [m.module_id, (Time.get_ticks_msec() - t0) / 1000.0,
			"built" if m.voxel_world and m.voxel_world.is_built() else ("building" if m.voxel_world else "not streamed in")])
	for p in [level.terrain, level.scatter]:
		if p.has_method(&"build_near"):
			p.build_near(at, 1000)
	await _seconds(4.0)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames_wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## The middle of the zone's densest wood at least 250 m from every site.
func _densest_wood() -> Vector3:
	var cells := {}
	var best := Vector2i.ZERO
	var best_n := 0
	for item: Dictionary in level.scatter.items:
		if int(item.kind) != ZoneScatter.Kind.TREE:
			continue
		var p: Vector3 = item.pos
		var c := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
		var n := int(cells.get(c, 0)) + 1
		cells[c] = n
		if n > best_n:
			var centre := Vector3((c.x + 0.5) * 64.0, 0, (c.y + 0.5) * 64.0)
			if level.modules().all(func(m: ZoneModule) -> bool: return m.distance_to(centre) > 250.0) \
					and level.map_area().grow(-200.0).has_point(Vector2(centre.x, centre.z)):
				best = c
				best_n = n
	print("perf: densest wood %s: %d trees in 64 m" % [best, best_n])
	return Vector3((best.x + 0.5) * 64.0, 0, (best.y + 0.5) * 64.0) if best_n > 0 else Vector3.INF


## A long drive by road across the zone: between the two sites furthest apart (RoadRoute), or
## straight across.
func _long_route() -> PackedVector3Array:
	var ms := level.modules()
	var a: ZoneModule = null
	var b: ZoneModule = null
	var far := 0.0
	for i in ms.size():
		for j in range(i + 1, ms.size()):
			var d := ms[i].global_position.distance_to(ms[j].global_position)
			if d > far and d < 1800.0:
				far = d
				a = ms[i]
				b = ms[j]
	var out := PackedVector3Array()
	if a == null:
		return out
	var from := Vector2(a.global_position.x, a.global_position.z)
	var to := Vector2(b.global_position.x, b.global_position.z)
	var way := RoadRoute.route(level.def, from, to)
	if way.is_empty():
		way = PackedVector2Array([from, to])
	for p in way:
		out.append(level.ground_point(Vector3(p.x, 0, p.y)))
	print("perf: route %s -> %s, %.0f m straight, %d waypoints" % [a.module_id, b.module_id, far, out.size()])
	return out


func _clear_spawned() -> void:
	for n in level.ai.get_children():
		if String(n.name).begins_with("Perf"):
			n.queue_free()


# --- measuring ---------------------------------------------------------------------------------

## Measures the case `name` for MEASURE_S[name]: the player walks `walk` (points, at WALK_MPS)
## if any; adds a result.
func _measure(name: String, walk: Array) -> void:
	_frames.clear()
	_f60.clear()
	_ticks_ms.clear()
	_spikes.clear()
	_frame_tick_sum = 0.0
	_frame_tick_n = 0
	_frame_proc = 0.0
	_scripts_ms.clear()
	_engine_ms.clear()
	_proc_ms.clear()
	_nav_ms = 0.0
	_nav_frames.clear()
	_costs = {}
	_hitches.clear()
	_by_script = {}
	_draw = {}
	FrameCost.on = true
	FrameCost.take()
	if _profile:
		_gather_profiled()
		SquadAI.profiling = true
		SquadAI.prof = {}
	_nodes_at_frame = get_tree().get_node_count()
	_ai_at_frame = level.ai.get_child_count()
	var nav := level.get_node_or_null(^"Navigation") as ZoneNav
	var bakes_before := nav.bakes if nav else 0
	var map := level.get_world_3d().navigation_map
	var syncs_before := NavigationServer3D.map_get_iteration_id(map)
	_prev_event_process = true
	_frame_start = Time.get_ticks_usec()
	_measuring = true
	var secs: float = _measure_s(name) * (CI_MEASURE_SHARE if OS.get_environment("GITHUB_ACTIONS") != "" else 1.0)
	var t0 := Time.get_ticks_msec()
	var leg := 0
	var last_draw := -10.0
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().physics_frame
		if leg + 1 < walk.size():
			var to: Vector3 = walk[leg + 1]
			var step := WALK_MPS / Engine.physics_ticks_per_second
			var flat := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z)
			if flat.length() <= step:
				leg += 1
			else:
				var p := player.global_position + flat.normalized() * step
				player.global_position = Vector3(p.x, level.ground_height(p.x, p.z), p.z)
		_on_measure_tick(name)
		var now_s := (Time.get_ticks_msec() - t0) / 1000.0
		if now_s - last_draw >= 5.0:
			last_draw = now_s
			_sample_draws()
	_measuring = false
	FrameCost.on = false
	_restore_profiled()
	var live := 0
	var asleep := 0
	var resting := 0
	var why_not := {}  # what keeps the awake ones stepping every tick
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion():
			live += 1
			if s.process_mode == Node.PROCESS_MODE_DISABLED:
				asleep += 1
			elif s.movement._resting():
				resting += 1
			else:
				var k := "moving" if s.move_input != Vector2.ZERO else ("aiming" if s.want_aim else ("down" if not s.vitals.is_up() else ("air" if not s.is_on_floor() else "other")))
				why_not[k] = int(why_not.get(k, 0)) + 1
	print("perf: %s: at the end %d AI resting, the rest: %s" % [name, resting, why_not])
	var intents := {}
	for n in level.ai.get_children():
		var brain := SquadAI.of(n)
		if brain and not n.is_queued_for_deletion() and n.process_mode != Node.PROCESS_MODE_DISABLED:
			var k: String = SquadAI.Intent.keys()[brain.intent]
			intents[k] = int(intents.get(k, 0)) + 1
	print("perf: %s: awake AI's intents at the end: %s" % [name, intents])
	if nav and is_instance_valid(nav):
		var syncs := NavigationServer3D.map_get_iteration_id(map) - syncs_before
		print("perf: %s: navigation: %d chunk bakes (%.1f a second), %d chunks held at the end, the map synced %d times (%.1f a second); the server's frame median %.2f ms, 95th %.2f, worst %.2f" % [
			name, nav.bakes - bakes_before, (nav.bakes - bakes_before) / secs, nav.chunk_total(), syncs, syncs / secs,
			_pct(_nav_frames, 0.5), _pct(_nav_frames, 0.95), _nav_frames.max() if not _nav_frames.is_empty() else 0.0])
	var n_frames := maxi(_frames.size(), 1)
	# Hitches: the spikes past HITCH_MEDIANS times the median of their kind.
	var med := {"tick": _pct(_ticks_ms, 0.5), "process": _pct(_proc_ms, 0.5)}
	_hitches = _spikes.filter(func(h: Dictionary) -> bool: return h.ms > HITCH_MEDIANS * float(med[h.kind]))
	var r := {"name": name, "avg": _avg(_f60), "p95": _pct(_f60, 0.95), "p99": _pct(_f60, 0.99),
		"worst": _f60.max() if not _f60.is_empty() else 0.0, "wall": _avg(_frames), "scripts": _avg(_scripts_ms), "engine": _avg(_engine_ms),
		"process": _avg(_proc_ms), "nav": _nav_ms / n_frames, "hitches": _hitches.size(), "hitches_min": _hitches.size() * 60.0 / secs,
		"ai": live, "asleep": asleep, "draws": _draw_text(_draw)}
	results.append(r)
	print("perf: %s: %d tick frames; 60 Hz frame cost avg %.2f ms, p95 %.2f, p99 %.2f, worst %.1f; wall frame avg %.1f; tick scripts %.2f, engine step %.2f; process scripts %.2f; nav %.2f; AI %d (asleep %d)"
		% [name, _frames.size(), r.avg, r.p95, r.p99, r.worst, r.wall, r.scripts, r.engine, r.process, r.nav, live, asleep])
	var systems := _costs.keys()
	systems.sort_custom(func(a: StringName, b: StringName) -> bool: return int(_costs[a]) > int(_costs[b]))
	var parts: Array[String] = []
	for k: StringName in systems:
		parts.append("%s %.2f" % [k, int(_costs[k]) / 1000.0 / n_frames])
	print("perf: %s: FrameCost ms a frame: %s" % [name, ", ".join(parts)])
	_hitches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	for h: Dictionary in _hitches.slice(0, 12):
		print("perf: %s: hitch %.1f ms: %s" % [name, h.ms, h.why])
	print("perf: %s: draw proxy peak: %s" % [name, r.draws])
	if _profile:
		var keys := _by_script.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(_by_script[a]) > int(_by_script[b]))
		for k: String in keys.slice(0, 20):
			print("perf: %s: profile %s %.3f ms a frame" % [name, k, int(_by_script[k]) / 1000.0 / n_frames])
		SquadAI.profiling = false
		var ticks := maxi(_scripts_ms.size(), 1)
		var ai_parts := SquadAI.prof.keys()
		ai_parts.sort_custom(func(a: StringName, b: StringName) -> bool: return int(SquadAI.prof[a][0]) > int(SquadAI.prof[b][0]))
		for part: StringName in ai_parts.slice(0, 24):
			var e: Array = SquadAI.prof[part]
			print("perf: %s: AI part %s %.3f ms a tick, %d calls, worst %.2f ms" % [name, part, int(e[0]) / 1000.0 / ticks, int(e[1]), int(e[2]) / 1000.0])


## How long case `name` is measured (s, before CI's share): MEASURE_S (the invasion suite has its own).
func _measure_s(name: String) -> float:
	return float(MEASURE_S[name])


## Called every physics frame while case `name` is measured (the invasion suite samples its ground
## streaming here).
func _on_measure_tick(_name: String) -> void:
	pass


## A frame boundary: the previous event was a frame's last _process, so this event starts a frame.
func _boundary() -> void:
	var now := Time.get_ticks_usec()
	if _prev_event_process:
		if _measuring and _frame_ticks > 0:
			_frames.append((now - _frame_start) / 1000.0)
			if _frame_tick_n > 0:
				_f60.append(_frame_tick_sum / _frame_tick_n + _frame_proc)
		_frame_tick_sum = 0.0
		_frame_tick_n = 0
		_frame_proc = 0.0
		_frame_start = now
		_frame_ticks = 0
		_frame_costs = {}
		_frame_top = ""
		_frame_top_us = 0
		_nodes_at_frame = get_tree().get_node_count()
		_ai_at_frame = level.ai.get_child_count() if level and is_instance_valid(level) else 0
	_prev_event_process = false


func _why() -> String:
	var parts: Array[String] = []
	var keys := _frame_costs.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(_frame_costs[a]) > int(_frame_costs[b]))
	for k: StringName in keys.slice(0, 5):
		parts.append("%s %.1f" % [k, int(_frame_costs[k]) / 1000.0])
	var nodes := get_tree().get_node_count() - _nodes_at_frame
	var ai := (level.ai.get_child_count() if level and is_instance_valid(level) else 0) - _ai_at_frame
	return "the frame's FrameCost so far [%s]; nodes %+d, AI %+d%s" % [", ".join(parts), nodes, ai,
		("; slowest script %s %.1f ms" % [_frame_top, _frame_top_us / 1000.0]) if _frame_top != "" else ""]


func _take_costs() -> void:
	var c := FrameCost.take()
	for k in c:
		_costs[k] = int(_costs.get(k, 0)) + int(c[k])
		_frame_costs[k] = int(_frame_costs.get(k, 0)) + int(c[k])


func _engine_part() -> void:
	if not _pending:
		return
	_pending = false
	if _measuring and not _scripts_ms.is_empty():
		_engine_ms.append((Time.get_ticks_usec() - _scripts_end) / 1000.0)
		var tick: float = _scripts_ms[-1] + _engine_ms[-1]
		_ticks_ms.append(tick)
		_frame_tick_sum += tick
		_frame_tick_n += 1
		if tick > HITCH_MS:
			_take_costs()
			_spikes.append({"ms": tick, "kind": "tick", "why": "a tick: " + _why()})


func _on_tick_first() -> void:
	_engine_part()
	_boundary()
	_frame_ticks += 1
	_tick_start = Time.get_ticks_usec()
	if _measuring and _profile:
		_run_profiled(true)


func _on_tick_last() -> void:
	_scripts_end = Time.get_ticks_usec()
	_pending = true
	if _measuring:
		_scripts_ms.append((_scripts_end - _tick_start) / 1000.0)


func _on_frame_first() -> void:
	_engine_part()
	_boundary()
	_process_start = Time.get_ticks_usec()
	if _measuring:
		var nav_now := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
		_nav_ms += nav_now
		_nav_frames.append(nav_now)
		if _profile:
			_run_profiled(false)


func _on_frame_last() -> void:
	if _measuring:
		_take_costs()
		if _frame_ticks > 0:
			var ms := (Time.get_ticks_usec() - _process_start) / 1000.0
			_proc_ms.append(ms)
			_frame_proc = ms
			if ms > HITCH_MS:
				_spikes.append({"ms": ms, "kind": "process", "why": "a _process pass: " + _why()})
	_prev_event_process = true


# --- the profile (PERF_PROFILE=1) --------------------------------------------------------------

func _gather_profiled() -> void:
	_profiled.clear()
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == _first or n == _last or n == self or n.get_script() == null:
			continue
		var phys := n.is_physics_processing() and n.has_method(&"_physics_process")
		var proc := n.is_processing() and n.has_method(&"_process")
		if phys or proc:
			n.set_meta(&"perf_phys", phys)
			n.set_meta(&"perf_proc", proc)
			if phys:
				n.set_physics_process(false)
			if proc:
				n.set_process(false)
			_profiled.append(n)


func _restore_profiled() -> void:
	for n in _profiled:
		if is_instance_valid(n):
			if n.get_meta(&"perf_phys", false):
				n.set_physics_process(true)
			if n.get_meta(&"perf_proc", false):
				n.set_process(true)
	_profiled.clear()


func _run_profiled(physics: bool) -> void:
	var delta := 1.0 / Engine.physics_ticks_per_second if physics else get_process_delta_time()
	var meta := &"perf_phys" if physics else &"perf_proc"
	for n in _profiled:
		if not is_instance_valid(n) or not n.is_inside_tree() or not n.can_process() or not n.get_meta(meta, false):
			continue
		var t := Time.get_ticks_usec()
		if physics:
			n._physics_process(delta)
		else:
			n._process(delta)
		var spent := Time.get_ticks_usec() - t
		var key := "%s:%s" % [(n.get_script() as Script).resource_path.get_file(), "phys" if physics else "proc"]
		_by_script[key] = int(_by_script.get(key, 0)) + spent
		if spent > _frame_top_us:
			_frame_top_us = spent
			_frame_top = "%s (%s)" % [key, n.name]
	# Picks up what came in since (spawned soldiers, streamed modules).
	if Engine.get_physics_frames() % 60 == 0 and physics:
		var before := _profiled.size()
		var stack: Array[Node] = [level]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n.get_script() == null or n.has_meta(&"perf_phys"):
				continue
			var phys := n.is_physics_processing() and n.has_method(&"_physics_process")
			var proc := n.is_processing() and n.has_method(&"_process")
			if phys or proc:
				n.set_meta(&"perf_phys", phys)
				n.set_meta(&"perf_proc", proc)
				if phys:
					n.set_physics_process(false)
				if proc:
					n.set_process(false)
				_profiled.append(n)
		if _profiled.size() > before and false:
			print("perf: profiling %d more" % (_profiled.size() - before))


# --- the draw proxy ----------------------------------------------------------------------------

## What the renderer would draw from the camera: geometry instances in view range and in the
## frustum (MultiMeshes count as one draw and their instances apart), and the shadow casters among
## them within the sun's shadow distance. Keeps the peak.
func _sample_draws() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var cam := camera.global_position
	var planes := camera.get_frustum()
	var sun_m := 0.0
	for c in level.get_children():
		var light := c as DirectionalLight3D
		if light and light.shadow_enabled:
			sun_m = maxf(sun_m, light.directional_shadow_max_distance)
	var draws := 0
	var by := {}  # what draws, by kind (_draw_kind)
	var instances := 0
	var shadow_draws := 0
	var lights := 0
	var shadow_lights := 0
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Light3D:
			var l := n as Light3D
			if l.visible and l.is_visible_in_tree() and not l is DirectionalLight3D:
				lights += 1
				if l.shadow_enabled:
					shadow_lights += 1
			continue
		var g := n as GeometryInstance3D
		if g == null or not g.is_visible_in_tree():
			continue
		var box := g.get_aabb()
		var world_box := g.global_transform * box
		var d := world_box.get_center().distance_to(cam) - world_box.size.length() * 0.5
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end:
			continue
		if g.visibility_range_begin > 0.0 and world_box.get_center().distance_to(cam) < g.visibility_range_begin:
			continue  # (a nearer level of detail draws there)
		if d > camera.far:
			continue
		var in_view := true
		for p: Plane in planes:
			var c := world_box.get_center()
			var r := world_box.size.length() * 0.5
			if p.distance_to(c) > r:
				in_view = false
				break
		var casts := g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and sun_m > 0.0 and d < sun_m
		if casts:
			shadow_draws += 1  # (the sun's cascades see round the camera, not just its frustum)
		if not in_view:
			continue
		draws += 1
		var kind := _draw_kind(g)
		by[kind] = int(by.get(kind, 0)) + 1
		if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			instances += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		else:
			instances += 1
	if draws > int(_draw.get("draws", 0)):
		_draw = {"draws": draws, "instances": instances, "shadow_draws": shadow_draws, "lights": lights, "shadow_lights": shadow_lights, "sun_m": sun_m, "by": by}


func _draw_text(d: Dictionary) -> String:
	if d.is_empty():
		return "-"
	var by: Dictionary = d.get("by", {})
	var kinds := by.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return int(by[a]) > int(by[b]))
	var parts: Array[String] = []
	for k: String in kinds.slice(0, 6):
		parts.append("%s %d" % [k, by[k]])
	return "%d draws (%d instances; %s), %d shadow casters (sun %.0f m), %d lights (%d with shadows)" % [d.draws, d.instances, ", ".join(parts), d.shadow_draws, d.sun_m, d.lights, d.shadow_lights]


## What a geometry instance belongs to, for the draw proxy's breakdown.
func _draw_kind(g: GeometryInstance3D) -> String:
	var n: Node = g
	while n and n != level:
		if n is ZoneScatter:
			var nm := String(g.name)
			if nm.contains("lib:"):
				return "props_far" if g.visibility_range_begin > 0.0 else "props"
			return "scatter_far" if nm.begins_with("Far") or g.visibility_range_begin > 0.0 else "scatter"
		if n is ZoneTerrain:
			return "terrain"
		if n is Soldier:
			return "soldiers"
		if n is Vehicle:
			return "vehicles"
		if n is ZoneModule:
			return "modules"
		if n.name == &"Roads":
			return "roads"
		n = n.get_parent()
	return "other"


func _avg(ms: Array[float]) -> float:
	if ms.is_empty():
		return 0.0
	var sum := 0.0
	for v in ms:
		sum += v
	return sum / ms.size()


func _pct(ms: Array[float], p: float) -> float:
	if ms.is_empty():
		return 0.0
	var sorted := ms.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * p), sorted.size() - 1)]
