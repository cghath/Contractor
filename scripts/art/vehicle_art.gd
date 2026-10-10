class_name VehicleArt
extends RefCounted
## Voxel vehicle models built in code, at the same 10 cm voxel size as the world's walls:
## UH-60 Black Hawk, AH-1Z Viper, AAV-7, MRAPs (MaxxPro, M-ATV) and a pickup technical.
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
}

static var _meshes := {}  # "model|scheme" -> Mesh
static var _sizes := {}   # model -> Vector3i canvas size
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
	hull.scale = Vector3.ONE * VOXEL_SIZE
	var size: Vector3i = _sizes[model]
	hull.position = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5) * VOXEL_SIZE
	root.add_child(hull)
	match model:
		"uh60":
			_add_rotor(root, "MainRotor", _vx(size, 23, 44, 58), 8.2, 0.53, 4, Vector3.UP)
			_add_rotor(root, "TailRotor", _vx(size, 26, 41, 151), 1.7, 0.25, 4, Vector3.RIGHT)
		"ah1z":
			_add_rotor(root, "MainRotor", _vx(size, 30, 39, 58), 7.3, 0.58, 4, Vector3.UP)
			_add_rotor(root, "TailRotor", _vx(size, 26, 35, 134), 1.4, 0.25, 4, Vector3.LEFT)
	return root


## Footprint and height in metres.
static func size_m(model: String) -> Vector3:
	if not _sizes.has(model):
		mesh(model, MODELS[model][0])
	return Vector3(_sizes[model]) * VOXEL_SIZE


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
	var basis := Basis.IDENTITY if axis == Vector3.UP else Basis(Vector3.FORWARD, PI * 0.5)
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

	func _init(p_size: Vector3i) -> void:
		size = p_size
		buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
		buffer.create(size.x + 2, size.y + 2, size.z + 2)
		buffer.fill(VehicleArt.P.EMPTY, VoxelBuffer.CHANNEL_COLOR)

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

## UH-60 Black Hawk: 15.3 m fuselage, 2.4 m wide, 4.4 m horizontal stabilator.
static func _uh60() -> Canvas:
	var c := Canvas.new(Vector3i(46, 50, 158))
	var cx := 23.0
	# Fuselage: rounded nose, cockpit, cabin, then taper into the tail boom.
	var fuselage := func(t: float) -> Vector4:
		var z := t * 111.0
		var hw := 11.5
		var hh := 12.0
		var cy := 18.0
		if z < 24.0:
			var k := sqrt(z / 24.0)
			hw = lerpf(4.0, 11.5, k)
			hh = lerpf(6.0, 12.0, k)
			cy = lerpf(14.0, 18.0, k)
		elif z > 82.0:
			var k := (z - 82.0) / 30.0
			hw = lerpf(11.5, 4.5, k)
			hh = lerpf(12.0, 5.5, k)
			cy = lerpf(18.0, 26.0, k)
		return Vector4(cx, cy, hw, hh)
	c.loft(0, 112, fuselage, P.PAINT)
	c.loft(108, 150, func(t: float) -> Vector4: return Vector4(cx, lerpf(26.0, 28.0, t), lerpf(4.5, 2.2, t), lerpf(5.5, 3.0, t)), P.PAINT)
	# Engine and transmission fairing on the roof, and the rotor mast.
	c.loft(34, 96, func(t: float) -> Vector4: return Vector4(cx, 30.0, lerpf(8.0, 5.0, absf(t - 0.4)), lerpf(5.5, 3.5, absf(t - 0.4))), P.PAINT)
	c.box(21, 34, 56, 25, 44, 60, P.METAL)
	c.box(19, 30, 40, 27, 33, 44, P.BLACK)  # engine intakes
	# Tail fin, swept back, with the tail rotor on its right.
	for y in range(26, 46):
		var back := int((y - 26) * 0.45)
		c.box(22, y, 140 + back, 24, y + 1, 152 + back / 2, P.PAINT)
	c.box(4, 27, 146, 42, 29, 156, P.PAINT)  # horizontal stabilator
	# Cockpit glass, cabin windows and the sliding door outline.
	c.paint_skin(0, 18, 3, 46, 30, 26, P.GLASS)
	c.paint_skin(0, 16, 26, 46, 26, 34, P.GLASS)
	c.paint_skin(0, 20, 42, 46, 26, 52, P.GLASS)
	c.paint_skin(0, 20, 62, 46, 26, 74, P.GLASS)
	c.paint_skin(0, 8, 40, 46, 9, 76, P.PAINT_DARK)
	c.paint_skin(0, 8, 40, 46, 28, 41, P.PAINT_DARK)
	c.paint_skin(0, 8, 75, 46, 28, 76, P.PAINT_DARK)
	# Door guns (M240 on the window mounts), landing gear, lights and markings.
	c.box(9, 20, 44, 11, 22, 52, P.GUN)
	c.box(35, 20, 44, 37, 22, 52, P.GUN)
	for side: int in [8, 34]:
		c.box(side, 4, 32, side + 4, 8, 36, P.METAL)
		c.wheel(side, side + 4, 3.0, 34.0, 3.0)
	c.box(22, 20, 132, 24, 24, 134, P.METAL)
	c.wheel(22, 24, 18.0, 133.0, 2.0)
	c.box(10, 18, 30, 11, 20, 32, P.LIGHT_RED)
	c.box(35, 18, 30, 36, 20, 32, P.LIGHT_GREEN)
	c.paint_skin(0, 22, 90, 46, 28, 100, P.MARKING, P.PAINT)
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
