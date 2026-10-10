extends Node
## Headless checks for world materials in the real compound: rounds through the wooden shed
## and the sheet-metal container hit whoever is behind, concrete stops them with a small
## mark and no hole, a deep wood stack stops them, frags only chip concrete, the marks are
## saved with the zone, and cover that only hides you is told apart from cover that stops
## rounds.
##   <voxel godot exe> --headless --path . res://tests/materials_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var shooter: StaticBody3D
var world: VoxelWorld


func _ready() -> void:
	GameState.zone_id = "test_materials" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	world = level.voxel_world
	shooter = StaticBody3D.new()
	shooter.collision_layer = 0
	level.add_child(shooter)
	await _wait_for_collision()
	_test_layout()
	await _test_thin_walls()
	await _test_concrete()
	await _test_wood_stack()
	await _test_frags()
	_test_cover()
	_test_saved()
	GameState.delete_save()
	print("MATERIALS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The walls' collision comes a few frames after the voxels, block by block.
func _wait_for_collision() -> void:
	var lines := [[Vector3(17.5, 1.3, -3), Vector3(17.5, 1.3, -8)], [Vector3(17.5, 1.3, -8), Vector3(17.5, 1.3, -13)],
		[Vector3(-17.3, 1.3, 3), Vector3(-17.3, 1.3, 9)], [Vector3(-3, 1.3, 2), Vector3(-3, 1.3, -5)],
		[Vector3(-16, 0.5, -10.5), Vector3(-12, 0.5, -10.5)], [Vector3(5, 1.0, -18), Vector3(5, 1.0, -21)]]
	var deadline := Time.get_ticks_msec() + 15000
	var space := player.get_world_3d()
	while lines.any(func(l: Array) -> bool: return Throwables.clear_line(space, l[0], l[1])) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _test_layout() -> void:
	print("The compound's materials")
	var M := VoxelWorld.Mat
	var expect := [
		[Vector3(0, 1, -19.85), M.CONCRETE, "perimeter wall"],
		[Vector3(-4.85, 1, -8), M.PAINTED, "main building"],
		[Vector3(-7.5, 0.5, 6.2), M.SANDBAG, "sandbag wall"],
		[Vector3(-12.5, 0.5, -10.5), M.WOOD, "crates"],
		[Vector3(17.5, 1, -7.05), M.WOOD, "shed wall"],
		[Vector3(17.5, 2.45, -9), M.SHEET_METAL, "shed roof"],
		[Vector3(-17.3, 1, 8.05), M.SHEET_METAL, "container wall"],
	]
	for e: Array in expect:
		check(world.material_at(e[0]) == e[1], "%s: %s" % [e[2], VoxelWorld.MATERIALS[e[1]].name])


func _dummy(pos: Vector3) -> TargetDummy:
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.respawn_seconds = 999.0
	level.add_child(dummy)
	dummy.global_position = pos
	return dummy


func _fire(from: Vector3, to: Vector3, weapon: StringName) -> Dictionary:
	shooter.global_position = from
	return Ballistics.fire(shooter, from, (to - from).normalized(), ItemDB.get_item(weapon))


func _test_thin_walls() -> void:
	print("Wood and sheet metal: rounds go through")
	var outside := _dummy(Vector3(17.0, 0, -13))  # north of the shed
	var inside := _dummy(Vector3(18.6, 0, -9))
	var boxed := _dummy(Vector3(-17.3, 0, 11))  # in the container
	await get_tree().physics_frame
	await get_tree().physics_frame
	var edits := GameState.voxel_edits.size()
	var decals := world.bullet_hole_count()
	var through := _fire(Vector3(17.05, 1.35, -3), Vector3(17.05, 1.35, -13), &"m4a1")
	check(through.result == "body" and not outside.vitals.wound_list().is_empty(),
		"an M4 round goes through both plank walls of the shed into a man behind it (%s, %s)" % [through.result, outside.vitals.condition_text()])
	check(world.bullet_hole_count() == decals + 4, "a calibre-sized bullet hole in and out of each wall (%d)" % (world.bullet_hole_count() - decals))
	check(world.material_at(Vector3(17.05, 1.35, -7.05)) == VoxelWorld.Mat.WOOD and world.material_at(Vector3(17.05, 1.35, -10.95)) == VoxelWorld.Mat.WOOD
		and world.holes_through(Vector3(17.05, 1.35, -7.05)) == 1 and world.holes_through(Vector3(17.05, 1.35, -10.95)) == 1,
		"no whole 10 cm voxel knocked out: the planks are still there, one round through each")
	var ops := GameState.voxel_edits.slice(edits).map(func(e: Dictionary) -> String: return e.op)
	check(ops == ["shot", "shot"], "two shots in the edit log (%s)" % [ops])
	var hole_size := float(GameState.voxel_edits[-1].d) * VoxelWorld.HOLE_DECAL_SCALE
	check(absf(float(GameState.voxel_edits[-1].d) - 0.0057) < 0.0001 and hole_size < 0.02, "the hole's core is the 5.56's diameter (%.1f mm), the decal %.1f cm" % [float(GameState.voxel_edits[-1].d) * 1000.0, hole_size * 100.0])
	for i in VoxelWorld.HOLES_TO_BREAK[VoxelWorld.Mat.WOOD] - 1:
		_fire(Vector3(17.05, 1.35, -3), Vector3(17.05, 1.35, -6), &"m4a1")
	check(world.material_at(Vector3(17.05, 1.35, -7.05)) == VoxelWorld.Mat.EMPTY and world.material_at(Vector3(17.25, 1.35, -7.05)) == VoxelWorld.Mat.WOOD,
		"%d rounds through one plank break that voxel out, and only that one" % VoxelWorld.HOLES_TO_BREAK[VoxelWorld.Mat.WOOD])
	var pistol := _fire(Vector3(18.65, 1.35, -3), Vector3(18.65, 1.35, -9), &"m17")
	check(pistol.result == "body" and not inside.vitals.wound_list().is_empty(), "a 9 mm through one plank wall hits a man inside (%s)" % pistol.result)
	var container := _fire(Vector3(-17.25, 1.35, 3), Vector3(-17.25, 1.35, 11), &"m17")
	check(container.result == "body" and not boxed.vitals.wound_list().is_empty(), "a 9 mm through the container's sheet metal hits a man inside (%s)" % container.result)
	check(world.material_at(Vector3(-17.25, 1.35, 8.05)) != VoxelWorld.Mat.EMPTY and world.holes_through(Vector3(-17.25, 1.35, 8.05)) == 1, "leaving a bullet hole in the sheet metal, not a missing voxel")
	check(Throwables.clear_line(player.get_world_3d(), Vector3(17.3, 1.8, -3), Vector3(17.3, 1.8, -8)) == false, "the shed wall still blocks sight")
	for d in [outside, inside, boxed]:
		d.queue_free()
	await get_tree().process_frame


func _test_concrete() -> void:
	print("Concrete: stops rounds, small marks, no holes")
	var behind := _dummy(Vector3(-3, 0, -6))  # inside the main building
	await get_tree().physics_frame
	await get_tree().physics_frame
	var edits := GameState.voxel_edits.size()
	var marks := world.mark_count()
	for weapon: StringName in [&"m4a1", &"m110", &"m17"]:
		var hit := _fire(Vector3(-2.95, 1.35, 2), Vector3(-2.95, 1.35, -6), weapon)
		check(hit.result == "world" and absf((hit.position as Vector3).z + 4.0) < 0.05 and behind.vitals.wound_list().is_empty(),
			"%s: stopped at the wall's face (%s at z %.2f), nobody hurt behind it" % [weapon, hit.result, (hit.position as Vector3).z])
	check(world.material_at(Vector3(-2.95, 1.35, -4.05)) == VoxelWorld.Mat.PAINTED, "no hole: the wall voxel is still there")
	check(world.mark_count() == marks + 3 and world.marks_near(Vector3(-2.95, 1.35, -4), 0.05) == 3, "three small marks where they hit (%d)" % world.marks_near(Vector3(-2.95, 1.35, -4), 0.05))
	var ops := GameState.voxel_edits.slice(edits).map(func(e: Dictionary) -> String: return e.op)
	check(ops == ["mark", "mark", "mark"], "only marks in the edit log (%s)" % [ops])
	check(VoxelWorld.MARK_SIZE_M < VoxelWorld.VOXEL_SIZE * 0.6, "a mark is %.0f cm across, well under a voxel" % (VoxelWorld.MARK_SIZE_M * 100.0))
	# Sustained fire on one spot: the log doesn't grow past MARKS_PER_VOXEL there.
	for i in 20:
		_fire(Vector3(-2.95, 1.35, 2), Vector3(-2.95, 1.35, -6), &"m4a1")
	check(world.marks_near(Vector3(-2.95, 1.35, -4), 0.1) <= VoxelWorld.MARKS_PER_VOXEL * 2, "20 more rounds on one spot add few marks (%d)" % world.marks_near(Vector3(-2.95, 1.35, -4), 0.1))
	var perimeter := _fire(Vector3(8.05, 1.35, -15), Vector3(8.05, 1.35, -25), &"m110")
	check(perimeter.result == "world" and world.material_at(Vector3(8.05, 1.35, -19.75)) == VoxelWorld.Mat.CONCRETE, "the perimeter wall stops an M110 round too")
	behind.queue_free()
	await get_tree().process_frame


func _test_wood_stack() -> void:
	print("A deep stack of wood stops a round")
	var behind := _dummy(Vector3(-9, 0, -10.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var marks := world.mark_count()
	var hit := _fire(Vector3(-16, 0.55, -10.45), Vector3(-9, 0.55, -10.45), &"m110")
	check(hit.result == "world" and absf((hit.position as Vector3).x + 13.0) < 0.05 and behind.vitals.wound_list().is_empty(),
		"2 m of crates stop an M110 round (%s at x %.2f)" % [hit.result, (hit.position as Vector3).x])
	check(world.mark_count() == marks + 1 and world.material_at(Vector3(-12.95, 0.55, -10.45)) == VoxelWorld.Mat.WOOD, "with a mark, not a hole")
	behind.queue_free()
	await get_tree().process_frame


func _test_frags() -> void:
	print("Frags: concrete chips, wood goes")
	var begin := Vector3i(40, 0, -200)  # the north perimeter wall around x = 5
	var size := Vector3i(20, 10, 3)
	var before := world.solid_voxels(begin, size).count(1)
	var edits := GameState.voxel_edits.size()
	Throwables.server_detonate(level, "frag", Vector3(5, 0.05, -19.65))
	var after := world.solid_voxels(begin, size).count(1)
	check(GameState.voxel_edits.size() == edits + 1 and GameState.voxel_edits.back().op == "blast", "a frag is one blast in the edit log")
	check(after < before and before - after < 30, "a frag against the concrete wall chips it a little (%d of %d voxels)" % [before - after, before])
	check(world.material_at(Vector3(5.05, 0.05, -19.95)) == VoxelWorld.Mat.CONCRETE and world.material_at(Vector3(5.05, 0.05, -19.85)) == VoxelWorld.Mat.CONCRETE,
		"but doesn't hole it")
	Throwables.server_detonate(level, "frag", Vector3(17.5, 0.05, -6.85))
	check(world.material_at(Vector3(17.55, 0.15, -7.05)) == VoxelWorld.Mat.EMPTY and world.material_at(Vector3(17.75, 0.25, -7.05)) == VoxelWorld.Mat.EMPTY,
		"one against the shed's plank wall blows a hole in it")


func _test_cover() -> void:
	print("Cover: concrete and sandbags stop rounds, wood and sheet metal only hide you")
	var m855 := 1650.0
	check(VoxelWorld.stops_round_in(level, Vector3(-3, 1.5, 2), Vector3(-3, 0.9, -6), m855), "the main building's wall")
	check(VoxelWorld.stops_round_in(level, Vector3(-7.5, 1.0, 10), Vector3(-7.5, 0.6, 5), m855), "the sandbag wall")
	check(not VoxelWorld.stops_round_in(level, Vector3(18.0, 1.5, 2), Vector3(18.0, 0.9, -9), m855), "not the shed's planks")
	check(not VoxelWorld.stops_round_in(level, Vector3(-17.0, 1.5, 2), Vector3(-17.0, 0.9, 11), m855), "not the container's sheet metal")
	check(VoxelWorld.stops_round_in(level, Vector3(-16, 0.5, -10.5), Vector3(-9, 0.5, -10.5), m855), "the crate stack")


func _test_saved() -> void:
	print("Marks and holes are saved with the zone")
	var marks := GameState.voxel_edits.filter(func(e: Dictionary) -> bool: return e.op == "mark").size()
	var holes := GameState.voxel_edits.filter(func(e: Dictionary) -> bool: return e.op == "shot").size()
	GameState.save_zone()
	GameState.load_zone()
	var saved_marks := GameState.voxel_edits.filter(func(e: Dictionary) -> bool: return e.op == "mark").size()
	var saved_holes := GameState.voxel_edits.filter(func(e: Dictionary) -> bool: return e.op == "shot").size()
	check(holes > 0, "there are bullet holes to save (%d)" % holes)
	check(marks > 0 and saved_marks == marks and saved_holes == holes, "the save holds %d marks and %d holes (%d, %d)" % [marks, holes, saved_marks, saved_holes])
