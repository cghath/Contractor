extends Node
## Headless checks for the company's income beyond contracts (claude/income, docs/income.md):
## the high command squads' side jobs, captures and bounties, FOB businesses and the black market.
## Pure campaign logic on the autoloads (no level), so it runs in seconds.
##   <voxel godot exe> --headless --path . res://tests/income_test.tscn
## Exits with the number of failures.

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_income" + tag  # never touch a real save
	Campaign.campaign_id = "test_income_campaign" + tag
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("INCOME TEST FAILED (timed out)")
		get_tree().quit(99))
	await get_tree().process_frame
	_new_campaign()
	_test_side_jobs()
	_test_captures()
	_test_bounties()
	_test_intel_buyers()
	_test_businesses()
	_test_market()
	Campaign.reset_campaign()
	print("INCOME TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _new_campaign() -> void:
	Campaign.reset_campaign()
	Contracts.new_full_campaign(4242, 200000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	Heroes.seed_standing(Campaign.section(&"roster"), Economy.day(), rng)


func _roster() -> Dictionary:
	return Campaign.section(&"roster")


func _test_side_jobs() -> void:
	print("High command side jobs (SideJobs)")
	SideJobs.refresh_offers(Economy.day())
	var s := Income.state()
	check((s.offers as Array).size() == int(SideJobs.c("board_size", 3)), "the board carries %d side job offers" % int(SideJobs.c("board_size", 3)))
	var o: Dictionary = s.offers[0]
	check(int(o.pay) > 0 and float(o.danger) > 0.0 and String(o.from) != "", "an offer has pay, danger and who offers it (%s, %s, $%d)" % [o.kind, o.from, o.pay])
	var k := SideJobs.kind(String(o.kind))
	check(SideJobs.pay_for(k, String(o.client), 1.0, 0.9) > SideJobs.pay_for(k, String(o.client), 1.0, 0.2), "pay scales with the zone's danger")
	var q_good := SideJobs.odds(k, 0.5, 0.85)
	var q_poor := SideJobs.odds(k, 0.5, 0.35)
	check(float(q_good.trouble) < float(q_poor.trouble), "a better squad gets into trouble less often (%.2f vs %.2f)" % [q_good.trouble, q_poor.trouble])
	check(float(SideJobs.odds(k, 0.9, 0.6).trouble) > float(SideJobs.odds(k, 0.2, 0.6).trouble), "a more dangerous zone means more trouble")
	var q := SideJobs.quality(_roster(), "d02")
	check(float(q.quality) > 0.2 and float(q.quality) < 0.95 and int(q.ready) == 4, "Hawk 2's quality comes from skill, kit, morale and men ready (%.2f)" % q.quality)
	# The danger follows the living war: a front in a zone makes it worse.
	var zone := String(o.zone)
	var before := Income.zone_danger(zone)
	WorldSites.site(zone)["front"] = {"by": "ashen_banner", "since": Economy.day(), "progress": 0.4}
	check(Income.zone_danger(zone) > before, "a front in the zone raises its danger (%.2f -> %.2f)" % [before, Income.zone_danger(zone)])
	WorldSites.site(zone).erase("front")
	# Sending a squad: the advance now, the squad away, it can't deploy.
	var cash0 := Economy.cash()
	var why := Income.server_request("job_send", [String(o.id), "d02"], 1)
	check(why == "", "Hawk 2 goes out on the job (%s)" % why)
	check(Economy.cash() == cash0 + roundi(int(o.pay) * SideJobs.c("advance_share", 0.25)), "the advance is paid up front")
	check(SideJobs.is_away("d02") and not "d02" in Heroes.deploying(_roster(), 3), "a squad that's out can't deploy with the company")
	check(Income.server_request("job_send", [String((Income.state().offers as Array)[0].id), "d02"], 1) != "", "a squad already out can't take a second job")
	check(Income.server_request("job_send", [String((Income.state().offers as Array)[0].id), "d03"], 2) != "", "only the host sends squads")
	check(Economy.ledger_kind("Side job: Hawk 2, Escort") == "Side jobs", "side job pay has its own line in the books")
	# Coming back: after its days, the job resolves and reports.
	var job := SideJobs.job_of("d02")
	var reports := (Income.state().reports as Array).size()
	Economy.advance_days(int(job.days), "test")
	check(not SideJobs.is_away("d02"), "Hawk 2 is back after %d days" % int(job.days))
	check((Income.state().reports as Array).size() == reports + 1, "the squad reports on the company net and leaves a debrief card")
	check("d02" in Heroes.deploying(_roster(), 3) or int(Heroes.strength(_roster(), "d02").ready) == 0, "back from the job, it deploys again")
	# The roll's outcomes over many jobs: good squads in calm zones mostly come back clean; poor ones
	# in hot zones get hurt and fail; pay follows the result.
	var tally := {"clean": 0, "trouble": 0, "failed": 0, "kia": 0}
	for i in 60:
		var fake := {"id": "t%d" % i, "kind": "escort", "client": "meridian", "from": "Meridian", "zone": zone, "days": 2, "pay": 30000,
			"advance": 7500, "did": "d03", "callsign": "Viper 3", "start": 100 + i, "end": 102 + i, "trouble": 0.6}
		(Income.state().jobs as Array).append(fake)
		var out := SideJobs.server_resolve(fake)
		tally[String(out.result)] = int(tally[String(out.result)]) + 1
		tally.kia = int(tally.kia) + (out.kia as Array).size()
		for mid: Variant in Heroes.get_detachment(_roster(), "d03").members:  # keep the squad whole for the next roll
			var m := Roster.get_member(_roster(), String(mid))
			m["status"] = Roster.READY
			m["sit_out_days"] = 0
	check(int(tally.clean) > 10 and int(tally.trouble) + int(tally.failed) > 20, "at 60%% trouble, some jobs come back clean and many don't (%s)" % str(tally))
	check(int(tally.kia) > 0 and int(tally.failed) > 0, "a squad can lose men or fail the job")
	check((Fallen.memorial(_roster()) as Array).size() > 0, "a man lost on a side job goes on the memorial wall")
	# The page builds on every peer's copy without errors.
	var rows := VBoxContainer.new()
	add_child(rows)
	SideWorkPage.build(rows, self)
	check(rows.get_child_count() >= 3, "the side work page builds (%d rows)" % rows.get_child_count())
	check(SideWorkPage.board_summary() != "", "the board has a side work line: %s" % SideWorkPage.board_summary())
	rows.queue_free()


func _test_captures() -> void:
	print("Captured vehicles and heavy weapons (Bounties)")
	var lot := Pallets.vehicle_lot("technical_dshk", false, "v:t1", "Technical")
	Economy.server_store_lot(lot)
	var caps := Bounties.stored_captures()
	check(caps.size() == 1, "a stored vehicle lot is a capture to sell")
	var buyers := Bounties.capture_buyers(lot)
	var by := {}
	for b: Dictionary in buyers:
		by[String(b.faction)] = b
	check(by.has("salvage_union") and by.has("us_forces") and by.has("highland_front"), "the Salvage Union, US Forces and the Highland Front want a technical")
	check(String(by.highland_front.why) != "", "the Highland Front won't deal below its standing floor (%s)" % String(by.highland_front.why))
	check(not Bounties.capture_buyers(Pallets.vehicle_lot("aav7", false, "v:a1", "AAV")).any(func(b: Dictionary) -> bool: return String(b.faction) == "highland_front"),
		"the Highland Front only buys guns and technicals")
	check(int(by.salvage_union.price) > int(by.us_forces.price), "buyers pay differently (Mama Rook $%d, US $%d)" % [by.salvage_union.price, by.us_forces.price])
	var cash0 := Economy.cash()
	var rep0 := Economy.reputation("salvage_union")
	check(Income.server_request("capture_sell", [int(caps[0].index), "salvage_union"], 1) == "", "sold to Mama Rook")
	check(Economy.cash() == cash0 + int(by.salvage_union.price) and Economy.reputation("salvage_union") > rep0, "paid her price, and she thinks better of the company")
	check(Bounties.stored_captures().is_empty(), "the lot leaves storage")
	check(Income.server_request("capture_sell", [0, "salvage_union"], 1) != "", "nothing left to sell")
	# Delivered by a high command squad: more, on the side job's risks.
	Economy.server_store_lot(Pallets.vehicle_lot("matv", false, "v:m1", "M-ATV"))
	var idx := int(Bounties.stored_captures()[0].index)
	var o := Bounties.delivery_offer(idx, "us_forces")
	check(int(o.pay) > Bounties.capture_price(Economy.pallet_store()[idx], {"faction": "us_forces", "mult": 0.7}), "delivered pays more than selling from storage")
	cash0 = Economy.cash()
	check(Income.server_request("capture_deliver", [idx, "us_forces", "d02"], 1) == "", "Hawk 2 drives the M-ATV to US Forces")
	var job := SideJobs.job_of("d02")
	check(int(job.advance) == 0 and Economy.cash() == cash0 and Bounties.stored_captures().is_empty(), "nothing up front; the lot travels with the squad")
	job["trouble"] = 0.0
	Economy.advance_days(int(job.days), "test")
	var paid := 0
	for e: Dictionary in Economy.ledger():
		if String(e.what).begins_with("Capture sold: M-ATV"):
			paid = int(e.amount)
	check(paid == int(o.pay) and not SideJobs.is_away("d02"), "delivered: the buyer pays on arrival ($%d)" % paid)
	check(Economy.ledger_kind("Capture sold: M-ATV to US Forces") == "Captures and bounties", "captures have their own line in the books")


func _test_bounties() -> void:
	print("Bounties on the living war's leaders")
	var open := Bounties.open_bounties()
	check(open.size() >= 6, "bounties are posted on the war's leaders (%d)" % open.size())
	var br: Array = open.filter(func(b: Dictionary) -> bool: return String(b.faction) == "black_ridge")
	check(not br.is_empty() and int(br[0].dead) < int(br[0].alive), "worth more alive than dead")
	check(bool(MissionRegistry.faction(String(br[0].poster)).get("lawful", false)), "posted by a lawful employer at war with them (%s)" % br[0].poster_name)
	check("hvt_kill" in WorldSites.LEADER_TYPES, "an HVT kill names a leader too")
	var leader := String(br[0].leader)
	var cash0 := Economy.cash()
	var c := {"leader": leader, "target": "black_ridge", "type": "hvt_capture"}
	check(Bounties.server_contract_closed(c, {"outcome": "completed"}) == int(br[0].alive) and Economy.cash() == cash0 + int(br[0].alive), "taken alive: the full bounty")
	check(Bounties.server_contract_closed(c, {"outcome": "failed"}) == 0, "a failed job pays no bounty")
	var k := {"leader": leader, "target": "black_ridge", "type": "hvt_kill"}
	check(Bounties.server_contract_closed(k, {"outcome": "completed", "withheld": 9000}) == 0, "dead without proof: no bounty")
	check(Bounties.server_contract_closed(k, {"outcome": "completed", "withheld": 0}) == int(br[0].dead), "dead with his ID papers: the dead bounty")
	WorldSites.server_leader_down("black_ridge", leader)
	check(not Bounties.open_bounties().any(func(b: Dictionary) -> bool: return String(b.leader) == leader), "a leader taken comes off the bounty board")


func _test_intel_buyers() -> void:
	print("Intel to the right buyer")
	check(Bounties.intel_buyer_kind("us_forces", "black_ridge") == "lawful", "US Forces: lawful")
	check(Bounties.intel_buyer_kind("salvage_union", "black_ridge") == "fixer", "the Salvage Union: a fixer's")
	check(Bounties.intel_buyer_kind("ashen_banner", "black_ridge") == "rival", "the Ashen Banner: a rival of Black Ridge")
	check(Bounties.intel_buyer_kind("black_ridge", "black_ridge") == "subject", "Black Ridge buying its own secrets back")
	var p := {}
	for f: String in ["us_forces", "salvage_union", "ashen_banner", "black_ridge"]:
		p[f] = Bounties.intel_price(&"hvt_case", 1, f, "black_ridge")
	check(int(p.black_ridge) > int(p.ashen_banner) and int(p.ashen_banner) > int(p.salvage_union) and int(p.salvage_union) > int(p.us_forces),
		"prices by buyer: subject > rival > fixer > lawful (%s)" % str(p))
	var us0 := Economy.reputation("us_forces")
	Bounties.server_intel_sold("ashen_banner", "black_ridge")
	check(Economy.reputation("us_forces") < us0, "selling to a terror group costs standing with the lawful factions")
	check(Bounties.intel_offer_text(&"hvt_case", 1, "us_forces", "black_ridge").contains("+3 standing"), "the debrief's buyer list says the price and the standing")


func _ledger_sum(prefix: String, since_day: int) -> int:
	var n := 0
	for e: Dictionary in Economy.ledger():
		if int(e.day) >= since_day and String(e.what).begins_with(prefix):
			n += int(e.amount)
	return n


func _test_businesses() -> void:
	print("FOB businesses (FobBusiness)")
	FobBusiness.fob_override = 0
	check(FobBusiness.cant_open("militia").contains("FOB"), "no FOB, no businesses")
	FobBusiness.fob_override = 1
	var cash0 := Economy.cash()
	check(Income.server_request("biz_open", ["militia"], 2) != "", "only the host opens a business")
	check(Income.server_request("biz_open", ["militia"], 1) == "" and Economy.cash() == cash0 - int(FobBusiness.kind("militia").setup), "the militia camp opens for its setup")
	check(FobBusiness.cant_open("militia") != "", "one of each")
	var region := RebelSupport.region_of(FobBusiness.fob_zone())
	var support0 := RebelSupport.support(region)
	Economy.server_take_stock("supplies", Economy.stock("supplies"))
	var d0 := Economy.day() + 1
	Economy.advance_days(1, "test")
	check(_ledger_sum("Business: Militia", d0) == roundi(FobBusiness.day_pay("militia") * FobBusiness.c("short_pay", 0.5)), "short of supplies, it pays half")
	check(_ledger_sum("Business upkeep: Militia", d0) == -int(FobBusiness.kind("militia").upkeep), "and its upkeep comes off every day")
	check(RebelSupport.support(region) > support0, "the camp raises rebel support in the region (%.1f -> %.1f)" % [support0, RebelSupport.support(region)])
	Economy.server_add_stock("supplies", 5)
	d0 = Economy.day() + 1
	Economy.advance_days(1, "test")
	check(_ledger_sum("Business: Militia", d0) == FobBusiness.day_pay("militia") and Economy.stock("supplies") == 4, "with supplies it pays in full and uses one")
	check(FobBusiness.units("tolls") >= 1 and FobBusiness.day_pay("tolls") == int(FobBusiness.kind("tolls").pay) + int(FobBusiness.kind("tolls").per_unit) * FobBusiness.units("tolls"),
		"tolls pay by the roads held (%d)" % FobBusiness.units("tolls"))
	check(FobBusiness.units("rentals") == MotorPool.list().filter(func(v: Dictionary) -> bool: return String(v.get("out", "")) == "").size(), "rentals pay by the vehicles at home")
	check(Economy.ledger_kind("Business: Checkpoint tolls") == "FOB businesses" and Economy.ledger_kind("Business upkeep: Tolls") == "FOB businesses", "businesses have their own line in the books")
	# The war threatens them: a protection job on the board; done, the threat lifts.
	var t := FobBusiness.server_threaten("militia", Economy.day())
	var offer := {}
	for c: Dictionary in Campaign.section(Contracts.SECTION).board:
		if String(c.get("business", "")) == "militia":
			offer = c
	check(not t.is_empty() and not offer.is_empty() and String(offer.get("type", "")) == "defend_hold", "raiders threaten it: a protection job (Hold the line) goes on the board")
	var locals0 := Economy.locals()
	FobBusiness.on_contract_closed({"business": "militia", "cid": "nope"}, "failed")
	check(not (FobBusiness.running().militia.threat as Dictionary).is_empty(), "another job's result doesn't touch the threat")
	FobBusiness.on_contract_closed(offer, "completed")
	check((FobBusiness.running().militia.threat as Dictionary).is_empty() and Economy.locals() > locals0, "protected: the threat lifts and the locals noticed")
	# Left alone, the raid comes.
	t = FobBusiness.server_threaten("militia", Economy.day())
	cash0 = Economy.cash()
	Economy.advance_days(int(FobBusiness.c("threat_days", 3)) + 1, "test")
	var b: Dictionary = FobBusiness.running().militia
	check(int(b.closed_until) >= Economy.day() - 1 and _ledger_sum("Business upkeep: Militia training camp raided", 0) < 0, "unprotected, it's raided: closed and repairs to pay")
	# The FOB lost takes them all.
	FobBusiness.fob_override = 0
	Economy.advance_days(1, "test")
	check(FobBusiness.running().is_empty(), "the FOB lost, the businesses go with it")
	FobBusiness.fob_override = 1
	var rows := VBoxContainer.new()
	add_child(rows)
	SideWorkPage.build(rows, self)
	check(rows.find_children("*", "Button", true, false).any(func(x: Button) -> bool: return x.text.begins_with("Open")), "the side work page offers the businesses with their setup and daily take")
	rows.queue_free()
	FobBusiness.fob_override = -1


func _test_market() -> void:
	print("Black market trading (BlackMarket)")
	var markets := BlackMarket.markets()
	check(markets.any(func(m: Dictionary) -> bool: return String(m.id).begins_with("r:")), "the home region's market is open (%s)" % str(markets.map(func(m: Dictionary) -> String: return String(m.name))))
	var home := String(markets[0].id)
	check(BlackMarket.price("weapons", home, "buy") > BlackMarket.price("weapons", home, "sell"), "a market sells dearer than it buys")
	# The war moves prices: a front in every zone of a region makes weapons scarce there.
	var region := home.trim_prefix("r:")
	var f0 := BlackMarket.war_factor("weapons", region)
	var zones: Array = WorldSites.war_zones().filter(func(z: String) -> bool: return RebelSupport.region_of(z) == region)
	for z: String in zones:
		WorldSites.site(z)["front"] = {"by": "ashen_banner", "since": Economy.day(), "progress": 0.3}
	check(BlackMarket.war_factor("weapons", region) > f0, "fronts make weapons scarce (x%.2f -> x%.2f)" % [f0, BlackMarket.war_factor("weapons", region)])
	for z: String in zones:
		WorldSites.site(z).erase("front")
	# Buying and selling.
	var cash0 := Economy.cash()
	var each := BlackMarket.price("fuel", home, "buy")
	check(Income.server_request("trade_buy", ["fuel", home, 10], 1) == "" and Economy.cash() == cash0 - each * 10, "bought 10 fuel at $%d" % each)
	check(BlackMarket.cargo_units() == 10, "it rides in the trucks")
	check(Income.server_request("trade_buy", ["fuel", home, BlackMarket.capacity()], 1) != "", "the trucks only hold so much (%d)" % BlackMarket.capacity())
	var sell_before := BlackMarket.price("fuel", home, "sell")
	check(Income.server_request("trade_sell", ["fuel", home, 10], 1) == "" and BlackMarket.cargo_units() == 0, "sold it again")
	check(BlackMarket.price("fuel", home, "sell") < sell_before, "selling drives that market's price down ($%d -> $%d)" % [sell_before, BlackMarket.price("fuel", home, "sell")])
	Economy.advance_days(3, "test")
	check(float((BlackMarket._s().pressure as Dictionary).get(home, {}).get("fuel", 0.0)) < 0.12 * 0.5, "and it recovers day by day")
	check(Income.server_request("trade_sell", ["fuel", home, 1], 1) != "", "nothing to sell")
	check(Income.server_request("trade_buy", ["fuel", "r:nowhere", 1], 1) != "", "only open markets")
	# The last job's region opens its market.
	var other := ""
	for r: Dictionary in MissionRegistry.data().get("regions", []):
		if "r:" + String(r.region) != home:
			other = String(r.region)
	var zone_there := ""
	for z: String in WorldSites.war_zones():
		if RebelSupport.region_of(z) == other:
			zone_there = z
	BlackMarket.on_contract_closed({"zone_id": zone_there}, "completed")
	check(BlackMarket.markets().any(func(m: Dictionary) -> bool: return String(m.id) == "r:" + other), "a job in %s opens its market" % other)
	# Contraband is risky: over many days some gets seized, with a fine and US standing.
	var us0 := Economy.reputation("us_forces")
	var cg: Dictionary = BlackMarket._s().cargo
	cg["contraband"] = {"units": 20, "paid": 30000}
	var seized := false
	for i in 40:
		Economy.advance_days(1, "test")
		if not BlackMarket.cargo().has("contraband"):
			seized = true
			break
	check(seized and Economy.reputation("us_forces") < us0, "contraband held long enough is found: seized, fined, US standing down")
	check(Economy.ledger_kind("Trade sold: 10 fuel") == "Black market", "trading has its own line in the books")
	var rows := VBoxContainer.new()
	add_child(rows)
	SideWorkPage.build(rows, self)
	check(rows.find_children("*", "Button", true, false).any(func(x: Button) -> bool: return x.text.begins_with("Buy 5")), "the side work page has the market's prices to buy at")
	rows.queue_free()
