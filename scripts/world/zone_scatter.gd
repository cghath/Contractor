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
const SEE_SCRUB_M := 550.0  # bushes read at mid range (round 3: was 400)
const SEE_ROCK_M := 650.0
const SEE_TREE_M := 950.0

## Foliage shapes for spotting (foliage_between), as shares of an item's size (its meshes:
## _scrub_mesh, _crown_mesh), and how far past a line's ends an item can still reach it (m).
const SCRUB_R := 0.5
const SCRUB_TOP := 0.6
const CROWN_R := 1.1
const CROWN_LOW := 2.0
const CROWN_HIGH := 4.9
const FOLIAGE_PAD_M := 3.0
## Ground cover (visual only, not in `items`, no collision, no effect on sight or the layout's
## checksum): grass tufts and pebbles laid out per cell when it builds, from the cell and the
## seed, so every peer draws the same. The preset's scatter "tufts_per_km2" (0: none) and
## "pebbles_per_km2"; seen out to SEE_TUFT_M / SEE_PEBBLE_M.
const SEE_TUFT_M := 140.0
const SEE_PEBBLE_M := 70.0
## Rock clusters (the preset's scatter "rock_clusters_per_km2"), visual only like the tufts.
const SEE_OUTCROP_M := 420.0
const CAP_TUFTS_PER_CELL := 1200

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
var _keep: Array[Rect2] = []
var _roads: Array = []
var _cluster: FastNoiseLite


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
	_keep = keep
	_roads = roads
	_cluster = cluster
	if float(_spec.get("tufts_per_km2", 0.0)) > 0.0:
		# Ground cover goes in every cell, not only those holding an item.
		var cells := ceili(terrain.size_m / CELL_M)
		for cz in cells:
			for cx in cells:
				if not _cells.has(Vector2i(cx, cz)):
					_cells[Vector2i(cx, cz)] = []
	var colours: Dictionary = _spec.get("colours", {})
	var rock_colours := _colours(colours.get("rock", ["77736a"]))
	var scrub_colours := _colours(colours.get("scrub", ["55633a"]))
	var crown_colours := _colours(colours.get("crown", ["46602f"]))
	var large_share := float(_spec.get("large_rock_share", 0.15))
	var scrub_size: Array = _spec.get("scrub_size", [0.6, 1.5])
	var scrub_lo := float(scrub_size[0])
	var scrub_hi := float(scrub_size[1])
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
					var s := lerpf(scrub_lo, scrub_hi, scale_roll)  # the preset's "scrub_size" [min, max], else 0.6..1.5
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


## The least foliage_between `from` and either of `to_a` and `to_b` (a head and a chest), with
## the foliage walked once for both lines (Spotting.foliage_m: two walks per pair in sight were
## a large share of an AI scan, research 2026-10-13 B2.6).
func foliage_least(from: Vector3, to_a: Vector3, to_b: Vector3) -> float:
	if _cells.is_empty():
		return 0.0
	var lo := _cell_of(minf(from.x, minf(to_a.x, to_b.x)) - FOLIAGE_PAD_M, minf(from.z, minf(to_a.z, to_b.z)) - FOLIAGE_PAD_M)
	var hi := _cell_of(maxf(from.x, maxf(to_a.x, to_b.x)) + FOLIAGE_PAD_M, maxf(from.z, maxf(to_a.z, to_b.z)) + FOLIAGE_PAD_M)
	var a := 0.0
	var b := 0.0
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				var kind := int(item.kind)
				if kind == Kind.ROCK:
					continue
				var p: Vector3 = item.pos
				if kind == Kind.SCRUB and Vector2(p.x - from.x, p.z - from.z).length() > SEE_SCRUB_M:
					continue  # as in foliage_between
				a += _through(item, kind, from, to_a)
				b += _through(item, kind, from, to_b)
	return minf(a, b)


## Metres of `item` (foliage of `kind`) the line `from` -> `to` passes through (foliage_between's
## test, for foliage_least).
static func _through(item: Dictionary, kind: int, from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.01:
		return 0.0
	var p: Vector3 = item.pos
	var size: Vector3 = item.size
	var r := size.x * (SCRUB_R if kind == Kind.SCRUB else CROWN_R)
	var c := Vector2(p.x - from.x, p.z - from.z)
	var along := c.dot(flat) / (flat_len * flat_len)
	var miss := (c - flat * along).length()
	if miss >= r:
		return 0.0
	var y0 := p.y + (0.0 if kind == Kind.SCRUB else size.y * CROWN_LOW)
	var y1 := p.y + size.y * (SCRUB_TOP if kind == Kind.SCRUB else CROWN_HIGH)
	var half_t := sqrt(r * r - miss * miss) / flat_len
	var t0 := maxf(along - half_t, 0.0)
	var t1 := minf(along + half_t, 1.0)
	var dy := to.y - from.y
	if absf(dy) < 0.0001:
		if from.y < y0 or from.y > y1:
			return 0.0
	else:
		var ta := (y0 - from.y) / dy
		var tb := (y1 - from.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return (t1 - t0) * from.distance_to(to) if t1 > t0 else 0.0


## Metres of foliage (scrub, and tree crowns) the straight line `from` -> `to` passes through,
## for spotting (Spotting.foliage_m). Each is a vertical cylinder about its mesh: scrub
## SCRUB_R x its width, up to SCRUB_TOP x its height; a crown CROWN_R x its size, from
## CROWN_LOW to CROWN_HIGH x its size up. Trunks and rocks are solid: rays see to those.
func foliage_between(from: Vector3, to: Vector3) -> float:
	if _cells.is_empty():
		return 0.0
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.01:
		return 0.0
	var lo := _cell_of(minf(from.x, to.x) - FOLIAGE_PAD_M, minf(from.z, to.z) - FOLIAGE_PAD_M)
	var hi := _cell_of(maxf(from.x, to.x) + FOLIAGE_PAD_M, maxf(from.z, to.z) + FOLIAGE_PAD_M)
	var length := from.distance_to(to)
	var dy := to.y - from.y
	var total := 0.0
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				var kind := int(item.kind)
				if kind == Kind.ROCK:
					continue
				var p: Vector3 = item.pos
				if kind == Kind.SCRUB and Vector2(p.x - from.x, p.z - from.z).length() > SEE_SCRUB_M:
					continue  # past where scrub is drawn it hides nobody (what players see is what counts)
				var size: Vector3 = item.size
				var r := size.x * (SCRUB_R if kind == Kind.SCRUB else CROWN_R)
				var y0 := p.y + (0.0 if kind == Kind.SCRUB else size.y * CROWN_LOW)
				var y1 := p.y + size.y * (SCRUB_TOP if kind == Kind.SCRUB else CROWN_HIGH)
				# The flat line against the circle: t runs 0..1 along it.
				var c := Vector2(p.x - from.x, p.z - from.z)
				var along := c.dot(flat) / (flat_len * flat_len)
				var miss := (c - flat * along).length()
				if miss >= r:
					continue
				var half_t := sqrt(r * r - miss * miss) / flat_len
				var t0 := maxf(along - half_t, 0.0)
				var t1 := minf(along + half_t, 1.0)
				# ...then its height (the line's y is linear in t).
				if absf(dy) < 0.0001:
					if from.y < y0 or from.y > y1:
						continue
				else:
					var ta := (y0 - from.y) / dy
					var tb := (y1 - from.y) / dy
					t0 = maxf(t0, minf(ta, tb))
					t1 = minf(t1, maxf(ta, tb))
				if t1 > t0:
					total += (t1 - t0) * length
	return total


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
		"trunk": _trunk_mesh(Color(String(colours.get("trunk", "4f3e2c")))),
		"crown": _crown_mesh(),
		"conifer": _conifer_mesh(),
		"tuft": _tuft_mesh(),
		"pebble": _blocky(Vector3(1, 1, 1), Color.WHITE, 0.3, 7, true),
		"outcrop": _blocky(Vector3(1, 1, 1), Color.WHITE, 0.26, 3, true),
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
	var groups := {Kind.ROCK: [], Kind.SCRUB: [], "trunk": [], "crown": [], "conifer": []}
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
				groups["conifer" if _is_conifer(item) else "crown"].append([xf, item.colour])
	_ground_cover(cell, groups)
	var ranges := {Kind.ROCK: SEE_ROCK_M, Kind.SCRUB: SEE_SCRUB_M, "trunk": SEE_TREE_M, "crown": SEE_TREE_M, "conifer": SEE_TREE_M,
		"tuft": SEE_TUFT_M, "pebble": SEE_PEBBLE_M, "outcrop": SEE_OUTCROP_M}
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
		var scrub: bool = (key is int and key == Kind.SCRUB) or key is String and key in ["tuft", "pebble"]  # keys mix Kind values and names
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if scrub else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)


## Grass tufts and pebbles for `cell` (visual only, see SEE_TUFT_M): from the cell and the seed,
## thicker where the scrub clusters, none on pads, roads, water or steep ground.
func _ground_cover(cell: Vector2i, groups: Dictionary) -> void:
	var tufts := mini(int(float(_spec.get("tufts_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6), CAP_TUFTS_PER_CELL)
	var pebbles := mini(int(float(_spec.get("pebbles_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6), CAP_TUFTS_PER_CELL)
	if tufts + pebbles == 0 and float(_spec.get("rock_clusters_per_km2", 0.0)) <= 0.0:
		return
	groups["tuft"] = []
	groups["pebble"] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _terrain.seed_value))
	var half := _terrain.size_m * 0.5
	var x0 := -half + cell.x * CELL_M
	var z0 := -half + cell.y * CELL_M
	var colours: Dictionary = _spec.get("colours", {})
	var tuft_colours := _colours(colours.get("tuft", colours.get("scrub", ["6f7040"])))
	var rock_colours := _colours(colours.get("rock", ["77736a"]))
	for n in tufts + pebbles:
		var pebble := n >= tufts
		var x := x0 + rng.randf() * CELL_M
		var z := z0 + rng.randf() * CELL_M
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf()
		var tint := rng.randf()
		if absf(x) > half - EDGE_KEEP_M or absf(z) > half - EDGE_KEEP_M:
			continue
		if not pebble and roll > clampf(_cluster.get_noise_2d(x * 3.0, z * 3.0) * 1.4 + 0.7, 0.15, 1.0):
			continue  # tufts in patches
		if _ground_blocked(x, z):
			continue
		var h := _terrain.height_at(x, z)
		if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.5:
			continue
		var nrm := _terrain.normal_at(x, z)
		if nrm.y < 0.82:
			continue
		var basis := Basis(Vector3.UP, yaw)
		if pebble:
			var size := lerpf(0.08, 0.32, s * s)
			var c: Color = rock_colours[int(tint * rock_colours.size()) % rock_colours.size()]
			groups["pebble"].append([Transform3D(basis.scaled(Vector3(size, size * 0.55, size * 1.2)), Vector3(x, h + size * 0.12, z)), c.darkened(tint * 0.15)])
		else:
			var size := lerpf(0.9, 1.8, s)
			var c: Color = tuft_colours[int(tint * tuft_colours.size()) % tuft_colours.size()]
			c = c.lerp(Color(c.r * 1.08, c.g * 1.05, c.b * 0.9), roll)  # some sun-bleached
			groups["tuft"].append([Transform3D(basis.scaled(Vector3(size, size * lerpf(0.8, 1.3, tint), size)), Vector3(x, h - 0.03, z)), c])
	# Rock clusters: a few half-buried stones round a bigger one (visual only, all under a
	# metre like the scatter's small rocks, which have no collision either).
	var clusters := int(float(_spec.get("rock_clusters_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6 + rng.randf())
	groups["outcrop"] = []
	for n in clusters:
		var cx := x0 + rng.randf() * CELL_M
		var cz := z0 + rng.randf() * CELL_M
		var stones := rng.randi_range(3, 7)
		if absf(cx) > half - EDGE_KEEP_M or absf(cz) > half - EDGE_KEEP_M or _ground_blocked(cx, cz):
			continue
		var ch := _terrain.height_at(cx, cz)
		if (_terrain.sea_side >= 0 and ch < _terrain.sea_level + 0.5) or _terrain.normal_at(cx, cz).y < 0.6:
			continue
		var base: Color = rock_colours[rng.randi() % rock_colours.size()]
		for k in stones:
			var a := rng.randf() * TAU
			var r := 0.0 if k == 0 else rng.randf_range(0.6, 2.6)
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			var size := rng.randf_range(0.55, 0.95) if k == 0 else rng.randf_range(0.2, 0.6)
			var squash := rng.randf_range(0.5, 0.8)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(cos(a), 0, sin(a)), rng.randf_range(-0.25, 0.25))
			var h := _terrain.height_at(x, z)
			groups["outcrop"].append([Transform3D(basis.scaled(Vector3(size, size * squash, size * rng.randf_range(0.8, 1.3))), Vector3(x, h + size * squash * 0.2, z)),
				base.darkened(rng.randf() * 0.12).lightened(rng.randf() * 0.08)])


## Whether ground cover keeps off (x, z): a pad or the line of a road.
func _ground_blocked(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for r in _keep:
		if r.grow(-PAD_KEEP_M + 2.0).has_point(p):
			return true
	for road: Array in _roads:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 4.0:
			return true
	return false


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


## Trees and scrub are built like the soldiers (VoxelArt lofts): stacked tiers with an
## octagonal cross-section (a square with its corners cut at 45 degrees), flat faces, light on
## top and darker underneath (the instance colour tints them). Scrub keeps inside the cylinder
## spotting hides people in (foliage_between: SCRUB_R, SCRUB_TOP); a crown's octagon corners and
## lobes reach out to about 1.45 x its size, past CROWN_R (as the old blocks' corners did), so its
## outer edge doesn't hide anyone (CROWN_LOW and CROWN_HIGH match it).
const TOP_SHADE := 1.0
const SIDE_SHADE := 0.82
const UNDER_SHADE := 0.6
## A tree's chance of being a conifer when its preset doesn't say ("scatter": "conifer_share").
const CONIFER_SHARE := 0.2


## Whether tree `item` is drawn as a conifer: its preset's share of them, picked by where it
## stands (the same every visit; the layout and its checksum don't change).
func _is_conifer(item: Dictionary) -> bool:
	var p: Vector3 = item.pos
	var roll := float(absi(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0)))) % 1000) / 1000.0
	return roll < float(_spec.get("conifer_share", CONIFER_SHARE))


## One tier: an octagonal frustum from y0 (half-width r0) to y1 (r1), centred on (cx, cz),
## with flat top and bottom.
func _tier(st: SurfaceTool, cx: float, cz: float, y0: float, y1: float, r0: float, r1: float, tint := Color.WHITE) -> void:
	var ring := func(y: float, r: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		var c := r * 0.7  # the 45-degree cut leaves 0.7 of each side (VoxelArt bevel 0.3)
		for v: Vector2 in [Vector2(c, -r), Vector2(r, -c), Vector2(r, c), Vector2(c, r), Vector2(-c, r), Vector2(-r, c), Vector2(-r, -c), Vector2(-c, -r)]:
			out.append(Vector3(cx + v.x, y, cz + v.y))
		return out
	var lo: Array[Vector3] = ring.call(y0, r0)
	var hi: Array[Vector3] = ring.call(y1, r1)
	var mid := Vector3(cx, (y0 + y1) * 0.5, cz)
	for i in 8:
		var j := (i + 1) % 8
		_face(st, [lo[i], lo[j], hi[j], hi[i]], mid, tint * SIDE_SHADE)
	for i in range(1, 7):
		_face(st, [hi[0], hi[i], hi[i + 1]], mid, tint * TOP_SHADE)
		_face(st, [lo[0], lo[i + 1], lo[i]], mid, tint * UNDER_SHADE)


## A flat face through `points` (3 or 4, in order), turned to face away from `inside`.
func _face(st: SurfaceTool, points: Array, inside: Vector3, colour: Color, up_normal := false) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var n := (b - a).cross(c - a).normalized()
	var centre := Vector3.ZERO
	for q: Vector3 in points:
		centre += q / points.size()
	var flip := n.dot(centre - inside) < 0.0
	if flip:
		n = -n
	colour.a = 1.0
	var tris := [[0, 1, 2]] if points.size() == 3 else [[0, 1, 2], [0, 2, 3]]
	for t: Array in tris:
		# Godot wants clockwise seen from outside.
		var order: Array = [t[0], t[2], t[1]] if not flip else [t[0], t[1], t[2]]
		for k: int in order:
			st.set_color(colour)
			st.set_normal(Vector3.UP if up_normal else n)  # grass: lit like the ground it stands on
			st.add_vertex(points[k])


## Scrub: four small octagonal clumps on the ground, the middle one tallest (within SCRUB_R,
## up to SCRUB_TOP of its height).
func _scrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Array in [[0.0, 0.0, 0.26, 0.58], [0.2, 0.1, 0.18, 0.42], [-0.17, 0.14, 0.17, 0.38], [0.03, -0.21, 0.16, 0.34]]:
		var r: float = c[2]
		var h: float = c[3]
		_tier(st, c[0], c[1], 0.0, h * 0.7, r * 0.75, r)
		_tier(st, c[0], c[1], h * 0.7, h, r, r * 0.55)
	return st.commit()


## A grass tuft: five thin four-sided blades from a 0.25 m clump, leaning out, up to 0.45 m.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4 * (k % 2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var foot := out * (0.05 + 0.04 * (k % 3))
		var tip := out * (0.12 + 0.05 * (k % 2)) + Vector3(0, 0.30 + 0.05 * (k % 3), 0)
		var w := 0.035
		var side := out.cross(Vector3.UP) * w
		var b := [foot + side, foot + out * w, foot - side, foot - out * w]
		var inside := foot + (tip - foot) * 0.25
		for i in 4:
			var shade := TOP_SHADE if i % 2 == 0 else SIDE_SHADE
			_face(st, [b[i], b[(i + 1) % 4], tip], inside, Color.WHITE * lerpf(shade, 1.0, 0.3), true)
	return st.commit()


## A broadleaf crown: a rounded blob of four tiers from 2 m up (the trunk's top) to 4.9 m.
func _crown_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[2.0, 2.55, 0.65, 1.05], [2.55, 3.45, 1.05, 1.1], [3.45, 4.3, 1.1, 0.85], [4.3, 4.9, 0.85, 0.35]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3])
	# Two lobes out to the sides break the outline (within CROWN_R of the middle, about).
	_tier(st, 0.72, 0.18, 2.55, 3.15, 0.45, 0.6)
	_tier(st, 0.72, 0.18, 3.15, 3.75, 0.6, 0.3)
	_tier(st, -0.45, -0.62, 3.25, 3.85, 0.42, 0.55)
	_tier(st, -0.45, -0.62, 3.85, 4.4, 0.55, 0.25)
	return st.commit()


## A conifer: three stacked tiers, each narrower, from 2 m up to 4.9 m.
func _conifer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[2.0, 3.0, 1.15, 0.7], [2.8, 3.9, 0.9, 0.45], [3.7, 4.9, 0.6, 0.06]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3])
	return st.commit()


## The trunk: an octagonal post, a little narrower at the top, 2.6 m tall (into the crown).
func _trunk_mesh(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 0.0, 2.6, 0.19, 0.14, colour / SIDE_SHADE)
	return st.commit()
