class_name Addictions
extends RefCounted
## Addictions and withdrawal (call 118; docs/survival_mind.md section 3): painkillers, alcohol,
## tobacco and stimulants give real relief (nerve up; a stimulant's sleep up; the painkiller's own
## drug eases pain) and raise a habit (0-100) by kind, kept in the body's Dictionary as "habits":
## {kind: {"habit", "since_h" (world hours since the last dose), "w" (withdrawal 0..1)}}. Past
## a kind's line, going AFTER_H without a dose brings withdrawal: tremors (aim sway), nerve worn
## down, slower work and stamina, moodlets; the habit falls faster while it lasts, so it eases
## over days and ends under the line. The smoker and drinker flaws (and traits) start with a habit.
## Static and pure.

const KEY := "habits"
## Proposed: gain a dose (times the item's own mult), the line, hours to withdrawal, the relief a
## dose gives the nerve, the habit's fall a world day clean and in withdrawal, sleep a dose.
const KINDS := {
	"tobacco": {"name": "tobacco", "gain": 6.0, "line": 30.0, "after_h": 10.0, "nerve": 10.0, "decay": 3.0, "wd_decay": 8.0, "sleep": 0.0,
		"start": "Your hands won't settle: you need a smoke", "word": "craving a smoke"},
	"alcohol": {"name": "drink", "gain": 8.0, "line": 35.0, "after_h": 20.0, "nerve": 15.0, "decay": 3.0, "wd_decay": 8.0, "sleep": 0.0,
		"start": "The shakes: you need a drink", "word": "the shakes, needs a drink"},
	"painkillers": {"name": "painkillers", "gain": 10.0, "line": 35.0, "after_h": 18.0, "nerve": 6.0, "decay": 3.0, "wd_decay": 8.0, "sleep": 0.0,
		"start": "Everything aches and sweats: you want the pills", "word": "sick for the pills"},
	"stimulants": {"name": "stimulants", "gain": 7.0, "line": 30.0, "after_h": 16.0, "nerve": -2.0, "decay": 3.0, "wd_decay": 8.0, "sleep": 15.0,
		"start": "Heavy, slow, flat: the pills wore off for good", "word": "crashing without pills"},
}
## Items without their own stats.mind: [kind, gain mult] (morphine through Body.on_treated).
const ITEM_KINDS := {"ibuprofen": ["painkillers", 0.3], "caffeine_pills": ["stimulants", 0.5], "energy_drink": ["stimulants", 0.3],
	"morphine": ["painkillers", 2.0]}
## The flaws and traits that start with a habit, and how much.
const START_HABITS := {"smoker": ["tobacco", 55.0], "drinker": ["alcohol", 55.0]}
## Withdrawal's effects at w = 1.
const SWAY := 0.5
const STAMINA := 0.25
const WORK := 0.3
const NERVE_H := 2.0


static func habits(n: Dictionary) -> Dictionary:
	if not n.get(KEY) is Dictionary:
		n[KEY] = {}
	return n[KEY]


static func habit(n: Dictionary, kind: String) -> float:
	return float((habits(n).get(kind, {}) as Dictionary).get("habit", 0.0))


static func withdrawal(n: Dictionary, kind: String) -> float:
	return float((habits(n).get(kind, {}) as Dictionary).get("w", 0.0))


## The worst withdrawal on `n` (0 none).
static func worst(n: Dictionary) -> float:
	if not n.get(KEY) is Dictionary:
		return 0.0
	var w := 0.0
	for k: String in n[KEY]:
		w = maxf(w, float((n[KEY][k] as Dictionary).get("w", 0.0)))
	return w


static func _rec(n: Dictionary, kind: String) -> Dictionary:
	var h := habits(n)
	if not h.has(kind):
		h[kind] = {"habit": 0.0, "since_h": 0.0, "w": 0.0}
	return h[kind]


## The kind and gain mult `item` feeds ([] for none): its stats' "mind" {"habit", "gain"}, else
## ITEM_KINDS.
static func kind_of(item: ItemData) -> Array:
	if item == null:
		return []
	var m: Variant = item.stats.get("mind", {})
	if m is Dictionary and (m as Dictionary).has("habit"):
		return [String(m.habit), float((m as Dictionary).get("gain", 1.0))]
	return ITEM_KINDS.get(String(item.id), [])


## A dose of `kind` (`mult` of its gain): relief now (nerve, a stimulant's sleep), the habit up,
## withdrawal gone. Returns the nerve relief given.
static func dose(n: Dictionary, kind: String, mult := 1.0) -> float:
	var k: Dictionary = KINDS.get(kind, {})
	if k.is_empty():
		return 0.0
	var r := _rec(n, kind)
	r.habit = minf(100.0, float(r.habit) + float(k.gain) * mult)
	r.since_h = 0.0
	r.w = 0.0
	var relief := float(k.nerve) * clampf(mult, 0.3, 1.0)
	Nerve.settle(n, relief)
	if float(k.sleep) > 0.0:
		n["sleep"] = minf(100.0, float(n.get("sleep", 100.0)) + float(k.sleep) * clampf(mult, 0.3, 1.0))
	return relief


## Starts a habit at `level` (a flaw's, a trait's).
static func start_habit(n: Dictionary, kind: String, level: float) -> void:
	var r := _rec(n, kind)
	r.habit = maxf(float(r.habit), level)
	r.since_h = 0.0


## `world_h` world hours: each habit's clock runs; past the line and AFTER_H without a dose,
## withdrawal (w by how far over the line); the habit falls (faster in withdrawal). Returns the
## kinds whose withdrawal just started.
static func step(n: Dictionary, world_h: float) -> Array:
	var started: Array = []
	if world_h <= 0.0 or not n.get(KEY) is Dictionary:
		return started
	for kind: String in n[KEY]:
		var k: Dictionary = KINDS.get(kind, {})
		if k.is_empty():
			continue
		var r: Dictionary = n[KEY][kind]
		r.since_h = float(r.since_h) + world_h
		var was := float(r.get("w", 0.0))
		var line := float(k.line)
		if float(r.habit) >= line and float(r.since_h) >= float(k.after_h):
			r.habit = maxf(0.0, float(r.habit) - float(k.wd_decay) * world_h / 24.0)
			r.w = clampf(0.25 + (float(r.habit) - line) / 40.0, 0.25, 1.0) if float(r.habit) >= line else 0.0
			if was <= 0.0 and float(r.w) > 0.0:
				started.append(kind)
		else:
			r.w = 0.0
			if float(r.since_h) >= float(k.after_h):
				r.habit = maxf(0.0, float(r.habit) - float(k.decay) * world_h / 24.0)
	return started


## The habits in words for the body and character screens: ["a smoker (craving a smoke)"].
static func words(n: Dictionary) -> Array:
	var out: Array = []
	if not n.get(KEY) is Dictionary:
		return out
	for kind: String in n[KEY]:
		var k: Dictionary = KINDS.get(kind, {})
		var r: Dictionary = n[KEY][kind]
		if k.is_empty() or float(r.get("habit", 0.0)) < float(k.line) * 0.5:
			continue
		var hooked := float(r.habit) >= float(k.line)
		var w := "%s: %s" % [String(k.name), "hooked" if hooked else "a habit"]
		if float(r.get("w", 0.0)) > 0.0:
			w += " (%s)" % String(k.word)
		out.append(w)
	return out
