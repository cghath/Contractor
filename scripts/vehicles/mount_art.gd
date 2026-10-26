class_name MountArt
extends RefCounted
## The mounts' voxel models (Contractor: Fallen, docs/survival_mounts.md): a horse about 1.6 m at
## the withers, a bicycle and a two-wheeled horse cart, drawn on VehicleArt's canvas at 5 cm voxels
## (metres: x centred, y up from the ground, z back from the nose) so VehicleHull, rounds and the
## seats treat them like any vehicle. VehicleArt._shape_for asks here first (canvas). The coat or
## paint is the scheme's (VehicleArt.SCHEMES: bay, chestnut, grey, black_horse; the bikes' colours;
## wood for the cart). A far LOD (far_lod) stands in past LOD_M.

const MODELS: Array[String] = ["horse", "bicycle", "cart"]
## Past this (m) the voxel model gives way to a few boxes (Proposed).
const LOD_M := 70.0


static func has(model: String) -> bool:
	return model in MODELS


static func canvas(model: String) -> VehicleArt.Canvas:
	match model:
		"horse":
			return _horse()
		"bicycle":
			return _bicycle()
		"cart":
			return _cart()
	return VehicleArt.Canvas.new(Vector3i.ONE, 0.05)


## A horse standing square: legs, the barrel, withers at ~1.6 m, the neck and head forward, mane
## and tail, a saddle with stirrups and saddlebags (the packs). 0.9 x 2.1 x 2.5 m.
static func _horse() -> VehicleArt.Canvas:
	var c := VehicleArt.Canvas.new(Vector3i(18, 42, 50), 0.05)
	var coat := VehicleArt.P.PAINT
	var dark := VehicleArt.P.PAINT_DARK
	for z0: float in [0.72, 1.88]:  # front and hind legs
		for x: float in [-0.16, 0.16]:
			c.mbox(x - 0.06, 0.08, z0, x + 0.06, 0.95, z0 + 0.13, coat)
			c.mbox(x - 0.07, 0.0, z0 - 0.01, x + 0.07, 0.09, z0 + 0.14, VehicleArt.P.BLACK)  # hooves
	c.mloft(0.6, 2.15, func(z: float) -> Vector4:
		var t := clampf((z - 0.6) / 1.55, 0.0, 1.0)
		return Vector4(0.0, 1.2 + 0.04 * sin(t * PI), 0.25 + 0.04 * sin(t * PI), 0.31 + 0.03 * sin(t * PI)), coat)
	c.mbox(-0.12, 1.4, 0.62, 0.12, 1.6, 0.92, coat)  # withers
	c.mbox(-0.14, 1.38, 1.85, 0.14, 1.52, 2.12, coat)  # croup
	c.mbar(Vector3(0, 1.45, 0.78), Vector3(0, 1.82, 0.36), 0.22, coat)  # neck
	c.mbar(Vector3(0, 1.62, 0.86), Vector3(0, 1.96, 0.42), 0.07, dark)  # mane
	c.mbar(Vector3(0, 1.88, 0.38), Vector3(0, 1.56, 0.04), 0.19, coat)  # head
	c.mbox(-0.08, 1.5, 0.0, 0.08, 1.62, 0.1, dark)  # muzzle
	c.mbox(-0.1, 1.8, 0.26, -0.08, 1.84, 0.3, VehicleArt.P.BLACK)  # eyes
	c.mbox(0.08, 1.8, 0.26, 0.1, 1.84, 0.3, VehicleArt.P.BLACK)
	c.mbox(-0.08, 1.94, 0.36, -0.04, 2.04, 0.4, dark)  # ears
	c.mbox(0.04, 1.94, 0.36, 0.08, 2.04, 0.4, dark)
	c.mbar(Vector3(0, 1.45, 2.14), Vector3(0, 0.78, 2.42), 0.1, dark)  # tail
	c.mbox(-0.29, 1.48, 1.05, 0.29, 1.6, 1.52, VehicleArt.P.SEAT)  # saddle
	c.mbox(-0.08, 1.6, 1.05, 0.08, 1.66, 1.14, VehicleArt.P.SEAT)  # pommel
	c.mbar(Vector3(-0.3, 1.5, 1.28), Vector3(-0.32, 1.02, 1.28), 0.03, VehicleArt.P.BLACK)  # stirrup leathers
	c.mbar(Vector3(0.3, 1.5, 1.28), Vector3(0.32, 1.02, 1.28), 0.03, VehicleArt.P.BLACK)
	c.mbox(-0.36, 0.98, 1.24, -0.28, 1.02, 1.34, VehicleArt.P.METAL)  # stirrups
	c.mbox(0.28, 0.98, 1.24, 0.36, 1.02, 1.34, VehicleArt.P.METAL)
	c.mbox(-0.38, 1.12, 1.55, -0.28, 1.44, 1.85, VehicleArt.P.RUST)  # saddlebags (the packs)
	c.mbox(0.28, 1.12, 1.55, 0.38, 1.44, 1.85, VehicleArt.P.RUST)
	c.mbar(Vector3(0, 1.62, 0.12), Vector3(0, 1.6, 0.95), 0.02, VehicleArt.P.BLACK)  # reins
	return c


## A plain town bicycle: two wheels, the diamond frame, bars, saddle and a rear basket. 0.6 x 1.15 x 1.8 m.
static func _bicycle() -> VehicleArt.Canvas:
	var c := VehicleArt.Canvas.new(Vector3i(12, 23, 36), 0.05)
	for cz: float in [0.36, 1.42]:
		c.mwheel(-0.03, 0.03, 0.34, cz, 0.34, VehicleArt.P.TIRE, VehicleArt.P.METAL)
	var paint := VehicleArt.P.PAINT
	var rear := Vector3(0, 0.34, 1.42)
	var front := Vector3(0, 0.34, 0.36)
	var bracket := Vector3(0, 0.32, 0.95)
	var seat := Vector3(0, 0.95, 1.15)
	var head := Vector3(0, 0.98, 0.5)
	c.mbar(rear, bracket, 0.04, paint)
	c.mbar(bracket, seat, 0.045, paint)
	c.mbar(seat, rear, 0.04, paint)
	c.mbar(seat, head, 0.045, paint)
	c.mbar(head, bracket, 0.05, paint)
	c.mbar(head, front, 0.04, paint)  # fork
	c.mbar(head, Vector3(0, 1.1, 0.48), 0.04, VehicleArt.P.METAL)  # stem
	c.mbox(-0.27, 1.08, 0.44, 0.27, 1.12, 0.5, VehicleArt.P.BLACK)  # bars
	c.mbox(-0.07, 0.98, 1.08, 0.07, 1.04, 1.28, VehicleArt.P.BLACK)  # saddle
	c.mbox(-0.12, 0.3, 0.92, 0.12, 0.34, 0.98, VehicleArt.P.BLACK)  # pedals
	c.mbox(-0.16, 0.78, 1.36, 0.16, 0.98, 1.72, VehicleArt.P.METAL)  # basket
	c.mbox(-0.14, 0.8, 1.38, 0.14, 0.98, 1.7, VehicleArt.P.EMPTY)
	return c


## A farm cart: a plank bed on two big wheels, a bench at the front, shafts reaching forward for
## the horse (hitched, the horse stands between them). 1.7 x 1.5 x 4.6 m.
static func _cart() -> VehicleArt.Canvas:
	var c := VehicleArt.Canvas.new(Vector3i(34, 30, 92), 0.05)
	var wood := VehicleArt.P.PAINT
	var dark := VehicleArt.P.PAINT_DARK
	c.mbox(-0.75, 0.6, 1.5, 0.75, 0.7, 4.0, wood)  # bed
	c.mbox(-0.75, 0.7, 1.5, -0.69, 1.05, 4.0, dark)  # sides
	c.mbox(0.69, 0.7, 1.5, 0.75, 1.05, 4.0, dark)
	c.mbox(-0.75, 0.7, 3.94, 0.75, 1.0, 4.0, dark)  # tailboard
	c.mbox(-0.75, 0.7, 1.5, 0.75, 1.15, 1.56, dark)  # front board
	c.mbox(-0.68, 1.0, 1.6, 0.68, 1.1, 1.98, VehicleArt.P.PAINT_LIGHT)  # bench
	c.mbox(-0.68, 0.7, 1.9, -0.6, 1.0, 1.98, dark)  # bench legs
	c.mbox(0.6, 0.7, 1.9, 0.68, 1.0, 1.98, dark)
	c.mwheel(-0.85, -0.76, 0.6, 2.9, 0.6, dark, VehicleArt.P.METAL)
	c.mwheel(0.76, 0.85, 0.6, 2.9, 0.6, dark, VehicleArt.P.METAL)
	c.mbar(Vector3(-0.8, 0.6, 2.9), Vector3(0.8, 0.6, 2.9), 0.06, VehicleArt.P.METAL)  # axle
	for x: float in [-0.45, 0.45]:
		c.mbar(Vector3(x, 0.65, 1.6), Vector3(x, 1.05, 0.05), 0.06, dark)  # shafts
	return c


## The far stand-in for `model` (every peer): a few untextured boxes in the scheme's colour,
## shown past LOD_M while the voxel mesh hides (VisibilityRange on both).
static func far_lod(model: String, scheme: String) -> MeshInstance3D:
	var s: Dictionary = VehicleArt.SCHEMES.get(scheme, VehicleArt.SCHEMES["od"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(s.paint))
	mat.roughness = 0.9
	var mesh := BoxMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "FarLod"
	match model:
		"horse":
			mesh.size = Vector3(0.55, 1.1, 2.0)
			mi.position = Vector3(0, 1.05, 0)
		"bicycle":
			mesh.size = Vector3(0.1, 0.9, 1.7)
			mi.position = Vector3(0, 0.55, 0)
		_:
			mesh.size = Vector3(1.6, 0.9, 2.6)
			mi.position = Vector3(0, 0.75, 0.4)
	mesh.material = mat
	mi.mesh = mesh
	mi.visibility_range_begin = LOD_M
	return mi
