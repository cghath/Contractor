class_name ZoneDef
extends RefCounted
## Zone definitions: everything a zone level (ZoneLevel) is built from, as a JSON-safe
## Dictionary so the host can send it to joining clients and the campaign can keep it:
##   "id", "name", "seed" (the terrain's), "size_m" (side of the square, a multiple of
##   SIZE_STEP_M), "relief_m" (hill height),
##   "modules": [{"id", "type" (ZoneModules.TYPES), "pos": [x, z]}] (snapped to GRID_M),
##   "insertion": [[x, z], ...] (where players can insert; the first is the default),
##   "extraction": [[x, z], ...] (extraction candidates).
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
	return out


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
