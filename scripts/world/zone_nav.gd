class_name ZoneNav
extends NavBuilder
## Host-side navigation for a zone: NavBuilder's chunks on the zone's own grid, baked in the
## background around the players (PLAYER_RADIUS_M) and every living AI soldier (AI_RADIUS_M)
## as they move, and dropped again once nobody is near (DROP_MARGIN_M beyond). A chunk bakes
## the terrain under it and the structures on it: a loaded module's voxels as they are now,
## or an unloaded module's base boxes. A breach in a module rebakes the chunks around it
## (VoxelWorld.breached), as in the compound.
##
## The grid's chunk centres fall on module origins (ZoneDef.GRID_M), so chunk edges run 6 m
## from each origin, as the compound's do, and stay clear of the doorways.

const ZONE_CHUNK_M := 12.0
## Proposed: how far around each player and each AI soldier the navigation is kept baked.
const PLAYER_RADIUS_M := 48.0
const AI_RADIUS_M := 20.0
## A chunk is dropped once it's this much further than that from everyone.
const DROP_MARGIN_M := 24.0
## Background bakes running at once, and how often the wanted chunks are worked out.
const MAX_BAKES := 8
const UPDATE_S := 0.3
## Room above the ground in a chunk's bake for the structures (m).
const HEADROOM_M := 8.0

var zone: ZoneLevel
var _origin := Vector2.ZERO  # the grid's corner (x, z)
var _wanted := {}  # Vector2i -> distance to the nearest soldier wanting it
var _queue: Array[Vector2i] = []
var _next_update := 0.0


## Host only. Starts the zone's navigation (chunks bake as soldiers come near).
static func build_zone(p_zone: ZoneLevel) -> ZoneNav:
	var nav := ZoneNav.new()
	nav.name = "Navigation"
	nav.level = p_zone
	nav.zone = p_zone
	var half := p_zone.terrain.size_m * 0.5
	# Chunk centres on the module grid: edges at 6 m past a multiple of 12 m.
	nav._origin = Vector2(-half - ZONE_CHUNK_M * 0.5, -half - ZONE_CHUNK_M * 0.5)
	p_zone.add_child(nav)
	# Chunks come and go all the time here; with asynchronous iterations some region updates
	# never reached the map (measured: whole chunks missing from paths while their regions
	# held the right meshes). Synchronous updates (map and regions) cost well under 1 ms.
	NavigationServer3D.map_set_use_async_iterations(nav.get_world_3d().navigation_map, false)
	return nav


## Host only. Connects a module's voxel world's breaches to rebakes (while it's loaded).
func watch(world: VoxelWorld) -> void:
	if not world.breached.is_connected(rebake_area):
		world.breached.connect(rebake_area.bind(world))


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - _origin.x) / ZONE_CHUNK_M), floori((pos.z - _origin.y) / ZONE_CHUNK_M))


func _rect_of(chunk: Vector2i) -> Rect2:
	return Rect2(_origin.x + chunk.x * ZONE_CHUNK_M, _origin.y + chunk.y * ZONE_CHUNK_M, ZONE_CHUNK_M, ZONE_CHUNK_M)


## The chunk plus its border, from below the lowest ground to HEADROOM_M above the highest,
## on a 0.25 m height grid shared by every chunk (so their edges line up).
func _bounds_of(chunk: Vector2i) -> AABB:
	var r := _rect_of(chunk).grow(BORDER_M)
	var heights := zone.terrain.height_range(r.grow(ZoneTerrain.CELL_M))
	var lo := floorf((heights.x - 1.0) / 0.25) * 0.25
	var hi := ceilf((heights.y + HEADROOM_M) / 0.25) * 0.25
	return AABB(Vector3(r.position.x, lo, r.position.y), Vector3(r.size.x, hi - lo, r.size.y))


func _ground_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var b := _bounds_of(chunk)
	var ground := zone.terrain.triangles_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z).grow(ZoneTerrain.CELL_M))
	if not ground.is_empty():  # a chunk all out at sea has none (add_faces errors on an empty array)
		source.add_faces(ground, Transform3D.IDENTITY)
	for box in zone.scatter.boxes_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z)):
		source.add_faces(_box_faces(box), Transform3D.IDENTITY)
	return source


## Loaded modules' voxels as they are now (false while one isn't built yet); unloaded
## modules' base boxes.
func _add_structures(source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> bool:
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	for module in zone.modules():
		if not module.footprint().grow(1.0).intersects(rect):
			continue
		var world := module.voxel_world
		if world:
			var local := world.global_transform.affine_inverse() * bounds
			var voxels := AABB(local.position / VoxelWorld.VOXEL_SIZE, local.size / VoxelWorld.VOXEL_SIZE)
			if not world.is_area_readable(voxels):
				return false
			for box in world.solid_boxes_m(local):
				source.add_faces(_box_faces(box), world.global_transform)
		else:
			var local := module.global_transform.affine_inverse() * bounds
			for box in ZoneModules.boxes_m(module.type):
				if box.intersects(local):
					source.add_faces(_box_faces(box.intersection(local.grow(0.01))), module.global_transform)
	return true


## True once every chunk wanted around the soldiers is baked and nothing is waiting.
func is_settled() -> bool:
	if not _queue.is_empty() or is_rebaking():
		return false
	for chunk: Vector2i in _wanted:
		if region_of(chunk) == null or region_of(chunk).navigation_mesh == null:
			return false
	return true


## Works out the wanted chunks now (they're also refreshed every UPDATE_S).
func refresh() -> void:
	_next_update = Time.get_ticks_msec() / 1000.0 + UPDATE_S
	_update_wanted()


## How many chunks are baked (or baking) now.
func chunk_total() -> int:
	return _regions.size()


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_update:
		_next_update = now + UPDATE_S
		_update_wanted()
	# Start new chunks, nearest first, while there's room.
	while not _queue.is_empty() and _baking.size() < MAX_BAKES:
		var chunk: Vector2i = _queue.pop_front()
		if _regions.has(chunk) or not _wanted.has(chunk):
			continue
		var region := NavigationRegion3D.new()
		region.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		add_child(region)
		NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
		_regions[chunk] = region
		_request_rebake(chunk)


func _update_wanted() -> void:
	var near := {}  # Vector2i -> distance
	var keep := {}
	for s in zone.soldiers_for_navigation():
		var radius := PLAYER_RADIUS_M if not s.is_ai() else AI_RADIUS_M
		_mark(near, s.global_position, radius)
		_mark(keep, s.global_position, radius + DROP_MARGIN_M)
	_wanted = near
	# Drop chunks nobody is near any more.
	for chunk: Vector2i in _regions.keys():
		if not keep.has(chunk):
			_regions[chunk].queue_free()
			_regions.erase(chunk)
			_waiting.erase(chunk)
			_again.erase(chunk)
	var missing: Array[Vector2i] = []
	for chunk: Vector2i in near:
		if not _regions.has(chunk):
			missing.append(chunk)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return near[a] < near[b])
	_queue = missing


## Marks every chunk within `radius` of `pos` (flat) with its distance from `pos`.
func _mark(into: Dictionary, pos: Vector3, radius: float) -> void:
	var lo := _chunk_of(pos - Vector3(radius, 0, radius))
	var hi := _chunk_of(pos + Vector3(radius, 0, radius))
	var p := Vector2(pos.x, pos.z)
	var half := zone.terrain.size_m * 0.5
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var chunk := Vector2i(cx, cz)
			var r := _rect_of(chunk)
			if r.end.x < -half or r.position.x > half or r.end.y < -half or r.position.y > half:
				continue
			var d := ZoneTerrain._distance_to_rect(p, r)
			if d <= radius and d < float(into.get(chunk, INF)):
				into[chunk] = d
