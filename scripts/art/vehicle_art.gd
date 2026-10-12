class_name VehicleArt
extends RefCounted
## Voxel vehicle models built in code at 5 cm voxels from their real dimensions:
## UH-60 Black Hawk, AH-1Z Viper, AAV-7, M2 Bradley, M1 Abrams, MRAPs (MaxxPro, M-ATV)
## and pickup technicals with the weapons common in the Middle East.
##
## Each model is a canvas of voxels filled with boxes and rounded cross-sections, then
## meshed once per model and paint scheme and cached. Rotors and gun mounts are separate
## nodes so they can spin. Shapes are drawn in metres (x centred, y up, z back from the
## nose); in the game front is -Z and the origin is the middle of the footprint.

enum P {
	EMPTY, PAINT, PAINT_DARK, PAINT_LIGHT, GLASS, BLACK, METAL, TIRE, TRACK,
	MARKING, LIGHT_RED, LIGHT_GREEN, RUST, SEAT, GUN,
}

## Paint schemes: body colour, darker panels, lighter trim, and markings.
const SCHEMES := {
	"army": {"paint": "3e4536", "marking": "1d1f1a"},
	"marine_gray": {"paint": "5a6168", "marking": "2a2e33"},
	"od": {"paint": "4c5a38", "marking": "1e2318"},
	"desert": {"paint": "b7a27a", "marking": "5a4c33"},
	"white": {"paint": "d8d6cf", "marking": "8a2a22"},
	"tan": {"paint": "c4ae86", "marking": "4a3b2a"},
	"red": {"paint": "8e2b23", "marking": "d8d6cf"},
}
## Models and the schemes they come in (the first is the default).
const MODELS := {
	"uh60": ["army", "od"],
	"ah1z": ["marine_gray"],
	"aav7": ["od", "desert"],
	"maxxpro": ["desert", "od"],
	"matv": ["desert", "od"],
	"technical": ["white", "tan", "red"],
	"technical_dshk": ["white", "tan", "red"],
	"technical_zu23": ["tan", "white", "red"],
	"technical_spg9": ["white", "tan", "red"],
	"technical_m40": ["tan", "white", "red"],
	"technical_rockets": ["white", "tan", "red"],
	"technical_zpu": ["red", "white", "tan"],
	"bradley": ["desert", "od"],
	"abrams": ["desert", "od"],
}

static var _meshes := {}  # "model|scheme" -> Mesh
static var _sizes := {}   # model -> Vector3i canvas size
static var _voxel := {}   # model -> voxel size in metres
static var _rotors := {}  # model -> [[name, position_m, radius, chord, blades, axis]]
static var _meshers := {}
static var _material: StandardMaterial3D
static var _blade_material: StandardMaterial3D


## The whole vehicle: hull mesh plus rotor and weapon nodes. `scheme` "" picks the default.
static func instance(model: String, scheme := "") -> Node3D:
	if scheme == "":
		scheme = MODELS.get(model, ["od"])[0]
	var root := Node3D.new()
	root.name = model
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = mesh(model, scheme)
	hull.material_override = _get_material()
	var vs: float = _voxel[model]
	hull.scale = Vector3.ONE * vs
	var size: Vector3i = _sizes[model]
	hull.position = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5) * vs
	root.add_child(hull)
	# Rotors drawn in metres on the canvas (z from the nose) move to the footprint centre.
	for r: Array in _rotors.get(model, []):
		var at: Vector3 = r[1]
		_add_rotor(root, r[0], Vector3(at.x, at.y, at.z - size.z * vs * 0.5), r[2], r[3], r[4], r[5])
	return root


## Footprint and height in metres.
static func size_m(model: String) -> Vector3:
	if not _sizes.has(model):
		mesh(model, MODELS[model][0])
	return Vector3(_sizes[model]) * float(_voxel[model])


## A static body with a box collider around the hull, for parking vehicles as props.
static func prop(model: String, scheme := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = model
	body.collision_layer = 1
	body.add_child(instance(model, scheme))
	var size := size_m(model)
	var shape := BoxShape3D.new()
	var col := CollisionShape3D.new()
	match model:
		"uh60", "ah1z":
			shape.size = Vector3(minf(size.x, 3.2), 3.4, size.z * 0.62)  # fuselage, not the tail boom or wings
			col.position = Vector3(0, 1.7, -size.z * 0.12)
		_:
			shape.size = size * Vector3(0.95, 0.85, 0.97)
			col.position = Vector3(0, size.y * 0.425, 0)
	col.shape = shape
	body.add_child(col)
	return body


## Turns every rotor under `root`; call each frame while engines run.
static func spin_rotors(root: Node3D, delta: float, rpm := 260.0) -> void:
	for rotor in [root.get_node_or_null(^"MainRotor"), root.get_node_or_null(^"TailRotor")]:
		if rotor:
			var axis: Vector3 = rotor.get_meta(&"axis")
			var speed := rpm * (4.5 if rotor.name == "TailRotor" else 1.0)
			rotor.rotate_object_local(axis, TAU * speed / 60.0 * delta)


static func mesh(model: String, scheme: String) -> Mesh:
	var key := "%s|%s" % [model, scheme]
	if not _meshes.has(key):
		var canvas := _canvas_for(model)
		_sizes[model] = canvas.size
		_voxel[model] = canvas.vs
		_rotors[model] = canvas.rotors
		_meshes[key] = _get_mesher(scheme).build_mesh(canvas.buffer, [])
	return _meshes[key]


static func _canvas_for(model: String) -> Canvas:
	match model:
		"uh60": return _uh60()
		"ah1z": return _ah1z()
		"aav7": return _aav7()
		"maxxpro": return _maxxpro()
		"matv": return _matv()
		"technical": return _technical("dshk")
		"bradley": return _bradley()
		"abrams": return _abrams()
	if model.begins_with("technical_"):
		return _technical(model.trim_prefix("technical_"))
	push_error("VehicleArt: unknown model '%s'" % model)
	return Canvas.new(Vector3i.ONE)


static func _add_rotor(root: Node3D, rotor_name: String, at: Vector3, radius: float, chord: float, blades: int, axis: Vector3) -> void:
	if _blade_material == null:
		_blade_material = StandardMaterial3D.new()
		_blade_material.albedo_color = Color("222421")
		_blade_material.roughness = 0.7
	var rotor := Node3D.new()
	rotor.name = rotor_name
	rotor.position = at
	rotor.set_meta(&"axis", axis)
	root.add_child(rotor)
	# Blades lie in the plane perpendicular to the axis.
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	for i in blades:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(radius, 0.05, chord)
		box.material = _blade_material
		blade.mesh = box
		var spin := Basis(Vector3.UP, TAU * i / blades)
		blade.transform = Transform3D(basis * spin, basis * spin * Vector3(radius * 0.5, 0, 0))
		rotor.add_child(blade)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.22
	cyl.height = 0.3
	cyl.material = _blade_material
	hub.mesh = cyl
	hub.basis = basis
	rotor.add_child(hub)


static func _get_mesher(scheme: String) -> VoxelMesherCubes:
	if not _meshers.has(scheme):
		var s: Dictionary = SCHEMES.get(scheme, SCHEMES["od"])
		var paint := Color(s.paint)
		var colours := {
			P.EMPTY: Color(0, 0, 0, 0), P.PAINT: paint, P.PAINT_DARK: paint.darkened(0.22),
			P.PAINT_LIGHT: paint.lightened(0.12), P.GLASS: Color("27343c"), P.BLACK: Color("161716"),
			P.METAL: Color("6e6f6a"), P.TIRE: Color("1c1c1b"), P.TRACK: Color("2a2926"),
			P.MARKING: Color(s.marking), P.LIGHT_RED: Color("c0281e"), P.LIGHT_GREEN: Color("2ea043"),
			P.RUST: Color("7a4a2a"), P.SEAT: Color("3b3a33"), P.GUN: Color("262626"),
		}
		var palette := VoxelColorPalette.new()
		for index: int in colours:
			palette.set_color(index, colours[index])
		var mesher := VoxelMesherCubes.new()
		mesher.palette = palette
		mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
		mesher.greedy_meshing_enabled = false  # greedy quads leave hairline cracks at 5 cm
		_meshers[scheme] = mesher
	return _meshers[scheme]


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
	return _material


# --- Canvas -----------------------------------------------------------------------------

## One cross-section for Canvas.mhull, in metres.
class Section:
	var cx := 0.0
	var bottom := 0.0
	var top := 1.0
	var half_bottom := 1.0  ## half width at the bottom
	var half_top := 1.0     ## half width at the top
	var r_bottom := 0.0     ## lower corner radius
	var r_top := 0.0        ## upper corner radius

	func _init(p_bottom: float, p_top: float, p_half_bottom: float, p_half_top: float, p_r_bottom: float, p_r_top: float, p_cx := 0.0) -> void:
		bottom = p_bottom
		top = p_top
		half_bottom = p_half_bottom
		half_top = p_half_top
		var h := (top - bottom) * 0.5
		r_bottom = minf(minf(p_r_bottom, h), minf(half_bottom, half_top))
		r_top = minf(minf(p_r_top, h), minf(half_bottom, half_top))
		cx = p_cx

	## Scales the whole section towards (cx, centre_y) by k, for rounding off a nose or tail.
	func scaled(k: float, centre_y: float) -> Section:
		return Section.new(lerpf(centre_y, bottom, k), lerpf(centre_y, top, k), half_bottom * k, half_top * k, r_bottom * k, r_top * k, cx)

	func half_width_at(y: float) -> float:
		if y < bottom or y > top:
			return 0.0
		var w := lerpf(half_bottom, half_top, (y - bottom) / (top - bottom))
		var d := y - bottom
		if d < r_bottom:
			w -= r_bottom - sqrt(maxf(r_bottom * r_bottom - (r_bottom - d) * (r_bottom - d), 0.0))
		d = top - y
		if d < r_top:
			w -= r_top - sqrt(maxf(r_top * r_top - (r_top - d) * (r_top - d), 0.0))
		return w


## A voxel buffer with drawing helpers. Coordinates exclude the 1-voxel mesher padding.
class Canvas:
	var size: Vector3i
	var buffer := VoxelBuffer.new()
	## Voxel size in metres.
	var vs := 0.1
	## Rotors to add as separate nodes: [name, position_m, radius, chord, blades, axis].
	var rotors: Array = []

	func _init(p_size: Vector3i, p_vs := 0.1) -> void:
		size = p_size
		vs = p_vs
		buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
		buffer.create(size.x + 2, size.y + 2, size.z + 2)
		buffer.fill(VehicleArt.P.EMPTY, VoxelBuffer.CHANNEL_COLOR)

	# Metre-space drawing: x is centred (negative = left), y up from the ground, z back from
	# the nose. Everything below converts to voxels at this canvas's size.

	func _vx(x: float) -> int:
		return floori(x / vs + size.x * 0.5)

	func _v(m: float) -> int:
		return floori(m / vs)

	func mbox(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> void:
		box(_vx(x0), _v(y0), _v(z0), maxi(_vx(x1), _vx(x0) + 1), maxi(_v(y1), _v(y0) + 1), maxi(_v(z1), _v(z0) + 1), colour)

	## Rounded cross-sections along z, in metres. profile(z_m) -> Vector4(centre_x, centre_y,
	## half_width, half_height). With `shell` > 0 only a skin that thick is filled (big hulls).
	func mloft(z0: float, z1: float, profile: Callable, colour: int, squareness := 2.6, shell := 0.0) -> void:
		for zi in range(_v(z0), _v(z1)):
			var p: Vector4 = profile.call((zi + 0.5) * vs)
			if p.z <= 0.0 or p.w <= 0.0:
				continue
			var inner_w := p.z - shell
			var inner_h := p.w - shell
			for xi in range(_vx(p.x - p.z), _vx(p.x + p.z) + 1):
				var x := (xi + 0.5 - size.x * 0.5) * vs
				var dx := absf((x - p.x) / p.z)
				if dx > 1.0:
					continue
				for yi in range(_v(p.y - p.w), _v(p.y + p.w) + 1):
					var y := (yi + 0.5) * vs
					var dy := absf((y - p.y) / p.w)
					if pow(dx, squareness) + pow(dy, squareness) > 1.0:
						continue
					if shell > 0.0 and inner_w > 0.0 and inner_h > 0.0 \
							and pow(absf((x - p.x) / inner_w), squareness) + pow(absf((y - p.y) / inner_h), squareness) < 1.0:
						continue
					put(xi, yi, zi, colour)

	## Aircraft-style hull sections along z, in metres. `section(z_m)` returns a Section: a
	## flat-bottomed, flat-topped shape whose sides lean in or out between the bottom and top
	## widths, with its lower and upper corners rounded. With `shell` > 0 only a skin that thick
	## is filled.
	func mhull(z0: float, z1: float, section: Callable, colour: int, shell := 0.0) -> void:
		for zi in range(_v(z0), _v(z1)):
			var s: VehicleArt.Section = section.call((zi + 0.5) * vs)
			if s == null or s.top <= s.bottom or s.half_bottom <= 0.0:
				continue
			for yi in range(_v(s.bottom), _v(s.top) + 1):
				var y := (yi + 0.5) * vs
				var w := s.half_width_at(y)
				if w <= 0.0:
					continue
				var inner := 0.0
				if shell > 0.0 and y > s.bottom + shell and y < s.top - shell:
					inner = s.half_width_at(y) - shell
				for xi in range(_vx(s.cx - w), _vx(s.cx + w) + 1):
					var dx := absf((xi + 0.5 - size.x * 0.5) * vs - s.cx)
					if dx <= w and (inner <= 0.0 or dx >= inner):
						put(xi, yi, zi, colour)

	## Upright cylinder (masts, hubs, hatches) centred on (cx, cz) from y0 to y1, in metres.
	func mdisc(cx: float, cz: float, r: float, y0: float, y1: float, colour: int) -> void:
		for yi in range(_v(y0), maxi(_v(y1), _v(y0) + 1)):
			for xi in range(_vx(cx - r), _vx(cx + r) + 1):
				for zi in range(_v(cz - r), _v(cz + r) + 1):
					if Vector2((xi + 0.5 - size.x * 0.5) * vs - cx, (zi + 0.5) * vs - cz).length() <= r:
						put(xi, yi, zi, colour)

	## Wheel: a cylinder across x from x0 to x1 (metres), centre (cy, cz), radius r.
	func mwheel(x0: float, x1: float, cy: float, cz: float, r: float, colour := VehicleArt.P.TIRE, hub := VehicleArt.P.METAL) -> void:
		for xi in range(_vx(x0), maxi(_vx(x1), _vx(x0) + 1)):
			for yi in range(_v(cy - r), _v(cy + r) + 1):
				for zi in range(_v(cz - r), _v(cz + r) + 1):
					var d := Vector2((yi + 0.5) * vs - cy, (zi + 0.5) * vs - cz).length()
					if d <= r:
						put(xi, yi, zi, hub if d <= r * 0.5 else colour)

	func mskin(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int, match_colour := -1) -> void:
		paint_skin(_vx(x0), _v(y0), _v(z0), _vx(x1), _v(y1), _v(z1), colour, match_colour)

	## A straight bar between two points (struts, antennas), `thick` metres square.
	func mbar(a: Vector3, b: Vector3, thick: float, colour: int) -> void:
		var steps := maxi(ceili(a.distance_to(b) / (vs * 0.5)), 1)
		for i in steps + 1:
			var p := a.lerp(b, float(i) / steps)
			mbox(p.x - thick * 0.5, p.y - thick * 0.5, p.z - thick * 0.5, p.x + thick * 0.5, p.y + thick * 0.5, p.z + thick * 0.5, colour)

	func rotor(rotor_name: String, at_m: Vector3, radius: float, chord: float, blades: int, axis: Vector3) -> void:
		rotors.append([rotor_name, at_m, radius, chord, blades, axis])

	func inside(x: int, y: int, z: int) -> bool:
		return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z

	func put(x: int, y: int, z: int, colour: int) -> void:
		if inside(x, y, z):
			buffer.set_voxel(colour, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)

	func get_at(x: int, y: int, z: int) -> int:
		return buffer.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) if inside(x, y, z) else VehicleArt.P.EMPTY

	## Solid box, `to` exclusive.
	func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int) -> void:
		for x in range(maxi(x0, 0), mini(x1, size.x)):
			for y in range(maxi(y0, 0), mini(y1, size.y)):
				for z in range(maxi(z0, 0), mini(z1, size.z)):
					buffer.set_voxel(colour, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)

	## A body of rounded (superellipse) cross-sections along z. `profile(t)` with t 0..1 from
	## z0 to z1 returns Vector4(centre_x, centre_y, half_width, half_height).
	func loft(z0: int, z1: int, profile: Callable, colour: int, squareness := 2.6) -> void:
		for z in range(z0, z1):
			var p: Vector4 = profile.call(float(z - z0) / maxf(z1 - z0 - 1, 1))
			if p.z <= 0.0 or p.w <= 0.0:
				continue
			for x in range(floori(p.x - p.z), ceili(p.x + p.z) + 1):
				for y in range(floori(p.y - p.w), ceili(p.y + p.w) + 1):
					var dx := absf((x + 0.5 - p.x) / p.z)
					var dy := absf((y + 0.5 - p.y) / p.w)
					if pow(dx, squareness) + pow(dy, squareness) <= 1.0:
						put(x, y, z, colour)

	## Cylinder along x (wheels): centre (cy, cz), radius, from x0 to x1.
	func wheel(x0: int, x1: int, cy: float, cz: float, radius: float, colour := VehicleArt.P.TIRE, hub := VehicleArt.P.METAL) -> void:
		for x in range(x0, x1):
			for y in range(floori(cy - radius), ceili(cy + radius) + 1):
				for z in range(floori(cz - radius), ceili(cz + radius) + 1):
					var d := Vector2(y + 0.5 - cy, z + 0.5 - cz).length()
					if d <= radius:
						put(x, y, z, hub if d <= radius * 0.45 else colour)

	## Recolours the outer skin (voxels with an empty neighbour) inside a box: windows, doors,
	## markings. `match_colour` -1 recolours any skin voxel.
	func paint_skin(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int, match_colour := -1) -> void:
		for x in range(maxi(x0, 0), mini(x1, size.x)):
			for y in range(maxi(y0, 0), mini(y1, size.y)):
				for z in range(maxi(z0, 0), mini(z1, size.z)):
					var current := get_at(x, y, z)
					if current == VehicleArt.P.EMPTY or (match_colour >= 0 and current != match_colour):
						continue
					if get_at(x + 1, y, z) == VehicleArt.P.EMPTY or get_at(x - 1, y, z) == VehicleArt.P.EMPTY or get_at(x, y + 1, z) == VehicleArt.P.EMPTY \
							or get_at(x, y - 1, z) == VehicleArt.P.EMPTY or get_at(x, y, z + 1) == VehicleArt.P.EMPTY or get_at(x, y, z - 1) == VehicleArt.P.EMPTY:
						put(x, y, z, colour)

	## Mirrors the left half (x < size.x / 2) onto the right.
	func mirror_x() -> void:
		var half := size.x / 2
		for x in half:
			for y in size.y:
				for z in size.z:
					put(size.x - 1 - x, y, z, get_at(x, y, z))


# --- Helicopters ------------------------------------------------------------------------

## UH-60M Black Hawk at 5 cm voxels, matched to reference photos and the real dimensions:
## 15.26 m fuselage, a 2.36 m cabin whose sides lean in towards the roof, a bulbous nose under
## the steep two-pane windscreen and overhead windows, the long upper deck with an engine
## nacelle on each shoulder (round intakes forward, IR exhaust suppressors angled out aft),
## the boom rising into a swept pylon with the tail rotor canted 20 degrees on its right, the
## wide stabilator low on the pylon, main wheels under the cockpit's rear on a shock strut and
## a long drag beam, and the tail wheel under the boom.
static func _uh60() -> Canvas:
	var c := Canvas.new(Vector3i(96, 86, 316), 0.05)
	var body := func(z: float) -> Section:
		var bottom := 0.5
		var top := 2.22
		var hw := 1.18
		var lean := 0.24  # the roof is this much narrower than the floor line on each side
		var rb := 0.3
		var rt := 0.45
		if z < 2.4:  # nose, windscreen and cockpit
			if z < 1.15:
				top = lerpf(1.22, 1.62, sqrt(z / 1.15))
			else:
				top = lerpf(1.62, 2.22, 1.0 - pow(1.0 - clampf((z - 1.15) / 1.0, 0.0, 1.0), 2.0))
			bottom = lerpf(0.85, 0.5, smoothstep(0.0, 2.0, z))
			hw = lerpf(0.86, 1.18, sqrt(clampf(z / 2.4, 0.0, 1.0)))
			lean = lerpf(0.5, 0.24, smoothstep(1.0, 2.3, z))
			rb = lerpf(0.5, 0.3, clampf(z / 2.0, 0.0, 1.0))
			rt = lerpf(0.45, 0.45, clampf(z / 2.0, 0.0, 1.0))
		elif z > 8.0:  # aft cabin sweeping up into the boom, then the boom tapering
			var e := smoothstep(8.0, 10.8, z)
			var b := clampf((z - 10.8) / 3.4, 0.0, 1.0)
			bottom = lerpf(0.5, 1.5, e) + 0.3 * b
			top = lerpf(2.22, 2.2, e) - 0.1 * b
			hw = lerpf(1.18, 0.44, e) - 0.14 * b
			lean = lerpf(0.24, 0.06, e)
			rb = lerpf(0.3, 0.5, e)
			rt = lerpf(0.45, 0.5, e)
		var s := Section.new(bottom, top, hw, hw - lean, rb, rt)
		if z < 0.6:  # round off the nose tip
			s = s.scaled(maxf(sqrt(1.0 - pow(1.0 - z / 0.6, 2.0)), 0.25), (top + bottom) * 0.5 - 0.05)
		elif z > 14.0:  # close off the tail cone behind the pylon
			s = s.scaled(maxf(sqrt(1.0 - pow((z - 14.0) / 0.45, 2.0)), 0.2), (top + bottom) * 0.5)
		return s
	c.mhull(0.0, 14.45, body, P.PAINT, 0.12)
	# Upper deck: the cowl behind the cockpit, flat over the engines and gearbox, then a long
	# fairing tapering down into the boom.
	var deck := func(z: float) -> Section:
		var top := 2.66
		var hw := 0.92
		if z < 3.6:
			var k := smoothstep(2.45, 3.6, z)
			top = lerpf(2.2, 2.66, sqrt(k))
			hw = lerpf(0.6, 0.92, k)
		elif z > 8.6:
			var k := smoothstep(8.6, 11.6, z)
			top = lerpf(2.66, 2.15, k)
			hw = lerpf(0.92, 0.26, k)
		return Section.new(1.9, top, hw, hw - 0.22, 0.0, 0.4)
	c.mhull(2.45, 11.6, deck, P.PAINT, 0.12)
	c.mskin(-0.7, 2.56, 6.3, 0.7, 2.7, 7.6, P.PAINT_DARK, P.PAINT)  # oil cooler exhaust
	for gz: float in [6.45, 6.75, 7.05, 7.35]:
		c.mskin(-0.5, 2.6, gz, 0.5, 2.7, gz + 0.1, P.BLACK, P.PAINT_DARK)
	c.mbox(0.36, 2.5, 9.0, 0.56, 2.62, 9.2, P.BLACK)  # APU exhaust
	# Engine nacelles on the shoulders: round intakes forward, IR suppressors angled out aft.
	for side: float in [-1.0, 1.0]:
		var nx := side * 0.8
		c.mbox(minf(side * 0.55, side * 1.0), 2.15, 4.2, maxf(side * 0.55, side * 1.0), 2.6, 7.6, P.PAINT)
		var nacelle := func(z: float) -> Vector4:
			var r := 0.37 if z < 4.15 else 0.35
			return Vector4(nx, 2.64, r, r)
		c.mloft(3.95, 7.75, nacelle, P.PAINT, 2.0)
		var intake := func(_z: float) -> Vector4: return Vector4(nx, 2.64, 0.27, 0.27)
		c.mloft(3.95, 4.05, intake, P.BLACK, 2.0)
		var spinner := func(z: float) -> Vector4:
			var r := lerpf(0.04, 0.11, clampf((z - 3.9) / 0.15, 0.0, 1.0))
			return Vector4(nx, 2.64, r, r)
		c.mloft(3.9, 4.05, spinner, P.METAL, 2.0)
		for seam: float in [5.1, 6.45]:  # cowling seams
			c.mskin(minf(side * 0.5, side * 1.2), 2.25, seam, maxf(side * 0.5, side * 1.2), 3.05, seam + 0.05, P.PAINT_DARK, P.PAINT)
		var hirss := func(z: float) -> Vector4:
			return Vector4(side * (0.82 + (z - 7.6) * 0.32), 2.64, 0.24, 0.3)
		c.mloft(7.6, 8.95, hirss, P.PAINT_DARK, 4.0)
		for lz: float in [7.9, 8.2, 8.5]:
			c.mskin(-1.5, 2.4, lz, 1.5, 2.96, lz + 0.05, P.BLACK, P.PAINT_DARK)
		var outlet := func(z: float) -> Vector4:
			return Vector4(side * (0.82 + (z - 7.6) * 0.32), 2.64, 0.18, 0.24)
		c.mloft(8.9, 8.95, outlet, P.BLACK, 4.0)
	# Main rotor mast, swashplate and hub; the blades turn on the MainRotor node.
	c.mdisc(0.0, 5.25, 0.3, 2.64, 2.85, P.PAINT_DARK)
	c.mdisc(0.0, 5.25, 0.17, 2.85, 3.62, P.METAL)
	c.mdisc(0.0, 5.25, 0.4, 3.22, 3.3, P.METAL)
	for side: float in [-1.0, 1.0]:  # pitch links
		c.mbox(side * 0.3 - 0.03, 3.3, 5.22, side * 0.3 + 0.03, 3.6, 5.28, P.METAL)
		c.mbox(-0.03, 3.3, 5.25 + side * 0.3 - 0.03, 0.03, 3.6, 5.25 + side * 0.3 + 0.03, P.METAL)
	c.mdisc(0.0, 5.25, 0.34, 3.58, 3.74, P.BLACK)
	c.rotor("MainRotor", Vector3(0.0, 3.82, 5.25), 8.18, 0.53, 4, Vector3.UP)
	# Swept tail pylon with the gearbox fairing on top; tail rotor canted 20 degrees on its right.
	var y := 1.5
	while y < 4.15:
		var le := 13.15 + maxf(y - 2.1, 0.0) * 0.72 + maxf(2.1 - y, 0.0) * 0.9
		var te := 14.3 + (y - 1.5) * 0.34
		var t := lerpf(0.18, 0.11, (y - 1.5) / 2.65)
		c.mbox(-t, y, le, t, y + c.vs, te, P.PAINT)
		y += c.vs
	var cap := func(z: float) -> Vector4:
		var k := clampf((z - 14.55) / 0.75, 0.0, 1.0)
		return Vector4(0.0, 4.12, 0.15 * sin(PI * k) + 0.02, 0.17 * sin(PI * k) + 0.02)
	c.mloft(14.55, 15.3, cap, P.PAINT, 2.2)
	c.mbox(0.12, 3.48, 14.6, 0.36, 3.76, 14.92, P.METAL)  # tail rotor gearbox
	c.mskin(-0.25, 3.7, 14.65, 0.25, 3.78, 14.9, P.PAINT_DARK, P.PAINT)
	var cant := deg_to_rad(20.0)
	c.rotor("TailRotor", Vector3(0.42, 3.62, 14.76), 1.68, 0.25, 4, Vector3(cos(cant), sin(cant), 0.0))
	c.mbox(-0.04, 4.1, 15.2, 0.04, 4.18, 15.32, P.PAINT_LIGHT)  # tail light
	# Stabilator: the full-width tailplane low on the pylon, slightly thicker at its spar.
	c.mbox(-2.19, 1.42, 13.8, 2.19, 1.5, 14.82, P.PAINT)
	c.mbox(-2.15, 1.4, 13.85, 2.15, 1.53, 14.3, P.PAINT)
	c.mbox(-0.22, 1.36, 13.6, 0.22, 1.56, 14.9, P.PAINT)  # root fairing
	# Glass: windscreen and overhead windows, cockpit door windows above and below, gunner's
	# windows, the two windows in each sliding cabin door.
	c.mskin(-1.0, 1.6, 1.05, 1.0, 2.18, 2.15, P.GLASS)
	c.mskin(-0.55, 2.15, 2.1, 0.55, 2.3, 2.45, P.GLASS)
	c.mskin(-0.04, 1.6, 1.1, 0.04, 2.3, 2.45, P.PAINT_DARK)  # centre post
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 0.92, side * 1.4)
		var ix := maxf(side * 0.92, side * 1.4)
		c.mskin(ox, 1.6, 1.05, ix, 2.3, 1.3, P.PAINT_DARK)  # windscreen side post
		c.mskin(ox, 1.38, 1.3, ix, 2.14, 2.45, P.GLASS)  # cockpit door window
		c.mskin(ox, 0.78, 1.55, ix, 1.3, 2.38, P.GLASS)  # lower door window
		c.mskin(ox, 0.65, 2.48, ix, 2.18, 2.55, P.PAINT_DARK, P.PAINT)  # door rear edge
		c.mskin(ox, 1.45, 2.95, ix, 2.08, 3.55, P.GLASS)  # gunner's window
		c.mskin(ox, 1.4, 2.88, ix, 2.14, 2.95, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 1.4, 3.55, ix, 2.14, 3.62, P.PAINT_DARK, P.PAINT)
		# Sliding cabin door: outline, the rail it runs back on, windows and the step.
		c.mskin(ox, 0.62, 4.3, ix, 2.15, 4.36, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 0.62, 6.42, ix, 2.15, 6.48, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 0.62, 4.3, ix, 0.68, 6.48, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 2.13, 4.3, ix, 2.2, 7.4, P.BLACK, P.PAINT)
		c.mskin(ox, 1.45, 4.55, ix, 1.98, 5.2, P.GLASS)
		c.mskin(ox, 1.45, 5.6, ix, 1.98, 6.25, P.GLASS)
		c.mbox(minf(side * 1.12, side * 1.3), 0.55, 4.6, maxf(side * 1.12, side * 1.3), 0.6, 5.3, P.METAL)
		c.mskin(ox, 0.9, 7.55, ix, 1.85, 7.6, P.PAINT_DARK, P.PAINT)  # aft fuselage seam
		# Chaff and flare dispensers on the boom.
		c.mbox(minf(side * 0.36, side * 0.54), 1.7, 10.4, maxf(side * 0.36, side * 0.54), 1.95, 10.9, P.PAINT_DARK)
		# M240H on the gunner's window mount, barrel stowed forward.
		var gx := side * 1.4
		c.mbar(Vector3(side * 1.18, 1.6, 3.62), Vector3(gx, 1.76, 3.45), 0.06, P.METAL)
		c.mbox(gx - 0.05, 1.75, 3.0, gx + 0.05, 1.89, 3.72, P.GUN)
		c.mbox(gx - 0.04, 1.77, 3.72, gx + 0.04, 1.85, 3.95, P.GUN)
		c.mbox(gx - 0.025, 1.8, 2.25, gx + 0.025, 1.84, 3.0, P.GUN)
		c.mbox(gx - 0.035, 1.78, 2.2, gx + 0.035, 1.86, 2.3, P.GUN)
		c.mbox(gx - 0.06, 1.58, 3.3, gx + 0.06, 1.75, 3.55, P.SEAT)  # ammo bag
		# Main gear: wheel under the cockpit's rear, shock strut up to the fuselage and the long
		# drag beam running forward to the belly.
		c.mbox(minf(side * 1.06, side * 1.24), 0.95, 3.9, maxf(side * 1.06, side * 1.24), 1.4, 4.4, P.PAINT_DARK)
		c.mbar(Vector3(side * 1.18, 1.1, 4.12), Vector3(side * 1.24, 0.36, 4.05), 0.12, P.METAL)
		c.mbar(Vector3(side * 0.92, 0.6, 2.25), Vector3(side * 1.22, 0.36, 4.05), 0.13, P.PAINT_DARK)
		c.mwheel(minf(side * 1.27, side * 1.49), maxf(side * 1.27, side * 1.49), 0.33, 4.05, 0.33)
		# Pitot probes on the cockpit roof.
		c.mbar(Vector3(side * 0.42, 2.2, 2.3), Vector3(side * 0.42, 2.4, 2.2), 0.04, P.METAL)
		c.mbar(Vector3(side * 0.42, 2.4, 2.2), Vector3(side * 0.42, 2.4, 1.75), 0.04, P.METAL)
		# Nav lights on the cabin's upper corners.
		c.mbox(minf(side * 1.0, side * 1.08), 2.05, 3.7, maxf(side * 1.0, side * 1.08), 2.13, 3.82, P.LIGHT_RED if side < 0.0 else P.LIGHT_GREEN)
	# Tail wheel on a trailing strut under the boom.
	c.mbar(Vector3(0.0, 1.72, 12.25), Vector3(0.0, 0.34, 12.8), 0.1, P.METAL)
	c.mbar(Vector3(0.0, 1.76, 13.15), Vector3(0.0, 0.36, 12.82), 0.07, P.METAL)
	c.mwheel(-0.07, 0.07, 0.22, 12.85, 0.22)
	for fx: float in [-0.1, 0.08]:
		c.mbox(fx, 0.2, 12.75, fx + 0.03, 0.42, 12.95, P.METAL)
	# Wire strike cutters above the cockpit and under the nose, belly light and antennas,
	# anti-collision beacons, boom seams.
	c.mbar(Vector3(0.0, 2.22, 2.42), Vector3(0.0, 2.56, 2.05), 0.05, P.METAL)
	c.mbar(Vector3(0.0, 0.6, 1.15), Vector3(0.0, 0.42, 0.8), 0.05, P.METAL)
	c.mskin(-0.25, 0.45, 1.3, 0.25, 0.6, 1.6, P.GLASS)
	c.mbox(-0.02, 0.32, 6.6, 0.02, 0.52, 6.9, P.PAINT_DARK)
	c.mbar(Vector3(0.0, 2.35, 10.0), Vector3(0.0, 2.85, 10.6), 0.04, P.METAL)
	c.mbox(-0.02, 2.05, 12.1, 0.02, 2.3, 12.45, P.PAINT_DARK)
	c.mbox(-0.06, 2.62, 8.85, 0.06, 2.7, 8.97, P.LIGHT_RED)
	c.mbox(-0.06, 0.44, 7.2, 0.06, 0.5, 7.32, P.LIGHT_RED)
	for seam: float in [10.3, 11.6, 12.8]:
		c.mskin(-1.0, 1.4, seam, 1.0, 2.35, seam + 0.05, P.PAINT_DARK, P.PAINT)
	return c




## AH-1Z Viper: a narrow, tall fuselage (under 1 m wide) with avionics bays bulging its lower
## sides, the target sight turret on the nose, the M197 three-barrel 20 mm turret under the
## chin, a flat-panelled stepped tandem canopy (gunner in front and lower), engines high on
## either side of the transmission with IR suppressors turned up, stub wings carrying rocket
## pods inboard, quad Hellfire racks outboard and Sidewinders on the tips, a slim boom with
## end-plated elevators, a swept fin with the tail rotor on its right, and high skids.
static func _ah1z() -> Canvas:
	var c := Canvas.new(Vector3i(100, 88, 280), 0.05)
	var body := func(z: float) -> Section:
		var bottom := 0.72
		var top := 2.0
		var hw := 0.62  # bottom half width (avionics bays)
		var lean := 0.17
		if z < 1.6:  # nose under the sight turret
			var k := clampf((z - 0.45) / 1.15, 0.0, 1.0)
			bottom = lerpf(0.95, 0.72, k)
			top = lerpf(1.42, 1.62, sqrt(k))
			hw = lerpf(0.36, 0.62, sqrt(k))
			lean = lerpf(0.08, 0.17, k)
		elif z > 8.8:  # aft body sweeping up into the boom
			var e := smoothstep(8.8, 10.6, z)
			var b := clampf((z - 10.6) / 2.9, 0.0, 1.0)
			bottom = lerpf(0.72, 1.45, e) + 0.25 * b
			top = lerpf(2.0, 1.98, e) + 0.02 * b
			hw = lerpf(0.55, 0.3, e) - 0.13 * b
			lean = lerpf(0.1, 0.03, e)
		elif z > 6.0:
			hw = lerpf(0.62, 0.55, clampf((z - 6.0) / 2.8, 0.0, 1.0))
			lean = lerpf(0.17, 0.1, clampf((z - 6.0) / 2.8, 0.0, 1.0))
		var s := Section.new(bottom, top, hw, hw - lean, 0.18, 0.12)
		if z > 13.2:
			s = s.scaled(maxf(sqrt(1.0 - pow((z - 13.2) / 0.35, 2.0)), 0.2), (top + bottom) * 0.5)
		return s
	c.mhull(0.45, 13.55, body, P.PAINT, 0.1)
	# Stepped tandem canopy: flat panels, gunner in front, pilot raised behind.
	var canopy := func(z: float) -> Section:
		var top := 2.0
		if z < 3.25:
			top = lerpf(1.62, 2.22, clampf((z - 1.45) / 0.9, 0.0, 1.0))
		elif z < 4.75:
			top = lerpf(2.22, 2.48, clampf((z - 3.25) / 0.35, 0.0, 1.0))
		if z > 4.25:
			top = lerpf(2.48, 2.08, clampf((z - 4.25) / 0.7, 0.0, 1.0))
		return Section.new(1.5, top, 0.46, 0.3, 0.0, 0.1)
	c.mhull(1.45, 5.0, canopy, P.PAINT, 0.08)
	c.mskin(-0.6, 1.6, 1.45, 0.6, 2.5, 4.55, P.GLASS)
	c.mskin(-0.6, 1.55, 3.18, 0.6, 2.5, 3.3, P.PAINT_DARK)  # frame between the cockpits
	c.mskin(-0.6, 1.55, 4.5, 0.6, 2.5, 4.6, P.PAINT_DARK)
	c.mskin(-0.04, 2.0, 1.45, 0.04, 2.5, 4.6, P.PAINT_DARK)  # spine of the canopy
	for side: float in [-1.0, 1.0]:
		c.mskin(minf(side * 0.3, side * 0.6), 1.55, 1.45, maxf(side * 0.3, side * 0.6), 1.62, 4.6, P.PAINT_DARK)  # sill
		c.mskin(minf(side * 0.3, side * 0.6), 1.55, 2.2, maxf(side * 0.3, side * 0.6), 2.5, 2.27, P.PAINT_DARK)
	# Target sight turret on the nose, M197 under the chin.
	var ball := func(z: float) -> Vector4:
		var k := clampf(z / 0.7, 0.0, 1.0)
		var r := 0.33 * sqrt(sin(PI * k))
		return Vector4(0.0, 1.22, r, r)
	c.mloft(0.0, 0.7, ball, P.PAINT_DARK, 2.0)
	c.mskin(-0.2, 1.05, 0.0, 0.2, 1.38, 0.15, P.GLASS)
	c.mskin(-0.06, 1.12, 0.0, 0.06, 1.2, 0.16, P.BLACK)
	c.mdisc(0.0, 1.15, 0.24, 0.48, 0.75, P.PAINT_DARK)
	c.mbox(-0.16, 0.42, 0.85, 0.16, 0.62, 1.35, P.GUN)
	for bx: float in [-0.055, 0.0, 0.055]:
		c.mbox(bx - 0.022, 0.5, 0.05, bx + 0.022, 0.545, 0.9, P.GUN)
	c.mbox(-0.08, 0.47, 0.25, 0.08, 0.57, 0.3, P.GUN)  # barrel clamp
	# Upper deck: transmission fairing, engines on the shoulders with their intakes forward and
	# IR suppressors turned up at the back, mast and rotor.
	var deck := func(z: float) -> Section:
		var k := clampf((z - 4.6) / 0.6, 0.0, 1.0)
		var top := lerpf(2.0, 2.35, sqrt(k))
		if z > 8.2:
			top = lerpf(2.35, 2.0, clampf((z - 8.2) / 1.6, 0.0, 1.0))
		return Section.new(1.8, top, 0.42, 0.3, 0.0, 0.18)
	c.mhull(4.6, 9.8, deck, P.PAINT, 0.08)
	for side: float in [-1.0, 1.0]:
		var nx := side * 0.52
		var nacelle := func(z: float) -> Vector4:
			var r := lerpf(0.26, 0.31, clampf((z - 5.0) / 0.4, 0.0, 1.0))
			return Vector4(nx, 2.12, r, r)
		c.mloft(5.0, 8.15, nacelle, P.PAINT, 2.0)
		var intake := func(_z: float) -> Vector4: return Vector4(nx, 2.12, 0.2, 0.2)
		c.mloft(5.0, 5.06, intake, P.BLACK, 2.0)
		c.mskin(minf(side * 0.3, side * 0.9), 1.8, 6.55, maxf(side * 0.3, side * 0.9), 2.5, 6.6, P.PAINT_DARK, P.PAINT)
		# Exhaust: a duct bending up and outwards, its outlet facing the sky.
		c.mbar(Vector3(side * 0.55, 2.12, 8.0), Vector3(side * 0.72, 2.45, 8.6), 0.3, P.PAINT_DARK)
		c.mbar(Vector3(side * 0.72, 2.45, 8.6), Vector3(side * 0.8, 2.72, 8.75), 0.28, P.PAINT_DARK)
		c.mbox(side * 0.8 - 0.1, 2.82, 8.65, side * 0.8 + 0.1, 2.88, 8.85, P.BLACK)
	c.mdisc(0.0, 5.85, 0.24, 2.3, 2.5, P.PAINT_DARK)
	c.mdisc(0.0, 5.85, 0.14, 2.5, 3.05, P.METAL)
	c.mdisc(0.0, 5.85, 0.32, 2.75, 2.82, P.METAL)
	c.mdisc(0.0, 5.85, 0.26, 3.0, 3.15, P.BLACK)
	c.rotor("MainRotor", Vector3(0.0, 3.2, 5.85), 7.32, 0.62, 4, Vector3.UP)
	# Swept fin with the tail rotor gearbox on its right; elevators with end plates.
	var y := 1.85
	while y < 3.75:
		var le := 12.55 + (y - 1.85) * 0.48
		var te := 13.5 + (y - 1.85) * 0.22
		c.mbox(-0.09, y, le, 0.09, y + c.vs, te, P.PAINT)
		y += c.vs
	c.mbox(0.09, 2.9, 13.15, 0.26, 3.15, 13.45, P.METAL)
	c.rotor("TailRotor", Vector3(0.32, 3.02, 13.3), 1.45, 0.26, 4, Vector3.RIGHT)
	c.mbox(-0.06, 3.7, 13.4, 0.06, 3.78, 13.55, P.PAINT_LIGHT)
	c.mbox(-1.4, 1.83, 10.9, 1.4, 1.91, 11.6, P.PAINT)
	for side: float in [-1.0, 1.0]:
		c.mbox(minf(side * 1.36, side * 1.44), 1.62, 10.85, maxf(side * 1.36, side * 1.44), 2.2, 11.65, P.PAINT)
	c.mbar(Vector3(0.0, 1.6, 12.9), Vector3(0.0, 1.15, 13.4), 0.06, P.METAL)  # tail skid guard
	# Stub wings: rocket pods inboard, quad Hellfire racks outboard, Sidewinders on the tips.
	c.mbox(-2.2, 1.18, 5.3, 2.2, 1.32, 6.45, P.PAINT)
	c.mbox(-2.2, 1.21, 5.25, 2.2, 1.29, 5.3, P.PAINT)
	for side: float in [-1.0, 1.0]:
		var px := side * 1.05
		c.mbox(px - 0.05, 1.0, 5.45, px + 0.05, 1.18, 6.15, P.PAINT_DARK)
		var pod := func(z: float) -> Vector4:
			var r := 0.22 if z > 4.75 else lerpf(0.16, 0.22, (z - 4.55) / 0.2)
			return Vector4(px, 0.78, r, r)
		c.mloft(4.55, 6.45, pod, P.PAINT_DARK, 2.0)
		for rx: float in [-0.1, 0.0, 0.1]:
			for ry: float in [-0.1, 0.0, 0.1]:
				c.mbox(px + rx - 0.025, 0.78 + ry - 0.025, 4.53, px + rx + 0.025, 0.78 + ry + 0.025, 4.58, P.BLACK)
		var hx := side * 1.75
		c.mbox(hx - 0.05, 1.03, 5.4, hx + 0.05, 1.18, 6.3, P.PAINT_DARK)
		c.mbox(hx - 0.25, 0.95, 5.0, hx + 0.25, 1.03, 6.55, P.PAINT_DARK)  # launcher rail
		for mx: float in [-0.13, 0.13]:
			for my: float in [0.72, 0.9]:
				var missile := func(z: float) -> Vector4:
					var r := 0.08 if z > 4.95 else lerpf(0.03, 0.08, (z - 4.8) / 0.15)
					return Vector4(hx + mx, my, r, r)
				c.mloft(4.8, 6.45, missile, P.PAINT_LIGHT, 2.0)
		var tx := side * 2.26
		c.mbox(tx - 0.04, 1.15, 5.1, tx + 0.04, 1.32, 6.6, P.PAINT_DARK)
		var winder := func(z: float) -> Vector4:
			var r := 0.065 if z > 4.65 else lerpf(0.02, 0.065, (z - 4.5) / 0.15)
			return Vector4(tx, 1.05, r, r)
		c.mloft(4.5, 7.3, winder, P.PAINT_LIGHT, 2.0)
		c.mbox(tx - 0.2, 1.03, 4.8, tx + 0.2, 1.07, 4.95, P.PAINT_LIGHT)  # canards
		c.mbox(tx - 0.2, 1.03, 7.0, tx + 0.2, 1.07, 7.25, P.PAINT_LIGHT)
	# Skids: toes curving up at the front, two cross tubes up to the belly.
	for side: float in [-1.0, 1.0]:
		var sx := side * 1.0
		c.mbar(Vector3(sx, 0.06, 2.4), Vector3(sx, 0.06, 8.7), 0.09, P.METAL)
		c.mbar(Vector3(sx, 0.06, 2.4), Vector3(sx, 0.22, 2.05), 0.09, P.METAL)
		c.mbar(Vector3(sx, 0.22, 2.05), Vector3(sx, 0.45, 1.9), 0.09, P.METAL)
		for cz: float in [3.5, 7.4]:
			c.mbar(Vector3(sx, 0.08, cz), Vector3(side * 0.75, 0.55, cz), 0.09, P.METAL)
			c.mbar(Vector3(side * 0.75, 0.55, cz), Vector3(side * 0.4, 0.78, cz), 0.09, P.METAL)
		# Nav lights on the wing tips' front, steps under the canopy.
		c.mbox(side * 2.2 - 0.04, 1.2, 5.22, side * 2.2 + 0.04, 1.3, 5.28, P.LIGHT_RED if side < 0.0 else P.LIGHT_GREEN)
		c.mbox(minf(side * 0.6, side * 0.72), 1.0, 3.6, maxf(side * 0.6, side * 0.72), 1.05, 3.85, P.METAL)
	# Antennas, the anti-collision beacon, and the boom's seams.
	c.mbar(Vector3(0.0, 2.32, 8.9), Vector3(0.0, 2.75, 9.4), 0.04, P.METAL)
	c.mbox(-0.02, 0.48, 6.6, 0.02, 0.72, 6.9, P.PAINT_DARK)
	c.mbox(-0.05, 2.32, 7.6, 0.05, 2.4, 7.7, P.LIGHT_RED)
	for seam: float in [10.3, 12.0]:
		c.mskin(-0.6, 1.3, seam, 0.6, 2.1, seam + 0.05, P.PAINT_DARK, P.PAINT)
	return c


# --- Ground vehicles --------------------------------------------------------------------

## Tracks in metres: road wheels, drive sprocket and idler on each side, return rollers under
## the top run, and track shoes picked out across both runs.
static func _mtracks(c: Canvas, inner: float, outer: float, z0: float, z1: float, wheels: int, r: float, sprocket_front: bool, rollers := 3) -> void:
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * inner, side * outer)
		var x1 := maxf(side * inner, side * outer)
		var top_y := 2.0 * r + 0.18
		c.mbox(x0, 0.0, z0 + r, x1, 0.09, z1 - r, P.TRACK)
		c.mbox(x0, top_y, z0 + r * 0.8, x1, top_y + 0.08, z1 - r * 0.8, P.TRACK)
		var step := (z1 - z0 - 3.2 * r) / maxf(wheels - 1, 1)
		for i in wheels:
			var wz := z0 + 1.6 * r + i * step
			c.mwheel(x0 + 0.04, x1 - 0.04, r + 0.05, wz, r, P.BLACK, P.METAL)
			c.mwheel(x0 + 0.06, x1 - 0.06, r + 0.05, wz, r * 0.82, P.METAL, P.PAINT_DARK)
		var front_r := r * (0.85 if sprocket_front else 0.75)
		var back_r := r * (0.75 if sprocket_front else 0.85)
		var front_y := r + 0.22
		var back_y := r + 0.18
		c.mwheel(x0, x1, front_y, z0 + front_r, front_r, P.TRACK, P.METAL)
		c.mwheel(x0, x1, back_y, z1 - back_r, back_r, P.TRACK, P.METAL)
		# Sprocket teeth showing through the track at the drive end.
		var sz := z0 + front_r if sprocket_front else z1 - back_r
		var sy := front_y if sprocket_front else back_y
		var sr := front_r if sprocket_front else back_r
		for t in 10:
			var a := TAU * t / 10.0
			var p := Vector3(0, sy + sin(a) * sr * 0.78, sz + cos(a) * sr * 0.78)
			c.mbox(x0 + 0.05, p.y - 0.04, p.z - 0.04, x1 - 0.05, p.y + 0.04, p.z + 0.04, P.METAL)
		for i in rollers:
			var rz := lerpf(z0 + 1.2 * r, z1 - 1.2 * r, (i + 0.5) / rollers)
			c.mwheel(x0 + 0.08, x1 - 0.08, top_y - 0.08, rz, 0.09, P.BLACK, P.METAL)
		# Track shoes: a dark groove every 16 cm across both runs.
		var gz := z0 + r
		while gz < z1 - r:
			c.mskin(x0, -0.05, gz, x1, 0.12, gz + c.vs, P.BLACK, P.TRACK)
			c.mskin(x0, top_y - 0.02, gz, x1, top_y + 0.1, gz + c.vs, P.BLACK, P.TRACK)
			gz += 0.16


## Hull cross-section of a tracked vehicle: slab sides, flat roof, sloped bow.
static func _hull(c: Canvas, z0: float, z1: float, half_w: float, bottom: float, top: float, bow_len: float, bow_top: float, bow_bottom: float) -> void:
	var z := z0
	while z < z1:
		var t := 0.0 if bow_len <= 0.0 else clampf((z - z0) / bow_len, 0.0, 1.0)
		c.mbox(-half_w, lerpf(bow_bottom, bottom, t), z, half_w, lerpf(bow_top, top, t), z + c.vs, P.PAINT)
		z += c.vs


## AAV-7A1: a 7.94 m slab-sided amphibious hull riding low over its tracks, the steep bow
## with the folded bow plane, bolted applique armour panels along the sides, the Up-Gunned
## Weapon Station (Mk19 and M2) on the front right beside the engine grilles, the driver's and
## commander's cupolas on the front left, two long cargo hatches on the roof, water-jet ducts
## either side at the back and the big rear ramp with its personnel door.
static func _aav7() -> Canvas:
	var c := Canvas.new(Vector3i(70, 70, 162), 0.05)
	_mtracks(c, 1.1, 1.6, 0.75, 7.55, 6, 0.3, true, 2)
	# Hull: the bow rises from the keel to the roof; the sides hang down over the tracks.
	var z := 0.0
	while z < 7.95:
		var top := 2.62 if z > 1.75 else lerpf(1.5, 2.62, z / 1.75)
		var bottom := 0.45 if z > 1.0 else lerpf(1.1, 0.45, z / 1.0)
		var side_bottom := 0.95 if z > 1.1 else lerpf(1.25, 0.95, z / 1.1)
		c.mbox(-1.1, bottom, z, 1.1, top, z + c.vs, P.PAINT)
		c.mbox(-1.63, maxf(side_bottom, bottom), z, 1.63, top, z + c.vs, P.PAINT)
		z += c.vs
	# Bow plane folded against the bow, headlights, tow eyes.
	c.mskin(-1.35, 1.6, 0.2, 1.35, 2.4, 1.6, P.PAINT_DARK, P.PAINT)
	c.mskin(-1.25, 1.65, 0.25, 1.25, 2.35, 1.55, P.PAINT, P.PAINT_DARK)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 1.3 - 0.13, 1.45, 0.62, side * 1.3 + 0.13, 1.62, 0.78, P.PAINT_DARK)
		c.mskin(side * 1.3 - 0.09, 1.48, 0.58, side * 1.3 + 0.09, 1.58, 0.66, P.PAINT_LIGHT)
		c.mbox(side * 0.7 - 0.08, 1.05, 0.15, side * 0.7 + 0.08, 1.2, 0.3, P.METAL)
		# Applique armour panels with bolt heads, and the skirt edge along the bottom.
		var x0 := minf(side * 1.63, side * 1.72)
		var x1 := maxf(side * 1.63, side * 1.72)
		var pz := 1.8
		while pz < 7.4:
			c.mbox(x0, 1.15, pz, x1, 2.45, pz + 1.07, P.PAINT)
			for by: float in [1.25, 2.3]:
				for bz: float in [0.1, 0.5, 0.9]:
					c.mskin(minf(side * 1.7, side * 1.73), by, pz + bz, maxf(side * 1.7, side * 1.73), by + 0.05, pz + bz + 0.05, P.PAINT_DARK, P.PAINT)
			pz += 1.12
		c.mbox(minf(side * 1.6, side * 1.66), 0.92, 0.9, maxf(side * 1.6, side * 1.66), 1.0, 7.8, P.PAINT_DARK)
		# Water-jet ducts at the back, low on each side.
		c.mbox(minf(side * 1.15, side * 1.6), 0.95, 7.0, maxf(side * 1.15, side * 1.6), 1.45, 7.98, P.PAINT_DARK)
		c.mbox(minf(side * 1.22, side * 1.53), 1.02, 7.97, maxf(side * 1.22, side * 1.53), 1.38, 8.0, P.BLACK)
		c.mbox(side * 1.45 - 0.08, 2.2, 7.95, side * 1.45 + 0.08, 2.32, 8.0, P.LIGHT_RED)
		# Vision blocks along the roof edge over the troop compartment.
		for vz: float in [4.0, 5.2, 6.4]:
			c.mbox(minf(side * 1.3, side * 1.55), 2.62, vz, maxf(side * 1.3, side * 1.55), 2.7, vz + 0.3, P.PAINT_DARK)
	# Roof: engine grilles beside the weapon station, the two long cargo hatches.
	var gz := 1.95
	while gz < 2.95:
		c.mskin(-0.3, 2.58, gz, 0.3, 2.66, gz + 0.05, P.BLACK, P.PAINT)
		gz += 0.12
	c.mskin(-1.05, 2.58, 3.7, 1.05, 2.66, 6.95, P.PAINT_DARK, P.PAINT)
	c.mbox(-1.0, 2.62, 3.75, -0.06, 2.65, 6.9, P.PAINT)
	c.mbox(0.06, 2.62, 3.75, 1.0, 2.65, 6.9, P.PAINT)
	for hz: float in [4.2, 6.4]:
		c.mbox(-0.9, 2.65, hz, 0.9, 2.69, hz + 0.08, P.PAINT_DARK)  # hinges
	# Rear ramp and personnel door.
	c.mbox(-1.15, 0.5, 7.93, 1.15, 2.5, 8.0, P.PAINT)
	c.mskin(-1.15, 0.5, 7.92, 1.15, 0.56, 8.02, P.PAINT_DARK)
	c.mskin(-1.15, 2.45, 7.92, 1.15, 2.5, 8.02, P.PAINT_DARK)
	c.mskin(-0.45, 0.65, 7.97, 0.45, 2.2, 8.02, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.4, 0.7, 7.98, 0.4, 2.15, 8.0, P.PAINT)
	c.mskin(-0.2, 1.65, 7.97, 0.2, 1.95, 8.03, P.GLASS)
	c.mbox(0.25, 1.3, 7.99, 0.35, 1.38, 8.06, P.METAL)
	# Up-Gunned Weapon Station: a squat turret with vision blocks, Mk19 (thick) and M2 (long).
	var ux := 0.82
	var uz := 2.15
	c.mdisc(ux, uz, 0.68, 2.62, 2.7, P.PAINT_DARK)
	var station := func(tz: float) -> Section:
		var k := clampf((tz - (uz - 0.62)) / 1.24, 0.0, 1.0)
		var hw := 0.62 * sqrt(maxf(1.0 - pow(2.0 * k - 1.0, 2.0) * 0.75, 0.0))
		return Section.new(2.7, 3.2, hw, hw - 0.08, 0.0, 0.08, ux)
	c.mhull(uz - 0.62, uz + 0.62, station, P.PAINT)
	for vx: float in [-0.35, 0.0, 0.35]:
		c.mskin(ux + vx - 0.1, 2.95, uz - 0.7, ux + vx + 0.1, 3.08, uz - 0.3, P.GLASS)
	c.mbox(ux - 0.45, 2.78, uz - 0.75, ux - 0.05, 3.08, uz - 0.45, P.PAINT_DARK)  # gun ports
	c.mbox(ux - 0.32, 2.86, uz - 1.3, ux - 0.16, 3.0, uz - 0.7, P.GUN)  # Mk19
	c.mbox(ux - 0.3, 2.88, uz - 1.36, ux - 0.18, 2.98, uz - 1.28, P.GUN)
	c.mbox(ux + 0.1, 2.88, uz - 1.85, ux + 0.15, 2.93, uz - 0.6, P.GUN)  # M2
	c.mbox(ux + 0.07, 2.86, uz - 1.9, ux + 0.18, 2.95, uz - 1.82, P.GUN)
	c.mbox(ux - 0.15, 3.2, uz - 0.2, ux + 0.25, 3.28, uz + 0.25, P.PAINT_DARK)  # hatch
	# Driver's cupola and the taller commander's cupola behind it, both with vision blocks.
	c.mdisc(-0.95, 2.05, 0.36, 2.62, 2.85, P.PAINT)
	c.mskin(-1.3, 2.7, 1.65, -0.6, 2.8, 2.45, P.GLASS)
	c.mdisc(-0.95, 2.05, 0.28, 2.85, 2.9, P.PAINT_DARK)
	c.mdisc(-0.95, 3.1, 0.38, 2.62, 3.0, P.PAINT)
	c.mskin(-1.35, 2.82, 2.7, -0.55, 2.94, 3.5, P.GLASS)
	c.mdisc(-0.95, 3.1, 0.3, 3.0, 3.05, P.PAINT_DARK)
	c.mbar(Vector3(-1.4, 2.62, 3.6), Vector3(-1.4, 3.6, 3.65), 0.03, P.METAL)
	c.mbar(Vector3(1.4, 2.62, 6.8), Vector3(1.4, 3.5, 6.85), 0.03, P.METAL)
	return c


## M2A3 Bradley: 6.55 m hull with the long sloped glacis (engine grille on its right, driver's
## hatch on its left), slab sides covered in bolted armour tiles, six road wheels with a front
## sprocket, the big rear ramp with its door, roof cargo hatch and troop periscopes; the turret
## with the 25 mm Bushmaster and coax M240, the twin TOW launcher stowed on its left, the
## gunner's sight up front, the commander's independent viewer behind, smoke launchers and a
## stowage rack on the bustle.
static func _bradley() -> Canvas:
	var c := Canvas.new(Vector3i(76, 64, 134), 0.05)
	var hz := 0.1
	_mtracks(c, 1.12, 1.6, hz + 0.35, hz + 6.45, 6, 0.3, true, 3)
	var z := 0.0
	while z < 6.55:
		var top := 1.95 if z > 1.65 else lerpf(0.95, 1.95, z / 1.65)
		var bottom := 0.48 if z > 0.3 else lerpf(0.9, 0.48, z / 0.3)
		c.mbox(-1.1, bottom, hz + z, 1.1, minf(top, 1.0), hz + z + c.vs, P.PAINT)
		c.mbox(-1.62, maxf(bottom, 0.95), hz + z, 1.62, top, hz + z + c.vs, P.PAINT)
		z += c.vs
	# Armour tiles on the sides: rows of bolted blocks with dark gaps between them.
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * 1.6, side * 1.8)
		var x1 := maxf(side * 1.6, side * 1.8)
		var tz := 0.55
		while tz < 6.3:
			for row: Array in [[0.62, 0.98], [1.05, 1.4], [1.47, 1.84]]:
				var front_cut := (row[0] as float) < 1.0 and tz < 0.9
				if not front_cut:
					c.mbox(x0, row[0], hz + tz, x1, row[1], hz + tz + 0.42, P.PAINT)
					c.mskin(minf(side * 1.75, side * 1.82), (row[0] as float) + 0.15, hz + tz + 0.2, maxf(side * 1.75, side * 1.82), (row[0] as float) + 0.22, hz + tz + 0.27, P.PAINT_DARK, P.PAINT)
			tz += 0.48
		c.mbox(minf(side * 1.62, side * 1.72), 0.6, hz + 0.55, maxf(side * 1.62, side * 1.72), 1.84, hz + 6.3, P.PAINT_DARK)  # backing plate seen through the gaps
		# Headlights and convoy lights on the glacis corners, tail lights on the rear.
		c.mbox(side * 1.35 - 0.12, 1.1, hz + 0.2, side * 1.35 + 0.12, 1.25, hz + 0.32, P.PAINT_DARK)
		c.mskin(side * 1.35 - 0.08, 1.12, hz + 0.18, side * 1.35 + 0.08, 1.22, hz + 0.22, P.PAINT_LIGHT)
		c.mbox(side * 1.3 - 0.08, 1.5, hz + 6.55, side * 1.3 + 0.08, 1.62, hz + 6.6, P.LIGHT_RED)
		c.mbox(side * 0.8 - 0.07, 0.62, hz + 0.1, side * 0.8 + 0.07, 0.76, hz + 0.25, P.METAL)  # tow eye
		# Troop periscopes along the roof edges.
		for pz: float in [4.0, 4.8, 5.6]:
			c.mbox(minf(side * 1.35, side * 1.55), 1.95, hz + pz, maxf(side * 1.35, side * 1.55), 2.05, hz + pz + 0.25, P.PAINT_DARK)
			c.mskin(minf(side * 1.5, side * 1.6), 1.97, hz + pz + 0.03, maxf(side * 1.5, side * 1.6), 2.03, hz + pz + 0.22, P.GLASS)
	# Glacis: engine grille on the right, driver's hatch and periscopes on the left.
	c.mskin(0.35, 1.0, hz + 0.45, 1.45, 1.75, hz + 1.3, P.BLACK, P.PAINT)
	var gx := 0.4
	while gx < 1.45:
		c.mskin(gx, 1.0, hz + 0.45, gx + 0.05, 1.75, hz + 1.3, P.PAINT_DARK, P.BLACK)
		gx += 0.15
	c.mbox(-1.35, 1.95, hz + 1.5, -0.7, 2.05, hz + 2.05, P.PAINT)
	c.mskin(-1.3, 1.85, hz + 1.42, -0.75, 2.02, hz + 1.55, P.GLASS)
	c.mskin(-1.62, 0.95, hz + 0.95, 1.62, 1.6, hz + 1.0, P.PAINT_DARK, P.PAINT)  # glacis seam
	# Roof cargo hatch, rear ramp with its door, stowage on the ramp.
	c.mskin(-0.85, 1.9, hz + 4.3, 0.85, 2.0, hz + 6.1, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.8, 1.95, hz + 4.35, 0.8, 1.98, hz + 6.05, P.PAINT)
	c.mbox(-1.15, 0.55, hz + 6.55, 1.15, 1.88, hz + 6.62, P.PAINT)
	c.mskin(-1.15, 0.55, hz + 6.55, 1.15, 0.6, hz + 6.65, P.PAINT_DARK)
	c.mskin(-1.15, 1.83, hz + 6.55, 1.15, 1.88, hz + 6.65, P.PAINT_DARK)
	c.mskin(-0.55, 0.75, hz + 6.6, 0.15, 1.7, hz + 6.65, P.PAINT_DARK, P.PAINT)  # ramp door
	c.mbox(-0.45, 0.85, hz + 6.62, 0.05, 1.6, hz + 6.64, P.PAINT)
	c.mskin(-0.35, 1.3, hz + 6.6, -0.05, 1.5, hz + 6.66, P.GLASS)
	c.mbox(0.05, 1.2, hz + 6.62, 0.2, 1.3, hz + 6.7, P.METAL)  # handle
	# Turret, offset right, with sloped front and sides.
	var tx := 0.15
	var turret := func(tz: float) -> Section:
		var t := tz - hz
		var top := 2.75 if t > 2.45 else lerpf(2.25, 2.75, (t - 1.95) / 0.5)
		return Section.new(1.95, top, 1.02, 0.86, 0.0, 0.06, tx)
	c.mhull(hz + 1.95, hz + 4.45, turret, P.PAINT)
	c.mbox(tx - 0.95, 1.95, hz + 4.45, tx + 0.95, 2.6, hz + 4.95, P.PAINT_DARK)  # bustle rack
	c.mbox(tx - 0.88, 2.0, hz + 4.48, tx + 0.88, 2.55, hz + 4.92, P.SEAT)
	# 25 mm Bushmaster in its mantlet with the coax on the right.
	c.mbox(tx - 0.32, 2.05, hz + 1.8, tx + 0.32, 2.5, hz + 2.1, P.PAINT_DARK)
	var barrel := func(bz: float) -> Vector4:
		var r := 0.05
		if bz > hz + 1.2:
			r = 0.085
		elif bz < hz + 0.2:
			r = 0.07
		return Vector4(tx, 2.28, r, r)
	c.mloft(0.0, hz + 1.85, barrel, P.GUN, 2.0)
	c.mbox(tx + 0.22, 2.16, hz + 1.45, tx + 0.27, 2.21, hz + 1.85, P.GUN)
	# TOW launcher stowed on the left of the turret, tubes facing forward.
	var lx := tx - 1.2
	c.mbox(lx - 0.25, 2.0, hz + 2.05, lx + 0.25, 2.62, hz + 3.6, P.PAINT)
	c.mskin(lx - 0.25, 2.3, hz + 2.0, lx + 0.25, 2.33, hz + 3.6, P.PAINT_DARK, P.PAINT)
	for ty: float in [2.06, 2.36]:
		c.mbox(lx - 0.18, ty, hz + 2.02, lx + 0.18, ty + 0.2, hz + 2.06, P.BLACK)
	c.mbox(lx + 0.25, 2.15, hz + 2.8, lx + 0.4, 2.4, hz + 3.1, P.METAL)  # elevating arm
	# Gunner's sight up front, commander's independent viewer behind, hatches, antennas.
	c.mbox(tx - 0.55, 2.75, hz + 2.45, tx - 0.15, 3.0, hz + 2.95, P.PAINT)
	c.mskin(tx - 0.5, 2.8, hz + 2.4, tx - 0.2, 2.96, hz + 2.5, P.GLASS)
	c.mdisc(tx + 0.5, hz + 3.85, 0.13, 2.75, 3.0, P.PAINT_DARK)
	c.mbox(tx + 0.3, 3.0, hz + 3.6, tx + 0.72, 3.32, hz + 4.05, P.PAINT)
	c.mskin(tx + 0.34, 3.05, hz + 3.55, tx + 0.68, 3.27, hz + 3.65, P.GLASS)
	c.mdisc(tx + 0.45, hz + 3.2, 0.33, 2.75, 2.82, P.PAINT_DARK)
	c.mdisc(tx - 0.4, hz + 3.6, 0.3, 2.75, 2.82, P.PAINT_DARK)
	c.mbar(Vector3(tx + 0.8, 2.75, hz + 4.3), Vector3(tx + 0.8, 3.6, hz + 4.35), 0.03, P.METAL)
	c.mbar(Vector3(tx - 0.8, 2.75, hz + 4.3), Vector3(tx - 0.8, 3.4, hz + 4.35), 0.03, P.METAL)
	# Smoke grenade launchers on the turret's front corners.
	for side: float in [-1.0, 1.0]:
		var sx := tx + side * 0.82
		c.mbox(sx - 0.14, 2.4, hz + 2.05, sx + 0.14, 2.6, hz + 2.4, P.PAINT_DARK)
		for k in 4:
			c.mbox(sx - 0.12 + k * 0.065, 2.45, hz + 2.02, sx - 0.08 + k * 0.065, 2.52, hz + 2.06, P.BLACK)
	return c


## M1A2 SEP v2 Abrams: 7.93 m hull with a steep lower glacis and long shallow upper glacis,
## sponsons over the tracks, thick side skirts (heavier over the front three wheels), seven
## road wheels and a rear sprocket; the wide flat turret with wedge cheeks, recessed mantlet,
## long bustle and bustle rack, the 120 mm gun with thermal shroud and bore evacuator, the
## gunner's sight, commander's thermal viewer, CROWS on the commander's hatch, the loader's
## M240 behind its shield, smoke launchers, stowage boxes, engine deck grilles and the rear
## exhaust grille.
static func _abrams() -> Canvas:
	var c := Canvas.new(Vector3i(80, 60, 198), 0.05)
	var hz := 1.85  # the hull starts here; the gun reaches the front of the canvas
	_mtracks(c, 1.15, 1.78, hz + 0.3, hz + 7.85, 7, 0.32, false, 4)
	# Hull: lower body between the tracks, upper hull and sponsons out over them.
	var z := 0.0
	while z < 7.93:
		var top := 1.42 if z > 1.7 else lerpf(0.98, 1.42, z / 1.7)
		var bottom := 0.47 if z > 0.5 else lerpf(0.95, 0.47, z / 0.5)
		if z > 7.55:
			bottom = lerpf(0.47, 0.75, (z - 7.55) / 0.38)
		c.mbox(-1.1, bottom, hz + z, 1.1, minf(top, 1.0), hz + z + c.vs, P.PAINT)
		c.mbox(-1.74, maxf(bottom, 0.95), hz + z, 1.74, top, hz + z + c.vs, P.PAINT)
		z += c.vs
	c.mskin(-1.74, 0.94, hz, 1.74, 1.0, hz + 1.0, P.PAINT_DARK, P.PAINT)  # glacis joint
	# Skirts: thick armoured panels over the front three wheels, thinner ones behind.
	for side: float in [-1.0, 1.0]:
		z = 0.2
		while z < 7.5:
			var front := z < 2.9
			var bottom := lerpf(1.0, 0.5 if front else 0.58, clampf((z - 0.2) / 0.7, 0.0, 1.0))
			var out := 1.9 if front else 1.84
			c.mbox(minf(side * 1.74, side * out), bottom, hz + z, maxf(side * 1.74, side * out), 1.4, hz + z + c.vs, P.PAINT)
			z += c.vs
		for pz: float in [0.95, 1.9, 2.9, 3.95, 4.95, 5.95, 6.95]:
			c.mskin(minf(side * 1.7, side * 1.95), 0.5, hz + pz, maxf(side * 1.7, side * 1.95), 1.38, hz + pz + 0.05, P.PAINT_DARK, P.PAINT)
		c.mskin(minf(side * 1.7, side * 1.95), 1.26, hz + 0.3, maxf(side * 1.7, side * 1.95), 1.3, hz + 7.4, P.PAINT_DARK, P.PAINT)
		for bz in range(9):  # bolt heads along the heavy panels
			c.mskin(minf(side * 1.85, side * 1.95), 0.62, hz + 0.45 + bz * 0.28, maxf(side * 1.85, side * 1.95), 0.67, hz + 0.5 + bz * 0.28, P.PAINT_DARK, P.PAINT)
		# Headlight clusters with guards on the front corners, tow eyes, tail lights.
		var hx := side * 1.42
		c.mbox(hx - 0.14, 1.0, hz + 0.18, hx + 0.14, 1.16, hz + 0.34, P.PAINT_DARK)
		c.mskin(hx - 0.1, 1.03, hz + 0.16, hx + 0.1, 1.13, hz + 0.2, P.PAINT_LIGHT)
		c.mbar(Vector3(hx - 0.16, 1.0, hz + 0.12), Vector3(hx - 0.16, 1.2, hz + 0.3), 0.03, P.METAL)
		c.mbar(Vector3(hx + 0.16, 1.0, hz + 0.12), Vector3(hx + 0.16, 1.2, hz + 0.3), 0.03, P.METAL)
		c.mbox(side * 0.75 - 0.08, 0.6, hz + 0.25, side * 0.75 + 0.08, 0.75, hz + 0.4, P.METAL)
		c.mbox(side * 1.5 - 0.1, 1.2, hz + 7.9, side * 1.5 + 0.1, 1.35, hz + 7.95, P.LIGHT_RED)
	# Driver's hatch and periscopes, engine deck with its grilles and access doors, rear grille.
	c.mbox(-0.38, 1.38, hz + 1.05, 0.38, 1.5, hz + 1.6, P.PAINT)
	c.mskin(-0.32, 1.42, hz + 1.0, 0.32, 1.48, hz + 1.1, P.GLASS)
	c.mbox(-1.45, 1.42, hz + 6.0, 1.45, 1.47, hz + 7.85, P.PAINT_DARK)
	var gz := hz + 6.1
	while gz < hz + 7.8:
		c.mbox(-1.35, 1.46, gz, 1.35, 1.48, gz + 0.06, P.BLACK)
		gz += 0.14
	c.mskin(-1.74, 1.38, hz + 5.9, 1.74, 1.48, hz + 5.95, P.PAINT_DARK, P.PAINT)
	c.mbox(-1.35, 0.72, hz + 7.92, 1.35, 1.36, hz + 7.97, P.METAL)
	var ex := -1.3
	while ex < 1.3:
		c.mbox(ex, 0.75, hz + 7.95, ex + 0.04, 1.33, hz + 7.98, P.BLACK)
		ex += 0.1
	# Turret: wedge cheeks either side of the recessed mantlet, slab sides leaning in, the
	# bustle overhanging the engine deck.
	var turret := func(tz: float) -> Section:
		var t := tz - hz
		var hw := 1.82
		var bottom := 1.42
		if t < 3.15:
			hw = lerpf(0.62, 1.82, clampf((t - 1.5) / 1.65, 0.0, 1.0))
		elif t > 5.35:
			hw = 1.62
			bottom = 1.55
		var lean := 0.0 if t < 3.15 else 0.1  # leaning cheeks would turn into a sawtooth
		return Section.new(bottom, 2.37, hw, hw - lean, 0.0, 0.04)
	c.mhull(hz + 1.5, hz + 6.7, turret, P.PAINT)
	c.mbox(-0.48, 1.55, hz + 1.42, 0.48, 2.25, hz + 1.85, P.PAINT_DARK)  # mantlet
	c.mbox(0.28, 1.85, hz + 1.38, 0.38, 1.95, hz + 1.45, P.BLACK)  # coax port
	# 120 mm gun: muzzle, thermal shroud with its bands, bore evacuator, muzzle reference sensor.
	var tube := func(gz2: float) -> Vector4:
		var r := 0.12
		if gz2 < 0.35:
			r = 0.1
		elif gz2 > 1.3 and gz2 < 2.0:
			r = 0.165
		return Vector4(0.0, 1.95, r, r)
	c.mloft(0.0, hz + 1.5, tube, P.PAINT, 2.0)
	for band: float in [0.5, 2.3, 2.9, 3.5]:
		var ring := func(_z: float) -> Vector4: return Vector4(0.0, 1.95, 0.125, 0.125)
		c.mloft(band, band + 0.05, ring, P.PAINT_DARK, 2.0)
	c.mbox(-0.06, 2.04, 0.05, 0.06, 2.12, 0.3, P.METAL)
	# Roof: gunner's primary sight, commander's thermal viewer, hatches, CROWS, loader's M240.
	c.mbox(0.55, 2.37, hz + 2.05, 1.15, 2.72, hz + 2.8, P.PAINT)
	c.mskin(0.62, 2.42, hz + 2.0, 1.08, 2.66, hz + 2.1, P.GLASS)
	c.mdisc(-0.85, hz + 3.1, 0.17, 2.37, 2.62, P.PAINT_DARK)
	c.mbox(-1.1, 2.62, hz + 2.85, -0.6, 2.95, hz + 3.35, P.PAINT)
	c.mskin(-1.05, 2.67, hz + 2.8, -0.65, 2.9, hz + 2.9, P.GLASS)
	c.mdisc(0.7, hz + 3.95, 0.42, 2.37, 2.46, P.PAINT)
	c.mdisc(0.7, hz + 3.95, 0.3, 2.46, 2.5, P.PAINT_DARK)
	c.mbox(0.35, 2.46, hz + 3.0, 1.05, 2.62, hz + 3.6, P.PAINT_DARK)  # CROWS base
	c.mbox(0.5, 2.62, hz + 3.05, 0.9, 2.95, hz + 3.5, P.PAINT)
	c.mbox(0.92, 2.65, hz + 3.05, 1.08, 2.88, hz + 3.3, P.PAINT_DARK)  # CROWS sight
	c.mskin(0.94, 2.7, hz + 3.0, 1.06, 2.84, hz + 3.08, P.GLASS)
	c.mbox(0.64, 2.75, hz + 2.85, 0.76, 2.87, hz + 3.1, P.GUN)  # M2
	c.mbox(0.68, 2.78, hz + 1.75, 0.72, 2.83, hz + 2.85, P.GUN)
	c.mbox(0.66, 2.76, hz + 1.7, 0.74, 2.85, hz + 1.78, P.GUN)
	c.mbox(0.4, 2.62, hz + 3.2, 0.5, 2.8, hz + 3.42, P.SEAT)  # ammo can
	c.mdisc(-0.72, hz + 4.15, 0.4, 2.37, 2.45, P.PAINT)
	c.mbox(-1.25, 2.45, hz + 3.5, -0.25, 2.92, hz + 3.56, P.PAINT)  # loader's shield
	c.mskin(-0.85, 2.68, hz + 3.48, -0.6, 2.82, hz + 3.58, P.GLASS)
	c.mbox(-0.78, 2.6, hz + 2.9, -0.72, 2.66, hz + 3.7, P.GUN)
	c.mbox(-0.8, 2.55, hz + 3.55, -0.7, 2.68, hz + 3.95, P.GUN)
	# Blow-out panels on the bustle roof, wind sensor, antennas.
	c.mskin(-1.4, 2.35, hz + 5.25, 1.4, 2.4, hz + 5.3, P.PAINT_DARK, P.PAINT)
	c.mskin(-1.4, 2.35, hz + 6.45, 1.4, 2.4, hz + 6.5, P.PAINT_DARK, P.PAINT)
	c.mskin(-0.03, 2.35, hz + 5.25, 0.03, 2.4, hz + 6.5, P.PAINT_DARK, P.PAINT)
	c.mbar(Vector3(0.0, 2.37, hz + 5.9), Vector3(0.0, 2.95, hz + 5.9), 0.04, P.METAL)
	c.mbox(-0.12, 2.93, hz + 5.87, 0.12, 2.97, hz + 5.93, P.METAL)
	for side: float in [-1.0, 1.0]:
		c.mbar(Vector3(side * 1.25, 2.37, hz + 5.8), Vector3(side * 1.25, 3.1, hz + 5.85), 0.03, P.METAL)
		# Smoke grenade launchers on the cheeks, stowage boxes on the turret sides.
		var sx := side * 1.62
		c.mbox(sx - 0.18, 2.0, hz + 2.95, sx + 0.18, 2.32, hz + 3.35, P.PAINT_DARK)
		for ty: float in [2.05, 2.17]:
			for tx: float in [-0.12, 0.0, 0.12]:
				c.mbox(sx + tx - 0.04, ty, hz + 2.92, sx + tx + 0.04, ty + 0.08, hz + 2.96, P.BLACK)
		c.mbox(minf(side * 1.7, side * 1.95), 1.7, hz + 3.9, maxf(side * 1.7, side * 1.95), 2.25, hz + 5.2, P.PAINT)
		c.mskin(minf(side * 1.7, side * 1.96), 2.15, hz + 3.9, maxf(side * 1.7, side * 1.96), 2.2, hz + 5.2, P.PAINT_DARK, P.PAINT)
		# Bustle rack: rails and posts around the bustle.
		var rx := side * 1.78
		for ry: float in [1.75, 2.25]:
			c.mbar(Vector3(rx, ry, hz + 5.35), Vector3(rx, ry, hz + 7.1), 0.05, P.PAINT_DARK)
		for pz in range(5):
			c.mbar(Vector3(rx, 1.7, hz + 5.45 + pz * 0.4), Vector3(rx, 2.27, hz + 5.45 + pz * 0.4), 0.04, P.PAINT_DARK)
	for ry: float in [1.75, 2.25]:
		c.mbar(Vector3(-1.78, ry, hz + 7.1), Vector3(1.78, ry, hz + 7.1), 0.05, P.PAINT_DARK)
	c.mbox(-1.6, 1.7, hz + 6.7, -0.5, 2.1, hz + 7.05, P.SEAT)  # kit in the rack
	c.mbox(0.3, 1.7, hz + 6.7, 1.2, 2.0, hz + 7.05, P.PAINT_DARK)
	return c


## MaxxPro: 6.4 m MRAP with a truck bonnet and tall slatted grille behind a brush guard, one
## tall armoured cab-and-troop box whose lower sides fold in to the V-hull, thick armoured
## windows, 1.1 m tyres under square arches, side steps and fuel tank, the rear door with its
## step and spare tyre, and a roof turret with the gun-protection kit and an M2.
static func _maxxpro() -> Canvas:
	var c := Canvas.new(Vector3i(56, 70, 132), 0.05)
	# V-hull under the box.
	var y := 0.48
	while y < 1.05:
		var inset := (1.05 - y) * 1.5
		c.mbox(-1.1 + inset, y, 1.3, 1.1 - inset, y + c.vs, 6.2, P.PAINT_DARK)
		y += c.vs
	# Bonnet, grille and front fenders.
	c.mbox(-0.95, 0.95, 0.2, 0.95, 1.72, 1.5, P.PAINT)
	c.mbox(-0.9, 1.72, 0.3, 0.9, 1.78, 1.45, P.PAINT)
	c.mskin(-0.95, 1.7, 0.2, 0.95, 1.8, 0.4, P.PAINT_LIGHT, P.PAINT)
	c.mbox(-0.82, 1.0, 0.17, 0.82, 1.62, 0.2, P.BLACK)
	var gx := -0.78
	while gx < 0.8:
		c.mbox(gx, 1.0, 0.15, gx + 0.05, 1.62, 0.2, P.PAINT_DARK)
		gx += 0.13
	for side: float in [-1.0, 1.0]:
		c.mbox(minf(side * 0.95, side * 1.28), 1.15, 0.45, maxf(side * 0.95, side * 1.28), 1.25, 1.95, P.PAINT)  # fender
		c.mbox(minf(side * 1.24, side * 1.28), 0.85, 0.45, maxf(side * 1.24, side * 1.28), 1.15, 0.55, P.PAINT)
		c.mbox(side * 1.08 - 0.12, 1.25, 0.45, side * 1.08 + 0.12, 1.38, 0.55, P.PAINT_DARK)  # headlight
		c.mskin(side * 1.08 - 0.09, 1.27, 0.43, side * 1.08 + 0.09, 1.36, 0.47, P.PAINT_LIGHT)
	c.mbox(-1.2, 0.65, 0.0, 1.2, 0.95, 0.22, P.PAINT_DARK)  # bumper
	for bx: float in [-0.75, 0.75]:  # brush guard
		c.mbar(Vector3(bx, 0.95, 0.08), Vector3(bx, 1.7, 0.12), 0.06, P.PAINT_DARK)
	c.mbar(Vector3(-0.75, 1.68, 0.12), Vector3(0.75, 1.68, 0.12), 0.06, P.PAINT_DARK)
	c.mbar(Vector3(-0.75, 1.3, 0.1), Vector3(0.75, 1.3, 0.1), 0.06, P.PAINT_DARK)
	# The armoured box: lower sides folded in, raked windscreen, roof.
	var box := func(z: float) -> Section:
		var top := 2.85
		if z < 1.85:
			top = lerpf(1.95, 2.85, clampf((z - 1.45) / 0.4, 0.0, 1.0))
		return Section.new(1.05, top, 1.12, 1.24, 0.25, 0.06)
	c.mhull(1.45, 6.4, box, P.PAINT)
	c.mskin(-1.0, 2.0, 1.4, -0.05, 2.75, 1.9, P.GLASS)
	c.mskin(0.05, 2.0, 1.4, 1.0, 2.75, 1.9, P.GLASS)
	c.mskin(-1.3, 2.75, 1.4, 1.3, 2.9, 6.45, P.PAINT_DARK, P.PAINT)  # roof edge
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 1.1, side * 1.35)
		var ix := maxf(side * 1.1, side * 1.35)
		c.mskin(ox, 1.95, 2.0, ix, 2.55, 2.75, P.GLASS)  # crew door windows
		c.mskin(ox, 1.95, 3.0, ix, 2.55, 3.6, P.GLASS)
		for wz: float in [4.1, 4.85, 5.6]:
			c.mskin(ox, 2.05, wz, ix, 2.45, wz + 0.42, P.GLASS)
		for dz: float in [1.88, 2.9, 3.75]:  # door seams
			c.mskin(ox, 1.1, dz, ix, 2.7, dz + 0.05, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 2.68, 1.88, ix, 2.72, 3.8, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 1.22, side * 1.3), 1.6, 2.6, maxf(side * 1.22, side * 1.3), 1.7, 2.8, P.METAL)  # handles
		# Steps under the doors, fuel tank and battery box, mirrors on their arms.
		c.mbox(minf(side * 1.0, side * 1.3), 0.75, 2.0, maxf(side * 1.0, side * 1.3), 0.8, 3.6, P.METAL)
		c.mbox(minf(side * 0.85, side * 1.2), 0.7, 3.85, maxf(side * 0.85, side * 1.2), 1.05, 4.5, P.PAINT_DARK)
		c.mbar(Vector3(side * 1.25, 2.55, 1.6), Vector3(side * 1.55, 2.6, 1.4), 0.04, P.METAL)
		c.mbar(Vector3(side * 1.25, 2.1, 1.6), Vector3(side * 1.55, 2.25, 1.45), 0.04, P.METAL)
		c.mbox(minf(side * 1.5, side * 1.6), 2.05, 1.32, maxf(side * 1.5, side * 1.6), 2.6, 1.48, P.BLACK)
		# Wheels under square arches.
		for wz: float in [1.15, 5.05]:
			_mtire(c, side, minf(side * 0.9, side * 1.28), maxf(side * 0.9, side * 1.28), 0.56, wz, 0.56)
		c.mbox(minf(side * 1.24, side * 1.32), 1.05, 4.3, maxf(side * 1.24, side * 1.32), 1.2, 5.85, P.PAINT_DARK)
		c.mbox(side * 1.2 - 0.06, 2.4, 6.4, side * 1.2 + 0.06, 2.6, 6.45, P.LIGHT_RED)
	# Rear door with its window, the folding step and the spare tyre on its carrier.
	c.mskin(-0.6, 1.1, 6.38, 0.6, 2.6, 6.45, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.55, 1.15, 6.4, 0.55, 2.55, 6.42, P.PAINT)
	c.mskin(-0.3, 2.05, 6.38, 0.3, 2.4, 6.45, P.GLASS)
	c.mbox(-0.5, 0.5, 6.35, 0.5, 0.56, 6.75, P.METAL)
	c.mbox(-0.5, 0.75, 6.35, 0.5, 0.8, 6.6, P.METAL)
	c.mbox(0.65, 1.3, 6.4, 1.15, 1.4, 6.5, P.METAL)
	var spare := func(z: float) -> Vector4: return Vector4(0.9, 1.75, 0.5 * sqrt(maxf(1.0 - pow((z - 6.66) / 0.17, 2.0), 0.0)) + 0.02, 0.5 * sqrt(maxf(1.0 - pow((z - 6.66) / 0.17, 2.0), 0.0)) + 0.02)
	c.mloft(6.45, 6.6, spare, P.TIRE, 2.0)
	# Roof: stowage rack, antennas, the turret.
	c.mbox(-0.9, 2.85, 4.5, 0.9, 2.9, 6.1, P.PAINT_DARK)
	c.mbox(-0.8, 2.9, 4.7, 0.2, 3.15, 5.6, P.SEAT)
	c.mbar(Vector3(-1.1, 2.85, 6.2), Vector3(-1.1, 3.9, 6.25), 0.03, P.METAL)
	c.mbar(Vector3(1.1, 2.85, 6.2), Vector3(1.1, 3.7, 6.25), 0.03, P.METAL)
	_turret(c, 0.0, 2.85, 3.0, 0.95)
	return c


## M-ATV: 6.27 m MRAP all-terrain vehicle with the long bonnet sloping down to a wide slatted
## grille, big flared arches over 1.24 m tyres on independent suspension, a compact armoured
## four-door cab with a raked two-pane windscreen and sides leaning in, the short cargo bed,
## and the roof turret.
static func _matv() -> Canvas:
	var c := Canvas.new(Vector3i(54, 62, 128), 0.05)
	var y := 0.45
	while y < 0.95:
		var inset := (0.95 - y) * 1.4
		c.mbox(-1.05 + inset, y, 1.6, 1.05 - inset, y + c.vs, 6.0, P.PAINT_DARK)
		y += c.vs
	# Bonnet sloping down to the grille, with its slats and the bash bar.
	var hood := func(z: float) -> Section:
		var top := lerpf(1.4, 1.72, clampf((z - 0.1) / 1.9, 0.0, 1.0))
		return Section.new(0.85, top, 0.98, 0.88, 0.1, 0.12)
	c.mhull(0.1, 2.05, hood, P.PAINT)
	c.mskin(-0.85, 0.9, 0.05, 0.85, 1.32, 0.2, P.BLACK)
	var gx := -0.8
	while gx < 0.82:
		c.mskin(gx, 0.9, 0.05, gx + 0.05, 1.32, 0.2, P.PAINT_DARK, P.BLACK)
		gx += 0.11
	c.mskin(-0.6, 1.5, 0.6, 0.6, 1.72, 1.9, P.PAINT_DARK, P.PAINT)  # bonnet louvre panel
	c.mbox(-1.15, 0.6, 0.0, 1.15, 0.85, 0.22, P.PAINT_DARK)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 0.82 - 0.12, 1.2, 0.08, side * 0.82 + 0.12, 1.34, 0.14, P.PAINT_LIGHT)
		# Flared arches over the wheels, suspension arms, the tyres.
		for wz: float in [1.05, 4.9]:
			c.mbox(minf(side * 0.95, side * 1.25), 1.12, wz - 0.8, maxf(side * 0.95, side * 1.25), 1.22, wz + 0.8, P.PAINT)
			c.mbox(minf(side * 1.2, side * 1.27), 0.95, wz - 0.8, maxf(side * 1.2, side * 1.27), 1.15, wz - 0.7, P.PAINT)
			c.mbar(Vector3(side * 0.5, 0.7, wz), Vector3(side * 0.88, 0.62, wz), 0.1, P.METAL)
			c.mbar(Vector3(side * 0.5, 0.95, wz - 0.1), Vector3(side * 0.88, 0.85, wz), 0.08, P.METAL)
			_mtire(c, side, minf(side * 0.9, side * 1.22), maxf(side * 0.9, side * 1.22), 0.62, wz, 0.6)
	# Cab: raked windscreen, sides leaning in, four doors.
	var cab := func(z: float) -> Section:
		var top := lerpf(1.72, 2.48, clampf((z - 2.0) / 0.55, 0.0, 1.0))
		return Section.new(0.9, top, 1.15, 1.0, 0.15, 0.08)
	c.mhull(2.0, 4.4, cab, P.PAINT, 0.1)
	c.mskin(-0.95, 1.8, 1.95, -0.05, 2.42, 2.55, P.GLASS)
	c.mskin(0.05, 1.8, 1.95, 0.95, 2.42, 2.55, P.GLASS)
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 0.95, side * 1.25)
		var ix := maxf(side * 0.95, side * 1.25)
		c.mskin(ox, 1.75, 2.6, ix, 2.3, 3.25, P.GLASS)
		c.mskin(ox, 1.75, 3.5, ix, 2.3, 4.1, P.GLASS)
		for dz: float in [2.55, 3.38, 4.25]:
			c.mskin(ox, 0.95, dz, ix, 2.4, dz + 0.05, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 1.12, side * 1.2), 1.55, 3.05, maxf(side * 1.12, side * 1.2), 1.62, 3.25, P.METAL)
		c.mbox(minf(side * 1.12, side * 1.2), 1.55, 3.9, maxf(side * 1.12, side * 1.2), 1.62, 4.1, P.METAL)
		c.mbox(minf(side * 0.95, side * 1.2), 0.75, 2.7, maxf(side * 0.95, side * 1.2), 0.8, 4.1, P.METAL)  # step
		c.mbar(Vector3(side * 1.1, 2.2, 2.2), Vector3(side * 1.42, 2.25, 2.05), 0.04, P.METAL)
		c.mbox(minf(side * 1.36, side * 1.46), 1.85, 1.95, maxf(side * 1.36, side * 1.46), 2.3, 2.1, P.BLACK)
		c.mbox(side * 1.0 - 0.06, 1.35, 6.2, side * 1.0 + 0.06, 1.5, 6.25, P.LIGHT_RED)
	# Cargo bed: low walls, tailgate, stowed kit.
	c.mbox(-1.12, 0.9, 4.4, 1.12, 1.2, 6.25, P.PAINT)
	c.mbox(-1.12, 1.2, 4.4, -1.04, 1.62, 6.25, P.PAINT)
	c.mbox(1.04, 1.2, 4.4, 1.12, 1.62, 6.25, P.PAINT)
	c.mbox(-1.12, 1.2, 6.17, 1.12, 1.62, 6.25, P.PAINT)
	c.mskin(-1.15, 1.55, 4.4, 1.15, 1.63, 6.26, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.9, 1.2, 4.6, 0.3, 1.55, 5.5, P.SEAT)
	c.mbox(0.4, 1.2, 4.6, 0.95, 1.45, 5.2, P.PAINT_DARK)
	c.mbar(Vector3(-1.0, 2.48, 4.2), Vector3(-1.0, 3.4, 4.25), 0.03, P.METAL)
	_turret(c, 0.0, 2.48, 3.3, 0.88)
	return c


## Roof turret ring with the O-GPK gun shield (front plate with wings angled back and an
## armoured window, side plates) and an M2 with its ammo can, centred at (x, z).
static func _turret(c: Canvas, x: float, roof: float, z: float, half: float) -> void:
	c.mdisc(x, z, half * 0.78, roof, roof + 0.12, P.PAINT_DARK)
	c.mdisc(x, z, half * 0.6, roof + 0.12, roof + 0.16, P.PAINT)
	var front := z - half
	c.mbox(x - half * 0.55, roof + 0.12, front, x + half * 0.55, roof + 0.72, front + 0.05, P.PAINT)
	c.mskin(x - 0.22, roof + 0.42, front - 0.01, x + 0.22, roof + 0.66, front + 0.06, P.GLASS)
	c.mbox(x - 0.07, roof + 0.25, front - 0.01, x + 0.07, roof + 0.38, front + 0.06, P.BLACK)  # gun port
	for side: float in [-1.0, 1.0]:
		# Wing angled back from the front plate, then the side plate.
		var w := 0.0
		while w < half * 0.45:
			var wx := x + side * (half * 0.55 + w)
			c.mbox(wx - 0.03, roof + 0.12, front + w * 0.8, wx + 0.03, roof + 0.66, front + w * 0.8 + 0.06, P.PAINT)
			w += c.vs * 0.5
		c.mskin(x + side * half * 0.7 - 0.1, roof + 0.4, front, x + side * half * 0.7 + 0.1, roof + 0.6, front + half * 0.3, P.GLASS)
		c.mbox(minf(x + side * half, x + side * (half - 0.05)), roof + 0.12, front + half * 0.35, maxf(x + side * half, x + side * (half - 0.05)), roof + 0.55, z + half * 0.4, P.PAINT)
		c.mbox(minf(x + side * half, x + side * (half - 0.05)), roof + 0.55, front + half * 0.35, maxf(x + side * half, x + side * (half - 0.05)), roof + 0.6, z + half * 0.4, P.PAINT_DARK)
	# M2 on its pintle: receiver, barrel with the carrying handle, spade grips, ammo can.
	c.mbar(Vector3(x, roof + 0.12, z - half * 0.3), Vector3(x, roof + 0.3, z - half * 0.3), 0.06, P.METAL)
	c.mbox(x - 0.07, roof + 0.28, z - half + 0.1, x + 0.07, roof + 0.42, z - half * 0.1, P.GUN)
	c.mbox(x - 0.03, roof + 0.33, z - half - 1.05, x + 0.03, roof + 0.38, z - half + 0.1, P.GUN)
	c.mbox(x - 0.05, roof + 0.31, z - half - 1.1, x + 0.05, roof + 0.4, z - half - 1.0, P.GUN)
	c.mbox(x - 0.02, roof + 0.38, z - half - 0.35, x + 0.02, roof + 0.44, z - half - 0.15, P.GUN)
	c.mbox(x - 0.06, roof + 0.3, z - half * 0.1, x + 0.06, roof + 0.38, z, P.GUN)
	c.mbox(x + 0.07, roof + 0.22, z - half + 0.15, x + 0.22, roof + 0.4, z - half + 0.45, P.SEAT)


## A military tyre at x0..x1 (metres), centre (cy, cz), radius r: tread blocks around the
## rim, the sidewall, and a hub with its bolt ring on the outer face (`side` -1 left, 1 right).
static func _mtire(c: Canvas, side: float, x0: float, x1: float, cy: float, cz: float, r: float) -> void:
	c.mwheel(x0, x1, cy, cz, r, P.TIRE, P.TIRE)
	c.mwheel(x0, x1, cy, cz, r * 0.5, P.METAL, P.PAINT_DARK)
	for t in 24:  # tread blocks: dark cuts across the running surface
		var a := TAU * t / 24.0
		var py := cy + sin(a) * r
		var pz := cz + cos(a) * r
		c.mskin(x0, py - 0.035, pz - 0.035, x1, py + 0.035, pz + 0.035, P.BLACK, P.TIRE)
	var face := x1 if side > 0.0 else x0
	c.mbox(face - 0.03, cy - r * 0.2, cz - r * 0.2, face + 0.03, cy + r * 0.2, cz + r * 0.2, P.PAINT_DARK)
	for b in 8:
		var a := TAU * b / 8.0
		c.mbox(face - 0.03, cy + sin(a) * r * 0.36 - 0.025, cz + cos(a) * r * 0.36 - 0.025, face + 0.03, cy + sin(a) * r * 0.36 + 0.025, cz + cos(a) * r * 0.36 + 0.025, P.METAL)


# --- Technicals -------------------------------------------------------------------------

## The pickups technicals are built on: "hilux" (Toyota Hilux, 5.25 m, low with a raked
## windscreen and a pressed-steel bed) or "lc79" (Land Cruiser 79 pickup, 5.2 m, taller and
## boxier with flared arches, the snorkel up the right pillar and a flat dropside tray behind a
## headboard rack). Both carry bumpers, lights, mirrors, door seams and handles, cut wheel
## arches, rust and a panel or two in a mismatched colour. Returns the bed floor height.
static func _pickup(c: Canvas, base: String) -> float:
	var lc := base == "lc79"
	var hood_end := 1.95 if lc else 1.7
	var cab_end := 3.25 if lc else 3.0
	var length := 5.2 if lc else 5.25
	var roof := 1.95 if lc else 1.68
	var hood_top := 1.25 if lc else 1.05
	var bed := 1.0 if lc else 0.8
	var r := 0.4 if lc else 0.37
	var hw := 0.88
	var wb := 3.18 if lc else 3.08
	var axles := [0.95, 0.95 + wb]
	# Lower body, then the bonnet with its rounded edges.
	c.mbox(-hw, 0.48, 0.12, hw, 0.85 if lc else 0.75, cab_end, P.PAINT)
	var bonnet := func(z: float) -> Section:
		var top := hood_top if lc else lerpf(0.93, hood_top, clampf(z / 0.9, 0.0, 1.0))
		return Section.new(0.48, top, hw, hw - (0.02 if lc else 0.06), 0.06, 0.08 if lc else 0.12)
	c.mhull(0.12, hood_end, bonnet, P.PAINT)
	# Cab: the windscreen raked (Hilux) or nearly upright (Land Cruiser), roof edges rounded.
	var rake := 0.18 if lc else 0.5
	var cab := func(z: float) -> Section:
		var top := lerpf(hood_top, roof, clampf((z - hood_end) / rake, 0.0, 1.0))
		return Section.new(0.48, top, hw, hw - 0.1, 0.06, 0.12)
	c.mhull(hood_end, cab_end, cab, P.PAINT)
	c.mskin(-0.78, hood_top + 0.04, hood_end - 0.02, 0.78, roof - 0.07, hood_end + rake + 0.05, P.GLASS)
	c.mskin(-0.04, hood_top + 0.04, hood_end - 0.02, 0.04, roof, hood_end + rake + 0.05, P.PAINT, P.GLASS)
	c.mskin(-0.95, hood_top + 0.08, hood_end + rake + 0.08, 0.95, roof - 0.09, cab_end - 0.14, P.GLASS)
	c.mskin(-0.55, hood_top + 0.12, cab_end - 0.03, 0.55, roof - 0.14, cab_end + 0.02, P.GLASS)
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 0.8, side * 0.95)
		var ix := maxf(side * 0.8, side * 0.95)
		var door := hood_end + 0.05
		c.mskin(ox, 0.55, door, ix, roof - 0.05, door + 0.05, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 0.55, cab_end - 0.1, ix, roof - 0.05, cab_end - 0.05, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 0.86, side * 0.92), hood_top - 0.05, cab_end - 0.35, maxf(side * 0.86, side * 0.92), hood_top, cab_end - 0.2, P.METAL)  # handle
		# Mirrors, headlights and indicators, tail lights.
		c.mbox(minf(side * 0.88, side * 1.03), hood_top + 0.1, hood_end + 0.05, maxf(side * 0.88, side * 1.03), hood_top + 0.24, hood_end + 0.14, P.BLACK)
		var lx := side * (0.66 if lc else 0.68)
		c.mbox(lx - 0.17, hood_top - (0.32 if lc else 0.22), 0.09, lx + 0.17, hood_top - 0.08, 0.14, P.PAINT_LIGHT)
		c.mbox(side * 0.84 - 0.05, hood_top - (0.32 if lc else 0.22), 0.1, side * 0.84 + 0.05, hood_top - 0.18, 0.15, P.RUST)
		c.mbox(minf(side * 0.82, side * hw), bed + 0.1, length - 0.04, maxf(side * 0.82, side * hw), bed + 0.38, length + 0.01, P.LIGHT_RED)
	# Grille: horizontal bars on the Hilux, vertical slats on the Land Cruiser.
	c.mbox(-0.48, 0.62, 0.08, 0.48, hood_top - 0.08, 0.13, P.BLACK)
	if lc:
		var gx := -0.45
		while gx < 0.48:
			c.mbox(gx, 0.64, 0.07, gx + 0.04, hood_top - 0.1, 0.12, P.METAL)
			gx += 0.09
	else:
		for gy: float in [0.7, 0.8, 0.9]:
			c.mbox(-0.46, gy, 0.07, 0.46, gy + 0.04, 0.12, P.METAL)
	c.mbox(-0.92, 0.4, 0.0, 0.92, 0.6, 0.14, P.METAL)  # front bumper
	# Bed: pressed-steel tub on the Hilux, a flat tray with dropsides on the Land Cruiser.
	var wall := bed + (0.38 if lc else 0.45)
	var bw := 0.93 if lc else hw
	c.mbox(-bw, bed - 0.08, cab_end + 0.05, bw, bed, length, P.PAINT_DARK if lc else P.PAINT)
	c.mbox(-bw, bed, cab_end + 0.05, -bw + 0.05, wall, length, P.PAINT)
	c.mbox(bw - 0.05, bed, cab_end + 0.05, bw, wall, length, P.PAINT)
	c.mbox(-bw, bed, length - 0.05, bw, wall, length, P.PAINT)
	c.mbox(-bw, bed, cab_end + 0.05, bw, wall, cab_end + 0.1, P.PAINT)
	c.mskin(-bw - 0.01, wall - 0.04, cab_end + 0.05, bw + 0.01, wall + 0.01, length + 0.01, P.PAINT_LIGHT, P.PAINT)  # top rails
	var rz := cab_end + 0.3
	while rz < length - 0.1:  # floor ribs
		c.mbox(-bw + 0.08, bed, rz, bw - 0.08, bed + 0.03, rz + 0.05, P.PAINT_DARK)
		rz += 0.25
	if lc:
		c.mbox(-0.95, 0.55, cab_end, 0.95, 1.0, length, P.PAINT_DARK)  # tray chassis
		for hx: float in [-0.85, 0.85]:  # headboard rack posts
			c.mbar(Vector3(hx, bed, cab_end + 0.08), Vector3(hx, roof + 0.05, cab_end + 0.08), 0.05, P.METAL)
		c.mbar(Vector3(-0.85, roof + 0.05, cab_end + 0.08), Vector3(0.85, roof + 0.05, cab_end + 0.08), 0.05, P.METAL)
		c.mbar(Vector3(-0.85, roof - 0.35, cab_end + 0.08), Vector3(0.85, roof - 0.35, cab_end + 0.08), 0.04, P.METAL)
		# Snorkel up the right windscreen pillar, intake facing forward.
		c.mbar(Vector3(0.93, hood_top - 0.1, hood_end - 0.3), Vector3(0.93, hood_top + 0.05, hood_end - 0.05), 0.1, P.BLACK)
		c.mbar(Vector3(0.93, hood_top + 0.05, hood_end - 0.05), Vector3(0.93, roof + 0.1, hood_end + rake), 0.1, P.BLACK)
		c.mbox(0.86, roof + 0.05, hood_end + rake - 0.15, 1.0, roof + 0.2, hood_end + rake + 0.05, P.BLACK)
		for side: float in [-1.0, 1.0]:  # flares on the arches
			for az: float in axles:
				c.mbox(minf(side * 0.86, side * 0.97), r * 2.0 + 0.08, az - r - 0.1, maxf(side * 0.86, side * 0.97), r * 2.0 + 0.16, az + r + 0.1, P.BLACK)
	c.mbox(-0.9, 0.55, length - 0.05, 0.9, 0.7, length + 0.08, P.METAL)  # rear step bumper
	# Wheel arches cut out of the body, then the wheels with their rims.
	for az: float in axles:
		c.mwheel(-1.0, 1.0, r, az, r + 0.08, P.EMPTY, P.EMPTY)
		for side: float in [-1.0, 1.0]:
			c.mwheel(minf(side * 0.66, side * 0.9), maxf(side * 0.66, side * 0.9), r, az, r, P.TIRE, P.METAL)
			c.mbox(minf(side * 0.86, side * 0.91), r - 0.06, az - 0.06, maxf(side * 0.86, side * 0.91), r + 0.06, az + 0.06, P.PAINT_DARK)
			for t in 16:
				var a := TAU * t / 16.0
				c.mskin(minf(side * 0.66, side * 0.91), r + sin(a) * r - 0.03, az + cos(a) * r - 0.03, maxf(side * 0.66, side * 0.91), r + sin(a) * r + 0.03, az + cos(a) * r + 0.03, P.BLACK, P.TIRE)
	c.mbox(-0.6, 0.4, 0.9, 0.6, 0.48, 4.3, P.BLACK)  # chassis rails seen under the body
	# Hard use: rust along the sills and on the bonnet, a door in another truck's paint.
	c.mskin(-1.0, 0.48, 1.6, 1.0, 0.62, length - 0.6, P.RUST, P.PAINT)
	c.mskin(-1.0, 0.62, hood_end + 0.1, -0.8, roof - 0.12, cab_end - 0.12, P.PAINT_LIGHT, P.PAINT)
	c.mskin(-0.45, hood_top - 0.03, 0.35, -0.25, hood_top + 0.03, 0.5, P.RUST, P.PAINT)
	c.mskin(0.3, hood_top - 0.03, 1.1, 0.42, hood_top + 0.03, 1.2, P.RUST, P.PAINT)
	return bed


## A technical: a pickup plus the weapon fitted in its bed. Weapons seen across the Middle
## East: DShK 12.7 mm, ZU-23-2 twin 23 mm cannon, SPG-9 73 mm and M40 106 mm recoilless
## rifles, a Type 63 twelve-tube 107 mm rocket launcher, and the ZPU-2 twin 14.5 mm.
static func _technical(weapon: String) -> Canvas:
	var c := Canvas.new(Vector3i(42, 64, 108), 0.05)
	var base := "lc79" if weapon in ["zu23", "rockets", "zpu"] else "hilux"
	var bed := _pickup(c, base)
	var mid := 4.15 if base == "lc79" else 4.1
	match weapon:
		"dshk":
			c.mbar(Vector3(0, bed, mid), Vector3(0, bed + 0.95, mid), 0.07, P.METAL)  # pintle
			c.mbox(-0.08, bed + 0.95, mid - 0.35, 0.08, bed + 1.1, mid + 0.25, P.GUN)  # receiver
			c.mbox(-0.03, bed + 1.0, mid - 1.45, 0.03, bed + 1.06, mid - 0.35, P.GUN)  # barrel
			c.mbox(-0.06, bed + 0.97, mid - 1.5, 0.06, bed + 1.09, mid - 1.4, P.GUN)  # muzzle brake
			c.mbox(-0.06, bed + 0.98, mid - 1.0, 0.06, bed + 1.08, mid - 0.9, P.GUN)  # cooling fins
			c.mbox(0.08, bed + 0.85, mid - 0.25, 0.25, bed + 1.0, mid, P.SEAT)  # ammo can
			c.mbar(Vector3(0, bed + 0.95, mid + 0.25), Vector3(0, bed + 1.0, mid + 0.4), 0.05, P.GUN)  # spade grips
		"zu23":
			c.mbox(-0.72, bed, mid - 0.7, 0.72, bed + 0.3, mid + 0.8, P.PAINT_DARK)  # mount base
			c.mbox(-0.45, bed + 0.3, mid - 0.4, 0.45, bed + 0.75, mid + 0.4, P.GUN)  # cradle
			for bx: float in [-0.18, 0.18]:
				c.mbox(bx - 0.08, bed + 0.72, mid - 0.45, bx + 0.08, bed + 0.92, mid + 0.35, P.GUN)  # receivers
				c.mbar(Vector3(bx, bed + 0.85, mid - 0.45), Vector3(bx, bed + 1.15, mid - 2.5), 0.06, P.GUN)  # barrels
				c.mbar(Vector3(bx, bed + 1.13, mid - 2.45), Vector3(bx, bed + 1.16, mid - 2.6), 0.1, P.GUN)  # flash hiders
				c.mbox(bx + (0.08 if bx > 0 else -0.24), bed + 0.75, mid - 0.25, bx + (0.24 if bx > 0 else -0.08), bed + 1.0, mid + 0.15, P.PAINT_DARK)  # magazines
			c.mbox(-0.55, bed + 0.3, mid + 0.4, -0.25, bed + 0.65, mid + 0.7, P.SEAT)  # gunner's seats
			c.mbox(0.25, bed + 0.3, mid + 0.4, 0.55, bed + 0.65, mid + 0.7, P.SEAT)
		"spg9":
			for leg: Vector3 in [Vector3(-0.5, bed, mid + 0.3), Vector3(0.5, bed, mid + 0.3), Vector3(0, bed, mid - 0.6)]:
				c.mbar(leg, Vector3(0, bed + 0.75, mid), 0.05, P.METAL)
			var tube := func(_z: float) -> Vector4: return Vector4(0.0, bed + 0.85, 0.075, 0.075)
			c.mloft(mid - 1.4, mid + 0.75, tube, P.GUN, 2.0)
			var venturi := func(z: float) -> Vector4: return Vector4(0.0, bed + 0.85, lerpf(0.08, 0.12, (z - mid - 0.55) / 0.3), lerpf(0.08, 0.12, (z - mid - 0.55) / 0.3))
			c.mloft(mid + 0.55, mid + 0.85, venturi, P.GUN, 2.0)
			c.mbox(-0.2, bed + 0.75, mid - 0.4, 0.2, bed + 1.05, mid - 0.37, P.PAINT_DARK)  # shield
			c.mbox(0.08, bed + 0.95, mid - 0.2, 0.16, bed + 1.05, mid, P.BLACK)  # sight
		"m40":
			c.mbar(Vector3(0, bed, mid), Vector3(0, bed + 0.7, mid), 0.12, P.METAL)
			var tube := func(_z: float) -> Vector4: return Vector4(0.0, bed + 0.85, 0.09, 0.09)
			c.mloft(mid - 2.6, mid + 0.6, tube, P.GUN, 2.0)
			var breech := func(_z: float) -> Vector4: return Vector4(0.0, bed + 0.85, 0.14, 0.14)
			c.mloft(mid + 0.35, mid + 0.85, breech, P.GUN, 2.0)
			c.mbox(-0.025, bed + 0.98, mid - 1.0, 0.025, bed + 1.03, mid + 0.2, P.GUN)  # spotting rifle
			c.mbox(0.12, bed + 0.85, mid - 0.1, 0.2, bed + 1.0, mid + 0.1, P.BLACK)  # sight
		"rockets":
			# Pedestal raised so the launcher clears the cab, twelve 107 mm tubes in three rows of
			# four tilted up 12 degrees, inside a frame with a hand-crank for elevation.
			c.mbox(-0.4, bed, mid - 0.2, 0.4, bed + 0.15, mid + 0.4, P.PAINT_DARK)
			c.mbar(Vector3(0, bed + 0.15, mid + 0.1), Vector3(0, bed + 0.85, mid + 0.1), 0.14, P.METAL)
			var tilt := tan(deg_to_rad(12.0))
			var base_y := bed + 0.95
			c.mbox(-0.4, base_y - 0.1, mid - 0.3, 0.4, base_y - 0.04, mid + 0.5, P.METAL)
			for row in 3:
				for col in 4:
					var x := -0.27 + col * 0.18
					var y0 := base_y + row * 0.15
					c.mbar(Vector3(x, y0 + 0.5 * tilt, mid - 0.6), Vector3(x, y0 - 0.5 * tilt, mid + 0.45), 0.13, P.GUN)
					c.mbox(x - 0.04, y0 + 0.5 * tilt - 0.04, mid - 0.62, x + 0.04, y0 + 0.5 * tilt + 0.04, mid - 0.58, P.BLACK)
			for fx: float in [-0.4, 0.38]:
				c.mbox(fx, base_y - 0.08, mid - 0.4, fx + 0.03, base_y + 0.45, mid + 0.4, P.METAL)
			c.mwheel(0.41, 0.45, base_y + 0.1, mid + 0.25, 0.1, P.METAL, P.GUN)
		"zpu":
			c.mbox(-0.6, bed, mid - 0.5, 0.6, bed + 0.35, mid + 0.6, P.PAINT_DARK)
			c.mbox(-0.3, bed + 0.35, mid - 0.25, 0.3, bed + 0.7, mid + 0.35, P.GUN)
			for bx: float in [-0.13, 0.13]:
				c.mbar(Vector3(bx, bed + 0.8, mid - 0.2), Vector3(bx, bed + 0.95, mid - 2.1), 0.05, P.GUN)
				c.mbar(Vector3(bx, bed + 0.94, mid - 2.05), Vector3(bx, bed + 0.95, mid - 2.2), 0.09, P.GUN)
				c.mbox(bx - 0.06, bed + 0.7, mid - 0.25, bx + 0.06, bed + 0.88, mid + 0.3, P.GUN)
			c.mbox(-0.65, bed + 0.35, mid + 0.35, -0.35, bed + 0.75, mid + 0.75, P.SEAT)
			c.mbox(0.35, bed + 0.35, mid - 0.2, 0.65, bed + 0.6, mid + 0.2, P.PAINT_DARK)  # ammo boxes
	return c
