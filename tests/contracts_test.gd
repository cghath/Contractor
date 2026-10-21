extends Node
## Headless checks for contracts, the economy and the debrief (wave 4, W10): generation from a
## seed, the difficulty rating and how often the briefing understates it, MW5-style
## negotiation and the advance kept on failure, renegotiating and aborting, lapses, weekly
## wages and the safety floor, the shop, the debrief's sums (pay, bonuses, fines, the
## 8-casualty void, salvage picks, intel), saving and reloading the campaign, objectives in a
## live level (clear an area, carry out an item, deliver an HVT, destroy a cache by voxels or
## a placed charge), the HUD's objective helper (the "what to do now" line for each kind and
## state, the markers on the current target, clamped to the screen's edge when behind, and
## their switch) and the ammo readout's estimates, and over ENet a client that sees the board,
## the objectives, the helper's line and marker, and the debrief.
##   <voxel godot exe> --headless --path . res://tests/contracts_test.tscn
## It hosts a session, and at the end starts a second copy of itself that joins (`-- --join`);
## the client reports its checks back to the host. Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var _made := 0
var _client_ready := false
var _client_done := false
var _client_phase := 0
var _go: Dictionary = {}


func _ready() -> void:
	var joining := "--join" in OS.get_cmdline_user_args()
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_contracts" + tag  # never touch a real save
	Campaign.campaign_id = "test_contracts_campaign" + tag  # not the zone save's name: both live in user://saves
	CompoundLevel.spawn_ai = false
	PeopleLayer.contract_people = false  # the objectives are driven by hand here
	Contracts.auto_show_debrief = joining
	if joining:
		Contracts.autosave = false  # the host's save file is the same one
	else:
		GameState.delete_save()
		Campaign.reset_campaign()
	add_child(load("res://scenes/main.tscn").instantiate())  # main joins on --join
	await get_tree().process_frame
	if joining:
		await _run_client()
		return
	_test_generation()
	_test_variety_board()
	_register_clear_compound()
	_test_rating_and_understatement()
	_test_negotiation()
	_test_malformed_requests()
	_test_reveal_renegotiate_abort()
	_test_wages_and_floor()
	_test_economy_balance()
	_test_overhaul_numbers()
	_test_lapse()
	_test_reputation_core()
	_test_world_sites()
	_test_faction_followups()
	_test_debrief_totals()
	_test_civilians_void()
	_test_save_reload()
	_test_shop()
	_test_intel_and_salvage()
	_test_set_down_at_the_point()
	_test_death_benefit()
	await _test_board_ui()
	await _test_debrief_screen()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	await _frames(20)
	await _test_nemesis_kill_attribution()
	await _test_allied_troops()
	await _test_live_objectives()
	await _test_objective_helper()
	_test_ammo_readout()
	await _test_driven_out()
	await _test_over_network()
	Campaign.reset_campaign()
	GameState.delete_save()
	print("CONTRACTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Generation ------------------------------------------------------------------------------

func _test_generation() -> void:
	print("Generation from a seed")
	var rep := {"meridian": 10, "black_ridge": -60, "salvage_union": 0}
	var a := ContractGen.generate_board(1234, 1, rep, 6)
	var b := ContractGen.generate_board(1234, 1, rep, 6)
	var c := ContractGen.generate_board(999, 1, rep, 6)
	check(a.size() == 6 and a == b, "the same seed gives the same board (%d offers)" % a.size())
	check(a != c, "another seed gives another board")
	var valid := true
	var unsound := ""  # the first offer that isn't, and what's wrong with it
	for o: Dictionary in a:
		var zone := MissionRegistry.zone(o.zone_id)
		var def := MissionRegistry.type_def(o.type)
		var problems := PackedStringArray()
		if not (int(o.rated) >= 1 and int(o.rated) <= 5 and int(o.true_rating) >= int(o.rated)):
			problems.append("rating %s/%s" % [o.rated, o.true_rating])
		if int(o.base_pay) <= 0 or (o.objectives as Array).is_empty():
			problems.append("pay or objectives")
		if not (ZoneModules.base(o.module) in MissionRegistry.type_modules(def) and ZoneModules.base(o.module) in zone.modules and (String(o.module_id) != "" or def.has("scenario"))):
			problems.append("module %s (%s)" % [o.module, o.module_id])
		if not o.employer in MissionRegistry.employers() or not o.target in MissionRegistry.enemies():
			problems.append("employer %s, target %s" % [o.employer, o.target])
		if o.zone_kind != zone.kind:
			problems.append("zone kind %s vs %s" % [o.zone_kind, zone.kind])
		if not problems.is_empty() and unsound == "":
			unsound = " (%s %s in %s: %s)" % [o.type, o.get("cid", "?"), o.zone_id, ", ".join(problems)]
		valid = valid and problems.is_empty()
	check(valid, "every offer is sound: rating 1-5, the briefing never overstates, pay, objectives, a target module in the zone's layout" + unsound)
	check(a[0].source == "safe" and int(a[0].rated) == 1 and not a[0].understated and a[0].zone_kind == "contract",
		"the first is a cheap low-risk job (safety floor): rated %d, $%d" % [a[0].rated, a[0].base_pay])
	check(not a.any(func(o: Dictionary) -> bool: return o.source == "fixer"), "no fixer work at neutral standing")
	check(a[0].clawback == ContractGen.FULL_CLAWBACK and a.all(func(o: Dictionary) -> bool: return String(o.get("clawback", "")) in ContractGen.clawback_terms()),
		"every offer states its clawback term; the safe job's is full (strict)")
	var friendly := rep.duplicate()
	friendly["meridian"] = 25
	var with_fixer := ContractGen.generate_board(1234, 1, friendly, 6)
	var fixer_jobs := with_fixer.filter(func(o: Dictionary) -> bool: return o.source == "fixer")
	check(fixer_jobs.size() == 1 and fixer_jobs[0].fixer == "Halloran" and fixer_jobs[0].employer == "meridian"
		and fixer_jobs[0].type in ["hvt_capture", "intel_grab"], "at reputation 25 Meridian's fixer offers a special job (%s)" % [fixer_jobs.map(func(o: Dictionary) -> String: return o.title)])
	check(not fixer_jobs.is_empty() and fixer_jobs[0].clawback == ContractGen.NO_CLAWBACK, "a fixer's job is shady: the advance is kept on a void")
	var lenient: Dictionary = ContractGen.clawback_terms().get(ContractGen.NO_CLAWBACK, {})
	check(float(lenient.get("pay_mult", 1.0)) < 1.0, "and a lenient client pays less (x%.2f)" % float(lenient.get("pay_mult", 1.0)))
	# Many offers: every placeholder type turns up, hot zones are paid by the zone's faction.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var seen := {}
	var hot_ok := true
	var hot := 0
	for i in 300:
		var o := ContractGen.generate(rng, {"day": 1, "source": "board"})
		seen[o.type] = true
		if o.zone_kind == "hot":
			hot += 1
			hot_ok = hot_ok and o.employer == MissionRegistry.zone(o.zone_id).faction
	check(seen.keys().size() == 14 and seen.has("forward_observer") and seen.has("supply_line") and seen.has("manhunt") and seen.has("convoy_chase") and seen.has("psd_escort") and seen.has("raid") and seen.has("hvt_capture") and seen.has("hostage_rescue") and seen.has("intel_grab")
		and seen.has("convoy_ambush") and seen.has("defend_hold") and seen.has("crew_rescue") and seen.has("sabotage") and seen.has("recon"),
		"Captain's first four mission types, the five of mission variety, the client escort, the supply line, the manhunt, the convoy chase and the forward observer come up (%s)" % [seen.keys()])
	check(hot > 30 and hot < 130 and hot_ok, "hot-zone contracts come up (%d of 300), each from the zone's own faction" % hot)
	# A mission type added at runtime (Noah's types drop in the same way).
	MissionRegistry.register_type({"type": "test_rescue", "name": "Hostage rescue", "module": "compound", "base_pay": 60000, "days": 1,
		"enemy_count": [4, 6], "enemy_quality": [0.4, 0.5], "threat_pool": [],
		"objectives": [{"kind": "deliver_hvt", "site": "hvt", "text": "Bring the hostage out"}]})
	var r := ContractGen.generate(rng, {"day": 1, "source": "board", "type": "test_rescue"})
	var objs := Objectives.from_contract(r)
	check(r.type == "test_rescue" and objs.size() == 1 and objs[0].kind == Objectives.DELIVER_HVT and objs[0].params.hvt == "hvt_compound"
		and "test_rescue" in MissionRegistry.types(), "a mission type registered at runtime generates contracts and objectives")
	var moved := Objectives.placed_site({"rect": [-20, -20, 40, 40], "box": [[0, 0, 0], [1, 1, 1]], "pos": [1, 2, 3]}, Vector3(100, 0, 50))
	check(moved.rect == [80.0, 30.0, 40, 40] and moved.pos == [101.0, 2.0, 53.0] and moved.box[1] == [101.0, 1.0, 51.0],
		"a module placed away from the origin moves its sites with it")
	MissionRegistry.unregister_type("test_rescue")
	check(not "test_rescue" in MissionRegistry.types(), "and unregisters")


## Task 8 (mission variety, 2026-10-20): convoy ambush, hold the line, downed crew rescue,
## sabotage and recon come up on the board (offers made as Contracts.server_refresh_board makes
## them) often enough to be seen, in zones holding a module each plays in, in contract and hot
## zones alike; sabotage's target is a fuel store, a vehicle park or a radio mast (a weapons cache
## is the raid's), and a park plays as destroy_vehicles with its vehicles listed. missions_test
## "Mission variety: from the board, played through" plays each one to the end.
func _test_variety_board() -> void:
	print("Mission variety on the board")
	var five: Array[String] = ["convoy_ambush", "defend_hold", "crew_rescue", "sabotage", "recon"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var n := 1300  # (a 14th board type, the forward observer: more offers for sabotage's rarer radio mast)
	var count := {}
	var zone_kinds := {}
	var targets := {}
	var misfit := ""
	for i in n:
		var o := ContractGen.generate(rng, {"day": 1, "source": "board"})
		if not o.type in five:
			continue
		count[o.type] = int(count.get(o.type, 0)) + 1
		if not zone_kinds.has(o.type):
			zone_kinds[o.type] = {}
		zone_kinds[o.type][o.zone_kind] = true
		var zone := MissionRegistry.zone(String(o.zone_id))
		var def := MissionRegistry.type_def(String(o.type))
		var problem := ""
		if not (ZoneModules.base(String(o.module)) in MissionRegistry.type_modules(def) and ZoneModules.base(String(o.module)) in zone.modules):
			problem = "module %s" % o.module
		var required: Array = (o.objectives as Array).filter(func(x: Dictionary) -> bool: return not bool(x.get("optional", false)))
		if required.is_empty() or (o.objectives as Array).any(func(x: Dictionary) -> bool: return String(x.text).contains("{") or not String(x.kind) in Objectives.KINDS):
			problem = "objectives"
		if o.type == "sabotage" and problem == "":
			var main: Dictionary = required[0]
			var site := String(main.site)
			targets[site] = int(targets.get(site, 0)) + 1
			var park := site == "park"
			var site_def := MissionRegistry.site(String(o.module), site)
			if not site in ["fuel", "park", "mast"] or (String(main.kind) == Objectives.DESTROY_VEHICLES) != park \
					or (park and (site_def.get("vehicles", []) as Array).is_empty()) or (not park and int(site_def.get("voxels", 0)) <= 0):
				problem = "sabotage target %s (%s, %s)" % [site, main.kind, o.module]
		if problem != "" and misfit == "":
			misfit = " (%s in %s: %s)" % [o.type, o.zone_id, problem]
	check(five.all(func(t: String) -> bool: return int(count.get(t, 0)) >= n / 13 / 2),
		"each of the five comes up on the board, about one offer in 13 (%s of %d offers)" % [count, n])
	check(misfit == "", "each in a zone holding a module it plays in, its objectives filled in" + misfit)
	check(five.all(func(t: String) -> bool: return (zone_kinds.get(t, {}) as Dictionary).has("contract") and (zone_kinds.get(t, {}) as Dictionary).has("hot")),
		"in contract zones and hot zones alike (%s)" % [zone_kinds])
	check(targets.has("fuel") and targets.has("park") and targets.has("mast") and not targets.has("cache"),
		"sabotage hits a fuel store, a vehicle park or a radio mast, never the raid's weapons cache (%s)" % [targets])
	var outpost := ContractGen.mission_target(rng, MissionRegistry.type_def("sabotage"), "")
	check(String(outpost.module) == "outpost" and (outpost.objectives as Array).size() >= 1 and String(outpost.objectives[0].kind) == Objectives.DESTROY_VEHICLES
		and String(outpost.title_extra) == " (vehicle park)", "an outpost's sabotage target is its vehicle park (%s)" % outpost.title_extra)


func _test_rating_and_understatement() -> void:
	print("Difficulty rating and understated briefings")
	check(ContractGen.rating(4, 0.3, []) == 1 and ContractGen.rating(10, 0.5, ["mg_nest"]) == 3 and ContractGen.rating(16, 0.7, ["armor"]) == 5
		and ContractGen.rating(40, 1.0, ["armor", "aa"]) == 5, "rating from enemy size, quality and threats (1, 3, 5, capped at 5)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var n := 0
	var understated := 0
	var expected := 0.0
	var consistent := true
	var low := [0, 0]   # intel under 0.5: [understated, count]
	var high := [0, 0]  # intel over 0.75
	var fog := [[0, 0], [0, 0]]  # honest briefings, [poor intel, good intel]: [count off, count]
	for i in 4000:
		var o := ContractGen.generate(rng, {"day": 1, "source": "board"})
		if int(o.true_rating) <= 1:
			consistent = consistent and not o.understated
			continue
		n += 1
		expected += ContractGen.understate_chance(float(o.intel_accuracy))
		var bucket: Array = low if float(o.intel_accuracy) < 0.5 else high if float(o.intel_accuracy) > 0.75 else []
		if not bucket.is_empty():
			bucket[1] += 1
		if o.understated:
			understated += 1
			if not bucket.is_empty():
				bucket[0] += 1
			consistent = consistent and int(o.rated) < int(o.true_rating) and int(o.enemy_est) < int(o.enemy_count) \
				and (o.threats_known as Array).size() <= (o.threats as Array).size() and float(o.quality_est) < float(o.quality)
		else:
			# Honest, but intel is never spot on (Captain): off by no more than its accuracy allows.
			var miss := 1.0 - float(o.intel_accuracy)
			var off := absi(int(o.enemy_est) - int(o.enemy_count))
			consistent = consistent and int(o.rated) == int(o.true_rating) \
				and off <= ceili(int(o.enemy_count) * ContractGen.INTEL_COUNT_ERROR * miss) + 1 \
				and absf(float(o.quality_est) - float(o.quality)) <= ContractGen.INTEL_QUALITY_ERROR * miss + 0.011
			if not bucket.is_empty():
				var f: Array = fog[0] if is_same(bucket, low) else fog[1]
				f[0] += 1 if off > 0 else 0
				f[1] += 1
	check(fog[0][1] > 0 and float(fog[0][0]) / fog[0][1] > 0.5 and float(fog[1][0]) / maxf(fog[1][1], 1) < float(fog[0][0]) / fog[0][1],
		"intel is never spot on: poor intel gets the count wrong more often than good intel (%d%% vs %d%% of honest briefings)" % [
			roundi(100.0 * fog[0][0] / maxf(fog[0][1], 1)), roundi(100.0 * fog[1][0] / maxf(fog[1][1], 1))])
	var rate := float(understated) / n
	expected /= n
	check(absf(rate - expected) < 0.03 and expected > 0.1 and expected < 0.3,
		"the briefing understates %.1f%% of contracts that can be understated (expected %.1f%% from intel accuracy)" % [rate * 100.0, expected * 100.0])
	var low_rate := float(low[0]) / maxi(low[1], 1)
	var high_rate := float(high[0]) / maxi(high[1], 1)
	check(low_rate > high_rate + 0.08, "poor intel lies more often than good intel (%.0f%% vs %.0f%%)" % [low_rate * 100.0, high_rate * 100.0])
	check(consistent, "an understated briefing rates lower and reports fewer fighters, lower quality, no more threats; an honest one is off by no more than its intel allows")
	var some := ContractGen.generate(rng, {"day": 1, "source": "board"})
	var view := ContractGen.public_view(some)
	check(not view.has("true_rating") and not view.has("enemy_count") and not view.has("understated") and view.has("rated") and view.has("enemy_est"),
		"clients only see the briefing, not the truth")


# --- Negotiation -----------------------------------------------------------------------------

## Audit A1-05: a request with missing or wrong-typed arguments, local or from a client, and
## terms that aren't plain numbers, are refused (the asker is told) before anything is read.
func _test_malformed_requests() -> void:
	print("Malformed requests")
	Contracts.new_full_campaign(55, 150000)
	var notes: Array = []
	var on_notice := func(text: String) -> void: notes.append(text)
	Contracts.notice.connect(on_notice)
	var cash := Economy.cash()
	var cid := String(Contracts.board()[0].cid)
	var bad: Array = [["accept", []], ["accept", [cid]], ["accept", [cid, []]], ["accept", [7, {}]], ["accept", "x"], ["renegotiate", []],
		["abort", [7]], ["pick", []], ["unpick", ["0"]], ["turn_in", [null]], ["sell", [0]], ["sell", ["0", "meridian"]], ["finish", [1]],
		[7, []], ["nonsense", []]]
	for req: Array in bad:
		Contracts._handle(req[0], req[1], 1)
	check(notes.size() == bad.size() and notes.all(func(n: String) -> bool: return n == "Bad request") and Economy.cash() == cash
		and Contracts.contract(cid).state == "offered" and Contracts.held().is_empty(),
		"%d malformed requests are each refused as a bad request, nothing changes (%d answers)" % [bad.size(), notes.size()])
	var bad_terms: Array = [{"pay_points": "lots"}, {"advance_share": NAN}, {"pay_points": 1.5}, {"bribe": 1}, {"support_points": []}, {7: 1}]
	check(bad_terms.all(func(t: Dictionary) -> bool: return Contracts.server_accept(cid, t) == "Those terms make no sense")
		and Economy.cash() == cash and Contracts.contract(cid).state == "offered", "terms that aren't the plain numbers negotiated are refused")
	Contracts.notice.disconnect(on_notice)


func _test_negotiation() -> void:
	print("Negotiation, the advance, and failure")
	Contracts.new_full_campaign(42, 100000)
	check(Economy.cash() == 100000 and Economy.day() == 1 and Economy.reputation("meridian") == 10 and Economy.reputation("black_ridge") == -60,
		"a fresh campaign: $100,000, day 1, factions at their start reputation")
	check(Contracts.board().size() >= MissionRegistry.setting_i("board_size", 6), "the board is up (%d offers)" % Contracts.board().size())
	check(ContractGen.max_points(10) == 4 and ContractGen.max_points(35) == 5 and ContractGen.max_points(80) == 6 and ContractGen.max_points(-50) == 4,
		"negotiation points: 4 at neutral, one more per tier above")
	var cid := _make_offer("clear_compound", "compound_01")
	var c := Contracts.contract(cid)
	var base := int(c.base_pay)
	var d0 := ContractGen.deal(c, ContractGen.default_terms())
	check(d0.pay_total == base and d0.advance == roundi(base * 0.3) and d0.completion == base - d0.advance and is_equal_approx(d0.salvage_share, 0.1)
		and d0.support_budget == 0, "standard terms: the base pay, 30% advance, 10% salvage, no support budget")
	# Captain, 2026-10-17: one point in support pays for a helicopter infil and its exfil.
	var one := ContractGen.deal(c, {"pay_points": 0, "salvage_points": 0, "support_points": 1, "advance_share": 0.3})
	check(int(one.support_budget) >= Prices.support_price("transport") + Prices.support_price("extraction"),
		"one support point covers a helicopter infil and exfil ($%d for $%d + $%d)" % [int(one.support_budget), Prices.support_price("transport"), Prices.support_price("extraction")])
	var pay := ContractGen.deal(c, {"pay_points": 4, "salvage_points": 0, "support_points": 0, "advance_share": 0.3})
	var salvage := ContractGen.deal(c, {"pay_points": 0, "salvage_points": 4, "support_points": 0, "advance_share": 0.3})
	var mixed := ContractGen.deal(c, {"pay_points": 2, "salvage_points": 2, "support_points": 0, "advance_share": 0.3})
	check(pay.pay_total == roundi(base * 1.4) and is_equal_approx(pay.salvage_share, 0.1) and salvage.pay_total == base and is_equal_approx(salvage.salvage_share, 0.5)
		and mixed.pay_total > salvage.pay_total and mixed.pay_total < pay.pay_total and mixed.salvage_share > pay.salvage_share and mixed.salvage_share < salvage.salvage_share,
		"pay trades against salvage: all pay $%d at 10%%, all salvage $%d at 50%%, half and half between" % [pay.pay_total, salvage.pay_total])
	check(ContractGen.terms_problem({"pay_points": 3, "salvage_points": 2}, 10) != "" and ContractGen.terms_problem({"pay_points": 2, "advance_share": 0.5}, 10) == ""
		and ContractGen.terms_problem({"pay_points": 3, "advance_share": 0.5}, 10) != "" and ContractGen.terms_problem({"advance_share": 0.6}, 10) != ""
		and ContractGen.terms_problem({"pay_points": 5}, 35) == "", "points cap the terms; a bigger advance costs points; more standing, more points")
	var before := Economy.cash()
	check(Contracts.server_accept(cid, {"pay_points": 3, "salvage_points": 2}) != "" and Economy.cash() == before and Contracts.contract(cid).state == "offered",
		"terms beyond the points are refused, nothing paid")
	var terms := {"pay_points": 2, "salvage_points": 1, "support_points": 1, "advance_share": 0.3}
	var deal := ContractGen.deal(c, terms)
	check(Contracts.server_accept(cid, terms) == "", "accepted on negotiated terms")
	var held := Contracts.contract(cid)
	var per_point := MissionRegistry.setting_i("support_per_point", 23000)
	check(held.state == "accepted" and Economy.cash() == before + deal.advance and int(held.support_left) == per_point
		and not Contracts.board().any(func(o: Dictionary) -> bool: return o.cid == cid) and Contracts.held().any(func(o: Dictionary) -> bool: return o.cid == cid),
		"signing pays the 30%% advance ($%d) and the contract moves to held, with a $%d support budget" % [deal.advance, per_point])
	check(Contracts.server_start_deployment([cid]) == "" and Contracts.is_deployed() and Contracts.objectives.list.size() == 2
		and Contracts.objectives.active().size() == 2, "deployed: its two objectives are live")
	var rep := Economy.reputation(String(held.employer))
	var cash := Economy.cash()
	var debrief := Contracts.server_end_deployment({})
	check(debrief.contracts[0].outcome == "failed" and int(debrief.totals.completion) == 0 and int(debrief.totals.advance) == deal.advance
		and Economy.cash() == cash - int(debrief.expenses_total) and not Contracts.is_deployed(),
		"failed: no completion pay, but the advance is kept ($%d; its days' wages and upkeep paid, $%d)" % [Economy.cash(), int(debrief.expenses_total)])
	check(Economy.reputation(String(held.employer)) == rep - 6 and Contracts.history().back().outcome == "failed" and Contracts.held().is_empty(),
		"and the client thinks less of the company (%+d)" % (Economy.reputation(String(held.employer)) - rep))
	Contracts.server_finish_debrief()


func _test_reveal_renegotiate_abort() -> void:
	print("Understated threats: renegotiate or abort")
	Contracts.new_full_campaign(43, 100000)
	var cid := _make_offer("raid", "compound_01", {"understated": true, "rated": 2, "true_rating": 4, "enemy_est": 5, "enemy_count": 12})
	Contracts.server_accept(cid, ContractGen.default_terms())
	check(Contracts.server_renegotiate(cid) != "", "no renegotiating before the lie shows")
	check(not Contracts._public().held[0].has("true_rating"), "the truth isn't in what clients get yet")
	Contracts.server_reveal_threat(cid)
	var view: Dictionary = Contracts._public().held[0]
	check(view.revealed and int(view.true_rating) == 4 and int(view.enemy_count) == 12, "revealed: clients now see the real threat (a 4, 12 fighters)")
	var base := int(Contracts.contract(cid).base_pay)
	check(Contracts.server_renegotiate(cid) == "" and int(Contracts.contract(cid).raise) == roundi(base * 0.25 * 2) and int(Contracts.contract(cid).rated) == 4,
		"renegotiated: +25%% of the base pay per step understated ($%d)" % int(Contracts.contract(cid).get("raise", 0)))
	check(Contracts.server_renegotiate(cid) != "", "only once")
	# Abort after a reveal costs no standing; abort without one does. Advances are kept.
	var employer := String(Contracts.contract(cid).employer)
	var rep := Economy.reputation(employer)
	var cash := Economy.cash()
	check(Contracts.server_abort(cid) == "" and Economy.reputation(employer) == rep and Economy.cash() == cash and Contracts.history().back().outcome == "aborted",
		"aborting a contract that lied: advance kept, no reputation lost")
	var other := _make_offer("intel_grab", "compound_01")
	Contracts.server_accept(other, ContractGen.default_terms())
	employer = String(Contracts.contract(other).employer)
	rep = Economy.reputation(employer)
	cash = Economy.cash()
	Contracts.server_reveal_threat(other)  # the world calls it on first contact, honest briefing or not
	check(not Contracts.contract(other).get("revealed", false) and not Contracts._public().held[0].get("revealed", false),
		"revealing an honest briefing changes nothing (no renegotiate, no free abort)")
	Contracts.server_abort(other)
	check(Economy.reputation(employer) == rep - 4 and Economy.cash() == cash, "aborting one that didn't: -4 reputation, advance still kept")


# --- Clock, wages, the safety floor, lapses --------------------------------------------------------

func _test_wages_and_floor() -> void:
	print("Weekly wages and the safety floor")
	Contracts.new_full_campaign(7, 100000)
	var up := Prices.weekly_upkeep()
	Economy.wages_provider = func() -> int: return 20000
	check(Economy.days_to_bill() == 7 and Economy.weekly_bill().total == 20000 + up, "the week's bill: $20,000 wages from the roster + $%d upkeep" % up)
	# Economy overhaul 2026-10-20: paid every day, a seventh of the week's (each debrief carries its own days).
	Economy.advance_days(1, "test")
	var first := floori(20000 / 7.0) + floori(up / 7.0)
	check(Economy.cash() == 100000 - first and int(Economy.ledger().back().amount) == -first, "day 2: a day's wages and upkeep paid ($%d)" % first)
	Economy.advance_days(6, "test")
	var left := 100000 - 20000 - up
	check(Economy.cash() == left and Economy.day() == 8, "day 8: the week's days add up to the week's bill exactly ($%d)" % (20000 + up))
	var run := Economy.take_run_expenses()
	check(run.size() == 14 and run.all(func(e: Dictionary) -> bool: return bool(e.get("bill", false))), "each day's wages and upkeep listed for the debrief (14 lines)")
	Economy.wages_provider = func() -> int: return 100000
	Economy.add_cash(5000 - Economy.cash(), "test: $5,000 left")
	var day_bill := {}
	var on_day := func(_day: int, b: Dictionary) -> void: day_bill.merge(b)
	var notices: Array = []
	var on_notice := func(text: String) -> void: notices.append(text)
	Economy.notice.connect(on_notice)
	Economy.bill_paid.connect(on_day)
	Economy.advance_days(1, "test")
	Economy.bill_paid.disconnect(on_day)
	Economy.notice.disconnect(on_notice)
	var floor_cash := MissionRegistry.setting_i("safety_floor_cash", 20000)
	check(Economy.cash() == floor_cash and Economy.loans_owed() == roundi((int(day_bill.total) - 5000 + floor_cash) * 1.1)
		and notices.any(func(t: String) -> bool: return t.contains("Emergency loan")),
		"a day's bill beyond the cash: an emergency loan covers it and leaves the floor ($%d cash, $%d owed)" % [Economy.cash(), Economy.loans_owed()])
	Economy.wages_provider = func() -> Array: return [{"what": "Alpha", "amount": 1000}, {"what": "Bravo", "amount": 1500}]
	var bill := Economy.weekly_bill()
	var owed := Economy.loans_owed()
	check(bill.wages == 2500 and bill.loans == ceili(owed / 8.0), "wages as lines from the roster ($%d), and the loan installment ($%d)" % [bill.wages, bill.loans])
	Economy.add_cash(100000 - Economy.cash(), "test")
	var paid := [0, 0]  # bills' total, installments
	var on_bill := func(_day: int, b: Dictionary) -> void:
		paid[0] += int(b.total)
		paid[1] += int(b.loans)
	Economy.bill_paid.connect(on_bill)
	Economy.advance_days(Economy.days_to_bill(), "test")
	Economy.bill_paid.disconnect(on_bill)
	check(Economy.loans_owed() == owed - bill.loans and paid[1] == bill.loans and Economy.cash() == 100000 - paid[0],
		"the week's installment comes off the loan, once, on the week's day")
	var lent := 0
	for i in 5:
		lent += Economy.server_take_loan()
	check(Economy.loans_owed() <= MissionRegistry.setting_i("loan_max", 150000) and Economy.server_take_loan() == 0 and lent > 0,
		"loans stop at the cap ($%d owed)" % Economy.loans_owed())
	check(Contracts.board().any(func(o: Dictionary) -> bool: return o.source == "safe" and int(o.rated) == 1), "the board always keeps a low-risk job")
	Economy.wages_provider = Callable()
	check(Economy.weekly_bill().wages == Prices.default_wage_bill(), "without a roster, the stand-in wage bill")


## The economy overhaul's numbers (docs/economy_proposal_2026-10-20.md, built 2026-10-20) and its
## closed loopholes that live in Contracts and Economy.
func _test_overhaul_numbers() -> void:
	print("Economy overhaul numbers")
	var pay: Array = MissionRegistry.data().settings.difficulty_pay
	var want := [0.0, 0.35, 0.5, 0.6, 0.75, 0.95]
	check(pay.size() == want.size() and range(want.size()).all(func(i: int) -> bool: return is_equal_approx(float(pay[i]), want[i])) and is_equal_approx(MissionRegistry.setting_f("hot_zone_pay_mult"), 1.4)
		and is_equal_approx(MissionRegistry.setting_f("clean_bonus_share"), 0.05), "pay a third lower, hot zones still x1.4 (no arrival contracts now), the clean bonus 5%")
	check(Prices.lost_support_price("transport") == 15000 and Prices.lost_support_price("resupply") == 15000 and Prices.operations("kia_benefit") == 10000
		and is_equal_approx(Prices.respawn_rise(), 0.25) and Prices.respawn_max() == 8000,
		"a lost helicopter's deductible $15,000, death benefit $10,000, respawns +25% each up to $8,000")
	# Intel sells for its own worth, and prices.json keeps intel at its intel_value (loot rotation's pieces too).
	var off := PackedStringArray()
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if MissionRegistry.is_intel(id) and item.stats.has("intel_value") and Prices.price_of(id) != int(item.stats.intel_value):
			off.append(String(id))
	check(Prices.intel_sale_value(&"intel_usb_drive") == 600 and Prices.intel_sale_value(&"intel_laptop", 2) == 6000 and Prices.intel_sale_value(&"vantage_ledger") == 4000
		and off.is_empty(), "intel sells for its intel_value ($600 USB drive, $3,000 laptop, $4,000 Vantage ledger); prices match it%s" % ("" if off.is_empty() else " except %s" % ", ".join(off)))
	# A hot zone goes in on the contracts taken for it (Captain, 2026-10-20: no top-up to 3-6 on arrival);
	# one that comes in on the spot (the radio's) pays nothing up front.
	Contracts.new_full_campaign(64, 200000)
	var hot := _make_offer("raid", "ridge_hot")
	Contracts.server_accept(hot, ContractGen.default_terms())
	var signed := int(Contracts.contract(hot).deal.advance)
	check(Contracts.server_start_deployment([hot]) == "" and Contracts.deployment().cids == [hot], "a hot zone deployed on one contract has that one live, no more")
	var cash := Economy.cash()
	var spot := Contracts.server_contract_on_spot()
	var on_spot := Contracts.contract(spot)
	check(spot != "" and spot in Contracts.deployment().cids and int(on_spot.deal.advance) == 0 and int(on_spot.deal.completion) == int(on_spot.deal.pay_total)
		and Economy.cash() == cash, "a contract taken there on the spot joins it: nothing up front, $%s on completion" % DebriefCalc.money(on_spot.get("deal", {}).get("completion", 0)))
	# The villages bring work too: a villager asked there hands the squad the locals' job, live.
	var told := RebelSupport.server_ask_in("ridge_hot", Economy.day(), "Villager")
	var village: Array = (Contracts.held() as Array).filter(func(c: Dictionary) -> bool: return String(c.get("in_zone", "")) == "village")
	check(told.contains("live now") and village.size() == 1 and String(village[0].source) == "locals" and String(village[0].type).begins_with("locals_")
		and String(village[0].cid) in Contracts.deployment().cids and int(village[0].deal.advance) == 0
		and not Contracts.board().any(func(c: Dictionary) -> bool: return String(c.get("source", "")) == "locals" and String(c.get("zone_id", "")) == "ridge_hot"),
		"a villager asked in the hot zone: the locals' job joins the deployment live, nothing up front (%s)" % told)
	check(RebelSupport.server_ask_in("ridge_hot", Economy.day(), "Villager").contains("you have our job") and village.size() == 1,
		"asked again that day: they've given theirs already")
	var d := Contracts.server_end_deployment({"extracted": ["You"]})
	check(signed > 0 and int(d.totals.advance) == signed and int(d.totals.paid_now) <= 0,
		"walking in and straight out keeps only the board contract's advance")
	Contracts.server_finish_debrief()
	var board_locals := Contracts.board().filter(func(c: Dictionary) -> bool: return String(c.get("source", "")) == "locals").size()
	check(RebelSupport.server_ask_in("harbour_yard", Economy.day(), "Villager").contains("on the contract board")
		and Contracts.board().filter(func(c: Dictionary) -> bool: return String(c.get("source", "")) == "locals").size() == board_locals + 1,
		"not deployed there: the locals' job goes on the board, as before")
	# The books (base screen) sort the ledger by kind.
	check(Economy.ledger_kind("Completion: Raid") == "Contract pay" and Economy.ledger_kind("Day 4: wages 900, upkeep 3000") == "Wages and upkeep"
		and Economy.ledger_kind("Emergency Loan from Meridian") == "Loans in" and Economy.ledger_kind("Lost helicopter (transport support): replacement") == "Lost helicopters"
		and Economy.ledger_kind("Respawn on credit") == "Respawns" and Economy.ledger_kind("Something new") == "Other", "the books sort the ledger by kind")


func _test_economy_balance() -> void:
	print("Economy balance")
	var report := {"extracted": ["A", "B", "C", "D", "E", "F"], "casualties": []}
	var base := {"cid": "E1", "title": "Typical", "employer": "meridian", "target": "black_ridge", "zone_kind": "contract", "region": "coast",
		"days": 1, "state": "deployed", "deal": {"pay_total": 40000, "advance": 12000, "completion": 28000, "salvage_share": 0.1}}
	var objs := [{"oid": "E1_o1", "cid": "E1", "kind": "clear_area", "state": "done", "optional": false, "bonus_share": 0.0, "text": "x"}]
	var d := DebriefCalc.compute([base], objs, 0, report)
	var e := DebriefCalc.expenses(report, int(d.days), [])
	var wages := 8 * 400 * int(d.days)
	var upkeep := Prices.weekly_upkeep() * int(d.days) / 7
	var net := int(d.totals.contract_value) - int(e.total) - wages - upkeep
	var share := float(net) / float(d.totals.contract_value)
	check(net > 0 and share >= 0.1 and share <= 0.6, "a standard contract nets a modest profit: $%d of $%d (%d%%)" % [net, d.totals.contract_value, roundi(share * 100.0)])
	var bad_report := {"extracted": ["A", "B", "C"], "casualties": [{"name": "D", "status": "kia"}, {"name": "E", "status": "kia"}, {"name": "F", "status": "wounded"}]}
	var bad_run := [{"what": "Support call: resupply", "amount": 12000}, {"what": "Support call: extraction", "amount": 14000}, {"what": "Lost helicopter", "amount": 40000}]
	var failed := DebriefCalc.compute([base], [objs[0].merged({"state": "failed"}, true)], 0, bad_report)
	var be := DebriefCalc.expenses(bad_report, int(failed.days), bad_run)
	var bad_net := int(failed.totals.contract_value) - int(be.total) - wages - upkeep
	check(bad_net < 0, "a disastrous one (2 KIA, a lost helicopter, supports, failed) loses money: $%d" % bad_net)
	check(be.lines.any(func(l: Dictionary) -> bool: return String(l.what).begins_with("Death benefit")) and int(be.charge) < int(be.total),
		"the expense lines list the death benefit and the run's own costs")
	# Daily bills are listed per day and summed per kind in the debrief, and a bought respawn costs money.
	Contracts.new_full_campaign(7, 500000)
	Economy.take_run_expenses()
	Economy.advance_days(14, "test")
	var listed := Economy.take_run_expenses()
	var lines: Array = DebriefCalc.expenses({}, 14, listed).lines
	check(listed.filter(func(x: Dictionary) -> bool: return String(x.what) == "Base upkeep").size() == 14
		and lines.any(func(l: Dictionary) -> bool: return String(l.what) == "Base upkeep (14 days)" and int(l.amount) == 2 * Prices.weekly_upkeep()),
		"14 days pass: 14 days of upkeep listed, one debrief line ($%d)" % (2 * Prices.weekly_upkeep()))
	Contracts.new_full_campaign(7, 500000)
	Economy.advance_days(3, "test: days at base")
	var cid := _make_offer("raid", "harbour_yard")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	check(Economy.take_run_expenses().is_empty(), "a deployment starts: the days waited at base aren't its debrief's")
	Contracts.server_abandon_deployment()
	var before := Economy.cash()
	Economy.charge_run(Prices.respawn_price(), "Respawn")
	var run := Economy.take_run_expenses()
	check(Economy.cash() == before - Prices.respawn_price() and run.size() == 1 and int(run[0].amount) == Prices.respawn_price(), "a bought respawn costs $%d and is listed" % Prices.respawn_price())


func _test_lapse() -> void:
	print("Lapsed contracts and expired offers")
	Contracts.new_full_campaign(11, 100000)
	var cid: String = Contracts.board()[0].cid
	Contracts.server_accept(cid, ContractGen.default_terms())
	var employer := String(Contracts.contract(cid).employer)
	var rep := Economy.reputation(employer)
	Economy.advance_days(MissionRegistry.setting_i("accept_window_days", 7), "test")
	check(Contracts.contract(cid).state == "accepted", "still held on its last day")
	Economy.advance_days(1, "test")
	check(Contracts.contract(cid).is_empty() and Contracts.history().back().cid == cid and Contracts.history().back().outcome == "lapsed"
		and Economy.reputation(employer) <= rep - 3 and Economy.reputation(employer) >= rep - 3 - _decay_since(int((Economy.state().get("rep_jobs", {}) as Dictionary).get(employer, Economy.day())), Economy.day()), "a contract never deployed lapses and costs reputation (%+d, decay included)" % (Economy.reputation(employer) - rep))
	check(Contracts.board().all(func(o: Dictionary) -> bool: return int(o.expires_day) >= Economy.day()) and Contracts.board().size() >= 6,
		"old offers expired and the board refilled (%d)" % Contracts.board().size())


## Days of reputation decay between a job on `job_day` and `today` (wave 6a rules).
func _decay_since(job_day: int, today: int) -> int:
	var rules := MissionRegistry.reputation_rules()
	return maxi(today - job_day - int(rules.get("decay_grace_days", 7)), 0) * int(rules.get("decay_per_day", 0))


## Wave 6a (2026-10-18; the decided rules in mission_brainstorm.md, Proposed numbers in
## factions.json): the five tiers, ripple to allies and enemies, decay toward neutral, side
## lockout, and pay by tier.
func _test_reputation_core() -> void:
	print("Reputation core (wave 6a)")
	Contracts.new_full_campaign(12, 100000)
	var ids := MissionRegistry.reputation_tiers().map(func(t: Dictionary) -> String: return String(t.id))
	check(ids == ["hostile", "distrusted", "neutral", "trusted", "allied"], "five tiers: Hostile, Distrusted, Neutral, Trusted, Allied (%s)" % [ids])
	# Ripple: Meridian's enemies are Black Ridge and Vantage.
	var br := Economy.reputation("black_ridge")
	var su := Economy.reputation("salvage_union")
	Economy.change_reputation("meridian", 8, "test")
	check(Economy.reputation("black_ridge") == br - 2 and Economy.reputation("salvage_union") == su,
		"rep with Meridian rises: its enemy Black Ridge drops a quarter of it, the neutral Salvage Union doesn't move (%d, %d)" % [Economy.reputation("black_ridge") - br, Economy.reputation("salvage_union") - su])
	var before := Economy.reputation("black_ridge")
	Economy.change_reputation("meridian", 2, "test")
	check(Economy.reputation("black_ridge") == before, "a small change ripples nothing")
	# Pay by tier.
	Economy.change_reputation("meridian", 40 - Economy.reputation("meridian"), "test", false)
	check(is_equal_approx(Economy.pay_mult("meridian"), 1.15) and is_equal_approx(Economy.pay_mult("salvage_union"), 1.0),
		"Trusted pays x1.15, Neutral x1.0 (%.2f, %.2f)" % [Economy.pay_mult("meridian"), Economy.pay_mult("salvage_union")])
	# Hostile: no work.
	check(Economy.work_problem("black_ridge").contains("Hostile"), "a Hostile faction won't hire the company (%s)" % Economy.work_problem("black_ridge"))
	# Side lockout: a Meridian job locks out Vantage for lockout_days.
	Economy.change_reputation("vantage_group", 10 - Economy.reputation("vantage_group"), "test", false)
	check(Economy.work_problem("vantage_group") == "", "Vantage would hire us at Neutral")
	Economy.note_job("meridian")
	var days := int(MissionRegistry.reputation_rules().get("lockout_days", 3))
	check(Economy.work_problem("vantage_group").contains("enemies"), "after a Meridian job, its enemy Vantage won't (%s)" % Economy.work_problem("vantage_group"))
	Economy.advance_days(days + 1, "test")
	Economy.note_job("salvage_union")  # (keeps nothing locked)
	check(Economy.work_problem("vantage_group") == "", "%d days on, the lockout is over" % (days + 1))
	# Decay: no job with Meridian for a while: it drifts toward neutral.
	var m := Economy.reputation("meridian")
	var grace := int(MissionRegistry.reputation_rules().get("decay_grace_days", 7))
	Economy.advance_days(grace + 3, "test")
	check(Economy.reputation("meridian") < m and Economy.reputation("meridian") > 0, "no work for Meridian in %d days: Trusted drifts toward neutral (%d -> %d)" % [grace + 3, m, Economy.reputation("meridian")])
	# Heat (wave 6d): a faction's men killed and sites taken out make it angry; it cools by the day.
	var rules := MissionRegistry.reputation_rules()
	var h0 := Economy.heat("black_ridge")
	Economy.add_heat("black_ridge", float(rules.heat_hunters) - h0 + 1.0)
	check(Economy.hunting("black_ridge") and not Economy.hunting("salvage_union"), "past %d heat Black Ridge hunts the squad (%.1f)" % [int(rules.heat_hunters), Economy.heat("black_ridge")])
	Economy.advance_days(1, "test")
	check(not Economy.hunting("black_ridge") and is_equal_approx(Economy.heat("black_ridge"), float(rules.heat_hunters) + 1.0 - float(rules.heat_cool_per_day)),
		"a quiet day cools it below that (%.1f)" % Economy.heat("black_ridge"))
	# Named hunter squads (wave 6d): one per faction at a time; it remembers; its leader's death ends it.
	var n := Economy.server_raise_nemesis("black_ridge")
	check(not n.is_empty() and String(n.name).split(" ").size() == 2 and String(n.leader) != "" and Economy.nemesis("black_ridge") == n
		and Economy.server_raise_nemesis("black_ridge") == n, "Black Ridge raises one named hunter squad: the %s, led by %s" % [n.get("name", "?"), n.get("leader", "?")])
	Economy.server_nemesis_met(String(n.id))
	Economy.server_nemesis_met(String(n.id))
	check(int(Economy.nemesis("black_ridge").encounters) == 2, "it remembers every time it came for the squad")
	Economy.server_nemesis_event(String(n.id), 0, true)
	check(Economy.nemesis("black_ridge").is_empty() and String(Economy.server_raise_nemesis("black_ridge").name) != "",
		"its leader dead, it's finished; a new one can rise in its place")
	# Wave 6b call 4: the allied employers ripple together, and a save from before the
	# placeholder army was renamed carries over (Campaign.load_campaign's migration).
	var uk := Economy.reputation("uk_forces")
	var ca := Economy.reputation("ca_forces")
	Economy.change_reputation("us_forces", 20, "test")
	check(Economy.reputation("uk_forces") == uk + 5 and Economy.reputation("ca_forces") == ca + 5,
		"standing with the US ripples a quarter to the UK and Canada (%+d, %+d)" % [Economy.reputation("uk_forces") - uk, Economy.reputation("ca_forces") - ca])
	var old_save := {"rep": {"federal_army": -35, "meridian": 4}, "heat": {"federal_army": 12.0},
		"nemeses": [{"id": "N1", "faction": "federal_army"}], "pass_hot": {"holder": "federal_army", "grip": 0.5}}
	check(MissionRegistry.migrate_faction_keys(old_save) and old_save.rep == {"eastern_concord": -35, "meridian": 4}
		and old_save.heat == {"eastern_concord": 12.0} and old_save.nemeses[0].faction == "eastern_concord" and old_save.pass_hot.holder == "eastern_concord"
		and not MissionRegistry.migrate_faction_keys(old_save),
		"an old save's Federal Army standing, heat, nemesis and held zone move to the Eastern Concord Forces, once")


## Wave 6c: persistent world (a zone's holder and grip outlive a deployment), made a living war
## (terror groups, 2026-10-20: docs/terror_groups.md 7): every zone in it, fronts that flip zones
## by the factions' wants and strength, the same war every time for a campaign, the last zone and
## the FOB sieged but never taken, the player's wins pushing fronts, the board following the war,
## the company's ground attacked, and a faction wiped out only with its leaders.
func _test_world_sites() -> void:
	print("World sites: the living war")
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	Campaign.section(ZoneControl.SECTION).clear()
	var zid := "pass_hot"
	var h1 := WorldSites.holder(zid)
	check(h1 == "kestrel" and WorldSites.holder(zid) == h1, "a zone's holder is seeded from its data and stays stable (%s)" % h1)
	check(WorldSites.war_zones().size() == 27 and WorldSites.holder("dry_wadi") == "valley_shura" and WorldSites.holder("greyfell_moor") == "highland_front",
		"every zone is in the war, each held by its group (%d zones)" % WorldSites.war_zones().size())
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP), "a fresh site starts at full grip (%.2f)" % WorldSites.grip(zid))
	WorldSites.server_contract_won(zid, "nobody_holds_this")
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP), "a win against someone who doesn't hold it does nothing to the grip")
	var st0 := WorldSites.strength(h1)
	WorldSites.server_contract_won(zid, h1)
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP - WorldSites.WIN_GRIP_HIT) and WorldSites.strength(h1) < st0,
		"a win against the actual holder knocks its grip and its strength down (%.2f, %.0f)" % [WorldSites.grip(zid), WorldSites.strength(h1)])
	check(WorldSites.worth("valley_shura", "dry_wadi") > WorldSites.worth("saltline", "dry_wadi") and WorldSites.worth("saltline", "harbour_yard") > WorldSites.worth("valley_shura", "harbour_yard"),
		"each wants its own: the Shura the village zones, the Syndicate the harbours")
	# The same campaign plays the same war.
	var snap_sites: Dictionary = Campaign.section(WorldSites.SECTION).duplicate(true)
	var snap_war: Dictionary = Campaign.section(WorldSites.WAR).duplicate(true)
	WorldSites.server_advance_days(30)
	var first := WorldSites.war_view()
	_restore_section(WorldSites.SECTION, snap_sites)
	_restore_section(WorldSites.WAR, snap_war)
	WorldSites.server_advance_days(30)
	var again := WorldSites.war_view()
	check(JSON.stringify(first.zones) == JSON.stringify(again.zones) and JSON.stringify(first.news) == JSON.stringify(again.news),
		"the war is deterministic: the same 30 days twice, the same war")
	var changed := WorldSites.war_zones().filter(func(z: String) -> bool: return String(first.zones[z].holder) != String(ZoneControl.zone_def_raw(z).controller))
	check(changed.size() >= 3, "zones change hands over a month (%d of them)" % changed.size())
	print("  news: %s" % " | ".join(PackedStringArray((first.news as Array).map(func(n: Dictionary) -> String: return String(n.text)))))
	# A front by hand: the attacker strong, the holder weak, nearly through.
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	var st: Dictionary = WorldSites._war().strength
	st["saltline"] = 100.0
	st["kestrel"] = 10.0
	var gulch := WorldSites.site("red_gulch")
	gulch.grip = 0.1
	gulch["front"] = {"by": "saltline", "since": 1, "progress": 0.98}
	WorldSites._tick_day()
	check(WorldSites.holder("red_gulch") == "saltline" and WorldSites.is_flashpoint("red_gulch") and WorldSites.front("red_gulch").is_empty(),
		"a front that gets through flips the zone, flagged a flashpoint (%s)" % WorldSites.holder("red_gulch"))
	var flip_news := (WorldSites.news() as Array).filter(func(n: Dictionary) -> bool: return String(n.kind) == "flip")
	check(not flip_news.is_empty() and String(flip_news.back().text).contains("took Red Gulch"),
		"the news says so: %s" % (String(flip_news.back().text) if not flip_news.is_empty() else "nothing"))
	# A player's win pushes a front back from whoever the company hit.
	var orchards := WorldSites.site("old_orchards")
	orchards["front"] = {"by": "valley_shura", "since": int(WorldSites._war().day), "progress": 0.5}
	WorldSites.server_contract_won("old_orchards", "valley_shura")
	check(is_equal_approx(float(WorldSites.front("old_orchards").progress), 0.5 - WorldSites.WIN_FRONT_PUSH), "a win against the attacker pushes its front back")
	WorldSites.server_contract_won("old_orchards", "kestrel")
	check(is_equal_approx(float(WorldSites.front("old_orchards").progress), 0.5), "and one against the holder helps it on")
	# The board follows the war: a job on the front.
	Contracts.server_refresh_board()
	var board: Array = Campaign.section(Contracts.SECTION).get("board", [])
	var on_front := board.filter(func(c: Dictionary) -> bool: return c.get("zone_id", "") == "old_orchards" and c.get("war_front", false))
	check(on_front.size() == 1 and String(on_front[0].target) in ["valley_shura", "kestrel"] and String(on_front[0].brief).begins_with("Fighting in Old Orchards"),
		"a job goes up on the front, its brief saying who is fighting whom (%s)" % [on_front.map(func(c: Dictionary) -> String: return String(c.brief).left(80))])
	var posted := board.filter(func(c: Dictionary) -> bool: return c.get("zone_id", "") == "red_gulch" and c.get("war_flip", false) and c.get("target", "") == "saltline")
	check(posted.size() == 1 and String(posted[0].target) == "saltline" and not WorldSites.is_flashpoint("red_gulch"),
		"and the flipped zone's own offer, against the new holder, clearing the flag (%s, flag %s)" % [posted.map(func(c: Dictionary) -> String: return "%s vs %s" % [c.title, c.target]), WorldSites.is_flashpoint("red_gulch")])
	# The last zone: sieged, never taken by another faction (Captain).
	st["black_ridge"] = 100.0
	st["highland_front"] = 5.0
	var moor := WorldSites.site("greyfell_moor")
	moor.grip = 0.05
	moor["front"] = {"by": "black_ridge", "since": int(WorldSites._war().day), "progress": 0.98}
	WorldSites._tick_day()
	check(WorldSites.holder("greyfell_moor") == "highland_front" and bool(WorldSites.front("greyfell_moor").get("sieged", false)),
		"a faction's last zone can be sieged but doesn't fall to another faction")
	# Wiped out only by the company, with its leaders taken.
	check(not WorldSites.server_company_takes("greyfell_moor") and not WorldSites.is_wiped("highland_front"),
		"its HQ and QRF down aren't enough while its leaders are free")
	WorldSites.server_contract_won("greyfell_moor", "highland_front", "hvt_capture")
	WorldSites.server_contract_won("greyfell_moor", "highland_front", "manhunt")
	check(WorldSites.leaders_all_down("highland_front") and WorldSites.server_company_takes("greyfell_moor") and WorldSites.is_wiped("highland_front")
		and "highland_front" not in WorldSites.warring(), "its leaders taken too, the company takes it and the faction is finished")
	# The company's ground attacked (Captain: yes, now): a defence job, and lost if the front gets through.
	var zones_c := Campaign.section(ZoneControl.SECTION)
	zones_c["zones"] = {"blackwood": {"state": ZoneControl.COMPANY, "down": []}}
	check(WorldSites.holder_now("blackwood") == ZoneControl.PLAYER, "a zone the company took is the company's in the war")
	var wood := WorldSites.site("blackwood")
	wood["front"] = {"by": "kestrel", "since": int(WorldSites._war().day), "progress": 0.5}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var defend := Contracts.front_offer(rng, "blackwood", Economy.day())
	check(String(defend.get("type", "")) == "defend_hold" and String(defend.get("target", "")) == "kestrel",
		"an attack on the company's ground posts a defence against the attacker (%s)" % String(defend.get("title", "")))
	st["kestrel"] = 100.0
	wood.grip = 0.0
	(wood.front as Dictionary)["progress"] = 0.99
	WorldSites._tick_day()
	check(ZoneControl.control("blackwood") == ZoneControl.ENEMY and WorldSites.holder("blackwood") == "kestrel",
		"a front that gets through takes the company's zone back (%s)" % ZoneControl.control("blackwood"))
	zones_c.clear()
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	# Contract targets follow the holder; Black Ridge no longer takes most of them.
	var offers := ContractGen.generate_board(4321, 1, {"meridian": 10}, 200)
	var by_target := {}
	var on_holder := 0
	var in_war := 0
	for o: Dictionary in offers:
		by_target[o.target] = int(by_target.get(o.target, 0)) + 1
		if WorldSites.is_war_zone(String(o.zone_id)):
			in_war += 1
			if String(o.target) == WorldSites.holder(String(o.zone_id)):
				on_holder += 1
	check(float(by_target.get("black_ridge", 0)) / offers.size() <= 0.25, "Black Ridge's share of contracts is down to %d%% (%s)" % [roundi(100.0 * by_target.get("black_ridge", 0) / offers.size()), by_target])
	check(["ashen_banner", "valley_shura", "saltline", "kestrel"].all(func(g: String) -> bool: return int(by_target.get(g, 0)) > 0),
		"every new group is a contract target")
	check(in_war > 0 and float(on_holder) / in_war >= 0.55, "most contracts are against the zone's holder (%d of %d)" % [on_holder, in_war])
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()


## A contract of `type_id` against `target` in `zone_id` from the first seed (of 300) whose offer
## `fits` (a Callable on the offer), {} if none does. `source` "locals" for the locals' own jobs.
func _offer_against(type_id: String, target: String, zone_id: String, fits: Callable, source := "board") -> Dictionary:
	for i in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7700 + i
		var c := ContractGen.generate(rng, {"day": 1, "source": source, "type": type_id, "zone_id": zone_id, "target": target})
		if String(c.type) == type_id and fits.call(c):
			return c
	return {}


## The first objective of `c` (its legs' too) at site `site_id`, {} if none.
static func _at_site(c: Dictionary, site_id: String) -> Dictionary:
	var all: Array = (c.get("objectives", []) as Array).duplicate()
	for leg: Dictionary in c.get("legs", []):
		all.append_array(leg.objectives)
	for o: Dictionary in all:
		if String(o.get("site", "")) == site_id:
			return o
	return {}


## Terror groups follow-ups (2026-10-20, docs/terror_groups.md section 9): each group's own name
## for a raid's cache, the cartels' goods beside a target to destroy, the leaders as the HVTs of
## capture and manhunt jobs (named, dressed for their part, and taken down by name), and Vantage
## and the Concord fighting by doctrines of their own.
func _test_faction_followups() -> void:
	print("Terror groups follow-ups: site names, contraband, named leaders, doctrines")
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	var zone := "harbour_yard"
	var on_cache := func(c: Dictionary) -> bool: return not _at_site(c, "cache").is_empty()
	# Site names follow the target.
	var lab := _offer_against("raid", "kestrel", zone, on_cache)
	var lab_o := _at_site(lab, "cache")
	check(String(lab_o.get("site_name", "")) in ["drug lab", "warehouse"] and String(lab_o.text) == "Destroy the %s" % lab_o.site_name
		and String(lab.title).contains("(%s)" % lab_o.site_name), "a raid on the Kestrel Cartel's cache is on its %s (%s)" % [lab_o.get("site_name", "nothing"), lab.get("title", "")])
	var again := _offer_against("raid", "kestrel", zone, func(c: Dictionary) -> bool: return String(c.module_id) == String(lab.module_id) and not _at_site(c, "cache").is_empty())
	check(String(_at_site(again, "cache").get("site_name", "")) == String(lab_o.get("site_name", "")), "the same site is the same thing every time")
	var cartels := {}
	for g: String in ["kestrel", "saltline"]:
		for i in 12:
			cartels[ContractGen.faction_site_name(g, "cache", "zone%d|m%d" % [i, i])] = true
	check(cartels.has("drug lab") and cartels.has("warehouse") and cartels.size() == 2, "the cartels keep both drug labs and warehouses (%s)" % [cartels.keys()])
	var ied := _offer_against("raid", "ashen_banner", zone, on_cache)
	var shura := _offer_against("supply_line", "valley_shura", zone, on_cache)
	check(String(_at_site(ied, "cache").get("text", "")) == "Destroy the IED workshop" and String(_at_site(shura, "cache").get("text", "")) == "Destroy the IED workshop",
		"the Ashen Banner's and the Valley Shura's caches are IED workshops (%s; %s)" % [_at_site(ied, "cache").get("text", ""), _at_site(shura, "cache").get("text", "")])
	var plain := _at_site(_offer_against("raid", "black_ridge", zone, on_cache), "cache")
	check(String(plain.get("text", "")) == "Destroy the weapons cache" and not plain.has("site_name") and not plain.has("loot_of"),
		"Black Ridge's is still a weapons cache, with nothing extra beside it")
	var placed := Objectives.from_contract(lab.merged({"cid": "TFF1"}, true))
	var placed_o: Dictionary = placed.filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.DESTROY_CACHE)[0]
	check(String(placed_o.params.get("name", "")) == String(lab_o.get("site_name", "")) and String(placed_o.params.get("loot_of", "")) == "kestrel",
		"placed, the objective's site carries its name (the HUD's \"Destroy the %s\") and whose goods sit beside it" % placed_o.params.get("name", ""))
	# Contraband: a box beside the cartels' targets, and in some of their men's pockets.
	check(String(lab_o.get("loot_of", "")) == "kestrel" and not _at_site(ied, "cache").has("loot_of"), "only the cartels leave their goods at a raid's target")
	var sab := _offer_against("sabotage", "saltline", zone, func(c: Dictionary) -> bool: return (c.objectives as Array).any(func(o: Dictionary) -> bool: return bool(o.get("optional", false)) and String(o.get("site", "")) == "aa"))
	var sab_main: Array = (sab.get("objectives", []) as Array).filter(func(o: Dictionary) -> bool: return not bool(o.get("optional", false)))
	var sab_aa: Array = (sab.get("objectives", []) as Array).filter(func(o: Dictionary) -> bool: return bool(o.get("optional", false)) and String(o.get("site", "")) == "aa")
	check(not sab.is_empty() and sab_main.size() == 1 and String(sab_main[0].get("loot_of", "")) == "saltline" and not sab_aa.is_empty() and not (sab_aa[0] as Dictionary).has("loot_of"),
		"a sabotage job on the Saltline Syndicate: its goods by the target (%s), not by the bonus AA gun" % sab_main[0].get("site", "") if not sab_main.is_empty() else "none")
	var stores := _at_site(_offer_against("locals_stores", "kestrel", zone, on_cache, "locals"), "cache")
	check(not stores.is_empty() and not stores.has("site_name") and not stores.has("loot_of"), "the locals' stolen stores stay their stores (%s)" % stores.get("text", "no offer"))
	var contraband := ["hashish", "captagon", "heroin_bricks", "counterfeit_dollars"]
	var seen := {}
	var only_goods := true
	for i in 200:
		var box := WorldValuables.contraband_box("kestrel", "test|%d" % i, true)
		for row: Dictionary in box.get("items", []):
			seen[String(row.id)] = true
			only_goods = only_goods and (Fixers.is_contraband(StringName(String(row.id))) or ItemDB.get_item(StringName(String(row.id))).type == "valuable")
	check(contraband.all(func(id: String) -> bool: return seen.has(id)) and only_goods, "the stash holds hashish, captagon, heroin and fake dollars (%s)" % [seen.keys()])
	check(WorldValuables.contraband_box("ashen_banner", "test|1", true).is_empty() and String(WorldValuables.contraband_box("saltline", "t", true).label) != "",
		"no stash for a group that doesn't deal")
	var carriers: Array = range(9).filter(func(i: int) -> bool: return not WorldValuables.pocket_contraband("kestrel", "zone|m1", i, true).is_empty())
	var pockets := WorldValuables.pocket_contraband("saltline", "zone|m1", 1, true)
	check(carriers == [1, 4, 7] and pockets.size() >= 1 and pockets.all(func(id: String) -> bool: return ItemDB.has_item(StringName(id)))
		and range(9).all(func(i: int) -> bool: return WorldValuables.pocket_contraband("black_ridge", "zone|m1", i, true).is_empty()),
		"every third cartel man carries some (%s; %s), nobody else's do" % [carriers, pockets])
	# Named leaders.
	var hvt := _offer_against("hvt_capture", "kestrel", zone, func(c: Dictionary) -> bool: return true)
	var hvt_o := _at_site(hvt, "hvt")
	var person: Dictionary = hvt_o.get("person", {})
	check(String(hvt.get("leader", "")) == "the Patron" and String(hvt.title).begins_with("HVT capture (the Patron):")
		and String(hvt.brief).begins_with("Target: %s, the Patron of the Kestrel Cartel." % person.get("name", "?")),
		"an HVT job against the Kestrel Cartel is after its first leader, by name (%s | %s)" % [hvt.get("title", ""), String(hvt.get("brief", "")).left(70)])
	check(String(hvt_o.text) == "Capture the Patron (%s) and bring them to extraction alive" % person.get("name", "?") and String(person.get("leader", "")) == "the Patron"
		and String(person.get("label", "")) == "HVT (%s, the Patron)" % person.get("name", "?") and String(person.get("role", "")) == "financier",
		"the objective names him, and he dresses as a financier (%s; %s)" % [hvt_o.get("text", ""), person.get("role", "")])
	var phone := _at_site(hvt, "hvt_phone")
	check(phone.is_empty() or String(phone.text) == "Bonus: bring out %s's phone" % person.get("name", "?"), "his phone is just his phone (%s)" % phone.get("text", "none"))
	WorldSites.server_contract_won(zone, "kestrel", "hvt_capture", String(hvt.leader))
	var next := _offer_against("hvt_capture", "kestrel", zone, func(c: Dictionary) -> bool: return true)
	check(WorldSites.leaders_down("kestrel") == ["the Patron"] and String(next.get("leader", "")) == "the Chemist"
		and String(_at_site(next, "hvt").get("person", {}).get("role", "")) == "bomb_maker",
		"taken, the next job is after the Chemist, dressed as a bomb maker (%s)" % next.get("title", ""))
	WorldSites.server_contract_won(zone, "kestrel", "hvt_capture", "the Enforcer")
	check(WorldSites.leaders_down("kestrel") == ["the Patron", "the Enforcer"] and WorldSites.next_leader("kestrel") == "the Chemist",
		"a job that named the Enforcer takes the Enforcer, the Chemist still free")
	WorldSites.server_contract_won(zone, "kestrel", "manhunt", "the Enforcer")
	check(WorldSites.leaders_all_down("kestrel") and WorldSites.next_leader("kestrel") == "", "one already taken: the next free goes instead, and then all are down")
	var spent := _offer_against("hvt_capture", "kestrel", zone, func(c: Dictionary) -> bool: return true)
	check(String(spent.get("leader", "x")) == "" and String(spent.title).begins_with("HVT capture:") and not String(spent.brief).begins_with("Target:"),
		"all its leaders taken: a plain HVT job (%s)" % spent.get("title", ""))
	var manhunt: Dictionary = {}
	for z: String in WorldSites.war_zones():
		if String(MissionRegistry.zone(z).get("kind", "")) != "contract":
			continue
		manhunt = _offer_against("manhunt", "highland_front", z, func(c: Dictionary) -> bool: return not (c.get("legs", []) as Array).is_empty())
		if not manhunt.is_empty():
			break
	var hunted := _at_site(manhunt, "hvt")
	check(not manhunt.is_empty() and String(manhunt.leader) == "the Commandant" and String(hunted.get("text", "")).begins_with("Capture the Commandant (")
		and String(manhunt.brief).contains("the Commandant of the Highland Free Front") and String(manhunt.title).contains("(the Commandant)"),
		"a manhunt names him too, in the zone next door (%s | %s)" % [manhunt.get("title", ""), hunted.get("text", "")])
	check(String(_offer_against("hvt_capture", "vantage_group", zone, func(c: Dictionary) -> bool: return true).get("leader", "x")) == "",
		"Vantage has no leaders: its HVT jobs are as they were")
	var roles_ok := true
	var unfit: Array = []
	for g: String in ["black_ridge", "ashen_banner", "valley_shura", "saltline", "kestrel", "highland_front"]:
		var roles: Dictionary = MissionRegistry.faction(g).get("leader_roles", {})
		for title: Variant in MissionRegistry.faction(g).get("leaders", []):
			if StringName(String(roles.get(String(title), ""))) not in PersonLook.HOSTILE_ROLES:
				roles_ok = false
				unfit.append("%s: %s" % [g, title])
	check(roles_ok, "every leader dresses as one of PersonLook's HVT roles (commander, financier, bomb maker) %s" % [unfit])
	var dressed := PersonLook.outfit(Person.HVT, Person.HOSTILE, {"name": "Person_x", "site": "outpost", "role": "financier"}).trim_prefix(VoxelArt.CIV_PREFIX).split(":")
	check(String(dressed[0]) in PersonLook.ROLES[&"financier"].shirt and String(dressed[1]) in PersonLook.ROLES[&"financier"].trousers,
		"a financier leader at an outpost wears a financier's dark suit (%s)" % [dressed])
	# Doctrines of their own.
	check(Kits.doctrine("eastern_concord") == &"regular" and Kits.doctrine("vantage_group") == &"pmc" and Doctrine.has(&"regular") and Doctrine.has(&"pmc"),
		"the Concord fights by the regular doctrine and Vantage by the PMC one, wherever they are")
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()


func _restore_section(section_name: StringName, snap: Dictionary) -> void:
	var sec := Campaign.section(section_name)
	sec.clear()
	sec.merge(snap.duplicate(true))


## Kill attribution (6d's open item): EnemyResponse tags every man it spawns for a named
## hunter squad with its id (meta "nemesis"); one of them killing a friendly counts against it
## (Soldier._note_nemesis_kill, off the same Harm ledger the session log reads). Needs a live
## level (level.spawn_soldier), so it runs after one is up, not from _test_reputation_core.
func _test_nemesis_kill_attribution() -> void:
	print("Named hunter squad: kill attribution")
	var n := Economy.server_raise_nemesis("black_ridge")
	var hunter := _hostile("NemesisHunter", Vector3(400, 0.1, 400))
	hunter.set_meta(&"nemesis", String(n.id))
	var victim := level.spawn_soldier({"name": "NemesisVictim", "faction": "friendly", "variant": "multicam",
		"pos": hunter.global_position + Vector3(2, 0, 0), "loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(victim).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(2)
	Harm.note_hit(victim, hunter)
	victim.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.FULL_POWER})
	await _frames(3)
	check(int(Economy.nemesis("black_ridge").kills) == 1, "a kill by its tagged men counts against it (%d)" % int(Economy.nemesis("black_ridge").kills))
	hunter.queue_free()
	victim.queue_free()
	Economy.server_nemesis_event(String(n.id), 0, true)  # tidy up: done with this one too


## Wave 6e: allied troops. Each element is its own Squad instance (faction "friendly" beside the
## player's own): Squad.members()/brains() must answer for it alone, never the player's squad,
## the other element, or vice versa. Standing sets how many at once (Trusted one, Allied two),
## cost and a per-slot cooldown gate the call; elements wear their employer's kit; the rifle
## squad and the MG + AT weapons team; the host's high command orders all or one (map orders).
func _test_allied_troops() -> void:
	print("Allied troops: elements, standing, kit, cost, cooldown, and the high command")
	var allies := AlliedTroops.current(level)
	check(allies != null, "installed on the level")
	var own_before := level.squad_for(&"friendly").members().size()
	check(allies.server_call(player) != "", "refused with no deployment to vouch for our standing")
	# A fake deployment for a UK job, trusted enough (Trusted tier, rep >= 30).
	var cs := Campaign.section(Contracts.SECTION)
	var held_before: Array = cs.get("held", [])
	var deployment_before: Dictionary = cs.get("deployment", {})
	var uk_before := Economy.reputation("uk_forces")
	Economy.change_reputation("uk_forces", 40 - Economy.reputation("uk_forces"), "test", false)
	cs.held = [{"cid": "TESTALLY1", "employer": "uk_forces"}]
	cs.deployment = {"cids": ["TESTALLY1"]}
	Economy.add_cash(Prices.support_price(AlliedTroops.PRICE_KIND) * 4, "test setup")  # whatever's left from earlier tests, cover the calls for sure
	var cash_before := Economy.cash()
	check(allies.max_out() == 1, "Trusted lends one element at a time")
	check(allies.server_call(player) == "", "Trusted standing, paid: the call goes through")
	check(Economy.cash() < cash_before, "and it's not free (%d -> %d)" % [cash_before, Economy.cash()])
	check(allies.is_out() and allies.squad.members().size() == AlliedTroops.SIZE, "a rifle squad of its own size is out (%d)" % allies.squad.members().size())
	check(allies.squad.members().all(func(s: Soldier) -> bool: return _carries(s, &"l85a2") or _carries(s, &"m249") or _carries(s, &"at4")),
		"lent by the UK, it carries UK kit (L85A2s, with its gunners and AT man)")
	check(level.squad_for(&"friendly").members().size() == own_before, "the player's own squad still counts only its own (%d)" % level.squad_for(&"friendly").members().size())
	check(allies.server_call(player, false, "weapons") != "", "refused: Trusted's one element is already out")
	# Allied standing: a second element, the weapons team.
	Economy.change_reputation("uk_forces", 75 - Economy.reputation("uk_forces"), "test", false)
	check(allies.max_out() == 2 and allies.server_call(player, false, "weapons") == "", "Allied standing lends a second: the weapons team comes")
	var first: Squad = allies.elements[0].squad
	var team: Squad = allies.elements[1].squad
	check(team.members().size() == 4 and team.members().any(func(s: Soldier) -> bool: return _carries(s, &"m240b"))
		and first.members().size() == AlliedTroops.SIZE, "the weapons team is four with its M240B; the rifle squad still counts only its own")
	check(allies.summary().size() == 2 and String(allies.summary()[1].label).contains("weapons team"), "the map summary lists both elements")
	# The high command: only the host, all or one.
	var far := player.global_position + Vector3(0, 0, -60)
	var bot: Soldier = first.members()[0]
	check(allies.server_order(bot, "move", far).contains("host"), "only the host commands them (%s)" % allies.server_order(bot, "move", far))
	check(allies.server_order(player, "move", far) == "", "Move there: every element")
	var ally_ai := SquadAI.of(first.members()[0])
	var team_ai := SquadAI.of(team.members()[0])
	check(ally_ai.order == Squad.Order.MOVE and ally_ai._move_point.distance_to(far) < 10.0 and team_ai.order == Squad.Order.MOVE,
		"both elements go, not the player's own squad")
	var near := player.global_position + Vector3(20, 0, 0)
	check(allies.server_order(player, "defend", Vector3(near.x, 0.0, near.z), "2") == "", "a map order (at y 0) to element 2 alone")
	check(SquadAI.of(team.members()[0])._move_point.distance_to(near) < 10.0 and SquadAI.of(first.members()[0])._move_point.distance_to(far) < 10.0,
		"element 2 goes to defend there; element 1 keeps its own order")
	allies.server_order(player, "follow", Vector3.ZERO, "1")
	check(SquadAI.of(first.members()[0]).order == Squad.Order.FOLLOW, "Follow me: element 1 follows the host")
	allies.server_hold(player)
	check(SquadAI.of(first.members()[0]).order == Squad.Order.HOLD and SquadAI.of(team.members()[0]).order == Squad.Order.HOLD, "Hold stops every element")
	check(allies.server_release(player, "2") == "" and allies.out().size() == 1 and allies.squad == first, "Release element 2: the rifle squad stays out")
	check(allies.server_call(player, false, "weapons") != "", "and slot 2's cooldown refuses another straight away")
	check(allies.server_release(player) == "", "Release the rest")
	check(not allies.is_out() and allies.squad == null, "nothing's out any more")
	check(allies.server_call(player) != "", "and the cooldown refuses another straight away")
	# Meridian (a company, no troops of its own) lends the US kit.
	check(AlliedTroops.kit_for("meridian") == "allied_us" and AlliedTroops.kit_for("ca_forces") == "allied_ca", "a company's ally lends US kit; Canada its own")
	# Wave 6c's zone UI: every hot zone with its holder and grip, and the board shows them.
	var rows := WorldSites.rows()
	check(rows.size() == 5 and rows.all(func(r: Dictionary) -> bool: return String(r.holder) in MissionRegistry.enemies() and float(r.grip) > 0.0)
		and Economy.world_sites().size() == 5 and WorldSites.row_text(rows[0]).contains("grip"),
		"the board's hot zones: who holds each and how firmly (%s)" % WorldSites.row_text(rows[0]))
	cs.held = held_before
	cs.deployment = deployment_before
	Economy.change_reputation("uk_forces", uk_before - Economy.reputation("uk_forces"), "test cleanup", false)
	Economy.add_cash(cash_before - Economy.cash(), "test cleanup")  # the calls' cost shouldn't ride into the next test


## Whether `s` wears or carries `id` (a slot or any container).
static func _carries(s: Soldier, id: StringName) -> bool:
	return s.inventory.slots.values().has(id) or s.inventory.count_of(id) > 0


# --- The debrief ---------------------------------------------------------------------------

func _test_debrief_totals() -> void:
	print("Debrief sums")
	var c := {"cid": "T1", "title": "Test job", "employer": "meridian", "target": "black_ridge", "zone_kind": "contract", "region": "coast",
		"days": 1, "state": "deployed", "deal": {"pay_total": 100000, "advance": 30000, "completion": 70000, "salvage_share": 0.3}}
	var objs := [{"oid": "T1_o1", "cid": "T1", "kind": "clear_area", "state": "done", "optional": false, "bonus_share": 0.0, "text": "Clear it"},
		{"oid": "T1_o2", "cid": "T1", "kind": "extract_item", "state": "done", "optional": true, "bonus_share": 0.1, "text": "Bonus: the case"}]
	var report := {"items": [{"id": "hvt_case", "count": 1}, {"id": "mag_556", "count": 2}],
		"field_items": [{"id": "m4a1", "count": 2}, {"id": "plate_ceramic_l4", "count": 1, "state": {"integrity": 0.5}}],
		"casualties": [{"name": "Bravo", "status": "kia", "injury": ""}]}
	var d := DebriefCalc.compute([c], objs, 0, report)
	var line: Dictionary = d.contracts[0]
	var clean := roundi(100000 * MissionRegistry.setting_f("clean_bonus_share"))  # 5% since the economy overhaul (was 10%)
	check(clean == 5000 and line.outcome == "completed" and line.completion == 70000 and line.bonuses.size() == 2 and line.pay == 80000 + clean
		and d.totals.paid_now == 80000 + clean and d.totals.contract_value == 110000 + clean and d.fines == 0,
		"completed: $70,000 completion + $10,000 bonus objective + $%s for no civilian casualties ($%s all told)" % [DebriefCalc.money(clean), DebriefCalc.money(110000 + clean)])
	check(d.rep.get("meridian") == 5 and d.rep.get("black_ridge") == -3 and d.days == 2, "reputation +5 with the client, -3 with the target; 1 day plus 1 of travel")
	check(d.salvage.pool_value == 2 * 1400 + 450 and d.salvage.budget == floori(3250 * 0.3) and not DebriefCalc.can_pick(d, 0) and DebriefCalc.can_pick(d, 1),
		"salvage: 30%% of $3,250 left in the field is a $%d budget: the cracked plate fits, two rifles don't" % d.salvage.budget)
	check(d.intel.size() == 1 and d.intel[0].id == "hvt_case" and d.items_out.size() == 2 and d.casualties.size() == 1, "intel, everything carried out and casualties listed")
	var fined := DebriefCalc.compute([c], objs, 2, report)
	check(fined.totals.paid_now == 70000 + 10000 - 5000 and fined.fines == 5000 and fined.rep.get("meridian") == 5 - 4 and fined.locals == -8,
		"two civilian casualties: no clean bonus, $5,000 fines, -4 with the client and -8 with the locals")
	var failed := DebriefCalc.compute([c], [objs[1].merged({"state": "failed"}, true), objs[0].merged({"state": "failed"}, true)], 0, report)
	check(failed.contracts[0].outcome == "failed" and failed.totals.paid_now == 0 and failed.totals.contract_value == 30000 and failed.salvage.budget == 0
		and failed.rep.get("meridian") == -6, "failed: only the advance, no salvage share, -6 reputation")
	var hot := DebriefCalc.compute([c.merged({"zone_kind": "hot"}, true)], [objs[0].merged({"state": "failed"}, true)], 0, report)
	check(hot.contracts[0].outcome == "lapsed" and hot.rep.get("meridian") == -3, "a hot-zone contract left unfinished lapses (-3)")
	# Hot zones (Captain 2026-10-15): staying pays more; several contracts live at once.
	var stayed := DebriefCalc.compute([c.merged({"zone_kind": "hot"}, true)], objs, 0, report.merged({"hazard_tier": 2}, true))
	var hazard: Array = (stayed.contracts[0].bonuses as Array).filter(func(b: Dictionary) -> bool: return String(b.text).begins_with("Hazard pay"))
	check(hazard.size() == 1 and int(hazard[0].amount) == roundi(100000 * HotZoneOps.HAZARD_SHARE_PER_TIER * 2) and stayed.contracts[0].pay == line.pay + int(hazard[0].amount),
		"a hot-zone contract done at pressure tier 2: hazard pay of %d%% on top ($%d)" % [roundi(HotZoneOps.HAZARD_SHARE_PER_TIER * 200), int(hazard[0].amount) if not hazard.is_empty() else 0])
	var plain := DebriefCalc.compute([c], objs, 0, report.merged({"hazard_tier": 2}, true))
	check(plain.contracts[0].pay == line.pay, "no hazard pay outside a hot zone")
	var voided := DebriefCalc.compute([c.merged({"state": "voided"}, true)], objs, 8, report)
	check(voided.contracts[0].outcome == "voided" and voided.totals.completion == 0 and voided.totals.bonuses == 0 and voided.fines == 20000
		and voided.contracts[0].clawback == 30000 and voided.totals.paid_now == -50000 and voided.totals.contract_value == -20000,
		"voided: pays nothing (the $30,000 advance clawed back) and $20,000 in fines")
	# Captain's clawback terms: what a voided contract gives back of its advance.
	var two := [objs[0].merged({"state": "done"}, true), objs[0].merged({"oid": "T1_o3", "state": "active"}, true)]
	var kept := DebriefCalc.compute([c.merged({"state": "voided", "clawback": ContractGen.NO_CLAWBACK}, true)], two, 8, report)
	var half := DebriefCalc.compute([c.merged({"state": "voided", "clawback": ContractGen.PRORATED_CLAWBACK}, true)], two, 8, report)
	var all_back := DebriefCalc.compute([c.merged({"state": "voided", "clawback": ContractGen.FULL_CLAWBACK}, true)], two, 8, report)
	check(kept.contracts[0].clawback == 0 and half.contracts[0].clawback == 15000 and all_back.contracts[0].clawback == 30000,
		"clawback terms on a void with 1 of 2 required objectives done: none keeps it all, prorated gives back $%d, full all" % half.contracts[0].clawback)
	var honest_abort := DebriefCalc.compute([c.merged({"state": "aborted", "revealed": true, "understated": false}, true)], objs, 0, report)
	var lied_abort := DebriefCalc.compute([c.merged({"state": "aborted", "revealed": true, "understated": true}, true)], objs, 0, report)
	check(honest_abort.rep.get("meridian", 0) == -4 and lied_abort.rep.get("meridian", 0) == 0,
		"aborting mid-deployment is free only when the briefing lied")
	var summary := "\n".join(DebriefCalc.summary(d))
	check(summary.contains("COMPLETED") and summary.contains("$70,000") and summary.contains("Paid now: $%s" % DebriefCalc.money(80000 + clean)), "the summary reads right")


func _test_civilians_void() -> void:
	print("Civilian casualties and the void at 8")
	Contracts.new_full_campaign(21, 100000)
	var cid := _make_offer("clear_compound", "compound_01")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	var voided: Array = []
	var on_void := func(id: String) -> void: voided.append(id)
	Contracts.contract_voided.connect(on_void)
	for i in 7:
		Contracts.server_civilian_casualty({"by": "test"})
	check(Contracts.deployment().civilians == 7 and Contracts.contract(cid).state == "deployed" and voided.is_empty(), "7 civilian casualties: still on")
	check(Contracts.server_civilian_casualty({"by": "test"}) == 8 and Contracts.contract(cid).state == "voided" and voided == [cid]
		and Contracts.objectives.for_contract(cid).all(func(o: Dictionary) -> bool: return o.state == "failed"), "the 8th voids the contract and fails its objectives")
	Contracts.contract_voided.disconnect(on_void)
	var employer := String(Contracts.contract(cid).employer)
	var advance := int(Contracts.contract(cid).deal.advance)
	var rep := Economy.reputation(employer)
	var cash := Economy.cash()
	var d := Contracts.server_end_deployment({})
	check(d.contracts[0].outcome == "voided" and Economy.cash() == cash - 20000 - advance - int(d.expenses_total) and Economy.reputation(employer) == rep - 6 - 16 and Economy.locals() == -32,
		"debrief: pays nothing (advance $%d clawed back), $20,000 in fines, -22 with the client, -32 with the locals" % advance)
	Contracts.server_finish_debrief()
	check(Contracts.server_civilian_casualty() == 0, "no deployment, nothing counted")


func _test_save_reload() -> void:
	print("Saving and reloading the campaign")
	Contracts.new_full_campaign(31, 120000)
	var cid := _make_offer("hvt_capture", "wadi_farm")
	Contracts.server_accept(cid, {"pay_points": 1, "salvage_points": 1, "support_points": 0, "advance_share": 0.4})
	Economy.change_reputation("salvage_union", 7)
	Economy.server_take_loan()
	Economy.advance_days(2, "test")
	var other := _make_offer("clear_compound", "compound_01")
	Contracts.server_accept(other, ContractGen.default_terms())
	Contracts.server_start_deployment([other])
	Contracts.objectives.server_set_state(Contracts.objectives.list[0].oid, Objectives.DONE)
	var econ: Dictionary = Economy.state().duplicate(true)
	var held: Array = Contracts.held().duplicate(true)
	var board_ids: Array = Contracts.board().map(func(o: Dictionary) -> String: return o.cid)
	var objectives: Array = Contracts.objectives.list.duplicate(true)
	Campaign.save_campaign()
	Contracts.objectives.server_clear()
	check(Campaign.load_campaign(), "the save loads")
	check(Economy.cash() == int(econ.cash) and Economy.day() == 3 and Economy.reputation("salvage_union") == 7 and Economy.loans_owed() == int(econ.loans[0].left)
		and typeof(Economy.state().cash) == TYPE_INT, "economy back: cash $%d, day %d, reputation, the loan" % [Economy.cash(), Economy.day()])
	var held_after := Contracts.held()
	check(held_after.size() == 2 and held_after[0].cid == cid and held_after[0].state == "accepted" and is_equal_approx(float(held_after[0].deal.salvage_share), 0.2)
		and int(held_after[0].deal.advance) == int(held[0].deal.advance) and held_after[1].state == "deployed", "held contracts back with their terms")
	check(Contracts.board().map(func(o: Dictionary) -> String: return o.cid) == board_ids, "the board back")
	var states := func(list: Array) -> Array: return list.map(func(o: Dictionary) -> String: return "%s=%s" % [o.oid, o.state])
	check(Contracts.is_deployed() and states.call(Contracts.objectives.list) == states.call(objectives) and Contracts.objectives.list[0].state == "done",
		"the deployment under way and its objectives back (one done)")
	# The normal first-access path: a fresh start that loads the save through ensure_campaign.
	Contracts.objectives.server_clear()
	Campaign._sections = {}
	Contracts._tried_load = false
	Contracts.ensure_campaign()
	check(Contracts.is_deployed() and Economy.cash() == int(econ.cash) and states.call(Contracts.objectives.list) == states.call(objectives)
		and Contracts.objectives.list[0].state == "done", "loaded on first access (ensure_campaign): the deployment and its objectives back")
	# Audit A1-02: with the save itself gone, first access still loads its backup.
	var path := Campaign.save_path()
	var saved := FileAccess.get_file_as_string(path)
	Campaign.reset_campaign()
	_write_file(GameState.backup_path(path), saved)
	Contracts.objectives.server_clear()
	Contracts._tried_load = false
	Contracts.ensure_campaign()
	check(Contracts.is_deployed() and Economy.cash() == int(econ.cash) and states.call(Contracts.objectives.list) == states.call(objectives),
		"with the save gone, first access loads its backup")
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()
	# Audit A1-01: nothing readable on first access: the save and the campaign's zones are kept
	# aside, a fresh campaign starts, and the host is told.
	Campaign.reset_campaign()
	_write_file(path, "{broken")
	var zone_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id("old_zone")]
	_write_file(zone_path, "{}")
	var notes: Array = []
	var on_notice := func(text: String) -> void: notes.append(text)
	Contracts.notice.connect(on_notice)
	Contracts.objectives.server_clear()
	Contracts._tried_load = false
	Contracts.ensure_campaign()
	Contracts.notice.disconnect(on_notice)
	var kept := GameState.kept_copies(path)
	var zone_kept := GameState.kept_copies(zone_path)
	check(kept.size() == 1 and zone_kept.size() == 1 and not GameState.has_save(zone_path) and not Contracts.is_deployed() and not Contracts.board().is_empty()
		and notes.any(func(n: String) -> bool: return n.contains("couldn't be read")),
		"an unreadable save on first access: kept aside with its zones (%s, %s), a fresh campaign, the host told" % [", ".join(kept), ", ".join(zone_kept)])
	for f in kept:
		DirAccess.remove_absolute("%s/%s" % [Campaign.SAVE_DIR, f])
	for f in zone_kept:
		DirAccess.remove_absolute("%s/%s" % [GameState.SAVE_DIR, f])


func _write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_shop() -> void:
	print("The shop")
	Contracts.new_full_campaign(51, 20000)
	Economy.take_unbanked()
	check(Prices.price_of(&"m4a1") == 1400 and Prices.price_of(&"frag_grenade") == 90 and Prices.for_sale(&"ifak") and not Prices.for_sale(&"hvt_case"),
		"prices from data/prices.json; objective items aren't for sale")
	check(Economy.server_buy(&"m4a1", 2) and Economy.cash() == 20000 - 2800, "two M4s: -$2,800")
	var inbox := Economy.take_unbanked()
	check(inbox.size() == 1 and inbox[0].id == "m4a1" and inbox[0].count == 2 and Economy.take_unbanked().is_empty(), "with no armory they wait in the base inbox")
	var sunk: Array = []
	Economy.purchase_sink = func(id: StringName, count: int, peer: int) -> bool:
		sunk.append([id, count, peer])
		return true
	check(Economy.server_buy(&"tourniquet", 3) and sunk == [[&"tourniquet", 3, 1]] and Economy.take_unbanked().is_empty(), "the base agent's armory takes purchases (purchase_sink)")
	Economy.purchase_sink = Callable()
	check(not Economy.server_buy(&"hvt_case") and not Economy.server_buy(&"defibrillator", 10), "no buying what isn't sold or what the company can't afford")
	var state := {"integrity": 0.5, "chips": [[0, 0, 0], [1, 1, 1]]}
	check(Prices.repair_cost(&"plate_ceramic_l4", state) == 384 and Prices.repair_cost(&"plate_ceramic_l4", {}) == 0, "repairing a half-broken plate costs $384")
	var cash := Economy.cash()
	var fixed := Economy.server_repair(&"plate_ceramic_l4", state)
	check(fixed == ItemDB.get_item(&"plate_ceramic_l4").default_state() and Economy.cash() == cash - 384, "repaired, as new")
	check(Prices.sell_price(&"m4a1") == 560 and Economy.server_sell(&"m4a1") == 560, "selling back fetches 40%")
	# Wave 6 call #1: allied quartermasters. Neutral: the base shop's prices, no heavy armour.
	var us0 := Economy.reputation("us_forces")
	var uk0 := Economy.reputation("uk_forces")
	check(Quartermaster.price(&"m4a1") == 1400 and not Quartermaster.sells(&"plate_carrier_heavy") and not Prices.for_sale(&"plate_carrier_heavy")
		and not &"plate_carrier_heavy" in Quartermaster.catalog(), "Neutral with the allies: list prices, and no heavy armour anywhere")
	check(Quartermaster.vehicle_deals().is_empty(), "and no vehicles for sale")
	Economy.change_reputation("us_forces", 35 - Economy.reputation("us_forces"), "test", false)
	var deals := Quartermaster.vehicle_deals()
	check(deals.size() == 1 and String(deals[0].model) == "matv" and int(deals[0].price) == roundi(Quartermaster.vehicle_price("matv") * 0.85),
		"Trusted with the US: an M-ATV for the motor pool, 15%% off ($%d)" % (int(deals[0].price) if not deals.is_empty() else -1))
	check(Quartermaster.price(&"m4a1") == 1190 and Quartermaster.seller_text(&"m4a1").begins_with("US Forces, Trusted -15")
		and Quartermaster.price(&"l85a2") == 1500 and not Quartermaster.sells(&"plate_carrier_heavy"),
		"Trusted with the US: its kit 15%% off (M4 $%d, %s), not the UK's rifle, and still no heavy armour" % [Quartermaster.price(&"m4a1"), Quartermaster.seller_text(&"m4a1")])
	Economy.change_reputation("us_forces", 75 - Economy.reputation("us_forces"), "test", false)
	cash = Economy.cash()
	check(Quartermaster.price(&"m4a1") == 1050 and Quartermaster.sells(&"plate_carrier_heavy") and &"plate_carrier_heavy" in Quartermaster.catalog()
		and Quartermaster.price(&"plate_carrier_heavy") == 1200 and BaseEconomy.item_price(&"plate_carrier_heavy") == 1200,
		"Allied: 25%% off, and the heavy carrier is for sale from its quartermaster ($%d)" % Quartermaster.price(&"plate_carrier_heavy"))
	check(Economy.server_buy(&"plate_carrier_heavy", 1) and Economy.cash() == cash - 1200, "and buying it charges the quartermaster's price")
	var models := Quartermaster.vehicle_deals().map(func(d: Dictionary) -> String: return String(d.model))
	check(models == ["matv", "maxxpro"], "Allied: the MaxxPro too (%s)" % [models])
	Economy.take_unbanked()
	Economy.change_reputation("us_forces", us0 - Economy.reputation("us_forces"), "test cleanup", false)
	Economy.change_reputation("uk_forces", uk0 - Economy.reputation("uk_forces"), "test cleanup", false)
	# Wave 6, contraband: never in the shop; the shady fixer pays full price and likes it; sold at
	# the base it fetches the usual share and lawful employers think less of the company.
	check(Fixers.is_contraband(&"captagon") and not Prices.for_sale(&"captagon") and not Quartermaster.sells(&"captagon") and not Fixers.is_contraband(&"gold_bars"),
		"contraband isn't sold anywhere")
	var su0 := Economy.reputation("salvage_union")
	var mer0 := Economy.reputation("meridian")
	var fixer := Fixers.buyer()
	check(String(fixer.get("fixer", "")) == "Mama Rook" and Fixers.offer(&"captagon") == Prices.price_of(&"captagon"), "Mama Rook buys it at full price ($%d)" % Fixers.offer(&"captagon"))
	BaseArmory.add(BaseHub.stash(), &"captagon", 2)
	cash = Economy.cash()
	check(Fixers.server_sell(&"captagon", 1) == Prices.price_of(&"captagon") and Economy.cash() == cash + Prices.price_of(&"captagon")
		and Economy.reputation("salvage_union") == su0 + 1 and int(BaseArmory.counts(BaseHub.stash()).get("captagon", 0)) == 1,
		"sold to her: paid in full, the Salvage Union thinks better of us, one left in the stash")
	check(BaseHub.server_sell_from_stash(&"captagon", 1) == Prices.sell_price(&"captagon") and Economy.reputation("meridian") == mer0 - 1,
		"sold at the base: %d%%, and Meridian (lawful) thinks less of us" % roundi(Prices.data().sell_ratio * 100.0))
	Economy.change_reputation("salvage_union", -40 - Economy.reputation("salvage_union"), "test", false)
	check(Fixers.buyer().is_empty() and Fixers.offer(&"captagon") == 0, "with the Salvage Union against us, nobody buys it")
	Economy.change_reputation("salvage_union", su0 - Economy.reputation("salvage_union"), "test cleanup", false)
	Economy.change_reputation("meridian", mer0 - Economy.reputation("meridian"), "test cleanup", false)
	for fid: String in ["us_forces", "uk_forces", "ca_forces"]:
		Economy.change_reputation(fid, ({"us_forces": us0, "uk_forces": uk0}.get(fid, Economy.reputation(fid) + 1) as int) - Economy.reputation(fid), "test cleanup", false)
	# Every item in data/items.json has a price of its own; CPR (an action, not an item) isn't sold.
	var unpriced: Array = ItemDB.all_ids().filter(func(id: StringName) -> bool: return not (Prices.data().items as Dictionary).has(String(id)))
	check(unpriced.is_empty() and Prices.price_of(&"io_kit") == 150 and Prices.price_of(&"surgery_kit_5") == 900
		and Prices.for_sale(&"pouch_mag_double") and Prices.for_sale(&"radio") and not Prices.for_sale(&"cpr"),
		"every item priced (unpriced: %s); pouches, radio and kits sold, CPR not" % [unpriced])
	# A carrier's MOLLE pouches and their contents are report entries of their own.
	var inv := Inventory.new()
	check(inv.take(&"plate_carrier") == 1 and inv.take(&"pouch_mag_double") == 1 and not inv.attachment(&"mag_1").is_empty()
		and inv.take(&"mag_556", 2) == 2 and inv.units_in(Inventory.pouch_container(&"mag_1")) == 2, "a mag pouch on a carrier, two mags in it")
	var flat := Contracts.inventory_items(inv)
	var ids: Array = flat.map(func(e: Dictionary) -> String: return e.id)
	var mags: int = flat.filter(func(e: Dictionary) -> bool: return e.id == "mag_556").reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var carrier: Array = flat.filter(func(e: Dictionary) -> bool: return e.id == "plate_carrier")
	check(ids.count("pouch_mag_double") == 1 and mags == 2 and carrier.size() == 1 and not (carrier[0].state as Dictionary).has("molle"),
		"the report lists the carrier, its pouch and the mags in it once each (%s)" % [ids])
	inv.free()
	var cid := _make_offer("raid", "compound_01")
	Contracts.server_accept(cid, {"pay_points": 0, "salvage_points": 0, "support_points": 1, "advance_share": 0.3})
	cash = Economy.cash()
	var budget := Contracts.support_left(cid)
	check(Economy.server_pay_support("resupply", cid) and Economy.server_pay_support("extraction", cid) and Contracts.support_left(cid) == 0
		and Economy.cash() == cash - (Prices.support_price("resupply") + Prices.support_price("extraction") - budget),
		"a resupply and an extraction: the $%d support budget first, the rest from cash" % budget)


func _test_intel_and_salvage() -> void:
	print("Intel, leads and salvage picks")
	Contracts.new_full_campaign(61, 100000)
	Economy.take_unbanked()
	var cid := _make_offer("intel_grab", "harbour_yard")
	Contracts.server_accept(cid, {"pay_points": 0, "salvage_points": 4, "support_points": 0, "advance_share": 0.3})
	Contracts.server_start_deployment([cid])
	var cash := Economy.cash()
	var d := Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 1}],
		"field_items": [{"id": "m4a1", "count": 1}, {"id": "rounds_556", "count": 30}], "extracted": ["You"]})
	var deal: Dictionary = Contracts.history().back()
	check(d.contracts[0].outcome == "completed" and Economy.cash() == cash + int(d.totals.paid_now) - _paid_at_debrief(d) and int(d.totals.paid_now) > 0,
		"the case carried out completes the contract and pays ($%d)" % int(d.totals.paid_now))
	check(d.salvage.budget == floori(1430 * 0.5) and Contracts.server_pick_salvage(1) and not Contracts.server_pick_salvage(0) and d.salvage.spent == 30,
		"a 50%% share of $1,430 in the field: the rounds can be claimed, the rifle can't")
	check(d.intel.size() == 1 and d.intel[0].status == "pending", "the case is intel to decide on")
	var buyer := "salvage_union" if String(d.contracts[0].employer) != "salvage_union" else "meridian"
	var client := String(d.contracts[0].employer)
	var client_rep := Economy.reputation(client)
	var buyer_rep := Economy.reputation(buyer)
	cash = Economy.cash()
	check(Contracts.server_sell_intel(0, client) != "", "intel can't be sold to the client")
	var worth := Prices.intel_sale_value(&"hvt_case")
	check(Contracts.server_sell_intel(0, buyer) == "" and worth == 3000 and Economy.cash() == cash + worth and Economy.reputation(buyer) == buyer_rep + 2
		and Economy.reputation(client) == client_rep + (-8 if d.intel[0].caught else 0),
		"sold to %s for its worth, $%d (was a flat $6,000; the client %s)" % [buyer, worth, "found out: -8" if d.intel[0].caught else "never knew"])
	check(DebriefCalc.money_in(d).any(func(l: Dictionary) -> bool: return l.what == "Intel sold" and int(l.amount) == worth)
		and DebriefCalc.money_in(d).any(func(l: Dictionary) -> bool: return l.what == "Completion pay" and int(l.amount) == int(d.totals.completion)),
		"the debrief says where the money came from: completion pay, intel sold")
	Contracts.server_finish_debrief()
	var inbox := Economy.take_unbanked()
	check(not inbox.any(func(e: Dictionary) -> bool: return e.id == "hvt_case") and inbox.any(func(e: Dictionary) -> bool: return e.id == "rounds_556" and e.count == 30)
		and not inbox.any(func(e: Dictionary) -> bool: return e.id == "m4a1") and d.finished,
		"closing the debrief banks what was carried out and the salvage picked, but not the intel sold (it was handed over)")
	check(Prices.sell_price(&"intel_laptop") == 0 and Prices.sell_price(&"hvt_case") == 0, "the shop never buys intel")
	check(deal.outcome == "completed", "the contract closed as completed")
	# Turning intel in opens leads.
	var second := _make_offer("intel_grab", "compound_01")
	Contracts.server_accept(second, ContractGen.default_terms())
	Contracts.server_start_deployment([second])
	Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 2}]})
	var leads_before := Contracts.board().filter(func(o: Dictionary) -> bool: return o.source == "lead").size()
	check(Contracts.server_turn_in_intel(0) == "", "intel turned in")
	var leads := Contracts.board().filter(func(o: Dictionary) -> bool: return o.source == "lead")
	check(leads.size() == leads_before + 2 and String(leads.back().title).begins_with("Lead:") and float(leads.back().intel_accuracy) >= 0.8,
		"two pieces open two leads on the board, with good intel (%s)" % [leads.map(func(o: Dictionary) -> String: return o.title)])
	Contracts.server_finish_debrief()
	# Economy overhaul 2026-10-20: a piece is debriefed once (kept and carried out again, it's worth nothing), and
	# intel left in the field isn't salvage.
	var piece := {"id": "intel_laptop", "count": 1, "state": {"intel_id": "test_laptop_1"}}
	for round_no in 2:
		var again := _make_offer("raid", "compound_01")
		Contracts.server_accept(again, ContractGen.default_terms())
		Contracts.server_start_deployment([again])
		var dd := Contracts.server_end_deployment({"items": [piece.duplicate(true)], "field_items": [{"id": "intel_phone", "count": 1}], "extracted": ["You"]})
		if round_no == 0:
			check(dd.intel.size() == 1 and int(dd.get("intel_repeats", 0)) == 0 and (dd.salvage.pool as Array).is_empty(),
				"a laptop carried out is intel to decide on; a phone left in the field isn't in the salvage pool")
		else:
			check(dd.intel.is_empty() and int(dd.get("intel_repeats", 0)) == 1, "the same laptop carried out again: already handed over, worth nothing")
		Contracts.server_finish_debrief()


## B-18: every contract debriefed "failed". What else came out at extraction (BaseHub's
## "bank": items set down in the point, a helicopter's hold, bodies carried in) never counted
## for "carry it out" objectives, only what the people still held: an intel grab whose laptop
## was set down at the point failed, as did an HVT capture's phone bonus.
func _test_set_down_at_the_point() -> void:
	print("Carried out but set down at the point (B-18)")
	Contracts.new_full_campaign(62, 100000)
	Economy.take_unbanked()
	var cid := _make_offer("intel_grab", "harbour_yard")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	var bank := _out_entries(cid)
	check(bank.size() == 2, "the intel grab wants two things carried out (%d)" % bank.size())
	var d := Contracts.server_end_deployment({"items": [{"id": "m4a1", "count": 1}], "bank": bank, "extracted": ["You"]})
	var line: Dictionary = d.contracts[0]
	check(line.outcome == "completed" and (line.bonuses as Array).any(func(b: Dictionary) -> bool: return String(b.text).contains("too")),
		"the intel and the bonus documents set down at the point complete the contract with its bonus (%s, %s)" % [line.outcome, line.objectives])
	check(d.intel.size() >= 1, "what was set down shows as intel in the debrief")
	Contracts.server_finish_debrief()
	# The HVT capture: the HVT delivered, his phone (the bonus) set down at the point.
	var hvt_cid := _make_offer("hvt_capture", "harbour_yard")
	Contracts.server_accept(hvt_cid, ContractGen.default_terms())
	Contracts.server_start_deployment([hvt_cid])
	var hvt_id := ""
	for o: Dictionary in Contracts.objectives.list:
		if o.cid == hvt_cid and o.kind == Objectives.DELIVER_HVT:
			hvt_id = String(o.params.get("hvt", ""))
	var phone := _out_entries(hvt_cid)
	d = Contracts.server_end_deployment({"items": [], "bank": phone, "hvts": [{"hvt": hvt_id, "alive": true}], "extracted": ["You"]})
	line = d.contracts[0]
	check(hvt_id != "" and phone.size() == 1 and line.outcome == "completed" and not (line.bonuses as Array).filter(func(b: Dictionary) -> bool: return String(b.text).contains("phone")).is_empty(),
		"the HVT delivered and his phone set down at the point: completed with the bonus (%s, %s)" % [line.outcome, line.objectives])
	Contracts.server_finish_debrief()
	# Nothing done is still a failure (the soaks' bots never take the objective).
	var idle := _make_offer("intel_grab", "compound_01")
	Contracts.server_accept(idle, ContractGen.default_terms())
	Contracts.server_start_deployment([idle])
	d = Contracts.server_end_deployment({"items": [{"id": "m4a1", "count": 1}], "bank": [{"id": "rounds_556", "count": 30}], "extracted": ["You"]})
	check(d.contracts[0].outcome == "failed", "extracting without the intel is still a failure (%s)" % d.contracts[0].outcome)
	Contracts.server_finish_debrief()


## The death benefit in a campaign (cghath's list, 2026-10-20; Fallen): each man's is paid when
## his death is confirmed (BaseHub.server_pay_death_benefit: his tags came out), during the run,
## so the debrief lists it as a line of its own and doesn't charge it again; the books call it a
## death benefit. A report without the roster (the board alone) still counts the dead.
func _test_death_benefit() -> void:
	print("The death benefit: once per man, a line of its own in the debrief")
	Contracts.new_full_campaign(63, 100000)
	Economy.take_unbanked()
	Economy.take_run_expenses()
	var benefit := Prices.operations("kia_benefit")
	var cid := _make_offer("intel_grab", "harbour_yard")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	var cash := Economy.cash()
	Economy.charge_run(benefit, "Death benefit: Reaper (killed in action, tags recovered)")
	check(Economy.cash() == cash - benefit and Economy.ledger_kind(String(Economy.ledger()[-1].what)) == "Death benefits",
		"paid when his tags came out: -$%s, in the books as a death benefit" % DebriefCalc.money(benefit))
	var casualties := [{"name": "Okafor", "status": "kia", "injury": "killed, tags recovered", "tags": Fallen.RECOVERED},
		{"name": "Brandt", "status": "mia", "injury": "fell, tags not brought out", "tags": Fallen.MISSING}]
	var d := Contracts.server_end_deployment({"items": [], "extracted": ["You"], "casualties": casualties, "benefits_paid": true})
	var lines: Array = (d.get("expenses", []) as Array).filter(func(l: Dictionary) -> bool: return String(l.what).begins_with("Death benefit"))
	check(lines.size() == 1 and int(lines[0].amount) == benefit and not bool(lines[0].charge) and String(lines[0].what).contains("Reaper"),
		"the debrief lists it once, as its own line, already paid (%s)" % [lines])
	check(Array(DebriefCalc.summary(d)).has("Expense: Death benefit: Reaper (killed in action, tags recovered): -$%s" % DebriefCalc.money(benefit)),
		"and the debrief's lines say so")
	check(_ledger_count("Death benefit") == 1, "one death benefit in the books after the debrief, not two")
	Contracts.server_finish_debrief()
	var counted := DebriefCalc.expenses({"casualties": [{"name": "D", "status": "kia"}, {"name": "E", "status": "kia"}]}, 1, [])
	var counted_lines: Array = (counted.lines as Array).filter(func(l: Dictionary) -> bool: return String(l.what).begins_with("Death benefit"))
	check(counted_lines.size() == 1 and String(counted_lines[0].what) == "Death benefit (2 KIA)" and int(counted_lines[0].amount) == 2 * benefit and bool(counted_lines[0].charge),
		"without the roster's word the dead are counted, charged at the debrief (%s)" % [counted_lines])


func _ledger_count(prefix: String) -> int:
	return Economy.ledger().filter(func(e: Dictionary) -> bool: return String(e.get("what", "")).begins_with(prefix)).size()


## One entry per "carry it out" objective of contract `cid`: its item, as the mission placed it.
func _out_entries(cid: String) -> Array:
	var out: Array = []
	for o: Dictionary in Contracts.objectives.list:
		if o.cid != cid or o.kind != Objectives.EXTRACT_ITEM:
			continue
		var items: Array = o.params.get("items", [])
		var ids: Array = o.params.get("intel_ids", [])
		var entry := {"id": String(items[0]) if not items.is_empty() else "hvt_case", "count": 1, "state": {}}
		if not ids.is_empty():
			entry.state["intel_id"] = String(ids[0])
		out.append(entry)
	return out


## B-18 (review): what goes home in a motor-pool vehicle's hold came out too. The hard case
## loaded into the M-ATV's hold from the player's hands (Vehicle.server_load) and the bonus
## documents in a pack stowed beside it, the squad extracting next to it: Extraction's report
## lists both as driven out (not deposited, so not banked), the M-ATV goes home with them aboard
## (MotorPoolNode.server_settle) and the debrief counts them: completed with the bonus, where it
## debriefed "failed". Extracting out of its reach, its hold doesn't count.
func _test_driven_out() -> void:
	print("Driven out in a motor-pool vehicle's hold (B-18)")
	Contracts.new_full_campaign(84, 200000)
	Economy.take_unbanked()
	Campaign.section(MotorPool.SECTION).clear()
	var pool_id := String(MotorPool.list()[0].id)
	var cid := _make_offer("intel_grab", "compound_01")
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([cid])
	var docs: Array = _out_entries(cid).filter(func(e: Dictionary) -> bool: return e.id == "intel_documents")
	var ext := MapNodes.extraction(level)
	ext.server_begin({"zone": Briefing.DEBUG_ZONE})
	var lz: Vector2 = ext.points[0].pos if not ext.points.is_empty() else Vector2(0, 34)
	var v := MotorPool.server_bring(pool_id, level, Transform3D(Basis(), Vector3(lz.x + 7.0, 0.3, lz.y)))
	await _frames(3)
	if v == null:
		check(false, "the pool's M-ATV is brought into the level")
		ext.server_cancel()
		Contracts.server_end_deployment({})
		Contracts.server_finish_debrief()
		return
	player.inventory.release_hands()
	player.inventory.take(&"hvt_case")
	var said := v.server_load(player, &"", -1, &"hvt_case")
	v.cargo_hold.take(&"assault_pack", 1, {"held": [{"id": "intel_documents", "count": 1, "state": docs[0].state if not docs.is_empty() else {}}]})
	check(said.begins_with("Loaded") and player.inventory.hands == &"" and v.cargo_hold.count_of(&"hvt_case") == 1 and v.cargo_hold.count_of(&"assault_pack") == 1
		and docs.size() == 1, "the hard case loaded into the M-ATV's hold from the hands (%s), the documents in a pack beside it" % said)
	var far := ext.build_report({"name": "far", "pos": lz + Vector2(300, 0)})
	check((far.get("driven_out", [0]) as Array).is_empty(), "extracting out of its reach: nothing in its hold is out")
	player.global_position = Vector3(lz.x, 0.1, lz.y)
	var report := {}
	ext.deployment_ended.connect(func(r: Dictionary) -> void: report.merge(r, true), CONNECT_ONE_SHOT)
	ext.countdown_s = 0.3
	var why := ext.server_confirm()
	await _wait_for(func() -> bool: return not report.is_empty(), 5.0)
	var driven: Array = report.get("driven_out", [])
	var ids := driven.map(func(e: Dictionary) -> String: return String(e.id))
	check(why == "" and "hvt_case" in ids and "assault_pack" in ids and driven.all(func(e: Dictionary) -> bool: return e.get("where") == "vehicle")
		and not (report.get("deposited", []) as Array).any(func(e: Dictionary) -> bool: return String(e.id) == "hvt_case"),
		"extracted beside it: the report lists its hold as driven out, not deposited (%s; %s)" % [why, ids])
	await _frames(2)
	var aboard: Array = []
	for list: Variant in (((MotorPool.entry(pool_id).get("record", {}) as Dictionary).get("cargo", {}) as Dictionary).get("containers", {}) as Dictionary).values():
		for e: Dictionary in list:
			aboard.append(String(e.id))
	check(String(MotorPool.entry(pool_id).get("out", "?")) == "" and (not is_instance_valid(v) or v.is_queued_for_deletion()) and "hvt_case" in aboard,
		"the M-ATV goes home with the case aboard (%s)" % [aboard])
	# The debrief, from the report as BaseHub builds it (the people bring their own gear home).
	var debrief_report := Contracts.report_from_level(level, [player])
	debrief_report["bank"] = []
	debrief_report["driven_out"] = driven
	var d := Contracts.server_end_deployment(debrief_report)
	var line: Dictionary = d.contracts[0] if not (d.get("contracts", []) as Array).is_empty() else {"outcome": "missing", "bonuses": [], "objectives": []}
	check(line.outcome == "completed" and (line.bonuses as Array).any(func(b: Dictionary) -> bool: return String(b.text).contains("too")),
		"the case and the documents driven out complete the intel grab with its bonus (%s, %s)" % [line.outcome, line.objectives])
	var intel := (d.get("intel", []) as Array).map(func(e: Dictionary) -> String: return String(e.id))
	var banked := Economy.take_unbanked().map(func(e: Dictionary) -> String: return String(e.id))
	check("hvt_case" in intel and "intel_documents" in intel and "hvt_case" not in banked and "intel_documents" not in banked,
		"they show as intel in the debrief and aren't banked as well: they stay in the M-ATV (intel %s, banked %s)" % [intel, banked])
	Contracts.server_finish_debrief()
	ext.server_cancel()


func _test_board_ui() -> void:
	print("Board, shop and debrief screens (host)")
	Contracts.new_full_campaign(71, 100000)
	var board := Contracts.open_board()
	await _frames(2)
	check(board.offer_count() == Contracts.board().size() and board.header_text().contains("Cash $100,000") and board.header_text().contains("Day 1"),
		"the board lists every offer, with cash and the day")
	board.select_offer(1)
	var cid: String = Contracts.board()[1].cid
	board.set_terms({"pay_points": 1, "salvage_points": 1, "support_points": 0, "advance_share": 0.3})
	board.accept_selected()
	await _frames(2)
	check(board.held_count() == 1 and Contracts.contract(cid).state == "accepted" and board.offer_count() == Contracts.board().size(),
		"accepting from the board signs the contract")
	# Esc closes the top-most screen only: the shop over the board first, then the board
	# (docs/ui_audit.md P0-4: Esc fell through the shop and closed the board under it).
	var over := board.open_shop()
	await _frames(1)
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	get_viewport().push_input(esc)
	await _frames(2)
	check(not is_instance_valid(over) and is_instance_valid(board) and not board.is_queued_for_deletion(),
		"Esc closes the shop opened over the board, not the board")
	get_viewport().push_input(esc)
	await _frames(2)
	check(not is_instance_valid(board), "a second Esc closes the board")
	var shop := ShopScreen.new()
	add_child(shop)
	await _frames(1)
	check(&"m4a1" in shop.listed() and not &"hvt_case" in shop.listed(), "the shop lists what's for sale")
	var cash := Economy.cash()
	shop.select(&"ifak")
	shop.buy_selected()
	check(Economy.cash() == cash - Prices.price_of(&"ifak"), "buying from the shop screen")
	shop.close()
	Contracts.server_start_deployment([cid])
	Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 1}], "field_items": [{"id": "rounds_556", "count": 10}],
		"casualties": [{"name": "Charlie", "status": "wounded", "injury": "Broken leg"}]})
	var screen := Contracts.show_debrief()
	await _frames(2)
	var text := screen.text()
	check(text.contains("DEBRIEF") and text.contains("Paid now") and text.contains("SALVAGE") and text.contains("Charlie (WOUNDED: Broken leg)") and text.contains("INTEL"),
		"the debrief screen shows pay, salvage, casualties and intel")
	screen.close()
	await _frames(1)
	check(Contracts.last_debrief().finished, "Continue on the host closes the debrief")


## Captain, 2026-10-14 (v0.3.1): "its hard to select the items you want". The debrief screen
## groups what came out and the salvage pool per item type; the sums must match the raw lists,
## claiming N of a type must stay in the budget (the host still checks each lot), and the panel
## must fit the screen at every resolution and UI scale.
func _test_debrief_screen() -> void:
	print("Debrief screen (grouped salvage, budget, fit)")
	Contracts.new_full_campaign(62, 100000)
	Economy.take_unbanked()
	var cid := _make_offer("intel_grab", "harbour_yard")
	Contracts.server_accept(cid, {"pay_points": 0, "salvage_points": 4, "support_points": 0, "advance_share": 0.3})
	Contracts.server_start_deployment([cid])
	var out_items := [{"id": "hvt_case", "count": 1}]
	for i in 6:  # what six soldiers carried, one entry each, as the Captain's screenshot had it
		out_items.append_array([{"id": "m4a1", "count": 1}, {"id": "m17", "count": 1}, {"id": "mag_556", "count": 3}, {"id": "ifak", "count": 1}, {"id": "frag_grenade", "count": 2}])
	var field := [{"id": "m4a1", "count": 1}, {"id": "m4a1", "count": 1}, {"id": "rounds_556", "count": 30}]
	for i in 4:
		field.append_array([{"id": "ifak", "count": 1}, {"id": "electronics_salvage", "count": 4}, {"id": "mag_556", "count": 3}])
	var d := Contracts.server_end_deployment({"items": out_items, "field_items": field, "extracted": ["You", "Alpha", "Bravo"]})
	var raw := {}
	for e: Dictionary in d.items_out:
		raw[String(e.id)] = int(raw.get(String(e.id), 0)) + int(e.get("count", 1))
	var grouped := DebriefCalc.group_items(d.items_out)
	var grouped_ok := grouped.size() == raw.size()
	for g: Dictionary in grouped:
		grouped_ok = grouped_ok and int(raw.get(g.id, -1)) == int(g.count) and g.category in DebriefCalc.CATEGORIES
	check(grouped_ok and grouped.filter(func(g: Dictionary) -> bool: return g.id == "m4a1")[0].count == 6
		and grouped.filter(func(g: Dictionary) -> bool: return g.id == "m4a1")[0].category == "weapons"
		and grouped.filter(func(g: Dictionary) -> bool: return g.id == "frag_grenade")[0].category == "grenades",
		"what was carried out, summed per item type, adds up to the raw list (%d kinds)" % grouped.size())
	var pool: Array = d.salvage.pool
	var groups := DebriefCalc.salvage_groups(d)
	var lots: Array = []
	var count := 0
	var value := 0
	for g: Dictionary in groups:
		lots.append_array(g.lots)
		count += int(g.count)
		value += int(g.value)
	lots.sort()
	check(lots == range(pool.size()) and value == int(d.salvage.pool_value) and count == pool.reduce(func(acc: int, e: Dictionary) -> int: return acc + int(e.count), 0)
		and groups.size() == 5 and int(groups[0].value) >= int(groups[-1].value),
		"the salvage pool, one row per item type: every lot once, counts and values add up, sorted by value")
	var budget := int(d.salvage.budget)
	var three := DebriefCalc.picks_for(d, "mag_556", 3)
	var took := three.all(func(i: int) -> bool: return Contracts.server_pick_salvage(i))
	check(three.size() == 3 and took and int(d.salvage.spent) <= budget and DebriefCalc.salvage_groups(d).filter(func(g: Dictionary) -> bool: return g.id == "mag_556")[0].picked.size() == 3,
		"claiming three lots of magazines: the host takes them all, $%s of $%s" % [DebriefCalc.money(d.salvage.spent), DebriefCalc.money(budget)])
	var most := DebriefCalc.picks_for(d, "electronics_salvage", -1)
	took = most.all(func(i: int) -> bool: return Contracts.server_pick_salvage(i))
	check(took and int(d.salvage.spent) <= budget and (DebriefCalc.picks_for(d, "electronics_salvage", 1).is_empty()),
		"claiming as many electronics as fit stays in the budget ($%s of $%s)" % [DebriefCalc.money(d.salvage.spent), DebriefCalc.money(budget)])
	var best := DebriefCalc.best_value_picks(d)
	took = best.all(func(i: int) -> bool: return Contracts.server_pick_salvage(i))
	var left := budget - int(d.salvage.spent)
	var any_fits := false
	for i in pool.size():
		any_fits = any_fits or (not i in d.salvage.picked and int(pool[i].value) <= left)
	check(took and int(d.salvage.spent) <= budget and not any_fits, "claim best value fills the budget: nothing else fits ($%s left)" % DebriefCalc.money(left))
	var blocked := groups.filter(func(g: Dictionary) -> bool: return (g.picked as Array).size() < (g.lots as Array).size() and DebriefCalc.pick_block_reason(d, g.id) != "")
	check(DebriefCalc.pick_block_reason(d, "m4a1").begins_with("Over budget") or DebriefCalc.pick_block_reason(d, "m4a1") == "All of it is claimed",
		"a row that won't fit says why (%d rows blocked)" % blocked.size())
	var spent := int(d.salvage.spent)
	var back := DebriefCalc.unpicks_for(d, "mag_556", 1)
	check(back.size() == 1 and Contracts.server_unpick_salvage(back[0]) and int(d.salvage.spent) == spent - int(pool[back[0]].value)
		and DebriefCalc.picks_for(d, "mag_556", 1) == back, "returning one lot gives its value back, and it can be claimed again")
	var screen := Contracts.show_debrief()
	await _frames(2)
	var text := screen.text()
	check(text.contains("CARRIED OUT") and text.contains("6 x M4A1") and text.contains("Claimed / qty") and text.contains("Paid now") and text.contains("SALVAGE"),
		"the screen shows the grouped carry-out and the salvage table")
	var name_rows := 0
	for node in screen.panel().find_children("*", "Label", true, false):
		if (node as Label).text == DebriefCalc.item_name("ifak"):
			name_rows += 1
	check(name_rows == 1, "one salvage row for the four IFAK lots (%d)" % name_rows)
	var bad := PackedStringArray()
	for res: Vector2 in [Vector2(1280, 720), Vector2(1366, 768), Vector2(1600, 900), Vector2(1920, 1080), Vector2(1920, 1200),
			Vector2(2000, 1250), Vector2(2560, 1440), Vector2(2560, 1600), Vector2(3440, 1440), Vector2(3840, 2160)]:
		for scale: float in [0.75, 1.0, 1.5]:
			var view := res / scale
			screen.fit(view)
			var rect := screen.panel().get_rect()
			if not Rect2(Vector2.ZERO, view).encloses(rect) or rect.size.x < 600.0 or rect.size.y < 400.0:
				bad.append("%dx%d@%.2f: %s" % [res.x, res.y, scale, rect])
	check(bad.is_empty(), "the debrief panel fits inside the screen at 10 resolutions and 3 UI scales%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	screen.close()
	await _frames(1)


# --- Live objectives in the level --------------------------------------------------------------

func _test_live_objectives() -> void:
	print("Objectives in the level (hot zone, three contracts)")
	var site := MissionRegistry.site("compound", "cache")
	var site_box := Objectives._box_of({"params": site})
	await _wait_for(func() -> bool: return Objectives.solid_count(level.voxel_world, site_box) >= 0, 5.0)
	var pristine := Objectives.solid_count(level.voxel_world, site_box)
	check(pristine == int(site.voxels), "the cache site's authored voxel count matches the pristine crate stack (%d of %d)" % [pristine, int(site.voxels)])
	Contracts.new_full_campaign(81, 200000)
	var clear := _make_offer("clear_compound", "ridge_hot")
	var cache := _make_offer("raid", "ridge_hot")
	var hvt := _make_offer("hvt_capture", "ridge_hot")
	for cid: String in [clear, cache, hvt]:
		Contracts.server_accept(cid, ContractGen.default_terms())
	var h1 := _hostile("TestHostile1", Vector3(-6, 0.1, -14))
	var h2 := _hostile("TestHostile2", Vector3(8, 0.1, 0))
	check(Contracts.server_start_deployment([], "ridge_hot") == "" and Contracts.deployment().cids.size() == 3 and Contracts.objectives.list.size() == 6,
		"a hot zone deploys on all three contracts at once (6 objectives, 3 of them bonuses)")
	await _seconds(1.2)
	var clear_o: Dictionary = Contracts.objectives.for_contract(clear)[0]
	check(clear_o.state == "active" and clear_o.progress == "2 hostiles left", "clear the compound: 2 hostiles left")
	var panel := _panel()
	check(panel != null and panel.text().contains("OBJECTIVES") and panel.text().contains("[ ] Clear the compound of hostiles (2 hostiles left)"),
		"the HUD lists the objectives")
	check(Contracts.objectives.markers().size() == 6 and Contracts.objectives.markers()[0].pos is Vector3, "and the map gets markers")
	# Compact / full list and picking the active objective (feat/objective-list).
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_objlist_settings.cfg"))
	GameSettings.set_value("hud", "objectives_expanded", true)
	panel.refresh()
	check(panel.text().contains("-- ") and panel.text().contains("[O] compact") and panel.text().contains("> "), "full list: grouped by contract, the active one marked (%s)" % panel.text().replace("
", " | "))
	var full_lines := panel.text().count("
")
	panel.toggle_compact()
	check(panel.compact() and panel.text().count("
") == 2 and panel.text().contains("+5 more") and panel.text().contains("> [ ]"),
		"compact: the active objective on one line and '+5 more' (%s)" % panel.text().replace("
", " | "))
	check(panel.text().count("
") < full_lines, "compact is shorter than the full list")
	GameSettings.reload()
	check(not bool(GameSettings.get_value("hud", "objectives_expanded")), "the compact state persists in the settings file")
	var before := String(_helper().current.get("oid", ""))
	panel.cycle()
	var picked := Objectives.chosen_oid
	check(picked != "" and String(_helper().current.get("oid", "")) == picked and panel.active_oid() == picked and panel.text().contains(Objectives.line(Contracts.objectives.get_objective(picked))),
		"N picks an objective: the helper's step and the panel follow (auto was %s, now %s)" % [before, picked])
	check(_helper().current.targets.is_empty() or _helper().current.targets[0].label != "", "the marker target is the picked objective's")
	var after := ObjectiveHelper.next_choice(Contracts.objectives.list, picked)
	check(after != picked, "the next pick differs from the last")
	Objectives.chosen_oid = ""
	panel.toggle_compact()
	check(not panel.compact(), "O again expands it")
	GameSettings.set_value("hud", "objectives_expanded", true)
	GameSettings.use_file("")
	h1.vitals.server_kill()
	h2.vitals.server_kill()
	await _seconds(1.2)
	check(Contracts.objectives.for_contract(clear)[0].state == "done", "both down: cleared")
	Contracts.server_items_banked([{"id": "hvt_case", "count": 1}])
	check(Contracts.objectives.for_contract(clear)[1].state == "done", "the bonus case sent out mid-zone counts")
	Contracts.server_hvt_delivered(String(Contracts.objectives.for_contract(hvt)[0].params.hvt))
	check(Contracts.objectives.for_contract(hvt)[0].state == "done", "the HVT delivered (the people agent's call)")
	# A charge placed on the cache.
	var cache_o: Dictionary = Contracts.objectives.for_contract(cache)[0]
	player.inventory.take(&"plate_carrier")
	player.inventory.take(&"breaching_charge")
	player.global_position = Vector3(-12, 0.1, -20)
	check(not Contracts.objectives.server_place_charge(player, cache_o.oid), "too far from the cache to place a charge")
	player.global_position = Vector3(-12, 0.1, -8.5)
	check(Contracts.objectives.server_place_charge(player, cache_o.oid) and player.inventory.count_of(&"breaching_charge") == 0
		and Contracts.objectives.get_objective(cache_o.oid).state == "active", "charge set on the cache (it goes off in 5 s)")
	player.global_position = Vector3(0, 0.1, 30)
	await _seconds(MissionRegistry.setting_f("charge_fuse_s", 5.0) + 1.0)
	check(Contracts.objectives.get_objective(cache_o.oid).state == "done" and level.voxel_world.material_at(Vector3(-12.5, 0.5, -10.5)) == VoxelWorld.Mat.EMPTY,
		"the charge blew the cache apart: destroyed")
	# A cache destroyed by voxel damage alone (the shed's plank wall standing in, its count authored here).
	var wall := Objectives.solid_count(level.voxel_world, AABB(Vector3(16, 0, -11), Vector3(0.1, 2.4, 1.4)))
	Contracts.objectives.server_add([{"oid": "test_cache", "cid": "", "kind": "destroy_cache", "text": "Blow the shed wall", "state": "active", "optional": true,
		"bonus_share": 0.0, "progress": "", "params": {"box": [[16, 0, -11], [16.1, 2.4, -9.6]], "voxels": wall}, "pos": [16, 1, -10]}])
	await _seconds(0.8)
	check(Contracts.objectives.get_objective("test_cache").state == "active", "a voxel cache stands until it's blown")
	level.voxel_world.server_blast(Vector3(16.05, 1.2, -10.3), 1.6)
	await _seconds(1.2)
	check(Contracts.objectives.get_objective("test_cache").state == "done", "explosive damage that takes out most of its voxels destroys it")
	# An area nobody holds: it only counts as cleared once the arming time is up.
	var settings: Dictionary = MissionRegistry.data().settings
	var arm_s: Variant = settings.clear_arm_timeout_s
	settings.clear_arm_timeout_s = 1.5
	Contracts.objectives.server_add([{"oid": "test_empty", "cid": "", "kind": "clear_area", "text": "Clear the empty field", "state": "active", "optional": true,
		"bonus_share": 0.0, "progress": "", "params": {"rect": [60, 60, 10, 10]}, "pos": [65, 0, 65]}])
	await _seconds(1.0)
	check(Contracts.objectives.get_objective("test_empty").state == "active", "an empty area isn't cleared the moment it goes live (no enemy spawned yet)")
	await _seconds(1.6)
	check(Contracts.objectives.get_objective("test_empty").state == "done", "but is once the arming time passes with nobody there")
	settings.clear_arm_timeout_s = arm_s
	var cash := Economy.cash()
	var report := Contracts.report_from_level(level, [player])
	check(report.items.any(func(e: Dictionary) -> bool: return e.id == "plate_carrier") and report.field_items.any(func(e: Dictionary) -> bool: return e.id == "m4a1")
		and report.extracted.size() == 1 and report.casualties.is_empty(), "an extraction report from the level: what the player carries, what's left lying about")
	var d := Contracts.server_end_deployment(report)
	check(d.contracts.size() == 3 and d.contracts.all(func(l: Dictionary) -> bool: return l.outcome == "completed") and Economy.cash() == cash + int(d.totals.paid_now) - _paid_at_debrief(d)
		and int(d.salvage.pool_value) > 0, "all three completed and paid ($%d); salvage pool $%d" % [int(d.totals.paid_now), int(d.salvage.pool_value)])
	check(Contracts.objectives.list.is_empty() and (panel == null or panel.text() == ""), "after extraction the objective list clears")
	Contracts.server_finish_debrief()
	# The zone kept its damage: the next cache contract on this module finds the crates already blown.
	level.voxel_world.server_blast(site_box.get_center(), 1.6)  # whatever the charge left standing
	await _seconds(0.3)
	var carved := Objectives.solid_count(level.voxel_world, site_box)
	var again := _make_offer("raid", "compound_01")
	Contracts.server_accept(again, ContractGen.default_terms())
	Contracts.server_start_deployment([again])
	await _seconds(1.5)
	var again_o: Dictionary = Contracts.objectives.for_contract(again)[0]
	check(carved >= 0 and carved < int(site.voxels) * 0.4 and again_o.state == "active",
		"a cache site carved before deploying (%d of %d voxels left) doesn't count as destroyed by itself" % [carved, int(site.voxels)])
	Contracts.server_cache_destroyed("cache_compound")
	check(Contracts.objectives.get_objective(again_o.oid).state == "done", "the hook still completes it")
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()


# --- The HUD's objective helper and ammo readout ------------------------------------------------

func _test_objective_helper() -> void:
	print("Objective helper (HUD): what to do now, and the markers")
	var at := func(x: float, z: float) -> Vector3: return Vector3(x, 0.1, z)
	var step := func(list: Array, sit: Dictionary) -> String: return String(ObjectiveHelper.step_for(list, sit).text)
	var area := {"oid": "t_o1", "cid": "t", "kind": "clear_area", "text": "Clear the compound of hostiles", "state": "active", "optional": false,
		"progress": "", "params": {"rect": [-20, -20, 40, 40]}, "pos": [0, 0, 0]}
	var sit := {"pos": at.call(0, 300), "sites": {"t": "compound"}}
	check(step.call([], sit) == "", "no deployment, no hint")
	var area2 := area.duplicate(true)
	area2.oid = "t_o9"
	area2.pos = [0, 0, 500]
	area2.params = {"rect": [-20, 480, 40, 40]}
	sit["chosen"] = "t_o9"
	check(String(ObjectiveHelper.step_for([area, area2], sit).oid) == "t_o9" and ObjectiveHelper.step_for([area2, area], sit).targets[0].pos.z > 400.0,
		"a picked objective beats the nearest one, and the marker follows it")
	sit["chosen"] = ""
	sit.pos = at.call(5, 5)
	check(String(ObjectiveHelper.step_for([area, area2], sit).oid) == "t_o1", "no pick: the nearest")
	check(ObjectiveHelper.next_choice([area, area2], "") == "t_o1" and ObjectiveHelper.next_choice([area, area2], "t_o1") == "t_o9"
		and ObjectiveHelper.next_choice([area, area2], "t_o9") == "", "N cycles through the live objectives, then back to auto")
	sit.pos = at.call(0, 300)
	check(step.call([area], sit) == "Head to the compound (N, 300 m)", "away from the site: head there, with the direction and distance")
	sit.pos = at.call(5, 5)
	check(step.call([area], sit) == "Clear the compound: search it for hostiles", "in the area: clear it")
	var cleared := area.duplicate(true)
	cleared.progress = "2 hostiles left"
	check(step.call([cleared], sit) == "Clear the compound: 2 hostiles left", "with the hostiles left")
	var cache := {"oid": "t_o2", "cid": "t", "kind": "destroy_cache", "text": "Destroy the weapons cache", "state": "active", "optional": false,
		"progress": "", "params": {"box": [[-13, 0, -11], [-11, 2, -10]], "name": "weapons cache"}, "pos": [-12, 1, -10.5]}
	check(step.call([cache], sit) == "Destroy the weapons cache (breaching charge or explosives)", "at a cache: destroy it")
	var charged := cache.duplicate(true)
	charged.progress = "charge set"
	check(step.call([charged], sit) == "Charge set on the weapons cache: get clear", "a charge set on it: get clear")
	var laptop := {"oid": "t_o3", "cid": "t", "kind": "extract_item", "text": "Recover the laptop and carry it out", "state": "active", "optional": false,
		"progress": "", "params": {"pos": [3, 0.5, -10], "place": "intel_laptop", "items": ["intel_laptop"], "name": "laptop"}, "pos": [3, 0.5, -10]}
	sit["indoors"] = ["t_o3"]
	check(step.call([laptop], sit) == "Find the laptop in the building", "an item indoors: find it in the building")
	sit["held"] = ["t_o3"]
	check(step.call([laptop], sit) == "Carry the laptop out: walk to an LZ or call extraction (map, M)", "the laptop in hand: carry it out")
	sit.erase("held")
	var hvt := {"oid": "t_o4", "cid": "t", "kind": "deliver_hvt", "text": "Capture Amir and bring them to extraction alive", "state": "active", "optional": false,
		"progress": "", "params": {"pos": [0, 0.1, -8], "hvt": "hvt_t", "person": {"side": "hostile", "name": "Amir", "label": "HVT (Amir)"}}, "pos": [0, 0.1, -8]}
	var phone := {"oid": "t_o5", "cid": "t", "kind": "extract_item", "text": "Bring out Amir's phone", "state": "active", "optional": false,
		"progress": "", "params": {"pos": [0, 0.1, -8], "items": ["intel_phone"], "of_hvt": "hvt"}, "pos": [0, 0.1, -8]}
	sit["cuffs"] = true
	check(step.call([hvt], sit) == "Capture Amir: cuff them, take them to the LZ", "at an HVT: capture them")
	sit.cuffs = false
	check(step.call([hvt], sit) == "Capture Amir: you need zip cuffs", "and says when the player has no cuffs")
	sit.cuffs = true
	sit["hvts"] = {"hvt_t": {"found": true, "custody": false, "surrendered": true}}
	check(step.call([hvt], sit) == "Amir gave up: cuff them, take them to the LZ", "an HVT who gave up: cuff them")
	var hvt_done := hvt.duplicate(true)
	hvt_done.state = "done"
	check(step.call([hvt_done, phone], sit) == "Search Amir for the phone", "a piece the HVT carries: search them")
	var lz := {"name": "LZ South", "pos": Vector3(0, 0, 34), "radius": 20.0, "source": "zone"}
	sit["lzs"] = [lz]
	sit.hvts = {"hvt_t": {"found": true, "custody": true}}
	var going: Dictionary = ObjectiveHelper.step_for([area, hvt], sit)
	check(String(going.text) == "Bring Amir to LZ South (S, 30 m)" and going.targets.size() == 1 and bool(going.targets[0].extract)
		and (going.targets[0].pos as Vector3).is_equal_approx(lz.pos), "an HVT in hand goes to the LZ first, the marker on it (%s)" % going.text)
	var hostage := hvt.duplicate(true)
	hostage.params.person = {"side": "friendly", "name": "Sara"}
	sit.hvts = {}
	check(step.call([hostage], sit) == "Free Sara: have them follow you to the LZ", "a hostage: free them")
	sit.pos = at.call(0, 300)
	check(step.call([hostage], sit) == "Find Sara at the compound (N, 310 m)", "a hostage far off: find them at the site")
	# Everything required done: extraction.
	var done := area.duplicate(true)
	done.state = "done"
	var bonus := cache.duplicate(true)
	bonus.optional = true
	var out: Dictionary = ObjectiveHelper.step_for([done, bonus], sit)
	check(String(out.text) == "All done: call extraction (map, M) or walk to an LZ" and out.targets.size() == 1 and bool(out.targets[0].extract),
		"all required done (a bonus left): extraction, the marker on the LZ")
	sit.pos = at.call(2, 30)
	check(step.call([done], sit) == "At LZ South: extract on the map (M) once everyone's in", "at the LZ: extract on the map")
	sit["extraction"] = {"countdown": true, "left": 6.2}
	check(step.call([done], sit) == "Extracting in 7 s: stay inside", "the countdown")
	sit.erase("extraction")
	check(ObjectiveHelper.distance_text(1234.0) == "1.2 km" and ObjectiveHelper.distance_text(47.0) == "45 m" and ObjectiveHelper.distance_text(347.0) == "350 m"
		and ObjectiveHelper.compass(Vector3.ZERO, Vector3(100, 0, 0)) == "E" and ObjectiveHelper.compass(Vector3.ZERO, Vector3(-50, 0, 50)) == "SW",
		"distances rounded as said, compass points with north up the map")
	# Live: a raid on the compound, from this HUD.
	Contracts.new_full_campaign(83, 200000)
	var cid := _make_offer("raid", "compound_01")
	Contracts.server_accept(cid, ContractGen.default_terms())
	player.global_position = Vector3(40, 0.1, 40)
	Contracts.server_start_deployment([cid])
	var helper := _helper()
	check(helper != null, "the HUD has the objective helper")
	if helper == null:
		return
	helper.refresh()
	var target_o: Dictionary = Contracts.objectives.for_contract(cid)[0]
	var site := Objectives.site_pos(target_o.params)
	var site_v := Vector3(float(site[0]), float(site[1]), float(site[2]))
	check(helper.hint_text().begins_with("Head to the compound (NW, ") and helper.current.targets.size() == 1,
		"deployed away from the site: '%s'" % helper.hint_text())
	var target: Vector3 = helper.current.targets[0].pos if not helper.current.targets.is_empty() else Vector3.INF
	check(Vector2(target.x, target.z).is_equal_approx(Vector2(site_v.x, site_v.z)), "one marker, on the objective's site (%s)" % target)
	var cam := player.camera
	var keep := cam.global_transform
	cam.global_transform = Transform3D(Basis.IDENTITY, cam.global_position).looking_at(target)
	var marks := helper.layout_markers()
	var view := helper.size
	check(marks.size() == 1 and not bool(marks[0].edge) and (marks[0].screen as Vector2).distance_to(view * 0.5) < 4.0 and String(marks[0].label) != "",
		"looking at it: the marker sits on it, mid-screen, labelled (%s)" % [marks[0].screen if not marks.is_empty() else "none"])
	cam.global_transform = Transform3D(Basis.IDENTITY, cam.global_position).looking_at(cam.global_position * 2.0 - target)
	marks = helper.layout_markers()
	var off: Vector2 = (marks[0].screen as Vector2 - view * 0.5).abs() if not marks.is_empty() else Vector2.ZERO
	var half := view * 0.5 - Vector2.ONE * ObjectiveHelper.EDGE_PX
	check(marks.size() == 1 and bool(marks[0].edge) and Rect2(Vector2.ZERO, view).has_point(marks[0].screen)
		and (is_equal_approx(off.x, half.x) or is_equal_approx(off.y, half.y)),
		"behind the camera: an arrow clamped to the screen's edge (%s)" % [marks[0].screen if not marks.is_empty() else "none"])
	ObjectiveHelper.markers_on = false
	check(helper.layout_markers().is_empty() and helper.hint_text() != "", "the switch hides the markers (the line stays)")
	ObjectiveHelper.markers_on = true
	cam.global_transform = keep
	player.global_position = site_v + Vector3(1, 0, 4)
	helper.refresh()
	check(helper.hint_text().begins_with("Destroy the ") and helper.layout_markers().is_empty(),
		"at the cache: what to do, and no marker that close ('%s')" % helper.hint_text())
	var ext := MapNodes.extraction(level)
	ext.server_begin({"zone": Briefing.DEBUG_ZONE})
	Contracts.server_cache_destroyed(String(target_o.params.get("cache", "")))
	helper.refresh()
	var lz_at: Vector3 = helper.current.targets[0].pos if not helper.current.targets.is_empty() else Vector3.INF
	check(helper.hint_text() == "All done: call extraction (map, M) or walk to an LZ" and helper.current.targets.size() == 1
		and Vector2(lz_at.x, lz_at.z).is_equal_approx(Vector2(0, 34)), "the cache gone: extraction, the marker on the LZ ('%s')" % helper.hint_text())
	# Captain, 2026-10-14: aimed through a red dot at "LZ 2" its name showed twice, small on the
	# LZ's own label in the world (inside the sight) and on the HUD marker. One name at a time:
	# while the HUD marks the point, its world label stands down.
	var dp := DeliveryPoint.new()
	dp.label = "LZ South"
	level.add_child(dp)
	dp.global_position = Vector3(lz_at.x, 0.0, lz_at.z)
	var stood := player.global_position
	player.global_position = Vector3(lz_at.x, 0.1, lz_at.z + 25.0)
	player.is_aiming = true
	var keep_cam := cam.global_transform
	cam.global_transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 1.6).looking_at(lz_at + Vector3.UP * 2.2)
	helper.drawn = helper.layout_markers()
	dp._process(0.0)
	var lz_marks := helper.drawn.filter(func(m: Dictionary) -> bool: return not bool(m.edge) and String(m.label) != "")
	check(lz_marks.size() == 1 and dp.text_label != null and not dp.text_label.visible,
		"aiming at the LZ from 25 m: its name once, on the HUD marker (%d marked, world label %s)" % [lz_marks.size(), "shown" if dp.text_label and dp.text_label.visible else "hidden"])
	player.global_position = Vector3(lz_at.x, 0.1, lz_at.z + 4.0)
	helper.drawn = helper.layout_markers()
	dp._process(0.0)
	check(helper.drawn.is_empty() and dp.text_label.visible, "in at the LZ the marker hides and the world label is back")
	player.is_aiming = false
	player.global_position = stood
	cam.global_transform = keep_cam
	dp.queue_free()
	ext.server_cancel()
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()
	helper.refresh()
	check(helper.hint_text() == "" and helper.layout_markers().is_empty(), "no deployment: no line and no markers")


func _test_ammo_readout() -> void:
	print("Ammo readout (HUD): mags and an estimate, not a count")
	var words := [[30, "Full"], [29, "Full"], [28, "Nearly full"], [20, "Nearly full"], [19, "About half"], [11, "About half"],
		[10, "Low"], [5, "Low"], [4, "Nearly empty"], [1, "Nearly empty"], [0, "Empty"]]
	var wrong := words.filter(func(w: Array) -> bool: return AmmoReadout.fill_word(int(w[0]), 30) != String(w[1]))
	check(wrong.is_empty(), "the fill words of a 30-round magazine by rounds left (%s wrong)" % [wrong])
	var inv := player.inventory
	if inv.slots.get(&"primary", &"") == &"":
		inv.take(&"m4a1")
	player.active_slot = &"primary"
	var weapon := player.active_weapon()
	var ammo_id := StringName(weapon.stats.get("ammo", "")) if weapon else &""
	check(weapon != null and ItemDB.has_item(ammo_id), "the player holds a magazine-fed rifle")
	if not ItemDB.has_item(ammo_id):
		return
	var full := ItemDB.get_item(ammo_id).magazine_rounds()
	inv.set_slot_state(&"primary", {"rounds": roundi(full * 0.5)})
	inv.take(ammo_id, 1, {"rounds": roundi(full * 0.3)})
	inv.take(ammo_id, 1, {"rounds": 0})
	var sum := AmmoReadout.summary(player)
	var mags := inv.count_of(ammo_id)
	var spares: Array = sum.get("spares", [])
	check(String(sum.get("loaded", "")) == "About half" and spares.size() == mags and spares.count(0.0) >= 1
		and spares.any(func(f: float) -> bool: return f > 0.0 and f < 0.95),
		"half a magazine loaded reads About half; a pip per spare magazine carried (%d), part-used and empty ones told apart" % mags)
	var text := AmmoReadout.text_of(sum)
	var with_rounds := spares.filter(func(f: float) -> bool: return f > 0.0).size()
	check(text.begins_with("About half | %d mag%s (" % [with_rounds, "" if with_rounds == 1 else "s"]) and text.contains("part-used") and text.contains("1 empty")
		and not text.contains("/%d" % full), "the readout in words, no round count ('%s')" % text)
	inv.take(&"frag_grenade", 2)
	check(AmmoReadout.text_of(AmmoReadout.summary(player)).contains("frag"), "grenades as a count")


func _helper() -> ObjectiveHelper:
	var found := get_tree().root.find_children("*", "ObjectiveHelper", true, false)
	return found[0] as ObjectiveHelper if not found.is_empty() else null


func _hostile(callsign: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": "hostile", "variant": "urban", "pos": pos,
		"loadout": ["plate_carrier_light", "mk18"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _panel() -> ObjectivesPanel:
	var found := get_tree().root.find_children("*", "ObjectivesPanel", true, false)
	return found[0] as ObjectivesPanel if not found.is_empty() else null


# --- Over ENet ---------------------------------------------------------------------------------

func _test_over_network() -> void:
	print("Over ENet (a second process joins late)")
	Contracts.new_full_campaign(91, 150000)
	var cid := _make_offer("clear_compound", "compound_01")
	Contracts.server_accept(cid, ContractGen.default_terms())
	# Audit A1-07: a hostile holds out in the compound, so the clear objective is legitimately
	# still active however long the client takes to join (an empty area completes itself after
	# "clear_arm_timeout_s"); the client compares with what the host has.
	var holdout := _hostile("NetHoldout", Vector3(8, 0.1, 0))
	Contracts.server_start_deployment([cid])
	var args :=PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/contracts_test.tscn", "--", "--join", "127.0.0.1"])
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "client process started")
	if pid <= 0:
		return
	await _wait_for(func() -> bool: return _client_ready, 30.0)
	check(_client_ready, "the client joined")
	if _client_ready:
		var peer := multiplayer.get_peers()[0]
		var offer: Dictionary = Contracts.board()[2]
		var states: Array = Contracts.objectives.list.map(func(o: Dictionary) -> String: return String(o.state))
		check(states.all(func(st: String) -> bool: return st == "active") and Contracts.objectives.hostiles_in(Contracts.objectives.list[0]) == 1,
			"host: with a hostile holding out, the clear objective is still active when the client is in (%s)" % ", ".join(PackedStringArray(states)))
		_start_client.rpc_id(peer, {"board": Contracts.board().size(), "objectives": Contracts.objectives.list.size(), "offer": offer.cid,
			"cash": Economy.cash(), "title": Contracts.contract(cid).title, "states": states})
		await _wait_for(func() -> bool: return _client_phase >= 1, 20.0)
		check(Contracts.contract(String(offer.cid)).get("state") == "accepted", "the client's accept went through the host")
		holdout.vitals.server_kill()
		Contracts.objectives.server_set_state(Contracts.objectives.list[0].oid, Objectives.DONE)
		await _wait_for(func() -> bool: return _client_phase >= 2, 10.0)
		Contracts.server_end_deployment(Contracts.report_from_level(level, [player]))
		await _wait_for(func() -> bool: return _client_phase >= 3, 20.0)
		await _seconds(0.5)
		check(not Contracts.last_debrief().finished, "a client's Continue doesn't close the debrief for everyone (only the host's)")
		Contracts.server_finish_debrief()
		# A reset campaign numbers its debriefs from 1 again: the client must still show the first.
		Contracts.new_full_campaign(92, 150000)
		var again := _make_offer("intel_grab", "compound_01")
		Contracts.server_accept(again, ContractGen.default_terms())
		Contracts.server_start_deployment([again])
		Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 1}]})
		check(int(Contracts.last_debrief().serial) == 1, "after a reset the debrief count starts over")
		await _wait_for(func() -> bool: return _client_done, 20.0)
		check(_client_done, "the client finished its checks")
	if OS.is_process_running(pid):
		OS.kill(pid)


## Client: runs in the joined copy of this test.
func _run_client() -> void:
	level = CompoundLevel.current(self)
	var deadline := Time.get_ticks_msec() + 20000
	var me: Soldier = null
	while Time.get_ticks_msec() < deadline:
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id())) if level else null
		if me:
			break
		level = CompoundLevel.current(self)
		await get_tree().process_frame
	if me == null:
		get_tree().quit(1)
		return
	me.set_physics_process(false)
	_remote_ready.rpc_id(1)
	while _go.is_empty() and Time.get_ticks_msec() < deadline + 15000:
		await get_tree().process_frame
	var host_states: Array = _go.get("states", [])
	var my_states := func() -> Array: return Contracts.objectives.list.map(func(o: Dictionary) -> String: return String(o.state))
	await _wait_for(func() -> bool: return Contracts.board().size() == int(_go.board) and my_states.call() == host_states, 5.0)
	_remote_check.rpc_id(1, Contracts.board().size() == int(_go.board) and Economy.cash() == int(_go.cash) and Economy.day() >= 1,
		"a late joiner gets the board (%d offers) and the company's cash ($%d)" % [Contracts.board().size(), Economy.cash()])
	_remote_check.rpc_id(1, not Contracts.board().any(func(o: Dictionary) -> bool: return o.has("true_rating") or o.has("understated")),
		"without the host-only truth about the threat")
	_remote_check.rpc_id(1, Contracts.objectives.list.size() == int(_go.objectives) and Contracts.is_deployed() and my_states.call() == host_states,
		"and the deployment's objectives, live, as the host has them (%s)" % ", ".join(PackedStringArray(my_states.call())))
	var helper := _helper()
	if helper:
		helper.refresh()
	var site: Array = Objectives.site_pos(Contracts.objectives.list[0].params) if not Contracts.objectives.list.is_empty() else [INF, 0, INF]
	var t: Vector3 = helper.current.targets[0].pos if helper and not helper.current.targets.is_empty() else Vector3.INF
	_remote_check.rpc_id(1, helper != null and helper.hint_text() != "" and Vector2(t.x, t.z).is_equal_approx(Vector2(float(site[0]), float(site[2]))),
		"the client's helper says what to do from the replicated objectives ('%s'), its marker on the site" % (helper.hint_text() if helper else ""))
	# Audit A1-05: a malformed request from a client is refused with an answer, not a host error.
	var answers: Array = []
	var on_notice := func(text: String) -> void: answers.append(text)
	Contracts.notice.connect(on_notice)
	Contracts._rq.rpc_id(1, "accept", [])
	Contracts._rq.rpc_id(1, "sell", ["0", 1])
	await _wait_for(func() -> bool: return answers.size() >= 2, 5.0)
	Contracts.notice.disconnect(on_notice)
	_remote_check.rpc_id(1, answers == ["Bad request", "Bad request"], "a client's malformed requests are refused as bad requests (%s)" % ", ".join(PackedStringArray(answers)))
	var board := Contracts.open_board()
	await _frames(2)
	_remote_check.rpc_id(1, board.offer_count() == int(_go.board) and board.held_count() == 1 and board.header_text().contains("Cash $%s" % DebriefCalc.money(_go.cash)),
		"the client's board screen lists them (%d offers, %d held)" % [board.offer_count(), board.held_count()])
	var cash := Economy.cash()
	Contracts.accept(String(_go.offer), ContractGen.default_terms())
	await _wait_for(func() -> bool: return Contracts.held().any(func(o: Dictionary) -> bool: return o.cid == _go.offer), 5.0)
	await _wait_for(func() -> bool: return Economy.cash() > cash, 3.0)
	_remote_check.rpc_id(1, Contracts.held().any(func(o: Dictionary) -> bool: return o.cid == _go.offer) and Economy.cash() > cash and board.held_count() == 2,
		"accepting from the client: the host signs it and the advance shows (cash $%d)" % Economy.cash())
	board.close()
	_remote_phase.rpc_id(1, 1)
	await _wait_for(func() -> bool: return Contracts.objectives.list[0].state == "done", 5.0)
	var panel := _panel()
	_remote_check.rpc_id(1, Contracts.objectives.list[0].state == "done" and panel != null and panel.text().contains("[x] Clear the compound"),
		"an objective the host completes shows done in the client's HUD")
	_remote_phase.rpc_id(1, 2)
	await _wait_for(func() -> bool: return Contracts.debrief_screen() != null, 8.0)
	var screen := Contracts.debrief_screen()
	await _frames(2)
	var text := screen.text() if screen else ""
	_remote_check.rpc_id(1, screen != null and text.contains("DEBRIEF") and text.contains(String(_go.title)) and text.contains("Paid now") and text.contains("SALVAGE"),
		"the debrief appears on the client with the contract, the pay and the salvage")
	_remote_check.rpc_id(1, Contracts.objectives.list.is_empty() and not Contracts.is_deployed(), "and the objectives clear")
	var first_id := screen.get_instance_id() if screen else 0
	Contracts.finish_debrief()  # a client asking to close it: the host ignores it
	_remote_phase.rpc_id(1, 3)
	await _wait_for(func() -> bool: return Contracts.debrief_screen() != null and Contracts.debrief_screen().get_instance_id() != first_id, 15.0)
	var next := Contracts.debrief_screen()
	_remote_check.rpc_id(1, next != null and next.get_instance_id() != first_id and next.text().contains("DEBRIEF"),
		"after the host resets the campaign, its first debrief still opens on the client")
	_remote_done.rpc_id(1)
	await _seconds(0.5)
	Net.leave()
	get_tree().quit(0)


@rpc("authority", "reliable")
func _start_client(go: Dictionary) -> void:
	_go = go


@rpc("any_peer", "reliable")
func _remote_ready() -> void:
	if multiplayer.is_server():
		_client_ready = true


@rpc("any_peer", "reliable")
func _remote_check(ok: bool, what: String) -> void:
	if multiplayer.is_server():
		check(ok, "client: " + what)


@rpc("any_peer", "reliable")
func _remote_phase(phase: int) -> void:
	if multiplayer.is_server():
		_client_phase = phase


@rpc("any_peer", "reliable")
func _remote_done() -> void:
	if multiplayer.is_server():
		_client_done = true


# --- Helpers -----------------------------------------------------------------------------------

## Host: a contract of `type_id` in `zone_id` on the board, honest unless `overrides` say
## otherwise. Returns its id.
## What a debrief took from the cash at the end of its deployment: the expenses charged then,
## and its days' wages and upkeep (paid daily since the economy overhaul, as the days passed).
func _paid_at_debrief(d: Dictionary) -> int:
	var total := 0
	for l: Dictionary in d.get("expenses", []):
		if bool(l.charge) or String(l.what).begins_with("Wages") or String(l.what).begins_with("Base upkeep") or String(l.what).begins_with("Loan installments"):
			total += int(l.amount)
	return total


func _make_offer(type_id: String, zone_id: String, overrides := {}) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + _made
	_made += 1
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type_id, "zone_id": zone_id})
	# Played in this test's compound level: the objectives go on the compound module.
	var def := MissionRegistry.type_def(type_id).duplicate(true)
	def["modules"] = ["compound"]
	c.objectives = ContractGen.mission_target(rng, def, "").objectives
	c.module = "compound"
	c.module_id = ""
	c.understated = false
	c.true_rating = c.rated
	c.enemy_count = c.enemy_est
	c.merge(overrides, true)
	return Contracts.server_add_offer(c)


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The clear-an-area checks use a compound-clearing type of their own (Captain's first four
## mission types have no clear-only job; compound assault comes later).
func _register_clear_compound() -> void:
	MissionRegistry.register_type({"type": "clear_compound", "name": "Clear a compound", "brief": "Clear the compound.", "module": "compound",
		"base_pay": 42000, "days": 1, "enemy_count": [4, 12], "enemy_quality": [0.3, 0.7], "threat_pool": ["mg_nest", "sniper", "ied", "qrf"],
		"objectives": [{"kind": "clear_area", "site": "compound", "text": "Clear the compound of hostiles"},
			{"kind": "extract_item", "site": "intel", "text": "Bonus: bring out the hard case", "optional": true, "bonus_share": 0.1}]})
