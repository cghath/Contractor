class_name WorldItem
extends RigidBody3D
## An item lying in the world. Spawned by the level's ItemSpawner on the host and
## replicated to every peer; only the host simulates physics, clients follow the synced
## transform.

var item_id: StringName
var count := 1
## Stable id for persistence (see GameState). Also used as the node name.
var uid := ""


func _init() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 2)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop: NodePath in [^".:position", ^".:rotation", ^".:count"]:
		config.add_property(prop)
		config.property_set_spawn(prop, true)
		config.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
	add_child(sync)


func _ready() -> void:
	add_to_group(&"world_items")
	freeze = not multiplayer.is_server()
	var item := ItemDB.get_item(item_id)
	var art := VoxelArt.model_for(item)
	var is_armor := item.type == "plate" or item.slot == &"helmet"
	var size := visual_size(item)
	if is_armor:
		size = VoxelArmor.size_m(item)
		var mesh := VoxelArmor.make_mesh_instance(item)
		mesh.position = -size * 0.5  # centred on the body, like the collision box
		add_child(mesh)
	elif art != "":
		size = VoxelArt.size_m(art)
		add_child(VoxelArt.instance(art, "multicam"))
	else:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = color_for(item)
		box.material = material
		mesh_instance.mesh = box
		add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	add_child(shape)
	mass = maxf(item.mass_kg, 0.1)


func describe() -> String:
	var item := ItemDB.get_item(item_id)
	var verb := "Carry" if item.two_handed else "Take"
	var amount := " x%d" % count if count > 1 else ""
	return "[E] %s %s%s   %.1f L  %.1f kg" % [verb, item.name, amount, item.volume_l * count, item.mass_kg * count]


## Placeholder box size: explicit `size_m` from item stats, else a cube of the item's volume.
static func visual_size(item: ItemData) -> Vector3:
	if item.stats.has("size_m"):
		var s: Array = item.stats["size_m"]
		return Vector3(s[0], s[1], s[2])
	var edge := pow(maxf(item.volume_l, 0.05) / 1000.0, 1.0 / 3.0)
	return Vector3.ONE * edge


static func color_for(item: ItemData) -> Color:
	match item.type:
		"weapon": return Color("2b2b2b")
		"ammo": return Color("b08d3c")
		"armor", "plate": return Color("5b6650")
		"backpack": return Color("6e5b3e")
		"medical": return Color("c23b3b")
		"utility": return Color("3f5f7a")
		"objective": return Color("d9a400")
		_: return Color("8a8a8a")
