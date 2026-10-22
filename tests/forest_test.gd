extends Node
## The Experimental forest test zone (Captain, 2026-10-14: "include experimental forest mission
## like we dev'd", "make it a button on the menu, not a regular mission"): the main menu's Test
## zones button hosts it (Menu.host_forest_zone) on the forest_experimental preset with the
## copses-as-cover layout, its stand-in raid briefing opens on the map, and nothing of it is in
## the campaign (not a campaign zone, nothing on the board or in the campaign save). One process:
##   <exe> --headless --path . res://tests/forest_test.tscn
## Prints FOREST TEST PASSED/FAILED and exits with its failure count.
##
## The woods perf pass (cghath's queue item 1.8; Captain, 2026-10-14: "frame goes 4 -> 10 ms in
## woods, up to 1.5k draws, 1.4M prims. Then denser copses"): a normal preset's dense copses are
## laid out the same every time, drawn within a budget (near and far tiers handing over with
## nothing drawn twice or missing), spotted through as before (the fine index gives the old
## answers), cheap to spot and navigate through; and in the forest's densest copse the frame and
## the AI's foliage cost stay within a budget (_test_dense_normal, _test_copse_frames).

## Proposed budgets (woods perf pass). What's drawn from the densest copse of a normal preset
## (temperate, hot zone 4409): MultiMeshes and triangles in view range, and the shadow pass's
## triangles within the default ("medium") shadow reach. Measured on this PC: before 590 draws,
## 1.70M triangles, ~231k shadow triangles (R0498, temperate forced to the dense layout); after,
## see CHANGELOG (queue item 1.8).
const DENSE_DRAWS_MAX := 600
const DENSE_TRIS_MAX := 700000
const DENSE_SHADOW_TRIS_MAX := 200000
const SHADOW_M := 320.0  # GameSettings "medium" (the default) shadow reach
## A capped sight line (Spotting.foliage_m) 20-250 m through the densest copse, on average (before:
## 4266 us uncapped, R0498), and a 12 m nav chunk's scatter geometry (before 0.75 ms).
const SPOT_US_MAX := 400.0
const NAV_CHUNK_MS_MAX := 0.5
## Standing in the forest's densest copse with its visuals built (headless: no drawing): the frame
## (average, 95th percentile); and a scan round of 16 men's sight lines through it (128 capped
## foliage walks; before, uncapped on the old walk, 649 ms a round, R0519; R0498's 16 AI fighting
## there spent 9.0 ms a frame on them).
const COPSE_FRAME_AVG_MS := 25.0
const COPSE_FRAME_P95_MS := 60.0
const SCAN_ROUND_MS := 30.0

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = "test_forest" + tag  # never touch a real campaign
	get_tree().create_timer(440.0).timeout.connect(func() -> void:
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
	await _test_copse_frames(level, scatter)
	await _test_dense_normal()
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


## The forest's densest copse (woods perf pass): the player standing in its middle with the zone's
## visuals built round him, the frame within COPSE_FRAME_AVG_MS / COPSE_FRAME_P95_MS; and the AI's
## sight lines through it (ZoneScatter.foliage_least as Spotting.foliage_m asks) within
## SCAN_ROUND_MS a scan round.
func _test_copse_frames(level: ZoneLevel, scatter: ZoneScatter) -> void:
	var best := _densest_copse(scatter)
	var c: Vector2 = best.get("centre", Vector2.ZERO)
	var player: Soldier = level.players.get_node(^"1")
	player.global_position = level.ground_point(Vector3(c.x, 0, c.y)) + Vector3(0, 0.2, 0)
	scatter.build_visuals()  # (not on a headless server by itself: built here to count its cost)
	while scatter.build_near(player.global_position, 8) > 0:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	var frames := await _frames(300)
	check(_avg(frames) <= COPSE_FRAME_AVG_MS and _pct(frames, 0.95) <= COPSE_FRAME_P95_MS,
		"woods perf: standing in the forest's densest copse (%d trees, %.0f m round; %d cells drawn round him, %d of them close up): frames %.1f ms on average, 95th percentile %.1f ms (Proposed budgets %.0f / %.0f)"
		% [int(best.get("trees", 0)), float(best.get("r", 0.0)), scatter.built_cells(), scatter.built_near_cells(), _avg(frames), _pct(frames, 0.95), COPSE_FRAME_AVG_MS, COPSE_FRAME_P95_MS])
	# The AI's sight lines through it (Spotting.foliage_m: eyes to head and chest, capped at
	# FOLIAGE_OPAQUE_M): a scan round of 8 men standing in the copse and 8 out round it, 70-126 m
	# off, each checking each of the other side, as SquadAI does every SCAN_S.
	var inside: Array[Vector3] = []
	var outside: Array[Vector3] = []
	for i in 8:
		var a := Vector2.from_angle(i * TAU / 8.0) * float(best.get("r", 10.0)) * 0.6
		inside.append(level.ground_point(Vector3(c.x + a.x, 0, c.y + a.y)))
		var b := Vector2.from_angle(i * TAU / 8.0 + 0.3) * (70.0 + 8.0 * i)
		outside.append(level.ground_point(Vector3(c.x + b.x, 0, c.y + b.y)))
	var hidden := 0
	var started := Time.get_ticks_usec()
	for rep in 10:
		for k in 2:
			var side := inside if k == 0 else outside
			var other := outside if k == 0 else inside
			for p: Vector3 in side:
				for q: Vector3 in other:
					if scatter.foliage_least(p + Vector3(0, 1.6, 0), q + Vector3(0, 1.65, 0), q + Vector3(0, 1.25, 0), Spotting.FOLIAGE_OPAQUE_M) >= Spotting.FOLIAGE_OPAQUE_M:
						hidden += 1
	var round_ms := (Time.get_ticks_usec() - started) / 1000.0 / 10.0
	check(round_ms <= SCAN_ROUND_MS and hidden > 0,
		"woods perf: a scan round of 16 men through the copse (128 sight lines, %d of 128 hidden) takes %.1f ms (Proposed budget %.0f; every %.1f s: %.1f ms a second)"
		% [hidden / 10, round_ms, SCAN_ROUND_MS, SquadAI.SCAN_S, round_ms / SquadAI.SCAN_S])


## A normal preset's dense copses (woods perf pass: temperate, hot zone 4409, now the
## copses-as-cover layout): laid out the same twice (items, copses, the fine index); drawn from its
## densest copse within DENSE_DRAWS_MAX / DENSE_TRIS_MAX / DENSE_SHADOW_TRIS_MAX; every cell's trees
## drawn exactly once (near tier, far tier or far blobs) from near and far; the fine index's sight
## lines the same as the old walk's, capped ones exact below FOLIAGE_OPAQUE_M; sight lines and nav
## chunks within SPOT_US_MAX / NAV_CHUNK_MS_MAX, and the nav boxes the same as from every item.
func _test_dense_normal() -> void:
	var def := ZoneDef.generate_hot(4409)
	def["terrain"] = "temperate"
	def = ZoneDef.normalize(def)
	var t := _preset_terrain(def)
	ZoneScatter.clear_cache(true)
	var a := ZoneScatter.new()
	add_child(a)
	a.generate(t, def)
	var trees_in_copses := 0
	var copses := 0
	for site: Dictionary in a.copse_sites:
		if not site.grove and int(site.trees) > 0:
			copses += 1
			trees_in_copses += int(site.trees)
	ZoneScatter.clear_cache(true)
	var b := ZoneScatter.new()
	b.generate(t, def)
	check(a._cover and a.cache_source == "generated" and b.cache_source == "generated" and a.checksum() == b.checksum() and str(a.copse_sites) == str(b.copse_sites)
		and a._foliage == b._foliage and a._solids == b._solids and copses >= 20 and trees_in_copses >= copses * 25,
		"dense woods: temperate has the dense copses (%d copses, %.0f trees a copse; %s), laid out the same twice, fine index and all"
		% [copses, float(trees_in_copses) / maxi(copses, 1), a.counts])
	b.free()
	var best := _densest_copse(a)
	var c: Vector2 = best.centre
	var eye := Vector3(c.x, t.height_at(c.x, c.y) + 1.7, c.y)
	a.build_visuals()
	while a.build_near(eye, 16) > 0:
		pass
	var drawn := _drawn(a, t, eye)
	check(drawn.draws <= DENSE_DRAWS_MAX and drawn.tris <= DENSE_TRIS_MAX and drawn.shadow_tris <= DENSE_SHADOW_TRIS_MAX,
		"dense woods: from the densest copse (%d trees) %d draws, %d triangles, ~%d in the shadow pass (Proposed budgets %d / %d / %d)"
		% [int(best.trees), drawn.draws, drawn.tris, drawn.shadow_tris, DENSE_DRAWS_MAX, DENSE_TRIS_MAX, DENSE_SHADOW_TRIS_MAX])
	# Near tier to LOD_M, far tier past it, blobs past SEE_TREE_M: each cell's trees drawn once, from
	# the copse and from further and further out (the cells built as the camera comes).
	var bad: Array[String] = []
	var looked := 0
	for off: float in [0.0, 150.0, 260.0, 600.0, 1000.0, 1400.0]:
		var at := eye + Vector3(off, 0, 0)
		while a.build_near(at, 16) > 0:
			pass
		var shown := _trees_shown(a, t, at)
		for cell: Vector2i in shown:
			looked += 1
			if int(shown[cell]) != 1 and bad.size() < 6:
				bad.append("%s from %.0f m out: %d" % [cell, off, shown[cell]])
	check(looked > 100 and bad.is_empty(), "dense woods: every cell's trees drawn exactly once from 6 spots out to 1400 m (%d looks; %s)" % [looked, bad])
	# Sight lines through the copse: the fine index's walk gives the old answers.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	var lines: Array = []
	for k in 1000:
		var p0 := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 30.0)
		var p1 := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 250.0)
		var from := Vector3(p0.x, t.height_at(p0.x, p0.y) + rng.randf_range(0.4, 1.7), p0.y)
		var to := Vector3(p1.x, t.height_at(p1.x, p1.y) + rng.randf_range(0.4, 1.7), p1.y)
		lines.append([from, to, to - Vector3(0, 0.45, 0)])
	var worst := 0.0
	var wrong_cap := 0
	var hidden := 0
	for k in 300:
		var l: Array = lines[k]
		var slow_a := a.foliage_between_slow(l[0], l[1])
		var slow_b := a.foliage_between_slow(l[0], l[2])
		var least := minf(slow_a, slow_b)
		worst = maxf(worst, maxf(absf(a.foliage_between(l[0], l[1]) - slow_a), absf(a.foliage_least(l[0], l[1], l[2]) - least)))
		var capped := a.foliage_least(l[0], l[1], l[2], Spotting.FOLIAGE_OPAQUE_M)
		if least >= Spotting.FOLIAGE_OPAQUE_M:
			hidden += 1
			wrong_cap += 0 if capped >= Spotting.FOLIAGE_OPAQUE_M else 1
		elif absf(capped - least) > 0.0001:
			wrong_cap += 1
	check(worst < 0.0001 and wrong_cap == 0 and hidden > 10 and hidden < 300,
		"dense woods: 300 sight lines through the copse meet the same foliage as walking every item (worst %.6f m off; %d hidden; capped at %.1f m: %d wrong)" % [worst, hidden, Spotting.FOLIAGE_OPAQUE_M, wrong_cap])
	var started := Time.get_ticks_usec()
	for l: Array in lines:
		a.foliage_least(l[0], l[1], l[2], Spotting.FOLIAGE_OPAQUE_M)
	var spot_us := float(Time.get_ticks_usec() - started) / lines.size()
	var boxes := 0
	var all_boxes := 0
	var chunks := 0
	started = Time.get_ticks_usec()
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			boxes += a.boxes_in(Rect2(c.x + dx * 12.0 - 7.0, c.y + dz * 12.0 - 7.0, 14.0, 14.0)).size()
			a.faces_in(Rect2(c.x + dx * 12.0 - 7.0, c.y + dz * 12.0 - 7.0, 14.0, 14.0))
			chunks += 1
	var nav_ms := (Time.get_ticks_usec() - started) / 1000.0 / chunks
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var r := Rect2(c.x + dx * 12.0 - 7.0, c.y + dz * 12.0 - 7.0, 14.0, 14.0)
			for item: Dictionary in a.items:
				if item.solid and not item.has("shape") and r.has_point(Vector2(item.pos.x, item.pos.z)):
					all_boxes += 1
	check(spot_us <= SPOT_US_MAX and nav_ms <= NAV_CHUNK_MS_MAX and boxes == all_boxes and boxes > 0,
		"dense woods: a capped sight line through the copse %.0f us (Proposed budget %.0f), a nav chunk's scatter %.2f ms (budget %.1f), %d trunk and rock boxes as from every item (%d)"
		% [spot_us, SPOT_US_MAX, nav_ms, NAV_CHUNK_MS_MAX, boxes, all_boxes])
	a.free()
	t.free()
	ZoneScatter.clear_cache()


## The copse (not a grove) with the most trees in `scatter`'s fresh layout.
func _densest_copse(scatter: ZoneScatter) -> Dictionary:
	var best := {}
	for site: Dictionary in scatter.copse_sites:
		if not site.grove and (best.is_empty() or int(site.trees) > int(best.trees)):
			best = site
	return best


## What `scatter` draws seen from `eye` (its built MultiMeshes by their visibility ranges, measured
## from their "centre" meta, a far-tier node hidden while its visibility parent shows): {"draws",
## "tris", "shadow_tris"} (shadow casters within SHADOW_M, in about two cascades each).
func _drawn(scatter: ZoneScatter, t: ZoneTerrain, eye: Vector3) -> Dictionary:
	var out := {"draws": 0, "tris": 0, "shadow_tris": 0}
	var tris := {}
	for node: Node in scatter.get_children():
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or not mmi.has_meta(&"centre") or not _shows(mmi, eye):
			continue
		var mesh := mmi.multimesh.mesh
		if not tris.has(mesh):
			var arrays := mesh.surface_get_arrays(0)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			tris[mesh] = (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var n := mmi.multimesh.instance_count * int(tris[mesh])
		out.draws += 1
		out.tris += n
		var d := Vector2(eye.x, eye.z).distance_to(Vector2((mmi.get_meta(&"centre") as Vector3).x, (mmi.get_meta(&"centre") as Vector3).z))
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and d < SHADOW_M + ZoneScatter.CELL_M * 0.71:
			out.shadow_tris += n * 2
	return out


## Whether `node` shows from `eye` by its visibility range (from its "centre" meta) and its
## visibility parent's (hidden while the parent shows).
func _shows(node: GeometryInstance3D, eye: Vector3) -> bool:
	var centre: Vector3 = node.get_meta(&"centre")
	var d := Vector2(eye.x, eye.z).distance_to(Vector2(centre.x, centre.z))
	if d < node.visibility_range_begin or (node.visibility_range_end > 0.0 and d > node.visibility_range_end):
		return false
	if not node.visibility_parent.is_empty():
		var parent := node.get_node_or_null(node.visibility_parent) as GeometryInstance3D
		if parent == null or _shows(parent, eye):
			return false
	return true


## For every cell holding trees: how many of its tree drawings show from `eye`: its near tier's
## trunks, its far tier's stand-ins, its block's far blobs.
func _trees_shown(scatter: ZoneScatter, t: ZoneTerrain, eye: Vector3) -> Dictionary:
	var out := {}
	var blobs := {}
	for node: Node in scatter.get_children():
		var name := String(node.name)
		if name.begins_with("Far_"):
			blobs[Vector2i(int(name.get_slice("_", 1)), int(name.get_slice("_", 2)))] = node
	for cell: Vector2i in scatter._cells:
		var has_trees := false
		for index: int in scatter._cells[cell]:
			if int(scatter.items[index].kind) == ZoneScatter.Kind.TREE:
				has_trees = true
				break
		if not has_trees:
			continue
		var n := 0
		for key: String in ["trunk", "trunk_lod"]:
			var node := scatter.get_node_or_null("Scatter_%d_%d_%s" % [cell.x, cell.y, key]) as GeometryInstance3D
			if node and _shows(node, eye):
				n += 1
		var block := Vector2i(floori(cell.x / float(ZoneScatter.FAR_BLOCK)), floori(cell.y / float(ZoneScatter.FAR_BLOCK)))
		if blobs.has(block) and _shows(blobs[block], eye):
			n += 1
		out[cell] = n
	return out


func _frames(n: int) -> Array[float]:
	var out: Array[float] = []
	var prev := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		out.append((now - prev) / 1000.0)
		prev = now
	return out


func _avg(values: Array[float]) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxi(values.size(), 1)


func _pct(values: Array[float], p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * p), sorted.size() - 1)] if not sorted.is_empty() else 0.0


## A zone's terrain on its own (as world_test's): its pads flat.
func _preset_terrain(def: Dictionary) -> ZoneTerrain:
	var flat: Array = []
	for m: Dictionary in def.modules:
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		flat.append(Rect2(p - half, half * 2.0))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	var t := ZoneTerrain.new()
	t.generate(def, flat)
	return t


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
