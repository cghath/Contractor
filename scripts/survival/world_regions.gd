class_name WorldRegions
extends RefCounted
## Contractor: Fallen's regions and places (docs/survival_world.md section 3, call 36): the
## campaign's zones grouped into geographic regions (data/survival_regions.json: plains, hills,
## desert, coast, the city), each zone with a type (its dead's base density, its tendencies) and
## its places (the zone layout's sites: ZoneDef's modules, by id). Regions are territories: the
## sum of which groups hold which places (WorldSim.holder_of, region_holders). Static and data
## only: the far tick (WorldModel) reads the zone table WorldSim builds once on the main thread.

const PATH := "res://data/survival_regions.json"
const REGION_IDS: Array[String] = ["plains", "hills", "desert", "coast", "city"]
## Proposed: what a place is worth defending in, by its site's base type (0-1), and its loot
## richness (a multiplier on the zone's loot).
const DEFENCE := {"compound": 0.6, "outpost": 0.5, "checkpoint": 0.4, "hq": 0.7, "qrf_base": 0.6, "village": 0.3,
	"town": 0.3, "farm": 0.25, "": 0.2}
const RICHNESS := {"compound": 1.2, "outpost": 1.0, "checkpoint": 0.8, "hq": 1.5, "qrf_base": 1.3, "village": 1.0,
	"town": 1.4, "farm": 0.9, "": 0.6}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {"regions": {}, "types": {}, "zones": {}}
	return _data


static func region_def(region_id: String) -> Dictionary:
	return (data().get("regions", {}) as Dictionary).get(region_id, {})


static func type_def(type_id: String) -> Dictionary:
	return (data().get("types", {}) as Dictionary).get(type_id, {})


## The campaign's zone ids (MissionRegistry), the base zone left out.
static func zone_ids() -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		out.append(String(z.zone_id))
	return out


## A zone's {"region", "type"}: the data's, else by its campaign region and the seed (coast stays
## coast; inland splits into plains and hills).
static func zone_info(zone_id: String, world_seed := 0) -> Dictionary:
	var z: Dictionary = (data().get("zones", {}) as Dictionary).get(zone_id, {})
	if not z.is_empty():
		return z
	var campaign_region := ""
	for raw: Dictionary in MissionRegistry.data().get("zones", []):
		if String(raw.zone_id) == zone_id:
			campaign_region = String(raw.get("region", ""))
	if campaign_region == "coast":
		return {"region": "coast", "type": "coast"}
	var hills := absi(hash([world_seed, zone_id, "region"])) % 3 == 0
	return {"region": "hills", "type": "hills"} if hills else {"region": "plains", "type": "village"}


## Host, main thread: the zone table the sim keeps in state()["world"]["zones"]: region, type,
## links (RegionMap), places (ZoneDef's modules: {"id", "type", "pos": [x, z], "defence",
## "richness", "looted", "holder"}), the dead's density (1 full of its type) and traces.
static func build_zone(zone_id: String, world_seed: int) -> Dictionary:
	var info := zone_info(zone_id, world_seed)
	var places: Array = []
	var def := MissionRegistry.zone_def(zone_id) if zone_id != "" else {}
	for m: Dictionary in def.get("modules", []):
		var base := ZoneModules.base(String(m.get("type", "")))
		var p: Array = m.get("pos", [0.0, 0.0])
		places.append({"id": String(m.get("id", "site%d" % places.size())), "type": base, "pos": [float(p[0]), float(p[1])],
			"defence": float(DEFENCE.get(base, DEFENCE[""])), "richness": float(RICHNESS.get(base, RICHNESS[""])),
			"looted": -100.0, "holder": ""})
	if places.is_empty():  # (a zone with no layout: one place in its middle)
		places.append({"id": "centre", "type": "", "pos": [0.0, 0.0], "defence": 0.2, "richness": 0.6, "looted": -100.0, "holder": ""})
	var links: Array = []
	for l: Dictionary in RegionMap.links(zone_id):
		links.append(String(l.to))
	return {"id": zone_id, "region": String(info.get("region", "plains")), "type": String(info.get("type", "village")),
		"name": RegionMap.zone_name(zone_id), "links": links, "places": places, "dead": 1.0, "traces": [], "horde": {},
		"size_m": float(def.get("size_m", 1920.0)), "held_by_player": false}


## The base dead density of a zone (its type's x its region's).
static func dead_base(zone: Dictionary) -> float:
	return float(type_def(String(zone.get("type", ""))).get("dead", 0.5)) * float(region_def(String(zone.get("region", ""))).get("dead", 0.6)) / 0.6


## The place `place_id` of `zone` ({} if none).
static func place(zone: Dictionary, place_id: String) -> Dictionary:
	for p: Dictionary in zone.get("places", []):
		if String(p.id) == place_id:
			return p
	return {}


## The shortest path of zone ids from `a` to `b` over `zones`' links ([] when unlinked; [a] when
## the same).
static func path(zones: Dictionary, a: String, b: String) -> Array:
	if a == b:
		return [a]
	var prev := {a: ""}
	var frontier: Array = [a]
	while not frontier.is_empty():
		var at := String(frontier.pop_front())
		for to: String in (zones.get(at, {}) as Dictionary).get("links", []):
			if prev.has(to):
				continue
			prev[to] = at
			if to == b:
				var out: Array = [b]
				var c := at
				while c != "":
					out.push_front(c)
					c = String(prev[c])
				return out
			frontier.append(to)
	return []


## Links apart (-1 unlinked).
static func distance(zones: Dictionary, a: String, b: String) -> int:
	var p := path(zones, a, b)
	return p.size() - 1 if not p.is_empty() else -1
