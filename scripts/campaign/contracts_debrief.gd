class_name DebriefCalc
extends RefCounted
## The debrief's sums, pure (wave 4, W10): what each contract of a deployment came to, the
## fines, reputation changes, the salvage budget and pool, intel brought out and the days it
## all took. Contracts.server_end_deployment applies the result to the campaign.
##
## The result (JSON-safe, replicated to every peer):
## - "contracts": per contract {"cid", "title", "employer", "outcome" ("completed",
##   "failed", "voided", "lapsed", "aborted"), "advance" (paid at signing), "completion",
##   "bonuses": [{"text", "amount"}], "pay" (completion + bonuses), "clawback" (a voided
##   contract's advance taken back when "void_claws_back_advance" is on: Captain's "pays
##   nothing"), "salvage_share", "objectives": [lines]};
## - "civilians", "fines"; "rep": {faction: change}, "locals": change;
## - "salvage": {"share", "pool": [{"id", "count", "state", "value"}], "pool_value",
##   "budget", "picked": [pool indices], "spent"};
## - "items_out": everything carried out (banked to the base);
## - "intel": [{"id", "count", "status": "pending"}] (intel among the items out);
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
			"advance": int(deal.get("advance", 0)), "completion": 0, "bonuses": [], "pay": 0, "clawback": 0, "salvage_share": 0.0,
			"objectives": mine.map(func(o: Dictionary) -> String: return Objectives.line(o))}
		var employer := String(c.get("employer", ""))
		match outcome:
			"completed":
				line.completion = int(deal.get("completion", 0)) + int(c.get("raise", 0))
				for o: Dictionary in mine:
					if o.optional and o.state == Objectives.DONE and float(o.get("bonus_share", 0.0)) > 0.0:
						line.bonuses.append({"text": "Bonus: %s" % String(o.text).trim_prefix("Bonus: "), "amount": roundi(pay_total * float(o.bonus_share))})
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
				if bool(MissionRegistry.setting("void_claws_back_advance", true)):
					line.clawback = line.advance
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
		if value <= 0:
			continue
		pool.append({"id": String(id), "count": int(entry.get("count", 1)), "state": entry.get("state", {}), "value": value})
		pool_value += value
	var items_out: Array = (report.get("items", []) as Array).duplicate(true)
	var intel: Array = []
	for entry: Dictionary in items_out:
		if MissionRegistry.is_intel(StringName(entry.get("id", ""))):
			intel.append({"id": String(entry.id), "count": int(entry.get("count", 1)), "status": "pending", "buyer": ""})
	return {
		"contracts": lines, "civilians": civilians, "fines": totals.fines,
		"rep": rep, "locals": civilians * int(S.call("civilian_rep_locals")),
		"salvage": {"share": best_share, "pool": pool, "pool_value": pool_value, "budget": floori(pool_value * best_share), "picked": [], "spent": 0},
		"items_out": items_out, "intel": intel, "casualties": (report.get("casualties", []) as Array).duplicate(true),
		"days": maxi(days, 1), "totals": totals, "finished": false,
	}


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


## The debrief in plain lines (the screen shows this; tests read it).
static func summary(debrief: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in debrief.get("contracts", []):
		out.append("%s - %s" % [c.title, String(c.outcome).to_upper()])
		out.append("  Advance (paid at signing): $%s" % money(c.advance))
		out.append("  Completion: $%s" % money(c.completion))
		for b: Dictionary in c.bonuses:
			out.append("  %s: $%s" % [b.text, money(b.amount)])
		if int(c.get("clawback", 0)) > 0:
			out.append("  Advance clawed back (voided): -$%s" % money(c.clawback))
		for l: String in c.get("objectives", []):
			out.append("    " + l)
	var totals: Dictionary = debrief.get("totals", {})
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
