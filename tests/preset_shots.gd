extends Node
## Screenshots of one terrain preset on a seeded zone (needs a real window, not --headless):
##   <voxel godot exe> --path . res://tests/preset_shots.tscn -- <preset id> <output folder> [seed]
## Saves <preset>_aerial.png (from above the zone), <preset>_ground.png (soldier's height at
## the insertion point, looking in), <preset>_trees.png and _scrub.png (the nearest of each, close
## up) and, for a preset with a sea, <preset>_shore.png. Run it
## once per preset (tools: docs/terrain_presets.md); keep the output as an S run
## (docs/debugging.md).

var level: ZoneLevel
var camera: Camera3D


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)  # no focus, no cursor capture: the machine stays usable
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))  # never idle forever (docs/debugging.md)
	var args := OS.get_cmdline_user_args()
	var preset := String(args[0]) if args.size() > 0 else "temperate"
	var out := String(args[1]) if args.size() > 1 else "res://screenshots"
	var seed_value := int(args[2]) if args.size() > 2 else 777
	DirAccess.make_dir_recursive_absolute(out)
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var def := ZoneDef.generate(seed_value, 1536.0)
	def["terrain"] = preset
	def["name"] = "Preset %s" % preset
	$Main.host_zone(ZoneDef.normalize(def))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player._hud.visible = false
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 6000.0
	add_child(camera)
	camera.current = true
	var t := level.terrain
	print("[shots] %s: seed %d, sea side %d (%.0f m), relief %.1f..%.1f m, %d scatter items" % [preset, seed_value, t.sea_side, t.sea_m, t.min_height, t.max_height, level.scatter.total()])
	var ins := level.insertion_points()[0]
	var mid := Vector3(0, t.height_at(0, 0), 0)
	await _shot("%s/%s_aerial.png" % [out, preset], Vector3(ins.x * 0.2, 520.0, ins.z * 0.2 + 420.0), mid)
	await _shot("%s/%s_ground.png" % [out, preset], ins + Vector3(0, 1.7, 0), Vector3(ins.x * 0.4, ins.y + 3.0, ins.z * 0.4))
	# Close up: the tree and the scrub nearest the insertion point (preset_trees, preset_scrub).
	for kind: int in [ZoneScatter.Kind.TREE, ZoneScatter.Kind.SCRUB]:
		var best: Dictionary = {}
		for item: Dictionary in level.scatter.items:
			if int(item.kind) == kind and (best.is_empty() or (item.pos as Vector3).distance_to(ins) < (best.pos as Vector3).distance_to(ins)):
				best = item
		if best.is_empty():
			continue
		var p: Vector3 = best.pos
		var tree := kind == ZoneScatter.Kind.TREE
		var away := Vector3(9.0, 3.0, 9.0) if tree else Vector3(2.2, 1.2, 2.2)
		await _shot("%s/%s_%s.png" % [out, preset, "trees" if tree else "scrub"], p + away, p + Vector3(0, 3.0 if tree else 0.3, 0))
	var module := level.modules()[0]
	var at := module.global_position
	await _shot("%s/%s_module.png" % [out, preset], at + Vector3(70, 22, 90), at + Vector3(0, 4, 0))
	if t.sea_side >= 0:
		var dir: Vector2 = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)][t.sea_side]
		var shore := Vector3(0, 0, 0) - Vector3(dir.x, 0, dir.y) * (t.size_m * 0.5 - t.sea_m * 0.55)
		shore.y = 25.0
		var look := Vector3(dir.x, 0, dir.y) * (t.size_m * 0.5 - 20.0) * 1.0
		await _shot("%s/%s_shore.png" % [out, preset], shore + Vector3(-dir.y, 0, dir.x) * 60.0, look + Vector3(0, -2, 0) - Vector3(dir.x, 0, dir.y) * 0.0)
	get_tree().quit()


func _shot(path: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to)
	level.terrain.build_near(from, 64)
	level.scatter.build_near(from, 64)
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)
