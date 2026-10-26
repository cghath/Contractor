class_name Foraging
extends RefCounted
## Wild edibles, medicine and poison (docs/survival_nature.md; calls 42, 105): forage spots on
## ZoneScatter's scrub, thickets and trees, each spot's plant fixed by where it stands (plant_of:
## data/survival_flora.json "forage" by the scatter kind's shares), ready in its seasons (berries
## in summer, mushrooms in autumn, nettles and wild garlic in spring, willow bark all year, yarrow,
## honey from a wild hive; nightshade and the death cap their poisons) and again regrow_days after
## it was picked (kept by zone in Survival.state()["nature"]["picked"]).
## Picking (server_forage): within REACH_M, a "forage" interaction. A poison you can't tell apart
## (tells: fieldcraft at the plant's "tell", a field guide counting GUIDE_LEVELS more: the death cap
## at 4, nightshade at 2) comes as what it looks like, its entry's state carrying {"poison"}; eaten
## (Survival.server_eat calls on_eaten), it poisons: Needs' food poisoning for the poison's hours and
## a "poison" record on the body for the medical lane ({"id", "left_h", "trauma"}). One you can tell
## apart comes as itself (a Death Cap, Nightshade Berries), and eaten still poisons.
## Every number here is Proposed.

const REACH_M := 3.0
const GUIDE_LEVELS := 2
const XP := 3.0
const KINDS := {ZoneScatter.Kind.SCRUB: "scrub", ZoneScatter.Kind.THICKET: "thicket", ZoneScatter.Kind.TREE: "tree"}


static func data() -> Dictionary:
	return Nature.flora().get("forage", {})


static func spec(plant: String) -> Dictionary:
	return data().get(plant, {})


## The plant at scatter item `item` ("" none), fixed by where it stands.
static func plant_of(item: Dictionary) -> String:
	var kind := String(KINDS.get(int(item.kind), ""))
	if kind == "" or item.has("felled"):
		return ""
	var p: Vector3 = item.pos
	var roll := float(posmod(hash(Vector3i(roundi(p.x * 10.0), roundi(p.z * 10.0), 77)), 10000)) / 10000.0
	var acc := 0.0
	for plant: String in data():
		var d: Dictionary = data()[plant]
		if not kind in (d.get("on", []) as Array):
			continue
		acc += float(d.get("share", 0.0))
		if roll < acc:
			return plant
	return ""


## Whether `plant` is in season in `season`.
static func in_season(plant: String, season: String) -> bool:
	return season in (spec(plant).get("seasons", []) as Array)


static func picked_rec() -> Dictionary:
	var r := Nature.rec()
	if not r.get("picked") is Dictionary:
		r["picked"] = {}
	return r["picked"]


## Whether scatter spot `index` with `plant` can be picked now (in season, regrown).
static func is_ready(index: int, plant: String) -> bool:
	if plant == "" or not in_season(plant, Seasons.current()):
		return false
	var key := "%s:%d" % [Nature.zone(), index]
	return Survival.day() - int(picked_rec().get(key, -9999)) >= int(spec(plant).get("regrow_days", 3))


## The forage spots within `r` of `pos`: [{"index", "pos", "plant", "ready"}].
static func spots_near(level: Node, pos: Vector3, r := REACH_M) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var zl := level as ZoneLevel
	if zl == null or zl.scatter == null:
		return out
	var sc := zl.scatter
	var c := sc._cell_of(pos.x, pos.z)
	var span := ceili(r / ZoneScatter.CELL_M)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for i: int in sc._cells.get(c + Vector2i(dx, dz), []):
				var item: Dictionary = sc.items[i]
				var p: Vector3 = item.pos
				if Vector2(p.x - pos.x, p.z - pos.z).length() > r:
					continue
				var plant := plant_of(item)
				if plant != "":
					out.append({"index": i, "pos": p, "plant": plant, "ready": is_ready(i, plant)})
	return out


## The fieldcraft `s` tells plants apart with (a field guide carried: GUIDE_LEVELS more).
static func eye(s: Soldier) -> int:
	var lvl := Rpg.level(s, "fieldcraft") if s else 0
	if s and s.inventory.count_of(&"field_guide") > 0:
		lvl += GUIDE_LEVELS
	return lvl


## Whether `s` tells `plant` from what it looks like.
static func tells(s: Soldier, plant: String) -> bool:
	return eye(s) >= int(spec(plant).get("tell", 0))


## Host: `s` forages scatter spot `index`. "" or why not.
static func server_forage(s: Soldier, index: int) -> String:
	var level := CompoundLevel.current(s)
	var zl := level as ZoneLevel
	if zl == null or zl.scatter == null or index < 0 or index >= zl.scatter.items.size():
		return "?"
	var item: Dictionary = zl.scatter.items[index]
	var p: Vector3 = item.pos
	if Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length() > REACH_M:
		return "Too far"
	var plant := plant_of(item)
	if plant == "":
		return "Nothing worth picking here"
	if not is_ready(index, plant):
		return "Nothing on it now" if in_season(plant, Seasons.current()) else "Not the season for it"
	var d := spec(plant)
	var r: Array = d.get("n", [1, 2])
	var n := randi_range(int(r[0]), int(r[1]))
	var id := String(d.get("item", plant))
	var state := {}
	if d.has("looks_like") and not tells(s, plant):
		id = String(d.looks_like)
		state = {"poison": String(d.get("poison", plant))}
	picked_rec()["%s:%d" % [Nature.zone(), index]] = Survival.day()
	Wildlife._give(s, StringName(id), n, state)
	Rpg.xp(s, "fieldcraft", XP)
	if bool(d.get("stings", false)):
		s.vitals.server_damage(1.0)
	var label := String(ItemDB.get_item(StringName(id)).name) if ItemDB.has_item(StringName(id)) else id
	Survival._tell(s, "Picked: %d %s%s" % [n, label, " (you got stung)" if bool(d.get("stings", false)) else ""])
	return ""


## Host (Survival.server_eat, after Needs.eat): a poison in what `s` ate (its entry's state, or the
## item's own): Needs' food poisoning for the poison's hours and the "poison" record on his body.
## Returns the poison's id or "".
static func on_eaten(_s: Soldier, n: Dictionary, item: ItemData, state: Dictionary) -> String:
	var poison := String(state.get("poison", item.stats.get("poison", "")) if item else state.get("poison", ""))
	if poison == "":
		return ""
	poisoned(n, poison)
	return poison


## `n` (a body's stores) poisoned by `poison`.
static func poisoned(n: Dictionary, poison: String) -> void:
	var p: Dictionary = (Nature.flora().get("poisons", {}) as Dictionary).get(poison, {})
	var hours := float(p.get("hours", 12.0))
	n["sick"] = {"id": "food_poisoning", "left_h": hours, "onset_h": 1.0, "from": poison}
	n["poison"] = {"id": poison, "left_h": hours, "trauma": float(p.get("trauma", 5.0))}
	var line := String(p.get("line", ""))
	if line != "":
		n["poison_line"] = line
