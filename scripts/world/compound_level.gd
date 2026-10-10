class_name CompoundLevel
extends Node3D
## Gray-box hostile compound: flat ground, 10 cm voxel walls you can shoot through, loot,
## and armored target dummies. Owns player and item spawning for the session.

const PLAYER_SCENE := preload("res://scenes/soldier.tscn")
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
	{"uid": "c01_smoke_a", "id": "smoke_grenade", "count": 3, "pos": Vector3(7, 0.5, 4)},
	{"uid": "c01_flash_a", "id": "flashbang", "count": 3, "pos": Vector3(8, 0.5, 4)},
	{"uid": "c01_salvage_a", "id": "electronics_salvage", "count": 8, "pos": Vector3(3, 0.5, -10)},
	{"uid": "c01_m110_a", "id": "m110", "pos": Vector3(-3, 0.5, -10)},
	{"uid": "c01_hvt_case", "id": "hvt_case", "pos": Vector3(0, 0.5, -10)},
	{"uid": "c01_crate_a", "id": "supply_crate", "pos": Vector3(12, 0.6, -12)},
]

## Turn off to host a session without AI (the older test suites do).
static var spawn_ai := true

## The player squad has 8 slots; AI fills the ones players don't (see rebalance_squad).
const SQUAD_SIZE := 8
const SQUAD_CALLSIGNS: Array[String] = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
const SQUAD_LOADOUT := ["plate_carrier", "plate_ceramic_l4", "plate_ceramic_l4", "helmet", "assault_pack", "m4a1",
	"mag_556", "mag_556", "mag_556", "mag_556", "mag_556", "ifak", "trauma_kit", "frag_grenade", "smoke_grenade"]
## Two fire teams: a pair guarding the main building, and a pair patrolling the yard.
const HOSTILES := [
	{"name": "Hostile1", "pos": Vector3(-2.5, 0.1, -10), "buddy": "Hostile2", "guard": true},
	{"name": "Hostile2", "pos": Vector3(2.5, 0.1, -6.5), "buddy": "Hostile1", "guard": true},
	{"name": "Hostile3", "pos": Vector3(-12, 0.1, -2), "buddy": "Hostile4", "guard": false},
	{"name": "Hostile4", "pos": Vector3(-10, 0.1, -3), "buddy": "Hostile3", "guard": false},
]
const HOSTILE_LOADOUT := ["plate_carrier_light", "plate_pe_l3", "helmet_bump", "assault_pack", "mk18",
	"mag_556", "mag_556", "mag_556", "mag_556", "ifak", "frag_grenade"]
const HOSTILE_PATROL: Array[Vector3] = [Vector3(-12, 0, -2), Vector3(-12, 0, -16), Vector3(12, 0, -16), Vector3(12, 0, 0), Vector3(-4, 0, 2)]

@onready var players: Node3D = $Players
@onready var ai: Node3D = $AI
@onready var items: Node3D = $Items
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var ai_spawner: MultiplayerSpawner = $AISpawner
@onready var voxel_world: VoxelWorld = $VoxelWorld

var _spawn_index := 0
var _throw_count := 0
var _squads := {}  # faction -> Squad
var _ai_ready := false  # host: AI spawns once the voxel walls exist


static func current(from: Node) -> CompoundLevel:
	return from.get_tree().get_first_node_in_group(&"level") as CompoundLevel


func squad_for(faction: StringName) -> Squad:
	return _squads.get(faction)


func _ready() -> void:
	add_to_group(&"level")
	item_spawner.spawn_function = _make_item
	ai_spawner.spawn_function = _make_soldier
	for faction: StringName in [&"friendly", &"hostile"]:
		var squad := Squad.new()
		squad.name = "%sSquad" % String(faction).capitalize()
		squad.faction = faction
		add_child(squad)
		_squads[faction] = squad
	_squads[&"hostile"].patrol = HOSTILE_PATROL
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


## Host only. Throws a grenade on every peer; the host's copy detonates (see Grenade).
func server_throw(id: StringName, origin: Vector3, velocity: Vector3) -> void:
	_throw_count += 1
	show_throw.rpc(_throw_count, String(id), origin, velocity)


@rpc("authority", "call_local", "reliable")
func show_throw(serial: int, id: String, origin: Vector3, velocity: Vector3) -> void:
	var grenade := Grenade.new()
	grenade.name = "Grenade%d" % serial
	grenade.setup(StringName(id))
	add_child(grenade)
	grenade.global_position = origin
	grenade.linear_velocity = velocity
	grenade.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


@rpc("authority", "call_local", "reliable")
func show_explosion(pos: Vector3) -> void:
	_burst(pos, Color(1.0, 0.6, 0.25), 3.2, 0.35)


@rpc("authority", "call_local", "reliable")
func show_flash(pos: Vector3) -> void:
	_burst(pos, Color.WHITE, 1.0, 0.15)


@rpc("authority", "call_local", "reliable")
func spawn_smoke(pos: Vector3) -> void:
	var cloud := SmokeCloud.new()
	add_child(cloud)
	cloud.global_position = pos


func _burst(pos: Vector3, colour: Color, size: float, life: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.material = material
	var ball := MeshInstance3D.new()
	ball.mesh = sphere
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 8.0
	light.omni_range = 14.0
	ball.add_child(light)
	add_child(ball)
	ball.global_position = pos + Vector3.UP * 0.3
	var tween := ball.create_tween().set_parallel()
	tween.tween_property(ball, "scale", Vector3.ONE * size, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_property(light, "light_energy", 0.0, life)
	tween.chain().tween_callback(ball.queue_free)


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
	NavBuilder.build(self)
	if spawn_ai:
		# AI needs the walls' collision before it can tell what it can see.
		if voxel_world.is_built():
			_spawn_ai()
		else:
			voxel_world.structures_built.connect(_spawn_ai, CONNECT_ONE_SHOT)


## Host only. Spawns the hostile fire teams and fills the player squad with AI.
func _spawn_ai() -> void:
	_ai_ready = true
	var spawned := {}
	for h: Dictionary in HOSTILES:
		spawned[h.name] = spawn_soldier({"name": h.name, "faction": "hostile", "variant": "urban", "pos": h.pos,
			"loadout": HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": h.guard})
	for h: Dictionary in HOSTILES:
		spawned[h.name].buddy = spawned[h.buddy]
	rebalance_squad()


## Host only. The player squad always has SQUAD_SIZE soldiers: AI fills every slot players
## don't (one player gets 7 squadmates, four players get 4). Called whenever a player joins
## or leaves. Then everyone, players included, is paired into battle buddies.
func rebalance_squad() -> void:
	if not _ai_ready:
		return
	var humans := players.get_children().filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
	var squad := squad_for(&"friendly")
	var members := _squad_ai_by_callsign()
	var want := maxi(SQUAD_SIZE - humans.size(), 0)
	while members.size() > want:
		var leaving: Soldier = members.pop_back()  # a player takes this slot
		leaving.release_carried()
		if is_instance_valid(leaving.carried_by):
			leaving.carried_by.release_carried()
		leaving.queue_free()
	var used := members.map(func(s: Soldier) -> String: return String(s.name))
	for callsign: String in SQUAD_CALLSIGNS:
		if members.size() >= want:
			break
		if callsign in used:
			continue
		var i := SQUAD_CALLSIGNS.find(callsign)
		var anchor: Node3D = squad.leader if is_instance_valid(squad.leader) else null
		var pos := anchor.global_transform * (Squad.FORMATIONS["wedge"][i % 7] as Vector3) if anchor else SPAWN_POINTS[i % SPAWN_POINTS.size()] + Vector3(0, 0, 3)
		members.append(spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
			"loadout": SQUAD_LOADOUT, "combat": 0.5 + 0.03 * (i % 5), "discipline": 0.6, "guard": false}))
	members.sort_custom(func(a: Soldier, b: Soldier) -> bool: return SQUAD_CALLSIGNS.find(String(a.name)) < SQUAD_CALLSIGNS.find(String(b.name)))
	# Battle buddies: players first (host, then joiners), then squadmates in callsign order.
	humans.sort_custom(func(a: Node, b: Node) -> bool: return a.name.to_int() < b.name.to_int())
	var everyone: Array = humans + members
	for i in everyone.size():
		var partner: Soldier = everyone[i ^ 1] if (i ^ 1) < everyone.size() else null
		(everyone[i] as Soldier).buddy = partner


func _squad_ai_by_callsign() -> Array:
	var members := ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == &"friendly" and not s.is_queued_for_deletion())
	members.sort_custom(func(a: Soldier, b: Soldier) -> bool: return SQUAD_CALLSIGNS.find(String(a.name)) < SQUAD_CALLSIGNS.find(String(b.name)))
	return members


## Host only. `data`: name, faction, variant, pos, loadout, and AI stats combat, discipline, guard.
func spawn_soldier(data: Dictionary) -> Soldier:
	return ai_spawner.spawn(data) as Soldier


func _make_soldier(data: Dictionary) -> Node:
	var soldier: Soldier = PLAYER_SCENE.instantiate()
	soldier.name = data.name
	soldier.faction = StringName(data.faction)
	soldier.variant = data.variant
	soldier.position = data.pos
	if multiplayer.is_server():
		var inventory: Inventory = soldier.get_node(^"Inventory")
		for id: String in data.loadout:
			inventory.take(StringName(id))
		var brain := SquadAI.new()
		brain.name = "SquadAI"
		brain.squad = squad_for(soldier.faction)
		brain.combat = data.combat
		brain.discipline = data.discipline
		brain.guard = data.guard
		soldier.add_child(brain)
	return soldier


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	voxel_world.send_edit_log_to(id)
	_add_player(id)


func _on_peer_left(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
	if multiplayer.is_server():
		var squad := squad_for(&"friendly")
		if squad.leader == player:
			squad.leader = players.get_node_or_null(^"1")
		rebalance_squad()


func _add_player(id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = next_spawn_point()
	players.add_child(player, true)
	if id == 1:
		_squads[&"friendly"].leader = player  # the host leads until someone else gives an order
	rebalance_squad()


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
