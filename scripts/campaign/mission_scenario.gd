class_name MissionScenario
extends Node
## Plays the scenario mission types in the level (mission variety, 2026-10-15; docs/missions.md):
## convoy ambush, hold the line, downed crew rescue, recon and the "never spotted" bonus. Host
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
				if o.kind in [Objectives.HOLD_POINT, Objectives.RESCUE_CREW]:
					_aim_waves(_p3(o.params.pos))
				if is_instance_valid(_squad) and (o.kind != Objectives.CONVOY or (runs[String(o.oid)].get("vehicles", []) as Array).any(func(e: Dictionary) -> bool: return bool(e.out))):
					_squad.patrol = [_ground(_p3(o.params.pos))]
	server_checkpoint()


## The deployment owns checkpoints across zones; only this level's runs are updated here.
func server_checkpoint() -> void:
	if not multiplayer.is_server():
		return
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
	var eye_to := _ground(pos) + Vector3.UP * 2.0
	var seen := false
	for s: Soldier in _friendlies():
		var d := s.global_position.distance_to(pos)
		if d <= float(p.observe_m) and _line_of_sight(s.global_position + Vector3.UP * 1.6, eye_to):
			seen = true
			break
	if seen:
		run.dwell += dt
	if float(run.dwell) >= float(p.dwell_s):
		_mark(run, o, Objectives.DONE, "observed")
	else:
		_mark(run, o, Objectives.ACTIVE, _progress(run, o))


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
