class_name LauncherRig
extends Node3D
## The launcher a soldier carries, drawn on every peer (wave 5, V2): slung across the back,
## or on the shoulder in both hands while it's the active weapon (active_slot "launcher",
## replicated). Placeholder art: tubes and boxes by the launcher's size and calibre, until a
## voxel launcher model arrives (Captain's art; swap make_model). Launchers keeps one on each
## soldier that carries a launcher and frees it when they don't. The local player's own is on
## PlayerInput.LOCAL_ONLY_LAYER like the rest of their body; their first-person launcher is
## make_model on the view model (LauncherSight.view_node).

## Shouldered, in CharacterModel.hands_anchor space (shoulder height, pitches with the aim),
## right-handed (x mirrors for left): the tube's middle sits on the firing shoulder, the
## firing hand on the grip under it and the support hand forward on the tube.
const SHOULDER := Vector3(0.1, 0.07, 0.0)
const GRIP := Vector3(0.0, -0.08, -0.12)
const SUPPORT := Vector3(0.0, -0.06, -0.38)
## Slung, torso-local: diagonally across the back.
const SLUNG := Vector3(0.0, 0.32, 0.2)
const SLUNG_TILT := 0.55

var soldier: Soldier
var item_id: StringName = &""
var _model: Node3D
var _held := false


func _init(s: Soldier) -> void:
	soldier = s
	name = "LauncherRig"


func _process(_delta: float) -> void:
	if not is_instance_valid(soldier):
		queue_free()
		return
	var id: StringName = soldier.inventory.slots.get(Launchers.SLOT, &"")
	if id != item_id:
		item_id = id
		if _model:
			_model.queue_free()
			_model = null
		if id != &"":
			_model = make_model(ItemDB.get_item(id), 1 << 1 if soldier.is_local() else 1)
			add_child(_model)
	if _model == null:
		_release()
		return
	var model := soldier.model
	var up := soldier.vitals.is_up() and soldier.carry_mode == &"" and soldier.inventory.hands == &""
	var shouldered := up and soldier.active_slot == Launchers.SLOT and model.hands_anchor != null
	var side := -1.0 if soldier.left_handed else 1.0
	if shouldered:
		global_transform = model.hands_anchor.global_transform * Transform3D(Basis.IDENTITY, SHOULDER * Vector3(side, 1, 1))
		model.set_held(self, GRIP, SUPPORT)
		_held = true
	else:
		_release()
		if model.torso:
			global_transform = model.torso.global_transform * Transform3D(Basis(Vector3.FORWARD, SLUNG_TILT * side) * Basis(Vector3.RIGHT, PI * 0.5), SLUNG)


func _release() -> void:
	if _held:
		_held = false
		# Only let go of what the hands hold if it's still this launcher (GearRig may have put
		# the rifle there since).
		if is_instance_valid(soldier) and soldier.model.get(&"_held") == self:
			soldier.model.clear_held()


func _exit_tree() -> void:
	_release()


## A placeholder model of `item` lying along -Z (the muzzle forward), centred: a tube of its
## length and calibre in its colour, with a grip and sight box, and the warhead of an RPG-7.
static func make_model(item: ItemData, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Launcher"
	if item == null:
		return root
	var size: Array = item.stats.get("size_m", [0.1, 0.1, 1.0])
	var length := float(size[2])
	var radius := maxf(float(item.stats.get("calibre_mm", 84)) / 2000.0 + 0.012, 0.03)
	var colour: Color = {"at4": Color("6b6a3f"), "rpg7": Color("3b3a36"), "javelin_clu": Color("575c3e"),
		"maaws": Color("4a4e47"), "nlaw": Color("5d6146"), "smaw": Color("4b5038")}.get(String(item.id), Color("55583f"))
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = length
	tube.radial_segments = 10
	tube.material = _material(colour)
	root.add_child(_mesh(tube, Vector3.ZERO, Vector3(-PI * 0.5, 0, 0), layers))
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.1, 0.05)
	box.material = _material(colour.darkened(0.4))
	root.add_child(_mesh(box, Vector3(0, -radius - 0.04, -0.12), Vector3.ZERO, layers))  # grip
	var sight := BoxMesh.new()
	sight.size = Vector3(0.05, 0.06, 0.12) if String(item.stats.get("sight", "iron")) != "iron" else Vector3(0.015, 0.04, 0.02)
	if item.id == &"javelin_clu":
		sight.size = Vector3(0.22, 0.16, 0.24)  # the command launch unit's box
	sight.material = _material(colour.darkened(0.25))
	root.add_child(_mesh(sight, Vector3(-radius - sight.size.x * 0.5 if item.id != &"javelin_clu" else -radius - 0.1, radius * 0.6, -0.05), Vector3.ZERO, layers))
	if item.id == &"rpg7":
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = 0.0425
		head.height = 0.3
		head.material = _material(Color("4d5a3a"))
		root.add_child(_mesh(head, Vector3(0, 0, -length * 0.5 - 0.15), Vector3(-PI * 0.5, 0, 0), layers))
	return root


static func _mesh(mesh: Mesh, pos: Vector3, rot: Vector3, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.layers = layers
	return mi


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	return m
