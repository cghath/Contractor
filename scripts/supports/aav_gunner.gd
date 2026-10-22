class_name AavGunner
extends Node
## An AI gunner on a vehicle's mounted gun (wave 5b, V4; host only): whoever sits in the gun's
## seat (Vehicle.gunner()), if they're AI and up, looks for enemies every check_s (soldiers of
## another side, not civilians, up, out in the open or in an open seat, within range_m and in
## clear sight of the muzzle) and fires bursts at the nearest through Vehicle.server_fire_gun
## (the gun's own rate, spread and belts from the hold), holding fire while a friend stands
## near the line. The support AAV's gunner and an enemy technical's both use it. Numbers in
## data/ground_supports.json "gunner" (Proposed). A child of the vehicle on the host only.
## A turret (VehicleTurret) turns to the target at its own speeds and within its limits, as a
## player's does (Vehicle.server_aim), and fires once its barrel is on (Vehicle.gun_on); the
## gunner's own unsteadiness goes into where it aims.
## Captain, 2026-10-15 (v0.4.3 co-op): every gun seat (Vehicle.gun_seats) has its own: the
## M-ATV's M2 and a Black Hawk's two M240H door guns, each at the enemies in its own arc. Every
## armed vehicle gets one (Vehicle._ready), so an AI squadmate on the gun engages.

const NODE_NAME := "AIGunner"
## Aim at the chest; a little below for a target lying down.
const LOW_TARGET_M := 0.4

var vehicle: Vehicle
## The soldier being fired at (tests, the session log): the main gun's, else the last picked.
var target: Soldier
## Rounds fired so far, all its guns (tests).
var fired := 0
var _cfg := {}
## Per gun seat: {"target", "check", "burst", "pause"}.
var _seats := {}
## Who the gunners have made out: soldier instance id -> [awareness 0..1, when last looked at].
var _aware := {}


## Host: gives `v` an AI gunner (once). Returns it.
static func attach(v: Vehicle) -> AavGunner:
	var have := v.get_node_or_null(NodePath(NODE_NAME)) as AavGunner
	if have:
		return have
	var g := AavGunner.new()
	g.name = NODE_NAME
	g.vehicle = v
	v.add_child(g)
	return g


func _ready() -> void:
	_cfg = AavSupport.data().get("gunner", {})


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(vehicle) or vehicle.wrecked or vehicle.is_burning():
		return
	var main := vehicle.gunner()
	if main == null or not main.is_ai() or not main.vitals.is_up():
		target = null
	for seat in vehicle.gun_seats():
		_seat_step(seat, delta)


func _seat_step(seat: int, delta: float) -> void:
	var gunner := vehicle.occupant(seat)
	var st: Dictionary = _seats.get(seat, {})
	_seats[seat] = st
	var brain := SquadAI.of(gunner) if gunner else null
	if gunner == null or not gunner.is_ai() or not gunner.vitals.is_up() or vehicle.gun_info(seat).is_empty() or (brain and brain.hold_fire):
		st.erase("target")  # a squadmate told to hold fire holds it on the gun too
		return
	st.check = float(st.get("check", 0.0)) - delta
	if st.check <= 0.0:
		st.check = float(_cfg.get("check_s", 0.5))
		st.target = _pick(gunner, seat)
		if st.target or seat == vehicle.gun_info().get("seat", -1):
			target = st.target
	var foe: Soldier = st.get("target") if is_instance_valid(st.get("target")) else null
	if foe == null or not foe.vitals.is_up():
		st.burst = 0
		return
	if float(st.get("pause", 0.0)) > 0.0:
		st.pause = float(st.pause) - delta
		return
	if int(st.get("burst", 0)) <= 0:
		var burst: Array = _cfg.get("burst", [4, 9])
		st.burst = randi_range(int(burst[0]), int(burst[1]))
	var muzzle := vehicle.gun_origin(seat)
	var aim := foe.aim_point() if foe.vitals.is_up() else foe.body_point() + Vector3.UP * LOW_TARGET_M
	var exact := (aim - muzzle).normalized()
	var spread := deg_to_rad(float(_cfg.get("spread_deg", 0.8)))
	var side := exact.cross(Vector3.UP).normalized() if absf(exact.y) < 0.99 else Vector3.RIGHT
	var dir := (exact + side * randf_range(-1, 1) * tan(spread) + side.cross(exact) * randf_range(-1, 1) * tan(spread)).normalized()
	var main := seat == int(vehicle.gun_info().get("seat", -1))
	if main:
		vehicle.server_aim(dir)
	else:
		## A door gun (DoorGun) swings with its gunner: he turns and looks down the line of fire.
		gunner.rotation.y = atan2(-exact.x, -exact.z)
		gunner.model.look_pitch = asin(clampf(exact.y, -1.0, 1.0))
	if not vehicle.gun_on(exact, VehicleTurret.ON_TARGET_DEG, -1 if main else seat):
		return  # still turning onto it (a door gun: it went out of the arc)
	if not main and not vehicle.door_arc_ok(seat, dir):
		dir = exact  # the spread took it past the door's edge
	var shot := vehicle.server_fire_gun(gunner, dir)
	if shot.is_empty():
		if vehicle.gun_info(seat).get("rounds", 0) <= 0:
			st.erase("target")  # dry: nothing more to do until the hold is restocked
		return
	fired += 1
	_noise(gunner, muzzle)
	st.burst = int(st.burst) - 1
	if st.burst <= 0:
		var pause: Array = _cfg.get("pause_s", [0.8, 1.8])
		st.pause = randf_range(float(pause[0]), float(pause[1]))


## The nearest enemy in range of gun seat `seat` (a door gun: in its arc), in clear sight of
## the muzzle, with no friend near the line.
func _pick(gunner: Soldier, seat: int) -> Soldier:
	var lvl := vehicle.level()
	if lvl == null:
		return null
	var muzzle := vehicle.gun_origin(seat)
	var door := seat != int(vehicle.gun_info().get("seat", -1))
	var reach := float(_cfg.get("range_m", 600.0))
	var everyone: Array[Soldier] = []
	for holder: Node in [lvl.players, lvl.ai]:
		for n in holder.get_children():
			var s := n as Soldier
			if s and not s.is_queued_for_deletion() and s.vitals.is_up():
				everyone.append(s)
	var foes: Array = []
	for s in everyone:
		if s.faction == gunner.faction or Person.is_noncombatant(s) or s.faction == Person.FACTION:
			continue
		var ride := Vehicle.ride_of(s)
		if ride and not ride.seat_open(ride.seat_of(s)):
			continue  # shut inside a vehicle: the gun can't see them
		var d := muzzle.distance_to(s.global_position)
		if door and not vehicle.door_arc_ok(seat, s.aim_point() - muzzle):
			continue
		if d <= reach:
			foes.append([d, s])
	foes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var exclude: Array[RID] = [vehicle.get_rid()]
	for f: Array in foes.slice(0, 6):
		var s: Soldier = f[1]
		var aim := s.aim_point()
		var q := PhysicsRayQueryParameters3D.create(muzzle, aim, 1 | Vehicle.LAYER, exclude)
		if not vehicle.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		if _friend_in_line(gunner, everyone, muzzle, aim):
			continue
		if _spotted(gunner, s) < 1.0:
			continue  # not made out yet (Spotting: a man down in cover at range takes a while)
		return s
	return null


## The gunner's awareness of `s` after this look (one check_s of it in sight): it builds over
## Spotting.spot_seconds as SquadAI's does, and goes once he's out of sight a look or two.
func _spotted(gunner: Soldier, s: Soldier) -> float:
	var now := Soldier._now()
	var id := s.get_instance_id()
	var e: Array = _aware.get(id, [0.0, now])
	var gap := now - float(e[1])
	var a := float(e[0]) if gap <= float(_cfg.get("check_s", 0.5)) * 3.0 else 0.0
	if a < 1.0:
		var brain := SquadAI.of(gunner)
		var t := Spotting.spot_seconds(gunner, s, Spotting.preset_of(vehicle), brain._react_combat() if brain and brain.body else 0.5, false, now,
			Spotting.foliage_m(Spotting.scatter_of(vehicle), gunner, s))
		a = 1.0 if t <= 0.0 else minf(a + float(_cfg.get("check_s", 0.5)) / t, 1.0)
	_aware[id] = [a, now]
	return a


func _friend_in_line(gunner: Soldier, everyone: Array[Soldier], from: Vector3, to: Vector3) -> bool:
	var clear := float(_cfg.get("friend_clear_m", 2.5))
	var seg := to - from
	var length := seg.length()
	if length < 0.1:
		return false
	var dir := seg / length
	for s in everyone:
		if s == gunner or s.faction != gunner.faction or Vehicle.ride_of(s) == vehicle:
			continue
		var p := s.global_position + Vector3.UP * 1.0
		var t := clampf((p - from).dot(dir), 0.0, length)
		if t > 1.0 and p.distance_to(from + dir * t) < clear:
			return true
	return false


## The shot is heard: by the enemy's alert in a hot zone (our side firing), by our squad (theirs).
func _noise(gunner: Soldier, at: Vector3) -> void:
	if gunner.faction != &"hostile":
		Alert.server_noise(gunner, at, Alert.SHOT, false)
	else:
		SquadAI.server_heard_shot(gunner, at, false)
