extends "res://tests/perfcases_test.gd"
## Contractor: Fallen's perf case (docs/survival.md "Performance"; phase A step 8), on perfcases'
## meter (this script extends it: each frame's 60 Hz frame cost, average, p95, hitches, the AI
## count). Run it headless:
##   <voxel godot exe> --headless --path . res://tests/fallen_test.tscn [-- --cases=night]
## or through tools/run_tests.sh fallen (PERF_CASES=... and PERF_NO_BUDGETS=1 as perfcases).
##
##   night   the start zone's farm at 22:00: LIVE_CAP of the dead as bodies about the player, most
##           of them chasing (the fight case's AI count and then some), a crowd of CROWD heads in
##           the far tier (ZoneDead) and a horde of HORDE walking at the farm. Measured NIGHT_S.
##
## Budgets: Proposed (FALLEN_BUDGETS, LOCAL_SLACK off CI), set 2026-10-26 beside the fight case's
## (avg 100 / p95 170 / hitches 140): the dead's brains are lighter than SquadAI's but there are
## more of them, and the crowd must cost about what the animals do.

## TODO (phase C, survival_world.md 13): a "settlement night" case (a horde siege on a built settlement with 12
## people) once the settlement lane's built settlement and its settlers can be set up here.
const FALLEN_CASES: Array[String] = ["night"]
const FALLEN_MEASURE_S := {"night": 30.0}
const FALLEN_BUDGETS := {
	"night": {"avg": 110.0, "p95": 180.0, "hitches_min": 140.0, "physics": 6.0},
}
const CROWD := 200
const HORDE := 50
const BODIES_M := Vector2(18.0, 55.0)
const HOST_S := 60.0

var _host_s := -1.0
var _counts := {}


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_fallen_settings%s.cfg" % tag))
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false
	Buildings.budget_always = true
	_rng.seed = 2026
	var cases: Array = FALLEN_CASES.duplicate()
	if OS.get_environment("PERF_CASES") != "":
		cases = Array(OS.get_environment("PERF_CASES").split(","))
	_no_budgets = OS.get_environment("PERF_NO_BUDGETS") == "1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cases="):
			cases = Array(a.trim_prefix("--cases=").split(","))
		elif a == "--no-budgets":
			_no_budgets = true
	get_tree().create_timer(240.0 + cases.size() * 200.0, true, false, true).timeout.connect(func() -> void:
		print("FALLEN TEST FAILED (timed out)")
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
		if not FALLEN_MEASURE_S.has(c):
			check(false, "no case named %s" % c)
			continue
		print("fallen: --- case %s ---" % c)
		await call("_fallen_" + c)
	_summary()
	Survival.server_stop()
	Campaign.reset_campaign()
	GameState.delete_save()
	print("FALLEN TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _measure_s(name: String) -> float:
	return float(FALLEN_MEASURE_S[name])


# --- cases -------------------------------------------------------------------------------------

func _fallen_night() -> void:
	if not await _host_world():
		return
	var at := level.ground_point(level.insertion_points()[0]) if not level.insertion_points().is_empty() else level.ground_point(Vector3.ZERO)
	await _settle_at(at, [])
	var dn := DayNight.current()
	if dn:
		dn.server_set(22.0, "clear")
	Survival._pop = -100000.0  # (the case lays out its own dead)
	var crowd := ZoneDead.of(level)
	crowd.dead.clear()
	# The bodies: LIVE_CAP about him, out of reach, all of them on him.
	var bodies := 0
	for i in Survival.LIVE_CAP:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(BODIES_M.x, BODIES_M.y)
		var kind := Survival.roll_kind(level, at, _rng)
		var z := Survival.server_spawn_zombie(level, level.ground_point(at + Vector3(cos(a), 0.0, sin(a)) * r), kind)
		if z:
			bodies += 1
			var brain := ZombieAI.of(z)
			if brain and i % 4 != 0:
				brain.target = player
				brain.mode = ZombieAI.Mode.CHASE
				brain.awareness = 1.0
	# The crowd and a horde.
	var heads := 0
	for i in CROWD:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(90.0, 400.0)
		if crowd.server_add(at + Vector3(cos(a), 0.0, sin(a)) * r, "walker"):
			heads += 1
	Survival._raise_pressure(level, at, Survival.HORDE_AT)
	var horde := crowd.server_horde(at, HORDE)
	_counts = {"bodies": bodies, "crowd": heads, "horde": horde}
	print("fallen: night: %d bodies about him (%d chasing), %d in the crowd, a horde of %d walking at the farm" % [bodies, bodies - bodies / 4, heads, horde])
	await _seconds(4.0)
	await _measure("night", [])
	print("fallen: after: %d bodies alive, %d in the crowd (%d of the horde), pressure %.0f" % [Survival.zombies(level).size(), crowd.count(), crowd.horde_count(), Survival.pressure(level)])


## Hosts a fresh survival world's start zone (the menu's way), builds its visuals as a player's
## machine would, and puts the player at its farm (perfcases' _host, for a world).
func _host_world() -> bool:
	var t_host := Time.get_ticks_usec()
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.reset_campaign()
	CompoundLevel.player_role_kits = false
	CompoundLevel.clean_loot = false
	if not Survival.server_new_world(main, "perf night " + tag, 7):
		check(false, "a survival world hosts")
		return false
	level = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await get_tree().process_frame
		var lvl := CompoundLevel.current(main) as SurvivalLevel
		if lvl and lvl.players and lvl.players.get_node_or_null(^"1") != null and ZoneDead.of(lvl) != null:
			level = lvl
			break
	check(level != null, "the start zone hosted (%.1f s)" % ((Time.get_ticks_usec() - t_host) / 1e6))
	if level == null:
		return false
	_hosted_zone = String(level.def.get("id", "survival"))
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	level.terrain.build_visuals()
	level.scatter.build_visuals()
	var roads := level.get_node_or_null(^"Roads") as ZoneRoads
	if roads:
		roads.build_visuals()
	_host_s = (Time.get_ticks_usec() - t_host) / 1e6
	return true


func _summary() -> void:
	print("fallen: === summary (60 Hz frame cost, ms; hitches: a tick or _process over %.0f ms and %.0fx the median) ===" % [HITCH_MS, HITCH_MEDIANS])
	for r: Dictionary in results:
		print("fallen: %-6s avg %6.2f  p95 %6.2f  p99 %6.2f  worst %7.1f | tick scripts %5.2f engine %5.2f | process %5.2f | nav %5.2f | hitches %d (%.1f/min) | AI %d (asleep %d)"
			% [r.name, r.avg, r.p95, r.p99, r.worst, r.scripts, r.engine, r.process, r.nav, r.hitches, r.hitches_min, r.ai, r.asleep])
	print("fallen: the load: %s; hosted in %.1f s" % [_counts, _host_s])
	if _no_budgets:
		return
	var k := 1.0 if OS.get_environment("GITHUB_ACTIONS") != "" else LOCAL_SLACK
	for r: Dictionary in results:
		var b: Dictionary = FALLEN_BUDGETS[r.name]
		check(r.avg <= b.avg * k, "%s: average frame %.2f ms (Proposed budget %.1f)" % [r.name, r.avg, b.avg * k])
		check(r.p95 <= b.p95 * k, "%s: 95th percentile frame %.2f ms (Proposed budget %.1f)" % [r.name, r.p95, b.p95 * k])
		check(r.hitches_min <= b.hitches_min * k, "%s: %.1f hitches a minute over %.0f ms (Proposed budget %.0f)" % [r.name, r.hitches_min, HITCH_MS, b.hitches_min * k])
		check(r.engine <= float(b.physics) * k, "%s: the physics step %.2f ms a tick (Proposed budget %.1f)" % [r.name, r.engine, float(b.physics) * k])
	if _host_s >= 0.0:
		check(_host_s <= HOST_S * k, "the start zone hosts, its visuals built, in %.1f s (Proposed budget %.0f)" % [_host_s, HOST_S * k])
