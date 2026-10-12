class_name LandingZone
extends RefCounted
## Where a helicopter can land (wave 5b V3), on the host. A spot is safe when the ground there
## is level enough for the gear (slope from a few raycasts round it), nothing stands in the
## rotor disc (a shape query: walls, trees, buildings, vehicles; a zone's building sites that
## aren't loaded count as built up), and nobody is under the fuselage (people, bodies).
## Captain: extraction lands near the marked spot, within 100 m, when the ground there can't take
## a landing (terrain or obstacles); every helicopter support uses the same search. Enemy fire
## never moves a landing (that's HeliCall's business, not this).
##
## Numbers are Proposed, except the 15° slope and the 100 m search (Captain, decided: "Safe to
## land": unsafe is a slope over 15°, water, buildings or trees).

## The UH-60's main rotor is 8.2 m: the disc plus a margin must be clear.
const ROTOR_CLEAR_M := 9.5
## Clear from this high above the ground (m) to CLEAR_TOP_M: low grass and the ground's own
## rise on a slope don't count.
const CLEAR_FROM_M := 0.6
const CLEAR_TOP_M := 7.0
## Nobody within this radius (m) of the spot, up to PEOPLE_TOP_M.
const PEOPLE_CLEAR_M := 5.0
const PEOPLE_TOP_M := 2.5
## The gear stands on ground no steeper than this, measured between points GEAR_SPAN_M from
## the spot (and the ground's own normal there). Captain (decided, design doc "Safe to land"):
## a slope over 15° is unsafe.
const MAX_SLOPE_DEG := 15.0
const GEAR_SPAN_M := 4.0
## The search: rings every RING_STEP_M out to SEARCH_M (Captain: 100 m), RING_POINTS round each.
const SEARCH_M := 100.0
const RING_STEP_M := 10.0
const RING_POINTS := 12
## A spot keeps this far inside the map's edge (m).
const EDGE_KEEP_M := 30.0
## Rays start this high above the terrain (m).
const RAY_UP_M := 150.0


## Whether a helicopter can land at `at` (x, z; any height) in `level`, ignoring the bodies in
## `ignore` (the helicopter itself, its passengers). {"ok": bool, "why": String (when not),
## "spot": Vector3 (the ground there), "slope_deg": float}.
static func check(level: Node3D, at: Vector3, ignore: Array[RID] = []) -> Dictionary:
	var out := {"ok": false, "why": "", "spot": at, "slope_deg": 0.0}
	if level == null or not level.is_inside_tree():
		out.why = "no level"
		return out
	if level.has_method(&"map_area"):
		var area: Rect2 = level.call(&"map_area")
		if not area.grow(-EDGE_KEEP_M).has_point(Vector2(at.x, at.z)):
			out.why = "too near the map's edge"
			return out
	var space := level.get_world_3d().direct_space_state
	var centre := _ground_hit(level, space, at, ignore)
	if centre.is_empty():
		out.why = "no ground"
		return out
	if not bool(centre.ground):
		out.why = "a structure there"
		out.spot = centre.position
		return out
	var spot: Vector3 = centre.position
	out.spot = spot
	var steepest := rad_to_deg(acos(clampf((centre.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	for offset: Vector3 in [Vector3(GEAR_SPAN_M, 0, 0), Vector3(-GEAR_SPAN_M, 0, 0), Vector3(0, 0, GEAR_SPAN_M), Vector3(0, 0, -GEAR_SPAN_M)]:
		var hit := _ground_hit(level, space, spot + offset, ignore)
		if hit.is_empty() or not bool(hit.ground):
			out.why = "a structure there"
			return out
		var rise := absf((hit.position as Vector3).y - spot.y)
		steepest = maxf(steepest, rad_to_deg(atan(rise / GEAR_SPAN_M)))
	out.slope_deg = steepest
	if steepest > MAX_SLOPE_DEG:
		out.why = "too steep (%.0f°)" % steepest
		return out
	if _unloaded_site(level, spot):
		out.why = "buildings there"
		return out
	if _blocked(level, space, spot, ROTOR_CLEAR_M, CLEAR_FROM_M, CLEAR_TOP_M, 1 | Vehicle.LAYER, ignore):
		out.why = "obstacles in the rotor's way"
		return out
	if _blocked(level, space, spot, PEOPLE_CLEAR_M, 0.1, PEOPLE_TOP_M, Soldier.BODY_LAYER | Ragdoll.LAYER, ignore):
		out.why = "people in the way"
		return out
	out.ok = true
	return out


## The nearest safe spot to `at` within SEARCH_M (`at` itself when it's safe):
## {"ok", "spot", "moved_m", "why" (why `at` itself wasn't safe, or "")}. Not ok when there's
## none within SEARCH_M.
static func find(level: Node3D, at: Vector3, ignore: Array[RID] = [], search_m := SEARCH_M) -> Dictionary:
	var first := check(level, at, ignore)
	if first.ok:
		return {"ok": true, "spot": first.spot, "moved_m": 0.0, "why": ""}
	var r := RING_STEP_M
	while r <= search_m + 0.01:
		var n := maxi(RING_POINTS, roundi(TAU * r / 12.0))
		for i in n:
			var ang := TAU * float(i) / float(n) + r * 0.37
			var cand := at + Vector3(cos(ang), 0.0, sin(ang)) * r
			var c := check(level, cand, ignore)
			if c.ok:
				return {"ok": true, "spot": c.spot, "moved_m": Vector2(cand.x - at.x, cand.z - at.z).length(), "why": String(first.why)}
		r += RING_STEP_M
	return {"ok": false, "spot": first.spot, "moved_m": 0.0, "why": String(first.why)}


## The surface under `at` from high up: {"position", "normal", "ground" (the terrain, not a
## structure or a vehicle)}, or {} for nothing.
static func _ground_hit(level: Node3D, space: PhysicsDirectSpaceState3D, at: Vector3, ignore: Array[RID]) -> Dictionary:
	var top := terrain_y(level, at) + RAY_UP_M
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, top - RAY_UP_M * 3.0, at.z), 1 | Vehicle.LAYER, ignore)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"position": hit.position, "normal": hit.normal, "ground": is_ground(level, hit.get("collider"))}


## Whether `collider` is the level's ground (a zone's terrain, the compound's ground slab),
## not a structure, a vehicle or anyone.
static func is_ground(level: Node, collider: Variant) -> bool:
	var node := collider as Node
	if node == null:
		return false
	var terrain: Variant = level.get(&"terrain") if "terrain" in level else null
	if terrain is Node and (terrain as Node).is_ancestor_of(node):
		return true
	return node is StaticBody3D and node.get_parent() == level


## Anything but the ground in a cylinder `radius` round `spot`, from `from_m` to `top_m` above it.
static func _blocked(level: Node3D, space: PhysicsDirectSpaceState3D, spot: Vector3, radius: float, from_m: float, top_m: float, mask: int, ignore: Array[RID]) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = top_m - from_m
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), spot + Vector3.UP * (from_m + shape.height * 0.5))
	q.collision_mask = mask
	q.exclude = ignore
	for hit: Dictionary in space.intersect_shape(q, 32):
		if not is_ground(level, hit.get("collider")):
			return true
	return false


## A zone's building site (module) round `spot` that isn't loaded on the host: its buildings
## have no collision yet, so it counts as built up.
static func _unloaded_site(level: Node, spot: Vector3) -> bool:
	if not level.has_method(&"modules"):
		return false
	for m: Variant in level.call(&"modules"):
		var module := m as ZoneModule
		if module and not module.is_streamed() and module.distance_to(spot) <= ROTOR_CLEAR_M:
			return true
	return false


## The terrain's height at `at` (a zone's heightmap; elsewhere the flat ground, or `at`'s own).
static func terrain_y(level: Node, at: Vector3) -> float:
	if level.has_method(&"ground_height"):
		return float(level.call(&"ground_height", at.x, at.z))
	return maxf(at.y, 0.0)
