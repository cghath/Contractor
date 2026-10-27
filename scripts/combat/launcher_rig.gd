class_name LauncherRig
extends Node3D
## The launcher a soldier carries, drawn on every peer (wave 5, V2): slung across the back,
## or on the shoulder in both hands while it's the active weapon (active_slot "launcher",
## replicated). Drawn as its voxel model from the ground (ItemArt), held on its own grips (HOLDS). Launchers keeps one on each
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
			_model = make_model(ItemDB.get_item(id), PlayerInput.LOCAL_BODY_LAYER if soldier.is_local() else 1)  # yours: seen (full-body first person)
			add_child(_model)
	if _model == null:
		_release()
		return
	var model := soldier.model
	var up := soldier.vitals.is_up() and soldier.carry_mode == &"" and soldier.inventory.hands == &""
	var shouldered := up and soldier.active_slot == Launchers.SLOT and model.hands_anchor != null
	var side := -1.0 if soldier.left_handed else 1.0
	if shouldered:
		var hold := hold_points(ItemDB.get_item(item_id))  # on the shoulder where it rests, the hands on its grips
		global_transform = model.hands_anchor.global_transform * Transform3D(Basis.IDENTITY, SHOULDER * Vector3(side, 1, 1) - hold[0])
		model.set_held(self, hold[1], hold[2])
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


## How each launcher is held (Captain, 2026-10-26: "launchers need work too so their in hand
## visuals match their on ground visuals"), in its ItemArt model's centimetres (muzzle at z 0,
## along +z): [where along the tube it rests on the shoulder, the firing hand's grip, the support
## hand, whether the model lies on its side (grips out to +x: turned upright, grips down)].
const HOLDS := {
	&"rpg7": [76.0, Vector3(6.5, 0, 65.75), Vector3(3.8, 0, 42.0), true],
	&"at4": [80.0, Vector3(4.5, -1.5, 57.0), Vector3(0, -5.5, 34.0), false],
	&"maaws": [72.0, Vector3(9.0, 0, 49.75), Vector3(9.0, 0, 23.75), true],
	&"smaw": [58.0, Vector3(8.5, 0, 45.75), Vector3(8.5, 0, 27.75), true],
	&"nlaw": [80.0, Vector3(0, -8.5, 63.5), Vector3(0, -7.5, 34.0), false],
	&"javelin_clu": [92.0, Vector3(11.5, 14.0, 59.5), Vector3(-11.5, 14.0, 59.5), false],
}


## `item`'s model lying along -Z (the muzzle forward), its top up, centred on the tube's middle:
## the voxel model it has on the ground (ItemArt), turned upright. A launcher with no hold yet
## (HOLDS) gets the old placeholder: a tube of its length and calibre with a grip and sight box.
static func make_model(item: ItemData, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Launcher"
	if item == null:
		return root
	if HOLDS.has(item.id):
		var entry := ItemArt.own_mesh(item)
		var origin: Vector3 = entry[2]
		var size: Vector3 = entry[3]
		var mi := MeshInstance3D.new()
		mi.mesh = entry[0]
		mi.material_override = VoxelArt._get_material()
		mi.layers = layers
		var turn := _upright(item)
		var mid := Vector3(0, 0, origin.z + size.z * 0.5)  # the tube's middle, on its axis
		mi.transform = Transform3D(turn.scaled(Vector3.ONE * float(entry[1])), turn * ((origin - mid) * 0.01))
		root.add_child(mi)
		return root
	return _placeholder(item, layers)


## Its model turned upright (HOLDS: one lying on its side turns its grips down).
static func _upright(item: ItemData) -> Basis:
	return Basis(Vector3.BACK, -PI * 0.5) if bool(HOLDS[item.id][3]) else Basis.IDENTITY


## A point on `item`'s model (its ItemArt centimetres) in make_model's space.
static func model_point(item: ItemData, cm: Vector3) -> Vector3:
	var entry := ItemArt.own_mesh(item)
	var mid := Vector3(0, 0, (entry[2] as Vector3).z + (entry[3] as Vector3).z * 0.5)
	return _upright(item) * ((cm - mid) * 0.01)


## Where `item` rests on the shoulder, its firing hand and its support hand, in make_model's space.
static func hold_points(item: ItemData) -> Array[Vector3]:
	if item == null or not HOLDS.has(item.id):
		return [Vector3.ZERO, GRIP, SUPPORT]
	var h: Array = HOLDS[item.id]
	return [model_point(item, Vector3(0, 0, float(h[0]))), model_point(item, h[1]), model_point(item, h[2])]


static func _placeholder(item: ItemData, layers: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Launcher"
	var size: Array = item.stats.get("size_m", [0.1, 0.1, 1.0])
	var length := float(size[2])
	var radius := maxf(float(item.stats.get("calibre_mm", 84)) / 2000.0 + 0.012, 0.03)
	var colour := Color("55583f")
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
	sight.material = _material(colour.darkened(0.25))
	root.add_child(_mesh(sight, Vector3(-radius - sight.size.x * 0.5, radius * 0.6, -0.05), Vector3.ZERO, layers))
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
