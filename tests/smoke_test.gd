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
	check(inv.unequip(&"vest") == &"", "can't drop a vest with plates in it")
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


func _armor(id: StringName, slot: StringName) -> VoxelArmor:
	var vitals := Vitals.new()
	add_child(vitals)
	var piece := VoxelArmor.new()
	vitals.add_child(piece)
	piece.setup(ItemDB.get_item(id), slot, vitals, 1)
	vitals.changed.connect(func() -> void: piece.apply_damage(vitals.plate_damage.get(slot, [])))
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
	plate.vitals.queue_free()

	print("VoxelArmor: helmets")
	for tier: Array in [[&"helmet_bump", "light"], [&"helmet", "medium"], [&"helmet_heavy", "heavy"]]:
		var helmet := _armor(tier[0], &"helmet")
		var size := VoxelArmor.size_m(ItemDB.get_item(tier[0]))
		var dome_front := Vector3(0, 0.08, -size.z * 0.5)
		check(helmet.server_try_stop(dome_front, Vector3.BACK, rifle), "%s: front of the dome stops a round" % tier[1])
		check(helmet.server_try_stop(Vector3(0.03, size.y - (0.2 if tier[1] == "heavy" else 0.0) - 0.001, 0.02), Vector3.DOWN, rifle), "%s: top stops a round" % tier[1])
		var shots := 1
		while helmet.server_try_stop(dome_front, Vector3.BACK, rifle) and shots < 12:
			shots += 1
		check(shots < 12, "%s: same spot punched through after %d hits" % [tier[1], shots + 1])
		var face := Vector3(0, -0.1 if tier[1] == "heavy" else 0.02, -size.z * 0.5)
		var face_blocked := helmet.server_try_stop(face, Vector3.BACK, rifle)
		check(face_blocked == (tier[1] == "heavy"), "%s: face %s" % [tier[1], "covered by the visor" if tier[1] == "heavy" else "left open"])
		helmet.vitals.queue_free()
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


func _test_ballistics() -> void:
	print("Ballistics")
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.loadout = PackedStringArray(["plate_carrier", "plate_steel_l3"])
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
	check(dummy.vitals.health == dummy.vitals.max_health, "plate protected the body")
	var second := Ballistics.fire(shooter, shooter.position, aim.normalized(), rifle)
	check(second.result == "body", "second shot through the hole hits the body (%s)" % second.result)
	check(dummy.vitals.health < dummy.vitals.max_health, "body took damage (%d HP)" % dummy.vitals.health)
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
	var dome := Ballistics.fire(shooter, shooter.position, Vector3.BACK, rifle)
	check(dome.result == "plate" and dummy.vitals.health == dummy.vitals.max_health, "helmet stopped a round to the forehead (%s)" % dome.result)
	check(dummy.gear.armor_integrity(&"helmet") >= 0.0 and dummy.gear.armor_integrity(&"helmet") < 1.0, "helmet chipped to %.0f%%" % (dummy.gear.armor_integrity(&"helmet") * 100.0))
	shooter.position = Vector3(0, 1.58, -5)
	var face := Ballistics.fire(shooter, shooter.position, Vector3.BACK, rifle)
	check(face.result == "body" and dummy.vitals.health <= 0.0, "shot to the face is a x3 headshot (%s, %d HP)" % [face.result, dummy.vitals.health])
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