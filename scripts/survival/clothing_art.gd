class_name ClothingArt
extends RefCounted
## How worn clothes are drawn (call 132; GearRig._rebuild calls dress): simple coloured overlays
## on the voxel body in each item's stats "colour", until the clothes get voxel art of their own.
## The outermost torso layer is a shell over the torso (no carrier on), or its hem and collar
## showing under and over a carrier; a hat sits on the head (not under a helmet); a face layer is
## a band over the mouth and nose. Small detail: no shadows, faded with the gear's small parts.

const TORSO_NODE := &"Clothes"
const HEAD_NODE := &"ClothesHead"
## Proposed sizes (torso-local: the torso spans y 0-0.56 from the hips).
const SHELL := Vector3(0.4, 0.5, 0.25)
const SHELL_Y := 0.28
const HEM := Vector3(0.41, 0.1, 0.26)
const HEM_Y := 0.06
const COLLAR := Vector3(0.24, 0.05, 0.19)
const COLLAR_Y := 0.54
const HAT := Vector3(0.2, 0.08, 0.23)
const HAT_Y := 0.21
const FACE := Vector3(0.16, 0.08, 0.03)
const FACE_POS := Vector3(0, 0.07, -0.11)


## Puts `inv`'s worn clothes on `model` (render `layers`), replacing what was drawn.
static func dress(model: CharacterModel, inv: Inventory, layers: int, carrier_on: bool, helmet_on: bool) -> void:
	if model == null or inv == null or model.torso == null or model.head == null:
		return
	var key := "%s|%s|%s|%d" % [",".join(PackedStringArray(Clothing.worn(inv).map(func(w: Dictionary) -> String: return String(w.id)))), carrier_on, helmet_on, layers]
	if String(model.get_meta(&"clothes_key", "")) == key:
		return
	model.set_meta(&"clothes_key", key)
	for parent: Node3D in [model.torso, model.head]:
		for name: StringName in [TORSO_NODE, HEAD_NODE]:
			var old := parent.get_node_or_null(NodePath(name))
			if old:
				old.queue_free()
				parent.remove_child(old)
	var top: ItemData = null
	for slot: StringName in Clothing.TORSO_OUT_IN:
		var id := StringName(inv.slots.get(slot, &""))
		if id != &"" and ItemDB.has_item(id):
			top = ItemDB.get_item(id)
			break
	var g := model.girth("torso")
	if top:
		var torso := Node3D.new()
		torso.name = TORSO_NODE
		var c := colour_of(top)
		if carrier_on:
			torso.add_child(_box(Vector3(HEM.x * g, HEM.y, HEM.z * g), Vector3(0, HEM_Y, 0), c, layers))
			torso.add_child(_box(COLLAR, Vector3(0, COLLAR_Y, 0), c, layers))
		else:
			torso.add_child(_box(Vector3(SHELL.x * g, SHELL.y, SHELL.z * g), Vector3(0, SHELL_Y, 0), c, layers))
		model.torso.add_child(torso)
	var head := Node3D.new()
	head.name = HEAD_NODE
	var hat := StringName(inv.slots.get(&"head", &""))
	if hat != &"" and not helmet_on and ItemDB.has_item(hat):
		head.add_child(_box(HAT, Vector3(0, HAT_Y, 0), colour_of(ItemDB.get_item(hat)), layers))
	var face := StringName(inv.slots.get(&"face", &""))
	if face != &"" and ItemDB.has_item(face):
		head.add_child(_box(FACE, FACE_POS, colour_of(ItemDB.get_item(face)), layers))
	if head.get_child_count() > 0:
		model.head.add_child(head)
	else:
		head.free()


## An item's colour: its stats' "colour", else by its camo tag.
static func colour_of(item: ItemData) -> Color:
	var hex := String(item.stats.get("colour", ""))
	if hex != "":
		return Color(hex)
	match String(item.stats.get("camo", "")):
		"woodland":
			return Color("4d5536")
		"desert":
			return Color("b9a77e")
		"snow":
			return Color("dfe3e6")
		"bright":
			return Color("c9a227")
	return Color("55524a")


static func _box(size: Vector3, pos: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.95
	box.material = mat
	mi.mesh = box
	mi.position = pos
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
