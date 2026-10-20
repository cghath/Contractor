class_name LhdNav
extends NavBuilder
## The walkable LHD's navigation (docs/lhd_home.md): NavBuilder's chunks on the ship's own grid
## (SHIP_AREA: the hull and a little round it, tall enough for the flight deck), the hangar floor as
## the ground (inside the hull only: the sea isn't walkable), the ship's voxel boxes, and a ramp
## over each stair so the squad walks between the decks (LhdLayout.ramp_faces; the steps as
## voxels bake cut in two, as BuildingGen's do). Host only, like NavBuilder.

const SHIP_AREA := AABB(Vector3(-18, -1, -84), Vector3(36, 10, 168))


## Host only. Bakes the ship from its boxes and keeps it up to date as walls are breached.
static func build_for(p_level: CompoundLevel) -> LhdNav:
	var nav := LhdNav.new()
	nav.name = "Navigation"
	nav.level = p_level
	p_level.add_child(nav)
	var started := Time.get_ticks_usec()
	nav._bake_from_boxes()
	print("[nav] baked the LHD's %d chunks in %.0f ms" % [nav._regions.size(), (Time.get_ticks_usec() - started) / 1000.0])
	p_level.voxel_world.breached.connect(nav.rebake_area)
	return nav


static func lhd_chunk_count() -> Vector2i:
	return Vector2i(ceili(SHIP_AREA.size.x / CHUNK_M), ceili(SHIP_AREA.size.z / CHUNK_M))


static func lhd_chunk_aabb(chunk: Vector2i) -> AABB:
	return AABB(Vector3(SHIP_AREA.position.x + chunk.x * CHUNK_M, SHIP_AREA.position.y, SHIP_AREA.position.z + chunk.y * CHUNK_M),
		Vector3(CHUNK_M, SHIP_AREA.size.y, CHUNK_M))


func _bake_from_boxes() -> void:
	var xform := level.voxel_world.global_transform
	var boxes: Array[AABB] = []
	for box in level.voxel_world.structure_boxes_m():
		boxes.append(xform * box)
	var count := lhd_chunk_count()
	for cz in count.y:
		for cx in count.x:
			var chunk := Vector2i(cx, cz)
			var source := _ground_source(chunk)
			var bounds := _bounds_of(chunk)
			for box in boxes:
				if box.intersects(bounds):
					source.add_faces(NavBuilder._box_faces(box), Transform3D.IDENTITY)
			var mesh := _mesh_for(chunk)
			NavigationServer3D.bake_from_source_geometry_data(mesh, source)
			var region := NavigationRegion3D.new()
			region.name = "Chunk_%d_%d" % [cx, cz]
			region.navigation_mesh = mesh
			add_child(region)
			_regions[chunk] = region


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - SHIP_AREA.position.x) / CHUNK_M), floori((pos.z - SHIP_AREA.position.z) / CHUNK_M))


func _bounds_of(chunk: Vector2i) -> AABB:
	var box := lhd_chunk_aabb(chunk)
	return AABB(box.position - Vector3(BORDER_M, 0, BORDER_M), box.size + Vector3(BORDER_M, 0, BORDER_M) * 2.0)


## The hangar floor under the chunk (the hull's footprint only) and the stairs' ramps.
func _ground_source(chunk: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var b := _bounds_of(chunk)
	var floor_rect := Rect2(b.position.x, b.position.z, b.size.x, b.size.z).intersection(LhdLayout.ship_rect())
	if floor_rect.has_area():
		var a := floor_rect.position
		var c := floor_rect.end
		source.add_faces(PackedVector3Array([
			Vector3(a.x, 0, a.y), Vector3(c.x, 0, a.y), Vector3(c.x, 0, c.y),
			Vector3(a.x, 0, a.y), Vector3(c.x, 0, c.y), Vector3(a.x, 0, c.y),
		]), Transform3D.IDENTITY)
	source.add_faces(LhdLayout.ramp_faces(), Transform3D.IDENTITY)
	return source
