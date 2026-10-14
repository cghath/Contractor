extends Node
## Every item in data/items.json lying on the ground (ItemArt ground models), laid out in rows on
## a seeded zone, left to settle, then checked and photographed (needs a real window for the
## shots; with --headless it only checks). Captain's ground-items pass, 2026-10-14:
##   <voxel godot exe> --path . res://tests/item_ground_shots.tscn -- <output folder> [seed]
## Prints, per item, how far the bottom of its box rests from the ground under it ([gap] in cm:
## + floating, - sunk) and whether it came to rest; a gap past GAP_LIMIT_CM or one still moving
## is a [FAIL] line. Saves overview_*.png from a standing soldier's eye height and row_*.png
## close-ups (a few items each, labelled). Keep the output as an S run (docs/debugging.md).

const GAP_LIMIT_CM := 1.5
const ROW_WIDTH_M := 5.0
const GAP_M := 0.22
## Extra rifles: each optic on an M4A1 (state "optic"), and one with none (irons).
const OPTIC_STATES := ["", "optic_red_dot", "optic_holo", "optic_lpvo", "optic_prism_4x", "optic_dmr_3_5_10", "optic_dmr_8x", "optic_dmr_3_15"]

var level: ZoneLevel
var camera: Camera3D
var placed: Array = []  # [WorldItem, label]
var rows: Array = []    # [[from x, to x, z, depth], ...]


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[items] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/items"
	var seed_value := int(args[1]) if args.size() > 1 else 777
	DirAccess.make_dir_recursive_absolute(out)
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var def := ZoneDef.generate(seed_value, 1536.0)
	def["terrain"] = "temperate"
	def["name"] = "Item ground shots"
	$Main.host_zone(ZoneDef.normalize(def))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player._hud.visible = false
	camera = Camera3D.new()
	camera.fov = 60
	camera.near = 0.02
	add_child(camera)
	camera.current = true
	var origin := _flat_spot(level.insertion_points()[0] + Vector3(6, 0, 6))
	player.global_position = origin + Vector3(-4, 0, -4)
	player.visible = false
	level.terrain.build_near(origin, 64)
	level.scatter.build_near(origin, 64)
	for i in 10:
		await get_tree().physics_frame
	# Lay them out: every item, then the rifle with each optic.
	var entries: Array = []
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if item.type == "medical" and item.volume_l <= 0.0:
			continue  # CPR: an action, not a thing
		entries.append([id, item.default_state()])
	for optic: String in OPTIC_STATES:
		entries.append([&"m4a1", {"rounds": 30, "optic": optic}])
	var x := 0.0
	var z := 0.0
	var depth := 0.0
	var row_start := 0.0
	var n := 0
	for e: Array in entries:
		var item := ItemDB.get_item(e[0])
		var state: Dictionary = e[1]
		var size := (Basis.from_euler(ItemArt.spawn_rotation(item)) * VoxelArmor.size_m(item)).abs() if item.type == "plate" or item.slot == &"helmet" else ItemArt.ground_size(item, state)
		if x > 0.0 and x + size.x > ROW_WIDTH_M:
			rows.append([row_start, x, z, depth])
			z += depth + GAP_M * 2.0
			x = 0.0
			depth = 0.0
		var at := origin + Vector3(x + size.x * 0.5, 0, z + size.z * 0.5)
		at.y = _ground_y(at) + size.y * 0.5 + 0.02
		var uid := "shot_%d" % n
		level.spawn_item(e[0], 1, at, uid, state)
		placed.append([uid, e[0], state.get("optic", null)])
		x += size.x + GAP_M
		depth = maxf(depth, size.z)
		n += 1
	rows.append([row_start, x, z, depth])
	for i in 240:  # 4 s to settle
		await get_tree().physics_frame
	var failed := _check()
	if not headless:
		await _shots(origin)
	print("[items] %d items laid out, %d rows" % [placed.size(), rows.size()])
	if failed:
		print("[items] TEST FAILED")
	else:
		print("[items] ITEM GROUND TEST PASSED")
	get_tree().quit(1 if failed else 0)


## The WorldItem spawned with `uid`.
func _node(uid: String) -> WorldItem:
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if (node as WorldItem).uid == uid:
			return node
	return null


## Every item: the bottom of its box against the ground under it, and whether it rests.
func _check() -> bool:
	var failed := false
	for p: Array in placed:
		var item_node := _node(p[0])
		if item_node == null:
			print("[FAIL] %s: not spawned" % p[1])
			failed = true
			continue
		var box: BoxShape3D = item_node._box
		var b := item_node.global_basis
		var half := box.size * 0.5
		var down := absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z
		var bottom := item_node.global_position.y - down
		var ground := _ground_y(item_node.global_position)
		var gap := (bottom - ground) * 100.0
		var speed := item_node.linear_velocity.length()
		var tilt := rad_to_deg(b.y.angle_to(Vector3.UP))
		var bad := absf(gap) > GAP_LIMIT_CM or speed > 0.05
		var name := String(p[1]) + ("" if p[2] == null else "+" + (String(p[2]) if p[2] != "" else "irons"))
		print("%s %-28s box %s  gap %+.1f cm  tilt %.0f deg  speed %.2f m/s" % ["[FAIL]" if bad else "[ok]", name, box.size, gap, tilt, speed])
		failed = failed or bad
		_label(item_node, name)
	return failed


func _label(item_node: WorldItem, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 1, 0.6)
	label.outline_size = 6
	add_child(label)
	label.global_position = item_node.action_point() + Vector3(0, 0.06, 0)


## Ground height under `at` (a ray down that only hits the world, not items).
func _ground_y(at: Vector3) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 3.0, at.z), Vector3(at.x, at.y - 6.0, at.z), 1)
	var hit := space.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else level.terrain.height_at(at.x, at.z)


## The flattest spot near `near` (8 m wide, ground heights checked on a grid).
func _flat_spot(near: Vector3) -> Vector3:
	var best := near
	var best_range := INF
	for dx in range(-60, 61, 12):
		for dz in range(-60, 61, 12):
			var lo := INF
			var hi := -INF
			for sx in range(0, 7, 2):
				for sz in range(0, 9, 2):
					var h := level.terrain.height_at(near.x + dx + sx, near.z + dz + sz)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			if hi - lo < best_range:
				best_range = hi - lo
				best = Vector3(near.x + dx, lo, near.z + dz)
	print("[items] flat spot %s, relief %.2f m" % [best, best_range])
	return best


func _shots(origin: Vector3) -> void:
	var far_z: float = rows[-1][2] + rows[-1][3]
	var mid := origin + Vector3(ROW_WIDTH_M * 0.5, 0, far_z * 0.5)
	# Standing eye height, from the front edge and from one side.
	await _shot("overview_front.png", origin + Vector3(ROW_WIDTH_M * 0.5, 1.7, -1.5), mid + Vector3(0, 0, -far_z * 0.15))
	await _shot("overview_side.png", origin + Vector3(-1.8, 1.7, far_z * 0.5), mid)
	await _shot("overview_top.png", mid + Vector3(0, 6.5, -1.0), mid)
	# Close up: a few items at a time along each row, framed on their boxes.
	var group: Array[WorldItem] = []
	var k := 0
	var last_z := INF
	for p: Array in placed:
		var node := _node(p[0])
		if node == null:
			continue
		var start_new := not group.is_empty() and (absf(node.global_position.z - last_z) > 0.6 			or node.global_position.x - group[0].global_position.x + node._box.size.x * 0.5 > 0.9)
		if start_new:
			await _group_shot(group, k)
			k += 1
			group.clear()
		group.append(node)
		last_z = node.global_position.z
	if not group.is_empty():
		await _group_shot(group, k)


## One close-up of `group`: from the front and above, far enough back to fit them all.
func _group_shot(group: Array[WorldItem], k: int) -> void:
	var box := AABB(group[0].global_position, Vector3.ZERO)
	for node in group:
		box = box.merge(AABB(node.global_position - node._box.size * 0.5, node._box.size))
	var centre := box.get_center()
	var dist := maxf(0.3, maxf(box.size.x, box.size.z) * 0.75 + box.size.y * 0.5)
	await _shot("close_%02d.png" % k, centre + Vector3(0, dist * 0.9, -dist * 0.8), centre)


func _shot(file: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := String(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else "res://screenshots/items"
	get_viewport().get_texture().get_image().save_png("%s/%s" % [out, file])
	print("[items] saved %s" % file)
