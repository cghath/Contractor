extends Node
## Render bench (Captain, 2026-10-22: v0.5.4's frame rate "unbelievably bad", menus included).
## WINDOWED, not a suite (headless has no GPU): runs the game with today's default video settings
## (a settings file of its own), vsync off and no fps cap, and measures per case:
## the GPU's and the render thread's time per frame (RenderingServer.viewport_get_measured_render_time_*),
## fps, draw calls, objects and primitives in the frame, video memory, and every SubViewport still
## rendering (what it is, its size, its update mode).
##   <voxel godot exe> --path . res://tests/render_bench.tscn [-- --cases=menu,town,woods,fight,woods_in,open,forest]
## Prints "bench:" lines. Cases: menu (the main menu up), town (Old Quarter, looking into its biggest
## town from its edge), woods (Kestrel Valley's densest wood), fight (Black Ridge, the biggest
## garrison 140 m off, the zone engaged); and, for the woods perf pass, woods_in (inside that wood),
## open (Kestrel Valley's open ground, the woods' baseline) and forest (the Experimental forest test
## zone's densest wood). Never touches a real save.
## Safe to run while someone uses the PC (2026-10-31: an agent's run kept cghath's mouse inside its
## window): it does nothing unless BENCH_WINDOWED=1 is set (for a person to run on purpose, never an
## agent's suite); its window sits at the screen's corner, borderless, never takes focus, and the
## mouse is let go every frame after every other script (the game captures it in fifty-odd places:
## player input, menus, the HUD); it quits by itself after TIMEOUT_S.
## The window is the game's own size (the project's, 1600x900) unless BENCH_SIZE=WxH says
## otherwise (e.g. BENCH_SIZE=1920x1080, or 640x360 for a small one out of the way). The GPU's
## work in foliage (overdraw, fill) goes with the pixels, so every measure line says the size it
## was taken at; compare GPU times only at the same size.

const SETTLE_S := 5.0
const MEASURE_S := 10.0
## The whole bench quits after this long, whatever is left (s).
const TIMEOUT_S := 300.0

var _size := Vector2i.ZERO

var main: Node
var level: ZoneLevel
var _hosted := ""
var _vp := RID()


func _ready() -> void:
	if OS.get_environment("BENCH_WINDOWED") != "1":
		print("bench: not run: set BENCH_WINDOWED=1 to run the windowed bench on purpose (it opens a window)")
		get_tree().quit(0)
		return
	_let_go()
	var win := get_window()
	win.set_flag(Window.FLAG_NO_FOCUS, true)
	win.set_flag(Window.FLAG_BORDERLESS, true)
	win.mode = Window.MODE_WINDOWED
	_size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	var asked := OS.get_environment("BENCH_SIZE").to_lower().split("x")
	if asked.size() == 2 and asked[0].is_valid_int() and asked[1].is_valid_int() and int(asked[0]) > 0 and int(asked[1]) > 0:
		_size = Vector2i(int(asked[0]), int(asked[1]))
	win.size = _size
	win.position = Vector2i.ZERO
	print("bench: window %dx%d (BENCH_SIZE=WxH to change it)" % [_size.x, _size.y])
	process_priority = 1000000  # after every other script's _process: the mouse let go last
	process_physics_priority = 1000000
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_render_bench" + tag
	Campaign.campaign_id = "test_render_bench_campaign" + tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_render_bench_settings%s.cfg" % tag))
	Contracts.auto_show_debrief = false
	if OS.get_environment("BENCH_DETAIL") != "":  # e.g. ultra, or a level by name
		GameSettings.set_value("video", "detail", OS.get_environment("BENCH_DETAIL"))
	if OS.get_environment("BENCH_VOXEL_MODULES") != "":
		GameSettings.detail_override["voxel_modules"] = int(OS.get_environment("BENCH_VOXEL_MODULES"))
	print("bench: detail %s" % GameSettings.detail())
	GameState.delete_save()
	Campaign.reset_campaign()
	var cases := ["menu", "town", "woods", "fight"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cases="):
			cases = Array(a.trim_prefix("--cases=").split(","))
	get_tree().create_timer(minf(TIMEOUT_S, 60.0 + cases.size() * 120.0), true, false, true).timeout.connect(func() -> void:
		print("bench: TIMED OUT")
		get_tree().quit(99))
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for c: String in cases:
		_uncap()
		print("bench: --- %s ---" % c)
		await call("_case_" + c)
	print("bench: done")
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


## The mouse free and the window unfocusable, every frame (after the game's own scripts).
func _process(_delta: float) -> void:
	_let_go()


func _physics_process(_delta: float) -> void:
	_let_go()


func _input(_event: InputEvent) -> void:
	_let_go()


func _let_go() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _uncap() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _case_menu() -> void:
	await _seconds(SETTLE_S)
	await _measure("menu")


func _case_town() -> void:
	if not await _host("city_hot"):
		return
	var town: ZoneModule = null
	for m in level.modules():
		if ZoneModules.base(m.type) in ["town", "city"] and (town == null or ZoneModules.boxes(m.type).size() > ZoneModules.boxes(town.type).size()):
			town = m
	if town == null:
		print("bench: town: no town")
		return
	var r := town.footprint()
	await _stand(level.ground_point(Vector3(r.get_center().x, 0, r.end.y + 40.0)), Vector3(r.get_center().x, 0, r.get_center().y), [town])
	await _measure("town")


func _case_woods() -> void:
	if not await _host("kestrel_valley"):
		return
	var spot := _densest_wood()
	await _stand(level.ground_point(spot - Vector3(40, 0, 0)), spot, [])
	await _measure("woods")


## Inside Kestrel Valley's densest wood, at its middle, looking along it (the woods perf pass:
## the trees all round, near tier everywhere).
func _case_woods_in() -> void:
	if not await _host("kestrel_valley"):
		return
	var spot := _densest_wood()
	await _stand(level.ground_point(spot), spot + Vector3(60, 0, 0), [])
	await _measure("woods_in")


## Kestrel Valley's open ground: the 64 m cell farthest from any tree or thicket (away from the
## zone's edge and its sites), looking across the zone's middle. The woods' baseline.
func _case_open() -> void:
	if not await _host("kestrel_valley"):
		return
	var area := level.map_area().grow(-250.0)
	var trees := {}
	for item: Dictionary in level.scatter.items:
		if int(item.kind) in [ZoneScatter.Kind.TREE, ZoneScatter.Kind.THICKET]:
			var p: Vector3 = item.pos
			trees[Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))] = true
	var best := Vector3.INF
	var best_d := -1
	for cx in range(floori(area.position.x / 64.0), floori(area.end.x / 64.0)):
		for cz in range(floori(area.position.y / 64.0), floori(area.end.y / 64.0)):
			var centre := Vector3((cx + 0.5) * 64.0, 0, (cz + 0.5) * 64.0)
			if not level.modules().all(func(m: ZoneModule) -> bool: return m.distance_to(centre) > 150.0):
				continue
			var d := 99
			for k: Vector2i in trees:
				d = mini(d, maxi(absi(k.x - cx), absi(k.y - cz)))
				if d <= best_d:
					break
			if d > best_d:
				best_d = d
				best = centre
	print("bench: open ground %s: %d cells (64 m) from the nearest tree" % [best, best_d])
	var mid := level.map_area().get_center()
	await _stand(level.ground_point(best), Vector3(mid.x, 0, mid.y), [])
	await _measure("open")


## The Experimental forest test zone (forest_experimental: the densest woods), in its densest wood.
func _case_forest() -> void:
	if not await _host("forest_experimental"):
		return
	var spot := _densest_wood()
	await _stand(level.ground_point(spot), spot + Vector3(60, 0, 0), [])
	await _measure("forest")


## The middle of the 64 m cell with the most trees (away from the sites and the zone's edge).
func _densest_wood() -> Vector3:
	var cells := {}
	var best := Vector2i.ZERO
	var best_n := 0
	for item: Dictionary in level.scatter.items:
		if int(item.kind) != ZoneScatter.Kind.TREE:
			continue
		var p: Vector3 = item.pos
		var c := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
		cells[c] = int(cells.get(c, 0)) + 1
		if cells[c] > best_n:
			best = c
			best_n = cells[c]
	print("bench: densest wood %s: %d trees in 64 m" % [best, best_n])
	return Vector3((best.x + 0.5) * 64.0, 0, (best.y + 0.5) * 64.0)


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
	await _stand(level.ground_point(centre + dir * (r.size.length() * 0.5 + 140.0)), centre, [site])
	var alert := Alert.of(level)
	if alert:
		alert._raise(alert.area_of(centre), Alert.State.ENGAGED, true)
	await _seconds(4.0)
	await _measure("fight")


## Hosts `zone_id` (the first by the menu's way, the rest by a level switch). True once the player is in.
func _host(zone_id: String) -> bool:
	var def := MissionRegistry.zone_def(zone_id)
	if def.is_empty():
		def = ZoneDef.get_def(zone_id)  # a test zone off the board (forest_experimental)
	if _hosted == "":
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
	_hosted = zone_id
	if level == null:
		print("bench: %s didn't host" % zone_id)
	_uncap()
	return level != null


## Puts the player at `at` looking at `look`, waits for `modules` to stream in, then SETTLE_S.
func _stand(at: Vector3, look: Vector3, modules: Array) -> void:
	var player := level.players.get_node(^"1") as Soldier
	if OS.get_environment("BENCH_NO_VOXEL_VISUALS") == "1":
		for v: Node in player.find_children("*", "VoxelViewer", true, false):
			(v as VoxelViewer).requires_visuals = false
		print("bench: the player's voxel viewer needs no visuals (experiment)")
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = at
	var flat := Vector3(look.x - at.x, 0, look.z - at.z)
	if flat.length() > 0.1:
		player.rotation.y = atan2(-flat.x, -flat.z)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not modules.all(func(m: ZoneModule) -> bool: return m.is_ready()):
		await get_tree().process_frame
	await _seconds(SETTLE_S)
	_census("settled")


## Resources and video memory now, and how many modules are streamed in.
func _census(when: String) -> void:
	var streamed := 0
	var cam := get_viewport().get_camera_3d()
	var near_d: Array[String] = []
	if level:
		for m in level.modules():
			if m.is_streamed():
				streamed += 1
				if cam:
					near_d.append("%s %.0f" % [m.module_id, m.distance_to(cam.global_position)])
	print("bench: census %s: streamed in: %s" % [when, near_d])
	print("bench: census %s: resources %d, objects %d, video mem %.0f MB, buffer mem %.0f MB, texture mem %.0f MB; modules streamed %d of %d"
		% [when, Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		streamed, level.modules().size() if level else 0])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _measure(name: String) -> void:
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var frame: Array[float] = []
	var draws: Array[float] = []
	var objects := 0.0
	var prims := 0.0
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < MEASURE_S * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame.append((now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp))
		draws.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		if frame.size() % 300 == 0:
			_census("measuring")
	var n := maxf(frame.size(), 1)
	var px := get_window().size  # (the window as the OS gave it, which may differ from the size asked)
	print("bench: %s at %dx%d: %d frames, %.1f fps; frame %.2f ms (p95 %.2f); GPU %.2f ms (p95 %.2f); render CPU %.2f ms; draws %.0f (max %.0f); objects %.0f; primitives %.0fk; video mem %.0f MB"
		% [name, int(px.x), int(px.y), frame.size(), frame.size() / MEASURE_S, _avg(frame), _pct(frame, 0.95), _avg(gpu), _pct(gpu, 0.95), _avg(cpu),
		_avg(draws), draws.max() if not draws.is_empty() else 0.0, objects / n, prims / n / 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	var subs: Array[String] = []
	for vp: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		var sv := vp as SubViewport
		if sv.render_target_update_mode != SubViewport.UPDATE_DISABLED and sv.is_inside_tree():
			subs.append("%s %dx%d mode %d (%s)" % [sv.name, sv.size.x, sv.size.y, sv.render_target_update_mode, sv.get_parent().name if sv.get_parent() else "-"])
	_census("measured")
	if OS.get_environment("BENCH_SPLIT") == "1" and level:
		await _split(name)
	print("bench: %s: SubViewports rendering: %d %s" % [name, subs.size(), subs])


## What each of the level's children costs the GPU: each hidden in turn for a moment (primitives,
## draws, GPU ms with it hidden against all shown).
func _split(name: String) -> void:
	var base := await _sample()
	print("bench: %s split: all shown: %.0fk primitives, %.0f draws, GPU %.2f ms" % [name, base[0] / 1000.0, base[1], base[2]])
	for c: Node in level.get_children():
		var n := c as Node3D
		if n == null or not n.visible:
			continue
		n.visible = false
		var got := await _sample()
		n.visible = true
		if base[0] - got[0] > 20000.0 or base[1] - got[1] > 20.0 or base[2] - got[2] > 0.5:
			print("bench: %s split: %-20s %.0fk primitives, %.0f draws, GPU %.2f ms" % [name, n.name, (base[0] - got[0]) / 1000.0, base[1] - got[1], base[2] - got[2]])


func _sample() -> Array:
	for i in 10:
		await get_tree().process_frame
	var p := 0.0
	var d := 0.0
	var g := 0.0
	for i in 30:
		await get_tree().process_frame
		p += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		d += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		g += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	return [p / 30.0, d / 30.0, g / 30.0]


func _avg(v: Array[float]) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / maxf(v.size(), 1)


func _pct(v: Array[float], p: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[mini(int(s.size() * p), s.size() - 1)]
