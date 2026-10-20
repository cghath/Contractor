extends Node
## Headless checks for AI virtualization (docs/virtualization.md; Virtualizer): a group far from
## everyone goes into a profile and comes back exactly as it was (men, kit, rounds, wounds, skill,
## orders, metas); a profile walks its route at its pace and takes its owner's new orders; two
## profiles at war fight off-screen and leave real bodies; nothing comes back where a player can
## see it (except inside FORCE_M); the high command, the spawn budget, the alert's check-ins and
## the garrison counts still count virtual men; a garrison goes virtual at its posts when its module
## streams out and comes back with it; and the zone save keeps every profile and gives them back.
##   <voxel godot exe> --headless --path . res://tests/virtualization_test.tscn
## Exits with the number of failures.

const ZONE := "ridge_hot"

var failures := 0
var level: ZoneLevel
var player: Soldier
var v: Virtualizer
var er: EnemyResponse
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_virtualization" + tag  # never touch a real save
	Campaign.campaign_id = "test_virtualization_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false
	Virtualizer.enabled = false  # each check drives it by hand
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		check(false, "the suite finishes in 15 minutes")
		_finish())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	if level == null or not await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0):
		check(false, "the zone hosts with a player")
		_finish()
		return
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place it
	v = Virtualizer.of(level)
	er = EnemyResponse.of(level)
	check(v != null and er != null, "a zone has its virtualizer (and its enemy response)")
	if v == null or er == null:
		_finish()
		return
	v._rng.seed = 12345
	await _frames(10)
	await _test_round_trip()
	await _test_rules()
	await _test_moving()
	await _test_fight()
	await _test_not_in_view()
	await _test_counting()
	await _test_garrison()
	await _test_save()
	await _test_capacity()
	await _test_rides()
	_finish()


func _finish() -> void:
	Virtualizer.enabled = true
	Campaign.reset_campaign()
	GameState.delete_save()
	print("VIRTUALIZATION TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Helpers ----------------------------------------------------------------------------------

## A point on the ground at least `dist` m from the player (flat), inside the zone and outside every
## module: along `angle` (radians), else the next bearing round that fits.
func _away(dist: float, angle := 0.0) -> Vector3:
	var area := level.map_area().grow(-200.0)
	for k in 72:
		var a := angle + TAU * k / 72.0
		var p := player.global_position + Vector3(cos(a), 0.0, sin(a)) * dist
		p.x = clampf(p.x, area.position.x, area.end.x)
		p.z = clampf(p.z, area.position.y, area.end.y)
		if Virtualizer._flat(p, player.global_position) >= dist - 1.0 and level.module_at(p) == null:
			return level.ground_point(p)
	return level.ground_point(Vector3(area.get_center().x, 0.0, area.get_center().y))


## The player at a point far from every module (the middle of the biggest gap), standing.
func _put_player(at: Vector3) -> void:
	player.global_position = level.ground_point(at) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO


## A hostile team of `size` at `at` (EnemyResponse's own spawning), as a tracked record of `kind`.
func _team(size: int, at: Vector3, kind := "hunters", faction := "") -> Dictionary:
	_made += 1
	var squad := er._new_squad("VT%d" % _made)
	var soldiers := er._spawn_team(squad, "VT%d" % _made, size, at, at + Vector3(0, 0, 10), CompoundLevel.HOSTILE_LOADOUT, 0.6, 0.6, "aware")
	if faction != "":
		for s: Soldier in soldiers:
			s.faction = StringName(faction)
		squad.faction = StringName(faction)
	var record := {"squad": squad, "soldiers": soldiers}
	v.track(record, kind, false)
	return record


## What makes a man him, for comparing before and after.
func _sig(s: Soldier) -> Dictionary:
	var brain := SquadAI.of(s)
	return {"name": String(s.name), "person": s.person_name, "nation": s.nation, "body": s.body, "role": String(s.role),
		"gear": JSON.stringify(s.inventory.net_state, "", true), "rounds": s.inventory.rounds_in(&"primary"), "slot": String(s.active_slot),
		"blood": snappedf(s.vitals.blood_fraction(), 0.0001), "wounds": s.vitals.wound_list().size(), "pain": snappedf(s.vitals.pain(), 0.0001),
		"combat": brain.combat if brain else -1.0, "discipline": brain.discipline if brain else -1.0, "nemesis": String(s.get_meta(&"nemesis", "")),
		"buddy": String(s.buddy.name) if is_instance_valid(s.buddy) else ""}


func _sigs(record: Dictionary) -> Array:
	return (record.soldiers as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s)).map(func(s: Variant) -> Dictionary: return _sig(s as Soldier))


## Every man of `record` comes back now.
func _wake(record: Dictionary) -> void:
	v.server_wake(record)
	v.server_flush()
	await _frames(2)


# --- Round trip ---------------------------------------------------------------------------------

func _test_round_trip() -> void:
	print("Live -> virtual -> live: the same men, exactly")
	_put_player(level.insertion_points()[0])
	var at := _away(900.0, 0.5)
	var team := _team(4, at)
	await _frames(3)
	var men: Array = team.soldiers
	# Make them their own: a wound, rounds fired, a named squad's meta, a better shot.
	var hurt := men[1] as Soldier
	hurt.vitals.server_add_wound(Vitals.THIGH_L, "gsw", 0.02)
	hurt.vitals.server_advance(20.0)
	for k in 7:
		(men[0] as Soldier).inventory.consume_round(&"primary")
	(men[3] as Soldier).set_meta(&"nemesis", "test_nemesis")
	SquadAI.of(men[0]).combat = 0.81
	var route: Array[Vector3] = [at + Vector3(40, 0, 0), at + Vector3(40, 0, 40)]
	er._set_route(team.squad, men, route)
	SquadAI.of(men[0])._patrol_index = 1
	SquadAI.of(men[1])._patrol_index = 1
	var before := _sigs(team)
	var spots: Array = men.map(func(s: Variant) -> Vector3: return (s as Soldier).global_position)
	var names: Array = men.map(func(s: Variant) -> String: return String((s as Soldier).name))
	var up_before := Virtualizer.up(team)
	check(v.server_virtualize(team, true) and Virtualizer.is_virtual(team) and (team.soldiers as Array).is_empty(), "a group goes virtual: its record holds a profile and no soldiers")
	await _frames(2)
	check(names.all(func(n: String) -> bool: return level.ai.get_node_or_null(NodePath(n)) == null), "its men have left the world (no nodes: nothing to simulate, draw or send)")
	check(Virtualizer.up(team) == up_before and (team.squad as Node).process_mode == Node.PROCESS_MODE_DISABLED,
		"it still counts %d men up; its squad sleeps meanwhile" % Virtualizer.up(team))
	check(Virtualizer.lead(team).distance_to(spots[0]) < 0.5, "it is where its lead was")
	await _wake(team)
	var after := _sigs(team)
	check(not Virtualizer.is_virtual(team) and after.size() == before.size(), "it comes back: %d of %d men" % [after.size(), before.size()])
	var same := true
	for i in mini(before.size(), after.size()):
		if before[i] != after[i]:
			same = false
			print("    before %s\n    after  %s" % [before[i], after[i]])
	check(same, "each man exactly as he was: name, face, kit, rounds in the gun, the weapon in his hands, wounds, blood, pain, skill, metas, buddy")
	var placed := true
	for i in mini(spots.size(), (team.soldiers as Array).size()):
		placed = placed and ((team.soldiers[i] as Soldier).global_position - (spots[i] as Vector3)).length() < 0.6
	check(placed, "a group that didn't move comes back where each man stood")
	var brains: Array = (team.soldiers as Array).map(func(s: Variant) -> int: return SquadAI.of(s)._patrol_index)
	check(team.soldiers.all(func(s: Variant) -> bool: return SquadAI.of(s).squad == team.squad) and brains[0] == 1,
		"their brains are back in their own squad, on the same leg of the route (%s)" % [brains])
	_drop(team)


## `record`'s men gone for good (the next check starts clean).
func _drop(record: Dictionary) -> void:
	if Virtualizer.is_virtual(record):
		record.erase("virtual")
	for s: Variant in record.get("soldiers", []):
		if is_instance_valid(s):
			(s as Node).queue_free()
	(record.soldiers as Array).clear()
	v.groups = v.groups.filter(func(g: Dictionary) -> bool: return not is_same(g, record))


# --- The rules ---------------------------------------------------------------------------------------

func _test_rules() -> void:
	print("When a group may go virtual")
	_put_player(level.insertion_points()[0])
	var far := _team(2, _away(Virtualizer.DESPAWN_M + 250.0, 1.2))
	var near := _team(2, _away(Virtualizer.DESPAWN_M - 200.0, 2.4))
	await _frames(3)
	var eyes := v._eyes(level)
	check(v.can_virtualize(far.soldiers, eyes, Virtualizer.DESPAWN_M) or v._seen(far.soldiers, eyes), "far out of everyone's way it may go (unless a player has a line to it)")
	check(not v.can_virtualize(near.soldiers, eyes, Virtualizer.DESPAWN_M), "inside DESPAWN_M of a player it stays real")
	var s: Soldier = far.soldiers[0]
	SquadAI.of(s)._last_contact = Soldier._now()
	check(not Virtualizer.calm(s), "a man in contact keeps his group real")
	SquadAI.of(s)._last_contact = -1000.0
	s.vitals.downed = true
	check(not Virtualizer.calm(s), "so does a man down (his squad treats him)")
	s.vitals.downed = false
	check(Virtualizer.calm(s), "calm again, it may go")
	check(Virtualizer.SPAWN_M < Virtualizer.DESPAWN_M and Virtualizer.FORCE_M < Virtualizer.SPAWN_M, "spawn range inside despawn range: no flicker at the edge")
	_drop(far)
	_drop(near)
	await _frames(2)


# --- Moving -----------------------------------------------------------------------------------------------

func _test_moving() -> void:
	print("A profile walks its route and takes new orders")
	_put_player(level.insertion_points()[0])
	var at := _away(1000.0, 3.0)
	var team := _team(2, at, "patrol")
	await _frames(2)
	var a := level.ground_point(at + Vector3(150, 0, 0))
	var b := level.ground_point(at + Vector3(150, 0, 150))
	var route: Array[Vector3] = [a, b]
	er._set_route(team.squad, team.soldiers, route)
	v.server_virtualize(team, true)
	var p: Dictionary = team.virtual
	var start: Vector3 = p.pos
	v.server_advance(30.0)
	var walked := Virtualizer._flat(start, p.pos)
	var pace := Virtualizer.pace(level, p)
	check(walked > 20.0 and walked < 30.0 * Virtualizer.PACE_MPS.max() * Virtualizer.ROAD_MULT + 1.0,
		"in 30 s it walks %.0f m toward its first point (pace here %.1f m/s)" % [walked, pace])
	check(Virtualizer._flat(p.pos, a) < Virtualizer._flat(start, a) and absf(float(p.pos.y) - level.ground_height(p.pos.x, p.pos.z)) < 0.5,
		"toward it, on the ground")
	v.server_advance(240.0)
	check(int(p.route_i) >= 1 and Virtualizer._flat(p.pos, a) > Virtualizer.ARRIVE_M, "past its first point it goes on to the next (leg %d)" % int(p.route_i))
	var c := level.ground_point(at + Vector3(-150, 0, 0))
	var sent: Array[Vector3] = [c]
	er._set_route(team.squad, [], sent)  # its owner sends it somewhere else, as it would a live group
	v.server_advance(1.0)
	check(int(p.route_i) == 0 and Virtualizer._flat(p.pos, c) < Virtualizer._flat(b, c) + 5.0, "a new route from its owner: it starts over on that one")
	v.server_advance(600.0)
	check(Virtualizer._flat(p.pos, c) <= Virtualizer.ARRIVE_M + 0.1, "a one-point route is walked to and held")
	# Roads and slopes.
	var terrain := level.terrain
	var road := Vector3.INF
	for r: Array in level.def.get("roads", []):
		var mid := (Vector2(r[0][0], r[0][1]) + Vector2(r[1][0], r[1][1])) * 0.5
		if terrain.road_weight(mid.x, mid.y) > 0.9:
			road = Vector3(mid.x, 0, mid.y)
			break
	if road.is_finite():
		var on := {"pos": level.ground_point(road), "members": p.members}
		var off := {"pos": level.ground_point(road + Vector3(60, 0, 60)), "members": p.members}
		check(Virtualizer.pace(level, on) > Virtualizer.pace(level, off) or terrain.road_weight(road.x + 60, road.z + 60) > 0.5,
			"faster on a road (%.2f m/s) than off it (%.2f m/s)" % [Virtualizer.pace(level, on), Virtualizer.pace(level, off)])
	else:
		check(false, "the zone has a road to walk on")
	# Waking where it got to: in a line across its heading, outside any unstreamed module.
	await _wake(team)
	var lead := Virtualizer.lead(team)
	check(not Virtualizer.is_virtual(team) and lead.is_finite() and Virtualizer._flat(lead, c) < 6.0, "it comes back where the profile had got to")
	check((team.soldiers as Array).all(func(s: Variant) -> bool:
		var m := level.module_at((s as Soldier).global_position)
		return m == null or m.is_streamed()), "never inside a module that isn't streamed in")
	_drop(team)
	await _frames(2)


# --- Fighting ---------------------------------------------------------------------------------------------------

func _test_fight() -> void:
	print("Two profiles at war fight off-screen")
	_put_player(level.insertion_points()[0])
	var at := _away(1100.0, 4.2)
	var reds := _team(4, at, "patrol")
	var others := _team(4, level.ground_point(at + Vector3(60, 0, 0)), "skirmish", "rival")
	await _frames(2)
	v.server_virtualize(reds, true)
	v.server_virtualize(others, true)
	var bodies_before := get_tree().get_nodes_in_group(Soldier.DEAD_GROUP).size()
	var fights := int(v.stats.fights)
	v.server_advance(Virtualizer.ROUND_S * 40.0)
	var left := Virtualizer.up(reds) + Virtualizer.up(others)
	await _frames(3)
	var bodies := get_tree().get_nodes_in_group(Soldier.DEAD_GROUP).size() - bodies_before
	check(int(v.stats.fights) > fights, "they meet (within CONTACT_M) and fight")
	check(left < 8 and bodies == 8 - left, "men fall: %d of 8 left, %d real bodies where they fell" % [left, bodies])
	check(not v.deaths.is_empty(), "the dead are on record (%d)" % v.deaths.size())
	var dead_body: Soldier = null
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		if v.deaths.has(String((n as Soldier).person_name)) or (n as Soldier).spawn_id != "" and v.deaths.has((n as Soldier).spawn_id):
			dead_body = n
	check(dead_body != null and dead_body.has_gear(), "a body has its kit on it (lootable when the squad gets there)")
	var red_left := Virtualizer.up(reds)
	var other_left := Virtualizer.up(others)
	check(red_left == 0 or other_left == 0 or float(Virtualizer.up(reds)) <= 4 * Virtualizer.BREAK_SHARE or float(Virtualizer.up(others)) <= 4 * Virtualizer.BREAK_SHARE \
		or v.stats.wounded > 0, "a side is wiped out or breaks off (%d against %d)" % [red_left, other_left])
	check(Virtualizer.at_war(&"hostile", &"rival") and not Virtualizer.at_war(&"hostile", &"hostile") and not Virtualizer.at_war(&"hostile", &"civilian"),
		"only sides at war fight (the same side never; civilians never)")
	_drop(reds)
	_drop(others)
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		(n as Node).queue_free()
	v.deaths.clear()
	await _frames(3)


# --- Never in view ----------------------------------------------------------------------------------------------

func _test_not_in_view() -> void:
	print("Nothing comes back where a player can see it")
	_put_player(level.insertion_points()[0])
	var at := _away(1000.0, 5.0)
	var team := _team(2, at, "patrol")
	await _frames(2)
	v.server_virtualize(team, true)
	var p: Dictionary = team.virtual
	var pos: Vector3 = p.pos
	# A player within SPAWN_M, high above the ground with a clear view of the spot.
	var dir := Vector3(1, 0, 0)
	player.global_position = level.ground_point(pos + dir * (Virtualizer.SPAWN_M - 100.0)) + Vector3.UP * 120.0
	await _frames(2)
	var spots := v.spawn_spots(team)
	var eyes := v._eyes(level)
	var seen := v.spots_seen(spots, eyes.players)
	check(seen, "from up there the player can see where its men would stand")
	check(not v._wake_due(team, eyes), "so the profile waits (inside SPAWN_M, in sight)")
	v.server_tick(0.0)
	check(Virtualizer.is_virtual(team), "and the tick doesn't spawn it")
	# A wall between them: out of sight, it comes back.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 400.0, 400.0)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = Throwables.WORLD_MASK
	level.add_child(wall)
	wall.global_position = Vector3(pos.x, pos.y, pos.z) + dir * 40.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not v.spots_seen(spots, eyes.players) and v._wake_due(team, eyes), "with a wall in the way it may come back")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Inside FORCE_M it comes back in sight or not.
	player.global_position = level.ground_point(pos + dir * (Virtualizer.FORCE_M - 50.0)) + Vector3.UP * 120.0
	await _frames(2)
	eyes = v._eyes(level)
	check(v._wake_due(team, eyes), "inside FORCE_M it comes back regardless")
	# Far away (beyond SPAWN_M) it stays a profile.
	player.global_position = level.ground_point(pos + dir * (Virtualizer.SPAWN_M + 80.0))
	await _frames(2)
	eyes = v._eyes(level)
	check(not v._wake_due(team, eyes), "beyond SPAWN_M it stays a profile")
	_drop(team)
	_put_player(level.insertion_points()[0])
	await _frames(2)


# --- Counting ----------------------------------------------------------------------------------------------------

func _test_counting() -> void:
	print("High command, the spawn budget and the QRF waves count virtual men")
	_put_player(level.insertion_points()[0])
	var command := EnemyCommand.of(level)
	check(command != null, "a hot zone has its high command")
	var at := _away(1000.0, 0.9)
	var team := _team(4, at, "hunters")
	team.merge({"k": 99, "at": er.now(), "retarget_at": INF, "smoked": false})
	er.hunters.append(team)
	await _frames(2)
	var total := er.alive_total()
	var names: Array = (team.soldiers as Array).map(func(s: Variant) -> String: return String((s as Soldier).name))
	v.server_virtualize(team, true)
	await _frames(2)
	check(er.alive_total() == total and er._alive_spawned() >= 4, "the spawn budget still counts them (%d out, %d before)" % [er.alive_total(), total])
	if command:
		command._count_losses()
		check(names.all(func(n: String) -> bool: return command._ever.has(n) and not command._deaths.has(n)), "the high command counts them as its men, none lost")
		# One killed off-screen: a loss on its books.
		var p: Dictionary = team.virtual
		var m: Dictionary = (p.members as Array).pop_back()
		v._kill(level, p, m)
		command._count_losses()
		check(command._deaths.has(String(m.name)), "a man killed while virtual is a loss to the high command")
		# It orders them home: the virtual group takes the order.
		command._send_home(team.squad, [], "", Virtualizer.lead(team))
		check(not (team.squad as Squad).patrol.is_empty(), "it can still send them home (their squad's route)")
	# A QRF wave as a profile still counts against the waves' cap.
	var reinf := er.reinforcements
	if reinf:
		var wave := _team(4, _away(1000.0, 1.6), "qrf")
		wave.merge({"index": 99, "sent_at": 0.0})
		reinf.waves.append(wave)
		var capped := reinf.capped_alive()
		v.server_virtualize(wave, true)
		check(reinf.capped_alive() == capped if reinf.driven else true, "the QRF waves' cap counts a virtual wave (%d)" % reinf.capped_alive())
		reinf.waves.erase(wave)
		_drop(wave)
	er.hunters.erase(team)
	_drop(team)
	await _frames(2)


# --- Garrisons ---------------------------------------------------------------------------------------------------

func _test_garrison() -> void:
	print("A garrison goes virtual at its posts and comes back with its module")
	var module: ZoneModule = null
	for m in level.modules():
		if ZoneModules.base(m.type) in GarrisonPost.TYPES and not level._garrisoned.has(m.module_id):
			module = m
			break
	if module == null:
		check(false, "a walled site to garrison")
		return
	_put_player(module.global_position + Vector3(0, 0, ZoneModules.HALF.get(module.type, Vector2(20, 20)).y + 30.0))
	if not await _wait_for(func() -> bool: return module.is_ready(), 30.0):
		check(false, "%s streams in" % module.module_id)
		return
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	level._spawn_garrison(module)
	await _wait_for(func() -> bool: return level.garrison_pending(module.module_id) == 0, 30.0)
	CompoundLevel.spawn_ai = false
	await _frames(5)
	var men := Virtualizer.garrison_men(level, module.module_id)
	var alive := level.garrison_alive(module.module_id)
	var before: Array = men.map(func(s: Variant) -> Dictionary: return _sig(s as Soldier))
	var posts: Array = men.map(func(s: Variant) -> Vector3: return SquadAI.of(s)._hold_point)
	var names: Array = men.map(func(s: Variant) -> String: return String((s as Soldier).name))
	check(men.size() >= 2 and alive == men.size(), "%s is garrisoned (%d men)" % [module.module_id, men.size()])
	# Away: the module streams out; the garrison goes virtual at its posts.
	_put_player(level.insertion_points()[0])
	await _wait_for(func() -> bool: return not module.is_streamed(), 20.0)
	check(not module.is_streamed(), "with the squad gone the module streams out")
	check(v.server_virtualize_garrison(level, module.module_id) and v.has_garrison(module.module_id), "its garrison goes virtual")
	await _frames(2)
	check(Virtualizer.garrison_men(level, module.module_id).is_empty() and level.garrison_alive(module.module_id) == alive
		and not level.site_down(module.module_id), "no men in the world, yet the site still has its %d (not down)" % level.garrison_alive(module.module_id))
	var alert := Alert.of(level)
	if alert:
		alert._check_ins[module.module_id] = -INF
		alert._check_in()
		await get_tree().create_timer(0.1).timeout
		check(v.garrison_up(module.module_id) == alive, "it answers its check-ins (as a profile: %d up)" % v.garrison_up(module.module_id))
	# Back: the module streams in and the garrison comes out at its posts.
	CompoundLevel.spawn_ai = true  # (as in a real session: garrisons come with their modules)
	_put_player(module.global_position + Vector3(0, 0, ZoneModules.HALF.get(module.type, Vector2(20, 20)).y + 30.0))
	await _wait_for(func() -> bool: return module.is_ready() and not v.has_garrison(module.module_id), 30.0)
	v.server_flush()
	CompoundLevel.spawn_ai = false
	await _frames(3)
	var back := Virtualizer.garrison_men(level, module.module_id)
	check(not v.has_garrison(module.module_id) and back.size() == men.size(), "with the squad back it comes back with its module (%d men)" % back.size())
	var after: Array = back.map(func(s: Variant) -> Dictionary: return _sig(s as Soldier))
	after.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.name < y.name)
	before.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.name < y.name)
	check(after == before, "the same men, exactly as they were")
	if after != before:
		for i in mini(before.size(), after.size()):
			if before[i] != after[i]:
				print("    before %s
    after  %s" % [before[i], after[i]])
	var post := level.post_of(module.module_id)
	var at_posts := true
	for s: Soldier in back:
		var i := names.find(String(s.name))
		at_posts = at_posts and i >= 0 and s.global_position.distance_to(posts[i]) < 1.0
	check(at_posts and (post == null or post.members.size() == back.size()), "each at his post, holding it again")
	_put_player(level.insertion_points()[0])
	await _wait_for(func() -> bool: return not module.is_streamed(), 20.0)
	v.server_virtualize_garrison(level, module.module_id)


# --- Saves -------------------------------------------------------------------------------------------------------

func _test_save() -> void:
	print("The zone save keeps every profile and gives it back")
	_put_player(level.insertion_points()[0])
	var team := _team(3, _away(1000.0, 2.0), "hunters")
	await _frames(2)
	var hurt := team.soldiers[0] as Soldier
	hurt.vitals.server_add_wound(Vitals.FOREARM_R, "gsw", 0.01)
	hurt.vitals.server_advance(10.0)
	for k in 5:
		(team.soldiers[1] as Soldier).inventory.consume_round(&"primary")
	var before := _sigs(team)
	v.server_virtualize(team, true)
	var garrisons := v.garrisons.size()
	check(GameState.save_zone(), "the zone saves")
	var read := GameState.read_save(GameState.save_path())
	var saved: Array = read.get("profiles", [])
	check(saved.size() >= 1 + garrisons and saved.all(func(p: Variant) -> bool: return Virtualizer.save_ok(p)),
		"its profiles are in the save (%d), each one sound" % saved.size())
	var mine: Dictionary = {}
	for p: Dictionary in saved:
		if String(p.squad) == String((team.squad as Node).name):
			mine = p
	check(not mine.is_empty() and (mine.members as Array).size() == 3, "this group's among them, all three men")
	# Back from the save, as a zone load does: a hunter team on the enemy response's list again.
	var hunters := er.hunters.size()
	GameState.load_zone()
	var restored_profiles := GameState.profiles.size()
	v._restored = false
	var keep_g := v.garrisons.duplicate()
	v.garrisons.clear()
	_drop(team)
	v.server_restore()
	check(restored_profiles >= 1 and er.hunters.size() == hunters + 1 and v.garrisons.size() == keep_g.size(),
		"a load gives them back: the hunters to the enemy response (%d), the garrisons to their modules (%d)" % [er.hunters.size() - hunters, v.garrisons.size()])
	var back: Dictionary = er.hunters.back()
	check(Virtualizer.is_virtual(back) and Virtualizer.up(back) == 3, "virtual, three men up")
	await _wake(back)
	var after := _sigs(back)
	for i in after.size():
		after[i].erase("buddy")
	for i in before.size():
		before[i].erase("buddy")
	check(after == before, "and they come back exactly as they were saved (kit, rounds, wounds)")
	if after != before:
		for i in mini(before.size(), after.size()):
			if before[i] != after[i]:
				print("    before %s\n    after  %s" % [before[i], after[i]])
	_drop(back)


# --- Capacity ------------------------------------------------------------------------------------------------------

func _test_capacity() -> void:
	print("A hot zone holds more: roaming teams on every route, outside the spawn budget")
	_put_player(level.insertion_points()[0])
	var routes := (level.def.get("patrols", []) as Array).size()
	var budget_before := er._alive_spawned()
	er.server_start()
	var want := er.patrols.filter(func(r: Dictionary) -> bool: return not r.second).size() * EnemyResponse.ROAM_TEAMS
	check(routes > 0 and er.roamers.size() == want, "%d roaming teams for %d routes (%d a route)" % [er.roamers.size(), routes, EnemyResponse.ROAM_TEAMS])
	for i in want + 2:
		er._tick_roamers()  # one sets out a tick
		await _frames(1)
	var out := er.roamers.filter(func(r: Dictionary) -> bool: return not r.pending)
	var men := 0
	for r: Dictionary in out:
		men += Virtualizer.up(r)
	check(out.size() == want and men == want * EnemyResponse.ROAM_SIZE, "all set out, one a tick: %d men" % men)
	var patrol_men := 0
	for r: Dictionary in er.patrols:
		patrol_men += Virtualizer.up(r)
	check(er._alive_spawned() == budget_before + patrol_men, "they don't count against the spawn budget (%d there, all patrols)" % er._alive_spawned())
	var virtual := 0
	for r: Dictionary in out:
		if v.server_virtualize(r, true):
			virtual += 1
	check(virtual == want and out.all(func(r: Dictionary) -> bool: return Virtualizer.up(r) == EnemyResponse.ROAM_SIZE),
		"far from the squad each is a profile, still %d men" % EnemyResponse.ROAM_SIZE)


# --- Rides (phase 3) -------------------------------------------------------------------------------------------------

## What a vehicle is, for comparing before and after (where it stands aside).
func _vsig(v: Vehicle) -> Dictionary:
	var out := v.to_save()
	out.erase("pos")
	out.erase("rot")
	out.fuel = snappedf(float(out.fuel), 0.01)
	return {"save": JSON.stringify(out, "", true)}


func _test_rides() -> void:
	print("A QRF technical goes virtual with its men, drives on, and comes back with them in their seats")
	_put_player(level.insertion_points()[0])
	var layer := VehicleLayer.of(level)
	var at := _away(1200.0, 0.3)
	var dir := Vector3(level.map_area().get_center().x - at.x, 0.0, level.map_area().get_center().y - at.z).normalized()
	var tech := layer.server_spawn("technical_dshk", Transform3D(Basis.looking_at(dir, Vector3.UP), at + Vector3.UP * 0.3), "", &"hostile", "")
	check(tech != null, "a technical out on the map")
	if tech == null:
		return
	await _frames(3)
	var team := _team(3, at + dir.cross(Vector3.UP) * 4.0, "qrf")
	await _frames(2)
	var order := VehicleQrf._seat_order(tech)
	for i in (team.soldiers as Array).size():
		tech.server_enter(team.soldiers[i], int(order[i]))
	var dest := level.ground_point(at + dir * 500.0)
	VehicleQrf.server_resume(level, tech, team.soldiers, dest, dest)  # a QRF ride on its way in
	await _frames(3)
	tech.server_set_fuel(41.5)
	tech.cargo_hold.take(&"frag_grenade", 2)
	var seats := {}
	for s: Soldier in team.soldiers:
		seats[String(s.name)] = tech.seat_of(s)
	var id := tech.vehicle_id
	var before_v := _vsig(tech)
	var before := _sigs(team)
	check(self.v.server_virtualize(team, true), "the group goes virtual, ride and all")
	await _frames(2)
	var p: Dictionary = team.get("virtual", {})
	check(layer.find(id) == null and (p.get("rides", []) as Array).size() == 1 and VehicleQrf.of(level).convoys.is_empty(),
		"the technical has left the world too; the profile holds it (1 ride) and VehicleQrf has let go of it")
	var start: Vector3 = p.get("pos", Vector3.ZERO)
	self.v.server_advance(10.0)
	var drove := Virtualizer._flat(start, p.pos)
	check(drove > 40.0 and Virtualizer._flat(p.pos, dest) < Virtualizer._flat(start, dest),
		"in 10 s it drives %.0f m toward where it's going (%.1f m/s here; a man walks %.1f)" % [drove, Virtualizer.ride_pace(level, p), Virtualizer.pace(level, p)])
	var spots := self.v.spawn_spots(team)
	check(spots.all(func(x: Vector3) -> bool: return Virtualizer._flat(x, p.pos) < 1.0), "its men would come back where the ride is (aboard)")
	await _wake(team)
	var back := layer.find(id)
	check(back != null and _vsig(back) == before_v, "the same technical comes back: its id, fuel, damage and cargo")
	if back:
		var seated := (team.soldiers as Array).all(func(s: Variant) -> bool: return back.seat_of(s) == int(seats.get(String((s as Node).name), -2)))
		check(seated and (team.soldiers as Array).size() == 3, "each man back in his own seat")
		check(not VehicleQrf.of(level).convoy_of(back).is_empty() and is_instance_valid(back.ai) and back.ai.active,
			"and it drives on as a QRF ride (VehicleQrf has it again, its driver at the wheel)")
	var after := _sigs(team)
	check(after == before, "the men exactly as they were")
	# Virtual all the way: it gets there off-screen, parks, and its men go on on foot.
	check(self.v.server_virtualize(team, true), "virtual again")
	self.v.server_advance(400.0)
	p = team.get("virtual", {})
	var parked := layer.find(id)
	check((p.get("rides", []) as Array).is_empty() and parked != null and parked.occupants().is_empty() and Virtualizer._flat(parked.global_position, dest) < 40.0,
		"at the end of its drive the technical is parked there, empty, and the profile goes on on foot")
	# Saved mid-drive and loaded: the ride and the seats come back.
	if parked:
		var crew := _team(2, parked.global_position + Vector3(4, 0, 0), "qrf")
		await _frames(2)
		for i in (crew.soldiers as Array).size():
			parked.server_enter(crew.soldiers[i], int(VehicleQrf._seat_order(parked)[i]))
		VehicleQrf.server_resume(level, parked, crew.soldiers, at, at)
		await _frames(2)
		check(self.v.server_virtualize(crew, true), "another crew drives it back: virtual")
		var saved: Array = self.v.to_save().filter(func(x: Dictionary) -> bool: return not (x.get("rides", []) as Array).is_empty())
		var json: Variant = JSON.parse_string(JSON.stringify(saved))
		check(json is Array and (json as Array).size() >= 1 and Virtualizer.save_ok(json[0]), "a ride is in the zone save")
		if json is Array and not (json as Array).is_empty():
			var restored := Virtualizer.from_save(json[0])
			_drop(crew)
			var rec := {"squad": er._new_squad("VTR"), "soldiers": [], "virtual": restored}
			self.v.track(rec, "qrf", false)
			await _wake(rec)
			var again := layer.find(id)
			check(again != null and (rec.soldiers as Array).size() == 2 and (rec.soldiers as Array).all(func(s: Variant) -> bool: return again.seat_of(s) >= 0),
				"loaded, the same technical comes back with its two men aboard")
			_drop(rec)
	_drop(team)
