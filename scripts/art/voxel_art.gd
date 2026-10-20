class_name VoxelArt
extends RefCounted
## Small voxel models built in code from box lists: the soldier's body parts and gear.
## Every model uses the same palette layout (enum C); a variant fills in the colours, so
## one soldier can be multicam, woodland, desert or urban. Meshes are cached per variant.
##
## Coordinates are voxels (VOXEL_SIZE metres). Front is -Z (voxel z = 0), up is +Y.
## A box is [from: Vector3i, to: Vector3i (exclusive), colour]; later boxes overwrite.

const VOXEL_SIZE := 0.02
## Fine gear (pouches, weapons, packs) and the body are built at 0.5 cm.
const FINE_VOXEL := 0.005

## Body types (CharacterModel.body). "male" is the default; a female soldier's parts are
## the same names with FEMALE_SUFFIX added ("torso_f", "head_f", ...), built on the same joints
## and pivots, so animations, plates, carriers, helmets and held weapons fit either.
const MALE := "male"
const FEMALE := "female"
const BODIES: Array[String] = [MALE, FEMALE]
const FEMALE_SUFFIX := "_f"
## A plate carrier fitted to a woman ("vest_f:<tier>", _vest; GearRig.carrier_fit): it conforms to
## her body with the plates inside, as a real one does (Captain): its front panel sits flat
## FEMALE_CARRIER_FRONT_OUT cm further out, over her bust held flat beneath it ("torso_fc"), its
## inside padded down to her chest and belly so it lies on her with no gap; its back panel sits
## FEMALE_CARRIER_BACK cm further in (her back is slimmer). (FEMALE_CARRIER_TILT_DEG can lean the
## front panel out from its top edge; flat, it is 0.)
const FEMALE_CARRIER_FRONT_OUT := 1.0
const FEMALE_CARRIER_TILT_DEG := 0.0
const FEMALE_CARRIER_BACK := 2

enum C {
	EMPTY, CAMO, CAMO_A, CAMO_B, CAMO_C, CAMO_D, SKIN, SKIN_SHADE, HAIR, EYE, MOUTH,
	BOOT, SOLE, GLOVE, BELT, METAL, PAD, PATCH, GEAR, GEAR_DARK, PACK, PACK_DARK,
	GUN, GUN_LIGHT, LENS, LIP, LIP_SHADE, WOOD, WOOD_DARK,
	WOUND, WOUND_DARK,  # torn flesh round a hole BodyDeform carved
	BRASS,  # cartridge cases (a belt-fed's belt)
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
		# Black Ridge Militia (Captain, 2026-10-17: "give the militia we typically face early game
		# an orange marker on their uniform instead of the same red one that's on the PMC"): an
		# orange patch, not Vantage's "black" scheme's dark red one, so the two hostile factions
		# read apart at a glance.
		"camo": ["5c6066", "3f4247", "7a7e84", "26282b"], "skin": "b07a52", "hair": "1f1a17",
		"patch": "d9730d", "gear": "34373b", "pack": "3a3d42",
	},
	"dummy": {
		"camo": ["f2c230", "f2c230", "e3b022", "f2c230"], "skin": "f2c230", "hair": "f2c230",
		"patch": "222222", "gear": "8a7a58", "pack": "7a6c4e",
	},
	## Vantage Group (CLAUDE.md squad-roles-pmc bundle, Captain 2026-10-17: "black for enemy
	## pmc"): flat black operator kit, not a camo pattern, so it reads apart from Black Ridge's
	## grey urban camo at a glance.
	"black": {
		"camo": ["1a1a1a", "141414", "202020", "0d0d0d"], "skin": "b07a52", "hair": "1f1a17",
		"patch": "5c1f1f", "gear": "232323", "pack": "1f1f1f",
	},
	## Captain, 2026-10-17: "tan for us". A flat coyote-tan kit, same shape as "black" above.
	"tan": {
		"camo": ["c9ba9c", "bfae8e", "d9ccae", "a89470"], "skin": "c8996f", "hair": "3b2a1d",
		"patch": "3b4a6b", "gear": "a8977a", "pack": "9c8a68",
	},
}
## Plain clothes (civilians, HVTs and hostages: PersonLook.outfit) instead of a uniform:
## "civ:<shirt>:<trousers>:<skin>:<shoes>" in hex. The torso, arms and head take the shirt,
## the legs the trousers; hands are bare, and the cloth is one flat colour: no pattern, unit
## patch, knee pads or belt (Captain). Each part builds from only the colours it shows (_civ_part), so
## people sharing a shirt share the torso mesh.
const CIV_PREFIX := "civ:"


## A colour scheme's colours: a VARIANTS entry, or a plain-clothes scheme built from its name.
static func spec(variant: String) -> Dictionary:
	if VARIANTS.has(variant):
		return VARIANTS[variant]
	if variant.begins_with(CIV_PREFIX) or variant.begins_with("civp:"):
		var f := variant.split(":")
		if f.size() >= 4:
			var cloth := Color(f[1])
			return {"camo": [cloth, cloth, cloth, cloth],
				"skin": f[2] if variant.begins_with("civp:") else f[3], "hair": "241a12", "patch": cloth,
				"gear": "5a5148", "pack": "5a5148", "pad": cloth, "belt": cloth, "glove": f[2] if variant.begins_with("civp:") else f[3],
				"boot": f[3] if variant.begins_with("civp:") else f[4]}
	return VARIANTS["multicam"]


## The scheme one body part of a plain-clothes person builds with: "civp:<cloth>:<skin>:<shoes>",
## the cloth the trousers on the legs and the shirt everywhere else.
static func _civ_part(model: String, variant: String) -> String:
	var f := variant.split(":")
	if f.size() < 5:
		return variant
	var part := model.get_slice(":", 0)
	var legs := part.begins_with("thigh") or part.begins_with("shin") or part.begins_with("leg")
	return "civp:%s:%s:%s" % [f[2] if legs else f[1], f[3], f[4]]

static var _meshers: Dictionary = {}  # variant -> VoxelMesherCubes
static var _meshes: Dictionary = {}   # "model|variant" -> Mesh
## Plain clothes' rasterised models (the model name's hash -> VoxelBuffer), shared by every plain-clothes
## scheme: their cloth is one flat palette entry (no camo), so the voxels' colour indices are the
## same whatever the colours, and only the mesher's palette differs. Rasterising a 0.5 cm body
## is about 0.5 s and meshing it about 30 ms, so a new person's outfit costs only the meshing
## (Captain P0362: 12 civilians at once were a 3.4 s hitch on deploying).
static var _plain_rasters: Dictionary = {}
## The body parts a soldier or person is built from (CharacterModel).
const BODY_PARTS: Array[String] = ["head", "torso", "upper_arm", "forearm", "thigh", "shin"]
## Rasters built ahead on a worker thread (warm): "salt|variant" (_raster_key) -> VoxelBuffer.
## The worker adds each as it finishes, under _warm_mutex; the main thread takes one that's there
## and never waits for the rest (it rasterises one that isn't, as before).
static var _warmed: Dictionary = {}
static var _warm_mutex := Mutex.new()
static var _warm_tasks: Array[int] = []
static var _warm_asked: Dictionary = {}  # "model|variant" -> true: warmed once already
static var _material: StandardMaterial3D
static var _noise_a: FastNoiseLite
static var _noise_b: FastNoiseLite
static var _box_meshes: Dictionary = {}     # "dims|colour" -> Mesh (bevel_box_mesh)
static var _colour_meshers: Dictionary = {}  # colour -> VoxelMesherCubes


## A pivot node holding the model's mesh. The pivot is the model's centre unless the
## spec names one (body parts pivot at their joints).
static func instance(model: String, variant: String, layers := 1) -> Node3D:
	var spec := _spec(model)
	var pivot := Node3D.new()
	pivot.name = model.get_slice("|", model.count("|")).get_slice(":", 0).trim_suffix(FEMALE_SUFFIX)  # "torso_f" is still the torso
	pivot.set_meta(&"voxel_model", model)  # BodyDeform re-rasterises it to carve into
	pivot.set_meta(&"voxel_variant", variant)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh(model, variant)
	mesh_instance.material_override = _get_material()
	mesh_instance.layers = layers
	var voxel: float = spec.get("voxel", VOXEL_SIZE)
	mesh_instance.scale = Vector3.ONE * voxel / int(spec.get("sub", 1))  # built in sub-voxels
	mesh_instance.position = -spec.get("pivot", Vector3(spec.size) * 0.5) * voxel
	pivot.add_child(mesh_instance)
	return pivot


## The model name of body part `part` ("head", "torso", "upper_arm", "forearm", "leg",
## "thigh", "shin") for a body type (BODIES; anything else builds the male part).
static func body_part(part: String, body: String) -> String:
	return part + FEMALE_SUFFIX if body == FEMALE else part


static func size_m(model: String) -> Vector3:
	var spec := _spec(model)
	return Vector3(spec.size) * float(spec.get("voxel", VOXEL_SIZE))


## The model `model` (model_for) as worn by body type `body`: a woman wears the fitted carrier
## ("vest:1" -> "vest_f:1"); everything else is the same model.
static func fitted(model: String, body: String) -> String:
	return model.replace("vest:", "vest_f:") if body == FEMALE and model.begins_with("vest:") else model


## Model name for an item, or "" if it has no voxel model yet (it falls back to a box). A
## rifle's names the sight on it ("rifle:42:dot", "rifle:52:scope", "rifle:42:irons"): the
## optic its item state `state` mounts (Optics), else its own.
static func model_for(item: ItemData, state := {}) -> String:
	if Optics.is_optic(item):
		return "optic:" + Optics.art_of(item)
	match item.slot:
		&"primary":
			var length: float = item.stats.get("size_m", [0, 0, 0.84])[2]
			var style := String(item.stats.get("model_style", ""))  # "ak", "mg": a different silhouette
			# No rail: the old fixed dot for the AR family, but AKs and MGs carry irons only
			# (Captain, 2026-10-15: the AK showed a red-dot block that did nothing).
			var art := Optics.art_of(Optics.mounted(item, state)) if Optics.has_rail(item) else ("dot" if style == "" else IRONS)
			var sup := Suppressors.mounted_id(item, state) != &""
			return "rifle:%d:%s:%s:%s" % [roundi(length / VOXEL_SIZE), art if art != "" else IRONS, style, "sup" if sup else ""]
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
		"rifle" when _rifle_style(model) == "walker":
			grip = Vector3(WALKER_AXIS_X, 2, n * 0.807)  # its pistol grip, under the receiver's back end
			support = Vector3(WALKER_AXIS_X, 2, n - 27.0)  # its vertical foregrip
		"rifle" when _rifle_style(model) == "bullpup":
			grip = Vector3(1.5, 4 + RIFLE_BELOW, n * 0.68)     # pistol grip, the magazine behind it
			support = Vector3(1.5, 6 + RIFLE_BELOW, n - 26.0)  # on the handguard, as far out as the arm reaches
		"rifle":
			grip = Vector3(1.5, 4 + RIFLE_BELOW, n * 0.68)     # pistol grip
			# Under the handguard, no further than 0.52 m from the butt: as far out as the
			# arms reach with the support shoulder forward (CharacterModel.SUPPORT_REACH).
			support = Vector3(1.5, 6 + RIFLE_BELOW, maxf(n * 0.42, n - 26.0))
		"pistol":
			grip = Vector3(1, 2.5, 7.5)
			support = Vector3(-0.5, 2, 7.5)      # cupping the grip from the left
		_:
			return {}
	return {"grip": (grip - centre) * VOXEL_SIZE, "support": (support - centre) * VOXEL_SIZE}


## The line of sight's back end, in metres relative to the instance pivot (its centre):
## aiming puts this point on the eye's line (PlayerInput.ads_view). A rifle's is the middle of
## its optic's back end (you look through it: Captain, P0362) or of its rear aperture (irons),
## a pistol's the top of its rear sight notch, level with the front post's top. Zero for
## non-weapons.
static func sight_point(model: String) -> Vector3:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	match model.get_slice(":", 0):
		"rifle":
			var art := _rifle_art(model)
			var back := sight_back(art, spec.size.z) + (IRON_EYE_RELIEF if art == IRONS else 0.0)
			return (Vector3(_axis_x(model), OPTIC_AXIS_Y + _below(model), back) - centre) * VOXEL_SIZE
		"pistol":
			return (Vector3(1, 7.0, 9.4) - centre) * VOXEL_SIZE  # rear sight notch
	return Vector3.ZERO


## Centre of the butt pad, in metres relative to the instance pivot (its centre): the point
## that goes into the shoulder pocket. Zero for weapons without a stock (and non-weapons).
static func butt_point(model: String) -> Vector3:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	if model.get_slice(":", 0) == "rifle":
		return (Vector3(_axis_x(model), 7.7 + _below(model), spec.size.z) - centre) * VOXEL_SIZE
	return Vector3.ZERO


static func mesh(model: String, variant: String) -> Mesh:
	if variant.begins_with(CIV_PREFIX):
		variant = _civ_part(model, variant)
	var key := "%s|%s" % [model, variant]
	if not _meshes.has(key):
		_meshes[key] = _build(_spec(model), variant, model.hash())
	return _meshes[key]


## A fresh raster of `model` for `variant`, the soldier's own to carve (BodyDeform). Thread-safe
## like warm(): the same rasterising, nothing shared written.
static func raster_copy(model: String, variant: String) -> VoxelBuffer:
	if variant.begins_with(CIV_PREFIX):
		variant = _civ_part(model, variant)
	return _rasterize(_spec(model), variant, model.hash())


## The mesher for `variant` (main thread: it may make one), for meshing a raster_copy elsewhere.
static func mesher_for(model: String, variant: String) -> VoxelMesherCubes:
	if variant.begins_with(CIV_PREFIX):
		variant = _civ_part(model, variant)
	return _get_mesher(variant)


static func _build(spec: Dictionary, variant: String, salt: int) -> Mesh:
	return _get_mesher(variant).build_mesh(_raster(spec, variant, salt), [])


## The model rasterised for `variant`: a plain-clothes scheme ("civp:") reuses the model's one
## plain raster (_plain_rasters, by `salt`: mesh() salts with the model's name); otherwise one
## the warm-up built (warm), or built now.
static func _raster(spec: Dictionary, variant: String, salt: int) -> VoxelBuffer:
	var plain := variant.begins_with("civp:")
	if plain and _plain_rasters.has(salt):
		return _plain_rasters[salt]
	var key := _raster_key(salt, variant)
	_warm_mutex.lock()
	var buffer: VoxelBuffer = _warmed.get(key)
	_warmed.erase(key)
	_warm_mutex.unlock()
	if buffer == null:
		buffer = _rasterize(spec, variant, salt)
	if plain:
		_plain_rasters[salt] = buffer
	return buffer


## Plain clothes all share one raster per model ("civp:"); every other scheme has its own.
static func _raster_key(salt: int, variant: String) -> String:
	return "%d|%s" % [salt, "civp:" if variant.begins_with("civp:") else variant]


## Rasterises `pairs` ([model, variant], as mesh() takes them) on a worker thread, so the
## first soldier or person built from them only meshes (rasterising is ~95% of building a
## 0.5 cm part). Each pair is warmed once a session. PeopleLayer calls it as a level starts:
## the hostiles' uniform (Captain P0362: the first garrison of the session was a 0.43 s frame)
## and plain clothes' bodies.
static func warm(pairs: Array) -> void:
	var todo: Array = []
	for pair: Array in pairs:
		var model: String = pair[0]
		var variant: String = pair[1]
		if variant.begins_with(CIV_PREFIX):
			variant = _civ_part(model, variant)
		var asked := "%s|%s" % [model, "civp:" if variant.begins_with("civp:") else variant]
		if _warm_asked.has(asked) or _meshes.has("%s|%s" % [model, variant]) or (variant.begins_with("civp:") and _plain_rasters.has(model.hash())):
			continue
		_warm_asked[asked] = true
		todo.append([model, variant])
	if todo.is_empty():
		return
	_camo(Vector3.ZERO, 0, "multicam")  # its noise is made here on the main thread, not on the worker
	_reap_warm()
	_warm_tasks.append(WorkerThreadPool.add_task(_warm.bind(todo), false, "VoxelArt warm-up"))


## The models a soldier in `variant` with `loadout` (item ids) is built from: the body's parts
## and the art of what's worn and carried (model_for), as [model, variant] pairs for warm().
static func uniform(variant: String, loadout: Array, body := MALE) -> Array:
	var out: Array = []
	for part in BODY_PARTS:
		out.append([body_part(part, body), variant])
	for id: Variant in loadout:
		var item := ItemDB.get_item(StringName(id))
		var model := fitted(model_for(item), body) if item else ""
		if model != "" and not out.has([model, variant]):
			out.append([model, variant])
			if has_magazine(model):  # a reload draws it in two (CharacterModel._pose_reload_mags)
				out.append_array([[WITHOUT_MAG + model, variant], [MAG + model, variant]])
			var moving := moving_parts(model)
			if not moving.is_empty():  # near the view, it works the action or cover apart too
				out.append([FIXED + model, variant])
				for tag in moving:
					out.append([(BOLT if tag == BOLT_TAG else COVER) + model, variant])
	return out


static func _warm(todo: Array) -> void:
	for pair: Array in todo:
		var model: String = pair[0]
		var buffer := _rasterize(_spec(model), pair[1], model.hash())
		_warm_mutex.lock()
		_warmed[_raster_key(model.hash(), pair[1])] = buffer
		_warm_mutex.unlock()


## Lets go of finished warm-up tasks (WorkerThreadPool wants every task waited for).
static func _reap_warm() -> void:
	for task in _warm_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_warm_tasks.erase(task)


## Waits for every warm-up task still running. As a level goes, so none is left at quit.
static func finish_warm() -> void:
	for task in _warm_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_warm_tasks.clear()


## Which built voxels of `model` are solid, for hit tests (BodyVolume): {"dims" (built
## voxels), "cell" (metres), "pivot" (metres from the grid's corner to the model's pivot),
## "solid" (a PackedByteArray, 1 where solid, x fastest then y then z)}.
static func occupancy(model: String) -> Dictionary:
	var spec := _spec(model)
	var s: int = spec.get("sub", 1)
	var voxel: float = spec.get("voxel", VOXEL_SIZE)
	var buffer := _rasterize(spec, "dummy", 0)  # dummy: plain colours, no camo noise to compute
	var dims: Vector3i = spec.size * s
	var solid := PackedByteArray()
	solid.resize(dims.x * dims.y * dims.z)
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				if buffer.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) != C.EMPTY:
					solid[x + dims.x * (y + dims.y * z)] = 1
	var pivot: Vector3 = spec.get("pivot", Vector3(spec.size) * 0.5)
	return {"dims": dims, "cell": voxel / s, "pivot": pivot * voxel, "solid": solid}


## The model's voxels in a buffer with 1 voxel of mesher padding per side.
static func _rasterize(spec: Dictionary, variant: String, salt: int) -> VoxelBuffer:
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
	# A run of one row (x, y), z0 to z1 exclusive, in one colour: the hidden middle of a loft.
	var run := func(x: int, y: int, z0: int, z1: int, colour: int) -> void:
		if x < 0 or y < 0 or x >= size.x or y >= size.y:
			return
		z0 = maxi(z0, 0)
		z1 = mini(z1, size.z)
		if z0 < z1:
			buffer.fill_area(colour, Vector3i(x + 1, y + 1, z0 + 1), Vector3i(x + 2, y + 2, z1 + 1), VoxelBuffer.CHANNEL_COLOR)
	for box: Variant in spec.boxes:
		if box is Dictionary:
			_fill_loft(box, put, s, run)
			continue
		var from := Vector3i((Vector3(box[0]) * s).round())  # corners may be fractional (_fb)
		var to := Vector3i((Vector3(box[1]) * s).round())
		var paint_only: bool = box.size() > 3 and box[3]  # _p: recolours, never adds
		if not paint_only and box[2] != C.CAMO:  # one colour: fill it in one go
			var lo := Vector3i(maxi(from.x, 0), maxi(from.y, 0), maxi(from.z, 0))
			var hi := Vector3i(mini(to.x, size.x), mini(to.y, size.y), mini(to.z, size.z))
			if lo.x < hi.x and lo.y < hi.y and lo.z < hi.z:
				buffer.fill_area(box[2], lo + Vector3i.ONE, hi + Vector3i.ONE, VoxelBuffer.CHANNEL_COLOR)
			continue
		for x in range(from.x, to.x):
			for y in range(from.y, to.y):
				for z in range(from.z, to.z):
					put.call(x, y, z, box[2], paint_only)
	return buffer


## Fills a loft (_loft): at each voxel layer, a low-poly cross-section (a rectangle with its
## four corners cut at 45 degrees by "bevel", 0 square to 1 a diamond) whose half-width and
## half-depth are interpolated between the keys, so the sides read as flat facets. Works a
## row (x) at a time: the row's z span comes straight from the cross-section, its outer
## voxels go in one by one (camo worked out per voxel), and with `run` its hidden middle goes
## in as one fill in the base colour, which keeps the 0.5 cm body quick to build.
static func _fill_loft(loft: Dictionary, put: Callable, s := 1, run := Callable()) -> void:
	var keys: Array = loft.keys
	var centre: Vector2 = loft.centre * s
	var bevel: float = loft.bevel
	var colour: int = loft.colour
	var paint: bool = loft.paint
	var y0 := int(keys[0][0]) * s
	var y1 := int(keys[keys.size() - 1][0]) * s
	const SHELL := 2  # outer voxels per side that get their own colour
	for y in range(y0, y1):
		var yc := (y + 0.5) / s
		var i := 0
		while i < keys.size() - 2 and yc > float(keys[i + 1][0]):
			i += 1
		var t := clampf(inverse_lerp(float(keys[i][0]), float(keys[i + 1][0]), yc), 0.0, 1.0)
		var hw := lerpf(keys[i][1], keys[i + 1][1], t) * s
		var hd := lerpf(keys[i][2], keys[i + 1][2], t) * s
		if hw <= 0.0 or hd <= 0.0:
			continue
		var end_layer := y < y0 + SHELL or y >= y1 - SHELL
		for x in range(int(floor(centre.x - hw)), int(ceil(centre.x + hw))):
			var dx := absf(x + 0.5 - centre.x) / hw
			var m := minf(1.0, 2.0 - bevel - dx)  # how far out (in half-depths) the row reaches
			if dx > 1.0 or m < 0.0:
				continue
			var za := int(ceil(centre.y - hd * m - 0.5))
			var zb := int(floor(centre.y + hd * m - 0.5)) + 1  # exclusive
			if za >= zb:
				continue
			var inner_x := absf(x + 0.5 - centre.x) <= hw - SHELL - 1.0
			if paint or not run.is_valid() or end_layer or not inner_x or zb - za <= SHELL * 2:
				for z in range(za, zb):
					put.call(x, y, z, colour, paint)
				continue
			for z in range(za, za + SHELL):
				put.call(x, y, z, colour, false)
			for z in range(zb - SHELL, zb):
				put.call(x, y, z, colour, false)
			run.call(x, y, za + SHELL, zb - SHELL, C.CAMO_A if colour == C.CAMO else colour)


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
	match "plain" if variant.begins_with("civp:") else variant:
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
		"plain":  # plain clothes: one flat colour, no pattern (Captain: nothing remotely military)
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
		var v: Dictionary = spec(variant)
		var skin := Color(v.skin)
		var colours := {
			C.EMPTY: Color(0, 0, 0, 0),
			C.CAMO_A: Color(v.camo[0]), C.CAMO_B: Color(v.camo[1]), C.CAMO_C: Color(v.camo[2]), C.CAMO_D: Color(v.camo[3]),
			C.SKIN: skin, C.SKIN_SHADE: skin.darkened(0.15), C.HAIR: Color(v.hair),
			C.EYE: Color("1c1c1c"), C.MOUTH: skin.darkened(0.35),
			C.BOOT: Color(v.get("boot", "3a3027")), C.SOLE: Color("1e1a17"), C.GLOVE: Color(v.get("glove", "2f2f2a")),
			C.BELT: Color(v.get("belt", "3d3a2e")), C.METAL: Color("8c8c84"), C.PAD: Color(v.get("pad", "2b2b27")),
			C.PATCH: Color(v.patch),
			C.GEAR: Color(v.gear), C.GEAR_DARK: Color(v.gear).darkened(0.25),
			C.PACK: Color(v.pack), C.PACK_DARK: Color(v.pack).darkened(0.25),
			C.GUN: Color("262626"), C.GUN_LIGHT: Color("3b3b37"), C.LENS: Color("3a6f8f"),
			C.WOOD: Color("8a5530"), C.WOOD_DARK: Color("5e3a1e"),
			C.LIP: skin.lerp(Color("9a4a44"), 0.3).darkened(0.12), C.LIP_SHADE: skin.lerp(Color("9a4a44"), 0.2),
			C.WOUND: Color("6e1712"), C.WOUND_DARK: Color("2a0605"),
			C.BRASS: Color("a8873f"),
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
	if model.contains("|"):  # a part of a weapon (MAG, WITHOUT_MAG, BOLT, COVER, FIXED)
		var prefix := model.get_slice("|", 0) + "|"
		var whole := _spec(model.substr(prefix.length()))
		var part := whole.duplicate()
		part.boxes = whole.boxes.filter(func(b: Variant) -> bool: return _in_part(b, prefix))
		return part
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
		"vest_f": return _vest(arg, _torso_f(true), true)
		"vest_f_front": return _vest(arg, _torso_f(true), true, true)
		"backpack": return _backpack(arg)
		"rifle":
			var art := _rifle_art(model)
			var out: Dictionary
			match _rifle_style(model):
				"ak": out = _rifle_ak(arg, art)
				"pk": out = _rifle_pkm(arg, art)
				"m240": out = _rifle_m240(arg, art)
				"m249": out = _rifle_m249(arg, art)
				"walker": out = _rifle_walker(arg, art)
				"bullpup": out = _rifle_bullpup(arg, art)
				"carbine_short": out = _rifle_carbine_short(arg, art)
				"piston_ar": out = _rifle_piston_ar(arg, art)
				"mosin": out = _rifle_bolt(arg, art, false)
				"chassis_bolt": out = _rifle_chassis_bolt(arg, art)
				_: out = _rifle(arg, art)
			if _rifle_suppressed(model):
				out = _with_suppressor(out)
			return _lowered(out, RIFLE_BELOW) if _rifle_style(model) != "walker" else out
		"optic": return _optic_model(model.get_slice(":", 1))
		"pistol": return _pistol()
		"head_f": return _head_f()
		"torso_f": return _torso_f()
		"torso_fc": return _torso_f(true)
		"upper_arm_f": return _upper_arm_f()
		"forearm_f": return _forearm_f()
		"leg_f": return _leg_f()
		"thigh_f": return _thigh_f()
		"shin_f": return _shin_f()
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
## Plate carriers (_vest): their mount's height over the torso pivot (GearRig.rest_transform
## "vest", 0.17 m), and how much webbing and padding the cummerbund adds round the body, by
## tier (light: none, it has straps).
const CARRIER_MOUNT_CM := 17.0
const CUMMERBUND_PAD: Array[float] = [0.0, 1.5, 2.5]
## How much the cummerbund's corners are cut (its loft's bevel): GearRig lays the pouches on
## its corners flat on these facets.
const CUMMERBUND_BEVEL := 0.3
## How far up from the mount (cm) the plate pockets and the cummerbund reach, and a heavy
## carrier's side plate pockets: their outer face out from the spine, half-depth and height
## (cm). GearRig keeps the pouches on a carrier inside these (GearRig.face_region).
const POCKET_TOP_CM := 33
const CUMMERBUND_TOP_CM := 22
const SIDE_POCKET_OUT_CM := 27
const SIDE_POCKET_HALF_Z_CM := 9
const SIDE_POCKET_TOP_CM := 23
## The carriers' padded shoulder pads (_vest): centred SHOULDER_PAD_X cm out from the spine,
## 5 cm wide, arching from the pockets' tops over the shoulders, as [carrier height, half-depth]
## in cm (a woman's reach FEMALE_CARRIER_BACK less far back, to her back panel: shoulder_pad_line).
## GearRig lays a pack's shoulder straps on them.
const SHOULDER_PAD_X := 8.5
const SHOULDER_PAD_ARCH := [[32.0, 12.0], [38.0, 10.5], [41.0, 7.5]]


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
			var up: Variant = Vector3(0, dy, 0) if box[0] is Vector3 else Vector3i(0, dy, 0)  # _fb, _fp: fractional
			box[0] = box[0] + up
			box[1] = box[1] + up
			out.append(box)
	return out


## 0.22 x 0.30 x 0.24 m including the neck. Pivot at the base of the neck. A boxy,
## bevelled Stormworks head with a flat face: eyes, brows, a nose, a mouth and ears, hair as
## a cap. The jaw is a 45-degree chamfer and the face above it is straight up: any other
## slope steps unevenly at 0.5 cm and shows as bands across the chin.
static func _head() -> Dictionary:
	var boxes := [
		_loft(11, 12, [[0, 4.5, 4.5], [8, 5.0, 5.0]], C.SKIN_SHADE, 0.8),  # neck
		_loft(11, 12, [[5, 8.0, 9.0], [8, 11.0, 12.0], [26, 11.0, 12.0], [30, 9.0, 10.0]], C.SKIN, 0.5),
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


## 0.52 x 0.66 x 0.22 m: the trunk from the crotch (0.10 m below the hip joints, where the
## legs show from on a real body) to the base of the neck 0.56 m above them. Pivot at the
## hips. Narrower at the waist, broad at the chest; above the chest the deltoids flare out
## at 45 degrees to 0.26 m, over the shoulder joints (CharacterModel.SHOULDER, 0.25 m out,
## 0.52 m up), and the trapezius runs flat in to the neck. The upper arms' tops sit inside
## the deltoids, so the arms hang out from under them and turn under them. The belt at the
## waist.
static func _torso() -> Dictionary:
	var boxes := [
		_loft(26, 11, [[0, 15.0, 9.5], [10, 16.0, 10.5], [22, 15.0, 10.0], [40, 18.0, 11.0], [53, 20.0, 11.0],
			[58, 25.0, 10.5], [62, 26.0, 10.0], [64, 22.0, 8.5], [66, 10.0, 7.0]], C.CAMO, 0.45),
		_p(0, 14, 0, 52, 20, 22, C.BELT),
		_p(23, 14, 0, 29, 20, 3, C.METAL),
		_p(20, 60, 0, 32, 66, 7, C.CAMO_C),  # collar
	]
	return {"size": Vector3i(52, 66, 22), "pivot": Vector3(26, 10, 11), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## 0.12 x 0.32 x 0.12 m. Pivot at the shoulder; the elbow is at the bottom. It tapers into
## the torso's deltoid at the top, so no square cap shows above the shoulder line.
static func _upper_arm() -> Dictionary:
	var boxes := [
		_loft(6, 6, [[0, 4.5, 4.5], [22, 5.6, 5.4], [28, 5.4, 5.2], [32, 3.6, 3.6]], C.CAMO, 0.6),
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


# --- Female body (body_part(..., FEMALE)) -------------------------------------------
# The same frames, joints and pivots as the male parts above, shaped within them: a smaller
# head with a softer, longer jaw and the hair in a low bun under the helmet's rim; narrower
# shoulders and slimmer deltoids and arms; a narrower waist over wider hips; a modest chest
# that stays inside the plate carrier's pockets (no deeper at the front than the male chest,
# 0.11 m, where the plates sit); slimmer thighs and calves, smaller hands and boots.


## A paint box (_p) with fractional corners, in the spec's voxels (built at its "sub").
static func _fp(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> Array:
	return [Vector3(x0, y0, z0), Vector3(x1, y1, z1), colour, true]


## 0.20 x 0.29 x 0.22 m head on the male head's pivot (base of the neck), with a low bun
## behind (the frame runs 6 cm deeper for it). The jaw is a longer 45-degree chamfer to a
## narrower chin; the face above it is straight up, as on the male head. The bun sits below
## the helmet's rim (head y 0.20), so every helmet still fits over the head.
static func _head_f() -> Dictionary:
	var boxes := [
		_loft(11, 12, [[0, 4.0, 4.0], [8, 4.4, 4.4]], C.SKIN_SHADE, 0.8),  # neck
		_loft(11, 12, [[6, 7.0, 8.0], [9, 10.0, 11.0], [27, 10.0, 11.0], [29, 8.0, 9.0]], C.SKIN, 0.55),
		_loft(11, 25, [[11, 2.5, 2.0], [13, 3.5, 3.0], [17, 3.5, 3.0], [19, 2.5, 2.0]], C.HAIR, 0.6),  # bun
		_p(0, 25, 0, 22, 30, 30, C.HAIR),   # cap, the hairline a little lower than the male's
		_p(0, 9, 17, 22, 30, 30, C.HAIR),   # back, down to the nape, pulled back to the bun
		_p(0, 19, 9, 22, 30, 30, C.HAIR),   # above the ears
		_fp(7, 14.5, 23.5, 15, 15.5, 30, C.PAD),  # hair tie
		_fb(0.5, 14, 10.5, 1, 18, 14, C.SKIN_SHADE), _fb(21, 14, 10.5, 21.5, 18, 14, C.SKIN_SHADE),  # ears
		_fp(6.5, 16.5, 0, 8.5, 19.5, 3, C.EYE), _fp(13.5, 16.5, 0, 15.5, 19.5, 3, C.EYE),
		_fp(6, 19, 0, 7, 19.5, 3, C.EYE), _fp(15, 19, 0, 16, 19.5, 3, C.EYE),  # lashes, at the outer corners
		_fp(6, 21, 0, 8.5, 21.5, 3, C.HAIR), _fp(13.5, 21, 0, 16, 21.5, 3, C.HAIR),  # brows, thin
		_fp(5.5, 20.5, 0, 6, 21, 3, C.HAIR), _fp(16, 20.5, 0, 16.5, 21, 3, C.HAIR),
		_fb(10.5, 13.5, 0.5, 11.5, 16.5, 1, C.SKIN_SHADE),  # nose
		_fp(9, 10.5, 0, 13, 11.5, 3, C.LIP), _fp(9.5, 9.5, 0, 12.5, 10.5, 3, C.LIP_SHADE),  # fuller lips
		_p(0, 17, 0, 2, 27, 6, C.HAIR), _p(20, 17, 0, 22, 27, 6, C.HAIR),  # hair framing the face under the helmet
	]
	return {"size": Vector3i(22, 30, 30), "pivot": Vector3(11, 0, 12), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## The male torso's frame and pivot (hips), 0.66 m from the crotch to the base of the neck:
## hips 0.35 m across (the male's: 0.32), easing in to a 0.27 m waist about 20 cm up and a narrower ribcage her arms
## hang against. Her shoulders (CharacterModel.FEMALE_SHOULDER, 0.20 m out and 1.5 cm lower
## than his) are capped by rounded deltoids 1 cm past the joint, and from there the shoulder
## line slopes down from the neck (the male's runs flat out to a square corner). The whole
## body is drawn at CharacterModel.FEMALE_SCALE.
## The bust is two low-poly lobes high on the chest, its fullest 0.135 m in front of the
## spine, 2.5 cm deeper than the male chest. Under a plate carrier (`carried`, "torso_fc") it
## is held flat by it, as a real carrier does: no deeper than 0.118 m, and pushed out to the
## sides; CharacterModel.set_carrier_worn swaps it in.
## The frame runs 5 cm further forward, and as before 2 cm deeper behind for the seat.
static func _torso_f(carried := false) -> Dictionary:
	var boxes := [
		_loft(26, 16, [[0, 14.5, 9.0], [4, 16.8, 10.0], [9, 17.6, 10.2], [14, 17.0, 9.8], [19, 15.4, 9.0], [25, 13.8, 8.3], [30, 13.4, 8.2], [38, 14.0, 8.5],
			[50, 15.3, 9.0], [55, 17.5, 9.0], [58.5, 20.5, 9.0], [60.5, 21.0, 8.8], [62.5, 17.8, 8.0], [64.5, 13.3, 7.2],
			[66, 9.0, 6.5]], C.CAMO, 0.45),
		_p(0, 14, 0, 52, 20, 29, C.BELT),
		_p(23, 14, 0, 29, 20, 8, C.METAL),
		_p(20, 60, 0, 32, 66, 12, C.CAMO_C),  # collar
	]
	for side: float in [-1.0, 1.0]:  # the bust: a short rounded underside, a long gentle top
		if carried:  # held flat by the carrier, spread to the sides
			boxes.append(_loft(26 + 7.5 * side, 8.7, [[40.5, 5.5, 1.0], [43, 7.5, 3.0], [46.5, 8.2, 4.5], [50, 7.9, 4.0],
				[54, 6.8, 2.2], [57.5, 5.5, 0.5]], C.CAMO, 0.7))
		else:
			boxes.append(_loft(26 + 6.2 * side, 9.3, [[40.5, 5.2, 1.0], [43, 6.9, 4.3], [46.5, 7.4, 6.8], [50, 7.1, 5.8],
				[54, 6.1, 3.2], [57.5, 5.0, 0.5]], C.CAMO, 0.7))
	# The seat: broad and fairly flat across the hips, setting out from the small of the back
	# and rounding under, not a ball (Captain's ref).
	boxes.append(_loft(26, 18, [[1, 13.5, 6.0], [4, 15.5, 9.0], [9, 15.8, 9.6], [14, 14.8, 8.6], [19, 12.5, 5.0], [23, 10.0, 1.5]], C.CAMO, 0.5))  # seat
	return {"size": Vector3i(52, 66, 29), "pivot": Vector3(26, 10, 16), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## The male upper arm's frame and pivot (shoulder), slimmer: 0.10 m across at the biceps (the male's: 0.112).
static func _upper_arm_f() -> Dictionary:
	var boxes := [
		_loft(6, 6, [[0, 4.0, 4.0], [22, 5.0, 4.9], [28, 4.8, 4.7], [32, 3.4, 3.4]], C.CAMO, 0.6),
		_fp(0, 14, 2.5, 2.5, 26, 9.5, C.PATCH), _fp(9.5, 14, 2.5, 12, 26, 9.5, C.PATCH),
	]
	return {"size": Vector3i(12, 32, 12), "pivot": Vector3(6, 32, 6), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


## The male forearm's frame and pivot (elbow; palm centre 0.25 m below), slimmer, with a
## smaller gloved hand.
static func _forearm_f() -> Dictionary:
	var boxes := [
		_loft(5.5, 5.5, [[14, 3.8, 3.8], [32, 4.6, 4.6]], C.CAMO, 0.6),
		_loft(5.5, 5.5, [[0, 3.2, 2.5], [6, 4.4, 2.9], [11, 3.8, 2.9], [15, 3.7, 3.5]], C.GLOVE, 0.6),
		_p(0, 14, 0, 11, 17, 11, C.CAMO_A),  # cuff
	]
	return {"size": Vector3i(11, 32, 11), "pivot": Vector3(5.5, 32, 5.5), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


static func _leg_f() -> Dictionary:
	var boxes := _shin_f_parts()
	boxes.append_array(_shifted(_thigh_f_parts(), 44))
	return {"size": Vector3i(14, 90, 18), "pivot": Vector3(7, 90, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": boxes}


static func _thigh_f() -> Dictionary:
	return {"size": Vector3i(14, 46, 18), "pivot": Vector3(7, 46, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": _thigh_f_parts()}


static func _shin_f() -> Dictionary:
	return {"size": Vector3i(14, 46, 18), "pivot": Vector3(7, 46, 10), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": _shin_f_parts()}


## Slimmer at the knee, still full at the top (its top 0.10 m is inside the hips).
static func _thigh_f_parts() -> Array:
	return [
		_loft(7, 10, [[0, 4.6, 5.2], [24, 6.2, 6.8], [36, 7.2, 7.3], [46, 7.6, 7.6]], C.CAMO, 0.55),
		_fb(2.5, 0, 3.5, 11.5, 4, 6, C.PAD),  # top of the knee pad
		_fp(0, 12, 6.5, 2.5, 26, 13.5, C.CAMO_C), _fp(11.5, 12, 6.5, 14, 26, 13.5, C.CAMO_C),  # cargo pockets
	]


static func _shin_f_parts() -> Array:
	return [
		_loft(7, 10, [[12, 3.7, 4.2], [32, 5.0, 5.4], [46, 4.6, 5.2]], C.CAMO, 0.55),
		_fb(2.5, 36, 3.5, 11.5, 46, 6, C.PAD),  # knee pad
		_loft(7, 9.5, [[0, 4.9, 8.2], [4, 4.9, 8.2], [10, 4.3, 6.2], [15, 4.0, 4.8]], C.BOOT, 0.35),
		_p(0, 0, 0, 14, 2, 18, C.SOLE),
	]


## Plate carriers by tier (0 light, 1 medium, 2 heavy), in 1 cm voxels built at 0.5 cm. The
## pivot is the carrier's mount point on the torso (GearRig mounts it at torso height 0.17 m),
## so the layout below is in carrier-local centimetres. Each plate the carrier takes sits in a
## bevelled fabric pocket: the pocket wraps the plate's edges and back, and a 2 cm lip runs
## round its face, leaving a window where the plate (the VoxelArmor, which GearRig colours as
## the carrier's fabric) shows. Plates centre at torso y 0.33 (front and back, at the
## carrier's plate_depth) and 0.28 (sides, at side_plate_x), as GearRig.armor_transform puts
## them. Details: PALS webbing rows across the panels, seams round the window, a loop panel
## for the name tape at the top of the front, a drag handle at the top of the back, padded
## shoulder pads that arch over the deltoids, and a cummerbund that wraps the waist.
## The cummerbund (and the light rig's straps, and the heavy rig's side pockets) fit the body
## that wears it, as a real one is cinched: its shape is the wearer's torso (`torso`, a torso
## spec; the male torso by default) plus CUMMERBUND_PAD of webbing and padding.
## `female`: fitted to a woman the way a real carrier sits on one ("vest_f:<tier>"): her torso
## shapes the cummerbund, the back panel sits FEMALE_CARRIER_BACK further in against her
## slimmer back, the heavy rig's side pockets sit in at her sides (carrier_side_inset), and the
## front panel is built apart ("vest_f_front:<tier>", `front`: only it) so GearRig can hang it
## from its top edge onto her chest (GearRig.carrier_fit).
static func _vest(tier: int, torso := {}, female := false, front := false) -> Dictionary:
	var body := torso if not torso.is_empty() else _torso_f() if female else _torso()
	var pad: float = CUMMERBUND_PAD[tier]
	var be: int = FEMALE_CARRIER_BACK if female else 0
	var depth: float = [14.0, 14.0, 16.5][tier]  # plate centre, front and back
	var below: int = [0, 0, 8][tier]       # the heavy carrier's groin flap hangs below the mount
	var half_x := 28
	var half_z := int(depth) + 5
	var size := Vector3i(half_x * 2, 42 + below, half_z * 2)
	var o := Vector3i(half_x, below, half_z)  # carrier-local (0, 0, 0) in voxels
	var boxes := []
	var front_boxes := [] if female else boxes  # the front panel's parts (a woman's: a model of their own)
	var at := func(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int, paint := false) -> void:
		boxes.append([Vector3i(x0, y0, z0) + o, Vector3i(x1, y1, z1) + o, colour, paint])
	var at_front := func(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, colour: int, paint := false) -> void:
		front_boxes.append([Vector3i(x0, y0, z0) + o, Vector3i(x1, y1, z1) + o, colour, paint])
	# Cummerbund round the torso from the mount up 22 cm, the body's own shape plus the pad (the
	# light rig has none, only straps round the back).
	if tier > 0:
		var rows: Array = []
		var hw := 0.0
		var hd := 0.0
		for y in range(0, CUMMERBUND_TOP_CM + 1, 2):
			var at_y := _torso_at(body, y)
			rows.append([o.y + y, at_y.x + pad, at_y.y + pad])
			hw = maxf(hw, at_y.x + pad)
			hd = maxf(hd, at_y.y + pad)
		boxes.append(_loft(o.x, o.z, rows, C.GEAR, CUMMERBUND_BEVEL))
		var w := ceili(hw)
		var d := ceili(hd)
		for y in [5, 9, 13, 17]:  # MOLLE rows on the sides
			at.call(-w, y, -d + 3, w, y + 1, d - 3, C.GEAR_DARK, true)
		at.call(-w, 0, -d, w, 2, d, C.GEAR_DARK, true)  # bottom binding
	else:
		var waist := _torso_at(body, 11.5)
		var w := ceili(waist.x) + 1
		var d := ceili(waist.y)
		at.call(-w, 10, 8, -w + 3, 13, d + 2, C.GEAR_DARK)
		at.call(w - 3, 10, 8, w, 13, d + 2, C.GEAR_DARK)
		at.call(-w, 10, d, w, 13, d + 2, C.GEAR_DARK)  # back strap
	# Plate pockets, front and (medium, heavy) back. The plate is 25 x 30 cm, y 1-31.
	var faces := [-1] if tier == 0 else [-1, 1]
	for f: int in faces:
		var put: Callable = at_front if f < 0 else at
		var list: Array = front_boxes if f < 0 else boxes
		var inner := int(depth) - 3
		var outer := int(depth) + 3
		var shift := 0 if f < 0 else -be
		var z0 := (-outer if f < 0 else inner) + shift
		var z1 := (-inner if f < 0 else outer) + shift
		# The pocket: bevelled upright edges, its top chamfered in.
		list.append(_loft(o.x, o.z + (z0 + z1) * 0.5, [[o.y, 14.0, 3.0], [o.y + 31, 14.0, 3.0], [o.y + POCKET_TOP_CM, 13.0, 2.0]], C.GEAR, 0.35))
		put.call(-13, 1, z0 + 1, 13, 32, z1 - 1, C.EMPTY)                 # the plate's room
		if f < 0 and female:
			# The panel conforms to her (the plate stays inside): padding behind the pocket down
			# to her chest and belly, so it lies on her with no gap under it, and cummerbund wings
			# from its edges back round her sides to the rear panel.
			var out := FEMALE_CARRIER_FRONT_OUT
			for y in range(0, 33, 2):
				var body_z := -roundi(_torso_front(body, y + 1.0) - out)  # her front, in the panel's frame
				if body_z > z1:
					put.call(-13, y, z1, 13, y + 2, body_z + 1, C.GEAR)
			for y in range(0, 23, 2):
				var side := _torso_at(body, y + 1.0)
				var w := ceili(side.x + pad)
				put.call(-w, y, z1, -12, y + 2, roundi(-side.y * 0.4 + out), C.GEAR)
				put.call(12, y, z1, w, y + 2, roundi(-side.y * 0.4 + out), C.GEAR)
		var face := z0 if f < 0 else z1 - 1
		put.call(-11, 3, face, 11, 30, face + 1, C.EMPTY)                 # window: the plate shows
		put.call(-14, 31, z0, 14, 33, z1, C.GEAR_DARK, true)              # top binding
		put.call(-12, 2, face, 12, 3, face + 1, C.GEAR_DARK, true)        # seams round the window
		put.call(-12, 2, face, -11, 30, face + 1, C.GEAR_DARK, true)
		put.call(11, 2, face, 12, 30, face + 1, C.GEAR_DARK, true)
		# PALS webbing across the panel, flush with the fabric (pouches thread through it).
		var top_row := 21 if f < 0 else 27
		for y in range(6, top_row + 1, 3):
			put.call(-11, y, face, 11, y + 1, face + 1, C.GEAR_DARK)
		if f < 0:
			put.call(-7, 24, face, 7, 29, face + 1, C.GEAR_DARK)          # loop panel: GearRig puts the name tape on it
		else:
			put.call(-4, 32, z1, 4, 36, z1 + 2, C.GEAR_DARK)              # drag handle
			put.call(-3, 33, z1, 3, 35, z1 + 2, C.EMPTY)
	# Padded shoulder pads, arching from the pockets' tops over the deltoids.
	for side: int in [-1, 1]:
		var arch: Array = SHOULDER_PAD_ARCH.map(func(k: Array) -> Array: return [o.y + k[0], 2.5, k[1] - be * 0.5])
		boxes.append(_loft(o.x + SHOULDER_PAD_X * side, o.z - be * 0.5, arch, C.GEAR, 0.6))
	if tier == 0:
		var back := ceili(_torso_at(body, 23.0).y)
		for side: int in [-1, 1]:  # straps cross the back
			var sx0 := 6 if side > 0 else -11
			at.call(sx0, 13, back, sx0 + 5, 33, back + 2, C.GEAR_DARK)
	# Heavy: side plate pockets (15 x 20 cm plates, y 1-21), collar and groin flap. Each pocket
	# reaches in to the cummerbund (a slimmer body: a deeper pocket wall), its plate at x 24.5
	# as GearRig puts it (side_plate_x); a woman's whole pocket sits carrier_side_inset further in.
	if tier == 2:
		var inside := mini(22, floori(_torso_at(body, 11.0).x + pad))
		var inset := 22 - inside if female else 0
		for side: int in [-1, 1]:
			var x0 := inside if side > 0 else -SIDE_POCKET_OUT_CM + inset
			var x1 := SIDE_POCKET_OUT_CM - inset if side > 0 else -inside
			at.call(x0, 0, -SIDE_POCKET_HALF_Z_CM, x1, SIDE_POCKET_TOP_CM, SIDE_POCKET_HALF_Z_CM, C.GEAR)
			var room := 23 - inset if side > 0 else -26 + inset
			at.call(room, 1, -8, room + 3, 22, 8, C.EMPTY)
			var face := 26 - inset if side > 0 else -27 + inset
			at.call(face, 3, -6, face + 1, 20, 6, C.EMPTY)
		at_front.call(-15, 33, -int(depth) - 2, 15, 39, -int(depth) + 3, C.GEAR_DARK)  # collar
		at_front.call(-8, -below, -int(depth) - 3, 8, 0, -int(depth) + 2, C.GEAR)       # groin flap
		at_front.call(-8, -below, -int(depth) - 3, 8, -below + 1, -int(depth) + 2, C.GEAR_DARK)
	return {"size": size, "pivot": Vector3(o), "voxel": BODY_VOXEL, "sub": BODY_SUB, "boxes": front_boxes if front else boxes}


## How far a woman's heavy carrier's side pockets (and their plates) sit in from the male fit, cm
## (0 for other tiers: they have none).
static func carrier_side_inset(tier: int, body: String) -> float:
	if tier != 2 or body != FEMALE:
		return 0.0
	return 22.0 - mini(22, floori(_torso_at(_torso_f(), 11.0).x + CUMMERBUND_PAD[tier]))


## A worn medium or heavy carrier's cummerbund (`tier` 1 or 2) round body type `body` at torso
## height `y` (metres over the hips, as the gear is placed): its half-width and half-depth in
## metres, the body's own shape there plus CUMMERBUND_PAD, centred on the spine. Its corners are
## cut by CUMMERBUND_BEVEL (GearRig.cummerbund_spot lays pouches on it).
static func cummerbund_size(tier: int, body: String, y: float) -> Vector2:
	var at := _torso_at(_torso_f() if body == FEMALE else _torso(), y * 100.0 - CARRIER_MOUNT_CM)
	return (at + Vector2.ONE * CUMMERBUND_PAD[clampi(tier, 0, 2)]) * 0.01


## How far body type `body`'s torso reaches in front of the spine (`back`: behind it) at torso
## height `y` (metres over the hips), in metres: the furthest of its lofts there (the trunk, a
## bust, her seat). `carried`: a woman's bust as a carrier holds it ("torso_fc").
static func torso_reach(body: String, y: float, back := false, carried := false) -> float:
	var torso := _torso_f(carried) if body == FEMALE else _torso()
	return _torso_front(torso, y * 100.0 - CARRIER_MOUNT_CM, back) * 0.01


## The top of body type `body`'s shoulders `x` metres out from the spine (metres over the
## hips): where the torso's main loft narrows in to that half-width above the chest, the line
## from the neck out over the shoulder. A pack's straps lie on it when no carrier is worn.
static func shoulder_top(body: String, x: float) -> float:
	var torso := _torso_f() if body == FEMALE else _torso()
	var keys: Array = (torso.boxes[0] as Dictionary).keys
	var pivot_y := float((torso.pivot as Vector3).y)
	var xc := absf(x) * 100.0
	for i in range(keys.size() - 1, 0, -1):
		var hi: Array = keys[i]
		var lo: Array = keys[i - 1]
		if float(hi[1]) >= xc:
			return (float(hi[0]) - pivot_y) * 0.01
		if float(lo[1]) >= xc:
			var t := (float(lo[1]) - xc) / maxf(float(lo[1]) - float(hi[1]), 0.001)
			return (lerpf(float(lo[0]), float(hi[0]), t) - pivot_y) * 0.01
	return (float(keys[0][0]) - pivot_y) * 0.01


## The top of a carrier's shoulder pad (SHOULDER_PAD_ARCH) from its back to its front, torso-local
## metres, at the pad's middle (x SHOULDER_PAD_X; mirror x for the left): [back end, back of the
## arch, top back, top front, front of the arch, front end]. A woman's pads reach
## FEMALE_CARRIER_BACK less far back (to her back panel).
static func shoulder_pad_line(female: bool) -> Array[Vector3]:
	var be := float(FEMALE_CARRIER_BACK) if female else 0.0
	var line: Array[Vector3] = []
	for i in [0, 1, 2]:
		var k: Array = SHOULDER_PAD_ARCH[i]
		line.append(Vector3(SHOULDER_PAD_X, CARRIER_MOUNT_CM + float(k[0]), float(k[1]) - be) * 0.01)
	for i in [2, 1, 0]:
		var k: Array = SHOULDER_PAD_ARCH[i]
		line.append(Vector3(SHOULDER_PAD_X, CARRIER_MOUNT_CM + float(k[0]), -float(k[1])) * 0.01)
	return line


## How far in front of the spine (cm) the torso spec `torso` reaches at carrier height `y` cm
## (`back`: behind it): the furthest of its lofts there (the trunk, a bust, a seat).
static func _torso_front(torso: Dictionary, y: float, back := false) -> float:
	var fy := y + CARRIER_MOUNT_CM + float((torso.pivot as Vector3).y)
	var pivot_z := float((torso.pivot as Vector3).z)
	var front := 0.0
	for part: Variant in torso.boxes:
		if not part is Dictionary:
			continue
		var keys: Array = part.keys
		for i in range(1, keys.size()):
			if fy >= float(keys[i - 1][0]) and fy <= float(keys[i][0]):
				var t := (fy - float(keys[i - 1][0])) / maxf(float(keys[i][0]) - float(keys[i - 1][0]), 0.001)
				var hd := lerpf(float(keys[i - 1][2]), float(keys[i][2]), t)
				if back:
					front = maxf(front, (part.centre as Vector2).y + hd - pivot_z)
				else:
					front = maxf(front, pivot_z - ((part.centre as Vector2).y - hd))
	return front


## The torso spec `torso`'s half-width and half-depth (cm, x and y) at carrier height `y` cm
## (above GearRig's mount, CARRIER_MOUNT_CM over the hips): its main loft at that height.
static func _torso_at(torso: Dictionary, y: float) -> Vector2:
	var keys: Array = (torso.boxes[0] as Dictionary).keys
	var fy := y + CARRIER_MOUNT_CM + float((torso.pivot as Vector3).y)
	for i in range(1, keys.size()):
		if fy <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var t := clampf((fy - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
			return Vector2(lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t))
	return Vector2(float(keys[-1][1]), float(keys[-1][2]))


## 0.34 x 0.44 m; depth in voxels grows with capacity. Outer face is +Z. A low-poly pack
## built at 0.5 cm: a bevelled main bag, a lid, a front pocket, straps.
static func _backpack(depth: int) -> Dictionary:
	var d := maxi(depth, 6)
	var body := (d - 1) * 0.5  # half-depth of the main bag; the front pocket fills the last voxel
	return {"size": Vector3i(17, 22, d), "sub": 4, "boxes": [
		_loft(8.5, body, [[0, 7.6, body - 0.4], [3, 8.5, body], [18, 8.5, body], [22, 7.4, body - 0.6]], C.PACK, 0.3),
		_p(0, 18, 0, 17, 22, d, C.PACK_DARK),                               # lid
		_loft(8.5, d - 1.6, [[3, 6.0, 1.4], [10.5, 6.4, 1.6]], C.PACK_DARK, 0.5),  # front pocket
		_fb(3.6, 0.5, d - 1.2, 4.4, 18, d - 0.6, C.PACK_DARK), _fb(12.6, 0.5, d - 1.2, 13.4, 18, d - 0.6, C.PACK_DARK),
		_fb(-0.1, 3, 2, 0.4, 3.6, d - 2, C.PACK_DARK), _fb(16.6, 3, 2, 17.1, 3.6, d - 2, C.PACK_DARK),
		_fb(-0.1, 7, 2, 0.4, 7.6, d - 2, C.PACK_DARK), _fb(16.6, 7, 2, 17.1, 7.6, d - 2, C.PACK_DARK),
		_fb(3, 4, 0, 5, 20, 0.6, C.PACK_DARK), _fb(12, 4, 0, 14, 20, 0.6, C.PACK_DARK),  # shoulder straps
	]}


## A box with fractional corners in the spec's voxels (built at its "sub" resolution).
static func _fb(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> Array:
	return [Vector3(x0, y0, z0), Vector3(x1, y1, z1), colour]


## A magazine's box (_fb, tagged MAG_TAG): a reload takes it out of the weapon (Captain,
## 2026-10-20: reloads), so first person draws the weapon WITHOUT_MAG and its magazine (MAG) as
## a part of its own that the hand carries. A belt-fed's ammo box counts.
static func _fbm(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> Array:
	return [Vector3(x0, y0, z0), Vector3(x1, y1, z1), colour, false, MAG_TAG]  # (box[3]: _p's paint-only flag)


## A box of a part that moves on its own in first person (_fb tagged `tag`): BELT_TAG goes with
## the magazine, BOLT_TAG slides back with the action (a charging handle, a bolt carrier seen
## through the port, a bolt-action's bolt, a pistol's slide), COVER_TAG hinges up (a belt-fed's
## feed cover). The whole model draws them in place; first person draws them apart (FIXED, BOLT,
## COVER) and Reloads.parts moves them on a reload's beats (weapon detail pass, 2026-10-20).
static func _fbt(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int, tag: String) -> Array:
	return [Vector3(x0, y0, z0), Vector3(x1, y1, z1), colour, false, tag]


## A box that only recolours voxels already there (_p with fractional corners).
static func _fbp(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> Array:
	return [Vector3(x0, y0, z0), Vector3(x1, y1, z1), colour, true]


const MAG_TAG := "mag"
const BELT_TAG := "mag_belt"  # a belt-fed's belt: it goes with the box, but not into the magazine's points
const BOLT_TAG := "bolt"
const COVER_TAG := "cover"
const COVER_OPTIC_TAG := "cover_optic"  # an optic on a feed cover's rail: it lifts with the cover
## Model name prefixes: just the magazine of a weapon model (and its belt), the weapon without
## it, just its sliding action or its feed cover, or the weapon with none of its moving parts.
const MAG := "mag|"
const WITHOUT_MAG := "nomag|"
const BOLT := "bolt|"
const COVER := "cover|"
const FIXED := "fixed|"


## A spec box's tag ("" for none).
static func _tag(b: Variant) -> String:
	return String(b[4]) if b is Array and b.size() > 4 else ""


## Whether box `b` belongs to model prefix `prefix` (MAG, WITHOUT_MAG, BOLT, COVER, FIXED).
static func _in_part(b: Variant, prefix: String) -> bool:
	var tag := _tag(b)
	match prefix:
		MAG: return tag.begins_with(MAG_TAG)
		WITHOUT_MAG: return not tag.begins_with(MAG_TAG)
		BOLT: return tag == BOLT_TAG
		COVER: return tag.begins_with(COVER_TAG)
	return tag == ""  # FIXED


## Whether weapon model `model` has a magazine part (tagged boxes) to take out.
static func has_magazine(model: String) -> bool:
	if not (model.begins_with("rifle") or model.begins_with("pistol")):
		return false
	return _spec(model).boxes.any(func(b: Variant) -> bool: return _tag(b) == MAG_TAG)


## The moving parts weapon model `model` has, of BOLT_TAG and COVER_TAG.
static func moving_parts(model: String) -> Array[String]:
	var out: Array[String] = []
	if not (model.begins_with("rifle") or model.begins_with("pistol")):
		return out
	for b: Variant in _spec(model).boxes:
		var tag := _tag(b)
		if (tag == BOLT_TAG or tag == COVER_TAG) and not out.has(tag):
			out.append(tag)
	return out


## Where a rifle's length share `f` sits in model `model` (voxels): the build's shares of its own
## length, moved back by a suppressor's length when it has one (_with_suppressor).
static func _z_at(model: String, f: float) -> float:
	var n := float(_spec(model).size.z)
	if not _rifle_suppressed(model):
		return n * f
	var n0 := float(_spec(model.substr(0, model.rfind(":") + 1)).size.z)
	return n0 * f + n0 * SUPPRESSOR_FRAC


## The points a reload's hands go to on weapon model `model`, in metres from the instance pivot
## (like hand_points): "mag" (the magazine's left side, halfway down: where the support hand
## takes it), "well" (the top of the magazine, or of an internal one), "catch" (a bolt catch or
## release button), "bolt" (a cocking or charging handle, a bolt handle, a pistol's slide) and
## "cover" (a belt-fed's feed cover, near its back end where it lifts). Reloads names them.
static func reload_points(model: String) -> Dictionary:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	var z := func(f: float) -> float: return _z_at(model, f)
	var out := {}
	var mag := _part_box(spec, MAG_TAG)
	if not mag.is_empty():
		var lo: Vector3 = mag[0]
		var hi: Vector3 = mag[1]
		out["mag"] = Vector3(lo.x - 0.3, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
		out["well"] = Vector3((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5)
	var b := _below(model)
	if model.get_slice(":", 0) == "pistol":
		out.merge({"bolt": Vector3(1.0, 6.8, 9.5), "catch": Vector3(0.0, 4.25, 5.5)}, true)  # the slide's back, the slide stop
	elif model.begins_with("rifle"):
		if mag.is_empty():  # an internal magazine: its top, through the open action
			out["mag"] = Vector3(0.6, 7.5 + b, z.call(0.62))
			out["well"] = Vector3(1.5, 9.2 + b, z.call(0.62))
		var cover := _part_box(spec, COVER_TAG)
		if not cover.is_empty():
			var lo: Vector3 = cover[0]
			var hi: Vector3 = cover[1]
			out["cover"] = Vector3((lo.x + hi.x) * 0.5, hi.y + 0.3, lerpf(lo.z, hi.z, 0.75))
		match _rifle_style(model):
			"ak": out["bolt"] = Vector3(2.75, 8.4 + b, z.call(0.5625))      # the charging handle's knob, right
			"bullpup":
				out["bolt"] = Vector3(2.5, 8.5 + b, z.call(0.5))           # the cocking handle, right
				out["catch"] = Vector3(0.5, 7.4 + b, z.call(0.76))         # the bolt release plunger, upper left
			"pk": out["bolt"] = Vector3(2.75, 7.25 + b, z.call(0.455))     # the charging handles: right, forward
			"m240": out["bolt"] = Vector3(2.75, 7.75 + b, z.call(0.455))
			"m249": out["bolt"] = Vector3(2.75, 7.5 + b, z.call(0.435))
			"mosin": out["bolt"] = Vector3(2.75, 9.0 + b, z.call(0.735))   # the bolt knob
			"chassis_bolt": out["bolt"] = Vector3(2.75, 8.5 + b, z.call(0.75))
			_:  # the AR family: the bolt catch paddle on the left behind the well, the T-handle at the back
				out["catch"] = Vector3(0.5, 6.5 + b, z.call(0.5875))
				out["bolt"] = Vector3(1.5, 9.3 + b, z.call(0.765))
	for k: String in out:
		out[k] = (out[k] - centre) * VOXEL_SIZE
	return out


## How weapon model `model`'s moving parts move (metres and radians, from the instance pivot):
## "travel" (how far its action slides back, open), "lift" (a bolt-action's handle turned up),
## "axis" (the bore, that it turns round), "hinge" (the feed cover's front edge, that it turns
## on) and "open" (the cover's angle, open). Reloads.parts says when, share by share.
static func part_motion(model: String) -> Dictionary:
	var spec := _spec(model)
	var centre := Vector3(spec.size) * 0.5
	var out := {"travel": 0.06, "lift": 0.0, "axis": (Vector3(1.5, 8.5 + _below(model), 0.0) - centre) * VOXEL_SIZE, "open": 1.25}
	if model.begins_with("pistol"):
		out.travel = 0.025  # a slide locked back
		return out
	match _rifle_style(model):
		"ak": out.travel = 0.1
		"bullpup": out.travel = 0.08
		"pk", "m240", "m249": out.travel = 0.12
		"mosin", "chassis_bolt":
			out.travel = 0.08
			out.lift = 1.4
	var cover := _part_box(spec, COVER_TAG)
	if not cover.is_empty():
		var lo: Vector3 = cover[0]
		var hi: Vector3 = cover[1]
		out["hinge"] = (Vector3((lo.x + hi.x) * 0.5, lo.y, lo.z) - centre) * VOXEL_SIZE
	return out


## Boxes `boxes` (an optic) riding a feed cover's rail (COVER_OPTIC_TAG): they lift with it.
static func _on_cover(boxes: Array) -> Array:
	return boxes.map(func(b: Array) -> Array: return [b[0], b[1], b[2], false, COVER_OPTIC_TAG])


## The bounds [lo, hi] (voxels) of `spec`'s boxes tagged `tag`, or [] for none.
static func _part_box(spec: Dictionary, tag: String) -> Array:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for b: Variant in spec.boxes:
		if _tag(b) == tag:
			lo = lo.min(Vector3(b[0]).min(Vector3(b[1])))
			hi = hi.max(Vector3(b[0]).max(Vector3(b[1])))
	return [lo, hi] if lo.x < INF else []


## Voxels of frame every rifle (but the WG-50) has below y = 0 of the frame it's written in
## (weapon detail pass, 2026-10-20: real magazines hang 12 to 17 cm under the well and didn't
## fit; an AR's was 9 cm, an AK's 10). The builders write y down to -RIFLE_BELOW; _spec lifts
## the boxes into the frame, and every point read off a rifle (hand_points, sight_point,
## butt_point, reload_points, part_motion) adds it to the heights it names.
const RIFLE_BELOW := 3.0


## RIFLE_BELOW for a rifle model that has it (part prefixes aside), else 0.
static func _below(model: String) -> float:
	var plain := model.get_slice("|", model.count("|"))
	return RIFLE_BELOW if plain.begins_with("rifle") and _rifle_style(plain) != "walker" else 0.0


## `spec` with `k` voxels more frame below: every box lifted by `k`.
static func _lowered(spec: Dictionary, k: float) -> Dictionary:
	var boxes: Array = []
	for b: Array in spec.boxes:
		boxes.append([b[0] + Vector3(0, k, 0), b[1] + Vector3(0, k, 0)] + b.slice(2))
	var size: Vector3i = spec.size
	size.y += ceili(k)
	return {"size": size, "sub": spec.get("sub", 1), "boxes": boxes}


## Height (voxels) of a rifle's line of sight: the middle of its optic, or its irons'
## aperture and front post's top.
const OPTIC_AXIS_Y := 11.8
## A rifle with no optic: its back-up irons.
const IRONS := "irons"
## How far (voxels) behind the irons' rear aperture the eye sits when aiming (about 9 cm).
const IRON_EYE_RELIEF := 4.5
## Rail top (voxels), where an optic's mount sits.
const RAIL_Y := 9.95


## The sight kind a rifle model names ("rifle:42:dot"), "dot" when it names none.
static func _rifle_art(model: String) -> String:
	var parts := model.split(":")
	return parts[2] if parts.size() > 2 and parts[2] != "" else "dot"


## The silhouette a rifle model names ("rifle:42:irons:ak"): "" for the AR-15 family.
static func _rifle_style(model: String) -> String:
	var parts := model.split(":")
	return parts[3] if parts.size() > 3 else ""


## True for a rifle model with a suppressor on its muzzle ("rifle:42:irons:ak:sup").
static func _rifle_suppressed(model: String) -> bool:
	var parts := model.split(":")
	return parts.size() > 4 and parts[4] == "sup"


## Where (voxels along a rifle of `n`) the back end of sight `art` sits: compact sights over
## the receiver's front, magnified tubes further back (eye relief), irons' rear aperture at
## the rail's end.
static func sight_back(art: String, n: float) -> float:
	match art:
		IRONS:
			return n * 0.715
		"lpvo", "scope", "scope_fixed", "scope_long":
			return n * 0.68
	return n * 0.64


## A red dot's length (voxels): 6.5 cm, a micro red dot's (Aimpoint T-2 class, about 6 cm).
## Captain, 2026-10-14: the 9 cm box it was, with a 3 x 4 cm window in a 4 x 5 cm housing, was
## longer than the holographic sight and filled the right of the first-person view.
const RED_DOT_LENGTH := 3.25


## An optic's length (voxels), front to back.
static func optic_length(art: String) -> float:
	match art:
		"holo": return 3.6
		"lpvo": return 13.0
		"prism": return 7.0
		"scope": return 17.0
		"scope_fixed": return 15.0
		"scope_long": return 19.0
	return RED_DOT_LENGTH


## The boxes of optic `art` in a rifle's frame, its back end at z = `back` (voxels): on the rail
## (RAIL_Y), its line of sight at OPTIC_AXIS_Y. Proposed shapes (Captain, P0362): a red dot's
## open tube (a micro red dot's size, 2026-10-14), a holographic window (its 3x magnifier
## flipped down beside the rail), an LPVO's slim tube, a prism's squat body, and DMR scopes with
## their objective bells and turrets.
static func optic_boxes(art: String, back: float) -> Array:
	var front := back - optic_length(art)
	match art:
		"holo":
			return [
				_fb(0.7, RAIL_Y, front - 0.4, 2.3, 10.6, back, C.GUN),              # base and battery
				_fb(0.4, 10.6, front, 2.6, 10.8, back, C.GUN),                      # window: floor
				_fb(0.4, 12.8, front, 2.6, 13.0, back, C.GUN),                      # hood
				_fb(0.4, 10.8, front, 0.65, 12.8, back, C.GUN),                     # sides
				_fb(2.35, 10.8, front, 2.6, 12.8, back, C.GUN),
				_fb(1.0, RAIL_Y, back + 0.4, 2.0, 10.3, back + 1.6, C.GUN_LIGHT),   # the magnifier's mount (it flips aside)
			]
		"lpvo", "scope", "scope_fixed", "scope_long":
			var r := 0.65 if art == "lpvo" else 0.7  # the tube's half-width
			var bell: float = {"lpvo": 0.9, "scope": 1.05, "scope_fixed": 0.95, "scope_long": 1.2}[art]
			var bell_len := 2.5 if art == "lpvo" else 4.0
			var y := OPTIC_AXIS_Y
			var mid := (front + back) * 0.5
			return [
				_fb(1.5 - r, y - r, front, 1.5 + r, y + r, back, C.GUN),                          # tube
				_fb(1.5 - bell, y - bell, front, 1.5 + bell, minf(y + bell, 13.0), front + bell_len, C.GUN),  # objective bell
				_fb(0.6, y - 0.9, back - 3.0, 2.4, y + 0.9, back, C.GUN),                          # eyepiece
				_fb(1.5 - r + 0.1, y - r + 0.1, front - 0.25, 1.5 + r - 0.1, y + r - 0.1, front, C.LENS),
				_fb(1.1, y + r, mid - 0.6, 1.9, 13.0, mid + 0.6, C.GUN_LIGHT),                   # turrets
				_fb(1.5 + r, y - 0.4, mid - 0.6, minf(1.5 + r + 0.45, 3.0), y + 0.4, mid + 0.6, C.GUN_LIGHT),
				_fb(1.05, RAIL_Y, front + bell_len + 0.5, 1.95, y - r, front + bell_len + 1.5, C.GUN),  # rings
				_fb(1.05, RAIL_Y, back - 4.5, 1.95, y - r, back - 3.5, C.GUN),
			]
		"prism":
			return [
				_fb(0.9, RAIL_Y, front + 1.0, 2.1, 10.4, back - 1.0, C.GUN),        # mount
				_fb(0.6, 10.4, front + 1.0, 2.4, 12.75, back, C.GUN),               # body
				_fb(0.5, 10.5, front, 2.5, 13.0, front + 1.5, C.GUN),               # objective hood
				_fb(0.75, 10.75, front - 0.25, 2.25, 12.75, front, C.LENS),
				_fb(1.25, 12.75, front + 2.0, 1.75, 13.0, back - 1.5, C.GUN_LIGHT),  # fibre on top
			]
	# Red dot: a micro red dot (Captain, 2026-10-14: the size of an Aimpoint T-2, not a box): an
	# open tube you look through when aimed, 3 cm across round a clear 2 cm window on the line of
	# sight, RED_DOT_LENGTH long: lens ends with their edges cut (an octagon in 0.5 cm voxels)
	# either side of a square body carrying the elevation and windage caps and the brightness
	# knob, on a slim riser and a rail clamp. 5.5 cm from the rail to the top cap, 4 cm across
	# the knobs.
	var x := 1.5
	var y := 11.75  # the line of sight (OPTIC_AXIS_Y) on the 0.5 cm build grid
	var mid := (front + back) * 0.5
	return [
		_fb(0.8, RAIL_Y, front + 0.5, 2.2, 10.5, back - 0.5, C.GUN),                     # rail clamp
		_fb(0.55, RAIL_Y, mid - 0.5, 0.8, 10.25, mid + 0.5, C.GUN_LIGHT),               # its lever
		_fb(1.05, 10.5, front + 0.75, 1.95, y - 0.5, back - 0.75, C.GUN),                # riser
		_fb(x - 0.75, y - 0.5, front, x + 0.75, y + 0.5, back, C.GUN),                   # tube
		_fb(x - 0.5, y - 0.75, front, x + 0.5, y + 0.75, back, C.GUN),
		_fb(x - 0.75, y - 0.75, mid - 0.75, x + 0.75, y + 0.75, mid + 0.75, C.GUN),      # body
		_fb(x - 0.25, y + 0.75, mid - 0.25, x + 0.25, y + 1.0, mid + 0.25, C.GUN_LIGHT), # elevation cap
		_fb(x + 0.75, y - 0.25, mid - 0.25, x + 1.0, y + 0.25, mid + 0.25, C.GUN_LIGHT), # windage cap
		_fb(x - 1.0, y - 0.25, mid - 0.5, x - 0.75, y + 0.25, mid + 0.5, C.GUN_LIGHT),   # brightness knob
		_fb(x - 0.5, y - 0.5, front, x + 0.5, y + 0.5, back, C.EMPTY),                   # the window, clear through
	]


## A rifle's back-up irons, up when it has no optic: a rear aperture at the rail's end and a
## front post on the gas block, the post's top level with the aperture's middle. (Parts are
## built in 0.5 cm voxels, a quarter of the spec's: nothing thinner than 0.25 survives.)
static func iron_boxes(n: float) -> Array:
	var rear := sight_back(IRONS, n)
	var front := n * 0.13
	return [
		# Captain, 2026-10-16 (screenshot: the rear sight a big block, the hole small and the post low):
		# a low base, a thin stalk, and a thin ghost ring round a wide hole centred on OPTIC_AXIS_Y;
		# the eye sits IRON_EYE_RELIEF behind it (sight_point), so it frames the post instead.
		# Captain, 2026-10-16 (M4 screenshot): an AR-style peep, a chunky housing round a small hole
		# centred on the sight line, sitting on a solid base (no thin stalk in the way).
		_fb(1.0, RAIL_Y, rear - 0.5, 2.0, 11.25, rear + 0.5, C.GUN),                # rear: base, up to the hole (all on the 0.25 grid)
		_fb(0.75, 11.25, rear - 0.25, 1.25, 12.75, rear + 0.25, C.GUN),              # housing: left
		_fb(1.75, 11.25, rear - 0.25, 2.25, 12.75, rear + 0.25, C.GUN),              # right
		_fb(0.75, 12.25, rear - 0.25, 2.25, 12.75, rear + 0.25, C.GUN),              # top (hole 1.25-1.75 x 11.25-12.25)
		_fb(1.25, 9.75, front, 1.75, OPTIC_AXIS_Y, front + 0.5, C.GUN),             # front post (centred on the grid)
		_fb(0.75, 9.75, front, 1.0, 12.0, front + 0.5, C.GUN),                      # and its ears
		_fb(2.0, 9.75, front, 2.25, 12.0, front + 0.5, C.GUN),
		_fb(0.75, 9.75, front, 2.25, 10.0, front + 0.5, C.GUN),                     # the ears' foot, joining them to the post
	]


## The WG-50 Walker Gun (a heavy exo's own weapon, ExoMech; learned from the Captain's reference
## art, 2026-10-17: a rotary gun held low on the right arm): six .50 cal barrels round a spindle
## in a front and a middle clamp, a drive motor housing behind them, a deep slab receiver with a
## belt box hung on its left and a feed chute up into it, a vertical foregrip and a pistol grip
## under it, and a stubby buffer stock. Wider than a rifle: its centre line
## is WALKER_AXIS_X (hand_points, sight_point and butt_point follow it), its irons the rifles'
## moved over to it.
const WALKER_AXIS_X := 3.5


static func _rifle_walker(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 40)
	var f := func(t: float) -> float: return n * t
	var shift := WALKER_AXIS_X - 1.5
	var sight: Array = (iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))).map(
		func(b: Array) -> Array: return [b[0] + Vector3(shift, 0, 0), b[1] + Vector3(shift, 0, 0)] + b.slice(2))
	var boxes := sight + [
		_fb(3.2, 8.0, 0.5, 3.8, 8.6, f.call(0.42), C.GUN_LIGHT),                # spindle, on into the motor
		_fb(1.6, 6.4, 1.0, 5.4, 10.2, 2.0, C.GUN),                              # front clamp
		_fb(1.6, 6.4, f.call(0.2), 5.4, 10.2, f.call(0.2) + 1.0, C.GUN),        # middle clamp
		_fb(1.5, 6.2, f.call(0.32), 5.5, 10.4, f.call(0.42), C.GUN_LIGHT),      # drive motor housing
		_fb(1.0, 3.5, f.call(0.38), 6.0, 10.5, f.call(0.82), C.GUN),            # slab receiver
		_fb(0.8, 5.0, f.call(0.45), 1.0, 9.5, f.call(0.75), C.GUN_LIGHT),       # its side plate
		_fb(2.0, 10.5, f.call(0.42), 5.0, 11.0, f.call(0.7), C.GUN_LIGHT),      # top cover
		_fb(0.0, 0.5, f.call(0.42), 1.6, 6.0, f.call(0.6), C.GUN_LIGHT),       # belt box, on the left
		_fb(0.0, 0.5, f.call(0.42), 1.6, 1.0, f.call(0.6), C.GUN),
		_fb(0.3, 6.0, f.call(0.46), 1.2, 8.5, f.call(0.5), C.GUN),              # feed chute, up into the receiver
		_fb(2.9, 0.5, n - 28.5, 4.1, 3.5, n - 25.5, C.GUN),                     # vertical foregrip
		_fb(3.0, 2.3, f.call(0.75), 4.0, 3.5, f.call(0.79), C.GUN),             # trigger guard
		_fb(2.9, 0.0, f.call(0.79), 4.1, 3.5, f.call(0.83), C.GUN),             # pistol grip
		_fb(2.0, 4.0, f.call(0.82), 5.0, 9.0, n - 1.0, C.GUN_LIGHT),            # buffer stock
		_fb(1.8, 3.5, n - 1.0, 5.2, 10.0, n, C.GUN),                            # butt pad
	]
	for k in 6:  # the six barrels round the spindle
		var a := k * TAU / 6.0
		var c := Vector2(WALKER_AXIS_X + cos(a) * 1.35, 8.3 + sin(a) * 1.35)
		boxes.append(_fb(c.x - 0.35, c.y - 0.35, 0, c.x + 0.35, c.y + 0.35, f.call(0.33), C.GUN))
	return {"size": Vector3i(7, 13, n), "sub": 4, "boxes": boxes}


## A rifle model's centre line across (voxels): the WG-50's is wider than the rest.
static func _axis_x(model: String) -> float:
	return WALKER_AXIS_X if _rifle_style(model) == "walker" else 1.5


## An AK's irons (Captain, 2026-10-16, with a photo: "you should be able to see the front and
## rear sights"): the tangent leaf on the front of the receiver, AK_REAR_FORWARD ahead of the
## eye's usual aperture spot, a wide flat plate with a U-notch whose top is the sight line; and
## out at the muzzle a post inside a hood, its tip level with the notch's top.
const AK_REAR_FORWARD := 13.0  # mid-receiver like the real leaf (smaller in view; was 6)
## The front post is about this many times further from the eye than the notch: that much wider.
const AK_POST_SCALE := 1.9  # with the leaf at AK_REAR_FORWARD


static func ak_iron_boxes(n: float) -> Array:
	var rear := sight_back(IRONS, n) - AK_REAR_FORWARD
	var front := n * 0.06
	var top := OPTIC_AXIS_Y
	return [
		_fb(1.0, 9.0, rear - 1.0, 2.0, 10.75, rear + 1.0, C.GUN),                     # the leaf's base, sunk in the receiver (2026-10-16: it floated)
		# Captain, 2026-10-16 (PKM screenshot; "the center post is supposed to be as wide as the gap
		# and your sights will half cover the point you're aiming at"): seen from the eye the post
		# fills the notch (the post is about AK_POST_SCALE times further off, so that much wider),
		# its tip on the sight line (OPTIC_AXIS_Y: the aim point sits on it, the post below), a
		# hood round it and a sight block down to the barrel so nothing floats.
		# Every edge on the 0.25 build grid and symmetric round x = 1.5 (Captain, 2026-10-16: "need
		# centering on the front post": off-grid edges rounded lopsided).
		_fb(0.75, 10.75, rear - 0.25, 1.25, top, rear + 0.25, C.GUN),                  # leaf: left of the notch
		_fb(1.75, 10.75, rear - 0.25, 2.25, top, rear + 0.25, C.GUN),                  # right of the notch
		_fb(1.25, 10.75, rear - 0.25, 1.75, top - 0.5, rear + 0.25, C.GUN),            # under the notch (a U 0.5 wide)
		_fb(1.0, 8.0, front, 2.0, 10.25, front + 0.5, C.GUN),                          # front sight block, from the barrel
		# Captain, 2026-10-17 ("ak irons need a pass... function is poor, especially past 50
		# meters"): the post was 1 cm wide, about 17 mrad from the eye (wider than a standing man
		# from 40 m out), so at range it hid the target. Now 0.5 cm (the thinnest that stays centred
		# on the 0.25 grid): about 8.6 mrad, a thin post inside the notch with light either side.
		_fb(1.25, 10.25, front, 1.75, top, front + 0.5, C.GUN),                        # front post
		_fb(0.75, 10.25, front, 2.25, 10.5, front + 0.5, C.GUN),                       # the hood's base, on the block (holds its sides)
		_fb(0.75, 10.25, front, 1.0, top + 0.5, front + 0.5, C.GUN),                   # hood: sides
		_fb(2.0, 10.25, front, 2.25, top + 0.5, front + 0.5, C.GUN),
		_fb(0.75, top + 0.25, front, 2.25, top + 0.5, front + 0.5, C.GUN),             # hood: top
	]


## A rifle with no rail of its own (AK family, Mosin): optic `art` sits on a mount from the
## receiver's top (`from_y`) up to RAIL_Y, under its whole length, so it never floats over the
## gun (2026-10-16). None for irons.
static func optic_mount(art: String, n: float, from_y: float) -> Array:
	if art == IRONS:
		return []
	var back := sight_back(art, n)
	return [_fb(0.9, from_y, back - optic_length(art), 2.1, RAIL_Y, back + 2.0, C.GUN)]


## An optic on its own (lying loose, in the inventory): the same boxes as on a rifle, its
## mount's foot at y = 0 and its front at z = 0.
static func _optic_model(art: String) -> Dictionary:
	var length := optic_length(art)
	var tail := 2.0 if art == "holo" else 0.0  # the magnifier's mount behind
	var boxes := []
	for b: Array in optic_boxes(art, length + 0.5):
		boxes.append([b[0] - Vector3(0, RAIL_Y, 0), b[1] - Vector3(0, RAIL_Y, 0), b[2]])
	return {"size": Vector3i(3, 4, ceili(length + 1.0 + tail)), "sub": 4, "boxes": boxes}


## The AR family's controls (the M4, M27, C8 and HK416 share the receiver), learned from the
## real rifle (weapon detail pass, 2026-10-20: the reloads work them): the ejection port on the
## upper's right with the bolt carrier in it (BOLT_TAG: an empty magazine leaves it locked back
## until the catch is slapped) and its dust cover swung open below, the brass deflector and the
## forward assist behind it, the T charging handle out of the upper's back end, the bolt catch
## paddle on the left behind the magazine well, the magazine release on the right and the
## safety over the grip. Drawn after the receivers (the port is cut into them).
static func _ar_controls(n: float) -> Array:
	var f := func(t: float) -> float: return n * t
	return [
		_fb(1.75, 8.0, f.call(0.56), 2.25, 8.75, f.call(0.625), C.EMPTY),                  # ejection port, right side of the upper
		_fbt(1.75, 8.0, f.call(0.56), 2.0, 8.75, f.call(0.625), C.GUN_LIGHT, BOLT_TAG),    # the bolt carrier in it, a step in
		_fb(2.25, 7.25, f.call(0.56), 2.5, 8.0, f.call(0.625), C.GUN),                     # dust cover, swung open below the port
		_fb(2.25, 8.0, f.call(0.625), 2.5, 9.0, f.call(0.65), C.GUN),                      # brass deflector, behind the port
		_fb(2.25, 7.75, f.call(0.65), 2.75, 8.5, f.call(0.69), C.GUN),                     # forward assist housing
		_fb(2.5, 7.85, f.call(0.69), 2.75, 8.4, f.call(0.715), C.GUN_LIGHT),               # and its plunger, pointing back
		_fb(1.0, 9.0, f.call(0.74), 2.0, 9.5, f.call(0.755), C.GUN),                       # T charging handle: its shaft, out of the upper's back
		_fb(0.5, 9.0, f.call(0.755), 2.5, 9.5, f.call(0.775), C.GUN_LIGHT),                # its T, wider than the receiver
		_fb(0.5, 6.0, f.call(0.575), 0.75, 6.9, f.call(0.6), C.GUN_LIGHT),                 # bolt catch paddle, left, behind the well
		_fb(2.25, 6.0, f.call(0.585), 2.5, 6.5, f.call(0.61), C.GUN_LIGHT),                # magazine release button, right, ahead of the trigger
		_fb(0.5, 6.25, f.call(0.665), 0.75, 6.75, f.call(0.69), C.GUN_LIGHT),              # safety selector, left, over the grip
	]


## Rifle of `length` voxels, muzzle at z = 0, in a 2 cm frame built at 0.5 cm: muzzle
## device, barrel, railed handguard, upper and lower receiver, curved magazine, angled pistol
## grip, buffer tube and stock, and its sight `art` (optic_boxes; IRONS: iron_boxes).
## hand_points and sight_point read this frame (pistol grip at 0.68, handguard underside at
## 0.38, the sight's back: sight_back).
static func _rifle(length: int, art := "dot") -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.25, 8.25, 0, 1.75, 8.75, f.call(0.3), C.GUN),                     # barrel
		_fb(1.05, 7.95, 0, 1.95, 9.05, 1.5, C.GUN),                             # muzzle device
		_fb(1.2, 8.75, f.call(0.13), 1.8, 9.9, f.call(0.15), C.GUN),            # gas block
		_fb(0.6, 7.0, f.call(0.15), 2.4, 9.6, f.call(0.45), C.GUN_LIGHT),       # handguard
		_fb(0.9, 9.6, f.call(0.15), 2.1, 9.95, f.call(0.74), C.GUN),            # top rail
		_fb(0.6, 7.0, f.call(0.15), 0.85, 9.6, f.call(0.45), C.GUN),            # side rails
		_fb(2.15, 7.0, f.call(0.15), 2.4, 9.6, f.call(0.45), C.GUN),
		_fb(0.7, 7.0, f.call(0.45), 2.3, 9.6, f.call(0.74), C.GUN),             # upper receiver
		_fb(0.75, 5.6, f.call(0.47), 2.25, 7.0, f.call(0.72), C.GUN),           # lower receiver
		_fb(0.75, 3.75, f.call(0.47), 2.25, 5.6, f.call(0.6), C.GUN),           # its magazine well, 6 cm deep
		_fb(1.0, 3.75, f.call(0.5), 2.0, 6.75, f.call(0.575), C.EMPTY),         # the well itself
		_fbm(0.9, 3.75, f.call(0.5), 2.1, 6.75, f.call(0.575), C.GUN_LIGHT),     # 30-round magazine: up in the well,
		_fbm(0.9, 2.25, f.call(0.49), 2.1, 3.75, f.call(0.565), C.GUN_LIGHT),    # then 12.5 cm under it, curving forward
		_fbm(0.9, 0.75, f.call(0.475), 2.1, 2.25, f.call(0.55), C.GUN_LIGHT),
		_fbm(0.9, -0.75, f.call(0.455), 2.1, 0.75, f.call(0.535), C.GUN_LIGHT),
		_fbm(0.9, -2.0, f.call(0.435), 2.1, -0.75, f.call(0.52), C.GUN_LIGHT),
		_fbm(0.85, -2.5, f.call(0.43), 2.15, -2.0, f.call(0.52), C.GUN),        # floorplate
		_fb(1.25, 4.6, f.call(0.6), 1.75, 5.0, f.call(0.66), C.GUN),            # trigger guard
		_fb(0.9, 4.4, f.call(0.66), 2.1, 5.6, f.call(0.71), C.GUN),             # pistol grip, raked back
		_fb(0.9, 3.0, f.call(0.67), 2.1, 4.4, f.call(0.72), C.GUN),
		_fb(0.9, 1.6, f.call(0.68), 2.1, 3.0, f.call(0.735), C.GUN),
		_fb(0.9, 0.6, f.call(0.69), 2.1, 1.6, f.call(0.745), C.GUN),            # its bottom: 10 cm of grip, like an A2's
		_fb(1.1, 7.6, f.call(0.74), 1.9, 8.8, f.call(0.82), C.GUN_LIGHT),       # buffer tube
		_fb(0.8, 6.0, f.call(0.8), 2.2, 9.4, n, C.GUN_LIGHT),                   # stock
		_fb(0.95, 9.4, f.call(0.82), 2.05, 9.8, f.call(0.95), C.GUN_LIGHT),     # cheek rest
		_fb(0.8, 5.6, n - 0.5, 2.2, 9.8, n, C.GUN),                             # butt pad
	] + _ar_controls(n)}


## An AK-pattern rifle (AKM, AK-74, RPK): slab receiver with a top cover, gas tube over a wooden
## handguard, a banana magazine, a straight wooden stock. Iron sights only. Same size, grip and
## shoulder points as the AR model (hand_points, butt_point use the box size, not the shape).
static func _rifle_ak(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := ak_iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n)) + optic_mount(art, n, 9.0)
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.25, 8.25, 0, 1.75, 8.75, f.call(0.3), C.GUN),                     # barrel
		_fb(1.0, 7.9, 0, 2.0, 9.1, 1.5, C.GUN),                                 # slant muzzle brake
		_fb(1.2, 8.75, f.call(0.13), 1.8, 9.9, f.call(0.15), C.GUN),            # gas block and front sight base
		_fb(1.2, 9.0, f.call(0.15), 1.8, 9.5, f.call(0.46), C.GUN),             # gas tube
		_fb(0.55, 6.6, f.call(0.16), 2.45, 8.9, f.call(0.46), C.WOOD),          # wooden handguard
		_fb(0.55, 6.6, f.call(0.16), 2.45, 7.0, f.call(0.46), C.WOOD_DARK),
		_fb(0.7, 7.0, f.call(0.46), 2.3, 9.6, f.call(0.76), C.GUN),             # receiver and dust cover
		_fb(0.75, 5.8, f.call(0.48), 2.25, 7.0, f.call(0.72), C.GUN),
		_fb(1.0, 5.8, f.call(0.51), 2.0, 6.6, f.call(0.6), C.EMPTY),            # the well: hooked in at its front, rocked back to the catch
		_fbm(0.9, 4.2, f.call(0.505), 2.1, 6.6, f.call(0.6), C.GUN_LIGHT),       # magazine: up in the well, then a deep banana
		_fbm(0.9, 2.6, f.call(0.485), 2.1, 4.2, f.call(0.585), C.GUN_LIGHT),     # 17 cm under the receiver, curving well forward
		_fbm(0.9, 1.0, f.call(0.46), 2.1, 2.6, f.call(0.565), C.GUN_LIGHT),
		_fbm(0.9, -0.6, f.call(0.43), 2.1, 1.0, f.call(0.54), C.GUN_LIGHT),
		_fbm(0.9, -2.0, f.call(0.4), 2.1, -0.6, f.call(0.515), C.GUN_LIGHT),
		_fbm(0.85, -2.75, f.call(0.385), 2.15, -2.0, f.call(0.505), C.GUN),      # floorplate
		_fb(1.25, 4.6, f.call(0.62), 1.75, 5.0, f.call(0.68), C.GUN),           # trigger guard
		_fb(0.9, 4.4, f.call(0.68), 2.1, 5.8, f.call(0.73), C.WOOD),            # pistol grip, raked back
		_fb(0.9, 3.0, f.call(0.69), 2.1, 4.4, f.call(0.74), C.WOOD),
		_fb(0.9, 1.6, f.call(0.7), 2.1, 3.0, f.call(0.75), C.WOOD_DARK),
		_fb(0.8, 5.8, f.call(0.76), 2.2, 8.6, n, C.WOOD),                       # straight stock
		_fb(0.8, 5.0, f.call(0.9), 2.2, 6.0, n, C.WOOD_DARK),
		_fb(0.8, 4.8, n - 0.5, 2.2, 8.8, n, C.GUN),                             # butt plate
		# Weapon detail pass (2026-10-20: the reloads work these): the ejection port under the dust
		# cover's edge on the right, the carrier in it and its charging handle ahead of it (BOLT_TAG:
		# they rack back together), the long safety lever over the handle's slot, the magazine
		# release paddle behind the magazine and the dust cover's rear button.
		_fb(1.75, 8.0, f.call(0.57), 2.25, 9.0, f.call(0.68), C.EMPTY),                   # ejection port, right
		_fbt(1.75, 8.0, f.call(0.57), 2.0, 9.0, f.call(0.62), C.GUN_LIGHT, BOLT_TAG),     # the bolt carrier's front in it
		_fbt(2.25, 8.25, f.call(0.55), 2.75, 8.75, f.call(0.57), C.GUN, BOLT_TAG),        # charging handle: its stem, off the carrier
		_fbt(2.5, 8.0, f.call(0.545), 3.0, 9.0, f.call(0.58), C.GUN_LIGHT, BOLT_TAG),     # and its knob
		_fb(2.25, 7.5, f.call(0.6), 2.5, 8.0, f.call(0.72), C.GUN),                       # safety lever, along the right side
		_fb(2.25, 7.25, f.call(0.7), 2.6, 8.0, f.call(0.74), C.GUN),                      # its pivot, at the receiver's back
		_fb(2.25, 7.25, f.call(0.6), 2.6, 7.75, f.call(0.625), C.GUN_LIGHT),              # its finger tab, at the front
		_fb(1.25, 5.25, f.call(0.6), 1.75, 5.8, f.call(0.625), C.GUN_LIGHT),              # magazine release paddle, behind the magazine
		_fb(1.25, 9.0, f.call(0.76), 1.75, 9.5, f.call(0.775), C.GUN_LIGHT),              # the dust cover's latch button, at the back
	]}


## A belt-fed's visible belt (BELT_TAG: it comes off with the box): up the receiver's side (the
## left, or the `right` for a PKM, which feeds right to left) from the box, `y0` to the feed
## tray at `tray_y`, and across the tray to `tray_x`, the rounds lying along the bore (`z0` to
## `z1`) with dark links between them; and the tray it lies in, cut into the receiver's top
## under the feed cover (open, the tray and the belt show).
static func _belt(y0: float, tray_y: float, tray_x: float, z0: float, z1: float, right := false) -> Array:
	var side := [2.5, 3.0] if right else [0.0, 0.5]           # the band up the outside
	var tray := [tray_x, 2.5] if right else [0.5, tray_x]     # and on the tray, from that side
	var out := [
		_fb(0.75 if right else 0.5, tray_y, z0 - 0.5, 2.5 if right else 2.25, tray_y + 0.25, z1 + 0.5, C.EMPTY),  # the feed tray, open on the feed side
		_fbp(0.75, tray_y - 0.25, z0 - 0.5, 2.25, tray_y, z1 + 0.5, C.GUN_LIGHT),        # its floor
		_fbt(side[0], y0, z0, side[1], tray_y + 0.25, z1, C.BRASS, BELT_TAG),             # rounds, up the side
		_fbt(tray[0], tray_y, z0, tray[1], tray_y + 0.25, z1, C.BRASS, BELT_TAG),         # and on the tray
		_fbt(side[0], y0, z1 - 0.5, side[1], tray_y + 0.25, z1, C.GUN, BELT_TAG),         # the links' backs, behind the rims
		_fbt(tray[0], tray_y, z1 - 0.5, tray[1], tray_y + 0.25, z1, C.GUN, BELT_TAG),
	]
	var y := y0 + 0.5
	while y < tray_y:
		out.append(_fbt(side[0], y, z0, side[1], y + 0.25, z1, C.GUN, BELT_TAG))  # a link between two rounds
		y += 0.75
	return out


## A PKM, to the real gun (Captain, 2026-10-20: "realistic pk please"; the first cut, from a
## 2026-10-16 photo, had the box off the left, a wooden handguard and a perforated barrel jacket,
## a Pecheneg's at best): a bare fluted barrel with a slotted flash hider and the front sight out
## at the muzzle; the gas cylinder under it from the gas block back to the receiver, the bipod
## on the gas block with its legs folded back under the cylinder; the barrel's carry handle
## folded down along its left; the stamped receiver with the leaf rear sight on its front and the
## feed cover hinged behind it; the 100-round box hung under the receiver's RIGHT side, the belt
## going up into the tray from the right (it feeds right to left); the ejection port and its
## flap on the LEFT; the charging handle low on the right; a brown pistol grip and the skeleton
## butt. AK-pattern leaf-and-post irons (the same action family's).
static func _rifle_pkm(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := ak_iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n)) + optic_mount(art, n, 9.6)
	var boxes := sight + [
		_fb(1.1, 8.0, 0, 1.9, 8.9, f.call(0.37), C.GUN),                        # barrel, on into the receiver
		_fbp(1.0, 8.25, f.call(0.04), 2.0, 8.5, f.call(0.3), C.GUN_LIGHT),       # its flutes, along the sides
		_fb(0.9, 7.7, 0, 2.1, 9.2, 1.5, C.GUN),                                 # slotted flash hider
		_fb(1.25, 7.7, 0.25, 1.75, 7.95, 1.25, C.EMPTY),                        # its slots, top and bottom
		_fb(1.25, 8.95, 0.25, 1.75, 9.2, 1.25, C.EMPTY),
		_fb(1.0, 6.75, f.call(0.14), 2.0, 8.9, f.call(0.17), C.GUN),            # gas block, round the barrel and down to the cylinder
		_fb(1.15, 7.0, f.call(0.17), 1.85, 7.75, f.call(0.35), C.GUN_LIGHT),    # gas cylinder under the barrel, back to the receiver
		_fb(0.5, 6.5, f.call(0.15), 2.5, 7.0, f.call(0.17), C.GUN),             # the bipod's yoke, on the gas block
		_fb(0.5, 6.25, f.call(0.17), 0.9, 6.75, f.call(0.33), C.GUN),           # its legs, folded back under the cylinder
		_fb(2.1, 6.25, f.call(0.17), 2.5, 6.75, f.call(0.33), C.GUN),
		_fb(0.75, 8.25, f.call(0.3), 1.0, 8.75, f.call(0.32), C.GUN),           # carry handle: its clamp on the barrel, left
		_fb(0.25, 8.0, f.call(0.22), 0.75, 9.0, f.call(0.33), C.GUN_LIGHT),     # and the handle, folded down along the barrel
		_fb(0.5, 6.8, f.call(0.34), 2.5, 9.9, f.call(0.52), C.GUN),             # stamped receiver, ahead of the feed cover (the rear sight on it)
		_fb(0.5, 6.8, f.call(0.52), 2.5, 9.5, f.call(0.72), C.GUN),             # and under it
		_fb(0.5, 7.25, f.call(0.55), 0.75, 8.25, f.call(0.66), C.EMPTY),        # ejection port, LEFT (it ejects left)
		_fb(0.25, 6.75, f.call(0.55), 0.5, 7.25, f.call(0.66), C.GUN_LIGHT),    # its flap, open below it
		_fbm(1.0, 1.5, f.call(0.42), 3.0, 6.8, f.call(0.56), C.GUN_LIGHT),       # 100-round box, hung under the receiver's RIGHT
		_fbm(1.0, 1.5, f.call(0.42), 3.0, 2.0, f.call(0.56), C.GUN),             # its bottom
		_fbm(2.75, 4.0, f.call(0.47), 3.0, 4.75, f.call(0.51), C.GUN),           # its lid's catch
		_fb(1.25, 5.8, f.call(0.6), 1.75, 6.2, f.call(0.66), C.GUN),            # trigger guard
		_fb(0.9, 4.4, f.call(0.66), 2.1, 6.8, f.call(0.71), C.WOOD),            # brown pistol grip
		_fb(0.9, 3.0, f.call(0.67), 2.1, 4.4, f.call(0.72), C.WOOD_DARK),
		# Skeleton butt: a hollow frame (top rail, bottom rail, front strut) round a big cut-out,
		# closed off by a solid butt pad at the very end.
		_fb(1.0, 8.4, f.call(0.68), 2.0, 8.9, n, C.WOOD),                       # top rail
		_fb(1.0, 5.6, f.call(0.68), 2.0, 6.1, n, C.WOOD),                       # bottom rail
		_fb(1.0, 5.6, f.call(0.68), 2.0, 8.9, f.call(0.72), C.WOOD_DARK),       # front strut, closes the frame
		_fb(0.8, 5.0, n - 0.5, 2.2, 9.0, n, C.GUN),                             # butt pad
		# The feed cover, hinged at its front (COVER_TAG: a reload lifts its back end), its latch;
		# the charging handle low on the right, forward (BOLT_TAG: charged on an empty reload).
		_fbt(0.5, 9.5, f.call(0.52), 2.5, 9.9, f.call(0.7), C.GUN, COVER_TAG),         # hinged feed cover
		_fbt(1.0, 9.5, f.call(0.68), 2.0, 10.25, f.call(0.71), C.GUN_LIGHT, COVER_TAG), # its latch, at the back
		_fbt(2.5, 7.0, f.call(0.44), 2.75, 7.5, f.call(0.47), C.GUN, BOLT_TAG),        # charging handle, right
		_fbt(2.5, 6.75, f.call(0.445), 3.0, 7.75, f.call(0.465), C.GUN_LIGHT, BOLT_TAG),
	]
	boxes.append_array(_belt(6.8, 9.25, 1.25, f.call(0.53), f.call(0.59), true))
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": boxes}


## An M240B: all black/olive, no wood anywhere (Captain, reference photo). A long, bulky
## receiver (longer than the M249's), a top-mounted carry handle over a top/right feed tray
## cover, a gas tube that runs below the barrel, a bipod folded near the muzzle, and a
## side-folding skeletonized stock (angled off-centre, not a straight fixed block). Rear
## aperture irons, like the M249 (neither is the AK-pattern family's leaf and post).
static func _rifle_m240(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else _on_cover(optic_boxes(art, sight_back(art, n)))  # an optic rides the cover's rail
	# Captain, 2026-10-16 (v0.4.26 on the ground: "none look right"): every part overlaps or sits
	# face-on against the next (weapons_test checks it is one piece); the first cut left the
	# ammo box and the sights hanging in air.
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.1, 8.0, 0, 1.9, 8.9, f.call(0.42), C.GUN),                        # heavy barrel, on into the receiver
		_fb(0.9, 7.7, 0, 2.1, 9.2, 1.5, C.GUN),                                 # flash hider
		_fb(1.1, 8.9, f.call(0.12), 1.9, 9.9, f.call(0.15), C.GUN),             # front sight base, on the barrel
		_fb(0.9, 7.0, f.call(0.07), 2.1, 8.9, f.call(0.1), C.GUN),              # gas regulator, round the barrel
		_fb(1.15, 7.2, f.call(0.07), 1.85, 8.0, f.call(0.4), C.GUN_LIGHT),      # gas tube, below the barrel
		_fb(0.35, 6.0, f.call(0.1), 0.9, 7.2, f.call(0.3), C.GUN),              # bipod legs, folded back under the barrel
		_fb(2.1, 6.0, f.call(0.1), 2.65, 7.2, f.call(0.3), C.GUN),
		_fb(0.35, 6.8, f.call(0.27), 2.65, 7.5, f.call(0.31), C.GUN),           # the bipod's yoke, on the gas tube
		_fb(0.4, 6.4, f.call(0.3), 2.6, 8.0, f.call(0.4), C.GUN_LIGHT),         # handguard under the barrel, ahead of the receiver
		_fb(1.2, 8.9, f.call(0.3), 1.8, 10.2, f.call(0.33), C.GUN),             # carry handle: its post on the barrel
		_fb(1.0, 10.2, f.call(0.22), 2.0, 10.7, f.call(0.36), C.GUN),           # and its grip, along the top
		_fb(0.4, 6.0, f.call(0.38), 2.6, 9.6, f.call(0.84), C.GUN),             # long, bulky receiver (the longest of the three)
		_fb(0.9, 9.6, f.call(0.38), 2.1, 9.95, f.call(0.42), C.GUN),            # top rail, ahead of the feed cover
		_fb(0.9, 9.6, f.call(0.64), 2.1, 9.95, f.call(0.8), C.GUN),             # and behind it (the rear sight)
		_fbm(0.2, -0.25, f.call(0.48), 2.2, 6.0, f.call(0.62), C.GUN_LIGHT),     # 100-round box (12.5 cm tall), hung under the receiver's left
		_fbm(0.2, -0.25, f.call(0.48), 2.2, 0.25, f.call(0.62), C.GUN),
		_fb(1.25, 5.2, f.call(0.61), 1.75, 6.0, f.call(0.66), C.GUN),           # trigger guard
		_fb(0.9, 4.0, f.call(0.66), 2.1, 6.0, f.call(0.72), C.GUN),             # black synthetic pistol grip, raked back
		_fb(0.9, 2.6, f.call(0.67), 2.1, 4.0, f.call(0.73), C.GUN),
		# Side-folding skeletonized stock: offset toward +x (it folds along the side, not a
		# straight block), an angular cut-out frame rather than a solid stock.
		_fb(1.1, 8.2, f.call(0.84), 2.5, 8.8, n, C.GUN),                        # top rail, offset to one side
		_fb(1.1, 5.6, f.call(0.84), 2.5, 6.2, n, C.GUN),                        # bottom rail
		_fb(1.1, 5.6, f.call(0.84), 2.5, 8.8, f.call(0.87), C.GUN_LIGHT),       # front strut, on the receiver's end
		_fb(1.0, 5.2, n - 0.5, 2.6, 9.2, n, C.GUN),                             # butt pad
		# Weapon detail pass (2026-10-20): the feed tray cover, hinged at its front with its rail
		# on it (COVER_TAG), the belt from the box over the tray, the charging handle on the right,
		# forward (BOLT_TAG).
		_fbt(0.55, 9.6, f.call(0.42), 2.45, 9.95, f.call(0.64), C.GUN_LIGHT, COVER_TAG),  # feed tray cover
		_fbt(0.9, 9.6, f.call(0.42), 2.1, 9.95, f.call(0.64), C.GUN, COVER_TAG),         # its rail, for an optic
		_fbt(1.0, 9.95, f.call(0.61), 2.0, 10.25, f.call(0.64), C.GUN_LIGHT, COVER_TAG), # its latch, at the back
		_fbt(2.5, 7.5, f.call(0.44), 2.75, 8.0, f.call(0.47), C.GUN, BOLT_TAG),          # charging handle, right
		_fbt(2.5, 7.25, f.call(0.445), 3.0, 8.25, f.call(0.465), C.GUN_LIGHT, BOLT_TAG),
	] + _belt(6.0, 9.25, 1.75, f.call(0.45), f.call(0.51))}


## An M249 SAW: the ammo box hangs directly under the receiver (not off to the side, like the
## PKM's), a full-length heat-shielded barrel with large oval vents along its TOP, a small
## magazine-well door on the left of the receiver (the STANAG-mag feed option neither the PKM
## nor the M240 have), and a collapsible CAR-style stock — slimmer than either's and shorter
## overall than the M240's. Rear aperture irons.
static func _rifle_m249(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else _on_cover(optic_boxes(art, sight_back(art, n)))  # an optic rides the cover's rail
	# Captain, 2026-10-16 (v0.4.26 on the ground: "the 249 is just missing a lot of its model"):
	# the first cut's receiver was a stub (0.56-0.64 of the length), so the grip, stock, ammo box,
	# bipod and sights all floated apart. Now one piece (weapons_test checks it): a long
	# receiver from the handguard to the buffer tube, everything hung off it.
	var boxes := sight + [
		_fb(1.15, 8.1, 0, 1.85, 8.8, f.call(0.4), C.GUN),                       # barrel, on into the receiver
		_fb(0.95, 7.8, 0, 2.05, 9.1, 1.3, C.GUN),                               # flash hider
		_fb(1.2, 8.75, f.call(0.12), 1.8, 9.9, f.call(0.15), C.GUN),            # front sight base, on the barrel
		_fb(1.2, 7.3, f.call(0.08), 1.8, 8.1, f.call(0.36), C.GUN_LIGHT),       # gas tube, below the barrel
		_fb(0.4, 6.6, f.call(0.06), 0.85, 7.6, f.call(0.28), C.GUN),            # bipod legs, folded under the barrel
		_fb(2.15, 6.6, f.call(0.06), 2.6, 7.6, f.call(0.28), C.GUN),
		_fb(0.4, 7.3, f.call(0.06), 2.6, 7.8, f.call(0.09), C.GUN),             # the bipod's yoke, on the gas tube
		_fb(0.7, 8.8, f.call(0.1), 2.3, 9.6, f.call(0.36), C.GUN_LIGHT),        # heat shield over the top of the barrel
		_fb(1.2, 9.6, f.call(0.3), 1.8, 10.0, f.call(0.36), C.GUN),             # carry handle: its post on the shield
		_fb(1.0, 10.0, f.call(0.26), 2.0, 10.4, f.call(0.36), C.GUN),           # and its grip
		_fb(0.5, 6.2, f.call(0.28), 2.5, 8.1, f.call(0.36), C.GUN_LIGHT),       # handguard, under the barrel
		_fb(0.5, 6.2, f.call(0.36), 2.5, 9.6, f.call(0.72), C.GUN),             # receiver
		_fb(0.9, 9.6, f.call(0.6), 2.1, 9.95, f.call(0.74), C.GUN),             # top rail behind the feed cover (the rear sight)
		_fb(0.25, 6.8, f.call(0.6), 0.5, 8.2, f.call(0.68), C.GUN_LIGHT),       # magazine-well door, left side of the receiver
		_fbm(0.4, -0.5, f.call(0.39), 2.6, 6.2, f.call(0.58), C.GUN_LIGHT),       # 200-round box (13.5 cm tall), directly under the receiver
		_fbm(0.4, -0.5, f.call(0.39), 2.6, -0.1, f.call(0.58), C.GUN),           # its bottom (it comes off with the box)
		_fb(1.25, 5.4, f.call(0.6), 1.75, 6.2, f.call(0.65), C.GUN),            # trigger guard
		_fb(0.9, 4.4, f.call(0.65), 2.1, 6.2, f.call(0.71), C.GUN),             # pistol grip, raked back (hand_points: 0.68)
		_fb(0.9, 3.0, f.call(0.66), 2.1, 4.4, f.call(0.72), C.GUN),
		_fb(0.9, 1.8, f.call(0.67), 2.1, 3.0, f.call(0.73), C.GUN),
		_fb(1.15, 7.5, f.call(0.72), 1.85, 8.5, f.call(0.9), C.GUN_LIGHT),      # buffer tube, exposed
		_fb(1.0, 6.2, f.call(0.86), 2.0, 9.2, n, C.GUN_LIGHT),                  # slim collapsible stock, on the tube
		_fb(0.9, 5.8, n - 0.4, 2.1, 9.4, n, C.GUN),                             # butt pad
	]
	# Oval vent holes along the TOP of the heat shield (not the sides: Captain's reference).
	var z: float = f.call(0.17)
	while z < f.call(0.34):
		boxes.append(_fb(1.0, 9.35, z, 2.0, 9.6, z + n * 0.02, C.EMPTY))
		z += n * 0.04
	# Weapon detail pass (2026-10-20): the feed cover over the receiver's front, hinged at its
	# front with its rail on it (COVER_TAG), the belt from the box up the left over the tray, the
	# charging handle on the right, forward (BOLT_TAG).
	boxes.append_array([
		_fbt(0.6, 9.6, f.call(0.37), 2.4, 9.95, f.call(0.6), C.GUN_LIGHT, COVER_TAG),   # feed cover
		_fbt(0.9, 9.6, f.call(0.37), 2.1, 9.95, f.call(0.6), C.GUN, COVER_TAG),         # its rail, for an optic
		_fbt(1.0, 9.95, f.call(0.57), 2.0, 10.25, f.call(0.6), C.GUN_LIGHT, COVER_TAG), # its latch, at the back
		_fbt(2.5, 7.25, f.call(0.42), 2.75, 7.75, f.call(0.45), C.GUN, BOLT_TAG),       # charging handle, right
		_fbt(2.5, 7.0, f.call(0.425), 3.0, 8.0, f.call(0.445), C.GUN_LIGHT, BOLT_TAG),
	])
	boxes.append_array(_belt(5.5, 9.25, 1.75, f.call(0.41), f.call(0.47)))
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": boxes}


## An L85A2: a bullpup — the magazine and the long receiver that feeds it sit BEHIND the
## pistol grip and trigger, running on to the shoulder plate with no separate stock past it
## (Captain, reference photo: the family's single most distinct trait — should read as a
## different gun at a glance). The grip itself stays at the AR family's usual spot
## (hand_points reads a fixed fraction of the model's length for every rifle style, not this
## one specially), so the shift the eye catches is the magazine moving in behind it and the
## stock disappearing. A flat full-length rail replaces the old carry-handle sight housing
## (the modern upgrade Captain's photo shows, not the original SUSAT hump).
static func _rifle_bullpup(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))
	# Captain, 2026-10-16 (v0.4.26 on the ground): the first cut's receiver stopped short of the
	# shoulder plate and sat above the magazine and grip, so all three floated free. Now the
	# body runs to the plate and its deep lower half (the mag well, the butt) carries the grip
	# and magazine: one piece (weapons_test checks it).
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.25, 8.25, 0, 1.75, 8.75, f.call(0.4), C.GUN),                     # barrel (most of it is inside the long receiver)
		_fb(1.05, 7.95, 0, 1.95, 9.05, 1.5, C.GUN),                             # muzzle device
		_fb(0.75, 8.5, 0.5, 1.05, 9.25, 1.25, C.GUN_LIGHT),                     # front sling ring, on the muzzle device
		_fb(1.2, 8.75, f.call(0.1), 1.8, 9.9, f.call(0.12), C.GUN),             # gas block
		_fb(0.6, 7.0, f.call(0.12), 2.4, 9.6, f.call(0.37), C.GUN_LIGHT),       # short handguard, angular lines, back under the support hand
		_fb(0.9, 9.6, f.call(0.12), 2.1, 9.95, f.call(0.9), C.GUN),             # flat full-length rail, replacing the old carry handle
		_fb(0.7, 7.0, f.call(0.33), 2.3, 9.6, n, C.GUN),                        # the long body, past the grip to the shoulder plate
		_fb(0.75, 5.4, f.call(0.58), 2.25, 7.0, n, C.GUN),                      # its deep lower half: the mag well and the butt
		_fb(1.25, 5.0, f.call(0.58), 1.75, 7.0, f.call(0.6), C.GUN),            # trigger guard: its front, under the body
		_fb(1.25, 4.6, f.call(0.58), 1.75, 5.0, f.call(0.66), C.GUN),           # and along to the grip, well forward of the magazine
		_fb(0.9, 4.4, f.call(0.66), 2.1, 5.4, f.call(0.71), C.GUN),             # pistol grip (the AR family's usual spot: hand_points)
		_fb(0.9, 3.0, f.call(0.67), 2.1, 4.4, f.call(0.72), C.GUN),
		_fb(0.9, 1.6, f.call(0.68), 2.1, 3.0, f.call(0.735), C.GUN),
		_fb(0.7, 5.0, f.call(0.745), 2.3, 5.4, f.call(0.895), C.GUN),           # the magazine housing's lip, round the well
		_fb(1.0, 5.0, f.call(0.78), 2.0, 6.75, f.call(0.86), C.EMPTY),          # the well, up into the body behind the grip
		_fbm(0.9, 3.9, f.call(0.78), 2.1, 6.75, f.call(0.86), C.GUN_LIGHT),     # 30-round magazine, up in the well, BEHIND the grip,
		_fbm(0.9, 2.4, f.call(0.77), 2.1, 3.9, f.call(0.85), C.GUN_LIGHT),      # then 11 cm under the housing, curving forward
		_fbm(0.9, 0.9, f.call(0.755), 2.1, 2.4, f.call(0.835), C.GUN_LIGHT),
		_fbm(0.9, -0.1, f.call(0.74), 2.1, 0.9, f.call(0.82), C.GUN_LIGHT),
		_fbm(0.85, -0.6, f.call(0.735), 2.15, -0.1, f.call(0.82), C.GUN),       # floorplate
		_fb(0.55, 5.9, f.call(0.735), 0.75, 6.3, f.call(0.76), C.GUN_LIGHT),    # magazine release button, left, at the well's front
		_fb(0.5, 7.2, f.call(0.745), 0.7, 7.6, f.call(0.775), C.GUN_LIGHT),     # bolt release plunger, upper left (pressed down)
		_fb(2.0, 8.25, f.call(0.48), 2.25, 8.5, f.call(0.62), C.EMPTY),         # the cocking handle's slot, running back
		_fbt(2.25, 8.25, f.call(0.48), 2.75, 8.75, f.call(0.52), C.GUN, BOLT_TAG),  # the cocking handle, right side ("comma"): it rides the carrier
		_fb(1.75, 7.75, f.call(0.62), 2.25, 8.5, f.call(0.72), C.EMPTY),        # ejection port, right side
		_fbt(1.75, 7.75, f.call(0.62), 2.0, 8.5, f.call(0.68), C.GUN_LIGHT, BOLT_TAG),  # the bolt carrier in it (locked back, empty)
		_fb(0.55, 6.6, f.call(0.6), 2.45, 6.85, f.call(0.62), C.GUN_LIGHT),     # cross-bolt safety, through above the trigger
		_fb(0.95, 9.6, f.call(0.9), 2.05, 9.9, n, C.GUN),                       # cheek piece over the butt, behind the rail
		_fb(0.6, 5.2, n - 0.5, 2.4, 9.8, n, C.GUN_LIGHT),                       # shoulder plate: the body's own back end, no stock past it
	]}


## A C8: the standard AR/M4-pattern upper and lower (no piston tube: unlike the HK416, just the
## thin direct-impingement gas tube under the rail), and a collapsible Magpul-style stock on a
## longer exposed buffer tube with position notches (it telescopes), not a fixed one. Its heavy
## 15.7 in barrel (the C8SFW's and C8A3's: longer than the M4's 14.5 in) runs out past a
## carbine-length handguard and a taller front sight base; the upper receiver is the M4's length
## (weapon detail pass, 2026-10-20: the first cut ran the upper forward to 0.3 of the length,
## half as long again as a real one, behind a stub of handguard).
static func _rifle_carbine_short(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))
	var boxes := sight + [
		_fb(1.2, 8.2, 0, 1.8, 8.8, f.call(0.46), C.GUN),                        # heavy barrel, on into the upper
		_fb(1.05, 7.95, 0, 1.95, 9.05, 1.5, C.GUN),                             # muzzle device
		_fb(1.1, 8.6, f.call(0.13), 1.9, 9.9, f.call(0.16), C.GUN),             # front sight base / gas block, a carbine's length out
		_fb(0.6, 7.0, f.call(0.16), 2.4, 9.6, f.call(0.45), C.GUN_LIGHT),       # carbine-length handguard
		_fb(0.9, 9.6, f.call(0.16), 2.1, 9.95, f.call(0.74), C.GUN),            # top rail
		_fb(0.6, 7.0, f.call(0.16), 0.85, 9.6, f.call(0.45), C.GUN),            # side rails
		_fb(2.15, 7.0, f.call(0.16), 2.4, 9.6, f.call(0.45), C.GUN),
		_fb(0.7, 7.0, f.call(0.45), 2.3, 9.6, f.call(0.74), C.GUN),             # upper receiver, on to the buffer tube
		_fb(0.75, 5.6, f.call(0.47), 2.25, 7.0, f.call(0.72), C.GUN),           # lower receiver
		_fb(0.75, 3.75, f.call(0.47), 2.25, 5.6, f.call(0.6), C.GUN),           # its magazine well, 6 cm deep
		_fb(1.0, 3.75, f.call(0.5), 2.0, 6.75, f.call(0.575), C.EMPTY),         # the well itself
		_fbm(0.9, 3.75, f.call(0.5), 2.1, 6.75, f.call(0.575), C.GUN_LIGHT),     # 30-round magazine: up in the well,
		_fbm(0.9, 2.25, f.call(0.49), 2.1, 3.75, f.call(0.565), C.GUN_LIGHT),    # then 12.5 cm under it, curving forward
		_fbm(0.9, 0.75, f.call(0.475), 2.1, 2.25, f.call(0.55), C.GUN_LIGHT),
		_fbm(0.9, -0.75, f.call(0.455), 2.1, 0.75, f.call(0.535), C.GUN_LIGHT),
		_fbm(0.9, -2.0, f.call(0.435), 2.1, -0.75, f.call(0.52), C.GUN_LIGHT),
		_fbm(0.85, -2.5, f.call(0.43), 2.15, -2.0, f.call(0.52), C.GUN),        # floorplate
		_fb(1.25, 4.6, f.call(0.6), 1.75, 5.0, f.call(0.66), C.GUN),            # trigger guard
		_fb(0.9, 4.4, f.call(0.66), 2.1, 5.6, f.call(0.71), C.GUN),             # pistol grip
		_fb(0.9, 3.0, f.call(0.67), 2.1, 4.4, f.call(0.72), C.GUN),
		_fb(0.9, 1.6, f.call(0.68), 2.1, 3.0, f.call(0.735), C.GUN),
		_fb(0.9, 0.6, f.call(0.69), 2.1, 1.6, f.call(0.745), C.GUN),            # its bottom: 10 cm of grip, like an A2's
		_fb(1.1, 7.5, f.call(0.74), 1.9, 8.7, f.call(0.95), C.GUN_LIGHT),       # buffer tube, exposed further than a fixed-stock AR's
	]
	var z: float = f.call(0.77)
	while z < f.call(0.92):
		boxes.append(_fb(1.1, 8.3, z, 1.9, 8.5, z + n * 0.008, C.EMPTY))        # position notches: it telescopes, not fixed
		z += n * 0.04
	boxes.append_array([
		_fb(0.85, 6.6, f.call(0.88), 2.15, 9.0, n, C.GUN_LIGHT),                # collapsible stock, slimmer than a fixed one
		_fb(0.85, 5.8, n - 0.4, 2.15, 9.0, n, C.GUN),                           # butt pad
	])
	boxes.append_array(_ar_controls(n))
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": boxes}


## An HK416, to the real rifle (weapon detail pass, 2026-10-20: the first cut ran its piston rod
## along the top of the rail, where the real one never shows): its short-stroke piston hides
## inside a chunky free-floated quad rail that runs out over the gas block, the top rail one flat
## line from there to the receiver's back, and a deep E2-style stock with its two storage tubes.
## The receiver and controls are the M4 pattern's.
static func _rifle_piston_ar(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.25, 8.25, 0, 1.75, 8.75, f.call(0.3), C.GUN),                     # barrel
		_fb(1.05, 7.95, 0, 1.95, 9.05, 1.5, C.GUN),                             # muzzle device
		_fb(1.1, 8.75, f.call(0.12), 1.9, 9.9, f.call(0.15), C.GUN),            # gas block and piston, hidden in the rail's front
		_fb(0.5, 6.75, f.call(0.11), 2.5, 9.6, f.call(0.45), C.GUN_LIGHT),      # free-floated quad rail, out over the gas block
		_fb(0.9, 9.6, f.call(0.11), 2.1, 9.95, f.call(0.74), C.GUN),            # top rail, one flat line (an optic or the rear aperture sits on it)
		_fb(0.5, 6.75, f.call(0.11), 0.75, 9.6, f.call(0.45), C.GUN),           # side rails
		_fb(2.25, 6.75, f.call(0.11), 2.5, 9.6, f.call(0.45), C.GUN),
		_fb(0.9, 6.5, f.call(0.11), 2.1, 6.75, f.call(0.45), C.GUN),            # bottom rail
		_fb(0.7, 7.0, f.call(0.45), 2.3, 9.6, f.call(0.74), C.GUN),             # upper receiver
		_fb(0.75, 5.6, f.call(0.47), 2.25, 7.0, f.call(0.72), C.GUN),           # lower receiver
		_fb(0.75, 3.75, f.call(0.47), 2.25, 5.6, f.call(0.6), C.GUN),           # its magazine well, 6 cm deep
		_fb(1.0, 3.75, f.call(0.5), 2.0, 6.75, f.call(0.575), C.EMPTY),         # the well itself
		_fbm(0.9, 3.75, f.call(0.5), 2.1, 6.75, f.call(0.575), C.GUN_LIGHT),     # 30-round magazine: up in the well,
		_fbm(0.9, 2.25, f.call(0.49), 2.1, 3.75, f.call(0.565), C.GUN_LIGHT),    # then 12.5 cm under it, curving forward
		_fbm(0.9, 0.75, f.call(0.475), 2.1, 2.25, f.call(0.55), C.GUN_LIGHT),
		_fbm(0.9, -0.75, f.call(0.455), 2.1, 0.75, f.call(0.535), C.GUN_LIGHT),
		_fbm(0.9, -2.0, f.call(0.435), 2.1, -0.75, f.call(0.52), C.GUN_LIGHT),
		_fbm(0.85, -2.5, f.call(0.43), 2.15, -2.0, f.call(0.52), C.GUN),        # floorplate
		_fb(1.25, 4.6, f.call(0.6), 1.75, 5.0, f.call(0.66), C.GUN),            # trigger guard
		_fb(0.9, 4.4, f.call(0.66), 2.1, 5.6, f.call(0.71), C.GUN),             # pistol grip
		_fb(0.9, 3.0, f.call(0.67), 2.1, 4.4, f.call(0.72), C.GUN),
		_fb(0.9, 1.6, f.call(0.68), 2.1, 3.0, f.call(0.735), C.GUN),
		_fb(0.9, 0.6, f.call(0.69), 2.1, 1.6, f.call(0.745), C.GUN),            # its bottom: 10 cm of grip, like an A2's
		_fb(1.1, 7.6, f.call(0.74), 1.9, 8.8, f.call(0.82), C.GUN_LIGHT),       # buffer tube
		_fb(0.8, 6.0, f.call(0.8), 2.2, 9.4, n, C.GUN_LIGHT),                   # stock
		_fb(0.95, 9.4, f.call(0.82), 2.05, 9.8, f.call(0.95), C.GUN_LIGHT),     # cheek rest
		_fb(0.8, 5.6, n - 0.5, 2.2, 9.8, n, C.GUN),                             # butt pad
		_fb(0.6, 5.25, f.call(0.84), 0.8, 6.5, n - 0.5, C.GUN),                 # the E2 stock's storage tubes, low either side
		_fb(2.2, 5.25, f.call(0.84), 2.4, 6.5, n - 0.5, C.GUN),
		_fb(0.8, 5.25, f.call(0.84), 2.2, 6.0, n, C.GUN_LIGHT),                 # and its deep belly between them
	] + _ar_controls(n)}


## A bolt-action rifle (Mosin-Nagant 91/30): a one-piece wood stock running nearly the barrel's
## full length (unlike the AR/AK families' separate handguard and receiver), a straight,
## uncurved wrist (no pistol grip), no visible magazine (it feeds internally, loaded from
## 5-round stripper clips, flush under the receiver), and a bolt handle sticking out to the
## right — the one thing that cycles it between shots. `art` is almost always IRONS: the PU
## scope mounts low and offset to the rifle's left in reality (its bolt handle needs the
## centreline clear), but this engine's rail always mounts an optic centred like every other
## rifle's (Optics has no per-weapon offset), so it rides centred here too.
static func _rifle_bolt(length: int, art := IRONS, turned_grip := false) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := ak_iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n)) + optic_mount(art, n, 9.0)
	var wrist_end: float = f.call(0.76) if turned_grip else f.call(0.73)
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": sight + [
		_fb(1.3, 8.3, 0, 1.7, 8.7, f.call(0.9), C.GUN),                         # thin barrel, most of it under the stock
		_fb(1.1, 8.1, 0, 1.9, 8.9, 2.0, C.GUN),                                 # muzzle / front barrel band
		_fb(0.6, 6.6, f.call(0.04), 2.4, 9.0, f.call(0.08), C.WOOD_DARK),       # nose cap
		_fb(0.55, 6.6, f.call(0.08), 2.45, 9.0, f.call(0.86), C.WOOD),          # one-piece wood stock, nearly full length
		_fb(0.55, 6.6, f.call(0.42), 2.45, 7.0, f.call(0.46), C.WOOD_DARK),     # middle barrel band / sling swivel
		_fb(0.7, 7.0, f.call(0.5), 2.3, 9.3, f.call(0.84), C.GUN),              # receiver, sitting in the stock's cut
		_fb(0.6, 6.4, f.call(0.52), 2.4, 7.0, f.call(0.62), C.GUN_LIGHT),       # flush floorplate: an internal box magazine, nothing sticking out
		_fb(1.25, 5.6, f.call(0.62), 1.75, 6.0, f.call(0.68), C.GUN),           # trigger guard
		# The bolt (BOLT_TAG: turned up and drawn back to load, weapon detail pass 2026-10-20): its
		# straight handle out to the right at the action's back, over the stock's line (the old one
		# sat half inside the wood), and the ball knob on it.
		_fbt(2.25, 9.0, f.call(0.72), 2.75, 9.5, f.call(0.75), C.GUN, BOLT_TAG),         # bolt handle, straight out to the right over the stock
		_fbt(2.5, 8.5, f.call(0.715), 3.0, 9.5, f.call(0.755), C.GUN_LIGHT, BOLT_TAG),   # its ball knob
		_fb(0.85, 4.0, f.call(0.65), 2.15, 7.0, wrist_end, C.WOOD_DARK if turned_grip else C.WOOD),  # stock's wrist
		_fb(0.8, 5.6, f.call(0.84), 2.2, 9.0, n, C.WOOD),                       # long buttstock
		_fb(0.8, 5.0, f.call(0.95), 2.2, 6.0, n, C.WOOD_DARK),
		_fb(0.8, 4.8, n - 0.4, 2.2, 9.0, n, C.METAL),                           # steel butt plate (no recoil pad on a milsurp bolt gun)
	]}


## A modern precision bolt-action rifle (the "Springfield Heatseeker": tan/FDE chassis, not the
## vintage wood rifle — Captain, reference photos, 2026-10-16): a folding, adjustable chassis
## stock instead of wood, an M-LOK handguard with lightening cuts, a DETACHABLE black box
## magazine (not stripper clips: this one's a modern precision chassis gun), an adjustable
## bipod, a threaded muzzle (suppressor-ready: _with_suppressor), and the same bolt-handle
## cue as the Mosin, since it's still a manually-cycled action.
static func _rifle_chassis_bolt(length: int, art := IRONS) -> Dictionary:
	var n := maxi(length, 20)
	var f := func(t: float) -> float: return n * t
	var sight := iron_boxes(n) if art == IRONS else optic_boxes(art, sight_back(art, n))
	var boxes := sight + [
		_fb(1.2, 8.2, 0, 1.8, 8.8, f.call(0.5), C.GUN),                         # heavy precision barrel
		_fb(1.0, 8.0, 0, 2.0, 9.0, 1.5, C.GUN),                                 # threaded muzzle device
		_fb(0.4, 5.2, f.call(0.1), 0.85, 7.6, f.call(0.24), C.GUN),             # adjustable bipod, extended
		_fb(2.15, 5.2, f.call(0.1), 2.6, 7.6, f.call(0.24), C.GUN),
		_fb(0.5, 6.6, f.call(0.12), 2.5, 8.6, f.call(0.56), C.GUN_LIGHT),       # M-LOK handguard
		_fb(0.9, 8.6, f.call(0.12), 2.1, 8.95, f.call(0.72), C.GUN),            # full-length top rail
		_fb(0.95, 8.95, f.call(0.4), 2.05, RAIL_Y, f.call(0.74), C.GUN),        # raised scope base on it, up to RAIL_Y (the optic sat in air)
		_fb(0.7, 7.0, f.call(0.56), 2.3, 8.6, f.call(0.74), C.GUN),             # receiver, in the chassis
		_fbm(0.9, 4.0, f.call(0.6), 2.1, 7.0, f.call(0.68), C.GUN),              # detachable box magazine, protruding below
		_fbm(0.9, 4.0, f.call(0.6), 2.1, 4.4, f.call(0.68), C.GUN_LIGHT),
		_fb(1.25, 5.8, f.call(0.68), 1.75, 6.2, f.call(0.73), C.GUN),           # trigger guard
		_fb(0.9, 4.4, f.call(0.73), 2.1, 7.0, f.call(0.78), C.GUN_LIGHT),       # chassis pistol grip
		# The bolt (BOLT_TAG: turned up and drawn back on an empty reload, weapon detail pass
		# 2026-10-20): its body in the ejection port, the shroud out of the receiver's back, the
		# handle and its oversized tactical knob.
		_fb(1.75, 7.75, f.call(0.6), 2.25, 8.5, f.call(0.68), C.EMPTY),                  # ejection port, right
		_fbt(1.75, 7.75, f.call(0.6), 2.0, 8.5, f.call(0.68), C.GUN_LIGHT, BOLT_TAG),    # the bolt's body in it
		_fbt(1.0, 7.25, f.call(0.74), 2.0, 8.25, f.call(0.765), C.GUN, BOLT_TAG),        # bolt shroud, out the back
		_fbt(2.25, 8.25, f.call(0.69), 2.75, 8.75, f.call(0.74), C.GUN, BOLT_TAG),       # bolt handle
		_fbt(2.5, 7.75, f.call(0.72), 3.0, 9.0, f.call(0.78), C.GUN_LIGHT, BOLT_TAG),    # its tactical knob
	]
	if art == IRONS:
		boxes.append(_fb(1.1, 8.95, f.call(0.12), 1.9, 9.75, f.call(0.15), C.GUN))  # back-up front sight's riser, on the rail
	# M-LOK lightening cuts along the handguard's sides (EMPTY slots, not solid polymer).
	var z: float = f.call(0.18)
	while z < f.call(0.52):
		boxes.append(_fb(0.5, 7.0, z, 0.65, 8.2, z + n * 0.012, C.EMPTY))
		boxes.append(_fb(2.35, 7.0, z, 2.5, 8.2, z + n * 0.012, C.EMPTY))
		z += n * 0.045
	boxes.append_array([
		# Folding, adjustable chassis stock: an open skeleton frame (not solid, not wood) with
		# an adjustable cheek riser block on top.
		_fb(1.0, 7.8, f.call(0.8), 2.0, 8.3, n, C.GUN_LIGHT),                   # cheek riser, raised above the frame
		_fb(1.0, 7.2, f.call(0.78), 2.0, 7.6, n, C.GUN),                        # top rail of the folding frame
		_fb(1.0, 5.4, f.call(0.78), 2.0, 5.9, n, C.GUN),                        # bottom rail
		_fb(1.0, 5.4, f.call(0.78), 2.0, 7.6, f.call(0.82), C.GUN),             # front strut, closes the frame
		_fb(0.9, 5.2, n - 0.6, 2.1, 8.4, n, C.GUN_LIGHT),                       # adjustable buttpad / spacer stack
	])
	return {"size": Vector3i(3, 13, n), "sub": 4, "boxes": boxes}


## A suppressor stacked on the muzzle: every other box shifts back by its length (so the model's
## muzzle, and everything behind it, keeps its usual place — grip/stock points, iron sights,
## optic mount), and a plain can fills the new gap at the front. Generic over every rifle style
## (_spec applies it after building whichever style ran), so adding it to a new silhouette
## never needs its own suppressor geometry.
const SUPPRESSOR_FRAC := 0.2

static func _with_suppressor(spec: Dictionary) -> Dictionary:
	var n: float = spec.size.z
	var shift := n * SUPPRESSOR_FRAC
	var boxes: Array = []
	for b: Array in spec.boxes:
		boxes.append([b[0] + Vector3(0, 0, shift), b[1] + Vector3(0, 0, shift)] + b.slice(2))  # (a magazine keeps its tag)
	boxes.append(_fb(1.0, 7.9, 0, 2.0, 9.1, shift, C.GUN_LIGHT))                # suppressor body
	boxes.append(_fb(1.1, 8.0, 0, 1.9, 9.0, shift * 0.1, C.GUN))                # end cap
	var size: Vector3i = spec.size
	size.z += ceili(shift)
	return {"size": size, "sub": spec.get("sub", 1), "boxes": boxes}


## 0.04 x 0.14 x 0.20 m, muzzle at z = 0, built at 0.5 cm: slide, frame, raked grip with its
## magazine up it, trigger guard, a front post and a notched rear sight (Captain, P0362:
## readable irons).
## hand_points: grip at (1, 2.5, 7.5); sight_point: the rear notch's top (1, 7.0, 9.4).
static func _pistol() -> Dictionary:
	# The slide and its sights are BOLT_TAG (weapon detail pass, 2026-10-20): an empty magazine
	# leaves it locked back until the reload racks it home.
	return {"size": Vector3i(2, 7, 10), "sub": 4, "boxes": [
		_fbt(0.15, 4.6, 0, 1.85, 6.8, 10, C.GUN, BOLT_TAG),             # slide
		_fbt(0.85, 6.8, 0.3, 1.15, 7.0, 0.8, C.GUN, BOLT_TAG),         # front post
		_fbt(0.3, 6.8, 8.8, 0.75, 7.0, 9.4, C.GUN, BOLT_TAG),          # rear sight, either side of the notch
		_fbt(1.25, 6.8, 8.8, 1.7, 7.0, 9.4, C.GUN, BOLT_TAG),
		[Vector3(0.15, 4.75, 7.25), Vector3(1.85, 6.5, 9.5), C.GUN_LIGHT, true, BOLT_TAG],  # rear cocking serrations (a recolour)
		[Vector3(0.15, 4.75, 7.25), Vector3(1.85, 6.5, 7.5), C.GUN, true, BOLT_TAG],
		[Vector3(0.15, 4.75, 7.75), Vector3(1.85, 6.5, 8.0), C.GUN, true, BOLT_TAG],
		[Vector3(0.15, 4.75, 8.25), Vector3(1.85, 6.5, 8.5), C.GUN, true, BOLT_TAG],
		[Vector3(0.15, 4.75, 8.75), Vector3(1.85, 6.5, 9.0), C.GUN, true, BOLT_TAG],
		_fb(0.0, 4.0, 4.5, 0.25, 4.5, 6.5, C.GUN),           # slide stop lever, on the frame's left
		_fb(0.2, 3.6, 0.6, 1.8, 4.6, 9.2, C.GUN_LIGHT),      # frame
		_fb(0.2, 2.4, 6.0, 1.8, 3.6, 9.2, C.GUN_LIGHT),      # grip, raked back
		_fb(0.2, 1.2, 6.4, 1.8, 2.4, 9.5, C.GUN_LIGHT),
		_fb(0.2, 0.25, 6.8, 1.8, 1.2, 9.8, C.GUN_LIGHT),
		_fb(0.75, 2.6, 4.2, 1.25, 3.6, 4.5, C.GUN),          # trigger guard
		_fb(0.75, 2.6, 4.2, 1.25, 2.9, 6.0, C.GUN),
		# Its magazine (Captain, 2026-10-20: "pistola needs a sep mag too"), up a well in the grip
		# (MAG_TAG: a reload drops it out the bottom and pushes a new one up): the well, the
		# magazine raked with the grip, and its floorplate, the grip's bottom.
		_fb(0.5, 2.4, 6.5, 1.5, 3.75, 8.75, C.EMPTY),
		_fb(0.5, 1.2, 6.9, 1.5, 2.4, 9.1, C.EMPTY),
		_fb(0.5, 0.25, 7.25, 1.5, 1.2, 9.4, C.EMPTY),
		_fbm(0.5, 2.4, 6.5, 1.5, 3.75, 8.75, C.GUN),
		_fbm(0.5, 1.2, 6.9, 1.5, 2.4, 9.1, C.GUN),
		_fbm(0.5, 0.25, 7.25, 1.5, 1.2, 9.4, C.GUN),
		_fbm(0.25, 0.0, 7.0, 1.75, 0.25, 9.75, C.GUN),       # floorplate
	]}


## A box of `size` metres in 0.5 cm voxels (FINE_VOXEL) with its edges bevelled (1 cm,
## less on thin boxes), in one colour: pouches and small gear. The mesh's origin is the
## box's corner; fine_dims gives its size in voxels.
static func bevel_box_mesh(size: Vector3, colour: Color) -> Mesh:
	var dims := fine_dims(size)
	var key := "%s|%s" % [dims, colour.to_html()]
	if _box_meshes.has(key):
		return _box_meshes[key]
	var b := mini(2, mini(dims.x, mini(dims.y, dims.z)) / 3)
	var buffer := VoxelBuffer.new()
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	buffer.create(dims.x + 2, dims.y + 2, dims.z + 2)
	buffer.fill(0, VoxelBuffer.CHANNEL_COLOR)
	for x in dims.x:
		var ex := mini(x, dims.x - 1 - x)
		for y in dims.y:
			var ey := mini(y, dims.y - 1 - y)
			for z in dims.z:
				var ez := mini(z, dims.z - 1 - z)
				if ex + ey < b or ex + ez < b or ey + ez < b:
					continue
				buffer.set_voxel(1, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
	var ckey := colour.to_html()
	if not _colour_meshers.has(ckey):
		var palette := VoxelColorPalette.new()
		palette.set_color(0, Color(0, 0, 0, 0))
		palette.set_color(1, colour)
		var mesher := VoxelMesherCubes.new()
		mesher.palette = palette
		mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
		_colour_meshers[ckey] = mesher
	var mesh: Mesh = _colour_meshers[ckey].build_mesh(buffer, [])
	_box_meshes[key] = mesh
	return mesh


static func fine_dims(size: Vector3) -> Vector3i:
	return Vector3i(maxi(1, roundi(size.x / FINE_VOXEL)), maxi(1, roundi(size.y / FINE_VOXEL)), maxi(1, roundi(size.z / FINE_VOXEL)))
