extends Node
## Two-process co-op check over real ENet: one instance hosts, one joins, and the client
## drives its player through RPCs and checks what replicates back.
##   <exe> --headless --path . res://tests/net_test.tscn -- --host
##   <exe> --headless --path . res://tests/net_test.tscn -- --join 127.0.0.1
## The client prints NET TEST PASSED/FAILED and exits with the failure count; the host
## exits when the client leaves.

const KIT: Array[StringName] = [&"plate_carrier", &"plate_ceramic_l4", &"m4a1", &"helmet", &"assault_pack"]

var failures := 0
var level: CompoundLevel


func _ready() -> void:
	GameState.zone_id = "test_net"
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())  # main reads --host/--join
	await get_tree().process_frame
	level = CompoundLevel.current(self)
	if Net.is_hosting():
		Net.peer_joined.connect(_give_kit)
		Net.peer_left.connect(func(_id: int) -> void: get_tree().quit(0))
		get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	else:
		_run_client()


func _give_kit(id: int) -> void:
	await get_tree().create_timer(0.5).timeout  # let the player spawn
	var player: Player = level.players.get_node_or_null(str(id))
	for item in KIT:
		player.inventory.take(item)
	player.inventory.take(&"mag_556", 2)
	player.inventory.take(&"ifak")
	player.vitals.server_damage(40.0)
	print("[host] gave peer %d a kit" % id)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _run_client() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	var me: Player
	while Time.get_ticks_msec() < deadline:
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me and me.inventory.slots[&"primary"] == &"m4a1":
			break
		await get_tree().process_frame
	print("Client over ENet")
	check(me != null and me.inventory.slots[&"primary"] == &"m4a1", "kit given by the host replicated to the client")
	if me == null:
		_finish()
		return
	me.set_physics_process(false)
	var gear: GearRig = me.get_node(^"Gear")
	check(gear.armor_integrity(&"plate_front") == 1.0 and gear.armor_integrity(&"helmet") == 1.0, "client built the worn voxel armor")
	for i in 3:
		me._server_fire.rpc_id(1, me.camera.global_position, -me.global_basis.z, &"primary")
		await get_tree().create_timer(0.15).timeout
	await _wait_for(func() -> bool: return me.inventory.rounds_in(&"primary") == 27, 3.0)
	check(me.inventory.rounds_in(&"primary") == 27, "3 shots: host's ammo count replicated back (27)")
	me._server_reload.rpc_id(1, &"primary")
	await _wait_for(func() -> bool: return me.inventory.rounds_in(&"primary") == 30, 5.0)
	check(me.inventory.rounds_in(&"primary") == 30 and me.inventory.spare_rounds(&"mag_556") == 57, "reload over the network (30 loaded, 57 spare)")
	me._server_use_medical.rpc_id(1)
	await _wait_for(func() -> bool: return me.vitals.health >= 94.9, 6.0)
	check(absf(me.vitals.health - 95.0) < 0.1, "IFAK heal replicated (60 -> %.0f HP)" % me.vitals.health)
	me._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"helmet", &"")
	await _wait_for(func() -> bool: return me.inventory.slots[&"helmet"] == &"", 3.0)
	await _wait_for(func() -> bool: return _dropped_helmet() != null, 3.0)
	check(_dropped_helmet() != null, "dropped helmet spawned on the client")
	_finish()


func _dropped_helmet() -> WorldItem:
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node.item_id == &"helmet" and node.uid.begins_with("test_net"):
			return node
	return null


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _finish() -> void:
	print("NET TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)
