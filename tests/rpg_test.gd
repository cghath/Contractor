extends Node
## The RPG layer of Contractor: Fallen (docs/survival_rpg.md section 8): a world made with a
## background and flaws starts its survivor's lines there; the XP curve and the at/below/above
## rule; a slow learner's x0.8; a gate refused at 2 and allowed at 3; a perk pick (carry weight);
## a flaw's points buying a level; the cold of the thin-skinned; the step noise; the silent kill
## for a machete at melee 4 and the heavy swing at 2; XP from treatments, searches, running and
## time unseen near the dead; reading a manual; crafting gated by station and level, using its
## inputs and giving its output; the character screen; permadeath wiping it all.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier

const CREATION := {"background": "nurse", "flaws": ["slow_learner"], "buys": {"fitness": 2}}


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("RPG TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_test_curve()
	_test_creation_rules()
	await _test_world()
	if level != null and player != null:
		_test_xp_rule()
		_test_gates()
		_test_perks()
		_test_flaws()
		await _test_melee()
		await _test_sources()
		await _test_crafting()
		_test_character_screen()
		await _test_permadeath()
	_finish()


func _test_curve() -> void:
	print("The XP curve (call 82)")
	check(is_equal_approx(RpgLines.xp_for(1), 60.0) and is_equal_approx(RpgLines.xp_for(4), 900.0), "levels 1-4 need 60/120/240/480 (%.0f to 4)" % RpgLines.xp_for(4))
	check(is_equal_approx(RpgLines.step_xp(5), 1000.0) and is_equal_approx(RpgLines.step_xp(10), 36000.0), "5-10 need 1,000 x (n-4)^2 each (%.0f, %.0f)" % [RpgLines.step_xp(5), RpgLines.step_xp(10)])
	check(RpgLines.level_of(899.0) == 3 and RpgLines.level_of(900.0) == 4 and RpgLines.level_of(1e9) == 10, "the level an XP total makes")
	check(RpgLines.survivor_level_of(999.0) == 0 and RpgLines.survivor_level_of(1000.0) == 1 and RpgLines.survivor_xp_for(2) > 2000.0, "a survivor level every 1,000 XP, slowing (%.0f for 2)" % RpgLines.survivor_xp_for(2))
	check(RpgLines.next_unlock("melee", 3) == [4, "silent kill with any blade"], "the next unlock is named (%s)" % [RpgLines.next_unlock("melee", 3)])


func _test_creation_rules() -> void:
	print("Backgrounds and flaws (calls 17, 84)")
	check(Backgrounds.ALL.size() >= 15 and Backgrounds.FLAWS.size() >= 15, "about 15 of each (%d backgrounds, %d flaws)" % [Backgrounds.ALL.size(), Backgrounds.FLAWS.size()])
	check(Backgrounds.FLAWS.values().all(func(f: Dictionary) -> bool: return int(f.points) >= 1 and int(f.points) <= 3), "every flaw is worth 1-3 points")
	var two := {"background": "", "flaws": ["clumsy"], "buys": {"stealth": 2}}
	check(Backgrounds.problem(two) == "" and int(Backgrounds.start_levels(two).get("stealth", 0)) == 2, "a 2-point flaw buys stealth 2 on a blank slate")
	var over := {"background": "", "flaws": ["clumsy"], "buys": {"stealth": 3}}
	check(Backgrounds.problem(over) != "", "but not 3 (%s)" % Backgrounds.problem(over))
	var five := {"background": "burglar", "flaws": ["clumsy"], "buys": {"stealth": 2}}
	check(int(Backgrounds.start_levels(five).get("stealth", 0)) == 5, "a burglar with points starts stealth at 5 (%s)" % [Backgrounds.start_levels(five)])
	var d := Rpg.fresh()
	check(Rpg.apply_creation(d, over) != "" and (d.lines as Dictionary).is_empty(), "an overspent creation leaves a blank slate")


func _test_world() -> void:
	print("A world made with a background")
	check(Survival.server_new_world(main, "test_rpg" + tag, 4321, {"survivor": CREATION}), "a new world with a nurse who learns slowly")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	await _wait_for(func() -> bool: return not Rpg.net().my.is_empty(), 5.0)
	check(Rpg.level(player, "medical") == 3 and Rpg.level(player, "cooking") == 1 and Rpg.level(player, "fitness") == 2 and Rpg.level(player, "melee") == 0,
		"the nurse starts medical 3, cooking 1, and the bought fitness 2 (%s)" % [Rpg.net().my.get("levels", {})])
	check(Rpg.has_flaw(player, "slow_learner") and String(Rpg.data(player).background) == "nurse" and Rpg.survivor_level(player) == 0, "with the flaw recorded and no survivor level yet")
	check(int((Rpg.net().my.get("levels", {}) as Dictionary).get("medical", 0)) == 3, "and the owner has the copy")


func _test_xp_rule() -> void:
	print("XP by doing: at, below, above level")
	var at := Rpg.xp(player, "medical", 10.0, 3)
	var below := Rpg.xp(player, "medical", 10.0, 2)
	var far := Rpg.xp(player, "medical", 10.0, 0)
	var above := Rpg.xp(player, "medical", 10.0, 5)
	check(is_equal_approx(at, 8.0), "at his level: full XP, x0.8 for the slow learner (%.1f)" % at)
	check(is_equal_approx(below, 2.4) and is_equal_approx(far, 0.8), "below it: little (%.1f a level under, %.1f further)" % [below, far])
	check(is_equal_approx(above, 16.0), "above it (a hard one that worked): a lot (%.1f)" % above)
	var earned := float(Rpg.data(player).earned)
	check(earned > 26.0 and earned < 28.0, "the survivor's earned XP counts it all, not the background's start (%.1f)" % earned)


func _test_gates() -> void:
	print("A level unlocks the gate")
	Rpg.set_level(player, "medical", 2)
	check(not Rpg.can(player, "stitch") and Rpg.can(player, "read_bleeding") and Rpg.medical_sees(player) == 1, "a stitch refused at medical 2 (he reads bleeding: sees %d)" % Rpg.medical_sees(player))
	Rpg.set_level(player, "medical", 3)
	check(Rpg.can(player, "stitch") and Rpg.gate(player, "medical", 3) and not Rpg.gate(player, "medical", 4), "done at 3")
	Rpg.set_level(player, "medical", 0)
	check(Rpg.medical_sees(player) == 0, "a novice sees only hurt and bleeding")
	Rpg.set_level(player, "medical", 7)
	check(Rpg.medical_sees(player) == 2, "a doctor sees everything")


func _test_perks() -> void:
	print("A perk pick (call 83)")
	check(Rpg.picks_owed(player) == 0 and Rpg.server_pick_perk(player, "strong_back") != "", "no pick before a survivor level")
	Rpg.data(player).earned = RpgLines.survivor_xp_for(1)
	check(Rpg.survivor_level(player) == 1 and Rpg.picks_owed(player) == 1, "a survivor level owes one pick")
	check(Rpg.server_pick_perk(player, "night_eyes") != "", "night eyes needs stealth 3")
	var bonus := Rpg.carry_bonus_kg(player)
	check(is_equal_approx(bonus, 6.0), "fitness 2 carries 6 kg free (%.1f)" % bonus)
	check(Rpg.server_pick_perk(player, "strong_back") == "" and Rpg.has_perk(player, "strong_back"), "strong back taken")
	check(is_equal_approx(Rpg.carry_bonus_kg(player), bonus + 6.0), "6 kg more carried free (%.1f)" % Rpg.carry_bonus_kg(player))
	var want := maxf(player.inventory.total_mass() - ExoFrame.assist_kg(player.inventory) - Rpg.carry_bonus_kg(player), 0.0)
	check(player.inventory.total_mass() > 0.5 and is_equal_approx(player.load_kg, want) and player.load_kg < player.inventory.total_mass(), "the load he feels is his mass less it (%.1f of %.1f kg)" % [player.load_kg, player.inventory.total_mass()])
	check(Rpg.picks_owed(player) == 0 and Rpg.server_pick_perk(player, "quiet_feet") != "", "and no second pick until the next level")


func _test_flaws() -> void:
	print("Flaws' effects")
	var d := Rpg.data(player)
	(d.flaws as Array).append("thin_skinned")
	check(is_equal_approx(Rpg.cold_mult(player), 1.3), "thin-skinned: the cold gets in 30%% faster (x%.2f)" % Rpg.cold_mult(player))
	var warm := Needs.fresh()
	var thin := Needs.fresh()
	Needs.step(warm, 3.0, {"dark": 1.0, "wind": 8.0, "cold_mult": 1.0})
	Needs.step(thin, 3.0, {"dark": 1.0, "wind": 8.0, "cold_mult": Rpg.cold_mult(player)})
	check(float(thin.warmth) < float(warm.warmth) - 0.05, "three cold hours: %.2f C against %.2f C" % [thin.warmth, warm.warmth])
	(d.flaws as Array).erase("thin_skinned")
	(d.flaws as Array).append("bad_knee")
	player._on_inventory_changed()
	check(Rpg.speed_mult(player) < 1.0 and player.load_mult <= MovementRules.load_speed_mult(player.load_kg) * Rpg.speed_mult(player) + 0.001, "a bad knee slows him (x%.2f)" % Rpg.speed_mult(player))
	(d.flaws as Array).erase("bad_knee")
	player._on_inventory_changed()
	check(Rpg.step_noise_mult(player) == 1.0, "at stealth 0 his steps carry as far as anyone's")
	Rpg.set_level(player, "stealth", 4)
	check(is_equal_approx(Rpg.step_noise_mult(player), 0.8), "at stealth 4 they carry 80%% as far (x%.2f; Survival._footsteps reads it)" % Rpg.step_noise_mult(player))
	(d.flaws as Array).append("clumsy")
	check(is_equal_approx(Rpg.step_noise_mult(player), 0.96), "a clumsy one louder again (x%.2f)" % Rpg.step_noise_mult(player))
	(d.flaws as Array).erase("clumsy")
	Rpg.set_level(player, "stealth", 0)
	var picker := SurvivorPicker.new()
	add_child(picker)
	picker.set_background("nurse")
	picker.set_flaw("slow_learner", true)
	picker.set_buy("fitness", 2)
	check(picker.choice() == {"background": "nurse", "flaws": ["slow_learner"], "buys": {"fitness": 2}} and picker.points_left() == 1 and picker.summary().contains("Nurse"),
		"the New world screen's survivor picker: %s" % picker.summary())
	picker.queue_free()


func _test_melee() -> void:
	print("Melee: the heavy at 2, the parry at 3, any blade's silent kill at 4")
	player.inventory.strip()
	check(not MeleeWeapons.blade_carried(player), "no knife on him")
	check(player.inventory.take(&"machete") == 1, "a machete in the sidearm slot")
	player.select_weapon(&"sidearm")
	var machete := player.active_weapon()
	Rpg.set_level(player, "melee", 1)
	check(not Rpg.can(player, "heavy_swing") and Rpg.parry_window_mult(player) == 1.0, "melee 1: no heavy swing yet")
	Rpg.set_level(player, "melee", 2)
	check(Rpg.can(player, "heavy_swing") and is_equal_approx(Rpg.melee_stamina_mult(player), 0.9), "melee 2: the heavy, and swings 10%% cheaper (x%.2f)" % Rpg.melee_stamina_mult(player))
	check(not Rpg.silent_blade_ok(player, machete), "a machete's silent kill refused under melee 4")
	Rpg.set_level(player, "melee", 3)
	check(is_equal_approx(Rpg.parry_window_mult(player), Rpg.PARRY_WIDER), "melee 3: the parry window wider")
	check(not Rpg.silent_blade_ok(player, machete), "still no machete silent kill at 3")
	Rpg.set_level(player, "melee", 4)
	check(Rpg.silent_blade_ok(player, machete), "allowed at 4")
	Rpg.set_level(player, "melee", 0)
	player.inventory.take(&"combat_knife")
	check(Rpg.silent_blade_ok(player, machete), "and a knife carried does it at any level")
	await get_tree().process_frame


func _test_sources() -> void:
	print("XP sources")
	var med := Rpg.line_xp(player, "medical")
	player._log_care(player, &"pressure_bandage", &"", "done")
	check(Rpg.line_xp(player, "medical") > med, "a treatment done: medical XP (%.1f -> %.1f)" % [med, Rpg.line_xp(player, "medical")])
	var scav := Rpg.line_xp(player, "scavenging")
	var box := Node.new()
	add_child(box)
	player._loot_node = box
	player._loot_ready_at = 0.0
	check(player._loot_session_ok(box) and Rpg.line_xp(player, "scavenging") > scav, "a search finished: scavenging XP")
	box.queue_free()
	var melee := Rpg.line_xp(player, "melee")
	Rpg.on_parry(player)
	check(Rpg.line_xp(player, "melee") > melee, "a parry: melee XP")
	var fit := Rpg.line_xp(player, "fitness")
	player.set_meta(&"rpg_at", player.global_position - Vector3(20.0, 0.0, 0.0))
	player.want_sprint = true
	player.velocity = Vector3(5.0, 0.0, 0.0)
	Rpg.server_tick(player, 1.0, [])
	player.want_sprint = false
	player.velocity = Vector3.ZERO
	check(is_equal_approx(Rpg.line_xp(player, "fitness") - fit, 20.0 * Rpg.XP_SPRINT_PER_M * 0.8), "20 m run: fitness XP (%.2f)" % (Rpg.line_xp(player, "fitness") - fit))
	var fwd := -player.global_basis.z
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd * 12.0))
	await get_tree().physics_frame
	z.process_mode = Node.PROCESS_MODE_DISABLED
	var st := Rpg.line_xp(player, "stealth")
	Rpg.server_tick(player, 1.0, [z])
	check(Rpg.line_xp(player, "stealth") > st, "a second unseen with the dead about: stealth XP (%.2f)" % (Rpg.line_xp(player, "stealth") - st))
	var brain := ZombieAI.of(z)
	if brain:
		brain.mode = ZombieAI.Mode.CHASE
	st = Rpg.line_xp(player, "stealth")
	Rpg.server_tick(player, 1.0, [z])
	check(brain != null and Rpg.line_xp(player, "stealth") == st, "none while one of them is after him")
	z.queue_free()
	Rpg.set_level(player, "medical", 1)
	var before := Rpg.line_xp(player, "medical")
	check(Rpg.server_read(player, &"book_first_aid") == "" and Rpg.line_xp(player, "medical") > before, "reading the first aid manual teaches medical")
	check(Rpg.server_read(player, &"book_first_aid") != "", "once")
	check(Rpg.server_teach(player, player, "medical") != "", "teaching waits for the companions (a stub)")
	var b := Rpg.line_xp(player, "building")
	Rpg.xp(player, "building", 10.0)
	check(Rpg.line_xp(player, "building") > b and Rpg.build_time_mult(player) <= 1.0, "the building lane's API: XP, and the build time it reads (x%.2f)" % Rpg.build_time_mult(player))
	await get_tree().process_frame


func _test_crafting() -> void:
	print("Crafting (call 43, first tier)")
	check(Crafting.recipes().size() >= 6 and Crafting.recipes().has("smoked_meat"), "the recipes load (%d)" % Crafting.recipes().size())
	player.inventory.strip()
	player.inventory.take(&"cloth_rag", 2)
	check(Crafting.server_craft(player, "bandage") == "" and player._server_busy_until > Soldier._now() + 2.0, "bandages from rags: the hands busy for a while")
	await _wait_for(func() -> bool: return player.inventory.count_of(&"pressure_bandage") > 0, 8.0)
	check(player.inventory.count_of(&"pressure_bandage") == 1 and player.inventory.count_of(&"cloth_rag") == 0, "the rags used up, a bandage made")
	await _wait_for(func() -> bool: return Soldier._now() >= player._server_busy_until, 2.0)  # (a timer can land a frame before the busy time ends)
	player.inventory.take(&"raw_meat")
	check(Crafting.server_craft(player, "smoked_meat", true).begins_with("Needs cooking"), "smoking meat refused at cooking 1 (%s)" % Crafting.problem(player, "smoked_meat"))
	Rpg.set_level(player, "cooking", 2)
	check(Crafting.problem(player, "smoked_meat") == "Needs a fire", "at cooking 2, it needs a fire (%s)" % Crafting.problem(player, "smoked_meat"))
	level.server_spawn_dropped(&"campfire", 1, player.global_position + Vector3(1.0, 0.3, 0.0))
	await _wait_for(func() -> bool: return "fire" in Crafting.stations_of(player), 3.0)
	check("fire" in Crafting.stations_of(player), "a campfire kit dropped beside him is a fire")
	var cook := Rpg.line_xp(player, "cooking")
	var why := Crafting.server_craft(player, "smoked_meat", true)
	check(why == "" and player.inventory.count_of(&"smoked_meat") == 1 and player.inventory.count_of(&"raw_meat") == 0,
		"the raw meat smoked (%s; %d smoked, %d raw)" % [why, player.inventory.count_of(&"smoked_meat"), player.inventory.count_of(&"raw_meat")])
	check(Rpg.line_xp(player, "cooking") > cook, "and it levels cooking")
	player.inventory.take(&"dirty_water_bottle")
	why = Crafting.server_craft(player, "boiled_water", true)
	check(why == "", "dirty water boiled at the fire (%s)" % why)
	var clean := false
	for c: StringName in Inventory.CONTAINERS:
		for e: Dictionary in player.inventory.containers.get(c, []):
			if StringName(e.id) == &"dirty_water_bottle" and Needs.quality_of(ItemDB.get_item(&"dirty_water_bottle"), e.get("state", {})) == "clean":
				clean = true
	check(clean, "and it's clean now")
	player.inventory.take(&"wood_stick", 3)
	check(Crafting.problem(player, "campfire").begins_with("Needs a lighter"), "a campfire needs a lighter or matches (%s)" % Crafting.problem(player, "campfire"))
	check(Crafting.problem(player, "spear").begins_with("Needs building 1"), "a spear needs building 1 (%s)" % Crafting.problem(player, "spear"))
	for wi in level.items.get_children():
		if wi is WorldItem and (wi as WorldItem).item_id == &"campfire":
			wi.queue_free()
	await get_tree().process_frame


func _test_character_screen() -> void:
	print("The character screen")
	Rpg.server_sync(player)
	var screen := CharacterScreen.new()
	add_child(screen)
	screen.refresh()
	var text := screen.text()
	check(RpgLines.LINES.all(func(l: String) -> bool: return text.contains(l.capitalize())), "it names the twelve lines")
	check(text.contains("next:") and text.contains("Perks: Strong back") and text.contains("Background: Nurse") and text.contains("Flaws: Slow learner"),
		"with the next unlocks, the perks, the background and the flaws:\n%s" % text)
	screen.queue_free()


func _test_permadeath() -> void:
	print("Permadeath wipes it")
	var gen := int(Survival.survivor_of(player).get("generation", 1))
	player.server_end_spawn_protection()
	player.vitals.server_kill()
	await _wait_for(func() -> bool: return int(Survival.survivor_of(player).get("generation", 1)) > gen, 10.0)
	check(int(Survival.survivor_of(player).get("generation", 1)) == gen + 1, "a new survivor")
	check(Rpg.level(player, "cooking") == 0 and Rpg.level(player, "medical") == 0 and not Rpg.has_perk(player, "strong_back") and String(Rpg.data(player).background) == ""
		and not Rpg.has_flaw(player, "slow_learner"), "from nothing: no lines, no perks, a blank slate (the newcomer's own pick comes later)")
	check(int((Rpg.net().my.get("levels", {}) as Dictionary).get("cooking", -1)) == 0 and (Rpg.net().my.get("perks", ["x"]) as Array).is_empty(), "and his copy says so")
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING, 20.0)


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
	print("RPG TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
