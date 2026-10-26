extends Node
## Children, faith and legacy (docs/survival_children.md, calls 128-130): a child can't be given a
## weapon, flees the dead, is passed by the dead with an adult near and taken with none; the
## player's hit on a child is ignored; a hungry child gives the adults the moodlet and swings a
## council vote; a group with children prefers to settle; an orphan joins as a settler; a burial
## with a pious companion opens a rite and the words give the moodlet; a chapel service runs and
## moves mood; a cultist deserter is cleansed by services; a vigil halves the loss; a new survivor
## finds the dead one's letters; the lineage lists both survivors with cause and days; last words
## are written when no letter exists; a grave marker piece is placed at a burial and on the map.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer
var st: Settlement
var mate: Dictionary  # a companion
var kid: Dictionary
var a1: Dictionary
var a2: Dictionary


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("CHILDREN TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_test_groups_pure()
	await _test_new_world()
	if level != null and player != null and layer != null:
		await _test_child_body()
		await _test_dead_and_children()
		await _test_care_and_council()
		await _test_orphan()
		await _test_rite_grave_vigil()
		await _test_chapel_and_deserter()
		await _test_legacy()
	_finish()


func _test_groups_pure() -> void:
	print("A group with children")
	var people := {"a": {"id": "a", "courage": 50.0}, "b": {"id": "b", "courage": 50.0}, "c": {"id": "c", "courage": 50.0, "child": true, "age": 8}}
	var g := {"id": "tg", "kind": "settlers", "members": ["a", "b", "c"], "leader": "a", "supplies": {"ammo": 4.0}, "mood": {"morale": 0.5}}
	var plain := {"id": "tp", "kind": "settlers", "members": ["a", "b"], "leader": "a", "supplies": {"ammo": 4.0}, "mood": {"morale": 0.5}}
	var out := [{"kind": "raid", "bias": 0.0}, {"kind": "settle", "bias": 0.0}, {"kind": "hunt_player", "bias": 0.0}, {"kind": "forage", "bias": 0.0}]
	var out2 := out.duplicate(true)
	Children.bias_group(g, people, out)
	Children.bias_group(plain, people, out2)
	var kinds := out.map(func(o: Dictionary) -> String: return String(o.kind))
	check(not "raid" in kinds and not "hunt_player" in kinds and float(out[0].bias) > 0.3 and String(out[0].kind) == "settle",
		"with a child: no raid, settling leans (%s)" % [kinds])
	check(out2.size() == 4 and is_zero_approx(float(out2[1].bias)), "without one: the options as they were")
	check(is_equal_approx(WorldGroup.strength(g, people), WorldGroup.strength(plain, people)), "a child adds nothing to a fight (%.2f)" % WorldGroup.strength(g, people))
	var cult := {"id": "tc", "kind": "cultists", "relations": {"player": -20.0}}
	WorldGroup.change_relation(cult, "player", 30.0)
	var bought := WorldGroup.relation(cult, "player")
	WorldGroup.change_relation(cult, "player", -5.0)
	check(is_equal_approx(bought, -20.0) and is_equal_approx(WorldGroup.relation(cult, "player"), -25.0), "a cult's standing can't be bought (%.0f), only lost" % bought)
	var v := {"question": {"kind": "raid"}, "options": ["Go", "Stay"]}
	check(Children.risky_result(v, {"Go": 6.0, "Stay": 4.0}, "Go") == "Go", "no children at home: a raid passes on a simple majority")


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_children" + tag, 7272), "the menu's New world hosts one")
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
	check(player != null and layer != null and layer._started and st != null and Settlement.exists(), "the survivor is in, with the people layer and the settlement")
	if player:
		player.inventory.take(&"pack_daypack_20")
	var placed := SurvivorsLayer.records().values().filter(func(r: Dictionary) -> bool: return Children.is_child_rec(r))
	print("  (children placed in the zone: %d)" % placed.size())


func _near(off: Vector3) -> Vector3:
	return level.ground_point(player.global_position + off)


func _test_child_body() -> void:
	print("A child: unarmed, small, never hurt")
	mate = layer.server_add_person(_near(Vector3(1.5, 0.0, 1.5)), {"traits": ["calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(mate.id)), "recruit")
	await _frames(3)
	check(String(mate.status) == "companion", "a companion along (%s)" % String(mate.status))
	kid = Children.server_add_child(layer, _near(Vector3(2.0, 0.0, -1.0)), {"age": 9})
	await _frames(2)
	var body := layer.body_of(String(kid.id))
	check(body != null and Children.is_child(body) and body.vitals.shielded and body.model and body.model.body_scale() < 0.8,
		"a child-sized, shielded body")
	if body == null:
		return
	await _frames(3)
	check(Children.size_of(body) < 1.0, "the capsule is smaller (x%.1f)" % Children.size_of(body))
	var acts := TalkMenu.actions_for(player, body, TalkMenu.KIND)
	check(not acts.any(func(x: Dictionary) -> bool: return String(x.id) in ["talk_recruit", "talk_threaten"]) and acts.any(func(x: Dictionary) -> bool: return String(x.id) == "talk_who"),
		"the talk: no Recruit, no Threaten (%s)" % [acts.map(func(x: Dictionary) -> String: return String(x.id))])
	player.inventory.take(&"crowbar")
	var at := _index_of(player, &"crowbar")
	var said := TalkMenu.server_talk(layer, player, body, "give", {"container": String(at[0]), "index": int(at[1])})
	check(at[0] != &"" and player.inventory.count_of(&"crowbar") >= 1 and body.inventory.count_of(&"crowbar") == 0 and not (kid.kit as Array).any(func(e: Dictionary) -> bool: return String(e.id) == "crowbar"),
		"a child can't be given a weapon (\"%s\")" % said)
	body.inventory.take(&"hatchet")
	check(Children.strip_weapons(body) == 1 and body.inventory.count_of(&"hatchet") == 0, "one put in their hands is taken off them")
	check(TalkMenu.server_talk(layer, player, body, "recruit") == "" and String(kid.status) == "out_there", "and they can't be recruited to fight")
	# The player's hit: ignored, "You don't."
	Children._refused.clear()
	var inj := body.vitals.injury()
	Melee._hit(player, body, {"name": "swing", "kind": "blunt", "round_class": &"pistol", "depth": 0.05, "parts": [Vitals.CHEST], "energy_j": 400.0}, 1.0)
	Harm.note_hit(body, player)
	body.vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.INTERMEDIATE, "channel_depth": 0.3, "direction": Vector3.FORWARD, "energy_j": 1500.0})
	check(is_equal_approx(body.vitals.injury(), inj) and body.vitals.is_up() and Children._refused.has(player.get_instance_id()) and Harm.last(body).is_empty(),
		"the player's blow and round on a child do nothing: \"You don't.\"")


func _test_dead_and_children() -> void:
	print("The dead and the children")
	var body := layer.body_of(String(kid.id))
	if body == null:
		check(false, "the child has a body")
		return
	var z := Survival.server_spawn_zombie(level, level.ground_point(body.global_position + Vector3(3.0, 0.0, 0.0)), "walker")
	check(z != null, "one of the dead near the child")
	if z == null:
		return
	await _frames(2)
	var brain := ZombieAI.of(z)
	var seen: Variant = brain._spot().get("who") if brain else null
	check(Children.ignored_by_dead(body) and seen != body and brain._smell() != body, "the dead don't see or smell the child (%s)" % [seen])
	var taken := Children.server_tick(layer, [z])
	var civ := body.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
	check(taken.is_empty() and civ != null and civ.threatened() and Moods.has(mate, "child_saw"), "an adult near: the child runs, not taken; the companion saw it")
	z.global_position = body.global_position + Vector3(0.8, 0.0, 0.0)
	check(Children.server_tick(layer, [z]).is_empty() and String(kid.status) == "out_there", "even close, with an adult by, the child is left alone")
	z.vitals.server_kill()
	# A child alone: taken.
	var spot := Vector3.INF
	for i in 16:
		var a := TAU * i / 16.0
		for r: float in [50.0, 62.0, 74.0]:
			var p := level.ground_point(player.global_position + Vector3(cos(a), 0.0, sin(a)) * r)
			if Children.nearest_adult(layer, p) == null:
				spot = p
				break
		if spot != Vector3.INF:
			break
	check(spot != Vector3.INF, "a spot with no adult within %.0f m" % Children.ADULT_M)
	if spot == Vector3.INF:
		return
	var lone := Children.server_add_child(layer, spot, {"age": 7})
	await _frames(2)
	var lb := layer.body_of(String(lone.id))
	var had_body := lb != null
	var z2 := Survival.server_spawn_zombie(level, level.ground_point(spot + Vector3(1.0, 0.0, 0.0)), "walker")
	await _frames(2)
	if had_body and z2:
		z2.global_position = lb.global_position + Vector3(1.0, 0.0, 0.0)
		Children.server_tick(layer, [z2])
	await _frames(2)
	var journal: Array = Survival.state().get("journal", [])
	check(had_body and String(lone.status) == "taken" and layer.body_of(String(lone.id)) == null,
		"no adult within %.0f m: the child is taken, no body left (%s)" % [Children.ADULT_M, String(lone.status)])
	check(journal.any(func(j: Dictionary) -> bool: return String(j.get("text", "")).contains("was taken")) and Moods.has(mate, "child_taken:" + String(lone.id)) and Moods.value_of(mate, "child_taken:" + String(lone.id)) <= -20.0,
		"a journal line and a heavy moodlet for everyone")
	if z2:
		z2.vitals.server_kill()


func _test_care_and_council() -> void:
	print("Care and the council")
	a1 = layer.server_add_person(_near(Vector3(-3.0, 0.0, 2.0)), {"traits": ["kind", "optimist", "pious"], "want": {"kind": "place"}, "age": 50})
	a2 = layer.server_add_person(_near(Vector3(-3.0, 0.0, -2.0)), {"traits": ["kind", "optimist", "pious"], "want": {"kind": "place"}, "age": 40})
	layer.server_settle(a1)
	layer.server_settle(a2)
	Children.server_take_in(layer, kid)
	check(String(kid.status) == "settler" and Children.settlement_children().size() == 1 and (Settlement.jobs_of(kid) as Array).is_empty(),
		"the child lives at the settlement; no jobs at %d" % int(kid.age))
	check(Settlement.jobs_of(a1).has("service"), "a pious settler holds the service (%s)" % [Settlement.jobs_of(a1)])
	check(Council.factions().values().all(func(l: Array) -> bool: return not l.has(kid)), "the child has no vote")
	var v := {"question": {"kind": "take_in", "people": []}, "options": ["Take them in", "Turn them away"], "player": {}}
	var before := Council._pick(Council.preference(st, a1, v), v.options)
	Settlement.data()["care_h"] = 0.0
	check(Children.mind(a2, 1.0) and Children.mind(a2, 1.0) and not Children.mind(a2, 1.0), "minding: two hours a child, then it's done")
	(kid.needs as Dictionary)["hunger"] = 10.0
	check(not Children.server_care_check() and Moods.has(a1, "child_hungry") and Moods.has(a2, "child_hungry") and not Moods.has(a1, "child_safe"),
		"a child went hungry: every adult takes it")
	var after := Council._pick(Council.preference(st, a1, v), v.options)
	check(before == "Take them in" and after == "Turn them away", "and it swings the vote to take more in (%s -> %s)" % [before, after])
	var id := Council.server_put({"kind": "take_in", "people": [], "text": "Take in the Fenwick family?"}, ["Take them in", "Turn them away"])
	check(Council.server_resolve(id) == "Turn them away", "the council votes them away with a hungry child at home")
	Moods.remove(a1, "child_hungry")
	Moods.remove(a2, "child_hungry")
	(kid.needs as Dictionary)["hunger"] = 90.0
	Settlement.data()["care_h"] = Children.CARE_H
	check(Children.server_care_check() and Moods.has(a1, "child_safe"), "fed and minded: a child is safe here")
	var id2 := Council.server_put({"kind": "take_in", "people": [], "text": "Take in the Fenwick family?"}, ["Take them in", "Turn them away"])
	check(Council.server_resolve(id2) == "Take them in", "fed, the same vote takes them in")
	var rv := {"question": {"kind": "raid"}, "options": ["Go", "Stay"]}
	check(Children.risky_result(rv, {"Go": 6.0, "Stay": 4.0}, "Go") == "Stay" and Children.risky_result(rv, {"Go": 8.0, "Stay": 2.0}, "Go") == "Go",
		"with children here a raid needs two thirds")


func _test_orphan() -> void:
	print("An orphan")
	var o := Children.server_add_child(layer, _near(Vector3(-1.5, 0.0, -2.5)), {"age": 13, "orphan": true})
	await _frames(2)
	var body := layer.body_of(String(o.id))
	check(body != null and TalkMenu.actions_for(player, body, TalkMenu.KIND).any(func(x: Dictionary) -> bool: return String(x.id) == "talk_come"), "a lone child asks to come along")
	if body == null:
		return
	var said := TalkMenu.server_talk(layer, player, body, "come")
	await _frames(2)
	check(String(o.status) == "settler" and not bool(o.get("orphan", true)) and said != "", "Come with me: a settler, not a companion (\"%s\")" % said)
	check(Settlement.jobs_of(o) == ["forage", "minding", "water"], "at 13: light jobs (%s)" % [Settlement.jobs_of(o)])
	var food := Settlement.count("wild_berries") + Settlement.count("apples")
	SettlementJobs.do_job(st, "forage", o, 5.0)
	check(Settlement.count("wild_berries") + Settlement.count("apples") > food, "foraging brings food in")


func _test_rite_grave_vigil() -> void:
	print("A burial, the rite, the grave, the vigil")
	var pious := layer.server_add_person(_near(Vector3(2.0, 0.0, 2.0)), {"traits": ["pious", "calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(pious.id)), "recruit")
	var other := layer.server_add_person(_near(Vector3(0.0, 0.0, 3.0)), {"traits": ["calm"], "want": {"kind": "place"}})
	TalkMenu.server_talk(layer, player, layer.body_of(String(other.id)), "recruit")
	await _frames(3)
	var ob := layer.body_of(String(other.id))
	check(String(pious.status) == "companion" and ob != null, "a pious companion and another along")
	if ob == null:
		return
	ob.vitals.server_kill()
	await _frames(3)
	check(String(other.status) == "dead" and Moods.has(a1, "companion_died:" + String(other.id)) and Settlement.data().has("vigil"), "one dies; the settlement will sit up tonight")
	var dead := layer.body_of(String(other.id))
	if dead == null:
		return
	var at := dead.global_position
	check(layer.server_bury(player, dead), "buried")
	var rite := Faith.open_rite(String(pious.id))
	var pb := layer.body_of(String(pious.id))
	check(not rite.is_empty() and pb != null and TalkMenu.actions_for(player, pb, InteractionMenu.SQUADMATE).any(func(x: Dictionary) -> bool: return String(x.id) == "talk_words"),
		"the pious one asks for words: the squadmate's menu offers Say a few words")
	var n := Survival.needs_of(player)
	Nerve.set_value(n, 30.0)
	var said := TalkMenu.server_talk(layer, player, pb, "words") if pb else ""
	check(Moods.has(pious, "words_said:" + String(other.id)) and Moods.value_of(pious, "words_said:" + String(other.id)) > 0.0 and Nerve.value(n) > 30.0 + 5.0,
		"the words said: a moodlet for those there, his nerve settles (30 -> %.0f; \"%s\")" % [Nerve.value(n), said])
	# The grave marker and the map.
	var gp := int(other.get("grave_piece", -1))
	var marks := Legacy.markers(level)
	check(gp > 0 and String(marks.get(gp, "")) == String(other.name), "a grave marker piece inscribed \"%s\"" % String(marks.get(gp, "")))
	check(SurvivalMap.marks("").any(func(m: Dictionary) -> bool: return String(m.get("kind", "")) == Legacy.MARK_KIND and String(m.get("text", "")).contains(String(other.name))),
		"the grave is on the map")
	# Declining: another rite let go.
	var rite2 := Faith.server_on_burial(layer, {"id": "zz", "name": "Nobody Known"}, at)
	check(not rite2.is_empty() and TalkMenu.server_talk(layer, player, pb, "no_words") != "" and Moods.has(pious, "no_words:zz") and Moods.value_of(pious, "no_words:zz") < 0.0,
		"no words: the pious one minds it")
	# The vigil.
	var cause := "companion_died:" + String(other.id)
	var was := Moods.value_of(a1, cause)
	var sleep_was := float((a1.needs as Dictionary).get("sleep", 100.0))
	check(Faith.server_vigil(st) > 0 and is_equal_approx(Moods.value_of(a1, cause), was * Faith.VIGIL_KEEP) and float(a1.needs.sleep) < sleep_was,
		"the vigil: the loss halved (%.0f -> %.0f), less sleep (%.0f -> %.0f)" % [was, Moods.value_of(a1, cause), sleep_was, float(a1.needs.sleep)])


func _test_chapel_and_deserter() -> void:
	print("The chapel, a service, a deserter cleansed")
	var b := Builder.find(level)
	var id := -1
	if b:
		for off: Vector3 in [Vector3(4, 0, 4), Vector3(-4, 0, 4), Vector3(4, 0, -4), Vector3(-4, 0, -4), Vector3(6, 0, 0), Vector3(0, 0, 6), Vector3(-6, 0, 0), Vector3(0, 0, -6), Vector3(8, 0, 8)]:
			var cell := Builder.ground_cell(level.ground_point(Settlement.pos() + off))
			for up in 2:
				id = b.server_place_piece(null, "altar", cell + Vector3i(0, up, 0), 0, true)
				if id > 0:
					break
			if id > 0:
				break
	check(id > 0, "an altar placed at the settlement (%s)" % (b.last_problem if b else "no builder"))
	if id <= 0:
		return
	var p: Dictionary = (b.pieces[id] as Dictionary).duplicate()
	p["prog"] = 1.0
	p["paid"] = true
	p["bp"] = false
	b._set_piece(id, p)
	st.refresh()
	check(Faith.has_chapel(), "the settlement has a chapel")
	var mood_was := Moods.mood(a2)
	Settlement.data()["served_day"] = -1
	check(SettlementJobs.do_job(st, "service", a1, 1.0) and Moods.has(a2, "service") and Moods.mood(a2) > mood_was and float(Settlement.data().get("faith", 0.0)) > 0.0,
		"the pious settler holds a service: mood %.0f -> %.0f, faith %.0f" % [mood_was, Moods.mood(a2), float(Settlement.data().get("faith", 0.0))])
	check(not Faith.service(st, a1), "one service a day")
	var vt := {"question": {"kind": "take_in"}, "options": ["Take them in", "Turn them away"], "player": {}}
	var s0 := float(Council.preference(st, a2, vt)["Take them in"])
	Settlement.data()["faith"] = 60.0
	check(float(Council.preference(st, a2, vt)["Take them in"]) > s0, "the council leans to charity with the faith")
	var dz := Faith.server_add_deserter(layer, _near(Vector3(-2.0, 0.0, 3.0)))
	await _frames(2)
	var db := layer.body_of(String(dz.id))
	var ask := TalkMenu.server_talk(layer, player, db, "who") if db else ""
	check(ask.contains("clean") or ask.contains("place"), "a cultist deserter asks to be cleansed (\"%s\")" % ask)
	layer.server_settle(dz)
	for i in Faith.CLEANSE_SERVICES:
		Settlement.data()["served_day"] = -1
		Faith.service(st, a1)
	check(bool(dz.get("cleansed", false)) and not bool(dz.get("cult_deserter", true)) and Moods.has(dz, "cleansed") and SurvivorPerson.has_trait(dz, "pious"),
		"after %d services the deserter is cleansed" % Faith.CLEANSE_SERVICES)
	# Grace at a meal, a prayer before a raid.
	(a1.jobs as Array).append("cook")
	a1["activity"] = "work"
	Faith.settlement_hour(st, Settlement.MEALS[0])
	check(Moods.has(a2, "grace") and Faith.server_prayer() > 0 and Moods.has(a2, "prayer"), "grace with a pious cook; a prayer before a raid")


func _test_legacy() -> void:
	print("Letters and the lineage")
	var first := Survival.survivor_name(player)
	var rec := Survival.survivor_of(player)
	rec["born_day"] = Survival.day() - 3
	check(Letters.server_write(player, "The pump by the barn still draws. Keep the children inside after dark.") == "", "a letter written")
	await _die()
	var second := Survival.survivor_name(player)
	check(second != first, "%s is the newcomer" % second)
	var people := JournalScreen.people_lines()
	check(people.any(func(l: String) -> bool: return l.contains("found on " + first) and l.contains("pump by the barn")), "the newcomer finds the dead one's letter, in their voice (%s)" % [people.filter(func(l: String) -> bool: return l.contains("found on"))])
	var rec2 := Survival.survivor_of(player)
	rec2["born_day"] = Survival.day() - 2
	player.set_meta(&"killed_by_dead", true)
	await _die()
	player.remove_meta(&"killed_by_dead")
	var lin := Legacy.lineage()
	check(lin.size() >= 2, "two survivors in the lineage")
	if lin.size() < 2:
		return
	var e1: Dictionary = lin[-2]
	var e2: Dictionary = lin[-1]
	check(String(e1.name) == first and int(e1.days) == 3 and (e1.letters as Array).size() == 1 and String(e1.get("last_words", "")) == "",
		"%s: %d days, %s, one letter" % [String(e1.name), int(e1.days), String(e1.cause)])
	check(String(e2.name) == second and int(e2.days) == 2 and String(e2.cause) == "killed by the dead" and String(e2.last_words) != "",
		"%s: %d days, %s; last words \"%s\"" % [String(e2.name), int(e2.days), String(e2.cause), String(e2.get("last_words", ""))])
	check((Survival.state().journal as Array).any(func(j: Dictionary) -> bool: return String(j.get("text", "")).contains("last words")), "the journal writes the last words")
	var tab: Array = JournalScreen.view().get("lineage", [])
	check(tab.any(func(l: String) -> bool: return l.contains(first) and l.contains("3 days")) and tab.any(func(l: String) -> bool: return l.contains(second) and l.contains("killed by the dead"))
		and tab.any(func(l: String) -> bool: return l.contains(Survival.survivor_name(player)) and l.contains("alive")), "the Lineage tab lists them in order, and the one alive")
	check(SurvivalMap.marks("").any(func(m: Dictionary) -> bool: return String(m.get("kind", "")) == Legacy.MARK_KIND and String(m.get("text", "")).contains(first)), "a player survivor's grave is on the map")


func _die() -> void:
	player.server_end_spawn_protection()
	player.vitals.server_kill()
	await _frames(2)
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING and player.vitals.is_up(), 25.0)
	await _frames(5)


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
	print("CHILDREN TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
