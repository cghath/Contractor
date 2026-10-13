class_name BaseTerminal
extends StaticBody3D
## A desk, board or kiosk at the base hub that opens one page of the base screen (BaseUI):
## the hiring board, the medbay desk, the shop terminal, the ops desk (squad, roster,
## deploy), the armory ledger, and the motor pool's sign (vehicles come in wave 5). Built
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
	&"motor_pool": {"title": "Motor pool", "page": "", "colour": Color("4f5559")},
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
	if kind == &"motor_pool":
		return _motor_pool_actions()
	if page == "":
		return [{"id": &"use", "label": "%s (vehicles in wave 5)" % title(), "disabled": "No vehicles yet"}]
	return [{"id": &"use", "label": "Use %s" % title(), "disabled": "", "call": BaseHub.open_ui.bind(page)}]


## Wave 5b (V4): the motor pool's sign lists the company's vehicles (MotorPoolNode's copy of the
## pool) and books one into the workshop: every hit zone, the battery and the hull fixed and the
## tank filled, for money and days (MotorPool.server_repair, on the host).
func _motor_pool_actions() -> Array[Dictionary]:
	var node := MotorPoolNode.of(self)
	var out: Array[Dictionary] = []
	var pool: Array = node.pool if node else []
	if pool.is_empty():
		return [{"id": &"use", "label": "Motor pool: no vehicles", "disabled": "The company owns no vehicles"}]
	for v: Dictionary in pool:
		var quote: Dictionary = v.get("quote", {})
		var why := String(v.get("problem", ""))
		var label := "%s: %d%% damaged, %d L" % [String(v.name), roundi(float(v.get("damage", 0.0)) * 100.0), roundi(float(v.get("fuel", 0.0)))]
		if why == "" and (int(quote.get("cost", 0)) > 0 or int(quote.get("days", 0)) > 0):
			label += " | Service: $%s, %d day%s" % [DebriefCalc.money(int(quote.cost)), int(quote.days), "" if int(quote.days) == 1 else "s"]
		elif why == "":
			why = "Ready"
		out.append({"id": StringName("repair_" + String(v.id)), "label": label, "disabled": why, "call": node.request_repair.bind(String(v.id))})
	return out
