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
## Flat pads under modules and landing zones: this much beyond the footprint stays flat,
## then the ground blends back over PAD_BLEND_M.
const PAD_MARGIN_M := 6.0
const PAD_BLEND_M := 40.0
## The apron around the zone (m beyond the edge) and the invisible wall's height.
const APRON_M := 6000.0
## The water reaches this far past the shoreline strip so the beach is covered (m).
const SEA_MARGIN_M := 40.0
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
var _bed := PackedByteArray()  # riverbed weight (0..255) per height
## The def's "roads" as [a, b, bounds] (Vector2, Vector2, Rect2 grown by ROAD_VERGE_M): the
## ground under and beside them takes the road colour, so they show past ZoneRoads.SEE_M.
var _roads: Array = []
## A generated town's streets (Rect2s, x/z in metres): its pad is road-coloured along them.
var _streets: Array[Rect2] = []

var _half := 0.0
var _visuals_built := false
var _material: ShaderMaterial
var _lod0 := {}  # Vector2i chunk -> its finest MeshInstance3D
var _lod1 := {}  # Vector2i chunk -> its middle MeshInstance3D


## Builds the heights from the zone definition (ZoneDef): seed, size, relief, terrain preset
## (TerrainPresets), sea, and a pad under each module footprint and landing zone (`flat`:
## Array of Rect2).
func generate(def: Dictionary, flat: Array) -> void:
	seed_value = int(def.get("seed", 0))
	size_m = float(def.get("size_m", 2048.0))
	preset_id = String(def.get("terrain", "plain"))
	preset = TerrainPresets.get_preset(preset_id)
	var land: Dictionary = preset.get("land", {})
	relief_m = float(def.get("relief_m", 18.0)) * float(land.get("relief_scale", 1.0))
	_half = size_m * 0.5
	points = int(round(size_m / CELL_M)) + 1
	_read_palette()
	_roads.clear()
	for road: Array in def.get("roads", []):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		_roads.append([a, b, Rect2(a, Vector2.ZERO).expand(b).grow(ROAD_VERGE_M)])
	_streets.clear()
	for m: Dictionary in def.get("modules", []):
		if ZoneModules.base(String(m.type)) == "town" and ZoneModules.has_type(String(m.type)):
			var at := Vector2(float(m.pos[0]), float(m.pos[1]))
			var half: Vector2 = ZoneModules.HALF[String(m.type)]
			_streets.append(Rect2(at.x - BuildingGen.TOWN_HALF_X, at.y - BuildingGen.STREET_W * 0.5, BuildingGen.TOWN_HALF_X * 2.0, BuildingGen.STREET_W))
			_streets.append(Rect2(at.x - BuildingGen.CROSS_W * 0.5, at.y - half.y, BuildingGen.CROSS_W, half.y * 2.0))
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
			var carve := 0.0
			for w: Dictionary in wadis:
				carve = maxf(carve, _wadi_weight(w, x, z))
			if carve > 0.0:
				h -= carve * float(w_depth)
			var fade := smoothstep(0.0, EDGE_FADE_M, edge)
			h *= fade
			if sea_side >= 0:
				var d: float = [z + _half, _half - z, x + _half, _half - x][sea_side]
				h = lerpf(h, sea_level - sea_depth, 1.0 - smoothstep(0.0, sea_m, d))
			heights[i + j * points] = h
			_bed[i + j * points] = int(carve * 255.0)
	pads.clear()
	for rect: Rect2 in flat:
		_flatten(rect)
	min_height = INF
	max_height = -INF
	for h in heights:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)
	_measure_shore()  # wave 5b (V4): the coast the LHD and AAVs use, from the sea above


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


## The height of the noise ground (before pads) is what a pad takes: the grid's height at
## its centre. Inside the rect grown by PAD_MARGIN_M it's flat; it blends back over
## PAD_BLEND_M beyond that.
func _flatten(rect: Rect2) -> void:
	var flat := rect.grow(PAD_MARGIN_M)
	var centre := flat.get_center()
	var h := snappedf(height_at(centre.x, centre.y), 0.05)
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
## height fields are; measured: within 0.1 mm of a raycast). Outside the zone: 0 (the apron).
func height_at(x: float, z: float) -> float:
	var gx := (x + _half) / CELL_M
	var gz := (z + _half) / CELL_M
	if gx < 0.0 or gz < 0.0 or gx > points - 1 or gz > points - 1:
		return 0.0
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


## The ground's surface normal at (x, z) (from the grid around it).
func normal_at(x: float, z: float) -> Vector3:
	var e := CELL_M
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## The steepest slope in the grid (degrees), for checks.
func max_slope_deg() -> float:
	var worst := 0.0
	for j in points - 1:
		for i in points - 1:
			var h := _h(i, j)
			worst = maxf(worst, maxf(absf(_h(i + 1, j) - h), absf(_h(i, j + 1) - h)))
	return rad_to_deg(atan(worst / CELL_M))


## A hash of the heights: two peers that generated the same zone have the same.
func checksum() -> int:
	return hash(heights)


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

## One static body per chunk with a height field, plus the walls at the zone's edge.
func build_collision() -> void:
	var count := chunk_count()
	for cz in count:
		for cx in count:
			var body := StaticBody3D.new()
			body.name = "Ground_%d_%d" % [cx, cz]
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := HeightMapShape3D.new()
			shape.map_width = CHUNK_CELLS + 1
			shape.map_depth = CHUNK_CELLS + 1
			var data := PackedFloat32Array()
			data.resize((CHUNK_CELLS + 1) * (CHUNK_CELLS + 1))
			for j in CHUNK_CELLS + 1:
				for i in CHUNK_CELLS + 1:
					data[i + j * (CHUNK_CELLS + 1)] = _h(cx * CHUNK_CELLS + i, cz * CHUNK_CELLS + j)
			shape.map_data = data
			var node := CollisionShape3D.new()
			node.shape = shape
			node.scale = Vector3(CELL_M, 1.0, CELL_M)
			body.add_child(node)
			var chunk_m := CHUNK_CELLS * CELL_M
			body.position = Vector3(-_half + (cx + 0.5) * chunk_m, 0.0, -_half + (cz + 0.5) * chunk_m)
			add_child(body)
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


# --- Visuals ---------------------------------------------------------------------------------

## The ground's mesh: every chunk at the two coarse levels of detail, and the apron. The
## finest level is built as the camera comes near (LOD0_BUILD_M, LOD0_PER_FRAME a frame):
## building all of it up front took 1.4 s for a 2 km zone. Not needed (and skipped) on a
## headless server.
func build_visuals() -> void:
	if _visuals_built:
		return
	_visuals_built = true
	_material = ground_material()
	var count := chunk_count()
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
	return m


## The finest level for the chunks nearest `pos`, at most `budget` of them; returns how
## many it built.
func build_near(pos: Vector3, budget: int) -> int:
	if not _visuals_built:
		return 0
	var chunk_m := CHUNK_CELLS * CELL_M
	var wanted: Array = []
	var count := chunk_count()
	for cz in count:
		for cx in count:
			var c := Vector2i(cx, cz)
			if _lod0.has(c):
				continue
			var centre := Vector2(-_half + (cx + 0.5) * chunk_m, -_half + (cz + 0.5) * chunk_m)
			var d := centre.distance_to(Vector2(pos.x, pos.z))
			if d < LOD0_BUILD_M:
				wanted.append([d, c])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var built := 0
	for w: Array in wanted.slice(0, budget):
		var c: Vector2i = w[1]
		_lod0[c] = _lod_instance(c.x, c.y, 0)
		_lod1[c].visibility_range_begin = LOD_END_M[0]
		built += 1
	return built


## How many chunks have their finest mesh built.
func fine_chunks() -> int:
	return _lod0.size()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		build_near(camera.global_position, LOD0_PER_FRAME)


func _lod_instance(cx: int, cz: int, lod: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Mesh_%d_%d_%d" % [cx, cz, lod]
	node.mesh = _chunk_mesh(cx, cz, LOD_STEPS[lod], SKIRT_M[lod])
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
	var n := CHUNK_CELLS / step
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var i0 := cx * CHUNK_CELLS
	var j0 := cz * CHUNK_CELLS
	for b in n + 1:
		for a in n + 1:
			_add_vertex(verts, normals, colours, i0 + a * step, j0 + b * step, 0.0)
	for b in n:
		for a in n:
			var p := a + b * (n + 1)
			indices.append_array([p, p + 1, p + n + 1, p + 1, p + n + 2, p + n + 1])  # clockwise from above
	# Skirts: each edge's vertices again, lowered, joined to the edge.
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(n, 0), Vector2i(0, 1)],
		[Vector2i(n, n), Vector2i(-1, 0)], [Vector2i(0, n), Vector2i(0, -1)],
	]
	for e: Array in edges:
		var start: Vector2i = e[0]
		var dir: Vector2i = e[1]
		var base := verts.size()
		for k in n + 1:
			var g: Vector2i = start + dir * k
			_add_vertex(verts, normals, colours, i0 + g.x * step, j0 + g.y * step, skirt)
		for k in n:
			var g0: Vector2i = start + dir * k
			var top0 := g0.x + g0.y * (n + 1)
			var g1: Vector2i = start + dir * (k + 1)
			var top1 := g1.x + g1.y * (n + 1)
			# Both sides: a skirt is seen from whichever neighbour shows the crack.
			indices.append_array([top0, top1, base + k + 1, top0, base + k + 1, base + k,
				top0, base + k + 1, top1, top0, base + k, base + k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_vertex(verts: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, i: int, j: int, drop: float) -> void:
	var v := _vertex(i, j)
	verts.append(v - Vector3(0, drop, 0))
	var n := Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * CELL_M, _h(i, j - 1) - _h(i, j + 1)).normalized()
	normals.append(n)
	colours.append(_ground_colour(i, j, n))


func _ground_colour(i: int, j: int, n: Vector3) -> Color:
	var p := Vector2(v_x(i), v_x(j))
	for pad: Array in pads:
		if (pad[0] as Rect2).grow(-1.0).has_point(p):
			return c_road if _streets.any(func(r: Rect2) -> bool: return r.has_point(p)) else c_earth
	var steep := clampf((1.0 - n.y) * 12.0, 0.0, 1.0)
	var patch := float(absi(hash(Vector2i(i / 3, j / 3) + Vector2i(seed_value, 0))) % 1000) / 1000.0
	var colour := c_grass.lerp(c_dry, patch * 0.25)  # the shader adds the larger, smoother patches
	var h := _h(i, j)
	# Rock on the high ground; sand in riverbeds and on the beach.
	colour = colour.lerp(c_rock, clampf((h - rock_above_m) / 8.0, 0.0, 0.8))
	colour = colour.lerp(c_earth, steep)
	colour = colour.lerp(c_rock, clampf((1.0 - n.y) * 30.0 - 2.0, 0.0, 1.0))
	if _bed.size() == heights.size():
		colour = colour.lerp(c_sand, clampf(float(_bed[i + j * points]) / 255.0 * 1.6 - 0.3, 0.0, 0.85) * (1.0 - steep))
	if sea_side >= 0 and sand_below_m > -100.0 and sea_edge_distance(p.x, p.y) < sea_m + SEA_MARGIN_M + 40.0:
		colour = colour.lerp(c_sand, smoothstep(sea_level + sand_below_m, sea_level, h) * (1.0 - steep * 0.5))
	return colour.lerp(c_road, road_weight(p.x, p.y) * 0.8)


## How much the ground at (x, z) is road: 1 on the line out to ROAD_CORE_M, 0 past
## ROAD_VERGE_M.
func road_weight(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for r: Array in _roads:
		if not (r[2] as Rect2).has_point(p):
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p)
		best = maxf(best, 1.0 - smoothstep(ROAD_CORE_M, ROAD_VERGE_M, d))
	return best


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
		verts.append_array([Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b.x, y, a.y),
			Vector3(a.x, y, a.y), Vector3(a.x, y, b.y), Vector3(b.x, y, b.y)])
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
	for q: Rect2 in [r, outer]:
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
## out past the zone's edge), -INF where there is no water. Below the ground it's dry land.
func water_height(x: float, z: float) -> float:
	return sea_level if sea_side >= 0 and sea_edge_distance(x, z) <= sea_m + SEA_MARGIN_M else -INF


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
