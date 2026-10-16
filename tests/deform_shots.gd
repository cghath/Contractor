extends Node
## Screenshots of procedural body deform (BodyDeform; Captain, 2026-10-16: "send screenies of the
## deform"). Needs a real window, not --headless (it never takes focus: shot_window.gd):
##   <voxel godot exe> --path . --resolution 1600x900 res://tests/deform_shots.tscn -- <output folder>
## One soldier in plain uniform (no armour, so the rounds reach the body), shot with a rifle
## through the right thigh, the left shoulder, an arm and the chest; front and back close-ups
## show the entry craters and the bigger exits.

const SPOT := Vector3(0, 0.1, 20)

var out := "res://screenshots/deform"
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
	GameState.zone_id = "deform_shots"
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
	_shooter = player
	var dummy := level.spawn_soldier({"name": "Dummy", "faction": "hostile", "variant": "multicam",
		"pos": SPOT, "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
	SquadAI.of(dummy).process_mode = Node.PROCESS_MODE_DISABLED
	dummy.rotation.y = PI  # facing +z, towards the front camera
	camera = Camera3D.new()
	camera.fov = 35.0
	level.add_child(camera)
	camera.make_current()
	await _seconds(1.0)
	dummy.vitals.set_process(false)  # no bleeding out mid-shoot: what the rounds do, nothing else
	dummy.vitals.set_physics_process(false)
	model = dummy.get_node(^"Model")
	deform = model.get_node(^"BodyDeform")
	var m4 := ItemDB.get_item(&"m4a1")
	var m110 := ItemDB.get_item(&"m110")
	await _look(Vitals.UPPER_ARM_R, "alive_arm_0_hits")
	# Alive: 5.56 into the right arm, a pair at a time. It tears up but stays on (SEVER_ALIVE).
	for pair in 3:
		for k in 2:
			_hit(dummy, Vitals.UPPER_ARM_R, m4, pair * 2 + k)
		await _seconds(0.8)
		await _look(Vitals.UPPER_ARM_R, "alive_arm_%d_hits" % ((pair + 1) * 2))
	print("[shots] alive: arm score %.1f, severed %s" % [deform.score_of(Vitals.UPPER_ARM_R), deform.severed()])
	# Alive, a .308 burst on top: the arm comes off (Vitals.AMPUTATION: a bleed a tourniquet stops).
	for k in 3:
		_hit(dummy, Vitals.UPPER_ARM_R, m110, 6 + k)
	await _seconds(1.2)
	print("[shots] alive after .308: arm score %.1f, severed %s, up %s dead %s, amputation wound %s" % [deform.score_of(Vitals.UPPER_ARM_R), deform.severed(),
		dummy.vitals.is_up(), dummy.vitals.is_dead(), dummy.vitals.wound_list().filter(func(w: Dictionary) -> bool: return w.name == Vitals.AMPUTATION).map(func(w: Dictionary) -> String: return "%s %.1f L/min" % [w.part, w.rate])])
	var shoulder := model.part_node(Vitals.CHEST).global_position
	await _shot("alive_arm_amputated", shoulder + Vector3(-0.7, 0.6, 0.6), shoulder)
	# Dead: two .308 into the left arm take it off; three 5.56 into the head take that.
	dummy.vitals.server_kill()
	await _seconds(1.5)
	await _look(Vitals.UPPER_ARM_L, "dead_left_arm_before")
	for k in 2:
		_hit(dummy, Vitals.UPPER_ARM_L, m110, 10 + k)
	await _seconds(1.2)
	await _look(Vitals.UPPER_ARM_L, "dead_left_arm_308x2")
	for k in 3:
		_hit(dummy, Vitals.HEAD, m4, 20 + k)
	await _seconds(1.5)
	print("[shots] dead: severed %s, pieces %d" % [deform.severed(), deform.pieces().size()])
	await _look(Vitals.HEAD, "dead_head_556x3")
	var whole := model.part_node(Vitals.CHEST).global_position
	await _shot("dead_overview", whole + Vector3(0.9, 1.8, 1.4), whole)
	for piece in deform.pieces():
		if is_instance_valid(piece):
			await _shot("piece_%s" % piece.name, piece.global_position + Vector3(0.4, 0.7, 0.4), piece.global_position)
	print("[shots] done (%d)" % _shots)
	get_tree().quit(0)


var model: CharacterModel
var deform: BodyDeform


## A round from `weapon` into the middle of `part` where it is now, from above and in front
## (`k` spreads them a little so they don't all go through one hole).
func _hit(dummy: Soldier, part: StringName, weapon: ItemData, k: int) -> void:
	var bone := model.part_node(part)
	var target := bone.global_transform * (_mid(part) + Vector3(0, 0.03 * ((k % 3) - 1), 0.01 * (k % 2)))
	var from := target + (dummy.global_basis * Vector3(0.2, 0.6, -1.6)).normalized() * 2.0
	var result := Ballistics.fire(_shooter, from, (target - from).normalized(), weapon)
	print("[shots] %s %s -> %s" % [weapon.id, part, result.get("result", "?")])


var _shooter: Soldier


func _look(part: StringName, label: String) -> void:
	var bone := model.part_node(part)
	var at := bone.global_transform * _mid(part)
	await _shot(label, at + Vector3(0.35, 0.55, 0.55), at)


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


## The middle of `part` in its bone's space (rest pose box centre minus the joint).
func _mid(part: StringName) -> Vector3:
	var boxes: Array = BodyMap.PART_BOXES.get(part, [])
	var centre: Vector3 = boxes[0][0] if not boxes.is_empty() else Vector3.ZERO
	return centre - BodyVolume.pivot_at(part, "male")
