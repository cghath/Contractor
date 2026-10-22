class_name SquadDrivers
extends Node
## The squad's AI at the wheel (docs/build_plan.md wave 6, Captain 2026-10-19: "the squad's AI
## drives the squad's vehicles"). Squadmates take the wheel of the squad's ground vehicles on
## command and drive them with the vehicle's own AI (VehicleAI, through Vehicle.server_drive_to);
## a player at the wheel always has it. The command menu's Mount entries (Soldier, host):
##   take_wheel        a selected squadmate (else the best of the squad for it: never a medic
##                     while anyone else can) gets into the driver's seat of the vehicle there;
##   mount_up          the squad's AI on foot get into our vehicles near the commander: one of
##                     them at each empty wheel, one on each free main gun, the rest in the
##                     seats (a seat kept for each player of the squad on foot);
##   drive_to          the AI-driven vehicle the commander rides (on foot: every one the squad
##                     drives, in a column behind the one nearest the point) goes to the point
##                     under the crosshair and stops: by road when there's a road way;
##   drive_offroad     the same, straight across country;
##   carry             mount up, drive there in a column, and dismount carry_standoff_m short
##                     of the point along the way (further back while an enemy the squad knows
##                     of is within ENEMY_STANDOFF_M of it); the passengers get out and go on
##                     on foot (following the commander when he's with them, else holding
##                     there); drivers and gunners stay with the vehicles. The commander at a
##                     wheel himself: the squad mounts up and the column follows him instead;
##   convoy            "Follow me in vehicles": they follow the commander in a column along the
##                     way he went (ConvoyColumn), CONVOY_GAP_M apart, keeping the gap by
##                     speed, slowing for the corners, never ramming the one ahead: behind his
##                     vehicle (his own driving or an AI's) or behind him on foot;
##   pickup            they come to the commander, stop PICKUP_STOP_M off, and the squadmates on
##                     foot get in (VehicleLayer.server_order_mount);
##   drive_stop        they stop where they are and hold;
##   contact_dismount  toggles how they meet contact on the move (on to start): judged by the
##                     threat and the vehicle's armour (DriveContact: drive through, or stop and
##                     the passengers out to fight, the gunner firing on), or always drive
##                     through. A disabled vehicle is abandoned either way, crew and all.
## Not getting stuck: VehicleAI backs off and goes round what stops it; when it gives up
## (GIVE_UP_TRIES) the order plans its way again (REPATHS times, the other way the second
## time: roads or straight); then the commander hears it's stuck (a carry dismounts there).
## The host's high command gives an allied or company element the same (AlliedTroops "mount",
## "drive", "dismount": server_squad_mount / server_squad_drive / server_squad_dismount, any Squad).
## One node, "SquadDrivers", under each level's VehicleLayer. Host only. Proposed numbers.

const NODE_NAME := "SquadDrivers"
const TICK_S := 1.0
## Columns are steered this often (their places move with the lead).
const CONVOY_TICK_S := 0.25
const CONVOY_GAP_M := 22.0
## A column's driver stops within this of his place while the one ahead is stopped.
const CONVOY_HOLD_M := 6.0
## A column's AI lead drives at COLUMN_KMH, and at CRAWL_KMH while one behind it is more than
## STRAGGLE_GAPS gaps back from the one ahead of it.
const COLUMN_KMH := 40.0
const CRAWL_KMH := 10.0
const STRAGGLE_GAPS := 2.5
## Catching up in a column: up to this (m/s), and FOLLOW_SHARE of its top speed.
const FOLLOW_MAX_MS := 20.0
const FOLLOW_SHARE := 0.85
## Below this (m/s) a column's driver just waits.
const FOLLOW_MIN_MS := 1.0
const PICKUP_STOP_M := 9.0
## Hits on a vehicle count as contact for this long (s).
const CONTACT_S := 6.0
## Driving through contact: this fast (m/s, its top speed caps it), until CONTACT_S after the last
## reason to.
const THROUGH_MS := 18.0
## Mount up: our vehicles within this of the commander (m).
const MOUNT_UP_M := 50.0
## Carry: everyone sent to get in has this long (s) to; then it goes with who's aboard.
const BOARD_WAIT_S := 45.0
## Carry: dismount this far short of the point (m, along the way), and at least ENEMY_STANDOFF_M
## from any enemy the squad knows of, pulled back STANDOFF_STEP_M at a time.
const CARRY_STANDOFF_M := 100.0
const ENEMY_STANDOFF_M := 150.0
const STANDOFF_STEP_M := 20.0
## Carry: the commander riding along or within this of the dismount leads them on (Follow);
## further off, they hold there.
const LEAD_ON_M := 60.0
## Stuck: VehicleAI gives up after GIVE_UP_TRIES tries at one spot; the order plans again
## REPATHS times before it's reported stuck.
const GIVE_UP_TRIES := 4
const REPATHS := 2
## Out under fire: on the side away from the enemy, this far off the vehicle (m).
const LEE_M := 8.0
## Who takes the wheel when nobody's named: earliest first (a gunner's role last).
const DRIVER_ROLES: Array[StringName] = [Roles.RIFLEMAN, Roles.MARKSMAN, Roles.GRENADIER, Roles.TEAM_LEADER, Roles.AUTORIFLEMAN]
## An element told to mount (the high command, from the map) takes the vehicle within this of
## the point given.
const ELEMENT_PICK_M := 40.0

enum Order { NONE, DRIVE, CONVOY, PICKUP, HOLD, CARRY }

## Host: vehicle instance id -> {"vehicle", "order" (Order), "point" (where it stops), "by" (the
## commander), "squad", "roads" (whether it was sent by road), "repaths"; a column's: "lead" (the
## Node3D at its head), "slot" (1 first behind it); driving through contact: "through_until";
## a column's AI lead: "cruise" (m/s, -1 the usual)}.
var orders := {}
## Host: whether contact is judged (true) or always driven through (false; contact_dismount).
var dismount_on_contact := true
## Host: how far short of a carry's point the squad gets out (CARRY_STANDOFF_M; tests shorten it).
var carry_standoff_m := CARRY_STANDOFF_M
## Host: the carries under way: {"by", "squad", "point", "roads", "stage" ("board", "drive",
## "done"), "vehicles", "until", "lead", "follow_him" (the commander drives himself)}.
var carries: Array[Dictionary] = []
## Host: the last contact call (DriveContact's act) for each vehicle (tests, the state dump).
var last_contact := {}
var _tick := 0.0
var _convoy_tick := 0.0
var _hit_at := {}  # vehicle instance id -> [{"at", "kind", "from"}], the hits of the last CONTACT_S
var _trails := {}  # column lead instance id -> PackedVector3Array, the way it went
var _mounted: Array[Vehicle] = []  # the vehicles the last mount up has one of ours at the wheel of


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
		"mount_up":
			return server_mount_up(from, names)
		"drive_to":
			return server_drive_to(from, point)
		"drive_offroad":
			return server_drive_to(from, point, false)
		"carry":
			return server_carry(from, point, names)
		"convoy":
			return server_convoy(from)
		"pickup":
			return server_pickup(from)
		"drive_stop":
			return server_stop(from)
		"contact_dismount":
			dismount_on_contact = not dismount_on_contact
			return "On contact: %s" % ("judge it (dismount or drive through), on" if dismount_on_contact else "always drive through, judging off")
	return "Order not understood"


# --- Orders ------------------------------------------------------------------------------------

## A squadmate gets into the driver's seat of the vehicle near `point`.
func server_take_wheel(from: Soldier, point: Vector3, names: PackedStringArray) -> String:
	var squad := _squad(from)
	var v := layer().vehicle_near(point)
	if squad == null:
		return "No squad"
	if v == null or v.kind in [Vehicle.HELICOPTER, Vehicle.STATIC]:
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


## "Mount up": the squad's AI on foot (the named, else all) get into our vehicles near the
## commander, the one he rides first, then the nearest: one at each empty wheel (pick_driver), one
## on each free main gun (VehicleLayer.pick_gunner), the rest in the seats left, a seat in the
## first kept for each player of the squad on foot. Those by a door get in at once, the rest
## walk over (VehicleLayer.server_board). Returns "" or why not.
func server_mount_up(from: Soldier, names: PackedStringArray) -> String:
	_mounted.clear()
	var squad := _squad(from)
	if squad == null:
		return "No squad"
	var vs := _our_vehicles(from, squad)
	if vs.is_empty():
		return "No vehicle of ours near"
	var walkers: Array[Soldier] = []
	for s: Soldier in squad.pick(names):
		if s.is_ai() and s.vitals.is_up() and Vehicle.ride_of(s) == null and layer().boarding_of(s) == null and not is_instance_valid(s.carried_by):
			walkers.append(s)
	var keep := squad.members().filter(func(s: Soldier) -> bool: return not s.is_ai() and s.vitals.is_up() and Vehicle.ride_of(s) == null).size()
	var had := walkers.size()
	for v: Vehicle in vs:
		if walkers.is_empty():
			break
		var drv := v.driver_seat()
		if drv >= 0 and v.occupant(drv) == null and not _seat_claimed(v, drv):
			var wheel := pick_driver(walkers)
			if wheel and layer().server_board(from, wheel, v, drv):
				walkers.erase(wheel)
		var gun := int(v.gun_info().get("seat", -1))
		if gun >= 0 and v.occupant(gun) == null and not _seat_claimed(v, gun):
			var gunner := VehicleLayer.pick_gunner(walkers)
			if gunner and layer().server_board(from, gunner, v, gun):
				walkers.erase(gunner)
		var free := _free_seats(v) - layer().boarding_to(v) + (1 if _seat_claimed(v, drv) else 0) + (1 if gun >= 0 and _seat_claimed(v, gun) else 0)
		if v == vs[0]:
			free -= mini(keep, maxi(free - 1, 0))  # (seats kept for us, but it always takes one of them)
		walkers.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(v.global_position) < b.global_position.distance_to(v.global_position))
		while free > 0 and not walkers.is_empty():
			var s: Soldier = walkers.pop_front()
			if layer().server_board(from, s, v, -1):
				free -= 1
	for v: Vehicle in vs:
		var d := v.driver()
		if (d and d.is_ai() and d in squad.members()) or (v.driver_seat() >= 0 and _seat_claimed(v, v.driver_seat())):
			_mounted.append(v)
	if had > 0 and walkers.size() == had:
		return "Nobody could get in"
	return "No room for %d" % walkers.size() if not walkers.is_empty() else ""


## The AI-driven vehicle the commander rides goes to `point` (on foot: every one the squad
## drives, in a column behind the one nearest the point), by road when `roads` and the zone's
## roads make a better way, else straight.
func server_drive_to(from: Soldier, point: Vector3, roads := true) -> String:
	var vs := _targets(from)
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	point = _ground(point)
	var mine := Vehicle.ride_of(from)
	_drive_column(vs, from, point, roads, null, mine if mine in vs else null, Order.DRIVE, 0.0)
	return ""


## Host: `v` drives to `point`: by road when `roads` and the zone's roads make a better way
## (RoadRoute; a long drive with a road near both ends), else by the navmesh or straight
## (plan()). Returns whether it took the roads.
func go(v: Vehicle, point: Vector3, roads := true, speed_kmh := -1.0) -> bool:
	var info := {}
	v.server_follow_path(plan(v, point, roads, info), speed_kmh)
	return bool(info.get("roads", false))


## The way `v` would drive to `point`: along the roads (RoadRoute) when `roads` and they make a
## better way, else the navmesh's path, else straight; `info` gets "roads": whether by road.
func plan(v: Vehicle, point: Vector3, roads := true, info := {}) -> PackedVector3Array:
	var lvl := CompoundLevel.current(self)
	var def: Variant = lvl.get(&"def") if lvl else null
	info["roads"] = false
	if roads and def is Dictionary and lvl.has_method(&"ground_point"):
		var way := RoadRoute.route(def, Vector2(v.global_position.x, v.global_position.z), Vector2(point.x, point.z))
		if not way.is_empty():
			var path := PackedVector3Array()
			for p: Vector2 in way:
				path.append(lvl.call(&"ground_point", Vector3(p.x, 0.0, p.y)))
			info["roads"] = true
			return path
	var p := PackedVector3Array()
	var map := v.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		p = NavigationServer3D.map_get_path(map, v.global_position, point, true)
	if p.size() < 2 or p[p.size() - 1].distance_to(point) > VehicleAI.PATH_SLACK_M:
		return PackedVector3Array([point])
	p.remove_at(0)  # where it is now
	if p[p.size() - 1].distance_to(point) > 0.5:
		p.append(point)
	return p


## "Carry us there": mount up (server_mount_up), then once everyone's aboard (or BOARD_WAIT_S),
## drive there in a column and get out carry_standoff_m short of it (_step_carry). The
## commander at a wheel himself: mount up, then the column follows him.
func server_carry(from: Soldier, point: Vector3, names: PackedStringArray, roads := true) -> String:
	var squad := _squad(from)
	if squad == null:
		return "No squad"
	var mine := Vehicle.ride_of(from)
	var why := server_mount_up(from, names)
	var vs: Array[Vehicle] = _mounted.duplicate()
	for v: Vehicle in driven(from):
		if v not in vs:
			vs.append(v)
	if vs.is_empty():
		return why if why != "" else "Nobody of ours is at the wheel"
	carries.append({"by": from, "squad": squad, "point": _ground(point), "roads": roads, "stage": "board", "vehicles": vs,
		"until": Soldier._now() + BOARD_WAIT_S, "lead": null, "follow_him": mine != null and mine.driver() == from})
	_tick = 0.0
	return why if why.begins_with("No room") else ""


## "Follow me in vehicles": the squad's AI-driven vehicles follow the commander in a column, in
## the order they're nearest him: behind his vehicle, or behind him on foot.
func server_convoy(from: Soldier) -> String:
	var lead: Node3D = Vehicle.ride_of(from)
	if lead == null:
		lead = from
	var vs := driven(from).filter(func(v: Vehicle) -> bool: return v != lead)
	if vs.is_empty():
		return "Nobody of ours is at the wheel"
	_form_column(vs, lead, from, null)
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
	for op in carries:
		if op.by == from:
			op.stage = "done"
	return ""


## The order vehicle `v` drives under (Order.NONE for none).
func order_of(v: Vehicle) -> int:
	return int((orders.get(v.get_instance_id(), {}) as Dictionary).get("order", Order.NONE))


# --- An element's vehicles (the host's high command, AlliedTroops) ------------------------------

## Host: `squad` (an element) takes the vehicle near `point`: one of it at the wheel, the rest in
## the other seats (VehicleLayer.server_board, walking over to it). Returns "" or why not.
func server_squad_mount(by: Soldier, squad: Squad, point: Vector3) -> String:
	var v := layer().vehicle_near(point, ELEMENT_PICK_M)
	if v == null or v.kind in [Vehicle.HELICOPTER, Vehicle.STATIC]:
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


## Host: the vehicles `squad` (an element) drives go to `point` (a column, more than one).
func server_squad_drive(by: Soldier, squad: Squad, point: Vector3) -> String:
	var vs := driven_by(squad)
	if vs.is_empty():
		return "nobody of it at a wheel"
	_drive_column(vs, by, point, true, squad, null, Order.DRIVE, 0.0)
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
## Host: an escort or a convoy truck of `squad` (its own crew at the wheel, AI) drives `path` at
## `speed_kmh` as an order, so contact on the way is met as the squad's own vehicles meet it
## (F-140, the overwatch mission's convoy): it always drives through the kill zone, faster, the
## gunner firing on (AavGunner), and when it's disabled the crew bail out on the side away from
## the fire and fight from there (DriveContact ABANDON). Returns whether it was given.
func server_drive_route(v: Vehicle, path: PackedVector3Array, speed_kmh: float, squad: Squad) -> bool:
	var d := v.driver() if v else null
	if d == null or not d.is_ai() or path.is_empty():
		return false
	var by: Soldier = squad.leader if squad and is_instance_valid(squad.leader) and squad.leader.vitals.is_up() else d
	_give(v, Order.DRIVE, by, path[path.size() - 1], squad)
	var o: Dictionary = orders[v.get_instance_id()]
	o["through_only"] = true  # a convoy pushes through: it stops only when it can't go on
	o["roads"] = true
	o["cruise"] = speed_kmh / 3.6 if speed_kmh > 0.0 else -1.0
	v.server_follow_path(path, speed_kmh)
	return true


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
		if not v.wrecked and not v.kind in [Vehicle.HELICOPTER, Vehicle.STATIC] and d and d.is_ai() and d.vitals.is_up() and d in members:
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


## Our ground vehicles to mount up in: whole enough to drive, within MOUNT_UP_M of the commander
## (or with one of ours at the wheel), nobody of another side aboard, at the wheel nobody or a
## player or one of ours; the one he rides first, then the nearest.
func _our_vehicles(from: Soldier, squad: Squad) -> Array[Vehicle]:
	var members := squad.members()
	var mine := Vehicle.ride_of(from)
	var out: Array[Vehicle] = []
	for v: Vehicle in layer().vehicles():
		if v.wrecked or v.kind in [Vehicle.HELICOPTER, Vehicle.STATIC] or not v.can_drive() or DriveContact.is_disabled(v):
			continue
		var d := v.driver()
		if d and d.is_ai() and d not in members:
			continue  # an element's, or the enemy's
		if v.global_position.distance_to(from.global_position) > MOUNT_UP_M and not (d and d in members):
			continue
		if v.occupants().any(func(s: Soldier) -> bool: return s.faction != from.faction and not Person.is_person(s)):
			continue
		out.append(v)
	out.sort_custom(func(a: Vehicle, b: Vehicle) -> bool:
		if (a == mine) != (b == mine):
			return a == mine
		return a.global_position.distance_to(from.global_position) < b.global_position.distance_to(from.global_position))
	return out


## Seats of `v` nobody sits in (not the driver's, the main gun's or an exo's).
func _free_seats(v: Vehicle) -> int:
	var gun := int(v.gun_info().get("seat", -1))
	var n := 0
	for i in v.seat_count():
		if v.occupant(i) == null and i != v.driver_seat() and i != gun and not v.exo_seat(i):
			n += 1
	return n


## Whether a squadmate is on his way to seat `seat` of `v`.
func _seat_claimed(v: Vehicle, seat: int) -> bool:
	if seat < 0:
		return false
	for b: Dictionary in layer()._boarding.values():
		if b.vehicle == v and int(b.get("seat", -1)) == seat:
			return true
	return false


func _squad(from: Soldier) -> Squad:
	var lvl := CompoundLevel.current(self)
	return lvl.squad_for(from.faction) if lvl and from else null


func _ground(point: Vector3) -> Vector3:
	var lvl := CompoundLevel.current(self)
	return lvl.call(&"ground_point", point) if lvl and lvl.has_method(&"ground_point") else point  # (a map order comes without a height)


func _give(v: Vehicle, order: int, by: Soldier, point: Vector3, squad: Squad = null) -> void:
	orders[v.get_instance_id()] = {"vehicle": v, "order": order, "by": by, "point": point, "squad": squad if squad else _squad(by), "repaths": 0}
	v._ensure_ai()
	v.ai.give_up_tries = 0 if order == Order.CONVOY else GIVE_UP_TRIES  # (a column keeps trying: its place moves on)
	if not v.damaged.is_connected(_on_damaged.bind(v)):
		v.damaged.connect(_on_damaged.bind(v))
	if not v.ai.gave_up.is_connected(_on_gave_up.bind(v)):
		v.ai.gave_up.connect(_on_gave_up.bind(v))


func _tell(by: Variant, text: String) -> void:
	if is_instance_valid(by) and (by as Soldier).owner_connected():
		(by as Soldier)._client_message.rpc_id((by as Soldier).owner_peer(), text)


## A point `gap` short of `target` on the way from `v` (where to stop to pick people up). (A
## pickup by road comes in off its last road point the same way: VehicleAI stops at the end.)
static func _stop_short(v: Vehicle, target: Vector3, gap: float) -> Vector3:
	var d := target - v.global_position
	d.y = 0.0
	return target - d.normalized() * gap if d.length() > gap else v.global_position


## `path` (driven from `start`) cut `short_m` short along the way; empty when it's no longer.
static func cut_short(path: PackedVector3Array, start: Vector3, short_m: float) -> PackedVector3Array:
	var pts := PackedVector3Array([start])
	pts.append_array(path)
	var left := short_m
	var i := pts.size() - 1
	while i > 0:
		var seg := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		if seg > left:
			var out := pts.slice(1, i)
			out.append(pts[i].lerp(pts[i - 1], left / seg))
			return out
		left -= seg
		i -= 1
	return PackedVector3Array()


# --- Columns -----------------------------------------------------------------------------------

## `vs` drive to `point` (`roads` as plan()) in a column behind `lead` (null: the one nearest the
## point), `short_m` short of it (a carry); the lead under `order`, the rest CONVOY behind it.
## Returns the lead, or null when the way there is shorter than `short_m` (nobody moves).
func _drive_column(vs: Array[Vehicle], by: Soldier, point: Vector3, roads: bool, squad: Squad, lead: Vehicle, order: int, short_m: float) -> Vehicle:
	if lead == null:
		lead = vs[0]
		for v in vs:
			if v.global_position.distance_to(point) < lead.global_position.distance_to(point):
				lead = v
	var info := {}
	var path := plan(lead, point, roads, info)
	if short_m > 0.0:
		path = cut_short(path, lead.global_position, short_m)
		var tries := 0
		while not path.is_empty() and _enemy_near(squad if squad else _squad(by), path[path.size() - 1], ENEMY_STANDOFF_M) and tries < 50:
			path = cut_short(path, lead.global_position, STANDOFF_STEP_M)
			tries += 1
		if path.is_empty():
			return null
	_give(lead, order, by, path[path.size() - 1], squad)
	var o: Dictionary = orders[lead.get_instance_id()]
	o["roads"] = bool(info.roads)
	o["cruise"] = COLUMN_KMH / 3.6 if vs.size() > 1 else -1.0
	lead.server_follow_path(path, COLUMN_KMH if vs.size() > 1 else -1.0)
	var rest: Array = vs.filter(func(v: Vehicle) -> bool: return v != lead)
	if not rest.is_empty():
		_form_column(rest, lead, by, squad)
	return lead


## `vs` follow `lead` in a column, in the order they're nearest it.
func _form_column(vs: Array, lead: Node3D, by: Soldier, squad: Squad) -> void:
	vs.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.global_position.distance_to(lead.global_position) < b.global_position.distance_to(lead.global_position))
	_trails[lead.get_instance_id()] = PackedVector3Array([lead.global_position])
	var slot := 1
	for v: Vehicle in vs:
		_give(v, Order.CONVOY, by, Vector3.ZERO, squad)
		orders[v.get_instance_id()]["lead"] = lead
		orders[v.get_instance_id()]["slot"] = slot
		slot += 1
	_convoy_tick = 0.0


## The vehicles following `lead` (CONVOY), first behind it first.
func column_of(lead: Node3D) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for o: Dictionary in orders.values():
		if int(o.order) == Order.CONVOY and o.get("lead") == lead and is_instance_valid(o.vehicle):
			out.append(o.vehicle)
	out.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return int(orders[a.get_instance_id()].slot) < int(orders[b.get_instance_id()].slot))
	return out


## Whether the squad knows of an enemy within `within` of `at`.
func _enemy_near(squad: Squad, at: Vector3, within: float) -> bool:
	if squad == null:
		return false
	for e: Dictionary in squad.enemy_picture():
		var p: Vector3 = e.pos
		if float(e.age) <= Squad.STALE_S and Vector2(p.x - at.x, p.z - at.z).length() < within:
			return true
	return false


static func _speed_of(n: Node3D) -> float:
	var vel := Vector3.ZERO
	if n is Vehicle:
		vel = (n as Vehicle).linear_velocity
	elif n is CharacterBody3D:
		vel = (n as CharacterBody3D).velocity
	return Vector2(vel.x, vel.z).length()


static func _fwd_of(n: Node3D) -> Vector3:
	if n is Vehicle and (n as Vehicle).linear_velocity.length() > 1.0:
		return (n as Vehicle).linear_velocity.normalized()
	return -n.global_basis.z


# --- Contact -----------------------------------------------------------------------------------

func _on_damaged(_zone: StringName, hit: Dictionary, v: Vehicle) -> void:
	var shooter: Variant = hit.get("shooter")
	var from := Vector3.INF
	if is_instance_valid(shooter) and shooter is Soldier:
		var d := v.driver()
		if d and (shooter as Soldier).faction == d.faction:
			return  # one of ours (a stray round): not contact
		from = (shooter as Soldier).global_position
	var id := v.get_instance_id()
	if not _hit_at.has(id):
		_hit_at[id] = []
	(_hit_at[id] as Array).append({"at": Soldier._now(), "kind": StringName(hit.get("kind", Vehicle.KINETIC)), "from": from})


## The hits `v` took in the last CONTACT_S.
func _hits(v: Vehicle) -> Array:
	var id := v.get_instance_id()
	var now := Soldier._now()
	var out: Array = (_hit_at.get(id, []) as Array).filter(func(h: Dictionary) -> bool: return now - float(h.at) < CONTACT_S)
	if out.is_empty():
		_hit_at.erase(id)
	else:
		_hit_at[id] = out
	return out


## Contact on the move: what DriveContact says. Returns whether the order stopped for it.
func _meet_contact(v: Vehicle, o: Dictionary) -> bool:
	var a := DriveContact.assess(v, o.get("squad"), _hits(v), not dismount_on_contact or bool(o.get("through_only", false)))
	last_contact[v.get_instance_id()] = a.act
	if (a.enemy as Vector3) != Vector3.INF:
		o["threat"] = a.enemy  # the last threat it met: where the crew keep away from once it's quiet (F-140)
	match String(a.act):
		DriveContact.ABANDON:
			_abandon(v, o, a.enemy if (a.enemy as Vector3) != Vector3.INF else o.get("threat", Vector3.INF))
			return true
		DriveContact.DISMOUNT:
			if int(o.order) != Order.HOLD:
				_halt_column(v, o, a.enemy)
				_tell(o.by, "Contact: %s stops, the squad's out (%s)" % [v.display_name(), a.why])
				return true
		DriveContact.THROUGH:
			if int(o.order) != Order.HOLD:
				_drive_through(v, o, String(a.why))
	return false


## Through the kill zone: faster until CONTACT_S after the last reason to (a column's driver
## keeps following: its place runs on ahead).
func _drive_through(v: Vehicle, o: Dictionary, why: String) -> void:
	if not o.has("through_until"):
		_tell(o.by, "Contact: %s drives through (%s)" % [v.display_name(), why])
	o["through_until"] = Soldier._now() + CONTACT_S
	if int(o.order) in [Order.DRIVE, Order.CARRY, Order.PICKUP] and is_instance_valid(v.ai) and v.ai.active:
		v.ai.cruise_ms = minf(THROUGH_MS, v.top_speed() * 0.9)


func _end_through(v: Vehicle, o: Dictionary) -> void:
	if o.has("through_until") and Soldier._now() > float(o.through_until):
		o.erase("through_until")
		if is_instance_valid(v.ai) and int(o.order) != Order.CONVOY:
			v.ai.cruise_ms = float(o.get("cruise", -1.0))


## Stops `v`'s whole column (every vehicle with the same lead, and the lead when it's ours) and
## the passengers get out on the side away from `enemy` (the drivers and gunners stay).
func _halt_column(v: Vehicle, o: Dictionary, enemy: Vector3) -> void:
	var head: Node3D = o.get("lead") if int(o.order) == Order.CONVOY and is_instance_valid(o.get("lead")) else v
	var halt: Array[Vehicle] = column_of(head)
	if head is Vehicle and orders.has(head.get_instance_id()) and head not in halt:
		halt.push_front(head as Vehicle)
	if v not in halt:
		halt.append(v)
	for h: Vehicle in halt:
		var ho: Dictionary = orders[h.get_instance_id()]
		h.server_stop()
		ho["order"] = Order.HOLD
		_dismount_here(h, ho, enemy, false)
	for op in carries:
		if op.lead == head or op.lead == v:
			op.stage = "done"


## Disabled: everyone aboard gets out, crew too, to cover away from `enemy`; the order's over.
func _abandon(v: Vehicle, o: Dictionary, enemy: Vector3) -> void:
	v.server_stop()
	var out := _dismount_here(v, o, enemy, true)
	orders.erase(v.get_instance_id())
	for op in carries:
		if op.lead == v:
			op.stage = "done"
	_tell(o.by, "%s is disabled: %s" % [v.display_name(), "everyone out" if not out.is_empty() else "abandoned"])


## The AI aboard `v` (not the driver and the gunner unless `everyone`) get out and hold on the
## side away from `enemy` (Vector3.INF: on its right). Returns their names.
func _dismount_here(v: Vehicle, o: Dictionary, enemy: Vector3, everyone: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Soldier in v.occupants():
		if s.is_ai() and s.vitals.is_up() and not Person.is_person(s) and (everyone or (s != v.driver() and s != v.gunner())):
			out.append(String(s.name))
	for s: Soldier in v.occupants():
		if String(s.name) in out:
			v.server_run_out(s)  # out of a walk-in bay at a run (Vehicle.server_run_out)
	var squad: Squad = o.get("squad") if is_instance_valid(o.get("squad")) else null
	if not out.is_empty() and squad and is_instance_valid(o.by):
		squad.give_order(o.by, Squad.Order.HOLD, lee_of(v, enemy), out)
	var crew := 0
	for s: Soldier in v.get_tree().get_nodes_in_group(&"combatants") if not out.is_empty() else []:
		if String(s.name) in out and s.has_meta(&"vehicle_crew") and SquadAI.of(s):
			SquadAI.of(s).on_order(Squad.Order.MOVE, lee_of(v, enemy), crew, out.size())  # (a convoy's crew aren't squad members: to the lee, then hold there; F-140)
			crew += 1
	return out


## Where to get out to: LEE_M off `v` on the side away from `enemy` (INF: on its right).
static func lee_of(v: Vehicle, enemy: Vector3) -> Vector3:
	var away := v.global_basis.x
	if enemy != Vector3.INF:
		away = v.global_position - enemy
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	return v.global_position + away * LEE_M


# --- Stuck -------------------------------------------------------------------------------------

## VehicleAI gave up getting past what stops it: plan the way again (the second time, the other
## way: roads or straight), then report it stuck (a carry gets out there).
func _on_gave_up(v: Vehicle) -> void:
	var o: Dictionary = orders.get(v.get_instance_id(), {})
	if o.is_empty() or not is_instance_valid(v):
		return
	if int(o.order) in [Order.DRIVE, Order.CARRY, Order.PICKUP] and int(o.get("repaths", 0)) < REPATHS:
		o["repaths"] = int(o.get("repaths", 0)) + 1
		var roads := bool(o.get("roads", true)) != (int(o.repaths) == REPATHS)
		var cruise := float(o.get("cruise", -1.0))
		v.server_follow_path(plan(v, o.point, roads), cruise * 3.6 if cruise > 0.0 else -1.0)
		return
	v.server_stop()
	o["order"] = Order.HOLD
	_tell(o.by, "%s is stuck: it can't get through" % v.display_name())
	for op in carries:
		if op.lead == v and op.stage == "drive":
			_carry_out(op)


# --- Carrying the squad ------------------------------------------------------------------------

func _step_carry(op: Dictionary) -> void:
	var by: Soldier = op.by if is_instance_valid(op.by) else null
	if by == null:
		op.stage = "done"
		return
	match String(op.stage):
		"board":
			var vs: Array = (op.vehicles as Array).filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Vehicle).wrecked)
			if vs.any(func(v: Vehicle) -> bool: return layer().boarding_to(v) > 0) and Soldier._now() < float(op.until):
				return
			for v: Vehicle in vs:
				layer().server_cancel_boarding(v)  # (time's up: it goes with who's aboard)
			var squad: Squad = op.squad if is_instance_valid(op.squad) else null
			var ours: Array[Vehicle] = []
			for v: Vehicle in vs:
				var d := v.driver()
				if squad and d and d.is_ai() and d.vitals.is_up() and d in squad.members():
					ours.append(v)
			if bool(op.follow_him):
				var mine := Vehicle.ride_of(by)
				var rest := ours.filter(func(v: Vehicle) -> bool: return v != mine)
				if mine and not rest.is_empty():
					_form_column(rest, mine, by, null)
				_tell(by, "Mounted up: following you")
				op.stage = "done"
				return
			if ours.is_empty():
				_tell(by, "Nobody of ours is at the wheel")
				op.stage = "done"
				return
			var mine := Vehicle.ride_of(by)
			op.vehicles = ours
			op.lead = _drive_column(ours, by, op.point, bool(op.roads), null, mine if mine in ours else null, Order.CARRY, carry_standoff_m)
			if op.lead == null:
				op.lead = ours[0]
				_carry_out(op)  # already within the stand-off
				return
			op.stage = "drive"
		"drive":
			var lead: Vehicle = op.lead if is_instance_valid(op.lead) else null
			if lead == null or order_of(lead) != Order.CARRY:
				op.stage = "done"  # contact took over (DriveContact), or it's gone
				return
			if lead.ai.status == "arrived":
				_carry_out(op)


## The carry's there: every vehicle in it stops and holds, and the passengers get out and go on
## on foot: following the commander when he rode along or is near, else holding there.
func _carry_out(op: Dictionary) -> void:
	op.stage = "done"
	var by: Soldier = op.by if is_instance_valid(op.by) else null
	var squad: Squad = op.squad if is_instance_valid(op.squad) else null
	var lead: Vehicle = op.lead if is_instance_valid(op.lead) else null
	var names := PackedStringArray()
	var rode := false
	for v: Variant in op.vehicles:
		if not is_instance_valid(v):
			continue
		var veh := v as Vehicle
		veh.server_stop()
		if orders.has(veh.get_instance_id()):
			orders[veh.get_instance_id()]["order"] = Order.HOLD
		if by and veh.seat_of(by) >= 0:
			rode = true
		var out: Array[Soldier] = []
		for s: Soldier in veh.occupants():
			if s.is_ai() and s.vitals.is_up() and not Person.is_person(s) and s != veh.driver() and s != veh.gunner():
				out.append(s)
		for s in out:
			names.append(String(s.name))
			veh.server_run_out(s)
	if names.is_empty() or squad == null or by == null:
		return
	var at := lead.global_position if lead else by.global_position
	var near := rode or by.global_position.distance_to(at) < LEAD_ON_M
	squad.give_order(by, Squad.Order.FOLLOW if near else Squad.Order.HOLD, by.global_position if near else at, names)
	var short := Vector2(at.x - (op.point as Vector3).x, at.z - (op.point as Vector3).z).length()
	_tell(by, "Dismounted %.0f m short: %s" % [short, "on you" if near else "holding there"])


# --- Each tick (host) --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or (orders.is_empty() and carries.is_empty()):
		return
	_convoy_tick -= delta
	if _convoy_tick <= 0.0:
		_convoy_tick = CONVOY_TICK_S
		_step_columns()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	for id: int in orders.keys():
		if not orders.has(id):
			continue  # (its column or its carry ended it this tick)
		var o: Dictionary = orders[id]
		var v: Vehicle = o.vehicle if is_instance_valid(o.vehicle) else null
		var by: Soldier = o.by if is_instance_valid(o.by) else null
		var d := v.driver() if v else null
		if v == null or v.wrecked or by == null or d == null or not d.is_ai() or not d.vitals.is_up():
			orders.erase(id)  # no AI at the wheel any more: the order goes with him
			continue
		if _meet_contact(v, o):
			continue
		_end_through(v, o)
		if int(o.order) == Order.PICKUP:
			_step_pickup(v, o, by)
	for op: Dictionary in carries.duplicate():
		_step_carry(op)
	carries.assign(carries.filter(func(op: Dictionary) -> bool: return op.stage != "done"))


## Every column: the leads' trails, each follower to its place at its speed, an AI lead paced to
## its stragglers.
func _step_columns() -> void:
	var leads := {}
	for o: Dictionary in orders.values():
		if int(o.order) == Order.CONVOY and is_instance_valid(o.get("lead")) and is_instance_valid(o.vehicle):
			leads[(o.lead as Node3D).get_instance_id()] = o.lead
	for id: int in _trails.keys():
		if not leads.has(id):
			_trails.erase(id)
	for id: int in leads:
		var lead: Node3D = leads[id]
		_trails[id] = ConvoyColumn.record(_trails.get(id, PackedVector3Array()), lead.global_position)
		var straggling := false
		var ahead: Node3D = lead
		var ahead_back := 0.0
		var k := 0
		for v: Vehicle in column_of(lead):
			k += 1
			var o: Dictionary = orders[v.get_instance_id()]
			var d := v.driver()
			if d == null or not d.is_ai():
				continue  # (the tick drops it)
			var back := maxf(CONVOY_GAP_M * k, ahead_back + CONVOY_GAP_M)
			var gap := Vector2(v.global_position.x - ahead.global_position.x, v.global_position.z - ahead.global_position.z).length()
			straggling = straggling or gap > CONVOY_GAP_M * STRAGGLE_GAPS
			_step_follower(v, o, lead, ahead, back, ahead_back, gap)
			ahead_back = ConvoyColumn.back_of(_trails[id], lead.global_position, v.global_position)
			ahead = v
		_pace_lead(lead, straggling)


## A column's driver: along the trail towards its place `back` behind `lead` (steering for a
## point a little past it), at the speed that keeps its `gap` to `ahead` (`ahead_back` along the
## trail); stopped when it's close enough and the one ahead is stopped.
func _step_follower(v: Vehicle, o: Dictionary, lead: Node3D, ahead: Node3D, back: float, ahead_back: float, gap: float) -> void:
	var trail: PackedVector3Array = _trails.get(lead.get_instance_id(), PackedVector3Array())
	var fwd := _fwd_of(lead)
	var spot := ConvoyColumn.place(trail, lead.global_position, fwd, back)
	var ahead_ms := _speed_of(ahead)
	var top := minf(v.top_speed() * FOLLOW_SHARE, FOLLOW_MAX_MS)
	var want := ConvoyColumn.follow_speed(gap, CONVOY_GAP_M, ahead_ms, top)
	var to_spot := Vector2(v.global_position.x - spot.x, v.global_position.z - spot.z).length()
	o["point"] = spot
	if want < FOLLOW_MIN_MS or (to_spot <= CONVOY_HOLD_M and ahead_ms < FOLLOW_MIN_MS):
		v.server_stop()
		return
	var carrot_back := maxf(back - ConvoyColumn.LOOKAHEAD_M, ahead_back + ConvoyColumn.AHEAD_CLEAR_M)
	var carrot := ConvoyColumn.place(trail, lead.global_position, fwd, carrot_back)
	v.ai.steer_to(ConvoyColumn.route(trail, lead.global_position, v.global_position, carrot, carrot_back), want, true)


## An AI lead of a column (under our order) crawls while one behind is straggling.
func _pace_lead(lead: Node3D, straggling: bool) -> void:
	if not lead is Vehicle:
		return
	var o: Dictionary = orders.get(lead.get_instance_id(), {})
	var v := lead as Vehicle
	if o.is_empty() or not int(o.order) in [Order.DRIVE, Order.CARRY] or not is_instance_valid(v.ai) or not v.ai.active or o.has("through_until"):
		return
	v.ai.cruise_ms = CRAWL_KMH / 3.6 if straggling else float(o.get("cruise", -1.0))


func _step_pickup(v: Vehicle, o: Dictionary, by: Soldier) -> void:
	if o.get("boarded", false):
		return
	if Vector2(v.global_position.x - by.global_position.x, v.global_position.z - by.global_position.z).length() > PICKUP_STOP_M + 6.0:
		if v.global_position.distance_to(o.point) > 1.0 and by.global_position.distance_to(o.point) > 12.0:
			o["point"] = by.global_position  # he moved: go to where he is now
			go(v, _stop_short(v, by.global_position, PICKUP_STOP_M))
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
	_tell(by, "%s is here: get in" % v.display_name())
