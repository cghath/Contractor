class_name UrbanDefence
extends Node
## How a town's garrison fights (Captain, 2026-10-17: "urban combat feels not urban, its mostly
## firefights from outside to into the town and a small bits of action when clearing the few
## remaining enemies"). The town itself holds men deep inside its blocks (BuildingGen deep
## posts, back rows, alleys, barricades); this node moves them once the town is in the fight:
##
## - Reserve: the town's reserve (its two crossroads posts, ZoneModules.town_reserve) leaves its
##   post when the town's area is ENGAGED and goes to the fallback point (a building's back room)
##   nearest the squad's last known position (LKP): the side being hit gets reinforced.
## - Falling back: a defender within FALLBACK_NEAR_M of the LKP who is hurt (blood under
##   FALLBACK_BLOOD) or whose buddy is down bounds back to the nearest fallback point at least
##   FALLBACK_GAIN_M farther from the LKP than he is, at most FALLBACK_MAX times; the fight
##   moves through the streets instead of ending at the edge.
## - Relief: in a hot zone the commander (EnemyCommand) sends one relief counterattack into the
##   town's streets the first time it's engaged (RELIEF_RATIO of its estimate of the squad there).
##   A town lost is the commander's like any site (EnemyCommand.SITE_TYPES): probed, reoccupied
##   or counterattacked.
## Host only; one node per zone ("UrbanDefence", ZoneLevel), every TICK_S. Proposed numbers.

const TICK_S := 2.0
const FALLBACK_NEAR_M := 35.0
const FALLBACK_BLOOD := 0.8
const FALLBACK_GAIN_M := 12.0
const FALLBACK_MAX := 2
const RELIEF_RATIO := 2.0
const NEAR_TOWN_M := 120.0

var level: Node3D
var alert: Alert
var response: EnemyResponse
var _tick := 0.0
var _reserve_sent := {}   # module id -> true
var _relief_sent := {}    # module id -> true
var _teams := 0


func _init() -> void:
	name = "UrbanDefence"


func _ready() -> void:
	level = get_parent() as Node3D
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	response = level.get_node_or_null(^"EnemyResponse") as EnemyResponse if level else null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()


func server_tick() -> void:
	if not multiplayer.is_server() or level == null or alert == null or response == null or alert.lkp.is_empty():
		return
	var lkp: Vector3 = alert.lkp.pos
	var ai := level.get(&"ai") as Node
	if ai == null:
		return
	for m: ZoneModule in level.call(&"modules"):
		if ZoneModules.base(m.type) != "town" or alert.state_of(m.module_id) < Alert.State.ENGAGED:
			continue
		var half: Vector2 = ZoneModules.HALF.get(m.type, Vector2(50, 30))
		if lkp.distance_to(m.global_position) > half.length() + NEAR_TOWN_M:
			continue
		var points: Array[Vector3] = []
		for p: Vector3 in ZoneModules.town_fallback(m.type):
			points.append(m.to_global(p))
		if points.is_empty():
			continue
		var reserve: Array = ZoneModules.town_reserve(m.type)
		if not _reserve_sent.has(m.module_id):
			_reserve_sent[m.module_id] = true
			var men: Array = []
			for i: int in reserve:
				var s := ai.get_node_or_null(NodePath(String(level.call(&"_garrison_callsign", m, i)))) as Soldier
				if s and s.vitals.is_up():
					men.append(s)
			if not men.is_empty():
				_move(men, _nearest(points, lkp), "RS_%s" % m.module_id)
				print("[urban] %s: reserve (%d) to the side being hit" % [m.module_id, men.size()])
		var size := int(level.get(&"_garrisoned").get(m.module_id, 0)) if level.get(&"_garrisoned") else 0
		for i in size:
			if i in reserve:
				continue
			var s := ai.get_node_or_null(NodePath(String(level.call(&"_garrison_callsign", m, i)))) as Soldier
			if s == null or not s.vitals.is_up() or s.is_in_group(Soldier.DEAD_GROUP) or int(s.get_meta(&"fell_back", 0)) >= FALLBACK_MAX:
				continue
			var d := s.global_position.distance_to(lkp)
			if d > FALLBACK_NEAR_M:
				continue
			var buddy_down := s.buddy != null and (not is_instance_valid(s.buddy) or not s.buddy.vitals.is_up())
			if not buddy_down and s.vitals.blood_fraction() >= FALLBACK_BLOOD:
				continue
			var to := _fallback_from(points, s.global_position, lkp, d)
			if not to.is_finite():
				continue
			s.set_meta(&"fell_back", int(s.get_meta(&"fell_back", 0)) + 1)
			_move([s], to, "FB_%s" % m.module_id)
		var relief_key := ZoneModules.city_of(m.type) if ZoneModules.city_of(m.type) != "" else m.module_id  # (a city: one relief for all its blocks)
		if not _relief_sent.has(relief_key):
			var command := EnemyCommand.of(self)
			if command and command.can_decide():
				_relief_sent[relief_key] = true
				var threat := maxf(command.threat_cp(m.global_position, half.length() + NEAR_TOWN_M), EnemyCommand.SQUAD_MAN_CP)
				command._launch_counterattack(m, threat, command.applied_ratio(RELIEF_RATIO), "relief of %s" % m.module_id, false)


## The nearest point of `points` to `from` at least FALLBACK_GAIN_M farther from `threat` than
## `now_d`; Vector3.INF with none.
func _fallback_from(points: Array[Vector3], from: Vector3, threat: Vector3, now_d: float) -> Vector3:
	var best := Vector3.INF
	for p: Vector3 in points:
		if p.distance_to(threat) < now_d + FALLBACK_GAIN_M:
			continue
		if not best.is_finite() or p.distance_to(from) < best.distance_to(from):
			best = p
	return best


static func _nearest(points: Array[Vector3], to: Vector3) -> Vector3:
	var best: Vector3 = points[0]
	for p: Vector3 in points:
		if p.distance_to(to) < best.distance_to(to):
			best = p
	return best


## `men` leave their posts for `to` as a team of their own (they hold there).
func _move(men: Array, to: Vector3, callsign: String) -> void:
	_teams += 1
	var squad := response._new_squad(("%s_%d" % [callsign, _teams]).validate_node_name())
	for s: Soldier in men:
		var brain := SquadAI.of(s)
		if brain:
			brain.guard = false
			brain.squad = squad
	var route: Array[Vector3] = [to]
	response._set_route(squad, men, route)
