class_name BaseTerminal
extends StaticBody3D
## A desk, board or kiosk at the base hub that opens one page of the base screen (BaseUI):
## the hiring board, the medbay desk, the shop terminal, the ops desk (squad, roster,
## deploy), the armory ledger, the motor pool's sign (the company's vehicles) and, on the LHD,
## the memorial wall (the fallen: BaseUI's "memorial" page). Built
## locally on every peer like the voxel structures. Use it from the interaction menu (hold
## Left Ctrl and look at it): it's in the "interactables" group and offers its actions.
##
## The look is a placeholder from make_visual(), the one place Noah's art swaps in.

const GROUP := &"interactables"
## What each kind is called and which BaseUI page it opens ("" for none yet).
const KINDS := {
	&"hiring": {"title": "Hiring board", "page": "hiring", "colour": Color("c9a26b")},
	&"medbay": {"title": "Medbay desk", "page": "medbay", "colour": Color("d8d8d8")},
	&"shop": {"title": "Shop terminal", "page": "shop", "colour": Color("5d7fa3")},
	&"ops": {"title": "Ops desk", "page": "squad", "colour": Color("6f7d5c")},
	&"armory": {"title": "Armory ledger", "page": "armory", "colour": Color("7a6a4f")},
	&"motor_pool": {"title": "Motor pool", "page": "motor_pool", "colour": Color("4f5559")},
	&"stores": {"title": "Supply cage", "page": "stores", "colour": Color("6b7a4f")},
	&"memorial": {"title": "Memorial wall", "page": "memorial", "colour": Color("3a3d40")},
}
const SIZE := Vector3(1.0, 1.2, 0.5)
## The action point sits this far above the top, so the sight check clears the desk itself.
const POINT_LIFT := 0.12

var kind: StringName = &"ops"


func _init(p_kind: StringName = &"ops") -> void:
	kind = p_kind
	name = "Terminal_%s" % String(p_kind)
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(GROUP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y / 2.0
	add_child(shape)
	add_child(make_visual(kind))


func title() -> String:
	return String(KINDS.get(kind, {}).get("title", "Terminal"))


## The terminal's look (placeholder: a coloured desk with a sign over it).
static func make_visual(p_kind: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = KINDS.get(p_kind, {}).get("colour", Color.GRAY)
	box.material = material
	mesh.mesh = box
	mesh.position.y = SIZE.y / 2.0
	root.add_child(mesh)
	var label := Label3D.new()
	label.text = String(KINDS.get(p_kind, {}).get("title", "Terminal"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.004
	label.position.y = SIZE.y + 0.55
	root.add_child(label)
	return root


## Where the interaction menu puts the action point.
func action_point() -> Vector3:
	return global_position + Vector3.UP * (SIZE.y + POINT_LIFT)


## The interaction menu's entries for this terminal: {"id", "label", "disabled", "call"
## (a local Callable the menu runs)}.
func interaction_actions(_actor: Node) -> Array[Dictionary]:
	var page := String(KINDS.get(kind, {}).get("page", ""))
	if page == "":
		return [{"id": &"use", "label": "%s (not open yet)" % title(), "disabled": "Nothing here yet"}]
	## The motor pool opens its page of the base screen like the other terminals (Captain,
	## 2026-10-14: "all the UIs need a pass"; audit P2-23): its ring of one entry per vehicle
	## (wave 5b, V4) is now the page's list, with the workshop's Service button on each.
	return [{"id": &"use", "label": "Use %s" % title(), "disabled": "", "call": BaseHub.open_ui.bind(page),
		"hint": String(BaseUI.ABOUT.get(page, ""))}]  # what it's for, under the cursor (ui-modern)
