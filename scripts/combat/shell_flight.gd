class_name ShellFlight
extends Node3D
## Gun shells in flight (combined arms A3, cg_brief queue item 2.2; docs/combined_arms.md 2.3.8):
## the Abrams' 120 mm and the Bradley's 25 mm rounds, any data/shells.json row a gun fires. One
## node per level ("ShellFlight", beside Launchers), every round in one array, no node per shell.
##
## The host flies them for real each physics step: gravity and quadratic drag (the row's "drag",
## per metre: a = g - drag x v|v|, tuned so 2.7.5's times of flight and drops come out), a swept
## ray along the step against the world, hitboxes, body armour and vehicles the way Ballistics
## and LauncherProjectile meet them (a vehicle's box counts only where its hull's voxels are:
## LauncherProjectile.hull_hit). What it meets:
## - a vehicle: Vehicle.server_take_hit with the "shell" id, the distance flown ("range_m": the
##   pen tables and arming), its shot id (the rolls' seed) and fuze mode. ArmourModel (A1) and the
##   modules (A2) decide it; a ricochet flies on along the bounce at 60% speed (2.3.3); a filling
##   bursts on the outside (Warheads.server_people: the people round it, not the crew under
##   armour), and a shaped charge's jet goes on behind a hull the modules didn't trace;
## - a body: a filling bursts on him (Warheads' direct hit and blast); a solid shot goes through
##   him (Warheads' direct hit: lethal) and flies on;
## - the world: a solid shot leaves a small hole; a shaped charge bores in (Warheads._jet_world);
##   HE bursts (a crater, people, gore), a delay fuze a little way on through what it met.
## Fuzes: arming_m (closer, a dud that does only its KE), airburst at the set range, the 25 mm
## HEI's self-destruct, the HEAT-MP's proximity mode against helicopters.
##
## Every peer draws each round (a glowing streak flown the same way) from the fire event and
## stops it at the host's end event; a late joiner skips rounds already in the air (they last
## seconds). Every number is Proposed.

const NODE_NAME := &"ShellFlight"
const GRAVITY := Vector3(0.0, -9.8, 0.0)
## A round in the air longer than this, or flown farther, is lost.
const MAX_S := 9.0
const MAX_M := 6000.0
const MASK := Ballistics.MASK
## A ricochet keeps flying at most this many times.
const RICOCHETS_MAX := 2
## A solid shot into the world: a hole of calibre_mm x this (m), within KE_HOLE_M.
const KE_HOLE_PER_MM := 0.002
const KE_HOLE_M := Vector2(0.05, 0.3)
## A delay fuze bursts at most this far past what fuzed it (120 mm AMP: 2 ms at 1,400 m/s).
const DELAY_MAX_M := 3.0
## Fragments reach this x (kg / a grenade's kg)^(1/3) metres when the row has no frag_m.
const FRAG_M_PER_GRENADE := 6.0
## The HEAT-MP in air mode looks this far round its line for a helicopter (the row's prox_m wins).
const PROX_M := 5.0
const RESULTS_KEPT := 64
## The drawn streak (every peer): length (m) and width.
const STREAK_M := 5.0
const STREAK_W := 0.06

var level: Node3D
## Host: every round in flight, each {"id", "sid", "s" (the Shells row), "pos", "vel", "age",
## "flown", "shooter", "veh" (the vehicle that fired it), "ex" (RIDs it never meets), "inside"
## (the vehicle box it's flying through without meeting the hull), "mode", "air_m", "shot",
## "rico", "k"}.
var shells: Array = []
## Host: how each round ended, by id (the last RESULTS_KEPT): {"how" ("vehicle", "body",
## "world", "air", "lost"), "position", "flown", "time", "shell", "vehicle", "result" (the
## vehicle's server_take_hit), "outcome", "ricochets", "bodies" (struck on the way)}.
var results: Dictionary = {}
## Tests: rounds fired, and the host's last physics step's time in ms.
var fired := 0
var last_step_ms := 0.0
var last_id := 0
var _next_id := 1
var _visuals := {}  # every peer: id -> {"node", "vel", "k", "age"}
## Every peer: the last impact drawn (VehicleFx.impact's kind; tests).
var last_impact := ""
static var _streak_mesh: BoxMesh
static var _streak_mats := {}  # A7: the tracer's colour by round kind

signal ended(id: int, result: Dictionary)


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	level = get_parent() as Node3D


## The level's ShellFlight (null outside one).
static func of(from: Node) -> ShellFlight:
	var lvl := CompoundLevel.current(from) if from else null
	return lvl.get_node_or_null(NodePath(String(NODE_NAME))) as ShellFlight if lvl else null


## Host only. Fires a round of shells.json `shell_id` from `origin` at `velocity` (world), fired
## by `shooter`. `opts`: "vehicle" (the vehicle firing it: it and whoever sits in it are never
## met), "fuze_mode" (a mode of the shell's fuze: "air", "delay", "airburst"), "airburst_m" (the
## set burst range), "shot_id" (the armour rolls' seed; default from the id). Returns its id (0:
## not fired).
func server_fire(shell_id: StringName, origin: Vector3, velocity: Vector3, shooter: Node = null, opts := {}) -> int:
	var row := Shells.shell(shell_id)
	if row.is_empty() or not origin.is_finite() or not velocity.is_finite() or velocity.length_squared() < 1.0:
		return 0
	var id := _next_id
	_next_id += 1
	last_id = id
	fired += 1
	var ex: Array[RID] = []
	var veh := opts.get("vehicle") as Vehicle
	if veh:
		ex.append(veh.get_rid())
		for s: Soldier in veh.occupants():
			ex.append_array(Launchers._rids_of(s))
	if shooter is Soldier and is_instance_valid(shooter):
		ex.append_array(Launchers._rids_of(shooter as Soldier))
	shells.append({"id": id, "sid": shell_id, "s": row, "pos": origin, "vel": velocity, "age": 0.0, "flown": 0.0, "shooter": shooter,
		"veh": veh, "ex": ex, "inside": null, "mode": String(opts.get("fuze_mode", "")), "air_m": float(opts.get("airburst_m", 0.0)),
		"shot": opts.get("shot_id", hash([String(name), id, Engine.get_physics_frames()])), "rico": 0, "k": float(row.get("drag", 0.0)),
		"bodies": []})
	_client_fire.rpc(id, String(shell_id), origin, velocity)
	return id


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and not shells.is_empty():
		var t0 := Time.get_ticks_usec()
		_server_step(delta)
		last_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if not _visuals.is_empty():
		_draw_step(delta)


## One physics step of every round (host).
func _server_step(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < shells.size():
		var sh: Dictionary = shells[i]
		if _fly(sh, dt, space):
			shells.remove_at(i)
		else:
			i += 1


## Flies `sh` one step; true when it ended.
func _fly(sh: Dictionary, dt: float, space: PhysicsDirectSpaceState3D) -> bool:
	var v0: Vector3 = sh.vel
	var v1 := v0 + (GRAVITY - v0 * v0.length() * float(sh.k)) * dt
	var from: Vector3 = sh.pos
	var to := from + (v0 + v1) * 0.5 * dt
	sh.age = float(sh.age) + dt
	var row: Dictionary = sh.s
	var fuze := fuze_of(row, String(sh.mode))
	var seg := from.distance_to(to)
	var dir := (to - from) / seg if seg > 0.0001 else v1.normalized()
	# Bursts in the air: at the set range (airburst), or its self-destruct.
	var burst_m := INF
	if String(fuze.get("kind", "")) == "airburst" and float(sh.air_m) > 0.0:
		burst_m = float(sh.air_m) + float(fuze.get("offset_m", 0.0))
	if float(fuze.get("self_destruct_m", 0.0)) > 0.0:
		burst_m = minf(burst_m, float(fuze.self_destruct_m))
	var reach := seg
	if float(sh.flown) + seg >= burst_m:
		reach = maxf(burst_m - float(sh.flown), 0.0)
	var hit := _trace(space, sh, from, from + dir * reach)
	if hit.is_empty() and String(fuze.get("kind", "")) == "proximity":
		var heli := _near_aircraft(from, from + dir * reach, float(fuze.get("prox_m", PROX_M)))
		if heli:
			var at := Geometry3D.get_closest_point_to_segment(heli.global_transform * heli.center_of_mass, from, from + dir * reach)
			sh.flown = float(sh.flown) + from.distance_to(at)
			heli.server_take_hit({"kind": Vehicle.HE, "position": at, "direction": dir, "shooter": _shooter(sh), "blast_kg": float(row.get("he_kg", 0.0))})
			_burst(sh, at, dir, [], 0.0)
			return _end(sh, "air", at, {"vehicle": heli, "outcome": "proximity"})
	if not hit.is_empty():
		sh.age = float(sh.age) - dt * (1.0 - clampf(from.distance_to(hit.position) / maxf(seg, 0.0001), 0.0, 1.0))  # when on the step it met it
		return _impact(sh, hit, from, dir, space)  # (on through: _impact moved it on)
	if reach < seg:  # its burst range: a burst in the air
		var at := from + dir * reach
		sh.flown = float(sh.flown) + reach
		if float(row.get("he_kg", 0.0)) > 0.0 and float(sh.flown) >= float(row.get("arming_m", 0.0)):
			_burst(sh, at, dir, [], 0.0)
		return _end(sh, "air", at, {"outcome": "airburst" if String(fuze.get("kind", "")) == "airburst" else "self_destruct"})
	sh.pos = to
	sh.vel = v1
	sh.flown = float(sh.flown) + seg
	if is_instance_valid(sh.inside) and not Launchers.hull_box(sh.inside as Node3D).grow(0.5).has_point(to):
		sh.inside = null
	if float(sh.age) > MAX_S or float(sh.flown) > MAX_M or to.y < -500.0:
		return _end(sh, "lost", to, {})
	return false


## What the step from `from` to `to` meets first ({} for nothing): LauncherProjectile._trace's
## rule for vehicles (a box counts only where the hull's voxels are).
func _trace(space: PhysicsDirectSpaceState3D, sh: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	var dir := (to - from).normalized()
	if dir == Vector3.ZERO:
		return {}
	var start := from
	var ex: Array[RID] = sh.ex
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(start, to, MASK, ex)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		var inside := sh.inside as Vehicle if is_instance_valid(sh.inside) else null
		if inside:
			var met := LauncherProjectile.hull_hit(inside, start, dir, start.distance_to(hit.position if not hit.is_empty() else to))
			if not met.is_empty():
				return met
		if hit.is_empty():
			return {}
		var v := Vehicle.find_on(hit.collider)
		if v == null or v.hull == null or not LauncherProjectile.hull_hit(v, hit.position, dir, Vehicle.PROBE_M).is_empty():
			return hit
		sh.inside = v  # only its box: on through it (an open bed, over a hatch)
		start = hit.position + dir * 0.01
	return {}


## The helicopter whose centre is within `prox_m` of the segment, or null.
func _near_aircraft(from: Vector3, to: Vector3, prox_m: float) -> Vehicle:
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v and v.kind == Vehicle.HELICOPTER and not v.wrecked:
			var c := v.global_transform * v.center_of_mass
			if Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) <= prox_m + VehicleArt.size_m(v.model).length() * 0.3:
				return v
	return null


## Host: `sh` met `hit` flying from `from` along `dir`. True when it ends there.
func _impact(sh: Dictionary, hit: Dictionary, from: Vector3, dir: Vector3, _space: PhysicsDirectSpaceState3D) -> bool:
	var row: Dictionary = sh.s
	var pos: Vector3 = hit.position
	var collider: Object = hit.get("collider")
	var flown := float(sh.flown) + from.distance_to(pos)
	var speed := (sh.vel as Vector3).length()
	var kg := float(row.get("he_kg", 0.0))
	var kind := String(row.get("kind", "he"))
	var column := column_of(kind)
	var armed := flown >= float(row.get("arming_m", 0.0))
	var shooter := _shooter(sh)
	var v := Vehicle.find_on(collider) if collider else null
	if v:
		var hd := {"kind": vehicle_kind(kind), "position": pos, "direction": dir, "shooter": shooter, "shell": String(sh.sid), "range_m": flown,
			"shot_id": sh.shot, "energy_j": 0.5 * float(row.get("mass_kg", 1.0)) * speed * speed, "probe_m": Vehicle.PROBE_M,
			"blast_kg": kg, "penetration_mm": float(row.get("pen_ce", 0.0)), "round": String(sh.sid)}  # (round: a soft model's tier, data/vehicles.json round_tiers)
		if String(sh.mode) != "":
			hd["fuze_mode"] = String(sh.mode)
		if float(sh.air_m) > 0.0:
			hd["airburst_m"] = float(sh.air_m)
		var r := v.server_take_hit(hd)
		if bool(r.get("missed", false)):
			sh.inside = v
			sh.pos = pos + dir * 0.01
			sh.flown = flown
			return false
		var armour: Dictionary = r.get("armour", {})
		var outcome := String(armour.get("outcome", "pen" if bool(r.get("penetrated", false)) else "non_pen"))
		if outcome == String(ArmourModel.RICOCHET) and int(sh.rico) < RICOCHETS_MAX:
			var rd := (v.global_basis * (armour.get("ricochet_dir", -dir) as Vector3)).normalized()
			sh.vel = rd * speed * float(armour.get("speed_frac", ArmourModel.RICOCHET_SPEED))
			sh.pos = pos + rd * 0.05
			(sh.ex as Array).append(v.get_rid())  # off it: never back into the same hull
			sh.rico = int(sh.rico) + 1
			sh.flown = flown
			return false
		sh.flown = flown
		if kg > 0.0 and armed and outcome != String(ArmourModel.DUD):
			_burst(sh, pos - dir * 0.08, dir, [], 0.0)  # the filling outside: the people round it
		if column == "ce" and bool(r.get("penetrated", false)) and not bool(r.get("traced", false)) and float(row.get("pen_ce", 0.0)) > 0.0:
			var jet := {"hurt": []}
			var behind: Array[RID] = [v.get_rid()]
			Warheads._jet_behind(level as CompoundLevel, (r.get("position", pos) as Vector3) + dir * 0.05, dir, shooter, behind, jet, false)
		return _end(sh, "vehicle", pos, {"vehicle": v, "result": r, "outcome": outcome})
	var body := Warheads.body_of(collider)
	if body and body.get_node_or_null(^"Vitals"):
		if kg > 0.0 and armed:
			Warheads._direct_hit(body, collider, pos, dir, shooter, kg)
			(sh.bodies as Array).append(body)
			sh.flown = flown
			_burst(sh, pos, dir, [body], 0.0)
			return _end(sh, "body", pos, {})
		Warheads._direct_hit(body, collider, pos, dir, shooter, 0.0)  # solid shot (or not yet armed): through him
		(sh.bodies as Array).append(body)
		(sh.ex as Array).append_array(Warheads._rids_of(body))
		if body is Soldier:
			(sh.ex as Array).append_array(Launchers._rids_of(body as Soldier))
		sh.pos = pos + dir * 0.02
		sh.flown = flown
		return false
	# The world: ground, walls, buildings.
	sh.flown = flown
	var lvl := level as CompoundLevel
	if column == "ke" or not armed:
		if lvl:
			lvl.server_blast(pos, clampf(float(row.get("calibre_mm", 20.0)) * KE_HOLE_PER_MM, KE_HOLE_M.x, KE_HOLE_M.y), 0.0)
		return _end(sh, "world", pos, {"outcome": "ke" if armed else "dud"})
	if column == "ce" and float(row.get("pen_ce", 0.0)) > 0.0:
		var world := VoxelWorld.find_on(collider) if collider else null
		if world:
			var jet := Warheads._jet_world(world, pos, dir, float(row.pen_ce))
			if not (jet.cells as Array).is_empty():
				world.server_holes(jet.cells)
	var centre := pos - dir * 0.08
	var fuze := fuze_of(row, String(sh.mode))
	if String(fuze.get("kind", "")) == "pd_delay":
		centre = pos + dir * minf(speed * float(fuze.get("delay_ms", 0.0)) / 1000.0, DELAY_MAX_M)  # on through the wall
	_burst(sh, centre, dir, [], (Warheads.HEAT_CRATER_M if column == "ce" and kind == "heat" else Warheads.HE_CRATER_M * pow(maxf(kg, 0.0), 1.0 / 3.0)))
	return _end(sh, "world", pos, {"outcome": "burst"})


## Host: a filling of `sh` going off at `centre`: the crater (`crater_m`, 0 none), Warheads'
## blast and fragments on everyone round it not under armour (server_people), the gore, the
## objectives a charge would hit, the noise. `skip`: bodies already dealt with.
func _burst(sh: Dictionary, centre: Vector3, _dir: Vector3, skip: Array, crater_m: float) -> void:
	var lvl := level as CompoundLevel
	if lvl == null:
		return
	var row: Dictionary = sh.s
	var kg := float(row.get("he_kg", 0.0))
	if kg <= 0.0:
		return
	var frag_m := float(row.get("frag_m", FRAG_M_PER_GRENADE * pow(kg / Warheads.GRENADE_TNT_KG, 1.0 / 3.0)))
	var d := {"blast_kg": kg, "frag_m": frag_m, "frag_wounds": row.get("frag_wounds", [1, 3]),
		"kind": String(Vehicle.THERMOBARIC if String(row.get("kind", "")) == "thermobaric" else Vehicle.HE)}
	if crater_m > 0.0:
		lvl.server_blast(centre, crater_m)
	var shooter := _shooter(sh)
	Warheads.server_people(lvl, centre, d, shooter, skip)
	BlastGore.server_blast(lvl, centre, kg, frag_m, skip)
	Contracts.objectives.server_charge_blast(centre)
	PeopleLayer.server_noise(lvl, centre, PeopleLayer.BLAST_HEARD_M)


func _shooter(sh: Dictionary) -> Node:
	return sh.shooter as Node if is_instance_valid(sh.shooter) else null


## Host: `sh` ends at `pos` (`how`); kept in results, every peer stops drawing it.
func _end(sh: Dictionary, how: String, pos: Vector3, extra: Dictionary) -> bool:
	var r := {"how": how, "position": pos, "flown": float(sh.flown), "time": float(sh.age), "shell": sh.sid, "ricochets": int(sh.rico),
		"bodies": (sh.bodies as Array).duplicate(), "outcome": String(extra.get("outcome", how))}
	for k: String in extra:
		r[k] = extra[k]
	results[int(sh.id)] = r
	while results.size() > RESULTS_KEPT:
		results.erase(results.keys()[0])
	var v := extra.get("vehicle") as Vehicle
	var cls := String(v.spec.get("class", "")) if is_instance_valid(v) else ""
	_client_end.rpc(int(sh.id), pos, how, String(r.outcome), String(sh.sid), cls, (sh.vel as Vector3).normalized())  # (A7: the impact by round, VehicleFx.impact)
	ended.emit(int(sh.id), r)
	return true


# --- Pure ----------------------------------------------------------------------------------------

## The threat column of a shell kind (ArmourModel's): "ke", "ce" or "he".
static func column_of(kind: String) -> String:
	return "ke" if kind in Shells.KE_KINDS else ("ce" if kind in Shells.CE_KINDS else "he")


## The Vehicle hit kind a shell of `kind` arrives as (server_take_hit: solid shot and jets meet the
## hull's voxels; HE bursts where its box is met).
static func vehicle_kind(kind: String) -> StringName:
	match kind:
		"heat":
			return Vehicle.HEAT
		"tandem_heat":
			return Vehicle.TANDEM_HEAT
		"hedp", "amp":
			return Vehicle.HEDP
		"he", "hei":
			return Vehicle.HE
		"thermobaric":
			return Vehicle.THERMOBARIC
	return Vehicle.KINETIC


## A shell row's fuze in `mode` (its "modes" entry, or the fuze itself).
static func fuze_of(row: Dictionary, mode: String) -> Dictionary:
	var fuze: Dictionary = row.get("fuze", {"kind": "none"})
	if mode != "" and (fuze.get("modes", {}) as Dictionary).has(mode):
		var out: Dictionary = (fuze.modes[mode] as Dictionary).duplicate()
		if fuze.has("self_destruct_m") and not out.has("self_destruct_m"):
			out["self_destruct_m"] = fuze.self_destruct_m
		return out
	return fuze


## Where a round of `shell_id` fired level from the origin at its muzzle velocity is after
## flying `range_m` metres downrange: {"time" (s), "drop" (m below the line), "speed" (m/s)}.
## The same steps the host flies (tests check 2.7.5's table; A4's fire control builds its
## ballistic table from it).
static func flight_to(shell_id: StringName, range_m: float, dt := 1.0 / 60.0) -> Dictionary:
	var row := Shells.shell(shell_id)
	var k := float(row.get("drag", 0.0))
	var vel := Vector3.FORWARD * float(row.get("muzzle_mps", 1000.0))
	var pos := Vector3.ZERO
	var t := 0.0
	while -pos.z < range_m and t < MAX_S:
		var v1 := vel + (GRAVITY - vel * vel.length() * k) * dt
		var to := pos + (vel + v1) * 0.5 * dt
		if -to.z >= range_m:
			var f := (range_m + pos.z) / maxf(pos.z - to.z, 0.0001)
			return {"time": t + dt * f, "drop": -lerpf(pos.y, to.y, f), "speed": lerpf(vel.length(), v1.length(), f)}
		pos = to
		vel = v1
		t += dt
	return {"time": t, "drop": -pos.y, "speed": vel.length()}


# --- Every peer: the drawn rounds ----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _client_fire(id: int, shell_id: String, origin: Vector3, velocity: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		_visuals[id] = {"node": null, "vel": velocity, "pos": origin, "k": float(Shells.shell(StringName(shell_id)).get("drag", 0.0)), "age": 0.0}
		return  # (headless: no mesh, the flight is still kept so tests can read it)
	if _streak_mesh == null:
		_streak_mesh = BoxMesh.new()
		_streak_mesh.size = Vector3(STREAK_W, STREAK_W, STREAK_M)
	var mi := MeshInstance3D.new()
	mi.mesh = _streak_mesh
	mi.material_override = tracer_material(String(Shells.shell(StringName(shell_id)).get("kind", "he")))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = origin
	_visuals[id] = {"node": mi, "vel": velocity, "pos": origin, "k": float(Shells.shell(StringName(shell_id)).get("drag", 0.0)), "age": 0.0}


@rpc("authority", "call_local", "reliable")
func _client_end(id: int, pos: Vector3, how: String, outcome := "", sid := "", cls := "", dir := Vector3.FORWARD) -> void:
	var vis: Dictionary = _visuals.get(id, {})
	_visuals.erase(id)
	if vis.is_empty():
		return
	var node := vis.node as Node3D
	if is_instance_valid(node):
		node.queue_free()
	if how in ["vehicle", "world", "air", "body"]:
		last_impact = VehicleFx.impact(self, pos, how, outcome, sid, cls, dir)  # A7 (2.10.3): sparks, a flash, a burst by the round and what it did


## Every peer: the drawn rounds fly on as the host's do (no hit tests: the host's end event stops them).
func _draw_step(dt: float) -> void:
	for id: int in _visuals.keys():
		var vis: Dictionary = _visuals[id]
		var v0: Vector3 = vis.vel
		var v1 := v0 + (GRAVITY - v0 * v0.length() * float(vis.k)) * dt
		vis.pos = (vis.pos as Vector3) + (v0 + v1) * 0.5 * dt
		vis.vel = v1
		vis.age = float(vis.age) + dt
		var node := vis.node as Node3D
		if is_instance_valid(node):
			node.global_position = vis.pos
			if v1.length_squared() > 1.0:
				node.look_at(node.global_position + v1, Vector3.UP if absf(v1.normalized().y) < 0.99 else Vector3.RIGHT)
		if float(vis.age) > MAX_S + 1.0:
			if is_instance_valid(node):
				node.queue_free()
			_visuals.erase(id)


## A7 (2.10.3): a round's tracer by its kind: a sabot's white-hot, HEAT's orange, HE's red.
const TRACER_COLOURS := {"apfsds": Color(1.0, 0.95, 0.8), "apds": Color(1.0, 0.9, 0.7), "heat": Color(1.0, 0.6, 0.25), "amp": Color(1.0, 0.45, 0.2),
	"he": Color(1.0, 0.35, 0.2), "hei": Color(1.0, 0.35, 0.2)}


static func tracer_material(kind: String) -> StandardMaterial3D:
	if not _streak_mats.has(kind):
		var c: Color = TRACER_COLOURS.get(kind, Color(1.0, 0.55, 0.25))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 4.0
		_streak_mats[kind] = mat
	return _streak_mats[kind]


## Every peer: how many rounds it's drawing now (tests).
func drawn_count() -> int:
	return _visuals.size()
