extends Node
## Survival (docs/survival.md): a new world from the menu's entry hosts its start zone as a
## SurvivalLevel with nobody living in it but the players; a survivor starts with the starter
## kit; the metabolism (calories, water, macros, sleep, warmth, hygiene) drains at its rates and
## food and water fill it; dirty water can make him sick; sleep passes time at speed and a chasing
## zombie wakes him; the HUD shows only low stores; empty needs slow stamina;
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
		await _test_metabolism()
		await _test_dead()
		await _test_melee()
		await _test_melee_weapons()
		await _test_stealth()
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
	print("Hunger and thirst: the metabolism's calories and water")
	var n := Survival.needs_of(player)
	Needs.respawn(n, 100.0)
	Needs.step(n, 18.0, {})  # three quarters of a world day, calm
	check(absf(float(n.calories) - (Needs.FED_KCAL - Needs.KCAL_DAY * 0.75)) < 1.0 and absf(float(n.water) - (Needs.FED_L - Needs.WATER_DAY * 0.75)) < 0.01,
		"three quarters of a day: 1,350 kcal and about 1.9 l gone (%.0f kcal, %.2f l)" % [n.calories, n.water])
	check(absf(float(n.hunger) - 46.0) < 1.0 and absf(float(n.thirst) - 37.5) < 1.0, "S1's hunger and thirst still read off them (%.0f, %.0f)" % [n.hunger, n.thirst])
	var hour_kcal := float(n.calories)
	Survival.server_drain(player, Survival.DAY_MIN * 60.0 / 24.0)  # one world hour, scaled by the day's length
	var burnt := hour_kcal - float(n.calories)
	check(burnt > 60.0 and burnt < 200.0, "an hour on the body burns about 75 kcal (%.0f)" % burnt)
	var calm := Needs.fresh()
	var running := Needs.fresh()
	Needs.step(calm, 6.0, {})
	Needs.step(running, 6.0, {"sprint": true})
	check(absf((Needs.FED_KCAL - float(running.calories)) - 2.0 * (Needs.FED_KCAL - float(calm.calories))) < 1.0, "running burns twice as fast")
	check(is_equal_approx(player.needs_stamina, 1.0), "still fed enough: stamina comes back as ever")
	Needs.respawn(n, 50.0)
	var kcal := float(n.calories)
	var protein := float(n.protein)
	var tin := _index_of(player, &"canned_meat")
	check(tin[0] != &"" and Consumables.server_use(player, tin[0], tin[1]) == "" and absf(float(n.calories) - kcal - 450.0) < 1.0 and float(n.protein) > protein,
		"eating the tin: its 450 kcal and its protein (%.0f -> %.0f kcal, protein %.0f -> %.0f)" % [kcal, n.calories, protein, n.protein])
	var water_l := float(n.water)
	var water := _index_of(player, &"water_bottle")
	check(water[0] != &"" and Consumables.server_use(player, water[0], water[1]) == "" and absf(float(n.water) - water_l - 1.0) < 0.01,
		"drinking the bottle: a litre (%.2f -> %.2f l)" % [water_l, n.water])
	kcal = float(n.calories)
	Survival.server_feed(player, &"ration", 1.0)
	check(float(n.calories) > kcal + 500.0, "an item without food values still feeds by S1's dose (%.0f -> %.0f)" % [kcal, n.calories])
	n.thirst = 10.0
	Survival.server_drain(player, 1.0)
	check(player.needs_stamina < Survival.LOW_STAMINA_MULT, "parched: stamina comes back slower (%.2f)" % player.needs_stamina)
	n.thirst = 0.0
	n.hunger = 0.0
	var blood := player.vitals.blood_fraction()
	Survival.server_drain(player, 30.0)
	var after := player.vitals.blood_fraction()
	check(after < blood, "empty water: it costs blood (%.3f -> %.3f)" % [blood, after])
	Needs.respawn(n, 80.0)
	Survival.server_drain(player, 1.0)
	player.vitals.server_reset_health()


func _test_metabolism() -> void:
	print("The metabolism: water quality, sickness, sleep, warmth, the body readout")
	var n := Survival.needs_of(player)
	Needs.respawn(n, 80.0)
	# Water quality: raw dirty water rolls dysentery; treated water doesn't.
	var dirty := ItemDB.get_item(&"dirty_water_bottle")
	check(dirty != null and Needs.quality_of(dirty) == "dirty" and bool(dirty.stats.get("raw", false)), "a bottle of dirty water is dirty and raw")
	player.inventory.take(&"dirty_water_bottle", 1)
	Needs.force_roll = 0.0
	var bottle := _index_of(player, &"dirty_water_bottle")
	check(bottle[0] != &"" and Consumables.server_use(player, bottle[0], bottle[1]) == "" and String((n.sick as Dictionary).get("id", "")) == "dysentery",
		"drinking it raw, an unlucky roll: dysentery (%s)" % [n.sick])
	var lucky := Needs.fresh()
	Needs.force_roll = 0.99
	Needs.eat(lucky, dirty, {})
	var treated := Needs.fresh()
	Needs.force_roll = 0.0
	Needs.eat(treated, dirty, Needs.treat_water({}))
	Needs.force_roll = -1.0
	check((lucky.sick as Dictionary).is_empty() and (treated.sick as Dictionary).is_empty(), "a lucky roll, or treated water (treat_water), stays well")
	var well := Needs.fresh()
	var sick := Needs.fresh()
	sick.sick = {"id": "dysentery", "left_h": 36.0, "onset_h": 1.0}
	Needs.step(well, 6.0, {})
	Needs.step(sick, 6.0, {})
	check(float(sick.water) < float(well.water) - 0.3 and float(sick.calories) < float(well.calories) - 150.0 and sick.has("_announce"),
		"once it shows, it says so and drains water and calories fast (%.2f vs %.2f l, %.0f vs %.0f kcal)" % [sick.water, well.water, sick.calories, well.calories])
	n.sick = {}
	# Sleep: low sleep dulls the senses and shakes the aim.
	var rested := Needs.fresh()
	var tired := Needs.fresh()
	tired.sleep = 5.0
	check(Needs.dulled(rested) == 0.0 and Needs.dulled(tired) > 0.5 and Needs.sway_mult(tired) > 1.2 and Needs.stamina_mult(tired) < Needs.stamina_mult(rested),
		"short of sleep: dulled %.2f, aim sway x%.2f, stamina x%.2f" % [Needs.dulled(tired), Needs.sway_mult(tired), Needs.stamina_mult(tired)])
	n.sleep = 5.0
	Survival.server_drain(player, 0.1)
	check(Needs.dulled_of(player) > 0.5 and player.vitals.needs_sway > 1.2, "and on the body (dulled %.2f, sway x%.2f)" % [Needs.dulled_of(player), player.vitals.needs_sway])
	# Warmth: a cold wet night out drains it and he shivers; indoors holds it.
	var out := Needs.fresh()
	var inside := Needs.fresh()
	Needs.step(out, 4.0, {"dark": 1.0, "wind": 14.0, "rain": true})
	Needs.step(inside, 4.0, {"dark": 1.0, "wind": 14.0, "rain": true, "indoors": true})
	check(float(out.warmth) < Needs.SHIVER_C and float(out.wet) > 0.5 and Needs.shivering(out) > 0.5 and float(inside.warmth) > float(out.warmth) + 1.0,
		"a stormy night out: soaked and %.1f C (indoors %.1f C)" % [out.warmth, inside.warmth])
	check(Needs.stamina_mult(out) < Needs.stamina_mult(Needs.fresh()) * 0.8, "shivering: stamina comes back slower (x%.2f)" % Needs.stamina_mult(out))
	check(Needs.words(out).warmth in ["freezing", "frozen through"], "in words: %s" % Needs.words(out).warmth)
	# Sleep: the clock runs at speed and sleep fills; a chasing zombie wakes him.
	for zz: Soldier in Survival.zombies(level):
		zz.queue_free()
	var pop := Survival._pop
	Survival._pop = -1000.0
	await get_tree().process_frame
	var hour0: float = Survival.hour()
	var t0 := Survival.day() * 24.0 + Survival.hour()
	Needs.respawn(n, 80.0)
	n.sleep = 20.0
	check(Survival.server_sleep(player, 2.0, "bed") == "" and SurvivalSleep.is_asleep(n), "tired, he lies down in a bed")
	check(is_equal_approx(SurvivalSleep.clock_mult(MapNodes.players(level)), SurvivalSleep.SPEED), "everyone asleep: the world runs at x%.0f" % SurvivalSleep.SPEED)
	Survival.server_tick_survivors(level, 10.0)  # ten real seconds: one world hour at x12
	var passed := Survival.day() * 24.0 + Survival.hour() - t0
	check(passed > 0.9 and float(n.sleep) > 30.0 and SurvivalSleep.is_asleep(n), "ten seconds asleep: %.1f world hours pass and sleep fills (%.0f)" % [passed, n.sleep])
	Survival.server_tick_survivors(level, 15.0)
	check(not SurvivalSleep.is_asleep(n), "the hours up, he wakes (sleep %.0f)" % n.sleep)
	n.sleep = 20.0
	Survival.server_sleep(player, 8.0, "ground")
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd.normalized() * 30.0))
	await get_tree().physics_frame
	var brain: ZombieAI = ZombieAI.of(z) if z else null
	if z:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	if brain:
		brain.mode = ZombieAI.Mode.CHASE
		brain.target = player
	Survival.server_tick_survivors(level, 0.5)
	check(brain != null and SurvivalSleep.is_asleep(n) == false, "one of the dead coming for him wakes him")
	check(Survival.server_sleep(player, 8.0) != "", "and he can't lie down again while it chases")
	if z:
		z.queue_free()
	Survival.state()["hour"] = hour0
	Survival._pop = pop
	# The HUD: small signs only when low, and the body readout names every store.
	Needs.respawn(n, 80.0)
	Survival._send_needs(player)
	var hud: Hud = player._hud
	check(hud != null and hud.needs_text() == "", "fed, watered and rested: no signs on the HUD (%s)" % [hud.needs_text() if hud else "no HUD"])
	n.water = 0.75
	Survival.server_drain(player, 0.1)
	Survival._send_needs(player)
	check(hud != null and hud.needs_text().contains("parched"), "low on water: the HUD says so (%s)" % [hud.needs_text() if hud else "no HUD"])
	if hud:
		hud.body_readout.refresh()
	var text := hud.body_readout.label.text if hud else ""
	check(text.contains("Water: parched") and text.contains("Calories:") and text.contains("Sleep:") and text.contains("Warmth:") and text.contains("Hygiene:"),
		"the body readout lists every store in words (%s)" % text.replace("\n", " | "))
	Needs.respawn(n, 80.0)
	Survival.server_drain(player, 0.1)
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
	await get_tree().process_frame
	# A clear spot, away from the bodies the last section left (a ragdoll at his feet nudges him
	# about: R2608-R2613 saw the pair drift apart between a placing and a strike).
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	player.global_position = level.ground_point(player.global_position + side * 25.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var p0 := player.global_position
	await _seconds(1.0)
	check(player.global_position.distance_to(p0) < 0.3, "standing still on clear ground, he stays put (moved %.2f m in a second)" % player.global_position.distance_to(p0))
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 1.3))
	await get_tree().physics_frame
	z.process_mode = Node.PROCESS_MODE_DISABLED  # (the test drives it)
	var face := func() -> void:
		z.global_position = level.ground_point(player.global_position + fwd * 1.3)
		z.look_at(player.global_position, Vector3.UP)
		z.rotation.x = 0.0
		player.look_at(z.global_position, Vector3.UP)
		player.rotation.x = 0.0
	face.call()
	await get_tree().physics_frame
	var wounds := player.vitals.wound_list().size()
	var front := Melee.target_in_front(z)
	check(front == player, "the bite has him in front of it (%s; %.2f m, z faces %s, to him %s)" % [front, z.global_position.distance_to(player.global_position),
		-z.global_basis.z, (player.global_position - z.global_position).normalized()])
	# The judgement, with the strike's landing given (no timers to race: R2607-R2613).
	var now := Soldier._now()
	Melee.server_block(player, true)
	Melee._land(z, Melee.ZOMBIE_ATTACK, 1.0, now + 0.1)  # a block raised 0.1 s before the landing the windup promised
	check(Melee.staggered(z) and player.vitals.wound_list().size() == wounds, "a block raised just before it lands parries: it staggers, nothing gets through (%s; its %s; wounds %d -> %d)" % [
		Melee.guard_of(player), Melee.guard_of(z), wounds, player.vitals.wound_list().size()])
	check(Soldier._now() < float(Melee.guard_of(player).counter_until), "and the parry opens a counter")
	var pool := z.vitals.undead_pool
	Melee.server_attack(player, {"windup": 0.6, "round_class": Vitals.PISTOL, "energy_j": 300.0, "parts": [Vitals.CHEST], "name": "knife"})
	check(z.vitals.undead_pool < pool and not player.has_meta(&"melee_winding"), "the counter lands at once, twice as hard (pool %.1f -> %.1f)" % [pool, z.vitals.undead_pool])
	Melee.server_block(player, false)
	# A block held a while: a jolt gets through, no parry.
	await _seconds(Melee.STAGGER_S + 0.1)
	Melee.guard_of(player).block_at = Soldier._now() - 1.0
	Melee._land(z, Melee.ZOMBIE_ATTACK, 1.0, Soldier._now())
	check(not Melee.staggered(z), "a block held a while just blocks (no parry)")
	Melee.server_block(player, false)
	# A dodge: nothing lands.
	player.vitals.server_reset_health()
	wounds = player.vitals.wound_list().size()
	check(Melee.server_dodge(player), "a dodge, for stamina")
	Melee._land(z, Melee.ZOMBIE_ATTACK, 1.0, Soldier._now())
	check(player.vitals.wound_list().size() == wounds, "and the bite misses (wounds %d -> %d)" % [wounds, player.vitals.wound_list().size()])
	# And the real thing: a strike wound up on its timer lands on an undefended man.
	await _seconds(Melee.DODGE_IFRAMES_S + 0.1)
	player.remove_meta(Melee.GUARD)
	face.call()
	check(Melee.server_attack(z, Melee.ZOMBIE_ATTACK), "the dead's bite winds up (%.2f s)" % float(Melee.ZOMBIE_ATTACK.windup))
	var land_at := float(z.get_meta(&"melee_winding", 0.0))
	while z.has_meta(&"melee_winding") and Soldier._now() < land_at + 2.0:
		await get_tree().process_frame
	await _seconds(0.1)
	check(player.vitals.wound_list().size() > wounds, "and lands on a man with no guard up (wounds %d -> %d; %.2f m apart)" % [wounds, player.vitals.wound_list().size(), z.global_position.distance_to(player.global_position)])
	z.queue_free()
	player.remove_meta(Melee.GUARD)
	player.vitals.server_reset_health()


func _test_melee_weapons() -> void:
	print("Melee weapons: a bat, a knife, the heavy to the head, the silent kill, the shove")
	for zz: Soldier in Survival.zombies(level):
		zz.queue_free()
	await get_tree().process_frame
	var bat := ItemDB.get_item(&"bat")
	check(bat != null and MeleeWeapons.is_melee(bat) and MeleeWeapons.two_handed(bat) and bat.slot == &"primary", "a baseball bat is a two-handed melee weapon in the primary slot")
	var knife := ItemDB.get_item(&"combat_knife")
	check(knife != null and MeleeWeapons.is_blade(knife) and knife.slot == &"sidearm", "the combat knife a one-handed blade in the sidearm slot")
	var model := VoxelArt.model_for(bat) if bat else ""
	check(model.begins_with("melee:bat:") and not VoxelArt.hand_points(model).is_empty() and VoxelArt._spec(model).boxes.size() >= 3, "and the bat has a model with hand points (%s)" % model)
	check(MeleeWeapons.profile(bat, true).heavy and MeleeWeapons.profile(bat, true).energy_j >= MeleeWeapons.HEAD_ONE_HIT_J and MeleeWeapons.profile(bat, false).energy_j < MeleeWeapons.HEAD_ONE_HIT_J,
		"its heavy is hard enough for the head, its light is not (%.0f / %.0f J)" % [MeleeWeapons.profile(bat, true).energy_j, MeleeWeapons.profile(bat, false).energy_j])
	# Up with the bat.
	check(player.inventory.take(&"bat") == 1 and player.inventory.slots.get(&"primary", &"") == &"bat", "taking a bat puts it in the primary slot (%s)" % player.inventory.slots.get(&"primary", &""))
	player.select_weapon(&"primary")
	check(MeleeWeapons.is_melee(player.active_weapon()), "and it is the weapon in hand")
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var place := func(zz: Soldier, dist: float, facing_away: bool) -> void:
		zz.global_position = level.ground_point(player.global_position + fwd * dist)
		if facing_away:
			zz.look_at(zz.global_position + fwd * 5.0, Vector3.UP)
		else:
			zz.look_at(player.global_position, Vector3.UP)
		zz.rotation.x = 0.0
		player.look_at(zz.global_position, Vector3.UP)
		player.rotation.x = 0.0
		# His eyes on its head (Melee._part_for: a swing lands where he looks).
		var head := zz.global_position + Vector3.UP * 1.62
		var eye := player.camera.global_position
		var flat := Vector2(head.x - eye.x, head.z - eye.z).length()
		player.set_pitch(atan2(head.y - eye.y, flat))
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 1.3))
	await get_tree().physics_frame
	z.process_mode = Node.PROCESS_MODE_DISABLED
	place.call(z, 1.3, false)
	await get_tree().physics_frame
	check(Melee._part_for(player, z, Vitals.CHEST) == Vitals.HEAD, "looking at its head, a swing goes there")
	# A light swing: stamina spent, a share of the pool from the head, not its life.
	player.remove_meta(Melee.GUARD)
	player.movement.stamina = 1.0
	var pool := z.vitals.undead_pool
	MeleeWeapons.server_action(player, "light")
	check(player.has_meta(&"melee_winding") and player.movement.stamina < 1.0, "a light swing winds up and costs stamina (%.2f)" % player.movement.stamina)
	var land_at := float(player.get_meta(&"melee_winding", 0.0))
	while player.has_meta(&"melee_winding") and Soldier._now() < land_at + 2.0:
		await get_tree().process_frame
	await _seconds(0.1)
	check(z.vitals.is_up() and z.vitals.undead_pool <= pool - Vitals.UNDEAD_POOL * MeleeWeapons.HEAD_LIGHT_SHARE + 0.01, "a light to a walker's head takes a share of the pool, not its life (pool %.1f -> %.1f)" % [pool, z.vitals.undead_pool])
	# A heavy to the head drops it.
	place.call(z, 1.3, false)
	MeleeWeapons.server_action(player, "heavy")
	land_at = float(player.get_meta(&"melee_winding", 0.0))
	while player.has_meta(&"melee_winding") and Soldier._now() < land_at + 2.0:
		await get_tree().process_frame
	await _seconds(0.1)
	check(z.vitals.is_dead(), "a heavy to the head drops it (%s)" % z.vitals.last_cause.get("cause", "still up"))
	z.queue_free()
	await get_tree().process_frame
	# The silent kill: behind an unaware one with a blade (the starter knife on the rig counts).
	player.set_pitch(0.0)
	var quiet := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 1.2))
	await get_tree().physics_frame
	quiet.process_mode = Node.PROCESS_MODE_DISABLED
	place.call(quiet, 1.2, true)
	await get_tree().physics_frame
	check(Melee.silent_kill_target(player) == quiet, "behind an unaware zombie within reach, the silent kill is on offer (%.2f m)" % quiet.global_position.distance_to(player.global_position))
	MeleeWeapons.server_action(player, "silent")
	check(player._server_busy_until > Soldier._now() + 1.0, "it takes %.0f s with the hands on it" % MeleeWeapons.SILENT_KILL_S)
	await _seconds(MeleeWeapons.SILENT_KILL_S + 0.4)
	check(quiet.vitals.is_dead() and String(quiet.vitals.last_cause.get("cause", "")) == "head", "and the blade goes in quietly (%s; %.2f m apart)" % [quiet.vitals.last_cause.get("cause", "still up"), quiet.global_position.distance_to(player.global_position)])
	quiet.queue_free()
	await get_tree().process_frame
	# The shove with a gun up: a second bought.
	check(player.inventory.take(&"m17") == 1, "a pistol for the sidearm slot")
	player.select_weapon(&"sidearm")
	var shoved := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 1.1))
	await get_tree().physics_frame
	shoved.process_mode = Node.PROCESS_MODE_DISABLED
	place.call(shoved, 1.1, false)
	await get_tree().physics_frame
	MeleeWeapons.server_action(player, "quick")
	land_at = float(player.get_meta(&"melee_winding", 0.0))
	while player.has_meta(&"melee_winding") and Soldier._now() < land_at + 2.0:
		await get_tree().process_frame
	check(Melee.staggered(shoved) and shoved.vitals.is_up(), "the quick melee with a gun up shoves it back a second, no more (%.2f m apart)" % shoved.global_position.distance_to(player.global_position))
	shoved.queue_free()
	# The slots as they were: the death test takes a rifle into the primary.
	player.inventory.unequip(&"primary")
	player.inventory.unequip(&"sidearm")
	player.select_weapon(&"primary")
	player.set_pitch(0.0)
	player.vitals.server_reset_health()


func _test_stealth() -> void:
	print("Stealth: awareness by sight, sound and smell; the eye and the ring")
	for zz: Soldier in Survival.zombies(level):
		zz.queue_free()
	await get_tree().process_frame
	player.vitals.server_reset_health()
	player.watched_until = -1.0
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Sight: one 8 m in front by day turns alert first (it stops and faces him), then comes.
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 8.0))
	await get_tree().physics_frame
	var brain := ZombieAI.of(z)
	check(brain != null and brain.mode == ZombieAI.Mode.IDLE and brain.unaware(), "one 8 m off starts idle, unaware")
	var alert := await _wait_for(func() -> bool: return brain.mode == ZombieAI.Mode.ALERT, 3.0)
	check(alert and brain.awareness >= ZombieAI.ALERT_AT and brain.aware_of == player, "it sees him and turns alert (awareness %.2f, %s)" % [brain.awareness, brain.state_name()])
	check(not brain.unaware(), "an alert one is no longer unaware (no silent kill)")
	var chase := await _wait_for(func() -> bool: return brain.mode == ZombieAI.Mode.CHASE, 4.0)
	check(chase and brain.target == player, "then its awareness fills and it comes for him (%s)" % brain.state_name())
	check(player.watched_until > Soldier._now() - 0.1, "and he knows he's watched (the HUD's eye)")
	z.queue_free()
	await get_tree().process_frame
	# Sound: a quiet step is a little, a shot is everything.
	var far := Survival.server_spawn_zombie(level, level.ground_point(player.global_position - fwd * 60.0))
	await get_tree().physics_frame
	far.process_mode = Node.PROCESS_MODE_DISABLED
	brain = ZombieAI.of(far)
	brain.hear(player.global_position, ZombieAI.HEAR_STEP)
	check(brain.mode == ZombieAI.Mode.INVESTIGATE and brain.awareness < ZombieAI.ALERT_AT, "a step heard: it goes to look, not yet alert (awareness %.2f)" % brain.awareness)
	brain.hear(player.global_position, ZombieAI.HEAR_SHOT)
	check(brain.awareness >= 1.0, "a shot heard: its awareness fills at once (%.2f)" % brain.awareness)
	far.queue_free()
	# The ring: his own shot shows on his HUD how far it carried.
	player.noise_at = -100.0
	Survival.server_noise(player, player.global_position, ZombieAI.SHOT_HEARD_M)
	await get_tree().process_frame
	check(is_equal_approx(player.noise_radius, ZombieAI.SHOT_HEARD_M) and Soldier._now() - player.noise_at < 1.0, "his own noise shows on his HUD as the ring (%.0f m)" % player.noise_radius)
	# Footsteps: a man running is heard by the dead STEP_M away, a crouched one hardly.
	player.noise_at = -100.0
	player.velocity = fwd * 4.0
	player.movement.is_sprinting = true
	Survival._footsteps(level)
	check(is_equal_approx(player.noise_radius, Survival.STEP_M.sprint * DayNight.hearing_x()), "a sprinting man's steps carry %.0f m (%.0f)" % [Survival.STEP_M.sprint * DayNight.hearing_x(), player.noise_radius])
	player.movement.is_sprinting = false
	player.velocity = Vector3.ZERO
	# Smell: bleeding, he's smelt downwind within SMELL_M.
	var sniffer := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 60.0))
	await get_tree().physics_frame
	sniffer.process_mode = Node.PROCESS_MODE_DISABLED
	brain = ZombieAI.of(sniffer)
	check(brain._smell() == null, "clean and far, nobody is smelt")
	var wind := DayNight.wind()
	var downwind := wind.normalized() if wind.length() >= ZombieAI.CALM_MPS else fwd
	sniffer.global_position = level.ground_point(player.global_position + downwind * 12.0)
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.PISTOL, "energy_j": 200.0})
	check(player.smell_strength() > 0.0, "bleeding, he smells of blood (%.1f)" % player.smell_strength())
	check(brain._smell() == player, "and one 12 m downwind smells him (wind %.1f m/s)" % wind.length())
	sniffer.queue_free()
	player.vitals.server_reset_health()
	player.watched_until = -1.0


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
