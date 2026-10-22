class_name PropArt
extends RefCounted
## The outdoor prop library (cghath's queue item 1.7, docs/cg_brief.md: "at least triple today's
## outdoor set"): street furniture, market stalls, fences and gates, power lines, farm and water
## props, scenery vehicles, shipping containers, graves, site clutter, and the animals' bodies.
## ZoneProps lays them out on a zone and ZoneScatter draws (MultiMeshes per cell, one mesh per
## shape and paint) and collides them (one convex hull per part).
##
## Each shape is a list of parts in its own metres: x across (a vehicle's length, a fence's run),
## y up from the ground at 0, z the other way (+z the front: a stall's customers, a lamp's arm, a
## sign's face). A part is a convex block: 8 corners in box order (corner k at x bit k & 1, y bit
## k & 2, z bit k & 4: boxes, wedges, bars at any angle) or 16 (an octagonal drum: two rings of 8:
## posts, wheels, tanks). The same corners are drawn and collided, so a round or a man meets the
## prop where it's drawn. A part is:
##   "pts": its corners, "c": its colour, "paint": a share of the item's paint instead (-1: none),
##   "m": its material (MATERIALS; "" the shape's own), "solid": collides; "decal": drawn only, a
##   hair off another part's face (windows, lights, stripes), so it doesn't change what's hit.
## Drawn-only parts that aren't decals (wires, a chain-link's weave, washing on a line) are things
## rounds and men go through anyway; a see-through part (material SEE_THROUGH: chain-link, barbed
## wire) stops men walking but not sight or rounds (ZoneScatter puts it on Soldier.BODY_LAYER).

## Every library type in the order zone caches store them by (append only: a cached layout keeps
## the index). Animals are drawn by ZoneAnimals; the rest are static props.
const NAMES: Array[String] = [
	# Street furniture
	"street_lamp", "lamp_double", "utility_pole", "pole_transformer", "sign_stop", "sign_warn", "sign_direction",
	"billboard", "bus_shelter", "bench", "bollard", "dumpster", "kiosk", "jersey_barrier",
	# Market
	"market_stall", "stall_canopy", "shop_awning", "produce_crates", "hand_cart",
	# Fences, walls and gates
	"fence_rail", "fence_board", "fence_chainlink", "fence_barbed", "fence_corrugated", "wall_stone", "wall_block",
	"wall_mud", "gate_farm", "gate_steel", "gate_wood",
	# Power lines
	"pylon", "power_pole_h",
	# Farm and water
	"well", "water_tower", "cistern", "trough", "hay_round", "hay_square", "irrigation_channel", "irrigation_pipe",
	"sluice_gate", "windpump", "pen_shelter",
	# Animals (ZoneAnimals)
	"goat", "sheep", "dog",
	# Scenery vehicles (static, not drivable)
	"car_sedan", "car_hatch", "van", "pickup_civ", "truck_cargo", "truck_tanker", "tractor", "hulk_car", "hulk_truck", "hulk_van",
	# Shipping containers
	"container_20", "container_40", "container_stack",
	# Graves
	"grave_mound", "headstone", "grave_cross", "tomb", "grave_stele",
	# Sites
	"generator", "sat_dish", "laundry_line", "fuel_tank", "gas_cylinders", "pallet_stack", "tyre_pile", "latrine",
]
const ANIMALS: Array[String] = ["goat", "sheep", "dog"]
## Today's outdoor set before this library (2026-10-21, claude/ai-driving 878a8de5), for the
## "tripled" check: ZoneScatter's natural shapes (8) and box props (6), and the modules' and
## buildings' outdoor dressing (11).
const BEFORE: Array[String] = [
	"rock", "scrub", "thicket", "broadleaf tree", "conifer", "grass tuft", "pebble", "rock outcrop",
	"crate stack", "drums", "debris pile", "broken wall", "car wreck (box)", "rubble mound",
	"sandbag wall", "HESCO", "watchtower", "weapons crates", "fuel drums", "AA emplacement", "compound gate", "tent",
	"checkpoint barrier", "guard booth", "radio mast",
]

## How each material takes a round (Ballistics via ZoneScatter.round_through; the AI's soft-cover
## test via VoxelWorld.stops_round_in): energy (J) lost per metre of the part it crosses, INF stops
## every small-arms round. A part is solid in its hull, so a hollow thing (a car's cabin, a shipping
## container) gets a low figure for its average over its width. Proposed, against data/rounds.json
## (M855 about 1650 J at the muzzle, 9 mm about 550 J, M80 about 3350 J):
## - a car's cabin or boot ("hollow", 1.8 m): an M855 goes through with about 600 J; a 9 mm stops;
## - its engine bay, a generator, steel posts, concrete, stone: stop everything (the cover to pick);
## - a shipping container (2.4 m): an M855 through with about 500 J, a 9 mm stops;
## - a hay bale (1.2 m+): stops rifle rounds; a full water or fuel tank too; mud like VoxelWorld's;
## - wood as VoxelWorld's (a 5 cm rail costs 125 J), sheet metal as its, cloth and glass next to nothing.
const MATERIALS := {
	"wood": 2500.0, "sheet": 1500.0, "hollow": 600.0, "container": 450.0, "engine": INF, "steel": INF,
	"concrete": INF, "stone": INF, "mud": 14000.0, "earth": 12000.0, "hay": 3500.0, "water": 4000.0,
	"tyre": 3000.0, "cloth": 200.0, "glass": 300.0, "mesh": 0.0,
}
const SEE_THROUGH := "mesh"
## A decal stands this far off the face it's on (m): out of z-fighting, inside the hitbox checks.
const DECAL_IN := 0.002
const DECAL_OUT := 0.006
## The six faces of a box-ordered part (corner indices, as ZoneScatter._add_box).
const QUADS := [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]
## Draw distances (m): by default, and for the big ones seen from far.
const SEE_M := 520.0
const SEE_SMALL_M := 260.0
const SEE_BIG_M := 1400.0
## Parts starting this high (m) are overhead: not in a shape's footprint (foot).
const FOOT_TOP_M := 2.2

# Colours.
const STEEL := Color("6b6f72")
const GALV := Color("8c9194")
const DARK := Color("2b2d2f")
const BLACK := Color("1c1d1e")
const TYRE := Color("242424")
const RIM := Color("5d6062")
const CONCRETE := Color("9a978f")
const WOOD := Color("6b5238")
const WOOD_OLD := Color("7d6b55")
const POLE := Color("5a4632")
const GLASS := Color("33424d")
const LAMP := Color("efe0a6")
const WHITE := Color("d8d6cf")
const RED := Color("a8261f")
const AMBER := Color("c98a2a")
const STONE := Color("8f8676")
const EARTH := Color("6b5640")
const HAY := Color("c9a85a")
const WATER := Color("39596a")
const CHAR := Color("2a2622")
const RUST := Color("7a4431")
const CERAMIC := Color("a9b5b8")

static var _shapes := {}
static var _meshes := {}


## Whether `shape` is a library type.
static func has(shape: String) -> bool:
	return shape in NAMES


static func index_of(shape: String) -> int:
	return NAMES.find(shape)


## Shape `name`: {"parts", "paints" (Array[Color]), "mat" (its parts' default material), "see"
## (draw distance m), "shadow", "wires" (where power lines hang from it, its own metres; the line
## runs along its z), "bounds" (AABB of every part), "solid_bounds" (of the solid ones)}.
static func shape(name: String) -> Dictionary:
	if not _shapes.has(name):
		var s := _build(name)
		var all := AABB()
		var solid := AABB()
		var first := true
		var first_solid := true
		for part: Dictionary in s.parts:
			for p: Vector3 in part.pts:
				all = AABB(p, Vector3.ZERO) if first else all.expand(p)
				first = false
				if part.solid:
					solid = AABB(p, Vector3.ZERO) if first_solid else solid.expand(p)
					first_solid = false
		s["bounds"] = all
		s["solid_bounds"] = solid
		# What stands on the ground: every part starting below FOOT_TOP_M (not a lamp's arm, a pylon's
		# cross arms or an awning overhead).
		var foot := AABB()
		var first_foot := true
		for part: Dictionary in s.parts:
			var low := INF
			for p: Vector3 in part.pts:
				low = minf(low, p.y)
			if low >= FOOT_TOP_M:
				continue
			for p: Vector3 in part.pts:
				foot = AABB(p, Vector3.ZERO) if first_foot else foot.expand(p)
				first_foot = false
		s["foot"] = foot if not first_foot else all
		_shapes[name] = s
	return _shapes[name]


## What shape `name` stands on the ground with (its own metres): the box of its parts that start
## below FOOT_TOP_M (placement keeps these apart; things overhead don't).
static func foot(name: String) -> AABB:
	return shape(name).foot


static func parts(name: String) -> Array:
	return shape(name).parts


static func paints(name: String) -> Array:
	return shape(name).paints


## The material part `part` of shape `name` takes rounds as.
static func material_of(name: String, part: Dictionary) -> String:
	var m := String(part.get("m", ""))
	return m if m != "" else String(shape(name).mat)


## Energy a round loses per metre of `material` (INF: stops it); unknown materials stop rounds.
static func loss_per_m(material: String) -> float:
	return float(MATERIALS.get(material, INF))


static func see_m(name: String) -> float:
	return float(shape(name).see)


## Half the footprint (x, z) of shape `name` (every part), in its own metres about its origin.
static func half_extents(name: String) -> Vector2:
	var b: AABB = shape(name).bounds
	return Vector2(maxf(absf(b.position.x), absf(b.end.x)), maxf(absf(b.position.z), absf(b.end.z)))


static func wire_points(name: String) -> PackedVector3Array:
	return shape(name).get("wires", PackedVector3Array())


## The faces of `part` as polygons (in order round each): 6 quads for a box-ordered part, 8 sides
## and two octagonal caps for a drum.
static func faces(part: Dictionary) -> Array:
	var p: PackedVector3Array = part.pts
	var out: Array = []
	if p.size() == 8:
		for q: Array in QUADS:
			out.append(PackedVector3Array([p[q[0]], p[q[1]], p[q[2]], p[q[3]]]))
		return out
	for i in 8:
		var j := (i + 1) % 8
		out.append(PackedVector3Array([p[i], p[j], p[8 + j], p[8 + i]]))
	out.append(p.slice(0, 8))
	out.append(p.slice(8, 16))
	return out


## Where the line `from` + t `dir` is inside `part` (a convex block): Vector2(t in, t out), t in >
## t out when it misses.
static func ray_span(part: Dictionary, from: Vector3, dir: Vector3) -> Vector2:
	var centre := _centre(part.pts)
	var t0 := -INF
	var t1 := INF
	for poly: PackedVector3Array in faces(part):
		var n := _normal(poly)
		if n == Vector3.ZERO:
			continue
		if n.dot(poly[0] - centre) < 0.0:
			n = -n
		var denom := n.dot(dir)
		var dist := n.dot(poly[0] - from)
		if absf(denom) < 1e-9:
			if dist < 0.0:
				return Vector2(1.0, -1.0)
			continue
		var t := dist / denom
		if denom < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	return Vector2(t0, t1)


## The mesh of shape `name` in paint `paint` (an index into its paints), made once a game.
static func mesh(name: String, paint: int) -> ArrayMesh:
	var key := "%s#%d" % [name, paint]
	if not _meshes.has(key):
		var s := shape(name)
		var colours: Array = s.paints
		var tint: Color = colours[clampi(paint, 0, colours.size() - 1)] if not colours.is_empty() else Color.WHITE
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: Dictionary in s.parts:
			if not bool(part.get("draw", true)):
				continue  # (a see-through part's collision panel: its weave is drawn instead)
			var c: Color = part.c
			if float(part.paint) >= 0.0:
				c = tint * float(part.paint)
			c.a = 1.0
			var centre := _centre(part.pts)
			for poly: PackedVector3Array in faces(part):
				_poly(st, poly, centre, c)
		_meshes[key] = st.commit()
	return _meshes[key]


## Every drawn triangle corner of shape `name` (three per triangle), for checks.
static func triangles(name: String, only_hit := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	for part: Dictionary in parts(name):
		if not bool(part.get("draw", true)):
			continue
		if only_hit and not (bool(part.solid) and material_of(name, part) != SEE_THROUGH) and not bool(part.get("decal", false)):
			continue
		for poly: PackedVector3Array in faces(part):
			for i in range(1, poly.size() - 1):
				out.append_array([poly[0], poly[i], poly[i + 1]])
	return out


static func _poly(st: SurfaceTool, poly: PackedVector3Array, inside: Vector3, colour: Color) -> void:
	var n := _normal(poly)
	if n == Vector3.ZERO:
		return
	var centre := _centre(poly)
	var flip := n.dot(centre - inside) < 0.0
	if flip:
		n = -n
	for i in range(1, poly.size() - 1):
		# Godot wants clockwise seen from outside.
		var order: Array = [poly[0], poly[i + 1], poly[i]] if not flip else [poly[0], poly[i], poly[i + 1]]
		for v: Vector3 in order:
			st.set_color(colour)
			st.set_normal(n)
			st.add_vertex(v)


static func _normal(poly: PackedVector3Array) -> Vector3:
	for i in range(1, poly.size() - 1):
		var n := (poly[i] - poly[0]).cross(poly[i + 1] - poly[0])
		if n.length_squared() > 1e-12:
			return n.normalized()
	return Vector3.ZERO


static func _centre(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


# --- Building blocks ---------------------------------------------------------------------------

## A part from its corners. `c`: a Color, or a float: that share of the item's paint.
static func _part(out: Array, pts: PackedVector3Array, c: Variant, m := "", solid := true, decal := false) -> void:
	out.append({"pts": pts, "c": c if c is Color else Color.WHITE, "paint": float(c) if not c is Color else -1.0, "m": m, "solid": solid, "decal": decal})


## An axis-aligned box `lo`..`hi`.
static func _box(out: Array, lo: Vector3, hi: Vector3, c: Variant, m := "", solid := true) -> void:
	var pts := PackedVector3Array()
	for k in 8:
		pts.append(Vector3(lo.x if (k & 1) == 0 else hi.x, lo.y if (k & 2) == 0 else hi.y, lo.z if (k & 4) == 0 else hi.z))
	_part(out, pts, c, m, solid)


## A drawn-only box (a decal lying on a face, or a detail inside the prop's hull).
static func _paint(out: Array, lo: Vector3, hi: Vector3, c: Variant) -> void:
	_box(out, lo, hi, c, "", false)
	out[out.size() - 1]["decal"] = true


## A block from its 8 corners in box order.
static func _hull(out: Array, pts: Array, c: Variant, m := "", solid := true) -> void:
	_part(out, PackedVector3Array(pts), c, m, solid)


## A square bar `w` thick from `a` to `b` (braces, rails, poles at an angle).
static func _bar(out: Array, a: Vector3, b: Vector3, w: float, c: Variant, m := "", solid := true) -> void:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * w * 0.5
	var v := d.cross(u).normalized() * w * 0.5
	var pts := PackedVector3Array()
	for k in 8:
		var p := a if (k & 2) == 0 else b
		pts.append(p + (u if (k & 1) != 0 else -u) + (v if (k & 4) != 0 else -v))
	_part(out, pts, c, m, solid)


## An octagonal drum of half-width `r`, `length` long, centred on `c`, along `dir`.
static func _drum(out: Array, c: Vector3, r: float, length: float, dir: Vector3, col: Variant, m := "", solid := true) -> void:
	var d := dir.normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := d.cross(u).normalized()
	var k := r * 0.7  # the 45-degree cut leaves 0.7 of each side (as ZoneScatter._octagon)
	var ring: Array[Vector2] = [Vector2(k, -r), Vector2(r, -k), Vector2(r, k), Vector2(k, r), Vector2(-k, r), Vector2(-r, k), Vector2(-r, -k), Vector2(-k, -r)]
	var pts := PackedVector3Array()
	for end: float in [-0.5, 0.5]:
		for o: Vector2 in ring:
			pts.append(c + d * length * end + u * o.x + v * o.y)
	_part(out, pts, col, m, solid)


## An upright post of half-width `r` from y0 to y1 at (x, z).
static func _post(out: Array, x: float, z: float, y0: float, y1: float, r: float, c: Variant, m := "", solid := true) -> void:
	_drum(out, Vector3(x, (y0 + y1) * 0.5, z), r, y1 - y0, Vector3.UP, c, m, solid)


## A drawn-only patch on the quad a, b, c, d (in order round it), on its side away from `inside`.
static func _decal(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Variant) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot((a + c) * 0.5 - inside) < 0.0:
		n = -n
	var q := [a, b, d, c]
	var pts := PackedVector3Array()
	for k in 8:
		pts.append((q[k & 3] as Vector3) + n * (DECAL_IN if (k & 4) == 0 else DECAL_OUT))
	_part(out, pts, col, "", false, true)


## A block with a flat bottom at y0 from x0 to x1, its top sloping from y_top0 (at x0) to y_top1
## (at x1), the top's x run inset to tx0..tx1, `hz` half wide (z) at the bottom and `tz` at the top.
static func _slab(out: Array, x0: float, x1: float, y0: float, y_top0: float, y_top1: float, tx0: float, tx1: float, hz: float, tz: float, c: Variant, m := "") -> void:
	var pts: Array = []
	for k in 8:
		var top := (k & 2) != 0
		var front := (k & 1) != 0
		var x := (tx1 if front else tx0) if top else (x1 if front else x0)
		var y := (y_top1 if front else y_top0) if top else y0
		var zz := (tz if top else hz) * (1.0 if (k & 4) != 0 else -1.0)
		pts.append(Vector3(x, y, zz))
	_hull(out, pts, c, m)


static func _make(parts_list: Array, paint_list: Array, mat: String, see := SEE_M, wires := PackedVector3Array(), shadow := true) -> Dictionary:
	var colours: Array[Color] = []
	for p: Variant in paint_list:
		colours.append(p if p is Color else Color(String(p)))
	return {"parts": parts_list, "paints": colours, "mat": mat, "see": see, "wires": wires, "shadow": shadow}


static func _build(name: String) -> Dictionary:
	match name:
		"street_lamp": return _street_lamp(false)
		"lamp_double": return _street_lamp(true)
		"utility_pole": return _utility_pole(false)
		"pole_transformer": return _utility_pole(true)
		"sign_stop": return _sign_stop()
		"sign_warn": return _sign_warn()
		"sign_direction": return _sign_direction()
		"billboard": return _billboard()
		"bus_shelter": return _bus_shelter()
		"bench": return _bench()
		"bollard": return _bollard()
		"dumpster": return _dumpster()
		"kiosk": return _kiosk()
		"jersey_barrier": return _jersey_barrier()
		"market_stall": return _market_stall()
		"stall_canopy": return _stall_canopy()
		"shop_awning": return _shop_awning()
		"produce_crates": return _produce_crates()
		"hand_cart": return _hand_cart()
		"fence_rail": return _fence_rail()
		"fence_board": return _fence_board()
		"fence_chainlink": return _fence_chainlink()
		"fence_barbed": return _fence_barbed()
		"fence_corrugated": return _fence_corrugated()
		"wall_stone": return _wall_stone()
		"wall_block": return _wall_block()
		"wall_mud": return _wall_mud()
		"gate_farm": return _gate_farm()
		"gate_steel": return _gate_steel()
		"gate_wood": return _gate_wood()
		"pylon": return _pylon()
		"power_pole_h": return _power_pole_h()
		"well": return _well()
		"water_tower": return _water_tower()
		"cistern": return _cistern()
		"trough": return _trough()
		"hay_round": return _hay_round()
		"hay_square": return _hay_square()
		"irrigation_channel": return _irrigation_channel()
		"irrigation_pipe": return _irrigation_pipe()
		"sluice_gate": return _sluice_gate()
		"windpump": return _windpump()
		"pen_shelter": return _pen_shelter()
		"goat": return _goat()
		"sheep": return _sheep()
		"dog": return _dog()
		"car_sedan": return _car(false, false)
		"car_hatch": return _car(true, false)
		"van": return _van(false)
		"pickup_civ": return _pickup()
		"truck_cargo": return _truck(false, false)
		"truck_tanker": return _truck(true, false)
		"tractor": return _tractor()
		"hulk_car": return _car(false, true)
		"hulk_truck": return _truck(false, true)
		"hulk_van": return _van(true)
		"container_20": return _container(6.06, false)
		"container_40": return _container(12.19, false)
		"container_stack": return _container(6.06, true)
		"grave_mound": return _grave_mound()
		"headstone": return _headstone()
		"grave_cross": return _grave_cross()
		"tomb": return _tomb()
		"grave_stele": return _grave_stele()
		"generator": return _generator()
		"sat_dish": return _sat_dish()
		"laundry_line": return _laundry_line()
		"fuel_tank": return _fuel_tank()
		"gas_cylinders": return _gas_cylinders()
		"pallet_stack": return _pallet_stack()
		"tyre_pile": return _tyre_pile()
		"latrine": return _latrine()
	push_error("PropArt: no shape '%s'" % name)
	var o: Array = []
	_box(o, Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5), Color.MAGENTA)
	return _make(o, [], "wood")


# --- Street furniture --------------------------------------------------------------------------

## A street lamp: a concrete foot, a steel pole, an arm out over the street (+z; both ways when
## `double`) and the lamp head with its lens underneath.
static func _street_lamp(double: bool) -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.18, 0, -0.18), Vector3(0.18, 0.35, 0.18), CONCRETE, "concrete")
	_post(o, 0, 0, 0.35, 6.6, 0.075, STEEL, "steel")
	for s: float in ([1.0, -1.0] if double else [1.0]):
		_bar(o, Vector3(0, 6.35, 0), Vector3(0, 6.55, 1.2 * s), 0.07, STEEL, "steel")
		var z0 := 1.05 if s > 0.0 else -1.6
		_box(o, Vector3(-0.16, 6.42, z0), Vector3(0.16, 6.62, z0 + 0.55), DARK, "steel")
		_paint(o, Vector3(-0.12, 6.414, z0 + 0.05), Vector3(0.12, 6.418, z0 + 0.5), LAMP)
	return _make(o, [], "steel", SEE_M)


## A wooden utility pole: crossarm across x, three insulators, its wires along z; with a
## transformer (a grey drum on a bracket) when `transformer`.
static func _utility_pole(transformer: bool) -> Dictionary:
	var o: Array = []
	_post(o, 0, 0, 0, 8.6, 0.13, POLE, "wood")
	_box(o, Vector3(-1.0, 7.85, -0.07), Vector3(-0.13, 8.0, 0.07), POLE, "wood")
	_box(o, Vector3(0.13, 7.85, -0.07), Vector3(1.0, 8.0, 0.07), POLE, "wood")
	for x: float in [-0.85, 0.85]:
		_post(o, x, 0, 8.0, 8.16, 0.045, CERAMIC, "glass")
		_bar(o, Vector3(x * 0.7, 7.85, 0), Vector3(0.0, 7.25, 0), 0.05, POLE, "wood")
	_post(o, 0, 0, 8.6, 8.76, 0.045, CERAMIC, "glass")
	if transformer:
		_box(o, Vector3(-0.09, 5.95, 0.13), Vector3(0.09, 6.15, 0.22), STEEL, "steel")
		_post(o, 0, 0.5, 5.55, 6.45, 0.28, Color("7b8285"), "steel")
		for x: float in [-0.12, 0.0, 0.12]:
			_post(o, x, 0.5, 6.45, 6.6, 0.03, CERAMIC, "glass")
	return _make(o, [], "wood", SEE_M, PackedVector3Array([Vector3(-0.85, 8.14, 0), Vector3(0.85, 8.14, 0), Vector3(0, 8.74, 0)]))


static func _sign_post(o: Array, x: float, top: float) -> void:
	_post(o, x, 0, 0, top, 0.035, GALV, "steel")


## A stop sign: a white octagon with a red face (+z) on a post.
static func _sign_stop() -> Dictionary:
	var o: Array = []
	_sign_post(o, 0, 2.45)
	_drum(o, Vector3(0, 2.1, 0.05), 0.38, 0.03, Vector3.BACK, WHITE, "sheet")
	_drum(o, Vector3(0, 2.1, 0.0675), 0.33, 0.004, Vector3.BACK, RED, "", false)
	o[o.size() - 1]["decal"] = true
	_paint(o, Vector3(-0.2, 2.07, 0.0695), Vector3(0.2, 2.13, 0.0715), WHITE)
	return _make(o, [], "sheet", SEE_SMALL_M)


## A warning sign: a yellow diamond with a black mark, on a post.
static func _sign_warn() -> Dictionary:
	var o: Array = []
	_sign_post(o, 0, 2.4)
	var pts: Array = []
	for k in 8:
		var corner := [Vector2(0, -0.42), Vector2(0.42, 0), Vector2(-0.42, 0), Vector2(0, 0.42)][k & 3] as Vector2
		pts.append(Vector3(corner.x, 2.0 + corner.y, 0.035 if (k & 4) == 0 else 0.065))
	_hull(o, pts, Color("d6a325"), "sheet")
	_paint(o, Vector3(-0.03, 1.9, 0.066), Vector3(0.03, 2.12, 0.07), BLACK)
	_paint(o, Vector3(-0.03, 1.82, 0.066), Vector3(0.03, 1.87, 0.07), BLACK)
	return _make(o, [], "sheet", SEE_SMALL_M)


## A direction sign: a board on two posts, lettered and arrowed in white (green or blue).
static func _sign_direction() -> Dictionary:
	var o: Array = []
	_sign_post(o, -0.65, 2.35)
	_sign_post(o, 0.65, 2.35)
	_box(o, Vector3(-0.95, 1.6, 0.04), Vector3(0.95, 2.3, 0.07), 1.0, "sheet")
	for y: float in [1.72, 1.92, 2.12]:
		_paint(o, Vector3(-0.8, y, 0.0705), Vector3(0.35, y + 0.07, 0.0745), WHITE)
	_paint(o, Vector3(0.48, 1.9, 0.0705), Vector3(0.82, 2.0, 0.0745), WHITE)
	_paint(o, Vector3(0.7, 1.82, 0.0705), Vector3(0.78, 2.08, 0.0745), WHITE)
	return _make(o, ["2f6b45", "2e5a8a"], "sheet", SEE_M)


## A billboard: a 6 x 3 m panel on two steel legs with a walkway, its face (+z) an advert.
static func _billboard() -> Dictionary:
	var o: Array = []
	for x: float in [-2.0, 2.0]:
		_post(o, x, -0.25, 0, 6.2, 0.12, STEEL, "steel")
	_box(o, Vector3(-3.0, 3.2, -0.12), Vector3(3.0, 6.2, 0.0), WHITE, "sheet")
	_box(o, Vector3(-3.0, 3.0, 0.0), Vector3(3.0, 3.08, 0.6), STEEL, "steel")
	_paint(o, Vector3(-2.85, 3.35, 0.002), Vector3(0.6, 6.05, 0.006), 1.0)
	_paint(o, Vector3(0.75, 4.6, 0.002), Vector3(2.85, 6.05, 0.006), 0.7)
	_paint(o, Vector3(0.75, 3.35, 0.002), Vector3(2.85, 4.4, 0.006), Color("e4ddcb"))
	_paint(o, Vector3(-2.5, 5.2, 0.006), Vector3(0.2, 5.6, 0.01), WHITE)
	_paint(o, Vector3(-2.5, 4.6, 0.006), Vector3(-0.4, 4.85, 0.01), WHITE)
	return _make(o, ["a33f2e", "3d5d88", "c9a238", "3e6b4f"], "sheet", SEE_BIG_M)


## A bus shelter, open to +z: four posts, a roof, a glazed back and sides, a bench.
static func _bus_shelter() -> Dictionary:
	var o: Array = []
	for x: float in [-1.8, 1.8]:
		for z: float in [-0.8, 0.75]:
			_box(o, Vector3(x - 0.04, 0, z - 0.04), Vector3(x + 0.04, 2.3, z + 0.04), STEEL, "steel")
	_box(o, Vector3(-1.95, 2.3, -0.92), Vector3(1.95, 2.42, 0.9), 1.0, "sheet")
	_box(o, Vector3(-1.76, 0.25, -0.79), Vector3(1.76, 2.2, -0.76), GLASS, "glass")
	for x: float in [-1.81, 1.79]:
		_box(o, Vector3(x, 0.25, -0.72), Vector3(x + 0.02, 2.2, 0.15), GLASS, "glass")
	_box(o, Vector3(-1.4, 0.42, -0.7), Vector3(1.4, 0.48, -0.36), WOOD, "wood")
	for x: float in [-1.2, 1.2]:
		_box(o, Vector3(x - 0.03, 0, -0.6), Vector3(x + 0.03, 0.42, -0.46), STEEL, "steel")
	_paint(o, Vector3(-0.5, 2.31, 0.902), Vector3(0.5, 2.41, 0.906), WHITE)
	return _make(o, ["3d5d88", "3e6b4f", "8e2b23"], "sheet", SEE_M)


## A park bench: concrete legs, a slatted wooden seat and back.
static func _bench() -> Dictionary:
	var o: Array = []
	for x: float in [-0.75, 0.75]:
		_box(o, Vector3(x - 0.06, 0, -0.22), Vector3(x + 0.06, 0.42, 0.2), CONCRETE, "concrete")
		_box(o, Vector3(x - 0.04, 0.42, -0.22), Vector3(x + 0.04, 0.85, -0.17), CONCRETE, "concrete")
	_box(o, Vector3(-0.95, 0.42, -0.22), Vector3(0.95, 0.47, 0.22), WOOD, "wood")
	_box(o, Vector3(-0.95, 0.55, -0.26), Vector3(0.95, 0.85, -0.22), WOOD, "wood")
	for z: float in [-0.08, 0.07]:
		_paint(o, Vector3(-0.95, 0.4705, z), Vector3(0.95, 0.4745, z + 0.015), DARK)
	_paint(o, Vector3(-0.95, 0.69, -0.2195), Vector3(0.95, 0.705, -0.2155), DARK)
	return _make(o, [], "wood", SEE_SMALL_M, PackedVector3Array(), false)


## A bollard: a short steel post with a white band.
static func _bollard() -> Dictionary:
	var o: Array = []
	_post(o, 0, 0, 0, 0.9, 0.09, DARK, "steel")
	_drum(o, Vector3(0, 0.75, 0), 0.094, 0.08, Vector3.UP, WHITE, "", false)
	o[o.size() - 1]["decal"] = true
	return _make(o, [], "steel", SEE_SMALL_M, PackedVector3Array(), false)


## A rubbish skip: a tapered steel bin with a sloping lid, on castors.
static func _dumpster() -> Dictionary:
	var o: Array = []
	_slab(o, -0.9, 0.9, 0.15, 1.15, 1.15, -0.95, 0.95, 0.55, 0.62, 1.0, "hollow")
	var lid: Array = []
	for k in 8:
		var front := (k & 4) != 0
		var y := (1.17 if front else 1.27) + (0.04 if (k & 2) != 0 else 0.0)
		lid.append(Vector3(-0.97 if (k & 1) == 0 else 0.97, y, 0.64 if front else -0.66))
	_hull(o, lid, DARK, "sheet")
	for x: float in [-0.75, 0.75]:
		for z: float in [-0.4, 0.4]:
			_post(o, x, z, 0, 0.15, 0.06, BLACK, "steel")
	_paint(o, Vector3(-0.9, 0.3, 0.552), Vector3(0.9, 0.36, 0.556), DARK)
	return _make(o, ["2f5a3a", "2e4a6e", "5a5a5a"], "hollow", SEE_SMALL_M)


## A street kiosk: a small booth with a roof overhang, a counter and a window (+z).
static func _kiosk() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.0, 0, -0.8), Vector3(1.0, 2.3, 0.8), 1.0, "hollow")
	_box(o, Vector3(-1.15, 2.3, -0.95), Vector3(1.15, 2.45, 1.1), DARK, "sheet")
	_box(o, Vector3(-0.9, 1.0, 0.8), Vector3(0.9, 1.06, 1.05), WOOD, "wood")
	_paint(o, Vector3(-0.8, 1.15, 0.802), Vector3(0.8, 2.0, 0.806), GLASS)
	_paint(o, Vector3(-0.9, 2.08, 0.802), Vector3(0.9, 2.26, 0.806), WHITE)
	return _make(o, ["b8642a", "3d5d88", "3e6b4f", "c9a238"], "hollow", SEE_M)


## A concrete road barrier (a Jersey wall): a broad foot and a tapering upper, 3 m long.
static func _jersey_barrier() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.5, 0, -0.3), Vector3(1.5, 0.25, 0.3), 1.0, "concrete")
	_slab(o, -1.5, 1.5, 0.25, 0.81, 0.81, -1.5, 1.5, 0.25, 0.08, 1.0, "concrete")
	_paint(o, Vector3(-1.5, 0.12, 0.302), Vector3(-0.9, 0.2, 0.306), RED)
	_paint(o, Vector3(0.9, 0.12, 0.302), Vector3(1.5, 0.2, 0.306), RED)
	return _make(o, ["a5a29a", "c9c4b6"], "concrete", SEE_M)


# --- Market ------------------------------------------------------------------------------------

## Produce on a table: little boxes of fruit and veg in their colours.
static func _goods(o: Array, x0: float, x1: float, y: float, z: float) -> void:
	var colours: Array[Color] = [Color("d9822b"), Color("6b8f3a"), Color("a83a2e"), Color("d6b24a"), Color("7a4a6e")]
	var x := x0
	var k := 0
	while x + 0.36 <= x1:
		_box(o, Vector3(x, y, z - 0.16), Vector3(x + 0.34, y + 0.16, z + 0.16), Color("8a6a45"), "wood")
		_paint(o, Vector3(x + 0.03, y + 0.1602, z - 0.13), Vector3(x + 0.31, y + 0.1642, z + 0.13), colours[k % colours.size()])
		x += 0.4
		k += 1


## A market stall: a table with a front skirt and goods, four poles and a striped awning sloping
## down to the front (+z, the customers' side).
static func _market_stall() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.2, 0.85, -0.5), Vector3(1.2, 0.92, 0.5), WOOD, "wood")
	_box(o, Vector3(-1.2, 0.1, 0.44), Vector3(1.2, 0.85, 0.5), WOOD_OLD, "wood")
	for x: float in [-1.12, 1.12]:
		_box(o, Vector3(x - 0.04, 0, -0.48), Vector3(x + 0.04, 0.85, -0.4), WOOD, "wood")
	for x: float in [-1.28, 1.28]:
		_post(o, x, -0.62, 0, 2.48, 0.035, WOOD, "wood")
		_post(o, x, 0.72, 0, 2.18, 0.035, WOOD, "wood")
	var roof: Array = []
	for k in 8:
		var front := (k & 4) != 0
		roof.append(Vector3(-1.35 if (k & 1) == 0 else 1.35, (2.2 if front else 2.5) + (0.04 if (k & 2) != 0 else 0.0), 0.8 if front else -0.7))
	_hull(o, roof, 1.0, "cloth")
	for x: float in [-0.95, -0.05, 0.85]:
		_decal(o, Vector3(x, 2.54, -0.7), Vector3(x + 0.45, 2.54, -0.7), Vector3(x + 0.45, 2.24, 0.8), Vector3(x, 2.24, 0.8), Vector3(0, 2.0, 0), WHITE)
	_goods(o, -1.15, 1.15, 0.92, -0.05)
	return _make(o, ["a33f2e", "3e6b4f", "3d5d88", "c9a238"], "wood", SEE_M)


## A big market canopy: four poles and a cloth gable roof over a trestle table with goods.
static func _stall_canopy() -> Dictionary:
	var o: Array = []
	for x: float in [-1.5, 1.5]:
		for z: float in [-1.5, 1.5]:
			_post(o, x, z, 0, 2.3, 0.05, WOOD, "wood")
	for side: float in [-1.0, 1.0]:
		var roof: Array = []
		for k in 8:
			var eave := (k & 4) != 0
			roof.append(Vector3(-1.7 if (k & 1) == 0 else 1.7, (2.25 if eave else 2.9) + (0.04 if (k & 2) != 0 else 0.0), side * (1.7 if eave else 0.0)))
		_hull(o, roof, 1.0 if side < 0.0 else 0.88, "cloth")
	_box(o, Vector3(-1.2, 0.75, -0.6), Vector3(1.2, 0.82, 0.6), WOOD, "wood")
	for x: float in [-1.05, 1.05]:
		_box(o, Vector3(x - 0.04, 0, -0.5), Vector3(x + 0.04, 0.75, 0.5), WOOD, "wood")
	_goods(o, -1.15, 1.15, 0.82, -0.3)
	_goods(o, -1.15, 1.15, 0.82, 0.3)
	return _make(o, ["c9a238", "a33f2e", "d8d2bc", "3d5d88"], "wood", SEE_M)


## A shop awning: a striped cloth lean-to on four poles, sloping down to the front (+z), a valance.
static func _shop_awning() -> Dictionary:
	var o: Array = []
	for x: float in [-1.6, 1.6]:
		_post(o, x, -0.95, 0, 2.62, 0.04, STEEL, "steel")
		_post(o, x, 0.95, 0, 2.22, 0.04, STEEL, "steel")
	var roof: Array = []
	for k in 8:
		var front := (k & 4) != 0
		roof.append(Vector3(-1.7 if (k & 1) == 0 else 1.7, (2.22 if front else 2.62) + (0.04 if (k & 2) != 0 else 0.0), 1.05 if front else -1.05))
	_hull(o, roof, 1.0, "cloth")
	_box(o, Vector3(-1.7, 1.98, 1.03), Vector3(1.7, 2.22, 1.07), 0.85, "cloth")
	for x: float in [-1.5, -0.7, 0.1, 0.9]:
		_decal(o, Vector3(x, 2.66, -1.05), Vector3(x + 0.4, 2.66, -1.05), Vector3(x + 0.4, 2.26, 1.05), Vector3(x, 2.26, 1.05), Vector3(0, 1.5, 0), WHITE)
	return _make(o, ["8e2b23", "2f6b45", "3d5d88", "b8642a"], "cloth", SEE_M)


## Produce crates: a stack of wooden crates, each topped with its fruit or veg.
static func _produce_crates() -> Dictionary:
	var o: Array = []
	var colours: Array[Color] = [Color("d9822b"), Color("6b8f3a"), Color("a83a2e"), Color("d6b24a"), Color("8a5a3a")]
	var k := 0
	for spot: Vector3 in [Vector3(-0.65, 0, 0), Vector3(0, 0, 0), Vector3(0.65, 0, 0), Vector3(-0.33, 0.32, 0), Vector3(0.33, 0.32, 0)]:
		_box(o, spot + Vector3(-0.3, 0, -0.2), spot + Vector3(0.3, 0.3, 0.2), Color("8a6a45"), "wood")
		if spot.y > 0.0 or k == 0 or k == 2:
			_paint(o, spot + Vector3(-0.27, 0.3002, -0.17), spot + Vector3(0.27, 0.3042, 0.17), colours[k % colours.size()])
		_paint(o, spot + Vector3(-0.3, 0.12, 0.2002), spot + Vector3(0.3, 0.16, 0.2042), Color("5e4630"))
		k += 1
	return _make(o, [], "wood", SEE_SMALL_M)


## A hand cart: a plank bed on two big wheels, handles to the back (-x), a few sacks aboard.
static func _hand_cart() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.9, 0.45, -0.5), Vector3(0.7, 0.53, 0.5), WOOD, "wood")
	for z: float in [-0.5, 0.46]:
		_box(o, Vector3(-0.9, 0.53, z), Vector3(0.7, 0.75, z + 0.04), WOOD_OLD, "wood")
	for z: float in [-0.6, 0.6]:
		_drum(o, Vector3(0, 0.4, z), 0.4, 0.07, Vector3.BACK, DARK, "wood")
	for z: float in [-0.42, 0.42]:
		_bar(o, Vector3(-0.9, 0.5, z), Vector3(-1.7, 0.85, z), 0.05, WOOD, "wood")
	_box(o, Vector3(0.6, 0, -0.04), Vector3(0.68, 0.45, 0.04), WOOD, "wood")
	_box(o, Vector3(-0.6, 0.53, -0.3), Vector3(-0.05, 0.85, 0.25), Color("b39f78"), "cloth")
	_box(o, Vector3(0.05, 0.53, -0.25), Vector3(0.6, 0.8, 0.3), Color("a8936b"), "cloth")
	return _make(o, [], "wood", SEE_SMALL_M)


# --- Fences, walls and gates (a section 3 m along x) -------------------------------------------

const SECTION_M := 3.0


static func _fence_posts(o: Array, top: float, half: float, c: Color, m: String) -> void:
	for x: float in [-1.5, 1.5]:
		_box(o, Vector3(x - half, 0, -half), Vector3(x + half, top, half), c, m)


## A post-and-rail fence: two posts and two rails.
static func _fence_rail() -> Dictionary:
	var o: Array = []
	_fence_posts(o, 1.25, 0.06, WOOD_OLD, "wood")
	for y: float in [0.45, 0.95]:
		_box(o, Vector3(-1.44, y, -0.025), Vector3(1.44, y + 0.1, 0.025), 1.0, "wood")
	return _make(o, ["7d6b55", "6b5238", "8f846f"], "wood", SEE_M)


## A board fence: posts, and a wall of upright boards (grooves painted between them).
static func _fence_board() -> Dictionary:
	var o: Array = []
	_fence_posts(o, 1.85, 0.06, WOOD, "wood")
	_box(o, Vector3(-1.44, 0.05, 0.03), Vector3(1.44, 1.8, 0.06), 1.0, "wood")
	var x := -1.3
	while x < 1.4:
		_paint(o, Vector3(x, 0.05, 0.0602), Vector3(x + 0.015, 1.8, 0.0642), DARK)
		x += 0.16
	return _make(o, ["8a7356", "5e4a36", "6b7a5a"], "wood", SEE_M)


## A chain-link fence: steel posts and a top rail; the weave is drawn (and stops men, not sight or
## rounds: its see-through panel).
static func _fence_chainlink() -> Dictionary:
	var o: Array = []
	for x: float in [-1.5, 1.5]:
		_post(o, x, 0, 0, 2.0, 0.035, GALV, "steel")
	_bar(o, Vector3(-1.5, 1.95, 0), Vector3(1.5, 1.95, 0), 0.04, GALV, "steel")
	_box(o, Vector3(-1.47, 0.05, -0.008), Vector3(1.47, 1.93, 0.008), GALV, SEE_THROUGH)
	o[o.size() - 1]["draw"] = false
	_weave(o, -1.47, 1.47, 0.05, 1.93, 0.28, Color("7d8285"))
	return _make(o, [], "steel", SEE_M)


## Diagonal wires both ways over the panel x0..x1, y0..y1 every `step` (drawn only).
static func _weave(o: Array, x0: float, x1: float, y0: float, y1: float, step: float, c: Color) -> void:
	var h := y1 - y0
	for dir: float in [1.0, -1.0]:
		var start := x0 - h
		while start < x1:
			# The line x = start + (y - y0) * 1 (or mirrored), clipped to the panel.
			var a := Vector2(start, y0)
			var b := Vector2(start + h, y1)
			if a.x < x0:
				a = Vector2(x0, y0 + (x0 - a.x))
			if b.x > x1:
				b = Vector2(x1, y1 - (b.x - x1))
			if b.y > a.y + 0.02:
				var pa := Vector3(a.x if dir > 0.0 else x0 + x1 - a.x, a.y, 0)
				var pb := Vector3(b.x if dir > 0.0 else x0 + x1 - b.x, b.y, 0)
				_bar(o, pa, pb, 0.012, c, "", false)
			start += step


## A barbed-wire fence: wooden posts and four strands (drawn; a see-through panel stops men).
static func _fence_barbed() -> Dictionary:
	var o: Array = []
	for x: float in [-1.5, 1.5]:
		_post(o, x, 0, 0, 1.3, 0.05, POLE, "wood")
	for y: float in [0.3, 0.6, 0.9, 1.2]:
		_bar(o, Vector3(-1.5, y, 0), Vector3(1.5, y - 0.02, 0), 0.012, Color("5d5a55"), "", false)
	_box(o, Vector3(-1.45, 0.05, -0.01), Vector3(1.45, 1.22, 0.01), DARK, SEE_THROUGH)
	o[o.size() - 1]["draw"] = false
	return _make(o, [], "wood", SEE_M, PackedVector3Array(), false)


## A corrugated-iron fence: posts and a sheet panel with its ribs.
static func _fence_corrugated() -> Dictionary:
	var o: Array = []
	_fence_posts(o, 2.0, 0.05, POLE, "wood")
	_box(o, Vector3(-1.45, 0, 0.05), Vector3(1.45, 2.0, 0.08), 1.0, "sheet")
	var x := -1.4
	while x < 1.4:
		_paint(o, Vector3(x, 0, 0.0802), Vector3(x + 0.06, 2.0, 0.0842), 0.8)
		x += 0.2
	return _make(o, ["7a4431", "8b8e8c", "6a5a4a", "5c6a6e"], "sheet", SEE_M)


## A dry-stone field wall: battered sides and a row of coping stones on top.
static func _wall_stone() -> Dictionary:
	var o: Array = []
	_slab(o, -1.5, 1.5, 0, 0.9, 0.9, -1.5, 1.5, 0.3, 0.22, 1.0, "stone")
	var x := -1.5
	var k := 0
	while x < 1.45:
		var w := minf(0.32 + 0.07 * (k % 3), 1.5 - x)
		_box(o, Vector3(x, 0.9, -0.2), Vector3(x + w, 0.98 + 0.05 * ((k * 7) % 3), 0.2), 0.85 + 0.06 * (k % 3), "stone")
		x += w
		k += 1
	_paint(o, Vector3(-1.5, 0.3, 0.27), Vector3(1.5, 0.34, 0.31), 0.7)
	return _make(o, ["8a8170", "77736a", "9a8e78"], "stone", SEE_M)


## A block wall: rendered blocks with a coping and painted joints.
static func _wall_block() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.5, 0, -0.1), Vector3(1.5, 1.4, 0.1), 1.0, "concrete")
	_box(o, Vector3(-1.5, 1.4, -0.13), Vector3(1.5, 1.48, 0.13), CONCRETE, "concrete")
	for y: float in [0.2, 0.4, 0.6, 0.8, 1.0, 1.2]:
		for s: float in [-1.0, 1.0]:
			var z := 0.1 * s
			_paint(o, Vector3(-1.5, y, minf(z, z + 0.004 * s)), Vector3(1.5, y + 0.012, maxf(z, z + 0.004 * s)), 0.82)
	_paint(o, Vector3(-1.5, 0, 0.1002), Vector3(1.5, 0.25, 0.1042), 0.7)
	return _make(o, ["d8d4c6", "ddd2b2", "9a978f", "c99d86"], "concrete", SEE_M)


## A mud-brick wall: thick at the foot, rounded at the top.
static func _wall_mud() -> Dictionary:
	var o: Array = []
	_slab(o, -1.5, 1.5, 0, 1.55, 1.55, -1.5, 1.5, 0.25, 0.18, 1.0, "mud")
	_slab(o, -1.5, 1.5, 1.55, 1.7, 1.7, -1.5, 1.5, 0.18, 0.07, 0.92, "mud")
	_paint(o, Vector3(-1.5, 0, 0.2502), Vector3(1.5, 0.22, 0.2542), 0.75)
	return _make(o, ["a47e57", "94634a", "b8956a"], "mud", SEE_M)


## A steel five-bar farm gate, swung open (+z) from its hinge post; the latch post across the gap.
static func _gate_farm() -> Dictionary:
	var o: Array = []
	_fence_posts(o, 1.3, 0.08, WOOD_OLD, "wood")
	var hinge := -1.38
	for y: float in [0.25, 0.45, 0.65, 0.85, 1.05]:
		_bar(o, Vector3(hinge, y, 0.1), Vector3(hinge, y, 2.85), 0.045, GALV, "steel")
	for z: float in [0.12, 2.83]:
		_bar(o, Vector3(hinge, 0.22, z), Vector3(hinge, 1.08, z), 0.05, GALV, "steel")
	_bar(o, Vector3(hinge, 0.25, 0.15), Vector3(hinge, 1.05, 2.8), 0.04, GALV, "steel")
	return _make(o, [], "steel", SEE_M)


## Steel double gates between concrete pillars, both leaves open (+z).
static func _gate_steel() -> Dictionary:
	var o: Array = []
	for x: float in [-2.05, 2.05]:
		_box(o, Vector3(x - 0.2, 0, -0.2), Vector3(x + 0.2, 2.4, 0.2), CONCRETE, "concrete")
		_box(o, Vector3(x - 0.24, 2.4, -0.24), Vector3(x + 0.24, 2.5, 0.24), CONCRETE, "concrete")
	for s: float in [-1.0, 1.0]:
		var x := s * 1.79
		_box(o, Vector3(minf(x, x + 0.05 * s), 0.05, 0.22), Vector3(maxf(x, x + 0.05 * s), 2.15, 2.05), 1.0, "steel")
		for z: float in [0.6, 1.1, 1.6]:
			var face := x + 0.05 * s
			_paint(o, Vector3(minf(face, face + 0.004 * s), 0.1, z), Vector3(maxf(face, face + 0.004 * s), 2.1, z + 0.03), 0.75)
	return _make(o, ["4d6a55", "4a6580", "6f7376"], "steel", SEE_M)


## A plank gate on wooden posts, swung open (+z).
static func _gate_wood() -> Dictionary:
	var o: Array = []
	_fence_posts(o, 1.7, 0.08, POLE, "wood")
	_box(o, Vector3(-1.4, 0.1, 0.12), Vector3(-1.34, 1.6, 2.85), 1.0, "wood")
	var z := 0.3
	while z < 2.8:
		_paint(o, Vector3(-1.3398, 0.1, z), Vector3(-1.3358, 1.6, z + 0.015), DARK)
		z += 0.2
	_bar(o, Vector3(-1.33, 0.2, 0.2), Vector3(-1.33, 1.5, 2.75), 0.06, 0.8, "wood")
	return _make(o, ["6b5238", "7d6b55", "4d6a55"], "wood", SEE_M)


# --- Power lines -------------------------------------------------------------------------------

## A steel lattice pylon, 24 m: four legs tapering from a 5.2 m base, bands and braces between them,
## two cross arms with insulator strings, an earth peak. Its wires run along z.
static func _pylon() -> Dictionary:
	var o: Array = []
	var base := 2.6
	var waist := 0.85
	var half := func(y: float) -> float: return lerpf(base, waist, y / 18.0)
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var c := Color("858a8c")
	for s: Vector2 in corners:
		_box(o, Vector3(s.x * base - 0.45, -0.2, s.y * base - 0.45), Vector3(s.x * base + 0.45, 0.3, s.y * base + 0.45), CONCRETE, "concrete")
		_bar(o, Vector3(s.x * base, 0.0, s.y * base), Vector3(s.x * waist, 18.0, s.y * waist), 0.18, c, "steel")
		_bar(o, Vector3(s.x * waist, 18.0, s.y * waist), Vector3(s.x * 0.4, 24.0, s.y * 0.4), 0.13, c, "steel")
	var bands: Array[float] = [6.0, 12.0, 18.0]
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var lo := 0.6
		for k in bands.size():
			var y := bands[k]
			var hy: float = half.call(y)
			var hl: float = half.call(lo)
			_bar(o, Vector3(a.x * hy, y, a.y * hy), Vector3(b.x * hy, y, b.y * hy), 0.09, c, "steel")
			var from := a if (k + i) % 2 == 0 else b
			var to := b if (k + i) % 2 == 0 else a
			_bar(o, Vector3(from.x * hl, lo, from.y * hl), Vector3(to.x * hy, y, to.y * hy), 0.07, c, "steel")
			lo = y
	_box(o, Vector3(-6.5, 17.75, -0.32), Vector3(6.5, 18.1, 0.32), c, "steel")
	_box(o, Vector3(-4.8, 21.3, -0.28), Vector3(4.8, 21.6, 0.28), c, "steel")
	for x: float in [-6.0, 6.0]:
		_post(o, x, 0, 15.9, 17.75, 0.12, CERAMIC, "glass")
	for x: float in [-4.3, 4.3]:
		_post(o, x, 0, 19.6, 21.3, 0.11, CERAMIC, "glass")
	return _make(o, [], "steel", SEE_BIG_M,
		PackedVector3Array([Vector3(-6.0, 15.9, 0), Vector3(6.0, 15.9, 0), Vector3(-4.3, 19.6, 0), Vector3(4.3, 19.6, 0), Vector3(0, 24.0, 0)]))


## An H-frame wooden pole for a country power line: two poles, a crossbeam, braces, three
## insulators. Its wires run along z.
static func _power_pole_h() -> Dictionary:
	var o: Array = []
	for x: float in [-1.3, 1.3]:
		_post(o, x, 0, 0, 10.2, 0.15, POLE, "wood")
	_box(o, Vector3(-2.4, 9.3, -0.1), Vector3(-1.45, 9.55, 0.1), POLE, "wood")
	_box(o, Vector3(-1.15, 9.3, -0.1), Vector3(1.15, 9.55, 0.1), POLE, "wood")
	_box(o, Vector3(1.45, 9.3, -0.1), Vector3(2.4, 9.55, 0.1), POLE, "wood")
	_bar(o, Vector3(-1.15, 7.6, 0), Vector3(1.15, 9.25, 0), 0.08, POLE, "wood")
	for x: float in [-2.0, 0.0, 2.0]:
		_post(o, x, 0, 9.55, 9.85, 0.05, CERAMIC, "glass")
	return _make(o, [], "wood", SEE_BIG_M, PackedVector3Array([Vector3(-2.0, 9.83, 0), Vector3(0, 9.83, 0), Vector3(2.0, 9.83, 0)]))


# --- Farm and water ----------------------------------------------------------------------------

## A well: a stone ring (dark water in it), two posts and a windlass under a small gable roof, a
## bucket.
static func _well() -> Dictionary:
	var o: Array = []
	_post(o, 0, 0, 0, 0.8, 0.8, STONE, "stone")
	_drum(o, Vector3(0, 0.8035, 0), 0.62, 0.003, Vector3.UP, Color("1d2526"), "", false)
	o[o.size() - 1]["decal"] = true
	for x: float in [-0.95, 0.95]:
		_box(o, Vector3(x - 0.07, 0, -0.07), Vector3(x + 0.07, 2.0, 0.07), WOOD, "wood")
	_drum(o, Vector3(0, 1.6, 0), 0.08, 1.76, Vector3.RIGHT, WOOD_OLD, "wood")
	for side: float in [-1.0, 1.0]:
		var roof: Array = []
		for k in 8:
			var eave := (k & 4) != 0
			roof.append(Vector3(-1.15 if (k & 1) == 0 else 1.15, (1.98 if eave else 2.35) + (0.04 if (k & 2) != 0 else 0.0), side * (0.75 if eave else 0.0)))
		_hull(o, roof, 1.0, "wood")
	_post(o, 0.3, 0, 0.95, 1.17, 0.12, GALV, "steel")
	_bar(o, Vector3(0.3, 1.17, 0), Vector3(0.3, 1.52, 0), 0.015, Color("8a7a5a"), "", false)
	return _make(o, ["7a4431", "5e4a36", "8a8170"], "stone", SEE_M)


## A raised water tank: four steel legs braced, a platform, the tank and its lid, a ladder.
static func _water_tower() -> Dictionary:
	var o: Array = []
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for s: Vector2 in corners:
		_bar(o, Vector3(s.x * 1.4, 0, s.y * 1.4), Vector3(s.x * 1.1, 5.0, s.y * 1.1), 0.12, STEEL, "steel")
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		_bar(o, Vector3(a.x * 1.25, 2.5, a.y * 1.25), Vector3(b.x * 1.25, 2.5, b.y * 1.25), 0.07, STEEL, "steel")
		_bar(o, Vector3(a.x * 1.38, 0.2, a.y * 1.38), Vector3(b.x * 1.25, 2.5, b.y * 1.25), 0.05, STEEL, "steel")
	_box(o, Vector3(-1.5, 5.0, -1.5), Vector3(1.5, 5.15, 1.5), STEEL, "steel")
	_post(o, 0, 0, 5.15, 7.55, 1.35, 1.0, "water")
	_post(o, 0, 0, 7.55, 7.8, 0.9, 0.85, "water")
	for x: float in [-0.2, 0.2]:
		_bar(o, Vector3(x, 0.0, 1.5), Vector3(x, 5.0, 1.12), 0.03, STEEL, "", false)
	return _make(o, ["c9c9c4", "4d6a55", "8a5b3e"], "water", SEE_BIG_M)


## A ground water tank on blocks, with a lid.
static func _cistern() -> Dictionary:
	var o: Array = []
	for x: float in [-0.55, 0.55]:
		_box(o, Vector3(x - 0.2, 0, -0.8), Vector3(x + 0.2, 0.25, 0.8), CONCRETE, "concrete")
	_post(o, 0, 0, 0.25, 1.75, 1.0, 1.0, "water")
	_post(o, 0, 0, 1.75, 1.85, 0.3, 0.7, "water")
	_paint(o, Vector3(-0.3, 0.6, 0.9902), Vector3(0.3, 0.66, 0.9942), 0.7)
	return _make(o, ["2a2c2e", "3d5d88", "c9c9c4"], "water", SEE_M)


## A water trough with water in it.
static func _trough() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.0, 0, -0.3), Vector3(1.0, 0.55, 0.3), 1.0, "concrete")
	_paint(o, Vector3(-0.92, 0.5502, -0.22), Vector3(0.92, 0.5542, 0.22), WATER)
	return _make(o, ["8c9194", "9a978f"], "concrete", SEE_SMALL_M, PackedVector3Array(), false)


## A round hay bale lying on its side (along x).
static func _hay_round() -> Dictionary:
	var o: Array = []
	_drum(o, Vector3(0, 0.72, 0), 0.72, 1.2, Vector3.RIGHT, 1.0, "hay")
	_drum(o, Vector3(0.6035, 0.72, 0), 0.45, 0.003, Vector3.RIGHT, 0.82, "", false)
	o[o.size() - 1]["decal"] = true
	return _make(o, ["c9a85a", "9a8456", "d8d6cf", "2a2c2e"], "hay", SEE_M)


## A stack of five square bales, three below and two on top.
static func _hay_square() -> Dictionary:
	var o: Array = []
	for z0: float in [-0.75, -0.25, 0.25]:
		_box(o, Vector3(-0.5, 0, z0), Vector3(0.5, 0.45, z0 + 0.5), 1.0 - 0.04 * absf(z0), "hay")
	for z0: float in [-0.5, 0.0]:
		_box(o, Vector3(-0.5, 0.45, z0), Vector3(0.5, 0.9, z0 + 0.5), 0.94, "hay")
	for x: float in [-0.25, 0.25]:
		_paint(o, Vector3(x, 0.9002, -0.5), Vector3(x + 0.02, 0.9042, 0.5), Color("6b5a3a"))
	return _make(o, ["c9a85a", "b39558"], "hay", SEE_M)


## A concrete-lined irrigation channel, 4 m along x, water in it.
static func _irrigation_channel() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-2.0, 0, 0.3), Vector3(2.0, 0.45, 0.42), 1.0, "concrete")
	_box(o, Vector3(-2.0, 0, -0.42), Vector3(2.0, 0.45, -0.3), 1.0, "concrete")
	_box(o, Vector3(-2.0, 0, -0.3), Vector3(2.0, 0.08, 0.3), 0.85, "concrete")
	_paint(o, Vector3(-2.0, 0.0802, -0.3), Vector3(2.0, 0.3, 0.3), WATER)
	return _make(o, ["9a978f", "a59478"], "concrete", SEE_M, PackedVector3Array(), false)


## An irrigation pipe, 4 m along x on two concrete supports, flanged at the ends.
static func _irrigation_pipe() -> Dictionary:
	var o: Array = []
	for x: float in [-1.4, 1.4]:
		_box(o, Vector3(x - 0.15, 0, -0.15), Vector3(x + 0.15, 0.32, 0.15), CONCRETE, "concrete")
	_drum(o, Vector3(0, 0.46, 0), 0.14, 4.0, Vector3.RIGHT, 1.0, "steel")
	for x: float in [-1.95, 1.95]:
		_drum(o, Vector3(x, 0.46, 0), 0.17, 0.08, Vector3.RIGHT, 0.8, "steel")
	return _make(o, ["8c9194", "3f5a78", "2b2d2f"], "steel", SEE_SMALL_M, PackedVector3Array(), false)


## A sluice gate: a concrete frame, a steel plate, and its wheel on a spindle.
static func _sluice_gate() -> Dictionary:
	var o: Array = []
	for x: float in [-0.58, 0.58]:
		_box(o, Vector3(x - 0.08, 0, -0.2), Vector3(x + 0.08, 1.4, 0.2), CONCRETE, "concrete")
	_box(o, Vector3(-0.66, 1.4, -0.2), Vector3(0.66, 1.55, 0.2), CONCRETE, "concrete")
	_box(o, Vector3(-0.5, 0, -0.03), Vector3(0.5, 0.9, 0.03), 1.0, "steel")
	_post(o, 0, 0, 0.9, 1.7, 0.025, STEEL, "steel")
	_drum(o, Vector3(0, 1.73, 0), 0.25, 0.04, Vector3.UP, RED, "steel")
	return _make(o, ["3f5a78", "6b6f72"], "concrete", SEE_SMALL_M)


## A windpump: a braced steel tower, a bladed wheel facing +x and a tail vane.
static func _windpump() -> Dictionary:
	var o: Array = []
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for s: Vector2 in corners:
		_bar(o, Vector3(s.x * 1.0, 0, s.y * 1.0), Vector3(s.x * 0.25, 8.0, s.y * 0.25), 0.1, GALV, "steel")
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		for y: float in [2.7, 5.4]:
			var h := lerpf(1.0, 0.25, y / 8.0)
			_bar(o, Vector3(a.x * h, y, a.y * h), Vector3(b.x * h, y, b.y * h), 0.05, GALV, "steel")
	_box(o, Vector3(-0.35, 8.0, -0.35), Vector3(0.35, 8.15, 0.35), GALV, "steel")
	_box(o, Vector3(-0.2, 8.15, -0.15), Vector3(0.4, 8.45, 0.15), GALV, "steel")
	_drum(o, Vector3(0.48, 8.6, 0), 0.2, 0.16, Vector3.RIGHT, DARK, "steel")
	for k in 8:
		var a := k * TAU / 8.0
		var dir := Vector3(0, sin(a), cos(a))
		_bar(o, Vector3(0.5, 8.6, 0) + dir * 0.2, Vector3(0.5, 8.6, 0) + dir * 1.3, 0.2, 1.0, "sheet")
	_bar(o, Vector3(0.0, 8.6, 0), Vector3(-1.5, 8.6, 0), 0.06, GALV, "steel")
	_box(o, Vector3(-1.95, 8.2, -0.02), Vector3(-1.2, 9.0, 0.02), 1.0, "sheet")
	return _make(o, ["a9b0b3", "8a3b2a"], "steel", SEE_BIG_M)


## An open-fronted animal shelter: four posts, a plank back, a corrugated roof sloping to the back.
static func _pen_shelter() -> Dictionary:
	var o: Array = []
	for x: float in [-1.5, 1.5]:
		_box(o, Vector3(x - 0.05, 0, -1.25), Vector3(x + 0.05, 1.9, -1.15), WOOD, "wood")
		_box(o, Vector3(x - 0.05, 0, 1.15), Vector3(x + 0.05, 2.3, 1.25), WOOD, "wood")
	var roof: Array = []
	for k in 8:
		var front := (k & 4) != 0
		roof.append(Vector3(-1.65 if (k & 1) == 0 else 1.65, (2.3 if front else 1.9) + (0.05 if (k & 2) != 0 else 0.0), 1.35 if front else -1.35))
	_hull(o, roof, 1.0, "sheet")
	_box(o, Vector3(-1.45, 0, -1.25), Vector3(1.45, 1.85, -1.2), WOOD_OLD, "wood")
	return _make(o, ["7a4431", "8b8e8c"], "wood", SEE_M)


# --- Animals (ZoneAnimals draws and moves them; no collision of their own here) -----------------

static func _legs(o: Array, xs: Array, zs: Array, top: float, w: float, c: Color) -> void:
	for x: float in xs:
		for z: float in zs:
			_box(o, Vector3(x - w, 0, z - w), Vector3(x + w, top, z + w), c, "", false)


## A goat (facing +x): lean body, neck and head, horns swept back, a beard and a short tail up.
static func _goat() -> Dictionary:
	var o: Array = []
	_legs(o, [-0.28, 0.28], [-0.1, 0.1], 0.48, 0.035, Color(0.35, 0.33, 0.3))
	_box(o, Vector3(-0.4, 0.45, -0.17), Vector3(0.38, 0.8, 0.17), 1.0, "", false)
	_bar(o, Vector3(0.33, 0.72, 0), Vector3(0.48, 0.95, 0), 0.13, 1.0, "", false)
	_box(o, Vector3(0.42, 0.86, -0.08), Vector3(0.68, 1.02, 0.08), 0.95, "", false)
	for z: float in [-0.05, 0.05]:
		_bar(o, Vector3(0.5, 1.01, z), Vector3(0.36, 1.18, z * 1.8), 0.03, Color(0.3, 0.28, 0.24), "", false)
	_box(o, Vector3(0.58, 0.78, -0.025), Vector3(0.64, 0.87, 0.025), 0.6, "", false)
	_bar(o, Vector3(-0.4, 0.75, 0), Vector3(-0.47, 0.9, 0), 0.05, 0.9, "", false)
	return _make(o, ["8a6a45", "2e2a26", "d8d2c0", "6b5040"], "", 160.0)


## A sheep (facing +x): a woolly barrel body, a dark face and legs.
static func _sheep() -> Dictionary:
	var o: Array = []
	_legs(o, [-0.3, 0.3], [-0.13, 0.13], 0.42, 0.04, Color(0.22, 0.2, 0.19))
	_box(o, Vector3(-0.48, 0.38, -0.27), Vector3(0.45, 0.88, 0.27), 1.0, "", false)
	_box(o, Vector3(0.38, 0.62, -0.11), Vector3(0.66, 0.9, 0.11), Color(0.2, 0.18, 0.17), "", false)
	for z: float in [-0.12, 0.12]:
		_box(o, Vector3(0.44, 0.82, z - 0.04), Vector3(0.5, 0.87, z + 0.04), Color(0.2, 0.18, 0.17), "", false)
	_box(o, Vector3(0.37, 0.84, -0.12), Vector3(0.52, 0.94, 0.12), 0.95, "", false)
	return _make(o, ["e4ddcb", "cfc6b0", "b9ae98"], "", 160.0)


## A dog (facing +x): body, head and snout, ears, a tail.
static func _dog() -> Dictionary:
	var o: Array = []
	_legs(o, [-0.25, 0.25], [-0.08, 0.08], 0.38, 0.035, Color(0.32, 0.26, 0.2))
	_box(o, Vector3(-0.36, 0.34, -0.12), Vector3(0.34, 0.6, 0.12), 1.0, "", false)
	_box(o, Vector3(0.3, 0.52, -0.1), Vector3(0.52, 0.74, 0.1), 1.0, "", false)
	_box(o, Vector3(0.52, 0.54, -0.055), Vector3(0.64, 0.64, 0.055), 0.85, "", false)
	_box(o, Vector3(0.62, 0.6, -0.025), Vector3(0.645, 0.64, 0.025), Color(0.1, 0.1, 0.1), "", false)
	for z: float in [-0.07, 0.07]:
		_box(o, Vector3(0.34, 0.74, z - 0.03), Vector3(0.42, 0.84, z + 0.03), 0.8, "", false)
	_bar(o, Vector3(-0.36, 0.56, 0), Vector3(-0.58, 0.74, 0), 0.05, 0.9, "", false)
	return _make(o, ["b8956a", "3a332c", "8a6a45", "d2c6a6"], "", 160.0)


# --- Scenery vehicles (static: not Vehicles; front is +x) ------------------------------------

## Glass on the quad, or an empty frame on a burnt-out hulk.
static func _glass(o: Array, q: Array, inside: Vector3, burnt: bool) -> void:
	_decal(o, q[0], q[1], q[2], q[3], inside, Color("121212") if burnt else GLASS)


## The part of the face b0, b1, t1, t0 (bottom edge, then top edge back the other way: a flat
## trapezoid) from u0 to u1 across and v0 to v1 up: windows that lie on the cabin's own face.
static func _inset(b0: Vector3, b1: Vector3, t1: Vector3, t0: Vector3, u0: float, u1: float, v0: float, v1: float) -> Array:
	var at := func(u: float, v: float) -> Vector3: return b0.lerp(b1, u).lerp(t0.lerp(t1, u), v)
	return [at.call(u0, v0), at.call(u1, v0), at.call(u1, v1), at.call(u0, v1)]


## Four wheels (tyres on hubs; bare rims on a hulk) at x in `xs`, z = ±`wz`, radius `r`.
static func _wheels(o: Array, xs: Array, wz: float, r: float, width: float, burnt: bool) -> void:
	for x: float in xs:
		for s: float in [-1.0, 1.0]:
			if burnt:
				_drum(o, Vector3(x, r * 0.62, s * wz), r * 0.62, width * 0.8, Vector3.BACK, RIM, "steel")
			else:
				_drum(o, Vector3(x, r, s * wz), r, width, Vector3.BACK, TYRE, "tyre")
				_drum(o, Vector3(x, r, s * (wz + width * 0.5 + 0.004)), r * 0.52, 0.004, Vector3.BACK, Color("9a9c9e"), "", false)
				o[o.size() - 1]["decal"] = true


## A cabin (a sloped-sided block from `back` to `front` at the belt, `roof_back` to `roof_front` at
## the roof, `w` and `t` half wide) and its glass: windscreen, rear window, two side windows a side.
static func _cabin(o: Array, back: float, front: float, roof_back: float, roof_front: float, belt: float, roof: float, w: float, t: float, shade: float, burnt: bool, rear_glass := true) -> void:
	_slab(o, back, front, belt, roof, roof, roof_back, roof_front, w, t, shade, "hollow")
	var inside := Vector3((back + front) * 0.5, (belt + roof) * 0.5, 0)
	_glass(o, _inset(Vector3(front, belt, -w), Vector3(front, belt, w), Vector3(roof_front, roof, t), Vector3(roof_front, roof, -t), 0.07, 0.93, 0.1, 0.9), inside, burnt)
	if rear_glass:
		_glass(o, _inset(Vector3(back, belt, -w), Vector3(back, belt, w), Vector3(roof_back, roof, t), Vector3(roof_back, roof, -t), 0.1, 0.9, 0.15, 0.88), inside, burnt)
	for s: float in [-1.0, 1.0]:
		var b0 := Vector3(back, belt, s * w)
		var b1 := Vector3(front, belt, s * w)
		var t1 := Vector3(roof_front, roof, s * t)
		var t0 := Vector3(roof_back, roof, s * t)
		_glass(o, _inset(b0, b1, t1, t0, 0.53, 0.9, 0.12, 0.86), inside, burnt)
		_glass(o, _inset(b0, b1, t1, t0, 0.1, 0.47, 0.12, 0.86), inside, burnt)


## Head and tail lights and a grille on a vertical nose at x = `front` and tail at x = `back`.
static func _lights(o: Array, front: float, back: float, y: float, spread: float) -> void:
	for s: float in [-1.0, 1.0]:
		_paint(o, Vector3(front + DECAL_IN, y, s * spread - 0.13), Vector3(front + DECAL_OUT, y + 0.11, s * spread + 0.13), LAMP)
		_paint(o, Vector3(back - DECAL_OUT, y + 0.04, s * (spread + 0.06) - 0.13), Vector3(back - DECAL_IN, y + 0.14, s * (spread + 0.06) + 0.13), RED)
	_paint(o, Vector3(front + DECAL_IN, y, -spread + 0.17), Vector3(front + DECAL_OUT, y + 0.1, spread - 0.17), DARK)


## A car: a sedan (or a hatchback, `hatch`), or its burnt-out hulk (`burnt`: sat down on bare rims,
## charred, no glass). The engine bay stops rounds (engine); the cabin and boot are thin (hollow).
static func _car(hatch: bool, burnt: bool) -> Dictionary:
	var o: Array = []
	var half := 1.95 if hatch else 2.25
	var drop := 0.18 if burnt else 0.0
	var y0 := 0.32 - drop
	var belt := 0.9 - drop
	var nose := half - 0.95
	var hz := 0.88
	# The engine bay (its hood sloping down to a vertical nose), the body, the boot.
	_slab(o, nose, half, y0, belt, belt - 0.1, nose, half, hz, hz, 1.0, "engine")
	var tail := -half + (0.0 if hatch else 0.9)
	_box(o, Vector3(tail, y0, -hz), Vector3(nose, belt, hz), 1.0, "hollow")
	if not hatch:
		_slab(o, -half, tail, y0, belt - 0.05, belt, -half, tail, hz, hz, 1.0, "hollow")
	var back := -half + (0.12 if hatch else 0.95)
	var front := nose - 0.2
	_cabin(o, back, front, back + (0.15 if hatch else 0.35), front - 0.6, belt, belt + (0.42 if burnt else 0.52), hz - 0.04, hz - 0.16, 0.95 if not burnt else 0.8, burnt)
	var bumper := DARK if not burnt else CHAR
	_box(o, Vector3(half - 0.02, y0 - 0.02, -hz + 0.02), Vector3(half + 0.08, y0 + 0.2, hz - 0.02), bumper, "hollow")
	_box(o, Vector3(-half - 0.08, y0 - 0.02, -hz + 0.02), Vector3(-half + 0.02, y0 + 0.2, hz - 0.02), bumper, "hollow")
	if not burnt:
		_lights(o, half, -half, y0 + 0.3, 0.55)
	else:
		# Scorch and rust down the sides; the hood buckled up.
		_paint(o, Vector3(tail + 0.2, y0 + 0.1, hz + DECAL_IN), Vector3(nose - 0.3, belt - 0.15, hz + DECAL_OUT), RUST)
		_paint(o, Vector3(tail + 0.5, y0 + 0.05, -hz - DECAL_OUT), Vector3(nose - 0.1, belt - 0.2, -hz - DECAL_IN), Color("5c4632"))
		_bar(o, Vector3(nose + 0.1, belt - 0.02, -0.4), Vector3(half - 0.2, belt + 0.12, -0.3), 0.08, CHAR, "hollow")
	_wheels(o, [half - 0.75, -half + 0.72], 0.78, 0.32, 0.22, burnt)
	var palette := ["d8d6cf", "b9bcbf", "8e2b23", "2f4f7a", "c9b48f", "3e5a44", "26282a", "d6a325"]
	if burnt:
		palette = ["2b2723", "3a2e26", "4a3a2e", "352b25"]
	return _make(o, palette, "hollow", SEE_M)


## A panel van (or its burnt hulk): a short engine bay and a tall body, windows only up front.
static func _van(burnt: bool) -> Dictionary:
	var o: Array = []
	var half := 2.45
	var drop := 0.2 if burnt else 0.0
	var y0 := 0.35 - drop
	var belt := 1.0 - drop
	var top := 2.05 - drop
	var hz := 0.96
	_slab(o, 1.7, half, y0, belt, belt - 0.08, 1.7, half, hz, hz, 1.0, "engine")
	_box(o, Vector3(-half, y0, -hz), Vector3(1.7, belt, hz), 1.0, "hollow")
	_slab(o, -half, 1.75, belt, top, top, -half, 1.2, hz, hz - 0.05, 0.96 if not burnt else 0.8, "hollow")
	var inside := Vector3(0, (belt + top) * 0.5, 0)
	_glass(o, _inset(Vector3(1.75, belt, -hz), Vector3(1.75, belt, hz), Vector3(1.2, top, hz - 0.05), Vector3(1.2, top, -hz + 0.05), 0.07, 0.93, 0.1, 0.88), inside, burnt)
	for s: float in [-1.0, 1.0]:
		var b0 := Vector3(-half, belt, s * hz)
		var b1 := Vector3(1.75, belt, s * hz)
		var t1 := Vector3(1.2, top, s * (hz - 0.05))
		var t0 := Vector3(-half, top, s * (hz - 0.05))
		_glass(o, _inset(b0, b1, t1, t0, 0.76, 0.95, 0.12, 0.8), inside, burnt)
		_decal(o, b0.lerp(t0, 0.12), b0.lerp(b1, 0.65).lerp(t0.lerp(t1, 0.65), 0.12), b0.lerp(b1, 0.65).lerp(t0.lerp(t1, 0.65), 0.17), b0.lerp(t0, 0.17), inside, 0.75)
	_paint(o, Vector3(-half - DECAL_OUT, belt + 0.05, -0.012), Vector3(-half - DECAL_IN, top - 0.05, 0.012), DARK)
	var bumper := DARK if not burnt else CHAR
	_box(o, Vector3(half - 0.02, y0 - 0.02, -hz + 0.02), Vector3(half + 0.08, y0 + 0.2, hz - 0.02), bumper, "hollow")
	_box(o, Vector3(-half - 0.08, y0 - 0.02, -hz + 0.02), Vector3(-half + 0.02, y0 + 0.2, hz - 0.02), bumper, "hollow")
	if not burnt:
		_lights(o, half, -half, y0 + 0.3, 0.6)
	else:
		_paint(o, Vector3(-2.0, y0 + 0.1, hz + DECAL_IN), Vector3(1.0, belt - 0.1, hz + DECAL_OUT), RUST)
	_wheels(o, [1.55, -1.6], 0.82, 0.34, 0.23, burnt)
	return _make(o, ["d8d6cf", "c9b48f", "3d5d88", "b9bcbf"] if not burnt else ["2b2723", "3a2e26", "4a3a2e"], "hollow", SEE_M)


## A civilian pickup: engine bay, cab, an open bed with low sides and a tailgate.
static func _pickup() -> Dictionary:
	var o: Array = []
	var hz := 0.92
	_slab(o, 1.4, 2.6, 0.42, 1.02, 0.94, 1.4, 2.6, hz, hz, 1.0, "engine")
	_box(o, Vector3(0.2, 0.42, -hz), Vector3(1.4, 1.02, hz), 1.0, "hollow")
	_cabin(o, 0.2, 1.35, 0.25, 0.8, 1.02, 1.75, hz - 0.04, hz - 0.14, 0.95, false)
	_box(o, Vector3(-2.4, 0.4, -0.5), Vector3(0.2, 0.55, 0.5), DARK, "steel")
	_box(o, Vector3(-2.6, 0.55, -hz + 0.03), Vector3(0.15, 0.62, hz - 0.03), 0.8, "sheet")
	for s: float in [-1.0, 1.0]:
		_box(o, Vector3(-2.6, 0.55, s * hz - 0.03), Vector3(0.15, 1.05, s * hz + 0.03), 1.0, "sheet")
	_box(o, Vector3(-2.6, 0.62, -hz + 0.03), Vector3(-2.54, 1.05, hz - 0.03), 1.0, "sheet")
	_box(o, Vector3(0.1, 0.62, -hz + 0.03), Vector3(0.15, 1.05, hz - 0.03), 0.9, "sheet")
	_box(o, Vector3(2.58, 0.38, -hz + 0.02), Vector3(2.68, 0.6, hz - 0.02), DARK, "hollow")
	_box(o, Vector3(-2.68, 0.38, -hz + 0.02), Vector3(-2.58, 0.55, hz - 0.02), DARK, "hollow")
	_lights(o, 2.6, -2.6, 0.7, 0.6)
	_wheels(o, [1.75, -1.6], 0.82, 0.38, 0.25, false)
	return _make(o, ["d8d6cf", "8e2b23", "c4ae86", "2f4f7a", "6f7376"], "hollow", SEE_M)


## A cab-over lorry with a dropside bed and a canvas tilt (or, `tanker`, a tank), or the burnt-out
## hulk of one (`burnt`: the cab charred and glassless, the bed down to its frame, bare rims).
static func _truck(tanker: bool, burnt: bool) -> Dictionary:
	var o: Array = []
	var hz := 1.22
	var d := 0.25 if burnt else 0.0
	var cab := 1.0 if not burnt else 0.8
	var frame := DARK if not burnt else CHAR
	# Chassis rails the whole length.
	for s: float in [-1.0, 1.0]:
		_box(o, Vector3(-3.8, 0.55 - d, s * 0.6 - 0.07), Vector3(3.0, 0.8 - d, s * 0.6 + 0.07), frame, "steel")
	# The cab: the engine under its front, the cab behind, the upper cab with its windscreen.
	_box(o, Vector3(3.0, 0.8 - d, -hz), Vector3(3.8, 1.6 - d, hz), cab, "engine")
	_box(o, Vector3(2.0, 0.8 - d, -hz), Vector3(3.0, 1.6 - d, hz), cab, "hollow")
	_slab(o, 2.0, 3.8, 1.6 - d, 2.9 - d, 2.9 - d, 2.0, 3.6, hz, hz - 0.06, cab * 0.96, "hollow")
	var inside := Vector3(2.9, 2.2 - d, 0)
	_glass(o, _inset(Vector3(3.8, 1.6 - d, -hz), Vector3(3.8, 1.6 - d, hz), Vector3(3.6, 2.9 - d, hz - 0.06), Vector3(3.6, 2.9 - d, -hz + 0.06), 0.06, 0.94, 0.12, 0.88), inside, burnt)
	for s: float in [-1.0, 1.0]:
		_glass(o, _inset(Vector3(2.0, 1.6 - d, s * hz), Vector3(3.8, 1.6 - d, s * hz), Vector3(3.6, 2.9 - d, s * (hz - 0.06)), Vector3(2.0, 2.9 - d, s * (hz - 0.06)), 0.5, 0.93, 0.1, 0.85), inside, burnt)
	_box(o, Vector3(3.8, 0.5 - d, -hz), Vector3(3.92, 0.85 - d, hz), frame, "steel")
	if not burnt:
		for s: float in [-1.0, 1.0]:
			_paint(o, Vector3(3.8 + DECAL_IN, 1.0, s * 0.85 - 0.14), Vector3(3.8 + DECAL_OUT, 1.15, s * 0.85 + 0.14), LAMP)
		_paint(o, Vector3(3.8 + DECAL_IN, 1.22, -0.6), Vector3(3.8 + DECAL_OUT, 1.5, 0.6), DARK)
	if tanker:
		_box(o, Vector3(-3.6, 0.8, -0.9), Vector3(1.6, 0.95, 0.9), DARK, "steel")
		_drum(o, Vector3(-1.0, 2.1, 0), 1.15, 5.4, Vector3.RIGHT, Color("c9c9c4"), "water")
		_drum(o, Vector3(-1.0, 3.252, 0), 0.25, 0.06, Vector3.UP, GALV, "", false)
	elif burnt:
		# The bed's frame: cross members and the bent headboard frame, the boards burnt away.
		var x := -3.6
		while x < 1.7:
			_box(o, Vector3(x, 0.8 - d, -hz + 0.05), Vector3(x + 0.1, 0.92 - d, hz - 0.05), CHAR, "steel")
			x += 0.9
		_bar(o, Vector3(1.8, 0.92 - d, -hz + 0.05), Vector3(1.75, 2.2 - d, -hz + 0.2), 0.08, CHAR, "steel")
		_bar(o, Vector3(1.8, 0.92 - d, hz - 0.05), Vector3(1.85, 2.1 - d, hz - 0.3), 0.08, CHAR, "steel")
		_paint(o, Vector3(2.1, 0.9 - d, hz + DECAL_IN), Vector3(2.9, 1.5 - d, hz + DECAL_OUT), RUST)
	else:
		_box(o, Vector3(-3.8, 0.8, -hz), Vector3(1.85, 1.0, hz), WOOD, "wood")
		for s: float in [-1.0, 1.0]:
			_box(o, Vector3(-3.8, 1.0, s * hz - 0.04), Vector3(1.8, 1.7, s * hz + 0.04), WOOD_OLD, "wood")
		_box(o, Vector3(-3.8, 1.0, -hz + 0.04), Vector3(-3.74, 1.7, hz - 0.04), WOOD_OLD, "wood")
		_box(o, Vector3(1.8, 1.0, -hz + 0.04), Vector3(1.85, 2.6, hz - 0.04), DARK, "steel")
		_box(o, Vector3(-3.74, 1.7, -hz + 0.04), Vector3(1.8, 2.95, hz - 0.04), Color("5d6347"), "cloth")
		for x: float in [-2.8, -1.4, 0.0, 1.2]:
			for s: float in [-1.0, 1.0]:
				var z := s * (hz - 0.04)
				_paint(o, Vector3(x, 1.72, minf(z + DECAL_IN * s, z + DECAL_OUT * s)), Vector3(x + 0.05, 2.9, maxf(z + DECAL_IN * s, z + DECAL_OUT * s)), Color("4a5038"))
	_wheels(o, [3.0], 1.0, 0.52, 0.32, burnt)
	_wheels(o, [-1.6, -2.85], 0.98, 0.52, 0.4, burnt)
	var palette := ["d8d6cf", "2f4f7a", "8e2b23", "3e6b4f", "c9a238"]
	if burnt:
		palette = ["2b2723", "3a2e26", "4a3a2e"]
	return _make(o, palette, "hollow", SEE_M)


## A farm tractor: big rear wheels, small fronts, the engine hood, a seat, a cab frame with a roof,
## mudguards and an exhaust.
static func _tractor() -> Dictionary:
	var o: Array = []
	for s: float in [-1.0, 1.0]:
		_drum(o, Vector3(-0.6, 0.78, s * 0.95), 0.78, 0.45, Vector3.BACK, TYRE, "tyre")
		_drum(o, Vector3(-0.6, 0.78, s * (0.95 + 0.225 + 0.004)), 0.4, 0.004, Vector3.BACK, Color("c9a238"), "", false)
		o[o.size() - 1]["decal"] = true
		_drum(o, Vector3(1.5, 0.45, s * 0.75), 0.45, 0.25, Vector3.BACK, TYRE, "tyre")
		_box(o, Vector3(-1.35, 1.58, s * 0.95 - 0.26), Vector3(0.15, 1.64, s * 0.95 + 0.26), 1.0, "sheet")
	_box(o, Vector3(0.3, 0.6, -0.42), Vector3(2.0, 1.4, 0.42), 1.0, "engine")
	_box(o, Vector3(-1.0, 0.75, -0.55), Vector3(0.3, 1.2, 0.55), DARK, "steel")
	_box(o, Vector3(-0.8, 1.2, -0.25), Vector3(-0.35, 1.6, 0.25), BLACK, "hollow")
	for x: float in [-1.05, 0.25]:
		for s: float in [-1.0, 1.0]:
			_bar(o, Vector3(x, 1.2, s * 0.62), Vector3(x, 2.6, s * 0.62), 0.06, DARK, "steel")
	_box(o, Vector3(-1.15, 2.6, -0.72), Vector3(0.35, 2.7, 0.72), 1.0, "sheet")
	_post(o, 1.2, 0.3, 1.4, 2.4, 0.05, DARK, "steel")
	_paint(o, Vector3(2.0 + DECAL_IN, 0.75, -0.3), Vector3(2.0 + DECAL_OUT, 1.25, 0.3), DARK)
	return _make(o, ["a33f2e", "3e6b3a", "2f4f7a", "c9a238"], "engine", SEE_M)


## A shipping container `length` long (or two 20 ft stacked, `stack`): corrugated sides, corner
## castings, doors with their locking bars at +x.
static func _container(length: float, stack: bool) -> Dictionary:
	var o: Array = []
	var h := 2.59
	var hx := length * 0.5
	var hz := 1.22
	for level in (2 if stack else 1):
		var y := level * h
		var shift := 0.35 if level == 1 else 0.0
		var shade := 1.0 if level == 0 else 0.82
		_box(o, Vector3(-hx + shift, y, -hz), Vector3(hx + shift, y + h, hz), shade, "container")
		var x := -hx + 0.25
		while x < hx - 0.3:
			for s: float in [-1.0, 1.0]:
				var z := s * hz
				_paint(o, Vector3(x + shift, y + 0.12, minf(z, z + 0.012 * s)), Vector3(x + 0.12 + shift, y + h - 0.12, maxf(z, z + 0.012 * s)), shade * 0.82)
			x += 0.3
		for s: float in [-1.0, 1.0]:
			_paint(o, Vector3(hx + shift + 0.002, y + 0.15, s * 0.6 - 0.02), Vector3(hx + shift + 0.012, y + h - 0.15, s * 0.6 + 0.02), DARK)
			_paint(o, Vector3(hx + shift + 0.002, y + 0.15, s * 0.25 - 0.02), Vector3(hx + shift + 0.012, y + h - 0.15, s * 0.25 + 0.02), DARK)
		_paint(o, Vector3(hx + shift + 0.002, y + 0.1, -0.005), Vector3(hx + shift + 0.006, y + h - 0.1, 0.005), BLACK)
		for cx: float in [-hx - 0.004, hx - 0.176]:
			for cz: float in [-hz - 0.004, hz - 0.18]:
				for cy: float in [y, y + h - 0.15]:
					_paint(o, Vector3(cx + shift, cy, cz), Vector3(cx + 0.18 + shift, cy + 0.15, cz + 0.184), DARK)
	return _make(o, ["8a3b2a", "3d6a8f", "3e6b4f", "b8642a", "6f7376", "c9c9c4", "c9a238"], "container", SEE_BIG_M)


# --- Graves ------------------------------------------------------------------------------------

## A fresh grave: a mound of earth and a stone at its head (+x).
static func _grave_mound() -> Dictionary:
	var o: Array = []
	_slab(o, -1.0, 0.9, 0, 0.3, 0.3, -0.85, 0.75, 0.45, 0.3, EARTH, "earth")
	_box(o, Vector3(0.92, 0, -0.25), Vector3(1.04, 0.62, 0.25), 1.0, "stone")
	return _make(o, ["8f8f88", "6b665c"], "earth", SEE_SMALL_M, PackedVector3Array(), false)


## A headstone on its base, its top tapered, lettered.
static func _headstone() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.35, 0, -0.16), Vector3(0.35, 0.12, 0.16), CONCRETE, "stone")
	_box(o, Vector3(-0.28, 0.12, -0.07), Vector3(0.28, 0.82, 0.07), 1.0, "stone")
	_slab(o, -0.28, 0.28, 0.82, 0.95, 0.95, -0.14, 0.14, 0.07, 0.07, 1.0, "stone")
	for y: float in [0.45, 0.55, 0.65]:
		_paint(o, Vector3(-0.16, y, 0.0702), Vector3(0.16, y + 0.03, 0.0742), 0.55)
	return _make(o, ["8f8f88", "5a5a56", "d8d6cf"], "stone", SEE_SMALL_M, PackedVector3Array(), false)


## A cross over a low mound.
static func _grave_cross() -> Dictionary:
	var o: Array = []
	_slab(o, -1.0, 0.8, 0, 0.18, 0.18, -0.9, 0.7, 0.4, 0.3, EARTH, "earth")
	_box(o, Vector3(0.84, 0, -0.04), Vector3(0.94, 1.15, 0.04), 1.0, "wood")
	_box(o, Vector3(0.84, 0.75, -0.3), Vector3(0.94, 0.84, -0.04), 1.0, "wood")
	_box(o, Vector3(0.84, 0.75, 0.04), Vector3(0.94, 0.84, 0.3), 1.0, "wood")
	return _make(o, ["d8d6cf", "5a4632"], "wood", SEE_SMALL_M, PackedVector3Array(), false)


## A box tomb with its lid and an upright stone at its head.
static func _tomb() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.05, 0, -0.5), Vector3(1.05, 0.55, 0.5), 1.0, "concrete")
	_box(o, Vector3(-1.12, 0.55, -0.57), Vector3(1.12, 0.65, 0.57), 0.92, "concrete")
	_box(o, Vector3(0.9, 0.65, -0.35), Vector3(1.04, 1.25, 0.35), 0.95, "concrete")
	_paint(o, Vector3(-0.8, 0.2, 0.5002), Vector3(0.8, 0.26, 0.5042), 0.6)
	return _make(o, ["e4ddcb", "9a978f", "b8b0a0"], "concrete", SEE_M)


## A plain grave of the arid style: a low border of stones round the earth, a stone at each end.
static func _grave_stele() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.92, 0, -0.32), Vector3(0.92, 0.1, 0.32), EARTH, "earth")
	_box(o, Vector3(-1.0, 0, -0.4), Vector3(1.0, 0.16, -0.32), 1.0, "stone")
	_box(o, Vector3(-1.0, 0, 0.32), Vector3(1.0, 0.16, 0.4), 1.0, "stone")
	_box(o, Vector3(-1.0, 0, -0.32), Vector3(-0.92, 0.16, 0.32), 1.0, "stone")
	_box(o, Vector3(0.92, 0, -0.32), Vector3(1.0, 0.16, 0.32), 1.0, "stone")
	_box(o, Vector3(0.75, 0.1, -0.12), Vector3(0.88, 0.7, 0.12), 0.9, "stone")
	_box(o, Vector3(-0.88, 0.1, -0.1), Vector3(-0.76, 0.45, 0.1), 0.9, "stone")
	return _make(o, ["b8ab8e", "9a8e78", "d2c6a6"], "stone", SEE_SMALL_M, PackedVector3Array(), false)


# --- Sites -------------------------------------------------------------------------------------

## A diesel generator on its skid: a housing, an exhaust, a control panel and vents (+z).
static func _generator() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.2, 0, -0.6), Vector3(1.2, 0.15, 0.6), DARK, "steel")
	_box(o, Vector3(-1.1, 0.15, -0.55), Vector3(1.1, 1.45, 0.55), 1.0, "engine")
	_post(o, 0.8, 0.3, 1.45, 1.95, 0.06, STEEL, "steel")
	_paint(o, Vector3(0.4, 0.6, 0.5502), Vector3(0.95, 1.2, 0.5542), DARK)
	for y: float in [0.5, 0.7, 0.9, 1.1]:
		_paint(o, Vector3(-0.95, y, 0.5502), Vector3(0.1, y + 0.06, 0.5542), 0.6)
	return _make(o, ["c9a238", "586243", "3e6b4f", "d8d6cf"], "engine", SEE_M)


## A satellite dish on a post, looking up and to +z, with its feed arm.
static func _sat_dish() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.2, 0.3), CONCRETE, "concrete")
	_post(o, 0, 0, 0.2, 1.6, 0.05, STEEL, "steel")
	var dir := Vector3(0, 0.57, 0.82).normalized()
	_drum(o, Vector3(0, 1.75, 0.12), 0.6, 0.07, dir, 1.0, "sheet")
	_bar(o, Vector3(0, 1.5, 0.45), Vector3(0, 2.05, 0.68), 0.03, STEEL, "steel")
	_box(o, Vector3(-0.05, 2.0, 0.6), Vector3(0.05, 2.12, 0.74), DARK, "steel")
	return _make(o, ["c9c9c4", "8c9194"], "sheet", SEE_SMALL_M)


## A washing line between two T-posts, washing pegged out on it (the washing is drawn only).
static func _laundry_line() -> Dictionary:
	var o: Array = []
	for x: float in [-2.0, 2.0]:
		_box(o, Vector3(x - 0.03, 0, -0.03), Vector3(x + 0.03, 1.9, 0.03), STEEL, "steel")
		_box(o, Vector3(x - 0.03, 1.85, -0.35), Vector3(x + 0.03, 1.9, 0.35), STEEL, "steel")
	var colours: Array[Color] = [Color("d8d6cf"), Color("3d5d88"), Color("a33f2e"), Color("c9a238"), Color("4d6a55"), Color("8a6a8a")]
	for s: float in [-0.3, 0.3]:
		_bar(o, Vector3(-1.97, 1.86, s), Vector3(1.97, 1.86, s), 0.01, Color("c8c8c0"), "", false)
	var k := 0
	for s: float in [-0.3, 0.3]:
		var x := -1.7 + 0.25 * (k % 2)
		while x < 1.5:
			var w := 0.35 + 0.15 * ((k * 3) % 3)
			var h := 0.45 + 0.2 * ((k * 5) % 3)
			_box(o, Vector3(x, 1.85 - h, s - 0.005), Vector3(minf(x + w, 1.9), 1.85, s + 0.005), colours[k % colours.size()], "", false)
			x += w + 0.25
			k += 1
	return _make(o, [], "steel", SEE_SMALL_M)


## A horizontal fuel tank on two saddles, a manhole and a red band.
static func _fuel_tank() -> Dictionary:
	var o: Array = []
	for x: float in [-1.2, 1.2]:
		_box(o, Vector3(x - 0.2, 0, -0.65), Vector3(x + 0.2, 0.55, 0.65), CONCRETE, "concrete")
	_drum(o, Vector3(0, 1.32, 0), 0.88, 3.6, Vector3.RIGHT, 1.0, "water")
	_drum(o, Vector3(0.6, 2.24, 0), 0.25, 0.08, Vector3.UP, 0.85, "steel")
	_drum(o, Vector3(-0.5, 1.32, 0), 0.892, 0.25, Vector3.RIGHT, RED, "", false)
	o[o.size() - 1]["decal"] = true
	return _make(o, ["d8d6cf", "4d6a55", "8a5b3e"], "water", SEE_M)


## Gas cylinders in a row on a rack, chained.
static func _gas_cylinders() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-1.2, 0, -0.25), Vector3(1.2, 0.05, 0.25), DARK, "steel")
	var x := -1.0
	while x <= 1.01:
		_post(o, x, 0, 0.05, 1.3, 0.14, 1.0, "steel")
		_post(o, x, 0, 1.3, 1.42, 0.06, DARK, "steel")
		x += 0.4
	_bar(o, Vector3(-1.15, 1.0, 0.15), Vector3(1.15, 1.0, 0.15), 0.02, GALV, "", false)
	return _make(o, ["3d5d88", "8c9194", "8a2a22", "c9a238"], "steel", SEE_SMALL_M)


## A stack of five pallets (the gaps between their boards painted on).
static func _pallet_stack() -> Dictionary:
	var o: Array = []
	for k in 5:
		var y := k * 0.15
		_box(o, Vector3(-0.6, y, -0.5), Vector3(0.6, y + 0.145, 0.5), 1.0 - 0.03 * (k % 2), "wood")
		for z: float in [-0.25, 0.05]:
			_paint(o, Vector3(0.6002, y + 0.02, z), Vector3(0.6042, y + 0.1, z + 0.18), DARK)
	return _make(o, ["a08259", "8a7356"], "wood", SEE_SMALL_M, PackedVector3Array(), false)


## Old tyres: a stack of three, a stack of two, one on its own.
static func _tyre_pile() -> Dictionary:
	var o: Array = []
	for spot: Vector3 in [Vector3(0, 0, 0), Vector3(0, 0.22, 0), Vector3(0, 0.44, 0), Vector3(0.78, 0, 0.2), Vector3(0.78, 0.22, 0.2), Vector3(-0.62, 0, -0.55)]:
		_post(o, spot.x, spot.z, spot.y, spot.y + 0.22, 0.36, TYRE, "tyre")
	for top: Vector3 in [Vector3(0, 0.66, 0), Vector3(0.78, 0.44, 0.2), Vector3(-0.62, 0.22, -0.55)]:
		_drum(o, top + Vector3(0, 0.0035, 0), 0.18, 0.003, Vector3.UP, BLACK, "", false)
		o[o.size() - 1]["decal"] = true
	return _make(o, [], "tyre", SEE_SMALL_M, PackedVector3Array(), false)


## A portable latrine: a plastic booth with a pale roof, a door and a vent.
static func _latrine() -> Dictionary:
	var o: Array = []
	_box(o, Vector3(-0.55, 0, -0.55), Vector3(0.55, 2.25, 0.55), 1.0, "hollow")
	_box(o, Vector3(-0.6, 2.25, -0.6), Vector3(0.6, 2.35, 0.6), Color("d8d6cf"), "hollow")
	_paint(o, Vector3(-0.42, 0.05, 0.5502), Vector3(0.42, 2.05, 0.5542), 0.85)
	_paint(o, Vector3(0.25, 1.0, 0.5542), Vector3(0.33, 1.12, 0.5582), DARK)
	return _make(o, ["2e5a8a", "3e6b4f", "6f7376"], "hollow", SEE_SMALL_M)
