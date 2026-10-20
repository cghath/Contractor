extends Node
## Screenshots of the IFF marks (GearRig.iff_art) at combat range, to judge whether the sides
## can be told apart through a scope: the company (tan, blue), an allied soldier (multicam,
## green), Black Ridge's militia (urban, orange) and a Vantage contractor (black, red) side by
## side, about 150 m off, through a 4x and an 8x scope's field of view, by day, at dusk and at
## night with and without the NVG picture (NvgView's effect over the whole screen). Plus a
## close-up. Needs a real window, not --headless:
##   <voxel godot exe> --path . --resolution 1920x1080 res://tests/iff_shots.tscn -- <output folder>
## Keep the output as an S run (docs/debugging.md); the pictures don't go in the repo.

## Where the four stand and where the camera is (m): about 150 m apart, the line of sight past
## the compound, inside the 160 m ground.
const AT := Vector3(-70, 0.1, 65)
const EYE := Vector3(75, 1.7, 30)
## The camera's vertical field of view unaided (PlayerInput's), and a scope's power.
const FOV := 75.0

var out := "user://iff_shots"
var camera: Camera3D
var level: CompoundLevel
var men: Array[Soldier] = []
var _shots := 0


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("[shots] deadline passed, quitting")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "iff_shots"
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 24)
	player._hud.visible = false
	var across := Vector3(EYE.x - AT.x, 0, EYE.z - AT.z).normalized().cross(Vector3.UP)
	var kits := [["Company", "friendly", "tan", "", ["plate_carrier", "plate_ceramic_l4", "helmet", "assault_pack", "m4a1"]],
		["Allied", "friendly", "multicam", "allied", Kits.loadout("allied_us", 0)],
		["Militia", "hostile", "urban", "", CompoundLevel.hostile_loadout(0)],
		["Vantage", "hostile", "black", "", CompoundLevel.rival_pmc_loadout(1)]]
	for i in kits.size():
		var k: Array = kits[i]
		var pos := level.ground_point(AT + across * 1.6 * (i - 1.5))
		var s := level.spawn_soldier({"name": k[0], "faction": k[1], "variant": k[2], "iff": k[3], "pos": pos,
			"loadout": k[4], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		s.look_at(Vector3(EYE.x, s.global_position.y, EYE.z))
		if i == 3:
			s.rotate_y(PI * 0.5)  # one side on
		men.append(s)
		print("[shots] %s: %s, marks %s" % [s.name, s.iff, GearRig.side_of(s.faction, s.iff, s.variant)])
	camera = Camera3D.new()
	level.add_child(camera)
	camera.make_current()
	var aim := level.ground_point(AT) + Vector3(0, 1.2, 0)
	print("[shots] range %.0f m" % EYE.distance_to(aim))
	for light: Array in [["day", 12.0], ["dusk", 18.0], ["late_dusk", 18.5], ["night", 23.0]]:
		DayNight.current().server_set(float(light[1]), "clear")
		await _seconds(1.2)
		print("[shots] %s: darkness %.2f" % [light[0], DayNight.darkness_at(AT)])
		await _shot("%s_4x" % light[0], EYE, aim, 4.0)
		await _shot("%s_8x" % light[0], EYE, aim, 8.0)
	for own: Node in player.get_children():
		if own is NvgView:
			own.process_mode = Node.PROCESS_MODE_DISABLED  # its own (NVG off) would undo ours
	var nvg := NvgView.new(null)
	nvg.process_mode = Node.PROCESS_MODE_DISABLED  # shown by hand: nobody's wearing the NVG
	add_child(nvg)
	nvg.rect.visible = true
	nvg._material.set_shader_parameter(&"tube", 3.0)
	var size := get_viewport().get_visible_rect().size
	nvg._material.set_shader_parameter(&"aspect", size.x / size.y)
	GearRig.iff_light(true, DayNight.darkness_at(AT))
	await _shot("night_nvg_4x", EYE, aim, 4.0)
	await _shot("night_nvg_8x", EYE, aim, 8.0)
	nvg.queue_free()
	GearRig.iff_light(false, 0.0)
	DayNight.current().server_set(12.0, "clear")
	await _seconds(1.2)
	var near := aim + (EYE - aim).normalized() * 6.0
	await _shot("day_close", near, aim, 1.0)
	print("[shots] done (%d)" % _shots)
	get_tree().quit(0)


func _shot(label: String, from: Vector3, at: Vector3, power: float) -> void:
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) * 0.5) / power))
	camera.global_position = from
	camera.look_at(at)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "%s/%02d_%s.png" % [out, _shots, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
