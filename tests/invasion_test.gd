extends "res://tests/perfcases_test.gd"
## The 8 km operation zone's performance (docs/combined_arms.md 6.2.3, phases D1/D2; cg_brief queue
## item 3.1): the "invasion" suite. Headless:
##   <voxel godot exe> --headless --path . res://tests/invasion_test.tscn [-- --cases=invasion,drive]
## or through tools/run_tests.sh invasion (PERF_CASES=... and PERF_NO_BUDGETS=1 as perfcases).
## The meter is perfcases' (this script extends it): each frame's 60 Hz frame cost, its average,
## 95th and 99th percentile and worst, the tick's scripts and engine step (physics), _process,
## FrameCost by system and the hitches a minute. The zone's visuals are built as on a player's
## machine and a camera rides with the player.
## Cases, in order (an operation zone from ZoneDef.generate_operation, then a hot zone):
##   invasion  the 6.2.3 case in the operation zone: two armour columns (COLUMN vehicles each, AI
##             driven) on the MSR and the truss route, LIVE_AI live soldiers (half friendly round the
##             player, half hostile 250-450 m ahead: they fight), VIRTUAL_AI hostiles as Virtualizer
##             profiles, one player;
##   drive     the player rides an AI-driven M-ATV along the MSR by road at DRIVE_KMH: the ground's
##             streaming catch-up (collision chunks missing within CATCH_NEAR_M of the vehicle at any
##             tick, and how long the 1 km round it took to fill each time it fell behind);
##   heli      the player rides a UH-60 contour-flying across the zone at its cruise: the same,
##             and the terrain's rings (fine chunks missing round the camera);
##   hot       the same load as invasion in a 4 km hot zone on the operation's terrain preset
##             (everything built and drawn up front): the case 6.2.3 says the invasion case must
##             hold against, on the same kind of ground.
## Memory: static memory before hosting, with the operation zone and its visuals in, the most during
## the drive and the flight, and after the switch to the hot zone (the operation zone let go).
## Budgets: Proposed (INV_BUDGETS, with perfcases' LOCAL_SLACK off CI); the doc's 14 / 33 ms host
## target (an RTX 4060 PC, rendering too) is printed beside them. CI runs the same cases on the same
## 8 km zone for CI_MEASURE_SHARE of the time. Never touches a real save.

const OP_SEED := 11
const OP_TYPE := "phased_invasion"
const OP_COVERS: Array[String] = ["ashfield", "red_mesa", "salt_pan"]
const HOT_ZONE := "hot_compare"
const INV_CASES: Array[String] = ["invasion", "drive", "heli", "hot"]
const INV_MEASURE_S := {"invasion": 35.0, "drive": 45.0, "heli": 40.0, "hot": 35.0}
const COLUMN := 4
const LIVE_AI := 60
const VIRTUAL_AI := 200
const TEAM := 4
const FAR_M := 1500.0
const DRIVE_KMH := 70.0
## The ground round a moving player: none of it may be missing within CATCH_NEAR_M at any tick, and
## the 1 km round him (the collision reach) must fill again within CATCH_S whenever it falls behind.
const CATCH_NEAR_M := 300.0
const CATCH_FAR_M := 1000.0
## The doc's host target (6.2.3), printed for reference: headless can't time the GPU.
const DOC_AVG_MS := 14.0
const DOC_P99_MS := 33.0
## Proposed budgets (ms of 60 Hz frame cost; hitches a minute; catch-up seconds; memory MB), set
## 2026-10-25 (cg_brief 3.1) like perfcases': room for CI's runners (about 2-2.5x a quiet local run;
## local runs get LOCAL_SLACK on top). The AI-heavy cases' absolute times are the AI's (perfcases'
## fight is 100 / 170 on CI with fewer men); what D2 answers for is VS_HOT, the invasion case's
## average against the hot zone's under the same load on the same ground (6.2.3: "it must hold the
## budget against today's hot-zone case"), the streaming's worst frame, the catch-up and the memory.
const INV_BUDGETS := {
	"invasion": {"avg": 250.0, "p95": 320.0, "hitches_min": 90.0},
	"drive": {"avg": 20.0, "p95": 30.0, "hitches_min": 15.0, "catch_s": 4.0},
	"heli": {"avg": 20.0, "p95": 32.0, "hitches_min": 15.0, "catch_s": 4.0},
	"hot": {"avg": 250.0, "p95": 320.0, "hitches_min": 90.0},
}
const VS_HOT := 1.5
const STREAM_TICK_MS := 8.0
const MEMORY_MB := {"zone": 1400.0, "growth": 250.0}

var _mem := {}
var _catch := {}  # case -> {"near_max", "far_worst_s", "behind_since", "fine_missing_max", "samples"}
var _stream: BigZoneStreaming
var _far := {}  # the invasion case's far drawing
var _rings := {}  # the flight's terrain rings and scatter cells


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_invasion" + tag
	Campaign.campaign_id = "test_invasion_campaign" + tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_invasion_settings%s.cfg" % tag))
	CompoundLevel.spawn_ai = false  # the load is the case's own (6.2.3), the same in both zones
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false
	Buildings.budget_always = true
	_rng.seed = 2026
	var cases: Array = INV_CASES.duplicate()
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
	get_tree().create_timer(240.0 + cases.size() * 200.0, true, false, true).timeout.connect(func() -> void:
		print("INVASION TEST FAILED (timed out)")
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
	_mem.start = _mem_mb()
	for c: String in cases:
		if not INV_MEASURE_S.has(c):
			check(false, "no case named %s" % c)
			continue
		print("invasion: --- case %s ---" % c)
		await call("_inv_" + c)
	_summary()
	Campaign.reset_campaign()
	GameState.delete_save()
	print("INVASION TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _measure_s(name: String) -> float:
	return float(INV_MEASURE_S[name])


static func _mem_mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0


# --- cases -------------------------------------------------------------------------------------

func _inv_invasion() -> void:
	if not await _host_op():
		return
	var at := level.insertion_points()[0]
	await _settle_at(level.ground_point(at), [])
	await _load(level.def)
	await _seconds(6.0)
	if _stream:
		_stream.worst_ms = 0.0
	await _measure("invasion", [])
	_report_stream("invasion")
	# Far drawing (6.2.2): soldiers to soldier_draw_m, vehicles their meshes to vehicle_proxy_m and a
	# box beyond to vehicle_draw_m.
	var spec := BigZoneStreaming.spec()
	var soldier_ok := 0
	var soldiers := 0
	for n in level.ai.get_children():
		if n is Soldier and n.has_meta(&"far_drawn"):
			soldiers += 1
			var ends := (n as Node).find_children("*", "GeometryInstance3D", true, false).map(func(g: Node) -> float: return (g as GeometryInstance3D).visibility_range_end)
			if ends.all(func(e: float) -> bool: return e > 0.0 and e <= float(spec.soldier_draw_m)):
				soldier_ok += 1
	var proxies := get_tree().get_nodes_in_group(Vehicle.GROUP).filter(func(v: Node) -> bool: return level.is_ancestor_of(v) and v.has_node(^"FarProxy")).size()
	_far = {"soldiers": soldiers, "soldier_ok": soldier_ok, "proxies": proxies, "vehicles": _stream.live_vehicles if _stream else 0}
	print("invasion: far drawing: %d of %d soldiers drawn to %.0f m at most, %d of %d vehicles with a far box" % [soldier_ok, soldiers, float(spec.soldier_draw_m), proxies, _far.vehicles])


func _inv_drive() -> void:
	if not await _host_op():
		return
	_clear_load()
	var msr: Array = level.def.op.msr
	var from := Vector2(float(msr[0][0]), float(msr[0][1]))
	var to := Vector2(float(msr.back()[0]), float(msr.back()[1]))
	var way := RoadRoute.route(level.def, from, to)
	if way.size() < 2:
		way = PackedVector2Array([from, to])
	var path := PackedVector3Array()
	for p in way:
		if p.distance_to(from) > 180.0:  # (from outside the FOB the MSR starts in)
			path.append(level.ground_point(Vector3(p.x, 0, p.y)))
	print("invasion: the drive: %d waypoints by road along the MSR, %.0f m start to end" % [path.size(), from.distance_to(to)])
	var a: Vector3 = path[0]
	var b: Vector3 = path[1]
	var v := VehicleLayer.of(level).server_spawn("matv", Transform3D(Basis.looking_at((b - a).normalized()), a + Vector3.UP * 0.6), "", &"player", "inv_matv")
	check(v != null, "an M-ATV at the start of the MSR")
	if v == null:
		return
	await _settle_at(a, [], false)
	player.set_physics_process(true)
	check(v.server_enter(player, 1), "the player rides in the M-ATV")
	await _frames_wait(30)
	v.server_follow_path(path, DRIVE_KMH)
	if _stream:
		_stream.worst_ms = 0.0
	_mem.drive_start = _mem_mb()
	await _measure("drive", [])
	_mem.drive_peak = maxf(float(_mem.get("drive_peak", 0.0)), _mem_mb())
	print("invasion: drive: the M-ATV went %.0f m" % Vector2(v.global_position.x - a.x, v.global_position.z - a.z).length())
	_report_stream("drive")
	if is_instance_valid(v):
		v.server_stop()
		player.set_physics_process(false)
		v.server_exit(player)


func _inv_heli() -> void:
	if not await _host_op():
		return
	_clear_load()
	var axis := Vector2(float(level.def.op.axis[0]), float(level.def.op.axis[1]))
	var half := level.terrain.size_m * 0.5 - 300.0
	var side := Vector2(-axis.y, axis.x)
	var a2 := -axis * half + side * 600.0
	var b2 := axis * half - side * 600.0
	var a := level.ground_point(Vector3(a2.x, 0, a2.y))
	var b := level.ground_point(Vector3(b2.x, 0, b2.y))
	VehicleHull.prewarm("uh60")
	var t0 := Time.get_ticks_msec()
	while not VehicleHull.is_ready("uh60") and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	player.global_position = a + Vector3.UP
	await _frames_wait(5)
	if _stream:
		_stream.ensure(a)
	var heli := VehicleLayer.of(level).server_spawn("uh60", Transform3D(Basis.looking_at((b - a).normalized()), a + Vector3.UP * 0.3), "", &"player", "inv_heli") as Helicopter
	check(heli != null, "a UH-60 at the operation zone's friendly edge")
	if heli == null:
		return
	await _settle_at(a, [], false)
	player.set_physics_process(true)
	check(heli.server_enter(player), "the player rides in the UH-60")
	heli.global_position.y += Helicopter.CRUISE_AGL_M
	heli.server_start_airborne()
	heli.server_fly_to(b, Helicopter.CRUISE_AGL_M, Helicopter.CRUISE_KMH, false)
	if _stream:
		_stream.worst_ms = 0.0
	await _measure("heli", [])
	_mem.heli_peak = _mem_mb()
	_rings = level.terrain.ring_counts().merged({"built": level.terrain.ring_built, "freed": level.terrain.ring_freed, "cells_freed": level.scatter.freed_cells,
		"cells_built": level.scatter.built_cells(), "near_cells": level.scatter.built_near_cells()})
	print("invasion: heli: flew %.0f m, the terrain's rings %s (built %d, freed %d), the scatter's freed cells %d" % [Vector2(heli.global_position.x - a.x, heli.global_position.z - a.z).length(),
		level.terrain.ring_counts(), level.terrain.ring_built, level.terrain.ring_freed, level.scatter.freed_cells])
	_report_stream("heli")


func _inv_hot() -> void:
	# Today's hot-zone case on the operation's own ground: a 4 km hot zone (ZoneDef.generate_hot,
	# built and drawn up front) on the operation's terrain preset, so the same load meets the same
	# woods and river, and what differs is the 8 km zone's streaming.
	var def := ZoneDef.generate_hot(OP_SEED)
	def["terrain"] = ZoneDef.generate_operation(OP_SEED, OP_TYPE, OP_COVERS).terrain
	def["sea_side"] = -1
	def["sea_m"] = 0.0
	def["id"] = HOT_ZONE
	if not await _host_def(def, HOT_ZONE):
		return
	_mem.after_switch = _mem_mb()
	var at := level.insertion_points()[0]
	await _settle_at(level.ground_point(at), [])
	await _load(level.def)
	await _seconds(6.0)
	await _measure("hot", [])


# --- setup -------------------------------------------------------------------------------------

func _host_op() -> bool:
	if level and is_instance_valid(level) and OperationGen.is_operation(level.def):
		return true
	var t := Time.get_ticks_msec()
	var def := ZoneDef.generate_operation(OP_SEED, OP_TYPE, OP_COVERS)
	print("invasion: operation zone %s generated in %d ms (%d modules, %s terrain)" % [def.id, Time.get_ticks_msec() - t, (def.modules as Array).size(), def.terrain])
	if not await _host_def(def, String(def.id)):
		return false
	_stream = level.get_node_or_null(NodePath(BigZoneStreaming.NODE_NAME)) as BigZoneStreaming
	check(_stream != null and level.terrain.on_demand and level.scatter.on_demand, "the operation zone streams its ground (BigZoneStreaming)")
	_mem.zone = _mem_mb()
	print("invasion: static memory %.0f MB before, %.0f MB with the operation zone and its visuals in" % [_mem.start, _mem.zone])
	return true


## Hosts `def` (the first by the menu's way, the rest by a level switch), builds its visuals as a
## player's machine would, and puts a camera on the player (perfcases' _host, for a def).
func _host_def(def: Dictionary, zone_id: String) -> bool:
	var t_host := Time.get_ticks_usec()
	if _hosted_zone == "":
		main.host_zone(def)
	else:
		var fresh := LevelSwitch.load_level(main, {"level": "zone", "def": ZoneDef.normalize(def)})
		fresh._on_hosted()
	level = null
	_stream = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await get_tree().process_frame
		var lvl := CompoundLevel.current(main) as ZoneLevel
		if lvl and String(lvl.def.get("id", "")) == zone_id and lvl.players and lvl.players.get_node_or_null(^"1") != null:
			level = lvl
			break
	check(level != null, "%s hosted (%.1f s; generated in %.0f ms, the scatter %.0f)" % [zone_id, (Time.get_ticks_usec() - t_host) / 1e6,
		level.generate_ms if level else 0.0, level.scatter_ms if level else 0.0])
	if level == null:
		return false
	_hosted_zone = zone_id
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	var t_vis := Time.get_ticks_usec()
	level.terrain.build_visuals()
	level.scatter.build_visuals()
	var roads := level.get_node_or_null(^"Roads") as ZoneRoads
	if roads:
		roads.build_visuals()
	print("invasion: %s's visuals built in %.0f ms" % [zone_id, (Time.get_ticks_usec() - t_vis) / 1000.0])
	camera = Camera3D.new()
	camera.name = "PerfCamera"
	camera.far = 4000.0
	camera.position = Vector3(0, 1.6, 0)
	player.add_child(camera)
	camera.current = true
	return true


## The 6.2.3 load in the hosted zone: the columns, LIVE_AI live soldiers, VIRTUAL_AI virtual.
func _load(def: Dictionary) -> void:
	await _columns(def)
	_live()
	_virtual()
	print("invasion: the load: %d live AI, %d tracked groups, %d vehicles" % [level.ai.get_child_count(), Virtualizer.of(level).groups.size(),
		get_tree().get_nodes_in_group(Vehicle.GROUP).filter(func(v: Node) -> bool: return level.is_ancestor_of(v)).size()])


## Two columns of COLUMN vehicles, each with an AI driver, driving by road: along the MSR and the
## truss route in an operation zone, between the sites furthest apart in a hot zone.
func _columns(def: Dictionary) -> void:
	var routes: Array = []
	if OperationGen.is_operation(def):
		for line: Array in [def.op.msr, def.op.route]:
			routes.append([Vector2(float(line[0][0]), float(line[0][1])), Vector2(float(line.back()[0]), float(line.back()[1]))])
	else:
		var path := _long_route()
		if path.size() >= 2:
			routes.append([Vector2(path[0].x, path[0].z), Vector2(path[-1].x, path[-1].z)])
			routes.append([Vector2(path[-1].x, path[-1].z), Vector2(path[0].x, path[0].z)])
	var layer := VehicleLayer.of(level)
	var models := [["abrams", "abrams", "bradley", "bradley"], ["bradley", "bradley", "bradley", "bradley"]]
	for c in routes.size():
		var way := RoadRoute.route(def, routes[c][0], routes[c][1])
		if way.size() < 2:
			way = PackedVector2Array([routes[c][0], routes[c][1]])
		var pts := PackedVector3Array()
		for p in way:
			pts.append(level.ground_point(Vector3(p.x, 0, p.y)))
		var dir := (pts[1] - pts[0]).normalized()
		for k in COLUMN:
			var at := level.ground_point(pts[0] - dir * (14.0 + k * 30.0)) + Vector3(0, 1.0, 0)
			if _stream:
				_stream.ensure(at)
			var v := layer.server_spawn(String(models[c][k]), Transform3D(Basis.looking_at(dir, Vector3.UP), at), "", &"friendly")
			if v == null:
				continue
			await get_tree().physics_frame
			var driver := level.spawn_soldier({"name": "PerfInvDriver%d_%d" % [c, k], "faction": "friendly", "variant": "multicam",
				"pos": at + Vector3(3, 0, 0), "loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "guard": false})
			await get_tree().physics_frame
			if driver:
				v.server_enter(driver, 0)
			v.set_meta(&"inv_load", true)
			v.server_follow_path(pts.slice(1), 30.0)


## LIVE_AI soldiers: half friendly round the player, half hostile in teams 250-450 m ahead.
func _live() -> void:
	var at := player.global_position
	for i in LIVE_AI / 2:
		level.spawn_soldier({"name": "PerfInvFriend%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(at + Vector3(-20.0 + (i % 10) * 4.0, 0, 6.0 + (i / 10) * 4.0)), "loadout": CompoundLevel.HOSTILE_LOADOUT,
			"combat": 0.5, "discipline": 0.6, "guard": true})
	var er := EnemyResponse.of(level)
	var map := level.map_area()
	var ahead := Vector3(map.get_center().x - at.x, 0, map.get_center().y - at.z).normalized()  # toward the middle
	for t in (LIVE_AI / 2) / TEAM:
		var pos := at + ahead.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * _rng.randf_range(250.0, 450.0)
		_team(er, level.ground_point(pos), false)


## VIRTUAL_AI hostiles in teams at least FAR_M from the player, tracked (they go virtual).
func _virtual() -> void:
	var er := EnemyResponse.of(level)
	var area := level.map_area().grow(-200.0)
	var at := player.global_position
	for t in VIRTUAL_AI / TEAM:
		var pos := Vector3.ZERO
		for k in 200:
			pos = Vector3(_rng.randf_range(area.position.x, area.end.x), 0, _rng.randf_range(area.position.y, area.end.y))
			if Vector2(pos.x - at.x, pos.z - at.z).length() >= FAR_M:
				break
		_team(er, level.ground_point(pos), true)


var _made := 0


func _team(er: EnemyResponse, pos: Vector3, virtualize: bool) -> void:
	_made += 1
	var callsign := "PerfIV%d" % _made
	var squad := er._new_squad(callsign)
	var a := _rng.randf() * TAU
	var route: Array[Vector3] = [pos, level.ground_point(pos + Vector3(cos(a), 0, sin(a)) * 150.0)]
	squad.patrol = route
	var soldiers := er._spawn_team(squad, callsign, TEAM, pos, route[1], CompoundLevel.HOSTILE_LOADOUT, 0.45, 0.5, "safe")
	if virtualize:
		Virtualizer.of(level).track({"squad": squad, "soldiers": soldiers}, "patrol", true)


## Takes the invasion load out (the drive and the flight measure the streaming on their own).
func _clear_load() -> void:
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v.has_meta(&"inv_load"):
			v.queue_free()
	for n in level.ai.get_children():
		n.queue_free()
	var virt := Virtualizer.of(level)
	if virt:
		virt.groups.clear()
	await get_tree().physics_frame


# --- the streaming's catch-up ------------------------------------------------------------------

func _on_measure_tick(name: String) -> void:
	if _stream == null or not is_instance_valid(_stream) or not name in ["drive", "heli", "invasion"]:
		return
	if Engine.get_physics_frames() % 6 != 0:
		return  # (ten samples a second)
	var c: Dictionary = _catch.get_or_add(name, {"near_max": 0, "far_worst_s": 0.0, "behind_since": -1.0, "fine_missing_max": 0, "samples": 0, "behind": 0})
	var at := player.global_position
	var near := _stream.missing_near(at, CATCH_NEAR_M)
	var far := _stream.missing_near(at, CATCH_FAR_M)
	var now := Time.get_ticks_msec() / 1000.0
	c.samples = int(c.samples) + 1
	c.near_max = maxi(int(c.near_max), near)
	if far > 0:
		c.behind = int(c.behind) + 1
		if float(c.behind_since) < 0.0:
			c.behind_since = now
		c.far_worst_s = maxf(float(c.far_worst_s), now - float(c.behind_since))
	else:
		c.behind_since = -1.0
	var fine := 0
	var t := level.terrain
	var chunk_m := ZoneTerrain.CHUNK_CELLS * ZoneTerrain.CELL_M
	var half := t.size_m * 0.5
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var cc := Vector2i(floori((at.x + half) / chunk_m) + dx, floori((at.z + half) / chunk_m) + dz)
			if cc.x >= 0 and cc.y >= 0 and cc.x < t.chunk_count() and cc.y < t.chunk_count() and not (t._lod1.has(cc) or t._lod0.has(cc)):
				fine += 1
	c.fine_missing_max = maxi(int(c.fine_missing_max), fine)


func _report_stream(name: String) -> void:
	if _stream == null or not is_instance_valid(_stream):
		return
	var c: Dictionary = _catch.get(name, {})
	print("invasion: %s: ground streaming worst tick %.1f ms (terrain %.1f, scatter %.1f); %d collision chunks of %d, %d cover cells; live soldiers %d, vehicles %d; virtual %d" % [name,
		_stream.worst_ms, _stream.worst_split[0], _stream.worst_split[1], level.terrain.collision_chunks(), level.terrain.chunk_count() * level.terrain.chunk_count(), level.scatter.cover_cells(),
		_stream.live_soldiers, _stream.live_vehicles, Virtualizer.of(level).virtual_count()])
	if not c.is_empty():
		print("invasion: %s: catch-up: at most %d chunks missing within %.0f m; the %.0f m round the player behind on %d of %d samples, %.1f s at worst; near ground meshes missing at most %d of 25" % [name,
			c.near_max, CATCH_NEAR_M, CATCH_FAR_M, c.behind, c.samples, c.far_worst_s, c.fine_missing_max])
	for r: Dictionary in results:
		if r.name == name:
			r["stream_ms"] = _stream.worst_ms
			r["catch"] = c


# --- the summary -------------------------------------------------------------------------------

func _summary() -> void:
	print("invasion: === summary (60 Hz frame cost: a frame's average tick + its _process, ms; engine = the physics step) ===")
	var by := {}
	for r: Dictionary in results:
		by[r.name] = r
		print("invasion: %-8s avg %6.2f  p95 %6.2f  p99 %6.2f  worst %7.1f | tick scripts %5.2f engine %5.2f | process %5.2f | nav %5.2f | hitches %d (%.1f/min) | AI %d (asleep %d) | stream worst %.1f ms"
			% [r.name, r.avg, r.p95, r.p99, r.worst, r.scripts, r.engine, r.process, r.nav, r.hitches, r.hitches_min, r.ai, r.asleep, float(r.get("stream_ms", 0.0))])
	print("invasion: memory (static, MB): %s" % [_mem])
	if by.has("invasion"):
		print("invasion: the doc's host target (6.2.3, with rendering, not measurable headless): average %.0f ms, 99th %.0f ms; headless invasion: %.2f / %.2f" % [DOC_AVG_MS, DOC_P99_MS, by.invasion.avg, by.invasion.p99])
	if _no_budgets:
		return
	var k := 1.0 if OS.get_environment("GITHUB_ACTIONS") != "" else LOCAL_SLACK
	for r: Dictionary in results:
		var b: Dictionary = INV_BUDGETS[r.name]
		check(r.avg <= b.avg * k, "%s: average frame %.2f ms (Proposed budget %.1f)" % [r.name, r.avg, b.avg * k])
		check(r.p95 <= b.p95 * k, "%s: 95th percentile frame %.2f ms (Proposed budget %.1f)" % [r.name, r.p95, b.p95 * k])
		check(r.hitches_min <= b.hitches_min * k, "%s: %.1f hitches a minute over %.0f ms (Proposed budget %.0f)" % [r.name, r.hitches_min, HITCH_MS, b.hitches_min * k])
		if r.has("stream_ms"):
			check(float(r.stream_ms) <= STREAM_TICK_MS * k, "%s: the ground streaming's worst tick %.1f ms (Proposed budget %.1f)" % [r.name, r.stream_ms, STREAM_TICK_MS * k])
		var c: Dictionary = r.get("catch", {})
		if b.has("catch_s") and not c.is_empty():
			check(int(c.near_max) == 0, "%s: no ground collision ever missing within %.0f m of the player (at most %d chunks)" % [r.name, CATCH_NEAR_M, c.near_max])
			check(float(c.far_worst_s) <= float(b.catch_s) * k, "%s: the %.0f m round the player filled within %.1f s each time it fell behind (Proposed budget %.1f s)" % [r.name, CATCH_FAR_M, c.far_worst_s, float(b.catch_s) * k])
			check(int(c.fine_missing_max) == 0, "%s: the ground round the camera always drawn at its near levels (at most %d of 25 chunks without)" % [r.name, c.fine_missing_max])
	if by.has("invasion") and by.has("hot"):
		check(float(by.invasion.avg) <= float(by.hot.avg) * VS_HOT * k, "the invasion case holds against the hot zone's under the same load: %.2f ms against %.2f (Proposed: at most %.2fx)" % [by.invasion.avg, by.hot.avg, VS_HOT * k])
	if not _far.is_empty():
		check(int(_far.soldiers) > 0 and int(_far.soldier_ok) == int(_far.soldiers) and int(_far.proxies) >= int(_far.vehicles) - 1,
			"far drawing: every soldier to the zone's draw distance (%d of %d), the vehicles with far boxes (%d of %d)" % [_far.soldier_ok, _far.soldiers, _far.proxies, _far.vehicles])
	if not _rings.is_empty():
		var cap := func(r: float) -> int: return ceili(PI * pow(r + 182.0, 2) / pow(ZoneTerrain.CHUNK_CELLS * ZoneTerrain.CELL_M, 2))
		check(int(_rings.freed) > 0 and int(_rings.cells_freed) > 0 and int(_rings.lod0) <= cap.call(ZoneTerrain.RING_FREE_M[0]) and int(_rings.lod1) <= cap.call(ZoneTerrain.RING_FREE_M[1])
			and int(_rings.lod2) <= cap.call(ZoneTerrain.RING_FREE_M[2]),
			"across the zone the ground's meshes and the scatter's cells free behind the camera: %s" % [_rings])
	if _mem.has("zone"):
		check(float(_mem.zone) - float(_mem.start) <= float(MEMORY_MB.zone) * k, "the operation zone and its visuals take %.0f MB of static memory (Proposed budget %.0f)" % [float(_mem.zone) - float(_mem.start), float(MEMORY_MB.zone) * k])
	var peak := maxf(float(_mem.get("drive_peak", 0.0)), float(_mem.get("heli_peak", 0.0)))
	if peak > 0.0 and _mem.has("zone"):
		check(peak - float(_mem.zone) <= float(MEMORY_MB.growth) * k, "driving and flying across the zone grows memory %.0f MB at most (Proposed budget %.0f: the rings and cells free behind)" % [peak - float(_mem.zone), float(MEMORY_MB.growth) * k])
