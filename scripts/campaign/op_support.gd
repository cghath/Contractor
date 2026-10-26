class_name OpSupport
extends OpBase
## What every operation type brings with it (docs/combined_arms.md 6.1, 6.4; cg_brief queue item
## 3.3, closing F-288 and F-292): attached armour, allied fires, the battlegroup's trucks and its
## medevac. One node, "Support", under every operation zone's Operations node on every peer.
##
## - Attached armour (6.1): the contract's "attached" vehicles (a Bradley section on an armoured
##   thrust, an Abrams section on a phased invasion) come out at the start line at H-hour with an
##   allied crew (a driver and a gunner, and a loader on the Abrams: the commander's seat, and the
##   Bradley's troop seats, are left for players to climb into). Until A9's crews they use what the
##   AI has today: their drivers drive by road (SquadDrivers), their gunners fire the coax
##   (AavGunner). Their orders are the company's (Support > Operation > Attached armour): follow the
##   company's task (the default: overwatch "overwatch_short_m" short of the task's objective on our
##   side, moving up as each phase begins), move there, hold, follow me; a player aboard can take the
##   gun from the AI gunner and give it back. A vehicle lost is the employer's loss (no indemnity),
##   said in the debrief; they go back after the operation (never saved with the zone).
## - Allied fires (6.1): the contract's "allied_fires" rounds ({"mortar", "artillery", "naval"}),
##   fired by the employer's guns (FireSupport.server_allied_fire: the battlegroup's mortar section
##   from its tubes in the zone, its battery and naval gunfire from off the map): the type's
##   preparation fires on its phases' objectives ("prep"), the allied commander's own calls (its
##   fire_support_wanted: smoke for a breach, HE else), and the company's calls (Support > Operation
##   > Allied fires: three rounds there, "call_cooldown_s" apart). Never danger close to friendlies;
##   the mortars stop when the section's tubes are gone. The enemy's mortar answers its commander's
##   calls (a counterattack's preparation) while its mortar team stands.
## - The trucks (F-292): OOB entries with "logistics" ("ammo", "fuel"; MaxxPros stand in for the
##   HEMTTs until D6a) drive up to the logistics point (the MSR "logistics_back_m" short of the last
##   phase line taken) and rearm or refuel the allied and attached vehicles within "serve_m" of them,
##   every "serve_s".
## - The medevac (F-292): a type's "medevac" calls: the company's Medevac (Dustoff) calls are the
##   employer's while any are left (Economy.server_pay_support asks employer_pays()).
## Numbers in data/operations.json "support", all Proposed.

const NODE_NAME := "Support"
const ATTACHED_META := &"op_attached"
## Company orders for the attached armour.
const FOLLOW_TASK := "task"
const MOVE := "move"
const HOLD := "hold"
const FOLLOW := "follow"
const COLUMN := "column"  # OpThrust drives it

var _tick_left := 0.0
var _vehicles := {}  # host: attached id -> Vehicle
var _reseat: Array = []  # host: {"ai", "vehicle", "seat", "until"}
var _called := {}  # host: unit -> when the company last called it


static func of(from: Node) -> OpSupport:
	var o := Operations.of(from)
	return o.get_node_or_null(NODE_NAME) as OpSupport if o else null


func _ready() -> void:
	super._ready()
	for cmd: String in ["op_attached", "op_fire"]:
		Supports.register(cmd, Callable(self, "_cmd_" + cmd))


func data_support(key: String, fallback := 0.0) -> float:
	return float((Operations.data().get("support", {}) as Dictionary).get(key, fallback))


# --- The run (host) ------------------------------------------------------------------------------------

func start() -> void:
	var m := mine()
	var c := contract()
	if not m.has("attached"):
		var list: Array = []
		var axis := ops._axis()
		var left := Vector2(-axis.y, axis.x)
		var start_p := Vector2(float((ops.def.op.start as Array)[0]), float((ops.def.op.start as Array)[1]))
		var k := 0
		for a: Dictionary in c.get("attached", []):
			for i in int(a.get("count", 1)):
				var p := start_p - axis * float(a.get("back_m", 180.0)) + left * (float(k % 2 * 2 - 1) * (30.0 + floorf(k / 2.0) * 30.0))
				list.append({"id": "att%d" % (k + 1), "model": String(a.model), "callsign": "%s-%d" % [String(a.get("callsign", "Iron 9")), i + 1],
					"crew": (a.get("seats", ["driver", "gunner"]) as Array).duplicate(), "kit": String(a.get("kit", "")), "state": Operations.PENDING,
					"pos": [snappedf(p.x, 1.0), snappedf(p.y, 1.0)], "order": String(a.get("order", FOLLOW_TASK)), "at": []})
				k += 1
		m["attached"] = list
		var fires: Dictionary = (c.get("allied_fires", {}) as Dictionary).duplicate()
		m["fires_left"] = fires
		m["fired"] = {}
		m["prep_done"] = []
		m["medevac_left"] = int(cfg().get("medevac", 0))
		m["served"] = 0
		if not list.is_empty():
			note("Attached to the company: %s." % ", ".join(PackedStringArray(list.map(func(e: Dictionary) -> String:
				return "%s (%s)" % [e.callsign, VehicleSpecs.spec(String(e.model)).get("name", e.model)]))))
	else:
		for e: Dictionary in m.attached:
			if String(e.state) == "live":
				e.state = Operations.PENDING  # (a loaded save: they come back where they were)
	if ops.friendly and not ops.friendly.fire_support_wanted.is_connected(_on_friendly_fires):
		ops.friendly.fire_support_wanted.connect(_on_friendly_fires)
	if ops.hostile and not ops.hostile.fire_support_wanted.is_connected(_on_hostile_fires):
		ops.hostile.fire_support_wanted.connect(_on_hostile_fires)
	_refresh_state()


func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_left -= dt
	_reseat_step()
	if _tick_left > 0.0:
		cost_us = float(Time.get_ticks_usec() - t0)
		return
	_tick_left = data_support("tick_s", 2.0)
	var r := run()
	if String(r.get("state", "")) in [Operations.RUNNING, Operations.DONE]:
		_attached_step()
		_logistics_step()
	_refresh_state()
	cost_us = float(Time.get_ticks_usec() - t0)
	if not heavy:
		worst_us = maxf(worst_us, cost_us)
	heavy = false


func phase_begun(k: int) -> void:
	_prep(k)
	for e: Dictionary in mine().get("attached", []):
		if String(e.order) == FOLLOW_TASK:
			e["moved_for"] = -1  # (moves up to the new task)


## The type's preparation fires for phase `k` (data "prep": [{"phase", "unit", "rounds", "targets":
## "objectives"|"task", "max", "shell"}]): on its known objectives only.
func _prep(k: int) -> void:
	var m := mine()
	for p: Dictionary in cfg().get("prep", []):
		if int(p.get("phase", -1)) != k or ("%d:%s" % [k, String(p.unit)]) in (m.get("prep_done", []) as Array):
			continue
		(m.prep_done as Array).append("%d:%s" % [k, String(p.unit)])
		var targets: Array = []
		var phases: Array = contract().get("phases", [])
		if k < phases.size():
			if String(p.get("targets", "objectives")) == "task":
				for t: Dictionary in phases[k].tasks:
					targets.append(v3(t.pos))
			else:
				for o: Dictionary in phases[k].objectives:
					if String(o.get("module_id", "")) != "":  # (its enemy sites: never a bridge the company is to take intact)
						targets.append(v3(o.pos))
		var fired := 0
		for at: Vector3 in targets.slice(0, int(p.get("max", 2))):
			if fire(String(p.unit), at, int(p.get("rounds", 4)), String(p.get("shell", "he")), "preparation") == "":
				fired += 1
		if fired > 0:
			say("%s: preparation fires on %d target%s for %s." % [unit_callsign(String(p.unit)), fired, "" if fired == 1 else "s",
				String(phases[k].name) if k < phases.size() else "the phase"])


# --- Allied fires (host) -------------------------------------------------------------------------------

static func unit_id(unit: String) -> String:
	return {"mortar": "allied_mortar", "artillery": "allied_artillery", "naval": "naval_gun", "enemy_mortar": "enemy_mortar"}.get(unit, unit)


func unit_callsign(unit: String) -> String:
	return String(FireMission.unit(unit_id(unit)).get("callsign", unit.capitalize()))


func fires_left(unit: String) -> int:
	return int((mine().get("fires_left", {}) as Dictionary).get(unit, 0))


## Host: `n` rounds of the operation's `unit` ("mortar", "artillery", "naval") on `at`, from its
## budget. "" when they're on their way, else why not.
func fire(unit: String, at: Vector3, n: int, shell := "he", why := "") -> String:
	var m := mine()
	var left := fires_left(unit)
	if left <= 0:
		return "%s has nothing left for this operation" % unit_callsign(unit)
	n = mini(n, left)
	var from := _gun_from(unit, at)
	if not from.is_finite():
		return "%s is out of action" % unit_callsign(unit)
	var fs := FireSupport.of(self)
	if fs == null:
		return "No guns here"
	var out := fs.server_allied_fire(unit_id(unit), at, n, shell, from)
	if out != "":
		return out
	(m.fires_left as Dictionary)[unit] = left - n
	(m.fired as Dictionary)[unit] = int((m.fired as Dictionary).get(unit, 0)) + n
	SessionLog.note("operation %s: %s fires %d %s on %s (%s), %d left" % [ops.cid, unit, n, shell, grid_ref(at), why, left - n])
	return ""


## Where `unit`'s guns fire from: the mortar section's tubes (the OOB's "mortar_section", while one
## stands; the start line before it's out), the friendly side for the battery, the sea for naval
## gunfire. INF when the unit is gone.
func _gun_from(unit: String, at: Vector3) -> Vector3:
	match unit:
		"mortar":
			for e: Dictionary in run().get("oob", []):
				if String(e.side) != "friendly" or String(e.kind) != "mortar_section":
					continue
				match String(e.state):
					Operations.PENDING, "spawning":
						return v3(e.pos)
					"live":
						for v: Variant in (ops.records.get(String(e.id), {}) as Dictionary).get("vehicles", []):
							if is_instance_valid(v) and not (v as Vehicle).wrecked:
								return (v as Vehicle).global_position
				return Vector3.INF if String(e.state) in ["live", "gone"] else v3(e.pos)
			return v3(ops.def.op.get("start", [0, 0]))
		"naval":
			var lhd := Lhd.of(self)
			return lhd.global_position if lhd and lhd.is_ship() else v3(ops.def.op.get("start", [0, 0]))
		"enemy_mortar":
			var axis := ops._axis()
			return at + Vector3(axis.x, 0.0, axis.y) * data_support("enemy_mortar_back_m", 1800.0)  # (its tube on its own side, in reach)
	if level() == null:
		return v3(ops.def.op.get("start", [0, 0]))
	return Supports.origin_for(level(), &"fob", at, 0.0).origin


## The allied commander wants fires (B2's fire_support_wanted: SOSRA's smoke, a fire support role).
func _on_friendly_fires(pos: Vector3, why: String) -> void:
	var smoke := why.contains("smoke")
	for unit: String in ["mortar", "artillery"]:
		if fire(unit, pos, 3, "smoke" if smoke else "he", "the allied commander: " + why) == "":
			say_once("cmd_fire", "%s: %s on %s, %s." % [unit_callsign(unit), "smoke" if smoke else "fire mission", grid_ref(pos), why], 90.0)
			return


## The enemy's commander wants fires (a counterattack's preparation): its mortar, while its team stands.
func _on_hostile_fires(pos: Vector3, why: String) -> void:
	server_enemy_mortar(pos, int(data_support("enemy_rounds", 4)), why)


## Host: the enemy's mortar on `pos`, while a mortar team of its OOB ("weapons_team" "Mortar") stands.
func server_enemy_mortar(pos: Vector3, n: int, why := "") -> String:
	var team := false
	for e: Dictionary in run().get("oob", []):
		if String(e.side) == "hostile" and String(e.callsign).begins_with("Mortar") and String(e.state) != "gone":
			team = true
	if not team and not bool(cfg().get("enemy_mortar", false)):
		return "no enemy mortar"
	var fs := FireSupport.of(self)
	if fs == null:
		return "no guns"
	var out := fs.server_allied_fire("enemy_mortar", pos, n, "he", _gun_from("enemy_mortar", pos))
	if out == "":
		var m := mine()
		m["enemy_fired"] = int(m.get("enemy_fired", 0)) + n
		say_once("enemy_mortar", "Citadel: incoming! Enemy mortars on %s." % grid_ref(pos), 60.0)
		SessionLog.note("operation %s: the enemy's mortar, %d rounds on %s (%s)" % [ops.cid, n, grid_ref(pos), why])
	return out


# --- Attached armour (host) ----------------------------------------------------------------------------

func attached() -> Array:
	return mine().get("attached", [])


func vehicle_of(id: String) -> Vehicle:
	var v: Variant = _vehicles.get(id)
	return v as Vehicle if is_instance_valid(v) and not (v as Vehicle).is_queued_for_deletion() else null


func _attached_step() -> void:
	var spawned := false
	for e: Dictionary in attached():
		match String(e.state):
			Operations.PENDING:
				if not spawned and not BigZoneStreaming.at_cap(level(), true):
					_spawn_attached(e)  # (one a tick: a few men a frame, as Operations' own spawner, D3-12)
					spawned = true
			"live":
				var v := vehicle_of(String(e.id))
				if v == null or v.wrecked:
					continue
				e.pos = [snappedf(v.global_position.x, 1.0), snappedf(v.global_position.z, 1.0)]
				_drive_attached(e, v)


func _spawn_attached(e: Dictionary) -> void:
	var layer := VehicleLayer.of(self)
	if layer == null:
		return
	var axis := ops._axis()
	var fwd := Vector3(axis.x, 0, axis.y)
	var at := ground(v3(e.pos))
	var stream := level().get_node_or_null(NodePath(BigZoneStreaming.NODE_NAME)) as BigZoneStreaming if level() else null
	if stream:
		stream.ensure(at)
	var v := layer.server_spawn(String(e.model), Transform3D(Basis.looking_at(fwd, Vector3.UP), at + Vector3.UP * 0.4), "", &"friendly", "")
	heavy = true
	if v == null:
		return
	v.set_meta(&"no_save", true)
	v.set_meta(ATTACHED_META, String(e.id))
	_vehicles[String(e.id)] = v
	var squad := Squad.new()
	squad.name = ops._fresh_name(String(e.callsign))
	squad.faction = &"friendly"
	squad.callsign = String(e.callsign)
	ops.add_child(squad)
	var entry := {"side": "friendly", "kit": String(e.kit)}
	var i := 0
	for want: Variant in e.crew:
		var seat := _seat_of_kind(v, StringName(String(want)))
		if seat < 0:
			continue
		var s := ops._spawn_man(entry, squad, i, v.global_position + Vector3.UP * 3.0)
		i += 1
		if s == null:
			continue
		s.set_meta(&"vehicle_crew", v.vehicle_id)
		s.set_meta(&"op_allied", true)
		v.server_enter(s, seat)
	squad.leader = squad.members()[0] if not squad.members().is_empty() else null
	AavGunner.attach(v)
	v.destroyed.connect(_on_attached_lost.bind(String(e.id)))
	e.state = "live"
	e["vid"] = v.vehicle_id
	e["moved_for"] = -1
	SessionLog.note("operation %s: attached %s (%s) out at %s" % [ops.cid, String(e.callsign), String(e.model), grid_ref(at)])


static func _seat_of_kind(v: Vehicle, kind: StringName) -> int:
	if kind == Vehicle.GUNNER:
		var gun := int(v.spec.get("gun", {}).get("seat", -1))
		if gun >= 0 and v.occupant(gun) == null:
			return gun
	for i in v.seat_count():
		if v.seat_kind(i) == kind and v.occupant(i) == null:
			return i
	return -1


func _on_attached_lost(_v: Vehicle, id: String) -> void:
	for e: Dictionary in attached():
		if String(e.id) == id and String(e.state) != "lost":
			e.state = "lost"
			note("%s (%s), attached, was lost: the employer's loss." % [String(e.callsign), VehicleSpecs.spec(String(e.model)).get("name", e.model)])
			say("Citadel: %s is hit and out of action." % String(e.callsign))
	_refresh_state()


## Its order: follow the company's task (overwatch short of it), move, hold, follow a player.
func _drive_attached(e: Dictionary, v: Vehicle) -> void:
	var drivers := SquadDrivers.of(self)
	if drivers == null or v.occupant(_seat_of_kind_any(v, Vehicle.DRIVER)) == null:
		return
	match String(e.order):
		FOLLOW_TASK:
			if int(e.get("moved_for", -1)) == phase():
				return
			var to := overwatch_point(phase())
			if to.is_finite():
				e["moved_for"] = phase()
				drivers.go(v, to + _slot(e), true)
				heavy = true  # (a route planned)
		MOVE:
			if not bool(e.get("moving", false)) and (e.at as Array).size() == 2:
				e["moving"] = true
				drivers.go(v, ground(Vector3(float(e.at[0]), 0, float(e.at[1]))) + _slot(e), true)
				heavy = true
		HOLD:
			if not bool(e.get("stopped", false)):
				e["stopped"] = true
				v.server_stop()
		FOLLOW:
			var who := ops._players().filter(func(p: Node) -> bool: return String(p.name) == String(e.get("who", "")))
			if who.is_empty():
				return
			var p := (who[0] as Soldier).global_position
			if Vehicle.ride_of(who[0] as Soldier) == v:
				return
			if Vector2(p.x - v.global_position.x, p.z - v.global_position.z).length() > data_support("follow_m", 45.0):
				drivers.go(v, p + (v.global_position - p).normalized() * data_support("follow_gap_m", 25.0), true)
				heavy = true


static func _seat_of_kind_any(v: Vehicle, kind: StringName) -> int:
	for i in v.seat_count():
		if v.seat_kind(i) == kind:
			return i
	return -1


## Where the attached armour overwatches phase `k`'s company task from: overwatch_short_m short of
## its first required objective, back along the axis (our side), on the ground.
func overwatch_point(k: int) -> Vector3:
	var phases: Array = contract().get("phases", [])
	if k < 0 or k >= phases.size():
		return Vector3.INF
	var tasks: Array = (phases[k] as Dictionary).tasks
	if tasks.is_empty():
		return Vector3.INF
	var axis := ops._axis()
	var p := v3(tasks[0].pos)
	return ground(p - Vector3(axis.x, 0, axis.y) * data_support("overwatch_short_m", 300.0))


func _slot(e: Dictionary) -> Vector3:
	var axis := ops._axis()
	var left := Vector3(-axis.y, 0, axis.x)
	var i := attached().find(e)
	return left * (float(i % 2 * 2 - 1) * (25.0 + floorf(i / 2.0) * 25.0))


## Host: the company's order for every attached vehicle (`verb`: task, move, hold, follow), by `by`.
func server_order(by: Soldier, verb: String, point: Vector3) -> String:
	var live := attached().filter(func(e: Dictionary) -> bool: return String(e.state) == "live")
	if live.is_empty():
		return "No attached armour out" if not attached().is_empty() else "No armour is attached to the company on this operation"
	for e: Dictionary in live:
		if String(e.order) == COLUMN:
			continue
		e.order = verb
		e.erase("moving")
		e.erase("stopped")
		e["moved_for"] = -1
		e["at"] = [point.x, point.z] if point.is_finite() else []
		e["who"] = String(by.name) if by else ""
	_tick_left = 0.0
	var names := ", ".join(PackedStringArray(live.map(func(e: Dictionary) -> String: return String(e.callsign))))
	say("%s: %s." % [names, {FOLLOW_TASK: "moving up to overwatch the company's task", MOVE: "moving to %s" % grid_ref(point), HOLD: "holding",
		FOLLOW: "following %s" % (by.display_name() if by else "you")}.get(verb, verb)])
	_refresh_state()
	return ""


## Host: `by`, aboard an attached vehicle, takes its gun from the AI gunner (who moves to his seat).
func server_take_gun(by: Soldier) -> String:
	var v := Vehicle.ride_of(by)
	if v == null or not v.has_meta(ATTACHED_META):
		return "Get into an attached vehicle first"
	var gun := int(v.spec.get("gun", {}).get("seat", -1))
	if gun < 0:
		return "It has no gun"
	if v.occupant(gun) == by:
		return "You have the gun"
	var ai := v.occupant(gun)
	var mine_seat := v.seat_of(by)
	if ai:
		v.server_exit(ai)
	if not v.server_switch(by, gun):
		if ai:
			v.server_enter(ai, gun)
		return "Can't get to the gun from there"
	if ai:
		_reseat.append({"ai": ai, "vehicle": v, "seat": mine_seat, "until": Soldier._now() + 12.0})
	say_once("gun_%s" % v.vehicle_id, "%s: %s has the gun." % [String(v.get_meta(ATTACHED_META)), by.display_name()], 5.0)
	return ""


## Host: `by` hands the gun back: he moves to a free seat, its AI gunner back on the gun.
func server_give_gun(by: Soldier) -> String:
	var v := Vehicle.ride_of(by)
	if v == null or not v.has_meta(ATTACHED_META):
		return "Get into an attached vehicle first"
	var gun := int(v.spec.get("gun", {}).get("seat", -1))
	if v.occupant(gun) != by:
		return "You're not on its gun"
	# The crewman who took his seat (the commander's, else any but the driver and the loader) goes back on the gun.
	var crew: Soldier = null
	for s: Soldier in v.occupants():
		var k := v.seat_kind(v.seat_of(s))
		if s.has_meta(&"vehicle_crew") and k != Vehicle.DRIVER and (crew == null or k == Vehicle.COMMANDER) and k != Vehicle.LOADER:
			crew = s
	var to := -1
	for i in v.seat_count():
		if v.occupant(i) == null and i != gun and v.seat_kind(i) != Vehicle.DRIVER:
			to = i
			break
	if to < 0 and crew:
		to = v.seat_of(crew)
		v.server_exit(crew)
	if to < 0:
		return "No seat to move to"
	if not v.server_switch(by, to):
		if crew and Vehicle.ride_of(crew) == null:
			v.server_enter(crew, to)
		return "Can't move from the gun now"
	if crew:
		if Vehicle.ride_of(crew) == v:
			v.server_exit(crew)
		_reseat.append({"ai": crew, "vehicle": v, "seat": gun, "until": Soldier._now() + 12.0})
	return ""


func _reseat_step() -> void:
	for r: Dictionary in _reseat.duplicate():
		var v := r.vehicle as Vehicle
		var ai := r.ai as Soldier
		if not is_instance_valid(v) or not is_instance_valid(ai) or Soldier._now() > float(r.until):
			_reseat.erase(r)
			continue
		if v.occupant(int(r.seat)) == ai or v.server_enter(ai, int(r.seat)):
			_reseat.erase(r)


# --- The trucks (host) ---------------------------------------------------------------------------------

## The logistics point: the MSR logistics_back_m short of the last phase line taken (the start
## line before any), on the ground.
func logistics_point() -> Vector3:
	var r := run()
	var phases: Array = contract().get("phases", [])
	var line := OperationGen.band_range(ops.def, "start").y
	for k in phases.size():
		if k < (r.phases as Array).size() and String(r.phases[k].get("state", "")) == Operations.DONE:
			line = maxf(line, float(phases[k].line_m))
	var want := maxf(line - data_support("logistics_back_m", 400.0), 200.0)
	var msr: Array = ops.def.op.get("msr", [])
	var best := Vector3.INF
	var best_d := INF
	for k in range(1, msr.size()):
		var a := Vector2(float(msr[k - 1][0]), float(msr[k - 1][1]))
		var b := Vector2(float(msr[k][0]), float(msr[k][1]))
		for i in 9:
			var p := a.lerp(b, i / 8.0)
			var d := absf(OperationGen.along(ops.def, p) - want)
			if d < best_d:
				best_d = d
				best = Vector3(p.x, 0, p.y)
	return ground(best) if best.is_finite() else v3(ops.def.op.get("start", [0, 0]))


func _logistics_step() -> void:
	var drivers := SquadDrivers.of(self)
	var at := logistics_point()
	var m := mine()
	var now := clock()
	for e: Dictionary in run().get("oob", []):
		if String(e.get("logistics", "")) == "" or String(e.state) != "live":
			continue
		var rec: Dictionary = ops.records.get(String(e.id), {})
		for v: Variant in rec.get("vehicles", []):
			if not is_instance_valid(v) or (v as Vehicle).wrecked:
				continue
			var truck := v as Vehicle
			var far := Vector2(truck.global_position.x - at.x, truck.global_position.z - at.z).length()
			if far > 40.0 and drivers and String(e.get("going_to", "")) != str(at.round()):
				e["going_to"] = str(at.round())
				drivers.go(truck, at, true)
				heavy = true
				continue
			if now - float(e.get("served_at", -INF)) < data_support("serve_s", 60.0):
				continue
			e["served_at"] = now
			for other in get_tree().get_nodes_in_group(Vehicle.GROUP):
				var ov := other as Vehicle
				if ov == null or ov == truck or ov.wrecked or ov.faction != &"friendly" or not level().is_ancestor_of(ov):
					continue
				if ov.global_position.distance_to(truck.global_position) > data_support("serve_m", 50.0):
					continue
				var did := 0
				if String(e.logistics) == "ammo":
					did = ov.server_rearm()
				else:
					did = roundi(ov.server_refuel(data_support("fuel_l", 200.0)))
				if did > 0:
					m["served"] = int(m.get("served", 0)) + 1
					SessionLog.note("operation %s: %s %s %s at the logistics point" % [ops.cid, String(e.callsign), "rearmed" if String(e.logistics) == "ammo" else "refuelled", ov.display_name()])


# --- The medevac -----------------------------------------------------------------------------------------

## Host (Economy.server_pay_support): whether the deployment's operation pays for this `kind` of
## support itself (its battlegroup's medevac: the type's "medevac" calls, while any are left).
static func employer_pays(kind: String) -> bool:
	if kind != "medevac":
		return false
	for cid: Variant in Contracts.deployment().get("cids", []):
		var c := Contracts.contract(String(cid))
		if not Operations.is_operation(c) or String(c.get("state", "")) != Contracts.DEPLOYED:
			continue
		var mech: Dictionary = (Operations.run_of(c).get("mech", {}) as Dictionary).get(NODE_NAME, {})
		var left := int(mech.get("medevac_left", 0))
		if left > 0:
			mech["medevac_left"] = left - 1
			var notes: Array = Operations.run_of(c).get("notes", [])
			notes.append("The employer's Dustoff flew for the company (%d of %d calls)." % [int(Operations.type_def(String(c.op_type)).get("medevac", 0)) - left + 1,
				int(Operations.type_def(String(c.op_type)).get("medevac", 0))])
			Operations.run_of(c)["notes"] = notes
			return true
	return false


# --- The company's commands (Supports: support:op_attached:<verb>, support:op_fire:<unit>) ----------------

func _cmd_op_attached(who: Node, arg: String, point: Vector3, _names: PackedStringArray) -> String:
	var by := who as Soldier
	match arg:
		"gun":
			return server_take_gun(by)
		"crew":
			return server_give_gun(by)
		MOVE:
			return server_order(by, MOVE, point)
		HOLD, FOLLOW, FOLLOW_TASK:
			return server_order(by, arg, Vector3.INF)
	return "Order not understood"


func _cmd_op_fire(who: Node, arg: String, point: Vector3, _names: PackedStringArray) -> String:
	if not ops or not ops.active():
		return "Allied fires come with an operation"
	var unit := arg if arg in ["mortar", "artillery", "naval"] else "artillery"
	var wait := data_support("call_cooldown_s", 120.0) - (clock() - float(_called.get(unit, -INF)))
	if wait > 0.0:
		return "%s fires again in %d s" % [unit_callsign(unit), ceili(wait)]
	var out := fire(unit, point, int(data_support("call_rounds", 3)), "he", "the company's call")
	if out != "":
		return "%s: %s" % [unit_callsign(unit), out]
	_called[unit] = clock()
	say("%s: fire mission on %s, %d rounds, out. %d left for the operation." % [unit_callsign(unit), grid_ref(point), int(data_support("call_rounds", 3)), fires_left(unit)])
	return ""


# --- Every peer ---------------------------------------------------------------------------------------------

func _refresh_state() -> void:
	var list: Array = []
	for e: Dictionary in attached():
		list.append({"callsign": String(e.callsign), "model": String(e.model), "state": String(e.state), "order": String(e.order), "vid": String(e.get("vid", ""))})
	var s := {"attached": list, "fires": (mine().get("fires_left", {}) as Dictionary).duplicate()}
	if s != state:
		state = s
		publish()


func strip_line() -> String:
	return line_of(state)


## The strip's line for the attached armour and allied fires.
static func line_of(extra: Dictionary) -> String:
	var parts := PackedStringArray()
	var att: Array = extra.get("attached", [])
	if not att.is_empty():
		var up := att.filter(func(e: Dictionary) -> bool: return String(e.state) == "live").size()
		parts.append("Attached %d/%d" % [up, att.size()])
	var fires: Dictionary = extra.get("fires", {})
	for unit: String in fires:
		parts.append("%s %d" % [unit, int(fires[unit])])
	return "  ".join(parts)
