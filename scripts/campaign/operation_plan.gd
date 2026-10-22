class_name OperationPlan
extends RefCounted
## An attacking side's plan (docs/combined_arms.md 3.4-3.5; B2): phases of objectives along an
## axis, what each phase needs, its timing, the reserve, stalls and the fall back. SideCommand runs
## the tasking; this says what's needed.
##
## spec: {"phases": [{"name", "limit_s", "axis": [from: Vector3, to: Vector3], "main": objective id,
##   "alt": objective id or "", "objectives": [{"id", "label", "pos", "radius", "required", "town"}]}],
##   "ld": Vector3 (line of departure), "rally": Vector3, "hhour_s": seconds after start (-1: the
##   company's crossing, start_phase()), "flanks": true (screens on the axis' flanks)}
## - Needs: each objective not taken an Assault and its SBF (on the axis' side, sbf_offset_m back and
##   off the line); each open flank a Screen; each taken objective a Defend by whoever took it; the
##   reserve held at the rally; AMBER-on-ammo groups a Resupply when someone can carry it.
## - Timing: nothing moves before H-hour; an objective is taken when the side's picture shows no
##   enemy in it for consolidate_s with one of its groups there; the next phase when every required
##   one is.
## - Reserve: reserve_share of the side's CP at each phase's start, the groups best suited to it.
##   Committed when the main objective stalls (phase_stall_share of the limit), an assault goes
##   AMBER, a counterattack bigger than a taken objective's defenders is seen, or to exploit (an
##   objective that fell in under half its time sends it on to the next).
## - Stalls: at the limit the main effort shifts to `alt`, or fire support is called and the phase
##   pauses phase_pause_s; at phase_fail_share x the limit the operation stalls.
## Numbers in data/side_command.json, Proposed.

var spec: Dictionary
var phase := 0
var phase_at := INF
var started := false
var taken := {}         # objective id -> when taken
var taken_by := {}      # objective id -> group id
var stalled := false
var reserve := {}       # group id -> true
var committed := {}     # group id -> objective id (a committed reserve's target)
var _quiet := {}        # objective id -> since when no enemy is reported in it
var _paused_until := -INF
var _shifted := false
var _stall_committed := false
var _exploit := ""      # the next phase's objective an exploiting reserve goes for


func _init(p_spec := {}) -> void:
	spec = p_spec


func task_s() -> float:
	return float((SideCommand.data().get("task_s", {}) as Dictionary).get("operation", 20.0))


func start(cmd: SideCommand) -> void:
	var h := float(spec.get("hhour_s", 0.0))
	if h >= 0.0:
		phase_at = cmd.now() + h


## The company crossed the line of departure (a player-paced operation): phase 1 goes.
func start_phase(cmd: SideCommand) -> void:
	if not started:
		phase_at = cmd.now()
		cmd.trigger("line of departure crossed")


func phases() -> Array:
	return spec.get("phases", [])


func current() -> Dictionary:
	return phases()[phase] if phase < phases().size() else {}


func objectives() -> Array:
	return current().get("objectives", [])


func objective(id: String) -> Dictionary:
	for p: Dictionary in phases():
		for o: Dictionary in p.get("objectives", []):
			if String(o.id) == id:
				return o
	return {}


func main_id() -> String:
	var c := current()
	return String(c.get("alt", "")) if _shifted and String(c.get("alt", "")) != "" else String(c.get("main", ""))


# --- Each cycle ----------------------------------------------------------------------------------

func update(cmd: SideCommand, t: float) -> void:
	if stalled or current().is_empty():
		return
	if not started:
		if t < phase_at or cmd.groups.is_empty():
			return  # (nothing to plan with yet)
		started = true
		_begin_phase(cmd, t)
	_check_objectives(cmd, t)
	if current().is_empty():
		return
	_top_up_reserve(cmd)
	var elapsed := t - phase_at
	var limit := float(current().get("limit_s", 1200.0))
	var main := main_id()
	if main != "" and not taken.has(main):
		if elapsed >= limit * SideCommand.num("phase_fail_share", 1.5):
			stalled = true
			cmd._log("the operation stalls at phase %d: %s not taken in %d min" % [phase + 1, main, roundi(elapsed / 60.0)])
			cmd.stalled.emit("%s not taken" % main)
			return
		if elapsed >= limit and t >= _paused_until:
			if String(current().get("alt", "")) != "" and not _shifted:
				_shifted = true
				cmd._log("main effort shifts to %s" % main_id())
				cmd.trigger()
			elif _paused_until == -INF:
				_paused_until = t + SideCommand.num("phase_pause_s", 300.0)
				cmd.fire_support_wanted.emit(objective(main).pos, "the phase stalled on %s" % main)
				cmd._log("phase %d paused 5 min for fire support on %s" % [phase + 1, main])
		elif elapsed >= limit * SideCommand.num("phase_stall_share", 0.6) and not _stall_committed:
			_stall_committed = true
			_commit_reserve(cmd, main, "the main objective stalls")
	_watch_assaults(cmd)
	_watch_counterattacks(cmd)


func _begin_phase(cmd: SideCommand, t: float) -> void:
	phase_at = t
	_paused_until = -INF
	_shifted = false
	_stall_committed = false
	_pick_reserve(cmd)
	cmd._log("phase %d (%s) begins" % [phase + 1, String(current().get("name", ""))])
	cmd.phase_changed.emit(phase)
	if _exploit != "":
		for gid: String in reserve.keys():
			committed[gid] = _exploit
		_exploit = ""


## The quarter of the side's CP best suited to being the reserve.
func _pick_reserve(cmd: SideCommand) -> void:
	reserve.clear()
	committed.clear()
	var rows := cmd.rows()
	var total := 0.0
	for r: Dictionary in rows:
		total += float(r.strength_cp)
	var rally: Vector3 = spec.get("rally", spec.get("ld", Vector3.ZERO))
	var keep := func(r: Dictionary) -> float:  # suited to the reserve, not needed up front
		var k := String(r.kind)
		return SideCommand.suitability(k, "reserve") - maxf(SideCommand.suitability(k, "assault"), SideCommand.suitability(k, "sbf")) * 0.5
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = keep.call(a)
		var sb: float = keep.call(b)
		if not is_equal_approx(sa, sb):
			return sa > sb
		return SideCommand._flat(a.pos, rally) < SideCommand._flat(b.pos, rally))  # then the nearest the rally
	var held := 0.0
	var share := SideCommand.num("reserve_share", 0.25)
	for r: Dictionary in rows:
		if held >= total * share or rows.size() - reserve.size() <= 2:
			break  # an Assault and its SBF still need someone
		reserve[String(r.id)] = true
		held += float(r.strength_cp)
	if not reserve.is_empty():
		cmd._log("reserve: %s (%.0f of %.0f CP)" % [", ".join(PackedStringArray(reserve.keys())), held, total])


## Groups arriving after the phase began (reinforcements at the line of departure, a group that
## reconstituted) fill the reserve back up to its share, while it's uncommitted.
func _top_up_reserve(cmd: SideCommand) -> void:
	if not committed.is_empty():
		return
	var rows := cmd.rows()
	var total := 0.0
	var held := 0.0
	for r: Dictionary in rows:
		total += float(r.strength_cp)
		if reserve.has(String(r.id)):
			held += float(r.strength_cp)
	if held >= total * SideCommand.num("reserve_share", 0.25) or rows.size() - reserve.size() <= 2:
		return
	for r: Dictionary in rows:
		var gid := String(r.id)
		if not reserve.has(gid) and String(r.role) in ["", "reserve"]:
			reserve[gid] = true
			cmd._log("%s joins the reserve" % cmd.groups[gid].callsign)
			return


func _commit_reserve(cmd: SideCommand, objective_id: String, why: String) -> void:
	var free := reserve.keys().filter(func(gid: String) -> bool: return not committed.has(gid))
	if free.is_empty():
		return
	for gid: String in free:
		committed[gid] = objective_id
	cmd._log("reserve committed to %s: %s" % [objective_id, why])
	cmd.trigger()


func _check_objectives(cmd: SideCommand, t: float) -> void:
	var pic := cmd.picture()
	var b := cmd.board()
	var all_done := true
	for o: Dictionary in objectives():
		var id := String(o.id)
		if taken.has(id):
			continue
		var r := float(o.get("radius", SideCommand.num("objective_radius_m", 60.0)))
		var enemy := pic != null and not pic.entries_near(o.pos, r).is_empty()
		if enemy:
			_quiet.erase(id)
		elif not _quiet.has(id):
			_quiet[id] = t
		var ours := ""
		for gid: String in cmd.groups:
			var row: Dictionary = b.rows.get(gid, {})
			if not row.is_empty() and SideCommand._flat(row.pos, o.pos) <= r:
				ours = gid
				break
		if not enemy and ours != "" and t - float(_quiet.get(id, t)) >= SideCommand.num("consolidate_s", 90.0):
			taken[id] = t
			taken_by[id] = ours
			cmd._log("%s taken by %s" % [String(o.get("label", id)), cmd.groups[ours].callsign])
			cmd.trigger("%s taken" % id)
			if t - phase_at < float(current().get("limit_s", 1200.0)) * 0.5 and phase + 1 < phases().size():
				_exploit = String((phases()[phase + 1] as Dictionary).get("main", ""))
		if bool(o.get("required", true)) and not taken.has(id):
			all_done = false
	if all_done:
		phase += 1
		if current().is_empty():
			cmd._log("every phase done")
		else:
			_begin_phase(cmd, t)


## An assault gone AMBER brings the reserve in.
func _watch_assaults(cmd: SideCommand) -> void:
	for g: Dictionary in cmd.groups.values():
		if String(g.role) == "assault" and bool(g.amber):
			_commit_reserve(cmd, String(g.need).get_slice(":", 0), "%s is amber" % g.callsign)
			return


## A counterattack bigger than a taken objective's defenders brings the reserve to it.
func _watch_counterattacks(cmd: SideCommand) -> void:
	var pic := cmd.picture()
	if pic == null:
		return
	for id: String in taken:
		var o := objective(id)
		var enemies := 0
		for e: Dictionary in pic.entries_near(o.pos, 400.0):
			enemies += int(e.count)
		var row: Dictionary = cmd.board().rows.get(String(taken_by.get(id, "")), {})
		if enemies > int(row.get("up", 0)) and enemies > 0:
			_commit_reserve(cmd, id, "a counterattack on %s (%d seen)" % [id, enemies])
			return


## Is a counterattack seen (RequestBroker: the last reserve isn't lent then)?
func counterattack_seen(cmd: SideCommand) -> bool:
	return committed.values().any(func(o: String) -> bool: return taken.has(o)) and not cmd.groups.is_empty()


# --- Needs ---------------------------------------------------------------------------------------

func needs(cmd: SideCommand, t: float) -> Array:
	var out: Array = []
	if stalled or not started or current().is_empty():
		return out
	var axis: Array = current().get("axis", [spec.get("ld", Vector3.ZERO), Vector3.ZERO])
	var dir: Vector3 = ((axis[1] as Vector3) - (axis[0] as Vector3))
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	var pic := cmd.picture()
	var main := main_id()
	var paused := t < _paused_until
	for o: Dictionary in objectives():
		var id := String(o.id)
		var p: Vector3 = o.pos
		if taken.has(id):
			out.append({"id": id + ":hold", "role": "defend", "pos": p, "facing": dir, "priority": 6.0, "prefer": taken_by.get(id, ""),
				"label": String(o.get("label", id))})
			continue
		if paused and id == main:
			continue
		var armour := false
		if pic:
			for e: Dictionary in pic.entries_near(p, float(o.get("radius", 60.0)) + 200.0):
				armour = armour or String(e.kind) in ["mbt", "ifv", "light_armour"]
		var prio := 10.0 if id == main else 8.0
		var sbf_at := p - dir * SideCommand.num("sbf_offset_m", 250.0) + side * 80.0
		out.append({"id": id, "role": "assault", "pos": p, "target": p, "pair": id + ":sbf", "priority": prio, "armour": armour,
			"town": bool(o.get("town", false)), "label": String(o.get("label", id))})
		out.append({"id": id + ":sbf", "role": "sbf", "pos": sbf_at, "target": p, "priority": prio, "armour": armour,
			"label": String(o.get("label", id))})
		if bool(spec.get("flanks", true)) and id == main:
			for s in [-1.0, 1.0]:
				out.append({"id": "%s:screen%d" % [id, int(s)], "role": "screen", "pos": p - dir * 100.0 + side * s * SideCommand.num("screen_offset_m", 300.0),
					"facing": side * s, "priority": 5.0, "label": "%s's %s flank" % [String(o.get("label", id)), "left" if s < 0.0 else "right"]})
	var rally: Vector3 = spec.get("rally", spec.get("ld", Vector3.ZERO))
	for gid: String in reserve:
		if committed.has(gid):
			var target := objective(String(committed[gid]))
			if not target.is_empty():
				var role := "defend" if taken.has(String(target.id)) else "assault"
				out.append({"id": "%s:%s" % [String(target.id), gid], "role": role, "pos": target.pos, "target": target.pos, "priority": 11.0,
					"only": gid, "label": String(target.get("label", target.id))})
				continue
		out.append({"id": "reserve:" + gid, "role": "reserve", "pos": rally, "priority": 9.0, "only": gid, "label": "the reserve"})
	for row: Dictionary in cmd.rows():
		if String(row.ammo_band) == "amber" and not reserve.has(String(row.id)):
			out.append({"id": "resupply:" + String(row.id), "role": "resupply", "pos": row.pos, "priority": 4.0, "label": "%s's ammo" % row.id})
	return out


## Where group `g` falls back to: the rally.
func rally_for(_cmd: SideCommand, _g: Dictionary) -> Vector3:
	return spec.get("rally", spec.get("ld", Vector3.INF))


## The side withdraws (3.5.3): every group to the last phase line it held, digging in.
func withdraw(cmd: SideCommand, _t: float) -> void:
	var line: Vector3 = spec.get("ld", Vector3.ZERO)
	var latest := -INF
	for id: String in taken:
		if float(taken[id]) > latest:
			latest = float(taken[id])
			line = objective(id).pos
	for g: Dictionary in cmd.groups.values():
		g.role = "withdrawn"
		g.need = ""
		cmd._give(g, HcOrder.make(String(g.id), "defend", [[line.x, line.z]]))
	cmd._log("withdrawing to the last line held (%s)" % cmd._grid(line))
