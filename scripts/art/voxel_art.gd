class_name VoxelArt
extends RefCounted
## Small voxel models built in code from box lists: the soldier's body parts and gear.
## Every model uses the same palette layout (enum C); a variant fills in the colours, so
## one soldier can be multicam, woodland, desert or urban. Meshes are cached per variant.
##
## Coordinates are voxels (VOXEL_SIZE metres). Front is -Z (voxel z = 0), up is +Y.
## A box is [from: Vector3i, to: Vector3i (exclusive), colour]; later boxes overwrite.

const VOXEL_SIZE := 0.02

enum C {
	EMPTY, CAMO, CAMO_A, CAMO_B, CAMO_C, CAMO_D, SKIN, SKIN_SHADE, HAIR, EYE, MOUTH,
	BOOT, SOLE, GLOVE, BELT, METAL, PAD, PATCH, GEAR, GEAR_DARK, PACK, PACK_DARK,
	GUN, GUN_LIGHT, LENS,
}

const VARIANTS := {
	"multicam": {
		"camo": ["a39a72", "6e7454", "7d6447", "4a4334"], "skin": "c8996f", "hair": "3b2a1d",
		"patch": "3b4a6b", "gear": "8a7a58", "pack": "7a6c4e",
	},
	"woodland": {
		"camo": ["5f6b42", "3f4a2e", "6b5236", "262420"], "skin": "8d5b3e", "hair": "1d1612",
		"patch": "2f3a24", "gear": "4f5a3a", "pack": "48523a",
	},
	"desert": {
		"camo": ["c2ab7f", "a68b5f", "d6c49b", "8a7353"], "skin": "e0b48f", "hair": "6b4a2b",
		"patch": "7a3b2e", "gear": "b29c74", "pack": "a38e68",
	},
	"urban": {
		"camo": ["5c6066", "3f4247", "7a7e84", "26282b"], "skin": "b07a52", "hair": "1f1a17",
		"patch": "1f2a44", "gear": "34373b", "pack": "3a3d42",
	},
	"dummy": {
		"camo": ["f2c230", "f2c230", "e3b022", "f2c230"], "skin": "f2c230", "hair": "f2c230",
		"patch": "222222", "gear": "8a7a58", "pack": "7a6c4e",
	},
}

static var _meshers: Dictionary = {}  # variant -> VoxelMesherCubes
static var _meshes: Dictionary = {}   # "model|variant" -> Mesh
static var _material: StandardMaterial3D
static var _noise_a: FastNoiseLite
static var _noise_b: FastNoiseLite


## A pivot node holding the model's mesh. The pivot is the model's centre unless the
## spec names one (body parts pivot at their joints).
static func instance(model: String, variant: String, layers := 1) -> Node3D:
	var spec := _spec(model)
	var pivot := Node3D.new()
	pivot.name = model.get_slice(":", 0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh(model, variant)
	mesh_instance.material_override = _get_material()
	mesh_instance.layers = layers
	mesh_instance.scale = Vector3.ONE * VOXEL_SIZE
	mesh_instance.position = -spec.get("pivot", Vector3(spec.size) * 0.5) * VOXEL_SIZE
	pivot.add_child(mesh_instance)
	return pivot


static func size_m(model: String) -> Vector3:
	return Vector3(_spec(model).size) * VOXEL_SIZE


## Model name for an item, or "" if it has no voxel model yet (it falls back to a box).
static func model_for(item: ItemData) -> String:
	match item.slot:
		&"primary":
			var length: float = item.stats.get("size_m", [0, 0, 0.84])[2]
			return "rifle:%d" % roundi(length / VOXEL_SIZE)
		&"sidearm":
			return "pistol"
		&"vest":
			return "vest:%d" % ["light", "medium", "heavy"].find(item.stats.get("tier", "medium"))
		&"backpack":
			return "backpack:%d" % (6 + roundi(item.capacity_l * 0.2))
	return ""


## Where the hands go on a weapon, in metres relative to the instance pivot (its centre):
## "grip" for the right hand, "support" for the left. Empty for non-weapons.
static func hand_points(model: String) -> Dictionary:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	var n := float(spec.size.z)
	var grip: Vector3
	var support: Vector3
	match model.get_slice(":", 0):
		"rifle":
			grip = Vector3(1.5, 4, n * 0.68)     # pistol grip
			support = Vector3(1.5, 6, n * 0.38)  # under the handguard
		"pistol":
			grip = Vector3(1, 2.5, 7.5)
			support = Vector3(-0.5, 2, 7.5)      # cupping the grip from the left
		_:
			return {}
	return {"grip": (grip - centre) * VOXEL_SIZE, "support": (support - centre) * VOXEL_SIZE}


## Top of the rear sight, in metres relative to the instance pivot (its centre). Aiming
## puts this point just under the eye. Zero for non-weapons.
static func sight_point(model: String) -> Vector3:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	match model.get_slice(":", 0):
		"rifle":
			return (Vector3(1.5, 13, spec.size.z * 0.62) - centre) * VOXEL_SIZE  # back of the optic
		"pistol":
			return (Vector3(1, 7, 9) - centre) * VOXEL_SIZE  # rear sight
	return Vector3.ZERO


static func mesh(model: String, variant: String) -> Mesh:
	var key := "%s|%s" % [model, variant]
	if not _meshes.has(key):
		_meshes[key] = _build(_spec(model), variant, model.hash())
	return _meshes[key]


static func _build(spec: Dictionary, variant: String, salt: int) -> Mesh:
	var size: Vector3i = spec.size
	var buffer := VoxelBuffer.new()
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	buffer.create(size.x + 2, size.y + 2, size.z + 2)  # 1 voxel of mesher padding per side
	buffer.fill(C.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	for box: Array in spec.boxes:
		var from: Vector3i = box[0]
		var to: Vector3i = box[1]
		for x in range(from.x, to.x):
			for y in range(from.y, to.y):
				for z in range(from.z, to.z):
					var colour: int = box[2]
					if colour == C.CAMO:
						colour = _camo(Vector3i(x, y, z), salt)
					buffer.set_voxel(colour, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
	return _get_mesher(variant).build_mesh(buffer, [])


static func _camo(p: Vector3i, salt: int) -> int:
	if _noise_a == null:
		_noise_a = FastNoiseLite.new()
		_noise_a.frequency = 0.11
		_noise_b = FastNoiseLite.new()
		_noise_b.seed = 7
		_noise_b.frequency = 0.17
	var offset := float(salt % 1000)
	var a := _noise_a.get_noise_3d(p.x + offset, p.y, p.z)
	var b := _noise_b.get_noise_3d(p.x, p.y + offset, p.z)
	if b > 0.38:
		return C.CAMO_D
	if a > 0.22:
		return C.CAMO_B
	if a < -0.28:
		return C.CAMO_C
	return C.CAMO_A


static func _get_mesher(variant: String) -> VoxelMesherCubes:
	if not _meshers.has(variant):
		var v: Dictionary = VARIANTS.get(variant, VARIANTS["multicam"])
		var skin := Color(v.skin)
		var colours := {
			C.EMPTY: Color(0, 0, 0, 0),
			C.CAMO_A: Color(v.camo[0]), C.CAMO_B: Color(v.camo[1]), C.CAMO_C: Color(v.camo[2]), C.CAMO_D: Color(v.camo[3]),
			C.SKIN: skin, C.SKIN_SHADE: skin.darkened(0.15), C.HAIR: Color(v.hair),
			C.EYE: Color("1c1c1c"), C.MOUTH: skin.darkened(0.35),
			C.BOOT: Color("3a3027"), C.SOLE: Color("1e1a17"), C.GLOVE: Color("2f2f2a"),
			C.BELT: Color("3d3a2e"), C.METAL: Color("8c8c84"), C.PAD: Color("2b2b27"),
			C.PATCH: Color(v.patch),
			C.GEAR: Color(v.gear), C.GEAR_DARK: Color(v.gear).darkened(0.25),
			C.PACK: Color(v.pack), C.PACK_DARK: Color(v.pack).darkened(0.25),
			C.GUN: Color("262626"), C.GUN_LIGHT: Color("3b3b37"), C.LENS: Color("3a6f8f"),
		}
		var palette := VoxelColorPalette.new()
		for index: int in colours:
			palette.set_color(index, colours[index])
		var mesher := VoxelMesherCubes.new()
		mesher.palette = palette
		mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
		_meshers[variant] = mesher
	return _meshers[variant]


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.85
	return _material


# --- Model specs ------------------------------------------------------------------------

static func _spec(model: String) -> Dictionary:
	var arg := model.get_slice(":", 1).to_int() if model.contains(":") else 0
	match model.get_slice(":", 0):
		"head": return _head()
		"torso": return _torso()
		"upper_arm": return _upper_arm()
		"forearm": return _forearm()
		"leg": return _leg()
		"thigh": return _thigh()
		"shin": return _shin()
		"vest": return _vest(arg)
		"backpack": return _backpack(arg)
		"rifle": return _rifle(arg)
		"pistol": return _pistol()
	push_error("VoxelArt: unknown model '%s'" % model)
	return {"size": Vector3i.ONE, "boxes": []}


static func _b(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int) -> Array:
	return [Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), colour]


## 0.22 x 0.30 x 0.24 m including the neck. Pivot at the base of the neck.
static func _head() -> Dictionary:
	return {"size": Vector3i(11, 15, 12), "pivot": Vector3(5.5, 0, 6), "boxes": [
		_b(3, 0, 3, 8, 2, 9, C.SKIN_SHADE),
		_b(0, 2, 0, 11, 15, 12, C.SKIN),
		_b(0, 13, 0, 11, 15, 12, C.HAIR),
		_b(0, 6, 9, 11, 15, 12, C.HAIR),
		_b(0, 9, 4, 1, 15, 12, C.HAIR), _b(10, 9, 4, 11, 15, 12, C.HAIR),
		_b(0, 12, 0, 11, 13, 2, C.HAIR),
		_b(0, 7, 5, 1, 10, 7, C.SKIN_SHADE), _b(10, 7, 5, 11, 10, 7, C.SKIN_SHADE),
		_b(2, 9, 0, 4, 10, 1, C.EYE), _b(7, 9, 0, 9, 10, 1, C.EYE),
		_b(2, 11, 0, 4, 12, 1, C.HAIR), _b(7, 11, 0, 9, 12, 1, C.HAIR),
		_b(5, 6, 0, 6, 9, 1, C.SKIN_SHADE),
		_b(4, 4, 0, 7, 5, 1, C.MOUTH),
	]}


## 0.38 x 0.56 x 0.22 m. Pivot at the hips.
static func _torso() -> Dictionary:
	return {"size": Vector3i(19, 28, 11), "pivot": Vector3(9.5, 0, 5.5), "boxes": [
		_b(0, 0, 0, 19, 28, 11, C.CAMO),
		_b(0, 0, 0, 19, 3, 11, C.BELT),
		_b(8, 0, 0, 11, 3, 1, C.METAL),
		_b(6, 26, 0, 13, 28, 2, C.CAMO_C),
	]}


## 0.12 x 0.32 x 0.12 m. Pivot at the shoulder; the elbow is at the bottom.
static func _upper_arm() -> Dictionary:
	return {"size": Vector3i(6, 16, 6), "pivot": Vector3(3, 16, 3), "boxes": [
		_b(0, 0, 0, 6, 16, 6, C.CAMO),
		_b(0, 7, 1, 1, 13, 5, C.PATCH), _b(5, 7, 1, 6, 13, 5, C.PATCH),
	]}


## 0.11 x 0.32 x 0.11 m including the gloved hand. Pivot at the elbow; the palm centre
## is 0.25 m below it (CharacterModel.FOREARM).
static func _forearm() -> Dictionary:
	return {"size": Vector3i(5, 16, 5), "pivot": Vector3(2.5, 16, 2.5), "boxes": [
		_b(0, 0, 0, 5, 16, 5, C.CAMO),
		_b(0, 0, 0, 5, 7, 5, C.GLOVE),
		_b(0, 7, 0, 5, 9, 5, C.CAMO_A),
	]}


## 0.14 x 0.90 x 0.18 m with the boot toe. Pivot at the hip joint.
static func _leg() -> Dictionary:
	return {"size": Vector3i(7, 45, 9), "pivot": Vector3(3.5, 45, 5), "boxes": [
		_b(0, 6, 1, 7, 45, 9, C.CAMO),
		_b(0, 0, 0, 7, 7, 9, C.BOOT),
		_b(0, 0, 0, 7, 1, 9, C.SOLE),
		_b(1, 19, 0, 6, 25, 1, C.PAD),
		_b(0, 27, 3, 1, 34, 7, C.CAMO_C), _b(6, 27, 3, 7, 34, 7, C.CAMO_C),
	]}


## The leg above the knee: 0.14 x 0.46 x 0.16 m, overlapping the knee by a voxel. Pivot at
## the hip joint; the knee (CharacterModel.THIGH) is at the bottom, with the top of the knee pad.
static func _thigh() -> Dictionary:
	return {"size": Vector3i(7, 23, 9), "pivot": Vector3(3.5, 23, 5), "boxes": [
		_b(0, 0, 1, 7, 23, 9, C.CAMO),
		_b(1, 0, 0, 6, 2, 1, C.PAD),
		_b(0, 5, 3, 1, 12, 7, C.CAMO_C), _b(6, 5, 3, 7, 12, 7, C.CAMO_C),
	]}


## The leg below the knee with the boot: 0.14 x 0.46 x 0.18 m, the bottom half of _leg.
## Pivot at the knee.
static func _shin() -> Dictionary:
	return {"size": Vector3i(7, 23, 9), "pivot": Vector3(3.5, 23, 5), "boxes": [
		_b(0, 6, 1, 7, 23, 9, C.CAMO),
		_b(0, 0, 0, 7, 7, 9, C.BOOT),
		_b(0, 0, 0, 7, 1, 9, C.SOLE),
		_b(1, 19, 0, 6, 23, 1, C.PAD),
	]}


## Plate carriers by tier (0 light, 1 medium, 2 heavy). The pivot is the bottom centre of
## the main body, mounted at torso height 0.17 m. Plates mount on the faces (GearRig).
static func _vest(tier: int) -> Dictionary:
	var boxes := []
	match tier:
		0:  # low-profile chest rig: front panel and straps, torso shows through
			boxes = [
				_b(0, 0, 0, 21, 14, 2, C.GEAR),
				_b(0, 4, 0, 21, 5, 2, C.GEAR_DARK), _b(0, 8, 0, 21, 9, 2, C.GEAR_DARK),
				_b(0, 4, 2, 1, 7, 11, C.GEAR_DARK), _b(20, 4, 2, 21, 7, 11, C.GEAR_DARK),
				_b(2, 2, 11, 19, 4, 12, C.GEAR_DARK),
				_b(4, 4, 11, 6, 14, 12, C.GEAR_DARK), _b(15, 4, 11, 17, 14, 12, C.GEAR_DARK),
				_b(3, 14, 1, 7, 16, 11, C.GEAR), _b(14, 14, 1, 18, 16, 11, C.GEAR),
			]
			return {"size": Vector3i(21, 16, 12), "pivot": Vector3(10.5, -2.5, 6), "boxes": boxes}
		2:  # assault carrier: thicker, side plate pockets, collar and groin protection
			boxes = [
				_b(0, 4, 0, 23, 22, 15, C.GEAR),
				_b(0, 4, 0, 23, 8, 15, C.GEAR_DARK),
				_b(0, 9, 3, 1, 19, 12, C.GEAR_DARK), _b(22, 9, 3, 23, 19, 12, C.GEAR_DARK),
				_b(4, 22, 1, 19, 25, 14, C.GEAR_DARK),
				_b(8, 22, 4, 15, 25, 11, C.EMPTY),
				_b(7, 0, 0, 16, 4, 2, C.GEAR), _b(7, 0, 0, 16, 1, 2, C.GEAR_DARK),
			]
			for y in [11, 14, 17, 20]:  # MOLLE rows
				boxes.append(_b(0, y, 0, 23, y + 1, 15, C.GEAR_DARK))
			return {"size": Vector3i(23, 25, 15), "pivot": Vector3(11.5, 4, 7.5), "boxes": boxes}
	boxes = [
		_b(0, 0, 0, 21, 17, 13, C.GEAR),
		_b(0, 0, 0, 21, 4, 13, C.GEAR_DARK),
		_b(6, 1, 0, 15, 5, 1, C.GEAR_DARK),
		_b(3, 17, 1, 7, 19, 12, C.GEAR), _b(14, 17, 1, 18, 19, 12, C.GEAR),
	]
	for y in [6, 9, 12]:  # MOLLE rows
		boxes.append(_b(0, y, 0, 21, y + 1, 13, C.GEAR_DARK))
	return {"size": Vector3i(21, 19, 13), "pivot": Vector3(10.5, 0, 6.5), "boxes": boxes}

## 0.34 x 0.44 m; depth in voxels grows with capacity. Outer face is +Z.
static func _backpack(depth: int) -> Dictionary:
	var d := maxi(depth, 6)
	return {"size": Vector3i(17, 22, d), "boxes": [
		_b(0, 0, 0, 17, 20, d, C.PACK),
		_b(0, 18, 0, 17, 22, d, C.PACK_DARK),
		_b(2, 3, d - 1, 15, 10, d, C.PACK_DARK),
		_b(4, 0, d - 1, 5, 18, d, C.PACK_DARK), _b(12, 0, d - 1, 13, 18, d, C.PACK_DARK),
		_b(0, 2, 2, 1, 9, d - 2, C.PACK_DARK), _b(16, 2, 2, 17, 9, d - 2, C.PACK_DARK),
	]}


## Rifle of `length` voxels, muzzle at z = 0.
static func _rifle(length: int) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> int: return int(n * t)
	return {"size": Vector3i(3, 13, n), "boxes": [
		_b(1, 8, 0, 2, 9, f.call(0.3), C.GUN),
		_b(0, 7, f.call(0.15), 3, 10, f.call(0.45), C.GUN_LIGHT),
		_b(0, 6, f.call(0.45), 3, 11, f.call(0.72), C.GUN),
		_b(1, 11, f.call(0.5), 2, 13, f.call(0.64), C.GUN),
		_b(1, 11, f.call(0.5), 2, 13, f.call(0.5) + 1, C.LENS),
		_b(1, 2, f.call(0.5), 2, 6, f.call(0.57), C.GUN_LIGHT),
		_b(1, 0, f.call(0.53), 2, 2, f.call(0.6), C.GUN_LIGHT),
		_b(1, 2, f.call(0.66), 2, 6, f.call(0.7), C.GUN),
		_b(1, 8, f.call(0.72), 2, 9, f.call(0.76), C.GUN),
		_b(0, 6, f.call(0.76), 3, 10, n, C.GUN_LIGHT),
		_b(1, 5, f.call(0.85), 2, 6, n, C.GUN_LIGHT),
	]}


## 0.04 x 0.14 x 0.20 m, muzzle at z = 0.
static func _pistol() -> Dictionary:
	return {"size": Vector3i(2, 7, 10), "boxes": [
		_b(0, 4, 0, 2, 7, 10, C.GUN),
		_b(0, 3, 1, 2, 4, 9, C.GUN_LIGHT),
		_b(0, 0, 6, 2, 4, 9, C.GUN_LIGHT),
		_b(0, 2, 4, 2, 3, 6, C.GUN),
	]}
