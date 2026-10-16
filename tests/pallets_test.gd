extends Node
## Headless checks for supply pallets, tagging and the FOB stocks (feat/pallet-tagging, Pallets,
## PalletField, docs/pallets.md): pallet kinds and values from data/pallets.json, tagging a
## pallet from the interaction menu (sell, gift, untag, reach, a map marker), the lots hauled
## home into the debrief, and there: sell now (the quick price), keep (the FOB's stocks), store
## then sell from storage (the better price), gift (reputation), what's undecided when the debrief
## closes, a vehicle lot, stocks offsetting a support call and a repair, drawing stock into the
## armory inbox, and the stocks saved with the campaign. One process:
##   <exe> --headless --path . res://tests/pallets_test.tscn
## Prints PALLETS TEST PASSED/FAILED and exits with its failure count.

var failures := 0
var level: CompoundLevel
var player: Soldier
var field: PalletField
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_pallets" + tag  # never touch a real save
	Campaign.campaign_id = "test_pallets_campaign" + tag
	CompoundLevel.spawn_ai = false
	PeopleLayer.contract_people = false
	Contracts.auto_show_debrief = false
	Contracts.autosave = false
	get_tree().create_timer(280.0).timeout.connect(func() -> void:
		print("PALLETS TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	Campaign.reset_campaign()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	_test_data()
	$Main/Menu.host_forest_zone()  # a real zone: village, compound and checkpoint modules
	level = CompoundLevel.current(self)
	var deadline := Time.get_ticks_msec() + 120000
	while (level.players.get_node_or_null(^"1") == null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	for i in 30:
		await get_tree().process_frame
	await _test_zone_sites()
	await _test_tagging()
	await _test_debrief_and_fob()
	_test_stock_effects()
	_test_save_reload()
	Campaign.reset_campaign()
	GameState.delete_save()
	print("PALLETS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Data ------------------------------------------------------------------------------------

func _test_data() -> void:
	print("Pallet kinds and values")
	var kinds := Pallets.pallet_kinds()
	check(kinds.size() >= 6 and "fuel_drums" in kinds and "fuel_bladder" in kinds and "mixed" in kinds and "medical" in kinds and "parts" in kinds,
		"the kinds: %s" % [kinds])
	var a := Pallets.roll("mixed", "m1_pal0")
	var b := Pallets.roll("mixed", "m1_pal0")
	var c := Pallets.roll("mixed", "m9_pal3")
	check(a == b and int(a.value) > 0 and (a.units as Dictionary).size() == 5, "a roll is the same on every peer and a mixed load holds five stock kinds ($%d)" % int(a.value))
	var values := {}
	for i in 12:
		values[int(Pallets.roll("ammo", "x%d" % i).value)] = true
	check(values.size() >= 4 and a != c, "values vary from pallet to pallet (%d different ammo pallets in 12)" % values.size())
	var lot := Pallets.pallet_lot("fuel_drums", "t1")
	check(Pallets.sell_price(lot) == roundi(int(lot.value) * 0.5) and Pallets.sell_price(lot, true) > Pallets.sell_price(lot)
		and Pallets.gift_rep(lot) >= 1 and Pallets.can_keep(lot), "quick sale %d, storage sale %d, gift +%d rep" % [Pallets.sell_price(lot), Pallets.sell_price(lot, true), Pallets.gift_rep(lot)])
	check(not Pallets.can_keep(Pallets.vehicle_lot("technical_dshk", false, "v:x", "Technical")) and Pallets.vehicle_lot("matv", true, "v:y", "M-ATV").value < Pallets.vehicle_lot("matv", false, "v:y", "M-ATV").value,
		"a vehicle can't go into the stocks and a wreck is worth less")
	var sites_ok := true
	for t: String in ["outpost", "checkpoint", "village", "qrf_base", "hq", "comms"]:
		sites_ok = sites_ok and not Pallets.sites(t).is_empty()
	check(sites_ok, "the enemy sites carry pallets")
	check(not Pallets.sale_offer(lot, "meridian").available and float(Pallets.sale_offer(lot, "meridian").betrayal_risk) >= 0.0, "the sale-mission hook answers: not available yet")


# --- Tagging -----------------------------------------------------------------------------------

## The zone builds its own pallets and parks an abandoned vehicle at the checkpoint.
func _test_zone_sites() -> void:
	print("Pallets and an abandoned vehicle at the zone's sites")
	var zone := level as ZoneLevel
	check(zone != null, "the forest is a zone level")
	var built := PalletField.of(level)
	check(built != null and built.pallets.size() == 4 and built.pallets.has("village_pal0") and built.pallets.has("checkpoint_pal1"),
		"every site has its pallets (%s)" % [built.pallets.keys() if built else "no field"])
	var a := built.pallets["village_pal0"] as SupplyPallet
	var ground := zone.ground_height(a.global_position.x, a.global_position.z)
	check(absf(a.global_position.y - ground) < 0.5, "a pallet stands on the ground (%.2f m off)" % absf(a.global_position.y - ground))
	var layer := level.get_node(^"Vehicles") as VehicleLayer
	var abandoned := layer.find("checkpoint_abv0")
	check(abandoned != null and abandoned.has_meta(&"abandoned") and abandoned.faction == &"hostile" and abandoned.occupants().is_empty(), "an abandoned technical sits at the checkpoint")
	if abandoned == null:
		return
	var key := PalletField.vehicle_key(abandoned)
	player.global_position = abandoned.global_position + Vector3(4, 0.5, 0)
	check(built.server_tag(key, "sell", "") == "" and built.tag_text(key) == "TAG: SELL" and abandoned.get_node_or_null(^"TagLabel") != null, "it can be tagged to sell, with a marker on it")
	var points := abandoned.find_children("*", "VehicleActionPoint", true, false)
	var labels: Array = []
	for pt: Node in points:
		for act: Dictionary in InteractionMenu.actions_for(player, pt):
			labels.append(String(act.label))
	check(labels.any(func(l: String) -> bool: return l.begins_with("Untag")) and "Tag for..." in labels, "its action points offer Tag for... and Untag: %s" % [labels])
	var lot: Dictionary = built.lots()[0]
	check(lot.kind == "vehicle" and lot.what == "technical_dshk" and int(lot.value) > 0, "and it is a vehicle lot worth $%d" % int(lot.value))
	built.server_tag(key, "none", "")
	player.global_position = a.global_position + Vector3(2, 1, 0)
	check(built.server_tag("village_pal0", "sell", "") == "" and built.lots().size() == 1, "a zone pallet tags too")
	built.server_tag("village_pal0", "none", "")


func _pallet(uid: String, kind: String, offset: Vector3) -> SupplyPallet:
	var p := SupplyPallet.new(uid, kind)
	p.field = field
	field.add_child(p)
	p.global_position = player.global_position + offset
	field.pallets[uid] = p
	return p


func _test_tagging() -> void:
	print("Tagging a pallet")
	field = PalletField.of(level)  # the zone's own field: the pallets set out by hand sit beside its
	var fuel := _pallet("t_fuel", "fuel_drums", Vector3(2, 0, 0))
	var far := _pallet("t_far", "ammo", Vector3(60, 0, 0))
	var employers := Pallets.gift_factions()
	var actions := InteractionMenu.actions_for(player, fuel)
	var labels := actions.map(func(a: Dictionary) -> String: return String(a.label))
	check("Tag to sell" in labels and "Tag for..." in labels and "Check pallet" in labels and not labels.any(func(l: String) -> bool: return l.begins_with("Untag")),
		"the menu offers Tag to sell, Tag for..., Check pallet: %s" % [labels])
	var sub: Dictionary = actions.filter(func(a: Dictionary) -> bool: return a.id == &"tag_for")[0]
	check((sub.items as Array).size() == employers.size() and employers.size() >= 2, "Tag for... lists the %d employers" % employers.size())
	var markers := MapNodes.markers(field)
	var before := markers.markers.size() if markers else 0
	InteractionMenu.perform(player, actions.filter(func(a: Dictionary) -> bool: return a.id == &"tag_sell")[0])
	check(field.tag_of("t_fuel").get("mode") == "sell" and field.tag_text("t_fuel") == "TAG: SELL", "choosing Tag to sell tags it (%s)" % field.tag_text("t_fuel"))
	check(markers != null and markers.markers.size() == before + 1, "and puts a marker on the map")
	var again := InteractionMenu.actions_for(player, fuel).map(func(a: Dictionary) -> String: return String(a.label))
	check(again.any(func(l: String) -> bool: return l.begins_with("Untag")), "a tagged pallet offers Untag: %s" % [again])
	InteractionMenu.perform(player, (sub.items as Array)[0])
	check(field.tag_of("t_fuel").get("mode") == "gift" and field.tag_of("t_fuel").faction == employers[0] and field.tag_text("t_fuel").begins_with("GIFT"),
		"re-tagging for %s switches it to a gift" % employers[0])
	check(markers.markers.size() == before + 1, "the map keeps one marker for it")
	check(field.server_tag("t_far", "sell", "") == "Too far away to tag" and field.tag_of("t_far").is_empty(), "a pallet out of reach can't be tagged")
	check(field.server_tag("t_fuel", "gift", "nobody") != "" and field.server_tag("t_fuel", "bogus", "") != "" and field.server_tag("nothing", "sell", "") != "",
		"a bad faction, mode or key is refused")
	check(field.server_tag("t_fuel", "none", "") == "" and field.tag_of("t_fuel").is_empty() and markers.markers.size() == before, "untagging clears the tag and the marker")
	field.server_tag("t_fuel", "sell", "")
	check(field.lots().size() == 1 and field.lots()[0].what == "fuel_drums" and field.lots()[0].tag == "sell" and int(field.lots()[0].value) > 0,
		"a tagged pallet is listed as a lot to haul home")


# --- The debrief and the FOB ----------------------------------------------------------------

func _lot(kind: String, uid: String, tag: String, faction := "") -> Dictionary:
	var lot := Pallets.pallet_lot(kind, uid)
	lot["tag"] = tag
	lot["faction"] = faction
	return lot


func _test_debrief_and_fob() -> void:
	print("Extraction: the debrief and the FOB")
	Contracts.new_full_campaign(71, 100000)
	Economy.take_unbanked()
	var cid := _make_offer("intel_grab", "harbour_yard")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	var employers := Pallets.gift_factions()
	var lots: Array = [
		_lot("fuel_drums", "d0", "sell"), _lot("ammo", "d1", "gift", employers[0]), _lot("parts", "d2", "sell"), _lot("mixed", "d3", "sell"),
		_lot("medical", "d4", "gift", employers[1]), _lot("supplies", "d5", "sell"), Pallets.vehicle_lot("technical_dshk", false, "v:test", "Technical")]
	lots[6]["tag"] = "sell"
	var d := Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 2}], "tagged": lots, "extracted": ["You"]})
	check((d.tagged as Array).size() == 7 and (d.tagged as Array).all(func(l: Dictionary) -> bool: return l.status == "pending"), "the debrief lists the 7 tagged lots, all undecided")
	var screen := DebriefScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.refresh()
	check(screen.text().contains("TAGGED PALLETS") and screen.text().contains("Fuel drums") and screen.text().contains("Technical"), "the debrief screen shows them")
	screen.queue_free()
	# Sell now (the quick price).
	var cash := Economy.cash()
	var price := Pallets.sell_price(d.tagged[0])
	check(Contracts.server_pallet("debrief", 0, "sell") == "" and Economy.cash() == cash + price and d.tagged[0].status == "sold" and price > 0,
		"sell now: cash +$%d (the quick price, half the value)" % price)
	check(Contracts.server_pallet("debrief", 0, "sell") != "", "a lot already sold can't be sold again")
	# Gift (reputation up).
	var rep := Economy.reputation(employers[0])
	var gain := Pallets.gift_rep(d.tagged[1])
	check(Contracts.server_pallet("debrief", 1, "gift") == "" and Economy.reputation(employers[0]) == rep + gain and d.tagged[1].status == "gifted",
		"gift (its tag's faction): %s reputation +%d" % [employers[0], gain])
	check(Contracts.server_pallet("debrief", 4, "gift", "nobody") != "" and d.tagged[4].status == "pending", "a gift needs a real faction")
	# Keep (the FOB's stocks).
	var parts := Economy.stock("parts")
	var want := int(d.tagged[2].units.parts)
	check(Contracts.server_pallet("debrief", 2, "keep") == "" and Economy.stock("parts") == parts + want and d.tagged[2].status == "kept",
		"keep: the FOB's spare parts +%d" % want)
	check(Contracts.server_pallet("debrief", 6, "keep") != "" and d.tagged[6].status == "pending", "a vehicle can't be kept as stocks")
	check(Contracts.server_pallet("debrief", 6, "sell") == "" and d.tagged[6].status == "sold", "a vehicle sells")
	# Store, then sell from storage at the better price.
	check(Contracts.server_pallet("debrief", 3, "store") == "" and Economy.pallet_store().size() == 1 and d.tagged[3].status == "stored", "store: it waits in FOB storage")
	var stored_price := Pallets.sell_price(Economy.pallet_store()[0], true)
	cash = Economy.cash()
	check(Contracts.server_pallet("store", 0, "sell") == "" and Economy.cash() == cash + stored_price and Economy.pallet_store().is_empty() and stored_price > Pallets.sell_price(d.tagged[3]),
		"sold from storage: +$%d, more than the quick price $%d" % [stored_price, Pallets.sell_price(d.tagged[3])])
	# What's undecided when the debrief closes.
	var rep1 := Economy.reputation(employers[1])
	Contracts.server_finish_debrief()
	check(d.tagged[4].status == "gifted" and Economy.reputation(employers[1]) == rep1 + Pallets.gift_rep(d.tagged[4]), "closing the debrief gifts a lot tagged for a faction")
	check(d.tagged[5].status == "stored" and Economy.pallet_store().size() == 1 and Economy.pallet_store()[0].uid == "d5", "and stores one tagged to sell")
	# Keep from storage; a gift from storage.
	var supplies := Economy.stock("supplies")
	check(Contracts.server_pallet("store", 0, "keep") == "" and Economy.stock("supplies") > supplies and Economy.pallet_store().is_empty(), "storage: keep adds to the stocks")
	Economy.server_store_lot(_lot("ammo", "s1", "sell"))
	var rep0 := Economy.reputation(employers[0])
	check(Contracts.server_pallet("store", 0, "gift", employers[0]) == "" and Economy.reputation(employers[0]) > rep0 and Economy.pallet_store().is_empty(), "storage: gift raises reputation")


# --- Stocks at work ----------------------------------------------------------------------------

func _test_stock_effects() -> void:
	print("Stocks offset costs and restock the stash")
	Contracts.new_full_campaign(72, 500000)
	Economy.take_unbanked()
	var price := Prices.support_price("transport")
	var cash := Economy.cash()
	check(Economy.server_pay_support("transport") and Economy.cash() == cash - price, "no fuel in stock: a transport call costs the full $%s" % DebriefCalc.money(price))
	Economy.server_add_stock("fuel", 100)
	var preview := Pallets.offset_preview(price, "support:transport")
	var expect_units := ceili(floor(price * 0.3) / 120.0)
	check(int(preview.offset) > 0 and int(preview.used.fuel) == expect_units and Economy.stock("fuel") == 100, "the preview names the fuel it would use (%d units, $%d off) without using it" % [int(preview.used.fuel), int(preview.offset)])
	cash = Economy.cash()
	check(Economy.server_pay_support("transport") and Economy.cash() == cash - (price - int(preview.offset)) and Economy.stock("fuel") == 100 - expect_units,
		"with fuel in stock the same call costs $%d less and uses %d units" % [int(preview.offset), expect_units])
	var small := Economy.stock("fuel")
	Economy.server_take_stock("fuel", small - 1)
	var tiny := Pallets.offset_preview(price, "support:transport")
	check(int(tiny.used.fuel) == 1 and int(tiny.offset) == 120, "with one unit left, it offsets only $120")
	check(Economy.server_take_stock("fuel", 5) == 1 and Economy.stock("fuel") == 0, "stock can't go below zero")
	check(Pallets.offset_preview(price, "support:transport").offset == 0, "no stock, no offset")
	Economy.server_add_stock("parts", 10)
	var repair := Pallets.offset_preview(1000, "repair")
	check(int(repair.offset) == 600 and int(repair.used.parts) == 2, "spare parts cover up to 60%% of a repair: $600 off for 2 units (%s)" % [repair])
	Economy.server_add_stock("ammo", 5)
	var field_costs := Pallets.offset_preview(10000, "field_costs")
	check(int(field_costs.offset) > 0 and field_costs.used.has("ammo") and not field_costs.used.has("fuel"), "stocks can offset field costs too (the economy hook): %s" % [field_costs])
	# Drawing into the stash.
	check(Pallets.server_draw("fuel", 1) != "" and Pallets.server_draw("ammo", 99) != "", "fuel can't be drawn as gear, nor more ammo than there is")
	check(Pallets.server_draw("ammo", 2) == "" and Economy.stock("ammo") == 3, "drawing 2 units of ammo uses them")
	var inbox := Economy.take_unbanked()
	check(inbox.any(func(e: Dictionary) -> bool: return e.id == "mag_556" and int(e.count) == 8), "and puts 8 magazines in the base inbox for the armory (%s)" % [inbox])
	var items_ok := true
	for kind: String in ["ammo", "supplies", "medical"]:
		for e: Dictionary in Pallets.data().draw[kind]:
			items_ok = items_ok and ItemDB.has_item(StringName(e.id))
	check(items_ok, "every drawn item exists")


func _test_save_reload() -> void:
	print("Stocks and storage are saved with the campaign")
	Economy.server_add_stock("medical", 7)
	Economy.server_store_lot(_lot("mixed", "sv", "sell"))
	var stocks: Dictionary = Economy.stocks().duplicate(true)
	Campaign.save_campaign()
	Economy.server_take_stock("medical", 7)
	Economy.server_unstore_lot(0)
	check(Campaign.load_campaign() and Economy.stock("medical") == int(stocks.medical) and Economy.stock("parts") == int(stocks.parts) and typeof(Economy.stocks().medical) == TYPE_INT,
		"the stocks come back (medical %d, parts %d)" % [Economy.stock("medical"), Economy.stock("parts")])
	check(Economy.pallet_store().size() == 1 and Economy.pallet_store()[0].uid == "sv" and int(Economy.pallet_store()[0].value) > 0, "and the lot in storage")


func _make_offer(type_id: String, zone_id: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + _made
	_made += 1
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type_id, "zone_id": zone_id})
	var def := MissionRegistry.type_def(type_id).duplicate(true)
	def["modules"] = ["compound"]
	c.objectives = ContractGen.mission_target(rng, def, "").objectives
	c.module = "compound"
	c.module_id = ""
	c.understated = false
	c.true_rating = c.rated
	c.enemy_count = c.enemy_est
	return Contracts.server_add_offer(c)
