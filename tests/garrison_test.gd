extends Node3D
## Site garrisons hold their walls (Captain, 2026-10-19: "troops in compounds shouldnt abandon
## compounds to attack the player and his ai ... they should wait in ambush for us or try to
## escape if they believe they are severely outgunned"): GarrisonPost. In the test zone with AI:
## the compound's garrison gets a post; with the player in sight outside, nobody leaves the walls
## and nobody fires (an ambush); it springs when one of them is fired on; cut down to half and
## faced with a bigger force it breaks, and the survivors run out away from the enemy.

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_garrison" + tag  # never touch a real save
	Campaign.campaign_id = "test_garrison" + tag
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
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
	var m := level.get_module("compound")
	var rect := m.footprint()
	# Stand 120 m south of the walls, in the open: the module streams in, its garrison comes out.
	var watch := level.ground_point(m.global_position + Vector3(0, 0, rect.size.y * 0.5 + 120.0))
	player.global_position = watch
	await _wait_for(func() -> bool: return level.post_of("compound") != null and level.garrison_pending("compound") == 0, 30.0)
	var post := level.post_of("compound")
	check(post != null and post.members.size() >= 3, "the compound's garrison holds a post (%d men)" % (post.members.size() if post else 0))
	if post == null:
		return
	check(post.members.all(func(s: Soldier) -> bool: return SquadAI.of(s).post == post), "every one of them knows it")
	check(not post.sprung and post.members.all(func(s: Soldier) -> bool: return not SquadAI.of(s).weapons_free()),
		"in ambush: nobody's weapon is free")
	# 20 s with the player out there in the open: nobody steps outside the walls.
	var worst := 0.0
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		for s in post.alive():
			if not post.holds(s.global_position):
				var p := Vector2(s.global_position.x, s.global_position.z)
				var r := post.rect
				worst = maxf(worst, maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y)))
	check(worst < 1.0, "20 s with the squad in the open outside: nobody leaves the walls (worst %.1f m out)" % worst)
	check(not post.sprung, "and nobody gives the ambush away at 120 m")
	# One of them fired on: the ambush springs, every weapon free.
	var first := post.alive()[0]
	SquadAI.of(first)._fired_on_at = Soldier._now()
	await _wait_for(func() -> bool: return post.sprung, 3.0)
	check(post.sprung and post.alive().all(func(s: Soldier) -> bool: return SquadAI.of(s).weapons_free() or SquadAI.of(s).hold_fire),
		"fired on, the ambush springs: they open up")
	# Cut down past half, faced with six: it breaks and they run.
	var up := post.alive()
	var keep := int(floor(post.start * GarrisonPost.FLEE_LEFT_SHARE))
	for k in range(keep, up.size()):
		up[k].vitals.server_kill()
	var squad: Array[Soldier] = []
	for k in 6:
		squad.append(level.spawn_soldier({"name": "Friend%d" % k, "faction": "friendly", "variant": "multicam", "guard": false,
			"pos": watch + Vector3(k * 2.0 - 5.0, 0, -60.0), "combat": 0.5, "discipline": 0.5, "loadout": ["m4a1", "mag_556"]}))
		SquadAI.of(squad[-1]).hold_fire = true  # counted, not fighting: on a slow runner they shot the survivors before the check (CI)
	await _wait_for(func() -> bool: return post.fleeing, 5.0)
	check(post.fleeing, "down to %d of %d against six, the garrison breaks" % [post.alive().size(), post.start])
	await get_tree().create_timer(6.0).timeout
	var running := post.alive().filter(func(s: Soldier) -> bool:
		var ai := SquadAI.of(s)
		return ai.intent == SquadAI.Intent.FALL_BACK and ai._fall_back_point != null and not post.holds(ai._fall_back_point as Vector3))
	check(not post.alive().is_empty() and running.size() == post.alive().size(),
		"its survivors run for it, out of the walls (%d of %d)" % [running.size(), post.alive().size()])
	var away := post.alive().all(func(s: Soldier) -> bool:
		return ((SquadAI.of(s)._fall_back_point as Vector3) - m.global_position).dot(m.global_position - watch) > 0.0) if not post.alive().is_empty() else false
	check(away, "away from the squad, not into it")
	await _test_road_ambush()


## F-140 (the overwatch mission's ambushers): a team laid by a road (RoadAmbush) holds its spots
## in cover, holding fire, while the squad watches from the high ground; it springs as a crewed
## friendly M-ATV comes level with it, every man opening up on the truck and its crew; the truck
## (driven as a convoy's, SquadDrivers.server_drive_route) drives on through faster; disabled, its
## crew bail out on the side away from the ambush; the ambushers fight from their ground.
func _test_road_ambush() -> void:
	print("Road ambush (F-140)")
	var road := PackedVector3Array([level.ground_point(Vector3(-400, 0, 300)), level.ground_point(Vector3(100, 0, 300))])
	var at := level.ground_point(Vector3(-150, 0, 350))
	player.global_position = level.ground_point(Vector3(-150, 0, 215))  # the overwatch: 85 m south of the road
	var map := player.get_world_3d().navigation_map
	await _wait_for(func() -> bool: return NavigationServer3D.map_get_closest_point(map, at).distance_to(at) < 1.5, 20.0)
	var hill: Array[Soldier] = []  # the squad on the high ground: out of the ambush's sight while the convoy comes on
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var f := n as Soldier
		if f and f.faction == &"friendly":
			if SquadAI.of(f):
				SquadAI.of(f).hold_fire = true  # (the squad on the hill watches: the ambush is the convoy's)
			hill.append(f)
	for f in hill:
		f.remove_from_group(&"combatants")
	var sq := Squad.new()
	sq.name = "AmbushTest"
	sq.faction = &"hostile"
	level.add_child(sq)
	var men: Array = []
	for k in 3:
		var s: Soldier = level.spawn_soldier({"name": "Amb%d" % k, "faction": "hostile", "variant": "urban", "guard": false, "mode": "aware",
			"pos": at + Vector3(k * 2.0 - 2.0, 0, 0), "combat": 0.6, "discipline": 0.5, "loadout": ["akm", "mag_762x39", "mag_762x39"]})
		SquadAI.of(s).squad = sq
		men.append(s)
	var amb := RoadAmbush.server_lay(men, at, road, "test_road")
	check(amb.members.size() == 3 and men.all(func(s: Soldier) -> bool: return SquadAI.of(s).post == amb and amb.position_of(s) is Vector3),
		"three men lie in wait by the road, each with his own spot")
	check(absf(amb.kill_point.z - road[0].z) < 0.5 and absf(amb.kill_point.x - at.x) < 1.0, "the kill zone is the road's nearest stretch (%s)" % amb.kill_point)
	# The convoy: an M-ATV with a driver and a gunner, its own squad, driven as an order.
	var layer := level.get_node(^"Vehicles") as VehicleLayer
	var fwd := (road[1] - road[0]).normalized()
	var v := layer.server_spawn("matv", Transform3D(Basis.looking_at(fwd, Vector3.UP), road[0] + Vector3.UP * 0.4), "", &"friendly", "ambush_matv")
	var convoy := Squad.new()
	convoy.name = "ConvoyTest"
	convoy.faction = &"friendly"
	level.add_child(convoy)
	var crew: Array[Soldier] = []
	var seats := VehicleQrf._seat_order(v)
	for k in 2:
		var c: Soldier = level.spawn_soldier({"name": "Crew%d" % k, "faction": "friendly", "variant": "multicam", "guard": false,
			"pos": road[0] + Vector3(-4, 0, 3 + k), "combat": 0.5, "discipline": 0.5, "loadout": ["m4a1", "mag_556"]})
		SquadAI.of(c).squad = convoy
		SquadAI.of(c).hold_fire = false
		c.set_meta(&"vehicle_crew", true)
		if v.server_enter(c, int(seats[k])):
			crew.append(c)
	convoy.leader = crew[0] if not crew.is_empty() else null
	await get_tree().create_timer(4.0).timeout  # (they get to their spots)
	var drivers := SquadDrivers.of(level)
	var path := PackedVector3Array([road[1]])
	check(crew.size() == 2 and drivers.server_drive_route(v, path, 30.0, convoy), "a crewed M-ATV sets out down the road as a convoy's truck")
	var held := true
	var free := false
	var worst := 0.0
	var deadline := Time.get_ticks_msec() + 60000
	while not amb.sprung and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
		for s: Soldier in amb.alive():
			var ai := SquadAI.of(s)
			free = free or (ai.weapons_free() and not amb.sprung)
			if v.global_position.distance_to(at) < RoadAmbush.KILL_M * 1.3:
				worst = maxf(worst, Vector2(s.global_position.x - (amb.position_of(s) as Vector3).x, s.global_position.z - (amb.position_of(s) as Vector3).z).length())
	held = worst < 2.0
	check(held and not free, "while it comes on they hold their spots, holding fire (worst %.1f m off his spot)" % worst)
	check(amb.sprung and amb.lead == v and absf(v.global_position.x - at.x) < 30.0,
		"they spring it as the truck comes level (%s; truck at x %.0f, the ambush at x %.0f)" % [amb.why, v.global_position.x, at.x])
	var hits := [0]
	v.damaged.connect(func(_z: StringName, hit: Dictionary) -> void:
		if is_instance_valid(hit.get("shooter")) and (hit.shooter as Soldier).faction == &"hostile":
			hits[0] += 1)
	var on_truck := await _wait_for(func() -> bool:
		return amb.alive().any(func(s: Soldier) -> bool: return SquadAI.of(s).target != null and Vehicle.ride_of(SquadAI.of(s).target) == v), 6.0)
	check(amb.alive().all(func(s: Soldier) -> bool: return SquadAI.of(s).weapons_free()) and on_truck,
		"sprung, every man opens up, on the truck's crew first")
	var crew_hit := func() -> int: return crew.filter(func(c: Soldier) -> bool: return not c.vitals.wound_list().is_empty()).size()
	await _wait_for(func() -> bool: return hits[0] > 0 or crew_hit.call() > 0, 10.0)
	check(hits[0] > 0 or crew_hit.call() > 0, "their rounds hit the truck or its crew (%d hits on it, %d of its crew hit; %s)" % [hits[0], crew_hit.call(), ", ".join(amb.members.map(func(s: Soldier) -> String:
		if not is_instance_valid(s):
			return "gone"
		var ai := SquadAI.of(s)
		return "%s %s: %s, target %s, supp %.2f, %d rounds, %s" % [s.name, "up" if s.vitals.is_up() else "down", s.ai_status,
			ai.target.name if ai.target else "none", s.suppression, s.inventory.rounds_in(s.active_slot), ai.shoot_blocker()]))])
	await _wait_for(func() -> bool: return String(drivers.last_contact.get(v.get_instance_id(), "")) == DriveContact.THROUGH, 4.0)
	check(String(drivers.last_contact.get(v.get_instance_id(), "")) == DriveContact.THROUGH and v.ai.cruise_ms > 30.0 / 3.6 + 1.0,
		"the truck drives on through, faster (%s, %.1f m/s)" % [drivers.last_contact.get(v.get_instance_id(), "none"), v.ai.cruise_ms])
	check(amb.priority_vehicle(&"hostile", get_tree()) == v, "the ambush's launchers would go for the lead truck first")
	# Disabled in the kill zone: the crew bail out on the far side and fight from there.
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.0)  # (its engine module too: combined arms A2's zones come from the modules)
	await _wait_for(func() -> bool: return v.occupants().is_empty(), 5.0)
	var out_of_it := v.occupants().is_empty()
	var away := func(c: Soldier) -> bool: return _flat_d(c.global_position, at) > _flat_d(v.global_position, at) + 1.0  # (the lee: the truck between him and the ambush)
	await _wait_for(func() -> bool: return crew.all(func(c: Soldier) -> bool: return not c.vitals.is_up() or away.call(c)), 8.0)
	var lee := crew.filter(func(c: Soldier) -> bool: return c.vitals.is_up() and away.call(c))
	check(out_of_it and lee.size() == crew.filter(func(c: Soldier) -> bool: return c.vitals.is_up()).size(),
		"disabled, its crew bail out on the side away from the ambush (%d of %d out on its far side; %s)" % [lee.size(), crew.size(),
		", ".join(crew.map(func(c: Soldier) -> String: return "%s %s %.0f m from the ambush (truck %.0f)" % [c.name, c.ai_status, _flat_d(c.global_position, at), _flat_d(v.global_position, at)]))])
	# The squad on the high ground in sight again: the ambush takes it on too, as a fight.
	for f in hill:
		if is_instance_valid(f):
			f.add_to_group(&"combatants")
	var on_hill := await _wait_for(func() -> bool:
		return amb.alive().any(func(s: Soldier) -> bool: return SquadAI.of(s).target != null and SquadAI.of(s).target in hill), 25.0)
	check(on_hill or amb.alive().is_empty(), "the squad on the high ground in sight, the ambush takes it on too (%s)" % ", ".join(amb.alive().map(func(s: Soldier) -> String:
		return "%s on %s" % [s.name, SquadAI.of(s).target.name if SquadAI.of(s).target else "nobody"])))
	# The fight goes on from their ground: nobody chases the truck or makes for the hill.
	var out := 0.0
	var until := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.5).timeout
		for s: Soldier in amb.alive():
			if not amb.fleeing:
				var p := Vector2(s.global_position.x, s.global_position.z)
				var r := amb.rect
				out = maxf(out, maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y)))
	check(out < 1.0, "the ambushers fight from their own ground (worst %.1f m out of it)" % out)
	await _test_patrol_formation()


## G-26: a hostile patrol walks its route in formation behind its lead (Squad.patrol_lead), each
## man at his slot (Squad.follow_point), its formation picked for the ground and its gaps by its
## doctrine.
func _test_patrol_formation() -> void:
	print("Patrol formation (G-26)")
	var start := level.ground_point(Vector3(260, 0, 120))
	var finish := level.ground_point(Vector3(260, 0, 20))
	player.global_position = level.ground_point(Vector3(330, 0, 70))
	var map := player.get_world_3d().navigation_map
	await _wait_for(func() -> bool: return NavigationServer3D.map_get_closest_point(map, start).distance_to(start) < 1.5 		and NavigationServer3D.map_get_closest_point(map, finish).distance_to(finish) < 1.5, 20.0)
	var unseen: Array[Soldier] = []  # (nobody of ours for them to see: the walk, not a fight, is checked)
	for n in get_tree().get_nodes_in_group(&"combatants"):
		if (n as Soldier).faction == &"friendly":
			unseen.append(n as Soldier)
	for f in unseen:
		f.remove_from_group(&"combatants")
	var sq := Squad.new()
	sq.name = "PatrolTest"
	sq.faction = &"hostile"
	sq.doctrine = Doctrine.REGULAR
	level.add_child(sq)
	var men: Array[Soldier] = []
	for k in 4:
		var s: Soldier = level.spawn_soldier({"name": "Pat%d" % k, "faction": "hostile", "variant": "urban", "guard": false, "mode": "safe",
			"pos": start + Vector3(k * 1.5, 0, 0), "combat": 0.5, "discipline": 0.5, "loadout": ["akm", "mag_762x39"]})
		SquadAI.of(s).squad = sq
		SquadAI.of(s).hold_fire = true
		men.append(s)
	var route: Array[Vector3] = [finish, start]
	sq.patrol = route
	var worst := [0.0, 0, 0.0, ""]  # the furthest a follower was off his slot, how many looks, the summed look averages, who was worst
	var apart := [INF]
	var deadline := Time.get_ticks_msec() + 18000
	await get_tree().create_timer(6.0).timeout  # (they form up)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		var lead := sq.patrol_lead()
		if lead == null:
			continue
		var sum := 0.0
		var n := 0
		for s: Soldier in men:
			if s == lead or not s.vitals.is_up():
				continue
			var off := Vector2(s.global_position.x - sq.follow_point(s).x, s.global_position.z - sq.follow_point(s).z).length()
			sum += off
			n += 1
			if off > float(worst[0]):
				worst[0] = off
				worst[3] = "%s %s" % [s.name, s.ai_status]
			for o: Soldier in men:
				if o != s:
					apart[0] = minf(float(apart[0]), s.global_position.distance_to(o.global_position))
		worst[1] = int(worst[1]) + 1
		worst[2] = float(worst[2]) + (sum / n if n > 0 else 0.0)
		if int(worst[1]) % 6 == 1:
			print("    lead %s at %s; %s" % [lead.name, lead.global_position.snappedf(0.1), ", ".join(men.filter(func(m: Soldier) -> bool: return m != lead).map(func(m: Soldier) -> String:
				return "%s at %s slot %s going %s (%s)" % [m.name, m.global_position.snappedf(0.1), sq.follow_point(m).snappedf(0.1), SquadAI.of(m).destination().snappedf(0.1), m.ai_status]))])
	var lead := sq.patrol_lead()
	check(lead != null and sq.leader == lead and lead.global_position.distance_to(start) > 15.0,
		"the patrol's lead walks its route (%s, %.0f m along)" % [lead.name if lead else "none", lead.global_position.distance_to(start) if lead else 0.0])
	var mean := float(worst[2]) / maxf(float(worst[1]), 1.0)
	check(int(worst[1]) > 10 and mean < float(sq.resolved(0).man) and float(apart[0]) > 1.5,
		"the rest keep their places in its %s behind him, within a man's gap (%.1f m off their slots on average, worst %.1f m: %s; never closer than %.1f m to another)" % [sq.context.formation, mean, worst[0], worst[3], apart[0]])
	check(absf(float(sq.resolved(0).man) - float(Squad.SPACINGS[String(sq.context.spacing)].man) * Doctrine.value(Doctrine.REGULAR, "spacing")) < 0.01,
		"at its doctrine's gaps (%s, %.1f m)" % [sq.context.spacing, float(sq.resolved(0).man)])
	for s: Soldier in men:
		s.queue_free()
	sq.queue_free()
	for f in unseen:
		if is_instance_valid(f):
			f.add_to_group(&"combatants")


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _finish() -> void:
	print("GARRISON TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	GameState.delete_save()
	get_tree().quit(failures)
