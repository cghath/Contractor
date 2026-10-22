class_name ZoneBridges
extends Node3D
## The ways across a zone's water (ZoneWater.crossings; queue item 1.1 of docs/cg_brief.md):
## - Bridges where a road crosses a river: CONCRETE (spans of up to 14 m on piers, parapets) or
##   steel TRUSS (spans of up to 32 m between two trusses), and FOOT bridges (timber, rails) where
##   ZoneWater adds a crossing to a long stretch without one. Real collision: vehicles drive over
##   them (Vehicle's wheels and hull see layer 1), soldiers walk them, rounds stop on them, the
##   AI's navigation runs over them (nav_faces_in, ZoneNav).
## - Fords: the river shallows and widens (ZoneWater shapes it), depth posts on each bank.
## - Culverts: the road on an embankment over a stream (ZoneWater raises the ground), a pipe
##   through it with a headwall at each end.
## Built the same on every peer from the zone's seed (setup). A bridge loses a span to a big
## enough blast: every blast in the zone comes here (ZoneLevel.server_blast, the host: the
## demolition block's, fire support's HE, a VBIED, a launcher's round), and does a span
## carve_radius^3 of damage, in full on or right beside it, nothing past
## FALLOFF_R_MULT x radius + FALLOFF_M; a span out of health drops into the river (its pivot end
## stays on its abutment, a middle span falls flat) and the navigation round it is baked again.
## Blasts smaller than MIN_BLAST_M (grenades, breaching shells, claymores) only chip. The host
## sends a drop to every peer (_client_drop), a late joiner asks for them all (_ask_all), and
## every span's health goes in the zone save (to_save, GameState.bridges). Numbers Proposed.

const CONCRETE := "concrete"
const TRUSS := "truss"
const FOOT := "foot"
const FORD := "ford"
const CULVERT := "culvert"
const GROUP := &"zone_bridges"

## Per bridge type (Proposed): deck width and thickness (m), the longest span, a span's health
## (in carve_radius^3 units: a demo block, carve 1.8 m, does 5.8 on contact; a 105 mm HE round,
## 1.15 m, 1.5; an 82 mm mortar round 0.33), the parapet or rail height, the truss height, colours.
const TYPES := {
	CONCRETE: {"name": "concrete bridge", "deck_w": 7.4, "deck_t": 0.75, "max_span": 14.0, "hp": 12.0, "rail_h": 0.95, "rail_t": 0.32,
		"colour": "8e8b83", "dark": "6d6a63"},
	TRUSS: {"name": "steel truss bridge", "deck_w": 6.6, "deck_t": 0.45, "max_span": 32.0, "hp": 8.0, "rail_h": 0.0, "truss_h": 5.2,
		"colour": "4f5d5a", "dark": "3b4442", "deck": "6c6a64"},
	FOOT: {"name": "footbridge", "deck_w": 1.9, "deck_t": 0.18, "max_span": 24.0, "hp": 2.0, "rail_h": 1.05, "rail_t": 0.08,
		"colour": "7b5b3c", "dark": "5a4230"},
}
## A blast smaller than this (carve radius, m) does a bridge no damage worth counting.
const MIN_BLAST_M := 0.5
## Full damage out to radius x FALLOFF_NEAR_MULT + FALLOFF_NEAR_M from a span, none past
## radius x FALLOFF_R_MULT + FALLOFF_M.
const FALLOFF_NEAR_MULT := 0.5
const FALLOFF_NEAR_M := 0.6
const FALLOFF_R_MULT := 2.5
const FALLOFF_M := 1.5
## A bridge's deck reaches this far (m) past the river's banks, and stands at least
## CLEARANCE_M over the water.
const END_M := 3.0
const CLEARANCE_M := 1.0
## A deck crosses a river at no more skew than this (the sine of the angle): a road nearly along
## the river gets a long, square-ish bridge.
const MIN_SIN := 0.5
## Ramps from a deck's end down to lower ground (m long).
const RAMP_M := 4.0
## A truss bridge's panels (m), and how far the trusses stand out from the deck's edge.
const TRUSS_PANEL_M := 4.0
## Deck tiles across and along (m): the voxel look of the deck's top.
const TILE_M := 1.0
const COLLISION_LAYER := 1
## A ford's track: scatter keeps off it this far (m) up each bank past the water, this wide each
## side of its line.
const FORD_TRACK_M := 30.0
const FORD_TRACK_HALF_W_M := 4.0

var water: ZoneWater
## Every bridge: {"id", "type", "xform" (Transform3D: origin at the middle of the deck's top, z
## along the road), "length", "water", "bed", "spans": [{"z0", "z1", "hp", "down"}], "piers":
## [z], "ramps": [[z_from, z_to, drop]]}.
var bridges: Array = []
## Culverts: {"id", "pos" (Vector3: the pipe's middle), "dir" (Vector2: the stream), "half_len",
## "top"}; fords: {"id", "pos" (Vector3), "dir" (Vector2: the way across), "half"}.
var culverts: Array = []
var fords: Array = []
## Every span's node pair while it stands ("<bridge>_<span>" -> StaticBody3D), the fallen ones'.
var _bodies := {}
var _meshes := {}
## What the scatter keeps off (_plan_keep_off).
var _keep_off: Array = []
var _collision_built := false
var _visuals_built := false
var _material: StandardMaterial3D


## Lays out the bridges, culverts and fords from `w`'s crossings (after the ground is carved).
func setup(w: ZoneWater) -> void:
	water = w
	add_to_group(GROUP)
	for c: Dictionary in w.crossings:
		var b: Dictionary = w.bodies[int(c.body)]
		var u := float(c.u)
		var k := clampi(floori(u), 0, (b.pts as PackedVector2Array).size() - 2)
		var f := u - k
		var level := lerpf((b.w as PackedFloat32Array)[k], (b.w as PackedFloat32Array)[k + 1], f)
		var half := lerpf((b.half as PackedFloat32Array)[k], (b.half as PackedFloat32Array)[k + 1], f)
		var bank_w := lerpf((b.bank_w as PackedFloat32Array)[k], (b.bank_w as PackedFloat32Array)[k + 1], f)
		var depth := lerpf((b.depth as PackedFloat32Array)[k], (b.depth as PackedFloat32Array)[k + 1], f)
		var pos: Vector2 = c.pos
		var road: Vector2 = c.dir
		var flow := ZoneWater.tangent(b, u)
		var s := maxf(absf(road.cross(flow)), MIN_SIN)
		match String(c.kind):
			CONCRETE, TRUSS, FOOT:
				bridges.append(_layout(String(c.id), String(c.kind), pos, road, (half + bank_w + END_M) / s, level, level - depth).merged({"role": String(c.get("role", ""))}))  # an operation's "msr" bridge (OperationGen; F-item)
			CULVERT:
				var reach := (ZoneWater.ROAD_HALF_M + (float(c.get("top", level + 1.4)) - (level - depth)) * ZoneWater.EMBANK_RUN) / s
				culverts.append({"id": c.id, "pos": Vector3(pos.x, level - depth * 0.5, pos.y), "dir": flow, "half_len": reach, "top": float(c.get("top", level + 1.4)), "water": level})
			FORD:
				fords.append({"id": c.id, "pos": Vector3(pos.x, level, pos.y), "dir": road, "half": (half + bank_w * 0.5) / s})
	_plan_keep_off()


## One bridge of `type` across the water at `pos`, along `road`, `reach` m to each end.
func _layout(id: String, type: String, pos: Vector2, road: Vector2, reach: float, level: float, bed: float) -> Dictionary:
	var spec: Dictionary = TYPES[type]
	var t := water.terrain
	var a := pos - road * reach
	var e := pos + road * reach
	var top := maxf(maxf(t.height_at(a.x, a.y), t.height_at(e.x, e.y)) + 0.05, level + CLEARANCE_M + float(spec.deck_t))
	var z_axis := Vector3(road.x, 0.0, road.y)
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var xform := Transform3D(Basis(x_axis, Vector3.UP, z_axis), Vector3(pos.x, top, pos.y))
	var length := reach * 2.0
	var n := maxi(ceili(length / float(spec.max_span)), 1)
	var spans: Array = []
	var piers: Array = []
	for k in n:
		var z0 := -reach + k * length / n
		var z1 := -reach + (k + 1) * length / n
		spans.append({"z0": z0, "z1": z1, "hp": float(spec.hp), "down": false})
		if k > 0:
			piers.append(z0)
	var ramps: Array = []
	for side: float in [-1.0, 1.0]:
		var end := pos + road * reach * side
		var beyond := pos + road * (reach + RAMP_M) * side
		var drop := top - t.height_at(beyond.x, beyond.y)
		if t.height_at(end.x, end.y) < top - 0.08 or drop > 0.08:
			ramps.append([reach * side, (reach + RAMP_M) * side, clampf(drop + 0.1, 0.1, 2.5)])
	return {"id": id, "type": type, "xform": xform, "length": length, "water": level, "bed": bed, "spans": spans, "piers": piers, "ramps": ramps}


## Whether `p` (x, z) is on a bridge, a culvert's way or a ford's track (scatter keeps off).
func covers(p: Vector2) -> bool:
	for r: Array in _keep_off:
		var v: Vector2 = p - (r[0] as Vector2)
		var along: Vector2 = r[1]
		if absf(v.dot(along)) <= float(r[2]) and absf(v.x * -along.y + v.y * along.x) <= float(r[3]):
			return true
	return false


## The ground the scatter keeps off, as boxes [centre, along (unit), half length, half width]:
## each bridge and its ramps, each culvert's embankment, each ford's track.
func _plan_keep_off() -> void:
	_keep_off.clear()
	for b: Dictionary in bridges:
		var xf: Transform3D = b.xform
		var along := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
		_keep_off.append([Vector2(xf.origin.x, xf.origin.z), along, float(b.length) * 0.5 + RAMP_M + 1.0, float(TYPES[b.type].deck_w) * 0.5 + 2.0])
	for c: Dictionary in culverts:
		var at: Vector3 = c.pos
		var d: Vector2 = c.dir
		_keep_off.append([Vector2(at.x, at.z), d, float(c.half_len) + 2.0, ZoneWater.ROAD_HALF_M + 4.0])
	for f: Dictionary in fords:
		var at: Vector3 = f.pos
		_keep_off.append([Vector2(at.x, at.z), f.dir, float(f.half) + FORD_TRACK_M, FORD_TRACK_HALF_W_M])


func _ready() -> void:
	if not multiplayer.is_server():
		(func() -> void: _ask_all.rpc_id(1)).call_deferred()


# --- Collision ------------------------------------------------------------------------------

## Every bridge's spans, abutments, piers and ramps, and the culverts' headwalls, as static
## bodies (layer 1: the world).
func build_collision() -> void:
	if _collision_built:
		return
	_collision_built = true
	for bi in bridges.size():
		var b: Dictionary = bridges[bi]
		var base := _static("BridgeBase_%s" % b.id)
		for part: Array in _base_parts(b):
			_add_shape(base, part[0], part[1])
		add_child(base)
		for k in (b.spans as Array).size():
			var span: Dictionary = b.spans[k]
			if span.down:
				_fallen_body(bi, k)
				continue
			var body := _static("Span_%s_%d" % [b.id, k])
			for part: Array in _span_parts(b, k):
				_add_shape(body, part[0], part[1])
			add_child(body)
			_bodies["%s_%d" % [b.id, k]] = body
	for c: Dictionary in culverts:
		var body := _static("Culvert_%s" % c.id)
		for part: Array in _culvert_parts(c):
			_add_shape(body, part[0], part[1])
		add_child(body)


func _static(node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	return body


func _add_shape(body: StaticBody3D, xform: Transform3D, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var node := CollisionShape3D.new()
	node.shape = box
	node.transform = xform
	body.add_child(node)


## A box's place in the bridge's frame: centre `c`, size `s` (no turn).
static func _at(xf: Transform3D, c: Vector3) -> Transform3D:
	return Transform3D(xf.basis, xf * c)


## Span `k` of bridge `b` as boxes: [world transform of the box's centre, size].
func _span_parts(b: Dictionary, k: int) -> Array:
	var spec: Dictionary = TYPES[b.type]
	var xf: Transform3D = b.xform
	var span: Dictionary = b.spans[k]
	var z0 := float(span.z0)
	var z1 := float(span.z1)
	var len_z := z1 - z0
	var zc := (z0 + z1) * 0.5
	var dw := float(spec.deck_w)
	var dt := float(spec.deck_t)
	var out: Array = [[_at(xf, Vector3(0, -dt * 0.5, zc)), Vector3(dw, dt, len_z)]]
	match String(b.type):
		CONCRETE:
			var rh := float(spec.rail_h)
			var rt := float(spec.rail_t)
			for side: float in [-1.0, 1.0]:
				out.append([_at(xf, Vector3(side * (dw * 0.5 - rt * 0.5), rh * 0.5, zc)), Vector3(rt, rh, len_z)])
		FOOT:
			var rh := float(spec.rail_h)
			for side: float in [-1.0, 1.0]:
				out.append([_at(xf, Vector3(side * (dw * 0.5 - 0.05), rh, zc)), Vector3(0.1, 0.1, len_z)])  # the top rail
				var posts := maxi(ceili(len_z / 2.0), 1)
				for p in posts + 1:
					out.append([_at(xf, Vector3(side * (dw * 0.5 - 0.05), rh * 0.5, z0 + p * len_z / posts)), Vector3(0.1, rh, 0.1)])
		TRUSS:
			var th := float(spec.truss_h)
			for side: float in [-1.0, 1.0]:
				var x := side * (dw * 0.5 + 0.2)
				out.append([_at(xf, Vector3(x, 0.25, zc)), Vector3(0.36, 0.5, len_z)])  # bottom chord
				out.append([_at(xf, Vector3(x, th, zc)), Vector3(0.36, 0.4, len_z)])  # top chord
				var panels := maxi(roundi(len_z / TRUSS_PANEL_M), 1)
				var pl := len_z / panels
				for p in panels + 1:
					out.append([_at(xf, Vector3(x, th * 0.5, z0 + p * pl)), Vector3(0.3, th, 0.3)])
				for p in panels:
					# A diagonal across each panel, leaning toward the span's middle.
					var za := z0 + p * pl
					var zb := za + pl
					var down_at_end := (za + zb) * 0.5 < zc
					var lo := Vector3(x, 0.4, za if down_at_end else zb)
					var hi := Vector3(x, th - 0.2, zb if down_at_end else za)
					var mid := (lo + hi) * 0.5
					var axis := (hi - lo)
					var basis := Basis(Vector3.RIGHT, atan2(axis.z, axis.y))
					out.append([Transform3D(xf.basis * basis, xf * mid), Vector3(0.22, axis.length(), 0.22)])
			var braces := maxi(roundi(len_z / (TRUSS_PANEL_M * 2.0)), 1)
			for p in braces + 1:
				out.append([_at(xf, Vector3(0, th, z0 + p * len_z / braces)), Vector3(dw + 0.4, 0.3, 0.3)])
	return out


## Bridge `b`'s abutments, piers and ramps (they stay when its spans go).
func _base_parts(b: Dictionary) -> Array:
	var spec: Dictionary = TYPES[b.type]
	var xf: Transform3D = b.xform
	var dw := float(spec.deck_w)
	var dt := float(spec.deck_t)
	var top := xf.origin.y
	var bed := float(b.bed)
	var half := float(b.length) * 0.5
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		var h := maxf(top - dt - (bed - 0.5), 1.0)
		out.append([_at(xf, Vector3(0, -dt - h * 0.5 + 0.02, side * (half - 1.0))), Vector3(dw + 0.6, h, 2.0)])
	var pier_w := 1.3 if String(b.type) != FOOT else 0.35
	for z: float in b.piers:
		var h := maxf(top - dt - (bed - 0.5), 1.0)
		out.append([_at(xf, Vector3(0, -dt - h * 0.5, z)), Vector3(dw * (0.82 if String(b.type) != FOOT else 1.0), h, pier_w)])
	for r: Array in b.ramps:
		var z_from := float(r[0])
		var z_to := float(r[1])
		var drop := float(r[2])
		var run := absf(z_to - z_from)
		var slope := atan2(drop, run)
		var mid := Vector3(0, -drop * 0.5 - 0.15, (z_from + z_to) * 0.5)
		var tilt := Basis(Vector3.RIGHT, slope * signf(z_to - z_from))
		out.append([Transform3D(xf.basis * tilt, xf * mid), Vector3(minf(dw, 7.4), 0.3, sqrt(run * run + drop * drop) + 0.4)])
	return out


## A culvert's headwalls: a low concrete wall across the stream at each end of the pipe.
func _culvert_parts(c: Dictionary) -> Array:
	var d: Vector2 = c.dir
	var z_axis := Vector3(d.x, 0.0, d.y)
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var at: Vector3 = c.pos
	var xf := Transform3D(Basis(x_axis, Vector3.UP, z_axis), at)
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		out.append([_at(xf, Vector3(0, 0.6, side * float(c.half_len))), Vector3(3.6, 2.0, 0.4)])
	return out


# --- Looks ----------------------------------------------------------------------------------

## Every span, abutment, pier, ramp, headwall and ford post as blocky meshes (the voxel look:
## flat shaded boxes, the deck's top in TILE_M tiles a shade apart). Not on a headless server.
func build_visuals() -> void:
	if _visuals_built:
		return
	_visuals_built = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.95
	for bi in bridges.size():
		var b: Dictionary = bridges[bi]
		var base := _mesh_node("BridgeBaseLook_%s" % b.id, _parts_mesh(_base_parts(b), Color(String(TYPES[b.type].get("dark", "6d6a63"))), 0))
		add_child(base)
		for k in (b.spans as Array).size():
			_build_span_look(bi, k)
	for c: Dictionary in culverts:
		add_child(_mesh_node("CulvertLook_%s" % c.id, _culvert_mesh(c)))
	for f: Dictionary in fords:
		add_child(_mesh_node("FordLook_%s" % f.id, _ford_mesh(f)))


func _build_span_look(bi: int, k: int) -> void:
	var b: Dictionary = bridges[bi]
	var key := "%s_%d" % [b.id, k]
	if _meshes.has(key):
		(_meshes[key] as Node).queue_free()
	var spec: Dictionary = TYPES[b.type]
	var mesh := _parts_mesh(_span_parts(b, k), Color(String(spec.colour)), hash(key))
	_add_deck_tiles(mesh, b, k)
	var node := _mesh_node("SpanLook_%s" % key, mesh)
	if (b.spans[k] as Dictionary).down:
		node.transform = fallen_xform(bi, k) * (b.xform as Transform3D).affine_inverse()
	add_child(node)
	_meshes[key] = node


func _mesh_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = _material
	return node


## Boxes [world transform, size] as one flat-shaded mesh in `colour`, each box a shade apart
## (seeded by `seed`), lighter on top.
func _parts_mesh(parts: Array, colour: Color, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for part: Array in parts:
		var shade := colour.darkened(rng.randf() * 0.08).lightened(rng.randf() * 0.05)
		add_box(st, part[0], part[1], shade)
	return st.commit()


## A box (centre and turn `xf`, `size`) to `st`, flat shaded: top lit, sides a shade darker,
## underneath darker still.
static func add_box(st: SurfaceTool, xf: Transform3D, size: Vector3, colour: Color) -> void:
	var c := _corners(xf, size)
	var shades := [1.0, 0.62, 0.9, 0.9, 0.84, 0.84]
	var quads := _QUADS
	for q in quads.size():
		var quad: Array = quads[q]
		var shade := float(shades[q])
		var tint := Color(colour.r * shade, colour.g * shade, colour.b * shade)
		var v: Array[Vector3] = [c[quad[0]], c[quad[1]], c[quad[2]], c[quad[3]]]
		var n := (xf.basis * _NORMALS[q]).normalized()
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(tint)
			st.set_normal(n)
			st.add_vertex(v[idx])


## A box's corners: bottom (y-) 0..3 then top 4..7, each ring (x-, z-), (x+, z-), (x+, z+), (x-, z+)
## (NavBuilder._box_faces' order).
static func _corners(xf: Transform3D, size: Vector3) -> Array[Vector3]:
	var h := size * 0.5
	var out: Array[Vector3] = []
	for y: float in [-h.y, h.y]:
		for v: Vector2 in [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]:
			out.append(xf * Vector3(v.x, y, v.y))
	return out


## The six faces' corners, wound as the terrain's and NavBuilder's (front faces, Godot's winding),
## top, bottom, -z, +z, +x, -x, and their normals.
const _QUADS := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
const _NORMALS: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]


## The deck's top in TILE_M tiles a shade apart, a hair over the deck (the voxel look); a truss
## bridge's deck is concrete between its steel.
func _add_deck_tiles(mesh: ArrayMesh, b: Dictionary, k: int) -> void:
	var spec: Dictionary = TYPES[b.type]
	var span: Dictionary = b.spans[k]
	var xf: Transform3D = b.xform
	var base := Color(String(spec.get("deck", spec.colour)))
	var dw := float(spec.deck_w) - (2.0 * float(spec.get("rail_t", 0.0)) if String(b.type) == CONCRETE else 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := maxi(roundi(dw / TILE_M), 1)
	var tile_x := dw / across
	var z0 := float(span.z0)
	var z1 := float(span.z1)
	var along := maxi(roundi((z1 - z0) / (TILE_M if String(b.type) != FOOT else 0.3)), 1)
	var tile_z := (z1 - z0) / along
	var n := xf.basis.y.normalized()
	for a in across:
		for c in along:
			var x0 := -dw * 0.5 + a * tile_x
			var zz := z0 + c * tile_z
			var roll := float(absi(hash(Vector3i(a, c, k + String(b.id).hash()))) % 1000) / 1000.0
			var colour := base.darkened(roll * 0.1).lightened(0.04 if (a + c) % 2 == 0 else 0.0)
			var g := 0.03 if String(b.type) == FOOT else 0.015  # the gaps between planks or slabs
			var corners := [Vector3(x0 + g, 0.012, zz + g), Vector3(x0 + tile_x - g, 0.012, zz + g), Vector3(x0 + tile_x - g, 0.012, zz + tile_z - g), Vector3(x0 + g, 0.012, zz + tile_z - g)]
			for idx: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(colour)
				st.set_normal(n)
				st.add_vertex(xf * (corners[idx] as Vector3))
	st.commit(mesh)


func _culvert_mesh(c: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in _culvert_parts(c):
		add_box(st, part[0], part[1], Color("8a877f"))
	# The pipe's dark mouth at each end, and its ring.
	var d: Vector2 = c.dir
	var z_axis := Vector3(d.x, 0.0, d.y)
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var at: Vector3 = c.pos
	var xf := Transform3D(Basis(x_axis, Vector3.UP, z_axis), at)
	for side: float in [-1.0, 1.0]:
		var z := side * (float(c.half_len) + 0.21)
		add_box(st, ZoneBridges._at(xf, Vector3(0, 0.35, z)), Vector3(1.1, 1.1, 0.02), Color("1d1f1f"))
		for k in 8:
			var a := k * TAU / 8.0
			var ring := Vector3(cos(a) * 0.62, 0.35 + sin(a) * 0.62, z)
			add_box(st, Transform3D(xf.basis * Basis(Vector3.BACK, a), xf * ring), Vector3(0.18, 0.5, 0.06), Color("a29f96"))
	return st.commit()


## A ford's depth posts: two on each bank either side of the way, white with red bands.
func _ford_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d: Vector2 = f.dir
	var side := Vector2(-d.y, d.x)
	var t := water.terrain
	var at: Vector3 = f.pos
	for end: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			var p := Vector2(at.x, at.z) + d * end * (float(f.half) + 1.0) + side * s * 3.5
			var g := t.height_at(p.x, p.y)
			for band in 4:
				var colour := Color("e8e4dc") if band % 2 == 0 else Color("b23a2e")
				add_box(st, Transform3D(Basis(), Vector3(p.x, g + 0.2 + band * 0.4, p.y)), Vector3(0.12, 0.4, 0.12), colour)
	return st.commit()


# --- Navigation -----------------------------------------------------------------------------

## The faces of every standing span, abutment and ramp whose bridge reaches into `area`.
func nav_faces_in(area: Rect2) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for b: Dictionary in bridges:
		if not _rect_of(b).intersects(area):
			continue
		var parts := _base_parts(b)
		for k in (b.spans as Array).size():
			if not (b.spans[k] as Dictionary).down:
				parts.append_array(_nav_span_parts(b, k))
		for part: Array in parts:
			faces.append_array(_box_faces(part[0], part[1]))
	return faces


## Span `k` as the navigation sees it: its deck, and a low wall along each edge (parapet, rail
## or truss: nobody walks off the side).
func _nav_span_parts(b: Dictionary, k: int) -> Array:
	var spec: Dictionary = TYPES[b.type]
	var xf: Transform3D = b.xform
	var span: Dictionary = b.spans[k]
	var zc := (float(span.z0) + float(span.z1)) * 0.5
	var len_z := float(span.z1) - float(span.z0)
	var dw := float(spec.deck_w)
	var dt := float(spec.deck_t)
	var out: Array = [[_at(xf, Vector3(0, -dt * 0.5, zc)), Vector3(dw, dt, len_z)]]
	for side: float in [-1.0, 1.0]:
		out.append([_at(xf, Vector3(side * (dw * 0.5 - 0.15), 0.5, zc)), Vector3(0.3, 1.0, len_z)])
	return out


func _rect_of(b: Dictionary) -> Rect2:
	var xf: Transform3D = b.xform
	var reach := float(b.length) * 0.5 + RAMP_M + 1.0
	var r := Rect2(Vector2(xf.origin.x, xf.origin.z), Vector2.ZERO)
	for c: Vector3 in [Vector3(-6, 0, -reach), Vector3(6, 0, -reach), Vector3(6, 0, reach), Vector3(-6, 0, reach)]:
		var w := xf * c
		r = r.expand(Vector2(w.x, w.z))
	return r


## A box's twelve triangles, facing out (the navigation bake's faces).
static func _box_faces(xf: Transform3D, size: Vector3) -> PackedVector3Array:
	var c := _corners(xf, size)
	var out := PackedVector3Array()
	for q: Array in _QUADS:
		out.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return out


# --- Damage (host) --------------------------------------------------------------------------

## Host: a blast of carve radius `radius_m` at `pos`: every span it reaches takes radius^3, in
## full close to it and fading out (FALLOFF_*); a span out of health drops.
func server_blast(pos: Vector3, radius_m: float) -> void:
	if radius_m < MIN_BLAST_M or not multiplayer.is_server():
		return
	var full := radius_m * radius_m * radius_m
	var near := radius_m * FALLOFF_NEAR_MULT + FALLOFF_NEAR_M
	var far := radius_m * FALLOFF_R_MULT + FALLOFF_M
	for bi in bridges.size():
		var b: Dictionary = bridges[bi]
		var xf: Transform3D = b.xform
		if Vector2(pos.x - xf.origin.x, pos.z - xf.origin.z).length() > float(b.length) * 0.5 + far + 2.0:
			continue
		var local := xf.affine_inverse() * pos
		var spec: Dictionary = TYPES[b.type]
		var top := maxf(float(spec.get("truss_h", 0.0)), float(spec.get("rail_h", 0.0)))
		for k in (b.spans as Array).size():
			var span: Dictionary = b.spans[k]
			if span.down:
				continue
			var lo := Vector3(-float(spec.deck_w) * 0.5 - 0.3, -float(spec.deck_t), float(span.z0))
			var hi := Vector3(float(spec.deck_w) * 0.5 + 0.3, top, float(span.z1))
			var d := (local.clamp(lo, hi) - local).length()
			var hit := full * (1.0 - smoothstep(near, far, d))
			if hit <= 0.0:
				continue
			span.hp = float(span.hp) - hit
			print("[bridges] %s span %d: blast %.2f m at %.1f m, %.2f damage, %.2f left" % [b.id, k, radius_m, d, hit, float(span.hp)])
			if float(span.hp) <= 0.0:
				_client_drop.rpc(bi, k)


## Every peer: span `k` of bridge `bi` drops (its collision goes, it lies fallen in the river).
@rpc("authority", "call_local", "reliable")
func _client_drop(bi: int, k: int) -> void:
	if bi < 0 or bi >= bridges.size() or k < 0 or k >= (bridges[bi].spans as Array).size():
		return
	var b: Dictionary = bridges[bi]
	var span: Dictionary = b.spans[k]
	if span.down:
		return
	span.down = true
	span.hp = minf(float(span.hp), 0.0)
	var key := "%s_%d" % [b.id, k]
	if _bodies.has(key):
		(_bodies[key] as Node).queue_free()
		_bodies.erase(key)
	if _collision_built:
		_fallen_body(bi, k)
	if _visuals_built:
		_build_span_look(bi, k)
	print("[bridges] %s (%s): span %d of %d is down" % [b.id, TYPES[b.type].name, k + 1, (b.spans as Array).size()])
	if is_inside_tree() and multiplayer.is_server():
		var lvl := CompoundLevel.current(self)
		var nav: Variant = lvl.get(&"nav") if lvl else null
		if nav is ZoneNav:
			(nav as ZoneNav).rebake_rect(_rect_of(b))


## Where fallen span `k` of bridge `bi` lies (the transform of the bridge's frame for it): an
## end span hangs from its abutment with its other end on the riverbed, a middle span lies flat
## on the bed.
func fallen_xform(bi: int, k: int) -> Transform3D:
	var b: Dictionary = bridges[bi]
	var xf: Transform3D = b.xform
	var span: Dictionary = b.spans[k]
	var n := (b.spans as Array).size()
	var t := water.terrain
	var dt := float(TYPES[b.type].deck_t)
	var z0 := float(span.z0)
	var z1 := float(span.z1)
	var pivot := 0.0
	if k == 0 and n > 1:
		pivot = z0
	elif k == n - 1 and n > 1:
		pivot = z1
	elif n == 1:
		pivot = z0 if absi(hash(String(b.id))) % 2 == 0 else z1
	else:
		# A middle span: down flat onto the bed, rolled a little.
		var mid := xf * Vector3(0, 0, (z0 + z1) * 0.5)
		var drop := xf.origin.y - (t.height_at(mid.x, mid.z) + dt)
		return Transform3D(xf.basis * Basis(Vector3.BACK, 0.12), xf.origin + Vector3.DOWN * maxf(drop, 0.5))
	var far := z1 if pivot == z0 else z0
	var far_w := xf * Vector3(0, 0, far)
	var drop := xf.origin.y - t.height_at(far_w.x, far_w.z) + 0.2
	var arm := absf(far - pivot)
	var angle := asin(clampf(drop / maxf(arm, 0.1), 0.05, 0.9)) * signf(far - pivot)
	var to_pivot := Transform3D(Basis(), Vector3(0, 0, pivot))
	var local := to_pivot * Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO) * to_pivot.affine_inverse()
	return xf * local


func _fallen_body(bi: int, k: int) -> void:
	var b: Dictionary = bridges[bi]
	var key := "%s_%d" % [b.id, k]
	var body := _static("Fallen_%s" % key)
	var span: Dictionary = b.spans[k]
	var spec: Dictionary = TYPES[b.type]
	var fxf := fallen_xform(bi, k)
	var dt := float(spec.deck_t)
	_add_shape(body, Transform3D(fxf.basis, fxf * Vector3(0, -dt * 0.5, (float(span.z0) + float(span.z1)) * 0.5)), Vector3(float(spec.deck_w), dt, float(span.z1) - float(span.z0)))
	add_child(body)


## Whether span `k` of bridge `bi` is down.
func is_down(bi: int, k: int) -> bool:
	return bool((bridges[bi].spans[k] as Dictionary).down)


## The bridges standing whole (no span down).
func standing() -> int:
	return bridges.filter(func(b: Dictionary) -> bool: return (b.spans as Array).all(func(s: Dictionary) -> bool: return not s.down)).size()


# --- Late joiners and saves -----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	_client_state.rpc_id(multiplayer.get_remote_sender_id(), _downs())


@rpc("authority", "call_remote", "reliable")
func _client_state(downs: Array) -> void:
	for d: Array in downs:
		_client_drop(int(d[0]), int(d[1]))


func _downs() -> Array:
	var out: Array = []
	for bi in bridges.size():
		for k in (bridges[bi].spans as Array).size():
			if (bridges[bi].spans[k] as Dictionary).down:
				out.append([bi, k])
	return out


## The zone save's record (GameState.bridges): every bridge's spans' health, by bridge id.
func to_save() -> Dictionary:
	var hp := {}
	for b: Dictionary in bridges:
		hp[String(b.id)] = (b.spans as Array).map(func(s: Dictionary) -> float: return float(s.hp))
	return {"hp": hp}


## Host: the saved health back, and the spans that were down dropped again (everyone sees them).
func server_restore(saved: Dictionary) -> void:
	var hp: Dictionary = saved.get("hp", {})
	for bi in bridges.size():
		var b: Dictionary = bridges[bi]
		var list: Array = hp.get(String(b.id), [])
		for k in mini(list.size(), (b.spans as Array).size()):
			(b.spans[k] as Dictionary).hp = float(list[k])
			if float(list[k]) <= 0.0:
				_client_drop.rpc(bi, k)
