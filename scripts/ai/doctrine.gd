class_name Doctrine
extends RefCounted
## Faction doctrine (Captain, P0164 queue 17 part 6): how a side's fighters were trained to
## fight, as weights that bias decisions the squad AI already makes, loaded once from
## res://data/doctrines.json (its "_notes" say what each weight does). Three profiles:
## insurgent (short range, long bursts, quick to break, rarely flanks), regular army (steady,
## frags readily, flanks) and PMC (long range, controlled bursts, steadiest under fire). The
## friendly squad fights as a PMC; hostiles as their zone's people (an insurgent region's are
## insurgents, a regional army's regulars). A squad (Squad.doctrine) or a unit
## (SquadAI.doctrine) can be given another.

const PATH := "res://data/doctrines.json"
const INSURGENT := &"insurgent"
const REGULAR := &"regular"
const PMC := &"pmc"
## What a weight is when the file lacks it: the squad AI's numbers before doctrines.
const FALLBACK := {"engage_m": 60.0, "reaction": 1.0, "aim_deg": 0.0, "burst": 1.0, "burst_pause": 1.0, "cover_fire_s": 5.0,
	"frag_cooldown_s": 15.0, "frag_wait_s": 4.0, "morale_shaken": 0.4, "morale_broken": 0.25, "advance_after_s": 6.0, "flank": 0.0}

static var _data := {}
## The hostile side's doctrine, worked out once per zone (zone id -> doctrine id).
static var _hostile_by_zone := {}


## Every doctrine id in the file.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: String in _profiles():
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return _profiles().has(String(id))


## Weight `key` of doctrine `id` (FALLBACK's when the profile or the weight is missing).
static func value(id: StringName, key: String) -> float:
	var profile: Dictionary = _profiles().get(String(id), {})
	return float(profile.get(key, FALLBACK.get(key, 0.0)))


## "Insurgent", "PMC"... ("" for an unknown id).
static func display_name(id: StringName) -> String:
	return String(_profiles().get(String(id), {}).get("name", ""))


## The doctrine `faction`'s fighters follow when neither their squad nor they have one set:
## the file's "sides", except that hostiles fight as the people of the zone they're in
## ("nations", by Names.region_nation of the zone's region).
static func default_for(faction: StringName) -> StringName:
	var sides: Dictionary = _load().get("sides", {})
	var side := StringName(String(sides.get(String(faction), INSURGENT)))
	if faction != &"hostile":
		return side
	var zone := GameState.zone_id
	if not _hostile_by_zone.has(zone):
		var nation := Names.region_nation(String(MissionRegistry.zone(zone).get("region", "")))
		var by_nation: Dictionary = _load().get("nations", {})
		_hostile_by_zone[zone] = StringName(String(by_nation.get(nation, side)))
	return _hostile_by_zone[zone]


static func _profiles() -> Dictionary:
	return _load().get("doctrines", {})


static func _load() -> Dictionary:
	if not _data.is_empty():
		return _data
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Doctrine: cannot open %s" % PATH)
		return _data
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("doctrines"):
		push_error("Doctrine: %s is not a valid doctrine file" % PATH)
		return _data
	_data = parsed
	return _data
