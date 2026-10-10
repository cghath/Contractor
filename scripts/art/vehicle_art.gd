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
	"marine_gray": {"paint": "68717a", "marking": "2a2e33"},
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

## UH-60 Black Hawk at 5 cm voxels, drawn from its real dimensions: 15.3 m from nose to
## tail rotor, 2.36 m wide cabin, two engines either side of the main transmission on the
## roof, the tail boom kinked up into a swept pylon with the tail rotor canted on its right,
## a low stabilator, forward main wheels on struts and a tail wheel.
static func _uh60() -> Canvas:
	var c := Canvas.new(Vector3i(96, 82, 314), 0.05)
	var fuselage := func(z: float) -> Vector4:
		var hw := 1.18
		var bottom := 0.55
		var top := 2.45
		if z < 1.3:  # nose cone
			var k := sqrt(z / 1.3)
			hw = lerpf(0.35, 1.12, k)
			bottom = lerpf(1.05, 0.6, k)
			top = lerpf(1.45, 2.0, k)
		elif z < 3.4:  # cockpit, windscreen rising to the roof
			var k := clampf((z - 1.3) / 1.3, 0.0, 1.0)
			hw = lerpf(1.12, 1.18, (z - 1.3) / 2.1)
			bottom = lerpf(0.6, 0.55, (z - 1.3) / 2.1)
			top = lerpf(2.0, 2.45, sqrt(k))
		elif z > 7.6:  # aft cabin closing up into the boom
			var k := clampf((z - 7.6) / 2.6, 0.0, 1.0)
			hw = lerpf(1.18, 0.45, pow(k, 0.8))
			bottom = lerpf(0.55, 1.6, k)
			top = lerpf(2.45, 2.3, k)
		return Vector4(0.0, (top + bottom) * 0.5, hw, (top - bottom) * 0.5)
	c.mloft(0.0, 10.25, fuselage, P.PAINT, 3.4, 0.12)
	var boom := func(z: float) -> Vector4:
		var k := clampf((z - 10.1) / 4.3, 0.0, 1.0)
		return Vector4(0.0, lerpf(1.95, 2.2, k), lerpf(0.45, 0.28, k), lerpf(0.38, 0.27, k))
	c.mloft(10.1, 14.45, boom, P.PAINT, 2.2)
	# Roof: transmission fairing, the two engine nacelles, intakes and IR exhaust suppressors.
	var fairing := func(z: float) -> Vector4:
		var k := clampf((z - 2.9) / 6.2, 0.0, 1.0)
		var bump := sin(PI * k)
		return Vector4(0.0, 2.45, 0.92 * minf(bump * 1.6, 1.0), 0.65 * minf(bump * 1.4, 1.0))
	c.mloft(2.9, 9.1, fairing, P.PAINT, 2.8)
	for side: float in [-1.0, 1.0]:
		var nacelle := func(z: float) -> Vector4:
			var k := clampf((z - 4.6) / 3.3, 0.0, 1.0)
			return Vector4(side * 0.74, 2.78, 0.34 * (0.85 + 0.15 * sin(PI * k)), 0.33)
		c.mloft(4.6, 7.95, nacelle, P.PAINT, 2.2)
		c.mbox(side * 0.74 - 0.22, 2.58, 4.55, side * 0.74 + 0.22, 3.0, 4.65, P.BLACK)
		c.mbox(minf(side * 0.72, side * 1.12), 2.6, 7.9, maxf(side * 0.72, side * 1.12), 2.98, 8.7, P.PAINT_DARK)
		c.mbox(minf(side * 1.05, side * 1.14), 2.62, 8.0, maxf(side * 1.05, side * 1.14), 2.95, 8.65, P.BLACK)
	# Rotor mast and hub; the blades are a separate node so they can turn.
	var mast := func(_z: float) -> Vector4: return Vector4(0.0, 3.4, 0.2, 0.45)
	c.mloft(4.85, 5.25, mast, P.METAL, 2.0)
	c.mbox(-0.35, 3.7, 4.7, 0.35, 3.9, 5.4, P.BLACK)
	c.rotor("MainRotor", Vector3(0.0, 3.92, 5.05), 8.18, 0.53, 4, Vector3.UP)
	# Swept tail pylon, tail rotor canted 20 degrees on its right, stabilator low on the pylon.
	var y := 2.05
	while y < 4.3:
		var front := 13.55 + (y - 2.05) * 0.5
		var back := 14.95 + (y - 2.05) * 0.16
		c.mbox(-0.12, y, front, 0.12, y + 0.05, back, P.PAINT)
		y += 0.05
	c.mbox(-0.1, 4.2, 14.6, 0.1, 4.32, 15.3, P.PAINT_DARK)
	c.mbox(0.12, 3.55, 14.85, 0.32, 3.85, 15.1, P.METAL)
	c.rotor("TailRotor", Vector3(0.36, 3.7, 14.98), 1.67, 0.25, 4, Vector3(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)), 0.0))
	c.mbox(-2.2, 1.92, 14.3, 2.2, 2.02, 15.35, P.PAINT)
	c.mbox(-2.2, 1.92, 14.15, -1.6, 2.02, 14.3, P.PAINT)
	c.mbox(1.6, 1.92, 14.15, 2.2, 2.02, 14.3, P.PAINT)
	# Glass: windscreen and cockpit side windows, chin windows, gunner and cabin windows.
	c.mskin(-1.25, 1.55, 0.9, 1.25, 2.47, 2.55, P.GLASS)
	c.mskin(-1.25, 1.45, 2.55, 1.25, 2.38, 3.3, P.GLASS)
	c.mskin(-0.95, 0.72, 0.5, 0.95, 1.3, 1.6, P.GLASS)
	c.mbox(-0.04, 1.7, 0.95, 0.04, 2.5, 2.6, P.PAINT_DARK)  # windscreen centre post
	for side: float in [-1.0, 1.0]:
		var sx := side * 1.2
		c.mbox(minf(sx, sx * 0.94), 1.4, 2.5, maxf(sx, sx * 0.94), 2.45, 2.6, P.PAINT_DARK)  # door frame
		c.mbox(minf(sx, sx * 0.94), 1.4, 3.3, maxf(sx, sx * 0.94), 2.45, 3.4, P.PAINT_DARK)
	c.mskin(-1.25, 1.55, 3.55, 1.25, 2.2, 4.15, P.GLASS)  # gunner's windows
	c.mskin(-1.25, 1.6, 4.55, 1.25, 2.15, 5.35, P.GLASS)  # sliding door windows
	c.mskin(-1.25, 1.6, 6.6, 1.25, 2.1, 7.3, P.GLASS)
	# Sliding cabin door outline and the step under it.
	c.mskin(-1.25, 0.6, 4.25, 1.25, 2.4, 4.32, P.PAINT_DARK, P.PAINT)
	c.mskin(-1.25, 0.6, 5.95, 1.25, 2.4, 6.02, P.PAINT_DARK, P.PAINT)
	c.mskin(-1.25, 2.33, 4.25, 1.25, 2.4, 6.0, P.PAINT_DARK, P.PAINT)
	c.mbox(-1.28, 0.62, 4.35, 1.28, 0.68, 5.9, P.PAINT_DARK)
	# M240 door guns on the gunner's window mounts.
	for side: float in [-1.0, 1.0]:
		var gx := side * 1.27
		c.mbox(gx - 0.05, 1.78, 3.55, gx + 0.05, 1.93, 4.35, P.GUN)
		c.mbox(gx - 0.025, 1.83, 2.9, gx + 0.025, 1.88, 3.55, P.GUN)
		c.mbox(gx - 0.06, 1.64, 4.0, gx + 0.06, 1.78, 4.15, P.GUN)  # ammo box
	# Main gear: wheels forward of the cabin on a strut and drag brace each side; tail wheel.
	for side: float in [-1.0, 1.0]:
		c.mbar(Vector3(side * 1.1, 0.95, 3.0), Vector3(side * 1.38, 0.32, 3.15), 0.1, P.METAL)
		c.mbar(Vector3(side * 1.1, 0.75, 4.0), Vector3(side * 1.38, 0.32, 3.2), 0.08, P.METAL)
		c.mwheel(minf(side * 1.28, side * 1.5), maxf(side * 1.28, side * 1.5), 0.31, 3.15, 0.31)
	c.mbar(Vector3(0.0, 1.75, 13.0), Vector3(0.0, 0.25, 13.15), 0.08, P.METAL)
	c.mwheel(-0.08, 0.08, 0.22, 13.15, 0.22)
	# Wire cutters, antennas, nav lights, the anti-collision beacon and the boom's band.
	c.mbox(-0.03, 2.45, 1.9, 0.03, 2.75, 2.0, P.METAL)
	c.mbox(-0.03, 0.45, 1.2, 0.03, 0.6, 1.3, P.METAL)
	c.mbar(Vector3(0.0, 2.3, 9.5), Vector3(0.0, 2.75, 10.1), 0.04, P.METAL)
	c.mbox(-1.22, 1.9, 3.4, -1.15, 1.98, 3.5, P.LIGHT_RED)
	c.mbox(1.15, 1.9, 3.4, 1.22, 1.98, 3.5, P.LIGHT_GREEN)
	c.mbox(-0.05, 2.25, 11.0, 0.05, 2.32, 11.1, P.LIGHT_RED)
	c.mskin(-0.6, 1.5, 11.8, 0.6, 2.6, 12.2, P.MARKING, P.PAINT)
	return c




## AH-1Z Viper: a narrow (about 1 m) fuselage with a stepped tandem canopy (gunner in front
## and lower), the targeting sight ball on the nose, the three-barrel M197 chin turret,
## engines high on either side of the transmission with upturned exhausts, stub wings
## carrying rocket pods, Hellfire racks and wingtip Sidewinder rails, and skids.
static func _ah1z() -> Canvas:
	var c := Canvas.new(Vector3i(96, 88, 278), 0.05)
	var fuselage := func(z: float) -> Vector4:
		var hw := 0.48
		var bottom := 0.75
		var top := 1.95
		if z < 1.5:
			var k := sqrt(z / 1.5)
			hw = lerpf(0.22, 0.48, k)
			bottom = lerpf(1.0, 0.78, k)
			top = lerpf(1.35, 1.7, k)
		elif z < 3.4:
			top = lerpf(1.7, 2.15, sqrt(clampf((z - 1.5) / 0.8, 0.0, 1.0)))  # gunner's canopy
		elif z < 5.2:
			top = lerpf(2.15, 2.45, sqrt(clampf((z - 3.4) / 0.6, 0.0, 1.0)))  # pilot sits higher
			top = lerpf(top, 1.95, clampf((z - 4.7) / 0.5, 0.0, 1.0))
		elif z > 8.9:
			var k := clampf((z - 8.9) / 1.5, 0.0, 1.0)
			hw = lerpf(0.48, 0.26, k)
			bottom = lerpf(0.75, 1.55, k)
			top = lerpf(1.95, 2.05, k)
		return Vector4(0.0, (top + bottom) * 0.5, hw, (top - bottom) * 0.5)
	c.mloft(0.25, 10.4, fuselage, P.PAINT, 3.0, 0.1)
	var boom := func(z: float) -> Vector4:
		var k := clampf((z - 10.3) / 3.0, 0.0, 1.0)
		return Vector4(0.0, lerpf(1.8, 2.05, k), lerpf(0.26, 0.17, k), lerpf(0.26, 0.18, k))
	c.mloft(10.3, 13.35, boom, P.PAINT, 2.2)
	# Canopy glass with frames between the two cockpits.
	c.mskin(-0.6, 1.55, 1.35, 0.6, 2.5, 5.0, P.GLASS)
	c.mbox(-0.5, 1.6, 3.3, 0.5, 2.5, 3.42, P.PAINT_DARK)
	c.mbox(-0.03, 1.9, 1.4, 0.03, 2.5, 5.0, P.PAINT_DARK)
	# Targeting sight ball on the nose and the M197 turret under the chin.
	var ball := func(z: float) -> Vector4:
		var k := clampf((z - 0.0) / 0.55, 0.0, 1.0)
		var r := 0.27 * sin(PI * k)
		return Vector4(0.0, 1.2, r, r)
	c.mloft(0.0, 0.55, ball, P.PAINT_DARK, 2.0)
	c.mskin(-0.15, 1.05, 0.0, 0.15, 1.35, 0.12, P.GLASS)
	c.mbox(-0.2, 0.45, 0.85, 0.2, 0.82, 1.35, P.PAINT_DARK)
	for bx: float in [-0.06, 0.0, 0.06]:
		c.mbox(bx - 0.025, 0.58, 0.05, bx + 0.025, 0.63, 0.9, P.GUN)
	# Transmission fairing, engines with upturned exhausts, mast and rotors.
	var fairing := func(z: float) -> Vector4:
		var k := clampf((z - 4.4) / 3.2, 0.0, 1.0)
		return Vector4(0.0, 1.95, 0.42 * minf(sin(PI * k) * 1.5, 1.0), 0.55 * minf(sin(PI * k) * 1.5, 1.0))
	c.mloft(4.4, 7.6, fairing, P.PAINT, 2.6)
	for side: float in [-1.0, 1.0]:
		var nacelle := func(_z: float) -> Vector4: return Vector4(side * 0.56, 2.08, 0.3, 0.3)
		c.mloft(5.0, 7.95, nacelle, P.PAINT, 2.2)
		c.mbox(side * 0.56 - 0.18, 1.9, 4.95, side * 0.56 + 0.18, 2.26, 5.05, P.BLACK)
		c.mbar(Vector3(side * 0.6, 2.15, 7.9), Vector3(side * 0.85, 2.6, 8.5), 0.26, P.PAINT_DARK)
		c.mbox(side * 0.85 - 0.1, 2.58, 8.4, side * 0.85 + 0.1, 2.68, 8.6, P.BLACK)
	var mast := func(_z: float) -> Vector4: return Vector4(0.0, 2.85, 0.16, 0.4)
	c.mloft(5.6, 5.9, mast, P.METAL, 2.0)
	c.rotor("MainRotor", Vector3(0.0, 3.3, 5.75), 7.3, 0.58, 4, Vector3.UP)
	# Fin swept back, tail rotor on its right, horizontal stabiliser with end plates.
	var y := 1.95
	while y < 3.6:
		c.mbox(-0.1, y, 12.45 + (y - 1.95) * 0.45, 0.1, y + 0.05, 13.55 + (y - 1.95) * 0.1, P.PAINT)
		y += 0.05
	c.rotor("TailRotor", Vector3(0.28, 3.0, 13.2), 1.45, 0.24, 4, Vector3.RIGHT)
	c.mbox(0.1, 2.85, 13.05, 0.24, 3.15, 13.35, P.METAL)
	c.mbox(-1.4, 1.92, 11.0, 1.4, 2.0, 11.65, P.PAINT)
	c.mbox(-1.45, 1.75, 10.95, -1.35, 2.25, 11.7, P.PAINT)
	c.mbox(1.35, 1.75, 10.95, 1.45, 2.25, 11.7, P.PAINT)
	# Stub wings and stores: rocket pods inboard, Hellfire racks outboard, Sidewinder rails.
	c.mbox(-2.2, 1.22, 5.35, 2.2, 1.34, 6.35, P.PAINT)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 1.1 - 0.05, 1.05, 5.5, side * 1.1 + 0.05, 1.22, 6.1, P.PAINT_DARK)
		var pod := func(_z: float) -> Vector4: return Vector4(side * 1.1, 0.83, 0.22, 0.22)
		c.mloft(4.6, 6.3, pod, P.PAINT_DARK, 2.0)
		c.mbox(side * 1.1 - 0.16, 0.68, 4.58, side * 1.1 + 0.16, 0.98, 4.64, P.BLACK)
		c.mbox(side * 1.85 - 0.25, 1.1, 5.3, side * 1.85 + 0.25, 1.22, 6.4, P.PAINT_DARK)
		for hx: float in [-0.12, 0.12]:
			for hy: float in [0.85, 1.02]:
				c.mbox(side * 1.85 + hx - 0.05, hy, 4.9, side * 1.85 + hx + 0.05, hy + 0.1, 6.5, P.PAINT_LIGHT)
		c.mbox(side * 2.25 - 0.04, 1.2, 5.0, side * 2.25 + 0.04, 1.3, 7.0, P.PAINT_LIGHT)
	# Skids with curved toes and cross tubes.
	for side: float in [-1.0, 1.0]:
		c.mbar(Vector3(side * 0.95, 0.08, 2.5), Vector3(side * 0.95, 0.08, 8.6), 0.08, P.METAL)
		c.mbar(Vector3(side * 0.95, 0.08, 2.5), Vector3(side * 0.95, 0.35, 2.0), 0.08, P.METAL)
		for cz: float in [3.4, 7.3]:
			c.mbar(Vector3(side * 0.95, 0.1, cz), Vector3(side * 0.42, 0.8, cz), 0.08, P.METAL)
	c.mskin(-0.6, 1.0, 9.2, 0.6, 2.2, 9.6, P.MARKING, P.PAINT)
	return c


# --- Ground vehicles --------------------------------------------------------------------

## Tracks in metres: road wheels, drive sprocket and idler on each side.
static func _mtracks(c: Canvas, inner: float, outer: float, z0: float, z1: float, wheels: int, r: float, sprocket_front: bool) -> void:
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * inner, side * outer)
		var x1 := maxf(side * inner, side * outer)
		c.mbox(x0, 0.0, z0 + r, x1, 0.08, z1 - r, P.TRACK)
		c.mbox(x0, 2.0 * r + 0.18, z0 + r * 0.8, x1, 2.0 * r + 0.26, z1 - r * 0.8, P.TRACK)
		var step := (z1 - z0 - 3.2 * r) / maxf(wheels - 1, 1)
		for i in wheels:
			c.mwheel(x0, x1, r + 0.04, z0 + 1.6 * r + i * step, r, P.TRACK, P.METAL)
		var front_r := r * (0.85 if sprocket_front else 0.75)
		var back_r := r * (0.75 if sprocket_front else 0.85)
		c.mwheel(x0, x1, r + 0.22, z0 + front_r, front_r, P.TRACK, P.METAL)
		c.mwheel(x0, x1, r + 0.18, z1 - back_r, back_r, P.TRACK, P.METAL)


## Hull cross-section of a tracked vehicle: slab sides, flat roof, sloped bow.
static func _hull(c: Canvas, z0: float, z1: float, half_w: float, bottom: float, top: float, bow_len: float, bow_top: float, bow_bottom: float) -> void:
	var z := z0
	while z < z1:
		var t := 0.0 if bow_len <= 0.0 else clampf((z - z0) / bow_len, 0.0, 1.0)
		c.mbox(-half_w, lerpf(bow_bottom, bottom, t), z, half_w, lerpf(bow_top, top, t), z + c.vs, P.PAINT)
		z += c.vs


## AAV-7A1: 7.9 m slab-sided amphibious hull over wide tracks, steep bow with the bow plane,
## upgunned weapon station (Mk19 and M2) front right, driver and commander cupolas front left,
## and the big rear ramp.
static func _aav7() -> Canvas:
	var c := Canvas.new(Vector3i(68, 68, 160), 0.05)
	_mtracks(c, 1.12, 1.62, 0.6, 7.6, 6, 0.3, true)
	_hull(c, 0.0, 7.95, 1.12, 0.45, 2.6, 1.8, 1.45, 1.05)
	_hull(c, 0.4, 7.9, 1.63, 1.12, 2.6, 1.4, 1.8, 1.25)  # sponsons over the tracks
	c.mbox(-1.63, 0.95, 0.9, 1.63, 1.12, 7.7, P.PAINT_DARK)  # track skirt line
	c.mskin(-1.4, 1.35, 0.0, 1.4, 2.4, 1.7, P.PAINT_DARK, P.PAINT)  # bow plane
	c.mbox(-1.1, 0.55, 7.9, 1.1, 2.45, 7.98, P.PAINT_DARK)  # ramp
	c.mbox(-0.08, 2.05, 7.95, 0.08, 2.35, 8.0, P.METAL)
	# Roof cargo hatches.
	c.mskin(-1.0, 2.55, 3.6, 1.0, 2.62, 7.0, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.95, 2.6, 3.65, -0.05, 2.62, 6.95, P.PAINT)
	c.mbox(0.05, 2.6, 3.65, 0.95, 2.62, 6.95, P.PAINT)
	# Weapon station front right with the Mk19 (thick) and M2 (long) guns.
	c.mbox(0.25, 2.6, 1.6, 1.42, 3.22, 3.0, P.PAINT)
	c.mbox(0.3, 3.22, 1.75, 1.35, 3.28, 2.85, P.PAINT_DARK)
	c.mskin(0.3, 2.95, 1.55, 1.35, 3.15, 1.65, P.GLASS)
	c.mbox(0.48, 2.78, 0.75, 0.62, 2.92, 1.6, P.GUN)
	c.mbox(0.92, 2.8, 0.2, 0.98, 2.86, 1.6, P.GUN)
	c.mbox(0.88, 2.76, 0.2, 1.02, 2.9, 0.3, P.GUN)
	# Driver's and commander's cupolas with vision blocks.
	c.mbox(-1.3, 2.6, 1.8, -0.55, 2.8, 2.5, P.PAINT)
	c.mskin(-1.3, 2.62, 1.75, -0.55, 2.78, 1.85, P.GLASS)
	c.mbox(-1.25, 2.6, 2.75, -0.6, 2.95, 3.35, P.PAINT)
	c.mskin(-1.25, 2.75, 2.7, -0.6, 2.9, 3.4, P.GLASS)
	# Headlights, tow hooks, exhaust grille on the right side.
	c.mbox(-1.2, 1.55, 0.95, -0.95, 1.7, 1.05, P.PAINT_LIGHT)
	c.mbox(0.95, 1.55, 0.95, 1.2, 1.7, 1.05, P.PAINT_LIGHT)
	c.mskin(1.55, 1.7, 2.0, 1.7, 2.3, 3.0, P.BLACK)
	return c


## M2A3 Bradley: 6.5 m hull with a long sloped glacis, side armour tiles, six road wheels
## and the rear ramp; turret with the 25 mm Bushmaster, the twin TOW box on its left, the
## gunner's sight and the commander's independent viewer.
static func _bradley() -> Canvas:
	var c := Canvas.new(Vector3i(74, 68, 132), 0.05)
	_mtracks(c, 1.15, 1.6, 0.4, 6.5, 6, 0.3, true)
	_hull(c, 0.0, 6.5, 1.6, 0.5, 1.95, 1.3, 1.05, 0.55)
	c.mbox(-1.6, 0.5, 0.0, 1.6, 0.95, 0.15, P.PAINT)
	# Side armour skirts with reactive tiles.
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * 1.6, side * 1.8)
		var x1 := maxf(side * 1.6, side * 1.8)
		var z := 0.7
		var row := 0
		while z < 6.2:
			c.mbox(x0, 0.55, z, x1, 1.05, z + 0.5, P.PAINT if row % 2 == 0 else P.PAINT_DARK)
			c.mbox(x0, 1.05, z, x1, 1.5, z + 0.5, P.PAINT_DARK if row % 2 == 0 else P.PAINT)
			z += 0.5
			row += 1
	c.mbox(-1.2, 0.6, 6.45, 1.2, 1.9, 6.52, P.PAINT_DARK)  # ramp
	c.mskin(0.35, 1.9, 1.2, 1.45, 2.0, 2.1, P.BLACK, P.PAINT)  # engine grille, front right
	c.mbox(-1.35, 1.95, 1.3, -0.75, 2.1, 1.9, P.PAINT)  # driver's hatch
	c.mskin(-1.35, 1.98, 1.25, -0.75, 2.08, 1.35, P.GLASS)
	# Turret.
	var z := 1.95
	while z < 4.3:
		var half := lerpf(0.75, 1.05, clampf((z - 1.95) / 0.6, 0.0, 1.0))
		c.mbox(-half + 0.1, 1.95, z, half + 0.1, 2.65, z + c.vs, P.PAINT)
		z += c.vs
	c.mbox(-0.6, 2.65, 2.4, 0.8, 2.7, 4.0, P.PAINT_DARK)
	c.mbox(0.05, 2.1, 1.75, 0.55, 2.55, 2.05, P.PAINT_DARK)  # mantlet
	c.mbox(0.2, 2.27, 0.25, 0.3, 2.37, 1.8, P.GUN)  # 25 mm barrel
	c.mbox(0.18, 2.25, 0.25, 0.32, 2.39, 0.4, P.GUN)
	c.mbox(0.42, 2.25, 1.4, 0.48, 2.31, 1.8, P.GUN)  # coax M240
	c.mbox(-1.42, 2.05, 2.0, -0.92, 2.6, 3.4, P.PAINT_LIGHT)  # TOW launcher
	c.mbox(-1.38, 2.1, 1.98, -1.18, 2.3, 2.02, P.BLACK)
	c.mbox(-1.15, 2.1, 1.98, -0.96, 2.3, 2.02, P.BLACK)
	c.mbox(-0.55, 2.65, 2.2, -0.15, 2.95, 2.6, P.PAINT)  # gunner's sight
	c.mskin(-0.55, 2.7, 2.15, -0.15, 2.9, 2.25, P.GLASS)
	c.mbox(0.45, 2.7, 3.3, 0.85, 3.12, 3.7, P.PAINT)  # commander's viewer
	c.mskin(0.45, 2.85, 3.25, 0.85, 3.05, 3.35, P.GLASS)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 0.95 - 0.12 + 0.1, 2.3, 2.0, side * 0.95 + 0.12 + 0.1, 2.5, 2.2, P.PAINT_DARK)  # smoke launchers
	c.mbar(Vector3(0.9, 2.7, 4.1), Vector3(0.9, 3.35, 4.15), 0.03, P.METAL)  # antenna
	return c


## M1A2 SEP Abrams: 7.9 m hull with a long shallow glacis, seven road wheels under side
## skirts, the wide angular turret with bustle rack, the 120 mm gun with bore evacuator,
## gunner's sight, commander's viewer and CROWS, and the engine deck grilles.
static func _abrams() -> Canvas:
	var c := Canvas.new(Vector3i(76, 60, 198), 0.05)
	var hz := 1.9  # the hull starts here; the gun reaches the front of the canvas
	_mtracks(c, 1.2, 1.7, hz + 0.3, hz + 7.9, 7, 0.32, false)
	_hull(c, hz, hz + 7.93, 1.7, 0.5, 1.5, 1.5, 0.95, 0.65)
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * 1.7, side * 1.83)
		var x1 := maxf(side * 1.7, side * 1.83)
		c.mbox(x0, 0.55, hz + 0.2, x1, 1.2, hz + 7.4, P.PAINT)
		var z := hz + 0.2
		while z < hz + 7.4:
			c.mbox(x0, 0.55, z, x1, 1.2, z + 0.04, P.PAINT_DARK)
			z += 1.0
	c.mbox(-1.4, 1.3, hz + 6.4, 1.4, 1.52, hz + 7.9, P.PAINT_DARK)  # engine deck
	var gz := hz + 6.5
	while gz < hz + 7.85:
		c.mbox(-1.3, 1.5, gz, 1.3, 1.53, gz + 0.05, P.BLACK)
		gz += 0.15
	c.mbox(-1.5, 0.6, hz + 7.9, 1.5, 1.45, hz + 7.95, P.METAL)  # exhaust grille
	# Turret: wedge-shaped front, slab sides, bustle and its rack.
	var z := hz + 1.3
	while z < hz + 6.0:
		var half := lerpf(0.7, 1.85, clampf((z - hz - 1.3) / 1.5, 0.0, 1.0))
		var top := lerpf(2.15, 2.35, clampf((z - hz - 1.3) / 1.0, 0.0, 1.0))
		c.mbox(-half, 1.5, z, half, top, z + c.vs, P.PAINT)
		z += c.vs
	c.mbox(-1.7, 1.6, hz + 6.0, 1.7, 2.25, hz + 6.9, P.PAINT_DARK)  # bustle rack
	c.mbox(-1.6, 1.65, hz + 6.05, 1.6, 2.2, hz + 6.85, P.PAINT)
	# 120 mm gun, mantlet, bore evacuator.
	c.mbox(-0.48, 1.65, hz + 1.1, 0.48, 2.15, hz + 1.4, P.PAINT_DARK)
	var tube := func(zz: float) -> Vector4:
		var r := lerpf(0.11, 0.085, zz / (hz + 1.2))
		if zz > 1.1 and zz < 1.55:
			r = 0.14
		return Vector4(0.0, 1.92, r, r)
	c.mloft(0.0, hz + 1.2, tube, P.PAINT, 2.0)
	c.mbox(-0.06, 2.0, 0.0, 0.06, 2.06, 0.12, P.METAL)  # muzzle reference sensor
	# Sights and weapons on the roof.
	c.mbox(0.85, 2.35, hz + 2.1, 1.3, 2.62, hz + 2.6, P.PAINT)  # gunner's primary sight
	c.mskin(0.85, 2.4, hz + 2.05, 1.3, 2.58, hz + 2.15, P.GLASS)
	c.mbox(-0.5, 2.35, hz + 2.7, -0.05, 2.85, hz + 3.15, P.PAINT)  # commander's viewer
	c.mskin(-0.5, 2.5, hz + 2.65, -0.05, 2.75, hz + 2.75, P.GLASS)
	c.mbox(0.3, 2.35, hz + 3.4, 1.0, 2.85, hz + 4.1, P.PAINT_DARK)  # CROWS
	c.mbox(0.6, 2.6, hz + 2.3, 0.66, 2.66, hz + 3.4, P.GUN)
	c.mbox(-1.35, 2.35, hz + 3.6, -0.7, 2.75, hz + 3.66, P.PAINT)  # loader's shield
	c.mbox(-1.05, 2.5, hz + 2.9, -0.99, 2.56, hz + 3.6, P.GUN)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 1.45 - 0.15, 1.95, hz + 2.4, side * 1.45 + 0.15, 2.2, hz + 2.75, P.PAINT_DARK)  # smoke
	c.mbar(Vector3(-1.2, 2.3, hz + 5.8), Vector3(-1.2, 3.0, hz + 5.85), 0.03, P.METAL)
	c.mbar(Vector3(1.2, 2.3, hz + 5.8), Vector3(1.2, 3.0, hz + 5.85), 0.03, P.METAL)
	return c


## MaxxPro: 6.5 m MRAP with a short bonnet and big grille, one tall armoured cab-and-troop
## box with small thick windows, a V-hull, 0.58 m radius wheels, rear door with a spare, and
## a roof turret with the gun-protection kit and an M2.
static func _maxxpro() -> Canvas:
	var c := Canvas.new(Vector3i(54, 66, 130), 0.05)
	var hw := 1.2
	# V-hull, bonnet, cab and troop box.
	var y := 0.45
	while y < 0.95:
		var inset := (0.95 - y) * 1.6
		c.mbox(-hw + inset, y, 0.9, hw - inset, y + c.vs, 6.1, P.PAINT_DARK)
		y += c.vs
	c.mbox(-1.05, 0.95, 0.15, 1.05, 1.65, 1.15, P.PAINT)
	c.mbox(-1.0, 1.65, 0.25, 1.0, 1.72, 1.1, P.PAINT_LIGHT)
	c.mbox(-0.85, 1.0, 0.12, 0.85, 1.55, 0.17, P.BLACK)  # grille
	var gx := -0.8
	while gx < 0.85:
		c.mbox(gx, 1.0, 0.1, gx + 0.05, 1.55, 0.15, P.PAINT_DARK)
		gx += 0.15
	c.mbox(-1.15, 0.7, 0.0, 1.15, 0.95, 0.25, P.PAINT_DARK)  # bumper
	c.mbox(-hw, 0.95, 1.15, hw, 2.75, 6.35, P.PAINT)
	c.mbox(-hw + 0.1, 2.75, 1.4, hw - 0.1, 2.8, 6.1, P.PAINT_DARK)
	# Thick armoured glass: two windscreen panes, cab doors, troop windows.
	c.mskin(-1.05, 1.8, 1.1, -0.06, 2.55, 1.2, P.GLASS)
	c.mskin(0.06, 1.8, 1.1, 1.05, 2.55, 1.2, P.GLASS)
	c.mskin(-1.25, 1.85, 1.4, 1.25, 2.5, 2.2, P.GLASS)
	c.mskin(-1.25, 1.85, 2.45, 1.25, 2.5, 3.15, P.GLASS)
	for wz: float in [3.8, 4.7, 5.6]:
		c.mskin(-1.25, 1.95, wz, 1.25, 2.35, wz + 0.4, P.GLASS)
	c.mskin(-1.25, 1.0, 1.35, 1.25, 2.6, 1.4, P.PAINT_DARK, P.PAINT)  # door seams
	c.mskin(-1.25, 1.0, 3.2, 1.25, 2.6, 3.25, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.65, 1.05, 6.35, 0.65, 2.55, 6.42, P.PAINT_DARK)  # rear door
	c.mwheel(-0.25, 0.25, 1.65, 6.48, 0.45)  # spare (tread facing back)
	# Wheels and arches, mirrors, lights, steps.
	for wz: float in [1.25, 5.05]:
		for side: float in [-1.0, 1.0]:
			c.mwheel(minf(side * 0.95, side * 1.3), maxf(side * 0.95, side * 1.3), 0.58, wz, 0.58)
			c.mbox(minf(side * 1.0, side * 1.3), 1.15, wz - 0.7, maxf(side * 1.0, side * 1.3), 1.25, wz + 0.7, P.PAINT_DARK)
	for side: float in [-1.0, 1.0]:
		c.mbar(Vector3(side * 1.2, 2.2, 1.3), Vector3(side * 1.45, 2.25, 1.2), 0.04, P.METAL)
		c.mbox(side * 1.4, 1.9, 1.12, side * 1.4 + side * 0.1, 2.3, 1.25, P.BLACK)
		c.mbox(side * 0.85 - 0.12, 1.25, 0.12, side * 0.85 + 0.12, 1.4, 0.15, P.PAINT_LIGHT)
		c.mbox(minf(side * 1.2, side * 1.32), 0.8, 1.9, maxf(side * 1.2, side * 1.32), 0.85, 2.4, P.METAL)
	_turret(c, 0.0, 2.8, 2.7, 1.0)
	return c


## M-ATV: 6.2 m MRAP all-terrain vehicle with a long sloped bonnet and slatted grille, a
## compact armoured cab with a raked windscreen, rear cargo bed, big flared wheel arches,
## and the roof turret.
static func _matv() -> Canvas:
	var c := Canvas.new(Vector3i(54, 58, 126), 0.05)
	var y := 0.4
	while y < 0.9:
		var inset := (0.9 - y) * 1.4
		c.mbox(-1.15 + inset, y, 0.5, 1.15 - inset, y + c.vs, 6.0, P.PAINT_DARK)
		y += c.vs
	# Bonnet sloping down to the grille.
	var z := 0.05
	while z < 2.05:
		var top := lerpf(1.3, 1.6, clampf(z / 1.4, 0.0, 1.0))
		c.mbox(-1.05, 0.9, z, 1.05, top, z + c.vs, P.PAINT)
		z += c.vs
	var gx := -0.75
	while gx < 0.8:
		c.mbox(gx, 0.95, 0.0, gx + 0.06, 1.28, 0.06, P.BLACK)
		gx += 0.12
	c.mbox(-1.15, 0.65, 0.0, 1.15, 0.9, 0.2, P.PAINT_DARK)
	# Cab with raked windscreen, then the cargo bed.
	z = 2.0
	while z < 4.35:
		var top := lerpf(1.6, 2.35, clampf((z - 2.0) / 0.45, 0.0, 1.0))
		c.mbox(-1.15, 0.9, z, 1.15, top, z + c.vs, P.PAINT)
		z += c.vs
	c.mskin(-1.05, 1.65, 2.0, -0.05, 2.3, 2.5, P.GLASS)
	c.mskin(0.05, 1.65, 2.0, 1.05, 2.3, 2.5, P.GLASS)
	c.mskin(-1.2, 1.7, 2.6, 1.2, 2.25, 3.3, P.GLASS)
	c.mskin(-1.2, 1.7, 3.5, 1.2, 2.25, 4.1, P.GLASS)
	c.mskin(-1.2, 0.95, 3.38, 1.2, 2.3, 3.43, P.PAINT_DARK, P.PAINT)
	c.mbox(-1.15, 0.9, 4.35, 1.15, 1.25, 6.2, P.PAINT)
	c.mbox(-1.15, 1.25, 4.35, -1.05, 1.65, 6.2, P.PAINT)
	c.mbox(1.05, 1.25, 4.35, 1.15, 1.65, 6.2, P.PAINT)
	c.mbox(-1.15, 1.25, 6.1, 1.15, 1.65, 6.2, P.PAINT)
	c.mbox(-0.9, 1.25, 4.6, 0.9, 1.55, 5.6, P.SEAT)  # stowed kit in the bed
	for wz: float in [1.0, 4.95]:
		for side: float in [-1.0, 1.0]:
			c.mwheel(minf(side * 0.9, side * 1.24), maxf(side * 0.9, side * 1.24), 0.56, wz, 0.56)
			c.mbox(minf(side * 1.0, side * 1.25), 1.12, wz - 0.75, maxf(side * 1.0, side * 1.25), 1.22, wz + 0.75, P.PAINT_DARK)
	for side: float in [-1.0, 1.0]:
		c.mbar(Vector3(side * 1.15, 2.0, 2.2), Vector3(side * 1.4, 2.05, 2.1), 0.04, P.METAL)
		c.mbox(side * 1.35, 1.75, 2.02, side * 1.35 + side * 0.1, 2.1, 2.15, P.BLACK)
		c.mbox(side * 0.8 - 0.12, 1.1, 0.0, side * 0.8 + 0.12, 1.22, 0.05, P.PAINT_LIGHT)
	_turret(c, 0.0, 2.35, 3.3, 0.9)
	return c


## Roof turret ring with the four-sided gun-protection kit and an M2, centred at (x, z).
static func _turret(c: Canvas, x: float, roof: float, z: float, half: float) -> void:
	c.mbox(x - half * 0.8, roof, z - half * 0.8, x + half * 0.8, roof + 0.1, z + half * 0.8, P.PAINT_DARK)
	c.mbox(x - half, roof + 0.1, z - half, x + half, roof + 0.55, z - half + 0.05, P.PAINT)  # front shield
	c.mskin(x - 0.25, roof + 0.3, z - half - 0.01, x + 0.25, roof + 0.5, z - half + 0.06, P.GLASS)
	c.mbox(x - half, roof + 0.1, z - half, x - half + 0.05, roof + 0.5, z + half * 0.5, P.PAINT)
	c.mbox(x + half - 0.05, roof + 0.1, z - half, x + half, roof + 0.5, z + half * 0.5, P.PAINT)
	c.mbox(x - 0.1, roof + 0.25, z - half + 0.1, x + 0.1, roof + 0.42, z, P.GUN)
	c.mbox(x - 0.03, roof + 0.31, z - half - 1.1, x + 0.03, roof + 0.37, z - half + 0.1, P.GUN)


# --- Technicals -------------------------------------------------------------------------

## The pickups technicals are built on: "hilux" (Toyota Hilux, 5.3 m) or "lc79" (Land
## Cruiser 79 pickup, 5.2 m, boxier and taller with a flat dropside bed). Returns the bed
## floor height.
static func _pickup(c: Canvas, base: String) -> float:
	var lc := base == "lc79"
	var hood_end := 1.85 if lc else 1.7
	var cab_end := 3.15 if lc else 3.0
	var length := 5.2 if lc else 5.25
	var roof := 1.95 if lc else 1.68
	var hood_top := 1.22 if lc else 1.05
	var bed := 0.95 if lc else 0.8
	var r := 0.4 if lc else 0.37
	var hw := 0.88
	# Lower body along the whole length.
	c.mbox(-hw, 0.45, 0.05, hw, bed, length, P.PAINT)
	# Bonnet (sloping on the Hilux, flat on the Land Cruiser) and grille.
	var z := 0.05
	while z < hood_end:
		var top := hood_top if lc else lerpf(0.95, hood_top, clampf(z / 0.8, 0.0, 1.0))
		c.mbox(-hw + 0.03, bed, z, hw - 0.03, top, z + c.vs, P.PAINT)
		z += c.vs
	c.mbox(-0.7, 0.62, 0.0, 0.7, hood_top - 0.08, 0.06, P.BLACK)
	if lc:
		var gx := -0.65
		while gx < 0.7:
			c.mbox(gx, 0.65, -0.01, gx + 0.04, hood_top - 0.1, 0.05, P.METAL)
			gx += 0.1
	c.mbox(-0.85, 0.75, 0.0, -0.6, 0.9, 0.06, P.PAINT_LIGHT)
	c.mbox(0.6, 0.75, 0.0, 0.85, 0.9, 0.06, P.PAINT_LIGHT)
	c.mbox(-0.9, 0.4, -0.02, 0.9, 0.6, 0.12, P.METAL)  # bumper
	# Cab with the windscreen raked (Hilux) or upright (Land Cruiser).
	z = hood_end
	var rake := 0.12 if lc else 0.42
	while z < cab_end:
		var top := lerpf(hood_top, roof, clampf((z - hood_end) / rake, 0.0, 1.0))
		c.mbox(-hw, bed, z, hw, top, z + c.vs, P.PAINT)
		z += c.vs
	c.mskin(-0.8, hood_top + 0.05, hood_end - 0.01, 0.8, roof - 0.06, hood_end + rake + 0.05, P.GLASS)
	c.mskin(-0.92, hood_top + 0.08, hood_end + rake + 0.1, 0.92, roof - 0.08, cab_end - 0.12, P.GLASS)
	c.mskin(-0.92, bed + 0.05, hood_end + 0.62, 0.92, roof - 0.05, hood_end + 0.66, P.PAINT_DARK, P.PAINT)
	c.mskin(-0.6, hood_top + 0.08, cab_end - 0.02, 0.6, roof - 0.12, cab_end + 0.02, P.GLASS)
	# Bed: dropsides and tailgate.
	var wall := bed + (0.5 if lc else 0.45)
	c.mbox(-hw, bed, cab_end + 0.05, -hw + 0.05, wall, length, P.PAINT)
	c.mbox(hw - 0.05, bed, cab_end + 0.05, hw, wall, length, P.PAINT)
	c.mbox(-hw, bed, length - 0.05, hw, wall, length, P.PAINT)
	c.mbox(-hw + 0.05, bed - 0.03, cab_end + 0.05, hw - 0.05, bed, length - 0.05, P.PAINT_DARK)
	# Wheels, arches, mirrors, rust and dents.
	var wb := 3.18 if lc else 3.08
	for wz: float in [0.95, 0.95 + wb]:
		for side: float in [-1.0, 1.0]:
			c.mwheel(minf(side * 0.68, side * 0.92), maxf(side * 0.68, side * 0.92), r, wz, r)
	for side: float in [-1.0, 1.0]:
		c.mbox(minf(side * 0.9, side * 1.02), hood_top + 0.1, hood_end + 0.05, maxf(side * 0.9, side * 1.02), hood_top + 0.22, hood_end + 0.15, P.BLACK)
	c.mskin(-1.0, 0.45, 1.6, 1.0, 0.6, length - 0.6, P.RUST, P.PAINT)
	c.mskin(-1.0, 0.7, 3.6, 1.0, 0.85, 4.1, P.PAINT_DARK, P.PAINT)
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
			c.mbox(-0.4, bed, mid - 0.2, 0.4, bed + 0.45, mid + 0.4, P.PAINT_DARK)  # mount
			# Twelve 107 mm tubes in three rows, tilted up 12 degrees.
			var tilt := tan(deg_to_rad(12.0))
			for row in 3:
				for col in 4:
					var x := -0.27 + col * 0.18
					var y0 := bed + 0.55 + row * 0.15
					c.mbar(Vector3(x, y0 + 0.5 * tilt, mid - 0.6), Vector3(x, y0 - 0.5 * tilt, mid + 0.45), 0.13, P.PAINT_DARK)
					c.mbox(x - 0.04, y0 + 0.5 * tilt - 0.04, mid - 0.62, x + 0.04, y0 + 0.5 * tilt + 0.04, mid - 0.58, P.BLACK)
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
