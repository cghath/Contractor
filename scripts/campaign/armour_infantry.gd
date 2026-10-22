class_name ArmourInfantry
extends RefCounted
## Armour and infantry together (docs/combined_arms.md 3.6; phase B3), for SideCommand: it pairs
## each armour section or IFV with an infantry group as its screen and keeps them together by the
## ground, hands targets the infantry can't take to its armour, and has armour ask for infantry
## against the AT teams it can't hit. Pure where it can be; apply() rewrites a cycle's needs.
##
## | Ground | Who leads | How |
## | Open | Armour | overwatch, open_overwatch_m back from the infantry's objective; IFVs dismount
##   their infantry dismount_m short in dead ground |
## | Woods, broken | Infantry | armour follow_woods_m behind on its track |
## | Town | Infantry | armour follow_town_m behind, and never past the town's edge before its
##   screen is in the town; never first round a corner |
## | Night | Armour with thermals | recon prefers armour and IFVs (their thermal sights, A4) |
## - Paired: within pair_m (50-150 m) of each other; the screen's sector faces out; its first job is
##   the AT teams near the armour.
## - Hand-off: an infantry group whose objective holds an MG or a gun it can't take (it's AMBER, or
##   held up there handoff_s) marks it to its armour: "Anvil 1, MG at 041 053, my tracer"; the
##   armour supports by fire on it (HE or AMP from A3's gunners when they're in).
## - Armour asks: an AT team reported within at_threat_m of armour gets the pair (or the nearest
##   infantry the commander has) sent at it; none free, a player near is asked (RequestBroker).
## Numbers in data/side_command.json "armour_infantry", Proposed.

const ARMOUR: Array[String] = ["armour_section", "armour_platoon", "mech_infantry", "light_armour"]
const INFANTRY: Array[String] = ["rifle_squad", "weapons_team", "at_team", "qrf", "recon_team", "engineers"]
const FORTIFIED: Array[String] = ["mg", "static_gun", "at"]


static func cfg() -> Dictionary:
	return SideCommand.data().get("armour_infantry", {})


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


## Pairs armour rows with infantry rows, nearest first, each used once: {armour id: infantry id}.
## Pairs in `previous` whose both groups are still there stay as they were (they move as one).
static func pair(rows: Array, previous := {}) -> Dictionary:
	var armour: Array = rows.filter(func(r: Dictionary) -> bool: return String(r.kind) in ARMOUR and String(r.kind) != "mech_infantry")
	var infantry: Array = rows.filter(func(r: Dictionary) -> bool: return String(r.kind) in INFANTRY)
	var out := {}
	var used := {}
	var present := {}
	for r: Dictionary in rows:
		present[String(r.id)] = true
	for aid: String in previous:
		if present.has(aid) and present.has(String(previous[aid])):
			out[aid] = String(previous[aid])
			used[String(previous[aid])] = true
	for a: Dictionary in armour:
		if out.has(String(a.id)):
			continue
		var best := ""
		var best_d := INF
		for i: Dictionary in infantry:
			if used.has(String(i.id)):
				continue
			var d := SideCommand._flat(a.pos, i.pos)
			if d < best_d:
				best_d = d
				best = String(i.id)
		if best != "":
			out[String(a.id)] = best
			used[best] = true
	return out


## The ground at `pos`: "town" (inside a town or village module, or an objective marked town),
## "woods" (the scatter's trees thick there), else "open"; "night" overrides open after dark.
static func ground(level: Node, pos: Vector3, town_hint := false) -> String:
	if town_hint or town_at(level, pos) != null:
		return "town"
	if level:
		var scatter := Spotting.scatter_of(level as Node3D) if level is Node3D else null
		if scatter:  # woods: foliage across most of a 60 m look either way
			var span := n("woods_probe_m", 30.0)
			var through := scatter.foliage_between(pos + Vector3(-span, 1.5, 0), pos + Vector3(span, 1.5, 0)) \
				+ scatter.foliage_between(pos + Vector3(0, 1.5, -span), pos + Vector3(0, 1.5, span))
			if through >= n("woods_foliage_m", 30.0):
				return "woods"
		var dn := level.get_node_or_null(^"DayNight")
		if dn and DayNight.night_of(float(dn.get(&"hour"))) > 0.5:
			return "night"
	return "open"


## The town or village module `pos` is in (or within town_edge_m of), or null.
static func town_at(level: Node, pos: Vector3, margin := 0.0) -> ZoneModule:
	if level == null or not level.has_method(&"modules"):
		return null
	for m: ZoneModule in level.call(&"modules"):
		var base := ZoneModules.base(m.type)
		if (base.begins_with("town") or base.begins_with("village")) and m.distance_to(pos) <= margin:
			return m
	return null


## Where paired armour should be (3.6), given its infantry at `inf_pos` heading for `objective`
## along `axis_dir`, on `ground_kind`.
static func escort_spot(ground_kind: String, inf_pos: Vector3, objective: Vector3, axis_dir: Vector3) -> Vector3:
	var dir := axis_dir
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	match ground_kind:
		"open", "night":
			var back := objective - dir * n("open_overwatch_m", 1000.0)
			return back if SideCommand._flat(back, objective) < SideCommand._flat(inf_pos, objective) + n("open_overwatch_m", 1000.0) else inf_pos
		"woods":
			return inf_pos - dir * n("follow_woods_m", 150.0)
	return inf_pos - dir * n("follow_town_m", 75.0)


## A spot inside a town is held at the town's edge until its screen is in the town (3.6): the
## point on the town's footprint edge nearest `from`.
static func town_edge(level: Node, spot: Vector3, from: Vector3, screen_pos: Vector3) -> Vector3:
	var town := town_at(level, spot)
	if town == null or town_at(level, screen_pos) == town:
		return spot
	var r := town.footprint()
	var p := Vector2(spot.x, spot.z)
	var f := Vector2(from.x, from.z)
	var edge := p
	for k in 32:  # walk back toward where it came from until it's out
		edge = p.lerp(f, float(k + 1) / 32.0)
		if not r.grow(n("town_edge_m", 5.0)).has_point(edge):
			break
	return Vector3(edge.x, spot.y, edge.y)


## Where an IFV puts its infantry down: dismount_m short of the objective along the axis, the
## candidate with no line from any reported enemy (dead ground) if one has none.
static func dismount_spot(level: Node3D, objective: Vector3, axis_dir: Vector3, enemies: Array) -> Vector3:
	var dir := axis_dir
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var lo := n("dismount_min_m", 300.0)
	var hi := n("dismount_max_m", 500.0)
	var first := objective - dir * lo
	if level == null or not level.is_inside_tree() or enemies.is_empty():
		return first
	var space := level.get_world_3d().direct_space_state
	for k in 5:
		var d := lerpf(lo, hi, k / 4.0)
		for side in [0.0, -60.0, 60.0]:
			var spot: Vector3 = objective - dir * d + Vector3(-dir.z, 0.0, dir.x) * float(side)
			var hidden := true
			for e: Vector3 in enemies:
				var q := PhysicsRayQueryParameters3D.create(e + Vector3.UP * 1.6, spot + Vector3.UP * 2.0)
				if space.intersect_ray(q).is_empty():
					hidden = false
					break
			if hidden:
				return spot
	return first


## The cycle's needs with 3.6 applied: escorts for paired armour, hand-offs, AT clearing.
static func apply(cmd: SideCommand, needs: Array, axis_dir: Vector3) -> Array:
	var rows := cmd.rows()
	var pairs := pair(rows, cmd.pairs)
	cmd.pairs = pairs
	var by_id := {}
	for r: Dictionary in rows:
		by_id[String(r.id)] = r
	var level := MapNodes.level_of(cmd)
	var out := needs.duplicate()
	for aid: String in pairs:
		var inf: Dictionary = by_id.get(String(pairs[aid]), {})
		var arm: Dictionary = by_id.get(aid, {})
		if inf.is_empty() or arm.is_empty():
			continue
		var ig: Dictionary = cmd.groups.get(String(inf.id), {})
		var target := _target_of(out, String(ig.get("need", "")), inf.pos)
		var kind := ground(level, target, _town_hint(out, String(ig.get("need", ""))))
		var spot := escort_spot(kind, inf.pos, target, axis_dir)
		if kind == "town":
			spot = town_edge(level, spot, arm.pos, inf.pos)
		out = out.filter(func(x: Dictionary) -> bool: return String(x.get("only", "")) != aid)  # its escort replaces the rest
		out.append({"id": "escort:" + aid, "role": "overwatch", "pos": spot, "facing": axis_dir, "priority": 7.5, "only": aid,
			"label": "%s's escort (%s)" % [cmd.groups.get(String(inf.id), {}).get("callsign", inf.id), kind]})
	var paired := {}
	for aid: String in pairs:
		paired[aid] = true
	for x: Dictionary in out:  # paired armour takes only its own tasks (escort, hand-offs)
		if String(x.get("only", "")) == "":
			var ex: Dictionary = (x.get("exclude", {}) as Dictionary).duplicate()
			ex.merge(paired)
			x["exclude"] = ex
	out.append_array(_hand_offs(cmd, pairs, by_id))
	out.append_array(_at_threats(cmd, pairs, by_id))
	return out


static func _target_of(needs: Array, need_id: String, fallback: Vector3) -> Vector3:
	for x: Dictionary in needs:
		if String(x.id) == need_id:
			return x.get("target", x.pos)
	return fallback


static func _town_hint(needs: Array, need_id: String) -> bool:
	for x: Dictionary in needs:
		if String(x.id) == need_id:
			return bool(x.get("town", false))
	return false


## Infantry held up by a fortified target marks it to its armour (3.6's hand-off).
static func _hand_offs(cmd: SideCommand, pairs: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = []
	var pic := cmd.picture()
	if pic == null:
		return out
	for aid: String in pairs:
		var ig: Dictionary = cmd.groups.get(String(pairs[aid]), {})
		var row: Dictionary = by_id.get(String(pairs[aid]), {})
		if ig.is_empty() or not (String(ig.role) in ["assault", "flank", "sbf"]):
			continue
		var so := ig.orders as SquadOrders
		var held := so != null and so._exec_at > -INF and Soldier._now() - so._exec_at >= n("handoff_s", 60.0)  # in on it a minute, not through
		if String(row.get("ce_band", "green")) == "green" and not held:
			continue
		var target: Vector3 = so._target if so and so._target.is_finite() else Vector3.INF
		if not target.is_finite():
			continue
		for e: Dictionary in pic.entries_near(target, n("handoff_m", 60.0)):
			if String(e.kind) in FORTIFIED:
				out.append({"id": "handoff:%s:%d" % [aid, int(e.id)], "role": "sbf", "pos": by_id[aid].pos, "target": e.pos, "priority": 9.5,
					"only": aid, "label": "%s's %s" % [ig.callsign, String(e.kind).to_upper()], "handoff": true})
				if not cmd.handed.has("%s|%d" % [aid, int(e.id)]):
					cmd.handed["%s|%d" % [aid, int(e.id)]] = true
					var ag: Dictionary = cmd.groups.get(aid, {})
					cmd._say(ig, "request", "%s, %s, %s at %s, %d metres, my tracer." % [ag.get("callsign", aid), ig.callsign, String(e.kind).to_upper(),
						cmd._grid(e.pos), roundi(SideCommand._flat(row.pos, e.pos))])
				break
	return out


## AT teams reported near armour: its pair (or the nearest infantry) goes at them; with none free a
## player near is asked.
static func _at_threats(cmd: SideCommand, pairs: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = []
	var pic := cmd.picture()
	if pic == null:
		return out
	for aid: String in pairs:
		var arm: Dictionary = by_id.get(aid, {})
		for e: Dictionary in pic.entries_near(arm.pos, n("at_threat_m", 400.0)):
			if String(e.kind) != "at":
				continue
			var iid := String(pairs[aid])
			out.append({"id": "clear_at:%d" % int(e.id), "role": "assault", "pos": e.pos, "target": e.pos, "priority": 9.8, "only": iid, "override": true,
				"label": "the AT team near %s" % cmd.groups.get(aid, {}).get("callsign", aid)})
			if not cmd.handed.has("at|%d" % int(e.id)):
				cmd.handed["at|%d" % int(e.id)] = true
				var ag: Dictionary = cmd.groups.get(aid, {})
				cmd._say(ag, "request", "%s, AT team at %s, need it cleared before we move." % [ag.get("callsign", aid), cmd._grid(e.pos)])
				var broker := RequestBroker.of(cmd)
				if broker and cmd.side == &"friendly" and String((cmd.groups.get(iid, {}) as Dictionary).get("role", "")) in ["assault", "counterattack"]:
					broker.server_ask_players(aid, "ask_clear_at", arm.pos, "%s, AT team at %s, need infantry to clear it before we move." % [ag.get("callsign", aid), cmd._grid(e.pos)])
			break
	return out
