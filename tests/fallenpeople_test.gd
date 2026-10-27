extends Node
## Contractor: Fallen's people (docs/survival_people.md, phase B): a new world places lone
## survivors (records, and bodies within range of a player); the talk menu's lines are picked by
## tags (a scared survivor and a cocky one); an unmet want refuses, a met one (an item, cash)
## joins as a companion (SquadAI on the players' squad, following); moodlets move the mood and a
## hungry gloomy one breaks into a desertion that makes a lone survivor again; a companion refuses
## a move into a horde and the loyal obey a second order; a grave eases the grief; a companion
## killed by the dead rises unless buried, and putting them down is a moodlet; after a player's
## death the newcomer is a stranger, and taking over a companion swaps the record; holding or
## fleeing (call 143): an armed household with a guard holds against the dead, an unarmed one
## gathers its child and runs (the place abandoned, a note left, the journal), its refugees come
## home when it's clear, "It's clear now" brings them back, and a settlement with no guard on shift
## sends its unarmed to shelter, not out; save and Continue keep the companions.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer
var a_rec: Dictionary  # a companion hired for an item (antibiotics)
var b_rec: Dictionary  # a companion hired for cash


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("FALLENPEOPLE TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null and layer != null:
		await _test_placed()
		_test_lines()
		await _test_unmet_want()
		await _test_join()
		await _test_moods_and_desertion()
		await _test_horde_refusal()
		await _test_grief_grave_rise()
		await _test_player_death_and_take_over()
		await _test_holding()
		await _test_save_and_continue()
	_finish()


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_fallenpeople" + tag, 4321), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	layer = SurvivorsLayer.find(level)
	check(player != null and layer != null, "the survivor is in, and the zone has its people layer")
	if player:
		player.inventory.take(&"pack_daypack_20")  # (room for what the tests hand him)
	if layer:
		await _wait_for(func() -> bool: return layer._started, 30.0)
		check(layer._started, "the people layer started with the zone")


func _test_placed() -> void:
	print("Lone survivors placed by the seed")
	var zone := String(Survival.state().zone)
	var mine := SurvivorsLayer.records().values().filter(func(r: Dictionary) -> bool: return String(r.zone) == zone and String(r.status) == "out_there" and not Children.is_child_rec(r))  # (children: families and orphans on top, call 128)
	check(mine.size() >= SurvivorsLayer.PER_ZONE.x and mine.size() <= SurvivorsLayer.PER_ZONE.y + SurvivorsLayer.VILLAGE_BONUS_MAX,
		"a new zone has %d lone survivors (records)" % mine.size())
	var ok := true
	var near := 0
	for r: Dictionary in mine:
		var d := SurvivorPerson.pos_of(r).distance_to(player.global_position)
		var body := layer.body_of(String(r.id))
		if d <= SurvivorsLayer.LIVE_M - 5.0:
			near += 1
			ok = ok and body != null
		elif d > SurvivorsLayer.DESPAWN_M + 5.0:
			ok = ok and body == null
	check(ok, "those within range of the player are bodies, the far ones only records (%d near)" % near)
	var r0: Dictionary = mine[0] if not mine.is_empty() else {}
	if r0.is_empty():
		return
	var start := player.global_position
	player.global_position = level.ground_point(SurvivorPerson.pos_of(r0) + Vector3(6.0, 0.0, 0.0)) + Vector3.UP * 0.2
	await _wait_for(func() -> bool: return layer.body_of(String(r0.id)) != null, 8.0)
	var body := layer.body_of(String(r0.id))
	check(body != null and Person.kind_of(body) == &"survivor" and body.faction == Person.FACTION, "walk up to one and they're there: a person, kind survivor")
	check(body != null and InteractionMenu.target_kind(player, body) == TalkMenu.KIND, "the interaction menu sees a survivor")
	player.global_position = start + Vector3.UP * 0.2
	await _frames(10)


func _near(off: Vector3) -> Vector3:
	return level.ground_point(player.global_position + off)


func _test_lines() -> void:
	print("Lines by tag")
	var scared := layer.server_add_person(_near(Vector3(2.0, 0.0, 6.0)), {"traits": ["timid"], "want": {"kind": "place"}})
	var cocky := layer.server_add_person(_near(Vector3(-2.0, 0.0, 6.0)), {"traits": ["brave", "hot_headed"], "want": {"kind": "place"}})
	var ls := TalkMenu.pick_line("greet", TalkMenu.tags_of(scared))
	var lc := TalkMenu.pick_line("greet", TalkMenu.tags_of(cocky))
	check("scared" in (ls.get("tags", []) as Array), "a scared survivor greets scared: \"%s\"" % ls.get("text", ""))
	check("cocky" in (lc.get("tags", []) as Array), "a cocky one greets cocky: \"%s\"" % lc.get("text", ""))
	var said := TalkMenu.line_for(scared, "want")
	check(said != "" and not said.contains("{"), "and the lines fill in (\"%s\")" % said)
	for r: Dictionary in [scared, cocky]:
		r.status = "settler"  # (out of the way of what follows)
		var b := layer.body_of(String(r.id))
		if b:
			b.queue_free()


func _test_unmet_want() -> void:
	print("A want unmet")
	a_rec = layer.server_add_person(_near(Vector3(1.5, 0.0, 0.0)), {"traits": ["calm", "kind"], "want": {"kind": "item", "what": "antibiotics", "id": "antibiotics", "count": 1, "text": "a box of antibiotics"}})
	var body := layer.body_of(String(a_rec.id))
	check(body != null, "a survivor stands by the player")
	if body == null:
		return
	while player.inventory.count_of(&"antibiotics") > 0:
		player.inventory.remove_one(&"antibiotics")
	var want := TalkMenu.server_talk(layer, player, body, "want")
	check(want.contains("antibiotics"), "asked, they say what they want (\"%s\")" % want)
	var no := TalkMenu.server_talk(layer, player, body, "recruit")
	check(String(a_rec.status) == "out_there" and no != "", "without it they won't come (\"%s\")" % no)
	await _frames(2)


func _test_join() -> void:
	print("A want met: they join")
	var body := layer.body_of(String(a_rec.id))
	check(player.inventory.take(&"antibiotics", 1) == 1, "the player has a box of antibiotics now")
	var yes := TalkMenu.server_talk(layer, player, body, "recruit")
	await _frames(3)
	var c := layer.body_of(String(a_rec.id))
	check(String(a_rec.status) == "companion" and c != null and c.faction == &"friendly", "with the antibiotics handed over they join (\"%s\")" % yes)
	check(player.inventory.count_of(&"antibiotics") == 0 and a_rec.kit.any(func(e: Dictionary) -> bool: return String(e.id) == "antibiotics"), "the antibiotics are theirs now")
	var brain: SquadAI = SquadAI.of(c) if c else null
	check(brain != null and brain.squad == level.squad_for(&"friendly") and brain.order == Squad.Order.FOLLOW and CompanionAI.of(c) != null,
		"a squadmate: SquadAI on the players' squad, following, a CompanionAI beside it")
	check(c != null and c.person_name == String(a_rec.name) and is_same(Survival.needs_of(c), a_rec.needs), "the same person: their name, their needs dictionary")
	var acts := InteractionMenu.actions_for(player, c).map(func(x: Dictionary) -> String: return String(x.id))
	check(acts.has("talk_how") or InteractionMenu.grouped(InteractionMenu.actions_for(player, c)).size() > 0, "a companion keeps the squadmate's menu and adds How are you (%s)" % [acts])
	level.rebalance_squad()
	await _frames(2)
	check(layer.body_of(String(a_rec.id)) != null and not layer.body_of(String(a_rec.id)).is_queued_for_deletion(), "the squad's rebalance leaves a companion be")
	# Following.
	if c:
		var from := player.global_position
		player.global_position = _near(Vector3(14.0, 0.0, 0.0)) + Vector3.UP * 0.2
		var d0 := c.global_position.distance_to(player.global_position)
		await _wait_for(func() -> bool: return c.global_position.distance_to(player.global_position) < d0 - 4.0, 15.0)
		check(c.global_position.distance_to(player.global_position) < d0 - 4.0, "and they follow (%.0f m -> %.0f m)" % [d0, c.global_position.distance_to(player.global_position)])
		player.global_position = from + Vector3.UP * 0.2
	# Cash.
	b_rec = layer.server_add_person(_near(Vector3(-1.5, 0.0, 0.0)), {"traits": ["optimist", "hard_worker"], "want": {"kind": "money", "amount": 300}})
	var bb := layer.body_of(String(b_rec.id))
	player.inventory.take(&"cash_bundle", 1)
	var short := TalkMenu.server_talk(layer, player, bb, "recruit")
	check(String(b_rec.status) == "out_there", "$250 isn't the $300 asked (\"%s\")" % short)
	player.inventory.take(&"cash_bundle", 1)
	TalkMenu.server_talk(layer, player, bb, "recruit")
	await _frames(3)
	check(String(b_rec.status) == "companion" and TalkMenu.cash_of(player) == 0, "$500 in bundles is, and it's handed over")


func _test_moods_and_desertion() -> void:
	print("Moods and a break")
	var c_rec := layer.server_add_person(_near(Vector3(0.0, 0.0, 1.5)), {"traits": ["gloomy", "fickle"], "want": {"kind": "place"}})
	var cb := layer.body_of(String(c_rec.id))
	TalkMenu.server_talk(layer, player, cb, "recruit")
	await _frames(3)
	check(String(c_rec.status) == "companion", "a gloomy, fickle one joins for a bed (the safehouse)")
	var m0 := Moods.mood(c_rec)
	Moods.add(c_rec, "ate_hot")
	check(is_equal_approx(Moods.mood(c_rec), m0 + 6.0), "a hot meal: +6 (%.0f -> %.0f)" % [m0, Moods.mood(c_rec)])
	var n: Dictionary = c_rec.needs
	n.hunger = 10.0  # (S1's write-through: 250 kcal left)
	Needs.step(n, 0.01, {})
	var m1 := Moods.mood(c_rec)
	Moods.from_needs(c_rec, n)
	check(Moods.has(c_rec, "hungry") or Moods.has(c_rec, "starving"), "hungry: a moodlet while it holds")
	check(Moods.mood(c_rec) < m1, "and the mood falls (%.0f -> %.0f)" % [m1, Moods.mood(c_rec)])
	var w := Moods.break_weights(c_rec, true)
	var heaviest: String = w.keys().reduce(func(acc: String, k: String) -> String: return k if float(w[k]) > float(w[acc]) else acc, "crying")
	check(heaviest == "desertion" and is_zero_approx(float(Moods.break_weights(c_rec, false).desertion)), "gloomy and fickle lean to desertion, never by day (%s)" % [w])
	c_rec["mood_forced"] = 10.0
	c_rec["low_hours"] = Moods.BREAK_AFTER_H
	var hour_was := Survival.hour()
	Survival.state()["hour"] = 22.5
	Moods.force_roll = 0.0
	layer.server_hour()
	Moods.force_roll = -1.0
	Survival.state()["hour"] = hour_was
	c_rec.erase("mood_forced")
	await _frames(3)
	check(String(c_rec.status) == "out_there" and SurvivorsLayer.record(String(c_rec.id)) == c_rec, "under the break line long enough, at night, they desert: a lone survivor again, the same record")
	check(layer.body_of(String(c_rec.id)) == null or Person.kind_of(layer.body_of(String(c_rec.id))) == &"survivor", "the companion's body is gone")
	check(SurvivorPerson.pos_of(c_rec).distance_to(player.global_position) > SurvivorsLayer.DESERT_M.x - 15.0, "they're off somewhere else (%.0f m)" % SurvivorPerson.pos_of(c_rec).distance_to(player.global_position))


func _test_horde_refusal() -> void:
	print("A bad order")
	var a := layer.body_of(String(a_rec.id))
	var b := layer.body_of(String(b_rec.id))
	if a == null or b == null:
		check(false, "two companions to order")
		return
	a_rec.loyalty = 70.0
	b_rec.loyalty = 10.0
	b_rec.traits = ["optimist", "hard_worker"]
	var goal := _near(Vector3(0.0, 0.0, -35.0))
	var dead: Array = []
	for i in 4:
		var z := Survival.server_spawn_zombie(level, level.ground_point(goal + Vector3(i * 1.5, 0.0, 1.0)))
		if z:
			for c in z.get_children():
				if c is ZombieAI:
					c.process_mode = Node.PROCESS_MODE_DISABLED
			dead.append(z)
	await _frames(2)
	var squad := level.squad_for(&"friendly")
	if SquadAI.of(a) == null or SquadAI.of(b) == null:
		check(false, "the companions have their brains")
		return
	CompanionAI.force_roll = 0.0
	squad.give_order(player, Squad.Order.MOVE, goal, PackedStringArray([String(a.name)]))
	check(SquadAI.of(a).order == Squad.Order.FOLLOW, "ordered into %d of the dead, they refuse" % dead.size())
	squad.give_order(player, Squad.Order.MOVE, goal, PackedStringArray([String(a.name)]))
	check(SquadAI.of(a).order == Squad.Order.MOVE, "a second order within the minute: the loyal one goes")
	squad.give_order(player, Squad.Order.MOVE, goal, PackedStringArray([String(b.name)]))
	squad.give_order(player, Squad.Order.MOVE, goal, PackedStringArray([String(b.name)]))
	check(SquadAI.of(b).order == Squad.Order.FOLLOW, "the one who isn't loyal refuses again")
	check(layer.said.any(func(s: Dictionary) -> bool: return String(s.id) == String(b_rec.id)), "and says so")
	CompanionAI.force_roll = -1.0
	var clear := _near(Vector3(0.0, 0.0, 30.0))
	squad.give_order(player, Squad.Order.MOVE, clear, PackedStringArray([String(b.name)]))
	check(SquadAI.of(b).order == Squad.Order.MOVE, "a move nowhere near the dead is just done")
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position, PackedStringArray())
	for z: Soldier in dead:
		z.queue_free()
	await _frames(2)


func _test_grief_grave_rise() -> void:
	print("Death, grief, graves and the rise")
	SurvivorPerson.change_relation(a_rec, String(b_rec.id), 50.0)
	SurvivorPerson.change_relation(b_rec, String(a_rec.id), 50.0)
	var b := layer.body_of(String(b_rec.id))
	b.vitals.server_kill()
	await _frames(3)
	var bid := String(b_rec.id)
	check(String(b_rec.status) == "dead" and not bool(b_rec.killed_by_dead), "a companion dies (not by the dead)")
	check(Moods.has(a_rec, "friend_died:" + bid) and Moods.has(a_rec, "body_left_out:" + bid), "their friend grieves, and the body lies out")
	check(layer.body_of(bid) != null and InteractionMenu.actions_for(player, layer.body_of(bid)).any(func(x: Dictionary) -> bool: return String(x.id) == "talk_bury"), "the body offers Bury")
	var grief := Moods.value_of(a_rec, "friend_died:" + bid)
	var before := Moods.mood(a_rec)
	check(layer.server_bury(player, layer.body_of(bid)), "buried")
	await _frames(2)
	check(Moods.value_of(a_rec, "friend_died:" + bid) > grief and Moods.has(a_rec, "grave_for_friend:" + bid) and not Moods.has(a_rec, "body_left_out:" + bid),
		"the grave eases the grief (%.0f -> %.0f) and there's a grave moodlet" % [grief, Moods.value_of(a_rec, "friend_died:" + bid)])
	check(Moods.mood(a_rec) > before, "the friend's mood lifts (%.0f -> %.0f)" % [before, Moods.mood(a_rec)])
	check(layer.graves.size() == 1 and layer.graves_node.get_child_count() >= 1 and (Survival.state().get(SurvivorsLayer.GRAVES_KEY, []) as Array).size() == 1, "a grave marker, saved with the world")
	# The rise.
	var d_rec := layer.server_add_person(_near(Vector3(1.5, 0.0, 1.5)), {"traits": ["calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(d_rec.id)), "recruit")
	var e_rec := layer.server_add_person(_near(Vector3(-1.5, 0.0, 1.5)), {"traits": ["calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(e_rec.id)), "recruit")
	await _frames(3)
	for r: Dictionary in [d_rec, e_rec]:
		var s := layer.body_of(String(r.id))
		if s:
			s.set_meta(&"killed_by_dead", true)
			s.vitals.server_kill()
	await _frames(3)
	check(bool(d_rec.get("killed_by_dead", false)) and float(d_rec.get("rise_at", 0.0)) > 0.0, "killed by the dead: they'll rise")
	layer.server_bury(player, layer.body_of(String(e_rec.id)))
	var zs_before := Survival.zombies(level).size()
	var later := Soldier._now() + SurvivorsLayer.RISE_S + 1.0
	layer._check_rise(d_rec, later)
	layer._check_rise(e_rec, later)
	await _frames(3)
	var risen := Survival.zombies(level).filter(func(z: Soldier) -> bool: return String(z.get_meta(&"risen_id", "")) == String(d_rec.id))
	check(risen.size() == 1 and bool(d_rec.risen) and layer.body_of(String(d_rec.id)) == null, "unburied, they rise in their kit, the body gone")
	check(not bool(e_rec.get("risen", false)) and Survival.zombies(level).size() == zs_before + 1, "buried, they don't")
	if not risen.is_empty():
		var z: Soldier = risen[0]
		check(Survival.kit_of(z.inventory).any(func(e: Dictionary) -> bool: return String(e.id) == "beans_tin"), "the risen carry what they had")
		z.vitals.server_kill()
		await _frames(3)
		check(Moods.has(a_rec, "put_down_friend:" + String(d_rec.id)), "putting them down is its own moodlet")


func _test_player_death_and_take_over() -> void:
	print("A player's death and the take-over")
	var profile := Survival.profile_of(player)
	a_rec["mood_forced"] = 70.0
	a_rec.loyalty = 70.0
	SurvivorPerson.change_opinion(a_rec, profile, 50.0)
	player.server_end_spawn_protection()
	player.vitals.server_kill()
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING and player.vitals.is_up(), 25.0)
	await _frames(5)
	check(is_zero_approx(SurvivorPerson.opinion_of(a_rec, profile)) and float(a_rec.loyalty) <= SurvivorsLayer.NEWCOMER_LOYALTY, "the newcomer is a stranger to the companion (opinion 0, loyalty %.0f)" % float(a_rec.loyalty))
	check(Moods.has(a_rec, "friend_died:" + profile), "who grieves the one who led them")
	check(String(a_rec.get("take_over_ok", "")) == profile, "and was willing to be taken over")
	var a := layer.body_of(String(a_rec.id))
	check(layer.server_take_over(player, String(a_rec.id)), "the player takes over the companion")
	await _frames(3)
	check(Survival.survivor_name(player) == String(a_rec.name) and String(a_rec.status) == "player", "the record swaps: he's %s now" % Survival.survivor_name(player))
	check(not is_instance_valid(a) or a.is_queued_for_deletion(), "the companion's body is gone")
	check(player.inventory.count_of(&"antibiotics") >= 1, "and their kit is his")
	a_rec.erase("mood_forced")


func _clear_dead_near(at: Vector3, r: float) -> void:
	for z: Soldier in Survival.zombies(level):
		if z.vitals.is_up() and z.global_position.distance_to(at) <= r:
			z.vitals.server_kill()
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if (d.pos as Vector2).distance_to(Vector2(at.x, at.z)) <= r:
				d.alive = false


func _test_holding() -> void:
	print("Holding or fleeing (call 143)")
	var back_to := player.global_position
	if Settlement.exists():  # (out in the fields, away from the players' farm)
		player.global_position = level.ground_point(Settlement.pos() + Vector3(140.0, 0.0, 0.0)) + Vector3.UP * 0.2
		await _frames(5)
	_clear_dead_near(player.global_position, 150.0)
	await _frames(3)
	var zone := String(Survival.state().zone)
	# An armed household with a guard holds.
	var home2 := _near(Vector3(-35.0, 0.0, 0.0))
	var gu := layer.server_add_person(home2, {"traits": ["brave", "calm"], "want": {"kind": "place"}, "family": "hold_fam", "guard": true, "kit": [{"id": "akm", "count": 1}]})
	var gw := layer.server_add_person(level.ground_point(home2 + Vector3(0.0, 0.0, 1.5)), {"traits": ["calm", "kind"], "want": {"kind": "place"}, "family": "hold_fam", "kit": []})
	var zs: Array[Soldier] = []
	for i in 2:
		var z := Survival.server_spawn_zombie(level, level.ground_point(home2 + Vector3(-9.0, 0.0, -2.0 + i * 4.0)))
		if z:
			zs.append(z)
	await _frames(2)
	var s2 := Holding.household_strength([gu, gw], layer)
	Holding.server_tick(layer, Survival.zombies(level))
	check(zs.size() == 2 and not gu.has("flee") and not gw.has("flee") and String(gu.get("refugee_from", "")) == "",
		"an armed household with a guard holds (strength %.1f against %.1f)" % [s2, zs.size() * Holding.WALKER_THREAT])
	for z: Soldier in zs:
		z.vitals.server_kill()
	await _frames(2)
	# An unarmed household of three (two adults, their child) with the dead at the fence runs.
	var home := _near(Vector3(0.0, 0.0, 35.0))
	var ma := layer.server_add_person(home, {"traits": ["calm", "kind"], "want": {"kind": "place"}, "family": "flee_fam", "age": 66, "kit": [{"id": "beans_tin", "count": 1}]})
	var pa := layer.server_add_person(level.ground_point(home + Vector3(1.5, 0.0, 0.0)), {"traits": ["calm", "kind"], "want": {"kind": "place"}, "family": "flee_fam", "age": 38, "kit": []})
	var kid := Children.server_add_child(layer, level.ground_point(home + Vector3(-1.0, 0.0, 1.0)), {"family": "flee_fam", "guardian": String(ma.id), "age": 8})
	var journal0 := (Survival.state().get("journal", []) as Array).size()
	zs.clear()
	for i in 2:
		var z := Survival.server_spawn_zombie(level, level.ground_point(home + Vector3(-2.0 + i * 4.0, 0.0, 10.0)))
		if z:
			zs.append(z)
	await _frames(2)
	var s1 := Holding.household_strength([ma, pa, kid], layer)
	var pb := layer.body_of(String(pa.id))
	var mb := layer.body_of(String(ma.id))
	Holding.server_tick(layer, Survival.zombies(level))
	var key := String(ma.get("refugee_from", ""))
	var e := Holding.entry(key)
	check(zs.size() == 2 and ma.has("flee") and pa.has("flee") and kid.has("flee") and String(kid.get("refugee_from", "")) == key and key != "",
		"an unarmed household (strength %.1f against %.1f) breaks: all three run, the child with them" % [s1, zs.size() * Holding.WALKER_THREAT])
	var f: Dictionary = pa.get("flee", {})
	var to := Holding._v3(f.get("to", []))
	var dead_c := (zs[0].global_position + zs[-1].global_position) * 0.5 if not zs.is_empty() else home
	var away := Vector2(home.x - dead_c.x, home.z - dead_c.z).normalized()
	check(not f.is_empty() and Holding._bearing_toward(home, to, away) <= Holding.TOWARD_DEAD and (f.get("route", []) as Array).size() >= 1 and (kid.get("flee", {}) as Dictionary).get("to") == f.get("to"),
		"away from the dead, by the road, to %s (%s)" % [String(f.get("label", "?")), String(f.get("kind", "?"))])
	check(not e.is_empty() and String(e.state) == "abandoned" and "handwritten_note" in (e.get("left", []) as Array) and (e.get("left", []) as Array).size() >= 2,
		"the place is abandoned: things dropped, a note (%s)" % str(e.get("left", [])))
	var lines := (Survival.state().get("journal", []) as Array).slice(journal0).map(func(j: Dictionary) -> String: return String(j.get("text", "")))
	check(lines.any(func(t: String) -> bool: return t.contains(" left their ") and t.contains("to the dead")), "the journal notes it: \"%s\"" % String(e.get("text", "")))
	check(layer.said.slice(-6).any(func(d: Dictionary) -> bool: return String(d.text) in Holding.FLEE_LINES), "someone shouts a warning")
	check(mb != null and zs.any(func(z: Soldier) -> bool: return ZombieAI.of(z) != null and ZombieAI.of(z).target == mb), "the dead go after the slowest (%s, %d)" % [String(ma.name), int(ma.age)])
	var p0 := pb.global_position if pb else Vector3.ZERO
	await _wait_for(func() -> bool: return pb == null or not is_instance_valid(pb) or pb.global_position.distance_to(p0) > 4.0, 6.0)
	check(pb != null and (not is_instance_valid(pb) or pb.global_position.distance_to(p0) > 4.0), "and they're running")
	for r: Dictionary in [ma, pa, kid]:
		if r.has("flee") and String(r.status) == "out_there":
			Holding.arrive(layer, r)
	var alive := [ma, pa, kid].filter(func(r: Dictionary) -> bool: return String(r.status) == "out_there")
	check(not alive.is_empty() and alive.all(func(r: Dictionary) -> bool: return not r.has("flee") and String(r.get("refugee_from", "")) == key),
		"arrived, they're refugees where they ran (%s)" % String(Holding.entry(key).get("where", "")))
	# Cleared: they come home after a day or so.
	_clear_dead_near(home, 60.0)
	await _frames(2)
	Holding.server_hour(layer)
	e = Holding.entry(key)
	check(float(e.get("clear_since", -1.0)) >= 0.0 and String(e.state) == "abandoned", "the place is clear; they wait")
	e["clear_since"] = Holding._now_d() - Holding.RETURN_DAYS - 0.05
	Holding.save(e)
	_clear_dead_near(home, 60.0)
	var st0 := String(Holding.entry(key).get("state", ""))
	var back := Holding.server_hour(layer)
	if back == 0 and st0 != "abandoned":
		print("  (the place was %s before the hour)" % st0)
	check(back >= 1 and String(Holding.entry(key).state) == "reclaimed" and alive.all(func(r: Dictionary) -> bool: return String(r.get("refugee_from", "")) == "" and String(r.zone) == zone and SurvivorPerson.pos_of(r, "home").distance_to(home) < 4.0),
		"%d came home when it was clear (%s)" % [back, str([ma, pa, kid].map(func(r: Dictionary) -> String: return "%s %s %s" % [String(r.status), String(r.get("refugee_from", "")) == key, String(r.zone) == zone]))])
	# "It's clear now".
	var there := _near(Vector3(25.0, 0.0, -25.0))
	var key2 := "h:test:clear_now"
	var rf := layer.server_add_person(_near(Vector3(1.5, 0.0, 1.5)), {"traits": ["calm"], "want": {"kind": "place"}, "refugee_from": key2})
	Holding.save({"key": key2, "zone": zone, "pos": Holding._arr(there), "ids": [String(rf.id)], "names": [String(rf.name)], "refugees": [String(rf.id)],
		"state": "abandoned", "word": "farm", "text": "%s left his farm to the dead" % String(rf.name), "clear_since": -1.0})
	await _frames(2)
	var rb := layer.body_of(String(rf.id))
	if rb:
		layer._set_known(rb, rf)
	var acts: Array = []
	if rb:
		acts = TalkMenu.actions_for(player, rb, TalkMenu.KIND)
	check(acts.any(func(a: Dictionary) -> bool: return a.id == &"talk_clear_now"), "a refugee can be told \"It's clear now\"")
	_clear_dead_near(there, 60.0)
	var op0 := SurvivorPerson.opinion_of(rf, Survival.profile_of(player))
	var said := TalkMenu.server_talk(layer, player, rb, "clear_now") if rb else ""
	check(said == Holding.CLEAR_YES and String(Holding.entry(key2).state) == "reclaimed" and SurvivorPerson.opinion_of(rf, Survival.profile_of(player)) > op0 and String(rf.get("refugee_from", "")) == "",
		"told, they go home and think better of you (%.0f -> %.0f)" % [op0, SurvivorPerson.opinion_of(rf, Survival.profile_of(player))])
	player.global_position = back_to + Vector3.UP * 0.2
	await _frames(5)
	# The players' settlement: no guard on shift, the unarmed to shelter, not out.
	await _wait_for(func() -> bool: return Settlement.exists(), 10.0)
	if not Settlement.exists() or Settlement.zone() != zone:
		check(false, "the farm is a settlement")
		return
	var c := Settlement.pos()
	var se := layer.server_add_person(level.ground_point(c + Vector3(2.0, 0.0, 2.0)), {"traits": ["calm"], "want": {"kind": "place"}, "kit": []})
	layer.server_settle(se)
	se["jobs"] = ["haul"]
	se["activity"] = "free"
	var sb := layer.server_settler_body(se, true)
	var start := player.global_position
	player.global_position = level.ground_point(c + Vector3(Settlement.radius() + 45.0, 0.0, 0.0)) + Vector3.UP * 0.2
	var zz := Survival.server_spawn_zombie(level, level.ground_point(c + Vector3(-Settlement.radius() * 0.7, 0.0, 0.0)))
	await _frames(2)
	Holding.settlement_tick(layer, Survival.zombies(level))
	var brain: CivilianAI = (sb.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI) if sb else null
	check(String(se.get("sheltering", "")) == "shelter" and String(se.status) == "settler" and brain != null and brain._has_hide and Vector2(brain._hide.x, brain._hide.z).distance_to(Vector2(c.x, c.z)) <= Settlement.radius(),
		"no guard and nobody home: the unarmed settler goes to the shelter, inside the settlement")
	player.global_position = level.ground_point(c + Vector3(3.0, 0.0, 0.0)) + Vector3.UP * 0.2
	await _frames(2)
	Holding.settlement_tick(layer, Survival.zombies(level))
	check(String(se.get("sheltering", "")) == "behind" and String(se.status) == "settler", "with a player home, they hide behind him")
	if zz:
		zz.vitals.server_kill()
	await _frames(2)
	Holding.settlement_tick(layer, [])
	check(not se.has("sheltering"), "the dead gone, back about the day")
	player.global_position = start + Vector3.UP * 0.2
	await _frames(5)


func _test_save_and_continue() -> void:
	print("Save and Continue")
	var f_rec := layer.server_add_person(_near(Vector3(1.5, 0.0, -1.5)), {"traits": ["loyal", "calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(f_rec.id)), "recruit")
	await _frames(3)
	var fid := String(f_rec.id)
	check(String(f_rec.status) == "companion", "one more companion")
	Survival.server_save()
	var name := Survival.world
	Net.leave()
	await get_tree().process_frame
	check(Survival.server_continue(main, name), "Continue hosts the world again")
	level = SurvivalLevel.of(self)
	await _wait_for(func() -> bool: return level != null and level.players.get_node_or_null(^"1") != null, 25.0)
	layer = SurvivorsLayer.find(level)
	await _wait_for(func() -> bool: return layer != null and layer._started, 30.0)
	var rec := SurvivorsLayer.record(fid)
	var body: Soldier = layer.body_of(fid) if layer else null
	check(String(rec.get("status", "")) == "companion" and Moods.has(rec, "joined"), "the companion's record came back, moods and all")
	check(body != null and SquadAI.of(body) != null and CompanionAI.of(body) != null and body.faction == &"friendly", "and they're with the squad again")
	check(body != null and is_same(Survival.needs_of(body), rec.needs), "their body runs on their saved needs")
	check(not (Survival.state().get(SurvivorsLayer.GRAVES_KEY, []) as Array).is_empty() and layer.graves.size() >= 1, "the graves are still there")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
	Moods.force_roll = -1.0
	CompanionAI.force_roll = -1.0
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("FALLENPEOPLE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
