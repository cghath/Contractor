class_name VehicleQrf
extends Node
## Enemy QRFs in technicals (wave 5b, V4; hot zones, Captain's hook): when EnemyResponse sends
## a QRF wave from a QRF base (Reinforcements.server_send at the base's gate), server_mount()
## may put it in an enemy technical (VehicleArt's technicals, "hostile"): one parked just outside
## the gate, the wave's men seated (driver, the gunner on the DShK, the rest in the cab and the
## bed), driven by V1's AI driver toward where the wave is sent. The men get out "dismount_m"
## short of it, or sooner when it's hit, stuck or slow to get there, and go on as the wave on
## foot (their brains wake with the wave's orders); the gunner stays on the gun (AavGunner) while
## the technical can still fire. A wave bigger than "max_vehicles" technicals hold walks the
## rest; with no room to park at the gate, or under "min_drive_m" to go, the wave walks.
##
## Whether a launch rides is decided from the zone's seed, the base and the launch count
## against "share", so the same zone plays the same. Numbers in data/ground_supports.json
## "vehicle_qrf" (Proposed). Host only; the technicals replicate as any vehicle. One node,
## "VehicleQrf", added to the level the first time (host).

const NODE_NAME := "VehicleQrf"
const TICK_S := 0.25
## Close to the dismount point this much, the men get out.
const ARRIVE_M := 15.0
## Tests: force (1) or forbid (0) vehicle QRFs; -1 uses data's share.
static var share_override := -1.0

## Host: [{"vehicle", "soldiers", "aim", "dismount" (point), "started", "progress_at",
## "progress_pos", "hit", "out" (dismounted)}].
var convoys: Array = []
## Host: QRF launches seen (the roll's count).
var launches := 0
var _tick := 0.0
var _cfg := {}


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	_cfg = AavSupport.data().get("vehicle_qrf", {})


## Host (EnemyResponse._launch_qrf): `soldiers` (a QRF wave just sent from `gate`, the gate of
## QRF base `base`) may ride a technical toward `aim`. Returns whether any of them do.
static func server_mount(level: Node, base: Node3D, gate: Vector3, aim: Vector3, soldiers: Array) -> bool:
	if level == null or not level.is_inside_tree() or not level.multiplayer.is_server() or soldiers.is_empty() or not gate.is_finite():
		return false
	var node := level.get_node_or_null(NodePath(NODE_NAME)) as VehicleQrf
	if node == null:
		node = VehicleQrf.new()
		level.add_child(node)
	return node._mount(base, gate, aim, soldiers)


## The level's node, or null (none sent yet).
static func of(from: Node) -> VehicleQrf:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as VehicleQrf if lvl else null


func _mount(base: Node3D, gate: Vector3, aim: Vector3, soldiers: Array) -> bool:
	launches += 1
	var lvl := get_parent()
	var def: Variant = lvl.get(&"def")
	var zone_seed := int((def as Dictionary).get("seed", 0)) if def is Dictionary else 0
	var share := share_override if share_override >= 0.0 else float(_cfg.get("share", 0.5))
	var base_id := String(base.get(&"module_id")) if base and "module_id" in base else String(base.name) if base else ""
	var roll := float(absi(hash([zone_seed, base_id, launches])) % 1000) / 1000.0
	if roll >= share:
		return false
	var flat := Vector3(aim.x - gate.x, 0.0, aim.z - gate.z)
	if flat.length() < float(_cfg.get("min_drive_m", 250.0)):
		return false
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null:
		return false
	var men: Array = soldiers.filter(func(s: Variant) -> bool: return is_instance_valid(s) and (s as Soldier).vitals.is_up() and Vehicle.ride_of(s as Soldier) == null)
	var models: Array = _cfg.get("models", ["technical_dshk"])
	var toward := flat.normalized()
	var out := Vector3(gate.x - base.global_position.x, 0.0, gate.z - base.global_position.z).normalized() if base else -toward
	if out.length() < 0.5:
		out = toward
	var dismount_m := float(_cfg.get("dismount_m", 180.0))
	var drop := aim - toward * minf(dismount_m, flat.length() * 0.5)
	if lvl.has_method(&"ground_point"):
		drop = lvl.call(&"ground_point", drop)
	var sent := 0
	for k in int(_cfg.get("max_vehicles", 2)):
		if men.is_empty():
			break
		var model := String(models[k % models.size()])
		var spot: Variant = _clear_spot(lvl, model, gate, out, k)
		if spot == null:
			break
		var v := layer.server_spawn(model, Transform3D(Basis.looking_at(toward, Vector3.UP), spot), String(_cfg.get("scheme", "")), &"hostile", "")
		if v == null:
			break
		v.set_meta(&"qrf", "inbound")
		v.set_meta(&"no_save", true)
		for c: Array in _cfg.get("cargo", []):
			v.cargo_hold.take(StringName(String(c[0])), int(c[1]) if c.size() > 1 else 1)
		var riders: Array = []
		for i in _seat_order(v):
			if men.is_empty():
				break
			var s: Soldier = men.pop_front()
			if v.server_enter(s, i):
				riders.append(s)
		AavGunner.attach(v)
		v.damaged.connect(_on_hit.bind(v))
		v.server_drive_to(drop, float(_cfg.get("speed_kmh", 55.0)))
		convoys.append({"vehicle": v, "soldiers": riders, "aim": aim, "dismount": drop, "started": Soldier._now(),
			"progress_at": Soldier._now(), "progress_pos": v.global_position, "hit": false, "out": false})
		sent += 1
		print("[vehicle qrf] %s from %s with %d men toward (%.0f, %.0f)" % [model, base_id, riders.size(), aim.x, aim.z])
	return sent > 0


## Seats in the order the QRF fills them: the driver, the gun, then the rest.
static func _seat_order(v: Vehicle) -> Array:
	var gun := int(v.spec.get("gun", {}).get("seat", -1)) if (v.spec.get("gun", {}) as Dictionary).has("weapon") else -1
	var order: Array = []
	for i in v.seat_count():
		if v.seat_kind(i) == Vehicle.DRIVER:
			order.append(i)
	if gun >= 0:
		order.append(gun)
	for i in v.seat_count():
		if not i in order and v.seat_kind(i) != Vehicle.PILOT:
			order.append(i)
	return order


## A spot just outside the gate with room for `model` (the `index`th vehicle), on the ground,
## or null.
func _clear_spot(lvl: Node, model: String, gate: Vector3, out: Vector3, index: int) -> Variant:
	var size := VehicleArt.size_m(model)
	var across := out.cross(Vector3.UP)
	var box := BoxShape3D.new()
	box.size = size + Vector3(0.6, 0.0, 0.6)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | Vehicle.LAYER | Soldier.BODY_LAYER
	var space := (lvl as Node3D).get_world_3d().direct_space_state
	for d: float in [9.0, 15.0, 21.0, 27.0]:
		for w: float in [0.0, -7.0, 7.0, -14.0, 14.0]:
			var p := gate + out * (d + index * 7.0) + across * w
			if lvl.has_method(&"ground_point"):
				p = lvl.call(&"ground_point", p)
			q.transform = Transform3D(Basis.looking_at(out, Vector3.UP), p + Vector3.UP * (size.y * 0.5 + 0.4))
			if space.intersect_shape(q, 1).is_empty():
				return p + Vector3.UP * 0.2
	return null


func _on_hit(_zone: StringName, _hit: Dictionary, v: Vehicle) -> void:
	for c: Dictionary in convoys:
		if c.vehicle == v:
			c.hit = true


func _physics_process(delta: float) -> void:
	if convoys.is_empty() or not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	var now := Soldier._now()
	for c: Dictionary in convoys.duplicate():
		var v: Vehicle = c.vehicle if is_instance_valid(c.vehicle) else null
		if v == null or v.is_queued_for_deletion() or v.wrecked:
			convoys.erase(c)
			continue
		if c.out:
			if v.driver() == null and is_instance_valid(v.ai) and v.ai.active:
				v.server_stop()  # nobody at the wheel
			continue
		if v.driver() == null or not v.driver().vitals.is_up():
			_dismount(c, v, "the driver is down")
			continue
		var p := v.global_position
		if p.distance_to(c.progress_pos) > 3.0:
			c.progress_pos = p
			c.progress_at = now
		var why := ""
		if Vector2(p.x - c.dismount.x, p.z - c.dismount.z).length() <= ARRIVE_M or (is_instance_valid(v.ai) and not v.ai.active):
			why = "there"
		elif c.hit or v.is_burning():
			why = "hit"
		elif now - float(c.progress_at) > float(_cfg.get("stuck_s", 8.0)):
			why = "stuck"
		elif now - float(c.started) > float(_cfg.get("timeout_s", 240.0)):
			why = "too long"
		if why != "":
			_dismount(c, v, why)


## Everyone out but the gunner (who stays on a gun that can fire, unless it burns); they go on
## as their wave.
func _dismount(c: Dictionary, v: Vehicle, why: String) -> void:
	c.out = true
	v.set_meta(&"qrf", "dismounted")
	v.server_stop()
	var keep := v.gunner() if not v.is_burning() and not v.gun_info().is_empty() and int(v.gun_info().get("rounds", 0)) > 0 else null
	for s: Soldier in v.occupants():
		if s != keep and s.vitals.is_up():
			v.server_exit(s)
	print("[vehicle qrf] %s dismounts (%s)" % [v.vehicle_id, why])
