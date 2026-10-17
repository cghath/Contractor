extends Node
## The LX-3 Assist Frame (ExoFrame) on a soldier: struts, hinges, cuffs, spine pack and shoulder
## pylons, the status light working (green) and disabled (red). Needs a real window, but never
## takes focus or the mouse (ShotWindow: tests/shot_window.gd), so it's safe to run alongside
## someone else at the keyboard.
##   <voxel godot exe> --path . res://tests/exo_shots.tscn -- <output folder>

var player: Soldier


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[exo] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/exo"
	DirAccess.make_dir_recursive_absolute(out)

	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "shots_exo" + tag
	Campaign.campaign_id = "shots_exo" + tag
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.host()
	var level: CompoundLevel = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(12, 0.1, 31)
	player.rotation.y = 0.0
	for id: StringName in [&"plate_carrier", &"helmet", &"m4a1"]:
		player.inventory.take(id)
	player.inventory.take(&"exo_frame_light")
	for i in 90:  # the draw animation (DRAW_S) and the hand easing onto the grip need real time
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	print("[exo] frame on: %s  working=%s  parts=%d" % [player.inventory.slots.get(ExoFrame.SLOT, &""),
		ExoFrame.working(player.inventory), player.model.find_children(ExoFrame.PART_NAME + "*", "", true, false).size()])
	if headless:
		print("[exo] headless: equipped the frame, no shots")
		get_tree().quit(0)
		return
	player._hud.visible = false

	var camera := Camera3D.new()
	camera.fov = 45
	add_child(camera)
	camera.current = true
	var c: Vector3 = player.global_position + Vector3(0, 1.3, 0)
	await _shot(camera, out, "exo_front", c + Vector3(0.3, 0.1, -1.6), c)
	await _shot(camera, out, "exo_side", c + Vector3(-1.8, 0.0, 0.0), c)
	await _shot(camera, out, "exo_rear", c + Vector3(0.0, 0.0, 1.6), c)
	await _shot(camera, out, "exo_spine_closeup", c + Vector3(0.1, 0.05, 0.6), c + Vector3(0, -0.05, 0.3))
	await _shot(camera, out, "exo_leg_closeup", player.global_position + Vector3(-0.35, 0.55, 0.9), player.global_position + Vector3(-0.1, 0.5, 0.0))
	await _shot(camera, out, "exo_arms_closeup", c + Vector3(0.0, -0.1, -1.0), c + Vector3(0, -0.2, 0))
	await _shot(camera, out, "exo_arms_side", c + Vector3(-1.0, -0.1, -0.3), c + Vector3(0, -0.2, 0))

	# Disable the frame (run it to 0 hp) and shoot the same set again: the light goes red.
	ExoFrame.server_damage(player, 1000.0)
	for i in 3:
		await get_tree().process_frame
	print("[exo] disabled: working=%s" % ExoFrame.working(player.inventory))
	await _shot(camera, out, "exo_front_disabled", c + Vector3(0.3, 0.1, -1.6), c)
	await _shot(camera, out, "exo_spine_closeup_disabled", c + Vector3(0.1, 0.05, 0.6), c + Vector3(0, -0.05, 0.3))
	print("[exo] saved to %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _shot(camera: Camera3D, out: String, file: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[exo] saved %s" % path)
