class_name Theatre
extends RefCounted
## What the world map shows about each zone (WorldMapView; Captain, 2026-10-20), gathered from
## the state that already exists, on any peer: who controls it (ZoneControl), the conflicts
## there (hot zones, the faction war's flashpoints and weak grips, a skirmish going on now, the
## enemy's alert and pressure while the squad is in one, contracts held and offered, fights of
## the last RECENT_DAYS), the locals' support in its region (RebelSupport), and where the squad
## and home are. Read-only: nothing here changes the campaign.

## Closed contracts this many days old or newer count as recent fights.
const RECENT_DAYS := 7
## A contract's difficulty (stars) in words, for a zone's threat.
const THREAT_WORDS: Array[String] = ["Light", "Low", "Moderate", "High", "Severe", "Extreme"]
## On-foot travel along one link (docs/linked_zones.md: 2 h a link on foot).
const LINK_HOURS := 2


## One zone's row: {"id", "name", "region", "region_name", "kind" ("base", "contract", "hot"),
## "controller", "controller_name", "side" (ZoneControl.SIDES), "contested", "flashpoint",
## "grip" (-1 if none), "held" [titles], "offered" [titles], "skirmish" (text, "" for none),
## "alert" (Alert.STATE_NAMES, "" if unknown), "pressure" (tier, -1 if unknown), "recent"
## [{"title", "outcome", "day"}], "support" (0-100), "rebel_tier", "threat", "squad", "home"}.
## `ctx` (zones() makes it once for every zone): {"held", "board", "history"}, else read here.
static func zone(zone_id: String, from: Node = null, ctx := {}) -> Dictionary:
	if ctx.is_empty():
		ctx = _context()
	var z := ZoneControl._zone(zone_id)
	var region := String(z.get("region", RegionMap.BASE_REGION if zone_id == RegionMap.BASE else ""))
	var kind := "base" if zone_id == RegionMap.BASE else String(z.get("kind", "contract"))
	var ctrl := ZoneControl.controller(zone_id)
	var site := ZoneControl._site(zone_id)
	var held: Array[String] = []
	var offered: Array[String] = []
	var stars := 0
	for c: Dictionary in ctx.held:
		if _in_zone(c, zone_id):
			held.append(String(c.get("title", "Contract")))
			stars = maxi(stars, int(c.get("rated", 0)))
	for c: Dictionary in ctx.board:
		if _in_zone(c, zone_id):
			offered.append(String(c.get("title", "Contract")))
			stars = maxi(stars, int(c.get("rated", 0)))
	var here := squad_zone(from) == zone_id
	var alert := ""
	var pressure := -1
	var skirmish := ""
	if here and from != null:
		var a := Alert.of(from)
		if a:
			alert = Alert.STATE_NAMES[clampi(int(a.zone_state), 0, Alert.STATE_NAMES.size() - 1)]
		var p := Pressure.of(from)
		if p:
			pressure = p.tier()
		var fs := FactionSkirmish.of(from)
		if fs and fs._alive() > 0 and not fs.last.is_empty():
			skirmish = "%s hitting %s" % [MissionRegistry.faction_name(String(fs.last.get("faction", ""))),
				MissionRegistry.faction_name(String(fs.last.get("against", "")))]
	var threat := ""
	if kind == "base":
		threat = "None: the company's base"
	elif kind == "hot":
		threat = "High: a hot zone" + (", pressure tier %d" % pressure if pressure > 0 else "")
	elif stars > 0:
		threat = "%s (contract %d star%s)" % [THREAT_WORDS[clampi(stars, 0, THREAT_WORDS.size() - 1)], stars, "" if stars == 1 else "s"]
	else:
		threat = "Unknown: no contract there"
	return {"id": zone_id, "name": RegionMap.zone_name(zone_id), "region": region, "region_name": region_name(region), "kind": kind,
		"controller": ctrl, "controller_name": ZoneControl.controller_name(ctrl), "side": ZoneControl.side(zone_id),
		"contested": ZoneControl.is_contested(zone_id), "flashpoint": bool(site.get("flashpoint", false)),
		"grip": float(site.get("grip", -1.0)), "held": held, "offered": offered, "skirmish": skirmish, "alert": alert,
		"pressure": pressure, "recent": recent_fights(zone_id, ctx.history), "support": RebelSupport.support(region) if region != "" else 0.0,
		"rebel_tier": RebelSupport.tier(region) if region != "" else 0, "threat": threat, "squad": here,
		"home": zone_id == RegionMap.BASE and ZoneControl.home() == ZoneControl.HOME_FOB}


## Every zone on the region map (RegionMap.layout), by id.
static func zones(from: Node = null) -> Dictionary:
	var out := {}
	var ctx := _context()
	for id: String in RegionMap.layout():
		out[id] = zone(id, from, ctx)
	return out


static func _context() -> Dictionary:
	return {"held": Contracts.held(), "board": Contracts.board(), "history": Contracts.history()}


## Whether contract `c` is in `zone_id` (its own zone or one of its legs, LZ-7).
static func _in_zone(c: Dictionary, zone_id: String) -> bool:
	if String(c.get("zone_id", "")) == zone_id:
		return true
	for leg: Dictionary in c.get("legs", []):
		if String(leg.get("zone_id", "")) == zone_id:
			return true
	return false


## Contracts closed in `zone_id` in the last RECENT_DAYS: [{"title", "outcome", "day"}], newest
## first (history entries from before they carried a zone are left out).
static func recent_fights(zone_id: String, history: Variant = null) -> Array:
	var out: Array = []
	var today := Economy.day()
	for h: Dictionary in (history if history is Array else Contracts.history()):
		if String(h.get("zone_id", "")) == zone_id and today - int(h.get("day", 0)) <= RECENT_DAYS:
			out.push_front({"title": String(h.get("title", "")), "outcome": String(h.get("outcome", "")), "day": int(h.get("day", 0))})
	return out


## Where the squad is: the deployment's zone, else the zone the game is in (when it's on the
## map), else home.
static func squad_zone(_from: Node = null) -> String:
	var dep := Contracts.deployment()
	if not dep.is_empty() and RegionMap.layout().has(String(dep.get("zone_id", ""))):
		return String(dep.zone_id)
	if RegionMap.layout().has(GameState.zone_id):
		return GameState.zone_id
	return RegionMap.BASE


static func region_name(region: String) -> String:
	return String(MissionRegistry.region(region).get("name", region.capitalize()))


## Days to get to `region` from home (data/contracts.json regions' "travel_days").
static func travel_days(region: String) -> int:
	return int(MissionRegistry.region(region).get("travel_days", 0))


## The tooltip text for a zone row (WorldMapView, and the info panel).
static func describe(row: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("%s  (%s, %s)" % [row.name, row.region_name, {"base": "base", "hot": "hot zone", "contract": "contract zone"}.get(row.kind, row.kind)])
	var held_by := String(row.controller_name)
	if bool(row.contested):
		held_by += ": CONTESTED" + (" (a faction just took it)" if bool(row.flashpoint) else "")
	if float(row.grip) >= 0.0:
		held_by += ", grip %d%%" % roundi(float(row.grip) * 100.0)
	lines.append("Controlled by: " + held_by)
	lines.append("Threat: " + String(row.threat))
	if String(row.alert) != "":
		lines.append("Enemy alert: " + String(row.alert))
	if String(row.skirmish) != "":
		lines.append("Skirmish now: " + String(row.skirmish))
	var held: Array = row.held
	var offered: Array = row.offered
	lines.append("Contracts: %s" % ("none" if held.is_empty() and offered.is_empty() else
		", ".join(PackedStringArray(held.map(func(t: String) -> String: return t + " (held)") + offered.map(func(t: String) -> String: return t + " (offered)")))))
	for f: Dictionary in row.recent:
		lines.append("Fought here day %d: %s (%s)" % [int(f.day), String(f.title), String(f.outcome)])
	if String(row.region) != "":
		lines.append("Rebel support (%s): %d/100, tier %d of %d" % [row.region_name, roundi(float(row.support)), int(row.rebel_tier), RebelSupport.TIERS.size()])
	if bool(row.squad):
		lines.append("The squad is here")
	if bool(row.home):
		lines.append("Home")
	return "\n".join(lines)
