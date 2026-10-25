extends Node
## Survival (docs/survival.md): a new world from the menu's entry hosts its start zone as a
## SurvivalLevel with nobody living in it but the players; a survivor starts with the starter
## kit; hunger and thirst drain and eating and drinking fill them; empty needs slow stamina;
## dying drops everything where he fell, it stays, and he's back with a starter kit; the world
## saves and Continue hosts it again where it was.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("SURVIVAL TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null:
		_test_needs()
		await _test_dead()
		await _test_melee()
		await _test_death()
		await _test_save_and_continue()
	_finish()


func _test_new_world() -> void:
	print("A new world")
	var name := "test_survival" + tag
	check(Survival.server_new_world(main, name, 1234), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	check(level != null and Net.is_hosting() and Survival.running, "its start zone is a survival zone, hosted (%s)" % [Survival.state().get("zone", "?")])
	if level == null:
		return
	check(Campaign.campaign_id == Survival.PREFIX + Survival.world and GameState.zone_id == Survival.zone_save(String(Survival.state().zone)),
		"its own save, apart from the campaign (%s, %s)" % [Campaign.campaign_id, GameState.zone_id])
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	for i in 240:  # a few seconds of the zone running: modules stream in, anything that spawns would
		await get_tree().process_frame
	var living := level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and not (s as Soldier).vitals.is_dead() and s.faction != ZombieAI.INFECTED)
	check(living.is_empty(), "nobody living holds or walks the zone: no garrisons, patrols or squad bots (%d)" % living.size())
	var have := Survival.kit_of(player.inventory).map(func(e: Dictionary) -> String: return String(e.id))
	check(have.has("knife") and have.has("water_bottle") and have.has("canned_meat") and not have.has("m4a1"),
		"a new survivor has the starter kit and no rifle (%s)" % [have])


func _test_needs() -> void:
	print("Hunger and thirst")
	var n := Survival.needs_of(player)
	n.hunger = 100.0
	n.thirst = 100.0
	Survival.server_drain(player, Survival.DAY_MIN * 60.0 * 0.75)  # three quarters of a world day
	check(absf(float(n.thirst) - 50.0) < 1.0 and absf(float(n.hunger) - 75.0) < 1.0,
		"three quarters of a day: thirst at half, hunger at three quarters (%.0f, %.0f)" % [n.thirst, n.hunger])
	check(is_equal_approx(player.needs_stamina, 1.0), "still fed enough: stamina comes back as ever")
	var tin := _index_of(player, &"canned_meat")
	check(tin[0] != &"" and Consumables.server_use(player, tin[0], tin[1]) == "" and float(n.hunger) > 75.0,
		"eating the tin fills hunger (%.0f)" % n.hunger)
	var water := _index_of(player, &"water_bottle")
	check(water[0] != &"" and Consumables.server_use(player, water[0], water[1]) == "" and float(n.thirst) >= 84.0,
		"drinking the water fills thirst (%.0f)" % n.thirst)
	n.thirst = 10.0
	Survival.server_drain(player, 1.0)
	check(player.needs_stamina < Survival.LOW_STAMINA_MULT, "parched: stamina comes back slower (%.2f)" % player.needs_stamina)
	n.thirst = 0.0
	n.hunger = 0.0
	var blood := player.vitals.blood_fraction()
	Survival.server_drain(player, 30.0)
	var after := player.vitals.blood_fraction()
	check(after < blood, "empty: it costs blood (%.3f -> %.3f)" % [blood, after])
	n.thirst = 80.0
	n.hunger = 80.0
	Survival.server_drain(player, 1.0)
	player.vitals.server_reset_health()


func _test_dead() -> void:
	print("The dead")
	player.server_end_spawn_protection()
	await _wait_for(func() -> bool: return not Survival.zombies(level).is_empty(), 12.0)
	var near := Survival.zombies(level)
	check(not near.is_empty() and near.all(func(z: Soldier) -> bool: return z.global_position.distance_to(player.global_position) >= Survival.SPAWN_MIN_M - 8.0),
		"the dead come about a survivor, out of reach and out of sight (%d; want %d here)" % [near.size(), Survival.dead_near(level, player.global_position)])
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	await get_tree().process_frame
	Survival._pop = -1000.0  # (no more for now: the test sets its own)
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Hearing: one behind him, far off, goes to a shot.
	var far := Survival.server_spawn_zombie(level, level.ground_point(player.global_position - fwd * 90.0))
	await get_tree().physics_frame
	Survival.server_noise(player, player.global_position, ZombieAI.SHOT_HEARD_M)
	var brain := ZombieAI.of(far)
	check(brain != null and brain.mode == ZombieAI.Mode.INVESTIGATE and brain.goal.distance_to(player.global_position) < 2.0,
		"one 90 m off hears a shot and goes to where it was (%s)" % [ZombieAI.Mode.keys()[brain.mode] if brain else "no brain"])
	far.queue_free()
	# Sight, the chase and the bite.
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 12.0))
	var blood := player.vitals.blood_fraction()
	var wounds_before := player.vitals.wound_list().size()
	var bit := await _wait_for(func() -> bool: return player.vitals.blood_fraction() < blood or player.vitals.wound_list().size() > wounds_before, 20.0)
	brain = ZombieAI.of(z)
	check(brain != null and brain.mode == ZombieAI.Mode.CHASE and brain.target == player, "one 12 m in front sees him and comes for him")
	check(bit, "and gets to him and bites (blood %.3f -> %.3f)" % [blood, player.vitals.blood_fraction()])
	# The head kills; the body wears the pool down.
	z.vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.INTERMEDIATE, "energy_j": 1700.0})
	check(z.vitals.is_up(), "a round in the chest doesn't stop it (pool %.1f)" % z.vitals.undead_pool)
	z.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "energy_j": 400.0})
	check(z.vitals.is_dead(), "one in the head does")
	var tough := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 30.0))
	await get_tree().physics_frame
	for i in 12:
		if tough.vitals.is_dead():
			break
		tough.vitals.server_hit(Vitals.ABDOMEN, {"round_class": Vitals.INTERMEDIATE, "energy_j": 1700.0})
	check(tough.vitals.is_dead(), "enough in the body puts it down too (%s)" % tough.vitals.last_cause.get("cause", "?"))
	check(Survival.thinned(z.global_position) > 0.0, "and every kill thins the dead about there (%.2f)" % Survival.thinned(z.global_position))
	player.vitals.server_reset_health()


func _test_melee() -> void:
	print("Melee: block, parry, counter, dodge")
	for zz: Soldier in Survival.zombies(level):
		zz.queue_free()
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var z := Survival.server_spawn_zombie(level, player.global_position + fwd * 1.0)
	await get_tree().physics_frame
	z.process_mode = Node.PROCESS_MODE_DISABLED  # (the test drives it)
	z.look_at(player.global_position, Vector3.UP)
	z.rotation.x = 0.0
	player.look_at(z.global_position, Vector3.UP)
	player.rotation.x = 0.0
	var blood := player.vitals.blood_fraction()
	var front := Melee.target_in_front(z)
	check(front == player, "the bite has him in front of it (%s; %.2f m, z faces %s, to him %s)" % [front, z.global_position.distance_to(player.global_position),
		-z.global_basis.z, (player.global_position - z.global_position).normalized()])
	# A parry: the block comes just before the bite lands.
	check(Melee.server_attack(z, Melee.ZOMBIE_ATTACK), "the dead's bite winds up (%.2f s)" % float(Melee.ZOMBIE_ATTACK.windup))
	await _seconds(float(Melee.ZOMBIE_ATTACK.windup) - 0.1)
	Melee.server_block(player, true)
	await _seconds(0.2)
	check(Melee.staggered(z) and is_equal_approx(player.vitals.blood_fraction(), blood), "a block raised just before it lands parries: it staggers, nothing gets through (now %.2f; his guard %s; its %s; winding %s)" % [
		Soldier._now(), Melee.guard_of(player), Melee.guard_of(z), z.get_meta(&"melee_winding", "landed")])
	var counter_ready := Soldier._now() < float(Melee.guard_of(player).counter_until)
	check(counter_ready, "and the parry opens a counter")
	var pool := z.vitals.undead_pool
	Melee.server_attack(player, {"windup": 0.6, "round_class": Vitals.PISTOL, "energy_j": 300.0, "parts": [Vitals.CHEST], "name": "knife"})
	check(z.vitals.undead_pool < pool, "the counter lands at once, twice as hard (pool %.1f -> %.1f)" % [pool, z.vitals.undead_pool])
	Melee.server_block(player, false)
	# A block held long before: a jolt gets through.
	await _seconds(Melee.STAGGER_S)
	Melee.server_block(player, true)
	await _seconds(0.5)
	Melee.server_attack(z, Melee.ZOMBIE_ATTACK)
	await _seconds(float(Melee.ZOMBIE_ATTACK.windup) + 0.1)
	check(not Melee.staggered(z), "a block held a while just blocks (no parry)")
	Melee.server_block(player, false)
	# A dodge: nothing lands.
	player.vitals.server_reset_health()
	blood = player.vitals.blood_fraction()
	Melee.server_attack(z, Melee.ZOMBIE_ATTACK)
	await _seconds(float(Melee.ZOMBIE_ATTACK.windup) - 0.15)
	check(Melee.server_dodge(player), "a dodge, for stamina")
	await _seconds(0.3)
	check(is_equal_approx(player.vitals.blood_fraction(), blood), "and the bite misses")
	z.queue_free()
	player.vitals.server_reset_health()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _test_death() -> void:
	print("Death")
	player.inventory.take(&"m4a1")
	var at := player.global_position
	var before := level.items.get_child_count()
	player.server_end_spawn_protection()
	player.vitals.server_kill()
	await _wait_for(func() -> bool: return level.items.get_child_count() > before, 10.0)
	var near := level.items.get_children().filter(func(i: Node) -> bool: return i is WorldItem and (i as WorldItem).global_position.distance_to(at) < 4.0)
	var ids := near.map(func(i: WorldItem) -> String: return String(i.item_id))
	check(ids.has("m4a1") and ids.has("knife"), "everything he had lies where he fell (%s)" % [ids])
	var have := Survival.kit_of(player.inventory).map(func(e: Dictionary) -> String: return String(e.id))
	check(not have.has("m4a1") and have.has("knife") and have.has("water_bottle"), "and he's back with a starter kit (%s)" % [have])
	check(float(Survival.needs_of(player).thirst) == Survival.RESPAWN_NEEDS, "and his needs at %.0f" % Survival.RESPAWN_NEEDS)
	var cleanup := level.get_node_or_null(^"ZoneCleanup") as ZoneCleanup
	if cleanup:
		cleanup.server_sweep(Soldier._now() + 100000.0)
		cleanup.server_sweep(Soldier._now() + 200000.0)
	await get_tree().process_frame
	var still := level.items.get_children().filter(func(i: Node) -> bool: return i is WorldItem and not i.is_queued_for_deletion() and (i as WorldItem).item_id == &"m4a1")
	check(not still.is_empty(), "and it stays there: survival never cleans up what's dropped")
	check(not (Survival.state().get("graves", []) as Array).is_empty(), "the world remembers where he fell")
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING, 20.0)


func _test_save_and_continue() -> void:
	print("Save and continue")
	Survival.state()["day"] = 3
	Survival.server_save()
	var name := Survival.world
	check(Campaign.has_save(), "the world saves (%s)" % Campaign.save_path())
	check(Survival.newest_world() == name, "and it's the newest world to continue (%s)" % Survival.newest_world())
	Survival.state()["day"] = 1
	Net.leave()  # (back at the menu: Continue hosts again)
	await get_tree().process_frame
	check(Survival.server_continue(main, name), "Continue hosts it again")
	level = SurvivalLevel.of(self)
	check(Survival.day() == 3 and level != null, "where it was left: day %d" % Survival.day())
	await _wait_for(func() -> bool: return level != null and level.players.get_node_or_null(^"1") != null, 20.0)


func _index_of(s: Soldier, id: StringName) -> Array:
	for c: StringName in Inventory.CONTAINERS:
		var list: Array = s.inventory.containers.get(c, [])
		for i in list.size():
			if StringName(list[i].id) == id:
				return [c, i]
	return [&"", -1]


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("SURVIVAL TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
