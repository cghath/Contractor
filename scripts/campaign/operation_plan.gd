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
## The reels (docs/ai_tactics.md, P1-P2):
## - A `fortified` objective is taken by SOSRA: Suppress (its SBF), Obscure (fire_support_wanted for
##   smoke on it as the breach goes in), Secure (a group on its far flank facing out, cutting its
##   reinforcement), Reduce (a breach group to the breach spot short of it), Assault (through the
##   breach once it's made).
## - A phase marked `isolate` (R07): fix it with fires, send small groups to its routes in (the
##   phase's `routes`, else three points round it away from the attacker), starve it until the
##   picture shows it at half the CP it had (or starve_s), then concentrate: every axis set, then
##   all at once.
## - An objective marked `lure` (R04's feigned retreat): one group goes at it and then falls back;
##   if the garrison follows it out, a second group waiting out of sight on another side goes in.
## Numbers in data/side_command.json, Proposed.

const STARVE_S := 600.0
const ISOLATE_M := 450.0
const LURE_S := 90.0
const LURE_BACK_M := 250.0
const PUSH_SIDE_M := 350.0
const FOLLOW_M := 60.0

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
## P2: the isolation of the phase's main objective: {"stage", "groups", "at", "cp0", "fired_at"}.
var isolation := {}
## P2: a lure: objective id -> {"lure", "push", "at", "state", "rally", "hide"}.
var lures := {}
var _obscured := {}     # objective id -> true: its smoke asked for


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
		if t < phase_at or cmd.my_groups().is_empty():
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
	_isolate(cmd, t)
	_lure(cmd, t)


func _begin_phase(cmd: SideCommand, t: float) -> void:
	phase_at = t
	_paused_until = -INF
	isolation = {}
	lures = {}
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
		if cmd.pairs.has(String(r.id)):
			continue  # paired armour escorts its infantry
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
		if not reserve.has(gid) and String(r.role) in ["", "reserve"] and not cmd.pairs.has(gid):
			reserve[gid] = true
			cmd._log("%s joins the reserve" % cmd.my_groups()[gid].callsign)
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
		for gid: String in cmd.my_groups():
			var row: Dictionary = b.rows.get(gid, {})
			if not row.is_empty() and SideCommand._flat(row.pos, o.pos) <= r:
				ours = gid
				break
		if not enemy and ours != "" and t - float(_quiet.get(id, t)) >= SideCommand.num("consolidate_s", 90.0):
			taken[id] = t
			taken_by[id] = ours
			cmd._log("%s taken by %s" % [String(o.get("label", id)), cmd.my_groups()[ours].callsign])
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
	for g: Dictionary in cmd.my_groups().values():
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
	return committed.values().any(func(o: String) -> bool: return taken.has(o)) and not cmd.my_groups().is_empty()


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
		if id == main and not isolation.is_empty() and String(isolation.stage) != "concentrate":
			out.append_array(_isolation_needs(o, dir, side))
			continue  # fixed by fires and cut off; the assault waits for the concentration
		if lures.has(id):
			out.append_array(_lure_needs(o))
			continue
		var assault := {"id": id, "role": "assault", "pos": p, "target": p, "pair": id + ":sbf", "priority": prio, "armour": armour,
			"town": bool(o.get("town", false)), "label": String(o.get("label", id))}
		if bool(o.get("fortified", false)):  # P1: SOSRA
			assault["breach"] = id + ":breach"
			out.append({"id": id + ":breach", "role": "breach", "pos": p - dir * 30.0, "priority": prio + 0.5, "label": "the breach of %s" % o.get("label", id)})
			out.append({"id": id + ":secure", "role": "secure", "pos": p + side * 90.0 + dir * 60.0, "facing": side, "priority": prio - 1.0,
				"label": "securing %s's far flank" % o.get("label", id)})
		if not isolation.is_empty() and String(isolation.stage) == "concentrate" and id == main:
			assault["together"] = id
		out.append(assault)
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


## The current phase's axis (B3: armour follows its infantry along it).
func axis_dir() -> Vector3:
	var axis: Array = current().get("axis", [])
	if axis.size() < 2:
		return Vector3.FORWARD
	var d: Vector3 = (axis[1] as Vector3) - (axis[0] as Vector3)
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else Vector3.FORWARD


# --- P1, P2: SOSRA's obscure, isolation, the lure -----------------------------------------------

## P1's obscure: smoke on a fortified objective once its breach group is on the way.
func _obscure(cmd: SideCommand) -> void:
	for o: Dictionary in objectives():
		var id := String(o.id)
		if not bool(o.get("fortified", false)) or _obscured.has(id) or taken.has(id):
			continue
		for g: Dictionary in cmd.my_groups().values():
			if String(g.need) == id + ":breach":
				_obscured[id] = true
				cmd.fire_support_wanted.emit(o.pos, "smoke on %s's ports for the breach" % o.get("label", id))
				cmd._log("obscure: smoke on %s for the breach" % o.get("label", id))


## P2: fix, isolate, starve, concentrate on a main objective whose phase says `isolate`.
func _isolate(cmd: SideCommand, t: float) -> void:
	_obscure(cmd)
	if not bool(current().get("isolate", false)) or taken.has(main_id()):
		return
	var o := objective(main_id())
	var pic := cmd.picture()
	var cp := float(DefencePlan.threat(pic, o.pos, float(o.get("radius", 60.0)) + 100.0).cp)
	if isolation.is_empty():
		isolation = {"stage": "isolate", "groups": [], "at": t, "cp0": cp, "fired_at": t}
		cmd.fire_support_wanted.emit(o.pos, "fix %s" % o.get("label", o.id))
		cmd._log("isolate %s: fires to fix it, teams to its routes in (%.0f CP there)" % [o.get("label", o.id), cp])
		return
	if t - float(isolation.fired_at) >= 120.0 and String(isolation.stage) != "concentrate":
		isolation.fired_at = t
		cmd.fire_support_wanted.emit(o.pos, "keep %s fixed" % o.get("label", o.id))
	match String(isolation.stage):
		"isolate":
			var there := 0
			for g: Dictionary in cmd.my_groups().values():
				if String(g.need).begins_with("isolate:"):
					var so := g.orders as SquadOrders
					if so and not so.order.is_empty() and String(so.order.state) in ["done", "set"]:
						there += 1
			if there >= 1 and there >= mini(3, cmd.my_groups().size() - 2):
				isolation.stage = "starve"
				isolation.at = t
				cmd._log("%s cut off: starving it" % o.get("label", o.id))
		"starve":
			var weak := float(isolation.cp0) > 0.0 and cp <= float(isolation.cp0) * 0.5
			if weak or t - float(isolation.at) >= float(current().get("starve_s", STARVE_S)):
				isolation.stage = "concentrate"
				cmd._log("concentrate on %s: %s" % [o.get("label", o.id), "half its strength gone" if weak else "starved %d min" % roundi((t - float(isolation.at)) / 60.0)])
				cmd.trigger()


func _isolation_needs(o: Dictionary, dir: Vector3, side: Vector3) -> Array:
	var out: Array = []
	var routes: Array = current().get("routes", [])
	if routes.is_empty():  # the three ways in that aren't the attacker's: its flanks and rear
		routes = [o.pos + side * ISOLATE_M, o.pos - side * ISOLATE_M, o.pos + dir * ISOLATE_M]
	for i in routes.size():
		out.append({"id": "isolate:%s:%d" % [o.id, i], "role": "recon", "pos": routes[i], "priority": 9.0,
			"label": "the way into %s (%d)" % [o.get("label", o.id), i + 1]})
	return out


## P2's lure: set up at the phase's start for objectives marked `lure`, then run.
func _lure(cmd: SideCommand, t: float) -> void:
	for o: Dictionary in objectives():
		var id := String(o.id)
		if not bool(o.get("lure", false)) or taken.has(id):
			continue
		if not lures.has(id):
			var rows := cmd.rows().filter(func(r: Dictionary) -> bool: return not reserve.has(String(r.id)))
			if rows.size() < 2:
				continue
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.strength_cp) < float(b.strength_cp))
			var lure: Dictionary = rows[0]
			var push: Dictionary = rows[rows.size() - 1]
			var back: Vector3 = (lure.pos as Vector3) - (o.pos as Vector3)
			back.y = 0.0
			back = back.normalized() if back.length() > 0.5 else Vector3.BACK
			var across := back.cross(Vector3.UP)
			lures[id] = {"lure": String(lure.id), "push": String(push.id), "at": t, "state": "luring",
				"rally": (o.pos as Vector3) + back * LURE_BACK_M, "hide": (o.pos as Vector3) + across * PUSH_SIDE_M}
			cmd._log("feigned retreat on %s: %s draws them out, %s waits to push in" % [o.get("label", id), lure.id, push.id])
			continue
		var l: Dictionary = lures[id]
		match String(l.state):
			"luring":
				if t - float(l.at) >= LURE_S:
					l.state = "falling back"
					l.at = t
					cmd._log("%s pulls back from %s" % [l.lure, o.get("label", id)])
					cmd.trigger()
			"falling back":
				var pic := cmd.picture()
				var followed := false
				if pic:
					for e: Dictionary in pic.entries_near(l.rally, LURE_BACK_M):
						if SideCommand._flat(e.pos, o.pos) > float(o.get("radius", 60.0)) + FOLLOW_M:
							followed = true
				if followed:
					l.state = "pushing"
					cmd._log("the garrison of %s followed %s out: %s pushes in" % [o.get("label", id), l.lure, l.push])
					cmd.trigger()


func _lure_needs(o: Dictionary) -> Array:
	var l: Dictionary = lures[String(o.id)]
	var out: Array = []
	match String(l.state):
		"luring":
			out.append({"id": "lure:" + String(o.id), "role": "assault", "pos": o.pos, "target": o.pos, "priority": 9.5, "only": l.lure, "label": "the feint on %s" % o.get("label", o.id)})
			out.append({"id": "hide:" + String(o.id), "role": "reserve", "pos": l.hide, "priority": 9.4, "only": l.push, "label": "waiting to push into %s" % o.get("label", o.id)})
		"falling back":
			out.append({"id": "lure_back:" + String(o.id), "role": "reserve", "pos": l.rally, "priority": 9.5, "only": l.lure, "label": "falling back from %s" % o.get("label", o.id)})
			out.append({"id": "hide:" + String(o.id), "role": "reserve", "pos": l.hide, "priority": 9.4, "only": l.push, "label": "waiting to push into %s" % o.get("label", o.id)})
		"pushing":
			out.append({"id": "push:" + String(o.id), "role": "assault", "pos": o.pos, "target": o.pos, "priority": 10.5, "only": l.push, "label": o.get("label", o.id)})
			out.append({"id": "turn:" + String(o.id), "role": "defend", "pos": l.rally, "facing": (o.pos as Vector3) - (l.rally as Vector3), "priority": 9.5, "only": l.lure,
				"label": "turning on the pursuers"})
	return out


## Whether the plan's current phase is stalled or paused (the brigade's reserve goes to it).
func stalled_now(t: float) -> bool:
	return stalled or t < _paused_until or (started and not current().is_empty() and t - phase_at >= float(current().get("limit_s", 1200.0)))


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
	for g: Dictionary in cmd.my_groups().values():
		g.role = "withdrawn"
		g.need = ""
		cmd._give(g, HcOrder.make(String(g.id), "defend", [[line.x, line.z]]))
	cmd._log("withdrawing to the last line held (%s)" % cmd._grid(line))
