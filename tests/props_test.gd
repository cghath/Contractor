extends Node
## The prop library (cghath's queue item 1.7, docs/cg_brief.md: "at least triple today's outdoor
## set"): PropArt's shapes, ZoneProps' layout over the campaign's zones, ZoneScatter's collision
## and rounds through props by their material, the AI's cover behind them, ZoneAnimals. Two
## processes over real ENet, like the world suite:
##   <exe> --headless --path . res://tests/props_test.tscn -- --props-host
##   <exe> --headless --path . res://tests/props_test.tscn -- --props-join 127.0.0.1
## The host checks the library and every campaign zone's layout, then hosts ZONE and checks the
## live props (placement, collision as drawn, rounds by material, cover, animals) with new
## connections refused, then lets the client in. The client (joining late) checks it laid the
## same props and has the host's animals where the host has them, the one the host shot dead.
## Each process prints PROPS TEST PASSED/FAILED and exits with its failure count.

## The zone hosted for the live checks: temperate, with a generated town and grown villages.
const ZONE := "old_orchards"
## PROP items over the campaign's zones before the library (crates, drums, debris, ruins, box
## wrecks), measured on claude/ai-driving 878a8de5 (2026-10-21) with the same zone defs.
const PROPS_BEFORE := 390
## The library's own layout in a zone, the worst over the campaign's (ms, headless). Proposed.
const BUDGET_LAYOUT_MS := 1200.0
## Rays across a test prop that may disagree with what's drawn (its edges, out of 41 a height).
const RAY_SLACK := 2
## How far the client's animals may be from the host's when it asks (m: a dog's 1.4 m/s over a
## packet's gap and the trip).
const ANIMAL_SLACK_M := 1.5
## How long the host's animals stand still while the client compares (s; _ask_digest).
const DIGEST_STILL_S := 10.0

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier
var _host_digest := {}
var _client_left := false
var _test_bodies: Array[Node] = []
var _layout_checksum := 0
var _layout_size := 0
var _layout_library := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_props" + tag  # never touch a real save
	Campaign.campaign_id = "test_props" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	var args := OS.get_cmdline_user_args()
	get_tree().create_timer(470.0, true, false, true).timeout.connect(func() -> void:
		print("PROPS TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--props-join" in args:
		await _run_client(args[args.find("--props-join") + 1] if args.find("--props-join") + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		await _run_host("--props-host" in args)


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
	print("PROPS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


# --- Host -------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	_test_library()
	_test_zones()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(ZONE))
	check(multiplayer.multiplayer_peer is ENetMultiplayerPeer, "hosting %s on port %d" % [ZONE, Net.port()])
	level = CompoundLevel.current(self) as ZoneLevel
	if level == null or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		check(false, "the zone is up")
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	_layout_checksum = level.scatter.checksum()  # (before the test props join its items)
	_layout_size = level.scatter.items.size()
	_layout_library = level.scatter.library_count
	_test_placement()
	await _test_shapes()
	await _test_rounds()
	await _test_cover()
	await _test_animals()
	for n in _test_bodies:
		n.queue_free()
	if not wait_for_client:
		_finish()
		return
	print("[host] waiting for the client")
	Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	await _wait_for(func() -> bool: return _client_left, 300.0)
	_finish()


## The library: at least three times today's outdoor set, every group the brief names, every
## shape with collision and a material for each part.
func _test_library() -> void:
	print("The library")
	var statics := PropArt.NAMES.filter(func(n: String) -> bool: return not n in PropArt.ANIMALS)
	var after := PropArt.BEFORE.size() + PropArt.NAMES.size()
	check(after >= PropArt.BEFORE.size() * 3, "the outdoor set: %d before (%s), %d after with the library's %d (%d static props and %s)"
		% [PropArt.BEFORE.size(), ", ".join(PropArt.BEFORE), after, PropArt.NAMES.size(), statics.size(), ", ".join(PropArt.ANIMALS)])
	var groups := {"street furniture": ["street_lamp", "utility_pole", "sign_stop", "bus_shelter"], "market": ["market_stall", "shop_awning"],
		"fences and gates": ["fence_rail", "fence_chainlink", "wall_stone", "gate_farm"], "power lines": ["pylon", "power_pole_h"],
		"water and farm": ["well", "water_tower", "irrigation_channel", "hay_round"], "animals": ["goat", "sheep", "dog"],
		"vehicles": ["car_sedan", "truck_cargo", "hulk_car", "hulk_truck"], "containers": ["container_20", "container_40"],
		"graves": ["headstone", "grave_cross", "tomb"], "sites": ["generator", "sat_dish", "laundry_line", "hay_square"]}
	var missing: Array = []
	for g: String in groups:
		for n: String in groups[g]:
			if not PropArt.has(n):
				missing.append(n)
	check(missing.is_empty(), "every group the brief names is in it (%s)%s" % [", ".join(groups.keys()), "" if missing.is_empty() else ": missing %s" % [missing]])
	var bad: Array = []
	for n: String in statics:
		var solid := 0
		for part: Dictionary in PropArt.parts(n):
			if part.solid:
				solid += 1
				if not PropArt.MATERIALS.has(PropArt.material_of(n, part)):
					bad.append("%s (material %s)" % [n, PropArt.material_of(n, part)])
		if solid == 0:
			bad.append("%s (no collision)" % n)
	check(bad.is_empty(), "every static prop type has collision, each part a known material (%d types)%s" % [statics.size(), "" if bad.is_empty() else ": %s" % [bad]])


## Every campaign zone's layout: the props tripled, every shape used somewhere, the same seed the
## same props (and from the disk cache), another seed others, the layout inside its budget.
func _test_zones() -> void:
	print("The campaign's zones")
	var total := 0
	var library := 0
	var used := {}
	var styles := {}
	var worst_ms := 0.0
	var worst_zone := ""
	var towns := 0
	var town_props := 0
	var pylons := 0
	var farms := 0
	var animals := 0
	var watered := 0
	var wet := 0
	var wet_at := ""
	var landmarks := 0
	var on_landmark := 0
	ZoneScatter.clear_cache(true)  # (this code's layouts, not ones cached on disk by an older build)
	for z: Dictionary in MissionRegistry.zones():
		var def := MissionRegistry.zone_def(String(z.zone_id))
		if def.is_empty():
			continue
		var t := _terrain_of(def)
		ZoneScatter.clear_cache()
		var s := ZoneScatter.new()
		s.generate(t, def)
		total += int(s.counts[ZoneScatter.Kind.PROP])
		library += s.library_count
		styles[ZoneProps.style_for(t.preset_id)] = true
		var r := s.props_report
		if float(r.get("ms", 0.0)) > worst_ms:
			worst_ms = float(r.get("ms", 0.0))
			worst_zone = String(z.zone_id)
		towns += int(r.get("towns", 0))
		town_props += int(r.get("town_props", 0))
		pylons += int(r.get("pylons", 0))
		farms += int(r.get("farms", 0))
		animals += int(r.get("animals", 0))
		var landmark_pads: Array[Rect2] = []
		for i in mini((def.modules as Array).size(), t.pads.size()):
			if String(def.modules[i].type).begins_with(ZoneModules.LANDMARK):
				landmark_pads.append(t.pads[i][0])
		landmarks += landmark_pads.size()
		if t.water:
			watered += 1
		for item: Dictionary in s.items:
			if item.has("shape"):
				used[String(item.shape)] = true
				var p := Vector2((item.pos as Vector3).x, (item.pos as Vector3).z)
				if t.water and t.water.keeps_clear(p.x, p.y):
					wet += 1
					wet_at = "%s %s at %s" % [z.zone_id, item.shape, p]
				for pad: Rect2 in landmark_pads:
					if pad.has_point(p):
						on_landmark += 1
		s.free()
		t.free()
	check(total >= PROPS_BEFORE * 3, "the props tripled: %d over the campaign's zones (%d before), %d of them the library's" % [total, PROPS_BEFORE, library])
	var unused := PropArt.NAMES.filter(func(n: String) -> bool: return not used.has(n))
	check(unused.is_empty(), "every prop type is laid somewhere in the campaign (%d of %d)%s" % [used.size(), PropArt.NAMES.size(), "" if unused.is_empty() else ": never %s" % [unused]])
	check(towns > 0 and town_props >= towns * 20 and pylons >= 100 and farms >= 10 and animals >= 50,
		"towns get their streets furnished (%d towns, %d props), the countryside pylons (%d) and farms (%d), %d animals; styles %s" % [towns, town_props, pylons, farms, animals, styles.keys()])
	check(watered > 0 and wet == 0, "no prop in a river, a lake, on a wet bank or a bridge (%d zones with water, %d in it%s)" % [watered, wet, "" if wet == 0 else ": %s" % wet_at])
	check(landmarks > 0 and on_landmark == 0, "no library prop on a landmark's pad: it builds its own (%d landmarks, %d on one)" % [landmarks, on_landmark])
	check(worst_ms <= BUDGET_LAYOUT_MS, "the library's layout takes at most %.0f ms a zone (%s; Proposed budget %.0f)" % [worst_ms, worst_zone, BUDGET_LAYOUT_MS])
	# Same seed, same props; from the disk cache too; another seed others.
	var def := MissionRegistry.zone_def(ZONE)
	var ta := _terrain_of(def)
	ZoneScatter.clear_cache(true)
	var a := ZoneScatter.new()
	a.generate(ta, def)
	ZoneScatter.clear_cache()
	var b := ZoneScatter.new()
	b.generate(_terrain_of(def), def)
	ZoneScatter.clear_cache(true)
	var c := ZoneScatter.new()
	c.generate(_terrain_of(def), def)
	var other_def := def.merged({"seed": int(def.seed) + 1}, true)
	var d := ZoneScatter.new()
	d.generate(_terrain_of(other_def), other_def)
	var same_shapes := a.items.size() == b.items.size()
	if same_shapes:
		for i in a.items.size():
			if String(a.items[i].get("shape", "")) != String(b.items[i].get("shape", "")) or int(a.items[i].get("paint", 0)) != int(b.items[i].get("paint", 0)) \
					or int(a.items[i].get("link", 0)) != int(b.items[i].get("link", 0)):
				same_shapes = false
				break
	check(a.checksum() == c.checksum() and a.library_count > 0 and same_shapes and b.cache_source == "disk" and b.checksum() == a.checksum()
		and b.library_count == a.library_count and d.checksum() != a.checksum(),
		"same seed, same props (%d library props, checksum %d; again from the %s cache, %d): another seed, other props" % [a.library_count, a.checksum(), b.cache_source, b.library_count])
	ZoneScatter.clear_cache()


func _terrain_of(def: Dictionary) -> ZoneTerrain:
	var flat: Array = []
	for m: Dictionary in def.modules:
		flat.append(ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))))  # (as ZoneLevel._flat_areas)
	for p: Array in def.get("extraction", []):
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.get("insertion", []):
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	var t := ZoneTerrain.new()
	t.generate(def, flat)
	return t


## Where the hosted zone's props stand: towns' street props on their streets and clear of every
## box they're built of; nothing else on a pad; nothing but a checkpoint's barriers on a road;
## wires from pole to pole; containers and generators by the sites.
func _test_placement() -> void:
	print("Placement in %s" % ZONE)
	var s := level.scatter
	var town_rects: Array = []
	var pads: Array = []
	for m in level.modules():
		var r := m.footprint()
		if ZoneModules.base(m.type) == "town":
			var boxes: Array = []
			for box: AABB in ZoneModules.boxes_m(m.type):
				if box.position.y < 2.0:
					boxes.append(Rect2(box.position.x + m.global_position.x, box.position.z + m.global_position.z, box.size.x, box.size.z))
			town_rects.append([r, boxes])
	for pad: Array in level.terrain.pads:
		pads.append(pad[0])
	var on_pad := 0
	var in_town := 0
	var in_buildings := 0
	var on_road := 0
	var links := 0
	var long_links := 0
	var by_site := 0
	for i in s.items.size():
		var item: Dictionary = s.items[i]
		if not item.has("shape") or int(item.kind) != ZoneScatter.Kind.PROP:
			continue
		var p := Vector2((item.pos as Vector3).x, (item.pos as Vector3).z)
		var town: Array = []
		for t: Array in town_rects:
			if (t[0] as Rect2).has_point(p):
				town = t
		if not town.is_empty():
			in_town += 1
			var foot := PropArt.foot(String(item.shape))
			var xf := ZoneScatter.library_transform(item)
			for corner: Vector3 in [Vector3(foot.position.x, 0, foot.position.z), Vector3(foot.end.x, 0, foot.position.z), Vector3(foot.position.x, 0, foot.end.z), Vector3(foot.end.x, 0, foot.end.z)]:
				var w := xf * (corner * 0.9)
				for box: Rect2 in town[1]:
					if box.has_point(Vector2(w.x, w.z)):
						in_buildings += 1
		else:
			for r: Rect2 in pads:
				if r.has_point(p):
					on_pad += 1
		if String(item.shape) != "jersey_barrier":
			for road: Array in level.def.get("roads", []):
				var a := Vector2(float(road[0][0]), float(road[0][1]))
				var b := Vector2(float(road[1][0]), float(road[1][1]))
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < ZoneProps.ROAD_HALF_M and town.is_empty():
					on_road += 1
		if int(item.get("link", 0)) == 1:
			links += 1
			var span := (item.pos as Vector3).distance_to(s.items[i - 1].pos)
			var most := ZoneProps.PYLON_STEP_M * ZoneProps.LINK_STEPS + 2.0
			if span > most and span <= most * 2.0 and level.terrain.water:  # over a river: one footing skipped
				var q: Vector3 = s.items[i - 1].pos
				var over := false
				for k in range(1, 40):
					var w := q.lerp(item.pos, k / 40.0)
					over = over or level.terrain.water.keeps_clear(w.x, w.z)
				if over:
					most *= 2.0
			if span > most or not s.items[i - 1].has("shape"):
				long_links += 1
		if String(item.shape) in ["container_20", "container_40", "container_stack", "generator"]:
			for m in level.modules():
				if m.footprint().grow(ZoneTerrain.PAD_MARGIN_M + ZoneProps.SITE_RING_M[1] + 8.0).has_point(p):
					by_site += 1
					break
	check(in_town >= 20 and in_buildings == 0, "%d props on the town's streets, none in its buildings or barricades (%d corners in)" % [in_town, in_buildings])
	check(on_pad == 0 and on_road == 0, "nothing else on a pad (%d) or a road (%d)" % [on_pad, on_road])
	check(links >= 10 and long_links == 0, "%d wire spans, each from a pole or pylon to the next (%d too long)" % [links, long_links])
	check(by_site >= 3, "%d containers and generators by the sites" % by_site)


## Every static shape on a test body up in the air: what collides is what's drawn (the boxes of
## its drawn and colliding parts agree, rays across it hit where its triangles are); see-through
## parts stop men (Soldier.BODY_LAYER) but not rays on the world layer.
func _test_shapes() -> void:
	print("Collision as drawn")
	var s := level.scatter
	var statics := PropArt.NAMES.filter(func(n: String) -> bool: return not n in PropArt.ANIMALS)
	var items: Array = []
	for k in statics.size():
		var item := {"kind": ZoneScatter.Kind.PROP, "shape": statics[k], "paint": 0, "pos": Vector3(-700.0 + k * 20.0, 420.0, 30.0), "yaw": 0.7,
			"size": Vector3.ONE, "colour": Color.WHITE, "solid": true, "link": 0}
		_test_body(s, item, "PropTest_%s" % statics[k])
		items.append(item)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := level.get_world_3d().direct_space_state
	var box_bad: Array = []
	var ray_bad: Array = []
	var through_bad: Array = []
	for k in items.size():
		var item: Dictionary = items[k]
		var shape := String(item.shape)
		var xf := ZoneScatter.library_transform(item)
		var drawn := AABB()
		var first := true
		for part: Dictionary in PropArt.parts(shape):
			if not bool(part.get("draw", true)):
				continue
			for c: Vector3 in part.pts:
				drawn = AABB(xf * c, Vector3.ZERO) if first else drawn.expand(xf * c)
				first = false
		var collides := AABB()
		first = true
		for part: Array in s.collision_parts(item):
			for c: Vector3 in (part[0] as ConvexPolygonShape3D).points:
				collides = AABB(part[1] * c, Vector3.ZERO) if first else collides.expand(part[1] * c)
				first = false
		var d := maxf((drawn.position - collides.position).abs()[(drawn.position - collides.position).abs().max_axis_index()],
			(drawn.end - collides.end).abs()[(drawn.end - collides.end).abs().max_axis_index()])
		if d > 0.04:
			box_bad.append("%s %.3f m" % [shape, d])
		# Rays across at three heights through what stands on the ground.
		var tris := PropArt.triangles(shape, true)
		for i in tris.size():
			tris[i] = xf * tris[i]
		var foot := PropArt.foot(shape)
		var across := Vector3(0.3, 0, 1).normalized()
		var side := across.cross(Vector3.UP).normalized()
		var centre := xf * foot.get_center()
		var reach := maxf(foot.size.x, foot.size.z) * 0.75 + 0.3
		for f: float in [0.23, 0.51, 0.79]:  # (off the faces' own heights: a ray along a face grazes it)
			var y := (item.pos as Vector3).y + foot.position.y + foot.size.y * f
			var hits := 0
			var wrong := 0
			for r in 41:
				var off := (float(r) / 40.0 - 0.5) * 2.0 * reach
				var from := Vector3(centre.x, y, centre.z) + side * off - across * (reach + 1.0)
				var to := from + across * (reach * 2.0 + 2.0)
				var drawn_hit := false
				for t in range(0, tris.size(), 3):
					if Geometry3D.segment_intersects_triangle(from, to, tris[t], tris[t + 1], tris[t + 2]) != null:
						drawn_hit = true
						break
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
				var hit_it := not hit.is_empty() and String((hit.collider as Node).name) == "PropTest_%s" % shape
				hits += 1 if hit_it else 0
				wrong += 1 if hit_it != drawn_hit else 0
			if wrong > RAY_SLACK:
				ray_bad.append("%s at %.0f%%: %d of 41 disagree (%d hit)" % [shape, f * 100.0, wrong, hits])
		# See-through parts: men stop, sight and rounds don't.
		var see := PropArt.parts(shape).filter(func(p: Dictionary) -> bool: return p.solid and PropArt.material_of(shape, p) == PropArt.SEE_THROUGH)
		if not see.is_empty():
			var at := xf * _centre(see[0].pts)
			var from := at - xf.basis.z.normalized() * 2.0
			var to := at + xf.basis.z.normalized() * 2.0
			var sight := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			var men := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Soldier.BODY_LAYER))
			if not sight.is_empty() or men.is_empty():
				through_bad.append(shape)
	check(box_bad.is_empty(), "every prop's collision covers what's drawn, to 4 cm (%d types)%s" % [items.size(), "" if box_bad.is_empty() else ": %s" % [box_bad]])
	check(ray_bad.is_empty(), "rays across every prop at three heights hit where it's drawn (%d types, at most %d of 41 off at its edges)%s" % [items.size(), RAY_SLACK, "" if ray_bad.is_empty() else ": %s" % [ray_bad]])
	check(through_bad.is_empty(), "chain-link and barbed wire stop men, not sight or rounds%s" % ("" if through_bad.is_empty() else ": %s" % [through_bad]))


static func _centre(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p / float(pts.size())
	return c


## A test body for `item` under the scatter (as build_collision makes them: its parts tagged for
## round_through), named `body_name`; the item joins the scatter's items unless `append` is false
## (it's in already).
func _test_body(s: ZoneScatter, item: Dictionary, body_name: String, append := true) -> void:
	var index := s.items.size()
	if append:
		s.items.append(item)
	else:
		index = s.items.find(item)  # (already in: ZoneScatter._add)
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	s.add_child(body)
	var through := StaticBody3D.new()
	through.name = body_name + "_through"
	through.collision_layer = Soldier.BODY_LAYER
	through.collision_mask = 0
	s.add_child(through)
	for part: Array in s.collision_parts(item):
		var shape := CollisionShape3D.new()
		shape.shape = part[0]
		shape.transform = part[1]
		shape.set_meta(&"prop", Vector2i(index, int(part[2])))
		(through if bool(part[3]) else body).add_child(shape)
	_test_bodies.append_array([body, through])


## Rounds by material (PropArt.MATERIALS): through wood rails and boards, a car's cabin, a shipping
## container and chain-link; stopped by a car's engine bay, concrete, mud brick and a hay bale;
## a pistol round stopped where a rifle round gets through. The AI's soft-cover test agrees.
func _test_rounds() -> void:
	print("Rounds by material")
	var s := level.scatter
	# [shape, aim (its own metres), weapon, expect through]
	var cases := [
		["fence_rail", Vector3(0, 0.5, 0), &"m4a1", true], ["fence_rail", Vector3(0, 0.5, 0), &"m17", true],
		["fence_board", Vector3(0, 1.0, 0.045), &"m17", true], ["jersey_barrier", Vector3(0, 0.5, 0), &"m4a1", false],
		["car_sedan", Vector3(-0.4, 1.15, 0), &"m4a1", true], ["car_sedan", Vector3(-0.4, 1.15, 0), &"m17", false],
		["car_sedan", Vector3(1.8, 0.6, 0), &"m4a1", false], ["hulk_car", Vector3(-0.4, 0.9, 0), &"m4a1", true],
		["container_20", Vector3(0, 1.3, 0), &"m4a1", true], ["container_20", Vector3(0, 1.3, 0), &"m17", false],
		["hay_round", Vector3(0, 0.72, 0), &"m4a1", false], ["wall_mud", Vector3(0, 0.8, 0), &"m4a1", false],
		["fence_chainlink", Vector3(0, 1.0, 0), &"m17", true], ["generator", Vector3(0, 0.8, 0), &"m4a1", false],
	]
	var bodies: Array = []
	for k in cases.size():
		var c: Array = cases[k]
		var item := {"kind": ZoneScatter.Kind.PROP, "shape": c[0], "paint": 0, "pos": Vector3(-600.0 + k * 25.0, 460.0, -40.0), "yaw": 0.0,
			"size": Vector3.ONE, "colour": Color.WHITE, "solid": true, "link": 0}
		_test_body(s, item, "RoundTest_%d" % k)
		bodies.append(item)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lines: Array = []
	var bad := 0
	for k in cases.size():
		var c: Array = cases[k]
		var item: Dictionary = bodies[k]
		var at := ZoneScatter.library_transform(item) * (c[1] as Vector3)
		var from := at - Vector3(0, 0, 12.0)
		player.global_position = from - Vector3(0, 1.6, 0)
		var result := Ballistics.fire(player, from, Vector3(0, 0, 1), ItemDB.get_item(c[2]))
		var through := String(result.get("result", "")) == "none"
		var soft := not VoxelWorld.stops_round_in(player, from, at + Vector3(0, 0, 6.0), SquadAI.SOFT_COVER_TEST_J)
		var ok: bool = through == bool(c[3]) and (soft == through or c[2] != &"m4a1")
		bad += 0 if ok else 1
		lines.append("%s%s %s %s" % ["" if ok else "WRONG ", c[0], c[2], "through" if through else "stopped"])
	check(bad == 0, "rounds through or stopped by each prop's material, and the AI's soft-cover test agrees (%s)" % ", ".join(lines))


## The AI finds cover behind a shipping container: one laid (as ZoneProps lays them: into the
## layout, so the navigation bakes round it) on open, flat ground with nothing else near to hide
## behind, the threat off its end; the spot it picks is hidden from the threat by that container.
func _test_cover() -> void:
	print("Cover behind props")
	var s := level.scatter
	var t := level.terrain
	var ground: Variant = _open_ground(12.0)
	check(ground != null, "open, flat ground with nothing on it to put a container on (%s)" % [ground])
	if ground == null:
		return
	var at: Vector2 = ground
	var foot := PropArt.foot("container_20")
	var lowest := INF
	for c: Vector2 in [Vector2(foot.position.x, foot.position.z), Vector2(foot.end.x, foot.position.z), Vector2(foot.position.x, foot.end.z), Vector2(foot.end.x, foot.end.z), Vector2.ZERO]:
		lowest = minf(lowest, t.height_at(at.x + c.x, at.y + c.y))
	var pick := {"kind": ZoneScatter.Kind.PROP, "shape": "container_20", "paint": 0, "pos": Vector3(at.x, lowest, at.y), "yaw": 0.0,
		"size": Vector3.ONE, "colour": Color.WHITE, "solid": true, "link": 0}
	s._add(pick)
	_test_body(s, pick, "CoverTest", false)
	var p: Vector3 = pick.pos
	var xf := ZoneScatter.library_transform(pick)
	var out := xf.basis.x.normalized()  # the threat off its end: down its length (a container's 6 m of steel stops a rifle round; its side doesn't)
	var threat := level.ground_point(p + out * 25.0)
	var anchor := level.ground_point(p - out * (PropArt.foot(String(pick.shape)).size.x * 0.5 + 3.0) + xf.basis.z.normalized() * 2.5)
	player.global_position = level.ground_point(p - out * 14.0) + Vector3(0, 0.2, 0)
	var soldier := level.spawn_soldier({"name": "PropCover", "faction": "hostile", "variant": "urban", "pos": anchor + Vector3(0, 0.15, 0),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "mode": "aware", "guard": true})
	var nav := level.get_node_or_null(^"Navigation") as ZoneNav
	for i in 30:
		await get_tree().physics_frame
	if nav:
		nav.refresh()  # (the new soldier's chunks wanted now, not at the next update)
	await _wait_for(func() -> bool: return nav == null or nav.is_settled(), 40.0)
	for i in 10:
		await get_tree().physics_frame
	var ai := SquadAI.of(soldier)
	ai.body.threat_pos = threat
	ai._has_cover = false
	var spot: Variant = ai.find_cover(soldier.global_position, 10.0)
	var hidden := false
	var by_it := false
	if spot != null:
		var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(threat + Vector3.UP * 1.5, (spot as Vector3) + Vector3.UP * 0.9, 1))
		hidden = not hit.is_empty()
		var body := hit.get("collider") as CollisionObject3D  # (a module's voxels aren't one)
		if hidden and body != null:
			var owner := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as Node
			by_it = owner != null and owner.has_meta(&"prop") and is_same(s.items[(owner.get_meta(&"prop") as Vector2i).x], pick)
	check(spot != null and hidden and by_it, "the AI takes cover behind the %s from a threat 25 m off its end (spot %s, %.1f m from it; hidden %s, by it %s)"
		% [pick.shape, spot, (spot as Vector3).distance_to(p) if spot != null else -1.0, hidden, by_it])
	soldier.vitals.server_kill()


## A spot (x, z) of flat, open ground: nothing solid (rocks, trees, props) within `r` m, no road
## within `r`, the sites 40 m off, the ground within 0.6 m of level over `r` round; null if none.
func _open_ground(r: float) -> Variant:
	var s := level.scatter
	var t := level.terrain
	var half := t.size_m * 0.5 - 80.0
	var step := 11.0
	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var p := Vector2(x, z)
			z += step
			if level.modules().any(func(m: ZoneModule) -> bool: return m.footprint().grow(40.0).has_point(p)):
				continue
			var lo := INF
			var hi := -INF
			for k in 9:
				var q := p + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * (r if k < 8 else 0.0)
				var h := t.height_at(q.x, q.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
			if hi - lo > 0.6 or (t.sea_side >= 0 and lo < t.sea_level + 1.0):
				continue
			var roads := false
			for road: Array in level.def.get("roads", []):
				roads = roads or Geometry2D.get_closest_point_to_segment(p, Vector2(road[0][0], road[0][1]), Vector2(road[1][0], road[1][1])).distance_to(p) < r
			if roads:
				continue
			var clear := true
			var cell := s._cell_of(p.x, p.y)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					for index: int in s._cells.get(cell + Vector2i(dx, dz), []):
						var other: Dictionary = s.items[index]
						if other.solid and Vector2((other.pos as Vector3).x, (other.pos as Vector3).z).distance_to(p) < r:
							clear = false
			if clear:
				return p
		x += step
	return null


## The animals: there, wandering in their homes, and a round kills one.
func _test_animals() -> void:
	print("Animals")
	var zoo := level.scatter.get_node_or_null(^"Animals") as ZoneAnimals
	check(zoo != null and zoo.animals.size() > 0, "the zone has animals (%d: %s)" % [zoo.animals.size() if zoo else 0,
		", ".join(zoo.animals.map(func(a: Dictionary) -> String: return a.species)) if zoo else ""])
	if zoo == null or zoo.animals.is_empty():
		return
	var start: Array = zoo.animals.map(func(a: Dictionary) -> Vector2: return a.pos)
	await get_tree().create_timer(12.0).timeout
	var moved := 0
	var strays := 0
	for i in zoo.animals.size():
		var a: Dictionary = zoo.animals[i]
		if (a.pos as Vector2).distance_to(start[i]) > 0.3:
			moved += 1
		var local := ((a.pos as Vector2) - (a.home.c as Vector2)).rotated(float(a.home.yaw))
		if absf(local.x) > float(a.home.half.x) + 0.5 or absf(local.y) > float(a.home.half.y) + 0.5:
			strays += 1
	check(moved * 3 >= zoo.animals.size() and strays == 0 and zoo.sent > 0, "they wander: %d of %d moved in 12 s, none out of its home (%d), %d packets sent" % [moved, zoo.animals.size(), strays, zoo.sent])
	# Shoot one.
	var a: Dictionary = zoo.animals[0]
	var p: Vector2 = a.pos
	var body := Vector3(p.x, level.terrain.height_at(p.x, p.y) + 0.6, p.y)
	var from := body + Vector3(0, 3.0, 0.0)  # (from above: a pen's wall in the way would take it)
	player.global_position = from - Vector3(0, 1.6, 0)
	var alive := zoo.alive_count()
	var result := Ballistics.fire(player, from, (body - from).normalized(), ItemDB.get_item(&"m4a1"))
	check(not a.alive and zoo.alive_count() == alive - 1, "a round kills the %s it hits (%s; %d alive)" % [a.species, result.get("result", "?"), zoo.alive_count()])


@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	var asker := multiplayer.get_remote_sender_id()
	# The animals stand still for the comparison, and a few packets go out first: the client
	# compares the reply with the last packet it has, and a client that stalls a second or two
	# (CI, just in the zone) took the reply with packets sent after it, the animals by then
	# metres on from where the reply had them ("worst 2.85 m off", CI run 40604654761 on dev,
	# 6a52a7f; green on the same commit in 40602801148).
	var zoo := level.scatter.get_node_or_null(^"Animals") as ZoneAnimals
	if zoo:
		for a: Dictionary in zoo.animals:
			a.wait = maxf(float(a.wait), DIGEST_STILL_S)
	await get_tree().create_timer(ZoneAnimals.SEND_S * 3.0).timeout
	_reply_digest.rpc_id(asker, _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var out := {"checksum": _layout_checksum if multiplayer.is_server() else level.scatter.checksum(), "library": _layout_library if multiplayer.is_server() else level.scatter.library_count, "animals": []}
	var zoo := level.scatter.get_node_or_null(^"Animals") as ZoneAnimals
	if zoo:
		for a: Dictionary in zoo.animals:
			out.animals.append([a.species, (a.pos as Vector2).x, (a.pos as Vector2).y, a.alive])
	return out


# --- Client -----------------------------------------------------------------------------------

func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 440000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	print("Client joining late")
	check(joined[0], "joined the host")
	if not joined[0]:
		_finish()
		return
	await _wait_for(func() -> bool: return CompoundLevel.current(self) is ZoneLevel, 60.0)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the zone loaded on the client")
	if level == null:
		_finish()
		return
	var zoo := level.scatter.get_node_or_null(^"Animals") as ZoneAnimals
	await _wait_for(func() -> bool: return zoo != null and zoo.received >= 4, 20.0)
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 10.0)
	var mine := _digest()
	check(_host_digest.get("checksum") == mine.checksum and _host_digest.get("library") == mine.library and int(mine.library) > 0,
		"the same props as the host's from the seed (%d library props, checksum %d)" % [mine.library, mine.checksum])
	var theirs: Array = _host_digest.get("animals", [])
	var worst := 0.0
	var same := theirs.size() == (mine.animals as Array).size() and not theirs.is_empty()
	var dead := 0
	if same:
		for i in theirs.size():
			var h: Array = theirs[i]
			var c: Array = mine.animals[i]
			same = same and h[0] == c[0] and h[3] == c[3]
			worst = maxf(worst, Vector2(h[1], h[2]).distance_to(Vector2(c[1], c[2])))
			dead += 0 if c[3] else 1
	check(same and worst <= ANIMAL_SLACK_M and dead >= 1, "the host's animals, where the host has them (%d; worst %.2f m off), the one it shot dead here too (%d dead; %d packets)"
		% [theirs.size(), worst, dead, zoo.received if zoo else 0])
	_finish()
