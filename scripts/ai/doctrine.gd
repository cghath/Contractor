class_name Doctrine
extends RefCounted
## Faction doctrine (Captain, P0164 queue 17 part 6): how a side's fighters were trained to
## fight, as weights meant to bias decisions the squad AI already makes (pending: see
## below), loaded once from res://data/doctrines.json (its "_notes" say what each weight
## does). Three profiles:
## insurgent (short range, long bursts, quick to break, rarely flanks), regular army (steady,
## frags readily, flanks) and PMC (long range, controlled bursts, steadiest under fire). The
## friendly squad fights as a PMC; hostiles as their zone's people (an insurgent region's are
## insurgents, a regional army's regulars). A squad (Squad.doctrine) can be given another.
##
## Every weight acts now (AI bar G-15, finished 2026-10-20; Captain: the last AI bar gaps). Each
## leans the squad AI's own tuned number by factor(): the weight over the same weight of its
## side's usual doctrine (default_for: insurgents for the hostile side, the PMC for the squad), so
## each side's usual enemy fights exactly as tuned (the P0362 accuracy and reaction calibration
## was against insurgents) and another doctrine on that side is sharper or looser than it, a
## regular army or the rival PMC among the hostiles. aim_deg adds its difference the same way:
##   engage_m       how far out it picks targets (SquadAI target scan: reach x factor, never more
##                  than the weapon and optic reach, G-27),
##   reaction       the time to spot and react to a new target (SquadAI._build_awareness),
##   aim_deg        degrees of aim error added (SquadAI._aim_error_deg),
##   burst, burst_pause   burst length and the pause between (SquadAI.burst_rounds, pause_mult),
##   cover_fire_s   how long after the last contact it keeps covering a moving buddy (SquadAI._shoot),
##   frag_cooldown_s, frag_wait_s   a unit's frag rhythm (SquadAI._maybe_frag),
##   morale_shaken, morale_broken   where aim suffers and where it breaks (SquadAI morale),
##   advance_after_s   how long a hostile waits without sight before pushing a bound,
##   flank          how far to the side of the enemy that bound goes (0 straight at him, 1 wide).
##   spacing        (G-26) the gaps between its men and fire teams on the move, as a multiple of
##                  Squad.SPACINGS (Squad.resolved; read as it is, not over the side's usual: an
##                  insurgent band bunches up, a regular army keeps the drill's gaps).
## A per-unit doctrine (SquadAI.doctrine) is still to come: a squad's, or its side's.

const PATH := "res://data/doctrines.json"
const INSURGENT := &"insurgent"
const REGULAR := &"regular"
const PMC := &"pmc"
## The weights no AI reads yet (see the class notes); the file's "_pending" lists the same.
const PENDING: Array[String] = []
## The weights the AI reads now (AI bar G-15, one at a time): burst and burst_pause (SquadAI
## burst_rounds and pause_mult, G-09). The file's "_wired" lists the same.
const WIRED: Array[String] = ["burst", "burst_pause", "engage_m", "reaction", "aim_deg", "cover_fire_s",
	"frag_cooldown_s", "frag_wait_s", "morale_shaken", "morale_broken", "advance_after_s", "flank", "spacing"]

## What a weight is when the file lacks it: the squad AI's numbers before doctrines (engage_m:
## a hostile's sight, SquadAI.SIGHT_RANGE).
const FALLBACK := {"engage_m": 200.0, "reaction": 1.0, "aim_deg": 0.0, "burst": 1.0, "burst_pause": 1.0, "cover_fire_s": 5.0,
	"frag_cooldown_s": 15.0, "frag_wait_s": 4.0, "morale_shaken": 0.4, "morale_broken": 0.25, "advance_after_s": 6.0, "flank": 0.0, "spacing": 1.0}

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


## Weight `key` of doctrine `id` (FALLBACK's when the profile or the weight is missing). A
## weight still in PENDING isn't wired into any decision yet: reading it doesn't make it act.
static func value(id: StringName, key: String) -> float:
	var profile: Dictionary = _profiles().get(String(id), {})
	return float(profile.get(key, FALLBACK.get(key, 0.0)))


## How far out doctrine `id`'s fighters pick targets (audit F-03): its engage_m, but never past
## what the shooter can see (`sight_m`: SquadAI.SIGHT_RANGE for a hostile, SQUAD_SIGHT_RANGE
## for the squad) nor past its weapon's reach (`weapon_m`, when known: about 300 m for an
## M4/Mk18, 600 m for an M110, 50 m for an M17). A doctrine can be set on either side's squad
## (Squad.doctrine), so a PMC's 300 m on a hostile still stops at 200 m. engage_m is pending:
## wiring it into target picking goes through here, so no doctrine can engage what it can't see.
## Doctrine `id`'s `key` over its side's usual doctrine's (`side`: a faction, default_for): how
## much it scales the AI's own number (1 for the usual doctrine itself, or a zero reference).
static func factor(id: StringName, key: String, side: StringName) -> float:
	var ref := value(default_for(side), key)
	return value(id, key) / ref if ref > 0.0 else 1.0


## Doctrine `id`'s `key` less its side's usual doctrine's: what it adds (aim_deg).
static func offset(id: StringName, key: String, side: StringName) -> float:
	return value(id, key) - value(default_for(side), key)


static func engage_m(id: StringName, sight_m: float, weapon_m := INF) -> float:
	return minf(value(id, "engage_m"), minf(sight_m, weapon_m))


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
