extends Node
## Screenshots of an AI squadmate dragging a downed one as a ragdoll (needs a real window, not
## --headless):
##   <voxel godot exe> --path . --resolution 1280x720 res://tests/drag_shots.tscn -- <output folder>
## Bravo takes Alpha by the straps at the head end and walks backwards, crouched, over a
## step (a 15 cm ledge) and a bump; shots from the side and the front part way, and a line per
## shot on how the ragdoll holds up (head end nearest the dragger, the feet on the ground, the
## fastest part: a throw or a jitter shows up there). Keep the output as an S run
## (docs/debugging.md).

const SPOT := Vector3(0, 0.1, 20)

var level: CompoundLevel
var alpha: Soldier  # the casualty
var bravo: Soldier  # the dragger
var camera: Camera3D
var out := "res://screenshots/drag"
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
	GameState.zone_id = "drag_shots"
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player._hud.visible = false
	player.global_position = SPOT + Vector3(12, 0, 0)
	alpha = _spawn("Alpha", SPOT + Vector3(0, 0, 1.6))
	bravo = _spawn("Bravo", SPOT + Vector3(0, 0, -0.2))
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.current = true
	await _seconds(1.0)
	alpha.vitals.server_damage(500.0)
	await _seconds(3.0)
	# At his head end, back to him, as SquadAI._care_reach and _start_drag leave the dragger.
	var head := alpha.model.head.global_position
	var way := head - alpha.model.torso.global_position
	way.y = 0.0
	way = way.normalized()
	bravo.global_position = Vector3(head.x, SPOT.y, head.z) + way * 0.35
	bravo.rotation = Vector3(0, atan2(-way.x, -way.z), 0)
	bravo.want_crouch = true
	# A step (15 cm) a metre on along his way, and a bump the casualty goes over first (world layer).
	_block(bravo.global_position + way * 2.6, Vector3(3, 0.15, 3))
	_block(bravo.global_position + way * 0.6, Vector3(0.5, 0.06, 0.4))
	await _seconds(0.3)
	print("[shots] took hold: %s" % bravo.server_pick_up_body(alpha, Soldier.DRAG))
	await _seconds(1.0)
	await _side("grabbed")
	bravo.move_input = Vector2(0, -1)  # straight back (his -Z, away from the casualty)
	for i in 4:
		await _seconds(1.1)
		_report("t%d" % i)
		await _side("drag_%d_side" % i)
		if i == 1 or i == 3:
			await _front("drag_%d_front" % i)
	bravo.move_input = Vector2.ZERO
	bravo.server_put_down()
	await _seconds(2.5)
	_report("let go")
	await _side("let_go")
	print("[shots] %d shots saved to %s" % [_shots, out])
	get_tree().quit()


func _report(label: String) -> void:
	var m := alpha.model
	var feet := maxf((m.part_node(Vitals.SHIN_L).global_transform * Vector3(0, -0.45, 0)).y, (m.part_node(Vitals.SHIN_R).global_transform * Vector3(0, -0.45, 0)).y)
	var fastest := 0.0
	if is_instance_valid(alpha.ragdoll):
		for p: Node in alpha.ragdoll.parts.values():
			if p is RigidBody3D:
				fastest = maxf(fastest, (p as RigidBody3D).linear_velocity.length())
	var head_d := _flat(m.head.global_position, bravo.global_position)
	var hips_d := _flat(m.torso.global_position, bravo.global_position)
	print("[shots] %s: dragger at %s moving %.2f m/s; casualty head %.2f m, hips %.2f m from him, highest foot %.2f m up, fastest part %.2f m/s, ragdoll %s"
		% [label, bravo.global_position, Vector2(bravo.velocity.x, bravo.velocity.z).length(), head_d, hips_d, feet - SPOT.y, fastest, alpha.dragged_as_ragdoll()])


## From the dragger's right, looking across the drag (he and the casualty both in frame).
func _side(label: String) -> void:
	var c := (bravo.global_position + alpha.body_point()) * 0.5 + Vector3.UP * 0.4
	await _shot(label, c + bravo.global_basis.x * 3.6 + Vector3.UP * 0.6, c)


## From in front of the dragger's way (behind the casualty's feet), looking at the head end.
func _front(label: String) -> void:
	var c := alpha.body_point() + Vector3.UP * 0.2
	await _shot(label, c + bravo.global_basis.z * 2.4 + bravo.global_basis.x * 0.8 + Vector3.UP * 0.9, c)


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


func _block(center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	b.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	b.add_child(mesh)
	add_child(b)
	b.global_position = center + Vector3(0, size.y * 0.5 - 0.1, 0)


func _spawn(callsign: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": ["plate_carrier", "plate_steel_l3", "m4a1", "assault_pack", "helmet"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # staged by hand
	return s


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
