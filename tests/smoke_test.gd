extends Node3D
## Headless checks for the core systems. Run from the project folder with:
##   <voxel godot exe> --headless --path . res://tests/smoke_test.tscn
## Exits with the number of failures as the process exit code.

var failures := 0


func _ready() -> void:
	_test_item_db()
	_test_inventory()
	await _test_armor()
	await _test_voxel_world()
	await _test_ballistics()
	await _test_hands()
	_test_item_state()
	_test_ammo()
	await _test_medical()
	await _test_world_item_state()
	await _test_downed()
	print("SMOKE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_item_db() -> void:
	print("ItemDB")
	check(ItemDB.all_ids().size() >= 20, "loaded %d items" % ItemDB.all_ids().size())
	check(ItemDB.get_item(&"m4a1").slot == &"primary", "m4a1 is a primary")


func _test_inventory() -> void:
	print("Inventory")
	var inv := Inventory.new()
	add_child(inv)
	check(inv.take(&"plate_steel_l3") == 1 and inv.slots[&"plate_front"] == &"", "plate without carrier goes to pockets, not a slot")
	check(inv.take(&"plate_carrier") == 1 and inv.slots[&"vest"] == &"plate_carrier", "carrier equips to vest")
	check(inv.take(&"plate_ceramic_l4") == 1 and inv.slots[&"plate_front"] == &"plate_ceramic_l4", "plate equips once carrier is worn")
	check(inv.take(&"mag_556", 30) == 25, "only 25 mags fit without a pack (got %.2f L used)" % inv.used(&"vest"))
	check(inv.take(&"assault_pack") == 1, "pack equips")
	check(inv.take(&"mag_556", 30) == 30, "pack takes 30 more mags")
	check(inv.take(&"hvt_case") == 1 and inv.hands == &"hvt_case", "bulky case goes to hands")
	check(inv.take(&"supply_crate") == 0, "can't carry two bulky items")
	check(inv.unequip(&"vest").is_empty(), "can't drop a vest with plates in it")
	check(inv.total_mass() > 30.0, "mass adds up (%.1f kg)" % inv.total_mass())
	var copy := Inventory.new()
	copy.net_state = inv.net_state
	check(copy.slots == inv.slots and copy.hands == inv.hands, "net_state round-trips")
	copy.free()
	inv.queue_free()

	print("Inventory: carrier tiers")
	var light := Inventory.new()
	add_child(light)
	light.take(&"plate_carrier_light")
	light.take(&"plate_pe_l3", 1)
	light.take(&"plate_pe_l3", 1)
	check(light.slots[&"plate_front"] == &"plate_pe_l3" and light.slots[&"plate_back"] == &"", "light carrier takes a front plate only")
	light.queue_free()
	var heavy := Inventory.new()
	add_child(heavy)
	heavy.take(&"plate_carrier_heavy")
	for id: StringName in [&"plate_steel_l3", &"plate_steel_l3", &"plate_side", &"plate_side"]:
		heavy.take(id)
	check(heavy.slots[&"plate_back"] == &"plate_steel_l3" and heavy.slots[&"plate_left"] == &"plate_side" and heavy.slots[&"plate_right"] == &"plate_side", "heavy carrier takes front, back and side plates")
	check(heavy.carrier_plate_slots().size() == 4, "heavy carrier has 4 plate pockets")
	heavy.queue_free()


## A piece of armor worn in an Inventory (chips are recorded as the item's state).
func _armor(id: StringName, slot: StringName) -> VoxelArmor:
	var inv := Inventory.new()
	add_child(inv)
	if slot != &"helmet":
		inv.take(&"plate_carrier")
	inv.take(id)
	var piece := VoxelArmor.new()
	inv.add_child(piece)
	piece.setup(ItemDB.get_item(id), slot, inv, 1)
	inv.changed.connect(func() -> void: piece.apply_damage(inv.chips_in(slot)))
	return piece


func _test_armor() -> void:
	print("VoxelArmor: plates")
	var rifle := ItemDB.get_item(&"m4a1")
	var plate := _armor(&"plate_ceramic_l4", &"plate_front")
	check(is_equal_approx(plate.integrity(), 1.0), "new plate is intact")
	var front := Vector3(0, 0, -0.01)  # strike face; rounds travel +Z into it
	check(plate.server_try_stop(front, Vector3.BACK, rifle), "first hit stopped")
	check(plate.integrity() < 1.0, "plate chipped to %.0f%%" % (plate.integrity() * 100.0))
	check(not plate.server_try_stop(front, Vector3.BACK, rifle), "second hit on the same spot goes through")
	check(plate.server_try_stop(front + Vector3(0.08, 0.08, 0), Vector3.BACK, rifle), "hit elsewhere still stopped")
	check(plate.server_try_stop(front + Vector3(-0.08, -0.1, 0), Vector3(0.5, 0.3, 1).normalized(), rifle), "angled hit stopped")
	check(plate.inventory.chips_in(&"plate_front").size() == 3, "chips recorded in the plate's item state")
	plate.inventory.queue_free()

	print("VoxelArmor: helmets")
	var pistol := ItemDB.get_item(&"m17")
	# Light (IIA) and medium (IIIA) helmets are rated for pistol rounds, the heavy (III++) for rifles.
	for tier: Array in [[&"helmet_bump", "light", pistol], [&"helmet", "medium", pistol], [&"helmet_heavy", "heavy", rifle]]:
		var helmet := _armor(tier[0], &"helmet")
		var round: ItemData = tier[2]
		var size := VoxelArmor.size_m(ItemDB.get_item(tier[0]))
		var dome_front := Vector3(0, 0.08, -size.z * 0.5)
		check(helmet.server_try_stop(dome_front, Vector3.BACK, round), "%s: front of the dome stops a %s round" % [tier[1], round.name])
		check(helmet.server_try_stop(Vector3(0.03, size.y - (0.2 if tier[1] == "heavy" else 0.0) - 0.001, 0.02), Vector3.DOWN, round), "%s: top stops a round" % tier[1])
		if round == pistol:
			check(not helmet.server_try_stop(Vector3(-0.05, 0.1, -size.z * 0.5 + 0.01), Vector3.BACK, rifle), "%s: a 5.56 round goes through" % tier[1])
		var shots := 1
		while helmet.server_try_stop(dome_front, Vector3.BACK, round) and shots < 12:
			shots += 1
		check(shots < 12, "%s: same spot punched through after %d hits" % [tier[1], shots + 1])
		var face := Vector3(0, -0.1 if tier[1] == "heavy" else 0.02, -size.z * 0.5)
		var face_blocked := helmet.server_try_stop(face, Vector3.BACK, round)
		check(face_blocked == (tier[1] == "heavy"), "%s: face %s" % [tier[1], "covered by the visor" if tier[1] == "heavy" else "left open"])
		helmet.inventory.queue_free()
	await get_tree().process_frame

func _test_voxel_world() -> void:
	print("VoxelWorld")
	var world := VoxelWorld.new()
	add_child(world)
	world.add_box_m(Vector3(0, 0, 0), Vector3(1, 1, 0.3), VoxelWorld.Mat.CONCRETE)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 128
	add_child(viewer)
	var deadline := Time.get_ticks_msec() + 15000
	while not world.is_built() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(world.is_built(), "structures built")
	var tool := world.terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	check(tool.get_voxel(Vector3i(5, 5, 1)) == VoxelWorld.Mat.CONCRETE, "inside the box is concrete")
	check(tool.get_voxel(Vector3i(9, 9, 2)) == VoxelWorld.Mat.CONCRETE, "last voxel of the box is set")
	check(tool.get_voxel(Vector3i(10, 5, 1)) == VoxelWorld.Mat.EMPTY, "box doesn't overflow by a voxel")
	world.server_carve(world.to_global(Vector3(0.5, 0.5, 0.15)), 0.12)
	check(tool.get_voxel(Vector3i(5, 5, 1)) == VoxelWorld.Mat.EMPTY, "carve removed voxels")
	check(GameState.voxel_edits.size() == 1, "carve recorded in the edit log")
	GameState.voxel_edits.clear()
	viewer.queue_free()
	world.queue_free()
	await get_tree().process_frame
	await _test_world_materials()


## Materials: what a round does to each (VoxelWorld.trace_round), impact marks, blasts by
## material, and the log replaying the same on a fresh world (as a save or a late joiner).
func _test_world_materials() -> void:
	print("VoxelWorld materials")
	var boxes := [
		[Vector3(0, 0, 0), Vector3(1, 1, 0.3), VoxelWorld.Mat.CONCRETE],
		[Vector3(2, 0, 0), Vector3(3, 1, 0.1), VoxelWorld.Mat.WOOD],
		[Vector3(4, 0, 0), Vector3(5, 1, 0.1), VoxelWorld.Mat.SHEET_METAL],
		[Vector3(6, 0, 0), Vector3(7, 1, 1.5), VoxelWorld.Mat.WOOD],
		[Vector3(8, 0, 0), Vector3(9, 1, 0.4), VoxelWorld.Mat.SANDBAG],
	]
	var world := _material_world(boxes)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 160
	add_child(viewer)
	var deadline := Time.get_ticks_msec() + 15000
	while not world.is_built() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(world.is_built(), "materials world built")
	# The walls' collision comes a few frames after the voxels, block by block.
	var space := world.get_world_3d()
	var open := func(x: float) -> bool: return Throwables.clear_line(space, Vector3(x, 0.55, -2), Vector3(x, 0.55, 2))
	while [0.55, 2.55, 4.55, 6.55, 8.55].any(open) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var m855 := 1650.0
	var nine := 550.0
	var m80 := 3350.0
	var concrete := world.trace_round(Vector3(0.55, 0.55, 0.0), Vector3.BACK, m855 * 10.0)
	check(concrete.stopped and concrete.material == VoxelWorld.Mat.CONCRETE and concrete.voxels.is_empty(), "concrete stops even a round ten times an M855")
	var wood := world.trace_round(Vector3(2.55, 0.55, 0.0), Vector3.BACK, m855)
	check(not wood.stopped and wood.voxels.size() == 1 and absf(float(wood.lost_j) - 250.0) < 5.0 and (wood.exit as Vector3).z >= 0.099,
		"an M855 goes through a 10 cm wood wall (%d voxel, %.0f J lost, out at z %.2f)" % [wood.voxels.size(), wood.lost_j, (wood.exit as Vector3).z])
	var pistol := world.trace_round(Vector3(2.55, 0.55, 0.0), Vector3.BACK, nine)
	check(not pistol.stopped, "and so does a 9 mm (%.0f J lost)" % pistol.lost_j)
	var slant := world.trace_round(Vector3(2.55, 0.55, 0.0), Vector3(0.6, 0, 0.8), m855)
	check(not slant.stopped and float(slant.lost_j) > float(wood.lost_j) + 50.0, "at a slant it crosses more wood (%.0f J lost)" % slant.lost_j)
	var sheet := world.trace_round(Vector3(4.55, 0.55, 0.0), Vector3.BACK, nine)
	check(not sheet.stopped and absf(float(sheet.lost_j) - 150.0) < 5.0, "a 9 mm goes through sheet metal (%.0f J lost)" % sheet.lost_j)
	var stack := world.trace_round(Vector3(6.55, 0.55, 0.0), Vector3.BACK, m855)
	var stack_m80 := world.trace_round(Vector3(6.55, 0.55, 0.0), Vector3.BACK, m80)
	check(stack.stopped and stack_m80.stopped and stack.voxels.is_empty(), "1.5 m of wood stops an M855 and an M80")
	var sandbag := world.trace_round(Vector3(8.55, 0.55, 0.0), Vector3.BACK, m80)
	check(sandbag.stopped and sandbag.material == VoxelWorld.Mat.SANDBAG, "40 cm of sandbags stops an M80")
	check(not world.stops_round(Vector3(2.55, 0.55, -2), Vector3(2.55, 0.55, 2), m855) and world.stops_round(Vector3(0.55, 0.55, -2), Vector3(0.55, 0.55, 2), m855)
		and not world.stops_round(Vector3(-2, 2, -2), Vector3(-2, 2, 2), m855), "stops_round: wood doesn't, concrete does, open air doesn't")

	# Marks: small, persistent, no voxel carved; capped per voxel; gone with their voxel.
	var tool := world.terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	world.server_mark(Vector3(0.55, 0.55, 0.0), Vector3.FORWARD, VoxelWorld.Mat.CONCRETE)
	await get_tree().process_frame
	check(world.mark_count() == 1 and tool.get_voxel(Vector3i(5, 5, 0)) == VoxelWorld.Mat.CONCRETE, "a mark on concrete, nothing carved")
	check(GameState.voxel_edits.size() == 1 and GameState.voxel_edits[0].op == "mark", "the mark is in the edit log")
	check(world._mark_mesh.multimesh.instance_count == 1, "and drawn")
	for i in VoxelWorld.MARKS_PER_VOXEL + 3:
		world.server_mark(Vector3(0.51 + 0.01 * i, 0.55, 0.0), Vector3.FORWARD, VoxelWorld.Mat.CONCRETE)
	check(world.mark_count() == VoxelWorld.MARKS_PER_VOXEL, "at most %d marks per voxel (%d)" % [VoxelWorld.MARKS_PER_VOXEL, world.mark_count()])
	world.server_mark(Vector3(0.25, 0.75, 0.0), Vector3.FORWARD, VoxelWorld.Mat.CONCRETE)
	world.server_holes(wood.voxels)
	check(tool.get_voxel(Vector3i(25, 5, 0)) == VoxelWorld.Mat.EMPTY and tool.get_voxel(Vector3i(26, 5, 0)) == VoxelWorld.Mat.WOOD, "a hole is just the voxel the round passed")
	world.server_carve(Vector3(0.55, 0.55, 0.05), 0.12)
	check(world.mark_count() == 1 and world.marks_near(Vector3(0.25, 0.75, 0.0), 0.02) == 1, "carving a voxel takes its marks with it (%d left)" % world.mark_count())

	# Blasts by material: wood goes, concrete chips.
	world.server_blast(Vector3(2.5, 0.5, -0.05), 0.45)
	world.server_blast(Vector3(0.5, 0.25, -0.05), 0.45)
	check(tool.get_voxel(Vector3i(28, 5, 0)) == VoxelWorld.Mat.EMPTY and tool.get_voxel(Vector3i(22, 3, 0)) == VoxelWorld.Mat.EMPTY, "a blast takes out wood across its radius")
	check(tool.get_voxel(Vector3i(5, 2, 0)) == VoxelWorld.Mat.EMPTY and tool.get_voxel(Vector3i(8, 2, 0)) == VoxelWorld.Mat.CONCRETE
		and tool.get_voxel(Vector3i(5, 2, 2)) == VoxelWorld.Mat.CONCRETE, "and only chips concrete near its centre")

	# The log (through JSON, as saved) builds the same world again.
	var edits: Variant = JSON.parse_string(JSON.stringify(GameState.voxel_edits))
	var copy := _material_world(boxes)
	while not copy.is_built() and Time.get_ticks_msec() < deadline + 15000:
		await get_tree().process_frame
	copy.load_edits(edits)
	await get_tree().process_frame
	var copy_tool := copy.terrain.get_voxel_tool()
	copy_tool.channel = VoxelBuffer.CHANNEL_COLOR
	var same := true
	for v: Vector3i in [Vector3i(25, 5, 0), Vector3i(26, 5, 0), Vector3i(28, 5, 0), Vector3i(5, 2, 0), Vector3i(8, 2, 0), Vector3i(5, 5, 0), Vector3i(5, 5, 2)]:
		same = same and copy_tool.get_voxel(v) == tool.get_voxel(v)
	check(same and copy.mark_count() == world.mark_count() and copy._mark_mesh.multimesh.instance_count == world.mark_count(),
		"the saved log replays the same holes, blasts and marks (%d marks)" % copy.mark_count())
	GameState.voxel_edits.clear()
	viewer.queue_free()
	world.queue_free()
	copy.queue_free()
	await get_tree().process_frame


func _material_world(boxes: Array) -> VoxelWorld:
	var world := VoxelWorld.new()
	add_child(world)
	for box: Array in boxes:
		world.add_box_m(box[0], box[1], box[2])
	return world


func _test_ballistics() -> void:
	print("Ballistics")
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	# The heavy carrier covers neck, face and arms, so the steel plate's spall hurts nobody.
	dummy.loadout = PackedStringArray(["plate_carrier_heavy", "plate_steel_l3"])
	add_child(dummy)
	var shooter := StaticBody3D.new()
	var plate_y: float = GearRig.plate_rest_position(&"plate_front").y
	shooter.position = Vector3(0, plate_y, -5)  # dummy faces -Z, so stand in front of it
	add_child(shooter)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rifle := ItemDB.get_item(&"m4a1")
	var aim := Vector3(0, plate_y, 0) - shooter.position
	var first := Ballistics.fire(shooter, shooter.position, aim.normalized(), rifle)
	check(first.result == "plate", "first shot hits the plate (%s)" % first.result)
	# A stopped round can still crack a rib (impact), but makes no wound of its own.
	check(dummy.vitals.wound_list().all(func(w: Dictionary) -> bool: return w.kind == "rib"), "plate protected the body")
	var second := Ballistics.fire(shooter, shooter.position, aim.normalized(), rifle)
	check(second.result == "body", "second shot through the hole hits the body (%s)" % second.result)
	check(not dummy.vitals.wound_list().is_empty(), "body was wounded (%s)" % dummy.vitals.condition_text())
	var low := Ballistics.fire(shooter, shooter.position, (Vector3(0, 0.45, 0) - shooter.position).normalized(), rifle)
	check(low.result == "body", "shot below the plate hits the body")
	dummy.queue_free()

	print("Ballistics: helmet and headshots")
	dummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.loadout = PackedStringArray(["helmet"])
	add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	shooter.position = Vector3(0, 1.73, -5)
	var dome := Ballistics.fire(shooter, shooter.position, Vector3.BACK, ItemDB.get_item(&"m17"))
	check(dome.result == "plate" and dummy.vitals.wound_list().is_empty() and dummy.vitals.is_up(), "helmet stopped a pistol round to the forehead (%s)" % dome.result)
	check(dummy.gear.armor_integrity(&"helmet") >= 0.0 and dummy.gear.armor_integrity(&"helmet") < 1.0, "helmet chipped to %.0f%%" % (dummy.gear.armor_integrity(&"helmet") * 100.0))
	shooter.position = Vector3(0, 1.58, -5)
	var face := Ballistics.fire(shooter, shooter.position, Vector3.BACK, rifle)
	check(face.result == "body" and dummy.vitals.is_dead(), "a rifle round through the face reaches the brain (%s, %s)" % [face.result, dummy.vitals.condition_text()])
	dummy.queue_free()
	shooter.queue_free()


func _test_hands() -> void:
	print("Hands (elbow IK)")
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.loadout = PackedStringArray(["m110", "m17", "plate_carrier"])
	add_child(dummy)
	var model: CharacterModel = dummy.get_node(^"Model")
	await get_tree().process_frame
	check(model.hand_error() < 0.0, "nothing held at rest")
	for pose: Array in [[CharacterModel.Hold.BOTH, "rifle", 0.0], [CharacterModel.Hold.BOTH, "rifle aimed up", 0.6],
			[CharacterModel.Hold.BOTH, "rifle aimed down", -0.6], [CharacterModel.Hold.RIGHT, "pistol", 0.0]]:
		model.hold = pose[0]
		model.look_pitch = pose[2]
		for i in 3:
			await get_tree().process_frame
		var error := model.hand_error()
		check(error >= 0.0 and error < 0.015, "%s: palms on grip points (off by %.1f cm)" % [pose[1], error * 100.0])
	model.hold = CharacterModel.Hold.NONE
	await get_tree().process_frame
	await get_tree().process_frame
	check(model.hand_error() < 0.0, "weapon back on the sling/holster")
	dummy.queue_free()

func _test_item_state() -> void:
	print("Item state")
	var inv := Inventory.new()
	add_child(inv)
	inv.take(&"plate_carrier")
	inv.take(&"plate_ceramic_l4")
	inv.add_chip(&"plate_front", [12, 15, 0, 2.6])
	var removed := inv.unequip(&"plate_front")
	check(removed.id == &"plate_ceramic_l4" and removed.state.chips.size() == 1, "unequipped plate keeps its chips")
	var other := Inventory.new()
	add_child(other)
	other.take(&"plate_carrier")
	other.take(removed.id, 1, removed.state)
	check(other.chips_in(&"plate_front").size() == 1, "damage comes back when someone else picks it up")
	other.take(&"assault_pack")
	other.take(&"plate_ceramic_l4", 1, {"chips": [[1, 1, 0, 2.0]]})
	check(other.chips_in(&"plate_back").size() == 1, "a damaged plate fills the free back pocket")
	check(other.take(&"plate_ceramic_l4", 1, {"chips": [[2, 2, 0, 2.0]]}) == 1, "another damaged plate is stowed")
	check(other.take(&"plate_ceramic_l4") == 1, "an undamaged one too")
	var entries: Array = other.containers[&"vest"] + other.containers[&"pockets"] + other.containers[&"backpack"]
	var plates := entries.filter(func(e: Dictionary) -> bool: return e.id == &"plate_ceramic_l4")
	check(plates.size() == 2, "damaged and undamaged plates don't stack (%d entries)" % plates.size())
	var mags := Inventory.new()
	add_child(mags)
	mags.take(&"plate_carrier")
	mags.take(&"mag_556", 3)
	check(mags.insert_entry(&"pockets", mags.remove_entry(&"vest", 0, 3)), "move 3 mags vest -> pockets")
	check(mags.containers[&"pockets"][0].count == 3 and mags.containers[&"vest"].is_empty(), "moved as one stack")
	check(not mags.insert_entry(&"pockets", {"id": &"plate_carrier", "count": 1}), "a carrier doesn't fit in a pocket")
	var copy := Inventory.new()
	copy.net_state = other.net_state
	check(copy.chips_in(&"plate_front").size() == 1, "item state replicates in net_state")
	copy.free()
	# A body's gear goes through the zone save as JSON (GameState.bodies) and comes back the same.
	mags.take(&"m4a1")
	mags.consume_round(&"primary")
	mags.take(&"plate_ceramic_l4", 1, {"chips": [[3, 4, 0, 0.1 + 0.2]]})  # a float that needs 17 digits
	var restored := Inventory.new()
	restored.net_state = GameState.from_json(JSON.parse_string(JSON.stringify(mags.net_state, "", true, true)))
	check(restored.rounds_in(&"primary") == 29 and typeof(restored.state_of(&"primary").rounds) == TYPE_INT
		and restored.chips_in(&"plate_front").size() == 1 and restored.count_of(&"mag_556") == 3,
		"a body's gear survives the zone save's JSON: rounds, chips and stacks")
	check(restored.state_of(&"plate_front") == mags.state_of(&"plate_front"), "plate state comes back exactly, at full precision (%s)" % [restored.state_of(&"plate_front")])
	restored.insert_entry(&"pockets", {"id": &"mag_556", "count": 1})
	check(restored.containers[&"pockets"].size() == 1 and restored.containers[&"pockets"][0].count == 4,
		"and magazines stack again after loading (%s)" % [restored.containers[&"pockets"]])
	restored.free()
	for node in [inv, other, mags]:
		node.queue_free()


func _test_ammo() -> void:
	print("Ammo and reloading")
	var inv := Inventory.new()
	add_child(inv)
	inv.take(&"plate_carrier")
	inv.take(&"m4a1")
	check(inv.rounds_in(&"primary") == 30, "new rifle comes loaded with 30")
	for i in 30:
		inv.consume_round(&"primary")
	check(inv.rounds_in(&"primary") == 0 and not inv.consume_round(&"primary"), "empty after 30, then won't fire")
	check(inv.reload(&"primary") == -1, "no reload without magazines")
	inv.take(&"mag_556", 2)
	check(inv.spare_rounds(&"mag_556") == 60, "two spare mags = 60 rounds")
	check(inv.reload(&"primary") == 30 and inv.spare_rounds(&"mag_556") == 30, "reload loads 30 (the empty mag goes back in the pouch)")
	for i in 12:
		inv.consume_round(&"primary")
	check(inv.reload(&"primary") == 30, "tactical reload loads a full mag")
	check(inv.spare_rounds(&"mag_556") == 18, "the 18-round mag went back into the vest")
	check(inv.reload(&"primary") == -1, "won't swap a full mag for a partial one")
	inv.take(&"m17")
	check(inv.rounds_in(&"sidearm") == 17 and inv.reload(&"sidearm") == -1, "pistol uses its own ammo type")
	inv.queue_free()


func _test_medical() -> void:
	print("Medical")
	var vitals := Vitals.new()
	add_child(vitals)
	vitals.server_damage(20.0)
	# A pistol round through the outside of the left thigh: a plain muscle wound.
	vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.PISTOL, "position": Vector3(-0.12, 0.7, -0.1), "direction": Vector3.BACK})
	var wounds := vitals.wound_list()
	check(wounds.size() == 1 and wounds[0].kind == "muscle" and wounds[0].bleeding, "a bleeding muscle wound (%s)" % [wounds])
	var tasks := vitals.care_needed()
	check(not tasks.is_empty() and tasks[0].item == &"pressure_bandage" and tasks[0].part == Vitals.THIGH_L, "care_needed asks for a pressure bandage on the left thigh (%s)" % [tasks])
	var blood := vitals.blood_fraction()
	check(vitals.server_apply_treatment(&"pressure_bandage", Vitals.THIGH_L), "a pressure bandage goes on")
	check(not vitals.wound_list()[0].bleeding and vitals.wound_list()[0].treated, "and stops the bleeding")
	check(not vitals.server_apply_treatment(&"pressure_bandage", Vitals.THIGH_L), "a second one has nothing to do")
	check(not vitals.care_needed().any(func(t: Dictionary) -> bool: return t.item == &"pressure_bandage"), "and isn't asked for")
	check(vitals.blood_fraction() >= blood - 0.0001 and vitals.blood_fraction() <= 1.0 - 20.0 * Vitals.TRAUMA_BLOOD_PER_DAMAGE + 0.0001, "but puts no blood back (%.3f)" % vitals.blood_fraction())
	vitals.queue_free()


func _test_world_item_state() -> void:
	print("World items carry state")
	var item := WorldItem.new()
	item.item_id = &"helmet"
	item.state = {"chips": [[17, 8, 0, 1.6], [10, 10, 2, 1.6]]}
	add_child(item)
	await get_tree().process_frame
	var piece: VoxelArmor = item.find_children("*", "VoxelArmor", false, false)[0]
	check(piece.integrity() < 1.0, "dropped helmet shows its damage on the ground (%.0f%%)" % (piece.integrity() * 100.0))
	check(piece.collision_layer == 0, "ground armor isn't a hit target")
	check(item.describe().contains("damaged: 2 hits"), "prompt says it's damaged")
	item.queue_free()

func _test_downed() -> void:
	print("Downed, coming round, cardiac arrest")
	var vitals := Vitals.new()
	add_child(vitals)
	var events: Array[String] = []
	vitals.went_down.connect(func() -> void: events.append("down"))
	vitals.woke.connect(func() -> void: events.append("woke"))
	vitals.died.connect(func() -> void: events.append("died"))
	vitals.server_damage(40.0)
	check(vitals.is_up() and events.is_empty(), "K once (24%% blood lost) keeps you up (%s)" % vitals.condition_text())
	vitals.server_damage(40.0)
	check(vitals.downed and not vitals.in_cardiac_arrest() and events == ["down"], "K twice (48%% lost) knocks you out (%s)" % vitals.condition_text())
	check(vitals.seconds_to_death() < 0.0 and not vitals.is_up(), "unconscious, not dying yet")
	check(vitals.care_needed().any(func(t: Dictionary) -> bool: return t.item == &"npa" and t.kind == "airway"), "unconscious: care_needed asks for an NPA airway")
	vitals.server_advance(60.0)
	check(vitals.downed and vitals.why_unconscious().has(&"blood") and events == ["down"], "48%% lost stays out: no revive, no blood back until IV (%s)" % [vitals.why_unconscious()])
	var knocked := Vitals.new()
	add_child(knocked)
	knocked.woke.connect(func() -> void: events.append("woke"))
	knocked.server_impact(Vitals.HEAD, Vitals.FULL_POWER, 400.0)
	knocked.server_impact(Vitals.HEAD, Vitals.FULL_POWER, 400.0)  # two helmet stops: knocked out by the pain
	knocked.server_advance(1.0)
	knocked.server_apply_treatment(&"npa", Vitals.HEAD)
	knocked.server_apply_treatment(&"morphine", Vitals.TORSO)
	knocked.server_advance(WoundModel.MORPHINE_ABSORB_S + 25.0)
	check(knocked.is_up() and events.back() == "woke", "knocked out by pain, morphine eases it and he comes round on his own (%s)" % knocked.condition_text())
	knocked.queue_free()
	vitals.server_damage(100.0)
	check(vitals.in_cardiac_arrest() and absf(vitals.seconds_to_death() - Vitals.ARREST_WINDOW_S) < 1.0, "50%% lost: cardiac arrest, %d s window" % vitals.seconds_to_death())
	vitals.server_damage(10.0)
	check(vitals.downed and not vitals.is_dead(), "a hit while down is just another wound")
	vitals.server_advance(Vitals.ARREST_WINDOW_S + 1.0)
	check(events.back() == "died" and vitals.is_dead() and not vitals.downed, "no heart rate when the window runs out: dead")
	var quick := Vitals.new()
	quick.can_go_down = false
	add_child(quick)
	var died := [false]
	quick.died.connect(func() -> void: died[0] = true)
	quick.server_damage(200.0)
	check(died[0] and not quick.downed, "can_go_down = false skips the downed state")
	vitals.queue_free()
	quick.queue_free()