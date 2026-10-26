class_name Backgrounds
extends RefCounted
## Character creation (docs/survival_rpg.md section 3, calls 17, 84): a blank slate by default
## (every line 0, no perks), or a background (one line +MAIN, a second +SECOND; Proposed +3/+1)
## plus flaws worth 1-3 points each that buy line levels above the background (BUY_COST points a
## level, up to BUY_CAP). A 3-flaw survivor can start one line at 5 (call 84).
##
## A choice is a Dictionary: {"background": id or "", "flaws": [ids], "buys": {line: levels}}
## (NewWorldScreen's "survivor" option; Rpg applies it on the first join).

const MAIN := 3
const SECOND := 1
const BUY_COST := 1  # Proposed
const BUY_CAP := 5  # Proposed: no line bought past 5 at creation

## id -> {name, lines {line: levels}, line (who they were)}.
const ALL := {
	"nurse": {"name": "Nurse", "lines": {"medical": MAIN, "cooking": SECOND}, "line": "Twelve-hour shifts on a ward that filled up in a week."},
	"paramedic": {"name": "Paramedic", "lines": {"medical": MAIN, "driving": SECOND}, "line": "Drove into it every day until the radio stopped."},
	"carpenter": {"name": "Carpenter", "lines": {"building": MAIN, "fitness": SECOND}, "line": "Framed houses; now boards them up."},
	"electrician": {"name": "Electrician", "lines": {"building": MAIN, "mechanics": SECOND}, "line": "Knows which wire was live."},
	"mechanic": {"name": "Mechanic", "lines": {"mechanics": MAIN, "driving": SECOND}, "line": "Ran a garage off the highway."},
	"soldier": {"name": "Soldier", "lines": {"firearms": MAIN, "fitness": SECOND}, "line": "Reserve infantry; the unit never mustered."},
	"hunter": {"name": "Hunter", "lines": {"archery": MAIN, "fieldcraft": SECOND}, "line": "Bow season every autumn since he was twelve."},
	"farmer": {"name": "Farmer", "lines": {"fieldcraft": MAIN, "cooking": SECOND}, "line": "The land goes on whoever is left."},
	"chef": {"name": "Chef", "lines": {"cooking": MAIN, "melee": SECOND}, "line": "A knife hand from a hot kitchen."},
	"police": {"name": "Police officer", "lines": {"firearms": MAIN, "melee": SECOND}, "line": "Held the line at the hospital until there was no line."},
	"athlete": {"name": "Athlete", "lines": {"fitness": MAIN, "stealth": SECOND}, "line": "Ran the marathon in spring; runs for real now."},
	"burglar": {"name": "Burglar", "lines": {"stealth": MAIN, "scavenging": SECOND}, "line": "Other people's houses were always the job."},
	"doctor": {"name": "Doctor", "lines": {"medical": 4, "fitness": -1}, "line": "A GP; the clinic was the first place to fall."},
	"teacher": {"name": "Teacher", "lines": {"scavenging": SECOND}, "perk": "people_person", "line": "Thirty kids a class; patience is a skill. (Teaching bonus: later.)"},
	"farm_kid": {"name": "Grew up on a farm", "lines": {"fieldcraft": MAIN, "fitness": SECOND}, "line": "Chores before school, animals before people."},
}

## id -> {name, points, text, fx (wired now), later: true (recorded for its system)}.
const FLAWS := {
	"smoker": {"name": "Smoker", "points": 2, "text": "Starts hooked on tobacco: a smoke settles the nerves, going without brings the shakes (Addictions)", "fx": {"habit": "tobacco"}},
	"bad_knee": {"name": "Bad knee", "points": 2, "text": "Moves 7% slower", "fx": {"speed": 0.93}},
	"short_sighted": {"name": "Short-sighted", "points": 2, "text": "Sees less far without glasses", "fx": {"sight": 0.7}, "later": true},
	"hard_of_hearing": {"name": "Hard of hearing", "points": 2, "text": "Hears the dead later", "fx": {"hearing": 0.7}, "later": true},
	"asthma": {"name": "Asthma", "points": 2, "text": "Stamina runs out sooner", "fx": {"stamina": 0.85}, "later": true},
	"weak_stomach": {"name": "Weak stomach", "points": 1, "text": "Raw or spoiled food makes him sick more", "fx": {"raw_risk": 1.5}, "later": true},
	"coward": {"name": "Coward", "points": 2, "text": "Courage down; refuses more; every shock shakes the nerve a third harder (Nerve)", "later": true},
	"hot_headed": {"name": "Hot-headed", "points": 1, "text": "Rage breaks", "later": true},
	"heavy_sleeper": {"name": "Heavy sleeper", "points": 1, "text": "Never wakes to the ring", "fx": {"heavy_sleeper": true}},
	"clumsy": {"name": "Clumsy", "points": 2, "text": "Louder on his feet", "fx": {"step_noise": 1.2}},
	"slow_learner": {"name": "Slow learner", "points": 3, "text": "XP x0.8 in every line", "fx": {"xp": 0.8}},
	"thin_skinned": {"name": "Thin-skinned", "points": 2, "text": "The cold gets in 30% faster", "fx": {"cold": 1.3}},
	"drinker": {"name": "A drinker", "points": 2, "text": "Starts hooked on drink: a drink settles the nerves, going without brings the shakes (Addictions)", "fx": {"habit": "alcohol"}},
	"insomniac": {"name": "Insomniac", "points": 2, "text": "Sleep restores less", "later": true},
	"allergic": {"name": "Allergic", "points": 1, "text": "Certain foods make him ill", "later": true},
}


static func blank() -> Dictionary:
	return {"background": "", "flaws": [], "buys": {}}


## The points `flaws` give.
static func points(flaws: Array) -> int:
	var n := 0
	for f: String in flaws:
		n += int((FLAWS.get(f, {}) as Dictionary).get("points", 0))
	return n


## The points `buys` (line -> levels) cost.
static func cost(buys: Dictionary) -> int:
	var n := 0
	for line: String in buys:
		n += maxi(0, int(buys[line])) * BUY_COST
	return n


## Line -> starting level for `choice`: the background's lines plus the bought levels (a bought
## line stops at BUY_CAP).
static func start_levels(choice: Dictionary) -> Dictionary:
	var out := {}
	var bg: Dictionary = ALL.get(String(choice.get("background", "")), {})
	var lines: Dictionary = bg.get("lines", {})
	for line: String in lines:
		out[line] = maxi(0, int(lines[line]))
	var buys: Dictionary = choice.get("buys", {})
	for line: String in buys:
		if line in RpgLines.LINES and int(buys[line]) > 0:
			var base := int(out.get(line, 0))
			out[line] = maxi(base, mini(base + int(buys[line]), BUY_CAP))
	return out


## "" if `choice` is a valid creation, else why not.
static func problem(choice: Dictionary) -> String:
	var bg := String(choice.get("background", ""))
	if bg != "" and not ALL.has(bg):
		return "No background %s" % bg
	for f: String in choice.get("flaws", []):
		if not FLAWS.has(f):
			return "No flaw %s" % f
	var buys: Dictionary = choice.get("buys", {})
	for line: String in buys:
		if not line in RpgLines.LINES:
			return "No line %s" % line
	if cost(buys) > points(choice.get("flaws", [])):
		return "The flaws give %d points; the levels cost %d" % [points(choice.get("flaws", [])), cost(buys)]
	return ""


## The product of flaw effect `key` over `flaws` (1 when none has it).
static func fx(flaws: Array, key: String) -> float:
	var out := 1.0
	for f: String in flaws:
		var e: Dictionary = (FLAWS.get(f, {}) as Dictionary).get("fx", {})
		if e.has(key) and typeof(e[key]) in [TYPE_FLOAT, TYPE_INT]:
			out *= float(e[key])
	return out


static func has_flag(flaws: Array, key: String) -> bool:
	for f: String in flaws:
		if bool(((FLAWS.get(f, {}) as Dictionary).get("fx", {}) as Dictionary).get(key, false)):
			return true
	return false
