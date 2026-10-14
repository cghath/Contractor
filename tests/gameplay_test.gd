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
	await _test_downed()
	await _test_throwables()
	await _test_bad_input()
	await _test_reload_across_death()
	await _test_reload_replaced_gun()
	await _test_fire_cadence()
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


## Audit L3-02: a reload started before dying doesn't finish on the rifle you respawn with.
func _test_reload_across_death() -> void:
	print("Reload across a death")
	await _seconds(1.0)
	player.inventory.consume_round(&"primary")
	player._server_reload.rpc_id(1, &"primary")
	await _frames(2)
	player.vitals.server_kill()  # respawns in the default kit, a fresh M4
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
	# Sights: the M4's red dot, the M17's irons, the M110's 3.5-10x scope (its ring shows the
	# real scope's field: about 2 degrees at 10x, 5.7 at 3.5x).
	var m110 := ItemDB.get_item(&"m110")
	check(GunSight.sight_of(weapon) == "red_dot" and GunSight.sight_of(ItemDB.get_item(&"m17")) == "iron" and GunSight.sight_of(m110) == "scope",
		"M4 red dot, M17 irons, M110 scope")
	var zr := GunSight.zoom_range(m110)
	var at10 := GunSight.aimed_fov(m110, 80.0, zr.y)
	var at35 := GunSight.aimed_fov(m110, 80.0, zr.x)
	check(zr == Vector2(3.5, 10.0) and absf(GunSight.ring_field(at10) - 2.05) < 0.05 and absf(GunSight.ring_field(at35) - 5.86) < 0.05,
		"the M110's scope zooms 3.5-10x (the ring shows %.1f deg at 10x, %.1f at 3.5x)" % [GunSight.ring_field(at10), GunSight.ring_field(at35)])
	check(is_equal_approx(GunSight.magnification(player, m110), 6.0), "and starts at 6x")


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
	player.vitals.server_damage(50.0)
	check(player.vitals.downed, "a hit while down is just another wound")
	player.vitals.server_advance(Vitals.ARREST_WINDOW_S + 1.0)  # nothing restarts a heart yet: the arrest window runs out
	await _frames(2)
	check(player.vitals.is_up() and player.vitals.blood_fraction() == 1.0 and player.vitals.wound_list().is_empty(), "dying respawns you unhurt")
	var inv := player.inventory
	check(inv.slots[&"primary"] == &"m4a1" and inv.count_of(&"mag_556") == 2 and inv.count_of(&"smoke_grenade") == 1 and inv.count_of(&"frag_grenade") == 1,
		"respawned in the default kit: M4, 2 mags, smoke, frag")
	check(inv.slots[&"vest"] == &"" and inv.slots[&"helmet"] == &"", "none of the old gear came along")
	var corpse: Soldier = level.bodies.get_child(level.bodies.get_child_count() - 1) if level.bodies.get_child_count() > 0 else null
	check(corpse != null and corpse.vitals.is_dead() and corpse.global_position.distance_to(death_spot) < 0.5
		and had_vest != &"" and corpse.inventory.slots[&"vest"] == had_vest and not _items_near(death_spot, 3.0).has(had_vest),
		"your body stays where you died with your old gear still on it (%s)" % [corpse.inventory.slots if corpse else "no body"])
	var markers := get_tree().get_nodes_in_group(GearMarker.GROUP)
	check(markers.size() == 1 and (markers[0] as GearMarker).body() == corpse, "a marker shows where it lies")


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
