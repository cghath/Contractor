class_name ZoneRoads
extends Node3D
## The zone's roads (cg_brief queue item 1.2): RoadNet plans them from the def on the generated
## terrain (curves that follow the ground, junctions, roundabouts, roads out through the crossings)
## and grades the terrain to them; this lays them: asphalt with its markings, dirt tracks, and in
## the towns kerbed pavements and a mini roundabout at the crossroads. Every peer plans and lays
## the same roads.
##
## Collision: every surface is a trimesh (ConcavePolygonShape3D), per TILE_M tile, one body for the
## hard surfaces (asphalt, concrete: hard footsteps, meta "hard_ground") and one for the soft (dirt),
## each with its kind's friction (PhysicsMaterial; Vehicle doesn't read surface grip yet, F-215).
## Edges slope down to the graded ground (SKIRT_M) and kerbs are chamfered (no step to trip on).
## Meshes: one per tile (the road shader, zone_road.gdshader), drawn out to SEE_M; past that the
## terrain's own colour carries them (ZoneTerrain.set_roads, road_weight).
##
## The public API (the water, props and building sides use it; all world space, metres):
##   ZoneRoads.of(node)        the level's roads (null in a level without them)
##   segments()                every road: {"id", "kind", "width", "points" (PackedVector3Array: the
##                             centreline on the surface), "water" ([[from, to]] sample spans over
##                             water: left out for a bridge), "drawn" (PackedByteArray: 0 where not
##                             laid: on a pad, over water or a bridge, inside a roundabout), "a"/"b" (its ends:
##                             {"site", "junction", "crossing"})}
##   junctions()               {"pos", "kind" ("x", "t", "node", "roundabout"), "radius", "roads"}
##   water_crossings()         where a road meets water: {"road", "kind", "width", "from", "to" (the
##                             banks, on the road), "deck_y", "dir"}: where the bridges go
##   edges(offset_m)           the roads' sides offset_m past their edges, in runs clear of pads,
##                             junctions and water: {"road", "kind", "side" (-1 left, 1 right),
##                             "points" (on the ground), "out" (facing away from the road)}
##   pavements()               towns' pavements: {"town", "a", "b" (the kerb line on the pavement's
##                             top), "out" (toward the buildings), "width"}
##   exits()                   the roads out through the crossings: {"crossing", "to", "side",
##                             "edge" (Vector3: at the zone's edge), "pos", "kind", "width", "road"}
##   surface_at(x, z)          the road's surface height there, -INF off the roads
##   kind_at(x, z)             "asphalt", "dirt", "street", "pavement", "island" or ""
##   distance_to(x, z)         metres from the nearest road's edge (0 on it; INF past 60 m)

## Drawn out to this distance (m); tiles (m) for meshes and collision.
const SEE_M := 600.0
const TILE_M := 256.0
const SHADER := preload("res://scripts/world/zone_road.gdshader")
## What the shader draws (UV2.y): asphalt with its markings, dirt, concrete (kerbs, pavements),
## plain asphalt (junctions, rings, town streets), an island's grass, white paint.
enum Look { ASPHALT, DIRT, CONCRETE, PLAIN, ISLAND, PAINT }
## A road's edge slopes down to the ground over this (m); patches, rings and town streets sit this
## far above the roads and pads under them (m), so nothing flickers.
const SKIRT_M := 0.45
const DISC_LIFT_M := 0.015
const RING_LIFT_M := 0.01
const STREET_LIFT_M := 0.02
## Concrete, kerb and paint colours (Proposed).
const CONCRETE := Color("9b988f")
const KERB := Color("85827b")
const PAINT := Color("d9d6cc")
## A pavement's width (m): from the kerb back to the building fronts (BuildingGen's setback).
const PAVEMENT_W := 2.0

var net: RoadNet
var terrain: ZoneTerrain
## Costs, for checks and the zone log: building the meshes and collision (ms), triangles drawn,
## collision faces, bodies and mesh tiles.
var build_ms := 0.0
var triangles := 0
var collision_faces := 0
var bodies := 0
var tiles := 0

var _visual := false
var _tiles := {}  # Vector2i -> {"v", "n", "c", "uv", "uv2", "hard", "soft"} (packed arrays)
## The batch being built (_tri), all in tile _b_key: flushed into _tiles when a triangle lands in
## another tile, and at the end (appending straight to a packed array in a dictionary would copy it
## every time).
var _b_key := Vector2i(1 << 30, 0)
var _b_hard := PackedVector3Array()
var _b_soft := PackedVector3Array()
var _b_v := PackedVector3Array()
var _b_n := PackedVector3Array()
var _b_c := PackedColorArray()
var _b_uv := PackedVector2Array()
var _b_uv2 := PackedVector2Array()
var _built := false
var _town_parts: Array[Dictionary] = []  # {"rect" (Rect2), "y", "kind"}: surface_at's town lookups
var _pavements: Array[Dictionary] = []


## The roads of `node`'s level, or null.
static func of(node: Node) -> ZoneRoads:
	var level := CompoundLevel.current(node) if node else null
	var r: Variant = level.get(&"roads") if level else null
	return r if r is ZoneRoads else null


## Plans the roads for `def` on `t` (generated, collision not built yet), cuts and fills the
## terrain to them and writes the def's "roads" and the trails' "patrols". Before the terrain's
## collision and the scatter.
func prepare(t: ZoneTerrain, def: Dictionary) -> void:
	terrain = t
	net = RoadNet.plan(def, t)
	t.set_roads(def.get("roads", []))
	_plan_towns()


## The roads' collision (every peer: vehicles and soldiers stand on it).
func build_collision() -> void:
	_build_geometry()
	var started := Time.get_ticks_usec()
	for key: Vector2i in _tiles:
		var tile: Dictionary = _tiles[key]
		for hard: bool in [true, false]:
			var faces: PackedVector3Array = tile.hard if hard else tile.soft
			if faces.is_empty():
				continue
			var body := StaticBody3D.new()
			body.name = "Road_%d_%d_%s" % [key.x, key.y, "hard" if hard else "soft"]
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta(&"hard_ground", hard)
			body.set_meta(&"road", "asphalt" if hard else "dirt")
			var mat := PhysicsMaterial.new()
			mat.friction = float(RoadNet.kind("asphalt" if hard else "dirt").get("friction", 1.0))
			body.physics_material_override = mat
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var node := CollisionShape3D.new()
			node.shape = shape
			body.add_child(node)
			add_child(body)
			bodies += 1
			collision_faces += faces.size() / 3
	build_ms += (Time.get_ticks_usec() - started) / 1000.0
	if not _visual:
		_tiles.clear()


## The roads' meshes (with a display only).
func build_visuals() -> void:
	_build_geometry()
	var started := Time.get_ticks_usec()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"seed_offset", float(terrain.seed_value % 97) * 3.1)
	mat.set_shader_parameter(&"verge_colour", terrain.c_dry.lerp(terrain.c_grass, 0.5))
	for key: Vector2i in _tiles:
		var tile: Dictionary = _tiles[key]
		var verts: PackedVector3Array = tile.v
		if verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = tile.n
		arrays[Mesh.ARRAY_COLOR] = tile.c
		arrays[Mesh.ARRAY_TEX_UV] = tile.uv
		arrays[Mesh.ARRAY_TEX_UV2] = tile.uv2
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshInstance3D.new()
		node.name = "RoadMesh_%d_%d" % [key.x, key.y]
		node.mesh = mesh
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = SEE_M
		node.visibility_range_end_margin = 40.0
		add_child(node)
		tiles += 1
		triangles += verts.size() / 3
	_tiles.clear()
	build_ms += (Time.get_ticks_usec() - started) / 1000.0


# --- The public API --------------------------------------------------------------------------

func segments() -> Array:
	var out: Array = []
	for r: Dictionary in net.roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		var line := PackedVector3Array()
		var drawn := PackedByteArray()
		line.resize(pts.size())
		drawn.resize(pts.size())
		for k in pts.size():
			line[k] = Vector3(pts[k].x, ys[k], pts[k].y)
			drawn[k] = 1 if _drawn(r, k) else 0
		out.append({"id": int(r.id), "kind": String(r.kind), "width": float(r.hw) * 2.0, "points": line, "water": (r.water as Array).duplicate(true),
			"drawn": drawn, "a": _end_info(r.a), "b": _end_info(r.b)})
	return out


func junctions() -> Array:
	var out: Array = []
	for j: Dictionary in net.junctions:
		out.append({"pos": Vector3(j.pos.x, float(j.y), j.pos.y), "kind": String(j.kind), "radius": float(j.r), "roads": (j.roads as Array).duplicate()})
	return out


func water_crossings() -> Array:
	var out: Array = []
	for r: Dictionary in net.roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		for span: Array in r.water:
			var a := int(span[0])
			var b := int(span[1])
			var from := Vector3(pts[a].x, ys[a], pts[a].y)
			var to := Vector3(pts[b].x, ys[b], pts[b].y)
			out.append({"road": int(r.id), "kind": String(r.kind), "width": float(r.hw) * 2.0, "from": from, "to": to,
				"deck_y": maxf(from.y, to.y), "dir": (to - from).normalized()})
	return out


func edges(offset_m := 0.5) -> Array:
	var out: Array = []
	for r: Dictionary in net.roads:
		var pts: PackedVector2Array = r.pts
		var hw := float(r.hw)
		for side: float in [-1.0, 1.0]:
			var run := PackedVector3Array()
			var outs := PackedVector3Array()
			for k in pts.size():
				var keep := _drawn(r, k) and not _near_junction(pts[k], 2.0)
				if keep:
					var n := _side(pts, k) * side
					var p := pts[k] + n * (hw + offset_m)
					run.append(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
					outs.append(Vector3(n.x, 0.0, n.y))
				if (not keep or k == pts.size() - 1) and run.size() >= 2:
					out.append({"road": int(r.id), "kind": String(r.kind), "side": int(side), "points": run, "out": outs})
				if not keep:
					run = PackedVector3Array()
					outs = PackedVector3Array()
	return out


func pavements() -> Array:
	return _pavements.duplicate(true)


func exits() -> Array:
	var out: Array = []
	for e: Dictionary in net.exits:
		var edge: Vector2 = e.edge
		var pos: Vector2 = e.pos
		var e2 := e.duplicate()
		e2["edge"] = Vector3(edge.x, terrain.height_at(edge.x, edge.y), edge.y)
		e2["pos"] = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
		out.append(e2)
	return out


func surface_at(x: float, z: float) -> float:
	return float(_surface(x, z)[0])


func kind_at(x: float, z: float) -> String:
	return String(_surface(x, z)[1])


func distance_to(x: float, z: float) -> float:
	if surface_at(x, z) > -INF:
		return 0.0
	var near := net.nearest(x, z, 60.0)
	if near.is_empty():
		return INF
	return maxf(float(near.d) - float(net.roads[int(near.road)].hw), 0.0)


## [height, kind] at (x, z): [-INF, ""] off the roads.
func _surface(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	for part: Dictionary in _town_parts:
		if (part.rect as Rect2).has_point(p):
			return [float(part.y), String(part.kind)]
	for j: Dictionary in net.junctions:
		var d := (j.pos as Vector2).distance_to(p)
		if String(j.kind) == "roundabout" and d <= float(j.r):
			var island := float(j.island)
			if d < island:
				return [float(j.y) + float((RoadNet.data().get("roundabout", {}) as Dictionary).get("island_h_m", 0.15)), "island"]
			return [float(j.y) + RING_LIFT_M, "asphalt"]
	var near := net.nearest(x, z, 8.0)
	if near.is_empty():
		return [-INF, ""]
	var r: Dictionary = net.roads[int(near.road)]
	var k := int(near.sample)
	if float(near.d) > float(r.hw) or not (_drawn(r, k) or _drawn(r, k + 1)):
		return [-INF, ""]
	return [float(near.y), String(r.kind)]


func _end_info(e: Dictionary) -> Dictionary:
	var j := -1
	if e.has("join"):
		for i in net.junctions.size():
			if (net.junctions[i].pos as Vector2).distance_to(e.exit) < 1.0:
				j = i
	return {"site": String(e.get("site", "")), "junction": j, "crossing": String(e.get("edge", ""))}


## Whether road `r`'s sample `k` is laid: not over water, inside a roundabout or on a pad.
func _drawn(r: Dictionary, k: int) -> bool:
	if not r.has("laid"):
		var pts: PackedVector2Array = r.pts
		var skip: PackedByteArray = r.skip
		var wet: PackedByteArray = r.wet
		var bridge: PackedByteArray = r.get("bridge", PackedByteArray())
		var laid := PackedByteArray()
		laid.resize(pts.size())
		var pads: Array[Rect2] = []
		for pad: Array in terrain.pads:
			pads.append((pad[0] as Rect2).grow(-0.5))
		for i in pts.size():
			var on := skip[i] == 0 and wet[i] == 0 and (bridge.is_empty() or bridge[i] == 0)  # (a bridge's deck carries it: F-175)
			if on:
				for pad in pads:
					if pad.has_point(pts[i]):
						on = false
						break
			laid[i] = 1 if on else 0
		r["laid"] = laid
	return k >= 0 and k < (r.laid as PackedByteArray).size() and (r.laid as PackedByteArray)[k] == 1


func _near_junction(p: Vector2, extra: float) -> bool:
	for j: Dictionary in net.junctions:
		if (j.pos as Vector2).distance_to(p) < float(j.r) + extra:
			return true
	return false


## The road's unit sideways (left) at sample `k`.
static func _side(pts: PackedVector2Array, k: int) -> Vector2:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	return (b - a).normalized().orthogonal()


# --- Geometry --------------------------------------------------------------------------------

func _build_geometry() -> void:
	if _built:
		return
	_built = true
	var started := Time.get_ticks_usec()
	_visual = DisplayServer.get_name() != "headless"
	for r: Dictionary in net.roads:
		_road(r)
	for j: Dictionary in net.junctions:
		if String(j.kind) == "roundabout":
			_roundabout(j)
		elif not _on_pad(j.pos):
			_patch(j)
	for town: Dictionary in net.towns:
		_town(town)
	_flush()
	build_ms += (Time.get_ticks_usec() - started) / 1000.0


## The batch into its tile.
func _flush() -> void:
	if _b_hard.is_empty() and _b_soft.is_empty() and _b_v.is_empty():
		return
	if not _tiles.has(_b_key):
		_tiles[_b_key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(),
			"uv2": PackedVector2Array(), "hard": PackedVector3Array(), "soft": PackedVector3Array()}
	var tile: Dictionary = _tiles[_b_key]
	for pair: Array in [["hard", _b_hard], ["soft", _b_soft], ["v", _b_v], ["n", _b_n], ["c", _b_c], ["uv", _b_uv], ["uv2", _b_uv2]]:
		var have: Variant = tile[pair[0]]
		have.append_array(pair[1])
		tile[pair[0]] = have
	_b_hard = PackedVector3Array()
	_b_soft = PackedVector3Array()
	_b_v = PackedVector3Array()
	_b_n = PackedVector3Array()
	_b_c = PackedColorArray()
	_b_uv = PackedVector2Array()
	_b_uv2 = PackedVector2Array()


func _on_pad(p: Vector2) -> bool:
	for pad: Array in terrain.pads:
		if (pad[0] as Rect2).grow(-0.5).has_point(p):
			return true
	return false


## One road: a flat strip across (edge, middle, edge) and a sloped skirt each side, every sample.
func _road(r: Dictionary) -> void:
	var pts: PackedVector2Array = r.pts
	var ys: PackedFloat32Array = r.ys
	var s: PackedFloat32Array = r.s
	var hw := float(r.hw)
	var kind_id := String(r.kind)
	var spec := RoadNet.kind(kind_id)
	var hard := bool(spec.get("hard", false))
	var look := Look.DIRT if kind_id == "dirt" else (Look.ASPHALT if bool(spec.get("lines", false)) else Look.PLAIN)
	var colour := Color(String(spec.colour)) if String(spec.get("colour", "")) != "" else terrain.c_road
	var offsets: Array[float] = [-hw - SKIRT_M, -hw, hw, hw + SKIRT_M]
	var prev: Array = []
	for k in pts.size():
		if not _drawn(r, k):
			prev = []
			continue
		var n := _side(pts, k)
		var row: Array = []
		for o in offsets:
			var q := pts[k] + n * o
			var y := ys[k] if absf(o) <= hw else ys[k] - RoadNet.SINK_M - 0.06
			row.append([Vector3(q.x, y, q.y), Vector2(o, s[k])])
		if not prev.is_empty():
			for c in offsets.size() - 1:
				var skirt := c == 0 or c == offsets.size() - 2
				var col := colour.darkened(0.12) if skirt else colour
				_quad(prev[c][0], prev[c + 1][0], row[c + 1][0], row[c][0], prev[c][1], prev[c + 1][1], row[c + 1][1], row[c][1],
					col, Vector2(hw, look), 1 if hard else 2)
		prev = row


## A plain junction's patch over where its roads overlap.
func _patch(j: Dictionary) -> void:
	var any_asphalt := (j.roads as Array).any(func(i: int) -> bool: return String(net.roads[i].kind) != "dirt")
	var spec := RoadNet.kind("asphalt" if any_asphalt else "dirt")
	var colour := Color(String(spec.colour)) if any_asphalt else terrain.c_road
	var look := Look.PLAIN if any_asphalt else Look.DIRT
	var c := Vector3(j.pos.x, float(j.y) + DISC_LIFT_M, j.pos.y)
	_disc(c, 0.0, float(j.r), 0.0, 0.0, 24, colour, look, 0)


## A roundabout: the ring, its edge sloping down to the ground, the island's kerb and its grass.
func _roundabout(j: Dictionary) -> void:
	var spec: Dictionary = RoadNet.data().get("roundabout", {})
	var island := float(j.island)
	var outer := float(j.r)
	var h := float(spec.get("island_h_m", 0.15))
	var c := Vector3(j.pos.x, float(j.y) + RING_LIFT_M, j.pos.y)
	var asphalt := Color(String(RoadNet.kind("asphalt").colour))
	_disc(c, island, outer, 0.0, 0.0, 40, asphalt, Look.PLAIN, 1)
	_disc(c, outer, outer + SKIRT_M, 0.0, -RoadNet.SINK_M - 0.06 - RING_LIFT_M, 40, asphalt.darkened(0.12), Look.PLAIN, 1)
	_disc(c, island - 0.25, island, h, 0.0, 40, KERB, Look.CONCRETE, 1)
	_disc(c, 0.0, island - 0.25, h, h, 40, terrain.c_grass, Look.ISLAND, 2)


## A ring (a disc with `inner` 0) round `c` from `inner` (at y + `y_in`) to `outer` (y + `y_out`).
func _disc(c: Vector3, inner: float, outer: float, y_in: float, y_out: float, sides: int, colour: Color, look: int, solid: int) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var o0 := c + d0 * outer + Vector3(0, y_out, 0)
		var o1 := c + d1 * outer + Vector3(0, y_out, 0)
		var uv_o0 := Vector2(outer, a0 * outer)
		var uv_o1 := Vector2(outer, a1 * outer)
		if inner <= 0.0:
			var mid := c + Vector3(0, y_in, 0)
			_tri(mid, o0, o1, Vector2(0, 0), uv_o0, uv_o1, colour, Vector2(outer, look), solid)
		else:
			var i0 := c + d0 * inner + Vector3(0, y_in, 0)
			var i1 := c + d1 * inner + Vector3(0, y_in, 0)
			_quad(i0, o0, o1, i1, Vector2(inner, a0 * inner), uv_o0, uv_o1, Vector2(inner, a1 * inner), colour, Vector2(outer, look), solid)


# --- Towns -----------------------------------------------------------------------------------

## A town's streets (BuildingGen.town: the main street along x, the cross street along z), each a
## carriageway between kerbed pavements; the parts surface_at answers for.
func _plan_towns() -> void:
	var spec: Dictionary = RoadNet.data().get("town", {})
	var kerb_in := float(spec.get("kerb_in_m", 1.0))
	var ph := float(spec.get("pavement_h_m", 0.12))
	for town: Dictionary in net.towns:
		var c: Vector2 = town.pos
		var y := float(town.y)
		var dims := _town_dims(town)
		var cwm: float = dims.cwm
		var cwc: float = dims.cwc
		var ext: Vector2 = dims.ext
		var half: Vector2 = town.half
		_town_parts.append({"rect": Rect2(c.x - ext.x, c.y - cwm, ext.x * 2.0, cwm * 2.0), "y": y + STREET_LIFT_M, "kind": "street"})
		_town_parts.append({"rect": Rect2(c.x - cwc, c.y - ext.y, cwc * 2.0, ext.y * 2.0), "y": y + STREET_LIFT_M, "kind": "street"})
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				# Along the main street, and down the cross street; kerb lines for the props.
				var main := _local_rect(c, sx, sz, Vector2(cwc, cwm), Vector2(BuildingGen.TOWN_HALF_X, cwm + PAVEMENT_W))
				var cross := _local_rect(c, sx, sz, Vector2(cwc, cwm + PAVEMENT_W), Vector2(cwc + PAVEMENT_W, half.y))
				_town_parts.append({"rect": main, "y": y + ph, "kind": "pavement"})
				_town_parts.append({"rect": cross, "y": y + ph, "kind": "pavement"})
				_pavements.append({"town": String(town.id), "a": Vector3(c.x + sx * cwc, y + ph, c.y + sz * cwm), "b": Vector3(c.x + sx * BuildingGen.TOWN_HALF_X, y + ph, c.y + sz * cwm),
					"out": Vector3(0, 0, sz), "width": PAVEMENT_W})
				_pavements.append({"town": String(town.id), "a": Vector3(c.x + sx * cwc, y + ph, c.y + sz * (cwm + PAVEMENT_W)), "b": Vector3(c.x + sx * cwc, y + ph, c.y + sz * half.y),
					"out": Vector3(sx, 0, 0), "width": PAVEMENT_W})
		town["kerb_in"] = kerb_in


func _town_dims(town: Dictionary) -> Dictionary:
	var kerb_in := float((RoadNet.data().get("town", {}) as Dictionary).get("kerb_in_m", 1.0))
	var half: Vector2 = town.half
	return {"cwm": BuildingGen.STREET_W * 0.5 - kerb_in, "cwc": BuildingGen.CROSS_W * 0.5 - kerb_in,
		"ext": half + Vector2(ZoneTerrain.PAD_MARGIN_M, ZoneTerrain.PAD_MARGIN_M)}


## The rect from `lo` to `hi` (the town's +x +z quarter, m from its middle `c`) mirrored into the
## quarter (sx, sz).
static func _local_rect(c: Vector2, sx: float, sz: float, lo: Vector2, hi: Vector2) -> Rect2:
	var a := c + Vector2(sx * lo.x, sz * lo.y)
	var b := c + Vector2(sx * hi.x, sz * hi.y)
	return Rect2(a, Vector2.ZERO).expand(b)


func _town(town: Dictionary) -> void:
	var spec: Dictionary = RoadNet.data().get("town", {})
	var ph := float(spec.get("pavement_h_m", 0.12))
	var chamfer := float(spec.get("kerb_chamfer_m", 0.18))
	var c: Vector2 = town.pos
	var y := float(town.y)
	var dims := _town_dims(town)
	var cwm: float = dims.cwm
	var cwc: float = dims.cwc
	var ext: Vector2 = dims.ext
	var half: Vector2 = town.half
	var street := Color(String(RoadNet.kind("street").get("colour", "45443f")))
	var top := y + STREET_LIFT_M
	# The carriageways: the main street end to end, the cross street either side of it.
	_flat(Rect2(c.x - ext.x, c.y - cwm, ext.x * 2.0, cwm * 2.0), top, street, Vector2(cwm, Look.PLAIN), true)
	_flat(Rect2(c.x - cwc, c.y - ext.y, cwc * 2.0, ext.y - cwm), top, street, Vector2(cwc, Look.PLAIN), false)
	_flat(Rect2(c.x - cwc, c.y + cwm, cwc * 2.0, ext.y - cwm), top, street, Vector2(cwc, Look.PLAIN), false)
	# The pavements, kerbed on the street sides and their open ends.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_slab(c, sx, sz, Vector2(cwc, cwm), Vector2(BuildingGen.TOWN_HALF_X, cwm + PAVEMENT_W), y, top, ph, chamfer, ["x0", "z0", "x1"])
			_slab(c, sx, sz, Vector2(cwc, cwm + PAVEMENT_W), Vector2(cwc + PAVEMENT_W, half.y), y, top, ph, chamfer, ["x0", "z1"])
	# The mini roundabout at the crossroads: a low white dome you can drive over.
	var r := float(spec.get("mini_island_r_m", 2.0))
	var h := float(spec.get("mini_island_h_m", 0.08))
	var mid := Vector3(c.x, top, c.y)
	_disc(mid, r * 0.75, r, h, 0.005, 24, PAINT, Look.PAINT, 1)
	_disc(mid, 0.0, r * 0.75, h + 0.02, h, 24, PAINT, Look.PAINT, 1)


## A flat rectangle at height `y`, in pieces of up to 8 m (UV: across from its middle line, along).
func _flat(rect: Rect2, y: float, colour: Color, look: Vector2, along_x: bool) -> void:
	var len := rect.size.x if along_x else rect.size.y
	var n := maxi(ceili(len / 8.0), 1)
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var a: Vector3
		var b: Vector3
		var cc: Vector3
		var d: Vector3
		var w := rect.size.y if along_x else rect.size.x
		if along_x:
			var x0 := rect.position.x + rect.size.x * t0
			var x1 := rect.position.x + rect.size.x * t1
			a = Vector3(x0, y, rect.position.y)
			b = Vector3(x1, y, rect.position.y)
			cc = Vector3(x1, y, rect.end.y)
			d = Vector3(x0, y, rect.end.y)
		else:
			var z0 := rect.position.y + rect.size.y * t0
			var z1 := rect.position.y + rect.size.y * t1
			a = Vector3(rect.position.x, y, z0)
			b = Vector3(rect.position.x, y, z1)
			cc = Vector3(rect.end.x, y, z1)
			d = Vector3(rect.end.x, y, z0)
		_quad(a, b, cc, d, Vector2(-w * 0.5, len * t0), Vector2(-w * 0.5, len * t1), Vector2(w * 0.5, len * t1), Vector2(w * 0.5, len * t0),
			colour, look, 1)


## A pavement slab in the town's quarter (sx, sz) from `lo` to `hi` (m from the middle `c`): its top
## at ground `y` + `ph`, a chamfered kerb down to the street (`street_y`) on the `kerbs` sides
## ("x0", "x1", "z0", "z1": the low and high x and z sides, in the +x +z quarter).
func _slab(c: Vector2, sx: float, sz: float, lo: Vector2, hi: Vector2, y: float, street_y: float, ph: float, chamfer: float, kerbs: Array) -> void:
	var map := func(p: Vector2, h: float) -> Vector3: return Vector3(c.x + sx * p.x, h, c.y + sz * p.y)
	var t_lo := lo + Vector2(chamfer if "x0" in kerbs else 0.0, chamfer if "z0" in kerbs else 0.0)
	var t_hi := hi - Vector2(chamfer if "x1" in kerbs else 0.0, chamfer if "z1" in kerbs else 0.0)
	var top := y + ph
	# The top, in pieces of up to 8 m along its length.
	var along_x := (hi.x - lo.x) >= (hi.y - lo.y)
	var len := (t_hi.x - t_lo.x) if along_x else (t_hi.y - t_lo.y)
	var n := maxi(ceili(len / 8.0), 1)
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		var p0: Vector2
		var p1: Vector2
		var p2: Vector2
		var p3: Vector2
		if along_x:
			p0 = Vector2(lerpf(t_lo.x, t_hi.x, f0), t_lo.y)
			p1 = Vector2(lerpf(t_lo.x, t_hi.x, f1), t_lo.y)
			p2 = Vector2(lerpf(t_lo.x, t_hi.x, f1), t_hi.y)
			p3 = Vector2(lerpf(t_lo.x, t_hi.x, f0), t_hi.y)
		else:
			p0 = Vector2(t_lo.x, lerpf(t_lo.y, t_hi.y, f0))
			p1 = Vector2(t_lo.x, lerpf(t_lo.y, t_hi.y, f1))
			p2 = Vector2(t_hi.x, lerpf(t_lo.y, t_hi.y, f1))
			p3 = Vector2(t_hi.x, lerpf(t_lo.y, t_hi.y, f0))
		_quad(map.call(p0, top), map.call(p1, top), map.call(p2, top), map.call(p3, top), p0, p1, p2, p3, CONCRETE, Vector2(PAVEMENT_W * 0.5, Look.CONCRETE), 1)
	# Each side: a chamfered kerb down to the street, or (against the buildings) a face down to the pad.
	var corners_out := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
	var corners_in := [Vector2(t_lo.x, t_lo.y), Vector2(t_hi.x, t_lo.y), Vector2(t_hi.x, t_hi.y), Vector2(t_lo.x, t_hi.y)]
	var names := ["z0", "x1", "z1", "x0"]  # side k runs from corner k to k + 1
	for k in 4:
		var kerb: bool = names[k] in kerbs
		var o0: Vector2 = corners_out[k]
		var o1: Vector2 = corners_out[(k + 1) % 4]
		var i0: Vector2 = corners_in[k]
		var i1: Vector2 = corners_in[(k + 1) % 4]
		var foot := street_y if kerb else y
		var out_dir := (o0 + o1) * 0.5 - (lo + hi) * 0.5
		_quad(map.call(i0, top), map.call(i1, top), map.call(o1, foot), map.call(o0, foot), i0, i1, o1, o0, KERB, Vector2(PAVEMENT_W * 0.5, Look.CONCRETE), 1,
			Vector3(sx * out_dir.x, 0.0, sz * out_dir.y))


# --- Primitives ------------------------------------------------------------------------------

## A quad a-b-c-d (in order round it) as two triangles.
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, colour: Color, look: Vector2, solid: int, out := Vector3.ZERO) -> void:
	_tri(a, b, c, ua, ub, uc, colour, look, solid, out)
	_tri(a, c, d, ua, uc, ud, colour, look, solid, out)


## A triangle, wound to face up (or toward `out` when it stands near upright), into its tile:
## drawn (with a display) and, `solid` 1 hard or 2 soft, in the collision.
func _tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, colour: Color, look: Vector2, solid: int, out := Vector3.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var facing := n.dot(out) if out != Vector3.ZERO and absf(n.normalized().y) < 0.2 else n.y
	if facing < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	var centre := (a + b + c) / 3.0
	var key := Vector2i(floori(centre.x / TILE_M), floori(centre.z / TILE_M))
	if key != _b_key:
		_flush()
		_b_key = key
	if solid == 1:
		_b_hard.append(a)
		_b_hard.append(b)
		_b_hard.append(c)
	elif solid == 2:
		_b_soft.append(a)
		_b_soft.append(b)
		_b_soft.append(c)
	if not _visual:
		return
	var nn := n.normalized()
	for k in 3:
		_b_n.append(nn)
		_b_c.append(colour)
		_b_uv2.append(look)
	_b_v.append(a)
	_b_v.append(b)
	_b_v.append(c)
	_b_uv.append(ua)
	_b_uv.append(ub)
	_b_uv.append(uc)
