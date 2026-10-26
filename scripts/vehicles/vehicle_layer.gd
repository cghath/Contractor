class_name VehicleLayer
extends Node
## A level's vehicles (wave 5): one node, "Vehicles", in every level on every peer
## (CompoundLevel._ready adds it), so vehicles spawn and their RPCs land at the same paths
## everywhere. The host spawns vehicles through its MultiplayerSpawner (late joiners get them
## with their state), saves them with the zone (GameState.vehicles: wrecks stay where they
## burned) and puts them back when the zone is hosted again: server_restore(), which the level
## calls from its own hosting path (CompoundLevel._restore_bodies, after the zone save is loaded
## and its bodies are back), whether it was hosted from the menu or switched to by BaseHub.
## (Not from Net.hosted: a campaign level switch never emits it.)
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
## Captain, 2026-10-15 (v0.4.3 co-op): the AI squad boarded an M-ATV as passengers and left
## the M2 empty. Who of the squadmates getting in takes a free main gun, best first; a medic
## never does (unless he's the one told to "Take the gun").
const GUNNER_ROLES: Array[StringName] = [Roles.AUTORIFLEMAN, Roles.GRENADIER, Roles.RIFLEMAN, Roles.MARKSMAN, Roles.TEAM_LEADER]

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
	var drivers := SquadDrivers.new()
	drivers.name = SquadDrivers.NODE_NAME
	add_child(drivers)  # the squad's AI at the wheel (wave 6, queued 2026-10-19)


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
	var v := spawner.spawn(data) as Vehicle
	if v and not record.has("cargo") and StringName(String(data.faction)) == &"hostile":  # (ours rearm at the motor pool)
		v.server_rearm()  # a new armed vehicle comes with its gun's load (Captain, 2026-10-15: technicals spawned out of ammo)
	return v


func _make(data: Dictionary) -> Node:
	var model := String(data.model)
	var scheme := String(data.get("scheme", ""))
	var faction := StringName(String(data.get("faction", "player")))
	var v: Vehicle = Mount.make(model, scheme, faction, String(data.id)) if Mount.is_mount_model(model) \
		else Helicopter.make(model, scheme, faction, String(data.id)) if Helicopter.flies(model) \
		else Vehicle.create(model, scheme, faction, String(data.id))  # wave 5b: helicopters fly (V3)
	v.from_save(data)
	return v


## Host (zones, the range): parks vehicles. Each entry: {"id" (stable within the zone),
## "model", "scheme"?, "faction"?, "pos" (Vector3 or [x, y, z]), "yaw" (degrees)?, "cargo"
## ([[item id, count], ...])?, "fuel"?}. An id the zone save already holds comes back as the
## save has it (where it was left, its damage and cargo, a wreck), not freshly parked. Call it
## after GameState.load_zone. Returns the vehicles parked fresh now.
func server_place_parked(entries: Array) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	if not multiplayer.is_server():
		return out
	var saved := {}
	for r: Dictionary in GameState.vehicles:
		saved[String(r.get("id", ""))] = r
	for e: Dictionary in entries:
		var id := String(e.get("id", ""))
		if id != "" and find(id) != null:
			continue
		if id != "" and saved.has(id):
			_restore_record(saved[id])
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
## Wave 5b: one with meta "no_save" (a support AAV, an enemy QRF technical, a motor pool vehicle
## out with the squad) goes with the op; only its wreck stays.
func records() -> Array:
	return vehicles().filter(func(v: Vehicle) -> bool: return v.wrecked or not v.has_meta(&"no_save")) \
		.map(func(v: Vehicle) -> Dictionary: return v.to_save())


## Host: the vehicles in the zone save (GameState.vehicles, loaded by the level), back where
## they were, as they were; and the bodies that rode in them back in their seats (call it once
## the zone's bodies are restored). A vehicle already here is left alone, so calling it again
## (or after server_place_parked) adds nothing twice.
func server_restore() -> void:
	if not multiplayer.is_server():
		return
	for record: Dictionary in GameState.vehicles:
		_restore_record(record)
	for v in vehicles():
		v.server_seat_saved_bodies()
		if v.logistics:
			v.logistics.server_rehook_saved()  # A6 (F-272): a tow saved with the zone


func _restore_record(record: Dictionary) -> Vehicle:
	var id := String(record.get("id", ""))
	if id == "" or not VehicleSpecs.has_model(String(record.get("model", ""))):
		return null
	var have := find(id)
	if have:
		return have
	return server_spawn(String(record.model), Transform3D.IDENTITY, String(record.get("scheme", "")), StringName(String(record.get("faction", "player"))), id, record)


# --- AI squadmates in and out (command menu: Mount) ------------------------------------------

## Host: the named squadmates (all selected if empty) get into the vehicle nearest `point`:
## those close by at once, the rest walk to its nearest door first; one of them takes its main
## gun while nobody mans it (pick_gunner). `take_gun` (the command menu's "Take the gun"): only
## the one picked goes, to the gun (moving over to it if already aboard). Returns "" or why not.
func server_order_mount(from: Soldier, point: Vector3, names: PackedStringArray, take_gun := false) -> String:
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
	var gun_seat := int(best.gun_info().get("seat", -1))
	if gun_seat >= 0 and (best.occupant(gun_seat) != null or _gun_claimed(best)):
		gun_seat = -1  # someone (a player, say) mans it, or is on the way to
	var team: Array[Soldier] = []
	for s: Soldier in squad.pick(names):
		if s.is_ai() and s.vitals.is_up() and (take_gun or Vehicle.ride_of(s) != best):
			team.append(s)
	var gunner := pick_gunner(team, take_gun) if gun_seat >= 0 else null
	if take_gun:
		if best.gun_info().is_empty():
			return "That vehicle has no gun"
		if gunner == null:
			return "Someone's already on the gun" if gun_seat < 0 else "Nobody to send"
		team.clear()
		team.append(gunner)
	var sent := 0
	for s in team:
		var seat := gun_seat if s == gunner else -1
		if Vehicle.ride_of(s) == best:
			if best.server_switch(s, seat):
				sent += 1
			continue
		var door := _nearest_door(best, s.global_position)
		if s.global_position.distance_to(door) <= BOARD_REACH_M:
			if (seat >= 0 and best.server_enter(s, seat)) or best.server_enter(s):
				sent += 1
			continue
		squad.give_order(from, Squad.Order.MOVE, door, PackedStringArray([String(s.name)]))
		_boarding[s.get_instance_id()] = {"soldier": s, "vehicle": best, "until": Soldier._now() + BOARD_TIMEOUT_S, "seat": seat}
		sent += 1
	return "" if sent > 0 else "Nobody to send"


## Host: the vehicle (not a wreck) nearest `point` within `within` (MOUNT_PICK_M), or null.
func vehicle_near(point: Vector3, within := MOUNT_PICK_M) -> Vehicle:
	var best: Vehicle = null
	var best_d := within
	for v in vehicles():
		var d := v.global_position.distance_to(point)
		if not v.wrecked and d < best_d:
			best = v
			best_d = d
	return best


## Host: squadmate `s` gets into seat `seat` (-1 any) of `v`: at once when he's aboard (he moves
## over) or by a door, else he walks to the nearest door first (ordered by `from`) and gets in
## there. Returns whether he's in or on his way.
func server_board(from: Soldier, s: Soldier, v: Vehicle, seat := -1) -> bool:
	if Vehicle.ride_of(s) == v:
		return v.server_switch(s, seat) if seat >= 0 else true
	var door := _nearest_door(v, s.global_position)
	if s.global_position.distance_to(door) <= BOARD_REACH_M:
		return (seat >= 0 and v.server_enter(s, seat)) or (seat < 0 and v.server_enter(s))
	# The walk order goes through his own Squad: an element's man (the high command's
	# SquadDrivers.server_squad_mount) isn't one of `from`'s squad, which picks only its own (A2-10).
	var brain := SquadAI.of(s)
	var squad: Squad = brain.squad if brain and is_instance_valid(brain.squad) else null
	if squad == null:
		var lvl := get_parent() as CompoundLevel
		squad = lvl.squad_for(from.faction) if lvl else null
	if squad == null:
		return false
	squad.give_order(from, Squad.Order.MOVE, door, PackedStringArray([String(s.name)]))
	_boarding[s.get_instance_id()] = {"soldier": s, "vehicle": v, "until": Soldier._now() + BOARD_TIMEOUT_S, "seat": seat}
	return true


## Who of `team` (AI squadmates) takes a vehicle's gun: by GUNNER_ROLES, never a medic, or null.
## `told` (the "Take the gun" order): the medic too, when he's the only one told.
static func pick_gunner(team: Array[Soldier], told := false) -> Soldier:
	var best: Soldier = null
	var best_rank := INF
	for s in team:
		var rank := GUNNER_ROLES.find(s.role)
		if s.role == Roles.MEDIC:
			if not told:
				continue
			rank = GUNNER_ROLES.size() + 1
		elif rank < 0:
			rank = GUNNER_ROLES.size()
		if rank < best_rank:
			best_rank = rank
			best = s
	return best


## Whether a squadmate is on the way to `v`'s gun seat.
func _gun_claimed(v: Vehicle) -> bool:
	var gun_seat := int(v.gun_info().get("seat", -1))
	for b: Dictionary in _boarding.values():
		if b.vehicle == v and int(b.get("seat", -1)) >= 0 and int(b.get("seat", -1)) == gun_seat:
			return true
	return false


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
			v.server_run_out(s)  # out of a walk-in bay at a run (Vehicle.server_run_out)
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
			var seat := int(b.get("seat", -1))
			if not (seat >= 0 and v.server_enter(s, seat)):
				v.server_enter(s)


## Host (tests): squadmates still on their way to a vehicle.
func boarding_count() -> int:
	return _boarding.size()


## Host: the vehicle squadmate `s` is on his way to get into, or null.
func boarding_of(s: Soldier) -> Vehicle:
	var b: Dictionary = _boarding.get(s.get_instance_id(), {})
	return b.vehicle as Vehicle if not b.is_empty() and is_instance_valid(b.vehicle) else null


## Host: how many squadmates are on their way to `v`.
func boarding_to(v: Vehicle) -> int:
	var n := 0
	for b: Dictionary in _boarding.values():
		if b.vehicle == v:
			n += 1
	return n


## Host: squadmates still on their way to `v` stop going (it's leaving without them).
func server_cancel_boarding(v: Vehicle) -> void:
	for id: int in _boarding.keys():
		if (_boarding[id] as Dictionary).vehicle == v:
			_boarding.erase(id)
