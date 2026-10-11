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
## A tourniquet's band and the red of medical pull tabs, as drawn on the carrier.
const TQ_BAND := Color("1b1b1a")
const MED_RED := Color("b3261e")
## Rest mounts: slot -> [mount, position, rotation]. The primary is slung muzzle-down on
## the right of the chest; the sidearm sits in a hip holster.
const MOUNTS := {
	&"vest": [&"torso", Vector3(0, 0.17, 0), Vector3.ZERO],  # vest pivots sit at the cummerbund
	&"primary": [&"torso", Vector3(0.2, 0.2, -0.17), Vector3(-PI / 2 + 0.25, 0, 0.2)],
	&"sidearm": [&"torso", Vector3(0.22, 0.02, -0.02), Vector3(-PI / 2, 0, 0)],
}
## Weapon positions in the hands, relative to CharacterModel.hands_anchor (shoulder height,
## pitches with aim). The arms reach for the weapon's VoxelArt.hand_points.
const HELD_POSES := {
	&"primary": Vector3(0.05, -0.04, -0.32),  # close enough for the left hand to reach an M110 handguard
	&"sidearm": Vector3(0.02, -0.03, -0.45),
}

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

static var _pouch_materials: Dictionary = {}  # colour -> StandardMaterial3D


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
			if slot != &"helmet":  # a plate sits inside the carrier's pocket, under its fabric
				piece.set_cover(Color(VoxelArt.VARIANTS.get(model.variant, VoxelArt.VARIANTS.multicam).gear) if carrier else Color(0, 0, 0, 0))
	for slot: StringName in MOUNTS:
		var mount: Array = MOUNTS[slot]
		_set_gear(slot, inventory.slots[slot], mount[0], mount[1], mount[2])
	var pack: StringName = inventory.slots[&"backpack"]
	var pack_depth := VoxelArt.size_m(VoxelArt.model_for(ItemDB.get_item(pack))).z if pack != &"" else 0.0
	_set_gear(&"backpack", pack, &"torso", Vector3(0, 0.3, 0.165 + pack_depth * 0.5), Vector3.ZERO)
	var held := inventory.hands
	var held_size := WorldItem.visual_size(ItemDB.get_item(held)) if held != &"" else Vector3.ZERO
	_set_gear(&"hands", held, &"torso", Vector3(0, 0.15, -0.15 - held_size.z * 0.5), Vector3.ZERO)
	_set_pouches()
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
		node.transform = point_transform(p, WorldItem.visual_size(ItemDB.get_item(StringName(att.id))))
		_pouches.add_child(node)


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
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var key := colour.to_html()
	if not _pouch_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.95
		_pouch_materials[key] = material
	box.material = _pouch_materials[key]
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.layers = layers
	return mesh_instance


func _process(delta: float) -> void:
	_clock += delta
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
		var rest: Array = MOUNTS[_held_key]
		var previous: Node3D = _gear[_held_key][1]
		previous.reparent(model.torso, false)
		previous.position = rest[1]
		previous.rotation = rest[2]
	_held_key = key
	_held_dirty = false
	model.clear_held()
	if not _gear.has(key):
		return
	var node: Node3D = _gear[key][1]
	if key == &"hands":
		# Bulky item stays in front of the torso; palms press on its sides.
		var half := WorldItem.visual_size(ItemDB.get_item(inventory.hands)).x * 0.5
		model.set_held(node, Vector3(half, 0, 0), Vector3(-half, 0, 0))
		return
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	if points.is_empty():
		return
	node.reparent(model.hands_anchor, false)
	node.position = HELD_POSES[key]
	node.rotation = Vector3.ZERO
	model.set_held(node, points.grip, points.support)


## Torso-local point where the right hand takes hold of the weapon in `key` on its rest
## mount (its grip, or the mount itself).
func _rest_grip(key: StringName) -> Vector3:
	var rest: Array = MOUNTS[key]
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	var grip: Vector3 = points.get("grip", Vector3.ZERO)
	return Transform3D(Basis.from_euler(rest[2]), rest[1]) * grip


## Replays armor chips into the meshes, skipping pieces whose chip list hasn't grown.
func _refresh_plate_damage() -> void:
	for slot: StringName in _armor:
		var chips := inventory.chips_in(slot)
		if chips.size() != _chip_counts.get(slot, -1):
			_armor[slot].apply_damage(chips, ArmorRules.is_shattered(inventory.state_of(slot)))
			_chip_counts[slot] = chips.size()


func _set_gear(key: StringName, id: StringName, mount: StringName, pos: Vector3, rot: Vector3) -> void:
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
	node.position = pos
	node.rotation = rot
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
