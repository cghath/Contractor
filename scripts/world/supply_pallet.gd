class_name SupplyPallet
extends StaticBody3D
## A supply pallet lying at an enemy site (feat/pallet-tagging, Pallets): a wooden pallet with a
## load of crates, drums or a bladder, coloured by its kind. Built locally on every peer from the
## same site table (PalletField), so its kind and contents (Pallets.roll) agree everywhere; only
## its tag is shared (PalletField). Use it from the interaction menu: Tag to sell, Tag for a
## faction, Untag, Check pallet. The look is a placeholder from make_visual().

const SIZE := Vector3(1.2, 1.0, 1.0)
const POINT_LIFT := 0.12

var uid := ""
var kind := "supplies"
var field: PalletField
var _label: Label3D


func _init(p_uid := "", p_kind := "supplies") -> void:
	uid = p_uid
	kind = p_kind
	name = ("Pallet_" + p_uid).validate_node_name()
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y / 2.0
	add_child(shape)
	add_child(make_visual(kind))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.no_depth_test = true
	_label.position.y = SIZE.y + 0.6
	_label.visible = false
	add_child(_label)


static func make_visual(p_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(SIZE.x, 0.15, SIZE.z)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("8a6a3e")
	base_mesh.material = wood
	base.mesh = base_mesh
	base.position.y = 0.075
	root.add_child(base)
	var load_mesh := MeshInstance3D.new()
	var shape: Mesh
	if p_kind.begins_with("fuel"):
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.28
		cyl.height = 0.85 if p_kind == "fuel_drums" else 0.4
		shape = cyl
	else:
		var b := BoxMesh.new()
		b.size = Vector3(SIZE.x - 0.1, SIZE.y - 0.2, SIZE.z - 0.1)
		shape = b
	var material := StandardMaterial3D.new()
	material.albedo_color = Pallets.kind_colour(p_kind)
	shape.material = material
	load_mesh.mesh = shape
	load_mesh.position.y = 0.15 + (SIZE.y - 0.15) / 2.0
	root.add_child(load_mesh)
	return root


func action_point() -> Vector3:
	return global_position + Vector3.UP * (SIZE.y + POINT_LIFT)


func lot() -> Dictionary:
	return Pallets.pallet_lot(kind, uid)


## Redraws the tag marker over the pallet (PalletField calls it on every peer).
func show_tag(text: String, colour: Color) -> void:
	if _label == null:
		return
	_label.visible = text != ""
	_label.text = text
	_label.modulate = colour


func interaction_actions(actor: Node) -> Array[Dictionary]:
	if field == null or not is_instance_valid(field):
		return []
	var out: Array[Dictionary] = field.tag_entries(uid, self, actor)
	var me := self
	out.append({"id": &"check_pallet", "label": "Check pallet", "disabled": "", "target": self,
		"call": func() -> void: PalletField.say(actor, Pallets.lot_text(me.lot())), "group": InteractionMenu.MORE})
	return out
