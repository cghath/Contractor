extends Node
## Voxel smoke (SmokeCloud) in the compound: the roofless main building filling (from above, and
## from outside its doorway), the voxel shed full and pouring out of its doorway, a purple cloud
## in the open, and a hole a frag pushed in a cloud. Needs a real window, but never takes focus
## or the mouse (ShotWindow: tests/shot_window.gd).
##   <voxel godot exe> --path . res://tests/smokecloud_shots.tscn -- <output folder>

var level: CompoundLevel
var camera: Camera3D
var out := ""


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[smoke] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 else "res://screenshots/smoke"
	DirAccess.make_dir_recursive_absolute(out)
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "shots_smoke" + tag
	Campaign.campaign_id = "shots_smoke" + tag
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	SmokeCloud.wind_override = Vector3.ZERO
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_meshed():
		await get_tree().process_frame
	var player := level.players.get_node(^"1") as Soldier
	player.set_physics_process(false)
	player.global_position = Vector3(30, 0.1, 30)
	if headless:
		print("[smoke] headless: no shots")
		get_tree().quit(0)
		return
	player._hud.visible = false
	player.player_input.set_process(false)
	player.player_input.set_physics_process(false)
	player.view_model.visible = false
	camera = Camera3D.new()
	camera.fov = 60
	add_child(camera)
	camera.current = true

	# The main building (10 x 8 m, no roof, its doorway in the south wall at x -0.6..0.6, z -4).
	var room := _cloud(Vector3(2.5, 0.1, -10.0), 11)
	for t: float in [1.5, 4.0, 10.0]:
		room.run_to(t)
		await _shot("room_filling_%02ds_above" % roundi(t), Vector3(9, 9, 2), Vector3(0, 0.5, -8))
	await _shot("room_doorway_10s", Vector3(-1.5, 1.7, 4), Vector3(0, 1.0, -4))
	room.queue_free()
	# The voxel shed (roofed, its doorway in its west wall at x 16, z -9.6..-8.4).
	var shed := _cloud(Vector3(18.5, 0.1, -9.0), 12)
	shed.run_to(1.5)
	await _shot("shed_door_1s", Vector3(9.5, 1.8, -6.5), Vector3(16, 1.0, -9))
	shed.run_to(8.0)
	await _shot("shed_door_8s", Vector3(9.5, 1.8, -6.5), Vector3(16, 1.0, -9))
	await _shot("shed_door_8s_above", Vector3(10, 7, -2), Vector3(17, 1.0, -9))
	shed.queue_free()
	# Purple in the open, and a frag's hole in a white one.
	var purple := _cloud(Vector3(0, 0.1, 30), 13, "purple")
	purple.run_to(6.0)
	await _shot("purple_open_6s", Vector3(-9, 2.5, 42), Vector3(0, 1.2, 30))
	purple.queue_free()
	var white := _cloud(Vector3(-30, 0.1, 30), 14)
	white.run_to(6.0)
	await _shot("blast_before", Vector3(-30, 2.0, 42), Vector3(-30, 1.2, 30))
	Throwables.server_detonate(level, "frag", Vector3(-29, 0.1, 32))
	white.run_to(6.0 + 3.0 / SmokeCloud.HZ)
	await _shot("blast_hole_0.4s", Vector3(-30, 2.0, 42), Vector3(-30, 1.2, 30))
	white.run_to(7.5)
	await _shot("blast_hole_1.9s", Vector3(-30, 2.0, 42), Vector3(-30, 1.2, 30))
	SmokeCloud.wind_override = null
	GameState.delete_save()
	print("[smoke] done")
	get_tree().quit(0)


func _cloud(pos: Vector3, cloud_seed: int, colour := "white") -> SmokeCloud:
	level.spawn_smoke(pos, colour, 0.0, cloud_seed, Vector3.ZERO)
	var cloud := level.get_node(NodePath(SmokeCloud.node_name(cloud_seed))) as SmokeCloud
	cloud.set_physics_process(false)
	return cloud


func _shot(file: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[smoke] saved %s" % path)
