class_name Buildings
extends RefCounted
## Buildings the AI can garrison and clear (Captain, P0164 queue 17 core). They are found by
## probing what stands in the world now, not read from a list, so the compound's main building,
## a module's houses and a wall blown open all count as they are:
## - Inside: a walkable spot (navmesh over it; the spot is on the floor itself, the navmesh
##   floats a little over it) with walls round it. Of PROBE_DIRS level rays at PROBE_HEIGHT
##   (below a window's sill, so only doorways and breaches let them out), at most
##   MAX_OPEN reach PROBE_M without meeting a wall, and never two opposite ones (a gap between
##   two buildings is no room). Under a roof (a hangar's or a factory's hall, F-162) the rays
##   reach HALL_PROBE_M and HALL_MAX_OPEN may be open. Ground rising under a ray isn't a wall (hilly zones). Inside
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
## "top", "spots"}]). Scans are cached for CACHE_S (walls change; see CELL_BAND_M). Proposed numbers.

const GRID_M := 1.0
const SCAN_M := 14.0
const PROBE_HEIGHT := 0.6
const PROBE_M := 12.0
const PROBE_DIRS := 8
const MAX_OPEN := 2
## Big open halls (F-162: a hangar about 19 x 17 m with a 14 m door, a factory floor up to 26 m
## wide): a spot with a roof straight over it within ROOF_UP_M (the underside of something, a
## surface facing down) probes for walls out to HALL_PROBE_M instead, and may have up to
## HALL_MAX_OPEN ways out (a wide door seen from close by), still never two opposite ones. A
## canopy with no walls stays outside. Proposed.
const ROOF_UP_M := 12.0
const HALL_PROBE_M := 26.0
const HALL_MAX_OPEN := 3
const ROOF_NORMAL_Y := -0.5
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
const CACHE_MAX := 256
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
## something (a watchtower's platform, a container's top), not in a building. The ground is
## the lowest surface over the building's cells within GROUND_DOWN_M under its lowest floor:
## found from the building itself, not from the scan's reach, so a scan from high up (whose
## reach stops short of the ground) gets the answer a scan from below gets. (A building is
## cached by its spots alone, _built: an answer that hung on the scan's height would hang on
## which scan came first. Review of the executive audit, 2026-10-18.)
const RAISED_M := 1.5
const GROUND_DOWN_M := 8.0

## Captain, 2026-10-14 (P1104, a fight in ridge_hot's town: 21 fps, "engine physics" 451.7 ms):
## the squads' tactics and context ask for the buildings round their centre and the enemy's
## every second, and both move, so nearly every ask missed the cache (keyed to 2 m) and scanned
## afresh: 150-960 ms a squad think in a town (R1130-R1136: three quarters of it the per-cell
## probes, half of those navmesh closest-point queries). Exact scans share each 1 m cell's
## probes across three CELL_BAND_M height bands, and buildings made of the same actual spots
## share their floors, stairs, entrances, ports and rooms (nothing in a building hangs on the
## scan's height: see RAISED_M). Closest-surface probes use a spatial index of navigation
## regions, refreshed when the map changes. Everything still goes after
## CACHE_S: an answer is never older than that (its "at" is the oldest probe it was built
## from), and a building is made afresh once any of its cells was probed again.
## Proposed: the height band (m), and how many cells, buildings and links are kept.
const CELL_BAND_M := 6.0
const CELL_MAX := 60000
const BUILT_MAX := 512
const LINK_MAX := 20000
## Closest-surface probes only accept points less than a metre away. Index navigation
## region bounds on this grid so they query nearby regions instead of the whole zone.
const REGION_GRID_M := 16.0
const REGION_MARGIN_M := 1.0

static var _cache := {}
static var _cells := {}  # Vector3i (cell x, z, height band) -> [at, surfaces, spots] (_probe_cell)
static var _built := {}  # a group's actual spots -> [built at, oldest probe, building]
static var _links := {}  # [a, b] -> [at, linked]: _linked's answers
static var _climbs := {}  # [from, to] -> [at, stair]: _climb's answers (F-206: a cut-short scan's next ask goes on)
## The index (_index_regions): Vector2i (a REGION_GRID_M square) -> the RIDs of the enabled
## regions whose bounds reach it. RIDs, not nodes: it's made again whenever the map's
## iteration or its count of regions changes, so a region freed since is never asked.
static var _region_grid := {}
static var _region_map := RID()
static var _region_iteration := 0
static var _region_count := -1
## Tests: how long scans have taken so far (usec, every world).
static var spent_usec := 0
## The world and level the cached scans belong to (_scope); another one empties the cache.
static var _cache_scope := ""
## Captain, 2026-10-17 playtest P1591 (stutters "dependant on ai presence"): the session log's
## worst frames were building scans, 46-400 ms, several AI asking in the same frame. A frame's
## scans stop at FRAME_BUDGET_USEC (the first always runs): later asks that frame get the last
## answer for that spot, however old, or none (they ask again next tick). Not when headless (the
## suites and a dedicated host keep exact, synchronous answers).
const FRAME_BUDGET_USEC := 4000
static var _budget_frame := -1
static var _budget_used := 0
## Perf pass (2026-10-22): a scan's cell probes stop at the frame's budget too, the first scan's
## as well (a town's first scan was 200-600 ms in one frame, and again each time its CACHE_S ran
## out); the cells probed so far are kept (_cells), so the next ask goes on from there, and until
## then the ask gets what it knew before, as an ask over budget does. The perf suites turn this on
## headless (budget_always) to measure the game as a player's machine runs it.
static var budget_always := false


## The buildings with an inside spot within `radius` of `centre` (see the class notes).
## Cached per world and level: another level at the same coordinates (the next zone, a
## second world) never gets this one's buildings. `exact`: never cut short by the frame's budget
## (FRAME_BUDGET_USEC), for a player's one-off order whose answer can't wait for the next tick
## (Squad.breach_target: an empty answer there would be taken as "no building behind that wall").
static func near(from: Node3D, centre: Vector3, radius := SCAN_M, details := true, exact := false) -> Array:
	if from == null or not from.is_inside_tree():
		return []
	if NavigationServer3D.map_get_iteration_id(from.get_world_3d().navigation_map) == 0:
		return []  # not synchronized yet; don't cache a false empty result
	var scope := _scope(from)
	if scope != _cache_scope:
		_cache.clear()  # a new level (or world): the old one's scans mean nothing here
		_cells.clear()
		_built.clear()
		_links.clear()
		_climbs.clear()
		_region_grid.clear()
		_region_iteration = 0
		_region_count = -1
		_cache_scope = scope
	var key := "%s|%d,%d,%d,%d" % [scope, roundi(centre.x / 2.0), roundi(centre.y / 2.0), roundi(centre.z / 2.0), roundi(radius)]
	if not details:
		key += "|presence"
	var now := Soldier._now()
	var hit: Dictionary = _cache.get(key, {})
	if not hit.is_empty() and now - float(hit.at) < CACHE_S:
		_cache.erase(key)
		_cache[key] = hit  # least recently used first, without a full-cache purge
		return hit.list
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	var budgeted := not exact and (budget_always or DisplayServer.get_name() != "headless")
	if _budget_used >= FRAME_BUDGET_USEC and budgeted:
		return hit.list if not hit.is_empty() else []  # over this frame's budget: what it knew
	_cache.erase(key)  # an expired answer: the fresh one goes in last (most recently used), not in its old slot
	if _cache.size() >= CACHE_MAX:
		_cache.erase(_cache.keys()[0])
	var t := Time.get_ticks_usec()
	# Scanned from exactly this centre and radius, as an uncached scan would be (an earlier
	# A wider square scan handed back whole buildings from outside the circle, which changed
	# answers: casualty's "out in the open" soldier found cover the plain scan doesn't). The
	# speed-up is in the parts below that don't change the answer: each cell's probes, each
	# building made of the same spots, and each stair link, all kept for CACHE_S.
	var area := _scan(from.get_world_3d(), centre, radius, now, details, t + FRAME_BUDGET_USEC - _budget_used if budgeted else 0)
	FrameCost.spent(&"buildings", t)  # (inside "ai" too when an AI's tick asked)
	spent_usec += Time.get_ticks_usec() - t
	_budget_used += Time.get_ticks_usec() - t
	if area.get("partial", false):
		if not hit.is_empty():
			_cache[key] = hit  # (kept for the next ask, which goes on probing)
		return hit.list if not hit.is_empty() else []
	var list: Array = area.list
	_cache[key] = {"at": area.at, "list": list}
	return list


## A formation only needs to know whether buildings are present. Keep the same probes,
## floor links and entrance/raised-surface validation, without computing every room and port.
static func has_near(from: Node3D, centre: Vector3, radius := SCAN_M) -> bool:
	return not near(from, centre, radius, false).is_empty()


## Which world and level `from` is in: its World3D and the level node above it (none for a
## node outside any level), as a cache key.
## Drops every cached scan, probe, building and link: for when the walls or the navmesh change
## under them at once (a test building a house and baking its navmesh mid-run). The cell probes
## (perf/town-physics) are shared by every ask nearby for CACHE_S, so one probe made before a
## bake would otherwise keep the old answer for every scan round it.
static func forget() -> void:
	_cache.clear()
	_cells.clear()
	_built.clear()
	_links.clear()
	_climbs.clear()
	_region_grid.clear()
	_region_iteration = 0
	_region_count = -1


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
## `exact`: as near's.
static func nearest(from: Node3D, point: Vector3, max_m: float, exact := false) -> Dictionary:
	var best := {}
	var best_d := max_m
	for b: Dictionary in near(from, point, maxf(max_m + 4.0, SCAN_M), true, exact):
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
## band `centre` is in (_cells), for the scans that overlap it. A cell's surfaces are probed
## GROUND_DOWN_M deeper than its spots, so any building found has its ground in them (RAISED_M).
## `deadline` (Time.get_ticks_usec, 0: none): past it no more cells are probed (at least one
## is) and the scan comes back {"partial": true}.
static func _scan(world: World3D, centre: Vector3, radius: float, now := Soldier._now(), details := true, deadline := 0) -> Dictionary:
	var started := Time.get_ticks_usec()
	var map := world.navigation_map
	_index_regions(map)
	var space := world.direct_space_state
	var spots := {}  # Vector2i grid cell -> Array of Vector3 on the navmesh, lowest first
	var surfaces := {}  # Vector2i grid cell -> every surface probed over it (y), lowest first
	var oldest := now
	var probed := {}  # Vector2i grid cell -> when its probes were made
	var n := ceili(radius / GRID_M)
	var base := Vector2i(roundi(centre.x / GRID_M), roundi(centre.z / GRID_M))
	var band := floori(centre.y / CELL_BAND_M)
	var top := centre.y + SCAN_UP_M
	var bottom := centre.y - SCAN_DOWN_M
	if _cells.size() >= CELL_MAX:
		_cells.clear()
	var probed_now := 0
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
				if deadline > 0 and probed_now > 0 and Time.get_ticks_usec() >= deadline:
					FrameCost.spent(&"building_probes", started)
					return {"partial": true}
				probed_now += 1
				# Spots down to the band below's reach, surfaces GROUND_DOWN_M (and a little) deeper:
				# a spot this scan finds is at most SCAN_DOWN_M + 0.15 under `centre`, and the band
				# above's probe (which a scan from here may use) starts that much higher.
				var spot_bottom := (band - 1) * CELL_BAND_M - SCAN_DOWN_M
				kept = [now] + _probe_cell(world, map, space, cell, (band + 2) * CELL_BAND_M + SCAN_UP_M, spot_bottom - GROUND_DOWN_M - 0.5, spot_bottom)
				_cells[Vector3i(cell.x, cell.y, band)] = kept
			oldest = minf(oldest, float(kept[0]))
			probed[cell] = kept[0]
			surfaces[cell] = kept[1]
			var here: Array = (kept[2] as Array).filter(func(sp: Vector3) -> bool: return sp.y >= bottom - 0.15 and sp.y <= top + 0.15)
			if not here.is_empty():
				spots[cell] = here
	FrameCost.spent(&"building_probes", started)
	var list := _group(world, map, spots, surfaces, probed, now, details, deadline)
	if _cut_short:
		return {"partial": true}
	return {"list": list, "at": oldest}


## One cell's probes (see the class notes), from height `top` down to `bottom`: [its upward
## surfaces, its walkable inside spots (on the surfaces from `spot_bottom` up)], both lowest first.
static func _probe_cell(world: World3D, map: RID, space: PhysicsDirectSpaceState3D, cell: Vector2i, top: float, bottom: float, spot_bottom := -INF) -> Array:
	var x := (cell.x + 0.5) * GRID_M
	var z := (cell.y + 0.5) * GRID_M
	var here: Array[Vector3] = []
	var surfaces := _surfaces(space, Vector3(x, top, z), bottom, MAX_SURFACES * 3)
	if surfaces.is_empty():
		return [surfaces, here]
	for y: float in surfaces:
		if y < spot_bottom:
			continue  # deep enough only for the ground under a building (RAISED_M)
		var p := Vector3(x, y + 0.1, z)
		var q := _closest_nav_point(p)
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


## Indexes the map's regions (_region_grid) unless nothing changed since: the same map, its
## iteration and its count of regions (a cheap guard: a region added or freed before the map's
## next sync changes the count, not the iteration).
static func _index_regions(map: RID) -> void:
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	var regions := NavigationServer3D.map_get_regions(map)
	if map == _region_map and iteration == _region_iteration and regions.size() == _region_count:
		return
	_region_map = map
	_region_iteration = iteration
	_region_count = regions.size()
	_region_grid.clear()
	for region: RID in regions:
		if not NavigationServer3D.region_get_enabled(region) or NavigationServer3D.region_get_iteration_id(region) == 0:
			continue
		var bounds := NavigationServer3D.region_get_bounds(region)
		if bounds.size.length_squared() == 0.0:
			continue
		bounds = bounds.grow(REGION_MARGIN_M)
		var lo := Vector2i(floori(bounds.position.x / REGION_GRID_M), floori(bounds.position.z / REGION_GRID_M))
		var hi := Vector2i(floori(bounds.end.x / REGION_GRID_M), floori(bounds.end.z / REGION_GRID_M))
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var key := Vector2i(x, z)
				if not _region_grid.has(key):
					_region_grid[key] = []
				(_region_grid[key] as Array).append(region)


static func _closest_nav_point(p: Vector3) -> Vector3:
	var key := Vector2i(floori(p.x / REGION_GRID_M), floori(p.z / REGION_GRID_M))
	var best := Vector3.INF
	var distance := INF
	for region: RID in _region_grid.get(key, []):
		var q := NavigationServer3D.region_get_closest_point(region, p)
		var d := p.distance_squared_to(q)
		if d < distance:
			distance = d
			best = q
	return best


## The scanned cells' spots (`spots`, `surfaces`, `probed`: see _scan) made into buildings.
## Perf (F-206, 2026-10-22): past `deadline` (Time.get_ticks_usec, 0: none) no more buildings are
## made (at least one is): _cut_short is set and the scan comes back partial. The ones made are
## kept (_built), so the next ask goes on from there, a building or more a frame, where a cold
## scan of a city block made them all in one frame (100-250 ms).
static var _cut_short := false


static func _group(world: World3D, map: RID, spots: Dictionary, surfaces: Dictionary, probed := {}, now := 0.0, details := true, deadline := 0) -> Array:
	_cut_short = false
	var started := Time.get_ticks_usec()
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
	var climbs := _link_floors(map, spots, groups, now, deadline)
	FrameCost.spent(&"building_groups", started)
	if _cut_short:
		return out
	var made := 0
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
			ids.append("%d,%s,%d" % [id.x, str(_spot(spots, id)), id.z])
		ids.sort()
		# The same geometry can be queried from different heights (slopes, stairs, a
		# moving soldier). Key its actual spots, not the querying soldier's height: what
		# _building makes of them never hangs on the scan's height or reach (RAISED_M).
		var key := ",".join(ids)
		if not details:
			key += "|presence"
		var kept: Array = _built.get(key, [])
		var b: Dictionary
		if not kept.is_empty() and float(kept[0]) >= newest and now - float(kept[1]) < CACHE_S:
			b = kept[2]
		else:
			if deadline > 0 and made > 0 and Time.get_ticks_usec() >= deadline:
				_cut_short = true
				return out
			made += 1
			b = _building(world, spots, groups[gi], joins, surfaces, climbs.get(gi, []), details)
			if _built.size() >= BUILT_MAX:
				_built.clear()
			_built[key] = [now, first, b]
		if not b.is_empty():
			out.append(b)
			if not details:
				return out
	return out


## Merges the groups (each an Array[Vector3i] of spots) that stand over each other, with
## LINK_OVERLAP cells or more of their footprints in common, and are linked by a navmesh path
## that stays within their footprint: the higher one's spots go into the lower one's group
## (the group merged away is left empty). Returns {group index: [{"foot", "top", "spots"}]}:
## each link's stair, from its path (the last point on the lower floor, the first on the upper).
static func _link_floors(map: RID, spots: Dictionary, groups: Array, now := 0.0, deadline := 0) -> Dictionary:
	var asked := 0  # navmesh paths asked this call (not kept in _climbs)
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
			if deadline > 0 and asked > 0 and Time.get_ticks_usec() >= deadline:
				_cut_short = true  # (the paths asked so far are kept: the next ask goes on)
				return {}
			var from := _spot_nearest(spots, groups[lo], info[hi].centre)
			var to := _spot_nearest(spots, groups[hi], info[lo].centre)
			var ckey := [from, to]
			var known: Array = _climbs.get(ckey, [])
			var stair: Dictionary
			if not known.is_empty() and now - float(known[0]) < CACHE_S:
				stair = known[1]
			else:
				asked += 1
				stair = _climb(map, spots, groups[lo], groups[hi], info[lo], info[hi])
				if _climbs.size() >= BUILT_MAX:
					_climbs.clear()
				_climbs[ckey] = [now, stair]
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


## Whether walkable spot `q` has walls round it (see the class notes). Under a roof (a hall,
## F-162) the walls may stand further off and one more way may be open (ROOF_UP_M).
static func inside(world: World3D, q: Vector3) -> bool:
	var eye := q + Vector3.UP * PROBE_HEIGHT
	var open: Array[int] = []
	for k in PROBE_DIRS:
		if not _wall_within(world, eye, _dir(k), PROBE_M):
			open.append(k)
			if open.size() > MAX_OPEN:
				return _hall_inside(world, q, eye)
	return not _opposite(open)


## A spot too open for inside(): inside a hall when it's roofed and the walls further off close
## it in (HALL_PROBE_M, HALL_MAX_OPEN).
static func _hall_inside(world: World3D, q: Vector3, eye: Vector3) -> bool:
	if not roofed(world, q):
		return false
	var open: Array[int] = []
	for k in PROBE_DIRS:
		if not _wall_within(world, eye, _dir(k), HALL_PROBE_M):
			open.append(k)
			if open.size() > HALL_MAX_OPEN:
				return false
	return not _opposite(open)


## Whether two of the open ways `open` are opposite (a gap between buildings).
static func _opposite(open: Array[int]) -> bool:
	for i in open:
		if (i + (PROBE_DIRS >> 1)) % PROBE_DIRS in open:
			return true
	return false


## Whether spot `q` has a roof straight over it within ROOF_UP_M: the underside of something.
static func roofed(world: World3D, q: Vector3) -> bool:
	var from := q + Vector3.UP * PROBE_HEIGHT
	var hit := world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * ROOF_UP_M, Throwables.WORLD_MASK))
	return not hit.is_empty() and (hit.normal as Vector3).y <= ROOF_NORMAL_Y


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


static func _building(world: World3D, spots: Dictionary, group: Array[Vector3i], joins: Dictionary, surfaces: Dictionary, climbs: Array = [], details := true) -> Dictionary:
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
	var entrances_started := Time.get_ticks_usec()
	b.entrances = _entrances(world, b, cells)
	FrameCost.spent(&"building_entrances", entrances_started)
	if b.entrances.is_empty():
		# The ground under it: the lowest surface over its cells within GROUND_DOWN_M under its
		# lowest floor (whatever the scan's height; see RAISED_M).
		var lowest_floor := float(floors[0].y)
		var low := INF
		for id in group:
			for y: float in surfaces.get(Vector2i(id.x, id.z), []):
				if y >= lowest_floor - GROUND_DOWN_M:
					low = minf(low, y)
					break
		if lowest_floor - low >= RAISED_M:
			return {}  # up on something with no way in: no building
	if not details:
		return b
	var started := Time.get_ticks_usec()
	for fi in range(1, floors.size()):
		floors[fi].roof = _open_sky(world, floors[fi].spots)
	b.ports = _ports(world, b, cells)
	FrameCost.spent(&"building_ports", started)
	started = Time.get_ticks_usec()
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
	FrameCost.spent(&"building_rooms", started)
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
