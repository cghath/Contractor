class_name GrassCarpet
extends MultiMeshInstance3D
## Grass near the camera (Captain, 2026-10-18: "the terrain itself, the ground and our props also
## need a pass"): ZoneScatter's tufts are laid per 128 m cell at about one per 16 m² (too few to
## read as grass up close, and more across a 16 km² zone would cost too much), so this lays a
## carpet of small tufts only round the camera: one every SPACING_M on a grid (jittered by the
## cell, so it stays put as you move), out to RADIUS_M, thinning over the last EDGE_SHARE of it
## so there's no edge. Re-laid when the camera has moved SNAP_M. Off roads and pads, out of the
## water, off steep ground, out of craters and dug earth (GroundCuts.bare; re-laid when the
## ground is cut), in the scatter's tuft colours. Visual only: no collision, no sight
## blocking. Never on a headless server (ZoneLevel adds it with the visuals).

const RADIUS_M := 28.0
const SPACING_M := 0.75
const EDGE_SHARE := 0.35
const SNAP_M := 6.0
const SIZE := Vector2(0.35, 0.75)
const MIN_UP := 0.8
## Proposed: no carpet with the eye this far over the ground (m; _process): a helicopter at its
## contour height (12.5 m) and up, a third-storey window.
const EYE_MAX_M := 10.0

var _scatter: ZoneScatter
var _terrain: ZoneTerrain
var _centre := Vector2(INF, INF)
var _colours: Array[Color] = []
var _cut_seen := 0  # GroundCuts.version the carpet was laid for
var _tufts := {}  # grid point (Vector2i) -> its 16 buffer floats (_tuft), or null for none (lay)
## Perf pass: at most this many grid points not seen before are worked out per lay; the rest come
## in over the next frames (_incomplete re-lays). From a helicopter almost every lay is new ground
## (15-50 ms a lay with the world expansion's fields). Standing, the carpet is whole in a frame or two.
const NEW_PER_LAY := 700
## ...and no more than this long (usec) on them a lay (perf, 2026-10-22: on a busy machine 700 new
## tufts from a helicopter were 40-60 ms frames).
const NEW_USEC := 2500
var _incomplete := false


func setup(scatter: ZoneScatter, terrain: ZoneTerrain, mesh: Mesh, material: Material, colours: Array[Color]) -> void:
	_scatter = scatter
	_terrain = terrain
	_colours = colours if not colours.is_empty() else ([Color("6f7040")] as Array[Color])
	name = "GrassCarpet"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _terrain == null:
		return
	var at := Vector2(camera.global_position.x, camera.global_position.z)
	# Perf (world content pass, 2026-10-23): with the eye more than EYE_MAX_M over the ground (a
	# helicopter, a tower's roof) every tuft is that far off at least, a few pixels at most: the
	# carpet isn't drawn or laid (from a UH-60 a lay was most of the new ground every frame).
	var up := camera.global_position.y - _terrain.height_at(at.x, at.y) > EYE_MAX_M
	if up:
		if visible:
			visible = false
			_centre = Vector2(INF, INF)
		return
	if not visible:
		visible = true
	var cut_now := _terrain.cuts.version if _terrain.cuts else 0
	if at.distance_to(_centre) < SNAP_M and cut_now == _cut_seen and not _incomplete:
		return
	if cut_now != _cut_seen:
		_tufts.clear()  # the ground changed: work them out again
		_pending.clear()
	_cut_seen = cut_now
	_centre = (at / SNAP_M).round() * SNAP_M
	var t0 := Time.get_ticks_usec()
	lay(_centre)
	FrameCost.spent(&"grass", t0)


## Lays the carpet round `centre` (x, z). Returns how many tufts.
## Perf pass (2026-10-22): each grid point's tuft (or none) is worked out once and kept (_tufts)
## until the ground is cut again, so a re-lay only works out the points that came into the
## circle; the scatter's pads and roads are narrowed to those near the circle once per lay (a
## tuft tested all the zone's roads before: 100-300 ms a lay, every 6 m on foot and many times a
## second in a vehicle). The carpet looks the same.
func lay(centre: Vector2) -> int:
	if _incomplete and centre == _laid_at and not _pending.is_empty():
		return _lay_pending()
	_pending.clear()
	_laid_at = centre
	var n := int(ceil(RADIUS_M / SPACING_M))
	var gx0 := int(floor(centre.x / SPACING_M))
	var gz0 := int(floor(centre.y / SPACING_M))
	var half := _terrain.size_m * 0.5
	var near := _blockers_near(centre)
	var keep: Array[Rect2] = near[0]
	var roads: Array = near[1]
	# Perf (2026-10-22): each kept tuft is its 16 floats of the multimesh's buffer (transform rows,
	# colour), handed over in one go (setting each instance's transform and colour was two server
	# calls a tuft, ~2000 tufts a lay).
	var buf := PackedFloat32Array()
	var fresh := 0
	var spent := 0
	_incomplete = false
	for gz in range(gz0 - n, gz0 + n + 1):
		# Only the row's points that can be in the circle (each is jittered up to a grid step).
		var dz := absf(gz * SPACING_M - centre.y) - SPACING_M
		if dz > RADIUS_M:
			continue
		var reach := int(ceil(sqrt(maxf(RADIUS_M * RADIUS_M - maxf(dz, 0.0) * maxf(dz, 0.0), 0.0)) / SPACING_M)) + 1
		var cx := int(floor(centre.x / SPACING_M))
		for gx in range(maxi(gx0 - n, cx - reach), mini(gx0 + n, cx + reach) + 1):
			var h1 := _hash(gx, gz)
			var x := (gx + h1) * SPACING_M
			var z := (gz + fposmod(h1 * 7.31, 1.0)) * SPACING_M
			var d := Vector2(x, z).distance_to(centre)
			if d > RADIUS_M or absf(x) > half - 2.0 or absf(z) > half - 2.0:
				continue
			var edge := clampf((RADIUS_M - d) / (RADIUS_M * EDGE_SHARE), 0.0, 1.0)
			if fposmod(h1 * 13.7, 1.0) > edge:
				continue  # thinner toward the edge: no ring
			var key := Vector2i(gx, gz)
			var tuft: Variant = _tufts.get(key, false)
			if tuft is bool:
				if fresh >= NEW_PER_LAY or spent >= NEW_USEC:
					_incomplete = true  # (the next frames' lays go on: _lay_pending)
					_pending.append([key, x, z, h1])
					continue
				fresh += 1
				var t0 := Time.get_ticks_usec()
				tuft = _tuft(x, z, h1, keep, roads)
				spent += Time.get_ticks_usec() - t0
				_tufts[key] = tuft
			if tuft == null:
				continue
			buf.append_array(tuft)
	_buf = buf
	if _incomplete:
		_pending_blockers = near
	var count := buf.size() / 16
	multimesh.instance_count = count
	if count > 0:
		multimesh.buffer = buf
	# Points well out of the circle are forgotten (a long walk doesn't grow the cache).
	if _tufts.size() > 4 * (2 * n + 1) * (2 * n + 1):
		var far := RADIUS_M + SNAP_M * 2.0
		for key: Vector2i in _tufts.keys():
			if Vector2(key.x * SPACING_M, key.y * SPACING_M).distance_to(centre) > far:
				_tufts.erase(key)
	return count


## A lay that didn't get to every new point (NEW_PER_LAY, NEW_USEC) goes on from the points left
## (_pending) at the same centre, adding their tufts to the carpet laid (_buf): perf, 2026-10-22,
## the whole circle's points were gone through again each frame (3-4 ms) until it was whole.
var _laid_at := Vector2(INF, INF)
var _buf := PackedFloat32Array()
var _pending: Array = []  # [grid point, x, z, hash]
var _pending_blockers: Array = []


func _lay_pending() -> int:
	var keep: Array[Rect2] = _pending_blockers[0]
	var roads: Array = _pending_blockers[1]
	var t0 := Time.get_ticks_usec()
	var k := 0
	while k < _pending.size() and k < NEW_PER_LAY and Time.get_ticks_usec() - t0 < NEW_USEC:
		var p: Array = _pending[k]
		k += 1
		var tuft: Variant = _tufts.get(p[0], false)
		if tuft is bool:
			tuft = _tuft(p[1], p[2], p[3], keep, roads)
			_tufts[p[0]] = tuft
		if tuft != null:
			_buf.append_array(tuft)
	_pending = _pending.slice(k)
	_incomplete = not _pending.is_empty()
	var count := _buf.size() / 16
	multimesh.instance_count = count
	if count > 0:
		multimesh.buffer = _buf
	return count


## The tuft at grid point (x, z) with hash `h1`: its 16 floats in the multimesh's buffer (the
## transform's three rows, then the colour), or null where none grows
## (a pad, a road, water, the sea's edge, steep or bare ground).
func _tuft(x: float, z: float, h1: float, keep: Array[Rect2], roads: Array) -> Variant:
	if _blocked(x, z, keep, roads):
		return null
	var h := _terrain.height_at(x, z)
	if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.4:
		return null
	if _terrain.normal_at(x, z).y < MIN_UP:
		return null
	if _terrain.cuts and _terrain.cuts.bare(x, z):
		return null
	var s := lerpf(SIZE.x, SIZE.y, fposmod(h1 * 3.97, 1.0))
	var basis := Basis(Vector3.UP, h1 * TAU).scaled(Vector3(s, s * lerpf(0.8, 1.4, fposmod(h1 * 5.3, 1.0)), s))
	var c: Color = _colours[int(fposmod(h1 * 17.0, 1.0) * _colours.size()) % _colours.size()]
	c = c.darkened(fposmod(h1 * 23.0, 1.0) * 0.18)
	var y := h - 0.03
	return PackedFloat32Array([basis.x.x, basis.y.x, basis.z.x, x, basis.x.y, basis.y.y, basis.z.y, y,
		basis.x.z, basis.y.z, basis.z.z, z, c.r, c.g, c.b, c.a])


## ZoneScatter._ground_blocked with the pads and roads narrowed to `keep` and `roads`.
func _blocked(x: float, z: float, keep: Array[Rect2], roads: Array) -> bool:
	if _terrain.water and _terrain.water.keeps_clear(x, z):
		return true
	if _terrain.features and _terrain.features.keeps_clear(x, z):
		return true  # a field (ZoneFeatures)
	var p := Vector2(x, z)
	for r in keep:
		if r.has_point(p):
			return true
	for road: Array in roads:
		if Geometry2D.get_closest_point_to_segment(p, road[0], road[1]).distance_to(p) < 4.0:
			return true
	return false


## The scatter's pads (already shrunk as ZoneScatter._ground_blocked does) and road segments
## that reach the circle round `centre`: [Array[Rect2], [[a, b], ...]].
func _blockers_near(centre: Vector2) -> Array:
	var keep: Array[Rect2] = []
	var roads: Array = []
	if _scatter == null:
		return [keep, roads]
	var box := Rect2(centre - Vector2.ONE * (RADIUS_M + 1.0), Vector2.ONE * (RADIUS_M + 1.0) * 2.0)
	for r in _scatter._keep:
		var g := r.grow(-ZoneScatter.PAD_KEEP_M + 2.0)
		if g.intersects(box):
			keep.append(g)
	for road: Array in _scatter._roads:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) < RADIUS_M + 5.0:
			roads.append([a, b])
	return [keep, roads]


static func _hash(x: int, z: int) -> float:
	return fposmod(sin(float(x) * 127.1 + float(z) * 311.7) * 43758.5453, 1.0)
