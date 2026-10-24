class_name TerrainRoute
extends RefCounted
## What a vehicle can drive over (combined arms A6, cg_brief queue item 2.7; docs/combined_arms.md
## 2.8, 9.2): the questions A9's AI crews, the AI driver's care (VehicleDrive.ai_guard), SquadDrivers'
## road routes and the HUD ask, from the vehicle's own numbers (VehicleDrive) and the zone's ground,
## water and bridges. Any peer; pure where it can be. Numbers Proposed (data/vehicle_drive.json).
##
## - can_cross(v, bridge): its mass class against the bridge's weakest span (ZoneBridges.bridge_mlc).
## - ford_ok(v, depth): water that deep over the ground (m) against its fording depth (or it swims).
## - slope_ok(v, grade_deg, side_deg, ground): a grade it can climb there (power and traction:
##   VehicleDrive.climb_deg) and a side slope under ai_share of its tip angle.
## - path_problem(v, points): the first thing on a drive along `points` it can't take
##   ({"at", "why", "kind"}), sampled every SAMPLE_M; ahead_problem(v, dir, reach) the same just
##   ahead of it.
## - roads_for(v, def): the def with the road pieces over a bridge too light for it left out, so
##   RoadRoute never routes it over one (2.8.5).

## A path is looked at this often along it (m).
const SAMPLE_M := 4.0
## A road piece within this far (m) of a bridge's deck line crosses it.
const ROAD_ON_BRIDGE_M := 3.0
## The ground is found by a ray from this far over a point to this far under it (m); a face
## steeper than this (its normal's y) is an obstacle, not a slope.
const RAY_UP_M := 4.0
const RAY_DOWN_M := 14.0
const OBSTACLE_Y := 0.5

static var _roads_cache := {}  # "roads' hash|bridges' classes|mlc" -> the filtered def


static func _terrain(v: Node) -> ZoneTerrain:
	var lvl: Node = (v as Vehicle).level() if v is Vehicle else CompoundLevel.current(v)
	var t: Variant = lvl.get(&"terrain") if lvl else null
	return t as ZoneTerrain if t is ZoneTerrain else null


static func bridges_of(v: Node) -> ZoneBridges:
	var t := _terrain(v)
	return t.water.bridges if t and t.water else null


## Whether `v` may cross bridge `bi` of its zone (its class is no more than the weakest span's).
static func can_cross(v: Vehicle, bi: int) -> bool:
	var b := bridges_of(v)
	if b == null or bi < 0 or bi >= b.bridges.size():
		return true
	return float(VehicleDrive.mlc(v)) <= b.bridge_mlc(bi)


## Whether `v` fords water `depth` m deep over the ground (it swims: always).
static func ford_ok(v: Vehicle, depth: float) -> bool:
	return depth <= VehicleDrive.ford_m(v.spec)


## Whether `v` takes a grade of `grade_deg` (uphill along its way) and a side slope of `side_deg`
## on ground `ground`.
static func slope_ok(v: Vehicle, grade_deg: float, side_deg: float, ground: StringName = VehicleDrive.DIRT) -> bool:
	return grade_deg <= VehicleDrive.climb_deg(v.spec, ground, v.logistics.packages if v.logistics else []) \
		and side_deg <= VehicleDrive.tip_deg(v.spec) * VehicleDrive.num("rollover", "ai_share", 0.6)


## The grade (uphill along `dir`, degrees; negative downhill) and side slope (degrees) of ground
## whose normal is `n`.
static func slopes_of(n: Vector3, dir: Vector3) -> Vector2:
	var f := Vector3(dir.x, 0.0, dir.z).normalized()
	var s := Vector3.UP.cross(f).normalized()
	var grade := rad_to_deg(atan2(-n.dot(f), n.y))
	var side := rad_to_deg(atan2(absf(n.dot(s)), n.y))
	return Vector2(grade, side)


## What stops `v` at `p` heading `dir` ("" nothing): on a deck, a span too light; else water too deep,
## a side slope over ai_share of its tip angle, a grade it can't climb.
static func problem_at(v: Vehicle, t: ZoneTerrain, b: ZoneBridges, p: Vector3, dir: Vector3) -> String:
	# The ground there as the wheels will meet it: a ray down onto the world (the terrain, a road, a
	# deck, a ramp), else the heightmap. A face steeper than OBSTACLE_Y is a thing in the way (a
	# wall, a tree, a rock: VehicleAI's to go round), not a slope.
	var ground_y := NAN
	var n := Vector3.UP
	if v.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP_M, p + Vector3.DOWN * RAY_DOWN_M, 1, [v.get_rid()])
		var hit := v.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			n = hit.normal
			if n.y < OBSTACLE_Y:
				return ""
			ground_y = (hit.position as Vector3).y
	if is_nan(ground_y):
		if t == null:
			return ""
		ground_y = t.height_at(p.x, p.z)
		n = t.normal_at(p.x, p.z)
	var on := Vector3(p.x, ground_y, p.z)
	if b:
		var at := b.deck_at(on)
		if at.x >= 0:
			var cls := b.span_mlc(at.x, at.y)
			return "bridge MLC %.0f: too heavy (MLC %d)" % [cls, VehicleDrive.mlc(v)] if float(VehicleDrive.mlc(v)) > cls else ""
	var water := t.water_height(p.x, p.z) if t else -INF
	if water > ground_y and not ford_ok(v, water - ground_y):
		return "too deep (%.1f m, fords %.1f m)" % [water - ground_y, VehicleDrive.ford_m(v.spec)]
	var sl := slopes_of(n, dir)
	var tip := VehicleDrive.tip_deg(v.spec) * VehicleDrive.num("rollover", "ai_share", 0.6)
	if sl.y > tip:
		return "side slope %.0f deg (keeps under %.0f)" % [sl.y, tip]
	var g := VehicleDrive.ground_at(v.level(), on)
	var climb := VehicleDrive.climb_deg(v.spec, g, v.logistics.packages if v.logistics else [])
	if sl.x > climb:
		return "too steep (%.0f deg on %s, climbs %.0f)" % [sl.x, g, climb]
	return ""


## What stops `v` just ahead of it along `dir`, out to `reach` m (VehicleDrive.ai_guard; "" none).
## Only in a zone (a ZoneTerrain): the compounds and the range are flat yards.
static func ahead_problem(v: Vehicle, dir: Vector3, reach: float) -> String:
	var t := _terrain(v)
	if t == null:
		return ""
	var b := t.water.bridges if t.water else null
	var from := v.global_position
	var d := SAMPLE_M
	while d <= reach + 0.01:
		var why := problem_at(v, t, b, from + Vector3(dir.x, 0.0, dir.z).normalized() * d, dir)
		if why != "":
			return why
		d += SAMPLE_M
	return ""


## The first thing on a drive along `points` (from where `v` is) it can't take: {"at" (Vector3),
## "why", "index" (the leg's end)} or {} (A9: plan round it; SquadDrivers' checks).
static func path_problem(v: Vehicle, points: PackedVector3Array) -> Dictionary:
	var t := _terrain(v)
	var b := t.water.bridges if t and t.water else null
	var prev := v.global_position
	for i in points.size():
		var leg := points[i] - prev
		var n := maxi(ceili(Vector2(leg.x, leg.z).length() / SAMPLE_M), 1)
		for s in range(1, n + 1):
			var p := prev.lerp(points[i], float(s) / n)
			if t:
				p.y = t.height_at(p.x, p.z)
			var why := problem_at(v, t, b, p, leg)
			if why != "":
				return {"at": p, "why": why, "index": i}
		prev = points[i]
	return {}


## `def` with its road pieces over a bridge `v` is too heavy for left out (RoadRoute then finds the
## way round, or none), cached per bridge state and class.
static func roads_for(v: Vehicle, def: Dictionary) -> Dictionary:
	var b := bridges_of(v)
	if b == null or b.bridges.is_empty():
		return def
	var cls := float(VehicleDrive.mlc(v))
	var light: Array[int] = []
	var state := PackedFloat32Array()
	for bi in b.bridges.size():
		var m := b.bridge_mlc(bi)
		state.append(m)
		if cls > m:
			light.append(bi)
	if light.is_empty():
		return def
	var key := "%d|%s|%d" % [hash(def.get("roads", [])), str(state), int(cls)]
	if _roads_cache.has(key):
		return _roads_cache[key]
	var kept: Array = []
	for r: Array in def.get("roads", []):
		var a := Vector2(float(r[0][0]), float(r[0][1]))
		var e := Vector2(float(r[1][0]), float(r[1][1]))
		var over := false
		for bi in light:
			var xf: Transform3D = b.bridges[bi].xform
			var half := float(b.bridges[bi].length) * 0.5
			var c := Vector2(xf.origin.x, xf.origin.z)
			var along := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
			var near := Geometry2D.get_closest_points_between_segments(a, e, c - along * half, c + along * half)
			if (near[0] as Vector2).distance_to(near[1]) <= ROAD_ON_BRIDGE_M:
				over = true
				break
		if not over:
			kept.append(r)
	var out := def.duplicate()
	out["roads"] = kept
	if _roads_cache.size() > 32:
		_roads_cache.clear()
	_roads_cache[key] = out
	return out
