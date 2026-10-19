class_name RoadRoute
extends RefCounted
## Driving by road (docs/build_plan.md wave 6, the squad's drivers part 2): a zone's roads (the
## def's "roads": straight [[x, z], [x, z]] segments joining its sites, and the trails) as a graph,
## and the way along them from one point to another: onto the nearest road, along the roads
## (shortest by length, through the segments' shared ends), off near the goal. SquadDrivers drives
## it with VehicleAI.follow when it's worth it (route()); the rest of the time the drivers go
## straight or by the navmesh as before. Proposed numbers.

## Not for drives shorter than this (m): straight is fine.
const MIN_TRIP_M := 150.0
## A road this close (m) to the start and the goal is used; further, it isn't.
const JOIN_M := 120.0
## The road way can be at most this much longer than straight.
const DETOUR_MAX := 1.7
## Segment ends this close together are one junction.
const SNAP_M := 2.0
## Waypoints along a long straight road, at most this far apart (so VehicleAI keeps its line).
const STEP_M := 60.0


## The way from `from` to `to` (x, z) by `def`'s roads, as waypoints ending at `to`; empty when
## driving straight is as good (short, no road near either end, or too long a detour).
static func route(def: Dictionary, from: Vector2, to: Vector2) -> PackedVector2Array:
	var none := PackedVector2Array()
	var roads: Array = def.get("roads", [])
	if roads.is_empty() or from.distance_to(to) < MIN_TRIP_M:
		return none
	var g := _graph(roads)
	var on := _nearest_on(g, from)
	var off := _nearest_on(g, to)
	if on.is_empty() or off.is_empty() or float(on.d) > JOIN_M or float(off.d) > JOIN_M:
		return none
	# The two join points become nodes of their own, linked to their segment's two ends.
	var nodes: Array = (g.nodes as Array).duplicate()
	var edges: Dictionary = (g.edges as Dictionary).duplicate(true)
	var start := _insert(nodes, edges, on)
	var goal := _insert(nodes, edges, off)
	if on.seg == off.seg:
		_link(edges, start, goal, (on.p as Vector2).distance_to(off.p))
	var chain := _shortest(nodes, edges, start, goal)
	if chain.is_empty():
		return none
	var out := PackedVector2Array()
	var length := from.distance_to(on.p)
	var prev: Vector2 = on.p
	out.append(on.p)
	for i in range(1, chain.size()):
		var p: Vector2 = nodes[chain[i]]
		var leg := prev.distance_to(p)
		for k in range(1, ceili(leg / STEP_M)):
			out.append(prev.lerp(p, float(k) / ceili(leg / STEP_M)))
		out.append(p)
		length += leg
		prev = p
	length += prev.distance_to(to)
	if length > from.distance_to(to) * DETOUR_MAX:
		return none
	if out[out.size() - 1].distance_to(to) > 1.0:
		out.append(to)
	return out


## {"nodes": [Vector2], "edges": {i: {j: length}}, "segs": [[i, j]]} from the segments.
static func _graph(roads: Array) -> Dictionary:
	var nodes: Array = []
	var edges := {}
	var segs: Array = []
	for r: Array in roads:
		var a := _node(nodes, Vector2(float(r[0][0]), float(r[0][1])))
		var b := _node(nodes, Vector2(float(r[1][0]), float(r[1][1])))
		if a == b:
			continue
		_link(edges, a, b, (nodes[a] as Vector2).distance_to(nodes[b]))
		segs.append([a, b])
	return {"nodes": nodes, "edges": edges, "segs": segs}


static func _node(nodes: Array, p: Vector2) -> int:
	for i in nodes.size():
		if (nodes[i] as Vector2).distance_to(p) <= SNAP_M:
			return i
	nodes.append(p)
	return nodes.size() - 1


static func _link(edges: Dictionary, a: int, b: int, d: float) -> void:
	if not edges.has(a):
		edges[a] = {}
	if not edges.has(b):
		edges[b] = {}
	edges[a][b] = d
	edges[b][a] = d


## The point on any segment nearest `p`: {"p", "d", "seg" (index), "a", "b"} or {}.
static func _nearest_on(g: Dictionary, p: Vector2) -> Dictionary:
	var best := {}
	for k in (g.segs as Array).size():
		var s: Array = g.segs[k]
		var a: Vector2 = g.nodes[s[0]]
		var b: Vector2 = g.nodes[s[1]]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_to(p)
		if best.is_empty() or d < float(best.d):
			best = {"p": q, "d": d, "seg": k, "a": int(s[0]), "b": int(s[1])}
	return best


## Adds the join point `at` (_nearest_on) as a node linked to its segment's ends; its index.
static func _insert(nodes: Array, edges: Dictionary, at: Dictionary) -> int:
	nodes.append(at.p)
	var i := nodes.size() - 1
	_link(edges, i, int(at.a), (at.p as Vector2).distance_to(nodes[at.a]))
	_link(edges, i, int(at.b), (at.p as Vector2).distance_to(nodes[at.b]))
	return i


## Dijkstra: the node indices from `start` to `goal`, or [].
static func _shortest(nodes: Array, edges: Dictionary, start: int, goal: int) -> Array:
	var dist := {start: 0.0}
	var prev := {}
	var open: Array[int] = [start]
	var done := {}
	while not open.is_empty():
		var best := 0
		for k in open.size():
			if float(dist[open[k]]) < float(dist[open[best]]):
				best = k
		var u: int = open.pop_at(best)
		if u == goal:
			break
		done[u] = true
		for v: int in edges.get(u, {}):
			if done.has(v):
				continue
			var alt := float(dist[u]) + float(edges[u][v])
			if not dist.has(v) or alt < float(dist[v]):
				dist[v] = alt
				prev[v] = u
				if v not in open:
					open.append(v)
	if not dist.has(goal):
		return []
	var chain: Array = [goal]
	while chain[0] != start:
		chain.push_front(prev[chain[0]])
	return chain
