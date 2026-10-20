class_name ZoneModules
extends RefCounted
## The registry of hand-built combat spaces a zone places on its terrain (ZoneModule): what
## each module type is made of (voxel boxes, in metres from its origin on the ground), how big
## it is, its loot, its hostile garrison and its named points (where an objective, a cache or
## intel can go, for the mission registry). All built with the voxel API (VoxelWorld.add_box_m),
## so the art pack can replace a type's boxes in one place (boxes()).
##
## Module origins sit on the zone's 12 m navigation grid (ZoneNav), so chunk edges run 6 m
## from the origin and every 12 m after: doorways stay clear of those lines (as in the
## compound, whose edges are the same).

## Types: "compound" (the test compound, as CompoundLevel builds it), "outpost" (a HESCO
## ring with a bunker and a watchtower), "village" (four houses in mixed materials) and
## "checkpoint" (a road checkpoint: barriers, a booth, a sandbag nest). Hot zones (4B part 3)
## add "hq" (the enemy HQ: a HESCO-walled base with a command building, barracks and
## watchtowers), "qrf_base" (barracks and a vehicle shed: its QRF answers alarms) and "comms" (a
## radio mast on a steel lattice behind HESCO: destroyed, enemy reports slow down).
## "fob" is the company's own (BaseFob.module_boxes: the base zone, docs/linked_zones.md LZ-1): no
## garrison, loot or named points.
const TYPES: Array[String] = ["compound", "outpost", "village", "checkpoint", "hq", "qrf_base", "comms", "fob"]

## Half the footprint in metres (x, z): the pad under it and its voxel bounds.
## (Static vars, not consts: a generated town ("town#<seed>", BuildingGen.town) adds its own
## entries the first time it's asked for: _town.)
static var HALF := {
	"compound": Vector2(31.0, 31.0),  # the zone's own compound (_compound), 60 x 60 m inside (was the test compound's 40 x 40)
	"outpost": Vector2(11.0, 11.0),
	"village": Vector2(20.0, 14.0),
	"checkpoint": Vector2(14.0, 10.0),
	"hq": Vector2(22.0, 22.0),
	"qrf_base": Vector2(17.0, 13.0),
	"comms": Vector2(9.0, 9.0),
	"fob": BaseFob.MODULE_HALF,
}
## Voxel bounds reach this far above the ground (m) and this far below it.
const TOP_M := 4.8
## A generated town's own top (m; two storeys and a roof go higher than TOP_M).
static var TOP := {}
const BELOW_M := 0.8

## Named points (m from the origin, on the ground): "objective" (where a mission's target
## goes: an HVT room, a document table), "cache" (something to destroy or recover: the crate
## stack), "intel" and "aa" (the outpost's AA emplacement). The mission sites built on them
## are in data/contracts.json "modules" (MissionRegistry.site).
static var POINTS := {
	"compound": {"objective": [Vector3(0, 0, -8)], "cache": [Vector3(-12, 0, -9)], "intel": [Vector3(18, 0, -9)]},
	"outpost": {"objective": [Vector3(-5.5, 0, -6)], "cache": [Vector3(2.5, 0, -0.5)], "intel": [Vector3(-4.5, 0, -6.5)], "aa": [Vector3(-6, 0, 2.5)]},
	"village": {"objective": [Vector3(15.5, 0, -10)], "cache": [Vector3(-14.8, 0, 10.2)], "intel": [Vector3(1, 0, -9.5)]},
	"checkpoint": {"objective": [Vector3(9, 0, 5)], "cache": [Vector3(5.6, 0, 5.2)], "intel": [Vector3(9.2, 0, 4.6)]},
	"hq": {"objective": [Vector3(-11, 0, -12)], "cache": [Vector3(9, 0, 9)], "intel": [Vector3(-5, 0, -12.5)], "aa": [Vector3(-11, 0, 9)]},
	"qrf_base": {"objective": [Vector3(-8, 0, -6)], "cache": [Vector3(9, 0, 5)], "intel": [Vector3(-11, 0, -7)]},
	"comms": {"objective": [Vector3(-4.5, 0, -4.5)], "cache": [Vector3(2.1, 0, -3.4)], "intel": [Vector3(-4.5, 0, -4.5)], "comms": [Vector3(2.1, 0, -3.4)]},
}

## Hostile garrison (m from the origin): they hold where they stand (guards), in pairs.
static var GARRISON := {
	"compound": [Vector3(-2.5, 0.1, -10), Vector3(2.5, 0.1, -6.5), Vector3(-12, 0.1, -2), Vector3(-10, 0.1, -3)],
	"outpost": [Vector3(-5.5, 0.1, -6), Vector3(6, 0.1, -2), Vector3(-4, 0.1, 7.2), Vector3(4, 0.1, 7.2)],
	"village": [Vector3(-15, 0.1, -10), Vector3(1, 0.1, -10), Vector3(15.5, 0.1, -10), Vector3(-13.5, 0.1, 9)],
	"checkpoint": [Vector3(9, 0.1, 5), Vector3(-10, 0.1, 6.5), Vector3(2, 0.1, -5), Vector3(-2, 0.1, -5)],
	"hq": [Vector3(-11, 0.1, -12), Vector3(-5, 0.1, -12), Vector3(10, 0.1, -13), Vector3(12, 0.1, -12), Vector3(-3.4, 0.1, 15.0), Vector3(3.4, 0.1, 15.0),
		Vector3(-16.4, 3.2, 16.4), Vector3(16.4, 3.2, -16.4)],
	"qrf_base": [Vector3(-8, 0.1, -6), Vector3(-10, 0.1, -5), Vector3(6, 0.1, -5), Vector3(9, 0.1, -5), Vector3(-3, 0.1, 8), Vector3(3, 0.1, 8)],
	"comms": [Vector3(-4.5, 0.1, -4.5), Vector3(4, 0.1, 2), Vector3(-2.5, 0.1, 4.5), Vector3(2.5, 0.1, 4.5)],
}
## The way each GARRISON post looks out (module space; Vector3.ZERO, or a type not here: away
## from the module's middle, ZoneLevel.post_yaw). A town's posts at doors look onto the street,
## those up high (F-02: upper windows, roofs) out of their window or over their parapet.
static var GARRISON_FACE := {}
## A generated town's stair ramps for the navmesh (ramps()).
static var RAMPS := {}

## Loot lying in each module (m from the origin; uids are made unique per module). A static
## var: a town adds its own (_town).
static var LOOT := {
	"compound": [
		{"uid": "mags", "id": "mag_556", "count": 3, "pos": Vector3(-3, 0.5, -10)},
		{"uid": "ifak", "id": "ifak", "pos": Vector3(3, 0.5, -10)},
		{"uid": "case", "id": "hvt_case", "pos": Vector3(0, 0.5, -10)},
		{"uid": "salvage", "id": "electronics_salvage", "count": 4, "pos": Vector3(18, 0.5, -9)},
	],
	"outpost": [
		{"uid": "rounds", "id": "rounds_556", "count": 60, "pos": Vector3(2.5, 0.5, -2.5)},
		{"uid": "frags", "id": "frag_grenade", "count": 2, "pos": Vector3(-5, 0.5, -7)},
		{"uid": "salvage", "id": "electronics_salvage", "count": 3, "pos": Vector3(-4.5, 0.5, -6.5)},
	],
	"village": [
		{"uid": "ifak", "id": "ifak", "pos": Vector3(1, 0.5, -9.5)},
		{"uid": "mags", "id": "mag_556", "count": 2, "pos": Vector3(-15, 0.5, -9)},
		{"uid": "salvage", "id": "electronics_salvage", "count": 2, "pos": Vector3(15.5, 0.5, -11)},
	],
	"checkpoint": [
		{"uid": "rounds", "id": "rounds_762", "count": 40, "pos": Vector3(-10, 0.5, 7)},
		{"uid": "smoke", "id": "smoke_grenade", "count": 2, "pos": Vector3(9, 0.5, 5.2)},
	],
	"hq": [
		{"uid": "mags", "id": "mag_556", "count": 4, "pos": Vector3(-12, 0.5, -13)},
		{"uid": "rounds", "id": "rounds_762", "count": 60, "pos": Vector3(10, 0.5, -14)},
		{"uid": "ifak", "id": "ifak", "pos": Vector3(12, 0.5, -14)},
		{"uid": "frags", "id": "frag_grenade", "count": 3, "pos": Vector3(-4, 0.5, -14)},
		{"uid": "salvage", "id": "electronics_salvage", "count": 5, "pos": Vector3(-6, 0.5, -14)},
	],
	"qrf_base": [
		{"uid": "rounds", "id": "rounds_556", "count": 90, "pos": Vector3(-11, 0.5, -7.5)},
		{"uid": "smoke", "id": "smoke_grenade", "count": 3, "pos": Vector3(-6, 0.5, -7.5)},
		{"uid": "ifak", "id": "ifak", "pos": Vector3(-9, 0.5, -7.5)},
	],
	"comms": [
		{"uid": "salvage", "id": "electronics_salvage", "count": 6, "pos": Vector3(-4.5, 0.5, -5)},
	],
}

static var _cache := {}
static var _counts := {}  # solid_voxels_in


## A module type's base type: "town" for a generated town ("town#<seed>"), else the type. The
## mission data (contracts.json "modules"), callsigns and the like are by base type.
static func base(type: String) -> String:
	if type.begins_with(TOWN):
		return "town"
	return type.get_slice(GROWN, 0) if GROWN in type else type


## A generated town's civilians (BuildingGen.town "civilians"); none for other types (theirs
## are in contracts.json).
static func civilians(type: String) -> Array:
	return (_towns.get(type, {}) as Dictionary).get("civilians", []) if has_type(type) else []


## A generated town's contract sites (contracts.json "modules" sites, made from its buildings):
## "area" (the whole town), "intel" and "docs" (its intel spots), "hvt" (+ "hvt_phone"),
## "hostage" and "cache" (the weapons cache, its voxels counted) (BuildingGen.town). {} for other
## types.
static func town_sites(type: String) -> Dictionary:
	if not type.begins_with(TOWN) or not has_type(type):
		return {}
	var t: Dictionary = _towns[type]
	var half: Vector2 = t.half
	var arr := func(p: Vector3) -> Array: return [p.x, p.y, p.z]
	var intel: Array = t.points.intel
	var hvt: Vector3 = t.hvt
	return {
		"area": {"rect": [-half.x, -half.y, half.x * 2.0, half.y * 2.0]},
		"intel": {"pos": arr.call((intel[0] as Vector3) + Vector3(0, 0.5, 0)), "place": "intel_laptop", "name": "laptop"},
		"docs": {"pos": arr.call((intel[intel.size() - 1] as Vector3) + Vector3(0.6, 0.5, 0)), "place": "intel_documents", "name": "documents"},
		"hvt": {"pos": arr.call(hvt), "hvt": "hvt_town", "person": {"side": "hostile", "intel": ["intel_phone"]}},
		"hvt_phone": {"pos": arr.call(hvt), "items": ["intel_phone"], "of_hvt": "hvt"},
		"hostage": {"pos": arr.call(t.hostage), "hvt": "hostage_town", "person": {"side": "friendly"}},
		"cache": {"box": [arr.call(t.cache[0]), arr.call(t.cache[1])], "cache": "cache_town", "name": "weapons cache", "voxels": "auto"},
	}


static var _towns := {}


## A generated town's reserve: its garrison post indices (UrbanDefence); [] for other types.
static func town_reserve(type: String) -> Array:
	return (_towns.get(type, {}) as Dictionary).get("reserve", []) if type.begins_with(TOWN) and has_type(type) else []


## A generated town's fallback points (every building's back room, m from the origin; UrbanDefence).
static func town_fallback(type: String) -> Array:
	return (_towns.get(type, {}) as Dictionary).get("fallback", []) if type.begins_with(TOWN) and has_type(type) else []


static func has_type(type: String) -> bool:
	if type.begins_with("fob_") and BaseFob.DEFENCES.has(type.trim_prefix("fob_")):
		var d: Dictionary = BaseFob.DEFENCES[type.trim_prefix("fob_")]
		HALF[type] = Vector2(float(d.half[0]), float(d.half[1]))  # a bought defence (BaseFob, LZ-6)
		return true
	if type.begins_with(TOWN):
		return _town(type)
	if GROWN in type:
		return _grown(type)
	return type in TYPES


## Generated towns (docs/building_gen.md): "town#<seed>". Builds it once (BuildingGen.town) and
## enters its boxes, footprint, named points and garrison under that type. False for a bad seed.
const TOWN := "town#"


static func _town(type: String) -> bool:
	if _cache.has(type):
		return true
	var seed_text := type.substr(TOWN.length())
	if not seed_text.is_valid_int():
		return false
	var t := BuildingGen.town(int(seed_text))
	_cache[type] = t.boxes
	HALF[type] = t.half
	POINTS[type] = t.points
	GARRISON[type] = t.garrison
	GARRISON_FACE[type] = t.garrison_face
	RAMPS[type] = t.ramps
	LOOT[type] = t.loot
	var top := TOP_M
	for bx: Array in t.boxes:
		top = maxf(top, (bx[1] as Vector3).y + 0.5)
	TOP[type] = top
	_towns[type] = {"civilians": t.civilians, "half": t.half, "points": t.points, "hvt": t.hvt, "hostage": t.hostage, "cache": t.cache,
		"reserve": t.garrison_reserve, "fallback": t.fallback}
	return true


## Grown modules (Captain, 2026-10-17: "2 or 3 new buildings for the outposts, then enlargify
## the really small villages to varying extents", "compounds should be a little larger"):
## "<type>+<seed>" for a type in GROW is the hand-built module with generated buildings
## (BuildingGen.building) in rows north and south of it, fronts facing it, GROW_GAP_M off its
## footprint. Each brings a garrison post inside its front door, loot by its rooms
## (BuildingGen.TOWN_LOOT) and its stair ramps; the footprint grows to fit. Mission data,
## callsigns and the rest go by the base type (base()). ZoneDef.normalize grows modules
## where there's room.
const GROWN := "+"
const GROW := {
	"outpost": {"count": [2, 3], "types": ["warehouse", "house", "police"]},
	"village": {"count": [1, 6], "types": ["house", "house", "house", "shop"]},
	# (A compound grows none: Captain, 2026-10-18, "there shouldnt be houses around them typically".)
}
const GROW_GAP_M := 3.0
const GROW_LOOT_MAX := 6


static func _grown(type: String) -> bool:
	if _cache.has(type):
		return true
	var core := type.get_slice(GROWN, 0)
	var seed_text := type.get_slice(GROWN, 1)
	if not GROW.has(core) or not seed_text.is_valid_int():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_text)
	var spec: Dictionary = GROW[core]
	var core_half: Vector2 = HALF[core]
	var out: Array = (boxes(core) as Array).duplicate()
	var garrison: Array = (GARRISON.get(core, []) as Array).duplicate()
	var face: Array = []
	for i in garrison.size():
		face.append(Vector3.ZERO)
	var loot: Array = (LOOT.get(core, []) as Array).duplicate(true)
	var ramps := PackedVector3Array()
	var rows := [[], []]  # north (-z, as built: front to +z, toward the core), south (turned)
	var count := rng.randi_range(int(spec.count[0]), int(spec.count[1]))
	for k in count:
		var b := BuildingGen.building(spec.types[rng.randi() % spec.types.size()], int(seed_text) * 131 + k)
		rows[k % 2].append(b)
	var half := core_half
	var top := TOP_M
	for side in 2:
		var row: Array = rows[side]
		var width := 0.0
		for b: Dictionary in row:
			width += (b.size as Vector2).x + BuildingGen.LOT_GAP
		var cursor := -width * 0.5
		var turned := side == 1
		for b: Dictionary in row:
			var size: Vector2 = b.size
			var z := (core_half.y + GROW_GAP_M + size.y * 0.5) * (1.0 if turned else -1.0)
			var origin := Vector3(cursor + size.x * 0.5, 0, z)
			cursor += size.x + BuildingGen.LOT_GAP
			var place := func(p: Vector3) -> Vector3: return (Vector3(-p.x, p.y, -p.z) if turned else p) + origin
			for bx: Array in b.boxes:
				var a: Vector3 = place.call(bx[0])
				var c: Vector3 = place.call(bx[1])
				out.append([a.min(c), a.max(c), bx[2]])
				top = maxf(top, maxf(a.y, c.y) + 0.5)
			for f: Vector3 in BuildingGen.ramp_faces(b):
				ramps.append(place.call(f))
			for dr: Dictionary in b.doors:
				if int(dr.rooms[1]) == -1:
					garrison.append(place.call((dr.at as Vector3) + Vector3(0, 0.1, -1.0)))  # just inside the front door
					face.append(Vector3.ZERO)
					break
			for l: Dictionary in b.loot:
				if BuildingGen.TOWN_LOOT.has(l.table) and loot.size() < (LOOT.get(core, []) as Array).size() + GROW_LOOT_MAX:
					var choices: Array = BuildingGen.TOWN_LOOT[l.table]
					var pick: Array = choices[rng.randi() % choices.size()]
					loot.append({"uid": "grown%d" % loot.size(), "id": pick[0], "count": int(pick[1]), "pos": place.call(l.at) + Vector3(0, 0.5, 0)})
			half = Vector2(maxf(half.x, absf(origin.x) + size.x * 0.5 + 1.0), maxf(half.y, absf(z) + size.y * 0.5 + 1.0))
	_cache[type] = out
	HALF[type] = half
	POINTS[type] = POINTS[core]
	GARRISON[type] = garrison
	GARRISON_FACE[type] = face
	RAMPS[type] = ramps
	LOOT[type] = loot
	TOP[type] = top
	return true


## The module's base structure: [from (Vector3, m), to (Vector3, m), VoxelWorld.Mat] boxes,
## in the order they are built.
static func boxes(type: String) -> Array:
	if not _cache.has(type):
		match type:
			"compound":
				_cache[type] = _compound()
			"outpost":
				_cache[type] = _outpost()
			"village":
				_cache[type] = _village()
			"checkpoint":
				_cache[type] = _checkpoint()
			"hq":
				_cache[type] = _hq()
			"qrf_base":
				_cache[type] = _qrf_base()
			"comms":
				_cache[type] = _comms()
			"fob":
				_cache[type] = BaseFob.module_boxes()
			_ when type.begins_with("fob_") and has_type(type):
				_cache[type] = BaseFob.defence_boxes(type.trim_prefix("fob_"))
			_ when type.begins_with(TOWN) and _town(type):
				pass
			_ when GROWN in type and _grown(type):
				pass
			_:
				push_error("ZoneModules: unknown type %s" % type)
				return []
	return _cache[type]


## The ramps over the module's stairs for the navmesh bake (BuildingGen.ramp_faces: triangles,
## m from the origin; a generated town's), empty for a type without stairs.
static func ramps(type: String) -> PackedVector3Array:
	if type.begins_with(TOWN) or GROWN in type:
		boxes(type)  # builds the town (or grown module) once
	return RAMPS.get(type, PackedVector3Array())


## The base structure as AABBs in metres from the origin, snapped to the voxels as
## VoxelWorld.add_box_m snaps them (for proxies and navigation while it's not loaded).
static func boxes_m(type: String) -> Array[AABB]:
	var out: Array[AABB] = []
	for b: Array in boxes(type):
		var a := ((b[0] as Vector3) / VoxelWorld.VOXEL_SIZE).round() * VoxelWorld.VOXEL_SIZE
		var c := ((b[1] as Vector3) / VoxelWorld.VOXEL_SIZE).round() * VoxelWorld.VOXEL_SIZE
		out.append(AABB(a.min(c), (a - c).abs()))
	return out


## The voxel world's bounds for a type (voxels, from the origin).
static func bounds_voxels(type: String) -> AABB:
	var half: Vector2 = HALF.get(type, Vector2(20, 20))
	var s := VoxelWorld.VOXEL_SIZE
	var lo := Vector3(-half.x - 1.0, -BELOW_M, -half.y - 1.0) / s
	var hi := Vector3(half.x + 1.0, float(TOP.get(type, TOP_M)), half.y + 1.0) / s
	return AABB(lo.round(), (hi - lo).round())


static func points(type: String, kind: String) -> Array:
	return (POINTS.get(type, {}) as Dictionary).get(kind, [])


# --- The placeholder modules -------------------------------------------------------------------

## A walled room: walls `t` thick from `a` to `b` (x, z corners), `h` tall, in `mat`, with
## doorway gaps: each [side ("n", "s", "w", "e"), from, to] along that wall (x for n/s, z for
## w/e), 2.1 m tall with wall over them. Optionally a roof `roof_t` thick in `roof_mat`.
static func _room(out: Array, a: Vector2, b: Vector2, h: float, t: float, mat: int, doors: Array, roof_mat := -1, roof_t := 0.2, windows: Array = []) -> void:
	var sides := {
		"n": [Vector3(a.x, 0, a.y), Vector3(b.x, h, a.y + t), 0],
		"s": [Vector3(a.x, 0, b.y - t), Vector3(b.x, h, b.y), 0],
		"w": [Vector3(a.x, 0, a.y + t), Vector3(a.x + t, h, b.y - t), 2],
		"e": [Vector3(b.x - t, 0, a.y + t), Vector3(b.x, h, b.y - t), 2],
	}
	for side: String in sides:
		var s: Array = sides[side]
		var lo: Vector3 = s[0]
		var hi: Vector3 = s[1]
		var axis: int = s[2]
		var gaps: Array = []
		for d: Array in doors:
			if d[0] == side:
				gaps.append([float(d[1]), float(d[2]), 0.0, 2.1])
		for w: Array in windows:
			if w[0] == side:
				gaps.append([float(w[1]), float(w[2]), 1.0, 1.7])
		gaps.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var at := lo[axis]
		for g: Array in gaps:
			if g[0] > at:
				out.append([_with(lo, axis, at), _with(hi, axis, g[0]), mat])
			# Below the gap (a window's sill) and above it (the lintel).
			if g[2] > 0.0:
				out.append([_with(lo, axis, g[0]), _with(Vector3(hi.x, g[2], hi.z), axis, g[1]), mat])
			out.append([_with(Vector3(lo.x, g[3], lo.z), axis, g[0]), _with(hi, axis, g[1]), mat])
			at = g[1]
		if at < hi[axis]:
			out.append([_with(lo, axis, at), hi, mat])
	if roof_mat >= 0:
		out.append([Vector3(a.x, h, a.y), Vector3(b.x, h + roof_t, b.y), roof_mat])


static func _with(v: Vector3, axis: int, value: float) -> Vector3:
	v[axis] = value
	return v


## A small outpost: a HESCO ring 20 m across with a gap to the south, a concrete bunker with
## a roof, a wooden watchtower, sandbag positions by the entrance and a stack of crates.
static func _outpost() -> Array:
	var out: Array = []
	var H := VoxelWorld.Mat.HESCO
	out.append([Vector3(-10, 0, -10), Vector3(10, 2.0, -9), H])
	out.append([Vector3(-10, 0, -9), Vector3(-9, 2.0, 10), H])
	out.append([Vector3(9, 0, -9), Vector3(10, 2.0, 10), H])
	out.append([Vector3(-9, 0, 9), Vector3(-1.5, 2.0, 10), H])
	out.append([Vector3(1.5, 0, 9), Vector3(9, 2.0, 10), H])
	# Bunker, 5 x 4 m, door to the south.
	_room(out, Vector2(-8, -8), Vector2(-3, -4), 2.2, 0.3, VoxelWorld.Mat.CONCRETE, [["s", -5.4, -4.2]], VoxelWorld.Mat.CONCRETE, 0.3)
	# Watchtower: four posts and a plank floor with a sandbag parapet.
	var W := VoxelWorld.Mat.WOOD
	for p: Vector2 in [Vector2(4.6, -7.6), Vector2(7.2, -7.6), Vector2(4.6, -5.0), Vector2(7.2, -5.0)]:
		out.append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.2, 3.0, p.y + 0.2), W])
	out.append([Vector3(4.6, 3.0, -7.6), Vector3(7.4, 3.1, -4.8), W])
	out.append([Vector3(4.6, 3.1, -7.6), Vector3(7.4, 3.8, -7.3), VoxelWorld.Mat.SANDBAG])
	# Sandbag positions either side of the entrance, and crates.
	out.append([Vector3(-5.5, 0, 5.6), Vector3(-2.5, 1.1, 6.0), VoxelWorld.Mat.SANDBAG])
	out.append([Vector3(2.5, 0, 5.6), Vector3(5.5, 1.1, 6.0), VoxelWorld.Mat.SANDBAG])
	out.append([Vector3(1.5, 0, -2.2), Vector3(3.5, 1.0, -1.2), W])
	out.append([Vector3(2.0, 1.0, -2.2), Vector3(3.0, 2.0, -1.2), W])
	# An AA emplacement in the west yard (a raid target): a low sandbag ring round a twin-barrel
	# gun on a steel mount. Steel shrugs off grenades: it takes a placed charge.
	_aa_site(out, Vector2(-6.0, 2.5))
	return out


## A village block: four houses in mixed materials (mud brick, cinder block with a sheet-metal
## roof, a two-room brick house, a plank shack), with doors and windows, and a low stone yard
## wall.
static func _village() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	_room(out, Vector2(-18, -12), Vector2(-12, -7), 2.6, 0.4, M.MUD_BRICK, [["s", -15.6, -14.4]], M.WOOD, 0.2,
		[["w", -10.5, -9.5], ["e", -10.5, -9.5]])
	_room(out, Vector2(-2, -12), Vector2(4, -7), 2.6, 0.2, M.CINDER_BLOCK, [["s", 0.4, 1.6]], M.SHEET_METAL, 0.1,
		[["n", -0.5, 0.5], ["e", -10.5, -9.5]])
	# The brick house: two rooms, a doorway between them.
	_room(out, Vector2(9, -13), Vector2(17, -7), 2.8, 0.25, M.BRICK, [["s", 10.4, 11.6]], M.CONCRETE, 0.2,
		[["n", 14.5, 15.5], ["e", -10.5, -9.5]])
	out.append([Vector3(12.9, 0, -12.75), Vector3(13.1, 2.8, -10.6), M.BRICK])
	out.append([Vector3(12.9, 0, -9.4), Vector3(13.1, 2.8, -7.25), M.BRICK])
	out.append([Vector3(12.9, 2.1, -10.6), Vector3(13.1, 2.8, -9.4), M.BRICK])
	_room(out, Vector2(-16, 7), Vector2(-11, 11), 2.3, 0.1, M.WOOD, [["e", 8.4, 9.6]], M.SHEET_METAL, 0.1,
		[["n", -14.5, -13.5]])
	out.append([Vector3(-9, 0, 1.8), Vector3(-3, 1.2, 2.2), M.STONE])
	# A weapons cache in the plank shack (a raid target): three crates against its back wall.
	_crates(out, Vector3(-15.8, 0, 9.6))
	return out


## A road checkpoint on an east-west road: staggered concrete barriers, a sheet-metal guard
## booth, a sandbag nest and a wooden barrier pole.
static func _checkpoint() -> Array:
	var out: Array = []
	var C := VoxelWorld.Mat.CONCRETE
	out.append([Vector3(-9, 0, -3), Vector3(-6.5, 0.9, -2.4), C])
	out.append([Vector3(-2.5, 0, 2.4), Vector3(0, 0.9, 3), C])
	out.append([Vector3(3.5, 0, -3), Vector3(6, 0.9, -2.4), C])
	_room(out, Vector2(8, 4), Vector2(10.2, 6.2), 2.4, 0.1, VoxelWorld.Mat.SHEET_METAL, [["w", 4.6, 5.4]], VoxelWorld.Mat.SHEET_METAL, 0.1,
		[["s", 8.6, 9.6], ["e", 4.6, 5.4]])
	var S := VoxelWorld.Mat.SANDBAG
	out.append([Vector3(-12, 0, 8), Vector3(-8, 1.1, 8.5), S])
	out.append([Vector3(-12, 0, 5), Vector3(-11.5, 1.1, 8), S])
	out.append([Vector3(-8.5, 0, 5), Vector3(-8, 1.1, 8), S])
	out.append([Vector3(1, 0.9, -0.1), Vector3(7, 1.05, 0.05), VoxelWorld.Mat.WOOD])
	out.append([Vector3(7, 0, -0.2), Vector3(7.3, 1.1, 0.1), VoxelWorld.Mat.WOOD])
	# A weapons cache by the booth (a raid target).
	_crates(out, Vector3(4.6, 0, 4.6))
	return out


## The enemy HQ (hot zones): a HESCO wall 40 m square with a gate to the south, a concrete
## command building (two rooms: the commander's office and the radio room with the intel),
## a plank barracks, watchtowers at two corners, sandbags at the gate, a weapons cache in the
## east yard and an AA site in the west yard.
## A militia compound (zones; the test level keeps CompoundLevel.structure_boxes). Captain,
## 2026-10-18: "further improve the compounds, there shouldnt be houses around them typically.
## and the interior should make sense, maybe a small barracks tent, a small armory tent, a
## generator or two etc", "make them a bit bigger too, theyre way small". A 60 x 60 m mud-brick
## perimeter (gate south, sandbags covering it), watchtowers on two corners, the command building
## in the middle (the objective), a barracks tent with cots and an armory tent with weapon racks
## (tarp over wooden frames), the store shed (intel) and supply crates (the cache), two
## generators and their fuel drums, a shipping container, and low walls to fight from. The
## mission spots (SITES, GARRISON, LOOT) stand where the test compound had them, all inside.
static func _compound() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var B := M.MUD_BRICK
	var h := 30.0
	var t := 0.6
	out.append([Vector3(-h, 0, -h), Vector3(h, 2.6, -h + t), B])
	out.append([Vector3(-h, 0, -h + t), Vector3(-h + t, 2.6, h), B])
	out.append([Vector3(h - t, 0, -h + t), Vector3(h, 2.6, h), B])
	out.append([Vector3(-h + t, 0, h - t), Vector3(-2.5, 2.6, h), B])
	out.append([Vector3(2.5, 0, h - t), Vector3(h - t, 2.6, h), B])
	_tower(out, Vector2(25.2, -27.6), ["n", "e"])
	_tower(out, Vector2(-27.6, 25.2), ["s", "w"])
	out.append([Vector3(-6.5, 0, 25.4), Vector3(-3.5, 1.1, 25.9), M.SANDBAG])  # covering the gate
	out.append([Vector3(3.5, 0, 25.4), Vector3(6.5, 1.1, 25.9), M.SANDBAG])
	# The command building, 10 x 8 m (as the test compound's: the objective is in it).
	var P := M.PAINTED
	var w := 0.3
	out.append([Vector3(-5, 0, -12), Vector3(5, 3, -12 + w), P])
	out.append([Vector3(-5, 0, -12), Vector3(-5 + w, 3, -4), P])
	out.append([Vector3(5 - w, 0, -12), Vector3(5, 3, -4), P])
	out.append([Vector3(-5, 0, -4 - w), Vector3(-0.6, 3, -4), P])
	out.append([Vector3(0.6, 0, -4 - w), Vector3(5, 3, -4), P])
	out.append([Vector3(-0.6, 2.2, -4 - w), Vector3(0.6, 3, -4), P])
	out.append([Vector3(-5, 3, -12), Vector3(5, 3.2, -4), M.CONCRETE])  # its roof
	# Barracks tent, 10 x 6 m (north-west): tarp walls and roof on a frame, a door south, cots.
	_room(out, Vector2(-24, -24), Vector2(-14, -18), 2.2, 0.1, M.TARP, [["s", -19.6, -18.4]], M.TARP, 0.1)
	for k in 4:
		var x := -23.2 + k * 2.3
		out.append([Vector3(x, 0, -23.4), Vector3(x + 0.8, 0.45, -21.5), M.WOOD])
	# Armory tent, 6 x 5 m (north-east): weapon racks along the back, ammo crates.
	_room(out, Vector2(8, -24), Vector2(14, -19), 2.2, 0.1, M.TARP, [["s", 10.4, 11.6]], M.TARP, 0.1)
	out.append([Vector3(8.4, 0, -23.7), Vector3(13.6, 1.6, -23.4), M.WOOD])
	out.append([Vector3(8.4, 0, -22.4), Vector3(9.6, 0.6, -21.6), M.WOOD])
	out.append([Vector3(12.4, 0, -22.4), Vector3(13.6, 0.6, -21.6), M.WOOD])
	# The store shed (intel) and the supply crates (the cache), as the test compound's.
	var W := M.WOOD
	out.append([Vector3(-13, 0, -11), Vector3(-12, 1, -10), W])
	out.append([Vector3(-12, 0, -11), Vector3(-11, 1, -10), W])
	out.append([Vector3(-12.5, 1, -11), Vector3(-11.5, 2, -10), W])
	for box: Array in CompoundLevel.SHED:
		out.append([box[0], box[1], W if box[2] == "wood" else M.SHEET_METAL])
	# Two generators and their fuel drums (east), a shipping container (west).
	for gx: float in [10.0, 12.6]:
		out.append([Vector3(gx, 0, 6.0), Vector3(gx + 1.4, 1.0, 6.9), M.STEEL])
		out.append([Vector3(gx + 0.5, 1.0, 6.2), Vector3(gx + 0.7, 1.5, 6.4), M.STEEL])  # its exhaust
	for d: Vector2 in [Vector2(15.4, 6.0), Vector2(16.2, 6.0), Vector2(15.8, 6.8)]:
		out.append([Vector3(d.x, 0, d.y), Vector3(d.x + 0.6, 0.9, d.y + 0.6), M.STEEL])
	for box: Array in CompoundLevel.CONTAINER:
		out.append([box[0], box[1], M.SHEET_METAL])
	# Low walls to fight from (the test compound's), and sandbag positions by the towers.
	out.append([Vector3(-9, 0, 6), Vector3(-6, 1.1, 6.4), M.SANDBAG])
	out.append([Vector3(6, 0, 3), Vector3(9, 1.1, 3.4), M.CONCRETE])
	out.append([Vector3(-1.5, 0, 10), Vector3(1.5, 1.1, 10.4), M.CONCRETE])
	out.append([Vector3(20, 0, -24), Vector3(23, 1.1, -23.5), M.SANDBAG])
	out.append([Vector3(-24, 0, 20), Vector3(-23.5, 1.1, 23), M.SANDBAG])
	return out


static func _hq() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var H := M.HESCO
	out.append([Vector3(-20, 0, -20), Vector3(20, 2.2, -19), H])
	out.append([Vector3(-20, 0, -19), Vector3(-19, 2.2, 20), H])
	out.append([Vector3(19, 0, -19), Vector3(20, 2.2, 20), H])
	out.append([Vector3(-19, 0, 19), Vector3(-2.0, 2.2, 20), H])
	out.append([Vector3(2.0, 0, 19), Vector3(19, 2.2, 20), H])
	# Command building, 13 x 7 m: office (west) and radio room (east), a doorway between.
	_room(out, Vector2(-15, -16), Vector2(-2, -9), 2.8, 0.3, M.CONCRETE, [["s", -12.6, -11.4], ["s", -5.6, -4.4]], M.CONCRETE, 0.3,
		[["n", -10.5, -9.5], ["e", -14.5, -13.5]])
	out.append([Vector3(-8.65, 0, -15.7), Vector3(-8.35, 2.8, -13.1), M.CONCRETE])
	out.append([Vector3(-8.65, 0, -11.9), Vector3(-8.35, 2.8, -9.3), M.CONCRETE])
	out.append([Vector3(-8.65, 2.1, -13.1), Vector3(-8.35, 2.8, -11.9), M.CONCRETE])
	# Barracks, 10 x 5 m, plank walls and a sheet-metal roof.
	_room(out, Vector2(4, -16), Vector2(14, -11), 2.5, 0.15, M.WOOD, [["s", 8.4, 9.6]], M.SHEET_METAL, 0.1,
		[["n", 6.5, 7.5], ["n", 10.5, 11.5]])
	# Watchtowers in the north-east and south-west corners.
	_tower(out, Vector2(15.2, -17.6), ["n", "e"])
	_tower(out, Vector2(-17.6, 15.2), ["s", "w"])
	# Sandbags inside the gate, the cache and the AA site.
	out.append([Vector3(-5.0, 0, 15.6), Vector3(-2.4, 1.1, 16.0), M.SANDBAG])
	out.append([Vector3(2.4, 0, 15.6), Vector3(5.0, 1.1, 16.0), M.SANDBAG])
	_crates(out, Vector3(8.0, 0, 8.4))
	_aa_site(out, Vector2(-11.0, 9.0))
	_fuel_drums(out, Vector3(12.0, 0, -6.5))  # the fuel store (a sabotage target, 2026-10-20)
	return out


## A QRF base (hot zones): a HESCO enclosure 30 x 22 m, gate to the south, a cinder-block
## barracks, an open vehicle shed (posts and a sheet-metal roof: vehicles park here from wave 5)
## and the QRF's ammunition crates.
static func _qrf_base() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var H := M.HESCO
	out.append([Vector3(-15, 0, -11), Vector3(15, 2.0, -10), H])
	out.append([Vector3(-15, 0, -10), Vector3(-14, 2.0, 11), H])
	out.append([Vector3(14, 0, -10), Vector3(15, 2.0, 11), H])
	out.append([Vector3(-14, 0, 10), Vector3(-2.5, 2.0, 11), H])
	out.append([Vector3(2.5, 0, 10), Vector3(14, 2.0, 11), H])
	_room(out, Vector2(-13, -9), Vector2(-3, -3), 2.6, 0.2, M.CINDER_BLOCK, [["s", -8.6, -7.4]], M.SHEET_METAL, 0.1,
		[["n", -10.5, -9.5], ["n", -5.5, -4.5], ["e", -7.5, -6.5]])
	for p: Vector2 in [Vector2(2.0, -9.0), Vector2(12.8, -9.0), Vector2(2.0, -2.2), Vector2(12.8, -2.2)]:
		out.append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.2, 3.0, p.y + 0.2), M.STEEL])
	out.append([Vector3(2.0, 3.0, -9.0), Vector3(13.0, 3.1, -2.0), M.SHEET_METAL])
	_crates(out, Vector3(8.0, 0, 4.4))
	_fuel_drums(out, Vector3(10.6, 0, 0.2))  # the vehicles' fuel store by the shed (a sabotage target, 2026-10-20)
	return out


## A comms site (hot zones): a HESCO ring 14 m across with a gap to the south, a sheet-metal
## generator shed and a radio mast: a steel lattice 4.4 m tall with a dish. Steel shrugs off
## grenades: it takes a placed charge. Destroyed, the zone's reports slow down (Alert).
static func _comms() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var H := M.HESCO
	out.append([Vector3(-7, 0, -7), Vector3(7, 2.0, -6), H])
	out.append([Vector3(-7, 0, -6), Vector3(-6, 2.0, 7), H])
	out.append([Vector3(6, 0, -6), Vector3(7, 2.0, 7), H])
	out.append([Vector3(-6, 0, 6), Vector3(-1.5, 2.0, 7), H])
	out.append([Vector3(1.5, 0, 6), Vector3(6, 2.0, 7), H])
	_room(out, Vector2(-5.8, -5.8), Vector2(-2.8, -2.8), 2.2, 0.1, M.SHEET_METAL, [["e", -4.9, -3.9]], M.SHEET_METAL, 0.1)
	# The mast: four steel legs, cross braces, a platform and a dish.
	var T := M.STEEL
	for p: Vector2 in [Vector2(1.4, -4.1), Vector2(2.6, -4.1), Vector2(1.4, -2.9), Vector2(2.6, -2.9)]:
		out.append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.15, 4.2, p.y + 0.15), T])
	for y: float in [1.4, 2.8]:
		out.append([Vector3(1.4, y, -4.1), Vector3(2.75, y + 0.1, -2.75), T])
	out.append([Vector3(1.3, 4.2, -4.2), Vector3(2.9, 4.3, -2.6), T])
	out.append([Vector3(1.8, 4.3, -3.6), Vector3(2.4, 4.6, -3.4), T])
	return out


## A wooden watchtower with its low corner at `c` (x, z): four posts, a plank floor at 3 m and a
## sandbag parapet on each side in `faces` ("n" -z, "s" +z, "w" -x, "e" +x): the sides that look
## out of the site (a corner tower: its two outer sides, Captain 2026-10-12).
static func _tower(out: Array, c: Vector2, faces: Array) -> void:
	var W := VoxelWorld.Mat.WOOD
	var S := VoxelWorld.Mat.SANDBAG
	for p: Vector2 in [c, c + Vector2(2.4, 0), c + Vector2(0, 2.4), c + Vector2(2.4, 2.4)]:
		out.append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.2, 3.0, p.y + 0.2), W])
	out.append([Vector3(c.x, 3.0, c.y), Vector3(c.x + 2.6, 3.1, c.y + 2.6), W])
	for side: String in faces:
		match side:
			"n":
				out.append([Vector3(c.x, 3.1, c.y), Vector3(c.x + 2.6, 3.8, c.y + 0.3), S])
			"s":
				out.append([Vector3(c.x, 3.1, c.y + 2.3), Vector3(c.x + 2.6, 3.8, c.y + 2.6), S])
			"w":
				out.append([Vector3(c.x, 3.1, c.y), Vector3(c.x + 0.3, 3.8, c.y + 2.6), S])
			"e":
				out.append([Vector3(c.x + 2.3, 3.1, c.y), Vector3(c.x + 2.6, 3.8, c.y + 2.6), S])


## A weapons cache: two wooden crates (1 x 1 x 1.2 m) side by side along x from `corner` (their
## low corner), and a third on the first. Its box is `corner` to `corner` + (2, 2, 1.2).
static func _crates(out: Array, corner: Vector3) -> void:
	var W := VoxelWorld.Mat.WOOD
	var crate := Vector3(1.0, 1.0, 1.2)
	out.append([corner, corner + crate, W])
	out.append([corner + Vector3(1, 0, 0), corner + Vector3(1, 0, 0) + crate, W])
	out.append([corner + Vector3(0, 1, 0), corner + Vector3(0, 1, 0) + crate, W])


## A fuel store (a sabotage target, mission variety 2026-10-20): two rows of four steel fuel drums
## (0.6 x 0.9 m, 0.1 m apart) from `corner` (their low corner) along +x and +z. Its box is
## `corner` to `corner` + (2.7, 0.9, 1.3) (contracts.json "fuel"). Steel: it takes a placed charge.
static func _fuel_drums(out: Array, corner: Vector3) -> void:
	for row in 2:
		for col in 4:
			var at := corner + Vector3(col * 0.7, 0, row * 0.7)
			out.append([at, at + Vector3(0.6, 0.9, 0.6), VoxelWorld.Mat.STEEL])


## An AA emplacement centred on `c` (x, z): a 3.6 m sandbag ring 0.8 m high, open to the east,
## round a twin-barrel gun on a steel mount (barrels to the north). The gun fills (-0.5, 0, -1.3)
## to (0.5, 1.3, 0.4) from the centre.
## An AA emplacement (Captain, 2026-10-18: "the aa guns and such need a pass"): a sandbag ring in
## two courses with a way in on +X, and in it a twin-barrelled 23 mm gun on its cruciform
## outriggers (a ZU-23-2 pattern), barrels north over the bags, a seat each side, ammo boxes and
## a sight, all steel voxels (a sabotage objective counts them: solid_voxels_in).
static func _aa_site(out: Array, c: Vector2) -> void:
	var S := VoxelWorld.Mat.SANDBAG
	var T := VoxelWorld.Mat.STEEL
	var W := VoxelWorld.Mat.WOOD
	var at := Vector3(c.x, 0, c.y)
	# Sandbags: a lower course 0.6 high and 0.5 thick, an upper course inset 0.4 higher, both
	# open on +X (the way in) between z -0.6 and 0.6.
	for course: Array in [[0.0, 0.6, 2.0, 0.5], [0.6, 1.0, 1.9, 0.4]]:
		var y0: float = course[0]
		var y1: float = course[1]
		var r: float = course[2]
		var t: float = course[3]
		out.append([at + Vector3(-r, y0, -r), at + Vector3(r, y1, -r + t), S])
		out.append([at + Vector3(-r, y0, r - t), at + Vector3(r, y1, r), S])
		out.append([at + Vector3(-r, y0, -r + t), at + Vector3(-r + t, y1, r - t), S])
		out.append([at + Vector3(r - t, y0, -r + t), at + Vector3(r, y1, -0.6), S])
		out.append([at + Vector3(r - t, y0, 0.6), at + Vector3(r, y1, r - t), S])
	# The gun: outriggers, pedestal, cradle and seats.
	out.append([at + Vector3(-1.2, 0, -0.1), at + Vector3(1.2, 0.15, 0.1), T])
	out.append([at + Vector3(-0.1, 0, -1.2), at + Vector3(0.1, 0.15, 1.2), T])
	out.append([at + Vector3(-0.3, 0.15, -0.3), at + Vector3(0.3, 0.6, 0.3), T])
	out.append([at + Vector3(-0.45, 0.6, -0.5), at + Vector3(0.45, 0.9, 0.5), T])
	for side: float in [-1.0, 1.0]:
		var sx := 0.6 * side
		out.append([at + Vector3(sx - 0.15, 0.55, 0.1), at + Vector3(sx + 0.15, 0.65, 0.4), W])  # seat
		out.append([at + Vector3(sx - 0.15, 0.65, 0.35), at + Vector3(sx + 0.15, 0.95, 0.45), W])  # its back
		var bx := 0.2 * side
		out.append([at + Vector3(bx - 0.08, 0.9, -0.4), at + Vector3(bx + 0.08, 1.2, 0.45), T])  # receiver
		out.append([at + Vector3(bx - 0.05, 1.0, -2.4), at + Vector3(bx + 0.05, 1.1, -0.4), T])  # barrel
		out.append([at + Vector3(bx - 0.08, 0.97, -2.55), at + Vector3(bx + 0.08, 1.13, -2.4), T])  # flash hider
		out.append([at + Vector3(bx + 0.1 * side - 0.12, 0.9, -0.1), at + Vector3(bx + 0.1 * side + 0.12, 1.15, 0.2), T])  # ammo box
	out.append([at + Vector3(-0.06, 1.2, 0.0), at + Vector3(0.06, 1.4, 0.15), T])  # sight


## Solid voxels of a module type's pristine structure inside `box` (metres from its origin),
## counted the way Objectives.solid_count reads them from the built world: the authored
## "voxels" of a cache site on a zone module. Cached per type and box.
static func solid_voxels_in(type: String, box: AABB) -> int:
	var key := "%s|%s" % [type, box]
	if _counts.has(key):
		return _counts[key]
	var s := VoxelWorld.VOXEL_SIZE
	var begin := Vector3i((box.position / s).round())
	var end := Vector3i((box.end / s).round())
	var cells: Array = []  # [lo, hi) per structure box, in voxels
	for b: Array in boxes(type):
		var a := Vector3i(((b[0] as Vector3) / s).round())
		var c := Vector3i(((b[1] as Vector3) / s).round())
		if int(b[2]) != VoxelWorld.Mat.EMPTY:
			cells.append([a.min(c), a.max(c)])
	var solid := 0
	for x in range(begin.x, end.x):
		for y in range(begin.y, end.y):
			for z in range(begin.z, end.z):
				for k: Array in cells:
					var lo: Vector3i = k[0]
					var hi: Vector3i = k[1]
					if x >= lo.x and x < hi.x and y >= lo.y and y < hi.y and z >= lo.z and z < hi.z:
						solid += 1
						break
	_counts[key] = solid
	return solid
