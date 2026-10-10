class_name VoxelWorld
extends Node3D
## Destructible structures made of 10 cm voxels. Every peer builds the same base structures
## locally, then applies the host's ordered edit log, so only small edit events cross the
## network, and the same log is what gets saved.
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
enum Mat { EMPTY, CONCRETE, PAINTED, WOOD, STEEL }
## Index 0 must stay transparent: the cubes mesher treats it as empty.
const PALETTE: Array[Color] = [Color(0, 0, 0, 0), Color("8a8577"), Color("5f6b58"), Color("8c6a46"), Color("4a4d50")]
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


## Host only. Removes a sphere of voxels around a world-space point.
func server_carve(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	var edit := {"op": "carve", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE}
	GameState.voxel_edits.append(edit)
	apply_edit.rpc(edit)


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
			if multiplayer.is_server():
				_dirty.append(AABB(centre - Vector3.ONE * r, Vector3.ONE * r * 2.0))
				set_process(true)


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
