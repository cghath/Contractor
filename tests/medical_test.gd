extends Node3D
## Headless checks for the kit and treatment (design doc "The kit", "Tourniquet", "Fractures",
## "Chest"): each item's effect, the rushed and second tourniquet, packing then taking a
## tourniquet off, seals and tension, splints, morphine as a level in the blood (relief,
## sedation, slowed breathing), NPAs and airway obstruction, care_needed's order, treatment
## waking a casualty (there is no revive), kits as bags of items, and, in a hosted session,
## the timed host requests (times on yourself and others, interruptions and their session-log
## lines: who moved the casualty, how far; H, the Treat menu,
## a casualty coming round once treated).
##   <voxel godot exe> --headless --path . res://tests/medical_test.tscn
## Exits with the number of failures. Rule dice are seeded, so results repeat.

const SPOT := Vector3(0, 0.1, 20)

var failures := 0
var level: CompoundLevel
var player: Soldier
var casualty: Soldier
var helper: Soldier


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("MEDICAL TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_tourniquet()
	_test_rushed_tourniquet()
	_test_packing_and_removal()
	_test_bandage_and_gauze()
	_test_chest_seal()
	_test_splint()
	_test_morphine()
	_test_impact_pain()
	_test_airway()
	_test_care_order()
	_test_bone_care()
	_test_treatment_wakes()
	_test_dying()
	_test_kits()
	_test_iv_fluids()
	_test_heart()
	_test_consumables()
	_test_surgery_and_damage()
	await _start_session()
	await _test_times()
	await _test_completed_treatments()
	await _test_interruptions()
	await _test_one_treater_per_site()
	await _test_casualty_kit_for_players()
	await _test_care_plan_moves_on()
	await _test_use_medical()
	await _test_consume_in_session()
	await _test_menu_and_removal()
	await _test_medical_menu()
	await _test_medical_menu_scrolls()
	await _test_menu_prefers_living()
	await _test_bleed_hud()
	await _test_wakes_in_session()
	await _test_splint_movement()
	GameState.delete_save()
	print("MEDICAL TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Rules (Vitals and WoundModel on their own) ------------------------------------------

func _test_tourniquet() -> void:
	print("Tourniquet")
	var v := _vitals()
	_wound(v, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	_wound(v, Vitals.SHIN_L, "venous", 0.3)
	_wound(v, Vitals.FOREARM_R, "muscle", 0.25)
	var pain := v.pain()
	var first := v.care_needed()[0]
	check(first.item == &"tourniquet" and first.part == Vitals.THIGH_L and first.kind == "arterial", "care_needed: a tourniquet on the left thigh first (%s)" % [first])
	check(v.treatment_problem(&"tourniquet", Vitals.CHEST) != "", "not on the chest (%s)" % v.treatment_problem(&"tourniquet", Vitals.CHEST))
	check(v.server_apply_treatment(&"tourniquet", Vitals.THIGH_L), "a tourniquet goes on the thigh")
	var on_leg := v.wound_list().filter(func(w: Dictionary) -> bool: return w.part in [Vitals.THIGH_L, Vitals.SHIN_L])
	check(on_leg.all(func(w: Dictionary) -> bool: return not w.bleeding and w.tourniquet), "it stops all the bleeding below it on that leg")
	check(absf(v.bleed_rate() - 0.25) < 0.001, "but not the arm's (%.2f L/min)" % v.bleed_rate())
	check(absf(v.pain() - pain - WoundModel.TOURNIQUET_PAIN) < 0.001, "it adds pain (%.2f -> %.2f)" % [pain, v.pain()])
	check(absf(v.speed_mult() - WoundModel.TOURNIQUET_LEG_SPEED) < 0.001 and not v.can_sprint(), "a leg tourniquet: a limp (speed x%.2f), no sprint" % v.speed_mult())
	check(not v.care_needed().any(func(t: Dictionary) -> bool: return t.part in [Vitals.THIGH_L, Vitals.SHIN_L]), "nothing more is asked for that leg")
	var arm := _vitals()
	_wound(arm, Vitals.UPPER_ARM_R, "arterial", 1.2, &"brachial_r")
	arm.server_apply_treatment(&"tourniquet", Vitals.UPPER_ARM_R)
	check(arm.bleed_rate() == 0.0 and arm.speed_mult() == 1.0 and arm.can_sprint(), "an arm tourniquet stops the bleeding without a limp")
	check(not arm.server_apply_treatment(&"tourniquet", Vitals.FOREARM_R), "nothing left bleeding below it: no second one needed")
	v.queue_free()
	arm.queue_free()


## Conscious but dying (Captain, 2026-10-20): blood running out with a wound still bleeding puts
## a conscious soldier on the ground, dying; a tourniquet ends it after DYING_CLEAR_S; it
## travels in the flags to every peer.
func _test_dying() -> void:
	print("Conscious but dying")
	var v := _vitals()
	_wound(v, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	check(not v.is_dying(), "a fresh arterial bleed: not dying yet")
	v._model.blood = 1.0 - WoundModel.DYING_LOST - 0.02
	v._model.update_state(0.1)
	check(v.is_dying() and v.is_up() and not v.is_unconscious() and v.condition_text() == "Dying",
		"%.0f%% of the blood gone and still bleeding: conscious but dying (%s)" % [(WoundModel.DYING_LOST + 0.02) * 100.0, v.condition_text()])
	var copy := WoundModel.new()
	copy.apply_net(v._model.to_net())
	check(copy.dying, "every peer sees it (the flags carry it)")
	v.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	v._model.update_state(1.0)
	check(v.is_dying(), "a tourniquet on: still dying a moment (DYING_CLEAR_S)")
	for i in 5:
		v._model.update_state(1.0)
	check(not v.is_dying(), "the bleeding stopped: he comes back out of it")
	v.queue_free()


func _test_rushed_tourniquet() -> void:
	print("Rushed tourniquet")
	var v := _vitals()
	_wound(v, Vitals.THIGH_R, "arterial", 1.2, &"femoral_r")
	v.server_apply_treatment(&"tourniquet", Vitals.THIGH_R, true)
	check(absf(v.bleed_rate() - 1.2 * 0.3) < 0.001, "rushed: bleeding cut by only 70%% (%.2f L/min)" % v.bleed_rate())
	var first := v.care_needed()[0]
	check(first.item == &"tourniquet" and first.part == Vitals.THIGH_R, "care_needed asks for a second tourniquet (%s)" % [first])
	check(v.server_apply_treatment(&"tourniquet", Vitals.THIGH_R, true) and v.bleed_rate() == 0.0, "a second one beside it (even rushed) stops it")
	check(v.treatment_problem(&"tourniquet", Vitals.THIGH_R) == "Already two tourniquets there", "no room for a third")
	check(v.tourniquets()[Vitals.THIGH_R].count == 2, "two tourniquets on the right thigh")
	v.queue_free()


func _test_packing_and_removal() -> void:
	print("Packing a tourniquet's wound, then taking it off")
	var v := _vitals()
	_wound(v, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	check(v.treatment_problem(&"hemostatic_gauze", Vitals.THIGH_L) == "Put a tourniquet on first", "gauze alone doesn't stop a limb artery")
	check(not v.care_needed().any(func(t: Dictionary) -> bool: return t.item == &"hemostatic_gauze"), "and care_needed doesn't ask for it")
	v.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	check(v.removal_problem(Vitals.THIGH_L) == "Pack the wound first" and v.server_remove_tourniquets(Vitals.THIGH_L) == 0, "the tourniquet can't come off before packing")
	check(v.server_apply_treatment(&"hemostatic_gauze", Vitals.THIGH_L), "gauze packs the wound under the tourniquet")
	var w := v.wound_list()[0]
	check(w.packed and w.treated, "packed (%s)" % [w])
	check(v.removal_problem(Vitals.THIGH_L) == "" and v.server_remove_tourniquets(Vitals.THIGH_L) == 1, "then the tourniquet comes off")
	check(v.bleed_rate() == 0.0 and v.speed_mult() == 1.0 and v.can_sprint() and v.tourniquets().is_empty(), "no bleeding, no limp")
	v.queue_free()


func _test_bandage_and_gauze() -> void:
	print("Pressure bandage and hemostatic gauze")
	var v := _vitals()
	for kind: String in ["venous", "muscle", "graze"]:
		v.server_reset_health()
		_wound(v, Vitals.FOREARM_L, kind, 0.2)
		check(v.care_needed()[0].item == &"pressure_bandage" and v.server_apply_treatment(&"pressure_bandage", Vitals.FOREARM_L) and v.bleed_rate() == 0.0,
			"a pressure bandage stops a %s wound" % kind)
	v.server_reset_health()
	_wound(v, Vitals.NECK, "junctional", 0.8, &"common_carotid_l")
	check(v.care_needed()[0].item == &"hemostatic_gauze" and v.care_needed()[0].part == Vitals.NECK, "a junctional bleed asks for gauze")
	check(not v.server_apply_treatment(&"pressure_bandage", Vitals.NECK), "a bandage doesn't fix it")
	check(v.server_apply_treatment(&"hemostatic_gauze", Vitals.NECK) and is_equal_approx(v.bleed_rate(), 0.8 * WoundModel.NECK_LEAK)
		and v.wound_list()[0].packed, "gauze packs a massive neck wound, leaving its defined residual bleed")
	check(v.care_needed().any(func(t: Dictionary) -> bool: return t.part == Vitals.NECK and t.item == &"surgical_clamp")
		and not v.care_needed().any(func(t: Dictionary) -> bool: return t.part == Vitals.NECK and t.item == &"hemostatic_gauze"),
		"the care plan advances to a clamp instead of repeatedly requesting ineffective packing")
	check(v.server_apply_treatment(&"surgical_clamp", Vitals.NECK) and v.bleed_rate() == 0.0, "a clamp stops the remaining massive neck bleed")
	v.server_reset_health()
	_wound(v, Vitals.ABDOMEN, "internal", 1.5, &"aorta")
	check(v.care_needed().map(func(t: Dictionary) -> StringName: return t.item) == [&"surgical_clamp"], "internal bleeding: only a surgery kit's clamp")
	check(v.treatment_problem(&"pressure_bandage", Vitals.ABDOMEN) != "" and v.treatment_problem(&"hemostatic_gauze", Vitals.ABDOMEN) != "", "and neither a bandage nor gauze helps")
	v.queue_free()


func _test_chest_seal() -> void:
	print("Vented chest seal")
	var v := _vitals()
	var w := _wound(v, Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
	w.tension_in = 60.0  # this one would go to tension
	check(v.care_needed()[0].item == &"chest_seal", "an open chest wound asks for a seal")
	check(v.server_apply_treatment(&"chest_seal", Vitals.CHEST), "the seal goes on")
	v.server_advance(400.0)
	check(not v.in_cardiac_arrest() and not v.wound_list()[0].tension, "sealed in time: no tension pneumothorax")
	var late := _vitals()
	var w2 := _wound(late, Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_r")
	w2.tension_in = 1.0
	late.server_advance(2.0)
	check(late.wound_list()[0].tension, "an unsealed one went to tension")
	check(late.server_apply_treatment(&"chest_seal", Vitals.CHEST) and late.care_needed().map(func(t: Dictionary) -> StringName: return t.item) == [&"decompression_needle"],
		"a seal still closes it; the needle is what's left (%s)" % [late.care_needed()])
	check(late.has_tension() and late.signs().has("Trachea shifted, neck veins bulging") and late.signs().has("No breath sounds on the right"),
		"a medic sees the tension: trachea shifted, no breath sounds on that side (%s)" % [late.signs()])
	var needled := _vitals()
	var w3 := _wound(needled, Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
	w3.tension_in = 1.0
	needled.server_advance(2.0)
	var squeezed: float = needled.lung(&"lung_r").efficiency
	check(squeezed <= 1.0 - WoundModel.TENSION_SHIFT + 0.001 and needled.lung(&"lung_l").collapse == 1.0,
		"tension: that lung fully collapsed, the other pushed (%.2f)" % squeezed)
	check(needled.treatment_problem(&"decompression_needle", Vitals.CHEST) == "" and needled.server_apply_treatment(&"decompression_needle", Vitals.CHEST),
		"the needle goes in")
	needled.server_advance(WoundModel.TENSION_ARREST_S + 30.0)
	check(not needled.has_tension() and not needled.in_cardiac_arrest() and needled.lung(&"lung_r").efficiency == 1.0,
		"and lets the air out: no arrest, the other lung free again")
	check(needled.treatment_problem(&"decompression_needle", Vitals.CHEST) == "No tension pneumothorax", "no second needle without tension")
	late.server_advance(WoundModel.TENSION_ARREST_S)
	check(late.in_cardiac_arrest(), "without the needle: cardiac arrest")
	v.queue_free()
	late.queue_free()
	needled.queue_free()


func _test_splint() -> void:
	print("Splint")
	var v := _vitals()
	_wound(v, Vitals.THIGH_L, "fracture", WoundModel.FEMUR_RATE, &"femur_l")
	check(absf(v.speed_mult() - WoundModel.BROKEN_LEG_SPEED) < 0.001 and not v.can_sprint() and v.pain() >= WoundModel.PAIN_FLOOR_LEG, "broken leg: walk only, heavy pain")
	check(v.care_needed()[0].item == &"splint" and v.server_apply_treatment(&"splint", Vitals.THIGH_L), "a splint goes on")
	check(v.speed_mult() == 1.0 and not v.can_sprint(), "splinted: walking and jogging back, still no sprint")
	check(absf(v.pain() - WoundModel.PAIN_FLOOR_SPLINTED_LEG) < 0.001 and v.bleed_rate() == 0.0, "its pain floor eases (%.2f) and the femur stops bleeding" % v.pain())
	v.server_reset_health()
	check(v.can_sprint(), "sprinting again after a full reset (a respawn)")
	_wound(v, Vitals.UPPER_ARM_R, "fracture", 0.0, &"humerus_r")
	var broken := v.sway_mult()
	check(v.reload_mult() > 1.0, "broken arm: slow reloads")
	v.server_apply_treatment(&"splint", Vitals.UPPER_ARM_R)
	check(v.reload_mult() == 1.0 and v.sway_mult() < broken and v.sway_mult() > 1.0, "splinted arm: normal reloads, less sway (%.2f -> %.2f)" % [broken, v.sway_mult()])
	v.queue_free()


## Audit L3-01: pain from a round stopped by armor (impact, no wound) is eased by morphine like
## wound pain, and no dose is asked for (or used up) once there's none left for it to ease.
func _test_impact_pain() -> void:
	print("Impact pain and morphine")
	var m := _model(5)
	m.impact = 0.7  # impact only: no wound, no fracture, no rib
	m.update_state(0.0)
	var asks := func(model: WoundModel) -> bool: return model.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "pain")
	check(m.wounds.is_empty() and asks.call(m), "impact pain alone asks for morphine (pain %.2f)" % m.pain())
	var before := m.pain()
	m.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	_step(m, WoundModel.MORPHINE_ABSORB_S)
	var faded := WoundModel.MORPHINE_ABSORB_S * WoundModel.IMPACT_FADE_PER_S
	check(m.pain() < before - faded - 0.3, "and the dose eases it, beyond its own fading (%.2f -> %.2f)" % [before, m.pain()])
	check(not asks.call(m), "with nothing left to ease, no second dose is asked for (%.2f to ease)" % m.pain_to_ease())
	var low := _model(6)
	low.impact = WoundModel.MORPHINE_FROM_PAIN - 0.1
	low.update_state(0.0)
	check(not asks.call(low), "light impact pain uses no morphine (%.2f)" % low.pain())


func _test_morphine() -> void:
	print("Morphine: a level in the blood")
	var m := _model(3)
	m.pain_wounds = 0.95
	m.update_state(0.0)
	m.npa = true  # out from the pain; keep the airway clear
	var first := m.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "pain")
	check(not first.is_empty() and first[0].item == &"morphine", "high pain asks for morphine")
	check(m.apply_item(WoundModel.MORPHINE, Vitals.TORSO), "a dose goes in")
	_step(m, 15.0)
	check(absf(m.morphine_level - 0.5) < 0.02, "half of it in the blood after 15 s (%.2f)" % m.morphine_level)
	var expected := 0.95 - 15.0 * WoundModel.PAIN_FADE_PER_S - WoundModel.MORPHINE_RELIEF * m.morphine_level
	check(absf(m.pain() - expected) < 0.01, "relief follows the level: pain %.2f" % m.pain())
	_step(m, 15.0)
	check(m.morphine_level > 0.97 and m.morphine_level <= 1.0, "a whole dose in after 30 s (%.2f)" % m.morphine_level)
	expected = 0.95 - 30.0 * WoundModel.PAIN_FADE_PER_S - WoundModel.MORPHINE_RELIEF * m.morphine_level
	check(absf(m.pain() - expected) < 0.01, "0.5 off over 30 s (%.2f)" % m.pain())
	check(m.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "pain"), "still %.2f to ease: a second dose is asked for" % m.pain_to_ease())
	m.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	check(not m.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "pain"), "no third: two doses in the blood is enough (%.2f)" % m.morphine_total())
	_step(m, WoundModel.MORPHINE_ABSORB_S)
	check(absf(m.morphine_relief() - WoundModel.MORPHINE_RELIEF_MAX) < 0.001 and m.morphine_level < WoundModel.MORPHINE_SEDATION_LEVEL and not m.unconscious,
		"two doses: %.1f off pain, not sedated (level %.2f)" % [m.morphine_relief(), m.morphine_level])
	# It wears off: half-life.
	var d := _model()
	d.pain_wounds = 0.6
	d.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	_step(d, WoundModel.MORPHINE_ABSORB_S)
	var peak := d.morphine_level
	_step(d, WoundModel.MORPHINE_HALF_LIFE_S)
	check(absf(d.morphine_level - peak * 0.5) < 0.02, "the level halves in %.0f min (%.2f -> %.2f)" % [WoundModel.MORPHINE_HALF_LIFE_S / 60.0, peak, d.morphine_level])
	check(absf(d.morphine_relief() - WoundModel.MORPHINE_RELIEF * d.morphine_level) < 0.001 and d.morphine_relief() < 0.3, "and the relief with it (%.2f)" % d.morphine_relief())
	_step(d, 6.0 * WoundModel.MORPHINE_HALF_LIFE_S)
	check(d.morphine_level < 0.02, "gone after a couple of hours (%.3f)" % d.morphine_level)
	# Too much sedates; much more slows breathing and can stop the heart.
	var sedated := _model()
	sedated.npa = true
	sedated.pain_wounds = 1.0
	for i in 3:
		sedated.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	_step(sedated, 3.0 * WoundModel.MORPHINE_ABSORB_S)
	check(sedated.unconscious and sedated.unconscious_causes() == [&"morphine"] and sedated.spo2 > WoundModel.SPO2_LABOURED,
		"three doses at once: sedated (%s, level %.2f), breathing still fine" % [sedated.unconscious_causes(), sedated.morphine_level])
	var t := 0.0
	while sedated.unconscious and t < 900.0:
		_step(sedated, 1.0)
		t += 1.0
	check(not sedated.unconscious and sedated.morphine_level < WoundModel.MORPHINE_SEDATION_LEVEL, "he comes round as it wears off (%.0f s later, level %.2f)" % [t, sedated.morphine_level])
	var depressed := _model()
	depressed.npa = true
	depressed.pain_wounds = 1.0
	for i in 5:
		depressed.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	_step(depressed, 5.0 * WoundModel.MORPHINE_ABSORB_S + 20.0)
	check(depressed.spo2 < WoundModel.SPO2_BLUE_LIPS and depressed.unconscious_causes().has(&"spo2") and depressed.unconscious_causes().has(&"morphine"),
		"five doses: breathing slows, SpO2 %.0f%% (%s)" % [depressed.spo2, depressed.unconscious_causes()])
	var lethal := _model()
	lethal.npa = true
	lethal.pain_wounds = 1.0
	for i in 7:
		lethal.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	t = 0.0
	while not lethal.arrest and t < 900.0:
		_step(lethal, 1.0)
		t += 1.0
	check(lethal.arrest, "seven: SpO2 stays under 70%% until the heart stops (%.0f s)" % t)
	# A cracked rib: morphine is its fix.
	var rib := _model(4)
	rib.add_impact(Vitals.CHEST, Vitals.PISTOL, 5.0, -1.0)
	while not rib.has_kind("rib"):
		rib.reset()
		rib.add_impact(Vitals.CHEST, Vitals.PISTOL, 5.0, -1.0)
	rib.impact = 0.0
	check(absf(rib.pain() - WoundModel.PAIN_FLOOR_RIB) < 0.001 and rib.care_tasks().any(func(task: Dictionary) -> bool: return task.item == &"morphine"), "a cracked rib's pain asks for morphine")
	rib.apply_item(WoundModel.MORPHINE, Vitals.TORSO)
	check(rib.pain() < 0.001 and rib.stamina_mult() < 1.0, "morphine is its fix (pain %.2f; still short of breath)" % rib.pain())


func _test_airway() -> void:
	print("NPA and airway obstruction")
	var m := _model(5)
	m.care_rng.seed = 5
	m.blood = 0.58  # unconscious
	m.update_state(0.0)
	check(m.unconscious and m.care_tasks().any(func(t: Dictionary) -> bool: return t.item == &"npa" and t.part == &"head"), "an unconscious casualty needs an NPA")
	var t := 0.0
	while not m.airway_blocked and t < 3600.0:
		m.advance(1.0)
		t += 1.0
	check(m.airway_blocked and not m.arrest, "without one the airway obstructs (after %.0f s)" % t)
	var arrest_in := (m.spo2 - WoundModel.SPO2_ARREST) / WoundModel.SPO2_FALL_PER_S + WoundModel.SPO2_ARREST_S
	_step(m, 30.0)
	check(m.spo2 < WoundModel.SPO2_BLUE_LIPS and m.unconscious_causes().has(&"spo2"), "SpO2 falls (%.0f%%)" % m.spo2)
	_step(m, arrest_in - 32.0)
	check(not m.arrest, "the heart holds out a while")
	_step(m, 3.0)
	check(m.arrest, "then cardiac arrest, %.0f s after the obstruction (%.0f s under 70%%)" % [arrest_in, WoundModel.SPO2_ARREST_S])
	var blocked := 0
	for i in 400:
		var c := _model(i)
		c.care_rng.seed = 1000 + i
		c.blood = 0.58
		c.update_state(0.0)
		for s in 60:
			c.advance(1.0)
		if c.airway_blocked:
			blocked += 1
	check(absf(blocked / 400.0 - WoundModel.AIRWAY_BLOCK_PER_MIN) < 0.04, "%.0f%% obstruct within a minute" % (blocked / 4.0))
	var fixed := _model(6)
	fixed.care_rng.seed = 6
	fixed.blood = 0.58
	fixed.update_state(0.0)
	for s in 7200:
		if fixed.airway_blocked:
			break
		fixed.advance(1.0)
	_step(fixed, 20.0)
	var before := fixed.spo2
	check(fixed.apply_item(WoundModel.NPA, &"head") and not fixed.airway_blocked, "an NPA clears an obstructed airway")
	_step(fixed, 60.0)
	check(fixed.spo2 > before and fixed.spo2 > 88.0, "SpO2 recovers (%.0f%% -> %.0f%%)" % [before, fixed.spo2])
	for s in 3600:
		fixed.advance(1.0)
	check(not fixed.arrest and not fixed.airway_blocked and fixed.unconscious, "and with it in, an hour unconscious without obstruction")
	check(not fixed.care_tasks().any(func(task: Dictionary) -> bool: return task.kind == "airway"), "nothing more asked for the airway")
	# Out only briefly (a concussion knockout): once the knockout is over, the obstruction
	# alone doesn't keep them down; they clear it themselves and come round.
	var brief := _model(7)
	brief.knockout_left = 40.0  # the longest (a second concussion in the same fight)
	brief.update_state(0.0)
	_step(brief, 1.0)
	brief.airway_blocked = true
	_step(brief, 38.0)
	check(brief.unconscious and brief.airway_blocked and brief.spo2 < WoundModel.SPO2_UNCONSCIOUS,
		"obstructed early in a knockout, SpO2 falls under %.0f%% (%.0f%%)" % [WoundModel.SPO2_UNCONSCIOUS, brief.spo2])
	_step(brief, 3.0)
	check(brief.unconscious and not brief.airway_blocked and brief.unconscious_causes() == [&"spo2"],
		"once the knockout is over the obstruction clears itself (%s, SpO2 %.0f%%)" % [brief.unconscious_causes(), brief.spo2])
	var woke_at := -1.0
	for s in 120:
		_step(brief, 1.0)
		if not brief.unconscious:
			woke_at = 2.0 + s
			break
	check(woke_at > 0.0 and not brief.npa and not brief.arrest,
		"and they come round without an NPA (%.0f s after the knockout)" % woke_at)
	var long_out := _model(8)
	long_out.pain_wounds = 0.98  # over the threshold the whole time, fading included
	long_out.update_state(0.0)
	_step(long_out, 20.0)
	long_out.airway_blocked = true
	_step(long_out, 30.0)  # out 50 s, SpO2 under the line
	long_out.pain_wounds = 0.0  # the pain has gone; only the obstruction is left
	_step(long_out, 30.0)
	check(long_out.unconscious and long_out.airway_blocked and long_out.unconscious_causes() == [&"spo2"],
		"out longer than %.0f s, the obstruction stays until an NPA (%s)" % [WoundModel.AIRWAY_SELF_CLEAR_S, long_out.unconscious_causes()])
	var awake := _model()
	check(awake.treatment_problem(WoundModel.NPA, &"head") != "", "no NPA for someone awake")


## Bone sim care (Vitals level): the pelvic binder item, open breaks' two tasks, the medical
## menu's wording and markers, the plan of care order and the replicated list.
func _test_bone_care() -> void:
	print("Bone sim care: pelvic binder, open breaks")
	check(ItemDB.has_item(&"pelvic_binder") and ItemDB.get_item(&"pelvic_binder").stats.has("treat_s") and MedicalMenu.medical_ids().has(&"pelvic_binder"), "the pelvic binder is a medical item")
	var splint := ItemDB.get_item(&"splint")
	var binder := ItemDB.get_item(&"pelvic_binder")
	check(is_equal_approx(binder.volume_l, splint.volume_l) and is_equal_approx(binder.mass_kg, splint.mass_kg), "about a splint's size and weight")
	var roles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/roles.json"))
	var medic_kit: Array = roles.roles.medic.kit if roles.has("roles") else roles.medic.kit
	check(medic_kit.any(func(e: Array) -> bool: return e[0] == "pelvic_binder"), "the medic's kit carries one")
	var v := _vitals()
	var w := v._model._add_fracture(Vitals.PELVIS, BodyMap.PELVIS_BONE)
	v._model.update_state(0.0)
	v._after_change(true)
	var tasks := v.care_needed()
	check(tasks[0].kind == "pelvis" and tasks[0].item == &"pelvic_binder" and Vitals.TREATS["pelvis"] == &"pelvic_binder", "care_needed: the binder first")
	check(not v.can_stand() and v.treatment_problem(&"pelvic_binder", Vitals.PELVIS) == "" and v.treatment_problem(&"splint", Vitals.PELVIS) != "", "item checks: a binder for a pelvis, a splint no")
	var listed: Dictionary = v.wound_list().filter(func(e: Dictionary) -> bool: return e.name == &"pelvis")[0]
	check(InteractionMenu._kind_text(listed) == "broken pelvis" and MedicalMenu.hud_parts(v).has(Vitals.PELVIS), "the injury list and the HUD silhouette show it")
	var ranked := SquadAI.plan_care([{"part": Vitals.SHIN_L, "kind": "fracture", "item": &"splint"}, {"part": Vitals.PELVIS, "kind": "pelvis", "item": &"pelvic_binder"},
		{"part": Vitals.THIGH_L, "kind": "venous", "item": &"pressure_bandage"}], false, true)
	check(ranked.map(func(t: Dictionary) -> String: return t.kind) == ["pelvis", "venous", "fracture"], "AI plan_care: binder before bandages, then splints")
	check(v.server_apply_treatment(&"pelvic_binder", Vitals.PELVIS) and w.treated, "the binder goes on through Vitals")
	var bound := MedicalMenu.part_state(v, Vitals.PELVIS)
	var listed2: Dictionary = v.wound_list().filter(func(e: Dictionary) -> bool: return e.name == &"pelvis")[0]
	check(bound.markers.has(MedicalMenu.BINDER) and InteractionMenu._wound_status(listed2).contains("binder on"), "the diagram marks the binder (%s)" % InteractionMenu._wound_status(listed2))
	v.queue_free()
	# An open break: two tasks, two statuses.
	var o := _vitals()
	var fx := o._model._add_fracture(Vitals.THIGH_L, &"femur_l")
	o._model._open_break(fx, "test")
	o._model.update_state(0.0)
	o._after_change(true)
	var kinds := o.care_needed().map(func(t: Dictionary) -> String: return "%s:%s" % [t.kind, t.item])
	check(kinds.has("venous:pressure_bandage") and kinds.has("fracture:splint"), "an open break asks for a bandage and a splint (%s)" % [kinds])
	var femur: Dictionary = o.wound_list().filter(func(e: Dictionary) -> bool: return e.kind == "fracture")[0]
	check(femur.open and not femur.bandaged and InteractionMenu._kind_text(femur) == "open broken bone" and InteractionMenu._wound_status(femur).contains("needs a bandage"), "the list says open and needing a bandage")
	check(o.server_apply_treatment(&"hemostatic_gauze", Vitals.THIGH_L), "gauze goes on the open wound")
	femur = o.wound_list().filter(func(e: Dictionary) -> bool: return e.kind == "fracture")[0]
	check(femur.bandaged and not femur.treated and o.care_needed().any(func(t: Dictionary) -> bool: return t.kind == "fracture"), "dressed, but the splint is still asked for")
	var net := _vitals()
	net._model.apply_net(o._model.to_net())
	check(net.wound_list().any(func(e: Dictionary) -> bool: return e.kind == "fracture" and e.open and e.bandaged), "replicated: open and bandaged")
	o.queue_free()
	net.queue_free()


func _test_care_order() -> void:
	print("care_needed order")
	var v := _vitals()
	_wound(v, Vitals.SHIN_R, "graze", 0.03)
	_wound(v, Vitals.FOREARM_L, "muscle", 0.25)
	_wound(v, Vitals.SHIN_L, "fracture", 0.0, &"tibia_l")
	_wound(v, Vitals.ABDOMEN, "internal", 0.8, &"renal_l")
	_wound(v, Vitals.THIGH_R, "venous", 0.4, &"femoral_vein_r")
	_wound(v, Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
	_wound(v, Vitals.NECK, "junctional", 0.8, &"jugular_l")
	_wound(v, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	v._model.pain_wounds = 0.7
	v._model.blood = 0.58  # unconscious: the airway too
	v._model.update_state(0.0)
	var items := v.care_needed().map(func(t: Dictionary) -> String: return "%s@%s" % [t.item, t.part])
	var expected := ["tourniquet@thigh_l", "surgical_clamp@abdomen", "hemostatic_gauze@neck", "npa@head", "chest_seal@chest", "pressure_bandage@thigh_r",
		"pressure_bandage@forearm_l", "pressure_bandage@shin_r", "io_kit@forearm_l", "hypothermia_blanket@torso", "splint@shin_l", "morphine@torso"]
	check(items == expected, "massive bleeding (internal: a clamp), airway, chest, other bleeding, a line (IO first in shock), a blanket, fractures, pain (%s)" % [items])
	v.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	v.server_apply_treatment(&"npa", Vitals.HEAD)
	items = v.care_needed().map(func(t: Dictionary) -> String: return "%s@%s" % [t.item, t.part])
	check(items.size() == expected.size() - 2 and items[0] == "surgical_clamp@abdomen", "handled ones drop out (%s)" % [items])
	check(v.care_needed().all(func(t: Dictionary) -> bool: return Vitals.CARE_ORDER.has(t.kind) and (Vitals.TREATS[t.kind] == t.item or Vitals.TREATS[t.kind] in t.get("items", [])) or t.kind == "pain"),
		"each task's kind maps to its item in TREATS and CARE_ORDER")
	v.queue_free()


## No revive: treatment takes away what keeps a casualty out and they come round on their own.
func _test_treatment_wakes() -> void:
	print("Treatment wakes a casualty (no revive)")
	# A femoral bleed and heavy pain: out from the pain before 40% lost.
	var treated := _vitals()
	var untreated := _vitals()
	for v: Vitals in [treated, untreated]:
		v._model.npa = true  # the airway is the next check's
		v._model.pain_wounds = 0.8
		_wound(v, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
		while not v.downed:
			v.server_advance(1.0)
	check(treated.downed and treated.why_unconscious() == [&"pain"] and treated.blood_fraction() > 0.6,
		"bleeding out, the pain knocks him out first (%s, %.0f%% lost)" % [treated.why_unconscious(), 100.0 - treated.blood_fraction() * 100.0])
	untreated.server_advance(600.0)
	check(untreated.downed and untreated.why_unconscious().has(&"blood"), "left alone he slides past 40%% lost and stays out (%s)" % [untreated.why_unconscious()])
	treated.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	var blood := treated.blood_fraction()
	treated.server_advance(30.0)
	check(treated.downed and treated.blood_fraction() >= blood and treated.why_unconscious() == [&"pain"],
		"a tourniquet stops the slide (blood only creeps back); the pain still keeps him out (%s)" % [treated.why_unconscious()])
	treated.server_apply_treatment(&"morphine", Vitals.TORSO)
	var t := 0.0
	while treated.downed and t < 120.0:
		treated.server_advance(1.0)
		t += 1.0
	check(treated.is_up() and t <= WoundModel.MORPHINE_ABSORB_S + WoundModel.WAKE_S[&"pain"] + 1.0,
		"morphine eases the pain and he comes round on his own %.0f s later (pain %.2f)" % [t, treated.pain()])
	# An obstructed airway: out from low SpO2 until an NPA goes in.
	var airway := _vitals()
	airway._model.pain_wounds = 0.98  # over the threshold the whole minute, fading included
	airway.server_advance(WoundModel.PAIN_KNOCKOUT_S + 0.1)  # held long enough to knock him out
	airway._model.airway_blocked = true  # it obstructed while the pain kept him out...
	airway.server_advance(60.0)  # ...longer than a brief spell (AIRWAY_SELF_CLEAR_S)
	airway.server_apply_treatment(&"morphine", Vitals.TORSO)
	airway.server_advance(30.0)
	check(airway.downed and airway.why_unconscious() == [&"spo2"] and not airway.in_cardiac_arrest(),
		"morphine took the pain, but the blocked airway keeps him out (%s)" % [airway.why_unconscious()])
	check(airway.signs().has("Blue lips") and airway.signs().has("Unresponsive") and airway.signs().has("Breathing laboured"),
		"what a medic sees: %s" % [airway.signs()])
	airway.server_apply_treatment(&"npa", Vitals.HEAD)
	t = 0.0
	while airway.downed and t < 120.0:
		airway.server_advance(1.0)
		t += 1.0
	check(airway.is_up() and not airway.in_cardiac_arrest() and airway.spo2() >= WoundModel.SPO2_UNCONSCIOUS,
		"an NPA clears it: SpO2 recovers and he comes round %.0f s later" % t)
	for v: Vitals in [treated, untreated, airway]:
		v.queue_free()


## IV and IO access, bags, pressure bags and collapsed veins (design doc, "IV gauge sets the flow").
func _test_iv_fluids() -> void:
	print("IV, IO and fluids")
	var fine := _model()
	fine.blood = 0.9
	check(not fine.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "access"), "10% lost: no line asked for")
	var m := _model()
	m.blood = 0.8
	var access := m.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "access")
	check(access.size() == 1 and access[0].item == &"iv_18" and access[0].part == &"forearm_l" and &"io_kit" in access[0].items,
		"20%% lost: a line, the 18 gauge first, in the left forearm (%s)" % [access])
	check(m.treatment_problem(&"saline_500", &"forearm_l") == "Needs IV or IO access first", "no bag without a line")
	var pain := m.pain()
	check(m.apply_item(&"iv_18", &"forearm_l") and m.access.kind == "iv" and int(m.access.gauge) == 18 and m.care_note == "",
		"an 18 gauge goes in with good veins")
	check(is_equal_approx(m.pain() - pain, 0.05), "and adds a little pain (+%.2f)" % (m.pain() - pain))
	check(m.treatment_problem(&"iv_14", &"forearm_l") == "Already has a line in", "one line at a time")
	var fluids := m.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "fluids")
	check(fluids.size() == 1 and fluids[0].item == &"blood_1000", "then a bag sized to what's missing (%s)" % [fluids])
	m.apply_item(&"saline_500", &"forearm_l")
	check(m.treatment_problem(&"blood_500", &"forearm_l") == "A bag is already running", "one bag at a time")
	var before := m.blood
	var t := 0.0
	while not m.infusion.is_empty() and t < 900.0:
		_step(m, 1.0)
		t += 1.0
	check(t >= 240.0 and t <= 300.0 and absf((m.blood - before) * WoundModel.BLOOD_L * 1000.0 - 500.0) < 2.0,
		"500 mL through an 18 gauge in %.1f min (design doc: 4 to 5), all of it into the blood" % (t / 60.0))
	var still := m.blood
	_step(m, 600.0)
	check(m.blood == still, "and nothing more comes back without a bag")
	var big := _model()
	big.blood = 0.7
	big.apply_item(&"iv_14", &"forearm_l")
	big.apply_item(&"blood_1000", &"forearm_l")
	t = 0.0
	while not big.infusion.is_empty() and t < 900.0:
		_step(big, 1.0)
		t += 1.0
	check(t > 140.0 and t < 160.0, "a 14 gauge runs 1000 mL in %.1f min (3x the 18 gauge)" % (t / 60.0))
	var full := _model()
	full.blood = 0.95
	full.apply_item(&"io_kit", WoundModel.IO_PART)
	full.apply_item(&"saline_1000", WoundModel.IO_PART)
	_step(full, 600.0)
	check(full.blood == 1.0, "blood never goes past full")
	var shock := _model()
	shock.blood = 0.6
	check(shock.veins_collapsed() and shock.care_tasks().any(func(t2: Dictionary) -> bool: return t2.kind == "access" and t2.item == &"io_kit"),
		"40% lost: veins collapsed, IO is the first pick")
	shock.apply_item(&"iv_16", &"forearm_l")
	while shock.access.is_empty():  # a miss now and then; keep trying
		shock.apply_item(&"iv_16", &"forearm_l")
	shock.apply_item(&"saline_500", &"forearm_l")
	check(is_equal_approx(shock.flow_mult(), 1.0), "collapsed veins halve a 16 gauge (%.2fx the 18 gauge rate)" % shock.flow_mult())
	check(shock.care_tasks().any(func(t2: Dictionary) -> bool: return t2.kind == "pressure"), "and ask for a pressure bag")
	shock.apply_item(WoundModel.PRESSURE_BAG, &"forearm_l")
	check(is_equal_approx(shock.flow_mult(), 2.5) and not shock.care_tasks().any(func(t2: Dictionary) -> bool: return t2.kind == "pressure"),
		"which brings it to 1.25x its gauge (%.2fx)" % shock.flow_mult())
	var io := _model()
	io.apply_item(&"io_kit", WoundModel.IO_PART)
	check(io.access.part == WoundModel.IO_PART and is_equal_approx(io.flow_mult(), 1.0), "IO flows like an 18 gauge")
	io.apply_item(WoundModel.PRESSURE_BAG, WoundModel.IO_PART)
	check(is_equal_approx(io.flow_mult(), 2.0), "and like a 16 gauge under a pressure bag")
	var missed := 0
	var noted := true
	for i in 400:
		var c := _model(100 + i)
		c.blood = 0.5
		c.apply_item(&"iv_18", &"forearm_l")
		if c.access.is_empty():
			missed += 1
			noted = noted and c.care_note == "Missed the vein"
	check(noted, "a missed IV says so (and still uses the catheter: apply_item returns true)")
	var arrest := _model()
	arrest.blood = 0.5
	check(absf(missed / 400.0 - WoundModel.IV_FAIL_MAX) < 0.07 and is_equal_approx(arrest.treat_time_mult(&"iv_18"), WoundModel.IV_SHOCK_TIME_MULT)
		and arrest.treat_time_mult(&"io_kit") == 1.0,
		"at 50%% lost an IV misses %.0f%% of the time and takes twice as long; IO always goes in" % (missed / 4.0))
	var tq := _model()
	tq.blood = 0.8
	tq.tourniquets[&"upper_arm_l"] = {"count": 1, "rushed": 0}
	check(tq.iv_part() == &"forearm_r", "a tourniquet on the left arm: the IV goes in the right")
	check(tq.treatment_problem(&"iv_18", &"forearm_l") != "" and not tq.apply_item(&"iv_18", &"forearm_l") and tq.access.is_empty(),
		"an IV asked for below that tourniquet is refused (\"%s\")" % tq.treatment_problem(&"iv_18", &"forearm_l"))
	# Audit A2-03: a tourniquet on every limb leaves no IV site: no IV goes in anywhere, the
	# care plan offers only an IO, and the IO still goes in.
	for limb: StringName in [&"upper_arm_r", &"thigh_l", &"thigh_r"]:
		tq.tourniquets[limb] = {"count": 1, "rushed": 0}
	var plan := tq.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "access")
	check(tq.iv_part() == &"" and plan.size() == 1 and plan[0].items.size() == 1 and plan[0].items[0] == WoundModel.IO_KIT and plan[0].part == WoundModel.IO_PART,
		"every limb under a tourniquet: the plan offers only an IO, in the sternum (%s)" % [plan])
	var refused := true
	for site: StringName in WoundModel.IV_SITES + [&"torso"]:
		refused = refused and tq.treatment_problem(&"iv_18", site) != "" and not tq.apply_item(&"iv_18", site)
	check(refused and tq.access.is_empty(), "and no IV goes in anywhere (%s)" % [tq.access])
	check(tq.apply_item(WoundModel.IO_KIT, WoundModel.IO_PART) and tq.access.kind == "io", "the IO does")
	var copy := _model()
	copy.apply_net(shock.to_net())
	check(copy.access == shock.access and int(copy.infusion.ml) == 500 and copy.infusion.item == &"saline_500",
		"the line and the bag replicate (%s, %s)" % [copy.access, copy.infusion])


## Heart rate, epinephrine, atropine and adenosine, and restarting a heart with CPR and the
## defibrillator (design doc "Drugs", "Defibrillator", "Cardiac arrest").
func _test_heart() -> void:
	print("Heart rate, drugs, CPR and defib")
	var calm := _model()
	_step(calm, 30.0)
	check(is_equal_approx(calm.heart_rate, WoundModel.HR_REST), "healthy: %.0f bpm" % calm.heart_rate)
	var bled := _model()
	bled.blood = 0.72
	_step(bled, 60.0)
	check(bled.heart_rate > 100.0, "blood loss speeds it up (%.0f bpm at 28%% lost)" % bled.heart_rate)
	var epi := _model()
	for i in 3:
		epi.apply_item(WoundModel.EPINEPHRINE, &"torso")
	_step(epi, 30.0)
	var racing := epi.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "racing")
	check(epi.heart_rate > WoundModel.HR_RACING and racing.size() == 1 and racing[0].item == WoundModel.ADENOSINE,
		"too much epinephrine: racing (%.0f bpm), adenosine asked for" % epi.heart_rate)
	epi.apply_item(WoundModel.ADENOSINE, &"torso")
	_step(epi, 20.0)
	check(epi.heart_rate < WoundModel.HR_RACING and not epi.arrest, "adenosine slows it (%.0f bpm)" % epi.heart_rate)
	var opiate := _model()
	opiate.npa = true
	opiate.morphine_level = 3.2
	_step(opiate, 30.0)
	var slow := opiate.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "slow_heart")
	check(opiate.heart_rate < WoundModel.HR_SLOW and slow.size() == 1 and slow[0].item == WoundModel.ATROPINE,
		"a morphine overdose slows it (%.0f bpm), atropine asked for" % opiate.heart_rate)
	opiate.apply_item(WoundModel.ATROPINE, &"torso")
	_step(opiate, 20.0)
	check(opiate.heart_rate > WoundModel.HR_SLOW, "atropine brings it up (%.0f bpm)" % opiate.heart_rate)
	var overdose := _model()
	for i in 8:
		overdose.apply_item(WoundModel.EPINEPHRINE, &"torso")
	var t := 0.0
	while not overdose.arrest and t < 300.0:
		_step(overdose, 1.0)
		t += 1.0
	check(overdose.arrest, "eight doses: racing past %.0f bpm long enough stops the heart (%.0f s)" % [WoundModel.HR_DEADLY_FAST, t])
	var empty := _model()
	empty.npa = true
	empty.blood = 0.5
	empty.update_state(0.0)
	check(empty.arrest and empty.heart_rate == 0.0 and not empty.care_tasks().any(func(t2: Dictionary) -> bool: return t2.kind in ["cpr", "defib"]),
		"arrest at 50%% lost: no CPR or shock asked for until blood is back")
	check(empty.treatment_problem(WoundModel.CPR, &"chest").begins_with("Get blood back in first")
		and empty.treatment_problem(WoundModel.DEFIBRILLATOR, &"chest").begins_with("Get blood back in first"), "and neither would do anything")
	empty.blood = 0.65
	var kinds: Array = empty.care_tasks().map(func(t2: Dictionary) -> String: return t2.kind)
	check(kinds.has("epinephrine") and kinds.has("defib") and kinds.has("cpr") and kinds.find("epinephrine") < kinds.find("defib"),
		"blood back over 60%%: epinephrine, shocks and CPR (%s)" % [kinds])
	var shocks := 0
	var cycles := 0
	for i in 400:
		var c := _model(500 + i)
		c.npa = true
		c.blood = 0.5
		c.update_state(0.0)
		c.blood = 0.65
		c.apply_item(WoundModel.DEFIBRILLATOR, &"chest")
		if not c.arrest:
			shocks += 1
		var p := _model(1500 + i)
		p.npa = true
		p.blood = 0.5
		p.update_state(0.0)
		p.blood = 0.65
		p.apply_item(WoundModel.CPR, &"chest")
		if not p.arrest:
			cycles += 1
	check(absf(shocks / 400.0 - WoundModel.DEFIB_RESTART_CHANCE) < 0.07 and absf(cycles / 400.0 - WoundModel.CPR_RESTART_CHANCE) < 0.05,
		"a shock restarts it %.0f%% of the time, a CPR cycle %.0f%%" % [shocks / 4.0, cycles / 4.0])
	var boosted := _model()
	boosted.blood = 0.5
	boosted.update_state(0.0)
	boosted.blood = 0.65
	boosted.drug_level[WoundModel.EPINEPHRINE] = 1.0
	check(is_equal_approx(boosted.restart_chance(WoundModel.DEFIBRILLATOR), WoundModel.DEFIB_RESTART_CHANCE + WoundModel.EPI_RESTART_BONUS),
		"epinephrine in the blood helps (%.0f%% a shock)" % (boosted.restart_chance(WoundModel.DEFIBRILLATOR) * 100.0))
	var back := _model(7)
	back.npa = true
	back.blood = 0.5
	back.update_state(0.0)
	back.blood = 0.65
	while back.arrest:
		back.apply_item(WoundModel.DEFIBRILLATOR, &"chest")
	check(back.care_note == "Pulse back" and is_equal_approx(back.heart_rate, WoundModel.HR_RESTART), "the heart beats again (%.0f bpm)" % back.heart_rate)
	_step(back, WoundModel.WAKE_S[&"arrest"] + 5.0)
	check(not back.arrest and not back.unconscious, "and with blood to spare he comes round on his own")
	var knocked := _model()
	knocked.knockout_left = 30.0
	knocked.update_state(0.0)
	check(knocked.care_tasks().any(func(t2: Dictionary) -> bool: return t2.kind == "wake" and t2.item == WoundModel.EPINEPHRINE),
		"knocked out: epinephrine's wake-up roll is offered")
	var woke := 0
	for i in 400:
		var k := _model(3000 + i)
		k.knockout_left = 30.0
		k.update_state(0.0)
		k.apply_item(WoundModel.EPINEPHRINE, &"torso")
		_step(k, WoundModel.EPI_WAKE_S + 0.5)
		if not k.unconscious:
			woke += 1
	check(absf(woke / 400.0 - WoundModel.EPI_WAKE_CHANCE) < 0.07, "the roll wakes %.0f%% of them within seconds" % (woke / 4.0))
	var held := _model(9)
	held.npa = true
	held.blood = 0.55
	held.update_state(0.0)
	for i in 5:
		held.apply_item(WoundModel.EPINEPHRINE, &"torso")
	_step(held, 10.0)
	check(held.unconscious and held.unconscious_causes().has(&"blood") and held.care_note == "", "no revive: epinephrine can't wake someone out from blood loss")
	var copy := _model()
	copy.apply_net(epi.to_net())
	check(absf(copy.heart_rate - epi.heart_rate) < 1.0 and copy.drug_total(WoundModel.EPINEPHRINE) > 0.0 and copy.drug_total(WoundModel.ADENOSINE) > 0.0,
		"heart rate and drugs replicate")


## The surgery kit and the other damage: blasts, falls, burns, hypothermia and deafness
## (design doc "Surgery kit", "Other damage").
func _test_surgery_and_damage() -> void:
	print("Surgery kit and other damage")
	var inside := _model()
	var renal := inside._add_wound(Vitals.ABDOMEN, "internal", 0.8, &"renal_l")
	inside.update_state(0.0)
	var tasks := inside.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "internal")
	check(tasks.size() == 1 and tasks[0].item == WoundModel.SURGICAL_CLAMP, "internal bleeding asks for a surgery kit's clamp")
	check(inside.apply_item(WoundModel.SURGICAL_CLAMP, Vitals.ABDOMEN) and renal.treated and renal.clamped and inside.wound_bleed_rate() == 0.0,
		"and the clamp stops it")
	var neck := _model()
	neck._add_wound(Vitals.NECK, "junctional", 0.8, &"jugular_l")
	var junction := neck.care_tasks()[0]
	check(junction.item == WoundModel.HEMOSTATIC_GAUZE and WoundModel.SURGICAL_CLAMP in junction.items, "a junctional bleed: gauze, or a clamp")
	var chest := _model()
	chest.npa = true
	var open := chest._add_wound(Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
	check(WoundModel.SURGICAL_CLAMP in chest.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "chest")[0].items,
		"a chest wound: a seal, or closing it with the surgery kit")
	chest.apply_item(WoundModel.SURGICAL_CLAMP, Vitals.CHEST)
	check(open.treated and open.closed, "closed by surgery")
	var reopened := 0
	for i in 400:
		var c := _model(4000 + i)
		var w := c._add_wound(Vitals.CHEST, "chest", WoundModel.CHEST_RATE, &"lung_l")
		c.apply_item(WoundModel.SURGICAL_CLAMP, Vitals.CHEST)
		if c.exert() > 0 and not w.treated and not w.closed:
			reopened += 1
	check(absf(reopened / 400.0 - WoundModel.CHEST_REOPEN_CHANCE) < 0.04, "sprinting or jumping reopens it %.0f%% of the time" % (reopened / 4.0))
	var blast := _model()
	blast.add_blast(1.0, WoundModel.BLAST_RADIUS)
	check(blast.deaf_left > 40.0 and blast.burn > 0.0 and blast.impact > 0.0,
		"a blast 1 m away: ears ringing %.0f s, burns over %.0f%%, bruising" % [blast.deaf_left, blast.burn * 100.0])
	var muffled := _model()
	muffled.add_blast(1.0, WoundModel.BLAST_RADIUS, true)
	check(is_equal_approx(muffled.deaf_left, blast.deaf_left * 0.5), "ear protection halves the deafness")
	var lungs := 0
	for i in 400:
		var b := _model(5000 + i)
		b.add_blast(0.0, WoundModel.BLAST_RADIUS)
		if b.blast_lung:
			lungs += 1
	check(absf(lungs / 400.0 - WoundModel.BLAST_LUNG_CHANCE) < 0.06, "blast lung %.0f%% of the time at the centre" % (lungs / 4.0))
	var outside := 0
	for i in 200:
		var b := _model(5500 + i)
		b.add_blast(WoundModel.BLAST_LUNG_RADIUS + 0.2, WoundModel.BLAST_RADIUS)
		if b.blast_lung:
			outside += 1
	check(outside == 0, "never past %.0f m outdoors" % WoundModel.BLAST_LUNG_RADIUS)
	var lung := _model()
	lung.npa = true
	lung.blast_lung = true
	_step(lung, 300.0)
	var rested := lung.spo2
	_step(lung, 1800.0)
	check(lung.stamina_mult() < 1.0 and rested < WoundModel.SPO2_NORMAL - 2.0 and absf(lung.spo2 - rested) < 0.5 and lung.spo2 > WoundModel.SPO2_LABOURED - 4.0
		and not lung.unconscious, "blast lung: short of breath (SpO2 %.0f%%), then it holds steady at rest for half an hour" % lung.spo2)
	var pushed := _model(8)
	pushed.npa = true
	pushed.blast_lung = true
	_step(pushed, 300.0)
	for i in 8:
		pushed.exert()
		if pushed.has_tension():  # a lung gave way: the medic needles it at once
			pushed.apply_item(WoundModel.NEEDLE, &"chest")
		_step(pushed, 15.0)
	check(pushed.spo2 < rested - 1.0, "sprinting and heavy loads make it worse (SpO2 %.0f%% against %.0f%% resting)" % [pushed.spo2, rested])
	_step(pushed, WoundModel.BLAST_LUNG_RECOVER_S + 600.0)
	check(absf(pushed.spo2 - rested) < 1.0 and not pushed.dead, "and rest brings it back to the steady level (%.0f%%)" % pushed.spo2)
	var drowned := _model()
	drowned.npa = true
	drowned.blast_lung = true
	drowned.blood = 0.98  # a little lost: the bag goes up, then runs on past full
	drowned.apply_item(WoundModel.IO_KIT, WoundModel.IO_PART)
	drowned.apply_item(&"saline_1000", WoundModel.IO_PART)
	_step(drowned, 600.0)
	check(drowned.blast_strain > 0.1 and drowned.spo2 < rested - 1.0, "fluid the body doesn't need goes into the lungs (SpO2 %.0f%%)" % drowned.spo2)
	var collapsed := 0
	for i in 400:
		var c := _model(9000 + i)
		c.blast_lung = true
		if c.exert() > 0 and c.has_tension():
			collapsed += 1
	check(absf(collapsed / 400.0 - WoundModel.BLAST_PNEUMO_CHANCE) < 0.03, "exertion collapses a lung %.1f%% of the time" % (collapsed / 4.0))
	var popped := _model()
	popped.blast_lung = true
	popped.care_rng.seed = 1
	while popped.exert() == 0:
		pass
	check(popped.has_tension() and popped.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "tension")
		and not popped.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "chest"), "a closed tension pneumothorax: the needle, nothing to seal")
	popped.apply_item(WoundModel.NEEDLE, &"chest")
	_step(popped, WoundModel.TENSION_ARREST_S + 30.0)
	check(not popped.has_tension() and not popped.arrest, "and the needle fixes it")
	var low := _model()
	low.add_fall(2.5)
	check(low.wounds.is_empty() and low.pain() == 0.0, "a fall under 3 m: nothing")
	var broken := 0
	var killed := 0
	for i in 400:
		var f := _model(6000 + i)
		f.add_fall(5.0)
		if f.has_fracture(BodyMap.LEG_BONES, false):
			broken += 1
		var h := _model(7000 + i)
		h.add_fall(12.0)
		if h.dead:
			killed += 1
	check(broken > 180 and broken < 280, "5 m: leg pain and a broken leg %.0f%% of the time" % (broken / 4.0))
	check(killed > 330, "12 m: fatal %.0f%% of the time" % (killed / 4.0))
	var burned := _model()
	burned.add_burn(0.4)
	_step(burned, 60.0)
	var dressings := burned.care_tasks().filter(func(t: Dictionary) -> bool: return t.kind == "burn")
	check(burned.lost() > 0.01 and dressings.size() == 1 and burned.burn_dressings_needed() == 4,
		"burns over 40%%: fluid loss (%.1f%% in a minute) and four burn dressings asked for" % (burned.lost() * 100.0))
	var hurt := burned.burn_pain()
	burned.apply_item(WoundModel.BURN_DRESSING, &"torso")
	check(burned.burn_pain() < hurt and burned.burn_dressings_needed() == 3, "a dressing takes off some pain")
	var cold := _model()
	cold.blood = 0.65
	cold._add_wound(Vitals.THIGH_L, "muscle", 0.25)
	var warm_rate := cold.bleed_rate()
	cold.still_s = WoundModel.HYPOTHERMIA_STILL_S + 1.0
	check(cold.hypothermic() and is_equal_approx(cold.bleed_rate(), warm_rate * WoundModel.HYPOTHERMIA_BLEED)
		and cold.care_tasks().any(func(t: Dictionary) -> bool: return t.kind == "hypothermia"),
		"35%% lost and lying still 5 min: hypothermic, bleeding faster, a blanket asked for")
	cold.apply_item(WoundModel.BLANKET, &"torso")
	check(not cold.hypothermic() and is_equal_approx(cold.bleed_rate(), warm_rate), "the blanket stops it")
	var loud := _model()
	for i in 9:
		loud.add_noise(1.0)
	check(loud.deaf_left == 0.0, "a few shots indoors: fine")
	loud.add_noise(1.0)
	check(is_equal_approx(loud.deaf_left, WoundModel.NOISE_DEAF_S), "sustained indoor fire: muffled for %.0f s" % loud.deaf_left)
	var guarded := _model()
	for i in 20:
		guarded.add_noise(1.0, true)
	guarded.deafen(5.0, true)
	check(guarded.deaf_left == 0.0, "ear protection: no deafness from gunfire or a flashbang")
	var copy := _model()
	burned.blanket = true
	copy.apply_net(burned.to_net())
	var clamped := _model()
	clamped.apply_net(inside.to_net())
	check(is_equal_approx(copy.burn, burned.burn) and copy.burn_dressings == 1 and copy.blanket and clamped.wounds[0].clamped,
		"burns, dressings, the blanket and clamps replicate")


func _test_kits() -> void:
	print("Kits are bags of items")
	var ifak := ItemDB.get_item(&"ifak")
	var trauma := ItemDB.get_item(&"trauma_kit")
	check(Inventory.kit_text(ifak, {}) == "TQ 1, Bandage 2, Gauze 1, Seal 1", "an IFAK: %s" % Inventory.kit_text(ifak, {}))
	check(Inventory.kit_text(trauma, {}) == "TQ 2, Bandage 4, Gauze 2, Seal 2, Splint 1, Morphine 2, NPA 1", "a trauma kit: %s" % Inventory.kit_text(trauma, {}))
	var inv := Inventory.new()
	add_child(inv)
	inv.take(&"assault_pack")
	inv.take(&"ifak", 2)
	inv.take(&"trauma_kit")
	inv.take(&"pressure_bandage")
	check(inv.medical_count(&"pressure_bandage") == 1 + 2 * 2 + 4, "bandages carried: loose and in kits (%d)" % inv.medical_count(&"pressure_bandage"))
	check(inv.take_medical(&"pressure_bandage") and inv.count_of(&"pressure_bandage") == 0 and _states(inv, &"ifak") == [{}, {}] and _states(inv, &"trauma_kit") == [{}],
		"the loose one first, kits untouched")
	inv.take_medical(&"pressure_bandage")
	var opened := _states(inv, &"ifak")
	check(inv.count_of(&"ifak") == 2 and opened.size() == 2 and opened.any(func(s: Dictionary) -> bool: return int(s.get("contents", {}).get("pressure_bandage", -1)) == 1),
		"then one out of an IFAK (the smaller kit), which keeps its own entry (%s)" % [opened])
	inv.take_medical(&"pressure_bandage")
	inv.take_medical(&"pressure_bandage")
	opened = _states(inv, &"ifak")
	check(opened.filter(func(s: Dictionary) -> bool: return s.has("contents")).size() == 2, "the opened IFAK first, then the other (%s)" % [opened])
	for id: StringName in [&"tourniquet", &"tourniquet", &"hemostatic_gauze", &"hemostatic_gauze", &"chest_seal", &"chest_seal", &"pressure_bandage"]:
		inv.take_medical(id)
	check(inv.count_of(&"ifak") == 0 and inv.count_of(&"trauma_kit") == 1, "emptied IFAKs are thrown away")
	check(inv.medical_count(&"pressure_bandage") == 4 and inv.medical_count(&"splint") == 1, "the trauma kit is still full")
	check(InventoryScreen._detail(trauma, _states(inv, &"trauma_kit")[0]).contains("Bandage 4"), "the inventory screen shows what's in it (%s)" % InventoryScreen._detail(trauma, _states(inv, &"trauma_kit")[0]))
	inv.take_medical(&"morphine")
	check(inv.medical_count(&"morphine") == 1 and inv.count_of(&"trauma_kit") == 1, "a morphine out of the trauma kit; the kit stays")
	check(not inv.take_medical(&"flashbang"), "nothing left to take is refused")
	var dropped := inv.strip()
	var other := Inventory.new()
	add_child(other)
	other.take(&"assault_pack")
	for entry in dropped:
		if entry.id == &"trauma_kit":
			other.take(entry.id, entry.count, entry.get("state", {}))
	check(other.medical_count(&"morphine") == 1 and other.medical_count(&"pressure_bandage") == 4, "an opened kit keeps what's left wherever it goes")
	inv.queue_free()
	other.queue_free()


# --- Host requests in a session -----------------------------------------------------------

func _start_session() -> void:
	GameState.zone_id = "test_medical" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	_restock()
	casualty = _spawn_ai("Casualty", SPOT + Vector3(0, 0, -1.5))
	helper = _spawn_ai("Helper", SPOT + Vector3(2.0, 0, 0))
	_place_player()
	await _frames(10)


func _test_times() -> void:
	print("Treatment times, on others and yourself (host requests)")
	_restock()
	# [item, part, kind, rate, seconds on someone else, seconds on yourself]
	var cases: Array = [
		[&"tourniquet", Vitals.THIGH_L, "arterial", 1.2, 4.0, 6.0],
		[&"pressure_bandage", Vitals.FOREARM_L, "muscle", 0.25, 5.0, 5.0],
		[&"hemostatic_gauze", Vitals.NECK, "junctional", 0.8, 8.0, 8.0],
		[&"chest_seal", Vitals.CHEST, "chest", WoundModel.CHEST_RATE, 5.0, 5.0],
		[&"splint", Vitals.SHIN_R, "fracture", 0.0, 8.0, 8.0],
		[&"morphine", Vitals.TORSO, "pain", 0.0, 2.0, 2.0],
	]
	for c: Array in cases:
		for on_self: bool in [false, true]:
			var target: Soldier = player if on_self else casualty
			_reset(target)
			if c[2] == "pain":
				target.vitals._model.pain_wounds = 0.6
			else:
				_wound(target.vitals, c[1], c[2], c[3])
			if player.inventory.medical_count(c[0]) == 0:
				player.inventory.take(c[0])
			var seconds := await _start_and_interrupt(target, c[0], c[1], false)
			check(absf(seconds - float(c[5] if on_self else c[4])) < 0.05, "%s on %s: %.1f s" % [c[0], "yourself" if on_self else "someone else", seconds])
	_reset(casualty)
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2)
	var rushed := await _start_and_interrupt(casualty, &"tourniquet", Vitals.THIGH_L, true)
	check(rushed < 2.0 and absf(rushed - 1.5) < 0.05, "a rushed tourniquet: %.1f s (under 2 s)" % rushed)
	_reset(casualty)
	casualty.vitals.server_damage(500.0)
	player.inventory.take(&"npa")
	await _frames(2)
	var npa := await _start_and_interrupt(casualty, &"npa", Vitals.HEAD, false)
	check(absf(npa - 3.0) < 0.05, "an NPA: %.1f s" % npa)
	check(player.inventory.count_of(&"tourniquet") == 1 and player.inventory.count_of(&"npa") == 1, "interrupted treatments use nothing up")
	_reset(casualty)
	_reset(player)


func _test_completed_treatments() -> void:
	print("Completed treatments")
	_restock()
	player.inventory.take(&"tourniquet")
	player.inventory.take(&"morphine")
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2)
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.THIGH_L)  # rushed left at its default
	await _seconds(4.2)
	check(casualty.vitals.bleed_rate() == 0.0 and player.inventory.medical_count(&"tourniquet") == 0, "a tourniquet on someone else, used up")
	player.vitals._model.pain_wounds = 0.6
	player._server_treat.rpc_id(1, player.get_path(), &"morphine", Vitals.TORSO)
	await _seconds(2.2)
	check(player.vitals._model.morphine_total() > 0.9 and player.inventory.medical_count(&"morphine") == 0, "morphine on yourself, used up")
	_reset(casualty)
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2)
	player.inventory.take(&"tourniquet", 2)
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.THIGH_L, true)
	await _seconds(1.7)
	check(absf(casualty.vitals.bleed_rate() - 1.2 * 0.3 * casualty.vitals.blood_fraction()) < 0.01, "the rushed one lets 30%% through (%.2f L/min)" % casualty.vitals.bleed_rate())
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.THIGH_L, true)
	await _seconds(1.7)
	check(casualty.vitals.bleed_rate() == 0.0, "a second one beside it stops it")
	_reset(casualty)
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2)
	player.inventory.take(&"tourniquet")
	player.vitals.server_impact(Vitals.CHEST, Vitals.PISTOL, 50.0)  # a round on your plate: under fire
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.THIGH_L)
	await _seconds(4.2)
	check(casualty.vitals.bleed_rate() > 0.0 and casualty.vitals.tourniquets()[Vitals.THIGH_L].rushed == 1, "placed under fire: it goes on rushed")
	# Audit A2-03: with a tourniquet on every limb the host places no IV, whatever site is
	# asked for; the IO the care plan offers instead goes in.
	_reset(casualty)
	_reset(player)
	var m: WoundModel = casualty.vitals._model
	m.blood = 0.8
	for limb: StringName in [Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.THIGH_L, Vitals.THIGH_R]:
		m.tourniquets[limb] = {"count": 1, "rushed": 0}
	casualty.vitals._after_change(true)
	player.inventory.take(&"iv_18")
	player.inventory.take(&"io_kit")
	var access := casualty.vitals.care_needed().filter(func(t: Dictionary) -> bool: return t.kind == "access")
	check(access.size() == 1 and access[0].items.size() == 1 and access[0].items[0] == WoundModel.IO_KIT, "every limb under a tourniquet: the care plan asks for an IO only (%s)" % [access])
	for site: StringName in [Vitals.FOREARM_L, &"shin_r", Vitals.TORSO]:
		player._server_busy_until = 0.0
		player._server_treat.rpc_id(1, casualty.get_path(), &"iv_18", site)
		await _frames(2)
		check(casualty.vitals.access().is_empty() and player._server_busy_until <= Soldier._now() and player.inventory.medical_count(&"iv_18") == 1,
			"an IV asked for on the %s is refused at once, nothing used" % site)
	player._server_treat.rpc_id(1, casualty.get_path(), &"io_kit", WoundModel.IO_PART)
	await _seconds(player.treat_seconds(casualty, ItemDB.get_item(&"io_kit")) + 0.3)
	check(casualty.vitals.access().get("kind", "") == "io" and player.inventory.medical_count(&"io_kit") == 0, "the IO goes in (%s)" % [casualty.vitals.access()])
	_reset(casualty)
	_reset(player)


func _test_interruptions() -> void:
	print("Interruptions")
	_open_scratch_log()
	_restock()
	_wound(casualty.vitals, Vitals.FOREARM_L, "muscle", 0.25)
	player.inventory.take(&"pressure_bandage")
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	await _seconds(0.3)
	casualty.global_position += Vector3(1.5, 0, 0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing() and player._server_busy_until <= Soldier._now(), "the casualty moved away: interrupted")
	var shoved := _care_lines("interrupted: ")
	check(shoved.size() == 1 and shoved[0].contains("%s treats %s: pressure_bandage on" % [player.log_name(), casualty.log_name()])
		and shoved[0].contains("interrupted: they were moved: nobody carried them (1.5 m, "),
		"  the log says nobody carried them, how far they went and how they are (%s)" % [shoved])
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	await _seconds(0.3)
	player.vitals.server_damage(500.0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing() and casualty.vitals.wound_list()[0].bleeding, "the treater went down: interrupted")
	check(_care_lines("interrupted: you went down").size() == 1, "  the log says so")
	player.vitals.server_reset_health()
	casualty.vitals.server_damage(500.0)  # down, so it can be carried
	await _frames(2)
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	await _seconds(0.3)
	check(casualty.vitals.is_healing(), "treating a downed casualty")
	helper.server_pick_up_body(casualty, Soldier.DRAG, 4.0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing() and player.inventory.count_of(&"pressure_bandage") == 1, "someone drags them off: interrupted, the bandage kept (%s, healing %s, carried by %s)"
		% [casualty.vitals.wound_list(), casualty.vitals.is_healing(), casualty.carried_by])
	var dragged := _care_lines("interrupted: they were moved: dragged by ")
	check(dragged.size() == 1 and dragged[0].contains("dragged by %s (" % helper.log_name()), "  the log says who dragged them (%s)" % [dragged])
	helper.release_carried()
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	casualty.global_position = SPOT + Vector3(0, 0, -8.0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing(), "out of reach: interrupted")
	casualty.global_position = SPOT + Vector3(0, 0, -6.0)
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	check(not casualty.vitals.is_healing(), "too far to start")
	var refused := _care_lines("refused: Too far away")
	var at := RegEx.create_from_string(" at ([0-9.]+) m,").search(refused[-1] if not refused.is_empty() else "")
	check(at != null and at.get_string(1).to_float() > Soldier.TREAT_REACH, "  the log says how far they were (%s)" % [refused])
	check(_care_lines("started (").size() == 4 and _care_lines("interrupted: ").size() == 4, "  each start and each interruption has its line (%s)" % [_care_lines("")])
	SessionLog.finish()
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	_reset(casualty)
	_reset(player)
	player.inventory.remove_one(&"pressure_bandage")


## B-09 (co-op soak S0578: "iv_18 on forearm_l" twice, "tourniquet on upper_arm_l" twice):
## a treatment goes on once. The same request sent twice (a resent or doubled RPC) is turned
## away while the first runs; a second treater (an AI medic beside a player) can't start the
## same thing on the same casualty meanwhile (the same item on that part, or a second line or
## bag); and a missed IV says so in the log, so a retry doesn't read as a second line put in.
func _test_one_treater_per_site() -> void:
	print("One treater per site (B-09)")
	_open_scratch_log()
	_restock()
	_reset(casualty)
	_reset(helper)
	var helper_was := helper.global_position
	helper.global_position = casualty.global_position + Vector3(-0.8, 0, 0)
	_wound(casualty.vitals, Vitals.FOREARM_L, "muscle", 0.25)
	player.inventory.take(&"pressure_bandage", 2)
	if helper.inventory.count_of(&"assault_pack") == 0 and helper.inventory.slots.get(&"backpack", &"") == &"":
		helper.inventory.take(&"assault_pack")
	helper.inventory.take(&"pressure_bandage")
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)  # the same request again
	helper._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	check(casualty.vitals.is_healing() and helper._server_busy_until <= Soldier._now(), "a second treater can't start the same bandage on the same wound")
	check(_care_lines("refused: Someone is already doing that").size() == 1, "  the log says why (%s)" % [_care_lines("refused")])
	await _seconds(5.3)
	var w: Dictionary = casualty.vitals.wound_list()[0]
	check(w.treated and not w.bleeding and player.inventory.medical_count(&"pressure_bandage") == 1 and helper.inventory.medical_count(&"pressure_bandage") == 1,
		"bandaged once: one bandage used, the doubled request and the second treater's used nothing (player %d, helper %d left)"
		% [player.inventory.medical_count(&"pressure_bandage"), helper.inventory.medical_count(&"pressure_bandage")])
	check(_care_lines("pressure_bandage on left forearm").filter(func(l: String) -> bool: return l.ends_with(", done")).size() == 1, "  one \"done\" line for it")
	# One line at a time: a second IV, even on the other arm, waits until the first is in.
	_reset(casualty)
	casualty.vitals._model.blood = 0.8
	casualty.vitals._after_change(true)
	player.inventory.take(&"iv_18")
	helper.inventory.take(&"iv_18")
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"iv_18", Vitals.FOREARM_L)
	helper._server_treat.rpc_id(1, casualty.get_path(), &"iv_18", Vitals.FOREARM_R)
	check(casualty.vitals.is_healing() and helper._server_busy_until <= Soldier._now() and helper.inventory.medical_count(&"iv_18") == 1,
		"a second IV while the first is going in is turned away, nothing used")
	await _seconds(player.treat_seconds(casualty, ItemDB.get_item(&"iv_18")) + 0.3)
	var lines := _care_lines("iv_18 on left forearm")
	var missed := casualty.vitals.access().is_empty()
	check(player.inventory.medical_count(&"iv_18") == 0 and not lines.is_empty()
		and lines[-1].ends_with("done: Missed the vein" if missed else ", done"),
		"the IV's line in the log says how it went (%s: %s)" % ["missed" if missed else "in", lines[-1] if not lines.is_empty() else "none"])
	# Once the first treater is done, the site is free again.
	helper._server_treat.rpc_id(1, casualty.get_path(), &"iv_18", Vitals.FOREARM_R)
	check(helper._server_busy_until > Soldier._now() if missed else helper._server_busy_until <= Soldier._now(),
		"after it: another IV starts only if the first missed (%s)" % ("missed" if missed else "in"))
	await _seconds(player.treat_seconds(casualty, ItemDB.get_item(&"iv_18")) + 0.3)
	SessionLog.finish()
	helper.global_position = helper_was
	_reset(casualty)
	_reset(helper)
	_reset(player)
	_restock()


## B-09 follow-up (co-op soak S0697: "npa on head (their kit)" 42 times, the casualty still
## Unconscious; S0578: two iv_18, two tourniquets): a treatment that goes on is kept, reaches
## every peer's copy (the state a client's care plan reads), and the plan moves on; asking for
## it again is refused with nothing used. (In S0697 every one of those requests was refused
## "Too far away": both bodies had fallen out of the world, 6 km below; none went on.)
func _test_care_plan_moves_on() -> void:
	print("A treatment goes on once and the care plan moves on (B-09)")
	_open_scratch_log()
	_restock()
	_reset(casualty)
	casualty.vitals._model.blood = 0.58  # unconscious from blood loss, heart still going: the plan asks for an airway
	casualty.vitals._model.update_state(0.0)
	casualty.vitals._after_change(true)
	await _frames(2)
	var asks_npa := func(v: Vitals) -> bool: return v.care_needed().any(func(t: Dictionary) -> bool: return t.item == &"npa")
	check(casualty.vitals.is_unconscious() and asks_npa.call(casualty.vitals), "unconscious: the plan asks for an NPA")
	player.inventory.take(&"npa", 2)
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"npa", Vitals.HEAD)
	await _seconds(player.treat_seconds(casualty, ItemDB.get_item(&"npa")) + 0.3)
	check(casualty.vitals.has_npa() and not asks_npa.call(casualty.vitals) and player.inventory.medical_count(&"npa") == 1,
		"one NPA goes in, stays in, and the plan moves on (%s)" % [casualty.vitals.care_needed().map(func(t: Dictionary) -> StringName: return t.item)])
	# What a client's copy reads (net_state, the replicated wound-model state): the NPA is in there too.
	var copy := WoundModel.new()
	copy.apply_net(casualty.vitals._model.to_net())
	check(copy.npa and not copy.care_tasks().any(func(t: Dictionary) -> bool: return t.item == &"npa"), "a client's copy has the NPA and asks for none")
	player._server_treat.rpc_id(1, casualty.get_path(), &"npa", Vitals.HEAD)
	await _frames(2)
	check(player._server_busy_until <= Soldier._now() and player.inventory.medical_count(&"npa") == 1 and _care_lines("npa on head").any(func(l: String) -> bool: return l.ends_with("refused: Already has an NPA")),
		"asked again: refused at once (Already has an NPA), nothing used")
	# A tourniquet that stops the bleed: the plan doesn't ask for a second, and a second is refused.
	_reset(casualty)
	_wound(casualty.vitals, Vitals.UPPER_ARM_L, "arterial", 1.2)
	player.inventory.take(&"tourniquet", 2)
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.UPPER_ARM_L)
	await _seconds(4.3)
	var asks_tq := func() -> bool: return casualty.vitals.care_needed().any(func(t: Dictionary) -> bool: return t.item == &"tourniquet")
	check(casualty.vitals.bleed_rate() == 0.0 and not asks_tq.call() and int(casualty.vitals.tourniquets()[Vitals.UPPER_ARM_L].count) == 1,
		"a tourniquet stops the arm's bleed: one on, the plan asks for no second")
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.UPPER_ARM_L)
	await _frames(2)
	check(player._server_busy_until <= Soldier._now() and player.inventory.medical_count(&"tourniquet") == 1 and int(casualty.vitals.tourniquets()[Vitals.UPPER_ARM_L].count) == 1,
		"asked again: refused at once (nothing bleeding there), still one on, nothing used")
	SessionLog.finish()
	_reset(casualty)
	_reset(player)
	_restock()


## Opens a session log in this test's own scratch folder under user:// (emptied first; never
## the real logs), so the checks can read the treatment lines: SessionLog is off when headless.
func _open_scratch_log() -> void:
	var dir := OS.get_user_data_dir().path_join("medical_test_log" + OS.get_environment("CONTRACTOR_TEST_TAG"))
	_remove(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	SessionLog.start(dir)


## The open session log's treatment lines ("<who> treats <whom>: ...") with `text` in them.
func _care_lines(text: String) -> Array:
	var lines := FileAccess.get_file_as_string(SessionLog.folder.path_join("session.log")).split("\n")
	return Array(lines).filter(func(l: String) -> bool: return " treats " in l and text in l and not "  [ok] " in l and not "  [FAIL] " in l)


## Removes this test's scratch folder (under user://, made by this test).
static func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _test_use_medical() -> void:
	print("H: the next item you carry, on yourself")
	_restock()
	_wound(player.vitals, Vitals.THIGH_L, "arterial", 1.2)
	_wound(player.vitals, Vitals.FOREARM_R, "muscle", 0.25)
	player._server_use_medical.rpc_id(1)
	check(not player.vitals.is_healing(), "nothing carried: nothing happens")
	player.inventory.take(&"pressure_bandage")
	player._server_use_medical.rpc_id(1)
	check(player.vitals.is_healing() and absf(player._server_busy_until - Soldier._now() - 5.0) < 0.05, "no tourniquet: the bandage, next on the list (5 s)")
	player._server_busy_until = 0.0
	player.global_position += Vector3(2.0, 0, 0)  # interrupt
	await _seconds(0.3)
	_place_player()
	player.inventory.take(&"ifak")
	player._server_busy_until = 0.0
	player._server_use_medical.rpc_id(1)
	check(absf(player._server_busy_until - Soldier._now() - 6.0) < 0.05, "with an IFAK: its tourniquet first, 6 s on yourself")
	await _seconds(6.2)
	check(player.vitals.tourniquets().has(Vitals.THIGH_L) and player.inventory.medical_count(&"tourniquet") == 0, "the IFAK's tourniquet is on")
	player._server_use_medical.rpc_id(1)
	await _seconds(5.2)
	check(player.inventory.count_of(&"pressure_bandage") == 0 and player.vitals.bleed_rate() == 0.0, "then the loose bandage before the IFAK's")
	_reset(player)
	player._server_use_medical.rpc_id(1)
	check(not player.vitals.is_healing(), "unhurt: nothing to treat")
	player.inventory.remove_one(&"ifak")


## Items expansion (2026-10-20): consumables by mouth (WoundModel.take_drug). Ibuprofen and
## paracetamol ease a little pain (OTC_RELIEF_MAX together, well under morphine), caffeine speeds
## stamina recovery and lifts the heart rate a little, water and rations speed recovery a little
## (STAMINA_BOOST_MAX together); none of it sedates, and it all wears off.
func _test_consumables() -> void:
	print("Consumables: painkillers, caffeine, water and rations")
	var m := _model(5)
	var plain := _model(5)
	for w: WoundModel in [m, plain]:
		w.pain_wounds = 0.6
		w.update_state(0.0)
	check(m.take_drug(&"ibuprofen", 1.0) and absf(m.drug_total(&"ibuprofen") - 1.0) < 0.001 and not m.take_drug(&"no_such_drug", 1.0),
		"two ibuprofen tablets go in as a dose; an unknown drug doesn't")
	_step(m, 300.0)
	_step(plain, 300.0)
	var eased := plain.pain() - m.pain()
	check(eased > 0.08 and eased <= WoundModel.OTC_RELIEF_MAX + 0.001 and absf(eased - m.otc_relief()) < 0.01,
		"five minutes on, ibuprofen takes %.2f off the pain (%.2f -> %.2f)" % [eased, plain.pain(), m.pain()])
	m.take_drug(&"paracetamol", 2.0)
	m.take_drug(&"ibuprofen", 2.0)
	_step(m, 300.0)
	_step(plain, 300.0)
	check(absf(m.otc_relief() - WoundModel.OTC_RELIEF_MAX) < 0.001 and m.otc_relief() < WoundModel.MORPHINE_RELIEF and m.morphine_level == 0.0 and not m.unconscious,
		"a fistful of both stops at %.2f off (morphine's dose is %.2f), and nothing sedates" % [m.otc_relief(), WoundModel.MORPHINE_RELIEF])
	var fit := _model(6)
	var drank := _model(6)
	check(is_equal_approx(fit.stamina_mult(), 1.0) and drank.take_drug(&"caffeine", 1.0), "unhurt: stamina recovers at 1x; an energy drink goes in")
	_step(fit, 240.0)
	_step(drank, 240.0)
	var boost := drank.stamina_mult() - fit.stamina_mult()
	check(boost > 0.2 and boost <= 0.3 + 0.001 and drank.heart_rate > fit.heart_rate + 3.0,
		"four minutes on, stamina recovers %.0f%% faster and the heart beats a little faster (%.0f vs %.0f)" % [boost * 100.0, drank.heart_rate, fit.heart_rate])
	drank.take_drug(&"caffeine", 4.0)
	drank.take_drug(&"water", 2.0)
	drank.take_drug(&"ration", 2.0)
	_step(drank, 300.0)
	check(is_equal_approx(drank.stamina_boost(), WoundModel.STAMINA_BOOST_MAX), "cans, water and an MRE together stop at +%.0f%%" % (WoundModel.STAMINA_BOOST_MAX * 100.0))
	_step(drank, 4.0 * 3600.0)
	check(drank.stamina_boost() < 0.05 and drank.otc_relief() == 0.0, "hours later it has worn off (+%.0f%%)" % (drank.stamina_boost() * 100.0))
	var net := _model(7)
	net.apply_net(drank.to_net())
	check(absf(net.drug_total(&"caffeine") - drank.drug_total(&"caffeine")) < 0.02, "what's in the blood replicates with the rest")


## Items expansion: an energy drink, painkillers and a ration used from the inventory (the Use
## action: Soldier "consume", Consumables): one used each time, the dose in the blood.
func _test_consume_in_session() -> void:
	print("Consumables from the inventory")
	_restock()
	_reset(player)
	var inv := player.inventory
	inv.take(&"energy_drink", 2)
	inv.take(&"ibuprofen")
	inv.take(&"mre")
	for want: Array in [[&"energy_drink", &"caffeine", 1.0, 1], [&"ibuprofen", &"ibuprofen", 1.0, 0], [&"mre", &"ration", 1.5, 0]]:
		var at := _carried_at(inv, want[0])
		var before := player.vitals.drug_total(want[1])
		player._server_inventory_action("consume", at[0], at[1], &"", &"")
		check(absf(player.vitals.drug_total(want[1]) - before - float(want[2])) < 0.05 and inv.count_of(want[0]) == want[3],
			"%s: %.1f dose of %s, %d left" % [want[0], float(want[2]), want[1], inv.count_of(want[0])])
	check(Consumables.verb(ItemDB.get_item(&"energy_drink")) == "Drink" and Consumables.verb(ItemDB.get_item(&"mre")) == "Eat"
		and Consumables.verb(ItemDB.get_item(&"ibuprofen")) == "Take" and Consumables.verb(ItemDB.get_item(&"battery_aa")) == "Use",
		"the Use button says Drink, Eat, Take or Use")
	var at := _carried_at(inv, &"energy_drink")
	check(Consumables.server_use(player, at[0], at[1]) == "" and inv.count_of(&"energy_drink") == 0, "the second can too")
	check(Consumables.server_use(player, &"backpack", 99) != "", "nothing there: nothing used")
	inv.take(&"battery_aa")
	at = _carried_at(inv, &"battery_aa")
	check(Consumables.server_use(player, at[0], at[1]) == "No NVG needs a battery" and inv.count_of(&"battery_aa") == 1, "no NVG: the batteries stay")
	inv.remove_one(&"battery_aa")
	_reset(player)
	await _seconds(0.1)


func _carried_at(inv: Inventory, id: StringName) -> Array:
	for c in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if list[i].id == id:
				return [c, i]
	return [&"", -1]


func _test_menu_and_removal() -> void:
	print("Treat menu, packing and taking a tourniquet off")
	_restock()
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	casualty.vitals.server_damage(70.0)  # 42% lost: down
	await _frames(2)
	# Earlier treatments may have left the casualty at its ragdoll's resting place.
	# Stand beside the visible body before testing the menu's item progression.
	var at := casualty.body_point()
	player.global_position = Vector3(at.x, SPOT.y, at.z - 1.0)  # courtyard side of the perimeter wall
	var treat := _action(player, casualty, &"treat")
	var labels: Array = treat.get("items", []).map(func(e: Dictionary) -> String: return e.label)
	check(labels.size() >= 3 and labels[0] == "Tourniquet, left thigh" and labels[1] == "Tourniquet (rushed, 1.5 s), left thigh" and labels[2] == "NPA Airway, head",
		"Treat on a casualty: %s" % [labels])
	check(treat.items[0].disabled == "You have no Tourniquet", "greyed out without the item (%s)" % treat.items[0].disabled)
	player.inventory.take(&"trauma_kit")
	check(_action(player, casualty, &"revive").is_empty(), "no Revive, even with a trauma kit: casualties come round on their own")
	treat = _action(player, casualty, &"treat")
	InteractionMenu.perform(player, treat.items[0])
	await _seconds(4.2)
	labels = _action(player, casualty, &"treat").items.map(func(e: Dictionary) -> String: return e.label)
	check(labels.has("Hemostatic Gauze (pack under tourniquet), left thigh") and not labels.any(func(l: String) -> bool: return l.begins_with("Remove")),
		"tourniquet on: packing offered, no removal yet (%s)" % [labels])
	var packing: Array = _action(player, casualty, &"treat").items.filter(func(e: Dictionary) -> bool: return e.label.begins_with("Hemostatic"))
	if packing.is_empty():
		_reset(casualty)  # the progression assertion above failed; keep later sections independent
		return
	var pack: Dictionary = packing[0]
	InteractionMenu.perform(player, pack)
	await _seconds(8.2)
	var remove: Array = _action(player, casualty, &"treat").items.filter(func(e: Dictionary) -> bool: return e.id == &"remove_tourniquet")
	check(remove.size() == 1 and remove[0].label == "Remove tourniquet, left thigh", "packed: Remove tourniquet offered")
	var report := InteractionMenu.condition_report(casualty)
	check(report.contains("Left thigh: arterial bleed, packed") and report.contains("Tourniquet on the left thigh"), "Check condition shows what's been done: %s" % report.replace("\n", " | "))
	var tourniquets := player.inventory.medical_count(&"tourniquet")
	if not remove.is_empty():
		InteractionMenu.perform(player, remove[0])
	await _seconds(3.2)
	check(casualty.vitals.tourniquets().is_empty() and casualty.vitals.bleed_rate() == 0.0, "the tourniquet comes off, the packing holds")
	check(player.inventory.medical_count(&"tourniquet") == tourniquets + 1, "and goes back in your kit")
	_reset(casualty)
	player.inventory.remove_one(&"trauma_kit")


## Audit A2-05: a medic carrying everything gets more item rows than fit; the list scrolls
## (mouse wheel), every usable row can be brought on screen and clicked, and only the rows on
## screen are hit (none past the panel's foot, unseen).
func _test_medical_menu_scrolls() -> void:
	print("Medical menu: a long item list scrolls")
	player.inventory.strip()
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"aid_bag")
	for id: StringName in MedicalMenu.medical_ids():
		if not ItemDB.get_item(id).stats.get("no_item", false):
			player.inventory.take(id)
	_place_player()
	_reset(casualty)
	_reset(player)
	var m: WoundModel = casualty.vitals._model
	m.blood = 0.8
	m.pain_wounds = 0.5
	m.burn = 0.2
	m.access = {"kind": "iv", "gauge": 18, "part": &"forearm_l", "pressure": false}
	m._add_wound(&"forearm_l", "muscle", 0.1)
	m._add_fracture(&"forearm_l", &"forearm_bones_l")
	casualty.vitals._after_change(true)
	await _frames(2)
	var menu := player.player_input.medical_menu
	var root := get_tree().root
	var old_size := root.size
	await _window(1600, 900)  # the menu fits itself to the window (P0-2): a real one, not headless 64 x 64
	menu.open(casualty)
	menu.select_part(&"forearm_l")
	var panel := menu._panel()
	var fits := menu.visible_rows()
	var usable := range(menu.options.size()).filter(func(i: int) -> bool: return menu.options[i].disabled == "")
	check(menu.options.size() > fits and usable.any(func(i: int) -> bool: return i >= fits),
		"a full kit: %d rows, %d fit, usable ones past them" % [menu.options.size(), fits])
	var wheel := func(down: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		e.pressed = true
		e.position = menu._rows_origin() + Vector2(100, 10)
		menu._gui_input(e)
	var unreachable := []
	var hit_unseen := []
	for i: int in usable:
		for step in menu.options.size():
			if menu.row_shown(i):
				break
			wheel.call(i >= menu.scroll)
		var rect := menu._row_rect(i)
		if not menu.row_shown(i) or rect.end.y > panel.end.y - 52.0 + 0.01 or menu._row_at(rect.get_center()) != i:
			unreachable.append(menu.options[i].label)
		for j in menu.options.size():
			if not menu.row_shown(j) and menu._row_at(menu._row_rect(j).get_center()) == j:
				hit_unseen.append(menu.options[j].label)
	check(unreachable.is_empty(), "the wheel brings every usable row into the list, inside the panel, and it's hit there (out of reach: %s)" % [unreachable])
	check(hit_unseen.is_empty(), "rows scrolled out of the list are never hit (%s)" % [hit_unseen])
	# The last usable row, clicked: its treatment starts, like any other.
	var last: int = usable[-1]
	for step in menu.options.size():
		if menu.row_shown(last):
			break
		wheel.call(last >= menu.scroll)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = menu._row_rect(last).get_center()
	var item: StringName = menu.options[last].item
	menu._gui_input(click)
	check(menu.row_shown(last) and casualty.vitals.is_healing() and player._server_busy_until > Soldier._now(),
		"scrolled to it, clicking the last usable row (%s) starts it" % menu.options[last].label)
	await _seconds(player.treat_seconds(casualty, ItemDB.get_item(item)) + 0.3)
	# In a short window (the panel at its least height) the activity log, full, still ends
	# above the panel's foot: only the newest lines that fit are drawn.
	await _window(1600, 0)  # the shortest window the layout is made for
	for n in MedicalMenu.MAX_LOG + 4:
		menu._add_log("Test line %d" % n)
	var font := menu.get_theme_default_font()
	panel = menu._panel()
	var shown := menu.log_lines_shown(font)
	var log_end := panel.position.y + MedicalMenu.LOG_Y + 22.0 + (shown - 1) * font.get_height(MedicalMenu.LOG_FONT) + font.get_descent(MedicalMenu.LOG_FONT)
	check(shown >= 1 and log_end <= panel.end.y and menu.log_lines.size() == MedicalMenu.MAX_LOG,
		"a full activity log in a %.0f px panel: %d of %d lines drawn, ending %.0f px above its foot" % [panel.size.y, shown, menu.log_lines.size(), panel.end.y - log_end])
	root.size = old_size
	await _frames(2)
	menu.close()
	_reset(casualty)
	_reset(player)
	_restock()


## H: the medical menu (MedicalMenu) on the casualty you look at, else yourself; Shift+H
## still quick-treats yourself.
func _test_medical_menu() -> void:
	print("Medical menu (H): diagram, items with reasons, treating from it; Shift+H quick-treat")
	_restock()
	_place_player()
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	casualty.vitals.server_damage(70.0)  # down
	await _frames(2)
	var thigh := MedicalMenu.part_state(casualty.vitals, Vitals.THIGH_L)
	check(thigh.state == MedicalMenu.BLEEDING and thigh.severity == 3 and MedicalMenu.state_color(thigh) == MedicalMenu.BLEED_COLORS[3],
		"a bleeding thigh artery: the left thigh shows severe bleeding (%s)" % [thigh])
	var chest := MedicalMenu.part_state(casualty.vitals, Vitals.CHEST)
	check(chest.state == MedicalMenu.OK and MedicalMenu.state_color(chest) == MedicalMenu.STATE_COLORS[MedicalMenu.OK], "an unhurt chest shows plain (%s)" % [chest])
	var input := player.player_input
	var menu := input.medical_menu
	input._unhandled_input(_key(KEY_H, false))
	check(menu.is_open() and menu.target == casualty and menu.part == Vitals.THIGH_L,
		"H opens it on the casualty in front, at the left thigh (%s, %s)" % [menu.target, menu.part])
	player.inventory.take(&"trauma_kit")
	player.inventory.take(&"iv_18")
	menu.refresh()
	var shown := {}
	for row in menu.options:
		if row.has("item"):
			shown[row.item] = true
	var carried := MedicalMenu.medical_ids().filter(func(id: StringName) -> bool: return Vitals.has_item(player.inventory, id))
	check(shown.size() == carried.size() and carried.all(func(id: StringName) -> bool: return shown.has(id)),
		"every medical item you carry is listed (%s)" % [shown.keys()])
	var rows := {}
	for row in menu.options:
		if row.has("item") and not row.rushed:
			rows[row.item] = row
	check(menu.options[0].item == &"tourniquet" and rows[&"tourniquet"].disabled == "", "the tourniquet is usable, top of the list (%s)" % menu.options[0].label)
	check(rows[&"splint"].disabled == casualty.vitals.treatment_problem(&"splint", Vitals.THIGH_L) and rows[&"splint"].disabled != "",
		"the splint greyed out: %s" % rows[&"splint"].disabled)
	check(rows[&"iv_18"].disabled == "An IV goes in a forearm or lower leg", "the IV greyed out: %s" % rows[&"iv_18"].disabled)
	check(not shown.has(&"saline_500"), "nothing you don't carry")
	menu.choose(menu.options.find(rows[&"tourniquet"]))
	var tq := ItemDB.get_item(&"tourniquet")
	check(casualty.vitals.is_healing() and absf(player._server_busy_until - Soldier._now() - player.treat_seconds(casualty, tq)) < 0.05,
		"choosing the tourniquet starts the same timed treatment (%.1f s)" % player.treat_seconds(casualty, tq))
	await _seconds(4.3)
	menu.refresh()
	thigh = MedicalMenu.part_state(casualty.vitals, Vitals.THIGH_L)
	check(thigh.markers.has(MedicalMenu.TOURNIQUET) and thigh.state != MedicalMenu.BLEEDING, "then the thigh shows a tourniquet, no bleeding (%s)" % [thigh])
	check(Array(menu.log_lines).any(func(l: String) -> bool: return l.contains("You: Tourniquet (")) \
		and Array(menu.log_lines).any(func(l: String) -> bool: return l.ends_with("Left thigh: TQ on")), "the activity log has both (%s)" % [menu.log_lines])
	# Triage card: set from the menu through the host, replicated, shown in Check condition.
	menu.set_triage(Vitals.TRIAGE_IMMEDIATE)
	await _frames(3)
	check(casualty.vitals.triage() == Vitals.TRIAGE_IMMEDIATE and casualty.vitals.net_state.get("tg") == "immediate",
		"the menu puts a red triage card on him, replicated in net_state (%s)" % casualty.vitals.triage())
	check(InteractionMenu.condition_report(casualty, player).contains("Immediate (red)"), "Check condition shows the card")
	var old_size := get_tree().root.size
	await _window(1600, 900)  # laid out in a real window, not headless 64 x 64
	check(menu.triage_at(menu._triage_rect(2).get_center()) == Vitals.TRIAGE_DELAYED, "the triage buttons are hit-tested")
	get_tree().root.size = old_size
	player.global_position += Vector3(30, 0, 0)
	player._server_set_triage.rpc_id(1, casualty.get_path(), Vitals.TRIAGE_MINIMAL)
	await _frames(3)
	check(casualty.vitals.triage() == Vitals.TRIAGE_IMMEDIATE, "out of reach the card doesn't change")
	_place_player()
	_reset(casualty)
	check(casualty.vitals.triage() == Vitals.TRIAGE_NONE, "a fresh life has no card")
	menu._unhandled_input(_key(KEY_H, false))
	check(not menu.is_open(), "H closes it")
	_reset(casualty)
	_wound(player.vitals, Vitals.FOREARM_R, "muscle", 0.25)
	player._server_busy_until = 0.0
	input._unhandled_input(_key(KEY_H, true))
	var bandage := ItemDB.get_item(&"pressure_bandage")
	check(not menu.is_open() and player.vitals.is_healing() and absf(player._server_busy_until - Soldier._now() - player.treat_seconds(player, bandage)) < 0.05,
		"Shift+H quick-treats yourself (a bandage), no menu")
	await _seconds(player.treat_seconds(player, bandage) + 0.2)
	check(player.vitals.bleed_rate() == 0.0, "and the bandage is on")
	player.rotation.y = PI  # nobody in front
	input._unhandled_input(_key(KEY_H, false))
	check(menu.is_open() and menu.target == player, "H with nobody in front: on yourself")
	menu._unhandled_input(_key(KEY_ESCAPE, false))
	check(not menu.is_open(), "Escape closes it")
	_place_player()
	_reset(player)
	player.inventory.remove_one(&"trauma_kit")
	player.inventory.remove_one(&"iv_18")


## Captain's playtest P0164: a body nearer the crosshair than the casualty took the H menu,
## and every item said "Too late". The living come first; a body alone is still checkable.
func _test_menu_prefers_living() -> void:
	print("Medical menu: the living before a body nearer the crosshair")
	_place_player()
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	casualty.vitals.server_damage(70.0)  # down
	var body := _spawn_ai("MenuBody", SPOT + Vector3(0.7, 0, -1.0))
	await _frames(2)
	body.vitals.server_kill()
	var start := Time.get_ticks_msec()
	while not (is_instance_valid(body.ragdoll) and body.ragdoll.frozen) and Time.get_ticks_msec() - start < 8000:
		await get_tree().physics_frame
	# Keep both actual bodies within treatment reach after they settle, even when a
	# ragdoll slid away from its capsule. Retain the nearer-to-crosshair dead body.
	var living_at := casualty.body_point()
	var shift := living_at + Vector3(0.7, 0, -0.5) - body.body_point()
	body.global_position += Vector3(shift.x, 0, shift.z)
	for frame in 2:
		await get_tree().physics_frame
	player.global_position = Vector3(living_at.x, SPOT.y, living_at.z - 1.5)
	check(player._in_treat_reach(casualty) and player._in_treat_reach(body), "both settled bodies are in treatment reach")
	var aim := body.body_point()
	player.look_at(Vector3(aim.x, player.global_position.y, aim.z), Vector3.UP)
	await _frames(1)
	var eye0 := player.camera.global_position
	player.head.rotation.x = atan2(aim.y - eye0.y, Vector2(aim.x - eye0.x, aim.z - eye0.z).length())  # looking down at it
	await _frames(2)
	var eye := player.camera.global_position
	var forward := -player.camera.global_basis.z
	var body_angle := rad_to_deg(forward.angle_to(body.body_point() - eye))
	var casualty_angle := rad_to_deg(forward.angle_to(casualty.body_point() - eye))
	check(body_angle < casualty_angle and casualty_angle < InteractionMenu.VIEW_CONE_DEG,
		"(set up: both in view, the body nearer the crosshair, %.0f against %.0f degrees)" % [body_angle, casualty_angle])
	check(MedicalMenu.looked_at(player, player.camera) == casualty, "H goes to the living casualty, not the body")
	check(body.vitals.treatment_problem(&"bandage", Vitals.THIGH_L) == "Already dead", "and a body's items say \"Already dead\"")
	_reset(casualty)
	casualty.global_position = SPOT + Vector3(0, 0, 30)  # out of reach: the body alone
	await _frames(3)
	check(MedicalMenu.looked_at(player, player.camera) == body, "with nobody alive in reach, the body (to check it)")
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	body.queue_free()
	_place_player()
	await _frames(2)


## The corner silhouette: shows while the player bleeds untreated, highlights the part, goes when treated.
func _test_bleed_hud() -> void:
	print("HUD silhouette while bleeding")
	_place_player()
	_reset(player)
	_restock()
	player.inventory.take(&"pressure_bandage")
	player._server_busy_until = 0.0
	var sil: Control
	for c in player.player_input.hud.get_children():
		if c is Hud.BleedSilhouette:
			sil = c
	check(sil != null, "the HUD has the silhouette")
	await _frames(2)
	check(not sil.visible, "hidden with nothing to show")
	_wound(player.vitals, Vitals.THIGH_L, "muscle", 0.25)
	await _frames(2)
	check(sil.visible and sil.parts.size() == 1 and sil.parts[0] == Vitals.THIGH_L, "a bleeding thigh shows it, highlighting the left thigh (%s, %s)" % [sil.visible, sil.parts])
	player._server_treat.rpc_id(1, player.get_path(), &"pressure_bandage", Vitals.THIGH_L)
	await _seconds(player.treat_seconds(player, ItemDB.get_item(&"pressure_bandage")) + 0.3)
	await _frames(2)
	check(player.vitals.bleed_rate() == 0.0 and not sil.visible, "treated, it disappears (%s, bleed %.2f, %s)" % [sil.parts, player.vitals.bleed_rate(), player.vitals.wound_list()])
	_reset(player)
	player.inventory.remove_one(&"pressure_bandage")


func _key(key: Key, shift: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	event.shift_pressed = shift
	return event


## Through the real host requests: tourniquet and morphine, then the casualty comes round.
func _test_wakes_in_session() -> void:
	print("Treated through the host requests, a casualty comes round")
	_restock()
	casualty.vitals._model.npa = true  # the airway is covered by the rules above
	casualty.vitals._model.pain_wounds = 0.95
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	casualty.vitals.server_advance(WoundModel.PAIN_KNOCKOUT_S + 0.1)  # pain held long enough to knock him out
	await _frames(2)
	check(casualty.vitals.downed and casualty.vitals.why_unconscious() == [&"pain"], "the casualty is out from the pain (%s)" % [casualty.vitals.why_unconscious()])
	var woke := [false]
	casualty.vitals.woke.connect(func() -> void: woke[0] = true, CONNECT_ONE_SHOT)
	player.inventory.take(&"trauma_kit")
	player._server_treat.rpc_id(1, casualty.get_path(), &"tourniquet", Vitals.THIGH_L)
	await _seconds(4.2)
	check(casualty.vitals.bleed_rate() == 0.0 and casualty.vitals.downed, "a tourniquet from the trauma kit: the bleeding stops, still out")
	player._server_treat.rpc_id(1, casualty.get_path(), &"morphine", Vitals.TORSO)
	await _seconds(2.2)
	check(casualty.vitals.downed and casualty.vitals._model.morphine_total() > 0.9, "morphine in")
	casualty.vitals.server_advance(WoundModel.MORPHINE_ABSORB_S + WoundModel.WAKE_S[&"pain"] + 1.0)
	check(casualty.vitals.is_up() and woke[0], "and he comes round on his own (%s)" % casualty.vitals.condition_text())
	check(player.inventory.count_of(&"trauma_kit") == 1 and player.inventory.medical_count(&"tourniquet") == 1 and player.inventory.medical_count(&"morphine") == 1,
		"both came out of the trauma kit, which stays")
	_reset(casualty)
	player.inventory.remove_one(&"trauma_kit")


func _test_splint_movement() -> void:
	print("Splint: jog, no sprint (movement)")
	_restock()
	var move := player.movement
	var normal := move.top_speed(false, false)
	_wound(player.vitals, Vitals.THIGH_L, "fracture", WoundModel.FEMUR_RATE, &"femur_l")
	check(move.top_speed(false, false) < normal * 0.7 and not move.can_sprint(), "broken leg: walking pace (%.1f of %.1f m/s), no sprint" % [move.top_speed(false, false), normal])
	player.inventory.take(&"splint")
	player._server_treat.rpc_id(1, player.get_path(), &"splint", Vitals.THIGH_L)
	await _seconds(8.2)
	check(absf(move.top_speed(false, false) - normal) < 0.01 and not move.can_sprint(), "splinted: back to a jog (%.1f m/s), still no sprint" % move.top_speed(false, false))
	_reset(player)
	check(move.can_sprint(), "after a respawn you can sprint again")


# --- Helpers -------------------------------------------------------------------------------

## Starts `item` on `target` and interrupts it by stepping away; returns how long it would
## have taken (seconds the host made the treater busy). Checks it was interrupted cleanly.
func _start_and_interrupt(target: Soldier, item: StringName, part: StringName, rushed: bool) -> float:
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, target.get_path(), item, part, rushed)
	var seconds := player._server_busy_until - Soldier._now()
	var started := target.vitals.is_healing()
	player.global_position += Vector3(1.5, 0, 0)
	await _seconds(0.3)
	check(started and not target.vitals.is_healing() and player._server_busy_until <= Soldier._now() + 0.01, "  %s started, then interrupted by stepping away" % item)
	_place_player()
	return seconds


## Adds a wound straight into a body's wound model (and publishes it).
func _wound(v: Vitals, part: StringName, kind: String, rate: float, name: StringName = &"") -> Dictionary:
	var w := v._model._add_wound(part, kind, rate, name)
	v._model.update_state(0.0)
	v._after_change(true)
	return w


func _vitals() -> Vitals:
	var v := Vitals.new()
	add_child(v)
	v.rng.seed = 1
	v.care_rng.seed = 1
	return v


func _model(seed_value := 1) -> WoundModel:
	var m := WoundModel.new()
	m.rng.seed = seed_value
	m.care_rng.seed = seed_value
	return m


## Runs a model for `seconds` in the host's 0.1 s steps.
func _step(m: WoundModel, seconds: float) -> void:
	while seconds > 0.0001:
		var dt := minf(seconds, Vitals.SIM_STEP_S)
		m.advance(dt)
		seconds -= dt


## The player with only a carrier, a pack and a rifle: no medical items.
func _restock() -> void:
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1"]:
		player.inventory.take(id)


func _reset(s: Soldier) -> void:
	s.vitals.server_reset_health()
	s._server_busy_until = 0.0


## The states of the stowed entries of `id` ({} for an untouched one).
func _states(inv: Inventory, id: StringName) -> Array:
	var out := []
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inv.containers[container]:
			if entry.id == id:
				for i in int(entry.count):
					out.append(entry.get("state", {}))
	return out


func _place_player() -> void:
	player.global_position = SPOT
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO


func _spawn_ai(callsign: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # we stage everything by hand
	return s


func _action(actor: Soldier, target: Node, id: StringName) -> Dictionary:
	for a in InteractionMenu.actions_for(actor, target):
		if a.id == id:
			return a
	return {}


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Sizes the root window so its visible rect (after the UI scale) is `w` x `h` logical px; `h`
## 0: the shortest the medical menu is made for (MedicalMenu.PANEL_MIN_H and its margins).
func _window(w: int, h: int) -> void:
	var root := get_tree().root
	var tall := float(h) if h > 0 else MedicalMenu.PANEL_MIN_H + MedicalMenu.PANEL_MARGIN * 2.0
	root.size = Vector2i(ceili(w * root.content_scale_factor), ceili(tall * root.content_scale_factor))
	await _frames(2)


## Players treat with the casualty's own kit when they carry none (Captain, co-op playtest
## 2026-10-15: "unable to use the other's medical items"): taken from theirs, host-side.
func _test_casualty_kit_for_players() -> void:
	print("Treating from the casualty's kit")
	_restock()
	_reset(casualty)
	var was := casualty.global_position
	player.global_position = casualty.global_position + Vector3(0.8, 0, 0)
	_wound(casualty.vitals, Vitals.FOREARM_L, "muscle", 0.25)
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack"]:
		player.inventory.take(id)
	if casualty.inventory.count_of(&"assault_pack") == 0 and casualty.inventory.slots.get(&"backpack", &"") == &"":
		casualty.inventory.take(&"assault_pack")
	casualty.inventory.take(&"pressure_bandage")
	var theirs := casualty.inventory.medical_count(&"pressure_bandage")
	check(player.inventory.medical_count(&"pressure_bandage") == 0 and theirs > 0, "setup: only the casualty carries a bandage")
	check(Soldier.kit_has(player, casualty, &"pressure_bandage") and not Soldier.kit_has(player, player, &"pressure_bandage"),
		"the menus count the casualty's bandage as usable")
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L, false, true)
	await _seconds(5.3)
	var w: Dictionary = casualty.vitals.wound_list()[0]
	check(w.treated and casualty.inventory.medical_count(&"pressure_bandage") == theirs - 1 and player.inventory.medical_count(&"pressure_bandage") == 0,
		"treated with the casualty's own bandage, used up from theirs (%d left)" % casualty.inventory.medical_count(&"pressure_bandage"))
