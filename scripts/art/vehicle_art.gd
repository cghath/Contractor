class_name VehicleArt
extends RefCounted
## Voxel vehicle models built in code, at the same 10 cm voxel size as the world's walls:
## UH-60 Black Hawk, AH-1Z Viper, AAV-7, M2 Bradley, M1 Abrams, MRAPs (MaxxPro, M-ATV)
## and a pickup technical.
##
## Each model is a canvas of voxels filled with boxes and rounded cross-sections, then
## meshed once per model and paint scheme and cached. Rotors and gun mounts are separate
## nodes so they can spin or turn later. Coordinates are voxels; front is -Z, up is +Y,
## and the model's origin is the middle of its footprint on the ground.

const VOXEL_SIZE := 0.1

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
	match model:
		"ah1z":
			_add_rotor(root, "MainRotor", _vx(size, 30, 39, 58), 7.3, 0.58, 4, Vector3.UP)
			_add_rotor(root, "TailRotor", _vx(size, 26, 35, 134), 1.4, 0.25, 4, Vector3.LEFT)
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
		"maxxpro": return _mrap(64, 25, 30, 11, true)
		"matv": return _mrap(62, 25, 27, 16, false)
		"technical": return _technical()
		"bradley": return _bradley()
		"abrams": return _abrams()
	push_error("VehicleArt: unknown model '%s'" % model)
	return Canvas.new(Vector3i.ONE)


## Voxel coordinates on a canvas to metres relative to the model origin.
static func _vx(size: Vector3i, x: float, y: float, z: float) -> Vector3:
	return Vector3(x - size.x * 0.5, y, z - size.z * 0.5) * VOXEL_SIZE


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


## AH-1Z Viper: 13.6 m fuselage only 1 m wide, tandem cockpit, stub wings with rocket pods
## and Hellfires, chin gun, skids.
static func _ah1z() -> Canvas:
	var c := Canvas.new(Vector3i(60, 44, 140))
	var cx := 30.0
	var fuselage := func(t: float) -> Vector4:
		var z := t * 91.0
		var hw := 5.5
		var hh := 10.0
		var cy := 17.0
		if z < 20.0:
			var k := sqrt(z / 20.0)
			hw = lerpf(2.0, 5.5, k)
			hh = lerpf(4.0, 10.0, k)
			cy = lerpf(13.0, 17.0, k)
		elif z > 72.0:
			var k := (z - 72.0) / 20.0
			hw = lerpf(5.5, 3.0, k)
			hh = lerpf(10.0, 4.0, k)
			cy = lerpf(17.0, 22.0, k)
		return Vector4(cx, cy, hw, hh)
	c.loft(0, 92, fuselage, P.PAINT)
	c.loft(88, 136, func(t: float) -> Vector4: return Vector4(cx, lerpf(22.0, 24.0, t), lerpf(3.0, 1.6, t), lerpf(4.0, 2.4, t)), P.PAINT)
	# Tandem canopy: a raised glass bubble over both seats.
	c.loft(10, 48, func(t: float) -> Vector4: return Vector4(cx, 24.0, 5.0 * sin(PI * clampf(t * 1.05, 0.0, 1.0)) + 0.5, 6.0 * sin(PI * clampf(t, 0.0, 1.0))), P.GLASS)
	c.box(29, 22, 26, 31, 31, 28, P.PAINT_DARK)  # frame between the cockpits
	# Engines either side of the rotor mast, exhausts pointing up and out.
	for side: float in [-1.0, 1.0]:
		c.loft(46, 82, func(t: float) -> Vector4: return Vector4(cx + side * 6.0, 27.0, 3.5, 3.5), P.PAINT_DARK)
		c.box(int(cx + side * 6.0) - 2, 28, 80, int(cx + side * 6.0) + 2, 32, 84, P.BLACK)
	c.box(29, 30, 56, 32, 38, 60, P.METAL)
	# Stub wings with a rocket pod and a Hellfire rack each side.
	c.box(4, 14, 54, 56, 16, 66, P.PAINT)
	for x0: int in [6, 48]:
		c.loft(48, 70, func(t: float) -> Vector4: return Vector4(x0 + 3.0, 11.0, 3.0, 3.0), P.PAINT_DARK)
		c.box(x0, 8, 48, x0 + 6, 9, 50, P.BLACK)
	for x0: int in [16, 40]:
		c.box(x0, 10, 52, x0 + 4, 14, 70, P.METAL)
		c.box(x0, 8, 50, x0 + 4, 10, 68, P.PAINT_LIGHT)
	# Chin turret with the 20 mm gun, skids, tail fin with the rotor on the left.
	c.box(27, 4, 6, 33, 8, 12, P.BLACK)
	c.box(29, 5, 0, 31, 7, 6, P.GUN)
	for x0: int in [19, 39]:
		c.box(x0, 0, 22, x0 + 2, 1, 80, P.METAL)
		c.box(x0, 1, 30, x0 + 2, 8, 32, P.METAL)
		c.box(x0, 1, 66, x0 + 2, 8, 68, P.METAL)
	for y in range(22, 40):
		var back := int((y - 22) * 0.5)
		c.box(29, y, 126 + back, 31, y + 1, 136, P.PAINT)
	c.box(18, 23, 118, 42, 25, 126, P.PAINT)
	c.paint_skin(0, 18, 76, 60, 24, 84, P.MARKING, P.PAINT)
	return c


# --- Ground vehicles --------------------------------------------------------------------

## AAV-7: 8.2 m tracked amphibious hull, sloped bow, up-gunned weapon station front right.
static func _aav7() -> Canvas:
	var c := Canvas.new(Vector3i(33, 34, 82))
	for z in 82:
		var top := 26
		var bottom := 4
		if z < 18:
			top = 14 + int(z * 12.0 / 18.0)  # sloped bow plate
			bottom = 4 + int((18 - z) * 6.0 / 18.0)
		c.box(1, bottom, z, 32, top, z + 1, P.PAINT)
	c.box(4, 26, 34, 29, 27, 76, P.PAINT_DARK)  # roof hatches
	c.paint_skin(0, 24, 40, 33, 27, 74, P.PAINT_DARK, P.PAINT)
	c.box(2, 4, 81, 31, 25, 82, P.PAINT_DARK)  # rear ramp
	# Tracks and road wheels down each side.
	for x0: int in [0, 27]:
		c.box(x0, 0, 8, x0 + 6, 2, 78, P.TRACK)
		c.box(x0, 10, 12, x0 + 6, 12, 76, P.TRACK)
		for i in 6:
			c.wheel(x0, x0 + 6, 5.5, 18.0 + i * 11.0, 5.0, P.TRACK, P.METAL)
		c.wheel(x0, x0 + 6, 7.0, 9.0, 4.0, P.TRACK, P.METAL)
		c.box(x0, 12, 6, x0 + 6, 14, 80, P.PAINT_DARK)  # track skirt
	# Weapon station (Mk19 and M2) and commander's cupola.
	c.box(19, 26, 18, 30, 33, 30, P.PAINT)
	c.box(21, 28, 6, 22, 30, 18, P.GUN)
	c.box(26, 28, 9, 27, 29, 18, P.GUN)
	c.paint_skin(19, 30, 17, 30, 32, 19, P.GLASS)
	c.box(5, 26, 28, 12, 30, 35, P.PAINT)
	c.paint_skin(5, 28, 27, 12, 30, 29, P.GLASS)
	c.box(2, 18, 2, 31, 19, 4, P.PAINT_DARK)  # trim vane folded on the bow
	c.box(3, 20, 0, 6, 22, 2, P.METAL)
	c.box(27, 20, 0, 30, 22, 2, P.METAL)
	return c


## MRAP: V-hull, armored cab and troop box, roof turret with gun shield, four big wheels.
## `hood` is the bonnet length in voxels; `troop_box` gives the MaxxPro's tall rear module.
static func _mrap(length: int, width: int, height: int, hood: int, troop_box: bool) -> Canvas:
	var c := Canvas.new(Vector3i(width + 2, height + 7, length))
	var x0 := 1
	var x1 := width + 1
	var floor_y := 9
	# V-hull under the body.
	for y in range(5, floor_y):
		var inset := (floor_y - y) * 2
		c.box(x0 + inset, y, 4, x1 - inset, y + 1, length - 4, P.PAINT_DARK)
	# Bonnet, cab and the rear troop compartment.
	c.box(x0 + 1, floor_y, 0, x1 - 1, floor_y + 9, hood, P.PAINT)
	c.box(x0 + 2, floor_y + 9, 2, x1 - 2, floor_y + 10, hood - 1, P.PAINT_LIGHT)
	c.box(x0 + 3, floor_y + 4, 0, x1 - 3, floor_y + 7, 1, P.BLACK)  # grille
	var cab_top := height if troop_box else height - 2
	c.box(x0, floor_y, hood, x1, cab_top, length - 1, P.PAINT)
	c.box(x0 + 1, cab_top, hood + 2, x1 - 1, cab_top + 1, length - 3, P.PAINT_DARK)
	# Thick armored glass: windscreen and side windows of the cab.
	c.paint_skin(x0 + 2, floor_y + 11, hood, x1 - 2, cab_top - 3, hood + 1, P.GLASS)
	c.paint_skin(x0, floor_y + 11, hood + 2, x1, cab_top - 3, hood + 18, P.GLASS)
	if troop_box:
		c.paint_skin(x0, floor_y + 13, hood + 24, x1, floor_y + 17, hood + 30, P.GLASS)
		c.paint_skin(x0, floor_y + 13, hood + 34, x1, floor_y + 17, hood + 40, P.GLASS)
	c.box(x0 + 3, floor_y + 1, length - 1, x1 - 3, cab_top - 2, length, P.PAINT_DARK)  # rear door
	c.wheel(x0 + 7, x1 - 7, floor_y + 6.0, length - 0.5, 4.0)  # spare tyre on the door
	# Roof turret: ring, gun shield and an M2.
	var tz := hood + 14
	c.box(x0 + 7, cab_top + 1, tz, x1 - 7, cab_top + 2, tz + 11, P.PAINT_DARK)
	c.box(x0 + 6, cab_top + 2, tz, x1 - 6, cab_top + 6, tz + 1, P.PAINT)
	c.box(x0 + 6, cab_top + 2, tz, x0 + 7, cab_top + 6, tz + 6, P.PAINT)
	c.box(x1 - 7, cab_top + 2, tz, x1 - 6, cab_top + 6, tz + 6, P.PAINT)
	c.paint_skin(x0 + 9, cab_top + 4, tz, x1 - 9, cab_top + 5, tz + 1, P.GLASS)
	var gx := (x0 + x1) / 2
	c.box(gx - 1, cab_top + 3, tz + 1, gx + 1, cab_top + 5, tz + 5, P.GUN)
	c.box(gx, cab_top + 4, tz - 9, gx + 1, cab_top + 5, tz + 1, P.GUN)
	# Wheels, mud flaps, mirrors and lights.
	var r := 6.0
	for wz: float in [hood - 2.0, length - 14.0]:
		c.wheel(0, 5, r, wz, r)
		c.wheel(width - 3, width + 2, r, wz, r)
		c.box(0, int(r) + 6, int(wz) - 7, 5, int(r) + 7, int(wz) + 7, P.PAINT_DARK)
		c.box(width - 3, int(r) + 6, int(wz) - 7, width + 2, int(r) + 7, int(wz) + 7, P.PAINT_DARK)
	c.box(0, floor_y + 12, hood + 1, 1, floor_y + 15, hood + 2, P.BLACK)
	c.box(x1, floor_y + 12, hood + 1, x1 + 1, floor_y + 15, hood + 2, P.BLACK)
	c.box(x0 + 2, floor_y + 6, 0, x0 + 4, floor_y + 8, 1, P.PAINT_LIGHT)
	c.box(x1 - 4, floor_y + 6, 0, x1 - 2, floor_y + 8, 1, P.PAINT_LIGHT)
	return c


## Tracks and road wheels down both sides of a tracked hull.
static func _tracks(c: Canvas, width: int, z0: int, z1: int, wheels: int, radius: float, track_w: int) -> void:
	for x0: int in [0, width - track_w]:
		c.box(x0, 0, z0 + 2, x0 + track_w, 2, z1 - 2, P.TRACK)
		c.box(x0, int(radius * 2.0), z0 + 4, x0 + track_w, int(radius * 2.0) + 2, z1 - 4, P.TRACK)
		var step := float(z1 - z0 - 12) / maxf(wheels - 1, 1)
		for i in wheels:
			c.wheel(x0, x0 + track_w, radius + 0.5, z0 + 6.0 + i * step, radius, P.TRACK, P.METAL)
		c.wheel(x0, x0 + track_w, radius + 2.0, z0 + 3.0, radius * 0.7, P.TRACK, P.METAL)  # drive sprocket
		c.wheel(x0, x0 + track_w, radius + 2.0, z1 - 3.0, radius * 0.7, P.TRACK, P.METAL)  # idler


## M2A3 Bradley: 6.5 m hull, 25 mm Bushmaster and a TOW launcher box on the turret's left.
static func _bradley() -> Canvas:
	var c := Canvas.new(Vector3i(36, 34, 78))
	_tracks(c, 36, 8, 74, 6, 4.0, 6)
	for z in range(8, 74):
		var top := 22
		if z < 22:
			top = 14 + int((z - 8) * 8.0 / 14.0)  # sloped glacis
		c.box(5, 5, z, 31, top, z + 1, P.PAINT)
	c.box(2, 10, 12, 34, 16, 72, P.PAINT_DARK)  # side armour skirts
	c.box(8, 5, 73, 28, 21, 74, P.PAINT_DARK)  # rear ramp
	c.box(7, 22, 14, 12, 24, 22, P.PAINT)  # driver's hatch
	# Turret, set right of centre, with the gun forward and the TOW box on its left.
	c.box(12, 22, 26, 30, 30, 46, P.PAINT)
	c.box(13, 30, 30, 29, 31, 44, P.PAINT_DARK)
	c.box(19, 25, 4, 21, 27, 26, P.GUN)  # 25 mm barrel
	c.box(18, 24, 22, 22, 28, 26, P.PAINT_DARK)  # mantlet
	c.box(8, 24, 28, 12, 30, 44, P.PAINT_LIGHT)  # TOW launcher
	c.box(8, 25, 28, 12, 29, 29, P.BLACK)
	c.paint_skin(24, 30, 32, 29, 32, 36, P.GLASS)  # commander's sight
	c.box(28, 30, 40, 30, 33, 42, P.METAL)  # antenna base
	return c


## M1A2 Abrams: 7.9 m hull, wide flat turret with the 120 mm gun reaching past the bow.
static func _abrams() -> Canvas:
	var c := Canvas.new(Vector3i(37, 30, 100))
	_tracks(c, 37, 18, 98, 7, 4.0, 7)
	for z in range(18, 98):
		var top := 20
		var bottom := 5
		if z < 26:
			top = 14 + int((z - 18) * 6.0 / 8.0)  # glacis
			bottom = 5 + int((26 - z) * 0.5)
		c.box(6, bottom, z, 31, top, z + 1, P.PAINT)
	c.box(2, 9, 20, 35, 15, 92, P.PAINT_DARK)  # side skirts
	c.box(8, 14, 96, 29, 19, 98, P.METAL)  # engine grille at the back
	# Turret: wedge front, bustle at the back, commander's weapon station.
	for z in range(36, 82):
		var half := 15
		if z < 46:
			half = 9 + int((z - 36) * 0.6)
		c.box(18 - half, 20, z, 19 + half, 27, z + 1, P.PAINT)
	c.box(5, 20, 76, 32, 26, 86, P.PAINT_DARK)  # bustle rack
	c.box(17, 22, 0, 20, 25, 38, P.PAINT)  # 120 mm gun tube
	c.box(16, 21, 14, 21, 26, 20, P.PAINT)  # bore evacuator
	c.box(16, 21, 34, 21, 26, 38, P.PAINT_DARK)  # mantlet
	c.box(24, 27, 58, 29, 30, 64, P.PAINT_DARK)  # CROWS
	c.box(26, 29, 50, 27, 30, 58, P.GUN)
	c.paint_skin(9, 26, 46, 14, 28, 52, P.GLASS)  # gunner's sight
	c.box(6, 27, 70, 7, 30, 71, P.METAL)  # antennas
	c.box(31, 27, 70, 32, 30, 71, P.METAL)
	return c


## Pickup technical: Hilux-sized truck with a DShK on a pintle in the bed.
static func _technical() -> Canvas:
	var c := Canvas.new(Vector3i(18, 22, 53))
	# Lower body, bonnet, cab and bed.
	c.box(0, 3, 1, 18, 8, 52, P.PAINT)
	c.box(1, 8, 1, 17, 10, 14, P.PAINT)
	c.box(1, 8, 14, 17, 16, 29, P.PAINT)
	c.box(2, 16, 16, 16, 17, 28, P.PAINT)
	c.paint_skin(1, 10, 14, 17, 15, 15, P.GLASS)
	c.paint_skin(0, 10, 16, 18, 15, 28, P.GLASS)
	c.box(0, 8, 30, 1, 11, 52, P.PAINT)  # bed walls
	c.box(17, 8, 30, 18, 11, 52, P.PAINT)
	c.box(0, 8, 51, 18, 11, 52, P.PAINT)
	c.box(1, 7, 30, 17, 8, 51, P.PAINT_DARK)  # bed floor
	c.box(1, 3, 0, 17, 5, 1, P.METAL)  # bumpers
	c.box(1, 3, 52, 17, 5, 53, P.METAL)
	c.box(3, 6, 0, 15, 8, 1, P.BLACK)  # grille
	c.box(1, 7, 0, 3, 8, 1, P.PAINT_LIGHT)
	c.box(15, 7, 0, 17, 8, 1, P.PAINT_LIGHT)
	c.paint_skin(0, 3, 20, 18, 5, 45, P.RUST, P.PAINT)
	# Wheels.
	for wz: float in [8.0, 42.0]:
		c.wheel(0, 3, 3.5, wz, 3.5)
		c.wheel(15, 18, 3.5, wz, 3.5)
	# DShK on a pintle: post, gun body, long barrel over the cab, small shield.
	c.box(8, 8, 37, 10, 15, 39, P.METAL)
	c.box(7, 15, 35, 11, 17, 42, P.GUN)
	c.box(8, 16, 15, 10, 17, 35, P.GUN)
	c.box(8, 15, 15, 10, 18, 16, P.GUN)  # muzzle brake
	c.box(5, 17, 34, 13, 21, 35, P.METAL)
	c.box(7, 11, 44, 11, 13, 47, P.SEAT)  # ammo box
	return c
