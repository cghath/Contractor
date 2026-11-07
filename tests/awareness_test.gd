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
## - Engines (F-365, Captain 2026-10-31: "engines are heard"): an M-ATV idling outside the wall is
##   heard from EngineNoise's reach in the open, not beyond it, and through the wall only within
##   half of it; a helicopter flying is heard from its own (longer) reach. The listener suspects
##   something over there and the alert gets an "engine" report; nobody learns who rides in it. A
##   vehicle sounds by itself every EMIT_S; nobody hears his own side's engine or the one he rides in.
## - Waves (F-365): reinforcements without an aim of their own go for the alert's last known
##   position, not the squad, and search the middle of the map before there is one.
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
	await _test_engines()
	_test_waves()
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
## The garrison stands further off than plain footstep reach (R0767: none within 12 m), so a
## listener of the test's own (a hostile in a squad of his own, standing still) is put just inside
## the wall: first in plain reach but beyond the muffled one, where he must not hear him; then
## within the muffled reach, where he must. So the check fails with the muffle gone, and with
## footsteps never carrying through a wall.
func _test_footsteps() -> void:
	print("Footsteps through the wall")
	var reach := Spotting.STEPS_WALK_M * DayNight.hearing_x()
	var muffled := reach * SquadAI.WALL_STEPS_MULT
	var world := player.get_world_3d()
	var sq := Squad.new()
	sq.name = "Listener"
	sq.faction = &"hostile"
	sq.patrol = []
	level.add_child(sq)
	var ear := level.spawn_soldier({"name": "Listener0", "faction": "hostile", "variant": "urban",
		"pos": level.ground_point(m.global_position), "loadout": ["akm", "mag_762"], "combat": 0.5, "discipline": 0.5, "guard": true})
	ear.set_physics_process(false)  # he stands where he's put
	var ear_ai := SquadAI.of(ear)
	ear_ai.squad = sq
	ear_ai.hold_fire = true
	await get_tree().physics_frame
	var far: Variant = await _place_behind_wall(ear, muffled + 1.2, reach - 1.2)
	check(far != null, "a listener inside the wall, %.1f-%.1f m from him, with no line to him (%s m)" % [muffled + 1.2, reach - 1.2, far])
	player.velocity = along * (Spotting.WALK_MPS + 1.0)  # walking (its physics is off: he stays put)
	var band := {}  # in plain reach but behind the wall: must not hear
	var heard_far: Array[String] = []
	var deadline := Time.get_ticks_msec() + 6000
	while far != null and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		for h in _hostiles():
			var d := h.global_position.distance_to(player.global_position)
			var lined := Throwables.clear_line(world, h.camera.global_position, player.aim_point()) or SquadAI.of(h).can_see(player)
			if lined or d <= muffled + 0.5:
				continue
			if d <= reach:
				band[h.name] = true
			if float(SquadAI.of(h)._aware.get(player.get_instance_id(), 0.0)) > 0.0 and heard_far.size() < 4:
				heard_far.append("%s at %.1f m" % [h.name, d])
	check(band.has(ear.name) and heard_far.is_empty(), "walking behind the wall: nobody further than %.1f m hears him through it (%d within %.1f-%.0f m of him, behind the wall: %s; %s)" \
		% [muffled, band.size(), muffled, reach, ", ".join(band.keys()), ", ".join(heard_far) if not heard_far.is_empty() else "none heard"])
	var near: Variant = await _place_behind_wall(ear, 1.5, muffled - 1.0)
	var heard := false
	if near != null:
		heard = await _wait_for(func() -> bool: return float(ear_ai._aware.get(player.get_instance_id(), 0.0)) > 0.0, 6.0)
	check(near != null and heard, "but within %.1f m, still behind the wall, he's heard (the listener %s m off, %s)" \
		% [muffled, near, "heard him" if heard else "heard nothing"])
	player.velocity = Vector3.ZERO
	ear.queue_free()
	sq.queue_free()
	await get_tree().physics_frame
	for h in _hostiles():  # (whoever heard him close by forgets, for what follows)
		SquadAI.of(h)._aware.erase(player.get_instance_id())
		if SquadAI.of(h).squad:
			SquadAI.of(h).squad.known.erase(player.get_instance_id())


## Puts `h` just inside the compound's wall, `lo`-`hi` m from the player, on level ground with the
## wall between them (no clear ray eye to chest, and SquadAI.can_see says no). How far off he
## ended up, or null.
func _place_behind_wall(h: Soldier, lo: float, hi: float) -> Variant:
	var into := m.global_position - spot
	into.y = 0.0
	into = into.normalized()
	var world := h.get_world_3d()
	var ai := SquadAI.of(h)
	for step: float in [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 2.0]:
		for side: float in [0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0]:
			var p := level.ground_point(player.global_position + into * step + along * side)
			var d := p.distance_to(player.global_position)
			if d < lo or d > hi or absf(p.y - player.global_position.y) > 0.8:
				continue
			h.global_position = p
			h.velocity = Vector3.ZERO
			await get_tree().physics_frame
			if not Throwables.clear_line(world, h.camera.global_position, player.aim_point()) and not ai.can_see(player):
				ai._aware.erase(player.get_instance_id())
				return snappedf(h.global_position.distance_to(player.global_position), 0.1)
	return null


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
	# The positive control: with all of them half spotted he counts them all (so "seen 1" above isn't
	# just the floor of one with everyone filtered out).
	var by_ai := SquadAI.of(by)
	var kept_aware: Dictionary = by_ai._aware.duplicate()
	var near_spot := men.filter(func(f: Soldier) -> bool: return f.vitals.is_up() and f.global_position.distance_to(where) <= Alert.SEEN_GROUP_M)
	for f: Soldier in men:
		by_ai._aware[f.get_instance_id()] = Spotting.SUSPECT
	var all_seen := int(alert._seen_at(where, by).get("seen", 0))
	by_ai._aware = kept_aware
	check(near_spot.size() >= 2 and all_seen == near_spot.size(), "and with all of them half spotted he counts all %d (seen %d)" % [near_spot.size(), all_seen])
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
	check(near_all > 0 and near_told == near_all and far_told.is_empty(), "the squads within %d m of it are told (%d of %d), none further (%s)" % [int(Alert.NET_SHARE_M), near_told, near_all, far_told])
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
	# Positive controls: everyone within half the reach, or within it with a clear line, does hear it;
	# and one of them 8 m from a second shot certainly does.
	var hearers: Array[String] = []
	for h in _hostiles():
		var d := h.global_position.distance_to(at)
		if d <= reach * SquadAI.WALL_SHOT_MULT or (d <= reach and Throwables.clear_line(world, at + Vector3.UP * 0.3, h.camera.global_position)):
			hearers.append(String(h.name))
	var deaf := hearers.filter(func(n: String) -> bool: return not alert._pending.any(func(p: Dictionary) -> bool: return String(p.report.by) == n))
	check(deaf.is_empty(), "those within %.0f m of it, or within %.0f m with a clear line, hear it (%d of %d; %s)" \
		% [reach * SquadAI.WALL_SHOT_MULT, reach, hearers.size() - deaf.size(), hearers.size(), ", ".join(deaf) if not deaf.is_empty() else "all"])
	alert._pending.clear()
	alert._last_report.clear()
	var h0: Soldier = _hostiles()[0] if not _hostiles().is_empty() else null
	if h0:
		Alert.server_noise(player, h0.global_position + Vector3(8.0, 1.5, 0.0), Alert.SHOT, true)
	check(h0 != null and alert._pending.any(func(p: Dictionary) -> bool: return p.by == h0 and p.report.kind == Alert.SHOT),
		"and %s, 8 m from a second one, hears it and will report it" % (h0.name if h0 else "a hostile"))
	alert._pending.clear()
	alert._last_report.clear()


## F-365 part 2 (Captain, 2026-10-31: "engines are heard"): an M-ATV with a driver in, idling just
## outside the wall, and a helicopter flying. A listener of the test's own (a hostile in a squad of
## his own, standing still) hears the M-ATV within EngineNoise's idle reach in the open and not
## beyond it, and through the wall only within half of it (SquadAI.WALL_SHOT_MULT, as a shot); he
## hears the helicopter flying from further off than it carries idling on the ground. A heard
## engine is a suspicion over there and an "engine" report to the alert, roughly placed; nobody's
## awareness of anyone rises. The vehicles' own physics is off (frozen, no _server_step), so only
## the test's EngineNoise.server_emit calls sound them, until the M-ATV's physics is turned on to
## show it sounds by itself (Vehicle._server_step, every EMIT_S). Each quiet gap is one listener's
## and one engine's (a helicopter shut out by a wall doesn't silence a truck beside him). With a
## hostile at the wheel, the hostile listener doesn't hear it, the squad's AI does, and one of the
## squad riding in it doesn't.
func _test_engines() -> void:
	print("Engines heard")
	var layer := VehicleLayer.of(level)
	check(layer != null, "the zone has its vehicle layer")
	if layer == null:
		return
	var into := m.global_position - spot
	into.y = 0.0
	into = into.normalized()
	var at := level.ground_point(spot - into * 6.0)
	var matv := layer.server_spawn("matv", Transform3D(Basis.looking_at(along, Vector3.UP), at + Vector3.UP * 0.4), "", &"player", "aw_matv")
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), m.global_position + Vector3(0, 200, 0)), "", &"player", "aw_heli") as Helicopter
	var driver := level.spawn_soldier({"name": "AwDriver", "faction": "friendly", "variant": "woodland", "pos": at + Vector3(0, 0.2, 3.0), "loadout": [],
		"combat": 0.5, "discipline": 0.5, "guard": false})
	var sq := Squad.new()
	sq.name = "EngineEar"
	sq.faction = &"hostile"
	sq.patrol = []
	level.add_child(sq)
	var ear := level.spawn_soldier({"name": "EngineEar0", "faction": "hostile", "variant": "urban",
		"pos": level.ground_point(m.global_position), "loadout": ["akm", "mag_762"], "combat": 0.5, "discipline": 0.5, "guard": true})
	check(matv != null and heli != null and driver != null and ear != null, "an M-ATV outside the wall, a UH-60, a driver and a listener")
	if matv == null or heli == null or driver == null or ear == null:
		for n: Node in [matv, heli, driver, ear, sq]:
			if is_instance_valid(n):
				n.queue_free()
		return
	for v: Vehicle in [matv, heli]:
		v.set_physics_process(false)  # (no _server_step: only the test sounds it)
		v.freeze = true
	ear.set_physics_process(false)
	var ear_ai := SquadAI.of(ear)
	ear_ai.squad = sq
	ear_ai.process_mode = Node.PROCESS_MODE_DISABLED  # (his eyes off: what he learns here is by ear only)
	if SquadAI.of(driver):
		SquadAI.of(driver).process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	var silent := EngineNoise.reach_of(matv)
	var seated := matv.server_enter(driver, matv.driver_seat())
	await get_tree().physics_frame
	var idle := EngineNoise.reach_of(matv)
	var want := EngineNoise.reach(Vehicle.WHEELED, false)
	check(silent == 0.0 and seated and idle == want and EngineNoise.reach(Vehicle.WHEELED, true) > idle,
		"nobody at the wheel it's silent (%.0f m); a driver in, standing, it idles: heard to %.0f m (%.0f m under way)" % [silent, idle, EngineNoise.reach(Vehicle.WHEELED, true)])
	var src := matv.global_position + Vector3.UP * EngineNoise.SOURCE_UP_M
	var world := matv.get_world_3d()
	var muffled := want * SquadAI.WALL_SHOT_MULT
	# In the open, away from the compound: within the reach heard, beyond it not.
	var open_near: Variant = await _place_ear(ear, src, -into, want * 0.6, want - 3.0, true)
	var got := _emit(matv, ear)
	check(open_near != null and got.heard and got.report, "in the open, %s m from it with a clear line, he hears it and will report an engine" % open_near)
	if got.heard:
		var flat := Vector2(ear_ai._suspect_pos.x - src.x, ear_ai._suspect_pos.z - src.z).length()
		var d := ear.global_position.distance_to(src)
		check(flat <= EngineNoise.ERROR_PER_100M * d / 100.0 + 0.5 and ear_ai._aware.is_empty() and sq.known.is_empty(),
			"a suspicion over there (%.1f m from it, at most %.1f), no awareness of anyone (%d) and nobody in his squad's picture (%d)" \
			% [flat, EngineNoise.ERROR_PER_100M * d / 100.0, ear_ai._aware.size(), sq.known.size()])
	var open_far: Variant = await _place_ear(ear, src, -into, want + 3.0, want + 15.0, true)
	got = _emit(matv, ear)
	check(open_far != null and not got.heard and not got.report, "beyond its reach (%s m) he doesn't" % open_far)
	# Behind the wall: past half the reach not heard, within it heard.
	var walled_far: Variant = await _place_ear(ear, src, into, muffled + 1.5, want - 1.5, false)
	got = _emit(matv, ear)
	check(walled_far != null and not got.heard and not got.report,
		"inside the wall %s m from it (%.0f-%.0f m), no line to it: he doesn't hear it through the wall" % [walled_far, muffled, want])
	var walled_near: Variant = await _place_ear(ear, src, into, 6.0, muffled - 1.5, false)
	got = _emit(matv, ear)
	check(walled_near != null and got.heard and got.report, "within %.0f m (%s m), still behind the wall, he does" % [muffled, walled_near])
	# The helicopter: flying it carries further than it does idling on the ground.
	ear.global_position = level.ground_point(m.to_global(Vector3(0, 0, 6)))  # (out in the courtyard)
	var flying := EngineNoise.reach(Vehicle.HELICOPTER, true)
	var landed := EngineNoise.reach(Vehicle.HELICOPTER, false)
	var off := (flying + landed) * 0.5
	var eye := ear.camera.global_position
	var high := Vector3.INF
	for k in 12:
		var a := TAU * k / 12.0
		var p := eye + Vector3(cos(a) * off, 0.0, sin(a) * off)
		p.y = level.ground_point(p).y + 150.0
		if Throwables.clear_line(world, p + Vector3.UP * EngineNoise.SOURCE_UP_M, eye):
			high = p
			break
	check(high.is_finite(), "a spot %.0f m off, 150 m up, with a clear line down to him" % off)
	if high.is_finite():
		heli.global_position = high
		heli._rpm = Helicopter.ROTOR_RPM
		heli.mode = Helicopter.Mode.FLYING
		var fly_reach := EngineNoise.reach_of(heli)
		got = _emit(heli, ear)
		var under := Vector2(ear_ai._suspect_pos.x - high.x, ear_ai._suspect_pos.z - high.z).length()
		var bound := EngineNoise.ERROR_PER_100M * ear.global_position.distance_to(high + Vector3.UP * EngineNoise.SOURCE_UP_M) / 100.0 + 0.5
		check(fly_reach == flying and got.heard and got.report and under <= bound,
			"a helicopter flying %.0f m off (it carries %.0f m) is heard, placed under it (%.0f m off)" % [ear.global_position.distance_to(high), fly_reach, under])
		heli.mode = Helicopter.Mode.LANDED
		var land_reach := EngineNoise.reach_of(heli)
		got = _emit(heli, ear)
		check(land_reach == landed and not got.heard and not got.report,
			"the same one with its rotors turning on the ground (%.0f m) isn't, from there" % land_reach)
		heli.mode = Helicopter.Mode.PARKED
		heli._rpm = 0.0
	# The alert's last known position: a heard engine moves it only when nothing harder is fresh.
	var hard := level.ground_point(m.global_position + Vector3(0, 0, 90))
	alert.lkp = {"pos": hard, "time": alert.now()}
	alert._receive({"kind": Alert.ENGINE, "pos": src, "area": alert.area_of(src), "by": "test"})
	var kept: Vector3 = alert.lkp.pos
	alert.lkp.time = alert.now() - Alert.ENGINE_LKP_AFTER_S - 1.0
	alert._receive({"kind": Alert.ENGINE, "pos": src, "area": alert.area_of(src), "by": "test"})
	check(kept.distance_to(hard) < 0.01 and (alert.lkp.pos as Vector3).distance_to(src) < 0.01,
		"an engine report leaves a fresh last known position where it was, and moves one older than %.0f s" % Alert.ENGINE_LKP_AFTER_S)
	# Engine after engine with nothing harder in between (a helicopter flying in): each newer one
	# moves it; a shot then outranks them, and the next engine report leaves the shot's fix.
	alert.lkp = {}
	var first := level.ground_point(m.global_position + Vector3(70, 0, 40))
	alert._receive({"kind": Alert.ENGINE, "pos": first, "area": alert.area_of(first), "by": "test"})
	var at_first: Vector3 = alert.lkp.pos
	alert.lkp.time = alert.now() - 5.0
	alert._receive({"kind": Alert.ENGINE, "pos": src, "area": alert.area_of(src), "by": "test"})
	var at_second: Vector3 = alert.lkp.pos
	alert._receive({"kind": &"shot", "pos": hard, "area": alert.area_of(hard), "by": "test"})
	alert.lkp.time = alert.now() - 5.0
	alert._receive({"kind": Alert.ENGINE, "pos": first, "area": alert.area_of(first), "by": "test"})
	check(at_first.distance_to(first) < 0.01 and at_second.distance_to(src) < 0.01
			and (alert.lkp.pos as Vector3).distance_to(hard) < 0.01,
		"a second engine report 5 s later moves an engine's fix (%.0f m), but not a shot's 5 s old (%.0f m off it)"
			% [at_first.distance_to(at_second), (alert.lkp.pos as Vector3).distance_to(hard)])
	alert.lkp = {}
	alert._pending.clear()
	alert._last_report.clear()
	# On its own clock: its physics on (still frozen in place), Vehicle._server_step sounds it
	# every EMIT_S, and a hostile in the open near it hears it without the test's server_emit.
	var self_near: Variant = await _place_ear(ear, src, -into, 8.0, muffled - 1.0, true)
	EngineNoise._quiet_until.clear()
	ear_ai._suspect_at = -1000.0
	matv.set_physics_process(true)
	var waited := 0.0
	var give_up := Time.get_ticks_msec() + int((EngineNoise.EMIT_S + 5.0) * 1000)
	while ear_ai._suspect_at <= -1000.0 and waited < EngineNoise.EMIT_S + 0.5 and Time.get_ticks_msec() < give_up:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	matv.set_physics_process(false)
	var by_ear := Vector2(ear_ai._suspect_pos.x - src.x, ear_ai._suspect_pos.z - src.z).length()
	var ear_d := ear.global_position.distance_to(src)
	check(self_near != null and ear_ai._suspect_at > -1000.0 and by_ear <= EngineNoise.ERROR_PER_100M * ear_d / 100.0 + 0.5,
		"its physics on, it sounds by itself: %s m off, he hears it %.2f s in (every %.0f s), %.1f m from it" \
		% [self_near, waited, EngineNoise.EMIT_S, by_ear])
	# Each quiet gap is the listener's and that one engine's: a helicopter flying past its muffled
	# reach with the compound between it and him shuts him out (server_emit sets his RECHECK_S gap
	# itself), and he still hears the M-ATV idling beside him. Keyed per listener only, that gap
	# would silence the M-ATV too.
	EngineNoise._quiet_until.clear()
	var heli_muffled := flying * SquadAI.WALL_SHOT_MULT
	var hidden := Vector3.INF
	var ear_eye := ear.camera.global_position
	for far_m: float in [heli_muffled + 40.0, heli_muffled + 100.0, heli_muffled + 160.0, flying - 60.0]:
		for side: float in [0.0, 15.0, -15.0, 30.0, -30.0]:
			var p := src + into * far_m + along * side
			p.y = level.ground_point(p).y + 3.0
			var d := ear.global_position.distance_to(p + Vector3.UP * EngineNoise.SOURCE_UP_M)
			if d > heli_muffled + 5.0 and d < flying - 5.0 \
					and not Throwables.clear_line(world, p + Vector3.UP * EngineNoise.SOURCE_UP_M, ear_eye):
				hidden = p
				break
		if hidden.is_finite():
			break
	var heli_gap := -INF
	var heli_heard := true
	if hidden.is_finite():
		heli.global_position = hidden
		heli._rpm = Helicopter.ROTOR_RPM
		heli.mode = Helicopter.Mode.FLYING
		var others := {}  # (everyone else left alone: the zone's men don't hear it, nor use up its MAX_RAYS before him)
		for n in get_tree().get_nodes_in_group(&"combatants"):
			if n != ear:
				others[n.get_instance_id()] = Soldier._now() + 60.0
		EngineNoise._quiet_until[heli.get_instance_id()] = others
		ear_ai._suspect_at = -1000.0
		heli_heard = EngineNoise.server_emit(heli).has(ear) or ear_ai._suspect_at > -1000.0
		var heli_quiet: Dictionary = EngineNoise._quiet_until.get(heli.get_instance_id(), {})
		heli_gap = float(heli_quiet.get(ear.get_instance_id(), -INF)) - Soldier._now()
		heli.mode = Helicopter.Mode.PARKED
		heli._rpm = 0.0
	check(hidden.is_finite() and not heli_heard and heli_gap > 0.0,
		"a helicopter flying %.0f m off (past %.0f m), the compound between: he doesn't hear it and it leaves him alone %.1f s" \
		% [ear.global_position.distance_to(hidden) if hidden.is_finite() else -1.0, heli_muffled, heli_gap])
	ear_ai._suspect_at = -1000.0
	check(heli_gap > 0.0 and EngineNoise.server_emit(matv).has(ear) and ear_ai._suspect_at > -1000.0,
		"that gap doesn't keep him from hearing the M-ATV %.0f m off" % ear_d)
	alert._pending.clear()
	alert._last_report.clear()
	# Sides: a hostile at the wheel makes it a hostile engine. The hostile listener doesn't hear his
	# own side's; one of the squad's AI by the wall does; one of the squad riding in the back
	# doesn't hear the vehicle he rides in.
	matv.server_exit(driver)
	driver.queue_free()  # (not left standing out there)
	var hdriver := level.spawn_soldier({"name": "AwHostileDriver", "faction": "hostile", "variant": "urban", "pos": at + Vector3(0, 0.2, -3.0),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	var rider := level.spawn_soldier({"name": "AwRider", "faction": "friendly", "variant": "woodland", "pos": at + Vector3(0, 0.2, 3.0),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": false})
	for s: Soldier in [hdriver, rider]:
		if s and SquadAI.of(s):
			SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # (as the other test actors: only server_emit moves them)
	var back := -1
	for k in matv.seat_count():
		if matv.seat_kind(k) == Vehicle.PASSENGER:
			back = k
			break
	var mate: Soldier = null  # one of the squad's AI standing by the wall
	for f: Soldier in men:
		if f != player and f.vitals.is_up():
			mate = f
			break
	var aboard := hdriver != null and rider != null and back >= 0 and matv.server_enter(hdriver, matv.driver_seat()) \
		and matv.server_enter(rider, back)
	await get_tree().physics_frame
	var mate_ai := SquadAI.of(mate) if mate else null
	var kept_at := mate_ai._suspect_at if mate_ai else 0.0
	var kept_pos := mate_ai._suspect_pos if mate_ai else Vector3.ZERO
	EngineNoise._quiet_until.clear()
	for s: Soldier in [ear, mate, rider]:
		if s and SquadAI.of(s):
			SquadAI.of(s)._suspect_at = -1000.0
	var hostile_side := EngineNoise.side_of(matv)
	var hostile_reach := EngineNoise.reach_of(matv)
	var heard_by: Array[Soldier] = EngineNoise.server_emit(matv) if aboard else ([] as Array[Soldier])
	var mate_d := mate.global_position.distance_to(src) if mate else INF
	var rider_d := rider.global_position.distance_to(src) if rider else INF
	check(aboard and hostile_side == &"hostile" and hostile_reach > 0.0,
		"a hostile at its wheel, one of the squad in the back: a hostile engine (%s, %.0f m)" % [hostile_side, hostile_reach])
	check(aboard and not heard_by.has(ear) and ear_ai._suspect_at <= -1000.0,
		"the hostile %.0f m off doesn't hear his own side's engine" % ear.global_position.distance_to(src))
	check(aboard and mate_ai != null and mate_d <= hostile_reach and heard_by.has(mate) and mate_ai._suspect_at > -1000.0,
		"%s of the squad, %.0f m off by the wall, hears it" % [mate.name if mate else "nobody", mate_d])
	check(aboard and rider_d <= hostile_reach and not heard_by.has(rider) and SquadAI.of(rider)._suspect_at <= -1000.0,
		"the one riding in it (%.0f m from its engine) doesn't" % rider_d)
	if mate_ai:
		mate_ai._suspect_at = kept_at
		mate_ai._suspect_pos = kept_pos
	for s: Soldier in [hdriver, rider]:
		if s and Vehicle.ride_of(s) == matv:
			matv.server_exit(s)
	await get_tree().physics_frame
	for n: Node in [matv, heli, hdriver, rider, ear, sq]:
		if is_instance_valid(n):
			n.queue_free()
	EngineNoise._quiet_until.clear()
	await get_tree().physics_frame


## One emission of `v`'s engine, fresh (nobody's rehear gap, no report on the way): whether `ear`
## heard it ({"heard"}) and whether he'll report it to the alert ({"report"}).
func _emit(v: Vehicle, ear: Soldier) -> Dictionary:
	EngineNoise._quiet_until.clear()
	alert._pending.clear()
	alert._last_report.clear()
	SquadAI.of(ear)._suspect_at = -1000.0
	var heard := EngineNoise.server_emit(v).has(ear) and SquadAI.of(ear)._suspect_at > -1000.0
	var report := alert._pending.any(func(p: Dictionary) -> bool: return p.by == ear and p.report.kind == Alert.ENGINE)
	return {"heard": heard, "report": report}


## Puts `h` `lo`-`hi` m (feet to `src`) out from `src` along `dir` (and a little to the sides):
## `open` with a clear line from `src` to his ears, else with none. How far off he ended up, or null.
func _place_ear(h: Soldier, src: Vector3, dir: Vector3, lo: float, hi: float, open: bool) -> Variant:
	var world := h.get_world_3d()
	var step := lo
	while step <= hi + 0.01:
		for side: float in [0.0, 3.0, -3.0, 6.0, -6.0]:
			var p := level.ground_point(src + dir * step + along * side)
			var d := p.distance_to(src)
			if d < lo or d > hi:
				continue
			h.global_position = p
			h.velocity = Vector3.ZERO
			await get_tree().physics_frame
			if Throwables.clear_line(world, src, h.camera.global_position) == open:
				return snappedf(h.global_position.distance_to(src), 0.1)
		step += 2.0
	return null


## F-365 part 1 (Captain, 2026-10-31): waves hunt where the enemy last knew the squad to be. The
## zone's reinforcements with no aim of their own (as a zone whose timer sends its waves would be)
## head for the alert's last known position, not the squad; with none yet they walk in to the
## middle of the map and search round it; with EnemyResponse's aim (hot zones) and nothing known a
## wave still keeps the route it has.
func _test_waves() -> void:
	print("Reinforcement waves go for the last known position")
	var r := MapNodes.reinforcements(level)
	check(r != null, "the zone has its reinforcements")
	if r == null:
		return
	var kept_aim := r.aim
	var kept_driven := r.driven
	r.aim = Callable()
	r.driven = false
	var sq := Squad.new()
	sq.name = "TestWave"
	sq.faction = &"hostile"
	sq.patrol = []
	level.add_child(sq)
	var from := level.ground_point(m.global_position + Vector3(400, 0, -300))
	var lk := level.ground_point(m.global_position + Vector3(-250, 0, 150))
	alert.lkp = {"pos": lk, "time": alert.now()}
	r._route(sq, level, from)
	var c: Vector3 = sq.patrol[1] if sq.patrol.size() >= 2 else Vector3.INF
	var to_lk := Vector2(c.x - lk.x, c.z - lk.z).length()
	var to_squad := Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
	check(to_lk < 3.0 and to_squad > 100.0, "with a last known position its route leads there (%.1f m from it), not to the squad (%.0f m from them)" % [to_lk, to_squad])
	alert.lkp = {}
	r._route(sq, level, from)
	var mid := level.map_area().get_center()
	c = sq.patrol[1] if sq.patrol.size() >= 3 else Vector3.INF
	var to_mid := Vector2(c.x - mid.x, c.z - mid.y).length()
	var ring := Vector2(sq.patrol[2].x - c.x, sq.patrol[2].z - c.z).length() if sq.patrol.size() >= 3 else 0.0
	check(to_mid < 3.0 and ring > Reinforcements.SEARCH_RING_M - 3.0,
		"with none yet it walks in to the middle of the map (%.1f m from it) and searches %.0f m round it (the squad %.0f m from there)" \
		% [to_mid, ring, Vector2(mid.x - player.global_position.x, mid.y - player.global_position.z).length()])
	r.aim = kept_aim
	r.driven = kept_driven
	var before: Array[Vector3] = sq.patrol.duplicate()
	r._route(sq, level, from)
	check(r.aim.is_valid() and sq.patrol == before, "with the zone's own aim (EnemyResponse) and nothing known, a wave keeps the route it has")
	sq.queue_free()


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
	drones._free_body(drones.drones[id])
	drones.drones.erase(id)
	# Told of them somewhere else, it searches there, not over the squad (back under the roof: a
	# drone passing over that saw him would rightly stay with him, so it comes up beyond that spot).
	# The spot is well away from the rest of the squad, parked out in the open at (300, 300+): it
	# was 65 m from them, the drone rightly found them there and circled them, and how near the spot
	# that left it hung on the orbit's angle (CI run 41219512393: 126 m, a fail; R0767: 44 m).
	player.global_position = m.to_global(inside[0] + Vector3.UP * 0.05)
	var away := level.ground_point(m.global_position + Vector3(-350, 0, 350))
	alert.lkp = {"pos": away, "time": alert.now()}
	var id2 := drones.server_launch(m.global_position + Vector3(-600, 0, 350))
	var saw := false
	for k in 60:
		drones.server_fly(id2, 1.0)
		saw = saw or not (drones.drones[id2].get("seen", []) as Array).is_empty()
	var d2: Dictionary = drones.drones[id2]
	var to_lkp := Vector2(d2.pos.x - away.x, d2.pos.z - away.z).length()
	var to_squad := Vector2(d2.pos.x - player.global_position.x, d2.pos.z - player.global_position.z).length()
	check(to_lkp <= EnemyDrones.ORBIT_M + 20.0 and to_squad > EnemyDrones.SEE_M and not saw,
		"sent with a last known position 500 m off, it circles there (%.0f m from it), not over the squad (%.0f m; saw them: %s)" % [to_lkp, to_squad, saw])
	drones._free_body(drones.drones[id2])
	drones.drones.erase(id2)


func _finish() -> void:
	print("AWARENESS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	GameState.delete_save()
	get_tree().quit(failures)
