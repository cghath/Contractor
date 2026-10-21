class_name ObserverMission
extends Node
## The forward observer contract (the Captain's list, 2026-10-20, "Campaign / mission types";
## contracts.json "forward_observer", ScenarioGen's "observer"): a client wants a site hit without
## anyone walking onto it. The squad gets eyes on the target area (a RECON_SITE objective, played by
## MissionScenario: within observe_m with a line of sight), calls fire on the vehicles and positions
## there (FireSupport: the mortars or the battery), and stays unseen (UNDETECTED, a bonus). Each
## target is an Objectives.FIRE_TARGET: the first required, the rest bonuses, so the pay goes by the
## targets the guns destroy. A target put out of action any other way (a charge, a rocket) fails
## its objective: the client paid for the guns' work.
##
## Targets ("model", "name", "pos" in the objective's params): an enemy vehicle or a weapon pit
## parked hostile and empty about the target module when the contract goes live (VehicleLayer.
## server_place_parked; out of the zone save while whole, as sabotage's vehicle park, so a squad
## back in the zone finds the same one: the id is kept in the params). Down (a wreck, burning, or a
## vehicle that can't drive) within CREDIT_S of a fire mission's round hurting it
## (FireSupport.HIT_META): done; down without one: failed.
##
## One node, "ObserverMission", in every level (FireSupport.install); the host's. Pure builder for
## the objectives: build() (ScenarioGen calls it). Test hook: target_vehicle(oid).

const NODE_NAME := "ObserverMission"
const TICK_S := 0.5
## A target down this soon after a fire mission's round hurt it is the guns' kill (s).
const CREDIT_S := 60.0
## What can stand in the target area: [model, name]. Proposed.
const TARGETS := [
	["technical_zu23", "ZU-23 anti-aircraft technical"],
	["technical_rockets", "rocket technical"],
	["technical_dshk", "DShK technical"],
	["technical_spg9", "SPG-9 recoilless technical"],
	["mortar_2b14", "82 mm mortar position"],
]

## Host: oid -> {"oid", "cid", "id" (the vehicle's), "credited"}.
var runs := {}
var _tick := 0.0


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	Contracts.contract_live.connect(_on_live)
	Contracts.contract_returned.connect(_on_live)


static func of(from: Node) -> ObserverMission:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as ObserverMission if lvl else null


# --- The objectives (pure; ScenarioGen) ----------------------------------------------------------

## The forward observer's objectives round the target `module` (a zone layout module): get eyes on
## the area (RECON_SITE from within "observe_m"), "targets" FIRE_TARGETs "spread_m" about it (the
## first required, each other a bonus of "target_bonus_share"), never spotted (UNDETECTED, a bonus).
static func build(pick: RandomNumberGenerator, module: Dictionary, half: float, knobs: Dictionary) -> Array:
	var centre := Vector2(float((module.pos as Array)[0]), float((module.pos as Array)[1]))
	var keep := half - ScenarioGen.EDGE_KEEP_M
	var name := MissionRegistry.module_name(String(module.type))
	var count := pick.randi_range(int(knobs.get("targets", [3, 4])[0]), int(knobs.get("targets", [3, 4])[1]))
	var spread: Array = knobs.get("spread_m", [25, 70])
	var observe_m := float(knobs.get("observe_m", 700.0))
	var grid := ScenarioGen._grid(ScenarioGen._v3(centre))
	var out: Array = [{"kind": Objectives.RECON_SITE, "site": "",
		"params": {"scenario": "observer", "pos": ScenarioGen._v3(centre), "module_id": String(module.get("id", "")), "observe_m": observe_m,
			"dwell_s": float(knobs.get("dwell_s", 10.0)), "name": "target area (%s)" % name},
		"text": "Get eyes on the target area, the %s at grid %s, from within %d m" % [name, grid, roundi(observe_m)]}]
	var pool := TARGETS.duplicate()
	for i in count:
		var t: Array = pool.pop_at(pick.randi() % pool.size()) if not pool.is_empty() else TARGETS[pick.randi() % TARGETS.size()]
		var a := pick.randf() * TAU
		var p := centre + Vector2(cos(a), sin(a)) * pick.randf_range(float(spread[0]), float(spread[1]))
		p = Vector2(clampf(p.x, -keep, keep), clampf(p.y, -keep, keep))
		var o := {"kind": Objectives.FIRE_TARGET, "site": "",
			"params": {"scenario": "observer", "pos": ScenarioGen._v3(p), "model": String(t[0]), "name": String(t[1]), "yaw_deg": snappedf(pick.randf() * 360.0, 1.0),
				"module_id": String(module.get("id", ""))},
			"text": "Bring fire onto the %s by the %s" % [String(t[1]), name]}  # (the HUD hint says how: ObjectiveHelper)
		if i > 0:
			o["optional"] = true
			o["bonus_share"] = float(knobs.get("target_bonus_share", 0.25))
			o.text = "Bonus: " + String(o.text)
		out.append(o)
	out.append({"kind": Objectives.UNDETECTED, "site": "", "optional": true, "bonus_share": float(knobs.get("unseen_bonus_share", 0.2)),
		"params": {"scenario": "observer"}, "text": "Bonus: never spotted"})
	return out


# --- Playing it (host) ---------------------------------------------------------------------------

func _on_live(_cid: String, objectives: Array) -> void:
	if not multiplayer.is_server():
		return
	var lvl := CompoundLevel.current(self)
	for given: Dictionary in objectives:
		if String(given.get("kind", "")) != Objectives.FIRE_TARGET or runs.has(String(given.oid)) or not Objectives.here(given, lvl):
			continue
		var o := Contracts.objectives.get_objective(String(given.oid))
		if not o.is_empty() and o.state == Objectives.ACTIVE:
			_begin(o)


## Host: objective `o`'s target parked (unless it's out of action already) and its run started.
func _begin(o: Dictionary) -> void:
	var p: Dictionary = o.params
	var layer := VehicleLayer.of(self)
	var lvl := CompoundLevel.current(self)
	if layer == null or lvl == null:
		return
	if String(p.get("id", "")) == "":
		p["id"] = ("fo_%s_%d" % [String(o.oid), Time.get_ticks_msec()]).validate_node_name()
	var id := String(p.id)
	var arr: Array = p.pos
	var at := lvl.ground_point(Vector3(float(arr[0]), 0.0, float(arr[2]))) + Vector3.UP * 0.2
	layer.server_place_parked([{"id": id, "model": String(p.model), "pos": at, "yaw": float(p.get("yaw_deg", 0.0)), "faction": "hostile"}])
	var v := layer.find(id)
	if v and not v.wrecked:
		v.set_meta(&"no_save", true)
	runs[String(o.oid)] = {"oid": String(o.oid), "cid": String(o.cid), "id": id, "credited": false}
	print("[mission] forward observer target %s: %s at (%.0f, %.0f)" % [o.oid, String(p.model), at.x, at.z])
	_check(runs[String(o.oid)], o)


func _physics_process(delta: float) -> void:
	if runs.is_empty() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	server_check()


## Host: every target's state now (the physics frame calls it; tests too).
func server_check() -> void:
	for oid: String in runs.keys():
		var o := Contracts.objectives.get_objective(oid)
		if o.is_empty() or o.state != Objectives.ACTIVE:
			runs.erase(oid)
			continue
		_check(runs[oid], o)


func _check(run: Dictionary, o: Dictionary) -> void:
	var layer := VehicleLayer.of(self)
	var v := layer.find(String(run.id)) if layer else null
	if v and FireSupport.hit_lately(v, CREDIT_S):
		run.credited = true
	var down := v == null or v.wrecked or v.is_burning() or (v.kind != Vehicle.STATIC and not v.can_drive())
	if not down:
		Contracts.objectives.server_set_state(String(run.oid), Objectives.ACTIVE, "standing" if not (v and v.has_meta(FireSupport.HIT_META)) else "hit, still standing")
		return
	if bool(run.credited) or (v and FireSupport.hit_lately(v, CREDIT_S)):
		Contracts.objectives.server_set_state(String(run.oid), Objectives.DONE, "destroyed by the fire you called")
		Contracts._notify_all("Target destroyed: the %s." % String(o.params.get("name", "target")))
	else:
		Contracts.objectives.server_set_state(String(run.oid), Objectives.FAILED, "put out of action, but not by the guns")


## The parked target of objective `oid` (tests), or null.
func target_vehicle(oid: String) -> Vehicle:
	var layer := VehicleLayer.of(self)
	return layer.find(String(runs.get(oid, {}).get("id", ""))) if layer and runs.has(oid) else null
