extends RefCounted
## The helicopter flight checks' measures, shared by the supports and loop suites (preload it).
## Captain, 2026-10-14 (v0.4.0: "the heli bumped into the ground on infil", "lets do 12 or 13
## m"): cruise about Helicopter.CRUISE_AGL_M over the ground, the airframe at least
## Helicopter.MIN_CLEAR_M clear of the ground and what stands on it until the last
## Helicopter.FINAL_LOW_M of the final, and nothing touched before touchdown.

## How long it may stay up after what it climbed for is behind it (s), sinking at about this
## rate (m/s at pace 1): the terrain following comes back down gently.
const BEHIND_S: Array[float] = [-1.0, -2.0, -3.0, -4.0]
const BEHIND_SINK_MS := 3.0
const AHEAD_S: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 14.0]


## What `h` touches that isn't a person (the ground, a wall, a tree, an edge wall).
static func touching(h: Helicopter) -> Array[Node]:
	var out: Array[Node] = []
	for body: Node in h.get_colliding_bodies():
		if body is Soldier or Ragdoll.body_of(body) != null:
			continue
		out.append(body)
	return out


## The least clearance (m) of `h`'s airframe over the ground or what stands on it: the bottom
## corners of its hull boxes, its wheels, its main rotor's tips (8 round the disc, tilted with
## it) and its tail rotor's lowest point.
static func airframe_clearance(h: Helicopter) -> float:
	var points: Array[Vector3] = []
	for b: Array in h.spec.get("boxes", []):
		for x: float in [float(b[0]), float(b[3])]:
			for z: float in [float(b[2]), float(b[5])]:
				points.append(h.to_global(Vector3(x, float(b[1]), z)))
	for w: Array in h.spec.get("wheels", []):
		points.append(h.to_global(Vector3(float(w[0]), 0.0, float(w[1]))))
	if h.hull and is_instance_valid(h.hull.art):
		var main_rotor := h.hull.art.get_node_or_null(^"MainRotor") as Node3D
		if main_rotor:
			for i in 8:
				var a := TAU * float(i) / 8.0
				points.append(main_rotor.global_position + (h.global_basis.x * cos(a) + h.global_basis.z * sin(a)) * Helicopter.ROTOR_RADIUS_M)
		var tail := h.hull.art.get_node_or_null(^"TailRotor") as Node3D
		if tail:
			points.append(tail.global_position + Vector3.DOWN * 1.7)
	var exclude: Array[RID] = [h.get_rid()]
	for s: Soldier in h.occupants():
		exclude.append(s.get_rid())
	var space := h.get_world_3d().direct_space_state
	var least := INF
	for p in points:
		var top := h.terrain_y(p)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, maxf(p.y, top) + 40.0, p.z), Vector3(p.x, top - 2.0, p.z), 1, exclude))
		if not hit.is_empty():
			top = maxf(top, (hit.position as Vector3).y)
		least = minf(least, p.y - top)
	return least


## How much higher than Helicopter.CRUISE_AGL_M over the ground at `pos` it may fly, going
## `vel` (flat): climbing at its planned climb for what's ahead (the ground rising under its
## footprint, what stands taller near its track), or coming back down after what's behind.
static func climb_allowance(h: Helicopter, pos: Vector3, vel: Vector3) -> float:
	var here := h.terrain_y(pos) + Helicopter.CRUISE_AGL_M
	var dir := Vector2(vel.x, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 0.5 else Vector2(0.0, -1.0)
	var side := Vector3(-dir.y, 0.0, dir.x) * Helicopter.ROTOR_REACH_M
	var climb := Helicopter.CLIMB_MS * Helicopter.CONTOUR_CLIMB * Helicopter.pace
	var most := 0.0
	for t: float in AHEAD_S + BEHIND_S:
		var p := pos + vel * t
		var need := maxf(h.terrain_y(p) + Helicopter.CRUISE_AGL_M, maxf(h.footprint_ground(p, dir) + Helicopter.MIN_CLEAR_M + Helicopter.CLEAR_MARGIN_M,
			h.obstacle_top(p, side) + Helicopter.OBSTACLE_CLEAR_M))
		var rate := climb if t >= 0.0 else BEHIND_SINK_MS * Helicopter.pace
		most = maxf(most, need - rate * absf(t) - here)
	return most
