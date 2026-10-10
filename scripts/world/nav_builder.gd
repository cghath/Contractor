class_name NavBuilder
extends Node3D
## Host-side navigation for the compound, in square chunks: one NavigationRegion3D per
## CHUNK_M chunk, baked with a border so neighbouring chunks' edges line up and paths run
## across them.
##
## At host start every chunk is baked from the flat ground and the voxel structures' boxes.
## When a wall is breached (VoxelWorld.breached: carving opened a gap a soldier fits
## through), the chunks around the gap are rebaked in the background from the voxel world's
## actual solid voxels. Until a rebake finishes the old navmesh stays, so AI treats the gap
## as blocked. Bullet holes never open such a gap, so they never cause a rebake.

## Emitted when a chunk's background rebake is in place (the map uses it a frame later).
signal rebaked(chunk: Vector2i)

## The baked area: the compound and a good way around it (formations behind a player at the
## gate reach past 45 m). Chunk edges (every CHUNK_M from AREA's corner, at x and z = ±6,
## ±18, ±30, ±42) stay clear of the gate and the building doorway.
const AREA := AABB(Vector3(-54, -1, -54), Vector3(108, 8, 108))
const CHUNK_M := 12.0
## Geometry this far beyond a chunk is baked with it, so its edges match its neighbours'.
## A multiple of the 0.25 m cell size, and more than the agent radius.
const BORDER_M := 1.0
const GROUND_HALF := 80.0
## The soldier the navmesh is for (multiples of the default 0.25 m cell size and height,
## so nothing gets rounded). The building doorway is 1.2 m wide.
const AGENT_RADIUS := 0.25
const AGENT_HEIGHT := 1.75
const AGENT_MAX_CLIMB := 0.25

var level: CompoundLevel
var _regions := {}   # Vector2i -> NavigationRegion3D
var _baking := {}    # Vector2i -> true while a background rebake runs
var _again := {}     # Vector2i -> true: breached again during its rebake
var _waiting := {}   # Vector2i -> true: voxels not loaded yet, rebake when they are


## Host only. Bakes the compound's navigation from the structures' boxes and keeps it up to
## date as walls are breached.
static func build(p_level: CompoundLevel) -> NavBuilder:
	var nav := NavBuilder.new()
	nav.name = "Navigation"
	nav.level = p_level
	p_level.add_child(nav)
	var started := Time.get_ticks_usec()
	nav._bake_from_boxes()
	print("[nav] baked %d chunks in %.0f ms" % [nav._regions.size(), (Time.get_ticks_usec() - started) / 1000.0])
	p_level.voxel_world.breached.connect(nav.rebake_area)
	return nav


## How many chunks there are along x and z.
static func chunk_count() -> Vector2i:
	return Vector2i(ceili(AREA.size.x / CHUNK_M), ceili(AREA.size.z / CHUNK_M))


## The chunk a world position falls in (may be outside the grid).
static func chunk_at(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - AREA.position.x) / CHUNK_M), floori((pos.z - AREA.position.z) / CHUNK_M))


static func chunk_aabb(chunk: Vector2i) -> AABB:
	return AABB(Vector3(AREA.position.x + chunk.x * CHUNK_M, AREA.position.y, AREA.position.z + chunk.y * CHUNK_M),
		Vector3(CHUNK_M, AREA.size.y, CHUNK_M))


## True while any chunk is waiting for or running a background rebake.
func is_rebaking() -> bool:
	return not _baking.is_empty() or not _waiting.is_empty()


## The region of one chunk (null outside the grid).
func region_of(chunk: Vector2i) -> NavigationRegion3D:
	return _regions.get(chunk)


## Host only. Rebakes, in the background, every chunk whose bake reaches `area_m` (an AABB in
## the voxel world's space, metres), from the voxels as they are now.
func rebake_area(area_m: AABB) -> void:
	var area := level.voxel_world.global_transform * area_m
	var lo := chunk_at(area.position - Vector3.ONE * BORDER_M)
	var hi := chunk_at(area.end + Vector3.ONE * BORDER_M)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var chunk := Vector2i(cx, cz)
			if _regions.has(chunk):
				_request_rebake(chunk)


func _process(_delta: float) -> void:
	for chunk: Vector2i in _waiting.keys():
		_waiting.erase(chunk)
		_request_rebake(chunk)
	if _waiting.is_empty():
		set_process(false)


func _request_rebake(chunk: Vector2i) -> void:
	if _baking.has(chunk):
		_again[chunk] = true  # the bake running now may have read the voxels too early
		return
	var source := _voxel_source(chunk)
	if source == null:
		_waiting[chunk] = true  # voxels not loaded yet: try again next frame
		set_process(true)
		return
	_baking[chunk] = true
	var mesh := _new_mesh(chunk)
	# Through a weak reference: the level may be gone by the time the bake finishes.
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, NavBuilder._bake_done.bind(weakref(self), chunk, mesh))


static func _bake_done(builder: WeakRef, chunk: Vector2i, mesh: NavigationMesh) -> void:
	var nav := builder.get_ref() as NavBuilder
	if nav:
		nav._on_rebaked.call_deferred(chunk, mesh)


func _on_rebaked(chunk: Vector2i, mesh: NavigationMesh) -> void:
	_baking.erase(chunk)
	if not is_inside_tree() or not _regions.has(chunk):
		return
	_regions[chunk].navigation_mesh = mesh
	rebaked.emit(chunk)
	if _again.has(chunk):
		_again.erase(chunk)
		_request_rebake(chunk)


## At host start: every chunk from the ground and the structures' boxes, right away.
func _bake_from_boxes() -> void:
	var xform := level.voxel_world.global_transform
	var boxes: Array[AABB] = []
	for box in level.voxel_world.structure_boxes_m():
		boxes.append(xform * box)
	var count := chunk_count()
	for cz in count.y:
		for cx in count.x:
			var chunk := Vector2i(cx, cz)
			var source := _ground_source(chunk)
			var bounds := _bake_bounds(chunk)
			for box in boxes:
				if box.intersects(bounds):
					source.add_faces(_box_faces(box), Transform3D.IDENTITY)
			var mesh := _new_mesh(chunk)
			NavigationServer3D.bake_from_source_geometry_data(mesh, source)
			var region := NavigationRegion3D.new()
			region.name = "Chunk_%d_%d" % [cx, cz]
			region.navigation_mesh = mesh
			add_child(region)
			_regions[chunk] = region


## A chunk's geometry from the voxels as they are now, or null if they aren't loaded.
func _voxel_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var world := level.voxel_world
	var bounds := _bake_bounds(chunk)
	var local := world.global_transform.affine_inverse() * bounds
	var voxels := AABB(local.position / VoxelWorld.VOXEL_SIZE, local.size / VoxelWorld.VOXEL_SIZE)
	if not world.is_area_readable(voxels):
		return null
	var source := _ground_source(chunk)
	for box in world.solid_boxes_m(local):
		source.add_faces(_box_faces(box), world.global_transform)
	return source


func _ground_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var b := _bake_bounds(chunk)
	var a := Vector3(b.position.x, 0, b.position.z)
	var c := Vector3(b.end.x, 0, b.end.z)
	source.add_faces(PackedVector3Array([
		Vector3(a.x, 0, a.z), Vector3(c.x, 0, a.z), Vector3(c.x, 0, c.z),
		Vector3(a.x, 0, a.z), Vector3(c.x, 0, c.z), Vector3(a.x, 0, c.z),
	]), Transform3D.IDENTITY)
	return source


## The chunk plus its border: what its bake reads.
static func _bake_bounds(chunk: Vector2i) -> AABB:
	var box := chunk_aabb(chunk)
	return AABB(box.position - Vector3(BORDER_M, 0, BORDER_M), box.size + Vector3(BORDER_M, 0, BORDER_M) * 2.0)


static func _new_mesh(chunk: Vector2i) -> NavigationMesh:
	var nav := NavigationMesh.new()
	nav.agent_radius = AGENT_RADIUS
	nav.agent_height = AGENT_HEIGHT
	nav.agent_max_climb = AGENT_MAX_CLIMB
	# Tile-aligned chunks: bake the border too, then trim it so edges meet their neighbours'.
	nav.filter_baking_aabb = _bake_bounds(chunk)
	nav.border_size = BORDER_M
	nav.edge_max_error = 1.0
	return nav


static func _box_faces(box: AABB) -> PackedVector3Array:
	var a := box.position
	var b := box.end
	var c := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),  # bottom
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),  # top
	]
	var quads := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
	var faces := PackedVector3Array()
	for q: Array in quads:
		faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return faces
