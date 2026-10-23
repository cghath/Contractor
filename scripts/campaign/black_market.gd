class_name BlackMarket
extends RefCounted
## Black market trading (Income 4; docs/income.md 4): buy low and sell high between the regions'
## markets and the fixers: fuel, weapons, medical supplies, contraband. Prices move with the living
## war (fronts and enemy-held ground make weapons, medical and fuel scarce; the cartels' ground
## floods contraband; lawful forces' presence makes it dear) and with the company's own trade
## (selling a lot of one thing in one market drives its price down; it recovers day by day). So it
## pays to trade where the war is, not to grind one route.
##
## Where the company can trade: its home region's market, the market of the region its last job was
## in (until the next job), and the fixers who'll deal with it (Mama Rook, Halloran: anywhere). The
## company's cargo rides in its trucks: 20 units plus 10 for each vehicle in the motor pool.
##
## The risk: every day contraband held may be found (more of it, more lawful forces about: the
## US's war footing), seized with a fine and the lawful factions' standing; weapons held may cost
## lawful standing if found; and cargo at a FOB in dangerous ground can be stolen.
##
## Section "income": "cargo" {good: {"units", "paid"}}, "pressure" {market: {good: n}},
## "market_region" (the last job's region). Numbers in data/income.json "market", Proposed.

const LEDGER_BUY := "Trade bought"
const LEDGER_SELL := "Trade sold"


static func cfg() -> Dictionary:
	return Income.data().get("market", {})


static func c(key: String, default := 0.0) -> float:
	return float(cfg().get(key, default))


static func goods() -> Dictionary:
	return cfg().get("goods", {})


static func good_name(g: String) -> String:
	return String((goods().get(g, {}) as Dictionary).get("name", g.capitalize()))


static func _s() -> Dictionary:
	var s := Income.state()
	for key: String in ["cargo", "pressure"]:
		if not s.has(key):
			s[key] = {}
	return s


static func cargo(s: Dictionary = {}) -> Dictionary:
	var st := s if not s.is_empty() else Income.view()
	return st.get("cargo", {})


static func cargo_units(s: Dictionary = {}) -> int:
	var n := 0
	var cg := cargo(s)
	for g: String in cg:
		n += int(cg[g].get("units", 0))
	return n


static func capacity() -> int:
	return int(c("capacity_base", 20)) + int(c("capacity_per_vehicle", 10)) * MotorPool.list().size()


# --- Markets ------------------------------------------------------------------------------

## The markets open to the company now: [{"id", "name", "region" or "fixer"}]. Region markets are
## "r:<region>", fixers "f:<faction>".
static func markets(s: Dictionary = {}) -> Array:
	var st := s if not s.is_empty() else Income.view()
	var out: Array = []
	var home := RebelSupport.region_of(ZoneControl.fob_zone() if not ZoneControl.home_is_lhd() and ZoneControl.fob_zone() != "" else RegionMap.BASE)
	if ZoneControl.home_is_lhd():
		home = "coast"
	var regions: Array = [home]
	var here := String(st.get("market_region", ""))
	if here != "" and not here in regions:
		regions.append(here)
	for r: Dictionary in MissionRegistry.data().get("regions", []):
		if String(r.region) in regions:
			out.append({"id": "r:" + String(r.region), "name": "%s market" % String(r.name), "region": String(r.region)})
	for fx: Dictionary in MissionRegistry.fixers():
		var f := String(fx.get("faction", ""))
		if (cfg().get("fixers", {}) as Dictionary).has(f) and Economy.reputation(f) >= int(fx.get("min_rep", 0)):
			out.append({"id": "f:" + f, "name": String(fx.fixer), "fixer": f})
	return out


## The scarcity of good `g` in `region` from the war, as a price factor around 1.
static func war_factor(g: String, region: String) -> float:
	var gd: Dictionary = goods().get(g, {})
	var zones: Array = []
	for z: String in WorldSites.war_zones():
		if RebelSupport.region_of(z) == region:
			zones.append(z)
	if zones.is_empty():
		return 1.0
	var fronts := 0
	var hostile := 0
	var cartel := 0
	var lawful := 0
	for z: String in zones:
		if not WorldSites.front(z).is_empty():
			fronts += 1
		var h := WorldSites.holder_now(z)
		if h in MissionRegistry.enemies():
			hostile += 1
		if bool(MissionRegistry.faction(h).get("predatory", false)) or h == "kestrel":
			cartel += 1
		if bool(MissionRegistry.faction(h).get("lawful", false)) or h == ZoneControl.PLAYER:
			lawful += 1
	var n := float(zones.size())
	var f := 1.0 + float(gd.get("front", 0.0)) * fronts / n + float(gd.get("hostile", 0.0)) * hostile / n \
		+ float(gd.get("cartel", 0.0)) * cartel / n + float(gd.get("lawful", 0.0)) * lawful / n
	return clampf(f, 0.5, 2.0)


## Today's mid price of `g` at market `mid`: base x the war's factor (a region's, or the fixer's
## own lean) x the day's noise x the company's own selling pressure there.
static func mid_price(g: String, mid: String, s: Dictionary = {}) -> int:
	var st := s if not s.is_empty() else Income.view()
	var base := float((goods().get(g, {}) as Dictionary).get("price", 0))
	var f := 1.0
	if mid.begins_with("r:"):
		f = war_factor(g, mid.trim_prefix("r:"))
	else:
		var lean: Dictionary = (cfg().get("fixers", {}) as Dictionary).get(mid.trim_prefix("f:"), {})
		f = float(lean.get(g, 1.0))
	var r := Income.rng(Economy.day(), "market:%s:%s" % [mid, g])
	f *= 1.0 + r.randf_range(-c("noise", 0.08), c("noise", 0.08))
	var press := float(((st.get("pressure", {}) as Dictionary).get(mid, {}) as Dictionary).get(g, 0.0))
	f *= maxf(1.0 - press, 0.4)
	return maxi(roundi(base * f), 1)


## What the market sells one unit for ("buy") and pays for one ("sell"); 0 when it doesn't deal in it.
static func price(g: String, mid: String, side: String, s: Dictionary = {}) -> int:
	if mid.begins_with("f:"):
		var lean: Dictionary = (cfg().get("fixers", {}) as Dictionary).get(mid.trim_prefix("f:"), {})
		if not lean.has(g):
			return 0
	var p := float(mid_price(g, mid, s))
	var half := c("spread", 0.16) / 2.0
	return roundi(p * (1.0 + half)) if side == "buy" else roundi(p * (1.0 - half))


static func _market(mid: String) -> Dictionary:
	for m: Dictionary in markets():
		if String(m.id) == mid:
			return m
	return {}


# --- Host: trading ------------------------------------------------------------------------

## Host: buys `units` of `g` at market `mid`. Returns "" or why not.
static func server_buy(g: String, mid: String, units: int) -> String:
	if _market(mid).is_empty():
		return "That market isn't open to the company"
	if not goods().has(g) or units <= 0:
		return "Bad request"
	var each := price(g, mid, "buy")
	if each <= 0:
		return "They don't sell %s" % good_name(g).to_lower()
	if cargo_units(_s()) + units > capacity():
		return "The trucks hold %d units; %d are loaded" % [capacity(), cargo_units(_s())]
	var cost := each * units
	if not Economy.spend(cost, "%s: %d %s at %s" % [LEDGER_BUY, units, good_name(g).to_lower(), String(_market(mid).name)]):
		return "Not enough cash ($%s)" % DebriefCalc.money(cost)
	var cg: Dictionary = _s().cargo
	var e: Dictionary = cg.get(g, {"units": 0, "paid": 0})
	e["units"] = int(e.units) + units
	e["paid"] = int(e.paid) + cost
	cg[g] = e
	_pressure(mid, g, -units * c("pressure_per_unit", 0.012) * 0.5)  # buying lifts the price a little
	return ""


## Host: sells `units` of `g` at market `mid`. Returns "" or why not.
static func server_sell(g: String, mid: String, units: int) -> String:
	if _market(mid).is_empty():
		return "That market isn't open to the company"
	var cg: Dictionary = _s().cargo
	var e: Dictionary = cg.get(g, {})
	if e.is_empty() or units <= 0 or int(e.units) < units:
		return "Not that much %s aboard" % good_name(g).to_lower()
	var each := price(g, mid, "sell")
	if each <= 0:
		return "They don't buy %s" % good_name(g).to_lower()
	var got := each * units
	var basis := roundi(float(e.paid) * units / maxf(float(e.units), 1.0))
	e["paid"] = int(e.paid) - basis
	e["units"] = int(e.units) - units
	if int(e.units) <= 0:
		cg.erase(g)
	Economy.add_cash(got, "%s: %d %s at %s" % [LEDGER_SELL, units, good_name(g).to_lower(), String(_market(mid).name)])
	_pressure(mid, g, units * c("pressure_per_unit", 0.012))
	if g == "contraband" and mid.begins_with("f:"):
		Economy.change_reputation(mid.trim_prefix("f:"), 1, "contraband traded", false)
	Contracts._notify_all("Sold %d %s at %s for $%s (%s$%s on what it cost)" % [units, good_name(g).to_lower(), String(_market(mid).name),
		DebriefCalc.money(got), "+" if got >= basis else "-", DebriefCalc.money(absi(got - basis))])
	return ""


static func _pressure(mid: String, g: String, delta: float) -> void:
	var p: Dictionary = _s().pressure
	if not p.has(mid):
		p[mid] = {}
	p[mid][g] = clampf(float((p[mid] as Dictionary).get(g, 0.0)) + delta, -0.3, 0.6)


## Host: a day passed: the company's selling pressure eases, and the cargo's risks are rolled.
static func server_day(days: int) -> void:
	var s := _s()
	var p: Dictionary = s.pressure
	for mid: String in p:
		for g: String in p[mid]:
			p[mid][g] = snappedf(float(p[mid][g]) * pow(1.0 - c("pressure_decay", 0.25), days), 0.001)
	if cargo_units(s) <= 0:
		return
	for i in days:
		_risks(Economy.day() - days + 1 + i)


## The cargo's risks today: contraband found (seized, fined, lawful standing down), weapons found
## (lawful standing down), theft at a FOB in dangerous ground.
static func _risks(day: int) -> void:
	var cg: Dictionary = _s().cargo
	var r := Income.rng(day, "market_risk")
	var lawful := 1.0 + (WorldSites.strength("us_forces") / 100.0 if WorldSites.is_belligerent("us_forces") else 0.0)
	var contra := int((cg.get("contraband", {}) as Dictionary).get("units", 0))
	if contra > 0 and r.randf() < clampf(c("contraband_risk", 0.03) * (1.0 + contra / 10.0) * lawful, 0.0, 0.6):
		var worth := int(cg.contraband.paid)
		cg.erase("contraband")
		var fine := roundi(worth * c("fine_share", 0.5))
		Economy.add_cash(-fine, "%s: fined for contraband" % LEDGER_BUY)
		for fid: String in MissionRegistry.faction_ids():
			if bool(MissionRegistry.faction(fid).get("lawful", false)):
				Economy.change_reputation(fid, int(c("contraband_rep", -3)) if fid == "us_forces" else -1, "contraband found", false)
		Income.report("Contraband seized", "An inspection found %d units of contraband: seized, and a $%s fine. US Forces won't forget it." % [contra, DebriefCalc.money(fine)], "bad",
			[["Fine", -fine]])
		return
	var guns := int((cg.get("weapons", {}) as Dictionary).get("units", 0))
	if guns > 0 and r.randf() < clampf(c("weapons_risk", 0.015) * (1.0 + guns / 10.0) * lawful, 0.0, 0.4):
		Economy.change_reputation("us_forces", -1, "unregistered weapons found", false)
		Income.report("Weapons noticed", "A patrol saw the company's crates of weapons. US Forces think a little less of it.", "neutral")
	if not ZoneControl.home_is_lhd() and r.randf() < c("theft_risk", 0.02) * FobBusiness.fob_danger() * 2.0:
		var goods_held: Array = cg.keys()
		goods_held.sort()
		var g := String(goods_held[r.randi() % goods_held.size()])
		var e: Dictionary = cg[g]
		var lost := maxi(roundi(int(e.units) * 0.4), 1)
		var basis := roundi(float(e.paid) * lost / maxf(float(e.units), 1.0))
		e["units"] = int(e.units) - lost
		e["paid"] = int(e.paid) - basis
		if int(e.units) <= 0:
			cg.erase(g)
		Income.report("Cargo stolen", "Thieves got into the FOB's stores: %d units of %s gone." % [lost, good_name(g).to_lower()], "bad")


## Host (Contracts.contract_closed): the region the last job was in opens its market until the next.
static func on_contract_closed(contract: Dictionary, _outcome: String) -> void:
	var region := RebelSupport.region_of(String(contract.get("zone_id", "")))
	if region != "":
		_s()["market_region"] = region
		Campaign.mark_changed(Income.SECTION)
