class_name VoxelWorld
extends Node3D
## Destructible structures made of 10 cm voxels. Every peer builds the same base structures
## locally, then applies the host's ordered edit log, so only small edit events cross the
## network, and the same log is what gets saved.
##
## Every voxel has a material (Mat, MATERIALS): rounds go through wood and sheet metal
## (carving a hole the size of the voxels they pass) and stop in concrete, steel or deep
## enough stacks, leaving only a small impact mark there (Ballistics, trace_round). Blasts
## take out each material within its own share of the radius (server_blast).
##
## The host checks every carve for a breach, a gap a soldier now fits through, and reports
## it with `breached` so the navigation around it is rebaked (NavBuilder).
##
## There is no voxel stream yet, so a block that unloads would come back without its
## edits: keep BOUNDS small enough that viewers always cover all of it.

signal structures_built
## Host only. Carving opened a gap in a structure that a soldier fits through; `area_m` is
## the gap (this node's space, metres). NavBuilder rebakes the navigation around it.
signal breached(area_m: AABB)

const VOXEL_SIZE := 0.1
## World materials, set by the structure that places the voxels (add_box_m). PAINTED is
## painted concrete; STEEL is thick steel (stops rounds like concrete); SHEET_METAL is thin
## sheet (a container's walls, a roof); SANDBAG is filled sandbags or packed earth.
## Append new materials at the end: edit logs and saves store these values.
## MUD_BRICK to DIRT_BERM come from the faction pack's worldspace material registry (colours
## only so far: without a MATERIALS entry they stop rounds like concrete).
enum Mat {
	EMPTY, CONCRETE, PAINTED, WOOD, STEEL,
	MUD_BRICK, STONE, LIMESTONE, BASALT, TUFF, CORAL_STONE, BRICK, CINDER_BLOCK, PLASTER,
	ROOF_TILE, FIBRE_CEMENT, CORRUGATED_IRON, THATCH, TARP, GLASS, SANDBAG, HESCO, DIRT_BERM,
	SHEET_METAL,
}
## One colour per Mat, in the same order. Index 0 must stay transparent: the cubes mesher
## treats it as empty.
const PALETTE: Array[Color] = [
	Color(0, 0, 0, 0), Color("8a8577"), Color("5f6b58"), Color("8c6a46"), Color("4a4d50"),
	Color("a47e57"), Color("8f8676"), Color("d6caa8"), Color("4b4845"), Color("c48a6a"),
	Color("cbbf9f"), Color("9c5a3c"), Color("9a978f"), Color("e3dccb"), Color("a4553b"),
	Color("a5a49c"), Color("8b8e8c"), Color("b49a5e"), Color("3f6d8c"), Color("9fbcc4"),
	Color("b8a378"), Color("a99a6c"), Color("8a6f4e"),
	Color("7b8a8c"),
]
## How each material takes fire (Ballistics walks a round through the voxels, trace_round):
## - "loss_j_per_m": energy a round loses per metre of it. INF stops every small-arms round:
##   no hole, only a small surface mark (server_mark). A round that runs out of energy inside
##   any material stops there with a mark too; one that gets through carves the voxels it
##   passed (server_holes) and carries on with what it has left.
## - "blast": share of a blast's radius (server_blast) that takes this material out.
## - "mark": colour of the impact mark a stopped round leaves.
## Proposed values against data/rounds.json (M855 about 1650 J at the muzzle, 9 mm about
## 550 J, M80 about 3350 J): a 10 cm wood wall costs 250 J (a 9 mm gets through two), 66 cm
## of wood stops an M855 and 1.4 m an M80 (a crate stack), a sheet-metal wall costs 150 J,
## 40 cm of sandbags stops anything, concrete and steel stop everything.
const MATERIALS := {
	Mat.CONCRETE: {"name": "concrete", "loss_j_per_m": INF, "blast": 0.4, "mark": Color("3b3935")},
	Mat.PAINTED: {"name": "painted concrete", "loss_j_per_m": INF, "blast": 0.4, "mark": Color("3b3935")},
	Mat.WOOD: {"name": "wood", "loss_j_per_m": 2500.0, "blast": 1.0, "mark": Color("2e2014")},
	Mat.STEEL: {"name": "steel", "loss_j_per_m": INF, "blast": 0.15, "mark": Color("b9bcbf")},
	Mat.SHEET_METAL: {"name": "sheet metal", "loss_j_per_m": 1500.0, "blast": 1.0, "mark": Color("1d2022")},
	Mat.SANDBAG: {"name": "sandbags", "loss_j_per_m": 12000.0, "blast": 0.6, "mark": Color("54472f")},
}
## Impact marks: a stopped round leaves a small crack or chip on the surface (MARK_SIZE_M
## across, nothing carved), kept in the edit log like any other edit. The host records at
## most MARKS_PER_VOXEL in one surface voxel (sustained fire on one spot doesn't grow the
## log), and only the newest MAX_MARKS are shown. A mark goes when its voxel is carved away.
const MARK_SIZE_M := 0.05
const MARKS_PER_VOXEL := 6
const MAX_MARKS := 8192
## trace_round: a round walks at most WALK_MAX_M through solid voxels (deeper counts as
## stopped), and looks SEEK_M past where the collider said it hit for the first solid voxel
## (the collider can lag a fresh hole by a frame or two).
const WALK_MAX_M := 4.0
const SEEK_M := 0.25
## Edit area, in voxels.
const BOUNDS := AABB(Vector3(-220, -8, -220), Vector3(440, 56, 440))
## Viewer range, in voxels. Must reach every corner of BOUNDS from anywhere players go.
const VIEW_DISTANCE := 640
## Breach detection (host, after every carve, see _check_breaches). A soldier (NavBuilder's
## agent: radius 0.25 m, height 1.75 m) fits through where a column that used to be wall
## has clear columns BREACH_HALF_WIDTH either side (0.5 m wide in all), clear from
## BREACH_FLOOR (lower rubble is stepped over: agent_max_climb is 0.25 m) up to
## BREACH_TOP. Voxels, measured from the ground. A bullet hole is far too small, so bullet
## holes never count; checks run at most every BREACH_CHECK_S.
const BREACH_HALF_WIDTH := 2
const BREACH_FLOOR := 2
const BREACH_TOP := 18
const BREACH_CHECK_S := 0.25

var terrain: VoxelTerrain
var _tool: VoxelTool
var _structures: Array = []  # [begin: Vector3i, end: Vector3i, mat]
var _structure_area := AABB()
var _built := false
var _pending: Array = []
var _dirty: Array[AABB] = []  # host: carved voxel boxes not checked for breaches yet
var _breached := {}           # host: Vector2i columns already reported as part of a gap
var _next_breach_check := 0.0
## Impact marks, oldest first: serial -> [position, normal (voxel units, terrain space), Mat,
## the surface voxel it sits on]. Every peer builds the same from the edit log.
var _marks := {}
var _mark_serial := 0
var _mark_cells := {}  # surface voxel (Vector3i) -> Array of mark serials on it
var _marks_dirty := false
var _mark_mesh: MultiMeshInstance3D


static func find_on(node: Object) -> VoxelWorld:
	var n := node as Node
	while n:
		if n is VoxelWorld:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	terrain = VoxelTerrain.new()
	terrain.name = "Terrain"
	terrain.scale = Vector3.ONE * VOXEL_SIZE
	var generator := VoxelGeneratorFlat.new()
	generator.channel = VoxelBuffer.CHANNEL_COLOR
	generator.height = -1000.0  # all air: ground is a plain collider, voxels are for structures
	terrain.generator = generator
	var palette := VoxelColorPalette.new()
	for i in PALETTE.size():
		palette.set_color(i, PALETTE[i])
	var mesher := VoxelMesherCubes.new()
	mesher.palette = palette
	mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
	terrain.mesher = mesher
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true  # palette colours are authored in sRGB
	material.roughness = 0.9
	terrain.material_override = material
	terrain.bounds = BOUNDS
	terrain.max_view_distance = VIEW_DISTANCE
	terrain.collision_layer = 1
	add_child(terrain)
	_tool = terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_COLOR
	add_to_group(&"voxel_worlds")
	_mark_mesh = _make_mark_mesh()
	terrain.add_child(_mark_mesh)  # in the terrain's space: voxel units


## Adds a solid box, in metres, relative to this node. Call before structures are built.
func add_box_m(from_m: Vector3, to_m: Vector3, mat: Mat) -> void:
	var a := Vector3i((from_m / VOXEL_SIZE).round())
	var b := Vector3i((to_m / VOXEL_SIZE).round())
	_structures.append([a.min(b), a.max(b) - Vector3i.ONE, mat])
	var box := AABB(Vector3(a.min(b)), Vector3((a - b).abs()))
	_structure_area = box if _structures.size() == 1 else _structure_area.merge(box)


func is_built() -> bool:
	return _built


## The base structures as boxes in metres, in this node's space (for navigation baking).
func structure_boxes_m() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for s: Array in _structures:
		var begin := Vector3(s[0]) * VOXEL_SIZE
		var end := Vector3(s[1] + Vector3i.ONE) * VOXEL_SIZE
		boxes.append(AABB(begin, end - begin))
	return boxes


func _process(_delta: float) -> void:
	if _built:
		_check_breaches()
		return
	if _structures.is_empty():
		return
	# Blocks only exist once a VoxelViewer (on a player) has loaded them.
	if not _tool.is_area_editable(_structure_area):
		return
	_tool.mode = VoxelTool.MODE_SET
	for s: Array in _structures:
		_tool.value = s[2]
		_tool.do_box(s[0], s[1])
	_built = true
	set_process(not _dirty.is_empty())
	for edit: Dictionary in _pending:
		_apply(edit)  # saved or early edits: the host checks them for breaches too
	_pending.clear()
	print("[world] voxel structures built (%d boxes)" % _structures.size())
	structures_built.emit()


## Host only. Removes a sphere of voxels of any material around a world-space point.
func server_carve(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	_server_edit({"op": "carve", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE})


## Host only. A blast (a frag) at a world-space point: takes out each material within its
## share of `radius_m` (MATERIALS "blast"), so wood and sheet metal go and concrete chips.
func server_blast(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	_server_edit({"op": "blast", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE})


## Host only. Clears single voxels (voxel coordinates, as trace_round gives them): the hole
## a round made going through.
func server_holes(voxels: Array) -> void:
	if voxels.is_empty():
		return
	var flat: Array = []
	for v: Vector3i in voxels:
		flat.append_array([v.x, v.y, v.z])
	_server_edit({"op": "holes", "v": flat})


## Host only. A small impact mark (a crack or chip, nothing carved) where a round stopped on
## the surface at `world_position` facing `normal`, in `mat`'s colour. Returns false when the
## surface voxel there already has MARKS_PER_VOXEL marks (nothing is recorded).
func server_mark(world_position: Vector3, normal: Vector3, mat: int) -> bool:
	var p := terrain.to_local(world_position)
	var n := (terrain.global_basis.inverse() * normal).normalized()
	if n.is_zero_approx():
		n = Vector3.UP
	if (_mark_cells.get(_mark_cell(p, n), []) as Array).size() >= MARKS_PER_VOXEL:
		return false
	_server_edit({"op": "mark", "p": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)],
		"n": [snappedf(n.x, 0.001), snappedf(n.y, 0.001), snappedf(n.z, 0.001)], "m": mat})
	return true


func _server_edit(edit: Dictionary) -> void:
	GameState.voxel_edits.append(edit)
	apply_edit.rpc(edit)


## How many impact marks there are (every peer has the same).
func mark_count() -> int:
	return _marks.size()


## How many impact marks lie within `radius_m` of a world-space point.
func marks_near(world_position: Vector3, radius_m: float) -> int:
	var p := terrain.to_local(world_position)
	var r := radius_m / VOXEL_SIZE
	var count := 0
	for serial: int in _marks:
		if (_marks[serial][0] as Vector3).distance_to(p) <= r:
			count += 1
	return count


## The material of the voxel at a world-space point (Mat.EMPTY for air or unloaded voxels).
func material_at(world_position: Vector3) -> int:
	var v := Vector3i(terrain.to_local(world_position).floor())
	if not is_area_readable(AABB(Vector3(v), Vector3.ONE)):
		return Mat.EMPTY
	return _tool.get_voxel(v)


## Energy (J) a round loses per metre of material `mat`: INF for what stops every
## small-arms round (concrete, steel, and anything unknown).
static func loss_per_m(mat: int) -> float:
	return float((MATERIALS.get(mat, {}) as Dictionary).get("loss_j_per_m", INF))


## Host only. Walks a round into the voxels from `entry` (world space, where its ray met a
## structure) along `direction` with `energy_j` joules. Returns:
## - "stopped": it ran out of energy inside (or the material stops everything, or it's
##   deeper than WALK_MAX_M, or the voxels aren't loaded);
## - "material": the first solid voxel's material (Mat.EMPTY if none was found);
## - "voxels": the voxels it passed through (empty when stopped: a stop makes no hole);
## - "exit": where it came out (world space), past the last solid voxel;
## - "lost_j": the energy it lost.
## A stretch of solid voxels ends at the first empty one; whatever is behind is a separate
## hit for the ray.
func trace_round(entry: Vector3, direction: Vector3, energy_j: float) -> Dictionary:
	var result := {"stopped": false, "material": Mat.EMPTY, "voxels": [], "exit": entry, "lost_j": 0.0}
	var dir := terrain.global_basis.inverse() * direction
	var units_per_m := dir.length()
	if units_per_m <= 0.0:
		result.stopped = true
		return result
	dir /= units_per_m
	var start := terrain.to_local(entry) + dir * 0.01
	var max_t := WALK_MAX_M * units_per_m
	var reach := AABB(start, Vector3.ZERO).expand(start + dir * max_t).grow(1.0)
	if not is_area_readable(reach):
		result.stopped = true
		result.material = Mat.CONCRETE
		return result
	var cell := Vector3i(start.floor())
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for axis in 3:
		if dir[axis] > 0.0:
			t_max[axis] = (cell[axis] + 1 - start[axis]) / dir[axis]
			t_delta[axis] = 1.0 / dir[axis]
		elif dir[axis] < 0.0:
			t_max[axis] = (start[axis] - cell[axis]) / -dir[axis]
			t_delta[axis] = -1.0 / dir[axis]
		else:
			t_max[axis] = INF
			t_delta[axis] = INF
	var seek_t := SEEK_M * units_per_m
	var remaining := energy_j
	var inside := false
	var t := 0.0
	var passed: Array[Vector3i] = []
	while t < max_t:
		var t_next := minf(t_max.x, minf(t_max.y, t_max.z))
		var mat := int(_tool.get_voxel(cell))
		if mat != Mat.EMPTY:
			if not inside:
				inside = true
				result.material = mat
			var per_m := loss_per_m(mat)
			var loss := per_m * maxf(t_next - t, 0.0) / units_per_m if per_m != INF else INF
			if loss >= remaining:
				result.stopped = true
				result.lost_j = maxf(energy_j, 0.0)
				return result
			remaining -= loss
			passed.append(cell)
		elif inside or t > seek_t:
			# Out the far side (or nothing solid here: a hole the collider hasn't caught up with).
			result.voxels = passed
			result.exit = terrain.to_global(start + dir * t)
			result.lost_j = energy_j - remaining
			return result
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			cell.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
		elif t_max.y <= t_max.z:
			cell.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
	result.stopped = true
	result.lost_j = maxf(energy_j, 0.0)
	return result


## Host only. Whether the structures between two world-space points stop a round arriving
## with `energy_j` joules: the line meets a structure (or other world geometry) it can't get
## through. Points in the clear, or behind only wood or sheet metal thin enough to shoot
## through, return false. For cover choices (SquadAI).
func stops_round(from: Vector3, to: Vector3, energy_j: float) -> bool:
	var space := get_world_3d().direct_space_state
	var direction := (to - from).normalized()
	var energy := energy_j
	var at := from
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1))
		if hit.is_empty():
			return false
		if VoxelWorld.find_on(hit.collider) != self:
			return true  # the ground or other solid world geometry
		var through := trace_round(hit.position, direction, energy)
		if through.stopped:
			return true
		energy -= float(through.lost_j)
		at = (through.exit as Vector3) + direction * 0.01
		if (at - from).dot(direction) >= (to - from).length():
			return false
	return true


## Host only. stops_round on the first VoxelWorld in `node`'s tree; true (anything in the
## way stops it) when there is none.
static func stops_round_in(node: Node, from: Vector3, to: Vector3, energy_j: float) -> bool:
	var world := node.get_tree().get_first_node_in_group(&"voxel_worlds") as VoxelWorld
	return world.stops_round(from, to, energy_j) if world else true


## Host only. Replays a saved edit log locally (the log itself is already in GameState).
func load_edits(edits: Array) -> void:
	for edit: Dictionary in edits:
		apply_edit(edit)


func send_edit_log_to(peer_id: int) -> void:
	_receive_edit_log.rpc_id(peer_id, GameState.voxel_edits)


@rpc("authority", "call_local", "reliable")
func apply_edit(edit: Dictionary) -> void:
	if _built:
		_apply(edit)
	else:
		_pending.append(edit)


@rpc("authority", "reliable")
func _receive_edit_log(edits: Array) -> void:
	load_edits(edits)


func _apply(edit: Dictionary) -> void:
	match edit.get("op"):
		"carve":
			var c: Array = edit["c"]
			# SET to EMPTY rather than MODE_REMOVE: on the color channel REMOVE doesn't
			# reliably clear voxels once `value` has been used for building.
			_tool.mode = VoxelTool.MODE_SET
			_tool.value = Mat.EMPTY
			var centre := Vector3(c[0], c[1], c[2])
			var r := float(edit["r"])
			_tool.do_sphere(centre, r)
			_carved(AABB(centre - Vector3.ONE * r, Vector3.ONE * r * 2.0))
		"blast":
			var c: Array = edit["c"]
			var centre := Vector3(c[0], c[1], c[2])
			var r := float(edit["r"])
			_blast(centre, r)
			_carved(AABB(centre - Vector3.ONE * r, Vector3.ONE * r * 2.0))
		"holes":
			var v: Array = edit["v"]
			var box := AABB()
			for i in range(0, v.size() - 2, 3):
				var cell := Vector3i(int(v[i]), int(v[i + 1]), int(v[i + 2]))
				_tool.set_voxel(cell, Mat.EMPTY)
				box = AABB(Vector3(cell), Vector3.ONE) if i == 0 else box.merge(AABB(Vector3(cell), Vector3.ONE))
			if v.size() >= 3:
				_carved(box)
		"mark":
			var p: Array = edit["p"]
			var n: Array = edit["n"]
			_add_mark(Vector3(p[0], p[1], p[2]), Vector3(n[0], n[1], n[2]), int(edit.get("m", Mat.CONCRETE)))


## Takes out each material within its share of radius `r` around `centre` (voxel units).
func _blast(centre: Vector3, r: float) -> void:
	var lo := Vector3i((centre - Vector3.ONE * r).floor())
	var hi := Vector3i((centre + Vector3.ONE * r).ceil())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var cell := Vector3i(x, y, z)
				var d := (Vector3(cell) + Vector3.ONE * 0.5).distance_to(centre)
				if d > r:
					continue
				var mat := int(_tool.get_voxel(cell))
				if mat != Mat.EMPTY and d <= r * float((MATERIALS.get(mat, {}) as Dictionary).get("blast", 1.0)):
					_tool.set_voxel(cell, Mat.EMPTY)


## After voxels in `box` (voxel units) were cleared: marks on voxels that are gone go too,
## and the host checks the area for a breach.
func _carved(box: AABB) -> void:
	var gone: Array[Vector3i] = []
	var area := box.grow(1.0)
	for cell: Vector3i in _mark_cells:
		if area.has_point(Vector3(cell) + Vector3.ONE * 0.5) and int(_tool.get_voxel(cell)) == Mat.EMPTY:
			gone.append(cell)
	for cell in gone:
		for serial: int in _mark_cells[cell]:
			_marks.erase(serial)
		_mark_cells.erase(cell)
		_queue_mark_rebuild()
	if multiplayer.is_server():
		_dirty.append(box)
		set_process(true)


# --- Impact marks --------------------------------------------------------------------------

## The voxel a mark at `p` facing `n` (voxel units) sits on.
static func _mark_cell(p: Vector3, n: Vector3) -> Vector3i:
	return Vector3i((p - n * 0.5).floor())


func _add_mark(p: Vector3, n: Vector3, mat: int) -> void:
	n = n.normalized() if not n.is_zero_approx() else Vector3.UP
	var cell := _mark_cell(p, n)
	_mark_serial += 1
	_marks[_mark_serial] = [p, n, mat, cell]
	if not _mark_cells.has(cell):
		_mark_cells[cell] = []
	(_mark_cells[cell] as Array).append(_mark_serial)
	while _marks.size() > MAX_MARKS:
		var oldest: int = _marks.keys()[0]
		var on: Array = _mark_cells.get(_marks[oldest][3], [])
		on.erase(oldest)
		if on.is_empty():
			_mark_cells.erase(_marks[oldest][3])
		_marks.erase(oldest)
	_queue_mark_rebuild()


func _queue_mark_rebuild() -> void:
	if not _marks_dirty:
		_marks_dirty = true
		_rebuild_marks.call_deferred()


## Every mark as a small quad flat on its surface, turned and sized by its position so every
## peer draws it the same.
func _rebuild_marks() -> void:
	_marks_dirty = false
	var mm := _mark_mesh.multimesh
	mm.instance_count = _marks.size()
	var size := MARK_SIZE_M / VOXEL_SIZE
	var i := 0
	for serial: int in _marks:
		var mark: Array = _marks[serial]
		var p: Vector3 = mark[0]
		var n: Vector3 = mark[1]
		var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
		var x := up.cross(n).normalized()
		var basis := Basis(x, n.cross(x), n)
		var h := absi(hash(Vector3i((p * 100.0).round())))
		basis = basis.rotated(n, float(h % 628) / 100.0)
		basis = basis.scaled(Vector3.ONE * size * (0.7 + float(floori(h / 628.0) % 60) / 100.0))
		mm.set_instance_transform(i, Transform3D(basis, p + n * 0.03))
		mm.set_instance_color(i, (MATERIALS.get(mark[2], {}) as Dictionary).get("mark", Color("3b3935")))
		i += 1


func _make_mark_mesh() -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_texture = _crack_texture()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	quad.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	var node := MultiMeshInstance3D.new()
	node.name = "ImpactMarks"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A small chip with hairline cracks running out of it (white on clear; each mark tints it).
static func _crack_texture() -> ImageTexture:
	const S := 32
	var image := Image.create(S, S, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1771
	var c := Vector2(S, S) * 0.5
	for y in S:
		for x in S:
			if Vector2(x + 0.5, y + 0.5).distance_to(c) < 3.6 + rng.randf() * 1.2:
				image.set_pixel(x, y, Color.WHITE)
	for k in 6:
		var p := c
		var heading := TAU * k / 6.0 + rng.randf_range(-0.4, 0.4)
		for s in rng.randi_range(7, 13):
			heading += rng.randf_range(-0.6, 0.6)
			p += Vector2.from_angle(heading)
			if p.x < 0.0 or p.y < 0.0 or p.x >= S or p.y >= S:
				break
			image.set_pixel(int(p.x), int(p.y), Color.WHITE)
	return ImageTexture.create_from_image(image)


# --- Breach detection (host) -----------------------------------------------------------

## Host only. Checks the carves since the last check (at most every BREACH_CHECK_S) for a
## gap a soldier now fits through, and reports each new one with `breached`.
func _check_breaches() -> void:
	if _dirty.is_empty():
		set_process(false)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_breach_check:
		return
	_next_breach_check = now + BREACH_CHECK_S
	var boxes := _dirty.duplicate()
	_dirty.clear()
	for box: AABB in boxes:
		var gap: Variant = find_breach(box)
		if gap == null and not is_area_readable(box):
			_dirty.append(box)  # not loaded yet: try again later
		elif gap != null:
			breached.emit(gap)


## Host only. Whether carving in `carved` (a voxel box) opened a new gap a soldier fits
## through in a structure: returns the gap as an AABB in metres (this node's space), or
## null. Columns of a gap found once aren't reported again, so later bullet holes around
## a breach don't count as new ones.
func find_breach(carved: AABB) -> Variant:
	if carved.end.y < BREACH_FLOOR or carved.position.y >= BREACH_TOP:
		return null  # below the rubble line or over head height
	var hw := BREACH_HALF_WIDTH
	var lo := Vector3i(floori(carved.position.x) - 2 * hw, BREACH_FLOOR, floori(carved.position.z) - 2 * hw)
	var hi := Vector3i(ceili(carved.end.x) + 2 * hw + 1, BREACH_TOP, ceili(carved.end.z) + 2 * hw + 1)
	var size := hi - lo
	# Columns that were wall in the soldier's band before any carving.
	var was_wall := PackedByteArray()
	was_wall.resize(size.x * size.z)
	var any_wall := false
	for s: Array in _structures:
		var a: Vector3i = s[0]
		var b: Vector3i = s[1]  # inclusive
		if b.y < BREACH_FLOOR or a.y >= BREACH_TOP:
			continue
		for z in range(maxi(a.z, lo.z), mini(b.z + 1, hi.z)):
			for x in range(maxi(a.x, lo.x), mini(b.x + 1, hi.x)):
				was_wall[(x - lo.x) + size.x * (z - lo.z)] = 1
				any_wall = true
	if not any_wall or not is_area_readable(AABB(lo, size)):
		return null
	# Columns with anything solid in the band now.
	var solid := solid_voxels(lo, size)
	var blocked := PackedByteArray()
	blocked.resize(size.x * size.z)
	for z in size.z:
		for x in size.x:
			var base := size.y * (x + size.x * z)
			for y in size.y:
				if solid[base + y] != 0:
					blocked[x + size.x * z] = 1
					break
	var opened := AABB()
	var found := false
	for z in range(hw, size.z - hw):
		for x in range(hw, size.x - hw):
			var column := Vector2i(lo.x + x, lo.z + z)
			if was_wall[x + size.x * z] == 0 or _breached.has(column) or not _clear_square(blocked, size.x, x, z, hw):
				continue
			_breached[column] = true
			var cell := AABB(Vector3(column.x, 0, column.y) * VOXEL_SIZE, Vector3(VOXEL_SIZE, BREACH_TOP * VOXEL_SIZE, VOXEL_SIZE))
			opened = cell if not found else opened.merge(cell)
			found = true
	if not found:
		return null
	return opened.grow(hw * VOXEL_SIZE)


func _clear_square(blocked: PackedByteArray, width: int, cx: int, cz: int, hw: int) -> bool:
	for z in range(cz - hw, cz + hw + 1):
		for x in range(cx - hw, cx + hw + 1):
			if blocked[x + width * z] != 0:
				return false
	return true


## Whether the structures' voxels in `box` (voxel coordinates) are built, loaded and can be
## read. Only the structures' area matters: everywhere else is always empty.
func is_area_readable(box: AABB) -> bool:
	if not _built:
		return false
	var need := box.intersection(_structure_area)
	return not need.has_volume() or _tool.is_area_editable(need)


## 1 where a voxel is solid and 0 where it's empty, for the box at `begin` (voxel
## coordinates) of `size`, indexed [y + size.y * (x + size.x * z)].
func solid_voxels(begin: Vector3i, size: Vector3i) -> PackedByteArray:
	var count := size.x * size.y * size.z
	var result := PackedByteArray()
	result.resize(count)
	if count <= 0:
		return result
	var buffer := VoxelBuffer.new()
	buffer.create(size.x, size.y, size.z)
	_tool.copy(begin, buffer, 1 << VoxelBuffer.CHANNEL_COLOR, false)
	if buffer.is_uniform(VoxelBuffer.CHANNEL_COLOR):
		if buffer.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_COLOR) != Mat.EMPTY:
			result.fill(1)
		return result
	var bytes := buffer.get_channel_as_byte_array(VoxelBuffer.CHANNEL_COLOR)
	var per := bytes.size() / count  # bytes per voxel (the channel's depth)
	for i in count:
		for k in per:
			if bytes[i * per + k] != 0:
				result[i] = 1
				break
	return result


## Host only. The structures' voxels as they are now (carving included), as boxes in metres
## in this node's space, for the part inside `area_m`: one box per vertical run of solid
## voxels, merged along x where neighbouring columns match. For navigation rebakes.
func solid_boxes_m(area_m: AABB) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var area_lo := Vector3i((area_m.position / VOXEL_SIZE).floor())
	var area_hi := Vector3i((area_m.end / VOXEL_SIZE).ceil())
	for s: Array in _structures:
		var lo: Vector3i = (s[0] as Vector3i).max(area_lo)
		var hi: Vector3i = (s[1] as Vector3i + Vector3i.ONE).min(area_hi)
		var size := hi - lo
		if size.x <= 0 or size.y <= 0 or size.z <= 0:
			continue
		var solid := solid_voxels(lo, size)
		for z in size.z:
			var open := {}  # run start y -> [run end y, first x]
			var prev: Array = []
			for x in size.x + 1:
				var runs: Array = _runs(solid, size, x, z) if x < size.x else []
				if runs != prev:
					# The runs that end here become boxes from where they started.
					for run: Array in prev:
						var key := Vector2i(run[0], run[1])
						if not runs.has(run):
							var x0: int = open[key]
							boxes.append(_box_m(lo + Vector3i(x0, run[0], z), Vector3i(x - x0, run[1] - run[0], 1)))
							open.erase(key)
					for run: Array in runs:
						var key := Vector2i(run[0], run[1])
						if not open.has(key):
							open[key] = x
					prev = runs
	return boxes


## Vertical runs of solid voxels in one column, as [start y, end y) pairs.
static func _runs(solid: PackedByteArray, size: Vector3i, x: int, z: int) -> Array:
	var runs: Array = []
	var base := size.y * (x + size.x * z)
	var start := -1
	for y in size.y + 1:
		var filled := y < size.y and solid[base + y] != 0
		if filled and start < 0:
			start = y
		elif not filled and start >= 0:
			runs.append([start, y])
			start = -1
	return runs


static func _box_m(begin: Vector3i, size: Vector3i) -> AABB:
	return AABB(Vector3(begin) * VOXEL_SIZE, Vector3(size) * VOXEL_SIZE)
