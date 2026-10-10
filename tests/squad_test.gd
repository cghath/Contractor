extends Node
## Headless squad AI scenarios, kept short: hosts a real session with the squad and
## hostiles, stages a few situations and checks what the AI does about them.
##   <voxel godot exe> --headless --path . res://tests/squad_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_squad" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("SQUAD TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	_remove_hostiles()
	await _frames(10)
	await _test_roster()
	_test_command_menu()
	_test_navigation()
	await _test_follow()
	await _test_buddy_carries_buddy()
	await _test_contact()
	_test_flash_stuns()
	GameState.delete_save()
	print("SQUAD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_roster() -> void:
	print("Roster")
	check(_squad().size() == 7, "one player gets 7 AI squadmates (%d)" % _squad().size())
	check(player.buddy == _ai("Alpha"), "the player's battle buddy is Alpha")
	check(_ai("Bravo").buddy == _ai("Charlie") and _ai("Charlie").buddy == _ai("Bravo"), "squadmates are paired too")
	var guest: Soldier = load("res://scenes/soldier.tscn").instantiate()
	guest.name = "2"
	guest.position = Vector3(6, 0.1, 30)
	level.players.add_child(guest)
	level.rebalance_squad()
	await _frames(2)
	check(_squad().size() == 6 and _ai("Golf") == null, "a second player takes the last slot (%d AI)" % _squad().size())
	check(guest.buddy == _ai("Bravo") or guest.buddy == _ai("Alpha") or guest.buddy == player, "and gets a buddy")
	guest.queue_free()
	await _frames(1)
	level.rebalance_squad()
	await _frames(2)
	check(_squad().size() == 7, "when they leave, AI fills the slot again (%d)" % _squad().size())


func _test_command_menu() -> void:
	print("Command menu")
	var menu: CommandMenu = player._hud.command_menu
	var squad := level.squad_for(&"friendly")
	_press(menu, KEY_F3)  # F1 is you, F2 Alpha, F3 Bravo
	check(menu.is_open() and menu.selected == PackedStringArray(["Bravo"]), "F3 selects Bravo and opens the menu")
	_press(menu, KEY_1)
	_press(menu, KEY_3)  # Move > Stop
	check(SquadAI.of(_ai("Bravo")).order == Squad.Order.HOLD and SquadAI.of(_ai("Alpha")).order == Squad.Order.FOLLOW,
		"1 Move > 3 Stop holds only Bravo")
	check(not menu.is_open(), "the menu closes after an order")
	_press(menu, KEY_QUOTELEFT)
	check(menu.selected.size() == 7, "~ selects the whole squad")
	for i in 7:
		_scroll(menu, MOUSE_BUTTON_WHEEL_DOWN)  # down to 8 Formation
	_scroll(menu, MOUSE_BUTTON_MIDDLE)
	_scroll(menu, MOUSE_BUTTON_WHEEL_DOWN)
	_scroll(menu, MOUSE_BUTTON_MIDDLE)  # File
	check(squad.formation == "file", "scroll and middle click: Formation > File")
	_press(menu, KEY_QUOTELEFT)
	_press(menu, KEY_3)
	_press(menu, KEY_2)  # Engage > Hold fire
	check(SquadAI.of(_ai("Golf")).hold_fire, "Engage > Hold fire")
	_press(menu, KEY_QUOTELEFT)
	_press(menu, KEY_3)
	_press(menu, KEY_1)  # Engage > Open fire
	_press(menu, KEY_QUOTELEFT)
	_press(menu, KEY_1)
	_press(menu, KEY_1)  # Move > Return to formation
	squad.formation = "wedge"
	check(not SquadAI.of(_ai("Golf")).hold_fire and SquadAI.of(_ai("Bravo")).order == Squad.Order.FOLLOW, "and back to open fire, in formation")


func _press(menu: CommandMenu, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	menu.handle_input(ev)


func _scroll(menu: CommandMenu, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	menu.handle_input(ev)


func _test_navigation() -> void:
	print("Navigation")
	var target := Vector3(0, 0, -8)
	var path := NavigationServer3D.map_get_path(player.get_world_3d().navigation_map, Vector3(0, 0, 27), target, true)
	check(path.size() > 2 and _flat(path[-1], target) < 1.0, "a path from the spawn into the building (ends at %s)" % (path[-1] if path.size() > 0 else "nothing"))


func _test_follow() -> void:
	print("Following")
	_place(player, Vector3(0, 0.1, 12))
	await _seconds(12.0)
	var squad := level.squad_for(&"friendly")
	var far := _squad().filter(func(s: Soldier) -> bool: return _flat(s.global_position, squad.follow_point(s)) > 3.0)
	for s: Soldier in far:
		print("    %s at %s, slot %s, %s" % [s.name, s.global_position, squad.follow_point(s), s.ai_status])
	check(far.is_empty(), "the whole squad follows the lead through the gate into formation (%d not there)" % far.size())


func _test_buddy_carries_buddy() -> void:
	print("Downed buddy, out of contact")
	var bravo := _ai("Bravo")
	var charlie := _ai("Charlie")
	var kits := _take_kits(charlie)
	bravo.vitals.server_damage(500.0)
	await _seconds(5.0)
	check(bravo.carried_by == charlie, "his buddy Charlie picks him up (%s)" % charlie.ai_status)
	_place(player, Vector3(-8, 0.1, 4))
	await _seconds(6.0)
	check(_flat(bravo.global_position, player.global_position) < 11.0, "and carries him after the lead (%.1f m)" % _flat(bravo.global_position, player.global_position))
	for id: StringName in kits:
		charlie.inventory.take(id)
	await _seconds(6.0)
	check(bravo.vitals.is_up() and bravo.carried_by == null, "handed a kit, Charlie revives him (Bravo HP %d)" % bravo.vitals.health)


func _test_contact() -> void:
	print("Contact")
	_place(player, Vector3(0, 0.1, 16))
	await _seconds(3.0)
	var hostile := level.spawn_soldier({"name": "TestHostile", "faction": "hostile", "variant": "urban", "pos": Vector3(0, 0.1, -1),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.3, "discipline": 0.5, "guard": true})
	var fought_from_cover := false
	for i in 20 * 4:
		await _seconds(0.25)
		if _squad().any(func(s: Soldier) -> bool: return s.ai_status in ["In cover", "Engaging", "Bounding", "Pinned down"]):
			fought_from_cover = true
		if not is_instance_valid(hostile) or not hostile.vitals.is_up():
			break
	check(fought_from_cover, "the squad fights from cover")
	check(not is_instance_valid(hostile) or not hostile.vitals.is_up(), "and puts the hostile down")


func _test_flash_stuns() -> void:
	print("Flashbang")
	var alpha := _ai("Alpha")
	Throwables.server_detonate(level, "flash", alpha.global_position + Vector3(0, 2.6, 0))
	check(alpha.stunned_s > 1.0, "a flashbang stuns AI that sees it (%.1f s)" % alpha.stunned_s)


# --- Helpers --------------------------------------------------------------

func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s.faction == &"friendly" and not s.is_queued_for_deletion())


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _take_kits(s: Soldier) -> Array[StringName]:
	var taken: Array[StringName] = []
	for id: StringName in SquadAI.REVIVE_KITS:
		while s.inventory.remove_one(id):
			taken.append(id)
	return taken


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
