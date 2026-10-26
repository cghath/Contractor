extends Node
## The body's phase D (docs/survival_medical.md section 10, for sections 2, 3, 5, 6 and 7): a
## zombie's bite starts the fever clock and its stages come with the days; antibiotics, rest and
## a doctor slow it; the serum cures it; a collapse rises; the immune never turn. A contaminated
## wound stages to sepsis unchecked and back with a course; stopping early lets it come back;
## surgery removes a fragment (refused below the gate) and the wound heals faster; a cough is
## noise; flu spreads among people living together; scurvy comes after weeks; the wrong blood
## reacts; repairing a zone's water works makes its taps run; boiling cleans water; washing lowers
## the infection risk; winter drains warmth faster than spring; the body screen hides the stage
## from a novice and shows it to a doctor. Days are driven directly (the clock's step functions).

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("BODY TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null:
		await _test_bite_clock()
		_test_clock_slowers()
		_test_immune()
		await _test_collapse_rises()
		_test_wound_staging()
		_test_hygiene()
		await _test_surgery()
		_test_sicknesses()
		_test_blood()
		_test_water()
		_test_seasons()
		await _test_body_screen()
	_finish()


func _test_new_world() -> void:
	print("A world for the body")
	check(Survival.server_new_world(main, "test_body" + tag, 4321), "a new survival world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	layer = SurvivorsLayer.find(level)
	check(player != null and layer != null, "the survivor is in, with the zone's people layer")
	if player:
		player.inventory.take(&"pack_daypack_20")
		for z: Soldier in Survival.zombies(level):
			z.queue_free()
		await _frames(5)


func _fresh_body() -> Dictionary:
	var n := Survival.needs_of(player)
	Needs.respawn(n, 100.0)
	n["immune"] = false
	Survival.survivor_of(player).erase("immune")
	player.vitals.server_reset_health()
	return n


func _test_bite_clock() -> void:
	print("The bite's fever clock")
	var n := _fresh_body()
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + Vector3(20, 0, 0)))
	await _frames(2)
	check(z != null, "one of the dead to do the biting")
	if z == null:
		return
	Melee._hit(z, player, Melee.ZOMBIE_ATTACK, 1.0)
	z.queue_free()
	check(BiteFever.bitten(n) and player.has_meta(&"bitten"), "a zombie's bite starts the clock (%s)" % [BiteFever.clock(n)])
	var bites := Infection.records(n).filter(func(r: Dictionary) -> bool: return bool(r.get("bite", false)))
	check(not bites.is_empty() and int((bites[0] as Dictionary).stage) >= 1, "and the bite is a dirty wound (%d records)" % Infection.records(n).size())
	check(BiteFever.stage(n) == 0, "day one: incubation")
	var ev := BiteFever.step(n, 23.0, {"abx": false})
	check(ev == "" and BiteFever.stage(n) == 0, "still incubating at 23 h")
	ev = BiteFever.step(n, 2.0, {"abx": false})
	check(ev == "fever" and BiteFever.stage(n) == 1 and float(BiteFever.effects(n).get("stamina", 1.0)) < 1.0, "day 2: the fever (%s), stamina slower" % ev)
	check(Body.fever_c(n) >= 38.0 and Body.stamina_factor(n) < 1.0, "the core runs hot (%.1f C)" % Body.fever_c(n))
	ev = BiteFever.step(n, 72.0, {"abx": false})
	check(ev == "delirium" and BiteFever.stage(n) == 2 and Needs.dulled(n) >= 0.5 and float(BiteFever.effects(n).get("vision", 0.0)) > 0.0, "day 5: delirium: dulled senses, the vision sways")
	# The serum before collapse.
	check(player.inventory.take(&"serum", 1) == 1, "a dose of serum")
	var said := Body.server_action(player, player, "serum", "", "")
	check(not BiteFever.bitten(n) and not player.has_meta(&"bitten") and player.inventory.count_of(&"serum") == 0, "the serum cures it (%s)" % said)
	await _frames(2)


func _test_clock_slowers() -> void:
	print("Antibiotics, rest and a doctor slow the clock")
	var plain := Needs.fresh()
	BiteFever.start(plain)
	BiteFever.step(plain, 24.0, {})
	var abx := Needs.fresh()
	BiteFever.start(abx)
	check(Infection.dose(abx), "a dose of antibiotics goes in")
	BiteFever.step(abx, 24.0, {})
	var hp := float(BiteFever.clock(plain).h)
	var ha := float(BiteFever.clock(abx).h)
	check(is_equal_approx(hp, 24.0) and ha < hp - 4.0, "a day on a course runs the clock slower (%.1f h vs %.1f h: a day paused over the course)" % [ha, hp])
	var rest := Needs.fresh()
	BiteFever.start(rest)
	rest.asleep = "bed"
	BiteFever.step(rest, 10.0, {"abx": false})
	check(absf(float(BiteFever.clock(rest).h) - 7.0) < 0.01, "rest in a bed with good food: x0.7 (%.2f h of 10)" % float(BiteFever.clock(rest).h))
	var doc := Needs.fresh()
	BiteFever.start(doc)
	doc.care_h = 24.0
	BiteFever.step(doc, 10.0, {"abx": false})
	check(absf(float(BiteFever.clock(doc).h) - 5.0) < 0.01, "a doctor's care: x0.5 (%.2f h of 10)" % float(BiteFever.clock(doc).h))


func _test_immune() -> void:
	print("The immune never turn")
	var n := Needs.fresh()
	BiteFever.start(n, true)
	var events: Array = []
	for i in 9:
		var ev := BiteFever.step(n, 20.0, {})
		if ev != "":
			events.append(ev)
		if i == 6:
			check(BiteFever.stage(n) <= 0, "day %d: no fever" % (i + 1))
	check(events == ["immune"] and not BiteFever.bitten(n) and bool(n.get("immune_known", false)), "the week runs out: no fever, no turn, and now they know (%s)" % [events])


func _test_collapse_rises() -> void:
	print("Collapse: the bitten rise")
	var rec := layer.server_add_person(level.ground_point(player.global_position + Vector3(4, 0, 0)), {"traits": ["calm"], "want": {"kind": "place"}})
	await _frames(3)
	var body := layer.body_of(String(rec.id))
	check(body != null, "a survivor stands by")
	if body == null:
		return
	rec["immune"] = false
	Body.on_bitten(body, &"forearm_r")
	var n: Dictionary = rec.needs
	check(BiteFever.bitten(n) and bool(rec.get("bitten", false)) and Moods.has(rec, "bitten"), "bitten: the clock on their record's body, and the moodlet")
	BiteFever.step(n, BiteFever.COLLAPSE_AT_H - 0.001, {"abx": false})
	check(BiteFever.stage(n) == 2, "the end of day 6: delirious")
	Survival.server_drain(body, 2.0)
	await _wait_for(func() -> bool: return String(rec.get("status", "")) == "dead", 5.0)
	check(String(rec.get("status", "")) == "dead" and bool(BiteFever.clock(n).get("collapsed", false)), "day 7: collapse and death (%s)" % rec.get("status", "?"))
	check(not BiteFever.cure(n), "the serum is too late after collapse")
	rec.rise_at = Soldier._now() - 1.0
	layer.server_tick()
	await _frames(3)
	var risen := Survival.zombies(level).filter(func(z: Soldier) -> bool: return String(z.get_meta(&"risen_id", "")) == String(rec.id))
	check(not risen.is_empty() and bool(rec.get("risen", false)), "and they rise as one of the dead, in their kit")
	for z: Soldier in risen:
		z.queue_free()
	await _frames(2)


func _test_wound_staging() -> void:
	print("Wound infection: to sepsis and back")
	var n := Needs.fresh()
	var r := Infection.add(n, "forearm_l", "muscle")
	Infection.step(n, 13.0, {"risk": 0.0})
	check(int(r.stage) == 1, "open to the air half a day: contaminated (%s)" % Infection.stage_name(r))
	Infection.step(n, 24.5, {"risk": 0.0})
	check(int(r.stage) == 2 and Infection.fever_c(n) > 37.5, "a day dirty: infected, a fever")
	Infection.step(n, 60.5, {"risk": 0.0})
	check(int(r.stage) == 3 and Body.dulled_add(n) > 0.0, "two and a half days infected: sepsis, delirium")
	var dead := n.duplicate(true)
	var out := Infection.step(dead, 48.5, {"risk": 0.0})
	check(bool(out.death), "two days of sepsis unchecked kills")
	var stages: Array = []
	for day in 5:
		var took := Infection.dose(n)
		if day == 0:
			check(took, "the first dose goes in")
		Infection.step(n, 24.0, {"risk": 0.0})
		stages.append(int(r.stage))
	check(stages[0] == 2 and stages[1] == 1 and stages[2] == 0 and int(r.stage) == 0 and Infection.course(n).is_empty(), "a full course takes it back a stage a day to clean (%s)" % [stages])
	var early := Needs.fresh()
	var e := Infection.add(early, "thigh_r", "muscle")
	e.stage = 2
	Infection.dose(early)
	Infection.step(early, 24.0, {"risk": 0.0})
	var mid := int(e.stage)
	Infection.step(early, Infection.COURSE_GAP_H + 1.0, {"risk": 0.0})
	check(mid == 1 and int(e.stage) == 2, "one dose and stop: it comes back (%d -> %d)" % [mid, int(e.stage)])
	check(Infection.clean(early, "thigh_r", "antiseptic") == 1 and int(e.stage) == 1, "antiseptic takes an infected wound back to dirty")
	check(Infection.clean(early, "thigh_r", "boiled") == 1 and int(e.stage) == 0, "boiled water cleans a dirty one")
	Infection.dress(early, "thigh_r")
	Infection.step(early, 20.0, {"risk": 0.0})
	check(int(e.stage) == 0, "a clean dressing keeps it clean through the day")
	var heal0 := float(e.heal_h)
	Infection.step(early, 10.0, {"risk": 0.0})
	check(float(e.heal_h) < heal0 and Infection.days_left(early, e) < INF, "clean, it heals (%.1f days left)" % Infection.days_left(early, e))
	early.calories = 0.0
	check(Infection.heal_rate(early, e) == 0.0 and "starving" in Infection.slowed_by(early, e), "starving, it doesn't")


func _test_hygiene() -> void:
	print("Hygiene: washing lowers the risk, gore raises it")
	var n := Needs.fresh()
	n.hygiene = 10.0
	var dirty := Hygiene.risk(n)
	Hygiene.wash(n, "river", true)
	check(dirty > 0.5 and Hygiene.risk(n) == 0.0 and float(n.hygiene) >= 99.0, "a wash with soap: the risk gone (%.2f -> %.2f)" % [dirty, Hygiene.risk(n)])
	Hygiene.gore(n)
	check(Hygiene.risk(n) > 0.0 and Hygiene.smell(n) > 0.5, "gore on you: risk and smell (%.2f)" % Hygiene.risk(n))
	var pn := Survival.needs_of(player)
	pn.hygiene = 80.0
	player.set_meta(&"gore_until", Soldier._now() + 60.0)
	player.set_meta(&"gore_at", 12.5)
	Hygiene.server_take_gore(player, pn)
	Hygiene.server_take_gore(player, pn)
	check(is_equal_approx(float(pn.hygiene), 80.0 - Hygiene.GORE_HYGIENE) and Hygiene.risk(pn) > 0.0 and player.smell_strength() >= 0.8, "masking's smear (gore_until, gore_at) costs hygiene once and raises the risk")
	Hygiene.server_wash(player, "basin", false)
	check(not player.has_meta(&"gore_until") and Hygiene.risk(pn) == 0.0, "and a wash takes it off")
	var r := Infection.add(n, "chest", "graze")
	Infection.step(n, 6.0, {"risk": Hygiene.risk(n)})
	var gory := float(r.dirt)
	Hygiene.wash(n, "bath", false)
	var r2 := Infection.add(n, "chest", "graze")
	Infection.step(n, 6.0, {"risk": Hygiene.risk(n)})
	check(gory > float(r2.dirt), "a wound dirties slower on a washed body (%.2f vs %.2f)" % [gory, float(r2.dirt)])


func _test_surgery() -> void:
	print("Field surgery: a fragment out")
	var n := _fresh_body()
	player.vitals.server_add_wound(&"thigh_l", "muscle", 0.0)
	Infection.server_sync(player, n)
	var recs := Infection.on_part(n, "thigh_l")
	check(recs.size() == 1, "a wound in the thigh has its record")
	if recs.is_empty():
		return
	var r: Dictionary = recs[0]
	r.fragment = true
	r.stage = 1
	Rpg.set_level(player, "medical", 2)
	var refused := Surgery.server_operate(player, player, "remove_fragment", "thigh_l")
	check(not bool(refused.ok) and String(refused.why).contains("medical"), "refused below the gate (%s)" % refused.why)
	Rpg.set_level(player, "medical", 6)
	var before := Infection.heal_rate(n, r)
	Surgery.force_roll = 0.0
	var done := Surgery.server_operate(player, player, "remove_fragment", "thigh_l")
	Surgery.force_roll = -1.0
	check(bool(done.ok) and not bool(r.fragment), "medical 6, a knife: it's out (%s)" % done.get("text", done.get("why", "")))
	check(Infection.heal_rate(n, r) > before, "and the wound heals faster (%.2f -> %.2f)" % [before, Infection.heal_rate(n, r)])
	Infection.clean(n, "thigh_l", "boiled")
	check(int(r.stage) == 0, "and now it can be cleaned")
	Surgery.force_roll = 0.0
	var st := Surgery.server_operate(player, player, "stitch", "thigh_l")
	Surgery.force_roll = -1.0
	check(bool(st.ok) and bool(r.stitched) and float(r.heal_total) < 168.0, "stitched: days instead of weeks (%.0f h)" % float(r.heal_total))
	Rpg.set_level(player, "medical", 0)
	player.vitals.server_reset_health()
	await _frames(2)


func _test_sicknesses() -> void:
	print("Sicknesses: a cough, flu spreading, scurvy")
	var n := Survival.needs_of(player)
	Sickness.start(n, "cold")
	(Sickness.ills(n)["cold"] as Dictionary).onset_h = 0.0
	var before := Survival.pressure(level)
	Sickness.server_cough(player)
	check(Sickness.coughing(n) and Survival.pressure(level) > before, "a cold's cough is a noise for the dead (pressure %.2f -> %.2f)" % [before, Survival.pressure(level)])
	Sickness.end(n, "cold")
	var chilled := Needs.fresh()
	chilled.warmth = 35.2
	Sickness.step(chilled, 9.0, {})
	check(Sickness.shows(chilled, "cold"), "hours chilled to the bone: a cold")
	var people: Array = [Needs.fresh(), Needs.fresh(), Needs.fresh(), Needs.fresh()]
	Sickness.start(people[0], "flu")
	(Sickness.ills(people[0])["flu"] as Dictionary).onset_h = 0.0
	Sickness.force_roll = 0.0
	var caught := Sickness.spread(people, 1.0, true)
	Sickness.force_roll = 0.99
	var none := Sickness.spread([Needs.fresh(), people[0]], 1.0, false)
	Sickness.force_roll = -1.0
	check(caught == 3 and Sickness.has(people[3], "flu") and none == 0, "flu spreads in a settlement (%d caught; %d on a lucky roll)" % [caught, none])
	var flu: Dictionary = people[0]
	check(Sickness.stamina_mult(flu) < 0.6 and Sickness.fever_c(flu) > 38.0, "flu: days down")
	var s := Needs.fresh()
	s.vitamin_c = 0.0
	for day in 13:
		Sickness.step(s, 24.0, {})
	check(not Sickness.shows(s, "scurvy"), "13 days without vitamin C: not yet")
	Sickness.step(s, 24.0, {})
	check(Sickness.shows(s, "scurvy"), "two weeks: scurvy")
	var r := Infection.add(s, "forearm_l", "graze")
	r.heal_h = 10.0
	Infection.step(s, 12.0, {"risk": 0.0})
	check(float(r.heal_h) > 10.0, "and old wounds open again (%.1f h of healing left)" % float(r.heal_h))
	s.vitamin_c = 40.0
	Sickness.step(s, 1.0, {})
	check(not Sickness.has(s, "scurvy"), "fruit and greens end it")


func _test_blood() -> void:
	print("Blood types")
	var a := Needs.fresh()
	a["blood_type"] = "A+"
	check(not Sickness.transfuse(a, "O-") and not Sickness.has(a, "transfusion_reaction"), "O negative into A positive: fine")
	check(Sickness.transfuse(a, "B+") and Sickness.shows(a, "transfusion_reaction") and Body.has_fever(a), "B positive into A positive: a reaction")
	check(Sickness.compatible("A-", "AB+") and not Sickness.compatible("AB+", "O+"), "the rules hold both ways")
	check(Sickness.blood_type(Needs.fresh()) in Sickness.BLOOD_TYPES, "everyone has a type")


func _test_water() -> void:
	print("Water works and treating water")
	var zone := String(Survival.state().get("zone", ""))
	WaterWorks.data()[zone] = {"intact": false, "repaired": false}
	check(not WaterWorks.taps_run(zone) and WaterWorks.quality("tap", zone) == "", "the zone's taps are dry")
	var why := WaterWorks.server_repair(zone, player)
	check(why != "", "no parts, no repair (%s)" % why)
	Rpg.set_level(player, "mechanics", 3)
	for it: StringName in [&"machine_parts", &"copper_wire", &"vehicle_battery"]:
		check(player.inventory.take(it, 1) == 1, "he carries %s" % it)
	why = WaterWorks.server_repair(zone, player)
	check(why == "" and WaterWorks.taps_run(zone) and WaterWorks.quality("tap", zone) == "clean", "a mechanic with parts and power: the taps run (%s)" % why)
	check(WaterWorks.quality("river") == "questionable" and WaterWorks.quality("dam") == "clean", "rivers questionable, the dam clean")
	WaterWorks.data()["zone_x"] = {"intact": false, "repaired": false}
	Infrastructure._call_global("WaterWorks", "server_repaired", ["zone_x"])
	check(WaterWorks.taps_run("zone_x"), "the world lane's infrastructure repair reaches the taps (server_repaired)")
	Rpg.set_level(player, "mechanics", 0)
	var item := ItemDB.get_item(&"dirty_water_bottle")
	var n := Needs.fresh()
	Needs.force_roll = 0.0
	var raw := Needs.eat(n, item, {"quality": "dirty"})
	n.sick = {}
	var boiled := WaterWorks.treat({"quality": "dirty"}, "boil")
	var after := Needs.eat(n, item, boiled)
	Needs.force_roll = -1.0
	check(raw == "dysentery" and after == "" and String(boiled.quality) == "clean", "boiling cleans it (raw: %s, boiled: %s)" % [raw, after if after != "" else "fine"])


func _test_seasons() -> void:
	print("The seasons on the body")
	var spring := Needs.fresh()
	var winter := Needs.fresh()
	Needs.step(spring, 3.0, {"dark": 1.0, "wind": 6.0, "season": "spring"})
	Needs.step(winter, 3.0, {"dark": 1.0, "wind": 6.0, "season": "winter"})
	check(float(winter.warmth) < float(spring.warmth) - 0.3, "a winter night drains warmth faster than spring (%.2f vs %.2f C)" % [float(winter.warmth), float(spring.warmth)])
	var dressed := Needs.fresh()
	Needs.step(dressed, 3.0, {"dark": 1.0, "wind": 6.0, "season": "winter", "clothing": 0.5})
	check(float(dressed.warmth) > float(winter.warmth), "layers keep it off (%.2f C)" % float(dressed.warmth))
	var summer := Needs.fresh()
	var mild := Needs.fresh()
	Needs.step(summer, 12.0, {"season": "summer"})
	Needs.step(mild, 12.0, {"season": "spring"})
	check(float(summer.water) < float(mild.water), "summer: thirstier (%.2f vs %.2f l)" % [float(summer.water), float(mild.water)])
	check(BodySeason.heat_gain(summer, {"season": "summer", "moving": true}) > 0.5 and BodySeason.heat_gain(summer, {"season": "spring"}) == 0.0, "summer sun on the move heats the core: heat stroke's road")
	check(is_equal_approx(BodySeason.spoils_days(ItemDB.get_item(&"canned_meat"), "summer"), 1095.0 * 0.5), "food keeps half as long in summer")
	BodySeason.force_season = "winter"
	check(BodySeason.season() == "winter", "the season can be read (forced for the test)")
	BodySeason.force_season = ""


func _test_body_screen() -> void:
	print("The body screen, gated by medical skill")
	var n := Needs.fresh()
	var r := Infection.add(n, "forearm_l", "muscle")
	r.stage = 2
	r.bite = true
	BiteFever.start(n)
	BiteFever.step(n, 30.0, {"abx": false})
	var wl: Array = [{"part": &"forearm_l", "kind": "muscle", "bleeding": true, "rate": 0.05}]
	Rpg.set_level(player, "medical", 0)
	var novice_sees := Rpg.medical_sees(player)
	var novice := String(BodyScreen.part_lines(n, wl, novice_sees).get(&"forearm_l", ""))
	var novice_sum := ", ".join(BodyScreen.summary(n, novice_sees))
	Rpg.set_level(player, "medical", 7)
	var doctor_sees := Rpg.medical_sees(player)
	var doctor := String(BodyScreen.part_lines(n, wl, doctor_sees).get(&"forearm_l", ""))
	var doctor_sum := ", ".join(BodyScreen.summary(n, doctor_sees))
	check(novice_sees == 0 and novice.contains("hurt") and novice.contains("bleeding") and not novice.contains("infected") and not novice_sum.contains("fever"),
		"a novice: \"%s\" / \"%s\"" % [novice, novice_sum])
	check(doctor_sees == 2 and doctor.contains("infected") and doctor.contains("bite") and doctor.contains("not healing") and doctor_sum.contains("fever") and doctor_sum.contains("collapse in"),
		"a doctor: \"%s\" / \"%s\"" % [doctor, doctor_sum])
	var medic := ", ".join(BodyScreen.summary(n, 1))
	check(medic.contains("bitten: fever") and not medic.contains("collapse in"), "a medic: the stage, not the days (\"%s\")" % medic)
	Rpg.set_level(player, "medical", 0)
	var br := BodyReadout.new()
	add_child(br)
	br.visible = true
	br.screen.pick_target()
	br.refresh()
	br.screen.figure.queue_redraw()
	await _frames(3)
	check(br.screen.target == player and br.label.text.begins_with("Body"), "the screen opens on yourself and draws")
	br.queue_free()


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
	Surgery.force_roll = -1.0
	Sickness.force_roll = -1.0
	Needs.force_roll = -1.0
	BodySeason.force_season = ""
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("BODY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
