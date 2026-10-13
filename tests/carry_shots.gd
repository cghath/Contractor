extends Node
## Screenshots of carrying and dragging a casualty (needs a real window, not --headless):
##   <voxel godot exe> --path . --resolution 1280x720 res://tests/carry_shots.tscn -- <output folder>
## A player lifts a downed squadmate onto the shoulder, carries him, puts him down, takes him by
## the drag handle, drags him walking backwards and lets go; then an AI squadmate does the same.
## Third person from the side and the front, and first person through the carrier's own camera,
## for the holds and part way through each pick-up and put-down (slowed down so a shot lands
## where it says). Keep the output as an S run (docs/debugging.md).

const SPOT := Vector3(0, 0.1, 20)
## Game time runs this fast while a transition is shot, so the frames a shot takes barely move it.
const SLOW := 0.1

var level: CompoundLevel
var player: Soldier
var alpha: Soldier  # the casualty
var bravo: Soldier  # an AI squadmate who carries him too
var camera: Camera3D
var out := "res://screenshots/carry"
var _shots := 0


func _ready() -> void:
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("[shots] deadline passed, quitting")
		get_tree().quit(2))  # never idle forever (docs/debugging.md)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "carry_shots"
	CompoundLevel.spawn_ai = false
	Handedness._left = false
	Handedness._loaded = true
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack", &"helmet", &"m4a1"]:
		if ItemDB.has_item(id):
			player.inventory.take(id)
	player._hud.visible = false
	alpha = _spawn("Alpha", SPOT + Vector3(0.3, 0, -1.3))
	bravo = _spawn("Bravo", SPOT + Vector3(6.0, 0, 0))
	_place(player, SPOT)
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.current = true
	await _seconds(1.5)
	alpha.vitals.server_damage(500.0)
	await _settled(alpha)

	# Fireman's carry: pick up, hold, put down.
	player._server_carry_body.rpc_id(1, alpha.get_path())
	await _transition("carry_up", [0.15, 0.45, 0.75, 1.05, 1.35])
	await _seconds(1.0)
	await _around("carry_hold", player)
	await _first_person("carry_fp", [0.0, -0.45, 0.35])
	player._server_release_body.rpc_id(1)
	await _transition("carry_down", [0.2, 0.5, 0.8, 1.1])
	await _seconds(1.0)
	await _side("carry_down_laid", player)
	await _settled(alpha)

	# Drag by the vest's handle, walking backwards: take hold, drag, let go.
	_place(player, alpha.body_point() + Vector3(0.2, 0, -1.2) - Vector3(0, alpha.body_point().y - SPOT.y, 0))
	await _seconds(0.3)
	player._server_drag_body.rpc_id(1, alpha.get_path())
	await _transition("drag_up", [0.15, 0.4, 0.7, 1.0])
	await _seconds(0.8)
	player.global_position += player.global_basis.z * -0.8  # walked a step
	await _seconds(0.6)
	await _around("drag_hold", player)
	await _first_person("drag_fp", [-0.25, -0.6, 0.15])
	player._server_release_body.rpc_id(1)
	await _transition("drag_down", [0.2, 0.5, 0.8])
	await _seconds(1.0)
	await _side("drag_down_laid", player)
	await _settled(alpha)

	# An AI squadmate the same way (server_pick_up_body, as SquadAI calls it).
	_place(bravo, alpha.body_point() + Vector3(-0.9, 0, 0.3) - Vector3(0, alpha.body_point().y - SPOT.y, 0))
	bravo.look_at(alpha.body_point() * Vector3(1, 0, 1) + Vector3(0, bravo.global_position.y, 0))
	await _seconds(0.3)
	bravo.server_pick_up_body(alpha, Soldier.CARRY)
	await _transition("ai_carry_up", [0.3, 0.8], bravo)
	await _seconds(1.0)
	await _side("ai_carry_hold", bravo)
	print("[shots] %d shots saved to %s" % [_shots, out])
	get_tree().quit()


## Shots of `who` (the player unless given) at these moments (seconds of game time) after the
## call, with game time slowed so each lands close to its moment.
func _transition(label: String, at: Array, who: Soldier = null) -> void:
	var s := who if who else player
	var start := Time.get_ticks_msec()
	var game_t := 0.0
	Engine.time_scale = SLOW
	for t: float in at:
		while game_t < t:
			await get_tree().process_frame
			game_t += get_process_delta_time()
		await _side("%s_%.2fs" % [label, t], s)
	Engine.time_scale = 1.0
	print("[shots] %s took %d ms" % [label, Time.get_ticks_msec() - start])


## A side view (from the soldier's right) of `s`.
func _side(label: String, s: Soldier) -> void:
	var c := s.global_position + Vector3.UP * 0.8
	await _shot(label, c + s.global_basis.x * 3.2 + Vector3.UP * 0.4, c)


## The hold from the side, the front three-quarter and the back three-quarter.
func _around(label: String, s: Soldier) -> void:
	var c := s.global_position + Vector3.UP * 0.9
	await _shot(label + "_side", c + s.global_basis.x * 3.2 + Vector3.UP * 0.3, c)
	await _shot(label + "_front", c - s.global_basis.z * 2.6 + s.global_basis.x * 1.4 + Vector3.UP * 0.4, c)
	await _shot(label + "_back", c + s.global_basis.z * 2.6 - s.global_basis.x * 1.4 + Vector3.UP * 0.6, c)


## Through the player's own camera, looking up or down by each pitch (radians).
func _first_person(label: String, pitches: Array) -> void:
	camera.current = false
	player.camera.current = true
	for p: float in pitches:
		player.set_pitch(p)
		await _seconds(0.4)
		await _grab("%s_%+.2f" % [label, p])
	player.set_pitch(0.0)
	player.camera.current = false
	camera.current = true


func _shot(label: String, from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at)
	await _grab(label)


func _grab(label: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "%s/%02d_%s.png" % [out, _shots, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)


func _spawn(callsign: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": ["plate_carrier", "plate_steel_l3", "m4a1", "assault_pack", "helmet"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # staged by hand
	return s


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.rotation = Vector3.ZERO
	s.velocity = Vector3.ZERO


## Until `s`'s ragdoll has come to rest, at most 6 s.
func _settled(s: Soldier) -> void:
	var left := 6.0
	while left > 0.0 and not (is_instance_valid(s.ragdoll) and s.ragdoll.frozen):
		await _seconds(0.1)
		left -= 0.1


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
