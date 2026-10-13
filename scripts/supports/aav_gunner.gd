class_name AavGunner
extends Node
## An AI gunner on a vehicle's mounted gun (wave 5b, V4; host only): whoever sits in the gun's
## seat (Vehicle.gunner()), if they're AI and up, looks for enemies every check_s (soldiers of
## another side, not civilians, up, out in the open or in an open seat, within range_m and in
## clear sight of the muzzle) and fires bursts at the nearest through Vehicle.server_fire_gun
## (the gun's own rate, spread and belts from the hold), holding fire while a friend stands
## near the line. The support AAV's gunner and an enemy technical's both use it. Numbers in
## data/ground_supports.json "gunner" (Proposed). A child of the vehicle on the host only.

const NODE_NAME := "AIGunner"
## Aim at the chest; a little below for a target lying down.
const LOW_TARGET_M := 0.4

var vehicle: Vehicle
## The soldier being fired at (tests, the session log).
var target: Soldier
## Rounds fired so far (tests).
var fired := 0
var _check := 0.0
var _burst_left := 0
var _pause := 0.0
var _cfg := {}


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
	var gunner := vehicle.gunner()
	if gunner == null or not gunner.is_ai() or not gunner.vitals.is_up() or vehicle.gun_info().is_empty():
		target = null
		return
	_check -= delta
	if _check <= 0.0:
		_check = float(_cfg.get("check_s", 0.5))
		target = _pick(gunner)
	if target == null or not target.vitals.is_up():
		_burst_left = 0
		return
	if _pause > 0.0:
		_pause -= delta
		return
	if _burst_left <= 0:
		var burst: Array = _cfg.get("burst", [4, 9])
		_burst_left = randi_range(int(burst[0]), int(burst[1]))
	var muzzle := _muzzle()
	var aim := target.aim_point() if target.vitals.is_up() else target.body_point() + Vector3.UP * LOW_TARGET_M
	var dir := (aim - muzzle).normalized()
	var spread := deg_to_rad(float(_cfg.get("spread_deg", 0.8)))
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
	dir = (dir + side * randf_range(-1, 1) * tan(spread) + side.cross(dir) * randf_range(-1, 1) * tan(spread)).normalized()
	var shot := vehicle.server_fire_gun(gunner, dir)
	if shot.is_empty():
		if vehicle.gun_info().get("rounds", 0) <= 0:
			target = null  # dry: nothing more to do until the hold is restocked
		return
	fired += 1
	_noise(gunner, muzzle)
	_burst_left -= 1
	if _burst_left <= 0:
		var pause: Array = _cfg.get("pause_s", [0.8, 1.8])
		_pause = randf_range(float(pause[0]), float(pause[1]))


## The gun's muzzle in the world.
func _muzzle() -> Vector3:
	var g: Dictionary = vehicle.spec.get("gun", {})
	return vehicle.global_transform * VehicleSpecs.vec(g.get("at"), Vector3(0, 2, 0))


## The nearest enemy in range, in clear sight of the muzzle, with no friend near the line.
func _pick(gunner: Soldier) -> Soldier:
	var lvl := vehicle.level()
	if lvl == null:
		return null
	var muzzle := _muzzle()
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
		if ride and not bool(ride.seats()[ride.seat_of(s)].get("open", false)):
			continue  # shut inside a vehicle: the gun can't see them
		var d := muzzle.distance_to(s.global_position)
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
		return s
	return null


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
