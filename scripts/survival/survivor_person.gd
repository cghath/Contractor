class_name SurvivorPerson
extends RefCounted
## The one record of a person in Contractor: Fallen (docs/survival_people.md section 1,
## survival_world.md 4.2): a survivor met in the world, a companion, a settler, a captive or the
## dead are the same Dictionary in Survival.state()["people"][id], moved between statuses, never
## copied. Static helpers only: the record is plain data (saved with the world as JSON), so the
## rules are testable without a body.
##
## Fields: id, name, first, age, sex ("m" | "f"), look (PersonLook's outfit), face (SoldierLook),
## background (a string the RPG lane applies later), traits (a few of TRAITS), skills (the RPG
## lane's, read through Rpg when it's there, else {}), needs (Needs' stores: the same dictionary
## the body carries as meta "needs" while live), moodlets ([{cause, value, until}] in world hours:
## Moods), break ("" or a break kind), break_until, low_hours, relations ({id: -100..100}),
## opinion_of_players ({profile: -100..100}), want ({kind: money | item | favour | place, ...}),
## loyalty, courage (0-100), kit (Survival.kit_of entries), wounds, history ([{day, text}]),
## disposition (friendly | wary | hostile), zone, pos ([x, y, z]), home, status (STATUSES), and
## while dead: died_day, body_pos, killed_by_dead, rise_at, buried. A child (call 128, Children):
## child true, age under 16, family / guardian / orphan; status "taken" when the dead took them.
## A cultist deserter (Faith): cult_deserter, cleansing, cleansed. Bonds (Relationships, call 74):
## relations are kept symmetric there; partner (an id), close_h ({id: hours as close friends}),
## widowed, carer (a child's), job_h / refused_h (the hour's shift), hurt and "bruises" wounds.

const STATUSES := ["out_there", "companion", "settler", "captive", "dead", "player"]
## Traits (call 40): pairs that exclude each other, then singles. Proposed: 2-3 a person.
const TRAIT_PAIRS := [["brave", "timid"], ["kind", "cruel"], ["loyal", "fickle"], ["hard_worker", "lazy"],
	["optimist", "gloomy"], ["hot_headed", "calm"]]
const TRAIT_SINGLES := ["pious", "greedy", "squeamish", "drinker", "smoker", "night_owl"]
const BACKGROUNDS := ["farmer", "nurse", "mechanic", "police officer", "teacher", "soldier", "cook", "student",
	"truck driver", "hunter", "shop clerk", "electrician", "paramedic", "carpenter"]
## Wants (call 2, S4): Proposed shares.
const WANT_SHARES := {"money": 0.3, "item": 0.4, "favour": 0.2, "place": 0.1}
## Proposed: $200-1,500 (survival_people.md section 4).
const MONEY_RANGE := Vector2i(200, 1500)
## What cash items are worth (Proposed: found cash is a currency, call 26).
const CASH_VALUE := {"cash_roll": 50, "cash_bundle": 250, "cash_brick": 2500}
## The want list (section 4): what matches is an exact id, an item tag or an item type, `count` of it.
const WANT_ITEMS := [
	{"what": "antibiotics", "id": "antibiotics", "count": 1, "text": "a box of antibiotics"},
	{"what": "rifle", "tag": "rifle", "count": 1, "text": "a rifle"},
	{"what": "tins", "tag": "food", "count": 5, "text": "five tins of food"},
	{"what": "backpack", "type": "backpack", "count": 1, "text": "a backpack"},
]
## A favour: clear a marked place of the dead, or fetch something from it.
const FAVOUR_TASKS := ["clear", "fetch"]
const FETCH_ITEMS := ["antibiotics", "pack_daypack_20", "beans_tin"]
## What a survivor met in the world carries (Proposed).
const START_KIT := [["water_bottle", 1], ["beans_tin", 1]]
const ARMED_KIT := ["crowbar", "hatchet", "pipe"]


## A new person from `rng` (deterministic by the world seed and an index). `opts` overrides any
## field (tests: traits, want, mood...).
static func make(rng: RandomNumberGenerator, id: String, opts := {}) -> Dictionary:
	var female := rng.randf() < 0.45
	var who := Names.person(rng, &"friendly", &"rifleman")
	var first := String(who.get("first", "Sam"))
	if female:  # (Names.person picks the body by role; a survivor is anyone)
		var firsts: Array = (Names.FIRST.get(String(who.get("nation", "US")), Names.FIRST["US"]) as Dictionary).get(Names.FEMALE, [first])
		first = String(firsts[rng.randi_range(0, firsts.size() - 1)])
	var traits := roll_traits(rng)
	var rec := {
		"id": id, "name": "%s %s" % [first, String(who.get("surname", "Reed"))], "first": first,
		"age": rng.randi_range(18, 68), "sex": "f" if female else "m",
		"look": PersonLook.outfit(Person.CIVILIAN, Person.NEUTRAL, {"name": id}),
		"face": "", "background": BACKGROUNDS[rng.randi_range(0, BACKGROUNDS.size() - 1)],
		"traits": traits, "skills": {}, "needs": Needs.fresh(), "moodlets": [], "break": "", "break_until": 0.0,
		"low_hours": 0.0, "relations": {}, "opinion_of_players": {}, "want": {},
		"loyalty": clampi(rng.randi_range(25, 55) + (20 if "loyal" in traits else 0) - (20 if "fickle" in traits else 0), 0, 100),
		"courage": clampi(rng.randi_range(30, 60) + (25 if "brave" in traits else 0) - (25 if "timid" in traits else 0), 0, 100),
		"kit": [], "wounds": [], "history": [], "status": "out_there", "zone": "", "pos": [0.0, 0.0, 0.0], "home": [0.0, 0.0, 0.0],
		"disposition": "friendly",
	}
	rec.face = SoldierLook.make(SoldierLook.seed_of([id, rec.name]), String(who.get("nation", "US")), VoxelArt.FEMALE if female else VoxelArt.MALE, _skin_of(String(rec.look)))
	for e: Array in START_KIT:
		rec.kit.append({"id": e[0], "count": e[1]})
	rec.merge(opts, true)
	rec.disposition = disposition_for(rec.traits) if not opts.has("disposition") else String(opts.disposition)
	if rec.disposition != "friendly" and rng.randf() < 0.6:
		rec.kit.append({"id": ARMED_KIT[rng.randi_range(0, ARMED_KIT.size() - 1)], "count": 1})  # a weapon up
	if (rec.want as Dictionary).is_empty():
		rec.want = roll_want(rng)
	return rec


static func _skin_of(look: String) -> String:
	var parts := look.split(":")
	return parts[3] if parts.size() >= 5 else ""


## 2-3 traits: at most one of each pair, sometimes a single.
static func roll_traits(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pairs := TRAIT_PAIRS.duplicate()
	for i in pairs.size():  # (shuffle by the rng: the world's seed decides)
		var j := rng.randi_range(i, pairs.size() - 1)
		var t: Variant = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = t
	var n := rng.randi_range(2, 3)
	for p: Array in pairs:
		if out.size() >= n:
			break
		out.append(p[rng.randi_range(0, 1)])
	if rng.randf() < 0.4:
		var single: String = TRAIT_SINGLES[rng.randi_range(0, TRAIT_SINGLES.size() - 1)]
		if out.size() >= 3:
			out[2] = single
		else:
			out.append(single)
	return out


## How a stranger takes you by traits (Proposed): the cruel and hot-headed or brave keep a weapon
## up and warn you off (hostile); the timid, fickle and greedy are wary; the rest friendly.
static func disposition_for(traits: Array) -> String:
	if "cruel" in traits and ("hot_headed" in traits or "brave" in traits):
		return "hostile"
	if "timid" in traits or "fickle" in traits or "greedy" in traits:
		return "wary"
	return "friendly"


static func roll_want(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	var kind := "item"
	for k: String in WANT_SHARES:
		r -= float(WANT_SHARES[k])
		if r <= 0.0:
			kind = k
			break
	match kind:
		"money":
			return {"kind": "money", "amount": snappedi(rng.randi_range(MONEY_RANGE.x, MONEY_RANGE.y), 50)}
		"favour":
			var task: String = FAVOUR_TASKS[rng.randi_range(0, FAVOUR_TASKS.size() - 1)]
			var w := {"kind": "favour", "task": task, "done": false}
			if task == "fetch":
				w.item = FETCH_ITEMS[rng.randi_range(0, FETCH_ITEMS.size() - 1)]
			return w
		"place":
			return {"kind": "place"}
	var it: Dictionary = WANT_ITEMS[rng.randi_range(0, WANT_ITEMS.size() - 1)]
	var want := it.duplicate()
	want.kind = "item"
	return want


static func has_trait(rec: Dictionary, t: String) -> bool:
	return t in (rec.get("traits", []) as Array)


## The want in words ("$450", "a rifle", "clear the place I marked", "a bed somewhere safe").
static func want_text(rec: Dictionary) -> String:
	var w: Dictionary = rec.get("want", {})
	match String(w.get("kind", "")):
		"money":
			return "$%d" % int(w.get("amount", 0))
		"item":
			return String(w.get("text", "something"))
		"favour":
			var item: ItemData = ItemDB.get_item(StringName(String(w.item))) if String(w.get("item", "")) != "" else null
			return "the dead cleared from a place I marked" if String(w.get("task", "")) == "clear" else "%s from a place I marked" % (item.name if item else "something")
		"place":
			return "a bed somewhere with walls"
	return "nothing"


## Whether `item` (with `count`) answers an item want `w` (an id, a tag or a type).
static func matches(w: Dictionary, item: ItemData) -> bool:
	if item == null:
		return false
	if w.has("id") and String(item.id) == String(w.id):
		return true
	if w.has("tag") and String(w.tag) in item.tags:
		return true
	return w.has("type") and String(item.type) == String(w.type)


## The skills the RPG lane keeps for this person, if it's there (Rpg autoload with skills_of),
## else the record's own (a placeholder, {}).
static func skills_of(rec: Dictionary, from: Node = null) -> Dictionary:
	var rpg: Node = from.get_node_or_null(^"/root/Rpg") if from and from.is_inside_tree() else null
	if rpg and rpg.has_method(&"skills_of"):
		var s: Variant = rpg.call(&"skills_of", rec)
		if s is Dictionary:
			return s
	return rec.get("skills", {})


## The person's opinion of a player profile (0 for a stranger), and a change to it.
static func opinion_of(rec: Dictionary, profile: String) -> float:
	return float((rec.get("opinion_of_players", {}) as Dictionary).get(profile, 0.0))


static func change_opinion(rec: Dictionary, profile: String, by: float) -> void:
	var o: Dictionary = rec.get("opinion_of_players", {})
	o[profile] = clampf(float(o.get(profile, 0.0)) + by, -100.0, 100.0)
	rec["opinion_of_players"] = o


static func relation(rec: Dictionary, other_id: String) -> float:
	return float((rec.get("relations", {}) as Dictionary).get(other_id, 0.0))


static func change_relation(rec: Dictionary, other_id: String, by: float) -> void:
	var r: Dictionary = rec.get("relations", {})
	r[other_id] = clampf(float(r.get(other_id, 0.0)) + by, -100.0, 100.0)
	rec["relations"] = r


## A line in the person's history (the source of what they know: rumours later).
static func note(rec: Dictionary, text: String) -> void:
	var h: Array = rec.get("history", [])
	h.append({"day": Survival.day(), "text": text})
	rec["history"] = h.slice(-30)


static func pos_of(rec: Dictionary, key := "pos") -> Vector3:
	var p: Array = rec.get(key, [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() >= 3 else Vector3.ZERO


static func set_pos(rec: Dictionary, at: Vector3, key := "pos") -> void:
	rec[key] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## Loyal enough to obey a second order they refused (section 2): the loyal trait, or loyalty 50+.
static func is_loyal(rec: Dictionary) -> bool:
	return has_trait(rec, "loyal") or float(rec.get("loyalty", 0.0)) >= 50.0
