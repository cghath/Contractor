class_name GroundCuts
extends Node3D
## The ground, cut (Captain, 2026-10-19: the terrain manipulation system, "explosion craters"
## then "real foxholes and trenches"). ZoneTerrain's ground is a 4 m height grid, too coarse to
## dent a crater into, so wherever something cuts the ground this lays a fine grid over it:
## FINE x FINE quads a cell (0.25 m, the size of the blocks the ground and the voxel walls are
## drawn in), each tile its own height-field collision, drawn merged with the other tiles in its
## BLOCK_CELLS x BLOCK_CELLS block (one draw call a block, however many craters a fight leaves).
##
## How the two fit: the cut cells' corner samples are blanked in the coarse collision (a NaN
## sample is a hole in a Jolt height field: every triangle touching it goes), which takes those
## cells and part of the ring of cells round them, so the fine tiles cover the cut cells and
## that ring, and the coarse ground's finest mesh leaves out the same cells (ZoneTerrain
## _chunk_mesh). A fine tile's heights are the coarse ground's own (ZoneTerrain.plane_height: its
## vertices lie on the coarse triangles, split the same way) plus what the cuts took (or threw
## up): an undug tile is the coarse ground exactly, so no seam shows. Cuts only change the cut
## cells, never the ring.
##
## Every peer: Digging sends each cut (an op) to all, and to late joiners. apply(op) is
## deterministic. ZoneTerrain.height_at reads the cut heights (cut_height) inside cut cells, so
## spawns, the grass and everything that stands on the ground stand in the crater.

const NODE_NAME := "GroundCuts"
const FINE := 16
const FINE_M := ZoneTerrain.CELL_M / FINE
const BLOCK_CELLS := 8
## Deepest a pile of cuts goes (m below the ground as it was).
const MAX_DEPTH_M := 2.5
## A crater from a blast of radius r (Digging.server_blast): CRATER_SCALE x r across (at least
## CRATER_MIN_M, at most CRATER_MAX_M), CRATER_DEPTH x its radius deep, a lip thrown up round it
## out to CRATER_LIP x its radius, LIP_SHARE of its depth high. Proposed.
const CRATER_SCALE := 1.2
const CRATER_MIN_M := 0.4
const CRATER_MAX_M := 4.0
const CRATER_DEPTH := 0.35
const CRATER_LIP := 1.6
const LIP_SHARE := 0.25
## Scorch: how far out (x the crater's radius) the soil darkens, and to what.
const SCORCH_REACH := 1.35
## A dug pit (Digging, dig phase 3: foxholes and trenches): PIT_HALF_W across and PIT_AHEAD_M /
## PIT_BEHIND_M along the way the digger faces from where he kneels, its walls sloping in over
## PIT_EDGE_M; each dig takes it to the next of PIT_STAGES_M (a prone scrape, kneeling, standing).
## Digging on from inside one, facing on, makes it a trench. Proposed.
const PIT_HALF_W := 0.6
const PIT_AHEAD_M := 0.7
const PIT_BEHIND_M := 0.9
const PIT_EDGE_M := 0.3
const PIT_STAGES_M: Array[float] = [0.45, 0.9, 1.4]
const SCORCH := Color("33281d")
const SCORCH_MAX := 0.7
## Ground this scorched or dug grows no grass (bare).
const BARE_FROM := 0.25

var terrain: ZoneTerrain
## Cut cells (Vector2i coarse cell -> true): their corners are holes in the coarse collision.
var cut := {}
## Fine vertex (Vector2i, global fine index) -> metres added to the coarse ground (- dug, + piled).
var delta := {}
## Fine vertex -> scorch 0..1.
var scorch := {}
## Fine vertex -> fresh earth 0..1 (dug or thrown up).
var earth := {}
var _tiles := {}  # coarse cell -> [StaticBody3D, its heights (PackedFloat32Array)]
var _blocks := {}  # Vector2i block -> MeshInstance3D drawing its tiles
var _dirty := {}  # blocks to redraw
## Counts up with every cut (GrassCarpet re-lays when it changes).
var version := 0


static func of(t: ZoneTerrain) -> GroundCuts:
	var g := t.get_node_or_null(NODE_NAME) as GroundCuts
	if g == null:
		g = GroundCuts.new()
		g.name = NODE_NAME
		g.terrain = t
		t.add_child(g)
		t.cuts = g
	return g


## Cells drawn fine (cut cells and the ring round them): the coarse mesh leaves these out.
func covers(cell: Vector2i) -> bool:
	return _tiles.has(cell)


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + terrain._half) / ZoneTerrain.CELL_M), floori((z + terrain._half) / ZoneTerrain.CELL_M))


## A crater op for a blast of radius `radius_m` at `pos`.
static func crater_op(pos: Vector3, radius_m: float) -> Dictionary:
	var r := clampf(radius_m * CRATER_SCALE, CRATER_MIN_M, CRATER_MAX_M)
	return {"kind": "crater", "x": pos.x, "z": pos.z, "r": r, "depth": r * CRATER_DEPTH}


## Applies one cut. Returns false if it was off the ground grid.
func apply(op: Dictionary) -> bool:
	match String(op.get("kind", "")):
		"crater":
			return _crater(float(op.x), float(op.z), float(op.r), float(op.depth))
		"pit":
			return _pit(float(op.x), float(op.z), float(op.yaw), float(op.depth))
	return false


func _crater(x: float, z: float, r: float, depth: float) -> bool:
	var reach := r * maxf(CRATER_LIP, SCORCH_REACH)
	if not _cut_area(Rect2(x - reach, z - reach, reach * 2.0, reach * 2.0)):
		return false
	var lo := _fine_index(x - reach, z - reach)
	var hi := _fine_index(x + reach, z + reach) + Vector2i.ONE
	for fj in range(lo.y, hi.y + 1):
		for fi in range(lo.x, hi.x + 1):
			var f := Vector2i(fi, fj)
			var p := _fine_pos(f)
			var d := Vector2(p.x - x, p.y - z).length() / r
			var add := 0.0
			if d < 1.0:
				add = -depth * (1.0 - d * d)
			elif d < CRATER_LIP:
				add = depth * LIP_SHARE * sin(PI * (d - 1.0) / (CRATER_LIP - 1.0))
			if add != 0.0:
				delta[f] = maxf(float(delta.get(f, 0.0)) + add, -MAX_DEPTH_M)
				earth[f] = maxf(float(earth.get(f, 0.0)), clampf(1.2 - absf(d - 1.0) * 1.5, 0.3, 1.0))
			if d < SCORCH_REACH:
				scorch[f] = maxf(float(scorch.get(f, 0.0)), clampf((SCORCH_REACH - d) / SCORCH_REACH * 1.4, 0.0, SCORCH_MAX))
	_rebuild_around(Rect2(x - reach, z - reach, reach * 2.0, reach * 2.0))
	version += 1
	return true


## Whether the ground at (x, z) is scorched or dug bare (no grass grows there).
func bare(x: float, z: float) -> bool:
	if not cut.has(cell_of(x, z)):
		return false
	var f := Vector2i(roundi((x + terrain._half) / FINE_M), roundi((z + terrain._half) / FINE_M))
	return maxf(float(scorch.get(f, 0.0)), float(earth.get(f, 0.0))) >= BARE_FROM


## How deep the ground at (x, z) is dug below the ground as it was (0 if it isn't).
func dug_depth(x: float, z: float) -> float:
	return maxf(0.0, terrain.plane_height(x, z) - terrain.height_at(x, z)) if cut.has(cell_of(x, z)) else 0.0


## The depth the next dig at (x, z) takes the ground to (the next PIT_STAGES_M past how deep it
## is already), or 0 if it's as deep as it goes.
static func next_stage(depth: float) -> float:
	for d in PIT_STAGES_M:
		if d > depth + 0.1:
			return d
	return 0.0


## A pit op: dug from (pos), facing `yaw` (the digger's), to `depth`.
static func pit_op(pos: Vector3, yaw: float, depth: float) -> Dictionary:
	return {"kind": "pit", "x": pos.x, "z": pos.z, "yaw": yaw, "depth": depth}


func _pit(x: float, z: float, yaw: float, depth: float) -> bool:
	var reach := PIT_AHEAD_M + PIT_EDGE_M + 0.5
	var area := Rect2(x - reach, z - reach, reach * 2.0, reach * 2.0)
	if not _cut_area(area):
		return false
	var fwd := Vector2(-sin(yaw), -cos(yaw))  # the way he faces (-Z at yaw 0)
	var side := Vector2(fwd.y, -fwd.x)
	var lo := _fine_index(area.position.x, area.position.y)
	var hi := _fine_index(area.end.x, area.end.y) + Vector2i.ONE
	for fj in range(lo.y, hi.y + 1):
		for fi in range(lo.x, hi.x + 1):
			var f := Vector2i(fi, fj)
			var p := _fine_pos(f) - Vector2(x, z)
			var along := p.dot(fwd)
			var across := absf(p.dot(side))
			# How far inside the pit's box (m): its floor where that's past PIT_EDGE_M, its walls in between.
			var inside := minf(PIT_HALF_W - across, minf(PIT_AHEAD_M - along, along + PIT_BEHIND_M))
			if inside <= 0.0:
				continue
			var want := -depth * clampf(inside / PIT_EDGE_M, 0.0, 1.0)
			if want < float(delta.get(f, 0.0)):
				delta[f] = maxf(want, -MAX_DEPTH_M)
			earth[f] = 1.0
	_rebuild_around(area)
	version += 1
	return true


## Cuts every cell `area` touches (holes in the coarse collision, fine tiles over them and their
## ring, the coarse mesh's finest level rebuilt without them). False if it's off the grid.
func _cut_area(area: Rect2) -> bool:
	var a := cell_of(area.position.x, area.position.y)
	var b := cell_of(area.end.x, area.end.y)
	if a.x < 1 or a.y < 1 or b.x > terrain.points - 3 or b.y > terrain.points - 3:
		return false  # the ring must stay on the grid
	var fresh: Array[Vector2i] = []
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			var c := Vector2i(i, j)
			if not cut.has(c):
				cut[c] = true
				fresh.append(c)
	if fresh.is_empty():
		return true
	var holes: Array[Vector2i] = []
	var chunks := {}
	for c in fresh:
		for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			holes.append(c + k)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var n := c + Vector2i(di, dj)
				if not _tiles.has(n):
					_tiles[n] = [null, null]
					chunks[Vector2i(n.x / ZoneTerrain.CHUNK_CELLS, n.y / ZoneTerrain.CHUNK_CELLS)] = true
	terrain.blank_samples(holes)
	for ch: Vector2i in chunks:
		terrain.rebuild_fine_chunk(ch)
	return true


## Rebuilds the tiles `area` reaches (and any not built yet).
func _rebuild_around(area: Rect2) -> void:
	var a := cell_of(area.position.x, area.position.y) - Vector2i.ONE
	var b := cell_of(area.end.x, area.end.y) + Vector2i.ONE
	for c: Vector2i in _tiles:
		var t: Array = _tiles[c]
		if t[0] == null or (c.x >= a.x and c.x <= b.x and c.y >= a.y and c.y <= b.y):
			_build_tile(c)
	_redraw()


func _fine_index(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + terrain._half) / FINE_M), floori((z + terrain._half) / FINE_M))


func _fine_pos(f: Vector2i) -> Vector2:
	return Vector2(f.x * FINE_M - terrain._half, f.y * FINE_M - terrain._half)


## The ground's height at fine vertex `f`: the coarse ground's plus the cuts'.
func fine_height(f: Vector2i) -> float:
	var p := _fine_pos(f)
	return terrain.plane_height(p.x, p.y) + float(delta.get(f, 0.0))


## The ground's height at (x, z) inside a cut cell, on the fine mesh (its quads split as the
## coarse ones are, from their (1, 0) corner to their (0, 1) corner).
func cut_height(x: float, z: float) -> float:
	var gx := (x + terrain._half) / FINE_M
	var gz := (z + terrain._half) / FINE_M
	var i := floori(gx)
	var j := floori(gz)
	var fx := gx - i
	var fz := gz - j
	var h10 := fine_height(Vector2i(i + 1, j))
	var h01 := fine_height(Vector2i(i, j + 1))
	if fx + fz <= 1.0:
		var h00 := fine_height(Vector2i(i, j))
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	var h11 := fine_height(Vector2i(i + 1, j + 1))
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func _build_tile(c: Vector2i) -> void:
	var t: Array = _tiles[c]
	if t[0] != null:
		(t[0] as Node).queue_free()
	var f0 := c * FINE
	var n := FINE + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			data[i + j * n] = fine_height(f0 + Vector2i(i, j))
	var body := StaticBody3D.new()
	body.name = "Cut_%d_%d" % [c.x, c.y]
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = data
	var node := CollisionShape3D.new()
	node.shape = shape
	node.scale = Vector3(FINE_M, 1.0, FINE_M)
	body.add_child(node)
	var centre := _fine_pos(f0) + Vector2.ONE * ZoneTerrain.CELL_M * 0.5
	body.position = Vector3(centre.x, 0.0, centre.y)
	add_child(body)
	t[0] = body
	t[1] = data
	_dirty[Vector2i(c.x / BLOCK_CELLS, c.y / BLOCK_CELLS)] = true


## Redraws the blocks whose tiles changed: each one mesh of all its tiles (world x, z).
func _redraw() -> void:
	if not terrain._visuals_built:
		_dirty.clear()
		return
	for blk: Vector2i in _dirty:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		for j in BLOCK_CELLS:
			for i in BLOCK_CELLS:
				var c := blk * BLOCK_CELLS + Vector2i(i, j)
				if _tiles.has(c) and _tiles[c][1] != null:
					_append_tile(c, _tiles[c][1], verts, normals, colours, indices)
		var node: MeshInstance3D = _blocks.get(blk)
		if node == null:
			node = MeshInstance3D.new()
			node.name = "Block_%d_%d" % [blk.x, blk.y]
			node.material_override = terrain._material
			node.visibility_range_end = ZoneTerrain.LOD_END_M[0]
			node.visibility_range_end_margin = 20.0
			add_child(node)
			_blocks[blk] = node
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		node.mesh = mesh
	_dirty.clear()


func _append_tile(c: Vector2i, data: PackedFloat32Array, verts: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array) -> void:
	var n := FINE + 1
	var f0 := c * FINE
	var first := verts.size()
	var corner := [terrain.vertex_colour(c.x, c.y), terrain.vertex_colour(c.x + 1, c.y),
		terrain.vertex_colour(c.x, c.y + 1), terrain.vertex_colour(c.x + 1, c.y + 1)]
	var cn := [terrain.vertex_normal(c.x, c.y), terrain.vertex_normal(c.x + 1, c.y),
		terrain.vertex_normal(c.x, c.y + 1), terrain.vertex_normal(c.x + 1, c.y + 1)]
	var dirt: Color = terrain.c_earth
	for j in n:
		for i in n:
			var f := f0 + Vector2i(i, j)
			var p := _fine_pos(f)
			verts.append(Vector3(p.x, data[i + j * n], p.y))
			var fx := float(i) / FINE
			var fz := float(j) / FINE
			var base: Color = _tri(corner, fx, fz)
			var coarse_n: Vector3 = _tri(cn, fx, fz)
			# The coarse normal tilted by the cuts' own slope, so an undug tile shades as the coarse ground.
			var ddx := (float(delta.get(f + Vector2i(1, 0), 0.0)) - float(delta.get(f - Vector2i(1, 0), 0.0))) / (2.0 * FINE_M)
			var ddz := (float(delta.get(f + Vector2i(0, 1), 0.0)) - float(delta.get(f - Vector2i(0, 1), 0.0))) / (2.0 * FINE_M)
			var sx := -coarse_n.x / maxf(coarse_n.y, 0.05) + ddx
			var sz := -coarse_n.z / maxf(coarse_n.y, 0.05) + ddz
			normals.append(Vector3(-sx, 1.0, -sz).normalized())
			var dug := float(earth.get(f, 0.0))
			var colour := base.lerp(dirt, dug * 0.85).lerp(SCORCH, float(scorch.get(f, 0.0)))
			colour.a = 1.0 - dug  # dug earth: the ground shader paints no rock on it
			colours.append(colour)
	for b in FINE:
		for a in FINE:
			var p := first + a + b * n
			indices.append_array([p, p + 1, p + n, p + 1, p + n + 1, p + n])  # clockwise from above, as the coarse chunks


## A value across a coarse cell from its corners [00, 10, 01, 11], split as the cell's triangles are.
static func _tri(v: Array, fx: float, fz: float) -> Variant:
	if fx + fz <= 1.0:
		return v[0] + (v[1] - v[0]) * fx + (v[2] - v[0]) * fz
	return v[3] + (v[2] - v[3]) * (1.0 - fx) + (v[1] - v[3]) * (1.0 - fz)
