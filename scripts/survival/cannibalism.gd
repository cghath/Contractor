class_name Cannibalism
extends RefCounted
## Cannibalism as a last resort (call 117; docs/survival_mind.md section 2): butchering a dead
## person with a blade (TalkMenu's "Butcher" on a dead survivor's body: server_butcher) gives human
## meat (data/items.json "human_meat": food by Needs' values, raw); butchering and eating it cost
## nerve and a heavy moodlet (less for the cruel), the companions who see it think less of you,
## the groups in the zone learn of it (an event in the world's pool, Intel.server_event, and
## their standing with the players falls; cultists don't mind) and it goes in the journal tagged
## "dark". Each meal risks a prion-like wasting sickness ("prion" in the body's Dictionary: own
## tick, nothing cures it): hidden PRION_ONSET_H, then tremors, a failing memory (lines), death
## after PRION_DEATH_H more. Cultists and the starving eat the dead too (eats_the_dead: a flag
## the world's groups can read).

const MEAT := &"human_meat"
## Proposed: cuts a body gives, the standing a group loses when it learns, the moodlets.
const CUTS := 3
const STANDING_DROP := 25.0
const WITNESS_M := 25.0
const WITNESS_OPINION := -30.0
## The prion sickness (Proposed): chance a meal, world hours hidden, then to death.
const PRION_CHANCE := 0.2
const PRION_ONSET_H := 240.0
const PRION_DEATH_H := 504.0
const PRION_LINE_EVERY_H := 24.0
const MEMORY_LINES := ["You stand in the doorway and can't think why you came.", "Whose boots are these? Yours. They're yours.",
	"You wrote the same line in the journal twice today.", "A name you knew for years is gone. You try for an hour.",
	"Your hands won't stop. The cup rattles on the table."]
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func is_human_meat(item: ItemData) -> bool:
	return item != null and bool(item.stats.get("human", false))


## Whether a world group eats its dead: cultists always, the starving when the food is gone.
static func eats_the_dead(g: Dictionary) -> bool:
	return String(g.get("kind", "")) == "cultists" or (bool(g.get("alive", true)) and WorldGroup.days_of_food(g) <= 0.0)


# --- Butchering and eating (host) ------------------------------------------------------------

## Whether `actor` may butcher the dead survivor `rec` (a blade; not buried, not done). "" or why.
static func butcher_problem(actor: Soldier, rec: Dictionary) -> String:
	if String(rec.get("status", "")) != "dead" or bool(rec.get("buried", false)):
		return "Not that one"
	if bool(rec.get("butchered", false)):
		return "There's nothing left on them you could bring yourself to take"
	if not Crafting.has_tool(actor, ["tag:blade", "tag:knife"]):
		return "You need a knife or a blade"
	return ""


## Host: `actor` butchers the dead person `body` (`rec`): CUTS of human meat, nerve and a moodlet,
## witnesses, the world learns, the journal. "" or why not.
static func server_butcher(actor: Soldier, body: Soldier, rec: Dictionary) -> String:
	var why := butcher_problem(actor, rec)
	if why != "":
		Survival._tell(actor, why)
		return why
	rec["butchered"] = true
	for i in CUTS:
		if actor.inventory.take(MEAT, 1) <= 0:
			var level := CompoundLevel.current(actor)
			if level:
				level.server_spawn_dropped(MEAT, 1, actor.global_position + Vector3(0.3 * i, 0.4, 0.3), {})
	var n := Survival.needs_of(actor)
	Nerve.shake(n, "butchered", Mind.traits_of(actor))
	Mind.mark_dark(actor, "butchered")
	_witnesses(actor, "butchered")
	var who := Survival.survivor_name(actor) if not actor.is_ai() else actor.log_name()
	dark_line("%s cut meat from %s's body." % [who, String(rec.get("name", "the dead"))])
	server_world_learns(actor, "%s butchered the dead for meat" % who)
	Survival._tell(actor, "You do it. You try not to look at the face")
	Needs.apply(actor, n)
	return ""


## Host: `s` ate human meat (Mind.server_on_used): nerve and a moodlet, the prion roll, the world.
static func server_on_eaten(s: Soldier, n: Dictionary) -> void:
	Nerve.shake(n, "ate_human", Mind.traits_of(s))
	n["ate_human"] = int(n.get("ate_human", 0)) + 1
	Mind.mark_dark(s, "ate_human")
	_witnesses(s, "ate_human")
	roll_prion(n)
	var who := Survival.survivor_name(s) if not s.is_ai() else s.log_name()
	if int(n.ate_human) == 1:
		dark_line("%s ate human flesh." % who)
		server_world_learns(s, "%s eats the dead's flesh" % who)


## The prion roll for a meal (nothing if it's already in).
static func roll_prion(n: Dictionary) -> bool:
	if n.has("prion"):
		return false
	var roll := force_roll if force_roll >= 0.0 else randf()
	if roll < PRION_CHANCE:
		n["prion"] = {"h": 0.0, "line_h": 0.0}
		return true
	return false


## Companions within WITNESS_M of `s` who saw it: a moodlet and their opinion of the player falls.
static func _witnesses(s: Soldier, what: String) -> void:
	var layer := SurvivorsLayer.find(s)
	if layer == null:
		return
	for c: Soldier in layer.companions():
		if c == s or not c.vitals.is_up() or c.global_position.distance_to(s.global_position) > WITNESS_M:
			continue
		var rec := layer.record_of(c)
		if rec.is_empty() or SurvivorPerson.has_trait(rec, "cruel"):
			continue
		Moods.add(rec, "saw_cannibalism")
		if not s.is_ai():
			SurvivorPerson.change_opinion(rec, Survival.profile_of(s), WITNESS_OPINION)
		SurvivorPerson.note(rec, "saw %s %s" % [Survival.survivor_name(s) if not s.is_ai() else s.log_name(), "butcher a body" if what == "butchered" else "eat human flesh"])


## A journal line tagged "dark" (the story page's later; the journal keeps the tag).
static func dark_line(text: String) -> void:
	var e := Intel.journal(text, "dark")
	var voiced := JournalVoice.phrase(text, JournalVoice.writer_traits())
	if voiced != text:
		e["voice"] = voiced


## Host: the groups in `s`'s zone learn of it: an event in the world's pool ("cannibalism") and
## their standing with the players falls by STANDING_DROP (cultists don't mind). Returns how many
## groups' standing fell.
static func server_world_learns(s: Soldier, text: String) -> int:
	if s.is_ai() or not WorldSim.is_set_up():
		return 0
	var zone := String(Survival.state().get("zone", ""))
	Intel.server_event(zone, "cannibalism", ["player"], text)
	var sim := WorldSim.get_sim()
	var fell := 0
	for g: Dictionary in WorldSim.groups_in(zone):
		if String(g.get("kind", "")) == "cultists":
			continue
		if sim:
			sim.server_change_relation(String(g.id), -STANDING_DROP, "eats the dead")
		else:
			WorldGroup.change_relation(g, "player", -STANDING_DROP)
		fell += 1
	return fell


# --- The prion sickness -----------------------------------------------------------------------

static func prion_stage(n: Dictionary) -> int:
	var p: Dictionary = n.get("prion", {})
	if p.is_empty():
		return 0
	var h := float(p.get("h", 0.0))
	if h < PRION_ONSET_H:
		return 0
	return 1 if h < PRION_ONSET_H + PRION_DEATH_H * 0.5 else 2


## How far gone, 0 (hidden or none) .. 1 (dying).
static func prion_share(n: Dictionary) -> float:
	var p: Dictionary = n.get("prion", {})
	if p.is_empty():
		return 0.0
	return clampf((float(p.get("h", 0.0)) - PRION_ONSET_H) / PRION_DEATH_H, 0.0, 1.0)


## `world_h` world hours of the sickness: "" , "onset" (it shows), "memory" (a line in
## n["_prion_line"]), "death".
static func prion_step(n: Dictionary, world_h: float) -> String:
	var p: Dictionary = n.get("prion", {})
	if p.is_empty() or world_h <= 0.0:
		return ""
	var before := float(p.get("h", 0.0))
	p.h = before + world_h
	if float(p.h) >= PRION_ONSET_H + PRION_DEATH_H:
		return "death"
	if before < PRION_ONSET_H and float(p.h) >= PRION_ONSET_H:
		return "onset"
	if float(p.h) >= PRION_ONSET_H:
		p.line_h = float(p.get("line_h", 0.0)) + world_h
		if float(p.line_h) >= PRION_LINE_EVERY_H:
			p.line_h = 0.0
			n["_prion_line"] = String(MEMORY_LINES[absi(hash([int(p.h)])) % MEMORY_LINES.size()])
			return "memory"
	return ""
