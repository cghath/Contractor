extends Node
## Hosts a session, stages a few scenes (gear pickup, plate hits, wall damage) and saves
## screenshots to res://screenshots/. Needs a real window (not --headless):
##   <voxel godot exe> --path . res://tests/screenshot_tour.tscn

const OUT_DIR := "res://screenshots"

var level: CompoundLevel
var player: Soldier
var input: PlayerInput
var camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	input = player.get_node(^"PlayerInput")
	input.set_physics_process(false)
	camera = Camera3D.new()
	camera.fov = 75
	add_child(camera)
	camera.current = true
	_gear_up()
	player.global_position = Vector3(12, 0.1, 31)  # out of the line-up shot
	_lineup()
	await _wait(90)  # voxel meshes and collision are built asynchronously after the edit
	_shoot_dummies()
	_shoot_wall()
	await _wait(40)

	input.hud.visible = false
	await _shot("00_soldier_lineup", Vector3(0.6, 1.35, 30.2), Vector3(0, 1.0, 27))
	await _shot("00b_soldier_closeup", Vector3(-1.1, 1.55, 28.4), Vector3(-1.5, 1.3, 27))
	await _shot("00c_heavy_kit", Vector3(0.95, 1.6, 28.3), Vector3(0.5, 1.3, 27))
	await _shot("01_compound_overview", Vector3(26, 16, 34), Vector3(0, 0, -2))
	await _shot("02_gate_loot", Vector3(0, 1.65, 23.2), Vector3(0, 0.3, 19.8))
	await _shot("03_dummies_plates", Vector3(0, 1.6, 16.5), Vector3(0, 1.0, 12))
	await _shot("04_heavy_dummy_hits", Vector3(4.4, 1.55, 13.4), Vector3(4, 1.35, 12.1))
	await _shot("05_light_dummy_hits", Vector3(-3.6, 1.55, 13.4), Vector3(-4, 1.35, 12.1))
	await _shot("08_heavy_helmet_closeup", Vector3(4.3, 1.85, 12.75), Vector3(4, 1.68, 12))
	await _shot("09_light_helmet_closeup", Vector3(-3.7, 1.85, 12.75), Vector3(-4, 1.68, 12))
	await _shot("06_wall_damage", Vector3(-1.2, 1.6, -0.6), Vector3(-3, 1.5, -4))
	input.hud.visible = true
	input.hud.update_status(player)
	input.hud.toggle_detail()  # opens the inventory screen
	await _wait(3)
	input.hud.update_status(player)
	await _shot("07_hud_inventory", Vector3(0, 1.65, 18), Vector3(0, 1.3, 12))
	await _shot("10_reload_pose", Vector3(-0.85, 1.5, 28.1), Vector3(-0.5, 1.25, 27))
	input.hud.toggle_detail()  # close the inventory screen
	var downed: TargetDummy = level.get_node(^"Dummies/LightDummy")
	downed.respawn_seconds = 999.0
	downed.vitals.server_reset_health()
	downed.vitals.server_damage(500.0)  # down, bleeding out
	await _wait(60)
	await _shot("11_downed_dummy", Vector3(-2.6, 1.3, 14.4), Vector3(-4, 0.2, 11.6))
	# Aiming down the sights, through the player's own camera.
	player.global_position = Vector3(1.2, 0.1, 17.5)
	player.rotation.y = 0.15
	player.head.rotation.x = -0.08
	player.is_aiming = true
	input.camera.fov = 50.0
	input.view_model.position = PlayerInput.ADS_EYE - VoxelArt.sight_point(VoxelArt.model_for(ItemDB.get_item(&"m4a1")))
	input.camera.current = true
	await _wait(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/12_aim_down_sights.png" % OUT_DIR)
	print("Screenshots saved to %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _lineup() -> void:
	var kits := [
		# Light, medium and heavy kit, then a medium pistol carrier.
		["desert", ["plate_carrier_light", "plate_pe_l3", "helmet_bump", "mk18", "m17"], CharacterModel.Hold.BOTH],
		["multicam", ["plate_carrier", "plate_ceramic_l4", "plate_ceramic_l4", "helmet", "m4a1", "m17", "assault_pack"], CharacterModel.Hold.BOTH],
		["woodland", ["plate_carrier_heavy", "plate_steel_l3", "plate_steel_l3", "plate_side", "plate_side", "helmet_heavy", "m110", "ruck_45"], CharacterModel.Hold.NONE],
		["urban", ["plate_carrier", "plate_ceramic_l4", "helmet", "m17"], CharacterModel.Hold.RIGHT],
	]
	for i in kits.size():
		var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
		dummy.get_node(^"Model").variant = kits[i][0]
		dummy.loadout = PackedStringArray(kits[i][1])
		dummy.position = Vector3(-1.5 + i, 0, 27)
		dummy.rotation.y = PI
		add_child(dummy)
		dummy.get_node(^"Label").visible = false
		dummy.get_node(^"Model").hold = kits[i][2]
		if i == 1:
			dummy.get_node(^"Model").reloading = true  # show the reload pose


func _gear_up() -> void:
	for id: StringName in [&"plate_carrier_heavy", &"plate_ceramic_l4", &"plate_steel_l3", &"plate_side", &"m4a1", &"m17", &"assault_pack", &"helmet_heavy"]:
		player.inventory.take(id)
	player.inventory.take(&"mag_556", 8)
	player.inventory.take(&"ifak", 2)
	player.inventory.take(&"electronics_salvage", 6)
	player.inventory.take(&"mag_556", 1, {"rounds": 12})
	player.inventory.take(&"plate_pe_l3", 1, {"chips": [[12, 15, 0, 3.2], [6, 20, 0, 3.2]]})
	for i in 4:
		player.inventory.consume_round(&"primary")


func _shoot_dummies() -> void:
	var rifle := ItemDB.get_item(&"m4a1")
	var dmr := ItemDB.get_item(&"m110")
	var offsets := [Vector2(0, 0), Vector2(0.06, 0.07), Vector2(-0.07, 0.03), Vector2(0.03, -0.09), Vector2(-0.05, -0.05), Vector2(0.08, -0.02)]
	for dummy_x: float in [-4.0, 4.0]:
		for o: Vector2 in offsets:
			_fire(Vector3(dummy_x, 1.23, 20), Vector3(dummy_x + o.x, 1.23 + o.y, 12.15), rifle)
	_fire(Vector3(4, 1.23, 20), Vector3(4, 1.23, 12.15), dmr)  # same spot again: goes through
	for dummy_x: float in [-4.0, 4.0]:  # helmets
		for o: Vector2 in [Vector2(0.04, 0.0), Vector2(-0.05, 0.05), Vector2(0.06, 0.08), Vector2(-0.02, 0.1)]:
			_fire(Vector3(dummy_x, 1.72, 20), Vector3(dummy_x + o.x, 1.7 + o.y, 12.0), rifle)


func _shoot_wall() -> void:
	var rifle := ItemDB.get_item(&"m4a1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var target := Vector3(-3 + rng.randf_range(-0.6, 0.6), 1.5 + rng.randf_range(-0.5, 0.5), -4)
		_fire(Vector3(-1, 1.6, 6), target, rifle)


func _fire(from: Vector3, to: Vector3, weapon: ItemData) -> void:
	# No impact markers here: they would hide the damage we want to show.
	Ballistics.fire(player, from, (to - from).normalized(), weapon)


func _shot(file: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target)
	await _wait(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, file])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
