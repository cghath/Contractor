class_name DebriefCalc
extends RefCounted
## The debrief's sums, pure (wave 4, W10): what each contract of a deployment came to, the
## fines, reputation changes, the salvage budget and pool, intel brought out and the days it
## all took. Contracts.server_end_deployment applies the result to the campaign.
##
## The result (JSON-safe, replicated to every peer):
## - "contracts": per contract {"cid", "title", "employer", "outcome" ("completed",
##   "failed", "voided", "lapsed", "aborted"), "advance" (paid at signing), "completion",
##   "bonuses": [{"text", "amount"}], "pay" (completion + bonuses), "clawback" (what a voided
##   contract gives back of its advance under its own term, ContractGen.clawback_amount:
##   all, none, or the share of required objectives not done), "salvage_share", "objectives": [lines],
##   and when an optional objective with a "withheld_share" wasn't done (an HVT kill's proof,
##   missions 2) "withheld" (taken off the completion) and "withheld_for" (its text);
## - "civilians", "fines"; "rep": {faction: change}, "locals": change;
## - "salvage": {"share", "pool": [{"id", "count", "state", "value"}], "pool_value",
##   "budget", "picked": [pool indices], "spent"};
## - "items_out": everything carried out (banked to the base);
## - "intel": [{"id", "count", "status": "pending", "intel_id"}] (intel among the items out;
##   Contracts drops a piece already debriefed once, by its intel_id);
## - "casualties": as the extraction report gave them;
## - "days": campaign days the deployment took (mission days plus travel);
## - "totals": {"advance", "completion", "bonuses", "fines", "clawback", "paid_now",
##   "contract_value"} (paid_now = completion + bonuses - fines - clawback).


## `contracts`: the deployment's contracts (host copies, with "deal"); `objectives`: the
## Objectives list, final; `civilians`: civilian casualties the squad caused; `report`: the
## extraction report (see Contracts.server_end_deployment).
static func compute(contracts: Array, objectives: Array, civilians: int, report: Dictionary) -> Dictionary:
	var S := func(key: String) -> float: return MissionRegistry.setting_f(key)
	var lines: Array = []
	var rep := {}
	var totals := {"advance": 0, "completion": 0, "bonuses": 0, "fines": 0, "clawback": 0, "paid_now": 0, "contract_value": 0}
	var best_share := 0.0
	var days := 0
	for c: Dictionary in contracts:
		var deal: Dictionary = c.get("deal", {})
		var mine := objectives.filter(func(o: Dictionary) -> bool: return o.cid == c.cid)
		var required := mine.filter(func(o: Dictionary) -> bool: return not o.optional)
		var outcome := "failed"
		match String(c.get("state", "")):
			"voided":
				outcome = "voided"
			"aborted":
				outcome = "aborted"
			_:
				if not required.is_empty() and required.all(func(o: Dictionary) -> bool: return o.state == Objectives.DONE):
					outcome = "completed"
				elif c.get("zone_kind") == "hot":
					outcome = "lapsed"  # a hot zone's unfinished contracts lapse at extraction
		var pay_total := int(deal.get("pay_total", 0))
		var line := {"cid": c.cid, "title": c.get("title", ""), "employer": c.get("employer", ""), "outcome": outcome,
			"clawback_term": String(c.get("clawback", ContractGen.FULL_CLAWBACK)),
			"advance": int(deal.get("advance", 0)), "completion": 0, "bonuses": [], "pay": 0, "clawback": 0, "salvage_share": 0.0,
			"objectives": mine.map(func(o: Dictionary) -> String: return Objectives.line(o))}
		var employer := String(c.get("employer", ""))
		var by_phase := Operations.is_operation(c) and outcome not in ["voided", "aborted"]
		if by_phase:
			outcome = Operations.debrief_into(c, line, rep)  # D3: paid phase by phase as each was done; its reputation too
			line.outcome = outcome
		match "" if by_phase else outcome:
			"completed":
				line.completion = int(deal.get("completion", 0)) + int(c.get("raise", 0))
				for o: Dictionary in mine:  # (missions 2: an HVT kill without its proof pays less)
					if o.optional and o.state != Objectives.DONE and float(o.get("withheld_share", 0.0)) > 0.0:
						var held := mini(roundi(pay_total * float(o.withheld_share)), int(line.completion))
						line.completion -= held
						line["withheld"] = int(line.get("withheld", 0)) + held
						line["withheld_for"] = String(o.text)
				for o: Dictionary in mine:
					if o.optional and o.state == Objectives.DONE and float(o.get("bonus_share", 0.0)) > 0.0:
						line.bonuses.append({"text": "Bonus: %s" % String(o.text).trim_prefix("Bonus: "), "amount": roundi(pay_total * float(o.bonus_share))})
				var hazard := int(report.get("hazard_tier", 0))
				if hazard > 0 and c.get("zone_kind") == "hot":  # staying longer pays more (Captain)
					line.bonuses.append({"text": "Hazard pay (enemy pressure, tier %d)" % hazard,
						"amount": roundi(pay_total * HotZoneOps.hazard_share(hazard))})
				if civilians == 0 and S.call("clean_bonus_share") > 0.0:
					line.bonuses.append({"text": "No civilian casualties", "amount": roundi(pay_total * S.call("clean_bonus_share"))})
				line.salvage_share = float(deal.get("salvage_share", 0.0))
				best_share = maxf(best_share, line.salvage_share)
				_add(rep, employer, int(S.call("rep_success")))
				_add(rep, String(c.get("target", "")), int(S.call("rep_target_on_success")))
			"failed":
				_add(rep, employer, int(S.call("rep_fail")))
			"voided":
				_add(rep, employer, int(S.call("rep_fail")))
				var done := required.filter(func(o: Dictionary) -> bool: return o.state == Objectives.DONE).size()
				line.clawback = ContractGen.clawback_amount(c, line.advance, done, required.size())
			"lapsed":
				_add(rep, employer, int(S.call("rep_lapse")))
			"aborted":
				# Free only when the briefing was shown to have lied (revealed and understated).
				var lied: bool = c.get("revealed", false) and c.get("understated", false)
				_add(rep, employer, 0 if lied else int(S.call("rep_abort")))
		for b: Dictionary in line.bonuses:
			totals.bonuses += int(b.amount)
		line.pay = line.completion + line.bonuses.reduce(func(acc: int, b: Dictionary) -> int: return acc + int(b.amount), 0)
		totals.advance += line.advance
		totals.completion += line.completion
		totals.clawback += int(line.clawback)
		if civilians > 0:
			_add(rep, employer, civilians * int(S.call("civilian_rep_employer")))
		days = maxi(days, int(c.get("days", 1)) + int(MissionRegistry.region(String(c.get("region", ""))).get("travel_days", 0)))
		lines.append(line)
	totals.fines = civilians * int(S.call("civilian_fine"))
	totals.paid_now = totals.completion + totals.bonuses - totals.fines - totals.clawback
	totals.contract_value = totals.advance + totals.paid_now
	# Salvage: the share of what was left in the field the squad may claim, and all it carried.
	var pool: Array = []
	var pool_value := 0
	for entry: Dictionary in report.get("field_items", []):
		var id := StringName(entry.get("id", ""))
		var value := Prices.value_of(id, int(entry.get("count", 1)), entry.get("state", {}))
		if value <= 0 or MissionRegistry.is_intel(id):  # intel counts only carried out (it isn't the client's to hand over as salvage)
			continue
		pool.append({"id": String(id), "count": int(entry.get("count", 1)), "state": entry.get("state", {}), "value": value})
		pool_value += value
	var items_out: Array = (report.get("items", []) as Array).duplicate(true)
	var intel: Array = []
	for entry: Dictionary in items_out:
		if MissionRegistry.is_intel(StringName(entry.get("id", ""))):
			intel.append({"id": String(entry.id), "count": int(entry.get("count", 1)), "status": "pending", "buyer": "",
				"intel_id": String((entry.get("state", {}) as Dictionary).get("intel_id", ""))})
	return {
		"contracts": lines, "civilians": civilians, "fines": totals.fines,
		"rep": rep, "locals": civilians * int(S.call("civilian_rep_locals")),
		"salvage": {"share": best_share, "pool": pool, "pool_value": pool_value, "budget": floori(pool_value * best_share), "picked": [], "spent": 0},
		"items_out": items_out, "intel": intel, "casualties": (report.get("casualties", []) as Array).duplicate(true),
		"days": maxi(days, 1), "totals": totals, "finished": false,
	}


## What a deployment cost on top of the contract: `run` (expenses already taken from the cash
## during the run and since: respawns, supports, lost helicopters, weekly bills) summed by
## what, plus the field costs per head and day, a death benefit per KIA and treatment per
## wounded squadmate (Prices.operations; with the report's "benefits_paid" the death benefits are
## `run`'s own lines, one per man). Returns {"lines": [{"what", "amount", "charge", "running"}],
## "total", "charge", "running"}: "charge" marks the lines still to take from the cash, "running"
## the company's own running costs in those days (wages, upkeep, loan installments: the daily
## bills), which it pays deployed or not (v0.7.1: they're shown apart from the job's net).
static func expenses(report: Dictionary, days: int, run: Array, use_stocks := false) -> Dictionary:
	var used := {}
	var lines: Array = []
	var sums := {}
	var bill_days := {}  # a daily bill's line: how many days it sums (Economy.pay_day)
	for e: Dictionary in run:
		sums[String(e.what)] = int(sums.get(String(e.what), 0)) + int(e.amount)
		if bool(e.get("bill", false)):
			bill_days[String(e.what)] = int(bill_days.get(String(e.what), 0)) + 1
	for what: String in sums:
		if int(sums[what]) != 0:
			var label := what
			if what != "Loan installments" and int(bill_days.get(what, 0)) > 0:
				label = "%s (%d day%s)" % [what, int(bill_days[what]), "" if int(bill_days[what]) == 1 else "s"]
			var running := what == "Loan installments" or int(bill_days.get(what, 0)) > 0
			lines.append({"what": label, "amount": int(sums[what]), "charge": false, "running": running})
	var kia := 0
	var wounded := 0
	var heads: int = (report.get("extracted", []) as Array).size()
	for c: Dictionary in report.get("casualties", []):
		match String(c.get("status", "")):
			"kia":
				kia += 1
				heads += 1
			"mia":
				heads += 1
			"wounded":
				wounded += 1
	# The standing high command squads (Heroes: "never charged per deployment") have a field rate
	# of their own, operations.hc_per_head_day (economy pass 2026-10-22; the squad's rate if unset).
	var hc_heads := 0
	var hc_names: Array = report.get("hc_names", [])
	if not hc_names.is_empty():
		for n: Variant in report.get("extracted", []):
			if n in hc_names:
				hc_heads += 1
		for c: Dictionary in report.get("casualties", []):
			if String(c.get("status", "")) in ["kia", "mia"] and c.get("name") in hc_names:
				hc_heads += 1
	var rate := Prices.operations("per_head_day")
	var hc_rate: int = int((Prices.data().get("operations", {}) as Dictionary).get("hc_per_head_day", rate))
	var field := ((heads - hc_heads) * rate + hc_heads * hc_rate) * maxi(days, 1)
	if field > 0:
		var who := "%d people" % heads if hc_heads == 0 or hc_rate == rate else "%d people, %d of them high command" % [heads, hc_heads]
		lines.append({"what": "Field costs: ammo, meds, fuel, comms (%s x %d days)" % [who, maxi(days, 1)], "amount": field, "charge": true})
		if use_stocks:
			# FOB stocks cover part of the field costs (Pallets.offset_preview).
			var stocked := Pallets.offset_preview(field, "field_costs")
			if int(stocked.offset) > 0:
				used = stocked.used
				lines.append({"what": "Covered by FOB stocks", "amount": -int(stocked.offset), "charge": true})
	# In a campaign each man's benefit is paid when his death is confirmed (his tags home: BaseHub.
	# server_pay_death_benefit) and is a line of its own in `run` ("benefits_paid"); a report
	# without the roster (the board alone) still counts the dead.
	if kia > 0 and not bool(report.get("benefits_paid", false)):
		lines.append({"what": "Death benefit (%d KIA)" % kia, "amount": kia * Prices.operations("kia_benefit"), "charge": true})
	if wounded > 0:
		lines.append({"what": "Treatment (%d wounded)" % wounded, "amount": wounded * Prices.operations("wounded_care"), "charge": true})
	var total := 0
	var charge := 0
	var running_total := 0
	for l: Dictionary in lines:
		total += int(l.amount)
		if bool(l.charge):
			charge += int(l.amount)
		if bool(l.get("running", false)):
			running_total += int(l.amount)
	return {"lines": lines, "total": total, "charge": charge, "running": running_total, "used": used}


static func _add(rep: Dictionary, faction: String, delta: int) -> void:
	if faction == "" or delta == 0:
		return
	rep[faction] = int(rep.get(faction, 0)) + delta


## Whether pool entry `index` still fits the salvage budget.
static func can_pick(debrief: Dictionary, index: int) -> bool:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	if index < 0 or index >= pool.size() or index in salvage.get("picked", []):
		return false
	return int(salvage.get("spent", 0)) + int(pool[index].value) <= int(salvage.get("budget", 0))


## Where a debrief's money came from (economy overhaul 2026-10-20: the screen showed only where
## it went): [{"what", "amount"}] (negative: fines and clawbacks), the contract's pay first, then
## what was sold in the debrief itself (intel to a faction, tagged lots sold now). Loot and
## salvage sold at the base afterwards aren't in it.
static func money_in(debrief: Dictionary) -> Array:
	var totals: Dictionary = debrief.get("totals", {})
	var out: Array = []
	var add := func(what: String, amount: int) -> void:
		if amount != 0:
			out.append({"what": what, "amount": amount})
	add.call("Advances (paid at signing)", int(totals.get("advance", 0)))
	add.call("Completion pay", int(totals.get("completion", 0)))
	add.call("Bonuses", int(totals.get("bonuses", 0)))
	add.call("Civilian fines", -int(totals.get("fines", 0)))
	add.call("Advances clawed back", -int(totals.get("clawback", 0)))
	var intel := 0
	for e: Dictionary in debrief.get("intel", []):
		if String(e.get("status", "")) == "sold":
			intel += int(e.get("price", 0))
	add.call("Intel sold", intel)
	var lots := 0
	for lot: Dictionary in debrief.get("tagged", []):
		if String(lot.get("status", "")) == "sold":
			lots += int(lot.get("sold_for", 0))
	add.call("Pallets and vehicles sold", lots)
	add.call("Bounties", int(debrief.get("bounties", 0)))  # claude/income: a leader taken (Bounties)
	return out


## The debrief in plain lines (the screen shows this; tests read it).
static func summary(debrief: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in debrief.get("contracts", []):
		out.append("%s - %s" % [c.title, String(c.outcome).to_upper()])
		out.append("  Advance (paid at signing): $%s" % money(c.advance))
		out.append("  Completion: $%s" % money(c.completion))
		if int(c.get("withheld", 0)) > 0:
			out.append("  Held back by the client (not done: %s): -$%s" % [String(c.get("withheld_for", "")).get_slice(" (", 0), money(c.withheld)])
		for b: Dictionary in c.bonuses:
			out.append("  %s: $%s" % [b.text, money(b.amount)])
		if int(c.get("clawback", 0)) > 0:
			out.append("  Advance clawed back (voided, %s): -$%s" % [c.get("clawback_term", "full"), money(c.clawback)])
		out.append_array(Operations.summary_lines(c))  # an operation's phases, each as it went (D3)
		for l: String in c.get("objectives", []):
			out.append("    " + l)
	var totals: Dictionary = debrief.get("totals", {})
	for l: Dictionary in debrief.get("expenses", []):
		out.append("Expense: %s: -$%s" % [l.what, money(l.amount)])
	if debrief.has("expenses_total"):
		var running := int(debrief.get("running_total", 0))
		out.append("Expenses: -$%s; the job's net after its expenses (before loot and salvage): $%s" % [money(int(debrief.expenses_total) - running), money(debrief.get("net", 0))])
		if running != 0:
			out.append("Company running costs these days (wages, upkeep, loans; paid deployed or not): -$%s" % money(running))
	if int(debrief.get("civilians", 0)) > 0:
		out.append("Civilian casualties: %d, fines -$%s" % [debrief.civilians, money(debrief.fines)])
	out.append("Paid now: $%s (contract value $%s)" % [money(totals.get("paid_now", 0)), money(totals.get("contract_value", 0))])
	for f: String in debrief.get("rep", {}):
		out.append("Reputation %s: %+d" % [MissionRegistry.faction_name(f), int(debrief.rep[f])])
	if int(debrief.get("locals", 0)) != 0:
		out.append("Reputation with the locals: %+d" % int(debrief.locals))
	return out


## 12345 -> "12,345".
static func money(amount: Variant) -> String:
	var n := int(amount)
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


# --- Grouping for the debrief screen -------------------------------------------------------
## Captain, 2026-10-14 (v0.3.1): "this ui needs a pass for sure. its hard to select the items
## you want": the carried-out list was one run-on line per item and the salvage pool one row
## per field lot, the same item many times over. The screen groups both by item type; the
## claim rules stay per pool lot (host-authoritative pick/unpick by index, as before).

## The categories the screen groups by, in display order.
const CATEGORIES := ["weapons", "armour", "ammo", "medical", "grenades", "intel", "other"]
const CATEGORY_NAMES := {"weapons": "Weapons", "armour": "Armour and kit", "ammo": "Ammo and magazines", "medical": "Medical",
	"grenades": "Grenades and explosives", "intel": "Intel and salvage", "other": "Other"}


## Which CATEGORIES entry item `id` falls under (from its item type and tags).
static func category_of(id: Variant) -> String:
	var sid := StringName(id)
	if MissionRegistry.is_intel(sid):
		return "intel"
	var item: ItemData = ItemDB.get_item(sid) if ItemDB.has_item(sid) else null
	if item == null:
		return "other"
	if "throwable" in item.tags or "explosive" in item.tags:
		return "grenades"
	match item.type:
		"weapon", "launcher", "optic":
			return "weapons"
		"armor", "plate", "backpack", "pouch":
			return "armour"
		"ammo", "mag":
			return "ammo"
		"medical", "aid_bag", "tq":
			return "medical"
		"intel", "salvage", "objective":
			return "intel"
	if "salvage" in item.tags:
		return "intel"
	return "other"


static func item_name(id: Variant) -> String:
	var item: ItemData = ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null
	return item.name if item else String(id)


## `items` ([{"id", "count"}]) summed per item type: [{"id", "name", "category", "count"}],
## by category (CATEGORIES order) then name. The counts add up to the raw list's.
static func group_items(items: Array) -> Array:
	var by_id := {}
	for e: Dictionary in items:
		var id := String(e.get("id", ""))
		if not by_id.has(id):
			by_id[id] = {"id": id, "name": item_name(id), "category": category_of(id), "count": 0}
		by_id[id].count = int(by_id[id].count) + int(e.get("count", 1))
	var out: Array = by_id.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := CATEGORIES.find(a.category)
		var cb := CATEGORIES.find(b.category)
		return ca < cb if ca != cb else String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


## The salvage pool summed per item type: [{"id", "name", "category", "lots": [pool indices],
## "picked": [picked pool indices], "count", "value", "picked_count", "picked_value", "each"
## (value per unit, averaged over the lots)}]. Sorted by `sort`: "value" (total, highest
## first), "category" or "name".
static func salvage_groups(debrief: Dictionary, sort := "value") -> Array:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var picked: Array = salvage.get("picked", [])
	var by_id := {}
	for i in pool.size():
		var e: Dictionary = pool[i]
		var id := String(e.get("id", ""))
		if not by_id.has(id):
			by_id[id] = {"id": id, "name": item_name(id), "category": category_of(id), "lots": [], "picked": [],
				"count": 0, "value": 0, "picked_count": 0, "picked_value": 0, "each": 0}
		var g: Dictionary = by_id[id]
		g.lots.append(i)
		g.count += int(e.get("count", 1))
		g.value += int(e.get("value", 0))
		if i in picked:
			g.picked.append(i)
			g.picked_count += int(e.get("count", 1))
			g.picked_value += int(e.get("value", 0))
	var out: Array = by_id.values()
	for g: Dictionary in out:
		g.each = roundi(float(g.value) / maxf(1.0, float(g.count)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match sort:
			"category":
				var ca := CATEGORIES.find(a.category)
				var cb := CATEGORIES.find(b.category)
				if ca != cb:
					return ca < cb
			"name":
				pass
			_:
				if int(a.value) != int(b.value):
					return int(a.value) > int(b.value)
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


## Pool indices to claim for `n` more lots of item `id` (-1: as many as fit), cheapest lot
## first, each fitting what's left of the budget after the ones before it (so the host, which
## checks every pick, takes them all in order).
static func picks_for(debrief: Dictionary, id: String, n := 1) -> Array:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var picked: Array = salvage.get("picked", [])
	var left := int(salvage.get("budget", 0)) - int(salvage.get("spent", 0))
	var lots: Array = []
	for i in pool.size():
		if String(pool[i].get("id", "")) == id and not i in picked:
			lots.append(i)
	lots.sort_custom(func(a: int, b: int) -> bool: return int(pool[a].value) < int(pool[b].value))
	var out: Array = []
	for i: int in lots:
		if n >= 0 and out.size() >= n:
			break
		if int(pool[i].value) > left:
			break
		out.append(i)
		left -= int(pool[i].value)
	return out


## Pool indices to return for `n` claimed lots of item `id` (-1: all), dearest first.
static func unpicks_for(debrief: Dictionary, id: String, n := 1) -> Array:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var lots: Array = (salvage.get("picked", []) as Array).filter(func(i: int) -> bool: return String(pool[i].get("id", "")) == id)
	lots.sort_custom(func(a: int, b: int) -> bool: return int(pool[a].value) > int(pool[b].value))
	return lots if n < 0 else lots.slice(0, n)


## The "claim best value" helper: pool indices to add to what's claimed, dearest lot first
## while it fits the budget left (greedy: fills the budget with the most valuable kit).
static func best_value_picks(debrief: Dictionary) -> Array:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var picked: Array = salvage.get("picked", [])
	var left := int(salvage.get("budget", 0)) - int(salvage.get("spent", 0))
	var lots: Array = range(pool.size()).filter(func(i: int) -> bool: return not i in picked)
	lots.sort_custom(func(a: int, b: int) -> bool: return int(pool[a].value) > int(pool[b].value))
	var out: Array = []
	for i: int in lots:
		if int(pool[i].value) <= left:
			out.append(i)
			left -= int(pool[i].value)
	return out


## Why no more of item `id` can be claimed ("" when one more lot fits).
static func pick_block_reason(debrief: Dictionary, id: String) -> String:
	if debrief.get("finished", false):
		return "The debrief is closed"
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var picked: Array = salvage.get("picked", [])
	var cheapest := -1
	for i in pool.size():
		if String(pool[i].get("id", "")) == id and not i in picked:
			cheapest = int(pool[i].value) if cheapest < 0 else mini(cheapest, int(pool[i].value))
	if cheapest < 0:
		return "All of it is claimed"
	var left := int(salvage.get("budget", 0)) - int(salvage.get("spent", 0))
	if cheapest > left:
		return "Over budget: the cheapest lot is $%s, $%s of the budget left" % [money(cheapest), money(left)]
	return ""
