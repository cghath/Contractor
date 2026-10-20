extends Node
## Headless checks for the ACE-style interaction menu (InteractionMenu) and the host
## requests behind it: what each kind of target offers, every action through its request
## (pick up, carry, drag, put down, give item, self actions; no revive), the signs a check
## shows, a human casualty
## carried and dragged, the key bindings, and the menu's cursor logic. Drives the API, not
## raw mouse input.
##   <voxel godot exe> --headless --path . res://tests/interaction_test.tscn
## Exits with the number of failures.

const SPOT := Vector3(0, 0.1, 20)

var failures := 0
var level: CompoundLevel
var player: Soldier
var alpha: Soldier    # friendly AI squadmate
var bravo: Soldier    # friendly AI squadmate (carries the human casualty)
var hostile: Soldier
var dummy: TargetDummy


func _ready() -> void:
	GameState.zone_id = "test_interaction" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false  # we place our own squadmates
	GameState.delete_save()
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("INTERACTION TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	_place_player()
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1"]:
		player.inventory.take(id)
	player.inventory.take(&"mag_556", 2)
	alpha = _spawn_ai("Alpha", &"friendly", SPOT + Vector3(0, 0, -1.5), ["plate_carrier", "m4a1"])
	bravo = _spawn_ai("Bravo", &"friendly", SPOT + Vector3(2.0, 0, 0), ["plate_carrier", "assault_pack", "m4a1"])
	hostile = _spawn_ai("Hostile", &"hostile", SPOT + Vector3(-2.0, 0, -1.0), ["m4a1"])
	dummy = level.get_node(^"Dummies/LightDummy")
	dummy.respawn_seconds = 999.0  # stays down while we look at it
	await _frames(10)
	_test_key_bindings()
	await _test_actions_for()
	await _test_pick_up()
	await _test_signs()
	await _test_carry_and_drag()
	await _test_human_casualty()
	await _test_give_item()
	await _test_self_actions()
	await _test_menu()
	await _test_body_points()
	await _test_declutter()
	await _test_slid_body()
	await _test_downed_enemy()  # last: the hostile ends up a prisoner
	await _test_loot_window()
	await _test_grenade_equip()
	await _test_enemy_tags()
	await _test_tutorial()
	GameState.delete_save()
	print("INTERACTION TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_key_bindings() -> void:
	print("Key bindings")
	# The keyboard's bindings (wave 7's controller adds a pad button to each action too).
	var interact := InputMap.action_get_events(&"interact").filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	check(interact.size() == 1 and interact[0] is InputEventKey and interact[0].physical_keycode == KEY_CTRL
		and interact[0].location == KEY_LOCATION_LEFT, "interact is Left Ctrl")
	check(not _bound(&"interact", KEY_E), "E no longer interacts")
	var self_events := InputMap.action_get_events(&"self_interact").filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	check(self_events.size() == 1 and self_events[0].physical_keycode == KEY_ALT and self_events[0].location == KEY_LOCATION_LEFT
		and self_events[0].ctrl_pressed, "self_interact is Left Ctrl + Left Alt")
	check(not _bound(&"crouch", KEY_CTRL), "Ctrl no longer crouches (it would while interacting)")
	_key(KEY_CTRL, KEY_LOCATION_LEFT, true, true, false)
	check(Input.is_action_pressed(&"interact") and not Input.is_action_pressed(&"self_interact"), "Left Ctrl: interact only")
	_key(KEY_ALT, KEY_LOCATION_LEFT, true, true, true)
	check(Input.is_action_pressed(&"interact") and Input.is_action_pressed(&"self_interact"), "then Left Alt: self-interact")
	_key(KEY_CTRL, KEY_LOCATION_LEFT, false, false, true)
	_key(KEY_ALT, KEY_LOCATION_LEFT, false, false, false)
	check(not Input.is_action_pressed(&"interact") and not Input.is_action_pressed(&"self_interact"), "letting go releases both")
	_key(KEY_ALT, KEY_LOCATION_LEFT, true, false, true)
	check(not Input.is_action_pressed(&"self_interact"), "Left Alt alone does nothing")
	_key(KEY_ALT, KEY_LOCATION_LEFT, false, false, false)
	_key(KEY_CTRL, KEY_LOCATION_RIGHT, true, true, false)
	check(not Input.is_action_pressed(&"interact"), "Right Ctrl doesn't interact")
	_key(KEY_CTRL, KEY_LOCATION_RIGHT, false, false, false)


func _test_actions_for() -> void:
	print("What each target offers (actions_for)")
	var item := await _spawn_item(&"ifak", SPOT + Vector3(0, 0.3, -1.0))
	check(_ids(player, item) == [&"pick_up"], "world item: Pick up (%s)" % [_ids(player, item)])
	check(_ids(player, alpha) == [&"give_item"], "standing squadmate: Give item (%s)" % [_ids(player, alpha)])
	var give := InteractionMenu.actions_for(player, alpha)[0]
	check(give.items.size() == 1 and give.items[0].label.begins_with("5.56"), "Give item lists your stowed items (%s)" % [give.items.map(func(e: Dictionary) -> String: return e.label)])
	check(_ids(player, hostile).is_empty(), "a standing enemy offers nothing")
	check(_ids(player, dummy).is_empty(), "a standing dummy offers nothing")
	check(_ids(player, null).is_empty() and InteractionMenu.target_kind(player, null) == &"", "nothing offers nothing")

	alpha.vitals.server_damage(70.0)  # 42% lost: unconscious, not in arrest
	hostile.vitals.server_damage(500.0)
	dummy.vitals.server_damage(500.0)  # cardiac arrest: only a line and fluids help until the heart restarts
	await _frames(2)
	check(_ids(player, alpha) == [&"treat", &"carry", &"drag", &"check_condition"], "downed squadmate: Treat, Carry, Drag, Check condition; no Revive (%s)" % [_ids(player, alpha)])
	var treat := _action(player, alpha, &"treat")
	check(treat.items.size() == 4 and treat.items[0].label == "NPA Airway, head" and treat.items[0].disabled.contains("NPA")
		and treat.items[1].label == "IO Kit (Sternal), sternum" and treat.items[2].label == "Hypothermia Blanket, torso"
		and treat.items[3].label.begins_with("Morphine"),
		"Treat lists what they need, greyed out without the item (%s: %s)" % [treat.items.map(func(e: Dictionary) -> String: return e.label), treat.items.map(func(e: Dictionary) -> String: return e.disabled)])
	player.inventory.take(&"trauma_kit")
	check(not _ids(player, alpha).has(&"revive"), "a trauma kit adds no Revive either (%s)" % [_ids(player, alpha)])
	check(_action(player, alpha, &"treat").items[0].disabled == "", "its NPA can go in")
	player.inventory.take(&"hvt_case")
	check(_action(player, alpha, &"carry").disabled.contains("hands") and not _ids(player, alpha).has(&"drag"),
		"can't carry with your hands full; Drag, greyed for the same reason, is left out (%s)" % [_ids(player, alpha)])
	player.inventory.release_hands()
	check(_ids(player, dummy) == [&"treat", &"check_condition"]
		and _action(player, dummy, &"treat").items.all(func(e: Dictionary) -> bool: return e.item in [WoundModel.IO_KIT, WoundModel.BLANKET] or WoundModel.IV_GAUGES.has(e.item)),
		"downed dummy in cardiac arrest: Check condition, and Treat offers only a line and a blanket (%s)" % [_ids(player, dummy)])
	player.inventory.take(&"iv_18")
	player.inventory.take(&"io_kit")
	var lines: Array = _action(player, dummy, &"treat").items.map(func(e: Dictionary) -> String: return e.label)
	check(lines == ["IO Kit (Sternal), sternum", "IV Catheter (18G), left forearm", "Hypothermia Blanket, torso"],
		"with an IO kit and an IV in the kit, one entry each, IO first in arrest (%s)" % [lines])
	# Captain, 2026-10-14 ("cant loot" a downed hostile): Loot and Loot all first, then Carry,
	# Drag and Zip-cuff (greyed: no cuffs), no Treat.
	check(_ids(player, hostile) == [&"loot", &"loot_all", &"carry", &"drag", &"cuff", &"check_condition"],
		"downed enemy: Loot, Loot all, Carry, Drag, Zip-cuff, Check condition (%s)" % [_ids(player, hostile)])
	check(_action(player, hostile, &"cuff").disabled == "You have no zip cuffs", "Zip-cuff greyed without cuffs (%s)" % _action(player, hostile, &"cuff").disabled)
	var report := InteractionMenu.perform(player, _action(player, alpha, &"check_condition"))
	check(report.begins_with(alpha.display_name() + ": " + alpha.vitals.condition_text()) and report.contains("\n"), "Check condition reads condition and wounds (%s)" % report.replace("\n", " | "))
	hostile.vitals.server_reset_health()
	dummy.vitals.server_reset_health()

	check(_ids(player, player) == [&"check_wounds", &"drop_held"], "self, unhurt: Check wounds, Drop held item (%s)" % [_ids(player, player)])
	check(_action(player, player, &"drop_held").label == "Drop M4A1 Carbine", "Drop names the active weapon (%s)" % _action(player, player, &"drop_held").label)


func _test_pick_up() -> void:
	print("Pick up")
	var item := await _spawn_item(&"ifak", player.global_position + Vector3(0, 0.5, -0.8))
	var before := player.inventory.count_of(&"ifak")
	InteractionMenu.perform(player, InteractionMenu.actions_for(player, item)[0])
	await _frames(2)
	check(player.inventory.count_of(&"ifak") == before + 1, "Pick up takes the item")
	check(not is_instance_valid(item) or item.is_queued_for_deletion(), "and it's gone from the world")
	await _test_pick_up_face_down()


## Captain's playtest: a steel plate that fell face first couldn't be picked up (it sank into
## the ground, or through a crate). Plates and helmets dropped face first, on the ground and
## on a crate, get an action point and Pick up takes them.
func _test_pick_up_face_down() -> void:
	print("Pick up armor that landed face first")
	var kit := player.inventory.net_state.duplicate(true)  # put back afterwards
	var owned := func(id: StringName) -> int:
		return player.inventory.count_of(id) + player.inventory.slots.values().count(id)
	for case: Array in [[&"plate_steel_l3", SPOT, Vector3(0, 2.0, -1.6)], [&"helmet", SPOT, Vector3(0.6, 2.0, -1.6)],
			[&"plate_steel_l3", Vector3(-12.5, 0.1, -9.0), Vector3(-0.25, 3.0, -1.5)]]:
		player.global_position = case[1]
		player.velocity = Vector3.ZERO
		var item := await _spawn_item(case[0], case[1] + case[2])
		item.rotation_degrees = Vector3(180, 30, 0) if case[0] == &"helmet" else Vector3(-90, 30, 0)
		for i in 120:
			await get_tree().physics_frame
		player.head.look_at(item.global_position)
		await _frames(1)
		var where := "on a crate" if case[1] != SPOT else "on the ground"
		var face_down := item.global_basis.y.y < -0.9 if case[0] == &"helmet" else item.global_basis.z.y > 0.9
		var point := InteractionMenu.collect_points(player, player.camera).filter(func(p: Dictionary) -> bool: return p.target == item)
		check(face_down and not point.is_empty(), "%s lying face down %s gets an action point (at y %.3f)" % [case[0], where, item.global_position.y])
		var before: int = owned.call(case[0])
		if not point.is_empty():
			InteractionMenu.perform(player, point[0].actions[0])
		await _frames(2)
		check(owned.call(case[0]) == before + 1, "...and Pick up takes it")
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			item.queue_free()
	player.inventory.net_state = kit
	_place_player()


## Check condition and Check wounds show plain signs, never numbers (SpO2 and blood stay hidden).
func _test_signs() -> void:
	print("Signs on Check condition and Check wounds")
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	var report := InteractionMenu.perform(player, _action(player, alpha, &"check_condition"))
	check(report.contains("Unresponsive"), "an unconscious squadmate is unresponsive (%s)" % report.replace("\n", " | "))
	alpha.vitals._model.spo2 = 80.0
	alpha.vitals.server_advance(0.1)
	report = InteractionMenu.condition_report(alpha)
	check(report.contains("Breathing laboured") and report.contains("Blue lips") and not report.contains("%"),
		"low SpO2 shows as laboured breathing and blue lips, no number (%s)" % report.replace("\n", " | "))
	player.inventory.take(&"pulse_oximeter")
	report = InteractionMenu.condition_report(alpha, player)
	check(report.contains("Pulse oximeter: SpO2 8"), "with a pulse oximeter the number shows (%s)" % report.replace("\n", " | "))
	player.inventory.remove_one(&"pulse_oximeter")
	player.vitals._model.pain_wounds = 0.6
	player.vitals.server_apply_treatment(&"morphine", Vitals.TORSO)
	player.vitals.server_advance(WoundModel.MORPHINE_ABSORB_S)
	var own := InteractionMenu.perform(player, _action(player, player, &"check_wounds"))
	check(own.contains("Drowsy (morphine)") and not own.contains("Pinpoint"), "Check wounds on yourself: drowsy from the morphine (%s)" % own.replace("\n", " | "))
	report = InteractionMenu.condition_report(player)
	check(report.contains("Pinpoint pupils (morphine)") and not report.contains("Unresponsive"), "someone checking you sees pinpoint pupils (%s)" % report.replace("\n", " | "))
	alpha.vitals.server_reset_health()
	player.vitals.server_reset_health()
	await _frames(2)
	check(alpha.vitals.is_up() and not InteractionMenu.condition_report(alpha).contains("Unresponsive"), "reset for the next checks")


func _test_carry_and_drag() -> void:
	print("Carry, drag and put down")
	alpha.vitals.server_damage(500.0)
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	InteractionMenu.perform(player, _action(player, alpha, &"carry"))
	check(player.carrying == alpha and alpha.carried_by == player and player.carry_mode == Soldier.CARRY, "Carry picks the body up")
	await _frames(2)  # (its ragdoll goes: the body is where it lay)
	var lying := alpha.global_position
	await _frames(3)
	check(player.carry_speed_mult() == 0.0 and _flat(alpha.global_position, lying) < 0.05 and not player.carry_holds(),
		"lifting it: you stand still and the body stays on the ground until it's up (speed %.2f, moved %.2f m, holds %s)"
			% [player.carry_speed_mult(), _flat(alpha.global_position, lying), player.carry_holds()])
	_end_carry_phase(player)
	check(is_equal_approx(player.carry_speed_mult(), Soldier.CARRY_SPEED_MULT) and is_equal_approx(Soldier.CARRY_SPEED_MULT, 0.55), "carrying slows you to 0.55")
	check(alpha.collision_layer == 0 and alpha.care_by == player, "the body stops colliding, and squadmates leave it to you")
	await _frames(3)
	check(alpha.global_position.distance_to(player.carry_transform().origin) < 0.05, "it rides on your shoulder")
	check(_ids(player, player)[0] == &"put_down", "self-interaction offers Put down, first (%s)" % [_ids(player, player)])
	var on_carried := _ids(player, alpha)
	check(on_carried[0] == &"put_down" and on_carried.has(&"drag") and _action(player, alpha, &"drag").disabled == "" and not on_carried.has(&"carry"),
		"the body you carry: Put down first, Drag to switch, no Carry (%s)" % [on_carried])
	hostile.vitals.server_damage(500.0)
	await _frames(2)
	check(_ids(player, hostile) == [&"loot", &"loot_all", &"carry", &"cuff", &"check_condition"] and _action(player, hostile, &"carry").disabled == "You're already moving someone",
		"another body: Carry greyed (can't pick up a second), no Drag, no Put down (%s)" % [_ids(player, hostile)])
	hostile.vitals.server_reset_health()

	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.carrying == alpha and player.carry_mode == Soldier.DRAG, "Drag on the body you carry switches to dragging")
	check(_ids(player, alpha).has(&"carry") and _action(player, alpha, &"carry").disabled == "" and not _ids(player, alpha).has(&"drag"),
		"dragging it: Carry to switch back, no Drag (%s)" % [_ids(player, alpha)])
	_end_carry_phase(player)  # took hold of the handle
	check(is_equal_approx(player.carry_speed_mult(), Soldier.DRAG_SPEED_MULT) and Soldier.DRAG_SPEED_MULT < Soldier.CARRY_SPEED_MULT, "dragging is slower (0.35)")
	player.global_position += Vector3(0, 0, -2.0)
	await _frames(3)
	var local := player.global_transform.affine_inverse() * alpha.global_position
	check(local.z > 0.8 and absf(local.y) < 0.2, "the body slides along behind you (%s)" % local)
	check(is_equal_approx(player.view_yaw(), PI), "dragging, the view faces the casualty behind the body")
	check(_ids(player, alpha).has(&"put_down") and _action(player, alpha, &"put_down").get("label") == "Release",
		"looking at the body you drag offers Release (%s)" % [_ids(player, alpha)])
	player.head.rotation.x = -0.6  # looking down at the casualty you're dragging
	await _frames(2)
	var dragged := InteractionMenu.collect_points(player, player.camera).filter(func(p: Dictionary) -> bool: return p.target == alpha)
	player.head.rotation.x = 0.0
	check(dragged.size() == 1 and dragged[0].get("region", &"") == &"" and dragged[0].actions[0].id == &"put_down" and dragged[0].actions[0].label == "Release",
		"Left Ctrl on the body you drag: one point, Release first (%s)" % [dragged.map(func(p: Dictionary) -> Array: return p.actions.map(func(a: Dictionary) -> String: return a.label))])
	check(InteractionMenu.general_actions(player, player).any(func(a: Dictionary) -> bool: return a.id == &"put_down" and a.label == "Release"),
		"and on yourself (Left Ctrl + Left Alt), Release at the waist")
	InteractionMenu.perform(player, _action(player, player, &"put_down"))
	check(player.carrying == null and player.carry_mode == &"" and is_equal_approx(player.carry_speed_mult(), 1.0), "Let go releases it and your speed")
	check(alpha.carried_by == null and alpha.collision_layer == Soldier.BODY_LAYER and alpha.care_by == null, "the body collides again")
	check(alpha.global_position.distance_to(player.global_position) > 0.8, "and stays where you dragged it")
	# G lets go too, dragging or carrying (your hands are full: nothing to throw).
	for mode: StringName in [Soldier.DRAG, Soldier.CARRY]:
		_place_player()
		alpha.global_position = SPOT + Vector3(0, 0, -1.2)
		await _frames(2)
		if mode == Soldier.DRAG:
			player._server_drag_body.rpc_id(1, alpha.get_path())
		else:
			player._server_carry_body.rpc_id(1, alpha.get_path())
		var held := player.carry_mode == mode
		await _frames(2)  # (its ragdoll goes as it's taken hold of)
		_end_carry_phase(player)
		var g := InputEventAction.new()
		g.action = &"grenade"
		g.pressed = true
		player.player_input._unhandled_input(g)
		await _frames(2)
		if mode == Soldier.CARRY:
			check(player.carrying == alpha and player.carry_speed_mult() == 0.0 and absf(_flat(alpha.global_position, player.global_position) - 0.8) < 0.1,
				"putting a carried body down: you kneel and lower it (standing still), where it'll lie, in front (carrying %s, speed %.2f, %.2f m from you)"
					% [player.carrying, player.carry_speed_mult(), _flat(alpha.global_position, player.global_position)])
			_end_carry_phase(player)
		check(held and player.carrying == null and player.carry_mode == &"" and alpha.carried_by == null,
			"G lets go of a body you're %s" % ("dragging" if mode == Soldier.DRAG else "carrying"))

	_place_player()
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.carry_mode == Soldier.DRAG, "Drag takes hold of a body directly")
	player.set_physics_process(true)  # the host keeps a player's casualty with them
	alpha.vitals.server_reset_health()
	for i in 3:  # physics frames: the host's update runs in the player's physics step
		await get_tree().physics_frame
	player.set_physics_process(false)
	_place_player()
	check(player.carrying == null and player.carry_mode == &"", "a body that gets up is let go (host update for players)")

	alpha.vitals.server_damage(500.0)
	alpha.global_position = SPOT + Vector3(2.0, 0, -1.0)
	await _frames(2)
	check(bravo.server_pick_up_body(alpha) and bravo.carry_mode == Soldier.CARRY, "AI casualty care still picks bodies up (server_pick_up_body)")
	bravo.release_carried()
	check(alpha.carried_by == null and bravo.carry_mode == &"", "and puts them down")
	alpha.vitals.server_reset_health()


func _test_human_casualty() -> void:
	print("Human casualty")
	player.vitals.server_damage(500.0)
	bravo.global_position = player.global_position + Vector3(1.5, 0, 0)
	await _frames(2)
	check(player.vitals.downed, "player is down")
	check(InteractionMenu.actions_for(bravo, player).any(func(a: Dictionary) -> bool: return a.id == &"carry"), "a squadmate can carry a downed player")
	bravo._server_carry_body.rpc_id(1, player.get_path())
	check(bravo.carrying == player and player.carried_by == bravo and player.collision_layer == 0, "carried by Bravo")
	_end_carry_phase(bravo)
	await _frames(3)
	var pos: Variant = player.carried_by_pos
	check(pos is Vector3 and (pos as Vector3).distance_to(bravo.carry_transform().origin) < 0.05, "the host sends the player where they are carried")
	player._physics_process(1.0 / 60.0)
	check(player.global_position.distance_to(bravo.carry_transform().origin) < 0.05, "the player's body follows it")
	bravo._server_drag_body.rpc_id(1, player.get_path())
	_end_carry_phase(bravo)
	await _frames(3)
	pos = player.carried_by_pos
	check(bravo.carry_mode == Soldier.DRAG and pos is Vector3 and (pos as Vector3).distance_to(bravo.carry_transform().origin) < 0.05, "and dragged")
	bravo._server_release_body.rpc_id(1)
	check(player.carried_by == null and bravo.carrying == null and player.collision_layer == Soldier.BODY_LAYER, "and put down")
	player.vitals.server_reset_health()
	player.carried_by_pos = null
	_place_player()


func _test_give_item() -> void:
	print("Give item")
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	var hud: Hud = player._hud
	var before := alpha.inventory.count_of(&"mag_556")
	var mine := player.inventory.count_of(&"mag_556")
	var mag := _give_entry(alpha, &"mag_556")
	check(not mag.is_empty(), "a magazine is in the Give item list")
	InteractionMenu.perform(player, mag)
	check(alpha.inventory.count_of(&"mag_556") == before + 1 and player.inventory.count_of(&"mag_556") == mine - 1, "Alpha got one magazine (%d)" % alpha.inventory.count_of(&"mag_556"))
	check(hud._message.text.begins_with("Gave"), "you're told (%s)" % hud._message.text)

	bravo.inventory.strip()  # nothing but pockets
	bravo.global_position = SPOT + Vector3(1.5, 0, 0)
	player.inventory.take(&"trauma_kit")
	var kits := player.inventory.count_of(&"trauma_kit")
	await _frames(2)
	var kit := _give_entry(bravo, &"trauma_kit")
	InteractionMenu.perform(player, kit)
	check(bravo.inventory.count_of(&"trauma_kit") == 0 and player.inventory.count_of(&"trauma_kit") == kits, "a trauma kit doesn't fit in Bravo's pockets: you keep it")
	check(hud._message.text.contains("no room"), "and you're told why (%s)" % hud._message.text)
	bravo.global_position = SPOT + Vector3(8.0, 0, 0)
	await _frames(2)
	mag = _give_entry(bravo, &"mag_556")
	InteractionMenu.perform(player, mag)
	check(bravo.inventory.count_of(&"mag_556") == 0, "nothing changes hands out of reach")


func _test_self_actions() -> void:
	print("Self-interaction")
	player.vitals.server_reset_health()  # earlier checks left the player down
	check(InteractionMenu.perform(player, _action(player, player, &"check_wounds")) == "No wounds found", "Check wounds: none")
	player.vitals.server_damage(30.0)
	check(InteractionMenu.perform(player, _action(player, player, &"check_wounds")) != "No wounds found", "Check wounds notices you're hurt")
	player.vitals.server_reset_health()
	# A pistol round through the outside of the left thigh (rest pose): a plain muscle wound.
	player.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.PISTOL, "position": player.global_transform * Vector3(-0.12, 0.7, -0.1),
		"direction": player.global_basis * Vector3.BACK})
	var report := InteractionMenu.perform(player, _action(player, player, &"check_wounds"))
	check(report.begins_with("Left thigh: muscle wound, bleeding"), "Check wounds: %s" % report.replace("\n", " | "))
	var treat := _action(player, player, &"treat")
	check(treat.label == "Treat yourself" and treat.items[0].label == "Pressure Bandage, left thigh" and treat.items[0].disabled == "",
		"Treat yourself lists the bandage, from your trauma kit (%s)" % [treat.items.map(func(e: Dictionary) -> String: return e.label)])
	player._server_busy_until = 0.0
	InteractionMenu.perform(player, treat.items[0])
	check(player.vitals.is_healing() and absf(player._server_busy_until - Soldier._now() - 5.0) < 0.1, "and puts it on (5 s)")
	await _seconds(5.3)
	report = InteractionMenu.perform(player, _action(player, player, &"check_wounds"))
	check(report.begins_with("Left thigh: muscle wound, bandaged"), "Check wounds shows what's been done: %s" % report.replace("\n", " | "))
	player.inventory.take(&"hvt_case")
	var drop := _action(player, player, &"drop_held")
	check(drop.label == "Drop HVT Hard Case", "Drop names what's in your hands (%s)" % drop.label)
	InteractionMenu.perform(player, drop)
	await _frames(2)
	check(player.inventory.hands == &"" and player.inventory.slots[&"primary"] == &"m4a1", "Drop puts down the case and keeps the rifle")
	check(_items_near(player.global_position, 3.0).has(&"hvt_case"), "the case is on the ground")


func _test_menu() -> void:
	print("Menu: keys, cursor and release")
	var own := player.player_input.interaction
	check(own != null and own.is_inside_tree() and not own.is_open(), "the local player has an interaction menu on the HUD")
	var menu := InteractionMenu.new(player)
	var screen := SubViewport.new()  # a real screen size (headless windows are 64 px)
	screen.size = Vector2i(1280, 720)
	add_child(screen)
	screen.add_child(menu)
	var centre := menu.get_viewport_rect().size * 0.5
	check(not menu.update_keys(true, false, 0.05) and menu.mode == InteractionMenu.Mode.CLOSED, "a quick Ctrl shows nothing yet")
	menu.update_keys(true, true, 0.05)
	check(menu.mode == InteractionMenu.Mode.SELF, "Ctrl then Alt opens self-interaction")
	menu.update_keys(true, false, 0.5)
	check(menu.mode == InteractionMenu.Mode.SELF, "and stays on it, never the object menu, while Ctrl is held")
	var rects := menu.entry_rects()
	check(rects.size() == InteractionMenu.grouped(InteractionMenu.general_actions(player, player)).size(), "your general actions are around the waist point")
	menu.set_cursor(rects[0].get_center())
	check(menu.highlighted().get("id") == &"check_wounds", "the cursor highlights Check wounds")
	check(menu.update_keys(false, false, 0.05) and menu.chosen.get("id") == &"check_wounds" and not menu.is_open(), "letting go picks it and closes")

	menu.update_keys(true, false, 0.1)
	menu.update_keys(true, false, 0.1)
	check(menu.mode == InteractionMenu.Mode.OBJECT, "holding Ctrl opens the object menu")
	_place_player()
	player.head.rotation.x = -0.6  # looking down at the floor in front
	var item := await _spawn_item(&"smoke_grenade", player.global_position + Vector3(0, 0.3, -1.4))
	await _frames(20)
	var found := InteractionMenu.collect_points(player, player.camera)
	check(found.any(func(p: Dictionary) -> bool: return p.target == item), "the item at your feet gets an action point (%d points)" % found.size())
	var far := await _spawn_item(&"smoke_grenade", player.global_position + Vector3(0, 0.3, 6.0))
	await _frames(2)
	check(not InteractionMenu.collect_points(player, player.camera).any(func(p: Dictionary) -> bool: return p.target == far), "one behind you doesn't")
	var points: Array[Dictionary] = [
		{"target": item, "screen": centre, "actions": InteractionMenu.actions_for(player, item)},
		{"target": alpha, "screen": centre + Vector2(-300, 0), "actions": InteractionMenu.actions_for(player, alpha)},
	]
	menu.set_points(points)
	check(menu.entry_rects().size() == 1, "the point under the cursor opens its menu")
	menu.move_cursor(menu.entry_rects()[0].get_center() - menu.cursor)
	check(menu.highlighted().get("id") == &"pick_up", "moving the mouse moves the cursor onto Pick up")
	await _frames(2)  # draws with a point open
	menu.set_cursor(Vector2(4, 4))
	check(menu.highlighted().is_empty(), "nothing is highlighted over empty screen")
	var held := player.inventory.count_of(&"smoke_grenade")
	check(menu.update_keys(false, false, 0.05) and menu.chosen.is_empty(), "letting go over nothing chooses nothing")
	check(InteractionMenu.perform(player, menu.chosen) == "", "and performing it does nothing")
	await _frames(2)
	check(is_instance_valid(item) and not item.is_queued_for_deletion() and player.inventory.count_of(&"smoke_grenade") == held, "the item is still there")

	menu.update_keys(true, false, 0.5)
	menu.set_points(points)
	menu.set_cursor(centre + Vector2(-300, 0))
	var give_rect := menu.entry_rects()[0]
	menu.set_cursor(give_rect.get_center())
	check(menu.highlighted().get("id") == &"give_item" and not menu.submenu_rects(0).is_empty(), "the squadmate's Give item opens its submenu")
	check(menu.release().is_empty(), "letting go on a submenu itself does nothing")
	menu.update_keys(true, false, 0.5)
	menu.set_points(points)
	menu.set_cursor(centre + Vector2(-300, 0))
	menu.set_cursor(menu.entry_rects()[0].get_center())
	menu.set_cursor(menu.submenu_rects(0)[0].get_center())
	await _frames(2)  # draws with a submenu open
	var picked := menu.highlighted()
	check(picked.get("container") != null and picked.get("target") == alpha, "a submenu entry is the item to give (%s)" % picked.get("label"))
	menu.update_keys(false, false, 0.05)
	screen.queue_free()


## Body interaction points (ACE3's medical rig): a point per region with that region's
## treatments, a general point at the waist, the same layout on yourself; IVs in the legs too.
func _test_body_points() -> void:
	print("Body interaction points")
	check(InteractionMenu.region_of(&"thigh_l") == &"leg_l" and InteractionMenu.region_of(&"forearm_r") == &"arm_r"
		and InteractionMenu.region_of(&"neck") == &"head" and InteractionMenu.region_of(Vitals.TORSO) == &"chest", "body parts map to regions")
	alpha.vitals.server_reset_health()
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	alpha.vitals.server_damage(70.0)  # out cold, 42% lost: a line, a blanket, the airway
	alpha.vitals._model._add_wound(&"thigh_l", "arterial", 1.2, &"femoral_l")
	alpha.vitals._model.update_state(0.0)
	alpha.vitals._after_change(true)
	await _frames(2)
	var general := InteractionMenu.general_actions(player, alpha)
	check(not general.any(func(a: Dictionary) -> bool: return a.id == &"treat") and general.any(func(a: Dictionary) -> bool: return a.id == &"carry")
		and general.any(func(a: Dictionary) -> bool: return a.id == &"check_condition"), "the waist point: carry, drag, check condition; no Treat")
	var labels := func(region: StringName) -> Array: return InteractionMenu.region_actions(player, alpha, region).map(func(a: Dictionary) -> String: return a.label)
	var leg: Array = labels.call(&"leg_l")
	check(leg[0] == "Check left leg" and leg.has("Tourniquet, left thigh"), "the left leg: check it, and its tourniquet (%s)" % [leg])
	check(not (labels.call(&"leg_r") as Array).any(func(l: String) -> bool: return l.begins_with("Tourniquet")), "not on the right leg")
	check((labels.call(&"head") as Array).has("NPA Airway, head"), "the airway on the head")
	player.inventory.take(&"iv_18")
	player.inventory.take(&"io_kit")
	check((labels.call(&"arm_l") as Array).has("IV Catheter (18G), left forearm") and (labels.call(&"leg_r") as Array).has("IV Catheter (18G), right shin")
		and (labels.call(&"chest") as Array).has("IO Kit (Sternal), sternum"), "a line: an IV on each arm and lower leg, an IO on the chest")
	alpha.vitals.server_apply_treatment(&"tourniquet", &"thigh_l")
	check(not (labels.call(&"leg_l") as Array).any(func(l: String) -> bool: return l.begins_with("IV")), "no IV below a tourniquet")
	for i in 20:  # in shock an IV can miss: try again, like a medic
		if alpha.vitals.access().is_empty():
			alpha.vitals.server_apply_treatment(&"iv_18", &"shin_r")
	check(alpha.vitals.access().get("part") == &"shin_r", "an IV in the leg (%s)" % [alpha.vitals.access()])
	var report := InteractionMenu.part_report(alpha, &"leg_l", player)
	check(report.contains("Left thigh: arterial bleed") and report.contains("Tourniquet on the left thigh"), "checking the leg reads its wounds (%s)" % report.replace("\n", " | "))
	check(InteractionMenu.part_report(alpha, &"leg_r", player).contains("IV 18G in the right shin"), "and the line in it")
	_place_player()
	player.head.rotation.x = -0.5
	await _frames(3)
	var points := InteractionMenu.collect_points(player, player.camera).filter(func(p: Dictionary) -> bool: return p.target == alpha)
	var regions := points.map(func(p: Dictionary) -> StringName: return p.region)
	check(regions.has(InteractionMenu.WAIST) and regions.has(&"leg_l") and regions.has(&"head") and regions.size() >= 5,
		"a downed squadmate in front: a waist point and the body's points (%s)" % [regions])
	check(not InteractionMenu.collect_points(player, player.camera).any(func(p: Dictionary) -> bool: return p.target == hostile and p.get("region", &"") != &""),
		"an enemy keeps a single point")
	var menu := InteractionMenu.new(player)
	var screen := SubViewport.new()
	screen.size = Vector2i(1280, 720)
	add_child(screen)
	screen.add_child(menu)
	menu.update_keys(true, true, 0.05)
	var own := menu.points.map(func(p: Dictionary) -> StringName: return p.region)
	check(menu.mode == InteractionMenu.Mode.SELF and own.size() == 7 and own.has(InteractionMenu.WAIST) and own.has(&"arm_r"),
		"self-interaction: the same layout on yourself (%s)" % [own])
	check(menu.highlighted().is_empty() and menu.entry_rects().size() == InteractionMenu.grouped(InteractionMenu.general_actions(player, player)).size(), "starting on the waist point")
	var arm: Vector2 = menu.points.filter(func(p: Dictionary) -> bool: return p.region == &"arm_l")[0].screen
	menu.set_cursor(arm)
	check(menu.entry_rects().size() >= 1 and InteractionMenu.region_actions(player, player, &"arm_l")[0].label == "Check left arm", "moving onto your left arm opens its point")
	menu.update_keys(false, false, 0.05)
	screen.queue_free()
	player.inventory.remove_one(&"iv_18")
	player.inventory.remove_one(&"io_kit")
	alpha.vitals.server_reset_health()


## The menu decluttered (Captain, P0164 queue 8): rarely used entries share one More submenu
## once two or more do (a submenu of one is clutter), entries with their own submenu stay on
## the ring, a ring never holds more than RING_MAX (the rest go into More), a picked entry
## inside More works like any other; on the dead Loot comes first, and Loot all is left out
## once there's nothing left (greyed for the same reason as Loot).
func _test_declutter() -> void:
	print("Declutter: More, a full ring, the dead")
	var entry := func(id: String, group: String) -> Dictionary:
		var e := {"id": StringName(id), "label": id.capitalize(), "show": &"condition", "target": alpha, "disabled": ""}
		if group != "":
			e["group"] = group
		return e
	var labels := func(ring: Array) -> Array: return ring.map(func(a: Dictionary) -> String: return a.label)
	var lone: Array[Dictionary] = [entry.call("carry", ""), entry.call("drag", ""), entry.call("check", InteractionMenu.MORE)]
	check(labels.call(InteractionMenu.grouped(lone)) == ["Carry", "Drag", "Check"], "one rare entry stays on the ring (%s)" % [labels.call(InteractionMenu.grouped(lone))])
	var cargo: Dictionary = entry.call("cargo", InteractionMenu.MORE)
	cargo["items"] = [entry.call("take", "")]
	var two: Array[Dictionary] = [entry.call("carry", ""), entry.call("search", InteractionMenu.MORE), cargo, entry.call("drag", ""), entry.call("check", InteractionMenu.MORE)]
	var ring := InteractionMenu.grouped(two)
	check(labels.call(ring) == ["Carry", "More", "Cargo", "Drag"] and ring[1].id == &"group" and labels.call(ring[1].get("items", [])) == ["Search", "Check"],
		"two rare entries share More, where the first was; one with its own submenu stays on the ring (%s; %s)" % [labels.call(ring), labels.call(ring[1].get("items", []))])
	var named: Array[Dictionary] = [entry.call("pull a", "Pull out"), entry.call("pull b", "Pull out")]
	named[0]["group_label"] = "Alpha"
	check(labels.call(InteractionMenu.grouped(named)) == ["Pull out"] and labels.call(InteractionMenu.grouped(named)[0].items) == ["Alpha", "Pull B"],
		"a group's entries use their group_label inside it")
	var many: Array[Dictionary] = []
	for i in InteractionMenu.RING_MAX + 3:
		many.append(entry.call("entry %d" % i, ""))
	many.insert(2, cargo)
	var full := InteractionMenu.grouped(many)
	check(full.size() == InteractionMenu.RING_MAX and labels.call(full) == ["Entry 0", "Entry 1", "Cargo", "Entry 2", "Entry 3", "More"]
		and labels.call(full.back().items) == ["Entry 4", "Entry 5", "Entry 6", "Entry 7", "Entry 8"],
		"%d entries: the ring keeps %d, the last plain ones go into More (%s; %s)" % [many.size(), InteractionMenu.RING_MAX, labels.call(full), labels.call(full.back().get("items", []))])

	var menu := InteractionMenu.new(player)
	var screen := SubViewport.new()
	screen.size = Vector2i(1280, 720)
	add_child(screen)
	screen.add_child(menu)
	var centre := menu.get_viewport_rect().size * 0.5
	menu.update_keys(true, false, 0.5)
	var points: Array[Dictionary] = [{"target": alpha, "screen": centre, "actions": ring}]
	menu.set_points(points)
	menu.set_cursor(centre)
	menu.set_cursor(menu.entry_rects()[1].get_center())
	check(menu.highlighted().get("id") == &"group" and menu.submenu_rects(1).size() == 2, "hovering More opens its submenu")
	menu.set_cursor(menu.submenu_rects(1)[1].get_center())
	await _frames(2)  # draws with More open
	check(menu.highlighted().get("id") == &"check", "the cursor highlights the entry inside it (%s)" % menu.highlighted().get("label"))
	check(menu.update_keys(false, false, 0.05) and menu.chosen.get("id") == &"check", "letting go picks it")
	var text := InteractionMenu.perform(player, menu.chosen)
	check(text.begins_with(alpha.display_name()), "and it does what it says (%s)" % text.replace("\n", " | "))
	screen.queue_free()

	hostile.global_position = SPOT + Vector3(-2.0, 0, -1.0)
	hostile.vitals.server_kill()
	await _frames(3)
	check(_ids(player, hostile) == [&"loot", &"loot_all", &"carry", &"drag"], "the dead: Loot first, then Loot all, Carry, Drag (%s)" % [_ids(player, hostile)])
	hostile.inventory.strip()
	check(_ids(player, hostile) == [&"loot", &"carry", &"drag"] and _action(player, hostile, &"loot").disabled == "Nothing left on them",
		"stripped: Loot greyed (nothing left on them), Loot all left out (%s)" % [_ids(player, hostile)])


## Captain, P0331: the dead couldn't be looted. One shot on the run slides metres as a ragdoll
## while its capsule stays where it fell, and the action point was at the capsule: looking at
## the body showed nothing. The point is on the body as it lies, for a fresh kill and for the
## same body back from the zone save.
func _test_slid_body() -> void:
	print("A body that slid from where it fell")
	var runner := _spawn_ai("Runner", &"hostile", SPOT + Vector3(3.0, 0, -2.0), ["m4a1", "plate_carrier"])
	await _frames(5)
	runner.set_physics_process(false)  # keeps the run going into the fall
	runner.velocity = Vector3(0, 0, -7.0)
	runner.vitals.server_kill()
	await _seconds(4.0)
	var record := runner.body_record()  # (before it's looted)
	await _check_slid_point(runner, "shot on the run")
	record["uid"] = "slid_body"
	record["pos"] = [SPOT.x, SPOT.y, SPOT.z - 2.0]
	var restored := CompoundLevel.current(self).server_spawn_body(record)
	await _seconds(4.0)
	await _check_slid_point(restored, "back from the zone save")
	runner.server_remove_body()
	restored.server_remove_body()
	await _frames(2)


## Stands the player over `body`'s ragdoll, looking down at it, and checks it has its point
## there with Loot and Loot all, and that Loot all reaches it.
func _check_slid_point(body: Soldier, what: String) -> void:
	var chest := body.body_point()
	var gap := Vector2(chest.x - body.global_position.x, chest.z - body.global_position.z).length()
	player.global_position = Vector3(chest.x, SPOT.y, chest.z + 1.5)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3(-0.6, 0, 0)
	player.velocity = Vector3.ZERO
	await _frames(3)
	var points := InteractionMenu.collect_points(player, player.camera).filter(func(p: Dictionary) -> bool: return p.target == body)
	var ids: Array = (points[0].actions as Array).map(func(a: Dictionary) -> StringName: return a.id) if points.size() == 1 else []
	check(gap > 2.0 and points.size() == 1 and ids.has(&"loot") and ids.has(&"loot_all"),
		"%s, %.1f m from its capsule: its point is on the body, with Loot and Loot all (%d points, %s)" % [what, gap, points.size(), ids])
	var before := player.inventory.net_state.duplicate(true)
	player.inventory.strip()
	InteractionMenu.perform(player, _action(player, body, &"loot_all"))
	await _frames(3)
	check(not body.has_gear() and player.inventory.slots[&"primary"] == &"m4a1", "and Loot all takes its gear")
	player.inventory.net_state = before


# --- Helpers -------------------------------------------------------------------------------

func _place_player() -> void:
	player.global_position = SPOT
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO


## Tagging an enemy by radio (EnemyTags; Captain, 2026-10-16, GR Wildlands style): a mark over
## him for every player and on the map, the squad told; no radio, no tag; gone once he's down.
func _test_enemy_tags() -> void:
	print("Enemy tags")
	var tags := EnemyTags.of(level)
	check(tags != null, "every level has the radio net for tags")
	if tags == null:
		return
	var foe := _spawn_ai("TagFoe", &"hostile", player.global_position + Vector3(0, 0, -20), ["m4a1"])
	await _frames(3)
	while player.inventory.count_of(&"radio") > 0 and player.inventory.remove_one(&"radio"):
		pass
	check(tags.server_tag(player, foe).contains("radio"), "no radio: nobody hears it")
	player.inventory.take(&"radio")
	var why := tags.server_tag(player, foe)
	await _frames(2)
	check(why == "Tagged" and tags.is_tagged("TagFoe") and tags.tags.has("TagFoe") and foe.get_node_or_null(^"TagMark") is Label3D,
		"with a radio: tagged, and a mark over him for everyone (%s)" % why)
	check(tags.map_points().size() == 1 and (tags.map_points()[0] as Vector2).distance_to(Vector2(foe.global_position.x, foe.global_position.z)) < 0.5, "and on the map")
	var far := _spawn_ai("TagFar", &"hostile", player.global_position + Vector3(0, 0, -EnemyTags.TAG_RANGE_M - 50.0), ["m4a1"])
	await _frames(2)
	far.global_position = player.global_position + Vector3(0, 0, -EnemyTags.TAG_RANGE_M - 50.0)  # (the spawn keeps to the map)
	await _seconds(EnemyTags.COOLDOWN_S + 0.1)
	var far_why := tags.server_tag(player, far)
	check(far_why != "" and not far_why.begins_with("Tag") and not tags.is_tagged("TagFar"),
		"one he can't make out (out of sight, or past %d m): no tag (%s, %.0f m)" % [int(EnemyTags.TAG_RANGE_M), far_why, far.global_position.distance_to(player.global_position)])
	foe.vitals.server_damage(1000.0)
	await _seconds(0.7)
	check(not tags.is_tagged("TagFoe") and foe.get_node_or_null(^"TagMark") == null, "down, his tag goes")
	foe.queue_free()
	far.queue_free()


## The tutorial (TutorialGuide; Captain, 2026-10-14): the kit and the target, steps ticking off
## on what the player does, Page Down skipping, the end.
func _test_tutorial() -> void:
	print("Tutorial")
	var g := TutorialGuide.start(level)
	await _frames(4)
	var target := level.ai.get_node_or_null(NodePath(TutorialGuide.TARGET)) as Soldier
	check(g != null and target != null and target.faction == &"hostile" and player.inventory.count_of(&"radio") > 0 and player.inventory.count_of(&"frag_grenade") > 0,
		"it hands out a radio and grenades, and stands a target across the yard")
	if g == null:
		return
	check(g.step == 0 and g._keys.text.contains("W"), "step 1 shows the keys as bound (%s)" % g._keys.text)
	player.global_position += Vector3(TutorialGuide.MOVE_M + 1.0, 0, 0)
	await _seconds(0.5)
	check(g.step == 1 and g.done == 1, "walking a few metres ticks it off")
	var sprint := InputEventAction.new()
	sprint.action = &"sprint"
	sprint.pressed = true
	g._input(sprint)
	check(g.step == 2 and g.done == 2, "pressing the step's key ticks it off")
	var skip := InputEventKey.new()
	skip.physical_keycode = TutorialGuide.SKIP_KEY
	skip.pressed = true
	g._input(skip)
	check(g.step == 3 and g.done == 2, "Page Down skips a step without counting it")
	var tag_step := g.index_of("_tagged")
	g.step = tag_step
	g._show()
	var tags := EnemyTags.of(level)
	if tags and target:
		tags._until[TutorialGuide.TARGET] = Soldier._now() + 30.0  # (tagged: EnemyTags' own checks are their test's)
		tags._send()
	await _seconds(0.5)
	check(g.step == tag_step + 1, "tagging the target ticks off the tag step")
	g.step = g.steps.size()
	g._show()
	check(g._title.text.begins_with("Tutorial: done"), "and the end says what to do next")
	g.queue_free()
	if target:
		target.queue_free()


func _spawn_ai(callsign: String, faction: StringName, pos: Vector3, loadout: Array) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": String(faction), "variant": "multicam", "pos": pos,
		"loadout": loadout, "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # we stage everything by hand
	return s


func _spawn_item(id: StringName, pos: Vector3) -> WorldItem:
	level.server_spawn_dropped(id, 1, pos)
	await _frames(2)
	var best: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item.item_id == id and not item.is_queued_for_deletion() and (best == null or item.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
			best = item
	return best


func _ids(actor: Soldier, target: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for a in InteractionMenu.actions_for(actor, target):
		ids.append(a.id)
	return ids


func _action(actor: Soldier, target: Node, id: StringName) -> Dictionary:
	for a in InteractionMenu.actions_for(actor, target):
		if a.id == id:
			return a
	return {}


func _give_entry(to: Soldier, item_id: StringName) -> Dictionary:
	var give := _action(player, to, &"give_item")
	for entry: Dictionary in give.get("items", []):
		var list: Array = player.inventory.containers[entry.container]
		if list[entry.index].id == item_id:
			return entry
	return {}


func _bound(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.physical_keycode == key or event.keycode == key):
			return true
	return false


func _key(key: Key, location: KeyLocation, pressed: bool, ctrl: bool, alt: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.location = location
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _items_near(pos: Vector3, radius: float) -> Array[StringName]:
	var ids: Array[StringName] = []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if not node.is_queued_for_deletion() and (node as Node3D).global_position.distance_to(pos) <= radius:
			ids.append(node.item_id)
	return ids


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


## The pick-up, take-hold or put-down `s` is in is over (the host counts it down in the
## carrier's physics step, which these tests mostly keep off).
func _end_carry_phase(s: Soldier) -> void:
	s._carry_phase_left = 0.0
	s.carry_busy_until = 0.0
	s._update_carried(0.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Captain, 2026-10-14 (v0.3.1, wadi_farm: "cant loot weird ragdoll floating blood"): a hostile
## shot through and lying downed lies on the ground (his ragdoll's parts, not in the air), his
## blood lies on the ground (it hung in the air: drops "landed" on his own gear and parts), and
## he can be searched and stripped (Loot, Loot all) and taken prisoner (Zip-cuff), while a
## squadmate down can't be looted.
func _test_downed_enemy() -> void:
	print("A downed enemy: on the ground, his blood on the ground, looted and cuffed")
	hostile.vitals.server_reset_health()
	hostile.global_position = SPOT + Vector3(-2.0, 0, -3.0)
	hostile.rotation = Vector3.ZERO
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1"]:  # (the dead check before stripped him)
		hostile.inventory.take(id)
	hostile.inventory.take(&"mag_556", 3)
	for i in 20:
		await get_tree().physics_frame
	var ground := SPOT.y - 0.1  # the compound's yard
	var shooter := StaticBody3D.new()
	add_child(shooter)
	shooter.global_position = hostile.global_transform * Vector3(0.1, 1.0, -6.0)
	var aim := (hostile.global_transform * Vector3(0.1, 1.0, 0.0) - shooter.global_position).normalized()
	var shot := Ballistics.fire(shooter, shooter.global_position, aim, ItemDB.get_item(&"m4a1"))
	shooter.queue_free()
	var through := hostile.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.get("out") is Vector3)
	check(shot.result == "body" and through, "shot through the hips (%s, through: %s)" % [shot.result, through])
	hostile.vitals.server_damage(70.0)  # down, not dead
	await _seconds(2.5)
	check(hostile.vitals.downed and is_instance_valid(hostile.ragdoll), "he's down, a ragdoll")
	var high := -INF
	for p: Node3D in hostile.ragdoll.parts.values():
		high = maxf(high, p.global_position.y - ground)
	var torso: Node3D = hostile.ragdoll.parts["torso"]
	check(torso.global_position.y - ground < 0.4 and high < 0.7,
		"lying on the ground (torso %.2f m up, highest part %.2f m)" % [torso.global_position.y - ground, high])
	var marks: WoundMarks = hostile.model.get_node(^"WoundMarks")
	# A drop falls to the ground under him, not onto his own parts (or plates, or pack): the
	# floor a drop falls to is looked up through the body (R0953: pool cells 0.45-0.9 m up).
	var floor_y := marks._floor_below(torso.global_position + Vector3.UP * 0.5)
	check(absf(floor_y - ground) < 0.05, "a drop over him falls through to the ground (%.2f m up)" % (floor_y - ground))
	# A drop from his lowest skin, pressed a little into the yard by the ragdoll, lands on the
	# yard, not 2.5 m under it (CI: pool cells at -2.50).
	var under_y := marks._floor_below(Vector3(torso.global_position.x, ground - 0.03, torso.global_position.z))
	check(absf(under_y - ground) < 0.05, "a drop starting just under the ground lands on it (%.2f m up)" % (under_y - ground))
	for i in 60:
		if marks.drops_in_air() == 0:
			break
		await get_tree().physics_frame
	var cells := marks.pool_cells()
	var off := cells.map(func(c: Vector3) -> float: return c.y - ground).filter(func(h: float) -> bool: return absf(h) > 0.2)
	check(not cells.is_empty() and off.is_empty(), "his blood is on the ground (%d cells; off it: %s)" % [cells.size(), off])
	player.global_position = hostile.body_point() + Vector3(0, 0, 1.2)
	player.global_position.y = SPOT.y
	await _frames(2)
	alpha.vitals.server_damage(70.0)
	await _frames(2)
	check(not _ids(player, alpha).has(&"loot"), "a downed squadmate can't be looted (%s)" % [_ids(player, alpha)])
	alpha.vitals.server_reset_health()
	var loot := _action(player, hostile, &"loot")
	check(loot.get("disabled") == "" and loot.get("window", false), "Loot opens the loot window (no more instant list)")
	var mags := player.inventory.count_of(&"mag_556")
	InteractionMenu.perform(player, _action(player, hostile, &"loot_all"))
	await _frames(3)
	check(hostile.inventory.slots[&"primary"] == &"" and hostile.inventory.count_of(&"mag_556") == 0 and player.inventory.count_of(&"mag_556") > mags,
		"Loot all disarms him: his rifle and mags are gone, the mags are yours (%d -> %d)" % [mags, player.inventory.count_of(&"mag_556")])
	player.inventory.take(Person.ZIP_CUFFS)
	InteractionMenu.perform(player, _action(player, hostile, &"cuff"))
	var cuffed: bool = await _wait_until(func() -> bool: return Person.is_cuffed(hostile), 8.0)
	check(cuffed and Person.is_captive(hostile) and SquadAI.of(hostile) == null,
		"Zip-cuff takes him prisoner: cuffed, a captive, no squad brain to fight on with")
	check(_ids(player, hostile).has(&"loot") and _ids(player, hostile).has(&"carry"), "and he can still be searched and carried (%s)" % [_ids(player, hostile)])


## The loot window (LootWindow, docs/loot_window.md): Loot opens it, contents wait for the
## search time, moves go each way through host requests, "Take all ammo" sweeps the mags, a stale
## or out-of-reach request moves nothing, and nothing is duplicated.
func _test_loot_window() -> void:
	print("The loot window")
	var body := _spawn_ai("Searched", &"hostile", SPOT + Vector3(-4.0, 0, 3.0), ["plate_carrier", "m4a1"])
	body.inventory.take(&"mag_556", 3)
	body.inventory.take(&"ifak", 2)
	body.vitals.server_kill()
	await _frames(4)
	player.global_position = body.body_point() + Vector3(0, 0, 1.2)
	player.global_position.y = SPOT.y
	await _frames(2)
	var hud: Hud = player._hud
	var win := hud.loot_window
	player.inventory.strip()
	player.inventory.take(&"plate_carrier")
	var total_ifak := body.inventory.count_of(&"ifak")
	var total_mags := body.inventory.count_of(&"mag_556")
	InteractionMenu.perform(player, _action(player, body, &"loot"))
	await _frames(3)
	check(win.is_open() and win.source == body and hud.is_inventory_open(), "Loot opens the window on the body")
	check(win.searching() and win.search_s >= Soldier.LOOT_SEARCH_BODY_S, "it searches first (%.1f s)" % win.search_s)
	var ifak_at := _find_entry(body.inventory, &"ifak")
	check(not ifak_at.is_empty(), "the body has the ifaks stowed")
	player.rpc_id(1, &"_server_loot_move", body.get_path(), ifak_at.container, ifak_at.index, &"ifak")
	await _frames(3)
	check(body.inventory.count_of(&"ifak") == total_ifak and player.inventory.count_of(&"ifak") == 0, "a move during the search is refused")
	await _seconds(win.search_s + 0.4)
	win._process(0.0)
	check(not win.searching(), "the contents show after the search time")
	win.move({"side": &"src", "where": ifak_at.container, "index": ifak_at.index, "id": &"ifak"})
	win.move({"side": &"src", "where": ifak_at.container, "index": ifak_at.index, "id": &"ifak"})  # a second, stale request
	await _frames(4)
	check(player.inventory.count_of(&"ifak") + body.inventory.count_of(&"ifak") == total_ifak and player.inventory.count_of(&"ifak") == total_ifak,
		"a body item moves to you, and the repeat request duplicates nothing (%d + %d of %d)" % [player.inventory.count_of(&"ifak"), body.inventory.count_of(&"ifak"), total_ifak])
	var mine := _find_entry(player.inventory, &"ifak")
	win.move({"side": &"me", "where": mine.container, "index": mine.index, "id": &"ifak"})
	await _frames(4)
	check(body.inventory.count_of(&"ifak") == total_ifak and player.inventory.count_of(&"ifak") == 0, "and yours moves to the body")
	win.take_class(&"ammo")
	await _frames(4)
	check(body.inventory.count_of(&"mag_556") == 0 and player.inventory.count_of(&"mag_556") == total_mags, "Take all ammo sweeps the magazines (%d of %d)" % [player.inventory.count_of(&"mag_556"), total_mags])
	check(body.inventory.count_of(&"ifak") == total_ifak, "and leaves the meds")
	win.take_class(&"medical")
	await _frames(4)
	check(body.inventory.count_of(&"ifak") == 0 and player.inventory.count_of(&"ifak") == total_ifak, "Take all meds takes the ifaks")
	check(win.why_close() == "", "still in reach: the window stays")
	player.global_position = body.body_point() + Vector3(8, 0, 0)
	player.global_position.y = SPOT.y
	check(win.why_close() == "Moved away", "walking off closes it")
	player.rpc_id(1, &"_server_loot_move", body.get_path(), &"primary", -1, &"m4a1")
	await _frames(3)
	check(body.inventory.slots[&"primary"] == &"m4a1", "a request out of reach moves nothing")
	win.close()
	player.global_position = body.body_point() + Vector3(0, 0, 1.2)
	player.global_position.y = SPOT.y
	await _frames(2)
	InteractionMenu.perform(player, _action(player, body, &"loot"))
	await _frames(3)
	check(win.is_open() and not win.searching(), "reopening a searched body is instant")
	player.vitals.server_damage(10.0)
	await _frames(3)
	check(not win.is_open(), "being hit closes it")
	win.close()
	check(not win.is_open() and not hud.is_inventory_open(), "closed")


## {container, index} of the first stowed entry of `id` in `inv`, or {}.
func _find_entry(inv: Inventory, id: StringName) -> Dictionary:
	for container in inv.search_containers():
		var list: Array = inv.containers[container]
		for i in list.size():
			if list[i].id == id:
				return {"container": container, "index": i}
	return {}


func _act(action: StringName, shift := false) -> void:
	var e: InputEvent
	if shift:
		var k := InputEventKey.new()
		k.keycode = KEY_G
		k.physical_keycode = KEY_G
		k.shift_pressed = true
		k.pressed = true
		e = k
		if not e.is_action(action):
			e = InputEventAction.new()
			(e as InputEventAction).action = action
			e.pressed = true
	else:
		e = InputEventAction.new()
		(e as InputEventAction).action = action
		e.pressed = true
	player.player_input._unhandled_input(e)


func _test_grenade_equip() -> void:
	print("Grenade equip")
	_place_player()
	player.inventory.take(&"frag_grenade", 2)
	player.inventory.take(&"flashbang", 1)
	player._busy_until = 0.0
	player._server_busy_until = 0.0
	var pi: PlayerInput = player.player_input
	pi.throwable = &"frag_grenade"
	var frags := player.inventory.count_of(&"frag_grenade")
	_act(&"grenade")
	await _frames(3)
	check(pi.nade_up and player.inventory.count_of(&"frag_grenade") == frags, "the grenade key equips it and throws nothing (count %d)" % player.inventory.count_of(&"frag_grenade"))
	check(player.view_model.get_node_or_null(^"HeldGrenade") != null, "the grenade is in your hand in first person")
	# Aiming and reloading don't break it.
	_act(&"reload")
	check(not player.is_reloading, "reloading does nothing with a grenade up")
	_act(&"grenade")
	await _frames(2)
	check(not pi.nade_up and player.inventory.count_of(&"frag_grenade") == frags and player.view_model.get_node_or_null(^"HeldGrenade") == null, "the key again puts it away, nothing thrown, weapon back")
	_act(&"grenade")
	_act(&"weapon_primary")
	await _frames(2)
	check(not pi.nade_up and player.inventory.count_of(&"frag_grenade") == frags, "a weapon key puts it away, nothing thrown")
	_act(&"grenade")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	pi._unhandled_input(wheel)
	check(not pi.nade_up and player.inventory.count_of(&"frag_grenade") == frags, "the wheel puts it away, nothing thrown")
	# Cycling while it is up.
	_act(&"grenade")
	var before := pi.throwable
	_act(&"grenade", true)
	check(pi.nade_up and pi.throwable != before, "Shift+G cycles the type with it up (%s)" % pi.throwable)
	pi.throwable = &"frag_grenade"
	player._busy_until = 0.0
	# Left click throws one.
	pi._try_throw(1.0)  # (a click: headless has no captured mouse for the input path)
	await _frames(4)
	check(player.inventory.count_of(&"frag_grenade") == frags - 1, "Fire throws exactly one (count %d)" % player.inventory.count_of(&"frag_grenade"))
	check(pi.nade_up, "the next one stays up")
	# Right click lobs (a second one), then the last one puts the weapon back.
	player._busy_until = 0.0
	player._server_busy_until = 0.0
	pi._try_throw(PlayerInput.LOB_POWER)
	await _frames(4)
	check(player.inventory.count_of(&"frag_grenade") == frags - 2 and not pi.nade_up, "Aim lobs one and the weapon comes back after the last")
	await _seconds(5.0)  # let them go off
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
