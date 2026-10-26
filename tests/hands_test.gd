extends Node
## Contractor: Fallen's hands on nature, spoilage and the clinic (docs/survival_hands.md): in a hosted
## survival world with a settlement on flat ground: the contextual menu offers Butcher on a carcass
## (and the one key does it); butchering takes time and yields by species (bones and fat too,
## fieldcraft more meat); a snare catches over the hours; a cast catches by water and season (a hand
## line, through the ice less); foraging a known plant works and an unknown one shows the unknown
## entry; felling yields planks and firewood, deadfall without a tool; raw meat goes stale then spoiled
## over world hours, cold slows it, a smoker preserves it, eating spoiled food risks food poisoning,
## the larder throws spoiled stock out and keeps the oldest first; a clinic bed speeds healing, surgery
## in a clinic goes bad less often, the doctor treats settlers with the cabinet stocked and files a
## work order when it runs low, and the bitten go into quarantine with a council vote.
## The world's clock is set directly.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var b: Builder
var st: Settlement
var nat: Nature
var origin := Vector3i.ZERO


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("HANDS TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if b != null and player != null and st != null and nat != null:
		_test_menus()
		await _test_butcher()
		_test_snare()
		_test_fishing()
		_test_forage()
		_test_fell()
		_test_spoilage()
		_test_clinic()
	_finish()


func _test_host() -> void:
	print("A survival world with a settlement")
	check(Survival.server_new_world(main, "test_hands" + tag, 4242), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	if player == null:
		check(false, "the host's survivor is in")
		return
	for i in 120:
		await get_tree().process_frame
	Survival._pop = -1000.0
	Seasons.force_frost = 0
	_clear_dead()
	b = Builder.find(level)
	st = Settlement.find(level)
	nat = Nature.of(level)
	check(b != null and st != null and nat != null, "the zone has its Builder, Settlement and Nature")
	if b == null or st == null or nat == null:
		return
	await _wait_for(func() -> bool: return Wildlife.zone_id != "", 10.0)
	nat.set_process(false)  # (the test drives the nature itself)
	st.set_process(false)
	var sieges := Sieges.of(level)
	if sieges:
		sieges.set_process(false)
	player.inventory.put_on(&"backpack", &"pack_ruck_60")
	var found := false
	var start := player.global_position
	for ring: float in [8.0, 12.0, 16.0, 22.0, 30.0, 38.0, 46.0, 56.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var x := start.x + cos(a) * ring
			var z := start.z + sin(a) * ring
			if _flat_and_clear(x, z):
				origin = Builder.ground_cell(Vector3(x, level.ground_height(x, z), z))
				found = true
				break
		if found:
			break
	check(found, "a patch of flat open ground (%s)" % origin)
	var home := BuildPieces.cell_centre(_at(0, 0))
	Settlement.server_found(String(Survival.state().zone), Vector3(home.x, level.ground_height(home.x, home.z), home.z))
	check(Settlement.exists() and st.hosted(), "the settlement founded there")
	_set_clock(2, 8.0)
	_stand_by(_at(0, -6))
	await _frames(5)


# --- The menu ------------------------------------------------------------------------------------------

func _test_menus() -> void:
	print("The contextual menu: a carcass offers Butcher first; the fieldwork's other entries")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	var deer := Wildlife.add(level, "deer", player.global_position + Vector3(1.5, 0, 0), {"alive": false})
	var p: Vector2 = deer.pos
	var at := Vector3(p.x, float(deer.y), p.y)
	var ctx := ContextMenu.classify(player, null, at)
	check(String(ctx.get("kind", "")) == "carcass" and String(ctx.get("sp", "")) == "deer", "looking at a dead deer: a carcass (%s)" % ctx)
	var opts := ContextResolver.resolve(ctx)
	check(not opts.is_empty() and String(opts[0].id) == "fw_butcher" and String(opts[0].do) == "fieldwork" and String(opts[0].label) == "Butcher the deer",
		"the one key's default: %s" % (opts[0].label if not opts.is_empty() else "none"))
	check(String(ContextResolver.resolve({"kind": "woods"})[0].id) == "fw_set_snare" and String(ContextResolver.resolve({"kind": "water", "frozen": true})[0].id) == "fw_cut_ice",
		"the woods offer a snare first; frozen water, cutting ice")
	var tree_opts := Fieldwork.options({"kind": "tree", "index": 3, "sp": "apple", "name": "apple tree"})
	check(tree_opts.size() == 3 and String(tree_opts[0].what) == "fell" and String(tree_opts[1].what) == "firewood" and String(tree_opts[2].what) == "fruit",
		"a tree: fell, gather firewood, pick apples on an apple")
	Wildlife.animals.erase(deer)


# --- Butchering ---------------------------------------------------------------------------------------

func _test_butcher() -> void:
	print("Butchering takes time and yields by species")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	Rpg.set_level(player, "fieldcraft", 0)
	check(Fieldwork.butcher_s("deer", 0) > Fieldwork.butcher_s("rabbit", 0) and Fieldwork.butcher_s("deer", 5) < Fieldwork.butcher_s("deer", 0),
		"a deer %.0f s, a rabbit %.0f s; a deer at fieldcraft 5 %.0f s" % [Fieldwork.butcher_s("deer", 0), Fieldwork.butcher_s("rabbit", 0), Fieldwork.butcher_s("deer", 5)])
	var me := player.global_position
	var rabbit := Wildlife.add(level, "rabbit", me + Vector3(1, 0, 0), {"alive": false})
	var meat0 := _have(&"raw_meat")
	check(Fieldwork.server_butcher(player, rabbit) == "" and _have(&"raw_meat") == meat0 and Soldier._now() < player._server_busy_until,
		"a rabbit: the knife work starts, nothing yet, the hands busy")
	check(Fieldwork.server_butcher(player, rabbit) != "", "and it can't be butchered twice at once")
	await get_tree().create_timer(Fieldwork.butcher_s("rabbit", 0) + 0.6).timeout
	check(_have(&"raw_meat") == meat0 + 1 and bool(rabbit.get("butchered", false)), "after %.0f s: a cut of meat" % Fieldwork.butcher_s("rabbit", 0))
	var deer := Wildlife.add(level, "deer", me + Vector3(1, 0, 0.5), {"alive": false})
	var m1 := _have(&"raw_meat")
	var bone0 := _have(&"bone")
	var fat0 := _have(&"animal_fat")
	var hide0 := _have(&"hide")
	check(Fieldwork.server_butcher(player, deer, true) == "" and _have(&"raw_meat") == m1 + 4 and _have(&"bone") == bone0 + 3 and _have(&"animal_fat") == fat0 + 1 and _have(&"hide") == hide0 + 1,
		"a deer: 4 meat, 3 bones, fat and a hide (%d, %d, %d)" % [_have(&"raw_meat") - m1, _have(&"bone") - bone0, _have(&"animal_fat") - fat0])
	Rpg.set_level(player, "fieldcraft", 5)
	var boar := Wildlife.add(level, "boar", me + Vector3(0.5, 0, 1), {"alive": false})
	var m2 := _have(&"raw_meat")
	check(Fieldwork.server_butcher(player, boar, true) == "" and _have(&"raw_meat") - m2 > int(Wildlife.spec("boar").meat),
		"a boar at fieldcraft 5: more meat than a novice gets (%d, not %d)" % [_have(&"raw_meat") - m2, int(Wildlife.spec("boar").meat)])
	Rpg.set_level(player, "fieldcraft", 0)
	var state := _entry_state(&"raw_meat")
	check(Spoilage.stage(ItemDB.get_item(&"raw_meat"), state) == "fresh", "the meat comes fresh (stamped to %.0f h)" % float(state.get(Spoilage.KEY, -1.0)))
	check(Fieldwork.server_butcher(player, Wildlife.add(level, "deer", me + Vector3(40, 0, 0), {"alive": false}), true) == "Too far", "a carcass out of reach")


# --- Snares, fishing, foraging, felling -----------------------------------------------------------

func _test_snare() -> void:
	print("A snare catches over the hours")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	Wildlife.snares().clear()
	player._server_busy_until = 0.0
	player.inventory.take(&"snare", 1)
	check(Fieldwork.server_request(player, "set_snare", "", player.global_position) == "" and Wildlife.snares().size() == 1, "a snare set from the menu")
	Wildlife.force_roll = 0.3
	check(Wildlife.server_snare_hours(level, 1.0) == 0, "nothing in it after an hour")
	check(Wildlife.server_snare_hours(level, 12.0) == 1 and String(Wildlife.snares()[0].caught) == "rabbit", "a rabbit in it after a night")
	Wildlife.force_roll = -1.0
	check(Fieldwork.server_request(player, "check_snare", "", player.global_position) == "" and not Wildlife.carcass_near(player.global_position, 3.0).is_empty(),
		"checked: the rabbit lies there to butcher")
	player.global_position += Vector3(30, 0, 0)
	check(Fieldwork.server_request(player, "check_snare", "", player.global_position) != "", "no snare where he isn't")
	_stand_by(_at(0, -6))


func _test_fishing() -> void:
	print("A cast catches by water and season")
	_set_clock(2, 8.0)
	check(Fieldwork.bite_chance("river", "spring", 1.0, 0) > Fieldwork.bite_chance("river", "winter", 1.0, 0) and Fieldwork.bite_chance("pond", "summer", 1.0, 0) < Fieldwork.bite_chance("dam", "summer", 1.0, 0),
		"a river in spring %.0f%% a cast, in winter %.0f%%; a pond in summer %.0f%%, the dam %.0f%%" % [100.0 * Fieldwork.bite_chance("river", "spring", 1.0, 0),
		100.0 * Fieldwork.bite_chance("river", "winter", 1.0, 0), 100.0 * Fieldwork.bite_chance("pond", "summer", 1.0, 0), 100.0 * Fieldwork.bite_chance("dam", "summer", 1.0, 0)])
	check(Fieldwork.bite_chance("lake", "winter", 1.0, 0, true) < Fieldwork.bite_chance("lake", "winter", 1.0, 0) and Fieldwork.bite_chance("river", "spring", Fieldwork.LINE_X, 0) < Fieldwork.bite_chance("river", "spring", 1.0, 0),
		"through the ice less; a hand line less than a rod")
	for id: StringName in [&"fishing_rod", &"fishing_net", &"hand_line"]:
		while player.inventory.remove_one(id):
			pass
	check(Fieldwork.server_cast(player, true, "river") != "", "no gear, no cast")
	player.inventory.take(&"hand_line", 1)
	var f0 := _have(&"raw_fish")
	Fieldwork.force_roll = 0.0
	check(Fieldwork.server_cast(player, true, "river") == "" and _have(&"raw_fish") == f0 + 1, "a hand line on a river: a bite, a fish")
	Fieldwork.force_roll = 0.99
	Fieldwork.server_cast(player, true, "river")
	check(_have(&"raw_fish") == f0 + 1, "a bad cast: nothing")
	Fieldwork.force_roll = -1.0


func _test_forage() -> void:
	print("Foraging: a known plant by name, an unknown one as unknown")
	_set_clock(15, 8.0)  # (summer: berries)
	Rpg.set_level(player, "fieldcraft", 0)
	while player.inventory.count_of(&"field_guide") > 0:
		player.inventory.remove_one(&"field_guide")
	check(Fieldwork.forage_label(player, "berries") == "Forage (unknown plant)" and Fieldwork.forage_label(player, "nightshade") == "Forage (unknown plant)",
		"a novice can't tell berries from nightshade: both unknown")
	check(Fieldwork.forage_label(player, "willow_bark").begins_with("Forage Willow"), "a plant with no look-alike is known (%s)" % Fieldwork.forage_label(player, "willow_bark"))
	player.inventory.take(&"field_guide", 1)
	check(Fieldwork.forage_label(player, "berries") == "Forage Wild Berries" and Fieldwork.forage_label(player, "nightshade").ends_with("(poison)"),
		"with a field guide: %s, %s" % [Fieldwork.forage_label(player, "berries"), Fieldwork.forage_label(player, "nightshade")])
	var spot := _spot("berries")
	check(spot >= 0, "a berry bush in the zone")
	if spot >= 0:
		_at_spot(spot)
		var n0 := _have(&"wild_berries")
		check(Fieldwork.server_forage(player, spot, true) == "" and _have(&"wild_berries") > n0, "picked: %d berries" % (_have(&"wild_berries") - n0))
		check(Fieldwork.server_forage(player, spot, true) != "", "and not again today")
		var ctx := Fieldwork.classify(player, level.scatter.items[spot].pos)
		check(String(ctx.get("kind", "")) in ["plant", "tree", "woods"], "looking at the bush: %s" % ctx.get("kind", "nothing"))
	_set_clock(2, 8.0)
	_stand_by(_at(0, -6))


func _test_fell() -> void:
	print("Felling yields logs; deadfall without a tool")
	player.inventory.release_hands()
	player.inventory.take(&"axe", 1)
	var t := _tree_of("pine")
	if t < 0:
		t = _tree_of("birch")
	check(t >= 0, "a tree in the zone")
	if t < 0:
		return
	_at_spot(t)
	var planks0 := _have(&"planks")
	var wood0 := _have(&"firewood")
	check(Fieldwork.server_fell(player, t, true) == "" and Trees.is_felled(t) and _have(&"planks") > planks0 and _have(&"firewood") > wood0,
		"the %s down: %d planks, %d firewood" % [Trees.species_of(level.scatter.items[t]), _have(&"planks") - planks0, _have(&"firewood") - wood0])
	var w1 := _have(&"firewood")
	check(Fieldwork.server_firewood(player, true) == "" and _have(&"firewood") > w1, "deadfall gathered by hand (%d)" % (_have(&"firewood") - w1))
	Fieldwork.server_firewood(player, true)
	check(Fieldwork.server_firewood(player, true) != "", "the patch picked clean for the day")
	var t2 := Trees.nearest(level, player.global_position, 30.0)
	if t2 >= 0:
		_at_spot(t2)
		player._server_busy_until = 0.0
		check(Fieldwork.server_fell(player, t2) == "" and Trees.progress.has(t2) and not Trees.is_felled(t2) and Soldier._now() < player._server_busy_until,
			"felling from the menu: a chop at a time, the hands busy")
		_stand_by(_at(0, -6))  # (walked off: the next chop stops it)
	check(Fieldwork.server_fell(player, t, true) != "", "a stump can't be felled again")


# --- Spoilage ------------------------------------------------------------------------------------------

func _test_spoilage() -> void:
	print("Spoilage: fresh, going off, spoiled; cold, the smoker, eating it, the larder")
	var raw := ItemDB.get_item(&"raw_meat")
	_set_clock(2, 0.0)
	var t0 := Moods.now_h()
	var s1 := Spoilage.made_state(&"raw_meat")
	check(Spoilage.stage(raw, s1) == "fresh" and Spoilage.tag(raw, s1) == "fresh", "raw meat made now: fresh")
	_set_now(t0 + 30.0)
	check(Spoilage.stage(raw, s1) == "stale" and Spoilage.tag(raw, s1) == "going off", "30 hours on: going off")
	_set_now(t0 + 50.0)
	check(Spoilage.stage(raw, s1) == "spoiled", "50 hours on: spoiled")
	check(Spoilage.made_state(&"canned_meat").is_empty(), "a tin doesn't spoil")
	# Cold slows it.
	_set_now(t0)
	var warm := Spoilage.made_state(&"raw_meat")
	var cold := Spoilage.made_state(&"raw_meat")
	Spoilage.step_state(raw, warm, 30.0, 1.0)
	Spoilage.step_state(raw, cold, 30.0, Spoilage.COLD.cold_store)
	_set_now(t0 + 30.0)
	check(Spoilage.stage(raw, warm) == "stale" and Spoilage.stage(raw, cold) == "fresh", "30 hours: going off on the side, fresh in the cold store")
	Settlement.data()["cold_stores"] = 0
	Settlement.data()["ice_boxes"] = 0
	var r_warm := Spoilage.larder_rate()
	Settlement.data()["cold_stores"] = 1
	check(Spoilage.larder_rate() < r_warm, "the larder with a cold store: x%.2f (from x%.2f)" % [Spoilage.larder_rate(), r_warm])
	Settlement.data()["cold_stores"] = 0
	_set_clock(35, 8.0)
	check(Spoilage.season_rate() < 1.0, "winter keeps food (x%.2f)" % Spoilage.season_rate())
	_set_clock(2, 0.0)
	# The smoker preserves it.
	_give([[&"hammer", 1], [&"planks", 6], [&"scrap_sheet", 3]])
	var c := _at(5, 0)
	_stand_by(c + Vector3i(0, 0, -3))
	var smoker := b.server_build_piece_now(player, "smoker", c, 0)
	check(smoker > 0 and b.is_piece_built(smoker), "a smoker built (%s)" % b.last_problem)
	if smoker > 0:
		player.global_position = level.ground_point(b.piece_pos(smoker) + Vector3(1.4, 0, 0)) + Vector3.UP * 0.05
		check("smoker" in Fieldwork.stations_near(player), "standing at the smoker (%s)" % [Fieldwork.stations_near(player)])
		while player.inventory.remove_one(&"raw_meat"):
			pass
		Wildlife._give(player, &"raw_meat", 3)
		player.inventory.take(&"firewood", 1)
		var sm0 := _have(&"smoked_meat")
		check(Crafting.server_craft(player, "smoker_meat", true) == "" and _have(&"smoked_meat") == sm0 + 3, "three cuts smoked")
		var smoked := ItemDB.get_item(&"smoked_meat")
		var sst := _entry_state(&"smoked_meat")
		_set_now(Moods.now_h() + 72.0)
		check(Spoilage.stage(smoked, sst) == "fresh" and Spoilage.stage(raw, Spoilage.made_state(&"raw_meat", {Spoilage.KEY: t0 + 28.0})) == "spoiled",
			"three days on, the smoked meat is good, raw would be spoiled")
		_set_clock(2, 0.0)
	# Eating it.
	var meal := ItemDB.get_item(&"cooked_meal")
	var n := Needs.fresh()
	n.calories = 500.0
	Needs.eat(n, meal, Spoilage.made_state(&"cooked_meal"))
	var fresh_kcal := float(n.calories) - 500.0
	var stale_st := Spoilage.made_state(&"cooked_meal")
	var spoiled_st := stale_st.duplicate()
	_set_now(Moods.now_h() + 30.0)
	n = Needs.fresh()
	n.calories = 500.0
	Spoilage.force_roll = 0.99
	Needs.eat(n, meal, stale_st)
	check(Spoilage.stage(meal, stale_st) == "stale" and absf(float(n.calories) - 500.0 - fresh_kcal * Spoilage.STALE_FOOD) < 1.0 and (n.get("sick", {}) as Dictionary).is_empty(),
		"a stale meal: half the food (%.0f of %.0f kcal)" % [float(n.calories) - 500.0, fresh_kcal])
	_set_now(Moods.now_h() + 30.0)
	n = Needs.fresh()
	Spoilage.force_roll = 0.0
	var got := Needs.eat(n, meal, spoiled_st)
	check(Spoilage.stage(meal, spoiled_st) == "spoiled" and got == "food_poisoning" and String((n.get("sick", {}) as Dictionary).get("id", "")) == "food_poisoning",
		"a spoiled meal: food poisoning (%s)" % got)
	n = Needs.fresh()
	check(Needs.eat(n, meal, Spoilage.made_state(&"cooked_meal")) == "", "a fresh meal: no risk")
	Spoilage.force_roll = -1.0
	# The larder: spoiled stock out as a loss, the oldest first.
	_set_clock(2, 0.0)
	Settlement.server_take("raw_meat", 999)
	st.server_put("raw_meat", 2)
	Spoilage.server_larder_hour(st)
	var lost0 := Spoilage.lost()
	_set_now(Moods.now_h() + 60.0)
	check(Spoilage.server_larder_hour(st) == 2 and Settlement.count("raw_meat") == 0 and Spoilage.lost() == lost0 + 2, "two days on, the larder's raw meat is spoiled: thrown out, counted lost")
	var now := Moods.now_h()
	st.server_put("raw_meat", 1, {Spoilage.KEY: now + 20.0})
	st.server_put("raw_meat", 1, {Spoilage.KEY: now + 5.0})
	Spoilage.server_larder_hour(st)
	var first := Settlement.server_take("raw_meat", 1)
	check(not first.is_empty() and absf(float(((first[0] as Dictionary).get("state", {}) as Dictionary).get(Spoilage.KEY, 0.0)) - (now + 5.0)) < 0.5, "the cook takes the oldest first")
	Settlement.server_take("raw_meat", 99)
	_set_clock(2, 8.0)
	_stand_by(_at(0, -6))


# --- The clinic ------------------------------------------------------------------------------------

func _test_clinic() -> void:
	print("The clinic: the bed heals faster, surgery goes bad less, the doctor and the cabinet, quarantine")
	_give([[&"hammer", 1], [&"planks", 12], [&"cloth_rag", 4], [&"scrap_sheet", 3]])
	var cb := _at(9, 0)
	_stand_by(cb + Vector3i(0, 0, -3))
	var bed := b.server_build_piece_now(player, "clinic_bed", cb, 0)
	var cc := _at(13, 0)
	_stand_by(cc + Vector3i(0, 0, -3))
	var cab := b.server_build_piece_now(player, "clinic_cabinet", cc, 0)
	check(bed > 0 and b.is_piece_built(bed) and cab > 0 and b.is_piece_built(cab), "a clinic bed and a cabinet built (%s)" % b.last_problem)
	st.refresh()
	check(Clinic.beds() == 1 and int(Settlement.data().get("clinic_cabinets", 0)) == 1, "the settlement counts the clinic (%d bed)" % Clinic.beds())
	# Healing.
	var out_n := Needs.fresh()
	var in_n := Needs.fresh()
	Infection.add(out_n, "thigh_l", "venous")
	Infection.add(in_n, "thigh_l", "venous")
	Infection.step(out_n, 10.0, {"risk": 0.0})
	Infection.step(in_n, 10.0, {"risk": 0.0})
	Clinic.care_step(in_n, 10.0, "")
	var h_out := float((Infection.records(out_n)[0] as Dictionary).heal_h)
	var h_in := float((Infection.records(in_n)[0] as Dictionary).heal_h)
	check(h_in < h_out, "ten hours in a clinic bed: %.0f h of healing left, %.0f h outside" % [h_in, h_out])
	if bed > 0:
		player.global_position = level.ground_point(b.piece_pos(bed) + Vector3(1.6, 0, 0)) + Vector3.UP * 0.05
		check(Clinic.in_bed(player) and Surgery.surface_of(player) == "clinic", "lying by the clinic bed: the clinic's surface")
		var n := Survival.needs_of(player)
		Clinic.server_care(player, n, 0.5)
		check(Clinic.words(n).begins_with("in a clinic bed"), "the body screen: %s" % Clinic.words(n))
		_stand_by(_at(0, -6))
		Clinic.server_care(player, n, 0.5)
		check(Clinic.words(n) == "", "out of the bed, out of care")
	# Surgery's infection chance.
	check(Clinic.infect_chance("clinic") < Clinic.infect_chance("bed") and Clinic.infect_chance("bed") < Clinic.infect_chance("ground"),
		"surgery goes bad: clinic %.0f%%, a bunk %.0f%%, the ground %.0f%%" % [100.0 * Clinic.infect_chance("clinic"), 100.0 * Clinic.infect_chance("bed"), 100.0 * Clinic.infect_chance("ground")])
	var r_clinic := {"stage": 0, "dirt": 0.0, "stage_h": 0.0}
	var r_ground := r_clinic.duplicate()
	check(not Clinic.after_surgery(r_clinic, "clinic", 0.1) and Clinic.after_surgery(r_ground, "ground", 0.1) and int(r_ground.stage) == 1,
		"the same luck: clean in the clinic, contaminated on the ground")
	check(Clinic.post_op_roll(0.5) >= 1.0, "a test forcing the surgery's own roll never rolls the post-op")
	# The doctor.
	var recs := SurvivorsLayer.records()
	var doc := {"id": "hands_doc", "name": "Ana Reyes", "status": "settler", "jobs": ["doctor"], "background": "doctor", "needs": Needs.fresh(), "wounds": [], "settled_h": 0.0}
	var pat := {"id": "hands_pat", "name": "Tom Hale", "status": "settler", "jobs": ["haul"], "background": "", "needs": Needs.fresh(),
		"wounds": [{"kind": "cut", "day": 1}, {"kind": "gunshot", "day": 1}], "settled_h": 1.0}
	recs["hands_doc"] = doc
	recs["hands_pat"] = pat
	check(Clinic.medical_of(doc) >= Clinic.DOCTOR_LEVEL and Clinic.doctor_name() == "Ana Reyes", "a doctor by trade takes the job (medicine %d)" % Clinic.medical_of(doc))
	Clinic.rec()["stock"] = {"pressure_bandage": 3}
	Clinic.force_roll = 0.5
	check(SettlementJobs.do_job(st, "doctor", doc, 1.0) and String(pat.get("in_care", "")) == "Ana Reyes", "the doctor's hour: the patient in a bed")
	var wounds: Array = pat.wounds
	check(wounds.size() == 1 and bool((wounds[0] as Dictionary).get("operated", false)) and Clinic.stock_count() == 1,
		"the cut dressed from the cabinet, the gunshot operated on (%d left, %d in the cabinet)" % [wounds.size(), Clinic.stock_count()])
	SettlementJobs.do_job(st, "doctor", doc, 1.0)
	check((pat.wounds as Array).is_empty() and Clinic.stock_count() == 0 and not Clinic.open_order().is_empty(),
		"the next hour he's patched up; the cabinet low: an order (%s)" % WorkOrders.text_of(Clinic.open_order()) if not Clinic.open_order().is_empty() else "no order")
	Clinic.rec()["stock"] = {}
	st.server_put("pressure_bandage", 4)
	check(WorkOrders.work_for(st, "doctor", 1.0) and Clinic.stock_count() >= 4, "the order: meds from the stores into the cabinet (%d)" % Clinic.stock_count())
	Clinic.force_roll = -1.0
	var players_n := Needs.fresh()
	Infection.add(players_n, "forearm_l", "graze")
	Clinic.care_step(players_n, 1.0, Clinic.doctor_name())
	check(Clinic.words(players_n) == "in care: Ana Reyes" and float(players_n.get("care_h", 0.0)) > 0.0, "in care with the doctor: %s (and the bite's fever slower)" % Clinic.words(players_n))
	# Quarantine.
	var vid := Clinic.server_quarantine(pat)
	check(vid >= 0 and bool(pat.get("quarantine", false)) and Clinic.patients(st)[0] == pat, "a bitten settler into quarantine; the council votes (%d)" % vid)
	Clinic.on_vote("hands_pat", "keep them")
	check(bool(pat.get("quarantine_kept", false)), "the council keeps them in the bed")
	recs.erase("hands_doc")
	recs.erase("hands_pat")


# --- Helpers --------------------------------------------------------------------------------------------

func _set_clock(day: int, hour: float) -> void:
	Survival.server_set_options({"season": "spring"})
	Survival.state()["day"] = day
	Survival.state()["hour"] = hour


func _set_now(h: float) -> void:
	Survival.state()["day"] = floori(h / 24.0)
	Survival.state()["hour"] = fposmod(h, 24.0)


func _have(id: StringName) -> int:
	return player.inventory.count_of(id) + _dropped(id)


func _entry_state(id: StringName) -> Dictionary:
	for c: StringName in player.inventory.search_containers():
		for e: Dictionary in player.inventory.containers.get(c, []):
			if StringName(String(e.id)) == id:
				return (e.get("state", {}) as Dictionary).duplicate(true)
	return {}


func _dropped(id: StringName) -> int:
	var n := 0
	for d: Dictionary in GameState.dropped.values():
		if String(d.get("id", "")) == String(id):
			n += int(d.get("count", 0))
	return n


func _spot(plant: String) -> int:
	var best := -1
	var best_d := INF
	var home := Settlement.pos()
	for i in level.scatter.items.size():
		var item: Dictionary = level.scatter.items[i]
		if Foraging.plant_of(item) != plant:
			continue
		var d := (item.pos as Vector3).distance_to(home)
		if d < best_d:
			best_d = d
			best = i
	return best


func _tree_of(sp: String) -> int:
	var best := -1
	var best_d := INF
	var home := Settlement.pos()
	for i in level.scatter.items.size():
		var item: Dictionary = level.scatter.items[i]
		if int(item.kind) != ZoneScatter.Kind.TREE or item.has("felled") or Trees.species_of(item) != sp:
			continue
		var d := (item.pos as Vector3).distance_to(home)
		if d < best_d:
			best_d = d
			best = i
	return best


func _at_spot(index: int) -> void:
	var p: Vector3 = level.scatter.items[index].pos
	player.global_position = level.ground_point(p + Vector3(1.0, 0, 0)) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO


func _flat_and_clear(x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dx in range(-10, 11, 2):
		for dz in range(-10, 11, 2):
			var h := level.ground_height(x + dx * 0.5, z + dz * 0.5)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			for up in [0.3, 1.2, 2.2]:
				if b._structure_at(Vector3(x + dx * 0.5, h + up, z + dz * 0.5)):
					return false
	return hi - lo < 0.5


func _at(dx: int, dz: int) -> Vector3i:
	var p := BuildPieces.cell_centre(origin + Vector3i(dx, 0, dz))
	return Builder.ground_cell(Vector3(p.x, level.ground_height(p.x, p.z), p.z))


func _pos(c: Vector3i) -> Vector3:
	var p := BuildPieces.cell_centre(c)
	return Vector3(p.x, level.ground_height(p.x, p.z) + 0.05, p.z)


func _stand_by(c: Vector3i) -> void:
	player.global_position = _pos(c) + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var crowd := ZoneDead.of(level)
	if crowd:
		crowd.dead.clear()


func _give(pairs: Array) -> void:
	for pair: Array in pairs:
		player.inventory.take(StringName(pair[0]), int(pair[1]))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	Seasons.force_frost = -1
	Wildlife.force_roll = -1.0
	Fieldwork.force_roll = -1.0
	Spoilage.force_roll = -1.0
	Clinic.force_roll = -1.0
	Wildlife.forget()
	Flora.reset()
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("HANDS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
