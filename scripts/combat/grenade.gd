class_name Grenade
extends RigidBody3D
## A thrown grenade on its fuse. Spawned on every peer by CompoundLevel.show_throw with the
## same start position and velocity; only the host's copy detonates.

var item_id: StringName
var kind := "frag"
## Host only: who threw it (CompoundLevel.server_throw), so its fragments count against them (Harm).
var thrower: Node
var _fuse := 3.0
## A thrown chem light settles once it's slower than this (m/s), or this long after its fuse.
const CHEMLIGHT_REST_MS := 0.3
const CHEMLIGHT_ROLL_S := 3.0


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
	if kind == "smoke" and item.stats.get("smoke_colour", "white") != "white":
		colour = SmokeCloud.colour_value(SmokeCloud.colour_of(id)).darkened(0.25)  # coloured smokes show their colour
	if kind == "chemlight":
		add_child(Demolitions.make_visual(id))  # a glow stick in flight, already glowing (Demolitions)
	else:
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
	if kind == "chemlight" and linear_velocity.length() > CHEMLIGHT_REST_MS and _fuse > -CHEMLIGHT_ROLL_S:
		return  # a chem light settles where it stops rolling (Demolitions)
	if multiplayer.is_server():
		Harm.blast_source = thrower if is_instance_valid(thrower) else null
		Throwables.server_detonate(CompoundLevel.current(self), kind, global_position, item_id)
		Harm.blast_source = null
		if kind != "smoke" and kind != "chemlight":
			PeopleLayer.server_noise(self, global_position, PeopleLayer.BLAST_HEARD_M)  # people nearby hear it
			Alert.server_noise(self, global_position, Alert.BLAST)
	queue_free()
