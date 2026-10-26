class_name Landmarks
extends RefCounted
## Named points per zone for Contractor: Fallen's map and wayfinding (docs/survival.md call 98):
## each zone's modules (the world sim's places: ZoneDef's modules) named by what they are ("the
## church", "the farm", "the checkpoint"), plus the tall things you steer by that every zone has a
## few of, placed by the world's seed: a water tower, a radio mast, a named hill. Two of a kind in a
## zone take their side of it ("the north church"). The map draws them at the zone zoom
## (FallenMap); companions' orders name them (nearest_name, meet_order: "Meet at the water
## tower"; resolve turns a name back into a point). Static, cached per zone and seed.

## What a module's base type is called on the map (ZoneModules.base, landmark kinds).
const KIND_NAMES := {"church": "church", "mosque": "mosque", "school": "school", "factory": "factory", "fuel_station": "fuel station",
	"farmhouse": "farmhouse", "barn": "barn", "farm": "farm", "compound": "compound", "outpost": "outpost", "checkpoint": "checkpoint",
	"town": "square", "village": "village", "hq": "headquarters", "qrf_base": "barracks", "office": "office block", "garage": "garage"}
## Proposed: the tall things a zone gets a few of (by seed), at most EXTRAS of them, kept within
## EXTRA_SPREAD of the zone's half size from its middle.
const TALL: Array[String] = ["water tower", "radio mast", "hill"]
const HILL_NAMES: Array[String] = ["Gallows", "Crow", "Beacon", "Lone Pine", "Signal", "Chapel", "Bald", "Shepherd's"]
const EXTRAS := 2
const EXTRA_SPREAD := 0.7

static var _cache := {}


## The named points of `zone_id`: [{"name", "kind", "pos": Vector2 (x, z)}].
static func of(zone_id: String) -> Array:
	var seed_v := int(Survival.state().get("seed", 0))
	var key := "%s|%d" % [zone_id, seed_v]
	if _cache.has(key):
		return _cache[key]
	var raw: Array = []
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone_id, {})
	var places: Array = zd.get("places", [])
	var size := float(zd.get("size_m", 1920.0))
	if places.is_empty():
		var def := MissionRegistry.zone_def(zone_id) if zone_id != "" else {}
		size = float(def.get("size_m", size))
		for m: Dictionary in def.get("modules", []):
			var p: Array = m.get("pos", [0.0, 0.0])
			places.append({"type": ZoneModules.base(String(m.get("type", ""))), "pos": [float(p[0]), float(p[1])]})
	for p: Dictionary in places:
		var noun := String(KIND_NAMES.get(String(p.get("type", "")), ""))
		if noun != "":
			raw.append({"noun": noun, "kind": String(p.type), "pos": Vector2(float(p.pos[0]), float(p.pos[1]))})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, zone_id, "landmarks"])
	var tall := TALL.duplicate()
	for i in EXTRAS:
		var kind: String = tall[rng.randi_range(0, tall.size() - 1)]
		tall.erase(kind)
		var half := size * 0.5 * EXTRA_SPREAD
		var at := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var noun := kind
		if kind == "hill":
			noun = "%s Hill" % HILL_NAMES[rng.randi_range(0, HILL_NAMES.size() - 1)]
		raw.append({"noun": noun, "kind": kind.replace(" ", "_"), "pos": at})
	var counts := {}
	for r: Dictionary in raw:
		counts[String(r.noun)] = int(counts.get(String(r.noun), 0)) + 1
	var out: Array = []
	var used := {}
	for r: Dictionary in raw:
		var noun := String(r.noun)
		var name := noun if noun.ends_with("Hill") else "the " + noun
		if int(counts[noun]) > 1:
			name = "the %s %s" % [side_of(r.pos as Vector2), noun]
		var n := 2
		var base := name
		while used.has(name):
			name = "%s %d" % [base, n]
			n += 1
		used[name] = true
		out.append({"name": name, "kind": String(r.kind), "pos": r.pos})
	_cache[key] = out
	return out


## A point's side of its zone's middle: north, south, east or west (north is -z).
static func side_of(p: Vector2) -> String:
	if absf(p.x) > absf(p.y):
		return "east" if p.x > 0.0 else "west"
	return "south" if p.y > 0.0 else "north"


static func _v2(pos: Variant) -> Vector2:
	if pos is Vector3:
		return Vector2((pos as Vector3).x, (pos as Vector3).z)
	if pos is Vector2:
		return pos
	return Vector2.ZERO


## The landmark of `zone_id` ("" the zone being played) nearest `pos` (Vector3 or Vector2 x, z).
static func nearest(pos: Variant, zone_id := "") -> Dictionary:
	var z := zone_id if zone_id != "" else SurvivalMap.current_zone()
	var at := _v2(pos)
	var best := {}
	var best_d := INF
	for l: Dictionary in of(z):
		var d := (l.pos as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = l
	return best


## The name of the landmark nearest `pos` ("" none).
static func nearest_name(pos: Variant, zone_id := "") -> String:
	return String(nearest(pos, zone_id).get("name", ""))


## A companion order naming the landmark nearest `pos`: "Meet at the water tower".
static func meet_order(pos: Variant, zone_id := "") -> String:
	var n := nearest_name(pos, zone_id)
	return "Meet at %s" % n if n != "" else ""


## The point (x, z) a landmark's name stands for in `zone_id` (an order's "the water tower"), or
## null. Matches without "the" and case.
static func resolve(name: String, zone_id := "") -> Variant:
	var z := zone_id if zone_id != "" else SurvivalMap.current_zone()
	var want := name.strip_edges().to_lower().trim_prefix("the ")
	for l: Dictionary in of(z):
		if String(l.name).to_lower().trim_prefix("the ") == want:
			return l.pos
	return null
