extends Node3D
## Headless checks for the wound model (Vitals, WoundModel, BodyMap): thresholds, bleeding,
## wound channels and cavitation, fractures, pain and knockout, organs, fragments, hitboxes,
## impact, consciousness (its causes, coming round on its own, SpO2, total trauma; there is
## no revive), what the kit can fix, and the replicated state.
##   <voxel godot exe> --headless --path . res://tests/wounds_test.tscn
## Exits with the number of failures. Dice are seeded, so results repeat.

const RIFLE := Vitals.INTERMEDIATE

var failures := 0


func _ready() -> void:
	_test_thresholds()
	_test_arterial_thigh()
	_test_cavitation()
	_test_fractures()
	_test_pain_knockout()
	_test_organs()
	_test_blood_loss_effects()
	_test_impact()
	_test_consciousness()
	_test_spo2()
	_test_trauma()
	_test_no_revive()
	_test_kit_economy()
	await _test_net_state()
	_test_hitboxes()
	await _test_ballistics_routing()
	await _test_fragments()
	print("WOUNDS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## A Vitals on its own (its parent sits at the origin, so world = rest pose).
func _vitals(seed_value := 1) -> Vitals:
	var vitals := Vitals.new()
	add_child(vitals)
	vitals.rng.seed = seed_value
	return vitals


func _model(seed_value := 1) -> WoundModel:
	var m := WoundModel.new()
	m.rng.seed = seed_value
	m.care_rng.seed = seed_value  # airway dice too, so results repeat
	return m


## Runs a model for `seconds` in the host's 0.1 s steps.
func _step(m: WoundModel, seconds: float) -> void:
	while seconds > 0.0001:
		var dt := minf(seconds, Vitals.SIM_STEP_S)
		m.advance(dt)
		seconds -= dt


## A rifle round straight through the front of a part at `pos` (rest pose).
func _shoot(vitals: Vitals, part: StringName, pos: Vector3, round_class := RIFLE) -> void:
	vitals.server_hit(part, {"round_class": round_class, "position": pos, "direction": Vector3.BACK, "distance": 50.0})


func _chest(m: WoundModel) -> Dictionary:
	for w in m.wounds:
		if w.kind == "chest":
			return w
	return {"tension_in": -1.0}


func _kinds(vitals: Vitals) -> Array:
	return vitals.wound_list().map(func(w: Dictionary) -> String: return w.kind)


func _test_thresholds() -> void:
	print("Blood thresholds")
	var m := _model()
	m.blood = 0.61
	m.update_state(0.0)
	check(not m.unconscious, "39% lost: still conscious")
	m.blood = 0.599
	m.update_state(0.0)
	check(m.unconscious and not m.arrest, "40% lost: unconscious")
	m.blood = 0.499
	m.update_state(0.0)
	check(m.arrest and is_equal_approx(m.arrest_left, Vitals.ARREST_WINDOW_S), "50% lost: cardiac arrest, 10-minute window")
	check(m.bleed_rate() == 0.0, "no heart output in arrest, so no bleeding")
	var vitals := _vitals()
	var died := [false]
	vitals.died.connect(func() -> void: died[0] = true)
	vitals.server_damage(85.0)  # 51% lost
	check(vitals.in_cardiac_arrest() and vitals.downed and vitals.condition_text() == "Cardiac arrest 10:00", "arrest through Vitals (%s)" % vitals.condition_text())
	vitals.server_advance(Vitals.ARREST_WINDOW_S - 1.0)
	check(not died[0] and absf(vitals.seconds_to_death() - 1.0) < 0.2, "alive with %.1f s of the window left" % vitals.seconds_to_death())
	vitals.server_advance(2.0)
	check(died[0] and vitals.is_dead() and vitals.condition_text() == "Dead", "dies when the window runs out")
	vitals.queue_free()


func _test_arterial_thigh() -> void:
	print("Arterial thigh hit")
	var vitals := _vitals(3)
	_shoot(vitals, Vitals.THIGH_R, Vector3(0.0578, 0.70, -0.11))
	var femoral := vitals.wound_list().filter(func(w: Dictionary) -> bool: return w.name == &"femoral_r")
	check(femoral.size() == 1 and femoral[0].kind == "arterial" and is_equal_approx(femoral[0].rate, 1.2), "direct hit on the femoral artery bleeds 1.2 L/min (%s)" % [_kinds(vitals)])
	var seconds := 0.0
	while vitals.blood_fraction() > 1.0 - WoundModel.UNCONSCIOUS_LOST and seconds < 600.0:
		vitals.server_advance(1.0)
		seconds += 1.0
	check(seconds >= 108.0 and seconds <= 192.0, "40%% lost after %.1f min (2-3 min expected)" % (seconds / 60.0))
	check(vitals.downed and vitals.condition_text() == "Unconscious", "and unconscious by then (%s)" % vitals.condition_text())
	var before := vitals.blood_fraction()
	vitals.server_advance(60.0)
	var per_min := (before - vitals.blood_fraction()) * WoundModel.BLOOD_L
	check(per_min < 1.2 * 0.62, "bleeding slows with the heart's output (%.2f L/min at %.0f%%)" % [per_min, before * 100.0])
	vitals.queue_free()
	# The hit itself (pain, a broken femur) rarely knocks you out at once: the blood does it.
	var instant := 0
	for i in 200:
		var t := _vitals(1000 + i)
		_shoot(t, Vitals.THIGH_R, Vector3(0.0578, 0.70, -0.11))
		instant += 1 if t.downed else 0
		t.free()
	check(instant <= 10, "a femoral rifle hit knocks out at once only rarely (%d of 200)" % instant)


func _test_cavitation() -> void:
	print("Wound channels and cavitation")
	var direct := BodyMap.trace(Vitals.THIGH_R, Vector3(0.0578, 0.70, -0.11), Vector3.BACK, RIFLE)
	var near := BodyMap.trace(Vitals.THIGH_R, Vector3(0.0828, 0.70, -0.11), Vector3.BACK, RIFLE)
	var near_pistol := BodyMap.trace(Vitals.THIGH_R, Vector3(0.0828, 0.70, -0.11), Vector3.BACK, Vitals.PISTOL)
	var miss := BodyMap.trace(Vitals.THIGH_R, Vector3(0.14, 0.70, -0.11), Vector3.BACK, RIFLE)
	var femoral := func(channel: Dictionary) -> float:
		for v: Dictionary in channel.vessels:
			if v.name == &"femoral_r":
				return v.share
		return 0.0
	check(is_equal_approx(femoral.call(direct), 1.0), "direct hit: full rate")
	var share: float = femoral.call(near)
	check(share > 0.1 and share < BodyMap.CAVITY_MAX_SHARE, "2.5 cm off with a rifle: inside the cavity, %.0f%% of the rate" % (share * 100.0))
	check(femoral.call(near_pistol) == 0.0, "same channel with a pistol (2 cm reach): missed")
	check(femoral.call(miss) == 0.0, "8 cm off: missed")
	var vitals := _vitals()
	_shoot(vitals, Vitals.THIGH_R, Vector3(0.14, 0.75, -0.11), Vitals.PISTOL)
	check(_kinds(vitals) == ["muscle"], "a miss is a plain muscle wound (%s)" % [_kinds(vitals)])
	vitals.server_reset_health()
	vitals.server_hit(Vitals.THIGH_R, {"round_class": RIFLE, "position": Vector3(0.145, 0.75, -0.02), "direction": Vector3(0.3, 0, 1).normalized()})
	check(_kinds(vitals) == ["graze"], "skimming the edge is a graze (%s)" % [_kinds(vitals)])
	vitals.queue_free()


func _test_fractures() -> void:
	print("Fracture odds by round class")
	var channel := {"graze": false, "depth": 0.15, "vessels": [], "organs": [], "bones": [&"femur_l"]}
	for round_class: StringName in WoundModel.FRACTURE_CHANCE:
		var m := _model(7)
		var broken := 0
		for i in 600:
			m.reset()
			m.add_hit(Vitals.THIGH_L, channel, round_class)
			if m.has_fracture(BodyMap.LEG_BONES, false):
				broken += 1
		var expected: float = WoundModel.FRACTURE_CHANCE[round_class]
		check(absf(broken / 600.0 - expected) < 0.06, "%s: %.0f%% broke (expected %.0f%%)" % [round_class, broken / 6.0, expected * 100.0])
	var leg := _model()
	leg.add_hit(Vitals.THIGH_L, channel, Vitals.FULL_POWER)
	check(not leg.can_sprint() and leg.speed_mult() < 0.7 and leg.pain() >= WoundModel.PAIN_FLOOR_LEG, "broken leg: walk only, heavy pain")
	check(leg.wound_bleed_rate() >= WoundModel.FEMUR_RATE, "a broken femur bleeds internally")
	var arm := _model()
	arm.add_hit(Vitals.UPPER_ARM_R, {"graze": false, "depth": 0.1, "vessels": [], "organs": [], "bones": [&"humerus_r"]}, Vitals.FULL_POWER)
	check(arm.reload_mult() > 1.0 and arm.sway_mult() > 2.0 and arm.can_sprint(), "broken arm: slow reloads and high sway (x%.1f)" % arm.sway_mult())


func _test_pain_knockout() -> void:
	print("Pain and knockout")
	var m := _model()
	m.pain_wounds = 0.89
	m.update_state(0.0)
	check(not m.unconscious, "0.89 pain at full blood: still up")
	m.pain_wounds = 0.9
	m.update_state(0.0)
	check(m.unconscious, "0.9 pain at full blood: knocked out")
	m.reset()
	m.blood = 0.7
	m.pain_wounds = 0.59
	m.update_state(0.0)
	check(not m.unconscious and absf(m.knockout_threshold() - 0.6) < 0.001, "30% lost: the threshold is 0.6")
	m.pain_wounds = 0.61
	m.update_state(0.0)
	check(m.unconscious, "0.61 pain at 30% lost: knocked out")
	m.reset()
	m.blood = 0.85
	check(absf(m.knockout_threshold() - 0.75) < 0.001, "15%% lost: threshold %.2f" % m.knockout_threshold())
	# No dice: once the pain is under the threshold they come round after WAKE_S[pain].
	var pain_wake: float = WoundModel.WAKE_S[&"pain"]
	m.reset()
	m.npa = true
	m.pain_wounds = 0.95
	m.update_state(0.0)
	check(m.unconscious_causes() == [&"pain"], "out from pain alone (%s)" % [m.unconscious_causes()])
	m.pain_wounds = 0.3
	_step(m, pain_wake - 0.5)
	check(m.unconscious and m.wake_left > 0.0, "pain eased: coming round, not yet (%.1f s to go)" % m.wake_left)
	_step(m, 1.0)
	check(not m.unconscious, "awake %.0f s after the pain went under the threshold" % pain_wake)
	var woke := 0
	for i in 100:
		var t := _model(100 + i)
		t.npa = true
		t.pain_wounds = 0.95
		t.update_state(0.0)
		t.pain_wounds = 0.3
		_step(t, pain_wake + 0.3)
		woke += 0 if t.unconscious else 1
	check(woke == 100, "every one of 100 comes round on time: no wake roll (%d)" % woke)
	var relapse := _model(5)
	relapse.npa = true
	relapse.pain_wounds = 0.95
	relapse.update_state(0.0)
	relapse.pain_wounds = 0.3
	_step(relapse, 5.0)
	relapse.pain_wounds = 0.95
	_step(relapse, 1.0)
	check(relapse.unconscious and relapse.wake_left == 0.0, "a cause coming back stops the countdown")
	relapse.pain_wounds = 0.3
	_step(relapse, pain_wake - 1.0)
	check(relapse.unconscious, "and it starts over once it's gone again")
	_step(relapse, 2.0)
	check(not relapse.unconscious, "then he comes round")
	var fade := _model()
	fade.pain_wounds = 0.9
	fade.advance(450.0)
	check(absf(fade.pain() - 0.4) < 0.01, "pain fades over about 15 minutes (0.9 -> %.2f in 7.5 min)" % fade.pain())


func _test_organs() -> void:
	print("Organs")
	var vitals := _vitals()
	_shoot(vitals, Vitals.HEAD, Vector3(0, 1.70, -0.12))
	check(vitals.is_dead(), "brain: a head hit past the helmet is fatal")
	vitals.server_reset_health()
	_shoot(vitals, Vitals.CHEST, Vector3(-0.015, 1.29, -0.11))
	check("heart" in _kinds(vitals) and not vitals.in_cardiac_arrest(), "heart hit (%s)" % [_kinds(vitals)])
	vitals.server_advance(WoundModel.HEART_ARREST_S.y + 0.2)
	check(vitals.in_cardiac_arrest() and vitals.downed, "cardiac arrest within seconds")
	vitals.server_reset_health()
	_shoot(vitals, Vitals.CHEST, Vector3(0.09, 1.32, -0.11))
	check("chest" in _kinds(vitals), "lung hit: an open chest wound (%s)" % [_kinds(vitals)])
	vitals.queue_free()
	# Tension pneumothorax: half of unsealed chest wounds, 60-120 s later, arrest ~90 s after.
	var lung := {"graze": false, "depth": 0.2, "vessels": [], "organs": [&"lung_l"], "bones": []}
	var tension := 0
	var timing_ok := true
	for i in 400:
		var m := _model(200 + i)
		m.add_hit(Vitals.CHEST, lung, Vitals.PISTOL)
		m.pain_wounds = 0.0
		if _chest(m).tension_in < 0.0:
			continue
		tension += 1
		if tension > 20:
			continue
		var t := 0.0
		while not m.arrest and t < 400.0:
			m.advance(1.0)
			t += 1.0
		timing_ok = timing_ok and t >= 60.0 + WoundModel.TENSION_ARREST_S - 1.0 and t <= 120.0 + WoundModel.TENSION_ARREST_S + 1.0
	check(absf(tension / 400.0 - WoundModel.TENSION_CHANCE) < 0.07, "%.0f%% of unsealed chest wounds develop tension" % (tension / 4.0))
	check(timing_ok, "tension then cardiac arrest 150-210 s after the hit")
	var sealed := _model(1)
	for i in 100:
		sealed.reset()
		sealed.add_hit(Vitals.CHEST, lung, Vitals.PISTOL)
		if _chest(sealed).tension_in >= 0.0:
			break
		sealed.rng.seed += 1
	sealed.apply_item(WoundModel.CHEST_SEAL, Vitals.CHEST)
	sealed.advance(1.0)
	sealed.advance(300.0)
	check(not sealed.arrest, "a treated (sealed) chest wound doesn't develop tension")


func _test_blood_loss_effects() -> void:
	print("Blood-loss effects")
	var m := _model()
	m.blood = 0.86
	check(m.sway_mult() == 1.0 and m.speed_mult() == 1.0 and m.stamina_mult() == 1.0 and m.can_sprint(), "under 15% lost: no effect")
	m.blood = 0.7
	check(absf(m.sway_mult() - 1.6) < 0.01 and absf(m.stamina_mult() - 0.64) < 0.01 and absf(m.speed_mult() - 0.88) < 0.01,
		"30%% lost: sway x%.2f, stamina x%.2f, speed x%.2f" % [m.sway_mult(), m.stamina_mult(), m.speed_mult()])
	check(not m.can_sprint(), "no sprint from 30%")
	m.blood = 0.6001
	check(absf(m.sway_mult() - 2.0) < 0.01 and absf(m.stamina_mult() - 0.4) < 0.01 and absf(m.speed_mult() - 0.8) < 0.01, "just under 40%: +100% sway, 40% stamina, 80% speed")
	m.pain_wounds = 0.5
	check(m.sway_mult() > 2.2, "pain adds sway on top")
	check(m.injury() > 0.45, "injury counts blood loss and pain (%.2f)" % m.injury())
	m.pain_wounds = 0.0
	check(m.injury() < 0.45, "blood loss alone stays under the AI's heal mark (%.2f): a kit can't fix it" % m.injury())
	var vitals := _vitals()
	vitals.server_damage(30.0)  # 18% lost
	var early := vitals.vision()
	check(early.fade > 0.0 and early.tunnel == 0.0 and early.black == 0.0, "early shock: colour fades (%.2f)" % early.fade)
	vitals.server_damage(30.0)  # 36% lost
	var severe := vitals.vision()
	check(severe.fade == 1.0 and severe.tunnel > 0.5, "severe shock: tunnel vision (%.2f)" % severe.tunnel)
	vitals.queue_free()


func _test_impact() -> void:
	print("Impact (armor stops)")
	for round_class: StringName in WoundModel.PLATE_IMPACT_PAIN:
		var plate := _model()
		plate.add_impact(Vitals.CHEST, round_class, 300.0, -1.0)
		check(is_equal_approx(plate.pain(), WoundModel.PLATE_IMPACT_PAIN[round_class]), "plate stop, %s: pain +%.2f" % [round_class, plate.pain()])
		var helmet := _model()
		helmet.add_impact(Vitals.HEAD, round_class, 300.0, -1.0)
		check(is_equal_approx(helmet.impact, WoundModel.HELMET_IMPACT_PAIN[round_class]), "helmet stop, %s: pain +%.2f" % [round_class, helmet.impact])
	var stagger := _model()
	stagger.add_impact(Vitals.CHEST, RIFLE, 300.0, -1.0)
	check(stagger.speed_mult() < 1.0 and stagger.sway_mult() > 1.5, "intermediate plate stop: brief stagger")
	stagger.advance(1.0)
	check(stagger.speed_mult() == 1.0, "and it passes")
	var winded := _model()
	winded.add_impact(Vitals.CHEST, Vitals.FULL_POWER, 300.0, -1.0)
	check(winded.stamina_mult() == 0.0 and not winded.can_sprint(), "full-power plate stop: winded")
	winded.advance(WoundModel.WINDED_S + 0.1)
	check(winded.stamina_mult() > 0.0, "for a few seconds")
	var stack := _model()
	stack.add_impact(Vitals.CHEST, Vitals.FULL_POWER, 300.0, -1.0)
	stack.add_impact(Vitals.CHEST, Vitals.FULL_POWER, 300.0, -1.0)
	check(is_equal_approx(stack.impact, 0.6), "impact stacks (%.2f)" % stack.impact)
	stack.advance(300.0)
	check(stack.impact < 0.01, "and fades over about 5 minutes")
	var two := _model(11)
	two.add_impact(Vitals.HEAD, Vitals.FULL_POWER, 300.0, -1.0)
	two.add_impact(Vitals.HEAD, Vitals.FULL_POWER, 300.0, -1.0)
	check(two.unconscious and not two.dead, "two .308 helmet stops from far off: knocked out, alive (pain %.2f)" % two.pain())
	# Concussion odds by class.
	for round_class: StringName in WoundModel.CONCUSSION_CHANCE:
		var concussed := 0
		var m := _model(13)
		for i in 2000:
			m.reset()
			m.add_impact(Vitals.HEAD, round_class, 300.0, -1.0)
			if m.concussion_left > 0.0:
				concussed += 1
		var expected: float = WoundModel.CONCUSSION_CHANCE[round_class]
		check(absf(concussed / 2000.0 - expected) < 0.04, "helmet stop, %s: %.0f%% concussed (expected %.0f%%)" % [round_class, concussed / 20.0, expected * 100.0])
	var conc := _model(17)
	conc._concuss()
	var first := conc.concussion_left
	conc.advance(first + 1.0)
	conc._concuss()
	check(first <= WoundModel.CONCUSSION_KO_S.y + WoundModel.CONCUSSION_S and conc.concussion_left >= 2.0 * WoundModel.CONCUSSION_S,
		"a second concussion in the same fight lasts twice as long (%.0f s, then %.0f s)" % [first, conc.concussion_left])
	check(conc.turn_mult() < 1.0 and conc.sway_mult() > 1.5, "concussion: sway and slow turning")
	# Cracked ribs only within range.
	for round_class: StringName in WoundModel.RIB_RANGE_M:
		var reach: float = WoundModel.RIB_RANGE_M[round_class]
		var inside := 0
		var outside := 0
		var m := _model(19)
		for i in 200:
			m.reset()
			m.add_impact(Vitals.CHEST, round_class, reach - 1.0, -1.0)
			inside += 1 if m.has_kind("rib") else 0
			m.reset()
			m.add_impact(Vitals.CHEST, round_class, reach + 1.0, -1.0)
			outside += 1 if m.has_kind("rib") else 0
		check(inside > 0 and outside == 0, "%s: ribs crack within %d m (%d/200), never beyond" % [round_class, reach, inside])
	var rib := _model()
	rib.add_impact(Vitals.CHEST, Vitals.PISTOL, 5.0, -1.0)
	while not rib.has_kind("rib"):
		rib.reset()
		rib.add_impact(Vitals.CHEST, Vitals.PISTOL, 5.0, -1.0)
	rib.advance(600.0)
	check(rib.stamina_mult() < 1.0 and rib.pain() >= WoundModel.PAIN_FLOOR_RIB, "a cracked rib: pain and slower stamina recovery")
	# When impact can kill.
	var fatal := func(part: StringName, round_class: StringName, distance: float, energy: float) -> int:
		var deaths := 0
		var m := _model(23)
		for i in 300:
			m.reset()
			m.add_impact(part, round_class, distance, energy)
			deaths += 1 if m.dead else 0
		return deaths
	var close: int = fatal.call(Vitals.HEAD, Vitals.FULL_POWER, 50.0, -1.0)
	check(close > 30 and close < 200, "full-power helmet stop at 50 m can be fatal (%d/300)" % close)
	check(fatal.call(Vitals.HEAD, Vitals.FULL_POWER, 250.0, -1.0) == 0, "but not beyond about 200 m")
	check(fatal.call(Vitals.HEAD, Vitals.FULL_POWER, 400.0, 3000.0) > 0, "energy decides when it's known (3000 J)")
	check(fatal.call(Vitals.HEAD, Vitals.FULL_POWER, 50.0, 1500.0) == 0, "a low-energy full-power round isn't fatal")
	check(fatal.call(Vitals.HEAD, RIFLE, 5.0, -1.0) == 0, "an intermediate helmet stop never kills")
	check(fatal.call(Vitals.CHEST, Vitals.FULL_POWER, 5.0, -1.0) == 0, "a plate stop alone never kills")
	var through := _vitals()
	through.server_impact(Vitals.CHEST, Vitals.FULL_POWER, 10.0, 3500.0)
	check(through.wound_list().all(func(w: Dictionary) -> bool: return w.kind == "rib") and through.pain() > 0.25, "server_impact through Vitals (%s)" % through.condition_text())
	through.queue_free()


## Every cause of unconsciousness, as Vitals reports it, and coming round once they're gone.
func _test_consciousness() -> void:
	print("Consciousness follows the body")
	var blood := _model()
	blood.npa = true
	blood.blood = 0.55
	blood._add_wound(Vitals.THIGH_L, "muscle", 0.001)  # a trickle: still bleeding
	blood.update_state(0.0)
	_step(blood, 600.0)
	check(blood.unconscious and blood.unconscious_causes() == [&"blood"] and blood.blood < 0.55,
		"past 40%% lost and still bleeding he stays out and gets no blood back (%s, %.1f%% left after 10 min)" % [blood.unconscious_causes(), blood.blood * 100.0])
	blood.wounds.clear()  # every bleed stopped
	var regained := blood.blood
	_step(blood, 60.0)
	check(is_equal_approx(blood.blood - regained, WoundModel.BLOOD_RECOVER_PER_MIN),
		"with every bleed stopped blood comes back slowly (%.2f%% in a minute)" % ((blood.blood - regained) * 100.0))
	var minutes := 0
	while blood.unconscious and minutes < 30:
		_step(blood, 60.0)
		minutes += 1
	check(not blood.unconscious and blood.lost() < WoundModel.UNCONSCIOUS_LOST,
		"and once he is back under 40%% lost he comes round on his own (%d min)" % minutes)
	var knocked := _model()
	knocked.knockout_left = 8.0
	knocked.update_state(0.0)
	check(knocked.unconscious_causes() == [&"knockout"], "a concussion knockout is a cause")
	_step(knocked, 8.0 + WoundModel.WAKE_S[&"knockout"] + 0.3)
	check(not knocked.unconscious, "and passes (8 s, then %.0f s to come round)" % WoundModel.WAKE_S[&"knockout"])
	var sedated := _model()
	sedated.npa = true
	sedated.morphine_level = WoundModel.MORPHINE_SEDATION_LEVEL + 0.1
	sedated.update_state(0.0)
	check(sedated.unconscious_causes() == [&"morphine"], "morphine over the sedation level is a cause")
	var arrest := _model()
	arrest.blood = 0.49
	arrest.update_state(0.0)
	check(arrest.unconscious_causes().has(&"arrest") and arrest.unconscious_causes().has(&"blood"), "cardiac arrest is a cause (%s)" % [arrest.unconscious_causes()])
	# Through Vitals: why_unconscious and wake_eta, and the woke signal.
	var vitals := _vitals()
	var woke := [false]
	vitals.woke.connect(func() -> void: woke[0] = true)
	vitals._model.npa = true
	vitals._model.pain_wounds = 0.95
	vitals.server_advance(0.1)
	check(vitals.downed and vitals.why_unconscious() == [&"pain"] and vitals.wake_eta() < 0.0, "Vitals: down, why_unconscious %s, not coming round yet" % [vitals.why_unconscious()])
	vitals._model.pain_wounds = 0.3
	vitals.server_advance(0.2)
	check(vitals.downed and vitals.why_unconscious().is_empty() and vitals.wake_eta() > 0.0, "pain gone: nothing keeps him out, %.1f s to come round" % vitals.wake_eta())
	vitals.server_advance(WoundModel.WAKE_S[&"pain"] + 0.3)
	check(vitals.is_up() and woke[0] and vitals.why_unconscious().is_empty() and vitals.wake_eta() < 0.0, "he comes round on his own (woke)")
	vitals.queue_free()


func _test_spo2() -> void:
	print("SpO2")
	var lung := {"graze": false, "depth": 0.2, "vessels": [], "organs": [&"lung_l"], "bones": []}
	var m := _model()
	m.advance(60.0)
	check(absf(m.spo2 - WoundModel.SPO2_NORMAL) < 0.01, "healthy: %.0f%%" % m.spo2)
	m.blood = 0.6001
	m.advance(60.0)
	check(m.spo2 < WoundModel.SPO2_LABOURED and m.spo2 > WoundModel.SPO2_UNCONSCIOUS and m.breathing_laboured(),
		"falls with blood loss: %.1f%% just under 40%% lost (breathing laboured)" % m.spo2)
	var chest := _model()
	chest.add_hit(Vitals.CHEST, lung, Vitals.PISTOL)
	chest.pain_wounds = 0.0
	_chest(chest).tension_in = -1.0
	chest.advance(60.0)
	check(absf(chest.spo2 - (WoundModel.SPO2_NORMAL - WoundModel.SPO2_OPEN_CHEST)) < 0.01 and chest.breathing_laboured() and not chest.unconscious,
		"an open chest wound: %.0f%%, laboured, still up" % chest.spo2)
	chest.apply_item(WoundModel.CHEST_SEAL, Vitals.CHEST)
	chest.advance(10.0)
	check(absf(chest.spo2 - WoundModel.SPO2_NORMAL) < 0.01 and not chest.breathing_laboured(), "sealed: back to %.0f%%" % chest.spo2)
	var tension := _model()
	tension.add_hit(Vitals.CHEST, lung, Vitals.PISTOL)
	tension.pain_wounds = 0.0
	tension.npa = true
	_chest(tension).tension_in = 1.0
	tension.advance(2.0)
	tension.advance(40.0)
	check(tension.unconscious and tension.unconscious_causes() == [&"spo2"] and tension.spo2 < WoundModel.SPO2_BLUE_LIPS,
		"tension pneumothorax: SpO2 %.0f%%, out from it (%s)" % [tension.spo2, tension.unconscious_causes()])
	# Long enough under 70% stops the heart.
	var low := _model()
	low.npa = true
	low.spo2 = 60.0
	low.morphine_level = 8.0  # deep breathing depression keeps it there
	_step(low, WoundModel.SPO2_ARREST_S - 1.0)
	check(not low.arrest and low.unconscious, "under 70%: out, the heart holds a while")
	_step(low, 2.0)
	check(low.arrest, "then cardiac arrest after %.0f s under 70%%" % WoundModel.SPO2_ARREST_S)
	# Vision greys as SpO2 falls (hidden: no number for the player).
	var vitals := _vitals()
	vitals._model.spo2 = 90.0
	var grey := vitals.vision()
	check(grey.fade > 0.4 and grey.tunnel == 0.0, "SpO2 falling greys the view (fade %.2f)" % grey.fade)
	vitals._model.spo2 = 85.5
	check(vitals.vision().tunnel > 0.5, "and closes it in near 85%% (tunnel %.2f)" % vitals.vision().tunnel)
	vitals.queue_free()


func _test_trauma() -> void:
	print("Total trauma")
	var one := _model()
	one.npa = true
	one._add_wound(Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	one._add_wound(Vitals.THIGH_L, "fracture", WoundModel.FEMUR_RATE, &"femur_l")
	one.update_state(0.0)
	check(one.trauma_level > 0.3 and one.trauma_level < WoundModel.TRAUMA_UNCONSCIOUS and not one.unconscious,
		"one serious wound (femoral bleed, broken femur): trauma %.2f, still up" % one.trauma_level)
	var several := _model()
	several.npa = true
	several._add_wound(Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	several._add_wound(Vitals.THIGH_L, "fracture", WoundModel.FEMUR_RATE, &"femur_l")
	several._add_wound(Vitals.THIGH_R, "arterial", 1.2, &"femoral_r")
	several._add_wound(Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
	several.update_state(0.0)
	check(several.unconscious and several.unconscious_causes() == [&"trauma"],
		"several serious wounds: trauma %.2f keeps him out (%s, pain %.2f)" % [several.trauma_level, several.unconscious_causes(), several.pain()])
	for item_part: Array in [[WoundModel.TOURNIQUET, Vitals.THIGH_L], [WoundModel.TOURNIQUET, Vitals.THIGH_R],
			[WoundModel.SPLINT, Vitals.THIGH_L], [WoundModel.CHEST_SEAL, Vitals.CHEST]]:
		several.apply_item(item_part[0], item_part[1])
	check(several.unconscious and several.trauma_target() < 0.6, "all treated: the trauma fades slowly from %.2f toward %.2f" % [several.trauma_level, several.trauma_target()])
	var t := 0.0
	while several.unconscious and t < 600.0:
		_step(several, 1.0)
		t += 1.0
	check(not several.unconscious and t > WoundModel.WAKE_S[&"trauma"], "he comes round %.0f s after the last wound was treated (trauma %.2f)" % [t, several.trauma_level])
	var frag := _model()
	for i in 8:
		frag._add_wound(Vitals.BODY_PARTS[2 + i], "muscle", WoundModel.MUSCLE_RATE * WoundModel.MUSCLE_CLASS_MULT[Vitals.FRAGMENT])
	frag.update_state(0.0)
	check(frag.trauma_level < 0.5, "eight small fragment wounds add up to less (%.2f)" % frag.trauma_level)


## There is no revive anywhere: the API is gone and kits carry none.
func _test_no_revive() -> void:
	print("No revive")
	var vitals := _vitals()
	check(not vitals.has_method(&"server_revive") and not vitals.has_method(&"revive_problem") and not WoundModel.new().has_method(&"revive"),
		"Vitals and WoundModel have no revive")
	var inv := Inventory.new()
	check(not inv.has_method(&"revive_kit") and not inv.has_method(&"take_kit_revive"), "Inventory has no kit revives")
	inv.free()
	var trauma_kit := ItemDB.get_item(&"trauma_kit")
	check(not trauma_kit.stats.has("revives") and not trauma_kit.stats.has("revive_s") and not "revive" in trauma_kit.tags,
		"the trauma kit is only a bag of treatment items")
	vitals.server_damage(85.0)
	vitals.server_reset_health()
	check(vitals.is_up() and vitals.blood_fraction() == 1.0 and vitals.wound_list().is_empty() and vitals.condition_text() == "OK"
		and vitals.spo2() == WoundModel.SPO2_NORMAL and vitals.trauma_level() == 0.0, "reset (respawns, tests): fully restored")
	vitals.queue_free()


## The kit fixes bleeding, chest wounds and pain, not lost blood or internal bleeding, so
## injury() (what AI treats itself on) and needs_treatment() (the "Nothing to treat" check)
## leave those out.
func _test_kit_economy() -> void:
	print("What the kit can fix")
	var m := _model(41)
	while not m.has_fracture(BodyMap.LEG_BONES, true):
		m.add_hit(Vitals.THIGH_L, {"graze": false, "depth": 0.15, "vessels": [], "organs": [], "bones": [&"femur_l"]}, Vitals.FULL_POWER)
	while not m.has_fracture(BodyMap.ARM_BONES, true):
		m.add_hit(Vitals.UPPER_ARM_R, {"graze": false, "depth": 0.1, "vessels": [], "organs": [], "bones": [&"humerus_r"]}, Vitals.FULL_POWER)
	m.add_impact(Vitals.CHEST, Vitals.PISTOL, 5.0, -1.0)
	m.blood = 0.62
	m.update_state(0.0)
	for w in m.wounds.duplicate():
		for item: StringName in [WoundModel.PRESSURE_BANDAGE, WoundModel.SPLINT]:
			m.apply_item(item, w.part)
	m.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	m.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	_step(m, 2.0 * WoundModel.MORPHINE_ABSORB_S + WoundModel.WAKE_S[&"pain"] + 1.0)  # the hits knocked him out: he comes round
	check(m.injury() < 0.45, "broken leg and arm, 38%% lost; bandaged, splinted, two morphine: under the AI's heal mark (%.2f)" % m.injury())
	check(m.care_tasks().is_empty(), "then the kit has nothing left to fix (pain %.2f, %s)" % [m.pain(), m.care_tasks()])
	var gut := _model(43)
	gut.add_hit(Vitals.ABDOMEN, {"graze": false, "depth": 0.2, "vessels": [{"name": &"aorta", "kind": BodyMap.INTERNAL, "rate": 2.5, "share": 0.1}], "organs": [], "bones": []}, Vitals.PISTOL)
	gut.pain_wounds = 0.1
	check(gut.wound_bleed_rate() > 0.0 and gut.treatable() < 0.2 and gut.care_tasks().is_empty(), "internal bleeding: nothing in the kit fixes it, so nothing is asked for (treatable %.2f)" % gut.treatable())
	var vitals := _vitals(47)
	check(not vitals.needs_treatment(), "unhurt: not injured")
	_shoot(vitals, Vitals.THIGH_R, Vector3(0.0578, 0.70, -0.11), Vitals.PISTOL)
	check(vitals.needs_treatment(), "bleeding: needs treatment")
	vitals.queue_free()


func _test_net_state() -> void:
	print("Replicated state")
	var vitals := _vitals(31)
	_shoot(vitals, Vitals.THIGH_R, Vector3(0.0578, 0.70, -0.11))
	vitals.server_damage(20.0)
	vitals.server_advance(30.0)
	var copy := WoundModel.new()
	copy.apply_net(vitals.net_state)
	check(absf(copy.blood - vitals.blood_fraction()) < 0.002 and copy.wounds.size() == vitals.wound_list().size() and copy.unconscious == vitals.downed,
		"net_state rebuilds blood, wounds and consciousness (%d wounds, %.1f%%)" % [copy.wounds.size(), copy.blood * 100.0])
	check(absf(copy.bleed_rate() - vitals.bleed_rate()) < 0.01 and absf(copy.pain() - vitals.pain()) < 0.01, "so a client's queries match the host's")
	vitals.server_apply_treatment(WoundModel.MORPHINE, Vitals.TORSO)
	vitals._model.add_hit(Vitals.CHEST, {"graze": false, "depth": 0.2, "vessels": [], "organs": [&"lung_l"], "bones": []}, Vitals.PISTOL)
	vitals.server_advance(20.0)
	copy.apply_net(vitals.net_state)
	check(absf(copy.spo2 - vitals.spo2()) <= 0.25 and absf(copy.morphine_level - vitals.morphine_level()) < 0.006
		and absf(copy.trauma_level - vitals.trauma_level()) < 0.006 and absf(copy.morphine_relief() - vitals._model.morphine_relief()) < 0.01,
		"SpO2 %.1f%%, morphine %.2f and trauma %.2f replicate" % [copy.spo2, copy.morphine_level, copy.trauma_level])
	check(copy.unconscious_causes() == vitals._model.unconscious_causes() and copy.breathing_laboured() == vitals.breathing_laboured()
		and absf(copy.pain() - vitals.pain()) < 0.01, "so every peer works out the same causes, cues and pain (%s)" % [copy.unconscious_causes()])
	var published := vitals.net_state
	var was_down := vitals.downed
	vitals.server_damage(1.0)
	check(vitals.downed != was_down or vitals.net_state == published, "a routine change waits for the next update (at most 2 Hz)")
	await get_tree().create_timer(Vitals.NET_INTERVAL_S + 0.2).timeout
	check(vitals.net_state != published, "and goes out once the interval has passed")
	vitals.server_damage(40.0)
	check(vitals.downed and int(vitals.net_state.f) & 1 != 0, "going unconscious publishes at once")
	vitals.queue_free()


## Every hitbox in the soldier and dummy scenes names a real body part, matches BodyMap's
## volumes, and the body parts are all covered exactly once.
func _test_hitboxes() -> void:
	print("Hitboxes")
	for path: String in ["res://scenes/soldier.tscn", "res://scenes/target_dummy.tscn"]:
		var body: Node3D = load(path).instantiate()
		var parts: Array[StringName] = []
		var valid := true
		for child in body.get_children():
			var area := child as Area3D
			if area == null:
				continue
			var part: StringName = area.get_meta(&"body_part", &"")
			parts.append(part)
			valid = valid and part in Vitals.BODY_PARTS and area.collision_layer == 2 and area.collision_mask == 0 \
				and not area.monitoring and area.transform == Transform3D.IDENTITY
			var boxes: Array = BodyMap.PART_BOXES.get(part, [])
			var shapes := area.get_children().filter(func(n: Node) -> bool: return n is CollisionShape3D)
			valid = valid and shapes.size() == boxes.size()
			for i in mini(shapes.size(), boxes.size()):
				var shape: CollisionShape3D = shapes[i]
				valid = valid and shape.position.is_equal_approx(boxes[i][0]) and (shape.shape as BoxShape3D).size.is_equal_approx(boxes[i][1])
		parts.sort()
		var expected := Vitals.BODY_PARTS.duplicate()
		expected.sort()
		check(valid and parts == expected, "%s: %d hitboxes, one per body part, matching BodyMap" % [path.get_file(), parts.size()])
		body.free()


func _test_ballistics_routing() -> void:
	print("Ballistics routes shots to body parts")
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	add_child(dummy)
	dummy.respawn_seconds = 999.0
	var shooter := StaticBody3D.new()
	add_child(shooter)
	var rifle := ItemDB.get_item(&"m4a1")
	var wrong := PackedStringArray()
	for part: StringName in Vitals.BODY_PARTS:
		dummy.vitals.server_reset_health()
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var box: Array = BodyMap.PART_BOXES[part][0]
		var target: Vector3 = box[0] - Vector3(0, 0, box[1].z * 0.5)
		shooter.position = target + Vector3(0, 0, -5)
		var result := Ballistics.fire(shooter, shooter.position, Vector3.BACK, rifle)
		var hit := dummy.vitals.is_dead() if part in [Vitals.HEAD, Vitals.FACE] else dummy.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part == part)
		if result.result != "body" or not hit:
			wrong.append("%s (%s, %s)" % [part, result.result, dummy.vitals.wound_list().map(func(w: Dictionary) -> StringName: return w.part)])
	check(wrong.is_empty(), "a shot at each of the 14 parts wounds that part %s" % wrong)
	# Lying down, the channel still follows the part: a shot down into the back of the chest.
	dummy.vitals.server_reset_health()
	dummy.vitals.server_damage(70.0)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var chest: Area3D = dummy.get_node(^"ChestHitbox")
	var back := chest.global_transform * Vector3(0, 1.31, 0.11)
	shooter.position = back + Vector3.UP * 3.0
	var down := Ballistics.fire(shooter, shooter.position, Vector3.DOWN, rifle)
	var parts := dummy.vitals.wound_list().map(func(w: Dictionary) -> StringName: return w.part)
	check(down.result == "body" and Vitals.CHEST in parts, "a downed body's hitboxes lie with it: shot in the back hits the chest (%s)" % [parts])
	shooter.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _test_fragments() -> void:
	print("Fragments")
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	add_child(dummy)
	dummy.respawn_seconds = 999.0
	seed(37)
	var counts_ok := true
	var wounds_ok := true
	var serious := 0
	var min_count := 99
	var max_count := 0
	for i in 30:
		dummy.vitals.server_reset_health()
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var count := Throwables.frag_body(dummy, dummy.vitals, Vector3(0.3, 0.6, -1.2), 1.3)
		min_count = mini(min_count, count)
		max_count = maxi(max_count, count)
		counts_ok = counts_ok and count >= Throwables.FRAG_MIN_WOUNDS and count <= Throwables.FRAG_MAX_WOUNDS
		var kinds := _kinds(dummy.vitals)
		if not dummy.vitals.is_dead():
			wounds_ok = wounds_ok and kinds.size() >= count
		if kinds.any(func(k: String) -> bool: return k in ["arterial", "junctional", "internal", "chest", "heart"]) or dummy.vitals.is_dead():
			serious += 1
	check(counts_ok and wounds_ok, "a close blast makes 3 to 8 fragment wounds (%d to %d over 30 blasts)" % [min_count, max_count])
	check(serious >= 3 and serious <= 15, "sometimes one is arterial or a chest wound (%d of 30)" % serious)
	dummy.vitals.server_reset_health()
	await get_tree().process_frame
	await get_tree().physics_frame
	var far := 0
	for i in 40:
		far += 1 if Throwables.frag_body(dummy, dummy.vitals, Vector3(0, 0.6, -7.5), 7.5) > 0 else 0
	check(far < 20, "near the edge of the radius most blasts miss (%d of 40 hit)" % far)
	dummy.queue_free()
