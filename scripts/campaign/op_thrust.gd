class_name OpThrust
extends OpBase
## The armoured thrust (docs/combined_arms.md 6.4.3; phase D4, cg_brief queue item 3.3): the company
## rides with an allied armoured column (the OOB's Abrams and mechanised platoons, and the Bradley
## section attached to it, OpSupport) down the axis, the MSR, through its blocking positions to the
## depth target. Speed is the point: "time_limit_min" (45) for the whole thrust from H-hour (the
## company crossing the line of departure). Inland only (the type's "region").
##
## - The blocking positions are the phases' company tasks (the MSR checkpoint, the town, the depth
##   target), the river's crossing passed between the first two (the MSR's bridge, or a ford when
##   it's down: the column's roads leave out a bridge too light for it, A6). The column drives by
##   road (SquadDrivers.go), its vehicles "gap_m" apart, and halts "halt_short_m" short of the next
##   position that isn't clear: it won't drive through one (3.6). The mechanised squads dismount
##   there.
## - The company is its infantry screen: dismount, clear the AT threat round the position (the task's
##   seize_site radius), mount up; the column moves on once the position is clear and every player is
##   aboard one of its vehicles, or after "wait_mount_s" (the company follows on foot or in its own
##   vehicles).
## - Bypass (Support > Operation > Column: bypass): off-road round the position ("bypass_side_m" to
##   the side the ground allows: TerrainRoute.path_problem), the position counted passed but its
##   ground left to the enemy behind the front (its cells stay theirs, its site not taken), said in
##   the debrief.
## - Fail: the time runs out with the depth target not taken, or the column loses more than
##   "lost_share" of its vehicles.
## Numbers in data/operations.json "armoured_thrust" "column", Proposed.

const TICK_S := 2.0

var _tick_left := 0.0
var _issued := {}  # vehicle instance id -> the spot it was sent to


func start() -> void:
	var m := mine()
	if not m.has("bypassed"):
		m["bypassed"] = []
		m["start_vehicles"] = 0
		m["cleared_at"] = -1.0
		m["halted_at"] = {}
	_refresh()


## The column's vehicles now: the allied armour and mechanised groups' and the attached ones (live).
func column() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for e: Dictionary in run().get("oob", []):
		if String(e.side) != "friendly" or not String(e.kind) in ["armour_section", "mech_infantry", "armour_platoon"] or String(e.state) != "live":
			continue
		for v: Variant in (ops.records.get(String(e.id), {}) as Dictionary).get("vehicles", []):
			if is_instance_valid(v) and not (v as Vehicle).wrecked:
				out.append(v)
	var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
	if sup:
		for e: Dictionary in sup.attached():
			var v := sup.vehicle_of(String(e.id))
			if v and not v.wrecked and String(e.state) == "live":
				e.order = OpSupport.COLUMN
				out.append(v)
	return out


func _expected() -> int:
	var n := 0
	for e: Dictionary in run().get("oob", []):
		if String(e.side) == "friendly" and String(e.kind) in ["armour_section", "mech_infantry", "armour_platoon"]:
			n += int(e.get("start_vehicles", (e.vehicles as Array).size()))
	var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
	return n + (sup.attached().size() if sup else 0)


func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_left -= dt
	if _tick_left > 0.0:
		return
	_tick_left = TICK_S
	var r := run()
	if String(r.get("state", "")) != Operations.RUNNING:
		return
	var m := mine()
	var vs := column()
	m["start_vehicles"] = maxi(int(m.get("start_vehicles", 0)), mini(vs.size() + _lost(), _expected()))
	var lost := _lost()
	var total := int(m.start_vehicles)
	if total > 0 and lost > total * num("column", "lost_share", 0.5):
		note("The column lost %d of its %d vehicles." % [lost, total])
		stall("the column lost more than half its vehicles")
		return
	var limit := num("column", "time_limit_min", 45.0) * 60.0
	var since := clock() - float(r.get("hhour_s", clock()))
	if float(r.get("hhour_s", -1.0)) >= 0.0 and since > limit:
		note("The thrust ran out of time: %s with the depth target not taken." % Operations.clock_text(since))
		stall("the %d minutes ran out" % roundi(limit / 60.0))
		return
	_drive(vs)
	_refresh()
	cost_us = float(Time.get_ticks_usec() - t0)
	if not heavy:
		worst_us = maxf(worst_us, cost_us)
	heavy = false


func _lost() -> int:
	var n := 0
	for e: Dictionary in run().get("oob", []):
		if String(e.side) == "friendly" and String(e.kind) in ["armour_section", "mech_infantry", "armour_platoon"] and String(e.state) in ["live", "gone"]:
			var have := (ops.records.get(String(e.id), {}) as Dictionary).get("vehicles", []) as Array
			n += have.filter(func(v: Variant) -> bool: return not is_instance_valid(v) or (v as Vehicle).wrecked).size()
	var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
	if sup:
		n += sup.attached().filter(func(e: Dictionary) -> bool: return String(e.state) == "lost").size()
	return n


## The blocking position of phase `k` (its first company task's spot), INF past the last.
func position_of(k: int) -> Vector3:
	var phases: Array = contract().get("phases", [])
	if k < 0 or k >= phases.size() or (phases[k].tasks as Array).is_empty():
		return Vector3.INF
	return v3(phases[k].tasks[0].pos)


## Where the column halts for phase `k`'s position: halt_short_m short of it along the axis, on the MSR.
func halt_point(k: int) -> Vector3:
	var bp := position_of(k)
	if not bp.is_finite():
		return Vector3.INF
	var axis := ops._axis()
	return _on_msr(bp - Vector3(axis.x, 0, axis.y) * num("column", "halt_short_m", 280.0))


func _on_msr(p: Vector3) -> Vector3:
	var msr: Array = ops.def.op.get("msr", [])
	var best := Vector2(p.x, p.z)
	var best_d := INF
	for k in range(1, msr.size()):
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(float(msr[k - 1][0]), float(msr[k - 1][1])), Vector2(float(msr[k][0]), float(msr[k][1])))
		var d := q.distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best = q
	return ground(Vector3(best.x, 0, best.y))


func _drive(vs: Array[Vehicle]) -> void:
	var m := mine()
	var k := phase()
	var target := halt_point(k)
	if not target.is_finite():
		return
	var drivers := SquadDrivers.of(self)
	if drivers == null:
		return
	# Cleared the last one (the phase moved on): wait for the company to mount, then go.
	var went := int(m.get("went_for", -1))
	if went != k:
		var players := ops._players()
		var aboard := players.all(func(p: Node) -> bool: return vs.has(Vehicle.ride_of(p as Soldier)))
		var since := clock() - float(m.get("cleared_at", -1.0))
		if k > 0 and float(m.get("cleared_at", -1.0)) >= 0.0 and not aboard and since < num("column", "wait_mount_s", 90.0):
			say_once("mount", "Iron 1: position clear. Mount up, we move in %d seconds." % roundi(num("column", "wait_mount_s", 90.0) - since), 30.0)
			return
		m["went_for"] = k
		_remount()
		_issued.clear()
		say("Iron 1: column moving to %s, halting short of %s." % [grid_ref(target), grid_ref(position_of(k))])
	var axis := ops._axis()
	var back := Vector3(axis.x, 0, axis.y) * -num("column", "gap_m", 30.0)
	var halted := 0
	for i in vs.size():
		var v := vs[i]
		var spot := _on_msr(target + back * i)
		var key := v.get_instance_id()
		var far := Vector2(v.global_position.x - spot.x, v.global_position.z - spot.z).length()
		if far < 18.0:
			halted += 1
			continue
		if not _issued.has(key) or (_issued[key] as Vector3).distance_to(spot) > 10.0 or not (is_instance_valid(v.ai) and v.ai.active):
			_issued[key] = spot
			drivers.go(v, spot, true, num("column", "kmh", 35.0))
			heavy = true  # (a route planned)
	if halted > 0 and halted >= vs.size() and not (m.halted_at as Dictionary).has(str(k)):
		m.halted_at[str(k)] = clock()
		heavy = true
		_dismount()
		say("Iron 1: halted short of the blocking position at %s. Screen, clear the AT threat." % grid_ref(position_of(k)))


## The mechanised squads get out at a halt (their commander takes them on).
func _dismount() -> void:
	for v: Vehicle in column():
		for s: Soldier in v.occupants():
			if s.has_meta(&"op_allied") and not s.has_meta(&"vehicle_crew") and s.vitals.is_up():
				v.server_exit(s)


## And back in when the column moves on.
func _remount() -> void:
	var drivers := SquadDrivers.of(self)
	if drivers == null:
		return
	for e: Dictionary in run().get("oob", []):
		if String(e.kind) != "mech_infantry" or String(e.state) != "live":
			continue
		var rec: Dictionary = ops.records.get(String(e.id), {})
		var squad := rec.get("squad") as Squad
		var vs: Array = (rec.get("vehicles", []) as Array).filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Vehicle).wrecked)
		if squad and is_instance_valid(squad) and is_instance_valid(squad.leader) and not vs.is_empty():
			drivers.server_squad_mount(squad.leader, squad, (vs[0] as Vehicle).global_position)


func phase_done(k: int) -> void:
	var m := mine()
	m["cleared_at"] = clock()
	if str(k) in (m.get("bypassed", []) as Array):
		# Passed, not taken: its ground stays the enemy's behind the front.
		var bp := position_of(k)
		var p2 := Vector2(bp.x, bp.z)
		var cells := ops.grid.cells_within(p2, num("column", "pocket_m", 200.0))
		var moved := ops.grid.set_cells(cells, FrontGrid.HOSTILE)
		if not moved.is_empty():
			ops._front_moved(moved)
		var r := run()
		var phases: Array = contract().get("phases", [])
		for o: Dictionary in phases[k].objectives:
			(r.taken as Array).erase(String(o.get("module_id", "")))
	else:
		say("Iron 1: blocking position %d clear." % (k + 1))


## Host (Support > Operation > Column: bypass): the column goes round the position it's halted
## short of, off-road, if the ground takes it.
func server_bypass(by: Soldier) -> String:
	var r := run()
	if String(r.get("state", "")) != Operations.RUNNING:
		return "The thrust isn't under way"
	var k := phase()
	var bp := position_of(k)
	var vs := column()
	if not bp.is_finite() or vs.is_empty():
		return "No column to take round"
	var axis := ops._axis()
	var fwd := Vector3(axis.x, 0, axis.y)
	var left := Vector3(-axis.y, 0, axis.x)
	var side := num("column", "bypass_side_m", 450.0)
	var chosen := PackedVector3Array()
	var why := ""
	for sgn: float in [1.0, -1.0]:
		var path := PackedVector3Array([ground(bp - fwd * 300.0 + left * side * sgn), ground(bp + left * side * sgn), ground(bp + fwd * 300.0 + left * side * sgn),
			_on_msr(bp + fwd * 450.0)])
		var p := TerrainRoute.path_problem(vs[0], path)
		if p.is_empty():
			chosen = path
			break
		why = String(p.get("why", "the ground"))
	if chosen.is_empty():
		return "The ground won't take the column round it (%s)" % why
	for i in vs.size():
		var each := chosen.duplicate()
		each[each.size() - 1] = each[each.size() - 1] - fwd * num("column", "gap_m", 30.0) * i
		vs[i].server_follow_path(each, num("column", "kmh", 35.0) * 0.6)
		_issued[vs[i].get_instance_id()] = each[each.size() - 1]
	var m := mine()
	(m.bypassed as Array).append(str(k))
	m["went_for"] = k + 1
	note("Blocking position %d at %s was bypassed off-road: its enemy is left behind the front." % [k + 1, grid_ref(bp)])
	say("Iron 1: bypassing %s off-road. Enemy left behind us there." % grid_ref(bp))
	# The position counts passed: its task and the allies' objectives there.
	for o: Dictionary in Contracts.objectives.for_contract(ops.cid):
		if int((o.get("params", {}) as Dictionary).get("phase", -1)) == k and String(o.state) == Objectives.ACTIVE and not bool(o.optional):
			Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE, "bypassed")
	var phases: Array = contract().get("phases", [])
	for o: Dictionary in phases[k].objectives:
		if ops.plan:
			ops.plan.taken[String(o.id)] = ops.friendly.now() if ops.friendly else 0.0
	return ""


func strip_line() -> String:
	if not ops or not ops.active():
		return ""
	var r := run()
	var since := clock() - float(r.get("hhour_s", clock())) if float(r.get("hhour_s", -1.0)) >= 0.0 else 0.0
	return "Column %d up, %d lost  BP %d/%d  %s of %s" % [int(state.get("vehicles", 0)), int(state.get("lost", 0)), int(state.get("bp", 0)) + 1,
		(contract().get("phases", []) as Array).size(), Operations.clock_text(since), Operations.clock_text(float(state.get("limit_s", 2700.0)))]


func _refresh() -> void:
	var m := mine()
	var s := {"bp": phase(), "bypassed": (m.get("bypassed", []) as Array).duplicate(), "vehicles": column().size() if ops and ops.active() else 0,
		"lost": _lost() if ops and ops.active() else 0, "limit_s": num("column", "time_limit_min", 45.0) * 60.0}
	if s != state:
		state = s
		publish()


func _ready() -> void:
	super._ready()
	Supports.register("op_column", Callable(self, "_cmd_op_column"))


## Support > Operation > Column: "bypass" the position ahead, "go" on now without waiting to mount.
func _cmd_op_column(who: Node, arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	if arg == "bypass":
		return server_bypass(who as Soldier)
	if arg == "go":
		mine()["cleared_at"] = -INF
		return ""
	return "Order not understood"
