class_name Operations
extends Node
## Operation contracts (docs/combined_arms.md 6.1, 6.3-6.6, 3.5; phase D3, cg_brief queue item 3.2):
## government employers' big jobs in an 8 km operation zone (OperationGen), fought in phases beside
## the employer's forces, paid by phase, feeding the living war. Two halves:
##
## Static (no level: the board, the debrief, the economy sim):
## - make_offer(): a front of a belligerent employer (WorldSites) posts an `operation` contract
##   (Contracts.operation_offers): its type (data/operations.json, the employer's factions.json
##   "operation_types" that are offered), its zone ("op_<seed>": OperationGen.generate over the front's
##   zone and its neighbours the target holds, the def's controller the target as WorldSites has it),
##   its phases (each a phase line, a time limit, a pay share, the allied objectives and the
##   company's task), its OOBs, allied fires and attached vehicles. zone_def() answers for its zone
##   (MissionRegistry.zone_def's hook), so the deployment, the briefing and a resumed save load it.
## - Pay by phase (6.5): deal() takes 20% on signing; server_phase_done() pays each phase's share of
##   the rest into the one bank as it's done (phase_pay: its bonuses and penalties), a ledger line
##   each; debrief_into() writes the debrief's line phase by phase (what's already paid isn't paid
##   again) and the outcome: completed, partial or failed. phases_done() is what the war hears
##   (WorldSites.server_operation_ended, 6.6).
##
## The node (one per operation zone level, "Operations", every peer; ZoneLevel installs it):
## - Host: the run of the deployed operation contract whose zone this is (its "op_run", saved with
##   the contract): the clock, H-hour, the phases one after another (the company's task objectives
##   added as each begins, the phase done when its task and its required allied objectives are, a
##   stall at side_command.json phase_fail_share x its limit), the commanders (a friendly
##   SideCommand with an OperationPlan from the phases, a hostile one with a DefencePlan over the
##   enemy's sites; their phases, reserves and withdrawal are B2's), the OOB spawned by the front
##   within BigZoneStreaming's caps, the enemy's reinforcements on its side of the front, the front
##   grid (FrontGrid) and its line on the map (MapMarkers, intel channel).
## - Every peer: `view` (what the HUD's OperationStrip shows) and the front grid, from the host
##   (whole on asking: a late joiner; then deltas).
##
## For D4/D5 (the mission types): register_type(op_type, def, hooks) adds or overrides a type's
## data and hooks, called with this node: "phases" (def, type) -> phases (replaces build_phases),
## "start" (ops) once the run starts, "tick" (ops, dt) every tick, "phase_begun" (ops, k),
## "phase_done" (ops, k), "task" (ops, objective, dt) -> "" or a state for a kind of its own, "pay"
## (contract, k, facts, result) to adjust a phase's pay, "h_hour" (ops) -> bool (H-hour has come:
## the beach landing's dawn). Numbers in data/operations.json, all Proposed.

signal phase_changed(index: int)
signal front_changed(cells: PackedInt32Array)

const NODE_NAME := "Operations"
const PATH := "res://data/operations.json"
const KIND := "operation"
const ZONE_PREFIX := "op_"
## Objective kinds of the company's tasks (Objectives' KINDS lists them).
const SEIZE_SITE := "seize_site"
const HOLD_LINE := "hold_line"
const KEEP_INTACT := "keep_intact"
## Phase and run states.
const PENDING := "pending"
const RUNNING := "running"
const DONE := "done"
const FAILED := "failed"
const WAITING := "waiting"
const STALLED := "stalled"
## Module types the enemy holds in an operation zone (its sites).
const ENEMY_SITES: Array[String] = ["outpost", "checkpoint", "hq", "qrf_base", "comms", "town", "compound"]

static var _data := {}
static var _defs := {}
static var _extra := {}
static var _hooks := {}

## Every peer: what the strip shows ({} until the host has said): "name", "type", "state", "phase",
## "clock_s", "phases": [{"name", "state", "limit_s", "started_s", "done_s"}], "task": [texts],
## "front_m", "line_m", "share", "allied".
var view := {}
## Every peer: the front.
var grid: FrontGrid
## The zone's def (the level's).
var def := {}
## Host: the contract id, its commanders and their plans.
var cid := ""
var friendly: SideCommand
var hostile: SideCommand
var plan: OperationPlan
var defence: DefencePlan
## Host: groups spawned from the OOB: entry id -> {"squad", "soldiers", "vehicles", "v_nosave"}.
var records := {}
## Host: every line said (tests).
var said: Array[String] = []
## Host: the last front cycle's cost (µs): the grid's and the whole gather.
var cycle_us := 0.0
## Its parts, µs: {"presence", "sites", "grid", "rest"} (the budgets check reads them).
var cycle_parts := {}

var _level: Node
var _tick_left := 0.0
var _front_left := 0.0
var _sync_left := 0.0
var _save_left := 0.0
var _spawning: Array[Dictionary] = []  # {"entry", "men": [spec], "vehicles": [model], "squad", "made": []}
var _front_marker := 0
var _front_marker_rev := -1
var _seize := {}     # oid -> seconds held
var _hold := {}      # oid -> seconds held
var _bridge_of := {} # oid -> bridge index
var _expected := {}  # module id -> its expected garrison (ZoneLevel.garrison_size, read once a run)
var _overrun_since := {}  # module id -> since when the allies have the presence
var _rng := RandomNumberGenerator.new()
var _withdraw_seen := false
var _clock_at := 0.0  # clients: Time when view.clock_s arrived
var _serial := 0


# --- Data --------------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {"_missing": true}
	return _data


static func knob(section: String, key: String, fallback := 0.0) -> float:
	var sec: Variant = data().get(section, {}) if section != "" else data()
	return float((sec as Dictionary).get(key, fallback)) if sec is Dictionary else fallback


## The type's data (data/operations.json "types", or one register_type added), {} for none.
static func type_def(op_type: String) -> Dictionary:
	if _extra.has(op_type):
		return _extra[op_type]
	return (data().get("types", {}) as Dictionary).get(op_type, {})


static func type_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Variant in (data().get("types", {}) as Dictionary).keys() + _extra.keys():
		if not String(t) in out:
			out.append(String(t))
	return out


## D4/D5: adds a type (or merges `p_def` over its data) and its hooks (see the class doc).
static func register_type(op_type: String, p_def := {}, hooks := {}) -> void:
	if not p_def.is_empty():
		var base := type_def(op_type).duplicate(true)
		base.merge(p_def, true)
		_extra[op_type] = base
	if not hooks.is_empty():
		_hooks[op_type] = hooks.duplicate()


static func unregister_type(op_type: String) -> void:
	_extra.erase(op_type)
	_hooks.erase(op_type)


## Type `op_type`'s hook `hook_name` (an invalid Callable when it has none).
static func hook(op_type: String, hook_name: String) -> Callable:
	var c: Variant = (_hooks.get(op_type, {}) as Dictionary).get(hook_name)
	return c if c is Callable and (c as Callable).is_valid() else Callable()


## The types `employer` posts now: its factions.json "operation_types" whose data says "offer".
static func offered_types(employer: String) -> Array[String]:
	var out: Array[String] = []
	for t: Variant in MissionRegistry.faction(employer).get("operation_types", []):
		if bool(type_def(String(t)).get("offer", false)):
			out.append(String(t))
	return out


static func is_operation(c: Dictionary) -> bool:
	return String(c.get("kind", "")) == KIND


# --- Offers ------------------------------------------------------------------------------------------

## The zones an operation from front `zone_id` against `target` covers: the front's zone, then its
## neighbours on the region map the target holds (by id), up to "covers_max".
static func covers_for(zone_id: String, target: String) -> Array:
	var out: Array = [zone_id]
	var near: Array = []
	for l: Dictionary in RegionMap.links(zone_id):
		var n := String(l.to)
		if n == RegionMap.BASE or n in out or n in near or MissionRegistry.zone(n).is_empty() or not WorldSites.is_war_zone(n):
			continue
		if WorldSites.holder_now(n) == target:
			near.append(n)
	near.sort()
	for n: String in near:
		if out.size() < int(knob("", "covers_max", 3.0)):
			out.append(n)
	return out


## An operation contract from the front in `zone_id` (WorldSites: `side` attacking, `target`
## holding) for `employer`, of `op_type` (one of its offered types when ""), {} when it posts none.
## Rolled on a generator of its own (seeded from `rng`, which it leaves alone).
static func make_offer(rng: RandomNumberGenerator, today: int, zone_id: String, side: String, target: String, employer: String, op_type := "") -> Dictionary:
	var types := offered_types(employer)
	if op_type == "":
		if types.is_empty():
			return {}
		var pick := RandomNumberGenerator.new()
		pick.seed = hash([rng.seed, rng.state, zone_id, employer, "op_type"])
		op_type = types[pick.randi() % types.size()]
	var t := type_def(op_type)
	if t.is_empty():
		return {}
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([rng.seed, rng.state, zone_id, employer, op_type, today])
	var op_seed := 1 + roll.randi() % 999999
	var covers := covers_for(zone_id, target)
	var c := {"kind": KIND, "op_type": op_type, "op_seed": op_seed, "op_zone": "%s%d" % [ZONE_PREFIX, op_seed], "covers": covers, "target": target}
	var zdef := def_for(c)
	var phases := build_phases(zdef, op_type)
	var names: Dictionary = data().get("names", {})
	var first: Array = names.get("first", ["GREY"])
	var second: Array = names.get("second", ["LANCE"])
	var codename := "%s %s" % [first[roll.randi() % first.size()], second[roll.randi() % second.size()]]
	# The enemy: its OOB's men and the sites' garrisons; rated as any contract.
	var oob := enemy_oob(zdef, op_type, roll)
	var count := 0
	var threats: Array = []
	for e: Dictionary in oob:
		count += int(e.men) + int(e.crew) * (e.vehicles as Array).size()
		if not (e.vehicles as Array).is_empty() and not "armor" in threats:
			threats.append("armor")
		if String(e.kind) == "gun_team" and not "mg_nest" in threats:
			threats.append("mg_nest")
		if String(e.kind) == "qrf" and not "qrf" in threats:
			threats.append("qrf")
	for m: Dictionary in zdef.get("modules", []):
		if ZoneModules.base(String(m.type)) in ENEMY_SITES:
			count += (ZoneModules.GARRISON.get(ZoneModules.base(String(m.type)), []) as Array).size()
	var quality := snappedf(roll.randf_range(0.4, 0.65), 0.01)
	var rated := ContractGen.rating(count, quality, threats)
	var pay_mult := float((MissionRegistry.setting("difficulty_pay", [0, 1, 1, 1, 1, 1]) as Array)[rated])
	pay_mult *= float(MissionRegistry.faction(employer).get("op_pay_mult", 1.0))
	var step := maxi(MissionRegistry.setting_i("pay_round", 500), 1)
	var base_pay := maxi(step, roundi(float(t.get("base_pay", 160000)) * pay_mult / step) * step)
	var zones_text := " and ".join(PackedStringArray(covers.map(func(z: Variant) -> String: return RegionMap.zone_name(String(z)))))
	var phase_text := PackedStringArray()
	for p: Dictionary in phases:
		phase_text.append("%s (%d%%, %d min)" % [String(p.name), roundi(float(p.pay_share) * 100.0), roundi(float(p.limit_s) / 60.0)])
	var brief := "%s are attacking %s, held by %s, and want the company in the push. %s Phases: %s. Paid by phase as each is done; 20%% on signing. The result decides the fight there." % [
		WorldSites.holder_name(side), zones_text, WorldSites.holder_name(target), String(t.get("brief", "")), ", ".join(phase_text)]
	var est := maxi(1, roundi(count * roll.randf_range(0.8, 1.2)))
	var offer := {
		"cid": "", "kind": KIND, "operation": true, "type": op_type, "op_type": op_type, "op_seed": op_seed, "op_zone": String(c.op_zone),
		"covers": covers, "op_front": zone_id, "op_side": side, "op_phases": phases.size(), "codename": codename,
		"title": "Operation %s: %s, %s" % [codename, String(t.get("name", op_type)), zones_text], "brief": brief, "source": "board", "fixer": "",
		"employer": employer, "target": target, "war_driven": true, "leader": "",
		"zone_id": String(c.op_zone), "zone_name": "Operation %s" % codename, "zone_kind": "contract", "region": String(zdef.get("region", "inland")),
		"module": "", "module_id": "", "module_name": "",
		"rated": rated, "squads_max": Heroes.squads_max(rated, false, true), "enemy_est": est, "quality_est": quality, "threats_known": threats.duplicate(),
		"intel_accuracy": 0.8, "true_rating": rated, "enemy_count": count, "quality": quality, "threats": threats, "understated": false,
		"revealed": false, "renegotiated": false, "clawback": ContractGen.PRORATED_CLAWBACK,
		"base_pay": base_pay, "days": int(t.get("days", 2)), "objectives": task_templates(phases, 0, zdef), "legs": [],
		"offered_day": today, "expires_day": today + Contracts.OP_OFFER_DAYS, "state": "offered",
		"phases": phases, "h_hour": String(t.get("h_hour", "now")), "friendly_oob": (t.get("friendly_oob", []) as Array).duplicate(true),
		"enemy_oob": oob, "allied_fires": (t.get("allied_fires", {}) as Dictionary).duplicate(), "attached": (t.get("attached", []) as Array).duplicate(true),
	}
	return offer


## Operation zone `zone_id`'s def from the contract on the board or held that names it (cached), {}
## for none: MissionRegistry.zone_def's hook.
static func zone_def(zone_id: String) -> Dictionary:
	if _defs.has(zone_id):
		return _defs[zone_id]
	var s := Campaign.section(Contracts.SECTION)
	for c: Dictionary in (s.get("board", []) as Array) + (s.get("held", []) as Array):
		if String(c.get("op_zone", "")) == zone_id and is_operation(c):
			return def_for(c)
	return {}


## Contract `c`'s operation zone (cached by its zone id): OperationGen's, its controller the target.
static func def_for(c: Dictionary) -> Dictionary:
	var zid := String(c.get("op_zone", ""))
	if _defs.has(zid):
		return _defs[zid]
	var d := OperationGen.generate(int(c.get("op_seed", 1)), String(c.get("op_type", "phased_invasion")), c.get("covers", []))
	d["id"] = zid
	if String(c.get("zone_name", "")) != "":
		d["name"] = String(c.zone_name)
	if String(c.get("target", "")) != "":
		d["controller"] = String(c.target)  # call D1-8: the target as WorldSites has it, not the first zone's data
	if _defs.size() > 6:
		_defs.clear()
	_defs[zid] = d
	return d


## Tests: forget the cached defs (and the data).
static func forget() -> void:
	_defs.clear()
	_data = {}


# --- Phases and sites -----------------------------------------------------------------------------------

## The phases of an operation of `op_type` in zone `zdef`, resolved: [{"index", "name", "line_m",
## "limit_s", "pay_share", "objectives": [{"id", "label", "pos": [x, z], "module_id", "radius",
## "required", "town"}], "tasks": [{"kind", "text", "pos", "module_id", "radius", "optional",
## "bonus_share", "hold_s"}]}]. A type's "phases" hook replaces this.
static func build_phases(zdef: Dictionary, op_type: String) -> Array:
	var custom := hook(op_type, "phases")
	if custom.is_valid():
		return custom.call(zdef, op_type)
	var out: Array = []
	var size := float(zdef.get("size_m", 8192.0))
	var area := Rect2(-size * 0.5, -size * 0.5, size, size)
	var templates: Array = type_def(op_type).get("phases", [])
	for k in templates.size():
		var p: Dictionary = templates[k]
		var objectives: Array = []
		for sel: Dictionary in p.get("objectives", []):
			for s: Dictionary in resolve(zdef, sel):
				if objectives.any(func(o: Dictionary) -> bool: return String(o.id) == String(s.id)):
					continue
				objectives.append({"id": String(s.id), "label": String(sel.get("label", s.label)), "pos": s.pos, "module_id": String(s.module_id),
					"radius": float(sel.get("radius", knob("run", "seize_radius_m", 70.0))), "required": bool(sel.get("required", false)),
					"town": bool(sel.get("town", false)) or String(s.module_id).begins_with("city") or ZoneModules.base(String(s.get("type", ""))) == "town"})
		var tasks: Array = []
		for tt: Dictionary in p.get("company_task", []):
			var at := resolve(zdef, tt.get("at", {}))
			if at.is_empty():
				continue
			var s: Dictionary = at[0]
			var pos := Vector2(float(s.pos[0]), float(s.pos[1]))
			tasks.append({"kind": String(tt.get("kind", SEIZE_SITE)), "text": String(tt.get("text", "Seize {name} at {grid}")).replace("{grid}", MapGrid.grid_ref(pos, area, 3)).replace("{name}", String(s.label)),
				"pos": s.pos, "module_id": String(s.module_id), "radius": float(tt.get("radius", knob("run", "seize_radius_m", 70.0))),
				"optional": bool(tt.get("optional", false)), "bonus_share": float(tt.get("bonus_share", 0.0)), "hold_s": float(tt.get("hold_s", 0.0))})
		var line := OperationGen.band_range(zdef, String(p.get("line", "outposts")))
		out.append({"index": k, "name": String(p.get("name", "PL %d" % (k + 1))), "line_m": line.y if line.y > 0.0 else float(k + 1) * size / maxf(templates.size(), 1.0),
			"limit_s": float(p.get("limit_min", 25)) * 60.0, "pay_share": float(p.get("pay_share", 1.0 / maxf(templates.size(), 1.0))),
			"objectives": objectives, "tasks": tasks})
	return out


## The sites a selector names in `zdef` (see data/operations.json): [{"id", "label", "pos": [x, z],
## "module_id", "type"}].
static func resolve(zdef: Dictionary, sel: Dictionary) -> Array:
	var op: Dictionary = zdef.get("op", {})
	var modules: Array = zdef.get("modules", [])
	var by_id := func(id: String) -> Dictionary:
		for m: Dictionary in modules:
			if String(m.id) == id:
				return m
		return {}
	var as_site := func(m: Dictionary) -> Dictionary:
		return {"id": String(m.id), "label": "the %s" % MissionRegistry.module_name(String(m.type)), "pos": [float(m.pos[0]), float(m.pos[1])],
			"module_id": String(m.id), "type": String(m.type)}
	if sel.has("site"):
		var id := String(sel.site)
		match id:
			"@town":
				if String(op.get("town", "town")) == "city" and not (zdef.get("cities", []) as Array).is_empty():
					var city: Dictionary = zdef.cities[0]
					return [{"id": "city", "label": "the city centre", "pos": [float(city.pos[0]), float(city.pos[1])], "module_id": "", "type": "city"}]
				id = "town"
			"@hq":
				id = String(op.get("hq", "hq"))
			"@depth":
				id = String(op.get("depth", "hq"))
			"@fob":
				id = String(op.get("fob", "fob"))
		var m: Dictionary = by_id.call(id)
		if m.is_empty():
			return []
		var s: Dictionary = as_site.call(m)
		if id == "town":
			s.label = "the town"
		return [s]
	if sel.has("crossing"):
		var role := String(sel.crossing)
		for x: Dictionary in (zdef.get("river_hint", {}) as Dictionary).get("crossings", []):
			if String(x.get("role", "")) == role:
				return [{"id": "crossing_%s" % role, "label": "the %s bridge" % ("MSR" if role == "msr" else role), "pos": [float(x.pos[0]), float(x.pos[1])],
					"module_id": "", "type": "crossing"}]
		return []
	if sel.has("band"):
		var band := String(sel.band)
		var types: Array = sel.get("types", [])
		var found: Array = []
		for m: Dictionary in modules:
			var p := Vector2(float(m.pos[0]), float(m.pos[1]))
			if OperationGen.band_at(zdef, p) == band and (types.is_empty() or ZoneModules.base(String(m.type)) in types):
				found.append(m)
		var msr: Array = op.get("msr", [])
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _off_line(Vector2(a.pos[0], a.pos[1]), msr) < _off_line(Vector2(b.pos[0], b.pos[1]), msr))
		var out: Array = []
		for m: Dictionary in found.slice(0, int(sel.get("max", 99))):
			out.append(as_site.call(m))
		return out
	return []


## How far `p` is from polyline `line` ([[x, z], ...]).
static func _off_line(p: Vector2, line: Array) -> float:
	var best := INF
	for k in range(1, line.size()):
		var a := Vector2(float(line[k - 1][0]), float(line[k - 1][1]))
		var b := Vector2(float(line[k][0]), float(line[k][1]))
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
	return best if best < INF else p.length()


## Phase `k`'s company tasks as Objectives templates ("params" in level metres; "phase" k).
static func task_templates(phases: Array, k: int, _zdef := {}) -> Array:
	var out: Array = []
	if k < 0 or k >= phases.size():
		return out
	var p: Dictionary = phases[k]
	for t: Dictionary in p.get("tasks", []):
		out.append({"kind": String(t.kind), "text": "PH%d %s: %s" % [k + 1, String(p.name).trim_prefix("PL "), String(t.text)],
			"optional": bool(t.get("optional", false)), "bonus_share": 0.0,
			"params": {"pos": [float(t.pos[0]), 0.0, float(t.pos[1])], "radius": float(t.get("radius", 70.0)), "module_id": String(t.get("module_id", "")),
				"hold_s": float(t.get("hold_s", 0.0)), "phase": k, "op_bonus": float(t.get("bonus_share", 0.0))}})
	return out


## The enemy OOB of an operation of `op_type` in `zdef`: one entry per group with a place.
static func enemy_oob(zdef: Dictionary, op_type: String, roll: RandomNumberGenerator) -> Array:
	return _oob(zdef, type_def(op_type).get("enemy_oob", []), "hostile", roll)


static func friendly_oob(zdef: Dictionary, op_type: String, roll: RandomNumberGenerator) -> Array:
	return _oob(zdef, type_def(op_type).get("friendly_oob", []), "friendly", roll)


## OOB `spec` placed in `zdef`: [{"id", "side", "kind", "callsign", "men", "crew", "vehicles", "kit",
## "pos": [x, z], "reserve", "wave_s", "state": "pending"}]. Friendly groups line the start band
## across the axis (the FOB's side first); hostile ones go "at" their site, else spread over "bands".
static func _oob(zdef: Dictionary, spec: Array, side: String, roll: RandomNumberGenerator) -> Array:
	var out: Array = []
	var op: Dictionary = zdef.get("op", {})
	var a: Array = op.get("axis", [0, 1])
	var axis := Vector2(float(a[0]), float(a[1]))
	var left := Vector2(-axis.y, axis.x)
	var half := float(zdef.get("size_m", 8192.0)) * 0.5
	var start: Array = op.get("start", [0, 0])
	var start_p := Vector2(float(start[0]), float(start[1]))
	var slot := 0
	for e: Dictionary in spec:
		var groups: Variant = e.get("groups", 1)
		var n := roll.randi_range(int(groups[0]), int(groups[1])) if groups is Array else int(groups)
		for g in n:
			var pos := Vector2.ZERO
			if side == "friendly":
				var across := (slot % 2 * 2 - 1) * (220.0 + floori(slot / 2.0) * 260.0)
				pos = start_p + left * across - axis * 120.0
				slot += 1
			else:
				var at: Array = resolve(zdef, e.at) if e.has("at") else []
				if not at.is_empty():
					var s: Dictionary = at[g % at.size()]
					pos = Vector2(float(s.pos[0]), float(s.pos[1])) + Vector2.from_angle(roll.randf() * TAU) * roll.randf_range(60.0, 160.0)
				else:
					var bands: Array = e.get("bands", ["outposts"])
					var r := OperationGen.band_range(zdef, String(bands[g % bands.size()]))
					var lat := half - 600.0
					pos = axis * (roll.randf_range(r.x + 120.0, maxf(r.y - 120.0, r.x + 121.0)) - half) + left * roll.randf_range(-lat, lat)
			pos = pos.clamp(Vector2(-half + 200.0, -half + 200.0), Vector2(half - 200.0, half - 200.0))
			out.append({"id": "%s%d" % ["f" if side == "friendly" else "h", out.size() + 1], "side": side, "kind": String(e.get("kind", "rifle_squad")),
				"callsign": "%s %d" % [String(e.get("callsign", "Saber")), g + 1], "men": int(e.get("men", 4)), "crew": int(e.get("crew", 0)),
				"vehicles": (e.get("vehicles", []) as Array).duplicate(), "kit": String(e.get("kit", "")), "pos": [snappedf(pos.x, 1.0), snappedf(pos.y, 1.0)],
				"reserve": bool(e.get("reserve", false)), "wave_s": float(e.get("wave", 0.0)) * 60.0, "state": PENDING})
	return out


# --- Pay by phase (6.5) -------------------------------------------------------------------------------

## The deal for operation `c` on `terms`: ContractGen's, with the employer's advance ("advance_share",
## 20%) whatever the terms asked.
static func deal(c: Dictionary, terms: Dictionary) -> Dictionary:
	var d := ContractGen.deal(c, terms)
	var share := knob("", "advance_share", 0.2)
	d.advance = roundi(int(d.pay_total) * share)
	d.completion = int(d.pay_total) - int(d.advance)
	d.advance_share = share
	return d


## Why the company can't sign operation `c` ("" when it can): the employer at Trusted.
static func accept_problem(c: Dictionary) -> String:
	if not is_operation(c):
		return ""
	var need := int(knob("", "trusted_rep", 30.0))
	if Economy.reputation(String(c.get("employer", ""))) < need:
		return "%s give operations only to a company they trust (reputation %d)" % [MissionRegistry.faction_name(String(c.employer)), need]
	return ""


## Contract `c`'s run ("op_run"), made the first time: {"state", "phase", "clock_s", "hhour_s",
## "phases": [{"state", ...}], "paid", "front", "oob", "lost_vehicles", "allied_start", "taken" (sites the company or the allies took),
## "withdrawn", "reinforced", "infiltrated_s"}.
static func run_of(c: Dictionary) -> Dictionary:
	if not c.has("op_run") or not c.op_run is Dictionary or (c.op_run as Dictionary).is_empty():
		var phases: Array = []
		for p: Variant in c.get("phases", []):
			phases.append({"state": PENDING})
		c["op_run"] = {"state": WAITING, "phase": 0, "clock_s": 0.0, "hhour_s": -1.0, "phases": phases, "paid": 0, "front": "", "oob": [],
			"lost_vehicles": [], "allied_start": 0, "taken": [], "withdrawn": false, "reinforced": 0, "infiltrated_s": -INF, "started": false}
	return c.op_run


static func phases_done(c: Dictionary) -> int:
	if not is_operation(c):
		return 0
	var n := 0
	for p: Dictionary in run_of(c).get("phases", []):
		if String(p.get("state", "")) == DONE:
			n += 1
	return n


## What phase `k` of `c` pays with `facts` ({"elapsed_s", "limit_s", "allied_start", "allied_lost",
## "coop", "civilians", "ff", "optional": [{"text", "share"}]}): {"base", "lines": [{"text",
## "amount"}], "pay"}. Bonuses and penalties are shares of the phase's own pay.
static func phase_pay(c: Dictionary, k: int, facts: Dictionary) -> Dictionary:
	var d: Dictionary = c.get("deal", {})
	var completion := int(d.get("completion", 0)) + int(c.get("raise", 0))
	var phases: Array = c.get("phases", [])
	var ph: Dictionary = phases[k] if k < phases.size() else {}
	var base := roundi(completion * float(ph.get("pay_share", 0.0)))
	var p: Dictionary = data().get("pay", {})
	var shares: Array = []
	var elapsed := float(facts.get("elapsed_s", 0.0))
	var limit := float(facts.get("limit_s", ph.get("limit_s", 1500.0)))
	if elapsed <= limit * float(p.get("fast_share", 0.6)):
		shares.append(["fast (%s of %s)" % [clock_text(elapsed), clock_text(limit)], float(p.get("fast_bonus", 0.1))])
	var start := int(facts.get("allied_start", 0))
	if start > 0 and int(facts.get("allied_lost", 0)) <= start * float(p.get("low_losses_share", 0.15)):
		shares.append(["low allied losses (%d of %d)" % [int(facts.get("allied_lost", 0)), start], float(p.get("low_losses_bonus", 0.05))])
	var coop := int(facts.get("coop", 0))
	if coop > 0:
		shares.append(["cooperation (%d asks answered)" % coop, minf(coop * float(p.get("coop_bonus", 0.02)), float(p.get("coop_max", 0.1)))])
	if int(facts.get("civilians", 0)) == 0 and MissionRegistry.setting_f("clean_bonus_share") > 0.0:
		shares.append(["no civilian casualties", MissionRegistry.setting_f("clean_bonus_share")])
	for o: Dictionary in facts.get("optional", []):
		shares.append([String(o.text), float(o.share)])
	if elapsed > limit:
		shares.append(["done late (%s of %s)" % [clock_text(elapsed), clock_text(limit)], -float(p.get("late_penalty", 0.2))])
	var ff := int(facts.get("ff", 0))
	if ff > 0:
		shares.append(["friendly fire (%d)" % ff, -ff * float(p.get("ff_penalty", 0.05))])
	var lines: Array = []
	var pay := base
	for s: Array in shares:
		var amount := roundi(base * float(s[1]))
		if amount != 0:
			lines.append({"text": String(s[0]), "amount": amount})
			pay += amount
	if pay < 0:
		lines.append({"text": "nothing left to pay", "amount": -pay})
		pay = 0
	var out := {"base": base, "lines": lines, "pay": pay}
	var custom := hook(String(c.get("op_type", "")), "pay")
	if custom.is_valid():
		custom.call(c, k, facts, out)
	return out


## Host (the run, or the economy sim's dice): phase `k` of `c` is done: its pay into the bank (one
## ledger line), its record kept in the run (and returned). Once.
static func server_phase_done(c: Dictionary, k: int, facts: Dictionary) -> Dictionary:
	var run := run_of(c)
	var phases: Array = run.phases
	if k < 0 or k >= phases.size():
		return {}
	var rec: Dictionary = phases[k]
	if String(rec.get("state", "")) == DONE:
		return rec
	var pay := phase_pay(c, k, facts)
	rec.merge({"state": DONE, "base": int(pay.base), "lines": pay.lines, "pay": int(pay.pay), "elapsed_s": float(facts.get("elapsed_s", 0.0)),
		"limit_s": float(facts.get("limit_s", 0.0)), "late": float(facts.get("elapsed_s", 0.0)) > float(facts.get("limit_s", INF))}, true)
	run.paid = int(run.get("paid", 0)) + int(pay.pay)
	var name := String((c.phases[k] as Dictionary).get("name", "phase %d" % (k + 1)))
	Economy.add_cash(int(pay.pay), "Completion: %s, phase %d (%s)" % [String(c.get("title", "operation")), k + 1, name])
	var ff := int(facts.get("ff", 0))
	if ff > 0:
		Economy.change_reputation(String(c.get("employer", "")), ff * int(knob("pay", "ff_rep", -1.0)), "friendly fire on %s" % name)
	Campaign.mark_changed(Contracts.SECTION)
	return rec


## Host: phase `k` of `c` failed (stalled, or its task failed): the run stops there; what's done is paid.
static func server_phase_failed(c: Dictionary, k: int, why: String) -> void:
	var run := run_of(c)
	var phases: Array = run.phases
	if k >= 0 and k < phases.size() and String(phases[k].get("state", "")) != DONE:
		phases[k]["state"] = FAILED
		phases[k]["why"] = why
	run.state = STALLED
	Campaign.mark_changed(Contracts.SECTION)


## The debrief's line for operation `c` (DebriefCalc.compute's `line`), phase by phase: the
## completion is each phase's base pay, the bonuses its bonus and penalty lines, "paid_at_phases"
## what's already in the bank, "phases" each phase's record; a company vehicle lost is half
## reimbursed now. Reputation into `rep`. Returns the outcome: "completed" (every phase), "partial"
## (some), "failed" (none).
static func debrief_into(c: Dictionary, line: Dictionary, rep: Dictionary) -> String:
	var run := run_of(c)
	var phases: Array = c.get("phases", [])
	var recs: Array = run.get("phases", [])
	var done := phases_done(c)
	var outcome := "completed" if done >= phases.size() and done > 0 else ("partial" if done > 0 else "failed")
	var shown: Array = []
	for k in phases.size():
		var r: Dictionary = recs[k] if k < recs.size() else {}
		var name := "PH%d %s" % [k + 1, String((phases[k] as Dictionary).get("name", ""))]
		shown.append({"name": name, "state": String(r.get("state", PENDING)), "base": int(r.get("base", 0)), "pay": int(r.get("pay", 0)),
			"lines": (r.get("lines", []) as Array).duplicate(true), "elapsed_s": float(r.get("elapsed_s", 0.0)), "limit_s": float((phases[k] as Dictionary).get("limit_s", 0.0)),
			"why": String(r.get("why", ""))})
		if String(r.get("state", "")) != DONE:
			continue
		line.completion = int(line.completion) + int(r.get("base", 0))
		for l: Dictionary in r.get("lines", []):
			(line.bonuses as Array).append({"text": "%s: %s" % [name, String(l.text)], "amount": int(l.amount)})
	var share := knob("pay", "indemnity_share", 0.5)
	for v: Dictionary in run.get("lost_vehicles", []):
		(line.bonuses as Array).append({"text": "Equipment indemnity (%d%%): %s" % [roundi(share * 100.0), String(v.get("name", v.get("model", "vehicle")))],
			"amount": roundi(int(v.get("value", 0)) * share)})
	line["phases"] = shown
	line["paid_at_phases"] = int(run.get("paid", 0))
	line["phases_done"] = done
	if done > 0:
		line.salvage_share = float((c.get("deal", {}) as Dictionary).get("salvage_share", 0.0))
	var employer := String(c.get("employer", ""))
	match outcome:
		"completed":
			DebriefCalc._add(rep, employer, MissionRegistry.setting_i("rep_success"))
			DebriefCalc._add(rep, String(c.get("target", "")), MissionRegistry.setting_i("rep_target_on_success"))
		"partial":
			DebriefCalc._add(rep, employer, int(knob("pay", "rep_partial", 2.0)) if done * 2 >= phases.size() else 0)
		_:
			DebriefCalc._add(rep, employer, MissionRegistry.setting_i("rep_fail"))
	return outcome


## The debrief's phase lines in words (DebriefCalc.summary).
static func summary_lines(line: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in line.get("phases", []):
		match String(p.state):
			DONE:
				var extras := PackedStringArray()
				for l: Dictionary in p.get("lines", []):
					extras.append("%s %s$%s" % [String(l.text), "+" if int(l.amount) >= 0 else "-", DebriefCalc.money(absi(int(l.amount)))])
				out.append("    %s: done in %s, $%s%s" % [String(p.name), clock_text(float(p.elapsed_s)), DebriefCalc.money(p.pay),
					" (%s)" % ", ".join(extras) if not extras.is_empty() else ""])
			FAILED:
				out.append("    %s: stalled%s, not paid" % [String(p.name), (": " + String(p.why)) if String(p.get("why", "")) != "" else ""])
			_:
				out.append("    %s: not reached, not paid" % String(p.name))
	if int(line.get("paid_at_phases", 0)) > 0:
		out.append("    Paid as each phase was done: $%s" % DebriefCalc.money(line.paid_at_phases))
	return out


static func clock_text(seconds: float) -> String:
	var s := maxi(roundi(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


# --- The node ------------------------------------------------------------------------------------------

static func of(from: Node) -> Operations:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Operations if lvl else null


## Every peer, from ZoneLevel._ready: an operation zone gets the node.
static func install(level: Node, p_def: Dictionary) -> void:
	if not OperationGen.is_operation(p_def) or level.get_node_or_null(NODE_NAME) != null:
		return
	var n := Operations.new()
	n.name = NODE_NAME
	n.def = p_def
	level.add_child(n)


func _ready() -> void:
	_level = get_parent()
	grid = FrontGrid.for_zone(def, data().get("front", {}))
	_rng.seed = hash([String(def.get("id", "")), "operations"])
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		Contracts.deployment_started.connect(func(_d: Dictionary) -> void: _try_start.call_deferred())
		_try_start.call_deferred()
	else:
		_ask_host.call_deferred()


func _host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


## Host: the contract this zone is for (held: accepted or deployed), {} for none.
func contract() -> Dictionary:
	if cid != "":
		return Contracts.contract(cid)
	for c: Dictionary in Campaign.section(Contracts.SECTION).get("held", []):
		if is_operation(c) and String(c.get("op_zone", "")) == String(def.get("id", "")):
			return c
	return {}


## Whether the run is under way here (host: a deployed operation contract for this zone).
func active() -> bool:
	return cid != ""


## Host: once this zone's operation contract is deployed, its run starts (or picks up where a save left it).
func _try_start() -> void:
	if cid != "" or not is_inside_tree():
		return
	var c := contract()
	if c.is_empty():
		return
	if _level and _level.has_method(&"_set_enemy_faction"):
		_level.call(&"_set_enemy_faction", String(c.get("target", "")))  # its garrisons are the target's
	if String(c.get("state", "")) != Contracts.DEPLOYED:
		return
	cid = String(c.cid)
	var run := run_of(c)
	if String(run.front) != "":
		grid.from_save(String(run.front))
	if (run.oob as Array).is_empty():
		var roll := RandomNumberGenerator.new()
		roll.seed = hash([String(c.cid), "oob"])
		run.oob = friendly_oob(def, String(c.op_type), roll) + (c.get("enemy_oob", []) as Array).duplicate(true)
		for e: Dictionary in run.oob:
			if String(e.side) == "friendly":
				run.allied_start = int(run.allied_start) + int(e.men) + int(e.crew) * (e.vehicles as Array).size()
	else:
		for e: Dictionary in run.oob:
			if String(e.state) != "gone":
				e.state = PENDING  # (a loaded save: they come back by the same rules, where they were)
	_install_commanders(c)
	_place_objectives(c)
	if not bool(run.get("started", false)):
		run.started = true
		_plant_ieds(c)
		var start := hook(String(c.op_type), "start")
		if start.is_valid():
			start.call(self)
	_say("Citadel: %s is on. %s" % [String(c.get("zone_name", "The operation")), _phase_brief(c)])
	SessionLog.note("operation %s: %s in %s, phase %d of %d, %s" % [cid, String(c.op_type), String(def.id), int(run.phase) + 1, (c.phases as Array).size(), String(run.state)])
	_front_left = 0.0
	_broadcast_full()


## The commanders (B2's API): the friendly side's OperationPlan from the phases, the hostile side's
## DefencePlan over the enemy's sites. Hooked into the run: their phases, reserves and withdrawal.
func _install_commanders(c: Dictionary) -> void:
	if _level == null:
		return
	var phases: Array = c.phases
	var start := _v3(def.op.get("start", [0, 0]))
	var spec_phases: Array = []
	var from := start
	for k in phases.size():
		var p: Dictionary = phases[k]
		var objs: Array = []
		var main := ""
		for o: Dictionary in p.objectives:
			objs.append({"id": String(o.id), "label": String(o.label), "pos": _v3(o.pos), "radius": float(o.radius), "required": bool(o.required), "town": bool(o.town)})
			if main == "" and bool(o.required):
				main = String(o.id)
		if main == "" and not objs.is_empty():
			main = String(objs[0].id)
		var to: Vector3 = objs[0].pos if not objs.is_empty() else from
		for o: Dictionary in objs:
			if String(o.id) == main:
				to = o.pos
		spec_phases.append({"name": String(p.name), "limit_s": float(p.limit_s), "axis": [from, to], "main": main, "alt": "", "objectives": objs})
		from = to
	var fob := resolve(def, {"site": "@fob"})
	var rally := _v3(fob[0].pos) if not fob.is_empty() else start
	var hhour := -1.0 if String(c.get("h_hour", "now")) == "player" else 0.0
	plan = OperationPlan.new({"phases": spec_phases, "ld": start, "rally": rally, "hhour_s": hhour, "flanks": true})
	friendly = SideCommand.install(_level, &"friendly", plan)
	var sites: Array = []
	var band_line := {"outposts": 0, "crossing": 1, "town": 2, "depth": 3, "keep": 3}
	var hq := Vector3.ZERO
	for m: Dictionary in def.get("modules", []):
		if not ZoneModules.base(String(m.type)) in ENEMY_SITES and not String(m.id).begins_with("city"):
			continue
		var p2 := Vector2(float(m.pos[0]), float(m.pos[1]))
		sites.append({"id": String(m.id), "label": "the %s" % MissionRegistry.module_name(String(m.type)), "pos": _v3([p2.x, p2.y]), "radius": 60.0,
			"line": int(band_line.get(OperationGen.band_at(def, p2), 0))})
		if String(m.id) == String(def.op.get("hq", "hq")):
			hq = _v3([p2.x, p2.y])
	var axis := _axis()
	defence = DefencePlan.new({"sites": sites, "rally": hq + Vector3(axis.x, 0, axis.y) * 500.0, "mobile": []}, hash([cid, "defence"]))
	hostile = SideCommand.install(_level, &"hostile", defence)
	var alert := _level.get_node_or_null(^"Alert") as Alert
	if alert and not alert.report_received.is_connected(_on_alert_report):
		alert.report_received.connect(_on_alert_report)


## The hostile commander's picture: what its men report (Alert's contact reports, already delayed).
func _on_alert_report(r: Dictionary) -> void:
	if hostile == null or not is_instance_valid(hostile) or r.get("kind") != &"contact":
		return
	hostile.picture().submit({"kind": "inf", "count": int(r.get("seen", 1)), "pos": r.pos, "by": String(r.get("by", "")), "source": "alert",
		"unc0": SidePicture.base_uncertainty("seen")}, hostile.now())


## Host: the running phase's company objectives on the ground (a saved run's are restored with the
## deployment; the first phase's came with it).
func _place_objectives(c: Dictionary) -> void:
	var fix: Array = []
	for o: Dictionary in Contracts.objectives.for_contract(String(c.cid)):
		var p: Array = o.get("pos", [])
		if p.size() == 3 and is_zero_approx(float(p[1])):
			var n: Dictionary = o.duplicate(true)
			var g := _ground(Vector3(float(p[0]), 0.0, float(p[2])))
			n.pos = [g.x, g.y, g.z]
			(n.params as Dictionary)["pos"] = [g.x, g.y, g.z]
			fix.append(n)
	if not fix.is_empty():
		Contracts.objectives.server_replace(fix)


## Host, once a run: the enemy's roadside IEDs (RoadsideIeds), "ied_count" of them spread along the
## MSR in the outposts, crossing and town bands.
func _plant_ieds(c: Dictionary) -> void:
	var ieds := RoadsideIeds.of(self)
	var msr: Array = def.op.get("msr", [])
	if ieds == null or msr.size() < 3:
		return
	var n := int(knob("run", "ied_count", 4.0))
	var spots: Array = []
	for k in range(1, msr.size()):
		var p := Vector2(float(msr[k][0]), float(msr[k][1]))
		if OperationGen.band_at(def, p) in ["outposts", "crossing", "town"]:
			spots.append(p)
	var count := mini(n, spots.size())
	for k in count:
		var p: Vector2 = spots[(k * spots.size()) / maxi(count, 1)]  # (spread along the MSR)
		ieds.server_plant("%s:msr%d" % [String(c.cid), k], _ground(Vector3(p.x, 0, p.y)))


# --- The tick ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _host():
		return
	if cid == "":
		return
	_spawn_step()
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = knob("run", "tick_s", 1.0)
	server_tick(knob("run", "tick_s", 1.0))


## Tests: the run's clock `seconds` on, tick by tick (the front's cycles with it).
func server_advance(seconds: float) -> void:
	var step := knob("run", "tick_s", 1.0)
	var left := seconds
	while left > 0.0:
		server_tick(minf(step, left))
		left -= step


## Host: one tick of `dt` seconds.
func server_tick(dt: float) -> void:
	var c := contract()
	if c.is_empty() or String(c.get("state", "")) != Contracts.DEPLOYED:
		return
	var run := run_of(c)
	run.clock_s = float(run.clock_s) + dt
	match String(run.state):
		WAITING:
			if _h_hour(c, run):
				_begin_phase(c, 0)
		RUNNING:
			_check_tasks(c, run, dt)
			_check_phase(c, run)
			_reinforce(c, run)
	var custom := hook(String(c.op_type), "tick")
	if custom.is_valid():
		custom.call(self, dt)
	_front_left -= dt
	if _front_left <= 0.0:
		_front_left = knob("front", "cycle_s", 10.0)
		server_front_cycle()
	_sync_left -= dt
	if _sync_left <= 0.0:
		_sync_left = knob("run", "sync_s", 10.0)
		_broadcast_view()
	_save_left -= dt
	if _save_left <= 0.0:
		_save_left = knob("run", "save_s", 30.0)
		_store(c)


## Whether H-hour has come: "now" at once, "player" once a player is past the start band's far end
## by crossed_m (the line of departure), "dawn" by the type's hook (else at once).
func _h_hour(c: Dictionary, _run: Dictionary) -> bool:
	match String(c.get("h_hour", "now")):
		"player":
			var ld := OperationGen.band_range(def, "start").y + knob("run", "crossed_m", 60.0)
			for p: Node in _players():
				var s := p as Soldier
				if s and OperationGen.along(def, Vector2(s.global_position.x, s.global_position.z)) >= ld:
					if plan and friendly:
						plan.start_phase(friendly)
					return true
			return false
		"dawn":
			var custom := hook(String(c.op_type), "h_hour")
			return bool(custom.call(self)) if custom.is_valid() else true
	return true


func _begin_phase(c: Dictionary, k: int) -> void:
	var run := run_of(c)
	var phases: Array = c.phases
	run.phase = k
	run.state = RUNNING
	if float(run.hhour_s) < 0.0:
		run.hhour_s = float(run.clock_s)
	var rec: Dictionary = run.phases[k]
	rec.state = RUNNING
	rec["started_s"] = float(run.clock_s)
	rec["coop0"] = _coop()
	rec["civ0"] = int(Contracts.deployment().get("civilians", 0))
	rec["ff0"] = _ff()
	rec["allied0"] = _allied_now(run)
	if k > 0:
		var added := Objectives.from_contract({"cid": c.cid, "uid": c.get("uid", c.cid), "objectives": task_templates(phases, k), "zone_id": c.zone_id})
		for i in added.size():
			var o: Dictionary = added[i]
			o.oid = "%s_p%d_o%d" % [String(c.cid), k + 1, i + 1]
			var p: Array = o.pos
			var g := _ground(Vector3(float(p[0]), 0.0, float(p[2])))
			o.pos = [g.x, g.y, g.z]
			(o.params as Dictionary)["pos"] = o.pos
		Contracts.objectives.server_add(added)
	var begun := hook(String(c.op_type), "phase_begun")
	if begun.is_valid():
		begun.call(self, k)
	_say("Citadel: H-hour. %s" % _phase_brief(c) if k == 0 else "Citadel: %s" % _phase_brief(c))
	SessionLog.note("operation %s: phase %d (%s) begins at %s" % [cid, k + 1, String(phases[k].name), clock_text(float(run.clock_s))])
	phase_changed.emit(k)
	Contracts._commit()
	_broadcast_full()


func _phase_brief(c: Dictionary) -> String:
	var run := run_of(c)
	var k := int(run.phase)
	var phases: Array = c.phases
	if k >= phases.size():
		return ""
	var tasks := PackedStringArray()
	for t: Dictionary in (phases[k] as Dictionary).tasks:
		if not bool(t.optional):
			tasks.append(String(t.text))
	return "Phase %d, %s, %s: %s." % [k + 1, String(phases[k].name), clock_text(float(phases[k].limit_s)), "; ".join(tasks)]


## The running phase's company objectives: seize_site, keep_intact and hold_line (and a type's own).
func _check_tasks(c: Dictionary, run: Dictionary, dt: float) -> void:
	var k := int(run.phase)
	var hold_need := knob("run", "seize_hold_s", 60.0)
	for o: Dictionary in Contracts.objectives.for_contract(String(c.cid)):
		var params: Dictionary = o.get("params", {})
		if int(params.get("phase", -1)) != k or String(o.state) != Objectives.ACTIVE:
			continue
		var pos := _v3_3(params.get("pos", [0, 0, 0]))
		var radius := float(params.get("radius", 70.0))
		match String(o.kind):
			SEIZE_SITE:
				var enemies := _hostiles_near(pos, radius, String(params.get("module_id", "")))
				var ours := _company_near(pos, radius)
				if enemies == 0 and ours > 0:
					_seize[o.oid] = float(_seize.get(o.oid, 0.0)) + dt
					if float(_seize[o.oid]) >= hold_need:
						Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE)
						_take_site(run, String(params.get("module_id", "")))
						_objective_fell(Vector2(pos.x, pos.z), radius)
					else:
						Contracts.objectives.server_set_state(String(o.oid), Objectives.ACTIVE, "holding %d of %d s" % [roundi(float(_seize[o.oid])), roundi(hold_need)])
				else:
					_seize.erase(o.oid)
					var text := "%d hostile%s left" % [enemies, "" if enemies == 1 else "s"] if enemies > 0 and ours > 0 else ""
					Contracts.objectives.server_set_state(String(o.oid), Objectives.ACTIVE, text)
			KEEP_INTACT:
				var bi := _bridge_near(String(o.oid), pos)
				var bridges := _bridges()
				if bi >= 0 and bridges and (bridges.bridges[bi].spans as Array).any(func(s: Dictionary) -> bool: return bool(s.down)):
					Contracts.objectives.server_set_state(String(o.oid), Objectives.FAILED, "the bridge is down")
					_say("Citadel: the bridge at %s is down. Armour reroutes by the fords." % _grid_ref(pos))
			HOLD_LINE:
				var hold_s := float(params.get("hold_s", 600.0))
				if grid.owner_at(Vector2(pos.x, pos.z)) == FrontGrid.FRIENDLY and _hostiles_near(pos, radius, "") == 0:
					_hold[o.oid] = float(_hold.get(o.oid, 0.0)) + dt
				if float(_hold.get(o.oid, 0.0)) >= hold_s:
					Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE)
				else:
					Contracts.objectives.server_set_state(String(o.oid), Objectives.ACTIVE, "held %s of %s" % [clock_text(float(_hold.get(o.oid, 0.0))), clock_text(hold_s)])
			_:
				var custom := hook(String(c.op_type), "task")
				if custom.is_valid():
					var state := String(custom.call(self, o, dt))
					if state != "":
						Contracts.objectives.server_set_state(String(o.oid), state)


## The phase is done when every required company objective of it is and its required allied
## objectives are seized (the allies' plan took them, or their cells are ours); it stalls at
## phase_fail_share x its limit, or when a required objective failed.
func _check_phase(c: Dictionary, run: Dictionary) -> void:
	var k := int(run.phase)
	var phases: Array = c.phases
	if k >= phases.size():
		return
	var p: Dictionary = phases[k]
	var rec: Dictionary = run.phases[k]
	var elapsed := float(run.clock_s) - float(rec.get("started_s", run.clock_s))
	var mine: Array = Contracts.objectives.for_contract(String(c.cid)).filter(func(o: Dictionary) -> bool:
		return int((o.get("params", {}) as Dictionary).get("phase", -1)) == k)
	var required := mine.filter(func(o: Dictionary) -> bool: return not bool(o.optional))
	var failed := required.filter(func(o: Dictionary) -> bool: return String(o.state) == Objectives.FAILED)
	var tasks_done := not required.is_empty() and required.all(func(o: Dictionary) -> bool: return String(o.state) == Objectives.DONE)
	var allied_ok := true
	for o: Dictionary in p.objectives:
		if bool(o.required) and not seized(o):
			allied_ok = false
	if required.is_empty():
		tasks_done = allied_ok  # (a phase with no company task: the allies' alone)
	if tasks_done and allied_ok:
		_phase_done(c, k, elapsed)
	elif not failed.is_empty():
		_stall(c, k, "%s failed" % _task_of(String(failed[0].text)))
	elif elapsed >= float(p.limit_s) * SideCommand.num("phase_fail_share", 1.5):
		_stall(c, k, "not done in %s" % clock_text(elapsed))
	elif elapsed >= float(p.limit_s) and not bool(rec.get("late_said", false)):
		rec["late_said"] = true
		_say("Citadel: %s is past its time. Done late, it pays less; by %s it stalls." % [String(p.name), clock_text(float(p.limit_s) * SideCommand.num("phase_fail_share", 1.5))])


## Whether allied objective `o` is in our hands: the friendly plan took it, or its cell is ours.
func seized(o: Dictionary) -> bool:
	if plan and plan.taken.has(String(o.id)):
		return true
	return grid.owner_at(Vector2(float(o.pos[0]), float(o.pos[1]))) == FrontGrid.FRIENDLY


func _phase_done(c: Dictionary, k: int, elapsed: float) -> void:
	var run := run_of(c)
	var phases: Array = c.phases
	var p: Dictionary = phases[k]
	var rec: Dictionary = run.phases[k]
	var optional: Array = []
	for o: Dictionary in Contracts.objectives.for_contract(String(c.cid)):
		var params: Dictionary = o.get("params", {})
		if int(params.get("phase", -1)) != k or not bool(o.optional):
			continue
		if String(o.state) == Objectives.ACTIVE and String(o.kind) == KEEP_INTACT:
			Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE)  # standing when the phase is done
		if String(Contracts.objectives.get_objective(String(o.oid)).get("state", "")) == Objectives.DONE and float(params.get("op_bonus", 0.0)) > 0.0:
			optional.append({"text": _task_of(String(o.text)).trim_prefix("Bonus: "), "share": float(params.op_bonus)})
	var facts := {"elapsed_s": elapsed, "limit_s": float(p.limit_s), "allied_start": int(rec.get("allied0", run.allied_start)),
		"allied_lost": maxi(int(rec.get("allied0", 0)) - _allied_now(run), 0) + int(rec.get("overrun_lost", 0)), "coop": maxi(_coop() - int(rec.get("coop0", 0)), 0),
		"civilians": int(Contracts.deployment().get("civilians", 0)) - int(rec.get("civ0", 0)), "ff": maxi(_ff() - int(rec.get("ff0", 0)), 0), "optional": optional}
	var done := server_phase_done(c, k, facts)
	# The front: the phase's objectives are ours, and everything short of its line with no enemy in it.
	for o: Dictionary in p.objectives:
		_take_site(run, String(o.get("module_id", "")))
		_objective_fell(Vector2(float(o.pos[0]), float(o.pos[1])), float(o.radius))
		if plan:
			plan.taken[String(o.id)] = friendly.now() if friendly else 0.0  # (its next update moves its phase on)
	var moved := grid.consolidate(float(p.line_m), FrontGrid.FRIENDLY)
	if not moved.is_empty():
		_front_moved(moved)
	var extras := PackedStringArray()
	for l: Dictionary in done.get("lines", []):
		extras.append("%s %s%d%%" % [String(l.text).get_slice(" (", 0), "+" if int(l.amount) >= 0 else "-", roundi(absf(float(l.amount)) / maxf(float(done.base), 1.0) * 100.0)])
	_say("Citadel: %s done in %s. $%s to the company%s." % [String(p.name), clock_text(elapsed), DebriefCalc.money(done.get("pay", 0)),
		" (%s)" % ", ".join(extras) if not extras.is_empty() else ""])
	SessionLog.note("operation %s: phase %d (%s) done in %s, paid $%d" % [cid, k + 1, String(p.name), clock_text(elapsed), int(done.get("pay", 0))])
	var hooked := hook(String(c.op_type), "phase_done")
	if hooked.is_valid():
		hooked.call(self, k)
	if k + 1 < phases.size():
		_begin_phase(c, k + 1)
	else:
		run.state = DONE
		_say("Citadel: every phase is done. Good work. Extraction at the start line.")
		phase_changed.emit(k + 1)
		Contracts._commit()
		_store(c)
		_broadcast_full()


func _stall(c: Dictionary, k: int, why: String) -> void:
	var run := run_of(c)
	server_phase_failed(c, k, why)
	for o: Dictionary in Contracts.objectives.for_contract(String(c.cid)):
		if int((o.get("params", {}) as Dictionary).get("phase", -1)) == k and String(o.state) == Objectives.ACTIVE:
			Contracts.objectives.server_set_state(String(o.oid), Objectives.FAILED, "stalled")
	_say("Citadel: the operation has stalled at %s (%s). What's done is paid. Extract at the start line." % [String((c.phases[k] as Dictionary).name), why])
	SessionLog.note("operation %s: stalled at phase %d: %s" % [cid, k + 1, why])
	run.state = STALLED
	phase_changed.emit(k)
	Contracts._commit()
	_store(c)
	_broadcast_full()


## Host: tests and D4/D5's own mechanics: the operation stalls now.
func server_stall(why: String) -> void:
	var c := contract()
	if not c.is_empty() and String(run_of(c).state) == RUNNING:
		_stall(c, int(run_of(c).phase), why)


# --- The front -------------------------------------------------------------------------------------------

## Host: one cycle of the front (FrontGrid.cycle) from every side's presence, live, virtual and the
## OOB still to come, and the enemy's sites; sites the allies overrun off-screen; the side's
## withdrawal; company vehicles lost.
func server_front_cycle() -> void:
	var c := contract()
	if c.is_empty():
		return
	var started := Time.get_ticks_usec()
	var run := run_of(c)
	var presence := _presence(run)
	var t1 := Time.get_ticks_usec()
	var sites := _sites(run)
	var t2 := Time.get_ticks_usec()
	var flipped := grid.cycle(presence, sites, float(run.clock_s))
	var t3 := Time.get_ticks_usec()
	_overrun(run, sites)
	if friendly and friendly.withdrawn and not _withdraw_seen:
		_withdraw_seen = true
		run.withdrawn = true
		var back := 0.0
		var phases: Array = c.phases
		for k in int(run.phase):
			back = float(phases[k].line_m)
		if back <= 0.0:
			back = OperationGen.band_range(def, "start").y
		var given := grid.give_back(back)
		flipped.append_array(given)
		_say("Citadel: all elements, fall back to %s and dig in." % (String(phases[int(run.phase) - 1].name) if int(run.phase) > 0 else "the line of departure"))
	_lost_vehicles(run)
	cycle_us = float(Time.get_ticks_usec() - started)
	cycle_parts = {"presence": float(t1 - started), "sites": float(t2 - t1), "grid": float(t3 - t2), "rest": float(Time.get_ticks_usec() - t3)}
	if not flipped.is_empty():
		_front_moved(flipped)
	_update_front_marker()
	front_changed.emit(flipped)


## Every side's presence for the grid: soldiers up (live), each virtual profile's men, vehicles, and
## the OOB groups still to come where they wait.
func _presence(run: Dictionary) -> Array:
	var out: Array = []
	var man := knob("front", "man_cp", 1.0)
	var veh := knob("front", "vehicle_cp", 4.0)
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(&"combatants"):
			var s := n as Soldier
			if s == null or s.is_queued_for_deletion() or not s.vitals.is_up() or Person.is_person(s):
				continue
			var side := _side_of(s.faction)
			if side != FrontGrid.NONE:
				out.append({"pos": Vector2(s.global_position.x, s.global_position.z), "side": side, "cp": man})
		var v := Virtualizer.of(self)
		if v:
			for r: Dictionary in v.virtual_records():
				var p: Dictionary = r.virtual
				var side := _side_of(StringName(p.get("side", "hostile")))
				if side == FrontGrid.NONE and not (p.members as Array).is_empty():
					side = _side_of(StringName((p.members[0] as Dictionary).get("faction", "hostile")))
				out.append({"pos": Vector2((p.pos as Vector3).x, (p.pos as Vector3).z), "side": side, "cp": man * (p.members as Array).size()})
		for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
			var vh := n as Vehicle
			if vh and _level and _level.is_ancestor_of(vh) and not vh.wrecked and not vh.occupants().is_empty():
				out.append({"pos": Vector2(vh.global_position.x, vh.global_position.z), "side": _side_of(vh.faction), "cp": veh})
	for e: Dictionary in run.oob:
		if String(e.state) == PENDING:
			out.append({"pos": Vector2(float(e.pos[0]), float(e.pos[1])), "side": FrontGrid.FRIENDLY if String(e.side) == "friendly" else FrontGrid.HOSTILE,
				"cp": man * int(e.men) + veh * (e.vehicles as Array).size()})
	return out


static func _side_of(faction: StringName) -> int:
	if faction in [&"friendly", &"player", &"allied"]:
		return FrontGrid.FRIENDLY
	if faction == &"hostile":
		return FrontGrid.HOSTILE
	return FrontGrid.NONE


## The enemy's sites for the grid: standing while its garrison is (live or a profile), or, never
## visited, its expected garrison; the FOB stands for the friendly side.
func _sites(run: Dictionary) -> Array:
	var out: Array = []
	var cp := knob("front", "site_cp", 1.0)
	var lvl := _level as ZoneLevel
	for m: Dictionary in def.get("modules", []):
		var id := String(m.id)
		var base := ZoneModules.base(String(m.type))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		if base == "fob":
			out.append({"pos": p, "side": FrontGrid.FRIENDLY, "cp": 8.0, "standing": true, "id": id})
			continue
		if not base in ENEMY_SITES and not id.begins_with("city"):
			continue
		var men := 0
		var visited := false
		if lvl:
			visited = lvl._garrisoned.has(id)
			if id in (run.taken as Array):
				men = 0
			elif visited:
				men = lvl.garrison_alive(id) + lvl.garrison_pending(id)
			else:
				if not _expected.has(id):
					_expected[id] = lvl.garrison_size(id) if lvl.get_module(id) else 0
				men = int(_expected[id])
		else:
			men = 0 if id in (run.taken as Array) else (ZoneModules.GARRISON.get(base, []) as Array).size()
		out.append({"pos": p, "side": FrontGrid.HOSTILE, "cp": cp * men, "standing": men > 0, "id": id, "visited": visited})
	return out


## Sites nobody has been near whose cell the allies have taken over by overrun_ratio x their
## expected garrison for the flip time: taken off-screen (call D3-6). Their garrisons never come.
func _overrun(run: Dictionary, sites: Array) -> void:
	var lvl := _level as ZoneLevel
	if lvl == null:
		return
	var ratio := knob("run", "overrun_ratio", 2.0)
	for s: Dictionary in sites:
		if int(s.side) != FrontGrid.HOSTILE or not bool(s.standing) or bool(s.get("visited", true)):
			continue
		var i := grid.index_of(s.pos)
		var ours := grid.presence_near(i, FrontGrid.FRIENDLY)
		var theirs := grid.presence_near(i, FrontGrid.HOSTILE)
		var id := String(s.id)
		if ours > 0.0 and ours >= ratio * theirs and not _players_near(_v3([s.pos.x, s.pos.y]), knob("run", "spawn_far_m", 600.0)):
			if not _overrun_since.has(id):
				_overrun_since[id] = float(run.clock_s)
			elif float(run.clock_s) - float(_overrun_since[id]) >= grid.flip_s:
				(run.taken as Array).append(id)
				lvl._garrisoned[id] = maxi(int(lvl._garrisoned.get(id, 0)), lvl.garrison_size(id))  # it won't come out later
				var lost := ceili(float(s.cp) * knob("run", "overrun_loss_share", 0.34))
				var rec: Dictionary = run.phases[clampi(int(run.phase), 0, (run.phases as Array).size() - 1)]
				rec["overrun_lost"] = int(rec.get("overrun_lost", 0)) + lost
				_overrun_since.erase(id)
				SessionLog.note("operation %s: the allies took %s off-screen (%d expected, %d lost)" % [cid, id, int(s.cp), lost])
				_say("Citadel: %s reports %s taken." % [_nearest_allied_callsign(_v3([s.pos.x, s.pos.y])), _site_name(id)])
		else:
			_overrun_since.erase(id)


## Site `module_id` is ours (the company or the allies took it): its garrison no longer stands.
func _take_site(run: Dictionary, module_id: String) -> void:
	if module_id != "" and not module_id in (run.taken as Array):
		(run.taken as Array).append(module_id)


## Objective at `p` fell: its cells are ours at once (the front moves as objectives fall).
func _objective_fell(p: Vector2, radius: float) -> void:
	var moved := grid.set_cells(grid.cells_within(p, maxf(radius, 60.0)), FrontGrid.FRIENDLY)
	if not moved.is_empty():
		_front_moved(moved)


func _front_moved(cells: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var c := contract()
	if not c.is_empty():
		run_of(c).front = grid.to_save()
	if _online():
		_client_front.rpc(grid.delta(cells))
	_update_front_marker()


## The front line on the map: one line marker on the intel channel (MapMarkers replicates it).
func _update_front_marker() -> void:
	if _front_marker_rev == grid.rev:
		return
	_front_marker_rev = grid.rev
	var markers := MapNodes.markers(_level) if _level else null
	if markers == null:
		return
	if _front_marker != 0:
		markers.server_remove(_front_marker)
	_front_marker = markers.server_add({"kind": "line", "points": grid.front_line(), "text": "Front", "colour": "blue", "channel": "intel", "author": 0})


## Company vehicles (the motor pool's) wrecked here: half reimbursed at the debrief (6.5).
func _lost_vehicles(run: Dictionary) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or not v.wrecked or MotorPool.pool_id(v) == "":
			continue
		var id := MotorPool.pool_id(v)
		if (run.lost_vehicles as Array).any(func(e: Dictionary) -> bool: return String(e.id) == id):
			continue
		(run.lost_vehicles as Array).append({"id": id, "model": v.model, "name": v.display_name(), "value": Quartermaster.vehicle_price(v.model)})


# --- OOB spawning by the front -----------------------------------------------------------------------------

## Host, every frame: the OOB groups due come out (friendly ones at H-hour and their wave, at the
## start; enemy ones once a player is near but not too near and none can see where they'd stand),
## a few men a frame, while the live caps allow.
func _spawn_step() -> void:
	var c := contract()
	if c.is_empty():
		return
	var run := run_of(c)
	if _spawning.is_empty():
		for e: Dictionary in run.oob:
			if String(e.state) == PENDING and _due(e, run):
				_spawning.append(_spawn_job(e))
				e.state = "spawning"
				break
	if _spawning.is_empty():
		return
	if BigZoneStreaming.at_cap(_level, false):
		return
	var job: Dictionary = _spawning[0]
	var per := maxi(int(knob("run", "spawn_men_frame", 2.0)), 1)
	for k in per:
		if not _spawn_one(job):
			_spawning.pop_front()
			_finish_job(job)
			return


func _due(e: Dictionary, run: Dictionary) -> bool:
	var at := _v3(e.pos)
	if String(e.side) == "friendly":
		return String(run.state) != WAITING and float(run.clock_s) - float(run.hhour_s) >= float(e.get("wave_s", 0.0))
	var near := knob("run", "spawn_near_m", 2600.0)
	var far := knob("run", "spawn_far_m", 600.0)
	var closest := INF
	for p: Node in _players():
		closest = minf(closest, Vector2((p as Node3D).global_position.x - at.x, (p as Node3D).global_position.z - at.z).length())
	if closest > near or closest < far:
		return false
	var v := Virtualizer.of(self)
	var spots: Array[Vector3] = [_ground(at)]
	return v == null or not v.spots_seen(spots, _players())


## What spawning entry `e` takes: its vehicles first, then its crew and men.
func _spawn_job(e: Dictionary) -> Dictionary:
	var squad: Squad
	var hostile_side := String(e.side) != "friendly"
	var response := EnemyResponse.of(self)
	if hostile_side and response:
		squad = response._new_squad(_fresh_name(String(e.callsign)))
	else:
		squad = Squad.new()
		squad.name = _fresh_name(String(e.callsign))
		squad.faction = &"hostile" if hostile_side else &"friendly"
		add_child(squad)
	var men: Array = []
	for v in (e.vehicles as Array).size():
		for k in int(e.crew):
			men.append({"vehicle": v})
	for k in int(e.men):
		men.append({"vehicle": -1 if (e.vehicles as Array).is_empty() else k % (e.vehicles as Array).size()})
	return {"entry": e, "squad": squad, "vehicles_left": (e.vehicles as Array).duplicate(), "vehicles": [], "men": men, "made": [], "i": 0}


## One step of a spawn job: a vehicle, else a man. False once it's all out.
func _spawn_one(job: Dictionary) -> bool:
	var e: Dictionary = job.entry
	var at := _ground(_v3(e.pos))
	var axis := _axis()
	var fwd := Vector3(axis.x, 0, axis.y) * (1.0 if String(e.side) == "friendly" else -1.0)
	if not (job.vehicles_left as Array).is_empty():
		if BigZoneStreaming.at_cap(_level, true):
			(job.vehicles_left as Array).clear()  # no room for more vehicles: the rest walk
			return true
		var model := String((job.vehicles_left as Array).pop_front())
		var layer := _level.get_node_or_null(^"Vehicles") as VehicleLayer if _level else null
		var k := (job.vehicles as Array).size()
		var spot := _ground(at - fwd * 16.0 * k + Vector3(fwd.z, 0, -fwd.x) * 6.0)
		var stream := _level.get_node_or_null(NodePath(BigZoneStreaming.NODE_NAME)) as BigZoneStreaming if _level else null
		if stream:
			stream.ensure(spot)
		var v: Vehicle = null
		if layer:
			v = layer.server_spawn(model, Transform3D(Basis.looking_at(fwd, Vector3.UP), spot + Vector3.UP * 0.4), "",
				&"friendly" if String(e.side) == "friendly" else &"hostile", "")
		if v:
			v.set_meta(&"no_save", true)
			v.set_meta(&"op_group", String(e.id))
			AavGunner.attach(v)
		(job.vehicles as Array).append(v)
		return true
	var i := int(job.i)
	if i >= (job.men as Array).size():
		return false
	job.i = i + 1
	var spec: Dictionary = job.men[i]
	var s := _spawn_man(e, job.squad, i, at + Vector3(fwd.z, 0, -fwd.x) * 1.6 * (i - (job.men as Array).size() / 2.0))
	if s == null:
		return true
	s.set_meta(&"op_group", String(e.id))
	if String(e.side) == "friendly":
		s.set_meta(&"op_allied", true)
	var vi := int(spec.vehicle)
	if vi >= 0 and vi < (job.vehicles as Array).size() and is_instance_valid(job.vehicles[vi]):
		var v := job.vehicles[vi] as Vehicle
		var seats := VehicleQrf._seat_order(v)
		for seat: int in seats:
			if v.occupant(seat) == null and v.server_enter(s, seat):
				break
	(job.made as Array).append(s)
	return true


func _spawn_man(e: Dictionary, squad: Squad, i: int, at: Vector3) -> Soldier:
	var pos := _ground(at)
	var name := "%s_%d" % [String(squad.name), i + 1]
	if String(e.side) == "friendly":
		var kit := String(e.kit) if String(e.kit) != "" else Kits.kit_of(String(contract().get("employer", "us_forces")))
		var k := Kits.data(kit)
		var s: Soldier = _level.call(&"spawn_soldier", {"name": name, "faction": "friendly", "iff": "allied", "variant": Kits.variant(kit, i),
			"pos": pos, "loadout": Kits.loadout(kit, i, 1), "role": Kits.role(kit, i), "combat": float(k.get("combat", 0.6)),
			"discipline": float(k.get("discipline", 0.7)), "guard": false, "mode": "aware", "faction_id": String(contract().get("employer", ""))})
		if s:
			var brain := SquadAI.of(s)
			if brain:
				brain.squad = squad
		return s
	var response := EnemyResponse.of(self)
	if response == null:
		return null
	var loadout: Array = CompoundLevel.HOSTILE_LOADOUT.duplicate()
	if String(e.kit) == "at" and i % 3 != 2:
		loadout.append_array(LauncherAI.INSURGENT_KIT)
	var made := response._spawn_team(squad, name, 1, pos, pos + Vector3(0, 0, 1), loadout, 0.5, 0.55, "aware")
	return made[0] as Soldier if not made.is_empty() else null


## A spawn job done: the group goes to its side's commander (and the Virtualizer through it).
func _finish_job(job: Dictionary) -> void:
	var e: Dictionary = job.entry
	var squad := job.squad as Squad
	var men: Array = (job.made as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s))
	if men.is_empty():
		e.state = "gone"
		squad.queue_free()
		return
	squad.leader = men[0]
	var record := {"squad": squad, "soldiers": men, "vehicles": job.vehicles, "v_nosave": true, "op_entry": String(e.id)}
	records[String(e.id)] = record
	e.state = "live"
	var cmd := friendly if String(e.side) == "friendly" else hostile
	if cmd and is_instance_valid(cmd):
		var foot := (job.vehicles as Array).is_empty()
		cmd.server_register(squad, String(e.kind), String(e.callsign), record if foot else {})
	SessionLog.note("operation %s: %s %s out at %s (%d men, %d vehicles)" % [cid, String(e.side), String(e.callsign), _grid_ref(_v3(e.pos)), men.size(), (job.vehicles as Array).size()])


## Host: the enemy's reinforcements by the front: every reinforce_s while a phase runs (at most
## reinforce_max a phase), a group on its own side of the front near the phase's main objective, at
## least spawn_far_m from every player and out of sight; now and then an infiltrator team behind it.
func _reinforce(c: Dictionary, run: Dictionary) -> void:
	var k := int(run.phase)
	var rec: Dictionary = run.phases[k]
	var since := float(run.clock_s) - float(rec.get("started_s", 0.0))
	var every := knob("run", "reinforce_s", 420.0)
	var sent := int(rec.get("reinforced", 0))
	if since >= every * (sent + 1) and sent < int(knob("run", "reinforce_max", 3.0)):
		rec["reinforced"] = sent + 1
		var main := _main_pos(c, k)
		var spot := _front_spot(main, FrontGrid.HOSTILE, 1500.0)
		if spot.is_finite():
			_add_group(run, "hostile", "rifle_squad", "Wave %d" % (int(run.reinforced) + 1), int(knob("run", "reinforce_men", 6.0)), spot)
			run.reinforced = int(run.reinforced) + 1
	var gap := knob("run", "infiltrator_s", 900.0)
	if float(run.clock_s) - float(run.get("infiltrated_s", -INF)) >= gap:
		run.infiltrated_s = float(run.clock_s)
		if _rng.randf() < knob("run", "infiltrator_chance", 0.5):
			var spot := _front_spot(_main_pos(c, k), FrontGrid.FRIENDLY, 2500.0, true)
			if spot.is_finite():
				_add_group(run, "hostile", "recon_team", "Ghost %d" % (int(run.reinforced) + 1), int(knob("run", "infiltrator_men", 4.0)), spot)
				_say("Citadel: reports of an enemy team behind the front near %s." % _grid_ref(_v3([spot.x, spot.y])))


## Host: a new OOB group waiting at `p` (it comes out by the same rules as the rest).
func _add_group(run: Dictionary, side: String, kind: String, callsign: String, men: int, p: Vector2) -> void:
	(run.oob as Array).append({"id": "%s%d" % ["f" if side == "friendly" else "h", (run.oob as Array).size() + 1], "side": side, "kind": kind,
		"callsign": callsign, "men": men, "crew": 0, "vehicles": [], "kit": "rifles", "pos": [snappedf(p.x, 1.0), snappedf(p.y, 1.0)],
		"reserve": false, "wave_s": 0.0, "state": PENDING})


## A spot (x, z) in a cell `side` owns within `reach` of `near`, at least spawn_far_m from every
## player and (if `behind`) with nobody of ours in its cell; INF when there's none.
func _front_spot(near: Vector3, side: int, reach: float, behind := false) -> Vector2:
	var far := knob("run", "spawn_far_m", 600.0)
	var best := Vector2.INF
	var best_d := INF
	for i in grid.cells * grid.cells:
		if grid.owner[i] != side:
			continue
		var p := grid.centre(i)
		var d := p.distance_to(Vector2(near.x, near.z))
		if d > reach or _players_near(_v3([p.x, p.y]), far):
			continue
		if behind and grid.raw_at(i, FrontGrid.FRIENDLY) > 0.0:
			continue
		var score := d + _rng.randf() * 200.0
		if score < best_d:
			best_d = score
			best = p
	if best != Vector2.INF:  # (somewhere in the cell, so waves don't stack on its centre)
		var j := grid.cell_m * 0.35
		best += Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))
	return best


## A task's text without its "PHk NAME: " head.
static func _task_of(text: String) -> String:
	var at := text.find(": ")
	return text.substr(at + 2) if at >= 0 else text


# --- Reading (host) ------------------------------------------------------------------------------------

func _players() -> Array:
	var out: Array = []
	var holder: Node = _level.get(&"players") if _level else null
	if holder:
		for p in holder.get_children():
			if p is Soldier and not (p as Soldier).is_queued_for_deletion() and (p as Soldier).vitals.is_up():
				out.append(p)
	return out


func _players_near(at: Vector3, radius: float) -> bool:
	for p: Node in _players():
		if Vector2((p as Node3D).global_position.x - at.x, (p as Node3D).global_position.z - at.z).length() < radius:
			return true
	return false


## Hostiles standing within `radius` of `pos` (live, a profile's, or a garrison not out yet).
func _hostiles_near(pos: Vector3, radius: float, module_id: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= radius:
			n += 1
	var v := Virtualizer.of(self)
	if v:
		n += v.count_in(Rect2(pos.x - radius, pos.z - radius, radius * 2.0, radius * 2.0), &"hostile")
	var lvl := _level as ZoneLevel
	if lvl and module_id != "" and lvl.get_module(module_id) and not lvl.garrison_spawned(module_id):
		var c := contract()
		if c.is_empty() or not module_id in (run_of(c).taken as Array):
			n += maxi(lvl.garrison_size(module_id) - int(lvl._garrisoned.get(module_id, 0)), 0)
	return n


## The company within `radius` of `pos`: players and the company's own AI (not the allies').
func _company_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or s.is_queued_for_deletion() or not s.vitals.is_up() or not (s.faction in [&"friendly", &"player"]):
			continue
		if s.has_meta(&"op_allied") or s.has_meta(&"allied_element") or s.has_meta(&"vehicle_crew") or Person.is_person(s):
			continue
		if Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= radius:
			n += 1
	return n


## The allies' men standing now: every friendly OOB group's (live or a profile) and those still to come.
func _allied_now(run: Dictionary) -> int:
	var n := 0
	for e: Dictionary in run.oob:
		if String(e.side) != "friendly":
			continue
		match String(e.state):
			PENDING, "spawning":
				n += int(e.men) + int(e.crew) * (e.vehicles as Array).size()
			"live":
				var r: Dictionary = records.get(String(e.id), {})
				n += Virtualizer.up(r) if not r.is_empty() else 0
	return n


func _coop() -> int:
	var broker := RequestBroker.of(self)
	var n := 0
	if broker:
		for v: Variant in broker.cooperation.values():
			n += int(v)
	return n


## Friendly-fire incidents by players so far (Deconfliction's list; call D3-8).
static func _ff() -> int:
	return Deconfliction.incidents.filter(func(r: Dictionary) -> bool: return bool(r.get("player", false))).size()


func _main_pos(c: Dictionary, k: int) -> Vector3:
	var phases: Array = c.phases
	if k >= phases.size():
		return Vector3.ZERO
	var objs: Array = (phases[k] as Dictionary).objectives
	for o: Dictionary in objs:
		if bool(o.required):
			return _v3(o.pos)
	return _v3(objs[0].pos) if not objs.is_empty() else _v3(def.op.get("start", [0, 0]))


func _bridges() -> ZoneBridges:
	var lvl := _level as ZoneLevel
	return lvl.terrain.water.bridges if lvl and lvl.terrain and lvl.terrain.water else null


func _bridge_near(oid: String, pos: Vector3) -> int:
	if _bridge_of.has(oid):
		return int(_bridge_of[oid])
	var bridges := _bridges()
	var best := -1
	var best_d := 80.0
	if bridges:
		for bi in bridges.bridges.size():
			var o: Vector3 = (bridges.bridges[bi].xform as Transform3D).origin
			var d := Vector2(o.x - pos.x, o.z - pos.z).length()
			if d < best_d:
				best_d = d
				best = bi
	_bridge_of[oid] = best
	return best


func _nearest_allied_callsign(at: Vector3) -> String:
	var best := "Saber"
	var best_d := INF
	var c := contract()
	for e: Dictionary in run_of(c).oob if not c.is_empty() else []:
		if String(e.side) != "friendly" or String(e.state) == "gone":
			continue
		var r: Dictionary = records.get(String(e.id), {})
		var p := Virtualizer.lead(r) if not r.is_empty() else _v3(e.pos)
		if p.is_finite() and p.distance_to(at) < best_d:
			best_d = p.distance_to(at)
			best = String(e.callsign)
	return best


func _site_name(module_id: String) -> String:
	for m: Dictionary in def.get("modules", []):
		if String(m.id) == module_id:
			return "the %s at %s" % [MissionRegistry.module_name(String(m.type)), _grid_ref(_v3(m.pos))]
	return module_id


func _grid_ref(p: Vector3) -> String:
	var size := float(def.get("size_m", 8192.0))
	return MapGrid.grid_ref(Vector2(p.x, p.z), Rect2(-size * 0.5, -size * 0.5, size, size), 3)


func _axis() -> Vector2:
	var a: Array = (def.get("op", {}) as Dictionary).get("axis", [0, 1])
	return Vector2(float(a[0]), float(a[1]))


func _ground(p: Vector3) -> Vector3:
	return _level.call(&"ground_point", p) if _level and _level.has_method(&"ground_point") else p


func _v3(p: Variant) -> Vector3:
	var a: Array = p if p is Array else [0, 0]
	return _ground(Vector3(float(a[0]), 0.0, float(a[1]))) if a.size() >= 2 else Vector3.ZERO


static func _v3_3(p: Variant) -> Vector3:
	var a: Array = p if p is Array else [0, 0, 0]
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO


func _fresh_name(want: String) -> String:
	_serial += 1
	return ("Op%s_%d" % [want.replace(" ", ""), _serial]).validate_node_name()


func _say(text: String) -> void:
	said.append(text)
	Contracts._notify_all(text)


## Host: keeps the run's front and the OOB where it stands in the contract (the campaign saves it).
func _store(c: Dictionary) -> void:
	var run := run_of(c)
	run.front = grid.to_save()
	for e: Dictionary in run.oob:
		var r: Dictionary = records.get(String(e.id), {})
		if String(e.state) != "live" or r.is_empty():
			continue
		var up := Virtualizer.up(r)
		var vehicles := (r.get("vehicles", []) as Array).filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Vehicle).wrecked).size()
		if up <= 0 and vehicles == 0:
			e.state = "gone"
			continue
		var at := Virtualizer.lead(r)
		if at.is_finite():
			e.pos = [snappedf(at.x, 1.0), snappedf(at.z, 1.0)]
		var per := int(e.crew)
		e.men = maxi(up - per * vehicles, 0)
		e.vehicles = (e.vehicles as Array).slice(0, vehicles)
	Campaign.mark_changed(Contracts.SECTION)


## Host: what the save holds of the run now (BaseHub's save: the front and the OOB where they are).
func server_save_state() -> void:
	var c := contract()
	if not c.is_empty():
		_store(c)


# --- What every peer sees -------------------------------------------------------------------------------

## The strip's view of contract `c`'s run (host).
func _make_view(c: Dictionary) -> Dictionary:
	var run := run_of(c)
	var phases: Array = c.phases
	var list: Array = []
	for k in phases.size():
		var r: Dictionary = run.phases[k]
		list.append({"name": String(phases[k].name), "state": String(r.get("state", PENDING)), "limit_s": float(phases[k].limit_s),
			"started_s": float(r.get("started_s", -1.0)), "done_s": float(r.get("elapsed_s", 0.0)), "line_m": float(phases[k].line_m)})
	var tasks: Array = []
	for o: Dictionary in Contracts.objectives.for_contract(String(c.cid)):
		if int((o.get("params", {}) as Dictionary).get("phase", -1)) == int(run.phase) and String(o.state) == Objectives.ACTIVE:
			tasks.append(_task_of(String(o.text)) + ((" (%s)" % String(o.progress)) if String(o.get("progress", "")) != "" else ""))
	var allied := PackedStringArray()
	if friendly and is_instance_valid(friendly):
		for g: Dictionary in friendly.groups.values():
			if String(g.role) != "" and allied.size() < 3:
				allied.append("%s %s" % [String(g.callsign), String(g.role).to_upper() if String(g.role) == "sbf" else String(g.role)])
	return {"name": String(c.get("zone_name", "Operation")), "codename": String(c.get("codename", "")), "type": String(c.get("op_type", "")),
		"state": String(run.state), "phase": int(run.phase), "clock_s": float(run.clock_s), "phases": list, "task": tasks,
		"front_m": grid.front_m(), "share": grid.share(FrontGrid.FRIENDLY), "allied": ", ".join(allied)}


func _broadcast_view() -> void:
	var c := contract()
	if c.is_empty():
		return
	view = _make_view(c)
	_clock_at = Time.get_ticks_msec() / 1000.0
	if _online():
		_client_view.rpc(view)


func _broadcast_full() -> void:
	var c := contract()
	if c.is_empty():
		return
	view = _make_view(c)
	_clock_at = Time.get_ticks_msec() / 1000.0
	if _online():
		_client_full.rpc(view, grid.to_bytes())


## The run's clock now on this peer (extrapolated between the host's updates while a phase runs).
func clock_now() -> float:
	if view.is_empty():
		return 0.0
	var extra := 0.0 if _host() or String(view.get("state", "")) != RUNNING else Time.get_ticks_msec() / 1000.0 - _clock_at
	return float(view.get("clock_s", 0.0)) + extra


## Client: the run as it stands, from the host (a late joiner too).
func _ask_host() -> void:
	if is_inside_tree() and _online():
		_ask_all.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	var c := contract()
	if c.is_empty() or cid == "":
		return
	_client_full.rpc_id(multiplayer.get_remote_sender_id(), _make_view(c), grid.to_bytes())


@rpc("authority", "call_remote", "reliable")
func _client_full(p_view: Dictionary, front: PackedByteArray) -> void:
	view = p_view
	_clock_at = Time.get_ticks_msec() / 1000.0
	grid.from_bytes(front)
	front_changed.emit(PackedInt32Array())


@rpc("authority", "call_remote", "reliable")
func _client_view(p_view: Dictionary) -> void:
	view = p_view
	_clock_at = Time.get_ticks_msec() / 1000.0


@rpc("authority", "call_remote", "reliable")
func _client_front(pairs: PackedInt32Array) -> void:
	grid.apply_delta(pairs)
	front_changed.emit(PackedInt32Array())


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
