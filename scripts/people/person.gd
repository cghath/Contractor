class_name Person
extends RefCounted
## Who someone on the map is, for anyone who asks: AI targeting and fire discipline, the
## interaction menu, the people code itself (wave 4, W11). Reads the per-person state that
## PeopleLayer replicates, so every answer is the same on every peer.
##
## People are Soldier bodies. Civilians and HVTs are in the "civilian" faction (FACTION),
## so no squad counts them and nobody's side is theirs; a hostile soldier who gave up keeps
## his faction but is a captive (surrendered, later cuffed). None of them fight, and AI never
## targets one (is_noncombatant).

## The faction of civilians and HVTs (Soldier.faction).
const FACTION := &"civilian"
## Kinds of person (state "kind").
const CIVILIAN := &"civilian"
const HVT := &"hvt"
const SOLDIER := &"soldier"  # a hostile soldier who surrendered
## Sides (state "side"): whose an HVT is. Civilians are neutral.
const FRIENDLY := &"friendly"
const HOSTILE := &"hostile"
const NEUTRAL := &"neutral"
## The item that cuffs a captive (data/items.json).
const ZIP_CUFFS := &"zip_cuffs"
## A hostile HVT can be cuffed from behind (or once down or surrendered): the cuffer must be
## further back than this (dot of the target's facing and the way to the cuffer, flat).
const BEHIND_DOT := -0.25
## The interaction menu's conditions this class answers (InteractionMenu._check).
const MENU_NEEDS: Array[StringName] = [&"cuffable", &"leadable", &"led", &"searchable", &"carriable_person"]
const HIDE := "-"


## The replicated state of `s` ({} for nobody in particular): "kind", "side", "uid",
## "hvt_id", "cuffed", "surrendered", "led_by" (path from the level), "order" ("follow",
## "stop", "cover" or ""), "delivered", "seated_in".
static func state(s: Node) -> Dictionary:
	var layer := PeopleLayer.find(s)
	return layer.state_of(s) if layer else {}


## CIVILIAN, HVT, SOLDIER (a hostile who gave up) or &"" for anyone else.
static func kind_of(s: Node) -> StringName:
	return StringName(state(s).get("kind", ""))


## FRIENDLY, HOSTILE or NEUTRAL; &"" for anyone who isn't a person.
static func side_of(s: Node) -> StringName:
	return StringName(state(s).get("side", ""))


## A civilian, an HVT, or a hostile who gave up: someone the interaction menu offers the
## people actions on.
static func is_person(s: Node) -> bool:
	return s is Soldier and (s.faction == FACTION or is_captive(s))


static func is_civilian(s: Node) -> bool:
	return s is Soldier and s.faction == FACTION and kind_of(s) == CIVILIAN


static func is_hvt(s: Node) -> bool:
	return kind_of(s) == HVT


## Never a target: civilians, HVTs and hostiles who gave up. AI holds fire when one of them
## is in its line of fire (SquadAI).
static func is_noncombatant(s: Node) -> bool:
	if not s is Soldier:
		return false
	if s.faction == FACTION:
		return true
	if s.faction != HOSTILE:
		return false  # the players' side never surrenders
	return is_captive(s)


## Cuffed, or surrendered and not yet cuffed.
static func is_captive(s: Node) -> bool:
	var st := state(s)
	return bool(st.get("cuffed", false)) or bool(st.get("surrendered", false))


static func is_cuffed(s: Node) -> bool:
	return bool(state(s).get("cuffed", false))


## Someone zip cuffs can go on: a hostile HVT or a hostile who surrendered, not yet cuffed
## and still alive.
static func cuffable(s: Node) -> bool:
	if not s is Soldier or (s as Soldier).vitals.is_dead() or is_cuffed(s):
		return false
	var st := state(s)
	return (StringName(st.get("kind", "")) == HVT and StringName(st.get("side", "")) == HOSTILE) or bool(st.get("surrendered", false))


## Someone who comes along when told (Follow me, Stop, Get in cover): a friendly HVT, or any
## captive. Conscious, alive and not yet delivered.
static func leadable(s: Node) -> bool:
	if not s is Soldier or not (s as Soldier).vitals.is_up():
		return false
	var st := state(s)
	if bool(st.get("delivered", false)):
		return false
	return (StringName(st.get("kind", "")) == HVT and StringName(st.get("side", "")) == FRIENDLY) or is_captive(s)


## Someone whose pockets can be searched for intel while alive: a captive, or an HVT lying
## unconscious. (A downed hostile soldier is searched by cuffing him first, or looted dead.)
static func searchable(actor: Soldier, s: Node) -> bool:
	if not s is Soldier or (s as Soldier).vitals.is_dead() or s == actor:
		return false
	if is_captive(s):
		return true
	return not (s as Soldier).vitals.is_up() and kind_of(s) == HVT


## True if `actor` stands behind `target` (outside its view, BEHIND_DOT).
static func is_behind(actor: Node3D, target: Node3D) -> bool:
	var to := actor.global_position - target.global_position
	to.y = 0.0
	if to.length() < 0.01:
		return false
	var facing := -target.global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(to.normalized()) < BEHIND_DOT


## Why `actor` can't zip-cuff `target` right now ("" if they can): no cuffs, or a hostile HVT
## who is up, hasn't given up and sees you coming. (Reach is checked by the host.)
static func cuff_problem(actor: Soldier, target: Node) -> String:
	if not cuffable(target):
		return "They can't be cuffed"
	if actor.inventory.count_of(ZIP_CUFFS) <= 0:
		return "You have no zip cuffs"
	var s := target as Soldier
	if s.vitals.is_up() and not bool(state(s).get("surrendered", false)) and not is_behind(actor, s):
		return "Get behind them, or wait until they give up"
	return ""


## The interaction menu's people conditions (MENU_NEEDS): "" when met, HIDE to leave the
## entry out, or why it's greyed out.
static func menu_check(need: StringName, actor: Soldier, target: Node) -> String:
	match need:
		&"cuffable":
			return cuff_problem(actor, target) if cuffable(target) else HIDE
		&"leadable":
			return "" if leadable(target) else HIDE
		&"led":
			return "" if leadable(target) and String(state(target).get("led_by", "")) != "" else HIDE
		&"searchable":
			return "" if searchable(actor, target) else HIDE
		&"carriable_person":
			if not (target is Soldier and is_cuffed(target) and (target as Soldier).vitals.is_up()):
				return HIDE
			if actor.carry_mode != &"":
				return "You're already moving someone"
			return "" if actor.inventory.hands == &"" else "Your hands are full"
	return HIDE
