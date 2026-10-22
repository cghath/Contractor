class_name ZoneProps
extends RefCounted
## Lays the prop library (PropArt; cghath's queue item 1.7) out on a zone for ZoneScatter, before
## its rocks and trees (which then keep off the props: blocks). Deterministic from the zone's seed,
## its preset's style (data/props.json) and its modules and roads, so every peer lays the same; the
## items go into ZoneScatter's layout and its caches like everything else.
##
## Where things go (Captain, 2026-10-21: "true expansion of terrains and props/buildings"):
## - towns: lamps and poles with wires along the streets, market stalls by the crossroads, parked
##   cars, benches, bins, a kiosk, bollards, stop and direction signs, a bus shelter, all on the
##   street and clear of the buildings, posts, loot and civilians' walks (_town);
## - round settlements and sites: washing lines, dishes and generators by the villages; shipping
##   containers, generators, fuel tanks, latrines and barriers outside the HQ, QRF bases, outposts
##   and compounds; barriers and signs at checkpoints (_site, data "sites");
## - along the roads (street_lines: one function, for the roads work to repoint at its road edges):
##   utility poles with wires, direction signs, a bus shelter and a billboard by a town, parked and
##   burnt-out vehicles (_roadside);
## - the countryside: pylon lines across the zone (_power_lines), farmsteads with a pen of goats or
##   sheep, water, hay, a shelter, field fences and gates, irrigation (_farm), a walled cemetery by
##   the biggest settlement (_cemetery).
## Animals are ANIMAL markers (ZoneScatter.Kind.ANIMAL: a home area and how many): ZoneAnimals
## spawns and walks them.

const DATA_PATH := "res://data/props.json"
## Most library items in a zone. Proposed.
const CAP := 7000
## The occupancy grid's cell (m), and the gap kept between props' footprints (m).
const OCC_M := 8.0
const GAP_M := 0.25
## Shapes laid in runs (fences, walls, gates, channels): their sections meet end to end.
const RUNS: Array[String] = ["fence_rail", "fence_board", "fence_chainlink", "fence_barbed", "fence_corrugated", "wall_stone", "wall_block",
	"wall_mud", "gate_farm", "gate_steel", "gate_wood", "irrigation_channel"]
## A road's half width (ZoneRoads.WIDTH_M), and how far a roadside prop keeps from its edge (m).
const ROAD_HALF_M := 2.5
const ROAD_CLEAR_M := 1.0
## Everything keeps this far inside the zone's edge (as ZoneScatter.EDGE_KEEP_M).
const EDGE_KEEP_M := 12.0
## A prop stands on the lowest ground under it; the highest may be at most this much above it (m)
## unless its shape says more (DROP).
const DROP_M := 0.35
const DROP := {"pylon": 1.4, "power_pole_h": 0.8, "utility_pole": 0.8, "pole_transformer": 0.8, "street_lamp": 0.6,
	"fence_rail": 0.5, "fence_barbed": 0.6, "fence_board": 0.45, "wall_stone": 0.5, "wall_mud": 0.45, "fence_chainlink": 0.45,
	"hay_round": 0.45, "windpump": 0.8, "water_tower": 0.6, "sign_direction": 0.5, "sign_warn": 0.5, "sign_stop": 0.5}
## Utility poles along a road: every POLE_STEP_M, POLE_OFF_M off its middle line. Pylons every
## PYLON_STEP_M along a line, shifted up to PYLON_SHIFT_M sideways to find a footing. Proposed.
const POLE_STEP_M := 38.0
const POLE_OFF_M := 6.0
const PYLON_STEP_M := 95.0
const PYLON_SHIFT_M := [0.0, 12.0, -12.0, 26.0, -26.0, 42.0, -42.0]
## Wires link a pole to the one before it when they're at most this many steps apart.
const LINK_STEPS := 1.7
## Clutter round a site goes this far out from its pad's edge (m) [min, max]; it keeps this far
## from a road's middle line, and every prop this far from an insertion or extraction pad.
const SITE_RING_M := [1.5, 16.0]
const SITE_ROAD_M := 5.0
const LANDING_KEEP_M := 10.0
## Farmsteads: this far from any pad, and from each other; their pen [min, max] (m).
const FARM_PAD_M := 60.0
const FARM_GAP_M := 110.0
const PEN_W := [12.0, 21.0]
const PEN_D := [9.0, 15.0]
const FIELD_FENCE_M := [40.0, 120.0]
const FIELD_GATE_EVERY := 15
const IRRIGATION_M := [30.0, 90.0]
## Cemeteries: inside a wall (W, D) [min, max], graves on a grid, this share of the plots used.
const CEMETERY_W := [18.0, 27.0]
const CEMETERY_D := [12.0, 18.0]
const GRAVE_STEP := Vector2(2.7, 1.5)
const GRAVE_FILL := 0.75
## Town street layout (BuildingGen's: the main street along x, the cross street along z).
const KERB_IN_M := 0.35

static var _data := {}

var scatter: ZoneScatter
var terrain: ZoneTerrain
var def: Dictionary
var style_id := "temperate"
var style := {}
var rng := RandomNumberGenerator.new()
## What it laid, for tests: {group: count} and the farms, cemeteries, pylon lines and towns.
var report := {"farms": 0, "cemeteries": 0, "pylons": 0, "poles": 0, "towns": 0, "town_props": 0, "sites": 0, "roadside": 0, "animals": 0}
var placed := 0
## Why props didn't fit where tried: {shape: {"edge" | "taken" | "road" | "pad" | "street" | "ground": count}}.
var rejected := {}
var _half := 0.0
var _occ := {}  # Vector2i -> Array of footprints [centre (Vector2), yaw, half (Vector2)]
var _near_cells := {}  # Vector2i -> true: cells with a footprint in them or next to them (blocks' quick look)
var _modules: Array = []  # {"type", "base", "centre" (Vector2), "y", "half" (Vector2), "pad" (Rect2)}
var _pads: Array = []  # [Rect2, margin] every pad, with how far props keep from it
var _lines: Array = []  # street_lines()
var _allow: Variant = null  # the town pad a street prop may stand on (Rect2), or null
var _farms: Array[Vector2] = []
var _open := false  # the preset has an open middle (ZoneScatter._open_weight: a salt pan)


static func _load() -> void:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"styles": {"temperate": {}}, "default_style": "temperate"}


## The style (data/props.json "styles") for terrain preset `preset_id`.
static func style_for(preset_id: String) -> String:
	_load()
	var map: Dictionary = _data.get("preset_styles", {})
	if map.has(preset_id):
		return String(map[preset_id])
	if preset_id.begins_with(TerrainPresets.MIX):
		var first := String(TerrainPresets.get_preset(preset_id).get("name", "")).get_slice(" / ", 0)
		for id: String in map:
			if String(TerrainPresets.get_preset(id).get("name", "")) == first:
				return String(map[id])
	return String(_data.get("default_style", "temperate"))


## Lays the library out on `t` (generated) for zone `d`, adding to `s`'s items.
func lay_out(s: ZoneScatter, t: ZoneTerrain, d: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	_load()
	scatter = s
	terrain = t
	def = d
	_half = t.size_m * 0.5
	rng.seed = t.seed_value ^ 0x9A0B5
	style_id = style_for(t.preset_id)
	style = (_data.styles as Dictionary).get(style_id, (_data.styles as Dictionary).values()[0])
	var mods: Array = d.get("modules", [])
	for i in t.pads.size():
		var rect: Rect2 = t.pads[i][0]
		_pads.append([rect, 0.5 if i < mods.size() else LANDING_KEEP_M])
	for i in mods.size():
		var m: Dictionary = mods[i]
		var type := String(m.type)
		ZoneModules.has_type(type)
		var half: Vector2 = ZoneModules.HALF.get(type, Vector2(20, 20))
		var c := Vector2(float(m.pos[0]), float(m.pos[1]))
		_modules.append({"type": type, "base": ZoneModules.base(type), "centre": c, "half": half,
			"pad": t.pads[i][0] if i < t.pads.size() else Rect2(c - half, half * 2.0).grow(ZoneTerrain.PAD_MARGIN_M),
			"y": t.height_at(c.x, c.y)})
	_lines = street_lines()
	_open = float(s._spec.get("margin_m", 0.0)) > 0.0
	for m: Dictionary in _modules:
		if m.base == "town":
			_town(m)
	for m: Dictionary in _modules:
		_site(m)
	_roadside()
	_power_lines()
	_cemetery()
	var area_km2 := t.size_m * t.size_m / 1.0e6
	for n in _how_many(float(style.get("farms_per_km2", 0.0)) * area_km2):
		_farm()
	report["placed"] = placed
	report["rejected"] = rejected
	report["ms"] = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)


## The zone's roads as street lines: {"a", "b" (Vector2, ends of the middle line), "half_w" (its
## half width, m)}. Today's roads are the def's straight "roads" segments, ZoneRoads.WIDTH_M wide;
## the roads work (zone_roads.gd) will expose their edges and pavements: point this at them and
## every roadside prop follows.
func street_lines() -> Array:
	var out: Array = []
	for road: Array in def.get("roads", []):
		out.append({"a": Vector2(float(road[0][0]), float(road[0][1])), "b": Vector2(float(road[1][0]), float(road[1][1])), "half_w": ROAD_HALF_M})
	return out


# --- Placing -----------------------------------------------------------------------------------

## Places shape `shape` at (x, z) turned `yaw` if it fits: inside the zone, dry, off every pad (but
## the town pad `_allow` for street props) and road ("road_m" from a road's middle, default its
## edge plus ROAD_CLEAR_M), on ground no rougher than its DROP, clear of other props. Options:
## "paint" (else picked), "road_m", "link" (wires to the item before it), "town" (a town's local
## check: a Callable(footprint) -> bool), "count" (an ANIMAL marker's), "free" (skip the occupancy
## check). Returns whether it did.
func put(shape: String, x: float, z: float, yaw: float, opts := {}) -> bool:
	if placed >= CAP:
		return false
	_shape_now = shape
	var paint := int(opts.get("paint", -1))
	var colours := PropArt.paints(shape)
	if paint < 0:
		paint = rng.randi() % maxi(colours.size(), 1)
	var tint := rng.randf_range(0.86, 1.0)
	var foot := _footprint(shape, x, z, yaw)
	if not _fits(shape, foot, opts):
		return false
	var y := _ground_under(foot)
	if y == INF:
		return _reject(shape, "ground")
	var item := {"kind": ZoneScatter.Kind.PROP, "shape": shape, "paint": paint, "pos": Vector3(x, y, z), "yaw": yaw,
		"size": Vector3.ONE, "colour": Color(tint, tint, tint), "solid": true, "link": 1 if bool(opts.get("link", false)) else 0}
	scatter._add(item)
	_mark(foot)
	placed += 1
	return true


## How far shape `shape` reaches back (its -z) from its origin on the ground: set against a kerb.
static func _back(shape: String) -> float:
	return maxf(-PropArt.foot(shape).position.z, 0.0)


## An ANIMAL marker: `count` of `species` living in the rectangle centred on (x, z), `half` (x,
## z) about it, turned `yaw` (a pen's inside, or round a farm or a village).
func animals(species: String, x: float, z: float, half: Vector2, yaw: float, count: int) -> void:
	if count <= 0 or (_open and scatter._open_weight(x, z) <= 0.0):
		return
	scatter._add({"kind": ZoneScatter.Kind.ANIMAL, "shape": species, "paint": count, "pos": Vector3(x, terrain.height_at(x, z), z), "yaw": yaw,
		"size": Vector3(half.x, 0.0, half.y), "colour": Color.WHITE, "solid": false, "link": 0})
	report.animals += count


## Whether a circle of radius `r` at (x, z) touches a prop's footprint (rocks, trees and bushes keep
## off them).
func blocks(x: float, z: float, r: float) -> bool:
	var g := Vector2i(floori(x / OCC_M), floori(z / OCC_M))
	if not _near_cells.has(g):
		return false  # (most of the zone: one look-up, no prop within a cell)
	var p := Vector2(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for f: Array in _occ.get(g + Vector2i(dx, dz), []):
				var local := (p - (f[0] as Vector2)).rotated(float(f[1]))
				var h: Vector2 = f[2]
				var q := Vector2(clampf(local.x, -h.x, h.x), clampf(local.y, -h.y, h.y))
				if q.distance_to(local) < r:
					return true
	return false


## A footprint: [centre (Vector2), yaw, half extents (Vector2, its own x and z), corners (world)]:
## what shape `shape` stands on the ground with (PropArt.foot), placed at (x, z) turned `yaw`, with
## half GAP_M round it; a run's section (RUNS) a little shorter, so a line's sections meet.
func _footprint(shape: String, x: float, z: float, yaw: float) -> Array:
	var b := PropArt.foot(shape)
	var run := shape in RUNS
	var h := Vector2(b.size.x, b.size.z) * 0.5 + (Vector2.ZERO if run else Vector2(GAP_M, GAP_M) * 0.5)
	if run:
		h.x -= 0.15
	var c := Vector2(x, z) + _to_world(Vector2(b.get_center().x, b.get_center().z), yaw)
	var corners: Array[Vector2] = []
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(c + _to_world(Vector2(s.x * h.x, s.y * h.y), yaw))
	return [c, yaw, h, corners]


## A prop's own (x, z) offset to the world's, turned `yaw` (Basis(Vector3.UP, yaw)).
static func _to_world(v: Vector2, yaw: float) -> Vector2:
	return Vector2(v.x * cos(yaw) + v.y * sin(yaw), -v.x * sin(yaw) + v.y * cos(yaw))


func _fits(shape: String, foot: Array, opts: Dictionary) -> bool:
	var corners: Array[Vector2] = foot[3]
	var inner := _half - EDGE_KEEP_M
	var samples: Array[Vector2] = corners.duplicate()
	samples.append(foot[0])
	# Along a long side too (fences, containers): a road or a pad between its corners.
	var h: Vector2 = foot[2]
	var long := maxf(h.x, h.y)
	if long > 1.5:
		var axis := _to_world(Vector2(1, 0) if h.x >= h.y else Vector2(0, 1), float(foot[1]))
		var k := -long + 1.0
		while k < long:
			samples.append((foot[0] as Vector2) + axis * k)
			k += 1.0
	for p in samples:
		if absf(p.x) > inner or absf(p.y) > inner:
			return _reject(shape, "edge")
		if _open and scatter._open_weight(p.x, p.y) <= 0.0:
			return _reject(shape, "open")  # (a salt pan's open middle stays bare, as for the rest of the scatter)
	if not bool(opts.get("free", false)) and _occupied(foot):
		return _reject(shape, "taken")
	var c: Vector2 = foot[0]
	var reach := h.length()
	var road_m := float(opts.get("road_m", -1.0))
	for line: Dictionary in _lines:
		var keep := road_m if road_m >= 0.0 else float(line.half_w) + ROAD_CLEAR_M
		if Geometry2D.get_closest_point_to_segment(c, line.a, line.b).distance_to(c) > keep + reach:
			continue
		for p in samples:
			if Geometry2D.get_closest_point_to_segment(p, line.a, line.b).distance_to(p) < keep:
				return _reject(shape, "road")
	for pad: Array in _pads:
		var r: Rect2 = pad[0]
		if _allow != null and r == _allow:
			continue
		if not r.grow(float(pad[1]) + reach).has_point(c):
			continue
		if _rect_hits(r.grow(float(pad[1])), foot):
			return _reject(shape, "pad")
	if opts.has("town") and not (opts.town as Callable).call(foot):
		return _reject(shape, "street")
	return true


## Counts why `shape` didn't fit (rejected: {shape: {reason: count}}, for tests and tuning); false.
func _reject(shape: String, why: String) -> bool:
	if not rejected.has(shape):
		rejected[shape] = {}
	rejected[shape][why] = int(rejected[shape].get(why, 0)) + 1
	return false


## Whether footprint `foot` overlaps rect `r` (two rectangles, one turned: separating axes).
func _rect_hits(r: Rect2, foot: Array) -> bool:
	return _overlap([r.get_center(), 0.0, r.size * 0.5], foot)


static func _overlap(a: Array, b: Array) -> bool:
	var axes: Array[Vector2] = []
	for f: Array in [a, b]:
		axes.append(_to_world(Vector2(1, 0), float(f[1])))
		axes.append(_to_world(Vector2(0, 1), float(f[1])))
	var d: Vector2 = (b[0] as Vector2) - (a[0] as Vector2)
	for axis in axes:
		var ra := _radius(a, axis)
		var rb := _radius(b, axis)
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


static func _radius(f: Array, axis: Vector2) -> float:
	var h: Vector2 = f[2]
	return absf(_to_world(Vector2(h.x, 0), float(f[1])).dot(axis)) + absf(_to_world(Vector2(0, h.y), float(f[1])).dot(axis))


func _occupied(foot: Array) -> bool:
	var c: Vector2 = foot[0]
	var reach := ceili((maxf((foot[2] as Vector2).x, (foot[2] as Vector2).y) + 7.0) / OCC_M)
	var g := Vector2i(floori(c.x / OCC_M), floori(c.y / OCC_M))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for f: Array in _occ.get(g + Vector2i(dx, dz), []):
				if _overlap(f, foot):
					return true
	return false


func _mark(foot: Array) -> void:
	# In every cell it covers (a pen's inside, a 40 ft container), so blocks finds it from any of them.
	var c: Vector2 = foot[0]
	var r := (foot[2] as Vector2).length()
	for gz in range(floori((c.y - r) / OCC_M), floori((c.y + r) / OCC_M) + 1):
		for gx in range(floori((c.x - r) / OCC_M), floori((c.x + r) / OCC_M) + 1):
			var g := Vector2i(gx, gz)
			if not _occ.has(g):
				_occ[g] = []
			(_occ[g] as Array).append(foot)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					_near_cells[g + Vector2i(dx, dz)] = true


## Keeps the rectangle centred on `c`, `half` (x, z) about it turned `yaw`, free of everything placed
## after (a pen's or a cemetery's inside: no tree, rock or prop grows there).
func _reserve(c: Vector2, yaw: float, half: Vector2) -> void:
	var corners: Array[Vector2] = []
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(c + _to_world(Vector2(s.x * half.x, s.y * half.y), yaw))
	_mark([c, yaw, half, corners])


## Whether `p` is on a module's pad (dry, flat land, whatever the sea's level: a harbour town).
func _on_module_pad(p: Vector2) -> bool:
	for pad: Array in _pads:
		if float(pad[1]) < LANDING_KEEP_M and (pad[0] as Rect2).has_point(p):
			return true
	return false


## The lowest ground under `foot` (its corners and middle), or INF where it's too rough (its DROP) or
## in the sea.
func _ground_under(foot: Array) -> float:
	var lo := INF
	var hi := -INF
	var points: Array[Vector2] = (foot[3] as Array[Vector2]).duplicate()
	points.append(foot[0])
	for p in points:
		var h := terrain.height_at(p.x, p.y)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35 and not _on_module_pad(p):
			return INF
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return lo if hi - lo <= _drop_of(foot) else INF


var _shape_now := ""


func _drop_of(_foot: Array) -> float:
	return float(DROP.get(_shape_now, DROP_M))


## put() with the shape remembered for its ground check.
func place(shape: String, x: float, z: float, yaw: float, opts := {}) -> bool:
	_shape_now = shape
	return put(shape, x, z, yaw, opts)


func _pick(weights: Variant) -> String:
	if weights is Array:
		return String((weights as Array)[rng.randi() % (weights as Array).size()]) if not (weights as Array).is_empty() else ""
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return String((weights as Dictionary).keys()[0])


func _how_many(v: float) -> int:
	return int(v + rng.randf())


## A line of `shape` from `a` to `b`, one every `step` (fence sections along their x, poles with
## their wires along their z, `poles`), each nudged up to `shift` sideways to fit; poles' wires
## link the ones in a row. Every `gate_every` th section (0: none) is `gate` instead. Returns
## how many it placed.
func line(shape: String, a: Vector2, b: Vector2, step: float, poles := false, gate := "", gate_every := 0, opts := {}, shift: Array = [0.0]) -> int:
	var length := a.distance_to(b)
	if length < step * 0.5:
		return 0
	var d := (b - a) / length
	var side := Vector2(-d.y, d.x)
	var yaw := atan2(d.x, d.y) if poles else atan2(-d.y, d.x)
	var n := maxi(int(length / step), 1)
	var last := -1
	var done := 0
	for k in n:
		var t := (k + 0.5) * length / n if not poles else k * length / maxf(n - 1, 1)
		var what := gate if gate != "" and gate_every > 0 and k % gate_every == gate_every / 2 else shape
		for off: float in shift:
			var p := a + d * t + side * off
			var o := opts.duplicate()
			o["link"] = poles and last >= 0 and k - last <= 1 and absf(off) < step * 0.5
			if place(what, p.x, p.y, yaw, o):
				last = k
				done += 1
				break
	return done


# --- Towns -------------------------------------------------------------------------------------

## A generated town's streets (BuildingGen.town: the main street along x, STREET_W wide; the
## cross street along z, CROSS_W wide): lamps, poles and wires, market stalls by the crossroads,
## parked cars, benches, bins, a kiosk, bollards and signs, all on the street, clear of every box
## the town is built of (walls, barricades), its garrison posts, loot, named points and the
## civilians' walks.
func _town(m: Dictionary) -> void:
	var type: String = m.type
	var o: Vector2 = m.centre
	var t_spec: Dictionary = _data.get("town", {})
	var street := BuildingGen.STREET_W * 0.5
	var cross := BuildingGen.CROSS_W * 0.5
	var span := BuildingGen.TOWN_HALF_X
	var half: Vector2 = m.half
	var blocked: Array = []  # town-local footprints of its boxes
	for box: AABB in ZoneModules.boxes_m(type):
		if box.position.y < 2.0 and box.size.x > 0.0 and box.size.z > 0.0:
			blocked.append([Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5), 0.0, Vector2(box.size.x, box.size.z) * 0.5 + Vector2(0.3, 0.3)])
	var spots: Array[Vector2] = []  # posts, loot, points, civilians' walks (town-local)
	for p: Vector3 in ZoneModules.GARRISON.get(type, []):
		spots.append(Vector2(p.x, p.z))
	for l: Dictionary in ZoneModules.LOOT.get(type, []):
		spots.append(Vector2((l.pos as Vector3).x, (l.pos as Vector3).z))
	for kind: String in ZoneModules.POINTS.get(type, {}):
		for p: Vector3 in ZoneModules.POINTS[type][kind]:
			spots.append(Vector2(p.x, p.z))
	for c: Dictionary in ZoneModules.civilians(type):
		for p: Array in c.get("routine", []):
			spots.append(Vector2(float(p[0]), float(p[2])))
	var grid := {}  # 4 m cells -> blocked footprints
	for f: Array in blocked:
		var c: Vector2 = f[0]
		var h: Vector2 = f[2]
		for gz in range(floori((c.y - h.y) / 4.0), floori((c.y + h.y) / 4.0) + 1):
			for gx in range(floori((c.x - h.x) / 4.0), floori((c.x + h.x) / 4.0) + 1):
				var g := Vector2i(gx, gz)
				if not grid.has(g):
					grid[g] = []
				(grid[g] as Array).append(f)
	var on_street := func(foot: Array) -> bool:
		var local := [(foot[0] as Vector2) - o, foot[1], foot[2]]
		var c: Vector2 = local[0]
		var r := maxf((foot[2] as Vector2).x, (foot[2] as Vector2).y) + 0.5
		if absf(c.x) > half.x - 1.0 or absf(c.y) > half.y - 1.0:
			return false
		for gz in range(floori((c.y - r) / 4.0), floori((c.y + r) / 4.0) + 1):
			for gx in range(floori((c.x - r) / 4.0), floori((c.x + r) / 4.0) + 1):
				for f: Array in grid.get(Vector2i(gx, gz), []):
					if _overlap(f, local):
						return false
		for s in spots:
			var q := (s - c).rotated(float(local[1]))
			var hh: Vector2 = local[2]
			if Vector2(clampf(q.x, -hh.x, hh.x), clampf(q.y, -hh.y, hh.y)).distance_to(q) < 1.3:
				return false
		return true
	_allow = m.pad
	var before := placed
	var opts := {"town": on_street, "road_m": 0.0}
	var at := func(x: float, z: float) -> Vector2: return o + Vector2(x, z)
	# Lamps along the main street, alternating kerbs, arms out over it; along the cross street too.
	var kerb := street - KERB_IN_M
	var step := float(t_spec.get("lamp_step_m", 16.0))
	var k := 0
	var x := -span + 3.0
	while x < span - 3.0:
		if absf(x) > cross + 1.5:
			var side := -1.0 if k % 2 == 0 else 1.0
			var p: Vector2 = at.call(x, side * kerb)
			place("street_lamp", p.x, p.y, 0.0 if side < 0.0 else PI, opts)
			k += 1
		x += step
	var z := street + 3.0
	while z < half.y - 3.0:
		for s: float in [-1.0, 1.0]:
			var p: Vector2 = at.call((cross - KERB_IN_M) * (1.0 if k % 2 == 0 else -1.0), s * z)
			place("lamp_double" if k % 3 == 0 else "street_lamp", p.x, p.y, -PI * 0.5 if k % 2 == 0 else PI * 0.5, opts)
			k += 1
		z += step
	# Poles and wires along the south kerb, between the lamps; a transformer on every third.
	for dir: float in [-1.0, 1.0]:
		var pole_step := float(t_spec.get("pole_step_m", 24.0))
		var px := cross + 6.0
		var prev := false
		var n := 0
		while px < span - 2.0:
			var p: Vector2 = at.call(dir * px, street - 0.25)
			prev = place("pole_transformer" if n % 3 == 1 else "utility_pole", p.x, p.y, PI * 0.5, opts.merged({"link": prev}, true))
			n += 1
			px += pole_step
	# Market stalls by the crossroads, facing the street.
	var stalls := rng.randi_range(int(t_spec.get("stalls", [4, 8])[0]), int(t_spec.get("stalls", [4, 8])[1]))
	var kinds: Dictionary = t_spec.get("stall_kinds", {"market_stall": 1})
	for n in stalls * 3:
		if stalls <= 0:
			break
		var shape := _pick(kinds)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var sx := (cross + 2.5 + rng.randf() * 22.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var p: Vector2 = at.call(sx, side * (street - _back(shape) - 0.1))
		if place(shape, p.x, p.y, 0.0 if side < 0.0 else PI, opts):
			stalls -= 1
	# Parked cars along the kerbs (a burnt one now and then), benches, bins, a kiosk.
	var parked := rng.randi_range(int(t_spec.get("parked", [3, 6])[0]), int(t_spec.get("parked", [3, 6])[1]))
	for n in parked * 4:
		if parked <= 0:
			break
		var hulk := rng.randf() < float(t_spec.get("hulk_share", 0.2))
		var shape := _pick(style.get("hulks", {"hulk_car": 1})) if hulk else _pick(style.get("vehicles", {"car_sedan": 1}))
		if shape in ["truck_cargo", "truck_tanker", "hulk_truck"]:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p: Vector2 = at.call((cross + 4.0 + rng.randf() * (span - cross - 8.0)) * (-1.0 if rng.randf() < 0.5 else 1.0), side * (street - _back(shape) - 0.15))
		if place(shape, p.x, p.y, 0.0 if rng.randf() < 0.5 else PI, opts):
			parked -= 1
	for want: Array in [["bench", t_spec.get("benches", [2, 4])], ["dumpster", t_spec.get("dumpsters", [1, 3])], ["kiosk", [1, 1]]]:
		var count := rng.randi_range(int(want[1][0]), int(want[1][1]))
		for n in count * 4:
			if count <= 0:
				break
			var shape: String = want[0]
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p: Vector2 = at.call((cross + 1.5 + rng.randf() * (span - cross - 4.0)) * (-1.0 if rng.randf() < 0.5 else 1.0), side * (street - _back(shape) - 0.1))
			if place(shape, p.x, p.y, 0.0 if side < 0.0 else PI, opts):
				count -= 1
	# Bollards at the crossroads' corners, stop signs on the main street's way in, direction signs at
	# the town's ends, a bus shelter.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for b in 3:
				var p: Vector2 = at.call(sx * (cross + 0.4 + b * 0.7), sz * (street - 0.25))
				place("bollard", p.x, p.y, 0.0, opts)
			var s: Vector2 = at.call(sx * (cross + 3.2), sz * (street - 0.3))
			place("sign_stop", s.x, s.y, -sx * PI * 0.5, opts)
	for sx: float in [-1.0, 1.0]:
		var p: Vector2 = at.call(sx * (span - 2.0), street - 0.4)
		place("sign_direction", p.x, p.y, sx * PI * 0.5, opts)
	for n in 6:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p: Vector2 = at.call((span - 10.0 - rng.randf() * 12.0) * (-1.0 if rng.randf() < 0.5 else 1.0), side * (street - _back("bus_shelter") - 0.1))
		if place("bus_shelter", p.x, p.y, 0.0 if side < 0.0 else PI, opts):
			break
	_allow = null
	report.towns += 1
	report.town_props += placed - before
	var dogs := rng.randi_range(int(t_spec.get("dogs", [1, 2])[0]), int(t_spec.get("dogs", [1, 2])[1]))
	animals("dog", o.x, o.y, Vector2(span - 6.0, street - 1.0), 0.0, dogs)


# --- Settlements and sites ---------------------------------------------------------------------

## A site's clutter outside its pad (data "sites" by its base type): containers squared to the
## site, the rest turned any way; a checkpoint's barriers and signs along its road; a village's or
## town's dogs, pen, well and parked cars round it.
func _site(m: Dictionary) -> void:
	var base: String = m.base
	var kit: Array = (_data.get("sites", {}) as Dictionary).get(base, [])
	var pad: Rect2 = m.pad
	for entry: Array in kit:
		var count := rng.randi_range(int(entry[1]), int(entry[2]))
		var shape := String(entry[0])
		if entry.size() > 3 and String(entry[3]) == "run":
			# A straight fence run along one side, a few metres out: a yard.
			for n in 8:
				var p := _ring_point(pad)
				var along := Vector2(1, 0) if absf(p.y - pad.position.y) < 0.5 or absf(p.y - pad.end.y) < 0.5 or rng.randf() < 0.5 else Vector2(0, 1)
				var length := count * (PropArt.SECTION_M + 0.02)
				if line(shape, p, p + along * length, PropArt.SECTION_M + 0.02, false, "", 0, {"road_m": SITE_ROAD_M}) > 0:
					report.sites += 1
					break
			continue
		var tries := count * 12
		while count > 0 and tries > 0:
			tries -= 1
			var p := _ring_point(pad)
			var square := shape.begins_with("container") or shape in ["generator", "fuel_tank", "latrine", "jersey_barrier", "pallet_stack"]
			var yaw := (PI * 0.5 * (rng.randi() % 4)) + (rng.randf_range(-0.06, 0.06) if square else rng.randf() * TAU)
			if place(shape, p.x, p.y, yaw, {"road_m": SITE_ROAD_M}):
				count -= 1
				report.sites += 1
	if base == "checkpoint":
		_checkpoint(m)
	if base in ["village", "town"]:
		_settlement(m)


## A random point in the ring SITE_RING_M out from `pad`'s edge.
func _ring_point(pad: Rect2) -> Vector2:
	var out := rng.randf_range(float(SITE_RING_M[0]), float(SITE_RING_M[1]))
	var r := pad.grow(out)
	var along := rng.randf()
	match rng.randi() % 4:
		0:
			return Vector2(lerpf(r.position.x, r.end.x, along), r.position.y)
		1:
			return Vector2(lerpf(r.position.x, r.end.x, along), r.end.y)
		2:
			return Vector2(r.position.x, lerpf(r.position.y, r.end.y, along))
	return Vector2(r.end.x, lerpf(r.position.y, r.end.y, along))


## A checkpoint's approach: on each road that ends at it, Jersey barriers in a chicane, then a stop
## sign and a warning sign further out.
func _checkpoint(m: Dictionary) -> void:
	var pad: Rect2 = (m.pad as Rect2).grow(0.6)
	for l: Dictionary in _lines:
		for end: Array in [[l.a, l.b], [l.b, l.a]]:
			var near: Vector2 = end[0]
			var far: Vector2 = end[1]
			if not pad.grow(4.0).has_point(near):
				continue
			var d := (far - near).normalized()
			var side := Vector2(-d.y, d.x)
			var t := _exit_t(pad, near, d)
			for k in 3:
				var s := 1.0 if k % 2 == 0 else -1.0
				var p := near + d * (t + 4.0 + k * 5.0) + side * s * (float(l.half_w) - 0.9)
				place("jersey_barrier", p.x, p.y, atan2(-d.y, d.x), {"road_m": 0.0})
			for sign: Array in [["sign_stop", 22.0], ["sign_warn", 45.0]]:
				var p := near + d * (t + float(sign[1])) + side * (float(l.half_w) + 1.4)
				place(String(sign[0]), p.x, p.y, atan2(d.x, d.y), {"road_m": float(l.half_w) + 0.6})


## How far along `d` from `p` (inside `r`) the line leaves rect `r`.
static func _exit_t(r: Rect2, p: Vector2, d: Vector2) -> float:
	var t := INF
	if d.x > 0.001:
		t = minf(t, (r.end.x - p.x) / d.x)
	elif d.x < -0.001:
		t = minf(t, (r.position.x - p.x) / d.x)
	if d.y > 0.001:
		t = minf(t, (r.end.y - p.y) / d.y)
	elif d.y < -0.001:
		t = minf(t, (r.position.y - p.y) / d.y)
	return maxf(t, 0.0) if t != INF else 0.0


## Round a village or town: a well or a water tank, a small pen with goats or sheep, a car or two
## parked, a market stall or two by the road in, and dogs about.
func _settlement(m: Dictionary) -> void:
	var pad: Rect2 = m.pad
	for want: String in [_pick(style.get("water", {"well": 1})), "pen", _pick(style.get("vehicles", {"pickup_civ": 1})), "market_stall"]:
		for n in 14:
			var p := _ring_point(pad)
			if want == "pen":
				if _pen(p, rng.randf() * TAU, Vector2(rng.randf_range(8.0, 11.0), rng.randf_range(7.0, 9.0)), false):
					break
				continue
			if place(want, p.x, p.y, rng.randf() * TAU, {"road_m": SITE_ROAD_M}):
				break
	var c: Vector2 = m.centre
	var h: Vector2 = (m.pad as Rect2).size * 0.5 + Vector2(10.0, 10.0)
	if m.base != "town":
		animals("dog", c.x, c.y, h, 0.0, 1 + rng.randi() % 2)


# --- Roads -------------------------------------------------------------------------------------

## Along each road: utility poles with wires on one side ("pole_roads" of roads), parked and
## abandoned vehicles (some burnt out, some in a cluster where an ambush was), a direction sign by
## each site it reaches, and a bus shelter and a billboard on the way into a town.
func _roadside() -> void:
	var share := float(style.get("pole_roads", 0.5))
	for l: Dictionary in _lines:
		var a: Vector2 = l.a
		var b: Vector2 = l.b
		var length := a.distance_to(b)
		if length < 20.0:
			continue
		var d := (b - a) / length
		var normal := Vector2(-d.y, d.x)
		var hw := float(l.half_w)
		if rng.randf() < share:
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var before := placed
			line(_pick(style.get("pole_kinds", {"utility_pole": 1})), a + normal * s * POLE_OFF_M + d * 10.0, b + normal * s * POLE_OFF_M - d * 10.0, POLE_STEP_M, true, "", 0,
				{"road_m": hw + 1.5}, [0.0, 1.5, -1.0])
			report.poles += placed - before
		# Vehicles: parked on the verge, nose along the road.
		var vehicles := _how_many(length / 1000.0 * float(style.get("roadside_per_km", 1.0)))
		for n in vehicles:
			var t := rng.randf_range(0.15, 0.85) * length
			var cluster := 1 if rng.randf() > 0.25 else rng.randi_range(2, 3)
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			for k in cluster:
				var hulk := cluster > 1 or rng.randf() < float(style.get("hulk_share", 0.35))
				var shape := _pick(style.get("hulks", {"hulk_car": 1})) if hulk else _pick(style.get("vehicles", {"car_sedan": 1}))
				var off := hw + PropArt.foot(shape).size.z * 0.5 + rng.randf_range(0.4, 2.2)
				var p := a + d * (t + k * rng.randf_range(8.0, 15.0)) + normal * s * off
				var yaw := atan2(-d.y, d.x) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.12, 0.12) + (rng.randf_range(-0.5, 0.5) if hulk else 0.0)
				if place(shape, p.x, p.y, yaw, {"road_m": hw + 0.3}):
					report.roadside += 1
	# By the sites: a direction sign where each road leaves a pad; a bus shelter and a billboard on
	# a town's or village's road.
	for m: Dictionary in _modules:
		var pad: Rect2 = m.pad
		var settled: bool = m.base in ["town", "village"]
		var shelter: bool = m.base == "town"
		var board: bool = m.base == "town" or rng.randf() < 0.3
		for l: Dictionary in _lines:
			for end: Array in [[l.a, l.b], [l.b, l.a]]:
				var near: Vector2 = end[0]
				if not pad.grow(4.0).has_point(near):
					continue
				var d := ((end[1] as Vector2) - near).normalized()
				var side := Vector2(-d.y, d.x)
				var t := _exit_t(pad, near, d)
				var hw := float(l.half_w)
				var p := near + d * (t + 14.0) + side * (hw + 2.4)
				place("sign_direction", p.x, p.y, atan2(d.x, d.y), {"road_m": hw + 0.8})
				if settled and shelter:
					var q := near + d * (t + 28.0) - side * (hw + 2.4)
					shelter = not place("bus_shelter", q.x, q.y, atan2(side.x, side.y), {"road_m": hw + 1.2})
				if settled and board:
					var q := near + d * (t + rng.randf_range(45.0, 80.0)) + side * (hw + rng.randf_range(7.0, 12.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
					var face := (near + d * (t + 60.0) - q).normalized()
					board = not place("billboard", q.x, q.y, atan2(face.x, face.y), {"road_m": hw + 4.0})


# --- Countryside -------------------------------------------------------------------------------

## Pylon lines across the zone ("pylon_lines" [min, max]): from one edge to the opposite through
## two bends, a pylon every PYLON_STEP_M, each nudged sideways to find a footing off the pads,
## roads, water and steep ground; its wires hang from pylon to pylon.
func _power_lines() -> void:
	var span: Array = style.get("pylon_lines", [1, 1])
	var lines := rng.randi_range(int(span[0]), int(span[1]))
	var inner := _half - EDGE_KEEP_M - 4.0
	for n in lines:
		var across := rng.randf() < 0.5
		var a := Vector2(-inner, rng.randf_range(-0.7, 0.7) * inner)
		var b := Vector2(inner, rng.randf_range(-0.7, 0.7) * inner)
		if across:
			a = Vector2(a.y, a.x)
			b = Vector2(b.y, b.x)
		var bends: Array[Vector2] = [a]
		for k in [1, 2]:
			var p := a.lerp(b, k / 3.0)
			var side := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
			bends.append(p + side * rng.randf_range(-0.18, 0.18) * inner)
		bends.append(b)
		for k in bends.size() - 1:
			var before := placed
			line("pylon", bends[k], bends[k + 1], PYLON_STEP_M, true, "", 0, {"road_m": ROAD_HALF_M + 5.0}, PYLON_SHIFT_M)
			report.pylons += placed - before


## A farmstead: a pen of goats or sheep (a gate, a shelter and a trough in it), a well or a tank,
## hay, a tractor or a pickup, a dog, field fences out from it with gates, and sometimes an
## irrigation channel with its sluice. On open, flat ground, FARM_PAD_M from any pad, near a road.
func _farm() -> void:
	for attempt in 30:
		var p := Vector2(rng.randf_range(-_half + 60.0, _half - 60.0), rng.randf_range(-_half + 60.0, _half - 60.0))
		var yaw := rng.randf() * TAU
		var size := Vector2(rng.randf_range(float(PEN_W[0]), float(PEN_W[1])), rng.randf_range(float(PEN_D[0]), float(PEN_D[1])))
		if not _farm_site(p):
			continue
		if not _pen(p, yaw, size, true):
			continue
		_farms.append(p)
		report.farms += 1
		var u := _to_world(Vector2(1, 0), yaw)
		var v := _to_world(Vector2(0, 1), yaw)
		var reach := size.length() * 0.5 + 4.0
		# Water, hay, a vehicle.
		var water := _pick(style.get("water", {"well": 1}))
		_near(water, p, reach, reach + 8.0)
		var hay: Array = style.get("hay", [])
		if not hay.is_empty():
			var stack := p + u * (size.x * 0.5 + 5.0) + v * rng.randf_range(-4.0, 4.0)
			for k in rng.randi_range(2, 5):
				var shape := _pick(hay)
				var q := stack + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
				place(shape, q.x, q.y, yaw + rng.randf_range(-0.3, 0.3), {})
		if rng.randf() < 0.7:
			_near("tractor" if rng.randf() < 0.6 else "pickup_civ", p, reach, reach + 10.0)
		if rng.randf() < 0.5:
			var home := p - u * (size.x * 0.5 + 9.0)
			animals("dog", home.x, home.y, Vector2(6.0, 6.0), yaw, 1)
		# Field fences out from the pen's corners, gates along them.
		var fence := _pick(style.get("field_fence", ["fence_rail"]))
		var gate := _pick(style.get("gate", ["gate_farm"]))
		for k in rng.randi_range(1, 3):
			var cs := Vector2(1.0 if k % 2 == 0 else -1.0, 1.0 if k < 2 else -1.0)
			var corner := p + u * cs.x * (size.x * 0.5 + 1.0) + v * cs.y * (size.y * 0.5 + 1.0)
			var dir := (u * cs.x) if k % 2 == 0 else (v * cs.y)
			var length := rng.randf_range(float(FIELD_FENCE_M[0]), float(FIELD_FENCE_M[1]))
			line(fence, corner, corner + dir * length, PropArt.SECTION_M + 0.02, false, gate, FIELD_GATE_EVERY)
		# Irrigation: a channel off to the fields, a sluice at its head, a gap every third section to
		# cross it.
		if rng.randf() < float(style.get("irrigation", 0.0)):
			var head := p + v * (size.y * 0.5 + 6.0)
			var dir := v.rotated(rng.randf_range(-0.4, 0.4))
			var yaw_c := atan2(-dir.y, dir.x)
			if place("sluice_gate", head.x, head.y, yaw_c + PI * 0.5, {}):
				var length := rng.randf_range(float(IRRIGATION_M[0]), float(IRRIGATION_M[1]))
				var t := 2.5
				var k := 0
				while t < length:
					if k % 3 != 2:
						var q := head + dir * t
						place("irrigation_channel", q.x, q.y, yaw_c, {})
					t += 4.02
					k += 1
				var pipe := head - u * 4.0
				place("irrigation_pipe", pipe.x, pipe.y, atan2(-u.y, u.x), {})
		return


## Whether (x, z) suits a farm: dry, gently rolling over the pen's area, FARM_PAD_M off the pads,
## FARM_GAP_M from other farms, and (when the zone has roads) within 220 m of one but off it.
func _farm_site(p: Vector2) -> bool:
	for pad: Array in _pads:
		var r: Rect2 = pad[0]
		if r.grow(FARM_PAD_M).has_point(p):
			return false
	for f in _farms:
		if f.distance_to(p) < FARM_GAP_M:
			return false
	if not _lines.is_empty():
		var nearest := INF
		for l: Dictionary in _lines:
			nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(p, l.a, l.b).distance_to(p))
		if nearest < 25.0 or nearest > 220.0:
			return false
	var lo := INF
	var hi := -INF
	for dz in [-14.0, 0.0, 14.0]:
		for dx in [-14.0, 0.0, 14.0]:
			var h := terrain.height_at(p.x + dx, p.y + dz)
			if terrain.sea_side >= 0 and h < terrain.sea_level + 0.5:
				return false
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo < 2.2 and terrain.normal_at(p.x, p.y).y > 0.95


## A pen `size` (x, z) round `c` turned `yaw`: the style's pen fence on all four sides with an
## open gate in one, its animals inside, and (`kit`) a shelter in a corner and a trough. False if it
## doesn't fit (it places nothing then: every section is checked first).
func _pen(c: Vector2, yaw: float, size: Vector2, kit: bool) -> bool:
	var fence := _pick(style.get("pen_fence", ["fence_rail"]))
	var gate := _pick(style.get("gate", ["gate_farm"]))
	var u := _to_world(Vector2(1, 0), yaw)
	var v := _to_world(Vector2(0, 1), yaw)
	var nx := maxi(roundi(size.x / PropArt.SECTION_M), 2)
	var nz := maxi(roundi(size.y / PropArt.SECTION_M), 2)
	size = Vector2(nx, nz) * (PropArt.SECTION_M + 0.02)
	var sections: Array = []  # [shape, pos, yaw]
	var gate_side := rng.randi() % 4
	for side in 4:
		var along_x := side < 2
		var count := nx if along_x else nz
		var length := size.x if along_x else size.y
		var s := -1.0 if side % 2 == 0 else 1.0
		var mid := (v * s * size.y * 0.5) if along_x else (u * s * size.x * 0.5)
		var dir := u if along_x else v
		for k in count:
			var t := (k + 0.5) * length / count - length * 0.5
			var p := c + mid + dir * t
			var shape := gate if side == gate_side and k == count / 2 else fence
			var y := atan2(-dir.y, dir.x)
			if shape == gate and ((along_x and s < 0.0) or (not along_x and s > 0.0)):
				y += PI  # the leaf swings out of the pen (its +z outward)
			sections.append([shape, p, y])
	for sec: Array in sections:
		_shape_now = sec[0]
		if not _fits(sec[0], _footprint(sec[0], (sec[1] as Vector2).x, (sec[1] as Vector2).y, sec[2]), {}) or _ground_under(_footprint(sec[0], (sec[1] as Vector2).x, (sec[1] as Vector2).y, sec[2])) == INF:
			return false
	for sec: Array in sections:  # (each checked above; free: a side's end section meets the next side's at the corner)
		place(sec[0], (sec[1] as Vector2).x, (sec[1] as Vector2).y, sec[2], {"free": true})
	var inside := size * 0.5 - Vector2(1.4, 1.4)
	if kit:
		var corner := c + u * (size.x * 0.5 - 2.0) + v * (size.y * 0.5 - 1.8)
		place("pen_shelter", corner.x, corner.y, yaw + PI, {})
		var trough := c - u * (size.x * 0.25) + v * (size.y * 0.5 - 1.0)
		place("trough", trough.x, trough.y, yaw, {})
	_reserve(c, yaw, size * 0.5 - Vector2(0.3, 0.3))  # (no tree or rock grows in the pen)
	var species := _pick(style.get("animals", {"goat": 1}))
	animals(species, c.x, c.y, inside, yaw, rng.randi_range(3, 7) if kit else rng.randi_range(2, 4))
	return true


## `shape` somewhere `r0` to `r1` from `c`, turned any way; whether it went.
func _near(shape: String, c: Vector2, r0: float, r1: float) -> bool:
	for n in 12:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r1)
		if place(shape, p.x, p.y, rng.randf() * TAU, {}):
			return true
	return false


## A walled cemetery by the biggest settlement (the style's wall and gate, graves in rows inside).
func _cemetery() -> void:
	var best: Dictionary = {}
	for m: Dictionary in _modules:
		if m.base in ["town", "village"] and (best.is_empty() or (m.pad as Rect2).get_area() > (best.pad as Rect2).get_area()):
			best = m
	if best.is_empty():
		return
	var wall := String(style.get("cemetery_wall", "wall_block"))
	var gate := String(style.get("cemetery_gate", "gate_steel"))
	var graves: Dictionary = style.get("graves", {"headstone": 1})
	for attempt in 40:
		var size := Vector2(rng.randf_range(float(CEMETERY_W[0]), float(CEMETERY_W[1])), rng.randf_range(float(CEMETERY_D[0]), float(CEMETERY_D[1])))
		var nx := maxi(roundi(size.x / PropArt.SECTION_M), 3)
		var nz := maxi(roundi(size.y / PropArt.SECTION_M), 3)
		size = Vector2(nx, nz) * (PropArt.SECTION_M + 0.02)
		var r := (best.pad as Rect2).grow(rng.randf_range(20.0, 110.0) + size.length() * 0.5)
		var along := rng.randf()
		var c := [Vector2(lerpf(r.position.x, r.end.x, along), r.position.y), Vector2(lerpf(r.position.x, r.end.x, along), r.end.y),
			Vector2(r.position.x, lerpf(r.position.y, r.end.y, along)), Vector2(r.end.x, lerpf(r.position.y, r.end.y, along))][rng.randi() % 4] as Vector2
		var yaw := rng.randf_range(-0.3, 0.3)
		if not _flat_enough(c, size, 1.6):
			continue
		var u := _to_world(Vector2(1, 0), yaw)
		var v := _to_world(Vector2(0, 1), yaw)
		var sections: Array = []
		for side in 4:
			var along_x := side < 2
			var count := nx if along_x else nz
			var length := size.x if along_x else size.y
			var s := -1.0 if side % 2 == 0 else 1.0
			var mid := (v * s * size.y * 0.5) if along_x else (u * s * size.x * 0.5)
			var dir := u if along_x else v
			for k in count:
				var t := (k + 0.5) * length / count - length * 0.5
				var shape := gate if side == 0 and k == count / 2 else wall
				var y := atan2(-dir.y, dir.x) + (PI if shape == gate else 0.0)
				sections.append([shape, c + mid + dir * t, y])
		var fits := true
		for sec: Array in sections:
			_shape_now = sec[0]
			var foot := _footprint(sec[0], (sec[1] as Vector2).x, (sec[1] as Vector2).y, sec[2])
			if not _fits(sec[0], foot, {}) or _ground_under(foot) == INF:
				fits = false
				break
		if not fits:
			continue
		for sec: Array in sections:  # (checked above; free: the corners' sections meet)
			place(sec[0], (sec[1] as Vector2).x, (sec[1] as Vector2).y, sec[2], {"free": true})
		# Graves in rows, heads to +x (the gate's side, -z, left open as a path).
		var cols := int((size.x - 3.0) / GRAVE_STEP.x)
		var rows := int((size.y - 4.0) / GRAVE_STEP.y)
		for j in rows:
			for i in cols:
				if rng.randf() > GRAVE_FILL:
					continue
				var local := Vector2((i + 0.5) * GRAVE_STEP.x - cols * GRAVE_STEP.x * 0.5, (j + 0.5) * GRAVE_STEP.y - rows * GRAVE_STEP.y * 0.5 + 1.0)
				var p := c + u * local.x + v * local.y
				place(_pick(graves), p.x, p.y, yaw + rng.randf_range(-0.04, 0.04), {})
		_reserve(c, yaw, size * 0.5 - Vector2(0.3, 0.3))
		report.cemeteries += 1
		return


func _flat_enough(c: Vector2, size: Vector2, drop: float) -> bool:
	var lo := INF
	var hi := -INF
	for dz in [-0.5, 0.0, 0.5]:
		for dx in [-0.5, 0.0, 0.5]:
			var h := terrain.height_at(c.x + dx * size.x, c.y + dz * size.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo <= drop


## A burnt-out vehicle hulk in place of one of ZoneScatter's old box car wrecks, at (x, z) turned
## `yaw`, if it fits; whether it did.
func hulk(x: float, z: float, yaw: float) -> bool:
	var shape := _pick(style.get("hulks", {"hulk_car": 1}))
	return place(shape, x, z, yaw, {"road_m": ROAD_HALF_M + 3.0})
