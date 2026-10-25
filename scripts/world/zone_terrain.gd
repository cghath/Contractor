class_name ZoneTerrain
extends Node3D
## The ground of a zone: a seeded heightmap covering the whole zone (ZoneDef "size_m"), the
## same on every peer. Not destructible: the 10 cm voxels are only in the modules placed on
## it (ZoneModule), which sit on flat pads cut into it.
##
## Heights are a grid every CELL_M metres. Collision is one HeightMapShape3D per CHUNK_CELLS
## chunk (Jolt height fields); the mesh is the same chunks at three levels of detail that
## Godot switches by distance (visibility ranges), with skirts hiding the seams between
## them. Heights fade to 0 at the zone's edge, where a flat apron carries the ground on to
## the horizon and an invisible wall keeps everyone in.
##
## The preset's sea is also the coast of wave 5b (V4: the LHD offshore, AAVs swimming in):
## has_coast(), shore_distance(), water_height(), seaward() and shore_point() at the end answer
## for it, so every zone with a sea gets the LHD, and every other zone the FOB.

## Grid spacing (m). Proposed: 4 m keeps a 2 km zone at 513 x 513 heights.
const CELL_M := 4.0
## Cells per chunk side (a power of two, so Jolt builds a height field).
const CHUNK_CELLS := 32
## Mesh levels of detail: cells per quad, and the distance (m) each one is drawn to.
const LOD_STEPS: Array[int] = [1, 4, 16]
const LOD_END_M: Array[float] = [450.0, 1200.0, 0.0]
## Skirts below each chunk's edges, per level of detail (m): hide cracks between levels.
const SKIRT_M: Array[float] = [1.5, 6.0, 16.0]
## The finest level is built for chunks within this distance of the camera, this many a frame.
const LOD0_BUILD_M := 650.0
const LOD0_PER_FRAME := 2
## Heights fade to 0 over this band inside the zone's edge.
const EDGE_FADE_M := 160.0
## Folds in the ground (Proposed; a preset's land "folds_m" / "folds_wavelength_m" overrides):
## swells and hollows this high (m, noise amplitude) over this wavelength.
const FOLDS_M := 2.6
const FOLDS_WAVELENGTH_M := 90.0
const FOLDS_FULL_RELIEF_M := 10.0
## Flat pads under modules and landing zones: this much beyond the footprint stays flat,
## then the ground blends back over PAD_BLEND_M.
const PAD_MARGIN_M := 6.0
const PAD_BLEND_M := 40.0
## The apron around the zone (m beyond the edge) and the invisible wall's height.
const APRON_M := 6000.0
## The water reaches this far past the shoreline strip so the beach is covered (m).
const SEA_MARGIN_M := 40.0
## The coast wobble (sea "coast_wobble_m") pushes the water inland at most this far.
const COAST_IN_M := 35.0
## Ground this far below the water is left out of the navigation mesh (m).
const NAV_WATER_M := 0.9
const WALL_HEIGHT_M := 400.0
## Ground colours: grass, dry grass, bare earth on slopes and on pads, rock on steep ground.
const GRASS := Color("5f6a3c")
## The ground's look (ground_material): vertex palette + world-space breakup, see the shader.
const GROUND_SHADER := preload("res://scripts/world/zone_ground.gdshader")
const DRY := Color("7d7748")
const EARTH := Color("7f6d4f")
const ROCK := Color("6f6a60")
## Ground within this distance of a road's line is tinted toward the road colour (full at
## ROAD_CORE_M, fading out by ROAD_VERGE_M).
const ROAD_CORE_M := 3.0
const ROAD_VERGE_M := 7.0
## The land's "margin" (a berm and mesas round the edge, salt_flats): it rises from this far in
## from the edge (the apron stays level with it), and the pads and roads it keeps clear of are
## measured on a grid this coarse (m). Proposed.
const MARGIN_FROM_M := 25.0
const MARGIN_RISE_M := 90.0
const MARGIN_KEEP_STEP_M := 32.0
## Mesas stand where their noise is above MESA_FROM (a lower tier) and MESA_TOP (the top).
const MESA_FROM := 0.34
const MESA_TOP := 0.50

var size_m := 2048.0
var seed_value := 0
## Hill height (m): the noise's amplitude.
var relief_m := 18.0
## Points per side (cells + 1) and the heights, row by row along x ([i + j * points]).
var points := 0
var heights := PackedFloat32Array()
var min_height := 0.0
var max_height := 0.0
## Flat pads: [Rect2 (x, z in metres), height].
var pads: Array = []

## The terrain preset (TerrainPresets) and what it gives: ground colours, the sea (side 0 north
## (-z), 1 south, 2 west, 3 east, -1 none; the water reaches sea_m in from that edge, its
## surface at sea_level, the seabed at the edge sea_depth below), riverbed depth.
var preset_id := "plain"
var preset := {}
var sea_side := -1
var sea_m := 0.0
var sea_level := 0.0
var sea_depth := 7.0
var w_depth := 8.0
var c_grass := GRASS
var c_dry := DRY
var c_earth := EARTH
var c_rock := ROCK
var c_sand := Color("c2b583")
var c_apron := GRASS
## Roads (ZoneRoads): packed earth, the palette's "road" or a darker earth.
var c_road := EARTH
var sand_below_m := -1000.0
var rock_above_m := 1.0e9
## The preset's ground (salt_flats): mud toward the edge over this band (m, 0 none), and the
## shader's damp patches, crust polygons and tyre tracks (0..1, 0 none).
var mud_margin_m := 0.0
var damp := 0.0
var crust := 0.0
var tracks := 0.0
## Where the land's "margin" stands (m in from the edge, 0 none): ZoneScatter's margins.
var margin_m := 0.0
var _bed := PackedByteArray()  # riverbed weight (0..255) per height
var _coast: FastNoiseLite
var _wobble_m := 0.0
## The def's "roads" as [a, b, bounds, core, verge, colour] (Vector2, Vector2, Rect2 grown by the
## verge, the half-width taking the full colour, where it has faded out, the road's far colour):
## the ground under and beside them takes the road colour, so they show past ZoneRoads.SEE_M.
## _road_grid: ROAD_GRID_M cell -> the indices of the roads crossing it (road_weight's lookups).
var _roads: Array = []
var _road_grid := {}
const ROAD_GRID_M := 64.0
## A generated town's streets (Rect2s, x/z in metres): its pad is road-coloured along them.
var _streets: Array[Rect2] = []

var _half := 0.0
var _visuals_built := false
var _material: ShaderMaterial
var _lod0 := {}  # Vector2i chunk -> its finest MeshInstance3D
var _lod1 := {}  # Vector2i chunk -> its middle MeshInstance3D
var _chunk_shapes := {}  # Vector2i chunk -> its HeightMapShape3D (GroundCuts blanks samples in it)
## An 8 km zone's ground collides only near players, vehicles and live soldiers (BigZoneStreaming,
## docs/combined_arms.md 6.2.2): build_collision builds no chunks, stream_collision does.
var on_demand := false
var _chunk_bodies := {}  # Vector2i chunk -> its StaticBody3D
var _blanks := {}  # Vector2i sample -> true: GroundCuts' holes, put back into a chunk built later
## The cuts in the ground (craters, dug holes: GroundCuts), or null while there are none.
var cuts: GroundCuts
## The rivers, streams, lakes and their bridges (ZoneWater: the preset's "water"), or null.
var water: ZoneWater
## Gullies, cliffs, marsh, snow and fields (ZoneFeatures: the preset's "features"), or null.
var features: ZoneFeatures


## Builds the heights from the zone definition (ZoneDef): seed, size, relief, terrain preset
## (TerrainPresets), sea, and a pad under each module footprint and landing zone (`flat`:
## Array of Rect2).
func generate(def: Dictionary, flat: Array) -> void:
	seed_value = int(def.get("seed", 0))
	size_m = float(def.get("size_m", 2048.0))
	on_demand = BigZoneStreaming.streams(size_m)
	preset_id = String(def.get("terrain", "plain"))
	preset = TerrainPresets.get_preset(preset_id)
	var land: Dictionary = preset.get("land", {})
	relief_m = float(def.get("relief_m", 18.0)) * float(land.get("relief_scale", 1.0))
	_half = size_m * 0.5
	points = int(round(size_m / CELL_M)) + 1
	_read_palette()
	set_roads(def.get("roads", []))
	_streets.clear()
	for m: Dictionary in def.get("modules", []):
		if String(m.type).begins_with(ZoneModules.TOWN) and ZoneModules.has_type(String(m.type)):  # (a city's block paints its own: ZoneModules.streets)
			var at := Vector2(float(m.pos[0]), float(m.pos[1]))
			var half: Vector2 = ZoneModules.HALF[String(m.type)]
			_streets.append(Rect2(at.x - BuildingGen.TOWN_HALF_X, at.y - BuildingGen.STREET_W * 0.5, BuildingGen.TOWN_HALF_X * 2.0, BuildingGen.STREET_W))
			_streets.append(Rect2(at.x - BuildingGen.CROSS_W * 0.5, at.y - half.y, BuildingGen.CROSS_W, half.y * 2.0))
		for r: Rect2 in ZoneModules.streets(String(m.type)):  # a landmark's hard standing: a runway, a forecourt, a quay
			_streets.append(Rect2(r.position + Vector2(float(m.pos[0]), float(m.pos[1])), r.size))
	var sea: Dictionary = preset.get("sea", {})
	sea_side = int(def.get("sea_side", -1)) if not sea.is_empty() else -1
	sea_m = float(def.get("sea_m", 0.0)) if sea_side >= 0 else 0.0
	sea_level = float(sea.get("level", 0.0))
	sea_depth = float(sea.get("depth_m", 7.0))
	var wavelength := float(land.get("wavelength_m", 650.0))
	var ridge := float(land.get("ridge", 0.0))
	var flatten := float(land.get("flatten", 1.0))
	var offset := float(land.get("offset_m", 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = int(land.get("octaves", 4))
	noise.fractal_gain = float(land.get("gain", 0.42))
	noise.frequency = 1.0 / wavelength
	var ridged := FastNoiseLite.new()
	ridged.seed = seed_value + 1
	ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridged.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridged.fractal_octaves = 3
	ridged.frequency = 1.3 / wavelength
	var wadis := _wadi_lines(preset.get("wadi", {}))
	# Gentle rises (land "detail_m" over "detail_wavelength_m"): small swells and dips on the
	# big shape, a few metres over a hundred or more, so the ground stops reading as a plain.
	var detail_m := float(land.get("detail_m", 0.0))
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 2
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 2
	detail.frequency = 1.0 / float(land.get("detail_wavelength_m", 160.0))
	# Folds (land "folds_m" over "folds_wavelength_m", FOLDS_M / FOLDS_WAVELENGTH_M without;
	# Captain, 2026-10-18: "we need to not have so many 300m sightlines"): low swells and hollows
	# a couple of metres high, too gentle to slow anyone, that make dead ground a man can drop
	# into. They break up the long flat lines the bigger shapes leave (tests/sightline_probe.gd).
	# A zone made nearly flat (its "relief_m" under FOLDS_FULL_RELIEF_M: test grounds) gets folds to
	# match; a definition's own "folds_m" wins.
	var folds_m := float(def.get("folds_m", float(land.get("folds_m", FOLDS_M)) * clampf(float(def.get("relief_m", 18.0)) / FOLDS_FULL_RELIEF_M, 0.0, 1.0)))
	var folds := FastNoiseLite.new()
	folds.seed = seed_value + 6
	folds.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	folds.fractal_type = FastNoiseLite.FRACTAL_NONE  # one smooth octave: gentle enough for landing zones (LandingZone.MAX_SLOPE_DEG)
	folds.frequency = 1.0 / float(land.get("folds_wavelength_m", FOLDS_WAVELENGTH_M))
	var berm_m := float((preset.get("wadi", {}) as Dictionary).get("berm_m", 0.0))
	# The margin (land "margin"; Captain, 2026-10-14: the salt flats were a flat white plate
	# meeting the sky): a low berm and flat-topped, two-tier mesas in a band inside the edge,
	# kept off the pads and roads, so the edge has landmarks and the horizon a silhouette.
	var margin: Dictionary = land.get("margin", {})
	margin_m = float(margin.get("width_m", 0.0))
	var margin_berm := float(margin.get("berm_m", 0.0))
	var mesa_m: Array = margin.get("mesa_m", [0.0, 0.0])
	var mesa := FastNoiseLite.new()
	mesa.seed = seed_value + 4
	mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mesa.fractal_type = FastNoiseLite.FRACTAL_FBM
	mesa.fractal_octaves = 2
	mesa.frequency = 1.0 / float(margin.get("mesa_wavelength_m", 150.0))
	var lift := FastNoiseLite.new()
	lift.seed = seed_value + 5
	lift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lift.frequency = 1.0 / 400.0
	var keep := _margin_keep(flat, float(margin.get("keep_m", 110.0))) if margin_m > 0.0 else PackedFloat32Array()
	# The coast (sea "coast_wobble_m"): the shoreline pushed in and out along its length, so
	# it isn't a ruled line. Inland at most COAST_IN_M (pads keep ZoneDef.SEA_PAD_KEEP_M clear).
	_wobble_m = minf(float(sea.get("coast_wobble_m", 0.0)), sea_m * 0.45)
	_coast = FastNoiseLite.new()
	_coast.seed = seed_value + 3
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coast.fractal_octaves = 3
	_coast.frequency = 1.0 / 260.0
	heights.resize(points * points)
	_bed.resize(points * points)
	for j in points:
		var z := j * CELL_M - _half
		for i in points:
			var x := i * CELL_M - _half
			var edge := minf(minf(x + _half, _half - x), minf(z + _half, _half - z))
			var n := noise.get_noise_2d(x, z)
			if ridge > 0.0:
				n = lerpf(n, 1.4 * (1.0 - 2.0 * absf(ridged.get_noise_2d(x, z))) - 0.7, ridge)
			if flatten != 1.0:
				n = signf(n) * pow(absf(n), flatten)
			var h := n * relief_m + offset
			if detail_m > 0.0:
				h += detail.get_noise_2d(x, z) * detail_m
			if folds_m > 0.0:
				h += folds.get_noise_2d(x, z) * folds_m
			var carve := 0.0
			var berm := 0.0
			for w: Dictionary in wadis:
				carve = maxf(carve, _wadi_weight(w, x, z))
				if berm_m > 0.0:
					berm = maxf(berm, _wadi_berm(w, x, z))
			if carve > 0.0:
				h -= carve * float(w_depth)
			h += berm * berm_m * (1.0 - carve)
			var fade := smoothstep(0.0, EDGE_FADE_M, edge)
			h *= fade
			if margin_m > 0.0 and edge < margin_m:
				var band := smoothstep(MARGIN_FROM_M, MARGIN_RISE_M, edge) * (1.0 - smoothstep(margin_m * 0.55, margin_m, edge))
				if band > 0.0:
					var l := lift.get_noise_2d(x, z) * 0.5 + 0.5
					h += band * margin_berm * (0.55 + 0.45 * l)
					var mv := mesa.get_noise_2d(x, z)
					if mv > MESA_FROM:
						var tier := smoothstep(MESA_FROM, MESA_FROM + 0.06, mv) * 0.55 + smoothstep(MESA_TOP, MESA_TOP + 0.05, mv) * 0.45
						h += tier * lerpf(float(mesa_m[0]), float(mesa_m[1]), l) * band * _keep_weight(keep, x, z)
			if sea_side >= 0:
				var d: float = [z + _half, _half - z, x + _half, _half - x][sea_side]
				d -= coast_shift(x, z)
				h = lerpf(h, sea_level - sea_depth, 1.0 - smoothstep(0.0, sea_m, d))
				if _wobble_m > 0.0:
					# Low land by the sea rises out of it along the (wobbly) coast profile, so the
					# shoreline is the coast's, not the straight inner edge of the water plane.
					var floor_h := lerpf(sea_level - sea_depth, sea_level + 0.5, smoothstep(0.0, sea_m, d))
					if h < floor_h:
						h = lerpf(h, floor_h, 1.0 - smoothstep(sea_m + SEA_MARGIN_M, sea_m + SEA_MARGIN_M + 80.0, d))
			heights[i + j * points] = h
			_bed[i + j * points] = int(carve * 255.0)
	pads.clear()
	var at_sea := {}  # pads made at a height over the sea (a harbour's quay: ZoneModules.pad_sea)
	for m: Dictionary in def.get("modules", []):
		if not is_nan(ZoneModules.pad_sea(String(m.type))):
			at_sea[ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1])))] = ZoneModules.pad_sea(String(m.type))
	for rect: Rect2 in flat:
		_flatten(rect, float(at_sea.get(rect, NAN)))
	if features:
		features.free()
	features = ZoneFeatures.carve(self, def)  # gullies, cliffs, the marsh, snow and farmland planned (queue item 1.3)
	if features:
		add_child(features)
	if water:
		water.free()
	# Rivers cut their valleys (queue item 1.1), bridged where the roads will run (RoadNet.water_links).
	water = ZoneWater.carve(self, def.merged({"roads": RoadNet.water_links(def)}, true))
	if water:
		add_child(water)
	if features:
		features.finish()  # the gullies and cliffs carved, off the water
	min_height = INF
	max_height = -INF
	for h in heights:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)
	_measure_shore()  # wave 5b (V4): the coast the LHD and AAVs use, from the sea above


## The roads the ground is tinted along (a def's "roads": [[x, z], [x, z]] pieces, a third entry
## naming the kind, data/roads.json; none: ROAD_CORE_M wide, c_road). RoadNet sets them again once
## it has laid the curved roads.
func set_roads(pieces: Array) -> void:
	_roads.clear()
	_road_grid.clear()
	for road: Array in pieces:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		var core := ROAD_CORE_M
		var colour := c_road
		if road.size() > 2:
			var k: Dictionary = RoadNet.kind(String(road[2]))
			core = float(k.get("width_m", ROAD_CORE_M * 2.0)) * 0.5
			if String(k.get("far_colour", "")) != "":
				colour = Color(String(k.far_colour))
		var verge := core + ROAD_VERGE_M - ROAD_CORE_M
		var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(verge)
		var i := _roads.size()
		_roads.append([a, b, bounds, core, verge, colour, String(road[2]) if road.size() > 2 else "dirt"])  # (A6: the kind is ground_at's)
		for cy in range(floori(bounds.position.y / ROAD_GRID_M), floori(bounds.end.y / ROAD_GRID_M) + 1):
			for cx in range(floori(bounds.position.x / ROAD_GRID_M), floori(bounds.end.x / ROAD_GRID_M) + 1):
				var key := Vector2i(cx, cy)
				if not _road_grid.has(key):
					_road_grid[key] = []
				_road_grid[key].append(i)


## After something changed `heights` in place (RoadNet's cut and fill): the height range and the
## shoreline again.
func heights_changed() -> void:
	min_height = INF
	max_height = -INF
	for h in heights:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)
	_measure_shore()


## The margin's clearance round the pads (`flat`) and roads: per MARGIN_KEEP_STEP_M grid node in
## the margin band, 0 within `keep_m` of one, rising to 1 by 60 m further (1 elsewhere).
func _margin_keep(flat: Array, keep_m: float) -> PackedFloat32Array:
	var n := ceili(size_m / MARGIN_KEEP_STEP_M) + 1
	var out := PackedFloat32Array()
	out.resize(n * n)
	out.fill(1.0)
	for j in n:
		var z := j * MARGIN_KEEP_STEP_M - _half
		for i in n:
			var x := i * MARGIN_KEEP_STEP_M - _half
			var edge := minf(minf(x + _half, _half - x), minf(z + _half, _half - z))
			if edge > margin_m + MARGIN_KEEP_STEP_M:
				continue
			var p := Vector2(x, z)
			var d := INF
			for rect: Rect2 in flat:
				d = minf(d, _distance_to_rect(p, rect))
			for r: Array in _roads:
				d = minf(d, Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p))
			out[i + j * n] = smoothstep(keep_m, keep_m + 60.0, d)
	return out


## The margin's clearance at (x, z) (_margin_keep), between its grid nodes.
func _keep_weight(keep: PackedFloat32Array, x: float, z: float) -> float:
	var n := ceili(size_m / MARGIN_KEEP_STEP_M) + 1
	var gx := clampf((x + _half) / MARGIN_KEEP_STEP_M, 0.0, n - 1.001)
	var gz := clampf((z + _half) / MARGIN_KEEP_STEP_M, 0.0, n - 1.001)
	var i := floori(gx)
	var j := floori(gz)
	var fx := gx - i
	var fz := gz - j
	var top := lerpf(keep[i + j * n], keep[i + 1 + j * n], fx)
	var bottom := lerpf(keep[i + (j + 1) * n], keep[i + 1 + (j + 1) * n], fx)
	return lerpf(top, bottom, fz)


## The dry riverbeds of a preset's "wadi": `count` lines across the zone (seeded), each a
## direction, a sideways offset and a meander noise.
func _wadi_lines(spec: Dictionary) -> Array:
	var out: Array = []
	if spec.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x3AD1
	w_depth = float(spec.get("depth_m", 8.0))
	for k in int(spec.get("count", 1)):
		var angle := rng.randf() * PI
		var meander := FastNoiseLite.new()
		meander.seed = seed_value + 10 + k
		meander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		meander.frequency = 1.0 / 520.0
		out.append({"dir": Vector2.from_angle(angle), "offset": rng.randf_range(-0.3, 0.3) * size_m,
			"width": float(spec.get("width_m", 50.0)), "meander": float(spec.get("meander_m", 120.0)), "noise": meander})
	return out


## 0 to 1: how deep in the riverbed `w` the point (x, z) is.
func _wadi_weight(w: Dictionary, x: float, z: float) -> float:
	var dir: Vector2 = w.dir
	var along := x * dir.x + z * dir.y
	var side := -x * dir.y + z * dir.x - float(w.offset) - (w.noise as FastNoiseLite).get_noise_1d(along) * float(w.meander)
	var width := float(w.width)
	var d := absf(side)
	if d >= width * 1.6:
		return 0.0
	# A flat-ish floor, banks easing up to the land.
	return 1.0 - smoothstep(width * 0.3, width * 1.6, d)


## 0 to 1: how deep in a wadi's riverbed (x, z) is, at the nearest height point (0 off the
## beds or with no wadis). ZoneScatter grows its wadi groves on the banks (Captain, 2026-10-14:
## groves near the watercourses).
func bed_at(x: float, z: float) -> float:
	if _bed.size() != heights.size() or points == 0:
		return 0.0
	var i := clampi(roundi((x + _half) / CELL_M), 0, points - 1)
	var j := clampi(roundi((z + _half) / CELL_M), 0, points - 1)
	return float(_bed[i + j * points]) / 255.0


## How far the coast at (x, z) is pushed inland (+) or out to sea (-) by the wobble: smooth,
## out to sea up to _wobble_m, inland only up to COAST_IN_M.
func coast_shift(x: float, z: float) -> float:
	if sea_side < 0 or _wobble_m <= 0.0:
		return 0.0
	var along: float = [x, x, z, z][sea_side]
	var n := tanh(_coast.get_noise_1d(along) * 1.8)  # smooth: no clipped, ruled stretches
	return n * (minf(_wobble_m, COAST_IN_M) if n > 0.0 else _wobble_m)


## 0 to 1: a low bank-top ridge just outside riverbed `w` (the wadi's "berm_m" high).
func _wadi_berm(w: Dictionary, x: float, z: float) -> float:
	var dir: Vector2 = w.dir
	var along := x * dir.x + z * dir.y
	var side := -x * dir.y + z * dir.x - float(w.offset) - (w.noise as FastNoiseLite).get_noise_1d(along) * float(w.meander)
	var width := float(w.width)
	var u := (absf(side) - width * 1.75) / (width * 0.45)
	if absf(u) > 3.0:
		return 0.0
	return exp(-u * u)


func _read_palette() -> void:
	var p: Dictionary = preset.get("palette", {})
	c_grass = Color(String(p.get("grass", "5f6a3c")))
	c_dry = Color(String(p.get("dry", "7d7748")))
	c_earth = Color(String(p.get("earth", "7f6d4f")))
	c_rock = Color(String(p.get("rock", "6f6a60")))
	c_sand = Color(String(p.get("sand", "c2b583")))
	c_apron = Color(String(p.get("apron", String(p.get("grass", "5f6a3c")))))
	c_road = Color(String(p["road"])) if p.has("road") else c_earth.darkened(0.15)
	var g: Dictionary = preset.get("ground", {})
	sand_below_m = float(g.get("sand_below_m", -1000.0))
	rock_above_m = float(g.get("rock_above_m", 1.0e9))
	mud_margin_m = float(g.get("mud_margin_m", 0.0))
	damp = float(g.get("damp", 0.0))
	crust = float(g.get("crust", 0.0))
	tracks = float(g.get("tracks", 0.0))


## The height of the noise ground (before pads) is what a pad takes: the grid's height at
## its centre. Inside the rect grown by PAD_MARGIN_M it's flat; it blends back over
## PAD_BLEND_M beyond that. `over_sea`: the pad is made that high over the sea instead (a
## harbour's quay, ZoneModules.pad_sea).
func _flatten(rect: Rect2, over_sea := NAN) -> void:
	var flat := rect.grow(PAD_MARGIN_M)
	var centre := flat.get_center()
	var h := snappedf(height_at(centre.x, centre.y), 0.05) if is_nan(over_sea) else sea_level + over_sea
	pads.append([flat, h])
	var reach := flat.grow(PAD_BLEND_M)
	var lo := _grid_index(reach.position)
	var hi := _grid_index(reach.end) + Vector2i.ONE
	for j in range(maxi(lo.y, 0), mini(hi.y + 1, points)):
		for i in range(maxi(lo.x, 0), mini(hi.x + 1, points)):
			var p := Vector2(i * CELL_M - _half, j * CELL_M - _half)
			var d := _distance_to_rect(p, flat)
			var w := smoothstep(0.0, 1.0, clampf(1.0 - d / PAD_BLEND_M, 0.0, 1.0))
			heights[i + j * points] = lerpf(heights[i + j * points], h, w)


static func _distance_to_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()


func _grid_index(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x + _half) / CELL_M), floori((p.y + _half) / CELL_M))


func _h(i: int, j: int) -> float:
	return heights[clampi(i, 0, points - 1) + clampi(j, 0, points - 1) * points]


## The ground's height at (x, z), exactly on the mesh and the collision (each cell is two
## triangles split along the diagonal from its (1, 0) corner to its (0, 1) corner, as Jolt's
## height fields are; measured: within 0.1 mm of a raycast). Outside the zone: the apron's,
## 0, or beyond the sea's edge its seabed (sea_level - sea_depth, as _apron() lowers it).
## Captain, 2026-10-14: the LHD now anchors out there on a narrow sea, so the water's depth
## past the edge has to be the seabed's, not a dry 0.
func height_at(x: float, z: float) -> float:
	if cuts and cuts.cut.has(cuts.cell_of(x, z)):
		return cuts.cut_height(x, z)
	return plane_height(x, z)


## The ground's height at (x, z) as generated, before any cuts (GroundCuts builds on it).
func plane_height(x: float, z: float) -> float:
	var gx := (x + _half) / CELL_M
	var gz := (z + _half) / CELL_M
	if gx < 0.0 or gz < 0.0 or gx > points - 1 or gz > points - 1:
		return _apron_height(x, z)
	var i := mini(floori(gx), points - 2)
	var j := mini(floori(gz), points - 2)
	var fx := gx - i
	var fz := gz - j
	var h10 := _h(i + 1, j)
	var h01 := _h(i, j + 1)
	if fx + fz <= 1.0:
		var h00 := _h(i, j)
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	var h11 := _h(i + 1, j + 1)
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


## The apron's height at (x, z) outside the zone: the seabed on the sea side's quad (the full
## width for a north or south sea, between the corners for a west or east one, as _apron()
## lays them), else 0.
func _apron_height(x: float, z: float) -> float:
	if sea_side < 0 or sea_edge_distance(x, z) >= 0.0:
		return 0.0
	if sea_side >= 2 and absf(z) > _half:
		return 0.0
	return sea_level - sea_depth


## The ground's surface normal at (x, z) (from the grid around it).
func normal_at(x: float, z: float) -> Vector3:
	var e := CELL_M
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## normal_at on the ground as generated, before any cuts (plane_height): reads only the heights,
## so a worker thread may ask (ZoneScatter's ground cover).
func plane_normal(x: float, z: float) -> Vector3:
	var e := CELL_M
	var dx := plane_height(x + e, z) - plane_height(x - e, z)
	var dz := plane_height(x, z + e) - plane_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## The steepest slope in the grid (degrees), for checks.
func max_slope_deg() -> float:
	var worst := 0.0
	for j in points - 1:
		for i in points - 1:
			var h := _h(i, j)
			worst = maxf(worst, maxf(absf(_h(i + 1, j) - h), absf(_h(i, j + 1) - h)))
	return rad_to_deg(atan(worst / CELL_M))


## A hash of the heights (and the water: ZoneScatter's cache keys on it): two peers that
## generated the same zone have the same.
func checksum() -> int:
	var sum := hash(heights) if water == null else hash([hash(heights), water.checksum()])
	return sum if features == null else hash([sum, features.checksum()])  # (its fields and crops too)


## The ground's triangles inside `area` (x, z in metres), world space, for navigation.
func triangles_in(area: Rect2) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var lo := _grid_index(area.position)
	var hi := _grid_index(area.end) + Vector2i.ONE
	for j in range(maxi(lo.y, 0), mini(hi.y, points - 1)):
		for i in range(maxi(lo.x, 0), mini(hi.x, points - 1)):
			var a := _vertex(i, j)
			var b := _vertex(i + 1, j)
			var c := _vertex(i + 1, j + 1)
			var d := _vertex(i, j + 1)
			if sea_side >= 0 and maxf(maxf(a.y, b.y), maxf(c.y, d.y)) < sea_level - NAV_WATER_M:
				continue  # too deep to walk: not part of the navigation mesh
			if water:
				# A river or lake too deep to wade, triangle by triangle: the bridges carry the way (ZoneWater).
				if not water.too_deep(a, b, d):
					faces.append_array([a, b, d])
				if not water.too_deep(b, c, d):
					faces.append_array([b, c, d])
				continue
			faces.append_array([a, b, d, b, c, d])  # clockwise seen from above: facing up
	return faces


func _vertex(i: int, j: int) -> Vector3:
	return Vector3(i * CELL_M - _half, _h(i, j), j * CELL_M - _half)


## The lowest and highest ground in `area` (x, z in metres).
func height_range(area: Rect2) -> Vector2:
	var lo := _grid_index(area.position)
	var hi := _grid_index(area.end) + Vector2i.ONE
	var r := Vector2(INF, -INF)
	for j in range(maxi(lo.y, 0), mini(hi.y + 1, points)):
		for i in range(maxi(lo.x, 0), mini(hi.x + 1, points)):
			var h := _h(i, j)
			r = Vector2(minf(r.x, h), maxf(r.y, h))
	return r if r.x <= r.y else Vector2.ZERO


func chunk_count() -> int:
	return (points - 1) / CHUNK_CELLS


# --- Collision -------------------------------------------------------------------------------

## One static body per chunk with a height field (none yet in an on_demand zone: stream_collision
## builds them), plus the walls at the zone's edge.
func build_collision() -> void:
	var count := chunk_count()
	for cz in count:
		for cx in count:
			if not on_demand:
				_build_chunk(Vector2i(cx, cz))
	var walls := StaticBody3D.new()
	walls.name = "EdgeWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	for side in 4:
		var box := BoxShape3D.new()
		box.size = Vector3(size_m + 40.0, WALL_HEIGHT_M, 10.0) if side < 2 else Vector3(10.0, WALL_HEIGHT_M, size_m + 40.0)
		var node := CollisionShape3D.new()
		node.shape = box
		var out := _half + 5.0
		node.position = [Vector3(0, 0, -out), Vector3(0, 0, out), Vector3(-out, 0, 0), Vector3(out, 0, 0)][side]
		walls.add_child(node)
	add_child(walls)
	if water:
		water.build_collision()  # the bridges and culverts


func _build_chunk(c: Vector2i) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [c.x, c.y]
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = CHUNK_CELLS + 1
	shape.map_depth = CHUNK_CELLS + 1
	# The chunk's rows of the height grid, a slice each (D2: 33 slices, not 1,089 _h calls: a chunk
	# streamed in an 8 km zone is ~0.05 ms of GDScript, not ~0.6); then GroundCuts' holes put back.
	var data := PackedFloat32Array()
	var i0 := c.x * CHUNK_CELLS
	for j in CHUNK_CELLS + 1:
		var row := (c.y * CHUNK_CELLS + j) * points + i0
		data.append_array(heights.slice(row, row + CHUNK_CELLS + 1))
	if not _blanks.is_empty():
		for j in CHUNK_CELLS + 1:
			for i in CHUNK_CELLS + 1:
				if _blanks.has(Vector2i(i0 + i, c.y * CHUNK_CELLS + j)):
					data[i + j * (CHUNK_CELLS + 1)] = NAN
	shape.map_data = data
	_chunk_shapes[c] = shape
	var node := CollisionShape3D.new()
	node.shape = shape
	node.scale = Vector3(CELL_M, 1.0, CELL_M)
	body.add_child(node)
	var chunk_m := CHUNK_CELLS * CELL_M
	body.position = Vector3(-_half + (c.x + 0.5) * chunk_m, 0.0, -_half + (c.y + 0.5) * chunk_m)
	add_child(body)
	_chunk_bodies[c] = body


## An on_demand zone (BigZoneStreaming): builds the chunks within `in_m` of any of `focus` (or
## `reach[k]` of focus k, where given), nearest first, at most `budget` of them (-1: all), and frees
## those further than `out_m` (scaled the same) from all of them. Returns how many it built.
## `until_usec` (Time.get_ticks_usec): stops building past it, after the first.
func stream_collision(focus: Array[Vector3], in_m: float, out_m: float, budget := -1, reach := PackedFloat32Array(), until_usec := 0) -> int:
	var todo := stream_plan(focus, in_m, out_m, reach)
	if budget >= 0:
		todo = todo.slice(0, budget)
	return build_chunks(todo, until_usec)


## stream_collision's first half: frees the chunks past reach (but those something lies on: held)
## and returns the wanted ones not built yet, nearest first, for build_chunks.
func stream_plan(focus: Array[Vector3], in_m: float, out_m: float, reach := PackedFloat32Array()) -> Array:
	if not on_demand:
		return []
	var chunk_m := CHUNK_CELLS * CELL_M
	var plan := BigZoneStreaming.plan(focus, reach, in_m, out_m, chunk_m, chunk_count(), _half)
	var wanted: Dictionary = plan[0]
	var keep: Dictionary = plan[1]
	for c: Vector2i in _chunk_bodies.keys():
		if not keep.has(c):
			var r := Rect2(-_half + c.x * chunk_m, -_half + c.y * chunk_m, chunk_m, chunk_m)
			if BigZoneStreaming.held(self, c, r, self):
				continue  # something lies on it (a body, a dropped item, a wreck): its ground stays
			(_chunk_bodies[c] as Node).queue_free()
			_chunk_bodies.erase(c)
			_chunk_shapes.erase(c)
	var todo: Array = []
	for c: Vector2i in wanted:
		if not _chunk_bodies.has(c):
			todo.append(c)
	todo.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return float(wanted[x]) < float(wanted[y]))
	return todo


## Builds the chunks of `todo` (stream_plan's) from its front, taking each out as it's built,
## until `until_usec` passes (after the first; 0: all). Returns how many it built.
func build_chunks(todo: Array, until_usec := 0) -> int:
	var built := 0
	while not todo.is_empty():
		if until_usec > 0 and built > 0 and Time.get_ticks_usec() > until_usec:
			break  # (the time is spent: the rest next time, nearest first)
		var c: Vector2i = todo.pop_front()
		if _chunk_bodies.has(c):
			continue
		_build_chunk(c)
		built += 1
	return built


## How many chunks have collision now.
func collision_chunks() -> int:
	return _chunk_bodies.size() if on_demand else _chunk_shapes.size()


## Whether chunk `c` has its collision now (always, in a zone that doesn't stream).
func has_collision(c: Vector2i) -> bool:
	return _chunk_shapes.has(c)


# --- Visuals ---------------------------------------------------------------------------------

## GroundCuts: blanks grid samples `samples` (Vector2i) in the coarse collision (a NaN sample
## is a hole: the triangles touching it go), in every chunk that has them.
func blank_samples(samples: Array[Vector2i]) -> void:
	var edits := {}  # chunk -> PackedFloat32Array
	for s in samples:
		if on_demand:
			_blanks[s] = true  # a chunk freed and built again keeps its holes
		for dz in [0, -1]:
			for dx in [0, -1]:
				var c := Vector2i(s.x / CHUNK_CELLS + dx, s.y / CHUNK_CELLS + dz)
				var li := s.x - c.x * CHUNK_CELLS
				var lj := s.y - c.y * CHUNK_CELLS
				if li < 0 or lj < 0 or li > CHUNK_CELLS or lj > CHUNK_CELLS or not _chunk_shapes.has(c):
					continue
				var data: PackedFloat32Array = edits[c] if edits.has(c) else (_chunk_shapes[c] as HeightMapShape3D).map_data
				data[li + lj * (CHUNK_CELLS + 1)] = NAN
				edits[c] = data  # a packed array is a value: put the changed one back
	for c: Vector2i in edits:
		(_chunk_shapes[c] as HeightMapShape3D).map_data = edits[c]


## GroundCuts: rebuilds chunk `c`'s finest mesh (if built) without the cells drawn fine.
func rebuild_fine_chunk(c: Vector2i) -> void:
	if _lod0.has(c):
		(_lod0[c] as MeshInstance3D).mesh = _chunk_mesh(c.x, c.y, LOD_STEPS[0], SKIRT_M[0])


## A grid vertex's colour and normal, as the coarse mesh has them (GroundCuts matches them).
func vertex_colour(i: int, j: int) -> Color:
	return _ground_colour(i, j, vertex_normal(i, j))


func vertex_normal(i: int, j: int) -> Vector3:
	return Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * CELL_M, _h(i, j - 1) - _h(i, j + 1)).normalized()


## The ground's mesh: every chunk at the two coarse levels of detail, and the apron. The
## finest level is built as the camera comes near (LOD0_BUILD_M, LOD0_PER_FRAME a frame):
## building all of it up front took 1.4 s for a 2 km zone. Not needed (and skipped) on a
## headless server.
func build_visuals() -> void:
	if _visuals_built:
		return
	_visuals_built = true
	_shrink_pads()
	_material = ground_material()
	var count := chunk_count()
	if on_demand:
		_build_far_tiles()  # an 8 km zone: far tiles, and every chunk's levels in rings round the camera (_ring_process)
	else:
		for cz in count:
			for cx in count:
				for lod in range(1, LOD_STEPS.size()):
					var node := _lod_instance(cx, cz, lod)
					if lod == 1:
						node.visibility_range_begin = 0.0  # until the finest level is built
						_lod1[Vector2i(cx, cz)] = node
	add_child(_apron(_material))
	if sea_side >= 0:
		add_child(_water())
	if water:
		water.build_visuals()
	if features:
		features.build_visuals()
	set_process(true)


## The ground's material (zone_ground.gdshader): the vertex palette broken up in world space,
## per-pixel rock on steep faces, fine normal detail near the camera; tinted from the preset.
func ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter(&"dry_colour", c_dry)
	m.set_shader_parameter(&"rock_colour", c_rock)
	m.set_shader_parameter(&"earth_colour", c_earth)
	m.set_shader_parameter(&"seed_offset", float(seed_value % 97) * 3.1)  # small: the noise keeps its float precision
	m.set_shader_parameter(&"snow_strength", features.snow_strength() if features else 0.0)  # (ZoneFeatures' snow)
	m.set_shader_parameter(&"damp_strength", damp)
	m.set_shader_parameter(&"crust_strength", crust)
	m.set_shader_parameter(&"track_strength", tracks)
	var asphalt := String(RoadNet.kind("asphalt").get("far_colour", ""))
	m.set_shader_parameter(&"road_colour", Color(asphalt) if asphalt != "" else c_road)  # (roads, cg_brief 1.2: kept off the patches)
	m.set_shader_parameter(&"track_colour", c_road)
	return m


## The finest level for the chunks nearest `pos`, at most `budget` of them; returns how
## many it built.
func build_near(pos: Vector3, budget: int) -> int:
	var built := 0
	for c: Vector2i in _wanted_near(pos, budget):
		_refine(c)
		built += 1
	return built


## The finest mesh for chunk `c`.
func _refine(c: Vector2i) -> void:
	_lod0[c] = _lod_instance(c.x, c.y, 0)
	if on_demand:
		_ring_ranges(c)
	else:
		_lod1[c].visibility_range_begin = LOD_END_M[0]


## The nearest `budget` chunks within LOD0_BUILD_M of `pos` without their finest mesh, nearest first.
func _wanted_near(pos: Vector3, budget: int) -> Array:
	if not _visuals_built:
		return []
	var chunk_m := CHUNK_CELLS * CELL_M
	var wanted: Array = []
	var count := chunk_count()
	# (D2: the chunks within LOD0_BUILD_M's square, not all 4,096 of an 8 km zone; the same ones.)
	var lo := Vector2i(clampi(floori((pos.x - LOD0_BUILD_M + _half) / chunk_m), 0, count - 1), clampi(floori((pos.z - LOD0_BUILD_M + _half) / chunk_m), 0, count - 1))
	var hi := Vector2i(clampi(floori((pos.x + LOD0_BUILD_M + _half) / chunk_m), 0, count - 1), clampi(floori((pos.z + LOD0_BUILD_M + _half) / chunk_m), 0, count - 1))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cz)
			if _lod0.has(c):
				continue
			var centre := Vector2(-_half + (cx + 0.5) * chunk_m, -_half + (cz + 0.5) * chunk_m)
			var d := centre.distance_to(Vector2(pos.x, pos.z))
			if d < LOD0_BUILD_M:
				wanted.append([d, c])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return wanted.slice(0, budget).map(func(w: Array) -> Vector2i: return w[1])


## How many chunks have their finest mesh built.
func fine_chunks() -> int:
	return _lod0.size()


## Perf pass (2026-10-22): the chunks to refine are worked out again only once the camera has
## moved REPLAN_M (every chunk of the zone was measured and sorted every frame), and built one a
## frame from that list (two in one frame before: a fine chunk is a few ms of GDScript meshing).
const REPLAN_M := 16.0
var _planned_at := Vector3.INF
var _queue: Array = []  # chunks to refine, nearest first
var _plan_full := false


func _process(_delta: float) -> void:
	if on_demand and _visuals_built:
		_ring_process()
	if _task >= 0:
		_take_refined()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not _visuals_built:
		return
	var at := camera.global_position
	if _queue.is_empty() and (_plan_full or at.distance_to(_planned_at) > REPLAN_M):
		_planned_at = at
		_queue = _wanted_near(at, LOD0_PER_FRAME * 8)
		_plan_full = _queue.size() == LOD0_PER_FRAME * 8  # (more may be waiting: plan again when these are done)
	if not _queue.is_empty():
		var c: Vector2i = _queue.pop_front()
		if not _lod0.has(c):
			# Perf (world content pass, 2026-10-23): a fine chunk's vertices, normals and colours are
			# worked out on a worker thread (15-30 ms of GDScript a chunk with the world expansion's
			# ground tints: fields, banks, roads, pads), its mesh made here when they're done.
			var t := Time.get_ticks_usec()
			_task_chunk = c
			_task_cuts = cuts.version if cuts else 0
			_task_out = []
			_task = WorkerThreadPool.add_task(_refine_arrays.bind(c, _covered_mask(c.x, c.y, LOD_STEPS[0])), false, "terrain fine chunk")
			FrameCost.spent(&"terrain_fine", t)


## The worker's fine chunk (_process): one at a time.
var _task := -1
var _task_chunk := Vector2i.ZERO
var _task_out: Array = []
var _task_cuts := 0  # GroundCuts.version when it started (a cut since: worked out again)


func _refine_arrays(c: Vector2i, covered: PackedByteArray) -> void:
	_task_out = _chunk_arrays(c.x, c.y, LOD_STEPS[0], SKIRT_M[0], covered)


## The worker's chunk is done: its finest mesh goes in (unless it was built meanwhile).
func _take_refined() -> void:
	if not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var c := _task_chunk
	if _lod0.has(c) or _task_out.is_empty() or not (_lod1.has(c) or on_demand):
		return
	if (cuts.version if cuts else 0) != _task_cuts:
		_queue.push_front(c)  # the ground was cut meanwhile: its cells drawn finely may have changed
		_task_out = []
		return
	var t := Time.get_ticks_usec()
	_lod0[c] = _lod_instance(c.x, c.y, 0, _mesh_of(_task_out))
	if on_demand:
		_ring_ranges(c)
	else:
		_lod1[c].visibility_range_begin = LOD_END_M[0]
	_task_out = []
	FrameCost.spent(&"terrain_fine", t)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _ring_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ring_task)
		_ring_task = -1


# --- An 8 km zone's ground in rings (D2, cg_brief queue item 3.1) ------------------------------

## An on_demand zone (BigZoneStreaming.streams) draws its ground in tiers, none of them built for
## the whole zone up front (4,096 chunks at three levels were 12,288 meshes and as many draws):
## - far tiles: FAR_TILE_CHUNKS x FAR_TILE_CHUNKS chunks (512 m) at the coarsest step, all built at
##   load (256 of them), drawn once the camera is FAR_TILE_BEGIN_M from a tile's middle;
## - nearer than that, each chunk's own levels (the coarsest with its tile as visibility_parent),
##   built on a worker in rings round the camera (RING_BUILD_M per level, RING_BATCH chunks a task,
##   nearest first) and freed past RING_FREE_M, so the memory held follows the camera, not the
##   ground it has seen;
## - each level's nearer edge waits for the level inside it (_ring_ranges), so a chunk is never a
##   hole while the finer level is still coming.
## Proposed.
const FAR_TILE_CHUNKS := 4
const FAR_TILE_BEGIN_M := 2000.0
const RING_BUILD_M: Array[float] = [LOD0_BUILD_M, 1500.0, 2600.0]
const RING_FREE_M: Array[float] = [900.0, 1800.0, 3000.0]
const RING_BATCH := 8
const RING_REPLAN_M := 32.0
var _lod2 := {}  # Vector2i chunk -> its coarsest MeshInstance3D (on_demand)
var _far_tiles := {}  # Vector2i tile -> MeshInstance3D
var _ring_task := -1
var _ring_jobs: Array = []  # [[chunk, lod], ...] on the worker
var _ring_out: Array = []  # their arrays, in order
var _ring_queue: Array = []  # [[chunk, lod], ...] to build, nearest first
var _ring_planned_at := Vector3.INF
## Tests and the invasion suite: ring meshes built and freed so far.
var ring_built := 0
var ring_freed := 0


func _build_far_tiles() -> void:
	var tiles := ceili(chunk_count() / float(FAR_TILE_CHUNKS))
	var cells := CHUNK_CELLS * FAR_TILE_CHUNKS
	for tz in tiles:
		for tx in tiles:
			var node := MeshInstance3D.new()
			node.name = "Far_%d_%d" % [tx, tz]
			node.mesh = _mesh_of(_chunk_arrays(tx, tz, LOD_STEPS[2], SKIRT_M[2], PackedByteArray(), cells))
			node.material_override = _material
			node.visibility_range_begin = FAR_TILE_BEGIN_M
			node.visibility_range_begin_margin = 40.0
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_far_tiles[Vector2i(tx, tz)] = node


## How many far tiles and chunk meshes (by level) are built now.
func ring_counts() -> Dictionary:
	return {"tiles": _far_tiles.size(), "lod0": _lod0.size(), "lod1": _lod1.size(), "lod2": _lod2.size()}


## Each level of chunk `c` drawn from where the level inside it ends, or nearer while that one
## isn't built (a coarser level stands in under the camera until the finer comes).
func _ring_ranges(c: Vector2i) -> void:
	if _lod1.has(c):
		(_lod1[c] as MeshInstance3D).visibility_range_begin = LOD_END_M[0] if _lod0.has(c) else 0.0
	if _lod2.has(c):
		var begin := LOD_END_M[1] if _lod1.has(c) else (LOD_END_M[0] if _lod0.has(c) else 0.0)
		(_lod2[c] as MeshInstance3D).visibility_range_begin = begin


func _ring_process() -> void:
	if _ring_task >= 0:
		if not WorkerThreadPool.is_task_completed(_ring_task):
			return
		WorkerThreadPool.wait_for_task_completion(_ring_task)
		_ring_task = -1
		var t := Time.get_ticks_usec()
		for k in _ring_jobs.size():
			var c: Vector2i = _ring_jobs[k][0]
			var lod: int = _ring_jobs[k][1]
			var into: Dictionary = _lod1 if lod == 1 else _lod2
			if into.has(c) or k >= _ring_out.size():
				continue
			var node := _lod_instance(c.x, c.y, lod, _mesh_of(_ring_out[k]))
			if lod == 2:
				var tile: MeshInstance3D = _far_tiles.get(Vector2i(c.x / FAR_TILE_CHUNKS, c.y / FAR_TILE_CHUNKS))
				if tile:
					node.visibility_parent = node.get_path_to(tile)
			into[c] = node
			ring_built += 1
			_ring_ranges(c)
		_ring_jobs = []
		_ring_out = []
		FrameCost.spent(&"terrain_rings", t)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	if _ring_queue.is_empty() and at.distance_to(_ring_planned_at) > RING_REPLAN_M:
		var t := Time.get_ticks_usec()
		_ring_planned_at = at
		_ring_queue = _ring_plan(at)
		FrameCost.spent(&"terrain_rings", t)
	if not _ring_queue.is_empty():
		_ring_jobs = _ring_queue.slice(0, RING_BATCH)
		_ring_queue = _ring_queue.slice(RING_BATCH)
		_ring_out = []
		_ring_task = WorkerThreadPool.add_task(_ring_arrays.bind(_ring_jobs.duplicate()), false, "terrain ring chunks")


func _ring_arrays(jobs: Array) -> void:
	var out: Array = []
	for j: Array in jobs:
		var c: Vector2i = j[0]
		var lod: int = j[1]
		out.append(_chunk_arrays(c.x, c.y, LOD_STEPS[lod], SKIRT_M[lod], PackedByteArray()))
	_ring_out = out


## Frees every level past its RING_FREE_M from `at`, and returns the levels 1 and 2 to build within
## their RING_BUILD_M, nearest first (level 1 counted nearer: it's what shows round the camera).
func _ring_plan(at: Vector3) -> Array:
	var chunk_m := CHUNK_CELLS * CELL_M
	var flat := Vector2(at.x, at.z)
	for lod in 3:
		var held: Dictionary = [_lod0, _lod1, _lod2][lod]
		for c: Vector2i in held.keys():
			if Vector2(-_half + (c.x + 0.5) * chunk_m, -_half + (c.y + 0.5) * chunk_m).distance_to(flat) > RING_FREE_M[lod]:
				(held[c] as Node).queue_free()
				held.erase(c)
				ring_freed += 1
				_ring_ranges(c)
	var count := chunk_count()
	var reach := RING_BUILD_M[2]
	var lo := Vector2i(clampi(floori((at.x - reach + _half) / chunk_m), 0, count - 1), clampi(floori((at.z - reach + _half) / chunk_m), 0, count - 1))
	var hi := Vector2i(clampi(floori((at.x + reach + _half) / chunk_m), 0, count - 1), clampi(floori((at.z + reach + _half) / chunk_m), 0, count - 1))
	var wanted: Array = []
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cz)
			var d := Vector2(-_half + (cx + 0.5) * chunk_m, -_half + (cz + 0.5) * chunk_m).distance_to(flat)
			if d <= RING_BUILD_M[1] and not _lod1.has(c):
				wanted.append([d * 0.5, c, 1])
			if d <= RING_BUILD_M[2] and not _lod2.has(c):
				wanted.append([d, c, 2])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return wanted.map(func(w: Array) -> Array: return [w[1], w[2]])


func _lod_instance(cx: int, cz: int, lod: int, mesh: ArrayMesh = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Mesh_%d_%d_%d" % [cx, cz, lod]
	node.mesh = mesh if mesh else _chunk_mesh(cx, cz, LOD_STEPS[lod], SKIRT_M[lod])
	node.material_override = _material
	node.visibility_range_begin = LOD_END_M[lod - 1] if lod > 0 else 0.0
	node.visibility_range_end = LOD_END_M[lod]
	node.visibility_range_begin_margin = 20.0 if lod > 0 else 0.0
	node.visibility_range_end_margin = 20.0 if LOD_END_M[lod] > 0.0 else 0.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## One chunk's mesh with a quad every `step` cells, and a skirt `skirt` metres deep.
func _chunk_mesh(cx: int, cz: int, step: int, skirt: float) -> ArrayMesh:
	return _mesh_of(_chunk_arrays(cx, cz, step, skirt, _covered_mask(cx, cz, step)))


## Which of a chunk's cells (row by row) GroundCuts draws finely, at the finest level (empty at
## the others, or with no cuts): read here on the main thread, for _chunk_arrays.
func _covered_mask(cx: int, cz: int, step: int) -> PackedByteArray:
	var out := PackedByteArray()
	if step != 1 or cuts == null:
		return out
	out.resize(CHUNK_CELLS * CHUNK_CELLS)
	for b in CHUNK_CELLS:
		for a in CHUNK_CELLS:
			if cuts.covers(Vector2i(cx * CHUNK_CELLS + a, cz * CHUNK_CELLS + b)):
				out[a + b * CHUNK_CELLS] = 1
	return out


func _mesh_of(data: Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data[0]
	arrays[Mesh.ARRAY_NORMAL] = data[1]
	arrays[Mesh.ARRAY_COLOR] = data[2]
	arrays[Mesh.ARRAY_INDEX] = data[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A chunk's mesh arrays [vertices, normals, colours, indices] with a quad every `step` cells and
## a skirt `skirt` metres deep, leaving out the cells `covered` marks (_covered_mask). Reads only
## the zone's generated ground (heights, pads, roads, water, features), never the scene: safe on a
## worker thread. A skirt's vertices take their edge vertex's normal and colour (worked out once).
func _chunk_arrays(cx: int, cz: int, step: int, skirt: float, covered: PackedByteArray, cells := CHUNK_CELLS) -> Array:
	var n := cells / step
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var i0 := cx * cells
	var j0 := cz * cells
	for b in n + 1:
		for a in n + 1:
			var i := i0 + a * step
			var j := j0 + b * step
			verts.append(_vertex(i, j))
			var nrm := vertex_normal(i, j)
			normals.append(nrm)
			colours.append(_ground_colour(i, j, nrm))
	for b in n:
		for a in n:
			if not covered.is_empty() and covered[a + b * CHUNK_CELLS] != 0:
				continue  # drawn fine (GroundCuts)
			var p := a + b * (n + 1)
			indices.append_array([p, p + 1, p + n + 1, p + 1, p + n + 2, p + n + 1])  # clockwise from above
	# Skirts: each edge's vertices again, lowered, joined to the edge.
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(n, 0), Vector2i(0, 1)],
		[Vector2i(n, n), Vector2i(-1, 0)], [Vector2i(0, n), Vector2i(0, -1)],
	]
	var down := Vector3(0, skirt, 0)
	for e: Array in edges:
		var start: Vector2i = e[0]
		var dir: Vector2i = e[1]
		var base := verts.size()
		for k in n + 1:
			var g: Vector2i = start + dir * k
			var top := g.x + g.y * (n + 1)
			verts.append(verts[top] - down)
			normals.append(normals[top])
			colours.append(colours[top])
		for k in n:
			var g0: Vector2i = start + dir * k
			var top0 := g0.x + g0.y * (n + 1)
			var g1: Vector2i = start + dir * (k + 1)
			var top1 := g1.x + g1.y * (n + 1)
			# Both sides: a skirt is seen from whichever neighbour shows the crack.
			indices.append_array([top0, top1, base + k + 1, top0, base + k + 1, base + k,
				top0, base + k + 1, top1, top0, base + k, base + k + 1])
	return [verts, normals, colours, indices]


func _ground_colour(i: int, j: int, n: Vector3) -> Color:
	var p := Vector2(v_x(i), v_x(j))
	if _pads_in.size() != pads.size():
		_shrink_pads()
	for k in _pads_in.size():
		if _pads_in[k].has_point(p):
			for r in _streets:
				if r.has_point(p):
					return c_road
			return _pad_colour(pads[k][0], p, i, j)
	var steep := clampf((1.0 - n.y) * 12.0, 0.0, 1.0)
	var patch := float(absi(hash(Vector2i(i / 3, j / 3) + Vector2i(seed_value, 0))) % 1000) / 1000.0
	var colour := c_grass.lerp(c_dry, patch * 0.25)  # the shader adds the larger, smoother patches
	if mud_margin_m > 0.0:
		# Mud toward the edge: the pan's margin, where the crust gives way to wet ground.
		var edge := minf(minf(p.x + _half, _half - p.x), minf(p.y + _half, _half - p.y)) + patch * 40.0
		colour = colour.lerp(c_earth, (1.0 - smoothstep(40.0, mud_margin_m, edge)) * 0.6)
	var h := _h(i, j)
	# Rock on the high ground; sand in riverbeds and on the beach.
	colour = colour.lerp(c_rock, clampf((h - rock_above_m) / 8.0, 0.0, 0.8))
	colour = colour.lerp(c_earth, steep)
	colour = colour.lerp(c_rock, clampf((1.0 - n.y) * 30.0 - 2.0, 0.0, 1.0))
	if _bed.size() == heights.size():
		colour = colour.lerp(c_sand, clampf(float(_bed[i + j * points]) / 255.0 * 1.6 - 0.3, 0.0, 0.85) * (1.0 - steep))
	if sea_side >= 0 and sand_below_m > -100.0 and sea_edge_distance(p.x, p.y) < sea_m + SEA_MARGIN_M + 40.0:
		# The beach: a band along the measured shoreline (which the coast wobble shapes).
		var beach := 1.0 - smoothstep(14.0, 50.0, shore_distance(p.x, p.y) + float(absi(hash(Vector2i(i / 2, j / 2))) % 100) * 0.08)
		colour = colour.lerp(c_sand, beach * (1.0 - steep * 0.5))
	if features:
		colour = features.tint(i, j, p, colour, n)  # fields, marsh, snow, gullies (ZoneFeatures)
	if water:
		# A river's or lake's bank: wet mud, gravel in patches (ZoneWater.shore_weight).
		var wet := water.shore_weight(i, j)
		if wet > 0.0:
			colour = colour.lerp(c_earth.darkened(0.28).lerp(c_rock, 0.35 if absi(hash(Vector2i(i, j) + Vector2i(seed_value, 3))) % 3 == 0 else 0.0), wet * 0.85)
	var tint := _road_tint(p.x, p.y)
	return colour.lerp(Color(tint.r, tint.g, tint.b), tint.a)  # (all of it on the road: the shader knows it by its colour)


## The pads a metre in from their edges (_ground_colour), made once (they were made again for
## every pad at every vertex). Pads are set while the zone generates, before any mesh is built.
var _pads_in: Array[Rect2] = []


func _shrink_pads() -> void:
	var out: Array[Rect2] = []
	for pad: Array in pads:
		out.append((pad[0] as Rect2).grow(-1.0))
	_pads_in = out


## A pad's ground at `p` (vertex i, j) (world visual pass, cghath 2026-10-20: a pad read as one
## flat square of earth): bare earth, worn back into dry grass toward its edge (PAD_WORN_M, unevenly),
## with patches of grey gravel and of darker trodden earth (PAD_PATCH_CELLS vertices across), all
## from the vertex and the zone's seed. The ground shader breaks it up further near the camera.
const PAD_WORN_M := 9.0
const PAD_PATCH_CELLS := 2


func _pad_colour(r: Rect2, p: Vector2, i: int, j: int) -> Color:
	var inside := minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))
	var roll := float(absi(hash(Vector3i(i, j, seed_value))) % 1000) / 1000.0
	var patch := absi(hash(Vector3i(i / PAD_PATCH_CELLS, j / PAD_PATCH_CELLS, seed_value + 5))) % 6
	var colour := c_earth
	if patch == 0:
		colour = colour.lerp(c_rock.lightened(0.12), 0.45)  # gravel
	elif patch == 1:
		colour = colour.darkened(0.1)  # trodden
	var worn := clampf(1.0 - (inside - 1.0) / PAD_WORN_M, 0.0, 1.0)
	return colour.lerp(c_dry.lerp(c_grass, 0.3), worn * (0.3 + 0.6 * roll))


## How much the ground at (x, z) is road: 1 on the line out to ROAD_CORE_M, 0 past
## ROAD_VERGE_M.
func road_weight(x: float, z: float) -> float:
	return _road_tint(x, z).a


## The road colour at (x, z), its alpha how much road it is (road_weight).
func _road_tint(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var best := Color(c_road, 0.0)
	for i: int in _road_grid.get(Vector2i(floori(x / ROAD_GRID_M), floori(z / ROAD_GRID_M)), []):
		var r: Array = _roads[i]
		if not (r[2] as Rect2).has_point(p):
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p)
		var w := 1.0 - smoothstep(float(r[3]), float(r[4]), d)
		if w > best.a:
			best = Color(r[5], w)
	return best


## Combined arms A6 (cg_brief queue item 2.7; docs/combined_arms.md 2.8.1): the ground at (x, z)
## for the vehicles' traction and rolling resistance (VehicleDrive, data/vehicle_drive.json
## "ground"): on a road's core asphalt (asphalt and street roads) or dirt (dirt roads and
## trails); a pad's town streets asphalt, the rest of a pad packed dirt; under water a river or
## lake bed is mud, but a ford's gravel track (ZoneBridges.on_ford) dirt; marsh mud, snow, rock
## (steep ground over STEEP_ROCK_Y, or the preset's high rock), riverbed and beach sand; else
## grass (fields too). Roads are looked up each time (they're narrow); the rest is kept per grid
## vertex once worked out (it never changes in a zone). Bridges' decks are VehicleDrive's
## (ZoneBridges.deck_at), patches of rubble the level's.
const GROUND_KINDS: Array[StringName] = [&"asphalt", &"dirt", &"grass", &"sand", &"mud", &"rock", &"snow", &"rubble"]
const STEEP_ROCK_Y := 0.8  # a slope over about 37 degrees reads as rock
var _ground := PackedByteArray()


func ground_at(x: float, z: float) -> StringName:
	if points == 0:
		return &"dirt"
	var p := Vector2(x, z)
	for i: int in _road_grid.get(Vector2i(floori(x / ROAD_GRID_M), floori(z / ROAD_GRID_M)), []):
		var r: Array = _roads[i]
		if (r[2] as Rect2).has_point(p) and Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) <= float(r[3]):
			return &"dirt" if String(r[6]) == "dirt" else &"asphalt"
	if water and water.depth_at(x, z) > 0.05:
		return &"dirt" if water.bridges and water.bridges.on_ford(p) else &"mud"
	if _ground.size() != heights.size():
		_ground.resize(heights.size())
		_ground.fill(255)
	var i := clampi(roundi((x + _half) / CELL_M), 0, points - 1)
	var j := clampi(roundi((z + _half) / CELL_M), 0, points - 1)
	var k := _ground[i + j * points]
	if k == 255:
		k = maxi(GROUND_KINDS.find(_ground_kind(i, j)), 0)
		_ground[i + j * points] = k
	return GROUND_KINDS[k]


func _ground_kind(i: int, j: int) -> StringName:
	var p := Vector2(v_x(i), v_x(j))
	for k in pads.size():
		if (pads[k][0] as Rect2).has_point(p):
			for r in _streets:
				if r.has_point(p):
					return &"asphalt"
			return &"dirt"
	if features:
		if features.soft_at(p.x, p.y) > 0.35:
			return &"mud"
		if features.snow_at(p.x, p.y) > 0.4:
			return &"snow"
	var n := vertex_normal(i, j)
	if n.y < STEEP_ROCK_Y or _h(i, j) > rock_above_m + 4.0:
		return &"rock"
	if mud_margin_m > 0.0 and minf(minf(p.x + _half, _half - p.x), minf(p.y + _half, _half - p.y)) < mud_margin_m * 0.5:
		return &"mud"
	if _bed.size() == heights.size() and float(_bed[i + j * points]) / 255.0 > 0.45:
		return &"sand"
	if sea_side >= 0 and sand_below_m > -100.0 and sea_edge_distance(p.x, p.y) < sea_m + SEA_MARGIN_M + 40.0 and shore_distance(p.x, p.y) < 30.0:
		return &"sand"
	if crust > 0.5:
		return &"dirt"  # a salt pan's crust
	return &"grass"


func v_x(i: int) -> float:
	return i * CELL_M - _half


## A flat ring of ground from the zone's edge out to APRON_M, at height 0.
func _apron(material: Material) -> MeshInstance3D:
	var h := _half
	var o := _half + APRON_M
	var verts := PackedVector3Array()
	var quads := [
		[Vector2(-o, -o), Vector2(o, -h)], [Vector2(-o, h), Vector2(o, o)],
		[Vector2(-o, -h), Vector2(-h, h)], [Vector2(h, -h), Vector2(o, h)],
	]
	for k in quads.size():
		var q: Array = quads[k]
		var a: Vector2 = q[0]
		var b: Vector2 = q[1]
		var y := (sea_level - sea_depth) if k == sea_side else -0.02  # the seabed beyond a sea
		verts.append_array([Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y),
			Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y)])  # clockwise from above (it faced down: culled, a void past the edge)
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for v in verts:
		normals.append(Vector3.UP)
		colours.append(c_apron)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = "Apron"
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# --- Sea -------------------------------------------------------------------------------------

## Distance from the sea side's edge to (x, z), or INF with no sea.
func sea_edge_distance(x: float, z: float) -> float:
	if sea_side < 0:
		return INF
	return [z + _half, _half - z, x + _half, _half - x][sea_side]


## How deep the water is at (x, z): 0 on dry ground or with no sea. Only the sea strip (the
## water reaches sea_m in from the edge, plus a margin for the shore) holds water.
func sea_depth_at(x: float, z: float) -> float:
	if sea_side < 0 or sea_edge_distance(x, z) > sea_m + SEA_MARGIN_M:
		return 0.0
	return maxf(sea_level - height_at(x, z), 0.0)


## The strip the water covers (x, z in metres), an empty Rect2 with no sea.
func sea_rect() -> Rect2:
	if sea_side < 0:
		return Rect2()
	var reach := sea_m + SEA_MARGIN_M
	var h := _half
	return [Rect2(-h, -h, size_m, reach), Rect2(-h, h - reach, size_m, reach), Rect2(-h, -h, reach, size_m), Rect2(h - reach, -h, reach, size_m)][sea_side]


## The water: a flat translucent plane over the shoreline strip, and one over the apron beyond
## the sea's edge (which is lowered to the seabed's height there).
func _water() -> MeshInstance3D:
	var r := sea_rect()
	var o := _half + APRON_M
	var h := _half
	var outer: Rect2 = [Rect2(-o, -o, 2.0 * o, o - h), Rect2(-o, h, 2.0 * o, o - h), Rect2(-o, -h, o - h, size_m), Rect2(h, -h, o - h, size_m)][sea_side]
	var verts := PackedVector3Array()
	# The strip carried on past the zone's two sides, so the coast doesn't end in a dry
	# spit of apron where the sea meets the side edge.
	var sides: Array = [Rect2(-o, r.position.y, o - h, r.size.y), Rect2(h, r.position.y, o - h, r.size.y)] if sea_side < 2 else [Rect2(r.position.x, -o, r.size.x, o - h), Rect2(r.position.x, h, r.size.x, o - h)]
	for q: Rect2 in [r, outer] + sides:
		var a := q.position
		var b := q.end
		var y := sea_level
		verts.append_array([Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y),
			Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y)])
	var normals := PackedVector3Array()
	for v in verts:
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.42, 0.50, 0.86)  # a sea under a blue sky, not a grey slab
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic_specular = 0.55
	var node := MeshInstance3D.new()
	node.name = "Sea"
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# --- The coast (wave 5b, V4): the sea above, as the LHD and the AAVs see it ------------------

## The sea's side by name ("north" -z, "south" +z, "west" -x, "east" +x; "" with no sea).
const SEA_SIDES: Array[String] = ["north", "south", "west", "east"]

var coast_side := ""
## The shoreline nearest the sea's edge: how far in from that edge the water ends at its
## narrowest (m; the LHD lies inside it).
var shore_m := 0.0
var _shore := PackedFloat32Array()  # per grid line along the coast: the shoreline's distance from the edge


## The shoreline along the coast: walking in from the sea's edge on each grid line, the first
## ground at or above the water (between grid points, where the ground crosses it), else the
## water's inner edge (sea_m + SEA_MARGIN_M). After the pads, so it is the ground as built.
func _measure_shore() -> void:
	coast_side = SEA_SIDES[sea_side] if sea_side >= 0 else ""
	_shore = PackedFloat32Array()
	shore_m = 0.0
	if sea_side < 0:
		return
	var reach := sea_m + SEA_MARGIN_M
	_shore.resize(points)
	shore_m = reach
	for k in points:
		var line := reach
		var prev := sea_level - sea_depth
		for s in points:
			var d := s * CELL_M
			if d > reach:
				break
			var h: float = [_h(k, s), _h(k, points - 1 - s), _h(s, k), _h(points - 1 - s, k)][sea_side]
			if h >= sea_level:
				line = 0.0 if s == 0 else d - CELL_M * (h - sea_level) / maxf(h - prev, 0.001)
				break
			prev = h
		_shore[k] = line
		shore_m = minf(shore_m, line)


func has_coast() -> bool:
	return sea_side >= 0


## How far (x, z) is inland of the shoreline (m; negative out to sea). INF with no sea.
func shore_distance(x: float, z: float) -> float:
	if sea_side < 0 or _shore.is_empty():
		return INF
	var along := x if sea_side <= 1 else z
	var g := clampf((along + _half) / CELL_M, 0.0, points - 1.0)
	var k := mini(floori(g), points - 2)
	return sea_edge_distance(x, z) - lerpf(_shore[k], _shore[k + 1], g - k)


## The water's surface at (x, z): sea_level over the sea strip (where the Sea mesh is, and on
## out past the zone's edge), a river's, stream's or lake's over its water (ZoneWater), -INF
## where there is no water. Below the ground it's dry land.
func water_height(x: float, z: float) -> float:
	var sea := sea_level if sea_side >= 0 and sea_edge_distance(x, z) <= sea_m + SEA_MARGIN_M else -INF
	return maxf(sea, water.surface_at(x, z)) if water else sea  # and the rivers and lakes (ZoneWater)


## Out to sea (a unit vector on the ground plane), ZERO with no sea.
func seaward() -> Vector3:
	return [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)][sea_side] if sea_side >= 0 else Vector3.ZERO


## The point `t` metres inland of the shoreline (negative: out to sea) level with `pos` along
## the coast, on the ground or the water.
func shore_point(pos: Vector3, t: float) -> Vector3:
	if sea_side < 0:
		return pos
	var out := seaward()
	var p := Vector3(pos.x, 0.0, pos.z)
	p -= out * (t - shore_distance(p.x, p.z))  # the shoreline is a function of the along-coast position: one step
	return Vector3(p.x, maxf(height_at(p.x, p.z), water_height(p.x, p.z)), p.z)
