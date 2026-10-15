extends RefCounted
## The helicopter flight checks' measures, shared by the supports and loop suites (preload it).
## Captain, 2026-10-14 (v0.4.0: "the heli bumped into the ground on infil", "lets do 12 or 13
## m"): cruise about Helicopter.CRUISE_AGL_M over the ground, the airframe at least
## Helicopter.MIN_CLEAR_M clear of the ground and what stands on it until the last
## Helicopter.FINAL_LOW_M of the final, and nothing touched before touchdown.

## On the way in, its height over the ground (m) stays within these (Captain, 2026-10-14: "12
## or 13 m", the task: "between ~8 and ~16 m except over obstacles"); more only to climb for
## what's ahead (ceiling). The low end allows the terrain following's lag up a sharp rise on
## ridge_hot's ridged ground at the test's pace (7.3 m seen at pace 2, 8.1 at pace 1); the
## airframe's MIN_CLEAR_M floor is checked on its own.
const INBOUND_LOW_M := 7.0
const INBOUND_HIGH_M := 16.0
## After what it climbed for is behind it (a ridge it came over), the height it may still hold
## comes down at this rate (m/s at pace 1): the terrain following comes back down gently
## (ridge_hot, 2026-10-14: 2-4 m/s down the far side).
const BEHIND_SINK_MS := 2.0
## Seconds after it's put in the air (at its cruise height over the ground just there) before
## the height checks start: it settles into its contour flight.
const SETTLE_S := 2.0


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


## The height (y) it may fly at, tracked frame to frame (`prev`: the last, -INF to start; `dt`
## the frame's seconds): the height its own contour flight holds for what's ahead along the way it
## flies (Helicopter._contour: the ground rising under its footprint, what stands taller near its
## track, its planned climb), and after that's behind it, coming down at BEHIND_SINK_MS.
static func ceiling(h: Helicopter, prev: float, dt: float) -> float:
	var vel := Vector3(h.linear_velocity.x, 0.0, h.linear_velocity.z)
	return maxf(h._contour(h.global_position, vel, h._agl).x, prev - BEHIND_SINK_MS * Helicopter.pace * dt)


## How much higher than Helicopter.CRUISE_AGL_M over the ground at `pos` the height `top` (from
## ceiling) is: what it may climb for.
static func climb_allowance(h: Helicopter, pos: Vector3, top: float) -> float:
	return maxf(top - h.terrain_y(pos) - Helicopter.CRUISE_AGL_M, 0.0)
