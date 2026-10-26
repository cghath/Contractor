extends Node
## Condition and wear (docs/survival_wear.md, calls 120-123): shots wear a gun (a wet one faster),
## a worn gun jams and R clears it, a cleaning kit brings it back, a broken one needs a repair kit;
## a dull blade hits softer and a whetstone sharpens it; corroded ammo misfires more than clean,
## a magazine's condition goes into the gun, ammo in the rain corrodes and under a roof keeps;
## clothes wear by the day, torn ones keep less warmth and a needle and thread mends them; worn
## boots make sore feet; a tyre punctures and a patch fixes it; stale fuel stalls the engine.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("WEAR TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _start()
	if level != null and player != null:
		await _test_gun()
		await _test_melee()
		await _test_ammo()
		_test_clothes()
		await _test_vehicle()
	_finish()


func _start() -> void:
	print("A survival world")
	check(Survival.server_new_world(main, "test_wear" + tag, 4321), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null and Wear.enabled(), "the survivor is in and wear runs (a survival world)")
	Wear.tick_off = true  # (the test steps the wear itself)
	for i in 60:
		await get_tree().physics_frame
	_clear_dead()


func _clear_dead() -> void:
	if ZoneDead.of(level):
		ZoneDead.of(level).dead.clear()
	for z: Soldier in Survival.zombies(level):
		z.queue_free()


func _fire() -> void:
	player._server_next_shot = 0.0
	player._server_busy_until = 0.0
	var eye := player.camera.global_position
	player._server_fire.rpc_id(1, eye, (-player.camera.global_basis.z + Vector3.DOWN * 0.3).normalized(), &"primary")
	await get_tree().physics_frame


func _gun() -> Dictionary:
	return player.inventory.state_of(&"primary")


func _test_gun() -> void:
	print("Guns: wear, the wet, jams and the clear, cleaning, broken")
	check(player.inventory.take(&"m4a1") == 1 and player.inventory.slots.get(&"primary", &"") == &"m4a1", "an M4A1 in the primary slot")
	player.inventory.take(&"mag_556", 3)
	player.select_weapon(&"primary")
	Wear.force_roll = 0.99  # (no jams, no duds: the condition alone)
	var rounds := player.inventory.rounds_in(&"primary")
	for i in 5:
		await _fire()
	var c := Wear.cond(_gun())
	check(player.inventory.rounds_in(&"primary") == rounds - 5 and absf(c - (100.0 - 5.0 * WeaponCondition.SHOT_WEAR)) < 0.01,
		"five shots: five rounds gone and the gun worn by them (%.2f)" % c)
	_gun()["wet"] = true
	for i in 5:
		await _fire()
	var wet_wear := c - Wear.cond(_gun())
	check(absf(wet_wear - 5.0 * WeaponCondition.SHOT_WEAR * WeaponCondition.WET_SHOT_X) < 0.01, "a wet gun wears faster (%.2f for five, dry %.2f)" % [wet_wear, 5.0 * WeaponCondition.SHOT_WEAR])
	var before := Wear.cond(_gun())
	WeaponCondition.step_carried(player, 4.0, true)
	check(Wear.cond(_gun()) < before - 0.9 and bool(_gun().get("wet", false)), "four hours in the rain: it rusts (%.2f -> %.2f)" % [before, Wear.cond(_gun())])
	# A worn gun jams; R clears it.
	Wear.set_cond(_gun(), 20.0)
	check(WeaponCondition.jam_chance(20.0) > WeaponCondition.jam_chance(60.0) and WeaponCondition.jam_chance(90.0) == 0.0, "the jam chance rises as the condition falls (%.3f at 20, %.3f at 60, 0 at 90)" % [WeaponCondition.jam_chance(20.0), WeaponCondition.jam_chance(60.0)])
	Wear.force_roll = 0.0
	rounds = player.inventory.rounds_in(&"primary")
	await _fire()
	check(WeaponCondition.jammed(_gun()) and player.inventory.rounds_in(&"primary") == rounds, "a worn gun jams: the shot fails")
	Wear.force_roll = 0.99
	await _fire()
	check(player.inventory.rounds_in(&"primary") == rounds, "jammed, it won't fire")
	Rpg.set_level(player, "firearms", 0)
	check(is_equal_approx(WeaponCondition.clear_s(player), 3.0), "clearing takes 3 s untrained")
	Rpg.set_level(player, "firearms", 3)
	check(is_equal_approx(WeaponCondition.clear_s(player), 1.5), "1.5 s from firearms 3")
	player._server_busy_until = 0.0
	player._server_reload.rpc_id(1, &"primary")
	await get_tree().physics_frame
	check(WeaponCondition.jammed(_gun()) and player._server_busy_until > Soldier._now(), "R starts the clear (busy)")
	await _seconds(1.8)
	check(not WeaponCondition.jammed(_gun()), "and it's cleared")
	await _fire()
	check(player.inventory.rounds_in(&"primary") == rounds - 1, "it fires again")
	# The cleaning kit, with oil.
	player.inventory.take(&"gun_cleaning_kit")
	player.inventory.take(&"gun_oil")
	Wear.set_cond(_gun(), 20.0)
	var at := _index_of(&"gun_cleaning_kit")
	check(at[0] != &"" and Wear.server_use_tool(player, at[0], at[1], true) == "", "Use on the cleaning kit cleans the gun")
	check(absf(Wear.cond(_gun()) - (20.0 + WeaponCondition.CLEAN_ADD + WeaponCondition.OIL_ADD)) < 0.01 and player.inventory.count_of(&"gun_oil") == 0 and not _gun().has("wet"),
		"with the oil: +50, the oil used up, dry (%.0f)" % Wear.cond(_gun()))
	at = _index_of(&"gun_cleaning_kit")
	check(at[0] != &"" and int((player.inventory.containers[at[0]][at[1]] as Dictionary).get("state", {}).get(Wear.USES, 0)) == 9, "the kit has nine cleanings left")
	# Broken.
	Wear.set_cond(_gun(), 0.0)
	rounds = player.inventory.rounds_in(&"primary")
	await _fire()
	check(player.inventory.rounds_in(&"primary") == rounds and WeaponCondition.is_broken(_gun()), "at 0 it's broken and won't fire")
	player.inventory.take(&"gun_repair_kit")
	Rpg.set_level(player, "firearms", 2)
	at = _index_of(&"gun_repair_kit")
	check(at[0] != &"" and Wear.server_use_tool(player, at[0], at[1], true) == "" and is_equal_approx(Wear.cond(_gun()), WeaponCondition.REPAIR_TO), "a gun repair kit (firearms 2) brings it back to 45%")
	await _fire()
	check(player.inventory.rounds_in(&"primary") == rounds - 1, "and it fires")
	check(Wear.tag(ItemDB.get_item(&"m4a1"), _gun()) != "", "the inventory shows its condition (%s)" % Wear.tag(ItemDB.get_item(&"m4a1"), _gun()))


func _test_melee() -> void:
	print("Blades dull, a whetstone, a worn axe")
	_clear_dead()
	player.select_weapon(&"sidearm")
	var knife := player.active_weapon()
	check(knife != null and MeleeWeapons.is_blade(knife), "a knife in hand (%s)" % (knife.id if knife else &"none"))
	if knife == null:
		return
	var st := player.inventory.state_of(player.active_slot)
	Wear.set_cond(st, 100.0)
	check(is_equal_approx(WeaponCondition.server_swing(player), 1.0) and absf(Wear.cond(player.inventory.state_of(player.active_slot)) - (100.0 - WeaponCondition.SWING_WEAR)) < 0.01, "a sharp blade hits full and a swing wears it")
	Wear.set_cond(player.inventory.state_of(player.active_slot), 10.0)
	check(is_equal_approx(WeaponCondition.server_swing(player), WeaponCondition.DULL_MULT), "a dull blade hits softer (x%.1f)" % WeaponCondition.DULL_MULT)
	player.inventory.take(&"whetstone")
	var at := _index_of(&"whetstone")
	check(at[0] != &"" and Wear.server_use_tool(player, at[0], at[1], true) == "" and Wear.cond(player.inventory.state_of(player.active_slot)) > 59.0, "a whetstone sharpens it (%.0f)" % Wear.cond(player.inventory.state_of(player.active_slot)))
	check(is_equal_approx(WeaponCondition.server_swing(player), 1.0), "sharp again, it hits full")
	player.inventory.take(&"hatchet")
	var hs := Wear.carried_state_rw(player.inventory, &"hatchet")
	Wear.set_cond(hs, 100.0)
	var fresh := WeaponCondition.tool_mult(player, "hatchet")
	Wear.set_cond(hs, 0.0)
	check(is_equal_approx(fresh, 1.0) and is_equal_approx(WeaponCondition.tool_mult(player, "hatchet"), WeaponCondition.AXE_SLOW), "a worn-out hatchet fells slower (x%.1f)" % WeaponCondition.tool_mult(player, "hatchet"))
	await get_tree().process_frame


func _test_ammo() -> void:
	print("Ammo: corroded misfires, reloads carry it, rain and a roof")
	_clear_dead()
	check(AmmoCondition.misfire_chance(30.0) > AmmoCondition.misfire_chance(70.0) and AmmoCondition.misfire_chance(95.0) == 0.0, "corroded ammo misfires more than clean (%.2f at 30, %.2f at 70, 0 at 95)" % [AmmoCondition.misfire_chance(30.0), AmmoCondition.misfire_chance(70.0)])
	var duds := [0, 0]
	for i in 400:
		if randf() < AmmoCondition.misfire_chance(30.0):
			duds[0] += 1
		if randf() < AmmoCondition.misfire_chance(100.0):
			duds[1] += 1
	check(duds[0] > 20 and duds[1] == 0, "400 rounds each: %d duds corroded, %d clean" % duds)
	player.select_weapon(&"primary")
	Wear.set_cond(_gun(), 100.0)
	_gun()[AmmoCondition.IN_GUN] = 20.0
	Wear.force_roll = 0.1
	var rounds := player.inventory.rounds_in(&"primary")
	await _fire()
	check(WeaponCondition.jammed(_gun()) and player.inventory.rounds_in(&"primary") == rounds - 1, "a corroded round in the gun: a dud, a click, jammed")
	_gun().erase("jammed")
	_gun().erase(AmmoCondition.IN_GUN)
	await _fire()
	check(not WeaponCondition.jammed(_gun()) and player.inventory.rounds_in(&"primary") == rounds - 2, "clean rounds, the same roll: it fires")
	Wear.force_roll = 0.99
	# A corroded magazine loaded: its condition goes into the gun, and back out on the next.
	_gun()["rounds"] = 0
	for c: StringName in Inventory.CONTAINERS:
		var list: Array = player.inventory.containers.get(c, [])
		for i in range(list.size() - 1, -1, -1):
			if StringName(list[i].id) == &"mag_556":
				player.inventory.remove_entry(c, i, int(list[i].count))
	player.inventory.take(&"mag_556", 1, {"rounds": 30, Wear.KEY: 40.0})
	check(player.inventory.reload(&"primary") == 30 and is_equal_approx(float(_gun().get(AmmoCondition.IN_GUN, 100.0)), 40.0), "reloading a corroded magazine: the gun's rounds are at 40")
	player.inventory.take(&"mag_556", 1, {"rounds": 30})
	_gun()["rounds"] = 1
	player.inventory.reload(&"primary")
	var out_cond := -1.0
	for e: Dictionary in Survival.kit_of(player.inventory):
		if String(e.id) == "mag_556" and int(e.get("state", {}).get("rounds", 30)) == 1:
			out_cond = float(e.state.get(Wear.KEY, 100.0))
	check(not _gun().has(AmmoCondition.IN_GUN) and is_equal_approx(out_cond, 40.0), "a clean one in: the old magazine comes out with its corroded round (%.0f)" % out_cond)
	check(is_equal_approx(AmmoCondition.reloaded_state()[Wear.KEY], 90.0), "hand-loaded rounds are x0.9")
	check(AmmoCondition.words({Wear.KEY: 30.0}, 0) == "" and AmmoCondition.words({Wear.KEY: 30.0}, 2) == "badly corroded", "the firearms skill shows its condition (2: %s)" % AmmoCondition.words({Wear.KEY: 30.0}, 2))
	var rolled := AmmoCondition.weather_loot([{"id": "rounds_556", "count": 20}], null)
	check(float((rolled[0] as Dictionary).get("state", {}).get(Wear.KEY, 100.0)) >= AmmoCondition.DRY_RANGE.x, "found in a dry store, it's good")
	# Rain on a pile in the open, a pile under a roof.
	var open_at := _open_spot(Vector3(6.0, 0.0, 6.0))
	var roof_at := _open_spot(Vector3(-6.0, 0.0, 6.0))
	var roof := StaticBody3D.new()
	roof.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.3, 4.0)
	shape.shape = box
	roof.add_child(shape)
	level.add_child(roof)
	roof.global_position = roof_at + Vector3.UP * 2.6
	var u1 := level.server_spawn_dropped(&"rounds_556", 20, open_at + Vector3.UP * 0.2)
	var u2 := level.server_spawn_dropped(&"rounds_556", 20, roof_at + Vector3.UP * 0.2)
	for i in 30:
		await get_tree().physics_frame
	var dn := DayNight.current()
	var was := dn.weather if dn else ""
	if dn:
		dn.weather = "rain"
	AmmoCondition.step_ground(level, 5.0)
	if dn:
		dn.weather = was
	var outside := _item(u1)
	var inside := _item(u2)
	check(outside != null and Wear.cond(outside.state) < 90.0, "a pile in the rain corrodes (%.0f)" % (Wear.cond(outside.state) if outside else -1.0))
	check(inside != null and Wear.cond(inside.state) >= 99.9, "a pile under a roof keeps (%.0f)" % (Wear.cond(inside.state) if inside else -1.0))
	roof.queue_free()


func _test_clothes() -> void:
	print("Clothes wear, tear and mend; boots and feet")
	var inv := player.inventory
	var worn := Clothing.worn(inv)
	check(not worn.is_empty(), "he wears clothes (%d pieces)" % worn.size())
	var torso := &""
	for slot: StringName in Clothing.TORSO_OUT_IN:
		if StringName(inv.slots.get(slot, &"")) != &"":
			torso = slot
			break
	check(torso != &"", "a torso layer on (%s)" % torso)
	if torso == &"":
		return
	var n := Survival.needs_of(player)
	Wear.set_cond(Wear.slot_state_rw(inv, torso), 100.0)
	ClothingWear.step(player, n, 24.0, {})
	var dur := float(ItemDB.get_item(StringName(inv.slots[torso])).stats.get("durability", 1.0))
	check(absf(Wear.cond(inv.state_of(torso)) - (100.0 - ClothingWear.DAY_WEAR / dur)) < 0.01, "a day worn: it wears (%.2f)" % Wear.cond(inv.state_of(torso)))
	var c := Wear.cond(inv.state_of(torso))
	ClothingWear.step(player, n, 24.0, {"rain": true})
	check(c - Wear.cond(inv.state_of(torso)) > ClothingWear.DAY_WEAR / dur * 1.2, "more in the rain")
	c = Wear.cond(inv.state_of(torso))
	ClothingWear.on_hit(player, Vitals.CHEST)
	check(absf(c - Wear.cond(inv.state_of(torso)) - ClothingWear.TEAR) < 0.01, "a blow to the chest tears it")
	var warm := Clothing.inv_warmth(inv)
	Wear.set_cond(Wear.slot_state_rw(inv, torso), 5.0)
	var torn := Clothing.inv_warmth(inv)
	check(torn < warm or is_equal_approx(warm, 0.0), "torn, it keeps less warmth (%.3f -> %.3f)" % [warm, torn])
	inv.take(&"needle_thread")
	var at := _index_of(&"needle_thread")
	check(at[0] != &"" and Wear.server_use_tool(player, at[0], at[1], true) == "" and Wear.cond(inv.state_of(torso)) > 39.0, "a needle and thread mends it (%.0f)" % Wear.cond(inv.state_of(torso)))
	check(Clothing.inv_warmth(inv) > torn or is_equal_approx(warm, 0.0), "and its warmth comes back (%.3f)" % Clothing.inv_warmth(inv))
	# Boots and feet.
	var stamina := Needs.stamina_mult(n)
	if StringName(inv.slots.get(&"feet", &"")) != &"":
		Wear.set_cond(Wear.slot_state_rw(inv, &"feet"), 5.0)
	ClothingWear.step_feet(n, inv, 4.0, true)
	check(float(n.get("sore_feet", 0.0)) > 0.0 and Needs.stamina_mult(n) < stamina, "worn-out boots on the move: sore feet, stamina down (%.2f -> %.2f)" % [stamina, Needs.stamina_mult(n)])
	ClothingWear.step_feet(n, inv, 24.0, false)
	check(float(n.get("sore_feet", 0.0)) == 0.0, "rest eases them")
	if StringName(inv.slots.get(&"feet", &"")) != &"":
		Wear.set_cond(Wear.slot_state_rw(inv, &"feet"), 100.0)


func _test_vehicle() -> void:
	print("Vehicles: a puncture, a patch, stale fuel")
	_clear_dead()
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer
	check(layer != null, "the zone has a vehicle layer")
	if layer == null:
		return
	var at := level.ground_point(player.global_position + Vector3(12.0, 0.0, 0.0)) + Vector3.UP * 0.6
	var v := layer.server_spawn("matv", Transform3D(Basis.IDENTITY, at))
	for i in 20:
		await get_tree().physics_frame
	check(v != null and VehicleWear.ground_vehicle(v), "a truck")
	if v == null:
		return
	v.server_set_fuel(50.0)
	var w := VehicleWear.of(v)
	check(VehicleWear.stale(v) > 0.0 and VehicleWear.stale(v) < 0.5, "its found fuel is a little stale (%.2f)" % VehicleWear.stale(v))
	var top := v.top_speed()
	VehicleWear.force_roll = 0.0
	VehicleWear.on_moved(v, 10.0, 0.1)
	check(VehicleWear.flat(v) and float(w.km) > 0.0 and float(w.tyres) < 100.0, "driving wears its parts, and a roll punctures a tyre")
	check(v.top_speed() < top * 0.45, "a flat holds it to 40%% (%.1f -> %.1f m/s)" % [top, v.top_speed()])
	VehicleWear.force_roll = -1.0
	player.global_position = v.global_position + Vector3(2.5, 0.0, 0.0)
	player.inventory.take(&"tyre_patch")
	var pat := _index_of(&"tyre_patch")
	check(VehicleWear.flat_near(player) == v and pat[0] != &"" and Wear.server_use_tool(player, pat[0], pat[1], true) == "" and not VehicleWear.flat(v), "a tyre patch fixes it")
	check(is_equal_approx(v.top_speed(), top), "full speed again")
	w["fuel_day"] = float(Survival.day()) - 400.0
	check(is_equal_approx(VehicleWear.stale(v), 1.0), "a year-old tank is stale")
	check(v.server_enter(player, v.driver_seat()), "he gets in to drive")
	VehicleWear.force_roll = 0.0
	VehicleWear.on_moved(v, 0.0, 1.0)
	check(VehicleWear.stalled(v) and not v.can_drive(), "stale fuel: the engine sputters and dies")
	w["stall_until"] = -1.0
	w["fuel_day"] = float(Survival.day())
	VehicleWear.on_moved(v, 0.0, 1.0)
	check(not VehicleWear.stalled(v), "fresh fuel doesn't stall")
	VehicleWear.force_roll = -1.0
	v.server_exit(player)
	check(VehicleWear.report(v).contains("engine"), "the check reads its wear (%s)" % VehicleWear.report(v))
	await get_tree().physics_frame


## A spot near him with open sky above (no tree or roof within Throwables.INDOOR_CEILING_M).
func _open_spot(off: Vector3) -> Vector3:
	for i in 24:
		var p := level.ground_point(player.global_position + off.rotated(Vector3.UP, i * 0.5) * (1.0 + i * 0.15))
		if not Throwables.indoors(player.get_world_3d(), p + Vector3.UP * 0.2):
			return p
	return level.ground_point(player.global_position + off)


func _item(uid: String) -> WorldItem:
	for node in level.items.get_children():
		if node is WorldItem and (node as WorldItem).uid == uid:
			return node as WorldItem
	return null


func _index_of(id: StringName) -> Array:
	for c: StringName in Inventory.CONTAINERS:
		var list: Array = player.inventory.containers.get(c, [])
		for i in list.size():
			if StringName(list[i].id) == id:
				return [c, i]
	return [&"", -1]


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	Wear.force_roll = -1.0
	Wear.tick_off = false
	VehicleWear.force_roll = -1.0
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("WEAR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
