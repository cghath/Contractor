class_name Bombers
extends Node
## Suicide bombers on foot (wave 6f; Captain, 2026-10-11: "where it fits best in the roadmap",
## the insurgents' behaviour). A hostile with no rifle in a bulky heavy vest walks straight at
## the squad, ignoring cover, and at TRIGGER_M from any of them sets off the charge he wears
## (Charges: placed on him and fired at once, the same blast as a breaching charge). Shot down
## first, nothing goes off. The tells are his: no weapon, the heavy vest, the straight walk.
## Counterplay: spot him, shoot early.
##
## Host only; one per zone ("Bombers", ZoneLevel). Only factions whose kit is the insurgents'
## (Kits.INSURGENT) send them: from Pressure tier MIN_TIER, or any time the faction is hunting
## the squad (Economy.hunting), at most one every GAP_S, from an unseen spot SEND_M away
## [min, max] (EnemyResponse._unseen). All numbers Proposed.

const TICK_S := 0.5
const TRIGGER_M := 7.0
const MIN_TIER := 2
const GAP_S := 600.0
const SEND_M := [150.0, 250.0]
const CHANCE_PER_CHECK := 0.1
const CHECK_S := 30.0
const KIT: Array[String] = ["plate_carrier_heavy", "assault_pack"]

## Host: bombers out: {"soldier", "squad"}; and how many went off (tests, the session log).
var out: Array[Dictionary] = []
var detonated := 0
var _tick := 0.0
var _check := 0.0
var _last_sent := -INF
var _n := 0


func _init() -> void:
	name = "Bombers"


static func of(from: Node) -> Bombers:
	var lvl := CompoundLevel.current(from)
	return lvl.get_node_or_null(^"Bombers") as Bombers if lvl else null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_S
		_maybe_send()


## Host: every bomber out walks at the nearest of the squad; close enough, he goes off.
func server_tick() -> void:
	var targets := _targets()
	for b: Dictionary in out.duplicate():
		var s: Soldier = b.soldier if is_instance_valid(b.soldier) else null
		if s == null or not s.vitals.is_up():
			out.erase(b)  # stopped in time
			continue
		var near: Soldier = null
		var best := INF
		for t in targets:
			var d := t.global_position.distance_to(s.global_position)
			if d < best:
				best = d
				near = t
		if near == null:
			continue
		if best <= TRIGGER_M:
			_go_off(b)
			continue
		var route: Array[Vector3] = [near.global_position]
		if is_instance_valid(b.squad):
			(b.squad as Squad).patrol = route
			var brain := SquadAI.of(s)
			if brain:
				brain._patrol_index = 0


## Host: a bomber sets out from `at` (on the ground), walking at the squad. Returns him.
func server_send(at: Vector3) -> Soldier:
	var lvl := get_parent() as CompoundLevel
	if lvl == null:
		return null
	_n += 1
	var squad := Squad.new()
	squad.name = "Bomber%d" % _n
	squad.faction = &"hostile"
	add_child(squad)
	var s: Soldier = lvl.spawn_soldier({"name": "Bomber%d_1" % _n, "faction": "hostile", "variant": "urban", "pos": at,
		"loadout": KIT, "combat": 0.2, "discipline": 1.0, "guard": false, "mode": "safe"})
	if s == null:
		squad.queue_free()
		return null
	var brain := SquadAI.of(s)
	if brain:
		brain.squad = squad
	out.append({"soldier": s, "squad": squad})
	_last_sent = Soldier._now()
	print("[bombers] %s sets out from (%.0f, %.0f)" % [s.name, at.x, at.z])
	return s


func _go_off(b: Dictionary) -> void:
	out.erase(b)
	var s: Soldier = b.soldier
	var charges := Charges.of(self)
	detonated += 1
	print("[bombers] %s goes off at (%.0f, %.0f)" % [s.name, s.global_position.x, s.global_position.z])
	if charges:
		var id := charges.server_place_at(null, Transform3D(s.global_basis, s.global_position + Vector3.UP * 1.2), s)
		if id != "":
			charges._detonate(id)
	if s.vitals.is_up():
		s.vitals.server_damage(1000.0)  # (whatever the blast left of him)


## Host, every CHECK_S: maybe a bomber, when the zone's enemy is an insurgent faction that's
## been pushed (tier) or is hunting the squad.
func _maybe_send() -> void:
	var response := get_parent().get_node_or_null(^"EnemyResponse") as EnemyResponse
	var pressure := get_parent().get_node_or_null(^"Pressure") as Pressure
	if response == null or Kits.kit_of(response.enemy_faction) != Kits.INSURGENT:
		return
	var tier := pressure.tier() if pressure else 0
	if tier < MIN_TIER and not Economy.hunting(String(response.enemy_faction)):
		return
	if Soldier._now() - _last_sent < GAP_S or not out.is_empty() or randf() > CHANCE_PER_CHECK:
		return
	var targets := _targets()
	if targets.is_empty():
		return
	var centre := targets[0].global_position
	for k in 8:
		var a := randf() * TAU
		var at := response._ground(centre + Vector3(cos(a), 0.0, sin(a)) * randf_range(float(SEND_M[0]), float(SEND_M[1])))
		if response._hidden(at):
			server_send(at)
			return


func _targets() -> Array[Soldier]:
	var all: Array[Soldier] = MapNodes.players(self)
	all.append_array(MapNodes.squad_ai(self))
	return all.filter(func(t: Soldier) -> bool: return is_instance_valid(t) and t.vitals.is_up())
