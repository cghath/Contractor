class_name OpTypes
extends RefCounted
## The five operation types (docs/combined_arms.md 6.4; phases D4 and D5, cg_brief queue item 3.3),
## each registered with D3's Operations through its public API (Operations.register_type: hooks
## only, the data stays in data/operations.json "types"):
##   phased_invasion  OpInvasion  (D4) four phases down the MSR, an Abrams section attached, the HQ's
##                                commander alive for a bonus
##   armoured_thrust  OpThrust    (D4) the company screens an armoured column through its blocking
##                                positions down the axis in 45 minutes, a Bradley section attached
##   beach_landing    OpLanding   (D5) AAV waves from the LHD's well deck at dawn, the beach exits, the
##                                harbour, the beachhead held
##   seize_crossing   OpCrossing  (D5) the bridge raced against its demolition, both banks held while
##                                the armour crosses
##   hold_town        OpTown      (D5) ten minutes to prepare from a defence budget, then the town
##                                centre held against two or three waves
## Every type also gets OpSupport (attached armour, allied fires, the trucks, the medevac).
##
## - install(ops): every peer, the zone's Operations node gets "Support" and its type's "Mechanic"
##   (the same paths everywhere, for their RPCs).
## - Hooks: start, tick, phase_begun, phase_done, task, h_hour: Support's then the Mechanic's.
## - Offer rules (eligible): the type's "region" ("coast": a front on the coast; "inland": not;
##   "any"), its "min_rep" with the employer (trusted, 30, unless the type asks more); and the
##   employer's factions.json "operation_types".
## - Rating (rated_sites): an operation is rated by the sites in its "rate_bands" (the ground it
##   fights over), not the whole 8 km zone's garrisons, plus its OOB.
## - Site selectors beyond D3's (resolve_extra): {"exit": "left"|"right"} the beach exits,
##   {"site": "@harbour"}, {"site": "@beachhead"}, {"site": "@firing_point"}, {"bank": "near"|"far"}.

const MECHANIC := "Mechanic"
const TYPES := ["phased_invasion", "armoured_thrust", "beach_landing", "seize_crossing", "hold_town"]
const HOOKS := ["start", "tick", "phase_begun", "phase_done", "task", "h_hour"]


static func mechanic_for(op_type: String) -> OpBase:
	match op_type:
		"phased_invasion":
			return OpInvasion.new()
		"armoured_thrust":
			return OpThrust.new()
		"beach_landing":
			return OpLanding.new()
		"seize_crossing":
			return OpCrossing.new()
		"hold_town":
			return OpTown.new()
	return null


## Registers the five types' hooks (once; again after a test unregistered one).
static func register_all() -> void:
	for t: String in TYPES:
		if not Operations._hooks.has(t):  # (not hook(): it asks this when a type has none)
			Operations.register_type(t, {}, hooks_for(t))


static func hooks_for(_op_type: String) -> Dictionary:
	return {
		"start": func(ops: Operations) -> void: _each(ops, "start", []),
		"resume": func(ops: Operations) -> void: _each(ops, "resume", []),
		"tick": func(ops: Operations, dt: float) -> void: _each(ops, "tick", [dt]),
		"phase_begun": func(ops: Operations, k: int) -> void: _each(ops, "phase_begun", [k]),
		"phase_done": func(ops: Operations, k: int) -> void: _each(ops, "phase_done", [k]),
		"task": func(ops: Operations, o: Dictionary, dt: float) -> String: return _task(ops, o, dt),
		"h_hour": func(ops: Operations) -> bool: return _h_hour(ops),
	}


static func _task(ops: Operations, o: Dictionary, dt: float) -> String:
	var m := mechanic(ops)
	return m.task(o, dt) if m else ""


static func _h_hour(ops: Operations) -> bool:
	var m := mechanic(ops)
	return m.h_hour() if m else true


static func _each(ops: Operations, method: String, args: Array) -> void:
	for n: String in [OpSupport.NODE_NAME, MECHANIC]:
		var m := ops.get_node_or_null(n) as OpBase
		if m:
			m.callv(method, args)


static func mechanic(ops: Operations) -> OpBase:
	return ops.get_node_or_null(MECHANIC) as OpBase if ops else null


## Every peer (Operations._ready): the zone's support and its type's mechanic.
static func install(ops: Operations) -> void:
	if ops.get_node_or_null(OpSupport.NODE_NAME) == null:
		var s := OpSupport.new()
		s.name = OpSupport.NODE_NAME
		ops.add_child(s)
	var t := String(ops.def.get("op_type", ""))
	if ops.get_node_or_null(MECHANIC) == null:
		var m := mechanic_for(t)
		if m:
			m.name = MECHANIC
			ops.add_child(m)


# --- Offer rules -----------------------------------------------------------------------------------

## Why `employer` can't post `op_type` for the front in `zone_id` ("" when it can).
static func eligible(op_type: String, zone_id: String, employer: String) -> String:
	var t := Operations.type_def(op_type)
	if t.is_empty():
		return "no such type"
	var coast := String(MissionRegistry.zone(zone_id).get("region", "")) == "coast"
	match String(t.get("region", "any")):
		"coast":
			if not coast:
				return "%s needs a front on the coast" % String(t.get("name", op_type))
		"inland":
			if coast:
				return "%s is fought inland" % String(t.get("name", op_type))
	var need := int(t.get("min_rep", Operations.knob("", "trusted_rep", 30.0)))
	if employer != "" and Economy.reputation(employer) < need:
		return "%s offer %s only to a company at reputation %d" % [MissionRegistry.faction_name(employer), String(t.get("name", op_type)).to_lower(), need]
	return ""


## The enemy sites an operation of `op_type` fights over in `zdef` (its "rate_bands"; every band
## when it names none): their garrisons count toward its rating.
static func rated_sites(zdef: Dictionary, op_type: String) -> Array:
	var bands: Array = Operations.type_def(op_type).get("rate_bands", [])
	var out: Array = []
	for m: Dictionary in zdef.get("modules", []):
		if not ZoneModules.base(String(m.type)) in Operations.ENEMY_SITES:
			continue
		if not bands.is_empty() and not OperationGen.band_at(zdef, Vector2(float(m.pos[0]), float(m.pos[1]))) in bands:
			continue
		out.append(m)
	return out


## The men of the counterattack waves an operation of `op_type` sends ("counter" in its sections).
static func wave_men(op_type: String) -> int:
	var n := 0
	var t := Operations.type_def(op_type)
	for key: Variant in t:
		var sec: Variant = t[key]
		if sec is Dictionary and (sec as Dictionary).has("counter"):
			for w: Dictionary in (sec as Dictionary).counter:
				n += int(w.get("groups", 1)) * (int(w.get("men", 0)) + int(w.get("crew", 0)) * (w.get("vehicles", []) as Array).size())
	return n


# --- Site selectors ------------------------------------------------------------------------------------

## The sites a selector of the types' own names (see the class doc), [] when it isn't one.
static func resolve_extra(zdef: Dictionary, sel: Dictionary) -> Array:
	var op: Dictionary = zdef.get("op", {})
	var a: Array = op.get("axis", [0, 1])
	var axis := Vector2(float(a[0]), float(a[1]))
	var left := Vector2(-axis.y, axis.x)
	var start: Array = op.get("start", [0, 0])
	var start_p := Vector2(float(start[0]), float(start[1]))
	var lt: Dictionary = Operations.type_def("beach_landing").get("landing", {})
	if sel.has("exit"):
		var gap := float(lt.get("exit_gap_m", 600.0))
		var half := float(zdef.get("size_m", 8192.0)) * 0.5 - 300.0
		var other := start_p + left * gap
		if absf(OperationGen.across(zdef, other)) > half:
			other = start_p - left * gap
		var exits := [start_p, other]
		exits.sort_custom(func(p: Vector2, q: Vector2) -> bool: return OperationGen.across(zdef, p) > OperationGen.across(zdef, q))  # the left exit first
		var p: Vector2 = exits[0] if String(sel.exit) == "left" else exits[1]
		return [{"id": "exit_%s" % String(sel.exit), "label": "the %s beach exit" % String(sel.exit), "pos": [p.x, p.y], "module_id": "", "type": "exit"}]
	if sel.has("bank"):
		var x := crossing(zdef)
		if x.is_empty():
			return []
		var cp := Vector2(float(x.pos[0]), float(x.pos[1]))
		var off := float((Operations.type_def("seize_crossing").get("crossing", {}) as Dictionary).get("bank_m", 90.0))
		var p := cp + axis * (off if String(sel.bank) == "far" else -off)
		return [{"id": "bank_%s" % String(sel.bank), "label": "the %s bank" % String(sel.bank), "pos": [p.x, p.y], "module_id": "", "type": "bank"}]
	if not sel.has("site"):
		return []
	match String(sel.site):
		"@harbour":
			for m: Dictionary in zdef.get("modules", []):
				if String(m.id) == "lm_harbour" or ZoneModules.base(String(m.type)) == "harbour":
					return [{"id": String(m.id), "label": "the harbour", "pos": [float(m.pos[0]), float(m.pos[1])], "module_id": String(m.id), "type": String(m.type)}]
			var best := {}
			var best_d := INF
			for m: Dictionary in zdef.get("modules", []):
				if ZoneModules.base(String(m.type)) != "village":
					continue
				var d := Vector2(float(m.pos[0]), float(m.pos[1])).distance_to(start_p)
				if d < best_d:
					best_d = d
					best = m
			if not best.is_empty():
				return [{"id": String(best.id), "label": "the coastal village", "pos": [float(best.pos[0]), float(best.pos[1])], "module_id": String(best.id), "type": String(best.type)}]
		"@beachhead":
			return [{"id": "beachhead", "label": "the beachhead", "pos": [start_p.x, start_p.y], "module_id": "", "type": "beachhead"}]
		"@firing_point":
			var fp := firing_point(zdef)
			if fp.is_finite():
				return [{"id": "firing_point", "label": "the firing point", "pos": [fp.x, fp.y], "module_id": "", "type": "firing_point"}]
	return []


## The MSR's planned bridge in `zdef` ({} for none): {"pos", "kind", "role"}.
static func crossing(zdef: Dictionary) -> Dictionary:
	for x: Dictionary in (zdef.get("river_hint", {}) as Dictionary).get("crossings", []):
		if String(x.get("role", "")) == "msr":
			return x
	return {}


## Where the enemy's engineers fire the bridge's charges from (6.4.4): "firing_back_m" past the
## bridge on the far bank, "firing_side_m" off the road.
static func firing_point(zdef: Dictionary) -> Vector2:
	var x := crossing(zdef)
	if x.is_empty():
		return Vector2.INF
	var cfg: Dictionary = Operations.type_def("seize_crossing").get("crossing", {})
	var a: Array = (zdef.get("op", {}) as Dictionary).get("axis", [0, 1])
	var axis := Vector2(float(a[0]), float(a[1]))
	var left := Vector2(-axis.y, axis.x)
	return Vector2(float(x.pos[0]), float(x.pos[1])) + axis * float(cfg.get("firing_back_m", 160.0)) + left * float(cfg.get("firing_side_m", 60.0))
