extends Node
## Screenshots of the world's look (cghath's world visual pass, 2026-10-20): buildings, compounds,
## the AA emplacement, the ground, props and trees, from the ground and from above, by day, from
## the same spots every run so a before and an after compare. Needs a real window (not --headless):
##   <voxel godot exe> --path . res://tests/world_shots.tscn -- <output folder> [preset] [seed]
## One zone (preset default temperate) with a compound, a grown outpost (its AA emplacement), a
## grown village, the HQ (its AA emplacement too) and a generated town, roads between them. For
## each spot it saves <spot>.png and prints a "[shots] perf" line: the frame's draw calls,
## primitives and objects, and the mean frame time over PERF_FRAMES (vsync off; the window is
## never focused, so treat the times as relative, before against after on the same machine).
## Keep the output as an S run (docs/debugging.md); the PNGs go wherever the first argument says.

const PERF_FRAMES := 40
const SETTLE_FRAMES := 14

var level: ZoneLevel
var camera: Camera3D
var player: Soldier
var out := ""
var _perf: Array[String] = []


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)  # no focus, no cursor capture
	get_tree().create_timer(400.0).timeout.connect(func() -> void: get_tree().quit(2))  # never idle forever
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 else OS.get_environment("TEMP").path_join("contractor_world_shots")
	var preset := String(args[1]) if args.size() > 1 else "temperate"
	var seed_value := int(args[2]) if args.size() > 2 else 4242
	DirAccess.make_dir_recursive_absolute(out)
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var mods := [
		{"id": "compound", "type": "compound", "pos": [-300, -264]},
		{"id": "outpost", "type": "outpost", "pos": [264, -300]},
		{"id": "village", "type": "village", "pos": [-288, 264]},
		{"id": "hq", "type": "hq", "pos": [276, 264]},
		{"id": "town", "type": "%s%d" % [ZoneModules.TOWN, seed_value], "pos": [0, 0]},
	]
	var roads: Array = []
	for m: Dictionary in mods.slice(0, 4):
		roads.append([[0.0, 0.0], [float(m.pos[0]), float(m.pos[1])]])
	var def := ZoneDef.normalize({"id": "world_shots" + OS.get_environment("CONTRACTOR_TEST_TAG"), "name": "World shots", "seed": seed_value,
		"size_m": 1536.0, "relief_m": 14.0, "terrain": preset, "hour": 11.5, "weather": "clear", "modules": mods,
		"insertion": [[0.0, 640.0]], "extraction": [[0.0, -640.0]]})
	def["roads"] = roads
	$Main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player._hud.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 6000.0
	add_child(camera)
	camera.current = true
	var t := level.terrain
	print("[shots] %s seed %d: %d scatter items, %d modules" % [preset, seed_value, level.scatter.total(), level.modules().size()])
	for m: ZoneModule in level.modules():
		await _module_shots(m)
	# The ground in the open, and a prop close up: from the insertion point.
	var ins := level.insertion_points()[0]
	await _shot("ground_eye", ins + Vector3(0, 1.7, 0), ins + Vector3(0, 0.6, -25))
	await _shot("ground_above", ins + Vector3(0, 14, 10), ins + Vector3(0, 0, -12))
	var prop := _nearest(ZoneScatter.Kind.PROP, ins, 0.0)
	if not prop.is_empty():
		var p: Vector3 = prop.pos
		await _shot("prop_close", _eye(p + Vector3(3.5, 0, 3.5), 1.5), p)
	# Each prop shape (ZoneScatter.PROP_SHAPES), the nearest of it to the middle. (Looked up by name:
	# the same script takes the before shots, on a checkout without them.)
	var consts := (level.scatter.get_script() as GDScript).get_script_constant_map()
	if consts.has("PROP_SHAPES"):
		for kind: String in consts.PROP_SHAPES:
			var best: Dictionary = {}
			for item: Dictionary in level.scatter.items:
				if int(item.kind) == ZoneScatter.Kind.PROP and level.scatter.call("_prop_kind", item) == kind and (best.is_empty() or (item.pos as Vector3).length() < (best.pos as Vector3).length()):
					best = item
			if not best.is_empty():
				var p: Vector3 = best.pos
				var far := maxf((best.size as Vector3).x, (best.size as Vector3).z) + 2.5
				await _shot("prop_%s" % kind, _eye(p + Vector3(far, 0, far * 0.8), 1.6), p)
	# A wood: the densest trees, from its edge and from above; a trunk close up.
	var wood := _densest_trees()
	if wood.is_finite():
		await _shot("wood_eye", _eye(wood + Vector3(0, 0, 34), 1.7), wood + Vector3(0, 2.0, 0))
		await _shot("wood_above", wood + Vector3(30, 40, 40), wood)
		var tree := _nearest(ZoneScatter.Kind.TREE, wood, 0.0)
		var tp: Vector3 = tree.pos
		await _shot("trunk_close", _eye(tp + Vector3(2.2, 0, 2.2), 1.5), tp + Vector3(0, 1.4, 0))
		var bush := _nearest(ZoneScatter.Kind.THICKET, wood, 0.0)
		if not bush.is_empty():
			var bp: Vector3 = bush.pos
			await _shot("thicket_close", _eye(bp + Vector3(3.0, 0, 3.0), 1.6), bp + Vector3(0, 0.9, 0))
	var f := FileAccess.open(out.path_join("perf.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_perf) + "\n")
	print("[shots] done: %s" % out)
	get_tree().quit()


func _module_shots(m: ZoneModule) -> void:
	var name := ZoneModules.base(m.type)
	var o := m.global_position
	player.global_position = o + Vector3(0, 0.2, 0)
	var waited := 0
	while not m.is_ready() and waited < 1800:
		await get_tree().process_frame
		waited += 1
	var half: Vector2 = ZoneModules.HALF.get(m.type, Vector2(20, 20))
	player.global_position = o + Vector3(half.x + 30.0, 0.2, half.y + 30.0)  # out of the shots, still in range
	var far := maxf(half.x, half.y)
	await _shot("%s_above" % name, o + Vector3(far * 0.9, far * 0.9 + 14.0, far * 1.25 + 10.0), o)
	await _shot("%s_eye" % name, _eye(o + Vector3(far * 0.25, 0, half.y + 12.0), 1.7), o + Vector3(0, 1.8, 0))
	if name == "town":
		await _shot("town_street", o + Vector3(-BuildingGen.TOWN_HALF_X + 6.0, 1.7, 1.5), o + Vector3(0, 2.2, -1.0))
		await _shot("town_facade", o + Vector3(14.0, 1.7, 2.5), o + Vector3(18.0, 2.4, -8.0))
		await _shot("town_roofs", o + Vector3(-22.0, 14.0, 30.0), o + Vector3(4.0, 3.0, 0.0))
	elif name == "compound":
		await _shot("compound_gate", o + Vector3(6.0, 1.7, half.y + 6.0), o + Vector3(0, 1.4, 20.0))
		await _shot("compound_inside", o + Vector3(-14.0, 1.7, 16.0), o + Vector3(0, 1.5, -8.0))
	elif name == "village":
		await _shot("village_close", o + Vector3(-4.0, 1.7, 2.0), o + Vector3(-12.0, 1.4, -10.0))
	var aa := m.points("aa")
	if not aa.is_empty():
		var a: Vector3 = aa[0]
		await _shot("%s_aa" % name, a + Vector3(3.6, 2.0, 3.4), a + Vector3(0, 0.8, -0.6))
		await _shot("%s_aa_side" % name, a + Vector3(-4.2, 1.6, -0.5), a + Vector3(0, 0.9, -0.8))


## A point `up` m over the ground at `p`.
func _eye(p: Vector3, up: float) -> Vector3:
	return Vector3(p.x, level.terrain.height_at(p.x, p.z) + up, p.z)


func _nearest(kind: int, to: Vector3, min_m: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for item: Dictionary in level.scatter.items:
		if int(item.kind) != kind:
			continue
		var d := (item.pos as Vector3).distance_to(to)
		if d >= min_m and d < best_d:
			best = item
			best_d = d
	return best


## The middle of the 24 m square with the most trees (Vector3.INF with none).
func _densest_trees() -> Vector3:
	var grid := {}
	for item: Dictionary in level.scatter.items:
		if int(item.kind) == ZoneScatter.Kind.TREE:
			var p: Vector3 = item.pos
			var g := Vector2i(floori(p.x / 24.0), floori(p.z / 24.0))
			grid[g] = int(grid.get(g, 0)) + 1
	var best := Vector2i.ZERO
	var most := 0
	for g: Vector2i in grid:
		if grid[g] > most:
			most = grid[g]
			best = g
	if most == 0:
		return Vector3.INF
	var x := (best.x + 0.5) * 24.0
	var z := (best.y + 0.5) * 24.0
	return Vector3(x, level.terrain.height_at(x, z), z)


func _shot(name: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to)
	level.terrain.build_near(from, 64)
	level.scatter.build_near(from, 64)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var started := Time.get_ticks_usec()
	for i in PERF_FRAMES:
		await get_tree().process_frame
	var ms := (Time.get_ticks_usec() - started) / 1000.0 / PERF_FRAMES
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	var line := "%-18s %5d draws %8d prims %5d objects %6.2f ms" % [name, draws, prims, objects, ms]
	_perf.append(line)
	print("[shots] perf %s" % line)
