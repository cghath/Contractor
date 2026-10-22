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
## The narrowest a room may be (m), and how much wall a doorway keeps either side of it. A
## doorway is DOOR_W wide (a type's outside door "door_w" at least as wide): the navmesh's
## 0.25 m cells, a cell lost to a wall face lying on a cell edge and one eroded off each side
## for the soldier's radius left a 0.9 m doorway no way through wherever an edge fell on a cell
## edge (rooms cut off, AI never in them; F-01). 1.1 m always leaves a cell.
const MIN_ROOM := 2.6
const DOOR_W := 1.1
const DOOR_H := 2.1
const DOOR_EDGE := 0.2
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
## clear past its top, and a railing RAIL_H high round its stairwell above. The rise is whole
## 0.1 m voxels (a 0.23 m rise, built as voxels, came out 0.2 or 0.3 m, and a soldier steps up
## 0.27 m at most: SoldierMovement.WORLD_STEP_M). The navmesh doesn't bake the steps (a 0.25 m
## tread, built as voxels, is 0.2 or 0.3 m deep, and a 0.25 m navmesh cell over three of them
## climbs two steps at once, cutting the stair in two): it bakes ramp_faces() over them (F-01).
const SLAB_T := 0.2
const STAIR_W := 1.0
const STAIR_RISE := 0.2
const STAIR_TREAD := 0.25
const STAIR_LANDING := 0.8
## Floor left clear in front of a stair's first step, so one walks onto it head on: a foot right
## against the end wall could only be stepped onto from the side, where the navmesh, eroded
## along the wall and the stair's open side, left no way on (F-01).
const STAIR_APPROACH := 0.5
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
		"dark": ["bathroom", "storeroom"], "door_w": 1.1, "win_w": 1.0,
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
	# Landmarks (queue item 1.4, cghath 2026-10-21; docs/building_gen.md "Landmarks"). Keys only
	# they use (Proposed): "styles" the styles it's built in (one picked from the seed), "h" its
	# wall height (m), "door_h" its front door's height, "apron" [min, max] m of open lot in front
	# of its front wall (a forecourt, a tower's or a canopy's room), "keep_big" the bigger part of
	# its first split stays one room (a prayer hall, a nave, a factory floor, a hangar),
	# "chunk_area" one more interior chunk for every this many m² of a room (big halls),
	# "sign" a sign over its front door, "extras" what's built round its shell (_extras: a dome
	# and a minaret, a bell tower, a canopy, a chimney, a gable roof).
	"office": {"w": [12.0, 16.0], "d": [9.0, 12.0], "rooms": [5, 6], "front": "reception", "fill": ["open_office", "meeting", "office"],
		"smallest": "bathroom", "inner": "storeroom", "rest": "office", "back": "office", "dark": ["bathroom", "storeroom"], "door_w": 1.6, "win_w": 1.6,
		"storeys": 1.0, "l_shape": 0.0, "yard": 0.0, "roof": 1.0, "styles": ["block", "brick"], "sign": true, "extras": "office",
		"upper": {"front": "open_office", "fill": ["meeting", "office"], "smallest": "bathroom", "rest": "office"}},
	"mosque": {"w": [14.0, 18.0], "d": [10.0, 12.5], "rooms": [3, 4], "first_cut": 0.66, "keep_big": true, "front": "prayer_hall",
		"fill": ["ablution", "office"], "rest": "storeroom", "back": "prayer_hall", "dark": ["ablution", "storeroom"], "door_w": 2.0, "win_w": 1.2,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.4, "roof": 0.0, "h": 4.2, "apron": [3.2, 4.2], "chunk_area": 14.0, "extras": "mosque"},
	"church": {"w": [9.0, 12.0], "d": [16.0, 21.0], "rooms": [2, 3], "first_cut": 0.24, "keep_big": true, "front": "nave",
		"fill": ["vestry", "office"], "rest": "storeroom", "back": "vestry", "dark": ["storeroom"], "door_w": 2.0, "win_w": 1.0,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.3, "roof": 0.0, "h": 4.6, "apron": [4.2, 5.2], "chunk_area": 16.0,
		"styles": ["stone", "brick"], "extras": "church"},
	"school": {"w": [16.0, 22.0], "d": [10.0, 12.5], "rooms": [5, 7], "front": "reception", "fill": ["classroom", "classroom", "office", "classroom"],
		"smallest": "bathroom", "rest": "classroom", "back": "classroom", "dark": ["bathroom", "storeroom"], "door_w": 1.8, "win_w": 1.6,
		"storeys": 0.6, "l_shape": 0.3, "yard": 0.7, "roof": 0.3, "apron": [2.6, 3.4], "styles": ["block", "brick", "stone"], "sign": true, "extras": "school",
		"upper": {"front": "classroom", "fill": ["classroom", "classroom", "office"], "smallest": "bathroom", "rest": "classroom"}},
	"garage": {"w": [11.0, 14.0], "d": [8.0, 10.5], "rooms": [2, 3], "first_cut": 0.68, "keep_big": true, "front": "workshop",
		"fill": ["office", "storeroom"], "rest": "storeroom", "back": "workshop", "dark": ["storeroom"], "door_w": 3.4, "door_h": 3.0, "win_w": 1.2,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.4, "roof": 0.2, "h": 3.6, "apron": [4.0, 6.0], "chunk_area": 18.0,
		"styles": ["block", "brick", "mud"], "sign": true, "extras": "garage"},
	"fuel_station": {"w": [8.0, 10.0], "d": [6.0, 8.0], "rooms": [2, 3], "front": "shopfront", "fill": ["storeroom", "office"],
		"rest": "storeroom", "back": "storeroom", "dark": ["storeroom"], "door_w": 1.8, "win_w": 2.0,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.3, "roof": 0.0, "apron": [11.0, 12.0], "styles": ["block", "brick"], "sign": true, "extras": "fuel_station"},
	"factory": {"w": [20.0, 26.0], "d": [13.0, 17.0], "rooms": [3, 5], "first_cut": 0.7, "keep_big": true, "front": "factory_floor",
		"fill": ["office", "storeroom", "office"], "smallest": "bathroom", "rest": "storeroom", "back": "factory_floor", "dark": ["bathroom", "storeroom"],
		"door_w": 3.6, "door_h": 3.2, "win_w": 1.6, "storeys": 0.0, "l_shape": 0.0, "yard": 0.35, "roof": 0.35, "h": 4.8, "apron": [5.0, 7.0],
		"chunk_area": 22.0, "styles": ["brick", "block"], "sign": true, "extras": "factory"},
	"farmhouse": {"w": [9.0, 13.0], "d": [7.0, 10.0], "rooms": [4, 6], "front": "living", "back": "kitchen",
		"dark": ["bathroom", "storeroom"], "door_w": 1.1, "win_w": 1.0, "storeys": 0.35, "l_shape": 0.4, "yard": 0.0, "roof": 0.3,
		"styles": ["stone", "mud", "brick"], "extras": "farmhouse",
		"upper": {"front": "living", "fill": ["bedroom"], "smallest": "bathroom", "rest": "bedroom"}},
	"barn": {"w": [12.0, 16.0], "d": [8.0, 10.5], "rooms": [1, 2], "first_cut": 0.75, "keep_big": true, "front": "barn", "fill": ["storeroom"],
		"rest": "storeroom", "back": "barn", "dark": ["storeroom"], "door_w": 3.4, "door_h": 3.0, "win_w": 1.0,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.0, "roof": 0.0, "h": 4.0, "chunk_area": 16.0, "styles": ["stone", "brick", "block", "mud"], "extras": "barn"},
	"harbour_shed": {"w": [14.0, 18.0], "d": [10.0, 12.0], "rooms": [2, 3], "first_cut": 0.72, "keep_big": true, "front": "dock_hall",
		"fill": ["office", "storeroom"], "rest": "storeroom", "back": "dock_hall", "dark": ["storeroom"], "door_w": 4.0, "door_h": 3.2, "win_w": 1.0,
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.0, "roof": 0.0, "h": 4.4, "chunk_area": 20.0, "styles": ["block"], "sign": true, "extras": "shed"},
	"hangar": {"w": [22.0, 26.0], "d": [16.0, 19.0], "rooms": [2, 2], "first_cut": 0.8, "keep_big": true, "front": "hangar", "fill": ["office"],
		"rest": "storeroom", "back": "hangar", "dark": ["storeroom"], "door_w": 14.0, "door_h": 5.0, "win_w": 1.2, "apron": [1.0, 1.4],
		"storeys": 0.0, "l_shape": 0.0, "yard": 0.0, "roof": 0.0, "h": 6.2, "chunk_area": 40.0, "styles": ["block"], "extras": "hangar"},
	"control_tower": {"w": [7.0, 8.5], "d": [7.0, 8.5], "rooms": [1, 2], "front": "office", "fill": ["storeroom"], "rest": "storeroom", "back": "office",
		"dark": ["storeroom"], "door_w": 1.2, "win_w": 1.8, "storeys": 1.0, "l_shape": 0.0, "yard": 0.0, "roof": 1.0, "styles": ["block"], "extras": "tower",
		"upper": {"front": "tower_cab", "rest": "tower_cab"}},
	"pumphouse": {"w": [6.0, 8.0], "d": [5.0, 6.5], "rooms": [1, 2], "front": "plant", "fill": ["office"], "rest": "storeroom", "back": "plant",
		"dark": ["storeroom"], "door_w": 1.6, "win_w": 1.0, "storeys": 0.0, "l_shape": 0.0, "yard": 0.0, "roof": 0.0, "h": 3.0, "apron": [1.6, 2.2],
		"styles": ["block"], "extras": "pumphouse"},
	"drug_lab": {"w": [9.0, 12.0], "d": [8.0, 10.5], "rooms": [3, 4], "front": "lab", "fill": ["lab", "storeroom"], "smallest": "bathroom",
		"rest": "storeroom", "back": "storeroom", "dark": ["lab", "storeroom", "bathroom"], "door_w": 1.1, "win_w": 1.0,
		"storeys": 0.0, "l_shape": 0.3, "yard": 0.8, "roof": 0.0, "styles": ["mud", "block"], "extras": "drug_lab"},
	"ied_workshop": {"w": [8.0, 11.0], "d": [7.0, 10.0], "rooms": [2, 4], "front": "bomb_workshop", "fill": ["storeroom", "bedroom"],
		"rest": "storeroom", "back": "bomb_workshop", "dark": ["storeroom"], "door_w": 1.1, "win_w": 0.8,
		"storeys": 0.2, "l_shape": 0.3, "yard": 0.7, "roof": 0.3, "styles": ["mud", "block", "stone"], "extras": "ied_workshop",
		"upper": {"front": "bedroom", "fill": ["storeroom"], "rest": "bedroom"}},
}
## The landmark building types (queue item 1.4): each has a ruined and a bombed-out variant
## (building(type, seed, style, RUINED / BOMBED)).
const LANDMARK_TYPES: Array[String] = ["office", "mosque", "church", "school", "garage", "fuel_station", "factory", "farmhouse", "barn",
	"harbour_shed", "hangar", "control_tower", "pumphouse", "drug_lab", "ied_workshop"]
const INTACT := 0
const RUINED := 1
const BOMBED := 2

static var _chunks: Array = []


## A house from `seed` in `style` (building("house", ...)).
static func house(seed: int, style := "") -> Dictionary:
	return building("house", seed, style)


## A building of `type` (TYPES) from `seed` in `style` (STYLES; "" picks one from the seed).
## Returns {"boxes": [[lo, hi, Mat]], "rooms": [{"role", "rect" (Rect2, x/z inside its walls),
## "chunk", "floor" (0 the ground), "y" (its floor's height, m)}], "doors": [{"at": Vector3,
## "rooms": [i, j] (j -1: outside, -2: the roof), "stair" (a stair up: "at" its landing)}],
## "windows": [{"at" (the middle of its opening's inner face, on its floor), "out" (Vector3 out
## of it), "floor", "room"}], "roof_y" (the roof's top: where one stands on it), "loot":
## [{"at", "table"}], "stairs": [{"foot" (Rect2), "from_y", "to_y", "steps", "low", "up",
## "along_x" (as _stair)}], "yards": [{"rect" (Rect2 inside its walls), "gate" (Vector3, or
## null)}], "size": Vector2 (the lot, yard and all), "storeys", "shape" ("rect" or "l"),
## "roof_access", "height" (m, its top), "style", "type", "ruin" (INTACT, RUINED, BOMBED),
## "buried" (doorways under a collapse's rubble: their "at"s), "apron" (m of open lot in front)}. The shell stands at the
## front (+z) of the lot, a yard behind it (and a landmark's "apron" in front of it).
## `ruin`: RUINED or BOMBED makes its ruined or bombed-out variant (_ruin): the same building
## (rooms, doors, loot) with walls breached, roofs fallen in, rubble.
static func building(type: String, seed: int, style := "", ruin := INTACT) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spec: Dictionary = TYPES[type]
	if style == "":
		var allowed: Array = spec.get("styles", STYLES.keys())
		style = allowed[rng.randi() % allowed.size()]
	var st: Dictionary = STYLES[style]
	var look := _look(style, type, seed)  # its own colours (a random stream of its own: the layout below is as it was)
	var w := snappedf(rng.randf_range(spec.w[0], spec.w[1]), 0.1)
	var d := snappedf(rng.randf_range(spec.d[0], spec.d[1]), 0.1)
	var t: float = st.t
	var h: float = float(spec.get("h", st.h))
	var roof_t: float = st.roof_t
	var fh := h + SLAB_T  # floor to floor
	var slab_mat: int = VoxelWorld.Mat.WOOD if style == "mud" else VoxelWorld.Mat.CONCRETE
	var storeys := 2 if rng.randf() < float(spec.get("storeys", 0.0)) else 1
	var yard_d := snappedf(rng.randf_range(YARD_D.x, YARD_D.y), 0.1) if rng.randf() < float(spec.get("yard", 0.0)) else 0.0
	var apron := snappedf(rng.randf_range(spec.apron[0], spec.apron[1]), 0.1) if spec.has("apron") else 0.0
	var depth := d + yard_d + apron
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
	var keep_big := bool(spec.get("keep_big", false))
	var plan := _plan(inner, cut, want, rng, float(spec.get("first_cut", -1.0)), keep_big)
	if (plan.rects as Array).size() < int(spec.rooms[0]):  # too small an L for its rooms: whole
		cut = Rect2()
		plan = _plan(inner, cut, want, rng, float(spec.get("first_cut", -1.0)), keep_big)
	var rects: Array[Rect2] = plan.rects
	var links := _links(rects)
	var roles := _house_roles(rects, links) if type in ["house", "farmhouse"] else _roles(spec, rects)
	var n := rects.size()
	var hub := roles.find(spec.front)
	var bath := roles.find("bathroom")
	var floors: Array = [{"rects": rects, "splits": plan.splits, "roles": roles, "gaps": {}, "y": 0.0, "first": 0}]
	var gaps: Dictionary = floors[0].gaps
	var doors: Array = []
	_doorways(rects, links, hub, bath, rng, gaps, doors, 0, 0.0)
	var door_w: float = spec.door_w
	var front := hub if _side_len(hub, rects, "s") >= door_w + 2.0 * DOOR_EDGE else _nearest_side(rects, "s", bath)
	_outer_door(gaps, doors, rects, front, "s", rng, door_w, float(spec.get("door_h", -1.0)))
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
		_doorways(rects, links, hub2, roles2.find("bathroom"), rng, floors[1].gaps, doors, n, fh, [hole.grow(0.3)])
		var land: Vector2 = (up.land as Rect2).get_center()
		doors.append({"at": Vector3(land.x, fh, land.y), "rooms": [int(up.room), n + hub2], "stair": true})
		stairs.append({"foot": hole, "from_y": 0.0, "to_y": fh, "steps": int(up.steps), "low": up.low, "up": up.up, "along_x": up.along_x, "land": up.land, "side": up.side})
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
			stairs.append({"foot": roof.foot, "from_y": top.y, "to_y": roof_y + roof_t, "steps": int(roof.steps), "low": roof.low, "up": roof.up, "along_x": roof.along_x, "land": roof.land, "side": roof.side})
			var key := "%d:%d" % [floors.size() - 1, roof.room]
			avoid[key] = (avoid.get(key, []) as Array) + [(roof.foot as Rect2).grow(0.7)]
	# Windows on outside walls, but not in the type's dark rooms (bathrooms, storerooms, an armoury).
	var win_w: float = spec.win_w
	var windows: Array = []
	var outward := {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "w": Vector3(-1, 0, 0), "e": Vector3(1, 0, 0)}
	for fi in floors.size():
		var f: Dictionary = floors[fi]
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
					var line := _line(fr[i], side)
					windows.append({"at": Vector3(mid, f.y, line) if side in ["n", "s"] else Vector3(line, f.y, mid),
						"out": outward[side], "floor": fi, "room": int(f.first) + i})
	# The walls, floor by floor; the slab between, the roof (with its parapet when it's used).
	var boxes: Array = []
	var walls: Array = []  # the outside walls as built, for the skin (_shell)
	for f: Dictionary in floors:
		_shell(boxes, f.rects, f.gaps, t, f.y, h, look.wall, walls)
		for sp: Array in f.splits:
			var key := "in:%d:%s" % [sp[0], snappedf(sp[1], 0.01)]
			_wall(boxes, 1 if sp[0] == 0 else 0, float(sp[1]) - INNER_T * 0.5, float(sp[1]) + INNER_T * 0.5, sp[2], sp[3], h, st.inner, f.gaps.get(key, []), f.y)
	if storeys == 2:
		_slab(boxes, rects, t, [up.foot], h, fh, slab_mat)
		_stair_boxes(boxes, up, 0.0, fh, slab_mat)
		_rails(boxes, up, fh)
	_slab(boxes, top.rects, t, [roof.foot] if not roof.is_empty() else [], roof_y, roof_y + roof_t, look.roof)
	if not roof.is_empty():
		_stair_boxes(boxes, roof, top.y, h + roof_t, slab_mat)
		_rails(boxes, roof, roof_y + roof_t)
		_shell(boxes, top.rects, {}, t, roof_y + roof_t, PARAPET_H, look.wall, walls, true)
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
			var placed_all: Array = [placed] if placed != "" else []
			if spec.has("chunk_area") and placed != "":  # a big hall: more chunks along its other walls
				for more in int(room.get_area() / float(spec.chunk_area)) - 1:
					var keep: Array = (avoid.get("%d:%d" % [fi, i], []) as Array).duplicate()
					for k in range(from_box, boxes.size()):
						var a: Vector3 = boxes[k][0]
						var c: Vector3 = boxes[k][1]
						keep.append(Rect2(a.x, a.z, c.x - a.x, c.z - a.z).grow(HALL_WALKWAY))
					var next := _furnish(boxes, loot, room, f.roles[i], doors, int(f.first) + i, rng, keep)
					if next == "":
						break
					placed_all.append(next)
			var lift := Vector3(0, f.y, 0)
			for k in range(from_box, boxes.size()):
				boxes[k] = [(boxes[k][0] as Vector3) + lift, (boxes[k][1] as Vector3) + lift, boxes[k][2]]
			for k in range(from_loot, loot.size()):
				loot[k].at = (loot[k].at as Vector3) + lift
			rooms.append({"role": f.roles[i], "rect": room, "chunk": placed, "chunks": placed_all, "floor": fi, "y": f.y})
	# Yards: walled, a gate to the side, a chunk of yard things.
	var yards: Array = []
	if yard_d > 0.0:
		yards.append(_yard(boxes, loot, Rect2(outer.position.x, -depth * 0.5, w, yard_d), ["n", "e", "w"], look.wall, doors, rng))
	elif cut.has_area() and rng.randf() < L_YARD_CHANCE:
		var left := cut.position.x <= inner.position.x + 0.01
		var yr := Rect2(outer.position.x, outer.position.y, cut.end.x - t - outer.position.x, cut.end.y - t - outer.position.y) if left \
			else Rect2(cut.position.x + t, outer.position.y, outer.end.x - cut.position.x - t, cut.end.y - t - outer.position.y)
		yards.append(_yard(boxes, loot, yr, ["n", "w" if left else "e"], look.wall, doors, rng))
	var height := roof_y + roof_t + (maxf(PARAPET_H, RAIL_H) if not roof.is_empty() else 0.0)
	var skin := _skin(look, walls, yards, roof_y, roof_t, type)
	var extras := String(spec.get("extras", ""))
	if roof.is_empty() and not extras in ROOFED:
		_roof_things(skin, top.rects, t, roof_y + roof_t, look)
	var out := {"boxes": boxes, "skin": skin, "rooms": rooms, "doors": doors, "loot": loot, "stairs": stairs, "yards": yards,
		"size": Vector2(w, depth), "storeys": storeys, "shape": "l" if cut.has_area() else "rect",
		"roof_access": not roof.is_empty(), "height": height, "style": style, "type": type,
		"windows": windows, "roof_y": roof_y + roof_t, "ruin": INTACT, "buried": [], "apron": apron}
	if extras != "":  # a landmark's own things round its shell (a random stream of their own)
		_extras(extras, out, {"outer": outer, "t": t, "h": h, "roof_t": roof_t, "top": top, "look": look, "apron": apron, "seed": seed,
			"lot": Rect2(-w * 0.5, -depth * 0.5, w, depth), "slab": slab_mat, "roof": roof, "style": style})
	if ruin != INTACT:
		_ruin(out, ruin, walls, look, seed, outer)
	return out


## A style for a zone's region and terrain preset (TerrainPresets ids).
static func style_for(preset: String, seed: int) -> String:
	var pick := {
		"desert_wadi": ["mud", "mud", "block"], "scrubland": ["mud", "block"], "salt_flats": ["block", "mud"],
		"rocky_ridge": ["stone", "block"], "temperate": ["brick", "stone", "block"],
		"coastal_lowland": ["block", "brick"], "amphibious_coast": ["block", "brick"],
	}
	var list: Array = pick.get(preset, ["block", "brick"])
	return list[absi(seed) % list.size()]


# --- Looks (world visual pass, cghath 2026-10-20) ------------------------------------------------

## Each building has its own look, so a street isn't one colour and a house isn't a plain box: its
## walls one of its style's "walls" shades, and a skin over them (_skin): frames round its windows
## and doors (a wooden lintel on mud brick), a darker plinth, a cornice or eaves at the roof (roof
## beam ends on mud brick), shutters on some, a shop's or clinic's or police station's sign over
## its front door, corner stones on brick and stone, weathered patches, a coping on parapets and
## yard walls. Every colour is a VoxelWorld variant of a material the wall already is or is as
## hard as (VoxelWorld.VARIANT_OF), the skin lies in the outermost voxels of the walls or above
## head height, and nothing of it is in a doorway or a window: rounds, blasts, the navmesh and the
## garrison posts are as they were. Picked from the seed on a random stream of its own.
const LOOKS := {
	"mud": {"walls": [VoxelWorld.Mat.MUD_BRICK, VoxelWorld.Mat.MUD_BRICK, VoxelWorld.Mat.MUD_LIGHT, VoxelWorld.Mat.MUD_RED, VoxelWorld.Mat.MUD_WASH],
		"trim": VoxelWorld.Mat.MUD_WASH, "trim_alt": VoxelWorld.Mat.MUD_LIGHT, "plinth": VoxelWorld.Mat.MUD_DARK, "dirty": VoxelWorld.Mat.MUD_DARK,
		"lintel": VoxelWorld.Mat.WOOD_DARK, "shutters": 0.0, "beams": true, "quoins": false},
	"brick": {"walls": [VoxelWorld.Mat.BRICK, VoxelWorld.Mat.BRICK, VoxelWorld.Mat.BRICK_DARK, VoxelWorld.Mat.BRICK_TAN],
		"trim": VoxelWorld.Mat.TRIM_WHITE, "trim_alt": VoxelWorld.Mat.LIMESTONE, "plinth": VoxelWorld.Mat.TRIM_DARK, "dirty": VoxelWorld.Mat.BRICK_DARK,
		"lintel": VoxelWorld.Mat.TRIM_WHITE, "shutters": 0.5, "beams": false, "quoins": true},
	"block": {"walls": [VoxelWorld.Mat.CINDER_BLOCK, VoxelWorld.Mat.RENDER_CREAM, VoxelWorld.Mat.RENDER_OCHRE, VoxelWorld.Mat.RENDER_BLUE,
			VoxelWorld.Mat.RENDER_GREEN, VoxelWorld.Mat.RENDER_PINK, VoxelWorld.Mat.RENDER_CREAM],
		"trim": VoxelWorld.Mat.TRIM_WHITE, "trim_alt": VoxelWorld.Mat.CONCRETE, "plinth": VoxelWorld.Mat.BLOCK_DIRTY, "dirty": VoxelWorld.Mat.CINDER_BLOCK,
		"lintel": VoxelWorld.Mat.CONCRETE, "shutters": 0.45, "beams": false, "quoins": false,
		"roofs": [VoxelWorld.Mat.SHEET_METAL, VoxelWorld.Mat.SHEET_RUST, VoxelWorld.Mat.SHEET_GREEN, VoxelWorld.Mat.SHEET_METAL]},
	"stone": {"walls": [VoxelWorld.Mat.STONE, VoxelWorld.Mat.STONE_WARM, VoxelWorld.Mat.STONE_GREY],
		"trim": VoxelWorld.Mat.LIMESTONE, "trim_alt": VoxelWorld.Mat.TRIM_WHITE, "plinth": VoxelWorld.Mat.STONE_GREY, "dirty": VoxelWorld.Mat.STONE_GREY,
		"lintel": VoxelWorld.Mat.LIMESTONE, "shutters": 0.5, "beams": false, "quoins": true},
}
const SHUTTERS: Array[int] = [VoxelWorld.Mat.WOOD_GREEN, VoxelWorld.Mat.WOOD_BLUE, VoxelWorld.Mat.WOOD_DARK]
const SIGNS: Array[int] = [VoxelWorld.Mat.SIGN_RED, VoxelWorld.Mat.SIGN_YELLOW, VoxelWorld.Mat.SIGN_BLUE]
## The skin's sizes (m): plinth height, frame width round a window (a door's DOOR_FRAME), how far
## a cornice stands out, eaves over a sheet-metal or tiled roof, roof beam ends (how far out, how
## far apart), and corner stones' courses.
const PLINTH_H := 0.4
const FRAME := 0.1
const DOOR_FRAME := 0.2
const CORNICE := 0.1
const EAVES := 0.4
const BEAM_OUT := 0.3
const BEAM_EVERY := 1.0
const QUOIN_H := 0.4
## Below this height nothing stands out of a wall (the navmesh's agent is 1.75 m tall; cornices,
## eaves and beam ends are all up at the roof).
const PROUD_ABOVE := 2.3


## Building `seed`'s look in `style` (LOOKS): {"wall", "roof", "trim", "plinth", "dirty",
## "lintel", "shutter" (-1: none), "sign", "beams", "quoins", "seed"}.
static func _look(style: String, type: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "look"])
	var l: Dictionary = LOOKS[style]
	var walls: Array = l.walls
	var wall: int = walls[rng.randi() % walls.size()]
	var trim: int = l.trim if l.trim != wall else l.trim_alt
	var plinth: int = l.plinth if l.plinth != wall else VoxelWorld.Mat.TRIM_DARK
	var dirty: int = l.dirty if l.dirty != wall else plinth
	var roofs: Array = l.get("roofs", [STYLES[style].roof])
	var roof: int = roofs[rng.randi() % roofs.size()]
	var shutter: int = SHUTTERS[rng.randi() % SHUTTERS.size()] if rng.randf() < float(l.shutters) else -1
	var sign: int = SIGNS[rng.randi() % SIGNS.size()]
	if type == "police":
		sign = VoxelWorld.Mat.SIGN_BLUE
	return {"wall": wall, "roof": roof, "trim": trim, "plinth": plinth, "dirty": dirty, "lintel": l.lintel, "shutter": shutter,
		"sign": sign, "beams": l.beams, "quoins": l.quoins, "seed": rng.randi(), "roof_kind": STYLES[style].roof}


## The building's skin (see LOOKS) over its outside `walls` (_shell's records) and `yards`' walls,
## as [lo, hi, Mat] boxes in its own metres. `roof_y`, `roof_t`: its roof slab.
static func _skin(look: Dictionary, walls: Array, yards: Array, roof_y: float, roof_t: float, type: String) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(look.seed)
	var trim: int = look.trim
	var top := -INF  # the top floor's walls hold the roof
	for w: Dictionary in walls:
		if not w.parapet:
			top = maxf(top, float(w.base))
	var roof_kind: int = look.roof_kind
	for w: Dictionary in walls:
		var h: float = w.h
		var t: float = w.t
		if w.parapet:
			_face_boxes(out, w, w.from, w.to, h - 0.1, h, trim, t)  # a coping along its top
			continue
		var ground := float(w.base) < 0.01
		if ground:
			_face_boxes(out, w, w.from, w.to, 0.0, PLINTH_H, look.plinth)
		# Corner stones, a long one and a short one in turn, up each outside corner.
		if look.quoins:
			for end: int in [0, 1]:
				if not (w.c0 if end == 0 else w.c1):
					continue
				var y := PLINTH_H if ground else 0.0
				var k := 0
				while y + QUOIN_H <= h - 0.2:
					var long := (0.5 if k % 2 == 0 else 0.3) + t
					var a0: float = w.from if end == 0 else float(w.to) - long
					_face_boxes(out, w, a0, a0 + long, y, y + QUOIN_H - 0.1, trim)
					y += QUOIN_H
					k += 1
		for g: Array in w.gaps:
			var g0 := float(g[0])
			var g1 := float(g[1])
			var bottom := float(g[2])
			var head := float(g[3])
			if g1 <= float(w.from) + 0.01 or g0 >= float(w.to) - 0.01:
				continue  # (a line's gaps are kept together: this one is in another room's stretch of it)
			if bottom > 0.01:  # a window: its frame and sill, shutters, a stain under it
				_face_boxes(out, w, g0 - FRAME, g1 + FRAME, bottom - FRAME, head + FRAME, trim)
				_face_boxes(out, w, g0 - FRAME * 2.0, g1 + FRAME * 2.0, bottom - FRAME, bottom, trim)
				if look.beams:
					_face_boxes(out, w, g0 - 0.2, g1 + 0.2, head, head + 0.2, look.lintel)
				var shutter: int = look.shutter
				if shutter >= 0:
					var sw := (g1 - g0) * 0.5
					for a: float in [g0 - FRAME - sw, g1 + FRAME]:
						if _solid_between(w, a, a + sw, bottom, head):
							_face_boxes(out, w, a, a + sw, bottom, head, shutter)
				var stain := rng.randf_range(0.3, 0.5)
				if rng.randf() < 0.5 and bottom - FRAME - stain >= (PLINTH_H if ground else 0.05):
					_face_boxes(out, w, g0 + 0.1, g1 - 0.1, bottom - FRAME - stain, bottom - FRAME, look.dirty)
			else:  # a doorway: jambs and a lintel; a sign over a shop's, a clinic's, a police station's front door
				_face_boxes(out, w, g0 - DOOR_FRAME, g1 + DOOR_FRAME, 0.0, head + DOOR_FRAME, look.lintel if look.beams else trim)
				var s0 := head + 0.1
				var s1 := minf(s0 + 0.45, h - 0.2)
				if ground and w.side == "s" and (type in ["shop", "clinic", "police"] or bool(TYPES[type].get("sign", false))) and s1 - s0 >= 0.2:
					if type == "clinic":  # a white board with a red cross
						var mid := (g0 + g1) * 0.5
						_face_boxes(out, w, mid - 0.6, mid + 0.6, s0, s1, VoxelWorld.Mat.TRIM_WHITE)
						var mid_y := snappedf((s0 + s1) * 0.5, 0.1)
						_face_boxes(out, w, mid - 0.15, mid + 0.15, mid_y - 0.05, mid_y + 0.05, VoxelWorld.Mat.SIGN_RED)
						_face_boxes(out, w, mid - 0.05, mid + 0.05, mid_y - 0.15, mid_y + 0.15, VoxelWorld.Mat.SIGN_RED)
					else:
						_face_boxes(out, w, g0 - 0.4, g1 + 0.4, s0, s1, look.sign)
		# Weathering: damp creeping up from the plinth here and there, ragged.
		var length := float(w.to) - float(w.from)
		if ground and length > 2.0:
			var a := float(w.from) + rng.randf_range(0.0, 1.5)
			while a < float(w.to) - 0.3:
				var pw := rng.randf_range(0.5, 1.6)
				if rng.randf() < 0.45:
					_face_boxes(out, w, a, minf(a + pw, float(w.to)), PLINTH_H, PLINTH_H + snappedf(rng.randf_range(0.1, 0.4), 0.1), look.dirty)
				a += pw
		# At the roof: eaves over sheet metal and tiles, beam ends out of mud brick, else a cornice.
		if absf(float(w.base) - top) < 0.01:
			var lo := float(w.from) - (CORNICE if w.c0 else 0.0)
			var hi := float(w.to) + (CORNICE if w.c1 else 0.0)
			if look.beams:
				var a := float(w.from) + 0.45
				while a < float(w.to) - 0.4:
					_face_boxes(out, w, a, a + 0.15, h - 0.35, h - 0.2, look.lintel, 0.0, BEAM_OUT)
					a += BEAM_EVERY
				_face_boxes(out, w, w.from, w.to, h - 0.1, h, trim)
			elif roof_kind in [VoxelWorld.Mat.SHEET_METAL, VoxelWorld.Mat.ROOF_TILE]:
				var e0 := float(w.from) - (EAVES if w.c0 else 0.0)
				var e1 := float(w.to) + (EAVES if w.c1 else 0.0)
				_face_boxes(out, w, e0, e1, h, h + roof_t, look.roof, 0.0, EAVES)
				_face_boxes(out, w, w.from, w.to, h - 0.2, h, trim)
			else:
				_face_boxes(out, w, lo, hi, h - 0.2, h + roof_t, trim, 0.1, CORNICE)
	# Yard walls: a coping along the top.
	for y: Dictionary in yards:
		for wl: Array in y.get("walls", []):
			var axis: int = wl[0]
			var a := float(wl[3])
			var gaps: Array = (wl[5] as Array).duplicate()
			gaps.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
			for g: Array in gaps + [[float(wl[4]), float(wl[4])]]:
				var b := minf(float(g[0]), float(wl[4]))
				if b - a > 0.05:
					var y0 := YARD_WALL_H - 0.1
					if axis == 0:
						out.append([Vector3(a, y0, wl[1]), Vector3(b, YARD_WALL_H, wl[2]), trim])
					else:
						out.append([Vector3(wl[1], y0, a), Vector3(wl[2], YARD_WALL_H, b), trim])
				a = maxf(a, float(g[1]))
	return out


## On a roof nobody goes up to (`rects`, a floor's rooms; `t` its walls, `y` the roof's top): a
## water tank on a stand in one corner now and then, and a vent box in another. Skin: no one
## stands up there, and the garrison posts on roofs are only on the ones with a stair.
static func _roof_things(out: Array, rects: Array[Rect2], t: float, y: float, look: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(look.seed) + 17
	var r: Rect2 = rects[rng.randi() % rects.size()]
	if r.size.x < 2.4 or r.size.y < 2.4:
		return
	var corners: Array[Vector2] = [r.position + Vector2(0.4, 0.4), Vector2(r.end.x - 1.4, r.position.y + 0.4),
		Vector2(r.position.x + 0.4, r.end.y - 1.4), r.end - Vector2(1.4, 1.4)]
	var k := rng.randi() % 4
	if rng.randf() < 0.6:
		var c := corners[k]
		for leg: Vector2 in [Vector2(0.05, 0.05), Vector2(0.85, 0.05), Vector2(0.05, 0.85), Vector2(0.85, 0.85)]:
			out.append([Vector3(c.x + leg.x, y, c.y + leg.y), Vector3(c.x + leg.x + 0.1, y + 0.4, c.y + leg.y + 0.1), VoxelWorld.Mat.STEEL])
		out.append([Vector3(c.x, y + 0.4, c.y), Vector3(c.x + 1.0, y + 1.3, c.y + 1.0), VoxelWorld.Mat.TRIM_DARK])
		out.append([Vector3(c.x + 0.4, y + 1.3, c.y + 0.4), Vector3(c.x + 0.6, y + 1.4, c.y + 0.6), VoxelWorld.Mat.TRIM_DARK])
	if rng.randf() < 0.5:
		var c := corners[(k + 2) % 4] + Vector2(0.2, 0.2)
		out.append([Vector3(c.x, y, c.y), Vector3(c.x + 0.8, y + 0.5, c.y + 0.6), VoxelWorld.Mat.TRIM_WHITE])
		out.append([Vector3(c.x + 0.1, y + 0.1, c.y - 0.1), Vector3(c.x + 0.5, y + 0.4, c.y + 0.1), VoxelWorld.Mat.TRIM_DARK])  # its grille


## Whether outside wall `w` is solid (no doorway or window, and the wall's own) from `a0` to `a1`
## along it, between `y0` and `y1` over its base.
static func _solid_between(w: Dictionary, a0: float, a1: float, y0: float, y1: float) -> bool:
	if a0 < float(w.from) - 0.001 or a1 > float(w.to) + 0.001:
		return false
	for g: Array in w.gaps:
		if float(g[0]) < a1 and float(g[1]) > a0 and float(g[2]) < y1 and float(g[3]) > y0:
			return false
	return true


## Boxes on outside wall `w`'s face (_shell's record) from `a0` to `a1` along it and `y0` to `y1`
## over its base, `depth` into the wall from its face and `proud` out past it, cut back to the wall's
## ends and round every doorway and window in it (so nothing of a skin ever stands in one). Nothing
## stands out of a wall below PROUD_ABOVE.
static func _face_boxes(out: Array, w: Dictionary, a0: float, a1: float, y0: float, y1: float, mat: int, depth := 0.1, proud := 0.0) -> void:
	if proud > 0.0 and y0 + float(w.base) < PROUD_ABOVE:
		proud = 0.0
	if proud <= 0.0:
		a0 = maxf(a0, float(w.from))
		a1 = minf(a1, float(w.to))
	if a1 - a0 < 0.05 or y1 - y0 < 0.05:
		return
	var pieces: Array = [Rect2(a0, y0, a1 - a0, y1 - y0)]
	for g: Array in w.gaps:
		var hole := Rect2(float(g[0]), float(g[2]), float(g[1]) - float(g[0]), float(g[3]) - float(g[2]))
		var next: Array = []
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
	var line: float = w.line
	var t: float = w.t
	var base: float = w.base
	for p: Rect2 in pieces:
		if p.size.x < 0.05 or p.size.y < 0.05:
			continue
		var lo_y := base + p.position.y
		var hi_y := base + p.end.y
		match String(w.side):
			"n": out.append([Vector3(p.position.x, lo_y, line - t - proud), Vector3(p.end.x, hi_y, line - t + depth), mat])
			"s": out.append([Vector3(p.position.x, lo_y, line + t - depth), Vector3(p.end.x, hi_y, line + t + proud), mat])
			"w": out.append([Vector3(line - t - proud, lo_y, p.position.x), Vector3(line - t + depth, hi_y, p.end.x), mat])
			_: out.append([Vector3(line + t - depth, lo_y, p.position.x), Vector3(line + t + proud, hi_y, p.end.x), mat])


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
## `keep_big`: the bigger part of the first split stays one room (a hall).
static func _plan(inner: Rect2, cut: Rect2, want: int, rng: RandomNumberGenerator, first_cut: float, keep_big := false) -> Dictionary:
	var rects: Array[Rect2] = []
	var splits: Array = []
	var big := Rect2()
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
			if keep_big and r == big:
				continue
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
			if keep_big and splits.size() == 1:
				big = a if a.get_area() >= b.get_area() else b
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
## `wells` (Rect2s: the stairwell up through this floor): a doorway is slid along its wall till
## the floor either side of it is clear of them (one over a stairwell was no way through).
static func _doorways(rects: Array[Rect2], links: Array, hub: int, bath: int, rng: RandomNumberGenerator, gaps: Dictionary, doors: Array, first: int, y: float, wells: Array = []) -> void:
	var n := rects.size()
	var tree: Array = []
	var reached := {hub: true}
	# A link whose every doorway would open onto a stairwell is used only if nothing else reaches
	# the room beyond it.
	var spots := {}
	var clear_links: Array = []
	for l: Array in links:
		var lo := _door_lo(l, wells)
		if not is_nan(lo):
			spots[l] = lo
			clear_links.append(l)
	for pool: Array in ([clear_links, links] if not wells.is_empty() else [links]):
		_tree(pool, bath, n, reached, tree)
	if rng.randf() < 0.3:
		for l: Array in clear_links:
			if not tree.has(l) and l[0] != bath and l[1] != bath:
				tree.append(l)
				break
	for l: Array in tree:
		var mid := (float(l[4]) + float(l[5])) * 0.5
		var lo: float = spots.get(l, clampf(mid - DOOR_W * 0.5, float(l[4]) + DOOR_EDGE, float(l[5]) - DOOR_EDGE - DOOR_W))
		_gap(gaps, "in:%d:%s" % [l[2], snappedf(l[3], 0.01)], lo, lo + DOOR_W, 0.0, DOOR_H)
		var at := Vector3(l[3], y, lo + DOOR_W * 0.5) if l[2] == 0 else Vector3(lo + DOOR_W * 0.5, y, l[3])
		doors.append({"at": at, "rooms": [first + int(l[0]), first + int(l[1])]})


## Grows doorway tree `tree` from the rooms in `reached` through `links` (the bathroom `bath` a
## leaf, nothing through it) till all `n` rooms are reached or no more can be.
static func _tree(links: Array, bath: int, n: int, reached: Dictionary, tree: Array) -> void:
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


## Where along link `l` ([i, j, axis, at, from, to]) its doorway starts: in the middle of the
## shared wall, slid along it till the floor either side of it is clear of `wells` (stairwells:
## a doorway onto a stairwell is no way through); NAN if nowhere along it is.
static func _door_lo(l: Array, wells: Array) -> float:
	var mid := (float(l[4]) + float(l[5])) * 0.5
	var lo := clampf(mid - DOOR_W * 0.5, float(l[4]) + DOOR_EDGE, float(l[5]) - DOOR_EDGE - DOOR_W)
	var over := func(a: float) -> bool:
		var c := Vector3(l[3], 0, a + DOOR_W * 0.5) if l[2] == 0 else Vector3(a + DOOR_W * 0.5, 0, l[3])
		var clear := Rect2(c.x - DOOR_CLEAR, c.z - DOOR_W * 0.5, DOOR_CLEAR * 2.0, DOOR_W) if l[2] == 0 else Rect2(c.x - DOOR_W * 0.5, c.z - DOOR_CLEAR, DOOR_W, DOOR_CLEAR * 2.0)
		return wells.any(func(r: Rect2) -> bool: return r.intersects(clear))
	if wells.is_empty() or not over.call(lo):
		return lo
	var best := NAN
	var a := float(l[4]) + DOOR_EDGE
	while a <= float(l[5]) - DOOR_EDGE - DOOR_W + 0.001:
		if not over.call(a) and (is_nan(best) or absf(a - lo) < absf(best - lo)):
			best = a
		a += 0.1
	return snappedf(best, 0.01) if not is_nan(best) else NAN


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


## `height`: a landmark's "door_h" (-1: DOOR_H, a little more for a wide one).
static func _outer_door(gaps: Dictionary, doors: Array, rects: Array[Rect2], room: int, side: String, rng: RandomNumberGenerator, width := DOOR_W, height := -1.0) -> void:
	var span := _side_span(room, rects, side)
	width = minf(width, span.y - span.x - DOOR_EDGE * 2.0)
	if width < DOOR_W:
		return
	var lo := snappedf(rng.randf_range(span.x + DOOR_EDGE, span.y - DOOR_EDGE - width), 0.1)
	_gap(gaps, _out_key(rects[room], side), lo, lo + width, 0.0, height if height > 0.0 else DOOR_H + (0.4 if width >= 2.5 else 0.0))
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
## and of `keep` (Rect2s), STAIR_APPROACH in front of its foot and STAIR_LANDING free past its
## top in the same room. {"room",
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
			if length >= run + STAIR_LANDING + STAIR_APPROACH + FURNITURE_GAP and across >= STAIR_W + 0.9:
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
			var low := ((room.position.x if along_x else room.position.y) + STAIR_APPROACH) if up == 1 \
				else ((room.end.x if along_x else room.end.y) - STAIR_APPROACH)
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


## For the navmesh bake only (NavBuilder, ZoneNav): a ramp over each of building `b`'s stairs,
## in its own metres, as triangles facing up (two a stair). It lies a step's rise over the step
## nosings, so it's over every tread, from that high at the foot to that high over its top
## landing: one 0.2 m climb on and off, and a smooth slope between that a 0.25 m cell bakes
## whole (the steps themselves, voxels, came out cut in two: see STAIR_RISE).
static func ramp_faces(b: Dictionary) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for st: Dictionary in b.get("stairs", []):
		if not st.has("up"):
			continue
		var f: Rect2 = st.foot
		var rise := (float(st.to_y) - float(st.from_y)) / maxf(float(st.steps), 1.0)
		var y_low := float(st.from_y) + rise
		var y_high := float(st.to_y) + rise
		var up := int(st.up)
		# Heights at the rect's low and high x (or z), whichever way it climbs.
		var y0 := y_low if up == 1 else y_high
		var y1 := y_high if up == 1 else y_low
		var a := Vector3(f.position.x, 0, f.position.y)
		var c := Vector3(f.end.x, 0, f.end.y)
		var corners: Array[Vector3]
		if st.along_x:
			corners = [Vector3(a.x, y0, a.z), Vector3(c.x, y1, a.z), Vector3(c.x, y1, c.z), Vector3(a.x, y0, c.z)]
		else:
			corners = [Vector3(a.x, y0, a.z), Vector3(c.x, y0, a.z), Vector3(c.x, y1, c.z), Vector3(a.x, y1, c.z)]
		faces.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	return faces


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
static func _shell(out: Array, rects: Array[Rect2], gaps: Dictionary, t: float, base: float, h: float, mat: int, walls: Array = [], parapet := false) -> void:
	for i in rects.size():
		var r := rects[i]
		for side: String in ["n", "s", "w", "e"]:
			var line := _line(r, side)
			var g: Array = gaps.get(_out_key(r, side), [])
			for iv: Vector2 in _exterior(i, rects, side):
				var c0 := _corner(rects, side, line, iv.x, -1.0)
				var c1 := _corner(rects, side, line, iv.y, 1.0)
				var from := iv.x - (t if c0 else 0.0)
				var to := iv.y + (t if c1 else 0.0)
				walls.append({"side": side, "line": line, "from": from, "to": to, "c0": c0, "c1": c1, "t": t, "base": base, "h": h, "gaps": g, "parapet": parapet})
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
	var built: Array = []
	for side: String in sides:
		var wl: Array = walls[side]
		_wall(out, wl[0], wl[1], wl[2], wl[3], wl[4], YARD_WALL_H, mat, gaps.get(side, []))
		built.append(wl + [gaps.get(side, [])])
	var inside := yr.grow_individual(-yt if "w" in sides else 0.0, -yt, -yt if "e" in sides else 0.0, 0.0)
	var ways: Array = []
	if gate != null:
		ways.append({"at": gate, "rooms": [-9, -1]})
	for dr: Dictionary in doors:
		if int(dr.rooms[1]) == -1 and inside.grow(0.6).has_point(Vector2((dr.at as Vector3).x, (dr.at as Vector3).z)):
			ways.append({"at": dr.at, "rooms": [-9, -1]})
	var chunk := _furnish(out, loot, inside, "yard", ways, -9, rng)
	return {"rect": inside, "gate": gate, "chunk": chunk, "walls": built}


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
## A town's weapons cache: a stack of crates this size (m).
const TOWN_CACHE := Vector3(1.4, 1.0, 0.9)
## Garrison posts (F-02): as many as one for every other building and two at the crossroads,
## TOWN_HIGH_SHARE of them up high: at an upper floor's window onto the street, or behind a
## roof's parapet (a roof is only ever reached by a stair, and every such roof has a parapet);
## the rest just inside front doors. A post up high stands POST_IN_M in from the wall, on a floor
## or a roof with nothing in a man's way (POST_CLEAR_M round, 1.7 m up).
const TOWN_HIGH_SHARE := 0.45  # of the street-front posts (2026-10-17: was a third; deep posts are on top)
const POST_IN_M := 0.7
const POST_CLEAR_M := 0.3
## Every TOWN_CIVILIAN_EVERY'th building has someone living or working there, walking between
## their front step, the street and the crossroads.
const TOWN_CIVILIAN_EVERY := 3
## Lot types by where they are along the street (0 the middle .. 1 the end): weights.
const TOWN_MIX := {"house": 6.0, "shop": 2.5, "warehouse": 1.0, "clinic": 0.6, "police": 0.6}
## Back rows (town): the alley between a row and the one behind it (m), and the share of the back
## lots left open. Street barricades and rubble piles [min, max] a town. Proposed.
const ALLEY_W := 4.0
const BACK_GAP_SHARE := 0.25
const TOWN_BARRICADES := Vector2i(4, 7)
## A deep post (_deep_posts) in every this-many'th building.
const TOWN_DEEP_EVERY := 4


## The town from `seed`: {"boxes", "buildings": [{"type", "origin" (Vector3), "turned" (180
## degrees), "data" (building())}], "half" (Vector2: footprint half-size, m), "points"
## ({"objective", "cache", "intel"}: Array of Vector3), "garrison" (Array of Vector3),
## "garrison_face" (Vector3 for each post: the way it looks out, Vector3.ZERO: the default),
## "garrison_high" (how many of the posts are up high), "ramps" (the stairs' ramp_faces for
## the navmesh, town metres), "loot"
## (ZoneModules.LOOT entries: {"uid", "id", "count", "pos"}), "hvt" and "hostage" (Vector3: the
## middle of the room an HVT lives in, an office or a living room, and of the room a hostage is
## held in, the police cells or a bedroom), "cache" ([lo, hi] Vector3s: a weapons cache, crates
## stacked in the police armoury or a store room), "civilians" ({"pos", "routine"},
## as contracts.json module "civilians", in arrays), "style"}.
static func town(seed: int, style := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if style == "":
		style = STYLES.keys()[rng.randi() % STYLES.size()]
	var boxes: Array = []
	var skin: Array = []  # the buildings' skins (_skin), town metres
	var ramps := PackedVector3Array()  # the stairs' ramps for the navmesh (ramp_faces), town metres
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
				_place_boxes(boxes, b.boxes, origin, turned)
				_place_boxes(skin, b.skin, origin, turned)
				for p: Vector3 in ramp_faces(b):  # (turned round: a rotation, the faces still face up)
					ramps.append((Vector3(-p.x, p.y, -p.z) if turned else p) + origin)
				buildings.append({"type": type, "origin": origin, "turned": turned, "data": b})
				deepest = maxf(deepest, size.y)
				cursor += size.x + LOT_GAP
	# Back rows (Captain, 2026-10-17: "urban combat feels not urban, its mostly firefights from
	# outside to into the town"): a second row behind each, across an ALLEY_W alley, facing out
	# onto a back street; BACK_GAP_SHARE of its lots left open (yards, rubble). Blocks, not a strip.
	var front_d := STREET_W * 0.5 + SETBACK + deepest
	var back_deepest := 0.0
	for side: int in [-1, 1]:
		for dir: int in [-1, 1]:
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
					continue
				if rng.randf() < BACK_GAP_SHARE:
					cursor += size.x + LOT_GAP  # an open lot
					continue
				if type in ["clinic", "police"]:
					once[type] = true
				var x := dir * (cursor + size.x * 0.5)
				var z := side * (front_d + ALLEY_W + SETBACK + size.y * 0.5)
				var turned := side == -1  # faces out, away from the main street
				var origin := Vector3(x, 0, z)
				_place_boxes(boxes, b.boxes, origin, turned)
				_place_boxes(skin, b.skin, origin, turned)
				for p: Vector3 in ramp_faces(b):
					ramps.append((Vector3(-p.x, p.y, -p.z) if turned else p) + origin)
				buildings.append({"type": type, "origin": origin, "turned": turned, "data": b, "back": true})
				back_deepest = maxf(back_deepest, size.y)
				cursor += size.x + LOT_GAP
	var outer := front_d + ALLEY_W + SETBACK + back_deepest
	# Street barricades and rubble: TOWN_BARRICADES [min, max], each across part of a street.
	for n in rng.randi_range(TOWN_BARRICADES.x, TOWN_BARRICADES.y):
		var on_cross := rng.randf() < 0.3
		var len := rng.randf_range(2.4, 4.0)
		var c: Vector3
		var across_x: bool
		if on_cross:
			c = Vector3(rng.randf_range(-CROSS_W, CROSS_W) * 0.25, 0, rng.randf_range(STREET_W, outer - 2.0) * (1.0 if rng.randf() < 0.5 else -1.0))
			across_x = true
		else:
			c = Vector3(rng.randf_range(CROSS_W + 3.0, TOWN_HALF_X - 4.0) * (1.0 if rng.randf() < 0.5 else -1.0), 0, rng.randf_range(-STREET_W, STREET_W) * 0.25)
			across_x = false
		var rubble := rng.randf() < 0.4
		var size := Vector3(rng.randf_range(1.4, 2.2), rng.randf_range(0.7, 1.2), rng.randf_range(1.2, 2.0)) if rubble 			else (Vector3(len, 1.1, 0.8) if across_x else Vector3(0.8, 1.1, len))
		boxes.append([c - Vector3(size.x * 0.5, 0, size.z * 0.5), c + Vector3(size.x * 0.5, size.y, size.z * 0.5),
			VoxelWorld.Mat.CONCRETE if rubble else VoxelWorld.Mat.SANDBAG])
	var half := Vector2(TOWN_HALF_X + 2.0, outer + 2.0)
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
	# Garrison posts (F-02): a share up high at upper windows and on roofs, the rest just inside
	# front doors, two at the crossroads; in building order (posts pair off as buddies in turn).
	var face: Array = []
	var high := _town_posts(buildings, garrison, face)
	for fallback: String in ["objective", "cache", "intel"]:
		if (points[fallback] as Array).is_empty():
			points[fallback].append(Vector3(0, 0, 0))
	var deep := _deep_posts(buildings, garrison, face)
	var reserve: Array = [garrison.size(), garrison.size() + 1]  # the two at the crossroads: the town's reserve
	garrison.append(Vector3(-CROSS_W, 0.1, 0))
	garrison.append(Vector3(CROSS_W, 0.1, 0))
	face.append_array([Vector3.ZERO, Vector3.ZERO])
	var fallback: Array = []  # every building's back room: where defenders fall back to
	for b: Dictionary in buildings:
		var back_room := _back_room(b.data)
		if back_room.is_finite():
			fallback.append((Vector3(-back_room.x, back_room.y, -back_room.z) if b.turned else back_room) + (b.origin as Vector3))
	# The weapons cache: crates in the middle of the armoury or a store room (a raid's target).
	var at := _town_room(buildings, ["armoury", "storeroom"], Vector3(0, 0.1, STREET_W * 0.5 + SETBACK + 3.0)) - Vector3(0, 0.1, 0)
	var cache: Array = [at - Vector3(TOWN_CACHE.x * 0.5, 0, TOWN_CACHE.z * 0.5), at + Vector3(TOWN_CACHE.x * 0.5, TOWN_CACHE.y, TOWN_CACHE.z * 0.5)]
	boxes.append([cache[0], cache[1], VoxelWorld.Mat.WOOD])
	return {"boxes": boxes, "skin": skin, "buildings": buildings, "half": half, "points": points, "garrison": garrison,
		"garrison_face": face, "garrison_high": high, "garrison_deep": deep, "garrison_reserve": reserve, "fallback": fallback, "ramps": ramps, "loot": loot, "civilians": civilians, "style": style, "cache": cache,
		"hvt": _town_room(buildings, ["office", "living"], Vector3(-CROSS_W, 0.1, 0)),
		"hostage": _town_room(buildings, ["cells", "bedroom"], Vector3(CROSS_W, 0.1, 0))}


## A building's `list` of [lo, hi, Mat] boxes (its own metres) into `out` at `origin`, turned round
## (180 degrees about y) when `turned`.
static func _place_boxes(out: Array, list: Array, origin: Vector3, turned: bool) -> void:
	for bx: Array in list:
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		if turned:
			var nlo := Vector3(-hi.x, lo.y, -hi.z)
			var nhi := Vector3(-lo.x, hi.y, -lo.z)
			lo = nlo
			hi = nhi
		out.append([lo + origin, hi + origin, bx[2]])


## A town's building posts into `posts` (town metres) and the way each looks out into `face`:
## as many as one for every other building, TOWN_HIGH_SHARE of them up high (spread over the
## buildings with an upper floor or a roof to stand on), the rest inside front doors (spread
## over the others). Returns how many are up high. No random numbers: the town's stay the same.
static func _town_posts(buildings: Array, posts: Array, face: Array) -> int:
	var front_rows := buildings.filter(func(b: Dictionary) -> bool: return not b.get("back", false)).size()
	var total := (front_rows + 1) / 2 + 2  # with the two at the crossroads (back rows: deep posts only, _deep_posts)
	var up_at := {}  # building index -> [post, face] up high
	for i in buildings.size():
		if buildings[i].get("back", false):
			continue  # a back row faces out of town: no overwatch out of it (fights start inside)
		var p := _high_post(buildings[i].data, i)
		if not p.is_empty():
			up_at[i] = p
	var want_high := mini(roundi(total * TOWN_HIGH_SHARE), up_at.size())
	var high := {}
	var keys: Array = up_at.keys()
	for k in want_high:
		high[keys[k * keys.size() / want_high]] = true
	var rest: Array = range(buildings.size()).filter(func(i: int) -> bool: return not high.has(i) and not buildings[i].get("back", false))
	var want_door := mini(total - 2 - want_high, rest.size())
	var door := {}
	for k in want_door:
		door[rest[k * rest.size() / want_door]] = true
	var count := 0
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		var turned: bool = b.turned
		var turn := func(p: Vector3) -> Vector3: return Vector3(-p.x, p.y, -p.z) if turned else p
		if door.has(i):
			for dr: Dictionary in b.data.doors:
				if dr.rooms[1] == -1 and (dr.at as Vector3).z > 0.0:
					posts.append(turn.call((dr.at as Vector3) + Vector3(0, 0.1, -1.0)) + (b.origin as Vector3))
					face.append(turn.call(Vector3(0, 0, 1)))  # out of the door, onto the street
					break
		if high.has(i):
			posts.append(turn.call(up_at[i][0]) + (b.origin as Vector3))
			face.append(turn.call(up_at[i][1]))
			count += 1
	return count


## Defence in depth (Captain, 2026-10-17: "small bits of action when clearing the few remaining
## enemies"): a post in the back room of every TOWN_DEEP_EVERY'th building, front rows and back,
## so the town is held from inside its blocks, not only its street fronts. Returns the posts'
## indices in `posts`.
static func _deep_posts(buildings: Array, posts: Array, face: Array) -> Array:
	var out: Array = []
	for i in buildings.size():
		if i % TOWN_DEEP_EVERY != 1:
			continue
		var b: Dictionary = buildings[i]
		var p := _back_room(b.data)
		if not p.is_finite():
			continue
		out.append(posts.size())
		posts.append((Vector3(-p.x, p.y, -p.z) if b.turned else p) + (b.origin as Vector3))
		face.append(Vector3.ZERO)
	return out


## The middle of building `b`'s backmost room that isn't a bathroom (its own metres, on its
## floor), Vector3.INF with none.
static func _back_room(b: Dictionary) -> Vector3:
	var best := Vector3.INF
	for r: Dictionary in b.rooms:
		if String(r.role) == "bathroom":
			continue
		var c: Vector2 = (r.rect as Rect2).get_center()
		if not best.is_finite() or c.y < best.z:
			best = Vector3(c.x, float(r.get("y", 0.0)) + 0.1, c.y)
	return best


## Building `b`'s post up high (in its own metres) and the way it looks: [post, face], [] for
## none. A two-storey building's is at an upper window onto the street, a roof's behind its
## parapet on the street side (a building with both: by `i`, every other one on its roof).
static func _high_post(b: Dictionary, i: int) -> Array:
	var tries: Array = []
	var roof := func() -> void:
		if not b.roof_access:
			return
		var front := -INF
		var span := Vector2(INF, -INF)
		for r: Dictionary in b.rooms:
			if int(r.floor) == int(b.storeys) - 1:
				var rect: Rect2 = r.rect
				front = maxf(front, rect.end.y)
				span = Vector2(minf(span.x, rect.position.x), maxf(span.y, rect.end.x))
		var y := float(b.roof_y)
		for k in 9:  # from the middle out, either way
			var x := (span.x + span.y) * 0.5 + float((k + 1) / 2) * 1.2 * (1.0 if k % 2 == 1 else -1.0)
			if x > span.x + 0.6 and x < span.y - 0.6:
				tries.append([Vector3(x, y + 0.1, front - POST_IN_M), Vector3(0, 0, 1)])
	var window := func() -> void:
		# Onto the street (+z) only.
		for w: Dictionary in (b.windows as Array).filter(func(w: Dictionary) -> bool: return int(w.floor) >= 1 and (w.out as Vector3).z > 0.5):
			for back: float in [POST_IN_M, POST_IN_M + 0.4]:
				tries.append([(w.at as Vector3) - (w.out as Vector3) * back + Vector3(0, 0.1, 0), w.out])
	if int(b.storeys) == 2 and i % 2 == 0:
		window.call()
		roof.call()
	else:
		roof.call()
		if int(b.storeys) == 2:
			window.call()
	for t: Array in tries:
		if _clear_post(b.boxes, t[0]):
			return t
	return []


## Whether a man fits at `p` (building metres, at his feet): nothing within POST_CLEAR_M of him
## up to 1.7 m, and something under his feet (a floor, a slab, a roof).
static func _clear_post(boxes: Array, p: Vector3) -> bool:
	var body := AABB(p + Vector3(-POST_CLEAR_M, 0.05, -POST_CLEAR_M), Vector3(POST_CLEAR_M * 2.0, 1.65, POST_CLEAR_M * 2.0))
	var under := false
	for bx: Array in boxes:
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		if AABB(lo, hi - lo).intersects(body):
			return false
		if p.x >= lo.x and p.x <= hi.x and p.z >= lo.z and p.z <= hi.z and absf(hi.y - (p.y - 0.1)) < 0.05:
			under = true
	return under


## Whether a man fits standing at `p` (at his feet, on the ground or a floor): nothing within
## POST_CLEAR_M of him up to 1.7 m.
static func _clear_standing(boxes: Array, p: Vector3) -> bool:
	var body := AABB(p + Vector3(-POST_CLEAR_M, 0.05, -POST_CLEAR_M), Vector3(POST_CLEAR_M * 2.0, 1.65, POST_CLEAR_M * 2.0))
	for bx: Array in boxes:
		var lo: Vector3 = bx[0]
		if AABB(lo, (bx[1] as Vector3) - lo).intersects(body):
			return false
	return true


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


# --- Landmarks (queue item 1.4, cghath 2026-10-21) ---------------------------------------------
# A landmark is one of TYPES' landmark types (LANDMARK_TYPES), generated like any building (rooms,
# doorways, stairs, chunks, loot), with its own things round its shell (_extras: a dome and a
# minaret, a bell tower and a gable roof, a fuel station's canopy, a factory's chimney), and a
# ruined and a bombed-out variant of each (_ruin). Big sites (site(): a farm, a fuel depot, a
# harbour, an airfield, an oil field) are several buildings and their props. All are boxes, as
# everything else: blasts carve them, the AI finds their rooms by probing (Buildings).

## Furniture in a big hall stays this far apart (m): a walkway between chunks.
const HALL_WALKWAY := 0.6
## Extras that put a roof of their own over the flat one (no water tank or vent box up there).
const ROOFED: Array[String] = ["mosque", "church", "barn", "hangar", "shed", "factory"]
## Proposed sizes (m): a mosque's dome at most DOME_MAX_R round, its minaret MINARET_W square and
## MINARET_H [min, max] tall; a church's bell tower TOWER_W square, BELL_TOWER_UP over its roof;
## a gable roof's steps (STEP_IN in, STEP_UP up: about 34 degrees); a hangar's arch ARCH_RISE high;
## a fuel station's canopy CANOPY_H high; a factory's chimney CHIMNEY_W square, CHIMNEY_H tall.
const DOME_MAX_R := 3.6
const MINARET_W := 2.0
const MINARET_H := Vector2(12.0, 17.0)
const TOWER_W := 3.4
const BELL_TOWER_UP := 8.0
const STEP_IN := 0.3
const STEP_UP := 0.2
const ARCH_RISE := 3.0
const CANOPY_H := 4.6
const CHIMNEY_W := 1.8
const CHIMNEY_H := Vector2(15.0, 18.0)
## A closed tank or silo has a floor inside every DECK_EVERY m: no room under any of them for a
## man to stand (NavBuilder's agent is 1.75 m tall), so the navmesh never bakes a room nobody can
## get into.
const DECK_EVERY := 1.5
## A dome's colour by style.
const DOMES := {"mud": [VoxelWorld.Mat.MUD_WASH, VoxelWorld.Mat.TRIM_WHITE], "brick": [VoxelWorld.Mat.TRIM_WHITE, VoxelWorld.Mat.SHEET_GREEN],
	"block": [VoxelWorld.Mat.TRIM_WHITE, VoxelWorld.Mat.SHEET_GREEN, VoxelWorld.Mat.RENDER_BLUE], "stone": [VoxelWorld.Mat.LIMESTONE, VoxelWorld.Mat.SHEET_GREEN]}
## What lies at a landmark's loot spots, by the spot's table (on top of TOWN_LOOT's).
const LANDMARK_LOOT := {
	"lab": [["hashish", 1], ["cash_roll", 1], ["caffeine_pills", 1]],
	"ied": [["copper_wire", 2], ["det_cord", 1], ["remote_detonator", 1], ["feature_phone", 1]],
	"garage": [["vehicle_battery", 1], ["multitool", 1], ["jerrycan", 1]],
}
const LANDMARK_LOOT_MAX := 6


## Building `b`'s front door ("at"): its outside doorway furthest to the front (+z), not under
## rubble; null if none.
static func front_door(b: Dictionary) -> Variant:
	var best: Variant = null
	for dr: Dictionary in b.doors:
		var at: Vector3 = dr.at
		if int(dr.rooms[1]) == -1 and not (b.get("buried", []) as Array).has(at) and (best == null or at.z > (best as Vector3).z + 0.01):
			best = at
	return best


## A spot a man can stand at near `p` (on a floor: `p.y` its height + 0.1) in building `b`: `p`
## itself, or the nearest clear one within 1.6 m; Vector3.INF if none (or `p` isn't finite).
static func _room_post(b: Dictionary, p: Vector3) -> Vector3:
	if not p.is_finite():
		return Vector3.INF
	for r: float in [0.0, 0.6, 1.2, 1.6]:
		for k in (1 if r == 0.0 else 8):
			var q: Vector3 = p + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * r
			if _clear_standing(b.boxes, q) and (q.y < 0.5 or _clear_post(b.boxes, q)):
				return q
	return Vector3.INF


## Building `b`'s first room of `role` (its rect), or an empty Rect2.
static func _room_of(b: Dictionary, role: String) -> Rect2:
	for r: Dictionary in b.rooms:
		if String(r.role) == role:
			return r.rect
	return Rect2()


## The x span ([from, to]) of building `b`'s outside doors in the wall at z = `z` (its front).
static func _door_spans(b: Dictionary, z: float, margin: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for dr: Dictionary in b.doors:
		var at: Vector3 = dr.at
		if int(dr.rooms[1]) == -1 and absf(at.z - z) < 0.6:
			out.append(Vector2(at.x - margin, at.x + margin))
	return out


## Of `options` (x spans [from, to] along the front), the first clear of every one of `spans`.
static func _clear_of(options: Array, spans: Array) -> Variant:
	for o: Vector2 in options:
		if not spans.any(func(s: Variant) -> bool: return s is Vector2 and (s as Vector2).x < o.y and (s as Vector2).y > o.x):
			return o
	return null


## A landmark's own things round its shell (TYPES "extras"): into `b`'s boxes and skin. `ctx`:
## its shell ("outer", outside faces), walls ("t"), wall height "h", roof slab "roof_t", top
## floor ("top"), "look", "apron" (m in front), "lot", "seed", "slab" (floors' material), "roof"
## (the roof stair, {} for none), "style". On a random stream of its own.
static func _extras(kind: String, b: Dictionary, ctx: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(ctx.seed), "extras"])
	var boxes: Array = b.boxes
	var skin: Array = b.skin
	var outer: Rect2 = ctx.outer
	var look: Dictionary = ctx.look
	var lot: Rect2 = ctx.lot
	var top_y: float = b.roof_y
	var apron := Rect2(outer.position.x, outer.end.y, outer.size.x, float(ctx.apron))
	var M := VoxelWorld.Mat
	var doors_front := _door_spans(b, outer.end.y, 1.6)
	var wall: int = look.wall
	var trim: int = look.trim
	match kind:
		"mosque":
			var hall := _room_of(b, "prayer_hall")
			if hall.has_area():
				var r := clampf(minf(hall.size.x, hall.size.y) * 0.5 * 0.72, 2.0, DOME_MAX_R)
				var mats: Array = DOMES[String(ctx.style)]
				var c := hall.get_center()
				var tip := _dome(boxes, Vector3(c.x, top_y, c.y), r, mats[rng.randi() % mats.size()], trim)
				boxes.append([Vector3(c.x - 0.05, tip, c.y - 0.05), Vector3(c.x + 0.05, tip + 0.9, c.y + 0.05), M.STEEL])
				boxes.append([Vector3(c.x - 0.2, tip + 0.9, c.y - 0.05), Vector3(c.x + 0.2, tip + 1.0, c.y + 0.05), M.SIGN_YELLOW])  # the crescent
			var spot: Variant = _clear_of([Vector2(apron.position.x + 0.3, apron.position.x + 0.3 + MINARET_W),
				Vector2(apron.end.x - 0.3 - MINARET_W, apron.end.x - 0.3)] if rng.randf() < 0.5 else [Vector2(apron.end.x - 0.3 - MINARET_W, apron.end.x - 0.3),
				Vector2(apron.position.x + 0.3, apron.position.x + 0.3 + MINARET_W)], doors_front)
			if spot != null and apron.size.y >= MINARET_W + 0.8:
				var z0 := apron.position.y + (apron.size.y - MINARET_W) * 0.5
				_minaret(boxes, Rect2((spot as Vector2).x, z0, MINARET_W, MINARET_W), snappedf(rng.randf_range(MINARET_H.x, MINARET_H.y), 0.1), wall, trim)
		"church":
			var roof_mat: int = M.ROOF_TILE if rng.randf() < 0.7 else M.SHEET_METAL
			_gable(boxes, outer, top_y, true, roof_mat, wall, lot)
			# The bell tower over the front door: its porch, a doorway through it front and back.
			var door: Variant = front_door(b)
			if door != null and apron.size.y >= TOWER_W + 0.4:
				var dx := (door as Vector3).x
				var x0 := clampf(snappedf(dx - TOWER_W * 0.5, 0.1), apron.position.x + 0.2, apron.end.x - 0.2 - TOWER_W)
				_bell_tower(boxes, Rect2(x0, apron.position.y + 0.1, TOWER_W, TOWER_W), top_y + BELL_TOWER_UP, wall, roof_mat, trim, dx)
		"school":
			# A flagpole in a front corner of the forecourt, railings along its edge, a gap at the door.
			var pole := Vector2(apron.end.x - 0.6, apron.end.y - 0.6) if rng.randf() < 0.5 else Vector2(apron.position.x + 0.5, apron.end.y - 0.6)
			boxes.append([Vector3(pole.x, 0, pole.y), Vector3(pole.x + 0.1, 7.0, pole.y + 0.1), M.STEEL])
			var flag := [M.SIGN_BLUE, M.SIGN_RED, M.WOOD_GREEN][rng.randi() % 3] as int
			var fx := pole.x - 1.1 if pole.x > 0.0 else pole.x + 0.1
			skin.append([Vector3(fx, 6.0, pole.y), Vector3(fx + 1.0, 6.7, pole.y + 0.1), flag])
			_railing(boxes, Vector2(lot.position.x + 0.1, apron.end.y - 0.2), Vector2(lot.end.x - 0.1, apron.end.y - 0.2), doors_front + [Vector2(pole.x - 0.4, pole.x + 0.5)])
		"garage":
			# A car waiting outside, oil drums and a stack of tyres by the wall.
			var spot: Variant = _clear_of([Vector2(apron.position.x + 0.4, apron.position.x + 4.8), Vector2(apron.end.x - 4.8, apron.end.x - 0.4)], doors_front)
			if spot != null and apron.size.y >= 2.6:
				_car(boxes, Vector3(((spot as Vector2).x + (spot as Vector2).y) * 0.5, 0, apron.position.y + 1.3 + rng.randf_range(0.0, apron.size.y - 2.6)),
					true, [M.SIGN_RED, M.SIGN_BLUE, M.TRIM_WHITE, M.STEEL_OLIVE][rng.randi() % 4])
			var drums: Variant = _clear_of([Vector2(apron.end.x - 1.6, apron.end.x - 0.2), Vector2(apron.position.x + 0.2, apron.position.x + 1.6)], doors_front + ([spot] if spot != null else []))
			if drums != null:
				for k in 2:
					var at := Vector3((drums as Vector2).x + k * 0.7, 0, apron.position.y + 0.2)
					boxes.append([at, at + Vector3(0.6, 0.9, 0.6), M.STEEL if k == 0 else M.SIGN_BLUE])
		"fuel_station":
			_fuel_canopy(boxes, skin, apron, look, rng)
		"factory":
			var spots := [Vector2(apron.position.x + 0.3, apron.position.x + 0.3 + CHIMNEY_W), Vector2(apron.end.x - 0.3 - CHIMNEY_W, apron.end.x - 0.3)]
			var spot: Variant = _clear_of(spots, doors_front)
			if spot != null and apron.size.y >= CHIMNEY_W + 0.6:
				_chimney(boxes, Rect2((spot as Vector2).x, apron.position.y + 0.3, CHIMNEY_W, CHIMNEY_W), snappedf(rng.randf_range(CHIMNEY_H.x, CHIMNEY_H.y), 0.1), wall, trim)
				# A container and pallets beside it, clear of the doors.
				var left := (spot as Vector2).x < 0.0
				var cx := (spot as Vector2).y + 0.6 if left else (spot as Vector2).x - 0.6 - 6.1
				if _clear_of([Vector2(cx, cx + 6.1)], doors_front) != null and apron.size.y >= 3.2:
					_container(boxes, Vector3(cx + 3.05, 0, apron.position.y + 1.6), true, [M.SHEET_RUST, M.SHEET_GREEN, M.SIGN_BLUE][rng.randi() % 3], 0)
			if not b.roof_access:
				var floor_room := _room_of(b, "factory_floor")
				if floor_room.has_area():
					_sawtooth(boxes, floor_room, top_y, M.SHEET_METAL)
		"barn":
			_gable(boxes, outer, top_y, false, [M.CORRUGATED_IRON, M.SHEET_RUST, M.WOOD_DARK][rng.randi() % 3], wall, lot)
		"shed":
			_gable(boxes, outer, top_y, false, [M.SHEET_METAL, M.SHEET_RUST, M.SHEET_GREEN][rng.randi() % 3], wall, lot, 0.1)
		"hangar":
			_arch(boxes, outer, top_y, ARCH_RISE, [M.SHEET_METAL, M.SHEET_GREEN, M.FIBRE_CEMENT][rng.randi() % 3])
			# The doors' leaves slid back either side of the opening, on the front wall's face.
			for dr: Dictionary in b.doors:
				var at: Vector3 = dr.at
				if int(dr.rooms[1]) == -1 and absf(at.z - outer.end.y) < 0.6:
					var half_w := float(TYPES.hangar.door_w) * 0.5
					for side: float in [-1.0, 1.0]:
						var x0 := at.x + side * half_w
						var x1 := x0 + side * 3.0
						var lo := maxf(minf(x0, x1), outer.position.x + 0.1)
						var hi := minf(maxf(x0, x1), outer.end.x - 0.1)
						if hi - lo > 0.5:
							boxes.append([Vector3(lo, 0.1, outer.end.y), Vector3(hi, float(TYPES.hangar.door_h) + 0.2, outer.end.y + 0.1), M.SHEET_GREEN])
					break
		"tower":
			# A mast and windsock in a roof corner away from its stair, a beacon on top.
			var top_rooms: Array = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == int(b.storeys) - 1)
			var span := Rect2()
			for r: Dictionary in top_rooms:
				span = r.rect if not span.has_area() else span.merge(r.rect)
			var corners := [span.position + Vector2(0.2, 0.2), Vector2(span.end.x - 0.3, span.position.y + 0.2), Vector2(span.position.x + 0.2, span.end.y - 0.3), span.end - Vector2(0.3, 0.3)]
			var stair_keep: Array = []
			for st: Dictionary in b.stairs:
				stair_keep.append((st.foot as Rect2).merge(st.land).grow(1.0))
			for c: Vector2 in corners:
				if not stair_keep.any(func(r: Rect2) -> bool: return r.has_point(c)):
					boxes.append([Vector3(c.x, top_y, c.y), Vector3(c.x + 0.1, top_y + 4.0, c.y + 0.1), M.STEEL])
					boxes.append([Vector3(c.x - 0.05, top_y + 4.0, c.y - 0.05), Vector3(c.x + 0.15, top_y + 4.2, c.y + 0.15), M.SIGN_RED])
					var dir := -1.0 if c.x > span.get_center().x else 1.0
					for k in 3:
						var x0 := c.x + 0.1 + k * 0.4 if dir > 0.0 else c.x - 0.4 - k * 0.4
						skin.append([Vector3(x0, top_y + 3.4 - k * 0.1, c.y), Vector3(x0 + 0.4, top_y + 3.8 - k * 0.1, c.y + 0.1), M.SIGN_RED if k % 2 == 0 else M.TRIM_WHITE])
					break
		"pumphouse":
			# Its pipes: out of the front wall clear of the door, across the forecourt and into the ground.
			var spot: Variant = _clear_of([Vector2(outer.position.x + 0.5, outer.position.x + 1.0), Vector2(outer.end.x - 1.0, outer.end.x - 0.5)], doors_front)
			if spot != null:
				var x := (spot as Vector2).x
				boxes.append([Vector3(x, 0.5, outer.end.y), Vector3(x + 0.3, 0.8, lot.end.y - 0.4), M.STEEL])
				boxes.append([Vector3(x, 0.0, lot.end.y - 0.7), Vector3(x + 0.3, 0.5, lot.end.y - 0.4), M.STEEL])
				boxes.append([Vector3(x - 0.15, 0.8, lot.end.y - 1.4), Vector3(x + 0.45, 0.9, lot.end.y - 1.2), M.SIGN_RED])  # a valve wheel
		"drug_lab":
			for y: Dictionary in b.yards:
				var yr: Rect2 = y.rect
				var spot := _yard_spot(b, yr, Vector2(1.6, 1.0))
				if spot.has_area():  # a generator and its jerrycans
					boxes.append([Vector3(spot.position.x, 0, spot.position.y), Vector3(spot.position.x + 1.4, 1.0, spot.position.y + 0.9), M.STEEL_OLIVE])
					boxes.append([Vector3(spot.position.x + 0.2, 1.0, spot.position.y + 0.3), Vector3(spot.position.x + 0.4, 1.5, spot.position.y + 0.5), M.STEEL])
				var more := _yard_spot(b, yr, Vector2(2.0, 1.4))
				if more.has_area():  # blue chemical drums
					for k in 4:
						var at := Vector3(more.position.x + (k % 3) * 0.65, 0, more.position.y + (k / 3) * 0.7)
						boxes.append([at, at + Vector3(0.6, 0.9, 0.6), M.SIGN_BLUE])
				break
		"ied_workshop":
			for y: Dictionary in b.yards:
				var yr: Rect2 = y.rect
				var spot := _yard_spot(b, yr, Vector2(4.6, 2.2))
				if spot.has_area():  # a car being rigged
					_car(boxes, Vector3(spot.get_center().x, 0, spot.get_center().y), true, [M.TRIM_WHITE, M.STEEL_OLIVE, M.SIGN_YELLOW][rng.randi() % 3])
				var jugs := _yard_spot(b, yr, Vector2(1.4, 0.8))
				if jugs.has_area():  # yellow jugs
					for k in 4:
						var at := Vector3(jugs.position.x + (k % 2) * 0.5, 0, jugs.position.y + (k / 2) * 0.4)
						boxes.append([at, at + Vector3(0.4, 0.5, 0.3), M.SIGN_YELLOW])
				break
		"office":
			# A canopy over the front door (skin: above head height, out over the street).
			for dr: Dictionary in b.doors:
				var at: Vector3 = dr.at
				if int(dr.rooms[1]) == -1 and absf(at.z - outer.end.y) < 0.6:
					skin.append([Vector3(at.x - 1.6, 2.6, outer.end.y), Vector3(at.x + 1.6, 2.8, outer.end.y + 1.4), M.TRIM_DARK])
					break
	var height: float = b.height
	for bx: Array in boxes:
		height = maxf(height, (bx[1] as Vector3).y)
	b.height = height


## A free floor rect `size` (x, z) in yard `yr` of building `b`: off the yard's walls (0.1), its
## gate's and doorways' way through (1.4 m round), and every box there already. An empty Rect2
## if none.
static func _yard_spot(b: Dictionary, yr: Rect2, size: Vector2) -> Rect2:
	var ways: Array[Vector2] = []
	for y: Dictionary in b.yards:
		if y.gate != null:
			ways.append(Vector2((y.gate as Vector3).x, (y.gate as Vector3).z))
	for dr: Dictionary in b.doors:
		if int(dr.rooms[1]) == -1:
			ways.append(Vector2((dr.at as Vector3).x, (dr.at as Vector3).z))
	var inner := yr.grow(-0.15)
	for cand: Vector2 in [inner.position, Vector2(inner.end.x - size.x, inner.position.y), Vector2(inner.position.x, inner.end.y - size.y), inner.end - size,
			Vector2(inner.get_center().x - size.x * 0.5, inner.position.y)]:
		var r := Rect2(cand, size)
		if r.position.x < inner.position.x - 0.01 or r.end.x > inner.end.x + 0.01 or r.position.y < inner.position.y - 0.01 or r.end.y > inner.end.y + 0.01:
			continue
		if ways.any(func(p: Vector2) -> bool: return r.grow(1.4).has_point(p)):
			continue
		var hit := false
		for bx: Array in b.boxes:
			var lo: Vector3 = bx[0]
			var hi: Vector3 = bx[1]
			if lo.y < 1.6 and Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z).intersects(r.grow(0.1)):
				hit = true
				break
		if not hit:
			return r
	return Rect2()


## An octagon round (c.x, c.z) `r` across the flats, from `y0` to `y1`, as three boxes.
static func _octagon(out: Array, c: Vector3, r: float, y0: float, y1: float, mat: int) -> void:
	var a := r * 0.41
	var q := r * 0.71
	out.append([Vector3(c.x - r, y0, c.z - a), Vector3(c.x + r, y1, c.z + a), mat])
	out.append([Vector3(c.x - a, y0, c.z - r), Vector3(c.x + a, y1, c.z + r), mat])
	out.append([Vector3(c.x - q, y0, c.z - q), Vector3(c.x + q, y1, c.z + q), mat])


## A dome `r` round on a drum, its foot on `c` (the roof's top): octagonal courses 0.3 m high,
## each narrower as a sphere is. Returns its top.
static func _dome(out: Array, c: Vector3, r: float, mat: int, drum: int) -> float:
	_octagon(out, c, r + 0.2, c.y, c.y + 0.6, drum)
	var y := 0.0
	while y < r - 0.15:
		var ry := sqrt(r * r - pow(y + 0.15, 2.0))
		_octagon(out, c, ry, c.y + 0.6 + y, c.y + 0.9 + y, mat)
		y += 0.3
	return c.y + 0.6 + y


## A minaret on `foot`: a solid shaft to its balcony (a railed ledge round it at about three
## quarters of `h`), a slimmer shaft above, a stepped cap and a finial. No way in: it's solid.
static func _minaret(out: Array, foot: Rect2, h: float, mat: int, trim: int) -> void:
	var M := VoxelWorld.Mat
	var c := foot.get_center()
	var hb := snappedf(h * 0.72, 0.1)
	var half := foot.size.x * 0.5
	out.append([Vector3(foot.position.x, 0, foot.position.y), Vector3(foot.end.x, hb, foot.end.y), mat])
	out.append([Vector3(c.x - half - 0.3, hb, c.y - half - 0.3), Vector3(c.x + half + 0.3, hb + 0.2, c.y + half + 0.3), trim])
	var e := half + 0.3
	out.append([Vector3(c.x - e, hb + 0.2, c.y - e), Vector3(c.x + e, hb + 0.9, c.y - e + 0.1), trim])
	out.append([Vector3(c.x - e, hb + 0.2, c.y + e - 0.1), Vector3(c.x + e, hb + 0.9, c.y + e), trim])
	out.append([Vector3(c.x - e, hb + 0.2, c.y - e + 0.1), Vector3(c.x - e + 0.1, hb + 0.9, c.y + e - 0.1), trim])
	out.append([Vector3(c.x + e - 0.1, hb + 0.2, c.y - e + 0.1), Vector3(c.x + e, hb + 0.9, c.y + e - 0.1), trim])
	out.append([Vector3(c.x - half * 0.7, hb + 0.2, c.y - half * 0.7), Vector3(c.x + half * 0.7, h, c.y + half * 0.7), mat])
	out.append([Vector3(c.x - half * 0.9, h, c.y - half * 0.9), Vector3(c.x + half * 0.9, h + 0.3, c.y + half * 0.9), trim])
	out.append([Vector3(c.x - half * 0.6, h + 0.3, c.y - half * 0.6), Vector3(c.x + half * 0.6, h + 0.7, c.y + half * 0.6), trim])
	out.append([Vector3(c.x - half * 0.3, h + 0.7, c.y - half * 0.3), Vector3(c.x + half * 0.3, h + 1.1, c.y + half * 0.3), trim])
	out.append([Vector3(c.x - 0.05, h + 1.1, c.y - 0.05), Vector3(c.x + 0.05, h + 1.8, c.y + 0.05), M.STEEL])
	out.append([Vector3(c.x - 0.2, h + 1.8, c.y - 0.05), Vector3(c.x + 0.2, h + 1.9, c.y + 0.05), M.SIGN_YELLOW])


## A gable roof over `rect` (a shell's outside) from `y0`, its ridge along z (`along_z`) or x:
## sloping courses STEP_IN in and `rise` up each (a hollow roof: two strips a course, and the
## gable ends filled in `end_mat`), kept inside `lot`. Returns its top.
static func _gable(out: Array, rect: Rect2, y0: float, along_z: bool, mat: int, end_mat: int, lot: Rect2, rise := STEP_UP) -> float:
	var r := rect.grow(0.2).intersection(lot)  # eaves where the lot has room
	var across := r.size.x if along_z else r.size.y
	var half := across * 0.5
	var k := 0
	var top := y0
	while k * STEP_IN < half - 0.05:
		var a0 := k * STEP_IN
		var a1 := minf(a0 + STEP_IN + 0.2, half)
		var y := y0 + k * rise
		var ends := a1 < half - 0.01
		if along_z:
			out.append([Vector3(r.position.x + a0, y, r.position.y), Vector3(r.position.x + a1, y + rise, r.end.y), mat])
			out.append([Vector3(r.end.x - a1, y, r.position.y), Vector3(r.end.x - a0, y + rise, r.end.y), mat])
			if ends:
				out.append([Vector3(r.position.x + a1, y, rect.position.y), Vector3(r.end.x - a1, y + rise, rect.position.y + 0.2), end_mat])
				out.append([Vector3(r.position.x + a1, y, rect.end.y - 0.2), Vector3(r.end.x - a1, y + rise, rect.end.y), end_mat])
		else:
			out.append([Vector3(r.position.x, y, r.position.y + a0), Vector3(r.end.x, y + rise, r.position.y + a1), mat])
			out.append([Vector3(r.position.x, y, r.end.y - a1), Vector3(r.end.x, y + rise, r.end.y - a0), mat])
			if ends:
				out.append([Vector3(rect.position.x, y, r.position.y + a1), Vector3(rect.position.x + 0.2, y + rise, r.end.y - a1), end_mat])
				out.append([Vector3(rect.end.x - 0.2, y, r.position.y + a1), Vector3(rect.end.x, y + rise, r.end.y - a1), end_mat])
		top = y + rise
		k += 1
	return top


## A curved roof over `rect` (its ridge along z) from `y0`, `rise` high at the middle: sheet
## strips 0.5 m wide along a circle's arc, each joined to the next, and its ends closed.
static func _arch(out: Array, rect: Rect2, y0: float, rise: float, mat: int) -> void:
	var half := rect.size.x * 0.5
	var cx := rect.get_center().x
	var prev := y0
	var x := rect.position.x
	while x < rect.end.x - 0.01:
		var x1 := minf(x + 0.5, rect.end.x)
		var dx := absf((x + x1) * 0.5 - cx) / half
		var y := snappedf(y0 + rise * sqrt(maxf(1.0 - dx * dx, 0.0)), 0.1)
		var lo := minf(y, prev)
		out.append([Vector3(x, lo, rect.position.y), Vector3(x1, maxf(y, prev) + 0.1, rect.end.y), mat])
		if y > y0 + 0.05:  # the ends, closed
			out.append([Vector3(x, y0, rect.position.y), Vector3(x1, y, rect.position.y + 0.1), mat])
			out.append([Vector3(x, y0, rect.end.y - 0.1), Vector3(x1, y, rect.end.y), mat])
		prev = y
		x = x1


## A sawtooth roof over `room` from `y0`: teeth along x every 4 m, a glazed face and three
## sheet plates stepping down from it.
static func _sawtooth(out: Array, room: Rect2, y0: float, mat: int) -> void:
	var x := room.position.x + 0.5
	while x + 3.6 <= room.end.x:
		out.append([Vector3(x, y0, room.position.y), Vector3(x + 0.1, y0 + 1.2, room.end.y), VoxelWorld.Mat.GLASS])
		for j in 3:
			var y := y0 + 1.2 - j * 0.4
			out.append([Vector3(x + 0.1 + j * 1.15, y - 0.1, room.position.y), Vector3(x + 0.1 + (j + 1) * 1.15, y, room.end.y), mat])
		x += 4.0


## A bell tower on `foot` (its back on the church's front wall) `h` tall: walls with a doorway
## onto the street and one behind into the church at `door_x` (its porch), open belfry arches near
## the top, a bell, a stepped spire and a cross.
static func _bell_tower(out: Array, foot: Rect2, h: float, mat: int, roof_mat: int, trim: int, door_x: float) -> void:
	var M := VoxelWorld.Mat
	var t := 0.35
	var belfry := h - 3.2
	var arch := [foot.size.x * 0.5 - 0.6, foot.size.x * 0.5 + 0.6, belfry + 0.6, h - 0.6]  # an arch's span along its wall (from the wall's start)
	var door := [door_x - 0.7, door_x + 0.7, 0.0, DOOR_H]
	# South (+z, the street) and north (the church): a doorway each; west, east.
	_wall(out, 0, foot.end.y - t, foot.end.y, foot.position.x, foot.end.x, h, mat, [door, [foot.position.x + arch[0], foot.position.x + arch[1], arch[2], arch[3]]])
	_wall(out, 0, foot.position.y, foot.position.y + t, foot.position.x, foot.end.x, h, mat, [door, [foot.position.x + arch[0], foot.position.x + arch[1], arch[2], arch[3]]])
	_wall(out, 1, foot.position.x, foot.position.x + t, foot.position.y + t, foot.end.y - t, h, mat, [[foot.position.y + arch[0], foot.position.y + arch[1], arch[2], arch[3]]])
	_wall(out, 1, foot.end.x - t, foot.end.x, foot.position.y + t, foot.end.y - t, h, mat, [[foot.position.y + arch[0], foot.position.y + arch[1], arch[2], arch[3]]])
	var c := foot.get_center()
	out.append([Vector3(foot.position.x + t, belfry, foot.position.y + t), Vector3(foot.end.x - t, belfry + 0.2, foot.end.y - t), M.WOOD])  # the belfry floor
	out.append([Vector3(c.x - 0.1, h - 0.6, foot.position.y + t), Vector3(c.x + 0.1, h - 0.4, foot.end.y - t), M.WOOD_DARK])  # its beam
	out.append([Vector3(c.x - 0.4, h - 1.5, c.y - 0.4), Vector3(c.x + 0.4, h - 0.6, c.y + 0.4), M.STEEL_OLIVE])  # the bell
	out.append([Vector3(foot.position.x - 0.1, h, foot.position.y - 0.1), Vector3(foot.end.x + 0.1, h + 0.2, foot.end.y + 0.1), trim])
	var y := h + 0.2
	for k in 5:
		var s := foot.size.x * 0.5 * (1.0 - k * 0.2)
		out.append([Vector3(c.x - s, y, c.y - s), Vector3(c.x + s, y + 0.7, c.y + s), roof_mat])
		y += 0.7
	out.append([Vector3(c.x - 0.05, y, c.y - 0.05), Vector3(c.x + 0.05, y + 1.2, c.y + 0.05), M.STEEL])
	out.append([Vector3(c.x - 0.35, y + 0.7, c.y - 0.05), Vector3(c.x + 0.35, y + 0.8, c.y + 0.05), M.STEEL])


## A chimney stack on `foot`, `h` tall: a hollow square of `mat` with a dark band at its top.
static func _chimney(out: Array, foot: Rect2, h: float, mat: int, trim: int) -> void:
	var t := 0.3
	_wall(out, 0, foot.position.y, foot.position.y + t, foot.position.x, foot.end.x, h, mat, [])
	_wall(out, 0, foot.end.y - t, foot.end.y, foot.position.x, foot.end.x, h, mat, [])
	_wall(out, 1, foot.position.x, foot.position.x + t, foot.position.y + t, foot.end.y - t, h, mat, [])
	_wall(out, 1, foot.end.x - t, foot.end.x, foot.position.y + t, foot.end.y - t, h, mat, [])
	out.append([Vector3(foot.position.x - 0.1, h - 1.0, foot.position.y - 0.1), Vector3(foot.end.x + 0.1, h - 0.6, foot.end.y + 0.1), VoxelWorld.Mat.TRIM_DARK])
	out.append([Vector3(foot.position.x, 0, foot.position.y), Vector3(foot.end.x, 1.0, foot.end.y), trim])  # its base


## A railing from `a` to `b` (x, z; straight along x or z): posts every 2 m, a top rail, gaps
## where `gaps` (x spans) cross it.
static func _railing(out: Array, a: Vector2, b: Vector2, gaps: Array) -> void:
	var M := VoxelWorld.Mat
	var along_x := absf(b.x - a.x) >= absf(b.y - a.y)
	var from := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var to := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var runs: Array = []
	var start := from
	var sorted := gaps.filter(func(g: Variant) -> bool: return g is Vector2)
	sorted.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	for g: Vector2 in sorted:
		if g.x > start + 0.3 and along_x:
			runs.append(Vector2(start, minf(g.x, to)))
		start = maxf(start, g.y)
	if start < to - 0.3:
		runs.append(Vector2(start, to))
	if not along_x:
		runs = [Vector2(from, to)]
	for run: Vector2 in runs:
		var p := run.x
		while p <= run.y - 0.09:
			var q := Vector3(p, 0, a.y) if along_x else Vector3(a.x, 0, p)
			out.append([q, q + Vector3(0.1, 1.1, 0.1), M.STEEL])
			p += 2.0
		if along_x:
			out.append([Vector3(run.x, 1.0, a.y), Vector3(run.y, 1.1, a.y + 0.1), M.STEEL])
		else:
			out.append([Vector3(a.x, 1.0, run.x), Vector3(a.x + 0.1, 1.1, run.y), M.STEEL])


## A fuel station's forecourt (`apron`): a canopy on four columns with a fascia in its sign colour,
## two pump islands under it, a price board on a pylon at the corner, the tanks' fill caps.
static func _fuel_canopy(boxes: Array, skin: Array, apron: Rect2, look: Dictionary, rng: RandomNumberGenerator) -> void:
	var M := VoxelWorld.Mat
	var z0 := apron.position.y + 1.5
	var z1 := apron.end.y - 1.0
	var x0 := apron.position.x + 0.4
	var x1 := apron.end.x - 0.4
	for c: Vector2 in [Vector2(x0 + 0.6, z0 + 0.6), Vector2(x1 - 1.0, z0 + 0.6), Vector2(x0 + 0.6, z1 - 1.0), Vector2(x1 - 1.0, z1 - 1.0)]:
		boxes.append([Vector3(c.x, 0, c.y), Vector3(c.x + 0.4, CANOPY_H, c.y + 0.4), M.TRIM_WHITE])
	boxes.append([Vector3(x0, CANOPY_H, z0), Vector3(x1, CANOPY_H + 0.3, z1), M.SHEET_METAL])
	var sign: int = look.sign
	skin.append([Vector3(x0, CANOPY_H - 0.2, z0), Vector3(x1, CANOPY_H + 0.5, z0 + 0.1), sign])
	skin.append([Vector3(x0, CANOPY_H - 0.2, z1 - 0.1), Vector3(x1, CANOPY_H + 0.5, z1), sign])
	skin.append([Vector3(x0, CANOPY_H - 0.2, z0 + 0.1), Vector3(x0 + 0.1, CANOPY_H + 0.5, z1 - 0.1), sign])
	skin.append([Vector3(x1 - 0.1, CANOPY_H - 0.2, z0 + 0.1), Vector3(x1, CANOPY_H + 0.5, z1 - 0.1), sign])
	var zc := snappedf((z0 + z1) * 0.5, 0.1)
	for ix: float in [-0.25, 0.25]:
		var cx := snappedf((x0 + x1) * 0.5 + ix * (x1 - x0), 0.1)
		boxes.append([Vector3(cx - 1.6, 0, zc - 0.5), Vector3(cx + 1.6, 0.2, zc + 0.5), M.CONCRETE])
		for px: float in [-1.0, 0.5]:
			boxes.append([Vector3(cx + px, 0.2, zc - 0.25), Vector3(cx + px + 0.5, 1.8, zc + 0.25), sign])
			boxes.append([Vector3(cx + px, 1.8, zc - 0.25), Vector3(cx + px + 0.5, 2.0, zc + 0.25), M.TRIM_WHITE])
	var px := apron.end.x - 0.5 if rng.randf() < 0.5 else apron.position.x + 0.2
	var pz := apron.end.y - 0.5
	boxes.append([Vector3(px, 0, pz), Vector3(px + 0.3, 5.6, pz + 0.3), M.STEEL])
	var bx0 := clampf(px - 0.8, apron.position.x, apron.end.x - 1.9)
	boxes.append([Vector3(bx0, 3.8, pz + 0.3), Vector3(bx0 + 1.9, 5.4, pz + 0.4), sign])
	skin.append([Vector3(bx0 + 0.2, 4.0, pz + 0.3), Vector3(bx0 + 1.7, 4.8, pz + 0.4), M.TRIM_WHITE])
	for k in 2:
		var cap := Vector3(x0 + 1.5 + k * 1.2, 0, z1 + 0.3)
		boxes.append([cap, cap + Vector3(0.6, 0.1, 0.6), M.STEEL])


## A car (or a wreck in its colours) on the ground at `at` (its middle), along x or z: a body,
## a cabin with dark glass, four wheels.
static func _car(out: Array, at: Vector3, along_x: bool, mat: int) -> void:
	var M := VoxelWorld.Mat
	var put := func(a: Vector3, b: Vector3, m: int) -> void:
		if along_x:
			out.append([at + a, at + b, m])
		else:
			out.append([at + Vector3(a.z, a.y, a.x), at + Vector3(b.z, b.y, b.x), m])
	put.call(Vector3(-2.1, 0.3, -0.85), Vector3(2.1, 1.0, 0.85), mat)
	put.call(Vector3(-1.1, 1.0, -0.75), Vector3(1.0, 1.4, 0.75), M.TRIM_DARK)
	put.call(Vector3(-1.0, 1.4, -0.75), Vector3(0.9, 1.5, 0.75), mat)
	for wx: float in [-1.5, 1.0]:
		for wz: float in [-0.95, 0.75]:
			put.call(Vector3(wx, 0, wz), Vector3(wx + 0.6, 0.6, wz + 0.2), M.TRIM_DARK)


## A shipping container (6.1 x 2.4 x 2.6 m) at `at` (its middle, on whatever it stands on),
## along x or z: sheet walls, its doors at one end opened back (a way in: a nook to fight from).
## `stacked`: one up on another, closed, with DECK_EVERY decks inside (no room in it to stand).
static func _container(out: Array, at: Vector3, along_x: bool, mat: int, stacked: int) -> void:
	var put := func(a: Vector3, b: Vector3, m: int) -> void:
		if along_x:
			out.append([at + a, at + b, m])
		else:
			out.append([at + Vector3(a.z, a.y, a.x), at + Vector3(b.z, b.y, b.x), m])
	put.call(Vector3(-3.05, 0, -1.2), Vector3(3.05, 0.1, 1.2), mat)  # floor
	put.call(Vector3(-3.05, 2.5, -1.2), Vector3(3.05, 2.6, 1.2), mat)  # roof
	put.call(Vector3(-3.05, 0.1, -1.2), Vector3(3.05, 2.5, -1.1), mat)
	put.call(Vector3(-3.05, 0.1, 1.1), Vector3(3.05, 2.5, 1.2), mat)
	put.call(Vector3(-3.05, 0.1, -1.1), Vector3(-2.95, 2.5, 1.1), mat)  # the closed end
	if stacked > 0:
		put.call(Vector3(2.95, 0.1, -1.1), Vector3(3.05, 2.5, 1.1), mat)
		put.call(Vector3(-2.95, 1.3, -1.1), Vector3(2.95, 1.4, 1.1), mat)
	else:  # the doors, swung back along its sides
		put.call(Vector3(3.05, 0.1, -2.3), Vector3(3.15, 2.5, -1.2), mat)
		put.call(Vector3(3.05, 0.1, 1.2), Vector3(3.15, 2.5, 2.3), mat)


## A closed tank (or silo) `r` across, `h` tall, its foot at `c`: an octagonal sheet ring, a roof,
## DECK_EVERY decks inside (nobody stands in it), a ladder up its side (`ladder`: the side, "",
## none) and a band. Hollow: a blast or a charge holes it like a real one.
static func _tank(out: Array, c: Vector3, r: float, h: float, mat: int, band: int, ladder := "") -> void:
	var shell: Array = []
	_octagon(shell, c, r, c.y, c.y + h, mat)
	var inner: Array = []
	_octagon(inner, c, r - 0.2, c.y - 0.01, c.y + h - 0.2, mat)
	for hole: Array in inner:
		shell = _carve(shell, AABB(hole[0], (hole[1] as Vector3) - (hole[0] as Vector3)))
	out.append_array(shell)
	var y := c.y + DECK_EVERY
	while y < c.y + h - 0.4:
		_octagon(out, c, r - 0.2, y, y + 0.1, mat)
		y += DECK_EVERY
	_octagon(out, c, r * 0.6, c.y + h, c.y + h + 0.3, mat)  # its crown
	_octagon(out, c, r + 0.05, c.y + h * 0.45, c.y + h * 0.45 + 0.3, band)
	if ladder != "":
		var d := {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "w": Vector3(-1, 0, 0), "e": Vector3(1, 0, 0)}[ladder] as Vector3
		var p := c + d * (r + 0.15)
		out.append([p - Vector3(0.25, 0, 0.25), p + Vector3(0.25, h + 1.0, 0.25), VoxelWorld.Mat.STEEL])


## A horizontal tank (a separator, a tanker's barrel) `r` round, `l` long along x, its middle at
## `c` (`c.y` its axis' height): an octagon's three boxes on their side.
static func _barrel(out: Array, c: Vector3, r: float, l: float, mat: int) -> void:
	var a := r * 0.41
	var q := r * 0.71
	out.append([Vector3(c.x - l * 0.5, c.y - r, c.z - a), Vector3(c.x + l * 0.5, c.y + r, c.z + a), mat])
	out.append([Vector3(c.x - l * 0.5, c.y - a, c.z - r), Vector3(c.x + l * 0.5, c.y + a, c.z + r), mat])
	out.append([Vector3(c.x - l * 0.5, c.y - q, c.z - q), Vector3(c.x + l * 0.5, c.y + q, c.z + q), mat])


# --- Ruins (queue item 1.4) ----------------------------------------------------------------------

## Proposed: a ruined building has RUIN_BREACHES [min, max] holes knocked through its outside
## walls and RUIN_ROOF_HOLES holes in its roof (rubble under each); a bombed-out one more of both,
## a back corner fallen in (RUIN_CORNER of its width and depth: everything over it from 0.4-1.2 m
## up gone, a heap of rubble in it), its upper storey's walls broken down and its roof gone.
## Rubble heaps stand RUBBLE_H high at most and never on a doorway's way through or a stair.
const RUIN_BREACHES := {RUINED: Vector2i(2, 3), BOMBED: Vector2i(3, 5)}
const RUIN_ROOF_HOLES := {RUINED: Vector2i(1, 2), BOMBED: Vector2i(2, 3)}
const RUIN_CORNER := Vector2(0.3, 0.45)
const RUBBLE_H := 1.3
## Scorch round a breach (skin): this much past the hole.
const SCORCH_M := 0.4


## Building `b` ruined (RUINED) or bombed out (BOMBED), in place: holes carved through its boxes
## and skin (_carve), rubble heaped under them, scorch round the breaches. Its stairs, their
## landings and every doorway's way through are kept: the rooms that were reachable still are,
## unless a fallen corner buries a doorway ("buried": their "at"s). A bombed-out
## building's roof comes down, so its stair up there goes ("stairs", "roof_access").
static func _ruin(b: Dictionary, level: int, walls: Array, look: Dictionary, seed: int, outer: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "ruin", level])
	var M := VoxelWorld.Mat
	var holes: Array[AABB] = []
	var heaps: Array = []  # [Rect2 footprint, floor y, height, Vector2 (the corner it's piled toward, or INF)]
	var scorch: Array = []
	# Never carved: every stair, its stairwell and its landing, and a man's height over them.
	var keep: Array[AABB] = []
	for st: Dictionary in b.stairs:
		var foot: Rect2 = (st.foot as Rect2).merge(st.get("land", st.foot)).grow(0.5)
		keep.append(AABB(Vector3(foot.position.x, float(st.from_y) - 0.05, foot.position.y), Vector3(foot.size.x, float(st.to_y) - float(st.from_y) + 2.4, foot.size.y)))
	# Floor rubble stays off: each doorway's way through, the stairs and their feet.
	var clear: Array = []
	for dr: Dictionary in b.doors:
		var at: Vector3 = dr.at
		clear.append([Rect2(at.x - 1.3, at.z - 1.3, 2.6, 2.6), at.y])
	for st: Dictionary in b.stairs:
		var foot: Rect2 = (st.foot as Rect2).merge(st.get("land", st.foot)).grow(STAIR_APPROACH + 0.6)
		clear.append([foot, float(st.from_y)])
		clear.append([foot, float(st.to_y)])
	var top_floor := int(b.storeys) - 1
	var roof_slab := float(b.roof_y) - 0.2  # (a roof slab is 0.1-0.2 m)
	# Breaches through the outside walls, with rubble fallen inward and scorch round them.
	var range_b: Vector2i = RUIN_BREACHES[level]
	var outside: Array = walls.filter(func(w: Dictionary) -> bool: return not w.parapet and float(w.to) - float(w.from) >= 2.6)
	for n in rng.randi_range(range_b.x, range_b.y):
		if outside.is_empty():
			break
		var w: Dictionary = outside[rng.randi() % outside.size()]
		var width := minf(rng.randf_range(1.0, 2.6 if level == RUINED else 3.4), float(w.to) - float(w.from) - 0.8)
		var a0 := snappedf(rng.randf_range(float(w.from) + 0.4, float(w.to) - 0.4 - width), 0.1)
		var a1 := snappedf(a0 + width, 0.1)
		var y0 := snappedf(rng.randf_range(0.3, 0.9) if level == RUINED else rng.randf_range(0.0, 0.5), 0.1)
		var y1 := minf(float(w.h), snappedf(y0 + rng.randf_range(1.2, 2.4), 0.1))
		holes.append(_wall_hole(w, a0, a1, y0, y1))
		var r0 := snappedf(lerpf(a0, a1, rng.randf_range(0.15, 0.4)), 0.1)
		var r1 := snappedf(lerpf(a0, a1, rng.randf_range(0.6, 0.85)), 0.1)
		holes.append(_wall_hole(w, r0, r1, y1 - 0.1, minf(float(w.h), y1 + snappedf(rng.randf_range(0.2, 0.7), 0.1))))  # ragged above
		_face_boxes(scorch, w, a0 - SCORCH_M, a1 + SCORCH_M, maxf(y0 - SCORCH_M, 0.0), minf(y1 + SCORCH_M, float(w.h)), M.TRIM_DARK)
		var line: float = w.line
		var t: float = w.t
		var inward: Rect2
		match String(w.side):
			"n": inward = Rect2(a0, line, a1 - a0, 0.9)
			"s": inward = Rect2(a0, line - 0.9, a1 - a0, 0.9)
			"w": inward = Rect2(line, a0, 0.9, a1 - a0)
			_: inward = Rect2(line - 0.9, a0, 0.9, a1 - a0)
		heaps.append([inward, float(w.base), snappedf(rng.randf_range(0.3, 0.5), 0.1), Vector2.INF])
	# Holes in the roof (and rubble on the floor under each): in the top floor's rooms.
	var tops: Array = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == top_floor)
	var range_r: Vector2i = RUIN_ROOF_HOLES[level]
	for n in rng.randi_range(range_r.x, range_r.y):
		if tops.is_empty():
			break
		var room: Dictionary = tops[rng.randi() % tops.size()]
		var rr: Rect2 = room.rect
		var big := 4.5 if level == BOMBED else 3.5
		var sx := snappedf(minf(rng.randf_range(1.4, big), rr.size.x - 0.4), 0.1)
		var sz := snappedf(minf(rng.randf_range(1.4, big), rr.size.y - 0.4), 0.1)
		if sx < 1.0 or sz < 1.0:
			continue
		var at := Vector2(snappedf(rng.randf_range(rr.position.x + 0.2, rr.end.x - 0.2 - sx), 0.1), snappedf(rng.randf_range(rr.position.y + 0.2, rr.end.y - 0.2 - sz), 0.1))
		var hole := Rect2(at, Vector2(sx, sz))
		holes.append(AABB(Vector3(hole.position.x, roof_slab - 0.01, hole.position.y), Vector3(hole.size.x, 60.0, hole.size.y)))
		heaps.append([hole.grow(-0.2), float(room.y), snappedf(rng.randf_range(0.4, 0.8), 0.1), hole.get_center()])
	var buried: Array = []
	if level == BOMBED:
		# A back corner fallen in.
		var cw := snappedf(outer.size.x * rng.randf_range(RUIN_CORNER.x, RUIN_CORNER.y), 0.1)
		var cd := snappedf(outer.size.y * rng.randf_range(RUIN_CORNER.x, RUIN_CORNER.y), 0.1)
		var corners: Array = [Vector2(outer.position.x, outer.position.y), Vector2(outer.end.x - cw, outer.position.y)]
		if rng.randf() < 0.5:
			corners.reverse()
		for k in 4:
			var c: Vector2 = corners[k % 2]
			var r := Rect2(c, Vector2(cw, cd) * (1.0 if k < 2 else 0.6))
			if k >= 2 and c.x > outer.position.x + 0.01:
				r.position.x = outer.end.x - r.size.x
			var cut := AABB(Vector3(r.position.x - 0.6, snappedf(rng.randf_range(0.4, 1.2), 0.1), r.position.y - 0.6), Vector3(r.size.x + 0.6, 60.0, r.size.y + 0.6))
			if keep.any(func(kb: AABB) -> bool: return kb.intersects(cut)):
				continue
			holes.append(cut)
			var corner := Vector2(r.position.x if c.x <= outer.position.x + 0.01 else r.end.x, r.position.y)
			heaps.append([r.intersection(outer.grow(-0.05)), 0.0, RUBBLE_H, corner])
			for dr: Dictionary in b.doors:
				var at: Vector3 = dr.at
				if r.grow(0.3).has_point(Vector2(at.x, at.z)):
					buried.append(at)
			b.loot = (b.loot as Array).filter(func(l: Dictionary) -> bool: return not r.grow(0.2).has_point(Vector2((l.at as Vector3).x, (l.at as Vector3).z)))
			break
		# The roof comes down (two storeys: all of it, and the walls up there broken; one storey:
		# the holes above); its stair up goes with it.
		if int(b.storeys) == 2:
			holes.append(AABB(Vector3(outer.position.x - 1.0, roof_slab - 0.01, outer.position.y - 1.0), Vector3(outer.size.x + 2.0, 60.0, outer.size.y + 2.0)))
			for w: Dictionary in walls:
				if w.parapet or absf(float(w.base)) < 0.01:
					continue
				var a := float(w.from)
				while a < float(w.to) - 0.2:
					var seg := minf(snappedf(rng.randf_range(1.0, 3.0), 0.1), float(w.to) - a)
					holes.append(_wall_hole(w, a, a + seg, snappedf(rng.randf_range(0.8, float(w.h)), 0.1), float(w.h) + 0.5))
					a += seg
			_drop_roof_stair(b)
	# Carve: the holes less what's kept, out of the structure, the skin and the scorch.
	var cuts: Array[AABB] = []
	for hole: AABB in holes:
		var pieces: Array[AABB] = [hole]
		for kb: AABB in keep:
			var next: Array[AABB] = []
			for p: AABB in pieces:
				next.append_array(_subtract_aabb(p, kb))
			pieces = next
		cuts.append_array(pieces)
	var boxes: Array = b.boxes
	var skin: Array = (b.skin as Array) + scorch
	for cut: AABB in cuts:
		boxes = _carve(boxes, cut)
		skin = _carve(skin, cut)
	# Rubble: stepped heaps, kept off the doorways and stairs.
	var mats: Array = [look.wall, look.wall, M.CONCRETE]
	for heap: Array in heaps:
		var foot: Rect2 = heap[0]
		var y: float = heap[1]
		var hh: float = heap[2]
		var toward: Vector2 = heap[3]
		if not foot.has_area():
			continue
		var blocked := clear.any(func(c: Array) -> bool: return absf(float(c[1]) - y) < 0.5 and (c[0] as Rect2).intersects(foot))
		if blocked:
			if hh > 1.0:  # a fallen corner's heap: its outer part still stands, low enough to cross
				hh = 0.2
			else:
				continue
		var steps := maxi(1, ceili(hh / 0.4))
		for k in steps:
			var share := 1.0 - float(k) / steps * 0.75
			var r := Rect2(foot.position, foot.size * share)
			if toward.is_finite():  # piled toward the corner, or the middle of the hole above
				r.position = Vector2(clampf(toward.x - r.size.x * 0.5, foot.position.x, foot.end.x - r.size.x),
					clampf(toward.y - r.size.y * 0.5, foot.position.y, foot.end.y - r.size.y))
			else:
				r.position = foot.position + (foot.size - r.size) * 0.5
			var y0 := y + (0.0 if k == 0 else minf(0.2 + (k - 1) * 0.4, hh))
			var y1 := y + minf(0.2 + k * 0.4, hh) if steps > 1 else y + hh
			if y1 - y0 < 0.05:
				continue
			boxes.append([Vector3(snappedf(r.position.x, 0.1), y0, snappedf(r.position.y, 0.1)), Vector3(snappedf(r.end.x, 0.1), y1, snappedf(r.end.y, 0.1)),
				mats[rng.randi() % mats.size()]])
	b.boxes = boxes
	b.skin = skin
	b.ruin = level
	b.buried = buried


## Building `b`'s stair up onto its roof taken out of its "stairs" and "doors" (the roof's gone):
## no ramp for the navmesh, no way up for the AI. Its steps stay, up to nothing.
static func _drop_roof_stair(b: Dictionary) -> void:
	if not b.roof_access:
		return
	var roof_top := float(b.roof_y)
	b.stairs = (b.stairs as Array).filter(func(st: Dictionary) -> bool: return absf(float(st.to_y) - roof_top) > 0.05)
	b.doors = (b.doors as Array).filter(func(dr: Dictionary) -> bool: return int(dr.rooms[1]) != -2)
	b.roof_access = false


## A hole through outside wall `w` (_shell's record) from `a0` to `a1` along it and `y0` to `y1`
## over its base: its whole thickness and anything standing proud of its face.
static func _wall_hole(w: Dictionary, a0: float, a1: float, y0: float, y1: float) -> AABB:
	var line: float = w.line
	var t: float = w.t
	var base: float = w.base
	var lo_y := base + y0
	var hy := maxf(y1 - y0, 0.1)
	match String(w.side):
		"n": return AABB(Vector3(a0, lo_y, line - t - 0.6), Vector3(a1 - a0, hy, t + 0.61))
		"s": return AABB(Vector3(a0, lo_y, line - 0.01), Vector3(a1 - a0, hy, t + 0.61))
		"w": return AABB(Vector3(line - t - 0.6, lo_y, a0), Vector3(t + 0.61, hy, a1 - a0))
	return AABB(Vector3(line - 0.01, lo_y, a0), Vector3(t + 0.61, hy, a1 - a0))


## `list` ([lo, hi, Mat] boxes) with `hole` taken out: each box it cuts is split into the pieces
## round it (up to six), slivers under a voxel dropped.
static func _carve(list: Array, hole: AABB) -> Array:
	var out: Array = []
	for bx: Array in list:
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		var box := AABB(lo, hi - lo)
		if not box.intersects(hole):
			out.append(bx)
			continue
		for piece: AABB in _subtract_aabb(box, hole):
			if piece.size.x > 0.04 and piece.size.y > 0.04 and piece.size.z > 0.04:
				out.append([piece.position, piece.end, bx[2]])
	return out


## `a` less `c`: the pieces of `a` outside `c` (none overlapping), or [a] if they don't meet.
static func _subtract_aabb(a: AABB, c: AABB) -> Array[AABB]:
	var i := a.intersection(c)
	if not i.has_volume():
		return [a]
	var out: Array[AABB] = []
	if i.position.y > a.position.y:
		out.append(AABB(a.position, Vector3(a.size.x, i.position.y - a.position.y, a.size.z)))
	if i.end.y < a.end.y:
		out.append(AABB(Vector3(a.position.x, i.end.y, a.position.z), Vector3(a.size.x, a.end.y - i.end.y, a.size.z)))
	var y0 := i.position.y
	var hy := i.size.y
	if i.position.x > a.position.x:
		out.append(AABB(Vector3(a.position.x, y0, a.position.z), Vector3(i.position.x - a.position.x, hy, a.size.z)))
	if i.end.x < a.end.x:
		out.append(AABB(Vector3(i.end.x, y0, a.position.z), Vector3(a.end.x - i.end.x, hy, a.size.z)))
	if i.position.z > a.position.z:
		out.append(AABB(Vector3(i.position.x, y0, a.position.z), Vector3(i.size.x, hy, i.position.z - a.position.z)))
	if i.end.z < a.end.z:
		out.append(AABB(Vector3(i.position.x, y0, i.end.z), Vector3(i.size.x, hy, a.end.z - i.end.z)))
	return out


# --- Landmark sites (queue item 1.4) -------------------------------------------------------------

## Landmark sites (ZoneModules "lm#<kind>#<seed>#<ruin>#<turn>"): one of LANDMARK_TYPES' buildings
## alone on its lot, or a site of several buildings and props.
const SITE_KINDS: Array[String] = ["mosque", "church", "school", "garage", "fuel_station", "fuel_depot", "factory", "farm", "harbour",
	"airfield", "oil_field", "drug_lab", "ied_workshop", "office"]
## Proposed: the open ground kept round a lone landmark (m), an airfield's runway (length and width,
## m: a strip for light aircraft and helicopters, painted on the ground: no voxels), a harbour's
## piers (how far they reach out past the quay, m) and how high its quay stands over the sea.
const SITE_MARGIN := 3.0
const RUNWAY := Vector2(240.0, 22.0)
const PIER_L := 30.0
const QUAY_OVER_SEA := 1.6
## A harbour's quay edge (z, its own metres: the sea is toward -z before it's turned).
const QUAY_Z := -10.0


## A landmark site of `kind` (SITE_KINDS) from `seed`, `ruin` (INTACT, RUINED, BOMBED: every
## building and prop in it), turned `turn` quarter turns (_rot). {"boxes", "skin", "buildings"
## ([{"type", "origin", "turn", "data" (building())}]), "half" (Vector2: its footprint's half
## size, m), "pad" (Rect2: the flat ground it stands on, its own metres), "pad_sea" (the pad's
## height over the sea: a harbour's quay; NAN: the ground's own), "streets" (Rect2s: hard
## standing painted on its pad: a runway, a forecourt, a quay), "points" ({"objective", "cache",
## "intel"}), "garrison", "garrison_face", "ramps" (its stairs' ramp_faces for the navmesh),
## "loot" (ZoneModules.LOOT entries), "below" (m its voxels reach under the ground), "extent"
## (Vector2: its voxels' half size), "kind", "ruin"}. The same seed builds the same site.
static func site(kind: String, seed: int, ruin := INTACT, turn := 0) -> Dictionary:
	var s := {"boxes": [], "skin": [], "buildings": [], "streets": [], "posts": [], "props": [], "kind": kind, "ruin": ruin,
		"pad_sea": NAN, "below": 0.8}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind])
	match kind:
		"farm":
			_farm(s, rng, seed, ruin)
		"fuel_depot":
			_fuel_depot(s, rng, seed, ruin)
		"harbour":
			_harbour(s, rng, seed, ruin)
		"airfield":
			_airfield(s, rng, seed, ruin)
		"oil_field":
			_oil_field(s, rng, seed, ruin)
		_:
			var b := _site_building(s, kind, seed, Vector3.ZERO, 0, ruin)
			var size: Vector2 = b.size
			if kind in ["fuel_station", "garage", "factory"]:  # its forecourt: hard standing
				var apron := float(b.get("apron", 0.0))
				(s.streets as Array).append(Rect2(-size.x * 0.5, size.y * 0.5 - apron, size.x, apron + SITE_MARGIN))
	if ruin != INTACT:
		_ruin_props(s, rng, ruin)
	_site_finish(s, seed)
	if turn % 4 != 0:
		_turn_site(s, turn % 4)
	s.erase("props")
	s.erase("posts")
	return s


## Building `type` (seed `seed`, ruin `ruin`) placed in site `s` at `origin`, turned `turn`.
static func _site_building(s: Dictionary, type: String, seed: int, origin: Vector3, turn: int, ruin: int, style := "") -> Dictionary:
	var b := building(type, seed, style, ruin)
	for bx: Array in b.boxes:
		(s.boxes as Array).append(_turn_box(bx, turn, origin))
	for bx: Array in b.skin:
		(s.skin as Array).append(_turn_box(bx, turn, origin))
	(s.buildings as Array).append({"type": type, "origin": origin, "turn": turn, "data": b})
	return b


## A point turned `k` quarter turns about y (k 1: +z to +x; 2: round, as a town's far side).
static func _rot(p: Vector3, k: int) -> Vector3:
	match posmod(k, 4):
		1: return Vector3(p.z, p.y, -p.x)
		2: return Vector3(-p.x, p.y, -p.z)
		3: return Vector3(-p.z, p.y, p.x)
	return p


static func _turn_box(bx: Array, k: int, origin: Vector3) -> Array:
	var a := _rot(bx[0], k) + origin
	var c := _rot(bx[1], k) + origin
	return [a.min(c), a.max(c), bx[2]]


static func _turn_rect(r: Rect2, k: int) -> Rect2:
	var a := _rot(Vector3(r.position.x, 0, r.position.y), k)
	var c := _rot(Vector3(r.end.x, 0, r.end.y), k)
	return Rect2(minf(a.x, c.x), minf(a.z, c.z), absf(c.x - a.x), absf(c.z - a.z))


## Site `s` turned `k` quarter turns about its origin: everything in it.
static func _turn_site(s: Dictionary, k: int) -> void:
	s.boxes = (s.boxes as Array).map(func(bx: Array) -> Array: return _turn_box(bx, k, Vector3.ZERO))
	s.skin = (s.skin as Array).map(func(bx: Array) -> Array: return _turn_box(bx, k, Vector3.ZERO))
	s.streets = (s.streets as Array).map(func(r: Rect2) -> Rect2: return _turn_rect(r, k))
	s.pad = _turn_rect(s.pad, k)
	s.garrison = (s.garrison as Array).map(func(p: Vector3) -> Vector3: return _rot(p, k))
	s.garrison_face = (s.garrison_face as Array).map(func(p: Vector3) -> Vector3: return _rot(p, k))
	for key: String in s.points:
		s.points[key] = (s.points[key] as Array).map(func(p: Vector3) -> Vector3: return _rot(p, k))
	for l: Dictionary in s.loot:
		l.pos = _rot(l.pos, k)
	var ramps := PackedVector3Array()
	for p: Vector3 in s.ramps:
		ramps.append(_rot(p, k))
	s.ramps = ramps
	for b: Dictionary in s.buildings:
		b.origin = _rot(b.origin, k)
		b.turn = posmod(int(b.turn) + k, 4)
	if k % 2 == 1:
		s.half = Vector2((s.half as Vector2).y, (s.half as Vector2).x)
		s.extent = Vector2((s.extent as Vector2).y, (s.extent as Vector2).x)
	s.turn = k


## Site `s`'s garrison posts, loot, named points, stair ramps and its footprint, from its buildings
## and props: in every building a post just inside its front door, one up high (an upper window or
## its roof) in every other, one in the back room of the bigger ones; the site's own posts
## ("posts": [pos, face]); loot at its spots (TOWN_LOOT, LANDMARK_LOOT), LANDMARK_LOOT_MAX at most.
static func _site_finish(s: Dictionary, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "site"])
	var garrison: Array = []
	var face: Array = []
	var loot: Array = []
	var points := {"objective": [], "cache": [], "intel": []}
	var ramps := PackedVector3Array()
	var tables := TOWN_LOOT.merged(LANDMARK_LOOT)
	for i in (s.buildings as Array).size():
		var bt: Dictionary = s.buildings[i]
		var b: Dictionary = bt.data
		var turn: int = bt.turn
		var origin: Vector3 = bt.origin
		var place := func(p: Vector3) -> Vector3: return _rot(p, turn) + origin
		var fd: Variant = front_door(b)
		for dr: Dictionary in b.doors:
			var at: Vector3 = dr.at
			if fd != null and at == (fd as Vector3):
				var post := at + Vector3(0, 0.1, -1.0)
				if _clear_standing(b.boxes, post):
					garrison.append(place.call(post))
					face.append(_rot(Vector3(0, 0, 1), turn))
				break
		if i % 2 == 0 or (s.buildings as Array).size() == 1:
			var high := _high_post(b, i)
			if not high.is_empty():
				garrison.append(place.call(high[0]))
				face.append(_rot(high[1], turn))
		var mine := garrison.size()
		if (b.rooms as Array).size() >= 2 or garrison.size() < 2:
			var back := _room_post(b, _back_room(b))
			if back.is_finite():
				garrison.append(place.call(back))
				face.append(Vector3.ZERO)
		for r: Dictionary in b.rooms:  # a lone building held by two at least: one in another room
			if (s.buildings as Array).size() > 1 or garrison.size() >= 2 or String(r.role) == "bathroom":
				break
			var c: Vector2 = (r.rect as Rect2).get_center()
			var p := _room_post(b, Vector3(c.x, float(r.y) + 0.1, c.y))
			if p.is_finite() and not garrison.slice(mine).any(func(q: Vector3) -> bool: return q.distance_to(place.call(p)) < 1.5):
				garrison.append(place.call(p))
				face.append(Vector3.ZERO)
		for l: Dictionary in b.loot:
			var t: String = l.table
			var where: Vector3 = place.call(l.at)
			if t in ["armoury", "objective"]:
				points.objective.append(where)
			elif t == "cache":
				points.cache.append(where)
			elif t == "intel":
				points.intel.append(where)
			if tables.has(t) and loot.size() < LANDMARK_LOOT_MAX:
				var choices: Array = tables[t]
				var pick: Array = choices[rng.randi() % choices.size()]
				loot.append({"uid": "lm%d" % loot.size(), "id": pick[0], "count": int(pick[1]), "pos": where + Vector3(0, 0.5, 0)})
		for p: Vector3 in ramp_faces(b):
			ramps.append(place.call(p))
	for post: Array in s.posts:
		garrison.append(post[0])
		face.append(post[1])
	for bt: Dictionary in s.buildings:  # still short: outside a front door, watching the approach
		var fd: Variant = front_door(bt.data)
		if garrison.size() >= 2 or fd == null:
			break
		for out: float in [2.0, 3.5]:
			var p := _rot((fd as Vector3) + Vector3(0, 0.1, out), int(bt.turn)) + (bt.origin as Vector3)
			if _clear_standing(s.boxes, p):
				garrison.append(p)
				face.append(_rot(Vector3(0, 0, 1), int(bt.turn)))
				break
	var centre := Vector3(0, 0.1, 0)
	if not (s.buildings as Array).is_empty():
		var first: Dictionary = s.buildings[0]
		var c: Vector2 = (first.data.size as Vector2)
		centre = (first.origin as Vector3) + _rot(Vector3(0, 0.1, -c.y * 0.1), int(first.turn))
	for key: String in points:
		if (points[key] as Array).is_empty():
			points[key].append(centre)
	# Its footprint: everything in it, and the open ground round it.
	var lo := Vector2(-SITE_MARGIN, -SITE_MARGIN)
	var hi := Vector2(SITE_MARGIN, SITE_MARGIN)
	var below := float(s.below)
	var top := 0.0
	for list: Array in [s.boxes, s.skin]:
		for bx: Array in list:
			var a: Vector3 = bx[0]
			var c: Vector3 = bx[1]
			lo = lo.min(Vector2(a.x, a.z))
			hi = hi.max(Vector2(c.x, c.z))
			below = maxf(below, -a.y)
			top = maxf(top, c.y)
	var extent := Vector2(maxf(-lo.x, hi.x), maxf(-lo.y, hi.y)) + Vector2(SITE_MARGIN, SITE_MARGIN)
	var half := extent
	for r: Rect2 in s.streets:
		half = half.max(Vector2(maxf(-r.position.x, r.end.x), maxf(-r.position.y, r.end.y)))
	half = Vector2(ceilf(half.x), ceilf(half.y))
	s.half = half
	s.extent = Vector2(ceilf(extent.x), ceilf(extent.y))
	if not s.has("pad"):
		s.pad = Rect2(-half, half * 2.0)
	s.below = below
	s.top = top
	s.garrison = garrison
	s.garrison_face = face
	s.points = points
	s.loot = loot
	s.ramps = ramps
	s.turn = 0


## Props' own damage on a ruined (or bombed-out) site: bites out of RUIN_PROPS of its props (their
## upper parts, where a blast or a shell would take them), and the scorch and rubble of it.
const RUIN_PROPS := {RUINED: 0.4, BOMBED: 0.75}


static func _ruin_props(s: Dictionary, rng: RandomNumberGenerator, level: int) -> void:
	var share: float = RUIN_PROPS[level]
	for prop: AABB in s.props:
		if rng.randf() >= share:
			continue
		var size := Vector3(minf(prop.size.x * rng.randf_range(0.3, 0.7), 4.0), prop.size.y * rng.randf_range(0.3, 0.6), minf(prop.size.z * rng.randf_range(0.3, 0.7), 4.0))
		var at := prop.position + Vector3(rng.randf() * (prop.size.x - size.x), prop.size.y - size.y, rng.randf() * (prop.size.z - size.z))
		var bite := AABB(at.snapped(Vector3.ONE * 0.1), size.snapped(Vector3.ONE * 0.1))
		s.boxes = _carve(s.boxes, bite)
		s.skin = _carve(s.skin, bite)
		# What fell: a low heap at its foot, beside it.
		var foot := Vector3(snappedf(at.x, 0.1), prop.position.y, snappedf(prop.end.z + 0.1, 0.1))
		(s.boxes as Array).append([foot, foot + Vector3(snappedf(maxf(size.x * 0.6, 0.6), 0.1), 0.4, 0.8), VoxelWorld.Mat.CONCRETE])


## A prop's boxes from `from` on in `s.boxes`, noted as one prop (for _ruin_props).
static func _prop(s: Dictionary, from: int) -> void:
	var box := AABB()
	for k in range(from, (s.boxes as Array).size()):
		var a: Vector3 = s.boxes[k][0]
		var c: Vector3 = s.boxes[k][1]
		box = AABB(a, c - a) if k == from else box.merge(AABB(a, c - a))
	if box.has_volume():
		(s.props as Array).append(box)


# --- A farm ---------------------------------------------------------------------------------------

## A farm: the farmhouse facing the track (+z), the barn across the yard facing it, one or two
## silos behind the barn, livestock pens with a field shelter and a trough, hay bales, a well.
static func _farm(s: Dictionary, rng: RandomNumberGenerator, seed: int, ruin: int) -> void:
	var M := VoxelWorld.Mat
	var hs: Vector2 = building("farmhouse", seed * 7 + 1).size
	var origin := Vector3(snappedf(-hs.x * 0.5 - 3.0, 0.1), 0, 0)
	_site_building(s, "farmhouse", seed * 7 + 1, origin, 0, ruin)
	var barn := building("barn", seed * 7 + 2, "", ruin)
	var bs: Vector2 = barn.size
	var barn_at := Vector3(snappedf(bs.y * 0.5 + 6.0, 0.1), 0, snappedf(-bs.x * 0.5 + 2.0, 0.1))
	_site_building(s, "barn", seed * 7 + 2, barn_at, 3, ruin)  # its doors toward the yard (-x)
	# Silos behind the barn.
	var sx := barn_at.x + bs.y * 0.5 + 3.4
	for k in rng.randi_range(1, 2):
		var from := (s.boxes as Array).size()
		var c := Vector3(sx, 0, barn_at.z - bs.x * 0.5 + 2.4 + k * 5.0)
		_tank(s.boxes, c, 2.2, snappedf(rng.randf_range(8.0, 10.0), 0.1), [M.SHEET_METAL, M.CONCRETE, M.FIBRE_CEMENT][rng.randi() % 3], M.SHEET_RUST, "w")
		_prop(s, from)
	# Pens: a fenced paddock south-east of the yard, its gate to the west, a shelter and a trough.
	var pen := Rect2(snappedf(barn_at.x - bs.y * 0.5, 0.1), snappedf(barn_at.z + bs.x * 0.5 + 3.0, 0.1), snappedf(rng.randf_range(12.0, 16.0), 0.1), snappedf(rng.randf_range(8.0, 11.0), 0.1))
	var from_pen := (s.boxes as Array).size()
	_fence(s.boxes, pen, "w", M.WOOD)
	(s.boxes as Array).append([Vector3(pen.end.x - 3.2, 0, pen.position.y + 0.3), Vector3(pen.end.x - 0.3, 0.6, pen.position.y + 0.9), M.WOOD_DARK])  # trough
	for p: Vector2 in [Vector2(pen.end.x - 3.4, pen.end.y - 3.2), Vector2(pen.end.x - 0.4, pen.end.y - 3.2), Vector2(pen.end.x - 3.4, pen.end.y - 0.4), Vector2(pen.end.x - 0.4, pen.end.y - 0.4)]:
		(s.boxes as Array).append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.15, 2.2, p.y + 0.15), M.WOOD])
	(s.boxes as Array).append([Vector3(pen.end.x - 3.5, 2.2, pen.end.y - 3.3), Vector3(pen.end.x - 0.2, 2.3, pen.end.y - 0.2), M.CORRUGATED_IRON])  # field shelter
	_prop(s, from_pen)
	# Hay bales by the barn (at the end of its front away from its doors), a well in the yard.
	var door_z := barn_at.z
	for dr: Dictionary in barn.doors:
		if int(dr.rooms[1]) == -1 and (dr.at as Vector3).z > 0.0:
			door_z = (_rot(dr.at, 3) + barn_at).z
	var north := door_z > barn_at.z
	var hay := Vector3(barn_at.x - bs.y * 0.5 - 0.5, 0, (barn_at.z - bs.x * 0.5 + 0.4) if north else (barn_at.z + bs.x * 0.5 - 2.0))
	for k in 3:
		(s.boxes as Array).append([hay + Vector3(-1.2 - k * 1.3, 0, 0), hay + Vector3(-0.1 - k * 1.3, 0.8, 1.6), M.THATCH])
	(s.boxes as Array).append([hay + Vector3(-2.4, 0.8, 0), hay + Vector3(-1.3, 1.6, 1.6), M.THATCH])
	var well := Vector3(snappedf(origin.x + hs.x * 0.5 + 4.0, 0.1), 0, snappedf(hs.y * 0.5 + 3.0, 0.1))
	_octagon(s.boxes, well, 0.8, 0.0, 0.8, M.STONE)
	(s.boxes as Array).append([well + Vector3(-0.9, 0, -0.05), well + Vector3(-0.8, 2.0, 0.05), M.WOOD])
	(s.boxes as Array).append([well + Vector3(0.8, 0, -0.05), well + Vector3(0.9, 2.0, 0.05), M.WOOD])
	(s.boxes as Array).append([well + Vector3(-0.9, 1.9, -0.05), well + Vector3(0.9, 2.0, 0.05), M.WOOD])
	# The yard: trodden earth between house, barn and pens.
	(s.streets as Array).append(Rect2(origin.x + hs.x * 0.5, -6.0, barn_at.x - bs.y * 0.5 - (origin.x + hs.x * 0.5), 14.0))
	(s.posts as Array).append([Vector3(origin.x + hs.x * 0.5 + 2.0, 0.1, -2.0), Vector3.ZERO])


## A post-and-rail fence round `r` (two rails, posts every 2 m) with a gate gap (2.4 m) in the
## middle of side `gate` ("n", "s", "w", "e").
static func _fence(out: Array, r: Rect2, gate: String, mat: int) -> void:
	var sides := {"n": [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)], "s": [Vector2(r.position.x, r.end.y - 0.1), Vector2(r.end.x, r.end.y - 0.1)],
		"w": [Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)], "e": [Vector2(r.end.x - 0.1, r.position.y), Vector2(r.end.x - 0.1, r.end.y)]}
	for side: String in sides:
		var a: Vector2 = sides[side][0]
		var b: Vector2 = sides[side][1]
		var along_x := side in ["n", "s"]
		var from := a.x if along_x else a.y
		var to := b.x if along_x else b.y
		var runs: Array = [Vector2(from, to)]
		if side == gate:
			var mid := (from + to) * 0.5
			runs = [Vector2(from, mid - 1.2), Vector2(mid + 1.2, to)]
		for run: Vector2 in runs:
			var p := run.x
			while p <= run.y - 0.1:
				var q := Vector3(p, 0, a.y) if along_x else Vector3(a.x, 0, p)
				out.append([q, q + Vector3(0.15, 1.3, 0.15), mat])
				p += 2.0
			for y: float in [0.5, 1.1]:
				if along_x:
					out.append([Vector3(run.x, y, a.y), Vector3(run.y, y + 0.1, a.y + 0.1), mat])
				else:
					out.append([Vector3(a.x, y, run.x), Vector3(a.x + 0.1, y + 0.1, run.y), mat])


# --- A fuel depot ------------------------------------------------------------------------------

## A fuel depot: storage tanks in a bunded yard, a pump house, a pipe rack from the tanks to a
## loading gantry with a tanker under it, a fence round it all with a gate (+z) and a guard booth.
static func _fuel_depot(s: Dictionary, rng: RandomNumberGenerator, seed: int, ruin: int) -> void:
	var M := VoxelWorld.Mat
	var n := rng.randi_range(3, 4)
	var r := snappedf(rng.randf_range(4.0, 5.0), 0.1)
	var gap := 2.0
	var bund := Rect2(-30.0, -24.0, n * (r * 2.0 + gap) + gap, r * 2.0 + gap * 2.0)
	var from := (s.boxes as Array).size()
	_low_wall(s.boxes, bund, 1.0, 0.3, M.CONCRETE, "s")
	_prop(s, from)
	for k in n:
		from = (s.boxes as Array).size()
		var c := Vector3(bund.position.x + gap + r + k * (r * 2.0 + gap), 0, bund.position.y + gap + r)
		_tank(s.boxes, c, r, snappedf(rng.randf_range(6.0, 8.0), 0.1), [M.TRIM_WHITE, M.STEEL, M.SHEET_GREEN][k % 3], M.SIGN_RED, "s")
		_prop(s, from)
	var pump := Vector3(bund.end.x + 8.0, 0, -18.0)
	_site_building(s, "pumphouse", seed * 7 + 3, pump, 0, ruin)
	# The pipe rack: posts and pipes overhead (walk under it), tanks to the gantry.
	from = (s.boxes as Array).size()
	var rack_z := bund.end.y + 2.0
	var x := bund.position.x + 2.0
	var gantry := Vector3(bund.end.x + 4.0, 0, 8.0)
	while x <= gantry.x:
		(s.boxes as Array).append([Vector3(x, 0, rack_z), Vector3(x + 0.2, 2.6, rack_z + 0.2), M.STEEL])
		x += 4.0
	(s.boxes as Array).append([Vector3(bund.position.x + 2.0, 2.6, rack_z - 0.2), Vector3(gantry.x + 0.2, 2.8, rack_z + 0.4), M.STEEL])
	(s.boxes as Array).append([Vector3(bund.position.x + 2.0, 2.8, rack_z - 0.1), Vector3(gantry.x + 0.2, 3.1, rack_z + 0.2), M.STEEL_OLIVE])
	(s.boxes as Array).append([Vector3(gantry.x, 2.6, rack_z), Vector3(gantry.x + 0.2, 2.8, gantry.z - 2.0), M.STEEL])
	_prop(s, from)
	# The loading gantry and a tanker under it.
	from = (s.boxes as Array).size()
	for p: Vector2 in [Vector2(gantry.x - 3.0, gantry.z - 2.0), Vector2(gantry.x + 3.0, gantry.z - 2.0), Vector2(gantry.x - 3.0, gantry.z + 2.0), Vector2(gantry.x + 3.0, gantry.z + 2.0)]:
		(s.boxes as Array).append([Vector3(p.x, 0, p.y), Vector3(p.x + 0.3, 5.0, p.y + 0.3), M.SIGN_YELLOW])
	(s.boxes as Array).append([Vector3(gantry.x - 3.0, 5.0, gantry.z - 2.0), Vector3(gantry.x + 3.3, 5.3, gantry.z + 2.3), M.STEEL])
	(s.boxes as Array).append([Vector3(gantry.x - 0.2, 3.8, gantry.z - 1.6), Vector3(gantry.x + 0.2, 5.0, gantry.z + 0.2), M.STEEL])  # the loading arm
	_prop(s, from)
	from = (s.boxes as Array).size()
	_tanker(s.boxes, Vector3(gantry.x + 0.15, 0, gantry.z + 0.15), M.TRIM_WHITE)
	_prop(s, from)
	# The fence and the gate, a booth inside it.
	var yard := Rect2(bund.position.x - 4.0, bund.position.y - 4.0, gantry.x + 8.0 - (bund.position.x - 4.0), gantry.z + 10.0 - (bund.position.y - 4.0))
	_mesh_fence(s.boxes, yard, 6.0)
	var booth := Vector3(snappedf(yard.get_center().x + 5.0, 0.1), 0, yard.end.y - 3.4)
	_booth(s.boxes, booth)
	(s.posts as Array).append([booth + Vector3(-2.0, 0.1, 0.6), Vector3(0, 0, 1)])
	(s.posts as Array).append([Vector3(gantry.x - 4.5, 0.1, gantry.z), Vector3(0, 0, 1)])
	(s.streets as Array).append(Rect2(yard.position.x + 1.0, rack_z + 1.0, yard.size.x - 2.0, yard.end.y - rack_z - 1.0))


## A low wall round `r`, `h` high and `t` thick, a way through (1.4 m) in the middle of side `gap`.
static func _low_wall(out: Array, r: Rect2, h: float, t: float, mat: int, gap: String) -> void:
	var mid_x := snappedf(r.get_center().x, 0.1)
	if gap == "n":
		out.append([Vector3(r.position.x, 0, r.position.y), Vector3(mid_x - 0.7, h, r.position.y + t), mat])
		out.append([Vector3(mid_x + 0.7, 0, r.position.y), Vector3(r.end.x, h, r.position.y + t), mat])
	else:
		out.append([Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, h, r.position.y + t), mat])
	if gap == "s":
		out.append([Vector3(r.position.x, 0, r.end.y - t), Vector3(mid_x - 0.7, h, r.end.y), mat])
		out.append([Vector3(mid_x + 0.7, 0, r.end.y - t), Vector3(r.end.x, h, r.end.y), mat])
	else:
		out.append([Vector3(r.position.x, 0, r.end.y - t), Vector3(r.end.x, h, r.end.y), mat])
	out.append([Vector3(r.position.x, 0, r.position.y + t), Vector3(r.position.x + t, h, r.end.y - t), mat])
	out.append([Vector3(r.end.x - t, 0, r.position.y + t), Vector3(r.end.x, h, r.end.y - t), mat])


## A security fence round `r`: a low concrete kerb, steel posts every 3 m, two rails (the mesh
## between, which shows nothing to a voxel, left out: you can see and shoot through it), a gate
## `gate_w` wide in the middle of its +z side.
static func _mesh_fence(out: Array, r: Rect2, gate_w: float) -> void:
	var M := VoxelWorld.Mat
	var mid := snappedf(r.get_center().x, 0.1)
	var runs := [[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)],
		[Vector2(r.position.x, r.end.y - 0.2), Vector2(mid - gate_w * 0.5, r.end.y - 0.2)], [Vector2(mid + gate_w * 0.5, r.end.y - 0.2), Vector2(r.end.x, r.end.y - 0.2)],
		[Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)], [Vector2(r.end.x - 0.2, r.position.y), Vector2(r.end.x - 0.2, r.end.y)]]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var along_x := absf(b.x - a.x) > absf(b.y - a.y)
		out.append([Vector3(a.x, 0, a.y), Vector3(b.x + (0.0 if along_x else 0.2), 0.2, b.y + (0.2 if along_x else 0.0)), M.CONCRETE])
		var p := a.x if along_x else a.y
		var end := b.x if along_x else b.y
		while p <= end - 0.1:
			var q := Vector3(p, 0, a.y) if along_x else Vector3(a.x, 0, p)
			out.append([q, q + Vector3(0.1, 2.3, 0.1), M.STEEL])
			p += 3.0
		for y: float in [1.1, 2.2]:
			out.append([Vector3(a.x, y, a.y), Vector3(b.x + (0.0 if along_x else 0.1), y + 0.1, b.y + (0.1 if along_x else 0.0)), M.STEEL])


## A guard booth (2.2 m square, sheet metal) at `at` (its middle): a door on its -x side, windows
## all round.
static func _booth(out: Array, at: Vector3) -> void:
	var M := VoxelWorld.Mat
	var a := Vector2(at.x - 1.1, at.z - 1.1)
	var b := Vector2(at.x + 1.1, at.z + 1.1)
	_wall(out, 0, a.y, a.y + 0.1, a.x, b.x, 2.4, M.SHEET_METAL, [[at.x - 0.5, at.x + 0.5, 1.0, 1.7]])
	_wall(out, 0, b.y - 0.1, b.y, a.x, b.x, 2.4, M.SHEET_METAL, [[at.x - 0.5, at.x + 0.5, 1.0, 1.7]])
	_wall(out, 1, a.x, a.x + 0.1, a.y + 0.1, b.y - 0.1, 2.4, M.SHEET_METAL, [[at.z - 0.55, at.z + 0.55, 0.0, 2.1]])
	_wall(out, 1, b.x - 0.1, b.x, a.y + 0.1, b.y - 0.1, 2.4, M.SHEET_METAL, [[at.z - 0.5, at.z + 0.5, 1.0, 1.7]])
	out.append([Vector3(a.x - 0.2, 2.4, a.y - 0.2), Vector3(b.x + 0.2, 2.5, b.y + 0.2), M.SHEET_METAL])


## A fuel tanker (a cab and a barrel on a chassis), its middle at `at`, along z (cab to +z).
static func _tanker(out: Array, at: Vector3, mat: int) -> void:
	var M := VoxelWorld.Mat
	out.append([at + Vector3(-1.1, 0.4, -4.5), at + Vector3(1.1, 0.8, 4.5), M.TRIM_DARK])  # chassis
	for z: float in [-3.6, -2.4, 3.0]:
		for x: float in [-1.25, 0.95]:
			out.append([at + Vector3(x, 0, z), at + Vector3(x + 0.3, 0.9, z + 0.9), M.TRIM_DARK])
	out.append([at + Vector3(-1.2, 0.8, 2.6), at + Vector3(1.2, 2.9, 4.6), mat])  # cab
	out.append([at + Vector3(-1.1, 2.0, 4.5), at + Vector3(1.1, 2.6, 4.7), M.GLASS])
	var barrel: Array = []
	_barrel(barrel, Vector3(0, 0, 0), 1.1, 6.6, M.STEEL)
	for bx: Array in barrel:  # (its axis turned to z)
		var a: Vector3 = bx[0]
		var c: Vector3 = bx[1]
		out.append([at + Vector3(a.z, a.y + 2.0, a.x - 1.0), at + Vector3(c.z, c.y + 2.0, c.x - 1.0), bx[2]])


# --- A harbour -------------------------------------------------------------------------------

## A harbour, its sea toward -z before it's turned: a quay along z = QUAY_Z (its concrete face
## down into the water, bollards along it), two piers out PIER_L on piles with a portal crane at
## the root of each, two sheds facing the quay, the harbourmaster's office behind, stacks of
## shipping containers, a fishing boat moored at a pier. The land stands QUAY_OVER_SEA over the
## sea (its pad, "pad_sea"); the piers stand out over whatever is past the quay's edge.
static func _harbour(s: Dictionary, rng: RandomNumberGenerator, seed: int, ruin: int) -> void:
	var M := VoxelWorld.Mat
	var boxes: Array = s.boxes
	s.pad_sea = QUAY_OVER_SEA
	s.below = 6.5
	var land := Rect2(-42.0, QUAY_Z, 84.0, 44.0)
	s.pad = Rect2(land.position.x, QUAY_Z + ZoneTerrain.PAD_MARGIN_M, land.size.x, land.size.y - ZoneTerrain.PAD_MARGIN_M)  # flat to the quay's edge
	var from := boxes.size()
	boxes.append([Vector3(land.position.x, -2.4, QUAY_Z - 0.4), Vector3(land.end.x, 0.0, QUAY_Z), M.CONCRETE])  # the quay's face
	var x := land.position.x + 1.0
	while x < land.end.x - 1.0:
		boxes.append([Vector3(x, 0, QUAY_Z + 0.2), Vector3(x + 0.4, 0.6, QUAY_Z + 0.6), M.STEEL])  # bollards
		x += 6.0
	_prop(s, from)
	var piers: Array[Rect2] = [Rect2(-30.0, QUAY_Z - PIER_L, 7.0, PIER_L), Rect2(8.0, QUAY_Z - PIER_L, 10.0, PIER_L)]
	for p: Rect2 in piers:
		from = boxes.size()
		boxes.append([Vector3(p.position.x, -0.4, p.position.y), Vector3(p.end.x, 0.0, p.end.y), M.CONCRETE])
		var z := p.position.y + 0.5
		while z < p.end.y - 0.5:
			for px: float in [p.position.x + 0.3, p.end.x - 0.7]:
				boxes.append([Vector3(px, -6.0, z), Vector3(px + 0.4, -0.4, z + 0.4), M.CONCRETE])  # piles
			boxes.append([Vector3(p.position.x - 0.2, -1.6, z), Vector3(p.position.x, -0.2, z + 0.6), M.TRIM_DARK])  # fenders
			boxes.append([Vector3(p.end.x, -1.6, z), Vector3(p.end.x + 0.2, -0.2, z + 0.6), M.TRIM_DARK])
			z += 5.0
		z = p.position.y + 1.0
		while z < p.end.y - 2.0:
			boxes.append([Vector3(p.position.x + 0.2, 0, z), Vector3(p.position.x + 0.6, 0.6, z + 0.4), M.STEEL])
			boxes.append([Vector3(p.end.x - 0.6, 0, z), Vector3(p.end.x - 0.2, 0.6, z + 0.4), M.STEEL])
			z += 6.0
		_prop(s, from)
		from = boxes.size()
		_crane(boxes, Vector3(snappedf(p.get_center().x, 0.1), 0, QUAY_Z - 6.0), p.size.x, rng)
		_prop(s, from)
		(s.posts as Array).append([Vector3(p.get_center().x, 0.1, QUAY_Z - 2.0), Vector3(0, 0, -1)])
	# The sheds, their big doors onto the quay; the office behind the first.
	var shed_a := building("harbour_shed", seed * 7 + 4).size as Vector2
	var shed_b := building("harbour_shed", seed * 7 + 5).size as Vector2
	var front := QUAY_Z + 8.0
	_site_building(s, "harbour_shed", seed * 7 + 4, Vector3(-24.0, 0, front + shed_a.y * 0.5), 2, ruin)
	_site_building(s, "harbour_shed", seed * 7 + 5, Vector3(13.0, 0, front + shed_b.y * 0.5), 2, ruin)
	var office := building("office", seed * 7 + 6).size as Vector2
	_site_building(s, "office", seed * 7 + 6, Vector3(-28.0, 0, front + shed_a.y + 4.0 + office.y * 0.5), 2, ruin)
	# Containers: stacks behind the second shed, a way between each.
	var cz := front + shed_b.y + 4.0
	for k in 3:
		from = boxes.size()
		var at := Vector3(2.0 + k * 9.0 + 3.05, 0, cz + 1.2 + (k % 2) * 3.0)
		var mats := [M.SHEET_RUST, M.SHEET_GREEN, M.SIGN_BLUE, M.SIGN_RED, M.TRIM_WHITE]
		_container(boxes, at, true, mats[rng.randi() % mats.size()], 0)
		if rng.randf() < 0.65:
			_container(boxes, at + Vector3(0, 2.6, 0), true, mats[rng.randi() % mats.size()], 1)
		_prop(s, from)
	# A fishing boat moored along the first pier.
	from = boxes.size()
	_boat(boxes, Vector3(piers[0].position.x - 1.9, -QUAY_OVER_SEA, QUAY_Z - 18.0), [M.SIGN_BLUE, M.TRIM_WHITE, M.SIGN_RED][rng.randi() % 3])
	_prop(s, from)
	# Drums by the quay.
	for k in 3:
		boxes.append([Vector3(30.0 + k * 0.7, 0, QUAY_Z + 3.0), Vector3(30.6 + k * 0.7, 0.9, QUAY_Z + 3.6), M.STEEL])
	(s.streets as Array).append(Rect2(land.position.x, QUAY_Z, land.size.x, 8.0))
	(s.streets as Array).append(Rect2(-12.0, front, 10.0, land.end.y - front))


## A portal crane at `at` (on its pier, the pier `span` wide): legs straddling it, a machinery
## house and cab up on its portal, a boom reaching out to sea (-z) and a hook hanging from it.
static func _crane(out: Array, at: Vector3, span: float, rng: RandomNumberGenerator) -> void:
	var M := VoxelWorld.Mat
	var Y := M.SIGN_YELLOW
	var hx := span * 0.5 - 0.8
	for p: Vector2 in [Vector2(-hx, -2.5), Vector2(hx - 0.5, -2.5), Vector2(-hx, 2.0), Vector2(hx - 0.5, 2.0)]:
		out.append([at + Vector3(p.x, 0, p.y), at + Vector3(p.x + 0.5, 8.0, p.y + 0.5), Y])
	out.append([at + Vector3(-hx, 8.0, -2.5), at + Vector3(hx, 8.6, 2.5), Y])
	out.append([at + Vector3(-2.0, 8.6, -2.0), at + Vector3(2.0, 11.0, 2.5), Y])
	out.append([at + Vector3(-2.0, 11.0, -2.0), at + Vector3(2.0, 11.2, 2.5), M.TRIM_WHITE])
	out.append([at + Vector3(1.2, 8.6, -2.6), at + Vector3(2.2, 10.2, -2.0), M.GLASS])
	out.append([at + Vector3(-0.8, 9.6, 2.5), at + Vector3(0.8, 11.0, 4.5), M.CONCRETE])  # counterweight
	var y := 10.0
	var z := -2.0
	var segs := rng.randi_range(6, 8)
	for k in segs:
		out.append([at + Vector3(-0.3, y, z - 2.0), at + Vector3(0.3, y + 0.6, z), M.STEEL if k % 2 == 0 else Y])
		y += 0.8
		z -= 2.0
	out.append([at + Vector3(-0.05, y - 6.5, z), at + Vector3(0.05, y, z + 0.1), M.STEEL])
	out.append([at + Vector3(-0.25, y - 7.0, z - 0.15), at + Vector3(0.25, y - 6.5, z + 0.25), Y])


## A fishing boat, its waterline round `at` (y the sea), along z (bow to -z): a hull narrowing
## to the bow, a wheelhouse aft.
static func _boat(out: Array, at: Vector3, mat: int) -> void:
	var M := VoxelWorld.Mat
	out.append([at + Vector3(-1.4, -0.8, -3.0), at + Vector3(1.4, 1.0, 4.0), mat])
	out.append([at + Vector3(-1.0, -0.6, -4.4), at + Vector3(1.0, 1.0, -3.0), mat])
	out.append([at + Vector3(-0.5, -0.3, -5.4), at + Vector3(0.5, 1.0, -4.4), mat])
	out.append([at + Vector3(-1.4, 0.9, -5.4), at + Vector3(1.4, 1.0, 4.0), M.WOOD])
	out.append([at + Vector3(-1.0, 1.0, 1.4), at + Vector3(1.0, 3.0, 3.6), M.TRIM_WHITE])
	out.append([at + Vector3(-0.9, 2.2, 1.3), at + Vector3(0.9, 2.7, 1.4), M.GLASS])
	out.append([at + Vector3(-0.05, 3.0, 2.4), at + Vector3(0.05, 5.0, 2.5), M.STEEL])


# --- An airfield -------------------------------------------------------------------------------

## An airfield: a runway (RUNWAY, painted on the ground) along x, an apron and taxiway in front of
## two hangars, a control tower, a light aircraft parked on the apron, a windsock, fuel drums, a
## sandbagged guard post at the apron's end.
static func _airfield(s: Dictionary, rng: RandomNumberGenerator, seed: int, ruin: int) -> void:
	var M := VoxelWorld.Mat
	var boxes: Array = s.boxes
	var apron_z := -8.0
	(s.streets as Array).append(Rect2(-RUNWAY.x * 0.5, 10.0, RUNWAY.x, RUNWAY.y))
	(s.streets as Array).append(Rect2(-76.0, apron_z, 116.0, 18.0))
	var h1 := building("hangar", seed * 7 + 7).size as Vector2
	var h2 := building("hangar", seed * 7 + 8).size as Vector2
	var x1 := -66.0 + h1.x * 0.5
	var x2 := x1 + h1.x * 0.5 + 4.0 + h2.x * 0.5
	_site_building(s, "hangar", seed * 7 + 7, Vector3(x1, 0, apron_z - h1.y * 0.5), 0, ruin)
	_site_building(s, "hangar", seed * 7 + 8, Vector3(x2, 0, apron_z - h2.y * 0.5), 0, ruin)
	var tw := building("control_tower", seed * 7 + 9).size as Vector2
	var tx := x2 + h2.x * 0.5 + 8.0 + tw.x * 0.5
	_site_building(s, "control_tower", seed * 7 + 9, Vector3(tx, 0, apron_z - 2.0 - tw.y * 0.5), 0, ruin)
	var from := boxes.size()
	_plane(boxes, Vector3(snappedf(x2 + h2.x * 0.5 - 2.0, 0.1), 0, 1.0), [M.TRIM_WHITE, M.SIGN_YELLOW, M.STEEL_OLIVE][rng.randi() % 3])
	_prop(s, from)
	(s.posts as Array).append([Vector3(x2 + h2.x * 0.5 - 2.0, 0.1, 5.5), Vector3(0, 0, 1)])
	# The windsock by the runway, fuel drums by the tower.
	var sock := Vector3(snappedf(tx + 14.0, 0.1), 0, 6.0)
	boxes.append([sock, sock + Vector3(0.15, 6.0, 0.15), M.STEEL])
	for k in 3:
		(s.skin as Array).append([sock + Vector3(0.15 + k * 0.6, 5.3 - k * 0.1, -0.2 + k * 0.05), sock + Vector3(0.75 + k * 0.6, 5.9 - k * 0.2, 0.35 - k * 0.05),
			M.SIGN_RED if k % 2 == 0 else M.TRIM_WHITE])
	for k in 6:
		var at := Vector3(tx + tw.x * 0.5 + 2.0 + (k % 3) * 0.7, 0, apron_z - 3.0 + (k / 3) * 0.7)
		boxes.append([at, at + Vector3(0.6, 0.9, 0.6), M.STEEL if k % 2 == 0 else M.SIGN_RED])
	# A guard post at the apron's west end: sandbags on three sides.
	var g := Vector3(-72.0, 0, apron_z + 6.0)
	from = boxes.size()
	boxes.append([g + Vector3(-1.6, 0, -1.6), g + Vector3(1.6, 1.1, -1.1), M.SANDBAG])
	boxes.append([g + Vector3(-1.6, 0, -1.1), g + Vector3(-1.1, 1.1, 1.6), M.SANDBAG])
	boxes.append([g + Vector3(1.1, 0, -1.1), g + Vector3(1.6, 1.1, 1.6), M.SANDBAG])
	_prop(s, from)
	(s.posts as Array).append([g + Vector3(0, 0.1, 0.2), Vector3(-1, 0, 0)])


## A light aircraft (a high-winged single), its middle at `at` on the ground, nose to +x: a
## fuselage, cabin glass, a wing on struts, a tail, a propeller, its wheels.
static func _plane(out: Array, at: Vector3, mat: int) -> void:
	var M := VoxelWorld.Mat
	var parts := [
		[Vector3(-3.5, 0.6, -0.6), Vector3(3.5, 1.7, 0.6), mat], [Vector3(3.5, 0.8, -0.45), Vector3(4.1, 1.5, 0.45), mat],
		[Vector3(4.1, 0.3, -0.05), Vector3(4.2, 2.0, 0.05), M.TRIM_DARK], [Vector3(1.2, 1.7, -0.55), Vector3(2.8, 2.1, 0.55), M.GLASS],
		[Vector3(1.0, 2.1, -5.0), Vector3(2.4, 2.3, 5.0), mat], [Vector3(1.6, 1.1, -2.6), Vector3(1.7, 2.1, -2.5), M.STEEL],
		[Vector3(1.6, 1.1, 2.5), Vector3(1.7, 2.1, 2.6), M.STEEL], [Vector3(-3.5, 1.7, -0.1), Vector3(-2.6, 3.0, 0.1), mat],
		[Vector3(-3.6, 1.5, -1.8), Vector3(-2.8, 1.7, 1.8), mat], [Vector3(2.2, 0, -1.1), Vector3(2.6, 0.5, -0.9), M.TRIM_DARK],
		[Vector3(2.2, 0, 0.9), Vector3(2.6, 0.5, 1.1), M.TRIM_DARK], [Vector3(2.3, 0.5, -1.0), Vector3(2.5, 0.7, 1.0), M.STEEL],
		[Vector3(-3.3, 0, -0.1), Vector3(-3.1, 0.6, 0.1), M.TRIM_DARK],
	]
	for p: Array in parts:
		out.append([at + (p[0] as Vector3), at + (p[1] as Vector3), p[2]])


# --- An oil field ------------------------------------------------------------------------------

## An oil field: pumpjacks on their gravel pads, flowlines along the ground to a separator, two
## storage tanks in a bund, a pump house and a site cabin, and a flare stack in the far corner.
static func _oil_field(s: Dictionary, rng: RandomNumberGenerator, seed: int, ruin: int) -> void:
	var M := VoxelWorld.Mat
	var boxes: Array = s.boxes
	_site_building(s, "pumphouse", seed * 7 + 10, Vector3(-30.0, 0, 18.0), 0, ruin)
	_site_building(s, "pumphouse", seed * 7 + 11, Vector3(-19.0, 0, 18.0), 0, ruin)
	var bund := Rect2(-36.0, -30.0, 22.0, 13.0)
	var from := boxes.size()
	_low_wall(boxes, bund, 1.0, 0.3, M.CONCRETE, "s")
	_prop(s, from)
	for k in 2:
		from = boxes.size()
		_tank(boxes, Vector3(bund.position.x + 5.5 + k * 11.0, 0, bund.get_center().y), 4.0, snappedf(rng.randf_range(5.0, 6.5), 0.1), [M.SHEET_GREEN, M.STEEL, M.TRIM_WHITE][rng.randi() % 3], M.SIGN_YELLOW, "s")
		_prop(s, from)
	# The separator on its saddles.
	var sep := Vector3(-4.0, 1.3, -22.0)
	from = boxes.size()
	_barrel(boxes, sep, 0.9, 5.0, M.STEEL_OLIVE)
	for sx: float in [-1.8, 1.4]:
		boxes.append([Vector3(sep.x + sx, 0, sep.z - 0.7), Vector3(sep.x + sx + 0.4, 0.6, sep.z + 0.7), M.CONCRETE])
	_prop(s, from)
	(s.posts as Array).append([sep + Vector3(0, -1.2, 2.2), Vector3(0, 0, 1)])
	# The flare stack, well away from the tanks.
	var flare := Vector3(36.0, 0, -28.0)
	from = boxes.size()
	for p: Vector2 in [Vector2(-1.2, -1.2), Vector2(1.0, -1.2), Vector2(-1.2, 1.0), Vector2(1.0, 1.0)]:
		boxes.append([flare + Vector3(p.x, 0, p.y), flare + Vector3(p.x + 0.2, 6.0, p.y + 0.2), M.STEEL])
	for y: float in [2.0, 4.0, 6.0]:
		boxes.append([flare + Vector3(-1.2, y, -1.2), flare + Vector3(1.2, y + 0.1, 1.2), M.STEEL])
	boxes.append([flare + Vector3(-0.2, 0, -0.2), flare + Vector3(0.2, 18.0, 0.2), M.STEEL])
	boxes.append([flare + Vector3(-0.4, 18.0, -0.4), flare + Vector3(0.4, 18.6, 0.4), M.TRIM_DARK])
	(s.skin as Array).append([flare + Vector3(-0.3, 18.6, -0.3), flare + Vector3(0.3, 19.6, 0.3), M.SIGN_YELLOW])  # the flame
	(s.skin as Array).append([flare + Vector3(-0.15, 19.6, -0.15), flare + Vector3(0.15, 20.4, 0.15), M.SIGN_RED])
	_prop(s, from)
	(s.posts as Array).append([flare + Vector3(-3.0, 0.1, 2.0), Vector3.ZERO])
	# Pumpjacks on a jittered grid, flowlines to the separator.
	var spots: Array[Vector2] = [Vector2(-2, 6), Vector2(12, -8), Vector2(22, 10), Vector2(8, 24), Vector2(30, -12), Vector2(-6, 30), Vector2(26, 28)]
	for k in range(spots.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t := spots[k]
		spots[k] = spots[j]
		spots[j] = t
	for k in rng.randi_range(4, 5):
		var p := spots[k] + Vector2(snappedf(rng.randf_range(-3.0, 3.0), 0.1), snappedf(rng.randf_range(-3.0, 3.0), 0.1))
		var along_x := rng.randf() < 0.5
		from = boxes.size()
		_pumpjack(boxes, Vector3(p.x, 0, p.y), along_x, [M.STEEL_OLIVE, M.SIGN_RED, M.SIGN_BLUE, M.SIGN_YELLOW][rng.randi() % 4])
		_prop(s, from)
		(s.streets as Array).append(Rect2(p.x - 4.0, p.y - 2.5, 8.0, 5.0) if along_x else Rect2(p.x - 2.5, p.y - 4.0, 5.0, 8.0))
		var head := Vector3(p.x + 3.1, 0, p.y) if along_x else Vector3(p.x, 0, p.y + 3.1)
		# The flowline: along the ground (low enough to step over), x then z.
		var corner := Vector3(sep.x + 2.6, 0, head.z)
		boxes.append([Vector3(minf(head.x, corner.x), 0, head.z - 0.1), Vector3(maxf(head.x, corner.x), 0.2, head.z + 0.1), M.STEEL])
		boxes.append([Vector3(corner.x - 0.1, 0, minf(corner.z, sep.z)), Vector3(corner.x + 0.1, 0.2, maxf(corner.z, sep.z)), M.STEEL])
	(s.streets as Array).append(Rect2(-40.0, 10.0, 80.0, 5.0))


## A pumpjack at `at` (its skid's middle), its beam along x (or z): a samson post, a walking beam
## with its horse head over the wellhead, cranks and counterweights, the motor.
static func _pumpjack(out: Array, at: Vector3, along_x: bool, mat: int) -> void:
	var M := VoxelWorld.Mat
	var put := func(a: Vector3, b: Vector3, m: int) -> void:
		if along_x:
			out.append([at + a, at + b, m])
		else:
			out.append([at + Vector3(a.z, a.y, a.x), at + Vector3(b.z, b.y, b.x), m])
	put.call(Vector3(-3.0, 0, -0.8), Vector3(3.0, 0.3, 0.8), M.CONCRETE)
	put.call(Vector3(-0.2, 0.3, -0.7), Vector3(0.2, 3.4, -0.5), M.STEEL)
	put.call(Vector3(-0.2, 0.3, 0.5), Vector3(0.2, 3.4, 0.7), M.STEEL)
	put.call(Vector3(-0.3, 3.4, -0.7), Vector3(0.3, 3.6, 0.7), M.STEEL)
	put.call(Vector3(-2.6, 3.6, -0.15), Vector3(2.6, 4.0, 0.15), mat)
	put.call(Vector3(2.6, 2.6, -0.25), Vector3(3.2, 4.2, 0.25), mat)
	put.call(Vector3(3.0, 0.9, -0.05), Vector3(3.1, 2.6, 0.05), M.STEEL)
	put.call(Vector3(2.8, 0.3, -0.3), Vector3(3.4, 0.9, 0.3), M.STEEL)
	put.call(Vector3(-2.2, 0.3, -0.5), Vector3(-1.2, 1.6, 0.5), M.STEEL_OLIVE)
	for side: float in [-1.0, 1.0]:
		var z0 := 0.6 if side > 0.0 else -0.75
		put.call(Vector3(-2.4, 0.9, z0), Vector3(-1.0, 2.4, z0 + 0.15), M.SIGN_RED)
		put.call(Vector3(-2.6, 0.6, z0 + side * 0.15 - (0.0 if side > 0.0 else 0.0)), Vector3(-1.6, 1.4, z0 + side * 0.15 + 0.15), M.TRIM_DARK)
		put.call(Vector3(-2.3, 2.4, z0), Vector3(-2.1, 3.6, z0 + 0.1), M.STEEL)
	put.call(Vector3(-2.9, 0.3, -0.4), Vector3(-2.3, 1.0, 0.4), M.TRIM_DARK)
