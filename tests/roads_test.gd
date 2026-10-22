extends Node
## Roads (cg_brief queue item 1.2: RoadNet plans them, ZoneRoads lays them). Headless, one process:
## - on a hot zone's terrain (no level): every site joined up through the def's roads, the roads
##   on the graded ground the whole way (no gaps, nothing poking through), curved, the same from
##   the same seed (and planning again from a planned def changes nothing), towns with kerbed
##   pavements, RoadRoute driving the curved roads;
## - two linked zones: the road out through a crossing on one side is the same kind and width as
##   the one in on the other, each at its crossing;
## - a hosted zone: the roads' collision where the surface is drawn (asphalt hard, dirt soft, for
##   footsteps), a town's pavement and its mini roundabout, ground_point on a road, and an AI
##   driver taking a truck along a road;
## - costs: planning, grading and laying (ms), collision faces, against the budgets below.
## Never touches a real save.

## Budgets (Proposed; headless, this machine): planning plus grading a 16 km² hot zone's roads,
## and laying them (meshes and collision) in a hosted zone (ms).
const BUDGET_PLAN_HOT_MS := 1500.0
const BUDGET_LAY_MS := 400.0
## The road's surface over the graded ground: at least this (m: a little under where a road passes
## close by another's junction and is held nearly level with it), at most
## this (RoadNet.SINK_M and the 4 m grid's chords on curves and crests).
const GAP_MIN_M := -0.15
const GAP_MAX_M := 0.45
## The most a road is cut or filled anywhere (m): RoadNet.CUT_MAX_M on its own, a little more where
## it's held level with a pad, a junction or a road beside it.
const CUT_WORST_M := 5.0
## Laying the scatter out round the curved roads takes at most this many times as long as round the
## straight links (Proposed).
const SCATTER_SLOWER := 1.5
## A truck driven along a road: how far (m), how long it gets (s), and how far off the middle line
## it may wander (m past the road's half-width).
const DRIVE_M := 220.0
const DRIVE_S := 70.0
const DRIVE_SLACK_M := 1.5

var failures := 0
var level: ZoneLevel


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_roads" + tag
	Campaign.campaign_id = "test_roads_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(440.0, true, false, true).timeout.connect(func() -> void:
		print("ROADS TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_hot_zone()
	_test_crossings()
	_test_every_zone()
	await _test_level()
	_finish()


func _finish() -> void:
	Campaign.reset_campaign()
	GameState.delete_save()
	print("ROADS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The terrain for `def` as ZoneLevel makes it (its flat pads: modules, extraction, insertion).
func _terrain(def: Dictionary) -> ZoneTerrain:
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


# --- A hot zone, planned on its terrain --------------------------------------------------------

func _test_hot_zone() -> void:
	print("A hot zone's roads")
	var def := ZoneDef.normalize(ZoneDef.generate_hot(5121))
	var links := (def.roads as Array).size()
	var t := _terrain(def)
	var natural := t.heights.duplicate()
	var started := Time.get_ticks_usec()
	var roads := ZoneRoads.new()
	roads.prepare(t, def)
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	var net := roads.net
	var kinds := {}
	for r: Dictionary in net.roads:
		kinds[String(r.kind)] = int(kinds.get(String(r.kind), 0)) + 1
	var kinds_j := {}
	for j: Dictionary in net.junctions:
		kinds_j[String(j.kind)] = int(kinds_j.get(String(j.kind), 0)) + 1
	print("  %d links -> %d roads %s, %d junctions %s, %d def pieces; planned %.0f ms, graded %.0f ms (%d heights)" % [links, net.roads.size(),
		kinds, net.junctions.size(), kinds_j, (def.roads as Array).size(), net.plan_ms, net.grade_ms, net.graded_vertices])
	check(ms < BUDGET_PLAN_HOT_MS, "planned and graded in %.0f ms (budget %.0f)" % [ms, BUDGET_PLAN_HOT_MS])
	check(kinds.has("asphalt") and kinds.has("dirt"), "asphalt roads and dirt tracks (%s)" % kinds)
	check(int(def.get("roads_version", 0)) == RoadNet.VERSION and def.has("road_links"), "the def keeps its links and says which planning made its roads")

	# Every site joined up through the def's pieces (as RoadRoute snaps them: 2 m).
	var graph := _graph(def.roads)
	var reach := _reachable(graph, Vector2(float(def.modules[0].pos[0]), float(def.modules[0].pos[1])))
	var missing: Array = []
	for m: Dictionary in def.modules:
		if not _has_node(reach, Vector2(float(m.pos[0]), float(m.pos[1]))):
			missing.append(String(m.id))
	check(missing.is_empty(), "every site is on the road network (%d sites%s)" % [(def.modules as Array).size(), "" if missing.is_empty() else ", not: %s" % [missing]])
	if not missing.is_empty():
		for j in net.junctions.size():
			var jn: Dictionary = net.junctions[j]
			var deg := 0
			var nodes: Array[Vector2] = graph.nodes
			for i in nodes.size():
				if nodes[i].distance_to(jn.pos) < 2.0:
					deg = (graph.adj.get(i, []) as Array).size()
			print("    junction %d %s at %s r %.1f roads %s: def degree %d, reached %s" % [j, jn.kind, jn.pos, float(jn.r), jn.roads, deg, _has_node(reach, jn.pos)])
	for id: String in missing:
		for r: Dictionary in net.roads:
			for side: String in ["a", "b"]:
				var e: Dictionary = r[side]
				if String(e.get("site", "")) == id or (e.has("join") and false):
					print("    %s: road %d (%s) end %s %s, other end %s, stub %s" % [id, int(r.id), r.kind, side, e.exit, r["b" if side == "a" else "a"], e.get("stub")])

	# On the ground the whole way: along the middle, between samples and out to the edges.
	var worst_gap := 0.0
	var worst_under := 0.0
	var worst_cut := 0.0
	var samples := 0
	var where := ""
	for r: Dictionary in net.roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		var raw: PackedFloat32Array = r.raw
		var hw := float(r.hw)
		for k in pts.size() - 1:
			if not (roads._drawn(r, k) and roads._drawn(r, k + 1)):
				continue
			samples += 1
			worst_cut = maxf(worst_cut, absf(ys[k] - raw[k]))
			var n := ZoneRoads._side(pts, k)
			for f: float in [0.0, 0.5]:
				var c := pts[k].lerp(pts[k + 1], f)
				var y := lerpf(ys[k], ys[k + 1], f)
				for o: float in [-hw * 0.95, 0.0, hw * 0.95]:
					var q := c + n * o
					var gap := y - t.height_at(q.x, q.y)
					if gap < worst_under:
						where = "road %d (%s) sample %d of %d at %s, %.0f m from a junction, %.0f m from another road" % [int(r.id), r.kind, k,
							pts.size(), q, _junction_near(net, q), _other_road(net, int(r.id), q)]
					worst_gap = maxf(worst_gap, gap)
					worst_under = minf(worst_under, gap)
	check(samples > 1000 and worst_under >= GAP_MIN_M and worst_gap <= GAP_MAX_M,
		"the roads lie on the graded ground: %d pieces, the surface %.2f to %.2f m over it (no gaps, nothing poking through)%s" % [samples, worst_under, worst_gap,
		"" if worst_under >= GAP_MIN_M and worst_gap <= GAP_MAX_M else "; worst: " + where])
	print("  timings: %s" % net.timings)
	if worst_under < GAP_MIN_M or worst_gap > GAP_MAX_M:
		_debug_gap(net, t, natural, where)
	check(worst_cut <= CUT_WORST_M, "never cut or filled more than %.1f m off the natural ground (worst %.2f m)" % [CUT_WORST_M, worst_cut])
	var changed := 0
	for i in natural.size():
		if not is_equal_approx(natural[i], t.heights[i]):
			changed += 1
	check(changed > 0 and changed < natural.size() / 4, "the terrain is cut and filled along the roads only (%d of %d heights)" % [changed, natural.size()])

	# Curves: the roads bend, smoothly.
	var bent := 0
	var sharpest := 0.0
	for r: Dictionary in net.roads:
		var pts: PackedVector2Array = r.pts
		if pts.size() < 10:
			continue
		var turned := 0.0
		for k in range(1, pts.size() - 1):
			var a := pts[k] - pts[k - 1]
			var b := pts[k + 1] - pts[k]
			if a.length() < 0.5 or b.length() < 0.5 or (r.skip as PackedByteArray)[k] == 1:
				continue
			var turn := absf(a.angle_to(b))
			turned += turn
			if _junction_near(net, pts[k]) > 30.0:
				sharpest = maxf(sharpest, rad_to_deg(turn) / ((a.length() + b.length()) * 0.5))
		if rad_to_deg(turned) > 20.0:
			bent += 1
	check(bent * 2 >= net.roads.size() and sharpest < 6.0,
		"the roads curve (%d of %d turn more than 20 degrees along their length), none sharper than %.1f degrees a metre" % [bent, net.roads.size(), sharpest])

	# Junctions: where roads cross and join, at one height.
	var level_ok := true
	for j in net.junctions.size():
		for ri: int in net.junctions[j].roads:
			var k := net.sample_of(ri, j)
			level_ok = level_ok and k >= 0 and absf((net.roads[ri].ys as PackedFloat32Array)[k] - float(net.junctions[j].y)) < 0.01
	var off_level := ""
	for j in net.junctions.size():
		for ri: int in net.junctions[j].roads:
			var k := net.sample_of(ri, j)
			if k < 0 or absf((net.roads[ri].ys as PackedFloat32Array)[k] - float(net.junctions[j].y)) >= 0.01:
				off_level += " junction %d (%s) road %d sample %d;" % [j, net.junctions[j].kind, ri, k]
	check(net.junctions.size() > 0 and level_ok, "%d junctions, every road through one level with it%s" % [net.junctions.size(), off_level])

	# Towns: kerbed pavements both sides of both streets, the street and the pavement where they should be.
	check(not net.towns.is_empty() and roads.pavements().size() == net.towns.size() * 8, "%d towns, %d kerbed pavements" % [net.towns.size(), roads.pavements().size()])
	if not net.towns.is_empty():
		var town: Dictionary = net.towns[0]
		var c: Vector2 = town.pos
		var y := float(town.y)
		var street := roads.surface_at(c.x + 20.0, c.y)
		var pave := roads.surface_at(c.x + 20.0, c.y + BuildingGen.STREET_W * 0.5 + 0.2)
		check(roads.kind_at(c.x + 20.0, c.y) == "street" and roads.kind_at(c.x + 20.0, c.y + BuildingGen.STREET_W * 0.5 + 0.2) == "pavement"
			and pave - street > 0.08, "a town's street and its raised pavement (%.2f m and %.2f m over the pad)" % [street - y, pave - y])

	# RoadRoute (the squad's drivers) drives the curved roads: a long trip keeps to them.
	var routed := 0
	var on_road := true
	for a: Dictionary in def.modules:
		for b: Dictionary in def.modules:
			var pa := Vector2(float(a.pos[0]), float(a.pos[1]))
			var pb := Vector2(float(b.pos[0]), float(b.pos[1]))
			if pa.distance_to(pb) < 900.0 or routed >= 6:
				continue
			var way := RoadRoute.route(def, pa + Vector2(30, 30), pb + Vector2(30, 30))
			if way.is_empty():
				continue
			routed += 1
			for k in range(1, way.size() - 1):
				var near := net.nearest(way[k].x, way[k].y, 12.0)
				var on_pad := t.pads.any(func(pad: Array) -> bool: return (pad[0] as Rect2).has_point(way[k]))
				on_road = on_road and (on_pad or (not near.is_empty() and float(near.d) <= float(net.roads[int(near.road)].hw) + 1.5)
					or _junction_near(net, way[k]) < 20.0)
	check(routed > 0 and on_road, "RoadRoute drives along the curved roads (%d long trips, every waypoint on a road)" % routed)

	# What the curved roads cost the scatter (ZoneScatter checks every road piece for every item it
	# tries): laying it out with the curved roads against the straight links, on the same ground.
	var stamp := Time.get_ticks_usec()
	var timed := func(pieces: Array) -> float:
		var sc := ZoneScatter.new()
		var probe := def.duplicate()
		probe["roads"] = pieces + [[[9000.0 + stamp % 1000, 9000.0], [9001.0, 9001.0]]]  # (a key of its own: no cached layout)
		var t0 := Time.get_ticks_usec()
		sc.generate(t, probe)
		var took := (Time.get_ticks_usec() - t0) / 1000.0
		sc.free()
		return took
	var with_curves: float = timed.call(def.roads)
	var with_links: float = timed.call(def.road_links)
	print("  scatter laid out in %.0f ms with the curved roads (%d pieces), %.0f ms with the straight links (%d)" % [with_curves,
		(def.roads as Array).size(), with_links, (def.road_links as Array).size()])
	check(with_curves < with_links * SCATTER_SLOWER + 300.0, "the scatter takes the curved roads in its stride (%.0f ms against %.0f)" % [with_curves, with_links])
	# The same seed, the same roads; planning again from a planned def (a late joiner) too.
	var def2 := ZoneDef.normalize(ZoneDef.generate_hot(5121))
	var t2 := _terrain(def2)
	var again := ZoneRoads.new()
	again.prepare(t2, def2)
	var t3 := _terrain(def)
	var replan := ZoneRoads.new()
	var def3 := def.duplicate(true)
	replan.prepare(t3, def3)
	check(str(def2.roads) == str(def.roads) and t2.checksum() == t.checksum() and str(def3.roads) == str(def.roads) and str(def3.patrols) == str(def.patrols),
		"the same seed gives the same roads and ground, and planning a planned def again changes nothing")
	for n: Node in [roads, again, replan, t, t2, t3]:
		n.free()


func _debug_gap(net: RoadNet, t: ZoneTerrain, natural: PackedFloat32Array, where: String) -> void:
	var at := where.substr(where.find("at (") + 4)
	at = at.substr(0, at.find(")"))
	var xy := at.split(",")
	var q := Vector2(float(xy[0]), float(xy[1]))
	var half := t.size_m * 0.5
	var i0 := floori((q.x + half) / ZoneTerrain.CELL_M)
	var j0 := floori((q.y + half) / ZoneTerrain.CELL_M)
	for dj in 2:
		for di in 2:
			var i := i0 + di
			var j := j0 + dj
			var p := Vector2(i * ZoneTerrain.CELL_M - half, j * ZoneTerrain.CELL_M - half)
			var line := "    vertex %s: natural %.2f graded %.2f;" % [p, natural[i + j * t.points], t.heights[i + j * t.points]]
			for r: Dictionary in net.roads:
				var pts: PackedVector2Array = r.pts
				var best := INF
				var bk := -1
				for k in pts.size():
					var d := pts[k].distance_to(p)
					if d < best:
						best = d
						bk = k
				if best < 40.0:
					line += " road %d d %.1f (hw %.1f) y %.2f wet %d;" % [int(r.id), best, float(r.hw), (r.ys as PackedFloat32Array)[bk], (r.wet as PackedByteArray)[bk]]
			print(line)
			var best := INF
			var by := 0.0
			var who := ""
			for r: Dictionary in net.roads:
				var pts: PackedVector2Array = r.pts
				var ys: PackedFloat32Array = r.ys
				var k := 0
				while k < pts.size() - 1:
					var k2 := mini(k + 2, pts.size() - 1)
					var ab := pts[k2] - pts[k]
					var u := clampf((p - pts[k]).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var d := p.distance_to(pts[k] + ab * u) - float(r.hw)
					if d < best:
						best = d
						by = lerpf(ys[k], ys[k2], u)
						who = "road %d piece %d-%d ys %.2f..%.2f" % [int(r.id), k, k2, ys[k], ys[k2]]
					k = k2
			for jn: Dictionary in net.junctions:
				var d := (jn.pos as Vector2).distance_to(p) - float(jn.r)
				if d < best:
					best = d
					by = float(jn.y)
					who = "junction %s y %.2f" % [jn.kind, float(jn.y)]
			print("      nearest grading: %s, d %.2f, y %.2f" % [who, best, by])
	var rid := int(where.substr(5, where.find(" (") - 5))
	var wk := int(where.substr(where.find("sample ") + 7, 6))
	var rr: Dictionary = net.roads[rid]
	var line2 := "    road %d samples %d..: ys/raw" % [rid, maxi(wk - 6, 0)]
	for k in range(maxi(wk - 6, 0), mini(wk + 7, (rr.pts as PackedVector2Array).size())):
		line2 += " %.2f/%.2f" % [(rr.ys as PackedFloat32Array)[k], (rr.raw as PackedFloat32Array)[k]]
	print(line2)
	for j in net.junctions.size():
		if rid in (net.junctions[j].roads as Array):
			print("    on junction %d %s at sample %d y %.2f roads %s" % [j, net.junctions[j].kind, net.sample_of(rid, j), float(net.junctions[j].y), net.junctions[j].roads])
	print("    ends: a %s, b %s" % [rr.a, rr.b])
	var pads := ""
	for pad: Array in t.pads:
		if (pad[0] as Rect2).grow(20.0).has_point(q):
			pads += " %s h %.2f" % [pad[0], float(pad[1])]
	print("    pads near: %s; water %.2f" % [pads, t.water_height(q.x, q.y)])


func _end_name(e: Dictionary) -> String:
	if String(e.get("site", "")) != "":
		return String(e.site)
	if e.has("join"):
		return "a junction"
	return "crossing " + String(e.edge) if e.has("edge") else "a trail end"


func _other_road(net: RoadNet, road: int, p: Vector2) -> float:
	var best := INF
	for r: Dictionary in net.roads:
		if int(r.id) == road:
			continue
		for q: Vector2 in r.pts:
			best = minf(best, q.distance_to(p))
	return best


func _junction_near(net: RoadNet, p: Vector2) -> float:
	var best := INF
	for j: Dictionary in net.junctions:
		best = minf(best, (j.pos as Vector2).distance_to(p) - float(j.r))
	return best


## The def's pieces as a graph: nodes (Vector2, 2 m snaps) and their neighbours.
func _graph(pieces: Array) -> Dictionary:
	var nodes: Array[Vector2] = []
	var adj := {}
	var node := func(p: Vector2) -> int:
		for i in nodes.size():
			if nodes[i].distance_to(p) <= 2.0:
				return i
		nodes.append(p)
		return nodes.size() - 1
	for r: Array in pieces:
		var a: int = node.call(Vector2(float(r[0][0]), float(r[0][1])))
		var b: int = node.call(Vector2(float(r[1][0]), float(r[1][1])))
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	return {"nodes": nodes, "adj": adj}


func _reachable(g: Dictionary, from: Vector2) -> Array[Vector2]:
	var nodes: Array[Vector2] = g.nodes
	var start := -1
	for i in nodes.size():
		if nodes[i].distance_to(from) <= 2.0:
			start = i
	var out: Array[Vector2] = []
	if start < 0:
		return out
	var seen := {start: true}
	var todo: Array[int] = [start]
	while not todo.is_empty():
		var at: int = todo.pop_back()
		out.append(nodes[at])
		for m: int in g.adj.get(at, []):
			if not seen.has(m):
				seen[m] = true
				todo.append(m)
	return out


func _has_node(list: Array[Vector2], p: Vector2) -> bool:
	return list.any(func(q: Vector2) -> bool: return q.distance_to(p) <= 2.0)


# --- Linked zones: the roads meet at the crossings ---------------------------------------------

func _test_crossings() -> void:
	print("Roads across a linked-zone crossing")
	# Two linked campaign zones, the smallest pair (each planned on its own terrain).
	var best: Array = []
	var best_size := INF
	for id: String in RegionMap.layout():
		if id == RegionMap.BASE:
			continue
		for l: Dictionary in RegionMap.links(id):
			var to := String(l.to)
			if to == RegionMap.BASE or to < id:
				continue
			var size := float(MissionRegistry.zone_def(id).get("size_m", 0.0)) + float(MissionRegistry.zone_def(to).get("size_m", 0.0))
			if size < best_size:
				best_size = size
				best = [id, to, int(l.side)]
	check(not best.is_empty(), "the region map links two campaign zones")
	if best.is_empty():
		return
	var made := {}
	for id: String in [best[0], best[1]]:
		var def := ZoneDef.normalize(MissionRegistry.zone_def(id))
		def["crossings"] = MissionRegistry.zone_def(id).get("crossings", [])
		var t := _terrain(def)
		var roads := ZoneRoads.new()
		roads.prepare(t, def)
		made[id] = {"def": def, "t": t, "roads": roads}
	var a: Dictionary = made[best[0]]
	var b: Dictionary = made[best[1]]
	var exit_a := _exit_to((a.roads as ZoneRoads).exits(), String(best[1]))
	var exit_b := _exit_to((b.roads as ZoneRoads).exits(), String(best[0]))
	check(not exit_a.is_empty() and not exit_b.is_empty(), "a road leaves %s toward %s and one leaves %s toward %s" % [best[0], best[1], best[1], best[0]])
	if not exit_a.is_empty() and not exit_b.is_empty():
		var side := int(best[2])
		var half_a := float(a.def.size_m) * 0.5
		var half_b := float(b.def.size_m) * 0.5
		var ca := RegionMap.crossing_of(a.def, RegionMap.crossing_id(String(best[1])))
		var cb := RegionMap.crossing_of(b.def, RegionMap.crossing_id(String(best[0])))
		var ea: Vector3 = exit_a.edge
		var eb: Vector3 = exit_b.edge
		var at_edge := func(e: Vector3, s: int, half: float) -> bool:
			return absf(absf([e.z, e.z, e.x, e.x][s]) - (half - RoadNet.EDGE_GAP_M)) < 0.5
		var along := func(e: Vector3, c: Dictionary, s: int) -> bool:
			return absf([e.x, e.x, e.z, e.z][s] - float(c.pos[[0, 0, 1, 1][s]])) < 0.5
		check(int(exit_a.side) == side and int(exit_b.side) == RegionMap.opposite(side) and at_edge.call(ea, side, half_a) and at_edge.call(eb, RegionMap.opposite(side), half_b)
			and along.call(ea, ca, side) and along.call(eb, cb, RegionMap.opposite(side)),
			"each leaves by the facing edge, straight out through its crossing (%s at %s, %s at %s)" % [best[0], ea, best[1], eb])
		check(String(exit_a.kind) == String(exit_b.kind) and is_equal_approx(float(exit_a.width), float(exit_b.width)),
			"the same road both sides: %s, %.1f m" % [exit_a.kind, float(exit_a.width)])
		# And the crossing road joins its zone's network.
		for side_info: Array in [[a, exit_a], [b, exit_b]]:
			var info: Dictionary = side_info[0]
			var graph := _graph(info.def.roads)
			var reach := _reachable(graph, Vector2((side_info[1].edge as Vector3).x, (side_info[1].edge as Vector3).z))
			var m0: Dictionary = info.def.modules[0]
			check(_has_node(reach, Vector2(float(m0.pos[0]), float(m0.pos[1]))), "%s: the road in from the crossing reaches its sites" % info.def.id)
	for info: Dictionary in made.values():
		(info.roads as Node).free()
		(info.t as Node).free()


func _exit_to(exits: Array, to: String) -> Dictionary:
	for e: Dictionary in exits:
		if String(e.to) == to:
			return e
	return {}


# --- Every campaign zone ------------------------------------------------------------------------

## Every zone the campaign has (and the hand-made ones): roads planned without a hitch, every site
## on them, a road out by every crossing, on the ground; towns kerbed; the costs.
func _test_every_zone() -> void:
	print("Every zone's roads")
	var ids: Array[String] = []
	for z: Dictionary in MissionRegistry.zones():
		ids.append(String(z.zone_id))
	var defs: Array = []
	for id in ids:
		defs.append(MissionRegistry.zone_def(id))
	for id: String in ["test", "forest_experimental", "coast"]:
		defs.append(ZoneDef.get_def(id))
	var unjoined: Array = []
	var no_exit: Array = []
	var bad_ground: Array = []
	var roundabouts := 0
	var kerbed := true
	var slowest := ""
	var slowest_ms := 0.0
	for raw: Dictionary in defs:
		var def := ZoneDef.normalize(raw)
		var t := _terrain(def)
		var natural := t.heights.duplicate()
		var started := Time.get_ticks_usec()
		var roads := ZoneRoads.new()
		roads.prepare(t, def)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		var net := roads.net
		var graph := _graph(def.roads)
		var sites: Array = (def.modules as Array).filter(func(m: Dictionary) -> bool: return not String(m.type).begins_with("fob_"))
		if not sites.is_empty():
			var reach := _reachable(graph, Vector2(float(sites[0].pos[0]), float(sites[0].pos[1])))
			for m: Dictionary in sites:
				if not _has_node(reach, Vector2(float(m.pos[0]), float(m.pos[1]))):
					unjoined.append("%s/%s" % [def.id, m.id])
		for c: Dictionary in def.get("crossings", []):
			if _exit_to(roads.exits(), String(c.to)).is_empty():
				no_exit.append("%s/%s" % [def.id, c.id])
		var under := 0.0
		var at := ""
		for r: Dictionary in net.roads:
			var pts: PackedVector2Array = r.pts
			var ys: PackedFloat32Array = r.ys
			for k in pts.size():
				if roads._drawn(r, k):
					var gap := ys[k] - t.height_at(pts[k].x, pts[k].y)
					if gap < under:
						under = gap
						at = "road %d (%s, %s to %s) sample %d of %d at %s, %.0f m from a junction, %.0f m from another road, raw %.2f" % [int(r.id), r.kind,
							_end_name(r.a), _end_name(r.b), k, pts.size(), pts[k], _junction_near(net, pts[k]), _other_road(net, int(r.id), pts[k]), (r.raw as PackedFloat32Array)[k]]
		if under < GAP_MIN_M:
			bad_ground.append("%s (%.2f)" % [def.id, under])
			print("    %s: %.2f at %s" % [def.id, under, at])
			_debug_gap(net, t, natural, at)
		for j: Dictionary in net.junctions:
			if String(j.kind) == "roundabout":
				roundabouts += 1
		kerbed = kerbed and roads.pavements().size() == net.towns.size() * 8
		if ms > slowest_ms:
			slowest_ms = ms
			slowest = "%s (%d m)" % [def.id, int(def.size_m)]
		print("  %s: %d m, %d roads, %d junctions, %d towns, %d crossings; %.0f ms (plan %.0f, grade %.0f)" % [def.id, int(def.size_m), net.roads.size(),
			net.junctions.size(), net.towns.size(), (def.get("crossings", []) as Array).size(), ms, net.plan_ms, net.grade_ms])
		roads.free()
		t.free()
	check(unjoined.is_empty(), "%d zones: every site on its zone's roads%s" % [defs.size(), "" if unjoined.is_empty() else " (not: %s)" % [unjoined]])
	check(no_exit.is_empty(), "a road out by every crossing%s" % ("" if no_exit.is_empty() else " (none at: %s)" % [no_exit]))
	check(bad_ground.is_empty(), "no terrain through a road anywhere%s" % ("" if bad_ground.is_empty() else " (%s)" % [bad_ground]))
	check(roundabouts > 0 and kerbed, "%d roundabouts across the campaign; every town kerbed" % roundabouts)
	print("  slowest: %s, %.0f ms" % [slowest, slowest_ms])


# --- A hosted zone: collision, a truck on a road --------------------------------------------------

func _test_level() -> void:
	print("A hosted zone: collision and a truck on the road")
	var def := ZoneDef.generate(7787, 1920.0, ["town", "outpost", "village", "checkpoint", "compound"], 5)
	def["id"] = "roads_test" + OS.get_environment("CONTRACTOR_TEST_TAG")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	var roads := level.roads
	var player := level.players.get_node(^"1") as Soldier
	check(roads != null and ZoneRoads.of(player) == roads, "the zone has its roads (ZoneRoads.of)")
	if roads == null:
		return
	print("  %d roads, laid in %.0f ms: %d collision faces in %d bodies" % [roads.net.roads.size(), roads.build_ms, roads.collision_faces, roads.bodies])
	check(roads.build_ms < BUDGET_LAY_MS, "laid in %.0f ms (budget %.0f)" % [roads.build_ms, BUDGET_LAY_MS])
	await get_tree().physics_frame
	var space := level.get_world_3d().direct_space_state
	# Collision under the drawn surface, from above only; asphalt hard underfoot, dirt soft.
	var hits := 0
	var tries := 0
	var worst := 0.0
	var hard_ok := true
	for r: Dictionary in roads.net.roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		for k in range(2, pts.size() - 2, 9):
			if not (roads._drawn(r, k - 1) and roads._drawn(r, k) and roads._drawn(r, k + 1)):
				continue
			tries += 1
			var q := PhysicsRayQueryParameters3D.create(Vector3(pts[k].x, ys[k] + 2.0, pts[k].y), Vector3(pts[k].x, ys[k] - 2.0, pts[k].y), 1)
			q.hit_back_faces = false
			var hit := space.intersect_ray(q)
			var body: Node = hit.collider as Node if not hit.is_empty() else null
			if body == null or not body.has_meta(&"hard_ground"):
				print("    no road under the ray at %s (road %d %s sample %d, surface %.2f): hit %s" % [pts[k], int(r.id), r.kind, k, ys[k], hit.get("collider")])
				continue
			hits += 1
			worst = maxf(worst, absf((hit.position as Vector3).y - ys[k]))
			hard_ok = hard_ok and bool(body.get_meta(&"hard_ground")) == bool(RoadNet.kind(String(r.kind)).get("hard", false))
	check(tries > 50 and hits == tries and worst < 0.05 and hard_ok,
		"the road's collision is its drawn surface: %d of %d rays down hit it (within %.3f m), hard or soft by its kind" % [hits, tries, worst])
	# A soldier on asphalt steps hard, on a dirt track soft (Sfx.hard_ground).
	var steps_ok := true
	var stepped := 0
	for want: String in ["asphalt", "dirt"]:
		for r: Dictionary in roads.net.roads:
			if String(r.kind) != want:
				continue
			var k := (r.pts as PackedVector2Array).size() / 2
			if not roads._drawn(r, k):
				continue
			player.global_position = Vector3(r.pts[k].x, float(r.ys[k]) + 0.02, r.pts[k].y)
			await get_tree().physics_frame
			var hard := Sfx.hard_ground(player)
			print("  on %s at %s (the road's surface %.2f): hard steps %s" % [want, player.global_position, float(r.ys[k]), hard])
			steps_ok = steps_ok and hard == (want == "asphalt")
			stepped += 1
			break
	check(stepped == 2 and steps_ok, "footsteps: hard on asphalt, soft on a dirt track")
	# ground_point on a road stands on it.
	var r0: Dictionary = roads.net.roads[0]
	var k0 := (r0.pts as PackedVector2Array).size() / 3
	var gp := level.ground_point(Vector3(r0.pts[k0].x, 0, r0.pts[k0].y))
	check(gp.y >= float(r0.ys[k0]) + 0.05, "ground_point on a road is on its surface (%.2f over it)" % (gp.y - float(r0.ys[k0])))
	# The town: its pavement and the mini roundabout at the crossroads are solid.
	if not roads.net.towns.is_empty():
		var town: Dictionary = roads.net.towns[0]
		var c: Vector2 = town.pos
		var y := float(town.y)
		var down := func(x: float, z: float) -> float:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, y + 3.0, z), Vector3(x, y - 1.0, z), 1)
			q.hit_back_faces = false
			var hit := space.intersect_ray(q)
			return (hit.position as Vector3).y - y if not hit.is_empty() and (hit.collider as Node).has_meta(&"hard_ground") else -1.0
		var pave: float = down.call(c.x + 20.0, c.y + BuildingGen.STREET_W * 0.5 + 0.3)
		var street: float = down.call(c.x + 20.0, c.y)
		var dome: float = down.call(c.x, c.y)
		check(pave > 0.1 and street >= 0.0 and street < 0.05 and dome > street + 0.05,
			"a town's kerbed pavement (%.2f m), its street (%.2f m) and the mini roundabout at its crossroads (%.2f m), all solid" % [pave, street, dome])
	# A truck with an AI driver along a road.
	await _drive(roads, player)


func _drive(roads: ZoneRoads, player: Soldier) -> void:
	# The longest open asphalt (else dirt) stretch: no junctions, pads or water on it.
	var best := []
	for r: Dictionary in roads.net.roads:
		var pts: PackedVector2Array = r.pts
		var s: PackedFloat32Array = r.s
		var from := -1
		for k in pts.size():
			var ok := roads._drawn(r, k) and _junction_near(roads.net, pts[k]) > 10.0
			if ok and from < 0:
				from = k
			if (not ok or k == pts.size() - 1) and from >= 0:
				var length := s[k] - s[from]
				var score := length + (1000.0 if String(r.kind) == "asphalt" else 0.0)
				if best.is_empty() or score > float(best[3]):
					best = [r, from, k if ok else k - 1, score]
				from = -1
	check(not best.is_empty(), "a stretch of road to drive")
	if best.is_empty():
		return
	var r: Dictionary = best[0]
	var pts: PackedVector2Array = r.pts
	var ys: PackedFloat32Array = r.ys
	var s: PackedFloat32Array = r.s
	var k0 := int(best[1]) + 2
	var k1 := int(best[2]) - 2
	while k1 > k0 and s[k1] - s[k0] > DRIVE_M + 40.0:
		k1 -= 1
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer
	var dir := (pts[k0 + 1] - pts[k0]).normalized()
	var start := Vector3(pts[k0].x, ys[k0] + 0.6, pts[k0].y)
	var yaw := atan2(-dir.x, -dir.y)
	var v := layer.server_spawn("matv", Transform3D(Basis(Vector3.UP, yaw), start), "", &"player", "roads_test_matv") if layer else null
	check(v != null, "a MATV on the road (%s, %.0f m of it)" % [r.kind, s[k1] - s[k0]])
	if v == null:
		return
	var driver := level.spawn_soldier({"name": "RoadDriver", "faction": "friendly", "variant": "multicam", "pos": start + Vector3(3, 0, 0),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "guard": false})
	for i in 10:
		await get_tree().physics_frame
	v.server_enter(driver, 0)
	player.global_position = start + Vector3(0, 40.0, 0)  # (out of the way: streaming follows it)
	var way := PackedVector3Array()
	var k := k0
	while k < k1:
		k = mini(k + 6, k1)
		way.append(Vector3(pts[k].x, ys[k], pts[k].y))
	v.server_follow_path(way, 30.0)
	var worst_off := 0.0
	var lowest := INF
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < DRIVE_S * 1000.0:
		await get_tree().physics_frame
		var p := v.global_position
		var near := roads.net.nearest(p.x, p.z, 30.0)
		if not near.is_empty():
			worst_off = maxf(worst_off, float(near.d))
			lowest = minf(lowest, p.y - float(near.y))
		if v.ai and v.ai.status == "arrived":
			break
	var end := way[way.size() - 1]
	var left := Vector2(v.global_position.x, v.global_position.z).distance_to(Vector2(end.x, end.z))
	print("  drove %.0f m in %.1f s, at most %.1f m off the middle line, the hull's origin at least %.2f m over the surface" % [s[k1] - s[k0],
		(Time.get_ticks_msec() - t0) / 1000.0, worst_off, lowest])
	check(left < VehicleAI.ARRIVE_M + 4.0 and worst_off <= float(r.hw) + DRIVE_SLACK_M and lowest > -0.3,
		"an AI driver takes the MATV along the road to its end (%.1f m short), on the road the whole way (%.1f m off the middle at most), never through it" % [left, worst_off])
