class_name ZoneNav
extends NavBuilder
## Host-side navigation for a zone: NavBuilder's chunks on the zone's own grid, baked in the
## background around the players (PLAYER_RADIUS_M) and every living AI soldier (AI_RADIUS_M)
## as they move, and dropped again once nobody is near (DROP_MARGIN_M beyond). A chunk bakes
## the terrain under it and the structures on it: a loaded module's voxels as they are now,
## or an unloaded module's proxy (its base boxes, with breaches made before it streamed out
## kept open). A breach in a module rebakes the chunks around it
## (VoxelWorld.breached), as in the compound.
##
## The grid's chunk centres fall on module origins (ZoneDef.GRID_M), so chunk edges run 6 m
## from each origin, as the compound's do, and stay clear of the doorways.
##
## Chunks join their neighbours only where their border vertices match (the regions' proximity
## edge connections are off: they cost town fights milliseconds a tick, R0036). Chunks baked
## from the same geometry match; a chunk baked from a module's proxy may not match one baked
## from its voxels (a carved proxy is coarser: whole 0.5 m cells), so once a module's voxels
## are built, every chunk last baked from its proxy is baked again from them (_proxied,
## _on_structures_built; review of the executive audit, 2026-10-18).

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
## Whether the zone's navigation map builds its iterations on a worker thread (build_zone).
const MAP_ASYNC := true

var zone: ZoneLevel
var _origin := Vector2.ZERO  # the grid's corner (x, z)
var _wanted := {}  # Vector2i -> distance to the nearest soldier wanting it
var _queue: Array[Vector2i] = []
var _next_update := 0.0
## Vector2i -> the ids of the modules whose proxy (not voxels) the chunk's last bake read.
var _proxied := {}
var _gathering: Array[String] = []  # while a chunk's geometry is gathered: the proxies read


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
	# World content pass (2026-10-23): in a city (~500 chunks with floors over floors) a map
	# update is 10-16 ms on the main thread, about twice a second (perfcases city, R0576: the
	# server's frame median 9.8 ms): the map's own iterations are built on a worker (MAP_ASYNC);
	# the regions' stay synchronous (the missing updates above).
	NavigationServer3D.map_set_use_async_iterations(nav.get_world_3d().navigation_map, MAP_ASYNC)
	return nav


## Host only. Connects a module's voxel world's breaches to rebakes (while it's loaded), and
## its voxels being built to rebaking the chunks baked from its proxy meanwhile.
func watch(world: VoxelWorld) -> void:
	if not world.breached.is_connected(rebake_area):
		world.breached.connect(rebake_area.bind(world))
	if not world.is_built():
		world.structures_built.connect(_on_structures_built.bind(world.module_id), CONNECT_ONE_SHOT)


## A module's voxels are built: every chunk whose last bake read that module's proxy is baked
## again from the voxels, a few a frame (NavBuilder._process, REBAKE_BUDGET_MS). Until then the
## proxy's bake stays, as a chunk's old bake does during any rebake.
func _on_structures_built(module_id: String) -> void:
	for chunk: Vector2i in _proxied:
		if (_proxied[chunk] as Array).has(module_id) and _regions.has(chunk):
			_waiting[chunk] = true
	if not _waiting.is_empty():
		set_process(true)


## Which proxies the chunk's geometry was read from, kept in _proxied (see _on_structures_built).
func _voxel_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	_gathering = []
	var source := super._voxel_source(chunk)
	if source != null:
		if _gathering.is_empty():
			_proxied.erase(chunk)
		else:
			_proxied[chunk] = _gathering
	return source


## Whether the chunk's last bake read any module's proxy instead of its voxels.
func baked_from_proxy(chunk: Vector2i) -> bool:
	return _proxied.has(chunk)


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - _origin.x) / ZONE_CHUNK_M), floori((pos.z - _origin.y) / ZONE_CHUNK_M))


func _rect_of(chunk: Vector2i) -> Rect2:
	return Rect2(_origin.x + chunk.x * ZONE_CHUNK_M, _origin.y + chunk.y * ZONE_CHUNK_M, ZONE_CHUNK_M, ZONE_CHUNK_M)


## The chunk plus its border, from below the lowest ground to HEADROOM_M above the highest (or
## over the tallest module standing on it, its top and a man's height: a city's floors and roofs,
## queue item 1.5), on a 0.25 m height grid shared by every chunk (so their edges line up).
func _bounds_of(chunk: Vector2i) -> AABB:
	var r := _rect_of(chunk).grow(BORDER_M)
	var heights := zone.terrain.height_range(r.grow(ZoneTerrain.CELL_M))
	var lo := floorf((heights.x - 1.0) / 0.25) * 0.25
	var top := heights.y + HEADROOM_M
	for module in zone.modules():
		if module.footprint().intersects(r):
			top = maxf(top, module.global_position.y + float(ZoneModules.TOP.get(module.type, 0.0)) + AGENT_HEIGHT)
	var hi := ceilf(top / 0.25) * 0.25
	return AABB(Vector3(r.position.x, lo, r.position.y), Vector3(r.size.x, hi - lo, r.size.y))


func _ground_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var b := _bounds_of(chunk)
	var ground := zone.terrain.triangles_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z).grow(ZoneTerrain.CELL_M))
	if not ground.is_empty():  # a chunk all out at sea has none (add_faces errors on an empty array)
		source.add_faces(ground, Transform3D.IDENTITY)
	for box in zone.scatter.boxes_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z)):
		source.add_faces(_box_faces(box), Transform3D.IDENTITY)
	if zone.terrain.water:
		var bridges := zone.terrain.water.nav_faces_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
		if not bridges.is_empty():
			source.add_faces(bridges, Transform3D.IDENTITY)  # the way over deep water (ZoneBridges)
	var props := zone.scatter.faces_in(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))  # the prop library's, as drawn
	if not props.is_empty():
		source.add_faces(props, Transform3D.IDENTITY)
	return source


## Bakes again every chunk baked now that `area` (x, z in metres) touches (a bridge's span
## dropped: ZoneBridges).
func rebake_rect(area: Rect2) -> void:
	var lo := _chunk_of(Vector3(area.position.x - BORDER_M, 0.0, area.position.y - BORDER_M))
	var hi := _chunk_of(Vector3(area.end.x + BORDER_M, 0.0, area.end.y + BORDER_M))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _regions.has(Vector2i(cx, cz)):
				_request_rebake(Vector2i(cx, cz))


## Whether every loaded module's voxels inside `bounds` can be read now (_add_structures).
func _structures_readable(bounds: AABB) -> bool:
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	for module in zone.modules():
		var world := module.voxel_world
		if world and module.footprint().grow(1.0).intersects(rect):
			var local := world.global_transform.affine_inverse() * bounds
			if not world.is_area_readable(AABB(local.position / VoxelWorld.VOXEL_SIZE, local.size / VoxelWorld.VOXEL_SIZE)):
				return false
	return true


## Loaded modules' voxels as they are now (false while one isn't built yet); unloaded
## modules' proxies (ZoneModule.proxy_boxes: the base boxes, less what was carved); either's
## stairs as ramps (ZoneModules.ramps).
func _add_structures(source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> bool:
	var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	for module in zone.modules():
		if not module.footprint().grow(1.0).intersects(rect):
			continue
		var world := module.voxel_world
		# A town builds its voxels in slices over many frames: until it's built its proxy (base boxes)
		# stands in, so its streets bake now instead of the AI walking blind into it (Captain,
		# 2026-10-16: "ai arent entering towns").
		if world and world.is_built():
			var local := world.global_transform.affine_inverse() * bounds
			var voxels := AABB(local.position / VoxelWorld.VOXEL_SIZE, local.size / VoxelWorld.VOXEL_SIZE)
			if not world.is_area_readable(voxels):
				return false
			for box in world.solid_boxes_m(local):
				source.add_faces(_box_faces(box), world.global_transform)
		else:
			var local := module.global_transform.affine_inverse() * bounds
			for box in module.proxy_boxes():  # with any breach made before it streamed out
				if box.intersects(local):
					source.add_faces(_box_faces(box.intersection(local.grow(0.01))), module.global_transform)
			_gathering.append(module.module_id)
		# Its stairs as ramps (the steps as voxels bake cut in two: BuildingGen.ramp_faces).
		var ramps := ZoneModules.ramps(module.type)
		if not ramps.is_empty():
			source.add_faces(ramps, module.global_transform)
	_add_builds(source, bounds)
	return true


## Survival's builds (call 141; docs/survival_building.md): the built blocks in Builder's voxel
## chunks as they are now, so the dead path round a wall (or push on it: BuildIntegrity's
## battering) and never through. Built pieces that stand solid join NavBuilder.OBSTACLES_GROUP
## themselves (BuildPiece.apply); doors don't (the dead push on them). Builder rebakes the
## chunks a change touches (Builder._nav_touch).
func _add_builds(source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> void:
	var b := zone.get_node_or_null(NodePath(Builder.NODE_NAME)) as Builder
	if b == null:
		return
	for w: BuildVoxels in b.chunks_in(bounds):
		if not w.is_built():
			continue
		var local := w.global_transform.affine_inverse() * bounds
		for box in w.solid_boxes_m(local):
			source.add_faces(_box_faces(box), w.global_transform)


## True once every chunk wanted around the soldiers is baked and nothing is waiting.
func is_settled() -> bool:
	if not _queue.is_empty() or is_rebaking():
		return false
	for chunk: Vector2i in _wanted:
		if region_of(chunk) == null or region_of(chunk).navigation_mesh == null:
			return false
	return map_caught_up()  # and the map has taken the last mesh in (a path asked for sooner misses it)


## Works out the wanted chunks now (they're also refreshed every UPDATE_S).
func refresh() -> void:
	_next_update = Time.get_ticks_msec() / 1000.0 + UPDATE_S
	_update_wanted(true)


## How many chunks are baked (or baking) now.
func chunk_total() -> int:
	return _regions.size()


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_update:
		_next_update = now + UPDATE_S
		var t_w := Time.get_ticks_usec()
		_update_wanted()
		FrameCost.spent(&"nav_wanted", t_w)
	var t_s := Time.get_ticks_usec()
	# Start new chunks, nearest first, while there's room, for at most REBAKE_BUDGET_MS a frame
	# (gathering a chunk's voxels takes milliseconds; 8 at once held fights' frames for 50-200 ms).
	var until := Time.get_ticks_usec() + int(REBAKE_BUDGET_MS * 1000.0)
	while not _queue.is_empty() and _baking.size() < MAX_BAKES and Time.get_ticks_usec() < until:
		var chunk: Vector2i = _queue.pop_front()
		if _regions.has(chunk) or not _wanted.has(chunk):
			continue
		var region := NavigationRegion3D.new()
		# These chunks share a voxel grid and bake border: their matching vertices join
		# directly. Skip costly proximity-edge matching only for these zone regions (a chunk
		# baked from a proxy is baked again once the voxels are: see the class notes).
		region.use_edge_connections = false
		region.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		add_child(region)
		NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
		_regions[chunk] = region
		_request_rebake(chunk)
	FrameCost.spent(&"nav_start", t_s)


## Perf (world content pass, 2026-10-23): the chunks nobody is near any more are looked for every
## DROP_EVERY passes (and on refresh), not every pass: the wider ring each soldier keeps was most of
## a pass's marking (~110 chunks a soldier against ~25 wanted), 5-10 ms a pass for a city's ~100 AI.
const DROP_EVERY := 4
var _drop_turn := 0


func _update_wanted(full := false) -> void:
	var near := {}  # Vector2i -> distance
	var keep := {}
	_drop_turn += 1
	var drops := full or _drop_turn % DROP_EVERY == 0
	for s in zone.soldiers_for_navigation():
		if _riding_past(s):
			continue
		var radius := PLAYER_RADIUS_M if not s.is_ai() else AI_RADIUS_M
		_mark(near, s.global_position, radius)
		if drops:
			_mark(keep, s.global_position, radius + DROP_MARGIN_M, false)
	_wanted = near
	# Drop chunks nobody is near any more.
	for chunk: Vector2i in (_regions.keys() if drops else []):
		if not keep.has(chunk):
			_regions[chunk].queue_free()
			_regions.erase(chunk)
			_waiting.erase(chunk)
			_again.erase(chunk)
			_proxied.erase(chunk)
	var missing: Array[Vector2i] = []
	for chunk: Vector2i in near:
		if not _regions.has(chunk):
			missing.append(chunk)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return near[a] < near[b])
	_queue = missing


## Proposed (world content pass, 2026-10-23): a soldier in a flying helicopter going faster than
## RIDE_FAST_MS, or more than RIDE_AGL_M over the ground, wants no navigation round him: he can't
## walk off, and every chunk he flew over was baked and dropped again (from a UH-60 contour-flying
## at 12.5 m, ~20 bakes a second, each a few ms of gathering on the main thread, R0568). Slowing
## and coming down to land, the chunks round him are wanted again (UPDATE_S) and bake before anyone
## gets out. (Ground vehicles keep theirs: VehicleAI plans on the navigation mesh round the vehicle.)
const RIDE_FAST_MS := 8.0
const RIDE_AGL_M := 15.0


func _riding_past(s: Soldier) -> bool:
	if s.vehicle == null or not is_instance_valid(s.vehicle):
		return false
	var heli := s.vehicle as Helicopter
	if heli == null or not heli.is_airborne():
		return false
	var v := heli.linear_velocity
	return Vector2(v.x, v.z).length() > RIDE_FAST_MS or heli.height_agl() > RIDE_AGL_M


## Marks every chunk within `radius` of `pos` (flat) with its distance from `pos` (`distances`
## false: with true, for a set). Perf (world content pass, 2026-10-23): the same chunks as before,
## worked out with plain floats (a Rect2 and a Vector2 per chunk, ~100 AI each marking ~110
## chunks every UPDATE_S, was a few ms a pass in a city).
func _mark(into: Dictionary, pos: Vector3, radius: float, distances := true) -> void:
	var lo := _chunk_of(pos - Vector3(radius, 0, radius))
	var hi := _chunk_of(pos + Vector3(radius, 0, radius))
	var half := zone.terrain.size_m * 0.5
	var r2 := radius * radius
	for cz in range(lo.y, hi.y + 1):
		var z0 := _origin.y + cz * ZONE_CHUNK_M
		var z1 := z0 + ZONE_CHUNK_M
		if z1 < -half or z0 > half:
			continue
		var dz := maxf(maxf(z0 - pos.z, pos.z - z1), 0.0)
		for cx in range(lo.x, hi.x + 1):
			var x0 := _origin.x + cx * ZONE_CHUNK_M
			var x1 := x0 + ZONE_CHUNK_M
			if x1 < -half or x0 > half:
				continue
			var dx := maxf(maxf(x0 - pos.x, pos.x - x1), 0.0)
			var d2 := dx * dx + dz * dz
			if d2 > r2:
				continue
			var chunk := Vector2i(cx, cz)
			if not distances:
				into[chunk] = true
				continue
			var d := sqrt(d2)
			if d < float(into.get(chunk, INF)):
				into[chunk] = d
