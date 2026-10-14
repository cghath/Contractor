class_name ZoneModule
extends Node3D
## One hand-built combat space on a zone's terrain (a ZoneModules type: compound, outpost,
## village, checkpoint), at its origin on a flat pad.
##
## Streamed: while anyone is near (ZoneLevel decides), it's a VoxelWorld of its own at 10 cm,
## built from the type's boxes and then its own edit log (the zone keeps every module's log,
## on every peer, and saves them with the zone). While nobody is near, the voxels are freed
## and a proxy stands in: the base boxes as one plain mesh, seen from up to PROXY_VIEW_M, with
## box collision so rounds and sight lines still stop at its walls. The proxy goes once the
## voxels are built and their collision has had PROXY_HOLD_S to come in. Streaming out keeps
## what was carved: a base box carving touched stands in the proxy (and in the navigation
## baked while away, proxy_boxes) as coarse cells of the voxels as they were, so a breach
## stays open for distant sight lines, rounds and paths until the voxels come back.

## Emitted on the peer where it happens.
signal streamed_in(module: ZoneModule)
signal streamed_out(module: ZoneModule)

const PROXY_VIEW_M := 2500.0
const PROXY_HOLD_S := 0.5
## A carved box's proxy cells: this many voxels a side (0.5 m), solid when at least half
## their voxels are (a bullet hole leaves a wall whole; a breach opens it).
const PROXY_CELL_VOXELS := 5

var module_id := ""
var type := ""
## The loaded voxels (null while streamed out).
var voxel_world: VoxelWorld
## How many entries of this module's edit log are applied to voxel_world.
var applied := 0
## The voxel terrain's view distance cap (voxels), set by the zone from its streaming range.
var view_voxels := 4000

var _proxy_mesh: MeshInstance3D
var _proxy_body: StaticBody3D
## What the proxy is made of: [AABB (m, module space), VoxelWorld.Mat] each. The base boxes,
## until streaming out finds carving (_carved_parts).
var _proxy_parts: Array = []
## The base boxes in voxels from the origin, [lo: Vector3i, size: Vector3i] each (as built).
var _proxy_base: Array = []
## While streamed in: base box index -> {cell (Vector3i): solid} for the cells carving has
## touched (_on_carved); the rest of a box is as built. Made again by each stream-in's replay.
var _cells := {}
var _ready_at := -1.0  # Time (s) the proxy can go, once the voxels are built
var _proxy_up := true


func setup(id: String, p_type: String, origin: Vector3) -> void:
	module_id = id
	type = p_type
	name = id.validate_node_name()
	position = origin


func _ready() -> void:
	var mats := ZoneModules.boxes(type)
	var boxes := ZoneModules.boxes_m(type)
	for i in boxes.size():
		_proxy_parts.append([boxes[i], int(mats[i][2])])
		var lo := Vector3i((boxes[i].position / VoxelWorld.VOXEL_SIZE).round())
		_proxy_base.append([lo, Vector3i((boxes[i].end / VoxelWorld.VOXEL_SIZE).round()) - lo])
	_build_proxy()
	set_process(false)


## The structure as it stands while streamed out (m, module space): the base boxes, with what
## was carved before streaming out taken out of them (for navigation baked meanwhile).
func proxy_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for part: Array in _proxy_parts:
		out.append(part[0])
	return out


## The footprint on the ground (x, z in metres, world space).
func footprint() -> Rect2:
	var half: Vector2 = ZoneModules.HALF.get(type, Vector2(20, 20))
	return Rect2(position.x - half.x, position.z - half.y, half.x * 2.0, half.y * 2.0)


## Flat distance (m) from `pos` to the footprint (0 inside).
func distance_to(pos: Vector3) -> float:
	return ZoneTerrain._distance_to_rect(Vector2(pos.x, pos.z), footprint())


## A named point of this module in world space (ZoneModules.POINTS: "objective", "cache",
## "intel"), or the origin if it has none.
func point(kind: String, index := 0) -> Vector3:
	var list := ZoneModules.points(type, kind)
	return to_global(list[index % list.size()]) if not list.is_empty() else global_position


func points(kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in ZoneModules.points(type, kind):
		out.append(to_global(p))
	return out


func is_streamed() -> bool:
	return voxel_world != null


## Streamed in, built, and the proxy gone (its own collision in place).
func is_ready() -> bool:
	return voxel_world != null and voxel_world.is_built() and not _proxy_up


## Makes the voxels (the type's boxes, then `log` from the start, then whatever the zone sends
## as it comes). `sink`: the host's edit sink (VoxelWorld.edit_sink), none on a client.
func stream_in(log: Array, sink: Callable) -> void:
	if voxel_world:
		return
	var world := VoxelWorld.new()
	world.name = "Voxels"
	world.module_id = module_id
	world.bounds = ZoneModules.bounds_voxels(type)
	world.view_distance = view_voxels
	world.edit_sink = sink
	for box: Array in ZoneModules.boxes(type):
		world.add_box_m(box[0], box[1], box[2])
	voxel_world = world
	applied = 0
	_cells.clear()  # the replay of the log fills it again
	world.carved.connect(_on_carved.bind(world))
	add_child(world)
	world.structures_built.connect(_on_built, CONNECT_ONE_SHOT)
	sync(log)


## Applies the entries of this module's edit log not applied yet (queued by the voxel world
## until it's built).
func sync(log: Array) -> void:
	if voxel_world == null:
		return
	for i in range(applied, log.size()):
		voxel_world.apply_edit(log[i])
	applied = log.size()


func stream_out() -> void:
	if voxel_world == null:
		return
	var parts := _carved_parts()
	if not parts.is_empty():
		_proxy_parts = parts
		_rebuild_proxy()
	voxel_world.queue_free()
	remove_child(voxel_world)
	voxel_world = null
	applied = 0
	_ready_at = -1.0
	set_process(false)
	_show_proxy(true)
	streamed_out.emit(self)


func _on_built() -> void:
	_ready_at = Time.get_ticks_msec() / 1000.0 + PROXY_HOLD_S
	set_process(true)


func _process(_delta: float) -> void:
	if voxel_world and voxel_world.is_built() and Time.get_ticks_msec() / 1000.0 >= _ready_at:
		set_process(false)
		_show_proxy(false)
		streamed_in.emit(self)


func _show_proxy(on: bool) -> void:
	_proxy_up = on
	_proxy_mesh.visible = on
	_proxy_body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_proxy_body.collision_layer = 1 if on else 0


## Every peer: carving cleared voxels in `box` (voxels): the cells it touched of each base
## box, looked at again while the voxels are certainly there (_cells).
func _on_carved(box: AABB, world: VoxelWorld) -> void:
	var touched := box.grow(1.0)
	var c := PROXY_CELL_VOXELS
	for i in _proxy_base.size():
		var lo: Vector3i = _proxy_base[i][0]
		var size: Vector3i = _proxy_base[i][1]
		if not AABB(Vector3(lo), Vector3(size)).intersects(touched):
			continue
		var n := _cell_count(size)
		var c_lo := Vector3i(((touched.position - Vector3(lo)) / c).floor()).clamp(Vector3i.ZERO, n)
		var c_hi := Vector3i(((touched.end - Vector3(lo)) / c).ceil()).clamp(Vector3i.ZERO, n)
		var read_lo := lo + c_lo * c
		var read_size := (lo + c_hi * c).min(lo + size) - read_lo
		if read_size.x <= 0 or read_size.y <= 0 or read_size.z <= 0 or not world.is_area_readable(AABB(Vector3(read_lo), Vector3(read_size))):
			continue
		var solid := world.solid_voxels(read_lo, read_size)
		var known: Dictionary = _cells.get(i, {})
		for z in range(c_lo.z, c_hi.z):
			for y in range(c_lo.y, c_hi.y):
				for x in range(c_lo.x, c_hi.x):
					var cell := Vector3i(x, y, z)
					known[cell] = _half_solid(cell * c, ((cell + Vector3i.ONE) * c).min(size), c_lo * c, read_size, solid)
		_cells[i] = known


## The cells (PROXY_CELL_VOXELS a side) along each axis of a box `size` voxels big.
static func _cell_count(size: Vector3i) -> Vector3i:
	var c := float(PROXY_CELL_VOXELS)
	return Vector3i(ceili(size.x / c), ceili(size.y / c), ceili(size.z / c))


## Whether the voxels from `a` to `b` (voxels from the box's corner) are at least half solid.
## `solid` is VoxelWorld.solid_voxels from `offset` (from the box's corner), `read_size` big.
static func _half_solid(a: Vector3i, b: Vector3i, offset: Vector3i, read_size: Vector3i, solid: PackedByteArray) -> bool:
	var count := 0
	for z in range(a.z, b.z):
		for x in range(a.x, b.x):
			for y in range(a.y, b.y):
				var r := Vector3i(x, y, z) - offset
				count += solid[r.y + read_size.y * (r.x + read_size.x * r.z)]
	return count * 2 >= (b.x - a.x) * (b.y - a.y) * (b.z - a.z)


## The proxy's parts with what carving took out (_cells): an untouched base box as it is, a
## touched one as its solid cells, merged into runs along x. [] while nothing was carved.
func _carved_parts() -> Array:
	if _cells.is_empty():
		return []
	var s := VoxelWorld.VOXEL_SIZE
	var c := PROXY_CELL_VOXELS
	var mats := ZoneModules.boxes(type)
	var out: Array = []
	for i in _proxy_base.size():
		var lo: Vector3i = _proxy_base[i][0]
		var size: Vector3i = _proxy_base[i][1]
		var mat := int(mats[i][2])
		if not _cells.has(i):
			out.append([AABB(Vector3(lo) * s, Vector3(size) * s), mat])
			continue
		var known: Dictionary = _cells[i]
		var n := _cell_count(size)
		for z in n.z:
			for y in n.y:
				var run_from := -1
				for x in n.x + 1:
					var full := x < n.x and bool(known.get(Vector3i(x, y, z), true))
					if full and run_from < 0:
						run_from = x
					elif not full and run_from >= 0:
						var a := Vector3i(run_from, y, z) * c
						var b := (Vector3i(x, y + 1, z + 1) * c).min(size)
						out.append([AABB(Vector3(lo + a) * s, Vector3(b - a) * s), mat])
						run_from = -1
	return out


## The proxy made again from _proxy_parts (after carving changed them).
func _rebuild_proxy() -> void:
	for node: Node in [_proxy_mesh, _proxy_body]:
		remove_child(node)
		node.queue_free()
	_build_proxy()
	_show_proxy(_proxy_up)


## The stand-in while streamed out: its parts (_proxy_parts) as one mesh in their materials'
## colours, and as box shapes on the world layer. Placeholder art: replace this one function.
func _build_proxy() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_proxy_body = StaticBody3D.new()
	_proxy_body.name = "Proxy"
	_proxy_body.collision_layer = 1
	_proxy_body.collision_mask = 0
	for part: Array in _proxy_parts:
		var box: AABB = part[0]
		var colour: Color = VoxelWorld.PALETTE[int(part[1])]
		st.set_color(colour)
		var faces := NavBuilder._box_faces(box)
		for k in range(0, faces.size(), 3):
			var n := (faces[k + 1] - faces[k]).cross(faces[k + 2] - faces[k]).normalized()
			st.set_normal(-n)  # NavBuilder's faces are clockwise from outside (Godot's front faces)
			st.add_vertex(faces[k])
			st.add_vertex(faces[k + 1])
			st.add_vertex(faces[k + 2])
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = box.size
		shape.shape = cube
		shape.position = box.get_center()
		_proxy_body.add_child(shape)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	_proxy_mesh = MeshInstance3D.new()
	_proxy_mesh.name = "ProxyMesh"
	_proxy_mesh.mesh = st.commit()
	_proxy_mesh.material_override = material
	_proxy_mesh.visibility_range_end = PROXY_VIEW_M
	add_child(_proxy_mesh)
	add_child(_proxy_body)
