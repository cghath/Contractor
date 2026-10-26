class_name OpCrossing
extends OpBase
## Seizing a crossing (docs/combined_arms.md 6.4.4; phase D5, cg_brief queue item 3.3): take the
## MSR's concrete bridge intact and hold both banks while the armour crosses.
##
## - The demolition: "charges" demo blocks (Demolitions, armed on a firing device: the same blocks a
##   player places, which a player can pick up again) under the middle span, wired to a firing point
##   on the far bank (OpTypes.firing_point: "firing_back_m" past the bridge, "firing_side_m" off the
##   road) where the enemy's engineers (the OOB's "engineers", Fuse 1) stand. The firing team blows
##   the bridge "fuse_s" after it sees a friendly force within "see_m" of the bridge (a line of
##   sight from the firing point, checked every "los_every_s"; before the team is out of the world,
##   anyone within "pending_see_m" of it), or at once when it sees a vehicle on the span.
## - The company stops it by killing the engineers (both down), cutting the firing wire (Support >
##   Operation > Cut the firing wire, within "cut_m" of one of its two marked points, on the far
##   abutment and on the bank), or seizing the firing point (one of the company within "seize_m",
##   no enemy within "seize_clear_m").
## - If it blows: the span drops (ZoneBridges takes the blast), the company's "keep intact" bonus
##   (data: +40% of phase 2) fails, and the operation goes on with a ford: the armour crosses there
##   (its roads leave out a bridge with a span down, A6), slower.
## - Phase 3: the allied armour (the OOB's armour section) drives across to "cross_to_m" past the
##   far bank while the company holds the crossing for its minutes against a counterattack
##   (OpBase.counter_step from the enemy's depth).
## - Fail: both banks held by the enemy for "hold_fail_s" with none of ours, or the bridge down and
##   every ford held by the enemy.
## Numbers in data/operations.json "seize_crossing" "crossing", Proposed.

const TICK_S := 0.5
const ARMED := "armed"
const COUNTING := "counting"
const BLOWN := "blown"
const CUT := "cut"
const SEIZED := "seized"
const NO_CREW := "no crew"

var _tick_left := 0.0
var _los_left := 0.0
var _wire_nodes: Array = []


func start() -> void:
	var m := mine()
	if not m.has("state"):
		var fp := OpTypes.firing_point(ops.def)
		var bi := _bridge()
		m["state"] = ARMED
		m["fuse_at"] = -1.0
		m["firing"] = [fp.x, fp.y] if fp.is_finite() else []
		m["bridge"] = bi
		m["charges"] = _place_charges(bi)
		m["wire"] = _wire_points(bi, fp)
		for e: Dictionary in run().get("oob", []):
			if String(e.side) == "hostile" and String(e.kind) == "engineers" and fp.is_finite():
				e.pos = [snappedf(fp.x, 1.0), snappedf(fp.y, 1.0)]
				m["engineers"] = String(e.id)
		_mark_wire()
		SessionLog.note("operation %s: the bridge's charges (%d) wired to the firing point at %s" % [ops.cid, (m.charges as Array).size(), grid_ref(v3(m.firing))])
	_refresh()


## The MSR's concrete bridge (the one nearest the planned crossing), -1 for none.
func _bridge() -> int:
	var b := ops._bridges()
	var x := OpTypes.crossing(ops.def)
	if b == null or x.is_empty():
		return -1
	for bi in b.bridges.size():
		if String(b.bridges[bi].get("role", "")) == "msr":
			return bi  # (F-196: the bridge carries its crossing's role)
	var best := -1
	var best_d := 120.0
	for bi in b.bridges.size():
		var o: Vector3 = (b.bridges[bi].xform as Transform3D).origin
		var d := Vector2(o.x - float(x.pos[0]), o.z - float(x.pos[1])).length()
		if d < best_d:
			best_d = d
			best = bi
	return best


func _span_centre(bi: int, k: int) -> Vector3:
	var b := ops._bridges()
	var br: Dictionary = b.bridges[bi]
	var span: Dictionary = br.spans[k]
	var spec: Dictionary = ZoneBridges.TYPES[br.type]
	return (br.xform as Transform3D) * Vector3(0.0, -float(spec.deck_t) - 0.05, (float(span.z0) + float(span.z1)) * 0.5)


func _place_charges(bi: int) -> Array:
	var out: Array = []
	var demo := Demolitions.of(self)
	var b := ops._bridges()
	if bi < 0 or b == null or demo == null:
		return out
	var spans: Array = b.bridges[bi].spans
	var k := spans.size() / 2
	var basis: Basis = (b.bridges[bi].xform as Transform3D).basis
	for i in int(num("crossing", "charges", 3)):
		var at := _span_centre(bi, k) + basis.x * (float(i) - (num("crossing", "charges", 3) - 1.0) / 2.0) * 1.8
		var id := demo.server_place(null, &"demo_block", Transform3D(basis, at), null, Demolitions.REMOTE)
		if id != "":
			out.append(id)
	return out


## The wire's two cut points (on the far abutment, and on the bank half way to the firing point).
func _wire_points(bi: int, fp: Vector2) -> Array:
	var b := ops._bridges()
	if bi < 0 or b == null or not fp.is_finite():
		return []
	var br: Dictionary = b.bridges[bi]
	var xf: Transform3D = br.xform
	var axis := ops._axis()
	var end_a := xf * Vector3(0, 0, float(br.length) * 0.5)
	var end_b := xf * Vector3(0, 0, -float(br.length) * 0.5)
	var far := end_a if Vector2(end_a.x, end_a.z).dot(axis) > Vector2(end_b.x, end_b.z).dot(axis) else end_b
	var mid := Vector2(far.x, far.z).lerp(fp, 0.5)
	return [[far.x, far.z], [mid.x, mid.y]]


func _mark_wire() -> void:
	var markers := MapNodes.markers(level()) if level() else null
	var m := mine()
	if markers == null:
		return
	var ids: Array = []
	for p: Array in m.get("wire", []):
		ids.append(markers.server_add({"kind": "point", "points": PackedVector2Array([Vector2(float(p[0]), float(p[1]))]), "text": "Firing wire (cut here)",
			"colour": "yellow", "channel": "intel", "author": 0}))
	m["markers"] = ids


func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_left -= dt
	if _tick_left > 0.0:
		return
	_tick_left = TICK_S
	var m := mine()
	if m.is_empty():
		return
	if String(m.state) in [ARMED, COUNTING]:
		_watch_firing(m, TICK_S)
	var phases: Array = contract().get("phases", [])
	var k := phase()
	var running := String(run().get("state", "")) == Operations.RUNNING
	if running and k == phases.size() - 1:
		_armour_step(m)
		var far := v3((OpTypes.resolve_extra(ops.def, {"bank": "far"})[0] as Dictionary).pos)
		var near := v3((OpTypes.resolve_extra(ops.def, {"bank": "near"})[0] as Dictionary).pos)
		counter_step("crossing", far, ops._axis(), [])
		var hold_m := num("crossing", "hold_m", 120.0)
		var fail_s := num("crossing", "hold_fail_s", 60.0)
		var far_lost := held_by_enemy("far", far, hold_m, TICK_S, fail_s)
		var near_lost := held_by_enemy("near", near, hold_m, TICK_S, fail_s)
		if far_lost and near_lost:
			note("The enemy took both banks back.")
			stall("both banks lost")
		elif bridge_down() and _fords_lost(hold_m, fail_s):
			note("With the bridge down, the enemy took the fords too.")
			stall("the bridge and the ford both lost")
	_refresh()
	cost_us = float(Time.get_ticks_usec() - t0)
	if not heavy:
		worst_us = maxf(worst_us, cost_us)
	heavy = false


func _fords_lost(hold_m: float, fail_s: float) -> bool:
	var fords: Array = ((ops.def.get("river_hint", {}) as Dictionary).get("crossings", []) as Array).filter(func(x: Dictionary) -> bool: return String(x.get("role", "")) == "ford")
	if fords.is_empty():
		return true
	for i in fords.size():
		if not held_by_enemy("ford%d" % i, v3(fords[i].pos), hold_m, TICK_S, fail_s):
			return false
	return true


func bridge_down() -> bool:
	var b := ops._bridges()
	var bi := int(mine().get("bridge", -1))
	return b != null and bi >= 0 and (b.bridges[bi].spans as Array).any(func(s: Dictionary) -> bool: return bool(s.down))


func firing_pos() -> Vector3:
	var f: Array = mine().get("firing", [])
	return v3(f) if f.size() == 2 else Vector3.INF


## Whether the firing team still has its hands on the wire; what it sees; the fuse.
func _watch_firing(m: Dictionary, dt: float) -> void:
	var fp := firing_pos()
	if not fp.is_finite():
		return
	if bridge_down():
		_set_state(BLOWN, "the bridge came down")
		return
	# Stopped: the firing point seized, the engineers down.
	if ops._company_near(fp, num("crossing", "seize_m", 12.0)) > 0 and ops._hostiles_near(fp, num("crossing", "seize_clear_m", 40.0), "") == 0:
		_set_state(SEIZED, "the company seized the firing point")
		return
	var team := _engineers()
	if team.is_empty() or String(team.get("state", "")) == "gone":
		_set_state(NO_CREW, "its engineers were killed")
		return
	if String(team.get("state", "")) == "live" and int(team.get("up", 0)) == 0:
		_set_state(NO_CREW, "its engineers were killed")
		return
	# A vehicle on the span: at once.
	var b := ops._bridges()
	var bi := int(m.bridge)
	if b and bi >= 0:
		for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
			var v := n as Vehicle
			if v and not v.wrecked and v.faction in [&"friendly", &"player"] and b.deck_at(v.global_position, 1.0, true).x == bi:
				_blow("it saw %s on the span" % v.display_name())
				return
	if String(m.state) == ARMED:
		_los_left -= dt
		if _los_left <= 0.0:
			_los_left = num("crossing", "los_every_s", 2.0)
			var who := _seen(fp, team)
			if who != "":
				m.state = COUNTING
				m.fuse_at = clock() + num("crossing", "fuse_s", 90.0)
				m["seen"] = who
				SessionLog.note("operation %s: the firing team saw %s: %d s to the blast" % [ops.cid, who, roundi(num("crossing", "fuse_s", 90.0))])
				say_once("fuse", "Citadel: enemy engineers on the far bank have seen us. Expect them to blow the bridge: kill them, cut the wire or take the firing point.", 300.0)
	elif clock() >= float(m.fuse_at):
		_blow("%d s after it saw %s" % [roundi(num("crossing", "fuse_s", 90.0)), String(m.get("seen", "us"))])


## The engineers' OOB entry: {"state", "up"} ({} with none).
func _engineers() -> Dictionary:
	var id := String(mine().get("engineers", ""))
	for e: Dictionary in run().get("oob", []):
		if String(e.id) == id:
			var rec: Dictionary = ops.records.get(id, {})
			return {"state": String(e.state), "up": Virtualizer.up(rec) if not rec.is_empty() else int(e.men), "eyes": rec.get("soldiers", [])}
	return {}


## Who the firing team sees within see_m of the bridge ("" for nobody): by a line of sight from its
## men (from the firing point while they aren't out), else, not out yet, anyone within pending_see_m.
func _seen(fp: Vector3, team: Dictionary) -> String:
	var bridge := v3(OpTypes.crossing(ops.def).get("pos", [0, 0]))
	var see := num("crossing", "see_m", 1000.0)
	var eyes: Array[Vector3] = []
	for s: Variant in team.get("eyes", []):
		if is_instance_valid(s) and (s as Soldier).vitals.is_up():
			eyes.append((s as Soldier).global_position + Vector3.UP * 1.6)
	var live := String(team.get("state", "")) == "live"
	if eyes.is_empty():
		eyes.append(fp + Vector3.UP * 1.7)
	var lvl := level() as Node3D
	var space := lvl.get_world_3d().direct_space_state if lvl and lvl.is_inside_tree() else null
	var checked := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or not s.vitals.is_up() or not (s.faction in [&"friendly", &"player"]) or Person.is_person(s):
			continue
		var p := s.global_position
		if Vector2(p.x - bridge.x, p.z - bridge.z).length() > see:
			continue
		if not live:
			if Vector2(p.x - fp.x, p.z - fp.z).length() <= num("crossing", "pending_see_m", 600.0):
				return s.display_name()
			continue
		if space == null or checked >= 12:
			continue
		checked += 1
		for eye: Vector3 in eyes:
			var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3.UP * 1.2, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit.position as Vector3).distance_to(p) < 1.5:
				return s.display_name()
	return ""


func _blow(why: String) -> void:
	var m := mine()
	var demo := Demolitions.of(self)
	var n := 0
	for id: Variant in m.get("charges", []):
		if demo and demo.records.has(String(id)):
			n += demo.server_detonate(String(id))
	var b := ops._bridges()
	var bi := int(m.get("bridge", -1))
	if n == 0 and b and bi >= 0:
		var spans: Array = b.bridges[bi].spans
		var k := spans.size() / 2
		var at := _span_centre(bi, k)
		b.server_blast(at, num("crossing", "fallback_carve_m", 2.6))  # (charges picked up or no demolitions node: the wire still had one)
	m["blown_s"] = clock()
	_set_state(BLOWN, "the enemy blew it %s" % why)
	say("Citadel: the bridge is down! The armour crosses at the ford. We push on.")


func _set_state(s: String, why: String) -> void:
	var m := mine()
	if String(m.get("state", "")) == s:
		return
	m.state = s
	m["why"] = why
	match s:
		BLOWN:
			note("The bridge at %s was blown at %s: %s." % [grid_ref(v3(OpTypes.crossing(ops.def).get("pos", [0, 0]))), Operations.clock_text(clock()), why])
		CUT, SEIZED, NO_CREW:
			note("The bridge's demolition was stopped at %s: %s." % [Operations.clock_text(clock()), why])
			say("Citadel: %s. The bridge's charges won't fire." % (why.left(1).to_upper() + why.substr(1)))
	_refresh()


## Host (Support > Operation > Cut the firing wire): `by` within cut_m of a cut point.
func server_cut(by: Soldier) -> String:
	var m := mine()
	if not String(m.get("state", "")) in [ARMED, COUNTING]:
		return "Nothing to cut" if String(m.get("state", "")) != BLOWN else "Too late: the bridge is down"
	for p: Array in m.get("wire", []):
		if Vector2(by.global_position.x - float(p[0]), by.global_position.z - float(p[1])).length() <= num("crossing", "cut_m", 3.0):
			_set_state(CUT, "%s cut the firing wire" % by.display_name())
			return ""
	return "Get to the firing wire first (its points are marked on the map)"


## Phase 3: the allied armour across, by the bridge or (down) a ford.
func _armour_step(m: Dictionary) -> void:
	var drivers := SquadDrivers.of(self)
	if drivers == null:
		return
	var axis := ops._axis()
	var bridge := v3(OpTypes.crossing(ops.def).get("pos", [0, 0]))
	var to := ground(bridge + Vector3(axis.x, 0, axis.y) * num("crossing", "cross_to_m", 300.0))
	var river := float(ops.def.op.get("river_at_m", 0.0))
	for e: Dictionary in run().get("oob", []):
		if String(e.side) != "friendly" or String(e.kind) != "armour_section" or String(e.state) != "live":
			continue
		for v: Variant in (ops.records.get(String(e.id), {}) as Dictionary).get("vehicles", []):
			if not is_instance_valid(v) or (v as Vehicle).wrecked:
				continue
			var veh := v as Vehicle
			if OperationGen.along(ops.def, Vector2(veh.global_position.x, veh.global_position.z)) > river + 60.0:
				if not bool(m.get("armour_across", false)):
					m["armour_across"] = true
					note("The armour crossed %s at %s." % ["by the ford" if bridge_down() else "the bridge", Operations.clock_text(clock())])
					say("Iron: across the river.")
				continue
			if not bool(veh.get_meta(&"op_crossing", false)) or not (is_instance_valid(veh.ai) and veh.ai.active):
				veh.set_meta(&"op_crossing", true)
				drivers.go(veh, to, true, 25.0 if bridge_down() else 35.0)
				heavy = true  # (a route planned: the driving's cost, not the tick's)


func strip_line() -> String:
	match String(state.get("demolition", "")):
		ARMED:
			return "Bridge: wired to blow (cut the wire, take the firing point)"
		COUNTING:
			return "Bridge: they've seen us, %d s to the blast" % roundi(float(state.get("fuse_left", 0.0)))
		BLOWN:
			return "Bridge: down. Armour by the ford"
		CUT, SEIZED, NO_CREW:
			return "Bridge: safe (%s)" % String(state.get("demolition", ""))
	return ""


func _refresh() -> void:
	var m := mine()
	var s := {"demolition": String(m.get("state", "")), "fuse_left": maxf(float(m.get("fuse_at", -1.0)) - clock(), 0.0) if String(m.get("state", "")) == COUNTING else -1.0,
		"wire": (m.get("wire", []) as Array).duplicate(true), "firing": (m.get("firing", []) as Array).duplicate(), "armour_across": bool(m.get("armour_across", false))}
	if s != state:
		state = s
		publish()
		_on_state()


## Every peer: the firing wire drawn from the firing point along the bank to the span.
func _on_state() -> void:
	for n: Variant in _wire_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_wire_nodes.clear()
	var w: Array = state.get("wire", [])
	var f: Array = state.get("firing", [])
	if w.size() < 2 or f.size() < 2 or String(state.get("demolition", "")) in [CUT, BLOWN] or DisplayServer.get_name() == "headless":
		return
	var pts := [v3(f), v3(w[1]), v3(w[0])]
	for i in range(1, pts.size()):
		var line := Demolitions.cord_line((pts[i - 1] as Vector3) + Vector3.UP * 0.05, (pts[i] as Vector3) + Vector3.UP * 0.05)
		add_child(line)
		_wire_nodes.append(line)


func _ready() -> void:
	super._ready()
	Supports.register("op_cut", Callable(self, "_cmd_op_cut"))


func _cmd_op_cut(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_cut(who as Soldier)
