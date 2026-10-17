class_name EnemyCommand
extends Node
## A hot zone's enemy high command, Phase 1 (docs/enemy_high_command.md; Captain, 2026-10-17:
## "if an outpost is lost and a suitable force cant take it back we shouldnt be assaulted by the
## rest of the map. the high commander can control high level stuff like that"). It decides; the
## zone's EnemyResponse does the doing (spawning, routes, gates, technicals).
##
## - Force against force: its own combat power (CP: a man is 1) against its estimate of the
##   squad's (threat_cp: every player and squad AI 1.5 for their armour, +1 in a working LX-3
##   frame). Phase 1 reads the squad's real size; reported strength (fog) is Phase 2.
## - Hunts (EnemyResponse's QRF launches and hunter teams) go only when the force it can send
##   is HUNT_RATIO of the threat (approve); otherwise they're turned down, and the squad isn't
##   chased by whatever is left on the map.
## - A garrisoned site lost (ZoneLevel.site_down): a Counterattack if it can field
##   COUNTER_RATIO of the threat there (the squad within SITE_THREAT_M; a token force with nobody
##   there). The task force spawns at the nearest unseen base gate, assembles at a rally point
##   RALLY_M short of the site, out of sight, then goes in together after ASSEMBLE_S (or when all
##   are there); under CALL_OFF_RATIO on the way it's called off and goes home. Without the
##   force: Contain, no attack, looked at again every RECHECK_S (the squad gone, or the budget
##   grown, a contained site can still be retaken).
## - At most MAX_OPS operations moving or attacking at once (MAX_OPS_HIGH from tier 3).
## Every decision is a record in `operations` ({"kind", "target", "state", "why", "at", ...}).
## Host only; one node per hot zone ("EnemyCommand", ZoneLevel), on the Alert's clock. All
## numbers Proposed.

const TICK_S := 30.0
const HUNT_RATIO := 2.0
const COUNTER_RATIO := 3.0
const CALL_OFF_RATIO := 1.5
const SITE_THREAT_M := 200.0
const RALLY_M := 150.0
const ASSEMBLE_S := 120.0
const ASSEMBLED_M := 25.0
const RECHECK_S := 300.0
const MAX_OPS := 2
const MAX_OPS_HIGH := 3
## Combat power of one of the squad: armoured contractors; in a working exo frame, more.
const SQUAD_MAN_CP := 1.5
const EXO_CP := 1.0
const SITE_TYPES: Array[String] = ["outpost", "checkpoint", "qrf_base", "comms"]

var level: Node3D
var response: EnemyResponse
var alert: Alert
var operations: Array[Dictionary] = []
var _tick := 0.0
var _handled := {}  # module id -> true: its loss already has an operation


func _init() -> void:
	name = "EnemyCommand"


func _ready() -> void:
	level = get_parent() as Node3D
	response = level.get_node_or_null(^"EnemyResponse") as EnemyResponse if level else null
	alert = level.get_node_or_null(^"Alert") as Alert if level else null


static func of(from: Node) -> EnemyCommand:
	var lvl := CompoundLevel.current(from) if from else null
	return lvl.get_node_or_null(^"EnemyCommand") as EnemyCommand if lvl else null


func now() -> float:
	return alert.now() if alert else Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()


# --- The picture --------------------------------------------------------------------------------

## The squad's combat power: everyone of it up (players and squad AI) within `radius` of `at`
## (all of it with no point given).
func threat_cp(at := Vector3.INF, radius := INF) -> float:
	var cp := 0.0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction != &"friendly" or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		if at.is_finite() and s.global_position.distance_to(at) > radius:
			continue
		cp += SQUAD_MAN_CP + (EXO_CP if ExoFrame.working(s.inventory) else 0.0)
	return cp


## The force it can send now (CP): what the zone's spawn budget still has room for.
func available_cp() -> float:
	return float(response._room()) if response else 0.0


func _active_ops() -> int:
	return operations.filter(func(o: Dictionary) -> bool: return o.state in ["assembling", "attacking", "approved"]).size()


func max_ops() -> int:
	var tier := response._tier() if response else 0
	return MAX_OPS_HIGH if tier >= 3 else MAX_OPS


# --- Decisions --------------------------------------------------------------------------------

## EnemyResponse asks before a hunt (`kind` "qrf" or "hunters") toward `target`: true to go.
func approve(kind: String, target: Vector3) -> bool:
	var threat := maxf(threat_cp(), 1.0)
	var have := available_cp()
	var ok := have >= threat * HUNT_RATIO and _active_ops() < max_ops()
	var why := "%.0f CP against %.1f (%.1f:1)" % [have, threat, have / threat]
	operations.append({"kind": "hunt:" + kind, "target": target, "state": "approved" if ok else "denied", "why": why, "at": now()})
	if not ok:
		print("[command] %s turned down: %s" % [kind, why])
	return ok


func server_tick() -> void:
	if not multiplayer.is_server() or level == null or response == null:
		return
	for op: Dictionary in operations:
		if op.state == "approved" and now() - float(op.at) > 60.0:
			op.state = "done"  # a hunt is EnemyResponse's from here on
	_watch_sites()
	for op: Dictionary in operations:
		if op.kind == "counterattack":
			_step_counterattack(op)
		elif op.kind == "contain" and op.state == "containing" and now() >= float(op.recheck_at):
			op.state = "rechecked"
			_handled.erase(op.target_id)  # looked at again: maybe a counterattack now


## Sites with a garrison that have fallen: each gets one operation.
func _watch_sites() -> void:
	var had := level.get(&"_garrisoned") as Dictionary
	if had == null:
		return
	for m: ZoneModule in level.call(&"modules"):
		if not (m.type in SITE_TYPES) or int(had.get(m.module_id, 0)) <= 0 or _handled.has(m.module_id):
			continue
		if level.call(&"site_down", m.module_id):
			_handled[m.module_id] = true
			_decide_lost(m)


func _decide_lost(m: ZoneModule) -> void:
	var threat := maxf(threat_cp(m.global_position, SITE_THREAT_M), 1.0)
	var need := ceili(threat * COUNTER_RATIO)
	var have := available_cp()
	var base := _nearest_base(m.global_position)
	var why := "%s lost: %.0f CP against %.1f there (needs %d)" % [m.module_id, have, threat, need]
	if base == null or have < need or _active_ops() >= max_ops():
		operations.append({"kind": "contain", "target": m.global_position, "target_id": m.module_id, "state": "containing",
			"why": why + (", no base" if base == null else ""), "at": now(), "recheck_at": now() + RECHECK_S})
		print("[command] contain %s" % why)
		return
	var gate := response._unseen_gate(base, m.global_position)
	if not gate.is_finite():
		operations.append({"kind": "contain", "target": m.global_position, "target_id": m.module_id, "state": "containing",
			"why": why + ", every gate watched", "at": now(), "recheck_at": now() + RECHECK_S})
		return
	var rally := response._ground(m.global_position.move_toward(gate, RALLY_M))
	var callsign := ("CA_%s" % m.module_id).validate_node_name()
	var squad := response._new_squad(callsign)
	var route: Array[Vector3] = [rally]
	squad.patrol = route
	var soldiers := response._spawn_team(squad, callsign, need, gate, rally, CompoundLevel.HOSTILE_LOADOUT,
		EnemyResponse.HUNTER_COMBAT, EnemyResponse.HUNTER_DISCIPLINE * response.coordination(), "combat")
	operations.append({"kind": "counterattack", "target": m.global_position, "target_id": m.module_id, "state": "assembling",
		"why": why, "at": now(), "rally": rally, "base": base.module_id, "squad": squad, "soldiers": soldiers, "threat": threat})
	print("[command] counterattack %s: %d men assembling at (%.0f, %.0f)" % [m.module_id, soldiers.size(), rally.x, rally.z])


func _step_counterattack(op: Dictionary) -> void:
	var living: Array = response._living(op.soldiers)
	if living.is_empty():
		op.state = "failed"
		op.why = "task force lost"
		return
	if op.state == "assembling":
		var there := living.all(func(s: Soldier) -> bool: return s.global_position.distance_to(op.rally) <= ASSEMBLED_M)
		if there or now() - float(op.at) >= ASSEMBLE_S:
			op.state = "attacking"
			op.attack_at = now()
			var route: Array[Vector3] = [response._ground(op.target)]
			response._set_route(op.squad, living, route)
	elif op.state == "attacking":
		var threat := maxf(threat_cp(op.target, SITE_THREAT_M), 1.0)
		if living.size() < threat * CALL_OFF_RATIO:
			op.state = "called off"
			op.why = "%d left against %.1f" % [living.size(), threat]
			var home: Vector3 = op.rally
			for m: ZoneModule in level.call(&"modules"):
				if m.module_id == op.base:
					home = m.global_position
			var route: Array[Vector3] = [response._ground(home)]
			response._set_route(op.squad, living, route)
		elif threat_cp(op.target, SITE_THREAT_M) <= 0.0 and living.any(func(s: Soldier) -> bool: return s.global_position.distance_to(op.target) <= 30.0):
			op.state = "done"
			op.why = "retaken"


func _nearest_base(pos: Vector3) -> ZoneModule:
	var bases := response._living_sites("qrf_base", pos)
	if not bases.is_empty():
		return bases[0]
	return response._hq()
