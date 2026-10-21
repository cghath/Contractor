class_name UavSupport
extends Node
## The recon UAV (the Captain's list, 2026-10-20: "player ... UAV calls"): a loitering drone the
## squad calls from Support > Fire support > Recon UAV ("support:uav:marker|here|me|home"). It
## flies in from where the supports come from (Supports.origin_for), circles the point it was
## sent to for loiter_s (data/fire_support.json "uav", Proposed numbers) and flies home. While it
## circles, its camera watches the ground within sensor_m of the point: a hostile in its sight is
## spotted over time, by the same things that hide a man from the enemy's eyes (Spotting's factors
## for stance, movement, camo against the zone, foliage in the way, the weather; it sees in thermal,
## so the night hides nobody), and once spotted he's tagged for the squad through EnemyTags (the red
## marks, the map) every tag_every_s while it still sees him. No new AI: what it reports goes where
## the rebels' lookouts' reports go. The caller (any player) opens its top-down feed (UavFeed).
##
## Storms ground it (Supports.can_fly: DayNight.grounds_aircraft): a call is refused, and one up
## when the weather turns flies home. It can be shot down: `hits` rounds (Ballistics' "on_bullet"
## on its body, as the enemy's drones), or a manned hostile AA technical (aa_models) within
## aa_reach_m with a clear line to it, which has aa_hit_chance every aa_every_s (the enemy's AI
## doesn't aim at it: docs/audits/followups.md F-150). Down or home, cooldown_s before the next.
## Paid like a fire mission's rounds (FireSupport.server_pay), gated the same way (availability).
##
## One node, "UavSupport", in every level (FireSupport.install). The host flies it and sends its
## position every SYNC_S; every peer draws it (make_visual) and keeps `shown` for the feed.
## Test hooks (host): server_advance(seconds), drone, server_hit().

const NODE_NAME := "UavSupport"
const SYNC_S := 0.2
const LOOK_S := 0.5
const FALL_MS := 25.0
## A spotted man stays "aware" this long out of sight (Spotting.FADE_S's idea, shorter: a camera).
const FADE_S := 8.0

## Host: the drone up, or {}: {"pos", "centre", "home", "state" ("inbound", "station", "home",
## "falling", "gone"), "until" (FireSupport.now() it leaves), "hits", "by", "aware": {name: 0..1},
## "next_tag": {name: now()}, "tagged": {name: true}, "body", "next_aa"}.
var drone := {}
## Every peer: {"pos", "centre", "state", "left" (s on station)}, from the host ({} with none up).
var shown := {}
var _visual: Node3D
var _look := 0.0
var _sync := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	_rng.randomize()


static func of(from: Node) -> UavSupport:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as UavSupport if lvl else null


func level() -> CompoundLevel:
	return get_parent() as CompoundLevel


func spec() -> Dictionary:
	return FireMission.uav()


func is_up() -> bool:
	return not drone.is_empty() and String(drone.state) in ["inbound", "station", "home"]


func cooldown_left() -> float:
	var fs := FireSupport.of(self)
	return maxf(float(fs.store().get("uav_cooldown", 0.0)) - FireSupport.now(), 0.0) if fs else 0.0


# --- Calls (host) -------------------------------------------------------------------------------

## Host: `caller` sends the UAV over `arg` ("marker", "here", "me") or home ("home"). A call
## while one's up moves its orbit, free.
func server_call(caller: Soldier, arg: String, point: Vector3) -> String:
	if not multiplayer.is_server() or caller == null:
		return "No UAV here"
	var s := spec()
	var fs := FireSupport.of(self)
	if arg == "home":
		if not is_up():
			return "No UAV up"
		_go_home("Heading home.")
		return ""
	var where := {}
	match arg.get_slice(":", 0):
		"me", "":
			where = {"pos": caller.global_position}
		"here":
			where = {"pos": point} if point.is_finite() else {"why": "Look at the spot (binoculars reach further)"}
		"marker":
			var heli := HeliSupports.of(self)
			var marker: Variant = heli.newest_marker(caller) if heli else null
			where = {"pos": Vector3((marker as Vector2).x, 0.0, (marker as Vector2).y)} if marker != null else {"why": "Put a marker on the map first (M, double-click)"}
		_:
			return "Say where: my map marker, there, or over us"
	if where.has("why"):
		return String(where.why)
	var at := _ground(where.pos)
	if is_up():
		drone.centre = at
		if String(drone.state) == "home":
			drone.state = "inbound"
		fs.radio_uav("Moving to grid %s." % FireMission.grid(at, level().map_area()))
		return ""
	var why := fs.availability(s, String(s.name)) if fs else "No UAV here"
	if why != "":
		return why
	if not Supports.can_fly(level()):
		return "The UAV is grounded: the weather won't let it fly"
	if cooldown_left() > 0.0:
		return "The UAV can go up again in %d s" % ceili(cooldown_left())
	if not FireSupport.server_pay(Prices.support_price(String(s.price)), "recon UAV"):
		return "Can't pay for the UAV ($%s)" % DebriefCalc.money(Prices.support_price(String(s.price)))
	var from := Supports.origin_for(level(), &"fob", at, float(s.alt_m)).origin
	var home := _air(from)
	var body := StaticBody3D.new()  # what a round hits (Ballistics: "on_bullet"), as the enemy's drones
	body.name = "UavBody"
	body.collision_layer = Vehicle.LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.6, 2.4)  # wingspan, fuselage
	shape.shape = box
	body.add_child(shape)
	body.set_meta(&"on_bullet", func(_pos: Vector3, _shooter: Variant) -> void: server_hit())
	add_child(body)
	body.global_position = home
	drone = {"pos": home, "centre": at, "home": home, "state": "inbound", "until": INF, "hits": 0, "by": caller, "aware": {}, "next_tag": {},
		"tagged": {}, "body": body, "next_aa": FireSupport.now() + float(s.get("aa_every_s", 5.0)), "angle": 0.0}
	SessionLog.note("uav: %s sent it to (%.0f, %.0f)" % [caller.name, at.x, at.z])
	fs.radio_uav("On the way to grid %s, %d minutes on station." % [FireMission.grid(at, level().map_area()), roundi(float(s.loiter_s) / 60.0)])
	_send()
	return ""


## Host: a round (or the AA) hit it.
func server_hit() -> void:
	if not is_up():
		return
	drone.hits = int(drone.hits) + 1
	if int(drone.hits) >= int(spec().get("hits", 3)):
		drone.state = "falling"
		var fs := FireSupport.of(self)
		if fs:
			fs.radio_uav("We've lost the UAV: it's going down.")
			fs.store()["uav_cooldown"] = FireSupport.now() + float(spec().cooldown_s)


func _go_home(why: String) -> void:
	if not is_up():
		return
	drone.state = "home"
	var fs := FireSupport.of(self)
	if fs:
		fs.radio_uav(why)
		fs.store()["uav_cooldown"] = FireSupport.now() + float(spec().cooldown_s)


# --- Flight (host) ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if drone.is_empty() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_fly(delta)


## Host (tests): `seconds` of flight, with the fire support clock moved on with it.
func server_advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not drone.is_empty():
		var dt := minf(left, 0.25)
		left -= dt
		FireSupport.offset_s += dt
		_fly(dt, true)


func _fly(delta: float, force_look := false) -> void:
	var s := spec()
	var pos: Vector3 = drone.pos
	var t := FireSupport.now()
	match String(drone.state):
		"falling":
			var ground := _ground(pos)
			pos.y -= FALL_MS * delta
			pos += Vector3(cos(float(drone.angle)), 0.0, sin(float(drone.angle))) * float(s.speed_ms) * 0.5 * delta
			if pos.y <= ground.y + 0.5:
				pos = ground
				_gone("crashed")
		"inbound", "station", "home":
			if String(drone.state) != "home" and not Supports.can_fly(level()):
				_go_home("Weather's closing in: heading home.")
			if String(drone.state) == "station" and t >= float(drone.until):
				_go_home("Off station: heading home.")
			var goal: Vector3 = drone.home
			var centre: Vector3 = drone.centre
			var orbit := float(s.orbit_m)
			if String(drone.state) != "home":
				var off := Vector2(pos.x - centre.x, pos.z - centre.z)
				if String(drone.state) == "inbound" and off.length() <= orbit * 1.15:
					drone.state = "station"
					drone.until = t + float(s.loiter_s)
					var fs := FireSupport.of(self)
					if fs:
						fs.radio_uav("On station over grid %s. Feed's up (Support > Fire support > Recon UAV)." % FireMission.grid(centre, level().map_area()))
				# Fly a circle round the centre: aim a little ahead on it.
				var a := atan2(off.y, off.x) + float(s.speed_ms) / orbit * 1.5
				goal = _air(centre + Vector3(cos(a), 0.0, sin(a)) * orbit)
			var to := goal - pos
			var step := float(s.speed_ms) * delta
			if to.length() > 0.01:
				drone.angle = atan2(to.z, to.x)
				pos += to.normalized() * minf(to.length(), step)
			if String(drone.state) == "home" and pos.distance_to(drone.home) < step * 2.0 + 1.0:
				_gone("home")
	if drone.is_empty():
		return
	drone.pos = pos
	if is_instance_valid(drone.get("body")):
		(drone.body as Node3D).global_position = pos
	_look -= delta
	if String(drone.state) == "station" and (_look <= 0.0 or force_look):
		_look = LOOK_S
		_watch(LOOK_S if not force_look else delta)
		_aa(t)
	_sync -= delta
	if _sync <= 0.0:
		_sync = SYNC_S
		_send()


func _gone(how: String) -> void:
	if is_instance_valid(drone.get("body")):
		(drone.body as Node).queue_free()
	SessionLog.note("uav: %s" % how)
	drone = {}
	_send()


func _ground(p: Vector3) -> Vector3:
	var lvl := level()
	return lvl.ground_point(Vector3(p.x, 0.0, p.z)) if lvl else Vector3(p.x, 0.0, p.z)


func _air(p: Vector3) -> Vector3:
	return _ground(p) + Vector3.UP * float(spec().get("alt_m", 280.0))


# --- What it sees (host) ------------------------------------------------------------------------

## Host: `dt` seconds of watching: every hostile up within sensor_m of the centre it can see gains
## awareness by Spotting's factors; at full, he's tagged (EnemyTags) every tag_every_s.
func _watch(dt: float) -> void:
	var s := spec()
	var centre: Vector3 = drone.centre
	var eye: Vector3 = drone.pos
	var tags := EnemyTags.of(self)
	var scatter := Spotting.scatter_of(self)
	var preset := Spotting.preset_of(self)
	var aware: Dictionary = drone.aware
	var seen_now := {}
	var t := FireSupport.now()
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var e := n as Soldier
		if e == null or e.faction != &"hostile" or e.is_queued_for_deletion() or not e.vitals.is_up() or Person.is_noncombatant(e):
			continue
		if FireMission.flat(e.global_position, centre) > float(s.sensor_m):
			continue
		var secs := spot_seconds(eye, e, scatter, preset)
		if secs == INF:
			continue
		var key := String(e.name)
		seen_now[key] = true
		aware[key] = minf(float(aware.get(key, 0.0)) + dt / maxf(secs, 0.05), 1.0)
		if float(aware[key]) >= 1.0 and t >= float((drone.next_tag as Dictionary).get(key, -INF)):
			drone.next_tag[key] = t + float(s.tag_every_s)
			if tags:
				tags.server_tag_reported(e)
			if not drone.tagged.has(key):
				drone.tagged[key] = true
				SessionLog.note("uav: tagged %s at (%.0f, %.0f)" % [key, e.global_position.x, e.global_position.z])
	for key: String in aware.keys():
		if not seen_now.has(key):
			aware[key] = maxf(float(aware[key]) - dt / FADE_S, 0.0)


## Seconds the UAV's camera at `eye` takes to spot `e` (INF: it can't see him): no wall or roof
## between, less than Spotting.FOLIAGE_OPAQUE_M of crown; spot_s times Spotting's stance,
## movement, camo and foliage factors and the weather's (thermal: darkness doesn't count).
func spot_seconds(eye: Vector3, e: Soldier, scatter: ZoneScatter = null, preset := "plain") -> float:
	var head := e.camera.global_position if e.camera else e.global_position + Vector3.UP * 1.6
	var chest := e.aim_point()
	var range_m := eye.distance_to(chest)
	if range_m > DayNight.sight_m(eye):
		return INF  # fog, rain, the storm: past what anyone sees
	var space := get_viewport().find_world_3d().direct_space_state if get_viewport() else null
	if space:
		var clear_head := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, head, 1)).is_empty()
		var clear_chest := clear_head or space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, 1)).is_empty()
		if not clear_chest:
			return INF  # a roof, a wall, the ground
	var foliage := scatter.foliage_least(eye, head, chest) if scatter else 0.0
	if foliage >= Spotting.FOLIAGE_OPAQUE_M:
		return INF
	var secs := float(spec().get("spot_s", 5.0))
	if e.movement.is_prone():
		secs *= Spotting.PRONE
	elif e.is_crouching():
		secs *= Spotting.CROUCHED
	var speed := Vector2(e.velocity.x, e.velocity.z).length()
	if speed >= Spotting.RUN_MPS:
		secs *= Spotting.RUNNING
	elif speed >= Spotting.WALK_MPS:
		secs *= Spotting.WALKING
	secs *= Spotting.camo(String(e.model.variant) if e.model else "", preset)
	secs *= exp(foliage / Spotting.FOLIAGE_M)
	secs *= DayNight.spot_x(eye)
	return secs


## Host: the enemy's AA technicals near it try for it (aa_every_s).
func _aa(t: float) -> void:
	if t < float(drone.next_aa):
		return
	var s := spec()
	drone.next_aa = t + float(s.get("aa_every_s", 5.0))
	var layer := VehicleLayer.of(self)
	if layer == null:
		return
	var space := get_viewport().find_world_3d().direct_space_state
	for v: Vehicle in layer.vehicles():
		if v.wrecked or v.faction != &"hostile" or not String(v.model) in (s.get("aa_models", []) as Array):
			continue
		if v.global_position.distance_to(drone.pos) > float(s.aa_reach_m):
			continue
		var manned := v.occupants().any(func(o: Soldier) -> bool: return o.faction == &"hostile" and o.vitals.is_up())
		if not manned:
			continue
		var from := v.global_position + Vector3.UP * 2.5
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, drone.pos, 1)).is_empty():
			continue
		Sfx.server_play(&"shot_hmg_far", from)
		if _rng.randf() < float(s.aa_hit_chance):
			server_hit()
			if is_up():
				var fs := FireSupport.of(self)
				if fs:
					fs.radio_uav("Taking AA fire, we're hit.")
		if not is_up():
			return


# --- Every peer: the drone in the sky ---------------------------------------------------------

func _send() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if drone.is_empty():
		_client_set.rpc({})
		return
	var left := maxf(float(drone.until) - FireSupport.now(), 0.0) if float(drone.until) < INF else float(spec().loiter_s)
	_client_set.rpc({"pos": drone.pos, "centre": drone.centre, "state": String(drone.state), "left": left, "tagged": (drone.tagged as Dictionary).size()})


@rpc("authority", "call_local", "unreliable_ordered")
func _client_set(state: Dictionary) -> void:
	shown = state
	if state.is_empty():
		if is_instance_valid(_visual):
			_visual.queue_free()
		_visual = null
		return
	if not is_instance_valid(_visual):
		_visual = make_visual()
		_visual.name = "UavVisual"
		add_child(_visual)
		_visual.global_position = state.pos
	_visual.set_meta(&"goal", state.pos)


func _process(delta: float) -> void:
	if not is_instance_valid(_visual) or not _visual.has_meta(&"goal"):
		return
	var goal: Vector3 = _visual.get_meta(&"goal")
	var to := goal - _visual.global_position
	if to.length() > 60.0:
		_visual.global_position = goal
	else:
		_visual.global_position += to * minf(delta * 6.0, 1.0)
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		_visual.look_at(_visual.global_position + flat, Vector3.UP)
		_visual.rotate_object_local(Vector3.FORWARD, -0.35)  # banked into its turn


## A small fixed-wing drone: a fuselage, a high wing, a tail, a pusher prop (grey, as recon
## drones are painted), nose along -z.
static func make_visual() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.57, 0.58)
	var parts := [
		[Vector3(0.35, 0.35, 2.6), Vector3.ZERO],       # fuselage
		[Vector3(4.2, 0.06, 0.55), Vector3(0, 0.2, -0.2)],  # wing
		[Vector3(1.4, 0.05, 0.35), Vector3(0, 0.15, 1.15)],  # tailplane
		[Vector3(0.05, 0.5, 0.35), Vector3(0, 0.4, 1.15)],  # fin
		[Vector3(0.9, 0.04, 0.08), Vector3(0, 0, 1.35)],  # prop
	]
	for p: Array in parts:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		box.material = mat
		m.mesh = box
		m.position = p[1]
		root.add_child(m)
	return root
