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
##   and repairs (whoever does them calls advance_days). Every "week_days" the weekly bill is
##   paid, MW5-style: wages (wages_provider, the base agent's roster), upkeep and loan
##   installments.
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
## Host: a week's bill was paid ({"wages", "upkeep", "loans", "total", "loan_taken"}).
signal week_paid(week: int, bill: Dictionary)
## A message for the local player (purchases, loans).
signal notice(text: String)
## Host: items bought (after purchase_sink, if any, took them).
signal purchased(item_id: StringName, count: int, peer_id: int)

const SECTION := &"economy"
const LEDGER_KEEP := 80
const REP_MIN := -100
const REP_MAX := 100

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
		if section_name == SECTION and _is_host():
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


## Days until the next weekly bill.
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
		"unbanked": [], "week": 0})
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


func change_reputation(faction: String, delta: int, why := "") -> void:
	if delta == 0 or faction == "":
		return
	var rep: Dictionary = _section().rep
	rep[faction] = clampi(int(rep.get(faction, 0)) + delta, REP_MIN, REP_MAX)
	if why != "":
		print("[economy] reputation %s %+d (%s)" % [faction, delta, why])
	_commit()


func change_locals(delta: int) -> void:
	var s := _section()
	s.locals = clampi(int(s.locals) + delta, REP_MIN, REP_MAX)
	_commit()


## Host: the clock moves on `days` days. Each day passes in turn: a weekly bill falls due
## every "week_days", and Contracts expires offers and lapses contracts (day_advanced).
func advance_days(days: int, reason := "") -> void:
	if days <= 0:
		return
	var s := _section()
	var week_days := maxi(MissionRegistry.setting_i("week_days", 7), 1)
	for i in days:
		s.day = int(s.day) + 1
		if (int(s.day) - MissionRegistry.setting_i("start_day", 1)) % week_days == 0:
			s.week = int(s.week) + 1
			pay_week()
	if reason != "":
		print("[economy] %d day%s pass (%s): day %d" % [days, "" if days == 1 else "s", reason, int(s.day)])
	_commit()
	day_advanced.emit(int(s.day), days)


## The week's bill as it stands: {"wages", "upkeep", "loans", "total", "lines": [{"what", "amount"}]}.
func weekly_bill() -> Dictionary:
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


## Host: pays the weekly bill (advance_days does, every week). If the cash won't cover it, an
## emergency loan covers the gap first (the safety floor), as far as "loan_max" allows.
func pay_week() -> Dictionary:
	var bill := weekly_bill()
	# This week's installments come off the loans already owed (the bill counts them).
	for loan: Dictionary in _section().loans:
		loan.left = int(loan.left) - mini(int(loan.weekly), int(loan.left))
	_section().loans = (_section().loans as Array).filter(func(l: Dictionary) -> bool: return int(l.left) > 0)
	var loan_taken := 0
	if int(bill.total) > cash():
		var short := int(bill.total) - cash() + MissionRegistry.setting_i("safety_floor_cash", 0)
		loan_taken = _lend(best_lender(), short, "emergency loan")
	add_cash(-int(bill.total), "Week %d: wages %d, upkeep %d, loans %d" % [int(_section().week), bill.wages, bill.upkeep, bill.loans])
	bill["loan_taken"] = loan_taken
	week_paid.emit(int(_section().week), bill)
	if loan_taken > 0:
		_notify_all("Emergency loan of $%s from %s to cover the week's bill" % [DebriefCalc.money(loan_taken), MissionRegistry.faction_name(best_lender())])
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
	if count <= 0 or not Prices.for_sale(item_id):
		_notify(peer_id, "The shop doesn't sell that")
		return false
	var total := Prices.price_of(item_id) * count
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
	if spend(price - from_budget - int(stocked.offset), "Support call: %s" % kind):
		Pallets.take_stock(stocked.used)
		return true
	if from_budget > 0:
		Contracts.server_draw_support(cid, -from_budget)  # give the budget back
	return false


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
	return _section().duplicate(true)


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
