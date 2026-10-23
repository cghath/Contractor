class_name Bounties
extends RefCounted
## Captures and bounties (Income 2; docs/income.md 2): what the company takes off the enemy sold
## to whoever pays best for it, by standing.
##
## - **Captured vehicles and heavy weapons**: a vehicle or gun tagged in the field comes home at
##   extraction as a lot (Pallets) and can be stored at the FOB. From storage it sells to a buyer
##   (data "captures" "buyers": the Salvage Union, Halloran, US Forces, the Highland Front for
##   guns and technicals) at its value x the buyer's rate x what the buyer pays the company for its
##   standing; each buyer has a standing floor and its own standing effects. Or a high command
##   squad delivers it (SideJobs "recover"): "deliver_mult" more, with the side job's risks; a
##   failed delivery loses the lot.
## - **Bounties** on the living war's leaders (factions.json "leaders": the HVTs of hvt_capture,
##   manhunt and hvt_kill contracts): posted by the lawful employer most at war with the faction,
##   worth more while the faction is strong, paid at the debrief of the contract that took the
##   man: alive (hvt_capture, manhunt) the full bounty; dead (hvt_kill) "dead_mult" of it, and only
##   with proof (the job's ID papers objective done, missions 2).
## - **Intel buyers**: intel sold in the debrief fetches a price and standing by who buys it
##   (data "intel_buyers"): lawful forces (fair, standing), the fixers' factions (more), a rival of
##   the faction the intel is about (more still; the lawful factions think less of the company),
##   the faction itself buying its secrets back (the most; worse with the lawful).
## All numbers in data/income.json, Proposed.

const LEDGER_CAPTURE := "Capture sold"
const LEDGER_BOUNTY := "Bounty"


static func cfg(group: String) -> Dictionary:
	return Income.data().get(group, {})


# --- Captured vehicles and heavy weapons --------------------------------------------------

## The vehicle lots in FOB storage: [{"index", "lot"}].
static func stored_captures() -> Array:
	var out: Array = []
	var store: Array = Economy.pallet_store()
	for i in store.size():
		if String((store[i] as Dictionary).get("kind", "")) == "vehicle":
			out.append({"index": i, "lot": store[i]})
	return out


## Who would buy `lot` now and for what: [{"faction", "from", "price", "rep", "lawful_hit", "why"}]
## ("why" non-empty: this buyer won't deal: standing too low, or not something it buys).
static func capture_buyers(lot: Dictionary) -> Array:
	var out: Array = []
	for b: Dictionary in cfg("captures").get("buyers", []):
		var f := String(b.faction)
		var why := ""
		if b.has("models") and not String(lot.get("what", "")) in (b.models as Array):
			continue
		if Economy.reputation(f) < int(b.get("min_rep", 0)):
			why = "%s won't deal until the company stands at %d with them (now %d)" % [MissionRegistry.faction_name(f), int(b.get("min_rep", 0)), Economy.reputation(f)]
		elif Economy.work_problem(f) != "":
			why = Economy.work_problem(f)
		out.append({"faction": f, "from": String(b.get("from", MissionRegistry.faction_name(f))), "price": capture_price(lot, b),
			"rep": int(b.get("rep", 0)), "lawful_hit": int(b.get("lawful_hit", 0)), "why": why})
	return out


static func capture_price(lot: Dictionary, b: Dictionary) -> int:
	return roundi(int(lot.get("value", 0)) * float(b.get("mult", 1.0)) * Economy.pay_mult(String(b.faction)) / 100.0) * 100


static func _buyer(faction: String) -> Dictionary:
	for b: Dictionary in cfg("captures").get("buyers", []):
		if String(b.faction) == faction:
			return b
	return {}


## Host: sells stored lot `index` to `faction`. Returns "" or why not.
static func server_sell_capture(index: int, faction: String) -> String:
	var store: Array = Economy.pallet_store()
	if index < 0 or index >= store.size() or String((store[index] as Dictionary).get("kind", "")) != "vehicle":
		return "Nothing in storage there"
	var lot: Dictionary = store[index]
	var offer := _offer(lot, faction)
	if offer.is_empty() or String(offer.why) != "":
		return "That buyer won't take it" if offer.is_empty() else String(offer.why)
	Economy.server_unstore_lot(index)
	_pay_capture(lot, offer, 1.0)
	return ""


static func _offer(lot: Dictionary, faction: String) -> Dictionary:
	for o: Dictionary in capture_buyers(lot):
		if String(o.faction) == faction:
			return o
	return {}


static func _pay_capture(lot: Dictionary, offer: Dictionary, mult: float, by := "") -> int:
	var price := roundi(int(offer.price) * mult)
	Economy.add_cash(price, "%s: %s to %s%s" % [LEDGER_CAPTURE, String(lot.get("label", "a vehicle")), String(offer.from), (", delivered by %s" % by) if by != "" else ""])
	Economy.change_reputation(String(offer.faction), int(offer.rep), "bought a captured %s" % String(lot.get("label", "vehicle")))
	_lawful_hit(int(offer.lawful_hit), "sold captured weapons to %s" % MissionRegistry.faction_name(String(offer.faction)))
	Income.report("Capture sold", "%s went to %s for $%s." % [String(lot.get("label", "A vehicle")), String(offer.from), DebriefCalc.money(price)], "good",
		[["Paid", price]])
	return price


static func _lawful_hit(n: int, why: String) -> void:
	if n == 0:
		return
	for fid: String in MissionRegistry.faction_ids():
		if bool(MissionRegistry.faction(fid).get("lawful", false)):
			Economy.change_reputation(fid, n, why, false)


## What a delivery by a high command squad pays and risks for stored lot `index` to `faction`:
## an offer SideJobs can send ({} when the buyer won't deal).
static func delivery_offer(index: int, faction: String) -> Dictionary:
	var store: Array = Economy.pallet_store()
	if index < 0 or index >= store.size():
		return {}
	var lot: Dictionary = store[index]
	var o := _offer(lot, faction)
	if o.is_empty() or String(o.why) != "":
		return {}
	var zone := _buyer_zone(faction)
	return {"id": "dv%d_%s" % [index, faction], "kind": "recover", "client": faction, "from": String(o.from), "mult": 1.0, "zone": zone,
		"days": int(SideJobs.kind("recover").get("days", 2)), "danger": snappedf(Income.zone_danger(zone), 0.01),
		"pay": roundi(int(o.price) * float(cfg("captures").get("deliver_mult", 1.25)) / 100.0) * 100, "expires": Economy.day(), "lot": lot.duplicate(true)}


## Where a buyer takes delivery: one of its own zones in the war, else the nearest war zone held by
## a friend of the company, else the first war zone.
static func _buyer_zone(faction: String) -> String:
	var own := WorldSites.zones_of(faction)
	if not own.is_empty():
		return own[0]
	for z: String in WorldSites.war_zones():
		if Income.zone_danger(z) < 0.3:
			return z
	var all := WorldSites.war_zones()
	return all[0] if not all.is_empty() else ""


## Host: sends squad `did` to deliver stored lot `index` to `faction`. Returns "" or why not.
static func server_deliver(index: int, faction: String, did: String) -> String:
	var o := delivery_offer(index, faction)
	if o.is_empty():
		return "That buyer won't take it"
	var why := SideJobs.cant_send(Campaign.section(&"roster"), did)
	if why != "":
		return why
	Economy.server_unstore_lot(index)
	o["advance"] = 0
	(Income.state().offers as Array).append(o)
	why = SideJobs.server_send(String(o.id), did)
	return why


## Host (SideJobs, a delivery back with the job done): the buyer pays the delivered price.
static func server_recovered(job: Dictionary) -> int:
	var lot: Dictionary = job.get("lot", {})
	var o := {"faction": String(job.client), "from": String(job.from), "price": int(job.pay), "rep": int(_buyer(String(job.client)).get("rep", 0)),
		"lawful_hit": int(_buyer(String(job.client)).get("lawful_hit", 0))}
	return _pay_capture(lot, o, 1.0, String(job.callsign))


# --- Bounties on the living war's leaders -------------------------------------------------

## Every open bounty: [{"faction", "leader", "role", "alive", "dead", "poster", "poster_name"}],
## the factions in the war that still have leaders free.
static func open_bounties() -> Array:
	var out: Array = []
	var b := cfg("bounties")
	for fid: String in MissionRegistry.faction_ids():
		var f := MissionRegistry.faction(fid)
		var leaders: Array = f.get("leaders", [])
		if leaders.is_empty() or WorldSites.is_wiped(fid):
			continue
		var down := WorldSites.leaders_down(fid)
		var poster := poster_of(fid)
		for l: String in leaders:
			if l in down:
				continue
			var alive := bounty(fid, l)
			out.append({"faction": fid, "leader": l, "role": String((f.get("leader_roles", {}) as Dictionary).get(l, "commander")),
				"alive": alive, "dead": roundi(alive * float(b.get("dead_mult", 0.6)) / 100.0) * 100, "poster": poster,
				"poster_name": MissionRegistry.faction_name(poster)})
	return out


## The bounty on `leader` of `faction`, alive: by role, more while the faction is strong.
static func bounty(faction: String, leader: String) -> int:
	var b := cfg("bounties")
	var role := String((MissionRegistry.faction(faction).get("leader_roles", {}) as Dictionary).get(leader, "commander"))
	var base := float((b.get("roles", {}) as Dictionary).get(role, 50000))
	var strong := 1.0 + WorldSites.strength(faction) / 100.0 * float(b.get("strength_bonus", 0.5))
	return roundi(base * strong / 500.0) * 500


## Who posts the bounty on `faction`: the lawful employer at war with it the company stands best
## with, else US Forces.
static func poster_of(faction: String) -> String:
	var best := ""
	for fid: String in MissionRegistry.employers():
		var f := MissionRegistry.faction(fid)
		if bool(f.get("lawful", false)) and faction in (f.get("enemies", []) as Array):
			if best == "" or Economy.reputation(fid) > Economy.reputation(best):
				best = fid
	return best if best != "" else "us_forces"


## Host (Contracts, a debrief): contract `c` closed with debrief line `result`. A completed job
## that took a leader pays his bounty: alive for a capture or a manhunt, dead for a kill with its
## proof brought out. Returns what was paid.
static func server_contract_closed(c: Dictionary, result: Dictionary) -> int:
	var leader := String(c.get("leader", ""))
	var faction := String(c.get("target", ""))
	if String(result.get("outcome", "")) != "completed" or leader == "" or faction == "":
		return 0
	var type := String(c.get("type", ""))
	var alive := type != "hvt_kill"
	var amount := bounty(faction, leader)
	var poster := poster_of(faction)
	var who := "%s of %s" % [leader, MissionRegistry.faction_name(faction)]
	if not alive:
		if int(result.get("withheld", 0)) > 0:
			Income.report("Bounty refused", "%s posted $%s for %s dead, but wants proof: no ID papers came out." % [MissionRegistry.faction_name(poster),
				DebriefCalc.money(roundi(amount * float(cfg("bounties").get("dead_mult", 0.6)))), who], "bad")
			return 0
		amount = roundi(amount * float(cfg("bounties").get("dead_mult", 0.6)) / 100.0) * 100
	Economy.add_cash(amount, "%s: %s (%s), from %s" % [LEDGER_BOUNTY, who, "alive" if alive else "dead, with proof", MissionRegistry.faction_name(poster)])
	Economy.change_reputation(poster, int(cfg("bounties").get("rep", 3)), "bounty on %s" % leader)
	Income.report("Bounty paid", "%s paid $%s for %s, %s." % [MissionRegistry.faction_name(poster), DebriefCalc.money(amount), who,
		"brought in alive" if alive else "dead, the papers as proof"], "good", [["Bounty", amount]])
	return amount


# --- Intel buyers -------------------------------------------------------------------------

## What kind of buyer `faction` is for intel about `subject`: "subject", "rival", "lawful",
## "fixer" or "other".
static func intel_buyer_kind(faction: String, subject: String) -> String:
	if subject != "" and faction == subject:
		return "subject"
	var f := MissionRegistry.faction(faction)
	if bool(f.get("lawful", false)):
		return "lawful"
	for fx: Dictionary in MissionRegistry.fixers():
		if String(fx.get("faction", "")) == faction:
			return "fixer"
	if subject != "" and String(f.get("role", "")) == "hostile" and subject in (f.get("enemies", []) as Array):
		return "rival"
	return "other"


static func intel_rule(faction: String, subject: String) -> Dictionary:
	var rules: Dictionary = cfg("intel_buyers")
	return rules.get(intel_buyer_kind(faction, subject), rules.get("other", {"mult": 1.0, "rep": 2}))


## What `faction` pays for `count` of intel `item_id` about `subject`.
static func intel_price(item_id: StringName, count: int, faction: String, subject: String) -> int:
	return roundi(Prices.intel_sale_value(item_id, count) * float(intel_rule(faction, subject).get("mult", 1.0)))


## The buyer list's line: "US Forces: $4,000, +3 standing".
static func intel_offer_text(item_id: StringName, count: int, faction: String, subject: String) -> String:
	var r := intel_rule(faction, subject)
	var hit := int(r.get("lawful_hit", 0))
	return "%s: $%s, %+d standing%s" % [MissionRegistry.faction_name(faction), DebriefCalc.money(intel_price(item_id, count, faction, subject)),
		int(r.get("rep", 0)), (", lawful factions %+d" % hit) if hit != 0 else ""]


## Host (Contracts.server_sell_intel): the buyer's standing and the lawful factions' view.
static func server_intel_sold(faction: String, subject: String) -> void:
	var r := intel_rule(faction, subject)
	Economy.change_reputation(faction, int(r.get("rep", 2)), "bought intel")
	_lawful_hit(int(r.get("lawful_hit", 0)), "intel sold to %s" % MissionRegistry.faction_name(faction))
