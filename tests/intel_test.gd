extends Node
## Contractor: Fallen's trade and intel layer (docs/survival_intel.md; survival_world.md sections 8
## and 10; calls 26, 37, 45, 95, 98): values from prices and types with the weights; a needy trader
## pays more for food; a trade moves items and standing, an unfair offer is refused, cheating costs
## standing with everyone who hears; a told rumour makes a journal entry and a mark with the teller,
## a lie is recorded as told (not flagged); the journal screen shows a log line, a person and a
## place; the radio needs repair and power and a broadcast makes a journal line; marks fade after
## three days; the political colour follows region_holders; a landmark name resolves near a
## module; the map table lists a sighting and a trade route.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var sim: WorldSim
var here := ""
var there := ""
var scav: Dictionary
var scav_rec: Dictionary


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("INTEL TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null and sim != null:
		_test_values()
		_test_needy_trader()
		_test_trade()
		_test_cheating()
		_test_rumours()
		_test_journal_screen()
		_test_radio()
		_test_marks_fade()
		_test_political_colour()
		_test_landmarks()
		_test_map_table()
	_finish()


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_intel" + tag, 1357), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 25.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	sim = WorldSim.get_sim()
	await _wait_for(func() -> bool: return WorldSim.is_set_up(), 20.0)
	check(player != null and sim != null and WorldSim.is_set_up() and Intel.get_intel() != null, "the survivor is in; the world sim and the intel node are under Survival")
	if sim == null or player == null:
		return
	sim.enabled = false  # (the test drives the world)
	player.inventory.take(&"pack_daypack_20")  # (room for what the tests hand him)
	here = String(Survival.state().zone)
	var links: Array = ((WorldSim.section().zones as Dictionary)[here] as Dictionary).get("links", [])
	there = String(links[0]) if not links.is_empty() else here
	check(there != here, "the zone has a neighbour (%s -> %s)" % [here, there])


# --- Trade ---------------------------------------------------------------------------------------

func _test_values() -> void:
	print("The value scale")
	var p: Dictionary = WorldTrade.prices().items
	var mag := WorldTrade.value("mag_556")
	check(is_equal_approx(mag, maxf(float(p.mag_556), 10.0) * float(WorldTrade.WEIGHT.ammo)), "a priced item: prices.json x the ammo weight ($%.0f for a 5.56 mag, $%d in the shop)" % [mag, int(p.mag_556)])
	var beans := WorldTrade.value("beans_tin")
	check(beans >= float(WorldTrade.CATEGORY_FLOOR.food) * float(WorldTrade.WEIGHT.food) - 0.01 and beans > float(p.beans_tin), "food weighs more than the shop's tin ($%.0f vs $%d)" % [beans, int(p.beans_tin)])
	# An item no price, tag or category covers: its type's default.
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var all: Array = (JSON.parse_string(f.get_as_text()) as Dictionary).items
	var plain := ""
	for it: Dictionary in all:
		var id := String(it.id)
		var tags: Array = it.get("tags", [])
		if p.has(id) or tags.any(func(t: String) -> bool: return WorldTrade.TAG_VALUE.has(t)) or Settlement.category_of(id) != "":
			continue
		if (WorldTrade.prices().default_by_type as Dictionary).has(String(it.type)):
			plain = id
			break
	var by_type: Dictionary = WorldTrade.prices().default_by_type
	check(plain != "" and is_equal_approx(WorldTrade.value(plain), float(by_type[String(ItemDB.get_item(StringName(plain)).type)])),
		"an unpriced item goes by its type ($%.0f for %s)" % [WorldTrade.value(plain) if plain != "" else 0.0, plain])
	check(WorldTrade.value("water_bottle", "desert") > WorldTrade.value("water_bottle"), "the region hook: water dearer in the desert ($%.0f vs $%.0f)" % [WorldTrade.value("water_bottle", "desert"), WorldTrade.value("water_bottle")])
	var cash := WorldTrade.value("cash_roll")
	check(cash >= 50.0 * (1.0 - WorldTrade.CASH_DRIFT) - 0.01 and cash <= 50.0 * (1.0 + WorldTrade.CASH_DRIFT) + 0.01, "cash is its face, drifted by the seed ($%.2f a roll)" % cash)


func _test_needy_trader() -> void:
	print("A trader's need")
	var m := WorldSim.model()
	var needy := m.new_group("settlers", there, Vector2.ZERO, m.rng_for("intel_needy"), 3)
	var full := m.new_group("settlers", there, Vector2(50, 0), m.rng_for("intel_full"), 3)
	needy.supplies.food = 0.0
	full.supplies.food = 60.0
	needy.relations["player"] = 0.0
	full.relations["player"] = 0.0
	var a := WorldTrade.buy_price(needy, "canned_meat")
	var b := WorldTrade.buy_price(full, "canned_meat")
	check(a > b, "a group short of food pays more for a tin ($%.0f) than one with food to spare ($%.0f)" % [a, b])
	needy.relations["player"] = 80.0
	check(WorldTrade.buy_price(needy, "canned_meat") > a and WorldTrade.sell_price(needy, "canned_meat") < WorldTrade.sell_price(full, "canned_meat") * WorldTrade.NEED_HIGH / WorldTrade.NEED_LOW,
		"friends pay more and ask less")
	check(Barter.is_trader(WorldSim.people()[String(needy.leader)]) and not Barter.is_trader(WorldSim.people()[String(needy.members[1])]),
		"a settlement trades through its leader: \"%s\"" % Barter.trader_problem(WorldSim.people()[String(needy.members[1])]))
	var r := m.new_group("raiders", there, Vector2(90, 0), m.rng_for("intel_raid"), 3)
	check(not Barter.is_trader(WorldSim.people()[String(r.leader)]), "raiders don't trade")
	needy.alive = false
	full.alive = false
	r.alive = false


func _test_trade() -> void:
	print("A trade")
	var m := WorldSim.model()
	scav = m.new_group("scavengers", there, Vector2.ZERO, m.rng_for("intel_scav"), 3)
	scav.supplies.food = 40.0
	scav.supplies.ammo = 0.0
	scav.relations["player"] = 0.0
	scav_rec = WorldSim.people()[String(scav.leader)]
	player.inventory.take(&"mag_556", 3)
	var deal := Barter.deal(player, scav_rec)
	var theirs: Array = deal.theirs
	check(String(deal.why) == "" and theirs.any(func(r: Dictionary) -> bool: return String(r.id) == "canned_meat"),
		"scavengers on the road trade: their spare food on the table (%d kinds of goods)" % theirs.size())
	check(theirs.any(func(r: Dictionary) -> bool: return String(r.id) in ["cash_roll", "cash_bundle"]), "and their cash")
	var mags0 := player.inventory.count_of(&"mag_556")
	var tins0 := player.inventory.count_of(&"canned_meat")
	var rel0 := WorldGroup.relation(scav, "player")
	var events0 := (WorldSim.section().events as Array).size()
	var unfair := Barter.server_trade(player, scav_rec, {}, {"canned_meat": 4})
	check(not bool(unfair.ok) and String(unfair.why) == "unfair" and player.inventory.count_of(&"canned_meat") == tins0,
		"an unfair offer is refused (\"%s\") and nothing moves" % String(unfair.said))
	var ts := TradeScreen.new()
	add_child(ts)
	ts.open(deal)
	ts.put("theirs", "canned_meat", 4)
	check(not ts.can_confirm() and ts.text().contains("they won't take it"), "the barter screen's balance says so and Confirm waits")
	ts.put("yours", "mag_556", 1)
	ts.put("theirs", "canned_meat", -2)
	check(ts.can_confirm() and ts.balance() >= 0.0, "one mag for two tins: even or in their favour ($%.0f)" % ts.balance())
	ts.queue_free()
	var done := Barter.server_trade(player, scav_rec, {"mag_556": 1}, {"canned_meat": 2})
	check(bool(done.ok), "a fair offer is taken (\"%s\")" % String(done.get("said", "")))
	check(player.inventory.count_of(&"mag_556") == mags0 - 1 and player.inventory.count_of(&"canned_meat") >= tins0 + 2,
		"the items move: a mag less, two tins more (%d, %d)" % [player.inventory.count_of(&"mag_556"), player.inventory.count_of(&"canned_meat")])
	check(WorldGroup.supply(WorldSim.group(String(scav.id)), "ammo") > 0.0, "the mag goes into their group's ammo")
	check(WorldGroup.relation(WorldSim.group(String(scav.id)), "player") > rel0, "their standing goes up (%.0f -> %.0f)" % [rel0, WorldGroup.relation(WorldSim.group(String(scav.id)), "player")])
	check((WorldSim.section().events as Array).slice(events0).any(func(e: Dictionary) -> bool: return String(e.kind) == "trade" and "player" in (e.groups as Array)),
		"the trade is an event in the world's pool")
	var j: Array = Survival.state().journal
	check(String((j[-1] as Dictionary).text).begins_with("Traded with"), "and a journal line: \"%s\"" % String((j[-1] as Dictionary).text))


func _test_cheating() -> void:
	print("Cheating")
	var m := WorldSim.model()
	var other := m.new_group("settlers", there, Vector2(30, 0), m.rng_for("intel_witness"), 3)
	var far_zone := ""
	for z: String in WorldSim.section().zones:
		var zd: Dictionary = WorldSim.section().zones[z]
		if z != there and not there in (zd.links as Array) and z != here:
			far_zone = z
			break
	var far := m.new_group("settlers", far_zone, Vector2.ZERO, m.rng_for("intel_far"), 2)
	var r_scav := WorldGroup.relation(scav, "player")
	var r_other := WorldGroup.relation(other, "player")
	var r_far := WorldGroup.relation(far, "player")
	var heard := Barter.server_cheated(String(scav.id), there)
	check(WorldGroup.relation(WorldSim.group(String(scav.id)), "player") <= r_scav + Barter.CHEAT_RELATION + 0.01, "the cheated group's standing drops")
	check(String(other.id) in heard and WorldGroup.relation(WorldSim.group(String(other.id)), "player") < r_other, "a group in the zone hears and thinks less of us")
	check(not String(far.id) in heard and is_equal_approx(WorldGroup.relation(far, "player"), r_far), "a group far off doesn't hear")
	other.alive = false
	far.alive = false
	WorldGroup.change_relation(WorldSim.group(String(scav.id)), "player", 40.0)  # (made up again for what follows)


# --- Rumours and the journal ---------------------------------------------------------------------

func _test_rumours() -> void:
	print("Rumours")
	var e := Intel.server_event(there, "fight", [String(scav.id)], "a fight at the grain silo")
	check(not e.is_empty() and (scav.get("intel", {}) as Dictionary).has(str(e.id)), "the scavengers know of a fight in %s" % there)
	var said := Intel.server_ask(scav_rec, "places", here)
	var r: Dictionary = said.rumour
	check(not r.is_empty() and String(said.text) != "", "asked about other places, %s tells one: \"%s\"" % [String(scav_rec.name), String(said.text)])
	var j: Dictionary = (Survival.state().journal as Array)[-1]
	check(String(j.get("kind", "")) == "told" and String(j.get("by", "")) == String(scav_rec.name) and String(j.text).contains(String(said.text)),
		"a journal entry, told by them: \"%s\"" % String(j.text))
	var marks := SurvivalMap.marks(String(r.get("zone", "")))
	var mark: Dictionary = marks[-1] if not marks.is_empty() else {}
	check(String(mark.get("kind", "")) == "told" and String(mark.get("teller", "")) == String(scav_rec.name), "a mark in %s with the teller" % String(r.get("zone", "")))
	check(SurvivalMap.is_known(String(r.get("zone", ""))), "and the zone goes on the map as told")
	var again := Intel.server_ask(scav_rec, "places", here)
	check(String(again.text) == "" or int((again.rumour as Dictionary).get("event", -9)) != int(r.event), "the same rumour isn't told twice")
	# A raider's tale is a lie, and the record doesn't say so.
	var m := WorldSim.model()
	var raiders := m.new_group("raiders", there, Vector2(60, 0), m.rng_for("intel_liars"), 3)
	var e2 := Intel.server_event(there, "horde", [String(raiders.id)], "a horde came down on the quarry")
	var liar: Dictionary = WorldSim.people()[String(raiders.leader)]
	var lie := Intel.server_ask(liar, "places", here)
	check(String((lie.rumour as Dictionary).get("truth", "")) == "lie" and int((lie.rumour as Dictionary).get("event", 0)) == int(e2.id), "a raider lies about the horde: \"%s\"" % String(lie.text))
	var lj: Dictionary = (Survival.state().journal as Array)[-1]
	var lmarks := SurvivalMap.marks(there)
	var lm: Dictionary = lmarks[-1] if not lmarks.is_empty() else {}
	check(String(lj.get("kind", "")) == "told" and not lj.has("truth") and not String(lj.text).contains("(lie)"), "the lie is in the journal as told, not flagged")
	check(String(lm.get("kind", "")) == "told" and not lm.has("truth") and String(lm.get("teller", "")) == String(liar.name), "and on the map the same: told, with its teller")
	raiders.alive = false


func _test_journal_screen() -> void:
	print("The journal screen")
	var js := JournalScreen.new()
	add_child(js)
	js.show_view(JournalScreen.view())
	var t := js.text()
	check(t.contains("told me") and t.contains("Day %d" % Survival.day()), "Log: by day, with what we were told")
	js.tab = "people"
	js.refresh()
	check(js.text().contains(String(scav_rec.name)) and js.text().contains("wants"), "People: %s, with their want" % String(scav_rec.name))
	js.tab = "places"
	js.refresh()
	check(js.text().contains("told by " + String(scav_rec.name)), "Places: the mark with who told it")
	js.tab = "trail"
	js.refresh()
	check(js.text().contains("Nothing of the trail yet"), "The trail: empty until the enclave lane writes it")
	js.queue_free()


# --- The radio -----------------------------------------------------------------------------------

func _test_radio() -> void:
	print("The radio")
	for b: StringName in FallenRadio.BATTERIES:
		while player.inventory.remove_one(b):
			pass
	check(FallenRadio.server_set_on(player, true) != "" and not FallenRadio.is_on(), "no radio, no radio")
	player.inventory.take(&"radio")
	check(FallenRadio.server_set_on(player, true).contains("repair"), "a found radio is dead: \"%s\"" % FallenRadio.server_set_on(player, true))
	check(FallenRadio.server_repair(player).contains("parts"), "repairing it needs radio parts")
	player.inventory.take(&"radio_parts")
	Rpg.set_level(player, FallenRadio.SKILL, 0)
	var gate := FallenRadio.server_repair(player)
	check(gate.contains("mechanics") or not Rpg.active(player), "and the mechanics line (\"%s\")" % gate)
	Rpg.set_level(player, FallenRadio.SKILL, FallenRadio.REPAIR_LEVEL)
	check(FallenRadio.server_repair(player) == "" and bool(FallenRadio.data().repaired) and player.inventory.count_of(&"radio_parts") == 0, "repaired, the parts used")
	check(FallenRadio.server_set_on(player, true).contains("power") and not FallenRadio.is_on(), "no battery and no generator: no power")
	player.inventory.take(&"battery_aa")
	check(FallenRadio.server_set_on(player, true) == "" and FallenRadio.is_on(), "a battery: it comes on")
	var n0 := (Survival.state().journal as Array).size()
	var heard: Array = []
	for i in 3:
		var b := FallenRadio.server_broadcast(level)
		if not b.is_empty():
			heard.append(String(b.kind))
	var lines := (Survival.state().journal as Array).slice(n0)
	check(heard.size() == 3 and lines.size() >= 3 and lines.all(func(l: Dictionary) -> bool: return String(l.get("kind", "")) == "radio"), "broadcasts become journal lines (%s)" % ", ".join(heard))
	check("numbers" in heard, "ARCHE's numbers station plays (canned until the trail has its own)")
	FallenRadio.data().next = 0.0
	var b2 := FallenRadio.server_tick(level, player)
	check(not b2.is_empty() and player.inventory.count_of(&"battery_aa") == 0 and float(FallenRadio.data().battery) > 0.0, "on its clock a broadcast is due, a battery in use")
	check(FallenRadio.server_set_on(player, false) == "" and not FallenRadio.is_on(), "and off")


# --- The map -------------------------------------------------------------------------------------

func _test_marks_fade() -> void:
	print("Marks age")
	var fresh := SurvivalMap.server_add_mark(here, Vector3(10, 0, 10), "A camp", "camp")
	var old := SurvivalMap.server_add_mark(here, Vector3(20, 0, 20), "An old camp", "camp")
	old["day_seen"] = SurvivalMap.now() - 3.1
	old["day_added"] = old.day_seen
	check(not SurvivalMap.is_faded(fresh) and SurvivalMap.is_faded(old), "a mark seen three days ago is faded (%s), today's isn't" % SurvivalMap.age_text(old))
	var told := SurvivalMap.marks(there).filter(func(mk: Dictionary) -> bool: return String(mk.get("teller", "")) != "")
	if not told.is_empty():
		(told[0] as Dictionary)["day_seen"] = SurvivalMap.now() - 3.5
		check(SurvivalMap.is_faded(told[0]), "a told one too")


func _test_political_colour() -> void:
	print("The political colour")
	var region := WorldSim.region_of(there)
	var saved := {}
	for z: String in WorldSim.section().zones:
		var zd: Dictionary = WorldSim.section().zones[z]
		if String(zd.region) != region:
			continue
		for p: Dictionary in zd.places:
			saved[z + "|" + String(p.id)] = String(p.holder)
			p.holder = ""
	check(FallenMap.political_colour(there).a == 0.0, "a region nobody holds is clear")
	var m := WorldSim.model()
	var a := m.new_group("raiders", there, Vector2.ZERO, m.rng_for("intel_pol_a"), 2)
	var b := m.new_group("settlers", there, Vector2.ZERO, m.rng_for("intel_pol_b"), 2)
	var places: Array = (WorldSim.section().zones[there] as Dictionary).places
	(places[0] as Dictionary).holder = String(a.id)
	if places.size() > 1:
		(places[1] as Dictionary).holder = String(a.id)
	var c1 := FallenMap.political_colour(there)
	check(c1.a > 0.0 and is_equal_approx(c1.r, (FallenMap.KIND_COLOURS.raiders as Color).r) and is_equal_approx(c1.g, (FallenMap.KIND_COLOURS.raiders as Color).g),
		"raiders hold most of %s: it washes red (%s)" % [region, str(WorldSim.region_holders(region))])
	for p: Dictionary in places:
		p.holder = String(b.id)
	var c2 := FallenMap.political_colour(there)
	check(is_equal_approx(c2.g, (FallenMap.KIND_COLOURS.settlers as Color).g) and is_equal_approx(c2.r, (FallenMap.KIND_COLOURS.settlers as Color).r), "settlers take it: green")
	for z: String in WorldSim.section().zones:
		var zd: Dictionary = WorldSim.section().zones[z]
		for p: Dictionary in zd.places:
			if saved.has(z + "|" + String(p.id)):
				p.holder = saved[z + "|" + String(p.id)]
	a.alive = false
	b.alive = false


func _test_landmarks() -> void:
	print("Landmarks")
	var all := Landmarks.of(here)
	check(all.size() >= Landmarks.EXTRAS, "%s has named points: %s" % [here, ", ".join(PackedStringArray(all.map(func(l: Dictionary) -> String: return String(l.name))))])
	var module: Dictionary = {}
	for l: Dictionary in all:
		if not String(l.kind) in ["water_tower", "radio_mast", "hill"]:
			module = l
			break
	if module.is_empty() and not all.is_empty():
		module = all[0]
	var p: Vector2 = module.get("pos", Vector2.ZERO)
	var lname := Landmarks.nearest_name(Vector3(p.x + 4.0, 0.0, p.y - 3.0), here)
	check(lname == String(module.get("name", "?")), "a point by a module resolves to its name (\"%s\")" % lname)
	check(Landmarks.meet_order(Vector3(p.x, 0.0, p.y), here) == "Meet at %s" % lname, "an order names it: \"%s\"" % Landmarks.meet_order(Vector3(p.x, 0.0, p.y), here))
	var back: Variant = Landmarks.resolve(lname, here)
	check(back is Vector2 and (back as Vector2).distance_to(p) < 0.1, "and the name turns back into the place")
	var dup := Landmarks.of(here)
	check(dup.size() == all.size() and String((dup[0] as Dictionary).name) == String((all[0] as Dictionary).name), "the same seed, the same names")


func _test_map_table() -> void:
	print("The map table")
	var m := WorldSim.model()
	var ally := m.new_group("settlers", there, Vector2(10, 0), m.rng_for("intel_ally"), 3)
	ally.relations["player"] = 70.0
	var t1 := m.new_group("scavengers", there, Vector2(20, 0), m.rng_for("intel_t1"), 2)
	var t2 := m.new_group("settlers", here, Vector2(30, 0), m.rng_for("intel_t2"), 2)
	Intel.server_event(there, "fight", [String(ally.id)], "a fight on the ridge road")
	Intel.server_event(there, "trade", [String(t1.id), String(t2.id)], "%s traded with %s" % [String(t1.name), String(t2.name)])
	var r := MapTable.reports()
	var sight: Array = r.sightings
	var routes: Array = r.routes
	check(sight.any(func(s: Dictionary) -> bool: return String(s.text).contains("ridge road") and String(s.from) == String(ally.name)), "an ally's sighting of the last day (%d)" % sight.size())
	check(routes.any(func(t: Dictionary) -> bool: return String(t.a) == String(t1.id) and String(t.b) == String(t2.id)), "a trade route between their homes (%d)" % routes.size())
	(ally.knows as Dictionary)[String(t1.id)] = {"t": WorldSim.world_now() - 1.5, "zone": there, "scouted": true}
	var mv: Array = MapTable.reports().movements
	check(mv.any(func(x: Dictionary) -> bool: return String(x.group) == String(t1.id) and float(x.age) > 1.0), "a known group's movement, aged")
	var b := Builder.find(level)
	check(b != null, "the zone has its builder")
	if b:
		check(not MapTable.near(player), "away from a map table, no reports on the map")
		var id: int = b._next_id
		var c := BuildPieces.cell_at(player.global_position + Vector3(1.0, 0.0, 0.0))
		b._set_piece(id, {"k": MapTable.PIECE, "c": [c.x, c.y, c.z], "r": 0, "hp": 80.0, "prog": 1.0, "bp": false, "paid": true, "open": false, "locked": false, "lock": {}})
		check(MapTable.near(player), "standing at the built map table")
		b._set_piece(id, {})
	check(BuildPieces.PIECES.has("map_table") and "map_table" in BuildPieces.PIECE_KEYS, "the map table is a build piece")
	ally.alive = false
	t1.alive = false
	t2.alive = false


# --- Helpers -------------------------------------------------------------------------------------

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
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("INTEL TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
