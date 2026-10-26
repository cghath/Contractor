class_name Nerve
extends RefCounted
## The nerve meter of Contractor: Fallen (call 116; docs/survival_mind.md section 1): how steady a
## survivor is, 0 (breaking) .. 100 (steady), kept as "nerve" in the body's Dictionary (Needs'
## stores: a player's, and a companion's through the same record). Hordes, a bite, a friend's
## death, nights without sleep, close calls (a bite dodged, a scream), killing a person shake it;
## sleep, an hour of safety at the settlement, a companion's talk, a drink or a smoke settle it.
## Low nerve shakes the hands (aim sway: Needs.sway_mult reads Mind.sway_add), rings the ears
## (Needs.dulled), slows stamina's return, and swells the tension layer (level(): the audio lane
## reads it). Static and pure but for the server_ calls.

const KEY := "nerve"
const START := 70.0
## Below this the meter has effects (shake01 0 here, 1 at 0).
const LOW := 50.0
## Proposed: what each thing takes off the meter.
const SHAKE := {"horde": 18.0, "bite": 25.0, "friend_died": 30.0, "companion_died": 15.0, "close_call": 10.0,
	"scream": 8.0, "killed_person": 15.0, "butchered": 20.0, "ate_human": 18.0, "nightmare": 8.0}
## Proposed rates a world hour: asleep, safe (after SAFE_H at the settlement), the drift back
## toward DRIFT_TO awake, a night without sleep (the sleep store under Needs.SLEEP_LOW).
const SLEEP_H := 5.0
const SAFE_H := 1.0
const SAFE_RATE_H := 4.0
const DRIFT_H := 0.5
const DRIFT_TO := 60.0
const NO_SLEEP_H := 1.5
## A companion's talk ("Talk me down") and the wait between two.
const TALK := 25.0
const TALK_COOLDOWN_H := 6.0
## How the traits take a shake (Proposed).
const TRAIT_MULT := {"brave": 0.7, "calm": 0.8, "timid": 1.3, "coward": 1.3, "gloomy": 1.1, "optimist": 0.9}
const CRUEL_CAUSES: Array[String] = ["killed_person", "butchered", "ate_human"]
## Effects at the bottom (shake01 = 1).
const SWAY := 0.9
const DULLED := 0.6
const STAMINA := 0.35
## The dead within this of a survivor at home take "safe" away.
const SAFE_DEAD_M := 40.0
## A screamer within this shakes (once a scream).
const SCREAM_M := 45.0


static func value(n: Dictionary) -> float:
	return float(n.get(KEY, START))


static func set_value(n: Dictionary, v: float) -> void:
	n[KEY] = clampf(v, 0.0, 100.0)


## 0 steady (60+), 1 uneasy (35+), 2 shaken (15+), 3 breaking.
static func level_of(n: Dictionary) -> int:
	if n.is_empty():
		return 0
	var v := value(n)
	return 0 if v >= 60.0 else (1 if v >= 35.0 else (2 if v >= 15.0 else 3))


## The tension layer's read (the audio lane): `s`'s nerve level 0-3 (the host's body, or the
## owner's own copy, Survival.my_body).
static func level(s: Soldier) -> int:
	if s == null or not is_instance_valid(s):
		return 0
	if s.has_meta(&"needs"):
		return level_of(s.get_meta(&"needs"))
	if s.is_inside_tree() and not s.multiplayer.is_server() and s.owner_peer() == s.multiplayer.get_unique_id():
		return level_of(Survival.my_body)
	return 0


static func word(n: Dictionary) -> String:
	var words: Array[String] = ["steady", "uneasy", "shaken", "breaking"]
	return words[level_of(n)]


## How low it is, 0 (LOW or more) .. 1 (empty).
static func shake01(n: Dictionary) -> float:
	if not n.has(KEY):
		return 0.0
	return clampf((LOW - value(n)) / LOW, 0.0, 1.0)


## Takes `cause`'s SHAKE (or `amount`) off `n`, by `traits` (the cruel shrug off killing and the
## worse); remembers it for the night's dream (Dreams.mark). Returns the nerve after.
static func shake(n: Dictionary, cause: String, traits: Array = [], amount := NAN) -> float:
	var a := float(SHAKE.get(cause, 10.0)) if is_nan(amount) else amount
	for t: String in traits:
		a *= float(TRAIT_MULT.get(t, 1.0))
	if "cruel" in traits and cause in CRUEL_CAUSES:
		a *= 0.4
	set_value(n, value(n) - a)
	Dreams.mark(n, cause)
	return value(n)


static func settle(n: Dictionary, amount: float) -> float:
	set_value(n, value(n) + amount)
	return value(n)


## `world_h` world hours: asleep it settles (less after a nightmare), safe at home after SAFE_H it
## settles, awake it drifts back toward DRIFT_TO, and a night without sleep wears it down.
## `ctx`: "safe" (at the settlement, no dead near), "wear" (extra a world hour: withdrawal, the
## sickness).
static func step(n: Dictionary, world_h: float, ctx: Dictionary) -> void:
	if world_h <= 0.0:
		return
	var v := value(n)
	var asleep := String(n.get("asleep", "")) != ""
	if bool(ctx.get("safe", false)):
		n["safe_h"] = float(n.get("safe_h", 0.0)) + world_h
	else:
		n["safe_h"] = 0.0
	if asleep:
		v += SLEEP_H * world_h * Dreams.restore_mult(n)
	elif float(n.get("safe_h", 0.0)) >= SAFE_H:
		v += SAFE_RATE_H * world_h
	elif v < DRIFT_TO:
		v = minf(DRIFT_TO, v + DRIFT_H * world_h)
	if not asleep and float(n.get("sleep", 100.0)) < Needs.SLEEP_LOW:
		v -= NO_SLEEP_H * world_h
		if float(n.get("no_sleep_mark_h", 0.0)) <= 0.0:
			Dreams.mark(n, "no_sleep")
			n["no_sleep_mark_h"] = 24.0
	n["no_sleep_mark_h"] = maxf(0.0, float(n.get("no_sleep_mark_h", 0.0)) - world_h)
	v -= float(ctx.get("wear", 0.0)) * world_h
	set_value(n, v)


# --- Hooks (host) ---------------------------------------------------------------------------

## Host: a person died (SurvivorsLayer._on_died: `rec`, a companion or settler before): the other
## companions are shaken (a friend more) and so are the players in the zone; and whoever killed
## them (a player, a companion) is shaken for killing a person (server_on_killed).
static func server_on_death(dead: Soldier, rec: Dictionary, was: String) -> void:
	if not Survival.running or dead == null or not is_instance_valid(dead):
		return
	if was in ["companion", "settler"]:
		var id := String(rec.get("id", ""))
		for other: Dictionary in SurvivorsLayer.records().values():
			if String(other.get("id", "")) == id or not String(other.get("status", "")) in ["companion", "settler"]:
				continue
			var n: Dictionary = other.get("needs", {})
			if n.is_empty():
				continue
			var friend := SurvivorPerson.relation(other, id) >= 40.0
			shake(n, "friend_died" if friend else "companion_died", other.get("traits", []))
		var lvl: CompoundLevel = CompoundLevel.current(dead) if dead.is_inside_tree() else null
		if lvl:
			for p: Soldier in MapNodes.players(lvl):
				if p.vitals.is_up():
					shake(Survival.needs_of(p), "friend_died", Mind.traits_of(p))
	server_on_killed(dead)


## Host: a person `victim` died; if a player or a companion killed them (Harm's last hit), the
## killer is shaken and a companion gets the killed_person moodlet.
static func server_on_killed(victim: Soldier) -> void:
	if victim == null or not is_instance_valid(victim) or not victim.has_meta(Harm.META) or victim.vitals.undead:
		return
	var info: Dictionary = victim.get_meta(Harm.META, {})
	var path := String(info.get("path", ""))
	if path == "" or not victim.is_inside_tree():
		return
	var killer := victim.get_node_or_null(NodePath(path)) as Soldier
	if killer == null or killer == victim or killer.vitals.undead or killer.faction == ZombieAI.INFECTED:
		return
	shake(Survival.needs_of(killer), "killed_person", Mind.traits_of(killer))
	var layer := SurvivorsLayer.find(killer)
	var rec := layer.record_of(killer) if layer else {}
	if not rec.is_empty():
		Moods.add(rec, "killed_person")


## Host: a close call on `s` (a bite dodged, a screamer near).
static func server_close_call(s: Soldier, cause := "close_call") -> void:
	if not Survival.running or s == null or not is_instance_valid(s) or s.vitals.undead:
		return
	shake(Survival.needs_of(s), cause, Mind.traits_of(s))


## Host: "Talk me down" (TalkMenu): the companion `rec` talks `actor` down: his nerve up, the
## companion's time spent (TALK_COOLDOWN_H), a moodlet for them. "" or why not ("busy").
static func server_talk_down(actor: Soldier, rec: Dictionary) -> String:
	var now := Moods.now_h()
	if float(rec.get("talk_down_until", -1.0)) > now:
		return "busy"
	var n := Survival.needs_of(actor)
	settle(n, TALK)
	rec["talk_down_until"] = now + TALK_COOLDOWN_H
	Moods.add(rec, "talked_down")
	Dreams.mark(n, "kindness")
	Needs.apply(actor, n)
	return ""


## What the companion says talking someone down (or too spent to).
const TALK_LINES := ["Breathe. In, hold it, out. We're still here.", "Look at me, not at that. Tell me about before.",
	"You did fine. Sit a minute; I've got the door.", "It's all right to shake. Shake it out. Then we go on."]
const BUSY_LINES := ["I've nothing left to give tonight. Ask me later.", "Not now. I'm barely holding it together myself."]


static func talk_line(rec: Dictionary, busy: bool) -> String:
	var pool: Array = BUSY_LINES if busy else TALK_LINES
	return String(pool[absi(hash([String(rec.get("id", "")), int(Moods.now_h())])) % pool.size()])
