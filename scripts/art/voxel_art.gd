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
	var voxel: float = spec.get("voxel", VOXEL_SIZE)
	mesh_instance.scale = Vector3.ONE * voxel / int(spec.get("sub", 1))  # built in sub-voxels
	mesh_instance.position = -spec.get("pivot", Vector3(spec.size) * 0.5) * voxel
	pivot.add_child(mesh_instance)
	return pivot


static func size_m(model: String) -> Vector3:
	var spec := _spec(model)
	return Vector3(spec.size) * float(spec.get("voxel", VOXEL_SIZE))


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
	## "sub": each voxel the spec is written in is built as sub x sub x sub smaller ones (the
	## body: shapes written in 1 cm, built in 0.5 cm), so curves step finer.
	var s: int = spec.get("sub", 1)
	var size: Vector3i = spec.size * s
	var cm := float(spec.get("voxel", VOXEL_SIZE)) * 100.0 / s  # centimetres per built voxel, for the camo
	var buffer := VoxelBuffer.new()
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	buffer.create(size.x + 2, size.y + 2, size.z + 2)  # 1 voxel of mesher padding per side
	buffer.fill(C.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	var put := func(x: int, y: int, z: int, colour: int, paint_only: bool) -> void:
		if x < 0 or y < 0 or z < 0 or x >= size.x or y >= size.y or z >= size.z:
			return
		if paint_only and buffer.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) == C.EMPTY:
			return
		if colour == C.CAMO:
			colour = _camo(Vector3(x, y, z) * cm, salt, variant)
		buffer.set_voxel(colour, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
	for box: Variant in spec.boxes:
		if box is Dictionary:
			_fill_loft(box, put, s)
			continue
		var from: Vector3i = box[0] * s
		var to: Vector3i = box[1] * s
		var paint_only: bool = box.size() > 3 and box[3]  # _p: recolours, never adds
		for x in range(from.x, to.x):
			for y in range(from.y, to.y):
				for z in range(from.z, to.z):
					put.call(x, y, z, box[2], paint_only)
	return _get_mesher(variant).build_mesh(buffer, [])


## Fills a loft (_loft): at each voxel layer, a low-poly cross-section (a rectangle with its
## four corners cut at 45 degrees by "bevel", 0 square to 1 a diamond) whose half-width and
## half-depth are interpolated between the keys, so the sides read as flat facets.
static func _fill_loft(loft: Dictionary, put: Callable, s := 1) -> void:
	var keys: Array = loft.keys
	var centre: Vector2 = loft.centre * s
	var bevel: float = loft.bevel
	for y in range(int(keys[0][0]) * s, int(keys[keys.size() - 1][0]) * s):
		var yc := (y + 0.5) / s
		var i := 0
		while i < keys.size() - 2 and yc > float(keys[i + 1][0]):
			i += 1
		var t := clampf(inverse_lerp(float(keys[i][0]), float(keys[i + 1][0]), yc), 0.0, 1.0)
		var hw := lerpf(keys[i][1], keys[i + 1][1], t) * s
		var hd := lerpf(keys[i][2], keys[i + 1][2], t) * s
		if hw <= 0.0 or hd <= 0.0:
			continue
		for x in range(int(floor(centre.x - hw)), int(ceil(centre.x + hw))):
			for z in range(int(floor(centre.y - hd)), int(ceil(centre.y + hd))):
				var dx := absf(x + 0.5 - centre.x) / hw
				var dz := absf(z + 0.5 - centre.y) / hd
				if dx <= 1.0 and dz <= 1.0 and dx + dz <= 2.0 - bevel:
					put.call(x, y, z, loft.colour, loft.paint)


## Camouflage by variant, from a point in centimetres: woodland's organic blotches with
## black branches, MultiCam's soft brushed blotches with small dark flecks, the desert
## pattern's broad drifts, urban as a grey woodland. Domain-warped so the shapes flow rather
## than repeat. CAMO_A is the base colour, then B, C and D in the order the variant lists them.
static func _camo(p: Vector3, salt: int, variant: String) -> int:
	if _noise_a == null:
		_noise_a = FastNoiseLite.new()
		_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_a.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise_a.frequency = 1.0
		_noise_b = FastNoiseLite.new()
		_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_b.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise_b.seed = 7
		_noise_b.frequency = 1.0
	p += Vector3(float(salt % 997), float(salt % 389), 0.0)
	var warp := Vector3(_noise_b.get_noise_3dv(p * 0.05), _noise_b.get_noise_3dv(p * 0.05 + Vector3(31, 0, 0)), 0.0) * 6.0
	var q := p + warp
	match variant:
		"multicam":
			var brush := Vector3(q.x, q.y * 0.6, q.z)  # MultiCam's shapes run up and down
			if _noise_b.get_noise_3dv(q * 0.2) > 0.78:
				return C.CAMO_D  # small dark flecks
			var a := _noise_a.get_noise_3dv(brush * 0.08)
			if a > 0.3:
				return C.CAMO_B
			if a < -0.32:
				return C.CAMO_C
			return C.CAMO_A
		"desert":
			var a := _noise_a.get_noise_3dv(q * 0.06)
			if a > 0.25:
				return C.CAMO_B
			if _noise_a.get_noise_3dv(q * 0.1 + Vector3(50, 0, 0)) > 0.45:
				return C.CAMO_C
			if _noise_b.get_noise_3dv(q * 0.2) > 0.68:
				return C.CAMO_D
			return C.CAMO_A
		"dummy":
			return C.CAMO_A
	# Woodland, and urban in greys: big blotches, then black branches across them.
	if absf(_noise_b.get_noise_3dv(q * 0.09 + Vector3(0, 70, 0))) < 0.07:
		return C.CAMO_D
	var b := _noise_a.get_noise_3dv(q * 0.07)
	if b > 0.22:
		return C.CAMO_C
	if b < -0.22:
		return C.CAMO_B
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


## A box that only recolours voxels already there (a face, a patch, a belt on a rounded
## part), so it never pokes out of the shape.
static func _p(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int) -> Array:
	return [Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), colour, true]


## Body parts are low-poly lofts (Stormworks): flat faces with 45-degree bevelled edges,
## written in centimetres (BODY_VOXEL) and built in BODY_SUB finer voxels. Every part keeps
## its joints (pivots), so the animations and gear fit as before.
const BODY_VOXEL := 0.01
## Built at half that (0.5 cm), so the bevels step finely.
const BODY_SUB := 2


## A loft: a low-poly body around the vertical line at (`cx`, `cz`), from `keys`, each
## [y, half-width, half-depth] in voxels (bottom to top), straight between keys. `bevel`
## cuts the corners (0 square, 1 a diamond). `paint` only recolours voxels already there.
static func _loft(cx: float, cz: float, keys: Array, colour: int, bevel := 0.5, paint := false) -> Dictionary:
	return {"centre": Vector2(cx, cz), "keys": keys, "colour": colour, "bevel": bevel, "paint": paint}


## Moves a part's lofts and boxes up by `dy` voxels (the shin and thigh stacked into a leg).
static func _shifted(parts: Array, dy: int) -> Array:
	var out := []
	for part: Variant in parts:
		if part is Dictionary:
			var moved: Dictionary = part.duplicate(true)
			for key: Array in moved.keys:
				key[0] = float(key[0]) + dy
			out.append(moved)
		else:
			var box: Array = part.duplicate()
			box[0] = box[0] + Vector3i(0, dy, 0)
			box[1] = box[1] + Vector3i(0, dy, 0)
			out.append(box)
	return out


## 0.22 x 0.30 x 0.24 m including the neck. Pivot at the base of the neck. A boxy,
## bevelled Stormworks head with a flat face: eyes, brows, a nose, a mouth and ears, hair as
## a cap.
static func _head() -> Dictionary:
	var boxes := [
		_loft(11, 12, [[0, 4.5, 4.5], [8, 5.0, 5.0]], C.SKIN_SHADE, 0.8),  # neck
		_loft(11, 12, [[5, 7.0, 8.0], [9, 9.8, 10.8], [13, 10.6, 11.6], [26, 11.0, 12.0], [30, 9.0, 10.0]], C.SKIN, 0.5),
		_p(0, 26, 0, 22, 30, 24, C.HAIR),   # cap
		_p(0, 11, 17, 22, 30, 24, C.HAIR),  # back
		_p(0, 20, 10, 22, 30, 24, C.HAIR),  # above the ears
		_b(0, 14, 10, 1, 19, 15, C.SKIN_SHADE), _b(21, 14, 10, 22, 19, 15, C.SKIN_SHADE),  # ears
		_p(6, 17, 0, 8, 20, 3, C.EYE), _p(14, 17, 0, 16, 20, 3, C.EYE),
		_p(5, 21, 0, 9, 22, 3, C.HAIR), _p(13, 21, 0, 17, 22, 3, C.HAIR),  # brows
		_b(10, 13, 0, 12, 17, 1, C.SKIN_SHADE),  # nose
		_p(8, 10, 0, 14, 11, 3, C.MOUTH),
	]
	return {"size": Vector3i(22, 30, 24), "pivot": Vector3(11, 0, 12), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## 0.38 x 0.66 x 0.22 m: the trunk from the crotch (0.10 m below the hip joints, where the
## legs show from on a real body) to the base of the neck 0.56 m above them. Pivot at the
## hips. Narrower at the waist, broad at the chest, sloping shoulders; the belt at the waist.
static func _torso() -> Dictionary:
	var boxes := [
		_loft(19, 11, [[0, 15.0, 9.5], [10, 16.0, 10.5], [22, 15.0, 10.0], [40, 18.0, 11.0], [56, 19.0, 11.0],
			[62, 16.0, 9.0], [66, 10.0, 7.0]], C.CAMO, 0.45),
		_p(0, 14, 0, 38, 20, 22, C.BELT),
		_p(16, 14, 0, 22, 20, 3, C.METAL),
		_p(13, 60, 0, 25, 66, 7, C.CAMO_C),  # collar
	]
	return {"size": Vector3i(38, 66, 22), "pivot": Vector3(19, 10, 11), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## 0.12 x 0.32 x 0.12 m. Pivot at the shoulder; the elbow is at the bottom.
static func _upper_arm() -> Dictionary:
	var boxes := [
		_loft(6, 6, [[0, 4.5, 4.5], [27, 5.6, 5.4], [32, 4.6, 4.6]], C.CAMO, 0.6),
		_p(0, 14, 2, 2, 26, 10, C.PATCH), _p(10, 14, 2, 12, 26, 10, C.PATCH),
	]
	return {"size": Vector3i(12, 32, 12), "pivot": Vector3(6, 32, 6), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## 0.11 x 0.32 x 0.11 m including the gloved hand. Pivot at the elbow; the palm centre is
## 0.25 m below it (CharacterModel.FOREARM).
static func _forearm() -> Dictionary:
	var boxes := [
		_loft(5.5, 5.5, [[14, 4.0, 4.0], [32, 5.0, 5.0]], C.CAMO, 0.6),
		_loft(5.5, 5.5, [[0, 3.6, 2.8], [6, 5.0, 3.3], [11, 4.2, 3.3], [15, 4.1, 3.9]], C.GLOVE, 0.6),
		_p(0, 14, 0, 11, 17, 11, C.CAMO_A),  # cuff
	]
	return {"size": Vector3i(11, 32, 11), "pivot": Vector3(5.5, 32, 5.5), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## 0.14 x 0.90 x 0.18 m with the boot toe: a thigh on a shin. Pivot at the hip joint.
static func _leg() -> Dictionary:
	var boxes := _shin_parts()
	boxes.append_array(_shifted(_thigh_parts(), 44))  # its knee overlaps the shin by 2 cm
	return {"size": Vector3i(14, 90, 18), "pivot": Vector3(7, 90, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## The leg above the knee: 0.14 x 0.46 x 0.18 m. Pivot at the hip joint; the knee
## (CharacterModel.THIGH) is at the bottom, with the top of the knee pad. Its top 0.10 m is
## inside the torso's hips.
static func _thigh() -> Dictionary:
	return {"size": Vector3i(14, 46, 18), "pivot": Vector3(7, 46, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": _thigh_parts()}


## The leg below the knee with the boot: 0.14 x 0.46 x 0.18 m. Pivot at the knee.
static func _shin() -> Dictionary:
	return {"size": Vector3i(14, 46, 18), "pivot": Vector3(7, 46, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": _shin_parts()}


static func _thigh_parts() -> Array:
	return [
		_loft(7, 10, [[0, 5.0, 5.5], [24, 6.2, 7.0], [46, 7.0, 7.8]], C.CAMO, 0.55),
		_b(2, 0, 3, 12, 4, 6, C.PAD),  # top of the knee pad
		_p(0, 12, 6, 2, 26, 14, C.CAMO_C), _p(12, 12, 6, 14, 26, 14, C.CAMO_C),  # cargo pockets
	]


static func _shin_parts() -> Array:
	return [
		_loft(7, 10, [[12, 4.0, 4.5], [32, 5.4, 6.0], [46, 5.0, 5.5]], C.CAMO, 0.55),
		_b(2, 36, 3, 12, 46, 6, C.PAD),  # knee pad
		_loft(7, 9.5, [[0, 5.2, 8.5], [4, 5.2, 8.5], [10, 4.6, 6.5], [15, 4.3, 5.0]], C.BOOT, 0.35),
		_p(0, 0, 0, 14, 2, 18, C.SOLE),
	]


## Plate carriers by tier (0 light, 1 medium, 2 heavy), in 1 cm voxels. The pivot is the
## carrier's mount point on the torso (GearRig mounts it at torso height 0.17 m), so the
## layout below is in carrier-local centimetres. Each plate the carrier takes sits in a
## fabric pocket: the pocket wraps the plate's edges and back, and a 2 cm lip runs round its
## face, leaving a window where the plate (the VoxelArmor, which GearRig colours as the
## carrier's fabric) shows. Plates centre at torso y 0.33 (front and back, at the carrier's
## plate_depth) and 0.28 (sides, at side_plate_x), as GearRig.armor_transform puts them.
static func _vest(tier: int) -> Dictionary:
	var hw: int = [20, 21, 23][tier]       # half-width of the cummerbund, cm
	var hd: int = [12, 13, 15][tier]       # half-depth of the cummerbund
	var depth: float = [14.0, 14.0, 16.5][tier]  # plate centre, front and back
	var below: int = [0, 0, 8][tier]       # the heavy carrier's groin flap hangs below the mount
	var half_x := 28
	var half_z := int(depth) + 5
	var size := Vector3i(half_x * 2, 41 + below, half_z * 2)
	var o := Vector3i(half_x, below, half_z)  # carrier-local (0, 0, 0) in voxels
	var boxes := []
	var at := func(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int, paint := false) -> void:
		boxes.append([Vector3i(x0, y0, z0) + o, Vector3i(x1, y1, z1) + o, colour, paint])
	# Cummerbund round the torso (the light rig has none, only straps round the back).
	if tier > 0:
		boxes.append(_loft(o.x, o.z, [[o.y, hw, hd], [o.y + 22, hw, hd]], C.GEAR, 0.3))
		for y in [5, 9, 13, 17]:  # MOLLE rows on the sides
			at.call(-hw, y, -hd + 3, hw, y + 1, hd - 3, C.GEAR_DARK, true)
		at.call(-hw, 0, -hd, hw, 2, hd, C.GEAR_DARK, true)  # bottom binding
	else:
		at.call(-hw, 10, 8, -hw + 3, 13, 13, C.GEAR_DARK)
		at.call(hw - 3, 10, 8, hw, 13, 13, C.GEAR_DARK)
		at.call(-hw, 10, 11, hw, 13, 13, C.GEAR_DARK)  # back strap
	# Plate pockets, front and (medium, heavy) back. The plate is 25 x 30 cm, y 1-31.
	var faces := [-1] if tier == 0 else [-1, 1]
	for f: int in faces:
		var inner := int(depth) - 3
		var outer := int(depth) + 3
		var z0 := -outer if f < 0 else inner
		var z1 := -inner if f < 0 else outer
		at.call(-14, 0, z0, 14, 33, z1, C.GEAR)                          # the pocket
		at.call(-13, 1, z0 + 1, 13, 32, z1 - 1, C.EMPTY)                 # the plate's room
		var face := z0 if f < 0 else z1 - 1
		at.call(-11, 3, face, 11, 30, face + 1, C.EMPTY)                 # window: the plate shows
		at.call(-14, 31, z0, 14, 33, z1, C.GEAR_DARK)                    # top binding
		# Shoulder straps from the top of the pocket up over the shoulder.
		for side: int in [-1, 1]:
			var sx0 := 6 if side > 0 else -11
			at.call(sx0, 31, -int(depth) if f < 0 else 0, sx0 + 5, 40, 0 if f < 0 else int(depth), C.GEAR)
	if tier == 0:
		for side: int in [-1, 1]:  # straps cross the back
			var sx0 := 6 if side > 0 else -11
			at.call(sx0, 13, 11, sx0 + 5, 40, 13, C.GEAR_DARK)
	# Heavy: side plate pockets (15 x 20 cm plates at x 24.5, y 1-21), collar and groin flap.
	if tier == 2:
		for side: int in [-1, 1]:
			var x0 := 22 if side > 0 else -27
			at.call(x0, 0, -9, x0 + 5, 23, 9, C.GEAR)
			at.call(x0 + 1, 1, -8, x0 + 4, 22, 8, C.EMPTY)
			var face := x0 + 4 if side > 0 else x0
			at.call(face, 3, -6, face + 1, 20, 6, C.EMPTY)
		at.call(-15, 33, -int(depth) - 2, 15, 39, -int(depth) + 3, C.GEAR_DARK)  # collar
		at.call(-8, -below, -int(depth) - 3, 8, 0, -int(depth) + 2, C.GEAR)       # groin flap
		at.call(-8, -below, -int(depth) - 3, 8, -below + 1, -int(depth) + 2, C.GEAR_DARK)
	return {"size": size, "pivot": Vector3(o), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


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
