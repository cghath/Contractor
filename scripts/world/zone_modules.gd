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
## "checkpoint" (a road checkpoint: barriers, a booth, a sandbag nest).
const TYPES: Array[String] = ["compound", "outpost", "village", "checkpoint"]

## Half the footprint in metres (x, z): the pad under it and its voxel bounds.
const HALF := {
	"compound": Vector2(21.0, 21.0),
	"outpost": Vector2(11.0, 11.0),
	"village": Vector2(20.0, 14.0),
	"checkpoint": Vector2(14.0, 10.0),
}
## Voxel bounds reach this far above the ground (m) and this far below it.
const TOP_M := 4.8
const BELOW_M := 0.8

## Named points (m from the origin, on the ground): "objective" (where a mission's target
## goes: an HVT room, a document table), "cache" (something to destroy or recover) and
## "intel".
const POINTS := {
	"compound": {"objective": [Vector3(0, 0, -8)], "cache": [Vector3(-12, 0, -9)], "intel": [Vector3(18, 0, -9)]},
	"outpost": {"objective": [Vector3(-5.5, 0, -6)], "cache": [Vector3(2.5, 0, -0.5)], "intel": [Vector3(-4.5, 0, -6.5)]},
	"village": {"objective": [Vector3(15.5, 0, -10)], "cache": [Vector3(-13.5, 0, 9)], "intel": [Vector3(1, 0, -9.5)]},
	"checkpoint": {"objective": [Vector3(9, 0, 5)], "cache": [Vector3(-10, 0, 6.5)], "intel": [Vector3(9.2, 0, 4.6)]},
}

## Hostile garrison (m from the origin): they hold where they stand (guards), in pairs.
const GARRISON := {
	"compound": [Vector3(-2.5, 0.1, -10), Vector3(2.5, 0.1, -6.5), Vector3(-12, 0.1, -2), Vector3(-10, 0.1, -3)],
	"outpost": [Vector3(-5.5, 0.1, -6), Vector3(6, 0.1, -2), Vector3(-4, 0.1, 7.2), Vector3(4, 0.1, 7.2)],
	"village": [Vector3(-15, 0.1, -10), Vector3(1, 0.1, -10), Vector3(15.5, 0.1, -10), Vector3(-13.5, 0.1, 9)],
	"checkpoint": [Vector3(9, 0.1, 5), Vector3(-10, 0.1, 6.5), Vector3(2, 0.1, -5), Vector3(-2, 0.1, -5)],
}

## Loot lying in each module (m from the origin; uids are made unique per module).
const LOOT := {
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
}

static var _cache := {}


static func has_type(type: String) -> bool:
	return type in TYPES


## The module's base structure: [from (Vector3, m), to (Vector3, m), VoxelWorld.Mat] boxes,
## in the order they are built.
static func boxes(type: String) -> Array:
	if not _cache.has(type):
		match type:
			"compound":
				_cache[type] = CompoundLevel.structure_boxes()
			"outpost":
				_cache[type] = _outpost()
			"village":
				_cache[type] = _village()
			"checkpoint":
				_cache[type] = _checkpoint()
			_:
				push_error("ZoneModules: unknown type %s" % type)
				return []
	return _cache[type]


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
	var hi := Vector3(half.x + 1.0, TOP_M, half.y + 1.0) / s
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
	return out
