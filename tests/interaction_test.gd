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
	GameState.delete_save()
	print("INTERACTION TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_key_bindings() -> void:
	print("Key bindings")
	var interact := InputMap.action_get_events(&"interact")
	check(interact.size() == 1 and interact[0] is InputEventKey and interact[0].physical_keycode == KEY_CTRL
		and interact[0].location == KEY_LOCATION_LEFT, "interact is Left Ctrl")
	check(not _bound(&"interact", KEY_E), "E no longer interacts")
	var self_events := InputMap.action_get_events(&"self_interact")
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
	dummy.vitals.server_damage(500.0)  # cardiac arrest: nothing in the kit helps until the heart restarts
	await _frames(2)
	check(_ids(player, alpha) == [&"treat", &"carry", &"drag", &"check_condition"], "downed squadmate: Treat, Carry, Drag, Check condition; no Revive (%s)" % [_ids(player, alpha)])
	var treat := _action(player, alpha, &"treat")
	check(treat.items.size() == 2 and treat.items[0].label == "NPA Airway, head" and treat.items[0].disabled.contains("NPA") and treat.items[1].label.begins_with("Morphine"),
		"Treat lists what they need, greyed out without the item (%s: %s)" % [treat.items.map(func(e: Dictionary) -> String: return e.label), treat.items.map(func(e: Dictionary) -> String: return e.disabled)])
	player.inventory.take(&"trauma_kit")
	check(not _ids(player, alpha).has(&"revive"), "a trauma kit adds no Revive either (%s)" % [_ids(player, alpha)])
	check(_action(player, alpha, &"treat").items[0].disabled == "", "its NPA can go in")
	player.inventory.take(&"hvt_case")
	check(_action(player, alpha, &"carry").disabled.contains("hands"), "can't carry with your hands full")
	player.inventory.release_hands()
	check(_ids(player, dummy) == [&"check_condition"], "downed dummy in cardiac arrest: Check condition, nothing to treat (%s)" % [_ids(player, dummy)])
	check(_ids(player, hostile) == [&"carry", &"drag", &"check_condition"], "downed enemy: Carry, Drag, Check condition (%s)" % [_ids(player, hostile)])
	var report := InteractionMenu.perform(player, _action(player, alpha, &"check_condition"))
	check(report.begins_with("Alpha: " + alpha.vitals.condition_text()) and report.contains("\n"), "Check condition reads condition and wounds (%s)" % report.replace("\n", " | "))
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
	check(is_equal_approx(player.carry_speed_mult(), Soldier.CARRY_SPEED_MULT) and is_equal_approx(Soldier.CARRY_SPEED_MULT, 0.55), "carrying slows you to 0.55")
	check(alpha.collision_layer == 0 and alpha.care_by == player, "the body stops colliding, and squadmates leave it to you")
	await _frames(3)
	check(alpha.global_position.distance_to(player.carry_transform().origin) < 0.05, "it rides on your shoulder")
	check(_ids(player, player).has(&"put_down"), "self-interaction offers Put down")
	check(_action(player, alpha, &"carry").disabled != "", "can't pick up a second body")

	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.carrying == alpha and player.carry_mode == Soldier.DRAG, "Drag on the body you carry switches to dragging")
	check(is_equal_approx(player.carry_speed_mult(), Soldier.DRAG_SPEED_MULT) and Soldier.DRAG_SPEED_MULT < Soldier.CARRY_SPEED_MULT, "dragging is slower (0.35)")
	player.global_position += Vector3(0, 0, -2.0)
	await _frames(3)
	var local := player.global_transform.affine_inverse() * alpha.global_position
	check(local.z > 0.8 and absf(local.y) < 0.2, "the body slides along behind you (%s)" % local)
	InteractionMenu.perform(player, _action(player, player, &"put_down"))
	check(player.carrying == null and player.carry_mode == &"" and is_equal_approx(player.carry_speed_mult(), 1.0), "Let go releases it and your speed")
	check(alpha.carried_by == null and alpha.collision_layer == Soldier.BODY_LAYER and alpha.care_by == null, "the body collides again")
	check(alpha.global_position.distance_to(player.global_position) > 0.8, "and stays where you dragged it")

	_place_player()
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.carry_mode == Soldier.DRAG, "Drag takes hold of a body directly")
	player.set_physics_process(true)  # the host keeps a player's casualty with them
	alpha.vitals.server_reset_health()
	await _frames(3)
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
	await _frames(3)
	var pos: Variant = player.carried_by_pos
	check(pos is Vector3 and (pos as Vector3).distance_to(bravo.carry_transform().origin) < 0.05, "the host sends the player where they are carried")
	player._physics_process(1.0 / 60.0)
	check(player.global_position.distance_to(bravo.carry_transform().origin) < 0.05, "the player's body follows it")
	bravo._server_drag_body.rpc_id(1, player.get_path())
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
	check(rects.size() == InteractionMenu.actions_for(player, player).size(), "your actions are around the centre")
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


# --- Helpers -------------------------------------------------------------------------------

func _place_player() -> void:
	player.global_position = SPOT
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO


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
