class_name BaseLevel
extends CompoundLevel
## The company's base hub (wave 4): a walkable FOB inside a HESCO perimeter, where the
## company lives between deployments. It is a CompoundLevel (players, items, AI and bodies
## spawn and replicate the same way, and Soldier finds it with CompoundLevel.current), with
## no hostiles and no zone loot:
## - the armory: the company stash (BaseArmory) laid out on its floor as world items, to pick
##   up and drop back; anything left lying in the hub counts as stash;
## - the medbay, hiring board, shop terminal and ops desk (BaseTerminal): each opens its page
##   of the base screen (BaseUI);
## - the motor pool: an empty shelter for wave 5's vehicles;
## - the company's available people standing at the muster line in their own gear, so
##   players can hand them kit (interaction menu > Give item) before deploying.
## Campaign state is BaseHub's; this node only shows it and reads the stash back.

## Where players appear: inside the gate.
const BASE_SPAWNS: Array[Vector3] = [Vector3(-3, 0.1, 15), Vector3(-1, 0.1, 15), Vector3(1, 0.1, 15), Vector3(3, 0.1, 15)]
## The muster line: where the available roster stands (in hiring order), and how many.
const MUSTER_ORIGIN := Vector3(-5.6, 0.1, 1.0)
const MUSTER_STEP := Vector3(1.4, 0.0, 0.0)
const MUSTER_ROWS := Vector3(0.0, 0.0, 1.8)
const MUSTER_PER_ROW := 9
const MUSTER_MAX := 18
## Where bought items are delivered (the shop counter, by the armory door).
const DELIVERY := Vector3(-9.4, 0.4, -6.3)
## The terminals: kind, position (feet), facing (y degrees).
const TERMINALS := [
	[&"armory", Vector3(-14.0, 0, -6.6), 0.0],
	[&"shop", Vector3(-7.0, 0, -6.6), 0.0],
	[&"medbay", Vector3(13.6, 0, -6.6), 0.0],
	[&"hiring", Vector3(-6.0, 0, 6.0), 90.0],
	[&"ops", Vector3(-6.0, 0, 8.2), 90.0],
	[&"motor_pool", Vector3(5.0, 0, 8.0), -90.0],
]
const PERIMETER_HALF := 19.5
const GATE_HALF := 3.0

## Host: member id -> the Soldier standing for them at the muster line.
var _muster := {}


func _ready() -> void:
	super._ready()
	for t: Array in TERMINALS:
		var terminal := BaseTerminal.new(t[0])
		terminal.position = t[1]
		terminal.rotation_degrees.y = t[2]
		add_child(terminal)


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return BASE_SPAWNS[_spawn_index % BASE_SPAWNS.size()]


## Host: the hub comes up with the stash, the host's player and the muster line. No zone save
## (the hub's state is the campaign's), no hostiles.
func _on_hosted() -> void:
	GameState.looted.clear()
	GameState.dropped.clear()
	GameState.voxel_edits.clear()
	GameState.bodies.clear()
	server_spawn_stash(BaseHub.stash())
	player_roles[1] = Roles.local_choice
	_add_player(1)
	NavBuilder.build(self)
	if voxel_world.is_built():
		_on_built()
	else:
		voxel_world.structures_built.connect(_on_built, CONNECT_ONE_SHOT)


func _on_built() -> void:
	server_show_roster()
	BaseHub.server_level_ready(self)


# --- The stash ----------------------------------------------------------------------------

## Host: lays the stash out as world items (armory floor first).
func server_spawn_stash(stash: Array) -> void:
	for i in stash.size():
		var entry: Dictionary = stash[i]
		spawn_item(StringName(entry.id), int(entry.count), BaseArmory.slot_position(i), "stash_%d_%d" % [i, Time.get_ticks_usec()],
			GameState.from_json(entry.get("state", {})))


## Host: everything lying in the hub now, as stash entries.
func server_collect_stash() -> Array:
	return BaseArmory.from_world_items(items.get_children())


## Host: puts a new item into the stash where it can be seen (a delivery from the shop).
func server_deliver(id: StringName, count: int, state := {}) -> void:
	var jitter := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.3, 0.3))
	spawn_item(id, count, DELIVERY + jitter, "stash_d_%d" % Time.get_ticks_usec(), state)


# --- The muster line ----------------------------------------------------------------------

## Host: the company's available people stand at the muster line in their own gear, holding
## (in hiring order, up to MUSTER_MAX); anyone no longer available leaves it. Their gear is
## read back with server_read_muster_gear.
func server_show_roster() -> void:
	var wanted := BaseHub.muster_ids()
	for mid: String in _muster.keys():
		if mid not in wanted or not is_instance_valid(_muster[mid]):
			var s: Soldier = _muster[mid]
			if is_instance_valid(s):
				BaseHub.server_store_member_gear(mid, s.inventory.net_state)
				s.queue_free()
			_muster.erase(mid)
	for i in mini(wanted.size(), MUSTER_MAX):
		var mid: String = wanted[i]
		if _muster.has(mid):
			continue
		var member := BaseHub.member(mid)
		var pos := MUSTER_ORIGIN + MUSTER_STEP * (i % MUSTER_PER_ROW) + MUSTER_ROWS * (i / MUSTER_PER_ROW)
		var stats := Roster.ai_stats(member)
		var s := spawn_soldier({"name": String(member.callsign), "faction": "friendly", "variant": "multicam", "pos": pos,
			"loadout": [], "combat": stats.combat, "discipline": stats.discipline, "guard": false, "mode": "safe"})
		s.role = StringName(member.role)
		s.set_meta(&"roster_id", mid)
		s.inventory.net_state = GameState.from_json(member.get("gear", {}))
		s.rotation.y = PI  # facing the yard
		var brain := SquadAI.of(s)
		if brain:
			brain.order = Squad.Order.HOLD  # where they stand (SquadAI holds at its spawn point)
		_muster[mid] = s


## Host: the gear each person at the muster line has on them now (member id -> net_state).
func server_read_muster_gear() -> Dictionary:
	var out := {}
	for mid: String in _muster:
		var s: Soldier = _muster[mid]
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			out[mid] = s.inventory.net_state.duplicate(true)
	return out


func muster_soldier(mid: String) -> Soldier:
	var s: Soldier = _muster.get(mid)
	return s if is_instance_valid(s) else null


# --- The FOB --------------------------------------------------------------------------------

## The FOB in voxels (all inside VoxelWorld.BOUNDS): a HESCO perimeter with a gate to the
## south, the armory (cinder block, a roof, a doorway to the yard) in the north-west, the
## medbay (plaster) in the north-east, the motor pool's open shelter in the south-east and an
## ops hut by the yard. Doorways stay clear of NavBuilder's chunk edges (x and z = ±6, ±18).
func _build_structures() -> void:
	var h := PERIMETER_HALF
	var hesco := VoxelWorld.Mat.HESCO
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(h, 2.2, -h + 1.0), hesco)
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(-h + 1.0, 2.2, h), hesco)
	voxel_world.add_box_m(Vector3(h - 1.0, 0, -h), Vector3(h, 2.2, h), hesco)
	voxel_world.add_box_m(Vector3(-h, 0, h - 1.0), Vector3(-GATE_HALF, 2.2, h), hesco)
	voxel_world.add_box_m(Vector3(GATE_HALF, 0, h - 1.0), Vector3(h, 2.2, h), hesco)
	# Armory: 10 x 8.4 m, doorway (1.6 m) in the south wall at x -12.4..-10.8.
	_hut(Vector2(-16.2, -16.2), Vector2(-5.8, -7.4), -12.4, -10.8, VoxelWorld.Mat.CINDER_BLOCK)
	# Medbay: 10 x 8.4 m, doorway at x 10.2..11.8.
	_hut(Vector2(5.8, -16.2), Vector2(16.2, -7.4), 10.2, 11.8, VoxelWorld.Mat.PLASTER)
	# Ops hut by the yard: 4 x 5 m, open towards the yard (east).
	var ply := VoxelWorld.Mat.WOOD
	voxel_world.add_box_m(Vector3(-11.0, 0, 4.0), Vector3(-7.0, 2.6, 4.2), ply)
	voxel_world.add_box_m(Vector3(-11.0, 0, 9.8), Vector3(-7.0, 2.6, 10.0), ply)
	voxel_world.add_box_m(Vector3(-11.0, 0, 4.0), Vector3(-10.8, 2.6, 10.0), ply)
	voxel_world.add_box_m(Vector3(-11.0, 2.6, 4.0), Vector3(-7.0, 2.7, 10.0), VoxelWorld.Mat.CORRUGATED_IRON)
	# Motor pool: a corrugated-iron roof on four posts, open on every side (wave 5 parks here).
	var iron := VoxelWorld.Mat.CORRUGATED_IRON
	for corner: Vector2 in [Vector2(7.0, 3.0), Vector2(16.6, 3.0), Vector2(7.0, 13.6), Vector2(16.6, 13.6)]:
		voxel_world.add_box_m(Vector3(corner.x, 0, corner.y), Vector3(corner.x + 0.3, 3.4, corner.y + 0.3), VoxelWorld.Mat.STEEL)
	voxel_world.add_box_m(Vector3(7.0, 3.4, 3.0), Vector3(16.9, 3.5, 13.9), iron)
	# Sandbagged gate guard post.
	voxel_world.add_box_m(Vector3(4.0, 0, 15.6), Vector3(6.4, 1.2, 16.0), VoxelWorld.Mat.SANDBAG)


## A walled, roofed hut from `a` to `b` (x, z) with a doorway in its south wall between x
## `door_from` and `door_to`.
func _hut(a: Vector2, b: Vector2, door_from: float, door_to: float, mat: VoxelWorld.Mat) -> void:
	var t := 0.3
	var top := 3.0
	voxel_world.add_box_m(Vector3(a.x, 0, a.y), Vector3(b.x, top, a.y + t), mat)
	voxel_world.add_box_m(Vector3(a.x, 0, a.y), Vector3(a.x + t, top, b.y), mat)
	voxel_world.add_box_m(Vector3(b.x - t, 0, a.y), Vector3(b.x, top, b.y), mat)
	voxel_world.add_box_m(Vector3(a.x, 0, b.y - t), Vector3(door_from, top, b.y), mat)
	voxel_world.add_box_m(Vector3(door_to, 0, b.y - t), Vector3(b.x, top, b.y), mat)
	voxel_world.add_box_m(Vector3(door_from, 2.2, b.y - t), Vector3(door_to, top, b.y), mat)
	voxel_world.add_box_m(Vector3(a.x, top, a.y), Vector3(b.x, top + 0.2, b.y), VoxelWorld.Mat.CONCRETE)
