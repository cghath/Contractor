class_name Mind
extends RefCounted
## The survivor's mind (calls 116-119; docs/survival_mind.md): the glue between the body's step
## and the mind's parts: the nerve (Nerve), addictions and withdrawal (Addictions), the prion
## sickness from human flesh (Cannibalism), dreams (Dreams). Needs.server_step calls server_step
## after the body's; Needs' effects read sway_add, dulled_add and stamina_factor; Survival.server_eat
## calls server_on_used for every item eaten, drunk or taken; Needs.respawn calls reset. Everything
## lives in the body's Dictionary (a player's and a companion's alike) and is saved with it.

## The keys reset() clears for a new survivor.
const KEYS: Array[String] = [Nerve.KEY, Addictions.KEY, Dreams.MARKS_KEY, "prion", "ate_human", "safe_h", "no_sleep_mark_h",
	"nightmare", "dream", "dream_kind", "horde_h", "screams", "mind_init", "_prion_line"]
## Proposed: a horde in the zone shakes again only after this many world hours.
const HORDE_EVERY_H := 12.0
## The prion's tremor and fog at the end.
const PRION_SWAY := 1.0
const PRION_DULLED := 0.6
## Companions' moodlets while it holds: shaken (nerve 35-), breaking (15-), withdrawal.


## A new survivor's mind: none of it carried over.
static func reset(n: Dictionary) -> void:
	for k: String in KEYS:
		n.erase(k)


# --- Effects (Needs reads these) ----------------------------------------------------------

static func sway_add(n: Dictionary) -> float:
	return Nerve.SWAY * Nerve.shake01(n) + Addictions.SWAY * Addictions.worst(n) + PRION_SWAY * Cannibalism.prion_share(n)


static func dulled_add(n: Dictionary) -> float:
	return clampf(Nerve.DULLED * Nerve.shake01(n) + PRION_DULLED * Cannibalism.prion_share(n), 0.0, 1.0)


static func stamina_factor(n: Dictionary) -> float:
	return (1.0 - Nerve.STAMINA * Nerve.shake01(n)) * (1.0 - Addictions.STAMINA * Addictions.worst(n))


## How fast hands work (crafting, building, looting can read it): withdrawal slows them.
static func work_mult(n: Dictionary) -> float:
	return 1.0 - Addictions.WORK * Addictions.worst(n)


# --- Who --------------------------------------------------------------------------------------

## The traits that shape `s`'s mind: a companion's record's, a player's survivor's (voice trait)
## and his flaws (coward, smoker, drinker, hot-headed).
static func traits_of(s: Soldier) -> Array:
	if s == null or not is_instance_valid(s):
		return []
	if s.is_ai():
		var layer := SurvivorsLayer.find(s)
		var rec := layer.record_of(s) if layer else {}
		return (rec.get("traits", []) as Array).duplicate()
	if not Survival.running:
		return []
	var out := JournalVoice.traits_of_record(Survival.survivor_of(s))
	for f: String in Rpg.view(s).get("flaws", []):
		if not f in out:
			out.append(f)
	return out


## A companion's record, or {}.
static func record_of(s: Soldier) -> Dictionary:
	if s == null or not s.is_ai():
		return {}
	var layer := SurvivorsLayer.find(s)
	return layer.record_of(s) if layer else {}


# --- Stepping ---------------------------------------------------------------------------------

## `world_h` world hours of `n`'s mind (pure): the habits' clocks (withdrawal wears the nerve),
## the prion, the nerve's settling and wearing. `ctx`: "safe", "horde" (a horde in the zone).
## Returns what happened: {"withdrawal": [kinds started], "prion": "" | "onset" | "memory" | "death",
## "horde": bool (it shook)}.
static func step(n: Dictionary, world_h: float, ctx: Dictionary, traits: Array = []) -> Dictionary:
	var out := {"withdrawal": [], "prion": "", "horde": false}
	if world_h <= 0.0:
		return out
	if not bool(n.get("mind_init", false)):
		n["mind_init"] = true
		for t: String in traits:
			if Addictions.START_HABITS.has(t):
				var sh: Array = Addictions.START_HABITS[t]
				Addictions.start_habit(n, String(sh[0]), float(sh[1]))
	n["horde_h"] = maxf(0.0, float(n.get("horde_h", 0.0)) - world_h)
	if bool(ctx.get("horde", false)) and float(n.horde_h) <= 0.0:
		Nerve.shake(n, "horde", traits)
		n.horde_h = HORDE_EVERY_H
		out.horde = true
	out.withdrawal = Addictions.step(n, world_h)
	out.prion = Cannibalism.prion_step(n, world_h)
	var wear := Addictions.NERVE_H * Addictions.worst(n) + 1.0 * Cannibalism.prion_share(n)
	Nerve.step(n, world_h, {"safe": bool(ctx.get("safe", false)), "wear": wear})
	return out


## Host: `world_h` world hours of `s`'s mind (Needs.server_step, after the body): the zone read
## (safe at the settlement, a horde, a screamer near), the step, and what it tells: withdrawal
## starting, the prion's lines and its end; a companion's moodlets.
static func server_step(s: Soldier, n: Dictionary, world_h: float, _ctx: Dictionary) -> void:
	if world_h <= 0.0 or s == null or s.vitals == null or s.vitals.is_dead() or s.vitals.undead:
		return
	var level: CompoundLevel = CompoundLevel.current(s) if s.is_inside_tree() else null
	var ctx := {"safe": _safe(s, level), "horde": false}
	if level:
		var crowd := ZoneDead.of(level)
		ctx.horde = crowd != null and crowd.horde_count() > 0
		_screams(s, n, level)
	var res := step(n, world_h, ctx, traits_of(s))
	for kind: String in res.withdrawal:
		Survival._tell(s, String((Addictions.KINDS[kind] as Dictionary).start))
	match String(res.prion):
		"onset":
			Survival._tell(s, "Your hands tremble and won't stop")
		"memory":
			Survival._tell(s, String(n.get("_prion_line", "")))
			Survival._journal_line(String(n.get("_prion_line", "")))
			n.erase("_prion_line")
		"death":
			Survival._journal_line("%s wasted away: the shaking sickness." % Body._name_of(s))
			s.vitals.last_cause = {"cause": "wasting"}
			s.vitals.server_kill()
			return
	var rec := record_of(s)
	if not rec.is_empty():
		person_moodlets(rec, n)


## Safe: at the settlement (its zone, inside its radius) with none of the dead within
## Nerve.SAFE_DEAD_M.
static func _safe(s: Soldier, level: CompoundLevel) -> bool:
	if level == null or not Settlement.exists() or Settlement.zone() != String(Survival.state().get("zone", "")):
		return false
	if s.global_position.distance_to(Settlement.pos()) > Settlement.radius():
		return false
	for z: Soldier in Survival.zombies(level):
		if z.vitals.is_up() and z.global_position.distance_to(s.global_position) <= Nerve.SAFE_DEAD_M:
			return false
	return true


## A screamer's scream (ZombieAI's "zombie_scream" meta) within Nerve.SCREAM_M: a close call, once a scream.
static func _screams(s: Soldier, n: Dictionary, level: CompoundLevel) -> void:
	var heard: Array = n.get("screams", [])
	for z: Soldier in Survival.zombies(level):
		if not z.has_meta(&"zombie_scream") or z.global_position.distance_to(s.global_position) > Nerve.SCREAM_M:
			continue
		var key := str(z.get_instance_id())
		if key in heard:
			continue
		heard.append(key)
		Nerve.shake(n, "scream", traits_of(s))
	n["screams"] = heard.slice(-8)


## A person's mind in their moods: shaken or breaking, in withdrawal.
static func person_moodlets(rec: Dictionary, n: Dictionary) -> void:
	var lv := Nerve.level_of(n) if n.has(Nerve.KEY) else 0
	Moods.hold(rec, "nerve_broken", lv >= 3)
	Moods.hold(rec, "shaken", lv == 2)
	Moods.hold(rec, "withdrawal", Addictions.worst(n) > 0.0)


## Host, every world hour (SurvivorsLayer.server_hour) for a companion or settler `rec`: a settler
## (stepped by the settlement, not a body) gets the mind's hour here, safe at home; everyone's
## moodlets follow their nerve.
static func person_hour(rec: Dictionary, horde: bool) -> void:
	var n: Dictionary = rec.get("needs", {})
	if n.is_empty():
		return
	if String(rec.get("status", "")) == "settler":
		step(n, 1.0, {"safe": not horde, "horde": horde}, rec.get("traits", []))
	person_moodlets(rec, n)


# --- Using things (host) ----------------------------------------------------------------------

## Host: `s` ate, drank or took `item` (Survival.server_eat): a habit's dose and its relief, or
## human flesh.
static func server_on_used(s: Soldier, n: Dictionary, item: ItemData) -> void:
	if item == null:
		return
	if Cannibalism.is_human_meat(item):
		Cannibalism.server_on_eaten(s, n)
	var k := Addictions.kind_of(item)
	if not k.is_empty():
		var before := Nerve.value(n)
		Addictions.dose(n, String(k[0]), float(k[1]))
		if Nerve.value(n) > before + 4.0:
			Survival._tell(s, "Your nerves settle a little")


## Host: a treatment `item_id` given to `target` (Body.on_treated): morphine is a painkiller dose.
static func on_treated(target: Soldier, item_id: StringName) -> void:
	if target == null or not Survival.running or not Addictions.ITEM_KINDS.has(String(item_id)):
		return
	var k: Array = Addictions.ITEM_KINDS[String(item_id)]
	Addictions.dose(Survival.needs_of(target), String(k[0]), float(k[1]))


## The worse things on record: a "dark" tag on the survivor (the story page reads it later).
static func mark_dark(s: Soldier, what: String) -> void:
	if s.is_ai():
		var rec := record_of(s)
		if not rec.is_empty():
			Moods.add(rec, "ate_human" if what == "ate_human" else "butchered")
			SurvivorPerson.note(rec, "crossed the line (%s)" % what)
		return
	var srec := Survival.survivor_of(s)
	var dark: Array = srec.get("dark", [])
	dark.append({"day": Survival.day(), "what": what})
	srec["dark"] = dark.slice(-20)


# --- Words ------------------------------------------------------------------------------------

## The HUD's low-only signs: shaken or breaking, in withdrawal, the shaking sickness.
static func signs(n: Dictionary) -> Array:
	var out: Array = []
	if n.has(Nerve.KEY) and Nerve.level_of(n) >= 2:
		out.append(Nerve.word(n))
	if Addictions.worst(n) > 0.0:
		out.append("withdrawal")
	if Cannibalism.prion_stage(n) >= 1:
		out.append("trembling")
	return out


## The body screen's and readout's words: the nerve, the habits, the sickness.
static func words(n: Dictionary) -> Array:
	var out: Array = []
	if n.has(Nerve.KEY) and Nerve.level_of(n) >= 1:
		out.append("nerve: %s" % Nerve.word(n))
	out.append_array(Addictions.words(n))
	if Cannibalism.prion_stage(n) >= 1:
		out.append("a trembling, wasting sickness")
	return out


## The character screen's line.
static func character_line(n: Dictionary) -> String:
	var w := Addictions.words(n)
	return "Nerve: %s. Habits: %s" % [Nerve.word(n) if n.has(Nerve.KEY) else "steady", ", ".join(PackedStringArray(w)) if not w.is_empty() else "none"]
