extends Node
## City zones (queue item 1.5, cghath 2026-10-22; docs/building_gen.md "City zones") and village
## houses (queue item 1.6). Headless; never touches a real save.
## - A city generates from its seed: its street grid (BuildingGen.city_layout: blocks, streets,
##   junctions), every block (BuildingGen.city_block) with its buildings in the storeys asked for
##   (CITY_CORE_STOREYS in the core, CITY_OUTSKIRT_STOREYS on the outskirts, CITY_TOWER_STOREYS in
##   its towers), a stair up to every floor and the roof of each, every room reached through its
##   doorways and up its stairs, no two buildings on each other, all inside the block's lots, its
##   garrison posts (CITY_POSTS) standing clear, most of them up high; the same every time.
## - Its blocks are module types (ZoneModules "city#..."), towns to the missions, one pad.
## - The Old Quarter (city_hot) is a city: the "city" terrain preset, its blocks, its street grid
##   exposed for the roads (ZoneModules.city_streets), a road in from the HQ, every block on one
##   flat pad with its half of the streets painted road-coloured.
## - Village houses (1.6): a village's houses are generated (BuildingGen.village_house) in its
##   module's layout, its garrison posts and mission spots where they were, clear.
## - Then in the world: the Old Quarter hosted (no AI), the player walks in toward the city while
##   its blocks stream in, every frame timed (a city block's frame cost, Proposed budgets); the
##   zone's navmesh (ZoneNav) round a tall building covers every one of its rooms, floor by floor,
##   and its roof, from the street; the AI's building scan (Buildings) finds its upper floors,
##   their rooms and firing ports from upstairs; a block's garrison, put in, holds its upper
##   floors (posts the scan finds inside the building, on its floors).

## Proposed budgets for a city block streaming in (headless, this machine: see the report): the
## worst frame and the average while the player walks in at a run and the city's blocks stream in
## round him (each block's voxels are stamped BUILD_BUDGET_MS a frame; the garrison isn't out).
const BLOCK_WORST_FRAME_MS := 200.0
const BLOCK_AVERAGE_FRAME_MS := 25.0
## The walk: from this far out from the city's edge, at this speed, until this far inside it.
const WALK_FROM_M := 330.0
const WALK_SPEED_MS := 6.0
const WALK_INTO_M := 30.0
## A frame longer than this is reported with where its time went.
const SPIKE_MS := 100.0
## How many navmesh polygons a path search in the checks may cover (Godot's default is 4096: F-193).
const NAV_SEARCH_POLYGONS := 65536
## Seeds for the generation checks.
const SEEDS: Array[int] = [204917, 77, 3001]

var failures := 0
var level: ZoneLevel
var player: Soldier
var _frame_ms: Array[float] = []
var _net_ms: Array[float] = []  # less the building scans past a game's frame budget for them
var _last_frame := 0
var _timing := false


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_city" + tag
	Campaign.campaign_id = "test_city_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func() -> void:
		print("CITY TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_layout()
	_test_blocks()
	_test_modules()
	_test_old_quarter()
	_test_villages()
	if OS.get_environment("CITY_DATA_ONLY") != "1":  # (a quicker run while working on the generation)
		await _test_in_world()
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	Campaign.reset_campaign()
	GameState.delete_save()
	print("CITY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _timing and _last_frame > 0:
		var ms := (now - _last_frame) / 1000.0
		_frame_ms.append(ms)
		var costs := FrameCost.take()
		# The frame as a game's would be: the AI's building scans run here in full (headless: exact
		# answers for the suites), where a game stops them at Buildings.FRAME_BUDGET_USEC a frame.
		var scans := int(costs.get(&"buildings", 0)) / 1000.0
		_net_ms.append(ms - scans + minf(scans, Buildings.FRAME_BUDGET_USEC / 1000.0))
		if ms > SPIKE_MS:  # where a long frame's time went (FrameCost's systems)
			var keys := costs.keys()
			keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(costs[a]) > int(costs[b]))
			print("city: a %.0f ms frame (%d city blocks in): %s" % [ms, level.streamed_modules().filter(func(m: ZoneModule) -> bool: return m.type.begins_with(ZoneModules.CITY)).size() if level else 0,
				", ".join(keys.slice(0, 5).map(func(k: StringName) -> String: return "%s %.1f ms" % [k, int(costs[k]) / 1000.0]))])
	_last_frame = now


# --- Generation ------------------------------------------------------------------------------

func _test_layout() -> void:
	print("A city's street grid")
	var bad: Array = []
	for seed: int in SEEDS:
		var c := BuildingGen.city_layout(seed)
		var blocks: Dictionary = c.blocks
		var towers := blocks.values().filter(func(b: Dictionary) -> bool: return b.tower)
		if blocks.size() != BuildingGen.CITY_BLOCKS.x * BuildingGen.CITY_BLOCKS.y:
			bad.append("%d: %d blocks" % [seed, blocks.size()])
		if towers.size() < BuildingGen.CITY_TOWERS.x or towers.size() > BuildingGen.CITY_TOWERS.y or not towers.all(func(b: Dictionary) -> bool: return b.core):
			bad.append("%d: %d towers" % [seed, towers.size()])
		if (c.streets as Array).size() != BuildingGen.CITY_BLOCKS.x + BuildingGen.CITY_BLOCKS.y + 2 \
				or (c.junctions as Array).size() != (BuildingGen.CITY_BLOCKS.x + 1) * (BuildingGen.CITY_BLOCKS.y + 1):
			bad.append("%d: %d streets, %d junctions" % [seed, (c.streets as Array).size(), (c.junctions as Array).size()])
		for at: Vector2i in blocks:
			var centre: Vector2 = blocks[at].centre
			if not is_equal_approx(fmod(absf(centre.x), ZoneDef.GRID_M), 0.0) or not is_equal_approx(fmod(absf(centre.y), ZoneDef.GRID_M), 0.0):
				bad.append("%d: block %s off the 12 m grid (%s)" % [seed, at, centre])
			# Every block has a street on each side: a grid line at its edges.
			var e := BuildingGen.CITY_PITCH * 0.5
			for edge: Vector2 in [centre + Vector2(e, 0), centre - Vector2(e, 0), centre + Vector2(0, e), centre - Vector2(0, e)]:
				if not (c.streets as Array).any(func(st: Array) -> bool: return _on_segment(edge, st[0], st[1])):
					bad.append("%d: block %s has no street at %s" % [seed, at, edge])
		if str(BuildingGen.city_layout(seed)) != str(c):
			bad.append("%d: not the same every time" % seed)
	var c0 := BuildingGen.city_layout(SEEDS[0])
	check(bad.is_empty(), "%d x %d blocks %.0f m apart, %.0f m streets round every one (%d street lines, %d junctions), %d-%d towers in the core, on the 12 m grid, the same from a seed %s" % [
		BuildingGen.CITY_BLOCKS.x, BuildingGen.CITY_BLOCKS.y, BuildingGen.CITY_PITCH, BuildingGen.CITY_STREET_W, (c0.streets as Array).size(), (c0.junctions as Array).size(),
		BuildingGen.CITY_TOWERS.x, BuildingGen.CITY_TOWERS.y, bad.slice(0, 4)])


func _on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 0.01


func _test_blocks() -> void:
	print("Its blocks: storeys, stairs, rooms, lots, garrison posts")
	var bad: Array = []
	var bands := {"core": [], "outskirts": [], "tower": []}
	var buildings_n := 0
	var floors_n := 0
	var posts := 0
	var high := 0
	var ruined := 0
	var towers := 0
	var worst_ms := 0.0
	for seed: int in SEEDS:
		var layout := BuildingGen.city_layout(seed)
		for at: Vector2i in layout.blocks:
			var t0 := Time.get_ticks_usec()
			var blk := BuildingGen.city_block(seed, at.x, at.y)
			worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
			var name := "%d %s" % [seed, at]
			var lot := (BuildingGen.CITY_PITCH - BuildingGen.CITY_STREET_W) * 0.5
			var feet: Array[Rect2] = []
			var block_towers := 0
			for bt: Dictionary in blk.buildings:
				var b: Dictionary = bt.data
				buildings_n += 1
				ruined += 1 if int(b.ruin) != BuildingGen.INTACT else 0
				var s := int(b.storeys)
				floors_n += s
				var band: Vector2i = BuildingGen.CITY_TOWER_STOREYS if bt.tower else (BuildingGen.CITY_CORE_STOREYS if blk.core else BuildingGen.CITY_OUTSKIRT_STOREYS)
				(bands["tower" if bt.tower else ("core" if blk.core else "outskirts")] as Array).append(s)
				block_towers += 1 if bt.tower else 0
				if s < band.x or s > band.y:
					bad.append("%s %s: %d storeys (%s)" % [name, bt.type, s, band])
				# A stair up from every floor and onto the roof, each flight the floor-to-floor rise.
				var flights: Array = (b.stairs as Array).duplicate()
				flights.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.from_y) < float(q.from_y))
				var reached_roof := false
				var ok := flights.size() == s
				for f in flights.size():
					var st: Dictionary = flights[f]
					if (float(st.to_y) - float(st.from_y)) / int(st.steps) > 0.25 + 0.001:
						ok = false
					if f > 0 and absf(float(st.from_y) - float(flights[f - 1].to_y)) > 0.01:
						ok = false
					if absf(float(st.to_y) - float(b.roof_y)) < 0.01:
						reached_roof = true
					var foot: Rect2 = st.foot
					if not _solid(b.boxes, Vector3(foot.get_center().x, float(st.from_y) + 0.05, foot.get_center().y)):
						ok = false
				if not ok or not reached_roof or not b.roof_access:
					bad.append("%s %s: %d storeys, stairs %s, roof %s" % [name, bt.type, s, flights.map(func(st: Dictionary) -> String: return "%.1f-%.1f" % [st.from_y, st.to_y]), b.roof_access])
				var reach := _reached(b)
				if int(reach.rooms) != (b.rooms as Array).size() or not reach.roof:
					bad.append("%s %s: %d of %d rooms reached, roof %s" % [name, bt.type, reach.rooms, (b.rooms as Array).size(), reach.roof])
				var blocked := _blocked_doors(b)
				if not blocked.is_empty():
					bad.append("%s %s: doorways blocked %s" % [name, bt.type, blocked])
				var size: Vector2 = b.size
				var foot := BuildingGen._turn_rect(Rect2(-size * 0.5, size), int(bt.turn))
				foot.position += Vector2((bt.origin as Vector3).x, (bt.origin as Vector3).z)
				if foot.position.x < -lot - 0.01 or foot.position.y < -lot - 0.01 or foot.end.x > lot + 0.01 or foot.end.y > lot + 0.01:
					bad.append("%s %s: outside the lots %s" % [name, bt.type, foot])
				if feet.any(func(o: Rect2) -> bool: return o.grow(-0.01).intersects(foot.grow(-0.01))):
					bad.append("%s %s: on another building" % [name, bt.type])
				feet.append(foot)
				# Its front door on its street: out of the lots' edge.
				var fd: Variant = BuildingGen.front_door(b)
				if fd == null:
					bad.append("%s %s: no front door" % [name, bt.type])
				else:
					var out := BuildingGen._rot((fd as Vector3) + Vector3(0, 0, 0.6), int(bt.turn)) + (bt.origin as Vector3)
					if maxf(absf(out.x), absf(out.z)) < lot:
						bad.append("%s %s: front door not on its street (%s)" % [name, bt.type, out])
			towers += block_towers
			if bool(blk.tower) != (block_towers == 1):
				bad.append("%s: tower block %s, %d towers" % [name, blk.tower, block_towers])
			for bx: Array in blk.boxes:
				var lo: Vector3 = bx[0]
				var hi: Vector3 = bx[1]
				if absf(lo.x) > BuildingGen.CITY_PITCH * 0.5 + 0.01 or absf(hi.x) > BuildingGen.CITY_PITCH * 0.5 + 0.01 or absf(lo.z) > BuildingGen.CITY_PITCH * 0.5 + 0.01 or absf(hi.z) > BuildingGen.CITY_PITCH * 0.5 + 0.01:
					bad.append("%s: a box outside its footprint" % name)
					break
			# Garrison posts: CITY_POSTS (and a tower's), clear, most up high.
			var g: Array = blk.garrison
			var want := int(BuildingGen.CITY_POSTS["core" if blk.core else "outskirts"]) + (int(BuildingGen.CITY_POSTS.tower) if blk.tower else 0)
			if g.size() < want - 1 or g.size() > want or (blk.garrison_face as Array).size() != g.size():
				bad.append("%s: %d posts (want %d)" % [name, g.size(), want])
			var up := 0
			for p: Vector3 in g:
				posts += 1
				var clear := BuildingGen._clear_post(blk.boxes, p) if p.y > 0.5 else BuildingGen._clear_standing(blk.boxes, p)
				if not clear:
					bad.append("%s: post %s in something" % [name, p])
				if p.y > 2.0:
					up += 1
			high += up
			if up < floori(g.size() * BuildingGen.CITY_HIGH_SHARE):
				bad.append("%s: %d of %d posts up high" % [name, up, g.size()])
			if (blk.loot as Array).size() > BuildingGen.CITY_LOOT_MAX or (blk.fallback as Array).size() < (blk.buildings as Array).size() / 2:
				bad.append("%s: %d loot, %d fallback" % [name, (blk.loot as Array).size(), (blk.fallback as Array).size()])
	var again := BuildingGen.city_block(SEEDS[0], 1, 1)
	check(str(again.boxes) == str(BuildingGen.city_block(SEEDS[0], 1, 1).boxes) and str(again.boxes) != str(BuildingGen.city_block(SEEDS[1], 1, 1).boxes),
		"the same block from the same seed, another from another")
	check(bad.is_empty(), "%d buildings in %d blocks of %d cities: storeys in their bands, a stair up to every floor and its roof (0.25 m a step at most), every room reached, doorways clear, inside the lots and off each other, front doors on the street %s" % [
		buildings_n, BuildingGen.CITY_BLOCKS.x * BuildingGen.CITY_BLOCKS.y * SEEDS.size(), SEEDS.size(), bad.slice(0, 5)])
	var spread := func(list: Array) -> String: return "%d-%d" % [list.min(), list.max()] if not list.is_empty() else "none"
	print("    storeys: core %s, outskirts %s, towers %s; %d floors in all, %d ruined; %d posts, %d up high; slowest block %.0f ms" % [
		spread.call(bands.core), spread.call(bands.outskirts), spread.call(bands.tower), floors_n, ruined, posts, high, worst_ms])
	check((bands.tower as Array).size() == towers and towers >= SEEDS.size() * BuildingGen.CITY_TOWERS.x and (bands.core as Array).max() >= 4 and (bands.outskirts as Array).min() >= 2,
		"towers %s storeys (%d of them), the core %s, the outskirts %s" % [spread.call(bands.tower), towers, spread.call(bands.core), spread.call(bands.outskirts)])
	check(posts > 0 and high >= posts * 0.6 and ruined > 0, "%d garrison posts, %d of them on upper floors or roofs; %d buildings ruined" % [posts, high, ruined])


## Building `b`'s rooms reached from the street through its doorways and stairs: {"rooms", "roof"}.
func _reached(b: Dictionary) -> Dictionary:
	var seen := {-1: true}
	var grew := true
	while grew:
		grew = false
		for dr: Dictionary in b.doors:
			if (b.buried as Array).has(dr.at):
				continue
			var a: int = dr.rooms[0]
			var c: int = dr.rooms[1]
			if seen.has(a) != seen.has(c):
				seen[a] = true
				seen[c] = true
				grew = true
	return {"rooms": seen.keys().filter(func(k: int) -> bool: return k >= 0).size(), "roof": seen.has(-2)}


func _solid(boxes: Array, q: Vector3) -> bool:
	return boxes.any(func(bx: Array) -> bool: return AABB(bx[0], (bx[1] as Vector3) - (bx[0] as Vector3)).has_point(q))


func _blocked_doors(b: Dictionary) -> Array:
	var out: Array = []
	for dr: Dictionary in b.doors:
		if (b.buried as Array).has(dr.at) or dr.get("stair", false):
			continue
		var at: Vector3 = (dr.at as Vector3) + Vector3(0, 0.5, 0)
		var through_x: bool = not _solid(b.boxes, at + Vector3(0.6, 0, 0)) and not _solid(b.boxes, at - Vector3(0.6, 0, 0))
		var through_z: bool = not _solid(b.boxes, at + Vector3(0, 0, 0.6)) and not _solid(b.boxes, at - Vector3(0, 0, 0.6))
		if _solid(b.boxes, at) or not (through_x or through_z):
			out.append(dr.at)
	return out


func _test_modules() -> void:
	print("City blocks as module types")
	var seed := SEEDS[0]
	var type := "%s%d#2#1" % [ZoneModules.CITY, seed]
	var ok := ZoneModules.has_type(type) and ZoneModules.base(type) == "town" and ZoneModules.city_of(type) == "%s%d" % [ZoneModules.CITY, seed] \
		and not ZoneModules.boxes(type).is_empty() and (ZoneModules.GARRISON.get(type, []) as Array).size() >= 2 \
		and (ZoneModules.GARRISON_FACE.get(type, []) as Array).size() == (ZoneModules.GARRISON.get(type, []) as Array).size() \
		and not ZoneModules.ramps(type).is_empty() and float(ZoneModules.TOP.get(type, 0.0)) > ZoneModules.TOP_M
	check(ok, "\"%s\" is a module type: a town to the rest (base \"%s\"), %d boxes, %d posts, its stairs' ramps, top %.1f m" % [type, ZoneModules.base(type),
		ZoneModules.boxes(type).size(), (ZoneModules.GARRISON.get(type, []) as Array).size(), float(ZoneModules.TOP.get(type, 0.0))])
	check(not ZoneModules.has_type("%s%d#9#0" % [ZoneModules.CITY, seed]) and not ZoneModules.has_type("%sx#0#0" % ZoneModules.CITY) and not ZoneModules.has_type("%s1#0" % ZoneModules.CITY),
		"a block off the grid or a bad seed isn't one")
	# Every block's pad is the whole city's, in zone metres the same rect.
	var pads := {}
	var layout := BuildingGen.city_layout(seed)
	for at: Vector2i in layout.blocks:
		var t := "%s%d#%d#%d" % [ZoneModules.CITY, seed, at.x, at.y]
		var c := BuildingGen.city_block_centre(at.x, at.y) + Vector2(600, -300)
		pads[str(ZoneModules.pad_rect(t, c))] = true
	var half: Vector2 = layout.half
	check(pads.size() == 1 and pads.has(str(Rect2(Vector2(600, -300) - half, half * 2.0))) and (ZoneModules.streets(type) as Array).size() == 4,
		"every block's pad is the whole city's (%s), its half streets painted on it" % pads.keys())
	# Missions take a block as a town: its sites come from its buildings.
	var sites_ok := true
	for id: String in ["area", "intel", "docs", "hvt", "hvt_phone", "hostage", "cache"]:
		sites_ok = sites_ok and not MissionRegistry.site(type, id).is_empty()
	var hvt: Array = MissionRegistry.site(type, "hvt").get("pos", [0, 0, 0])
	check(sites_ok and ZoneModules.civilians(type).size() >= 1 and ZoneModules.town_fallback(type).size() >= 3,
		"a block's contract sites, people and fallback points come from its buildings (an HVT at %s)" % [hvt])


func _test_old_quarter() -> void:
	print("The Old Quarter is a city")
	var def := MissionRegistry.zone_def("city_hot")
	var blocks: Array = (def.modules as Array).filter(func(m: Dictionary) -> bool: return String(m.type).begins_with(ZoneModules.CITY))
	var cities: Array = def.get("cities", [])
	check(String(def.get("terrain", "")) == "city" and bool(def.get("urban", false)) and cities.size() == 1
		and blocks.size() == BuildingGen.CITY_BLOCKS.x * BuildingGen.CITY_BLOCKS.y and MissionRegistry.zone("city_hot").get("modules", []).has("town"),
		"%s: the \"city\" preset, a city of %d blocks (%s)" % [def.get("name", ""), blocks.size(), cities])
	if cities.is_empty():
		return
	var at := Vector2(float(cities[0].pos[0]), float(cities[0].pos[1]))
	var layout := BuildingGen.city_layout(int(cities[0].seed))
	var half: Vector2 = layout.half
	var rect := Rect2(at - half, half * 2.0)
	var on_grid := blocks.all(func(m: Dictionary) -> bool:
		var parts := String(m.type).split("#")
		var c := at + BuildingGen.city_block_centre(int(parts[2]), int(parts[3]))
		return absf(float(m.pos[0]) - c.x) < 0.01 and absf(float(m.pos[1]) - c.y) < 0.01)
	var clear := (def.modules as Array).all(func(m: Dictionary) -> bool:
		return String(m.type).begins_with(ZoneModules.CITY) or not ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))).intersects(rect.grow(20.0)))
	var streets := ZoneModules.city_streets(def)
	var inside := streets.all(func(st: Array) -> bool: return rect.grow(0.01).has_point(Vector2(st[0][0], st[0][1])) and rect.grow(0.01).has_point(Vector2(st[1][0], st[1][1])))
	var road_in := (def.roads as Array).any(func(r: Array) -> bool: return rect.grow(0.5).has_point(Vector2(float(r[1][0]), float(r[1][1]))) and not rect.grow(-1.0).has_point(Vector2(float(r[1][0]), float(r[1][1]))))
	var again: Dictionary = ZoneDef.generate_hot(6607, ZoneDef.HOT_SIZE_M, true)
	var patrolled := (def.patrols as Array).any(func(route: Array) -> bool: return route.all(func(q: Array) -> bool: return rect.has_point(Vector2(q[0], q[1]))))
	check(on_grid and clear and road_in and patrolled and streets.size() == (layout.streets as Array).size() and inside and str(again.get("cities")) == str(def.get("cities")),
		"its blocks on their grid at %s, every other site clear of it, a road in from the HQ to its edge, a patrol round its inner streets, its %d streets exposed for the roads (ZoneModules.city_streets), the same every time" % [at, streets.size()])
	# On the ground: one flat pad under every block, its streets road-coloured, its lots not.
	var flat: Array = []
	for m: Dictionary in def.modules:
		flat.append(ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))))
	var t := ZoneTerrain.new()
	t.generate(def, flat)
	var heights: Array = blocks.map(func(m: Dictionary) -> float: return t.height_at(float(m.pos[0]), float(m.pos[1])))
	var street_p := at + Vector2(0.0, -half.y + BuildingGen.CITY_PITCH)  # on a street line between two rows of blocks
	var lot_p := at + BuildingGen.city_block_centre(1, 1) + Vector2(0.0, BuildingGen.CITY_PITCH * 0.5 - BuildingGen.CITY_STREET_W - 2.0)
	var colour_at := func(p: Vector2) -> Color: return t._ground_colour(roundi((p.x + t.size_m * 0.5) / ZoneTerrain.CELL_M), roundi((p.y + t.size_m * 0.5) / ZoneTerrain.CELL_M), Vector3.UP)
	check(float(heights.max()) - float(heights.min()) < 0.01 and colour_at.call(street_p) == t.c_road and colour_at.call(lot_p) != t.c_road,
		"every block stands on one flat pad (%.2f-%.2f m), its streets road-coloured, its lots not" % [heights.min(), heights.max()])
	t.free()


func _test_villages() -> void:
	print("Village houses (queue item 1.6): generated, in the village's layout")
	var boxes := ZoneModules.boxes("village")
	var keep := ZoneModules._village_keep()
	var bad: Array = []
	var rooms := 0
	var furnished := 0
	for spec: Dictionary in ZoneModules.VILLAGE_HOUSES:
		var h := BuildingGen.village_house(spec, keep)
		var b: Dictionary = h.data
		var rect: Rect2 = spec.rect
		var name := "%s house" % spec.style
		if int(b.storeys) != 1 or b.roof_access or (b.yards as Array).size() > 0 or String(b.shape) != "rect":
			bad.append("%s: storeys %d, roof %s, %d yards, %s" % [name, b.storeys, b.roof_access, (b.yards as Array).size(), b.shape])
		var reach := _reached(b)
		if int(reach.rooms) != (b.rooms as Array).size():
			bad.append("%s: %d of %d rooms reached" % [name, reach.rooms, (b.rooms as Array).size()])
		for bx: Array in h.boxes:
			var lo: Vector3 = bx[0]
			var hi: Vector3 = bx[1]
			if lo.x < rect.position.x - 0.01 or lo.z < rect.position.y - 0.01 or hi.x > rect.end.x + 0.01 or hi.z > rect.end.y + 0.01:
				bad.append("%s: a box outside its ground %s" % [name, rect])
				break
		# Its front door where the hand-built one's was, on the same side.
		var fd: Vector3 = BuildingGen._rot(BuildingGen.front_door(b), int(h.turn)) + (h.origin as Vector3)
		var along := fd.x if String(spec.front) == "s" else fd.z
		var on_side := absf(fd.z - rect.end.y) < 0.45 if String(spec.front) == "s" else absf(fd.x - rect.end.x) < 0.45  # (its door is on its wall's inner face)
		if not on_side or absf(along - float(spec.door)) > 0.3:
			bad.append("%s: front door at %s (want %s at %.1f)" % [name, fd, spec.front, spec.door])
		for r: Dictionary in b.rooms:
			rooms += 1
			furnished += 1 if String(r.chunk) != "" else 0
		if (b.windows as Array).is_empty() and String(spec.style) != "plank":
			bad.append("%s: no windows" % name)
	# Its garrison posts, loot, points and mission sites, where they were, inside the houses and clear.
	var posts_ok := true
	for p: Vector3 in ZoneModules.GARRISON.village:
		var inside := ZoneModules.VILLAGE_HOUSES.any(func(s: Dictionary) -> bool: return (s.rect as Rect2).grow(-0.2).has_point(Vector2(p.x, p.z)))
		if not inside or not BuildingGen._clear_standing(boxes, p):
			posts_ok = false
			bad.append("post %s: %s" % [p, "clear" if inside else "not in a house"])
	var spots: Array[Vector3] = []
	for l: Dictionary in ZoneModules.LOOT.village:
		spots.append(Vector3((l.pos as Vector3).x, 0.05, (l.pos as Vector3).z))
	for site: Dictionary in (MissionRegistry.module("village").get("sites", {}) as Dictionary).values():
		if site.has("pos"):
			spots.append(Vector3(float(site.pos[0]), 0.05, float(site.pos[2])))
	for spot: Dictionary in WorldValuables.site_spec("village").get("spots", []):
		spots.append(Vector3(float(spot.pos[0]), 0.05, float(spot.pos[1])))
	for q: Vector3 in spots:
		if boxes.any(func(bx: Array) -> bool: return AABB(bx[0], (bx[1] as Vector3) - (bx[0] as Vector3)).intersects(AABB(q - Vector3(0.2, 0, 0.2), Vector3(0.4, 1.0, 0.4)))):
			bad.append("spot %s covered" % q)
	var crates := MissionRegistry.site("village", "cache")
	var crate_voxels := ZoneModules.solid_voxels_in("village", AABB(Vector3(-15.8, 0, 9.6), Vector3(2.0, 2.0, 1.2)))
	check(bad.is_empty() and posts_ok and furnished >= rooms - 1 and not crates.is_empty() and crate_voxels > 1000,
		"its %d houses generated in village style (mud brick, cinder block, brick, a plank shack: %d rooms, %d furnished), each on its old ground with its door where it was, every room reached; its %d garrison posts in them and clear, its loot, points, mission sites and site boxes (%d spots) clear, its cache of crates (%d voxels) %s" % [
			ZoneModules.VILLAGE_HOUSES.size(), rooms, furnished, (ZoneModules.GARRISON.village as Array).size(), spots.size(), crate_voxels, bad.slice(0, 5)])
	check(ZoneModules.HALF.village == Vector2(20, 14) and ZoneModules.ramps("village").is_empty() and not ZoneModules.skin("village").is_empty()
		and ZoneModules.has_type("village+5") and ZoneModules.boxes("village+5").size() > boxes.size(),
		"its footprint, no stairs, a skin of its own; a grown village keeps them and adds its houses round them")


# --- In the world ------------------------------------------------------------------------------

func _test_in_world() -> void:
	print("The Old Quarter hosted: a city's blocks streaming in, navmesh, the AI's scan, garrisons")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	main.host_zone(MissionRegistry.zone_def("city_hot"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	print("city: zone hosted in %d ms (%s)" % [Time.get_ticks_msec() - t0, "%.0f ms generating" % level.generate_ms])
	player = level.players.get_node(^"1") as Soldier
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	var cities: Array = level.def.get("cities", [])
	if cities.is_empty():
		check(false, "the hosted Old Quarter has its city")
		return
	var city_at := Vector2(float(cities[0].pos[0]), float(cities[0].pos[1]))
	var half: Vector2 = BuildingGen.city_layout(int(cities[0].seed)).half
	# The walk in: from WALK_FROM_M out on the side facing the zone's middle, at a run.
	var dir := (-city_at).normalized() if city_at.length() > 1.0 else Vector2(1, 0)
	var edge := city_at + Vector2(dir.x * half.x, dir.y * half.y)
	var start := edge + dir * WALK_FROM_M
	var finish := edge - dir * WALK_INTO_M
	player.global_position = level.ground_point(Vector3(start.x, 0, start.y)) + Vector3.UP * 0.1
	for i in 240:  # (the terrain and anything near the start settle first)
		await get_tree().process_frame
	_frame_ms.clear()
	_net_ms.clear()
	FrameCost.on = true
	FrameCost.take()
	_timing = true
	var streamed_before := level.streamed_modules().filter(func(m: ZoneModule) -> bool: return m.type.begins_with(ZoneModules.CITY)).size()
	var walk := start.distance_to(finish)
	var moved := 0.0
	while moved < walk:
		var dt := get_process_delta_time()
		moved = minf(moved + WALK_SPEED_MS * maxf(dt, 1.0 / 60.0), walk)
		var p := start.lerp(finish, moved / walk)
		player.global_position = level.ground_point(Vector3(p.x, 0, p.y)) + Vector3.UP * 0.1
		await get_tree().process_frame
	var nearest: ZoneModule = null
	for m in level.modules():
		if m.type.begins_with(ZoneModules.CITY) and (nearest == null or m.distance_to(player.global_position) < nearest.distance_to(player.global_position)):
			nearest = m
	for i in 1200:
		await get_tree().process_frame
		if nearest.is_ready() and level.nav and level.nav.is_settled():
			break
	_timing = false
	FrameCost.on = false
	var city_blocks := level.streamed_modules().filter(func(m: ZoneModule) -> bool: return m.type.begins_with(ZoneModules.CITY))
	var raw := _stats(_frame_ms)
	var net := _stats(_net_ms)
	print("city: walked %.0f m in, %d city blocks streamed in (%d before), %d frames: worst %.1f ms, 95th %.1f, average %.2f ms; less the building scans past a game's %.0f ms a frame: worst %.1f ms, 95th %.1f, average %.2f ms" % [
		walk, city_blocks.size(), streamed_before, _frame_ms.size(), raw.worst, raw.p95, raw.avg, Buildings.FRAME_BUDGET_USEC / 1000.0, net.worst, net.p95, net.avg])
	check(city_blocks.size() >= 6 and nearest.is_ready(), "walking in, the city streams in block by block (%d blocks in; the nearest ready)" % city_blocks.size())
	check(float(net.worst) <= BLOCK_WORST_FRAME_MS and float(net.avg) <= BLOCK_AVERAGE_FRAME_MS,
		"a city block's frame cost streaming in (the AI's building scans as a game caps them, F-191): worst frame %.0f ms (Proposed budget %.0f), average %.1f ms (Proposed budget %.0f)" % [
			net.worst, BLOCK_WORST_FRAME_MS, net.avg, BLOCK_AVERAGE_FRAME_MS])
	# The tall building checks in the tower block nearest the player.
	var tower: ZoneModule = null
	for m: ZoneModule in city_blocks:
		var parts: PackedStringArray = m.type.split("#")
		if BuildingGen.city_layout(int(parts[1])).blocks[Vector2i(int(parts[2]), int(parts[3]))].tower \
				and (tower == null or m.distance_to(player.global_position) < tower.distance_to(player.global_position)):
			tower = m
	await _check_tall_building(tower if tower != null else nearest)


## Worst, 95th percentile and average of `ms`.
func _stats(ms: Array[float]) -> Dictionary:
	if ms.is_empty():
		return {"worst": 0.0, "p95": 0.0, "avg": 0.0}
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for v: float in ms:
		sum += v
	return {"worst": sorted[-1], "p95": sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], "avg": sum / ms.size()}


## In block `m` (streamed in): its tallest building's every room and roof reached by the zone's
## navmesh from the street, the AI's scan from upstairs, and the block's garrison on its floors.
func _check_tall_building(m: ZoneModule) -> void:
	var parts := m.type.split("#")
	var blk := BuildingGen.city_block(int(parts[1]), int(parts[2]), int(parts[3]))
	var best: Dictionary = {}
	for bt: Dictionary in blk.buildings:
		if int(bt.data.ruin) == BuildingGen.INTACT and (best.is_empty() or int(bt.data.storeys) > int(best.data.storeys)):
			best = bt
	var b: Dictionary = best.data
	var turn := int(best.turn)
	var origin: Vector3 = best.origin
	var to_world := func(p: Vector3) -> Vector3: return m.to_global(BuildingGen._rot(p, turn) + origin)
	var fd: Vector3 = BuildingGen.front_door(b)
	var street: Vector3 = to_world.call(fd + Vector3(0, 0.1, 2.5))
	player.global_position = street
	level.nav.refresh()
	var map := player.get_world_3d().navigation_map
	for i in 1800:
		await get_tree().physics_frame
		if level.nav.is_settled() and m.is_ready():
			break
	await _physics_frames(20)
	Buildings.forget()
	var street_nav := NavigationServer3D.map_get_closest_point(map, street)
	var bad: Array = []
	var by_floor := {}
	var short_of := 0
	for r: Dictionary in b.rooms:
		var goal := _room_goal(map, r.rect, float(r.y), street_nav, to_world, m.global_position.y)
		var path := _path(map, street_nav, goal) if goal.is_finite() else PackedVector3Array()
		if goal.is_finite() and path.size() > 1 and path[-1].distance_to(goal) < 0.5:
			by_floor[int(r.floor)] = int(by_floor.get(int(r.floor), 0)) + 1
			var short := NavigationServer3D.map_get_path(map, street_nav, goal, true)
			if short.is_empty() or short[-1].distance_to(goal) >= 0.5:
				short_of += 1
		else:
			bad.append("floor %d %s (%s)" % [r.floor, r.role, "no navmesh there" if not goal.is_finite() else "no path"])
	var roof_spot: Rect2 = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == int(b.storeys) - 1)[0].rect
	var roof_goal := NavigationServer3D.map_get_closest_point(map, to_world.call(Vector3(roof_spot.get_center().x, float(b.roof_y) + 0.2, roof_spot.get_center().y)))
	var roof_path := _path(map, street_nav, roof_goal)
	var on_roof := absf(roof_goal.y - m.global_position.y - float(b.roof_y)) < Buildings.SURFACE_SNAP_M and roof_path.size() > 2 and roof_path[-1].distance_to(roof_goal) < 0.5
	check(bad.is_empty() and on_roof, "the navmesh covers every room of a %d-storey %s (rooms reached by floor %s) and its roof (%.1f m), from the street %s" % [
		b.storeys, best.type, by_floor, b.roof_y, bad.slice(0, 4)])
	print("  (map_get_path's 4096-polygon search falls short of %d of its %d rooms from the street: F-193)" % [short_of, (b.rooms as Array).size()])
	# The AI's scan from its top floor and from a middle floor.
	var top := int(b.storeys) - 1
	var scans: Array = []
	for fl: int in [top, maxi(top / 2, 1)]:
		var rr: Dictionary = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == fl and String(r.role) != "bathroom")[0]
		var c: Vector2 = (rr.rect as Rect2).get_center()
		var q: Vector3 = to_world.call(Vector3(c.x, float(rr.y) + 0.1, c.y))
		var found := Buildings.nearest(player, q, 4.0)
		var floors: Array = found.get("floors", [])
		var up_floors := floors.filter(func(f: Dictionary) -> bool: return float(f.y) > m.global_position.y + 2.0).size()
		var up_rooms := (found.get("rooms", []) as Array).filter(func(r: Dictionary) -> bool: return float(floors[int(r.floor)].y) > m.global_position.y + 2.0).size() if not floors.is_empty() else 0
		var up_ports := (found.get("ports", []) as Array).filter(func(p: Dictionary) -> bool: return String(p.kind) == "window" and (p.point as Vector3).y > m.global_position.y + 2.0).size()
		scans.append({"floor": fl, "found": found, "up_floors": up_floors, "up_rooms": up_rooms, "up_ports": up_ports, "at": q})
	var scan_ok := scans.all(func(s: Dictionary) -> bool: return not (s.found as Dictionary).is_empty() and int(s.up_floors) >= 2 and int(s.up_rooms) >= 2 and int(s.up_ports) >= 1)
	check(scan_ok, "the AI's building scan from upstairs finds its upper floors, their rooms and their windows to fire from (%s)" % [
		scans.map(func(s: Dictionary) -> String: return "from floor %d: %d floors up, %d rooms up, %d windows up" % [s.floor, s.up_floors, s.up_rooms, s.up_ports])])
	# The block's garrison posts: up high ones stand inside a building the scan finds, on its floors.
	var posts: Array = ZoneModules.GARRISON.get(m.type, [])
	var seen := 0
	var in_scan := 0
	for p: Vector3 in posts:
		var g: Vector3 = m.to_global(p)
		if g.y < m.global_position.y + 2.0:
			continue
		seen += 1
		var found := Buildings.nearest(player, g, 2.0)
		if not found.is_empty() and Buildings.floor_at(found, g) >= 1:
			in_scan += 1
	check(seen >= 1 and in_scan == seen, "its garrison's posts up high (%d) stand on floors the AI's scan finds (%d)" % [seen, in_scan])
	# Put the block's garrison in: they hold the upper floors.
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	level._spawn_garrison(m)
	CompoundLevel.spawn_ai = false
	for i in 600:
		await get_tree().physics_frame
		if level.garrison_pending(m.module_id) == 0 and level._garrisoned.has(m.module_id):
			break
	await _physics_frames(120)
	var men := 0
	var upstairs := 0
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and String(s.name).begins_with(("%s_H" % m.module_id).validate_node_name()) and s.vitals.is_up():
			men += 1
			if s.global_position.y > level.ground_height(s.global_position.x, s.global_position.z) + 2.0:
				upstairs += 1
	check(men >= posts.size() - 1 and upstairs >= floori(men * BuildingGen.CITY_HIGH_SHARE) - 1 and upstairs >= 1,
		"its garrison put in (%d men), %d of them hold the upper floors and roofs" % [men, upstairs])


## A walkable spot on room `rect`'s floor (at `y`, building metres; `to_world` places it) that a
## navmesh path from `street` reaches, the one nearest its middle; Vector3.INF if none.
func _room_goal(map: RID, rect: Rect2, y: float, street: Vector3, to_world: Callable, base_y: float) -> Vector3:
	var found: Array = []
	var c := rect.get_center()
	var x := rect.position.x + 0.25
	while x < rect.end.x:
		var z := rect.position.y + 0.25
		while z < rect.end.y:
			var want: Vector3 = to_world.call(Vector3(x, y + 0.1, z))
			var q := NavigationServer3D.map_get_closest_point(map, want)
			if Vector2(q.x - want.x, q.z - want.z).length() < 0.3 and absf(q.y - base_y - y) < Buildings.SURFACE_SNAP_M:
				found.append([Vector2(x, z).distance_to(c), q])
			z += 0.5
		x += 0.5
	if found.is_empty():
		return Vector3.INF
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in mini(found.size(), 12):
		var q: Vector3 = found[k][1]
		var path := _path(map, street, q)
		if path.size() > 1 and path[-1].distance_to(q) < 0.5:
			return q
	return found[0][1]


## A navmesh path from `from` to `to` searched over up to NAV_SEARCH_POLYGONS polygons. Godot's
## map_get_path (what the AI calls) gives up after 4096 and returns the path to the nearest spot it
## got to: from the street to a tower's top floors that's a floor or two short (F-193). This
## checks that the navmesh joins them up; the AI gets there by re-pathing on the way.
func _path(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	var q := NavigationPathQueryParameters3D.new()
	q.map = map
	q.start_position = from
	q.target_position = to
	q.path_search_max_polygons = NAV_SEARCH_POLYGONS
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.get_path()


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
