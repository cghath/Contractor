class_name ConvoyRoad
extends RefCounted
## The way a live convoy takes through a zone (docs/survival_events.md section 1b): from the road
## in at the zone's edge it came through (ZoneRoads.exits(): the crossing toward the zone it came
## from) to the road out toward the zone it's going to, along the laid roads (RoadNet's curves, not
## the def's straight chords: RoadRoute): shortest by length over the roads, split at their
## junctions. A convoy on its first zone (no way in named) comes in at the exit farthest from the
## one it leaves by. Pure data; FallenConvoy.road_for falls back on the zone's main road when
## there's no way through.

## A junction counts as on a road when the road's nearest sample is this close (m).
const JOIN_M := 12.0
## Proposed: what going in and out of a site costs (m each): roads that meet only at a site have
## no road between them (a compound's walls), so a way round by junctions is taken when there's one.
const SITE_COST_M := 250.0


## The road through `roads` (a ZoneRoads) from the exit toward zone `from` to the exit toward zone
## `to`, points on the road's surface in driving order; empty when it can't be found.
static func between_exits(roads: ZoneRoads, from: String, to: String) -> PackedVector3Array:
	var exits := roads.exits()
	var out_exit := _exit_to(exits, to)
	var in_exit := _exit_to(exits, from)
	if in_exit.is_empty() and out_exit.is_empty():
		return PackedVector3Array()
	if in_exit.is_empty():
		in_exit = _farthest(exits, out_exit)
	elif out_exit.is_empty():
		out_exit = _farthest(exits, in_exit)
	if in_exit.is_empty() or out_exit.is_empty() or String(in_exit.crossing) == String(out_exit.crossing):
		return PackedVector3Array()
	return route(roads.segments(), roads.junctions(), in_exit.edge, int(in_exit.road), out_exit.edge, int(out_exit.road))


static func _exit_to(exits: Array, zone: String) -> Dictionary:
	if zone != "":
		for e: Dictionary in exits:
			if String(e.get("to", "")) == zone:
				return e
	return {}


## The exit farthest from `e` (not its own crossing), {} when there's no other.
static func _farthest(exits: Array, e: Dictionary) -> Dictionary:
	var best := {}
	var best_d := -1.0
	var at: Vector3 = e.edge
	for x: Dictionary in exits:
		if String(x.crossing) == String(e.crossing):
			continue
		var d := at.distance_to(x.edge)
		if d > best_d:
			best_d = d
			best = x
	return best


## The way along `segments` (ZoneRoads.segments()) from point `a` on road `road_a` to `b` on
## `road_b`, joined at `junctions` (ZoneRoads.junctions()) and at a site two roads both end at.
## Empty if they aren't connected.
static func route(segments: Array, junctions: Array, a: Vector3, road_a: int, b: Vector3, road_b: int) -> PackedVector3Array:
	var stations := {}  # road index -> [[sample, node key], ...]
	for ri in segments.size():
		var pts: PackedVector3Array = segments[ri].points
		if pts.size() < 2:
			continue
		var list: Array = [[0, _end_key(segments[ri].a, ri, "a")], [pts.size() - 1, _end_key(segments[ri].b, ri, "b")]]
		for j in junctions.size():
			if not ri in (junctions[j].roads as Array):
				continue
			var k := _nearest_sample(pts, junctions[j].pos)
			if _flat(pts[k]).distance_to(_flat(junctions[j].pos)) <= JOIN_M:
				list.append([k, "j%d" % j])
		if ri == road_a:
			list.append([_nearest_sample(pts, a), "A"])
		if ri == road_b:
			list.append([_nearest_sample(pts, b), "B"])
		list.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
		stations[ri] = list
	if not stations.has(road_a) or not stations.has(road_b):
		return PackedVector3Array()
	var edges := {}  # node key -> [[other key, length, road, from sample, to sample], ...]
	for ri: int in stations:
		var pts: PackedVector3Array = segments[ri].points
		var list: Array = stations[ri]
		for n in list.size() - 1:
			var i0 := int(list[n][0])
			var i1 := int(list[n + 1][0])
			if String(list[n][1]) == String(list[n + 1][1]):
				continue  # (two stations at one sample stay linked, at no length: A on a road's very end)
			var len_m := _arc(pts, i0, i1)
			_link(edges, String(list[n][1]), String(list[n + 1][1]), len_m, ri, i0, i1)
	var legs := _shortest(edges, "A", "B")
	if legs.is_empty():
		return PackedVector3Array()
	var out := PackedVector3Array()
	for leg: Array in legs:
		var pts: PackedVector3Array = segments[int(leg[2])].points
		var i0 := int(leg[3])
		var i1 := int(leg[4])
		var step := 1 if i1 >= i0 else -1
		var k := i0
		while true:
			if out.is_empty() or out[out.size() - 1].distance_to(pts[k]) > 0.5:
				out.append(pts[k])
			if k == i1:
				break
			k += step
	return out


static func _end_key(info: Dictionary, road: int, which: String) -> String:
	if int(info.get("junction", -1)) >= 0:
		return "j%d" % int(info.junction)
	if String(info.get("site", "")) != "":
		return "s%s" % String(info.site)
	return "e%d%s" % [road, which]


static func _nearest_sample(pts: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in pts.size():
		var d := _flat(pts[k]).distance_squared_to(_flat(p))
		if d < best_d:
			best_d = d
			best = k
	return best


static func _arc(pts: PackedVector3Array, i0: int, i1: int) -> float:
	var total := 0.0
	for k in range(mini(i0, i1), maxi(i0, i1)):
		total += pts[k].distance_to(pts[k + 1])
	return total


static func _link(edges: Dictionary, a: String, b: String, len_m: float, road: int, i0: int, i1: int) -> void:
	len_m += (SITE_COST_M if a.begins_with("s") else 0.0) + (SITE_COST_M if b.begins_with("s") else 0.0)
	if not edges.has(a):
		edges[a] = []
	if not edges.has(b):
		edges[b] = []
	(edges[a] as Array).append([b, len_m, road, i0, i1])
	(edges[b] as Array).append([a, len_m, road, i1, i0])


## Dijkstra over `edges`: the legs from `start` to `goal` ([other, length, road, from, to]), [] none.
static func _shortest(edges: Dictionary, start: String, goal: String) -> Array:
	if not edges.has(start) or not edges.has(goal):
		return []
	var dist := {start: 0.0}
	var via := {}
	var open: Array[String] = [start]
	var done := {}
	while not open.is_empty():
		var best := 0
		for k in open.size():
			if float(dist[open[k]]) < float(dist[open[best]]):
				best = k
		var u: String = open.pop_at(best)
		if u == goal:
			break
		done[u] = true
		for e: Array in edges[u]:
			var v := String(e[0])
			if done.has(v):
				continue
			var alt := float(dist[u]) + float(e[1])
			if not dist.has(v) or alt < float(dist[v]):
				dist[v] = alt
				via[v] = [u, e]
				if not v in open:
					open.append(v)
	if not via.has(goal):
		return []
	var legs: Array = []
	var at := goal
	while at != start:
		legs.push_front(via[at][1])
		at = String(via[at][0])
	return legs


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
