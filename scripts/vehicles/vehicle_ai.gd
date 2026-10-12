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
var _stuck_s := 0.0
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
	while index < path.size() - 1 and _flat(pos).distance_to(_flat(path[index])) < WAYPOINT_M:
		index += 1
	var target := path[index]
	var to := _flat(target) - _flat(pos)
	var dist := to.length()
	var last := index == path.size() - 1
	var speed := vehicle.forward_speed()
	if last and dist < ARRIVE_M:
		vehicle.set_ai_input(0.0, 0.0, true)
		if absf(speed) < 0.3:
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
	if last:
		want = minf(want, maxf(dist * 0.45, 1.5))
	# Obstacles ahead: ease off and steer round, or stop.
	var block := _obstacles(speed)
	if block.center < INF and block.center < maxf(speed, 1.0) * 1.2 + 2.0:
		want = 0.0
		status = "blocked"
	elif block.center < INF:
		want = minf(want, 2.5)
		steer = clampf(steer + (1.0 if block.left < block.right else -1.0) * 0.8, -1.0, 1.0)
	elif block.left < INF or block.right < INF:
		steer = clampf(steer + (0.4 if block.left < block.right else -0.4), -1.0, 1.0)
	if status == "blocked" and block.center == INF:
		status = "driving"
	# Stuck: back off with the wheel the other way, then try again.
	if _backoff_s > 0.0:
		_backoff_s -= delta
		vehicle.set_ai_input(-0.6, _backoff_steer, false)
		return
	if want > 0.5 and absf(speed) < STUCK_MS and vehicle.can_drive():
		_stuck_s += delta
		if _stuck_s > STUCK_S:
			_stuck_s = 0.0
			_backoff_s = BACKOFF_S
			_backoff_steer = -signf(steer) if steer != 0.0 else 1.0
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


## Distances to anything in the way ahead (centre, left, right; INF for clear).
func _obstacles(speed: float) -> Dictionary:
	var out := {"center": INF, "left": INF, "right": INF}
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
	return out


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
