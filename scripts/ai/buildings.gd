class_name Buildings
extends RefCounted
## Buildings the AI can garrison and clear (Captain, P0164 queue 17 core). They are found by
## probing what stands in the world now, not read from a list, so the compound's main building,
## a module's houses and a wall blown open all count as they are:
## - Inside: a walkable spot (navmesh over it; the spot is on the floor itself, the navmesh
##   floats a little over it) with walls round it. Of PROBE_DIRS level rays at PROBE_HEIGHT
##   (below a window's sill, so only doorways and breaches let them out), at most
##   MAX_OPEN reach PROBE_M without meeting a wall, and never two opposite ones (a gap between
##   two buildings is no room). Ground rising under a ray isn't a wall (hilly zones). Inside
##   spots next to each other make one building.
## - Floors (audit follow-up F-01): every walkable surface over each grid cell counts, from
##   SCAN_DOWN_M below the query to SCAN_UP_M above it (found by casting down through the
##   building: ground floor, upper floor, roof), so a scan from any floor finds them all.
##   Neighbouring spots join when they're level (STEP_M) or, up to STAIR_STEP_M apart, when a
##   short navmesh path links them (a stair's steps; never a bed's top). Floors stacked over
##   each other (LINK_OVERLAP cells in common) are one building when a navmesh path within
##   their footprint runs from one to the other (a stair the 1 m grid misses). Heights where
##   FLOOR_MIN_SPOTS or more spots stand level are the building's floors; the spots between
##   them are stairs. A floor above the first with open sky over it is a roof (a flat roof with
##   a parapet: its edge spots are firing ports all round).
## - Entrances: where a navmesh path from inside the first floor out to the open leaves the
##   building (a doorway, or a breach the navmesh has been rebaked through).
## - Firing ports: spots on a floor's edge against a wall with an opening in it, looking out
##   square to the wall (a wall at PROBE_HEIGHT, a clear view out at PORT_EYE): "window" with
##   wall above it, "parapet" without
##   (a roof's parapet; a railing that only looks across the building's own floor isn't one);
##   and the doorways ("door").
## - Rooms: per floor, the inside spots that see each other, taken in turn from the way in (the
##   first entrance, or the stair up), each with the two corners the first two in take.
## - Stairs: where two floors join (stair spots, or the path that linked them), the spot at its
##   foot and the one at its top: the way up is an inside entrance to the floor above (and a
##   chokepoint).
## A building is a Dictionary: "spots" (Array of Vector3 on the floors, every floor), "centre",
## "entrances" ([{"door", "inside", "outside", "normal"}], "normal" pointing out), "ports"
## ([{"point", "dir", "kind": "window", "parapet" or "door", "floor"}]), "rooms" ([{"spots",
## "centre", "corners", "floor"}], floor by floor), "floors" ([{"y", "spots", "rooms" (indices
## into "rooms"), "roof"}], lowest first) and "stairs" ([{"from", "to" (floor indices), "foot",
## "top", "spots"}]). Scans are cached for CACHE_S (walls change; see AREA_SNAP_M). Proposed numbers.

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
## A window port: a wall within PORT_WALL_M at PROBE_HEIGHT, open for PORT_VIEW_M at PORT_EYE;
## a window has wall above it at PORT_HEAD (a parapet or a railing doesn't).
const PORT_WALL_M := 1.2
const PORT_EYE := 1.45
const PORT_VIEW_M := 4.0
const PORT_HEAD := 2.0
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
## Floors (F-01): surfaces are looked for from SCAN_UP_M above the query down to SCAN_DOWN_M
## below it (a scan from the roof of a two-storey building reaches its ground floor), at most
## MAX_SURFACES of them over a cell; a surface is one whose normal.y is FLOOR_NORMAL_Y or more,
## and a navmesh point from SURFACE_SNAP_BELOW_M under it to SURFACE_SNAP_M over it, with that
## surface the first one under it, is walkable there (the baked navmesh sits up to two 0.25 m
## cells over the floor it was baked on). Each ray after the first starts SURFACE_SKIP_M under
## the surface found (below a slab).
const SCAN_UP_M := 9.0
const SCAN_DOWN_M := 8.0
const MAX_SURFACES := 8
const FLOOR_NORMAL_Y := 0.7
const SURFACE_SNAP_M := 0.65
const SURFACE_SNAP_BELOW_M := 0.2
const SURFACE_SKIP_M := 0.3
## Neighbouring spots up to STEP_M apart in height are level; up to STAIR_STEP_M apart they
## join only when a navmesh path no longer than LINK_PATH_M runs from one to the other.
const STEP_M := 0.35
const STAIR_STEP_M := 1.25
const LINK_PATH_M := 3.0
## Floors that share LINK_OVERLAP or more cells of their footprints are linked when a navmesh
## path no longer than LINK_PATH_MAX_M runs from one to the other within that footprint.
const LINK_OVERLAP := 4
const LINK_PATH_MAX_M := 40.0
## A floor: FLOOR_MIN_SPOTS or more spots level with each other; spots within FLOOR_BAND_M of
## its height are on it. A floor above the first is a roof when nothing stands ROOF_SKY_M over
## most of it.
const FLOOR_MIN_SPOTS := 4
const FLOOR_BAND_M := 0.4
const ROOF_SKY_M := 4.0
## Spots with no way in that stand RAISED_M or more above the ground under them are up on
## something (a watchtower's platform, a container's top), not in a building.
const RAISED_M := 1.5

## Captain, 2026-10-14 (P1104, a fight in ridge_hot's town: 21 fps, "engine physics" 451.7 ms):
## the squads' tactics and context ask for the buildings round their centre and the enemy's
## every second, and both move, so nearly every ask missed the cache (keyed to 2 m) and scanned
## afresh: 150-960 ms a squad think in a town (R1130-R1136: three quarters of it the per-cell
## probes, half of those navmesh closest-point queries). Now a scan covers an AREA_SNAP_M grid
## square's worth of centres (scanned that much wider from the square's middle, and each ask's
## buildings picked out of it), and each 1 m cell's probes are kept too, so a scan of the next
## square over reuses what it overlaps (a cell is probed for scans from three CELL_BAND_M height
## bands at once, its own and one each side, so scans from heights near each other share it); so is each building made of the same
## spots (its floors, stairs, entrances, ports and rooms) and each stair-step link. Everything
## still goes after
## CACHE_S: an answer is never older than that (its "at" is the oldest probe it was built
## from), and a building is made afresh once any of its cells was probed again.
## Proposed: the area grid (m), and how many areas, cells, buildings and links are kept.
const AREA_SNAP_M := 4.0
const CELL_BAND_M := 6.0
const AREA_MAX := 64
const CELL_MAX := 60000
const BUILT_MAX := 512
const LINK_MAX := 20000

static var _cache := {}
static var _areas := {}  # snapped centre and reach -> {"at", "list"}: a wider scan's buildings
static var _cells := {}  # Vector3i (cell x, z, height band) -> [at, surfaces, spots] (_probe_cell)
static var _built := {}  # the scan's height and a group's spots -> [built at, oldest probe, building]
static var _links := {}  # [a, b] -> [at, linked]: _linked's answers
## Tests: how long scans have taken so far (usec, every world).
static var spent_usec := 0
## The world and level the cached scans belong to (_scope); another one empties the cache.
static var _cache_scope := ""


## The buildings with an inside spot within `radius` of `centre` (see the class notes).
## Cached per world and level: another level at the same coordinates (the next zone, a
## second world) never gets this one's buildings.
static func near(from: Node3D, centre: Vector3, radius := SCAN_M) -> Array:
	if from == null or not from.is_inside_tree():
		return []
	var scope := _scope(from)
	if scope != _cache_scope:
		_cache.clear()  # a new level (or world): the old one's scans mean nothing here
		_areas.clear()
		_cells.clear()
		_built.clear()
		_links.clear()
		_cache_scope = scope
	var key := "%s|%d,%d,%d,%d" % [scope, roundi(centre.x / 2.0), roundi(centre.y / 2.0), roundi(centre.z / 2.0), roundi(radius)]
	var now := Soldier._now()
	var hit: Dictionary = _cache.get(key, {})
	if not hit.is_empty() and now - float(hit.at) < CACHE_S:
		return hit.list
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	var t := Time.get_ticks_usec()
	# The area scan: from the middle of centre's AREA_SNAP_M square (and its 2 m height step),
	# wide enough to hold this ask's whole circle from anywhere in the square.
	var mid := Vector3(snappedf(centre.x, AREA_SNAP_M), roundi(centre.y / 2.0) * 2.0, snappedf(centre.z, AREA_SNAP_M))
	var reach := radius + AREA_SNAP_M * 0.75
	var area_key := "%d,%d,%d,%d" % [roundi(mid.x), roundi(mid.y), roundi(mid.z), roundi(reach * 4.0)]
	var area: Dictionary = _areas.get(area_key, {})
	if area.is_empty() or now - float(area.at) >= CACHE_S:
		if _areas.size() >= AREA_MAX:
			_areas.clear()
		area = _scan(from.get_world_3d(), mid, reach, now)
		_areas[area_key] = area
	# This ask's buildings: those with an inside spot within its circle and height range.
	var list := (area.list as Array).filter(func(b: Dictionary) -> bool:
		return (b.spots as Array).any(func(sp: Vector3) -> bool:
			return Vector2(sp.x - centre.x, sp.z - centre.z).length() <= radius + GRID_M * 0.5 \
				and sp.y <= centre.y + SCAN_UP_M and sp.y >= centre.y - SCAN_DOWN_M))
	FrameCost.spent(&"buildings", t)  # (inside "ai" too when an AI's tick asked)
	spent_usec += Time.get_ticks_usec() - t
	_cache[key] = {"at": area.at, "list": list}
	return list


## Which world and level `from` is in: its World3D and the level node above it (none for a
## node outside any level), as a cache key.
## Drops every cached scan, probe, building and link: for when the walls or the navmesh change
## under them at once (a test building a house and baking its navmesh mid-run). The cell probes
## (perf/town-physics) are shared by every ask nearby for CACHE_S, so one probe made before a
## bake would otherwise keep the old answer for every scan round it.
static func forget() -> void:
	_cache.clear()
	_areas.clear()
	_cells.clear()
	_built.clear()
	_links.clear()


static func _scope(from: Node3D) -> String:
	var level: Node = from
	while level and not level.is_in_group(&"level"):
		level = level.get_parent()
	return "%d/%d" % [from.get_world_3d().get_instance_id(), level.get_instance_id() if level else 0]


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


## Flat distance from `point` to building `b`'s nearest inside spot on the floor `point` is on
## (spots within 2 m of its height).
static func distance_to(b: Dictionary, point: Vector3) -> float:
	var best := INF
	for s: Vector3 in b.get("spots", []):
		if absf(s.y - point.y) < 2.0:
			best = minf(best, Vector2(s.x - point.x, s.z - point.z).length())
	return best


## Which of `b`'s floors `point` is on (the one whose height is nearest it, within 2 m), -1
## for none.
static func floor_at(b: Dictionary, point: Vector3) -> int:
	var best := -1
	var best_d := 2.0
	var floors: Array = b.get("floors", [])
	for i in floors.size():
		var d := absf(float(floors[i].y) - point.y)
		if d < best_d:
			best = i
			best_d = d
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


## The buildings found from `centre` out to `radius` ({"list", "at": when the oldest cell probe
## it used was made}), with each cell's surfaces and spots from SCAN_UP_M over `centre` down to
## SCAN_DOWN_M under it. Each cell's probes are kept for CACHE_S under the cell and the height
## band `centre` is in (_cells), for the scans that overlap it.
static func _scan(world: World3D, centre: Vector3, radius: float, now := Soldier._now()) -> Dictionary:
	var map := world.navigation_map
	var space := world.direct_space_state
	var spots := {}  # Vector2i grid cell -> Array of Vector3 on the navmesh, lowest first
	var ground := {}  # Vector2i grid cell -> the lowest surface found over it (y)
	var oldest := now
	var probed := {}  # Vector2i grid cell -> when its probes were made
	var n := ceili(radius / GRID_M)
	var base := Vector2i(roundi(centre.x / GRID_M), roundi(centre.z / GRID_M))
	var height := roundi(centre.y * 4.0)
	var band := floori(centre.y / CELL_BAND_M)
	var top := centre.y + SCAN_UP_M
	var bottom := centre.y - SCAN_DOWN_M
	if _cells.size() >= CELL_MAX:
		_cells.clear()
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			if Vector2(ix, iz).length() * GRID_M > radius:
				continue
			var cell := base + Vector2i(ix, iz)
			# Probed for band b: scans from heights in bands b - 1 to b + 1.
			var kept: Array = []
			for b: int in [band, band - 1, band + 1]:
				kept = _cells.get(Vector3i(cell.x, cell.y, b), [])
				if not kept.is_empty() and now - float(kept[0]) < CACHE_S:
					break
				kept = []
			if kept.is_empty():
				kept = [now] + _probe_cell(world, map, space, cell, (band + 2) * CELL_BAND_M + SCAN_UP_M, (band - 1) * CELL_BAND_M - SCAN_DOWN_M)
				_cells[Vector3i(cell.x, cell.y, band)] = kept
			oldest = minf(oldest, float(kept[0]))
			probed[cell] = kept[0]
			for y: float in kept[1]:
				if y >= bottom and y <= top:
					ground[cell] = y  # the lowest in this scan's reach
					break
			var here: Array = (kept[2] as Array).filter(func(sp: Vector3) -> bool: return sp.y >= bottom - 0.15 and sp.y <= top + 0.15)
			if not here.is_empty():
				spots[cell] = here
	return {"list": _group(world, map, spots, ground, probed, height, now), "at": oldest}


## One cell's probes (see the class notes), from height `top` down to `bottom`: [its upward
## surfaces, its walkable inside spots], both lowest first.
static func _probe_cell(world: World3D, map: RID, space: PhysicsDirectSpaceState3D, cell: Vector2i, top: float, bottom: float) -> Array:
	var x := (cell.x + 0.5) * GRID_M
	var z := (cell.y + 0.5) * GRID_M
	var here: Array[Vector3] = []
	var surfaces := _surfaces(space, Vector3(x, top, z), bottom, MAX_SURFACES * 3)
	if surfaces.is_empty():
		return [surfaces, here]
	for y: float in surfaces:
		var p := Vector3(x, y + 0.1, z)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(q.x - p.x, q.z - p.z).length() > NAV_SNAP_M or q.y - y > SURFACE_SNAP_M or y - q.y > SURFACE_SNAP_BELOW_M:
			continue
		# The floor under that navmesh point must be this surface: the navmesh floats a little
		# over the floor, as high as a bed or a sofa (the floor's navmesh beside one is no
		# spot on its top). The spot is on the floor itself.
		var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.05, q + Vector3.DOWN * (SURFACE_SNAP_M + 0.3), Throwables.WORLD_MASK))
		if under.is_empty() or absf((under.position as Vector3).y - y) > 0.15:
			continue
		var s := Vector3(q.x, (under.position as Vector3).y, q.z)
		if here.any(func(o: Vector3) -> bool: return absf(o.y - s.y) < STEP_M):
			continue
		if inside(world, s):
			here.append(s)
	return [surfaces, here]


## The scanned cells' spots (`spots`, `ground`, `probed`: see _scan; `height`: the scan's)
## made into buildings.
static func _group(world: World3D, map: RID, spots: Dictionary, ground: Dictionary, probed := {}, height := 0, now := 0.0) -> Array:
	# Spots next to each other (8 ways) and level, or linked up a stair, make one building.
	var out: Array = []
	var groups: Array = []  # Array[Vector3i] each: the spots of one floor (or more, up a stair)
	var seen := {}
	var joins := {}  # Vector3i -> Array of Vector3i: neighbours joined up a stair's rise
	for cell: Vector2i in spots:
		for k in (spots[cell] as Array).size():
			var first := Vector3i(cell.x, k, cell.y)
			if seen.has(first):
				continue
			var group: Array[Vector3i] = []
			var queue: Array[Vector3i] = [first]
			seen[first] = true
			while not queue.is_empty():
				var c: Vector3i = queue.pop_back()
				group.append(c)
				var a := _spot(spots, c)
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var nc := Vector2i(c.x + dx, c.z + dz)
						if (dx == 0 and dz == 0) or not spots.has(nc):
							continue
						var list: Array = spots[nc]
						for j in list.size():
							var b: Vector3 = list[j]
							var rise := absf(b.y - a.y)
							if rise > STAIR_STEP_M or (rise > STEP_M and not _linked(map, a, b)):
								continue
							var id := Vector3i(nc.x, j, nc.y)
							if rise > STEP_M:
								_join(joins, c, id)
							if not seen.has(id):
								seen[id] = true
								queue.append(id)
			if group.size() >= MIN_SPOTS:
				groups.append(group)
	# Floors stacked over each other and linked by a navmesh path that never leaves their
	# footprint (a stair inside: the grid's spots on a narrow stair can miss its navmesh) are
	# one building; the path gives the stair between them.
	var climbs := _link_floors(map, spots, groups)
	for gi in groups.size():
		if (groups[gi] as Array).is_empty():
			continue
		# The same spots as a building made since its cells were last probed: that building.
		var group: Array = groups[gi]
		var newest := -INF
		var first := INF
		var ids := PackedStringArray()
		for id: Vector3i in group:
			var at := float(probed.get(Vector2i(id.x, id.z), now))
			newest = maxf(newest, at)
			first = minf(first, at)
			ids.append("%d,%d,%d" % [id.x, id.y, id.z])
		ids.sort()
		var key := "%d|%s" % [height, ",".join(ids)]
		var kept: Array = _built.get(key, [])
		var b: Dictionary
		if not kept.is_empty() and float(kept[0]) >= newest and now - float(kept[1]) < CACHE_S:
			b = kept[2]
		else:
			b = _building(world, spots, groups[gi], joins, ground, climbs.get(gi, []))
			if _built.size() >= BUILT_MAX:
				_built.clear()
			_built[key] = [now, first, b]
		if not b.is_empty():
			out.append(b)
	return out


## Merges the groups (each an Array[Vector3i] of spots) that stand over each other, with
## LINK_OVERLAP cells or more of their footprints in common, and are linked by a navmesh path
## that stays within their footprint: the higher one's spots go into the lower one's group
## (the group merged away is left empty). Returns {group index: [{"foot", "top", "spots"}]}:
## each link's stair, from its path (the last point on the lower floor, the first on the upper).
static func _link_floors(map: RID, spots: Dictionary, groups: Array) -> Dictionary:
	var info: Array = []  # per group: {"cells": {Vector2i: true}, "y": mean height, "centre"}
	for g: Array in groups:
		var cells := {}
		var sum := Vector3.ZERO
		for id: Vector3i in g:
			cells[Vector2i(id.x, id.z)] = true
			sum += _spot(spots, id)
		info.append({"cells": cells, "y": sum.y / g.size(), "centre": sum / g.size()})
	var order: Array = range(groups.size())
	order.sort_custom(func(a: int, c: int) -> bool: return float(info[a].y) < float(info[c].y))
	var owner: Array = range(groups.size())  # each group's building: the group it's merged into
	var climbs := {}
	for oi in order.size():
		var hi: int = order[oi]
		for oj in range(oi - 1, -1, -1):
			var lo: int = order[oj]
			if float(info[hi].y) - float(info[lo].y) <= STEP_M or int(owner[lo]) == int(owner[hi]):
				continue
			var shared := 0
			for c: Vector2i in info[hi].cells:
				if info[lo].cells.has(c):
					shared += 1
			if shared < LINK_OVERLAP:
				continue
			var stair := _climb(map, spots, groups[lo], groups[hi], info[lo], info[hi])
			if stair.is_empty():
				continue
			var root: int = owner[lo]
			var gone: int = owner[hi]
			for k in owner.size():
				if int(owner[k]) == gone:
					owner[k] = root
			climbs[root] = (climbs.get(root, []) as Array) + (climbs.get(gone, []) as Array) + [stair]
			climbs.erase(gone)
			break
	for k in groups.size():
		var root: int = owner[k]
		if root != k:
			(groups[root] as Array).append_array(groups[k])
	for k in groups.size():
		if int(owner[k]) != k:
			groups[k] = [] as Array[Vector3i]
	return climbs


## The stair from group `lo` up to group `hi` (see _link_floors): {"foot", "top", "spots"}, or
## {} if no navmesh path within their footprint links them.
static func _climb(map: RID, spots: Dictionary, lo: Array, hi: Array, lo_info: Dictionary, hi_info: Dictionary) -> Dictionary:
	var from := _spot_nearest(spots, lo, hi_info.centre)
	var to := _spot_nearest(spots, hi, lo_info.centre)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty() or not _reached(path[path.size() - 1], to):
		return {}
	var cells: Dictionary = (lo_info.cells as Dictionary).duplicate()
	cells.merge(hi_info.cells)
	var samples: Array[Vector3] = [path[0]]
	var length := 0.0
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var z: Vector3 = path[i]
		length += a.distance_to(z)
		var steps := maxi(ceili(a.distance_to(z) / (GRID_M * 0.25)), 1)
		for j in range(1, steps + 1):
			samples.append(a.lerp(z, float(j) / steps))
	if length > LINK_PATH_MAX_M:
		return {}
	for p in samples:
		var c := Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))
		var near := false
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if cells.has(c + Vector2i(dx, dz)):
					near = true
		if not near:
			return {}  # out of the building and back in: no stair inside
	# The path runs on the navmesh, a little over the floors: heights are taken from its ends,
	# and the foot and top put back down on the floors.
	var low_y := samples[0].y
	var high_y := samples[samples.size() - 1].y
	var foot := -1
	for i in samples.size():
		if samples[i].y <= low_y + FLOOR_BAND_M:
			foot = i
	var top := -1
	for i in range(maxi(foot, 0), samples.size()):
		if samples[i].y >= high_y - FLOOR_BAND_M:
			top = i
			break
	if foot < 0 or top <= foot:
		return {}
	var sink := func(p: Vector3, floor_y: float, nav_y: float) -> Vector3: return Vector3(p.x, p.y - nav_y + floor_y, p.z)
	var between: Array = samples.slice(foot + 1, top).map(func(p: Vector3) -> Vector3: return sink.call(p, from.y, low_y))
	return {"foot": sink.call(samples[foot], from.y, low_y), "top": sink.call(samples[top], to.y, high_y), "spots": between}


## Whether a path's last point `end` (on the navmesh, which floats up to SURFACE_SNAP_M over the
## floor) got to `goal` (a spot on the floor).
static func _reached(end: Vector3, goal: Vector3) -> bool:
	return Vector2(end.x - goal.x, end.z - goal.z).length() <= 0.5 and end.y - goal.y <= SURFACE_SNAP_M + 0.1 and goal.y - end.y <= 0.5


## The spot of `group` flat-nearest `point`.
static func _spot_nearest(spots: Dictionary, group: Array, point: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for id: Vector3i in group:
		var s := _spot(spots, id)
		var d := Vector2(s.x - point.x, s.z - point.z).length()
		if d < best_d:
			best = s
			best_d = d
	return best


## The upward surfaces straight down from `top` to height `bottom` (lowest first): floors,
## slabs, a roof, a parapet's top, furniture.
static func _surfaces(space: PhysicsDirectSpaceState3D, top: Vector3, bottom: float, most := MAX_SURFACES) -> Array[float]:
	var out: Array[float] = []
	var from := top
	for k in most:
		if from.y <= bottom:
			break
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(from.x, bottom, from.z), Throwables.WORLD_MASK))
		if hit.is_empty():
			break
		var p: Vector3 = hit.position
		if (hit.normal as Vector3).y >= FLOOR_NORMAL_Y:
			out.push_front(p.y)
		from = Vector3(from.x, p.y - SURFACE_SKIP_M, from.z)
	return out


## Whether a short navmesh path runs from `a` to `b` (a stair's steps between them).
static func _linked(map: RID, a: Vector3, b: Vector3) -> bool:
	var now := Soldier._now()
	var key := [a, b]
	var kept: Array = _links.get(key, [])
	if not kept.is_empty() and now - float(kept[0]) < CACHE_S:
		return kept[1]
	if _links.size() >= LINK_MAX:
		_links.clear()
	var linked := false
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	if not path.is_empty() and _reached(path[path.size() - 1], b):
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		linked = length <= LINK_PATH_M
	_links[key] = [now, linked]
	return linked


static func _join(joins: Dictionary, a: Vector3i, b: Vector3i) -> void:
	for pair: Array in [[a, b], [b, a]]:
		if not joins.has(pair[0]):
			joins[pair[0]] = []
		if not (joins[pair[0]] as Array).has(pair[1]):
			joins[pair[0]].append(pair[1])


static func _spot(spots: Dictionary, id: Vector3i) -> Vector3:
	return (spots[Vector2i(id.x, id.z)] as Array)[id.y]


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
	return _wall_m(world, from, dir, reach) < INF


## How far along `dir` from `from` a wall stands (see _wall_within), INF for none within `reach`.
static func _wall_m(world: World3D, from: Vector3, dir: Vector3, reach: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Throwables.WORLD_MASK)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf((hit.normal as Vector3).y) >= WALL_NORMAL_Y:
		return INF
	return from.distance_to(hit.position)


static func _dir(k: int) -> Vector3:
	var a := TAU * k / PROBE_DIRS
	return Vector3(cos(a), 0.0, sin(a))


static func _building(world: World3D, spots: Dictionary, group: Array[Vector3i], joins: Dictionary, ground: Dictionary, climbs: Array = []) -> Dictionary:
	var list: Array[Vector3] = []
	var centre := Vector3.ZERO
	var cells := {}  # Vector2i -> true: every cell the building covers, any floor
	for id in group:
		var s := _spot(spots, id)
		list.append(s)
		centre += s
		cells[Vector2i(id.x, id.z)] = true
	centre /= list.size()
	# Floors: heights where FLOOR_MIN_SPOTS or more spots stand level, lowest first.
	var heights: Array[float] = []
	for s in list:
		heights.append(s.y)
	heights.sort()
	var levels: Array[float] = []
	var run: Array[float] = [heights[0]]
	for i in range(1, heights.size() + 1):
		if i < heights.size() and heights[i] - run.back() <= STEP_M:
			run.append(heights[i])
			continue
		if run.size() >= FLOOR_MIN_SPOTS:
			levels.append(run[run.size() >> 1])
		if i < heights.size():
			run = [heights[i]]
	if levels.is_empty():
		levels.append(heights[0])
	var floors: Array = []
	for y in levels:
		floors.append({"y": y, "spots": [], "cells": {}, "rooms": [], "roof": false})
	for id in group:
		var s := _spot(spots, id)
		var fi := _floor_index(floors, s.y)
		if fi >= 0:
			(floors[fi].spots as Array).append(s)
			floors[fi].cells[Vector2i(id.x, id.z)] = s
	floors = floors.filter(func(f: Dictionary) -> bool: return not (f.spots as Array).is_empty())
	# The stairs: spots between floors joined to two floors, or two floors' spots joined directly.
	var b := {"spots": list, "centre": centre, "entrances": [], "ports": [], "rooms": [], "floors": floors, "stairs": []}
	b.stairs = _stairs(spots, group, joins, floors)
	# And those found by a navmesh path between stacked floors (_link_floors).
	for c: Dictionary in climbs:
		var lo := _floor_index(floors, (c.foot as Vector3).y)
		var hi := _floor_index(floors, (c.top as Vector3).y)
		if lo >= 0 and hi > lo and not (b.stairs as Array).any(func(st: Dictionary) -> bool: return int(st.from) == lo and int(st.to) == hi):
			(b.stairs as Array).append({"from": lo, "to": hi, "foot": c.foot, "top": c.top, "spots": c.spots})
	(b.stairs as Array).sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return int(p.to) < int(q.to))
	b.entrances = _entrances(world, b, cells)
	if b.entrances.is_empty():
		var low := INF
		for id in group:
			low = minf(low, float(ground.get(Vector2i(id.x, id.z), INF)))
		if float(floors[0].y) - low >= RAISED_M:
			return {}  # up on something with no way in: no building
	for fi in range(1, floors.size()):
		floors[fi].roof = _open_sky(world, floors[fi].spots)
	b.ports = _ports(world, b, cells)
	var rooms: Array = []
	for fi in floors.size():
		var f: Dictionary = floors[fi]
		var from: Vector3 = f.spots[0]
		if fi == 0 and not b.entrances.is_empty():
			from = b.entrances[0].inside
		for st: Dictionary in b.stairs:
			if int(st.to) == fi:
				from = st.top
				break
		for r: Dictionary in _rooms(world, f.spots, from):
			r["floor"] = fi
			(f.rooms as Array).append(rooms.size())
			rooms.append(r)
	b.rooms = rooms
	for f: Dictionary in floors:
		f.erase("cells")
	return b


## The floor (index in `floors`) height `y` is on, -1 for none (a stair between floors).
static func _floor_index(floors: Array, y: float) -> int:
	for i in floors.size():
		if absf(float(floors[i].y) - y) <= FLOOR_BAND_M:
			return i
	return -1


## The stairs between floors (see the class notes): [{"from", "to", "foot", "top", "spots"}],
## lowest first.
static func _stairs(spots: Dictionary, group: Array[Vector3i], joins: Dictionary, floors: Array) -> Array:
	var by_cell := {}  # Vector2i -> the group's spots over it
	var fl := {}  # Vector3i -> its floor, -1 on a stair
	for id in group:
		var c := Vector2i(id.x, id.z)
		if not by_cell.has(c):
			by_cell[c] = []
		by_cell[c].append(id)
		fl[id] = _floor_index(floors, _spot(spots, id).y)
	# The spots a spot is joined to: level neighbours, and those up a stair's rise.
	var linked := func(id: Vector3i) -> Array:
		var out: Array = []
		var a := _spot(spots, id)
		var up: Array = joins.get(id, [])
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for other: Vector3i in by_cell.get(Vector2i(id.x + dx, id.z + dz), []):
					if other != id and (absf(_spot(spots, other).y - a.y) <= STEP_M or up.has(other)):
						out.append(other)
		return out
	# Stair spots (on no floor) in runs joined to each other.
	var comp := {}  # Vector3i -> run number
	var runs: Array = []
	for id in group:
		if int(fl[id]) >= 0 or comp.has(id):
			continue
		var run: Array = []
		var queue: Array = [id]
		comp[id] = runs.size()
		while not queue.is_empty():
			var c: Vector3i = queue.pop_back()
			run.append(_spot(spots, c))
			for other: Vector3i in linked.call(c):
				if int(fl[other]) < 0 and not comp.has(other):
					comp[other] = runs.size()
					queue.append(other)
		runs.append({"spots": run, "floors": {}})  # floor -> the spot on it the run joins
	var out: Array = []
	var add := func(from: int, to: int, foot: Vector3, top: Vector3, list: Array) -> void:
		for st: Dictionary in out:
			if int(st.from) == from and int(st.to) == to and (st.foot as Vector3).distance_to(foot) < 2.5:
				return
		out.append({"from": from, "to": to, "foot": foot, "top": top, "spots": list})
	# Floors' spots next to a run, or joined straight to a higher floor's.
	for id in group:
		var fi: int = fl[id]
		if fi < 0:
			continue
		for other: Vector3i in linked.call(id):
			var fo: int = fl[other]
			if fo < 0:
				var r: Dictionary = runs[comp[other]]
				if not r.floors.has(fi):
					r.floors[fi] = _spot(spots, id)
			elif fo > fi:
				add.call(fi, fo, _spot(spots, id), _spot(spots, other), [])
	for r: Dictionary in runs:
		var touched: Array = r.floors.keys()
		if touched.size() < 2:
			continue
		touched.sort()
		add.call(touched[0], touched[-1], r.floors[touched[0]], r.floors[touched[-1]], r.spots)
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return int(p.to) < int(q.to))
	return out


## Whether most of `spots` (a few looked at) have nothing over them for ROOF_SKY_M.
static func _open_sky(world: World3D, spots: Array) -> bool:
	var step := maxi(spots.size() / 6, 1)
	var open := 0
	var looked := 0
	for i in range(0, spots.size(), step):
		var s: Vector3 = spots[i]
		looked += 1
		if Throwables.clear_line(world, s + Vector3.UP * 0.3, s + Vector3.UP * ROOF_SKY_M):
			open += 1
	return open * 2 > looked


## Where navmesh paths from the middle of the first floor out to the open (PROBE_DIRS ways)
## leave the building (`cells`: every cell it covers).
static func _entrances(world: World3D, b: Dictionary, cells: Dictionary) -> Array:
	var map := world.navigation_map
	var first: Array = b.floors[0].spots
	var start: Vector3 = first[0]
	var best := INF
	for s: Vector3 in first:
		var d := Vector2(s.x - b.centre.x, s.z - b.centre.z).length()
		if d < best:
			best = d
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


## Window and parapet ports (a wall at PROBE_HEIGHT with a clear view out at PORT_EYE) along
## each floor's edge spots, and a door port just inside each entrance. A low wall (no wall
## above at PORT_HEAD) whose view lands on the same floor of this building is a railing across
## a stairwell or round a roof hatch, not a port.
static func _ports(world: World3D, b: Dictionary, cells: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in b.entrances:
		out.append({"point": e.inside, "dir": e.normal, "kind": "door", "floor": 0})
	var floors: Array = b.floors
	for fi in floors.size():
		var f: Dictionary = floors[fi]
		var on: Dictionary = f.cells
		for c: Vector2i in on:
			var edge := false
			for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not on.has(c + nb):
					edge = true
			if not edge:
				continue
			var q: Vector3 = on[c]
			if out.any(func(p: Dictionary) -> bool: return (p.point as Vector3).distance_to(q) < PORT_GAP_M):
				continue
			# Of the ways out of it, the one square to its wall (the wall nearest that way).
			var best := {}
			var best_m := INF
			for k in PROBE_DIRS:
				var d := _dir(k)
				var wall_m := _wall_m(world, q + Vector3.UP * PROBE_HEIGHT, d, PORT_WALL_M)
				if wall_m >= best_m:
					continue
				var eye := q + Vector3.UP * PORT_EYE
				if not Throwables.clear_line(world, eye, eye + d * PORT_VIEW_M):
					continue
				var window := _wall_within(world, q + Vector3.UP * PORT_HEAD, d, PORT_WALL_M)
				var far := eye + d * PORT_VIEW_M
				if not window and on.has(Vector2i(floori(far.x / GRID_M), floori(far.z / GRID_M))):
					continue  # a railing: across its own floor
				best = {"point": q, "dir": d, "kind": "window" if window else "parapet", "floor": fi}
				best_m = wall_m
			if not best.is_empty():
				out.append(best)
	return out


## The rooms of one floor (`spots`), from `from` inward: the spots seen from the nearest spot
## not yet in a room, each with its two far corners (left and right as one comes in).
static func _rooms(world: World3D, spots: Array, from: Vector3) -> Array:
	var left: Array[Vector3] = []
	left.assign(spots)
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
