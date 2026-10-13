class_name Buildings
extends RefCounted
## Buildings the AI can garrison and clear (Captain, P0164 queue 17 core). They are found by
## probing what stands in the world now, not read from a list, so the compound's main building,
## a module's houses and a wall blown open all count as they are:
## - Inside: a walkable spot (on the navmesh) with walls round it. Of PROBE_DIRS level rays at
##   PROBE_HEIGHT (below a window's sill, so only doorways and breaches let them out), at most
##   MAX_OPEN reach PROBE_M without meeting a wall, and never two opposite ones (a gap between
##   two buildings is no room). Ground rising under a ray isn't a wall (hilly zones). Inside
##   spots next to each other make one building.
## - Entrances: where a navmesh path from inside out to the open leaves the building (a
##   doorway, or a breach the navmesh has been rebaked through).
## - Firing ports: inside spots against a wall with a window in it (a wall at PROBE_HEIGHT, a
##   clear view out at PORT_EYE), and the doorways.
## - Rooms: the inside spots that see each other, taken in turn from the first entrance inward,
##   each with the two corners the first two in take.
## A building is a Dictionary: "spots" (Array of Vector3 on the navmesh), "centre",
## "entrances" ([{"door", "inside", "outside", "normal"}], "normal" pointing out), "ports"
## ([{"point", "dir", "kind": "window" or "door"}]) and "rooms" ([{"spots", "centre",
## "corners"}]). Scans are cached for CACHE_S (walls change). Proposed numbers.

const GRID_M := 1.0
const SCAN_M := 14.0
const PROBE_HEIGHT := 0.6
const PROBE_M := 12.0
const PROBE_DIRS := 8
const MAX_OPEN := 2
## A hit counts as a wall when its surface is this close to upright (normal.y below it).
const WALL_NORMAL_Y := 0.5
## Fewer inside spots than this is a nook, not a building.
const MIN_SPOTS := 4
## A grid point counts as walkable when the navmesh is this close to it.
const NAV_SNAP_M := 0.45
## A window port: a wall within PORT_WALL_M at PROBE_HEIGHT, open for PORT_VIEW_M at PORT_EYE.
const PORT_WALL_M := 1.2
const PORT_EYE := 1.45
const PORT_VIEW_M := 4.0
## Ports closer than this to one already found are the same port.
const PORT_GAP_M := 1.4
## Path crossings closer than this are the same entrance.
const ENTRANCE_GAP_M := 2.0
## Where to stand outside an entrance, and how far out the paths probing for entrances reach.
const OUTSIDE_M := 1.5
const EXIT_PROBE_M := 8.0
const ROOM_EYE := 1.2
const CACHE_S := 20.0
const CACHE_MAX := 48

static var _cache := {}


## The buildings with an inside spot within `radius` of `centre` (see the class notes).
static func near(from: Node3D, centre: Vector3, radius := SCAN_M) -> Array:
	if from == null or not from.is_inside_tree():
		return []
	var key := "%d,%d,%d,%d" % [roundi(centre.x / 2.0), roundi(centre.y / 2.0), roundi(centre.z / 2.0), roundi(radius)]
	var now := Soldier._now()
	var hit: Dictionary = _cache.get(key, {})
	if not hit.is_empty() and now - float(hit.at) < CACHE_S:
		return hit.list
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	var list := _scan(from.get_world_3d(), centre, radius)
	_cache[key] = {"at": now, "list": list}
	return list


## The building `point` is inside ({} for none).
static func at(from: Node3D, point: Vector3) -> Dictionary:
	for b: Dictionary in near(from, point, SCAN_M):
		if contains(b, point):
			return b
	return {}


## The building whose nearest inside spot is closest to `point`, within `max_m` ({} for none).
static func nearest(from: Node3D, point: Vector3, max_m: float) -> Dictionary:
	var best := {}
	var best_d := max_m
	for b: Dictionary in near(from, point, maxf(max_m + 4.0, SCAN_M)):
		var d := distance_to(b, point)
		if d <= best_d:
			best = b
			best_d = d
	return best


## Whether `point` stands inside building `b` (within a grid step of one of its spots).
static func contains(b: Dictionary, point: Vector3) -> bool:
	return not b.is_empty() and distance_to(b, point) <= GRID_M * 0.8


## Flat distance from `point` to building `b`'s nearest inside spot.
static func distance_to(b: Dictionary, point: Vector3) -> float:
	var best := INF
	for s: Vector3 in b.get("spots", []):
		if absf(s.y - point.y) < 2.0:
			best = minf(best, Vector2(s.x - point.x, s.z - point.z).length())
	return best


## The entrance of `b` nearest `point` ({} if it has none).
static func entrance_near(b: Dictionary, point: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for e: Dictionary in b.get("entrances", []):
		var d := (e.outside as Vector3).distance_to(point)
		if d < best_d:
			best = e
			best_d = d
	return best


static func _scan(world: World3D, centre: Vector3, radius: float) -> Array:
	var map := world.navigation_map
	var spots := {}  # Vector2i grid cell -> Vector3 on the navmesh
	var n := ceili(radius / GRID_M)
	var base := Vector2i(roundi(centre.x / GRID_M), roundi(centre.z / GRID_M))
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			if Vector2(ix, iz).length() * GRID_M > radius:
				continue
			var cell := base + Vector2i(ix, iz)
			var p := Vector3((cell.x + 0.5) * GRID_M, centre.y, (cell.y + 0.5) * GRID_M)
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > NAV_SNAP_M or absf(q.y - p.y) > 2.5:
				continue
			if inside(world, q):
				spots[cell] = q
	# Spots next to each other (8 ways) make one building.
	var out: Array = []
	var seen := {}
	for cell: Vector2i in spots:
		if seen.has(cell):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [cell]
		seen[cell] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			group.append(c)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var nb := c + Vector2i(dx, dz)
					if spots.has(nb) and not seen.has(nb):
						seen[nb] = true
						queue.append(nb)
		if group.size() >= MIN_SPOTS:
			out.append(_building(world, spots, group))
	return out


## Whether walkable spot `q` has walls round it (see the class notes).
static func inside(world: World3D, q: Vector3) -> bool:
	var eye := q + Vector3.UP * PROBE_HEIGHT
	var open: Array[int] = []
	for k in PROBE_DIRS:
		if not _wall_within(world, eye, _dir(k), PROBE_M):
			open.append(k)
			if open.size() > MAX_OPEN:
				return false
	for i in open:
		if (i + (PROBE_DIRS >> 1)) % PROBE_DIRS in open:
			return false  # open both ways: a gap between buildings
	return true


## A wall (an upright surface, not the ground rising) within `reach` from `from` along `dir`.
static func _wall_within(world: World3D, from: Vector3, dir: Vector3, reach: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Throwables.WORLD_MASK)
	var hit := world.direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf((hit.normal as Vector3).y) < WALL_NORMAL_Y


static func _dir(k: int) -> Vector3:
	var a := TAU * k / PROBE_DIRS
	return Vector3(cos(a), 0.0, sin(a))


static func _building(world: World3D, spots: Dictionary, group: Array[Vector2i]) -> Dictionary:
	var list: Array[Vector3] = []
	var centre := Vector3.ZERO
	for c in group:
		list.append(spots[c])
		centre += spots[c]
	centre /= list.size()
	var b := {"spots": list, "centre": centre, "entrances": [], "ports": [], "rooms": []}
	b.entrances = _entrances(world, b, spots, group)
	b.ports = _ports(world, b, spots, group)
	b.rooms = _rooms(world, b)
	return b


## Where navmesh paths from the middle out to the open (PROBE_DIRS ways) leave the building.
static func _entrances(world: World3D, b: Dictionary, spots: Dictionary, group: Array[Vector2i]) -> Array:
	var map := world.navigation_map
	var cells := {}
	for c in group:
		cells[c] = true
	var start: Vector3 = b.spots[0]
	var best := INF
	for s: Vector3 in b.spots:
		if s.distance_to(b.centre) < best:
			best = s.distance_to(b.centre)
			start = s
	var reach := 0.0
	for s: Vector3 in b.spots:
		reach = maxf(reach, Vector2(s.x - start.x, s.z - start.z).length())
	var out: Array = []
	for k in PROBE_DIRS:
		var goal := NavigationServer3D.map_get_closest_point(map, start + _dir(k) * (reach + EXIT_PROBE_M))
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		var last_in := start
		for i in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var z: Vector3 = path[i]
			var steps := maxi(ceili(Vector2(z.x - a.x, z.z - a.z).length() / (GRID_M * 0.5)), 1)
			var crossed := false
			for j in range(1, steps + 1):
				var p := a.lerp(z, float(j) / steps)
				if cells.has(Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))):
					last_in = p
					continue
				var normal := Vector3(p.x - last_in.x, 0.0, p.z - last_in.z)
				normal = normal.normalized() if normal.length() > 0.05 else _dir(k)
				var outside := NavigationServer3D.map_get_closest_point(map, p + normal * OUTSIDE_M)
				if not out.any(func(e: Dictionary) -> bool: return (e.door as Vector3).distance_to(p) < ENTRANCE_GAP_M):
					out.append({"door": p, "inside": last_in, "outside": outside, "normal": normal})
				crossed = true
				break
			if crossed:
				break
	return out


## Window ports (a wall at PROBE_HEIGHT with a clear view out at PORT_EYE) along the edge
## spots, and a door port just inside each entrance.
static func _ports(world: World3D, b: Dictionary, spots: Dictionary, group: Array[Vector2i]) -> Array:
	var out: Array = []
	for e: Dictionary in b.entrances:
		out.append({"point": e.inside, "dir": e.normal, "kind": "door"})
	for c in group:
		var edge := false
		for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not spots.has(c + nb):
				edge = true
		if not edge:
			continue
		var q: Vector3 = spots[c]
		for k in PROBE_DIRS:
			var d := _dir(k)
			if not _wall_within(world, q + Vector3.UP * PROBE_HEIGHT, d, PORT_WALL_M):
				continue
			var eye := q + Vector3.UP * PORT_EYE
			if not Throwables.clear_line(world, eye, eye + d * PORT_VIEW_M):
				continue
			if out.any(func(p: Dictionary) -> bool: return (p.point as Vector3).distance_to(q) < PORT_GAP_M):
				continue
			out.append({"point": q, "dir": d, "kind": "window"})
	return out


## The rooms, from the first entrance inward: the spots seen from the nearest spot not yet in a
## room, each with its two far corners (left and right as one comes in).
static func _rooms(world: World3D, b: Dictionary) -> Array:
	var left: Array[Vector3] = []
	left.assign(b.spots)
	var from: Vector3 = (b.entrances[0].inside as Vector3) if not b.entrances.is_empty() else (b.centre as Vector3)
	var out: Array = []
	while not left.is_empty():
		var seed := left[0]
		for s in left:
			if s.distance_to(from) < seed.distance_to(from):
				seed = s
		var room: Array[Vector3] = []
		var rest: Array[Vector3] = []
		for s in left:
			if s == seed or Throwables.clear_line(world, seed + Vector3.UP * ROOM_EYE, s + Vector3.UP * ROOM_EYE):
				room.append(s)
			else:
				rest.append(s)
		left = rest
		var centre := Vector3.ZERO
		for s in room:
			centre += s
		centre /= room.size()
		var ahead := Vector3(centre.x - from.x, 0.0, centre.z - from.z)
		ahead = ahead.normalized() if ahead.length() > 0.1 else Vector3.FORWARD
		var side := ahead.cross(Vector3.UP)
		var corners: Array[Vector3] = []
		for sign_v: float in [1.0, -1.0]:
			var best := room[0]
			var best_v := -INF
			for s in room:
				var v := (s - seed).dot(side) * sign_v + (s - seed).dot(ahead) * 0.5
				if v > best_v:
					best_v = v
					best = s
			if corners.is_empty() or corners[0].distance_to(best) > 1.0:
				corners.append(best)
		out.append({"spots": room, "centre": centre, "corners": corners})
		from = seed
	return out
