class_name VehicleLayer
extends Node
## A level's vehicles (wave 5): one node, "Vehicles", in every level on every peer
## (CompoundLevel._ready adds it), so vehicles spawn and their RPCs land at the same paths
## everywhere. The host spawns vehicles through its MultiplayerSpawner (late joiners get them
## with their state), saves them with the zone (GameState.vehicles: wrecks stay where they
## burned) and puts them back when the zone is hosted again.
##
## Hooks for other work:
## - server_spawn(): any vehicle anywhere (V3's helicopters, V4's AAVs and motor pool).
## - server_place_parked(): the one call a zone (or the range) makes to park vehicles; one
##   whose id the save already holds comes back as saved instead (a wreck stays a wreck).
## - server_order_mount() / server_order_dismount(): the command menu's Mount > Get in / Get out
##   for AI squadmates (the full vehicle command set is V4's).

## Proposed: AI ordered to get in walk to the nearest door and get in within this reach (m),
## giving up after BOARD_TIMEOUT_S; checked every BOARD_CHECK_S.
const BOARD_REACH_M := 3.5
const BOARD_TIMEOUT_S := 60.0
const BOARD_CHECK_S := 0.3
## "Get in" takes the vehicle nearest the point under the crosshair, this close.
const MOUNT_PICK_M := 10.0

var spawner: MultiplayerSpawner
var _boarding := {}  # host: soldier instance id -> {"soldier", "vehicle", "until"}
var _board_left := 0.0
var _serial := 0


func _init() -> void:
	name = "Vehicles"


func _ready() -> void:
	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _make
	add_child(spawner)
	Net.hosted.connect(_on_hosted)


## The vehicles node of the level `from` is in (or null).
static func of(from: Node) -> VehicleLayer:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"Vehicles") as VehicleLayer if lvl else null


## Every vehicle in this level.
func vehicles() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for c in get_children():
		if c is Vehicle and not c.is_queued_for_deletion():
			out.append(c as Vehicle)
	return out


func find(id: String) -> Vehicle:
	for v in vehicles():
		if v.vehicle_id == id:
			return v
	return null


## Host: a new vehicle of `model` at `xform` (its footprint centre on the ground), or as
## `record` says (Vehicle.to_save: damage, cargo, wreck). Returns it, or null for a model with
## no numbers. `id` "" gets a fresh one.
func server_spawn(p_model: String, xform: Transform3D, scheme := "", faction := &"player", id := "", record := {}) -> Vehicle:
	if not multiplayer.is_server() or not VehicleSpecs.has_model(p_model):
		return null
	if id == "":
		_serial += 1
		id = "%s_v%d_%d" % [GameState.zone_id, Time.get_ticks_msec(), _serial]
	var data := record.duplicate(true)
	data["id"] = id
	data["model"] = p_model
	data["scheme"] = scheme if scheme != "" else String(data.get("scheme", ""))
	data["faction"] = String(faction) if not record.has("faction") else String(record.faction)
	if not record.has("pos"):
		var q := xform.basis.get_rotation_quaternion()
		data["pos"] = [xform.origin.x, xform.origin.y, xform.origin.z]
		data["rot"] = [q.x, q.y, q.z, q.w]
	return spawner.spawn(data) as Vehicle


func _make(data: Dictionary) -> Node:
	var v := Vehicle.create(String(data.model), String(data.get("scheme", "")), StringName(String(data.get("faction", "player"))), String(data.id))
	v.from_save(data)
	return v


## Host (zones, the range): parks vehicles. Each entry: {"id" (stable within the zone),
## "model", "scheme"?, "faction"?, "pos" (Vector3 or [x, y, z]), "yaw" (degrees)?, "cargo"
## ([[item id, count], ...])?, "fuel"?}. An id the zone save already holds is left to the save
## (_restore puts it back as it was). Returns the vehicles placed now.
func server_place_parked(entries: Array) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	if not multiplayer.is_server():
		return out
	var saved := {}
	for r: Dictionary in GameState.vehicles:
		saved[String(r.get("id", ""))] = true
	for e: Dictionary in entries:
		var id := String(e.get("id", ""))
		if id != "" and (saved.has(id) or find(id) != null):
			continue
		var p: Variant = e.get("pos", Vector3.ZERO)
		var pos: Vector3 = p if p is Vector3 else VehicleSpecs.vec(p)
		var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0)))), pos)
		var v := server_spawn(String(e.model), xform, String(e.get("scheme", "")), StringName(String(e.get("faction", "player"))), id)
		if v == null:
			continue
		for c: Array in e.get("cargo", []):
			v.cargo_hold.take(StringName(String(c[0])), int(c[1]) if c.size() > 1 else 1)
		if e.has("fuel"):
			v.server_set_fuel(float(e.fuel))
		out.append(v)
	return out


## Host: every vehicle as the zone save keeps it (GameState.save_zone calls this through the group).
func records() -> Array:
	return vehicles().map(func(v: Vehicle) -> Dictionary: return v.to_save())


func _on_hosted() -> void:
	_restore.call_deferred()  # after the level has loaded the zone save (its own _on_hosted)


## Host: the vehicles in the zone save, back where they were, as they were.
func _restore() -> void:
	if not multiplayer.is_server():
		return
	for record: Dictionary in GameState.vehicles:
		var id := String(record.get("id", ""))
		if id == "" or find(id) != null or not VehicleSpecs.has_model(String(record.get("model", ""))):
			continue
		server_spawn(String(record.model), Transform3D.IDENTITY, String(record.get("scheme", "")), StringName(String(record.get("faction", "player"))), id, record)


# --- AI squadmates in and out (command menu: Mount) ------------------------------------------

## Host: the named squadmates (all selected if empty) get into the vehicle nearest `point`:
## those close by at once, the rest walk to its nearest door first. Returns "" or why not.
func server_order_mount(from: Soldier, point: Vector3, names: PackedStringArray) -> String:
	var lvl := get_parent() as CompoundLevel
	var squad := lvl.squad_for(from.faction) if lvl else null
	if squad == null:
		return "No squad"
	var best: Vehicle = null
	var best_d := MOUNT_PICK_M
	for v in vehicles():
		var d := v.global_position.distance_to(point)
		if not v.wrecked and d < best_d:
			best = v
			best_d = d
	if best == null:
		return "No vehicle there"
	var sent := 0
	for s: Soldier in squad.pick(names):
		if not s.is_ai() or not s.vitals.is_up() or Vehicle.ride_of(s) == best:
			continue
		var door := _nearest_door(best, s.global_position)
		if s.global_position.distance_to(door) <= BOARD_REACH_M:
			if best.server_enter(s):
				sent += 1
			continue
		squad.give_order(from, Squad.Order.MOVE, door, PackedStringArray([String(s.name)]))
		_boarding[s.get_instance_id()] = {"soldier": s, "vehicle": best, "until": Soldier._now() + BOARD_TIMEOUT_S}
		sent += 1
	return "" if sent > 0 else "Nobody to send"


## Host: the named squadmates (all if empty) get out of whatever they ride, and fall in.
func server_order_dismount(from: Soldier, names: PackedStringArray) -> String:
	var lvl := get_parent() as CompoundLevel
	var squad := lvl.squad_for(from.faction) if lvl else null
	if squad == null:
		return "No squad"
	var out := 0
	var picked := PackedStringArray()
	for s: Soldier in squad.pick(names):
		_boarding.erase(s.get_instance_id())
		var v := Vehicle.ride_of(s)
		if v and s.is_ai():
			v.server_exit(s)
			picked.append(String(s.name))
			out += 1
	if out > 0:
		squad.give_order(from, Squad.Order.FOLLOW, from.global_position, picked)
	return "" if out > 0 else "Nobody is in a vehicle"


func _nearest_door(v: Vehicle, from: Vector3) -> Vector3:
	var best := v.global_position
	var best_d := INF
	for p in v.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == VehicleActionPoint.DOOR:
			var at := (p as Node3D).global_position
			var d := at.distance_to(from)
			if d < best_d:
				best_d = d
				best = at
	return Vector3(best.x, v.global_position.y, best.z)


func _physics_process(delta: float) -> void:
	if _boarding.is_empty() or not multiplayer.is_server():
		return
	_board_left -= delta
	if _board_left > 0.0:
		return
	_board_left = BOARD_CHECK_S
	for id: int in _boarding.keys():
		var b: Dictionary = _boarding[id]
		var s: Soldier = b.soldier if is_instance_valid(b.soldier) else null
		var v: Vehicle = b.vehicle if is_instance_valid(b.vehicle) else null
		if s == null or v == null or v.wrecked or not s.vitals.is_up() or Soldier._now() > float(b.until):
			_boarding.erase(id)
			continue
		if s.global_position.distance_to(_nearest_door(v, s.global_position)) <= BOARD_REACH_M:
			_boarding.erase(id)
			v.server_enter(s)


## Host (tests): squadmates still on their way to a vehicle.
func boarding_count() -> int:
	return _boarding.size()
