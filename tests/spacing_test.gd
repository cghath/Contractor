extends Node
## Squad spacing over a long follow (Captain, 2026-10-14, playtesting v0.3.1: "ai are bunching
## up after a while in mission"). Hosts a real session with the full 7-AI squad, walks the lead
## round the open ground outside the test compound, halts, takes contact (an enemy the squad
## sees and fights), a casualty, then goes in through the compound (the town) and out again,
## measuring every simulated second how far apart the squad stands: each squadmate's nearest
## neighbour (anyone in the squad, the lead too), pairs stacked closer than STACK_M, and how far
## apart the two fire teams are. Then the spacing must hold to the Proposed numbers the whole
## way (Squad.SPACINGS: open ground about 6-12 m between men and 15-30 m between fire teams,
## a town about 3-5 m).
##   <voxel godot exe> --headless --path . res://tests/spacing_test.tscn
## Exits with the number of failures.

## How much faster than real time the walk runs, and the lead's pace (a walk).
const SCALE := 3.0
const LEADER_SPEED := 2.0
## Closer than this two squadmates, two samples (seconds) running, count as stacked.
const STACK_M := 1.5
## Squadmates further than this from their formation spot are still getting there: not judged.
const SETTLING_M := 12.0

var failures := 0
var level: CompoundLevel
var player: Soldier
var _route := PackedVector3Array()
var _route_index := 0
var _sim_s := 0.0
var _paused_until := -1.0
var _close_before := {}  # pairs closer than STACK_M at the last sample


func _ready() -> void:
	GameState.zone_id = "test_spacing" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(420.0, true, false, true).timeout.connect(func() -> void:
		print("SPACING TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test walks the lead by hand
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	_remove_hostiles()
	_place(player, Vector3(0, 0.1, 30))
	await _seconds(1.0)
	_clear_contact()
	if OS.get_environment("SPACING_ONLY") != "wall":
		await _test_long_follow()
	await _test_wall_follow()
	GameState.delete_save()
	print("SPACING TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _physics_process(delta: float) -> void:
	if _route_index >= _route.size():
		return
	_sim_s += delta
	if _sim_s < _paused_until:
		return
	var to := _route[_route_index] - player.global_position
	to.y = 0.0
	if to.length() < 0.2:
		_route_index += 1
		return
	var step := minf(LEADER_SPEED * delta, to.length())
	player.global_position += to.normalized() * step
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))


## The walk: open ground right round the compound (a halt, a contact, a casualty on the way),
## then in through the gate, round the yard (the town) and out.
func _test_long_follow() -> void:
	print("Long follow: spacing holds over a mission's worth of walking, contact and a casualty")
	var map := player.get_world_3d().navigation_map
	# (The test ground's navmesh is 108 m square: the loop keeps the formation on it.)
	var open: Array[Vector3] = [Vector3(0, 0, 30), Vector3(0, 0, 40), Vector3(38, 0, 40), Vector3(40, 0, 0), Vector3(38, 0, -40),
		Vector3(0, 0, -42), Vector3(-38, 0, -40), Vector3(-40, 0, 0), Vector3(-38, 0, 40), Vector3(0, 0, 40), Vector3(0, 0, 30)]
	var town: Array[Vector3] = [Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(-12, 0, 8), Vector3(-14, 0, -14), Vector3(14, 0, -14),
		Vector3(14, 0, 8), Vector3(0, 0, 14), Vector3(0, 0, 30), Vector3(0, 0, 45)]
	var route := PackedVector3Array()
	for leg: Array[Vector3] in [open, town]:
		for k in range(1, leg.size()):
			route.append_array(NavigationServer3D.map_get_path(map, leg[k - 1], leg[k], true))
	var town_from := 0
	for k in range(1, open.size()):
		town_from += NavigationServer3D.map_get_path(map, open[k - 1], open[k], true).size()
	Engine.physics_ticks_per_second = roundi(60 * SCALE)
	Engine.time_scale = SCALE
	var real_start := Time.get_ticks_msec()
	_sim_s = 0.0
	_route = route
	_route_index = 0
	var samples := {"open": [], "town": []}
	var enemy: Soldier = null
	var hurt: Soldier = null
	var events := {}
	while _route_index < _route.size() and _sim_s < 600.0:
		await _seconds(1.0)
		# Interruptions on the way round: a halt, contact, a casualty.
		if _sim_s > 40.0 and not events.has("halt"):
			events.halt = true
			_paused_until = _sim_s + 15.0
			print("    %.0f s: the lead halts for 15 s" % _sim_s)
		if _sim_s > 75.0 and not events.has("contact"):
			events.contact = true
			var off := Vector3(-signf(player.global_position.x), 0.0, 0.0) * 100.0  # across the compound (the squad faces it)
			enemy = level.spawn_soldier({"name": "SpacingHostile", "faction": "hostile", "variant": "urban",
				"pos": player.global_position + off + Vector3.UP * 0.1, "loadout": [], "combat": 0.0, "discipline": 0.5, "guard": true})
			await _frames(2)
			SquadAI.of(enemy).process_mode = Node.PROCESS_MODE_DISABLED
			for s: Soldier in _squad():
				s.threat_pos = enemy.global_position
				s.threat_time = Soldier._now()
			level.squad_for(&"friendly").note_enemy(enemy, enemy.global_position)
			_paused_until = _sim_s + 25.0  # the lead goes to ground while they fight
			print("    %.0f s: contact %.0f m off" % [_sim_s, enemy.global_position.distance_to(player.global_position)])
		if events.has("contact") and not events.has("contact_over") and _sim_s > 105.0:
			events.contact_over = true
			if is_instance_valid(enemy):
				enemy.queue_free()
			_clear_contact()
			print("    %.0f s: contact over" % _sim_s)
		if _sim_s > 130.0 and not events.has("casualty"):
			events.casualty = true
			hurt = _ai("Delta")
			if hurt:
				hurt.vitals.server_damage(45.0)
				print("    %.0f s: Delta is hit (%s)" % [_sim_s, hurt.vitals.condition_text()])
		var where := "town" if _route_index >= town_from and absf(player.global_position.x) < 22.0 and absf(player.global_position.z) < 22.0 else "open"
		if _sim_s > 20.0:
			var m := _measure()
			if not m.is_empty():
				m.t = _sim_s
				(samples[where] as Array).append(m)
		if OS.get_environment("SPACING_DEBUG") != "" and int(_sim_s) % 10 == 0:
			_dump()
	var walked := _sim_s
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_route = PackedVector3Array()
	print("    %.0f s simulated in %.0f s real" % [walked, (Time.get_ticks_msec() - real_start) / 1000.0])
	for where: String in ["open", "town"]:
		var list: Array = samples[where]
		_report(where, list)
	var open_s: Array = samples.open
	var town_s: Array = samples.town
	check(open_s.size() >= 60 and town_s.size() >= 15, "measured %d s in the open and %d s in the town" % [open_s.size(), town_s.size()])
	if open_s.is_empty() or town_s.is_empty():
		return
	var open_nn := _median(open_s.map(func(m: Dictionary) -> float: return m.nn))
	var open_late := _median(open_s.slice(open_s.size() / 2).map(func(m: Dictionary) -> float: return m.nn))
	var open_stacked := _mean(open_s.map(func(m: Dictionary) -> float: return m.stacked))
	var open_teams := _median(open_s.map(func(m: Dictionary) -> float: return m.teams))
	var town_nn := _median(town_s.map(func(m: Dictionary) -> float: return m.nn))
	var on_lead := _mean(open_s.map(func(m: Dictionary) -> float: return m.on_lead) + town_s.map(func(m: Dictionary) -> float: return m.on_lead))
	check(open_nn >= 5.0 and open_nn <= 14.0, "open ground: men about 6-12 m apart (median nearest neighbour %.1f m)" % open_nn)
	check(open_late >= 5.0, "and still after the halt, the contact and the casualty (second half %.1f m)" % open_late)
	check(open_stacked <= 0.1, "nobody stacks on anyone in the open (%.2f stacked pairs a second)" % open_stacked)
	check(open_teams >= 12.0 and open_teams <= 36.0, "the fire teams keep about 15-30 m apart (median %.1f m)" % open_teams)
	check(town_nn >= 2.5 and town_nn < open_nn, "in the town they close up, to about 3-5 m (median %.1f m, open %.1f m)" % [town_nn, open_nn])
	check(on_lead <= 0.05, "nobody walks on the lead's heels (%.2f a second within %.1f m)" % [on_lead, STACK_M])


## Beside a long wall (Captain, 2026-10-15, v0.4.3 harbour_yard screenshot, "dynamic: wedge"):
## the squad piled into a single file pressed on the building wall, one man stood in the player,
## and they stayed there when he moved on. The lead walks a metre off the outside of the
## compound's west wall (40 m of 2.6 m concrete) in a wedge, normal spacing, the wall on the
## wedge's left arm, halts beside it, then walks away into the open.
func _test_wall_follow() -> void:
	print("Wall follow: walking beside a long wall, nobody piles on the wall or the lead, nobody stays stuck")
	var squad := level.squad_for(&"friendly")
	squad.formation = "wedge"
	squad.spacing = "normal"
	Engine.physics_ticks_per_second = roundi(60 * SCALE)
	Engine.time_scale = SCALE
	var wall_x := -CompoundLevel.COMPOUND_HALF  # the west wall's outer face
	var start := Vector3(wall_x - 1.0, 0.1, -30.0)
	_route = PackedVector3Array()
	_place(player, start)
	player.rotation.y = 0.0  # facing -z; the walk turns him north
	squad.heading = Vector3(0, 0, 1)
	squad._heading_from = start
	squad.set(&"_trail", PackedVector3Array())  # (a fresh start: no trail from the long follow)
	await _frames(2)
	for s: Soldier in _squad():
		if s.vitals.is_up():
			_place(s, squad.follow_point(s) + Vector3.UP * 0.1)
	await _seconds(2.0)
	_sim_s = 0.0
	_paused_until = -1.0
	_route = PackedVector3Array([Vector3(wall_x - 1.0, 0.0, 16.0)])
	_route_index = 0
	var on_lead := 0
	var stacked := 0
	var on_wall_max := 0
	var samples := 0
	var close_before := {}
	var phase := "walk"
	var halt_end := -1.0
	var t := 0.0  # (_sim_s stops when the route ends)
	while phase != "done" and t < 120.0:
		await _seconds(0.5)
		t += 0.5
		if phase == "walk" and _route_index >= _route.size():
			phase = "halt"
			halt_end = t + 8.0
		elif phase == "halt" and t >= halt_end:
			phase = "done"
		samples += 1
		var up: Array[Soldier] = []
		for s: Soldier in _squad():
			if s.vitals.is_up():
				up.append(s)
		var on_wall := 0
		var close := {}
		for i in up.size():
			var a := up[i]
			if _flat(a.global_position, player.global_position) < STACK_M:
				on_lead += 1
			if a.global_position.x > wall_x - 1.6 and absf(a.global_position.z - player.global_position.z) < 14.0:
				on_wall += 1  # right up on the wall, along the lead's stretch of it
			for j in range(i + 1, up.size()):
				if _flat(a.global_position, up[j].global_position) < STACK_M:
					var key := "%s|%s" % [a.name, up[j].name]
					close[key] = true
					if close_before.has(key):
						stacked += 1
		close_before = close
		on_wall_max = maxi(on_wall_max, on_wall)
		if OS.get_environment("SPACING_DEBUG") != "" and samples % 4 == 0:
			_dump()
	print("    %d samples: %d on the lead, %d stacked, at most %d on the wall at once" % [samples, on_lead, stacked, on_wall_max])
	check(on_lead <= 1, "nobody stands on the lead beside the wall (%d half-second samples within %.1f m)" % [on_lead, STACK_M])
	check(stacked <= 2, "nobody stacks on anyone beside the wall (%d samples)" % stacked)
	check(on_wall_max <= 3, "the squad doesn't pile into a line on the wall (at most %d men within 0.6 m of it)" % on_wall_max)
	# The slots themselves, halted: apart from each other and the lead.
	var slots: Array[Vector3] = []
	var nearest := INF
	for s: Soldier in _squad():
		if s.vitals.is_up():
			var p := squad.follow_point(s)
			nearest = minf(nearest, _flat(p, player.global_position))
			for q in slots:
				nearest = minf(nearest, _flat(p, q))
			slots.append(p)
	check(nearest >= 2.0, "halted by the wall, every slot is 2 m or more from the lead and the others (closest %.1f m)" % nearest)
	# Then off into the open: everyone comes along.
	_sim_s = 0.0
	_route = PackedVector3Array([Vector3(wall_x - 24.0, 0.0, 16.0), Vector3(wall_x - 24.0, 0.0, 40.0)])
	_route_index = 0
	while _route_index < _route.size() and _sim_s < 60.0:
		await _seconds(0.5)
	await _seconds(12.0)
	var behind := PackedStringArray()
	for s: Soldier in _squad():
		if s.vitals.is_up() and _flat(s.global_position, squad.follow_point(s)) > SETTLING_M:
			behind.append("%s %.0f m off" % [s.name, _flat(s.global_position, squad.follow_point(s))])
			var ai := SquadAI.of(s)  # (what holds him: an order, a tactic, care)
			print("    stuck %s: %s, order %s, tactic %s, care %d" % [s.name, s.ai_status, Squad.Order.keys()[ai.order], ai.ordered.get("kind", "-"), ai.care])
	check(behind.is_empty(), "walking away from the wall, nobody stays stuck on it (%s)" % (", ".join(behind) if not behind.is_empty() else "all with their slots"))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_route = PackedVector3Array()
	squad.formation = Squad.DYNAMIC
	squad.spacing = Squad.DYNAMIC


## One second's spacing: the median of each judged squadmate's nearest neighbour, pairs closer
## than STACK_M, squadmates that close to the lead, and the fire teams' centres apart. {} if
## too few are following.
func _measure() -> Dictionary:
	var squad := level.squad_for(&"friendly")
	var up: Array[Soldier] = [player]
	var judged: Array[Soldier] = []
	for s: Soldier in _squad():
		if not s.vitals.is_up() or s.carrying != null or is_instance_valid(s.carried_by):
			continue
		up.append(s)
		var ai := SquadAI.of(s)
		if ai.intent in [SquadAI.Intent.FOLLOW, SquadAI.Intent.FIGHT] and ai.care == SquadAI.Care.NONE \
				and _flat(s.global_position, squad.follow_point(s)) < SETTLING_M:
			judged.append(s)
	if judged.size() < 4:
		return {}
	var nn: Array = []
	var on_lead := 0
	for s in judged:
		var best := INF
		for o in up:
			if o != s:
				best = minf(best, _flat(s.global_position, o.global_position))
		nn.append(best)
		if _flat(s.global_position, player.global_position) < STACK_M:
			on_lead += 1
	# Stacked: still that close a second later (two passing each other aren't stacked).
	var stacked := 0
	var close := {}
	for i in judged.size():
		for j in range(i + 1, judged.size()):
			if _flat(judged[i].global_position, judged[j].global_position) < STACK_M:
				var key := "%s|%s" % [judged[i].name, judged[j].name]
				close[key] = true
				if _close_before.has(key):
					stacked += 1
	_close_before = close
	var centres := [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	for s in up:
		var team := s.fire_team if s.fire_team in [0, 1] else 0
		centres[team] += s.global_position
		counts[team] += 1
	var teams := INF
	if counts[0] > 0 and counts[1] > 0:
		teams = _flat(centres[0] / counts[0], centres[1] / counts[1])
	return {"nn": _median(nn), "min": nn.min(), "stacked": float(stacked), "on_lead": float(on_lead), "teams": teams}


## SPACING_DEBUG: where everyone is against the lead, his slot and what he's doing.
func _dump() -> void:
	var squad := level.squad_for(&"friendly")
	print("    -- %.0f s lead %s heading %s context %s" % [_sim_s, player.global_position.snappedf(0.1), squad.heading.snappedf(0.01), squad.context])
	for s: Soldier in _squad():
		var ai := SquadAI.of(s)
		print("      %s t%d at %s slot %s dest %s %s" % [s.name, s.fire_team, (s.global_position - player.global_position).snappedf(0.1),
			(squad.follow_point(s) - player.global_position).snappedf(0.1), (ai.destination() - player.global_position).snappedf(0.1) if ai.destination().is_finite() else "-", s.ai_status])


func _report(where: String, list: Array) -> void:
	if list.is_empty():
		print("    %s: no samples" % where)
		return
	# Every 20 s: how the spacing went over time.
	var line := PackedStringArray()
	var k := 0
	while k < list.size():
		var chunk := list.slice(k, k + 20)
		line.append("%.0fs nn %.1f min %.1f teams %.0f" % [float(chunk[0].t), _median(chunk.map(func(m: Dictionary) -> float: return m.nn)),
			chunk.map(func(m: Dictionary) -> float: return m.min).min(), _median(chunk.map(func(m: Dictionary) -> float: return m.teams))])
		k += 20
	print("    %s: %s" % [where, " | ".join(line)])


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return float(v[v.size() / 2])


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for x: float in values:
		sum += x
	return sum / values.size()


# --- Helpers --------------------------------------------------------------

func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s.faction == &"friendly" and not s.is_queued_for_deletion())


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _clear_contact() -> void:
	for s: Soldier in _squad():
		s.threat_time = -1000.0
		var ai := SquadAI.of(s)
		ai._last_contact = -1000.0
		ai._fired_on_at = -1000.0
		ai.target = null
	var squad := level.squad_for(&"friendly")
	squad.engaged_at = -1000.0
	squad.known.clear()


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
