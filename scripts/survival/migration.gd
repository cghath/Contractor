class_name Migration
extends RefCounted
## The year's game and fish (docs/survival_nature.md; calls 42, 103): where each species is by
## season (data/survival_fauna.json "seasons": deer to the valleys in winter, the birds gone, the
## bear in its den), and fishing: rods and nets at the coast, rivers, streams, lakes, ponds and the
## dam, the catch an hour by the water and the season (fish_rate), a net NET_X a rod. Fishing is a
## timed action on the world clock (server_start_fishing, then server_stop_fishing pays out the
## hours sat there; server_fish for a set number of hours). Raw fish spoils in a day: smoked at a fire
## it keeps (the "smoked_fish" recipe). Every number here is Proposed.

const BODIES: Array[String] = ["coast", "river", "stream", "lake", "pond", "dam"]
const NET_X := 2.5
const FIELDCRAFT_X := 0.08
## How far from where he stands the water may be (m).
const REACH_M := 8.0
const MAX_H := 12.0


## Where `sp` is in `season` ("woods", "open", "hills", "valleys", "deep_woods", "stores", "den", "gone").
static func where(sp: String, season: String) -> String:
	var d: Dictionary = Wildlife.spec(sp)
	return String((d.get("seasons", {}) as Dictionary).get(season, d.get("habitat", "woods")))


## Whether `sp` is about at all in `season` (not gone, not denned up).
static func present(sp: String, season: String) -> bool:
	return not where(sp, season) in ["gone", "den"]


## Fish an hour with a rod at `body` in `season`.
static func fish_rate(body: String, season: String) -> float:
	var row: Dictionary = (Nature.fauna().get("fish", {}) as Dictionary).get(body, {})
	return float(row.get(season, 0.0))


## What bites at `body`.
static func fish_species(body: String) -> Array:
	return ((Nature.fauna().get("fish", {}) as Dictionary).get(body, {}) as Dictionary).get("species", [])


## The water at `pos` (or within REACH_M): "coast" (the sea), a ZoneWater body's kind ("river",
## "stream", "lake", "pond"), or "" for none. A dam is named by the caller (a landmark's water).
static func water_body_at(level: Node, pos: Vector3) -> String:
	var zl := level as ZoneLevel
	if zl == null or zl.terrain == null:
		return ""
	var t := zl.terrain
	for off: Vector2 in [Vector2.ZERO, Vector2(REACH_M, 0), Vector2(-REACH_M, 0), Vector2(0, REACH_M), Vector2(0, -REACH_M)]:
		var x := pos.x + off.x
		var z := pos.z + off.y
		if t.water:
			var bi := t.water._water_body_at(Vector2(x, z))
			if bi >= 0 and bi < t.water.bodies.size():
				return String((t.water.bodies[bi] as Dictionary).get("kind", "river"))
		if t.sea_side >= 0 and t.height_at(x, z) < t.sea_level - 0.3:
			return "coast"
	return ""


static func _gear(s: Soldier) -> float:
	if Wildlife.carries(s, "fishing_net"):
		return NET_X
	if Wildlife.carries(s, "fishing_rod"):
		return 1.0
	return 0.0


## Host: `s` fishes `hours` at the water by him (or `body` named): raw fish into his kit by the
## water's and season's rate, his gear and fieldcraft (the fraction carried to the next time).
## Returns how many, or -1 (no gear), -2 (no water).
static func server_fish(s: Soldier, hours: float, body := "") -> int:
	var gear := _gear(s)
	if gear <= 0.0:
		return -1
	if body == "":
		body = water_body_at(CompoundLevel.current(s), s.global_position)
	if body == "":
		return -2
	if Seasons.water_frozen() and body != "coast":
		gear *= 0.3  # (through a hole in the ice)
	var rate := fish_rate(body, Seasons.current()) * gear * (1.0 + FIELDCRAFT_X * Rpg.level(s, "fieldcraft"))
	var got := rate * minf(hours, MAX_H) + float(s.get_meta(&"fish_acc", 0.0))
	var n := floori(got)
	s.set_meta(&"fish_acc", got - n)
	if n > 0:
		Wildlife._give(s, &"raw_fish", n)
		Rpg.xp(s, "fieldcraft", 2.0 * n)
	return n


## Host: `s` starts fishing here (the world clock times it). "" or why not.
static func server_start_fishing(s: Soldier, body := "") -> String:
	if _gear(s) <= 0.0:
		return "You need a rod or a net"
	if body == "" and water_body_at(CompoundLevel.current(s), s.global_position) == "":
		return "There's no water to fish here"
	s.set_meta(&"fishing", {"since_h": Moods.now_h(), "body": body})
	return ""


## Host: `s` stops fishing: the hours since he started paid out (server_fish). Returns the fish.
static func server_stop_fishing(s: Soldier) -> int:
	if not s.has_meta(&"fishing"):
		return 0
	var f: Dictionary = s.get_meta(&"fishing")
	s.remove_meta(&"fishing")
	var n := server_fish(s, Moods.now_h() - float(f.since_h), String(f.body))
	if n >= 0:
		Survival._tell(s, "%d fish." % n if n > 0 else "Nothing biting.")
	return n


## The season's game for the settlement's hunters (SettlementJobs' hunt): autumn's fat, winter's lean.
static func hunt_x() -> float:
	return float({"autumn": 1.2, "winter": 0.5}.get(Seasons.current(), 1.0))
