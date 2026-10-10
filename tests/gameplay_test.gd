extends Node
## Headless end-to-end checks: hosts a real session and drives the host player through the
## same RPCs a client would send (fire, reload, heal, inventory actions, drop and pick up).
##   <voxel godot exe> --headless --path . res://tests/gameplay_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_gameplay"  # never touch a real save
	CompoundLevel.spawn_ai = false  # squad AI has its own test
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	await _frames(30)
	await _test_firing_and_reload()
	await _test_medical()
	await _test_inventory_actions()
	await _test_drop_and_pickup_keep_state()
	await _test_spread()
	await _test_revive_and_downed()
	await _test_throwables()
	GameState.delete_save()
	print("GAMEPLAY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_firing_and_reload() -> void:
	print("Firing and reloading (RPC)")
	var inv := player.inventory
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		inv.take(id)
	inv.take(&"mag_556", 2)
	var aim := -player.global_basis.z
	for i in 3:
		player._server_fire.rpc_id(1, player.head.global_position, aim, &"primary")
		await _seconds(0.12)
	check(inv.rounds_in(&"primary") == 27, "3 shots fired: 27 left (%d)" % inv.rounds_in(&"primary"))
	player._server_reload.rpc_id(1, &"primary")
	player._server_fire.rpc_id(1, player.head.global_position, aim, &"primary")
	check(inv.rounds_in(&"primary") == 27, "can't fire mid-reload")
	await _seconds(2.6)
	check(inv.rounds_in(&"primary") == 30, "reload finished: 30 loaded")
	check(inv.spare_rounds(&"mag_556") == 57, "spare: one full mag + the 27-round one (%d)" % inv.spare_rounds(&"mag_556"))


func _test_medical() -> void:
	print("Medical (RPC)")
	player.inventory.take(&"ifak")
	player.vitals.server_damage(50.0)
	player._server_use_medical.rpc_id(1)
	check(player.vitals.is_healing(), "IFAK applied")
	check(player.inventory.count_of(&"ifak") == 0, "IFAK used up")
	await _seconds(4.4)
	check(is_equal_approx(player.vitals.health, 85.0), "healed 35 over time (%.1f)" % player.vitals.health)
	player._server_use_medical.rpc_id(1)  # no more kits: nothing happens
	check(is_equal_approx(player.vitals.health, 85.0) and not player.vitals.is_healing(), "nothing to use without a kit")


func _test_inventory_actions() -> void:
	print("Inventory screen actions (RPC)")
	var inv := player.inventory
	var vest_mags := _count(inv, &"vest", &"mag_556")
	player._server_inventory_action.rpc_id(1, "move_entry", &"vest", 0, &"", &"pockets")
	check(_count(inv, &"pockets", &"mag_556") > 0 and _count(inv, &"vest", &"mag_556") < vest_mags, "moved a mag stack vest -> pockets")
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"helmet", &"")
	check(inv.slots[&"helmet"] == &"helmet", "helmet won't stow without room (stays on)")
	inv.take(&"assault_pack")
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"helmet", &"")
	check(inv.slots[&"helmet"] == &"" and _count(inv, &"backpack", &"helmet") == 1, "helmet stowed in the backpack")
	var index := _index_of(inv, &"backpack", &"helmet")
	player._server_inventory_action.rpc_id(1, "equip_entry", &"backpack", index, &"", &"")
	check(inv.slots[&"helmet"] == &"helmet", "and equipped again from the backpack")
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"vest", &"")
	check(inv.slots[&"vest"] == &"plate_carrier", "can't drop a carrier with mags in it")


func _test_drop_and_pickup_keep_state() -> void:
	print("Drop and pick up keep item state (RPC)")
	var inv := player.inventory
	for i in 5:
		inv.consume_round(&"primary")
	inv.add_chip(&"helmet", [17, 10, 0, 1.6])
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"primary", &"")
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"helmet", &"")
	await _frames(2)
	var rifle := _world_item(&"m4a1")
	var helmet := _world_item(&"helmet")
	check(rifle != null and int(rifle.state.get("rounds", -1)) == 25, "dropped rifle keeps its 25 rounds")
	check(helmet != null and helmet.state.get("chips", []).size() == 1, "dropped helmet keeps its damage")
	check(GameState.dropped.size() == 2, "both drops recorded for saving")
	for item: WorldItem in [rifle, helmet]:
		item.global_position = player.global_position + Vector3(0, 0.5, -0.6)
		player._server_interact.rpc_id(1, item.get_path())
	await _frames(2)
	check(inv.rounds_in(&"primary") == 25, "picked-up rifle still has 25")
	check(inv.chips_in(&"helmet").size() == 1, "picked-up helmet still damaged")
	check(GameState.dropped.is_empty(), "picked-up drops removed from the save")


func _test_spread() -> void:
	print("Spread and aiming")
	var weapon := ItemDB.get_item(&"m4a1")
	var forward := -player.head.global_basis.z
	var hip := 0.0
	var aimed := 0.0
	for i in 200:
		player.is_aiming = false
		hip = maxf(hip, rad_to_deg(forward.angle_to(player._spread_direction(weapon))))
		player.is_aiming = true
		aimed = maxf(aimed, rad_to_deg(forward.angle_to(player._spread_direction(weapon))))
	player.is_aiming = false
	check(hip > 0.3 and hip <= 1.2 * 2.5 + 0.01, "hip-fire stays inside the cone (max %.2f deg)" % hip)
	check(aimed < hip * 0.3, "aiming tightens it (max %.2f deg)" % aimed)


func _test_revive_and_downed() -> void:
	print("Downed and revive (RPC)")
	var dummy: TargetDummy = level.get_node(^"Dummies/MediumDummy")
	dummy.respawn_seconds = 999.0  # don't get up on its own during the test
	dummy.vitals.server_damage(500.0)
	await _frames(2)
	check(dummy.vitals.downed and dummy.model.downed, "dummy is down and lying down")
	var hitbox: Area3D = dummy.get_node(^"Hitbox")
	check(absf(hitbox.rotation.x + PI / 2) < 0.01, "its hitbox lies down with it")
	player.global_position = dummy.global_position + Vector3(0, 0, -1.2)
	await _frames(2)
	player._server_revive.rpc_id(1, dummy.get_path())
	check(player.inventory.count_of(&"ifak") == 0, "no kit, no revive")
	player.inventory.take(&"ifak")
	player._server_revive.rpc_id(1, dummy.get_path())
	await _seconds(5.3)
	check(dummy.vitals.is_up() and is_equal_approx(dummy.vitals.health, 25.0), "revived with an IFAK to 25 HP (%.0f)" % dummy.vitals.health)
	check(player.inventory.count_of(&"ifak") == 0, "the IFAK was used")
	player.inventory.take(&"hvt_case")
	var rounds := player.inventory.rounds_in(&"primary")
	player.vitals.server_damage(500.0)
	await _frames(2)
	check(player.vitals.downed and player.inventory.hands == &"", "player goes down and drops the HVT case")
	player._server_fire.rpc_id(1, player.head.global_position, -player.global_basis.z, &"primary")
	check(player.inventory.rounds_in(&"primary") == rounds, "can't shoot while down")
	var death_spot := player.global_position
	var had_vest: StringName = player.inventory.slots[&"vest"]
	player._server_give_up.rpc_id(1)
	await _frames(2)
	check(player.vitals.is_up() and player.vitals.health == player.vitals.max_health, "giving up respawns you at full health")
	var inv := player.inventory
	check(inv.slots[&"primary"] == &"m4a1" and inv.count_of(&"mag_556") == 2 and inv.count_of(&"smoke_grenade") == 1 and inv.count_of(&"frag_grenade") == 1,
		"respawned in the default kit: M4, 2 mags, smoke, frag")
	check(inv.slots[&"vest"] == &"" and inv.slots[&"helmet"] == &"", "none of the old gear came along")
	var left := _items_near(death_spot, 3.0)
	check(had_vest != &"" and left.has(had_vest), "old gear left where you died (%s)" % [left])
	var markers := level.get_children().filter(func(n: Node) -> bool: return n is GearMarker)
	check(markers.size() == 1, "a marker shows where it lies")


func _test_throwables() -> void:
	print("Grenades")
	var inv := player.inventory
	inv.strip()  # start from empty pockets, not the respawn kit
	for id: StringName in [&"frag_grenade", &"flashbang", &"smoke_grenade"]:
		inv.take(id)
	player.global_position = Vector3(0, 0.1, 18)
	await _frames(2)
	player._server_busy_until = 0.0
	player._server_throw.rpc_id(1, player.camera.global_position, -player.global_basis.z, &"frag_grenade")
	check(inv.count_of(&"frag_grenade") == 0, "throwing uses the grenade")
	check(level.get_children().any(func(n: Node) -> bool: return n is Grenade), "a grenade is in flight")
	await _seconds(3.8)
	check(not level.get_children().any(func(n: Node) -> bool: return n is Grenade), "it went off after its fuse")

	var light: TargetDummy = level.get_node(^"Dummies/LightDummy")
	var medium: TargetDummy = level.get_node(^"Dummies/MediumDummy")
	for d: TargetDummy in [light, medium]:
		d.respawn_seconds = 999.0
		d.vitals.server_reset_health()
	var edits := GameState.voxel_edits.size()
	Throwables.server_detonate(level, "frag", light.global_position + Vector3(1.0, 0.05, 0.0))
	check(light.vitals.health < light.vitals.max_health, "frag hurts a dummy 1 m away (HP %.0f)" % light.vitals.health)
	check(GameState.voxel_edits.size() == edits + 1, "frag leaves a crater in the voxels")
	Throwables.server_detonate(level, "frag", Vector3(3, 0.2, -2.5))
	check(is_equal_approx(medium.vitals.health, medium.vitals.max_health), "a wall shields the dummy inside the building")
	for d: TargetDummy in [light, medium]:
		d.vitals.server_reset_health()

	var hud: Hud = player._hud
	player.global_position = Vector3(0, 0.1, 18)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await _frames(2)
	Throwables.server_detonate(level, "flash", player.global_position + Vector3(0, 0.3, -3))
	await _frames(2)
	check(hud._white_left > 3.0, "a flashbang in front of you whites out the screen (%.1f s)" % hud._white_left)

	var smoke_at := Vector3(0, 0.1, 14)
	Throwables.server_detonate(level, "smoke", smoke_at)
	await _seconds(3.2)
	check(SmokeCloud.blocks(smoke_at + Vector3(-8, 1.5, 0), smoke_at + Vector3(8, 1.5, 0)), "smoke blocks a sight line through it")
	check(not SmokeCloud.blocks(smoke_at + Vector3(-8, 1.5, 12), smoke_at + Vector3(8, 1.5, 12)), "but not one well clear of it")


func _items_near(pos: Vector3, radius: float) -> Array[StringName]:
	var ids: Array[StringName] = []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if not node.is_queued_for_deletion() and (node as Node3D).global_position.distance_to(pos) <= radius:
			ids.append(node.item_id)
	return ids


func _world_item(id: StringName) -> WorldItem:
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node.item_id == id and GameState.dropped.has(node.uid) and not node.is_queued_for_deletion():
			return node
	return null


func _count(inv: Inventory, container: StringName, id: StringName) -> int:
	return inv.containers[container].filter(func(e: Dictionary) -> bool: return e.id == id).reduce(func(a: int, e: Dictionary) -> int: return a + e.count, 0)


func _index_of(inv: Inventory, container: StringName, id: StringName) -> int:
	var list: Array = inv.containers[container]
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
