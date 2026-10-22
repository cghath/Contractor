class_name Viewshed
extends RefCounted
## What a gun at a spot can see across its arc (docs/combined_arms.md 5.4.2): RAYS rays fanned
## over the arc from the muzzle's height, each sampled outward over the terrain's heights and
## the coarse building boxes, out to the weapon's effective range. A sample is seen when a man
## standing there (MAN_M) shows over everything nearer on the ray (the classic horizon test);
## dead ground is the rest. A crest or wall within CLOSE_M that hides the ground beyond it marks
## the ray "blocked close in". Pure: the caller gives the heights (Callable(x, z) -> float) and
## the boxes, so tests stage a ridge.
##
## Bearings are map bearings: 0 north (-z), clockwise. Budget (9.3): under 2 ms; at most
## MAX_SAMPLES samples a ray (the step grows past 10 m for a long range), RAYS x MAX_SAMPLES in all.

const RAYS := 64
const STEP_M := 10.0
const MAX_SAMPLES := 64
const MAN_M := 1.0
const CLOSE_M := 30.0
const MUZZLE_UP_M := 0.65
const RANGES_PATH := "res://data/gun_ranges.json"

static var _ranges := {}


## Casts the viewshed. Returns {"origin", "bearing", "arc", "range", "step", "eye",
## "rays": [{"bearing", "seen": PackedByteArray (1 seen), "close": bool}], "blocked_close": int
## (rays blocked within CLOSE_M), "seen_share": float, "samples": int, "ms": float}.
static func cast(origin: Vector3, bearing_deg: float, arc_deg: float, range_m: float, height: Callable, boxes: Array = [],
		rays := RAYS, muzzle_up := MUZZLE_UP_M) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var step := maxf(STEP_M, range_m / MAX_SAMPLES)
	var n := maxi(int(range_m / step), 1)
	var eye := _h(height, boxes, origin.x, origin.z) + muzzle_up
	var out_rays: Array = []
	var seen_total := 0
	var close_count := 0
	rays = maxi(rays, 2)
	for i in rays:
		var b := bearing_deg - arc_deg * 0.5 + arc_deg * float(i) / float(rays - 1)
		var dir := dir_of(b)
		var seen := PackedByteArray()
		seen.resize(n)
		var best := -INF  # the steepest angle to anything nearer
		var best_d := 0.0
		var close := false
		for j in n:
			var d := (j + 1) * step
			var x := origin.x + dir.x * d
			var z := origin.z + dir.y * d
			var g := _h(height, boxes, x, z)
			var man := (g + MAN_M - eye) / d
			var vis := man >= best
			seen[j] = 1 if vis else 0
			if vis:
				seen_total += 1
			elif best_d <= CLOSE_M and d > CLOSE_M:
				close = true
			var ground := (g - eye) / d
			if ground > best:
				best = ground
				best_d = d
		if close:
			close_count += 1
		out_rays.append({"bearing": b, "seen": seen, "close": close})
	return {"origin": origin, "bearing": bearing_deg, "arc": arc_deg, "range": range_m, "step": step, "eye": eye,
		"rays": out_rays, "blocked_close": close_count, "seen_share": float(seen_total) / float(rays * n),
		"samples": rays * n, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## Whether `b` (a man standing) can be seen from `a` (eyes 1.7 m) over the ground: the known-enemy
## read-out ("seen by 1 known enemy position").
static func line_clear(a: Vector3, b: Vector3, height: Callable, boxes: Array = []) -> bool:
	var ea := _h(height, boxes, a.x, a.z) + 1.7
	var eb := _h(height, boxes, b.x, b.z) + MAN_M
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := clampi(int(dist / STEP_M), 2, 200)
	for k in range(1, steps):
		var t := float(k) / steps
		var x := lerpf(a.x, b.x, t)
		var z := lerpf(a.z, b.z, t)
		if _h(height, boxes, x, z) > lerpf(ea, eb, t):
			return false
	return true


## The map direction (x, z) of bearing `deg` (0 north = -z, clockwise).
static func dir_of(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), -cos(r))


## The bearing of (x, z) direction `d`.
static func bearing_of(d: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## Whether bearing `deg` lies inside the arc [left, right] (clockwise from left).
static func in_arc(deg: float, left: float, right: float) -> bool:
	var span := fposmod(right - left, 360.0)
	return fposmod(deg - left, 360.0) <= span


## A weapon kit's ranges from data/gun_ranges.json: {"name", "effective_m", "max_m", "min_m"
## (mortars), "area_m" (Mk19)}; {} for an unknown kit.
static func ranges(kit: String) -> Dictionary:
	if _ranges.is_empty():
		var f := FileAccess.open(RANGES_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_ranges = data if data is Dictionary else {"_none": {}}
	return _ranges.get(kit, {})


## Ground height at (x, z), raised to the top of any building box there.
static func _h(height: Callable, boxes: Array, x: float, z: float) -> float:
	var g := float(height.call(x, z))
	for b: Variant in boxes:
		var box := b as AABB
		if x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z:
			g = maxf(g, box.end.y)
	return g
