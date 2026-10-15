class_name ScenarioGen
extends RefCounted
## The objectives of the scenario mission types (mission variety, 2026-10-15): convoy ambush,
## defend/hold, downed crew rescue and recon. Pure (no campaign state), called by
## ContractGen.mission_target for a type whose definition has a "scenario" key. Each builds
## its objectives with their positions already in the zone's metres ("params", which
## Objectives.from_contract takes as they are), from a generator seeded by the contract, so a
## board is the same every time. MissionScenario (the host's node in the level) plays them.
##
## Knobs live in data/contracts.json under the type's "scenario_knobs" (Proposed numbers).

const CONVOY := "convoy"
const DEFEND := "defend"
const RESCUE := "rescue"
const RECON := "recon"
## How far inside the zone's edge a route or an approach may reach (m).
const EDGE_KEEP_M := 140.0


## {"module", "module_id", "objectives", "title_extra"} for a contract of type `def` in zone
## `zone_id` (see ContractGen.mission_target). `module` is a module the scenario is built
## around (the convoy's landmark, the held point, the first recon site); "module_id" is set
## only where the zone's garrison logic should know the module (the defended one).
static func build(pick: RandomNumberGenerator, def: Dictionary, zone_id: String, target: String) -> Dictionary:
	var layout := MissionRegistry.zone_def(zone_id)
	var allowed := MissionRegistry.type_modules(def)
	var options: Array = (layout.get("modules", []) as Array).filter(
		func(m: Dictionary) -> bool: return ZoneModules.base(String(m.type)) in allowed)
	var half := float(layout.get("size_m", 1536.0)) * 0.5
	var knobs: Dictionary = def.get("scenario_knobs", {})
	var module: Dictionary = options[pick.randi() % options.size()] if not options.is_empty() else {"id": "", "type": String(allowed[0]) if not allowed.is_empty() else "", "pos": [0.0, 0.0]}
	var kind := String(def.get("scenario", ""))
	var out := {"module": String(module.type), "module_id": "", "objectives": [], "title_extra": ""}
	match kind:
		CONVOY:
			out.objectives = _convoy(pick, def, module, half, knobs)
		DEFEND:
			out.module_id = String(module.id)
			out.objectives = _defend(pick, def, module, half, knobs)
		RESCUE:
			out.objectives = _rescue(pick, def, module, half, knobs, target)
		RECON:
			var made := _recon(pick, def, options, half, knobs)
			out.objectives = made.objectives
			out.module = String(made.module)
	if kind == RECON:
		out.title_extra = " (%d sites)" % (out.objectives as Array).filter(func(o: Dictionary) -> bool: return o.kind == Objectives.RECON_SITE).size()
	elif not options.is_empty():
		out.title_extra = " (%s)" % MissionRegistry.module_name(String(module.type))
	return out


## A point `reach` metres from `from` along `dir` (x, z), kept inside the zone.
static func _inside(from: Vector2, dir: Vector2, reach: float, half: float) -> Vector2:
	var keep := half - EDGE_KEEP_M
	var t := reach
	if absf(dir.x) > 0.001:
		t = minf(t, ((keep if dir.x > 0.0 else -keep) - from.x) / dir.x)
	if absf(dir.y) > 0.001:
		t = minf(t, ((keep if dir.y > 0.0 else -keep) - from.y) / dir.y)
	return from + dir * maxf(t, 0.0)


static func _v3(p: Vector2) -> Array:
	return [snappedf(p.x, 0.1), 0.0, snappedf(p.y, 0.1)]


static func _minutes(seconds: float) -> String:
	return "%d min" % roundi(seconds / 60.0)


# --- Convoy ambush ---------------------------------------------------------------------------

## An enemy convoy drives a route across the zone past the ambush point (beside the landmark
## module); it sets out "depart_s" after the deployment starts. Stop it (every cargo truck
## halted: destroyed, or its driver killed or the truck disabled) before it leaves the far end,
## then seize the cargo (the bonus: carry the crate out).
static func _convoy(pick: RandomNumberGenerator, def: Dictionary, module: Dictionary, half: float, knobs: Dictionary) -> Array:
	var centre := Vector2(float((module.pos as Array)[0]), float((module.pos as Array)[1]))
	var heading := pick.randf() * TAU
	var dir := Vector2(cos(heading), sin(heading))
	var side := dir.orthogonal()
	var ambush := centre + side * float(knobs.get("road_offset_m", 80.0)) * (1.0 if pick.randf() < 0.5 else -1.0)
	var keep := half - EDGE_KEEP_M
	ambush = Vector2(clampf(ambush.x, -keep, keep), clampf(ambush.y, -keep, keep))
	var start := _inside(ambush, -dir, 1400.0, half)
	var finish := _inside(ambush, dir, 1400.0, half)
	var points: Array = [_v3(start)]
	var length := start.distance_to(finish)
	var step := float(knobs.get("waypoint_m", 160.0))
	var n := maxi(floori(length / step), 2)
	for i in range(1, n):
		var p := start.lerp(finish, float(i) / n)
		p += side * sin(float(i) * 0.9) * 14.0  # the road bends a little
		points.append(_v3(p))
	points.append(_v3(finish))
	var trucks := pick.randi_range(int(knobs.get("trucks", [1, 2])[0]), int(knobs.get("trucks", [1, 2])[1]))
	var escorts := pick.randi_range(int(knobs.get("escorts", [1, 2])[0]), int(knobs.get("escorts", [1, 2])[1]))
	var depart: Array = knobs.get("depart_s", [420, 600])
	var depart_s := snappedf(pick.randf_range(float(depart[0]), float(depart[1])), 15.0)
	var cargo_id := "convoy_cargo_%d" % pick.randi()
	var params := {"scenario": CONVOY, "route": points, "trucks": trucks, "escorts": escorts, "depart_s": depart_s,
		"speed_kmh": float(knobs.get("speed_kmh", 28.0)), "pos": _v3(ambush), "radius": 60.0, "cargo": "hvt_case", "cargo_ids": [cargo_id]}
	var main := {"kind": Objectives.CONVOY, "site": "", "params": params,
		"text": "Stop the convoy before it leaves the zone (about %s after insertion): destroy its cargo %s or disable and seize it" % [_minutes(depart_s), "truck" if trucks == 1 else "trucks"]}
	var bonus := {"kind": Objectives.EXTRACT_ITEM, "site": "", "optional": true, "bonus_share": float(knobs.get("cargo_bonus_share", 0.2)),
		"params": {"items": ["hvt_case"], "intel_ids": [cargo_id], "pos": _v3(ambush), "name": "cargo crate"},
		"text": "Bonus: carry the convoy's cargo out"}
	return [main, bonus]


# --- Defend / hold ---------------------------------------------------------------------------

## Hold the module's position for "hold_s" (the clock runs while someone of ours stands in it)
## against waves from several directions; the position is lost when nobody of ours holds it and
## the enemy stands in it. The module has no garrison of its own (the type's "no_garrison").
static func _defend(pick: RandomNumberGenerator, def: Dictionary, module: Dictionary, half: float, knobs: Dictionary) -> Array:
	var centre := Vector2(float((module.pos as Array)[0]), float((module.pos as Array)[1]))
	var hold: Array = knobs.get("hold_s", [420, 600])
	var hold_s := snappedf(pick.randf_range(float(hold[0]), float(hold[1])), 30.0)
	var dirs := pick.randi_range(int(knobs.get("dirs", [3, 4])[0]), int(knobs.get("dirs", [3, 4])[1]))
	var name := MissionRegistry.module_name(String(module.type))
	var params := {"scenario": DEFEND, "pos": _v3(centre), "radius": float(knobs.get("radius_m", 32.0)), "hold_s": hold_s,
		"first_wave_s": float(knobs.get("first_wave_s", 60.0)), "gap_s": float(knobs.get("gap_s", 80.0)), "dirs": dirs,
		"bearing": snappedf(pick.randf() * TAU, 0.01), "approach_m": float(knobs.get("approach_m", 230.0)), "name": name}
	return [{"kind": Objectives.HOLD_POINT, "site": "", "params": params,
		"text": "Hold the %s for %s against attacks from all sides" % [name, _minutes(hold_s)]}]


# --- Downed crew rescue ----------------------------------------------------------------------

## A shot-down helicopter's wreck with 2-4 crew, some wounded (a broken leg: carried; an arm:
## walks), in open ground a little way from the module; hostiles converge on the site in waves
## starting "first_wave_s" after the deployment. Bring the crew to extraction: at most one may
## be lost (the bonus: everyone out).
static func _rescue(pick: RandomNumberGenerator, def: Dictionary, module: Dictionary, half: float, knobs: Dictionary, _target: String) -> Array:
	var centre := Vector2(float((module.pos as Array)[0]), float((module.pos as Array)[1]))
	var heading := pick.randf() * TAU
	var site := _inside(centre, Vector2(cos(heading), sin(heading)), float(knobs.get("site_offset_m", 220.0)), half)
	var count := pick.randi_range(int(knobs.get("crew", [2, 4])[0]), int(knobs.get("crew", [2, 4])[1]))
	var tag := pick.randi() % 100000
	var crew: Array = []
	var taken := {}
	for i in count:
		var who := Names.mission_person(pick, "crew", "US", Names.MALE, taken)
		taken[who] = true
		var wound := "none"
		if i == 0:
			wound = "leg"  # the one who has to be carried
		elif i == 1 and count >= 3:
			wound = "arm"
		crew.append({"hvt": "crew_%d_%d" % [tag, i + 1], "name": who, "wound": wound})
	var need := maxi(count - 1, 1)
	var wave: Array = knobs.get("first_wave_s", [150, 240])
	var params := {"scenario": RESCUE, "pos": _v3(site), "crew": crew, "need": need, "yaw": snappedf(pick.randf() * TAU, 0.01),
		"first_wave_s": snappedf(pick.randf_range(float(wave[0]), float(wave[1])), 15.0), "gap_s": float(knobs.get("gap_s", 150.0)),
		"approach_m": float(knobs.get("approach_m", 260.0))}
	var all := params.duplicate(true)
	all["need"] = count
	all["bonus_only"] = true
	return [
		{"kind": Objectives.RESCUE_CREW, "site": "", "params": params,
			"text": "Find the downed %s crew (%d), treat or carry the wounded, and get at least %d of them to extraction" % ["Black Hawk", count, need]},
		{"kind": Objectives.RESCUE_CREW, "site": "", "optional": true, "bonus_share": float(knobs.get("all_bonus_share", 0.15)), "params": all,
			"text": "Bonus: bring out the whole crew"},
	]


# --- Recon -----------------------------------------------------------------------------------

## Observe 2-4 enemy sites (distinct modules of the zone) from "observe_m" for "dwell_s" with
## a line of sight; the bonus: never spotted.
static func _recon(pick: RandomNumberGenerator, def: Dictionary, options: Array, half: float, knobs: Dictionary) -> Dictionary:
	var pool := options.duplicate()
	var want := mini(pick.randi_range(int(knobs.get("sites", [3, 4])[0]), int(knobs.get("sites", [3, 4])[1])), pool.size())
	var objectives: Array = []
	var first := ""
	var n := 0
	while n < want and not pool.is_empty():
		var m: Dictionary = pool.pop_at(pick.randi() % pool.size())
		n += 1
		var name := MissionRegistry.module_name(String(m.type))
		if first == "":
			first = String(m.type)
		var pos := Vector2(float((m.pos as Array)[0]), float((m.pos as Array)[1]))
		objectives.append({"kind": Objectives.RECON_SITE, "site": "",
			"params": {"scenario": RECON, "pos": _v3(pos), "module_id": String(m.id), "observe_m": float(knobs.get("observe_m", 75.0)),
				"dwell_s": float(knobs.get("dwell_s", 8.0)), "name": name},
			"text": ""})
	for i in objectives.size():
		objectives[i].text = "Recon: observe the %s at grid %s from within %d m" % [objectives[i].params.name, _grid(objectives[i].params.pos), roundi(float(knobs.get("observe_m", 75.0)))]
	objectives.append({"kind": Objectives.UNDETECTED, "site": "", "optional": true, "bonus_share": float(knobs.get("unseen_bonus_share", 0.25)),
		"params": {"scenario": RECON}, "text": "Bonus: never spotted"})
	return {"objectives": objectives, "module": first}


## A rough grid reference ("E 120 N -40") for a position, for objective text.
static func _grid(pos: Array) -> String:
	return "%d, %d" % [roundi(float(pos[0]) / 10.0) * 10, roundi(float(pos[2]) / 10.0) * 10]
