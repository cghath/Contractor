class_name ZombieAI
extends Node
## Host-only brain for one of the dead (docs/survival.md S2). Like CivilianAI it only writes the
## body's intent fields (move_input, want_sprint, rotation); the body is a Soldier in faction
## INFECTED with Vitals.undead (the head kills, anything else wears the pool down).
##
## - Idle: shuffles about where it stands, now and then a few steps somewhere near.
## - Hears (Survival.server_noise: shots, doors, cars): goes to the sound and looks about there.
## - Sees (SIGHT_M by day, NIGHT_SIGHT_M at night, half as far for a crouched or prone man): goes
##   for him, a walker at its shamble, a runner flat out; the dead within GROUP_M of it come too.
## - Reaches (ATTACK_M): a bite or a blow every ATTACK_S (Melee.server_strike).
## - Loses him (out of sight LOSE_S): goes where it saw him last, then idles there.
## Thinks every THINK_S (a sight check and a path), steers every physics frame.

const INFECTED := &"infected"
## The kinds (data/zombies.json in time; Proposed): a walker's shamble (share of the run), a
## runner's sprint, at night a walker's a little faster.
const KINDS := {
	"walker": {"walk": 0.3, "chase": 0.38, "sprint": false, "pool": 12.0},
	"runner": {"walk": 0.32, "chase": 1.0, "sprint": true, "pool": 9.0},
}
const NIGHT_WALK_MULT := 1.25
const SIGHT_M := 40.0
const NIGHT_SIGHT_M := 15.0
const LOW_SIGHT_MULT := 0.5
const SHOT_HEARD_M := 180.0
const SUPPRESSED_HEARD_M := 40.0
const GROUP_M := 12.0
const ATTACK_M := 1.5
const ATTACK_S := 1.3
const LOSE_S := 6.0
const THINK_S := 0.4
const SEARCH_S := 12.0
const ARRIVE_M := 1.5
const WANDER_M := 8.0
const TURN_RATE := 6.0

enum Mode { IDLE, INVESTIGATE, CHASE, SEARCH }

var body: Soldier
var kind := "walker"
var mode := Mode.IDLE
var target: Soldier
var goal := Vector3.INF
var _path := PackedVector3Array()
var _path_index := 0
var _think := 0.0
var _attack_at := 0.0
var _seen_at := -100.0
var _search_until := 0.0
var _idle_next := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	body = get_parent() as Soldier
	_rng.seed = hash(String(body.name))
	_think = _rng.randf() * THINK_S  # (not every one on the same frame)
	_idle_next = Soldier._now() + _rng.randf_range(1.0, 6.0)


## The brain on `s`, or null.
static func of(s: Node) -> ZombieAI:
	return s.get_node_or_null(^"ZombieAI") as ZombieAI if s else null


## Host: a sound at `pos` this one can hear: unless it's after someone, it goes to look.
func hear(pos: Vector3) -> void:
	if mode == Mode.CHASE:
		return
	mode = Mode.INVESTIGATE
	_set_goal(pos)


func _physics_process(delta: float) -> void:
	if body == null or not body.vitals.is_up():
		if body:
			body.move_input = Vector2.ZERO
		return
	_think -= delta
	if _think <= 0.0:
		_think = THINK_S
		_decide()
	_steer(delta)


func _decide() -> void:
	var now := Soldier._now()
	var seen := _spot()
	if seen != null:
		if target != seen:
			_rally(seen)
		target = seen
		mode = Mode.CHASE
		_seen_at = now
		_set_goal(seen.global_position)
	elif mode == Mode.CHASE:
		if not is_instance_valid(target) or not target.vitals.is_up() or now - _seen_at > LOSE_S:
			mode = Mode.SEARCH
			_search_until = now + SEARCH_S
			target = null
	if mode == Mode.CHASE and is_instance_valid(target):
		_set_goal(target.global_position)
		if _flat(target.global_position) <= ATTACK_M and now >= _attack_at:
			_attack_at = now + ATTACK_S
			Melee.server_strike(body, target)
	elif mode in [Mode.INVESTIGATE, Mode.SEARCH]:
		if goal == Vector3.INF or _flat(goal) <= ARRIVE_M:
			if mode == Mode.INVESTIGATE:
				mode = Mode.SEARCH
				_search_until = now + SEARCH_S
			elif now >= _search_until:
				mode = Mode.IDLE
				goal = Vector3.INF
			else:
				_wander()
	elif mode == Mode.IDLE and now >= _idle_next:
		_idle_next = now + _rng.randf_range(4.0, 12.0)
		_wander()


## The nearest living non-infected this one can see now, or null.
func _spot() -> Soldier:
	var night := DayNight.current() != null and DayNight.current().darkness() > 0.5
	var reach := NIGHT_SIGHT_M if night else SIGHT_M
	var eye := body.global_position + Vector3.UP * 1.6
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == INFECTED or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		var r := reach * (LOW_SIGHT_MULT if s.movement and (s.movement.is_crouched() or s.movement.is_prone()) else 1.0)
		if is_instance_valid(target) and s == target:
			r *= 1.5  # (one it's after is easier to keep in sight)
		var d := body.global_position.distance_to(s.global_position)
		if d > r or d >= best_d:
			continue
		if d > ATTACK_M * 2.0 and not Throwables.clear_line(body.get_world_3d(), eye, s.global_position + Vector3.UP * 1.4):
			continue
		best = s
		best_d = d
	return best


## The dead about this one join the chase.
func _rally(who: Soldier) -> void:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != INFECTED or s.global_position.distance_to(body.global_position) > GROUP_M:
			continue
		var other := ZombieAI.of(s)
		if other and other.mode != Mode.CHASE:
			other.target = who
			other.mode = Mode.CHASE
			other._seen_at = Soldier._now()
			other._set_goal(who.global_position)


func _wander() -> void:
	var a := _rng.randf() * TAU
	_set_goal(body.global_position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.0, WANDER_M))


func _set_goal(at: Vector3) -> void:
	if goal != Vector3.INF and goal.distance_to(at) < 1.0 and not _path.is_empty():
		goal = at
		return
	goal = at
	var map := body.get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, body.global_position, at, true)
	_path_index = 0


func _steer(delta: float) -> void:
	if goal == Vector3.INF or _flat(goal) <= (ATTACK_M * 0.8 if mode == Mode.CHASE else ARRIVE_M):
		body.move_input = Vector2.ZERO
		body.want_sprint = false
		if mode == Mode.CHASE and is_instance_valid(target):
			_face(target.global_position, delta)
		return
	while _path_index < _path.size() and _flat(_path[_path_index]) < 0.8:
		_path_index += 1
	var next := _path[_path_index] if _path_index < _path.size() else goal
	var dir := next - body.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		body.move_input = Vector2.ZERO
		return
	dir = dir.normalized()
	var k: Dictionary = KINDS.get(kind, KINDS.walker)
	var night := DayNight.current() != null and DayNight.current().darkness() > 0.5
	var pace := float(k.chase) if mode == Mode.CHASE else float(k.walk)
	if not bool(k.sprint) or mode != Mode.CHASE:
		pace *= NIGHT_WALK_MULT if night else 1.0
	_face(body.global_position + dir, delta)
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z) * clampf(pace, 0.0, 1.0)
	body.want_sprint = bool(k.sprint) and mode == Mode.CHASE


func _face(at: Vector3, delta: float) -> void:
	var to := at - body.global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-TURN_RATE * delta))


func _flat(p: Vector3) -> float:
	return Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length()
