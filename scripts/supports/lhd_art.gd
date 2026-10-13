class_name LhdArt
extends RefCounted
## The LHD's look (wave 5b, V4): a placeholder amphibious assault ship, about the size of a
## Wasp or America class (LENGTH_M by BEAM_M), built from boxes. build() is the one place
## Captain's art can replace it (keep the frame and the named markers).
##
## Frame: the origin is the middle of the ship at the waterline; -z is the bow, +x starboard,
## y up. The flight deck is DECK_M above the water, the hull DRAFT_M below it. The hull and
## island are solid (layer 1, the world), so helicopters can sit on the deck and nothing sails
## through it. Markers (Node3D children): "Deck" (the middle of the flight deck's aft spots,
## where supports start), "Stern" (the well deck's gate at the waterline).

const LENGTH_M := 257.0
const BEAM_M := 32.0
const DECK_M := 18.0
const DRAFT_M := 8.0
const ISLAND := Vector3(9.0, 22.0, 52.0)  # width, height above the deck, length
const HULL := Color(0.42, 0.45, 0.48)
const BOTTOM := Color(0.36, 0.16, 0.14)
const DECK := Color(0.23, 0.24, 0.25)
const LINES := Color(0.85, 0.82, 0.55)
const GATE := Color(0.12, 0.12, 0.13)


## The ship (see the class doc). `length` and `beam` scale it (data); the rest follows.
static func build(length := LENGTH_M, beam := BEAM_M, deck := DECK_M, draft := DRAFT_M) -> Node3D:
	var root := Node3D.new()
	root.name = "LHD"
	var half := length * 0.5
	var bow := 34.0  # the bow narrows over this much
	# Hull: below the waterline in antifouling red, above it grey; the bow a narrowing wedge.
	_box(root, "Bottom", Vector3(beam * 0.86, draft, length - bow), Vector3(0, -draft * 0.5, bow * 0.5), BOTTOM)
	_box(root, "Sides", Vector3(beam * 0.9, deck - 2.0, length - bow), Vector3(0, (deck - 2.0) * 0.5, bow * 0.5), HULL)
	var wedge := MeshInstance3D.new()
	wedge.name = "Bow"
	var prism := PrismMesh.new()
	prism.size = Vector3(beam * 0.9, bow, deck + draft - 2.0)
	prism.left_to_right = 0.5
	prism.material = _material(HULL)
	wedge.mesh = prism
	wedge.rotation_degrees = Vector3(-90, 0, 0)  # the prism's apex points forward (-z)
	wedge.position = Vector3(0, (deck - 2.0 - draft) * 0.5, -half + bow * 0.5)
	root.add_child(wedge)
	# Flight deck: overhanging the sides, dark, with a yellow centre line and spot marks.
	_box(root, "FlightDeck", Vector3(beam, 2.0, length - 6.0), Vector3(0, deck - 1.0, 3.0), DECK)
	_box(root, "DeckLine", Vector3(0.5, 0.05, length - 20.0), Vector3(-beam * 0.18, deck + 0.03, 6.0), LINES)
	for k in 6:
		_box(root, "Spot%d" % k, Vector3(9.0, 0.05, 0.5), Vector3(-beam * 0.18, deck + 0.03, -80.0 + k * 36.0), LINES)
	# The island, starboard, amidships, with its mast.
	_box(root, "Island", ISLAND, Vector3(beam * 0.5 - ISLAND.x * 0.5 - 1.0, deck + ISLAND.y * 0.5, -6.0), HULL.lightened(0.08))
	_box(root, "Mast", Vector3(1.5, 14.0, 1.5), Vector3(beam * 0.5 - ISLAND.x * 0.5 - 1.0, deck + ISLAND.y + 7.0, -8.0), HULL.darkened(0.2))
	# The well deck's stern gate, down at the waterline.
	_box(root, "Gate", Vector3(beam * 0.5, 7.0, 0.4), Vector3(0, 2.5, half + 0.25), GATE)
	# Solid: the hull with the deck on top, and the island.
	var body := StaticBody3D.new()
	body.name = "Hull"
	body.collision_layer = 1
	body.collision_mask = 0
	_shape(body, Vector3(beam * 0.9, deck + draft, length - 6.0), Vector3(0, (deck - draft) * 0.5, 3.0))
	_shape(body, Vector3(beam, 2.0, length - 6.0), Vector3(0, deck - 1.0, 3.0))
	_shape(body, ISLAND, Vector3(beam * 0.5 - ISLAND.x * 0.5 - 1.0, deck + ISLAND.y * 0.5, -6.0))
	root.add_child(body)
	var deck_mark := Node3D.new()
	deck_mark.name = "Deck"
	deck_mark.position = Vector3(-beam * 0.18, deck, half * 0.45)
	root.add_child(deck_mark)
	var stern := Node3D.new()
	stern.name = "Stern"
	stern.position = Vector3(0, 0, half)
	root.add_child(stern)
	return root


static func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, colour: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(colour)
	mesh.mesh = box
	mesh.position = at
	parent.add_child(mesh)


static func _shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	return m
