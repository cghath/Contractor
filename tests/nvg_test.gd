extends Node
## NVGs (wave 7, S2; Nvg, NvgView). On the vehicle range, the host's player:
## - has the NVG key (U, rebindable) and three NVGs by generation, priced;
## - without a helmet, the key tells him to put one on; with one, it mounts the NVG he
##   carries and lowers it: the helmet's state holds it, it gives back its generation's share of
##   the darkness penalty (Nvg.restores), and his own view turns green (NvgView);
## - the key again raises it: restores 0, the view plain;
## - lowered, the battery drains (the host charges it a step at a time); flat, the goggles
##   stay down but show nothing and restore nothing;
## - restores by generation (gen 1 0.6, gen 2 0.8, gen 3 0.9), 0 raised, flat or with none;
## - the NVG and its charge survive the helmet coming off and going back on, being taken off
##   and mounted again, and a save and load of the inventory (JSON, as the zone saves it).
##   <godot> --headless --path . res://tests/nvg_test.tscn

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_nvg" + tag
	Campaign.campaign_id = "test_nvg" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("NVG TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the vehicle range")
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test drives the battery drain itself
	await _frame()
	_run()
	_finish()


func _run() -> void:
	var inv := player.inventory
	print("Items and the key")
	for gen in [1, 2, 3]:
		var item := ItemDB.get_item(StringName("nvg_gen%d" % gen))
		check(item != null and Nvg.is_nvg(item) and int(item.stats.nvg_gen) == gen and Nvg.capacity_h(item) > 0.0
			and Prices.price_of(item.id) >= 3000 and Prices.price_of(item.id) <= 9000,
			"nvg_gen%d: an NVG, gen %d, a battery, priced %d" % [gen, gen, Prices.price_of(item.id) if item else 0])
	check(not Nvg.is_nvg(ItemDB.get_item(&"helmet")), "a helmet isn't an NVG")
	var keys: Array = Controls.KEYS.get(&"nvg_toggle", [])
	var clash := Controls.KEYS.keys().filter(func(a: StringName) -> bool: return a != &"nvg_toggle" and KEY_U in Controls.KEYS[a])
	check(InputMap.has_action(&"nvg_toggle") and keys == [KEY_U] and clash.is_empty()
		and GameSettings.BINDABLE.any(func(p: Array) -> bool: return p[0] == &"nvg_toggle"),
		"the NVG key: U, on no other action, rebindable")
	check(player.get_node_or_null(^"NvgView") is NvgView, "the local player has the NVG view")
	var view := player.get_node_or_null(^"NvgView") as NvgView

	print("Mounting and lowering")
	var helmet_id := &"helmet"
	if inv.slots[&"helmet"] != &"":
		inv.unequip(&"helmet")
	check(inv.take(&"nvg_gen2") == 1, "a Gen 2 NVG goes into his containers")
	check(Nvg.restores(player) == 0.0 and not Nvg.is_lowered(player), "carried, not mounted: restores 0")
	check(player.server_toggle_nvg().contains("helmet") and Nvg.mounted_state(inv).is_empty(), "no helmet: the key says put one on")
	check(inv.take(helmet_id) == 1 and inv.slots[&"helmet"] == helmet_id, "the helmet goes on")
	var said := player.server_toggle_nvg()
	check(Nvg.mounted(inv) != null and Nvg.mounted(inv).id == &"nvg_gen2" and Nvg.is_lowered(player) and inv.count_of(&"nvg_gen2") == 0,
		"the key mounts the carried NVG on the helmet and lowers it (%s)" % said)
	check(inv.state_of(&"helmet").has(Nvg.STATE_KEY) and inv.net_state.slot_state.helmet.has(Nvg.STATE_KEY),
		"it's in the helmet's state, and in the replicated snapshot")
	check(is_equal_approx(Nvg.restores(player), 0.8) and Nvg.is_on(player) and is_equal_approx(Nvg.fov_of(player), 45.0),
		"lowered gen 2: restores 0.8, a 45 deg tube (%.2f)" % Nvg.restores(player))
	view.update()
	check(view.rect.visible, "his view goes green")
	var mat := view.rect.material as ShaderMaterial
	check(float(mat.get_shader_parameter(&"tube")) >= NvgView.FULL_SCREEN and is_equal_approx(float(mat.get_shader_parameter(&"gain")), 110.0),
		"v0.7.1: the picture fills the screen, at the gen 2's own gain (%.0f)" % float(mat.get_shader_parameter(&"gain")))
	var r := NvgView.tube_radius(45.0, 75.0)
	check(r > 0.4 and r < 0.6 and NvgView.tube_radius(50.0, 75.0) > r, "the tube is narrower than the view, wider by generation (%.2f)" % r)
	said = player.server_toggle_nvg()
	check(not Nvg.is_lowered(player) and Nvg.restores(player) == 0.0 and Nvg.fov_of(player) == 0.0, "the key again raises it: restores 0 (%s)" % said)
	view.update()
	check(not view.rect.visible, "his view is plain again")

	print("Battery")
	player.server_toggle_nvg()
	var full := Nvg.seconds_left(inv)
	check(is_equal_approx(full, 10.0 * 3600.0) and is_equal_approx(Nvg.battery_fraction(inv), 1.0), "a full gen 2 battery: 10 h (%.0f s)" % full)
	var rev: int = inv.net_gear.get("rev", 0)
	player._drain_nvg(4.0)
	player._drain_nvg(4.0)
	check(is_equal_approx(Nvg.seconds_left(inv), full) and inv.net_gear.get("rev", 0) == rev, "short of a step, nothing is charged or sent yet")
	player._drain_nvg(4.0)
	check(is_equal_approx(Nvg.seconds_left(inv), full - 12.0), "a step's worth is charged at once (%.1f s used)" % (full - Nvg.seconds_left(inv)))
	player.server_toggle_nvg()  # up
	player._drain_nvg(30.0)
	check(is_equal_approx(Nvg.seconds_left(inv), full - 12.0), "raised, it doesn't drain")
	player.server_toggle_nvg()  # down
	check(not Nvg.server_drain(inv, 3600.0) and is_equal_approx(Nvg.battery_fraction(inv), (full - 12.0 - 3600.0) / full),
		"an hour lowered takes an hour off (%d%%: %s)" % [roundi(Nvg.battery_fraction(inv) * 100.0), Nvg.label(inv)])
	player._drain_nvg(Nvg.seconds_left(inv) + 1.0)
	check(Nvg.seconds_left(inv) == 0.0 and Nvg.is_lowered(player) and not Nvg.is_on(player) and Nvg.restores(player) == 0.0,
		"run flat, it stays down but restores nothing")
	view.update()
	check(not view.rect.visible, "flat: no green view")
	check(player.server_toggle_nvg() == "NVG up" and player.server_toggle_nvg().contains("flat"), "lowering a flat one says so")

	print("By generation, and moving it")
	check(Nvg.server_remove(inv) == "" and Nvg.mounted_state(inv).is_empty() and inv.count_of(&"nvg_gen2") == 1,
		"taken off, it goes into his containers")
	var at := Nvg.first_carried(inv)
	check(not at.is_empty() and Nvg.battery_of(ItemDB.get_item(&"nvg_gen2"), inv.containers[at[0]][at[1]].get("state", {})) == 0.0,
		"stowed, it keeps its (flat) charge")
	for want: Array in [[&"nvg_gen1", 0.6], [&"nvg_gen3", 0.9]]:
		inv.take(want[0])
		var spot := _carried(inv, want[0])
		check(Nvg.server_mount(inv, spot[0], spot[1]) == "" and Nvg.mounted(inv).id == want[0] and Nvg.restores(player) == 0.0,
			"%s mounted raised: restores 0" % want[0])
		Nvg.server_set_lowered(inv, true)
		check(is_equal_approx(Nvg.restores(player), want[1]), "%s lowered: restores %.1f" % [want[0], want[1]])
	check(inv.count_of(&"nvg_gen1") == 1, "the gen 1 it replaced went back into his containers")
	Nvg.server_drain(inv, 1800.0)
	var left := Nvg.seconds_left(inv)
	var removed := inv.unequip(&"helmet")
	check(Nvg.restores(player) == 0.0 and removed.state.has(Nvg.STATE_KEY), "the helmet off: no NVG view, the NVG goes with the helmet")
	check(inv.take(removed.id, 1, removed.state) == 1 and Nvg.mounted(inv).id == &"nvg_gen3" and is_equal_approx(Nvg.seconds_left(inv), left)
		and Nvg.is_on(player), "back on: the gen 3 still on it, down, its charge kept")
	var saved: Variant = JSON.parse_string(JSON.stringify(Roster.json_safe(inv.net_state.duplicate(true))))
	var loaded := Inventory.new()
	loaded.net_state = GameState.from_json(saved)
	var s := Nvg.mounted_state(loaded)
	check(not s.is_empty() and String(s.id) == "nvg_gen3" and bool(s.lowered) and is_equal_approx(float(s.battery_h) * 3600.0, left),
		"saved and loaded (JSON): the gen 3, down, its charge (%s)" % str(s))
	loaded.free()
	inv.remove_one(&"nvg_gen1")
	inv.remove_one(&"nvg_gen2")
	var why := Nvg.server_remove(inv)
	check(why == "" and Nvg.restores(player) == 0.0 and inv.count_of(&"nvg_gen3") == 1, "taken off again: restores 0, it's in his containers (%s)" % why)

	print("Batteries (items expansion)")
	var gen3 := ItemDB.get_item(&"nvg_gen3")
	var at3 := _carried(inv, &"nvg_gen3")
	check(Nvg.battery_of(gen3, inv.containers[at3[0]][at3[1]].get("state", {})) < Nvg.capacity_h(gen3), "the stowed gen 3 is part used")
	inv.take(&"battery_aa", 2)
	var b := _carried(inv, &"battery_aa")
	player._server_inventory_action.rpc_id(1, "consume", b[0], b[1], &"", &"")
	at3 = _carried(inv, &"nvg_gen3")
	check(is_equal_approx(Nvg.battery_of(gen3, inv.containers[at3[0]][at3[1]].get("state", {})), Nvg.capacity_h(gen3)) and inv.count_of(&"battery_aa") == 1,
		"Use on AA batteries (the inventory's action): the stowed gen 3 back to full, one pack used")
	b = _carried(inv, &"battery_aa")
	check(Consumables.server_use(player, b[0], b[1]) == "No NVG needs a battery" and inv.count_of(&"battery_aa") == 1, "with nothing part used, a battery isn't spent")
	check(Nvg.server_mount(inv, at3[0], at3[1], true) == "" and Nvg.mounted(inv) == gen3, "the gen 3 back on the helmet")
	Nvg.server_drain(inv, 7200.0)
	check(Nvg.battery_fraction(inv) < 1.0, "two hours down (%s)" % Nvg.label(inv))
	inv.take(&"battery_cr123")
	b = _carried(inv, &"battery_cr123")
	check(Consumables.server_use(player, b[0], b[1]) == "" and is_equal_approx(Nvg.battery_fraction(inv), 1.0) and inv.count_of(&"battery_cr123") == 0,
		"a CR123A pack in the mounted gen 3: full again (%s), the pack used" % Nvg.label(inv))


func _carried(inv: Inventory, id: StringName) -> Array:
	for c in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if list[i].id == id:
				return [c, i]
	return [&"", -1]


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("NVG TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _frame() -> void:
	await get_tree().process_frame
