class_name Moods
extends RefCounted
## Moods and breaks of Contractor: Fallen's people (docs/survival_people.md section 2, calls 40,
## 75), RimWorld-style: a person's mood (0-100) is a base of BASE plus their traits' lean plus
## every moodlet's value; a moodlet is {cause, value, until} with `until` in world hours
## (Survival.day() * 24 + hour(); -1 "while it holds": a condition the hourly tick sets and clears).
## A cause may carry who it's about after a colon ("friend_died:p3"); TABLE is keyed by the part
## before it. Under BREAK_LINE for BREAK_AFTER_H world hours a person rolls a break by traits
## (BREAK_TRAITS) each hour at BREAK_CHANCE. Static: the record is plain data (SurvivorPerson).

## Proposed numbers (the doc's table; the ones it lacks are marked).
const BASE := 50.0
const BREAK_LINE := 20.0
const BREAK_AFTER_H := 4.0
const BREAK_CHANCE := 0.25
## How long a break lasts (world hours) before the person settles.
const BREAK_HOURS := {"crying": 1.0, "rage": 0.5, "binge": 2.0, "hiding": 3.0, "desertion": 0.0, "refusal": 1.0}
## A break vents a little (Proposed): the mood after it.
const CATHARSIS := 6.0
## [value, hours] (hours -1: while it holds).
const TABLE := {
	"ate_hot": [6.0, 24.0], "ate_raw": [-8.0, 24.0],
	"slept_bed": [4.0, 24.0], "slept_ground": [-4.0, 24.0], "no_sleep": [-12.0, 24.0],
	"warm_dry": [2.0, -1.0], "cold": [-6.0, -1.0], "soaked": [-8.0, -1.0],
	"hungry": [-6.0, -1.0], "starving": [-14.0, -1.0], "thirsty": [-8.0, -1.0],  # (Proposed: the doc's needs)
	"friend_died": [-18.0, 120.0], "companion_died": [-8.0, 72.0], "friend_sick": [-6.0, -1.0],
	"saw_horde": [-10.0, 48.0], "bitten": [-15.0, -1.0],
	"killed_person": [-8.0, 72.0],
	"job_liked": [3.0, 24.0], "job_hated": [-5.0, 24.0], "long_watch": [-6.0, 24.0],
	"captive_freed": [8.0, 72.0], "paid_in_people": [-20.0, 240.0],
	"settlement_grew": [4.0, 48.0], "wall_fell": [-6.0, 48.0], "raid_repelled": [10.0, 48.0],
	"grave_for_friend": [5.0, 120.0], "grave": [2.0, 72.0], "body_left_out": [-6.0, 120.0],
	"promise_kept": [6.0, 120.0], "promise_broken": [-10.0, 120.0],
	"put_down_friend": [-12.0, 72.0],  # (Proposed: call 77, putting a risen friend down)
	"threatened": [-15.0, 72.0], "gift": [4.0, 24.0], "joined": [8.0, 48.0],  # (Proposed)
	"lost_their_player": [-10.0, 72.0], "break_vented": [6.0, 12.0],  # (Proposed)
}
## Traits lean the mood (Proposed).
const TRAIT_LEAN := {"optimist": 6.0, "gloomy": -6.0}
## Breaks and the traits that pull toward each (call 75); the order breaks ties.
const BREAK_KINDS := ["desertion", "crying", "rage", "binge", "hiding", "refusal"]
const BREAK_TRAITS := {
	"desertion": ["gloomy", "fickle", "lazy"],
	"crying": ["timid", "squeamish", "kind"],
	"rage": ["hot_headed", "cruel"],
	"binge": ["drinker", "smoker", "greedy"],
	"hiding": ["timid", "gloomy"],
	"refusal": ["hot_headed", "fickle", "brave"],
}
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


## The world's time in hours (moodlets' clock).
static func now_h() -> float:
	return Survival.day() * 24.0 + Survival.hour()


## The base cause of `cause` ("friend_died:p3" -> "friend_died").
static func base_of(cause: String) -> String:
	return cause.get_slice(":", 0)


## Adds (or refreshes) the moodlet `cause` on `rec`: the table's value and length unless given.
static func add(rec: Dictionary, cause: String, value := NAN, hours := NAN) -> void:
	var row: Array = TABLE.get(base_of(cause), [0.0, 24.0])
	var v := float(row[0]) if is_nan(value) else value
	var h := float(row[1]) if is_nan(hours) else hours
	if base_of(cause) == "killed_person" and SurvivorPerson.has_trait(rec, "cruel"):
		v *= 0.4  # less for the cruel
	var list: Array = rec.get("moodlets", [])
	for m: Dictionary in list:
		if String(m.cause) == cause:
			m.value = v
			m.until = -1.0 if h < 0.0 else now_h() + h
			return
	list.append({"cause": cause, "value": v, "until": -1.0 if h < 0.0 else now_h() + h})
	rec["moodlets"] = list


static func remove(rec: Dictionary, cause: String) -> void:
	rec["moodlets"] = (rec.get("moodlets", []) as Array).filter(func(m: Dictionary) -> bool: return String(m.cause) != cause)


static func has(rec: Dictionary, cause: String) -> bool:
	return (rec.get("moodlets", []) as Array).any(func(m: Dictionary) -> bool: return String(m.cause) == cause)


static func value_of(rec: Dictionary, cause: String) -> float:
	for m: Dictionary in rec.get("moodlets", []):
		if String(m.cause) == cause:
			return float(m.value)
	return 0.0


## A "while it holds" moodlet on or off.
static func hold(rec: Dictionary, cause: String, on: bool) -> void:
	if on and not has(rec, cause):
		add(rec, cause)
	elif not on and has(rec, cause):
		remove(rec, cause)


## The mood now (0-100). A forced mood ("mood_forced", tests and dev) wins.
static func mood(rec: Dictionary) -> float:
	if rec.has("mood_forced"):
		return float(rec.mood_forced)
	var m := BASE
	for t: String in rec.get("traits", []):
		m += float(TRAIT_LEAN.get(t, 0.0))
	for ml: Dictionary in rec.get("moodlets", []):
		m += float(ml.value)
	return clampf(m, 0.0, 100.0)


## The mood in a word band for lines and the talk: broken, low, ok, high.
static func band(rec: Dictionary) -> String:
	var m := mood(rec)
	return "broken" if m < BREAK_LINE else ("low" if m < 40.0 else ("ok" if m < 70.0 else "high"))


## Drops moodlets past their time.
static func expire(rec: Dictionary) -> void:
	var t := now_h()
	rec["moodlets"] = (rec.get("moodlets", []) as Array).filter(func(m: Dictionary) -> bool: return float(m.until) < 0.0 or float(m.until) > t)


## The conditions a body's needs hold (Needs' stores): hungry, starving, thirsty, cold, soaked,
## or warm and dry.
static func from_needs(rec: Dictionary, n: Dictionary) -> void:
	if n.is_empty():
		return
	Needs.ensure(n)
	hold(rec, "starving", float(n.hunger) < 10.0)
	hold(rec, "hungry", float(n.hunger) >= 10.0 and float(n.hunger) < 35.0)
	hold(rec, "thirsty", float(n.thirst) < 35.0)
	var cold := float(n.warmth) < Needs.SHIVER_C
	var soaked := float(n.wet) > 0.5
	hold(rec, "cold", cold)
	hold(rec, "soaked", soaked)
	hold(rec, "warm_dry", not cold and not soaked)


## One world hour of `rec`: moodlets expire, its needs' conditions are read, and under BREAK_LINE
## long enough it may break. Returns the break kind that started, or "". `night` lets desertion
## in (they leave at night).
static func hour_tick(rec: Dictionary, night: bool, rng: RandomNumberGenerator = null) -> String:
	expire(rec)
	from_needs(rec, rec.get("needs", {}))
	if String(rec.get("break", "")) != "":
		if now_h() >= float(rec.get("break_until", 0.0)) and String(rec.get("break", "")) != "refusal":
			end_break(rec)
		return ""
	if mood(rec) < BREAK_LINE:
		rec["low_hours"] = float(rec.get("low_hours", 0.0)) + 1.0
	else:
		rec["low_hours"] = 0.0
		return ""
	if float(rec.low_hours) < BREAK_AFTER_H:
		return ""
	var roll := force_roll if force_roll >= 0.0 else (rng.randf() if rng else randf())
	if roll >= BREAK_CHANCE:
		return ""
	var kind := pick_break(rec, roll / BREAK_CHANCE, night)
	start_break(rec, kind)
	return kind


## The break kind by traits: each kind weighs 1 per trait of its BREAK_TRAITS (a person with none
## of them: every kind 1); `roll` 0..1 picks along BREAK_KINDS' order. Desertion waits for night.
static func break_weights(rec: Dictionary, night: bool) -> Dictionary:
	var w := {}
	var any := false
	for k: String in BREAK_KINDS:
		var n := 0.0
		for t: String in BREAK_TRAITS[k]:
			if SurvivorPerson.has_trait(rec, t):
				n += 1.0
		w[k] = n
		any = any or n > 0.0
	if not any:
		for k: String in BREAK_KINDS:
			w[k] = 1.0
	if not night:
		w["desertion"] = 0.0
	return w


static func pick_break(rec: Dictionary, roll: float, night: bool) -> String:
	var w := break_weights(rec, night)
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	if total <= 0.0:
		return "crying"
	var acc := 0.0
	for k: String in BREAK_KINDS:
		acc += float(w[k]) / total
		if roll < acc and float(w[k]) > 0.0:
			return k
	return "crying"


static func start_break(rec: Dictionary, kind: String) -> void:
	rec["break"] = kind
	rec["break_until"] = now_h() + float(BREAK_HOURS.get(kind, 1.0))
	rec["low_hours"] = 0.0
	SurvivorPerson.note(rec, "broke down (%s)" % kind)


static func end_break(rec: Dictionary) -> void:
	rec["break"] = ""
	rec["break_until"] = 0.0
	add(rec, "break_vented", CATHARSIS)
