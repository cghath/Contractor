class_name Dreams
extends RefCounted
## Dreams (call 119; docs/survival_mind.md section 4): the day leaves marks on a survivor (a horde
## seen, a loss, a kindness, hunger, a bite, a kill: "marks" in the body's Dictionary, world hours),
## and on waking from sleep a short dream line coloured by the strongest of them (the "dreams"
## section of data/survival_lines.json, else LINES). A death in the last NIGHTMARE_DAYS (or nerve
## breaking) makes the night a nightmare: falling asleep sets "nightmare", and sleep then restores
## the sleep store and the nerve at NIGHTMARE_RESTORE (restore_mult, read by Needs.step and
## Nerve.step); waking from one costs a little nerve and is written in the journal.

const MARKS_KEY := "marks"
const MARK_CAP := 12
## Marks older than this (world hours) don't colour a dream.
const MARK_H := 30.0
const NIGHTMARE_DAYS := 3.0
const NIGHTMARE_RESTORE := 0.5
## The day's colour by weight: the heaviest mark wins.
const WEIGHT := {"friend_died": 10, "companion_died": 9, "loss": 9, "ate_human": 9, "butchered": 9, "bite": 8, "killed_person": 7,
	"horde": 6, "scream": 5, "close_call": 5, "hunger": 4, "no_sleep": 3, "kindness": 2}
## Which dream a mark colours.
const KIND_OF := {"friend_died": "loss", "companion_died": "loss", "loss": "loss", "ate_human": "dark", "butchered": "dark",
	"bite": "bite", "killed_person": "killed", "horde": "horde", "scream": "horde", "close_call": "horde", "hunger": "hunger",
	"no_sleep": "calm", "kindness": "kindness"}
const LOSS_MARKS: Array[String] = ["friend_died", "companion_died", "loss"]
## Fallback lines (the JSON's "dreams" section overrides them).
const LINES := {
	"calm": ["You dreamt of nothing. It was good."],
	"horde": ["You dreamt of a crowd walking past the window, all night, and none of them looked in."],
	"loss": ["You dreamt they were still here, laughing at something you said."],
	"kindness": ["You dreamt of a warm kitchen and somebody calling you in."],
	"hunger": ["You dreamt of bread, and woke chewing."],
	"bite": ["You dreamt your arm was someone else's."],
	"killed": ["You dreamt of a face. You didn't know it then either."],
	"dark": ["You dreamt of a table laid for a feast, and you knew what was on it."],
	"nightmare": ["You woke screaming. You don't remember why; your hands do."],
}
const LINES_PATH := "res://data/survival_lines.json"

static var _lines: Dictionary = {}


static func lines() -> Dictionary:
	if _lines.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		var d: Variant = (parsed as Dictionary).get("dreams", {}) if parsed is Dictionary else {}
		_lines = d if d is Dictionary and not (d as Dictionary).is_empty() else LINES
	return _lines


## Remembers `kind` happened to `n` now (Nerve.shake marks every shake).
static func mark(n: Dictionary, kind: String) -> void:
	if not WEIGHT.has(kind):
		return
	var list: Array = n.get(MARKS_KEY, [])
	list.append({"k": kind, "h": Moods.now_h()})
	n[MARKS_KEY] = list.slice(-MARK_CAP)


static func _recent(n: Dictionary, within_h: float) -> Array:
	var now := Moods.now_h()
	return (n.get(MARKS_KEY, []) as Array).filter(func(m: Dictionary) -> bool: return now - float(m.get("h", -1000.0)) <= within_h)


## The day's colour: the heaviest recent mark's dream kind (hunger counts when hungry now), or
## "calm".
static func colour(n: Dictionary) -> String:
	var best := ""
	var best_w := 0
	for m: Dictionary in _recent(n, MARK_H):
		var w := int(WEIGHT.get(String(m.k), 0))
		if w > best_w:
			best_w = w
			best = String(m.k)
	if best_w < int(WEIGHT.hunger) and float(n.get("hunger", 100.0)) < 35.0:
		best = "hunger"
	return String(KIND_OF.get(best, "calm"))


## Whether tonight is a nightmare: a death within NIGHTMARE_DAYS, or nerve breaking.
static func nightmare_due(n: Dictionary) -> bool:
	for m: Dictionary in _recent(n, NIGHTMARE_DAYS * 24.0):
		if String(m.k) in LOSS_MARKS:
			return true
	return Nerve.level_of(n) >= 3


## Falling asleep (SurvivalSleep.start): tonight's kind is set.
static func on_sleep(n: Dictionary) -> void:
	n["nightmare"] = nightmare_due(n)


## Sleep's restore this night (Needs.step's sleep store, Nerve.step): cut by a nightmare.
static func restore_mult(n: Dictionary) -> float:
	return NIGHTMARE_RESTORE if bool(n.get("nightmare", false)) else 1.0


## Waking (SurvivalSleep.wake, while still asleep): the dream line into "dream" (the waker is
## told it: Survival._wake, take_line), a nightmare costs nerve and goes in the journal. Returns
## the line.
static func on_wake(n: Dictionary) -> String:
	var kind := "nightmare" if bool(n.get("nightmare", false)) else colour(n)
	var pool: Array = lines().get(kind, LINES.get(kind, LINES.calm))
	if pool.is_empty():
		pool = LINES.calm
	var line := String(pool[absi(hash([kind, Survival.day(), int(Moods.now_h())])) % pool.size()])
	n["dream"] = line
	n["dream_kind"] = kind
	n.erase("nightmare")
	if kind == "nightmare":
		Nerve.set_value(n, Nerve.value(n) - float(Nerve.SHAKE.nightmare))
	else:
		Nerve.settle(n, 3.0)
	return line


## The dream line waiting to be told (once), or "".
static func take_line(n: Dictionary) -> String:
	var line := String(n.get("dream", ""))
	n.erase("dream")
	return line
