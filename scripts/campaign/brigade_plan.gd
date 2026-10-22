class_name BrigadePlan
extends RefCounted
## A brigade: its companies plus a command element (docs/ai_tactics.md 6; P3). Each company runs
## its own plan (OperationPlan or DefencePlan) over its own groups (SideCommand.server_register's
## `company`); the command element keeps one company in reserve and moves the main effort: a
## company whose phase stalls gets the brigade's fires first, then the reserve company, sent at
## that company's main objective. SideCommand runs it like any plan.

var companies := {}       # company id -> its plan
var reserve_company := ""
var rally := Vector3.ZERO
## The company the reserve company was sent to ("" while it's held).
var committed_to := ""


func _init(p_companies := {}, p_reserve := "", p_rally := Vector3.ZERO) -> void:
	companies = p_companies
	reserve_company = p_reserve
	rally = p_rally


func task_s() -> float:
	var s := INF
	for id: String in companies:
		s = minf(s, float(companies[id].call(&"task_s")))
	return s if s < INF else 20.0


func start(cmd: SideCommand) -> void:
	for id: String in companies:
		cmd.company = id
		if companies[id].has_method(&"start"):
			companies[id].call(&"start", cmd)
	cmd.company = ""


func update(cmd: SideCommand, t: float) -> void:
	for id: String in companies:
		cmd.company = id
		companies[id].call(&"update", cmd, t)
	cmd.company = ""
	if committed_to != "" or reserve_company == "":
		return
	for id: String in companies:
		var p: RefCounted = companies[id]
		if p.has_method(&"stalled_now") and bool(p.call(&"stalled_now", t)):
			committed_to = id
			var target := _main_of(id)
			cmd.fire_support_wanted.emit(target, "the brigade's fires for %s first" % id)
			cmd._log("brigade: %s is stalled: the brigade's fires to it first, then %s" % [id, reserve_company])
			cmd.trigger()
			return


## The company's main objective (its current phase's), else its first site.
func _main_of(id: String) -> Vector3:
	var p: RefCounted = companies.get(id)
	if p is OperationPlan:
		var o: Dictionary = (p as OperationPlan).objective((p as OperationPlan).main_id())
		if not o.is_empty():
			return o.pos
	if p is DefencePlan and not (p as DefencePlan).sites().is_empty():
		return (p as DefencePlan).sites()[0].pos
	return rally


func needs(cmd: SideCommand, t: float) -> Array:
	var out: Array = []
	for id: String in companies:
		cmd.company = id
		var mine := cmd.my_groups()
		var others := {}
		for gid: String in cmd.groups:
			if not mine.has(gid):
				others[gid] = true
		for n: Dictionary in companies[id].call(&"needs", cmd, t):
			if String(n.get("only", "")) == "":
				var ex: Dictionary = (n.get("exclude", {}) as Dictionary).duplicate()
				ex.merge(others)
				n["exclude"] = ex  # a company's needs are its own groups'
			n["company"] = id
			out.append(n)
	cmd.company = reserve_company
	for gid: String in cmd.my_groups():
		if committed_to != "":
			var target := _main_of(committed_to)
			out.append({"id": "brigade_reserve:%s:%s" % [committed_to, gid], "role": "assault", "pos": target, "target": target, "priority": 10.2,
				"only": gid, "label": "%s's objective (the brigade reserve)" % committed_to})
		else:
			out.append({"id": "brigade_reserve:" + gid, "role": "reserve", "pos": rally, "priority": 9.0, "only": gid, "label": "the brigade reserve"})
	cmd.company = ""
	return out


func axis_dir() -> Vector3:
	for id: String in companies:
		if companies[id].has_method(&"axis_dir"):
			return companies[id].call(&"axis_dir")
	return Vector3.FORWARD


func rally_for(cmd: SideCommand, g: Dictionary) -> Vector3:
	var p: RefCounted = companies.get(String(g.get("company", "")))
	if p and p.has_method(&"rally_for"):
		return p.call(&"rally_for", cmd, g)
	return rally


func withdraw(cmd: SideCommand, t: float) -> void:
	for id: String in companies:
		if companies[id].has_method(&"withdraw"):
			cmd.company = id
			companies[id].call(&"withdraw", cmd, t)
	cmd.company = ""


func counterattack_seen(cmd: SideCommand) -> bool:
	for id: String in companies:
		if companies[id].has_method(&"counterattack_seen") and bool(companies[id].call(&"counterattack_seen", cmd)):
			return true
	return false
