class_name FobBusiness
extends RefCounted
## FOB businesses (Income 3; docs/income.md 3): once the company's home is a FOB it holds, it can
## run businesses from it: convoy security for the locals, a militia training camp (raises rebel
## support), checkpoint tolls on the roads it holds, motor pool rentals. Each needs its people
## (local staff, paid in its upkeep), supplies (the FOB's stocks: Economy.stock, kept from pallets)
## and upkeep, and pays daily by what the company has made of the war: the roads it holds, the
## vehicles at home, the friendly ground around it.
##
## The living war threatens them: every day raiders may move on one (more often the more dangerous
## the FOB's ground and the fronts next to it). A threatened business puts a protection contract
## (Hold the line, at the FOB) on the board: done, the threat lifts and the locals think better
## of the company; left, the business is raided (closed for days, a share of its setup to put
## right). The FOB lost, every business goes with it.
##
## Section "income" "businesses": id -> {"id", "opened", "closed_until", "threat" ({"since",
## "until", "cid", "by"}), "earned", "days"}. Numbers in data/income.json "businesses", Proposed.

const LEDGER_PAY := "Business"
## The economy sim's stand-in for "home is a FOB" (-1: ask ZoneControl; 0 no; 1 yes).
static var fob_override := -1
const LEDGER_COST := "Business upkeep"


static func cfg() -> Dictionary:
	return Income.data().get("businesses", {})


static func c(key: String, default := 0.0) -> float:
	return float(cfg().get(key, default))


static func kinds() -> Array:
	return cfg().get("kinds", [])


static func kind(id: String) -> Dictionary:
	for k: Dictionary in kinds():
		if String(k.id) == id:
			return k
	return {}


static func running(s: Dictionary = {}) -> Dictionary:
	var st := s if not s.is_empty() else Income.view()
	return st.get("businesses", {})


static func _mine() -> Dictionary:
	var s := Income.state()
	if not s.has("businesses"):
		s["businesses"] = {}
	return s.businesses


## Whether the company holds a FOB to run businesses from (home is a FOB, not the LHD).
static func has_fob() -> bool:
	return fob_override == 1 if fob_override >= 0 else not ZoneControl.home_is_lhd()


## The zone the FOB stands in (the inland FOB's own, or the zone it was built in).
static func fob_zone() -> String:
	var z := ZoneControl.fob_zone()
	return z if z != "" else RegionMap.BASE


## How dangerous the FOB's ground is for its businesses, 0..1: its own zone's danger, and each
## neighbour held by an enemy or fought over.
static func fob_danger() -> float:
	var z := fob_zone()
	var d := Income.zone_danger(z) if WorldSites.is_war_zone(z) else float(Income.data().get("danger", {}).get("company", 0.12))
	for n: Dictionary in RegionMap.links(z):
		var nz := String(n.to)
		if not WorldSites.is_war_zone(nz):
			continue
		var h := WorldSites.holder_now(nz)
		if not WorldSites.front(nz).is_empty() or (h in MissionRegistry.enemies()):
			d += c("neighbour_danger", 0.08)
	return clampf(d, 0.05, 1.0)


## The units a business pays per: roads, vehicles, friendly zones (see data "unit").
static func units(id: String) -> int:
	match id:
		"tolls":
			var n := 1  # the FOB's own supply road
			for z: String in WorldSites.war_zones():
				if ZoneControl.is_company(z) and z != fob_zone():
					var a: Array = ZoneControl.zone_def_raw(z).get("assets", [])
					if "route" in a or "crossing" in a:
						n += 1
			return n
		"convoy":
			var n := 0
			var near: Array = [fob_zone()] + RegionMap.links(fob_zone()).map(func(l: Dictionary) -> String: return String(l.to))
			for z: Variant in near:
				var zid := String(z)
				var a: Array = ZoneControl.zone_def_raw(zid).get("assets", [])
				if WorldSites.is_war_zone(zid) and ("route" in a or "crossing" in a) and Income.zone_danger(zid) < 0.4:
					n += 1
			return n
		"rentals":
			var n := 0
			for v: Dictionary in MotorPool.list():
				if String(v.get("out", "")) == "" and int(v.get("ready_day", 0)) <= Economy.day():
					n += 1
			return n
	return 0


## What business `id` would pay a day now, before supplies: pay + per_unit x units.
static func day_pay(id: String) -> int:
	var k := kind(id)
	return int(k.get("pay", 0)) + int(k.get("per_unit", 0)) * units(id)


## Why business `id` can't open now ("" if it can).
static func cant_open(id: String) -> String:
	var k := kind(id)
	if k.is_empty():
		return "No such business"
	if not has_fob():
		return "Needs a FOB: the company runs from the LHD"
	if running().has(id):
		return "Already running"
	if bool(k.get("needs_vehicle", false)) and MotorPool.list().is_empty():
		return "Needs a vehicle in the motor pool"
	if Economy.cash() < int(k.get("setup", 0)):
		return "Setting it up costs $%s" % DebriefCalc.money(k.get("setup", 0))
	return ""


## Host: opens business `id`. Returns "" or why not.
static func server_open(id: String) -> String:
	var why := cant_open(id)
	if why != "":
		return why
	var k := kind(id)
	Economy.add_cash(-int(k.setup), "%s set up: %s" % [LEDGER_COST, String(k.name)])
	_mine()[id] = {"id": id, "opened": Economy.day(), "closed_until": 0, "threat": {}, "earned": 0, "days": 0}
	Contracts._notify_all("%s opens at the FOB: about $%s a day" % [String(k.name), DebriefCalc.money(day_pay(id) - int(k.get("upkeep", 0)))])
	return ""


## Host: closes business `id` for good (nothing back). Returns "" or why not.
static func server_close(id: String) -> String:
	if not _mine().has(id):
		return "Not running"
	_mine().erase(id)
	Contracts._notify_all("%s closed" % String(kind(id).get("name", id)))
	return ""


## Host: a day or more passed (Income.server_advance_days): each business pays and costs its day,
## threats come and go, the FOB lost takes them all.
static func server_day(days: int) -> void:
	var mine := _mine()
	if mine.is_empty():
		return
	if not has_fob():
		for id: String in mine.keys():
			Income.report("%s lost" % String(kind(id).get("name", id)), "The FOB is gone and the business with it.", "bad")
		mine.clear()
		return
	var today := Economy.day()
	for i in days:
		var day := today - days + 1 + i
		for id: String in mine.keys():
			_run_day(id, mine[id], day)
		_roll_threat(day)


static func _run_day(id: String, b: Dictionary, day: int) -> void:
	var k := kind(id)
	var t: Dictionary = b.get("threat", {})
	if not t.is_empty() and day > int(t.get("until", 0)):
		_raided(id, b, day)
	if int(b.get("closed_until", 0)) >= day:
		return
	var short := false
	var sup: Dictionary = k.get("supplies", {})
	for s: String in sup:
		if Economy.stock(s) >= int(sup[s]):
			Economy.server_take_stock(s, int(sup[s]))
		else:
			short = true
	var pay := day_pay(id)
	if short:
		pay = roundi(pay * c("short_pay", 0.5))
	var net := pay - int(k.get("upkeep", 0))
	Economy.add_cash(pay, "%s: %s%s" % [LEDGER_PAY, String(k.name), " (short of supplies)" if short else ""])
	Economy.add_cash(-int(k.get("upkeep", 0)), "%s: %s" % [LEDGER_COST, String(k.name)])
	b["earned"] = int(b.get("earned", 0)) + net
	b["days"] = int(b.get("days", 0)) + 1
	if float(k.get("rebel_support", 0.0)) != 0.0:
		RebelSupport.change(RebelSupport.region_of(fob_zone()), float(k.rebel_support), "the FOB's militia camp")
	if int(k.get("locals_per_week", 0)) != 0 and int(b.days) % 7 == 0:
		Economy.change_locals(int(k.locals_per_week))


## Raiders may move on a business today: the chance grows with the FOB's danger.
static func _roll_threat(day: int) -> void:
	var mine := _mine()
	var open: Array = mine.keys().filter(func(id: String) -> bool:
		return (mine[id].get("threat", {}) as Dictionary).is_empty() and int(mine[id].get("closed_until", 0)) < day)
	if open.is_empty():
		return
	var r := Income.rng(day, "business_threat")
	if r.randf() >= c("raid_base", 0.02) + c("raid_danger", 0.12) * fob_danger():
		return
	open.sort()
	var id := String(open[r.randi() % open.size()])
	server_threaten(id, day, r)


## The faction most likely to raid the FOB: an enemy holding or attacking a neighbouring zone, else
## the strongest enemy in the war.
static func raider() -> String:
	for n: Dictionary in RegionMap.links(fob_zone()):
		var f := WorldSites.front(String(n.to))
		if not f.is_empty() and String(f.by) in MissionRegistry.enemies():
			return String(f.by)
		var h := WorldSites.holder_now(String(n.to))
		if h in MissionRegistry.enemies():
			return h
	var best := ""
	for e: String in MissionRegistry.enemies():
		if not WorldSites.is_wiped(e) and (best == "" or WorldSites.strength(e) > WorldSites.strength(best)):
			best = e
	return best


## Host: raiders threaten business `id`: a protection contract goes on the board.
static func server_threaten(id: String, day: int, r: RandomNumberGenerator = null) -> Dictionary:
	var b: Dictionary = _mine().get(id, {})
	if b.is_empty():
		return {}
	var k := kind(id)
	var by := raider()
	var t := {"since": day, "until": day + int(c("threat_days", 3)), "by": by, "cid": ""}
	if r == null:
		r = Income.rng(day, "business_threat:" + id)
	var offer := ContractGen.generate(r, {"day": day, "source": "board", "zone_id": fob_zone(), "type": "defend_hold", "target": by,
		"employer": String(k.get("client", ""))})
	if not offer.is_empty():
		offer["business"] = id
		offer["title"] = "Protect the %s" % String(k.name).to_lower()
		offer["brief"] = "%s are moving on the FOB's %s. Hold them off and the business keeps running. %s" % [MissionRegistry.faction_name(by),
			String(k.name).to_lower(), String(offer.get("brief", ""))]
		t["cid"] = Contracts.server_add_offer(offer)
	b["threat"] = t
	Income.report("%s threatened" % String(k.name), "%s are moving on it. A protection job is on the board until day %d; leave it and the business gets raided." \
		% [MissionRegistry.faction_name(by), int(t.until)], "bad")
	return t


static func _raided(id: String, b: Dictionary, day: int) -> void:
	var k := kind(id)
	var cost := roundi(int(k.get("setup", 0)) * c("raid_cost_share", 0.3))
	b["threat"] = {}
	b["closed_until"] = day + int(c("raid_days", 4)) - 1
	Economy.add_cash(-cost, "%s: %s raided, repairs" % [LEDGER_COST, String(k.name)])
	Income.report("%s raided" % String(k.name), "Raiders hit it: closed until day %d and $%s to put right." % [int(b.closed_until) + 1, DebriefCalc.money(cost)], "bad",
		[["Repairs", -cost]])


## Host (Contracts.contract_closed): a protection job done lifts its business's threat; failed or
## lapsed, the raid comes at once. Only the job for the threat now standing counts.
static func on_contract_closed(contract: Dictionary, outcome: String) -> void:
	var id := String(contract.get("business", ""))
	var b: Dictionary = _mine().get(id, {})
	if id == "" or b.is_empty():
		return
	var t: Dictionary = b.get("threat", {})
	if t.is_empty() or String(t.get("cid", "")) != String(contract.get("cid", "")):
		return  # an old protection job: the raid it was for already came (or never did)
	if outcome == "completed":
		b["threat"] = {}
		Economy.change_locals(int(c("protect_rep", 2)))
		Income.report("%s safe" % String(kind(id).get("name", id)), "The raiders were beaten off; the business runs on and the locals noticed.", "good")
	else:
		_raided(id, b, Economy.day())
	Campaign.mark_changed(Income.SECTION)
