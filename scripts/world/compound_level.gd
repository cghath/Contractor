class_name CompoundLevel
extends Node3D
## Gray-box hostile compound: flat ground, 10 cm voxel walls you can shoot through, loot,
## and armored target dummies. Owns player and item spawning for the session.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SPAWN_POINTS: Array[Vector3] = [Vector3(-3, 0.1, 24), Vector3(-1, 0.1, 24), Vector3(1, 0.1, 24), Vector3(3, 0.1, 24)]
const COMPOUND_HALF := 20.0
const WALL_THICKNESS := 0.3

## Starting loot. Each uid is stable so a pickup stays picked up across saves.
const LOOT := [
	{"uid": "c01_carrier_a", "id": "plate_carrier", "pos": Vector3(-2, 0.5, 21)},
	{"uid": "c01_plate_a", "id": "plate_steel_l3", "pos": Vector3(-1, 0.5, 21)},
	{"uid": "c01_plate_b", "id": "plate_ceramic_l4", "pos": Vector3(0, 0.5, 21)},
	{"uid": "c01_m4_a", "id": "m4a1", "pos": Vector3(1, 0.5, 21)},
	{"uid": "c01_m17_a", "id": "m17", "pos": Vector3(2, 0.5, 21)},
	{"uid": "c01_pack_a", "id": "assault_pack", "pos": Vector3(3, 0.5, 21)},
	{"uid": "c01_mags_a", "id": "mag_556", "count": 6, "pos": Vector3(-3, 0.5, 21)},
	{"uid": "c01_carrier_b", "id": "plate_carrier", "pos": Vector3(-2, 0.5, 19.5)},
	{"uid": "c01_plate_c", "id": "plate_steel_l3", "pos": Vector3(-1, 0.5, 19.5)},
	{"uid": "c01_mk18_a", "id": "mk18", "pos": Vector3(1, 0.5, 19.5)},
	{"uid": "c01_ruck_a", "id": "ruck_45", "pos": Vector3(3, 0.5, 19.5)},
	{"uid": "c01_helmet_a", "id": "helmet", "pos": Vector3(0, 0.5, 19.5)},
	{"uid": "c01_carrier_light", "id": "plate_carrier_light", "pos": Vector3(-5, 0.5, 21)},
	{"uid": "c01_plate_pe", "id": "plate_pe_l3", "pos": Vector3(-5, 0.5, 22)},
	{"uid": "c01_helmet_bump", "id": "helmet_bump", "pos": Vector3(-5, 0.5, 23)},
	{"uid": "c01_carrier_heavy", "id": "plate_carrier_heavy", "pos": Vector3(5, 0.5, 21)},
	{"uid": "c01_helmet_heavy", "id": "helmet_heavy", "pos": Vector3(5, 0.5, 22)},
	{"uid": "c01_side_a", "id": "plate_side", "pos": Vector3(5.5, 0.5, 23)},
	{"uid": "c01_side_b", "id": "plate_side", "pos": Vector3(4.5, 0.5, 23)},
	{"uid": "c01_ifak_a", "id": "ifak", "count": 2, "pos": Vector3(-6, 0.5, 4)},
	{"uid": "c01_frag_a", "id": "frag_grenade", "count": 3, "pos": Vector3(6, 0.5, 4)},
	{"uid": "c01_salvage_a", "id": "electronics_salvage", "count": 8, "pos": Vector3(3, 0.5, -10)},
	{"uid": "c01_m110_a", "id": "m110", "pos": Vector3(-3, 0.5, -10)},
	{"uid": "c01_hvt_case", "id": "hvt_case", "pos": Vector3(0, 0.5, -10)},
	{"uid": "c01_crate_a", "id": "supply_crate", "pos": Vector3(12, 0.6, -12)},
]

@onready var players: Node3D = $Players
@onready var items: Node3D = $Items
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var voxel_world: VoxelWorld = $VoxelWorld

var _spawn_index := 0


static func current(from: Node) -> CompoundLevel:
	return from.get_tree().get_first_node_in_group(&"level") as CompoundLevel


func _ready() -> void:
	add_to_group(&"level")
	item_spawner.spawn_function = _make_item
	_build_environment()
	_build_structures()
	Net.hosted.connect(_on_hosted)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return SPAWN_POINTS[_spawn_index % SPAWN_POINTS.size()]


## Host only.
func spawn_item(id: StringName, count: int, pos: Vector3, uid: String, state := {}) -> void:
	item_spawner.spawn({"id": String(id), "count": count, "pos": pos, "uid": uid, "state": state})


## Host only. Spawns an item a player dropped and records it for saving.
func server_spawn_dropped(id: StringName, count: int, pos: Vector3, state := {}) -> void:
	var uid := GameState.new_uid()
	GameState.item_dropped(uid, id, count, pos, state)
	spawn_item(id, count, pos, uid, state)


## Marks where a dead player's gear lies (the handoff's map marker, until there's a map).
@rpc("authority", "call_local", "reliable")
func show_gear_marker(pos: Vector3, text: String) -> void:
	var marker := GearMarker.new()
	marker.text = text
	add_child(marker)
	marker.global_position = pos + Vector3.UP * 1.6


@rpc("authority", "call_local", "unreliable")
func show_impact(pos: Vector3, normal: Vector3, kind: String) -> void:
	var mark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = {"plate": Color.CYAN, "body": Color.RED}.get(kind, Color.YELLOW)
	sphere.material = material
	mark.mesh = sphere
	add_child(mark)
	mark.global_position = pos + normal * 0.01
	get_tree().create_timer(4.0).timeout.connect(mark.queue_free)


func _on_hosted() -> void:
	GameState.load_zone()
	voxel_world.load_edits(GameState.voxel_edits)
	for loot: Dictionary in LOOT:
		if not GameState.is_looted(loot.uid):
			spawn_item(StringName(loot.id), loot.get("count", 1), loot.pos, loot.uid)
	for uid: String in GameState.dropped:
		var d: Dictionary = GameState.dropped[uid]
		spawn_item(StringName(d.id), int(d.count), Vector3(d.pos[0], d.pos[1], d.pos[2]), uid, d.get("state", {}))
	_add_player(1)


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	voxel_world.send_edit_log_to(id)
	_add_player(id)


func _on_peer_left(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()


func _add_player(id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = next_spawn_point()
	players.add_child(player, true)


func _make_item(data: Dictionary) -> Node:
	var item := WorldItem.new()
	item.item_id = StringName(data.id)
	item.count = data.count
	item.state = data.get("state", {})
	item.uid = data.uid
	item.name = data.uid
	item.position = data.pos
	return item


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6d6a55")
	plane.material = material
	mesh_instance.mesh = plane
	ground.add_child(mesh_instance)
	add_child(ground)


## Voxel structures, in metres. Gray box only: a walled compound with a south gate, a
## main building with a doorway, low cover and a couple of crates.
func _build_structures() -> void:
	var h := COMPOUND_HALF
	var t := WALL_THICKNESS
	var C := VoxelWorld.Mat.CONCRETE
	# Perimeter, with a 4 m gate in the south wall.
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(h, 2.6, -h + t), C)
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(-h + t, 2.6, h), C)
	voxel_world.add_box_m(Vector3(h - t, 0, -h), Vector3(h, 2.6, h), C)
	voxel_world.add_box_m(Vector3(-h, 0, h - t), Vector3(-2, 2.6, h), C)
	voxel_world.add_box_m(Vector3(2, 0, h - t), Vector3(h, 2.6, h), C)
	# Main building, 10 x 8 m, doorway in the south wall.
	var P := VoxelWorld.Mat.PAINTED
	voxel_world.add_box_m(Vector3(-5, 0, -12), Vector3(5, 3, -12 + t), P)
	voxel_world.add_box_m(Vector3(-5, 0, -12), Vector3(-5 + t, 3, -4), P)
	voxel_world.add_box_m(Vector3(5 - t, 0, -12), Vector3(5, 3, -4), P)
	voxel_world.add_box_m(Vector3(-5, 0, -4 - t), Vector3(-0.6, 3, -4), P)
	voxel_world.add_box_m(Vector3(0.6, 0, -4 - t), Vector3(5, 3, -4), P)
	voxel_world.add_box_m(Vector3(-0.6, 2.2, -4 - t), Vector3(0.6, 3, -4), P)
	# Low cover.
	voxel_world.add_box_m(Vector3(-9, 0, 6), Vector3(-6, 1.1, 6.4), C)
	voxel_world.add_box_m(Vector3(6, 0, 3), Vector3(9, 1.1, 3.4), C)
	voxel_world.add_box_m(Vector3(-1.5, 0, 10), Vector3(1.5, 1.1, 10.4), C)
	# Crates.
	var W := VoxelWorld.Mat.WOOD
	voxel_world.add_box_m(Vector3(-13, 0, -11), Vector3(-12, 1, -10), W)
	voxel_world.add_box_m(Vector3(-12, 0, -11), Vector3(-11, 1, -10), W)
	voxel_world.add_box_m(Vector3(-12.5, 1, -11), Vector3(-11.5, 2, -10), W)
