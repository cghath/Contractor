class_name EnemyDrones
extends Node
## Wave 6: the enemy's recon drones and the jammer. In a hot zone, once the enemy is alerted
## (Pressure tier MIN_TIER or more), its HQ (else any site) sends a small quadcopter up every
## GAP_S: ALT_M over the ground, it flies to where the enemy last heard of the squad (Alert's last
## known position) and orbits there; once it has any of the squad in sight (within SEE_M, a clear
## line from its camera: a roof or a wall in the way hides them) it follows them, for FIX_KEEP_S
## after it last saw one. Every REPORT_S it sees any of them it reports them to the enemy's net
## (Alert._receive, a "contact": the last known position moves there, QRFs and hunters get a fresh
## fix). It used to fly straight to the squad wherever it was and see through roofs (F-362). Its
## battery lasts ENDURANCE_S, then it goes home.
##
## Dealt with by shooting it (HITS rounds bring it down: Ballistics calls its body's "on_bullet"
## meta) or with a jammer (data/items.json "jammer", carried by any of the squad up within JAM_M:
## its link is cut and it falls). Numbers Proposed.
##
## Every peer has this node (ZoneLevel._ready): the host flies them and sends where each is,
## every SYNC_S; the others draw them there.

const NODE_NAME := "EnemyDrones"
const JAMMER := &"jammer"
const MIN_TIER := 1
const GAP_S := 300.0
const FIRST_S := 60.0
const ALT_M := 60.0
const ORBIT_M := 70.0
const SPEED_MS := 14.0
const SEE_M := 160.0
const REPORT_S := 20.0
const ENDURANCE_S := 240.0
const JAM_M := 150.0
const HITS := 2
const FALL_MS := 12.0
const SYNC_S := 0.2
## How often (s) a drone looks for the squad, and how long it keeps to where it last saw one.
const LOOK_S := 1.0
const FIX_KEEP_S := 30.0

## Tests and dev tools: false stops launches (server_launch still works).
static var enabled := true
## Host: id -> {"pos": Vector3, "home": Vector3, "launched", "hits", "state" ("out", "home",
## "falling", "gone"), "next_report", "seen_once", "body": StaticBody3D, and once it has looked:
## "look_in", "seen" (the squad it has in sight), "fix" (where it last saw them), "fix_age"}.
var drones := {}
## Every peer: id -> its visual.
var _shown := {}
var _next_id := 1
var _next_launch := INF
var _sync := 0.0


static func of(from: Node) -> EnemyDrones:
	var level := CompoundLevel.current(from)
	return level.get_node_or_null(NODE_NAME) as EnemyDrones if level else null


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	_next_launch = Soldier._now() + FIRST_S


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_host_tick(delta)


func _host_tick(delta: float) -> void:
	var level := CompoundLevel.current(self)
	if level == null:
		return
	var pressure := Pressure.of(level)
	if enabled and Supports.is_hot_zone(level) and pressure and pressure.tier() >= MIN_TIER and Soldier._now() >= _next_launch:
		_next_launch = Soldier._now() + GAP_S
		server_launch()
	for id: int in drones.keys():
		server_fly(id, delta)
	_sync -= delta
	if _sync <= 0.0 and not drones.is_empty():
		_sync = SYNC_S
		var out := {}
		for id: int in drones:
			out[id] = [drones[id].pos, String(drones[id].state)]
		_client_set.rpc(out)
		for id: int in drones.keys():
			if String(drones[id].state) == "gone":
				drones.erase(id)


## Host: a drone goes up from the HQ (else the first site). Returns its id (0: nowhere to launch from).
func server_launch(from := Vector3.INF) -> int:
	var level := CompoundLevel.current(self)
	if level == null:
		return 0
	if not from.is_finite():
		var mods: Array = level.call(&"modules") if level.has_method(&"modules") else []
		for m: ZoneModule in mods:
			if m.type == "hq" or not from.is_finite():
				from = m.global_position
				if m.type == "hq":
					break
	if not from.is_finite():
		return 0
	var id := _next_id
	_next_id += 1
	var body := StaticBody3D.new()  # what a round hits (Ballistics: "on_bullet")
	body.name = "DroneBody_%d" % id
	body.collision_layer = Vehicle.LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	body.add_child(shape)
	body.set_meta(&"on_bullet", server_hit.bind(id))
	add_child(body)
	var at := _air(from)
	body.global_position = at
	drones[id] = {"pos": at, "home": at, "launched": Soldier._now(), "hits": 0, "state": "out", "next_report": 0.0, "seen_once": false, "body": body}
	print("[drones] drone %d up from (%.0f, %.0f)" % [id, from.x, from.z])
	return id


## Host: drone `id` flies `delta` seconds: to where it saw the squad, else to the enemy's last
## known position, and round it; home when its battery's low, down when jammed or shot.
func server_fly(id: int, delta: float) -> void:
	var d: Dictionary = drones[id]
	var level := CompoundLevel.current(self)
	var pos: Vector3 = d.pos
	match String(d.state):
		"falling":
			var ground: Vector3 = level.call(&"ground_point", pos)
			pos.y -= FALL_MS * delta
			if pos.y <= ground.y + 0.3:
				pos = ground
				d.state = "gone"
				_free_body(d)
				print("[drones] drone %d crashed at (%.0f, %.0f)" % [id, pos.x, pos.z])
		"out", "home":
			var squad := _squad(level)
			if String(d.state) == "out" and Soldier._now() - float(d.launched) >= ENDURANCE_S:
				d.state = "home"
			if _jammed(pos, squad):
				d.state = "falling"
				Contracts._notify_all("Jammer: the drone's link is cut. It's coming down.")
			var goal: Vector3 = d.home
			if String(d.state) == "out":
				_search(d, pos, squad, delta)
				var c := _search_point(d, level)
				if c.is_finite():
					var a := Soldier._now() * SPEED_MS / ORBIT_M + id
					goal = _air(c + Vector3(cos(a), 0.0, sin(a)) * ORBIT_M)
			var to := goal - pos
			pos += to.normalized() * minf(to.length(), SPEED_MS * delta) if to.length() > 0.01 else Vector3.ZERO
			if String(d.state) == "home" and pos.distance_to(d.home) < 3.0:
				d.state = "gone"
				_free_body(d)
			elif String(d.state) == "out":
				_look(id, d, pos, level)
	d.pos = pos
	if is_instance_valid(d.get("body")):
		(d.body as Node3D).global_position = pos


## Every LOOK_S: which of `squad` drone `d` at `pos` has in sight ("seen"), and where it saw
## them ("fix", kept FIX_KEEP_S).
func _search(d: Dictionary, pos: Vector3, squad: Array[Soldier], delta: float) -> void:
	d.fix_age = float(d.get("fix_age", INF)) + delta
	d.look_in = float(d.get("look_in", 0.0)) - delta
	if float(d.look_in) > 0.0:
		return
	d.look_in = LOOK_S
	var seen: Array[Soldier] = []
	var sum := Vector3.ZERO
	for s: Soldier in squad:
		if Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= SEE_M 				and Throwables.clear_line(s.get_world_3d(), pos, s.aim_point()):
			seen.append(s)
			sum += s.global_position
	d.seen = seen
	if not seen.is_empty():
		d.fix = sum / seen.size()
		d.fix_age = 0.0


## Where drone `d` searches: where it last saw the squad (FIX_KEEP_S), else the enemy's last
## known position, else nowhere (Vector3.INF: it hangs over home).
func _search_point(d: Dictionary, level: Node) -> Vector3:
	if d.has("fix") and float(d.get("fix_age", INF)) <= FIX_KEEP_S:
		return d.fix
	var alert := Alert.of(level)
	var known := alert.last_known() if alert else {}
	return known.pos if not known.is_empty() else Vector3.INF


func _look(id: int, d: Dictionary, pos: Vector3, level: Node) -> void:
	if Soldier._now() < float(d.next_report):
		return
	for v: Variant in d.get("seen", []):
		var s: Soldier = v as Soldier if is_instance_valid(v) else null
		if s and s.vitals.is_up():
			d.next_report = Soldier._now() + REPORT_S
			var alert := Alert.of(level)
			if alert:
				var seen := alert._seen_at(s.global_position, null, pos)
				alert._receive({"kind": &"contact", "pos": s.global_position, "area": alert.area_of(s.global_position), "by": "drone",
					"seen": int(seen.seen), "exo": int(seen.exo)})
			if not bool(d.seen_once):
				d.seen_once = true
				Contracts._notify_all("Drone overhead! It's calling in our position. Shoot it down or jam it.")
			print("[drones] drone %d reports the squad at (%.0f, %.0f)" % [id, s.global_position.x, s.global_position.z])
			return


## Host: a round hit drone `id`.
func server_hit(_pos: Vector3, _shooter: Variant, id: int) -> void:
	var d: Dictionary = drones.get(id, {})
	if d.is_empty() or String(d.state) not in ["out", "home"]:
		return
	d.hits = int(d.hits) + 1
	if int(d.hits) >= HITS:
		d.state = "falling"
		Contracts._notify_all("Drone down!")


## Whether any of `squad` carries a working jammer within JAM_M of `pos`.
static func _jammed(pos: Vector3, squad: Array[Soldier]) -> bool:
	for s: Soldier in squad:
		if s.global_position.distance_to(pos) <= JAM_M and (s.inventory.count_of(JAMMER) > 0 or s.inventory.slots.values().has(JAMMER)):
			return true
	return false


static func _squad(level: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s: Soldier in MapNodes.players(level) + MapNodes.squad_ai(level):
		if s.vitals.is_up():
			out.append(s)
	return out


func _air(at: Vector3) -> Vector3:
	var level := CompoundLevel.current(self)
	var g: Vector3 = level.call(&"ground_point", at) if level else at
	return g + Vector3.UP * ALT_M


func _free_body(d: Dictionary) -> void:
	if is_instance_valid(d.get("body")):
		(d.body as Node).queue_free()
	d.body = null


# --- Every peer: what's drawn -------------------------------------------------------------

@rpc("authority", "call_local", "unreliable_ordered")
func _client_set(list: Dictionary) -> void:
	for id: int in list:
		var pos: Vector3 = list[id][0]
		var state := String(list[id][1])
		var node: Node3D = _shown.get(id)
		if state == "gone":
			if node and is_instance_valid(node):
				node.queue_free()
			_shown.erase(id)
			continue
		if node == null or not is_instance_valid(node):
			node = make_visual()
			add_child(node)
			_shown[id] = node
		node.global_position = pos
	for id: int in _shown.keys():
		if not list.has(id):
			var gone: Node = _shown[id]
			if is_instance_valid(gone):
				gone.queue_free()
			_shown.erase(id)


## A small quadcopter: a body, four arms and rotors.
static func make_visual() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.2)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.1, 0.3)
	box.material = mat
	body.mesh = box
	root.add_child(body)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.36, 0.03, 0.04)
		am.material = mat
		arm.mesh = am
		arm.position = Vector3(cos(a), 0.0, sin(a)) * 0.2
		arm.rotation.y = -a
		root.add_child(arm)
		var rotor := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.11
		rm.bottom_radius = 0.11
		rm.height = 0.01
		rm.material = mat
		rotor.mesh = rm
		rotor.position = Vector3(cos(a), 0.06, sin(a)) * 0.38
		root.add_child(rotor)
	return root
