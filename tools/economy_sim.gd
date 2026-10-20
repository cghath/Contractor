extends Node
## Economy balance simulation (docs/economy_proposal_2026-10-20.md). Not a test suite: it never
## runs from tools/run_tests.sh or CI. It plays many short campaigns through the real economy
## code - the contract board (Contracts, ContractGen: pay, ratings, fixers, clawback terms, hot
## zones and their extra contracts), negotiation (ContractGen.deal), the debrief and its expenses
## (Contracts.server_end_deployment, DebriefCalc), the weekly bill and emergency loans (Economy),
## support calls (Economy.server_pay_support), salvage picks, intel sales, pallets (Pallets),
## the hiring board and wage growth (Hiring, Roster), shop sell prices (Prices) and the loot
## that really spawns (CompoundLevel.hostile_loadout, WorldValuables' site boxes) - with the
## fighting itself replaced by a play profile's dice: how often it wins, who gets hurt, how many
## supports it calls and how much it loots (PROFILES below; every number there is an assumption,
## stated in the proposal).
##
##   <voxel godot exe> --headless --path . res://tools/economy_sim.tscn -- [options]
##     --runs N        campaigns per profile (default 40)
##     --days N        campaign days each (default 35)
##     --variant V     current | proposed | both (default both)
##     --profile P     careful | median | sloppy | all (default all)
##     --seed N        first campaign seed (default 1)
##     --hot_win X     a hot-zone contract's win chance as a share of the profile's (default 0.92)
##     --hot_cap N     at most N contracts done per hot-zone deployment (default 0: no cap)
##
## It plays in a campaign of its own ("sim_economy"), never saved, so a real campaign save is
## never touched. Quits by itself (a script error would otherwise leave it idling).

const SQUAD_OUT := 6  # heads deployed: 2 players + 4 AI squadmates
const AI_OUT := 4
const ROSTER_SIZE := 8
const CHECKPOINTS := [0, 7, 14, 21, 28, 35]

## Play profiles. Every number is an assumption about how a squad plays (stated in the proposal),
## not something read from the game.
## - max_rated: the highest briefed rating it takes; hot: whether it takes hot-zone work.
## - terms: how it spends its negotiation points (spare points go to pay).
## - win: chance a contract's required objectives get done, by true rating 1-5; opt: an optional one.
## - kia: expected AI squadmates killed per deployment = kia[0] + kia[1] x true rating; bodies:
##   chance a dead squadmate's body (and kit) is brought home.
## - wounded: expected wounded per deployment; deaths: expected player deaths (respawns).
## - supports: {kind: chance it's called once per deployment}; heli_loss: chance a called
##   helicopter is shot down; aav and allied troops are never "lost" (no lost_supports price).
## - carry: items from the dead it carries out (the most valuable first), boxes: share of the
##   target site's loot boxes it opens, extra_modules: other sites it searches, scatter: dead
##   drops / caches out in the open it finds, officer_intel: chance of an officer's intel.
## - intel: "sell" (to another faction), "half" (sell every other piece) or "turn_in".
## - pallets: "keep" (FOB stocks), "sell" or "" (not tagged); vehicles: chance it tags a site vehicle.
## - civ: chance of a civilian casualty per deployment; hazard: hot-zone pressure tier reached.
const PROFILES := {
	"careful": {"max_rated": 3, "hot": false, "terms": {"salvage_points": 2, "support_points": 1},
		"win": [0.97, 0.95, 0.92, 0.85, 0.75], "opt": 0.7, "kia": [0.05, 0.04], "bodies": 0.9, "wounded": 0.8, "deaths": 1.0,
		"supports": {"transport": 0.5, "extraction": 0.5}, "heli_loss": 0.02,
		"carry": 12, "boxes": 1.0, "extra_modules": 1, "scatter": 2, "officer_intel": 0.6,
		"intel": "sell", "pallets": "keep", "vehicles": 0.6, "civ": 0.02, "hazard": 1},
	"median": {"max_rated": 4, "hot": true, "terms": {"salvage_points": 1, "support_points": 1},
		"win": [0.93, 0.88, 0.82, 0.72, 0.6], "opt": 0.5, "kia": [0.1, 0.1], "bodies": 0.6, "wounded": 1.5, "deaths": 3.0,
		"supports": {"transport": 0.7, "extraction": 0.7, "resupply": 0.4, "medevac": 0.3}, "heli_loss": 0.05,
		"carry": 6, "boxes": 0.7, "extra_modules": 0, "scatter": 1, "officer_intel": 0.4,
		"intel": "half", "pallets": "sell", "vehicles": 0.3, "civ": 0.08, "hazard": 1},
	"sloppy": {"max_rated": 5, "hot": true, "terms": {"support_points": 2},
		"win": [0.85, 0.78, 0.68, 0.55, 0.42], "opt": 0.3, "kia": [0.3, 0.2], "bodies": 0.3, "wounded": 2.5, "deaths": 6.0,
		"supports": {"transport": 1.0, "extraction": 1.0, "resupply": 0.8, "medevac": 0.8, "aav": 0.3, "allied_troops": 0.2}, "heli_loss": 0.1,
		"carry": 2, "boxes": 0.3, "extra_modules": 0, "scatter": 0, "officer_intel": 0.2,
		"intel": "turn_in", "pallets": "", "vehicles": 0.0, "civ": 0.2, "hazard": 2},
}
## Contract types played quietly: fewer of the enemy die (and less is left to loot).
const STEALTHY := ["recon", "sabotage", "intel_grab"]
## A scenario contract's objectives come from its live scenario (not built headless): the sim
## stands in one required objective and the scenario's bonus (its *_bonus_share knob).
const SCENARIO_BONUS_KNOBS := ["cargo_bonus_share", "all_bonus_share", "unseen_bonus_share", "unhurt_bonus_share"]

## The proposed numbers (docs/economy_proposal_2026-10-20.md). "prices" and "settings" override
## data/prices.json and data/contracts.json "settings" in memory; "sim" are proposed rules that
## need a code change, modelled here (see the proposal for where each would go).
const PROPOSED := {
	"prices": {
		"lost_supports": {"resupply": 15000, "transport": 15000, "extraction": 15000, "medevac": 15000, "cargo": 15000},
		"respawn_rise": 0.25,
		"operations": {"per_head_day": 700, "kia_benefit": 10000, "wounded_care": 1200},
	},
	"settings": {
		"difficulty_pay": [0, 0.35, 0.5, 0.6, 0.75, 0.95],
		"hot_zone_pay_mult": 1.0,
		"clean_bonus_share": 0.05,
	},
	"sim": {
		"daily_bill": true,           # wages and upkeep charged each day (a 7th of the week's), so each debrief carries its own
		"intel_by_value": 1.0,        # an intel piece sells for its intel_value (data/items.json) instead of the flat intel_sale_price
		"arrival_no_advance": true,   # a hot zone's arrival contracts pay nothing up front: all of it on completion
		"respawn_cap": 8000,          # a bought respawn never costs more than this (prices.json "respawn_max")
	},
}

var _orig_prices: Dictionary
var _orig_settings: Dictionary
var _acc: Dictionary = {}
var _variant: Dictionary = {}
var _roster: Array = []
var _hire_refresh := 0
var _rng := RandomNumberGenerator.new()
var _hot_win := 0.92  # --hot_win: a hot-zone contract's win chance, as a share of the profile's
var _hot_cap := 0  # --hot_cap: at most this many contracts done per hot deployment (0: no cap)


func _ready() -> void:
	get_tree().create_timer(1800.0).timeout.connect(func() -> void: get_tree().quit(2))
	await get_tree().process_frame  # the autoloads' deferred hook-ups first
	Campaign.campaign_id = "sim_economy"  # never a real save (and autosave is off)
	Contracts.autosave = false
	Contracts.auto_show_debrief = false
	_orig_prices = Prices.data().duplicate(true)
	_orig_settings = (MissionRegistry.data().get("settings", {}) as Dictionary).duplicate(true)
	Economy.week_paid.connect(_on_week_paid)
	var args := _args()
	var runs := int(args.get("runs", 40))
	var days := int(args.get("days", 35))
	var first_seed := int(args.get("seed", 1))
	_hot_win = float(args.get("hot_win", _hot_win))
	_hot_cap = int(args.get("hot_cap", _hot_cap))
	var variants: Array = ["current", "proposed"] if String(args.get("variant", "both")) == "both" else [String(args.variant)]
	var profiles: Array = PROFILES.keys() if String(args.get("profile", "all")) == "all" else [String(args.profile)]
	print("ECONOMY SIM: %d runs x %d days per profile; variants %s; hot_win %.2f, hot_cap %d" % [runs, days, variants, _hot_win, _hot_cap])
	_print_kit_values()
	for v: String in variants:
		for p: String in profiles:
			_run_profile(p, v, runs, days, first_seed)
	get_tree().quit(0)


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out


# --- Variants ---------------------------------------------------------------------------------

func _apply_variant(v: String) -> void:
	Prices._data = _orig_prices.duplicate(true)
	MissionRegistry.data()["settings"] = _orig_settings.duplicate(true)
	_variant = {}
	if v != "proposed":
		return
	for k: String in PROPOSED.prices:
		Prices._data[k] = (PROPOSED.prices[k] as Variant).duplicate(true) if PROPOSED.prices[k] is Dictionary else PROPOSED.prices[k]
	for k: String in PROPOSED.settings:
		MissionRegistry.data().settings[k] = (PROPOSED.settings[k] as Variant).duplicate(true) if PROPOSED.settings[k] is Array else PROPOSED.settings[k]
	_variant = (PROPOSED.sim as Dictionary).duplicate(true)
	if _variant.has("sell_ratio"):
		Prices._data["sell_ratio"] = float(_variant.sell_ratio)
	if _variant.get("daily_bill", false):
		# Emulates billing every day with the real Economy.pay_week: a "week" of one day, upkeep a
		# 7th, loan installments spread over the same 8 weeks.
		var s: Dictionary = MissionRegistry.data().settings
		s["loan_weeks"] = int(s.get("loan_weeks", 8)) * int(_orig_settings.get("week_days", 7))
		s["week_days"] = 1
		Prices._data["weekly_upkeep"] = roundi(float(_orig_prices.get("weekly_upkeep", 0)) / float(_orig_settings.get("week_days", 7)))


func _week_days() -> int:
	return maxi(MissionRegistry.setting_i("week_days", 7), 1)


# --- One profile ------------------------------------------------------------------------------

func _run_profile(pname: String, v: String, runs: int, days: int, first_seed: int) -> void:
	_apply_variant(v)
	var prof: Dictionary = PROFILES[pname]
	var totals := {}
	var cash_at := {}
	var worth_at := {}
	var deploys: Array = []
	var bankrupt := 0
	var min_cash: Array = []
	for r in runs:
		var res := _run_campaign(prof, first_seed + r, days)
		for k: String in res.acc:
			totals[k] = float(totals.get(k, 0.0)) + float(res.acc[k])
		for d: int in res.cash_at:
			if not cash_at.has(d):
				cash_at[d] = []
				worth_at[d] = []
			cash_at[d].append(res.cash_at[d])
			worth_at[d].append(res.worth_at[d])
		deploys.append_array(res.deploys)
		min_cash.append(res.min_worth)
		if res.broke:
			bankrupt += 1
	_report(pname, v, runs, totals, cash_at, worth_at, deploys, bankrupt, min_cash)


func _run_campaign(prof: Dictionary, campaign_seed: int, days: int) -> Dictionary:
	_rng.seed = hash([campaign_seed, "sim"])
	seed(hash([campaign_seed, "global"]))  # server_sell_intel's randf() (caught or not)
	_acc = {}
	Contracts.new_full_campaign(campaign_seed)
	_hire_refresh = 0
	_roster = []
	Economy.wages_provider = func() -> int:
		var total := 0
		for m: Dictionary in _roster:
			total += int(m.wage)
		return total * _week_days()
	_harvest("")
	while _roster.size() < ROSTER_SIZE:
		_hire_one()
	_harvest("")
	var start_day := Economy.day()
	var cash_at := {0: Economy.cash()}
	var worth_at := {0: Economy.cash() - Economy.loans_owed()}
	var deploys: Array = []
	var min_worth := Economy.cash()
	var broke := false
	var guard := 0
	while Economy.day() - start_day < days and guard < 200:
		guard += 1
		var before_day := Economy.day()
		var d := _deploy(prof)
		if d.is_empty():
			Economy.advance_days(1, "waiting for work")
			_harvest("")
		else:
			deploys.append(d)
		for cp: int in CHECKPOINTS:
			if not cash_at.has(cp) and Economy.day() - start_day >= cp and cp > 0:
				cash_at[cp] = Economy.cash()
				worth_at[cp] = Economy.cash() - Economy.loans_owed()
		min_worth = mini(min_worth, Economy.cash() - Economy.loans_owed())
		if Economy.cash() < 0 and Economy.loan_room() <= 0:
			broke = true
		if Economy.day() == before_day:
			Economy.advance_days(1, "sim")
	for cp: int in CHECKPOINTS:
		if not cash_at.has(cp):
			cash_at[cp] = Economy.cash()
			worth_at[cp] = Economy.cash() - Economy.loans_owed()
	Economy.wages_provider = Callable()
	return {"acc": _acc.duplicate(), "cash_at": cash_at, "worth_at": worth_at, "deploys": deploys, "min_worth": min_worth, "broke": broke}


# --- Hiring -----------------------------------------------------------------------------------

func _hire_one() -> void:
	var pool := Hiring.draw_pool(int(hash(["sim_hire", Economy.day()])), _hire_refresh)
	_hire_refresh += 1
	var c: Dictionary = pool[0]
	for cand: Dictionary in pool:
		if int(cand.missions) <= 9 and int(cand.fee) < int(c.fee):
			c = cand
	if not Economy.spend(int(c.fee), "Hired %s" % c.name):
		Economy.add_cash(-int(c.fee), "Hired %s (into debt: the sim keeps the roster full)" % c.name)
	var m := c.duplicate(true)
	m.erase("cid")
	_roster.append(m)


# --- One deployment ---------------------------------------------------------------------------

func _contracts_section() -> Dictionary:
	return Campaign.section(Contracts.SECTION)


func _pick_contract(prof: Dictionary) -> Dictionary:
	var best := {}
	var best_score := -1.0
	for c: Dictionary in _contracts_section().board:
		var src := String(c.get("source", ""))
		if src in ["locals", "recovery"]:
			continue
		if int(c.rated) > int(prof.max_rated):
			continue
		if String(c.zone_kind) == "hot" and not bool(prof.hot):
			continue
		if Economy.work_problem(String(c.employer)) != "":
			continue
		var days := int(c.days) + int(MissionRegistry.region(String(c.get("region", ""))).get("travel_days", 0))
		var score := float(c.base_pay) / maxf(days, 1.0) * (2.5 if String(c.zone_kind) == "hot" else 1.0)  # a hot zone hands out 3-6 contracts
		if score > best_score:
			best_score = score
			best = c
	return best


func _terms(prof: Dictionary, employer: String) -> Dictionary:
	var t := ContractGen.default_terms()
	var points := ContractGen.max_points(Economy.reputation(employer))
	for k: String in prof.terms:
		var n := mini(int(prof.terms[k]), points)
		if k == "salvage_points":
			while n > 0 and ContractGen.S("salvage_base") + n * ContractGen.S("salvage_per_point") > ContractGen.S("salvage_max") + 0.001:
				n -= 1
		t[k] = n
		points -= n
	t.pay_points = int(t.pay_points) + points
	return t


func _deploy(prof: Dictionary) -> Dictionary:
	var c := _pick_contract(prof)
	if c.is_empty():
		return {}
	var cash0 := Economy.cash()
	var acc0 := _acc.duplicate()
	var cid := String(c.cid)
	if Contracts.server_accept(cid, _terms(prof, String(c.employer))) != "":
		return {}
	_harvest("")
	var why := Contracts.server_start_deployment([cid])
	if why != "":
		push_error("sim: could not deploy on %s: %s" % [cid, why])
		return {}
	_harvest("")
	var s := _contracts_section()
	var dep: Dictionary = s.deployment
	var deployed: Array = (s.held as Array).filter(func(x: Dictionary) -> bool: return x.cid in dep.cids)
	var hot := String(dep.zone_kind) == "hot"
	var kind := "hot" if hot else "contract"
	if hot:
		Contracts.server_note_deployment("hazard_tier", int(prof.hazard))
	if _variant.get("arrival_no_advance", false):
		# Proposed (a code change in Contracts._hot_zone_extras): an arrival contract's advance
		# moves into its completion pay. Modelled by handing the advance back at once.
		for x: Dictionary in deployed:
			if String(x.get("in_zone", "")) == "arrival" and int(x.deal.advance) > 0:
				Economy.add_cash(-int(x.deal.advance), "Advance: %s (moved to completion)" % x.title)
				x.deal.completion = int(x.deal.completion) + int(x.deal.advance)
				x.deal.advance = 0
		_harvest("")
	var arrival_advance := 0  # what the hot zone's arrival contracts paid up front, kept whatever happens next
	for x: Dictionary in deployed:
		if String(x.get("in_zone", "")) == "arrival":
			arrival_advance += int(x.deal.advance)
	var rating := 1
	for x: Dictionary in deployed:
		rating = maxi(rating, int(x.true_rating))
	# The fighting's dice: objectives.
	# (Through Objectives' own calls: they keep the campaign's copy, which the list is restored from.)
	var objectives: Objectives = Contracts.objectives
	var hot_done := 0
	for x: Dictionary in deployed:
		var mine := objectives.for_contract(String(x.cid))
		if mine.filter(func(o: Dictionary) -> bool: return not o.optional).is_empty():
			var share := 0.1
			var knobs: Dictionary = MissionRegistry.type_def(String(x.type)).get("scenario_knobs", {})
			for k: String in SCENARIO_BONUS_KNOBS:
				if knobs.has(k):
					share = float(knobs[k])
			objectives.server_add([
				{"oid": "%s_sim1" % x.cid, "cid": x.cid, "kind": "scenario", "text": "scenario", "state": Objectives.ACTIVE, "optional": false, "bonus_share": 0.0, "progress": "", "params": {}, "pos": Vector3.ZERO},
				{"oid": "%s_sim2" % x.cid, "cid": x.cid, "kind": "scenario", "text": "Bonus: scenario", "state": Objectives.ACTIVE, "optional": true, "bonus_share": share, "progress": "", "params": {}, "pos": Vector3.ZERO}])
		var won := _rng.randf() < float(prof.win[clampi(int(x.true_rating), 1, 5) - 1]) * (_hot_win if hot else 1.0)
		if hot and _hot_cap > 0 and hot_done >= _hot_cap:
			won = false
		if won:
			hot_done += 1
		for o: Dictionary in objectives.for_contract(String(x.cid)):
			var done: bool = won and (not o.optional or _rng.randf() < float(prof.opt))
			objectives.server_set_state(String(o.oid), Objectives.DONE if done else Objectives.FAILED)
	if _rng.randf() < float(prof.civ):
		dep.civilians = int(dep.civilians) + 1
	# Supports, lost helicopters, respawns: charged as they happen (the real calls).
	for k: String in prof.supports:
		if _rng.randf() < float(prof.supports[k]) * (1.5 if hot else 1.0):
			if Economy.server_pay_support(k, cid) and Prices.lost_support_price(k) > 0 and _rng.randf() < float(prof.heli_loss):
				Economy.charge_run(roundi(Prices.lost_support_price(k) * HeliUpgrades.lost_mult(k)), "Lost helicopter (%s support): replacement" % k)
	_harvest("")
	var deaths := _poisson(float(prof.deaths) * (1.5 if hot else 1.0))
	var free := int(RosterDeployment.FREE_RESPAWNS.get(kind, 4))
	var bought := 0
	for i in deaths:
		if i < free:
			continue
		var cost := roundi(Prices.respawn_price() * (1.0 + Prices.respawn_rise() * bought))
		if _variant.has("respawn_cap"):
			cost = mini(cost, int(_variant.respawn_cap))
		bought += 1
		# As BaseHub.server_count_respawn: cash first, then the support budget, then on credit.
		var from_cash := clampi(Economy.cash(), 0, cost)
		var from_budget := Contracts.server_draw_support(cid, cost - from_cash) if cost > from_cash else 0
		if from_cash > 0:
			Economy.charge_run(from_cash, "Respawn")
		if cost - from_cash - from_budget > 0:
			Economy.charge_run(cost - from_cash - from_budget, "Respawn on credit")
	_harvest("")
	# Casualties among the AI squadmates.
	var kia_expect := float(prof.kia[0]) + float(prof.kia[1]) * rating
	var out_ai: Array = []
	var pool := _roster.duplicate()
	pool.shuffle()
	for i in mini(AI_OUT, pool.size()):
		out_ai.append(pool[i])
	var dead: Array = []
	for m: Dictionary in out_ai:
		if _rng.randf() < kia_expect / AI_OUT:
			dead.append(m)
	var casualties: Array = []
	var extracted: Array = []
	for i in SQUAD_OUT - dead.size():
		extracted.append("S%d" % i)
	for m: Dictionary in dead:
		casualties.append({"name": String(m.name), "status": "kia"})
	var wounded := mini(_poisson(float(prof.wounded) * (1.3 if hot else 1.0)), extracted.size())
	for i in wounded:
		casualties.append({"name": extracted[i], "status": "wounded"})
	# Loot: the dead enemy's kit (the real hostile loadouts), what the squad carries out, the
	# site's loot boxes (the real rolls), dead drops, an officer's intel and the objective intel.
	var field: Array = []
	var bank: Array = []
	var kills := 0
	for x: Dictionary in deployed:
		var share := 0.4 if String(x.type) in STEALTHY else 0.9
		var reinf := 0 if String(x.type) in STEALTHY else roundi(2.0 * lerpf(2.0, 4.0, (int(x.true_rating) - 1) / 4.0) * 0.6)
		kills += roundi(int(x.enemy_count) * share) + reinf
	var enemy_items: Array = []
	for i in kills:
		for id: Variant in CompoundLevel.hostile_loadout(i):
			var st := {}
			if String(id).begins_with("plate_"):
				st = {"integrity": snappedf(_rng.randf_range(0.3, 1.0), 0.01)}
			enemy_items.append({"id": String(id), "count": 1, "state": st})
	enemy_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Prices.value_of(StringName(a.id), 1, a.state) > Prices.value_of(StringName(b.id), 1, b.state))
	for i in enemy_items.size():
		if i < int(prof.carry):
			bank.append(enemy_items[i])
		else:
			field.append(enemy_items[i])
	for m: Dictionary in dead:
		var kit: Array = []
		for pair: Array in Roles.kit(StringName(m.role)):
			kit.append({"id": String(pair[0]), "count": int(pair[1]), "state": {}})
		if _rng.randf() < float(prof.bodies):
			bank.append_array(kit)
		else:
			field.append_array(kit)
	var modules: Array = []
	var layout: Array = MissionRegistry.zone_def(String(dep.zone_id)).get("modules", [])
	for x: Dictionary in deployed:
		if String(x.get("module_id", "")) != "":
			modules.append({"id": String(x.module_id), "type": String(x.module), "share": float(prof.boxes)})
	var extra := int(prof.extra_modules)
	for m: Dictionary in layout:
		if extra <= 0:
			break
		if not modules.any(func(e: Dictionary) -> bool: return e.id == String(m.get("id", ""))):
			modules.append({"id": String(m.get("id", "")), "type": String(m.get("type", "")), "share": float(prof.boxes)})
			extra -= 1
	for m: Dictionary in modules:
		bank.append_array(_site_boxes(m, prof))
	for i in int(prof.scatter):
		bank.append_array(_scatter_find())
	if _rng.randf() < float(prof.officer_intel):
		bank.append({"id": "intel_documents" if _rng.randf() < 0.5 else "intel_phone", "count": 1, "state": {}})
	for x: Dictionary in deployed:
		for o: Dictionary in objectives.for_contract(String(x.cid)).filter(func(o: Dictionary) -> bool: return o.state == Objectives.DONE):
			for it: Variant in (o.get("params", {}) as Dictionary).get("items", []):
				if MissionRegistry.is_intel(StringName(it)):
					bank.append({"id": String(it), "count": 1, "state": {}})
	var tagged: Array = []
	if String(prof.pallets) != "":
		for x: Dictionary in deployed:
			for p: Dictionary in Pallets.sites(String(x.module)):
				tagged.append(Pallets.pallet_lot(String(p.kind), "%s_%s_%d" % [x.cid, p.kind, _rng.randi()]))
	for x: Dictionary in deployed:
		for veh: Dictionary in Pallets.site_vehicles(String(x.module)):
			if _rng.randf() < float(prof.vehicles):
				tagged.append(Pallets.vehicle_lot(String(veh.model), false, "%s_veh_%d" % [x.cid, _rng.randi()], String(veh.model)))
	var report := {"items": [], "bank": bank, "field_items": field, "extracted": extracted, "casualties": casualties, "tagged": tagged}
	var debrief := Contracts.server_end_deployment(report)
	if OS.get_environment("ECONOMY_SIM_DEBUG") != "":
		print("sim debrief: ", (debrief.contracts as Array).map(func(l: Dictionary) -> String: return "%s %s %s" % [l.cid, l.outcome, l.objectives]))
	_split_debrief(debrief)
	_harvest("")
	# Loot carried out goes to the base inbox: sold (contraband to the fixer).
	_sell_inbox("loot")
	# The debrief: salvage picks (the "claim best value" helper), intel, pallets.
	var d: Dictionary = _contracts_section().debrief
	for i: int in DebriefCalc.best_value_picks(d):
		Contracts.server_pick_salvage(i)
	var intel: Array = d.intel
	for i in intel.size():
		var sell := String(prof.intel) == "sell" or (String(prof.intel) == "half" and i % 2 == 0)
		if sell:
			var buyer := _intel_buyer(Contracts.debrief_client())
			if buyer != "":
				if _variant.has("intel_by_value"):
					var item := ItemDB.get_item(StringName(intel[i].id))
					MissionRegistry.data().settings["intel_sale_price"] = roundi(float(item.stats.get("intel_value", 1000)) * float(_variant.intel_by_value))
				Contracts.server_sell_intel(i, buyer)
	_harvest("intel")
	for i in (d.get("tagged", []) as Array).size():
		var lot: Dictionary = d.tagged[i]
		var act := "sell" if String(lot.kind) == "vehicle" or String(prof.pallets) == "sell" else "keep"
		Contracts.server_pallet("debrief", i, act)
	_harvest("pallets")
	Contracts.server_finish_debrief()
	_harvest("")
	_sell_inbox("salvage")
	# The roster: the dead replaced (the hiring fee), the rest a mission older (wages grow).
	for m: Dictionary in dead:
		_roster.erase(m)
	for m: Dictionary in out_ai:
		if not m in dead:
			Roster.after_mission(m, _rng, Economy.day())
	while _roster.size() < ROSTER_SIZE:
		_hire_one()
	_harvest("")
	var delta := {}
	for k: String in _acc:
		delta[k] = float(_acc[k]) - float(acc0.get(k, 0.0))
	# Its economic result: every income and expense line but the bills and loans, less its own
	# days' share of wages and upkeep (so a weekly bill falling due mid-deployment doesn't count
	# against that one deployment).
	var days := int(debrief.days)
	var econ := -_fixed_daily() * days
	for k: String in INCOME + EXPENSES:
		if not k in ["wages", "upkeep", "loan_repay"]:
			econ += float(delta.get(k, 0.0))
	return {"rating": rating, "hot": hot, "days": days, "cash_delta": Economy.cash() - cash0, "net_shown": int(debrief.get("net", 0)),
		"econ_net": econ, "delta": delta, "arrival_advance": arrival_advance,
		"completed": (debrief.contracts as Array).filter(func(l: Dictionary) -> bool: return l.outcome == "completed").size(),
		"contracts": (debrief.contracts as Array).size()}


## Wages plus upkeep per day, as the bill stands.
func _fixed_daily() -> float:
	var wages := 0
	for m: Dictionary in _roster:
		wages += int(m.wage)
	return wages + float(_orig_prices.get("weekly_upkeep", 0)) / 7.0


func _intel_buyer(client: String) -> String:
	var best := ""
	for f: String in MissionRegistry.employers():
		if f != client and (best == "" or Economy.reputation(f) > Economy.reputation(best)):
			best = f
	return best


## A module's loot boxes, as WorldValuables.server_spawn_site_boxes rolls them (same seed, same
## contents), each opened with the profile's chance; an HQ's strongbox when its share is full.
func _site_boxes(m: Dictionary, prof: Dictionary) -> Array:
	var out: Array = []
	var spots: Array = ZoneModules.LOOT.get(String(m.type), [])
	if spots.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|valbox" % String(m.id))
	var count := mini(WorldValuables._site_box_count(rng, String(m.type)), mini(spots.size(), WorldValuables.SITE_BOX_OFFSETS.size()))
	for k in count:
		var contents := WorldValuables._roll_site_box(rng)
		var box_id := "%s_valbox%d" % [String(m.id), k]
		var mt := String(m.type)
		if (mt in WorldValuables.CONTRABAND_TYPES or ZoneModules.base(mt) in WorldValuables.CONTRABAND_TYPES) and contents.size() == 1 \
				and String(contents[0].id) not in WorldValuables.RARE_GUNS and posmod(hash("contraband:" + box_id), 100) < WorldValuables.CONTRABAND_PCT:
			contents = [{"id": WorldValuables.CONTRABAND_ITEMS[posmod(hash("contraband_kind:" + box_id), WorldValuables.CONTRABAND_ITEMS.size())], "count": 1}]
		if _rng.randf() < float(m.share):
			for e: Dictionary in contents:
				out.append({"id": String(e.id), "count": int(e.count), "state": {}})
	if String(m.type) == "hq" and float(m.share) >= 1.0:
		for e: Dictionary in WorldValuables.strongbox_contents(String(m.id)):
			out.append({"id": String(e.id), "count": int(e.count), "state": {}})
	return out


## A find out in the open, as WorldValuables._spawn_site rolls one: a dead drop (intel or a
## valuable) or a small cache (a gun, its mags, salvage or medical).
func _scatter_find() -> Array:
	if _rng.randf() < WorldValuables.DEAD_DROP_SHARE:
		var pool := WorldValuables.INTEL_ITEMS if _rng.randf() < 0.5 else WorldValuables.VALUABLE_ITEMS
		return [{"id": pool[_rng.randi() % pool.size()], "count": 1, "state": {}}]
	var gun := WorldValuables.CACHE_GUNS[_rng.randi() % WorldValuables.CACHE_GUNS.size()]
	var kit: Array = CompoundLevel.HOSTILE_GUNS.get(gun, [gun])
	var items: Array = [{"id": gun, "count": 1, "state": {}}]
	if kit.size() > 1:
		items.append({"id": String(kit[1]), "count": kit.size() - 1, "state": {}})
	var extra := WorldValuables.SALVAGE_ITEMS[_rng.randi() % WorldValuables.SALVAGE_ITEMS.size()] if _rng.randf() < 0.4 \
		else WorldValuables.CACHE_MEDICAL[_rng.randi() % WorldValuables.CACHE_MEDICAL.size()]
	items.append({"id": extra, "count": 1, "state": {}})
	return items


## Sells everything waiting in the base inbox (the loot banked, or the salvage picks): contraband
## to the fixer who buys it (Fixers.offer, its reputation as Fixers.server_sell gives it), the
## rest at the shop (Economy.server_sell). Intel stays (it was sold or turned in already).
func _sell_inbox(tag: String) -> void:
	for e: Dictionary in Economy.take_unbanked():
		var id := StringName(e.id)
		if MissionRegistry.is_intel(id) or not ItemDB.has_item(id):
			continue
		var fixer := Fixers.buyer()
		if Fixers.is_contraband(id) and not fixer.is_empty():
			Economy.add_cash(Fixers.offer(id, int(e.count)), "Sold %d x %s to %s" % [int(e.count), String(id), String(fixer.fixer)])
			Economy.change_reputation(String(fixer.faction), int(fixer.get("buy_rep", 1)), "contraband sold")
			_harvest("contraband")
		else:
			Economy.server_sell(id, int(e.count), e.get("state", {}))
	_harvest(tag)


# --- Book-keeping -------------------------------------------------------------------------------

func _on_week_paid(_week: int, bill: Dictionary) -> void:
	_add("wages", -float(bill.wages))
	_add("upkeep", -float(bill.upkeep))
	_add("loan_repay", -float(bill.loans))


func _add(key: String, amount: float) -> void:
	_acc[key] = float(_acc.get(key, 0.0)) + amount


## The debrief's own split: contract pay (advance, completion), bonuses (in the completion
## entries), and its expense lines charged now (field costs, death benefits, treatment).
func _split_debrief(d: Dictionary) -> void:
	_add("bonuses", float(d.totals.bonuses))
	_add("completion", -float(d.totals.bonuses))  # the completion ledger entries include them
	for l: Dictionary in d.get("expenses", []):
		if not bool(l.get("charge", false)):
			continue
		var what := String(l.what)
		var key := "field_costs" if what.begins_with("Field costs") or what.begins_with("Covered by FOB") else "kia_benefit" if what.begins_with("Death benefit") else "treatment"
		_add(key, -float(l.amount))


## Moves the economy's new ledger entries into the sums by what they were ("Sold" ones under
## `tag`), and clears the ledger.
func _harvest(tag: String) -> void:
	var ledger: Array = Campaign.section(Economy.SECTION).get("ledger", [])
	for e: Dictionary in ledger:
		var what := String(e.what)
		var amount := float(e.amount)
		var key := "other"
		if what.begins_with("Advance clawed back"):
			key = "clawback"
		elif what.begins_with("Advance:"):
			key = "advance"
		elif what.begins_with("Completion:"):
			key = "completion"
		elif what.begins_with("Civilian fines"):
			key = "fines"
		elif what.begins_with("Deployment costs") or what.begins_with("Week "):
			continue  # split by _split_debrief / _on_week_paid
		elif what.to_lower().begins_with("emergency loan") or what.to_lower().begins_with("loan from"):
			key = "loans_in"
		elif what.begins_with("Support call") or what.begins_with("Support refund"):
			key = "supports"
		elif what.begins_with("Lost helicopter"):
			key = "lost_heli"
		elif what.begins_with("Respawn"):
			key = "respawns"
		elif what.begins_with("Hired"):
			key = "hiring"
		elif what.begins_with("Intel sold"):
			key = "intel"
		elif what.begins_with("Sold") or what.begins_with("Kept"):
			key = tag if tag != "" else "sold_other"
		_add(key, amount)
	ledger.clear()


func _poisson(mean: float) -> int:
	var l := exp(-mean)
	var k := 0
	var p := 1.0
	while true:
		p *= _rng.randf()
		if p <= l:
			return k
		k += 1
	return k


# --- Output -------------------------------------------------------------------------------------

const INCOME := ["advance", "completion", "bonuses", "loot", "salvage", "intel", "contraband", "pallets"]
const EXPENSES := ["wages", "upkeep", "field_costs", "kia_benefit", "treatment", "supports", "lost_heli", "respawns", "hiring", "fines", "clawback", "loan_repay"]


func _report(pname: String, v: String, runs: int, totals: Dictionary, cash_at: Dictionary, worth_at: Dictionary, deploys: Array, bankrupt: int, min_worth: Array) -> void:
	print("")
	print("=== %s / %s (%d campaigns) ===" % [pname, v, runs])
	var line := "cash by day (mean / p10 / p90), cash less loans owed in []:"
	print(line)
	for cp: int in CHECKPOINTS:
		if cash_at.has(cp):
			print("  day %2d: %s / %s / %s   [%s]" % [cp, _k(_mean(cash_at[cp])), _k(_pct(cash_at[cp], 0.1)), _k(_pct(cash_at[cp], 0.9)), _k(_mean(worth_at[cp]))])
	var income := 0.0
	for k: String in INCOME:
		income += float(totals.get(k, 0.0))
	print("income per campaign: %s" % _k(income / runs))
	for k: String in INCOME:
		print("  %-12s %s  %4.1f%%" % [k, _k(float(totals.get(k, 0.0)) / runs), 100.0 * float(totals.get(k, 0.0)) / maxf(income, 1.0)])
	var spent := 0.0
	for k: String in EXPENSES:
		spent -= float(totals.get(k, 0.0))
	print("expenses per campaign: %s" % _k(spent / runs))
	for k: String in EXPENSES:
		print("  %-12s %s  %4.1f%%" % [k, _k(-float(totals.get(k, 0.0)) / runs), 100.0 * -float(totals.get(k, 0.0)) / maxf(spent, 1.0)])
	print("  (loans taken %s per campaign; other %s)" % [_k(float(totals.get("loans_in", 0.0)) / runs), _k(float(totals.get("other", 0.0)) / runs)])
	var nets: Array = deploys.map(func(d: Dictionary) -> float: return float(d.econ_net))
	var shown: Array = deploys.map(func(d: Dictionary) -> float: return float(d.net_shown))
	var neg_shown := shown.filter(func(x: float) -> bool: return x < 0).size()
	var neg_net := nets.filter(func(x: float) -> bool: return x < 0).size()
	var done := 0
	var total_c := 0
	for d: Dictionary in deploys:
		done += int(d.completed)
		total_c += int(d.contracts)
	print("deployments: %.1f per campaign, %d%% of contracts completed, %d%% hot" % [float(deploys.size()) / runs, roundi(100.0 * done / maxf(total_c, 1)),
		roundi(100.0 * deploys.filter(func(d: Dictionary) -> bool: return d.hot).size() / maxf(deploys.size(), 1))])
	print("  economic net per deployment (all cash in and out, its days' wages and upkeep): mean %s, p10 %s, worst %s, %d%% negative" % [
		_k(_mean(nets)), _k(_pct(nets, 0.1)), _k(_pct(nets, 0.0)), roundi(100.0 * neg_net / maxf(nets.size(), 1))])
	print("  debrief 'net after expenses' as shown: mean %s, p10 %s, worst %s, %d%% negative" % [_k(_mean(shown)), _k(_pct(shown, 0.1)), _k(_pct(shown, 0.0)), roundi(100.0 * neg_shown / maxf(shown.size(), 1))])
	# Mean per-deployment line items.
	var per := {}
	for d: Dictionary in deploys:
		for k: String in d.delta:
			per[k] = float(per.get(k, 0.0)) + float(d.delta[k])
	var parts := PackedStringArray()
	for k: String in INCOME + EXPENSES:
		if absf(float(per.get(k, 0.0))) > 0.5:
			parts.append("%s %s" % [k, _k(float(per[k]) / maxf(deploys.size(), 1))])
	print("  mean per deployment: " + ", ".join(parts))
	var worst := {}
	for d: Dictionary in deploys:
		if worst.is_empty() or float(d.econ_net) < float(worst.econ_net):
			worst = d
	if not worst.is_empty():
		var wparts := PackedStringArray()
		for k: String in INCOME + EXPENSES:
			if absf(float(worst.delta.get(k, 0.0))) > 0.5:
				wparts.append("%s %s" % [k, _k(float(worst.delta[k]))])
		print("  worst deployment (%s, rating %d, %d days, %d of %d contracts done): %s" % ["hot" if worst.hot else "contract", int(worst.rating), int(worst.days),
			int(worst.completed), int(worst.contracts), ", ".join(wparts)])
	# By rating.
	for r in range(1, 6):
		var of_r := deploys.filter(func(d: Dictionary) -> bool: return int(d.rating) == r)
		if of_r.is_empty():
			continue
		var n: Array = of_r.map(func(d: Dictionary) -> float: return float(d.econ_net))
		print("  rating %d: %3d deployments, net mean %s, p10 %s, worst %s" % [r, of_r.size(), _k(_mean(n)), _k(_pct(n, 0.1)), _k(_pct(n, 0.0))])
	for hot: bool in [false, true]:
		var of_k := deploys.filter(func(d: Dictionary) -> bool: return bool(d.hot) == hot)
		if of_k.is_empty():
			continue
		var n: Array = of_k.map(func(d: Dictionary) -> float: return float(d.econ_net))
		var pay: Array = of_k.map(func(d: Dictionary) -> float: return float(d.delta.get("advance", 0.0)) + float(d.delta.get("completion", 0.0)) + float(d.delta.get("bonuses", 0.0)))
		var days_n: Array = of_k.map(func(d: Dictionary) -> float: return float(d.days))
		var arr: Array = of_k.map(func(d: Dictionary) -> float: return float(d.arrival_advance))
		print("  %s zones: %3d deployments, %.1f days each, contract pay %s, net mean %s, p10 %s, worst %s; arrival advances (kept whatever happens) %s" % [
			"hot" if hot else "contract", of_k.size(), _mean(days_n), _k(_mean(pay)), _k(_mean(n)), _k(_pct(n, 0.1)), _k(_pct(n, 0.0)), _k(_mean(arr))])
	print("  lowest cash less loans in a campaign: mean %s, worst %s; out of credit and in debt: %d of %d" % [_k(_mean(min_worth)), _k(_pct(min_worth, 0.0)), bankrupt, runs])


func _print_kit_values() -> void:
	print("Role kits (Roles.kit, what a new hire brings): shop value / sells for / typical sign-on fee")
	for role: String in ["rifleman", "medic", "autorifleman", "grenadier", "marksman", "team_leader"]:
		var value := 0
		var sells := 0
		for pair: Array in Roles.kit(StringName(role)):
			value += Prices.price_of(pair[0]) * int(pair[1])
			sells += Prices.sell_price(pair[0], int(pair[1]))
		print("  %-13s %s / %s" % [role, _k(value), _k(sells)])
	var fees: Array = []
	for r in 20:
		for c: Dictionary in Hiring.draw_pool(77, r):
			fees.append(float(c.fee))
	print("  sign-on fee: median %s, p10 %s, p90 %s" % [_k(_pct(fees, 0.5)), _k(_pct(fees, 0.1)), _k(_pct(fees, 0.9))])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x: Variant in a:
		t += float(x)
	return t / a.size()


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(roundi(q * (s.size() - 1)), 0, s.size() - 1)])


func _k(x: float) -> String:
	return "%s$%.1fk" % ["-" if x < 0 else "", absf(x) / 1000.0]
