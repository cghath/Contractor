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
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
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
	_clear_contact()  # anyone glimpsed before they were removed (friendlies see 120 m)
	await _test_roster()
	_test_command_menu()
	_test_navigation()
	await _test_follow()
	await _test_senses()
	await _test_buddy_carries_buddy()
	await _test_contact()
	_test_flash_stuns()
	await _test_dead_leave_squad()
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
	check(_squad().size() == 7 and guest.squad_slot == -1, "a second player waits outside the squad until their pick arrives (%d AI)" % _squad().size())
	level.player_roles[2] = Roles.RIFLEMAN
	level.rebalance_squad()
	await _frames(2)
	check(_squad().size() == 6 and _ai("Foxtrot") == null and guest.role == Roles.RIFLEMAN,
		"then, as a rifleman, takes Foxtrot's rifleman slot (%d AI)" % _squad().size())
	check(guest.buddy == _ai("Golf") and _ai("Golf").buddy == guest, "and pairs with that slot's buddy, Golf")
	guest.queue_free()
	level.player_roles.erase(2)
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


## The squad's senses and habits (Captain, 2026-10-12: they seemed a bit unintelligent):
## halted with the lead they take spots beside something solid and watch outward; they hear
## enemy fire they can't see; contact one sees reaches the rest; pinned in the open, one
## crawls to cover instead of freezing.
func _test_senses() -> void:
	print("Senses and habits")
	var squad := level.squad_for(&"friendly")
	# The lead has stood still since "Following": everyone has a halt spot near their slot.
	var spots := _squad().filter(func(s: Soldier) -> bool:
		var ai := SquadAI.of(s)
		return ai._halt_spot != null and _flat(ai._halt_spot, squad.follow_point(s)) <= SquadAI.HALT_COVER_M + 0.7)
	check(spots.size() == _squad().size(), "halted with the lead, each takes a spot by its slot (%d of %d)" % [spots.size(), _squad().size()])
	await _seconds(1.5)
	var out := _squad().filter(func(s: Soldier) -> bool:
		var ai := SquadAI.of(s)
		if ai._halt_spot == null or _flat(s.global_position, ai._halt_spot) > SquadAI.ARRIVE + 0.3:
			return true  # still getting there: not judged
		var away := Vector3(s.global_position.x - player.global_position.x, 0, s.global_position.z - player.global_position.z).normalized()
		return (-s.global_basis.z).dot(away) > 0.5)
	check(out.size() >= _squad().size() - 1, "and watches outward from the lead (%d of %d)" % [out.size(), _squad().size()])
	# Hearing: a hostile shot 60 m off, out of sight, puts the squad in contact toward it;
	# a suppressed one that far doesn't.
	var shooter := level.spawn_soldier({"name": "HeardHostile", "faction": "hostile", "variant": "urban",
		"pos": player.global_position + Vector3(0, 0, -60), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(2)
	SquadAI.of(shooter).process_mode = Node.PROCESS_MODE_DISABLED
	var alpha := _ai("Alpha")
	var before := alpha.threat_time
	SquadAI.server_heard_shot(shooter, shooter.global_position, true)
	check(alpha.threat_time == before, "a suppressed shot 60 m off goes unheard")
	SquadAI.server_heard_shot(shooter, shooter.global_position, false)
	var off := _flat(alpha.threat_pos, shooter.global_position)
	check(alpha.threat_time > before and off <= SquadAI.HEARD_ERROR_PER_100M * 0.85, "a plain one is heard: contact toward it (%.1f m off)" % off)
	await _frames(2)
	check(SquadAI.of(alpha).in_contact(), "and Alpha is in contact (%s)" % alpha.ai_status)
	shooter.queue_free()
	_clear_contact()
	# Shared contact: what one squadmate sees, the rest nearby know about.
	var bravo := _ai("Bravo")
	SquadAI.of(alpha)._share_contact(player.global_position + Vector3(0, 0, -40), Soldier._now())
	check(bravo.threat_time >= Soldier._now() - 0.1 and _flat(bravo.threat_pos, player.global_position + Vector3(0, 0, -40)) < 0.1,
		"contact Alpha sees reaches Bravo")
	_clear_contact()
	# Pinned in the open: crawl to cover rather than freeze.
	var echo := _ai("Echo")
	var ai := SquadAI.of(echo)
	var threat := echo.global_position + Vector3(0, 0, -15)
	ai._has_cover = false
	var reached := await _wait_until(func() -> bool:
		echo.suppression = 1.0
		echo.threat_pos = threat
		echo.threat_time = Soldier._now()
		return ai._has_cover and ai._at_cover(), 6.0)
	check(reached and ai._cover_protects(ai._cover_point), "pinned in the open, Echo crawls to cover (%s, %.1f m off)" % [echo.ai_status, _flat(echo.global_position, ai._cover_point)])
	echo.suppression = 0.0
	_clear_contact()
	await _seconds(1.0)


## Everyone out of contact again (between staged checks).
func _clear_contact() -> void:
	for s: Soldier in _squad():
		s.threat_time = -1000.0
		var ai := SquadAI.of(s)
		ai._last_contact = -1000.0
		ai._fired_on_at = -1000.0
		ai.target = null
	level.squad_for(&"friendly").engaged_at = -1000.0


func _test_buddy_carries_buddy() -> void:
	print("Downed buddy, out of contact")
	var bravo := _ai("Bravo")
	var charlie := _ai("Charlie")  # Bravo's battle buddy and team A's medic
	bravo.vitals.server_damage(70.0)  # out cold, 42% of his blood lost: he won't wake soon
	var picked := await _wait_until(func() -> bool: return bravo.carried_by == charlie, 45.0)  # NPA, then a line, a bag, a pressure bag
	check(picked, "nothing left to treat and not waking, his buddy Charlie, the medic, picks him up (%s)" % charlie.ai_status)
	check(bravo.vitals.access().get("kind", "") == "io" and bravo.vitals.access().pressure and not bravo.vitals.infusion().is_empty(),
		"first an IO line (veins collapsed), a pressure bag and a bag running (%s, %s)" % [bravo.vitals.access(), bravo.vitals.infusion()])
	_place(player, Vector3(-8, 0.1, 4))
	var along := await _wait_until(func() -> bool: return _flat(bravo.global_position, player.global_position) < 11.0, 15.0)
	check(along, "and carries him after the lead (%.1f m)" % _flat(bravo.global_position, player.global_position))
	check(bravo.vitals.downed, "nobody revives him: he's still out (%s)" % bravo.vitals.condition_text())
	bravo.vitals.server_reset_health()  # he comes round (the wound model decides when; the test stands in)
	var down := await _wait_until(func() -> bool: return bravo.carried_by == null and SquadAI.of(charlie).casualty == null, 5.0)
	check(down, "awake, he's put down and Charlie goes back to following (%s)" % charlie.ai_status)


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


func _test_dead_leave_squad() -> void:
	print("A dead squadmate")
	var squad := level.squad_for(&"friendly")
	var foxtrot := _ai("Foxtrot")
	var living := level._squad_ai().size()
	foxtrot.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(2)
	check(foxtrot not in squad.members() and foxtrot.squad_slot == -1, "leaves the squad: no member, no slot, no formation place")
	var order_before := SquadAI.of(foxtrot).order
	squad.give_order(player, Squad.Order.HOLD, player.global_position)
	check(SquadAI.of(foxtrot).order == order_before and SquadAI.of(_ai("Golf")).order == Squad.Order.HOLD, "and takes no orders")
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position)
	level.rebalance_squad()
	await _frames(2)
	check(is_instance_valid(foxtrot) and foxtrot.is_in_group(Soldier.DEAD_GROUP) and foxtrot.inventory.slots[&"primary"] != &""
		and level._squad_ai().size() == living - 1, "a rebalance leaves his body and gear where they are and doesn't replace him (%d living)" % level._squad_ai().size())


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


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Waits until `cond` holds or `timeout` seconds pass; returns whether it held.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
