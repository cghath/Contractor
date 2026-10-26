extends Node
## The survivor's mind (docs/survival_mind.md, calls 116-119, 130): a horde shakes the nerve and
## sleep and safety settle it; low nerve shakes the hands and dulls the senses; a companion's talk
## calms it (their time, a moodlet); a drink calms it and grows the habit; withdrawal past the line
## without a dose eases over days; the smoker flaw starts hooked; human meat feeds but costs nerve,
## a moodlet and standing, and the shaking sickness ticks; a dream on waking coloured by the day,
## a nightmare after a death cuts sleep's restore; the journal's voice by trait; a letter written,
## found on the body and read by the newcomer.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer
var mate: Dictionary  # a companion


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("MIND TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_test_nerve_pure()
	_test_addictions_pure()
	_test_dreams_pure()
	_test_voice_pure()
	_test_prion_pure()
	await _test_new_world()
	if level != null and player != null and layer != null:
		await _test_talk_down()
		_test_drink_and_flaw()
		await _test_human_meat()
		_test_journal_line()
		await _test_letters()
	_finish()


func _test_nerve_pure() -> void:
	print("The nerve: shaken and settled")
	var n := Needs.fresh()
	var start := Nerve.value(n)
	var res := Mind.step(n, 0.1, {"horde": true})
	check(bool(res.horde) and Nerve.value(n) < start - 10.0, "a horde seen shakes it (%.0f -> %.0f)" % [start, Nerve.value(n)])
	var once := Nerve.value(n)
	Mind.step(n, 0.1, {"horde": true})
	check(Nerve.value(n) >= once - 0.5, "the same horde doesn't shake it again at once (%.1f)" % Nerve.value(n))
	Nerve.set_value(n, 20.0)
	n.asleep = "bed"
	Mind.step(n, 6.0, {})
	check(Nerve.value(n) >= 45.0, "six hours' sleep settles it (20 -> %.0f)" % Nerve.value(n))
	n.asleep = ""
	Nerve.set_value(n, 20.0)
	var drift := n.duplicate(true)
	Mind.step(n, 3.0, {"safe": true})
	Mind.step(drift, 3.0, {})
	check(Nerve.value(n) > Nerve.value(drift) + 5.0, "three hours safe at home settle it more than the drift (%.0f vs %.0f)" % [Nerve.value(n), Nerve.value(drift)])
	# Low nerve: hands shake, ears ring, the tension layer's level.
	var calm := Needs.fresh()
	var low := Needs.fresh()
	Nerve.set_value(calm, 80.0)
	Nerve.set_value(low, 8.0)
	check(Needs.sway_mult(low) > Needs.sway_mult(calm) + 0.5 and Needs.dulled(low) > 0.4 and is_zero_approx(Needs.dulled(calm)),
		"low nerve shakes the aim (x%.2f vs x%.2f) and dulls the senses (%.2f)" % [Needs.sway_mult(low), Needs.sway_mult(calm), Needs.dulled(low)])
	check(Needs.stamina_mult(low) < Needs.stamina_mult(calm) and Nerve.level_of(low) == 3 and Nerve.level_of(calm) == 0, "and slows stamina; level 3 for the tension layer")
	check(Needs.signs(low).has("breaking") and not Needs.signs(calm).has("steady"), "the HUD shows it only when low (%s)" % [Needs.signs(low)])
	var sleepless := Needs.fresh()
	sleepless.sleep = 10.0
	Nerve.set_value(sleepless, 60.0)
	Mind.step(sleepless, 4.0, {})
	check(Nerve.value(sleepless) < 56.0, "a night without sleep wears it down (60 -> %.0f)" % Nerve.value(sleepless))


func _test_addictions_pure() -> void:
	print("Habits and withdrawal")
	var n := Needs.fresh()
	Nerve.set_value(n, 30.0)
	Addictions.dose(n, "alcohol")
	check(Nerve.value(n) > 40.0 and Addictions.habit(n, "alcohol") > 0.0, "a drink calms (30 -> %.0f) and starts a habit (%.0f)" % [Nerve.value(n), Addictions.habit(n, "alcohol")])
	var w := Needs.fresh()
	Addictions.start_habit(w, "tobacco", 60.0)
	Mind.step(w, 6.0, {})
	check(is_zero_approx(Addictions.worst(w)), "hooked, but not yet: the clock runs")
	var nerve_before := Nerve.value(w)
	var res := Mind.step(w, 8.0, {})
	var w1 := Addictions.worst(w)
	check(w1 > 0.5 and "tobacco" in (res.withdrawal as Array) and Nerve.value(w) < nerve_before, "past the line without a smoke: withdrawal (%.2f), the nerve worn (%.0f -> %.0f)" % [w1, nerve_before, Nerve.value(w)])
	check(Needs.sway_mult(w) > 1.3 and Mind.work_mult(w) < 1.0, "tremors and slower hands (sway x%.2f, work x%.2f)" % [Needs.sway_mult(w), Mind.work_mult(w)])
	Mind.step(w, 48.0, {})
	var w2 := Addictions.worst(w)
	check(w2 > 0.0 and w2 < w1, "two days on it eases (%.2f -> %.2f)" % [w1, w2])
	Mind.step(w, 96.0, {})
	check(is_zero_approx(Addictions.worst(w)) and Addictions.habit(w, "tobacco") < float(Addictions.KINDS.tobacco.line), "and after days it's over (habit %.0f)" % Addictions.habit(w, "tobacco"))
	var smoker := Needs.fresh()
	Mind.step(smoker, 0.1, {}, ["smoker"])
	check(Addictions.habit(smoker, "tobacco") >= 50.0 and Addictions.words(smoker).size() == 1, "the smoker flaw starts hooked (%s)" % [Addictions.words(smoker)])


func _test_dreams_pure() -> void:
	print("Dreams")
	var n := Needs.fresh()
	n.sleep = 40.0
	Dreams.mark(n, "horde")
	n.asleep = "bed"
	Dreams.on_sleep(n)
	check(not bool(n.get("nightmare", false)), "a horde seen: no nightmare")
	SurvivalSleep.wake(n)
	var line := Dreams.take_line(n)
	check(String(n.get("dream_kind", "")) == "horde" and line in (Dreams.lines().horde as Array), "waking: a dream of the horde (\"%s\")" % line)
	var k := Needs.fresh()
	Dreams.mark(k, "kindness")
	k.asleep = "bed"
	SurvivalSleep.wake(k)
	check(String(k.get("dream_kind", "")) == "kindness" and Dreams.take_line(k) != line, "a kind day dreams kinder")
	# A nightmare after a death: sleep restores less.
	var grief := Needs.fresh()
	var easy := Needs.fresh()
	for b: Dictionary in [grief, easy]:
		b.sleep = 40.0
		Nerve.set_value(b, 50.0)
	Nerve.shake(grief, "friend_died")
	Nerve.set_value(grief, 50.0)
	for b: Dictionary in [grief, easy]:
		b.asleep = "bed"
		Dreams.on_sleep(b)
		Needs.step(b, 2.0, {"indoors": true})
		Mind.step(b, 2.0, {})
	check(bool(grief.get("nightmare", false)) and float(grief.sleep) < float(easy.sleep) - 5.0 and Nerve.value(grief) < Nerve.value(easy),
		"a friend dead: a nightmare cuts sleep's restore (%.0f vs %.0f) and the nerve's (%.0f vs %.0f)" % [grief.sleep, easy.sleep, Nerve.value(grief), Nerve.value(easy)])
	SurvivalSleep.wake(grief)
	check(String(grief.get("dream_kind", "")) == "nightmare" and Dreams.take_line(grief) in (Dreams.lines().nightmare as Array), "and wakes from a nightmare")


func _test_voice_pure() -> void:
	print("The journal's voice")
	var fact := "Ann Price died."
	var gloomy := JournalVoice.phrase(fact, ["gloomy"])
	var bright := JournalVoice.phrase(fact, ["optimist"])
	var pious := JournalVoice.phrase(fact, ["pious", "kind"])
	check(gloomy != bright and bright != pious and gloomy.contains(fact) and bright.contains(fact) and pious.contains(fact),
		"the same death in three voices, the fact kept (\"%s\" / \"%s\" / \"%s\")" % [gloomy, bright, pious])
	check(JournalVoice.phrase(fact, []) == fact and JournalVoice.event_of("Sam was bitten.") == "bite", "no voice trait: as written; a bite is a bite")


func _test_prion_pure() -> void:
	print("The shaking sickness")
	var n := Needs.fresh()
	Cannibalism.force_roll = 0.0
	check(Cannibalism.roll_prion(n) and n.has("prion"), "a bad meal: the sickness is in")
	Cannibalism.force_roll = -1.0
	var sway0 := Needs.sway_mult(n)
	check(Cannibalism.prion_step(n, Cannibalism.PRION_ONSET_H - 1.0) == "" and is_equal_approx(Needs.sway_mult(n), sway0), "hidden for days")
	check(Cannibalism.prion_step(n, 2.0) == "onset", "then it shows")
	var ev := ""
	for i in 30:
		var e := Cannibalism.prion_step(n, 6.0)
		if e == "memory":
			ev = e
			break
	check(ev == "memory" and String(n.get("_prion_line", "")) != "", "the memory goes (\"%s\")" % String(n.get("_prion_line", "")))
	Cannibalism.prion_step(n, 200.0)
	check(Needs.sway_mult(n) > sway0 + 0.3 and Needs.dulled(n) > 0.2, "tremors and fog grow (sway x%.2f, dulled %.2f)" % [Needs.sway_mult(n), Needs.dulled(n)])
	check(Cannibalism.prion_step(n, Cannibalism.PRION_DEATH_H) == "death", "and in weeks it kills")


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_mind" + tag, 7171), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	layer = SurvivorsLayer.find(level)
	if layer:
		await _wait_for(func() -> bool: return layer._started, 30.0)
	check(player != null and layer != null and layer._started, "the survivor is in, with the people layer")
	if player:
		player.inventory.take(&"pack_daypack_20")


func _near(off: Vector3) -> Vector3:
	return level.ground_point(player.global_position + off)


func _test_talk_down() -> void:
	print("Talk me down")
	mate = layer.server_add_person(_near(Vector3(1.5, 0.0, 0.0)), {"traits": ["calm", "kind"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(mate.id)), "recruit")
	await _frames(3)
	var body := layer.body_of(String(mate.id))
	check(String(mate.status) == "companion" and body != null, "a companion (%s)" % String(mate.get("status", "?")))
	if body == null:
		return
	check(TalkMenu.actions_for(player, body, InteractionMenu.SQUADMATE).any(func(x: Dictionary) -> bool: return String(x.id) == "talk_talk_down"), "the squadmate's menu offers Talk me down")
	var n := Survival.needs_of(player)
	Nerve.set_value(n, 15.0)
	var said := TalkMenu.server_talk(layer, player, body, "talk_down")
	check(Nerve.value(n) >= 15.0 + Nerve.TALK - 0.1 and Moods.has(mate, "talked_down") and said != "", "they talk him down (15 -> %.0f: \"%s\"), a moodlet for them" % [Nerve.value(n), said])
	var again := Nerve.value(n)
	TalkMenu.server_talk(layer, player, body, "talk_down")
	check(is_equal_approx(Nerve.value(n), again), "it costs their time: not again at once")
	Nerve.set_value(Survival.needs_of(body), 5.0)
	Mind.person_moodlets(mate, Survival.needs_of(body))
	check(Moods.has(mate, "nerve_broken") and Moods.value_of(mate, "nerve_broken") < 0.0, "a companion's broken nerve weighs on their mood")
	Nerve.set_value(Survival.needs_of(body), 70.0)
	Mind.person_moodlets(mate, Survival.needs_of(body))


func _test_drink_and_flaw() -> void:
	print("A drink, and the smoker flaw")
	var n := Survival.needs_of(player)
	Nerve.set_value(n, 30.0)
	player.inventory.take(&"spirits_flask")
	var at := _index_of(player, &"spirits_flask")
	check(at[0] != &"" and Consumables.server_use(player, at[0], at[1]) == "", "he drinks the flask")
	check(Nerve.value(n) > 40.0 and Addictions.habit(n, "alcohol") > 0.0, "it calms (30 -> %.0f) and the habit grows (%.0f)" % [Nerve.value(n), Addictions.habit(n, "alcohol")])
	var d := Rpg.data(player)
	var flaws_before: Array = (d.get("flaws", []) as Array).duplicate()
	d.flaws = ["smoker"]
	Needs.respawn(n, 100.0)
	Survival.server_drain(player, 1.0)
	check(Addictions.habit(n, "tobacco") >= 50.0, "a smoker's survivor starts hooked (%.0f)" % Addictions.habit(n, "tobacco"))
	check(Mind.character_line(n).contains("tobacco"), "the character screen says so (%s)" % Mind.character_line(n))
	d.flaws = flaws_before
	Needs.respawn(n, 100.0)


func _test_human_meat() -> void:
	print("The dark line")
	var other := layer.server_add_person(_near(Vector3(-1.5, 0.0, 0.0)), {"traits": ["calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(other.id)), "recruit")
	await _frames(3)
	var ob := layer.body_of(String(other.id))
	var n := Survival.needs_of(player)
	Nerve.set_value(n, 80.0)
	if ob:
		ob.vitals.server_kill()
	await _frames(3)
	check(String(other.get("status", "")) == "dead" and Nerve.value(n) < 60.0, "a companion dies: his nerve is shaken (80 -> %.0f)" % Nerve.value(n))
	var dead := layer.body_of(String(other.id))
	check(dead != null and InteractionMenu.actions_for(player, dead).any(func(x: Dictionary) -> bool: return String(x.id) == "talk_butcher"), "the body offers Butcher")
	if dead == null:
		return
	if not Crafting.has_tool(player, ["tag:blade", "tag:knife"]):
		player.inventory.take(&"knife")
	Nerve.set_value(n, 80.0)
	TalkMenu.server_talk(layer, player, dead, "butcher")
	check(player.inventory.count_of(Cannibalism.MEAT) >= 1 and bool(other.get("butchered", false)) and Nerve.value(n) < 70.0,
		"butchered: %d cuts, nerve 80 -> %.0f" % [player.inventory.count_of(Cannibalism.MEAT), Nerve.value(n)])
	check(Moods.has(mate, "saw_cannibalism"), "the companion saw it")
	var zone := String(Survival.state().zone)
	if WorldSim.is_set_up():  # (two groups here to learn of it: settlers who mind, cultists who don't)
		var gs: Dictionary = WorldSim.section().get("groups", {})
		gs["mind_t1"] = {"id": "mind_t1", "name": "Test settlers", "kind": "settlers", "zone": zone, "alive": true, "members": [], "memory": [], "relations": {"player": 10.0}}
		gs["mind_t2"] = {"id": "mind_t2", "name": "Test cult", "kind": "cultists", "zone": zone, "alive": true, "members": [], "memory": [], "relations": {"player": -20.0}}
		WorldSim.section()["groups"] = gs
	var groups := WorldSim.groups_in(zone)
	var rel_before := 0.0
	for g: Dictionary in groups:
		rel_before += WorldGroup.relation(g, "player")
	Nerve.set_value(n, 80.0)
	Needs.respawn(n, 40.0)
	Nerve.set_value(n, 80.0)
	var kcal := float(n.calories)
	Cannibalism.force_roll = 0.0
	var at := _index_of(player, Cannibalism.MEAT)
	check(at[0] != &"" and Consumables.server_use(player, at[0], at[1]) == "", "he eats it")
	Cannibalism.force_roll = -1.0
	check(float(n.calories) > kcal + 300.0 and Nerve.value(n) < 70.0, "it feeds (%.0f -> %.0f kcal) and costs nerve (80 -> %.0f)" % [kcal, n.calories, Nerve.value(n)])
	check(n.has("prion") and not (Survival.survivor_of(player).get("dark", []) as Array).is_empty(), "the sickness rolled in, the dark line on his record")
	check((Survival.state().get("journal", []) as Array).any(func(j: Dictionary) -> bool: return String(j.get("kind", "")) == "dark"), "the journal keeps it, tagged dark")
	if WorldSim.is_set_up():
		var ev := (WorldSim.section().get("events", []) as Array).any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "cannibalism")
		var rel_after := 0.0
		for g: Dictionary in WorldSim.groups_in(zone):
			rel_after += WorldGroup.relation(g, "player")
		var takers := groups.filter(func(g: Dictionary) -> bool: return String(g.get("kind", "")) != "cultists").size()
		check(ev and takers > 0 and rel_after < rel_before, "the world learns: an event, standing falls with %d groups here (%.0f -> %.0f)" % [takers, rel_before, rel_after])
		check(is_equal_approx(WorldGroup.relation(WorldSim.group("mind_t1"), "player"), 10.0 - Cannibalism.STANDING_DROP) and is_equal_approx(WorldGroup.relation(WorldSim.group("mind_t2"), "player"), -20.0),
			"settlers think less of him (%.0f); the cult doesn't mind (%.0f)" % [WorldGroup.relation(WorldSim.group("mind_t1"), "player"), WorldGroup.relation(WorldSim.group("mind_t2"), "player")])
		(WorldSim.section().groups as Dictionary).erase("mind_t1")
		(WorldSim.section().groups as Dictionary).erase("mind_t2")
	n.erase("prion")
	Needs.respawn(n, 100.0)


func _test_journal_line() -> void:
	print("The journal in his voice")
	var rec := Survival.survivor_of(player)
	rec["traits"] = ["gloomy"]
	Survival._journal_line("Bo Kemp died.")
	var last: Dictionary = (Survival.state().journal as Array)[-1]
	check(String(last.text) == "Bo Kemp died." and String(last.get("voice", "")).contains("list"), "a gloomy writer: \"%s\"" % String(last.get("voice", "")))
	rec["traits"] = ["optimist"]
	Survival._journal_line("Bo Kemp died.")
	var last2: Dictionary = (Survival.state().journal as Array)[-1]
	check(String(last2.get("voice", "")) != String(last.get("voice", "")), "an optimist writes it otherwise: \"%s\"" % String(last2.get("voice", "")))
	var days := JournalScreen.log_days()
	check(not days.is_empty() and ((days[0] as Dictionary).lines as Array).any(func(l: String) -> bool: return l.contains(String(last2.voice))), "the journal screen reads the voice")


func _test_letters() -> void:
	print("Letters")
	var name_before := Survival.survivor_name(player)
	check(Letters.server_write(player, "If you find this, the well water is good. Boil it anyway.") == "" and (Survival.survivor_of(player).get("letters", []) as Array).size() == 1, "a letter written, kept on him")
	var at := player.global_position
	player.server_end_spawn_protection()
	player.vitals.server_kill()
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING and player.vitals.is_up(), 25.0)
	await _frames(5)
	var letters := level.items.get_children().filter(func(i: Node) -> bool: return i is WorldItem and (i as WorldItem).item_id == Letters.ITEM and (i as WorldItem).global_position.distance_to(at) < 5.0)
	check(not letters.is_empty() and Survival.survivor_name(player) != name_before, "his letter lies on his body; %s is the newcomer" % Survival.survivor_name(player))
	if letters.is_empty():
		return
	var it := letters[0] as WorldItem
	player.inventory.take(Letters.ITEM, 1, it.state.duplicate(true))
	var people := JournalScreen.people_lines()
	check(people.any(func(l: String) -> bool: return l.contains("well water") and l.contains(name_before)), "the newcomer reads it in the journal (%s)" % [people.filter(func(l: String) -> bool: return l.begins_with("A letter"))])


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
	print("MIND TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
