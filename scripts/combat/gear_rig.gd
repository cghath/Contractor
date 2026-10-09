class_name GearRig
extends Node3D
## Puts what an Inventory is wearing onto a CharacterModel. Gear is voxel art (VoxelArt)
## mounted on the model's torso or head so it follows the animation; items without a
## voxel model yet fall back to a coloured box. Plates and helmets are VoxelArmor nodes:
## destructible 1 cm voxels that are also the hit targets.

@export var inventory: Inventory
@export var vitals: Vitals
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

var _armor: Dictionary = {}      # slot -> VoxelArmor
var _armor_ids: Dictionary = {}  # slot -> item id last worn; survives _clear()
var _gear: Dictionary = {}    # key -> [item id, Node3D]
var _held_key: StringName = &""  # which _gear entry is in the hands
var _held_dirty := true


func _ready() -> void:
	inventory.changed.connect(_rebuild)
	vitals.changed.connect(_refresh_plate_damage)
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


## Remaining fraction of an armor slot's material, or -1 if nothing is worn there.
func armor_integrity(slot: StringName) -> float:
	var piece: VoxelArmor = _armor.get(slot)
	return piece.integrity() if piece else -1.0


## "Front 87%  Back 100%  Helmet 92%" for HUDs and labels; "" with no armor.
func armor_summary(separator := "  ") -> String:
	var parts := PackedStringArray()
	for slot: StringName in ARMOR_SLOTS:
		var integrity := armor_integrity(slot)
		if integrity >= 0.0:
			parts.append("%s %d%%" % [ARMOR_SLOTS[slot], roundi(integrity * 100.0)])
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
			if multiplayer.is_server() and _armor_ids.get(slot, &"") != id:
				vitals.server_clear_plate(slot)  # damage belonged to the previous piece
			piece = VoxelArmor.new()
			(model.head if slot == &"helmet" else model.torso).add_child(piece)
			piece.setup(ItemDB.get_item(id), slot, vitals, render_layers)
			_armor[slot] = piece
		if piece:
			piece.transform = armor_transform(slot, carrier)
		_armor_ids[slot] = id
	for slot: StringName in MOUNTS:
		var mount: Array = MOUNTS[slot]
		_set_gear(slot, inventory.slots[slot], mount[0], mount[1], mount[2])
	var pack: StringName = inventory.slots[&"backpack"]
	var pack_depth := VoxelArt.size_m(VoxelArt.model_for(ItemDB.get_item(pack))).z if pack != &"" else 0.0
	_set_gear(&"backpack", pack, &"torso", Vector3(0, 0.3, 0.165 + pack_depth * 0.5), Vector3.ZERO)
	var held := inventory.hands
	var held_size := WorldItem.visual_size(ItemDB.get_item(held)) if held != &"" else Vector3.ZERO
	_set_gear(&"hands", held, &"torso", Vector3(0, 0.15, -0.15 - held_size.z * 0.5), Vector3.ZERO)
	_refresh_plate_damage()


func _process(_delta: float) -> void:
	var want := _wanted_in_hands()
	if want != _held_key or _held_dirty:
		_put_in_hands(want)


func _wanted_in_hands() -> StringName:
	if inventory.hands != &"":
		return &"hands"
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


func _refresh_plate_damage() -> void:
	for slot: StringName in _armor:
		_armor[slot].apply_damage(vitals.plate_damage.get(slot, []))


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
