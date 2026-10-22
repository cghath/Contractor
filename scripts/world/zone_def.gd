class_name ZoneDef
extends RefCounted
## Zone definitions: everything a zone level (ZoneLevel) is built from, as a JSON-safe
## Dictionary so the host can send it to joining clients and the campaign can keep it:
##   "id", "name", "seed" (the terrain's), "size_m" (side of the square, a multiple of
##   SIZE_STEP_M), "relief_m" (hill height),
##   "modules": [{"id", "type" (ZoneModules.TYPES), "pos": [x, z]}] (snapped to GRID_M),
##   "insertion": [[x, z], ...] (where players can insert; the first is the default),
##   "extraction": [[x, z], ...] (extraction candidates).
##   "terrain" (a preset id from data/terrain_presets.json: the def's own, else chosen from its
##   "name" and "region"), "sea_side" and "sea_m" (normalize fills them in).
## Coordinates are metres from the zone's centre. Hand-made ones live in data/zones.json;
## generate() makes one from a seed (for contracts).

const PATH := "res://data/zones.json"
## The navigation grid (ZoneNav): module origins sit on its chunk centres.
const GRID_M := 12.0
## Zone sizes are whole terrain chunks (ZoneTerrain.CHUNK_CELLS * CELL_M).
const SIZE_STEP_M := 128.0
const MIN_SIZE_M := 512.0
## generate(): Proposed spacing between modules, distance kept from the edge, and how far
## insertion points stay from any module.
const MIN_SPACING_M := 260.0
const EDGE_KEEP_M := 200.0
const INSERTION_CLEAR_M := 350.0
## Hot zones (4B part 3, Captain 2026-10-12: 16 km², a 4096 m square; generate_hot). Proposed:
## how far the HQ sits from the centre at most, the ring round it the comms site and QRF bases
## sit in, how many of each kind, and how far insertion points keep from any site (out of
## sight of the nearest outpost).
const HOT_SIZE_M := 4096.0
const HOT_HQ_REACH_M := 600.0
const HOT_RING_M := Vector2(450.0, 1100.0)
const HOT_OUTPOSTS := Vector2i(3, 6)
const HOT_QRF_BASES := Vector2i(1, 2)
const HOT_CHECKPOINTS := Vector2i(2, 4)
const HOT_VILLAGES := Vector2i(2, 3)
## One of a hot zone's villages is a town instead (BuildingGen.town, "town#<seed>"): HOT_TOWNS.
const HOT_TOWNS := 1
## Urban hot zones (Captain, 2026-10-13: "add urban hotzones too"): URBAN_TOWNS towns packed
## round the HQ (URBAN_REACH_M), URBAN_SPACING_M apart (closer than other sites: districts of
## one city), a road from the HQ to each; the enemy patrols their streets. Villages on the
## outskirts: URBAN_VILLAGES.
const URBAN_TOWNS := Vector2i(3, 4)
const URBAN_REACH_M := Vector2(200.0, 900.0)
const URBAN_SPACING_M := 190.0
const URBAN_VILLAGES := Vector2i(1, 2)
const HOT_INSERTION_CLEAR_M := 700.0
const HOT_PATROLS := Vector2i(2, 4)
## A shoreline (_choose_sea) is at least this wide and keeps this far from any pad (m).
const SEA_MIN_M := 80.0
const SEA_PAD_KEEP_M := 60.0
## Captain, 2026-10-14 ("on foot exfils should only be possible at the edge zones"): the squad
## walks in and out only within Extraction.edge_reach of the edge, so generated insertion and
## extraction points stand EDGE_POINT_IN_M in from it, and normalize adds one there to a zone
## with none at the edge (_ensure_edge), EDGE_POINT_CLEAR_M clear of any module's footprint.
## Proposed.
const EDGE_POINT_IN_M := 45.0
const EDGE_POINT_CLEAR_M := 40.0

static var _defs := {}


## The definition named `id` in data/zones.json (normalized), or {} if there is none.
static func get_def(id: String) -> Dictionary:
	_load()
	return normalize(_defs[id]).merged({"id": id}, true) if _defs.has(id) else {}


static func ids() -> Array:
	_load()
	return _defs.keys()


static func _load() -> void:
	if not _defs.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) == TYPE_DICTIONARY:
		_defs = (data as Dictionary).get("zones", {})
	else:
		push_error("ZoneDef: cannot read %s" % PATH)


## A definition made safe to build from: size in whole chunks, module positions on the grid,
## unique module ids, known types only, at least one insertion point.
static func normalize(def: Dictionary) -> Dictionary:
	var out := def.duplicate(true)
	var size := maxf(ceilf(float(def.get("size_m", 1920.0)) / SIZE_STEP_M) * SIZE_STEP_M, MIN_SIZE_M)
	out["size_m"] = size
	out["seed"] = int(def.get("seed", 0))
	out["relief_m"] = float(def.get("relief_m", 18.0))
	out["id"] = String(def.get("id", "zone"))
	out["name"] = String(def.get("name", out.id))
	var half := size * 0.5
	var modules: Array = []
	var seen := {}
	for m: Dictionary in def.get("modules", []):
		var type := String(m.get("type", ""))
		var id := String(m.get("id", "%s_%d" % [type, modules.size()]))
		if not ZoneModules.has_type(type) or seen.has(id):
			push_warning("ZoneDef: skipping module %s (%s)" % [id, type])
			continue
		seen[id] = true
		var p: Array = m.get("pos", [0, 0])
		var keep := half - 60.0
		var x := clampf(snappedf(float(p[0]), GRID_M), -keep, keep)
		var z := clampf(snappedf(float(p[1]), GRID_M), -keep, keep)
		modules.append({"id": id, "type": type, "pos": [snappedf(x, GRID_M), snappedf(z, GRID_M)]})
	out["modules"] = modules
	for key in ["insertion", "extraction"]:
		var points: Array = []
		for p: Array in def.get(key, []):
			points.append([clampf(float(p[0]), -half + 20.0, half - 20.0), clampf(float(p[1]), -half + 20.0, half - 20.0)])
		out[key] = points
	if (out.insertion as Array).is_empty():
		out.insertion = [[0.0, half - 80.0]]
	out["grow"] = bool(def.get("grow", true))
	_grow(out, half)
	ZoneModules.place_landmarks(out)  # its landmarks by its asset tags (queue item 1.4; once: kept after)
	out["terrain"] = TerrainPresets.choose(out)
	_choose_sea(out)
	ZoneModules.place_harbour(out)  # a harbour on that sea (it stands in it: _choose_sea leaves it out)
	_ensure_edge(out, "insertion")
	_ensure_edge(out, "extraction")
	return out


## Captain, 2026-10-17 ("lets use the systems we already made to fill the zones up a bit better and
## make them feel a bit more alive"): each outpost, village and compound in `def` grows
## (ZoneModules.GROW: "<type>+<seed>", generated buildings round the hand-built core, the seed
## from the zone's and the module's id) when the bigger footprint stays GROW_KEEP_M clear of
## every other module and every insertion and extraction point, and GROW_EDGE_M inside the edge.
## A def with "grow": false keeps them as built (tests, hand layouts that want it).
const GROW_KEEP_M := 12.0
const GROW_EDGE_M := 60.0


static func _grow(def: Dictionary, half: float) -> void:
	if not bool(def.get("grow", true)):
		return
	var mods: Array = def.modules
	var rect_of := func(m: Dictionary) -> Rect2:
		var h: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		return Rect2(float(m.pos[0]) - h.x, float(m.pos[1]) - h.y, h.x * 2.0, h.y * 2.0)
	for m: Dictionary in mods:
		var type := String(m.type)
		if not ZoneModules.GROW.has(type):
			continue
		var grown := "%s%s%d" % [type, ZoneModules.GROWN, absi(hash([int(def.seed), String(m.id)])) % 1000000]
		if not ZoneModules.has_type(grown):
			continue
		var h: Vector2 = ZoneModules.HALF[grown]
		var r := Rect2(float(m.pos[0]) - h.x, float(m.pos[1]) - h.y, h.x * 2.0, h.y * 2.0)
		var keep := half - GROW_EDGE_M
		var fits := r.position.x >= -keep and r.position.y >= -keep and r.end.x <= keep and r.end.y <= keep
		var wide := r.grow(GROW_KEEP_M)
		for other: Dictionary in mods:
			if fits and other != m and wide.intersects(rect_of.call(other)):
				fits = false
		for key in ["insertion", "extraction"]:
			for pt: Array in def.get(key, []):
				if fits and wide.has_point(Vector2(float(pt[0]), float(pt[1]))):
					fits = false
		if fits:
			m.type = grown


## Captain, 2026-10-14: `def` (normalized, its sea chosen) gets a point of `key` ("insertion",
## "extraction") at the edge when none of its own is (Extraction.at_edge): EDGE_POINT_IN_M in
## from the side nearest its first point, not the sea's, slid along it clear of the modules.
## Added last: the default insertion (the first) stays.
static func _ensure_edge(def: Dictionary, key: String) -> void:
	var size := float(def.size_m)
	var half := size * 0.5
	var area := Rect2(-half, -half, size, size)
	var points: Array = def[key]
	for p: Array in points:
		if Extraction.at_edge(area, Vector2(float(p[0]), float(p[1]))):
			return
	var from := Vector2(float(points[0][0]), float(points[0][1])) if not points.is_empty() else Vector2.ZERO
	var pads: Array[Rect2] = []
	for m: Dictionary in def.modules:
		var h: Vector2 = ZoneModules.HALF.get(String(m.type), ZoneModules.HALF.get(ZoneModules.base(String(m.type)), Vector2(40, 40)))
		pads.append(Rect2(Vector2(float(m.pos[0]), float(m.pos[1])) - h, h * 2.0).grow(EDGE_POINT_CLEAR_M))
	var sea := int(def.get("sea_side", -1))
	var keep := half - maxf(EDGE_POINT_IN_M, float(def.get("sea_m", 0.0)) + SEA_PAD_KEEP_M if sea >= 0 else EDGE_POINT_IN_M)
	var inset := half - EDGE_POINT_IN_M
	# Sides (0 north -z, 1 south +z, 2 west -x, 3 east +x, as sea_side), nearest `from` first.
	var sides: Array = [0, 1, 2, 3].filter(func(side: int) -> bool: return side != sea)
	var gap := func(side: int) -> float: return [from.y + half, half - from.y, from.x + half, half - from.x][side]
	sides.sort_custom(func(a: int, b: int) -> bool: return gap.call(a) < gap.call(b))
	var first: Variant = null
	for side: int in sides:
		var along := from.x if side < 2 else from.y
		for slide: float in [0.0, 120.0, -120.0, 240.0, -240.0, 480.0, -480.0, 720.0, -720.0]:
			var a := clampf(along + slide, -keep, keep)
			var p: Vector2 = [Vector2(a, -inset), Vector2(a, inset), Vector2(-inset, a), Vector2(inset, a)][side]
			if first == null:
				first = p
			if not pads.any(func(r: Rect2) -> bool: return r.has_point(p)):
				points.append([snappedf(p.x, 1.0), snappedf(p.y, 1.0)])
				return
	if first != null:
		points.append([snappedf(first.x, 1.0), snappedf(first.y, 1.0)])


## The shoreline of a preset with a sea (TerrainPresets "sea"): a side picked by the seed from
## those where no module, insertion or extraction point would stand in the water. "sea_side"
## (0 north -z, 1 south +z, 2 west -x, 3 east +x; -1 = no sea) and "sea_m" (how far in from the
## edge the water reaches: shortened to keep clear of the nearest pad, SEA_MIN_M at least).
static func _choose_sea(def: Dictionary) -> void:
	def["sea_side"] = -1
	def["sea_m"] = 0.0
	var sea: Dictionary = TerrainPresets.get_preset(String(def.terrain)).get("sea", {})
	if sea.is_empty():
		return
	var half := float(def.size_m) * 0.5
	var pads: Array[Rect2] = []
	for m: Dictionary in def.modules:
		if ZoneModules.base(String(m.type)) == "harbour":
			continue  # (placed on the sea once it's chosen: ZoneModules.place_harbour)
		var h: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		pads.append(Rect2(p - h, h * 2.0))
	for key in ["extraction", "insertion"]:
		var r := 12.0 if key == "extraction" else 8.0
		for p: Array in def[key]:
			pads.append(Rect2(float(p[0]) - r, float(p[1]) - r, r * 2.0, r * 2.0))
	var width := float(sea.get("width_m", 180.0))
	var options: Array = []
	for side in 4:
		var clear := INF
		for r in pads:
			clear = minf(clear, [r.position.y + half, half - r.end.y, r.position.x + half, half - r.end.x][side])
		var reach := minf(width, clear - SEA_PAD_KEEP_M)
		if reach >= SEA_MIN_M:
			options.append([side, reach])
	if options.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(def.seed) ^ 0x5EA
	var pick: Array = options[rng.randi() % options.size()]
	def["sea_side"] = int(pick[0])
	def["sea_m"] = float(pick[1])


## A zone made from a seed: `count` modules of `types` spread over a `size_m` square, two
## insertion points near the edges clear of every module, three extraction candidates. The
## same seed gives the same zone. A "town" in `types` is a generated town ("town#<seed>", its
## seed from the zone's).
static func generate(seed: int, size_m := 1920.0, types: Array = ["compound", "outpost", "village", "checkpoint"], count := 5) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := maxf(ceilf(size_m / SIZE_STEP_M) * SIZE_STEP_M, MIN_SIZE_M)
	var half := size * 0.5
	var reach := half - EDGE_KEEP_M
	var placed: Array[Vector2] = []
	var modules: Array = []
	for attempt in 400:
		if modules.size() >= count:
			break
		var p := Vector2(snappedf(rng.randf_range(-reach, reach), GRID_M), snappedf(rng.randf_range(-reach, reach), GRID_M))
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < MIN_SPACING_M):
			continue
		placed.append(p)
		var type: String = types[modules.size() % types.size()]
		if type == "town":
			type = "%s%d" % [ZoneModules.TOWN, seed * 31 + modules.size()]
		modules.append({"id": "%s_%d" % [ZoneModules.base(type), modules.size()], "type": type, "pos": [p.x, p.y]})
	var edge_points := func(n: int) -> Array:
		var out: Array = []
		for attempt in 200:
			if out.size() >= n:
				break
			var side := rng.randi_range(0, 3)
			var along := rng.randf_range(-reach, reach)
			var inset := half - EDGE_POINT_IN_M  # Captain, 2026-10-14: at the edge, where the squad walks in and out
			var p: Vector2 = [Vector2(along, -inset), Vector2(along, inset), Vector2(-inset, along), Vector2(inset, along)][side]
			if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < INSERTION_CLEAR_M):
				continue
			out.append([snappedf(p.x, 1.0), snappedf(p.y, 1.0)])
		return out
	var def := normalize({"id": "generated_%d" % seed, "name": "Zone %d" % seed, "seed": seed, "size_m": size,
		"relief_m": 18.0, "modules": modules, "insertion": edge_points.call(2), "extraction": edge_points.call(3)})
	_add_roads_and_patrols(def, rng)
	return def


## Roads (a simple network: each site to its nearest already-connected one, so there is always a
## way between every site) and 1-2 roaming patrols (between neighbouring sites, skipping villages
## and towns: civilians, not patrol anchors) for a regular contract zone's modules. Captain,
## 2026-10-16: regular zones had neither (only hot zones did), so the enemy never patrolled and
## the zone never had roads to draw or drive on.
const TRAILS := 3
const TRAIL_POINTS := 5
const TRAIL_EDGE_SHARE := 0.85  # trails start and end this far out toward the edge (inside the wall)


static func _add_roads_and_patrols(def: Dictionary, rng: RandomNumberGenerator) -> void:
	var sites: Array[Vector2] = []
	for m: Dictionary in def.modules:
		sites.append(Vector2(m.pos[0], m.pos[1]))
	var roads: Array = []
	if sites.size() >= 2:
		var connected: Array[int] = [0]
		var remaining := range(1, sites.size())
		while not remaining.is_empty():
			var best_i := -1
			var best_j := -1
			var best_d := INF
			for i in connected:
				for j in remaining:
					var d: float = sites[i].distance_to(sites[j])
					if d < best_d:
						best_d = d
						best_i = i
						best_j = j
			roads.append([[sites[best_i].x, sites[best_i].y], [sites[best_j].x, sites[best_j].y]])
			connected.append(best_j)
			remaining.erase(best_j)
	var patrol_sites: Array = (def.modules as Array).filter(func(m: Dictionary) -> bool:
		return ZoneModules.base(m.type) != "village" and ZoneModules.base(m.type) != "town")
	var patrols: Array = []
	if patrol_sites.size() >= 3:
		for i in rng.randi_range(1, 2):
			var a: Dictionary = patrol_sites[rng.randi() % patrol_sites.size()]
			var pa := Vector2(a.pos[0], a.pos[1])
			var near: Array = patrol_sites.filter(func(m: Dictionary) -> bool: return m != a)
			near.sort_custom(func(m: Dictionary, n: Dictionary) -> bool:
				return pa.distance_to(Vector2(m.pos[0], m.pos[1])) < pa.distance_to(Vector2(n.pos[0], n.pos[1])))
			var route: Array = [[pa.x, pa.y]]
			for m: Dictionary in near.slice(0, 2):
				route.append([float(m.pos[0]), float(m.pos[1])])
			patrols.append(route)
	_add_trails(def, roads, patrols, rng)
	def["roads"] = roads
	def["patrols"] = patrols

## Trails right across the map (Captain, 2026-10-16: "paths that they patrol too, all across the
## map"): TRAILS of them, edge to edge through a jittered middle, added to `roads` (tracks) and
## `patrols` (a patrol walks each).
static func _add_trails(def: Dictionary, roads: Array, patrols: Array, rng: RandomNumberGenerator) -> void:
	var half := float(def.get("size_m", 1920.0)) * 0.5 * TRAIL_EDGE_SHARE
	for t in TRAILS:
		var a := rng.randf() * TAU
		var start := Vector2(cos(a), sin(a)) * half
		var finish := -start.rotated(rng.randf_range(-0.6, 0.6))
		var trail: Array = [[start.x, start.y]]
		for k in range(1, TRAIL_POINTS):
			var p := start.lerp(finish, float(k) / TRAIL_POINTS) + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * half * 0.25
			trail.append([p.x, p.y])
		trail.append([finish.x, finish.y])
		for k in range(1, trail.size()):
			roads.append([trail[k - 1], trail[k]])
		patrols.append(trail)



## A hot zone made from a seed (4B part 3): a `size_m` square (HOT_SIZE_M: 16 km²) holding the
## enemy's structure: one HQ near the centre; a comms site and HOT_QRF_BASES QRF bases in a
## ring round it; HOT_OUTPOSTS outposts spread out; HOT_CHECKPOINTS road checkpoints part way
## along the "roads" from the HQ to the outposts; HOT_VILLAGES villages (people live there),
## HOT_TOWNS of them generated towns ("town#<seed>", its seed from the zone's).
## Three insertion points at the edges, HOT_INSERTION_CLEAR_M from any site, the default (first)
## the one furthest from them; three extraction candidates; "roads" ([[x, z], [x, z]] pairs,
## HQ to each outpost) and "patrols" (routes, [[x, z], ...], between nearby sites) for the
## enemy's roaming patrols. "kind": "hot". The same seed gives the same zone. `urban`: an urban
## hot zone (URBAN_TOWNS; "urban": true).
static func generate_hot(seed: int, size_m := HOT_SIZE_M, urban := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := maxf(ceilf(size_m / SIZE_STEP_M) * SIZE_STEP_M, MIN_SIZE_M)
	var half := size * 0.5
	var reach := half - EDGE_KEEP_M
	var modules: Array = []
	var placed: Array[Vector2] = []
	var place := func(type: String, at: Vector2, spacing := MIN_SPACING_M) -> bool:
		var p := Vector2(snappedf(clampf(at.x, -reach, reach), GRID_M), snappedf(clampf(at.y, -reach, reach), GRID_M))
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < spacing):
			return false
		placed.append(p)
		modules.append({"id": "%s_%d" % [ZoneModules.base(type), modules.size()], "type": type, "pos": [p.x, p.y]})
		return true
	var around := func(type: String, centre: Vector2, ring: Vector2) -> Variant:
		for attempt in 200:
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(ring.x, ring.y)
			if place.call(type, p):
				return Vector2(modules.back().pos[0], modules.back().pos[1])
		return null
	var hq: Vector2 = around.call("hq", Vector2.ZERO, Vector2(0.0, HOT_HQ_REACH_M))
	around.call("comms", hq, HOT_RING_M)
	for i in rng.randi_range(HOT_QRF_BASES.x, HOT_QRF_BASES.y):
		around.call("qrf_base", hq, HOT_RING_M)
	var outposts: Array[Vector2] = []
	for i in rng.randi_range(HOT_OUTPOSTS.x, HOT_OUTPOSTS.y):
		var p: Variant = around.call("outpost", hq, Vector2(HOT_RING_M.y * 0.8, reach))
		if p != null:
			outposts.append(p)
	var roads: Array = []
	for p in outposts:
		roads.append([[hq.x, hq.y], [p.x, p.y]])
	if urban:
		for i in rng.randi_range(URBAN_TOWNS.x, URBAN_TOWNS.y):
			var type := "%s%d" % [ZoneModules.TOWN, seed * 31 + 100 + i]
			for attempt in 300:
				var at := hq + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(URBAN_REACH_M.x, URBAN_REACH_M.y)
				if place.call(type, at, URBAN_SPACING_M):
					roads.append([[hq.x, hq.y], [float(modules.back().pos[0]), float(modules.back().pos[1])]])
					break
	# Checkpoints part way along the roads (the first ones), off to the side a little.
	var checkpoints := rng.randi_range(HOT_CHECKPOINTS.x, HOT_CHECKPOINTS.y)
	var order := range(outposts.size())
	for i in order.size():
		if checkpoints <= 0:
			break
		var o: Vector2 = outposts[order[i]]
		for attempt in 20:
			var at := hq.lerp(o, rng.randf_range(0.4, 0.7)) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			if place.call("checkpoint", at):
				checkpoints -= 1
				break
	var villages := rng.randi_range(URBAN_VILLAGES.x, URBAN_VILLAGES.y) if urban else rng.randi_range(HOT_VILLAGES.x, HOT_VILLAGES.y)
	for i in villages:
		var type := "%s%d" % [ZoneModules.TOWN, seed * 31 + i] if i < HOT_TOWNS and not urban else "village"
		for attempt in 200:
			if place.call(type, Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))):
				break
	# Patrols walk between neighbouring sites: each from a site to its two nearest, and back.
	var patrols: Array = []
	var sites := modules.filter(func(m: Dictionary) -> bool:
		return ZoneModules.base(m.type) != "village" and (urban or ZoneModules.base(m.type) != "town"))
	for i in rng.randi_range(HOT_PATROLS.x, HOT_PATROLS.y):
		if sites.size() < 3:
			break
		var a: Dictionary = sites[rng.randi() % sites.size()]
		var pa := Vector2(a.pos[0], a.pos[1])
		var near := sites.filter(func(m: Dictionary) -> bool: return m != a)
		near.sort_custom(func(m: Dictionary, n: Dictionary) -> bool:
			return pa.distance_to(Vector2(m.pos[0], m.pos[1])) < pa.distance_to(Vector2(n.pos[0], n.pos[1])))
		var route: Array = [[pa.x, pa.y]]
		for m: Dictionary in near.slice(0, 2):
			route.append([float(m.pos[0]), float(m.pos[1])])
		patrols.append(route)
	var edge_points := func(n: int, clear: float) -> Array:
		var out: Array = []
		for attempt in 400:
			if out.size() >= n:
				break
			var side := rng.randi_range(0, 3)
			var along := rng.randf_range(-reach, reach)
			var inset := half - EDGE_POINT_IN_M  # Captain, 2026-10-14: at the edge, where the squad walks in and out
			var p: Vector2 = [Vector2(along, -inset), Vector2(along, inset), Vector2(-inset, along), Vector2(inset, along)][side]
			if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < clear):
				continue
			out.append([snappedf(p.x, 1.0), snappedf(p.y, 1.0)])
		return out
	var insertion: Array = edge_points.call(3, HOT_INSERTION_CLEAR_M)
	# The default insertion is the one furthest from every site.
	insertion.sort_custom(func(a: Array, b: Array) -> bool:
		return _clearance(Vector2(a[0], a[1]), placed) > _clearance(Vector2(b[0], b[1]), placed))
	var def := normalize({"id": "hot_%d" % seed, "name": "Hot zone %d" % seed, "seed": seed, "size_m": size,
		"relief_m": 24.0, "modules": modules, "insertion": insertion, "extraction": edge_points.call(3, INSERTION_CLEAR_M)})
	def["kind"] = "hot"
	if urban:
		def["urban"] = true
	_add_trails(def, roads, patrols, rng)
	def["roads"] = roads
	def["patrols"] = patrols
	return def


## How far `p` is from the nearest of `sites`.
static func _clearance(p: Vector2, sites: Array[Vector2]) -> float:
	var best := INF
	for q in sites:
		best = minf(best, p.distance_to(q))
	return best


## Captain, 2026-10-15 (coastal zone): the foot insertion sat on the shore a km from the target.
## Edge points (EDGE_POINT_IN_M in, so Extraction.at_edge) of a generated zone for a contract at
## `target` (x, z): on land (not the sea side, not the shoreline strip), outside every module's
## footprint grown by INSERT_CLEAR_M, nearest the INSERT_BAND_M walk to the target first. Returns
## [closer, safer] (Vector2; safer is further from the modules, INSERT_SPLIT_M or more from the
## closer), or one, or none. Proposed.
const INSERT_BAND_M := Vector2(300.0, 800.0)
const INSERT_CLEAR_M := 150.0
const INSERT_SPLIT_M := 150.0
const SHORE_KEEP_M := 40.0

static func insertion_options(def: Dictionary, target: Vector2) -> Array[Vector2]:
	var half := float(def.size_m) * 0.5
	var sea := int(def.get("sea_side", -1))
	var sea_m := float(def.get("sea_m", 0.0))
	var pads: Array[Rect2] = []
	for m: Dictionary in def.modules:
		var h: Vector2 = ZoneModules.HALF.get(String(m.type), ZoneModules.HALF.get(ZoneModules.base(String(m.type)), Vector2(40, 40)))
		pads.append(Rect2(Vector2(float(m.pos[0]), float(m.pos[1])) - h, h * 2.0))
	var inset := half - EDGE_POINT_IN_M
	var keep := half - (maxf(EDGE_POINT_IN_M, sea_m + SHORE_KEEP_M) if sea >= 0 else EDGE_POINT_IN_M)
	var cands: Array = []  # [point, distance to target, clearance from modules]
	for side in 4:
		if side == sea:
			continue
		var a := -keep
		while a <= keep:
			var p: Vector2 = [Vector2(a, -inset), Vector2(a, inset), Vector2(-inset, a), Vector2(inset, a)][side]
			a += 40.0
			if sea >= 0 and sea_m > 0.0:  # a side next to the sea: stay off its shoreline strip
				var depth: float = [p.y + half, half - p.y, p.x + half, half - p.x][sea]
				if depth < sea_m + SHORE_KEEP_M:
					continue
			var clear := INF
			for r in pads:
				clear = minf(clear, _rect_gap(r, p))
			if clear < INSERT_CLEAR_M:
				continue
			cands.append([p, p.distance_to(target), clear])
	var off := func(c: Array) -> float: return maxf(0.0, maxf(INSERT_BAND_M.x - float(c[1]), float(c[1]) - INSERT_BAND_M.y))
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var oa: float = off.call(a)
		var ob: float = off.call(b)
		return oa < ob if absf(oa - ob) > 1.0 else float(a[1]) < float(b[1]))
	var out: Array[Vector2] = []
	if cands.is_empty():
		return out
	var near: Array = cands[0]
	out.append(near[0])
	var safe: Variant = null
	for c: Array in cands:
		if (c[0] as Vector2).distance_to(near[0]) < INSERT_SPLIT_M or off.call(c) > off.call(near) + 250.0:
			continue
		if safe == null or float(c[2]) > float(safe[2]):
			safe = c
	if safe != null:
		out.append(safe[0])
	return out


static func _rect_gap(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)
