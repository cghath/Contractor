class_name WaterWorks
extends RefCounted
## Water (docs/survival_medical.md section 5, call 48): the sources and their quality, the taps
## that run in a zone while its water tower or pump house is intact or repaired
## (server_repair: mechanics, parts, power), and treating water (boiling on a fire or stove,
## a filter, tablets). Raw water's sickness roll is Needs.eat's (WATER_RISK by quality); a
## bottle filled here carries its quality in its entry's state. State:
## Survival.state()["water_works"]: {zone: {"intact": bool, "repaired": bool}}.

const KEY := "water_works"
## Proposed: the quality of each kind of source. A tap runs clean only while the works do.
const SOURCES := {"tap": "clean", "well": "questionable", "river": "questionable", "lake": "questionable",
	"dam": "clean", "rain_barrel": "clean", "snow": "clean", "puddle": "dirty", "pond": "dirty"}
## Sources that need a fire to be drinkable at all (snow is melted).
const NEEDS_FIRE: Array[String] = ["snow"]
## Proposed: a zone's works still intact at the start (by the seed), the repair's skill, parts
## and power (as the lab's: a jerrycan for the pump's generator or a vehicle battery).
const INTACT_SHARE := 0.25
const REPAIR_SKILL := 3
const REPAIR_PARTS: Array = [["machine_parts", 1], ["copper_wire", 1]]
const POWER_ITEMS: Array[String] = ["jerrycan", "vehicle_battery"]
## Boiling: 10 world minutes on a fire or stove (real seconds at the world's day length).
const BOIL_WORLD_MIN := 10.0
## A filter's uses before it's spent (a hand filter item; the filter piece is the builder's).
const FILTER_USES := 20
const FIRE_M := 3.0


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


## `zone`'s works ({"intact", "repaired"}), rolled from the world's seed the first time.
static func works(zone: String) -> Dictionary:
	var d := data()
	if not d.get(zone) is Dictionary:
		var r := RandomNumberGenerator.new()
		r.seed = hash([int(Survival.state().get("seed", 0)), zone, "water works"])
		d[zone] = {"intact": r.randf() < INTACT_SHARE, "repaired": false}
	return d[zone]


## Whether the taps run in `zone`.
static func taps_run(zone: String) -> bool:
	var w := works(zone)
	return bool(w.get("intact", false)) or bool(w.get("repaired", false))


## The quality of water from `source` (SOURCES' keys) in `zone`: "" when there's none (a dry tap).
static func quality(source: String, zone := "") -> String:
	if source == "tap" and not taps_run(zone):
		return ""
	return String(SOURCES.get(source, "dirty"))


## Host: `s` repairs `zone`'s water tower or pump house: mechanics REPAIR_SKILL, REPAIR_PARTS
## from his kit, and power (a jerrycan or a battery, or `free`: a generator wired by the builder).
## Returns why not ("" the taps run).
static func server_repair(zone: String, s: Soldier = null, free := false) -> String:
	if taps_run(zone):
		return ""
	if not free:
		if s == null:
			return "Nobody to do the work"
		if not Rpg.gate(s, "mechanics", REPAIR_SKILL):
			return "It takes a mechanic (mechanics %d) to get the pumps going" % REPAIR_SKILL
		for p: Array in REPAIR_PARTS:
			if s.inventory.count_of(StringName(String(p[0]))) < int(p[1]):
				return "It needs %s" % ItemDB.get_item(StringName(String(p[0]))).name.to_lower() if ItemDB.has_item(StringName(String(p[0]))) else "It needs parts"
		var power := ""
		for it: String in POWER_ITEMS:
			if s.inventory.count_of(StringName(it)) > 0:
				power = it
				break
		if power == "":
			return "The pump needs power: fuel for its generator or a battery"
		for p: Array in REPAIR_PARTS:
			for i in int(p[1]):
				FallenStory.take_one(s, String(p[0]))
		FallenStory.take_one(s, power)
		Rpg.xp(s, "mechanics", 8.0, REPAIR_SKILL)
	works(zone)["repaired"] = true
	Survival._journal_line("The water tower runs again: the taps in %s have water." % zone)
	return ""


## Treats a water entry's `state` by `how` ("boil", "filter", "tablet"): clean after (Needs.treat_water).
static func treat(state: Dictionary, how: String) -> Dictionary:
	Needs.treat_water(state)
	state["treated"] = how
	return state


## Real seconds a boil takes (10 world minutes).
static func boil_seconds() -> float:
	return BOIL_WORLD_MIN / 1440.0 * Survival.DAY_MIN * 60.0


## Whether `s` stands by a fire: a built stove piece within FIRE_M (a campfire later).
static func near_fire(s: Soldier) -> bool:
	if s == null or not s.is_inside_tree():
		return false
	for node in s.get_tree().get_nodes_in_group(InteractionMenu.INTERACTABLES):
		var bp := node as BuildPiece
		if bp and String(bp.rec.get("k", "")) == "stove" and float(bp.rec.get("prog", 0.0)) >= 1.0 and bp.global_position.distance_to(s.global_position) <= FIRE_M:
			return true
	return false


## Host: `s` treats the untreated water he carries by `how`: "boil" (a fire near: `fire` or
## near_fire; he's busy boil_seconds), "filter" (a water_filter, worn a use), "tablet" (one
## water_tablets each). Returns how many bottles came clean, or -1 and he's told why.
static func server_treat(s: Soldier, how: String, fire := false) -> int:
	match how:
		"boil":
			if not fire and not near_fire(s):
				Survival._tell(s, "Boiling needs a fire or a stove")
				return -1
		"filter":
			if s.inventory.count_of(&"water_filter") <= 0:
				Survival._tell(s, "No water filter")
				return -1
		"tablet":
			if s.inventory.count_of(&"water_tablets") <= 0:
				Survival._tell(s, "No purification tablets")
				return -1
	var done := 0
	for c: StringName in s.inventory.containers:
		for e: Dictionary in s.inventory.containers[c]:
			var item := ItemDB.get_item(StringName(String(e.get("id", "")))) if ItemDB.has_item(StringName(String(e.get("id", "")))) else null
			if item == null or not item.stats.has("water_l") or item.stats.has("kcal"):
				continue
			var st: Dictionary = e.get("state", {})
			if Needs.quality_of(item, st) == "clean":
				continue
			if how == "tablet" and not FallenStory.take_one(s, "water_tablets"):
				break
			treat(st, how)
			e["state"] = st
			done += int(e.get("count", 1))
	if how == "boil" and done > 0:
		s.server_busy(boil_seconds(), "Boiling water")
	Survival._tell(s, "%d bottles clean" % done if done > 0 else "Nothing to treat")
	return done


## Host: `s` fills a bottle at `source` in `zone`: a dirty_water_bottle whose state carries the
## source's quality (snow needs a fire to melt). Returns why not ("" filled).
static func server_fill(s: Soldier, source: String, zone := "") -> String:
	var q := quality(source, zone)
	if q == "":
		return "The tap is dry: the zone's water works are down"
	if source in NEEDS_FIRE and not near_fire(s):
		return "Snow has to be melted on a fire"
	if s.inventory.take(&"dirty_water_bottle", 1, {"quality": q, "source": source}) != 1:
		return "No room for the water"
	return ""
