class_name MissionRegistry
extends RefCounted
## The mission types contracts are made from, the zones and modules they play in, and the
## contract settings, read from res://data/contracts.json (wave 4, W10). The four types there
## (clear a compound, recover an HVT, retrieve intel, destroy a cache) are placeholders until
## Noah's mission pack and the mission brainstorm doc land: swap the data, or add types at
## runtime with register_type, and the generator, objectives and debrief use them as they are.
##
## A mission type ("type") names:
## - "module": the hand-built area it needs (a zone lists the modules it holds);
## - "objectives": templates, each {"kind" (an Objectives kind), "site" (a named site of the
##   module, which gives positions, items, the HVT or the cache), "text", "optional",
##   "bonus_share" (share of the pay an optional one adds)};
## - "base_pay", "days" (campaign days it takes);
## - the drivers of its difficulty: "enemy_count" and "enemy_quality" ranges and the
##   "threat_pool" it may bring (ids in "threats", each with a rating weight).
##
## Factions (ids, names, start reputation, reputation tiers) come from res://data/factions.json.

const PATH := "res://data/contracts.json"
const FACTIONS_PATH := "res://data/factions.json"

static var _data: Dictionary = {}
static var _factions: Dictionary = {}
static var _extra_types: Array = []  # register_type


## The whole contracts file (loaded once).
static func data() -> Dictionary:
	if _data.is_empty():
		_data = _load(PATH)
	return _data


## Forget the loaded files (tests that change them; types added with register_type stay).
static func reload() -> void:
	_data = {}
	_factions = {}


## Adds a mission type at runtime (same shape as the file's); one with the same "type" id
## replaces it.
static func register_type(def: Dictionary) -> void:
	_extra_types = _extra_types.filter(func(t: Dictionary) -> bool: return t.get("type") != def.get("type"))
	_extra_types.append(def.duplicate(true))


static func unregister_type(type_id: String) -> void:
	_extra_types = _extra_types.filter(func(t: Dictionary) -> bool: return t.get("type") != type_id)


## Every mission type definition, the file's first.
static func type_defs() -> Array:
	var out: Array = []
	var ids := {}
	for t: Dictionary in _extra_types:
		ids[t["type"]] = true
	for t: Dictionary in data().get("mission_types", []):
		if not ids.has(t["type"]):
			out.append(t)
	out.append_array(_extra_types)
	return out


static func types() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in type_defs():
		out.append(String(t["type"]))
	return out


static func type_def(type_id: String) -> Dictionary:
	for t: Dictionary in type_defs():
		if t["type"] == type_id:
			return t
	return {}


## A value from "settings" (Proposed numbers), or `default` if it isn't there.
static func setting(key: String, default: Variant = null) -> Variant:
	return (data().get("settings", {}) as Dictionary).get(key, default)


static func setting_f(key: String, default := 0.0) -> float:
	return float(setting(key, default))


static func setting_i(key: String, default := 0) -> int:
	return int(setting(key, default))


static func module(module_id: String) -> Dictionary:
	return (data().get("modules", {}) as Dictionary).get(module_id, {})


## A named site in a module: {"rect": [x, z, w, d]} (metres), {"pos": [x, y, z]},
## {"box": [[x, y, z], [x, y, z]]}, plus "items"/"tags" (intel), "hvt" or "cache" ids.
static func site(module_id: String, site_id: String) -> Dictionary:
	return (module(module_id).get("sites", {}) as Dictionary).get(site_id, {})


static func zones() -> Array:
	return data().get("zones", [])


static func zone(zone_id: String) -> Dictionary:
	for z: Dictionary in zones():
		if z.zone_id == zone_id:
			return z
	return {}


## Zones of `kind` ("contract" or "hot") that hold `module_id`.
static func zones_for(module_id: String, kind: String) -> Array:
	return zones().filter(func(z: Dictionary) -> bool: return z.get("kind") == kind and module_id in z.get("modules", []))


static func region(region_id: String) -> Dictionary:
	for r: Dictionary in data().get("regions", []):
		if r.region == region_id:
			return r
	return {}


static func fixers() -> Array:
	return data().get("fixers", [])


static func threat(threat_id: String) -> Dictionary:
	return (data().get("threats", {}) as Dictionary).get(threat_id, {"name": threat_id, "weight": 0.5})


static func threat_name(threat_id: String) -> String:
	return String(threat(threat_id).get("name", threat_id))


## Whether an item is intel (opens leads, can be sold): tagged "intel" in items.json, or
## listed in the contracts file's "intel_items".
static func is_intel(item_id: StringName) -> bool:
	if String(item_id) in data().get("intel_items", []):
		return true
	var item: ItemData = ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	return item != null and "intel" in item.tags


# --- Factions ----------------------------------------------------------------------------

static func factions() -> Array:
	if _factions.is_empty():
		_factions = _load(FACTIONS_PATH)
	return _factions.get("factions", [])


static func faction(faction_id: String) -> Dictionary:
	for f: Dictionary in factions():
		if f.id == faction_id:
			return f
	return {}


static func faction_ids() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in factions():
		out.append(String(f.id))
	return out


static func faction_name(faction_id: String) -> String:
	return String(faction(faction_id).get("name", faction_id))


## Factions that hire (every faction that isn't "hostile").
static func employers() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in factions():
		if f.get("role") != "hostile":
			out.append(String(f.id))
	return out


## Factions the squad is hired against.
static func enemies() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in factions():
		if f.get("role") == "hostile":
			out.append(String(f.id))
	return out


## The reputation tiers, lowest first: [{"id", "min"}]. Numbers only; what a tier unlocks
## is wave 6's call.
static func reputation_tiers() -> Array:
	if _factions.is_empty():
		factions()
	var tiers: Array = (_factions.get("reputation_tiers", []) as Array).duplicate()
	tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.min) < float(b.min))
	return tiers


## The tier a reputation value is in, as a number (0 = the lowest tier).
static func tier_index(rep: int) -> int:
	var index := 0
	var tiers := reputation_tiers()
	for i in tiers.size():
		if rep >= int(tiers[i].min):
			index = i
	return index


static func tier_id(rep: int) -> String:
	var tiers := reputation_tiers()
	return String(tiers[tier_index(rep)].id) if not tiers.is_empty() else ""


## The tier index of "neutral" (the tier a fresh faction stands in).
static func neutral_tier() -> int:
	var tiers := reputation_tiers()
	for i in tiers.size():
		if tiers[i].id == "neutral":
			return i
	return 0


static func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MissionRegistry: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MissionRegistry: %s is not valid JSON" % path)
		return {}
	return parsed
