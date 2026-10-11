class_name DeliveryPoint
extends Node3D
## A placeholder extraction point for people and intel (wave 4, W11): HVTs brought here are
## delivered and intel carried here is banked (PeopleLayer). Any node in GROUP with a
## `radius` works the same, so the map's real extraction point only has to join the group.
## Spawned through PeopleLayer's spawner, so every peer and late joiner sees it.

const GROUP := &"extraction_points"
const DEFAULT_RADIUS := 4.0

@export var radius := DEFAULT_RADIUS
@export var label := "Extraction"


func _ready() -> void:
	add_to_group(GROUP)
	_build_marker()


## The radius of an extraction point node (its `radius`, else DEFAULT_RADIUS).
static func radius_of(point: Node) -> float:
	var r: Variant = point.get(&"radius")
	return float(r) if r != null else DEFAULT_RADIUS


## True if `pos` is inside extraction point `point` (flat distance).
static func covers(point: Node3D, pos: Vector3) -> bool:
	var d := Vector2(pos.x - point.global_position.x, pos.z - point.global_position.z).length()
	return d <= radius_of(point)


## The first extraction point in `tree` that covers `pos`, or null.
static func at(tree: SceneTree, pos: Vector3) -> Node3D:
	for node in tree.get_nodes_in_group(GROUP):
		if node is Node3D and not node.is_queued_for_deletion() and covers(node, pos):
			return node
	return null


## Placeholder look (one function, so real art can replace it): a flat purple disc and a label.
func _build_marker() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.55, 0.3, 0.75, 0.35)
	mesh.material = material
	disc.mesh = mesh
	disc.position.y = 0.02
	add_child(disc)
	var text := Label3D.new()
	text.text = label
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.position.y = 2.2
	text.modulate = Color(0.8, 0.65, 1.0)
	add_child(text)
