class_name ItemArt
extends RefCounted
## How each item looks lying on the ground (WorldItem): a low-poly voxel model in 0.5 cm voxels,
## Stormworks style like VoxelArt's gear, laid in its resting pose (a rifle on its side, a
## carrier on its back, a pouch flat, a jerrycan standing). ground_node() is centred on the
## model's own bounds and ground_size() is those bounds, so the item's collision box is the
## model: it lies on the ground with nothing floating or sunk.
##
## Reuses the art that already exists: rifles, the pistol, carriers and packs are VoxelArt's
## models (the ones soldiers carry), pouches and the knife GearRig.pouch_node (the ones on the
## carrier). Everything else is built here from box lists (Shape), one mesh per item id,
## cached, all on VoxelArt's shared vertex-colour material. Plates and helmets lie as their
## VoxelArmor piece (WorldItem does that, not this). An item with no model of its own here gets
## a bevelled box of its size and type colour.

## Resting turns for VoxelArt models: on its side (ejection port up), on its back (front up), or
## a pack on its harness (outer face up).
const ON_SIDE := Vector3(0, 0, PI / 2)
const ON_BACK := Vector3(PI / 2, 0, 0)
const ON_STRAPS := Vector3(-PI / 2, 0, 0)

## A carrier lying empty is this deep front to back, of what it is worn (VoxelArt's vest is
## shaped round a torso).
const VEST_SLUMP := 0.42

enum Axis { X, Y, Z }

## Colours for the item models: VoxelArt's palette (VoxelArt.C, multicam) plus these.
enum K {
	RED = 40, RED_DARK, WHITE, PAPER, BRASS, COPPER, OD, OD_DARK, KHAKI, BLACK, ORANGE, YELLOW,
	GREEN, BLUE, PURPLE, GREY, GREY_LIGHT, STEEL, SILVER, GOLD, WOOD, WOOD_DARK, PCB, SCREEN,
	CLEAR, BLOOD, PINK, TEAL, MANILA, TAN, RUBBER, DARK_GREY, NAVY, BROWN, AMBER, LIME,
	GUNMETAL, SMOKE_WHITE, SAND, CREAM, SALINE,
}
const COLOURS := {
	K.RED: "b3261e", K.RED_DARK: "7a1a15", K.WHITE: "e6e4dc", K.PAPER: "d8d2c0", K.BRASS: "c79c45",
	K.COPPER: "b0643c", K.OD: "535a36", K.OD_DARK: "3b4028", K.KHAKI: "8c8458", K.BLACK: "1d1d1c",
	K.ORANGE: "d8681e", K.YELLOW: "dcb426", K.GREEN: "3f8f43", K.BLUE: "2f5ea8", K.PURPLE: "6a3d91",
	K.GREY: "5d6063", K.GREY_LIGHT: "a3a6a6", K.STEEL: "8f9290", K.SILVER: "c6c9cb", K.GOLD: "c9a443",
	K.WOOD: "9a7448", K.WOOD_DARK: "6b4f30", K.PCB: "2d6a3c", K.SCREEN: "26323c", K.CLEAR: "c6d4d6",
	K.BLOOD: "6e1015", K.PINK: "d6738c", K.TEAL: "2f8a85", K.MANILA: "d2b77c", K.TAN: "b59f74",
	K.RUBBER: "262626", K.DARK_GREY: "3b3d3f", K.NAVY: "27324a", K.BROWN: "6b4a2e", K.AMBER: "e0a030",
	K.LIME: "9fd24a", K.GUNMETAL: "4a4e47", K.SMOKE_WHITE: "c9ccc8", K.SAND: "c2ab7f", K.CREAM: "efe6cc",
	K.SALINE: "9cc6da",  # saline in a bag (TreatProps), against the bag's milky plastic
}
## Smoke grenade band colours by smoke_colour.
const SMOKE_BANDS := {"white": K.SMOKE_WHITE, "green": K.GREEN, "yellow": K.YELLOW, "blue": K.BLUE, "purple": K.PURPLE}
## IV catheter hub colours by gauge (the usual colour code; 10 and 12 G vary by maker).
const GAUGE_COLOURS := {10: K.BROWN, 12: K.TEAL, 14: K.ORANGE, 16: K.GREY, 18: K.GREEN, 20: K.PINK}

static var _mesher: VoxelMesherCubes
static var _meshes: Dictionary = {}  # item id -> [Mesh, voxel size (m)]
static var _sizes: Dictionary = {}   # item id -> Vector3 (ground_size)


## The item's ground model: a holder whose children are the model, centred on its bounds (so
## a box of ground_size() round the holder's origin is the model's). `state` is the item's
## state: a rifle shows the optic its state mounts (VoxelArt.model_for, P0362).
static func ground_node(item: ItemData, state := {}) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Art"
	var model := _raw_node(item, state)
	holder.add_child(model)
	var bounds := _bounds(holder)
	model.position -= bounds.get_center()
	_sizes[_key(item, state)] = bounds.size
	return holder


## The size (metres) of what ground_node() shows for `item` (with `state`), as it rests.
static func ground_size(item: ItemData, state := {}) -> Vector3:
	var key := _key(item, state)
	if not _sizes.has(key):
		ground_node(item, state).free()
	return _sizes[key]


## The turn an item spawned in the world (CompoundLevel._make_item) starts with, so it lies as
## it would come to rest: a plate flat on its back, strike face up (its VoxelArmor piece is
## upright, and it stood on its edge). Everything else is modelled lying already.
static func spawn_rotation(item: ItemData) -> Vector3:
	return ON_BACK if item != null and item.type == "plate" else Vector3.ZERO


## What the size cache is keyed by: the item id, plus the VoxelArt model (a rifle's names its
## optic, so the same rifle with another optic is its own entry).
static func _key(item: ItemData, state: Dictionary) -> String:
	return "%s|%s" % [item.id, VoxelArt.model_for(item, state)]


## The model in its resting pose, not yet centred.
static func _raw_node(item: ItemData, state := {}) -> Node3D:
	var art := VoxelArt.model_for(item, state)
	if art != "" and not _own_weapon(item):
		var turn := Vector3.ZERO  # an optic sits on its mount, upright
		if item.type == "weapon":
			turn = ON_SIDE
		elif item.slot == &"backpack":
			turn = ON_STRAPS
		elif not Optics.is_optic(item):
			turn = ON_BACK
		var model := VoxelArt.instance(art, "multicam")
		model.rotation = turn
		if item.slot == &"vest":
			model.scale = Vector3(1, 1, VEST_SLUMP)  # nobody in it: the front panel sags onto the back
		return model
	if Inventory.is_attachable(item) and item.type != "launcher" and not _has_own(item):
		var pouch := GearRig.pouch_node(item, Color(VoxelArt.VARIANTS.multicam.gear).darkened(0.12), false)
		pouch.rotation = ON_BACK  # lying on its back, flap up
		return pouch
	var entry: Array = _mesh_for(item)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = entry[0]
	mesh_instance.material_override = VoxelArt._get_material()
	mesh_instance.scale = Vector3.ONE * float(entry[1])
	return mesh_instance


## Whether ItemArt builds `item`'s model itself (attachables that aren't plain pouches).
static func _has_own(item: ItemData) -> bool:
	return item.id == &"aid_bag"


## A gun whose ground model is ItemArt's own, not VoxelArt's carried one (the shotgun: VoxelArt
## has no shotgun silhouette yet, so carried it shows as a rifle until the Captain's side adds one).
static func _own_weapon(item: ItemData) -> bool:
	return item.type == "weapon" and String(item.stats.get("model_style", "")) == "shotgun"


## `item`'s own model (not VoxelArt's) as [mesh, metres per mesh unit, where its Shape's origin
## is (cm), its size (cm)]: LauncherRig draws a launcher in the hands with the one on the ground.
static func own_mesh(item: ItemData) -> Array:
	return _mesh_for(item)


static func _mesh_for(item: ItemData) -> Array:
	if not _meshes.has(item.id):
		var spec := _spec_for(item)
		var buffer := VoxelArt._rasterize(spec, "multicam", String(item.id).hash())
		_meshes[item.id] = [_get_mesher().build_mesh(buffer, []), float(spec.voxel), spec.get("origin_cm", Vector3.ZERO), Vector3(spec.size) * float(spec.voxel) * 100.0]
	return _meshes[item.id]


static func _get_mesher() -> VoxelMesherCubes:
	if _mesher == null:
		var base := VoxelArt._get_mesher("multicam").palette
		var palette := VoxelColorPalette.new()
		for i in VoxelArt.C.size():
			palette.set_color(i, base.get_color(i))
		for k: int in COLOURS:
			palette.set_color(k, Color(COLOURS[k]))
		_mesher = VoxelMesherCubes.new()
		_mesher.palette = palette
		_mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
	return _mesher


## Bounds of every mesh under `root`, in root's space (it need not be in the tree).
static func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var node: Node = mesh_instance
		while node != root and node is Node3D:
			xform = (node as Node3D).transform * xform
			node = node.get_parent()
		var box := xform * mesh_instance.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


# --- Model specs ------------------------------------------------------------------------
# Written in centimetres, lying as they rest: x across, y up, z along. Shape turns them into a
# VoxelArt spec at 0.5 cm (1 cm for the big ones) and trims it to its bounds.

static func _spec_for(item: ItemData) -> Dictionary:
	var id := String(item.id)
	var s: Shape
	match id:
		"mag_556": s = _magazine(6.4, 18.0, 2.4, 1.6, VoxelArt.C.GUN_LIGHT, 1.3)
		"mag_762": s = _magazine(7.4, 13.5, 2.8, 0.5, VoxelArt.C.GUN, 1.6)
		"mag_9mm": s = _magazine(3.2, 12.5, 2.3, 0.0, VoxelArt.C.GUN, 1.0)
		"mag_762x39": s = _magazine(7.0, 14.0, 2.8, 3.5, VoxelArt.C.GUN, 1.5)
		"mag_545": s = _magazine(6.4, 13.0, 2.6, 3.0, VoxelArt.C.GUN_LIGHT, 1.3)
		"mag_rpk40": s = _magazine(7.0, 18.0, 2.8, 4.5, VoxelArt.C.GUN, 1.5)
		"mag_svd": s = _magazine(7.4, 9.0, 2.8, 0.5, VoxelArt.C.GUN, 1.6)
		"mag_45acp": s = _magazine(3.4, 11.0, 2.5, 0.0, VoxelArt.C.GUN, 1.1)
		"rounds_762x39": s = _rounds(3.9, 1.2, 1.6, Vector3(10, 5.5, 6.5), K.RED)
		"rounds_545": s = _rounds(3.9, 1.0, 1.3, Vector3(10, 5, 6), K.GREEN)
		"rounds_762x54r": s = _rounds(5.4, 1.3, 2.0, Vector3(11, 6, 7), K.RED)
		"belt_762x54r": s = _ammo_can(13, 17, 26, K.OD, true)
		"box_556": s = _ammo_can(12, 16, 24, K.OD, false)
		"belt_762x51": s = _ammo_can(13, 17, 26, K.OD_DARK, true)
		"rounds_556": s = _rounds(4.5, 1.0, 1.3, Vector3(10, 4.5, 6), K.GREEN)
		"rounds_762": s = _rounds(5.1, 1.2, 1.9, Vector3(11, 6, 7), K.RED)
		"rounds_9mm": s = _rounds(1.9, 1.0, 1.0, Vector3(8, 3, 6.5), K.BLUE)
		"rounds_45acp": s = _rounds(2.3, 1.1, 1.1, Vector3(8, 3, 6.5), K.ORANGE)
		# Items expansion (2026-10-20): the new magazines and rounds on the same builders.
		"mag_mp5": s = _magazine(3.4, 18.0, 2.3, 2.5, VoxelArt.C.GUN, 1.0)
		"mag_uzi", "mag_glock33": s = _magazine(3.0, 21.0, 2.3, 0.0, VoxelArt.C.GUN, 1.0)
		"mag_vityaz": s = _magazine(3.4, 18.0, 2.4, 2.0, VoxelArt.C.GUN, 1.0)
		"mag_9x18", "mag_tt33": s = _magazine(3.0, 10.0, 2.2, 0.0, VoxelArt.C.GUN, 1.0)
		"mag_57_pistol": s = _magazine(3.2, 13.0, 2.2, 0.0, VoxelArt.C.GUN, 0.9)
		"mag_usp45": s = _magazine(3.4, 12.0, 2.6, 0.0, VoxelArt.C.GUN, 1.1)
		"mag_ump45": s = _magazine(3.6, 20.0, 2.8, 0.0, VoxelArt.C.GUN, 1.1)
		"mag_mp7": s = _magazine(2.8, 20.0, 2.2, 0.0, VoxelArt.C.GUN, 0.8)
		"mag_saiga12": s = _magazine(8.0, 16.0, 3.4, 1.0, VoxelArt.C.GUN, 2.0)
		"mag_m14": s = _magazine(7.4, 14.0, 2.8, 0.8, VoxelArt.C.GUN, 1.6)
		"mag_g3": s = _magazine(7.4, 14.0, 2.8, 1.2, VoxelArt.C.GUN, 1.6)
		"mag_fal", "mag_762_match": s = _magazine(7.4, 13.5, 2.8, 0.6, VoxelArt.C.GUN, 1.6)
		"mag_556_match": s = _magazine(6.4, 18.0, 2.4, 1.6, VoxelArt.C.GUN, 1.3)
		"mag_g36": s = _magazine(6.4, 18.0, 2.6, 2.0, K.DARK_GREY, 1.3)
		"mag_aug": s = _magazine(6.4, 17.0, 2.6, 1.8, K.CLEAR, 1.3)
		"mag_rpk74": s = _magazine(6.4, 21.0, 2.6, 4.5, VoxelArt.C.GUN_LIGHT, 1.3)
		"mag_vz58": s = _magazine(7.0, 14.0, 2.6, 3.0, K.GREY, 1.5)
		"rounds_9x18": s = _rounds(1.8, 1.0, 1.0, Vector3(8, 3, 6.5), K.GREY)
		"rounds_762x25": s = _rounds(2.5, 1.0, 1.0, Vector3(8, 3, 6.5), K.RED)
		"rounds_57x28": s = _rounds(2.9, 0.8, 1.0, Vector3(8, 3, 6.5), K.BLUE)
		"rounds_46x30": s = _rounds(3.0, 0.7, 0.9, Vector3(8, 3, 6.5), K.TEAL)
		"rounds_303": s = _rounds(5.6, 1.3, 2.0, Vector3(11, 6, 7), K.GREEN)
		"smartphone", "feature_phone": s = _phone()
		"laptop_civilian", "tablet_civilian": s = _laptop()
		"intel_id_cards", "intel_manifest", "intel_bank_slips", "intel_photos", "intel_letters": s = _documents()
		"circuit_board", "radio_parts", "capacitors", "graphics_card", "drone_parts": s = _electronics()
		"ear_comtac", "ear_sordin": s = _ear_protection()
		"belt_50bmg": s = _ammo_can(15, 19, 30, K.OD, true)
		"belt_127x108": s = _ammo_can(12, 17, 28, K.GUNMETAL, false)
		"at4": s = _at4()
		"rpg7": s = _rpg7()
		"javelin_clu": s = _javelin_clu()
		"maaws": s = _maaws()
		"nlaw": s = _nlaw()
		"smaw": s = _smaw()
		"pg7v_round": s = _pg7(false)
		"og7v_round": s = _pg7(true)
		"javelin_missile": s = _javelin_tube()
		"ffv551_round": s = _rounds_84(60, VoxelArt.C.GUN, K.YELLOW)
		"ffv441_round": s = _rounds_84(50, K.OD, K.YELLOW)
		"ffv502_round": s = _rounds_84(50, VoxelArt.C.GUN, K.RED)
		"smaw_hedp_round": s = _smaw_round(K.YELLOW)
		"smaw_ne_round": s = _smaw_round(K.ORANGE)
		"m320": s = _m320()
		"round_40mm_he": s = _grenade_40mm(K.OD, K.YELLOW)
		"round_40mm_smoke": s = _grenade_40mm(K.GREY_LIGHT, K.BLACK)
		"skeleton_key": s = _skeleton_key()
		"choke_870": s = _choke()
		"shells_12g_buck": s = _shells(K.RED)
		"shells_12g_hibrass": s = _shells(K.NAVY)
		"shells_12g_breach": s = _shells(K.ORANGE)
		"ifak": s = _ifak()
		"trauma_kit": s = _trauma_kit()
		"aid_bag": s = _aid_bag()
		"tourniquet": s = _tourniquet()
		"pressure_bandage": s = _flat_pack(Vector3(10, 2.5, 15), K.OD, K.WHITE, K.RED)
		"hemostatic_gauze": s = _flat_pack(Vector3(10, 1.5, 13), K.TAN, K.WHITE, K.ORANGE)
		"chest_seal": s = _flat_pack(Vector3(15, 1.0, 15), K.WHITE, K.BLACK, K.RED)
		"burn_dressing": s = _flat_pack(Vector3(12, 1.5, 16), K.WHITE, K.BLUE, K.TEAL)
		"splint": s = _splint()
		"pelvic_binder": s = _pelvic_binder()
		"morphine": s = _injector(K.OD, K.RED, K.YELLOW)
		"epinephrine": s = _injector(K.YELLOW, K.ORANGE, K.BLUE)
		"atropine": s = _injector(K.GREEN, K.YELLOW, K.WHITE)
		"adenosine": s = _syringe()
		"npa": s = _npa()
		"io_kit": s = _io_kit()
		"pressure_bag": s = _pressure_bag()
		"decompression_needle": s = _decompression_needle()
		"pulse_oximeter": s = _pulse_oximeter()
		"defibrillator": s = _defibrillator()
		"surgical_clamp": s = _clamp()
		"hypothermia_blanket": s = _foil_blanket()
		"ear_protection": s = _ear_protection()
		"frag_grenade", "grenade_rgd5", "grenade_f1", "grenade_m67": s = _frag()
		"flashbang", "flash_9bang": s = _flashbang()
		"breaching_charge": s = _breaching_charge()
		"electronics_salvage": s = _electronics()
		"radio": s = _radio(false)
		"enemy_radio": s = _radio(true)
		"binoculars": s = _binoculars()
		"zip_cuffs": s = _zip_cuffs()
		"intel_laptop", "intel_tablet": s = _laptop()
		"intel_phone", "intel_sat_phone": s = _phone()
		"intel_documents", "intel_marked_map", "intel_codebook", "intel_freq_list", "intel_passports", "intel_orders": s = _documents()
		"hvt_case": s = _hard_case()
		"supply_crate": s = _crate()
		"supply_pallet": s = _pallet()
		"jerrycan": s = _jerrycan()
		"spare_wheel", "truck_tyre": s = _wheel()
		"track_links": s = _track_links()
		"repair_kit": s = _toolbox()
		"vehicle_battery": s = _battery()
		"engine_parts": s = _engine_parts()
	if s == null:
		if id.begins_with("iv_"):
			s = _iv_catheter(int(item.stats.get("gauge", id.trim_prefix("iv_").to_int())))
		elif id.begins_with("saline_") or id.begins_with("blood_"):
			s = _fluid_bag(int(item.stats.get("ml", id.get_slice("_", 1).to_int())), id.begins_with("blood_"))
		elif id.begins_with("surgery_kit"):
			s = _surgery_kit(id.get_slice("_", 2).to_int())
		elif item.stats.has("smoke_colour") or id.begins_with("smoke"):
			s = _smoke(SMOKE_BANDS.get(String(item.stats.get("smoke_colour", "white")), K.SMOKE_WHITE))
	if s == null:
		s = _fallback(item)
	return s.spec()


## A bevelled box of the item's placeholder size and type colour, for items with no model yet.
static func _fallback(item: ItemData) -> Shape:
	var size := WorldItem.visual_size(item) * 100.0
	var s := Shape.new(0.5 if maxf(size.x, maxf(size.y, size.z)) < 50.0 else 1.0)
	var colour: int = K.GREY
	match item.type:
		"weapon", "launcher": colour = VoxelArt.C.GUN
		"ammo": colour = K.BRASS
		"armor", "plate": colour = K.OD
		"backpack": colour = VoxelArt.C.PACK
		"medical": colour = K.RED
		"utility": colour = K.NAVY
		"objective": colour = K.YELLOW
		"vehicle": colour = K.OD
		"intel": colour = K.MANILA
		"valuable": colour = K.GOLD
		"salvage": colour = K.COPPER
		"consumable": colour = K.OD
		"barter": colour = K.TAN
	var cut := minf(1.0, minf(size.x, minf(size.y, size.z)) * 0.25)
	s.prism(Axis.Z, 0, size.y * 0.5, size.x * 0.5, size.y * 0.5, cut, 0, size.z, colour)
	return s


# --- Ammunition -------------------------------------------------------------------------

## A magazine on its side: `depth` front to back (x, the rounds point to -x), `length` feed
## lips to baseplate (z), `thick` (y); it curves forward by `curve` cm at the bottom.
static func _magazine(depth: float, length: float, thick: float, curve: float, colour: int, bullet: float) -> Shape:
	var s := Shape.new()
	var steps := int(length)
	for i in steps:
		var t := float(i) / steps
		var off := curve * t * t
		s.b(off, 0, i, off + depth, thick, i + 1, colour)
		if i % 3 == 1:  # ribs along the body
			s.b(off + 0.5, thick - 0.1, i, off + depth - 0.5, thick + 0.4, i + 0.5, VoxelArt.C.GUN)
	var end := curve
	s.b(end - 0.4, -0.3, length - 0.5, end + depth + 0.6, thick + 0.3, length + 1.0, VoxelArt.C.GUN)  # baseplate
	s.b(0.4, 0.2, -0.8, depth - 0.6, thick - 0.2, 0, VoxelArt.C.GUN)  # feed lips
	s.b(bullet, thick * 0.25, -1.1, depth - 0.8, thick * 0.75, -0.2, K.BRASS)  # top round
	s.b(0.0, thick * 0.3, -1.0, bullet, thick * 0.7, -0.3, K.COPPER)
	return s


## Loose rounds: an opened carton (brass showing) with two rounds lying in front of it.
static func _rounds(case_len: float, dia: float, bullet: float, carton: Vector3, stripe: int) -> Shape:
	var s := Shape.new()
	s.b(0, 0, 0, carton.x, carton.y, carton.z, K.TAN)
	s.b(0.5, carton.y - 0.5, 0.5, carton.x - 0.5, carton.y, carton.z - 0.5, K.BRASS)  # the rounds' bases
	var rows := int((carton.z - 1.0) / dia)
	for r in range(1, rows):
		s.b(0.5, carton.y - 0.5, 0.5 + r * dia, carton.x - 0.5, carton.y, 0.5 + r * dia + 0.25, K.BROWN)
	s.b(-0.2, carton.y, 0, carton.x + 0.2, carton.y + 0.5, 0.5, K.TAN)  # the open lid's edge
	s.p(0, carton.y * 0.35, 0, carton.x, carton.y * 0.65, 0.5, stripe)  # label stripe on the front
	s.p(carton.x * 0.6, carton.y * 0.4, 0, carton.x * 0.9, carton.y * 0.6, 0.5, K.WHITE)
	for j in 2:
		var z0 := -1.2 - j * (dia + 0.8)
		var x0 := 0.5 + j * 2.0
		s.b(x0, 0, z0 - dia, x0 + case_len, dia, z0, K.BRASS)
		s.b(x0 + case_len, 0, z0 - dia, x0 + case_len + bullet * 0.6, dia, z0, K.COPPER)
		s.b(x0 + case_len + bullet * 0.6, dia * 0.25, z0 - dia * 0.75, x0 + case_len + bullet, dia * 0.75, z0 - dia * 0.25, K.COPPER)
	return s


## An ammo can (`w` x `h` x `l` cm) with its lid and latch, a carry handle when `handle`, and
## the belt hanging out over one side.
static func _ammo_can(w: float, h: float, l: float, body: int, handle: bool) -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, w * 0.5, h * 0.5, w * 0.5, h * 0.5, 0.5, 0, l, body)
	s.b(-0.3, h - 3.0, -0.3, w + 0.3, h - 0.5, l + 0.3, body)  # lid lip
	s.b(0.6, h - 0.5, 0.6, w - 0.6, h + 0.5, l - 0.6, body)    # lid top
	s.p(-0.3, h - 3.0, -0.3, w + 0.3, h - 2.5, l + 0.3, K.OD_DARK)
	s.b(w * 0.3, h - 6, l, w * 0.7, h - 0.5, l + 1.2, K.STEEL)  # latch
	if handle:
		s.b(w * 0.5 - 1.0, h + 0.5, l * 0.25, w * 0.5 + 1.0, h + 1.5, l * 0.75, K.BLACK)
	s.p(w - 0.5, h * 0.3, l * 0.15, w, h * 0.38, l * 0.85, K.YELLOW)  # stencil lines
	s.p(w - 0.5, h * 0.45, l * 0.15, w, h * 0.5, l * 0.6, K.YELLOW)
	for i in 6:  # the belt: rounds across it, hanging down the side
		var y := h - 2.5 - i * 1.9
		s.b(-1.5, y - 1.3, l * 0.25, -0.1, y, l * 0.25 + 7.5, K.BRASS)
		s.b(-1.3, y - 1.1, l * 0.25 + 7.5, -0.3, y - 0.2, l * 0.25 + 10.5, VoxelArt.C.GUN)
		s.b(-1.7, y - 1.5, l * 0.25 + 2.0, -0.1, y + 0.2, l * 0.25 + 3.0, K.DARK_GREY)  # link
	return s


## 84 mm recoilless round: nose, body, bands, aluminium case and base.
static func _rounds_84(length: float, nose: int, band: int) -> Shape:
	var s := Shape.new()
	var body := length * 0.45
	s.lathe(Axis.Z, 0, 0, [[0, 1.0], [3, 2.6], [10, 4.2], [body, 4.2]], nose)
	s.cyl(Axis.Z, 0, 0, 4.3, body, length - 2.0, K.GREY_LIGHT)
	s.cyl(Axis.Z, 0, 0, 4.6, length - 2.0, length, K.STEEL)
	s.cyl(Axis.Z, 0, 0, 1.2, length - 0.5, length, K.BRASS)
	s.cyl(Axis.Z, 0, 0, 5, body * 0.55, body * 0.55 + 1.5, band, true)
	s.cyl(Axis.Z, 0, 0, 5, body * 0.75, body * 0.75 + 0.8, band, true)
	return s


## RPG-7 rocket: PG-7V (anti-tank, big cone) or OG-7V (fragmentation, slim).
static func _pg7(frag: bool) -> Shape:
	var s := Shape.new()
	var keys := [[0, 1.0], [3, 2.4], [8, 3.5], [20, 3.5], [24, 2.0]] if frag \
		else [[0, 0.8], [2, 1.1], [20, 4.25], [30, 4.25], [34, 2.2]]
	var warhead_end: float = keys[-1][0]
	var motor_end := warhead_end + (16.0 if frag else 28.0)
	var total := 60.0 if frag else 93.0
	s.lathe(Axis.Z, 0, 0, keys, K.OD_DARK if frag else K.OD)
	s.cyl(Axis.Z, 0, 0, 1.2, 0, 2, K.STEEL)  # nose fuze
	if frag:
		for z: float in [10.0, 13.0, 16.0]:
			s.cyl(Axis.Z, 0, 0, 4, z, z + 0.5, K.OD, true)
	else:
		s.cyl(Axis.Z, 0, 0, 5, 24, 25.5, K.BLACK, true)
	s.cyl(Axis.Z, 0, 0, 2.0, warhead_end, motor_end, VoxelArt.C.GUN_LIGHT)
	s.b(-3.0, -0.25, motor_end - 10, 3.0, 0.25, motor_end, VoxelArt.C.GUN)  # folded fins
	s.b(-0.25, -3.0, motor_end - 10, 0.25, 3.0, motor_end, VoxelArt.C.GUN)
	s.cyl(Axis.Z, 0, 0, 2.5, motor_end, total, K.KHAKI)  # booster charge
	s.cyl(Axis.Z, 0, 0, 2.7, total - 1.5, total, K.BROWN)
	return s


## Javelin missile in its launch tube: end caps, carry handle, battery unit, live band.
static func _javelin_tube() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 7, 0, 120, K.OD)
	s.cyl(Axis.Z, 0, 0, 7.6, 0, 5, K.TAN)
	s.cyl(Axis.Z, 0, 0, 7.6, 115, 120, K.TAN)
	s.cyl(Axis.Z, 0, 0, 8, 20, 21.5, K.YELLOW, true)
	s.b(-1, 6.5, 50, 1, 9.5, 52, K.BLACK)  # carry handle
	s.b(-1, 6.5, 68, 1, 9.5, 70, K.BLACK)
	s.b(-1, 8.5, 50, 1, 9.5, 70, K.BLACK)
	s.b(-3, -10, 106, 3, -6, 115, VoxelArt.C.GUN)  # battery coolant unit
	s.b(4.5, -1, 30, 7.5, 1, 45, K.WHITE, true)  # stencil
	return s


## SMAW encased round: its launch tube with caps and a coupler, banded by kind.
static func _smaw_round(band: int) -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 5.5, 0, 70, K.OD_DARK)
	s.cyl(Axis.Z, 0, 0, 6, 0, 4, K.BLACK)
	s.cyl(Axis.Z, 0, 0, 6, 66, 70, K.BLACK)
	s.cyl(Axis.Z, 0, 0, 6.5, 10, 12.5, band, true)
	s.cyl(Axis.Z, 0, 0, 6.5, 15, 16, band, true)
	s.b(-1.5, 5, 56, 1.5, 7, 64, VoxelArt.C.GUN)  # coupler latch
	return s


## A 40 mm grenade (M406 HE, M714 smoke): the projectile's ogive nose first, its `body` colour
## and a marking band, in a short aluminium case with a rim.
static func _grenade_40mm(body: int, band: int) -> Shape:
	var s := Shape.new()
	s.lathe(Axis.Z, 0, 0, [[0, 0.6], [1.0, 1.3], [2.5, 1.9], [5.0, 2.0]], body)
	s.cyl(Axis.Z, 0, 0, 0.6, 0, 0.5, K.STEEL)  # the fuze's tip
	s.cyl(Axis.Z, 0, 0, 2.2, 3.0, 3.6, band, true)
	s.cyl(Axis.Z, 0, 0, 2.05, 4.8, 5.4, K.COPPER)  # rotating band
	s.cyl(Axis.Z, 0, 0, 2.1, 5.4, 10.0, K.SILVER)  # the case
	s.cyl(Axis.Z, 0, 0, 2.35, 9.6, 10.0, K.GREY)  # its rim
	s.cyl(Axis.Z, 0, 0, 0.5, 9.9, 10.1, K.BRASS)  # primer
	return s


## 12 gauge shells: an open carton with the brass heads showing, and two shells in front, the
## plastic hull in `hull` (red buckshot, green slugs, orange breaching rounds).
static func _shells(hull: int) -> Shape:
	var s := Shape.new()
	s.b(0, 0, 0, 11, 7, 9, K.TAN)
	s.b(0.5, 6.5, 0.5, 10.5, 7, 8.5, K.BRASS)  # the shells' heads
	for r in range(1, 4):
		s.b(0.5, 6.5, 0.5 + r * 2.0, 10.5, 7, 0.5 + r * 2.0 + 0.25, K.BROWN)
	s.p(0, 2.5, 0, 11, 4.5, 0.5, hull)  # label stripe in the shells' colour
	for j in 2:
		var z0 := -1.6 - j * 2.8
		var x0 := 0.5 + j * 2.5
		s.b(x0, 0, z0 - 2.0, x0 + 1.4, 2.0, z0, K.BRASS)  # head
		s.b(x0 + 1.4, 0, z0 - 2.0, x0 + 7.0, 2.0, z0, hull)  # hull
		s.b(x0 + 6.6, 0.4, z0 - 1.6, x0 + 7.0, 1.6, z0 - 0.4, K.DARK_GREY, true)  # crimp
	return s


# --- Under the barrel and the shotgun ---------------------------------------------------
# Muzzle at z = 0, lying on its side like the launchers: the bottom (grip) out to +x, the top
# (rail, sights) to -x.

## M320: a 40 mm barrel on a rail clamp, its breech and side-opening hinge, trigger guard and
## pistol grip, the folding leaf sight.
static func _m320() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 2.7, 0, 22, K.DARK_GREY)  # barrel
	s.ring(Axis.Z, 0, 0, 2.9, 2.1, 0, 1.0, VoxelArt.C.GUN)  # muzzle
	s.cyl(Axis.Z, 0, 0, 3.0, 22, 29, VoxelArt.C.GUN)  # breech
	s.b(-4.6, -1.6, 2, -2.6, 1.6, 28, VoxelArt.C.GUN)  # the rail clamp along its top
	s.b(-5.2, -1.2, 4, -4.6, 1.2, 27, K.BLACK)
	s.b(-0.8, 2.6, 21, 0.8, 3.6, 29, VoxelArt.C.GUN)  # hinge
	s.b(2.8, -0.4, 21, 6.0, 0.4, 22, VoxelArt.C.GUN)  # trigger guard
	s.b(5.6, -0.4, 21, 6.0, 0.4, 25.5, VoxelArt.C.GUN)
	s.b(2.8, -0.3, 23, 4.6, 0.3, 23.8, K.BLACK)  # trigger
	s.b(2.8, -1.4, 25.5, 11, 1.4, 29, K.RUBBER)  # pistol grip
	s.b(-6.8, -0.3, 13, -5.2, 0.3, 14, K.BLACK)  # folded leaf sight
	s.b(-6.0, -1.4, 13, -5.2, 1.4, 14, K.BLACK)
	return s


## The Skeleton Key: a cut-down pump 12 gauge for under a rifle's rail, its toothed standoff
## muzzle (pressed to a door), the barrel over a short three-shell tube, the pump, a small
## receiver and the rail clamp along its top. Lying on its side like the M320 (grip to +x).
static func _skeleton_key() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 1.1, 0, 30, VoxelArt.C.GUN)  # barrel
	s.ring(Axis.Z, 0, 0, 1.6, 0.9, -3.0, 0, K.DARK_GREY)  # standoff muzzle
	for y: float in [-1.7, 1.2]:
		s.b(-1.7, y, -3.0, -0.9, y + 0.5, -2.0, K.BLACK, true)  # its teeth
		s.b(0.9, y, -3.0, 1.7, y + 0.5, -2.0, K.BLACK, true)
	s.cyl(Axis.Z, 2.4, 0, 1.2, 4, 30, VoxelArt.C.GUN)  # tube magazine
	s.prism(Axis.Z, 2.0, 0, 2.3, 2.0, 0.6, 10, 22, K.BLACK)  # the pump
	for z: float in [12.0, 15.0, 18.0]:
		s.b(4.1, -2.0, z, 4.4, 2.0, z + 1.0, K.DARK_GREY, true)
	s.b(-1.6, -1.5, 30, 3.6, 1.5, 42, VoxelArt.C.GUN)  # receiver
	s.b(-4.0, -1.6, 4, -1.4, 1.6, 40, VoxelArt.C.GUN)  # the rail clamp along its top
	s.b(-4.6, -1.2, 6, -4.0, 1.2, 38, K.BLACK)
	s.b(3.6, -0.4, 33, 6.0, 0.4, 34, VoxelArt.C.GUN)  # trigger guard
	s.b(3.6, -0.25, 35, 5.0, 0.25, 35.8, K.BLACK)  # trigger
	return s


## A shotgun choke tube: a short ported steel cylinder with its knurled collar.
static func _choke() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 1.4, 0, 7, K.STEEL)
	s.ring(Axis.Z, 0, 0, 1.7, 1.0, 0, 1.5, K.GUNMETAL)  # collar
	for z: float in [3.0, 4.6]:
		s.b(-1.5, -0.3, z, 1.5, 0.3, z + 0.6, K.BLACK, true)  # ports
	return s


## The pump shotgun: barrel over its tube magazine with a clamp, a crenellated breaching muzzle,
## the pump, the receiver with its port and a side saddle of red shells, ghost-ring sights, and
## a stock with a recoil pad.
static func _shotgun() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, -1.2, 0, 1.1, 0, 47, VoxelArt.C.GUN)  # barrel
	s.ring(Axis.Z, -1.2, 0, 1.5, 0.9, -2.5, 0, VoxelArt.C.GUN)  # breaching muzzle
	for y: float in [-1.6, 1.1]:
		s.b(-1.6, y, -2.5, -0.8, y + 0.5, -1.6, K.DARK_GREY, true)  # its teeth
	s.cyl(Axis.Z, 1.5, 0, 1.2, 4, 47, VoxelArt.C.GUN)  # tube magazine
	s.b(-2.4, -1.3, 4, 2.8, 1.3, 6, VoxelArt.C.GUN)  # its clamp
	s.prism(Axis.Z, 1.0, 0, 2.4, 2.1, 0.7, 24, 42, K.BLACK)  # the pump
	for z: float in [26.0, 29.0, 32.0, 35.0, 38.0]:
		s.b(3.2, -2.2, z, 3.5, 2.2, z + 1.0, K.DARK_GREY, true)
	s.b(-2.6, -1.6, 47, 3.0, 1.6, 70, VoxelArt.C.GUN)  # receiver
	s.p(-1.8, 1.4, 51, 0.2, 1.6, 59, K.DARK_GREY)  # ejection port
	s.b(-1.6, 1.6, 49, 2.0, 2.2, 58, K.BLACK)  # side saddle
	for z: float in [49.5, 51.8, 54.1, 56.4]:
		s.b(-1.2, 2.2, z, 1.6, 2.6, z + 1.8, K.RED)  # its shells
	s.b(-2.2, -0.3, 0.8, -1.4, 0.3, 1.5, K.SILVER)  # front bead
	s.ring(Axis.Z, -3.4, 0, 0.9, 0.5, 63, 63.6, K.BLACK)  # ghost ring
	s.b(-2.6, -0.5, 62.5, -2.5, 0.5, 64, K.BLACK)
	s.b(-2.9, -0.4, 62.5, -2.5, 0.4, 64, K.BLACK)
	s.b(3.0, -0.4, 59, 5.2, 0.4, 60, VoxelArt.C.GUN)  # trigger guard
	s.b(4.8, -0.4, 59, 5.2, 0.4, 66, VoxelArt.C.GUN)
	s.b(3.0, -0.25, 62, 4.4, 0.25, 62.8, K.BLACK)  # trigger
	s.b(-2.2, -1.6, 70, 4.5, 1.6, 81, K.BLACK)  # stock
	s.b(-2.2, -1.6, 81, 7.5, 1.6, 93, K.BLACK)
	s.b(-2.6, -1.9, 93, 7.9, 1.9, 95, K.RUBBER)  # recoil pad
	return s


# --- Launchers --------------------------------------------------------------------------
# Muzzle at z = 0. The ones with grips lie on their side: grips out to +x.

static func _at4() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 5, 0, 102, K.KHAKI)
	s.cyl(Axis.Z, 0, 0, 5.6, 0, 5, K.OD_DARK)      # front shock cap
	s.cyl(Axis.Z, 0, 0, 3.6, 0, 0.5, K.BLACK)
	s.cyl(Axis.Z, 0, 0, 5.8, 94, 102, K.OD_DARK)   # venturi end
	s.cyl(Axis.Z, 0, 0, 4.0, 101.5, 102, K.BLACK)
	s.cyl(Axis.Z, 0, 0, 6, 9, 10.5, K.YELLOW, true)
	s.cyl(Axis.Z, 0, 0, 6, 30, 31, K.OD_DARK, true)
	s.cyl(Axis.Z, 0, 0, 6, 70, 71, K.OD_DARK, true)
	s.b(-1, 4.5, 22, 1, 7.5, 25, K.OD_DARK)         # front sight
	s.b(-1.5, 4.5, 60, 1.5, 7.5, 64, K.OD_DARK)     # rear sight
	s.b(-1.2, 4.5, 66, 1.2, 6.5, 74, K.BLACK)       # cocking lever
	s.b(-0.6, 6.5, 72, 0.6, 8, 74, K.BLACK)
	s.b(4.5, -1, 54, 7, 1.5, 60, K.BLACK)           # trigger
	s.b(-2.5, -7, 74, 2.5, -4.5, 84, K.BLACK)       # shoulder stop
	s.b(-5.6, -1, 36, -4.5, 1, 56, K.WHITE, true)   # stencil
	return s


static func _rpg7() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 2.4, 0, 82, K.DARK_GREY)
	s.cyl(Axis.Z, 0, 0, 2.9, 0, 2, VoxelArt.C.GUN)   # muzzle ring
	s.cyl(Axis.Z, 0, 0, 1.9, 0, 0.5, K.BLACK)
	s.cyl(Axis.Z, 0, 0, 3.3, 38, 62, K.WOOD)          # wooden heat guards
	for z: float in [43.0, 49.0, 55.0]:
		s.cyl(Axis.Z, 0, 0, 3.5, z, z + 0.5, K.WOOD_DARK, true)
	s.lathe(Axis.Z, 0, 0, [[80, 2.4], [86, 3.2], [95, 5.0]], VoxelArt.C.GUN)  # venturi flare
	s.cyl(Axis.Z, 0, 0, 3.8, 94.5, 95, K.BLACK)
	s.b(2.2, -1.2, 64, 9.5, 1.2, 67.5, K.WOOD_DARK)    # pistol grip
	s.b(2.2, -0.4, 59.5, 6.0, 0.4, 60.0, VoxelArt.C.GUN)  # trigger guard
	s.b(5.5, -0.4, 59.5, 6.0, 0.4, 64, VoxelArt.C.GUN)
	s.b(2.2, -0.3, 61.5, 4.5, 0.3, 62.3, VoxelArt.C.GUN)  # trigger
	s.b(-9, -1.8, 44, -3.5, 1.8, 56, VoxelArt.C.GUN)     # PGO-7 sight
	s.b(-8.5, -1.4, 56, -5.0, 1.4, 59, K.RUBBER)
	s.b(-8.6, -1.2, 43.5, -5.5, 1.2, 44, VoxelArt.C.LENS)
	s.b(-3.5, -1, 47, -2.2, 1, 53, VoxelArt.C.GUN)
	s.b(-0.3, 2.2, 6, 0.3, 4.2, 7, VoxelArt.C.GUN)     # front sight post
	return s


static func _javelin_clu() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 7, 0, 120, K.OD)
	s.cyl(Axis.Z, 0, 0, 7.6, 0, 5, K.TAN)
	s.cyl(Axis.Z, 0, 0, 7.6, 115, 120, K.TAN)
	s.b(-10, 6.5, 46, 10, 21, 76, K.OD_DARK)         # command launch unit
	s.b(-8, 9.5, 45.5, 1, 19, 46, VoxelArt.C.LENS)    # day sight
	s.b(3, 12, 45.5, 7.5, 17, 46, VoxelArt.C.LENS)    # thermal
	s.b(-4.5, 11, 76, 4.5, 18, 81, K.RUBBER)          # eyepiece
	s.b(-13, 9, 57, -10, 19, 62, K.BLACK)             # handles
	s.b(10, 9, 57, 13, 19, 62, K.BLACK)
	s.b(-6, 21, 52, 6, 22, 70, K.OD)
	s.b(-3, -10, 106, 3, -6, 115, VoxelArt.C.GUN)     # battery coolant unit
	return s


static func _maaws() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 5, 0, 88, K.GUNMETAL)
	s.cyl(Axis.Z, 0, 0, 5.5, 0, 3, VoxelArt.C.GUN)
	s.cyl(Axis.Z, 0, 0, 4.2, 0, 0.5, K.BLACK)
	s.lathe(Axis.Z, 0, 0, [[86, 5.0], [92, 5.6], [100, 6.6]], VoxelArt.C.GUN)  # venturi
	s.cyl(Axis.Z, 0, 0, 4.6, 99.5, 100, K.BLACK)
	s.b(4.8, -1.2, 22, 12, 1.2, 25.5, VoxelArt.C.GUN)   # front grip
	s.b(4.8, -1.2, 48, 12, 1.2, 51.5, VoxelArt.C.GUN)   # firing grip
	s.b(4.8, -0.4, 44.5, 8.5, 0.4, 45, VoxelArt.C.GUN)
	s.b(4.8, -2.5, 64, 8, 2.5, 80, K.RUBBER)           # shoulder piece
	s.b(-10, -1.8, 36, -5, 1.8, 52, VoxelArt.C.GUN)     # sight
	s.b(-9.5, -1.4, 52, -6, 1.4, 55, K.RUBBER)
	s.b(-9.5, -1.2, 35.5, -6.5, 1.2, 36, VoxelArt.C.LENS)
	return s


static func _nlaw() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 0, 0, 6, 7, 2, 6, 94, K.OD)
	s.prism(Axis.Z, 0, 0, 7, 8, 2.5, 0, 8, K.DARK_GREY)    # front cap
	s.prism(Axis.Z, 0, 0, 7, 8, 2.5, 94, 102, K.DARK_GREY)
	s.b(-3, 7, 50, 3, 12, 68, K.OD_DARK)                    # sight
	s.b(-2, 8, 68, 2, 11, 71, K.RUBBER)
	s.b(-2, 8, 49.5, 2, 11, 50, VoxelArt.C.LENS)
	s.b(-2, -10, 55, 2, -7, 72, K.BLACK)                    # folded grip
	s.prism(Axis.Z, 0, 0, 7, 8, 2, 14, 15.5, K.YELLOW, true)
	s.b(-6.5, -2, 30, -5.5, 2, 46, K.WHITE, true)           # stencil
	return s


static func _smaw() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 4.2, 0, 70, K.OD)
	s.cyl(Axis.Z, 0, 0, 4.8, 0, 4, K.DARK_GREY)
	s.cyl(Axis.Z, 0, 0, 3.4, 0, 0.5, K.BLACK)
	s.lathe(Axis.Z, 0, 0, [[66, 4.2], [70, 5.0], [76, 5.0]], K.DARK_GREY)
	s.cyl(Axis.Z, 0, 0, 4.0, 75.5, 76, K.BLACK)
	s.cyl(Axis.Z, 0, 6.2, 1.1, 6, 60, VoxelArt.C.GUN)       # spotting rifle on top
	s.b(-1, 3.8, 20, 1, 5.5, 24, VoxelArt.C.GUN)
	s.b(-1, 3.8, 48, 1, 5.5, 52, VoxelArt.C.GUN)
	s.b(4, -1.2, 26, 11, 1.2, 29.5, VoxelArt.C.GUN)         # grips
	s.b(4, -1.2, 44, 11, 1.2, 47.5, VoxelArt.C.GUN)
	s.b(-10, -1.8, 38, -4, 1.8, 54, VoxelArt.C.GUN)         # sight
	s.b(-9.5, -1.4, 54, -5.5, 1.4, 57, K.RUBBER)
	s.b(-9.5, -1.2, 37.5, -6.0, 1.2, 38, VoxelArt.C.LENS)
	return s


# --- Medical ----------------------------------------------------------------------------

## A red cross painted on the top face (y = top) centred at (cx, cz), `arm` long.
static func _cross(s: Shape, cx: float, top: float, cz: float, arm: float, colour: int) -> void:
	var t := maxf(arm * 0.33, 0.5)
	s.p(cx - arm, top - 0.5, cz - t, cx + arm, top, cz + t, colour)
	s.p(cx - t, top - 0.5, cz - arm, cx + t, top, cz + arm, colour)


static func _ifak() -> Shape:
	var s := Shape.new()
	var gear := VoxelArt.C.GEAR
	s.prism(Axis.Z, 9, 4.5, 9, 4.5, 1.5, 0, 13, gear)
	s.b(-0.3, 4, -0.3, 18.3, 5, 13.3, VoxelArt.C.GEAR_DARK)     # zip seam
	s.p(-0.3, 4.4, -0.3, 18.3, 4.6, 13.3, K.BLACK)
	s.b(2.5, 9, 3, 15.5, 9.5, 10, K.RED)                         # patch
	_cross(s, 9, 9.5, 6.5, 2.4, K.WHITE)
	s.b(1, 7, -1.5, 3, 9, 0, K.RED)                               # pull tabs
	s.b(15, 7, -1.5, 17, 9, 0, K.RED)
	for z: float in [2.0, 6.0, 10.0]:
		s.b(18, 1, z, 18.5, 7, z + 2, VoxelArt.C.GEAR_DARK)        # MOLLE straps
	return s


static func _trauma_kit() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 17, 7.5, 17, 7.5, 2.5, 0, 24, K.RED)
	s.b(-0.3, 7, -0.3, 34.3, 8, 24.3, K.RED_DARK)
	s.p(-0.3, 7.3, -0.3, 34.3, 7.7, 24.3, K.BLACK)               # zip
	s.b(10, 15, 6, 24, 15.5, 18, K.WHITE)
	_cross(s, 17, 15.5, 12, 4.5, K.RED)
	s.b(14, 15, -2.5, 20, 17, 0.5, K.BLACK)                      # handle
	s.b(14, 15, 23.5, 20, 17, 26.5, K.BLACK)
	s.b(1, 3, 24, 9, 12, 25.5, K.RED_DARK)                       # end pocket
	s.b(25, 3, 24, 33, 12, 25.5, K.RED_DARK)
	return s


## M9-style aid bag on its back: main bag, lid zip, two front pockets, a cross patch, the
## carry handle and the folded shoulder strap.
static func _aid_bag() -> Shape:
	var s := Shape.new()
	var gear := VoxelArt.C.GEAR
	var dark := VoxelArt.C.GEAR_DARK
	s.prism(Axis.Z, 15, 6.5, 15, 6.5, 2.5, 0, 34, gear)
	s.b(-0.3, 9, -0.3, 30.3, 10, 34.3, dark)
	s.p(-0.3, 9.3, -0.3, 30.3, 9.7, 34.3, K.BLACK)
	s.prism(Axis.Z, 8, 14.5, 6, 2, 1.2, 4, 18, gear)            # front pockets
	s.prism(Axis.Z, 22, 14.5, 6, 2, 1.2, 4, 18, gear)
	s.b(2, 15.5, 4, 14, 16.5, 7, dark)
	s.b(16, 15.5, 4, 28, 16.5, 7, dark)
	s.b(9, 13, 21, 21, 13.5, 31, K.RED)                           # patch
	_cross(s, 15, 13.5, 26, 3.6, K.WHITE)
	s.b(11, 12, -2.5, 19, 14, 0.5, K.BLACK)                       # handle
	s.b(-1.5, 3, 4, 0, 11, 30, dark)                              # strap folded on the side
	for z: float in [6.0, 14.0, 22.0]:
		s.b(30, 2, z, 30.5, 10, z + 3, dark)
	return s


## A CAT-style tourniquet lying flat: the band's loop, the windlass rod and its clip, the
## red tab and the white time strap.
static func _tourniquet() -> Shape:
	var s := Shape.new()
	s.frame(0, 0, 15, 6, 0, 0.8, 1.8, K.BLACK)                   # the band, looped
	s.b(-4, 0, 1.5, 0, 0.6, 4.5, K.BLACK)                         # free end
	s.b(-6, 0, 1.5, -4, 0.8, 4.5, K.RED)                          # red tip
	s.b(4, 0.8, -1.5, 5.2, 2.0, 7.5, K.BLACK)                     # windlass rod
	s.b(6.5, 0.8, 0.5, 10.5, 1.6, 5.5, K.DARK_GREY)               # clip
	s.b(11.5, 0.8, 0, 14, 1.3, 6, K.WHITE)                        # time strap
	return s


## A vacuum-packed dressing: `size`, body colour, label and stripe.
static func _flat_pack(size: Vector3, body: int, label: int, stripe: int) -> Shape:
	var s := Shape.new()
	var cut := minf(1.0, size.y * 0.5)
	s.prism(Axis.Z, size.x * 0.5, size.y * 0.5, size.x * 0.5, size.y * 0.5, cut, 0, size.z, body)
	s.b(0.2, 0, -0.8, size.x - 0.2, 0.5, 0, body)                # sealed ends
	s.b(0.2, 0, size.z, size.x - 0.2, 0.5, size.z + 0.8, body)
	s.p(size.x * 0.15, size.y - 0.5, size.z * 0.2, size.x * 0.85, size.y, size.z * 0.55, label)
	s.p(0, size.y - 0.5, size.z * 0.65, size.x, size.y, size.z * 0.75, stripe)
	s.p(size.x * 0.25, size.y - 0.5, size.z * 0.3, size.x * 0.75, size.y, size.z * 0.36, K.DARK_GREY)
	return s


## A SAM-style splint rolled up: orange outside, a blue edge spiral, a strap round it.
static func _splint() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.X, 4.5, 4.5, 4.5, 0, 11, K.ORANGE)
	s.ring(Axis.X, 4.5, 4.5, 3.4, 2.4, -0.01, 11.01, K.BLUE)
	s.cyl(Axis.X, 4.5, 4.5, 1.4, -0.01, 11.01, K.BLUE)
	s.cyl(Axis.X, 4.5, 4.5, 2.4, -0.01, 11.01, K.ORANGE, true)
	s.cyl(Axis.X, 4.5, 4.5, 1.4, -0.01, 11.01, K.BLUE, true)
	s.cyl(Axis.X, 4.5, 4.5, 4.9, 4.5, 6.5, K.BLACK)               # strap
	return s


static func _pelvic_binder() -> Shape:
	var s := Shape.new()
	for i in 3:  # the folded band
		s.b(i * 0.6, i * 1.3, i * 0.6, 26 - i * 0.6, i * 1.3 + 1.3, 11 - i * 0.6, K.BLACK if i % 2 == 0 else K.DARK_GREY)
	s.b(10, 3.9, 2, 16, 5, 9, K.GREY)                             # buckle
	s.b(11.5, 4.5, 3.5, 14.5, 5, 7.5, K.DARK_GREY)
	s.b(-2.5, 0, 3, 0, 1.3, 8, K.BLUE)                            # pull handles
	s.b(26, 0, 3, 28.5, 1.3, 8, K.BLUE)
	return s


## An autoinjector pen lying along z: body, safety cap, tip, a label band.
static func _injector(body: int, tip: int, cap: int) -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 1.2, 0, 13, body)
	s.cyl(Axis.Z, 0, 0, 1.25, 0, 2.5, tip)
	s.cyl(Axis.Z, 0, 0, 1.0, 13, 15.5, cap)
	s.cyl(Axis.Z, 0, 0, 1.5, 5, 9, K.WHITE, true)
	s.b(-0.3, 1.0, 6, 0.3, 1.5, 8, K.BLACK, true)
	return s


static func _syringe() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 0.8, 0, 7, K.CLEAR)                     # barrel
	s.cyl(Axis.Z, 0, 0, 0.5, 1, 6, K.RED, true)                  # the drug in it
	s.b(-1.5, -0.5, 7, 1.5, 0.5, 7.5, K.WHITE)                   # finger flange
	s.cyl(Axis.Z, 0, 0, 0.4, 7.5, 11, K.WHITE)                   # plunger
	s.cyl(Axis.Z, 0, 0, 0.9, 11, 11.5, K.WHITE)
	s.cyl(Axis.Z, 0, 0, 0.5, -3, 0, K.ORANGE)                    # needle cap
	return s


## A nasopharyngeal airway: soft curved tube with a flange.
static func _npa() -> Shape:
	var s := Shape.new()
	for i in 12:
		var off := 0.05 * i * i
		s.b(off, 0, i, off + 1.3, 1.3, i + 1, K.AMBER)
	s.b(-1.2, -0.2, -0.6, 2.5, 1.5, 0, K.AMBER)                  # flange
	s.b(0.3, 0.3, -0.7, 1.0, 1.0, 0, K.BROWN)                    # bore
	return s


## An IV catheter in its blister: a clear tray, the needle in its cover, the hub and wings in
## the gauge's colour code, the white flash plug.
static func _iv_catheter(gauge: int) -> Shape:
	var s := Shape.new()
	var hub: int = GAUGE_COLOURS.get(gauge, K.GREY)
	var r := 0.5 + 0.05 * maxi(20 - gauge, 0)  # bigger bore, fatter cover
	s.b(-2.5, 0, -1, 2.5, 0.5, 10, K.CLEAR)                       # the blister's tray
	s.p(-2.5, 0, 7.5, 2.5, 0.5, 10, K.WHITE)                       # its paper end
	s.cyl(Axis.Z, 0, 0.5 + r, r, 0, 4.5, K.CLEAR)                  # needle cover
	s.cyl(Axis.Z, 0, 0.5 + r, 0.3, 0.2, 4.3, K.STEEL, true)         # the needle in it
	s.cyl(Axis.Z, 0, 0.5 + r, r + 0.3, 4.5, 6.5, hub)              # hub
	s.b(-2.0, 0.5, 4.8, 2.0, 1.0, 6.0, hub)                        # wings
	s.cyl(Axis.Z, 0, 0.5 + r, r + 0.1, 6.5, 8.5, K.CLEAR)          # flash chamber
	s.cyl(Axis.Z, 0, 0.5 + r, r + 0.2, 8.5, 9.5, K.WHITE)          # flash plug
	return s


static func _io_kit() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 5, 2, 5, 2, 1, 0, 14, K.YELLOW)
	s.p(1, 3.5, 2, 9, 4, 6, K.CLEAR)                             # window
	s.cyl(Axis.Y, 5, 4, 1.5, 3.5, 4, K.RED, true)                # target patch in it
	s.b(1.5, 4, 8, 8.5, 5.5, 9.5, K.BLACK)                       # T-handle introducer
	s.b(4.3, 4, 9.5, 5.7, 5.5, 13, K.BLACK)
	s.p(0, 0.5, 14 - 0.5, 10, 3.5, 14, K.BLACK)
	return s


## An IV bag lying flat, `ml` sizing it: clear saline with a blue label, or blood (dark red,
## white label). Ports at one end, the hanger tab at the other.
static func _fluid_bag(ml: int, blood: bool) -> Shape:
	var s := Shape.new()
	var scale := pow(maxf(ml, 100) / 500.0, 1.0 / 3.0)
	var w := 12.0 * scale
	var l := 19.0 * scale
	var h := 2.4 * scale
	var body := K.BLOOD if blood else K.CLEAR
	s.prism(Axis.Z, w * 0.5, h * 0.5, w * 0.5, h * 0.5, h * 0.45, 0, l, body)
	s.b(0.3, 0, -1.2, w - 0.3, 0.5, 0, body)                     # sealed edges
	s.b(0.3, 0, l, w - 0.3, 0.5, l + 2.0, body)
	s.b(w * 0.4, 0, l + 0.8, w * 0.6, 0.5, l + 1.6, K.WHITE, true)  # hanger hole
	s.p(w * 0.15, h - 0.5, l * 0.2, w * 0.85, h, l * 0.7, K.WHITE if blood else K.BLUE)
	s.p(w * 0.25, h - 0.5, l * 0.3, w * 0.75, h, l * 0.36, K.DARK_GREY)
	s.cyl(Axis.Z, w * 0.35, 0.5, 0.45, -3.5, -1.2, K.WHITE)      # ports
	s.cyl(Axis.Z, w * 0.65, 0.5, 0.45, -3.0, -1.2, K.BLUE if blood else K.WHITE)
	return s


static func _pressure_bag() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 6.5, 1.5, 6.5, 1.5, 1.2, 0, 26, K.BLUE)
	s.p(1, 2.5, 3, 12, 3, 23, K.NAVY)
	s.cyl(Axis.Y, 3, -4.5, 2.2, 0, 2.6, K.WHITE)                 # gauge
	s.cyl(Axis.Y, 3, -4.5, 1.6, 2.1, 2.6, K.CREAM)
	s.b(2.9, 2.4, -5.6, 3.2, 2.7, -4.5, K.RED)
	s.b(2.6, 0.5, -2.4, 3.4, 1.2, 0, K.CLEAR)
	s.b(9.6, 0.4, -6, 10.4, 1.2, 0, K.CLEAR)                     # tube to the bulb
	s.cyl(Axis.Z, 10, 1.2, 1.4, -11, -6, K.BLACK)                # bulb
	return s


static func _decompression_needle() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 1.0, 0, 13, K.GREY_LIGHT)
	s.cyl(Axis.Z, 0, 0, 1.15, 13, 16, K.RED)
	s.cyl(Axis.Z, 0, 0, 1.3, 4, 9, K.WHITE, true)
	s.cyl(Axis.Z, 0, 0, 0.3, -1.5, 0, K.STEEL)
	return s


static func _pulse_oximeter() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 2, 1.8, 2, 1.8, 0.8, 0, 6, K.BLUE)
	s.b(0.4, 1.8, 0.5, 3.6, 3.5, 5.5, K.GREY_LIGHT)              # upper jaw
	s.p(0.8, 3.0, 1.0, 3.2, 3.5, 4.0, K.SCREEN)                  # display
	s.p(1.2, 3.0, 1.5, 1.6, 3.5, 2.5, K.LIME)
	s.p(2.2, 3.0, 1.5, 2.6, 3.5, 3.2, K.LIME)
	s.b(1.4, 1.2, 6, 2.6, 2.8, 7, K.DARK_GREY)                   # hinge
	return s


## An AED in its case, lying flat: case, grey face with the red heart, handle.
static func _defibrillator() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 12.5, 4, 12.5, 4, 2.0, 0, 28, K.YELLOW)
	s.p(2.5, 7.5, 3, 22.5, 8, 22, K.DARK_GREY)
	s.p(9, 7.5, 7, 16, 8, 13, K.RED)                              # heart
	s.p(10, 7.5, 13, 15, 8, 14.5, K.RED)
	s.p(12, 7.5, 9, 13, 8, 11.5, K.WHITE)                         # bolt
	s.p(11, 7.5, 10, 14, 8, 10.5, K.WHITE)
	s.cyl(Axis.Y, 18.5, 18, 1.5, 7.5, 8.2, K.GREEN)               # on button
	s.b(8, 2, -2.5, 17, 6, 0.3, K.BLACK)                          # handle
	s.b(9.5, 2.8, -1.5, 15.5, 5.2, 0.3, K.YELLOW, true)
	return s


## A hemostat lying flat: finger rings, shanks, box lock, jaws.
static func _clamp() -> Shape:
	var s := Shape.new()
	var steel := K.SILVER
	s.frame(-3.5, 0, -0.5, 3, 0, 0.5, 0.6, steel)                 # finger rings
	s.frame(0.5, 0, 3.5, 3, 0, 0.5, 0.6, steel)
	s.b(-1.4, 0, 3, -0.6, 0.5, 9, steel)                          # shanks
	s.b(0.6, 0, 3, 1.4, 0.5, 9, steel)
	s.b(-1, 0, 9, 1, 0.8, 10.5, K.STEEL)                          # box lock
	s.b(-0.5, 0, 10.5, 0.5, 0.5, 15, steel)                       # jaws
	s.b(-1.6, 0, 7.5, 1.6, 0.4, 8.2, K.STEEL)                     # ratchet
	return s


## A roll-up surgical kit; more uses, a bigger roll.
static func _surgery_kit(uses: int) -> Shape:
	var s := Shape.new()
	var k := 1.0 + 0.08 * maxi(uses - 2, 0)
	var w := 19.0 * k
	var l := 13.0 * k
	var h := 5.0 * k
	s.prism(Axis.Z, w * 0.5, h * 0.5, w * 0.5, h * 0.5, 1.5, 0, l, K.NAVY)
	s.b(-0.3, h * 0.5 - 0.4, -0.3, w + 0.3, h * 0.5 + 0.4, l + 0.3, K.BLACK)  # zip
	s.b(w * 0.15, h, l * 0.2, w * 0.55, h + 0.5, l * 0.8, K.WHITE)            # label
	s.p(w * 0.2, h, l * 0.35, w * 0.5, h + 0.5, l * 0.42, K.DARK_GREY)
	s.b(w * 0.62, h, l * 0.25, w * 0.9, h + 0.5, l * 0.75, K.RED)
	_cross(s, w * 0.76, h + 0.5, l * 0.5, 1.8, K.WHITE)
	for i in uses:  # one tab per use along the edge
		s.b(w, 0.5, 1.0 + i * (l - 2.0) / maxf(uses, 1), w + 0.8, h - 0.5, 1.0 + i * (l - 2.0) / maxf(uses, 1) + 1.2, K.RED)
	return s


static func _foil_blanket() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 7, 1.25, 7, 1.25, 0.8, 0, 20, K.SILVER)
	s.p(0, 1.5, 0, 14, 2.5, 20, K.GOLD)
	for z: float in [5.0, 10.0, 15.0]:
		s.p(0, 2.0, z, 14, 2.5, z + 0.5, K.AMBER)                    # fold lines
	s.p(4, 2.0, 1, 10, 2.5, 3.5, K.WHITE)
	return s


# --- Kit --------------------------------------------------------------------------------

static func _ear_protection() -> Shape:
	var s := Shape.new()
	for x: float in [3.5, 15.5]:  # the cups, lying flat
		s.cyl(Axis.Y, x, 4, 3.5, 0.8, 4.5, K.OD_DARK)
		s.cyl(Axis.Y, x, 4, 3.6, 0, 1.0, K.BLACK)                   # cushions
		s.cyl(Axis.Y, x, 4, 0.9, 4.5, 5.3, K.BLACK)                 # knobs
	s.b(1.5, 1.5, 7.5, 2.5, 3.0, 12, K.BLACK)                       # headband
	s.b(16.5, 1.5, 7.5, 17.5, 3.0, 12, K.BLACK)
	s.b(1.5, 1.5, 12, 17.5, 3.0, 13.5, K.BLACK)
	s.b(5, 3.0, 12, 14, 3.5, 13.5, K.OD_DARK)
	return s


## M67 frag on its side: body, yellow band, fuze, spoon, pin ring.
static func _frag() -> Shape:
	var s := Shape.new()
	s.lathe(Axis.Z, 0, 0, [[0, 1.4], [0.8, 2.5], [2.0, 3.2], [4.4, 3.2], [5.6, 2.6], [6.4, 1.6]], K.OD)
	s.cyl(Axis.Z, 0, 0, 3.4, 4.0, 4.6, K.YELLOW, true)
	s.cyl(Axis.Z, 0, 0, 1.3, 6.2, 8.0, K.GREY)                     # fuze
	s.b(-0.7, 1.4, 6.2, 0.7, 2.0, 8.2, K.GREY)                     # spoon
	s.b(-0.7, 2.0, 1.2, 0.7, 2.6, 6.8, K.GREY)
	s.b(-0.7, 2.6, 1.2, 0.7, 3.4, 4.2, K.GREY)
	s.frame(1.3, 6.4, 3.6, 8.7, -0.2, 0.3, 0.4, K.STEEL)           # pin ring
	return s


## M18-style smoke on its side: grey-green can, band and top in its colour, fuze and spoon.
static func _smoke(band: int) -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 3.1, 0, 11.5, K.OD if band != K.SMOKE_WHITE else K.GUNMETAL)
	s.cyl(Axis.Z, 0, 0, 3.3, 7.0, 9.5, band, true)
	s.cyl(Axis.Z, 0, 0, 3.0, 11.0, 11.5, band)
	s.cyl(Axis.Z, 0, 0, 1.3, 11.5, 13.3, K.GREY)                    # fuze
	s.b(-0.7, 1.3, 11.5, 0.7, 1.9, 13.5, K.GREY)                    # spoon
	s.b(-0.7, 2.9, 3.0, 0.7, 3.5, 11.5, K.GREY)
	s.frame(1.3, 11.7, 3.6, 14.0, -0.2, 0.3, 0.4, K.STEEL)
	s.b(-0.7, -0.7, -0.4, 0.7, 0.7, 0, K.BLACK)                     # emission holes
	return s


## M84-style flashbang: perforated steel tube, fuze, spoon, ring.
static func _flashbang() -> Shape:
	var s := Shape.new()
	s.cyl(Axis.Z, 0, 0, 2.2, 0, 12, K.GREY)
	for z: float in [2.0, 4.5, 7.0, 9.5]:
		s.b(-2.5, -0.4, z, 2.5, 0.4, z + 1.0, K.BLACK, true)       # holes round the tube
		s.b(-0.4, -2.5, z, 0.4, 2.5, z + 1.0, K.BLACK, true)
	s.cyl(Axis.Z, 0, 0, 1.2, 12, 13.6, K.STEEL)
	s.b(-0.6, 1.2, 12, 0.6, 1.7, 13.8, K.STEEL)
	s.b(-0.6, 2.2, 3, 0.6, 2.7, 12, K.STEEL)
	s.frame(1.2, 12.2, 3.4, 14.4, -0.2, 0.3, 0.4, K.SILVER)
	return s


## A breaching charge: plastic explosive taped to a board, det cord coiled on it, the
## detonator with its light.
static func _breaching_charge() -> Shape:
	var s := Shape.new()
	s.b(0, 0, 0, 30, 1.5, 12, K.WOOD)                              # board
	s.b(2, 1.5, 2, 24, 5, 10, K.OD)                                # charge
	for x: float in [5.0, 12.0, 19.0]:
		s.b(x, 1.5, 1.6, x + 2, 5.4, 10.4, K.BLACK)                 # tape
	s.frame(24.5, 2.5, 29.5, 9.5, 1.5, 2.3, 0.7, K.YELLOW)         # det cord coil
	s.frame(25.5, 3.5, 28.5, 8.5, 2.3, 3.1, 0.7, K.YELLOW)
	s.b(20, 5, 4, 26, 5.6, 4.8, K.YELLOW)
	s.b(10, 5, 5, 14, 7, 7, K.SILVER)                              # detonator
	s.b(11.5, 7, 5.5, 12.5, 7.8, 6.5, K.RED)
	return s


static func _electronics() -> Shape:
	var s := Shape.new()
	s.b(0, 0, 0, 14, 0.5, 10, K.PCB)                               # board
	s.b(2, 0.5, 2, 6, 1.2, 5, K.BLACK)                             # chips
	s.b(7.5, 0.5, 1.5, 9.5, 1.0, 3.5, K.BLACK)
	s.b(8, 0.5, 6, 12.5, 1.0, 8.5, K.SILVER)
	s.cyl(Axis.Y, 4, 7.5, 0.8, 0.5, 2.5, K.BLUE)                   # capacitors
	s.cyl(Axis.Y, 6, 7.5, 0.6, 0.5, 2.0, K.BLACK)
	s.b(11, 0.5, 2, 13, 1.5, 4, K.WHITE)                           # connector
	for i in 3:  # loose wires
		var colour: int = [K.RED, K.BLUE, K.YELLOW][i]
		s.b(14, 0, 2 + i, 18 + i, 0.5, 2.5 + i, colour)
		s.b(17.5 + i, 0, 2.5 + i, 18 + i, 0.5, 6 + i, colour)
	s.b(-4, 0, 3, 0, 2.5, 8, K.GREY)                               # a stripped drive
	s.p(-3.5, 2.0, 3.5, -0.5, 2.5, 7.5, K.SILVER)
	return s


## A handheld radio on its back: PRC-152 (dark, keypad, tape antenna) or a cheap enemy
## handset (black, amber screen, stubby antenna).
static func _radio(enemy: bool) -> Shape:
	var s := Shape.new()
	var w := 6.0 if enemy else 7.0
	var l := 11.0 if enemy else 16.0
	var h := 3.5 if enemy else 4.5
	s.prism(Axis.Z, w * 0.5, h * 0.5, w * 0.5, h * 0.5, 0.8, 0, l, K.BLACK if enemy else K.DARK_GREY)
	if not enemy:
		s.b(-0.2, -0.2, l, w + 0.2, h + 0.2, l + 4.5, K.TAN)       # battery
	s.p(0.8, h - 0.5, 1.5, w - 0.8, h, 4.5, K.LIME if not enemy else K.AMBER)  # display
	s.p(1.0, h - 0.5, 2.0, w - 1.0, h, 4.0, K.SCREEN if not enemy else K.AMBER)
	for r in 4:  # keypad
		for c in 3:
			s.p(0.8 + c * (w - 1.6) / 3.0 + 0.2, h - 0.5, 5.5 + r * 1.4, 0.8 + (c + 1) * (w - 1.6) / 3.0 - 0.2, h, 6.5 + r * 1.4, K.GREY)
	s.cyl(Axis.Z, w * 0.3, h * 0.5, 0.8, -1.5, 0, K.BLACK)        # knobs
	s.cyl(Axis.Z, w * 0.75, h * 0.5, 0.6, -1.0, 0, K.BLACK)
	if enemy:
		s.cyl(Axis.Z, w * 0.3, h * 0.5, 0.6, -9, -1.5, K.RUBBER)  # stubby antenna
	else:
		s.b(w * 0.3 - 0.6, h * 0.5 - 0.2, -20, w * 0.3 + 0.6, h * 0.5 + 0.2, -1.5, K.BLACK)  # tape antenna
	return s


static func _binoculars() -> Shape:
	var s := Shape.new()
	for x: float in [3.0, 9.0]:
		s.cyl(Axis.Z, x, 3, 2.9, 0, 15, K.OD_DARK)
		s.cyl(Axis.Z, x, 3, 2.3, -0.01, 0.5, VoxelArt.C.LENS)
		s.cyl(Axis.Z, x, 3, 2.4, 13, 15, K.BLACK)                  # eyecups
		s.cyl(Axis.Z, x, 3, 1.3, 14.5, 15.01, K.DARK_GREY)
	s.b(5.5, 1.5, 4, 6.5, 5.2, 12, K.BLACK)                        # bridge
	s.cyl(Axis.Z, 6, 4.5, 0.8, 8, 12, K.BLACK)                     # focus wheel
	return s


static func _zip_cuffs() -> Shape:
	var s := Shape.new()
	s.frame(0, 0, 5.5, 6, 0, 0.6, 0.6, K.BLACK)
	s.frame(6.5, 0, 12, 6, 0, 0.6, 0.6, K.BLACK)
	s.b(4.5, 0, 1.5, 7.5, 1.2, 4.5, K.WHITE)                       # lock block
	s.b(-2, 0, 2.5, 0, 0.5, 3.5, K.BLACK)                          # tails
	s.b(12, 0, 2.5, 14, 0.5, 3.5, K.BLACK)
	return s


static func _laptop() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 17, 0.75, 17, 0.75, 0.5, 0, 24, K.DARK_GREY)   # base
	s.prism(Axis.Z, 17, 2.25, 17, 0.75, 0.5, 0, 24, K.GREY)        # lid, closed
	s.p(0, 1.5, 0, 34, 2.0, 24, K.BLACK)                           # the seam
	s.p(14.5, 2.5, 10, 19.5, 3, 15, K.SILVER)                      # logo
	s.b(3, 0.5, 24, 31, 2.5, 24.6, K.BLACK)                        # hinge
	s.p(0, 0.5, 4, 0.5, 1.2, 7, K.BLACK)                           # ports
	s.p(0, 0.5, 8, 0.5, 1.2, 9.5, K.BLACK)
	s.b(10, 3, 3, 15, 3.5, 8, K.YELLOW)                            # a sticky note
	return s


static func _phone() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 4, 0.5, 4, 0.5, 0.5, 0, 16, K.BLACK)
	s.p(0.5, 0.5, 1.0, 7.5, 1.0, 15.0, K.SCREEN)
	s.p(1.5, 0.5, 3.0, 4.0, 1.0, 5.5, K.NAVY)                      # glint
	s.p(4.5, 0.5, 9.0, 6.5, 1.0, 12.5, K.NAVY)
	s.p(3.5, 0.5, 15.2, 4.5, 1.0, 15.7, K.DARK_GREY)               # camera
	s.b(8, 0.2, 4, 8.3, 0.8, 7, K.DARK_GREY)                       # buttons
	return s


## A manila folder with papers sticking out, a red stamp and a clip.
static func _documents() -> Shape:
	var s := Shape.new()
	s.b(0, 0, 0, 22, 0.5, 30, K.MANILA)
	s.b(1.5, 0.5, -1.5, 22.5, 1.5, 29.5, K.PAPER)                  # papers
	s.b(2.5, 0.5, 29.5, 20, 1.0, 31.5, K.WHITE)
	s.b(0, 1.5, 0, 21.5, 2.0, 29.5, K.MANILA)                      # front cover
	s.b(14, 1.5, 29.5, 21, 2.0, 31, K.MANILA)                      # tab
	s.p(3, 1.5, 4, 14, 2.0, 7, K.RED)                              # stamp
	s.p(4, 1.5, 4.8, 13, 2.0, 6.2, K.MANILA)
	s.p(3, 1.5, 12, 17, 2.0, 12.5, K.BROWN)                        # handwriting
	s.p(3, 1.5, 14, 15, 2.0, 14.5, K.BROWN)
	s.b(-0.3, 0, 22, 0.3, 2.3, 25, K.SILVER)                       # clip
	return s


# --- Objectives and vehicle parts -------------------------------------------------------

## A hard case lying flat: shell, lid seam, ribs, latches, handle, corner guards.
static func _hard_case() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 27.5, 11, 27.5, 11, 2.0, 0, 40, K.BLACK)
	s.b(-0.4, 9, -0.4, 55.4, 11, 40.4, K.RUBBER)                    # lid seam
	for x: float in [8.0, 25.0, 42.0]:
		s.b(x, 22, 3, x + 5, 22.6, 37, K.RUBBER)                   # ribs on the lid
	for x: float in [10.0, 41.0]:
		s.b(x, 7, -1.2, x + 4, 13, 0, K.GREY)                      # latches
	s.b(22, 9, -2.5, 33, 11, -1.2, K.RUBBER)                       # handle
	s.p(46, 22, 32, 53, 22.6, 38, K.YELLOW)                        # tag
	return s


## A wooden crate: planks, corner battens, rope handles, a stencil.
static func _crate() -> Shape:
	var s := Shape.new(1.0)
	s.b(0, 0, 0, 60, 40, 40, K.WOOD)
	for y: float in [10.0, 20.0, 30.0]:
		s.p(0, y, 0, 60, y + 1, 40, K.WOOD_DARK)                   # plank gaps
	for x: float in [0.0, 56.0]:  # end battens
		s.b(x - 1, 0, -1, x + 5, 40, 41, K.WOOD_DARK)
	s.b(-1, 38, -1, 61, 41, 41, K.WOOD_DARK)                       # lid frame
	s.b(4, 40, 4, 56, 41, 36, K.WOOD)
	s.b(-2, 26, 16, -1, 28, 24, K.TAN)                             # rope handles
	s.b(61, 26, 16, 62, 28, 24, K.TAN)
	s.p(15, 14, -1, 45, 26, 0, K.BLACK)                            # stencil
	s.p(17, 16, -1, 43, 24, 0, K.WOOD)
	s.p(19, 18, -1, 41, 22, 0, K.BLACK)
	return s


## A pallet: bottom boards, blocks, the top deck, a strap and a stencil.
static func _pallet() -> Shape:
	var s := Shape.new(1.0)
	for z: float in [0.0, 45.0, 90.0]:
		s.b(0, 0, z, 120, 2, z + 10, K.WOOD_DARK)                  # bottom boards
		for x: float in [0.0, 55.0, 110.0]:
			s.b(x, 2, z, x + 10, 11, z + 10, K.WOOD)               # blocks
		s.b(0, 11, z, 120, 13, z + 10, K.WOOD_DARK)                # stringer boards
	for i in 7:
		s.b(0, 13, i * 15.0, 120, 15, i * 15.0 + 10, K.WOOD)       # deck
	s.b(58, 15, -0.5, 62, 15.5, 100.5, K.BLACK)                    # strap
	s.p(3, 4, -0.1, 7, 9, 0.5, K.BLACK)
	return s


## A NATO jerrycan standing: body with its X pressings, the three handles, the spout.
static func _jerrycan() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Y, 8.5, 17.5, 8.5, 17.5, 1.5, 0, 42, K.OD)
	s.b(-0.3, 0, 17, 17.3, 42, 18, K.OD_DARK)                      # weld seam round it
	for side: float in [-0.01, 17.01]:  # the X pressings on each face
		for i in 30:
			var t := float(i) / 30.0
			var y := 4.0 + t * 34.0
			var z1 := 3.0 + t * 29.0
			var z2 := 32.0 - t * 29.0
			var x0 := side - 0.5 if side > 1.0 else side
			s.b(x0, y, z1, x0 + 0.5, y + 1.2, z1 + 1.2, K.OD_DARK, true)
			s.b(x0, y, z2 - 1.2, x0 + 0.5, y + 1.2, z2, K.OD_DARK, true)
	s.prism(Axis.Z, 8.5, 42, 7.5, 1.5, 0.8, 1.5, 33.5, K.OD)       # top
	for z: float in [6.0, 16.5, 27.0]:
		s.b(7.5, 42, z, 9.5, 47, z + 2, K.OD)                       # handles
	s.b(7.5, 45, 6, 9.5, 47, 29, K.OD)
	s.b(5, 41, -2.5, 12, 47, 3, K.OD_DARK)                          # spout cap
	s.b(6, 44, -3.5, 11, 46, -2.5, K.STEEL)
	s.p(-0.01, 20, 9, 0.5, 23, 26, K.YELLOW)                        # fuel stencil
	return s


## A spare wheel lying flat: tyre with tread, steel rim, hub and nuts.
static func _wheel() -> Shape:
	var s := Shape.new(1.0)
	s.ring(Axis.Y, 45, 45, 45, 24, 0, 30, K.RUBBER)
	for y: float in [6.0, 14.0, 22.0]:
		s.ring(Axis.Y, 45, 45, 46, 40, y, y + 2, K.BLACK, true)     # tread grooves
	s.ring(Axis.Y, 45, 45, 35, 33, 29, 30, K.DARK_GREY, true)       # sidewall line
	s.ring(Axis.Y, 45, 45, 25, 12, 5, 25, K.OD)                     # rim
	s.cyl(Axis.Y, 45, 45, 12, 10, 24, K.OD_DARK)                    # hub
	s.cyl(Axis.Y, 45, 45, 5, 23, 26, K.STEEL)
	for a in 8:
		var ang := a * TAU / 8.0
		s.b(45 + cos(ang) * 9 - 1, 24, 45 + sin(ang) * 9 - 1, 45 + cos(ang) * 9 + 1, 25, 45 + sin(ang) * 9 + 1, K.STEEL)
	return s


## A run of four track links: plates with grousers, guide horns and pins.
static func _track_links() -> Shape:
	var s := Shape.new()
	var steel := K.DARK_GREY
	for i in 4:
		var x0 := i * 15.0
		s.b(x0, 0, 0, x0 + 13.5, 3, 30, steel)                      # shoe
		s.b(x0 + 5.5, 3, 1, x0 + 8, 4.5, 29, K.GREY)                # grouser
		s.b(x0 + 4, 3, 12.5, x0 + 10, 11, 17.5, steel)              # guide horn
		s.b(x0 + 5, 11, 13, x0 + 9, 12, 17, K.GREY)
		s.cyl(Axis.Z, x0 + 13.5 + 0.75, 1.5, 1.4, 0.5, 29.5, K.STEEL)  # pin to the next
		s.b(x0 + 1, 3, 3, x0 + 3, 3.5, 8, K.BROWN)                  # rust
	return s


static func _toolbox() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 25, 9, 25, 9, 1.0, 0, 25, K.OD)
	s.b(-0.3, 15, -0.3, 50.3, 18, 25.3, K.OD_DARK)                  # lid
	s.prism(Axis.X, 18, 12.5, 2, 2, 1.0, 1, 49, K.OD)               # lid top, rounded
	s.b(20, 20, 11, 22, 23, 14, K.BLACK)                            # handle
	s.b(28, 20, 11, 30, 23, 14, K.BLACK)
	s.b(20, 22, 11, 30, 23.5, 14, K.BLACK)
	s.b(6, 12, -1.2, 10, 17, 0, K.STEEL)                            # latches
	s.b(40, 12, -1.2, 44, 17, 0, K.STEEL)
	s.p(15, 5, -0.01, 35, 8, 0.5, K.YELLOW)                         # stencil
	s.b(50, 2, 8, 52, 4, 20, K.SILVER)                              # wrench on the side
	return s


static func _battery() -> Shape:
	var s := Shape.new()
	s.prism(Axis.Z, 16.5, 10.5, 16.5, 10.5, 1.0, 0, 18, K.BLACK)
	s.b(0.5, 21, 0.5, 32.5, 22.5, 17.5, K.DARK_GREY)                # lid
	s.cyl(Axis.Y, 4, 4, 1.4, 22.5, 24.5, K.RED)                     # terminals
	s.cyl(Axis.Y, 29, 4, 1.4, 22.5, 24.5, K.BLACK)
	for x: float in [9.0, 13.5, 18.0, 22.5]:
		s.cyl(Axis.Y, x, 11, 1.0, 22.5, 23.2, K.GREY)               # vent caps
	s.b(14, 22.5, 13, 19, 24, 16, K.RUBBER)                         # strap handle
	s.p(6, 6, -0.01, 27, 15, 0.5, K.WHITE)                          # label
	s.p(8, 9, -0.01, 25, 11, 0.5, K.RED)
	return s


## Engine parts: a cylinder block with its bores, a pulley, an oil filter, a hose.
static func _engine_parts() -> Shape:
	var s := Shape.new()
	s.prism(Axis.X, 10, 17.5, 10, 13, 2.0, 2, 34, K.GREY)           # block
	for x: float in [5.0, 12.0, 19.0, 26.0]:
		s.cyl(Axis.Y, x + 3, 17.5, 2.6, 19.5, 20.0, K.DARK_GREY)    # bores
	s.cyl(Axis.X, 10, 17.5, 8, 0, 2, K.BLACK)                       # pulley
	s.cyl(Axis.X, 10, 17.5, 2, -1.5, 0, K.STEEL)
	s.cyl(Axis.Y, 40, 8, 4.5, 0, 12, K.ORANGE)                      # oil filter
	s.cyl(Axis.Y, 40, 8, 4.0, 11.5, 12.5, K.STEEL)
	for i in 6:  # a hose curling off the block
		s.b(34 + i * 1.5, 2, 26 + i * 0.8, 36 + i * 1.5, 4, 29 + i * 0.8, K.RUBBER)
	s.b(36, 0, 18, 45, 3, 23, K.STEEL)                              # a bracket
	return s


# --- Shape: box lists in centimetres ----------------------------------------------------

## A model being written: boxes in centimetres (later ones overwrite), and helpers for
## low-poly round parts (octagonal prisms, lathes, rings) built from boxes. spec() makes a
## VoxelArt spec of it at `res` cm per voxel, trimmed to its bounds.
class Shape:
	var res := 0.5
	var boxes: Array = []

	func _init(cm_per_voxel := 0.5) -> void:
		res = cm_per_voxel

	## A box between two corners.
	func b(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int, paint := false) -> void:
		boxes.append([Vector3(minf(x0, x1), minf(y0, y1), minf(z0, z1)), Vector3(maxf(x0, x1), maxf(y0, y1), maxf(z0, z1)), colour, paint])

	## A box that only recolours what is already there.
	func p(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> void:
		b(x0, y0, z0, x1, y1, z1, colour, true)

	## Box spanning `a` along `axis`, `u` and `v` across it (x: y, z; y: x, z; z: x, y).
	func _axis_box(axis: int, a0: float, a1: float, u0: float, u1: float, v0: float, v1: float, colour: int, paint: bool) -> void:
		match axis:
			0: b(a0, u0, v0, a1, u1, v1, colour, paint)
			1: b(u0, a0, v0, u1, a1, v1, colour, paint)
			_: b(u0, v0, a0, u1, v1, a1, colour, paint)

	## A prism along `axis` from a0 to a1: a cross-section `hu` by `hv` half-wide round (u, v)
	## with its corners cut at 45 degrees by `cut`, built a voxel row at a time.
	func prism(axis: int, u: float, v: float, hu: float, hv: float, cut: float, a0: float, a1: float, colour: int, paint := false) -> void:
		for k in range(floori((u - hu) / res), ceili((u + hu) / res)):
			var du := absf((k + 0.5) * res - u)
			if du > hu:
				continue
			var half := hv - maxf(0.0, cut - (hu - du))
			if half <= 0.0:
				continue
			_axis_box(axis, a0, a1, k * res, (k + 1) * res, v - half, v + half, colour, paint)

	## An octagonal rod of radius r.
	func cyl(axis: int, u: float, v: float, r: float, a0: float, a1: float, colour: int, paint := false) -> void:
		prism(axis, u, v, r, r, r * 0.586, a0, a1, colour, paint)

	## A turned shape: radius keys [[a, r], ...] along `axis`, one voxel slice at a time (runs
	## of slices with the same radius as one).
	func lathe(axis: int, u: float, v: float, keys: Array, colour: int, paint := false) -> void:
		var a_lo: float = keys[0][0]
		var a_hi: float = keys[-1][0]
		var start := a_lo
		var last := -1.0
		var k := roundi(a_lo / res)
		while k * res < a_hi - 0.001:
			var ac := (k + 0.5) * res
			var i := 0
			while i < keys.size() - 2 and ac > float(keys[i + 1][0]):
				i += 1
			var t := clampf(inverse_lerp(float(keys[i][0]), float(keys[i + 1][0]), ac), 0.0, 1.0)
			var r := snappedf(lerpf(keys[i][1], keys[i + 1][1], t), res * 0.5)
			if r != last and last > 0.0:
				cyl(axis, u, v, last, start, k * res, colour, paint)
				start = k * res
			elif last <= 0.0:
				start = k * res
			last = r
			k += 1
		if last > 0.0:
			cyl(axis, u, v, last, start, a_hi, colour, paint)

	## An octagonal tube: outer radius ro, inner ri.
	func ring(axis: int, u: float, v: float, ro: float, ri: float, a0: float, a1: float, colour: int, paint := false) -> void:
		var co := ro * 0.586
		var ci := ri * 0.586
		for k in range(floori((u - ro) / res), ceili((u + ro) / res)):
			var du := absf((k + 0.5) * res - u)
			if du > ro:
				continue
			var outer := ro - maxf(0.0, co - (ro - du))
			if outer <= 0.0:
				continue
			var inner := ri - maxf(0.0, ci - (ri - du)) if du < ri else 0.0
			if inner <= 0.0:
				_axis_box(axis, a0, a1, k * res, (k + 1) * res, v - outer, v + outer, colour, paint)
			else:
				_axis_box(axis, a0, a1, k * res, (k + 1) * res, v - outer, v - inner, colour, paint)
				_axis_box(axis, a0, a1, k * res, (k + 1) * res, v + inner, v + outer, colour, paint)

	## A flat rectangular loop in x-z from (x0, z0) to (x1, z1), `w` wide, y0 to y1 thick.
	func frame(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, w: float, colour: int) -> void:
		b(x0, y0, z0, x1, y1, z0 + w, colour)
		b(x0, y0, z1 - w, x1, y1, z1, colour)
		b(x0, y0, z0, x0 + w, y1, z1, colour)
		b(x1 - w, y0, z0, x1, y1, z1, colour)

	## The VoxelArt spec: boxes in voxels, shifted so the solid ones start at 0, and the size
	## their bounds come to.
	func spec() -> Dictionary:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var out: Array = []
		for box: Array in boxes:
			var a: Vector3 = (box[0] / res).round()
			var c: Vector3 = (box[1] / res).round()
			if c.x <= a.x or c.y <= a.y or c.z <= a.z:
				continue
			if not box[3]:
				lo = lo.min(a)
				hi = hi.max(c)
			out.append([a, c, box[2], box[3]])
		if lo.x == INF:
			return {"size": Vector3i.ONE, "voxel": res / 100.0, "sub": 1, "boxes": [[Vector3.ZERO, Vector3.ONE, K.GREY, false]]}
		for box: Array in out:
			box[0] -= lo
			box[1] -= lo
		return {"size": Vector3i(hi - lo), "voxel": res / 100.0, "sub": 1, "boxes": out, "origin_cm": lo * res}
