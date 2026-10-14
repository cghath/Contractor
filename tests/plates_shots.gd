extends Node
## Screenshots of plates on the carrier (Captain, 2026-10-14: the co-op soak's soldiers looked
## plate-less). Needs a real window, not --headless:
##   <voxel godot exe> --path . --resolution 1600x900 res://tests/plates_shots.tscn -- <output folder>
## Three soldiers side by side in a Plate Carrier (Medium): left with front and rear plates (a
## role kit), middle with none (how the soak's bots kitted up: a carrier, no plates picked up),
## right a hostile's light carrier with its one front plate. Front, back and side views. Keep the
## output as an S run (docs/debugging.md).

const SPOT := Vector3(0, 0.1, 20)

var out := "res://screenshots/plates"
var camera: Camera3D
var _shots := 0


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		print("[shots] deadline passed, quitting")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "plates_shots"
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	var level := CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = SPOT + Vector3(0, 0, 12)
	player._hud.visible = false
	var plated := _spawn(level, "Plated", SPOT + Vector3(-1.2, 0, 0), "friendly")
	Roles.apply_kit(plated.inventory, Roles.RIFLEMAN)
	var bare := _spawn(level, "NoPlates", SPOT, "friendly")
	for id: StringName in [&"plate_carrier", &"helmet", &"assault_pack", &"m4a1"]:
		bare.inventory.take(id)
	var hostile := _spawn(level, "Hostile", SPOT + Vector3(1.2, 0, 0), "hostile")
	for id: String in CompoundLevel.HOSTILE_LOADOUT:
		hostile.inventory.take(StringName(id))
	for s: Soldier in [plated, bare, hostile]:
		print("[shots] %s: carrier %s, front %s, back %s" % [s.name, s.inventory.slots[&"vest"], s.inventory.slots[&"plate_front"], s.inventory.slots[&"plate_back"]])
	camera = Camera3D.new()
	camera.fov = 40.0
	level.add_child(camera)
	camera.make_current()
	await _seconds(1.5)
	# They face +z (toward the player's spot): the front camera is on +z.
	var chest := SPOT + Vector3(0, 1.3, 0)
	await _shot("front_all", chest + Vector3(0, 0.2, 4.2), chest)
	await _shot("back_all", chest + Vector3(0, 0.2, -4.2), chest)
	for s: Soldier in [plated, bare]:
		var c := s.global_position + Vector3(0, 1.25, 0)
		await _shot("front_close_%s" % s.name, c + Vector3(0, 0.05, 1.3), c)
		await _shot("side_close_%s" % s.name, c + Vector3(1.0, 0.05, 0.6), c)
		await _shot("back_close_%s" % s.name, c + Vector3(0, 0.05, -1.3), c)
	print("[shots] done (%d)" % _shots)
	get_tree().quit(0)


func _spawn(level: CompoundLevel, soldier_name: String, pos: Vector3, faction: String) -> Soldier:
	var s := level.spawn_soldier({"name": soldier_name, "faction": faction, "variant": "multicam" if faction == "friendly" else "urban",
		"pos": pos, "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	s.rotation.y = PI  # facing +z, towards the front camera
	return s


func _shot(label: String, from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "%s/%02d_%s.png" % [out, _shots, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
