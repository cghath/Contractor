class_name GearRig
extends Node3D
## Puts what an Inventory is wearing onto a CharacterModel. Gear is voxel art (VoxelArt)
## mounted on the model's torso or head so it follows the animation; items without a
## voxel model yet fall back to a coloured box. Plates and helmets are VoxelArmor nodes:
## destructible 1 cm voxels that are also the hit targets.
##
## Hands: the weapon the model holds (CharacterModel.hold) is drawn from its sling or
## holster (the hand goes to it first, CharacterModel.start_draw) and goes back there while
## the hands are busy with a casualty or an action (CharacterModel.hands_busy). Both follow
## replicated state, so every peer sees the same.

@export var inventory: Inventory
@export var model: CharacterModel
## Render layers for gear meshes. The local player's camera hides LOCAL_ONLY so your own
## kit doesn't block your view.
@export_flags_3d_render var render_layers := 1:
	set(value):
		render_layers = value
		if is_node_ready():
			_clear()
			_rebuild()

## Armor slots that become VoxelArmor nodes, with HUD names.
const ARMOR_SLOTS := {
	&"plate_front": "Front", &"plate_back": "Back", &"plate_left": "Left", &"plate_right": "Right", &"helmet": "Helmet",
}
## Torso-local plate centre heights (torso pivot is at the hips; torso spans y 0-0.56).
const PLATE_HEIGHT := 0.33
const SIDE_PLATE_HEIGHT := 0.28
## Where a helmet's pivot (the centre of its dome base) sits, head-local.
const HELMET_POSITION := Vector3(0, 0.2, 0)
## A female soldier's carrier (and the plates, pouches, name tape, slung rifle and pack on it)
## rides this much further forward on her torso, over her bust (VoxelArt._torso_f), as a plate
## carrier sits on a real woman; her back is slimmer, so the back panel still lies against it.
const FEMALE_CARRIER_FORWARD := 0.03
## A tourniquet's band and the red of medical pull tabs, as drawn on the carrier.
const TQ_BAND := Color("1b1b1a")
const MED_RED := Color("b3261e")
## Rest mounts, torso-local, for a right-handed shooter (rest_transform mirrors them for a
## left-handed one): the vest at the cummerbund; the primary on its sling in the patrol
## carry, diagonally across the front of the carrier clear of the pouches (stock up under the
## firing-side armpit, muzzle down at the support-side thigh), lying flat on its side against
## the chest: ejection port out, magazine down towards the firing-side hip. The sidearm is in
## a thigh holster on the firing side.
const MOUNTS := [&"vest", &"primary", &"sidearm"]
const SLING_CENTRE := Vector3(0.02, 0.2, -0.21)
const SLING_DIR := Vector3(-0.5, -0.866, 0.0)  # where the muzzle points: 30 degrees off vertical
const HOLSTER := Vector3(0.22, 0.02, -0.02)
## Held weapons, in CharacterModel.hands_anchor space (shoulder height, pitches with aim),
## for a right-handed shooter (mirrored for a left-handed one):
## - A rifle's butt (VoxelArt.butt_point) sits in the firing shoulder's pocket. Aiming, it
##   points straight out, the optic under the (dipped) eye line. At the ready, the stock stays
##   in the pocket and the muzzle dips READY_DIP and turns READY_TURN in across the body.
## - A pistol is pushed out two-handed at the eye line aiming, and held low in front of the
##   chest at the ready.
## The arms reach for the weapon's VoxelArt.hand_points, the support shoulder brought forward
## (CharacterModel.SUPPORT_REACH).
## The pockets are spots on the chest: torso-local, from hands_anchor's origin, as if the
## upper body faced the view. A rifle held two-handed blades the upper body
## (CharacterModel.BLADE) while hands_anchor turns back to the view, so held_transform turns
## the pocket with the twist and the butt stays on the same spot of the chest.
const SHOULDER_POCKET := Vector3(0.09, 0.07, -0.11)
const READY_POCKET := Vector3(0.11, 0.03, -0.11)
const READY_DIP := 0.5
const READY_TURN := 0.15
const PISTOL_AIM := Vector3(0.0, 0.16, -0.44)
const PISTOL_READY := Vector3(0.06, -0.12, -0.32)
const PISTOL_READY_DIP := 0.45
## How fast a held weapon moves between the ready and aiming (per second).
const HOLD_EASE := 12.0
## Name tape lettering: cap height in metres, and the ink.
const TAPE_HEIGHT_M := 0.016
const TAPE_INK := Color(0.1, 0.1, 0.08)
## The tape: a strip of tan cloth on the loop panel, letters on it.
const TAPE_SIZE := Vector3(0.12, 0.028, 0.004)
const TAPE_CLOTH := Color("8f8a6c")

var _armor: Dictionary = {}        # slot -> VoxelArmor
var _chip_counts: Dictionary = {}  # slot -> chips already applied to the mesh
var _gear: Dictionary = {}    # key -> [item id, Node3D]
var _held_key: StringName = &""  # which _gear entry is in the hands
var _held_dirty := true
var _want_key: StringName = &""  # what should be in the hands
var _clock := 0.0
var _grab_at := -1.0             # _clock when a weapon being drawn reaches the hands
var _pouches: Node3D             # MOLLE attachments on the carrier
var _pouch_key := ""             # what _pouches shows
var _left_shown := false          # model.left_handed the rest mounts were placed for
var _straps: Node3D              # the pack's shoulder straps (torso-local)
var _straps_for: StringName = &""  # the pack they were built for
var _tape: Node3D                 # the name tape on the carrier's loop panel
var _tape_key := ""              # carrier and text it shows



func _ready() -> void:
	inventory.changed.connect(_rebuild)
	_rebuild()


## Where an armor piece sits. Plates sit on the carrier's faces, outside the 0.12 m-deep
## hitbox, strike face outward; the carrier sets how far out (heavy carriers are thicker).
static func armor_transform(slot: StringName, carrier: ItemData) -> Transform3D:
	var depth: float = carrier.stats.get("plate_depth", 0.14) if carrier else 0.14
	var side: float = carrier.stats.get("side_plate_x", 0.245) if carrier else 0.245
	match slot:
		&"plate_front": return Transform3D(Basis.IDENTITY, Vector3(0, PLATE_HEIGHT, -depth))
		&"plate_back": return Transform3D(Basis(Vector3.UP, PI), Vector3(0, PLATE_HEIGHT, depth))
		&"plate_left": return Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-side, SIDE_PLATE_HEIGHT, 0))
		&"plate_right": return Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(side, SIDE_PLATE_HEIGHT, 0))
	return Transform3D(Basis.IDENTITY, HELMET_POSITION)


## Body-space position of a plate slot at rest with a medium carrier (for tests and tools).
static func plate_rest_position(slot: StringName) -> Vector3:
	return CharacterModel.TORSO_PIVOT + armor_transform(slot, null).origin


func armor_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for piece: VoxelArmor in _armor.values():
		rids.append(piece.get_rid())
	return rids


## Remaining fraction of an armor slot's protection, or -1 if nothing is worn there: the
## piece's integrity (ArmorRules, which every hit wears down), or the share of its voxels
## left if that is lower.
func armor_integrity(slot: StringName) -> float:
	var piece: VoxelArmor = _armor.get(slot)
	if piece == null:
		return -1.0
	return minf(ArmorRules.integrity(inventory.state_of(slot)), piece.integrity())


## "Front IV 64% 3 cracks  Back IV 100%  Helmet IIIA 92%" for HUDs and labels (rating, what's
## left, a ceramic plate's cracks or "shattered"); "" with no armor.
func armor_summary(separator := "  ") -> String:
	var parts := PackedStringArray()
	for slot: StringName in ARMOR_SLOTS:
		var integrity := armor_integrity(slot)
		if integrity < 0.0:
			continue
		var piece: VoxelArmor = _armor[slot]
		var state := inventory.state_of(slot)
		var text := "%s %s" % [ARMOR_SLOTS[slot], ArmorRules.rating(piece.item)]
		if ArmorRules.is_shattered(state):
			text += " " + ArmorRules.failed_text(piece.item)
		else:
			text += " %d%%" % roundi(integrity * 100.0)
			var cracks := ArmorRules.cracks(state).size()
			if cracks > 0:
				text += " %d crack%s" % [cracks, "" if cracks == 1 else "s"]
		parts.append(text)
	return separator.join(parts)


func _rebuild() -> void:
	var vest: StringName = inventory.slots[&"vest"]
	var carrier := ItemDB.get_item(vest) if vest != &"" else null
	for slot: StringName in ARMOR_SLOTS:
		var id: StringName = inventory.slots[slot]
		var piece: VoxelArmor = _armor.get(slot)
		if piece and piece.item.id != id:
			piece.queue_free()
			_armor.erase(slot)
			piece = null
		if piece == null and id != &"":
			piece = VoxelArmor.new()
			(model.head if slot == &"helmet" else model.torso).add_child(piece)
			piece.setup(ItemDB.get_item(id), slot, inventory, render_layers)
			_armor[slot] = piece
			_chip_counts[slot] = 0
		if piece:
			piece.transform = armor_transform(slot, carrier)
			if slot != &"helmet":
				piece.transform = piece.transform.translated(carrier_shift())
			if slot != &"helmet":  # a plate sits inside the carrier's pocket, under its fabric
				piece.set_cover(Color(VoxelArt.VARIANTS.get(model.variant, VoxelArt.VARIANTS.multicam).gear) if carrier else Color(0, 0, 0, 0))
	for slot: StringName in MOUNTS:
		_set_gear(slot, inventory.slots[slot], &"torso", rest_transform(slot))
	var pack: StringName = inventory.slots[&"backpack"]
	var pack_depth := VoxelArt.size_m(VoxelArt.model_for(ItemDB.get_item(pack))).z if pack != &"" else 0.0
	_set_gear(&"backpack", pack, &"torso", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.165 + pack_depth * 0.5) + carrier_shift()))
	var held := inventory.hands
	var held_size := WorldItem.visual_size(ItemDB.get_item(held)) if held != &"" else Vector3.ZERO
	_set_gear(&"hands", held, &"torso", Transform3D(Basis.IDENTITY, Vector3(0, 0.15, -0.15 - held_size.z * 0.5)))
	_set_pouches()
	_set_pack_straps(pack)
	_set_name_tape(carrier)
	_refresh_plate_damage()


## MOLLE attachments on the worn carrier, drawn as small boxes on its attach points (the
## points' "at" and "face"); rebuilt only when what's attached changes.
func _set_pouches() -> void:
	var points := inventory.attach_points()
	var key := String(inventory.slots[&"vest"])
	for p: Dictionary in points:
		var att := inventory.attachment(StringName(p.id))
		if not att.is_empty():
			key += "|%s=%s%s" % [p.id, att.id, "+" if not att.get("held", []).is_empty() else ""]
	if key == _pouch_key:
		return
	_pouch_key = key
	if _pouches:
		_pouches.queue_free()
		_pouches = null
	if inventory.attachment_count() == 0:
		return
	_pouches = Node3D.new()
	_pouches.name = "Pouches"
	model.torso.add_child(_pouches)
	var gear := Color(VoxelArt.VARIANTS.get(model.variant, VoxelArt.VARIANTS.multicam).gear).darkened(0.12)
	for p: Dictionary in points:
		var att := inventory.attachment(StringName(p.id))
		if att.is_empty():
			continue
		var node := pouch_node(ItemDB.get_item(StringName(att.id)), gear, not att.get("held", []).is_empty(), render_layers)
		node.transform = point_transform(p, WorldItem.visual_size(ItemDB.get_item(StringName(att.id)))).translated(carrier_shift())
		_pouches.add_child(node)


## The name tape: the soldier's surname (CharacterModel.name_tape) in dark capitals on the
## carrier's loop panel at the top of the plate pocket's front (VoxelArt._vest), TAPE_HEIGHT_M
## tall. None without a carrier or a name. Rebuilt when either changes (see _process).
func _set_name_tape(carrier: ItemData) -> void:
	var key := "%s|%s" % [carrier.id if carrier else &"", model.name_tape]
	if key == _tape_key:
		return
	_tape_key = key
	if _tape:
		_tape.queue_free()
		_tape = null
	if carrier == null or model.name_tape == "":
		return
	var front := float(carrier.stats.get("plate_depth", 0.14)) + 0.03  # the pocket's face
	_tape = Node3D.new()
	_tape.name = "NameTape"
	_tape.position = Vector3(0, 0.17 + 0.265, -front) + carrier_shift()  # the loop panel
	model.torso.add_child(_tape)
	_tape.add_child(_part_box(TAPE_SIZE, Vector3(0, 0, -TAPE_SIZE.z * 0.5), TAPE_CLOTH, render_layers))
	var letters := Label3D.new()
	letters.text = model.name_tape
	letters.font_size = 48
	letters.pixel_size = TAPE_HEIGHT_M / 48.0
	letters.outline_size = 0
	letters.modulate = TAPE_INK
	letters.double_sided = false
	letters.layers = render_layers
	letters.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -TAPE_SIZE.z - 0.001))  # reads from the front
	_tape.add_child(letters)


## A worn pack's padded shoulder straps: from the top of the pack, over each shoulder outside
## the carrier's pads, and down the front edges of the plate pocket, with a sternum strap
## across under the ID panel, in front of the pouches. Rebuilt when the pack changes.
func _set_pack_straps(pack: StringName) -> void:
	if pack == _straps_for:
		return
	_straps_for = pack
	if _straps:
		_straps.queue_free()
		_straps = null
	if pack == &"":
		return
	_straps = Node3D.new()
	_straps.name = "PackStraps"
	_straps.position = carrier_shift()  # the pack and the carrier it runs over
	model.torso.add_child(_straps)
	var colour := Color(VoxelArt.VARIANTS.get(model.variant, VoxelArt.VARIANTS.multicam).gear).darkened(0.3)
	for s: float in [-1.0, 1.0]:
		var path: Array[Vector3] = [Vector3(0.12, 0.5, 0.17), Vector3(0.13, 0.585, 0.06), Vector3(0.13, 0.595, -0.06),
			Vector3(0.155, 0.5, -0.17), Vector3(0.155, 0.34, -0.16)]
		for i in path.size() - 1:
			_straps.add_child(_strap(path[i] * Vector3(s, 1, 1), path[i + 1] * Vector3(s, 1, 1), 0.045, 0.015, colour))
	_straps.add_child(_strap(Vector3(-0.155, 0.355, -0.215), Vector3(0.155, 0.355, -0.215), 0.02, 0.008, colour))  # sternum strap


## A strap of `width` and `thick` from `a` to `b` (torso-local), lying flat on the body: its
## face turned out from inside the upper chest.
func _strap(a: Vector3, b: Vector3, width: float, thick: float, colour: Color) -> Node3D:
	var holder := Node3D.new()
	holder.add_child(_part_box(Vector3(width, (b - a).length() + thick, thick), Vector3.ZERO, colour, render_layers))
	var y := (b - a).normalized()
	var out := (a + b) * 0.5 - Vector3(0, 0.45, 0)
	var z := (out - y * out.dot(y)).normalized()
	holder.transform = Transform3D(Basis(y.cross(z), y, z), (a + b) * 0.5)
	return holder


## Torso-local transform of an attachment of `size` on attach point `p`: its back against the
## carrier at "at", facing out of "face" (front, back, left or right).
static func point_transform(p: Dictionary, size: Vector3) -> Transform3D:
	var at: Array = p.get("at", [0, 0.3, -0.18])
	var origin := Vector3(float(at[0]), float(at[1]), float(at[2]))
	var basis := Basis.IDENTITY
	match String(p.get("face", "front")):
		"back": basis = Basis(Vector3.UP, PI)
		"left": basis = Basis(Vector3.UP, PI / 2)
		"right": basis = Basis(Vector3.UP, -PI / 2)
	return Transform3D(basis, origin + basis * Vector3(0, 0, -size.z * 0.5))


## A pouch (or knife) as small boxes: body and a darker flap, or a sheath and handle; a radio
## shows its antenna. A tourniquet holder is open-topped: the tourniquet in it shows (black
## band, windlass rod across the top, red tab). A full IFAK pouch shows its red pull tabs, so
## you can see who carries one. Front is -Z. Used on the soldier and for item previews.
static func pouch_node(item: ItemData, colour: Color, full: bool, layers := 1) -> Node3D:
	var root := Node3D.new()
	var size := WorldItem.visual_size(item)
	if item.id == &"knife" or item.stats.get("attach", []).has("knife") and not Inventory.is_pouch(item):
		root.add_child(_part_box(Vector3(size.x, size.y * 0.62, size.z), Vector3(0, -size.y * 0.19, 0), colour.darkened(0.35), layers))
		root.add_child(_part_box(Vector3(size.x * 0.7, size.y * 0.38, size.z * 0.8), Vector3(0, size.y * 0.31, 0), Color("26241f"), layers))
		return root
	var accepts: Array = item.stats.get("accepts", [])
	if accepts.has("tourniquet"):
		root.add_child(_part_box(Vector3(size.x, size.y * 0.6, size.z), Vector3(0, -size.y * 0.2, 0), colour, layers))
		if full:
			root.add_child(_part_box(Vector3(size.x * 0.8, size.y * 0.5, size.z * 0.75), Vector3(0, size.y * 0.25, 0), TQ_BAND, layers))
			root.add_child(_part_box(Vector3(size.x * 1.9, 0.012, 0.012), Vector3(0, size.y * 0.5, -size.z * 0.1), TQ_BAND.lightened(0.15), layers))
			root.add_child(_part_box(Vector3(0.016, 0.022, 0.006), Vector3(size.x * 0.25, size.y * 0.42, -size.z * 0.42), MED_RED, layers))
		return root
	root.add_child(_part_box(size, Vector3.ZERO, colour, layers))
	root.add_child(_part_box(Vector3(size.x * 1.02, size.y * 0.28, size.z * 1.08), Vector3(0, size.y * 0.36, -size.z * 0.04), colour.darkened(0.25), layers))
	if full and accepts.has("radio"):
		root.add_child(_part_box(Vector3(0.008, 0.16, 0.008), Vector3(size.x * 0.3, size.y * 0.5 + 0.08, 0), Color("1d1d1b"), layers))
	if full and accepts.has("type:medical"):
		for side in [-1.0, 1.0]:
			root.add_child(_part_box(Vector3(0.018, 0.03, 0.008), Vector3(side * size.x * 0.32, size.y * 0.5 + 0.012, -size.z * 0.3), MED_RED, layers))
	return root


static func _part_box(size: Vector3, pos: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()  # a bevelled box in 0.5 cm voxels, centred on `pos`
	mesh_instance.mesh = VoxelArt.bevel_box_mesh(size, colour)
	mesh_instance.material_override = VoxelArt._get_material()
	mesh_instance.scale = Vector3.ONE * VoxelArt.FINE_VOXEL
	mesh_instance.position = pos - Vector3(VoxelArt.fine_dims(size)) * VoxelArt.FINE_VOXEL * 0.5
	mesh_instance.layers = layers
	return mesh_instance


func _process(delta: float) -> void:
	_clock += delta
	if not _tape_key.ends_with("|" + model.name_tape):  # the name arrives after the body is built
		var vest: StringName = inventory.slots[&"vest"]
		_set_name_tape(ItemDB.get_item(vest) if vest != &"" else null)
	if model.left_handed != _left_shown:
		_left_shown = model.left_handed  # the slung weapons move to the other side
		for slot: StringName in MOUNTS:
			if _gear.has(slot) and slot != _held_key:
				(_gear[slot][1] as Node3D).transform = rest_transform(slot)
		_held_dirty = true
	var want := _wanted_in_hands()
	if want != _want_key:
		_want_key = want
		_grab_at = -1.0
		if want in MOUNTS and _gear.has(want) and want != _held_key:
			# Drawn: what was held goes back first, the hand fetches the new one.
			if _held_key != &"":
				_put_in_hands(&"")
			model.start_draw(_rest_grip(want))
			_grab_at = _clock + CharacterModel.DRAW_S * CharacterModel.DRAW_GRAB
	if _grab_at >= 0.0 and _clock < _grab_at:
		return
	_grab_at = -1.0
	if want != _held_key or _held_dirty:
		_put_in_hands(want)
	_ease_held(delta)


## True while a weapon is on its way from its sling or holster to the hands.
func drawing() -> bool:
	return _grab_at >= 0.0


func _wanted_in_hands() -> StringName:
	if inventory.hands != &"":
		return &"hands"
	if model.hands_busy():
		return &""  # slung or holstered while the hands work
	match model.hold:
		CharacterModel.Hold.BOTH:
			return &"primary" if _gear.has(&"primary") else &""
		CharacterModel.Hold.RIGHT:
			return &"sidearm" if _gear.has(&"sidearm") else &""
	return &""


func _put_in_hands(key: StringName) -> void:
	# Whatever was held goes back to its rest mount.
	if _held_key in MOUNTS and _gear.has(_held_key):
		var previous: Node3D = _gear[_held_key][1]
		previous.reparent(model.torso, false)
		previous.transform = rest_transform(_held_key)
	_held_key = key
	_held_dirty = false
	model.clear_held()
	if not _gear.has(key):
		return
	var node: Node3D = _gear[key][1]
	if key == &"hands":
		# Bulky item stays in front of the torso; palms press on its sides.
		var half := WorldItem.visual_size(ItemDB.get_item(inventory.hands)).x * 0.5
		model.set_held(node, Vector3(half, 0, 0), Vector3(-half, 0, 0), false)
		return
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	if points.is_empty():
		return
	node.reparent(model.hands_anchor, false)
	node.transform = held_transform(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])), model.aiming, model.left_handed, model.twist_shown())
	model.set_held(node, points.grip, points.support)


## Torso-local point where the firing hand takes hold of the weapon in `key` on its rest
## mount (its grip, or the mount itself).
func _rest_grip(key: StringName) -> Vector3:
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	var grip: Vector3 = points.get("grip", Vector3.ZERO)
	return rest_transform(key) * grip


## How far this body's carrier rides forward of the male fit (FEMALE_CARRIER_FORWARD), torso-local.
func carrier_shift() -> Vector3:
	return Vector3(0, 0, -FEMALE_CARRIER_FORWARD) if model.body == VoxelArt.FEMALE else Vector3.ZERO


## Where `slot`'s item rests on the torso (MOUNTS), mirrored for a left-handed shooter.
func rest_transform(slot: StringName) -> Transform3D:
	var s := -1.0 if model.left_handed else 1.0
	match slot:
		&"vest":
			return Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0) + carrier_shift())  # vest pivots sit at the cummerbund
		&"primary":
			var centre := SLING_CENTRE * Vector3(s, 1, 1) + carrier_shift()
			var dir := SLING_DIR * Vector3(s, 1, 1)
			# On its side: the top (optic) towards the support shoulder, across the sling line.
			return Transform3D(Basis.looking_at(dir, Vector3(-0.866 * s, 0.5, 0.0)), centre)
		&"sidearm":
			return Transform3D(Basis(Vector3.RIGHT, -PI / 2), HOLSTER * Vector3(s, 1, 1))
	return Transform3D.IDENTITY


## Where a held weapon (VoxelArt model `art`) sits in hands_anchor space, aiming or at the
## ready, for the firing shoulder (see SHOULDER_POCKET), the upper body twisted by `twist`
## (CharacterModel.twist_shown; NAN: fully bladed).
static func held_transform(art: String, aiming: bool, left: bool, twist := NAN) -> Transform3D:
	var s := -1.0 if left else 1.0
	if is_nan(twist):
		twist = CharacterModel.blade_twist(left)
	if art.begins_with("rifle"):
		var basis := Basis.IDENTITY
		var pocket := SHOULDER_POCKET
		if not aiming:
			basis = Basis(Vector3.UP, READY_TURN * s) * Basis(Vector3.RIGHT, -READY_DIP)
			pocket = READY_POCKET
		return Transform3D(basis, Basis(Vector3.UP, twist) * (pocket * Vector3(s, 1, 1)) - basis * VoxelArt.butt_point(art))
	if aiming:
		return Transform3D(Basis.IDENTITY, PISTOL_AIM)
	return Transform3D(Basis(Vector3.RIGHT, -PISTOL_READY_DIP), PISTOL_READY * Vector3(s, 1, 1))


## Moves the weapon in the hands towards where it sits now (raised to aim, or at the ready).
func _ease_held(delta: float) -> void:
	if _held_key == &"" or _held_key == &"hands" or not _gear.has(_held_key):
		return
	var node: Node3D = _gear[_held_key][1]
	var goal := held_transform(VoxelArt.model_for(ItemDB.get_item(_gear[_held_key][0])), model.aiming, model.left_handed, model.twist_shown())
	node.transform = node.transform.interpolate_with(goal, minf(delta * HOLD_EASE, 1.0))


## Replays armor chips into the meshes, skipping pieces whose chip list hasn't grown.
func _refresh_plate_damage() -> void:
	for slot: StringName in _armor:
		var chips := inventory.chips_in(slot)
		if chips.size() != _chip_counts.get(slot, -1):
			_armor[slot].apply_damage(chips, ArmorRules.is_shattered(inventory.state_of(slot)))
			_chip_counts[slot] = chips.size()


func _set_gear(key: StringName, id: StringName, mount: StringName, at: Transform3D) -> void:
	var current: Array = _gear.get(key, [&"", null])
	if current[0] == id:
		return
	if current[1]:
		current[1].queue_free()
	_gear.erase(key)
	_held_dirty = true
	if id == &"":
		return
	var item := ItemDB.get_item(id)
	var art := VoxelArt.model_for(item)
	var node: Node3D = VoxelArt.instance(art, model.variant, render_layers) if art != "" else _box(item)
	node.transform = at
	(model.head if mount == &"head" else model.torso).add_child(node)
	_gear[key] = [id, node]
	_held_dirty = true  # a held node may have been replaced


func _box(item: ItemData) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WorldItem.visual_size(item)
	var material := StandardMaterial3D.new()
	material.albedo_color = WorldItem.color_for(item)
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.layers = render_layers
	return mesh_instance


func _clear() -> void:
	for piece: VoxelArmor in _armor.values():
		piece.queue_free()
	_armor.clear()
	for entry: Array in _gear.values():
		entry[1].queue_free()
	_gear.clear()
	_held_key = &""
	_held_dirty = true
	if _pouches:
		_pouches.queue_free()
		_pouches = null
	_pouch_key = ""
