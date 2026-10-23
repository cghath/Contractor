extends Node
## The HX-1 Assault Frame (ExoMech) for art review: standing open on the vehicle range, a
## soldier climbing in (hatch half shut), piloted from all round with its WG-50 low and ready,
## close-ups of the gun, legs and head unit, plates after a few hits, climbing out, and first
## person. Needs a real window, but never takes focus or the mouse (ShotWindow:
## tests/shot_window.gd); run it off-screen (--position -20000,-20000).
##   <voxel godot exe> --path . --position -20000,-20000 --resolution 1280x800 res://tests/mech_shots.tscn -- <output folder>

var player: Soldier
var camera: Camera3D
var out := ""


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[mech] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 else "res://screenshots/mech"
	DirAccess.make_dir_recursive_absolute(out)

	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "shots_mech" + tag
	Campaign.campaign_id = "shots_mech" + tag
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var level := LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	for id: StringName in [&"plate_carrier", &"plate_steel_l3", &"helmet", &"m4a1"]:
		player.inventory.take(id)
	var suit := _suit()
	print("[mech] suit on the range: %s" % (suit != null))
	if suit == null:
		get_tree().quit(1)
		return
	var feet := suit.global_position - Vector3.UP * ExoMech.PARKED_SIZE.y * 0.5
	player.global_position = feet + Vector3(1.6, 0, 1.2)
	for i in 30:
		await get_tree().process_frame
	if headless:
		print("[mech] headless: no shots")
		get_tree().quit(0)
		return
	player._hud.visible = false
	for n: Node in get_tree().get_nodes_in_group(&"combatants"):  # the range's passers-by: out of the shots
		if n != player and n is Node3D:
			(n as Node3D).visible = false
	player.player_input.set_process(false)
	player.player_input.set_physics_process(false)  # (it shows the view model there)
	player.view_model.visible = false
	camera = Camera3D.new()
	camera.fov = 45
	add_child(camera)
	camera.current = true

	# Standing open on the range (it faces +Z, the spawn).
	var c := feet + Vector3(0, 1.4, 0)
	await _shot("parked_front", c + Vector3(1.0, 0.25, 2.4), c)
	await _shot("parked_side", c + Vector3(2.6, 0.1, 0.0), c)
	await _shot("parked_rear", c + Vector3(-0.8, 0.3, -2.4), c)
	await _shot("parked_release", c + Vector3(0.5, -0.1, -1.1), c + Vector3(0.1, -0.1, -0.5))

	# Climbing in from behind: the release, the back unzipping down the legs, the step in, shut.
	player.global_position = feet + Vector3(0, 0, -0.8)
	player.rotation.y = PI
	await _frames(3)
	player._server_enter_mech.rpc_id(1, suit.get_path())
	for step: Array in [[CharacterModel.MECH_RELEASE, 0.35, "entering_1_release"], [CharacterModel.MECH_RELEASE, 0.8, "entering_2_unzipped"],
			[CharacterModel.MECH_IN, 0.1, "entering_3_in_it_open"], [CharacterModel.MECH_IN, 0.6, "entering_4_zipping_shut"]]:
		while player.model.action_shown() != step[0]:
			await get_tree().process_frame
		await _wait_progress(float(step[1]))
		print("[mech] %s at %.2f" % [step[2], player.model.action_progress()])
		var eye: Vector3 = c + (Vector3(1.4, 0.3, -2.3) if step[0] == CharacterModel.MECH_RELEASE else Vector3(0.25, 0.6, -2.2))  # (in it: from straight behind)
		await _shot(String(step[2]), eye, c + Vector3(0, -0.3, 0))
	await get_tree().create_timer(ExoMech.ENTER_S * 0.4 + 1.5).timeout  # in, and the gun drawn
	for i in 90:
		await get_tree().process_frame
	print("[mech] piloting: %s  gun %s  parts %d" % [player.inventory.slots.get(ExoMech.SLOT, &""), player.inventory.slots.get(&"primary", &""),
		player.model.find_children(ExoMech.PART_NAME + "*", "", true, false).size()])

	# Piloted, all round (he faces +Z now: the suit's way).
	c = player.global_position + Vector3(0, 1.4, 0)
	await _shot("piloted_front", c + Vector3(0.9, 0.2, 2.6), c)
	await _shot("piloted_front_straight", c + Vector3(0.0, 0.1, 2.8), c)
	await _shot("piloted_side", c + Vector3(2.8, 0.0, 0.2), c)
	await _shot("piloted_rear", c + Vector3(-0.9, 0.3, -2.6), c)
	await _shot("piloted_gun_low_ready", c + Vector3(-1.4, -0.2, 1.6), c + Vector3(0.1, -0.35, 0.4))
	await _shot("piloted_legs", player.global_position + Vector3(1.2, 0.6, 1.4), player.global_position + Vector3(0, 0.5, 0))
	await _shot("piloted_head_unit", c + Vector3(0.5, 0.55, 1.1), c + Vector3(0, 0.55, 0))
	await _shot("piloted_low_angle", player.global_position + Vector3(1.4, 0.3, 2.2), c + Vector3(0, 0.2, 0))

	# Plates after a few hits: rifle rounds on the chest and a shoulder, AP through a thigh.
	var shooter := StaticBody3D.new()
	add_child(shooter)
	var gear := player.get_node(^"Gear") as GearRig
	var m855 := ItemData.from_dict({"id": "shots_mech_m855", "type": "weapon", "stats": {"round": "556_m855", "damage": 30}})
	var ap := ItemData.from_dict({"id": "shots_mech_ap", "type": "weapon", "stats": {"threat": "RF3", "round_class": String(Vitals.INTERMEDIATE), "damage": 30}})
	var chest: VoxelArmor = gear.pads().get("chest")
	for p: Vector3 in [Vector3(0.08, 0.05, -0.8), Vector3(-0.1, -0.03, -0.8), Vector3(0.0, 0.08, -0.8)]:
		Ballistics.fire(shooter, chest.to_global(p), chest.global_basis.z, m855)
	var thigh: VoxelArmor = gear.pads().get("thigh_r")
	Ballistics.fire(shooter, thigh.to_global(Vector3(0.8, 0.05, 0.0)), -thigh.global_basis.x, ap)
	player.vitals.server_reset_health()
	await _frames(4)
	await _shot("piloted_hits", c + Vector3(0.9, 0.2, 2.2), c)

	# First person, through his own eyes.
	player.view_model.visible = true
	camera.cull_mask = 0xFFFFF & ~PlayerInput.LOCAL_ONLY_LAYER
	camera.global_transform = player.camera.global_transform
	camera.fov = 75
	await _frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("mech_first_person.png"))
	player.view_model.visible = false
	camera.cull_mask = 0xFFFFF
	camera.fov = 45

	# Climbing out: the back unzipping, then he steps back out of it, and it's left standing open.
	player._server_exit_mech.rpc_id(1)
	for step: Array in [[0.4, "exiting_1_unzipping"], [0.95, "exiting_2_open"]]:
		await _wait_progress(float(step[0]))
		await _shot(String(step[1]), c + Vector3(0.25, 0.6, -2.2), c + Vector3(0, -0.3, 0))
	while player.model.action_shown() != CharacterModel.MECH_OUT:
		await get_tree().process_frame
	for step: Array in [[0.3, "exiting_3_stepping_out"], [0.7, "exiting_4_out"]]:
		await _wait_progress(float(step[0]))
		await _shot(String(step[1]), c + Vector3(2.0, 0.2, -1.8), c + Vector3(0, -0.3, -0.4))
	await get_tree().create_timer(ExoMech.OUT_S * 0.3 + 0.5).timeout
	await _shot("left_standing_open", c + Vector3(1.6, 0.4, -3.0), c)

	# The one lying face down (punched out), its back open: kneel at the release, lie down into
	# it, it zips shut and pushes itself up.
	var lying := _suit(true)
	if lying:
		var lf := ExoMech.parked_feet(lying)
		var mid := lf + Vector3(0, 0.5, 1.2)  # (it lies along +Z from its feet)
		await _shot("lying_punched_out", mid + Vector3(2.4, 1.4, -0.6), mid)
		await _shot("lying_back_open", mid + Vector3(0.4, 2.4, -1.2), mid)
		player.global_position = Vector3(ExoMech.parked_point(lying).x + 0.9, lf.y, ExoMech.parked_point(lying).z)
		player.rotation.y = -PI / 2
		await _frames(3)
		player._server_enter_mech.rpc_id(1, lying.get_path())
		for step: Array in [[CharacterModel.MECH_RELEASE, 0.5, "lying_1_release"], [CharacterModel.MECH_RISE, 0.1, "lying_2_in_it"],
				[CharacterModel.MECH_RISE, 0.45, "lying_3_shut"], [CharacterModel.MECH_RISE, 0.7, "lying_4_pushing_up"], [CharacterModel.MECH_RISE, 0.9, "lying_5_up"]]:
			while player.model.action_shown() != step[0]:
				await get_tree().process_frame
			await _wait_progress(float(step[1]))
			print("[mech] %s at %.2f" % [step[2], player.model.action_progress()])
			await _shot(String(step[2]), mid + Vector3(2.6, 1.0, -0.8), mid + Vector3(0, 0.3, -0.6))
	print("[mech] saved to %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _suit(prone := false) -> WorldItem:
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if n is WorldItem and (n as WorldItem).item_id == &"exo_mech_heavy" and bool((n as WorldItem).state.get("prone", false)) == prone:
			return n
	return null


## Until the clip playing reaches `u` of its length (or ends).
func _wait_progress(u: float) -> void:
	while player.model.action_progress() >= 0.0 and player.model.action_progress() < u:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = target + (eye - target) * 1.45  # the suit stands 2.3 m: step back for it
	camera.look_at(target)
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := out.path_join("mech_" + file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[mech] saved %s" % path)
