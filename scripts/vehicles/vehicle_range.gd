class_name VehicleRange
extends CompoundLevel
## The vehicle range (wave 5 debug level, main menu "Host vehicle range"): flat ground with an
## M-ATV, a MaxxPro, a DShK technical and an AAV-7 parked by the spawn, their holds stocked
## with belts, and a table of vehicle parts, fuel and an M110 to try repairs, refuelling and
## shooting with. A row of concrete blocks and a sandbag wall down the range give the AI driver
## something to steer round. No hostiles; the friendly squad fills in as anywhere (Mount > Get
## in). It saves under its own zone id, so wrecks stay until the save is reset.

const ZONE_ID := "vehicle_range"
## Players appear here, facing the vehicles.
const RANGE_SPAWNS: Array[Vector3] = [Vector3(-3, 0.1, 18), Vector3(-1, 0.1, 18), Vector3(1, 0.1, 18), Vector3(3, 0.1, 18)]
## The parked vehicles (VehicleLayer.server_place_parked).
const PARKED := [
	{"id": "range_matv", "model": "matv", "pos": Vector3(-12, 0, 6), "yaw": 0.0, "cargo": [["belt_50bmg", 2], ["jerrycan", 1]]},
	{"id": "range_maxxpro", "model": "maxxpro", "pos": Vector3(-4, 0, 6), "yaw": 0.0, "cargo": [["belt_50bmg", 2]]},
	{"id": "range_technical", "model": "technical_dshk", "pos": Vector3(4, 0, 6), "yaw": 0.0, "cargo": [["belt_127x108", 2]]},
	{"id": "range_aav7", "model": "aav7", "pos": Vector3(13, 0, 6), "yaw": 0.0, "cargo": [["belt_50bmg", 2]]},
]
## Parts, fuel and ammunition laid out by the spawn.
const RANGE_LOOT := [
	{"uid": "rng_jerrycan", "id": "jerrycan", "count": 2, "pos": Vector3(-6, 0.5, 14)},
	{"uid": "rng_repair", "id": "repair_kit", "count": 2, "pos": Vector3(-5, 0.5, 14)},
	{"uid": "rng_wheel", "id": "spare_wheel", "pos": Vector3(-4, 0.6, 14)},
	{"uid": "rng_tracks", "id": "track_links", "pos": Vector3(-3, 0.5, 14)},
	{"uid": "rng_battery", "id": "vehicle_battery", "pos": Vector3(-2, 0.5, 14)},
	{"uid": "rng_engine", "id": "engine_parts", "pos": Vector3(-1, 0.5, 14)},
	{"uid": "rng_belt50", "id": "belt_50bmg", "count": 2, "pos": Vector3(0, 0.5, 14)},
	{"uid": "rng_rounds", "id": "rounds_556", "count": 120, "pos": Vector3(2, 0.5, 14)},
	{"uid": "rng_m110", "id": "m110", "pos": Vector3(3, 0.5, 14)},
	{"uid": "rng_mags762", "id": "mag_762", "count": 4, "pos": Vector3(4, 0.5, 14)},
]
## Obstacles down the range (from, to, material).
const BLOCKS := [
	[Vector3(-8, 0, -30), Vector3(-6, 1.2, -29), "concrete"],
	[Vector3(6, 0, -30), Vector3(8, 1.2, -29), "concrete"],
	[Vector3(-2, 0, -45), Vector3(2, 1.1, -44.6), "sandbag"],
]

## The range's spawns.
func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return spawn_point(_spawn_index)


func spawn_point(index: int) -> Vector3:
	return RANGE_SPAWNS[posmod(index, RANGE_SPAWNS.size())]


## What a joining client loads to play here (LevelSwitch).
func level_info() -> Dictionary:
	return {"level": "range"}


## No hostiles on the range.
func hostiles_to_spawn() -> Array:
	return []


func _build_structures() -> void:
	for b: Array in BLOCKS:
		voxel_world.add_box_m(b[0], b[1], VoxelWorld.Mat.SANDBAG if b[2] == "sandbag" else VoxelWorld.Mat.CONCRETE)


## Host: the range's save, its loot, the host's player, the parked vehicles (or the saved ones,
## wrecks included).
func _on_hosted() -> void:
	BodyVolume.warm(["", BodyVolume.FEMALE])
	GameState.load_zone()  # under GameState.zone_id: ZONE_ID from the menu (host_from_menu), a test's own
	voxel_world.load_edits(GameState.voxel_edits)
	for loot: Dictionary in RANGE_LOOT:
		if not GameState.is_looted(loot.uid):
			spawn_item(StringName(loot.id), loot.get("count", 1), loot.pos, loot.uid)
	for uid: String in GameState.dropped:
		var d: Dictionary = GameState.dropped[uid]
		spawn_item(StringName(d.id), int(d.count), Vector3(d.pos[0], d.pos[1], d.pos[2]), uid, GameState.from_json(d.get("state", {})))
	player_roles[1] = Roles.local_choice
	player_handed[1] = Handedness.local_left()
	_add_player(1)
	NavBuilder.build(self)
	if voxel_world.is_built():
		_restore_bodies()
	else:
		voxel_world.structures_built.connect(_restore_bodies, CONNECT_ONE_SHOT)
	var layer := get_node_or_null(^"Vehicles") as VehicleLayer
	if layer:
		layer.server_place_parked(PARKED)
	if spawn_ai:
		if voxel_world.is_built():
			_spawn_ai()
		else:
			voxel_world.structures_built.connect(_spawn_ai, CONNECT_ONE_SHOT)


## Main menu: hosts the range (a fresh session, players in their role's kit).
static func host_from_menu(menu: Node) -> void:
	BaseHub.cancel_session()
	CompoundLevel.player_role_kits = true
	CompoundLevel.clean_loot = true
	var main := menu.get_parent()
	if main == null:
		return
	GameState.zone_id = ZONE_ID
	LevelSwitch.load_level(main, {"level": "range"})
	if menu.has_method(&"host"):
		menu.call(&"host")
