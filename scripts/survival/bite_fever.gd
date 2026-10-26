class_name BiteFever
extends RefCounted
## The bite's fever clock (docs/survival_medical.md section 3, calls 10, 15, 46, 80): a zombie's
## bite (Melee's "bite" hit, Body.on_bitten) on a non-immune Person starts a clock a world week
## long (the "needs" world option scales it, as it scales the body's time): incubation (day 1,
## hidden), fever (days 2-4: stamina return slower, thirst faster, the core up; companions
## notice), delirium (days 5-6: vision sways, aim worse, senses dulled; they say odd things),
## collapse (day 7: down, dead, and risen as one of the dead in their kit within minutes, unless
## the head is destroyed; a player's survivor is gone for good: Survival.server_player_died).
## An antibiotic course slows it (a world day's pause over the course's five), rest in a bed with
## good food x0.7, a doctor's care (a treatment by medical 5+: Body.on_treated) x0.5; the serum
## (Cure.server_apply) cures it before collapse; the immune never turn (the clock runs out and
## they learn they're immune). State: the body's Dictionary "bite": {"h" (world hours on the
## clock), "day" (the world day of the bite), "immune", "seen" (the last stage told),
## "collapsed"}.

const STAGES: Array[String] = ["incubation", "fever", "delirium", "collapse"]
## Proposed (call 80): the stage boundaries in world hours (day 1, days 2-4, days 5-6, day 7).
const FEVER_AT_H := 24.0
const DELIRIUM_AT_H := 96.0
const COLLAPSE_AT_H := 144.0
const WEEK_H := 168.0
## The slowers (call 46): a course (its five days pause one: x0.8 while it covers), rest in a bed
## with good food, a doctor's care.
const ABX_MULT := 0.8
const REST_MULT := 0.7
const DOCTOR_MULT := 0.5
const GOOD_FOOD_KCAL := 1250.0
const GOOD_FOOD_PROTEIN := 40.0
## A doctor's care lasts this long after the treatment (world hours).
const DOCTOR_CARE_H := 24.0
const DOCTOR_LEVEL := 5
## Effects by stage: stamina return's share, extra water a world day (litres), the core held,
## aim sway added, senses dulled (Needs.dulled), the vision sway (the camera can read it).
const EFFECTS := {
	1: {"stamina": 0.75, "water": 0.8, "fever": 38.3, "sway": 0.2, "dulled": 0.0, "vision": 0.0},
	2: {"stamina": 0.6, "water": 1.0, "fever": 38.8, "sway": 0.6, "dulled": 0.6, "vision": 1.0},
}
const LINES := {
	"fever": ["You're burning up.", "You're sweating buckets. Sit a minute.", "You look grey. That bite?"],
	"delirium": ["You're not making sense. Sit down.", "Stay with me. Look at me.", "We need the serum. Now."],
	"odd": ["Who turned the sky off?", "My hands are somebody else's.", "Can you hear them singing?", "The radio's in my teeth."],
}
## Proposed: real seconds from collapse to rising ("within minutes").
static var rise_s := 90.0


static func clock(n: Dictionary) -> Dictionary:
	return n.get("bite", {}) if n.get("bite") is Dictionary else {}


## Whether a bite's clock runs on `n` (an immune one's too, until it runs out).
static func bitten(n: Dictionary) -> bool:
	return not clock(n).is_empty()


## The stage (0 incubation .. 3 collapse; -1 not bitten). An immune body stays at 0.
static func stage(n: Dictionary) -> int:
	var c := clock(n)
	if c.is_empty():
		return -1
	if bool(c.get("immune", false)):
		return 0
	var h := float(c.get("h", 0.0))
	return 3 if h >= COLLAPSE_AT_H else (2 if h >= DELIRIUM_AT_H else (1 if h >= FEVER_AT_H else 0))


static func stage_name(n: Dictionary) -> String:
	var st := stage(n)
	return STAGES[st] if st >= 0 else ""


## World hours to collapse at the clock's own pace (INF immune or not bitten).
static func hours_left(n: Dictionary) -> float:
	var c := clock(n)
	if c.is_empty() or bool(c.get("immune", false)):
		return INF
	return maxf(0.0, COLLAPSE_AT_H - float(c.get("h", 0.0)))


## The bite: starts the clock on `n` (nothing when it already runs). `immune`: it will run out.
static func start(n: Dictionary, immune := false, day := 0) -> bool:
	if bitten(n):
		return false
	n["bite"] = {"h": 0.0, "day": day, "immune": immune, "seen": 0, "collapsed": false}
	return true


## The clock's pace now (1 the week's own), from the body and `ctx` ("abx", "rest").
static func pace(n: Dictionary, ctx := {}) -> float:
	var p := 1.0
	if bool(ctx.get("abx", Infection.covered(n))):
		p *= ABX_MULT
	var rest := bool(ctx.get("rest", String(n.get("asleep", "")) == "bed"))
	if rest and float(n.get("calories", 0.0)) >= GOOD_FOOD_KCAL and float(n.get("protein", 0.0)) >= GOOD_FOOD_PROTEIN:
		p *= REST_MULT
	if float(n.get("care_h", 0.0)) > 0.0:
		p *= DOCTOR_MULT
	return p


## `world_h` world hours of the clock on `n`. Returns what happened: "" nothing new, "fever",
## "delirium", "collapse", or "immune" (the clock ran out on an immune body: it's gone, and they know).
static func step(n: Dictionary, world_h: float, ctx := {}) -> String:
	var c := clock(n)
	if c.is_empty() or bool(c.get("collapsed", false)) or world_h <= 0.0:
		return ""
	c.h = float(c.get("h", 0.0)) + world_h * pace(n, ctx)
	if bool(c.get("immune", false)):
		if float(c.h) >= WEEK_H:
			n.erase("bite")
			n["immune_known"] = true
			return "immune"
		return ""
	var st := stage(n)
	if st > int(c.get("seen", 0)):
		c.seen = st
		return STAGES[st]
	return ""


## The serum (or a test): the clock gone, unless it already collapsed. Returns whether it cured.
static func cure(n: Dictionary) -> bool:
	var c := clock(n)
	if c.is_empty() or bool(c.get("collapsed", false)):
		return false
	n.erase("bite")
	return true


## The stage's effects on `n` ({} at incubation, immune or not bitten).
static func effects(n: Dictionary) -> Dictionary:
	var st := stage(n)
	return EFFECTS.get(mini(st, 2), {}) if st >= 1 else {}


# --- Host -------------------------------------------------------------------------------------

## Host: day 7 on `s`: down and dead, and up again as one of the dead in their kit within
## rise_s seconds. A companion or settler rises through their record (SurvivorsLayer, killed by
## the dead); a player's survivor dies for good (Survival.server_player_died: the kit goes with the
## risen, not the ground) and the risen one is his old self; anyone else rises where they fell
## unless the head is gone (meta "head_destroyed").
static func server_collapse(s: Soldier) -> void:
	if s == null or not is_instance_valid(s) or s.vitals.is_dead():
		return
	var n := Survival.needs_of(s)
	var c := clock(n)
	if not c.is_empty():
		c.collapsed = true
	var layer := SurvivorsLayer.find(s)
	var rec := layer.record_of(s) if layer else {}
	var who := Survival.survivor_name(s) if not s.is_ai() else (String(rec.get("name", "")) if not rec.is_empty() else s.log_name())
	Survival._journal_line("%s collapsed from the bite's fever." % who)
	s.vitals.last_cause = {"cause": "the bite's fever"}
	s.set_meta(&"killed_by_dead", true)
	if not rec.is_empty():
		for other_id: String in SurvivorsLayer.records().keys():
			var o: Dictionary = SurvivorsLayer.records()[other_id]
			if other_id != String(rec.get("id", "")) and String(o.get("status", "")) in ["companion", "settler"] and bool(rec.get("bite_kept", false)):
				Moods.add(o, "lost_to_bite:" + String(rec.id), -8.0, 72.0)
		s.vitals.server_kill()  # the layer's _on_died: rise_at, and _check_rise brings them up
		return
	var level := CompoundLevel.current(s)
	var at := s.global_position
	var entries: Array = []
	if not s.is_ai():
		entries.assign(s.inventory.strip())
	s.vitals.server_kill()
	if level == null:
		return
	var body: Soldier = s if s.is_ai() else null
	var timer := s.get_tree().create_timer(rise_s)
	timer.timeout.connect(func() -> void: _rise(level, at, entries, who, body))


static func _rise(level: CompoundLevel, at: Vector3, entries: Array, who: String, body: Soldier) -> void:
	if not is_instance_valid(level) or not level.is_inside_tree():
		return
	if body != null and is_instance_valid(body):
		if bool(body.get_meta(&"head_destroyed", false)):
			return
		for e: Dictionary in body.inventory.strip():
			entries.append(e)
		at = body.global_position
		body.queue_free()
	var z := Survival.server_spawn_zombie(level, at, "walker")
	if z == null:
		return
	for e: Dictionary in entries:
		z.inventory.take(StringName(String(e.id)), int(e.get("count", 1)), e.get("state", {}))
	z.person_name = who
	z.set_meta(&"risen_from_bite", who)
	Survival._journal_line("%s rose." % who)


## A companion on the clock: the player's choice (call 46): "send_away" (they leave on their own,
## the clock with them; the group's mood a little down), "keep" (treat them: the group's mood
## follows how it ends), "put_down" (a heavy moodlet, worse for friends; no rise: the head).
## Returns why not ("" done).
static func server_choice(layer: SurvivorsLayer, rec: Dictionary, choice: String) -> String:
	if layer == null or rec.is_empty():
		return "Nobody to decide on"
	var n: Dictionary = rec.get("needs", {})
	if not bitten(n):
		return "%s isn't bitten" % String(rec.get("name", "They"))
	var id := String(rec.get("id", ""))
	match choice:
		"send_away":
			_group_mood(layer, rec, "sent_away_bitten:" + id, -3.0, -3.0, 48.0)
			rec["bite_away"] = true
			layer.server_desert(rec)
			Survival._journal_line("%s walked off alone with the bite." % String(rec.get("name", "")))
		"keep":
			rec["bite_kept"] = true
		"put_down":
			_group_mood(layer, rec, "put_down_bitten:" + id, -12.0, -18.0, 96.0)
			var body := layer.body_of(id)
			if body:
				body.set_meta(&"head_destroyed", true)
				body.vitals.last_cause = {"cause": "put down before the turn"}
				body.vitals.server_kill()
			rec["put_down"] = true
			rec["rise_at"] = 0.0
			Survival._journal_line("We put %s down before the fever finished." % String(rec.get("name", "")))
		_:
			return "No such choice"
	return ""


## The serum saved a kept companion: the group's mood lifts.
static func on_cured(layer: SurvivorsLayer, rec: Dictionary) -> void:
	if layer and bool(rec.get("bite_kept", false)):
		_group_mood(layer, rec, "saved_from_bite:" + String(rec.get("id", "")), 6.0, 10.0, 72.0)
	Moods.remove(rec, "bitten")


static func _group_mood(layer: SurvivorsLayer, rec: Dictionary, cause: String, value: float, friend_value: float, hours: float) -> void:
	var id := String(rec.get("id", ""))
	for other_id: String in SurvivorsLayer.records().keys():
		var o: Dictionary = SurvivorsLayer.records()[other_id]
		if other_id == id or not String(o.get("status", "")) in ["companion", "settler"]:
			continue
		var friend := SurvivorPerson.relation(o, id) >= SurvivorsLayer.FRIEND_AT
		Moods.add(o, cause, friend_value if friend else value, hours)
