extends Node
## The company's money, reputation and calendar (wave 4, W10), the autoload `Economy`.
## The host owns it in the campaign save's "economy" section (Campaign.section(&"economy"));
## every peer and late joiner gets a copy (state(), the same keys) to show.
##
## - Cash, with a ledger of what came and went.
## - Reputation with each faction in data/factions.json (-100..100, start_rep to begin with),
##   its tier as a number (tier()); what tiers unlock is wave 6's call. "locals" is the
##   standing with the local population (civilian casualties lower it).
## - The campaign clock in days: missions advance it (Contracts), and so do travel, recovery
##   and repairs (whoever does them calls advance_days). Wages (wages_provider, the base agent's
##   roster) and upkeep are paid every day, a "week_days"-th of the week's bill (economy overhaul
##   2026-10-20: each debrief carries its own days, none takes a whole week's bill at once); loan
##   installments every "week_days".
## - The safety floor: when the bill can't be paid the employer that likes the company best
##   lends the difference (an emergency loan, up to "loan_max" owed); loans can also be taken
##   by hand (take_loan). The contract board always carries a cheap low-risk job too.
## - The shop's side: prices (Prices, data/prices.json) and the transactions: buying gear,
##   medical supplies and support calls, repairs, selling. Bought items go to purchase_sink
##   (the base agent's armory) or wait in the base inbox (take_unbanked).
##
## Clients ask through the request functions (buy, take_loan...), which reach the host.

signal changed
## Host: the clock moved on `days` days to `day`.
signal day_advanced(day: int, days: int)
## Host: a bill was paid on `day` ({"wages", "upkeep", "loans", "total", "loan_taken"}): the
## day's wages and upkeep every day, the week's loan installments every "week_days".
signal bill_paid(day: int, bill: Dictionary)
## A message for the local player (purchases, loans).
signal notice(text: String)
## Host: items bought (after purchase_sink, if any, took them).
signal purchased(item_id: StringName, count: int, peer_id: int)

const SECTION := &"economy"
const LEDGER_KEEP := 80
const REP_MIN := -100
const REP_MAX := 100
const HEAT_MAX := 100.0

## Host: the weekly wage bill. The base agent sets it to its roster's wages: a Callable
## returning an int (the week's total) or an Array of {"what", "amount"}. Unset, the
## stand-in from data/prices.json ("default_wage_bill") is charged.
var wages_provider: Callable
## Host: optional; the week's base upkeep (int). Unset: "weekly_upkeep" from prices.json.
var upkeep_provider: Callable
## Host: optional; takes bought items: func(item_id: StringName, count: int, peer_id: int) -> bool.
## When unset or it returns false, they wait in the base inbox (take_unbanked).
var purchase_sink: Callable
## Host: optional; takes items brought home from a deployment (carried out, salvage picks):
## func(items: Array) -> bool. When unset or false, they wait in the base inbox.
var stash_sink: Callable

var _remote: Dictionary = {}  # clients: the host's state
var _dirty := false


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	Campaign.changed.connect(func(section_name: StringName) -> void:
		if (section_name == SECTION or section_name == ZoneControl.SECTION or section_name == WorldSites.WAR) and _is_host():
			_queue_sync())


# --- State (every peer) ------------------------------------------------------------------

## The economy as this peer knows it: the host's own section, or the copy it was sent.
## Keys: "cash", "day", "rep" {faction: int}, "locals", "loans" [{"faction", "left",
## "weekly"}], "ledger" [{"day", "amount", "what"}], "unbanked" [items], "week" (paid weeks).
func state() -> Dictionary:
	if _is_host():
		return _section()
	return _remote


func cash() -> int:
	return int(state().get("cash", 0))


func day() -> int:
	return int(state().get("day", 1))


## Which week of the campaign it is (1 in the first).
func week() -> int:
	return (day() - MissionRegistry.setting_i("start_day", 1)) / maxi(MissionRegistry.setting_i("week_days", 7), 1) + 1


## Days until the next loan installments (wages and upkeep are paid daily).
func days_to_bill() -> int:
	var w := maxi(MissionRegistry.setting_i("week_days", 7), 1)
	return w - (day() - MissionRegistry.setting_i("start_day", 1)) % w


func reputation(faction: String) -> int:
	return int((state().get("rep", {}) as Dictionary).get(faction, 0))


## Reputation tier with `faction`, as a number (0 = lowest; see MissionRegistry).
func tier(faction: String) -> int:
	return MissionRegistry.tier_index(reputation(faction))


func locals() -> int:
	return int(state().get("locals", 0))


func loans_owed() -> int:
	var total := 0
	for loan: Dictionary in state().get("loans", []):
		total += int(loan.get("left", 0))
	return total


func ledger() -> Array:
	return state().get("ledger", [])


## What a ledger line was, from its text (the base screen's books): "Contract pay", "Sales",
## "Loans in", "Wages and upkeep", "Loan installments", "Field costs", "Supports", "Respawns",
## "Lost helicopters", "Hiring", "Medical", "Purchases", "Upgrades", "Repairs and service",
## "Fines and clawbacks", "Death benefits" or "Other".
static func ledger_kind(what: String) -> String:
	const KINDS := [["Advance clawed back", "Fines and clawbacks"], ["Civilian fines", "Fines and clawbacks"],
		["Advance:", "Contract pay"], ["Completion:", "Contract pay"], ["Sold", "Sales"], ["Intel sold", "Sales"],
		["Emergency", "Loans in"], ["Loan from", "Loans in"], ["Day ", "Wages and upkeep"], ["Week ", "Loan installments"],
		["Deployment costs", "Field costs"], ["Support ", "Supports"], ["Helicopter out", "Supports"], ["Raid flight", "Supports"],
		["Lost helicopter", "Lost helicopters"], ["Respawn", "Respawns"], ["Hired", "Hiring"], ["Medbay", "Medical"],
		["Bought", "Purchases"], ["Air wing upgrade", "Upgrades"], ["FOB upgrade", "Upgrades"], ["Rebel ", "Upgrades"],
		["HX-1", "Upgrades"], ["Repaired", "Repairs and service"], ["Motor pool", "Repairs and service"],
		["Death benefit", "Death benefits"], ["Side job", "Side jobs"], ["Capture sold", "Captures and bounties"], ["Bounty", "Captures and bounties"]]
	for pair: Array in KINDS:
		if what.begins_with(String(pair[0])):
			return String(pair[1])
	return "Other"


## The ledger's lines from day `since` on, summed by ledger_kind: [{"kind", "in", "out"}] ("out"
## positive), the biggest movers first.
func ledger_summary(since: int) -> Array:
	var by := {}
	for e: Dictionary in ledger():
		if int(e.get("day", 0)) < since:
			continue
		var k := ledger_kind(String(e.get("what", "")))
		if not by.has(k):
			by[k] = {"kind": k, "in": 0, "out": 0}
		var amount := int(e.get("amount", 0))
		if amount >= 0:
			by[k]["in"] = int(by[k]["in"]) + amount
		else:
			by[k]["out"] = int(by[k]["out"]) - amount
	var out: Array = by.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["in"]) + int(a.out) > int(b["in"]) + int(b.out))
	return out


func price_of(item_id: StringName) -> int:
	return Prices.price_of(item_id)


func repair_cost(item_id: StringName, item_state: Dictionary) -> int:
	return Prices.repair_cost(item_id, item_state)


func support_price(kind: String) -> int:
	return Prices.support_price(kind)


# --- Host --------------------------------------------------------------------------------

## Host: a fresh economy (start cash, factions' start reputation, day 1). `start_cash` < 0
## takes the setting.
func new_campaign(start_cash := -1) -> void:
	var s := Campaign.section(SECTION)
	s.clear()
	var rep := {}
	for f: Dictionary in MissionRegistry.factions():
		rep[String(f.id)] = int(f.get("start_rep", 0))
	s.merge({"cash": start_cash if start_cash >= 0 else MissionRegistry.setting_i("start_cash", 150000),
		"day": MissionRegistry.setting_i("start_day", 1), "rep": rep, "locals": 0, "loans": [], "ledger": [],
		"unbanked": [], "week": 0, "run_expenses": []})
	_commit()


func add_cash(amount: int, what: String) -> void:
	if amount == 0:
		return
	var s := _section()
	s.cash = int(s.cash) + amount
	var ledger: Array = s.ledger
	ledger.append({"day": int(s.day), "amount": amount, "what": what})
	while ledger.size() > LEDGER_KEEP:
		ledger.pop_front()
	_commit()


## Host: pays `amount` if the company has it. Returns whether it did.
func spend(amount: int, what: String) -> bool:
	if amount < 0 or cash() < amount:
		return false
	add_cash(-amount, what)
	return true


## Host: a cost of the run in progress (a bought respawn, a lost helicopter): comes off the
## cash even into debt and is listed in the next debrief's expenses.
func charge_run(amount: int, what: String) -> void:
	if amount <= 0:
		return
	add_cash(-amount, what)
	note_run_expense(amount, what)


## Host: lists an expense already taken from the cash (negative: a refund) for the debrief.
## `bill`: a day's running costs or a loan installment (a deployment's debrief lists only its own
## days of them: drop_run_bills).
func note_run_expense(amount: int, what: String, bill := false) -> void:
	var s := _section()
	if not s.has("run_expenses"):
		s["run_expenses"] = []
	var e := {"what": what, "amount": amount}
	if bill:
		e["bill"] = true
	(s.run_expenses as Array).append(e)


## Host: forgets the bills listed since the last debrief (they stay in the ledger): a deployment
## starting, so its debrief shows only its own days' wages and upkeep, not the days waited at base.
func drop_run_bills() -> void:
	var s := _section()
	s["run_expenses"] = (s.get("run_expenses", []) as Array).filter(func(e: Dictionary) -> bool: return not bool(e.get("bill", false)))


## Host: the expenses listed since the last debrief, emptied.
func take_run_expenses() -> Array:
	var s := _section()
	var out: Array = (s.get("run_expenses", []) as Array).duplicate(true)
	s["run_expenses"] = []
	return out


## Host: `faction`'s reputation moves by `delta`. With `ripple` (wave 6a, decided: "gaining rep
## with a faction slightly raises it with that faction's allies and lowers it with its
## enemies"), "ripple_ally" of it goes to its allies and the opposite "ripple_enemy" to its
## enemies (whole points, toward zero: a small change ripples nothing), once: the ripple doesn't ripple again.
func change_reputation(faction: String, delta: int, why := "", ripple := true) -> void:
	if delta == 0 or faction == "":
		return
	var rep: Dictionary = _section().rep
	rep[faction] = clampi(int(rep.get(faction, 0)) + delta, REP_MIN, REP_MAX)
	if why != "":
		print("[economy] reputation %s %+d (%s)" % [faction, delta, why])
	if ripple:
		var rules := MissionRegistry.reputation_rules()
		for ally: String in MissionRegistry.allies_of(faction):
			change_reputation(ally, int(delta * float(rules.get("ripple_ally", 0.0))), "", false)
		for enemy: String in MissionRegistry.enemies_of(faction):
			change_reputation(enemy, -int(delta * float(rules.get("ripple_enemy", 0.0))), "", false)
	_commit()


## Host: the squad worked for `faction` today (a contract signed or settled): its reputation
## doesn't decay for a while, and its enemies won't hire the squad for "lockout_days" (wave 6a,
## decided: side lockout).
func note_job(faction: String) -> void:
	if faction == "":
		return
	var s := _section()
	var jobs: Dictionary = s.get("rep_jobs", {})
	jobs[faction] = int(s.day)
	s["rep_jobs"] = jobs
	var locks: Dictionary = s.get("lockouts", {})
	var until := int(s.day) + int(MissionRegistry.reputation_rules().get("lockout_days", 0))
	for enemy: String in MissionRegistry.enemies_of(faction):
		locks[enemy] = maxi(int(locks.get(enemy, 0)), until)
	s["lockouts"] = locks
	_commit()


## Why `faction` won't hire the squad now ("" if it will): Hostile reputation, or locked out
## for working for its enemies.
func work_problem(faction: String) -> String:
	if faction == "":
		return ""
	if bool(MissionRegistry.tier_of(reputation(faction)).get("no_work", false)):
		return "%s won't work with the company (Hostile)" % MissionRegistry.faction(faction).get("name", faction)
	var until := int((state().get("lockouts", {}) as Dictionary).get(faction, 0))
	if day() <= until:
		return "%s won't hire you while you work for their enemies (until day %d)" % [MissionRegistry.faction(faction).get("name", faction), until]
	return ""


## What `faction` pays at the squad's tier with it (the tier's "pay_mult", 1 without one).
func pay_mult(faction: String) -> float:
	return float(MissionRegistry.tier_of(reputation(faction)).get("pay_mult", 1.0)) if faction != "" else 1.0


## A faction's heat (wave 6d, decided: "angering a faction builds heat, and high heat brings
## generic hunter teams into missions near that faction's territory"): 0..HEAT_MAX, raised by
## add_heat (Pressure: its men killed, its sites taken out), cooling "heat_cool_per_day".
## Reading it never starts a campaign (state() would: the 6f bombers ask on a zone's first frame,
## and a test zone hosted on its own quietly got a campaign and a board).
func heat(faction: String) -> float:
	var s: Dictionary = Campaign.section(SECTION) if _is_host() else _remote
	return float((s.get("heat", {}) as Dictionary).get(faction, 0.0))


## Host: `faction`'s heat rises by `amount` (kept within 0..HEAT_MAX).
func add_heat(faction: String, amount: float) -> void:
	if faction == "" or amount == 0.0:
		return
	var s := _section()
	var h: Dictionary = s.get("heat", {})
	h[faction] = clampf(float(h.get(faction, 0.0)) + amount, 0.0, HEAT_MAX)
	s["heat"] = h
	_commit()


## Whether `faction` is angry enough to send hunters after the squad in any zone it holds.
func hunting(faction: String) -> bool:
	return heat(faction) >= float(MissionRegistry.reputation_rules().get("heat_hunters", INF))


## Named hunter squads (wave 6d, decided: "at the top end, persistent named hunter squads appear
## that remember the player and come back"): one per faction at a time, raised once its heat
## reaches "heat_named". {"id", "faction", "name", "leader", "encounters", "kills", "alive",
## "raised_day"}. Each time it comes for the squad it's better (EnemyResponse: combat and
## discipline by encounters); it's done when its leader dies.
const NEMESIS_FIRST: Array[String] = ["Black", "Grey", "Red", "Iron", "Night", "Dust", "Ash", "Stone"]
const NEMESIS_SECOND: Array[String] = ["Wolves", "Jackals", "Hounds", "Vipers", "Hawks", "Ravens", "Scorpions", "Lynxes"]


## `faction`'s named hunter squad still in the field, or {}.
func nemesis(faction: String) -> Dictionary:
	for n: Dictionary in state().get("nemeses", []):
		if String(n.faction) == faction and bool(n.alive):
			return n
	return {}


## Host: `faction` raises a named hunter squad (if it has none in the field); returns it.
func server_raise_nemesis(faction: String) -> Dictionary:
	var have := nemesis(faction)
	if not have.is_empty() or faction == "":
		return have
	var s := _section()
	var list: Array = s.get("nemeses", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([faction, list.size(), int(s.day)])
	var name := "%s %s" % [NEMESIS_FIRST[rng.randi() % NEMESIS_FIRST.size()], NEMESIS_SECOND[rng.randi() % NEMESIS_SECOND.size()]]
	var nation := String(MissionRegistry.faction(faction).get("nation", "insurgent"))
	var n := {"id": "N%d" % (list.size() + 1), "faction": faction, "name": name, "leader": Names.mission_person(rng, "hvt", nation),
		"encounters": 0, "kills": 0, "alive": true, "raised_day": int(s.day)}
	list.append(n)
	s["nemeses"] = list
	_commit()
	print("[economy] %s raises a named hunter squad: the %s, led by %s" % [faction, name, n.leader])
	return n


## Host: named squad `id` came for the squad again (it learns: EnemyResponse reads "encounters").
func server_nemesis_met(id: String) -> void:
	for n: Dictionary in _section().get("nemeses", []):
		if String(n.id) == id:
			n.encounters = int(n.encounters) + 1
	_commit()


## Host: named squad `id` killed one of ours, or lost its leader (done for good).
func server_nemesis_event(id: String, killed_ours := 0, leader_dead := false) -> void:
	for n: Dictionary in _section().get("nemeses", []):
		if String(n.id) == id:
			n.kills = int(n.kills) + killed_ours
			if leader_dead:
				n.alive = false
				print("[economy] the %s are finished: %s is dead" % [n.name, n.leader])
	_commit()


func _cool_heat() -> void:
	var s := _section()
	var h: Dictionary = s.get("heat", {})
	var cool := float(MissionRegistry.reputation_rules().get("heat_cool_per_day", 0.0))
	for f: String in h.keys():
		h[f] = maxf(float(h[f]) - cool, 0.0)


## Host, once a day: every faction the squad hasn't worked for in "decay_grace_days" (an Allied
## one "allied_grace_days") drifts "decay_per_day" toward neutral (wave 6a, decided: rep decay).
func _decay_reputation() -> void:
	var s := _section()
	var rules := MissionRegistry.reputation_rules()
	var step := int(rules.get("decay_per_day", 0))
	if step <= 0:
		return
	var rep: Dictionary = s.rep
	var jobs: Dictionary = s.get("rep_jobs", {})
	for f: String in rep.keys():
		var r := int(rep[f])
		if r == 0:
			continue
		var allied: bool = MissionRegistry.tier_of(r).get("id", "") == "allied"
		var grace := int(rules.get("allied_grace_days" if allied else "decay_grace_days", 7))
		var since := int(s.day) - int(jobs.get(f, MissionRegistry.setting_i("start_day", 1)))
		if since > grace:
			rep[f] = r - signi(r) * mini(step, absi(r))


func change_locals(delta: int) -> void:
	var s := _section()
	s.locals = clampi(int(s.locals) + delta, REP_MIN, REP_MAX)
	_commit()


## Host: the clock moves on `days` days. Each day passes in turn: the day's wages and upkeep
## are paid (pay_day), loan installments every "week_days" (pay_week), and Contracts expires
## offers and lapses contracts (day_advanced).
func advance_days(days: int, reason := "") -> void:
	if days <= 0:
		return
	var s := _section()
	var week_days := maxi(MissionRegistry.setting_i("week_days", 7), 1)
	for i in days:
		s.day = int(s.day) + 1
		pay_day()
		if (int(s.day) - MissionRegistry.setting_i("start_day", 1)) % week_days == 0:
			s.week = int(s.week) + 1
			pay_week()
		_decay_reputation()
		_cool_heat()
	WorldSites.server_advance_days(days)  # wave 6c: the faction war and site repair/reoccupation
	Income.server_advance_days(days)  # claude/income: side jobs come back, businesses pay, markets move
	if reason != "":
		print("[economy] %d day%s pass (%s): day %d" % [days, "" if days == 1 else "s", reason, int(s.day)])
	_commit()
	day_advanced.emit(int(s.day), days)


## The week's bill as it stands: {"wages", "upkeep", "loans", "total", "lines": [{"what", "amount"}]}.
func weekly_bill() -> Dictionary:
	if not _is_host() and _remote.has("bill"):
		return _remote.bill  # a client: the host's, as last synced (the wages are the host's roster's)
	var lines: Array = []
	var wages := 0
	if wages_provider.is_valid():
		var w: Variant = wages_provider.call()
		if w is Array:
			for entry: Dictionary in w:
				lines.append({"what": String(entry.get("what", "Wages")), "amount": int(entry.get("amount", 0))})
				wages += int(entry.get("amount", 0))
		else:
			wages = int(w)
			lines.append({"what": "Wages", "amount": wages})
	else:
		wages = Prices.default_wage_bill()
		lines.append({"what": "Wages (stand-in roster)", "amount": wages})
	var upkeep := int(upkeep_provider.call()) if upkeep_provider.is_valid() else Prices.weekly_upkeep()
	lines.append({"what": "Base upkeep", "amount": upkeep})
	var loans := 0
	for loan: Dictionary in state().get("loans", []):
		var due := mini(int(loan.weekly), int(loan.left))
		loans += due
		lines.append({"what": "Loan from %s" % MissionRegistry.faction_name(String(loan.faction)), "amount": due})
	return {"wages": wages, "upkeep": upkeep, "loans": loans, "total": wages + upkeep + loans, "lines": lines}


## Today's share of the week's wages and upkeep: {"wages", "upkeep", "loans" (0), "total"}.
## Each day pays the next "week_days"-th, rounded so a week's days add up to the week's bill.
func daily_bill() -> Dictionary:
	var week := weekly_bill()
	var w := maxi(MissionRegistry.setting_i("week_days", 7), 1)
	var k := posmod(day() - MissionRegistry.setting_i("start_day", 1) - 1, w) + 1  # today is the k-th day of its week (1..w)
	var wages := _share(int(week.wages), k, w)
	var upkeep := _share(int(week.upkeep), k, w)
	return {"wages": wages, "upkeep": upkeep, "loans": 0, "total": wages + upkeep}


## The k-th of `w` daily parts of `total` (the parts add up to it exactly).
static func _share(total: int, k: int, w: int) -> int:
	return floori(float(total) * k / w) - floori(float(total) * (k - 1) / w)


## Host: pays today's wages and upkeep (advance_days does, every day; economy overhaul
## 2026-10-20: was once a week). A bill beyond the cash takes an emergency loan (_pay_bill).
func pay_day() -> Dictionary:
	var bill := daily_bill()
	if int(bill.total) <= 0:
		return bill
	return _pay_bill(bill, "Day %d: wages %d, upkeep %d" % [day(), bill.wages, bill.upkeep],
		[["Wages", int(bill.wages)], ["Base upkeep", int(bill.upkeep)]])


## Host: pays the week's loan installments (advance_days does, every week). Returns the bill
## ({"wages" and "upkeep" 0, "loans", "total", "loan_taken"}).
func pay_week() -> Dictionary:
	var loans := int(weekly_bill().loans)
	# This week's installments come off the loans already owed (the bill counts them).
	for loan: Dictionary in _section().loans:
		loan.left = int(loan.left) - mini(int(loan.weekly), int(loan.left))
	_section().loans = (_section().loans as Array).filter(func(l: Dictionary) -> bool: return int(l.left) > 0)
	var bill := {"wages": 0, "upkeep": 0, "loans": loans, "total": loans, "loan_taken": 0}
	if loans <= 0:
		return bill
	return _pay_bill(bill, "Week %d: loan installments %d" % [int(_section().week), loans], [["Loan installments", loans]])


## Pays `bill` ({"total", ...}). If the cash won't cover it, an emergency loan covers the gap
## first (the safety floor), as far as "loan_max" allows. `lines`: [[what, amount]] for the debrief.
func _pay_bill(bill: Dictionary, ledger_text: String, lines: Array) -> Dictionary:
	var loan_taken := 0
	if int(bill.total) > cash():
		var short := int(bill.total) - cash() + MissionRegistry.setting_i("safety_floor_cash", 0)
		loan_taken = _lend(best_lender(), short, "emergency loan")
	add_cash(-int(bill.total), ledger_text)
	for pair: Array in lines:
		if int(pair[1]) != 0:
			note_run_expense(int(pair[1]), String(pair[0]), true)
	bill["loan_taken"] = loan_taken
	bill_paid.emit(day(), bill)
	if loan_taken > 0:
		_notify_all("Emergency loan of $%s from %s to cover the bills" % [DebriefCalc.money(loan_taken), MissionRegistry.faction_name(best_lender())])
	return bill


## The faction most willing to lend: the employer the company stands best with.
func best_lender() -> String:
	var best := ""
	for f: String in MissionRegistry.employers():
		if best == "" or reputation(f) > reputation(best):
			best = f
	return best


## How much more the company can borrow.
func loan_room() -> int:
	return maxi(MissionRegistry.setting_i("loan_max", 150000) - loans_owed(), 0)


## Host: borrows `amount` (the standard "loan_amount" when 0) from `faction` (the best
## lender when ""). Repaid weekly over "loan_weeks" with "loan_interest". Returns the amount lent.
func server_take_loan(faction := "", amount := 0) -> int:
	return _lend(faction if faction != "" else best_lender(), amount if amount > 0 else MissionRegistry.setting_i("loan_amount", 50000), "loan")


func _lend(faction: String, amount: int, what: String) -> int:
	# What's owed (with interest) stays within "loan_max".
	amount = mini(amount, floori(loan_room() / (1.0 + MissionRegistry.setting_f("loan_interest", 0.1))))
	if amount <= 0 or faction == "":
		return 0
	var owed := roundi(amount * (1.0 + MissionRegistry.setting_f("loan_interest", 0.1)))
	var weeks := maxi(MissionRegistry.setting_i("loan_weeks", 8), 1)
	(_section().loans as Array).append({"faction": faction, "left": owed, "weekly": ceili(float(owed) / weeks), "day": day()})
	add_cash(amount, "%s from %s" % [what.capitalize(), MissionRegistry.faction_name(faction)])
	return amount


## Host: buys `count` of `item_id` from the base shop for the company. They go to
## purchase_sink, or the base inbox. Returns whether it went through.
func server_buy(item_id: StringName, count := 1, peer_id := 1) -> bool:
	if count <= 0 or not Quartermaster.sells(item_id):
		_notify(peer_id, "The shop doesn't sell that")
		return false
	var total := Quartermaster.price(item_id) * count  # the base shop's, or an allied quartermaster's better deal (wave 6)
	if not spend(total, "Bought %d x %s" % [count, ItemDB.get_item(item_id).name]):
		_notify(peer_id, "Not enough cash for %s ($%s)" % [ItemDB.get_item(item_id).name, DebriefCalc.money(total)])
		return false
	if not (purchase_sink.is_valid() and purchase_sink.call(item_id, count, peer_id)):
		bank_items([{"id": String(item_id), "count": count}], "")
	purchased.emit(item_id, count, peer_id)
	_notify(peer_id, "Bought %d x %s for $%s" % [count, ItemDB.get_item(item_id).name, DebriefCalc.money(total)])
	return true


## Host: sells items back to the shop. Returns what they fetched.
func server_sell(item_id: StringName, count := 1, item_state := {}) -> int:
	var price := Prices.sell_price(item_id, count, item_state)
	if price > 0:
		add_cash(price, "Sold %d x %s" % [count, ItemDB.get_item(item_id).name if ItemDB.has_item(item_id) else String(item_id)])
	return price


## Host: repairs a damaged item if the company can pay. Returns its state as new (the
## item's default state) or {} when it couldn't. Repairs take time: the base agent advances
## the clock for them.
func server_repair(item_id: StringName, item_state: Dictionary) -> Dictionary:
	var cost := Prices.repair_cost(item_id, item_state)
	var stocked := Pallets.offset_preview(cost, "repair")  # spare parts in the FOB's stocks cover part of it
	if cost > 0 and not spend(cost - int(stocked.offset), "Repaired %s" % ItemDB.get_item(item_id).name):
		return {}
	Pallets.take_stock(stocked.used)
	return ItemDB.get_item(item_id).default_state()


## Host: pays for a support call ("resupply", "transport", "aav", "extraction"): from the
## contract's negotiated support budget first, the rest from cash. Returns whether it's paid.
func server_pay_support(kind: String, cid := "") -> bool:
	var price := Prices.support_price(kind)
	if price <= 0:
		return false
	var from_budget := Contracts.server_draw_support(cid, price) if cid != "" else 0
	if from_budget >= price:
		return true
	# FOB stocks cover part of it (fuel for the lift, parts, ammo; Pallets.offset_preview).
	var stocked := Pallets.offset_preview(price - from_budget, "support:" + kind)
	var paid := price - from_budget - int(stocked.offset)
	if spend(paid, "Support call: %s" % kind):
		Pallets.take_stock(stocked.used)
		note_run_expense(paid, "Support call: %s" % kind)
		return true
	if from_budget > 0:
		Contracts.server_draw_support(cid, -from_budget)  # give the budget back
	return false


## Host: a helicopter insertion's price (prices.json supports "insertion"; economy pass
## 2026-10-22, Proposed): paid like a support call (the contract's support budget, FOB stocks,
## cash), and on credit when none of them covers it: the squad is already aboard.
func server_pay_insertion(cid := "") -> void:
	var price := Prices.support_price("insertion")
	if price <= 0 or server_pay_support("insertion", cid):
		return
	charge_run(price, "Support call: insertion (on credit)")


## Host: buys air wing upgrade `id` (HeliUpgrades: one-time, company-wide, kept in this
## section's "heli_upgrades"). "" when bought, or why not.
func server_buy_heli_upgrade(id: String) -> String:
	var why := HeliUpgrades.problem(id)
	if why != "":
		return why
	var d := HeliUpgrades.def(id)
	if not spend(int(d.get("cost", 0)), "Air wing upgrade: %s" % String(d.get("name", id))):
		return "Can't afford it"
	var s := _section()
	var owned: Array = s.get(HeliUpgrades.KEY, [])
	owned.append(id)
	s[HeliUpgrades.KEY] = owned
	_commit()
	return ""


## Host: items brought home (or bought) go to the base: stash_sink, or the base inbox.
func bank_items(items: Array, why: String) -> void:
	if items.is_empty():
		return
	if why != "" and stash_sink.is_valid() and stash_sink.call(items):
		return
	var inbox: Array = _section().unbanked
	for entry: Dictionary in items:
		inbox.append({"id": String(entry.get("id", "")), "count": int(entry.get("count", 1)), "state": entry.get("state", {})})
	_commit()


## Host: everything waiting in the base inbox, emptied (the base agent's stash takes it).
func take_unbanked() -> Array:
	var items: Array = _section().unbanked.duplicate(true)
	_section().unbanked = []
	_commit()
	return items


# --- FOB stocks and pallet storage (feat/pallet-tagging; Pallets, docs/pallets.md) --------------

## The FOB's own stocks: {"fuel", "ammo", "parts", "supplies", "medical": units}. Saved with the
## campaign (this section), copied to every peer. Stocks offset costs (Pallets.offset_preview).
func stocks() -> Dictionary:
	return state().get("stocks", {})


func stock(kind: String) -> int:
	return int(stocks().get(kind, 0))


## Host: adds `units` of a stock kind.
func server_add_stock(kind: String, units: int) -> void:
	if units <= 0:
		return
	var s := _section()
	if not s.has("stocks"):
		s["stocks"] = {}
	s.stocks[kind] = int(s.stocks.get(kind, 0)) + units
	_commit()


## Host: uses up to `units` of a stock kind; returns how many were there to use.
func server_take_stock(kind: String, units: int) -> int:
	var used := mini(maxi(units, 0), stock(kind))
	if used > 0:
		_section().stocks[kind] = stock(kind) - used
		_commit()
	return used


## Tagged lots waiting in FOB storage (Pallets lots with status "stored").
func pallet_store() -> Array:
	return state().get("pallet_store", [])


## Host: puts a lot into FOB storage.
func server_store_lot(lot: Dictionary) -> void:
	var s := _section()
	if not s.has("pallet_store"):
		s["pallet_store"] = []
	(s.pallet_store as Array).append(lot)
	_commit()


## Host: takes lot `index` out of storage ({} for none).
func server_unstore_lot(index: int) -> Dictionary:
	var store: Array = _section().get("pallet_store", [])
	if index < 0 or index >= store.size():
		return {}
	var lot: Dictionary = store[index]
	store.remove_at(index)
	_commit()
	return lot


# --- Requests (any peer) -----------------------------------------------------------------

func buy(item_id: StringName, count := 1) -> void:
	if _is_host():
		server_buy(item_id, count, 1)
	else:
		_rq_buy.rpc_id(1, String(item_id), count)


## Sells `count` of `id` from the company stash (BaseHub.server_sell_from_stash).
func sell_from_stash(item_id: StringName, count := 1) -> void:
	if _is_host():
		_sold(1, item_id, BaseHub.server_sell_from_stash(item_id, count))
	else:
		_rq_sell.rpc_id(1, String(item_id), count)


## Sells `count` of contraband `id` from the company stash to the fixer who buys it (Fixers).
func sell_contraband(item_id: StringName, count := 1) -> void:
	if _is_host():
		_sold(1, item_id, Fixers.server_sell(item_id, count))
	else:
		_rq_sell_contraband.rpc_id(1, String(item_id), count)


@rpc("any_peer", "call_remote", "reliable")
func _rq_sell_contraband(item_id: String, count: int) -> void:
	if multiplayer.is_server():
		_sold(multiplayer.get_remote_sender_id(), StringName(item_id), Fixers.server_sell(StringName(item_id), clampi(count, 1, 50)))


func _sold(peer_id: int, item_id: StringName, got: int) -> void:
	var item_name := ItemDB.get_item(item_id).name if ItemDB.has_item(item_id) else String(item_id)
	_notify(peer_id, ("Sold %s for $%s" % [item_name, DebriefCalc.money(got)]) if got > 0 else "No %s in the stash to sell" % item_name)


@rpc("any_peer", "call_remote", "reliable")
func _rq_sell(item_id: String, count: int) -> void:
	if multiplayer.is_server():
		_sold(multiplayer.get_remote_sender_id(), StringName(item_id), BaseHub.server_sell_from_stash(StringName(item_id), clampi(count, 1, 50)))


## Buys air wing upgrade `id` (HeliUpgrades); the result comes back as a notice.
func buy_heli_upgrade(id: String) -> void:
	if _is_host():
		_heli_upgrade_bought(1, id, server_buy_heli_upgrade(id))
	else:
		_rq_heli_upgrade.rpc_id(1, id)


func _heli_upgrade_bought(peer_id: int, id: String, why: String) -> void:
	var upgrade_name := String(HeliUpgrades.def(id).get("name", id))
	_notify(peer_id, ("Bought the %s" % upgrade_name) if why == "" else "%s: %s" % [upgrade_name, why])


@rpc("any_peer", "call_remote", "reliable")
func _rq_heli_upgrade(id: String) -> void:
	if multiplayer.is_server():
		_heli_upgrade_bought(multiplayer.get_remote_sender_id(), id, server_buy_heli_upgrade(id))


func take_loan() -> void:
	if _is_host():
		var lent := server_take_loan()
		notice.emit("Borrowed $%s" % DebriefCalc.money(lent) if lent > 0 else "No more credit")
	else:
		_rq_loan.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rq_buy(item_id: String, count: int) -> void:
	if multiplayer.is_server():
		server_buy(StringName(item_id), count, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rq_loan() -> void:
	if multiplayer.is_server():
		var lent := server_take_loan()
		_notify(multiplayer.get_remote_sender_id(), "Borrowed $%s" % DebriefCalc.money(lent) if lent > 0 else "No more credit")


# --- Replication -------------------------------------------------------------------------

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _section() -> Dictionary:
	var s := Campaign.section(SECTION)
	if s.is_empty():
		Contracts.ensure_campaign()
		s = Campaign.section(SECTION)
	return s


func _commit() -> void:
	changed.emit()
	_queue_sync()


func _queue_sync() -> void:
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


func _flush() -> void:
	_dirty = false
	if _online() and not Campaign.section(SECTION).is_empty():
		_sync.rpc(_public())


func _public() -> Dictionary:
	var out := _section().duplicate(true)
	out["bill"] = weekly_bill()  # the week's wages, upkeep and loans as the host's roster stands (the base screen, the debrief)
	out["world_sites"] = WorldSites.rows()  # wave 6c: who holds each hot zone, for every peer's board
	out["war"] = WorldSites.war_view()  # the living war (2026-10-20): every zone's holder and front, strength, the news
	out[String(ZoneControl.SECTION)] = Campaign.section(ZoneControl.SECTION).duplicate(true)  # who controls each zone (the world map)
	out[String(Income.SECTION)] = Income.state().duplicate(true)  # side jobs, bounties, businesses, the market (the side work page)
	return out


## Who holds each hot zone and how firmly (WorldSites.rows()): the host's own, every other peer's
## from the last sync.
func world_sites() -> Array:
	return WorldSites.rows() if _is_host() else (_remote.get("world_sites", []) as Array)


## The living war (WorldSites.war_view: every zone's holder, grip and front, each faction's
## strength, the news): the host's own, every other peer's from the last sync.
func war_view() -> Dictionary:
	return WorldSites.war_view() if _is_host() else (_remote.get("war", {}) as Dictionary)


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and not Campaign.section(SECTION).is_empty():
		_sync.rpc_id(id, _public())


@rpc("authority", "call_remote", "reliable")
func _sync(s: Dictionary) -> void:
	_remote = s
	changed.emit()


func _notify(peer_id: int, text: String) -> void:
	if peer_id == 1 or peer_id == 0 or not _online():
		notice.emit(text)
	else:
		_notice.rpc_id(peer_id, text)


func _notify_all(text: String) -> void:
	notice.emit(text)
	if _online():
		_notice.rpc(text)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
