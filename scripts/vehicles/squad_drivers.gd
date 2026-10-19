class_name SquadDrivers
extends Node
## The squad's AI at the wheel (docs/build_plan.md wave 6, Captain 2026-10-19: "the squad's AI
## drives the squad's vehicles"). Squadmates take the wheel of the squad's ground vehicles on
## command and drive them with the vehicle's own AI (VehicleAI, through Vehicle.server_drive_to);
## a player at the wheel always has it. The command menu's Mount entries (Soldier, host):
##   take_wheel        a selected squadmate (else the best of the squad for it: never a medic
##                     while anyone else can) gets into the driver's seat of the vehicle there;
##   drive_to          the AI-driven vehicle the commander rides (on foot: every one the squad
##                     drives) goes to the point under the crosshair and stops;
##   convoy            they follow the commander in a column, CONVOY_GAP_M apart: the first
##                     behind his vehicle (or him on foot), each next behind the one before;
##   pickup            they come to the commander, stop PICKUP_STOP_M off, and the squadmates on
##                     foot get in (VehicleLayer.server_order_mount);
##   drive_stop        they stop where they are and hold;
##   contact_dismount  toggles (on to start) the contact drill: a vehicle under orders whose
##                     squad is engaged (Squad.is_engaged) or that was hit (Vehicle.damaged) in
##                     the last CONTACT_S stops, and its AI passengers (not the driver or the
##                     gunner) get out and fight.
## The host's high command gives an allied or company element the same (AlliedTroops "mount",
## "drive", "dismount": server_squad_mount / server_squad_drive / server_squad_dismount, any Squad).
## One node, "SquadDrivers", under each level's VehicleLayer. Host only. Proposed numbers.

const NODE_NAME := "SquadDrivers"
const TICK_S := 1.0
const CONVOY_GAP_M := 22.0
## A column's driver stops within this of his place, and drives again past it.
const CONVOY_HOLD_M := 6.0
const PICKUP_STOP_M := 9.0
const CONTACT_S := 6.0
## Who takes the wheel when nobody's named: earliest first (a gunner's role last).
const DRIVER_ROLES: Array[StringName] = [Roles.RIFLEMAN, Roles.MARKSMAN, Roles.GRENADIER, Roles.TEAM_LEADER, Roles.AUTORIFLEMAN]
## An element told to mount (the high command, from the map) takes the vehicle within this of
## the point given.
const ELEMENT_PICK_M := 40.0

enum Order { NONE, DRIVE, CONVOY, PICKUP, HOLD }

## Host: vehicle instance id -> {"vehicle", "order" (Order), "point", "by" (the commander),
## "ahead" (a column's: the Node3D it follows), "boarded" (a pickup's squad sent to board)}.
var orders := {}
## Host: whether the contact drill is on (contact_dismount toggles it).
var dismount_on_contact := true
var _tick := 0.0
var _hit_at := {}  # vehicle instance id -> Soldier._now() it was last hit


static func of(from: Node) -> SquadDrivers:
	var layer := VehicleLayer.of(from)
	return layer.get_node_or_null(NODE_NAME) as SquadDrivers if layer else null


func layer() -> VehicleLayer:
	return get_parent() as VehicleLayer


## Host: one of the menu's commands (above) from `from` at `point` for `names`. Returns "" or
## what went wrong, for the commander's message line.
func server_command(from: Soldier, cmd: String, point: Vector3, names: PackedStringArray) -> String:
	if not multiplayer.is_server() or from == null:
		return ""
	match cmd:
		"take_wheel":
			return server_take_wheel(from, point, names)
		"drive_to":
			return server_drive_to(from, point)
		"convoy":
			return server_convoy(from)
		"pickup":
			return server_pickup(from)
		"drive_stop":
			return server_stop(from)
		"contact_dismount":
			dismount_on_contact = not dismount_on_contact
			return "Dismount on contact: %s" % ("on" if dismount_on_contact else "off")
	return "Order not understood"


# --- Orders ------------------------------------------------------------------------------------

## A squadmate gets into the driver's seat of the vehicle near `point`.
func server_take_wheel(from: Soldier, point: Vector3, names: PackedStringArray) -> String:
	var squad := _squad(from)
	var v := layer().vehicle_near(point)
	if squad == null:
		return "No squad"
	if v == null or v.kind == Vehicle.HELICOPTER:
		return "No vehicle there to drive"
	var seat := v.driver_seat()
	if seat < 0:
		return "That has no driver's seat"
	var d := v.driver()
	if d and not d.is_ai():
		return "A player is driving it"
	if d and d.is_ai() and d in squad.members():
		return "%s already has the wheel" % String(d.name)
	var team: Array[Soldier] = []
	for s: Soldier in squad.pick(names):
		if s.is_ai() and s.vitals.is_up() and s != v.gunner():
			team.append(s)
	var who := pick_driver(team, not names.is_empty())
	if who == null:
		return "Nobody to send"
	if not layer().server_board(from, who, v, seat):
		return "%s can't get to the wheel" % String(who.name)
	return ""


## Who of `team` drives: the first DRIVER_ROLES has, never a medic unless `told` and he's the
## only one; null for nobody.
static func pick_driver(team: Array[Soldier], told := false) -> Soldier:
	var best: Soldier = null
	var best_rank := INF
	for s in team:
		var rank := DRIVER_ROLES.find(s.role)
		if s.role == Roles.MEDIC:
			if not told:
				continue
			rank = DRIVER_ROLES.size() + 1
		elif rank < 0:
			rank = DRIVER_ROLES.size()
		if rank < best_rank:
			best_rank = rank
			best = s
	return best


## The AI-driven vehicle the commander rides goes to `point` (on foot: every one the squad drives).
func server_drive_to(from: Soldier, point: Vector3) -> String:
	var vs := _targets(from)
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	var lvl := CompoundLevel.current(self)
	if lvl and lvl.has_method(&"ground_point"):
		point = lvl.call(&"ground_point", point)  # (a map order comes without a height)
	for v in vs:
		_give(v, Order.DRIVE, from, point)
		go(v, point)
	return ""


## Host: `v` drives to `point`: by road when the zone's roads make a better way (RoadRoute; a long
## drive with a road near both ends), else straight or by the navmesh (VehicleAI.drive_to).
## Returns whether it took the roads.
func go(v: Vehicle, point: Vector3) -> bool:
	var lvl := CompoundLevel.current(self)
	var def: Variant = lvl.get(&"def") if lvl else null
	var way := RoadRoute.route(def, Vector2(v.global_position.x, v.global_position.z), Vector2(point.x, point.z)) if def is Dictionary else PackedVector2Array()
	if way.is_empty() or not lvl.has_method(&"ground_point"):
		v.server_drive_to(point)
		return false
	var path := PackedVector3Array()
	for p: Vector2 in way:
		path.append(lvl.call(&"ground_point", Vector3(p.x, 0.0, p.y)))
	v.server_follow_path(path)
	return true


## The squad's AI-driven vehicles follow the commander in a column.
func server_convoy(from: Soldier) -> String:
	var lead: Node3D = Vehicle.ride_of(from)
	if lead == null:
		lead = from
	var vs := driven(from).filter(func(v: Vehicle) -> bool: return v != lead)
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	vs.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.global_position.distance_to(lead.global_position) < b.global_position.distance_to(lead.global_position))
	var ahead: Node3D = lead
	for v: Vehicle in vs:
		_give(v, Order.CONVOY, from, Vector3.ZERO)
		orders[v.get_instance_id()]["ahead"] = ahead
		ahead = v
	_tick = 0.0
	return ""


## The squad's AI-driven vehicles come to the commander and pick the squad up.
func server_pickup(from: Soldier) -> String:
	var vs := driven(from).filter(func(v: Vehicle) -> bool: return v != Vehicle.ride_of(from))
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	for v: Vehicle in vs:
		_give(v, Order.PICKUP, from, from.global_position)
		go(v, _stop_short(v, from.global_position, PICKUP_STOP_M))
	return ""


## The squad's AI-driven vehicles stop and hold.
func server_stop(from: Soldier) -> String:
	var vs := driven(from)
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	for v in vs:
		_give(v, Order.HOLD, from, v.global_position)
		v.server_stop()
	return ""


## The order vehicle `v` drives under (Order.NONE for none).
func order_of(v: Vehicle) -> int:
	return int((orders.get(v.get_instance_id(), {}) as Dictionary).get("order", Order.NONE))


# --- An element's vehicles (the host's high command, AlliedTroops) ------------------------------

## Host: `squad` (an element) takes the vehicle near `point`: one of it at the wheel, the rest in
## the other seats (VehicleLayer.server_board, walking over to it). Returns "" or why not.
func server_squad_mount(by: Soldier, squad: Squad, point: Vector3) -> String:
	var v := layer().vehicle_near(point, ELEMENT_PICK_M)
	if v == null or v.kind == Vehicle.HELICOPTER:
		return "no vehicle there"
	var d := v.driver()
	if d and not d.is_ai():
		return "a player is driving it"
	var team: Array[Soldier] = squad.members().filter(func(s: Soldier) -> bool: return s.is_ai() and s.vitals.is_up())
	if team.is_empty():
		return "nobody up"
	var sent := 0
	if d == null:
		var wheel := pick_driver(team)
		if wheel and layer().server_board(by, wheel, v, v.driver_seat()):
			team.erase(wheel)
			sent += 1
	for s: Soldier in team:  # (more than it seats: the rest find no seat at the door, and stay)
		if layer().server_board(by, s, v, -1):
			sent += 1
	return "" if sent > 0 else "nobody could get in"


## Host: the vehicles `squad` (an element) drives go to `point`.
func server_squad_drive(by: Soldier, squad: Squad, point: Vector3) -> String:
	var vs := driven_by(squad)
	if vs.is_empty():
		return "nobody of it at a wheel"
	for v in vs:
		_give(v, Order.DRIVE, by, point, squad)
		go(v, point)
	return ""


## Host: `squad` (an element) gets out of whatever it rides and holds there.
func server_squad_dismount(by: Soldier, squad: Squad) -> String:
	var out := 0
	var at := Vector3.ZERO
	for s: Soldier in squad.members():
		var v := Vehicle.ride_of(s)
		if v and s.is_ai():
			orders.erase(v.get_instance_id())
			v.server_stop()
			v.server_run_out(s)
			at = v.global_position
			out += 1
	if out == 0:
		return "nobody of it in a vehicle"
	squad.give_order(by, Squad.Order.HOLD, at)
	return ""


# --- Who drives what ---------------------------------------------------------------------------

## The squad's ground vehicles with one of its AI at the wheel.
func driven(from: Soldier) -> Array[Vehicle]:
	return driven_by(_squad(from))


## The ground vehicles with one of `squad`'s AI at the wheel.
func driven_by(squad: Squad) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	if squad == null:
		return out
	var members := squad.members()
	for v: Vehicle in layer().vehicles():
		var d := v.driver()
		if not v.wrecked and v.kind != Vehicle.HELICOPTER and d and d.is_ai() and d.vitals.is_up() and d in members:
			out.append(v)
	return out


## What a drive order from `from` moves: the vehicle he rides if one of ours drives it, else all.
func _targets(from: Soldier) -> Array[Vehicle]:
	var all := driven(from)
	var mine := Vehicle.ride_of(from)
	if mine and mine in all:
		var only: Array[Vehicle] = [mine]
		return only
	return all


func _squad(from: Soldier) -> Squad:
	var lvl := CompoundLevel.current(self)
	return lvl.squad_for(from.faction) if lvl and from else null


func _give(v: Vehicle, order: int, by: Soldier, point: Vector3, squad: Squad = null) -> void:
	orders[v.get_instance_id()] = {"vehicle": v, "order": order, "by": by, "point": point, "squad": squad if squad else _squad(by)}
	if not v.damaged.is_connected(_on_damaged.bind(v)):
		v.damaged.connect(_on_damaged.bind(v))


func _on_damaged(_zone: StringName, _hit: Dictionary, v: Vehicle) -> void:
	_hit_at[v.get_instance_id()] = Soldier._now()


## A point `gap` short of `target` on the way from `v` (where to stop to pick people up). (A
## pickup by road comes in off its last road point the same way: VehicleAI stops at the end.)
static func _stop_short(v: Vehicle, target: Vector3, gap: float) -> Vector3:
	var d := target - v.global_position
	d.y = 0.0
	return target - d.normalized() * gap if d.length() > gap else v.global_position


# --- Each tick (host) --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or orders.is_empty():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	for id: int in orders.keys():
		var o: Dictionary = orders[id]
		var v: Vehicle = o.vehicle if is_instance_valid(o.vehicle) else null
		var by: Soldier = o.by if is_instance_valid(o.by) else null
		var d := v.driver() if v else null
		if v == null or v.wrecked or by == null or d == null or not d.is_ai() or not d.vitals.is_up():
			orders.erase(id)  # no AI at the wheel any more: the order goes with him
			continue
		if dismount_on_contact and int(o.order) != Order.HOLD and _in_contact(v, o):
			_contact_drill(v, o)
			continue
		match int(o.order):
			Order.CONVOY:
				_step_convoy(v, o)
			Order.PICKUP:
				_step_pickup(v, o, by)


func _in_contact(v: Vehicle, o: Dictionary) -> bool:
	var squad: Squad = o.get("squad") if is_instance_valid(o.get("squad")) else null
	return (squad != null and squad.is_engaged()) or Soldier._now() - float(_hit_at.get(v.get_instance_id(), -INF)) < CONTACT_S


## Contact: the vehicle stops and its AI passengers get out and fight (driver and gunner stay).
func _contact_drill(v: Vehicle, o: Dictionary) -> void:
	var by: Soldier = o.by
	var squad: Squad = o.get("squad") if is_instance_valid(o.get("squad")) else null
	v.server_stop()
	o["order"] = Order.HOLD
	var out := PackedStringArray()
	for s: Soldier in v.occupants():
		if s.is_ai() and s.vitals.is_up() and s != v.driver() and s != v.gunner():
			out.append(String(s.name))
	if not out.is_empty():
		if squad == _squad(by):
			layer().server_order_dismount(by, out)
		elif squad:
			for s: Soldier in v.occupants():
				if String(s.name) in out:
					v.server_run_out(s)
			squad.give_order(by, Squad.Order.HOLD, v.global_position)  # an element: out and holding round its vehicle
	if by.owner_connected():
		by._client_message.rpc_id(by.owner_peer(), "Contact: %s stops%s" % [v.display_name(), ", the squad's out" if not out.is_empty() else ""])


func _step_convoy(v: Vehicle, o: Dictionary) -> void:
	var ahead: Node3D = o.get("ahead") if is_instance_valid(o.get("ahead")) else null
	if ahead == null:
		v.server_stop()
		return
	var fwd := -ahead.global_basis.z
	if ahead is Vehicle and (ahead as Vehicle).linear_velocity.length() > 1.0:
		fwd = (ahead as Vehicle).linear_velocity.normalized()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var place := ahead.global_position - fwd * CONVOY_GAP_M
	if v.global_position.distance_to(place) <= CONVOY_HOLD_M:
		v.server_stop()
	else:
		v.server_drive_to(place)


func _step_pickup(v: Vehicle, o: Dictionary, by: Soldier) -> void:
	if o.get("boarded", false):
		return
	if Vector2(v.global_position.x - by.global_position.x, v.global_position.z - by.global_position.z).length() > PICKUP_STOP_M + 6.0:
		if v.global_position.distance_to(o.point) > 1.0 and by.global_position.distance_to(o.point) > 12.0:
			o["point"] = by.global_position  # he moved: go to where he is now
			v.server_drive_to(_stop_short(v, by.global_position, PICKUP_STOP_M))
		return
	v.server_stop()
	o["boarded"] = true
	o["order"] = Order.HOLD
	var walkers := PackedStringArray()
	var squad := _squad(by)
	for s: Soldier in squad.members() if squad else []:
		if s.is_ai() and s.vitals.is_up() and Vehicle.ride_of(s) == null:
			walkers.append(String(s.name))
	if not walkers.is_empty():
		layer().server_order_mount(by, v.global_position, walkers)
	if by.owner_connected():
		by._client_message.rpc_id(by.owner_peer(), "%s is here: get in" % v.display_name())
