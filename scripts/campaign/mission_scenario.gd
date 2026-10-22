class_name MissionScenario
extends Node
## Plays the scenario mission types in the level (mission variety, 2026-10-15; docs/missions.md):
## convoy ambush, hold the line, downed crew rescue, recon, the "never spotted" bonus,
## sabotage's vehicle park (2026-10-20: its own section) and missions 2's HVT kill, crash site and
## overwatch (2026-10-20: their own section at the end). Host
## only (everything it spawns replicates like any AI, vehicle or person); one node per level,
## "MissionScenario", installed by MapNodes.install on every peer and idle off the host.
##
## ScenarioGen builds the objectives (their "params" hold the route, the point, the crew);
## this node starts a run per objective when its contract goes live (Contracts.contract_live)
## and ticks them every TICK_S, marking them done or failed through Objectives.server_set_state.
## The runs keep their own clocks (seconds ticked), so tests move time with server_advance().
## Waves come from the level's Reinforcements (server_send from a point on a ring round the
## site), sized by the contract's tuning; the types with "own_waves" have the standard timer off
## (Contracts.reinforcement_tuning).
##
## Test hooks (host): server_advance(seconds), run_of(oid), server_mark_site(oid),
## server_spotted(), server_neutralize_convoy(oid).

const NODE_NAME := "MissionScenario"
const TICK_S := 0.5
## Hold: lost this long with the enemy in the position and none of ours (s); or abandoned
## (nobody of ours in it) this long after the clock started.
const LOSE_S := 15.0
const ABANDON_S := 90.0
## Convoy: a cargo truck this close to the end of the route has got away (m); trucks are
## spaced this far apart along the route at the start (m).
const ESCAPE_M := 30.0
const SPACING_M := 14.0
const CARGO_MODEL := "maxxpro"
const ESCORT_MODEL := "technical_dshk"
## A rescue's crew stands this far round the wreck (m).
const CREW_RING_M := 5.5
const WRECK_MODEL := "uh60"

## Host: oid -> the run's state (see _begin).
var runs: Dictionary = {}

var level: Node3D
var _tick := 0.0
var _squad: Squad


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	level = get_parent() as Node3D
	Contracts.contract_live.connect(_on_live)
	Contracts.contract_returned.connect(_on_live)


## The node of the level `from` is in, or null.
static func of(from: Node) -> MissionScenario:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as MissionScenario if lvl else null


func run_of(oid: String) -> Dictionary:
	return runs.get(oid, {})


func _physics_process(delta: float) -> void:
	if runs.is_empty() or not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_advance(TICK_S)


## Host: runs every run `seconds` forward (in TICK_S steps; the physics frame calls it, tests
## jump it).
func server_advance(seconds: float) -> void:
	if not multiplayer.is_server():
		return
	var left := seconds
	while left > 0.0:
		var dt := minf(left, TICK_S)
		left -= dt
		_step(dt)


func _step(dt: float) -> void:
	for oid: String in runs.keys():
		var run: Dictionary = runs[oid]
		var o := Contracts.objectives.get_objective(oid)
		if o.is_empty() or o.state != Objectives.ACTIVE:
			_finish(run, o)
			runs.erase(oid)
			continue
		match String(run.kind):
			Objectives.CONVOY:
				_convoy_tick(run, o, dt)
			Objectives.HOLD_POINT:
				_hold_tick(run, o, dt)
			Objectives.RESCUE_CREW:
				_rescue_tick(run, o, dt)
			Objectives.RECON_SITE:
				_recon_tick(run, o, dt)
			Objectives.UNDETECTED:
				_unseen_tick(run, o)
			Objectives.DESTROY_VEHICLES:
				_park_tick(run, o)
			HVT_KILL, ScenarioGen.CRASH, ScenarioGen.OVERWATCH:
				_ops_tick(run, o, dt)  # (missions 2: their own section at the end)


## A run that ended (objective done, failed or gone): a convoy that is still rolling is left to it.
func _finish(run: Dictionary, _o: Dictionary) -> void:
	if String(run.kind) == Objectives.CONVOY and String(run.get("phase", "")) == "left":
		return


func _on_live(_cid: String, objectives: Array) -> void:
	if not multiplayer.is_server():
		return
	for o: Dictionary in objectives:
		if o.get("state") != Objectives.ACTIVE or not Objectives.here(o, level) or runs.has(String(o.oid)):
			continue
		if String(o.kind) in [Objectives.CONVOY, Objectives.HOLD_POINT, Objectives.RESCUE_CREW, Objectives.RECON_SITE, Objectives.UNDETECTED]:
			var saved: Dictionary = Campaign.section(&"contracts").get("deployment", {}).get("scenario_runs", {}).get(String(o.oid), {})
			if saved.is_empty():
				_begin(o)  # older saves have no checkpoint; never restart a run already present
			else:
				runs[String(o.oid)] = ScenarioCheckpoint.restore(self, saved)
				if o.kind == Objectives.CONVOY:
					_track_convoy(runs[String(o.oid)])
				if o.kind in [Objectives.HOLD_POINT, Objectives.RESCUE_CREW]:
					_aim_waves(_p3(o.params.pos))
				if is_instance_valid(_squad) and (o.kind != Objectives.CONVOY or (runs[String(o.oid)].get("vehicles", []) as Array).any(func(e: Dictionary) -> bool: return bool(e.out))):
					_squad.patrol = [_ground(_p3(o.params.pos))]
	server_checkpoint()


## The deployment owns checkpoints across zones; only this level's runs are updated here.
func server_checkpoint() -> void:
	if not multiplayer.is_server():
		return
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		for run: Dictionary in runs.values():
			if run.has("group") and Virtualizer.is_virtual(run.group):
				virtualizer.server_wake(run.group)  # a convoy out of everyone's way as a profile: back in the world to be saved as one
		virtualizer.server_flush()
	var dep: Dictionary = Campaign.section(&"contracts").get("deployment", {})
	if dep.is_empty():
		return
	if not dep.has("scenario_runs"):
		dep["scenario_runs"] = {}
	for oid: String in runs:
		var o := Contracts.objectives.get_objective(oid)
		if not o.is_empty() and o.state == Objectives.ACTIVE:
			dep.scenario_runs[oid] = ScenarioCheckpoint.capture(runs[oid], dep.scenario_runs.get(oid, {}))


## Host: a run for objective `o`: its clock, and whatever it puts in the level at once (a
## rescue's wreck and crew; a convoy waits to set out).
func _begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var run := {"kind": String(o.kind), "oid": String(o.oid), "cid": String(o.cid), "t": 0.0}
	match String(o.kind):
		Objectives.CONVOY:
			run["phase"] = "waiting"
			run["vehicles"] = []
			run["dropped"] = false
			var route := PackedVector3Array()
			for point: Variant in p.get("route", []):
				route.append(_ground(Vector3(float(point[0]), 0.0, float(point[2]))))
			run["route"] = route
		Objectives.HOLD_POINT:
			run["clock"] = 0.0
			run["started"] = false
			run["wave"] = 0
			run["lose_s"] = 0.0
			run["away_s"] = 0.0
			_aim_waves(_p3(p.pos))
		Objectives.RESCUE_CREW:
			if bool(p.get("bonus_only", false)):
				return  # shares the main objective's crew
			run["wave"] = 0
			run["crew"] = []
			_aim_waves(_p3(p.pos))
			_rescue_spawn(run, o)
		Objectives.RECON_SITE:
			run["dwell"] = 0.0
	runs[run.oid] = run
	Contracts.objectives.server_set_state(run.oid, Objectives.ACTIVE, _progress(run, o))


## Waves head for the point rather than for the players (not in a hot zone, where EnemyResponse
## owns the aim).
func _aim_waves(point: Vector3) -> void:
	var r := _reinforcements()
	if r and not r.driven and not r.aim.is_valid():
		r.aim = func() -> Vector3: return point


func _reinforcements() -> Reinforcements:
	return level.get_node_or_null(^"Reinforcements") as Reinforcements if level else null


## A wave from the ring round `centre`: `index` picks the bearing among `dirs` spread evenly
## from `bearing`, `approach_m` out, inside the zone. Returns the soldiers.
func _send_wave(centre: Vector3, index: int, dirs: int, bearing: float, approach_m: float) -> Array:
	var r := _reinforcements()
	if r == null:
		return []
	var a := bearing + TAU * float(index % maxi(dirs, 1)) / float(maxi(dirs, 1))
	var spot := centre + Vector3(cos(a), 0.0, sin(a)) * approach_m
	var area: Rect2 = level.call(&"ground_area") if level.has_method(&"ground_area") else Rect2(-400, -400, 800, 800)
	area = area.grow(-50.0)
	spot = Vector3(clampf(spot.x, area.position.x, area.end.x), 0.0, clampf(spot.z, area.position.y, area.end.y))
	return r.server_send(_ground(spot), 0, -1, _ground(centre))  # it assaults the point, not the squad's last known spot


func _ground(p: Vector3) -> Vector3:
	return level.call(&"ground_point", p) if level and level.has_method(&"ground_point") else p


static func _p3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Our side, up: the players and their squad (faction friendly; people have their own faction).
func _friendlies() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"friendly" and not s.is_queued_for_deletion() and s.vitals.is_up():
			out.append(s)
	return out


func _hostiles_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= radius:
			n += 1
	return n


func _mark(run: Dictionary, o: Dictionary, state: String, progress := "") -> void:
	Contracts.objectives.server_set_state(String(run.oid), state, progress)
	if String(o.get("kind", "")) == Objectives.CONVOY and not o.has("leg"):
		_chase_after(String(run.cid), state)


## A convoy chase (LZ-7, contracts.json "chase"): the convoy stopped here, its leg's convoy is
## done too (nothing got away to chase); got away, the squad hears where it went.
func _chase_after(cid: String, state: String) -> void:
	var c := Contracts.contract(cid)
	if not bool(MissionRegistry.type_def(String(c.get("type", ""))).get("chase", false)) or (c.get("legs", []) as Array).is_empty():
		return
	var leg: Dictionary = c.legs[0]
	if state == Objectives.DONE:
		for o: Dictionary in Contracts.objectives.list:
			if String(o.cid) == cid and o.has("leg") and String(o.kind) == Objectives.CONVOY and String(o.state) == Objectives.ACTIVE:
				Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE, "stopped before it got away")
	elif state == Objectives.FAILED:
		Contracts._notify_all("The convoy got away into %s: chase it through the crossing." % String(leg.zone_name))


func _progress(run: Dictionary, o: Dictionary) -> String:
	var p: Dictionary = o.params
	match String(run.kind):
		Objectives.CONVOY:
			match String(run.get("phase", "")):
				"waiting":
					return "due in %d min" % ceili(maxf(float(p.get("depart_s", 0.0)) - float(run.t), 0.0) / 60.0)
				"rolling":
					return "rolling, %d cargo truck%s still moving" % [_moving_cargo(run), "" if _moving_cargo(run) == 1 else "s"]
			return String(run.get("phase", ""))
		Objectives.HOLD_POINT:
			var left := maxf(float(p.hold_s) - float(run.clock), 0.0)
			return ("%d:%02d left" % [floori(left / 60.0), int(left) % 60]) if bool(run.started) else "get to the position"
		Objectives.RESCUE_CREW:
			var crew: Array = p.get("crew", [])
			return "%d of %d out" % [(p.get("out", []) as Array).size(), crew.size()]
		Objectives.RECON_SITE:
			return "%d of %d s observed" % [floori(float(run.dwell)), roundi(float(p.dwell_s))]
	return ""


# --- Convoy ------------------------------------------------------------------------------------

func _convoy_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	run.t += dt
	if String(run.phase) == "waiting":
		if float(run.t) >= float(p.depart_s):
			_convoy_spawn(run, o)
			run.phase = "rolling"
		_mark(run, o, Objectives.ACTIVE, _progress(run, o))
		return
	if String(run.phase) != "rolling":
		return
	if run.has("group") and Virtualizer.is_virtual(run.group):
		_virtual_convoy_tick(run, o)  # out of everyone's way, a profile drives it on (Virtualizer)
		return
	var cargo_down := 0
	var cargo_total := 0
	var route: PackedVector3Array = run.route
	var end := route[route.size() - 1] if not route.is_empty() else Vector3.ZERO
	for e: Dictionary in run.vehicles:
		var v := e.v as Vehicle if is_instance_valid(e.v) else null
		if bool(e.cargo):
			cargo_total += 1
		if v == null or v.is_queued_for_deletion():
			e["down"] = true
		elif not bool(e.get("down", false)) and _neutralized(e, v):
			e["down"] = true
			if not bool(e.out):
				_convoy_dismount(run, e, "disabled")
		if bool(e.get("down", false)) and bool(e.cargo):
			cargo_down += 1
			if bool(e.crate) and not bool(run.dropped):
				_convoy_drop_crate(run, o, e)
		elif v and not bool(e.out) and bool(e.cargo) and Vector2(v.global_position.x - end.x, v.global_position.z - end.z).length() <= ESCAPE_M:
			_convoy_leave(run)
			_mark(run, o, Objectives.FAILED, "the convoy got away")
			return
		if v and bool(e.hit) and not bool(run.get("ambushed", false)):
			run["ambushed"] = true
			_convoy_halt_all(run, "ambushed")
	if cargo_total > 0 and cargo_down >= cargo_total:
		_mark(run, o, Objectives.DONE, "convoy stopped")
		return
	_mark(run, o, Objectives.ACTIVE, _progress(run, o))


## Whether a convoy vehicle is out of the fight: wrecked, burning, can't drive, or its crew is all down.
func _neutralized(e: Dictionary, v: Vehicle) -> bool:
	if v.wrecked or v.is_burning() or not v.can_drive():
		return true
	var crew: Array = e.crew
	return not crew.is_empty() and crew.all(func(s: Variant) -> bool: return not is_instance_valid(s) or not (s as Soldier).vitals.is_up())


func _moving_cargo(run: Dictionary) -> int:
	var n := 0
	for e: Dictionary in run.vehicles:
		if bool(e.cargo) and not bool(e.get("down", false)):
			n += 1
	return n


## Host: the convoy's vehicles and crews, on the route's first leg and driving: escorts front and
## back, the cargo trucks between, drivers and gunners and the rest of the true force aboard.
func _convoy_spawn(run: Dictionary, o: Dictionary) -> void:
	var p: Dictionary = o.params
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	var route: PackedVector3Array = run.route
	if layer == null or route.size() < 2:
		return
	var trucks := int(p.get("trucks", 1))
	var escorts := int(p.get("escorts", 1))
	var models: Array = []
	var front := ceili(escorts / 2.0)
	for i in front:
		models.append([ESCORT_MODEL, false])
	for i in trucks:
		models.append([CARGO_MODEL, true])
	for i in escorts - front:
		models.append([ESCORT_MODEL, false])
	var fwd := (route[1] - route[0])
	fwd.y = 0.0
	fwd = fwd.normalized()
	var force := int(Contracts.enemy_force(String(o.cid)).get("count", 6))
	var quality := float(Contracts.enemy_force(String(o.cid)).get("quality", 0.4))
	var crews := clampi(force, models.size() * 2, 14)
	var made := 0
	var cargo_first := true
	var path := PackedVector3Array()
	for k in range(1, route.size()):
		path.append(route[k])
	for i in models.size():
		var model: String = models[i][0]
		var at := _ground(route[0] - fwd * SPACING_M * i)
		var v := layer.server_spawn(model, Transform3D(Basis.looking_at(fwd, Vector3.UP), at), "", &"hostile", "")
		if v == null:
			continue
		v.set_meta(&"no_save", true)
		var e := {"v": v, "cargo": bool(models[i][1]), "crate": false, "crew": [], "out": false, "hit": false}
		if e.cargo and cargo_first:
			e.crate = true
			cargo_first = false
		var seats := VehicleQrf._seat_order(v)
		var want := mini(seats.size(), maxi(2, ceili(float(crews) / models.size())))
		for si in want:
			var s := _convoy_soldier(run, "CV%d_%d" % [i + 1, si + 1], at, quality)
			if s == null:
				continue
			if v.server_enter(s, int(seats[si])):
				(e.crew as Array).append(s)
				made += 1
			else:
				s.queue_free()
		AavGunner.attach(v)
		v.damaged.connect(_on_convoy_hit.bind(e))
		run.vehicles.append(e)
		v.server_follow_path(path, float(p.get("speed_kmh", 28.0)))
	print("[mission] convoy %s sets out: %d vehicles, %d crew" % [run.oid, (run.vehicles as Array).size(), made])
	_track_convoy(run)


## The convoy of `run`, while it rolls with everyone aboard, may go virtual far from the squad (AI
## virtualization: Virtualizer, rides): "group" is its crews as one group, this node vouching for
## its vehicles (virtual_ride) and driving them on when they're back (virtual_ride_back). It isn't
## in the zone save's profiles: the scenario checkpoint keeps it (server_checkpoint wakes it first).
func _track_convoy(run: Dictionary) -> void:
	var virtualizer := Virtualizer.of(self)
	if virtualizer == null or not run.has("vehicles"):
		return
	var crew: Array = []
	for e: Dictionary in run.vehicles:
		crew.append_array((e.crew as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s)))
	run["group"] = {"squad": _squad, "soldiers": crew, "v_owner": self, "v_nosave": true, "v_keep_squad": true, "oid": String(run.get("oid", ""))}
	virtualizer.track(run.group, "convoy", false)


## Virtualizer: where convoy vehicle `v` is going while every one of its convoy still rolls ({} once
## any has stopped, been hit or got out): the rest of its path and its speed, and which it is ("key").
func virtual_ride(v: Vehicle) -> Dictionary:
	for oid: String in runs:
		var run: Dictionary = runs[oid]
		if String(run.get("kind", "")) != Objectives.CONVOY or String(run.get("phase", "")) != "rolling" or bool(run.get("ambushed", false)):
			continue
		var vehicles: Array = run.get("vehicles", [])
		for i in vehicles.size():
			var e: Dictionary = vehicles[i]
			if e.v != v:
				continue
			if vehicles.any(func(x: Dictionary) -> bool: return bool(x.out) or bool(x.get("down", false)) or bool(x.hit)):
				return {}
			if not is_instance_valid(v.ai) or not v.ai.active:
				return {}
			var path: Array[Vector3] = []
			for k in range(v.ai.index, v.ai.path.size()):
				path.append(v.ai.path[k])
			return {"key": "%s|%d" % [oid, i], "path": path, "speed_kmh": v.ai.cruise_ms * 3.6}
	return {}


## Virtualizer: convoy vehicle `key` ("<oid>|<index>") is back as `v` with `riders` aboard: it's that
## vehicle of its run again (crew, hits, gun) and drives on along `path` at `speed_kmh`.
func virtual_ride_back(key: String, v: Vehicle, riders: Array, path: Array[Vector3], speed_kmh: float) -> void:
	var parts := key.split("|")
	var run: Dictionary = runs.get(parts[0], {})
	var vehicles: Array = run.get("vehicles", [])
	if parts.size() < 2 or not parts[1].is_valid_int() or int(parts[1]) >= vehicles.size():
		return
	var e: Dictionary = vehicles[int(parts[1])]
	e.v = v
	e.crew = riders.duplicate()
	AavGunner.attach(v)
	v.damaged.connect(_on_convoy_hit.bind(e))
	if not path.is_empty():
		v.server_follow_path(PackedVector3Array(path), speed_kmh)


## A virtual convoy's tick: still on its way, or (its lead within ESCAPE_M of the route's end) it got
## away, profile and all.
func _virtual_convoy_tick(run: Dictionary, o: Dictionary) -> void:
	var route: PackedVector3Array = run.route
	var end := route[route.size() - 1] if not route.is_empty() else Vector3.ZERO
	var at := Virtualizer.lead(run.group)
	if at.is_finite() and Vector2(at.x - end.x, at.z - end.z).length() <= ESCAPE_M:
		var virtualizer := Virtualizer.of(self)
		if virtualizer:
			virtualizer.server_forget(run.group)
		_convoy_leave(run)
		_mark(run, o, Objectives.FAILED, "the convoy got away")
		return
	_mark(run, o, Objectives.ACTIVE, _progress(run, o))


func _convoy_soldier(_run: Dictionary, soldier_name: String, at: Vector3, quality: float, identity := {}) -> Soldier:
	if _squad == null or not is_instance_valid(_squad):
		_squad = Squad.new()
		_squad.name = "ConvoyCrews"
		_squad.faction = &"hostile"
		add_child(_squad)
	var loadout: Variant = level.get(&"HOSTILE_LOADOUT")
	var data := {"name": soldier_name, "faction": "hostile", "variant": "urban", "pos": at + Vector3.UP * 0.5,
		"loadout": loadout if loadout is Array else Reinforcements.LOADOUT, "combat": clampf(quality, 0.2, 0.9), "discipline": 0.5, "guard": false, "mode": "aware"}
	data.merge(identity, true)
	var s: Soldier = level.call(&"spawn_soldier", data)
	if s == null:
		return null
	var brain := SquadAI.of(s)
	if brain:
		brain.squad = _squad
	return s


func _on_convoy_hit(_zone: StringName, _hit: Dictionary, e: Dictionary) -> void:
	e["hit"] = true


## The whole convoy stops under fire and the crews get out to fight (the gunner stays on a gun
## that can fire), pushing toward the ambush.
func _convoy_halt_all(run: Dictionary, why: String) -> void:
	for e: Dictionary in run.vehicles:
		if is_instance_valid(e.v) and not bool(e.out):
			_convoy_dismount(run, e, why)


func _convoy_dismount(run: Dictionary, e: Dictionary, why: String) -> void:
	e["out"] = true
	var v := e.v as Vehicle
	if not is_instance_valid(v):
		return
	v.server_stop()
	var keep: Soldier = v.gunner() if not v.is_burning() and not v.wrecked and not v.gun_info().is_empty() and int(v.gun_info().get("rounds", 0)) > 0 else null
	for s: Soldier in v.occupants():
		if s != keep and s.vitals.is_up():
			v.server_exit(s)
	if _squad and is_instance_valid(_squad) and run.has("oid"):
		var o := Contracts.objectives.get_objective(String(run.oid))
		if not o.is_empty():
			_squad.patrol = [_ground(_p3(o.params.pos))]
	print("[mission] convoy vehicle %s stops (%s)" % [v.vehicle_id, why])


## Host: the first cargo truck is out: its crate is on the ground beside it.
func _convoy_drop_crate(run: Dictionary, o: Dictionary, e: Dictionary) -> void:
	run["dropped"] = true
	var v := e.v as Vehicle if is_instance_valid(e.v) else null
	var p: Dictionary = o.params
	var where: Vector3 = v.global_position + v.global_basis.x * 3.2 if v else _p3(p.pos)
	var item := String(p.get("cargo", "hvt_case"))
	var id := String((p.get("cargo_ids", [""]) as Array)[0])
	if level.has_method(&"spawn_item") and id != "":
		level.call(&"spawn_item", StringName(item), 1, _ground(where) + Vector3.UP * 0.4, id, {"intel_id": id, "source": "convoy cargo"})
	print("[mission] convoy cargo %s on the ground at (%.0f, %.0f)" % [id, where.x, where.z])


## Host: a convoy that got away leaves the zone (its vehicles and crew go).
func _convoy_leave(run: Dictionary) -> void:
	run["phase"] = "left"
	for e: Dictionary in run.vehicles:
		if is_instance_valid(e.v):
			for s: Soldier in (e.v as Vehicle).occupants():
				s.queue_free()
			(e.v as Vehicle).queue_free()


## Test hook: puts every cargo truck of convoy `oid` out of action (as if destroyed).
func server_neutralize_convoy(oid: String) -> void:
	var run := run_of(oid)
	for e: Dictionary in run.get("vehicles", []):
		if bool(e.cargo) and is_instance_valid(e.v):
			(e.v as Vehicle).server_start_fire(1.0)


# --- Hold the line -----------------------------------------------------------------------------

func _hold_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	var pos := _p3(p.pos)
	var radius := float(p.radius)
	var friends := 0
	for s: Soldier in _friendlies():
		if Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= radius:
			friends += 1
	var foes := _hostiles_near(pos, radius)
	if friends > 0:
		run.started = true
		run.clock += dt
		run.lose_s = 0.0
		run.away_s = 0.0
	elif bool(run.started):
		run.away_s += dt
		run.lose_s = float(run.lose_s) + dt if foes > 0 else 0.0
	if bool(run.started):
		while float(run.clock) >= float(p.first_wave_s) + float(p.gap_s) * int(run.wave):
			if not run.has("waves"):
				run["waves"] = []
			run.waves.append_array(_send_wave(pos, int(run.wave), int(p.dirs), float(p.bearing), float(p.approach_m)))
			run.wave += 1
	if float(run.clock) >= float(p.hold_s):
		_mark(run, o, Objectives.DONE, "held")
		return
	if float(run.lose_s) >= LOSE_S:
		_mark(run, o, Objectives.FAILED, "the %s fell" % String(p.get("name", "position")))
		return
	if float(run.away_s) >= ABANDON_S:
		_mark(run, o, Objectives.FAILED, "abandoned")
		return
	var text := _progress(run, o)
	if foes > 0 and bool(run.started):
		text += ", %d hostile%s in it" % [foes, "" if foes == 1 else "s"]
	_mark(run, o, Objectives.ACTIVE, text)


# --- Downed crew rescue ------------------------------------------------------------------------

## Host: the wreck (the UH-60 model, a wreck) and its crew, some of them hurt. A client escort
## ("wreck": false) has no wreck, its one person labelled "Client", and its ambush team sent to
## lie in wait off the route out ("ambush", "ambush_men").
func _rescue_spawn(run: Dictionary, o: Dictionary) -> void:
	var p: Dictionary = o.params
	var site := _ground(_p3(p.pos))
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	if p.has("ambush"):
		var r := _reinforcements()
		var at := _ground(_p3(p.ambush))
		if r:
			run["ambush"] = r.server_send(at, 0, int(p.get("ambush_men", 4)), at)
			print("[mission] escort ambush: %d at (%.0f, %.0f)" % [(run.ambush as Array).size(), at.x, at.z])
	if layer and bool(p.get("wreck", true)):
		var wreck := layer.server_spawn(WRECK_MODEL, Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), site), "", &"friendly", "", {"wrecked": true})
		if wreck:
			wreck.set_meta(&"no_save", true)
			run["wreck"] = wreck
	var people := PeopleLayer.find(self)
	if people == null:
		return
	var crew: Array = p.get("crew", [])
	for i in crew.size():
		var c: Dictionary = crew[i]
		var a := TAU * float(i) / float(maxi(crew.size(), 1)) + float(p.get("yaw", 0.0))
		var at := _ground(site + Vector3(cos(a), 0.0, sin(a)) * CREW_RING_M)
		var s := people.server_spawn_person({"name": ("Person_" + String(c.hvt)).validate_node_name(), "kind": "hvt", "side": "friendly",
			"label": "%s (%s)" % [String(p.get("label", "Crew")), String(c.name)], "pos": at, "hvt_id": String(c.hvt)})
		if s == null:
			continue
		match String(c.get("wound", "none")):
			"leg":
				for k in 2:
					s.vitals.server_hit(Vitals.SHIN_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
			"arm":
				s.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
		(run.crew as Array).append(s)
	print("[mission] downed crew: %d at (%.0f, %.0f)" % [(run.crew as Array).size(), site.x, site.z])


func _rescue_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	run.t += dt
	var pos := _p3(p.pos)
	var escort := String(p.get("scenario", "")) == ScenarioGen.ESCORT
	if escort:
		var client: Soldier = (run.crew as Array)[0] if not (run.crew as Array).is_empty() and is_instance_valid(run.crew[0]) else null
		if client:
			pos = client.global_position  # the waves come after the client, wherever the squad has taken him
			if client.vitals.injury() > 0.0:
				_fail_unhurt(run)
	while float(run.t) >= float(p.first_wave_s) + float(p.gap_s) * int(run.wave):
		if not run.has("waves"):
			run["waves"] = []
		run.waves.append_array(_send_wave(pos, int(run.wave), 3, float(p.get("yaw", 0.0)) + 0.7, float(p.approach_m)))
		run.wave += 1


## A client escort's "out without a scratch" bonus fails the moment the client is hurt.
func _fail_unhurt(run: Dictionary) -> void:
	if bool(run.get("hurt", false)):
		return
	run["hurt"] = true
	for o: Dictionary in Contracts.objectives.for_contract(String(run.cid)):
		if o.kind == Objectives.RESCUE_CREW and bool((o.params as Dictionary).get("unhurt", false)) and o.state == Objectives.ACTIVE:
			Contracts.objectives.server_set_state(String(o.oid), Objectives.FAILED, "the client was hurt")


# --- Recon -------------------------------------------------------------------------------------

func _recon_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	var pos := _p3(p.pos)
	var points := sight_points(o)
	var seen := false
	for s: Soldier in _friendlies():
		var d := s.global_position.distance_to(pos)
		if d > float(p.observe_m):
			continue
		var eye := s.global_position + Vector3.UP * 1.6
		for to: Vector3 in points:
			if _line_of_sight(eye, to):
				seen = true
				break
		if seen:
			break
	if seen:
		run.dwell += dt
	if float(run.dwell) >= float(p.dwell_s):
		_mark(run, o, Objectives.DONE, "observed")
	else:
		_mark(run, o, Objectives.ACTIVE, _progress(run, o))


## Where eyes on a recon site may fall (Captain, 2026-10-21, a forward observer's area: "im in the
## area observing it but nothing"): its middle, the forward observer's targets about it (a vehicle
## or a weapon pit: its own contract's FIRE_TARGETs, chest high), and SIGHT_RING points round it
## SIGHT_RING_M out. Before, only the middle counted, 2 m up, and a compound's walls or a building
## round it hid it from every post however well the squad saw the area.
const SIGHT_RING := 6
const SIGHT_RING_M := 25.0
func sight_points(o: Dictionary) -> Array[Vector3]:
	var p: Dictionary = o.params
	var pos := _p3(p.pos)
	var out: Array[Vector3] = [_ground(pos) + Vector3.UP * 2.0]
	for t: Dictionary in Contracts.objectives.for_contract(String(o.get("cid", ""))):
		if String(t.kind) == Objectives.FIRE_TARGET and (t.params as Dictionary).has("pos"):
			out.append(_ground(_p3(t.params.pos)) + Vector3.UP * 1.2)
	for k in SIGHT_RING:
		var a := TAU * k / SIGHT_RING
		out.append(_ground(pos + Vector3(cos(a), 0.0, sin(a)) * SIGHT_RING_M) + Vector3.UP * 1.5)
	return out


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := get_viewport().find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return space.intersect_ray(query).is_empty()


## Test hook: the recon site `oid` has been observed.
func server_mark_site(oid: String) -> void:
	var o := Contracts.objectives.get_objective(oid)
	if not o.is_empty() and o.kind == Objectives.RECON_SITE:
		Contracts.objectives.server_set_state(oid, Objectives.DONE, "observed")


# --- Never spotted -----------------------------------------------------------------------------

func _unseen_tick(run: Dictionary, o: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or s.faction != &"hostile" or s.is_queued_for_deletion() or not s.vitals.is_up():
			continue
		var brain := SquadAI.of(s)
		if brain and brain.in_contact() and brain.target != null and brain.target.faction == &"friendly":
			_mark(run, o, Objectives.FAILED, "spotted")
			return


## Test hook: somebody spotted the squad (every "never spotted" bonus is gone).
func server_spotted() -> void:
	for oid: String in runs.keys():
		if String(runs[oid].kind) == Objectives.UNDETECTED:
			Contracts.objectives.server_set_state(oid, Objectives.FAILED, "spotted")


# --- Sabotage: a vehicle park (mission variety, 2026-10-20) ------------------------------------
## Sabotage's vehicle park (Objectives.DESTROY_VEHICLES, contracts.json module site "park"): its
## "vehicles" parked side by side "spacing_m" apart about "pos", facing "yaw_deg", when the
## contract goes live: empty and hostile, out of the zone save while whole (a wreck stays). Done
## when every one burns, is a wreck or can't drive (a charge set on each: Charges rides it and
## calls Vehicle.server_explosion; rockets and fire do as well). Kept apart from _on_live and its
## runs above (its own handlers) so it merges cleanly with their checkpoints.
##
## The objective's params keep "ids" (the vehicles', given when first parked) and "down" (those
## out of action), so a squad back in the zone (contract_returned) finds the same park: the ones
## still whole parked again, a wreck back from the zone save. Run keys: "kind", "oid", "cid",
## "ids", "down" (vehicle ids, strings; no node references).

func _enter_tree() -> void:
	if not Contracts.contract_live.is_connected(_on_park_live):
		Contracts.contract_live.connect(_on_park_live)
		Contracts.contract_returned.connect(_on_park_live)
	if not Contracts.contract_live.is_connected(_on_ops_live):
		Contracts.contract_live.connect(_on_ops_live)  # (missions 2: the section at the end)
		Contracts.contract_returned.connect(_on_ops_live)


func _on_park_live(_cid: String, objectives: Array) -> void:
	if not multiplayer.is_server() or level == null:
		return
	for given: Dictionary in objectives:
		if String(given.get("kind", "")) != Objectives.DESTROY_VEHICLES or runs.has(String(given.oid)) or not Objectives.here(given, level):
			continue
		var o := Contracts.objectives.get_objective(String(given.oid))
		if not o.is_empty() and o.state == Objectives.ACTIVE:
			_park_begin(o)


## Host: parks objective `o`'s vehicles (those not yet out of action) and starts its run.
func _park_begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer
	var models: Array = p.get("vehicles", [])
	if layer == null or models.is_empty():
		return
	if (p.get("ids", []) as Array).size() != models.size():
		var stamp := Time.get_ticks_msec()
		p["ids"] = range(models.size()).map(func(i: int) -> String: return ("park_%s_%d_%d" % [String(o.oid), stamp, i]).validate_node_name())
	var ids: Array = p.ids
	var down: Array = p.get("down", [])
	var yaw := float(p.get("yaw_deg", 0.0))
	var across := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT
	var spacing := float(p.get("spacing_m", 4.5))
	var centre := _p3(p.pos)
	var entries: Array = []
	for i in ids.size():
		if ids[i] in down:
			continue  # out of action already (a wreck comes back with the zone save)
		var at := _ground(centre + across * spacing * (i - (ids.size() - 1) * 0.5)) + Vector3.UP * 0.2
		entries.append({"id": String(ids[i]), "model": String(models[i]), "pos": at, "yaw": yaw, "faction": "hostile"})
	layer.server_place_parked(entries)
	for id: Variant in ids:
		var v := layer.find(String(id))
		if v and not v.wrecked:
			v.set_meta(&"no_save", true)
	var run := {"kind": Objectives.DESTROY_VEHICLES, "oid": String(o.oid), "cid": String(o.cid), "ids": ids.duplicate(), "down": down.duplicate()}
	runs[run.oid] = run
	print("[mission] vehicle park %s: %d vehicles at (%.0f, %.0f)" % [run.oid, entries.size(), centre.x, centre.z])
	_park_tick(run, o)


func _park_tick(run: Dictionary, o: Dictionary) -> void:
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	if layer == null:
		return
	var down: Array = run.down
	for id: Variant in run.ids:
		if id in down:
			continue
		var v := layer.find(String(id))
		if v == null or v.wrecked or v.is_burning() or not v.can_drive():
			down.append(id)
	o.params["down"] = down.duplicate()
	var progress := "%d of %d out of action" % [down.size(), (run.ids as Array).size()]
	_mark(run, o, Objectives.DONE if down.size() >= (run.ids as Array).size() else Objectives.ACTIVE, progress)


## The parked vehicles of park objective `oid` still in the level (tests).
func park_vehicles(oid: String) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	for id: Variant in run_of(oid).get("ids", []):
		var v := layer.find(String(id)) if layer else null
		if v:
			out.append(v)
	return out


# --- Missions 2 (2026-10-20): HVT kill, crash site, overwatch ----------------------------------
## Captain's list, 2026-10-20 (docs/missions.md "Missions 2"). Kept apart from the runs above (its
## own handler, _on_ops_live, connected in _enter_tree beside the park's) so it merges cleanly;
## its runs live in `runs` like theirs and are checkpointed by ScenarioCheckpoint (server_checkpoint,
## the deployment's "scenario_runs"): every node a run holds is under a key ScenarioCheckpoint
## keeps by identity, never by reference. Run kinds and their keys:
## - HVT_KILL ("hvt_kill", objective KILL_HVT): "t"; "crew" [the HVT, a person PeopleLayer
##   spawns, walking between the module's buildings: the type's "hvt_knobs" "routine_sites"];
##   "ambush" [his guard detail, hostiles of their own squad (_guard_squad_name) who keep close to
##   him]. The kill and its proof complete through the People ledger (Objectives.server_hvt_lost,
##   server_hvt_delivered) and extraction (server_items_out: his ID papers).
## - ScenarioGen.CRASH ("crash", the flight recorder's EXTRACT_ITEM): "t", "wave", "next_s" (when
##   the next wave comes), "waves" [their soldiers], "wreck" (the aircraft, a wreck). The recorder
##   and the crew's tags lie by the wreck (WorldItems by their params' "box_uid"/"tags_uid", put
##   there again on a return only when gone and not picked up). The wreck denied: a charge
##   (Objectives.server_charge_blast, DESTROY_WRECK).
## - ScenarioGen.OVERWATCH ("overwatch", the main OVERWATCH objective): "t", "phase" ("waiting",
##   "rolling"), "on_s" (ours on the position, waiting), "away_s" (nobody of ours on it, rolling),
##   "through" (trucks out the far end), "route", "vehicles" [the friendly convoy, as the enemy
##   convoy's entries: "v", "crew", "out", "hit", "down"; a truck through is "out" and "down"],
##   "ambush" [the teams lying in wait]. Its bonuses (OVERWATCH "bonus_only") have no runs: this
##   one settles them.

const HVT_KILL := "hvt_kill"
## An HVT's guards follow him once he has walked this far from where they last made for (m).
const GUARD_FOLLOW_M := 6.0
## Overwatch: nobody of ours on the position this long while the convoy rolls loses its bonus (s).
const OVERWATCH_AWAY_S := 30.0
## The overwatch position moves onto the highest ground in a grid this many points a side.
const HIGH_GROUND_GRID := 7


## The run kind objective `o` starts (missions 2), "" for none.
static func _ops_kind(o: Dictionary) -> String:
	var p: Dictionary = o.get("params", {})
	match String(o.get("kind", "")):
		Objectives.KILL_HVT:
			return HVT_KILL
		Objectives.EXTRACT_ITEM:
			return ScenarioGen.CRASH if String(p.get("scenario", "")) == ScenarioGen.CRASH else ""
		Objectives.OVERWATCH:
			return "" if bool(p.get("bonus_only", false)) else ScenarioGen.OVERWATCH
	return ""


func _on_ops_live(_cid: String, objectives: Array) -> void:
	if not multiplayer.is_server() or level == null:
		return
	for given: Dictionary in objectives:
		var kind := _ops_kind(given)
		if kind == "" or String(runs.get(String(given.oid), {}).get("kind", "")) == kind or not Objectives.here(given, level):
			continue  # (a run of another kind under its oid is a stale one: an older campaign's, its oid given out again)
		var o := Contracts.objectives.get_objective(String(given.oid))
		if o.is_empty() or o.state != Objectives.ACTIVE:
			continue
		var saved: Dictionary = Campaign.section(&"contracts").get("deployment", {}).get("scenario_runs", {}).get(String(o.oid), {})
		if saved.is_empty():
			match kind:
				HVT_KILL:
					_hvt_begin(o)
				ScenarioGen.CRASH:
					_crash_begin(o)
				ScenarioGen.OVERWATCH:
					_overwatch_begin(o)
		else:
			runs[String(o.oid)] = ScenarioCheckpoint.restore(self, saved)
			_ops_restored(runs[String(o.oid)], o)


func _ops_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	match String(run.kind):
		HVT_KILL:
			_hvt_tick(run, o, dt)
		ScenarioGen.CRASH:
			_crash_tick(run, o, dt)
		ScenarioGen.OVERWATCH:
			_overwatch_tick(run, o, dt)


## A run back from its checkpoint (ScenarioCheckpoint brings its soldiers back in the convoy
## crews' squad): each soldier in its own squad again, the HVT on his walk, the crash site's
## items and the convoy's crews as they were.
func _ops_restored(run: Dictionary, o: Dictionary) -> void:
	match String(run.kind):
		HVT_KILL:
			var guards := _ops_squad(_guard_squad_name(run), &"hostile")
			for g: Variant in run.get("ambush", []):
				if is_instance_valid(g) and SquadAI.of(g as Soldier):
					SquadAI.of(g as Soldier).squad = guards
			var hvt := _hvt_of(run)
			var brain := hvt.get_node_or_null(NodePath(PeopleLayer.BRAIN)) if hvt else null
			if brain:
				brain.set(&"routine", _hvt_routine(o))
		ScenarioGen.CRASH:
			_aim_waves(_p3(o.params.pos))
			_crash_items(o)
		ScenarioGen.OVERWATCH:
			var element := _ops_squad(_element_squad_name(run), &"friendly")
			for e: Dictionary in run.get("vehicles", []):
				var v := e.v as Vehicle if is_instance_valid(e.get("v")) else null
				for s: Variant in e.crew:
					if is_instance_valid(s):
						_element_crewman(s as Soldier, v, element)


## A squad of this node's (`squad_name`, made the first time) for `faction`.
func _ops_squad(squad_name: String, faction: StringName) -> Squad:
	var sq := get_node_or_null(NodePath(squad_name.validate_node_name())) as Squad
	if sq == null:
		sq = Squad.new()
		sq.name = squad_name.validate_node_name()
		sq.faction = faction
		add_child(sq)
	return sq


## A soldier of squad `sq`'s side (hostile in the enemy's uniform, friendly in the company's
## kit), its brain in that squad.
func _ops_soldier(sq: Squad, soldier_name: String, at: Vector3, combat: float) -> Soldier:
	var hostile := sq.faction == &"hostile"
	var loadout: Variant = level.get(&"HOSTILE_LOADOUT" if hostile else &"PMC_LOADOUT")
	var s: Soldier = level.call(&"spawn_soldier", {"name": soldier_name.validate_node_name(), "faction": String(sq.faction),
		"variant": "urban" if hostile else Soldier.COMPANY_VARIANT, "pos": at + Vector3.UP * 0.5,
		"loadout": loadout if loadout is Array else Reinforcements.LOADOUT, "combat": clampf(combat, 0.2, 0.9), "discipline": 0.5, "guard": false, "mode": "aware"})
	if s and SquadAI.of(s):
		SquadAI.of(s).squad = sq
	return s


# HVT kill ----------------------------------------------------------------------------------------

func _guard_squad_name(run: Dictionary) -> String:
	return "HvtGuards_" + String(run.oid)


func _hvt_of(run: Dictionary) -> Soldier:
	var crew: Array = run.get("crew", [])
	return crew[0] as Soldier if not crew.is_empty() and is_instance_valid(crew[0]) and not (crew[0] as Soldier).is_queued_for_deletion() else null


## The type's "hvt_knobs" for objective `o`'s contract.
static func _hvt_knobs(o: Dictionary) -> Dictionary:
	return MissionRegistry.type_def(String(Contracts.contract(String(o.cid)).get("type", ""))).get("hvt_knobs", {})


## Where the HVT of objective `o` walks: his own spot first, then the module's other indoor
## sites the type names ("routine_sites": the intel's, the documents', the hostage's rooms), in
## the level.
func _hvt_routine(o: Dictionary) -> Array:
	var c := Contracts.contract(String(o.cid))
	var module_type := String(c.get("module", ""))
	var origin := Contracts.module_origin(c)
	var out: Array = []
	for site_id: Variant in _hvt_knobs(o).get("routine_sites", ["hvt"]):
		var site := MissionRegistry.site(module_type, String(site_id))
		if not site.has("pos"):
			continue
		var q: Array = site.pos
		var at := origin + Vector3(float(q[0]), float(q[1]), float(q[2]))
		if out.all(func(x: Vector3) -> bool: return x.distance_to(at) > 3.0):
			out.append(at)
	return out


## Host: the HVT of objective `o` (his ID papers and phone on him, his walk between the
## buildings) and his guard detail ("guards" of them round him, of the contract's true quality).
func _hvt_begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var run := {"kind": HVT_KILL, "oid": String(o.oid), "cid": String(o.cid), "t": 0.0, "crew": [], "ambush": []}
	runs[run.oid] = run
	var people := PeopleLayer.find(self)
	var hvt_id := String(p.get("hvt", ""))
	if people == null or hvt_id == "" or People.is_delivered(hvt_id):
		print("[mission] HVT kill %s: no HVT to put in (%s)" % [run.oid, "no people layer" if people == null else "delivered already" if hvt_id != "" else "no HVT id"])
		return
	var s := people.hvt(hvt_id)
	if s == null:
		var person: Dictionary = p.get("person", {})
		var spawn := {"name": ("Person_" + hvt_id).validate_node_name(), "kind": "hvt", "side": String(person.get("side", Person.HOSTILE)),
			"label": String(person.get("label", "HVT")), "pos": _p3(p.pos), "hvt_id": hvt_id, "routine": _hvt_routine(o)}
		if person.has("role"):
			spawn["look_role"] = String(person.role)  # a faction's named leader dresses for his part (as PeopleLayer's HVTs)
		s = people.server_spawn_person(spawn)
		if s == null:
			print("[mission] HVT kill %s: the HVT didn't spawn" % run.oid)
			return
		for carried: Dictionary in person.get("intel", []):
			s.inventory.take(StringName(carried.id), 1, {"intel_id": String(carried.intel_id), "source": "HVT %s" % s.display_name()})
	run.crew = [s]
	var knobs := _hvt_knobs(o)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(o.oid), "guards"])
	var range_n: Array = knobs.get("guards", [2, 4])
	var n := rng.randi_range(int(range_n[0]), int(range_n[1]))
	var ring := float(knobs.get("guard_ring_m", 2.5))
	var quality := float(Contracts.enemy_force(String(o.cid)).get("quality", 0.5))
	var guards := _ops_squad(_guard_squad_name(run), &"hostile")
	for i in n:
		var a := TAU * float(i) / float(maxi(n, 1))
		var g := _ops_soldier(guards, "HvtGuard_%s_%d" % [String(o.oid), i + 1], _ground(s.global_position + Vector3(cos(a), 0.0, sin(a)) * ring), quality + 0.1)
		if g:
			(run.ambush as Array).append(g)
	guards.patrol = [_ground(s.global_position)]
	print("[mission] HVT %s at (%.0f, %.0f) with %d guards" % [s.display_name(), s.global_position.x, s.global_position.z, (run.ambush as Array).size()])


func _hvt_tick(run: Dictionary, _o: Dictionary, dt: float) -> void:
	run.t += dt
	var hvt := _hvt_of(run)
	if hvt == null or not hvt.vitals.is_up():
		return
	var guards := get_node_or_null(NodePath(_guard_squad_name(run).validate_node_name())) as Squad
	if guards and (guards.patrol.is_empty() or Vector2(guards.patrol[0].x - hvt.global_position.x, guards.patrol[0].z - hvt.global_position.z).length() > GUARD_FOLLOW_M):
		guards.patrol = [_ground(hvt.global_position)]  # his detail keeps with him as he walks between the buildings


# Crash site --------------------------------------------------------------------------------------

## Host: the wreck (a wreck of the params' "model"), the flight recorder and the crew's tags by it;
## the waves aimed at the site.
func _crash_begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var run := {"kind": ScenarioGen.CRASH, "oid": String(o.oid), "cid": String(o.cid), "t": 0.0, "wave": 0, "next_s": float(p.get("first_wave_s", 150.0)), "waves": []}
	runs[run.oid] = run
	_aim_waves(_p3(p.pos))
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer:
		var wreck := layer.server_spawn(String(p.get("model", WRECK_MODEL)), Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), _ground(_p3(p.pos))),
			"", &"friendly", "", {"wrecked": true})
		if wreck:
			wreck.set_meta(&"no_save", true)  # (a wreck is saved with the zone all the same: VehicleLayer.records)
			run["wreck"] = wreck
	_crash_items(o)
	print("[mission] crash site: a %s down at (%.0f, %.0f)" % [String(p.get("aircraft", "aircraft")), float(p.pos[0]), float(p.pos[2])])


## The flight recorder and the crew's tags by the wreck, unless they're there already or were picked up.
func _crash_items(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var site := _p3(p.pos)
	var turn := Basis(Vector3.UP, float(p.get("yaw", 0.0)))
	for piece: Array in [[String(p.get("box_uid", "")), ScenarioGen.BLACK_BOX, Vector3(4.0, 0, 1.5)], [String(p.get("tags_uid", "")), ScenarioGen.CREW_TAGS, Vector3(-3.0, 0, 2.5)]]:
		var uid: String = piece[0]
		if uid == "" or GameState.is_looted(uid) or _world_item(uid) != null or not level.has_method(&"spawn_item"):
			continue
		level.call(&"spawn_item", StringName(String(piece[1])), 1, _ground(site + turn * (piece[2] as Vector3)) + Vector3.UP * 0.3, uid, {"source": "crash site"})


func _world_item(uid: String) -> WorldItem:
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := n as WorldItem
		if item and item.uid == uid and not item.is_queued_for_deletion():
			return item
	return null


func _crash_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	run.t += dt
	while float(run.t) >= float(run.next_s):
		if not run.has("waves"):
			run["waves"] = []
		run.waves.append_array(_send_wave(_p3(p.pos), int(run.wave), 3, float(p.get("yaw", 0.0)) + 1.1, float(p.get("approach_m", 260.0))))
		run.next_s = float(run.next_s) + maxf(float(p.get("gap_min_s", 75.0)), float(p.get("gap_s", 150.0)) - float(p.get("gap_step_s", 15.0)) * int(run.wave))
		run.wave += 1
	if int(run.wave) > 0:
		_mark(run, o, Objectives.ACTIVE, "the enemy is converging on the site (%d wave%s)" % [int(run.wave), "" if int(run.wave) == 1 else "s"])


# Overwatch ---------------------------------------------------------------------------------------

func _element_squad_name(run: Dictionary) -> String:
	return "Element_" + String(run.oid)


## A friendly convoy's crewman: not a squadmate (no slot, no squad orders: CompoundLevel._squad_ai
## and Squad.members skip a vehicle's crew), nor one of ours at the debrief (Contracts.report_from_level).
func _element_crewman(s: Soldier, v: Vehicle, element: Squad) -> void:
	s.set_meta(&"vehicle_crew", v.vehicle_id if v else "element")
	s.set_meta(&"allied_element", true)
	if SquadAI.of(s):
		SquadAI.of(s).squad = element


## Host: the run waits for the squad on the position (moved onto the highest ground about it
## first) with the ambush teams out by the road.
func _overwatch_begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var route := PackedVector3Array()
	for point: Variant in p.get("route", []):
		route.append(_ground(Vector3(float(point[0]), 0.0, float(point[2]))))
	var run := {"kind": ScenarioGen.OVERWATCH, "oid": String(o.oid), "cid": String(o.cid), "t": 0.0, "phase": "waiting", "on_s": 0.0, "away_s": 0.0,
		"through": 0, "route": route, "vehicles": [], "ambush": []}
	runs[run.oid] = run
	_high_ground(o)
	var r := _reinforcements()
	if r:
		for a: Dictionary in p.get("ambushes", []):
			var at := _ground(_p3(a.pos))
			(run.ambush as Array).append_array(r.server_send(at, 0, int(a.get("men", 3)), at))
	print("[mission] overwatch %s: position at (%.0f, %.0f), %d lying in wait by the road" % [run.oid, float(p.pos[0]), float(p.pos[2]), (run.ambush as Array).size()])
	_mark(run, o, Objectives.ACTIVE, _overwatch_progress(run, o))


## The overwatch position of objective `o` (and its bonuses') onto the highest ground within
## "search_m" of where ScenarioGen put it, once.
func _high_ground(o: Dictionary) -> void:
	var p: Dictionary = o.params
	if bool(p.get("refined", false)) or not level.has_method(&"ground_height"):
		return
	var c := _p3(p.pos)
	var reach := float(p.get("search_m", 120.0))
	var area: Rect2 = level.call(&"ground_area") if level.has_method(&"ground_area") else Rect2(c.x - reach, c.z - reach, reach * 2.0, reach * 2.0)
	var best := Vector3(c.x, float(level.call(&"ground_height", c.x, c.z)), c.z)
	var half := (HIGH_GROUND_GRID - 1) / 2
	for ix in range(-half, half + 1):
		for iz in range(-half, half + 1):
			var q := Vector2(c.x + ix * reach / half, c.z + iz * reach / half)
			if not area.grow(-40.0).has_point(q):
				continue
			var h := float(level.call(&"ground_height", q.x, q.y))
			if h > best.y + 0.5:
				best = Vector3(q.x, h, q.y)
	var at := [snappedf(best.x, 0.1), snappedf(best.y, 0.1), snappedf(best.z, 0.1)]
	for other: Dictionary in Contracts.objectives.for_contract(String(o.cid)):
		if String(other.kind) == Objectives.OVERWATCH:
			other.params["pos"] = at.duplicate()
			other.params["refined"] = true
			other["pos"] = at.duplicate()


func _overwatch_progress(run: Dictionary, o: Dictionary) -> String:
	var p: Dictionary = o.params
	if String(run.phase) == "waiting":
		if float(run.on_s) > 0.0:
			return "in position: the convoy is getting ready"
		return "get to the overwatch position (the convoy rolls in %d min at the latest)" % ceili(maxf(float(p.get("depart_s", 600.0)) - float(run.t), 0.0) / 60.0)
	var lost := (run.vehicles as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("down", false))).size() - int(run.through)
	return "rolling: %d of %d through%s" % [int(run.through), (run.vehicles as Array).size(), (", %d lost" % lost) if lost > 0 else ""]


func _overwatch_tick(run: Dictionary, o: Dictionary, dt: float) -> void:
	var p: Dictionary = o.params
	run.t += dt
	var pos := _p3(p.pos)
	var on := 0
	for s: Soldier in _friendlies():
		if not s.has_meta(&"vehicle_crew") and Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= float(p.get("radius", 30.0)):
			on += 1
	if String(run.phase) == "waiting":
		if on > 0:
			run.on_s += dt
		if float(run.on_s) >= float(p.get("set_s", 20.0)) or float(run.t) >= float(p.get("depart_s", 600.0)):
			_overwatch_spawn(run, o)
			run.phase = "rolling"
			Contracts._notify_all("Radio, convoy: rolling now. Eyes on the road.")
		_mark(run, o, Objectives.ACTIVE, _overwatch_progress(run, o))
		return
	run.away_s = 0.0 if on > 0 else float(run.away_s) + dt
	if float(run.away_s) >= OVERWATCH_AWAY_S:
		_overwatch_bonus(run, "held", Objectives.FAILED, "left the position")
	var route: PackedVector3Array = run.route
	var end := route[route.size() - 1] if not route.is_empty() else Vector3.ZERO
	for e: Dictionary in run.vehicles:
		if bool(e.get("down", false)):
			continue
		var v := e.v as Vehicle if is_instance_valid(e.get("v")) else null
		if v == null or v.is_queued_for_deletion():
			e["down"] = true
		elif _neutralized(e, v):
			e["down"] = true
			v.server_stop()
			for s: Soldier in v.occupants():
				if s.vitals.is_up():
					v.server_exit(s)  # stranded: they get out and fight where they stopped
			print("[mission] overwatch: convoy truck %s lost" % v.vehicle_id)
		elif Vector2(v.global_position.x - end.x, v.global_position.z - end.z).length() <= ESCAPE_M:
			e["down"] = true
			e["out"] = true
			run.through += 1
			for s: Variant in e.crew:
				if is_instance_valid(s):
					(s as Soldier).queue_free()
			v.queue_free()  # through: out of the zone
	var total := (run.vehicles as Array).size()
	var down := (run.vehicles as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("down", false))).size()
	var lost := down - int(run.through)
	var need := int(p.get("need", 1))
	if total - lost < need:
		_overwatch_bonus(run, "", Objectives.FAILED, "the convoy was lost")
		_mark(run, o, Objectives.FAILED, "the convoy was lost (%d of %d trucks)" % [lost, total])
	elif down >= total:
		_overwatch_bonus(run, "all", Objectives.DONE if int(run.through) >= total else Objectives.FAILED, "%d of %d through" % [int(run.through), total])
		_overwatch_bonus(run, "held", Objectives.DONE, "held it")
		_mark(run, o, Objectives.DONE, "%d of %d through" % [int(run.through), total])
	else:
		if lost > 0:
			_overwatch_bonus(run, "all", Objectives.FAILED, "a truck was lost")
		_mark(run, o, Objectives.ACTIVE, _overwatch_progress(run, o))


## Settles run `run`'s still-open bonuses: "all" (every truck through), "held" (on the position
## till it's through), or "" both.
func _overwatch_bonus(run: Dictionary, which: String, state: String, progress: String) -> void:
	for b: Dictionary in Contracts.objectives.for_contract(String(run.cid)):
		var bp: Dictionary = b.get("params", {})
		if String(b.kind) != Objectives.OVERWATCH or not bool(bp.get("bonus_only", false)) or String(b.state) != Objectives.ACTIVE:
			continue
		var held := bool(bp.get("held", false))
		if which == "" or (which == "held") == held:
			Contracts.objectives.server_set_state(String(b.oid), state, progress)


## Host: the friendly convoy on the route's first leg and driving it, its crews aboard (the
## client's, not ours: _element_crewman).
func _overwatch_spawn(run: Dictionary, o: Dictionary) -> void:
	var p: Dictionary = o.params
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	var route: PackedVector3Array = run.route
	if layer == null or route.size() < 2:
		return
	var fwd := route[1] - route[0]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var path := PackedVector3Array()
	for k in range(1, route.size()):
		path.append(route[k])
	var element := _ops_squad(_element_squad_name(run), &"friendly")
	var trucks: Array = p.get("trucks", ["matv"])
	var tag := absi(hash(String(run.oid))) % 10000
	for i in trucks.size():
		var at := _ground(route[0] - fwd * SPACING_M * i)
		var v := layer.server_spawn(String(trucks[i]), Transform3D(Basis.looking_at(fwd, Vector3.UP), at), "", &"friendly", "")
		if v == null:
			continue
		v.set_meta(&"no_save", true)
		var e := {"v": v, "cargo": false, "crate": false, "crew": [], "out": false, "hit": false, "down": false}
		var seats := VehicleQrf._seat_order(v)
		for si in mini(seats.size(), maxi(int(p.get("crew", 2)), 1)):
			var s := _ops_soldier(element, "OW%d_%d_%d" % [tag, i + 1, si + 1], at, 0.55)
			if s == null:
				continue
			_element_crewman(s, v, element)
			if v.server_enter(s, int(seats[si])):
				(e.crew as Array).append(s)
			else:
				s.queue_free()
		AavGunner.attach(v)
		v.damaged.connect(_on_convoy_hit.bind(e))
		run.vehicles.append(e)
		v.server_follow_path(path, float(p.get("speed_kmh", 24.0)))
	print("[mission] overwatch %s: the convoy sets out, %d trucks" % [run.oid, (run.vehicles as Array).size()])
