class_name VehicleSmoke
extends Node
## The smoke grenade dischargers (combined arms A7, cg_brief queue item 2.5; F-249;
## docs/combined_arms.md 2.7.1, 2.2.2, 2.5.2, 2.9.2): the Abrams' M250 (two launchers of six
## tubes) and the Bradley's M257 (two of four), the "Smoke" child of a vehicle whose fx block has
## "dischargers". A salvo fires per_salvo grenades from each side's launcher, thrown range_m out
## at angles_deg off the turret's front (left and right), a screen across the front arc where each
## bursts into a MULTISPECTRAL SmokeCloud (CompoundLevel.server_spawn_smoke): it blocks sight
## (SmokeCloud.blocks), thermal (ThermalView.smoke_blocks) and the laser (VehicleGunnery.
## range_along) for the cloud's life, then clears as any smoke does. A side's module (smoke_l,
## smoke_r) damaged loses half its grenades, destroyed all of them. Reloads come from stowage
## (stowed per side: one full load), reload_s a salvo, stopped, by an able crewman; A8's FOB rearm
## refills the stowage (server_restock) until the smoke_salvo items are stowage of their own.
##
## Who pops it: a player from the crew wheel ("Pop smoke": request_pop), and A9's AI with the
## one call server_pop(by) (on a launch at it, a near miss, a laser warning: 2.13). Host
## authoritative; net_state (the vehicle's StateSync) and the zone save keep the counts. Every
## number is Proposed (data/vehicle_fx.json).

const NODE_NAME := &"Smoke"
## The grenade arcs and bursts this long after the salvo (s).
const FLIGHT_S := 0.9
## Stopped: slower than this (m/s) to reload.
const STOPPED_MPS := 0.5

## Host: a salvo went (the clouds' points).
signal popped(points: Array)

var vehicle: Vehicle
## The dischargers' data (data/vehicle_fx.json "dischargers").
var d: Dictionary = {}
## Grenades in each side's launcher (left, right), and stowed for each side.
var loaded: Array[int] = [0, 0]
var stowed: Array[int] = [0, 0]
## Salvos fired so far (host), and the last salvo's cloud points.
var fired := 0
var last_points: Array = []
## Host clock until the next reloaded salvo is in (0: not reloading), and who reloads.
var reload_until := 0.0
var reload_by: Soldier
var _halved := [false, false]
var _check_left := 0.0
## Replicated: {"r": loaded, "s": stowed, "rl": reload seconds left when published}.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if not _is_host():
			loaded = [int((value.get("r", [0, 0]) as Array)[0]), int((value.get("r", [0, 0]) as Array)[1])]
			stowed = [int((value.get("s", [0, 0]) as Array)[0]), int((value.get("s", [0, 0]) as Array)[1])]


func _init(p_vehicle: Vehicle = null) -> void:
	name = NODE_NAME
	vehicle = p_vehicle
	if vehicle:
		d = VehicleFire.fx_of(vehicle.spec).get("dischargers", {})
		var n := int(d.get("tubes", 0))
		loaded = [n, n]
		stowed = [int(d.get("stowed", 0)), int(d.get("stowed", 0))]
	_publish()


func _ready() -> void:
	set_physics_process(_is_host())


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


## Whether `v` has dischargers.
static func has_dischargers(spec: Dictionary) -> bool:
	return not (VehicleFire.fx_of(spec).get("dischargers", {}) as Dictionary).is_empty()


## The salvos loaded now: on the side with more grenades whose launcher still works.
func salvos() -> int:
	var n := 0
	for side in 2:
		if _side_ok(side):
			n = maxi(n, loaded[side] / per_salvo())
	return n


## Grenades a side throws a salvo.
func per_salvo() -> int:
	return maxi(int(d.get("per_salvo", 1)), 1)


func _side_ok(side: int) -> bool:
	var mods: Array = d.get("modules", [])
	if vehicle == null or vehicle.modules == null or side >= mods.size():
		return true
	var i := vehicle.modules.index_of(String(mods[side]))
	return i < 0 or vehicle.modules.state(String(mods[side])) != VehicleModules.DESTROYED


## Why a salvo can't go now ("" it can).
func can_pop() -> String:
	if vehicle == null or d.is_empty():
		return "No smoke dischargers"
	if vehicle.wrecked:
		return "Wrecked"
	if salvos() <= 0:
		return "No smoke left" if stowed[0] + stowed[1] <= 0 else "Reload the smoke"
	return ""


## Host: a salvo of multispectral smoke (2.5.2's "Pop smoke"; A9's call). `by` who popped it (or
## null). Why not ("" it went).
func server_pop(by: Soldier = null) -> String:
	if not _is_host():
		return "Not the host"
	var why := can_pop()
	if why != "":
		return why
	var lvl := vehicle.level()
	var points: Array = []
	var ats: Array = d.get("at", [])
	var angles: Array = d.get("angles_deg", [20.0])
	var reach := float(d.get("range_m", 30.0))
	var t := vehicle.turret.turret_transform() if vehicle.turret else Transform3D.IDENTITY
	var pivot := vehicle.turret.pivot if vehicle.turret else Vector3.ZERO
	for side in 2:
		if loaded[side] < per_salvo() or not _side_ok(side):
			continue
		loaded[side] -= per_salvo()
		var rest := VehicleSpecs.vec(ats[side] if side < ats.size() else [0, 2, 0], Vector3(0, 2, 0))
		var from_local := t * (rest - pivot) if vehicle.turret else rest
		var from := vehicle.to_global(from_local)
		var centre := vehicle.to_global(pivot)  # (the pattern is laid about the turret's line: the screen meets in front)
		for k in per_salvo():
			var deg := float(angles[k % angles.size()])
			var dir_local := (t.basis * Vector3.FORWARD).rotated(Vector3.UP, deg_to_rad(deg) * (1.0 if side == 0 else -1.0))
			var flat := (vehicle.global_basis * dir_local)
			flat.y = 0.0
			var land := _ground(centre + flat.normalized() * reach)
			points.append(land)
			VehicleFx.server_event(vehicle, "smoke", {"from": from, "to": land})
	if points.is_empty():
		return "No smoke left"
	fired += 1
	last_points = points
	Sfx.server_play(&"smoke_discharge", vehicle.global_position + Vector3.UP * 2.0)
	if lvl:
		get_tree().create_timer(FLIGHT_S).timeout.connect(_burst_clouds.bind(points))
	if by and by.is_ai():
		var callouts := Callouts.of(vehicle)
		if callouts:
			callouts.say(by, &"smoke_out", "Popping smoke!")
	print("[smoke] %s popped smoke (%d | %d left)" % [vehicle.display_name(), loaded[0], loaded[1]])
	_publish()
	popped.emit(points)
	return ""


## Host: the salvo's grenades burst into their clouds where they landed.
func _burst_clouds(points: Array) -> void:
	var lvl := vehicle.level() if vehicle and vehicle.is_inside_tree() else null
	if lvl:
		for p: Vector3 in points:
			lvl.server_spawn_smoke(p, ThermalView.MULTISPECTRAL)


## Clients: a player in a crew seat asks for a salvo (the crew wheel's "Pop smoke").
@rpc("any_peer", "call_local", "reliable")
func request_pop() -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender() if vehicle else null
	if s == null or vehicle.seat_of(s) < 0 or vehicle.is_rider(vehicle.seat_of(s)):
		return
	var why := server_pop(s)
	if why != "":
		vehicle._tell(s, why)


## Host: `by` (an able crewman, the vehicle stopped) reloads the launchers from stowage, reload_s a
## salvo, until they're full or the stowage is empty. Why not ("" started).
func server_reload(by: Soldier) -> String:
	if not _is_host() or d.is_empty():
		return "No smoke dischargers"
	if by == null or not by.vitals.is_up() or vehicle.seat_of(by) < 0:
		return "Nobody to reload"
	if vehicle.linear_velocity.length() > STOPPED_MPS:
		return "Stop first"
	if not _wants_reload():
		return "Full" if stowed[0] + stowed[1] > 0 else "No smoke stowed"
	reload_by = by
	reload_until = Soldier._now() + float(d.get("reload_s", 10.0))
	_publish()
	return ""


func _wants_reload() -> bool:
	var full := int(d.get("tubes", 0))
	for side in 2:
		if _side_ok(side) and loaded[side] < full and stowed[side] > 0:
			return true
	return false


## Host (A8's FOB rearm): the stowage full again, and the launchers.
func server_restock() -> void:
	var n := int(d.get("tubes", 0))
	loaded = [n, n]
	stowed = [int(d.get("stowed", 0)), int(d.get("stowed", 0))]
	_halved = [false, false]
	reload_until = 0.0
	_publish()


func _physics_process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or vehicle == null or d.is_empty():
		return
	_check_left = 0.25
	_damage_check()
	if reload_until <= 0.0:
		return
	var who := reload_by if is_instance_valid(reload_by) else null
	if who == null or not who.vitals.is_up() or vehicle.seat_of(who) < 0 or vehicle.linear_velocity.length() > STOPPED_MPS or vehicle.wrecked:
		reload_until = 0.0
		reload_by = null
		_publish()
		return
	if Soldier._now() < reload_until:
		return
	var full := int(d.get("tubes", 0))
	for side in 2:
		if _side_ok(side) and loaded[side] < full and stowed[side] > 0:
			var n := mini(mini(per_salvo(), full - loaded[side]), stowed[side])
			loaded[side] += n
			stowed[side] -= n
	reload_until = Soldier._now() + float(d.get("reload_s", 10.0)) if _wants_reload() else 0.0
	if reload_until <= 0.0:
		reload_by = null
	_publish()


## A side's module damaged: half its grenades lost (once); destroyed: all (2.2.2).
func _damage_check() -> void:
	var mods: Array = d.get("modules", [])
	if vehicle.modules == null:
		return
	var changed := false
	for side in mini(2, mods.size()):
		var st := vehicle.modules.state(String(mods[side])) if vehicle.modules.index_of(String(mods[side])) >= 0 else VehicleModules.WORKING
		if st == VehicleModules.DESTROYED and loaded[side] > 0:
			loaded[side] = 0
			changed = true
		elif st == VehicleModules.DAMAGED and not _halved[side]:
			_halved[side] = true
			loaded[side] = loaded[side] / 2
			changed = true
		elif st == VehicleModules.WORKING and _halved[side]:
			_halved[side] = false  # repaired: the next half lost is a new one
	if changed:
		_publish()


## The HUD's line ("SMOKE 6 | 6, 12 stowed" as 2.12.1's panel has it), for crew seats.
func readout_parts(seat: int) -> Array[Dictionary]:
	if d.is_empty() or seat < 0 or vehicle.is_rider(seat):
		return []
	var left := loaded[0] if _side_ok(0) else 0
	var right := loaded[1] if _side_ok(1) else 0
	var text := "SMOKE %d | %d" % [left, right]
	if stowed[0] + stowed[1] > 0:
		text += ", %d stowed" % (stowed[0] + stowed[1])
	if float(net_state.get("rl", 0.0)) > 0.0 or reload_until > 0.0:
		text += ", reloading"
	return [{"text": text, "style": &"warn" if left + right == 0 else &""}]


func _publish() -> void:
	if not _is_host():
		return
	net_state = {"r": [loaded[0], loaded[1]], "s": [stowed[0], stowed[1]], "rl": snappedf(maxf(reload_until - Soldier._now(), 0.0), 0.5) if reload_until > 0.0 else 0.0}


func to_save() -> Dictionary:
	return {"ready": [loaded[0], loaded[1]], "stowed": [stowed[0], stowed[1]], "halved": _halved.duplicate()}


func from_save(data: Dictionary) -> void:
	var r: Array = data.get("ready", [])
	var s: Array = data.get("stowed", [])
	if r.size() == 2:
		loaded = [maxi(int(r[0]), 0), maxi(int(r[1]), 0)]
	if s.size() == 2:
		stowed = [maxi(int(s[0]), 0), maxi(int(s[1]), 0)]
	var h: Array = data.get("halved", [])
	if h.size() == 2:
		_halved = [bool(h[0]), bool(h[1])]
	_publish()


## A point on the ground below `p` (the world, layer 1), or `p` itself.
func _ground(p: Vector3) -> Vector3:
	if vehicle == null or not vehicle.is_inside_tree():
		return p
	var space := vehicle.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3) + Vector3.UP * 0.1 if not hit.is_empty() else p
