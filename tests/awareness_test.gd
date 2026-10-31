extends Node3D
## What the enemy can know of the squad (Captain's "Next" 2, 2026-10-14: "AI awareness leaks
## through compound walls; one zone-wide hostile squad (ai_bar_gaps G-02/G-03). Tied to the infil
## problems."). In the test zone with AI, the squad by the compound and its garrison:
## - Hidden: the squad stands still just outside the compound's wall, out of every line from inside
##   (and the test checks no hostile had one). For HIDE_S nobody there or anywhere in the zone
##   learns of them: no awareness, target, suspicion or threat near them, no squad's picture, and the
##   alert stays calm with nothing on the way.
## - Footsteps through the wall (G-29): a man walking there is heard no further off than footsteps
##   carry through a wall (Spotting.STEPS_WALK_M x SquadAI.WALL_STEPS_MULT).
## - Seen: one of them steps into a garrison man's sight. Only the compound stands to at once; the
##   zone, and every other squad, hear of it by radio, after the report delay (Alert: discipline,
##   under fire, the mast), and only squads with a man within Alert.NET_SHARE_M of it are told. The
##   report counts the men he saw, not the ones behind the wall (F-360). A contact the net hasn't
##   heard of yet doesn't ride in on someone else's report of a shot (F-361). The mast down, the
##   report takes Alert.COMMS_DOWN_MULT longer; a reporter cut down first takes it with him.
## - Heard: a suppressed shot behind the wall carries half as far to the alert through it (F-359,
##   as SquadAI's own hearing: G-29).
## - From the air: a recon drone goes where the net last heard of the squad, not to the squad, and
##   doesn't see them under a roof (F-362).

const HIDE_S := 20.0
## Knowledge "near" the squad: a suspicion, threat or heard fix within this of one of them.
const NEAR_M := 20.0

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier
var alert: Alert
var m: ZoneModule
var men: Array[Soldier] = []  # the squad behind the wall: the player and three squad AI
var spot := Vector3.ZERO      # where they stand
var along := Vector3.ZERO     # along the wall there


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_awareness" + tag  # never touch a real save
	Campaign.campaign_id = "test_awareness" + tag
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	EnemyDrones.enabled = false  # the drone section sends its own
	Bombers.enabled = false
	await _run()
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(ZoneDef.get_def("test"))
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the test zone is up")
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	alert = Alert.of(level)
	m = level.get_module("compound")
	# Out of everyone's sight (not a combatant) while the compound streams in and its garrison
	# comes out, so nothing is known of the squad before the test starts.
	player.remove_from_group(&"combatants")
	player.global_position = level.ground_point(m.to_global(Vector3(45, 0, 0)))
	await _wait_for(func() -> bool: return level.post_of("compound") != null and level.garrison_pending("compound") == 0 \
		and m.voxel_world != null and not m._proxy_up and not MapNodes.squad_ai(level).is_empty(), 40.0)
	var post := level.post_of("compound")
	check(post != null and post.alive().size() >= 3 and alert != null, "the compound's garrison is out (%d men), its walls built" % (post.alive().size() if post else 0))
	if post == null or alert == null:
		return
	var mates := MapNodes.squad_ai(level)
	var found: Variant = _hidden_spot()
	check(found != null, "a spot just outside the wall no eye inside has a line to")
	if found == null:
		return
	spot = found[0]
	along = found[1]
	men = [player]
	for k in mates.size():
		var s := mates[k]
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # they stand where they're put, quiet
		s.set_physics_process(false)
		s.velocity = Vector3.ZERO
		if k < 3:
			men.append(s)
		else:
			s.remove_from_group(&"combatants")  # the rest of the squad: elsewhere, out of it
			s.global_position = level.ground_point(m.to_global(Vector3(300, 0, 300 + k * 3.0)))
	for k in men.size():
		men[k].global_position = level.ground_point(spot + along * (k - 1.5) * 1.2)
	player.velocity = Vector3.ZERO
	player.add_to_group(&"combatants")
	# The rest of the zone: a patrol on the compound's far side (in radio reach of it) and one far
	# out (beyond Alert.NET_SHARE_M), each its own squad, as EnemyResponse's are.
	_spawn_patrol("NearPatrol", m.global_position + Vector3(-110, 0, 0))
	_spawn_patrol("FarPatrol", m.global_position + Vector3(-640, 0, 40))
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("    the squad stands at %s (%d hostiles in the zone, %d hostile squads)" % [spot, _hostiles().size(), _squads().size()])
	await _test_hidden(post)
	await _test_footsteps()
	await _test_seen(post)
	_test_heard()
	_test_drone()


## Two hostiles holding at `at` as a squad of their own.
func _spawn_patrol(label: String, at: Vector3) -> void:
	var sq := Squad.new()
	sq.name = label
	sq.faction = &"hostile"
	sq.patrol = []
	level.add_child(sq)
	for k in 2:
		var s := level.spawn_soldier({"name": "%s%d" % [label, k], "faction": "hostile", "variant": "urban",
			"pos": level.ground_point(at + Vector3(k * 3.0, 0, 0)), "loadout": ["akm", "mag_762"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).squad = sq


## A spot outside the compound's wall where four men in a row along it are out of every line from
## inside: eyes 1.7 m up on a 3 m grid over the courtyard and 4.8 m up on the two towers, to each
## man's shins, waist and chest (SquadAI.can_see looks at the chest). [spot, along] or null. The east wall first, away from the towers.
func _hidden_spot() -> Variant:
	var eyes: Array[Vector3] = []
	for x in range(-27, 28, 3):
		for z in range(-27, 28, 3):
			eyes.append(m.to_global(Vector3(x, 1.7, z)))
	for t: Vector2 in [Vector2(26.5, -26.3), Vector2(-26.3, 26.5)]:
		eyes.append(m.to_global(Vector3(t.x, 4.8, t.y)))
	var world := m.get_world_3d()
	var walls: Array = []  # [local point, local along]
	for z in [0.0, 4.0, -4.0, 8.0, -8.0, 12.0, -12.0]:
		walls.append([Vector3(30.7, 0, z), Vector3(0, 0, 1)])  # (hugging it: from a tower a man's chest 1.8 m out shows over it)
		walls.append([Vector3(-30.7, 0, -z), Vector3(0, 0, 1)])
		walls.append([Vector3(z, 0, -30.7), Vector3(1, 0, 0)])
	for c: Array in walls:
		var at := m.to_global(c[0] as Vector3)
		var dir := (m.to_global(c[1] as Vector3) - m.to_global(Vector3.ZERO)).normalized()
		var clear := true
		for k in 4:
			var feet := level.ground_point(at + dir * (k - 1.5) * 1.2)
			for h: float in [0.3, 0.9, 1.4]:
				for eye in eyes:
					if Throwables.clear_line(world, eye, feet + Vector3.UP * h):
						clear = false
						break
				if not clear:
					break
			if not clear:
				break
		if clear:
			return [at, dir]
	return null


## Every hostile up in the zone.
func _hostiles() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_queued_for_deletion() and SquadAI.of(s):
			out.append(s)
	return out


## Every hostile squad in the zone (each garrison's, each patrol's, ...).
func _squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for h in _hostiles():
		var sq := SquadAI.of(h).squad
		if sq and not out.has(sq):
			out.append(sq)
	return out


func _near_men(p: Vector3, within: float) -> bool:
	return men.any(func(f: Soldier) -> bool: return Vector2(f.global_position.x - p.x, f.global_position.z - p.z).length() <= within)


## What hostile `h` knows of the squad behind the wall (since `since`), or "" for nothing.
func _knows(h: Soldier, since: float) -> String:
	var ai := SquadAI.of(h)
	for f in men:
		var id := f.get_instance_id()
		if float(ai._aware.get(id, 0.0)) > 0.0:
			return "%s is %.2f aware of %s" % [h.name, float(ai._aware[id]), f.name]
		if ai.target == f:
			return "%s has %s as his target" % [h.name, f.name]
	if ai._suspect_at > since and _near_men(ai._suspect_pos, NEAR_M):
		return "%s suspects someone by them" % h.name
	if h.threat_time > since and _near_men(h.threat_pos, NEAR_M):
		return "%s has a threat by them" % h.name
	return ""


## What hostile squad `sq` has of the squad in its picture, or "".
func _pictured(sq: Squad) -> String:
	for f in men:
		if sq.known.has(f.get_instance_id()):
			return "%s has %s in its picture" % [sq.name, f.name]
	return ""


func _alert_calm(reports0: int) -> String:
	if not alert._pending.is_empty():
		return "%d reports on the way (%s)" % [alert._pending.size(), alert._pending[0].report]
	if alert.reports.size() > reports0:
		return "a report reached the net (%s)" % alert.reports[-1]
	if alert.zone_state != Alert.State.NORMAL:
		return "the zone is %s" % Alert.STATE_NAMES[alert.zone_state]
	for k: String in alert.areas:
		if int(alert.areas[k].state) != Alert.State.NORMAL:
			return "%s is %s" % [k, Alert.STATE_NAMES[int(alert.areas[k].state)]]
	return ""


func _test_hidden(post: GarrisonPost) -> void:
	print("Behind the compound's wall, still and quiet")
	var since := Soldier._now()
	var reports0 := alert.reports.size()
	var lines: Array[String] = []
	var learned := ""
	var calm := ""
	var nearest := INF
	var checks := 0
	var deadline := Time.get_ticks_msec() + int(HIDE_S * 1000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		checks += 1
		for h in _hostiles():
			var ai := SquadAI.of(h)
			for f in men:
				if post.members.has(h):
					nearest = minf(nearest, h.global_position.distance_to(f.global_position))
				if ai.body and ai.can_see(f) and lines.size() < 4:
					lines.append("%s -> %s" % [h.name, f.name])
			if learned == "":
				learned = _knows(h, since)
		if learned == "":
			for sq in _squads():
				learned = _pictured(sq)
				if learned != "":
					break
		if calm == "":
			calm = _alert_calm(reports0)
	check(lines.is_empty(), "%d s, %d looks: no hostile had a line to any of them (%s)" % [int(HIDE_S), checks, ", ".join(lines) if not lines.is_empty() else "the nearest of the garrison %.1f m off, through the wall" % nearest])
	check(learned == "", "nobody at the compound or elsewhere in the zone learns of them: no awareness, target, suspicion, threat or squad picture (%s)" % (learned if learned != "" else "%d hostiles in %d squads" % [_hostiles().size(), _squads().size()]))
	check(calm == "", "the alert hears nothing: no report on the way, every area and the zone normal (%s)" % (calm if calm != "" else "calm"))
	check(not post.sprung, "and the garrison's ambush isn't sprung")


## G-29: walking there, he's heard through the wall only as close as footsteps carry through one.
func _test_footsteps() -> void:
	print("Footsteps through the wall")
	var reach := Spotting.STEPS_WALK_M * DayNight.hearing_x()
	var muffled := reach * SquadAI.WALL_STEPS_MULT
	var world := player.get_world_3d()
	player.velocity = along * (Spotting.WALK_MPS + 1.0)  # walking (its physics is off: he stays put)
	var band := {}  # in plain reach but behind the wall: must not hear
	var heard_far: Array[String] = []
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		for h in _hostiles():
			var d := h.global_position.distance_to(player.global_position)
			var lined := Throwables.clear_line(world, h.camera.global_position, player.aim_point())
			if lined or d <= muffled + 0.5:
				continue
			if d <= reach:
				band[h.name] = true
			if float(SquadAI.of(h)._aware.get(player.get_instance_id(), 0.0)) > 0.0 and heard_far.size() < 4:
				heard_far.append("%s at %.1f m" % [h.name, d])
	player.velocity = Vector3.ZERO
	check(heard_far.is_empty(), "walking behind the wall: nobody further than %.1f m hears him through it (%d of the garrison within %.0f m, behind the wall; %s)" \
		% [muffled, band.size(), reach, ", ".join(heard_far) if not heard_far.is_empty() else "none heard"])
	for h in _hostiles():  # (whoever heard him close by forgets, for what follows)
		SquadAI.of(h)._aware.erase(player.get_instance_id())
		if SquadAI.of(h).squad:
			SquadAI.of(h).squad.known.erase(player.get_instance_id())


## One of them seen: the compound stands to; the zone hears of it by radio only.
func _test_seen(post: GarrisonPost) -> void:
	print("Seen: the news goes by radio")
	var site := level.site_squad("compound")
	for h in post.alive():
		SquadAI.of(h).hold_fire = true  # (they see him; nobody needs shooting for this)
	# Just inside the wall, by the others (behind it), where one of the garrison has a line to him.
	var inside := Vector3.INF
	var into := (m.global_position - spot)
	into.y = 0.0
	into = into.normalized()
	var chest := player.aim_point() - player.global_position
	for step: float in [4.0, 6.0, 8.0, 3.0]:
		for side: float in [0.0, 3.0, -3.0, 6.0, -6.0]:
			var p := level.ground_point(spot + into * step + along * side)
			if post.alive().any(func(h: Soldier) -> bool: return Throwables.clear_line(h.get_world_3d(), h.camera.global_position, p + chest)):
				inside = p
				break
		if inside.is_finite():
			break
	check(inside.is_finite(), "a spot just inside the wall in sight of the garrison (%s)" % inside)
	if not inside.is_finite():
		return
	var reports0 := alert.reports.size()
	player.global_position = inside
	var seen := await _wait_for(func() -> bool: return alert._pending.any(func(p: Dictionary) -> bool: return p.report.kind == &"contact"), 20.0)
	var where := player.global_position
	player.global_position = level.ground_point(spot + along * -1.8)  # back behind the wall
	var pending: Array = alert._pending.filter(func(p: Dictionary) -> bool: return p.report.kind == &"contact")
	check(seen and pending.all(func(p: Dictionary) -> bool: return post.members.has(p.by)),
		"in sight, one of the garrison spots him and will radio it in (%s)" % ", ".join(pending.map(func(p: Dictionary) -> String: return String(p.report.by))))
	if pending.is_empty():
		return
	var first: Dictionary = pending[0]
	for p: Dictionary in pending:
		if float(p.due) < float(first.due):
			first = p
	var by: Soldier = first.by
	var base := lerpf(Alert.REPORT_DELAY_S.x, Alert.REPORT_DELAY_S.y, clampf(float(SquadAI.of(by).discipline), 0.0, 1.0))
	var delay := float(first.due) - alert.now()
	check(delay <= base * Alert.REPORT_UNDER_FIRE_MULT + 0.1 and delay >= base - 0.6,
		"his report is on its way: %.0f s (discipline %.2f: %.0f s, x%.1f under fire)" % [delay, float(SquadAI.of(by).discipline), base, Alert.REPORT_UNDER_FIRE_MULT])
	check(int(first.report.get("seen", 0)) == 1, "it counts the one man he saw, not the three behind the wall (seen %d)" % int(first.report.get("seen", 0)))
	var compound_state := alert.state_of("compound")
	var others := alert.areas.keys().filter(func(k: String) -> bool: return k != "compound" and alert.state_of(k) != Alert.State.NORMAL)
	check(compound_state == Alert.State.ENGAGED and alert.zone_state == Alert.State.NORMAL and others.is_empty(),
		"the compound stands to at once (%s); the zone (%s) and every other area (%s) don't know yet" % [Alert.STATE_NAMES[compound_state], Alert.STATE_NAMES[alert.zone_state], others])
	var told := ""
	for sq in _squads():
		if sq != site and _pictured(sq) != "":
			told = _pictured(sq)
	for h in _hostiles():
		if SquadAI.of(h).squad != site and told == "":
			told = _knows(h, -INF)
	check(told == "", "no other squad in the zone knows of him (%s)" % (told if told != "" else "%d other squads" % (_squads().size() - 1)))
	# A contact the net hasn't heard of yet doesn't come in with somebody else's shot (F-361).
	var field := where + Vector3(Alert.AREA_REACH_M + 300.0, 0, 0)
	alert._receive({"kind": &"shot", "pos": field, "area": Alert.FIELD, "by": ""})
	check(alert.zone_state == Alert.State.SUSPICIOUS, "a shot reported meanwhile out in the field: the zone is suspicious, not engaged (%s)" % Alert.STATE_NAMES[alert.zone_state])
	alert.lkp = {}
	alert.advance(maxf(delay - 1.0, 0.0))
	check(alert.reports.filter(func(r: Dictionary) -> bool: return r.kind == &"contact").is_empty() and alert.zone_state < Alert.State.ENGAGED,
		"a second before it's due the net still hasn't heard (zone %s)" % Alert.STATE_NAMES[alert.zone_state])
	alert.advance(1.5)
	var got := alert.reports.filter(func(r: Dictionary) -> bool: return r.kind == &"contact")
	check(not got.is_empty() and String(got[0].by) == String(by.name) and alert.zone_state == Alert.State.ENGAGED and not alert.last_known().is_empty() \
		and (alert.last_known().pos as Vector3).distance_to(where) < 3.0,
		"then it lands: the zone is engaged, its last known position where he was seen (%d reports from %d)" % [alert.reports.size() - reports0, reports0])
	var near_told := 0
	var near_all := 0
	var far_told: Array[String] = []
	for sq in _squads():
		if sq == site:
			continue
		var near := sq.members().any(func(s: Soldier) -> bool: return s.global_position.distance_to(where) <= Alert.NET_SHARE_M)
		var knows := sq.known.has(player.get_instance_id())
		if near:
			near_all += 1
			near_told += 1 if knows else 0
		elif knows:
			far_told.append(String(sq.name))
	check(near_told == near_all and far_told.is_empty(), "the squads within %d m of it are told (%d of %d), none further (%s)" % [int(Alert.NET_SHARE_M), near_told, near_all, far_told])
	# The mast down: the next report takes COMMS_DOWN_MULT longer.
	var other: Soldier = null
	for h in post.alive():
		if h != by:
			other = h
	if other == null:
		return
	alert.comms_down = true
	var under := SquadAI.of(other).in_contact()
	Alert.server_sighting(other, player.global_position)
	var mine: Array = alert._pending.filter(func(p: Dictionary) -> bool: return p.by == other and p.report.kind == &"contact")
	var want := lerpf(Alert.REPORT_DELAY_S.x, Alert.REPORT_DELAY_S.y, clampf(float(SquadAI.of(other).discipline), 0.0, 1.0)) \
		* (Alert.REPORT_UNDER_FIRE_MULT if under else 1.0) * Alert.COMMS_DOWN_MULT
	check(mine.size() == 1 and absf(float(mine[0].due) - alert.now() - want) < 0.1,
		"the mast down, the next report takes x%.0f as long (%.0f s)" % [Alert.COMMS_DOWN_MULT, float(mine[0].due) - alert.now() if mine.size() == 1 else -1.0])
	alert.comms_down = false
	# Cut down before he gets it out, the report dies with him.
	var before := alert.reports.size()
	other.vitals.server_kill()
	alert.advance(want + 1.0)
	check(alert.reports.size() == before and not alert._pending.any(func(p: Dictionary) -> bool: return p.by == other),
		"cut down before he gets it out: the report dies with him")


## F-359: a suppressed shot behind the wall reaches the alert through it only half as far.
func _test_heard() -> void:
	print("A suppressed shot behind the wall")
	alert._pending.clear()
	alert._last_report.clear()
	var world := player.get_world_3d()
	var reach := Alert.SUPPRESSED_HEARD_M
	# Fired from outside the wall where the most of the garrison are within reach but beyond half of
	# it, behind the wall: those must not hear it.
	var at := player.global_position + Vector3.UP * 1.5
	var band: Array[String] = []
	for r: float in [34.0, 40.0, 48.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := level.ground_point(m.to_global(Vector3(cos(a) * r, 0, sin(a) * r))) + Vector3.UP * 1.5
			var here: Array[String] = []
			for h in _hostiles():
				var d := h.global_position.distance_to(p)
				if d <= reach and d > reach * SquadAI.WALL_SHOT_MULT and not Throwables.clear_line(world, p + Vector3.UP * 0.3, h.camera.global_position):
					here.append(String(h.name))
			if here.size() > band.size():
				band = here
				at = p
	player.global_position = at - Vector3.UP * 1.5  # (the shooter: he never hears himself)
	Alert.server_noise(player, at, Alert.SHOT, true)
	var wrong: Array = alert._pending.filter(func(p: Dictionary) -> bool: return band.has(String(p.report.by)))
	check(wrong.is_empty(), "nobody %.0f-%.0f m off with a wall between hears it (%d of them; %d hear it nearer or in the open)" \
		% [reach * SquadAI.WALL_SHOT_MULT, reach, band.size(), alert._pending.size()])
	alert._pending.clear()


## F-362: a recon drone goes where the net last heard of the squad and doesn't see through a roof.
func _test_drone() -> void:
	print("A recon drone overhead")
	var drones := EnemyDrones.of(level)
	check(drones != null, "the zone has the enemy's drones")
	if drones == null:
		return
	for h in _hostiles():
		SquadAI.of(h).process_mode = Node.PROCESS_MODE_DISABLED  # the garrison out of it: only the drone looks
	# All four under the command building's roof, away from its door.
	var inside: Array[Vector3] = [Vector3(3.5, 0, -10.5), Vector3(-3.5, 0, -10.5), Vector3(3.5, 0, -9.0), Vector3(-3.5, 0, -9.0)]
	for k in men.size():
		men[k].global_position = m.to_global(inside[k] + Vector3.UP * 0.05)
	var house := m.to_global(Vector3(0, 0, -8))
	alert.lkp = {"pos": house, "time": alert.now()}
	var reports := alert.reports.size()
	var id := drones.server_launch(m.global_position + Vector3(200, 0, 0))
	for k in 60:
		drones.server_fly(id, 1.0)
	var d: Dictionary = drones.drones[id]
	var over := Vector2(d.pos.x - house.x, d.pos.z - house.z).length()
	check(over <= EnemyDrones.ORBIT_M + 20.0 and alert.reports.size() == reports,
		"over the building where the net last heard of them (%.0f m), it sees nobody under the roof (%d reports)" % [over, alert.reports.size() - reports])
	player.global_position = level.ground_point(m.to_global(Vector3(0, 0, 6)))  # out into the courtyard
	for k in 5:
		drones.server_fly(id, 1.0)
	var got := alert.reports.slice(reports)
	check(not got.is_empty() and String(got[-1].by) == "drone" and int(got[-1].get("seen", 0)) == 1,
		"one steps out into the open: it reports him, one man seen (%s)" % (got[-1] if not got.is_empty() else "none"))
	drones.drones.erase(id)
	# Told of them somewhere else, it searches there, not over the squad (back under the roof: a
	# drone passing over that saw him would rightly stay with him).
	player.global_position = m.to_global(inside[0] + Vector3.UP * 0.05)
	var away := level.ground_point(m.global_position + Vector3(350, 0, 350))
	alert.lkp = {"pos": away, "time": alert.now()}
	var id2 := drones.server_launch(m.global_position + Vector3(-200, 0, 0))
	for k in 60:
		drones.server_fly(id2, 1.0)
	var d2: Dictionary = drones.drones[id2]
	var to_lkp := Vector2(d2.pos.x - away.x, d2.pos.z - away.z).length()
	var to_squad := Vector2(d2.pos.x - player.global_position.x, d2.pos.z - player.global_position.z).length()
	check(to_lkp <= EnemyDrones.ORBIT_M + 20.0 and to_squad > EnemyDrones.SEE_M,
		"sent with a last known position 500 m off, it circles there (%.0f m from it), not over the squad (%.0f m)" % [to_lkp, to_squad])
	drones.drones.erase(id2)


func _finish() -> void:
	print("AWARENESS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	GameState.delete_save()
	get_tree().quit(failures)
