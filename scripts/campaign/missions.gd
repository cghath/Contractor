class_name MissionRegistry
extends RefCounted
## The mission types contracts are made from, the zones and modules they play in, and the
## contract settings, read from res://data/contracts.json (wave 4, W10). The four types there
## (clear a compound, recover an HVT, retrieve intel, destroy a cache) are placeholders until
## Noah's mission pack and the mission brainstorm doc land: swap the data, or add types at
## runtime with register_type, and the generator, objectives and debrief use them as they are.
##
## A mission type ("type") names:
## - "modules": the module types it can play in (a zone's generated layout holds them; a
##   contract picks one of the zone's modules of those types as its target);
## - "objectives": templates, each {"kind" (an Objectives kind), "site" (a named site of the
##   module, or a list to pick from, which gives positions, items, the HVT or the cache),
##   "text" ({name}: the site's or person's name, {module}: the module's), "optional",
##   "bonus_share" (share of the pay an optional one adds)};
## - "time_limit_min" (optional): the required objectives fail when it runs out;
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
static var _zones: Array = []  # zones(), with their layouts' module types filled in
static var _zone_defs := {}  # zone id -> ZoneDef


## The whole contracts file (loaded once).
static func data() -> Dictionary:
	if _data.is_empty():
		_data = _load(PATH)
	return _data


## Forget the loaded files (tests that change them; types added with register_type stay).
static func reload() -> void:
	_data = {}
	_factions = {}
	_zones = []
	_zone_defs = {}


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


## A module type's entry ("name", "sites", "civilians").
static func module(module_type: String) -> Dictionary:
	var entry: Dictionary = (data().get("modules", {}) as Dictionary).get(ZoneModules.base(module_type), {})
	if module_type.begins_with(ZoneModules.TOWN) or module_type.begins_with(ZoneModules.CITY):  # a generated town (or a city block): its own civilians and sites (a grown module keeps its base type's)
		entry = entry.duplicate()
		entry["name"] = entry.get("name", "town")
		entry["civilians"] = ZoneModules.civilians(module_type)
		entry["sites"] = ZoneModules.town_sites(module_type)
	return entry


## A module type's name in words ("outpost").
static func module_name(module_type: String) -> String:
	return String(module(module_type).get("name", module_type))


## A named site in a module type: {"rect": [x, z, w, d]} (metres), {"pos": [x, y, z]},
## {"box": [[x, y, z], [x, y, z]]}, plus "items"/"tags" (intel), "place", "hvt" and "person",
## "of_hvt", "cache" ids, "name". A cache whose "voxels" is "auto" gets its count from the
## module's pristine boxes (ZoneModules.solid_voxels_in). A copy.
static func site(module_type: String, site_id: String) -> Dictionary:
	var s: Dictionary = ((module(module_type).get("sites", {}) as Dictionary).get(site_id, {}) as Dictionary).duplicate(true)
	if s.has("box") and typeof(s.get("voxels")) == TYPE_STRING:
		var a: Array = s.box[0]
		var b: Array = s.box[1]
		var lo := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var hi := Vector3(float(b[0]), float(b[1]), float(b[2]))
		s.voxels = ZoneModules.solid_voxels_in(module_type, AABB(lo.min(hi), (hi - lo).abs())) if ZoneModules.has_type(module_type) else 0
	return s


static func has_site(module_type: String, site_id: String) -> bool:
	return (module(module_type).get("sites", {}) as Dictionary).has(site_id)


## The module types a mission type can play in ("modules", or an older single "module").
static func type_modules(def: Dictionary) -> Array:
	if def.has("modules"):
		return def.modules
	return [def.module] if def.has("module") else []


## Every zone, with "modules" (the module types its layout holds) filled in from its layout.
static func zones() -> Array:
	if _zones.is_empty():
		for z: Dictionary in data().get("zones", []):
			var entry := z.duplicate(true)
			var def := zone_def(String(z.zone_id))
			if not def.is_empty():
				var types: Array = []
				for m: Dictionary in def.modules:
					if not ZoneModules.base(String(m.type)) in types:  # a town ("town#<seed>") as "town"
						types.append(ZoneModules.base(String(m.type)))
				entry["modules"] = types
			_zones.append(entry)
	return _zones


## The layout (ZoneDef) of a zone: its "def" ({"seed", "size_m", "types", "count"}: made by
## ZoneDef.generate, the same every time; with "layout": "hot", ZoneDef.generate_hot's
## structure of HQ, outposts, QRF bases and the rest; or a data/zones.json id), {} if it has none.
static func zone_def(zone_id: String) -> Dictionary:
	if _zone_defs.has(zone_id):
		return _zone_defs[zone_id]
	var raw: Dictionary = {}
	for z: Dictionary in data().get("zones", []):
		if z.zone_id == zone_id:
			raw = z
	var spec: Variant = raw.get("def", null)
	var def := {}
	if spec is String:
		def = ZoneDef.get_def(spec)
	elif spec is Dictionary and String(spec.get("layout", "")) == "hot":
		def = ZoneDef.generate_hot(int(spec.get("seed", hash(zone_id))), float(spec.get("size_m", ZoneDef.HOT_SIZE_M)), bool(spec.get("urban", false)))
	elif spec is Dictionary:
		def = ZoneDef.generate(int(spec.get("seed", hash(zone_id))), float(spec.get("size_m", 1920.0)),
			spec.get("types", ["compound", "outpost", "village", "checkpoint"]), int(spec.get("count", 5)))
	if not def.is_empty():
		def["id"] = zone_id
		def["name"] = String(raw.get("name", zone_id))
		def["region"] = String(raw.get("region", ""))
		for key: String in ["hour", "weather"]:  # the zone's time of day and weather (DayNight, wave 7 S1)
			if raw.has(key):
				def[key] = raw[key]
		def["assets"] = raw.get("assets", [])  # its landmarks go by these (ZoneModules.place_landmarks, queue item 1.4)
		def["controller"] = String(raw.get("controller", ""))
		if not spec is String:
			def.erase("terrain")  # generate() already chose one before it knew the name and region
			var named: Variant = raw.get("terrain", spec.get("terrain", "") if spec is Dictionary else "")
			if String(named) != "":
				def["terrain"] = String(named)
		def = ZoneDef.normalize(def)  # the terrain preset follows the name and region
		def["crossings"] = RegionMap.crossings(zone_id, def)  # its edges into the neighbouring zones (LZ-2)
	_zone_defs[zone_id] = def
	return def


static func zone(zone_id: String) -> Dictionary:
	for z: Dictionary in zones():
		if z.zone_id == zone_id:
			return z
	return {}


## Zones of `kind` ("contract" or "hot") that hold any of `module_types` (one type or a list).
static func zones_for(module_types: Variant, kind: String) -> Array:
	var wanted: Array = module_types if module_types is Array else [module_types]
	return zones().filter(func(z: Dictionary) -> bool:
		return z.get("kind") == kind and wanted.any(func(t: Variant) -> bool: return t in z.get("modules", [])))


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


## Faction ids that were renamed, old -> new (wave 6b, 2026-10-18: the "federal_army"
## placeholder became the Eastern Concord Forces). faction() still answers for an old id, and
## migrate_faction_keys() carries a save's per-faction entries over.
const RENAMED_FACTIONS := {"federal_army": "eastern_concord"}


static func faction(faction_id: String) -> Dictionary:
	faction_id = String(RENAMED_FACTIONS.get(faction_id, faction_id))
	for f: Dictionary in factions():
		if f.id == faction_id:
			return f
	return {}


## Renames old faction ids (RENAMED_FACTIONS) in a campaign section, in place: keys of every
## dictionary it holds (Economy's "rep", "heat", ...) and "faction"/"holder" values of the
## dictionaries it holds or lists (WorldSites' sites, Economy's nemeses). True when anything
## moved. Campaign.load_campaign runs it over every section once, as a save loads.
static func migrate_faction_keys(section: Dictionary) -> bool:
	var moved := false
	for v: Variant in section.values():
		var entries: Array = (v as Array) if v is Array else [v]
		for e: Variant in entries:
			if not e is Dictionary:
				continue
			var d: Dictionary = e
			for old: String in RENAMED_FACTIONS:
				var now: String = RENAMED_FACTIONS[old]
				if d.has(old):
					if not d.has(now):
						d[now] = d[old]
					d.erase(old)
					moved = true
				for field: String in ["faction", "holder"]:
					if d.get(field) is String and d[field] == old:
						d[field] = now
						moved = true
	return moved


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


## The tier entry ({"id", "name", "min", "pay_mult", ...}) a reputation value is in; {} without tiers.
static func tier_of(rep: int) -> Dictionary:
	var tiers := reputation_tiers()
	return tiers[tier_index(rep)] if not tiers.is_empty() else {}


## The reputation rules (factions.json "reputation_rules", wave 6a): ripple, decay, lockout.
static func reputation_rules() -> Dictionary:
	if _factions.is_empty():
		factions()
	return _factions.get("reputation_rules", {})


## The factions `faction_id` counts as allies or as enemies (factions.json "allies"/"enemies").
static func allies_of(faction_id: String) -> Array:
	return faction(faction_id).get("allies", [])


static func enemies_of(faction_id: String) -> Array:
	return faction(faction_id).get("enemies", [])


## How a hostile faction is drawn and marked (terror groups, 2026-10-20): "militia" (orange: Black
## Ridge, the cartels, the Highland Free Front) or "hostile" (red: the terror groups and the
## armies), from its "side"; one without falls back to the old rule (the insurgent kit is militia).
static func faction_side(faction_id: String) -> String:
	var f := faction(faction_id)
	if f.has("side"):
		return String(f.side)
	return "militia" if String(f.get("kit", "insurgent")) == "insurgent" else "hostile"


## A faction's short name for radio and news lines ("the Shura"), else its name.
static func faction_short(faction_id: String) -> String:
	var f := faction(faction_id)
	return String(f.get("short", f.get("name", faction_id)))


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
