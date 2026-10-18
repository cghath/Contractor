extends Node
## Screenshots of the two new faction colour schemes (CLAUDE.md squad-roles-pmc bundle, Captain
## 2026-10-17: "black for enemy pmc, tan for us"). Needs a real window, not --headless:
##   <voxel godot exe> --path . --resolution 1600x900 res://tests/faction_colors_shots.tscn -- <output folder>
## Three soldiers side by side: the player faction in "tan" with an M4A1, Black Ridge Militia in
## "urban" (orange patch) with an AKM, and the Vantage Group rival PMC in "black" (dark red
## patch) with a SCAR-H. Front, close-up and head-only views. Keep the output as an S run
## (docs/debugging.md).

const SPOT := Vector3(0, 0.1, 20)

var out := "res://screenshots/faction_colors"
var camera: Camera3D
var _shots := 0


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[shots] deadline passed, quitting")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "faction_colors_shots"
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
	var us := _spawn(level, "US", SPOT + Vector3(-1.6, 0, 0), "friendly", "tan")
	for id: StringName in [&"plate_carrier", &"plate_ceramic_l4", &"helmet", &"assault_pack", &"m4a1"]:
		us.inventory.take(id)
	var militia := _spawn(level, "BlackRidge", SPOT, "hostile", "urban")
	for id: String in CompoundLevel.HOSTILE_LOADOUT:
		militia.inventory.take(StringName(id))
	var vantage := _spawn(level, "Vantage", SPOT + Vector3(1.6, 0, 0), "hostile", "black")
	for id: String in CompoundLevel.rival_pmc_loadout(1):  # the SCAR-H slot
		vantage.inventory.take(StringName(id))
	camera = Camera3D.new()
	camera.fov = 40.0
	level.add_child(camera)
	camera.make_current()
	await _seconds(1.5)
	var chest := SPOT + Vector3(0, 1.3, 0)
	await _shot("front_all", chest + Vector3(0, 0.2, 5.2), chest)
	for s: Soldier in [us, militia, vantage]:
		var c := s.global_position + Vector3(0, 1.25, 0)
		await _shot("front_close_%s" % s.name, c + Vector3(0, 0.05, 1.3), c)
		await _shot("side_close_%s" % s.name, c + Vector3(1.0, 0.05, 0.6), c)
	var heads := SPOT + Vector3(0, 1.55, 0)
	await _shot("heads", heads + Vector3(0, 0.0, 2.6), heads)
	for s: Soldier in [us, militia, vantage]:
		var h := s.global_position + Vector3(0, 1.55, 0)
		await _shot("helmet_%s" % s.name, h + Vector3(0, 0.0, 0.5), h)
	print("[shots] done (%d)" % _shots)
	get_tree().quit(0)


func _spawn(level: CompoundLevel, soldier_name: String, pos: Vector3, faction: String, variant: String) -> Soldier:
	var s := level.spawn_soldier({"name": soldier_name, "faction": faction, "variant": variant,
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
