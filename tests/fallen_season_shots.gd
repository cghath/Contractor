extends Node
## Fallen's seasons on the land (plans/fallen-seasons.md, steps 8 and 9), in the real renderer
## (needs a window, not --headless; the window never takes focus):
##   <voxel godot exe> --path . res://tests/fallen_season_shots.tscn -- <season> <output folder> [zone id]
## Hosts Fallen's start zone (Survival.start_zone(), the zone def as Survival hosts it, its season
## set) with the season shown by SeasonLive, and saves <season>_<view>.png for four views: the farm
## (over the fields), a wood's edge (the most broadleaf trees together near the start), a pond or
## stream (the first that freezes; skipped with none) and the ground at the insertion point. At
## each view it then times FRAMES frames with vsync off and prints one line:
##   [frametime] <season> <view>: avg <ms> worst <ms> draws <n> prims <n>
## Run once per season (four processes: a fresh zone each); keep the output as an S run
## (docs/debugging.md).
## Season "perf" instead: no pictures; at the wood and the farm views, summer and winter shown in
## turn (SeasonLive, live) PERF_ROUNDS times, PERF_FRAMES frames each, and one line a view:
##   [perf] <zone> <view>: summer gpu <ms> cpu <ms> | winter gpu <ms> cpu <ms> (medians)
## Alternating in one process cancels out whatever else the machine is doing (a game running
## beside it moves both seasons alike); separate runs a season apart don't.

const DAY := {"spring": 5, "summer": 5, "autumn": 5, "winter": 4}
const FRAMES := 240
const PERF_ROUNDS := 8
const PERF_FRAMES := 90

var level: ZoneLevel
var camera: Camera3D
var season := "summer"


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(240.0).timeout.connect(func() -> void: get_tree().quit(2))  # never idle forever
	var args := OS.get_cmdline_user_args()
	season = String(args[0]) if args.size() > 0 else "summer"
	var out := String(args[1]) if args.size() > 1 else OS.get_environment("TEMP").path_join("fallen_season_shots")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # (frame times, not the monitor's)
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var zone := String(args[2]) if args.size() > 2 else Survival.start_zone()  # (another zone: one with water, for the ice)
	var def := MissionRegistry.zone_def(zone).duplicate(true)
	def["season"] = "summer" if season == "perf" else season
	$Main.host_zone(ZoneDef.normalize(def))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player._hud.visible = false
	var live := SeasonLive.install(level)
	var perf := season == "perf"
	if perf:
		season = "summer"
	live.server_set(season, int(DAY[season]))
	live.finish_blend()
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 6000.0
	add_child(camera)
	camera.current = true
	var t := level.terrain
	print("[shots] %s: zone %s (%s), day %d of the season, snow %.2f, leaf %.2f, ice %s, %d scatter items" % [season, zone, String(level.def.get("terrain", "")),
		int(DAY[season]), t.season_snow, level.scatter.leaf_cover, live.ice, level.scatter.total()])
	var ins := level.insertion_points()[0]
	if perf:
		await _perf(live, ins)
		get_tree().quit()
		return
	# The farm: from 35 m up past the start, toward the middle of the zone (its fields and woods).
	var toward := Vector3(-ins.x, 0, -ins.z).normalized()
	var farm_from := ins + Vector3(0, 35.0, 0) - toward * 20.0
	await _view(out, "farm", farm_from, ins + toward * 160.0)
	# A wood's edge: the broadleaf tree with the most others round it, from 30 m out at eye height.
	var wood := _wood_near(ins)
	if wood != Vector3.INF:
		var off := (ins - wood).normalized() * 30.0
		off.y = 0.0
		var from := wood + off
		from.y = t.height_at(from.x, from.z) + 1.8
		await _view(out, "wood", from, wood + Vector3(0, 4.0, 0))
	else:
		print("[shots] %s: no broadleaf wood near the start" % season)
	# A pond or stream (the first that freezes), from 25 m off and 6 m up.
	var w := t.water
	var bi := -1
	if w:
		for k in w.bodies.size():
			if w.iced(k):
				bi = k
				break
	if bi >= 0:
		var b: Dictionary = w.bodies[bi]
		var c2: Vector2 = b.centre if b.has("centre") else (b.pts as PackedVector2Array)[(b.pts as PackedVector2Array).size() / 2]
		var c := Vector3(c2.x, t.height_at(c2.x, c2.y), c2.y)
		var from := c + Vector3(25.0, 0, 18.0)
		from.y = t.height_at(from.x, from.z) + 6.0
		await _view(out, "water", from, c)
	else:
		print("[shots] %s: no stream, pond or lake in this zone" % season)
	# The ground at the insertion point, a man's height, looking in.
	await _view(out, "ground", ins + Vector3(0, 1.7, 0), Vector3(ins.x * 0.4, ins.y + 3.0, ins.z * 0.4))
	print("[shots] done: %s" % out)
	get_tree().quit()


## Summer and winter in turn at the wood's edge and over the farm: medians of the GPU's render time
## and the frame time.
func _perf(live: SeasonLive, ins: Vector3) -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var t := level.terrain
	var views := {}
	var wood := _wood_near(ins)
	if wood != Vector3.INF:
		var off := (ins - wood).normalized() * 30.0
		off.y = 0.0
		var from := wood + off
		from.y = t.height_at(from.x, from.z) + 1.8
		views["wood"] = [from, wood + Vector3(0, 4.0, 0)]
	var toward := Vector3(-ins.x, 0, -ins.z).normalized()
	views["farm"] = [ins + Vector3(0, 35.0, 0) - toward * 20.0, ins + toward * 160.0]
	for view: String in views:
		camera.global_position = views[view][0]
		camera.look_at(views[view][1])
		level.terrain.build_near(camera.global_position, 64)
		level.scatter.build_near(camera.global_position, 64)
		var gpu := {"summer": [], "winter": []}
		var cpu := {"summer": [], "winter": []}
		for k in PERF_ROUNDS:
			for s: String in ["summer", "winter"]:
				live.server_set(s, int(DAY[s]))
				live.finish_blend()
				for i in 20:
					await get_tree().process_frame  # (settle: the uniforms in, the frame after)
				var last := Time.get_ticks_usec()
				for i in PERF_FRAMES:
					await get_tree().process_frame
					var now := Time.get_ticks_usec()
					(cpu[s] as Array).append((now - last) / 1000.0)
					last = now
					(gpu[s] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		print("[perf] %s %s: summer gpu %.2f cpu %.2f | winter gpu %.2f cpu %.2f (medians of %d frames each)" % [String(level.def.get("id", "zone")), view,
			_median(gpu.summer), _median(cpu.summer), _median(gpu.winter), _median(cpu.winter), PERF_ROUNDS * PERF_FRAMES])


static func _median(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var l := list.duplicate()
	l.sort()
	return float(l[l.size() / 2])


## The broadleaf tree within 400 m of `near` with the most broadleaf trees within 20 m of it.
func _wood_near(near: Vector3) -> Vector3:
	var sc := level.scatter
	var best := Vector3.INF
	var most := 0
	var tried := 0
	for item: Dictionary in sc.items:
		if not sc._broadleaf(item) or (item.pos as Vector3).distance_to(near) > 400.0:
			continue
		tried += 1
		if tried > 300:
			break
		var n := sc.broadleaf_near(item.pos, 20.0)
		if n > most:
			most = n
			best = item.pos
	return best


func _view(out: String, view: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to)
	level.terrain.build_near(from, 64)
	level.scatter.build_near(from, 64)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join("%s_%s_%s.png" % [String(level.def.get("id", "zone")), season, view])
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)
	var total := 0.0
	var worst := 0.0
	var draws := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		total += ms
		worst = maxf(worst, ms)
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("[frametime] %s %s %s: avg %.2f worst %.2f draws %d prims %d" % [String(level.def.get("id", "zone")), season, view, total / FRAMES, worst, draws, prims])
