class_name ZoneFeatures
extends Node3D
## Terrain features and the marsh, snow and farmland presets (queue item 1.3 of docs/cg_brief.md),
## from the terrain preset's "features" (data/terrain_presets.json, docs/terrain_presets.md) and
## the zone's seed and season only, so every peer and late joiner builds the same:
## - Gullies and ditches: dry cuts in the ground, a flat floor and steep sides (GULLY_*), that
##   hide a prone man (a gully a crouched one too) from the flat round them. They are the
##   heightmap itself, so the AI's cover search and spotting (rays against the ground's
##   collision: SquadAI.find_cover, Spotting) see them as cover with no code of their own.
## - Cliffs: escarpments, a rock face CLIFF_FACE_M across (60-75 degrees on the 4 m grid: no one
##   walks or drives up it, the navigation mesh leaves it out), a ledge on top, the high ground
##   easing back down behind; tapering out at both ends so the way round is short. The ground
##   shader draws steep faces as layered rock; fallen rock (talus) lies at the foot.
## - Marsh ("marsh"): soft ground in seeded patches that slows a man on foot (slow_at, the
##   movement hook in Wading.ground_mult), dark wet mud, reed beds that hide (cover_least); its
##   standing water is ZoneWater's (shallow ponds and pools, the preset's "water").
## - Snow ("snow"): snow cover over a snow line that moves with the season, off the steep rock,
##   in drifts; slows a man on foot except on the roads and tracks (packed); the shader's tyre
##   tracks; the streams and ponds freeze (ZoneWater "frozen": ice you walk on).
## - Fields ("fields"): a patchwork on a turned grid round the farms (never on a pad: a landmark
##   farm's buildings stand on theirs), each a crop with its colour and height by season (CROPS,
##   Season), orchards (rows of fruit trees), hedges along some field edges, and irrigation
##   channels along others (ZoneWater "channels": shallow water you wade). Crops are drawn near
##   the camera as blocks in rows; tall ones (maize, ripe wheat) hide people (cover_least).
## ZoneTerrain.generate calls carve() once the pads are flat (plans them all) and finish() after
## the water (the gullies and cliffs go into the heights then, off the water); ZoneTerrain._ground_colour asks tint();
## ZoneScatter keeps off the fields (keeps_clear) and lays the orchards, hedges and talus
## (lay_out); ZoneScatter.foliage_least adds cover_least. Numbers Proposed.

## Samples along a gully or ditch (m).
const STEP_M := 8.0
## Gullies and ditches keep this far from every pad's rect and from each other and from cliffs
## (m), and a gully this far inside the zone's edge; their ends taper over END_M.
const LINE_PAD_GAP_M := 30.0
const LINE_GAP_M := 40.0
const EDGE_KEEP_M := 220.0
const END_M := 40.0
## The carve and the cliffs fade out near pads (between these distances from a pad's rect, m)
## and near roads (gullies, cliffs: a road crosses a cliff on a ramp), and near the zone's edge.
const PAD_NEAR_M := 8.0
const PAD_FAR_M := 45.0
const GULLY_ROAD_M := Vector2(5.0, 16.0)
const CLIFF_ROAD_M := Vector2(10.0, 60.0)
const EDGE_NEAR_M := 150.0
const EDGE_FAR_M := 230.0
## Lookups of pads and roads by KEEP_CELL_M cell.
const KEEP_CELL_M := 128.0
## Cliffs: the face is this wide across (m: under one cell, so the step falls between two rows of
## heights), each end tapers over CLIFF_END_M, the face wanders CLIFF_WOBBLE_M either way; the
## ledge on top is plateau_m deep before the ground eases back over back_m. Keeps CLIFF_PAD_M
## off every pad and CLIFF_GAP_M off other cliffs.
const CLIFF_FACE_M := 2.0
const CLIFF_END_M := 45.0
const CLIFF_WOBBLE_M := 4.0
const CLIFF_PAD_M := 60.0
const CLIFF_GAP_M := 90.0
## Defaults for each part of a preset's "features" (each key optional in the data).
const GULLY_DEFAULTS := {"count": [2, 3], "depth_m": [2.0, 2.8], "half_m": [8.0, 10.0], "floor_m": 2.6, "length_m": [260.0, 520.0], "meander": 0.35}
const DITCH_DEFAULTS := {"count": [1, 2], "depth_m": [1.2, 1.5], "half_m": [6.5, 7.5], "floor_m": 2.2, "length_m": [140.0, 320.0], "meander": 0.08}
const CLIFF_DEFAULTS := {"count": [1, 2], "height_m": [8.0, 14.0], "length_m": [160.0, 320.0], "plateau_m": [10.0, 24.0], "back_m": [110.0, 170.0], "talus_per_m": 0.22}
const MARSH_DEFAULTS := {"share": 0.6, "slow": 0.35, "wavelength_m": 130.0, "reeds": 0.35, "reed_h_m": 1.7, "colour": "4b5132"}
const SNOW_DEFAULTS := {"cover": 1.0, "line_m": {"winter": -1000.0, "spring": 4.0, "summer": 16.0, "autumn": 8.0}, "slow": 0.25,
	"colour": "e4e8ec", "drifts": 0.25, "tracks": 0.6}
const FIELD_DEFAULTS := {"share": 0.8, "size_m": [70.0, 150.0], "lane_m": 2.0, "orchard_share": 0.12, "orchards_max": 6,
	"crops": {"wheat": 3, "maize": 2, "vegetables": 1, "fallow": 1}, "hedges": 0.3, "channels": 0.25, "channel_m": [120.0, 340.0]}
## Crops by season (Season.ALL): [colour (sRGB), height (m), cover (foliage metres a metre of
## crop counts as, Spotting.FOLIAGE_*: wheat ~15 m hides, maize ~5 m)]. Proposed.
const CROPS := {
	"wheat": {"spring": ["6c8c38", 0.35, 0.0], "summer": ["c4a24a", 0.9, 0.08], "autumn": ["a89260", 0.15, 0.0], "winter": ["6e5c46", 0.0, 0.0]},
	"maize": {"spring": ["6f5c43", 0.2, 0.0], "summer": ["4c7a2a", 2.2, 0.25], "autumn": ["ae965a", 2.0, 0.2], "winter": ["7a6a50", 0.15, 0.0]},
	"vegetables": {"spring": ["5d7d34", 0.3, 0.0], "summer": ["4b7230", 0.45, 0.0], "autumn": ["69603a", 0.25, 0.0], "winter": ["5f503c", 0.0, 0.0]},
	"fallow": {"spring": ["6a7a3c", 0.0, 0.0], "summer": ["8a884a", 0.0, 0.0], "autumn": ["7c7348", 0.0, 0.0], "winter": ["6f694c", 0.0, 0.0]},
	"orchard": {"spring": ["66803c", 0.0, 0.0], "summer": ["5f7836", 0.0, 0.0], "autumn": ["74703e", 0.0, 0.0], "winter": ["67603f", 0.0, 0.0]},
}
## An orchard's trees by season: crown colour (spring blossom, autumn turning, winter bare), size
## [min, max] of ZoneScatter's tree, rows ORCHARD_ROW_M apart and ORCHARD_STEP_M along, inset.
const ORCHARD_CROWNS := {"spring": ["e6d6da", "dcc8cf", "8fa25a"], "summer": ["4f6e2e", "5a7834"], "autumn": ["8a7a32", "9a6a2e", "6e7230"], "winter": ["6a5a48", "5e5244"]}
const ORCHARD_SIZE := [0.5, 0.62]
const ORCHARD_ROW_M := 7.0
const ORCHARD_STEP_M := 6.0
const ORCHARD_INSET_M := 5.0
## Hedges: a bush every HEDGE_STEP_M along a field's edge, a tree every HEDGE_TREE_EVERY bushes.
const HEDGE_STEP_M := 2.6
const HEDGE_TREE_EVERY := 6
## Fields keep FIELD_PAD_M off a pad's rect, FIELD_EDGE_M inside the zone, off ground steeper
## than FIELD_UP (the up component of its normal) and off water.
const FIELD_PAD_M := 6.0
const FIELD_EDGE_M := 40.0
const FIELD_UP := 0.96
## Crops drawn near the camera: per CROP_CELL_M cell within CROP_SEE_M (freed past CROP_DROP_M),
## CROP_PER_FRAME cells a frame; blocks CROP_STEPS x CROP_STEPS a 4 m ground cell.
const CROP_CELL_M := 32.0
const CROP_SEE_M := 170.0
const CROP_DROP_M := 240.0
const CROP_PER_FRAME := 1
const CROP_STEPS := 3
## Reed beds drawn per REED_CELL_M cell, seen to REED_SEE_M; a clump every REED_STEP_M.
const REED_CELL_M := 64.0
const REED_SEE_M := 260.0
const REED_STEP_M := 2.2
## Reed beds hide like tall crops (cover a metre).
const REED_COVER := 0.3
## cover_least marches this far from each end of a line, a metre a step.
const COVER_MARCH_M := 25.0
## Bump when what the features make changes (the scatter's cache keys on checksum()).
const LAYOUT_VERSION := 1

var terrain: ZoneTerrain
var spec := {}
var season := Season.DEFAULT
## Gullies and ditches: {"kind" ("gully" | "ditch"), "pts" (PackedVector2Array every STEP_M),
## "depth", "half", "floor"}.
var lines: Array = []
## Cliffs: {"a" (Vector2: one end of the face's line), "dir" (along it), "normal" (toward the high
## side), "len", "h", "plateau", "back"}.
var cliffs: Array = []
## The field grid: turned by _field_angle; column and row edges along its axes (m), each column's
## rows shifted along it by its own row_shift (a staggered patchwork, not a chessboard).
var field_cols := PackedFloat32Array()
var field_rows := PackedFloat32Array()
var row_shift := PackedFloat32Array()
## Per field (col * rows + row): its crop ("" none: kept open), and the orchards' field ids.
var field_crops := PackedStringArray()
var orchards: Array[int] = []
## What carve() took (ms), for checks and the zone's log line.
var carve_ms := 0.0

var _rng := RandomNumberGenerator.new()
var _half := 0.0
var _field_angle := 0.0
var _field_dir := Vector2.RIGHT
var _farm_noise: FastNoiseLite
var _farm_from := -INF
var _soft_noise: FastNoiseLite
var _soft_from := INF
var _reed_noise: FastNoiseLite
var _drift_noise: FastNoiseLite
var _wobble: FastNoiseLite
var _pads: Array[Rect2] = []
var _roads: Array = []  # [Vector2, Vector2]
var _keep_cells := {}  # Vector2i -> [pad indices, road indices]
var _cut := PackedByteArray()  # 0..255: how deep in a gully or ditch each height point is
var _slow := PackedByteArray()  # memo per height point: 255 - not yet, else the pace kept x 254
var _wet_known := false  # finish() ran: the water is there to keep the fields off
var _marsh := {}
var _snow := {}
var _fields := {}
var _planting := false
var _visuals_on := false
var _crop_cells := {}  # Vector2i -> MultiMeshInstance3D (or null: nothing in it)
var _reed_cells := {}
var _material: StandardMaterial3D
var _crop_mesh: ArrayMesh
var _next_check := 0.0


## Plans and carves `t`'s features into its heights (after the pads, before the water). Null when
## its preset has none (or the def says "no_features": checks).
static func carve(t: ZoneTerrain, def: Dictionary) -> ZoneFeatures:
	var f_spec: Dictionary = t.preset.get("features", {})
	if f_spec.is_empty() or def.get("no_features", false):
		return null
	var f := ZoneFeatures.new()
	f.name = "Features"
	f.terrain = t
	f.spec = f_spec
	f.season = Season.of_def(def)
	f._generate(def)
	return f


func _generate(def: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	_half = terrain.size_m * 0.5
	_rng.seed = terrain.seed_value ^ 0x7E3A1
	for pad: Array in terrain.pads:
		_pads.append(pad[0])
	for road: Array in def.get("roads", []):
		_roads.append([Vector2(float(road[0][0]), float(road[0][1])), Vector2(float(road[1][0]), float(road[1][1]))])
	_build_keep_cells()
	_wobble = _noise(41, 1.0 / 40.0)
	if spec.has("marsh"):
		_marsh = MARSH_DEFAULTS.merged(spec.marsh, true)
		_soft_noise = _noise(43, 1.0 / float(_marsh.wavelength_m))
		_soft_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_soft_noise.fractal_octaves = 3
		_soft_from = _quantile(_soft_noise, 1.0 - float(_marsh.share))
		_reed_noise = _noise(44, 1.0 / 45.0)
	if spec.has("snow"):
		_snow = SNOW_DEFAULTS.merged(spec.snow, true)
		_drift_noise = _noise(45, 1.0 / 70.0)
		_drift_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_drift_noise.fractal_octaves = 3
	if spec.has("cliffs"):
		_plan_cliffs(CLIFF_DEFAULTS.merged(spec.cliffs, true))
	for kind: String in ["gullies", "ditches"]:
		if spec.has(kind):
			_plan_lines("gully" if kind == "gullies" else "ditch", (GULLY_DEFAULTS if kind == "gullies" else DITCH_DEFAULTS).merged(spec[kind], true))
	if spec.has("fields"):
		_fields = FIELD_DEFAULTS.merged(spec.fields, true)
		_plan_fields()
	if not _marsh.is_empty() or not _snow.is_empty():
		_slow.resize(terrain.points * terrain.points)
		_slow.fill(255)
	carve_ms = (Time.get_ticks_usec() - started) / 1000.0


## After the water is carved (ZoneTerrain.generate): the cliffs and gullies go into the heights
## now, kept off the water (a stream cuts a notch through a cliff, not a canyon: carved before the
## water, a stream held at its level through a cliff cut 30 m down), and the fields keep off it.
func finish() -> void:
	_wet_known = true
	var started := Time.get_ticks_usec()
	for c: Dictionary in cliffs:
		_carve_cliff(c)
	if not lines.is_empty():
		_carve_lines()
	carve_ms += (Time.get_ticks_usec() - started) / 1000.0


func _noise(salt: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = terrain.seed_value + salt
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = frequency
	return n


## The value of `n` that `share` of the zone lies under (a 48 x 48 sample): a share in the data
## becomes a threshold, whatever the noise's spread.
func _quantile(n: FastNoiseLite, share: float) -> float:
	var vals := PackedFloat32Array()
	for j in 48:
		for i in 48:
			vals.append(n.get_noise_2d((i + 0.5) / 48.0 * terrain.size_m - _half, (j + 0.5) / 48.0 * terrain.size_m - _half))
	vals.sort()
	return vals[clampi(int(share * vals.size()), 0, vals.size() - 1)]


func _count(v: Variant) -> int:
	return _rng.randi_range(int(v[0]), int(v[1])) if v is Array else int(v)


func _range(v: Variant) -> float:
	return _rng.randf_range(float(v[0]), float(v[1])) if v is Array else float(v)


# --- Keeping off pads, roads and the edge -----------------------------------------------------

func _build_keep_cells() -> void:
	var reach := maxf(PAD_FAR_M, CLIFF_ROAD_M.y) + 10.0
	for k in _pads.size():
		_stamp_keep(_pads[k].grow(maxf(reach, CLIFF_PAD_M)), 0, k)
	for k in _roads.size():
		var r: Array = _roads[k]
		_stamp_keep(Rect2(r[0], Vector2.ZERO).expand(r[1]).grow(reach), 1, k)


func _stamp_keep(box: Rect2, slot: int, index: int) -> void:
	for cz in range(floori(box.position.y / KEEP_CELL_M), floori(box.end.y / KEEP_CELL_M) + 1):
		for cx in range(floori(box.position.x / KEEP_CELL_M), floori(box.end.x / KEEP_CELL_M) + 1):
			var key := Vector2i(cx, cz)
			if not _keep_cells.has(key):
				_keep_cells[key] = [PackedInt32Array(), PackedInt32Array()]
			var list: PackedInt32Array = _keep_cells[key][slot]
			list.append(index)
			_keep_cells[key][slot] = list


## The nearest pad rect's distance from `p` (m; INF with none near).
func pad_distance(p: Vector2) -> float:
	var cell: Variant = _keep_cells.get(Vector2i(floori(p.x / KEEP_CELL_M), floori(p.y / KEEP_CELL_M)))
	var d := INF
	if cell != null:
		for k: int in cell[0]:
			d = minf(d, ZoneTerrain._distance_to_rect(p, _pads[k]))
	return d


## The nearest road's distance from `p` (m; INF with none near).
func road_distance(p: Vector2) -> float:
	var cell: Variant = _keep_cells.get(Vector2i(floori(p.x / KEEP_CELL_M), floori(p.y / KEEP_CELL_M)))
	var d := INF
	if cell != null:
		for k: int in cell[1]:
			var r: Array = _roads[k]
			d = minf(d, Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p))
	return d


## 0 to 1: how much of a feature's carve stands at `p`: none near a pad or (within road.x, full
## from road.y) a road, or near the zone's edge.
func _keep_at(p: Vector2, road: Vector2) -> float:
	var edge := minf(minf(p.x + _half, _half - p.x), minf(p.y + _half, _half - p.y))
	var k := smoothstep(EDGE_NEAR_M, EDGE_FAR_M, edge)
	if k <= 0.0:
		return 0.0
	k *= smoothstep(PAD_NEAR_M, PAD_FAR_M, pad_distance(p))
	if k <= 0.0:
		return 0.0
	if _wet_known and terrain.water and terrain.water.keeps_clear(p.x, p.y):
		return 0.0  # a river's, stream's or pond's water and banks (and the bridges) keep their ground
	return k * smoothstep(road.x, road.y, road_distance(p))


func _inside(p: Vector2, margin: float) -> bool:
	return absf(p.x) <= _half - margin and absf(p.y) <= _half - margin


# --- Gullies and ditches ----------------------------------------------------------------------

## Plans `count` gullies or ditches (`kind`): each from a seeded start, wandering (`meander`)
## and leaning downhill, `length_m` long, clear of pads, cliffs and the others.
func _plan_lines(kind: String, s: Dictionary) -> void:
	for k in _count(s.count):
		var wig := _noise(300 + lines.size(), 1.0 / 90.0)
		for attempt in 30:
			var length := _range(s.length_m)
			var start := Vector2(_rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M), _rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M))
			var dir := Vector2.from_angle(_rng.randf() * TAU)
			var depth := _range(s.depth_m)
			var half := _range(s.half_m)
			if not _line_clear(start, half):
				continue
			var pts := PackedVector2Array([start])
			var ok := true
			for step in int(length / STEP_M):
				var p := pts[pts.size() - 1]
				var e := 4.0
				var down := Vector2(terrain.plane_height(p.x - e, p.y) - terrain.plane_height(p.x + e, p.y),
					terrain.plane_height(p.x, p.y - e) - terrain.plane_height(p.x, p.y + e))
				if down.length() > 0.05:
					dir = dir.slerp(down.normalized(), 0.12).normalized()
				dir = dir.rotated(wig.get_noise_1d(step * STEP_M) * float(s.meander)).normalized()
				var q := p + dir * STEP_M
				if not _inside(q, EDGE_KEEP_M * 0.7) or not _line_clear(q, half):
					ok = false
					break
				pts.append(q)
			if not ok:
				continue
			lines.append({"kind": kind, "pts": pts, "depth": depth, "half": half, "floor": float(s.floor_m)})
			break


## Whether a gully or ditch `half` wide may pass `p`: clear of pads, other lines and cliffs.
func _line_clear(p: Vector2, half: float) -> bool:
	if pad_distance(p) < LINE_PAD_GAP_M + half:
		return false
	for l: Dictionary in lines:
		var pts: PackedVector2Array = l.pts
		for i in range(0, pts.size(), 2):
			if pts[i].distance_to(p) < LINE_GAP_M + half + float(l.half):
				return false
	for c: Dictionary in cliffs:
		if _cliff_reach(c, p) < LINE_GAP_M:
			return false
	return true


## Carves every gully and ditch: per height point the deepest cut over it (its floor full depth,
## its sides easing up to its half width, its ends tapered over END_M), faded off pads, roads and
## the edge; _cut keeps how deep (the ground's colour, checks).
func _carve_lines() -> void:
	var n := terrain.points
	var cell := ZoneTerrain.CELL_M
	_cut.resize(n * n)
	var cut := {}  # height index -> metres cut
	for l: Dictionary in lines:
		var pts: PackedVector2Array = l.pts
		var half := float(l.half)
		var fl := float(l.floor)
		var depth := float(l.depth)
		var total := (pts.size() - 1) * STEP_M
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var box := Rect2(a, Vector2.ZERO).expand(b).grow(half + cell)
			for j in range(maxi(floori((box.position.y + _half) / cell), 0), mini(ceili((box.end.y + _half) / cell), n - 1) + 1):
				for i in range(maxi(floori((box.position.x + _half) / cell), 0), mini(ceili((box.end.x + _half) / cell), n - 1) + 1):
					var p := Vector2(i * cell - _half, j * cell - _half)
					var ab := b - a
					var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
					var d := (a + ab * t).distance_to(p)
					if d >= half:
						continue
					var along := (s + t) * STEP_M
					var taper := smoothstep(0.0, END_M, along) * smoothstep(total, total - END_M, along)
					var m := depth * (1.0 - smoothstep(fl, half, d)) * taper * (0.85 + 0.15 * _wobble.get_noise_1d(along + s))
					var idx := i + j * n
					if m > float(cut.get(idx, 0.0)):
						cut[idx] = m
	var heights := terrain.heights
	for idx: int in cut:
		var p := Vector2((idx % n) * cell - _half, (idx / n) * cell - _half)
		var m := float(cut[idx]) * _keep_at(p, GULLY_ROAD_M)
		if m <= 0.0:
			continue
		heights[idx] -= m
		_cut[idx] = clampi(int(m / 3.0 * 255.0), 0, 255)
	terrain.heights = heights


## How deep (m, as carved) the gully or ditch cut is at height point (i, j); 0 off them.
func cut_at(i: int, j: int) -> float:
	if _cut.is_empty():
		return 0.0
	var n := terrain.points
	return float(_cut[clampi(i, 0, n - 1) + clampi(j, 0, n - 1) * n]) / 255.0 * 3.0


# --- Cliffs -----------------------------------------------------------------------------------

## Plans `count` cliffs: a seeded line with its high side where the ground already rises, clear of
## pads (CLIFF_PAD_M), other cliffs and the edge; the first tries also keep clear of the roads.
func _plan_cliffs(s: Dictionary) -> void:
	for k in _count(s.count):
		for attempt in 40:
			var length := _range(s.length_m)
			var c := Vector2(_rng.randf_range(-_half + EDGE_KEEP_M + 60.0, _half - EDGE_KEEP_M - 60.0), _rng.randf_range(-_half + EDGE_KEEP_M + 60.0, _half - EDGE_KEEP_M - 60.0))
			var dir := Vector2.from_angle(_rng.randf() * TAU)
			var normal := Vector2(-dir.y, dir.x)
			var h := _range(s.height_m)
			var plateau := _range(s.plateau_m)
			var back := _range(s.back_m)
			if terrain.plane_height(c.x + normal.x * 40.0, c.y + normal.y * 40.0) < terrain.plane_height(c.x - normal.x * 40.0, c.y - normal.y * 40.0):
				normal = -normal
			var cliff := {"a": c - dir * length * 0.5, "dir": dir, "normal": normal, "len": length, "h": h, "plateau": plateau, "back": back,
				"talus": float(s.talus_per_m)}
			if not _cliff_fits(cliff, attempt < 25):
				continue
			cliffs.append(cliff)
			break


## Whether `c` stands clear of the pads and other cliffs (and the roads, `avoid_roads`), its
## footprint inside the zone.
func _cliff_fits(c: Dictionary, avoid_roads: bool) -> bool:
	var a: Vector2 = c.a
	var dir: Vector2 = c.dir
	var normal: Vector2 = c.normal
	var length := float(c.len)
	var deep := float(c.plateau) + float(c.back)
	var corners := [a - normal * 12.0, a + dir * length - normal * 12.0, a + normal * deep, a + dir * length + normal * deep]
	for p: Vector2 in corners:
		if not _inside(p, EDGE_KEEP_M * 0.8):
			return false
	for t in range(0, int(length) + 1, 12):
		for off: float in [-12.0, 0.0, deep * 0.3, deep * 0.6, deep]:
			var p: Vector2 = a + dir * t + normal * off
			if pad_distance(p) < CLIFF_PAD_M:
				return false
			if avoid_roads and road_distance(p) < CLIFF_ROAD_M.y * 0.5:
				return false
			for other: Dictionary in cliffs:
				if _cliff_reach(other, p) < CLIFF_GAP_M * 0.5:
					return false
	return true


## How far `p` is from cliff `c`'s footprint (0 inside it).
func _cliff_reach(c: Dictionary, p: Vector2) -> float:
	var v: Vector2 = p - (c.a as Vector2)
	var along := v.dot(c.dir)
	var side := v.dot(c.normal)
	var da := maxf(maxf(-along, along - float(c.len)), 0.0)
	var ds := maxf(maxf(-12.0 - side, side - float(c.plateau) - float(c.back)), 0.0)
	return Vector2(da, ds).length()


## Cliff `c`'s rise (0 to 1 of its height) at `p`, before the keep: the face across
## CLIFF_FACE_M (wandering CLIFF_WOBBLE_M), the ledge, the back slope, the ends tapered.
func _cliff_rise(c: Dictionary, p: Vector2) -> float:
	var v: Vector2 = p - (c.a as Vector2)
	var along := v.dot(c.dir)
	var length := float(c.len)
	if along < 0.0 or along > length:
		return 0.0
	var side := v.dot(c.normal) - _wobble.get_noise_1d(along + float(c.h) * 37.0) * CLIFF_WOBBLE_M
	var f := CLIFF_FACE_M * 0.5
	if side < -f:
		return 0.0
	var top := float(c.plateau)
	var rise := smoothstep(-f, f, side) if side < f else 1.0 - smoothstep(f + top, f + top + float(c.back), side)
	return rise * smoothstep(0.0, CLIFF_END_M, along) * smoothstep(length, length - CLIFF_END_M, along)


func _carve_cliff(c: Dictionary) -> void:
	var a: Vector2 = c.a
	var dir: Vector2 = c.dir
	var normal: Vector2 = c.normal
	var length := float(c.len)
	var deep := float(c.plateau) + float(c.back) + 4.0
	var box := Rect2(a - normal * 8.0, Vector2.ZERO).expand(a + dir * length - normal * 8.0).expand(a + normal * deep).expand(a + dir * length + normal * deep)
	var n := terrain.points
	var cell := ZoneTerrain.CELL_M
	var h := float(c.h)
	var heights := terrain.heights
	for j in range(maxi(floori((box.position.y + _half) / cell), 0), mini(ceili((box.end.y + _half) / cell), n - 1) + 1):
		for i in range(maxi(floori((box.position.x + _half) / cell), 0), mini(ceili((box.end.x + _half) / cell), n - 1) + 1):
			var p := Vector2(i * cell - _half, j * cell - _half)
			var r := _cliff_rise(c, p)
			if r <= 0.0:
				continue
			heights[i + j * n] += h * r * _keep_at(p, CLIFF_ROAD_M)
	terrain.heights = heights


## A point on cliff `c`'s face `t` (0..1) along it, `off` metres out from the face (negative: at
## its foot, positive: on its top), on the ground: checks and the talus.
func cliff_point(c: Dictionary, t: float, off: float) -> Vector3:
	var along := float(c.len) * t
	var side := _wobble.get_noise_1d(along + float(c.h) * 37.0) * CLIFF_WOBBLE_M + off
	var p: Vector2 = (c.a as Vector2) + (c.dir as Vector2) * along + (c.normal as Vector2) * side
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


# --- Marsh and snow ---------------------------------------------------------------------------

## 0 to 1: how soft (marsh) the ground at (x, z) is; 0 on pads, roads and dry presets.
func soft_at(x: float, z: float) -> float:
	if _marsh.is_empty():
		return 0.0
	var v := _soft_noise.get_noise_2d(x, z)
	var s := smoothstep(_soft_from, _soft_from + 0.12, v)
	if s <= 0.0:
		return 0.0
	var p := Vector2(x, z)
	return s * smoothstep(2.0, 10.0, pad_distance(p)) * smoothstep(3.0, 8.0, road_distance(p))


## 0 to 1: how much of a reed bed stands at (x, z) (marsh only).
func reeds_at(x: float, z: float) -> float:
	if _marsh.is_empty() or float(_marsh.reeds) <= 0.0:
		return 0.0
	var soft := soft_at(x, z)
	if soft < 0.5:
		return 0.0
	return smoothstep(1.0 - float(_marsh.reeds) * 2.0, 1.0 - float(_marsh.reeds) * 2.0 + 0.15, _reed_noise.get_noise_2d(x, z) * 0.5 + 0.5) * soft


## The snow line now (m): the season's (snow "line_m").
func snow_line() -> float:
	return float((_snow.line_m as Dictionary).get(season, 0.0))


## 0 to 1: how much snow lies at (x, z): over the snow line (fading in over 6 m), off steep rock,
## thinner where the wind takes it ("drifts"). 0 on presets with no snow.
func snow_at(x: float, z: float) -> float:
	if _snow.is_empty():
		return 0.0
	var h := terrain.height_at(x, z)
	var line := snow_line()
	var s := float(_snow.cover) * smoothstep(line - 2.0, line + 4.0, h)
	if s <= 0.0:
		return 0.0
	s *= smoothstep(0.66, 0.8, terrain.normal_at(x, z).y)
	var d := _drift_noise.get_noise_2d(x, z) * 0.5 + 0.5
	return s * (1.0 - float(_snow.drifts) * smoothstep(0.55, 0.85, d))


## The share of his pace a man on foot keeps at (x, z): soft marsh ground and snow slow him
## (marsh "slow", snow "slow"; packed snow on the roads and tracks doesn't). Memoised per height
## point (Wading.ground_mult asks every physics step).
func slow_at(x: float, z: float) -> float:
	if _slow.is_empty():
		return 1.0
	var n := terrain.points
	var i := clampi(roundi((x + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	var j := clampi(roundi((z + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	var idx := i + j * n
	var v := _slow[idx]
	if v == 255:
		var px := i * ZoneTerrain.CELL_M - _half
		var pz := j * ZoneTerrain.CELL_M - _half
		var m := 1.0
		if not _marsh.is_empty():
			m *= 1.0 - float(_marsh.slow) * soft_at(px, pz)
		if not _snow.is_empty():
			var packed := maxf(terrain.road_weight(px, pz), 1.0 - smoothstep(2.0, 8.0, pad_distance(Vector2(px, pz))))
			m *= 1.0 - float(_snow.slow) * snow_at(px, pz) * (1.0 - packed)
		v = clampi(roundi(m * 254.0), 0, 254)
		_slow[idx] = v
	return float(v) / 254.0


# --- Fields -----------------------------------------------------------------------------------

## The field grid: turned by a seeded angle, its column and row edges `size_m` apart (seeded),
## a crop for each field by the weights, some orchards (at most "orchards_max") among the fields
## that lie inside the zone; where the farm noise is under "share", no fields (rough ground).
func _plan_fields() -> void:
	_field_angle = _rng.randf() * PI
	_field_dir = Vector2.from_angle(_field_angle)
	var reach := _half * 1.42
	field_cols = _field_edges(reach)
	field_rows = _field_edges(reach)
	row_shift.resize(field_cols.size())
	for c in field_cols.size():
		row_shift[c] = _rng.randf_range(0.0, float(_fields.size_m[0]))
	_farm_noise = _noise(46, 1.0 / 520.0)
	_farm_from = _quantile(_farm_noise, 1.0 - float(_fields.share)) if float(_fields.share) < 1.0 else -INF
	var crops: Dictionary = _fields.crops
	var weight := 0.0
	for k: String in crops:
		weight += float(crops[k])
	var cols := field_cols.size() - 1
	var rows := field_rows.size() - 1
	field_crops.resize(cols * rows)
	var eligible: Array[int] = []
	for c in cols:
		for r in rows:
			var roll := _rng.randf() * weight
			var pick := ""
			for k: String in crops:
				roll -= float(crops[k])
				if roll <= 0.0:
					pick = k
					break
			field_crops[c * rows + r] = pick if pick != "" else String(crops.keys()[0])
			var mid := _from_grid(Vector2((field_cols[c] + field_cols[c + 1]) * 0.5, (field_rows[r] + field_rows[r + 1]) * 0.5 + row_shift[c]))
			var span := minf(field_cols[c + 1] - field_cols[c], field_rows[r + 1] - field_rows[r])
			if _inside(mid, span + FIELD_EDGE_M) and _farm_noise.get_noise_2d(mid.x, mid.y) >= _farm_from and pad_distance(mid) > span:
				eligible.append(c * rows + r)
	var want := mini(int(round(eligible.size() * float(_fields.orchard_share))), int(_fields.orchards_max))
	while orchards.size() < want and not eligible.is_empty():
		var id: int = eligible.pop_at(_rng.randi() % eligible.size())
		orchards.append(id)
		field_crops[id] = "orchard"


## Field edges from -reach to past reach, "size_m" apart (seeded).
func _field_edges(reach: float) -> PackedFloat32Array:
	var edges := PackedFloat32Array()
	var at := -reach
	while at < reach:
		edges.append(at)
		at += _range(_fields.size_m)
	edges.append(at)
	return edges


## A point on the ground (x, z) in the field grid's frame, and back.
func _to_grid(p: Vector2) -> Vector2:
	return Vector2(p.dot(_field_dir), p.dot(Vector2(-_field_dir.y, _field_dir.x)))


func _from_grid(g: Vector2) -> Vector2:
	return _field_dir * g.x + Vector2(-_field_dir.y, _field_dir.x) * g.y


## The field at (x, z): its id (col * rows + row), -1 off the fields (rough ground, a lane between
## two, a pad, the water once it's there, steep ground, the zone's edge).
func field_at(x: float, z: float) -> int:
	if field_cols.is_empty():
		return -1
	var p := Vector2(x, z)
	if not _inside(p, FIELD_EDGE_M) or _farm_noise.get_noise_2d(x, z) < _farm_from:
		return -1
	var g := _to_grid(p)
	var c := field_cols.bsearch(g.x) - 1
	if c < 0 or c >= field_cols.size() - 1:
		return -1
	var v := g.y - row_shift[c]
	var r := field_rows.bsearch(v) - 1
	if r < 0 or r >= field_rows.size() - 1:
		return -1
	var lane := float(_fields.lane_m)
	if minf(g.x - field_cols[c], field_cols[c + 1] - g.x) < lane or minf(v - field_rows[r], field_rows[r + 1] - v) < lane:
		return -1
	if pad_distance(p) < FIELD_PAD_M:
		return -1
	if _wet_known and terrain.water and terrain.water.keeps_clear(x, z):
		return -1
	if terrain.normal_at(x, z).y < FIELD_UP:
		return -1
	return c * (field_rows.size() - 1) + r


## What grows in field `id` this season: {"crop", "colour", "height", "cover"} ({} for none).
func crop_of(id: int) -> Dictionary:
	if id < 0 or id >= field_crops.size() or field_crops[id] == "":
		return {}
	var crop := field_crops[id]
	var row: Array = (CROPS.get(crop, CROPS.fallow) as Dictionary)[season]
	return {"crop": crop, "colour": Color(String(row[0])), "height": float(row[1]), "cover": float(row[2])}


## The irrigation channels' lines (ZoneWater "channels" asks, as it carves): along a seeded
## "channels" share of the column edges (straight lines: the rows are staggered), every stretch
## where both sides are fields (clear of pads and the edge) and the ground keeps within 3 m of
## level, cut into lengths of at most channel_m[1] and kept from channel_m[0] * 0.6; each a
## polyline every ZoneWater.STEP_M.
func channel_lines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if field_cols.is_empty() or float(_fields.channels) <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value ^ 0xD17C4
	var step := ZoneWater.STEP_M
	var side := _from_grid(Vector2(6.0, 0.0))
	var shortest := float(_fields.channel_m[0]) * 0.6
	var longest := float(_fields.channel_m[1])
	for e in range(1, field_cols.size() - 1):
		if rng.randf() >= float(_fields.channels):
			continue
		var run := PackedVector2Array()
		var lo := INF
		var hi := -INF
		var y := field_rows[0]
		while y <= field_rows[field_rows.size() - 1] + step:
			var p := _from_grid(Vector2(field_cols[e], y))
			y += step
			var ok := _inside(p, FIELD_EDGE_M + 30.0) and pad_distance(p) >= ZoneWater.PAD_CLEAR_M + 12.0 \
				and field_at(p.x + side.x, p.y + side.y) >= 0 and field_at(p.x - side.x, p.y - side.y) >= 0
			var h := terrain.plane_height(p.x, p.y) if ok else 0.0
			if ok and run.size() * step < longest and maxf(hi, h) - minf(lo, h) <= 3.0:
				run.append(p)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				continue
			if run.size() * step >= shortest:
				out.append(run)
			run = PackedVector2Array([p]) if ok else PackedVector2Array()
			lo = h if ok else INF
			hi = h if ok else -INF
		if run.size() * step >= shortest:
			out.append(run)
	return out


# --- The ground's colour ----------------------------------------------------------------------

## Height point (i, j)'s colour (at `p`, its normal `n`) with the features over `colour`: a
## field's crop, marsh mud, snow, a gully's bare earth (ZoneTerrain._ground_colour).
func tint(i: int, j: int, p: Vector2, colour: Color, n: Vector3) -> Color:
	if not _cut.is_empty():
		var cut := cut_at(i, j)
		if cut > 0.05:
			colour = colour.lerp(terrain.c_earth.lerp(terrain.c_dry, 0.3), clampf(cut / 1.6, 0.0, 0.55))
	if not field_cols.is_empty():
		var crop := crop_of(field_at(p.x, p.y))
		if not crop.is_empty():
			var jitter := float(absi(hash(Vector2i(i / 3, j / 3) + Vector2i(terrain.seed_value, 9))) % 100) / 100.0
			colour = colour.lerp((crop.colour as Color).darkened(jitter * 0.06), 0.85)
	if not _marsh.is_empty():
		var soft := soft_at(p.x, p.y)
		if soft > 0.0:
			colour = colour.lerp(Color(String(_marsh.colour)), soft * 0.7)
	if not _snow.is_empty():
		var snow := snow_at(p.x, p.y)
		if snow > 0.0:
			colour = colour.lerp(Color(String(_snow.colour)), snow * 0.95)
	return colour


## The ground shader's snow (ZoneTerrain.ground_material): 0 with no snow.
func snow_strength() -> float:
	return 1.0 if not _snow.is_empty() else 0.0


# --- The scatter ------------------------------------------------------------------------------

## Whether ZoneScatter keeps its rocks, trees, scrub and ground cover off (x, z): a field (its
## own orchards and hedges go in through lay_out).
func keeps_clear(x: float, z: float) -> bool:
	if _planting or field_cols.is_empty():
		return false
	return field_at(x, z) >= 0


## Lays what the features bring into ZoneScatter's layout (before its trees): fallen rock at the
## foot of each cliff, each orchard's rows of fruit trees, and hedges along some field edges.
func lay_out(s: ZoneScatter) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value ^ 0x7A105
	_planting = true
	s._tree_limit = s._cap_trees
	for c: Dictionary in cliffs:
		_talus(s, rng, c)
	for id in orchards:
		_orchard(s, rng, id)
	if not field_cols.is_empty() and float(_fields.hedges) > 0.0:
		_hedges(s, rng)
	_planting = false


func _talus(s: ZoneScatter, rng: RandomNumberGenerator, c: Dictionary) -> void:
	var colours: Array = s._rock_colours if not s._rock_colours.is_empty() else [terrain.c_rock]
	for k in int(float(c.len) * float(c.talus)):
		var t := rng.randf()
		var size := rng.randf_range(0.5, 2.4)
		var p := cliff_point(c, t, -rng.randf_range(2.0, 10.0))
		if _keep_at(Vector2(p.x, p.z), CLIFF_ROAD_M) < 0.5 or s._blocked(p.x, p.z, s._keep, s._roads) or terrain.normal_at(p.x, p.z).y < 0.6:
			continue
		var large := size > 1.5 and s.solid_count < s._cap_solid
		var dims := Vector3(size, size * rng.randf_range(0.55, 0.85), size * rng.randf_range(0.8, 1.2))
		s._add({"kind": ZoneScatter.Kind.ROCK, "yaw": rng.randf() * TAU, "solid": large, "size": dims, "pos": Vector3(p.x, p.y + dims.y * 0.3, p.z),
			"colour": colours[rng.randi() % colours.size()]})


func _orchard(s: ZoneScatter, rng: RandomNumberGenerator, id: int) -> void:
	var rows := field_rows.size() - 1
	var c := id / rows
	var r := id % rows
	var crowns: Array = ORCHARD_CROWNS[season]
	var u := field_cols[c] + ORCHARD_INSET_M
	while u < field_cols[c + 1] - ORCHARD_INSET_M:
		var v := field_rows[r] + row_shift[c] + ORCHARD_INSET_M
		while v < field_rows[r + 1] + row_shift[c] - ORCHARD_INSET_M:
			var p := _from_grid(Vector2(u, v))
			if field_at(p.x, p.y) == id and not s._blocked(p.x, p.y, s._keep, s._roads) and s.counts[ZoneScatter.Kind.TREE] < s._cap_trees:
				var size := rng.randf_range(float(ORCHARD_SIZE[0]), float(ORCHARD_SIZE[1]))
				s._add({"kind": ZoneScatter.Kind.TREE, "pos": Vector3(p.x, terrain.height_at(p.x, p.y), p.y), "yaw": rng.randf() * TAU,
					"size": Vector3(size, size, size), "colour": Color(String(crowns[rng.randi() % crowns.size()])), "solid": true, "orchard": true})
			v += ORCHARD_STEP_M
		u += ORCHARD_ROW_M


## Hedges: a seeded "hedges" share of the field edges' pieces (one field's side each) that run
## between fields, a bush every HEDGE_STEP_M along the lane and a tree every HEDGE_TREE_EVERY.
func _hedges(s: ZoneScatter, rng: RandomNumberGenerator) -> void:
	for axis in 2:
		var edges: PackedFloat32Array = field_cols if axis == 0 else field_rows
		var across: PackedFloat32Array = field_rows if axis == 0 else field_cols
		for e in range(1, edges.size() - 1):
			for piece in across.size() - 1:
				if rng.randf() >= float(_fields.hedges):
					continue
				# A field's side: along a column edge (its rows shifted with the column after it), or
				# along a row edge within one column (shifted with that column).
				var shift := row_shift[e] if axis == 0 else 0.0
				var line := 0.0 if axis == 0 else row_shift[piece]
				var mid := (across[piece] + across[piece + 1]) * 0.5 + shift
				var centre := _from_grid(Vector2(edges[e], mid) if axis == 0 else Vector2(mid, edges[e] + line))
				if not _inside(centre, ZoneScatter.EDGE_KEEP_M + 4.0) or not _farmed(centre):
					continue
				var at := across[piece] + shift + HEDGE_STEP_M
				var k := 0
				while at < across[piece + 1] + shift - HEDGE_STEP_M * 0.5:
					var p := _from_grid(Vector2(edges[e], at) if axis == 0 else Vector2(at, edges[e] + line))
					if k % HEDGE_TREE_EVERY == HEDGE_TREE_EVERY - 1:
						s._try_tree(rng, p.x, p.y, 0.7, 1.15)
					else:
						s._try_bush(rng, p.x, p.y, ZoneScatter.Kind.SCRUB, 1.2, 2.0)
					at += HEDGE_STEP_M
					k += 1


## Whether `p` (on a lane) runs between fields: a field a few metres either way.
func _farmed(p: Vector2) -> bool:
	var g := _to_grid(p)
	for d: Vector2 in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
		var q := _from_grid(g + d)
		if field_at(q.x, q.y) >= 0:
			return true
	return false


# --- Cover in the crops and reeds -------------------------------------------------------------

## How tall the cover standing at (x, z) is (m) and how much it hides a metre (foliage metres, as
## ZoneScatter's): a field's crop this season, or a reed bed. Vector2(height, per metre).
func cover_at(x: float, z: float) -> Vector2:
	if not field_cols.is_empty():
		var crop := crop_of(field_at(x, z))
		if not crop.is_empty() and float(crop.cover) > 0.0:
			return Vector2(float(crop.height), float(crop.cover))
	if not _marsh.is_empty():
		var reeds := reeds_at(x, z)
		if reeds > 0.4:
			return Vector2(float(_marsh.reed_h_m) * reeds, REED_COVER)
	return Vector2.ZERO


## The foliage metres (ZoneScatter.foliage_least's measure) the crops and reed beds add to the
## lines `from` -> `to_a` and `from` -> `to_b`: each line walked COVER_MARCH_M in from both ends,
## a metre a step, counting where it runs under the cover's top. Vector2(a, b).
func cover_least(from: Vector3, to_a: Vector3, to_b: Vector3) -> Vector2:
	if field_cols.is_empty() and (_marsh.is_empty() or float(_marsh.reeds) <= 0.0):
		return Vector2.ZERO
	return Vector2(_cover_line(from, to_a), _cover_line(from, to_b))


func _cover_line(from: Vector3, to: Vector3) -> float:
	var length := from.distance_to(to)
	if length < 0.5:
		return 0.0
	var total := 0.0
	var near_to := mini(int(COVER_MARCH_M), int(length))  # from the target back toward the eye
	var near_from := mini(int(COVER_MARCH_M), int(length) - near_to)  # and out from the eye (never the same metres twice)
	for end in 2:
		var a := to if end == 0 else from
		var b := from if end == 0 else to
		var steps := near_to if end == 0 else near_from
		var probe := a.lerp(b, minf(6.0 / length, 1.0))
		if steps <= 0 or (cover_at(a.x, a.z) == Vector2.ZERO and cover_at(probe.x, probe.z) == Vector2.ZERO):
			continue  # nothing standing at this end
		for k in steps:
			var q := a.lerp(b, (k + 0.5) / length)
			var cover := cover_at(q.x, q.z)
			if cover.x > 0.0 and q.y - terrain.height_at(q.x, q.z) < cover.x:
				total += cover.y
	return total


# --- Checks -----------------------------------------------------------------------------------

## A hash of what the features made (the season's crops too): two peers that built the same zone
## have the same (ZoneTerrain.checksum).
func checksum() -> int:
	var parts: Array = [LAYOUT_VERSION, season]
	for l: Dictionary in lines:
		parts.append([l.kind, l.pts, l.depth])
	for c: Dictionary in cliffs:
		parts.append([c.a, c.dir, c.h, c.len])
	parts.append([field_cols, field_rows, row_shift, field_crops, orchards])
	return hash(str(parts))


# --- Visuals ----------------------------------------------------------------------------------

func _ready() -> void:
	set_process(_visuals_on and (not field_cols.is_empty() or not _marsh.is_empty()))


## The crops and reed beds near the camera, built as it comes near (_process). Not on a headless
## server.
func build_visuals() -> void:
	if _visuals_on:
		return
	_visuals_on = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # (the blocks seen from any side)
	_crop_mesh = _make_crop_mesh()
	set_process(not field_cols.is_empty() or not _marsh.is_empty())


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_check:
		return
	_next_check = now + 0.2
	var camera := get_viewport().get_camera_3d()
	if camera:
		build_near(camera.global_position, CROP_PER_FRAME)


## Builds the crop and reed cells nearest `pos` (at most `budget` of each), frees the far ones;
## returns how many it built.
func build_near(pos: Vector3, budget: int) -> int:
	if not _visuals_on:
		return 0
	var built := 0
	if not field_cols.is_empty():
		built += _build_cells(_crop_cells, CROP_CELL_M, CROP_SEE_M, CROP_DROP_M, pos, budget, _crop_cell)
	if not _marsh.is_empty():
		built += _build_cells(_reed_cells, REED_CELL_M, REED_SEE_M, REED_SEE_M + 120.0, pos, budget, _reed_cell)
	return built


func _build_cells(cells: Dictionary, size: float, see: float, drop: float, pos: Vector3, budget: int, make: Callable) -> int:
	for c: Vector2i in cells.keys():
		var centre := Vector2((c.x + 0.5) * size, (c.y + 0.5) * size)
		if centre.distance_to(Vector2(pos.x, pos.z)) > drop:
			if cells[c] != null:
				(cells[c] as Node).queue_free()
			cells.erase(c)
	var wanted: Array = []
	var reach := ceili(see / size)
	var at := Vector2i(floori(pos.x / size), floori(pos.z / size))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := at + Vector2i(dx, dz)
			if cells.has(c):
				continue
			var centre := Vector2((c.x + 0.5) * size, (c.y + 0.5) * size)
			var d := centre.distance_to(Vector2(pos.x, pos.z))
			if d < see and _inside(centre, -size):
				wanted.append([d, c])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var built := 0
	for w: Array in wanted.slice(0, budget):
		var node: Node3D = make.call(w[1])
		cells[w[1]] = node
		if node:
			add_child(node)
		built += 1
	return built


## Crop cell `c`: blocks of the crop over each 4 m ground cell that is a field with something
## standing (CROP_STEPS x CROP_STEPS, maize in rows with lanes), its colour and height by season.
func _crop_cell(c: Vector2i) -> Node3D:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var cell := ZoneTerrain.CELL_M
	var x0 := c.x * CROP_CELL_M
	var z0 := c.y * CROP_CELL_M
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, terrain.seed_value))
	var turn := Basis(Vector3.UP, -_field_angle)
	var per := cell / CROP_STEPS
	for gz in int(CROP_CELL_M / cell):
		for gx in int(CROP_CELL_M / cell):
			var mx := x0 + (gx + 0.5) * cell
			var mz := z0 + (gz + 0.5) * cell
			var crop := crop_of(field_at(mx, mz))
			if crop.is_empty() or float(crop.height) < 0.12 or terrain.road_weight(mx, mz) > 0.2:
				continue
			var rows := String(crop.crop) == "maize"
			for sz in CROP_STEPS:
				for sx in CROP_STEPS:
					if rows and sx == 1:
						continue  # a lane between the rows
					var x := x0 + gx * cell + (sx + 0.5) * per + rng.randf_range(-0.15, 0.15)
					var z := z0 + gz * cell + (sz + 0.5) * per + rng.randf_range(-0.15, 0.15)
					var h := float(crop.height) * rng.randf_range(0.85, 1.1)
					var w := per * (0.75 if rows else 1.02)
					transforms.append(Transform3D(turn.scaled(Vector3(w, h, per * 1.02)), Vector3(x, terrain.height_at(x, z) - 0.05, z)))
					colours.append((crop.colour as Color).darkened(rng.randf() * 0.12).lightened(rng.randf() * 0.05))
	return _multimesh("Crops_%d_%d" % [c.x, c.y], _crop_mesh, transforms, colours, CROP_SEE_M + 20.0)


## Reed cell `c`: a clump of reeds every REED_STEP_M where a reed bed stands.
func _reed_cell(c: Vector2i) -> Node3D:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, terrain.seed_value + 7))
	var palette := [Color("7a7a42"), Color("8a8450"), Color("6a7038"), Color("958a58")]
	var n := int(REED_CELL_M / REED_STEP_M)
	for gz in n:
		for gx in n:
			var x := c.x * REED_CELL_M + (gx + rng.randf()) * REED_STEP_M
			var z := c.y * REED_CELL_M + (gz + rng.randf()) * REED_STEP_M
			var r := reeds_at(x, z)
			if r < 0.4 or rng.randf() > r or (terrain.water and terrain.water.keeps_clear(x, z) and terrain.water.depth_at(x, z) > 0.6):
				continue
			var s := rng.randf_range(0.9, 1.4) * lerpf(0.7, 1.05, r)
			transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.4, s, s * 1.4)), Vector3(x, terrain.height_at(x, z) - 0.05, z)))
			colours.append((palette[rng.randi() % palette.size()] as Color).darkened(rng.randf() * 0.15))
	return _multimesh("Reeds_%d_%d" % [c.x, c.y], ZoneWater.reed_mesh(), transforms, colours, REED_SEE_M)


func _multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colours: Array[Color], see: float) -> Node3D:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_color(k, colours[k])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = see
	node.visibility_range_end_margin = 20.0
	return node


## A crop block: a unit box standing on y = 0 (sides darker at the foot, a lighter ragged top
## of four steps), in the voxel look.
static func _make_crop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops := [0.92, 1.0, 0.86, 0.97]
	for q in 4:
		var x0 := -0.5 + (q % 2) * 0.5
		var z0 := -0.5 + (q / 2) * 0.5
		var y := float(tops[q])
		var lo := Vector3(x0, 0.0, z0)
		var hi := Vector3(x0 + 0.5, y, z0 + 0.5)
		var faces := [
			[Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, 1.1],
			[Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.FORWARD, 0.8],
			[Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.BACK, 0.8],
			[Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3.LEFT, 0.75],
			[Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.RIGHT, 0.75],
		]
		for f: Array in faces:
			for v: int in [0, 2, 1, 0, 3, 2]:
				var shade := float(f[5]) if v >= 2 or (f[4] as Vector3) == Vector3.UP else float(f[5]) * 0.7
				st.set_color(Color.WHITE * shade)
				st.set_normal(f[4])
				st.add_vertex(f[v])
	return st.commit()
