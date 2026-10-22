extends Node
## The Experimental forest test zone (Captain, 2026-10-14: "include experimental forest mission
## like we dev'd", "make it a button on the menu, not a regular mission"): the main menu's Test
## zones button hosts it (Menu.host_forest_zone) on the forest_experimental preset with the
## copses-as-cover layout, its stand-in raid briefing opens on the map, and nothing of it is in
## the campaign (not a campaign zone, nothing on the board or in the campaign save). One process:
##   <exe> --headless --path . res://tests/forest_test.tscn
## Prints FOREST TEST PASSED/FAILED and exits with its failure count.

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = "test_forest" + tag  # never touch a real campaign
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("FOREST TEST FAILED (timed out)")
		get_tree().quit(99))
	print("Experimental forest: not in the campaign")
	var campaign_zones: Array = MissionRegistry.zones().map(func(z: Dictionary) -> String: return String(z.zone_id))
	var preset_used := false
	for id: String in campaign_zones:
		preset_used = preset_used or String(MissionRegistry.zone_def(id).get("terrain", "")) == "forest_experimental"
	check(Menu.FOREST_ZONE not in campaign_zones and not preset_used and TerrainPresets.choose({"name": "Black forest", "region": "inland"}) != "forest_experimental",
		"no campaign zone is the forest or uses its preset, and no name hint picks it (%s)" % [campaign_zones])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var button: Button = null
	for b: Node in main.get_node(^"Menu").find_children("*", "Button", true, false):
		if (b as Button).text == Menu.FOREST_BUTTON_TEXT:
			button = b
	check(button != null, "the main menu's Test zones has \"%s\"" % Menu.FOREST_BUTTON_TEXT)
	if button == null:
		_finish()
		return
	var started := Time.get_ticks_msec()
	button.pressed.emit()
	var level := CompoundLevel.current(self) as ZoneLevel
	check(level != null and Net.is_hosting(), "pressing it hosts a zone on port %d (%.1f s)" % [Net.port(), (Time.get_ticks_msec() - started) / 1000.0])
	if level == null or not Net.is_hosting():
		_finish()
		return
	check(String(level.def.get("terrain", "")) == "forest_experimental" and level.modules().size() == 3 and String(level.def.name).contains("Experimental")
		and GameState.zone_id == "test_" + Menu.FOREST_ZONE,
		"it's the Experimental forest: %s, %.0f m, %d modules, preset %s, save %s" % [level.def.name, float(level.def.size_m), level.modules().size(), level.def.get("terrain", "?"), GameState.zone_id])
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	check(level.players.get_node_or_null(^"1") != null, "the host's player is in")
	var scatter: ZoneScatter = null
	for n: Node in level.find_children("*", "", true, false):
		if n is ZoneScatter:
			scatter = n
	check(scatter != null and scatter._cover and scatter.counts[ZoneScatter.Kind.TREE] > 2000 and scatter.counts[ZoneScatter.Kind.THICKET] > 2000,
		"its woods are the denser copses-as-cover layout (%s)" % [scatter.counts if scatter else "no scatter"])
	var briefing := MapNodes.briefing(level)
	var c: Dictionary = briefing.contract if briefing else {}
	check(briefing != null and briefing.is_open() and String(c.get("title", "")).begins_with("EXPERIMENTAL") and (c.get("objectives", []) as Array).size() == 3
		and not briefing.insertion_points().is_empty(),
		"its stand-in raid briefing is open: %s, %d objectives, %d insertion points" % [c.get("title", "?"), (c.get("objectives", []) as Array).size(), briefing.insertion_points().size() if briefing else 0])
	for i in 120:  # a couple of seconds of the zone running (streaming, garrisons)
		await get_tree().process_frame
	await _test_hitboxes(level, scatter)
	check(Campaign.section(Contracts.SECTION).is_empty() and Contracts.board().is_empty(),
		"nothing went into the campaign (no contracts section, no board)")
	_finish()


## Tree, rock and prop hitboxes (cghath's world visual pass, 2026-10-20): what collides (and stops
## rounds and men) is what's drawn. Every solid item's shapes (ZoneScatter.collision_parts) cover
## the same box as its drawn mesh (visual_parts: a tree's trunk, not its crown); rays swept across
## a trunk, a rock and each prop shape hit where the drawn triangles are and pass where they aren't
## (the old trunk cylinder was narrower than the octagon's corners; rocks and props were a box 0.9
## of their size, drawn sheared when turned); a crown stops nothing (leaves hide, they don't stop
## rounds: ZoneScatter.foliage_between); and a soldier walking into a trunk is stopped at it.
func _test_hitboxes(level: ZoneLevel, scatter: ZoneScatter) -> void:
	var meshes := scatter._shared_meshes("4a3a2a")
	var verts := {}  # group key -> the mesh's triangle corners
	var drawn_points := func(item: Dictionary) -> PackedVector3Array:
		var out := PackedVector3Array()
		for part: Array in scatter.visual_parts(item):
			if part[0] is String and part[0] in ["crown", "conifer"]:
				continue  # leaves: no collision
			if not verts.has(part[0]):
				var mesh: Mesh = meshes.get(part[0])
				if mesh == null:  # a library prop's (the props suite checks those shape by shape)
					var np := String(part[0]).trim_prefix(ZoneScatter.LIBRARY)
					mesh = PropArt.mesh(np.get_slice("#", 0), int(np.get_slice("#", 1)))
				verts[part[0]] = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var xf: Transform3D = part[1]
			for v: Vector3 in verts[part[0]]:
				out.append(xf * v)
		return out
	var shape_points := func(item: Dictionary) -> PackedVector3Array:
		var out := PackedVector3Array()
		for part: Array in scatter.collision_parts(item):
			var xf: Transform3D = part[1]
			for v: Vector3 in (part[0] as ConvexPolygonShape3D).points:
				out.append(xf * v)
		return out
	var box_of := func(points: PackedVector3Array) -> AABB:
		var box := AABB(points[0], Vector3.ZERO)
		for v in points:
			box = box.expand(v)
		return box
	var names := {ZoneScatter.Kind.TREE: "trunk", ZoneScatter.Kind.ROCK: "rock", ZoneScatter.Kind.PROP: "prop"}
	var worst := {}
	var checked := {}
	var samples := {}  # kind -> an item on flat ground with nothing solid near it
	for item: Dictionary in scatter.items:
		var kind := int(item.kind)
		if not item.solid or int(checked.get(kind, 0)) >= 300:
			continue
		checked[kind] = int(checked.get(kind, 0)) + 1
		var a: AABB = box_of.call(drawn_points.call(item))
		var b: AABB = box_of.call(shape_points.call(item))
		var d := 0.0
		for v: Vector3 in [(a.position - b.position).abs(), (a.end - b.end).abs()]:
			d = maxf(d, maxf(v.x, maxf(v.y, v.z)))
		worst[kind] = maxf(float(worst.get(kind, 0.0)), d)
		var p: Vector3 = item.pos
		if not samples.has(kind) and level.terrain.normal_at(p.x, p.z).y > 0.985 and _alone(scatter, item, 3.0):
			samples[kind] = item
	check(checked.has(ZoneScatter.Kind.TREE) and checked.has(ZoneScatter.Kind.ROCK) and worst.values().all(func(d: float) -> bool: return d <= 0.04),
		"hitboxes: every solid item's collision covers what's drawn, to 4 cm (%s)" % ", ".join(worst.keys().map(func(k: int) -> String:
			return "%ss %.3f m over %d" % [names.get(k, str(k)), worst[k], checked[k]])))
	# Rays across what's drawn: they hit where its triangles are and miss where they aren't. A lone
	# trunk and rock where they stand; each prop shape on a test body up in the air.
	var space := level.get_world_3d().direct_space_state
	var ground: Array[RID] = []
	for body: Node in level.terrain.find_children("*", "CollisionObject3D", true, false):
		ground.append((body as CollisionObject3D).get_rid())
	var sweeps: Array = []  # [what, item, height]
	for kind: int in [ZoneScatter.Kind.TREE, ZoneScatter.Kind.ROCK]:
		check(samples.has(kind), "hitboxes: a lone %s on flat ground to shoot at" % names[kind])
		if samples.has(kind):
			sweeps.append(["a " + names[kind], samples[kind], 1.0 if kind == ZoneScatter.Kind.TREE else -0.41])
	var props := Node3D.new()
	add_child(props)
	for want: String in ZoneScatter.PROP_SHAPES:
		for k in 400:  # a spot and size that make this shape (the shape is picked from them)
			var size := Vector3(2.6, 1.3, 1.6) if want in ["wall", "wreck", "mound"] else Vector3(0.9, 0.7, 0.8)
			var item := {"kind": ZoneScatter.Kind.PROP, "pos": Vector3(k * 7.3, 300.0 + size.y * 0.5, 40.0 + sweeps.size() * 9.0), "yaw": 0.7, "size": size, "solid": true, "colour": Color.WHITE}
			if ZoneScatter._prop_kind(item) != want:
				continue
			var body := StaticBody3D.new()
			body.name = "Cover_test_%s" % want
			props.add_child(body)
			for part: Array in scatter.collision_parts(item):
				var shape := CollisionShape3D.new()
				shape.shape = part[0]
				shape.transform = part[1]
				body.add_child(shape)
			sweeps.append(["a \"%s\" prop" % want, item, -0.41])
			break
	await get_tree().physics_frame
	await get_tree().physics_frame
	for sw: Array in sweeps:
		var item: Dictionary = sw[1]
		var tris: PackedVector3Array = drawn_points.call(item)
		var box: AABB = box_of.call(tris)
		var p: Vector3 = item.pos
		var y := p.y + float(sw[2]) if float(sw[2]) > 0.0 else lerpf(maxf(box.position.y, level.terrain.height_at(p.x, p.z) + 0.1), box.end.y, -float(sw[2]))
		var reach := maxf(box.size.x, box.size.z) * 0.6 + 0.2
		var across := Vector3(0.3, 0, 1).normalized()  # square to nothing
		var side := across.cross(Vector3.UP).normalized()
		var hits := 0
		var wrong := 0
		var steps := 41
		for k in steps:
			var off := (float(k) / (steps - 1) - 0.5) * 2.0 * reach
			var from := Vector3(box.get_center().x, y, box.get_center().z) + side * off - across * (reach + 1.0)
			var to := from + across * (reach * 2.0 + 2.0)
			var drawn := false
			for t in range(0, tris.size(), 3):
				if Geometry3D.segment_intersects_triangle(from, to, tris[t], tris[t + 1], tris[t + 2]) != null:
					drawn = true
					break
			var query := PhysicsRayQueryParameters3D.create(from, to, 1, ground)
			var hit := space.intersect_ray(query)
			var hit_it := not hit.is_empty() and String((hit.collider as Node).name).begins_with("Cover_")
			hits += 1 if hit_it else 0
			wrong += 1 if hit_it != drawn else 0
		check(hits >= 3 and wrong <= 1,
			"hitboxes: %d rays across %s (%.2f m wide): %d hit it, %d disagree with what's drawn (dev's shapes: a trunk 2, a rock 4)" % [steps, sw[0], maxf(box.size.x, box.size.z), hits, wrong])
	props.queue_free()
	if samples.has(ZoneScatter.Kind.TREE):
		var tree: Dictionary = samples[ZoneScatter.Kind.TREE]
		var p: Vector3 = tree.pos
		var s := float((tree.size as Vector3).x)
		var up := Vector3(0, s * (ZoneScatter.TRUNK_TALL + 0.4), 0)  # over the trunk's top, in the crown
		var through_crown := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + up + Vector3(-3, 0, 0), p + up + Vector3(3, 0, 0), 1, ground))
		check(through_crown.is_empty(), "hitboxes: a round through a crown's leaves goes on (leaves hide, they don't stop rounds)")
		# A soldier walking into the trunk is stopped at it (his own capsule, as he moves).
		var player: Soldier = level.players.get_node(^"1")
		var was := player.global_position
		player.set_physics_process(false)
		var start := Vector3(p.x + 1.6, 0, p.z)
		start.y = maxf(level.terrain.height_at(start.x, start.z), p.y) + 0.4
		player.global_position = start
		var hit := player.move_and_collide(Vector3(-3.2, 0, 0), true)
		var stop := 1.6 - (hit.get_travel().length() if hit else 3.2)
		var capsule := ((player.get_node(^"Collision") as CollisionShape3D).shape as CapsuleShape3D).radius
		check(hit != null and String((hit.get_collider() as Node).name).begins_with("Cover_") and stop > capsule + ZoneScatter.TRUNK_TOP_R * s - 0.06 and stop < capsule + 0.25 * s + 0.06,
			"hitboxes: walking into a trunk (%.2f m across at its foot) stops him %.2f m from its middle (his capsule %.2f m round)" % [ZoneScatter.TRUNK_FOOT_R * 2.0 * s, stop, capsule])
		player.global_position = was
		player.set_physics_process(true)


## Whether nothing solid but `item` stands within `m` of it (its cell and the ones round it).
func _alone(scatter: ZoneScatter, item: Dictionary, m: float) -> bool:
	var p: Vector3 = item.pos
	var cell := scatter._cell_of(p.x, p.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for index: int in scatter._cells.get(cell + Vector2i(dx, dz), []):
				var other: Dictionary = scatter.items[index]
				if not is_same(other, item) and other.solid and (other.pos as Vector3).distance_to(p) < m + maxf((other.size as Vector3).x, (other.size as Vector3).z):
					return false
	return true


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	GameState.delete_save()
	print("FOREST TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
