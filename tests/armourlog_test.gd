extends Node
## Headless checks for combined arms A8 (cg_brief queue item 2.6; docs/combined_arms.md 2.2.2,
## 2.4.5, 2.8.3, 2.9, 9.3): logistics and armour packages, in the real compound. The round items,
## their prices and the packages' (the MaxxPro appliqué's 40,000); firing drawing real items from
## the racks; rearming by hand, from a truck's hold (twice as fast), from a pallet on the ground and
## from the hold by a crewman, with its times and conditions (stopped, a man at the cargo point,
## the right rack, a pause under fire); smoke salvos into the stowage; rounds out as items; each
## field repair and its limits (two men or one alone, the workshop's modules, progress kept), the
## kill states clearing; ERA tiles from the spares; the FOB's per-module quote and service, the
## load-out rearm and its bill; packages fitted and removed at the motor pool for price and days,
## keeping their STANAG ratings and costing speed and fuel; the tow (recovery's stand-in); fuel
## from a drum pallet; the helicopter's armour load; the API A9 reads; save and load; the cost of
## it all; then a second process joins over ENet and finds the packages, tiles, racks, salvos, the
## jobs and the tow as the host has them.
##   <voxel godot exe> --headless --path . res://tests/armourlog_test.tscn
## The host starts the client itself ("-- --armourlog-join"). Exits with the number of failures.

## Budgets (Proposed; 9.3 gives A8 none): a vehicle's logistics tick, what the menu asks.
const TICK_BUDGET_MS := 0.05
const NEEDS_BUDGET_MS := 0.3
const MENU_BUDGET_MS := 3.0
## Locally under load, this much slack.
const LOCAL_SLACK := 3.0

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _n := 0
var _tag := ""


func _ready() -> void:
	_tag = OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_armourlog" + _tag  # never touch a real save
	Campaign.campaign_id = "test_armourlog" + _tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_armourlog_settings%s.cfg" % _tag))  # never the player's
	GameSettings.reset_all()
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--armourlog-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(700.0).timeout.connect(func() -> void:
		print("ARMOURLOG TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_data()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	layer = VehicleLayer.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	player.global_position = Vector3(0, 0.1, 0)
	Vehicle.fire_rolls = false
	for model: String in ["abrams", "bradley", "matv", "maxxpro", "technical"]:
		VehicleHull.prewarm(model)
	if _want("fire"):
		await _test_fire_draws()
	if _want("rearm"):
		await _test_rearm()
		await _test_smoke_and_unstow()
	if _want("repair"):
		await _test_field_repairs()
		await _test_tiles()
	if _want("fob"):
		await _test_fob()
		await _test_packages()
	if _want("tow"):
		await _test_tow()
	if _want("fuel"):
		await _test_fuel()
		await _test_heli_load()
	if _want("save"):
		await _test_save()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	GameState.delete_save()
	Campaign.reset_campaign()
	GameSettings.reset_all()
	GameSettings.use_file("")
	print("ARMOURLOG TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_ARMOURLOG_ONLY="rearm,tow" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_ARMOURLOG_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Data (pure) ---------------------------------------------------------------------------------

func _test_data() -> void:
	print("Round items, prices, packages, the repair table (pure)")
	var rounds := {"round_120_m829a3": ["m829a3", 1, 10.0], "round_120_m830a1": ["m830a1", 1, 10.0], "round_120_m1147": ["m1147", 1, 10.0],
		"links_25_m791": ["m791", 50, 15.0], "links_25_m919": ["m919", 50, 15.0], "links_25_m792": ["m792", 50, 15.0], "tow_2a": ["tow2a", 1, 30.0],
		"can_40_m430": ["m430a1", 48, 15.0]}
	var off := PackedStringArray()
	for id: String in rounds:
		var r: Array = rounds[id]
		var sid := StringName(id)
		if VehicleLogistics.item_shell(sid) != String(r[0]) or VehicleLogistics.per_item(sid) != int(r[1]) or not is_equal_approx(VehicleLogistics.stow_s(sid), float(r[2])) \
				or Shells.shell(String(r[0])).is_empty() or VehicleLogistics.round_item(String(r[0])) != sid:
			off.append(id)
		if Prices.price_of(sid) != int(r[1]) * VehicleLogistics.round_price(String(r[0])):
			off.append("%s price %d" % [id, Prices.price_of(sid)])
	check(off.is_empty() and ItemDB.get_item(&"round_120_m829a3").two_handed and is_equal_approx(ItemDB.get_item(&"round_120_m829a3").mass_kg, 21.0)
		and ItemDB.get_item(&"tow_2a").two_handed and is_equal_approx(ItemDB.get_item(&"tow_2a").mass_kg, 29.0),
		"rounds are items (2.9.2): 120 mm rounds one each (21 kg, two hands), 25 mm cans of 50, TOWs (29 kg), Mk19 cans of 48; 10 / 15 / 30 s each; priced per round (%s)" % ", ".join(off))
	var ammo: Dictionary = Prices.data().get("ammo", {})
	check(int(ammo.m829a3) == 1100 and int(ammo.m830a1) == 800 and int(ammo.m1147) == 900 and int(ammo.m791) == 45 and int(ammo.m919) == 70 and int(ammo.m792) == 30
		and int(ammo.tow2a) == 9000 and int(ammo.m430a1) == 40 and int(ammo.m33) == 6 and int(ammo.m8_api) == 9, "2.9.2's prices a round")
	check(VehicleLogistics.is_salvo(&"smoke_salvo") and Prices.price_of(&"smoke_salvo") > 0 and Prices.for_sale(&"smoke_salvo") and Prices.for_sale(&"round_120_m829a3")
		and not Prices.for_sale(&"round_125_3bm42") and Prices.price_of(&"round_125_3bm42") > 0, "smoke salvos and our rounds in the shop; the enemy's 125 mm loot, sell-only")
	var pal_ok := true
	for id: StringName in [&"pallet_ammo_120", &"pallet_ammo_25", &"pallet_ammo_tow", &"pallet_smoke"]:
		var load := VehicleLogistics.pallet_load(id, {})
		var worth := 300
		for k: String in load:
			worth += int(load[k]) * Prices.price_of(StringName(k))
		pal_ok = pal_ok and not load.is_empty() and Prices.price_of(id) == worth and Pallets.kind_def(VehicleLogistics.pallet_kind(id)).has("load")
	check(pal_ok and VehicleLogistics.pallet_load(&"pallet_ammo_120", {}) == {"round_120_m829a3": 6, "round_120_m830a1": 4, "round_120_m1147": 2}
		and is_equal_approx(VehicleLogistics.pallet_fuel(&"pallet_fuel_drums", {}), 832.0), "a pallet per calibre in data/pallets.json, priced as its load plus the pallet; the drums 832 L")
	var pk: Dictionary = Prices.data().get("packages", {})
	var unpriced := PackedStringArray()
	for m: String in ["abrams", "bradley", "aav7", "matv", "maxxpro"]:
		for p: String in (VehicleSpecs.spec(m).get("packages", {}) as Dictionary):
			if not pk.has(p):
				unpriced.append(p)
	check(unpriced.is_empty() and int(pk.maxxpro_applique) == 40000 and int(pk.matv_applique) == 35000 and int(pk.tusk1) == 180000 and int(pk.trophy) == 400000
		and int(pk.m919) == 0, "every package priced (2.4.5; the MaxxPro appliqué $40,000, cg_brief 2.0; unpriced %s)" % [unpriced])
	var mx := VehicleSpecs.spec("maxxpro")
	var w := VehicleLogistics.weight_mults(mx, ["maxxpro_applique"])
	check(_near(float(w.speed), sqrt(14500.0 / 15400.0), 0.0001) and _near(float(w.accel), 14500.0 / 15400.0, 0.0001) and _near(float(w.fuel), 15400.0 / 14500.0, 0.0001)
		and _near(VehicleLogistics.added_t(VehicleSpecs.spec("abrams"), ["tusk2"]), 4.0, 0.001),
		"weight costs (2.4.5): the appliqué's 0.9 t on 14.5 t: speed x%.3f, accel x%.3f, fuel x%.3f; TUSK II 4.0 t, its TUSK I not counted twice" % [w.speed, w.accel, w.fuel])
	# STANAG ratings kept with the packages (ArmourStandards: stored and proven from the plates).
	var base := ArmourStandards.rating(mx)
	var app := ArmourStandards.rating(mx, ["maxxpro_applique"])
	var proven := ["front", "side", "rear"].all(func(arc: String) -> bool: return ArmourStandards.ke_proven(mx, arc, ["maxxpro_applique"]) == 3)
	check(_ke(base) == [2, 2, 2] and _ke(app) == [3, 3, 3] and proven and int(app.artillery) == 5,
		"the MaxxPro appliqué's STANAG rating: KE 3 all round, artillery 5, as its plates prove (base KE 2)")
	var tusk := ArmourStandards.rating(VehicleSpecs.spec("abrams"), ["tusk1"])
	check(String(tusk.mine.wheel) == "4a" and String(ArmourStandards.mine_proven(VehicleSpecs.spec("abrams"), ["tusk1"]).wheel) == "4a", "TUSK I: mine 4a under the tracks, proven")
	# The load-outs and F-247's M919.
	var ab := VehicleLogistics.loadout_racks(VehicleSpecs.spec("abrams"), "", [])
	var m919 := VehicleLogistics.loadout_racks(VehicleSpecs.spec("bradley"), "standard", ["m919"])
	check(ab == VehicleWeapons.default_racks(VehicleSpecs.spec("abrams")) and (m919.rack_25 as Dictionary).has("m919") and not (m919.rack_25 as Dictionary).has("m791")
		and int(m919.ready_25.m919) == 70, "the standard load-out is the racks' default; with the M919 package the AP rounds come as M919 (F-247)")
	var lo_ok := true
	for m: String in ["abrams", "bradley"]:
		for lo: String in VehicleLogistics.loadouts(VehicleSpecs.spec(m)):
			var racks := VehicleLogistics.loadout_racks(VehicleSpecs.spec(m), lo, [])
			for r: String in racks:
				var cap := 0
				for mod: Dictionary in VehicleModules.layout_of(m, VehicleSpecs.spec(m)):
					if String(mod.id) == r:
						cap = int(mod.rounds)
				lo_ok = lo_ok and VehicleWeapons._sum(racks[r]) == cap
	check(lo_ok, "every load-out fills each rack to its module's count")
	var track: Array = VehicleLogistics.repair_rules("track")
	var wheel: Array = VehicleLogistics.repair_rules("wheel")
	var engine: Array = VehicleLogistics.repair_rules("engine")
	check(track.size() == 1 and StringName(track[0].item) == &"track_links" and is_equal_approx(float(track[0].s), 180.0) and is_equal_approx(float(track[0].solo_x), 2.0)
		and VehicleModules.DESTROYED in (track[0].states as Array) and is_equal_approx(float(track[0].to), 0.6)
		and is_equal_approx(float(wheel[0].s), 25.0) and is_equal_approx(float(wheel[0].solo_x), 1.0)
		and engine.any(func(r: Dictionary) -> bool: return StringName(r.item) == &"repair_kit" and is_equal_approx(float(r.s), 90.0) and not VehicleModules.DESTROYED in (r.states as Array))
		and VehicleLogistics.fob_only("breech") and VehicleLogistics.fob_only("structure") and VehicleLogistics.fob_only("fcs") and not VehicleLogistics.fob_only("track"),
		"2.2.2's field column: track links 180 s with two (360 alone), a wheel 25 s, the engine damaged only (90 s), to 60%; breech, FCS, structure the workshop's")


# --- Firing draws on the racks' items -------------------------------------------------------------

func _test_fire_draws() -> void:
	print("Firing draws real items from the racks (2.9.2, F-247)")
	var v := await _spawn("abrams", Vector3(-60, 0, 40), 0.0)
	var crew := await _crew(v, [1, 3])
	var lg := v.logistics
	v.turret.aim(0.0, deg_to_rad(15.0))
	v.turret.settle()
	var before := _items_of(lg.rack_items("ammo_rack_bustle"), &"round_120_m829a3")
	var aboard := int(lg.ammo_aboard().get("m829a3", 0))
	var r := v.weapons.server_fire(crew[0], "main")
	await _until(func() -> bool: return v.weapons.loaded("main") != "", 10.0)
	var after := _items_of(lg.rack_items("ammo_rack_bustle"), &"round_120_m829a3")
	check(bool(r.ok) and before == 15 and after == 14 and int(lg.ammo_aboard().get("m829a3", 0)) == aboard - 1,
		"a sabot fired: the loader takes the next from the bustle, 15 -> 14 M829A3 rounds there, %d -> %d aboard" % [aboard, int(lg.ammo_aboard().get("m829a3", 0))])
	await _clear(v, crew)
	var b := await _spawn("bradley", Vector3(-60, 0, 60), 0.0)
	var bc := await _crew(b, [1, 2])
	b.turret.aim(0.0, deg_to_rad(15.0))
	b.turret.settle()
	var ready := b.logistics.rack_items("ready_25")
	var ok := bool(b.weapons.server_fire(bc[0], "main").ok)
	var now := b.logistics.rack_items("ready_25")
	var e0 := _entry_of(ready, &"links_25_m791")
	var e1 := _entry_of(now, &"links_25_m791")
	check(ok and int(e0.count) == 1 and int(e0.loose) == 20 and int(e1.count) == 1 and int(e1.loose) == 19,
		"a 25 mm round fired: the AP box is one can of 50 and 20 loose, then 19 (%s -> %s)" % [e0, e1])
	await _clear(b, bc)


# --- Rearming --------------------------------------------------------------------------------------

func _test_rearm() -> void:
	print("Rearming: by hand, from a truck, a pallet, the hold (2.9.2)")
	var v := await _spawn("abrams", Vector3(-30, 0, 40), 0.0)
	var lg := v.logistics
	var w := v.weapons
	w.server_take_rounds("ammo_rack_bustle", "m829a3", 6)
	var bustle := w.rack_total("ammo_rack_bustle")
	player.inventory.strip()
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"round_120_m829a3")
	_stand_at_cargo(v)
	await _physics(2)
	check(v.in_reach(player) and lg.rack_for(&"round_120_m829a3") == "ammo_rack_bustle" and lg.stow_problem(&"round_120_m829a3") == ""
		and lg.stow_problem(&"links_25_m791") != "", "an M829A3 goes into the bustle; a 25 mm can doesn't fit an Abrams (%s)" % lg.stow_problem(&"links_25_m791"))
	var srcs := lg.rearm_sources(player)
	check(srcs.size() == 1 and String(srcs[0].key) == VehicleLogistics.HANDS and int((srcs[0].items as Dictionary).get("round_120_m829a3", 0)) == 1,
		"at the cargo point with a round in his hands: Rearm from your kit (%s)" % [srcs.map(func(s: Dictionary) -> String: return s.label)])
	v.linear_velocity = Vector3(2.0, 0, 0)
	check(lg.stow_problem(&"round_120_m829a3") == "Stop first", "moving: \"Stop first\"")
	v.linear_velocity = Vector3.ZERO
	check(v.server_start_job(player, "stow", &"hands", &"") == "" and _near(v.job_left(player), 10.0, 0.3), "a 120 mm round by hand: %.1f s (10)" % v.job_left(player))
	await _seconds(0.4)
	player.threat_time = Soldier._now()  # fired at
	await _seconds(0.6)
	var job := lg.job_of(player)
	var held := float(job.get("done", 0.0))
	await _seconds(0.6)
	check(String(job.get("paused", "")) == "under fire" and is_equal_approx(float(job.get("done", 0.0)), held), "under fire, the job waits (%s)" % String(job.get("paused", "")))
	player.threat_time = -1000.0
	job.done = float(job.need) - 0.05
	await _seconds(0.5)
	check(lg.job_of(player).is_empty() and w.rack_total("ammo_rack_bustle") == bustle + 1 and player.inventory.hands == &"",
		"stowed: the bustle %d -> %d, his hands empty" % [bustle, w.rack_total("ammo_rack_bustle")])
	# From a truck's hold (the HEMTT stand-in): twice hand speed, within 8 m.
	var truck := await _spawn("matv", Vector3(-30, 0, 47.5), 90.0)
	truck.cargo_hold.take(&"round_120_m830a1", 3)
	await _physics(2)
	srcs = lg.rearm_sources(player)
	var from_truck: Array = srcs.filter(func(s: Dictionary) -> bool: return String(s.key) == "v:" + truck.vehicle_id)
	check(from_truck.size() == 1 and _near(float(from_truck[0].mult), 2.0, 0.001) and lg._gap(truck) <= 8.0, "an M-ATV with rounds in its hold %.1f m off: a source at twice hand speed" % lg._gap(truck))
	w.server_take_rounds("ammo_rack_bustle", "m830a1", 3)
	check(v.server_start_job(player, "stow", StringName("v:" + truck.vehicle_id), &"") == "" and _near(v.job_left(player), 5.0, 0.3), "from the truck: %.1f s a round (5)" % v.job_left(player))
	for i in 3:
		var j := lg.job_of(player)
		if j.is_empty():
			break
		j.done = float(j.need) - 0.05
		await _seconds(0.4)
	check(lg.job_of(player).is_empty() and truck.cargo_hold.count_of(&"round_120_m830a1") == 0 and int(w.rack_contents("ammo_rack_bustle").get("m830a1", 0)) == 10,
		"the job carries on round by round until the truck's three are stowed (10 HEAT back in the bustle)")
	# From a pallet on the ground, at hand speed.
	await _clear(truck, [])
	_stand_at_cargo(v)
	w.server_take_rounds("ammo_rack_bustle", "m1147", 2)
	var uid := VehicleLogistics.server_drop_pallet(level, &"pallet_ammo_120", level.ground_point(v.global_transform * Vector3(4.5, 0, 3.0)) + Vector3.UP * 0.3)
	var far_uid := VehicleLogistics.server_drop_pallet(level, &"pallet_ammo_120", level.ground_point(v.global_position + Vector3(0, 0, -30)) + Vector3.UP * 0.3)
	await _seconds(1.0)
	srcs = lg.rearm_sources(player)
	var pal: Array = srcs.filter(func(s: Dictionary) -> bool: return String(s.key) == "w:" + uid)
	check(pal.size() == 1 and srcs.all(func(s: Dictionary) -> bool: return String(s.key) != "w:" + far_uid) and _near(float(pal[0].mult), 1.0, 0.001),
		"a 120 mm pallet within 8 m is a source at hand speed; one 30 m off isn't")
	check(v.server_start_job(player, "stow", StringName("w:" + uid), &"round_120_m1147") == "" and _near(v.job_left(player), 10.0, 0.3), "an AMP round from the pallet: 10 s")
	for i in 2:
		var j2 := lg.job_of(player)
		if j2.is_empty():
			break
		j2.done = float(j2.need) - 0.05
		await _seconds(0.4)
	var wi := lg._world_item(uid)
	check(wi != null and int(VehicleLogistics.pallet_load(wi.item_id, wi.state).get("round_120_m1147", 0)) == 0 and int(w.rack_contents("ammo_rack_bustle").get("m1147", 0)) == 8
		and GameState.dropped.has(uid) and int((((GameState.dropped[uid] as Dictionary).get("state", {}) as Dictionary).get("load", {}) as Dictionary).get("round_120_m1147", -1)) == 0,
		"the pallet's two AMP rounds stowed; what it has left rides in its state and the zone save")
	var racks_full := lg.stow_problem(&"round_120_m829a3")
	check(racks_full == "The racks are full" or w.rack_room("ammo_rack_bustle") + w.rack_room("ammo_rack_hull") > 0,
		"full racks take no more (%s)" % racks_full)
	# A crewman stows from the hold from his seat.
	w.server_take_rounds("ammo_rack_hull", "m829a3", 1)
	v.cargo_hold.take(&"round_120_m829a3", 1)
	var loader := (await _crew(v, [3]))[0] as Soldier
	check(v.server_start_job(loader, "stow", &"hold", &"") == "" and _near(v.job_left(loader), 10.0, 0.3), "the loader stows a round from the hold from his seat: 10 s")
	var lj := lg.job_of(loader)
	lj.done = float(lj.need) - 0.05
	await _seconds(0.5)
	check(v.cargo_hold.count_of(&"round_120_m829a3") == 0 and lg.job_of(loader).is_empty(), "from the hold into the racks")
	var far := (await _men(1, v.global_position + Vector3(20, 0, 0)))[0] as Soldier
	check(not v.in_reach(far), "a man 20 m off can't rearm it (the cargo point's reach)")
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if (n as WorldItem).uid in [uid, far_uid]:
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	await _clear(v, [loader, far])


func _test_smoke_and_unstow() -> void:
	print("Smoke salvos into the stowage; rounds out as items (2.9.2, 2.9.3)")
	var v := await _spawn("bradley", Vector3(-30, 0, 70), 0.0)
	var lg := v.logistics
	var sm := v.smoke
	sm.stowed = [0, 0]
	sm._publish()
	player.inventory.strip()
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"smoke_salvo", 3)
	_stand_at_cargo(v)
	await _physics(2)
	check(sm.stow_room() == 2 and lg.rack_for(&"smoke_salvo") == VehicleLogistics.SMOKE_RACK, "the M257's stowage takes two salvos (4 grenades a side, 2 a salvo)")
	check(v.server_start_job(player, "stow", &"hands", &"smoke_salvo") == "" and _near(v.job_left(player), 10.0, 0.3), "a salvo: 10 s")
	for i in 3:
		var j := lg.job_of(player)
		if j.is_empty():
			break
		j.done = float(j.need) - 0.05
		await _seconds(0.4)
	check(sm.stowed[0] == 4 and sm.stowed[1] == 4 and player.inventory.count_of(&"smoke_salvo") == 1 and sm.stowed_salvos() == 2,
		"two salvos in (%s), the third kept: the stowage is full" % [sm.stowed])
	sm.loaded = [0, 0]
	var crew := await _crew(v, [1])
	check(sm.server_reload(crew[0]) == "", "and the crew reloads the dischargers from it as before")
	# A TOW out of the rack, as an item, into his hands.
	player.inventory.strip()
	var tow_before := v.weapons.rack_total("rack_tow")
	check(v.server_start_job(player, "unstow", &"rack_tow", &"tow_2a") == "" and _near(v.job_left(player), 30.0, 0.3), "a TOW out of the rack: 30 s")
	var j2 := lg.job_of(player)
	j2.done = float(j2.need) - 0.05
	await _seconds(0.5)
	check(player.inventory.hands == &"tow_2a" and v.weapons.rack_total("rack_tow") == tow_before - 1, "a TOW-2A in his hands, the rack %d -> %d" % [tow_before, v.weapons.rack_total("rack_tow")])
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	await _clear(v, crew)


# --- Field repairs -----------------------------------------------------------------------------------

func _test_field_repairs() -> void:
	print("Field repairs by module and their limits (2.2.2, 2.9.3)")
	var v := await _spawn("abrams", Vector3(30, 0, 40), 0.0)
	var lg := v.logistics
	var mods := v.modules
	player.inventory.strip()
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"track_links")
	_stand_at_service(v)
	mods.server_set("track_l", 0.0)
	await _seconds(0.7)
	check(mods.kill_state().mobility, "a thrown left track: a mobility kill")
	var opts: Array = lg.repair_options(player).filter(func(o: Dictionary) -> bool: return String(o.module) == "track_l")
	check(opts.size() == 1 and String(opts[0].label) == "Track Links: left track" and String(opts[0].why) == "" and _near(float(opts[0].s), 360.0, 0.5),
		"the service point offers Track Links: left track, 360 s alone (%s)" % [opts])
	check(v.server_start_job(player, "repair_module", &"track_l", &"track_links") == "" and _near(v.job_left(player), 360.0, 1.0), "alone: %.0f s (180 x 2)" % v.job_left(player))
	var helper := (await _men(1, player.global_position + Vector3(1.5, 0, 0)))[0] as Soldier
	helper.global_position = player.global_position + Vector3(1.5, 0, 0)
	await _seconds(0.6)
	check(_near(v.job_left(player), 180.0, 2.0), "a second man beside him: %.0f s (180)" % v.job_left(player))
	var job := lg.job_of(player)
	job.done = 90.0
	await _seconds(0.4)
	player.global_position += Vector3(4, 0, 0)  # walks off half way
	await _seconds(0.5)
	check(lg.job_of(player).is_empty() and _near(float(lg.progress.get("m:track_l", 0.0)), 90.0, 1.0) and player.inventory.count_of(&"track_links") == 1,
		"walking off stops it; the work done stays on the track (%.0f s), the links kept" % float(lg.progress.get("m:track_l", 0.0)))
	_stand_at_service(v)
	await _physics(2)
	check(v.server_start_job(player, "repair_module", &"track_l", &"track_links") == "" and _near(v.job_left(player), 90.0, 2.0), "back at it: %.0f s left" % v.job_left(player))
	job = lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.8)
	check(_near(mods.health_of("track_l"), 0.6, 0.001) and not mods.kill_state().mobility and player.inventory.count_of(&"track_links") == 0 and not lg.progress.has("m:track_l"),
		"the track back on at 60%: the mobility kill clears, the links used (%s)" % VehicleModules.kill_text(mods.kill))
	helper.queue_free()
	await _physics(2)
	# The engine: damaged in the field, destroyed only at the motor pool.
	player.inventory.take(&"repair_kit")
	mods.server_set("engine", 0.0)
	await _physics(2)
	check(lg.repair_problem(player, "engine", &"repair_kit").begins_with("Only the motor pool") and VehicleService.repair_problem(v, player, Vehicle.ZONE_ENGINE, &"repair_kit").begins_with("Only the motor pool"),
		"a destroyed engine: only the motor pool (the zone repair too: %s)" % VehicleService.repair_problem(v, player, Vehicle.ZONE_ENGINE, &"repair_kit"))
	mods.server_set("engine", 0.3)
	check(lg.repair_problem(player, "engine", &"repair_kit") == "" and v.server_start_job(player, "repair_module", &"engine", &"repair_kit") == ""
		and _near(v.job_left(player), 180.0, 1.0), "a damaged engine: the repair kit, 90 s with two (%.0f alone)" % v.job_left(player))
	v.damaged.emit(Vehicle.ZONE_HULL, {})
	await _seconds(0.6)
	check(String(lg.job_of(player).get("paused", "")) == "the vehicle is taking hits", "a hit on the vehicle pauses the job (2.9.3)")
	lg._hit_at = -INF
	job = lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.8)
	check(_near(mods.health_of("engine"), 0.6, 0.001) and player.inventory.count_of(&"repair_kit") == 0, "the engine working again at 60%, the kit used")
	mods.server_set("breech", 0.3)
	var breech: Array = lg.repair_options(player).filter(func(o: Dictionary) -> bool: return String(o.module) == "breech")
	check(breech.size() == 1 and String(breech[0].why).contains("only the motor pool") and StringName(breech[0].item) == &"", "a damaged breech: the workshop's (%s)" % [breech])
	mods.server_set("breech", 1.0)
	# Spares from the hold; the radio; the periscope.
	mods.server_set("radio", 0.0)
	mods.server_set("driver_vision", 0.2)
	await _physics(2)
	v.cargo_hold.take(&"radio", 1)
	v.cargo_hold.take(&"periscope", 1)
	check(v.has_meta(&"radio_down") and lg.has_part(player, &"radio") and lg.repair_problem(player, "radio", &"radio") == "", "a dead radio, a radio in the hold: the spare is used from there")
	check(v.server_start_job(player, "repair_module", &"radio", &"radio") == "" and _near(v.job_left(player), 40.0, 0.5), "a radio swap: 20 s with two (40 alone)")
	job = lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check(not v.has_meta(&"radio_down") and v.cargo_hold.count_of(&"radio") == 0, "the radio back: the net and the BFT with it")
	check(v.server_start_job(player, "repair_module", &"driver_vision", &"periscope") == "" and _near(v.job_left(player), 60.0, 0.5), "a periscope swap: 30 s with two")
	job = lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check(mods.state("driver_vision") == VehicleModules.WORKING, "the driver's periscope working")
	# A fuel tank patched stops the leak.
	player.inventory.take(&"repair_kit")
	mods.server_set("fuel_tank_rear", 0.3)
	v._leak = 0.5
	check(v.server_start_job(player, "repair_module", &"fuel_tank_rear", &"repair_kit") == "", "a holed fuel tank: patched (45 s)")
	job = lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check(is_equal_approx(v._leak, 0.0) and mods.state("fuel_tank_rear") == VehicleModules.WORKING, "the patch stops the leak")
	# A wheel on an MRAP: one man's job, as today.
	var m := await _spawn("matv", Vector3(30, 0, 70), 0.0)
	m.modules.server_set("wheel_fl", 0.0)
	player.inventory.strip()
	player.inventory.take(&"spare_wheel")
	_stand_at_service(m)
	await _physics(2)
	check(m.server_start_job(player, "repair_module", &"wheel_fl", &"spare_wheel") == "" and _near(m.job_left(player), 25.0, 0.3), "a spare wheel: 25 s alone, as today")
	job = m.logistics.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check(m.modules.state("wheel_fl") == VehicleModules.WORKING and player.inventory.hands == &"", "the wheel back on")
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	await _clear(m, [])
	await _clear(v, [])


func _test_tiles() -> void:
	print("ERA tiles and slat from the spares (2.4.4, 2.9.3)")
	var v := await _spawn("abrams", Vector3(60, 0, 40), 0.0)
	var lg := v.logistics
	lg.server_set_packages(["tusk1"])
	var group := ""
	for t: Dictionary in v.spec.get("tiles", []):
		if String(t.kind) == "light_era" and ArmourModel.tile_fitted(t, ArmourModel.fitted_packages(v.spec, ["tusk1"])):
			group = String(t.group)
			break
	var flags := PackedByteArray()
	flags.resize(4)
	flags[1] = 1
	flags[2] = 1
	v.set_meta(ArmourModel.META_TILES, {group: flags})
	await _seconds(0.5)
	v.cargo_hold.take(&"era_tile", 2)
	player.inventory.strip()
	_stand_at_service(v)
	await _physics(2)
	check(group != "" and (lg.fired_tiles().get(group, []) as Array).size() == 2 and VehicleLogistics.tile_spare("light_era") == &"era_tile" and VehicleLogistics.tile_spare("slat") == &"slat_panel"
		and (lg.net_state.get("tl", {}) as Dictionary).has(group), "TUSK I's ARAT %s: two tiles fired, replicated; an ERA tile (or a slat panel) replaces one" % group)
	check(v.server_start_job(player, "tile", StringName(group), &"era_tile") == "" and _near(v.job_left(player), 80.0, 0.5), "a tile: 40 s with two (80 alone)")
	var job := lg.job_of(player)
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check((lg.fired_tiles().get(group, []) as Array).size() == 1 and v.cargo_hold.count_of(&"era_tile") == 1, "one tile back from the spares in the hold")
	var m2 := v.weapons.mount("commander_m2")
	var buttoned := v.hatches.mount_why(2, m2)
	lg.server_set_packages(["tusk2"])
	check(buttoned == "Turn out first" and v.hatches.mount_why(2, m2) == "", "TUSK II's CROWS: the commander's M2 fires from inside (TUSK I: %s)" % buttoned)
	await _clear(v, [])


# --- The FOB -----------------------------------------------------------------------------------------

func _test_fob() -> void:
	print("The motor pool: per-module quotes and service, the load-out rearm and its bill (2.9.2, 2.9.3)")
	Economy.new_campaign(2000000)
	Campaign.section(MotorPool.SECTION).clear()
	var id := MotorPool.add("abrams")
	var e := MotorPool.entry(id)
	(e.record as Dictionary)["modules"] = {"hp": {"engine": 0.0, "breech": 0.5, "track_l": 0.0}, "rounds": {}, "crew_lost": false, "flags": {}}
	_set_record(id, e.record)
	var q := MotorPool.repair_quote(id)
	var value := 4000000.0
	var want := roundi(value * (0.06 + 0.05 * 0.5 + 0.01))
	check(int(q.cost) == want - int(q.parts_credit) and int(q.days) >= 2, "a destroyed engine and track, a breech at half: $%d (the modules' shares, $%d), %d days" % [int(q.cost), want, int(q.days)])
	check(MotorPool.server_repair(id) == "" and MotorPool.repair_quote(id).cost == 0 and (MotorPool.entry(id).record.modules.hp as Dictionary).is_empty(), "serviced: every module whole")
	Economy.advance_days(int(q.days) + 1)
	var at := Transform3D(Basis(), level.ground_point(Vector3(90, 0, 40)) + Vector3.UP * 0.3)
	var cash := Economy.cash()
	check(MotorPool.server_set_loadout(id, "anti_armour") == "", "the anti-armour load-out picked")
	var v := MotorPool.server_bring(id, level, at)
	await _seconds(1.0)
	var kills := v.modules.kill_state() if v else {}
	var racks := v.weapons.racks if v else {}
	var added := (24 + 6) - 20  # M829A3 over the default the hull came with (one in the breech is one of them)
	check(v != null and not bool(kills.get("mobility", true)) and not bool(kills.get("firepower", true)) and v.modules.health_of("engine") >= 0.999,
		"brought out after the service: no kill states, the engine whole")
	check(v != null and int((racks.get("ammo_rack_bustle", {}) as Dictionary).get("m829a3", 0)) + (1 if v.weapons.loaded("main") == "m829a3" else 0) == 24
		and int((racks.get("ammo_rack_hull", {}) as Dictionary).get("m829a3", 0)) == 6 and Economy.cash() == cash - added * 1100,
		"its racks to the anti-armour load-out; the bill: %d sabot rounds put in at $1,100 ($%d)" % [added, cash - Economy.cash()])
	# Firing some and coming home: the rounds refilled, charged.
	v.weapons.server_take_rounds("ammo_rack_bustle", "m829a3", 4)
	v.smoke.loaded = [0, 0]
	v.logistics.server_use_bottle("engine")
	cash = Economy.cash()
	var salvo := int(Prices.data().ammo.smoke_salvo)
	var bottle := int(VehicleLogistics.data().extinguishers.refill_price.engine)
	check(MotorPool.server_return(v) and Economy.cash() == cash - (4 * 1100 + 2 * salvo + bottle),
		"home at the FOB: 4 sabot, 2 salvos and an engine bottle refilled for $%d" % (cash - Economy.cash()))
	var rec: Dictionary = MotorPool.entry(id).record
	check(String(rec.logistics.loadout) == "anti_armour" and int(rec.logistics.bottles.engine) == 2, "the record keeps the load-out and the bottles")
	MotorPool.remove(id)


func _test_packages() -> void:
	print("Armour packages at the motor pool: price, days, STANAG, weight (2.4.5)")
	Economy.new_campaign(2000000)
	var id := MotorPool.add("maxxpro")
	var cash := Economy.cash()
	var day := Economy.day()
	var offers := MotorPool.package_offers(id)
	var app: Array = offers.filter(func(o: Dictionary) -> bool: return String(o.id) == "maxxpro_applique")
	check(app.size() == 1 and int(app[0].price) == 40000 and String(app[0].why) == "" and int(app[0].days) == 2, "the MaxxPro appliqué on offer: $40,000, 2 days (%s)" % [app])
	Economy.change_reputation("us_forces", -Economy.reputation("us_forces"), "test", false)
	check(MotorPool.package_problem(id, "crows").begins_with("Needs Trusted"), "CROWS needs Trusted with the US (%s)" % MotorPool.package_problem(id, "crows"))
	check(MotorPool.server_package(id, "maxxpro_applique") == "" and Economy.cash() == cash - 40000 and int(MotorPool.entry(id).ready_day) == day + 2
		and MotorPool.problem(id).begins_with("In the workshop"), "fitted: $40,000, in the workshop 2 days")
	Economy.advance_days(2)
	var v := MotorPool.server_bring(id, level, Transform3D(Basis(), level.ground_point(Vector3(90, 0, 80)) + Vector3.UP * 0.3))
	await _seconds(1.0)
	var pk: Array = v.get_meta(ArmourModel.META_PACKAGES, []) if v else []
	var r := ArmourStandards.rating(v.spec, pk) if v else {}
	var base_top := float(v.spec.top_speed_kmh) * VehicleSpecs.KMH if v else 0.0
	check(v != null and pk == ["maxxpro_applique"] and v.logistics.packages == ["maxxpro_applique"] and _ke(r) == [3, 3, 3]
		and ArmourStandards.ke_proven(v.spec, "side", pk) == 3, "brought out with its appliqué: STANAG KE 3 all round, as its plates prove (%s)" % ArmourStandards.text(v.spec, pk) if v else "")
	check(v != null and _near(v.top_speed(), base_top * sqrt(14500.0 / 15400.0), 0.01) and _near(v.logistics.fuel_mult(), 15400.0 / 14500.0, 0.0001),
		"its 0.9 t: top speed %.2f of %.2f m/s, fuel x%.3f" % [v.top_speed() if v else 0.0, base_top, v.logistics.fuel_mult() if v else 0.0])
	var res: Dictionary = ArmourStandards.ke_result(v.spec, 3, "side", pk) if v else {}
	var bare: Dictionary = ArmourStandards.ke_result(v.spec, 3, "side", []) if v else {}
	check(v != null and bool(res.get("stopped", false)) and not bool(bare.get("stopped", true)), "KE 3's threats on the side: stopped with the appliqué the vehicle carries, not without (%s)" % String(bare.get("worst", "")))
	MotorPool.server_return(v)
	await _physics(2)
	cash = Economy.cash()
	check(MotorPool.server_package(id, "maxxpro_applique", false) == "" and Economy.cash() == cash + 20000 and (MotorPool.entry(id).record.logistics.packages as Array).is_empty(),
		"removed: half back ($20,000)")
	MotorPool.remove(id)
	# The Abrams: Trophy after TUSK I; TUSK II an upgrade that credits TUSK I.
	Economy.change_reputation("us_forces", 80 - Economy.reputation("us_forces"), "test", false)
	var a := MotorPool.add("abrams")
	check(MotorPool.package_problem(a, "trophy").begins_with("Fit the Abrams TUSK I first"), "Trophy needs TUSK I first (%s)" % MotorPool.package_problem(a, "trophy"))
	cash = Economy.cash()
	MotorPool.server_package(a, "tusk1")
	var upgrade := MotorPool.package_cost(a, "tusk2")
	check(upgrade == 320000 - 180000 and MotorPool.server_package(a, "tusk2") == "" and MotorPool.entry(a).record.logistics.packages == ["tusk2"]
		and Economy.cash() == cash - 320000, "TUSK II over TUSK I: $%d more, the list just TUSK II" % upgrade)
	check(MotorPool.package_problem(a, "tusk1", false).begins_with("Part of another") and MotorPool.package_problem(a, "trophy") == "", "TUSK I is part of TUSK II now; Trophy can go on")
	MotorPool.remove(a)


# --- Recovery: the tow ----------------------------------------------------------------------------------

func _test_tow() -> void:
	print("Recovery: a tow from a vehicle of half the mass (2.8.3's stand-in)")
	var o := _flat_spot()
	var hurt := await _spawn("maxxpro", o, 0.0, &"player", false)
	var tower := await _spawn("matv", o + Vector3(0, 0, -9.5), 0.0, &"player", false)
	var light := await _spawn("technical", o + Vector3(8, 0, -8.5), 0.0, &"player", false)
	await _seconds(1.5)
	for wid: String in ["wheel_fl", "wheel_fr", "wheel_rl"]:
		hurt.modules.server_set(wid, 0.0)
	await _seconds(0.7)
	var lg := hurt.logistics
	check(not hurt.can_drive() and lg.needs().recovery and lg.tow_problem(tower) == "" and lg.tow_problem(light).contains("too light"),
		"three wheels gone: it needs recovery; the M-ATV (12.5 t) can tow the MaxxPro (%s), the technical can't (%s)" % [lg.tow_problem(tower), lg.tow_problem(light)])
	check(lg.server_call_recovery() == "" and hurt in VehicleLogistics.recoveries(level), "the crew calls for recovery (A9's flag)")
	_stand_at_service(hurt)
	await _physics(2)
	var why := hurt.server_start_job(player, "tow", StringName(tower.vehicle_id), &"")
	check(why == "" and _near(hurt.job_left(player), 60.0, 0.5), "hooking up: 60 s (%s)" % why)
	var job := lg.job_of(player)
	if job.is_empty():
		for v: Vehicle in [hurt, tower, light]:
			await _clear(v, [])
		return
	job.done = float(job.need) - 0.05
	await _seconds(0.6)
	check(lg.towed() and VehicleLogistics.of(tower).towing_one() and not lg.recovery_wanted and hurt.readout(0).contains("UNDER TOW"), "hooked: the MaxxPro under tow")
	player.global_position = Vector3(0, 0.1, 0)
	var start := hurt.global_position
	check(_near(tower.top_speed(), 15.0 / 3.6, 0.05), "towing: at most 15 km/h (%.1f)" % (tower.top_speed() * 3.6))
	tower.server_drive_to(tower.global_position + tower.global_basis * Vector3(0, 0, -40), 15.0)
	await _seconds(9.0)
	var gap := tower.to_global(VehicleLogistics.hitch(tower, true)).distance_to(hurt.to_global(VehicleLogistics.hitch(hurt, false)))
	var moved := hurt.global_position.distance_to(start)
	check(moved > 6.0 and gap < 5.0, "it follows on the bar: %.1f m towed, the hitches %.1f m apart" % [moved, gap])
	tower.server_stop()
	await _seconds(2.0)
	lg.server_unhook()
	check(not lg.towed() and not VehicleLogistics.of(tower).towing_one(), "unhooked")
	for v: Vehicle in [hurt, tower, light]:
		await _clear(v, [])


# --- Fuel and the helicopter's load -------------------------------------------------------------------

func _test_fuel() -> void:
	print("Fuel from a drum pallet (2.9.1)")
	var v := await _spawn("matv", Vector3(60, 0, -60), 0.0)
	v.server_set_fuel(100.0)
	var uid := VehicleLogistics.server_drop_pallet(level, &"pallet_fuel_drums", level.ground_point(v.global_transform * Vector3(2.5, 0, 3.0)) + Vector3.UP * 0.3)
	await _seconds(1.0)
	_stand_at_cargo(v)
	await _physics(2)
	var srcs := v.logistics.fuel_sources()
	check(srcs.size() == 1 and String(srcs[0].key) == "w:" + uid and _near(float(srcs[0].lpm), 60.0, 0.01), "a drum pallet within 8 m: a source at 60 L/min")
	check(v.server_start_job(player, "refuel_from", StringName("w:" + uid), &"") == "" and _near(v.job_left(player), 200.0, 2.0), "200 L to fill: about %.0f s" % v.job_left(player))
	await _seconds(3.0)
	var got := v.fuel - 100.0
	var wi := v.logistics._world_item(uid)
	check(got > 1.5 and got < 5.0 and wi != null and _near(VehicleLogistics.pallet_fuel(wi.item_id, wi.state), 832.0 - got, 0.6), "3 s: %.1f L in, the drums down to %.0f L" % [got, VehicleLogistics.pallet_fuel(wi.item_id, wi.state) if wi else -1.0])
	v.logistics.server_stop_jobs()
	if wi:
		GameState.item_taken(uid)
		wi.queue_free()
	await _clear(v, [])


func _test_heli_load() -> void:
	print("The helicopter's armour load (2.9.2: 8 x 120 mm or 300 x 25 mm or 2 TOW)")
	var a := await _spawn("abrams", Vector3(120, 0, -60), 0.0)
	var b := await _spawn("bradley", Vector3(120, 0, -30), 0.0)
	a.weapons.server_take_rounds("ammo_rack_bustle", "m829a3", 10)
	b.weapons.server_take_rounds("rack_tow", "tow2a", 4)
	var loads := VehicleLogistics.heli_armour_load(level)
	var for_a: Array = loads.filter(func(l: Dictionary) -> bool: return String(l.for) == a.vehicle_id)
	var for_b: Array = loads.filter(func(l: Dictionary) -> bool: return String(l.for) == b.vehicle_id)
	var n_a := 0
	for k: Variant in (for_a[0].load as Dictionary) if not for_a.is_empty() else {}:
		n_a += int(for_a[0].load[k])
	check(for_a.size() == 1 and StringName(for_a[0].id) == &"pallet_ammo_120" and n_a == 8, "the Abrams short of sabot: a 120 mm pallet of 8 rounds in its load-out's mix (%s)" % [for_a])
	check(for_b.size() == 1 and StringName(for_b[0].id) == &"pallet_ammo_tow" and for_b[0].load == {"tow_2a": 2}, "the Bradley short of TOWs: 2 TOW (%s)" % [for_b])
	b.weapons.server_rearm()
	b.weapons.server_take_rounds("rack_25", "m792", 400)
	var again: Array = VehicleLogistics.heli_armour_load(level).filter(func(l: Dictionary) -> bool: return String(l.for) == b.vehicle_id)
	var cans := 0
	for k: Variant in (again[0].load as Dictionary) if not again.is_empty() else {}:
		cans += int(again[0].load[k])
	check(again.size() == 1 and StringName(again[0].id) == &"pallet_ammo_25" and cans == 6, "short of 25 mm: 300 rounds, six cans (%s)" % [again])
	await _clear(a, [])
	await _clear(b, [])


# --- Save and load ------------------------------------------------------------------------------------

func _test_save() -> void:
	print("Save and load: packages, the load-out, bottles, repair progress, fired tiles, racks as items")
	var v := await _spawn("abrams", Vector3(-120, 0, 40), 0.0)
	var lg := v.logistics
	lg.server_set_packages(["tusk1"])
	lg.loadout = "urban"
	lg.server_use_bottle("halon")
	lg.progress["m:track_r"] = 42.0
	v.set_meta(ArmourModel.META_TILES, {"x": PackedByteArray([0, 1])})
	v.weapons.server_take_rounds("ammo_rack_hull", "m830a1", 2)
	v.smoke.server_take_salvo()
	var rec := v.to_save()
	for k: String in ["id", "pos", "rot"]:
		rec.erase(k)
	var w := layer.server_spawn("abrams", Transform3D(Basis(), level.ground_point(Vector3(-120, 0, 70)) + Vector3.UP * 0.3), "", &"player", "", rec)
	await _seconds(1.0)
	var l2 := w.logistics
	check(l2.packages == ["tusk1"] and w.get_meta(ArmourModel.META_PACKAGES, []) == ["tusk1"] and l2.loadout == "urban" and int(l2.bottles.halon) == 0
		and _near(float(l2.progress.get("m:track_r", 0.0)), 42.0, 0.01) and (l2.fired_tiles().get("x", []) as Array) == [1],
		"a saved Abrams back: TUSK I, the urban load-out, the halon used, the track's 42 s, the fired tile")
	check(_items_of(l2.rack_items("ammo_rack_hull"), &"round_120_m830a1") == 0 and w.smoke.stowed_salvos() == v.smoke.stowed_salvos()
		and _near(l2.speed_mult(), lg.speed_mult(), 0.0001), "its racks as items and the smoke stowage as saved, the weight's cost with them")
	await _clear(v, [])
	await _clear(w, [])


# --- Budgets -------------------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Cost: the logistics tick, needs(), the cargo point's menu")
	var v := await _spawn("abrams", Vector3(-150, 0, 40), 0.0)
	var lg := v.logistics
	_stand_at_cargo(v)
	await _physics(2)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		lg._physics_process(0.25)
	var tick_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	t0 = Time.get_ticks_usec()
	for i in 50:
		lg.needs()
	var needs_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 50.0
	var cargo: VehicleActionPoint = null
	for p in v.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == VehicleActionPoint.CARGO:
			cargo = p
	t0 = Time.get_ticks_usec()
	for i in 20:
		cargo.interaction_actions(player)
	var menu_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	var slack := 1.0 if OS.has_environment("GITHUB_ACTIONS") else LOCAL_SLACK
	check(tick_ms < TICK_BUDGET_MS * slack and needs_ms < NEEDS_BUDGET_MS * slack and menu_ms < MENU_BUDGET_MS * slack,
		"a vehicle's tick %.4f ms (budget %.2f), needs() %.3f ms (%.1f), the cargo point's menu %.2f ms (%.1f)" % [tick_ms, TICK_BUDGET_MS, needs_ms, NEEDS_BUDGET_MS, menu_ms, MENU_BUDGET_MS])
	await _clear(v, [])


# --- A late joiner ---------------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins late)")
	var a := await _spawn("abrams", Vector3(-30, 0, -100), 0.0)
	a.logistics.server_set_packages(["tusk1"])
	var group := ""
	for t: Dictionary in a.spec.get("tiles", []):
		if String(t.kind) == "light_era" and ArmourModel.tile_fitted(t, ArmourModel.fitted_packages(a.spec, ["tusk1"])):
			group = String(t.group)
			break
	a.set_meta(ArmourModel.META_TILES, {group: PackedByteArray([1, 0, 1])})
	a.weapons.server_take_rounds("ammo_rack_bustle", "m829a3", 5)
	a.smoke.server_take_salvo()
	a.modules.server_set("track_l", 0.0)
	a.logistics.progress["m:track_l"] = 60.0
	a.logistics._publish()
	var hurt := await _spawn("matv", Vector3(30, 0, -100), 0.0, &"player", false)
	var tower := await _spawn("maxxpro", Vector3(30, 0, -100 - 9.5), 0.0, &"player", false)
	await _seconds(1.0)
	hurt.logistics.server_hook(tower)
	await _seconds(0.8)
	expect = {"a": a.vehicle_id, "pk": ["tusk1"], "group": group, "tiles": [0, 2], "m829a3": _items_of(a.logistics.rack_items("ammo_rack_bustle"), &"round_120_m829a3"),
		"salvos": a.smoke.stowed_salvos(), "stanag": ArmourStandards.text(a.spec, ["tusk1"]), "hurt": hurt.vehicle_id, "share": 60.0}
	var log_path := OS.get_user_data_dir().path_join("armourlog_client%s.log" % _tag)
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/armourlog_test.tscn", "--", "--armourlog-join"]
	multiplayer.peer_connected.connect(func(peer: int) -> void:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.get_peer(peer):
			enet.get_peer(peer).set_timeout(32, 60000, 120000))
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_failures >= 0, 300.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())
	hurt.logistics.server_unhook()
	for v: Vehicle in [a, hurt, tower]:
		await _clear(v, [])


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		print("  [%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 120.0)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if joined and enet and enet.get_peer(1):
		enet.get_peer(1).set_timeout(32, 60000, 120000)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until and multiplayer.get_unique_id() != 1:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.a)) != null and find.call(String(expect.hurt)) != null, 30.0)
		var a: Vehicle = find.call(String(expect.a))
		var hurt: Vehicle = find.call(String(expect.hurt))
		await _until(func() -> bool: return a != null and a.logistics != null and a.logistics.packages == expect.pk, 20.0)
		await _seconds(1.0)
		var lg := a.logistics if a else null
		var pk: Array = a.get_meta(ArmourModel.META_PACKAGES, []) if a else []
		note.call(lg != null and lg.packages == expect.pk and pk == expect.pk and ArmourStandards.text(a.spec, pk) == String(expect.stanag),
			"the Abrams' TUSK I here too, its STANAG rating the host's (%s)" % (ArmourStandards.text(a.spec, pk) if a else "-"))
		note.call(lg != null and lg.fired_tiles().get(String(expect.group), []) == expect.tiles and lg.speed_mult() < 1.0,
			"its fired ARAT tiles (the HUD's and x-ray's meta), and the weight's cost (%s)" % [lg.fired_tiles() if lg else {}])
		note.call(lg != null and _items_of(lg.rack_items("ammo_rack_bustle"), &"round_120_m829a3") == int(expect.m829a3) and a.smoke.stowed_salvos() == int(expect.salvos),
			"the racks as items (%d M829A3 in the bustle) and the smoke stowage (%d salvos)" % [_items_of(lg.rack_items("ammo_rack_bustle"), &"round_120_m829a3") if lg else -1, a.smoke.stowed_salvos() if a else -1])
		note.call(lg != null and _near(float(lg.progress.get("m:track_l", 0.0)), float(expect.share), 0.5) and a.modules.kill_state().mobility,
			"the track's repair progress (%.0f s) and its mobility kill" % (float(lg.progress.get("m:track_l", 0.0)) if lg else -1.0))
		note.call(hurt != null and hurt.logistics.towed() and hurt.readout(0).contains("UNDER TOW"), "the M-ATV under tow")
	if multiplayer.get_unique_id() != 1:
		_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


# --- Helpers -------------------------------------------------------------------------------------------

func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player", frozen := true) -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), level.ground_point(pos) + Vector3.UP * 0.3), "", faction, "log_%s_%d" % [model, _n])
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(1.2)
	if frozen:
		v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		v.freeze = true
		v.linear_velocity = Vector3.ZERO
	return v


## AI soldiers in `seats` of `v` (their brains off), seated.
func _crew(v: Vehicle, seats: Array) -> Array:
	var out: Array = []
	for seat: int in seats:
		_n += 1
		var s := level.spawn_soldier({"name": "LogCrew%d" % _n, "person_name": "Crew %d" % _n, "faction": "friendly", "variant": "woodland",
			"pos": v.global_position + Vector3(12.0, 0.1, float(seat)), "loadout": [], "combat": 1.0, "discipline": 0.6, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().physics_frame
		v.server_enter(s, seat)
		out.append(s)
	await _seconds(0.5)
	return out


## `n` AI men at `at`, not seated.
func _men(n: int, at: Vector3) -> Array:
	var out: Array = []
	for i in n:
		_n += 1
		var s := level.spawn_soldier({"name": "LogMan%d" % _n, "person_name": "Man %d" % _n, "faction": "friendly", "variant": "woodland",
			"pos": at + Vector3(0, 0.1, float(i) * 1.2), "loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		out.append(s)
	await _physics(2)
	return out


func _point(v: Vehicle, kind: String) -> VehicleActionPoint:
	for p in v.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == kind:
			return p
	return null


## The player on his feet by `v`'s cargo point (or service point).
func _stand_at_cargo(v: Vehicle) -> void:
	var p := _point(v, VehicleActionPoint.CARGO)
	player.global_position = level.ground_point(p.global_position) + Vector3.UP * 0.1
	player.threat_time = -1000.0
	player.suppression = 0.0


func _stand_at_service(v: Vehicle) -> void:
	var p := _point(v, VehicleActionPoint.SERVICE)
	player.global_position = level.ground_point(p.global_position) + Vector3.UP * 0.1
	player.threat_time = -1000.0
	player.suppression = 0.0


func _set_record(id: String, rec: Dictionary) -> void:
	for e: Dictionary in Campaign.section(MotorPool.SECTION).vehicles:
		if String(e.id) == id:
			e.record = rec


static func _items_of(items: Array, id: StringName) -> int:
	for e: Dictionary in items:
		if StringName(e.id) == id:
			return int(e.count)
	return 0


static func _entry_of(items: Array, id: StringName) -> Dictionary:
	for e: Dictionary in items:
		if StringName(e.id) == id:
			return e
	return {}


## A spot on flat open ground for a tow (the ground within 0.3 m over 60 m along z, 12 m wide).
func _flat_spot() -> Vector3:
	for c: Vector3 in [Vector3(-70, 0, -40), Vector3(-40, 0, -130), Vector3(70, 0, -130), Vector3(-130, 0, -40), Vector3(130, 0, 0), Vector3(-130, 0, 100), Vector3(20, 0, 130)]:
		var lo := INF
		var hi := -INF
		for dz in range(-50, 11, 5):
			for dx in [-6, 0, 6]:
				var y := level.ground_point(c + Vector3(dx, 0, dz)).y
				lo = minf(lo, y)
				hi = maxf(hi, y)
		if hi - lo < 0.3:
			return c
	return Vector3(-70, 0, -40)


## A STANAG rating's KE levels as [front, side, rear].
static func _ke(r: Dictionary) -> Array:
	var ke: Dictionary = r.get("ke", {})
	return [int(ke.get("front", -1)), int(ke.get("side", -1)), int(ke.get("rear", -1))]


static func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _clear(v: Vehicle, people: Array) -> void:
	if is_instance_valid(v):
		if v.logistics:
			v.logistics.server_stop_jobs()
			v.logistics.server_unhook()
		for s: Soldier in v.occupants():
			v.server_exit(s)
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	player.global_position = Vector3(0, 0.1, 0)
	await _seconds(0.3)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
