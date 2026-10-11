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
const WALL_HEIGHT_M := 400.0
## Ground colours: grass, dry grass, bare earth on slopes and on pads, rock on steep ground.
const GRASS := Color("5f6a3c")
const DRY := Color("7d7748")
const EARTH := Color("7f6d4f")
const ROCK := Color("6f6a60")

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

var _half := 0.0
var _visuals_built := false
var _material: StandardMaterial3D
var _lod0 := {}  # Vector2i chunk -> its finest MeshInstance3D
var _lod1 := {}  # Vector2i chunk -> its middle MeshInstance3D


## Builds the heights from the zone definition (ZoneDef): seed, size, relief, and a pad
## under each module footprint and landing zone (`flat`: Array of Rect2).
func generate(def: Dictionary, flat: Array) -> void:
	seed_value = int(def.get("seed", 0))
	size_m = float(def.get("size_m", 2048.0))
	relief_m = float(def.get("relief_m", 18.0))
	_half = size_m * 0.5
	points = int(round(size_m / CELL_M)) + 1
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.42
	noise.frequency = 1.0 / 650.0
	heights.resize(points * points)
	for j in points:
		var z := j * CELL_M - _half
		for i in points:
			var x := i * CELL_M - _half
			var edge := minf(minf(x + _half, _half - x), minf(z + _half, _half - z))
			heights[i + j * points] = noise.get_noise_2d(x, z) * relief_m * smoothstep(0.0, EDGE_FADE_M, edge)
	pads.clear()
	for rect: Rect2 in flat:
		_flatten(rect)
	min_height = INF
	max_height = -INF
	for h in heights:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)


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
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	var count := chunk_count()
	for cz in count:
		for cx in count:
			for lod in range(1, LOD_STEPS.size()):
				var node := _lod_instance(cx, cz, lod)
				if lod == 1:
					node.visibility_range_begin = 0.0  # until the finest level is built
					_lod1[Vector2i(cx, cz)] = node
	add_child(_apron(_material))
	set_process(true)


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
			return EARTH
	var steep := clampf((1.0 - n.y) * 12.0, 0.0, 1.0)
	var patch := float(absi(hash(Vector2i(i / 3, j / 3) + Vector2i(seed_value, 0))) % 1000) / 1000.0
	var colour := GRASS.lerp(DRY, patch * 0.6)
	colour = colour.lerp(EARTH, steep)
	return colour.lerp(ROCK, clampf((1.0 - n.y) * 30.0 - 2.0, 0.0, 1.0))


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
	for q: Array in quads:
		var a: Vector2 = q[0]
		var b: Vector2 = q[1]
		verts.append_array([Vector3(a.x, -0.02, a.y), Vector3(b.x, -0.02, b.y), Vector3(b.x, -0.02, a.y),
			Vector3(a.x, -0.02, a.y), Vector3(a.x, -0.02, b.y), Vector3(b.x, -0.02, b.y)])
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for v in verts:
		normals.append(Vector3.UP)
		colours.append(GRASS)
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
