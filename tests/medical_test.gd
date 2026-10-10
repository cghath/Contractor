extends Node3D
## Headless checks for the kit and treatment (design doc "The kit", "Tourniquet", "Fractures",
## "Chest"): each item's effect, the rushed and second tourniquet, packing then taking a
## tourniquet off, seals and tension, splints, morphine as a level in the blood (relief,
## sedation, slowed breathing), NPAs and airway obstruction, care_needed's order, treatment
## waking a casualty (there is no revive), kits as bags of items, and, in a hosted session,
## the timed host requests (times on yourself and others, interruptions, H, the Treat menu,
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
	_test_airway()
	_test_care_order()
	_test_treatment_wakes()
	_test_kits()
	await _start_session()
	await _test_times()
	await _test_completed_treatments()
	await _test_interruptions()
	await _test_use_medical()
	await _test_menu_and_removal()
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
	check(v.server_apply_treatment(&"hemostatic_gauze", Vitals.NECK) and v.bleed_rate() == 0.0 and v.wound_list()[0].packed, "gauze packs it")
	v.server_reset_health()
	_wound(v, Vitals.ABDOMEN, "internal", 1.5, &"aorta")
	check(v.care_needed().is_empty(), "internal bleeding: care_needed asks for nothing (wave 3's surgery kit)")
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
	check(late.server_apply_treatment(&"chest_seal", Vitals.CHEST) and late.care_needed().is_empty(), "a seal still closes it (nothing more the kit can do)")
	late.server_advance(WoundModel.TENSION_ARREST_S)
	check(late.in_cardiac_arrest(), "but doesn't relieve the tension: cardiac arrest (the needle is wave 3)")
	v.queue_free()
	late.queue_free()


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


## A bleed too small to matter for an hour or two, so blood doesn't creep back
## (WoundModel.BLOOD_RECOVER_PER_MIN) and wake a casualty a test keeps out on blood loss.
func _trickle(m: WoundModel) -> void:
	m._add_wound(Vitals.SHIN_R, "graze", 0.0005)


func _test_airway() -> void:
	print("NPA and airway obstruction")
	var m := _model(5)
	m.care_rng.seed = 5
	m.blood = 0.58  # unconscious
	_trickle(m)
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
		_trickle(c)
		c.update_state(0.0)
		for s in 60:
			c.advance(1.0)
		if c.airway_blocked:
			blocked += 1
	check(absf(blocked / 400.0 - WoundModel.AIRWAY_BLOCK_PER_MIN) < 0.04, "%.0f%% obstruct within a minute" % (blocked / 4.0))
	var fixed := _model(6)
	fixed.care_rng.seed = 6
	fixed.blood = 0.58
	_trickle(fixed)
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
	var expected := ["tourniquet@thigh_l", "hemostatic_gauze@neck", "npa@head", "chest_seal@chest", "pressure_bandage@thigh_r",
		"pressure_bandage@forearm_l", "pressure_bandage@shin_r", "splint@shin_l", "morphine@torso"]
	check(items == expected, "massive bleeding, airway, chest, other bleeding, fractures, pain (%s)" % [items])
	v.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	v.server_apply_treatment(&"npa", Vitals.HEAD)
	items = v.care_needed().map(func(t: Dictionary) -> String: return "%s@%s" % [t.item, t.part])
	check(items.size() == expected.size() - 2 and items[0] == "hemostatic_gauze@neck", "handled ones drop out (%s)" % [items])
	check(v.care_needed().all(func(t: Dictionary) -> bool: return Vitals.CARE_ORDER.has(t.kind) and Vitals.TREATS[t.kind] == t.item or t.kind == "pain"),
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
	_reset(casualty)
	_reset(player)


func _test_interruptions() -> void:
	print("Interruptions")
	_restock()
	_wound(casualty.vitals, Vitals.FOREARM_L, "muscle", 0.25)
	player.inventory.take(&"pressure_bandage")
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	await _seconds(0.3)
	casualty.global_position += Vector3(1.5, 0, 0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing() and player._server_busy_until <= Soldier._now(), "the casualty moved away: interrupted")
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_L)
	await _seconds(0.3)
	player.vitals.server_damage(500.0)
	await _seconds(0.3)
	check(not casualty.vitals.is_healing() and casualty.vitals.wound_list()[0].bleeding, "the treater went down: interrupted")
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
	casualty.global_position = SPOT + Vector3(0, 0, -1.5)
	_reset(casualty)
	_reset(player)
	player.inventory.remove_one(&"pressure_bandage")


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


func _test_menu_and_removal() -> void:
	print("Treat menu, packing and taking a tourniquet off")
	_restock()
	_wound(casualty.vitals, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l")
	casualty.vitals.server_damage(70.0)  # 42% lost: down
	await _frames(2)
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
	var pack: Dictionary = _action(player, casualty, &"treat").items.filter(func(e: Dictionary) -> bool: return e.label.begins_with("Hemostatic"))[0]
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
