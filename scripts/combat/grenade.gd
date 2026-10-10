class_name Grenade
extends RigidBody3D
## A thrown grenade on its fuse. Spawned on every peer by CompoundLevel.show_throw with the
## same start position and velocity; only the host's copy detonates.

var item_id: StringName
var kind := "frag"
var _fuse := 3.0


func setup(id: StringName) -> void:
	item_id = id
	var item := ItemDB.get_item(id)
	kind = String(item.stats.get("throwable", "frag"))
	_fuse = float(item.stats.get("fuse_s", 3.0))
	mass = item.mass_kg
	collision_layer = 0
	collision_mask = 1  # world only: grenades bounce off walls and the ground
	continuous_cd = true
	angular_damp = 2.0
	linear_damp = 0.2
	var colour: Color = {"frag": Color("4b5a3a"), "smoke": Color("7a8a80"), "flash": Color("b8b8c0")}.get(kind, Color.GRAY)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 0.11
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)
	var shape := SphereShape3D.new()
	shape.radius = 0.045
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse > 0.0:
		return
	if multiplayer.is_server():
		Throwables.server_detonate(CompoundLevel.current(self), kind, global_position)
	queue_free()
