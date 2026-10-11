class_name WoundMarks
extends Node3D
## The body's wounds drawn where they are: an entry hole where a round went in and a bigger,
## ragged exit hole where it came out, on the bone of the part that was hit, so they move
## with the limb; once treated, a dressing over the spot. Positions come from the wounds'
## "at" and "out" (rest pose, Vitals.wound_list, replicated), so every peer draws the same.

const ENTRY_COLOUR := Color("4a0f0c")
const EXIT_COLOUR := Color("6b1510")
const DRESSING_COLOUR := Color("d8d0b8")
const ENTRY_SIZE := 0.012
const EXIT_SIZE := 0.024
const DRESSING_SIZE := 0.05

var model: CharacterModel
var vitals: Vitals
var _marks: Array[Node3D] = []
var _key := ""
static var _materials: Dictionary = {}  # colour -> StandardMaterial3D


func setup(p_model: CharacterModel, p_vitals: Vitals) -> void:
	model = p_model
	vitals = p_vitals
	vitals.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	var wounds := vitals.wound_list() if is_instance_valid(vitals) else []
	var key := ""
	for w: Dictionary in wounds:
		if w.get("at") is Vector3:
			key += "%s%s%s%s|" % [w.part, w.at, w.get("out"), w.treated]
	if key == _key:
		return
	_key = key
	for mark in _marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_marks.clear()
	var drawn := {}  # one mark per spot: several wounds from one round share their holes
	for w: Dictionary in wounds:
		var at: Variant = w.get("at")
		if not at is Vector3:
			continue
		var spot := "%s%s" % [w.part, at]
		if drawn.has(spot):
			if w.treated:
				drawn[spot].treated = true
			continue
		drawn[spot] = {"part": w.part, "at": at, "out": w.get("out"), "treated": w.treated}
	for spot: Dictionary in drawn.values():
		var bone := model.part_node(spot.part)
		if bone == null:
			continue
		var pivot := BodyVolume.pivot_at(spot.part)
		if spot.treated:
			_mark(bone, Vector3(spot.at) - pivot, DRESSING_SIZE, DRESSING_COLOUR)
		else:
			_mark(bone, Vector3(spot.at) - pivot, ENTRY_SIZE, ENTRY_COLOUR)
		if spot.out is Vector3:
			_mark(bone, Vector3(spot.out) - pivot, DRESSING_SIZE if spot.treated else EXIT_SIZE, DRESSING_COLOUR if spot.treated else EXIT_COLOUR)


func _mark(bone: Node3D, local: Vector3, size: float, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(colour)
	node.layers = model.render_layers
	node.position = local
	node.name = "WoundMark"
	bone.add_child(node, true)  # readable names (WoundMark, WoundMark2...), not @WoundMark@n
	_marks.append(node)


static func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.6
		_materials[key] = m
	return _materials[key]
