class_name CivilianAI
extends Node
## Host-only brain for someone who never fights (wave 4, W11): a civilian, an HVT, or a hostile
## who gave up. Like SquadAI it only writes the body's intent fields (move_input, want_sprint,
## want_stance, want_aim), and it's named PeopleLayer.BRAIN ("PersonAI") on the body.
##
## - Routine: walks between its routine points around the buildings at a stroll, idling a few
##   seconds at each (with no routine, a civilian wanders near home and an HVT stays there).
## - Gunfire: shots heard nearby (PeopleLayer.server_noise), rounds passing close
##   (Soldier.threat_pos from Ballistics) or a wound set it running to a spot the threat can't
##   see (the navmesh, rings around it), where it cowers (crouched low) until COWER_S after
##   the last shot, then goes back to its routine. Some shout as they run.
## - Orders (from the interaction menu, through PeopleLayer's replicated state): "follow" goes
##   after whoever leads it, "stop" holds where it is, "cover" finds cover from the last threat
##   and gets down there. Captives with no order stay put: a surrendered one standing, a cuffed
##   one kneeling.
## - Seated in a vehicle (the hook PeopleLayer.server_seat_in_vehicle): it rides along.
## It has no weapon and never shoots.

enum Mode { ROUTINE, FLEE, COWER, FOLLOW, HOLD, COVER, SEATED }

const THINK_S := 0.3
## Proposed: a frightened civilian stays hidden this long after the last shot.
const COWER_S := 25.0
## Hiding spots are searched on these rings around the body, in HIDE_DIRECTIONS directions.
const HIDE_RINGS: Array[float] = [3.0, 6.0, 9.0, 12.0, 16.0]
const HIDE_DIRECTIONS := 12
## With nowhere hidden, it runs this far straight away from the threat.
const FLEE_FALLBACK_M := 14.0
## Following: keeps about this far behind the leader, running when further than FOLLOW_RUN_M.
const FOLLOW_GAP_M := 2.0
const FOLLOW_RUN_M := 6.0
const ARRIVE := 0.6
const WAYPOINT_REACH := 0.45
const REPATH_S := 1.0
const TURN_RATE := 6.0
## Seconds idling at each routine point (min, max).
const IDLE_S := Vector2(3.0, 8.0)
## With no routine, it wanders within this far of home.
const WANDER_M := 6.0
const WORLD_MASK := 1
## What a frightened civilian shouts (subtitles for players close by), at most once per PANIC_GAP_S.
const PANIC_LINES: Array[String] = ["Don't shoot!", "Help!", "Please, no!", "Get down!"]
const PANIC_GAP_S := 12.0

var body: Soldier
## Routine points (Vector3), set by PeopleLayer before the brain enters the tree.
var routine: Array = []
var kind := Person.CIVILIAN
var side := Person.NEUTRAL
var mode := Mode.ROUTINE
## Where the last threat came from, and when (Soldier._now()).
var threat_pos := Vector3.ZERO
var threat_at := -1000.0

var _ready_done := false
var _think_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _path := PackedVector3Array()
var _path_index := 0
var _path_target := Vector3.INF
var _repath_cd := 0.0
var _destination := Vector3.ZERO
var _has_destination := false
var _run := false
var _routine_index := 0
var _idle_until := 0.0
var _idling := false
var _hide := Vector3.ZERO
var _has_hide := false
var _hold := Vector3.ZERO
var _home := Vector3.ZERO
var _cover := Vector3.ZERO
var _has_cover := false
var _order_seen := "-"
var _seen_threat_time := -1000.0
var _last_injury := 0.0
var _panic_at := -1000.0


func _physics_process(delta: float) -> void:
	if not _ready_done:
		_setup()
		return
	if body.vitals.is_dead():
		_stop()
		set_physics_process(false)
		return
	if not body.vitals.is_up() or is_instance_valid(body.carried_by):
		_stop()
		body.ai_status = body.vitals.condition_text() if not body.vitals.is_up() else "Carried"
		return
	_notice()
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_S
		_decide()
	_act()
	_steer(delta)
	body.ai_status = status_text()


func _setup() -> void:
	body = get_parent() as Soldier
	if body == null or not body.is_node_ready():
		return
	_rng.seed = String(body.name).hash()
	_home = body.global_position
	_hold = body.global_position
	_ready_done = true


## Host: a shot or blast at `pos` was heard (PeopleLayer.server_noise).
func hear(pos: Vector3) -> void:
	alarm(pos)


## Something dangerous happened at `pos`: hide from it (a civilian), or remember it (orders).
func alarm(pos: Vector3) -> void:
	var fresh := Soldier._now() - threat_at > 2.0
	threat_pos = pos
	threat_at = Soldier._now()
	if fresh:
		_think_cd = 0.0  # react now
		if _has_hide and not _hides_from(_hide, pos):
			_has_hide = false


## Recently frightened (within COWER_S of the last threat).
func threatened() -> bool:
	return Soldier._now() - threat_at < COWER_S


func status_text() -> String:
	match mode:
		Mode.FLEE:
			return "Fleeing"
		Mode.COWER:
			return "Hiding"
		Mode.FOLLOW:
			return "Following"
		Mode.HOLD:
			return "Cuffed" if Person.is_cuffed(body) else ("Surrendered" if Person.is_captive(body) else "Waiting")
		Mode.COVER:
			return "In cover"
		Mode.SEATED:
			return "Seated"
	return "Idle" if _idling else "Walking"


# --- Deciding ------------------------------------------------------------------------------

## Notices rounds passing close and wounds (both come with a direction).
func _notice() -> void:
	if body.threat_time > _seen_threat_time:
		_seen_threat_time = body.threat_time
		alarm(body.threat_pos)
	var injury := body.vitals.injury()
	if injury > _last_injury + 0.01:
		var harm := Harm.last(body)
		var from: Variant = null
		if not harm.is_empty():
			var attacker := get_node_or_null(NodePath(String(harm.get("path", "")))) as Node3D
			if attacker:
				from = attacker.global_position
		alarm(from if from != null else body.global_position + body.global_basis.z * 5.0)
	_last_injury = injury


func _decide() -> void:
	var st := Person.state(body)
	var order := String(st.get("order", ""))
	# A new order, or he just gave up (or was brought in): hold where he is now, not where an
	# older order found him (an HVT who ran, then surrendered, walked back to where he started).
	var seen := order + ("|captive" if Person.is_captive(body) or bool(st.get("delivered", false)) else "")
	if seen != _order_seen:
		_order_seen = seen
		_hold = body.global_position
		_has_cover = false
	if String(st.get("seated_in", "")) != "":
		mode = Mode.SEATED
		return
	match order:
		"follow":
			if _leader(st) != null:
				mode = Mode.FOLLOW
				return
		"stop":
			mode = Mode.HOLD
			return
		"cover":
			mode = Mode.COVER
			return
	if Person.is_captive(body) or bool(st.get("delivered", false)):
		mode = Mode.HOLD
		return
	_decide_free()


## No orders and not a captive: hide while frightened, else the routine. HvtAI overrides it.
func _decide_free() -> void:
	if threatened():
		if not _has_hide:
			_find_hide()
		if mode != Mode.COWER or _flat(_hide) > ARRIVE + 1.0:
			mode = Mode.FLEE if _flat(_hide) > ARRIVE + 0.3 else Mode.COWER
		if mode == Mode.FLEE:
			_panic()
		return
	if mode in [Mode.FLEE, Mode.COWER]:
		_has_hide = false
		_idle_until = 0.0
	mode = Mode.ROUTINE


## Who leads this person (state "led_by"), if they're still up; else null.
func _leader(st: Dictionary) -> Soldier:
	var path := String(st.get("led_by", ""))
	if path == "":
		return null
	var layer := PeopleLayer.find(body)
	var leader := layer.get_parent().get_node_or_null(NodePath(path)) as Soldier if layer else null
	return leader if leader and not leader.is_queued_for_deletion() and leader.vitals.is_up() else null


# --- Acting --------------------------------------------------------------------------------

func _act() -> void:
	body.want_stance = -1
	body.want_crouch = false
	body.want_aim = false
	body.want_sprint = false
	match mode:
		Mode.ROUTINE:
			_routine()
		Mode.FLEE:
			_go(_hide, true)
			if _flat(_hide) <= ARRIVE + 0.3:
				mode = Mode.COWER
		Mode.COWER:
			_has_destination = false
			body.want_stance = SoldierMovement.Stance.CROUCH_LOW
		Mode.FOLLOW:
			_follow()
		Mode.HOLD:
			_go(_hold, false)
			if Person.is_cuffed(body):
				body.want_stance = SoldierMovement.Stance.CROUCH_MID  # kneeling, hands behind
			elif threatened() and not Person.is_captive(body):
				body.want_stance = SoldierMovement.Stance.CROUCH_LOW
		Mode.COVER:
			_take_cover()
		Mode.SEATED:
			_ride()


func _routine() -> void:
	var now := Soldier._now()
	if _idling:
		_has_destination = false
		if now < _idle_until:
			return
		_idling = false
		_routine_index += 1
	var point := _routine_point()
	_go(point, false)
	body.want_aim = true  # a stroll: the aiming pace (SoldierMovement.top_speed)
	if _flat(point) <= ARRIVE + 0.3:
		_idling = true
		_idle_until = now + _rng.randf_range(IDLE_S.x, IDLE_S.y)


func _routine_point() -> Vector3:
	if not routine.is_empty():
		return routine[_routine_index % routine.size()]
	if kind != Person.CIVILIAN:
		return _home  # an HVT (or a captive) with no routine stays where he was put
	# No routine: somewhere near home, picked again at each stop.
	if not _has_destination or _flat(_destination) <= ARRIVE + 0.3:
		var angle := _rng.randf() * TAU
		var p := _home + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(1.5, WANDER_M)
		return NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, p)
	return _destination


func _follow() -> void:
	var leader := _leader(Person.state(body))
	if leader == null:
		_has_destination = false
		return
	var gap := _flat(leader.global_position)
	if gap > FOLLOW_GAP_M + 0.5:
		var behind := leader.global_position + (body.global_position - leader.global_position).normalized() * FOLLOW_GAP_M
		_go(behind, gap > FOLLOW_RUN_M)
	else:
		_has_destination = false
		_face(leader.global_position)
		if threatened():
			body.want_stance = SoldierMovement.Stance.CROUCH_MID


func _take_cover() -> void:
	if not _has_cover:
		var from := threat_pos if threat_at > -999.0 else body.global_position - body.global_basis.z * 10.0
		var spot: Variant = _hiding_spot(from, [2.0, 4.0, 6.0, 8.0])
		_cover = spot if spot != null else body.global_position
		_has_cover = true
	_go(_cover, true)
	if _flat(_cover) <= ARRIVE + 0.3:
		_has_destination = false
		body.want_stance = SoldierMovement.Stance.CROUCH_LOW


## Seated in a vehicle (PeopleLayer.server_seat_in_vehicle): rides at the seat it names, if
## the vehicle has a seat_transform(seat); otherwise it stays where it is.
func _ride() -> void:
	_has_destination = false
	var st := Person.state(body)
	var layer := PeopleLayer.find(body)
	var vehicle := layer.get_parent().get_node_or_null(NodePath(String(st.get("seated_in", "")))) if layer else null
	if vehicle and vehicle.has_method(&"seat_transform"):
		body.global_transform = vehicle.seat_transform(String(st.get("seat", "")))
		body.velocity = Vector3.ZERO


func _panic() -> void:
	if kind != Person.CIVILIAN or Soldier._now() - _panic_at < PANIC_GAP_S:
		return
	_panic_at = Soldier._now()
	var layer := PeopleLayer.find(body)
	if layer:
		layer.server_say(body, PANIC_LINES[_rng.randi() % PANIC_LINES.size()])


# --- Hiding --------------------------------------------------------------------------------

func _find_hide() -> void:
	var spot: Variant = _hiding_spot(threat_pos, HIDE_RINGS)
	if spot == null:
		var away := body.global_position - threat_pos
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else -body.global_basis.z
		spot = NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, body.global_position + away * FLEE_FALLBACK_M)
	_hide = spot
	_has_hide = true


## The best spot on the navmesh around this body that `from` can't see, not closer to it
## than this body is (nearest first, then further from the threat); null if none.
func _hiding_spot(from: Vector3, rings: Array) -> Variant:
	var map := body.get_world_3d().navigation_map
	var mine := _flat_between(body.global_position, from)
	var best: Variant = null
	var best_score := INF
	for ring: float in rings:
		for k in HIDE_DIRECTIONS:
			var angle := TAU * k / HIDE_DIRECTIONS + ring * 0.37
			var p := body.global_position + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.6:
				continue
			var away := _flat_between(q, from)
			if away < mine - 0.5 or not _hides_from(q, from):
				continue
			var score := _flat(q) - away * 0.4
			if score < best_score:
				best = q
				best_score = score
	return best


func _hides_from(point: Vector3, from: Vector3) -> bool:
	return not Throwables.clear_line(body.get_world_3d(), from + Vector3.UP * 1.5, point + Vector3.UP * 1.0)


# --- Steering (as SquadAI) -------------------------------------------------------------------

func _go(point: Vector3, run := false) -> void:
	_destination = point
	_has_destination = true
	_run = run


func _steer(delta: float) -> void:
	var dir := Vector3.ZERO
	_repath_cd -= delta
	if _has_destination and _flat(_destination) > ARRIVE:
		if _repath_cd <= 0.0 or _path_target.distance_to(_destination) > 0.5:
			_repath_cd = REPATH_S
			_path_target = _destination
			_path = NavigationServer3D.map_get_path(body.get_world_3d().navigation_map, body.global_position, _destination, true)
			_path_index = 0
		while _path_index < _path.size() and _flat(_path[_path_index]) < WAYPOINT_REACH:
			_path_index += 1
		var next := _path[_path_index] if _path_index < _path.size() else _destination
		dir = next - body.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.ZERO
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z)
	body.want_sprint = _run and dir != Vector3.ZERO and body.want_stance < 0
	if dir != Vector3.ZERO:
		body.want_aim = body.want_aim and not _run
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * delta))
	body.head.rotation.x = lerpf(body.head.rotation.x, 0.0, 0.1)


func _face(point: Vector3) -> void:
	var d := point - body.global_position
	if Vector2(d.x, d.z).length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-d.x, -d.z), 0.15)


func _stop() -> void:
	_has_destination = false
	if body:
		body.move_input = Vector2.ZERO
		body.want_sprint = false
		body.want_aim = false


func _flat(point: Vector3) -> float:
	return _flat_between(body.global_position, point)


static func _flat_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
