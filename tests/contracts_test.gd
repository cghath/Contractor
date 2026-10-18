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
	_register_clear_compound()
	_test_rating_and_understatement()
	_test_negotiation()
	_test_malformed_requests()
	_test_reveal_renegotiate_abort()
	_test_wages_and_floor()
	_test_economy_balance()
	_test_lapse()
	_test_reputation_core()
	_test_world_sites()
	_test_debrief_totals()
	_test_civilians_void()
	_test_save_reload()
	_test_shop()
	_test_intel_and_salvage()
	_test_set_down_at_the_point()
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
	for o: Dictionary in a:
		var zone := MissionRegistry.zone(o.zone_id)
		var def := MissionRegistry.type_def(o.type)
		valid = valid and int(o.rated) >= 1 and int(o.rated) <= 5 and int(o.true_rating) >= int(o.rated) and int(o.base_pay) > 0 \
			and not (o.objectives as Array).is_empty() and ZoneModules.base(o.module) in MissionRegistry.type_modules(def) and ZoneModules.base(o.module) in zone.modules and (String(o.module_id) != "" or def.has("scenario")) \
			and o.employer in MissionRegistry.employers() and o.target in MissionRegistry.enemies() and o.zone_kind == zone.kind
	check(valid, "every offer is sound: rating 1-5, the briefing never overstates, pay, objectives, a target module in the zone's layout")
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
	check(seen.keys().size() == 10 and seen.has("psd_escort") and seen.has("raid") and seen.has("hvt_capture") and seen.has("hostage_rescue") and seen.has("intel_grab")
		and seen.has("convoy_ambush") and seen.has("defend_hold") and seen.has("crew_rescue") and seen.has("sabotage") and seen.has("recon"),
		"Captain's first four mission types, the five of mission variety and the client escort come up (%s)" % [seen.keys()])
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
		and Economy.cash() == cash and not Contracts.is_deployed(), "failed: no completion pay, but the advance is kept ($%d)" % Economy.cash())
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
	check(Economy.days_to_bill() == 7 and Economy.weekly_bill().total == 20000 + up, "the bill: $20,000 wages from the roster + $%d upkeep, due in 7 days" % up)
	Economy.advance_days(6, "test")
	check(Economy.cash() == 100000 and Economy.day() == 7, "nothing due before the week is out")
	Economy.advance_days(1, "test")
	var left := 100000 - 20000 - up
	check(Economy.cash() == left and Economy.day() == 8 and int(Economy.ledger().back().amount) == -(20000 + up), "day 8: the week's bill is paid once")
	Economy.advance_days(6, "test")
	check(Economy.cash() == left, "and not again in the days after it")
	Economy.wages_provider = func() -> int: return 100000
	var notices: Array = []
	var on_notice := func(text: String) -> void: notices.append(text)
	Economy.notice.connect(on_notice)
	Economy.advance_days(7, "test")
	Economy.notice.disconnect(on_notice)
	check(Economy.cash() == MissionRegistry.setting_i("safety_floor_cash", 20000) and Economy.loans_owed() == roundi((100000 + up - left + MissionRegistry.setting_i("safety_floor_cash", 20000)) * 1.1)
		and notices.any(func(t: String) -> bool: return t.contains("Emergency loan")),
		"a bill beyond the cash: an emergency loan covers it and leaves the floor ($%d cash, $%d owed)" % [Economy.cash(), Economy.loans_owed()])
	Economy.wages_provider = func() -> Array: return [{"what": "Alpha", "amount": 1000}, {"what": "Bravo", "amount": 1500}]
	var bill := Economy.weekly_bill()
	var owed := Economy.loans_owed()
	check(bill.wages == 2500 and bill.loans == ceili(owed / 8.0), "wages as lines from the roster ($%d), and the loan installment ($%d)" % [bill.wages, bill.loans])
	Economy.add_cash(100000 - Economy.cash(), "test")
	Economy.advance_days(7, "test")
	check(Economy.loans_owed() == owed - bill.loans and Economy.cash() == 100000 - bill.total, "the installment comes off the loan")
	var lent := 0
	for i in 5:
		lent += Economy.server_take_loan()
	check(Economy.loans_owed() <= MissionRegistry.setting_i("loan_max", 150000) and Economy.server_take_loan() == 0 and lent > 0,
		"loans stop at the cap ($%d owed)" % Economy.loans_owed())
	check(Contracts.board().any(func(o: Dictionary) -> bool: return o.source == "safe" and int(o.rated) == 1), "the board always keeps a low-risk job")
	Economy.wages_provider = Callable()
	check(Economy.weekly_bill().wages == Prices.default_wage_bill(), "without a roster, the stand-in wage bill")


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
	# Weekly bills are listed once each, and a bought respawn costs money.
	Contracts.new_full_campaign(7, 500000)
	Economy.take_run_expenses()
	Economy.advance_days(14, "test")
	var weeks := Economy.take_run_expenses().filter(func(x: Dictionary) -> bool: return String(x.what).begins_with("Week "))
	check(weeks.size() == 2, "two weeks pass: two weekly bills listed")
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


## Wave 6c: persistent world (a hot zone's holder and grip outlive a deployment) and the
## faction war (a weak holder can lose the zone to one of its own listed enemies between
## missions), plus the war-driven offer that follows (Contracts.server_refresh_board).
func _test_world_sites() -> void:
	print("World sites: persistent holder, the faction war, and its offer")
	Campaign.section(WorldSites.SECTION).clear()
	var zid := "pass_hot"
	var h1 := WorldSites.holder(zid)
	check(h1 != "" and WorldSites.holder(zid) == h1, "a zone's holder is seeded once and stays stable (%s)" % h1)
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP), "a fresh site starts at full grip (%.2f)" % WorldSites.grip(zid))
	WorldSites.server_contract_won(zid, "nobody_holds_this")
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP), "a win against someone who doesn't hold it does nothing")
	WorldSites.server_contract_won(zid, h1)
	check(is_equal_approx(WorldSites.grip(zid), WorldSites.START_GRIP - WorldSites.WIN_GRIP_HIT), "a win against the actual holder knocks its grip down (%.2f)" % WorldSites.grip(zid))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	WorldSites.server_advance_days(1, rng)
	check(WorldSites.grip(zid) > WorldSites.START_GRIP - WorldSites.WIN_GRIP_HIT, "a quiet day repairs some of it back (%.2f)" % WorldSites.grip(zid))
	# Push it to contested, with a known holder that has a real hostile rival (black_ridge's
	# enemies include federal_army, the only other one that's also hostile-role), and keep it
	# there (repair only gets one day's grace before the next contract would knock it down
	# again) for up to 200 days: at 0.2/day, the faction war flipping it is a near-certainty.
	# Checks the mechanism, not a coin flip.
	h1 = "black_ridge"
	var s := Campaign.section(WorldSites.SECTION)
	rng.seed = 7
	for _day in 200:
		if String(s[zid].holder) != h1:
			break
		var site_d: Dictionary = s[zid]
		site_d.holder = h1
		site_d.grip = WorldSites.CONTESTED_GRIP
		s[zid] = site_d
		WorldSites.server_advance_days(1, rng)
	var h2 := WorldSites.holder(zid)
	check(h2 != h1 and h2 in MissionRegistry.enemies_of(h1), "weak and contested long enough, a listed rival takes it over (%s -> %s)" % [h1, h2])
	check(WorldSites.is_flashpoint(zid), "and it's flagged a flashpoint")
	Contracts.server_refresh_board()
	var board: Array = Campaign.section(Contracts.SECTION).get("board", [])
	var posted := board.filter(func(c: Dictionary) -> bool: return c.get("zone_id", "") == zid and c.get("war_driven", false))
	check(posted.size() == 1 and String(posted[0].target) == h2, "and posts its own offer on the board, against the new holder (%s)" % [posted.map(func(c: Dictionary) -> String: return c.title)])
	check(not WorldSites.is_flashpoint(zid), "clearing the flag once it has")


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
	# Hot zones (Captain 2026-10-15): staying pays more; several contracts live at once.
	var stayed := DebriefCalc.compute([c.merged({"zone_kind": "hot"}, true)], objs, 0, report.merged({"hazard_tier": 2}, true))
	var hazard: Array = (stayed.contracts[0].bonuses as Array).filter(func(b: Dictionary) -> bool: return String(b.text).begins_with("Hazard pay"))
	check(hazard.size() == 1 and int(hazard[0].amount) == roundi(100000 * HotZoneOps.HAZARD_SHARE_PER_TIER * 2) and stayed.contracts[0].pay == line.pay + int(hazard[0].amount),
		"a hot-zone contract done at pressure tier 2: hazard pay of %d%% on top ($%d)" % [roundi(HotZoneOps.HAZARD_SHARE_PER_TIER * 200), int(hazard[0].amount) if not hazard.is_empty() else 0])
	var plain := DebriefCalc.compute([c], objs, 0, report.merged({"hazard_tier": 2}, true))
	check(plain.contracts[0].pay == line.pay, "no hazard pay outside a hot zone")
	var targets := [1, 2, 3, 4].map(func(held: int) -> int: return HotZoneOps.live_target(7, 3, "ridge_hot", held))
	check(targets[0] >= HotZoneOps.LIVE_RANGE.x and targets[0] <= HotZoneOps.LIVE_RANGE.y and targets[0] == targets[1] and targets[2] == 3 and targets[3] == 4
		and HotZoneOps.live_target(7, 3, "ridge_hot", 1) == targets[0],
		"a hot zone keeps 3-6 contracts live: fewer taken are topped up (to %d, the same every time), 3 or more stay as taken" % targets[0])
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
	check(d.contracts[0].outcome == "completed" and Economy.cash() == cash + int(d.totals.paid_now) - (d.expenses as Array).reduce(func(a: int, l: Dictionary) -> int: return a + (int(l.amount) if bool(l.charge) else 0), 0) and int(d.totals.paid_now) > 0,
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
	check(d.contracts.size() == 3 and d.contracts.all(func(l: Dictionary) -> bool: return l.outcome == "completed") and Economy.cash() == cash + int(d.totals.paid_now) - (d.expenses as Array).reduce(func(a: int, l: Dictionary) -> int: return a + (int(l.amount) if bool(l.charge) else 0), 0)
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
