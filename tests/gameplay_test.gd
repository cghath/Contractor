extends Node
## Headless end-to-end checks: hosts a real session and drives the host player through the
## same RPCs a client would send (fire, reload, heal, inventory actions, drop and pick up).
##   <voxel godot exe> --headless --path . res://tests/gameplay_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_gameplay" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	Soldier.respawn_delay_s = 0.0  # these checks want the old instant respawn (the wait and spawn
	Soldier.spawn_protect_s = 0.0  # protection have their own checks in gameplay and missions)
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
	await _test_optics()
	await _test_downed()
	await _test_throwables()
	await _test_bad_input()
	await _test_reload_across_death()
	await _test_respawn_wait_and_protection()
	await _test_give_up()
	await _test_reload_replaced_gun()
	await _test_fire_cadence()
	_test_ammo_replication()
	await _test_saves()
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


## Playtest blocker B2: a shot sends only the counts (Inventory.net_ammo), not the whole
## snapshot (net_gear); a peer, whichever arrives first and joining late, ends up with the
## right rounds. Peers are stand-in inventories given what the synchroniser would set.
func _test_ammo_replication() -> void:
	print("Ammo replication: counts, not the whole inventory")
	var inv := Inventory.new()
	for id: StringName in [&"plate_carrier", &"m4a1"]:
		inv.take(id)
	inv.take(&"mag_556", 2)
	var gear_before := inv.net_gear
	var rev := int(inv.net_gear.get("rev", -1))
	inv.consume_round(&"primary")
	inv.consume_round(&"primary")
	check(is_same(inv.net_gear, gear_before) and inv.net_ammo[0] == rev and inv.net_ammo[1] == 28
		and int(inv.net_state.slot_state.primary.rounds) == 28 and int(inv.net_gear.state.slot_state.primary.rounds) == 30,
		"two shots: only the counts change (rev %d, %s); the host's own net_state keeps up (28)" % [rev, inv.net_ammo])
	var late := Inventory.new()  # a late joiner: the snapshot, then the counts
	late.net_gear = inv.net_gear.duplicate(true)
	late.net_ammo = inv.net_ammo.duplicate()
	var early := Inventory.new()  # the counts first: they wait for their snapshot
	early.net_ammo = inv.net_ammo.duplicate()
	early.net_gear = inv.net_gear.duplicate(true)
	var stale := Inventory.new()  # counts of an older snapshot don't land on a newer one
	stale.net_gear = inv.net_gear.duplicate(true)
	stale.net_ammo = PackedInt32Array([rev - 1, 3, -1, -1])
	check(late.rounds_in(&"primary") == 28 and early.rounds_in(&"primary") == 28 and stale.rounds_in(&"primary") == 30
		and late.slots[&"vest"] == &"plate_carrier" and late.count_of(&"mag_556") == 2,
		"a peer gets 28 whichever comes first; old counts are ignored (%d, %d, %d)" % [late.rounds_in(&"primary"), early.rounds_in(&"primary"), stale.rounds_in(&"primary")])
	inv.take(&"mag_556")
	check(int(inv.net_gear.get("rev", -1)) == rev + 1 and inv.net_ammo[0] == rev + 1 and int(inv.net_gear.state.slot_state.primary.rounds) == 28,
		"a real change sends the whole snapshot again, counts included (rev %d)" % int(inv.net_gear.get("rev", -1)))
	var kept := inv.net_state.duplicate(true)
	var copy := Inventory.new()
	copy.net_state = kept
	copy.consume_round(&"primary")
	check(int(kept.slot_state.primary.rounds) == 28 and copy.rounds_in(&"primary") == 27,
		"a shot after net_state is assigned doesn't change the caller's dictionary")
	for x: Inventory in [inv, late, early, stale, copy]:
		x.free()
	for scene: String in ["res://scenes/soldier.tscn", "res://scenes/target_dummy.tscn"]:
		var node: Node = load(scene).instantiate()
		var config: SceneReplicationConfig = node.get_node(^"ServerSync").replication_config
		var ok := not config.has_property(^"Inventory:net_state") and not config.has_property(^"Vitals:net_state")
		for prop: NodePath in [^"Inventory:net_gear", ^"Inventory:net_ammo", ^"Vitals:net_vitals", ^"Vitals:net_pulse"]:
			ok = ok and config.has_property(prop) and config.property_get_spawn(prop) \
				and config.property_get_replication_mode(prop) == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		check(ok, "%s: the host sends net_gear, net_ammo, net_vitals and net_pulse on change and to late joiners, not a whole net_state" % scene.get_file())
		node.free()


func _test_medical() -> void:
	print("Medical (RPC)")
	player.inventory.take(&"ifak")
	# A pistol round through the outside of the left thigh (rest pose): a plain muscle wound.
	player.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.PISTOL, "position": player.global_transform * Vector3(-0.12, 0.7, -0.1),
		"direction": player.global_basis * Vector3.BACK})
	player._server_use_medical.rpc_id(1)
	check(player.vitals.is_healing() and absf(player._server_busy_until - Soldier._now() - 5.0) < 0.1, "H: a pressure bandage on yourself, 5 s")
	await _seconds(5.3)
	check(player.vitals.wound_list()[0].treated and not player.vitals.wound_list()[0].bleeding, "the bandage stopped the bleeding")
	var kit := _entry(player.inventory, &"ifak")
	check(int(Inventory.kit_contents(ItemDB.get_item(&"ifak"), kit.get("state", {})).get("pressure_bandage", 0)) == 1, "drawn from the IFAK: one bandage left (%s)" % Inventory.kit_text(ItemDB.get_item(&"ifak"), kit.get("state", {})))
	player._server_use_medical.rpc_id(1)  # nothing in the IFAK for what's left (pain, if any)
	check(not player.vitals.is_healing(), "nothing more an IFAK can do")
	player.inventory.remove_one(&"ifak")
	player.vitals.server_reset_health()  # blood lost would widen the spread checks below


func _entry(inv: Inventory, id: StringName) -> Dictionary:
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inv.containers[container]:
			if entry.id == id:
				return entry
	return {}


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


## Audit L6-01: a shot or throw from a non-finite point, or with no direction, is refused before
## anything is spent, and makes nothing.
func _test_bad_input() -> void:
	print("Bad coordinates from a client")
	await _seconds(1.0)  # past any throw or reload still keeping the hands busy
	player.vitals.server_reset_health()  # the grenade tests may have knocked us down
	await _frames(2)
	player.inventory.strip()  # a clean kit: a loaded rifle, so a refused shot is a real refusal
	player.inventory.take(&"m4a1")
	player.inventory.take(&"mag_556", 2)
	player.inventory.reload(&"primary")
	player.inventory.take(&"smoke_grenade")
	var rounds := player.inventory.rounds_in(&"primary")
	var smokes := player.inventory.count_of(&"smoke_grenade")
	var clouds := SmokeCloud.active.size()
	var eye := player.camera.global_position
	for origin: Vector3 in [Vector3(NAN, 0, 0), Vector3(INF, 0, 0), eye]:
		var dir := Vector3.ZERO if origin == eye else Vector3.FORWARD
		player._server_fire.rpc_id(1, origin, dir, &"primary")
		player._server_throw.rpc_id(1, origin, dir, &"smoke_grenade")
	player._server_squad_command.rpc_id(1, "move", Vector3(0, NAN, 0), PackedStringArray())
	await _frames(3)
	check(player.inventory.rounds_in(&"primary") == rounds and player.inventory.count_of(&"smoke_grenade") == smokes,
		"NaN, infinite or zero-length shots and throws are refused before a round or grenade is spent (%d rounds, %d smokes)" % [rounds, smokes])
	await _seconds(0.3)
	player._server_fire.rpc_id(1, eye, -player.global_basis.z, &"primary")
	await _frames(3)
	check(player.inventory.rounds_in(&"primary") == rounds - 1, "while a normal shot right after still fires (%d rounds; up %s, hands '%s')" % [player.inventory.rounds_in(&"primary"), player.vitals.is_up(), player.inventory.hands])
	await _seconds(4.0)  # past a smoke grenade's fuse
	check(SmokeCloud.active.size() == clouds, "and no smoke goes off from them")


## Audit L10-01: shots that reach the host bunched up (paced right when sent, delayed unevenly by
## the network) all count, while the weapon's rate still holds: a flood fires no faster.
func _test_fire_cadence() -> void:
	print("Fire cadence under bunching")
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	player.inventory.take(&"mag_556", 2)
	player.inventory.reload(&"primary")
	var fire := func() -> void: player._server_fire.rpc_id(1, player.camera.global_position, -player.global_basis.z, &"primary")
	await _seconds(1.0)
	var start := player.inventory.rounds_in(&"primary")
	for i in 2:
		fire.call()
	await _seconds(0.2)
	for i in 2:
		fire.call()
	await _frames(2)
	check(start - player.inventory.rounds_in(&"primary") == 4, "two pairs arriving bunched (0.1 s apart on average) all fire (%d of 4)" % (start - player.inventory.rounds_in(&"primary")))
	await _seconds(1.0)
	start = player.inventory.rounds_in(&"primary")
	for i in 10:
		fire.call()
	await _frames(2)
	var burst := start - player.inventory.rounds_in(&"primary")
	var interval := 60.0 / float(ItemDB.get_item(&"m4a1").stats.rpm)
	check(burst == 1 + int(Soldier.FIRE_BUNCH_S / interval), "ten in one instant after a pause: only %d fire (the bunching allowance, no more)" % burst)
	await _seconds(1.0)
	start = player.inventory.rounds_in(&"primary")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		fire.call()
		await get_tree().process_frame
	var flood := start - player.inventory.rounds_in(&"primary")
	var most := int(1.0 / interval) + 1 + int(Soldier.FIRE_BUNCH_S / interval) + 1
	check(flood >= int(1.0 / interval) - 1 and flood <= most, "a request every frame for a second fires at the weapon's rate (%d shots, at most %d)" % [flood, most])


## Captain, playtest P0362: a dead player waits Soldier.respawn_delay_s out of the fight (unseen,
## untouchable, no firing), then comes back with spawn protection that blocks harm until it runs
## out or they fire. (Where they come back: missions, _test_respawn_points.)
func _test_respawn_wait_and_protection() -> void:
	print("Respawn: the wait and spawn protection")
	Soldier.respawn_delay_s = 1.5
	Soldier.spawn_protect_s = 1.5
	var death_spot := Vector3(10, 0.1, 30)
	player.global_position = death_spot
	await _frames(2)
	var bodies_before := level.bodies.get_child_count()
	player.vitals.server_kill()
	var died_at := Soldier._now()
	await _frames(3)
	check(player.respawn_state == Soldier.RESPAWN_WAITING and player.vitals.is_up() and level.bodies.get_child_count() == bodies_before,
		"killed: no body is left (Captain, 2026-10-14), the player waits to respawn (state %d)" % player.respawn_state)
	check(not player.model.visible and not player.is_in_group(&"combatants") and player.collision_layer == 0,
		"while waiting: not drawn, no collision, not a target")
	check(player.global_position.distance_to(death_spot) < 0.5, "still where he died, not at a spawn point yet")
	player.vitals.server_damage(40.0)
	check(player.vitals.blood_fraction() == 1.0, "nothing hurts him while he waits")
	var rounds := player.inventory.rounds_in(&"primary")
	player._server_fire.rpc_id(1, player.head.global_position, -player.global_basis.z, &"primary")
	check(player.inventory.rounds_in(&"primary") == rounds and rounds > 0, "and he can't fire")
	await _seconds(0.8)
	check(player.respawn_state == Soldier.RESPAWN_WAITING, "%.1f s on, still waiting (the delay is %.1f s)" % [Soldier._now() - died_at, Soldier.respawn_delay_s])
	var t0 := Soldier._now()
	while player.respawn_state == Soldier.RESPAWN_WAITING and Soldier._now() - t0 < 3.0:
		await get_tree().process_frame
	var waited := Soldier._now() - died_at
	await _frames(2)  # every peer applies the state in its own frame (Soldier._apply_respawn_state)
	var spawn_gap: float = CompoundLevel.SPAWN_POINTS.map(func(p: Vector3) -> float: return p.distance_to(player.global_position)).min()
	check(player.respawn_state == Soldier.RESPAWN_PROTECTED and waited >= Soldier.respawn_delay_s - 0.05 and waited < Soldier.respawn_delay_s + 0.5,
		"respawned after the delay (%.2f s), with spawn protection" % waited)
	check(spawn_gap < 0.5 and player.model.visible and player.is_in_group(&"combatants") and player.collision_layer == Soldier.BODY_LAYER,
		"back at a spawn point (%.2f m off), seen and solid again" % spawn_gap)
	player.vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.INTERMEDIATE})
	player.vitals.server_damage(40.0)
	check(player.vitals.wound_list().is_empty() and player.vitals.blood_fraction() == 1.0, "spawn protection: a round and trauma do nothing")
	await _seconds(0.2)
	player._server_fire.rpc_id(1, player.head.global_position, -player.global_basis.z, &"primary")
	check(player.respawn_state == Soldier.RESPAWN_NONE and player.inventory.rounds_in(&"primary") == rounds - 1, "firing ends it")
	player.vitals.server_damage(40.0)
	check(player.vitals.blood_fraction() < 1.0, "and then harm lands again")
	player.vitals.server_reset_health()
	# Unbroken, it runs out on its own.
	player.vitals.server_kill()
	await _seconds(Soldier.respawn_delay_s + 0.3)
	check(player.respawn_state == Soldier.RESPAWN_PROTECTED, "killed again: back with protection")
	await _seconds(Soldier.spawn_protect_s + 0.3)
	check(player.respawn_state == Soldier.RESPAWN_NONE and not player.vitals.shielded, "spawn protection runs out after %.1f s" % Soldier.spawn_protect_s)
	Soldier.respawn_delay_s = 0.0
	Soldier.spawn_protect_s = 0.0
	player.vitals.server_reset_health()


## Captain, playtest P0362: down with nobody to help, a player was stuck until the session ended.
## Holding the give-up key Soldier.GIVE_UP_HOLD_S gives up (a death: no body is left, the respawn
## pool counts it, base checks the pool), once down GIVE_UP_AFTER_S or at once with no conscious
## friendly within GIVE_UP_ALONE_M.
func _test_give_up() -> void:
	print("Giving up while down")
	player.global_position = Vector3(10, 0.1, 30)
	await _frames(2)
	check(not player.can_give_up() and Hud.give_up_text(player, 0.0) == "", "on his feet: no giving up, no prompt")
	var buddy := level.spawn_soldier({"name": "GiveUpBuddy", "faction": "friendly", "variant": "multicam", "pos": Vector3(14, 0.1, 30),
		"loadout": [], "slot": 1, "combat": 0.5, "discipline": 0.5, "guard": false})
	await _frames(3)
	SquadAI.of(buddy).process_mode = Node.PROCESS_MODE_DISABLED
	player.vitals.server_damage(500.0)
	await _frames(3)
	var key := OS.get_keycode_string(GameSettings.key_for(&"give_up"))
	check(not player.vitals.is_up() and player.help_near() and not player.can_give_up(),
		"down with a conscious squadmate 4 m off: not yet")
	check(("Give up ([%s], hold) in" % key) in Hud.give_up_text(player, 0.0), "the prompt says when (%s)" % Hud.give_up_text(player, 0.0).strip_edges())
	player._server_give_up.rpc_id(1)
	await _frames(2)
	check(not player.vitals.is_up() and not player.vitals.is_dead(), "the host refuses a give-up asked too early")
	buddy.global_position = Vector3(10, 0.1, 30 + Soldier.GIVE_UP_ALONE_M + 10.0)
	await _frames(2)
	check(not player.help_near() and player.can_give_up() and ("Hold [%s] to give up" % key) in Hud.give_up_text(player, 0.0),
		"nobody within %.0f m: open at once, and the prompt says so" % Soldier.GIVE_UP_ALONE_M)
	buddy.global_position = Vector3(14, 0.1, 30)
	buddy.vitals.server_damage(500.0)  # a squadmate who's down himself is no help
	await _frames(3)
	check(not buddy.vitals.is_up() and player.can_give_up(), "a downed squadmate beside him is no help: open")
	buddy.vitals.server_reset_health()
	await _frames(3)
	check(not player.can_give_up(), "the squadmate back up: closed again")
	player._down_since = Soldier._now() - Soldier.GIVE_UP_AFTER_S - 0.1
	check(player.can_give_up(), "down %.0f s: open even with help near" % Soldier.GIVE_UP_AFTER_S)
	# Holding the key (PlayerInput._update_give_up): a short hold does nothing...
	var deaths := [0]
	var on_died := func() -> void: deaths[0] += 1
	player.vitals.died.connect(on_died)
	var bodies_before := level.bodies.get_child_count()
	Input.action_press(&"give_up")
	await _seconds(Soldier.GIVE_UP_HOLD_S * 0.5)
	check(player.player_input.give_up_held > 0.0 and "Giving up" in Hud.give_up_text(player, player.player_input.give_up_held), "holding the key fills the prompt")
	Input.action_release(&"give_up")
	await _frames(2)
	check(not player.vitals.is_up() and deaths[0] == 0 and player.player_input.give_up_held == 0.0, "let go early: still down")
	# ...a full one gives up: a death, through the respawn.
	Input.action_press(&"give_up")
	await _seconds(Soldier.GIVE_UP_HOLD_S + 0.4)
	Input.action_release(&"give_up")
	await _frames(3)
	player.vitals.died.disconnect(on_died)
	check(deaths[0] == 1 and level.bodies.get_child_count() == bodies_before, "held %.0f s: he dies (a death, no body left behind)" % Soldier.GIVE_UP_HOLD_S)
	var spawn_gap: float = CompoundLevel.SPAWN_POINTS.map(func(p: Vector3) -> float: return p.distance_to(player.global_position)).min()
	check(player.vitals.is_up() and spawn_gap < 0.5 and player.inventory.slots[&"primary"] == &"m4a1", "and respawns with his own rifle")
	buddy.queue_free()
	await _frames(2)


## Audit L3-02: a reload started before dying doesn't finish on the rifle you respawn with.
func _test_reload_across_death() -> void:
	print("Reload across a death")
	await _seconds(1.0)
	player.inventory.consume_round(&"primary")
	player._server_reload.rpc_id(1, &"primary")
	await _frames(2)
	player.vitals.server_kill()  # respawns with the same M4 (Captain, 2026-10-14: your own kit)
	await _frames(3)
	player.inventory.consume_round(&"primary")
	player.inventory.consume_round(&"primary")
	var after := player.inventory.rounds_in(&"primary")
	await _seconds(player.reload_seconds(ItemDB.get_item(&"m4a1")) + 0.5)
	check(after > 0 and player.inventory.rounds_in(&"primary") == after, "the old reload didn't refill the new rifle (%d rounds, still %d)" % [after, player.inventory.rounds_in(&"primary")])


## Audit A2-02: a reload started on one M4 doesn't finish on another M4 picked up meanwhile;
## the gun now in hand reloads as usual.
func _test_reload_replaced_gun() -> void:
	print("Reload, then a different gun of the same model")
	var inv := player.inventory
	var seconds := player.reload_seconds(ItemDB.get_item(&"m4a1"))
	inv.consume_round(&"primary")
	player._server_busy_until = 0.0
	player._server_reload.rpc_id(1, &"primary")
	await _seconds(0.1)
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"primary", &"")
	level.server_spawn_dropped(&"m4a1", 1, player.global_position + Vector3.UP * 0.5, {"rounds": 1, "test_mark": "replacement"})
	await _frames(2)
	var replacement: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if node is WorldItem and node.state.get("test_mark", "") == "replacement":
			replacement = node
	if replacement:
		player._server_interact.rpc_id(1, replacement.get_path())
	var spare := inv.spare_rounds(&"mag_556")
	check(replacement != null and inv.slots[&"primary"] == &"m4a1" and inv.rounds_in(&"primary") == 1,
		"mid-reload: the M4 dropped, another M4 (1 round) picked up")
	await _seconds(seconds + 0.5)
	check(inv.rounds_in(&"primary") == 1 and inv.spare_rounds(&"mag_556") == spare,
		"the old reload didn't load the other M4 (%d rounds, spare %d -> %d)" % [inv.rounds_in(&"primary"), spare, inv.spare_rounds(&"mag_556")])
	player._server_busy_until = 0.0
	player._server_reload.rpc_id(1, &"primary")
	await _seconds(seconds + 0.3)
	check(inv.rounds_in(&"primary") == 30, "reloading the M4 now in hand works (%d)" % inv.rounds_in(&"primary"))
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):  # the dropped M4: not part of later tests
		if node is WorldItem and node.item_id == &"m4a1":
			GameState.item_taken(node.uid)
			node.queue_free()


## Audit L1-01 and L1-05: a level-placed stack partly taken saves what's left; a save goes through a
## checked temporary file and keeps a backup; a broken save falls back to it; bad records are
## skipped and a save with a wrong-typed section is refused, without touching the live state.
func _test_saves() -> void:
	print("Saves: partly taken loot, backup, bad records")
	player.inventory.strip()
	player.inventory.take(&"assault_pack")  # room for some magazines, not 200
	var uid := "test_level_stack"
	level.spawn_item(&"mag_556", 200, player.global_position + Vector3(0, 0.5, -0.6), uid)
	await _frames(2)
	var stack: WorldItem = null
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node.uid == uid:
			stack = node
	player._server_interact.rpc_id(1, stack.get_path())
	await _frames(2)
	var left := stack.count if is_instance_valid(stack) else -1
	check(left > 0 and left < 200 and GameState.is_looted(uid) and int(GameState.dropped.get(uid, {}).get("count", -1)) == left,
		"a level stack partly taken is saved with what's left (%d of 200)" % left)
	GameState.save_zone()
	GameState.save_zone()  # the first becomes the backup
	var path := GameState.save_path()
	check(FileAccess.file_exists(GameState.backup_path(path)) and not FileAccess.file_exists(path + ".tmp"), "saving keeps the previous save as a backup, no temporary file left")
	GameState.load_zone()
	check(int(GameState.dropped.get(uid, {}).get("count", -1)) == left, "and after a reload the stack is still %d, not 200" % left)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"looted\": [")  # cut off mid-write
	f.close()
	GameState.load_zone()
	check(int(GameState.dropped.get(uid, {}).get("count", -1)) == left, "a broken save loads its backup instead")
	# Audit A1-01, A1-02: the broken save is kept aside, not deleted, and with the save gone the
	# backup still loads.
	var kept := GameState.kept_copies(path)
	check(kept.size() == 1 and FileAccess.get_file_as_string("%s/%s" % [GameState.SAVE_DIR, kept[0]]) == "{\"version\": 1, \"looted\": [",
		"the broken save is kept aside as it was (%s)" % ", ".join(kept))
	GameState.dropped.clear()
	GameState.load_zone()
	check(not FileAccess.file_exists(path) and int(GameState.dropped.get(uid, {}).get("count", -1)) == left, "with no save but its backup, the backup loads")
	for k in kept:
		DirAccess.remove_absolute("%s/%s" % [GameState.SAVE_DIR, k])
	# Audit A1-03: records replay or restore can't use are skipped, the rest of the zone loads and
	# replays in the live level.
	var good_text := FileAccess.get_file_as_string(GameState.backup_path(path))
	var zone: Dictionary = JSON.parse_string(good_text)
	var mark_at := player.global_position + Vector3(0, 1.0, -3.0)
	var at := level.voxel_world.terrain.to_local(mark_at)
	zone.voxel_edits = [{"op": "carve", "c": [], "r": 1}, {"op": "blast", "c": [1, 2, 3], "r": "big"}, {"op": "holes", "v": [1, 2]},
		{"op": "shot", "a": [0, 1, 0], "an": [0, 0, 1], "b": [0, 1, 1], "v": []}, {"op": "melt", "c": [0, 0, 0]}, "carve",
		{"op": "mark", "p": [at.x, at.y, at.z], "n": [0, 0, 1], "m": "concrete"}, {"op": "mark", "p": [at.x, at.y, at.z], "n": [0, 0, 1], "m": 2}]
	zone.bodies = [{"uid": "bad_gear", "pos": [0, 1, 0], "gear": []}, {"uid": "bad_ragdoll", "pos": [0, 1, 0], "ragdoll": {"a": 1}},
		{"uid": "bad_age", "pos": [0, 1, 0], "age_s": "old"}]
	zone.dropped["bad_state"] = {"id": "mag_556", "count": 1, "pos": [0, 1, 0], "state": []}
	zone.dropped["bad_id"] = {"id": ["mag_556"], "count": 1, "pos": [0, 1, 0]}
	zone["vehicles"] = [{"id": "bad_zones", "model": "matv", "pos": [0, 1, 0], "zones": []}, {"id": "bad_model", "model": 7, "pos": [0, 1, 0]}]
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(JSON.stringify(zone))
	f2.close()
	GameState.load_zone()
	check(GameState.voxel_edits.size() == 1 and int(GameState.voxel_edits[0].m) == 2 and GameState.bodies.is_empty() and GameState.vehicles.is_empty()
		and int(GameState.dropped.get(uid, {}).get("count", -1)) == left and not GameState.dropped.has("bad_state") and not GameState.dropped.has("bad_id"),
		"bad voxel edits, bodies, vehicles and dropped items are skipped; the good edit and the stack load (%d edits)" % GameState.voxel_edits.size())
	var marks := level.voxel_world.marks_near(mark_at, 0.05)
	level.voxel_world.load_edits(GameState.voxel_edits)
	await _frames(2)
	check(level.voxel_world.marks_near(mark_at, 0.05) == marks + 1, "and what's left replays in the level: the good mark is there")
	var f3 := FileAccess.open(path, FileAccess.WRITE)
	f3.store_string(good_text)
	f3.close()
	GameState.load_zone()
	var bad :={"version": GameState.SAVE_VERSION, "looted": ["a"], "voxel_edits": [], "bodies": [{"uid": "b1", "pos": [0, 1]}],
		"dropped": {"ok": {"id": "mag_556", "count": 2, "pos": [0, 1, 0]}, "unknown": {"id": "no_such_item", "count": 1, "pos": [0, 1, 0]},
			"short_pos": {"id": "mag_556", "count": 1, "pos": [0, 1]}, "zero": {"id": "mag_556", "count": 0, "pos": [0, 1, 0]}}}
	var test_path := "%s/%s_bad.json" % [GameState.SAVE_DIR, GameState.zone_id]
	GameState.write_safely(test_path, JSON.stringify(bad))
	var read := GameState.read_save(test_path)
	check(read.get("dropped", {}).keys() == ["ok"] and (read.get("bodies", [1]) as Array).is_empty() and read.get("looted", {}).has("a"),
		"bad records are skipped (unknown item, two-number position, zero count, broken body); the rest loads")
	bad["dropped"] = []
	GameState.write_safely(test_path, JSON.stringify(bad))
	check(GameState.read_save(test_path).is_empty(), "a save whose section has the wrong type is refused")
	for p: String in [test_path, GameState.backup_path(test_path)]:
		DirAccess.remove_absolute(p)
	if is_instance_valid(stack):
		stack.queue_free()


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
	check(hip > 0.3 and hip <= Soldier.SHOOTER_HIP_DEG * 1.5 + 0.1, "hip-fire stays inside the cone (max %.2f deg)" % hip)
	check(aimed < hip * 0.3, "aiming tightens it (max %.2f deg)" % aimed)
	# Captain, P0362: a player's aimed rifle shot standing still lands within about 10 cm at
	# 100 m (the weapon's own cone plus the trigger press); sway and recoil are the rest.
	check(aimed <= 0.06, "aimed and still, an M4 groups tight (max %.3f deg, %.0f cm at 100 m)" % [aimed, tan(deg_to_rad(aimed)) * 10000.0])
	# The AI keeps its own cone: the weapon's ai_spread_deg, its accuracy before P0362.
	check(is_equal_approx(Soldier.ai_spread_deg(weapon), 1.2) and is_equal_approx(Soldier.ai_spread_deg(ItemDB.get_item(&"m110")), 1.6),
		"the AI's cone is unchanged (M4 %.2f deg)" % Soldier.ai_spread_deg(weapon))
	var ai_max := 0.0
	player.is_aiming = true
	for i in 200:
		ai_max = maxf(ai_max, rad_to_deg(forward.angle_to(player.ai_spread_direction(weapon))))
	player.is_aiming = false
	check(ai_max > aimed * 1.5, "and stays wider than a player's aimed shot (AI %.3f, player %.3f deg)" % [ai_max, aimed])
	# Recoil heat blooms the cone; it fades in about a second.
	player.recoil_heat = 5.0
	player._heat_at = Soldier._now()
	player.is_aiming = true
	var hot := player.spread_deg_now(weapon)
	player.recoil_heat = 0.0
	var cold := player.spread_deg_now(weapon)
	player.is_aiming = false
	check(hot > cold + 0.3, "auto fire blooms the cone (%.2f vs %.2f deg)" % [hot, cold])


## Optics as attachments (Captain, P0362, 2026-10-13): the optic on a gun is in the gun's own
## item state (so it's replicated, dropped, picked up and saved with it), swapped from the
## inventory screen's actions; magnified power is against the unaimed view; the AI's cone is
## the gun's whatever optic it carries.
func _test_optics() -> void:
	print("Optics (RPC)")
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	var m110 := ItemDB.get_item(&"m110")
	var on_gun := func() -> StringName:
		var optic := Optics.on_slot(inv, &"primary")
		return optic.id if optic else &""
	check(on_gun.call() == &"optic_red_dot" and Optics.mounted(m110, {}).id == &"optic_dmr_3_5_10"
		and not Optics.has_rail(ItemDB.get_item(&"m17")) and Optics.mounted(ItemDB.get_item(&"m17"), {}) == null,
		"the M4 comes with its red dot, the M110 with its 3.5-10x, the M17 has irons only")
	check(VoxelArt.model_for(m4, inv.state_of(&"primary")).ends_with(":dot"), "the M4's model shows its red dot")
	var rounds := inv.rounds_in(&"primary")
	check(inv.take(&"optic_lpvo") == 1, "an LPVO picked up")
	var where := _find(inv, &"optic_lpvo")
	player._server_inventory_action.rpc_id(1, "mount_optic", where[0], where[1], &"primary", &"")
	check(on_gun.call() == &"optic_lpvo" and inv.count_of(&"optic_red_dot") == 1 and inv.count_of(&"optic_lpvo") == 0,
		"the LPVO goes on the M4, its red dot into the kit")
	check(String(inv.net_state.slot_state.primary.get("optic", "")) == "optic_lpvo" and inv.rounds_in(&"primary") == rounds,
		"in the gun's replicated state, its rounds kept")
	check(VoxelArt.model_for(m4, inv.state_of(&"primary")).ends_with(":lpvo"), "and its model shows the LPVO")
	player._server_inventory_action.rpc_id(1, "remove_optic", &"", -1, &"primary", &"")
	check(on_gun.call() == &"" and inv.count_of(&"optic_lpvo") == 1 and VoxelArt.model_for(m4, inv.state_of(&"primary")).ends_with(":irons"),
		"taken off: back-up irons, the LPVO stowed")
	where = _find(inv, &"optic_lpvo")
	player._server_inventory_action.rpc_id(1, "mount_optic", where[0], where[1], &"primary", &"")
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"primary", &"")
	await _frames(2)
	var rifle := _world_item(&"m4a1")
	check(rifle != null and String(rifle.state.get("optic", "")) == "optic_lpvo", "a dropped M4 keeps its LPVO")
	if rifle:
		rifle.global_position = player.global_position + Vector3(0, 0.5, -0.6)
		player._server_interact.rpc_id(1, rifle.get_path())
	await _frames(2)
	check(on_gun.call() == &"optic_lpvo", "and has it when picked up again")
	where = _find(inv, &"optic_red_dot")
	player._server_inventory_action.rpc_id(1, "mount_optic", where[0], where[1], &"primary", &"")
	check(on_gun.call() == &"optic_red_dot" and not inv.state_of(&"primary").has("optic") and inv.count_of(&"optic_lpvo") == 1,
		"the red dot back on: the M4 as it came")
	player._server_inventory_action.rpc_id(1, "mount_optic", where[0], where[1], &"sidearm", &"")
	check(inv.slots[&"sidearm"] == &"" or Optics.on_slot(inv, &"sidearm") == null, "nothing mounts on a pistol")
	# Power against the unaimed view: 10x is a tenth of its tangent; 1x the weapon's ads_fov.
	var at10 := GunSight.aimed_fov(m110, 80.0, 10.0)
	check(absf(tan(deg_to_rad(40.0)) / tan(deg_to_rad(at10 * 0.5)) - 10.0) < 0.01 and is_equal_approx(GunSight.aimed_fov(m4, 80.0, 1.0), 50.0),
		"10x shows a tenth of the unaimed view's tangent (%.1f deg at 80), 1x the weapon's aimed view" % at10)
	var zr := func(id: StringName) -> Vector2: return GunSight.zoom_range(ItemDB.get_item(id))
	check(zr.call(&"optic_lpvo") == Vector2(1, 6) and zr.call(&"optic_prism_4x") == Vector2(4, 4) and zr.call(&"optic_dmr_3_5_10") == Vector2(3.5, 10)
		and zr.call(&"optic_dmr_8x") == Vector2(8, 8) and zr.call(&"optic_dmr_3_15") == Vector2(3, 15) and zr.call(&"optic_red_dot") == Vector2.ONE
		and float(ItemDB.get_item(&"optic_holo").stats.magnifier) == 3.0, "LPVO 1-6x, 4x prism, 3.5-10x, 8x, 3-15x, a red dot at 1x, the holo's 3x magnifier")
	check(is_equal_approx(GunSight.power(player, ItemDB.get_item(&"optic_dmr_3_5_10")), 6.0), "the 3.5-10x starts at 6x")
	# Zoom on the side mouse buttons (rebindable): Mouse 5 in, Mouse 4 out; nothing else on them.
	var on_button := func(action: StringName, button: MouseButton) -> bool:
		return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventMouseButton and (e as InputEventMouseButton).button_index == button)
	var others := InputMap.get_actions().filter(func(a: StringName) -> bool:
		return a != &"zoom_in" and a != &"zoom_out" and (on_button.call(a, MOUSE_BUTTON_XBUTTON1) or on_button.call(a, MOUSE_BUTTON_XBUTTON2)))
	check(on_button.call(&"zoom_in", MOUSE_BUTTON_XBUTTON2) and on_button.call(&"zoom_out", MOUSE_BUTTON_XBUTTON1) and others.is_empty()
		and GameSettings.key_for(&"zoom_in") == GameSettings.MOUSE_BIND | MOUSE_BUTTON_XBUTTON2 and GameSettings.binding_name(GameSettings.key_for(&"zoom_out")) == "Mouse 4"
		and GameSettings.BINDABLE.any(func(p: Array) -> bool: return p[0] == &"zoom_in") and not InputMap.has_action(&"magnifier"),
		"zoom in on Mouse 5, out on Mouse 4, in the Keys list (others on them: %s)" % [others])
	var lpvo := ItemDB.get_item(&"optic_lpvo")
	var holo := ItemDB.get_item(&"optic_holo")
	var kept := inv.state_of(&"primary")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, kept, &"optic_lpvo"))
	var at1 := GunSight.power(player, lpvo)
	var told := GunSight.zoom_step(player, 1)
	check(GunSight.of(player) != null and is_equal_approx(at1, 1.0) and is_equal_approx(GunSight.power(player, lpvo), 1.25) and told != "",
		"zoom in steps the LPVO from 1x to 1.25x (%s)" % told)
	for i in 20:
		GunSight.zoom_step(player, 1)
	check(is_equal_approx(GunSight.power(player, lpvo), 6.0) and GunSight.zoom_step(player, 1) == "", "and stops at 6x")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, kept, &"optic_holo"))
	var up := GunSight.zoom_step(player, 1)
	var magnified := GunSight.magnified(player, holo) and is_equal_approx(GunSight.power(player, holo), 3.0)
	var down := GunSight.zoom_step(player, -1)
	check(up != "" and magnified and down != "" and not GunSight.magnified(player, holo) and is_equal_approx(GunSight.power(player, holo), 1.0),
		"the holo's magnifier flips up on zoom in (3x) and down on zoom out")
	inv.set_slot_state(&"primary", kept)
	# A gun's mass and price are with its own optic; another changes them by the difference.
	var mass := func(state: Dictionary) -> float: return Inventory.entry_mass({"id": &"m4a1", "count": 1, "state": state})
	var full := m4.default_state()
	check(is_equal_approx(mass.call(Optics.with_optic(m4, full, &"optic_lpvo")) - mass.call(full), lpvo.mass_kg - 0.22)
		and is_equal_approx(mass.call(Optics.with_optic(m4, full, &"")) - mass.call(full), -0.22),
		"an LPVO adds its mass over the red dot's, irons take the red dot's off")
	check(Prices.sell_price(&"m4a1") == 560 and Prices.sell_price(&"m4a1", 1, Optics.with_optic(m4, full, &"optic_lpvo")) == floori((1400 + 1500 - 600) * 0.4),
		"and its price: an M4 with an LPVO sells for %d" % Prices.sell_price(&"m4a1", 1, Optics.with_optic(m4, full, &"optic_lpvo")))
	# Mils read true at any power; a scale too crowded to read spaces out.
	check(GunSight.mark_step(GunSight.px_per_mil(at10, 1080.0)) == 1.0 and GunSight.mark_step(GunSight.px_per_mil(GunSight.aimed_fov(m110, 80.0, 3.5), 1080.0)) > 1.0,
		"mil marks a mil apart at 10x, wider apart at 3.5x")
	# The AI's cone doesn't care what optic the gun carries.
	check(is_equal_approx(Soldier.ai_spread_deg(m4), 1.2) and is_equal_approx(Soldier.ai_spread_deg(m110), 1.6), "the AI's cone is the gun's, whatever its optic")


## [container, index] of the first stowed `id`, or [&"", -1].
func _find(inv: Inventory, id: StringName) -> Array:
	for c in inv.search_containers():
		var i := _index_of(inv, c, id)
		if i >= 0:
			return [c, i]
	return [&"", -1]


func _test_downed() -> void:
	print("Downed (RPC); no revive")
	var dummy: TargetDummy = level.get_node(^"Dummies/MediumDummy")
	dummy.respawn_seconds = 999.0  # don't get up on its own during the test
	dummy.vitals.server_damage(500.0)
	await _frames(2)
	check(dummy.vitals.downed and dummy.model.downed, "dummy is down and lying down")
	var hitboxes := dummy.get_children().filter(func(n: Node) -> bool: return n is Area3D)
	check(hitboxes.size() == Vitals.BODY_PARTS.size() and hitboxes.all(func(h: Area3D) -> bool: return absf(h.rotation.x + PI / 2) < 0.01),
		"all %d of its hitboxes lie down with it" % hitboxes.size())
	player.global_position = dummy.global_position + Vector3(0, 0, -1.2)
	player.inventory.take(&"trauma_kit")
	await _frames(2)
	check(not InteractionMenu.actions_for(player, dummy).any(func(a: Dictionary) -> bool: return a.id == &"revive"),
		"no revive, even with a trauma kit at hand")
	dummy.vitals.server_advance(5.0)
	check(dummy.vitals.downed and dummy.vitals.in_cardiac_arrest() and dummy.vitals.why_unconscious().has(&"arrest"),
		"in cardiac arrest nothing brings it round (%s)" % [dummy.vitals.why_unconscious()])
	dummy.vitals.server_reset_health()
	player.inventory.remove_one(&"trauma_kit")
	player.inventory.take(&"hvt_case")
	var rounds := player.inventory.rounds_in(&"primary")
	player.vitals.server_damage(500.0)
	await _frames(2)
	check(player.vitals.downed and player.inventory.hands == &"", "player goes down and drops the HVT case")
	player._server_fire.rpc_id(1, player.head.global_position, -player.global_basis.z, &"primary")
	check(player.inventory.rounds_in(&"primary") == rounds, "can't shoot while down")
	var death_spot := player.global_position
	var had_vest: StringName = player.inventory.slots[&"vest"]
	var kit_before := _kit_of(player.inventory)
	var bodies_before := level.bodies.get_child_count()
	player.vitals.server_damage(50.0)
	check(player.vitals.downed, "a hit while down is just another wound")
	player.vitals.server_advance(Vitals.ARREST_WINDOW_S + 1.0)  # nothing restarts a heart yet: the arrest window runs out
	await _frames(2)
	check(player.vitals.is_up() and player.vitals.blood_fraction() == 1.0 and player.vitals.wound_list().is_empty(), "dying respawns you unhurt")
	# Captain, 2026-10-14: "respawn with the kit you had on. delete old player/bot bodies".
	var kit_after := _kit_of(player.inventory)
	check(kit_after == kit_before and had_vest != &"" and player.inventory.slots[&"vest"] == had_vest,
		"respawned with the kit he had on, spent rounds and all%s" % ("" if kit_after == kit_before else " (%s -> %s)" % [kit_before, kit_after]))
	check(level.bodies.get_child_count() == bodies_before and get_tree().get_nodes_in_group(GearMarker.GROUP).is_empty()
		and not _items_near(death_spot, 3.0).has(had_vest), "no body and no gear marker left where he died, and nothing of his on the ground")


## Everything in an inventory, worn and stowed, with its state (rounds, plate damage): to tell
## the kit after a respawn is the kit before it.
static func _kit_of(inv: Inventory) -> String:
	return JSON.stringify(Roster.json_safe(inv.net_state), "", true)


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
	var frag_wounds := light.vitals.wound_list().size()
	check(frag_wounds >= 1 or light.vitals.is_dead(), "frag wounds a dummy 1 m away (%d wounds, %s)" % [frag_wounds, light.vitals.condition_text()])
	check(GameState.voxel_edits.size() == edits + 1, "frag leaves a crater in the voxels")
	Throwables.server_detonate(level, "frag", Vector3(3, 0.2, -2.5))
	check(medium.vitals.wound_list().is_empty(), "a wall shields the dummy inside the building")
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
