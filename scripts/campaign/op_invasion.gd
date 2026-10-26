class_name OpInvasion
extends OpBase
## The phased invasion made full (docs/combined_arms.md 6.4.1; phase D4, cg_brief queue item 3.3):
## D3 built its four phases (COPPER the outposts, BRASS the crossing with the bridge to keep, IRON
## the town, STEEL the HQ and the depth target), its front and its pay. D4 adds what 6.4.1 lists
## beyond them: the full order of battle (data: the rifle platoons, the mechanised and armour
## platoons, the mortar section with its tubes, the fuel and ammunition trucks and the medevac, an
## Abrams section attached to the company: OpSupport), preparation fires on each phase's objectives
## (data "prep"), and phase 4's bonus: the HQ's commander taken alive.
##
## The commander: when PL STEEL begins he's at the HQ compound (a hostile of his own, "op_commander"),
## the company's optional task "op_take_alive" (data, bonus_share of the phase's pay): done once he's
## down or a captive, not dead, with one of the company within "secure_m" of him; failed if he dies.
## Numbers in data/operations.json "phased_invasion" "commander", Proposed.

const COMMANDER_META := &"op_commander"
const TAKE_ALIVE := "op_take_alive"

var commander: Soldier


func start() -> void:
	var m := mine()
	if bool(m.get("commander_out", false)) and String(m.get("commander_state", "")) == "":
		m["commander_out"] = false  # (a loaded save: he comes out again with his phase)
	_refresh()


func phase_begun(k: int) -> void:
	if _has_task(k, TAKE_ALIVE):
		_spawn_commander(k)


func _has_task(k: int, kind: String) -> bool:
	var phases: Array = contract().get("phases", [])
	return k < phases.size() and (phases[k].tasks as Array).any(func(t: Dictionary) -> bool: return String(t.kind) == kind)


func _spawn_commander(k: int) -> void:
	var m := mine()
	if bool(m.get("commander_out", false)):
		return
	var response := EnemyResponse.of(self)
	var phases: Array = contract().get("phases", [])
	var at := Vector3.INF
	for t: Dictionary in phases[k].tasks:
		if String(t.kind) == TAKE_ALIVE:
			at = v3(t.pos)
	if response == null or not at.is_finite():
		return
	var squad := response._new_squad(ops._fresh_name("Commander"))
	var made := response._spawn_team(squad, "HQ_Commander", 1, at, at + Vector3(0, 0, 1), CompoundLevel.HOSTILE_LOADOUT.duplicate(), 0.45, 0.6, "aware")
	if made.is_empty():
		return
	commander = made[0] as Soldier
	commander.set_meta(COMMANDER_META, true)
	squad.leader = commander
	m["commander_out"] = true
	SessionLog.note("operation %s: the HQ's commander is at %s" % [ops.cid, grid_ref(at)])
	_refresh()


func task(o: Dictionary, _dt: float) -> String:
	if String(o.kind) != TAKE_ALIVE:
		return ""
	var m := mine()
	if commander == null or not is_instance_valid(commander):
		return ""
	if commander.vitals.is_dead():
		if String(m.get("commander_state", "")) != "dead":
			m["commander_state"] = "dead"
			note("The HQ's commander was killed: no bonus for taking him alive.")
			say("Citadel: the HQ's commander is dead.")
			_refresh()
		return Objectives.FAILED
	if commander.vitals.is_up() and not Person.is_captive(commander):
		return ""
	var secure := num("commander", "secure_m", 6.0)
	if ops._company_near(commander.global_position, secure) > 0:
		m["commander_state"] = "taken"
		note("The HQ's commander was taken alive.")
		say("Citadel: good work, the HQ's commander is in our hands.")
		_refresh()
		return Objectives.DONE
	return ""


func strip_line() -> String:
	match String(state.get("commander", "")):
		"out":
			return "HQ commander: take him alive"
		"taken":
			return "HQ commander: taken alive"
		"dead":
			return "HQ commander: dead"
	return ""


func _refresh() -> void:
	var s := {"commander": String(mine().get("commander_state", "out" if bool(mine().get("commander_out", false)) else ""))}
	if s != state:
		state = s
		publish()
