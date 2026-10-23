extends Node
## Mesh census (render pass 2026-10-22, not a suite): hosts a zone headless, builds its visuals as
## a player's machine would, and counts what the renderer would hold: geometry nodes, unique meshes
## and their surfaces, MultiMeshes and their instances, materials, by what owns them (the level's
## child they sit under). Each mesh surface, MultiMesh and material is GPU buffers on a real
## renderer.
##   <voxel godot exe> --headless --path . res://tests/mesh_census.tscn [-- --zone=city_hot]

func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_mesh_census" + tag
	Campaign.campaign_id = "test_mesh_census_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	var zone := "city_hot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zone="):
			zone = a.trim_prefix("--zone=")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(zone))
	var level: ZoneLevel = null
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	level.terrain.build_visuals()
	level.scatter.build_visuals()
	var roads := level.get_node_or_null(^"Roads")
	if roads and roads.has_method(&"build_visuals"):
		roads.build_visuals()
	var town: ZoneModule = null
	for m in level.modules():
		if ZoneModules.base(m.type) in ["town", "city"] and (town == null or ZoneModules.boxes(m.type).size() > ZoneModules.boxes(town.type).size()):
			town = m
	if town:
		var r := town.footprint()
		var player := level.players.get_node(^"1") as Soldier
		player.set_physics_process(false)
		player.global_position = level.ground_point(Vector3(r.get_center().x, 0, r.end.y + 40.0))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 45000:
		await get_tree().process_frame
	var streamed := 0
	for m in level.modules():
		if m.is_streamed():
			streamed += 1
	print("census: %d of %d modules streamed in" % [streamed, level.modules().size()])
	var player2 := level.players.get_node(^"1") as Soldier
	var eye := player2.global_position
	var ds: Array = []
	for m in level.modules():
		ds.append([m.distance_to(eye), m.module_id, ZoneModules.boxes(m.type).size(), ZoneModules.bounds_voxels(m.type).size])
	ds.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in ds.slice(0, 22):
		print("census: module %-14s %5.0f m off, %5d boxes, bounds %s voxels" % [e[1], e[0], e[2], e[3]])
	var by := {}  # owner -> [nodes, multimesh instances, surfaces of unique meshes, unique meshes, multimeshes]
	var seen_mesh := {}
	var seen_mat := {}
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var g := n as GeometryInstance3D
		if g == null:
			continue
		var owner_name := _owner(level, n)
		var e: Array = by.get(owner_name, [0, 0, 0, 0, 0])
		e[0] += 1
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			e[1] += mm.instance_count
			e[4] += 1
			mesh = mm.mesh
		if mesh and not seen_mesh.has(mesh.get_instance_id()):
			seen_mesh[mesh.get_instance_id()] = true
			e[2] += mesh.get_surface_count()
			e[3] += 1
		if g.material_override:
			seen_mat[g.material_override.get_instance_id()] = true
		by[owner_name] = e
	var keys := by.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(by[a][0]) > int(by[b][0]))
	for k: String in keys.slice(0, 25):
		var e: Array = by[k]
		print("census: %-28s %6d geometry nodes, %6d unique meshes (%d surfaces), %5d multimeshes (%d instances)" % [k, e[0], e[3], e[2], e[4], e[1]])
	print("census: %d unique meshes in all, %d material overrides; objects %d, resources %d" % [seen_mesh.size(), seen_mat.size(),
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


## The level's child `n` sits under (and the one under it, for big holders).
func _owner(level: Node, n: Node) -> String:
	var path := level.get_path_to(n)
	var top := String(path.get_name(0)) if path.get_name_count() > 0 else "?"
	var second := String(path.get_name(1)) if path.get_name_count() > 2 else ""
	return top if second == "" or top in ["Terrain", "Scatter"] else "%s/%s" % [top, second.left(14)]
