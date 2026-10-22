extends Node
## Terrain features and presets (queue item 1.3 of docs/cg_brief.md: ZoneFeatures, Season, the
## marsh, snow_mountain and farmland presets). One process:
##   <exe> --headless --path . res://tests/terrain_test.tscn
## Generation (no level): gullies and ditches hide a prone man (a gully a crouched one) from the
## flat round them, measured on the heights; cliffs are steep (a rock face, its foot to its top);
## each new preset builds by seed with its features (the marsh's ponds, soft ground and reed beds;
## the snow's cover, its snow line by season, frozen streams and ponds; farmland's fields, crops by
## season, orchards, hedges, irrigation channels, fields never on a pad); the same seed builds the
## same zone (ground, water, features, scatter), another seed another; a procedural mix takes the
## new presets' features; the campaign has a zone of each new preset a contract can go to; the
## season from the campaign day; what it costs to build.
## Hosted (a snow_mountain zone): rays and the AI see a man down in a gully as hidden and its cover
## search picks the gully; a cliff's face stops a man walking into it, and the navigation mesh
## doesn't climb it; snow slows a man on foot (packed ground doesn't); a frozen stream is ice he
## stands on, not water; marsh ground slows him the same way (the hook).
## Prints TERRAIN TEST PASSED/FAILED and exits with its failure count.

const SIZE_M := 2048.0
## Seeds tried for the hosted zone: the first with a cliff, a gully and a frozen stream wins.
const SEEDS: Array[int] = [31, 32, 33, 34, 35, 36, 37, 38]
## Observers on the flat round a gully: these far off (m), eyes this high.
const LOOK_FROM_M: Array[float] = [35.0, 70.0, 140.0]
const EYE_M := 1.6
const PRONE_M := 0.25
const CROUCH_M := 0.9

var failures := 0
var main: Node
var level: ZoneLevel
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_terrain" + tag
	Campaign.campaign_id = "test_terrain" + tag
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	get_tree().create_timer(560.0).timeout.connect(func() -> void:
		print("TERRAIN TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	ZoneScatter.clear_cache(true)  # layouts from this run's code, not an older run's disk cache
	print("Generation")
	if OS.get_environment("TERRAIN_HOSTED_ONLY") == "":  # (a dev shortcut: the hosted half alone)
		_test_season()
		_test_gullies()
		_test_cliffs()
		_test_marsh()
		_test_snow()
		_test_farmland()
		_test_same_seed()
		_test_procedural()
		_test_campaign()
		_test_cost()
	print("Hosted")
	var def := _pick_hosted()
	if def.is_empty():
		_finish()
		return
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and level.terrain.features != null, "hosting a snow_mountain zone (seed %d)" % int(def.seed))
	if level == null or level.terrain.features == null:
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	# A fresh build the way the level builds (ZoneLevel._build_environment): the heights, water and
	# features from the def as it came, then the roads planned and the ground graded to them (the
	# level's def now carries the planned roads: RoadNet.unplanned takes it back to what was sent).
	var sent := RoadNet.unplanned(level.def)
	var fresh := _terrain(sent)
	var fresh_roads := ZoneRoads.new()
	fresh_roads.prepare(fresh, sent)
	check(fresh.checksum() == level.terrain.checksum() and fresh.features.checksum() == level.terrain.features.checksum()
		and JSON.stringify(sent.get("roads", [])) == JSON.stringify(level.def.get("roads", [])),
		"the hosted zone's ground (graded to its roads), water, features and planned roads are a fresh build's from its seed (every peer and late joiner builds them)")
	fresh_roads.free()
	fresh.free()
	await _test_gully_cover()
	await _test_cliff_hosted()
	await _test_snow_slows()
	await _test_ice()
	_finish()


# --- Helpers ---------------------------------------------------------------------------------

func _def(preset: String, seed_value: int, size := SIZE_M, extra := {}) -> Dictionary:
	return ZoneDef.normalize(ZoneDef.generate(seed_value, size).merged({"terrain": preset, "id": "test_terrain", "name": "Terrain test"}, true).merged(extra, true))


## The flat pads a level would give `def` (ZoneLevel._flat_areas).
static func _flat(def: Dictionary) -> Array:
	var flat: Array = []
	for m: Dictionary in def.modules:
		flat.append(ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return flat


func _terrain(def: Dictionary) -> ZoneTerrain:
	var t := ZoneTerrain.new()
	t.generate(def, _flat(def))
	return t


## Whether the line `a` -> `b` clears the ground (the heights, exactly: ZoneTerrain.height_at).
static func _clear(t: ZoneTerrain, a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.5)
	for k in range(1, n):
		var q := a.lerp(b, float(k) / n)
		if t.height_at(q.x, q.z) > q.y:
			return false
	return true


## Full-depth spots along a gully or ditch (m along it, away from its ends and from pads and roads):
## [Vector2 on its line, its unit direction].
static func _deep_spots(f: ZoneFeatures, l: Dictionary) -> Array:
	var out: Array = []
	var pts: PackedVector2Array = l.pts
	for i in range(3, pts.size() - 3, 3):
		var p := pts[i]
		var n := f.terrain.points
		var gi := clampi(roundi((p.x + f.terrain.size_m * 0.5) / ZoneTerrain.CELL_M), 0, n - 1)
		var gj := clampi(roundi((p.y + f.terrain.size_m * 0.5) / ZoneTerrain.CELL_M), 0, n - 1)
		if f.cut_at(gi, gj) > float(l.depth) * 0.7:
			out.append([p, (pts[i + 1] - pts[i - 1]).normalized()])
	return out


## The lowest ground within 2 m of `p` (the gully's floor there).
static func _floor_at(t: ZoneTerrain, p: Vector2) -> Vector2:
	var best := p
	for k in 16:
		var q := p + Vector2.from_angle(k * TAU / 16.0) * (2.0 if k % 2 == 0 else 1.0)
		if t.height_at(q.x, q.y) < t.height_at(best.x, best.y):
			best = q
	return best


## How many of the lines from the flat round `p` (gully direction `dir`) to a man `up` metres over
## the ground at `p` the ground stops: observers LOOK_FROM_M off, square to it and 35 degrees off
## square, both sides, on ground no higher than the gully's rim nearby + 1.5 m. [hidden, tried].
static func _hidden_from_flat(t: ZoneTerrain, p: Vector2, dir: Vector2, up: float) -> Vector2i:
	var target := Vector3(p.x, t.height_at(p.x, p.y) + up, p.y)
	var side := Vector2(-dir.y, dir.x)
	var rim := maxf(t.height_at(p.x + side.x * 14.0, p.y + side.y * 14.0), t.height_at(p.x - side.x * 14.0, p.y - side.y * 14.0))
	var out := Vector2i.ZERO
	for d in LOOK_FROM_M:
		for s: float in [1.0, -1.0]:
			for turn: float in [0.0, deg_to_rad(35.0), deg_to_rad(-35.0)]:
				var o := p + side.rotated(turn) * s * d
				var ground := t.height_at(o.x, o.y)
				if ground > rim + 1.5:
					continue  # up a slope looking down into it: not the flat round it
				out.y += 1
				if not _clear(t, Vector3(o.x, ground + EYE_M, o.y), target):
					out.x += 1
	return out


func _soldier(pos: Vector3, callsign := "") -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": callsign if callsign != "" else "TT%d" % _made, "faction": "friendly", "variant": "woodland", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _face(s: Soldier, dir: Vector2) -> void:
	s.global_rotation = Vector3(0.0, atan2(-dir.x, -dir.y), 0.0)


func _park_player(at: Vector3) -> void:
	var player := level.players.get_node(^"1") as Soldier
	player.global_position = level.ground_point(at)
	player.velocity = Vector3.ZERO
	level.nav.refresh()
	await _wait_for(func() -> bool: return level.nav.is_settled(), 40.0)


# --- Generation ------------------------------------------------------------------------------

func _test_season() -> void:
	check(Season.of_day(1) == "spring" and Season.of_day(30) == "spring" and Season.of_day(31) == "summer" and Season.of_day(91) == "winter"
		and Season.of_day(121) == "spring" and Season.of_def({}) == Season.DEFAULT and Season.of_def({"season": "autumn"}) == "autumn",
		"the season from the campaign day: %d days each from %s (day 1 %s, 31 %s, 91 %s, 121 %s); a def without one is %s" % [Season.SEASON_DAYS, Season.START,
			Season.of_day(1), Season.of_day(31), Season.of_day(91), Season.of_day(121), Season.DEFAULT])


func _test_gullies() -> void:
	var prone := Vector2i.ZERO
	var crouch := Vector2i.ZERO
	var ditch := Vector2i.ZERO
	var counted := {"gully": 0, "ditch": 0}
	var pads_flat := true
	for preset: String in ["temperate", "scrubland", "desert_wadi"]:
		for seed_value in [41, 42, 43]:
			var def := _def(preset, seed_value)
			var t := _terrain(def)
			var f := t.features
			if f == null:
				t.free()
				continue
			for l: Dictionary in f.lines:
				counted[l.kind] = int(counted[l.kind]) + 1
				for spot: Array in _deep_spots(f, l):
					var floor_p := _floor_at(t, spot[0])
					if String(l.kind) == "gully":
						prone += _hidden_from_flat(t, floor_p, spot[1], PRONE_M)
						crouch += _hidden_from_flat(t, floor_p, spot[1], CROUCH_M)
					else:
						ditch += _hidden_from_flat(t, floor_p, spot[1], PRONE_M)
			for pad: Array in t.pads:
				var r: Rect2 = pad[0]  # (as the pad was flattened: the features keep off it)
				for p in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
					pads_flat = pads_flat and f.cut_at(roundi((p.x + t.size_m * 0.5) / ZoneTerrain.CELL_M), roundi((p.y + t.size_m * 0.5) / ZoneTerrain.CELL_M)) == 0.0
			t.free()
	check(int(counted.gully) >= 4 and int(counted.ditch) >= 1 and pads_flat, "gullies (%d) and ditches (%d) across temperate, scrubland and desert_wadi zones; none cuts into a pad" % [counted.gully, counted.ditch])
	var p_share := float(prone.x) / maxf(prone.y, 1.0)
	var c_share := float(crouch.x) / maxf(crouch.y, 1.0)
	var d_share := float(ditch.x) / maxf(ditch.y, 1.0)
	check(prone.y >= 60 and p_share >= 0.9, "a man prone in a gully is hidden from the flat round it: %.0f%% of %d lines from %s m (square and 35 degrees off)" % [p_share * 100.0, prone.y, LOOK_FROM_M])
	check(c_share >= 0.6, "crouched in a gully he's hidden from %.0f%% of those lines" % [c_share * 100.0])
	check(ditch.y >= 12 and d_share >= 0.75, "a man prone in a ditch is hidden from %.0f%% of %d lines from the flat" % [d_share * 100.0, ditch.y])


func _test_cliffs() -> void:
	var cliffs := 0
	var steep := 0
	var tall := 0
	var faces := 0
	var worst_pad := INF
	for preset: String in ["rocky_ridge", "snow_mountain", "badlands"]:
		for seed_value in [51, 52]:
			var def := _def(preset, seed_value)
			var t := _terrain(def)
			var f := t.features
			if f == null:
				t.free()
				continue
			for c: Dictionary in f.cliffs:
				cliffs += 1
				for k in 5:
					var u := 0.35 + k * 0.075
					var foot := f.cliff_point(c, u, -3.0)
					var top := f.cliff_point(c, u, 3.0)
					if f._keep_at(Vector2(foot.x, foot.z), ZoneFeatures.CLIFF_ROAD_M) < 0.95:
						continue  # a road's ramp up it
					faces += 1
					if top.y - foot.y > float(c.h) * 0.6:
						tall += 1
					# The steepest rise across the face (the grid's own slope there).
					var worst := 0.0
					for s in range(-6, 7):
						var a := f.cliff_point(c, u, float(s) - 0.5)
						var b := f.cliff_point(c, u, float(s) + 0.5)
						worst = maxf(worst, rad_to_deg(atan2(b.y - a.y, 1.0)))
					if worst > 55.0:
						steep += 1
				for pad: Array in t.pads:
					worst_pad = minf(worst_pad, f._cliff_reach(c, (pad[0] as Rect2).get_center()) - (pad[0] as Rect2).size.length() * 0.5)
			t.free()
	check(cliffs >= 4, "cliffs on rocky_ridge, snow_mountain and badlands zones (%d)" % cliffs)
	check(faces >= 15 and tall >= faces * 0.85 and steep >= faces * 0.85,
		"a cliff is a rock face: %d of %d spots along them rise most of their height over 6 m, %d steeper than 55 degrees" % [tall, faces, steep])
	check(worst_pad > 0.0, "cliffs keep off the pads (nearest pad edge %.0f m from one's footprint)" % worst_pad)


func _test_marsh() -> void:
	var def := _def("marsh", 61)
	var t := _terrain(def)
	var f := t.features
	var w := t.water
	check(f != null and w != null, "marsh: features and water")
	if f == null or w == null:
		t.free()
		return
	var ponds := 0
	var shallow := true
	for b: Dictionary in w.bodies:
		if String(b.kind) == "lake":
			ponds += 1
			shallow = shallow and float(b.depth) <= 1.2
	var soft := 0
	var reeds := 0
	var samples := 0
	var on_pad_soft := false
	for j in 40:
		for i in 40:
			var x := (i + 0.5) / 40.0 * t.size_m - t.size_m * 0.5
			var z := (j + 0.5) / 40.0 * t.size_m - t.size_m * 0.5
			samples += 1
			if f.soft_at(x, z) > 0.5:
				soft += 1
			if f.reeds_at(x, z) > 0.4:
				reeds += 1
	for pad: Array in t.pads:
		var c := (pad[0] as Rect2).get_center()
		on_pad_soft = on_pad_soft or f.soft_at(c.x, c.y) > 0.0
	var soft_share := float(soft) / samples
	check(ponds >= 8 and shallow and w.count_of("stream") >= 1, "marsh: standing water: %d shallow ponds and pools (ZoneWater), %d streams" % [ponds, w.count_of("stream")])
	check(soft_share > 0.3 and soft_share < 0.8 and reeds > 20 and not on_pad_soft,
		"marsh: soft ground over %.0f%% of it, reed beds at %d of %d samples, none on the pads" % [soft_share * 100.0, reeds, samples])
	var slowest := 1.0
	var p_slow := Vector2.ZERO
	for k in 400:
		var p := Vector2(fposmod(k * 97.3, t.size_m) - t.size_m * 0.5, fposmod(k * 61.7, t.size_m) - t.size_m * 0.5)
		var m := f.slow_at(p.x, p.y)
		if m < slowest:
			slowest = m
			p_slow = p
	check(slowest < 0.75 and slowest > 0.55 and f.slow_at(t.pads[0][0].get_center().x, t.pads[0][0].get_center().y) == 1.0,
		"marsh: the softest ground keeps %.0f%% of a man's pace (at %s), a pad all of it" % [slowest * 100.0, p_slow])
	var cover := _find_cover(f, t, 1.0)
	check(not cover.is_empty() and float(cover[1]) >= Spotting.FOLIAGE_OPAQUE_M, "marsh: a man crouched in a reed bed is hidden by the reeds (%.1f foliage metres on the line to him from 80 m)" % (float(cover[1]) if not cover.is_empty() else -1.0))
	t.free()


## A spot standing in cover (crops, reeds) with a line from 80 m to a man `up` m over the ground
## there: [spot, foliage metres]; [] with none found.
static func _find_cover(f: ZoneFeatures, t: ZoneTerrain, up: float) -> Array:
	for k in 4000:
		var p := Vector2(fposmod(k * 37.1, t.size_m * 0.8) - t.size_m * 0.4, fposmod(k * 53.9, t.size_m * 0.8) - t.size_m * 0.4)
		var c := f.cover_at(p.x, p.y)
		if c.x < 0.8:
			continue
		# Deep in it: cover all round for 20 m.
		var deep := true
		for a in 8:
			var q := p + Vector2.from_angle(a * TAU / 8.0) * 20.0
			deep = deep and f.cover_at(q.x, q.y).x >= 0.8
		if not deep:
			continue
		var target := Vector3(p.x, t.height_at(p.x, p.y) + up, p.y)
		var o := p + Vector2(80.0, 0.0)
		var eye := Vector3(o.x, t.height_at(o.x, o.y) + EYE_M, o.y)
		var m := f.cover_least(eye, target, target)
		return [p, minf(m.x, m.y)]
	return []


func _test_snow() -> void:
	var def := _def("snow_mountain", 71)
	var by_season := {}
	var heights := {}
	for season: String in Season.ALL:
		var t := _terrain(def.merged({"season": season}, true))
		var f := t.features
		var covered := 0
		var samples := 0
		var steep_snow := 0
		for j in range(0, t.points, 8):
			for i in range(0, t.points, 8):
				var x := t.v_x(i)
				var z := t.v_x(j)
				if absf(x) > t.size_m * 0.4 or absf(z) > t.size_m * 0.4:
					continue
				samples += 1
				if f.snow_at(x, z) > 0.5:
					covered += 1
				if t.normal_at(x, z).y < 0.6 and f.snow_at(x, z) > 0.2:
					steep_snow += 1
		by_season[season] = float(covered) / maxf(samples, 1.0)
		heights[season] = hash(t.heights)
		if season == "winter":
			var frozen := 0
			var dry_ice := true
			for bi in t.water.bodies.size():
				var b: Dictionary = t.water.bodies[bi]
				if not b.get("frozen", false):
					continue
				frozen += 1
				if String(b.kind) == "stream":
					var mid := t.water.sample_at(bi, (int(b.lo) + int(b.hi)) * 0.5)
					var p: Vector2 = mid.pos
					dry_ice = dry_ice and t.water_height(p.x, p.y) == -INF and float(mid.surface) - t.height_at(p.x, p.y) < 0.2
			check(frozen >= 2 and t.water.count_of("stream") >= 1 and dry_ice,
				"snow: %d frozen streams and ponds; on a frozen stream there's no water to wade (the ice lies on its bed)" % frozen)
			check(steep_snow == 0 and f.snow_strength() > 0.0 and f.slow_at(0.0, 0.0) <= 1.0, "snow: none on the steep rock; the ground shader's snow on")
			var slowest := 1.0
			for k in 300:
				var p := Vector2(fposmod(k * 91.3, t.size_m * 0.7) - t.size_m * 0.35, fposmod(k * 57.1, t.size_m * 0.7) - t.size_m * 0.35)
				slowest = minf(slowest, f.slow_at(p.x, p.y))
			var road: Array = def.roads[0]
			var on_road := (Vector2(road[0][0], road[0][1]) + Vector2(road[1][0], road[1][1])) * 0.5
			check(slowest < 0.85 and slowest > 0.6 and f.slow_at(on_road.x, on_road.y) > slowest + 0.1,
				"snow: deep snow keeps %.0f%% of a man's pace, the packed road %.0f%%" % [slowest * 100.0, f.slow_at(on_road.x, on_road.y) * 100.0])
		t.free()
	check(float(by_season.winter) > 0.9 and float(by_season.summer) < float(by_season.winter) and float(by_season.summer) > 0.25 and heights.summer == heights.winter,
		"snow: cover by season over the snow line (winter %.0f%%, spring %.0f%%, summer %.0f%%, autumn %.0f%% of the ground); the ground itself the same" % [
			float(by_season.winter) * 100.0, float(by_season.spring) * 100.0, float(by_season.summer) * 100.0, float(by_season.autumn) * 100.0])


func _test_farmland() -> void:
	var def := MissionRegistry.zone_def("harrow_fields").merged({"season": "summer"}, true)
	var t := _terrain(def)
	var f := t.features
	check(f != null and not f.field_cols.is_empty(), "farmland: Harrow Fields has its fields")
	if f == null or f.field_cols.is_empty():
		t.free()
		return
	var seen := {}
	var crops := {}
	var on_pad := 0
	for j in range(0, t.points, 3):
		for i in range(0, t.points, 3):
			var x := t.v_x(i)
			var z := t.v_x(j)
			var id := f.field_at(x, z)
			if id < 0:
				continue
			seen[id] = true
			crops[f.field_crops[id]] = int(crops.get(f.field_crops[id], 0)) + 1
			if f.pad_distance(Vector2(x, z)) < ZoneFeatures.FIELD_PAD_M:
				on_pad += 1
	var landmark_farm := false
	for m: Dictionary in def.modules:
		landmark_farm = landmark_farm or (String(m.type).begins_with(ZoneModules.LANDMARK) and ZoneModules.base(String(m.type)) == "farm")
	check(seen.size() >= 40 and crops.size() >= 4 and on_pad == 0,
		"farmland: %d fields (%s), none within %.0f m of a pad (a landmark farm's yard%s)" % [seen.size(), crops, ZoneFeatures.FIELD_PAD_M, " here" if landmark_farm else ": none in this zone"])
	var s := ZoneScatter.new()
	s.generate(t, def)
	var orchard := 0
	var in_field: Array[String] = []
	var lane_fences := 0
	var pylons_in_fields := 0
	for item: Dictionary in s.items:
		if item.get("orchard", false):
			orchard += 1
			continue
		var kind := int(item.kind)
		if kind == ZoneScatter.Kind.VALUABLE or kind == ZoneScatter.Kind.ANIMAL:
			continue  # (a placement mark; animals wander)
		var shape := String(item.get("shape", ""))
		var id := f.field_at(item.pos.x, item.pos.z)
		if shape in ZoneProps.FIELD_OK:
			pylons_in_fields += 1 if id >= 0 else 0
			continue  # the power lines cross the fields (a call)
		if shape.begins_with("fence_") or shape.begins_with("gate_"):
			var on_lane := false
			for d: Vector2 in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
				on_lane = on_lane or f.field_at(item.pos.x + d.x, item.pos.z + d.y) >= 0
			lane_fences += 1 if on_lane and id < 0 else 0
		if id >= 0:
			in_field.append("%s %s" % [ZoneScatter.Kind.keys()[kind], shape])
	var farms := int(s.props_report.get("farms", 0))
	check(f.orchards.size() >= 1 and orchard >= 40 and in_field.is_empty() and farms >= 2 and lane_fences >= 40,
		"farmland: %d orchards (%d fruit trees in rows); nothing of the scatter's or the prop library's in a crop field (%s); %d farmsteads off the fields, %d fence and gate sections down the lanes between them (F-187); %d pylons and poles stand in fields" % [
			f.orchards.size(), orchard, in_field.slice(0, 6), farms, lane_fences, pylons_in_fields])
	var channels := 0
	var wadeable := 0
	var depths := Vector2(INF, 0.0)
	for bi in t.water.bodies.size():
		var b: Dictionary = t.water.bodies[bi]
		if String(b.kind) != "channel":
			continue
		channels += 1
		var deepest := 0.0
		for u in range(int(b.lo), int(b.hi) + 1):
			deepest = maxf(deepest, float(t.water.sample_at(bi, u).depth))
		depths = Vector2(minf(depths.x, deepest), maxf(depths.y, deepest))
		if deepest > 0.15 and deepest < Wading.NO_SPRINT_M:
			wadeable += 1
	var culverts := t.water.crossings.filter(func(c: Dictionary) -> bool: return String((t.water.bodies[int(c.body)] as Dictionary).kind) == "channel").size()
	check(channels >= 2 and wadeable >= channels * 0.8, "farmland: %d irrigation channels along field edges, %d of them shallow water to wade (deepest %.2f-%.2f m); %d road crossings over them (culverts and fords)" % [
		channels, wadeable, depths.x, depths.y, culverts])
	# Crops by season: what stands in a field in summer, and in winter.
	var wheat := -1
	var maize := -1
	for id in f.field_crops.size():
		if f.field_crops[id] == "wheat" and wheat < 0:
			wheat = id
		if f.field_crops[id] == "maize" and maize < 0:
			maize = id
	var summer_w := f.crop_of(wheat)
	var summer_m := f.crop_of(maize)
	var tw := _terrain(def.merged({"season": "winter"}, true))
	var winter_w := tw.features.crop_of(wheat)
	var winter_m := tw.features.crop_of(maize)
	check(float(summer_m.height) > 1.8 and float(summer_w.height) > 0.7 and float(winter_w.height) < 0.1 and float(winter_m.height) < 0.3
		and summer_w.colour != winter_w.colour and tw.checksum() != t.checksum() and hash(tw.heights) == hash(t.heights),
		"farmland: crops by season: summer maize %.1f m and wheat %.1f m, winter %.1f m and %.1f m of stubble, other colours; the ground the same" % [
			float(summer_m.height), float(summer_w.height), float(winter_m.height), float(winter_w.height)])
	var prone := _find_cover_crop(f, t, "wheat", PRONE_M)
	var standing := _find_cover_crop(f, t, "wheat", 1.5)
	var in_maize := _find_cover_crop(f, t, "maize", 1.5)
	check(prone >= Spotting.FOLIAGE_OPAQUE_M and standing < Spotting.FOLIAGE_OPAQUE_M * 0.5 and in_maize >= Spotting.FOLIAGE_OPAQUE_M,
		"farmland in summer: a man prone in the wheat is hidden from 80 m (%.1f foliage metres), standing in it he isn't (%.1f); standing in the maize he is (%.1f)" % [prone, standing, in_maize])
	s.free()
	tw.free()
	t.free()


## Foliage metres on the line from 80 m off to a man `up` m over the ground in the middle of a field
## of `crop` (-1 with none found).
static func _find_cover_crop(f: ZoneFeatures, t: ZoneTerrain, crop: String, up: float) -> float:
	for k in 6000:
		var p := Vector2(fposmod(k * 37.1, t.size_m * 0.8) - t.size_m * 0.4, fposmod(k * 53.9, t.size_m * 0.8) - t.size_m * 0.4)
		var id := f.field_at(p.x, p.y)
		if id < 0 or f.field_crops[id] != crop:
			continue
		var o := p + Vector2(80.0, 0.0)
		var ok := true
		for d in range(5, 30, 5):
			var q := p + Vector2(d, 0.0)
			ok = ok and f.field_at(q.x, q.y) == id
		if not ok:
			continue
		var target := Vector3(p.x, t.height_at(p.x, p.y) + up, p.y)
		var eye := Vector3(o.x, t.height_at(o.x, o.y) + EYE_M, o.y)
		var m := f.cover_least(eye, target, target)
		return minf(m.x, m.y)
	return -1.0


func _test_same_seed() -> void:
	for preset: String in ["marsh", "snow_mountain", "farmland"]:
		var def := _def(preset, 81, 1536.0)
		var a := _terrain(def)
		var b := _terrain(def)
		var other := _terrain(ZoneDef.normalize(def.merged({"seed": 82}, true)))
		var sa := ZoneScatter.new()
		sa.generate(a, def)
		ZoneScatter.clear_cache(false)
		var sb := ZoneScatter.new()
		sb.generate(b, def)
		check(a.features != null and a.checksum() == b.checksum() and a.features.checksum() == b.features.checksum() and a.checksum() != other.checksum()
			and sa.checksum() == sb.checksum() and sa.total() > 200,
			"%s: the same seed builds the same ground, water, features and scatter (%d items), another seed another" % [preset, sa.total()])
		sa.free()
		sb.free()
		a.free()
		b.free()
		other.free()


func _test_procedural() -> void:
	var found := {}
	for k in 400:
		var seed_value := 9000 + k
		var p := TerrainPresets.get_preset("%s%d" % [TerrainPresets.MIX, seed_value])
		var name := String(p.get("name", ""))
		for want: String in ["Marsh", "Snowy mountain pass", "Farmland"]:
			if name.contains(want) and not found.has(want):
				found[want] = seed_value
		if found.size() == 3:
			break
	check(found.size() == 3, "procedural mixes take the new presets (seeds %s)" % [found])
	for want: String in found:
		var seed_value: int = found[want]
		var def := ZoneDef.normalize(ZoneDef.generate(seed_value, 1536.0).merged({"terrain": "procedural", "id": "test_terrain_mix", "name": "Mix"}, true))
		var a := _terrain(def)
		var b := _terrain(def)
		var spec: Dictionary = a.preset.get("features", {})
		var has_part := spec.has("marsh") if want == "Marsh" else (spec.has("snow") if want.begins_with("Snowy") else spec.has("fields"))
		check(String(def.terrain).begins_with(TerrainPresets.MIX) and a.features != null and has_part and a.checksum() == b.checksum(),
			"procedural %s (%s): its features %s, the same twice" % [def.terrain, a.preset.get("name", ""), spec.keys()])
		a.free()
		b.free()


func _test_campaign() -> void:
	var want := {"blackwater_fen": "marsh", "whitecap_pass": "snow_mountain", "harrow_fields": "farmland"}
	for id: String in want:
		var def := MissionRegistry.zone_def(id)
		var z := MissionRegistry.zone(id)
		var linked := RegionMap.links(id).size() >= 1
		var offered := MissionRegistry.zones_for(def.get("modules", []).map(func(m: Dictionary) -> String: return ZoneModules.base(String(m.type))), "contract").any(
			func(e: Dictionary) -> bool: return e.zone_id == id)
		check(String(def.get("terrain", "")) == want[id] and String(z.get("kind", "")) == "contract" and linked and offered,
			"the campaign's %s (%s) is %s, a contract zone a contract can go to, linked to %d neighbours" % [z.get("name", id), id, def.get("terrain", "?"), RegionMap.links(id).size()])
	check(TerrainPresets.choose({"name": "Reed Fen"}) == "marsh" and TerrainPresets.choose({"name": "Snowfield"}) == "snow_mountain" and TerrainPresets.choose({"name": "Wadi farm", "region": "inland"}) == "desert_wadi",
		"zone names pick the new presets (a fen, snow), Wadi farm stays desert_wadi")


func _test_cost() -> void:
	var worst := {}
	for id: String in ["blackwater_fen", "whitecap_pass", "harrow_fields", "red_mesa"]:
		var def := MissionRegistry.zone_def(id)
		var started := Time.get_ticks_usec()
		var t := _terrain(def)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		worst[id] = [snappedf(ms, 1.0), snappedf(t.features.carve_ms if t.features else 0.0, 1.0)]
		t.free()
	var ok := true
	for id: String in worst:
		ok = ok and float(worst[id][1]) < 600.0
	check(ok, "what the features cost to carve on the campaign zones ([heights in all ms, features ms]): %s (features under 600 ms)" % [worst])


func _pick_hosted() -> Dictionary:
	for seed_value in SEEDS:
		var def := _def("snow_mountain", seed_value).merged({"season": "winter"}, true)
		var t := _terrain(def)
		var f := t.features
		var frozen := t.water != null and t.water.bodies.any(func(b: Dictionary) -> bool: return b.get("frozen", false) and String(b.kind) == "stream")
		var gully := f != null and not _gully_spot(f, t).is_empty() and not _cover_case(f, t).is_empty()
		var ok := f != null and not f.cliffs.is_empty() and gully and frozen
		print("  seed %d: %d cliffs, %d gullies, frozen stream %s" % [seed_value, f.cliffs.size() if f else 0, f.lines.size() if f else 0, frozen])
		t.free()
		if ok:
			return def
	check(false, "a snow_mountain seed among %s with a cliff, a gully and a frozen stream" % [SEEDS])
	return {}


## A gully spot for the cover search: [its floor (Vector2), the way to the threat (unit)] where, on
## the heights, a man crouched (0.9 m) on its floor is hidden from a threat 70 m off on the flat and
## standing 10 to 16 m out toward it he isn't; [] with none.
static func _cover_case(f: ZoneFeatures, t: ZoneTerrain) -> Array:
	for l: Dictionary in f.lines:
		if String(l.kind) != "gully":
			continue
		for s: Array in _deep_spots(f, l):
			var p := _floor_at(t, s[0])
			var side := Vector2(-(s[1] as Vector2).y, (s[1] as Vector2).x)
			for sign: float in [1.0, -1.0]:
				var toward := side * sign
				var o := p + toward * 70.0
				var eye := Vector3(o.x, t.height_at(o.x, o.y) + 1.5, o.y)
				if _clear(t, eye, Vector3(p.x, t.height_at(p.x, p.y) + 0.9, p.y)):
					continue
				var open := true
				for d: float in [10.0, 12.0, 14.0, 16.0]:
					var q := p + toward * d
					open = open and _clear(t, eye, Vector3(q.x, t.height_at(q.x, q.y) + 0.9, q.y))
				if open:
					return [p, toward]
	return []


## A full-depth spot in a gully of `f` hidden from every line from the flat round it (at least 8
## of them) to a man 0.6 m over its floor (margin: a prone man's eyes and back sit over PRONE_M),
## or []: [Vector2, its direction].
static func _gully_spot(f: ZoneFeatures, t: ZoneTerrain) -> Array:
	for l: Dictionary in f.lines:
		if String(l.kind) == "gully":
			for s: Array in _deep_spots(f, l):
				var h := _hidden_from_flat(t, _floor_at(t, s[0]), s[1], 0.6)
				if h.y >= 8 and h.x == h.y:
					return s
	return []


# --- Hosted ----------------------------------------------------------------------------------

func _test_gully_cover() -> void:
	var f := level.terrain.features
	var t := level.terrain
	var spot := _gully_spot(f, t)
	check(not spot.is_empty(), "a gully spot hidden from every flat line")
	if spot.is_empty():
		return
	var p := _floor_at(t, spot[0])
	var dir: Vector2 = spot[1]
	var side := Vector2(-dir.y, dir.x)
	await _park_player(Vector3(p.x, 0.0, p.y) + Vector3(side.x, 0.0, side.y) * 30.0)
	var hider := _soldier(Vector3(p.x, t.height_at(p.x, p.y) + 0.1, p.y), "Hider")
	var o := p + side * 70.0
	var watcher := _soldier(Vector3(o.x, t.height_at(o.x, o.y) + 0.1, o.y), "Watcher")
	_face(watcher, -side)
	hider.want_stance = SoldierMovement.Stance.PRONE
	hider.movement.set_stance(SoldierMovement.Stance.PRONE)
	await _frames(90)
	var brain := SquadAI.of(watcher)
	var world := level.get_world_3d()
	var eye := watcher.camera.global_position
	var to_chest := Throwables.clear_line(world, eye, hider.aim_point())
	var to_head := Throwables.clear_line(world, eye, hider.camera.global_position)
	var seen := brain != null and brain.can_see(hider)
	check(hider.movement.is_prone() and not to_chest and not to_head and brain != null and not seen,
		"a man prone in a gully (%.1f m deep there): the rays from a watcher 70 m off on the flat hit the ground (chest clear %s, head clear %s; his head %.2f m over the floor), the AI can't see him (SquadAI.can_see %s)" % [
			f.cut_at(roundi((p.x + t.size_m * 0.5) / ZoneTerrain.CELL_M), roundi((p.y + t.size_m * 0.5) / ZoneTerrain.CELL_M)), to_chest, to_head,
			hider.camera.global_position.y - t.height_at(p.x, p.y), seen])
	# The same man standing up on the flat beside it is seen.
	var q := p + side * 22.0
	hider.global_position = Vector3(q.x, t.height_at(q.x, q.y) + 0.1, q.y)
	hider.want_stance = SoldierMovement.Stance.STAND_HIGH
	hider.movement.set_stance(SoldierMovement.Stance.STAND_HIGH)
	await _frames(30)
	check(brain.can_see(hider), "standing on the flat beside the gully the watcher sees him")
	# The AI's cover search, from out in the open beside a gully with a threat across the flat, picks
	# the gully: a spot where he stands exposed and the gully's floor is hidden (on the heights).
	var case := _cover_case(f, t)
	check(not case.is_empty(), "a gully with open flat beside it on the threat's side")
	if case.is_empty():
		hider.queue_free()
		watcher.queue_free()
		return
	var floor_p: Vector2 = case[0]
	var toward: Vector2 = case[1]
	var stand := floor_p + toward * 13.0
	var threat := floor_p + toward * 70.0
	hider.global_position = Vector3(stand.x, t.height_at(stand.x, stand.y) + 0.1, stand.y)
	var hider_brain := SquadAI.of(hider)
	hider.threat_pos = Vector3(threat.x, t.height_at(threat.x, threat.y), threat.y)
	await _park_player(Vector3(stand.x, 0.0, stand.y) + Vector3(toward.x, 0.0, toward.y) * 8.0)
	await _frames(10)
	var exposed := hider_brain != null and not hider_brain._cover_protects(hider.global_position)
	var cover: Variant = hider_brain.find_cover(hider.global_position, 14.0) if hider_brain else null
	var cut := -1.0
	var across := INF
	var how := "none"
	if cover is Vector3:
		var c3: Vector3 = cover
		cut = f.cut_at(roundi((c3.x + t.size_m * 0.5) / ZoneTerrain.CELL_M), roundi((c3.z + t.size_m * 0.5) / ZoneTerrain.CELL_M))
		across = absf((Vector2(c3.x, c3.z) - floor_p).dot(toward))
		how = "down in it, crouched out of sight" if hider_brain._cover_protects(c3) else ("prone at its lip, firing over (a fold)" if hider_brain._fold_at(world, c3) else "uncovered")
	check(exposed and cover is Vector3 and (across < 10.0 or cut > 0.5) and how != "uncovered",  # (down in it, or at its lip; it bends)
		"the AI's cover search (SquadAI.find_cover), out in the open 13 m from a gully with a threat 57 m across the flat (in the open there: %s), picks the gully: %.1f m from its middle, cut %.1f m there, %s" % [exposed, across, cut, how])
	hider.queue_free()
	watcher.queue_free()
	await _frames(2)


func _test_cliff_hosted() -> void:
	var f := level.terrain.features
	var t := level.terrain
	var c: Dictionary = f.cliffs[0]
	for each: Dictionary in f.cliffs:
		if float(each.h) > float(c.h):
			c = each
	var u := 0.5
	for k in 9:
		var test_u := 0.3 + k * 0.05
		var foot := f.cliff_point(c, test_u, -4.0)
		var top := f.cliff_point(c, test_u, 4.0)
		if top.y - foot.y > float(c.h) * 0.75 and f._keep_at(Vector2(foot.x, foot.z), ZoneFeatures.CLIFF_ROAD_M) > 0.95:
			u = test_u
			break
	var foot := f.cliff_point(c, u, -5.0)
	var top := f.cliff_point(c, u, 5.0)
	var normal: Vector2 = c.normal
	var out := Vector3(normal.x, 0.0, normal.y)
	await _park_player(foot - out * 25.0)
	var from := f.cliff_point(c, u, -2.5) + Vector3.UP * 2.0
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + out * 8.0, 1))
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	check(not hit.is_empty() and hit_normal.y < 0.5, "a cliff's face has collision: a level ray 2 m up from its foot hits it %.1f m on (its normal %s: steep)" % [
		(hit.get("position", from) as Vector3).distance_to(from), hit_normal])
	var climber := _soldier(foot + Vector3.UP * 0.1, "Climber")
	_face(climber, normal)
	await _frames(10)
	climber.move_input = Vector2(0, -1)
	var highest := climber.global_position.y
	for k in 180:
		await get_tree().physics_frame
		highest = maxf(highest, climber.global_position.y)
	var mid_y := (foot.y + top.y) * 0.5
	check(top.y - foot.y > 8.0 and highest < mid_y, "a man walking into the face for 3 s doesn't get up it (highest %.1f m over its foot, half way %.1f m, the top %.1f m up)" % [
		highest - foot.y, mid_y - foot.y, top.y - foot.y])
	climber.queue_free()
	await _park_player(foot - out * 8.0)
	var map := level.get_world_3d().navigation_map
	var mid := foot.lerp(top, 0.5)
	var near_mid := NavigationServer3D.map_get_closest_point(map, mid)
	var path := NavigationServer3D.map_get_path(map, foot, top, true)
	var length := 0.0
	var steepest := 0.0
	for k in range(1, path.size()):
		length += path[k - 1].distance_to(path[k])
		var flat := Vector2(path[k].x - path[k - 1].x, path[k].z - path[k - 1].z).length()
		if flat > 0.3:
			steepest = maxf(steepest, rad_to_deg(atan2(absf(path[k].y - path[k - 1].y), flat)))
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(top) < 2.0
	check(near_mid.distance_to(mid) > 1.5 and steepest < 50.0 and (not reached or length > foot.distance_to(top) * 2.5),
		"the navigation mesh doesn't climb the face: nothing on it half way up (nearest %.1f m off), the way from foot to top %s (%.0f m against %.0f m straight, steepest step %.0f degrees)" % [
			near_mid.distance_to(mid), "goes round" if reached else "doesn't go straight up", length, foot.distance_to(top), steepest])


func _test_snow_slows() -> void:
	var f := level.terrain.features
	var t := level.terrain
	# Deep snow on the flat, and the insertion pad (packed, cleared ground).
	var snowy := Vector2.INF
	for k in 600:
		var p := Vector2(fposmod(k * 71.3, t.size_m * 0.6) - t.size_m * 0.3, fposmod(k * 43.7, t.size_m * 0.6) - t.size_m * 0.3)
		if f.slow_at(p.x, p.y) < 0.8 and t.normal_at(p.x, p.y).y > 0.98 and t.normal_at(p.x + 12.0, p.y).y > 0.97 and level.terrain.water_height(p.x, p.y) == -INF \
				and f.slow_at(p.x + 8.0, p.y) < 0.8:
			snowy = p
			break
	check(snowy.is_finite(), "a flat stretch of deep snow")
	if not snowy.is_finite():
		return
	var pad: Rect2 = t.pads[0][0]
	var on_pad := pad.get_center() - Vector2(pad.size.x * 0.3, 0.0)
	await _park_player(Vector3(snowy.x, 0.0, snowy.y) + Vector3(0, 0, 30))
	var in_snow := _soldier(Vector3(snowy.x, t.height_at(snowy.x, snowy.y) + 0.05, snowy.y), "Snow")
	var packed := _soldier(Vector3(on_pad.x, t.height_at(on_pad.x, on_pad.y) + 0.05, on_pad.y), "Packed")
	_face(in_snow, Vector2(1, 0))
	_face(packed, Vector2(1, 0))
	await _frames(20)
	var a0 := in_snow.global_position
	var b0 := packed.global_position
	for s: Soldier in [in_snow, packed]:
		s.move_input = Vector2(0, -1)
	for k in 120:
		await get_tree().physics_frame
	var a := Vector2(in_snow.global_position.x - a0.x, in_snow.global_position.z - a0.z).length()
	var b := Vector2(packed.global_position.x - b0.x, packed.global_position.z - b0.z).length()
	check(a < b * 0.92 and a > b * 0.55 and in_snow.movement.ground_mult < 0.85 and packed.movement.ground_mult == 1.0,
		"snow slows a man on foot: %.1f m in 2 s through deep snow (pace x%.2f), %.1f m on a cleared pad" % [a, in_snow.movement.ground_mult, b])
	in_snow.queue_free()
	packed.queue_free()
	await _frames(2)


func _test_ice() -> void:
	var t := level.terrain
	var w := t.water
	var bi := -1
	for k in w.bodies.size():
		var b: Dictionary = w.bodies[k]
		if b.get("frozen", false) and String(b.kind) == "stream":
			bi = k
			break
	var b: Dictionary = w.bodies[bi]
	var mid := w.sample_at(bi, (int(b.lo) + int(b.hi)) * 0.5)
	var p: Vector2 = mid.pos
	await _park_player(Vector3(p.x, 0.0, p.y) + Vector3(0, 0, 20))
	var skater := _soldier(Vector3(p.x, t.height_at(p.x, p.y) + 0.3, p.y), "Skater")
	await _frames(60)
	var feet := skater.global_position.y
	var near := NavigationServer3D.map_get_closest_point(level.get_world_3d().navigation_map, Vector3(p.x, t.height_at(p.x, p.y), p.y))
	check(skater.movement.wet == 0.0 and not skater.movement.swimming and absf(feet - float(mid.surface)) < 0.25 and near.distance_to(Vector3(p.x, t.height_at(p.x, p.y), p.y)) < 1.0,
		"a frozen stream is ice he stands on: no water at his feet (wet %.2f), feet %.2f m from the ice, on the navigation mesh" % [skater.movement.wet, feet - float(mid.surface)])
	skater.queue_free()
	await _frames(2)


# --- Plumbing --------------------------------------------------------------------------------

func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	GameState.delete_save()
	print("TERRAIN TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
