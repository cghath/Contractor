extends Node
## The walk-in cabins and their sliding doors (Captain, 2026-10-17): the UH-60's roomy cabin
## (open floor, kneeling and standing spots, the 4-seat aft bench, riders on the door sills,
## boarding that doesn't float), and each airframe's door (UH-60, VT-14 Petrel, Razorback):
## flush shut, popped out past the hull, slid back; the FFV riders crouched behind it shut and
## sitting with it open. Needs a real window, but never takes focus or the mouse (ShotWindow:
## tests/shot_window.gd).
##   <voxel godot exe> --path . res://tests/uh60_cabin_shots.tscn --position -20000,-20000 -- <output folder>
## Keep the output as an S run (docs/debugging.md).

## [model, where it's parked, the left door's [x of its skin, y0, y1, z0, z1]]
const AIRFRAMES := [
	["uh60", Vector3(20, 0, 40), [1.264, 0.6, 2.38, -3.9, -1.2]],
	["vtol_petrel", Vector3(60, 0, 40), [1.244, 0.6, 2.6, -2.4, 0.6]],
	["vtol_razorback", Vector3(110, 0, 40), [2.045, 1.0, 3.6, -4.1, -1.5]],
]

var level: CompoundLevel
var _made := 0


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[uh60] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/uh60_cabin"
	DirAccess.make_dir_recursive_absolute(out)

	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "shots_uh60" + tag
	Campaign.campaign_id = "shots_uh60" + tag
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(-40, 0.1, -40)
	var layer := level.get_node(^"Vehicles") as VehicleLayer
	var helis: Array[Vehicle] = []
	for a: Array in AIRFRAMES:
		helis.append(layer.server_spawn(a[0], Transform3D(Basis(), a[1]), "", &"player", "shots_" + String(a[0])))
		VehicleHull.prewarm(a[0])
	var t0 := Time.get_ticks_msec()
	while not AIRFRAMES.all(func(a: Array) -> bool: return VehicleHull.is_ready(a[0])) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	for i in 60:
		await get_tree().physics_frame  # settled on their wheels
	if headless:
		print("[uh60] headless: spawned the airframes, no shots")
		get_tree().quit(0)
		return
	player._hud.visible = false
	player.player_input.set_process(false)
	player.player_input.set_physics_process(false)
	player.view_model.visible = false
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = 0.05
	add_child(camera)
	camera.current = true

	# Every airframe's left door: shut (flush), popped out, slid open; its FFV riders crouched
	# behind it shut and sitting with it open.
	for n in AIRFRAMES.size():
		var heli := helis[n]
		var model := String(AIRFRAMES[n][0])
		var d: Array = AIRFRAMES[n][2]
		var at := func(local: Vector3) -> Vector3: return heli.to_global(local)
		var mid_y := (float(d[1]) + float(d[2])) * 0.5
		var mid_z := (float(d[3]) + float(d[4])) * 0.5
		var riders: Array[Soldier] = []
		for side_seat in heli.seat_count():
			if String(heli.spec.seats[side_seat].get("ffv", "")) == "left":
				var r := _soldier(at.call(Vector3(25, 0.1, 0)))
				await get_tree().physics_frame
				heli.server_enter(r, side_seat)
				riders.append(r)
		for i in 30:
			await get_tree().process_frame
		var side_eye: Vector3 = at.call(Vector3(-float(d[0]) - 4.5, mid_y + 0.6, mid_z + 1.5))
		var side_look: Vector3 = at.call(Vector3(-float(d[0]), mid_y, mid_z))
		var edge_eye: Vector3 = at.call(Vector3(-float(d[0]) - 0.9, mid_y + 0.3, float(d[3]) - 1.6))
		var edge_look: Vector3 = at.call(Vector3(-float(d[0]), mid_y, float(d[3]) + 0.4))
		var in_eye: Vector3 = at.call(Vector3(0.6, mid_y + 0.7, mid_z + 0.4))
		var in_look: Vector3 = at.call(Vector3(-float(d[0]), mid_y - 0.4, mid_z))
		await _shot(camera, out, model + "_door_1_shut", side_eye, side_look)
		await _shot(camera, out, model + "_door_1_shut_edge", edge_eye, edge_look)
		await _shot(camera, out, model + "_ffv_crouched", in_eye, in_look)
		heli.server_set_bay(true)
		var bay := heli.bay
		while bay.open_fraction() < VehicleBay.POP_PART * 0.9:
			await get_tree().process_frame
		await _shot(camera, out, model + "_door_2_popped_edge", edge_eye, edge_look, false)
		for i in 90:
			await get_tree().process_frame
		await _shot(camera, out, model + "_door_3_open", side_eye, side_look)
		await _shot(camera, out, model + "_ffv_sitting", in_eye, in_look)
		heli.server_set_bay(false)
		for i in 90:
			await get_tree().process_frame
		for r in riders:
			heli.server_exit(r)
			r.queue_free()

	# The UH-60's cabin: empty, a rider boarding by the right door, then full.
	var heli := helis[0]
	var at := func(local: Vector3) -> Vector3: return heli.to_global(local)
	heli.server_set_bay(true)
	for i in 90:
		await get_tree().process_frame
	await _shot(camera, out, "uh60_cabin_empty_door", at.call(Vector3(-3.4, 1.9, -2.55)), at.call(Vector3(0.6, 1.2, -2.3)))
	await _shot(camera, out, "uh60_cabin_empty_aft_forward", at.call(Vector3(0, 2.2, 0.85)), at.call(Vector3(0, 1.0, -4.5)))
	heli.server_set_bay(false)
	for i in 90:
		await get_tree().process_frame  # shut again: boarding opens them
	var boarder := _soldier(at.call(Vector3(2.6, 0.1, -2.55)))
	await get_tree().physics_frame
	heli.server_enter(boarder, 13)  # the aft bench, in by the right door
	var side_eye: Vector3 = at.call(Vector3(5.2, 1.6, -0.6))
	var side_look: Vector3 = at.call(Vector3(1.2, 1.0, -2.0))
	for step: Array in [[0.15, "board_1_foot_up"], [0.45, "board_2_push"], [0.8, "board_3_on_sill"], [2.0, "board_4_walk_in"], [3.4, "board_5_sitting"]]:
		while boarder.model.action_seconds() >= 0.0 and boarder.model.action_seconds() < float(step[0]):
			await get_tree().process_frame
		await _shot(camera, out, "uh60_" + String(step[1]), side_eye, side_look, false)
	for i in 60:
		await get_tree().process_frame
	for i in heli.seat_count():
		if heli.seat_kind(i) == Vehicle.PASSENGER and heli.occupant(i) == null:
			heli.server_enter(_soldier(at.call(Vector3(20, 0.1, 0))), i)
	heli.server_set_bay(true)
	for i in 120:
		await get_tree().process_frame
	await _shot(camera, out, "uh60_riders_door", at.call(Vector3(-3.4, 1.9, -2.55)), at.call(Vector3(0.6, 1.2, -1.6)))
	await _shot(camera, out, "uh60_riders_outside", at.call(Vector3(-6.0, 2.2, -1.0)), at.call(Vector3(0, 1.2, -2.4)))
	await _shot(camera, out, "uh60_riders_aft_forward", at.call(Vector3(0, 2.38, 0.9)), at.call(Vector3(0, 1.1, -4.0)))
	await _shot(camera, out, "uh60_riders_forward_aft", at.call(Vector3(0, 2.2, -4.9)), at.call(Vector3(0, 1.2, 0.8)))
	# The door gunners on their guns in the open ports, from outside and from the crew chief's eye.
	for g in [2, 3]:
		var gunner := _soldier(at.call(Vector3(20, 0.1, 0)))
		await get_tree().physics_frame
		heli.server_enter(gunner, g)
		gunner.rotation.y = heli.global_rotation.y + (PI / 2.0 if g == 2 else -PI / 2.0) + 0.35
		gunner.model.look_pitch = -0.15
	for i in 30:
		await get_tree().process_frame
	await _shot(camera, out, "uh60_gunner_port_outside", at.call(Vector3(-4.2, 2.2, -6.2)), at.call(Vector3(-1.3, 1.7, -4.55)))
	await _shot(camera, out, "uh60_gunner_inside", at.call(Vector3(0.3, 2.3, -5.2)), at.call(Vector3(-1.4, 1.6, -4.4)))
	await _shot(camera, out, "uh60_gunner_over_shoulder", at.call(Vector3(0.1, 2.35, -4.3)), at.call(Vector3(-2.6, 1.4, -5.2)))
	await _shot(camera, out, "uh60_kneelers", at.call(Vector3(0.0, 2.3, -4.3)), at.call(Vector3(0.0, 0.9, -2.2)))
	await _shot(camera, out, "uh60_kneelers_side", at.call(Vector3(-0.9, 1.6, -0.6)), at.call(Vector3(0.0, 0.9, -2.55)))
	# An AI running out of the right door from the aft bench (Vehicle.server_run_out).
	var runner := heli.occupant(13)
	heli.server_run_out(runner)
	var run_eye: Vector3 = at.call(Vector3(5.5, 1.8, -0.2))
	var run_look: Vector3 = at.call(Vector3(1.0, 1.0, -2.2))
	for step: Array in [[0.25, "run_1_up"], [0.9, "run_2_to_door"], [1.45, "run_3_off_sill"], [1.7, "run_4_down"]]:
		while runner.model.action_seconds() >= 0.0 and runner.model.action_seconds() < float(step[0]):
			await get_tree().process_frame
		await _shot(camera, out, "uh60_" + String(step[1]), run_eye, run_look, false)
	# The Razorback's aft exo bay, two soldiers drawn 1.25x as stand-ins for HX-1 suits.
	var rb := helis[2]
	var rat := func(local: Vector3) -> Vector3: return rb.to_global(local)
	for i in rb.seat_count():
		if not rb.exo_seat(i):
			continue
		var big := _soldier(rat.call(Vector3(30, 0.1, 0)))
		await get_tree().physics_frame
		rb.server_enter(big, i)
		big.model.scale = Vector3.ONE * 1.25
		big.gear.scale = Vector3.ONE * 1.25
	rb.server_set_bay(true)
	for i in 120:
		await get_tree().process_frame
	await _shot(camera, out, "razorback_exo_bay_ramp", rat.call(Vector3(0.0, 3.4, 9.5)), rat.call(Vector3(0.0, 2.2, 3.5)))
	await _shot(camera, out, "razorback_exo_bay_inside", rat.call(Vector3(1.6, 3.4, 1.4)), rat.call(Vector3(-0.6, 2.0, 4.4)))
	print("[uh60] saved to %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _soldier(pos: Vector3) -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": "Rider%d" % _made, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": ["plate_carrier", "helmet", "assault_pack", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _shot(camera: Camera3D, out: String, file: String, eye: Vector3, target: Vector3, settle := true) -> void:
	camera.global_position = eye
	camera.look_at(target)
	for i in (6 if settle else 1):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[uh60] saved %s" % path)
