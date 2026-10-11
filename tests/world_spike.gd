extends Node
## Spike: what one bounded VoxelTerrain costs as its bounds grow, and how a viewer's
## view_distance maps onto a scaled terrain.

var _frame_max := 0.0
var _last := 0
var _alt_worst := 0.0


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if "--terrain" in args:
		await _terrain()
		get_tree().quit(0)
		return
	await _units()
	for side_m in [44, 100, 200, 400]:
		await _bounded(side_m)
	get_tree().quit(0)


func _terrain() -> void:
	var mem0 := _mem()
	var terrain := ZoneTerrain.new()
	add_child(terrain)
	var t := Time.get_ticks_usec()
	terrain.generate({"seed": 4417, "size_m": 2048.0, "relief_m": 18.0}, [Rect2(-22, -22, 44, 44), Rect2(300, 300, 30, 30)])
	var gen_ms := (Time.get_ticks_usec() - t) / 1000.0
	var mem1 := _mem()
	t = Time.get_ticks_usec()
	terrain.build_collision()
	var col_ms := (Time.get_ticks_usec() - t) / 1000.0
	var mem2 := _mem()
	t = Time.get_ticks_usec()
	terrain.build_visuals()
	var vis_ms := (Time.get_ticks_usec() - t) / 1000.0
	var mem3 := _mem()
	print("[spike] terrain 2048 m (%d x %d heights): heights %.0f ms (+%.1f MB), collision %.0f ms (+%.1f MB), meshes %.0f ms (+%.1f MB), heights %.1f..%.1f m, max slope %.1f deg" % [
		terrain.points, terrain.points, gen_ms, mem1 - mem0, col_ms, mem2 - mem1, vis_ms, mem3 - mem2, terrain.min_height, terrain.max_height, terrain.max_slope_deg()])
	var tris := [0, 0, 0]
	for child in terrain.get_children():
		if child is MeshInstance3D and child.name.begins_with("Mesh_"):
			var lod := int(String(child.name).get_slice("_", 3))
			tris[lod] += (child.mesh as ArrayMesh).surface_get_array_index_len(0) / 3
	print("[spike] triangles per level of detail (whole zone): %s" % [tris])
	for i in 3:
		await get_tree().physics_frame
	var space := terrain.get_world_3d().direct_space_state
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var misses := 0
	for k in 400:
		var x := rng.randf_range(-1000, 1000)
		var z := rng.randf_range(-1000, 1000)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z)))
		if hit.is_empty():
			misses += 1
			continue
		worst = maxf(worst, absf(hit.position.y - terrain.height_at(x, z)))
		var gx := (x + 1024.0) / 4.0
		var gz := (z + 1024.0) / 4.0
		var i := floori(gx)
		var j := floori(gz)
		var fx := gx - i
		var fz := gz - j
		var h00 := terrain._h(i, j)
		var h10 := terrain._h(i + 1, j)
		var h01 := terrain._h(i, j + 1)
		var h11 := terrain._h(i + 1, j + 1)
		var alt := 0.0
		if fx + fz <= 1.0:
			alt = h00 + (h10 - h00) * fx + (h01 - h00) * fz
		else:
			alt = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
		_alt_worst = maxf(_alt_worst, absf(hit.position.y - alt))
	print("[spike] other diagonal worst %.4f" % _alt_worst)
	print("[spike] raycast vs height_at over 400 points: worst %.4f m, %d misses" % [worst, misses])
	var pad := terrain.height_at(0, 0)
	print("[spike] pad flat: %.3f %.3f %.3f %.3f" % [pad, terrain.height_at(-27, -27), terrain.height_at(27, 27), terrain.height_at(10, -25)])
	t = Time.get_ticks_usec()
	var faces := terrain.triangles_in(Rect2(-7, -7, 14, 14))
	print("[spike] nav faces for a 14 m square: %d triangles in %.2f ms" % [faces.size() / 3, (Time.get_ticks_usec() - t) / 1000.0])


func _mem() -> float:
	return OS.get_static_memory_usage() / 1048576.0


func _make(bounds: AABB, view_vox: int) -> VoxelTerrain:
	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3.ONE * 0.1
	var generator := VoxelGeneratorFlat.new()
	generator.channel = VoxelBuffer.CHANNEL_COLOR
	generator.height = -1000.0
	terrain.generator = generator
	var mesher := VoxelMesherCubes.new()
	var palette := VoxelColorPalette.new()
	palette.set_color(1, Color.GRAY)
	mesher.palette = palette
	mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
	terrain.mesher = mesher
	terrain.bounds = bounds
	terrain.max_view_distance = view_vox
	add_child(terrain)
	return terrain


func _viewer(pos: Vector3, dist: int) -> VoxelViewer:
	var v := VoxelViewer.new()
	v.view_distance = dist
	v.requires_collisions = true
	v.requires_visuals = true
	add_child(v)
	v.global_position = pos
	return v


## Does view_distance count world metres or voxels on a 0.1-scaled terrain?
func _units() -> void:
	# A 4 m box of terrain 50 m from the viewer.
	var terrain := _make(AABB(Vector3(480, -8, -20), Vector3(40, 56, 40)), 4096)
	var viewer := _viewer(Vector3.ZERO, 64)  # 64 m if metres; 6.4 m if voxels
	var tool := terrain.get_voxel_tool()
	var loaded := false
	for i in 120:
		await get_tree().process_frame
		if tool.is_area_editable(AABB(Vector3(480, -8, -20), Vector3(40, 56, 40))):
			loaded = true
			break
	print("[spike] view_distance 64 on a 0.1-scaled terrain loads a block 48-52 m away: %s" % loaded)
	viewer.queue_free()
	terrain.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## A bounded box `side_m` square (5.6 m tall) with perimeter walls, loaded from its centre.
func _bounded(side_m: int) -> void:
	var half := side_m * 5  # voxels
	var bounds := AABB(Vector3(-half, -8, -half), Vector3(half * 2, 56, half * 2))
	var mem0 := _mem()
	var started := Time.get_ticks_usec()
	var terrain := _make(bounds, half * 2 + 200)
	var viewer := _viewer(Vector3.ZERO, side_m + 20)
	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	var area := AABB(Vector3(-half, 0, -half), Vector3(half * 2, 26, half * 2))
	var worst := 0.0
	var prev := Time.get_ticks_usec()
	var frames := 0
	while not tool.is_area_editable(area):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - prev) / 1000.0)
		prev = now
		frames += 1
		if frames > 20000:
			break
	var load_ms := (Time.get_ticks_usec() - started) / 1000.0
	tool.mode = VoxelTool.MODE_SET
	tool.value = 1
	var t := Time.get_ticks_usec()
	tool.do_box(Vector3i(-half, 0, -half), Vector3i(half - 1, 25, -half + 2))
	tool.do_box(Vector3i(-half, 0, half - 3), Vector3i(half - 1, 25, half - 1))
	tool.do_box(Vector3i(-half, 0, -half), Vector3i(-half + 2, 25, half - 1))
	tool.do_box(Vector3i(half - 3, 0, -half), Vector3i(half - 1, 25, half - 1))
	var build_ms := (Time.get_ticks_usec() - t) / 1000.0
	# Let meshing and collision settle.
	var settle_worst := 0.0
	prev = Time.get_ticks_usec()
	for i in 90:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		settle_worst = maxf(settle_worst, (now - prev) / 1000.0)
		prev = now
	var stats: Dictionary = terrain.get_statistics()
	print("[spike] bounded %d m square: loaded in %.0f ms over %d frames (worst frame %.1f ms), walls %.1f ms, worst frame while meshing %.1f ms, +%.1f MB static, stats %s" % [
		side_m, load_ms, frames, worst, build_ms, settle_worst, _mem() - mem0, stats])
	viewer.queue_free()
	terrain.queue_free()
	for i in 5:
		await get_tree().process_frame
