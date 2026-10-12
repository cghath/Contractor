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
const HOT_INSERTION_CLEAR_M := 700.0
const HOT_PATROLS := Vector2i(2, 4)
## A shoreline (_choose_sea) is at least this wide and keeps this far from any pad (m).
const SEA_MIN_M := 80.0
const SEA_PAD_KEEP_M := 60.0

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
	out["terrain"] = TerrainPresets.choose(out)
	_choose_sea(out)
	return out


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
## same seed gives the same zone.
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
		modules.append({"id": "%s_%d" % [type, modules.size()], "type": type, "pos": [p.x, p.y]})
	var edge_points := func(n: int) -> Array:
		var out: Array = []
		for attempt in 200:
			if out.size() >= n:
				break
			var side := rng.randi_range(0, 3)
			var along := rng.randf_range(-reach, reach)
			var inset := half - 90.0
			var p: Vector2 = [Vector2(along, -inset), Vector2(along, inset), Vector2(-inset, along), Vector2(inset, along)][side]
			if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < INSERTION_CLEAR_M):
				continue
			out.append([snappedf(p.x, 1.0), snappedf(p.y, 1.0)])
		return out
	return normalize({"id": "generated_%d" % seed, "name": "Zone %d" % seed, "seed": seed, "size_m": size,
		"relief_m": 18.0, "modules": modules, "insertion": edge_points.call(2), "extraction": edge_points.call(3)})


## A hot zone made from a seed (4B part 3): a `size_m` square (HOT_SIZE_M: 16 km²) holding the
## enemy's structure: one HQ near the centre; a comms site and HOT_QRF_BASES QRF bases in a
## ring round it; HOT_OUTPOSTS outposts spread out; HOT_CHECKPOINTS road checkpoints part way
## along the "roads" from the HQ to the outposts; HOT_VILLAGES villages (people live there).
## Three insertion points at the edges, HOT_INSERTION_CLEAR_M from any site, the default (first)
## the one furthest from them; three extraction candidates; "roads" ([[x, z], [x, z]] pairs,
## HQ to each outpost) and "patrols" (routes, [[x, z], ...], between nearby sites) for the
## enemy's roaming patrols. "kind": "hot". The same seed gives the same zone.
static func generate_hot(seed: int, size_m := HOT_SIZE_M) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := maxf(ceilf(size_m / SIZE_STEP_M) * SIZE_STEP_M, MIN_SIZE_M)
	var half := size * 0.5
	var reach := half - EDGE_KEEP_M
	var modules: Array = []
	var placed: Array[Vector2] = []
	var place := func(type: String, at: Vector2) -> bool:
		var p := Vector2(snappedf(clampf(at.x, -reach, reach), GRID_M), snappedf(clampf(at.y, -reach, reach), GRID_M))
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < MIN_SPACING_M):
			return false
		placed.append(p)
		modules.append({"id": "%s_%d" % [type, modules.size()], "type": type, "pos": [p.x, p.y]})
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
	for i in rng.randi_range(HOT_VILLAGES.x, HOT_VILLAGES.y):
		for attempt in 200:
			if place.call("village", Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))):
				break
	# Patrols walk between neighbouring sites: each from a site to its two nearest, and back.
	var patrols: Array = []
	var sites := modules.filter(func(m: Dictionary) -> bool: return m.type != "village")
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
			var inset := half - 90.0
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
	def["roads"] = roads
	def["patrols"] = patrols
	return def


## How far `p` is from the nearest of `sites`.
static func _clearance(p: Vector2, sites: Array[Vector2]) -> float:
	var best := INF
	for q in sites:
		best = minf(best, p.distance_to(q))
	return best
