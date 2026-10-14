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
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
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
	await _test_spotting()
	await _test_fire_discipline()
	await _test_tactics()
	_test_doctrine_pending()
	await _test_dead_leave_squad()
	await _test_buildings_per_world()
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
	# Contact (SquadAI._last_contact) is taken up in the AI's physics step, and a process frame
	# can pass with no physics step at all (0 in 52 of 300 two-frame windows here, R0125): wait
	# for physics steps, not frames (CI run 38422752494 failed this check after two frames).
	await _physics_frames(2)
	check(SquadAI.of(alpha).in_contact(), "and Alpha is in contact (%s)" % alpha.ai_status)
	shooter.queue_free()
	_clear_contact()
	# Shared contact: what one squadmate sees, the rest nearby know about.
	var bravo := _ai("Bravo")
	var told_at := Soldier._now()
	SquadAI.of(alpha)._share_contact(player.global_position + Vector3(0, 0, -40), told_at)
	check(bravo.threat_time < told_at, "a callout takes a moment to land (queue 17 part 3)")
	await _seconds(SquadAI.SHARE_VOICE_S + 0.3)
	check(bravo.threat_time >= told_at and _flat(bravo.threat_pos, player.global_position + Vector3(0, 0, -40)) < 0.1,
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
		# (Seven on one this close, the squad's tactics may assault through: that's fighting too.)
		if _squad().any(func(s: Soldier) -> bool: return s.ai_status in ["In cover", "Engaging", "Bounding", "Pinned down", "Assaulting", "Flanking"]):
			fought_from_cover = true
		if not is_instance_valid(hostile) or not hostile.vitals.is_up():
			break
	check(fought_from_cover, "the squad fights (from cover, or assaulting the position)")
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


## Captain (P0164 queue 17 core): the squad's tactical evaluator picks what the situation calls
## for (SquadTactics.score, staged), and (queue 12) the command menu's orders reach the units.
func _test_tactics() -> void:
	print("Tactics: the situation decides")
	var sit := {"up": 6, "down": 0, "contact": true, "known": 3, "fresh": true, "stale": false, "cluster": {"centre": Vector3.ZERO},
		"range": 80.0, "enemy_building": {}, "home_building": {}, "in_home": false, "suppression": 0.1, "morale": 0.9, "ammo": 0.9,
		"cover": 0.6, "order": Squad.Order.FOLLOW, "weapons_free": true, "age": 1.0}
	var pmc: Dictionary = SquadTactics.DOCTRINES[Doctrine.PMC]
	var best := func(changes: Dictionary) -> int:
		var scores: Dictionary = SquadTactics.score(sit.merged(changes, true), pmc).scores
		var top := -1
		for o: int in scores:
			if top < 0 or float(scores[o]) > float(scores[top]):
				top = o
		return top
	check(best.call({}) == SquadTactics.Option.SUPPRESS_FLANK, "6 of us, 3 of them 80 m off, in cover: fix them and flank")
	check(best.call({"range": 15.0}) == SquadTactics.Option.ASSAULT, "2 to 1 and 15 m off: assault through")
	check(best.call({"up": 2, "known": 6, "morale": 0.1, "down": 2}) == SquadTactics.Option.BREAK_CONTACT, "outnumbered, shaken, two down: break contact")
	check(best.call({"down": 1}) == SquadTactics.Option.CASUALTY, "one down otherwise steady: cover the casualty first")
	check(not SquadTactics.score(sit.merged({"order": Squad.Order.HOLD}, true), pmc).scores.has(SquadTactics.Option.SUPPRESS_FLANK),
		"on Hold, the squad doesn't go flanking")
	check(best.call({"contact": false, "fresh": false, "stale": true, "age": 30.0}) == SquadTactics.Option.SEARCH, "lost them: search where they were last seen")

	print("Command menu orders")
	var squad := level.squad_for(&"friendly")
	squad.known.clear()
	var alpha := SquadAI.of(_ai("Alpha"))
	check(squad.order_command(player, "suppress:known", Vector3.ZERO, PackedStringArray(["Alpha"])) == "No known enemy to suppress",
		"Suppress known enemy with nothing known: says so")
	var far := level.spawn_soldier({"name": "TacticsTarget", "faction": "hostile", "variant": "urban", "pos": Vector3(40, 0.1, -40),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.3, "discipline": 0.5, "guard": true})
	SquadAI.of(far).process_mode = Node.PROCESS_MODE_DISABLED
	squad.note_enemy(far, far.global_position)
	check(squad.order_command(player, "suppress:known", Vector3.ZERO, PackedStringArray(["Alpha"])) == ""
		and StringName(alpha.ordered.get("kind", &"")) == &"suppress" and alpha.weapons_free()
		and alpha._suppress_point() != null and _flat(alpha._suppress_point(), far.global_position) < 3.0,
		"Suppress known enemy: Alpha puts rounds on the known position (%s)" % [alpha.ordered])
	far.queue_free()
	squad.known.clear()
	var lying := _standing_mate([_ai("Alpha")])
	var one := PackedStringArray([String(lying.name)])
	squad.order_command(player, "stance:prone", Vector3.ZERO, one)
	await _frames(4)
	check(lying.want_stance == SoldierMovement.Stance.PRONE, "Stance > Prone: %s goes prone (%s)" % [lying.name, lying.ai_status])
	squad.order_command(player, "stance:auto", Vector3.ZERO, one)
	await _frames(4)
	check(lying.want_stance == -1, "Their choice: back to their own")
	var hurt := _squad().filter(func(s: Soldier) -> bool: return not SquadAI.of(s)._self_task().is_empty()).size()
	check(hurt > 0 or squad.order_command(player, "heal", Vector3.ZERO, one) == "Nobody selected has wounds they can treat",
		"Heal up with nobody hurt: says so")
	check(squad.order_command(player, "follow", Vector3.ZERO) == "?", "anything else goes to the older commands")
	squad.order_command(player, "take_cover", Vector3.ZERO, PackedStringArray(["Charlie"]))
	check(StringName(SquadAI.of(_ai("Charlie")).ordered.get("kind", &"")) == &"cover", "Take cover: Charlie looks for cover")
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position, PackedStringArray(["Charlie"]))
	check(SquadAI.of(_ai("Charlie")).ordered.is_empty(), "and a movement order replaces it")

	# Drop packs, then go back for them.
	var mate: Soldier = null
	for s: Soldier in _squad():
		if s.inventory.slots.get(&"backpack", &"") != &"" and SquadAI.of(s).care == SquadAI.Care.NONE:
			mate = s
			break
	if mate == null:
		check(false, "someone in the squad wears a pack")
	else:
		var names := PackedStringArray([String(mate.name)])
		var pack: StringName = mate.inventory.slots[&"backpack"]
		check(squad.order_command(player, "drop_packs", Vector3.ZERO, names) == "" and mate.inventory.slots[&"backpack"] == &""
			and get_tree().get_nodes_in_group(WorldItem.GROUP).any(func(n: Node) -> bool: return (n as WorldItem).item_id == pack and _flat(n.global_position, mate.global_position) < 2.0),
			"Drop packs here: %s's pack goes on the ground beside him" % mate.name)
		# Audit A2-08: his own pack, by identity. It has rolled behind him, and a squadmate's pack of
		# the same model lies right where his went down: he must not take that one.
		var mate_ai := SquadAI.of(mate)
		var own := mate_ai._dropped_pack_item()
		var had_own := own != null
		var decoy_uid := ""
		if own:
			own.state = own.state.merged({"test_serial": "own"}, true)
			own.global_position = mate.global_position + mate.global_basis.z * 0.6 + Vector3.UP * 0.4
			own.linear_velocity = Vector3.ZERO
			decoy_uid = level.server_spawn_dropped(pack, 1, mate_ai.dropped_pack.pos, {"test_serial": "decoy"})
		squad.order_command(player, "pick_packs", Vector3.ZERO, names)
		check(await _wait_until(func() -> bool: return mate.inventory.slots[&"backpack"] == pack, 8.0), "Pick packs up: and back on (%s)" % mate.ai_status)
		var decoy := _world_item(decoy_uid)
		check(had_own and mate.inventory.state_of(&"backpack").get("test_serial", "") == "own" and decoy != null,
			"his own pack, not a same-model one lying closer to where his went down (wears %s; the other %s)"
			% [mate.inventory.state_of(&"backpack").get("test_serial", "?"), "still there" if decoy else "gone"])
		# And one somebody has taken meanwhile: the order ends, nobody else's pack goes on instead.
		squad.order_command(player, "drop_packs", Vector3.ZERO, names)
		var taken := mate_ai._dropped_pack_item()
		var had_taken := taken != null
		var taken_state: Dictionary = taken.state.duplicate(true) if taken else {}
		if taken:
			GameState.item_taken(taken.uid)
			taken.queue_free()
		await _frames(1)
		squad.order_command(player, "pick_packs", Vector3.ZERO, names)
		await _seconds(1.0)
		var decoy_left := _world_item(decoy_uid) != null
		check(had_taken and mate_ai.dropped_pack.is_empty() and mate_ai.ordered.is_empty() and mate.inventory.slots[&"backpack"] == &"" and decoy_left,
			"Pick packs up with his pack gone: the order ends and he leaves the other pack alone (%s; %s; wears %s; the other %s)"
			% [mate.ai_status, mate_ai.ordered, mate.inventory.slots[&"backpack"], "still there" if decoy_left else "gone"])
		mate.inventory.take(pack, 1, taken_state)  # back on, for what follows
		decoy = _world_item(decoy_uid)
		if decoy:
			GameState.item_taken(decoy.uid)
			decoy.queue_free()

	# Give me ammo: the nearest who carries the player's magazines brings some.
	player.inventory.take(&"assault_pack")  # somewhere to put them
	var ammo := Soldier._ammo_of(player.active_weapon()) if player.active_weapon() else &""
	var had := player.inventory.count_of(ammo)
	var why := squad.order_command(player, "give_ammo", Vector3.ZERO) if ammo != &"" else "no rifle"
	var bringer: SquadAI = null
	for s: Soldier in _squad():
		if StringName(SquadAI.of(s).ordered.get("kind", &"")) == &"give_ammo":
			bringer = SquadAI.of(s)
	var status := "%s %s" % [bringer.body.name, bringer.ordered] if bringer else "nobody"
	check(why == "" and await _wait_until(func() -> bool:
			if bringer:
				status = "%s: %s, %.1f m off, %s" % [bringer.body.name, bringer.body.ai_status, _flat(bringer.body.global_position, player.global_position), bringer.ordered]
			return player.inventory.count_of(ammo) > had, 10.0),
		"Give me ammo: a squadmate brings magazines (%s; %d -> %d; %s)" % [why, had, player.inventory.count_of(ammo), status])
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position)


## Audit A3-07: a doctrine acts through its id only (SquadTactics' option biases); its numbers
## aren't wired into the AI yet, and say so. Every number a profile holds is listed pending in
## the code and the file alike, so tuning one can't pass for working gameplay: wiring one in
## means taking it off both lists, with a check of what it now does.
func _test_doctrine_pending() -> void:
	print("Doctrines: the id acts, the numbers are pending")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Doctrine.PATH))
	var pending: Array = file.get("_pending", [])
	var unmarked: Array[String] = []
	for id: StringName in Doctrine.ids():
		for key: String in (file.doctrines[String(id)] as Dictionary):
			if key != "name" and not (key in Doctrine.PENDING and key in pending):
				unmarked.append("%s.%s" % [id, key])
	check(not Doctrine.ids().is_empty() and unmarked.is_empty() and pending.size() == Doctrine.PENDING.size() and String(file.get("_notes", "")).begins_with("PENDING"),
		"every doctrine number is marked pending, in the code and the file (unmarked: %s)" % [unmarked])
	var sit := {"up": 6, "down": 1, "contact": true, "known": 3, "fresh": true, "stale": false, "cluster": {"centre": Vector3.ZERO},
		"range": 80.0, "enemy_building": {}, "home_building": {}, "in_home": false, "suppression": 0.1, "morale": 0.9, "ammo": 0.9,
		"cover": 0.6, "order": Squad.Order.FOLLOW, "weapons_free": true, "age": 1.0}
	var pmc: Dictionary = SquadTactics.score(sit, SquadTactics.DOCTRINES[Doctrine.PMC]).scores
	var insurgent: Dictionary = SquadTactics.score(sit, SquadTactics.DOCTRINES[Doctrine.INSURGENT]).scores
	check(float(pmc.get(SquadTactics.Option.CASUALTY, 0.0)) > float(insurgent.get(SquadTactics.Option.CASUALTY, 0.0)),
		"what does act: the same fight scores differently for a PMC squad and an insurgent one (casualty care %.2f vs %.2f)"
		% [float(pmc.get(SquadTactics.Option.CASUALTY, 0.0)), float(insurgent.get(SquadTactics.Option.CASUALTY, 0.0))])


## Audit A3-04: the building scan cache belongs to one world (and level). The compound's main
## building is found where it stands; another world with only an open floor at the same
## coordinates (as the next zone would be) must not be handed that building from the cache.
func _test_buildings_per_world() -> void:
	print("Buildings: one world's scans stay in it")
	var inside := Vector3(-3, 0.1, -6)  # in the main building
	var here := Buildings.at(player, inside)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var other := Node3D.new()
	viewport.add_child(other)
	var mesh := NavigationMesh.new()
	mesh.set_vertices(PackedVector3Array([Vector3(-12, 0, -14), Vector3(-12, 0, 2), Vector3(6, 0, 2), Vector3(6, 0, -14)]))
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var floor_region := NavigationRegion3D.new()
	floor_region.navigation_mesh = mesh
	other.add_child(floor_region)
	await _frames(4)
	var there := Buildings.at(other, inside)
	var again := Buildings.at(player, inside)
	check(not here.is_empty() and there.is_empty() and not again.is_empty(),
		"the main building is found in the compound (%d spots); an open floor at the same spot in another world has none (%d); the compound's is still found"
		% [(here.get("spots", []) as Array).size(), (there.get("spots", []) as Array).size()])
	viewport.queue_free()
	await _frames(2)


## ZoneScatter.foliage_between on made-up lines: through a bush, over it, past it, through a
## crown, and not through the open space under the crown.
func _test_foliage_lines() -> void:
	var sc := _scatter_with([
		{"kind": ZoneScatter.Kind.SCRUB, "pos": Vector3(0, 0, 0), "size": Vector3(1.4, 1.2, 1.4)},
		{"kind": ZoneScatter.Kind.TREE, "pos": Vector3(20, 0, 0), "size": Vector3(1, 1, 1)},
	])
	var through := sc.foliage_between(Vector3(0, 0.3, -20), Vector3(0, 0.3, 20))
	var over := sc.foliage_between(Vector3(0, 1.6, -20), Vector3(0, 1.6, 20))
	var past := sc.foliage_between(Vector3(3, 0.3, -20), Vector3(3, 0.3, 20))
	var crown := sc.foliage_between(Vector3(20, 3.0, -20), Vector3(20, 3.0, 20))
	var under := sc.foliage_between(Vector3(20, 1.0, -20), Vector3(20, 1.0, 20))
	check(is_equal_approx(through, 1.4) and over == 0.0 and past == 0.0 and crown > 2.0 and under == 0.0,
		"foliage lines: %.2f m through a bush, none over or past it, %.1f m through a crown, none under it" % [through, crown])
	sc.free()


## A ZoneScatter holding just `items` (on a made-up 2 km terrain), for foliage checks.
func _scatter_with(items: Array) -> ZoneScatter:
	var sc := ZoneScatter.new()
	var terrain := ZoneTerrain.new()
	terrain.size_m = 2048.0
	sc._terrain = terrain
	sc.add_child(terrain)
	for item: Dictionary in items:
		var p: Vector3 = item.pos
		var cell := sc._cell_of(p.x, p.z)
		if not sc._cells.has(cell):
			sc._cells[cell] = []
		(sc._cells[cell] as Array).append(sc.items.size())
		sc.items.append(item)
	return sc


# --- Helpers --------------------------------------------------------------

func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s.faction == &"friendly" and not s.is_queued_for_deletion())


## Captain (P0164 queue 17, part 1): spotting takes time, more for the far, the hidden and
## the unseen; a muzzle flash gives a shooter away. Staged in one frame with two squadmates
## (Spotting doesn't care whose side they're on).
func _test_spotting() -> void:
	print("Spotting: awareness builds over time")
	var alpha := _ai("Alpha")
	var bravo := _ai("Bravo") if _ai("Bravo") else _ai("Charlie")
	var saved := [alpha.global_transform, bravo.global_transform]
	var now := Soldier._now()
	alpha.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 30))  # faces -z
	bravo.velocity = Vector3.ZERO
	bravo.last_shot_at = -1000.0
	_place(bravo, Vector3(0, 0.1, 10))
	var near := Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now)
	_place(bravo, Vector3(0, 0.1, -50))
	var far := Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now)
	check(near > 0.0 and far > near * 2.0, "farther takes longer: 20 m %.1f s, 80 m %.1f s" % [near, far])
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.6, true, now) > far * 1.5, "a suppressed observer is slower")
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.1, false, now) > far, "and an unskilled one")
	bravo.last_shot_at = now
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now) < far * 0.3, "a muzzle flash gives a shooter away")
	bravo.last_shot_suppressed = true
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now) > far * 0.3, "less so through a suppressor")
	bravo.last_shot_at = -1000.0
	bravo.last_shot_suppressed = false
	alpha.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), alpha.global_position)  # faces away
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now) > far * 2.0, "someone outside the view cone is much slower to spot")
	check(Spotting.camo("woodland", "temperate") > Spotting.camo("woodland", "desert_wadi") and Spotting.camo("desert", "desert_wadi") > Spotting.camo("desert", "temperate"),
		"camo that matches the terrain hides better")
	# The spotter module (Captain, 2026-10-13): the camo matrix complete, worked out from the
	# colours: every uniform on every terrain preset, and plain clothes too.
	var matrix := ""
	var in_range := true
	for preset in TerrainPresets.ids():
		matrix += "\n    %-17s" % preset
		for variant: String in Soldier.PLAYER_VARIANTS:
			var f := Spotting.camo(variant, String(preset))
			in_range = in_range and f >= Spotting.CAMO_MIN and f <= Spotting.CAMO_MAX
			matrix += " %s %.2f" % [variant, f]
	print("  camo (above 1 hides, below 1 stands out):" + matrix)
	check(in_range and TerrainPresets.ids().size() >= 8, "every uniform has a camo factor on every terrain preset (%d)" % TerrainPresets.ids().size())
	check(Spotting.camo("woodland", "temperate") > Spotting.camo("woodland", "salt_flats") and Spotting.camo("desert", "salt_flats") > Spotting.camo("desert", "temperate")
		and Spotting.camo("multicam", "temperate") > Spotting.camo("urban", "temperate"),
		"woodland hides in green hills, not on the salt flats; desert the other way; grey urban stands out in the hills")
	var robe := PersonLook._variant("e8e4d8", "e8e4d8", "c8996f", "6b4a2b")
	check(Spotting.camo(robe, "salt_flats") > Spotting.camo(robe, "temperate") and Spotting.camo(robe, "temperate") < Spotting.camo("woodland", "temperate"),
		"plain clothes too: a white robe blends on the salt flats (%.2f), stands out in green hills (%.2f)" % [Spotting.camo(robe, "salt_flats"), Spotting.camo(robe, "temperate")])
	# Each soldier's own camo reaches the spot time.
	var own := String(bravo.model.variant)
	var other := "desert" if own != "desert" else "woodland"
	var with_own := Spotting.spot_seconds(alpha, bravo, "temperate", 0.6, false, now)
	bravo.model.variant = other
	var with_other := Spotting.spot_seconds(alpha, bravo, "temperate", 0.6, false, now)
	bravo.model.variant = own
	check(absf(with_other / with_own - Spotting.camo(other, "temperate") / Spotting.camo(own, "temperate")) < 0.01,
		"the soldier's own camo (%s) is what's scored: %.1f s, in %s %.1f s" % [own, with_own, other, with_other])
	# Optics: past OPTIC_FROM_M the rifle's sight, and binoculars when calm, shorten the distance.
	alpha.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 30))
	_place(bravo, Vector3(0, 0.1, -270))
	var had_binos := alpha.inventory.count_of(&"binoculars") > 0
	if not had_binos:
		alpha.inventory.take(&"binoculars")
	var busy_s := Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now, 0.0, false)
	var calm_s := Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now, 0.0, true)
	check(Spotting.optic_x(alpha, false) > 1.0 and calm_s < busy_s * 0.75 and alpha.inventory.count_of(&"binoculars") > 0,
		"at 300 m the rifle sight helps (x%.2f, %.1f s) and binoculars more when calm (x%.2f, %.1f s)" % [Spotting.optic_x(alpha, false), busy_s, Spotting.optic_x(alpha, true), calm_s])
	if not had_binos:
		alpha.inventory.remove_one(&"binoculars")
	_place(bravo, Vector3(0, 0.1, -50))
	alpha.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), alpha.global_position)
	# Foliage: leaves in the way slow a spot down, and enough hide someone.
	check(Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now, 1.0) > Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now) * 3.0
		and Spotting.spot_seconds(alpha, bravo, "plain", 0.6, false, now, Spotting.FOLIAGE_OPAQUE_M) == INF,
		"a metre of leaves in the way slows a spot down; %.1f m hides them" % Spotting.FOLIAGE_OPAQUE_M)
	_test_foliage_lines()
	# Through SquadAI: no instant target, a few scans first.
	alpha.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 30))
	var ai := SquadAI.of(alpha)
	ai._aware.clear()
	var scans := 0
	while ai._build_awareness(bravo) < 1.0 and scans < 200:
		scans += 1
	check(scans >= 2 and scans <= ceili(far / SquadAI.SCAN_S) + 1, "awareness builds over %d scans (%.1f s at 80 m)" % [scans + 1, (scans + 1) * SquadAI.SCAN_S])
	# Hearing (part 2): a heard shot half finds the shooter, never fully; then sight is quicker.
	ai._aware.clear()
	for i in 5:
		ai.hear(bravo, bravo.global_position, Spotting.HEARD_SHOT)
	check(is_equal_approx(float(ai._aware[bravo.get_instance_id()]), Spotting.HEARD_MAX) and ai.suspecting(), "shots heard: suspected, awareness capped at %.1f" % Spotting.HEARD_MAX)
	var after := 0
	while ai._build_awareness(bravo) < 1.0 and after < 200:
		after += 1
	check(after < scans, "and seen, he's spotted sooner (%d scans, not %d)" % [after + 1, scans + 1])
	# (Measured standing: a squadmate at a halt in Combat mode crouches, and crouched steps are quiet.)
	var brain := SquadAI.of(bravo)
	brain.process_mode = Node.PROCESS_MODE_DISABLED
	bravo.want_crouch = false
	bravo.want_stance = -1
	await _wait_until(func() -> bool: return not bravo.is_crouching(), 3.0)
	bravo.velocity = Vector3(0, 0, 4.0)
	var running := Spotting.footsteps_m(bravo)
	bravo.velocity = Vector3(0, 0, 1.5)
	var walking := Spotting.footsteps_m(bravo)
	bravo.velocity = Vector3.ZERO
	check(running > walking and walking > 0.0 and Spotting.footsteps_m(bravo) == 0.0, "footsteps carry %.0f m running, %.0f m walking, none standing still" % [running, walking])
	# Foliage on real bodies: a bush between them hides Bravo prone, not standing (his head
	# shows over it). A made-up scatter: the compound has none.
	var bush := _scatter_with([{"kind": ZoneScatter.Kind.SCRUB, "pos": Vector3(0, 0.1, -48.0), "size": Vector3(1.5, 1.35, 1.5)}])
	alpha.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 30))
	var standing_leaves := Spotting.foliage_m(bush, alpha, bravo)
	bravo.want_stance = SoldierMovement.Stance.PRONE
	await _wait_until(func() -> bool: return bravo.movement.is_prone(), 3.0)
	await get_tree().create_timer(0.6).timeout  # the eyes settle down
	var prone_leaves := Spotting.foliage_m(bush, alpha, bravo)
	check(bravo.movement.is_prone() and standing_leaves < 0.2 and prone_leaves >= Spotting.FOLIAGE_OPAQUE_M,
		"a bush hides him prone (%.1f m of leaves), not standing (%.1f m: his head shows)" % [prone_leaves, standing_leaves])
	bravo.want_stance = -1
	bush.free()
	brain.process_mode = Node.PROCESS_MODE_INHERIT
	ai._aware.clear()
	ai._suspect_at = -1000.0
	alpha.global_transform = saved[0]
	bravo.global_transform = saved[1]
	# Morale (part 4): suppression drags it down; broken in contact on Follow, he falls back.
	var calm := ai.morale_target()
	alpha.suppression = 1.0
	var pinned := ai.morale_target()
	check(pinned < calm - 0.2, "suppression drags morale down (%.2f -> %.2f)" % [calm, pinned])
	alpha.suppression = 0.0
	var steady := ai.morale
	ai.morale = 0.1
	alpha.threat_pos = alpha.global_position + Vector3(0, 0, -30)
	alpha.threat_time = Soldier._now()
	ai._last_contact = Soldier._now()
	var order_was := ai.order
	ai.order = Squad.Order.FOLLOW
	ai._choose_intent()
	ai._choose_intent()
	check(ai.broken() and ai.intent == SquadAI.Intent.FALL_BACK, "broken in contact on Follow, he falls back (%s)" % ai.status_text())
	ai.order = Squad.Order.HOLD
	ai._choose_intent()
	ai._choose_intent()
	check(ai.intent != SquadAI.Intent.FALL_BACK, "but a Hold order wins (%s)" % ai.status_text())
	ai.order = order_was
	ai.morale = steady
	ai._fall_back_point = null
	_clear_contact()


## Captain (P0164 queue 17, part 5): fire discipline. No round through or past a squadmate:
## the clearance grows down the line with the rounds' spread, someone past the target counts,
## someone prone counts where he lies, someone beside the shooter doesn't. Frags: nobody near
## where it lands or under its arc. Launchers: nobody in the backblast. Staged in one frame
## at a time.
func _test_fire_discipline() -> void:
	print("Fire discipline: the line of fire, past the target, frags and backblast")
	var alpha := _ai("Alpha")
	var bravo := _standing_mate([alpha])  # (whoever the fights so far left up and on his feet)
	var ai := SquadAI.of(alpha)
	var saved := [alpha.global_transform, bravo.global_transform]
	bravo.want_stance = SoldierMovement.Stance.PRONE
	var prone := await _wait_until(func() -> bool: return bravo.movement.is_prone(), 4.0)
	await _seconds(0.5)  # the hit boxes follow the pose down
	var origin := Vector3(300, 50.1, 300)  # up and away from everyone: only Bravo near the lines
	alpha.global_transform = Transform3D(Basis.IDENTITY, origin)  # faces -z
	var eye := alpha.camera.global_position
	var aim := eye + Vector3(0, -0.4, -30)  # someone 30 m off
	var away := Vector3(500, 50.1, 500)
	_place(bravo, away)
	check(not ai._friendly_in_line(aim), "nobody near the line: free to fire")
	var widen := tan(ai._fire_cone())
	_place(bravo, origin + Vector3(1.5, 0, -25))
	var far_off := ai._friendly_in_line(aim)
	_place(bravo, origin + Vector3(1.5, 0, -3))
	var near_off := ai._friendly_in_line(aim)
	check(prone and far_off and not near_off, "1.5 m off the line: in it 25 m out (clearance %.1f m), clear 3 m out (%.1f m)" % [
		SquadAI.FRIENDLY_CLEARANCE + 25.0 * widen, SquadAI.FRIENDLY_CLEARANCE + 3.0 * widen])
	_place(bravo, origin + Vector3(0, 0, -50))
	check(ai._friendly_in_line(aim), "a squadmate 20 m past the target: rounds that miss fly on, no shot")
	_place(bravo, origin + Vector3(0, 0, -90 - SquadAI.DOWNRANGE_M))
	check(not ai._friendly_in_line(aim), "far beyond that, the shot is free again")
	_place(bravo, origin + Vector3(0.6, 0, 0.2))
	check(not ai._friendly_in_line(aim), "a squadmate beside the shooter isn't in the line")
	_place(bravo, origin + Vector3(0, 0, -29))
	var low := bravo.aim_point().y - bravo.global_position.y
	check(SquadAI._lying(bravo) and low < 0.8 and ai._friendly_in_line(aim + Vector3.DOWN * 1.0),
		"prone just short of a prone target, he counts where he lies (chest %.2f m up)" % low)
	# Frags: where it lands, and the arc's low start in front of the thrower.
	var from := eye + Vector3.UP * 0.2
	var at := origin + Vector3(0, 0, -15)
	_place(bravo, away)
	var clear := ai._frag_safe(from, at)
	_place(bravo, at + Vector3(Throwables.FRAG_RADIUS + 1.0, 0, 0))
	var near_blast := ai._frag_safe(from, at)
	_place(bravo, at + Vector3(Throwables.FRAG_RADIUS + SquadAI.FRAG_SAFETY_M + 3.0, 0, 0))
	var outside := ai._frag_safe(from, at)
	check(clear and not near_blast and outside, "a frag: not with a squadmate within %.0f m of where it lands" % (Throwables.FRAG_RADIUS + SquadAI.FRAG_SAFETY_M))
	bravo.want_stance = -1
	alpha.global_transform = saved[0]  # back on the ground while he gets up
	bravo.global_transform = saved[1]
	await _wait_until(func() -> bool: return not bravo.movement.is_prone(), 4.0)
	alpha.global_transform = Transform3D(Basis.IDENTITY, origin)
	var far_at := origin + Vector3(0, 0, -20)
	_place(bravo, origin + Vector3(0, 0, -1.2))
	var in_front := ai._frag_safe(from, far_at)
	_place(bravo, origin + Vector3(0, 0, -9))
	var under_top := ai._frag_safe(from, far_at)
	_place(bravo, origin + Vector3(0.6, 0, 0))
	var beside := ai._frag_safe(from, far_at)
	check(not in_front and under_top and beside, "nor with one right in front, in the arc's way; one under its peak or beside the thrower is fine")
	# Launcher backblast (RPG-7: a 45 degree cone, 20 m of injury).
	var rpg := ItemDB.get_item(&"rpg7")
	_place(bravo, origin + Vector3(0, 0, 4))
	var behind := LauncherAI.friend_in_backblast(alpha, rpg)
	_place(bravo, origin + Vector3(0, 0, -4))
	var ahead := LauncherAI.friend_in_backblast(alpha, rpg)
	_place(bravo, origin + Vector3(8, 0, 2))
	var aside := LauncherAI.friend_in_backblast(alpha, rpg)
	check(behind and not ahead and not aside, "no rocket with a squadmate in the backblast (behind %s, ahead %s, off to the side %s)" % [behind, ahead, aside])
	alpha.global_transform = saved[0]
	bravo.global_transform = saved[1]
	_clear_contact()


## A squadmate (not one of `besides`) who is up, not carrying or carried, and not busy with a
## casualty: the staged checks move him about.
func _standing_mate(besides: Array) -> Soldier:
	for s: Soldier in _squad():
		var ai := SquadAI.of(s)
		if s not in besides and s.vitals.is_up() and s.carrying == null and not is_instance_valid(s.carried_by) and ai.care == SquadAI.Care.NONE:
			return s
	return _ai("Bravo")


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _world_item(uid: String) -> WorldItem:
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if n is WorldItem and (n as WorldItem).uid == uid and uid != "" and not n.is_queued_for_deletion():
			return n
	return null


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


## Waits until `n` physics steps have begun, so at least n - 1 have run in full (every AI's
## _physics_process included).
func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
