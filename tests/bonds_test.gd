extends Node
## Bonds and gunsmithing (docs/survival_bonds.md, calls 74 and 85): two settlers on the same shift
## drift toward friends; the hot-headed and the calm argue and drift apart; a saved life jumps a
## bond; close friends who get on become partners, share a bunk, and a death grieves the other;
## rivals refuse a shared shift and split a vote; "Settle it" mends rivals with social skill; a brawl
## between enemies costs health, a moodlet and a vote; a companion with a low bond refuses a risky
## order, a close one follows; a gift raises the bond; the People tab lists bonds. A gunsmith bench
## and an armoury rack are built; a broken gun stripped gives parts and the bench rebuilds one; a
## crafted gun's condition scales with skill; a pipe shotgun fires (improvised, worn three times as
## fast), misfires at low condition and blows at 0; the gunsmith's order repairs stocked guns
## overnight.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer
var st: Settlement
var s1: Dictionary
var s2: Dictionary
var s3: Dictionary
var s4: Dictionary
var c1: Dictionary
var c2: Dictionary


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("BONDS TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_test_pure()
	await _test_new_world()
	if level != null and player != null and layer != null and st != null:
		_test_shift_friends()
		_test_argue_saved()
		_test_rivals_vote()
		_test_settle_it()
		_test_brawl()
		await _test_partners()
		await _test_orders_and_gifts()
		_test_people_tab()
		await _test_bench()
		await _test_improvised()
		_test_overnight_order()
	Relationships.force_roll = -1.0
	Wear.force_roll = -1.0
	CompanionAI.force_roll = -1.0
	Gunsmith.force_bench = false
	_finish()


func _test_pure() -> void:
	print("Labels, traits, quality")
	check(Relationships.label_of(0.0) == "stranger" and Relationships.label_of(15.0) == "acquaintance" and Relationships.label_of(40.0) == "friend"
		and Relationships.label_of(70.0) == "close friend" and Relationships.label_of(-30.0) == "rival" and Relationships.label_of(-70.0) == "enemy",
		"the bond reads as stranger, acquaintance, friend, close friend, rival, enemy")
	var hot := {"id": "x1", "traits": ["hot_headed"]}
	var calm := {"id": "x2", "traits": ["calm"]}
	check(Relationships.friction(hot, calm) > 0.0 and Relationships.friction(calm, calm) == 0.0 and Relationships.affinity(calm, calm) > 0.0,
		"the hot-headed and the calm grate; two calm ones get on")
	check(is_equal_approx(Gunsmith.quality(7, 7), Gunsmith.QUALITY_BASE) and Gunsmith.quality(9, 7) > Gunsmith.quality(8, 7) and Gunsmith.quality(10, 7) <= 100.0,
		"a made gun's condition rises with the smith's level (%.0f, %.0f, %.0f)" % [Gunsmith.quality(7, 7), Gunsmith.quality(8, 7), Gunsmith.quality(9, 7)])
	check(Gunsmith.misfire_chance(15.0) > Gunsmith.misfire_chance(90.0) and Gunsmith.misfire_chance(100.0) > 0.0, "an improvised gun misfires more as it wears")
	var a := {"id": "a", "partner": "b"}
	var b := {"id": "b", "partner": "a"}
	var c := {"id": "c"}
	check(Relationships.beds_used([a, b, c]) == 2 and Relationships.bed_slot(b, [a, b, c]) == 0 and Relationships.bed_slot(c, [a, b, c]) == 1, "a couple shares one bunk")


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_bonds" + tag, 7474), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	layer = SurvivorsLayer.find(level)
	if layer:
		await _wait_for(func() -> bool: return layer._started, 30.0)
	await _wait_for(func() -> bool: return Settlement.exists(), 15.0)
	st = Settlement.find(level)
	check(player != null and layer != null and st != null, "the survivor is in, with the people layer and the settlement")
	if player:
		player.inventory.take(&"pack_daypack_20")
	Wear.tick_off = true


func _near(off: Vector3) -> Vector3:
	return level.ground_point(player.global_position + off)


func _settler(traits: Array, jobs: Array, age := 35) -> Dictionary:
	var r := layer.server_add_person(_near(Vector3(randf_range(-40.0, 40.0), 0.0, 60.0)), {"traits": traits, "want": {"kind": "place"}, "age": age})
	layer.server_settle(r)
	Settlement.server_set_jobs(r, jobs)
	r["family"] = ""
	return r


func _test_shift_friends() -> void:
	print("The same shift")
	Relationships.force_roll = 0.99  # (no events: the drift alone)
	s1 = _settler(["calm", "kind"], ["guard"])
	s2 = _settler(["calm", "hard_worker"], ["guard"])
	check(Relationships.label(s1, s2) == "stranger", "two new settlers are strangers")
	for i in 20:
		st.server_hour(10)
	check(String(s1.get("job_now", "")) == "guard" and String(s2.get("job_now", "")) == "guard", "both on the guard shift")
	var b := Relationships.bond(s1, s2)
	check(b >= Relationships.FRIEND_AT and is_equal_approx(b, Relationships.bond(s2, s1)) and Relationships.label(s1, s2) == "friend",
		"twenty hours on the same shift: friends (%.1f, %s)" % [b, Relationships.label(s1, s2)])


func _test_argue_saved() -> void:
	print("The hot-headed and the calm; a life saved")
	s3 = _settler(["hot_headed", "brave"], ["guard"])
	s4 = _settler(["calm", "timid"], ["guard"])
	Relationships.force_roll = 0.0  # (every chance comes up)
	var events: Array = []
	for i in 4:
		events.append(Relationships.pair_hour(s3, s4))
	var b := Relationships.bond(s3, s4)
	check(events.has("argue") and b <= Relationships.RIVAL_AT and Moods.has(s3, "argued") and Moods.has(s4, "argued"),
		"they argue and drift apart: %.0f, %s (%s)" % [b, Relationships.label(s3, s4), events])
	var before := Relationships.bond(s2, s1)
	Relationships.server_saved(s1, s2)
	check(Relationships.bond(s2, s1) >= before + Relationships.SAVED - 0.01, "a life saved jumps the bond (%.0f -> %.0f)" % [before, Relationships.bond(s2, s1)])


func _test_rivals_vote() -> void:
	print("Rivals")
	Relationships.force_roll = 0.99
	check(Relationships.is_rival(s3, s4), "they're rivals (%.0f)" % Relationships.bond(s3, s4))
	st.server_hour(11)
	var jobs := [String(s3.get("job_now", "")), String(s4.get("job_now", ""))]
	check(jobs.has("guard") and jobs.has("idle") and (String(s3.get("refused_with", "")) == String(s4.id) or String(s4.get("refused_with", "")) == String(s3.id)),
		"one won't work the shift with the other (%s)" % [jobs])
	var fs := Council.factions()
	var together := false
	for f: String in fs:
		var list: Array = fs[f]
		if list.has(s3) and list.has(s4):
			together = true
	check(not together and fs.keys().any(func(k: String) -> bool: return k.begins_with("alone:")), "they split the vote: one votes alone (%s)" % [fs.keys()])


func _test_settle_it() -> void:
	print("Settle it")
	Relationships.force_roll = 0.5
	var d := Rpg.data(player)
	(d.perks as Array).erase("people_person")
	var was := Relationships.bond(s3, s4)
	var no := Relationships.server_mediate(player, s3)
	check(Relationships.bond(s3, s4) < was and no.begins_with("No"), "untrained, it goes wrong (\"%s\")" % no)
	s3.erase("settle_" + String(s4.id))
	(d.perks as Array).append("people_person")
	var yes := Relationships.server_mediate(player, s3)
	check(not Relationships.is_rival(s3, s4) and Relationships.bond(s3, s4) >= Relationships.SETTLE_TO - 0.01 and Moods.has(s4, "made_peace"),
		"a people person settles it: %.0f (\"%s\")" % [Relationships.bond(s3, s4), yes])
	(d.perks as Array).erase("people_person")


func _test_brawl() -> void:
	print("A brawl")
	Relationships.set_bond(s3, s4, -75.0)
	Relationships.force_roll = 0.0
	var votes := Council.open_votes().size()
	var ev := Relationships.event(s3, s4, layer)
	check(ev == "brawl" and Moods.has(s3, "brawled") and Moods.has(s4, "brawled") and float(s3.get("hurt", 0.0)) > 0.0 and float(s4.get("hurt", 0.0)) > 0.0
		and (s3.wounds as Array).any(func(w: Dictionary) -> bool: return String(w.get("kind", "")) == "bruises"),
		"enemies come to blows: both hurt, a moodlet (%s)" % ev)
	var vote: Dictionary = {}
	for v: Dictionary in Council.open_votes():
		if String((v.question as Dictionary).get("kind", "")) == Relationships.VOTE_OUT:
			vote = v
	check(Council.open_votes().size() == votes + 1 and not vote.is_empty(), "the council asks whether to send one away")
	if vote.is_empty():
		return
	var who := SurvivorsLayer.record(String((vote.question as Dictionary).person))
	var result := Council.server_resolve(int(vote.id))
	check(result in ["Send them away", "Let them stay"] and (String(who.status) != "settler") == (result == "Send them away"),
		"the council votes: %s (%s is %s)" % [result, String(who.get("name", "")), String(who.get("status", ""))])
	Relationships.force_roll = 0.99


func _test_partners() -> void:
	print("Partners")
	c1 = layer.server_add_person(_near(Vector3(1.5, 0.0, 1.5)), {"traits": ["kind", "calm"], "want": {"kind": "item", "id": "antibiotics", "count": 1, "text": "x"}, "age": 30})
	c2 = layer.server_add_person(_near(Vector3(-1.5, 0.0, 1.5)), {"traits": ["kind", "optimist"], "want": {"kind": "item", "id": "antibiotics", "count": 1, "text": "x"}, "age": 32})
	layer.server_recruit(c1, player)
	layer.server_recruit(c2, player)
	await _frames(3)
	check(String(c1.status) == "companion" and String(c2.status) == "companion" and layer.body_of(String(c2.id)) != null, "two companions along")
	Relationships.set_bond(c1, c2, 72.0)
	c1["close_h"] = {String(c2.id): Relationships.PARTNER_H - 1.0}
	c2["close_h"] = {String(c1.id): Relationships.PARTNER_H - 1.0}
	layer.server_hour()
	check(Relationships.are_partners(c1, c2) and Moods.has(c1, "partnered") and Moods.has(c2, "with_partner") and Relationships.label(c1, c2) == "partner",
		"close friends for two days who get on: partners")
	var n: Dictionary = c1.needs
	var nerve := Nerve.value(n)
	var body := layer.body_of(String(c2.id))
	if body == null:
		return
	body.vitals.server_kill()
	await _frames(3)
	var cause := "partner_died:" + String(c2.id)
	check(String(c2.status) == "dead" and Moods.has(c1, cause) and Moods.value_of(c1, cause) <= -30.0 and Nerve.value(n) < nerve - 20.0 and not Relationships.are_partners(c1, c2),
		"a partner dies: the long grief (%.0f) and a shaken nerve (%.0f -> %.0f)" % [Moods.value_of(c1, cause), nerve, Nerve.value(n)])


func _test_orders_and_gifts() -> void:
	print("The players' bond: orders, a gift, the talk")
	var body := layer.body_of(String(c1.id))
	var ai := CompanionAI.of(body) if body else null
	check(ai != null, "the companion has a mind")
	if ai == null:
		return
	body.global_position = player.global_position + Vector3(1.2, 0.0, 0.0)
	var point := level.ground_point(player.global_position + Vector3(0.0, 0.0, 30.0))
	var dead: Array = []
	for i in 3:
		var z := Survival.server_spawn_zombie(level, level.ground_point(point + Vector3(i, 0.0, 1.0)), "walker")
		if z:
			dead.append(z)
	await _frames(2)
	var profile := Survival.profile_of(player)
	(c1.opinion_of_players as Dictionary)[profile] = -60.0
	CompanionAI.force_roll = 0.99  # (a roll that would obey)
	ai._refused_at = -1000.0
	check(ai.horde_near(point) and ai.refuses(Squad.Order.MOVE, point) and ai.refuses(Squad.Order.MOVE, point), "a low bond refuses a risky order, twice")
	(c1.opinion_of_players as Dictionary)[profile] = 80.0
	CompanionAI.force_roll = 0.0  # (a roll that would refuse)
	ai._refused_at = -1000.0
	check(not ai.refuses(Squad.Order.MOVE, point), "a close bond follows into worse odds")
	for z: Soldier in dead:
		z.vitals.server_kill()
	(c1.opinion_of_players as Dictionary)[profile] = 10.0
	var acts := TalkMenu.actions_for(player, body, InteractionMenu.SQUADMATE)
	check(acts.any(func(x: Dictionary) -> bool: return String(x.id) == "talk_gift") and acts.any(func(x: Dictionary) -> bool: return String(x.id) == "talk_settle_it"),
		"the squadmate's talk has Gift and Settle it")
	player.inventory.take(&"beans_tin")
	var at := _index_of(player, &"beans_tin")
	var beans := player.inventory.count_of(&"beans_tin")
	TalkMenu.server_talk(layer, player, body, "gift", {"container": String(at[0]), "index": int(at[1])})
	check(SurvivorPerson.opinion_of(c1, profile) >= 10.0 + Relationships.GIFT - 0.01 and player.inventory.count_of(&"beans_tin") == beans - 1,
		"a gift raises the bond (10 -> %.0f)" % SurvivorPerson.opinion_of(c1, profile))
	# A close bond talks you down any time.
	(c1.opinion_of_players as Dictionary)[profile] = 70.0
	c1["talk_down_until"] = Moods.now_h() + 10.0
	var pn := Survival.needs_of(player)
	Nerve.set_value(pn, 30.0)
	TalkMenu.server_talk(layer, player, body, "talk_down")
	check(Nerve.value(pn) > 30.0 + 5.0, "a close companion talks you down even when spent (%.0f)" % Nerve.value(pn))


func _test_people_tab() -> void:
	print("The People tab")
	var lines := JournalScreen.people_lines()
	check(lines.any(func(l: String) -> bool: return l.begins_with(String(s1.name)) and l.contains("friend of " + String(s2.first)) and l.contains("you:")),
		"a line for %s with the bond (%s)" % [String(s1.name), lines.filter(func(l: String) -> bool: return l.begins_with(String(s1.name)))])


func _place(kind: String) -> int:
	var b := Builder.find(level)
	if b == null:
		return -1
	var id := -1
	for off: Vector3 in [Vector3(5, 0, 5), Vector3(-5, 0, 5), Vector3(5, 0, -5), Vector3(-5, 0, -5), Vector3(8, 0, 0), Vector3(0, 0, 8), Vector3(-8, 0, 0), Vector3(0, 0, -8), Vector3(10, 0, 10), Vector3(-10, 0, -10)]:
		var cell := Builder.ground_cell(level.ground_point(Settlement.pos() + off))
		for up in 2:
			id = b.server_place_piece(null, kind, cell + Vector3i(0, up, 0), 0, true)
			if id > 0:
				break
		if id > 0:
			break
	if id <= 0:
		return -1
	var p: Dictionary = (b.pieces[id] as Dictionary).duplicate()
	p["prog"] = 1.0
	p["paid"] = true
	p["bp"] = false
	b._set_piece(id, p)
	return id


func _test_bench() -> void:
	print("The gunsmith bench")
	var bench := _place(Gunsmith.BENCH)
	var rack := _place(Gunsmith.RACK)
	st.refresh()
	var b := Builder.find(level)
	check(bench > 0 and rack > 0 and int(Settlement.data().get("gun_benches", 0)) == 1 and int(Settlement.data().get("gun_racks", 0)) == 1,
		"a gunsmith bench and an armoury rack at the settlement")
	if bench > 0:
		check(Gunsmith.bench_near(level, b.piece_pos(bench)) and Gunsmith.bench_menu(b.pieces[bench]).any(func(e: Array) -> bool: return String(e[2]) == "gs_strip"),
			"the bench offers its work (strip, rebuild, zero, the recipes)")
	Gunsmith.force_bench = true  # (he works at it)
	Wear.force_roll = 0.99
	player.inventory.unequip(&"primary")
	check(player.inventory.put_on(&"primary", &"m4a1", {Wear.KEY: 0.0, "rounds": 0}), "a broken M4A1 slung")
	Rpg.set_level(player, "firearms", 6)
	check(Gunsmith.server_strip(player, true) == "Needs firearms 7", "stripping needs firearms 7")
	Rpg.set_level(player, "firearms", 7)
	var parts := player.inventory.count_of(Gunsmith.PARTS)
	check(Gunsmith.server_strip(player, true) == "" and player.inventory.slots.get(&"primary", &"") == &"" and player.inventory.count_of(Gunsmith.PARTS) == parts + 2,
		"stripped at the bench: the gun's gone, two gun parts (%d)" % player.inventory.count_of(Gunsmith.PARTS))
	player.inventory.put_on(&"primary", &"m4a1", {Wear.KEY: 0.0, "rounds": 0})
	player.inventory.take(&"weapon_parts")
	check(Gunsmith.server_rebuild(player, true) == "Needs firearms 8", "rebuilding needs firearms 8")
	Rpg.set_level(player, "firearms", 8)
	check(Gunsmith.server_rebuild(player, true) == "" and is_equal_approx(Wear.cond(player.inventory.state_of(&"primary")), Gunsmith.quality(8, 8))
		and player.inventory.count_of(Gunsmith.PARTS) == parts and player.inventory.count_of(&"weapon_parts") == 0,
		"the bench rebuilds it from the parts: %.0f%%" % Wear.cond(player.inventory.state_of(&"primary")))
	# Quality by skill.
	var conds: Array = []
	for lv: int in [7, 9]:
		Rpg.set_level(player, "firearms", lv)
		for k in 4:
			if player.inventory.count_of(&"pipe") >= 2:
				break
			player.inventory.take(&"pipe")
		player.inventory.take(&"scrap_sheet", 1)
		player.inventory.take(&"duct_tape", 1)
		var why := Crafting.server_craft(player, "pipe_shotgun", true)
		var at := _index_of(player, &"pipe_shotgun")
		if why == "" and at[0] != &"":
			var e: Dictionary = player.inventory.containers[at[0]][at[1]]
			conds.append(Wear.cond(e.get("state", {})))
			player.inventory.remove_entry(at[0], at[1], 1)
		else:
			conds.append(-1.0)
			print("  (craft: %s)" % why)
	check(conds.size() == 2 and is_equal_approx(float(conds[0]), Gunsmith.quality(7, 7)) and is_equal_approx(float(conds[1]), Gunsmith.quality(9, 7)),
		"a pipe shotgun made at firearms 7 starts at %.0f%%, at 9 at %.0f%%" % [float(conds[0]), float(conds[1])])
	Gunsmith.force_bench = false
	check(Crafting.problem(player, "pipe_shotgun").contains("gun bench"), "away from the bench, no bench recipes (%s)" % Crafting.problem(player, "pipe_shotgun"))
	player.inventory.unequip(&"primary")


func _fire() -> void:
	player._server_next_shot = 0.0
	player._server_busy_until = 0.0
	var eye := player.camera.global_position
	player._server_fire.rpc_id(1, eye, (-player.camera.global_basis.z + Vector3.DOWN * 0.3).normalized(), &"primary")
	await get_tree().physics_frame


func _load(cond: float) -> void:
	player.inventory.set_slot_state(&"primary", {"tube": ["shells_12g_buck"], "rounds": 1, Wear.KEY: cond})


func _test_improvised() -> void:
	print("An improvised shotgun")
	player.inventory.unequip(&"primary")
	check(player.inventory.put_on(&"primary", &"pipe_shotgun", {"tube": ["shells_12g_buck"], "rounds": 1, Wear.KEY: 100.0}), "a pipe shotgun slung")
	var gun := ItemDB.get_item(&"pipe_shotgun")
	check(WeaponCondition.improvised(gun) and Shotguns.is_shotgun(gun), "it's improvised (tag) and takes 12 gauge")
	player.select_weapon(&"primary")
	await _frames(2)
	Wear.force_roll = 0.2
	await _fire()
	var stt := player.inventory.state_of(&"primary")
	check(Shotguns.tube_of(stt).is_empty() and absf(Wear.cond(stt) - (100.0 - WeaponCondition.SHOT_WEAR * WeaponCondition.IMPROVISED_X)) < 0.01,
		"it fires: the shell gone, worn three times a found gun's (%.2f)" % Wear.cond(stt))
	_load(15.0)
	await _fire()
	stt = player.inventory.state_of(&"primary")
	check(Shotguns.tube_of(stt).is_empty() and not WeaponCondition.jammed(stt) and player.inventory.slots.get(&"primary", &"") == &"pipe_shotgun" and is_equal_approx(Wear.cond(stt), 15.0),
		"worn to 15%%: a misfire, the shell lost, no shot (%s)" % [stt])
	_load(0.0)
	Wear.force_roll = 0.0
	var wounds := player.vitals.server_wounds().size()
	await _fire()
	check(player.inventory.slots.get(&"primary", &"") == &"" and player.has_meta(&"gun_blew") and player.vitals.server_wounds().size() >= wounds + 2
		and player.vitals.server_wounds().any(func(w: Dictionary) -> bool: return String(w.get("name", "")) == "powder burns"),
		"at 0% it blows apart in his hands: the gun gone, both forearms burnt")
	Wear.force_roll = 0.99


func _test_overnight_order() -> void:
	print("The gunsmith's overnight order")
	s1["skills"] = {"firearms": 8}
	check(st.server_action(1, "order_add", [Gunsmith.ORDER, 1]) == "" and Gunsmith.order_on(), "the gunsmith order is on")
	st.server_put("m4a1", 1, {Wear.KEY: 0.0})
	st.server_put("glock17", 1, {Wear.KEY: 30.0})
	st.server_put(String(Gunsmith.PARTS), 2)
	st.server_hour(Gunsmith.ORDER_HOUR)
	var m4 := -1.0
	var glock := -1.0
	for key: String in Settlement.stores():
		for e: Dictionary in Settlement._entries(key):
			if String(e.id) == "m4a1" and e.get("state") is Dictionary:
				m4 = Wear.cond(e.state)
			elif String(e.id) == "glock17" and e.get("state") is Dictionary:
				glock = Wear.cond(e.state)
	check(is_equal_approx(m4, Gunsmith.quality(8, Gunsmith.REBUILD_LEVEL)) and is_equal_approx(glock, Gunsmith.quality(8, Gunsmith.STRIP_LEVEL)) and Settlement.count(String(Gunsmith.PARTS)) == 0,
		"by morning the stocked guns are worked: the broken M4 %.0f%%, the worn Glock %.0f%%" % [m4, glock])


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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
	print("BONDS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
