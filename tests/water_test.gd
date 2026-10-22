extends Node
## Water (queue item 1.1 of docs/cg_brief.md: ZoneWater, ZoneBridges, Wading). One process:
##   <exe> --headless --path . res://tests/water_test.tscn
## Generation (no level): on a river_valley zone a river runs edge to edge in a valley it cut,
## its surface falling all the way downstream, deep enough to swim, banks above it; streams flow
## downhill too; the same seed builds the same water, another seed other water; pads stay flat
## and dry; every road over the river has a bridge, and no stretch of river longer than the gap
## goes without a crossing; deep water is out of the navigation mesh; no scatter in the water;
## reeds on the banks; the campaign's Kestrel Valley (river_valley) has its river; the other
## presets' water (streams, ponds) and none on the dry ones.
## Hosted (the same zone): wading slows a man, deep water makes him swim (hands busy, drifting
## downstream); the navigation routes over a bridge, not through deep water beside it; a truck
## drives over a bridge and through a ford; a footbridge drops to one demolition block, a
## concrete span to three; a truss span to 105 mm HE; the navigation stops using a dropped span;
## the drops are saved with the zone and come back on a restore and for a late joiner; and the
## cost: the carve's time, a water query, and the physics frame with men wading.
## Prints WATER TEST PASSED/FAILED and exits with its failure count.

const SIZE_M := 2048.0
## Seeds tried for the hosted zone: the first whose river has a vehicle bridge, a footbridge and
## a ford wins.
const SEEDS: Array[int] = [20, 13, 11, 18, 12, 15, 16, 14, 17, 19]
const WADERS := 12

var failures := 0
var main: Node
var level: ZoneLevel
var water: ZoneWater
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_water" + tag
	Campaign.campaign_id = "test_water" + tag
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	Vehicle.fire_rolls = false
	get_tree().create_timer(460.0).timeout.connect(func() -> void:
		print("WATER TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	print("Generation")
	ZoneScatter.clear_cache(true)  # layouts from this run's code, not an older run's disk cache
	var def := _pick_def()
	if def.is_empty():
		_finish()
		return
	_test_generation(def)
	_test_kestrel_and_presets()
	print("Hosted")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and level.terrain.water != null, "hosting the river valley zone (seed %d)" % int(def.seed))
	if level == null or level.terrain.water == null:
		_finish()
		return
	water = level.terrain.water
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	var fresh := _terrain(def)
	check(fresh.water.checksum() == water.checksum() and fresh.checksum() == level.terrain.checksum(),
		"the hosted zone's water is the same as a fresh build from its seed (every peer and late joiner builds it)")
	fresh.free()
	await _test_wading()
	await _test_swimming()
	await _test_nav_over_bridge()
	await _test_vehicle_bridge()
	await _test_ford()
	await _test_demolition()
	await _test_fire_support()
	await _test_nav_after_drop()
	_test_save_and_join()
	await _test_cost(def)
	_finish()


# --- Generation -----------------------------------------------------------------------------

func _def(seed_value: int) -> Dictionary:
	return ZoneDef.normalize(ZoneDef.generate(seed_value, SIZE_M).merged({"terrain": "river_valley", "id": "test_water", "name": "Water test"}, true))


## The flat pads a level would give `def` (ZoneLevel._flat_areas).
static func _flat(def: Dictionary) -> Array:
	var flat: Array = []
	for m: Dictionary in def.modules:
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		flat.append(Rect2(p - half, half * 2.0))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return flat


func _terrain(def: Dictionary) -> ZoneTerrain:
	var t := ZoneTerrain.new()
	t.generate(def, _flat(def))
	return t


func _kinds(w: ZoneWater) -> Dictionary:
	var out := {}
	for c: Dictionary in w.crossings:
		var key := String(c.kind)
		if key == ZoneBridges.FORD and String((w.bodies[int(c.body)] as Dictionary).kind) == "river":
			key = "river_ford"
		out[key] = int(out.get(key, 0)) + 1
	return out


func _pick_def() -> Dictionary:
	for seed_value in SEEDS:
		var def := _def(seed_value)
		var t := _terrain(def)
		var k := _kinds(t.water) if t.water else {}
		var ok := t.water != null and (k.has(ZoneBridges.CONCRETE) and k.has(ZoneBridges.TRUSS)) and k.has(ZoneBridges.FOOT) and k.has("river_ford")
		print("  seed %d: crossings %s" % [seed_value, k])
		t.free()
		if ok:
			return def
	check(false, "a seed among %s gives a river with a concrete and a truss bridge, a footbridge and a ford" % [SEEDS])
	return {}


func _river(w: ZoneWater) -> int:
	for bi in w.bodies.size():
		if String((w.bodies[bi] as Dictionary).kind) == "river":
			return bi
	return -1


func _test_generation(def: Dictionary) -> void:
	var t := _terrain(def)
	var w := t.water
	var dry_def := def.duplicate(true)
	dry_def["no_water"] = true
	var base := _terrain(dry_def)
	check(w != null and w.count_of("river") == 1 and w.count_of("stream") >= 1 and w.count_of("lake") >= 1,
		"river_valley: a river, %d streams, %d ponds (carved in %.0f ms: %s)" % [w.count_of("stream"), w.count_of("lake"), w.carve_ms(), w.timings])
	var ri := _river(w)
	var r: Dictionary = w.bodies[ri]
	var pts: PackedVector2Array = r.pts
	var surf: PackedFloat32Array = r.w
	var lo := int(r.lo)
	var hi := int(r.hi)
	# It runs edge to edge.
	var first := pts[lo]
	var last := pts[hi]
	var edge := t.size_m * 0.5 - 30.0
	check(maxf(absf(first.x), absf(first.y)) > edge and maxf(absf(last.x), absf(last.y)) > edge,
		"the river runs edge to edge ((%.0f, %.0f) to (%.0f, %.0f), %.1f km)" % [first.x, first.y, last.x, last.y, (hi - lo) * ZoneWater.STEP_M / 1000.0])
	# Downhill all the way: never rising downstream, and falling in all.
	var down := int(r.down)
	var rises := 0
	for i in range(lo, hi):
		if (surf[i + 1] - surf[i]) * down > 0.001:
			rises += 1
	var drop := (surf[lo] - surf[hi]) * down
	check(rises == 0 and drop > 1.0, "it flows downhill: its surface never rises downstream and falls %.1f m from end to end" % drop)
	# A valley it cut: deep in its channel, its floor its banks' height, the ground lower than before.
	var deep := 0
	var cut := 0.0
	var banks_ok := 0
	var samples := 0
	var floor_cut := 0.0
	for i in range(lo, hi, 4):
		var p := pts[i]
		if maxf(absf(p.x), absf(p.y)) > t.size_m * 0.5 - 200.0 or _near_crossing(w, ri, i, 30.0):
			continue
		samples += 1
		var at := w.sample_at(ri, i)
		if float(at.depth) >= Wading.SWIM_DEPTH_M:
			deep += 1
		cut += base.height_at(p.x, p.y) - t.height_at(p.x, p.y)
		var tan := ZoneWater.tangent(r, i)
		var side := Vector2(-tan.y, tan.x)
		var inner := float((r.half as PackedFloat32Array)[i]) + float((r.bank_w as PackedFloat32Array)[i])
		var bank := p + side * (inner + 1.0)
		var bank_h := t.height_at(bank.x, bank.y) - surf[i]
		if bank_h > float(r.bank_h) * 0.5 and bank_h < float(r.bank_h) + 1.5:
			banks_ok += 1
		var out := p + side * (inner + 25.0)
		floor_cut += base.height_at(out.x, out.y) - t.height_at(out.x, out.y)
	check(samples > 20 and deep >= samples * 0.9, "deep enough to swim in %d of %d places along it (over %.2f m)" % [deep, samples, Wading.SWIM_DEPTH_M])
	check(cut / maxf(samples, 1) > 2.0 and banks_ok >= samples * 0.85,
		"it cut its channel %.1f m into the ground on average; its banks stand over the water in %d of %d places" % [cut / maxf(samples, 1), banks_ok, samples])
	print("  (the valley 25 m out from the banks: %.1f m lower than the land was, on average)" % (floor_cut / maxf(samples, 1)))
	# The current runs downstream.
	var mid := pts[(lo + hi) / 2]
	var flow := w.flow_at(mid.x, mid.y)
	var tan_mid := ZoneWater.tangent(r, (lo + hi) / 2.0) * down
	check(flow.length() > 0.5 and Vector2(flow.x, flow.z).normalized().dot(tan_mid) > 0.9, "its current runs downstream (%.2f m/s)" % flow.length())
	# Streams flow downhill too, and end in the river (or a pond, or off the edge).
	var streams_ok := true
	for b: Dictionary in w.bodies:
		if String(b.kind) != "stream":
			continue
		var sw: PackedFloat32Array = b.w
		for i in range(int(b.lo), int(b.hi)):
			streams_ok = streams_ok and sw[i + 1] <= sw[i] + 0.001
		streams_ok = streams_ok and float(b.perched) <= ZoneWater.PERCHED_MAX
	check(streams_ok, "every stream flows downhill and none runs on a dyke")
	# The same seed builds the same; another seed other water.
	var again := _terrain(def)
	var other := _terrain(def.merged({"seed": int(def.seed) + 1}, true))
	check(again.water.checksum() == w.checksum() and again.checksum() == t.checksum() and other.water != null and other.water.checksum() != w.checksum(),
		"the same seed builds the same rivers and crossings, another seed other ones")
	again.free()
	other.free()
	# Pads flat and dry.
	var flat_ok := true
	var dry := true
	for pad: Array in t.pads:
		var rect: Rect2 = (pad[0] as Rect2).grow(-ZoneTerrain.PAD_MARGIN_M)
		for p in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), rect.get_center()]:
			flat_ok = flat_ok and absf(t.height_at(p.x, p.y) - float(pad[1])) < 0.01
			dry = dry and w.depth_at(p.x, p.y) == 0.0
	check(flat_ok and dry, "every pad stays flat and dry (%d pads)" % t.pads.size())
	# Roads over the river have bridges; no long stretch without a crossing.
	var bridged := true
	for road: Array in def.roads:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var e := Vector2(float(road[1][0]), float(road[1][1]))
		for i in range(lo, hi):
			var hit: Variant = Geometry2D.segment_intersects_segment(a, e, pts[i], pts[i + 1])
			if hit == null or not w._inside(hit, ZoneWater.CROSSING_EDGE_M):
				continue
			bridged = bridged and w.bridges.bridges.any(func(b: Dictionary) -> bool:
				var o: Vector3 = (b.xform as Transform3D).origin
				return Vector2(o.x, o.z).distance_to(hit) < ZoneWater.CROSSING_MIN_GAP_M and String(b.type) != ZoneBridges.FOOT)
	var at: Array[float] = []
	for c: Dictionary in w.crossings:
		if int(c.body) == ri:
			at.append(float(c.u))
	at.sort()
	var gap := 0.0
	for k in range(1, at.size()):
		gap = maxf(gap, (at[k] - at[k - 1]) * ZoneWater.STEP_M)
	check(bridged and gap <= float(t.preset.water.get("crossing_gap_m", ZoneWater.CROSSING_GAP_M)) + 2.0 * ZoneWater.STEP_M,
		"every road over the river has a bridge; the crossings along it (%s) are never more than %.0f m apart" % [_kinds(w), gap])
	# Deep water is out of the navigation mesh.
	var p := w.sample_at(ri, (lo + hi) / 2.0).pos as Vector2
	var faces := t.triangles_in(Rect2(p - Vector2(40, 40), Vector2(80, 80)))
	var deep_tris := 0
	var worst := 0.0
	for k in range(0, faces.size(), 3):
		var centre := (faces[k] + faces[k + 1] + faces[k + 2]) / 3.0
		var deep_m := w.depth_at(centre.x, centre.z)
		worst = maxf(worst, deep_m)
		if deep_m > ZoneWater.NAV_WATER_M + 0.35:
			deep_tris += 1
	check(deep_tris == 0 and faces.size() > 0, "the navigation's ground leaves deep water out (%d triangles round the river's middle, the deepest %.2f m under water at its middle)" % [faces.size() / 3, worst])
	# No scatter in the water; reeds along the banks.
	var scatter := ZoneScatter.new()
	scatter.generate(t, def)
	var wet := 0
	for item: Dictionary in scatter.items:
		var ip: Vector3 = item.pos
		if w.depth_at(ip.x, ip.z) > 0.05 or w.bridges.covers(Vector2(ip.x, ip.z)):
			wet += 1
	check(wet == 0 and scatter.total() > 500, "no rocks, trees or scrub in the water or on a bridge (%d items)" % scatter.total())
	scatter.free()
	var reeds := w._reeds()
	check(reeds != null and reeds.multimesh.instance_count > 100, "reeds along the banks (%d clumps)" % (reeds.multimesh.instance_count if reeds else 0))
	if reeds:
		reeds.free()
	var verts := 0
	for b: Dictionary in w.bodies:
		var mesh := w._lake_mesh(b) if String(b.kind) == "lake" else w._line_mesh(b)
		if mesh:
			verts += (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("  (the water's surfaces: %d triangles; bridges: %d)" % [verts / 3, w.bridges.bridges.size()])
	t.free()
	base.free()


func _near_crossing(w: ZoneWater, bi: int, u: float, m: float) -> bool:
	for c: Dictionary in w.crossings:
		if int(c.body) == bi and absf(float(c.u) - u) * ZoneWater.STEP_M < m + ZoneWater.FORD_HALF_M * 2.0:
			return true
	return false


func _test_kestrel_and_presets() -> void:
	var def := ZoneDef.normalize(MissionRegistry.zone_def("kestrel_valley"))
	var t := _terrain(def)
	var dry := true
	for m: Dictionary in def.modules:
		dry = dry and t.water.depth_at(float(m.pos[0]), float(m.pos[1])) == 0.0
	check(String(def.terrain) == "river_valley" and t.water != null and t.water.count_of("river") == 1 and dry,
		"Kestrel Valley (the campaign's river valley) has its river and %d bridges, every site dry" % (t.water.bridges.bridges.size() if t.water else 0))
	t.free()
	for preset: String in ["temperate", "highland_moor", "scrubland", "desert_wadi", "plain"]:
		var d := ZoneDef.normalize(ZoneDef.generate(777, 1536.0).merged({"terrain": preset}, true))
		var pt := _terrain(d)
		var want := TerrainPresets.get_preset(preset).has("water")
		var desc := "no water" if pt.water == null else "%d streams, %d ponds or lakes" % [pt.water.count_of("stream"), pt.water.count_of("lake")]
		check((pt.water != null) == want, "preset %s: %s" % [preset, desc])
		pt.free()


# --- Hosted ---------------------------------------------------------------------------------

## Host: an AI soldier (no brain running) at `pos`.
func _soldier(pos: Vector3, callsign := "") -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": callsign if callsign != "" else "WT%d" % _made, "faction": "friendly", "variant": "woodland", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _face(s: Soldier, dir: Vector2) -> void:
	s.global_rotation = Vector3(0.0, atan2(-dir.x, -dir.y), 0.0)


func _river_ford() -> Dictionary:
	for c: Dictionary in water.crossings:
		if String(c.kind) == ZoneBridges.FORD and String((water.bodies[int(c.body)] as Dictionary).kind) == "river":
			return c
	return {}


func _bridge(type: String) -> int:
	for bi in water.bridges.bridges.size():
		if String(water.bridges.bridges[bi].type) == type:
			return bi
	return -1


## Bridge `bi`'s span over the deepest water.
func _water_span(bi: int) -> int:
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var best := 0
	var deepest := -INF
	for k in (b.spans as Array).size():
		var span: Dictionary = b.spans[k]
		var mid := xf * Vector3(0, 0, (float(span.z0) + float(span.z1)) * 0.5)
		var d := water.depth_at(mid.x, mid.z)
		if d > deepest:
			deepest = d
			best = k
	return best


## A deep stretch of the river well away from any crossing: [sample, its point].
func _deep_spot() -> Array:
	var ri := _river(water)
	var r: Dictionary = water.bodies[ri]
	var lo := int(r.lo)
	var hi := int(r.hi)
	for k in range(0, hi - lo, 3):
		var i := (lo + hi) / 2 + (k / 2 if k % 2 == 0 else -k / 2)
		var at := water.sample_at(ri, i)
		var p: Vector2 = at.pos
		if float(at.depth) > 1.9 and not _near_crossing(water, ri, i, 60.0) and maxf(absf(p.x), absf(p.y)) < SIZE_M * 0.5 - 250.0:
			return [i, p]
	return []


func _test_wading() -> void:
	var c := _river_ford()
	var pos: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var t := level.terrain
	# One wades across the ford from just short of its middle; one walks on dry ground well away.
	var start := pos - dir * 4.0
	var wader := _soldier(Vector3(start.x, t.height_at(start.x, start.y) + 0.05, start.y), "Wader")
	var dry_at := _dry_spot(pos + Vector2(-dir.y, dir.x) * 90.0)
	var walker := _soldier(Vector3(dry_at.x, t.height_at(dry_at.x, dry_at.y) + 0.05, dry_at.y), "Walker")
	_face(wader, dir)
	_face(walker, dir)
	await _frames(20)
	var a0 := wader.global_position
	var b0 := walker.global_position
	var depth_seen := 0.0
	for s: Soldier in [wader, walker]:
		s.move_input = Vector2(0, -1)
	for f in 120:
		await get_tree().physics_frame
		depth_seen = maxf(depth_seen, wader.movement.wet)
	var wade := Vector2(wader.global_position.x - a0.x, wader.global_position.z - a0.z).length()
	var walk := Vector2(walker.global_position.x - b0.x, walker.global_position.z - b0.z).length()
	check(depth_seen > 0.25 and wade < walk * 0.85 and wade > walk * 0.3,
		"wading a ford %.2f m deep he goes %.1f m in 2 s, %.0f%% of a man on dry ground (%.1f m): water slows him" % [depth_seen, wade, wade / maxf(walk, 0.01) * 100.0, walk])
	check(Wading.speed_mult(0.5) < 0.75 and Wading.speed_mult(1.0) < 0.4 and Wading.speed_mult(0.05) == 1.0,
		"the pace in water: knee-deep %.2f, waist-deep %.2f of it" % [Wading.speed_mult(0.5), Wading.speed_mult(1.0)])
	for s: Soldier in [wader, walker]:
		s.queue_free()
	await _frames(2)


## A spot near `p` with no water.
func _dry_spot(p: Vector2) -> Vector2:
	for k in 40:
		var q := p + Vector2.from_angle(k * 0.7) * k * 6.0
		if water.surface_at(q.x, q.y) == -INF and level.terrain.normal_at(q.x, q.y).y > 0.97:
			return q
	return p


func _test_swimming() -> void:
	var spot := _deep_spot()
	check(not spot.is_empty(), "a deep stretch of river away from the crossings")
	if spot.is_empty():
		return
	var p: Vector2 = spot[1]
	var surface := water.surface_at(p.x, p.y)
	var swimmer := _soldier(Vector3(p.x, surface - 0.6, p.y), "Swimmer")
	await _frames(90)
	var feet := swimmer.global_position.y
	var drift_from := swimmer.global_position
	check(swimmer.movement.swimming and absf(feet - (surface - Wading.SWIM_FLOAT_M)) < 0.3 and swimmer._busy_until > Soldier._now() and swimmer.movement.stance == SoldierMovement.Stance.STAND_HIGH,
		"in water %.1f m deep he swims, head and shoulders out (feet %.2f m under), standing, hands busy" % [surface - level.terrain.height_at(p.x, p.y), surface - feet])
	await _frames(120)
	var drift := swimmer.global_position - drift_from
	var flow := water.flow_at(p.x, p.y)
	check(Vector2(drift.x, drift.z).dot(Vector2(flow.x, flow.z).normalized()) > 0.4, "left alone he drifts downstream (%.1f m in 2 s on a %.1f m/s current)" % [Vector2(drift.x, drift.z).length(), flow.length()])
	var from := swimmer.global_position
	_face(swimmer, Vector2(-flow.z, flow.x).normalized())
	swimmer.move_input = Vector2(0, -1)
	await _frames(120)
	var moved := Vector2(swimmer.global_position.x - from.x, swimmer.global_position.z - from.z).length() / 2.0
	check(swimmer.movement.swimming and moved < Wading.SWIM_SPEED + flow.length() + 0.4 and moved > 0.3,
		"swimming across he makes %.1f m/s (swim %.1f, the current %.1f): slow" % [moved, Wading.swim_speed(swimmer.movement.load_fraction()), flow.length()])
	swimmer.queue_free()
	await _frames(2)


## The way across vehicle bridge `bi`: [from, to] on the ground `out` m past each end, `side` m to
## its right.
func _across(bi: int, out: float, side := 0.0) -> Array:
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var reach := float(b.length) * 0.5 + out
	var a := xf * Vector3(side, 0, -reach)
	var e := xf * Vector3(side, 0, reach)
	return [level.ground_point(a), level.ground_point(e)]


func _test_nav_over_bridge() -> void:
	var bi := _bridge(ZoneBridges.CONCRETE)
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var player := level.players.get_node(^"1") as Soldier
	player.global_position = xf.origin + Vector3.UP * 0.2  # the navigation bakes round him
	player.velocity = Vector3.ZERO
	level.nav.refresh()
	await _wait_for(func() -> bool: return level.nav.is_settled(), 40.0)
	var ends := _across(bi, 10.0, 12.0)  # a straight line between them crosses deep water beside the bridge
	var path := NavigationServer3D.map_get_path(level.get_world_3d().navigation_map, ends[0], ends[1], true)
	var deepest := -INF
	var on_deck := false
	for k in range(1, path.size()):
		for s in 10:
			var q := path[k - 1].lerp(path[k], s / 10.0)
			var surface := water.surface_at(q.x, q.z)
			if surface > -INF:
				deepest = maxf(deepest, surface - q.y)
			var local := xf.affine_inverse() * q
			if absf(local.x) < float(ZoneBridges.TYPES[b.type].deck_w) * 0.5 and absf(local.z) < float(b.length) * 0.25 and absf(local.y) < 0.8:
				on_deck = true
	check(path.size() >= 2 and path[path.size() - 1].distance_to(ends[1]) < 2.5 and on_deck and deepest < ZoneWater.NAV_WATER_M,
		"the navigation routes across the river over the %s (%d points, ends %.1f m from the far end, on the deck %s, deepest water on the way %.2f m), not through the deep water beside it" % [ZoneBridges.TYPES[b.type].name, path.size(), path[path.size() - 1].distance_to(ends[1]) if path.size() > 0 else -1.0, on_deck, maxf(deepest, 0.0)])


func _test_vehicle_bridge() -> void:
	var bi := _bridge(ZoneBridges.CONCRETE)
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	var ends := _across(bi, 16.0)
	var player := level.players.get_node(^"1") as Soldier
	var aside := _dry_spot(Vector2(xf.origin.x, xf.origin.z) + Vector2(xf.basis.x.x, xf.basis.x.z) * 70.0)
	player.global_position = level.ground_point(Vector3(aside.x, 0, aside.y))  # off the deck: not in the truck's way
	player.velocity = Vector3.ZERO
	var yaw := atan2(-xf.basis.z.x, -xf.basis.z.z)  # facing along +z of the bridge
	var truck := VehicleLayer.of(level).server_spawn("matv", Transform3D(Basis(Vector3.UP, yaw), (ends[0] as Vector3) + Vector3.UP * 1.0), "", &"player", "water_truck")
	var driver := _soldier((ends[0] as Vector3) + xf.basis.x * 4.0 + Vector3.UP * 0.2, "Driver")
	await _frames(30)
	truck.server_enter(driver, 0)
	var half := float(b.length) * 0.5
	truck.server_follow_path(PackedVector3Array([xf * Vector3(0, 0, -half - 3.0), xf * Vector3(0, 0, half + 3.0), ends[1]]), 15.0)
	var lowest := INF
	var wet := 0.0
	var deadline := Time.get_ticks_msec() + 60000
	while truck.ai.status != "arrived" and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var local := xf.affine_inverse() * truck.global_position
		if absf(local.z) < half - 3.0:
			lowest = minf(lowest, local.y)
		wet = maxf(wet, AavWater.depth(truck))
	var miss := Vector2(truck.global_position.x - (ends[1] as Vector3).x, truck.global_position.z - (ends[1] as Vector3).z).length()
	var where := xf.affine_inverse() * truck.global_position
	check(truck.ai.status == "arrived" and miss < VehicleAI.ARRIVE_M + 3.0 and lowest > -0.6 and wet == 0.0,
		"a truck drives over the %s (%.0f m) and on (%.1f m from its goal; never below the deck: lowest %.2f m; dry; %s at (%.1f, %.1f, %.1f) on the bridge)" % [ZoneBridges.TYPES[b.type].name, float(b.length), miss, lowest, truck.ai.status, where.x, where.y, where.z])
	truck.server_stop()
	truck.server_exit(driver)
	driver.queue_free()
	set_meta(&"truck", truck)


func _test_ford() -> void:
	var c := _river_ford()
	var truck := get_meta(&"truck") as Vehicle
	var driver := _soldier(truck.global_position + Vector3(3, 0.5, 0), "Driver2")
	var pos: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var ford: Dictionary = {}
	for f: Dictionary in water.bridges.fords:
		if String(f.id) == String(c.id):
			ford = f
	var reach := float(ford.get("half", 20.0)) + 14.0
	var a := pos - dir * reach
	var e := pos + dir * reach
	var start := level.ground_point(Vector3(a.x, 0, a.y))
	var goal := level.ground_point(Vector3(e.x, 0, e.y))
	truck.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), start + Vector3.UP * 1.0)
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	await _frames(30)
	truck.server_enter(driver, 0)
	truck.server_follow_path(PackedVector3Array([level.ground_point(Vector3(pos.x, 0, pos.y)), goal]), 10.0)
	var wet := 0.0
	var deadline := Time.get_ticks_msec() + 60000
	while truck.ai.status != "arrived" and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		wet = maxf(wet, AavWater.depth(truck))
	var miss := Vector2(truck.global_position.x - goal.x, truck.global_position.z - goal.z).length()
	var off := truck.global_position - level.ground_point(Vector3(pos.x, 0, pos.y))
	check(truck.ai.status == "arrived" and miss < VehicleAI.ARRIVE_M + 3.0 and wet > 0.0 and wet < AavWater.FORD_M,
		"a truck drives through the ford and out (water %.2f m over its floor at most, under its %.1f m fording depth; %.1f m from its goal, %s, %.1f m along the way from the ford's middle)" % [wet, AavWater.FORD_M, miss, truck.ai.status, Vector2(off.x, off.z).dot(dir)])
	truck.server_stop()
	truck.server_exit(driver)
	driver.queue_free()


## A demolition block set on bridge `bi`'s span `k` deck and fired; returns the block's id.
func _blast_block(bi: int, k: int, along := 0.5) -> String:
	var b: Dictionary = water.bridges.bridges[bi]
	var span: Dictionary = b.spans[k]
	var z := lerpf(float(span.z0), float(span.z1), along)
	var at := (b.xform as Transform3D) * Vector3(0, 0.05, z)
	var dem := Demolitions.of(level)
	var id := dem.server_place(null, &"demo_block", Transform3D(Basis(), at), null, "remote")
	dem.server_detonate(id)
	return id


func _test_demolition() -> void:
	var fi := _bridge(ZoneBridges.FOOT)
	var foot: Dictionary = water.bridges.bridges[fi]
	var k := (foot.spans as Array).size() / 2
	var span: Dictionary = foot.spans[k]
	var xf: Transform3D = foot.xform
	var deck := xf * Vector3(0, 0, (float(span.z0) + float(span.z1)) * 0.5)
	var space := level.get_world_3d().direct_space_state
	var before := space.intersect_ray(PhysicsRayQueryParameters3D.create(deck + Vector3.UP * 2.0, deck + Vector3.DOWN * 12.0, 1))
	var id := _blast_block(fi, k)
	await _frames(5)
	var after := space.intersect_ray(PhysicsRayQueryParameters3D.create(deck + Vector3.UP * 2.0, deck + Vector3.DOWN * 12.0, 1))
	var fallen := level.get_node_or_null(NodePath("Terrain/Water/Bridges/Fallen_%s_%d" % [foot.id, k]))
	check(id != "" and not before.is_empty() and absf((before.position as Vector3).y - deck.y) < 0.1 and water.bridges.is_down(fi, k)
		and (after.is_empty() or (after.position as Vector3).y < deck.y - 1.0) and fallen != null,
		"one demolition block drops the footbridge's span: the deck under it is gone (a ray down meets %s), the span lies fallen" % ["nothing" if after.is_empty() else "%.1f m lower" % (deck.y - (after.position as Vector3).y)])
	# A concrete span takes three.
	var ci := _bridge(ZoneBridges.CONCRETE)
	var concrete: Dictionary = water.bridges.bridges[ci]
	var hp_full := float(ZoneBridges.TYPES[ZoneBridges.CONCRETE].hp)
	var ck := _water_span(ci)
	_blast_block(ci, ck)
	await _frames(3)
	var hp_one := float((concrete.spans[ck] as Dictionary).hp)
	var up_one := not water.bridges.is_down(ci, ck)
	_blast_block(ci, ck)
	_blast_block(ci, ck)
	await _frames(5)
	check(up_one and hp_one < hp_full and water.bridges.is_down(ci, ck),
		"a concrete span stands up to one block (health %.1f of %.0f left) and drops to the third" % [hp_one, hp_full])


func _test_fire_support() -> void:
	var ti := _bridge(ZoneBridges.TRUSS)
	var truss: Dictionary = water.bridges.bridges[ti]
	var xf: Transform3D = truss.xform
	var tk := _water_span(ti)
	var span: Dictionary = truss.spans[tk]
	var at := xf * Vector3(0.8, 0.15, lerpf(float(span.z0), float(span.z1), 0.5))
	var rounds := 0
	var first_hp := -1.0
	while not water.bridges.is_down(ti, tk) and rounds < 12:
		Warheads.server_burst(level, &"arty_105_he", at, Vector3.DOWN, null, null)
		rounds += 1
		if rounds == 1:
			first_hp = float(span.hp)
		await _frames(2)
	check(water.bridges.is_down(ti, tk) and rounds >= 2 and rounds <= 8 and first_hp < float(ZoneBridges.TYPES[ZoneBridges.TRUSS].hp),
		"105 mm HE (fire support's) drops a steel truss span: %d rounds on it" % rounds)


func _test_nav_after_drop() -> void:
	var bi := _bridge(ZoneBridges.CONCRETE)
	var b: Dictionary = water.bridges.bridges[bi]
	var xf: Transform3D = b.xform
	await _frames(10)
	await _wait_for(func() -> bool: return level.nav.is_settled(), 30.0)
	var ends := _across(bi, 10.0)
	var path := NavigationServer3D.map_get_path(level.get_world_3d().navigation_map, ends[0], ends[1], true)
	var span: Dictionary = b.spans[_water_span(bi)]
	var over_gap := false
	for k in range(1, path.size()):
		for s in 10:
			var local := xf.affine_inverse() * path[k - 1].lerp(path[k], s / 10.0)
			if absf(local.x) < 3.0 and local.z > float(span.z0) + 0.5 and local.z < float(span.z1) - 0.5 and absf(local.y) < 0.8:
				over_gap = true
	check(water.bridges.is_down(bi, _water_span(bi)) and not over_gap, "with its span over the river down the navigation no longer runs over it (%d points)" % path.size())


func _test_save_and_join() -> void:
	check(GameState.save_zone(), "the zone saves")
	var saved: Dictionary = GameState.read_save(GameState.save_path())
	var hp: Dictionary = (saved.get("bridges", {}) as Dictionary).get("hp", {})
	var ci := _bridge(ZoneBridges.CONCRETE)
	var cid := String(water.bridges.bridges[ci].id)
	var low := 99.0
	for v: Variant in hp.get(cid, []):
		low = minf(low, float(v))
	check(low <= 0.0 and hp.size() == water.bridges.bridges.size(),
		"the save holds every bridge's spans' health, the dropped span at %.1f" % low)
	# A fresh build of the zone takes the save back (the host loading it) and a late joiner's list.
	var restored := _terrain(level.def)
	add_child(restored)
	restored.water.bridges.server_restore(saved.get("bridges", {}))
	var joiner := _terrain(level.def)
	joiner.water.bridges._client_state(water.bridges._downs())
	var same := true
	for bi in water.bridges.bridges.size():
		for k in (water.bridges.bridges[bi].spans as Array).size():
			var down := water.bridges.is_down(bi, k)
			same = same and restored.water.bridges.is_down(bi, k) == down and joiner.water.bridges.is_down(bi, k) == down
	check(same and water.bridges._downs().size() >= 3, "restored from the save, and on a late joiner, the same %d spans are down" % water.bridges._downs().size())
	restored.queue_free()
	joiner.free()


func _test_cost(def: Dictionary) -> void:
	# The carve on load.
	var t := _terrain(def)
	var carve := t.water.carve_ms()
	t.free()
	# A water query (every soldier's step asks one or two).
	var started := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 20000:
		level.terrain.water_height(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
	var query_us := (Time.get_ticks_usec() - started) / 20000.0
	# A man's step in water: what the water costs it (read the water, the current), wading and dry.
	var c := _river_ford()
	var pos: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var dry_at := _dry_spot(pos + Vector2(-dir.y, dir.x) * 120.0)
	var wader := _soldier(Vector3(pos.x, level.terrain.height_at(pos.x, pos.y) + 0.05, pos.y), "CostWader")
	var walker := _soldier(Vector3(dry_at.x, level.terrain.height_at(dry_at.x, dry_at.y) + 0.05, dry_at.y), "CostWalker")
	await _frames(20)
	var step_us := {}
	for s: Soldier in [wader, walker]:
		started = Time.get_ticks_usec()
		for k in 2000:
			s.movement._read_water()
			Wading.flow(s)
		step_us[s] = (Time.get_ticks_usec() - started) / 2000.0
	# A man's whole movement step (SoldierMovement.step, move_and_slide and all), wading and dry.
	var step_ms := {wader: INF, walker: INF}
	for s: Soldier in [wader, walker]:
		s.move_input = Vector2(0, -1)
	for batch in 4:  # the quickest of four batches, the two taking turns (other work on the machine)
		for s: Soldier in [wader, walker]:
			started = Time.get_ticks_usec()
			for k in 40:
				s.movement.step(1.0 / 60.0)
			step_ms[s] = minf(float(step_ms[s]), (Time.get_ticks_usec() - started) / 40.0 / 1000.0)
		await get_tree().physics_frame
	print("  (cost: the carve %.0f ms on load; a water query %.2f us; reading the water %.1f us a step wading, %.1f us dry; a whole step %.3f ms wading, %.3f ms dry)" % [carve, query_us, step_us[wader], step_us[walker], step_ms[wader], step_ms[walker]])
	check(carve < 1500.0 and query_us < 20.0 and float(step_us[wader]) < 60.0 and float(step_ms[wader]) < float(step_ms[walker]) * 1.5 + 0.1,
		"the cost: the carve %.0f ms on load (under 1500), %.2f us a water query (under 20); a wading man's step %.3f ms against %.3f ms on dry ground (%d men wading: %.2f ms a tick more)" % [carve, query_us, step_ms[wader], step_ms[walker], WADERS, (float(step_ms[wader]) - float(step_ms[walker])) * WADERS])
	wader.queue_free()
	walker.queue_free()
	await _frames(2)


# --- Helpers --------------------------------------------------------------------------------

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
	print("WATER TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
