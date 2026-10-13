class_name BuildingGen
extends RefCounted
## Procedural buildings (Captain, 2026-10-13; docs/building_gen.md). A building is a shell from a
## footprint, rooms laid out by its type's rules, and each room furnished from the interior chunk
## library (data/building_chunks.json) with a chunk that suits it. The output is the same kind of
## box list as ZoneModules ([lo, hi, Mat], metres from the building's origin on the ground,
## front door to +z), so destruction, saves and streaming work as they do, and the AI finds its
## rooms and doorways by probing (Buildings). The same seed gives the same building.
##
## Phase 1: single-storey houses. Phase 2: shops, warehouses, clinics, police stations.

const CHUNKS_PATH := "res://data/building_chunks.json"
## The narrowest a room may be (m), and how much wall a doorway keeps either side of it.
const MIN_ROOM := 2.6
const DOOR_W := 0.9
const DOOR_H := 2.1
const DOOR_EDGE := 0.3
## Windows: width, sill and top (m); only on outer walls this long or longer.
const WIN_W := 1.0
const WIN_SILL := 1.0
const WIN_TOP := 1.7
const WIN_WALL_MIN := 2.2
## Kept clear in front of a doorway (m into the room) when furnishing.
const DOOR_CLEAR := 1.0
## Interior walls, and how much a room's furniture stays off its walls (m).
const INNER_T := 0.15
const FURNITURE_GAP := 0.05
## Moderate variation (Captain, 2026-10-13): an optional item is there at least MIN_CHANCE of the
## time, and "vary" shrinks an item by at most MAX_VARY of its size on any side.
const MIN_CHANCE := 0.6
const MAX_VARY := 0.2
## Building styles: outer wall (material, thickness), inner walls, roof (material, thickness), and
## the wall height. Picked by region/preset (style_for) or given.
const STYLES := {
	"mud": {"wall": VoxelWorld.Mat.MUD_BRICK, "t": 0.4, "inner": VoxelWorld.Mat.MUD_BRICK, "roof": VoxelWorld.Mat.WOOD, "roof_t": 0.2, "h": 2.7},
	"brick": {"wall": VoxelWorld.Mat.BRICK, "t": 0.25, "inner": VoxelWorld.Mat.PLASTER, "roof": VoxelWorld.Mat.CONCRETE, "roof_t": 0.2, "h": 2.8},
	"block": {"wall": VoxelWorld.Mat.CINDER_BLOCK, "t": 0.2, "inner": VoxelWorld.Mat.CINDER_BLOCK, "roof": VoxelWorld.Mat.SHEET_METAL, "roof_t": 0.1, "h": 2.6},
	"stone": {"wall": VoxelWorld.Mat.STONE, "t": 0.4, "inner": VoxelWorld.Mat.PLASTER, "roof": VoxelWorld.Mat.ROOF_TILE, "roof_t": 0.2, "h": 2.8},
}
## Building types: footprint (width x along the street, depth z: [min, max] m each), how many
## rooms, and their roles: "front" the room the front door opens into (the one with most street
## wall; doorways spread from it), "fill" roles given to the rest biggest first, "smallest" the
## smallest room's role, "inner" a role that goes in the room with the least outside wall (none
## for "rest" when the list runs out); "back" the room with a back door; rooms with no windows;
## the front door's and the windows' widths (m). A house keeps its own rules (_house_roles).
const TYPES := {
	"house": {"w": [8.0, 13.0], "d": [7.0, 11.0], "rooms": [4, 6], "front": "living", "back": "kitchen",
		"dark": ["bathroom", "storeroom"], "door_w": 0.9, "win_w": 1.0},
	"shop": {"w": [7.0, 11.0], "d": [8.0, 12.0], "rooms": [3, 4], "front": "shopfront", "fill": ["storeroom", "office"],
		"smallest": "bathroom", "rest": "storeroom", "back": "storeroom", "dark": ["bathroom", "storeroom"], "door_w": 1.8, "win_w": 2.0},
	"warehouse": {"w": [12.0, 18.0], "d": [10.0, 14.0], "rooms": [2, 3], "front": "hall", "fill": ["office", "storeroom"],
		"rest": "storeroom", "back": "hall", "dark": ["storeroom"], "door_w": 3.0, "win_w": 1.0, "first_cut": 0.72},
	"clinic": {"w": [11.0, 15.0], "d": [10.0, 13.0], "rooms": [5, 6], "front": "reception", "fill": ["ward", "treatment", "office"],
		"smallest": "bathroom", "inner": "pharmacy", "rest": "ward", "back": "treatment", "dark": ["bathroom", "pharmacy"], "door_w": 1.2, "win_w": 1.2},
	"police": {"w": [11.0, 15.0], "d": [9.0, 12.0], "rooms": [5, 6], "front": "front_desk", "fill": ["office", "cells", "storeroom"],
		"smallest": "bathroom", "inner": "armoury", "rest": "office", "back": "office", "dark": ["bathroom", "armoury", "cells", "storeroom"],
		"door_w": 1.2, "win_w": 1.0},
}

static var _chunks: Array = []


## A house from `seed` in `style` (building("house", ...)).
static func house(seed: int, style := "") -> Dictionary:
	return building("house", seed, style)


## A building of `type` (TYPES) from `seed` in `style` (STYLES; "" picks one from the seed).
## Returns {"boxes": [[lo, hi, Mat]], "rooms": [{"role", "rect" (Rect2, x/z inside its walls),
## "chunk"}], "doors": [{"at": Vector3, "rooms": [i, j] (j -1: outside)}], "loot": [{"at",
## "table"}], "size": Vector2, "style", "type"}.
static func building(type: String, seed: int, style := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if style == "":
		style = STYLES.keys()[rng.randi() % STYLES.size()]
	var st: Dictionary = STYLES[style]
	var spec: Dictionary = TYPES[type]
	var w := snappedf(rng.randf_range(spec.w[0], spec.w[1]), 0.1)
	var d := snappedf(rng.randf_range(spec.d[0], spec.d[1]), 0.1)
	var outer := Rect2(-w * 0.5, -d * 0.5, w, d)
	var t: float = st.t
	var inner := outer.grow(-t)
	# Rooms: split the inside along the longer side until there are enough.
	var want := rng.randi_range(spec.rooms[0], spec.rooms[1])
	var rects: Array[Rect2] = [inner]
	var splits: Array = []  # [axis (0: a wall at x, 1: at z), at, from, to]
	while rects.size() < want:
		rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.get_area() > b.get_area())
		var done := false
		for i in rects.size():
			var r: Rect2 = rects[i]
			var axis := 0 if r.size.x >= r.size.y else 1
			var span := r.size.x if axis == 0 else r.size.y
			if span < MIN_ROOM * 2.0 + INNER_T:
				axis = 1 - axis
				span = r.size.x if axis == 0 else r.size.y
				if span < MIN_ROOM * 2.0 + INNER_T:
					continue
			var share := float(spec.first_cut) if splits.is_empty() and spec.has("first_cut") else rng.randf_range(0.4, 0.6)
			var cut := snappedf(clampf(span * share, MIN_ROOM + INNER_T * 0.5, span - MIN_ROOM - INNER_T * 0.5), 0.1)
			var a: Rect2
			var b: Rect2
			if axis == 0:
				var x := r.position.x + cut
				a = Rect2(r.position, Vector2(cut, r.size.y))
				b = Rect2(Vector2(x, r.position.y), Vector2(r.size.x - cut, r.size.y))
				splits.append([0, x, r.position.y, r.end.y])
			else:
				var z := r.position.y + cut
				a = Rect2(r.position, Vector2(r.size.x, cut))
				b = Rect2(Vector2(r.position.x, z), Vector2(r.size.x, r.size.y - cut))
				splits.append([1, z, r.position.x, r.end.x])
			rects.remove_at(i)
			rects.append(a)
			rects.append(b)
			done = true
			break
		if not done:
			break
	# Which rooms share a wall long enough for a doorway: [i, j, axis, at, from, to].
	var links: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var l := _shared(rects[i], rects[j])
			if not l.is_empty():
				links.append([i, j] + l)
	var roles := _house_roles(rects, links) if type == "house" else _roles(spec, rects, inner)
	var n := rects.size()
	var hub := roles.find(spec.front)
	var bath := roles.find("bathroom")
	# Doorways: a tree from the front room (the bathroom a leaf), and now and then one loop.
	var tree: Array = []
	var reached := {hub: true}
	var grew := true
	while grew and reached.size() < n:
		grew = false
		for pass_bath in [false, true]:
			for l: Array in links:
				var a: int = l[0]
				var b: int = l[1]
				if reached.has(a) == reached.has(b):
					continue
				var new_room := b if reached.has(a) else a
				var from_room := a if reached.has(a) else b
				if not pass_bath and (new_room == bath or from_room == bath):
					continue
				if from_room == bath:
					continue  # nothing through the bathroom
				tree.append(l)
				reached[new_room] = true
				grew = true
			if grew:
				break
	if rng.randf() < 0.3:
		for l: Array in links:
			if not tree.has(l) and l[0] != bath and l[1] != bath:
				tree.append(l)
				break
	var gaps := {}  # wall key -> [[from, to, bottom, top]]
	var doors: Array = []
	for l: Array in tree:
		var mid := (float(l[4]) + float(l[5])) * 0.5
		var lo := clampf(mid - DOOR_W * 0.5, float(l[4]) + DOOR_EDGE, float(l[5]) - DOOR_EDGE - DOOR_W)
		_gap(gaps, "in:%d:%s" % [l[2], snappedf(l[3], 0.01)], lo, lo + DOOR_W, 0.0, DOOR_H)
		var at := Vector3(l[3], 0, lo + DOOR_W * 0.5) if l[2] == 0 else Vector3(lo + DOOR_W * 0.5, 0, l[3])
		doors.append({"at": at, "rooms": [l[0], l[1]]})
	# Outside: the front door (+z, the street) from the front room if it can, else the room
	# nearest the front; a back door from the type's back room.
	var door_w: float = spec.door_w
	var front := hub if _side_len(rects[hub], inner, "s") >= door_w + 2.0 * DOOR_EDGE else _nearest_side(rects, inner, "s", bath)
	_outer_door(gaps, doors, rects, inner, front, "s", rng, door_w)
	var back := roles.find(spec.back)
	for side: String in ["n", "e", "w"]:
		if back >= 0 and (back != front or side == "n") and _side_len(rects[back], inner, side) >= DOOR_W + 2.0 * DOOR_EDGE:
			_outer_door(gaps, doors, rects, inner, back, side, rng, maxf(DOOR_W, door_w if type == "warehouse" else DOOR_W))
			break
	# Windows on outer walls, but not in the type's dark rooms (bathrooms, storerooms, an armoury).
	var win_w: float = spec.win_w
	for i in n:
		if roles[i] in (spec.dark as Array):
			continue
		for side: String in ["n", "s", "e", "w"]:
			var span := _side_span(rects[i], inner, side)
			if span.y - span.x < maxf(WIN_WALL_MIN, win_w + 1.0):
				continue
			var mid := (span.x + span.y) * 0.5
			if not _overlaps(gaps.get("out:" + side, []), mid - win_w * 0.5 - 0.3, mid + win_w * 0.5 + 0.3):
				_gap(gaps, "out:" + side, mid - win_w * 0.5, mid + win_w * 0.5, WIN_SILL, WIN_TOP)
	# The walls.
	var boxes: Array = []
	var h: float = st.h
	_wall(boxes, 0, outer.position.y, outer.position.y + t, outer.position.x, outer.end.x, h, st.wall, gaps.get("out:n", []))
	_wall(boxes, 0, outer.end.y - t, outer.end.y, outer.position.x, outer.end.x, h, st.wall, gaps.get("out:s", []))
	_wall(boxes, 1, outer.position.x, outer.position.x + t, inner.position.y, inner.end.y, h, st.wall, gaps.get("out:w", []))
	_wall(boxes, 1, outer.end.x - t, outer.end.x, inner.position.y, inner.end.y, h, st.wall, gaps.get("out:e", []))
	for s: Array in splits:
		var key := "in:%d:%s" % [s[0], snappedf(s[1], 0.01)]
		_wall(boxes, 1 if s[0] == 0 else 0, float(s[1]) - INNER_T * 0.5, float(s[1]) + INNER_T * 0.5, s[2], s[3], h, st.inner, gaps.get(key, []))
	boxes.append([Vector3(outer.position.x, h, outer.position.y), Vector3(outer.end.x, h + float(st.roof_t), outer.end.y), st.roof])
	# Furnish each room.
	var rooms: Array = []
	var loot: Array = []
	for i in n:
		var room := _room_rect(rects[i], inner)
		var placed := _furnish(boxes, loot, room, roles[i], doors, i, rng)
		rooms.append({"role": roles[i], "rect": room, "chunk": placed})
	return {"boxes": boxes, "rooms": rooms, "doors": doors, "loot": loot, "size": Vector2(w, d), "style": style, "type": type}


## A style for a zone's region and terrain preset (TerrainPresets ids).
static func style_for(preset: String, seed: int) -> String:
	var pick := {
		"desert_wadi": ["mud", "mud", "block"], "scrubland": ["mud", "block"], "salt_flats": ["block", "mud"],
		"rocky_ridge": ["stone", "block"], "temperate": ["brick", "stone", "block"],
		"coastal_lowland": ["block", "brick"], "amphibious_coast": ["block", "brick"],
	}
	var list: Array = pick.get(preset, ["block", "brick"])
	return list[absi(seed) % list.size()]


# --- Rooms -----------------------------------------------------------------------------------

## The stretch two rooms share (a wall between them long enough for a doorway): [axis, at,
## from, to], axis 0 a wall at x = at running along z, 1 a wall at z = at; or [].
static func _shared(a: Rect2, b: Rect2) -> Array:
	var need := DOOR_W + DOOR_EDGE * 2.0
	for pair: Array in [[a, b], [b, a]]:
		var p: Rect2 = pair[0]
		var q: Rect2 = pair[1]
		if absf(p.end.x - q.position.x) < 0.01:
			var lo := maxf(p.position.y, q.position.y)
			var hi := minf(p.end.y, q.end.y)
			if hi - lo >= need:
				return [0, p.end.x, lo, hi]
		if absf(p.end.y - q.position.y) < 0.01:
			var lo := maxf(p.position.x, q.position.x)
			var hi := minf(p.end.x, q.end.x)
			if hi - lo >= need:
				return [1, p.end.y, lo, hi]
	return []


## A non-house building's room roles from its type's spec (TYPES): the front room the one with
## the most street wall, the smallest room its "smallest" role, the room with the least outside
## wall its "inner" role, the rest "fill" biggest first, then "rest".
static func _roles(spec: Dictionary, rects: Array[Rect2], inner: Rect2) -> Array:
	var n := rects.size()
	var roles: Array = []
	roles.resize(n)
	roles.fill("")
	var front := _nearest_side(rects, inner, "s")
	roles[front] = spec.front
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return rects[a].get_area() > rects[b].get_area())
	if spec.has("smallest") and n >= 4 and roles[order[n - 1]] == "":
		roles[order[n - 1]] = spec.smallest
	if spec.has("inner"):
		var outside := func(i: int) -> float:
			return _side_len(rects[i], inner, "n") + _side_len(rects[i], inner, "s") + _side_len(rects[i], inner, "e") + _side_len(rects[i], inner, "w")
		var best := -1
		for i in n:
			if roles[i] == "" and (best < 0 or outside.call(i) < outside.call(best)):
				best = i
		if best >= 0:
			roles[best] = spec.inner
	var fill: Array = (spec.get("fill", []) as Array).duplicate()
	for i: int in order:
		if roles[i] == "":
			roles[i] = fill.pop_front() if not fill.is_empty() else String(spec.get("rest", "storeroom"))
	return roles


## A house's room roles: the biggest is the living room, the smallest the bathroom, the kitchen
## the biggest left next to the living room, a sixth room a storeroom, the rest bedrooms.
static func _house_roles(rects: Array[Rect2], links: Array) -> Array:
	var n := rects.size()
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return rects[a].get_area() > rects[b].get_area())
	var roles: Array = []
	roles.resize(n)
	roles.fill("bedroom")
	roles[order[0]] = "living"
	roles[order[n - 1]] = "bathroom"
	if n >= 6:
		roles[order[n - 2]] = "storeroom"
	for i: int in order.slice(1):
		if roles[i] != "bedroom":
			continue
		var next_to := links.any(func(l: Array) -> bool: return (l[0] == i and l[1] == order[0]) or (l[1] == i and l[0] == order[0]))
		if next_to:
			roles[i] = "kitchen"
			break
	if not roles.has("kitchen"):
		for i: int in order.slice(1):
			if roles[i] == "bedroom":
				roles[i] = "kitchen"
				break
	return roles


## The room's floor inside its walls (a room's rect runs to the middle of its inner walls).
static func _room_rect(r: Rect2, inner: Rect2) -> Rect2:
	var lo := r.position
	var hi := r.end
	if lo.x > inner.position.x + 0.01:
		lo.x += INNER_T * 0.5
	if lo.y > inner.position.y + 0.01:
		lo.y += INNER_T * 0.5
	if hi.x < inner.end.x - 0.01:
		hi.x -= INNER_T * 0.5
	if hi.y < inner.end.y - 0.01:
		hi.y -= INNER_T * 0.5
	return Rect2(lo, hi - lo)


## How much of the house's `side` ("n", "s", "e", "w") wall room `r` has: [from, to] along it, or
## a zero-length span when it doesn't touch that side.
static func _side_span(r: Rect2, inner: Rect2, side: String) -> Vector2:
	match side:
		"n": return Vector2(r.position.x, r.end.x) if absf(r.position.y - inner.position.y) < 0.01 else Vector2.ZERO
		"s": return Vector2(r.position.x, r.end.x) if absf(r.end.y - inner.end.y) < 0.01 else Vector2.ZERO
		"w": return Vector2(r.position.y, r.end.y) if absf(r.position.x - inner.position.x) < 0.01 else Vector2.ZERO
		"e": return Vector2(r.position.y, r.end.y) if absf(r.end.x - inner.end.x) < 0.01 else Vector2.ZERO
	return Vector2.ZERO


static func _side_len(r: Rect2, inner: Rect2, side: String) -> float:
	var s := _side_span(r, inner, side)
	return s.y - s.x


## The room with the most of the house's `side` wall, not `skip` (the bathroom: its one doorway
## stays the one inside).
static func _nearest_side(rects: Array[Rect2], inner: Rect2, side: String, skip := -1) -> int:
	var best := 0 if skip != 0 else 1
	for i in rects.size():
		if i != skip and _side_len(rects[i], inner, side) > _side_len(rects[best], inner, side):
			best = i
	return best


static func _outer_door(gaps: Dictionary, doors: Array, rects: Array[Rect2], inner: Rect2, room: int, side: String, rng: RandomNumberGenerator, width := DOOR_W) -> void:
	var span := _side_span(rects[room], inner, side)
	width = minf(width, span.y - span.x - DOOR_EDGE * 2.0)
	if width < DOOR_W:
		return
	var lo := snappedf(rng.randf_range(span.x + DOOR_EDGE, span.y - DOOR_EDGE - width), 0.1)
	_gap(gaps, "out:" + side, lo, lo + width, 0.0, DOOR_H + (0.4 if width >= 2.5 else 0.0))
	var c := lo + width * 0.5
	var at: Vector3
	match side:
		"n": at = Vector3(c, 0, inner.position.y)
		"s": at = Vector3(c, 0, inner.end.y)
		"w": at = Vector3(inner.position.x, 0, c)
		_: at = Vector3(inner.end.x, 0, c)
	doors.append({"at": at, "rooms": [room, -1]})


# --- Walls -----------------------------------------------------------------------------------

static func _gap(gaps: Dictionary, key: String, from: float, to: float, bottom: float, top: float) -> void:
	if not gaps.has(key):
		gaps[key] = []
	(gaps[key] as Array).append([from, to, bottom, top])


static func _overlaps(list: Array, from: float, to: float) -> bool:
	return list.any(func(g: Array) -> bool: return g[0] < to and g[1] > from)


## A wall `h` tall with its gaps (doorways, windows: [from, to, bottom, top] along it): `axis` 0
## runs along x (from `lo`..`hi` in z thick), 1 along z (from `lo`..`hi` in x thick).
static func _wall(out: Array, axis: int, lo: float, hi: float, from: float, to: float, h: float, mat: int, gaps: Array) -> void:
	var box := func(a0: float, a1: float, y0: float, y1: float) -> void:
		if a1 - a0 < 0.05 or y1 - y0 < 0.05:
			return
		if axis == 0:
			out.append([Vector3(a0, y0, lo), Vector3(a1, y1, hi), mat])
		else:
			out.append([Vector3(lo, y0, a0), Vector3(hi, y1, a1), mat])
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var at := from
	for g: Array in sorted:
		var g0 := maxf(float(g[0]), from)
		var g1 := minf(float(g[1]), to)
		if g1 <= g0:
			continue
		box.call(at, g0, 0.0, h)
		box.call(g0, g1, 0.0, float(g[2]))   # under it (a window's sill)
		box.call(g0, g1, float(g[3]), h)     # over it (the lintel)
		at = g1
	box.call(at, to, 0.0, h)


# --- Furnishing ------------------------------------------------------------------------------

## The interior chunk library (data/building_chunks.json "chunks").
static func chunks() -> Array:
	if _chunks.is_empty():
		var text := FileAccess.get_file_as_string(CHUNKS_PATH)
		var data: Variant = JSON.parse_string(text)
		_chunks = (data as Dictionary).get("chunks", []) if data is Dictionary else []
	return _chunks


## Puts a chunk that suits `role` against a wall of `room` with no doorway (the longest such
## wall that fits it), keeping every doorway's DOOR_CLEAR free: items that would block one are
## left out. Returns the chunk's id, or "".
static func _furnish(boxes: Array, loot: Array, room: Rect2, role: String, doors: Array, index: int, rng: RandomNumberGenerator) -> String:
	var mine := doors.filter(func(dr: Dictionary) -> bool: return index in dr.rooms)
	# Kept clear: the doorway's width (and a little) along its wall, DOOR_CLEAR out from it.
	var clear: Array[Rect2] = []
	for dr: Dictionary in mine:
		var p: Vector3 = dr.at
		var along := DOOR_W * 0.5 + 0.2
		var in_x_wall := minf(absf(p.x - room.position.x), absf(p.x - room.end.x)) < minf(absf(p.z - room.position.y), absf(p.z - room.end.y))
		if in_x_wall:  # the doorway is in a wall at x (it runs along z)
			clear.append(Rect2(p.x - DOOR_CLEAR, p.z - along, DOOR_CLEAR * 2.0, along * 2.0))
		else:
			clear.append(Rect2(p.x - along, p.z - DOOR_CLEAR, along * 2.0, DOOR_CLEAR * 2.0))
	# Walls: [side, length, whether a doorway is in it].
	var walls: Array = []
	for side: String in ["n", "s", "e", "w"]:
		var along := room.size.x if side in ["n", "s"] else room.size.y
		var blocked := mine.any(func(dr: Dictionary) -> bool: return _door_on(dr.at, room, side))
		walls.append([side, along, blocked])
	walls.sort_custom(func(a: Array, b: Array) -> bool: return (not a[2] and b[2]) or (a[2] == b[2] and a[1] > b[1]))
	var fits := chunks().filter(func(c: Dictionary) -> bool: return role in (c.roles as Array))
	if fits.is_empty():
		return ""
	for attempt in fits.size():
		var c: Dictionary = fits[rng.randi() % fits.size()]
		var size: Array = c.size  # [along the wall, out from it]
		for wl: Array in walls:
			var depth := room.size.y if wl[0] in ["n", "s"] else room.size.x
			if float(size[0]) > float(wl[1]) - FURNITURE_GAP * 2.0 or float(size[1]) > depth - FURNITURE_GAP * 2.0:
				continue
			# This placement's take on the chunk: an item with a "chance" may be left out, one
			# with "vary" [x, y, z] is up to that much smaller (from its far side, so it stays
			# against the wall), one with "mats" is one of them.
			var items: Array = []
			for it: Dictionary in c.items:
				if it.has("chance") and rng.randf() > maxf(float(it.chance), MIN_CHANCE):
					continue
				var b: Array = (it.box as Array).duplicate()
				var v: Array = it.get("vary", [0, 0, 0])
				for k in 3:
					var extent := float(b[k + 3]) - float(b[k])
					b[k + 3] = float(b[k + 3]) - rng.randf() * minf(float(v[k]), extent * MAX_VARY)
				var mats: Array = it.get("mats", [String(it.get("mat", "WOOD"))])
				items.append({"box": b, "mat": String(mats[rng.randi() % mats.size()])})
			if items.is_empty():
				continue
			# Centred on the wall, else slid to either end of it, wherever the most of it fits.
			var slack := float(wl[1]) - float(size[0]) - FURNITURE_GAP * 2.0
			var best_offset := 0.0
			var best: Array = []
			for offset: float in [FURNITURE_GAP + slack * 0.5, FURNITURE_GAP, FURNITURE_GAP + slack]:
				var fit: Array = []
				for it: Dictionary in items:
					var b: Array = it.box  # [x0, y0, z0, x1, y1, z1]: x along the wall, z out from it
					var lo := _to_room(room, wl[0], offset + float(b[0]), float(b[2]) + FURNITURE_GAP, float(b[1]))
					var hi := _to_room(room, wl[0], offset + float(b[3]), float(b[5]) + FURNITURE_GAP, float(b[4]))
					var a := lo.min(hi)
					var z := lo.max(hi)
					var foot := Rect2(a.x, a.z, z.x - a.x, z.z - a.z)
					if not clear.any(func(cr: Rect2) -> bool: return cr.intersects(foot)):
						fit.append([a, z, VoxelWorld.Mat.get(String(it.get("mat", "WOOD")), VoxelWorld.Mat.WOOD)])
				if fit.size() > best.size():
					best = fit
					best_offset = offset
				if fit.size() == items.size():
					break
			if best.is_empty():
				continue
			boxes.append_array(best)
			for l: Array in c.get("loot", []):
				loot.append({"at": _to_room(room, wl[0], best_offset + float(l[0]), float(l[1]) + FURNITURE_GAP, 0.0), "table": String(l[2])})
			return String(c.id)
	return ""


## Whether doorway `at` is in `room`'s `side` wall.
static func _door_on(at: Vector3, room: Rect2, side: String) -> bool:
	var e := INNER_T + 0.45
	match side:
		"n": return absf(at.z - room.position.y) < e and at.x >= room.position.x - 0.1 and at.x <= room.end.x + 0.1
		"s": return absf(at.z - room.end.y) < e and at.x >= room.position.x - 0.1 and at.x <= room.end.x + 0.1
		"w": return absf(at.x - room.position.x) < e and at.z >= room.position.y - 0.1 and at.z <= room.end.y + 0.1
		_: return absf(at.x - room.end.x) < e and at.z >= room.position.y - 0.1 and at.z <= room.end.y + 0.1


## A chunk's (along, out, up) against `room`'s `side` wall, in the building's metres.
static func _to_room(room: Rect2, side: String, along: float, out: float, up: float) -> Vector3:
	match side:
		"n": return Vector3(room.position.x + along, up, room.position.y + out)
		"s": return Vector3(room.end.x - along, up, room.end.y - out)
		"w": return Vector3(room.position.x + out, up, room.end.y - along)
		_: return Vector3(room.end.x - out, up, room.position.y + along)


# --- Towns (phase 2) -------------------------------------------------------------------------

## A town (ZoneModules type "town#<seed>"): a main street along x and a cross street along z,
## lots along both sides of each, every building facing its street (the far side turned round).
## Mostly houses; shops near the middle, warehouses at the ends, a clinic and a police station.
const TOWN_HALF_X := 54.0
const STREET_W := 8.0
const CROSS_W := 7.0
const LOT_GAP := 2.0
const SETBACK := 1.0
## Lot types by where they are along the street (0 the middle .. 1 the end): weights.
const TOWN_MIX := {"house": 6.0, "shop": 2.5, "warehouse": 1.0, "clinic": 0.6, "police": 0.6}


## The town from `seed`: {"boxes", "buildings": [{"type", "origin" (Vector3), "turned" (180
## degrees), "data" (building())}], "half" (Vector2: footprint half-size, m), "points"
## ({"objective", "cache", "intel"}: Array of Vector3), "garrison" (Array of Vector3), "style"}.
static func town(seed: int, style := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if style == "":
		style = STYLES.keys()[rng.randi() % STYLES.size()]
	var boxes: Array = []
	var buildings: Array = []
	var once := {}
	var deepest := 0.0
	var k := 0
	for side: int in [-1, 1]:  # -1: north of the main street (facing +z), 1: south (turned round)
		for dir: int in [-1, 1]:  # out from the cross street, west then east
			var cursor := CROSS_W * 0.5 + LOT_GAP
			while true:
				var along := cursor / TOWN_HALF_X
				var type := _town_type(rng, along, once)
				var b := building(type, seed * 97 + k, style)
				k += 1
				var size: Vector2 = b.size
				if cursor + size.x > TOWN_HALF_X:
					if type == "house":
						break
					continue  # too big for what's left: try again (a house, most likely)
				if type in ["clinic", "police"]:
					once[type] = true
				var x := dir * (cursor + size.x * 0.5)
				var z := side * (STREET_W * 0.5 + SETBACK + size.y * 0.5)  # north (-z) faces +z as built; south turned
				var turned := side == 1
				var origin := Vector3(x, 0, z)
				for bx: Array in b.boxes:
					var lo: Vector3 = bx[0]
					var hi: Vector3 = bx[1]
					if turned:
						var nlo := Vector3(-hi.x, lo.y, -hi.z)
						var nhi := Vector3(-lo.x, hi.y, -lo.z)
						lo = nlo
						hi = nhi
					boxes.append([lo + origin, hi + origin, bx[2]])
				buildings.append({"type": type, "origin": origin, "turned": turned, "data": b})
				deepest = maxf(deepest, size.y)
				cursor += size.x + LOT_GAP
	var half := Vector2(TOWN_HALF_X + 2.0, STREET_W * 0.5 + SETBACK + deepest + 2.0)
	# Named points: where loot of a kind lies, in town metres.
	var points := {"objective": [], "cache": [], "intel": []}
	var garrison: Array = []
	for b: Dictionary in buildings:
		var to_town := func(p: Vector3) -> Vector3:
			return (Vector3(-p.x, p.y, -p.z) if b.turned else p) + (b.origin as Vector3)
		for l: Dictionary in b.data.loot:
			var t: String = l.table
			var where: Vector3 = to_town.call(l.at)
			if t in ["armoury", "objective"]:
				points.objective.append(where)
			elif t == "cache":
				points.cache.append(where)
			elif t == "intel":
				points.intel.append(where)
		# A post just inside the front door of every other building.
		if buildings.find(b) % 2 == 0:
			for dr: Dictionary in b.data.doors:
				if dr.rooms[1] == -1 and (dr.at as Vector3).z > 0.0:
					garrison.append(to_town.call((dr.at as Vector3) + Vector3(0, 0.1, -1.0)))
					break
	for fallback: String in ["objective", "cache", "intel"]:
		if (points[fallback] as Array).is_empty():
			points[fallback].append(Vector3(0, 0, 0))
	garrison.append(Vector3(-CROSS_W, 0.1, 0))
	garrison.append(Vector3(CROSS_W, 0.1, 0))
	return {"boxes": boxes, "buildings": buildings, "half": half, "points": points, "garrison": garrison, "style": style}


## A lot's building type: by TOWN_MIX, shops toward the middle, warehouses toward the ends, a
## clinic and a police station at most once each (`once`).
static func _town_type(rng: RandomNumberGenerator, along: float, once: Dictionary) -> String:
	var weights := {}
	for t: String in TOWN_MIX:
		var w: float = TOWN_MIX[t]
		if t == "shop":
			w *= lerpf(2.0, 0.3, along)
		elif t == "warehouse":
			w *= lerpf(0.1, 2.0, along)
		elif once.has(t):
			w = 0.0
		weights[t] = w
	var total := 0.0
	for t: String in weights:
		total += weights[t]
	var roll := rng.randf() * total
	for t: String in weights:
		roll -= weights[t]
		if roll <= 0.0:
			return t
	return "house"
