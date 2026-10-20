class_name ConvoyColumn
extends RefCounted
## A column of vehicles behind a lead (the squad's drivers part 2, 2026-10-20): the maths
## SquadDrivers steers its convoys with. The lead (a player's vehicle, an AI-driven one, or a
## player on foot) leaves a trail of points every TRAIL_STEP_M; each vehicle behind it drives
## to its place on that trail, its slot's gaps back along the way the lead went (round the same
## corners, down the same road), not a straight line cut across; and it keeps its gap to the
## one ahead of it by speed: catching up when it's fallen back, holding back when it's close,
## stopping when it's too close (follow_speed). VehicleAI slows for the trail's corners and
## steers round anything in the way. Proposed numbers.

## A new trail point once the lead has moved this far (m); at most TRAIL_MAX kept (the oldest go).
const TRAIL_STEP_M := 3.0
const TRAIL_MAX := 200
## Closer than this share of the gap to the one ahead: stop.
const MIN_GAP_SHARE := 0.55
## Every metre past the gap adds this much speed (m/s) over the speed of the one ahead.
const CATCH_UP_PER_M := 0.35
## A vehicle further than this (m) off the trail drives straight to its place, not along it.
const JOIN_M := 30.0
## It steers for a point this far (m) on along the trail past its place (its speed keeps the
## gap), never closer than AHEAD_CLEAR_M behind the one ahead.
const LOOKAHEAD_M := 10.0
const AHEAD_CLEAR_M := 8.0


## `trail` with `at` added when the lead has moved TRAIL_STEP_M since its last point.
static func record(trail: PackedVector3Array, at: Vector3) -> PackedVector3Array:
	if trail.is_empty() or _flat(trail[trail.size() - 1]).distance_to(_flat(at)) >= TRAIL_STEP_M:
		trail.append(at)
		if trail.size() > TRAIL_MAX:
			trail = trail.slice(trail.size() - TRAIL_MAX)
	return trail


## The point `back` metres behind the lead (at `lead_pos`, facing `lead_fwd`) along its trail;
## past the trail's oldest point, straight on back the way it came.
static func place(trail: PackedVector3Array, lead_pos: Vector3, lead_fwd: Vector3, back: float) -> Vector3:
	var prev := lead_pos
	var left := back
	for i in range(trail.size() - 1, -1, -1):
		var seg := _flat(prev).distance_to(_flat(trail[i]))
		if seg >= left and seg > 0.001:
			return prev.lerp(trail[i], left / seg)
		left -= seg
		prev = trail[i]
	var dir := -_flat(lead_fwd)
	if trail.size() >= 2:
		dir = _flat(trail[0] - trail[1])
	elif trail.size() == 1 and _flat(lead_pos).distance_to(_flat(trail[0])) > 0.5:
		dir = _flat(trail[0] - lead_pos)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	return prev + dir * left


## How far back along the trail from the lead the point nearest `p` is (m): where a vehicle in
## the column is. Off the trail (or no trail): straight from the lead.
static func back_of(trail: PackedVector3Array, lead_pos: Vector3, p: Vector3) -> float:
	var best := _flat(lead_pos).distance_to(_flat(p))
	var best_d := best
	var arc := 0.0
	var prev := lead_pos
	for i in range(trail.size() - 1, -1, -1):
		arc += _flat(prev).distance_to(_flat(trail[i]))
		prev = trail[i]
		var d := _flat(trail[i]).distance_to(_flat(p))
		if d < best_d:
			best_d = d
			best = arc
	return best


## The waypoints from `from` to `to` (its place, `back` metres behind the lead) along the trail:
## the trail's points between the two, then the place. Far off the trail: just the place.
static func route(trail: PackedVector3Array, lead_pos: Vector3, from: Vector3, to: Vector3, back: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if trail.is_empty():
		out.append(to)
		return out
	var arcs := PackedFloat32Array()
	arcs.resize(trail.size())
	var arc := 0.0
	var prev := lead_pos
	for i in range(trail.size() - 1, -1, -1):
		arc += _flat(prev).distance_to(_flat(trail[i]))
		arcs[i] = arc
		prev = trail[i]
	var near := 0
	var near_d := INF
	for i in trail.size():
		var d := _flat(trail[i]).distance_to(_flat(from))
		if d < near_d:
			near_d = d
			near = i
	if near_d <= JOIN_M:
		for i in range(near + 1, trail.size()):
			if arcs[i] > back + 0.5:
				out.append(trail[i])
	out.append(to)
	return out


## The speed (m/s) to keep `gap` (m) to the one ahead (going `ahead_ms`) at `want_gap`, never
## more than `top`; 0: stop.
static func follow_speed(gap: float, want_gap: float, ahead_ms: float, top: float) -> float:
	if gap < want_gap * MIN_GAP_SHARE:
		return 0.0
	return clampf(ahead_ms + (gap - want_gap) * CATCH_UP_PER_M, 0.0, top)


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
