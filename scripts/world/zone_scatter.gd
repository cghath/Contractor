class_name ZoneScatter
extends Node3D
## Rocks, scrub and trees on a zone's terrain (the terrain preset's "scatter": items per km2 of
## zone, so a bigger zone gets more, up to caps). Deterministic from the zone's seed and
## preset: every peer lays out the same items. Never on a module's pad, an insertion or
## extraction point, a road, in the sea or on steep ground.
##
## Visuals are MultiMeshes per CELL_M square (low-poly blocky shapes, in the voxel look),
## built nearest cells first as the camera comes near (like the terrain's finest level) and
## skipped on a headless server. Large rocks and tree trunks also have collision (one static
## body per cell, built up front: cover for the AI) and are baked into the navigation mesh as
## boxes; scrub is visual only.

enum Kind { ROCK, SCRUB, TREE }

## Most items of each kind in a zone (a 16 km2 hot zone hits them).
const CAP_ROCKS := 2600
const CAP_SCRUB := 9000
const CAP_TREES := 1400
## Most items with collision (large rocks and trees) in a zone.
const CAP_SOLID := 1700
## Items keep this far outside every pad (the pad's own margin is already in its rect), the
## edge of the zone, and a road's line (m).
const PAD_KEEP_M := 10.0
const EDGE_KEEP_M := 12.0
const ROAD_KEEP_M := 9.0
## Cells are this wide (m); visuals build for cells within BUILD_M of the camera, this many a
## frame, checked every CHECK_S.
const CELL_M := 128.0
const BUILD_M := 1000.0
const PER_FRAME := 2
const CHECK_S := 0.5
## Draw distances (m): scrub, rocks, trunks and crowns.
const SEE_SCRUB_M := 240.0
const SEE_ROCK_M := 650.0
const SEE_TREE_M := 950.0

## Every item: {"kind", "pos" (Vector3), "yaw", "size" (Vector3), "colour" (Color), "solid"}.
var items: Array[Dictionary] = []
var counts := {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0}
var solid_count := 0

var _terrain: ZoneTerrain
var _spec := {}
var _cells := {}  # Vector2i -> Array of item indices
var _built := {}  # Vector2i -> true
var _meshes := {}
var _material: StandardMaterial3D
var _next_check := 0.0
var _visuals_on := false


## Lays the items out. `terrain` must be generated; `def` is the zone's def ("roads" in it
## keep clear).
func generate(terrain: ZoneTerrain, def: Dictionary) -> void:
	_terrain = terrain
	items.clear()
	_cells.clear()
	counts = {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0}
	solid_count = 0
	_spec = terrain.preset.get("scatter", {})
	if _spec.is_empty():
		return
	var half := terrain.size_m * 0.5
	var area_km2 := terrain.size_m * terrain.size_m / 1.0e6
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value ^ 0x5CA7
	var cluster := FastNoiseLite.new()
	cluster.seed = terrain.seed_value + 77
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster.frequency = 1.0 / 240.0
	var keep: Array[Rect2] = []
	for pad: Array in terrain.pads:
		keep.append((pad[0] as Rect2).grow(PAD_KEEP_M))
	var roads: Array = def.get("roads", [])
	var colours: Dictionary = _spec.get("colours", {})
	var rock_colours := _colours(colours.get("rock", ["77736a"]))
	var scrub_colours := _colours(colours.get("scrub", ["55633a"]))
	var crown_colours := _colours(colours.get("crown", ["46602f"]))
	var large_share := float(_spec.get("large_rock_share", 0.15))
	var plan := [
		[Kind.ROCK, float(_spec.get("rocks_per_km2", 0.0)), CAP_ROCKS],
		[Kind.TREE, float(_spec.get("trees_per_km2", 0.0)), CAP_TREES],
		[Kind.SCRUB, float(_spec.get("scrub_per_km2", 0.0)), CAP_SCRUB],
	]
	for entry: Array in plan:
		var kind: int = entry[0]
		var want := mini(int(round(float(entry[1]) * area_km2)), int(entry[2]))
		var attempts := want * 4
		while counts[kind] < want and attempts > 0:
			attempts -= 1
			var x := rng.randf_range(-half + EDGE_KEEP_M, half - EDGE_KEEP_M)
			var z := rng.randf_range(-half + EDGE_KEEP_M, half - EDGE_KEEP_M)
			var roll := rng.randf()
			var yaw := rng.randf() * TAU
			var pick := rng.randf()
			var variation := rng.randf()
			var scale_roll := rng.randf()
			var squash_roll := rng.randf()
			if _blocked(x, z, keep, roads):
				continue
			var h := terrain.height_at(x, z)
			if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
				continue
			var up := terrain.normal_at(x, z).y
			var item := {"kind": kind, "yaw": yaw, "solid": false}
			match kind:
				Kind.ROCK:
					if up < 0.55:
						continue
					var large := pick < large_share and solid_count < CAP_SOLID
					var s := lerpf(1.6, 3.4, scale_roll) if large else lerpf(0.35, 1.1, scale_roll)
					item["size"] = Vector3(s, s * lerpf(0.55, 0.85, squash_roll), s * lerpf(0.8, 1.2, squash_roll))
					item["pos"] = Vector3(x, h + item.size.y * 0.3, z)
					item["colour"] = rock_colours[int(variation * rock_colours.size()) % rock_colours.size()]
					item["solid"] = large
				Kind.SCRUB:
					# Clumps: denser where the cluster noise is high.
					if up < 0.8 or roll > clampf(cluster.get_noise_2d(x, z) * 1.6 + 0.8, 0.1, 1.0):
						continue
					var s := lerpf(0.6, 1.5, scale_roll)
					item["size"] = Vector3(s, s * lerpf(0.5, 0.9, squash_roll), s)
					item["pos"] = Vector3(x, h, z)
					item["colour"] = scrub_colours[int(variation * scrub_colours.size()) % scrub_colours.size()]
				Kind.TREE:
					if up < 0.9 or roll > clampf(cluster.get_noise_2d(x + 500.0, z - 500.0) * 2.2 + 0.6, 0.05, 1.0):
						continue
					var s := lerpf(0.8, 1.45, scale_roll)
					item["size"] = Vector3(s, s, s)
					item["pos"] = Vector3(x, h, z)
					item["colour"] = crown_colours[int(variation * crown_colours.size()) % crown_colours.size()]
					item["solid"] = solid_count < CAP_SOLID
			if item.solid:
				solid_count += 1
			counts[kind] += 1
			var cell := _cell_of(x, z)
			if not _cells.has(cell):
				_cells[cell] = []
			(_cells[cell] as Array).append(items.size())
			items.append(item)


func _colours(hexes: Array) -> Array[Color]:
	var out: Array[Color] = []
	for hex in hexes:
		out.append(Color(String(hex)))
	return out


func _blocked(x: float, z: float, keep: Array[Rect2], roads: Array) -> bool:
	var p := Vector2(x, z)
	for r in keep:
		if r.has_point(p):
			return true
	for road: Array in roads:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < ROAD_KEEP_M:
			return true
	return false


func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + _terrain.size_m * 0.5) / CELL_M), floori((z + _terrain.size_m * 0.5) / CELL_M))


## A hash of the layout: two peers that generated the same zone have the same.
func checksum() -> int:
	var flat := PackedFloat32Array()
	for item in items:
		var p: Vector3 = item.pos
		flat.append_array([float(item.kind), p.x, p.y, p.z, item.yaw, (item.size as Vector3).x])
	return hash(flat)


func total() -> int:
	return items.size()


## The footprints (world AABBs) of the solid items overlapping `area` (x, z in metres), for
## the navigation mesh.
func boxes_in(area: Rect2) -> Array[AABB]:
	var out: Array[AABB] = []
	if _cells.is_empty():
		return out
	var lo := _cell_of(area.position.x, area.position.y)
	var hi := _cell_of(area.end.x, area.end.y)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				if not item.solid or not area.has_point(Vector2(item.pos.x, item.pos.z)):
					continue
				var half := _solid_half(item)
				var p: Vector3 = item.pos
				var centre := p + Vector3(0, half.y, 0) if item.kind == Kind.TREE else p
				out.append(AABB(centre - half, half * 2.0))
	return out


func _solid_half(item: Dictionary) -> Vector3:
	var s: Vector3 = item.size
	if item.kind == Kind.TREE:
		return Vector3(0.3 * s.x, 1.5 * s.y, 0.3 * s.x)
	return Vector3(maxf(s.x, s.z) * 0.5, s.y * 0.5, maxf(s.x, s.z) * 0.5)


# --- Collision -------------------------------------------------------------------------------

## One static body per cell holding every solid item's shape in it (large rocks and trunks).
func build_collision() -> void:
	for cell: Vector2i in _cells:
		var body: StaticBody3D = null
		for index: int in _cells[cell]:
			var item: Dictionary = items[index]
			if not item.solid:
				continue
			if body == null:
				body = StaticBody3D.new()
				body.name = "Cover_%d_%d" % [cell.x, cell.y]
				body.collision_layer = 1
				body.collision_mask = 0
				add_child(body)
			var shape := CollisionShape3D.new()
			var s: Vector3 = item.size
			if item.kind == Kind.TREE:
				var cylinder := CylinderShape3D.new()
				cylinder.radius = 0.3 * s.x
				cylinder.height = 3.0 * s.y
				shape.shape = cylinder
				shape.position = (item.pos as Vector3) + Vector3(0, 1.5 * s.y, 0)
			else:
				var box := BoxShape3D.new()
				box.size = Vector3(s.x * 0.9, s.y, s.z * 0.9)
				shape.shape = box
				shape.position = item.pos
				shape.rotation.y = item.yaw
			body.add_child(shape)


# --- Visuals ---------------------------------------------------------------------------------

## Starts building the visuals as the camera nears (nothing on a headless server).
func build_visuals() -> void:
	if _visuals_on or _cells.is_empty():
		return
	_visuals_on = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	var colours: Dictionary = _spec.get("colours", {})
	_meshes = {
		Kind.ROCK: _blocky(Vector3(1, 1, 1), Color.WHITE, 0.22, 1, true),
		Kind.SCRUB: _scrub_mesh(),
		"trunk": _blocky(Vector3(0.4, 2.6, 0.4), Color(String(colours.get("trunk", "4f3e2c"))), 0.03, 2, false),
		"crown": _crown_mesh(),
	}
	set_process(true)


## Builds up to `budget` cells' visuals near `pos`, nearest first; returns how many it built.
func build_near(pos: Vector3, budget: int) -> int:
	if not _visuals_on:
		return 0
	var wanted: Array = []
	var half := _terrain.size_m * 0.5
	for cell: Vector2i in _cells:
		if _built.has(cell):
			continue
		var centre := Vector2(-half + (cell.x + 0.5) * CELL_M, -half + (cell.y + 0.5) * CELL_M)
		var d := centre.distance_to(Vector2(pos.x, pos.z))
		if d < BUILD_M:
			wanted.append([d, cell])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var done := 0
	for w: Array in wanted.slice(0, budget):
		_build_cell(w[1])
		done += 1
	return done


func built_cells() -> int:
	return _built.size()


func _process(delta: float) -> void:
	_next_check -= delta
	if _next_check > 0.0:
		return
	_next_check = CHECK_S
	var camera := get_viewport().get_camera_3d()
	if camera:
		build_near(camera.global_position, PER_FRAME)


func _build_cell(cell: Vector2i) -> void:
	_built[cell] = true
	var groups := {Kind.ROCK: [], Kind.SCRUB: [], "trunk": [], "crown": []}
	for index: int in _cells[cell]:
		var item: Dictionary = items[index]
		var basis := Basis(Vector3.UP, float(item.yaw))
		var xf := Transform3D(basis.scaled(item.size), item.pos)
		match int(item.kind):
			Kind.ROCK:
				groups[Kind.ROCK].append([xf, item.colour])
			Kind.SCRUB:
				groups[Kind.SCRUB].append([xf, item.colour])
			Kind.TREE:
				var trunk := Transform3D(basis.scaled(item.size), (item.pos as Vector3) - Vector3(0, 0.1, 0))
				groups["trunk"].append([trunk, Color.WHITE])
				groups["crown"].append([xf, item.colour])
	var ranges := {Kind.ROCK: SEE_ROCK_M, Kind.SCRUB: SEE_SCRUB_M, "trunk": SEE_TREE_M, "crown": SEE_TREE_M}
	for key in groups:
		var list: Array = groups[key]
		if list.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _meshes[key]
		multi.instance_count = list.size()
		for k in list.size():
			multi.set_instance_transform(k, list[k][0])
			multi.set_instance_color(k, list[k][1])
		var node := MultiMeshInstance3D.new()
		node.name = "Scatter_%d_%d_%s" % [cell.x, cell.y, str(key)]
		node.multimesh = multi
		node.material_override = _material
		node.visibility_range_end = float(ranges[key])
		node.visibility_range_end_margin = 20.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key == Kind.SCRUB else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)


# --- Shapes: low-poly blocks, flat shaded ----------------------------------------------------

## A box `size` m with its corners nudged by `jitter` (a fraction of its size), seeded by
## `seed`, flat shaded, in `colour`; centred on the origin, or standing on y = 0.
func _blocky(size: Vector3, colour: Color, jitter: float, seed: int, centred: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var corners: Array[Vector3] = []
	for k in 8:
		var sx := -0.5 if (k & 1) == 0 else 0.5
		var sy := (0.0 if (k & 2) == 0 else 1.0) - (0.5 if centred else 0.0)
		var sz := -0.5 if (k & 4) == 0 else 0.5
		var v := Vector3(sx * size.x, sy * size.y, sz * size.z)
		v += Vector3(rng.randf_range(-jitter, jitter) * size.x, rng.randf_range(-jitter, jitter) * size.y, rng.randf_range(-jitter, jitter) * size.z)
		corners.append(v)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, corners, colour)
	return st.commit()


func _add_box(st: SurfaceTool, corners: Array[Vector3], colour: Color) -> void:
	var centre := Vector3.ZERO
	for c in corners:
		centre += c / 8.0
	for q: Array in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		var a: Vector3 = corners[q[0]]
		var b: Vector3 = corners[q[1]]
		var c: Vector3 = corners[q[2]]
		var d: Vector3 = corners[q[3]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c + d) / 4.0 - centre) < 0.0:
			n = -n
			var swap := b
			b = d
			d = swap
		# a, b, c, d run counter-clockwise seen from outside; Godot wants clockwise.
		for v: Vector3 in [a, c, b, a, d, c]:
			st.set_color(colour)
			st.set_normal(n)
			st.add_vertex(v)


## Scrub: three blocky lumps in a clump, on the ground (the instance colour tints it).
func _scrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 3:
		var corners: Array[Vector3] = []
		var size := Vector3(0.55, rng.randf_range(0.45, 0.7), 0.55)
		var at := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		for c in 8:
			var v := Vector3(-0.5 if (c & 1) == 0 else 0.5, 0.0 if (c & 2) == 0 else 1.0, -0.5 if (c & 4) == 0 else 0.5)
			var top := 0.55 if (c & 2) != 0 else 1.0  # narrower at the top
			corners.append(at + Vector3(v.x * size.x * top, v.y * size.y, v.z * size.z * top)
				+ Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06)))
		_add_box(st, corners, Color.WHITE)
	return st.commit()


## A tree's crown: two blocks, wide under narrow, from 2 m up (the trunk's top).
func _crown_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for spec: Array in [[Vector3(2.6, 1.8, 2.6), 2.0], [Vector3(1.7, 1.3, 1.7), 3.6]]:
		var size: Vector3 = spec[0]
		var corners: Array[Vector3] = []
		for c in 8:
			var v := Vector3(-0.5 if (c & 1) == 0 else 0.5, 0.0 if (c & 2) == 0 else 1.0, -0.5 if (c & 4) == 0 else 0.5)
			corners.append(Vector3(v.x * size.x, float(spec[1]) + v.y * size.y, v.z * size.z)
				+ Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.15, 0.15)))
		_add_box(st, corners, Color.WHITE)
	return st.commit()
