class_name DefencePlan
extends RefCounted
## A defending side's plan (docs/combined_arms.md 3.7; B2): its sites on lines of defence, a
## garrison on each, a mobile reserve, and counterattacks on what it loses.
##
## spec: {"sites": [{"id", "label", "pos", "radius", "line" (0 forward)}], "mobile": [group ids]
##   (its armour and mechanised groups if empty), "rally": Vector3, "hot": false (a hot zone's
##   distances: rally_hot_m)}
## - Garrisons: each site a Defend, by whoever holds it (the nearest group at the start).
## - The mobile reserve holds at the rally, and once the attacker is through the first line it goes
##   to the most threatened site of the next.
## - A site is lost when none of its groups is there and the side's picture shows the enemy in it.
##   Then (Captain's rule, 2026-10-17): retaken only by a force that can retake it, ratio x the CP
##   seen there (called off under call_off), with AT power at least at_share of any armour seen;
##   else contained. A stale picture there gets a probe first. The force assembles out of sight
##   rally_m short and goes wait_s after the loss (or once assembled), a prep landing prep_s before.
## - Players hear it coming when their side has reported the enemy massing (the friendly picture
##   has an entry near the rally): "Enemy massing at 038 061, expect a counterattack on <site>".
## - Withdrawing (3.5.3, the hostile side): consolidate on the last line.
## Numbers in data/side_command.json "counterattack", Proposed.

var spec: Dictionary
var holders := {}   # site id -> group id
var lost := {}      # site id -> when lost
var ops: Array[Dictionary] = []  # {"site", "state", "groups", "rally", "lost_at", "go_at", "threat", "why"}
var mobile := {}    # group id -> true
var mobile_sent := ""
var consolidating := false
var _rng := RandomNumberGenerator.new()


func _init(p_spec := {}, p_seed := 0) -> void:
	spec = p_spec
	_rng.seed = p_seed if p_seed != 0 else hash(str(p_spec.get("sites", [])))


func task_s() -> float:
	return float((SideCommand.data().get("task_s", {}) as Dictionary).get("defence", 20.0))


func start(_cmd: SideCommand) -> void:
	pass


static func ca() -> Dictionary:
	return SideCommand.data().get("counterattack", {})


func sites() -> Array:
	return spec.get("sites", [])


func site(id: String) -> Dictionary:
	for s: Dictionary in sites():
		if String(s.id) == id:
			return s
	return {}


# --- Each cycle ----------------------------------------------------------------------------------

func update(cmd: SideCommand, t: float) -> void:
	_assign_holders(cmd)
	_pick_mobile(cmd)
	var pic := cmd.picture()
	var b := cmd.board()
	for s: Dictionary in sites():
		var id := String(s.id)
		if lost.has(id):
			continue
		var r := float(s.get("radius", 60.0))
		var ours := false
		for gid: String in cmd.groups:
			var row: Dictionary = b.rows.get(gid, {})
			if not row.is_empty() and SideCommand._flat(row.pos, s.pos) <= r:
				ours = true
		var enemy := pic != null and not pic.entries_near(s.pos, r).is_empty()
		if not ours and enemy:
			lost[id] = t
			cmd._log("%s lost" % String(s.get("label", id)))
			_decide(cmd, s, t)
			cmd.trigger("%s lost" % id)
	for op in ops:
		_step(cmd, op, t)
	_commit_mobile(cmd)


func _assign_holders(cmd: SideCommand) -> void:
	var b := cmd.board()
	for s: Dictionary in sites():
		var id := String(s.id)
		if holders.has(id) and cmd.groups.has(String(holders[id])):
			continue
		var best := ""
		var best_d := INF
		for gid: String in cmd.groups:
			if gid in holders.values() or mobile.has(gid) or _in_op(gid):
				continue
			var row: Dictionary = b.rows.get(gid, {})
			if row.is_empty():
				continue
			var d := SideCommand._flat(row.pos, s.pos)
			if d < best_d:
				best_d = d
				best = gid
		if best != "":
			holders[id] = best


func _pick_mobile(cmd: SideCommand) -> void:
	if not mobile.is_empty():
		return
	for gid: Variant in spec.get("mobile", []):
		mobile[String(gid)] = true
	if mobile.is_empty():
		for row: Dictionary in cmd.rows():
			if String(row.kind) in ["armour_section", "armour_platoon", "mech_infantry"] and not (String(row.id) in holders.values()):
				mobile[String(row.id)] = true


func _in_op(gid: String) -> bool:
	for op in ops:
		if String(op.state) in ["assembling", "attacking", "probing"] and (op.groups as Array).has(gid):
			return true
	return false


## The CP and armour CP the picture shows near `at`.
static func threat(pic: SidePicture, at: Vector3, radius: float) -> Dictionary:
	var cp := 0.0
	var armour := 0.0
	var fresh := -INF
	if pic:
		for e: Dictionary in pic.entries_near(at, radius):
			var k := String(e.kind)
			if SidePicture.is_vehicle_kind(k):
				var v := GroupBoard.vehicle_cp(k)
				cp += v
				if k in ["mbt", "ifv", "light_armour"]:
					armour += v
			else:
				cp += float(e.count) * EnemyCommand.SQUAD_MAN_CP
			fresh = maxf(fresh, float(e.seen_at))
	return {"cp": cp, "armour": armour, "seen_at": fresh}


## 3.7: counterattack, probe or contain for lost site `s` (with any group but the other sites'
## garrisons: its own, driven off, can go back in).
func _decide(cmd: SideCommand, s: Dictionary, t: float) -> void:
	var c := ca()
	var th := threat(cmd.picture(), s.pos, float(s.get("radius", 60.0)) + 150.0)
	var stale := t - float(th.seen_at) > float(c.get("stale_s", 180.0))
	var free: Array[Dictionary] = []
	for row: Dictionary in cmd.rows():
		var gid := String(row.id)
		var garrison := false
		for sid: String in holders:
			garrison = garrison or (sid != String(s.id) and String(holders[sid]) == gid and not lost.has(sid))
		if (garrison and not mobile.has(gid)) or _in_op(gid) or String(row.role) == "reconstituting":
			continue
		free.append(row)
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return SideCommand._flat(a.pos, s.pos) < SideCommand._flat(b.pos, s.pos))
	var op := {"site": String(s.id), "state": "", "groups": [], "lost_at": t, "threat": float(th.cp), "armour": float(th.armour), "why": ""}
	if stale and not free.is_empty():
		var smallest: Dictionary = free[0]
		for row in free:
			if float(row.strength_cp) < float(smallest.strength_cp):
				smallest = row
		op.state = "probing"
		op.groups = [String(smallest.id)]
		op.why = "the picture there is stale: a probe first"
		ops.append(op)
		cmd._log("%s: %s" % [String(s.id), op.why])
		return
	var need := float(th.cp) * float(c.get("ratio", 3.0))
	var have := 0.0
	var at := 0.0
	var force: Array = []
	for row in free:
		if have >= need and at >= float(th.armour) * float(c.get("at_share", 0.25)):
			break
		force.append(String(row.id))
		have += float(row.strength_cp)
		at += float(row.at_cp)
	var why := "%.0f CP against %.1f seen (needs %.0f), AT %.0f against armour %.0f" % [have, float(th.cp), need, at, float(th.armour)]
	if have < need or at < float(th.armour) * float(c.get("at_share", 0.25)) or force.is_empty():
		op.state = "contained"
		op.why = why
		ops.append(op)
		cmd._log("contain %s: %s" % [String(s.id), why])
		return
	var rally := _rally(cmd, s, force)
	op.state = "assembling"
	op.groups = force
	op.rally = rally
	var w: Array = c.get("wait_s", [300.0, 720.0])
	op.go_at = t + _rng.randf_range(float(w[0]), float(w[1]))
	op.prep_done = false
	op.why = why
	ops.append(op)
	cmd._log("counterattack on %s: %s, assembling at %s" % [String(s.id), why, cmd._grid(rally)])
	cmd.counterattack_seen.emit(op)
	_telegraph(cmd, op, s)


## Out of sight, rally_m short of the site on the side its force comes from.
func _rally(cmd: SideCommand, s: Dictionary, force: Array) -> Vector3:
	var c := ca()
	var from := Vector3.ZERO
	var n := 0
	for gid: String in force:
		var row: Dictionary = cmd.board().rows.get(gid, {})
		if not row.is_empty():
			from += row.pos
			n += 1
	var dir: Vector3 = (from / n - s.pos) if n > 0 else Vector3.BACK
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	var span: Array = c.get("rally_m", [600.0, 1200.0])
	var d := float(c.get("rally_hot_m", 150.0)) if bool(spec.get("hot", false)) else _rng.randf_range(float(span[0]), float(span[1]))
	return (s.pos as Vector3) + dir * d


## The friendly side hears of it only if it has reported the enemy there.
func _telegraph(cmd: SideCommand, op: Dictionary, s: Dictionary) -> void:
	if cmd.side == &"friendly":
		return
	var friendly := SideIntel.picture_of(cmd, &"friendly")
	var broker := RequestBroker.of(cmd)
	if friendly == null or broker == null or friendly.entries_near(op.rally, 300.0).is_empty():
		return
	var mins := maxi(roundi((float(op.go_at) - cmd.now()) / 60.0), 1)
	broker._say("Shadow", "Shadow, enemy massing at %s, expect a counterattack on %s in about %d minutes." % [cmd._grid(op.rally),
		String(s.get("label", s.id)), mins])


func _step(cmd: SideCommand, op: Dictionary, t: float) -> void:
	var s := site(String(op.site))
	var c := ca()
	match String(op.state):
		"probing":
			var gid0 := String((op.groups as Array)[0]) if not (op.groups as Array).is_empty() else ""
			var row: Dictionary = cmd.board().rows.get(gid0, {})
			var seen := not cmd.picture().entries_near(s.pos, 300.0).is_empty() and t - float(op.lost_at) > 120.0
			if row.is_empty():
				op.state = "failed"
				lost.erase(op.site)  # decided again with what it has
			elif SideCommand._flat(row.pos, s.pos) <= float(s.get("radius", 60.0)) + 100.0 or seen:
				op.state = "done"
				lost.erase(op.site)  # the probe saw: decide again
				cmd._log("probe at %s reports; deciding again" % String(op.site))
		"assembling":
			var all_there := true
			for gid: String in op.groups:
				var row: Dictionary = cmd.board().rows.get(gid, {})
				if row.is_empty() or SideCommand._flat(row.pos, op.rally) > float(c.get("assembled_m", 50.0)):
					all_there = false
			if not bool(op.get("prep_done", false)) and t >= float(op.go_at) - float(c.get("prep_s", 60.0)):
				op.prep_done = true
				cmd.fire_support_wanted.emit(s.pos, "preparation for the counterattack on %s" % op.site)
			if all_there or t >= float(op.go_at):
				op.state = "attacking"
				cmd._log("counterattack on %s goes in (%s)" % [String(op.site), "assembled" if all_there else "on time"])
				cmd.trigger()
		"attacking":
			var have := 0.0
			for gid: String in op.groups:
				have += float((cmd.board().rows.get(gid, {}) as Dictionary).get("strength_cp", 0.0))
			var th := threat(cmd.picture(), s.pos, float(s.get("radius", 60.0)) + 150.0)
			if float(th.cp) > 0.0 and have < float(th.cp) * float(c.get("call_off", 1.5)):
				op.state = "called off"
				cmd._log("counterattack on %s called off: %.0f CP against %.1f" % [String(op.site), have, float(th.cp)])
				cmd.trigger()
				return
			var ours := false
			for gid: String in op.groups:
				var row: Dictionary = cmd.board().rows.get(gid, {})
				if not row.is_empty() and SideCommand._flat(row.pos, s.pos) <= float(s.get("radius", 60.0)):
					ours = true
			if ours and cmd.picture().entries_near(s.pos, float(s.get("radius", 60.0))).is_empty():
				op.state = "done"
				lost.erase(op.site)
				holders[String(op.site)] = String((op.groups as Array)[0])
				cmd._log("%s retaken" % String(op.site))
				cmd.trigger()


## Once a forward (line 0) site is lost, the mobile reserve goes to the most threatened site of the
## next line.
func _commit_mobile(cmd: SideCommand) -> void:
	if mobile_sent != "" or mobile.is_empty():
		return
	var broken := lost.keys().any(func(id: String) -> bool: return int(site(id).get("line", 0)) == 0)
	if not broken:
		return
	var best := ""
	var most := -1.0
	for s: Dictionary in sites():
		if int(s.get("line", 0)) != 1 or lost.has(String(s.id)):
			continue
		var th := threat(cmd.picture(), s.pos, 400.0)
		if float(th.cp) > most:
			most = float(th.cp)
			best = String(s.id)
	if best != "":
		mobile_sent = best
		cmd._log("the mobile reserve goes to %s" % best)
		cmd.trigger()


func counterattack_seen(_cmd: SideCommand) -> bool:
	return ops.any(func(op: Dictionary) -> bool: return String(op.state) in ["assembling", "attacking"])


# --- Needs ---------------------------------------------------------------------------------------

func needs(cmd: SideCommand, _t: float) -> Array:
	var out: Array = []
	var rally: Vector3 = spec.get("rally", Vector3.ZERO)
	for s: Dictionary in sites():
		var id := String(s.id)
		if lost.has(id) or consolidating and int(s.get("line", 0)) < _last_line():
			continue
		out.append({"id": "hold:" + id, "role": "defend", "pos": s.pos, "priority": 6.0 + float(s.get("line", 0)) * 0.1,
			"only": String(holders.get(id, "")), "label": String(s.get("label", id))})
	for op in ops:
		var s := site(String(op.site))
		for gid: String in op.groups:
			match String(op.state):
				"probing":
					out.append({"id": "probe:%s:%s" % [op.site, gid], "role": "probe", "pos": s.pos, "priority": 8.0, "only": gid, "label": "a probe of %s" % op.site})
				"assembling":
					out.append({"id": "assemble:%s:%s" % [op.site, gid], "role": "qrf", "pos": op.rally, "priority": 9.0, "only": gid, "label": "the assembly for %s" % op.site})
				"attacking":
					out.append({"id": "ca:%s:%s" % [op.site, gid], "role": "counterattack", "pos": s.pos, "target": s.pos, "priority": 10.0, "only": gid,
						"label": String(s.get("label", op.site))})
	for gid: String in mobile:
		if _in_op(gid):
			continue
		var to: Vector3 = site(mobile_sent).pos if mobile_sent != "" else rally
		out.append({"id": "mobile:" + gid, "role": "defend" if mobile_sent != "" else "reserve", "pos": to, "priority": 7.0, "only": gid,
			"label": "the mobile reserve"})
	return out


func _last_line() -> int:
	var top := 0
	for s: Dictionary in sites():
		top = maxi(top, int(s.get("line", 0)))
	return top


## The hostile side consolidates on its last line (3.5.3).
func withdraw(cmd: SideCommand, _t: float) -> void:
	consolidating = true
	for op in ops:
		if String(op.state) in ["assembling", "attacking", "probing"]:
			op.state = "called off"
	cmd._log("consolidating on line %d" % (_last_line() + 1))
	cmd.withdrawn = false  # it still holds what it has left: the cycle goes on
	cmd.trigger()


func rally_for(_cmd: SideCommand, _g: Dictionary) -> Vector3:
	return spec.get("rally", Vector3.INF)
