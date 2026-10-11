class_name PersonLook
extends RefCounted
## Placeholder looks for civilians and HVTs (wave 4, W11), all behind dress(), so Noah's
## character art can replace them in one place: a soldier body in a plain colour scheme with
## a coloured shirt over the torso, and headwear for an HVT (a red band on a hostile one).

## Shirt colours civilians pick from (by name, so every peer picks the same).
const SHIRTS: Array[Color] = [Color("d8d2c0"), Color("7a8fa6"), Color("a65e48"), Color("6b7f4f"), Color("c9a85a"), Color("4f4a6b")]
const HVT_SHIRT := Color("2a2a2e")
const HOSTILE_BAND := Color("b22a2a")
const FRIENDLY_BAND := Color("e8e4d8")


## The soldier colour scheme (VoxelArt.VARIANTS) a person's body uses under the shirt.
static func variant_for(kind: StringName, _side: StringName) -> String:
	return "urban" if kind == Person.HVT else "desert"


## Dresses `body` (a Soldier not yet in the tree) as a `kind` person of `side`. Runs on every
## peer (the spawn function), so everyone sees the same.
static func dress(body: Soldier, kind: StringName, side: StringName) -> void:
	body.ready.connect(_apply.bind(body, kind, side), CONNECT_ONE_SHOT)


static func _apply(body: Soldier, kind: StringName, side: StringName) -> void:
	var model := body.model
	if model == null or model.torso == null:
		return
	var shirt: Color = HVT_SHIRT if kind == Person.HVT else SHIRTS[absi(String(body.name).hash()) % SHIRTS.size()]
	_box(model.torso, Vector3(0.40, 0.44, 0.24), Vector3(0, 0.32, 0), shirt, model.render_layers)
	if kind == Person.HVT and model.head:
		var band := HOSTILE_BAND if side == Person.HOSTILE else FRIENDLY_BAND
		_box(model.head, Vector3(0.24, 0.06, 0.26), Vector3(0, 0.27, 0), band, model.render_layers)


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, layers: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "PersonLook"
	node.mesh = mesh
	node.position = at
	node.layers = layers
	parent.add_child(node)
