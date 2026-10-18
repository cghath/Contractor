class_name HeliRoute
extends RefCounted
## A support helicopter's way in and out of a zone (host): where on the zone's edge it comes in,
## the point it flies in low by on the way, and the edge it leaves by.
##
## Captain, 2026-10-14 (v0.3.1, harbour_yard): the insertion "came in from wrong side of the map
## and is trying to land in the wrong area", then "it turned around". It started on the side of
## the LHD (Supports.origin_for: the support origin, not the LZ), flew across the map to the
## briefing's foot insertion point it was planned from (on the west edge, mid-map) and turned
## back to its LZ near the south edge: most of the map crossed twice. Now:
## - It comes in from the zone's edge nearest the LZ whose approach corridor no watcher sees
##   (entry): points along every edge, at least MIN_APPROACH_M from the LZ (a run in for the
##   J-hook), the nearest first; among those within ENTRY_SLACK_M of the nearest, the first
##   whose corridor nobody sees, else the one seen least.
## - The point it flies in low by (waypoints) lies between there and the LZ: the planned
##   insertion point only when the path by it is at most RATIO_MAX times the straight line and
##   turns at most TURN_MAX_DEG there, else a point on the straight line LOW_POINT_M short of
##   the LZ (none on a short run: HOOK_ROOM_M). No backtracking.
## - It leaves by the nearest edge whose corridor isn't watched (exit_for).
## Watchers are DeadGround.watchers (garrison posts, hostiles up); a corridor point is seen when
## one of them sees a man standing there (DeadGround.seen_by: the terrain only). Numbers are
## Proposed.

## Its run in from the edge to the LZ is at least this long (m), where the zone allows.
const MIN_APPROACH_M := 500.0
## Edges up to this much farther (m) than the nearest are tried for an unwatched corridor.
const ENTRY_SLACK_M := 400.0
## Points along each edge this far apart (m), beside the foot of the LZ on it.
const EDGE_STEP_M := 100.0
## A corridor is looked at every this many metres, from CORRIDOR_SKIP_M out from the LZ (the
## last stretch is the same whichever edge it came from) to the edge.
const CORRIDOR_STEP_M := 100.0
const CORRIDOR_SKIP_M := 250.0
## Corridors worked out at most (the search's time cap).
const MAX_ENTRY_CHECKS := 8
## The point flown in low by: the path by it at most RATIO_MAX times the straight line, a turn
## there of at most TURN_MAX_DEG (the Captain's limits are 1.6 and 120: these keep a margin).
const RATIO_MAX := 1.5
const TURN_MAX_DEG := 90.0
## With no planned point on the way: the point on the straight line this far short of the LZ
## (m; less on a shorter run, as long as it's passed after setting off).
const LOW_POINT_M := 600.0
## A point flown by is at least this far from the LZ (m): passed ROUTE_PASS_M short of it, it
## still leaves the J-hook its run in (2026-10-14: a point 225 m out cut the hook to 117 degrees).
const HOOK_ROOM_M := 450.0


## The zone's map area kept inside (`inset` m in from its edge, the invisible wall).
static func inside(level: Node, inset := HeliSupports.SPAWN_INSET_M) -> Rect2:
	var area := Rect2(-1000, -1000, 2000, 2000)
	if level and level.has_method(&"map_area"):
		area = level.call(&"map_area")
	return area.grow(-inset)


## Where on the edge of `level` (`inset` in) it comes in to `lz`, host side:
## {"at": Vector3 (y 0), "watched": corridor points seen, "run": m to the LZ,
## "checked": [{"at": Vector2, "run", "watched"}] in the order tried}. `posts`: the watchers
## (DeadGround.watchers when empty). `min_run` (m): the shortest run in it takes (0 leaving).
## The map's edges, in the order entry() walks them (`side` there and in plan()).
const SIDES: Array[String] = ["north", "east", "south", "west"]


static func entry(level: Node, lz: Vector3, posts: Array[Vector3] = [], min_run := MIN_APPROACH_M, inset := HeliSupports.SPAWN_INSET_M, only_side := -1) -> Dictionary:
	var rect := inside(level, inset)
	var p := Vector2(lz.x, lz.z).clamp(rect.position, rect.end)
	var cands: Array = []  # [run, Vector2]
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for side in 4:
		if only_side >= 0 and side != only_side:
			continue  # Captain, 2026-10-17: the briefing picked the side it comes in from
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var foot := clampf((p - a).dot((b - a) / maxf(length, 0.001)), 0.0, length)
		var along: Array[float] = [foot]
		var s := 0.0
		while s <= length + 0.01:
			along.append(s)
			s += EDGE_STEP_M
		for t: float in along:
			var at := a + (b - a) * (t / maxf(length, 0.001))
			cands.append([at.distance_to(Vector2(lz.x, lz.z)), at])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var long_enough := cands.filter(func(c: Array) -> bool: return float(c[0]) >= min_run - 0.01)
	if long_enough.is_empty():  # (a small zone: the longest run it has)
		long_enough = [cands.back()]
	var nearest := float(long_enough[0][0])
	var watch := posts
	if watch.is_empty() and level is Node3D and level.is_inside_tree():
		watch = DeadGround.watchers(level)
	var checked: Array = []
	var best: Array = []
	var best_watched := 1 << 30
	for c: Array in long_enough:
		if float(c[0]) > nearest + ENTRY_SLACK_M or checked.size() >= MAX_ENTRY_CHECKS:
			break
		var at: Vector2 = c[1]
		if checked.any(func(d: Dictionary) -> bool: return (d.at as Vector2).distance_to(at) < 1.0):
			continue  # (a corner, or the foot on a step)
		var seen := corridor_watched(level, Vector3(at.x, 0.0, at.y), lz, watch)
		checked.append({"at": at, "run": float(c[0]), "watched": seen})
		if seen < best_watched:
			best = c
			best_watched = seen
		if seen == 0:
			break
	var chosen: Vector2 = best[1]
	return {"at": Vector3(chosen.x, 0.0, chosen.y), "watched": best_watched, "run": float(best[0]), "checked": checked}


## How many points of the corridor from `from` to `lz` (every CORRIDOR_STEP_M, from
## CORRIDOR_SKIP_M out from the LZ) a watcher in `posts` sees.
static func corridor_watched(level: Node, from: Vector3, lz: Vector3, posts: Array[Vector3]) -> int:
	if posts.is_empty() or not (level is Node3D):
		return 0
	var run := Vector2(from.x - lz.x, from.z - lz.z)
	var length := run.length()
	var n := 0
	var d := CORRIDOR_SKIP_M
	while d <= length + 0.01:
		var q := Vector2(lz.x, lz.z) + run / maxf(length, 0.001) * d
		var at := Vector3(q.x, 0.0, q.y)
		at.y = LandingZone.terrain_y(level, at)
		n += DeadGround.seen_by(level as Node3D, at, posts, 1)
		d += CORRIDOR_STEP_M
	return n


## The points (y 0) it flies in low by from `start` to `lz`: `via` (Vector3, the planned
## insertion point) when it's on the way (path_ratio <= RATIO_MAX, max_turn_deg <= TURN_MAX_DEG,
## at least HOOK_ROOM_M from the LZ), else the point on the straight line LOW_POINT_M short of
## the LZ, or none for a short run.
static func waypoints(start: Vector3, lz: Vector3, via: Variant = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a := Vector3(start.x, 0.0, start.z)
	var b := Vector3(lz.x, 0.0, lz.z)
	var run := a.distance_to(b)
	if via is Vector3:
		var v: Vector3 = via
		v.y = 0.0
		var line: Array[Vector3] = [a, v, b]
		if v.distance_to(b) >= HOOK_ROOM_M and v.distance_to(a) > HeliCall.ROUTE_PASS_M \
				and path_ratio(line) <= RATIO_MAX and max_turn_deg(line) <= TURN_MAX_DEG:
			out.append(v)
			return out
	var short := minf(LOW_POINT_M, run - HeliCall.ROUTE_PASS_M - 1.0)
	if short >= HOOK_ROOM_M:
		out.append(b + (a - b) / maxf(run, 0.001) * short)
	return out


## The whole plan into `lz` (Vector3) of `level`: {"entry": Vector3, "points": Array[Vector3]
## (flown in low by), "watched", "checked"} (see entry, waypoints). `via`: the planned insertion
## point (Vector3) or null.
static func plan(level: Node, lz: Vector3, via: Variant = null, posts: Array[Vector3] = [], side := -1) -> Dictionary:
	var e := entry(level, lz, posts, MIN_APPROACH_M, HeliSupports.SPAWN_INSET_M, side)
	return {"entry": e.at, "points": waypoints(e.at, lz, via), "watched": e.watched, "checked": e.checked, "run": e.run}


## Where it leaves from `at` (Vector3, y 0): the nearest edge whose corridor isn't watched.
static func exit_for(level: Node, at: Vector3, posts: Array[Vector3] = []) -> Vector3:
	return entry(level, at, posts, 0.0).at


## The flown length of `line` (Vector3s, x and z) over the straight distance from its first to
## its last point (1: straight).
static func path_ratio(line: Array) -> float:
	if line.size() < 2:
		return 1.0
	var flown := 0.0
	for i in range(1, line.size()):
		flown += _flat(line[i - 1], line[i])
	return flown / maxf(_flat(line[0], line[-1]), 0.001)


## The sharpest turn along `line` (degrees: 0 straight on, 180 a reversal).
static func max_turn_deg(line: Array) -> float:
	var worst := 0.0
	for i in range(1, line.size() - 1):
		var d1 := Vector2(line[i].x - line[i - 1].x, line[i].z - line[i - 1].z)
		var d2 := Vector2(line[i + 1].x - line[i].x, line[i + 1].z - line[i].z)
		if d1.length() < 0.01 or d2.length() < 0.01:
			continue
		worst = maxf(worst, rad_to_deg(absf(d1.angle_to(d2))))
	return worst


## Vector3s as [[x, z], ...] (a briefing's zone dictionary, sent to every peer).
static func to_xz(points: Array) -> Array:
	return points.map(func(p: Vector3) -> Array: return [snappedf(p.x, 0.1), snappedf(p.z, 0.1)])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
