class_name FoundLoot
extends RefCounted
## The early loot curve (the Captain's playtest, 2026-10-26: "got a gun off a mil zombie in the
## first 5 minutes"; docs/survival_deadtime.md "Early loot curve", survival.md call 38: ammo scarce,
## guns common-ish but a real find). A working gun with ammo is a find of the first hour, not the
## first five minutes, and the military places stay the reward:
##
## - **The zone's tier** (zone_tier): links from the start zone on the region map, plus a dangerous
##   region's step (the city). Tier 0 is the start zone.
## - **The dead's origins** (DeadDress.roll_at, armed_mults): outside a military place the soldiers'
##   and cops' shares grow by ARMED_TIER_STEP a tier; in the start zone no soldiers turn within
##   START_CLEAR_M of the farm (unless a military place is there).
## - **Boxes found first** (first_roll, WorldCache.server_fill's first roll of a WorldValuables box:
##   a site box, a field cache in the open, a strongbox): within START_CLEAR_M of the farm the guns
##   in a box that isn't at a military place were taken by whoever left; a box in the open away
##   from the military keeps its gun OPEN_GUN_KEPT[tier] of the time; a gun that's there has a found
##   condition (WeaponCondition.found_state: dry or weathered).
## - **Ground loot** (ground_state, ZoneLevel's module loot): guns and ammo lying about have a
##   found condition too.
## Host side, survival only (Wear.enabled). Every number is Proposed.

const START_CLEAR_M := 250.0
const TIER_MAX := 3
## Soldier and cop shares outside military places: x(1 + ARMED_TIER_STEP x tier).
const ARMED_TIER_STEP := 1.0
## A region's danger adds to the zone's tier.
const DANGER_REGIONS := {"city": 1}
## A gun in a box in the open (not at a military place) is still in it this often, by tier.
const OPEN_GUN_KEPT: Array[float] = [0.35, 0.6, 0.8, 1.0]
## Military places (base types): their dead and their boxes are the reward, never thinned.
const MILITARY: Array[String] = ["hq", "qrf_base", "outpost", "checkpoint", "comms", "airfield", "fuel_depot", "compound"]

## Tests: the zone's tier (-1: by the rules).
static var force_tier := -1


## The zone being played's tier: 0 the start zone, +1 a link away (to TIER_MAX), + its region's danger.
static func zone_tier() -> int:
	if force_tier >= 0:
		return force_tier
	var st := Survival.state()
	var zone := String(st.get("zone", ""))
	var start := String(st.get("start_zone", zone))
	var d := RegionMap.distance(start, zone)
	if d < 0:
		d = 0 if zone == start else TIER_MAX
	var region := String(WorldRegions.zone_info(zone, int(st.get("seed", 0))).get("region", "")) if zone != "" else ""
	return clampi(d + int(DANGER_REGIONS.get(region, 0)), 0, TIER_MAX)


static func military(site: String) -> bool:
	return ZoneModules.base(site) in MILITARY


## The farm (the start zone's first insertion point, where the cold open wakes him), or null
## outside the start zone.
static func farm(level: Node) -> Variant:
	var zl := level as ZoneLevel
	if zl == null:
		return null
	var st := Survival.state()
	if String(st.get("zone", "")) != String(st.get("start_zone", "")):
		return null
	var points := zl.insertion_points()
	return zl.ground_point(points[0]) if not points.is_empty() else null


## Whether `pos` is within START_CLEAR_M of the farm (flat), in the start zone.
static func near_farm(level: Node, pos: Vector3) -> bool:
	var f: Variant = farm(level)
	if not f is Vector3:
		return false
	var at: Vector3 = f
	return Vector2(pos.x - at.x, pos.z - at.z).length() <= START_CLEAR_M


## The multipliers on a site's soldier (x) and cop (y) shares of the dead at `pos`.
static func armed_mults(level: Node, pos: Vector3, site: String) -> Vector2:
	if military(site):
		return Vector2.ONE
	var m := 1.0 + ARMED_TIER_STEP * zone_tier()
	return Vector2(0.0 if near_farm(level, pos) else m, m)


## Host (WorldCache.server_fill, a box's first roll only): `items` thinned and weathered by where
## the box `at` stands. Only WorldValuables' boxes (a site box, a field cache, a strongbox); others
## (a bunker's rooms, an event's crates, a survivor's stash) pass as they are.
static func first_roll(items: Array, at: WorldCache) -> Array:
	if not Wear.enabled() or at == null or not at.is_inside_tree():
		return items
	var uid := at.uid
	if not (uid.begins_with("scatter_val") or "_box_" in uid or uid.ends_with("_strongbox")):
		return items
	var level := CompoundLevel.current(at)
	var pos := at.global_position
	var site := DeadDress.site_at(level, pos)
	var dry := Throwables.indoors(at.get_world_3d(), pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([uid, "found", int(Survival.state().get("seed", 0))])
	var mil := military(site)
	var cleared := not mil and near_farm(level, pos)
	var kept := 1.0 if mil or dry else OPEN_GUN_KEPT[clampi(zone_tier(), 0, OPEN_GUN_KEPT.size() - 1)]
	var out: Array = []
	for e: Dictionary in items:
		var item := ItemDB.get_item(StringName(String(e.get("id", ""))))
		if not WeaponCondition.is_gun(item) or (e.get("state", {}) as Dictionary).has(Wear.KEY):
			out.append(e)
			continue
		if cleared or rng.randf() >= kept:
			continue  # taken by whoever came first
		for i in int(e.get("count", 1)):
			out.append({"id": String(e.id), "count": 1, "state": WeaponCondition.found_state(item, dry, rng)})
	return out


## Host (ZoneLevel's module loot, survival only): the found state of `id` lying at `pos` (a gun's
## or ammo's condition by where it lay), {} for anything else or outside survival.
static func ground_state(level: Node, id: StringName, pos: Vector3, uid: String) -> Dictionary:
	if not Wear.enabled() or level == null or not (level as Node3D).is_inside_tree():
		return {}
	var item := ItemDB.get_item(id)
	if item == null or not (WeaponCondition.is_gun(item) or AmmoCondition.is_ammo(item)):
		return {}
	var dry := Throwables.indoors((level as Node3D).get_world_3d(), pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([uid, "found", int(Survival.state().get("seed", 0))])
	if WeaponCondition.is_gun(item):
		return WeaponCondition.found_state(item, dry, rng)
	var c := AmmoCondition.roll(dry, rng)
	return {Wear.KEY: c} if c < 99.5 else {}
