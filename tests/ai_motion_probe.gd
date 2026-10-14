extends Node
## AI movement-quality probe (not a pass/fail suite; Captain 2026-10-14: AI "move around
## weirdly, lots of zigging and unnatural paths, and piling up on the enemy team").
## Hosts the hot zone with the AI on, walks the (untargetable) lead toward the nearest
## garrisoned module and stops ENGAGE_STOP_M short of it, then records every AI's motion for
## RUN_S seconds and prints the numbers:
##   tortuosity      path walked / straight distance, per move order (destination change > 1.5 m,
##                   moves of 3 m or more)
##   turns45/s       velocity heading changes over 45 deg between 0.25 s samples, per moving second
##   flips/min       heading reversals (over 120 deg), per moving minute
##   repaths/min     navmesh paths drawn (SquadAI._repath_cd jumps up), per minute alive
##   mate<1m         share of samples with a squadmate (same side) closer than 1 m
##   foe<10m         share of engaged samples (with a target) with the nearest foe under 10 m,
##                   and how many units ever got that close
##   <exe> --headless --path . res://tests/ai_motion_probe.tscn  (env PROBE_RUN_S, PROBE_SEED)

const ZONE := "ridge_hot"
const ENGAGE_STOP_M := 70.0
const LEAD_SPEED := 1.6
const START_M := 160.0
const SETTLE_S := 12.0
const SAMPLE_S := 0.25

var level: ZoneLevel
var player: Soldier
var run_s := float(OS.get_environment("PROBE_RUN_S")) if OS.get_environment("PROBE_RUN_S") != "" else 150.0
var _units := {}  # instance id -> track dict
var _t := 0.0
var _sample_cd := 0.0
var _lead_path := PackedVector3Array()
var _lead_i := 0
var _recording := false


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	seed(int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 1234)
	GameState.zone_id = "test_probe" + tag
	Campaign.campaign_id = "test_probe_campaign" + tag
	CompoundLevel.spawn_ai = true
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(run_s + 200.0).timeout.connect(func() -> void:
		print("PROBE FAILED (timed out)")
		get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.remove_from_group(&"combatants")  # the lead walks; nobody shoots him
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	var waited := 0.0
	while _squad().size() < 7 and waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	await get_tree().create_timer(3.0).timeout
	var module := _target_module()
	if module == null:
		print("PROBE FAILED (no garrisoned module)")
		get_tree().quit(1)
		return
	var centre := module.global_position
	# The squad starts START_M out from the module, on the side the lead came from.
	var out := (Vector3(player.global_position.x, 0, player.global_position.z) - Vector3(centre.x, 0, centre.z)).normalized()
	var start := level.ground_point(centre + out * START_M) + Vector3.UP * 0.1
	player.global_position = start
	var k := 0
	for s: Soldier in _squad():
		k += 1
		s.global_position = level.ground_point(start + out * 2.0 + out.cross(Vector3.UP) * (k - 4) * 1.5) + Vector3.UP * 0.1
		s.velocity = Vector3.ZERO
	await get_tree().create_timer(SETTLE_S).timeout  # the modules and the navigation there stream in
	var from := player.global_position
	var to := centre + (Vector3(from.x, 0, from.z) - Vector3(centre.x, 0, centre.z)).normalized() * ENGAGE_STOP_M
	var map := player.get_world_3d().navigation_map
	to = NavigationServer3D.map_get_closest_point(map, to)
	_lead_path = NavigationServer3D.map_get_path(map, from, to, true)
	print("probe: lead from (%.0f, %.0f) to (%.0f, %.0f), %.0f m from module %s (%s) at (%.0f, %.0f); path %d points" % [from.x, from.z,
		to.x, to.z, ENGAGE_STOP_M, module.module_id, module.type, centre.x, centre.z, _lead_path.size()])
	_recording = true
	await get_tree().create_timer(run_s).timeout
	_recording = false
	_report()
	GameState.delete_save()
	Campaign.reset_campaign()
	print("PROBE DONE")
	get_tree().quit(0)


## The nearest module with garrison posts (streamed in, or not).
func _target_module() -> ZoneModule:
	var best: ZoneModule = null
	var best_d := INF
	for m in level.modules():
		if (ZoneModules.GARRISON.get(m.type, []) as Array).is_empty():
			continue
		var d := m.distance_to(player.global_position)
		if d < best_d:
			best = m
			best_d = d
	return best


func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and (s as Soldier).faction == &"friendly")


func _physics_process(delta: float) -> void:
	if not _recording:
		return
	_t += delta
	_walk_lead(delta)
	for n in level.ai.get_children():
		var s := n as Soldier
		var ai := SquadAI.of(s)
		if s == null or ai == null or s.is_queued_for_deletion():
			continue
		var id := s.get_instance_id()
		if not _units.has(id):
			_units[id] = {"name": String(s.name), "side": String(s.faction), "repaths": 0, "cd": ai._repath_cd, "alive_s": 0.0,
				"moving_s": 0.0, "turns": 0, "flips": 0, "samples": [], "seg": {}, "tort": [], "mate_n": 0, "mate_close": 0,
				"eng_n": 0, "eng_close": 0, "ever_close": false, "foe_d": []}
		var u: Dictionary = _units[id]
		if not s.vitals.is_up():
			u.seg = {}
			continue
		u.alive_s += delta
		if ai._repath_cd > float(u.cd) + 0.01:
			u.repaths += 1
		u.cd = ai._repath_cd
		_track_segment(u, ai, s)
	_sample_cd -= delta
	if _sample_cd <= 0.0:
		_sample_cd = SAMPLE_S
		_sample()


## Walks the lead along its path at walking pace, then stands.
func _walk_lead(delta: float) -> void:
	var step := LEAD_SPEED * delta
	while step > 0.0 and _lead_i < _lead_path.size():
		var p := _lead_path[_lead_i]
		var to := p - player.global_position
		if to.length() <= step:
			player.global_position = p
			step -= to.length()
			_lead_i += 1
		else:
			player.global_position += to.normalized() * step
			player.rotation.y = atan2(-to.x, -to.z)
			step = 0.0


func _track_segment(u: Dictionary, ai: SquadAI, s: Soldier) -> void:
	var seg: Dictionary = u.seg
	var pos := Vector3(s.global_position.x, 0, s.global_position.z)
	var dest := Vector3(ai._destination.x, 0, ai._destination.z)
	var going := ai._has_destination and ai._flat_distance(ai._destination) > SquadAI.ARRIVE
	if not seg.is_empty():
		seg.len += pos.distance_to(seg.last)
		seg.last = pos
		if not going or dest.distance_to(seg.dest) > 1.5:
			var straight := pos.distance_to(seg.start)
			if straight >= 3.0:
				(u.tort as Array).append(float(seg.len) / straight)
			u.seg = {}
			seg = u.seg
	if going and seg.is_empty():
		u.seg = {"start": pos, "last": pos, "len": 0.0, "dest": dest}
	elif going:
		seg.dest = dest  # a slowly moving goal (a follow slot) stays one order


func _sample() -> void:
	var alive: Array[Soldier] = []
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and s.vitals.is_up() and _units.has(s.get_instance_id()):
			alive.append(s)
	for s in alive:
		var u: Dictionary = _units[s.get_instance_id()]
		var ai := SquadAI.of(s)
		var p := Vector2(s.global_position.x, s.global_position.z)
		var samples: Array = u.samples
		if not samples.is_empty():
			var prev: Dictionary = samples[-1]
			var v: Vector2 = (p - (prev.p as Vector2)) / SAMPLE_S
			if v.length() > 0.5 and v.length() < 12.0:
				u.moving_s += SAMPLE_S
				if prev.has("v") and (prev.v as Vector2).length() > 0.5:
					var ang := rad_to_deg(absf((prev.v as Vector2).angle_to(v)))
					if ang > 45.0:
						u.turns += 1
					if ang > 120.0:
						u.flips += 1
				samples.append({"p": p, "v": v})
			else:
				samples.append({"p": p})
		else:
			samples.append({"p": p})
		if samples.size() > 4:
			samples.pop_front()
		var mate := INF
		var foe := INF
		for o in alive:
			if o == s:
				continue
			var d := Vector2(o.global_position.x - s.global_position.x, o.global_position.z - s.global_position.z).length()
			if o.faction == s.faction:
				mate = minf(mate, d)
			else:
				foe = minf(foe, d)
		if s.faction == &"friendly":
			var d := Vector2(player.global_position.x - s.global_position.x, player.global_position.z - s.global_position.z).length()
			mate = minf(mate, d)  # the lead counts as a squadmate
		else:
			var d := Vector2(player.global_position.x - s.global_position.x, player.global_position.z - s.global_position.z).length()
			foe = minf(foe, d)
		if mate < INF:
			u.mate_n += 1
			if mate < 1.0:
				u.mate_close += 1
		if ai.target != null and foe < INF:
			u.eng_n += 1
			(u.foe_d as Array).append(foe)
			if foe < 10.0:
				u.eng_close += 1
				u.ever_close = true


func _report() -> void:
	print("probe: %.0f s recorded" % _t)
	print("probe: unit                    side     alive  tort(med) turns45/s flips/min repaths/min mate<1m  foe<10m  foe(med)")
	var sides := {}
	for id: int in _units:
		var u: Dictionary = _units[id]
		if float(u.alive_s) < 10.0:
			continue
		var tort: Array = (u.tort as Array).duplicate()
		tort.sort()
		var foe_d: Array = (u.foe_d as Array).duplicate()
		foe_d.sort()
		var row := {
			"tort": tort[tort.size() / 2] if not tort.is_empty() else -1.0,
			"turns": float(u.turns) / maxf(float(u.moving_s), 1.0),
			"flips": float(u.flips) / maxf(float(u.moving_s), 1.0) * 60.0,
			"repaths": float(u.repaths) / float(u.alive_s) * 60.0,
			"mate": float(u.mate_close) / maxf(float(u.mate_n), 1.0),
			"foe10": float(u.eng_close) / maxf(float(u.eng_n), 1.0),
			"foe_med": foe_d[foe_d.size() / 2] if not foe_d.is_empty() else -1.0,
		}
		print("probe: %-22s %-8s %5.0f  %8.2f %9.2f %9.1f %11.1f %7.0f%% %7.0f%% %8.1f  (%d moves, %.0f s moving, %d engaged samples)" % [u.name, u.side,
			u.alive_s, row.tort, row.turns, row.flips, row.repaths, row.mate * 100.0, row.foe10 * 100.0, row.foe_med, tort.size(), u.moving_s, u.eng_n])
		var side: String = u.side
		if not sides.has(side):
			sides[side] = {"n": 0, "tort": [], "turns": 0.0, "moving": 0.0, "flips": 0.0, "repaths": 0.0, "alive": 0.0,
				"mate_n": 0, "mate_close": 0, "eng_n": 0, "eng_close": 0, "ever": 0, "engaged_units": 0, "foe_d": []}
		var a: Dictionary = sides[side]
		a.n += 1
		(a.tort as Array).append_array(u.tort)
		a.turns += float(u.turns)
		a.flips += float(u.flips)
		a.moving += float(u.moving_s)
		a.repaths += float(u.repaths)
		a.alive += float(u.alive_s)
		a.mate_n += int(u.mate_n)
		a.mate_close += int(u.mate_close)
		a.eng_n += int(u.eng_n)
		a.eng_close += int(u.eng_close)
		(a.foe_d as Array).append_array(u.foe_d)
		if int(u.eng_n) > 0:
			a.engaged_units += 1
		if u.ever_close:
			a.ever += 1
	for side: String in sides:
		var a: Dictionary = sides[side]
		var tort: Array = a.tort
		tort.sort()
		var foe_d: Array = a.foe_d
		foe_d.sort()
		var p90: float = tort[int(tort.size() * 0.9)] if not tort.is_empty() else -1.0
		print("PROBE SUMMARY %s: units %d, moves %d, tortuosity median %.2f p90 %.2f, turns45 %.2f/s moving, flips %.1f/min moving, repaths %.1f/min, mate<1m %.1f%%, engaged %d units, foe<10m %.1f%% of engaged samples, %d units ever within 10 m, foe distance median %.1f m" % [
			side, a.n, tort.size(), tort[tort.size() / 2] if not tort.is_empty() else -1.0, p90, a.turns / maxf(a.moving, 1.0),
			a.flips / maxf(a.moving, 1.0) * 60.0, a.repaths / maxf(a.alive, 1.0) * 60.0, float(a.mate_close) / maxf(a.mate_n, 1) * 100.0,
			a.engaged_units, float(a.eng_close) / maxf(a.eng_n, 1) * 100.0, a.ever, foe_d[foe_d.size() / 2] if not foe_d.is_empty() else -1.0])
