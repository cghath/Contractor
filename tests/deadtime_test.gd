extends Node
## The dead over time (docs/survival_deadtime.md; survival.md calls 112, 114, 115, 140): in a
## hosted survival world: a fresh one of the dead is faster, hits harder and has more pool than an
## old one, and the old one's limbs come apart; the world's date sets the mix of stages and winter
## keeps them (no decay); the look meta and the clothes change with the stage; the crowd's heads
## carry their stage and origin; one of the dead at a military site has a rifle and plates on it,
## at a clinic a doctor's bag, and they stay on the corpse for the looting; a site's mix of origins
## says what it was; a nest holds its heads by day, pours them out at dusk and takes them back at
## dawn; a nest entered by day lies dormant, a silent kill leaves the rest asleep, a scream wakes
## them all; clearing it flags the payoff and it refills over the days; walkers don't climb, a
## runner vaults a metre, a crawler squeezes a 0.4 m gap and the dead's paths keep off climb links.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("DEADTIME TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if level != null and player != null:
		await _test_decay()
		_test_mix()
		await _test_dress()
		await _test_nests()
		await _test_climb()
	_finish()


func _test_host() -> void:
	print("A survival world")
	check(Survival.server_new_world(main, "test_deadtime" + tag, 777), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	for i in 120:
		await get_tree().process_frame
	Survival._pop = -100000.0  # (the test puts the dead down itself)
	Seasons.force_frost = 0
	DeadNests.force_hour = 12.0
	Survival.state()["nests_seeded_" + String(Survival.state().get("zone", ""))] = true  # (the zone's own nests left out: the test makes its own)
	DeadNests.all().clear()
	_clear_dead()


func _test_decay() -> void:
	print("Decay stages (call 112)")
	Survival.state()["fall_weeks"] = 3
	var now := DeadDecay.kept_since()
	var fresh := _zombie(Vector3(70, 0, 0), "walker", {"turned": now})
	var old := _zombie(Vector3(70, 0, 6), "walker", {"turned": now - 400.0})
	await get_tree().process_frame
	check(fresh != null and old != null, "a fresh one and an old one")
	if fresh == null or old == null:
		return
	var fb := ZombieAI.of(fresh)
	var ob := ZombieAI.of(old)
	check(String(fresh.get_meta(&"dead_decay", "")) == "fresh" and String(old.get_meta(&"dead_decay", "")) == "old",
		"the look meta says the age (%s, %s)" % [fresh.get_meta(&"dead_decay", "?"), old.get_meta(&"dead_decay", "?")])
	check(fb != null and ob != null and fb.pace() > ob.pace() * 1.2, "the fresh one is faster (%.2f vs %.2f)" % [fb.pace() if fb else 0.0, ob.pace() if ob else 0.0])
	check(fresh.vitals.undead_pool > old.vitals.undead_pool * 1.5, "and has more pool (%.1f vs %.1f)" % [fresh.vitals.undead_pool, old.vitals.undead_pool])
	check(DeadDecay.strike_mult(fresh) > DeadDecay.strike_mult(old), "and hits harder (x%.2f vs x%.2f)" % [DeadDecay.strike_mult(fresh), DeadDecay.strike_mult(old)])
	check(DeadDecay.limb_mult(old, &"forearm_l") > DeadDecay.limb_mult(fresh, &"forearm_l") and is_equal_approx(DeadDecay.limb_mult(old, Vitals.HEAD), 1.0),
		"an old one's limbs come apart easier (x%.2f), its head no different" % DeadDecay.limb_mult(old, &"forearm_l"))
	var fskin := fresh.variant.split(":")
	var oskin := old.variant.split(":")
	check(fskin.size() >= 5 and oskin.size() >= 5 and fskin[3] != oskin[3], "the skin goes from flesh-grey to bone (%s -> %s)" % [fskin[3] if fskin.size() > 3 else "?", oskin[3] if oskin.size() > 3 else "?"])
	var plain := "civ:a65e48:3b4a63:c8996f:6b4a2b"
	var aged := DeadDecay.look(plain, 1.0).split(":")
	check(Color(aged[1]).s < Color("a65e48").s and Color(aged[1]).v < Color("a65e48").v, "an old one's clothes are greyed and dirtied (%s)" % aged[1])
	# The crowd's heads carry it.
	var crowd := ZoneDead.of(level)
	check(crowd != null and crowd.server_add(level.ground_point(player.global_position + Vector3(150, 0, 0))), "a head in the crowd")
	if crowd:
		var d: Dictionary = crowd.dead[crowd.dead.size() - 1]
		check(d.has("turned") and String(d.get("origin", "")) in DeadDress.ORIGIN_NAMES and ZoneDead.stage_of(d) in DeadDecay.STAGES,
			"the crowd's head carries its age and origin (%s, %s)" % [ZoneDead.stage_of(d), d.get("origin", "?")])
		var back := DeadDecay.carry(old)
		check(is_equal_approx(float(back.turned), float(old.get_meta(&"dead_turned"))) and String(back.origin) == String(old.get_meta(&"dead_origin")),
			"a body going back into the crowd keeps both")
		crowd.dead.clear()
	_clear_dead()
	await get_tree().process_frame


func _test_mix() -> void:
	print("The world's date sets the mix")
	Survival.state()["fall_weeks"] = 3
	var early := DeadDecay.mix(1.0)
	var late := DeadDecay.mix(60.0)
	check(float(early.fresh) > 0.6 and float(late.old) > float(early.old) + 0.3 and float(late.fresh) < float(early.fresh),
		"early on most are fresh (%s); months on most are old (%s)" % [_pct(early), _pct(late)])
	var a := DeadDecay.kept_since(31.0)
	var b := DeadDecay.kept_since(41.0)
	check(Seasons.of_day(35, "spring") == "winter" and is_equal_approx(a, b) and DeadDecay.kept_since(51.0) > b,
		"winter's days don't rot them: the frozen keep (%.0f = %.0f story days, then %.0f)" % [a, b, DeadDecay.kept_since(51.0)])
	check(DeadDecay.count_mult(60.0) > DeadDecay.count_mult(1.0), "and there are more of them as the months go (x%.2f -> x%.2f)" % [DeadDecay.count_mult(1.0), DeadDecay.count_mult(60.0)])


func _test_dress() -> void:
	print("The dead wear what they were (call 114)")
	DeadDress.force_site = "hq"
	var soldiers: Array = []
	for i in 8:
		var z := _zombie(Vector3(80, 0, i * 2.0), "walker")
		if z and String(z.get_meta(&"dead_origin", "")) == "soldier":
			soldiers.append(z)
	DeadDress.force_site = "clinic"
	var doctors: Array = []
	for i in 8:
		var z := _zombie(Vector3(86, 0, i * 2.0), "walker")
		if z and String(z.get_meta(&"dead_origin", "")) == "doctor":
			doctors.append(z)
	DeadDress.force_site = ""
	await get_tree().process_frame
	check(not soldiers.is_empty() and not doctors.is_empty(), "the base's dead are mostly soldiers (%d of 8), the clinic's doctors (%d of 8)" % [soldiers.size(), doctors.size()])
	if soldiers.is_empty() or doctors.is_empty():
		return
	var s: Soldier = soldiers[0]
	var inv := s.inventory
	check(DeadDress.carried(inv, &"m4a1") > 0 and DeadDress.carried(inv, &"plate_steel_l3") > 0 and DeadDress.carried(inv, &"plate_carrier_light") > 0,
		"a soldier has a rifle and plates on him (%s)" % [Survival.kit_of(inv).map(func(e: Dictionary) -> String: return String(e.id))])
	check(inv.slots[&"primary"] == &"" and inv.slots[&"sidearm"] == &"" and s.active_weapon() == null, "and the rifle rides in his pack: the dead don't use weapons")
	var shirt := s.variant.split(":")[1]
	check(Color(shirt).g >= Color(shirt).b, "and he's in uniform colours (%s)" % shirt)
	var doc: Soldier = doctors[0]
	check(DeadDress.carried(doc.inventory, &"aid_bag") > 0 and DeadDress.carried(doc.inventory, &"suture_kit") > 0, "a doctor has a doctor's bag and meds")
	var hz := _zombie(Vector3(92, 0, 0), "hazmat")
	check(hz != null and String(hz.get_meta(&"dead_origin", "")) == "soldier" and DeadDress.carried(hz.inventory, &"gas_mask_m50") > 0 and DeadDress.carried(hz.inventory, &"plate_steel_l3") > 0,
		"the hazmat one was a soldier of the decon teams: plates and a mask")
	# Loot yields them: the corpse keeps it all.
	s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "energy_j": 400.0})
	for i in 6:
		await get_tree().process_frame
	check(s.vitals.is_dead() and DeadDress.carried(s.inventory, &"m4a1") > 0 and DeadDress.carried(s.inventory, &"plate_steel_l3") > 0,
		"put down, his corpse still has the rifle and the plates to loot")
	# A site's mix of origins tells what it was.
	check(DeadDress.leading(DeadDress.site_mix("hq")) == "soldier" and DeadDress.leading(DeadDress.site_mix("clinic")) == "doctor"
		and DeadDress.leading(DeadDress.site_mix("police")) == "cop" and DeadDress.leading(DeadDress.site_mix("farm")) == "farmer"
		and DeadDress.leading(DeadDress.site_mix("factory")) == "worker", "a site's mix of origins tells its type")
	DeadDress.force_site = "police"
	var line := DeadDress.tell(level, player.global_position + Vector3(0, 0, -300), 5.0)
	DeadDress.force_site = ""
	check("Police" in line, "a place's dead say what it was (%s)" % line)
	_clear_dead()
	await get_tree().process_frame


func _test_nests() -> void:
	print("Nests and roosts (call 115)")
	var crowd := ZoneDead.of(level)
	crowd.dead.clear()
	DeadNests.force_hour = 12.0
	var at := player.global_position + Vector3(0, 0, 150)
	var id := DeadNests.server_add(level, "nest_test", at, 6, "church")
	DeadNests.server_tick(level)
	var rec := DeadNests.get_nest(id)
	check(not bool(rec.out) and int(rec.n) == 6 and _tagged(id) == 0, "by day the nest holds its six inside, none drawn outside")
	DeadNests.force_hour = 20.0
	DeadNests.server_tick(level)
	check(bool(rec.out) and int(rec.n) == 0 and _tagged(id) == 6, "at dusk they pour out of its door (%d in the crowd)" % _tagged(id))
	for d: Dictionary in crowd.dead:
		if String(d.get("nest", "")) == id:
			d.pos = d.to  # (the night out: they've walked off round it)
	DeadNests.force_hour = 6.5
	DeadNests.server_tick(level)
	var walking_back := crowd.dead.filter(func(d: Dictionary) -> bool: return String(d.get("nest", "")) == id and (d.target as Vector2).distance_to(Vector2(at.x, at.z)) < 3.0).size()
	check(walking_back == 6, "at dawn they walk back to it (%d)" % walking_back)
	DeadNests.force_hour = 8.5
	DeadNests.server_tick(level)
	check(not bool(rec.out) and int(rec.n) == 6 and _tagged(id) == 0, "and are counted back in (%d inside)" % int(rec.n))
	if not level.modules().is_empty():
		var mod: ZoneModule = level.modules()[0]
		var mid := DeadNests.server_add(level, "nest_" + mod.module_id, mod.global_position, 4)
		var by_day := DeadNests.outside_mult(mod)
		DeadNests.force_hour = 22.0
		var by_night := DeadNests.outside_mult(mod)
		DeadNests.force_hour = 8.5
		check(is_equal_approx(by_day, DeadNests.OUTSIDE_BY_DAY) and is_equal_approx(by_night, 1.0), "by day a site's dead sit in its nest: fewer about it outside (x%.1f by day, x%.1f by night)" % [by_day, by_night])
		DeadNests.all().erase(mid)
	# Entering it by day: dormant.
	DeadNests.force_hour = 12.0
	var made := DeadNests.server_enter(level, id)
	await get_tree().process_frame
	var bodies := DeadNests.bodies(level, id)
	check(made == 6 and bodies.size() == 6 and bodies.all(func(z: Soldier) -> bool: return ZombieAI.of(z) != null and ZombieAI.of(z).dormant and ZombieAI.of(z).unaware()),
		"entered by day, the six lie dormant, packed by the door (%d)" % bodies.size())
	for i in 30:
		await get_tree().physics_frame
	var first: Soldier = bodies[0]
	first.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "channel_depth": 0.08, "melee": "silent", "energy_j": 400.0})
	for i in 10:
		await get_tree().physics_frame
	var asleep := DeadNests.bodies(level, id).filter(func(z: Soldier) -> bool: return ZombieAI.of(z).dormant).size()
	check(first.vitals.is_dead() and asleep == 5 and int(rec.inside) == 5, "a silent kill leaves the rest asleep (%d dormant)" % asleep)
	var screamer: Soldier = DeadNests.bodies(level, id)[0]
	Survival.server_noise(screamer, screamer.global_position, ZombieAI.SCREAM_M, ZombieAI.HEAR_SHOT)
	await get_tree().physics_frame
	var awake := DeadNests.bodies(level, id).filter(func(z: Soldier) -> bool: return not ZombieAI.of(z).dormant and ZombieAI.of(z).awareness >= 0.99).size()
	check(awake == 5, "a scream wakes them all at once (%d of 5)" % awake)
	for z: Soldier in DeadNests.bodies(level, id):
		z.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "energy_j": 400.0})
	for i in 10:
		await get_tree().physics_frame
	check(bool(rec.cleared) and DeadNests.loot_bonus(id), "the last of it down clears the nest: its loot untouched (the payoff flag)")
	var journal: Array = Survival.state().get("journal", [])
	check(not journal.is_empty() and "nest" in String((journal[journal.size() - 1] as Dictionary).text), "and the journal says so")
	var day0 := Survival.day()
	Survival.state()["day"] = day0 + 2
	DeadNests._refill(rec)
	check(int(rec.n) > 0 and int(rec.n) < int(rec.cap), "it refills slowly (%d of %d after two days)" % [int(rec.n), int(rec.cap)])
	Survival.state()["day"] = day0
	check(DeadNests.take_bonus(id) and not DeadNests.loot_bonus(id), "the payoff is taken once")
	DeadNests.all().erase(id)
	_clear_dead()
	await get_tree().process_frame


func _test_climb() -> void:
	print("Climbing rules (call 140)")
	check(not ZombieAI.can_climb("walker") and not ZombieAI.can_climb("runner") and not ZombieAI.can_get_up("walker", 1.0), "walkers don't climb a ladder or get up a metre")
	check(ZombieAI.can_get_up("runner", 1.0) and not ZombieAI.can_get_up("runner", 1.4), "a runner vaults a metre, not more")
	check(ZombieAI.can_pass_gap("crawler", 0.4) and not ZombieAI.can_pass_gap("walker", 0.4) and not ZombieAI.can_pass_gap("runner", 0.4), "a crawler squeezes through a 0.4 m gap, nobody else")
	check(is_equal_approx(ZombieAI.VAULT_M, Sieges.VAULT_M) and (ZombieAI.NAV_LAYERS & ZombieAI.CLIMB_LAYER) == 0, "the walls' vault matches, and the dead's paths keep off climb links")
	var w := _zombie(Vector3(70, 0, -10), "walker")
	var r := _zombie(Vector3(70, 0, -14), "runner")
	await get_tree().process_frame
	if w and r:
		var wb := ZombieAI.of(w)
		var rb := ZombieAI.of(r)
		check(wb.ledge_blocked(w.global_position + Vector3(1, 3.0, 0)) and not rb.ledge_blocked(r.global_position + Vector3(1, 1.0, 0)),
			"a man on a 3 m platform is out of a walker's reach; a runner gets up a metre")
	_clear_dead()


func _tagged(id: String) -> int:
	return ZoneDead.of(level).dead.filter(func(d: Dictionary) -> bool: return String(d.get("nest", "")) == id and bool(d.alive)).size()


func _pct(m: Dictionary) -> String:
	return "%.0f%% fresh, %.0f%% worn, %.0f%% old" % [float(m.fresh) * 100.0, float(m.worn) * 100.0, float(m.old) * 100.0]


func _zombie(off: Vector3, kind := "walker", extra := {}) -> Soldier:
	return Survival.server_spawn_zombie(level, level.ground_point(player.global_position + off), kind, extra)


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var crowd := ZoneDead.of(level)
	if crowd:
		crowd.dead.clear()


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
	Seasons.force_frost = -1
	DeadNests.force_hour = -1.0
	DeadDecay.force_day = -1.0
	DeadDress.force_site = ""
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("DEADTIME TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
