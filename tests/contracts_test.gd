extends Node
## Headless checks for contracts, the economy and the debrief (wave 4, W10): generation from a
## seed, the difficulty rating and how often the briefing understates it, MW5-style
## negotiation and the advance kept on failure, renegotiating and aborting, lapses, weekly
## wages and the safety floor, the shop, the debrief's sums (pay, bonuses, fines, the
## 8-casualty void, salvage picks, intel), saving and reloading the campaign, objectives in a
## live level (clear an area, carry out an item, deliver an HVT, destroy a cache by voxels or
## a placed charge), and over ENet a client that sees the board, the objectives and the debrief.
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
	_test_rating_and_understatement()
	_test_negotiation()
	_test_reveal_renegotiate_abort()
	_test_wages_and_floor()
	_test_lapse()
	_test_debrief_totals()
	_test_civilians_void()
	_test_save_reload()
	_test_shop()
	_test_intel_and_salvage()
	await _test_board_ui()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	await _frames(20)
	await _test_live_objectives()
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
	for o: Dictionary in a:
		var zone := MissionRegistry.zone(o.zone_id)
		var def := MissionRegistry.type_def(o.type)
		valid = valid and int(o.rated) >= 1 and int(o.rated) <= 5 and int(o.true_rating) >= int(o.rated) and int(o.base_pay) > 0 \
			and not (o.objectives as Array).is_empty() and def.module == o.module and o.module in zone.modules \
			and o.employer in MissionRegistry.employers() and o.target in MissionRegistry.enemies() and o.zone_kind == zone.kind
	check(valid, "every offer is sound: rating 1-5, the briefing never overstates, pay, objectives, a zone holding its module")
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
		and fixer_jobs[0].type in ["recover_hvt", "retrieve_intel"], "at reputation 25 Meridian's fixer offers a special job (%s)" % [fixer_jobs.map(func(o: Dictionary) -> String: return o.title)])
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
	check(seen.keys().size() == 4 and seen.has("clear_compound") and seen.has("recover_hvt") and seen.has("retrieve_intel") and seen.has("destroy_cache"),
		"all four placeholder mission types come up (%s)" % [seen.keys()])
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
			consistent = consistent and int(o.rated) == int(o.true_rating) and int(o.enemy_est) == int(o.enemy_count) and o.threats_known == o.threats
	var rate := float(understated) / n
	expected /= n
	check(absf(rate - expected) < 0.03 and expected > 0.1 and expected < 0.3,
		"the briefing understates %.1f%% of contracts that can be understated (expected %.1f%% from intel accuracy)" % [rate * 100.0, expected * 100.0])
	var low_rate := float(low[0]) / maxi(low[1], 1)
	var high_rate := float(high[0]) / maxi(high[1], 1)
	check(low_rate > high_rate + 0.08, "poor intel lies more often than good intel (%.0f%% vs %.0f%%)" % [low_rate * 100.0, high_rate * 100.0])
	check(consistent, "an understated briefing rates lower and reports fewer fighters, lower quality, no more threats; an honest one tells the truth")
	var some := ContractGen.generate(rng, {"day": 1, "source": "board"})
	var view := ContractGen.public_view(some)
	check(not view.has("true_rating") and not view.has("enemy_count") and not view.has("understated") and view.has("rated") and view.has("enemy_est"),
		"clients only see the briefing, not the truth")


# --- Negotiation -----------------------------------------------------------------------------

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
	check(held.state == "accepted" and Economy.cash() == before + deal.advance and int(held.support_left) == 5000
		and not Contracts.board().any(func(o: Dictionary) -> bool: return o.cid == cid) and Contracts.held().any(func(o: Dictionary) -> bool: return o.cid == cid),
		"signing pays the 30%% advance ($%d) and the contract moves to held, with a $5,000 support budget" % deal.advance)
	check(Contracts.server_start_deployment([cid]) == "" and Contracts.is_deployed() and Contracts.objectives.list.size() == 2
		and Contracts.objectives.active().size() == 2, "deployed: its two objectives are live")
	var rep := Economy.reputation(String(held.employer))
	var cash := Economy.cash()
	var debrief := Contracts.server_end_deployment({})
	check(debrief.contracts[0].outcome == "failed" and int(debrief.totals.completion) == 0 and int(debrief.totals.advance) == deal.advance
		and Economy.cash() == cash and not Contracts.is_deployed(), "failed: no completion pay, but the advance is kept ($%d)" % Economy.cash())
	check(Economy.reputation(String(held.employer)) == rep - 6 and Contracts.history().back().outcome == "failed" and Contracts.held().is_empty(),
		"and the client thinks less of the company (%+d)" % (Economy.reputation(String(held.employer)) - rep))
	Contracts.server_finish_debrief()


func _test_reveal_renegotiate_abort() -> void:
	print("Understated threats: renegotiate or abort")
	Contracts.new_full_campaign(43, 100000)
	var cid := _make_offer("destroy_cache", "compound_01", {"understated": true, "rated": 2, "true_rating": 4, "enemy_est": 5, "enemy_count": 12})
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
	var other := _make_offer("retrieve_intel", "compound_01")
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
	Contracts.new_full_campaign(7, 50000)
	Economy.wages_provider = func() -> int: return 20000
	check(Economy.days_to_bill() == 7 and Economy.weekly_bill().total == 24000, "the bill: $20,000 wages from the roster + $4,000 upkeep, due in 7 days")
	Economy.advance_days(6, "test")
	check(Economy.cash() == 50000 and Economy.day() == 7, "nothing due before the week is out")
	Economy.advance_days(1, "test")
	check(Economy.cash() == 26000 and Economy.day() == 8 and int(Economy.ledger().back().amount) == -24000, "day 8: the week's bill is paid ($26,000 left)")
	Economy.wages_provider = func() -> int: return 60000
	var notices: Array = []
	var on_notice := func(text: String) -> void: notices.append(text)
	Economy.notice.connect(on_notice)
	Economy.advance_days(7, "test")
	Economy.notice.disconnect(on_notice)
	check(Economy.cash() == MissionRegistry.setting_i("safety_floor_cash", 20000) and Economy.loans_owed() == roundi(58000 * 1.1)
		and notices.any(func(t: String) -> bool: return t.contains("Emergency loan")),
		"a $64,000 bill on $26,000: an emergency loan covers it and leaves the floor ($%d cash, $%d owed)" % [Economy.cash(), Economy.loans_owed()])
	Economy.wages_provider = func() -> Array: return [{"what": "Alpha", "amount": 1000}, {"what": "Bravo", "amount": 1500}]
	var bill := Economy.weekly_bill()
	var owed := Economy.loans_owed()
	check(bill.wages == 2500 and bill.loans == ceili(owed / 8.0), "wages as lines from the roster ($%d), and the loan installment ($%d)" % [bill.wages, bill.loans])
	Economy.advance_days(7, "test")
	check(Economy.loans_owed() == owed - bill.loans and Economy.cash() == 20000 - bill.total, "the installment comes off the loan")
	var lent := 0
	for i in 5:
		lent += Economy.server_take_loan()
	check(Economy.loans_owed() <= MissionRegistry.setting_i("loan_max", 150000) and Economy.server_take_loan() == 0 and lent > 0,
		"loans stop at the cap ($%d owed)" % Economy.loans_owed())
	check(Contracts.board().any(func(o: Dictionary) -> bool: return o.source == "safe" and int(o.rated) == 1), "the board always keeps a low-risk job")
	Economy.wages_provider = Callable()
	check(Economy.weekly_bill().wages == Prices.default_wage_bill(), "without a roster, the stand-in wage bill")


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
		and Economy.reputation(employer) == rep - 3, "a contract never deployed lapses and costs reputation (%+d)" % (Economy.reputation(employer) - rep))
	check(Contracts.board().all(func(o: Dictionary) -> bool: return int(o.expires_day) >= Economy.day()) and Contracts.board().size() >= 6,
		"old offers expired and the board refilled (%d)" % Contracts.board().size())


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
	check(line.outcome == "completed" and line.completion == 70000 and line.bonuses.size() == 2 and line.pay == 90000
		and d.totals.paid_now == 90000 and d.totals.contract_value == 120000 and d.fines == 0,
		"completed: $70,000 completion + $10,000 bonus objective + $10,000 for no civilian casualties ($120,000 all told)")
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
	check(summary.contains("COMPLETED") and summary.contains("$70,000") and summary.contains("Paid now: $90,000"), "the summary reads right")


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
	check(d.contracts[0].outcome == "voided" and Economy.cash() == cash - 20000 - advance and Economy.reputation(employer) == rep - 6 - 16 and Economy.locals() == -32,
		"debrief: pays nothing (advance $%d clawed back), $20,000 in fines, -22 with the client, -32 with the locals" % advance)
	Contracts.server_finish_debrief()
	check(Contracts.server_civilian_casualty() == 0, "no deployment, nothing counted")


func _test_save_reload() -> void:
	print("Saving and reloading the campaign")
	Contracts.new_full_campaign(31, 120000)
	var cid := _make_offer("recover_hvt", "wadi_farm")
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
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()


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
	var cid := _make_offer("destroy_cache", "compound_01")
	Contracts.server_accept(cid, {"pay_points": 0, "salvage_points": 0, "support_points": 1, "advance_share": 0.3})
	cash = Economy.cash()
	check(Economy.server_pay_support("resupply", cid) and Contracts.support_left(cid) == 0 and Economy.cash() == cash - 3000,
		"a $8,000 resupply call: $5,000 from the support budget, $3,000 cash")


func _test_intel_and_salvage() -> void:
	print("Intel, leads and salvage picks")
	Contracts.new_full_campaign(61, 100000)
	Economy.take_unbanked()
	var cid := _make_offer("retrieve_intel", "harbour_yard")
	Contracts.server_accept(cid, {"pay_points": 0, "salvage_points": 4, "support_points": 0, "advance_share": 0.3})
	Contracts.server_start_deployment([cid])
	var cash := Economy.cash()
	var d := Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 1}],
		"field_items": [{"id": "m4a1", "count": 1}, {"id": "rounds_556", "count": 30}], "extracted": ["You"]})
	var deal: Dictionary = Contracts.history().back()
	check(d.contracts[0].outcome == "completed" and Economy.cash() == cash + int(d.totals.paid_now) and int(d.totals.paid_now) > 0,
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
	check(Contracts.server_sell_intel(0, buyer) == "" and Economy.cash() == cash + 6000 and Economy.reputation(buyer) == buyer_rep + 2
		and Economy.reputation(client) == client_rep + (-8 if d.intel[0].caught else 0),
		"sold to %s for $6,000 (the client %s)" % [buyer, "found out: -8" if d.intel[0].caught else "never knew"])
	Contracts.server_finish_debrief()
	var inbox := Economy.take_unbanked()
	check(inbox.any(func(e: Dictionary) -> bool: return e.id == "hvt_case") and inbox.any(func(e: Dictionary) -> bool: return e.id == "rounds_556" and e.count == 30)
		and not inbox.any(func(e: Dictionary) -> bool: return e.id == "m4a1") and d.finished, "closing the debrief banks what was carried out and the salvage picked")
	check(deal.outcome == "completed", "the contract closed as completed")
	# Turning intel in opens leads.
	var second := _make_offer("retrieve_intel", "compound_01")
	Contracts.server_accept(second, ContractGen.default_terms())
	Contracts.server_start_deployment([second])
	Contracts.server_end_deployment({"items": [{"id": "hvt_case", "count": 2}]})
	var leads_before := Contracts.board().filter(func(o: Dictionary) -> bool: return o.source == "lead").size()
	check(Contracts.server_turn_in_intel(0) == "", "intel turned in")
	var leads := Contracts.board().filter(func(o: Dictionary) -> bool: return o.source == "lead")
	check(leads.size() == leads_before + 2 and String(leads.back().title).begins_with("Lead:") and float(leads.back().intel_accuracy) >= 0.8,
		"two pieces open two leads on the board, with good intel (%s)" % [leads.map(func(o: Dictionary) -> String: return o.title)])
	Contracts.server_finish_debrief()


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
	board.close()
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
	var cache := _make_offer("destroy_cache", "ridge_hot")
	var hvt := _make_offer("recover_hvt", "ridge_hot")
	for cid: String in [clear, cache, hvt]:
		Contracts.server_accept(cid, ContractGen.default_terms())
	var h1 := _hostile("TestHostile1", Vector3(-6, 0.1, -14))
	var h2 := _hostile("TestHostile2", Vector3(8, 0.1, 0))
	check(Contracts.server_start_deployment([], "ridge_hot") == "" and Contracts.deployment().cids.size() == 3 and Contracts.objectives.list.size() == 4,
		"a hot zone deploys on all three contracts at once (4 objectives)")
	await _seconds(1.2)
	var clear_o: Dictionary = Contracts.objectives.for_contract(clear)[0]
	check(clear_o.state == "active" and clear_o.progress == "2 hostiles left", "clear the compound: 2 hostiles left")
	var panel := _panel()
	check(panel != null and panel.text().contains("OBJECTIVES") and panel.text().contains("[ ] Clear the compound of hostiles (2 hostiles left)"),
		"the HUD lists the objectives")
	check(Contracts.objectives.markers().size() == 4 and Contracts.objectives.markers()[0].pos is Vector3, "and the map gets markers")
	h1.vitals.server_kill()
	h2.vitals.server_kill()
	await _seconds(1.2)
	check(Contracts.objectives.for_contract(clear)[0].state == "done", "both down: cleared")
	Contracts.server_items_banked([{"id": "hvt_case", "count": 1}])
	check(Contracts.objectives.for_contract(clear)[1].state == "done", "the bonus case sent out mid-zone counts")
	Contracts.server_hvt_delivered("hvt_compound")
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
	check(d.contracts.size() == 3 and d.contracts.all(func(l: Dictionary) -> bool: return l.outcome == "completed") and Economy.cash() == cash + int(d.totals.paid_now)
		and int(d.salvage.pool_value) > 0, "all three completed and paid ($%d); salvage pool $%d" % [int(d.totals.paid_now), int(d.salvage.pool_value)])
	check(Contracts.objectives.list.is_empty() and (panel == null or panel.text() == ""), "after extraction the objective list clears")
	Contracts.server_finish_debrief()
	# The zone kept its damage: the next cache contract on this module finds the crates already blown.
	level.voxel_world.server_blast(site_box.get_center(), 1.6)  # whatever the charge left standing
	await _seconds(0.3)
	var carved := Objectives.solid_count(level.voxel_world, site_box)
	var again := _make_offer("destroy_cache", "compound_01")
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
	Contracts.server_start_deployment([cid])
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/contracts_test.tscn", "--", "--join", "127.0.0.1"])
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "client process started")
	if pid <= 0:
		return
	await _wait_for(func() -> bool: return _client_ready, 30.0)
	check(_client_ready, "the client joined")
	if _client_ready:
		var peer := multiplayer.get_peers()[0]
		var offer: Dictionary = Contracts.board()[2]
		_start_client.rpc_id(peer, {"board": Contracts.board().size(), "objectives": Contracts.objectives.list.size(), "offer": offer.cid,
			"cash": Economy.cash(), "title": Contracts.contract(cid).title})
		await _wait_for(func() -> bool: return _client_phase >= 1, 20.0)
		check(Contracts.contract(String(offer.cid)).get("state") == "accepted", "the client's accept went through the host")
		Contracts.objectives.server_set_state(Contracts.objectives.list[0].oid, Objectives.DONE)
		await _wait_for(func() -> bool: return _client_phase >= 2, 10.0)
		Contracts.server_end_deployment(Contracts.report_from_level(level, [player]))
		await _wait_for(func() -> bool: return _client_phase >= 3, 20.0)
		await _seconds(0.5)
		check(not Contracts.last_debrief().finished, "a client's Continue doesn't close the debrief for everyone (only the host's)")
		Contracts.server_finish_debrief()
		# A reset campaign numbers its debriefs from 1 again: the client must still show the first.
		Contracts.new_full_campaign(92, 150000)
		var again := _make_offer("retrieve_intel", "compound_01")
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
	await _wait_for(func() -> bool: return Contracts.board().size() == int(_go.board) and Contracts.objectives.list.size() == int(_go.objectives), 5.0)
	_remote_check.rpc_id(1, Contracts.board().size() == int(_go.board) and Economy.cash() == int(_go.cash) and Economy.day() >= 1,
		"a late joiner gets the board (%d offers) and the company's cash ($%d)" % [Contracts.board().size(), Economy.cash()])
	_remote_check.rpc_id(1, not Contracts.board().any(func(o: Dictionary) -> bool: return o.has("true_rating") or o.has("understated")),
		"without the host-only truth about the threat")
	_remote_check.rpc_id(1, Contracts.objectives.list.size() == int(_go.objectives) and Contracts.is_deployed()
		and Contracts.objectives.list.all(func(o: Dictionary) -> bool: return o.state == "active"), "and the deployment's objectives, live")
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
func _make_offer(type_id: String, zone_id: String, overrides := {}) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + _made
	_made += 1
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type_id, "zone_id": zone_id})
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
