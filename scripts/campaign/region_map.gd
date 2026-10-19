class_name RegionMap
extends RefCounted
## The region map (docs/linked_zones.md LZ-2, call 4: "every zone linked to its 2-4 geographic
## neighbours"): every zone of data/contracts.json, and the base zone ("fob"), on one grid, each
## region a block of its own (coast to the west, inland to the east, meeting along their seam),
## the base in the middle of its region (inland: the FOB's). Zones link to the ones beside them on
## the grid (north, south, west, east: 2-4 each), and each link puts a crossing on both zones' edges,
## on the side facing the other (ZoneDef "crossings"), so walking out of one zone's east edge comes
## in at the next one's west edge. Made from the data, the same every time: links aren't written
## by hand.

const BASE := "fob"
const BASE_REGION := "inland"
const REGIONS: Array[String] = ["coast", "inland"]
## Sides, as ZoneDef's sea_side: 0 north (-z, grid y - 1), 1 south (+z), 2 west (-x), 3 east (+x).
const SIDE_STEP: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const SIDE_NAMES: Array[String] = ["north", "south", "west", "east"]
## A crossing slides along its edge this far either way to keep off a site's pad.
const SLIDES: Array[float] = [0.0, 120.0, -120.0, 240.0, -240.0, 360.0, -360.0]
## A crossing's radius (m): the point the squad stands in to cross (Extraction).
const RADIUS_M := 20.0

static var _layout := {}


## zone id -> its cell (Vector2i) on the region grid.
static func layout() -> Dictionary:
	if not _layout.is_empty():
		return _layout
	var x0 := 0
	for region: String in REGIONS:
		var ids: Array[String] = []
		for z: Dictionary in MissionRegistry.data().get("zones", []):
			if String(z.get("region", "")) == region:
				ids.append(String(z.zone_id))
		var with_base := region == BASE_REGION
		var n := ids.size() + (1 if with_base else 0)
		var cols := maxi(ceili(sqrt(float(n))), 1)
		var rows := ceili(float(n) / cols)
		var base_cell := Vector2i(cols / 2, rows / 2)
		var k := 0
		for y in rows:
			for x in cols:
				var cell := Vector2i(x0 + x, y)
				if with_base and Vector2i(x, y) == base_cell:
					_layout[BASE] = cell
				elif k < ids.size():
					_layout[ids[k]] = cell
					k += 1
		x0 += cols
	return _layout


## The zone at `cell`, or "".
static func zone_at(cell: Vector2i) -> String:
	for id: String in layout():
		if layout()[id] == cell:
			return id
	return ""


## The zones linked to `zone_id`: [{"to", "side"}] (side as SIDE_STEP), north, south, west, east.
static func links(zone_id: String) -> Array:
	var out: Array = []
	if not layout().has(zone_id):
		return out
	var at: Vector2i = layout()[zone_id]
	for side in 4:
		var other := zone_at(at + SIDE_STEP[side])
		if other != "":
			out.append({"to": other, "side": side})
	return out


## The side opposite `side` (the other zone's edge of the same link).
static func opposite(side: int) -> int:
	return [1, 0, 3, 2][side]


## A crossing's id in a zone: the zone it leads to.
static func crossing_id(to: String) -> String:
	return "to_" + to


## A zone's name for the map and the crossings ("FOB" for the base).
static func zone_name(zone_id: String) -> String:
	if zone_id == BASE:
		return "FOB"
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if String(z.zone_id) == zone_id:
			return String(z.get("name", zone_id))
	return zone_id


## The crossings of the zone `def` describes (normalized: size, modules, sea): one per link, at the
## middle of the side facing that neighbour, ZoneDef.EDGE_POINT_IN_M in (past the sea's reach on a
## coast), slid along the edge off any site's pad. [{"id", "to", "to_crossing", "name", "side",
## "pos": [x, z], "radius"}].
static func crossings(zone_id: String, def: Dictionary) -> Array:
	var out: Array = []
	var half := float(def.get("size_m", 1920.0)) * 0.5
	var pads: Array[Rect2] = []
	for m: Dictionary in def.get("modules", []):
		var h: Vector2 = ZoneModules.HALF.get(String(m.type), ZoneModules.HALF.get(ZoneModules.base(String(m.type)), Vector2(40, 40)))
		pads.append(Rect2(Vector2(float(m.pos[0]), float(m.pos[1])) - h, h * 2.0).grow(ZoneDef.EDGE_POINT_CLEAR_M))
	var sea := int(def.get("sea_side", -1))
	for link: Dictionary in links(zone_id):
		var side := int(link.side)
		var inset := half - (maxf(ZoneDef.EDGE_POINT_IN_M, float(def.get("sea_m", 0.0)) + ZoneDef.SEA_PAD_KEEP_M) if side == sea else ZoneDef.EDGE_POINT_IN_M)
		var keep := half - ZoneDef.EDGE_KEEP_M
		var pos := Vector2.ZERO
		for slide: float in SLIDES:
			var a := clampf(slide, -keep, keep)
			pos = [Vector2(a, -inset), Vector2(a, inset), Vector2(-inset, a), Vector2(inset, a)][side]
			if not pads.any(func(r: Rect2) -> bool: return r.has_point(pos)):
				break
		var to := String(link.to)
		out.append({"id": crossing_id(to), "to": to, "to_crossing": crossing_id(zone_id), "name": "To %s" % zone_name(to),
			"side": side, "pos": [snappedf(pos.x, 1.0), snappedf(pos.y, 1.0)], "radius": RADIUS_M})
	return out


## The crossing `id` of `def`, or {}.
static func crossing_of(def: Dictionary, id: String) -> Dictionary:
	for c: Dictionary in def.get("crossings", []):
		if String(c.id) == id:
			return c
	return {}
