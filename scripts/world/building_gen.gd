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
## Phase 3: second storeys with stairs, flat roofs the AI can climb onto, L-shaped buildings,
## walled yards and courtyards.

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
## Storeys (phase 3): a floor slab SLAB_T thick between them; a stair STAIR_W wide, its steps
## STAIR_RISE high at most (the navmesh climbs 0.25 m) and STAIR_TREAD deep, STAIR_LANDING
## clear past its top, and a railing RAIL_H high round its stairwell above.
const SLAB_T := 0.2
const STAIR_W := 1.0
const STAIR_RISE := 0.23
const STAIR_TREAD := 0.25
const STAIR_LANDING := 0.8
const RAIL_H := 1.0
const RAIL_T := 0.1
## A flat roof with a stair up to it has a parapet round its edge.
const PARAPET_H := 0.9
## Yards (phase 3): behind a building (YARD_D deep, m) or in an L-shaped one's missing corner
## (L_YARD_CHANCE of them): walls YARD_WALL_H high and YARD_WALL_T thick, a gate GATE_W wide.
const YARD_D := Vector2(4.0, 6.5)
const L_YARD_CHANCE := 0.6
const YARD_WALL_H := 2.2
const YARD_WALL_T := 0.25
const GATE_W := 1.4
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
## Phase 3: the chance of a second storey ("storeys"; its rooms' roles by "upper", the stair
## landing in its "front" room), of an L shape (single storey, no yard behind), of a walled yard behind,
## and of a stair up onto the roof of a single-storey one ("roof"; two storeys always have one).
const TYPES := {
	"house": {"w": [8.0, 13.0], "d": [7.0, 11.0], "rooms": [4, 6], "front": "living", "back": "kitchen",
		"dark": ["bathroom", "storeroom"], "door_w": 0.9, "win_w": 1.0,
		"storeys": 0.3, "l_shape": 0.5, "yard": 0.4, "roof": 0.25,
		"upper": {"front": "living", "fill": ["bedroom"], "smallest": "bathroom", "rest": "bedroom"}},
	"shop": {"w": [7.0, 11.0], "d": [8.0, 12.0], "rooms": [3, 4], "front": "shopfront", "fill": ["storeroom", "office"],
		"smallest": "bathroom", "rest": "storeroom", "back": "storeroom", "dark": ["bathroom", "storeroom"], "door_w": 1.8, "win_w": 2.0,
		"storeys": 0.5, "l_shape": 0.0, "yard": 0.2, "roof": 0.2,
		"upper": {"front": "living", "fill": ["kitchen", "bedroom"], "smallest": "bathroom", "rest": "bedroom"}},
	"warehouse": {"w": [12.0, 18.0], "d": [10.0, 14.0], "rooms": [2, 3], "front": "hall", "fill": ["office", "storeroom"],
		"rest": "storeroom", "back": "hall", "dark": ["storeroom"], "door_w": 3.0, "win_w": 1.0, "first_cut": 0.72,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.25, "roof": 0.3},
	"clinic": {"w": [11.0, 15.0], "d": [10.0, 13.0], "rooms": [5, 6], "front": "reception", "fill": ["ward", "treatment", "office"],
		"smallest": "bathroom", "inner": "pharmacy", "rest": "ward", "back": "treatment", "dark": ["bathroom", "pharmacy"], "door_w": 1.2, "win_w": 1.2,
		"storeys": 0.4, "l_shape": 0.4, "yard": 0.15, "roof": 0.2,
		"upper": {"front": "ward", "fill": ["office", "ward"], "smallest": "bathroom", "rest": "ward"}},
	"police": {"w": [11.0, 15.0], "d": [9.0, 12.0], "rooms": [5, 6], "front": "front_desk", "fill": ["office", "cells", "storeroom"],
		"smallest": "bathroom", "inner": "armoury", "rest": "office", "back": "office", "dark": ["bathroom", "armoury", "cells", "storeroom"],
		"door_w": 1.2, "win_w": 1.0,
		"storeys": 0.4, "l_shape": 0.35, "yard": 0.35, "roof": 0.4,
		"upper": {"front": "office", "fill": ["storeroom", "office"], "smallest": "bathroom", "rest": "office"}},
}

static var _chunks: Array = []


## A house from `seed` in `style` (building("house", ...)).
static func house(seed: int, style := "") -> Dictionary:
	return building("house", seed, style)


## A building of `type` (TYPES) from `seed` in `style` (STYLES; "" picks one from the seed).
## Returns {"boxes": [[lo, hi, Mat]], "rooms": [{"role", "rect" (Rect2, x/z inside its walls),
## "chunk", "floor" (0 the ground), "y" (its floor's height, m)}], "doors": [{"at": Vector3,
## "rooms": [i, j] (j -1: outside, -2: the roof), "stair" (a stair up: "at" its landing)}],
## "loot": [{"at", "table"}], "stairs": [{"foot" (Rect2), "from_y", "to_y", "steps"}], "yards":
## [{"rect" (Rect2 inside its walls), "gate" (Vector3, or null)}], "size": Vector2 (the lot,
## yard and all), "storeys", "shape" ("rect" or "l"), "roof_access", "height" (m, its top),
## "style", "type"}. The shell stands at the front (+z) of the lot, a yard behind it.
static func building(type: String, seed: int, style := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if style == "":
		style = STYLES.keys()[rng.randi() % STYLES.size()]
	var st: Dictionary = STYLES[style]
	var spec: Dictionary = TYPES[type]
	var w := snappedf(rng.randf_range(spec.w[0], spec.w[1]), 0.1)
	var d := snappedf(rng.randf_range(spec.d[0], spec.d[1]), 0.1)
	var t: float = st.t
	var h: float = st.h
	var roof_t: float = st.roof_t
	var fh := h + SLAB_T  # floor to floor
	var slab_mat: int = VoxelWorld.Mat.WOOD if style == "mud" else VoxelWorld.Mat.CONCRETE
	var storeys := 2 if rng.randf() < float(spec.get("storeys", 0.0)) else 1
	var yard_d := snappedf(rng.randf_range(YARD_D.x, YARD_D.y), 0.1) if rng.randf() < float(spec.get("yard", 0.0)) else 0.0
	var depth := d + yard_d
	var outer := Rect2(-w * 0.5, -depth * 0.5 + yard_d, w, d)
	var inner := outer.grow(-t)
	# An L: a back corner left out (single storey, no yard behind).
	var cut := Rect2()
	if storeys == 1 and yard_d == 0.0 and rng.randf() < float(spec.get("l_shape", 0.0)):
		var nw := snappedf(inner.size.x * rng.randf_range(0.35, 0.5), 0.1)
		var nd := snappedf(inner.size.y * rng.randf_range(0.35, 0.5), 0.1)
		if nw >= MIN_ROOM and nd >= MIN_ROOM and inner.size.x - nw >= MIN_ROOM * 2.0 and inner.size.y - nd >= MIN_ROOM:
			cut = Rect2(inner.position.x if rng.randf() < 0.5 else inner.end.x - nw, inner.position.y, nw, nd)
	# The ground floor: its rooms, roles and doorways, the front door and a back door.
	var want := rng.randi_range(spec.rooms[0], spec.rooms[1])
	var plan := _plan(inner, cut, want, rng, float(spec.get("first_cut", -1.0)))
	if (plan.rects as Array).size() < int(spec.rooms[0]):  # too small an L for its rooms: whole
		cut = Rect2()
		plan = _plan(inner, cut, want, rng, float(spec.get("first_cut", -1.0)))
	var rects: Array[Rect2] = plan.rects
	var links := _links(rects)
	var roles := _house_roles(rects, links) if type == "house" else _roles(spec, rects)
	var n := rects.size()
	var hub := roles.find(spec.front)
	var bath := roles.find("bathroom")
	var floors: Array = [{"rects": rects, "splits": plan.splits, "roles": roles, "gaps": {}, "y": 0.0, "first": 0}]
	var gaps: Dictionary = floors[0].gaps
	var doors: Array = []
	_doorways(rects, links, hub, bath, rng, gaps, doors, 0, 0.0)
	var door_w: float = spec.door_w
	var front := hub if _side_len(hub, rects, "s") >= door_w + 2.0 * DOOR_EDGE else _nearest_side(rects, "s", bath)
	_outer_door(gaps, doors, rects, front, "s", rng, door_w)
	var back := roles.find(spec.back)
	for side: String in ["n", "e", "w"]:
		if back >= 0 and (back != front or side == "n") and _side_len(back, rects, side) >= DOOR_W + 2.0 * DOOR_EDGE:
			_outer_door(gaps, doors, rects, back, side, rng, maxf(DOOR_W, door_w if type == "warehouse" else DOOR_W))
			break
	# A second storey: a stair up from a ground-floor room; the walls above stand on the ones
	# below (so the stairwell and its landing are in one room up there too), the rooms given the
	# type's "upper" roles and doorways of their own.
	var stairs: Array = []
	var avoid := {}  # "floor:room" -> Rect2s furniture keeps off (stairs, stairwells, landings)
	var up := {}
	if storeys == 2:
		up = _stair(rects, roles, doors, 0, fh, [], rng)
		if up.is_empty():
			storeys = 1
	if storeys == 2:
		var hole: Rect2 = up.foot
		var hub2: int = up.room
		var roles2 := _upper_roles(spec.upper, rects, hub2)
		floors.append({"rects": rects, "splits": plan.splits, "roles": roles2, "gaps": {}, "y": fh, "first": n})
		_doorways(rects, links, hub2, roles2.find("bathroom"), rng, floors[1].gaps, doors, n, fh)
		var land: Vector2 = (up.land as Rect2).get_center()
		doors.append({"at": Vector3(land.x, fh, land.y), "rooms": [int(up.room), n + hub2], "stair": true})
		stairs.append({"foot": hole, "from_y": 0.0, "to_y": fh, "steps": int(up.steps)})
		avoid["0:%d" % up.room] = [hole.grow(0.7)]
		avoid["1:%d" % hub2] = [hole.grow(0.5), (up.land as Rect2).grow(0.3)]
	# Up onto the roof: two storeys always, one now and then.
	var top: Dictionary = floors.back()
	var roof_y: float = float(top.y) + h
	var roof := {}
	if storeys == 2 or rng.randf() < float(spec.get("roof", 0.0)):
		var keep_off: Array = []
		if storeys == 2:
			keep_off = [(up.foot as Rect2).grow(0.9), (up.land as Rect2).grow(0.3)]
		roof = _stair(top.rects, top.roles, doors, int(top.first), h + roof_t, keep_off, rng)
		if not roof.is_empty():
			var land: Vector2 = (roof.land as Rect2).get_center()
			doors.append({"at": Vector3(land.x, roof_y + roof_t, land.y), "rooms": [int(top.first) + int(roof.room), -2], "stair": true})
			stairs.append({"foot": roof.foot, "from_y": top.y, "to_y": roof_y + roof_t, "steps": int(roof.steps)})
			var key := "%d:%d" % [floors.size() - 1, roof.room]
			avoid[key] = (avoid.get(key, []) as Array) + [(roof.foot as Rect2).grow(0.7)]
	# Windows on outside walls, but not in the type's dark rooms (bathrooms, storerooms, an armoury).
	var win_w: float = spec.win_w
	for f: Dictionary in floors:
		var fr: Array[Rect2] = f.rects
		for i in fr.size():
			if f.roles[i] in (spec.dark as Array):
				continue
			for side: String in ["n", "s", "e", "w"]:
				var span := _side_span(i, fr, side)
				if span.y - span.x < maxf(WIN_WALL_MIN, win_w + 1.0):
					continue
				var mid := (span.x + span.y) * 0.5
				var key := _out_key(fr[i], side)
				if not _overlaps(f.gaps.get(key, []), mid - win_w * 0.5 - 0.3, mid + win_w * 0.5 + 0.3):
					_gap(f.gaps, key, mid - win_w * 0.5, mid + win_w * 0.5, WIN_SILL, WIN_TOP)
	# The walls, floor by floor; the slab between, the roof (with its parapet when it's used).
	var boxes: Array = []
	for f: Dictionary in floors:
		_shell(boxes, f.rects, f.gaps, t, f.y, h, st.wall)
		for sp: Array in f.splits:
			var key := "in:%d:%s" % [sp[0], snappedf(sp[1], 0.01)]
			_wall(boxes, 1 if sp[0] == 0 else 0, float(sp[1]) - INNER_T * 0.5, float(sp[1]) + INNER_T * 0.5, sp[2], sp[3], h, st.inner, f.gaps.get(key, []), f.y)
	if storeys == 2:
		_slab(boxes, rects, t, [up.foot], h, fh, slab_mat)
		_stair_boxes(boxes, up, 0.0, fh, slab_mat)
		_rails(boxes, up, fh)
	_slab(boxes, top.rects, t, [roof.foot] if not roof.is_empty() else [], roof_y, roof_y + roof_t, st.roof)
	if not roof.is_empty():
		_stair_boxes(boxes, roof, top.y, h + roof_t, slab_mat)
		_rails(boxes, roof, roof_y + roof_t)
		_shell(boxes, top.rects, {}, t, roof_y + roof_t, PARAPET_H, st.wall)
	# Furnish each room, floor by floor.
	var rooms: Array = []
	var loot: Array = []
	for fi in floors.size():
		var f: Dictionary = floors[fi]
		var fr: Array[Rect2] = f.rects
		for i in fr.size():
			var room := _room_rect(fr, i)
			var from_box := boxes.size()
			var from_loot := loot.size()
			var placed := _furnish(boxes, loot, room, f.roles[i], doors, int(f.first) + i, rng, avoid.get("%d:%d" % [fi, i], []))
			var lift := Vector3(0, f.y, 0)
			for k in range(from_box, boxes.size()):
				boxes[k] = [(boxes[k][0] as Vector3) + lift, (boxes[k][1] as Vector3) + lift, boxes[k][2]]
			for k in range(from_loot, loot.size()):
				loot[k].at = (loot[k].at as Vector3) + lift
			rooms.append({"role": f.roles[i], "rect": room, "chunk": placed, "floor": fi, "y": f.y})
	# Yards: walled, a gate to the side, a chunk of yard things.
	var yards: Array = []
	if yard_d > 0.0:
		yards.append(_yard(boxes, loot, Rect2(outer.position.x, -depth * 0.5, w, yard_d), ["n", "e", "w"], st.wall, doors, rng))
	elif cut.has_area() and rng.randf() < L_YARD_CHANCE:
		var left := cut.position.x <= inner.position.x + 0.01
		var yr := Rect2(outer.position.x, outer.position.y, cut.end.x - t - outer.position.x, cut.end.y - t - outer.position.y) if left \
			else Rect2(cut.position.x + t, outer.position.y, outer.end.x - cut.position.x - t, cut.end.y - t - outer.position.y)
		yards.append(_yard(boxes, loot, yr, ["n", "w" if left else "e"], st.wall, doors, rng))
	var height := roof_y + roof_t + (maxf(PARAPET_H, RAIL_H) if not roof.is_empty() else 0.0)
	return {"boxes": boxes, "rooms": rooms, "doors": doors, "loot": loot, "stairs": stairs, "yards": yards,
		"size": Vector2(w, depth), "storeys": storeys, "shape": "l" if cut.has_area() else "rect",
		"roof_access": not roof.is_empty(), "height": height, "style": style, "type": type}


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
static func _roles(spec: Dictionary, rects: Array[Rect2]) -> Array:
	var n := rects.size()
	var roles: Array = []
	roles.resize(n)
	roles.fill("")
	var front := _nearest_side(rects, "s")
	roles[front] = spec.front
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return rects[a].get_area() > rects[b].get_area())
	if spec.has("smallest") and n >= 4 and roles[order[n - 1]] == "":
		roles[order[n - 1]] = spec.smallest
	if spec.has("inner"):
		var outside := func(i: int) -> float:
			return _side_len(i, rects, "n") + _side_len(i, rects, "s") + _side_len(i, rects, "e") + _side_len(i, rects, "w")
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


## Rooms: `inner` (less `cut`, an L's missing back corner) split along the longer side until
## there are `want` of them, none narrower than MIN_ROOM. {"rects": Array[Rect2], "splits":
## [[axis (0: a wall at x, 1: at z), at, from, to]]}.
static func _plan(inner: Rect2, cut: Rect2, want: int, rng: RandomNumberGenerator, first_cut: float) -> Dictionary:
	var rects: Array[Rect2] = []
	var splits: Array = []
	if cut.has_area():
		var bx := cut.end.x if cut.position.x <= inner.position.x + 0.01 else inner.position.x
		var back := Rect2(bx, inner.position.y, inner.size.x - cut.size.x, cut.size.y)
		rects.append(Rect2(inner.position.x, cut.end.y, inner.size.x, inner.end.y - cut.end.y))
		rects.append(back)
		splits.append([1, cut.end.y, back.position.x, back.end.x])
	else:
		rects.append(inner)
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
			var share := first_cut if splits.is_empty() and first_cut > 0.0 else rng.randf_range(0.4, 0.6)
			var c := snappedf(clampf(span * share, MIN_ROOM + INNER_T * 0.5, span - MIN_ROOM - INNER_T * 0.5), 0.1)
			var a: Rect2
			var b: Rect2
			if axis == 0:
				var x := r.position.x + c
				a = Rect2(r.position, Vector2(c, r.size.y))
				b = Rect2(Vector2(x, r.position.y), Vector2(r.size.x - c, r.size.y))
				splits.append([0, x, r.position.y, r.end.y])
			else:
				var z := r.position.y + c
				a = Rect2(r.position, Vector2(r.size.x, c))
				b = Rect2(Vector2(r.position.x, z), Vector2(r.size.x, r.size.y - c))
				splits.append([1, z, r.position.x, r.end.x])
			rects.remove_at(i)
			rects.append(a)
			rects.append(b)
			done = true
			break
		if not done:
			break
	return {"rects": rects, "splits": splits}


## Which rooms share a wall long enough for a doorway: [i, j, axis, at, from, to].
static func _links(rects: Array[Rect2]) -> Array:
	var links: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var l := _shared(rects[i], rects[j])
			if not l.is_empty():
				links.append([i, j] + l)
	return links


## Doorways between a floor's rooms: a tree from `hub` (the bathroom a leaf, nothing through
## it), and now and then one loop. Rooms in `doors` are numbered from `first`; at height `y`.
static func _doorways(rects: Array[Rect2], links: Array, hub: int, bath: int, rng: RandomNumberGenerator, gaps: Dictionary, doors: Array, first: int, y: float) -> void:
	var n := rects.size()
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
	for l: Array in tree:
		var mid := (float(l[4]) + float(l[5])) * 0.5
		var lo := clampf(mid - DOOR_W * 0.5, float(l[4]) + DOOR_EDGE, float(l[5]) - DOOR_EDGE - DOOR_W)
		_gap(gaps, "in:%d:%s" % [l[2], snappedf(l[3], 0.01)], lo, lo + DOOR_W, 0.0, DOOR_H)
		var at := Vector3(l[3], y, lo + DOOR_W * 0.5) if l[2] == 0 else Vector3(lo + DOOR_W * 0.5, y, l[3])
		doors.append({"at": at, "rooms": [first + int(l[0]), first + int(l[1])]})


## An upper floor's room roles (a type's "upper"): the room the stair comes up into its
## "front", the smallest its "smallest" (three rooms or more), the rest "fill" biggest first,
## then "rest".
static func _upper_roles(upper: Dictionary, rects: Array[Rect2], hub: int) -> Array:
	var n := rects.size()
	var roles: Array = []
	roles.resize(n)
	roles.fill("")
	roles[hub] = upper.front
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return rects[a].get_area() > rects[b].get_area())
	if upper.has("smallest") and n >= 3 and order[n - 1] != hub:
		roles[order[n - 1]] = upper.smallest
	var fill: Array = (upper.get("fill", []) as Array).duplicate()
	for i: int in order:
		if roles[i] == "":
			roles[i] = fill.pop_front() if not fill.is_empty() else String(upper.get("rest", "bedroom"))
	return roles


## The room (index in `rects`) that `p` is in, or -1.
static func _room_at(rects: Array, p: Vector2) -> int:
	for i in rects.size():
		if (rects[i] as Rect2).has_point(p):
			return i
	return -1


## The room's floor inside its walls (a room's rect runs to the middle of its inner walls, and
## to the inside face of an outside wall).
static func _room_rect(rects: Array[Rect2], i: int) -> Rect2:
	var r := rects[i]
	var lo := r.position
	var hi := r.end
	var outside := func(side: String) -> bool:
		var ext := _exterior(i, rects, side)
		var length := r.size.x if side in ["n", "s"] else r.size.y
		return ext.size() == 1 and absf(ext[0].y - ext[0].x - length) < 0.01
	if not outside.call("w"):
		lo.x += INNER_T * 0.5
	if not outside.call("n"):
		lo.y += INNER_T * 0.5
	if not outside.call("e"):
		hi.x -= INNER_T * 0.5
	if not outside.call("s"):
		hi.y -= INNER_T * 0.5
	return Rect2(lo, hi - lo)


## Where room `r`'s `side` ("n": -z, "s": +z the street, "w", "e") edge runs.
static func _line(r: Rect2, side: String) -> float:
	match side:
		"n": return r.position.y
		"s": return r.end.y
		"w": return r.position.x
	return r.end.x


static func _out_key(r: Rect2, side: String) -> String:
	return "out:%s:%s" % [side, snappedf(_line(r, side), 0.01)]


## The stretches of room `i`'s `side` edge with no other room beyond them (outside walls):
## [from, to] along it (x for "n"/"s", z for "w"/"e").
static func _exterior(i: int, rects: Array[Rect2], side: String) -> Array[Vector2]:
	var r := rects[i]
	var line := _line(r, side)
	var along_x := side in ["n", "s"]
	var out: Array[Vector2] = [Vector2(r.position.x, r.end.x) if along_x else Vector2(r.position.y, r.end.y)]
	var facing := {"n": "s", "s": "n", "w": "e", "e": "w"}
	for j in rects.size():
		if j == i or absf(_line(rects[j], facing[side]) - line) > 0.01:
			continue
		var q := rects[j]
		var span := Vector2(q.position.x, q.end.x) if along_x else Vector2(q.position.y, q.end.y)
		var next: Array[Vector2] = []
		for iv: Vector2 in out:
			if span.y <= iv.x or span.x >= iv.y:
				next.append(iv)
				continue
			if span.x > iv.x + 0.01:
				next.append(Vector2(iv.x, span.x))
			if span.y < iv.y - 0.01:
				next.append(Vector2(span.y, iv.y))
		out = next
	return out


## The longest outside stretch of room `i`'s `side` edge ([from, to]; zero length if none).
static func _side_span(i: int, rects: Array[Rect2], side: String) -> Vector2:
	var best := Vector2.ZERO
	for iv: Vector2 in _exterior(i, rects, side):
		if iv.y - iv.x > best.y - best.x:
			best = iv
	return best


static func _side_len(i: int, rects: Array[Rect2], side: String) -> float:
	var s := _side_span(i, rects, side)
	return s.y - s.x


## The room with the most outside wall on `side`, not `skip` (the bathroom: its one doorway
## stays the one inside).
static func _nearest_side(rects: Array[Rect2], side: String, skip := -1) -> int:
	var best := 0 if skip != 0 else 1
	for i in rects.size():
		if i != skip and _side_len(i, rects, side) > _side_len(best, rects, side):
			best = i
	return best


static func _outer_door(gaps: Dictionary, doors: Array, rects: Array[Rect2], room: int, side: String, rng: RandomNumberGenerator, width := DOOR_W) -> void:
	var span := _side_span(room, rects, side)
	width = minf(width, span.y - span.x - DOOR_EDGE * 2.0)
	if width < DOOR_W:
		return
	var lo := snappedf(rng.randf_range(span.x + DOOR_EDGE, span.y - DOOR_EDGE - width), 0.1)
	_gap(gaps, _out_key(rects[room], side), lo, lo + width, 0.0, DOOR_H + (0.4 if width >= 2.5 else 0.0))
	var c := lo + width * 0.5
	var line := _line(rects[room], side)
	doors.append({"at": Vector3(c, 0, line) if side in ["n", "s"] else Vector3(line, 0, c), "rooms": [room, -1]})


## The floor kept clear in front of doorway `at` in `room` (its width and a little along its
## wall, DOOR_CLEAR out from it).
static func _door_clear(at: Vector3, room: Rect2) -> Rect2:
	var along := DOOR_W * 0.5 + 0.2
	var in_x_wall := minf(absf(at.x - room.position.x), absf(at.x - room.end.x)) < minf(absf(at.z - room.position.y), absf(at.z - room.end.y))
	if in_x_wall:  # the doorway is in a wall at x (it runs along z)
		return Rect2(at.x - DOOR_CLEAR, at.z - along, DOOR_CLEAR * 2.0, along * 2.0)
	return Rect2(at.x - along, at.z - DOOR_CLEAR, along * 2.0, DOOR_CLEAR * 2.0)


# --- Stairs (phase 3) --------------------------------------------------------------------------

## A stair up `rise` m in one of a floor's rooms (`rects`, numbered from `first` in `doors`; not
## a bathroom; the biggest first): along a wall from a corner, clear of every doorway's floor
## and of `keep` (Rect2s), with STAIR_LANDING free past its top in the same room. {"room",
## "foot" (Rect2), "side" (its wall), "along_x", "low" (where its foot is, along), "up" (1 or
## -1: which way it climbs), "steps", "land" (Rect2: the landing)}, or {} if none fits.
static func _stair(rects: Array[Rect2], roles: Array, doors: Array, first: int, rise: float, keep: Array, rng: RandomNumberGenerator) -> Dictionary:
	var steps := ceili(rise / STAIR_RISE)
	var run := steps * STAIR_TREAD
	var order: Array = range(rects.size())
	order.sort_custom(func(a: int, b: int) -> bool: return rects[a].get_area() > rects[b].get_area())
	for i: int in order:
		if roles[i] == "bathroom":
			continue
		var room := _room_rect(rects, i)
		var clear: Array = keep.duplicate()
		for dr: Dictionary in doors:
			if first + i in dr.rooms:
				clear.append(_door_clear(dr.at, room))
		var options: Array = []
		for side: String in ["n", "s", "w", "e"]:
			var along_x := side in ["n", "s"]
			var length := room.size.x if along_x else room.size.y
			var across := room.size.y if along_x else room.size.x
			if length >= run + STAIR_LANDING + FURNITURE_GAP * 2.0 and across >= STAIR_W + 0.9:
				options.append([side, 1])
				options.append([side, -1])
		for k in range(options.size() - 1, 0, -1):
			var j := rng.randi() % (k + 1)
			var o: Array = options[k]
			options[k] = options[j]
			options[j] = o
		for o: Array in options:
			var side: String = o[0]
			var up: int = o[1]
			var along_x := side in ["n", "s"]
			var low := ((room.position.x if along_x else room.position.y) + FURNITURE_GAP) if up == 1 \
				else ((room.end.x if along_x else room.end.y) - FURNITURE_GAP)
			var high := low + up * run
			var c0: float
			match side:
				"n": c0 = room.position.y
				"s": c0 = room.end.y - STAIR_W
				"w": c0 = room.position.x
				_: c0 = room.end.x - STAIR_W
			var a0 := minf(low, high)
			var l0 := high if up == 1 else high - STAIR_LANDING
			var foot := Rect2(a0, c0, run, STAIR_W) if along_x else Rect2(c0, a0, STAIR_W, run)
			var land := Rect2(l0, c0, STAIR_LANDING, STAIR_W) if along_x else Rect2(c0, l0, STAIR_W, STAIR_LANDING)
			if clear.any(func(r: Rect2) -> bool: return r.intersects(foot.grow(0.05)) or r.intersects(land)):
				continue
			return {"room": i, "foot": foot, "side": side, "along_x": along_x, "low": low, "up": up, "steps": steps, "land": land}
	return {}


## Stair `s`'s steps, solid from `y0`, climbing `rise` m in all.
static func _stair_boxes(out: Array, s: Dictionary, y0: float, rise: float, mat: int) -> void:
	var steps: int = s.steps
	var f: Rect2 = s.foot
	var up: int = s.up
	for k in steps:
		var a0: float = float(s.low) + up * k * STAIR_TREAD
		var a1 := a0 + up * STAIR_TREAD
		var top := y0 + rise * (k + 1) / steps
		if s.along_x:
			out.append([Vector3(minf(a0, a1), y0, f.position.y), Vector3(maxf(a0, a1), top, f.end.y), mat])
		else:
			out.append([Vector3(f.position.x, y0, minf(a0, a1)), Vector3(f.end.x, top, maxf(a0, a1)), mat])


## A railing round stair `s`'s stairwell at height `y`: along its open side and across its foot
## (the top end is the way off).
static func _rails(out: Array, s: Dictionary, y: float) -> void:
	var f: Rect2 = s.foot
	var mat: int = VoxelWorld.Mat.STEEL
	var yt := y + RAIL_H
	match String(s.side):
		"n": out.append([Vector3(f.position.x, y, f.end.y), Vector3(f.end.x, yt, f.end.y + RAIL_T), mat])
		"s": out.append([Vector3(f.position.x, y, f.position.y - RAIL_T), Vector3(f.end.x, yt, f.position.y), mat])
		"w": out.append([Vector3(f.end.x, y, f.position.y), Vector3(f.end.x + RAIL_T, yt, f.end.y), mat])
		_: out.append([Vector3(f.position.x - RAIL_T, y, f.position.y), Vector3(f.position.x, yt, f.end.y), mat])
	var low: float = s.low
	var l0 := low - RAIL_T if int(s.up) == 1 else low
	if s.along_x:
		out.append([Vector3(l0, y, f.position.y), Vector3(l0 + RAIL_T, yt, f.end.y), mat])
	else:
		out.append([Vector3(f.position.x, y, l0), Vector3(f.end.x, yt, l0 + RAIL_T), mat])


# --- Walls -----------------------------------------------------------------------------------

static func _gap(gaps: Dictionary, key: String, from: float, to: float, bottom: float, top: float) -> void:
	if not gaps.has(key):
		gaps[key] = []
	(gaps[key] as Array).append([from, to, bottom, top])


static func _overlaps(list: Array, from: float, to: float) -> bool:
	return list.any(func(g: Array) -> bool: return g[0] < to and g[1] > from)


## A wall `h` tall standing at `base` with its gaps (doorways, windows: [from, to, bottom, top]
## along it, from its base): `axis` 0 runs along x (from `lo`..`hi` in z thick), 1 along z (from
## `lo`..`hi` in x thick).
static func _wall(out: Array, axis: int, lo: float, hi: float, from: float, to: float, h: float, mat: int, gaps: Array, base := 0.0) -> void:
	var box := func(a0: float, a1: float, y0: float, y1: float) -> void:
		if a1 - a0 < 0.05 or y1 - y0 < 0.05:
			return
		if axis == 0:
			out.append([Vector3(a0, base + y0, lo), Vector3(a1, base + y1, hi), mat])
		else:
			out.append([Vector3(lo, base + y0, a0), Vector3(hi, base + y1, a1), mat])
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


## A floor's outside walls (`t` thick, outside its rooms' edges, `h` tall from `base`) round
## whatever shape its rooms make, with their gaps (keyed by _out_key); turned out at the
## outside corners so they close.
static func _shell(out: Array, rects: Array[Rect2], gaps: Dictionary, t: float, base: float, h: float, mat: int) -> void:
	for i in rects.size():
		var r := rects[i]
		for side: String in ["n", "s", "w", "e"]:
			var line := _line(r, side)
			var g: Array = gaps.get(_out_key(r, side), [])
			for iv: Vector2 in _exterior(i, rects, side):
				var from := iv.x - (t if _corner(rects, side, line, iv.x, -1.0) else 0.0)
				var to := iv.y + (t if _corner(rects, side, line, iv.y, 1.0) else 0.0)
				match side:
					"n": _wall(out, 0, line - t, line, from, to, h, mat, g, base)
					"s": _wall(out, 0, line, line + t, from, to, h, mat, g, base)
					"w": _wall(out, 1, line - t, line, from, to, h, mat, g, base)
					_: _wall(out, 1, line, line + t, from, to, h, mat, g, base)


## Whether an outside wall's end at `along` (on `side`'s `line`, `dir` the way past its end) is
## an outside corner: just past it, inside the line, is no room.
static func _corner(rects: Array[Rect2], side: String, line: float, along: float, dir: float) -> bool:
	var a := along + dir * 0.01
	var p: Vector2
	match side:
		"n": p = Vector2(a, line + 0.01)
		"s": p = Vector2(a, line - 0.01)
		"w": p = Vector2(line + 0.01, a)
		_: p = Vector2(line - 0.01, a)
	return _room_at(rects, p) < 0


## A slab over a floor's rooms (out over their outside walls, `t`), from `y0` to `y1`, with
## `holes` (Rect2s: stairwells) left open.
static func _slab(out: Array, rects: Array[Rect2], t: float, holes: Array, y0: float, y1: float, mat: int) -> void:
	for i in rects.size():
		var g := rects[i].grow_individual(t if not _exterior(i, rects, "w").is_empty() else 0.0, t if not _exterior(i, rects, "n").is_empty() else 0.0,
			t if not _exterior(i, rects, "e").is_empty() else 0.0, t if not _exterior(i, rects, "s").is_empty() else 0.0)
		var pieces: Array[Rect2] = [g]
		for hole: Rect2 in holes:
			var next: Array[Rect2] = []
			for p: Rect2 in pieces:
				var c := p.intersection(hole)
				if not c.has_area():
					next.append(p)
					continue
				if c.position.y > p.position.y:
					next.append(Rect2(p.position.x, p.position.y, p.size.x, c.position.y - p.position.y))
				if c.end.y < p.end.y:
					next.append(Rect2(p.position.x, c.end.y, p.size.x, p.end.y - c.end.y))
				if c.position.x > p.position.x:
					next.append(Rect2(p.position.x, c.position.y, c.position.x - p.position.x, c.size.y))
				if c.end.x < p.end.x:
					next.append(Rect2(c.end.x, c.position.y, p.end.x - c.end.x, c.size.y))
			pieces = next
		for p: Rect2 in pieces:
			out.append([Vector3(p.position.x, y0, p.position.y), Vector3(p.end.x, y1, p.end.y), mat])


## A walled yard on `yr` (its outside edge): walls on `sides` (the others are the building's),
## a gate in one of them, furnished from the "yard" chunks. {"rect" (inside its walls), "gate"
## (Vector3, or null if no wall is long enough), "chunk"}.
static func _yard(out: Array, loot: Array, yr: Rect2, sides: Array, mat: int, doors: Array, rng: RandomNumberGenerator) -> Dictionary:
	var yt := YARD_WALL_T
	var gate_side: String = sides[rng.randi() % sides.size()]
	var order: Array = [gate_side] + sides.filter(func(sd: String) -> bool: return sd != gate_side)
	var gate: Variant = null
	var walls := {}
	for side: String in sides:
		match side:
			"n": walls[side] = [0, yr.position.y, yr.position.y + yt, yr.position.x, yr.end.x]
			"w": walls[side] = [1, yr.position.x, yr.position.x + yt, yr.position.y + yt, yr.end.y]
			_: walls[side] = [1, yr.end.x - yt, yr.end.x, yr.position.y + yt, yr.end.y]
	var gaps := {}
	for side: String in order:
		var wl: Array = walls[side]
		if gate == null and float(wl[4]) - float(wl[3]) >= GATE_W + 0.6:
			var g0 := snappedf(rng.randf_range(float(wl[3]) + 0.3, float(wl[4]) - 0.3 - GATE_W), 0.1)
			gaps[side] = [[g0, g0 + GATE_W, 0.0, YARD_WALL_H]]
			var c := g0 + GATE_W * 0.5
			var mid := (float(wl[1]) + float(wl[2])) * 0.5
			gate = Vector3(c, 0, mid) if int(wl[0]) == 0 else Vector3(mid, 0, c)
	for side: String in sides:
		var wl: Array = walls[side]
		_wall(out, wl[0], wl[1], wl[2], wl[3], wl[4], YARD_WALL_H, mat, gaps.get(side, []))
	var inside := yr.grow_individual(-yt if "w" in sides else 0.0, -yt, -yt if "e" in sides else 0.0, 0.0)
	var ways: Array = []
	if gate != null:
		ways.append({"at": gate, "rooms": [-9, -1]})
	for dr: Dictionary in doors:
		if int(dr.rooms[1]) == -1 and inside.grow(0.6).has_point(Vector2((dr.at as Vector3).x, (dr.at as Vector3).z)):
			ways.append({"at": dr.at, "rooms": [-9, -1]})
	var chunk := _furnish(out, loot, inside, "yard", ways, -9, rng)
	return {"rect": inside, "gate": gate, "chunk": chunk}


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
## `keep` (Rect2s) is floor furniture stays off too (a stair and its landing); a wall with any
## of it against it counts as blocked, like one with a doorway.
static func _furnish(boxes: Array, loot: Array, room: Rect2, role: String, doors: Array, index: int, rng: RandomNumberGenerator, keep: Array = []) -> String:
	var mine := doors.filter(func(dr: Dictionary) -> bool: return index in dr.rooms and not dr.get("stair", false))
	# Kept clear: the doorway's width (and a little) along its wall, DOOR_CLEAR out from it.
	var clear: Array[Rect2] = []
	for dr: Dictionary in mine:
		clear.append(_door_clear(dr.at, room))
	for r: Rect2 in keep:
		clear.append(r)
	# Walls: [side, length, whether a doorway (or a stair) is against it].
	var walls: Array = []
	for side: String in ["n", "s", "e", "w"]:
		var along := room.size.x if side in ["n", "s"] else room.size.y
		var strip: Rect2
		match side:
			"n": strip = Rect2(room.position.x, room.position.y, room.size.x, 0.3)
			"s": strip = Rect2(room.position.x, room.end.y - 0.3, room.size.x, 0.3)
			"w": strip = Rect2(room.position.x, room.position.y, 0.3, room.size.y)
			_: strip = Rect2(room.end.x - 0.3, room.position.y, 0.3, room.size.y)
		var blocked := mine.any(func(dr: Dictionary) -> bool: return _door_on(dr.at, room, side)) \
			or keep.any(func(r: Rect2) -> bool: return r.intersects(strip))
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
## What lies at a building's loot spots in a town, by the spot's table: [item id, count]
## choices; tables not listed hold nothing yet. At most TOWN_LOOT_MAX in a town.
const TOWN_LOOT := {
	"medical": [["ifak", 1]], "ward": [["ifak", 1]],
	"armoury": [["mag_556", 2], ["rounds_762", 40], ["frag_grenade", 2]],
	"warehouse": [["electronics_salvage", 2]], "storeroom": [["electronics_salvage", 1], ["smoke_grenade", 1]],
	"house_store": [["rounds_556", 30]], "office": [["electronics_salvage", 1]], "yard": [["smoke_grenade", 1]],
}
const TOWN_LOOT_MAX := 10
## Every TOWN_CIVILIAN_EVERY'th building has someone living or working there, walking between
## their front step, the street and the crossroads.
const TOWN_CIVILIAN_EVERY := 3
## Lot types by where they are along the street (0 the middle .. 1 the end): weights.
const TOWN_MIX := {"house": 6.0, "shop": 2.5, "warehouse": 1.0, "clinic": 0.6, "police": 0.6}


## The town from `seed`: {"boxes", "buildings": [{"type", "origin" (Vector3), "turned" (180
## degrees), "data" (building())}], "half" (Vector2: footprint half-size, m), "points"
## ({"objective", "cache", "intel"}: Array of Vector3), "garrison" (Array of Vector3), "loot"
## (ZoneModules.LOOT entries: {"uid", "id", "count", "pos"}), "hvt" and "hostage" (Vector3: the
## middle of the room an HVT lives in, an office or a living room, and of the room a hostage is
## held in, the police cells or a store room), "civilians" ({"pos", "routine"},
## as contracts.json module "civilians", in arrays), "style"}.
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
	var loot: Array = []
	var civilians: Array = []
	var arr := func(p: Vector3) -> Array: return [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
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
			if TOWN_LOOT.has(t) and loot.size() < TOWN_LOOT_MAX:
				var choices: Array = TOWN_LOOT[t]
				var pick: Array = choices[rng.randi() % choices.size()]
				loot.append({"uid": "loot%d" % loot.size(), "id": pick[0], "count": int(pick[1]), "pos": where + Vector3(0, 0.5, 0)})
		var i := buildings.find(b)
		if i % TOWN_CIVILIAN_EVERY == 1:
			for dr: Dictionary in b.data.doors:
				if dr.rooms[1] == -1 and (dr.at as Vector3).z > 0.0:
					var step: Vector3 = to_town.call((dr.at as Vector3) + Vector3(0, 0, 1.2))
					var across := Vector3(step.x + rng.randf_range(-6.0, 6.0), 0, -signf(step.z) * rng.randf_range(0.5, STREET_W * 0.4))
					var corner := Vector3(signf(step.x) * CROSS_W * 0.3, 0, rng.randf_range(-STREET_W, STREET_W) * 0.3)
					civilians.append({"pos": arr.call(step + Vector3(0, 0.1, 0)), "routine": [arr.call(step), arr.call(across), arr.call(corner)]})
					break
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
	return {"boxes": boxes, "buildings": buildings, "half": half, "points": points, "garrison": garrison,
		"loot": loot, "civilians": civilians, "style": style,
		"hvt": _town_room(buildings, ["office", "living"], Vector3(-CROSS_W, 0.1, 0)),
		"hostage": _town_room(buildings, ["cells", "storeroom", "house_store", "store"], Vector3(CROSS_W, 0.1, 0))}


## The middle of the first room (in town metres, on the floor) whose role is the earliest of
## `roles` in any building of a town; `fallback` if none has one.
static func _town_room(buildings: Array, roles: Array, fallback: Vector3) -> Vector3:
	for role: String in roles:
		for b: Dictionary in buildings:
			for r: Dictionary in b.data.rooms:
				if r.role == role:
					var c: Vector2 = (r.rect as Rect2).get_center()
					var p := Vector3(c.x, float(r.get("y", 0.0)) + 0.1, c.y)
					return (Vector3(-p.x, p.y, -p.z) if b.turned else p) + (b.origin as Vector3)
	return fallback


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
