class_name VehicleAI
extends Node
## The AI at a vehicle's wheel (wave 5, host only): drives along a path to a point, slows for
## the turns and the end, stops there with the brakes on, and avoids obvious obstacles (walls,
## other vehicles, people in the way) by easing round them or stopping; a stuck vehicle backs
## off and tries again. It writes throttle, steer and brake into Vehicle.set_ai_input each
## physics step; Vehicle drives with them unless a player holds the driver's seat.
##
## Paths: drive_to() asks the level's navigation map for a path (the navmesh the squad walks
## on) and drives it, or goes straight when there's none; follow() takes waypoints as given
## (roads, a route V4 plans). Proposed numbers; road following is later work. V3 and V4 build
## on drive_to / follow / stop through Vehicle.server_drive_to, server_follow_path, server_stop.
##
## Part 2 of the squad's drivers (2026-10-20): it slows in time for the next corner, not only
## once it's in it; a wall (or a wreck) dead ahead that doesn't go away, or being stuck twice
## at one spot, backs it off and sends it round by a detour (two waypoints off to the clearer
## side, wider each time); and with give_up_tries set (SquadDrivers sets it) it gives up after
## that many tries without getting anywhere: status "stuck" and gave_up, so whoever ordered it
## can plan another way. steer_to() changes the path without forgetting any of that (a convoy's
## driver gets a fresh place every quarter second).

## Host: it tried give_up_tries times at one spot and stopped (status "stuck").
signal gave_up

## Cruise speed as a share of the vehicle's top speed, and its cap (m/s).
const CRUISE_SHARE := 0.55
const CRUISE_MAX_MS := 14.0
## A waypoint counts as reached this close (m); the last one: ARRIVE_M.
const WAYPOINT_M := 4.0
const ARRIVE_M := 3.0
## Full steering lock for a target this far off the nose.
const FULL_STEER_DEG := 35.0
## Slows to TURN_SPEED_SHARE of cruise for a waypoint more than TURN_SLOW_DEG off the nose.
const TURN_SLOW_DEG := 40.0
const TURN_SPEED_SHARE := 0.35
## Looks ahead this far (m, plus 1.2 s of travel) for obstacles, from bumper height.
const LOOK_AHEAD_M := 4.0
const LOOK_SPREAD_DEG := 22.0
const OBSTACLE_MASK := 1 | Vehicle.LAYER | Soldier.BODY_LAYER
## Stuck: trying to move but slower than STUCK_MS for STUCK_S, then backs off for BACKOFF_S.
const STUCK_MS := 0.3
const STUCK_S := 3.0
const BACKOFF_S := 1.6
## A navmesh path whose end is further than this from the target isn't used (straight instead).
const PATH_SLACK_M := 6.0
## Blocked this long by a wall (the world, a wreck) dead ahead, or this long by anything (a
## parked vehicle, people who won't move): it backs off and goes round.
const BLOCKED_WALL_S := 3.0
const BLOCKED_ANY_S := 10.0
## Stuck backoffs at one spot before it goes round (a wall seen ahead: the first).
const DETOUR_AFTER := 2
## Before going round it backs off straight until this far (m) back, or for BACKOFF_WALL_S: room
## to turn out before what stopped it.
const BACKOFF_WALL_M := 9.0
const BACKOFF_WALL_S := 6.0
## A detour: off to the side this far (wider by half each time at one spot) and DETOUR_OUT_M on,
## then on past where it was stopped by DETOUR_AHEAD_M. Two tries a side, then the other side.
const DETOUR_SIDE_M := 12.0
const DETOUR_OUT_M := 6.0
const DETOUR_AHEAD_M := 14.0
const SIDE_TRIES := 2
## Moving this far from where it first got stuck counts as getting somewhere (the tries reset).
const PROGRESS_M := 10.0
## A corner sharper than CORNER_DEG is taken at cruise * (1 - turn / CORNER_FULL_DEG), at least
## CORNER_MIN_SHARE of it, braking for it at CORNER_DECEL m/s2.
const CORNER_DEG := 20.0
const CORNER_FULL_DEG := 120.0
const CORNER_MIN_SHARE := 0.3
const CORNER_DECEL := 3.0
## Corners are looked for this far (m) down the path: a bend traced by many close points (a
## column following its lead's trail) counts as one.
const CORNER_LOOK_M := 40.0

var vehicle: Vehicle
var active := false
## The waypoints in order, and the next one.
var path := PackedVector3Array()
var index := 0
## Why it stopped last ("arrived", "blocked", "stopped"), for tests and the HUD.
var status := "idle"
## The cruise speed asked for (m/s), or -1: CRUISE_SHARE of the vehicle's top speed (capped
## at CRUISE_MAX_MS). Never more than the vehicle can do.
var cruise_ms := -1.0
## The speed is the caller's (steer_to's `paced`: a column's driver keeping its gap): no easing
## in to the last waypoint, and reaching it doesn't end the drive (it brakes and waits there).
var paced := false
## Gives up after this many tries at one spot (backoffs and detours); 0: never (it keeps trying).
var give_up_tries := 0
## Tries at the spot it's stuck at now, and detours taken in all (tests, the HUD).
var stuck_tries := 0
var detours := 0
## Waypoints round whatever stopped it, driven before path[index].
var detour := PackedVector3Array()
var _stuck_s := 0.0
var _blocked_s := 0.0
var _stuck_from := Vector3.INF
var _last_side := 0.0
var _side_tries := 0
var _detour_due := false
var _backoff_from := Vector3.ZERO
var _backoff_s := 0.0
var _backoff_steer := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	vehicle = p_vehicle
	name = "AI"


## Drives to `point` and stops there, at `speed_ms` (m/s; -1: the usual cruise).
func drive_to(point: Vector3, speed_ms := -1.0) -> void:
	var p := PackedVector3Array()
	var map := vehicle.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		p = NavigationServer3D.map_get_path(map, vehicle.global_position, point, true)
	if p.size() < 2 or p[p.size() - 1].distance_to(point) > PATH_SLACK_M:
		p = PackedVector3Array([point])
	else:
		p.remove_at(0)  # where it is now
		if p[p.size() - 1].distance_to(point) > 0.5:
			p.append(point)
	follow(p, speed_ms)


## Drives through `points` in order and stops at the last, at `speed_ms` (m/s; -1: the usual
## cruise).
func follow(points: PackedVector3Array, speed_ms := -1.0) -> void:
	path = points.duplicate()
	cruise_ms = speed_ms
	index = 0
	active = not path.is_empty()
	status = "driving" if active else "idle"
	_stuck_s = 0.0
	_backoff_s = 0.0
	_blocked_s = 0.0
	stuck_tries = 0
	_stuck_from = Vector3.INF
	_last_side = 0.0
	_side_tries = 0
	_detour_due = false
	paced = false
	detour.clear()


## Drives through `points` from now on, as follow() but keeping what it knows of being stuck and
## any detour it's on (a convoy's driver, given a fresh place every step); `p_paced`: at
## `speed_ms` all the way (paced).
func steer_to(points: PackedVector3Array, speed_ms := -1.0, p_paced := false) -> void:
	if points.is_empty():
		stop()
		return
	path = points.duplicate()
	cruise_ms = speed_ms
	paced = p_paced
	index = 0
	if not active:
		_stuck_s = 0.0
		_blocked_s = 0.0
	active = true
	if status != "blocked":
		status = "driving"


func stop() -> void:
	active = false
	status = "stopped"
	if is_instance_valid(vehicle):
		vehicle.set_ai_input(0.0, 0.0, true)


## Distance left to the end of the path (m).
func remaining() -> float:
	if not active or index >= path.size():
		return 0.0
	var d := _flat(vehicle.global_position).distance_to(_flat(path[index]))
	for i in range(index, path.size() - 1):
		d += path[i].distance_to(path[i + 1])
	return d


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(vehicle) or not multiplayer.is_server():
		return
	if vehicle.wrecked:
		stop()
		return
	var pos := vehicle.global_position
	if _stuck_from != Vector3.INF and _flat(pos).distance_to(_flat(_stuck_from)) > PROGRESS_M:
		stuck_tries = 0  # it got somewhere
		_stuck_from = Vector3.INF
		_last_side = 0.0
		_side_tries = 0
	while not detour.is_empty() and _flat(pos).distance_to(_flat(detour[0])) < WAYPOINT_M:
		detour.remove_at(0)
	while index < path.size() - 1 and (_flat(pos).distance_to(_flat(path[index])) < WAYPOINT_M \
			or (_flat(pos) - _flat(path[index])).dot(_flat(path[index + 1]) - _flat(path[index])) > 0.0):
		index += 1  # there, or already past it along the next leg
	var target := detour[0] if not detour.is_empty() else path[index]
	var to := _flat(target) - _flat(pos)
	var dist := to.length()
	var last := detour.is_empty() and index == path.size() - 1
	var speed := vehicle.forward_speed()
	if last and dist < ARRIVE_M:
		vehicle.set_ai_input(0.0, 0.0, true)
		if absf(speed) < 0.3 and not paced:
			active = false
			status = "arrived"
		return
	var forward := -vehicle.global_basis.z
	var fwd2 := Vector2(forward.x, forward.z).normalized()
	var to2 := Vector2(to.x, to.z).normalized()
	var angle := rad_to_deg(fwd2.angle_to(to2))  # positive: the target is to the right
	var steer := clampf(angle / FULL_STEER_DEG, -1.0, 1.0)
	var cruise := minf(vehicle.top_speed() * CRUISE_SHARE, CRUISE_MAX_MS) if cruise_ms <= 0.0 else minf(cruise_ms, vehicle.top_speed())
	var want := cruise
	if absf(angle) > TURN_SLOW_DEG:
		want = cruise * TURN_SPEED_SHARE
	if last and not paced:
		want = minf(want, maxf(dist * 0.45, 1.5))
	elif not last:
		want = minf(want, _corner_speed(target, dist, cruise))
	# Obstacles ahead: ease off and steer round, or stop.
	var block := _obstacles(speed)
	if block.center < INF and block.center < maxf(speed, 1.0) * 1.2 + 2.0:
		want = 0.0
		status = "blocked"
		_blocked_s += delta
	elif block.center < INF:
		want = minf(want, 2.5)
		steer = clampf(steer + (1.0 if block.left < block.right else -1.0) * 0.8, -1.0, 1.0)
	elif block.left < INF or block.right < INF:
		steer = clampf(steer + (0.4 if block.left < block.right else -0.4), -1.0, 1.0)
	if status == "blocked" and block.center == INF:
		status = "driving"
	if status != "blocked":
		_blocked_s = 0.0
	# Stuck: back off with the wheel the other way, then try again (or go round).
	if _backoff_s > 0.0:
		_backoff_s -= delta
		if _detour_due and _flat(pos).distance_to(_flat(_backoff_from)) >= BACKOFF_WALL_M:
			_backoff_s = 0.0
		vehicle.set_ai_input(-0.6, _backoff_steer, false)
		if _backoff_s <= 0.0 and _detour_due:
			_detour_due = false
			_go_round(block)
		return
	if _blocked_s > (BLOCKED_WALL_S if block.wall else BLOCKED_ANY_S) and vehicle.can_drive():
		_blocked_s = 0.0
		_back_off(steer, true)
		return
	if want > 0.5 and absf(speed) < STUCK_MS and vehicle.can_drive():
		_stuck_s += delta
		if _stuck_s > STUCK_S:
			_stuck_s = 0.0
			_back_off(steer, false)
			return
	else:
		_stuck_s = 0.0
	var throttle := 0.0
	var brake := false
	if want <= 0.0:
		brake = true
	elif speed < want - 0.5:
		throttle = clampf((want - speed) / 3.0, 0.3, 1.0)
	elif speed > want + 1.0:
		brake = speed > want + 3.0
	vehicle.set_ai_input(throttle, steer, brake)


## A try at getting unstuck: back off with the wheel the other way; then (`wall` ahead, or the
## DETOUR_AFTER-th try at one spot) go round. Past give_up_tries: stop, "stuck", gave_up.
func _back_off(steer: float, wall: bool) -> void:
	if _stuck_from == Vector3.INF:
		_stuck_from = vehicle.global_position
	stuck_tries += 1
	if give_up_tries > 0 and stuck_tries > give_up_tries:
		stop()
		status = "stuck"
		gave_up.emit()
		return
	_detour_due = wall or stuck_tries >= DETOUR_AFTER
	_backoff_from = vehicle.global_position
	# Going round: straight back for room to turn out. Else a short one, the wheel the other way.
	_backoff_s = BACKOFF_WALL_S if _detour_due else BACKOFF_S
	_backoff_steer = 0.0 if _detour_due else (-signf(steer) if steer != 0.0 else 1.0)


## Two waypoints round what's ahead: out to the clearer side (SIDE_TRIES tries a side from one
## spot, then the other), wider each try, then on past where it was stopped.
func _go_round(block: Dictionary) -> void:
	var fwd := -vehicle.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var side := 1.0 if float(block.right) >= float(block.left) else -1.0
	if _last_side != 0.0:
		side = _last_side if _side_tries < SIDE_TRIES else -_last_side
	_side_tries = _side_tries + 1 if side == _last_side else 1
	_last_side = side
	var wide := DETOUR_SIDE_M * (1.0 + 0.5 * (_side_tries - 1))
	var backed := _flat(vehicle.global_position).distance_to(_flat(_backoff_from))
	var a := vehicle.global_position + right * side * wide + fwd * DETOUR_OUT_M
	detour = PackedVector3Array([a, a + fwd * (backed + DETOUR_AHEAD_M)])
	# The waypoints it's going round (short of the detour's end) are left out: a path planned
	# through what stopped it (a navmesh from before a wreck burned there) mustn't lead it back.
	var origin := _flat(vehicle.global_position)
	while index < path.size() - 1 and (_flat(path[index]) - origin).dot(fwd) < DETOUR_OUT_M + backed + DETOUR_AHEAD_M:
		index += 1
	detours += 1
	status = "driving"


## The fastest it may be going now for the bends in the next CORNER_LOOK_M of the way, from
## `target` (`dist` off) on: each leg turned more than CORNER_DEG from the way to `target` is
## taken slower the sharper it is, braked for in time (INF: nothing worth slowing for).
func _corner_speed(target: Vector3, dist: float, cruise: float) -> float:
	var ahead := PackedVector3Array([target])
	if not detour.is_empty():
		ahead.append_array(detour.slice(1))
		ahead.append_array(path.slice(index))
	else:
		ahead.append_array(path.slice(index + 1))
	var leg_in := _flat(target) - _flat(vehicle.global_position)
	if leg_in.length() < 0.5:
		return INF
	var best := INF
	var along := dist
	for j in ahead.size() - 1:
		var leg := _flat(ahead[j + 1]) - _flat(ahead[j])
		if leg.length() < 0.1:
			continue
		var turn := rad_to_deg(leg_in.angle_to(leg))
		if turn >= CORNER_DEG:
			var corner_ms := cruise * clampf(1.0 - turn / CORNER_FULL_DEG, CORNER_MIN_SHARE, 1.0)
			best = minf(best, sqrt(corner_ms * corner_ms + 2.0 * CORNER_DECEL * along))
		along += leg.length()
		if along > CORNER_LOOK_M:
			break
	return best


## Distances to anything in the way ahead (centre, left, right; INF for clear), and whether what's
## dead ahead is a wall ("wall": the world or a wreck, not a vehicle or people that may move off).
func _obstacles(speed: float) -> Dictionary:
	var out := {"center": INF, "left": INF, "right": INF, "wall": false}
	var size := VehicleArt.size_m(vehicle.model)
	var reach := LOOK_AHEAD_M + maxf(speed, 0.0) * 1.2
	var basis := vehicle.global_basis
	var forward := -basis.z
	var space := vehicle.get_world_3d().direct_space_state
	var exclude: Array[RID] = [vehicle.get_rid()]
	for s in vehicle.occupants():
		exclude.append((s as Soldier).get_rid())
	var rays := {"center": 0.0, "left": LOOK_SPREAD_DEG, "right": -LOOK_SPREAD_DEG}
	for key: String in rays:
		var dir := forward.rotated(basis.y, deg_to_rad(float(rays[key])))
		var from := vehicle.global_transform * Vector3(0, minf(1.0, size.y * 0.4), -size.z * 0.5 + 0.2)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, OBSTACLE_MASK, exclude)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			if n.y > 0.7:
				continue  # ground rising ahead, not a wall
			out[key] = from.distance_to(hit.position)
			if key == "center":
				var c: Object = hit.collider
				out["wall"] = not (c is Vehicle or c is CharacterBody3D) or (c is Vehicle and (c as Vehicle).wrecked)
	return out


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
