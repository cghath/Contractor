class_name FfvGunner
extends Node
## AI passengers in fire-from-vehicle seats (VehicleBay, Captain 2026-10-16: "ffv seats in both
## for player and ai"; host only, a child of the vehicle). While the bay is open, each AI in an
## FFV seat who is up and has a gun in hand picks the nearest enemy out of its door (the seat's
## arc: VehicleBay.ffv_arc_ok), in clear sight, no friend near the line, and fires short bursts
## through the same host fire path a soldier on foot uses (Soldier._server_fire: rate, spread,
## ammo, noise), reloading when the magazine runs dry. The seated brain is off (Vehicle.server_
## enter), so this is all the fighting they do aboard. Shooting from a moving aircraft is wild:
## the spread grows while it flies.

const NODE_NAME := "FfvGunner"
const CHECK_S := 0.6
const RANGE_M := 350.0
const FRIEND_CLEAR_M := 2.5
const AIRBORNE_SPREAD := 2.2

var vehicle: Vehicle
## Rounds fired so far (tests).
var fired := 0
## Per seat: {"target", "check", "next", "burst", "pause_until"}.
var _seats := {}


static func attach(v: Vehicle) -> FfvGunner:
	var have := v.get_node_or_null(NodePath(NODE_NAME)) as FfvGunner
	if have:
		return have
	var g := FfvGunner.new()
	g.name = NODE_NAME
	g.vehicle = v
	v.add_child(g)
	return g


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(vehicle) or vehicle.bay == null or vehicle.wrecked:
		return
	if not vehicle.bay.open:
		_seats.clear()
		return
	for seat in vehicle.seat_count():
		if vehicle.bay.ffv_side(seat) != 0.0:
			_seat_step(seat, delta)


func _seat_step(seat: int, delta: float) -> void:
	var s := vehicle.occupant(seat)
	if s == null or not s.is_ai() or not s.vitals.is_up():
		_seats.erase(seat)
		return
	var weapon := s.active_weapon()
	if weapon == null or weapon.type != "weapon" or Launchers.is_launcher(weapon):
		return
	var st: Dictionary = _seats.get(seat, {"target": null, "check": 0.0, "next": 0.0, "burst": 0, "pause_until": 0.0})
	_seats[seat] = st
	st.check = float(st.check) - delta
	var target := st.target as Soldier
	if st.check <= 0.0 or target == null or not is_instance_valid(target) or not target.vitals.is_up():
		st.check = CHECK_S
		target = _pick(s, seat)
		st.target = target
	if target == null:
		return
	var now := Soldier._now()
	if s.inventory.rounds_in(s.active_slot) <= 0:
		if now >= s._busy_until and s.inventory.spare_rounds(Soldier._ammo_of(weapon)) > 0:
			s._server_reload.rpc_id(1, s.active_slot)
		return
	if now < float(st.next) or now < float(st.pause_until) or now < s._busy_until:
		return
	var origin := s.camera.global_position
	var aim := target.aim_point()
	var dir := (aim - origin).normalized()
	if not vehicle.ffv_ok(s, dir):
		st.target = null
		return
	var auto: bool = weapon.stats.get("auto", false)
	st.next = now + 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	if int(st.burst) <= 0:
		st.burst = randi_range(3, 5) if auto else randi_range(1, 2)
	st.burst = int(st.burst) - 1
	if int(st.burst) <= 0:
		st.pause_until = now + randf_range(0.6, 1.4)
	var spread := deg_to_rad(s.ai_spread_deg(weapon))
	var heli := vehicle as Helicopter
	if heli and heli.is_airborne():
		spread *= AIRBORNE_SPREAD
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(spread) * 0.6).normalized()
	s._server_fire.rpc_id(1, origin, dir, s.active_slot)
	fired += 1


## The nearest enemy out of seat `seat`'s door, in range, in clear sight, no friend in the way.
func _pick(s: Soldier, seat: int) -> Soldier:
	var lvl := vehicle.level()
	if lvl == null:
		return null
	var origin := s.camera.global_position
	var everyone: Array[Soldier] = []
	for holder: Node in [lvl.players, lvl.ai]:
		for n in holder.get_children():
			var o := n as Soldier
			if o and not o.is_queued_for_deletion() and o.vitals.is_up():
				everyone.append(o)
	var foes: Array = []
	for o in everyone:
		if o.faction == s.faction or Person.is_noncombatant(o) or o.faction == Person.FACTION:
			continue
		var ride := Vehicle.ride_of(o)
		if ride and not ride.seat_open(ride.seat_of(o)):
			continue  # shut inside a vehicle
		var d := origin.distance_to(o.global_position)
		if d <= RANGE_M and vehicle.ffv_ok(s, o.aim_point() - origin):
			foes.append([d, o])
	foes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var exclude: Array[RID] = [vehicle.get_rid(), s.get_rid()]
	var space := vehicle.get_world_3d().direct_space_state
	for f: Array in foes.slice(0, 6):
		var o: Soldier = f[1]
		var aim := o.aim_point()
		var q := PhysicsRayQueryParameters3D.create(origin, aim, 1 | Vehicle.LAYER, exclude)
		if not space.intersect_ray(q).is_empty():
			continue
		if _friend_in_line(s, everyone, origin, aim):
			continue
		return o
	return null


func _friend_in_line(s: Soldier, everyone: Array[Soldier], from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var length := seg.length()
	if length < 0.1:
		return false
	var dir := seg / length
	for o in everyone:
		if o == s or o.faction != s.faction or Vehicle.ride_of(o) == vehicle:
			continue
		var p := o.global_position + Vector3.UP * 1.0
		var t := clampf((p - from).dot(dir), 0.0, length)
		if t > 1.0 and p.distance_to(from + dir * t) < FRIEND_CLEAR_M:
			return true
	return false
