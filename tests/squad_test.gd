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
	_clear_contact()  # anyone glimpsed before they were removed (friendlies see SquadAI.SQUAD_SIGHT_RANGE, 300 m)
	await _test_roster()
	_test_command_menu()
	_test_navigation()
	await _test_follow()
	await _test_formation_orders()
	await _test_exo_pilot()
	_test_distinct_cover()
	await _test_senses()
	await _test_buddy_carries_buddy()
	await _test_contact()
	_test_flash_stuns()
	await _test_fire_fix()
	await _test_spotting()
	await _test_fire_discipline()
	await _test_no_fire_into_walls()
	await _test_close_range_aim()
	await _test_tactics()
	_test_doctrine_pending()
	await _test_doctrine_ranges()
	await _test_dead_leave_squad()
	await _test_buildings_per_world()
	await _test_buildings_raised_any_order()
	await _test_multi_storey()
	await _test_human_team_lead()
	GameState.delete_save()
	print("SQUAD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## AI bar G-03: rounds cracking past give the shooter's direction well and his range badly,
## better as he keeps firing from the same spot; a blast is exact.
func _test_fire_fix() -> void:
	print("Fixing a shooter from his fire")
	var alpha := _ai("Alpha")
	var keep := [alpha.threat_pos, alpha.threat_time, alpha.threat_err, alpha.suppression]
	var from := alpha.global_position + Vector3(0, 1.5, -200)
	alpha.threat_err = 0.0
	alpha.threat_time = -1000.0
	alpha.suppress_fire(0.05, from)
	var to := Vector3(alpha.threat_pos.x - alpha.global_position.x, 0, alpha.threat_pos.z - alpha.global_position.z)
	var first := alpha.threat_err
	check(first > 10.0 and to.normalized().dot(Vector3.FORWARD) > 0.97, "one crack: the right way, a rough range (+-%.0f m, %.0f m out)" % [first, to.length()])
	for i in 6:
		alpha.suppress_fire(0.0, from + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
	check(alpha.threat_err < first * 0.5, "he keeps firing from there: placed better (+-%.0f m)" % alpha.threat_err)
	alpha.suppress(0.0, from)
	check(alpha.threat_err == 0.0 and alpha.threat_pos == from, "a blast: exact")
	alpha.threat_pos = keep[0]
	alpha.threat_time = keep[1]
	alpha.threat_err = keep[2]
	alpha.suppression = keep[3]
	# G-27: the reach goes with the weapon and its optic; past HOLDOVER_FROM_M they hold over.
	var m4 := ItemDB.get_item(&"m4a1")
	var reach := SquadAI.reach_m(player)
	print("    player reach %.0f m with %s" % [reach, player.active_weapon().id if player.active_weapon() else "nothing"])
	check(reach >= SquadAI.REACH_IRONS_M and reach <= SquadAI.REACH_MAX_M, "a rifle's reach goes by its optic (%.0f m)" % reach)
	var d300 := Ballistics.drop_m(m4, 300.0)
	var d500 := Ballistics.drop_m(m4, 500.0)
	check(absf(Ballistics.drop_m(m4, Ballistics.ZERO_M)) < 0.05 and d300 > 0.1 and d500 > d300, "the round drops past its zero (%.2f m at 300, %.2f m at 500)" % [d300, d500])
	# G-05: getting down on his own: prone to fire at a man far off in the open, not at one close in,
	# not on the move, not when ordered a stance.
	var bravo_ai := SquadAI.of(_ai("Bravo"))
	var bravo := bravo_ai.body
	var foe_far := level.spawn_soldier({"name": "ProneFoeFar", "faction": "hostile", "variant": "urban",
		"pos": bravo.global_position + Vector3(0, 0, -140), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(2)
	SquadAI.of(foe_far).process_mode = Node.PROCESS_MODE_DISABLED
	var keep_target := bravo_ai.target
	var keep_dest := bravo_ai._has_destination
	var keep_order := bravo_ai.stance_order
	bravo_ai.target = foe_far
	bravo_ai._has_destination = false
	bravo_ai.stance_order = -1
	bravo_ai._stance_at = -1000.0
	var far_line := Throwables.clear_line(bravo.get_world_3d(), bravo.global_position + Vector3.UP * SquadAI.PRONE_EYE_M, foe_far.aim_point())
	var far := bravo_ai._auto_stance()
	check(far == SoldierMovement.Stance.PRONE or not far_line, "an enemy 140 m off in the open, a line lying down: he goes prone (%d, line %s)" % [far, far_line])
	foe_far.global_position = bravo.global_position + Vector3(0, 0, -12)
	bravo_ai._stance_at = -1000.0
	check(bravo_ai._auto_stance() == -1, "12 m off: he stays up, ready to move")
	foe_far.global_position = bravo.global_position + Vector3(0, 0, -140)
	bravo_ai._has_destination = true
	bravo_ai._stance_at = -1000.0
	check(bravo_ai._auto_stance() == -1, "on the move: on his feet")
	bravo_ai.target = keep_target
	bravo_ai._has_destination = keep_dest
	bravo_ai.stance_order = keep_order
	bravo_ai._auto_prone = false
	bravo.want_stance = -1
	# G-07: a round cracks close in the open with nothing near to hide behind: he drops flat at once.
	bravo_ai._fire_react_at = -1000.0
	bravo_ai._has_cover = false
	bravo.threat_pos = bravo.global_position + Vector3(0, 0, -140)
	bravo_ai.react_to_fire(0.3)
	var reacted := bravo_ai._react_until > Soldier._now() or bravo_ai._has_destination
	check(reacted, "a near miss in the open: he drops flat or dashes for cover (flat %s, dash %s)" % [bravo_ai._react_until > Soldier._now(), bravo_ai._has_destination])
	var again := bravo_ai._fire_react_at
	bravo_ai.react_to_fire(0.3)
	check(bravo_ai._fire_react_at == again, "and not again a moment later")
	bravo_ai._react_until = -1000.0
	bravo_ai._fire_react_at = -1000.0
	bravo_ai._auto_prone = false
	bravo_ai._has_destination = keep_dest
	bravo.want_stance = -1
	foe_far.queue_free()
	# G-17: high ground with a line scores better than low; out of another group's sight better still.
	var world := player.get_world_3d()
	var up_high := player.global_position + Vector3(0, 40, 0)
	var enemy := up_high + Vector3(0, -6, -60)
	var low := SquadTactics.overwatch_score(world, enemy + Vector3(0, 0, 50), up_high, enemy, [])
	var high := SquadTactics.overwatch_score(world, up_high, up_high, enemy, [])
	var seen := SquadTactics.overwatch_score(world, up_high, up_high, enemy, [up_high + Vector3(40, 0, 0)])
	check(high < low and seen > high, "overwatch: height over him scores (%.1f high, %.1f level, %.1f in another group's sight)" % [high, low, seen])


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
	squad.formation = Squad.DYNAMIC
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


## Formation and spacing (Captain, 2026-10-14: "ai are bunching up after a while in mission",
## then "so long as I can set them to be dynamic"): Dynamic picks tighter in a town than in the
## open; a spacing order spreads the slots and is acknowledged; a fire team's own formation
## order leaves the other team's alone; the HUD shows it.
func _test_formation_orders() -> void:
	print("Formation and spacing orders")
	var squad := level.squad_for(&"friendly")
	squad._update_context()
	var town: Dictionary = squad.context.duplicate()
	_place(player, Vector3(0, 0.1, 45))  # open ground north of the compound
	squad._update_context()
	var open: Dictionary = squad.context.duplicate()
	check(town.spacing == "tight" and open.spacing == "normal" and float(Squad.SPACINGS[town.spacing].man) < float(Squad.SPACINGS[open.spacing].man),
		"Dynamic: tighter in the town (%s, %s) than in the open (%s, %s)" % [town.spacing, town.why, open.spacing, open.why])
	check(town.formation == "staggered column" and open.formation == "wedge", "a staggered column in the town, a wedge in the open (%s, %s)" % [town.formation, open.formation])
	var alpha := _ai("Alpha")
	var bravo := _ai("Bravo")
	var before := _flat(squad.follow_point(alpha), squad.follow_point(bravo))
	var said_from: int = level.callouts.sent.size()
	check(squad.command(player, "spacing:wide", player.global_position), "Spacing > Wide is an order")
	var wide := _flat(squad.follow_point(alpha), squad.follow_point(bravo))
	check(squad.spacing == "wide" and wide > before * 1.3, "it spreads the slots (Alpha to Bravo %.1f m, was %.1f m)" % [wide, before])
	var acks := level.callouts.sent.slice(said_from).filter(func(l: Dictionary) -> bool: return String(l.text).begins_with("Copy,") and String(l.text).contains("wide"))
	check(not acks.is_empty(), "and is acknowledged (%s)" % [level.callouts.sent.slice(said_from).map(func(l: Dictionary) -> String: return String(l.text))])
	check(not squad.command(player, "spacing:huge", player.global_position) and not squad.command(player, "formation:blob", player.global_position), "nonsense isn't an order")
	var team_b := PackedStringArray()
	for s: Soldier in _squad():
		if s.fire_team == 1:
			team_b.append(String(s.name))
	check(squad.command(player, "formation:file", player.global_position, team_b), "team B alone: Formation > File")
	check(squad.ordered_formation(1) == "file" and squad.ordered_formation(0) == Squad.DYNAMIC, "team B takes it, team A keeps its own (%s, %s)" % [squad.ordered_formation(1), squad.ordered_formation(0)])
	var right := squad.heading.cross(Vector3.UP).normalized()
	var across: Array = Array(team_b).map(func(n: String) -> float: return (squad.follow_point(_ai(n)) - player.global_position).dot(right))
	check(across.max() - across.min() < 2.5, "team B's slots in single file (across %.1f m)" % (across.max() - across.min()))
	await _seconds(0.3)
	var echo := _ai("Echo")
	check(echo.ai_status.contains("file") and alpha.ai_status.contains("dynamic"), "the squad HUD shows it (%s; %s)" % [echo.ai_status, alpha.ai_status])
	check(squad.command(player, "formation:dynamic", player.global_position) and squad.command(player, "spacing:dynamic", player.global_position)
		and squad.ordered_formation(1) == Squad.DYNAMIC and squad.ordered_spacing(0) == Squad.DYNAMIC, "the whole squad back to Dynamic clears team B's order")
	_place(player, Vector3(0, 0.1, 12))
	await _seconds(12.0)


## AI pilots for the HX-1 (Captain, 2026-10-17/18): "Climb into the HX-1" sends a squadmate to
## a parked suit and in; "Climb out of the suit" puts him back on his feet beside it.
func _test_exo_pilot() -> void:
	print("AI HX-1 pilot")
	var echo := _ai("Echo")
	var squad := level.squad_for(&"friendly")
	check(squad.order_command(player, "exo_in", player.global_position, PackedStringArray(["Echo"])) != "", "no suit about: the order says so")
	var uid := level.server_spawn_dropped(&"exo_mech_heavy", 1, echo.global_position + Vector3(9, ExoMech.PARKED_SIZE.y * 0.5, 0), {"open": false})
	await _frames(3)
	check(squad.order_command(player, "exo_in", player.global_position, PackedStringArray(["Echo"])) == "", "Climb into the HX-1: Echo goes")
	var in_suit := await _wait_until(func() -> bool: return ExoMech.piloting(echo.inventory) and not ExoMech.transitioning(echo), 25.0)
	check(in_suit, "walks to it and climbs in (%s)" % echo.ai_status)
	check(squad.order_command(player, "exo_out", player.global_position, PackedStringArray(["Echo"])) == "", "Climb out of the suit")
	var out := await _wait_until(func() -> bool: return not ExoMech.piloting(echo.inventory) and not ExoMech.transitioning(echo), 8.0)
	check(out, "and he's out, the suit left standing")
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var w := n as WorldItem
		if w and (w.item_id == &"exo_mech_heavy" or w.uid == uid):
			GameState.item_taken(w.uid)
			w.queue_free()
	_place(echo, player.global_position + Vector3(2, 0.1, -2))
	await _frames(5)


## No two squadmates pick the same cover from the same spot (Captain, 2026-10-14: they bunched up).
func _test_distinct_cover() -> void:
	print("Distinct cover")
	var a := SquadAI.of(_ai("Alpha"))
	var b := SquadAI.of(_ai("Bravo"))
	var anchor := a.body.global_position
	var threat := anchor + Vector3(0, 0, -15)
	a.body.threat_pos = threat
	b.body.threat_pos = threat
	b._has_cover = false
	a._has_cover = false
	var first: Variant = a.find_cover(anchor, 10.0)
	if first != null:
		a._cover_point = first
		a._has_cover = true
	var second: Variant = b.find_cover(anchor, 10.0)
	check(first != null and second != null and _flat(first, second) >= SquadAI.COVER_GAP_M,
		"from the same spot, two squadmates take cover %.1f m apart" % (_flat(first, second) if first != null and second != null else -1.0))
	a._has_cover = false


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
	for s: Soldier in _squad():
		if s not in spots:
			print("    %s at %s, halt spot %s, slot %s, %s" % [s.name, s.global_position, SquadAI.of(s)._halt_spot, squad.follow_point(s), s.ai_status])
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
	# Captain, 2026-10-14: "Stop bringing casualties" did nothing visible. Now it stands: the
	# carrier lays him down where he is and stays with him, and nobody lifts him again until
	# "Bring casualties" (or a move order).
	var squad := level.squad_for(&"friendly")
	var said_from: int = level.callouts.sent.size()
	check(squad.order_command(player, "ccp_off", player.global_position) == "" and squad.hold_casualties, "Stop bringing casualties: the order stands")
	var laid := await _wait_until(func() -> bool: return bravo.carried_by == null, 3.0)
	await _seconds(0.5)
	var laid_at := bravo.global_position
	check(laid, "Charlie lays him down where he is (%s)" % charlie.ai_status)
	_place(player, Vector3(-8, 0.1, 34))  # the lead goes off: without the order he'd be carried along
	var lifted := await _wait_until(func() -> bool: return is_instance_valid(bravo.carried_by), 8.0)
	check(not lifted and _flat(bravo.global_position, laid_at) < 1.5, "and nobody lifts him again while it stands (%s)"
		% (bravo.carried_by.ai_status if is_instance_valid(bravo.carried_by) else "he lies where he was put"))
	check(SquadAI.of(charlie).casualty == bravo, "Charlie stays with him (%s)" % charlie.ai_status)
	var said := level.callouts.sent.slice(mini(said_from, level.callouts.sent.size())).any(
		func(l: Dictionary) -> bool: return l.speaker == "Charlie" and l.id == &"putting_down")
	check(said, "and says so")
	check(squad.order_command(player, "ccp_me", player.global_position) == "" and not squad.hold_casualties, "Bring casualties to me lifts it")
	var again := await _wait_until(func() -> bool: return is_instance_valid(bravo.carried_by), 10.0)
	check(again, "and he's carried again (%s)" % charlie.ai_status)
	squad.ccp = null
	bravo.vitals.server_reset_health()  # he comes round (the wound model decides when; the test stands in)
	var down := await _wait_until(func() -> bool: return bravo.carried_by == null and SquadAI.of(charlie).casualty == null, 5.0)
	check(down, "awake, he's put down and Charlie goes back to following (%s)" % charlie.ai_status)


func _test_contact() -> void:
	print("Contact")
	_place(player, Vector3(0, 0.1, 16))
	## The player stands in the open 17 m from the hostile (placed by hand, physics off) and
	## the hostile rightly shoots him too: unshielded, he went down here and stayed down for
	## every later check (R0612, R0864, R0925: Give me ammo with the player Unconscious, the
	## squad on casualty care for him). Shielded, the hostile still sees and fires at him;
	## his rounds just do nothing, so no wounds leak into what follows.
	player.vitals.shielded = true
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
	player.vitals.shielded = false
	check(player.vitals.condition_text() == "OK", "the player, shielded, comes out of it unhurt (%s)" % player.vitals.condition_text())


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
	# Captain, 2026-10-14: no reflex body-hauling. Long out of contact, nowhere to take him.
	for s: Soldier in _squad():
		SquadAI.of(s)._last_contact = -1000.0
	var hauled := await _wait_until(func() -> bool: return is_instance_valid(foxtrot.carried_by), 6.0)
	check(not hauled, "nobody carries his body off on reflex (%s)"
		% (foxtrot.carried_by.ai_status if is_instance_valid(foxtrot.carried_by) else "he lies where he fell"))
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
	# P0362: "base of fire ... no flank to take" every second while taking fire, sitting still.
	var keep := SquadTactics.MIN_KEEP_S
	check(not SquadTactics.switches(0.6, 0.75, keep * 0.4, false) and SquadTactics.switches(0.6, 0.75, keep, false),
		"a chosen tactic is held %.0f s against a somewhat better one" % keep)
	check(SquadTactics.switches(0.6, 0.6 + SquadTactics.URGENT_MARGIN, 1.0, false) and SquadTactics.switches(0.6, 0.75, 1.0, true)
		and SquadTactics.switches(-1.0, 0.3, 0.0, false), "unless the situation changes a lot: a much better option, someone else down, or it stops applying")
	var pinned := {"no_flank": true, "up": 4, "known": 4, "suppression": 0.35, "cover": 0.0}
	check(not SquadTactics.score(sit.merged({"no_flank": true}, true), pmc).scores.has(SquadTactics.Option.SUPPRESS_FLANK)
		and best.call({"no_flank": true}) == SquadTactics.Option.HOLD, "no flank to take, not out-shot: no drill, hold and improve cover")
	check(best.call(pinned) == SquadTactics.Option.BREAK_CONTACT and best.call(pinned.merged({"no_flank": false}, true)) != SquadTactics.Option.BREAK_CONTACT,
		"no flank to take and out-shot (P0362: 4 on 4, suppressed, nobody in cover): bound back to cover, not hold")

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
	## Down, he can't take magazines: a clear refusal, not an order the bringer drops on the way.
	player.vitals.downed = true
	var down_why := squad.order_command(player, "give_ammo", Vector3.ZERO) if ammo != &"" else "no rifle"
	player.vitals.downed = false
	check(down_why != "" and not _squad().any(func(s: Soldier) -> bool: return StringName(SquadAI.of(s).ordered.get("kind", &"")) == &"give_ammo"),
		"Give me ammo while down: refused, nobody sent (%s)" % down_why)
	var why := squad.order_command(player, "give_ammo", Vector3.ZERO) if ammo != &"" else "no rifle"
	var bringer: SquadAI = null
	for s: Soldier in _squad():
		if StringName(SquadAI.of(s).ordered.get("kind", &"")) == &"give_ammo":
			bringer = SquadAI.of(s)
	# An Array, so the lambda's update reaches the message (a captured local is a copy).
	var status: Array[String] = ["%s %s" % [bringer.body.name, bringer.ordered] if bringer else "nobody"]
	check(why == "" and await _wait_until(func() -> bool:
			if bringer:
				status[0] = "%s: %s, %.1f m off, moving %.1f m/s, target %s, intent %s, %s" % [bringer.body.name, bringer.body.ai_status,
					_flat(bringer.body.global_position, player.global_position), Vector2(bringer.body.velocity.x, bringer.body.velocity.z).length(),
					bringer.target.name if is_instance_valid(bringer.target) else "none", bringer.intent, bringer.ordered]
			return player.inventory.count_of(ammo) > had, 10.0),
		"Give me ammo: a squadmate brings magazines (%s; %d -> %d; %s; the player: %s)" % [why, had, player.inventory.count_of(ammo), status[0], player.vitals.condition_text()])
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
			if key != "name" and not (key in Doctrine.PENDING and key in pending) and not (key in Doctrine.WIRED and key in file.get("_wired", [])):
				unmarked.append("%s.%s" % [id, key])
	check(not Doctrine.ids().is_empty() and unmarked.is_empty() and pending.size() == Doctrine.PENDING.size() and String(file.get("_notes", "")).begins_with("PENDING"),
		"every doctrine number is marked pending or wired, in the code and the file (unmarked: %s)" % [unmarked])
	# G-09: bursts by range; machine guns keep theirs; doctrine scales them.
	var m4 := ItemDB.get_item(&"m4a1")
	var close := SquadAI.burst_rounds(m4, 15.0, false, Doctrine.REGULAR)
	var far := SquadAI.burst_rounds(m4, 250.0, false, Doctrine.REGULAR)
	var mg := SquadAI.burst_rounds(ItemDB.get_item(&"m249"), 250.0, false, Doctrine.REGULAR)
	check(close >= 3 and far == 1 and mg >= 3, "bursts by range: %d up close, %d far out; a machine gun still %d" % [close, far, mg])
	check(SquadAI.pause_mult(250.0, Doctrine.REGULAR) > SquadAI.pause_mult(20.0, Doctrine.REGULAR) * 1.5, "and the pauses longer far out")
	var ins := 0
	var pmc_n := 0
	for i in 40:
		ins += SquadAI.burst_rounds(m4, 15.0, false, Doctrine.INSURGENT)
		pmc_n += SquadAI.burst_rounds(m4, 15.0, false, Doctrine.PMC)
	check(ins > pmc_n, "insurgents fire longer bursts than the PMC (%d to %d rounds in 40)" % [ins, pmc_n])
	# G-11: suppression by round.
	var pistol := Ballistics.suppress_of(ItemDB.get_item(&"m17"))
	var rifle := Ballistics.suppress_of(m4)
	var heavy := Ballistics.suppress_of(ItemDB.get_item(&"m240b"))
	check(pistol.x < rifle.x and heavy.x > rifle.x and heavy.y > rifle.y, "suppression by round: pistol %.1f m, 5.56 %.1f m, 7.62 %.1f m (x%.1f)" % [pistol.x, rifle.x, heavy.x, heavy.y])
	var sit := {"up": 6, "down": 1, "contact": true, "known": 3, "fresh": true, "stale": false, "cluster": {"centre": Vector3.ZERO},
		"range": 80.0, "enemy_building": {}, "home_building": {}, "in_home": false, "suppression": 0.1, "morale": 0.9, "ammo": 0.9,
		"cover": 0.6, "order": Squad.Order.FOLLOW, "weapons_free": true, "age": 1.0}
	var pmc: Dictionary = SquadTactics.score(sit, SquadTactics.DOCTRINES[Doctrine.PMC]).scores
	var insurgent: Dictionary = SquadTactics.score(sit, SquadTactics.DOCTRINES[Doctrine.INSURGENT]).scores
	check(float(pmc.get(SquadTactics.Option.CASUALTY, 0.0)) > float(insurgent.get(SquadTactics.Option.CASUALTY, 0.0)),
		"what does act: the same fight scores differently for a PMC squad and an insurgent one (casualty care %.2f vs %.2f)"
		% [float(pmc.get(SquadTactics.Option.CASUALTY, 0.0)), float(insurgent.get(SquadTactics.Option.CASUALTY, 0.0))])


## Audit F-03: the doctrines' engage_m fits the sight ranges (hostiles SIGHT_RANGE, the squad
## SQUAD_SIGHT_RANGE): no doctrine engages past what its shooter can see, and none sits so far
## inside it that the AI spots targets it then won't engage. And the ranges act: a hostile picks
## a target he sees 180 m off (not one 310 m off, past his 300 m sight), the squad one 280 m off.
## Staged up in the air like the fire discipline checks, all in one frame (_find_target builds
## awareness one scan per call).
func _test_doctrine_ranges() -> void:
	print("Doctrines: engage ranges fit the sight ranges")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Doctrine.PATH))
	var hostile_ids: Array[StringName] = [StringName(String(file.sides.hostile))]
	for nation: String in (file.get("nations", {}) as Dictionary):
		hostile_ids.append(StringName(String(file.nations[nation])))
	var friendly_id := Doctrine.default_for(&"friendly")
	var report := ""
	var fits := true
	var clamped := true
	for id: StringName in Doctrine.ids():
		var e := Doctrine.value(id, "engage_m")
		report += " %s %.0f m" % [id, e]
		var sight := SquadAI.SIGHT_RANGE if id in hostile_ids and id != friendly_id else SquadAI.SQUAD_SIGHT_RANGE
		# Past its side's sight it would never act; under 3/4 of it, targets in sight go unengaged.
		fits = fits and e <= sight and e >= sight * 0.75
		for s: float in [SquadAI.SIGHT_RANGE, SquadAI.SQUAD_SIGHT_RANGE]:
			clamped = clamped and Doctrine.engage_m(id, s) <= s and Doctrine.engage_m(id, s, 50.0) <= 50.0
	check(fits, "each side's doctrines engage within its sight (hostiles %.0f m, the squad %.0f m) and not far inside it:%s"
		% [SquadAI.SIGHT_RANGE, SquadAI.SQUAD_SIGHT_RANGE, report])
	check(clamped and Doctrine.engage_m(Doctrine.PMC, SquadAI.SIGHT_RANGE) == SquadAI.SIGHT_RANGE,
		"and Doctrine.engage_m never goes past the shooter's sight or his weapon's reach (a PMC on the hostile side stops at %.0f m)"
		% Doctrine.engage_m(Doctrine.PMC, SquadAI.SIGHT_RANGE))
	var hostile_default := Doctrine.default_for(&"hostile")
	check(Doctrine.engage_m(hostile_default, SquadAI.SIGHT_RANGE) >= 180.0,
		"this zone's hostiles (%s) engage at 180 m (%.0f m)" % [hostile_default, Doctrine.engage_m(hostile_default, SquadAI.SIGHT_RANGE)])
	# Live: the AI's own target pick at those distances.
	var mate := _standing_mate([])
	await _wait_until(func() -> bool: return mate.stunned_s <= 0.0, 5.0)  # a stunned man picks no target (the flash check)
	var saved := mate.global_transform
	var origin := Vector3(300, 50.1, 300)  # up and away from everyone
	var hostile := level.spawn_soldier({"name": "RangeHostile", "faction": "hostile", "variant": "urban", "pos": origin,
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
	var hai := SquadAI.of(hostile)
	var mai := SquadAI.of(mate)
	# His AI sets itself up on its first physics steps (SquadAI._setup: body), not by a render
	# frame or two (R0572: _find_target on a null body).
	await _wait_until(func() -> bool: return hai.body != null and mai.body != null, 5.0)
	await _physics_frames(2)
	hai.process_mode = Node.PROCESS_MODE_DISABLED
	mai.process_mode = Node.PROCESS_MODE_DISABLED
	hostile.global_transform = Transform3D(Basis.IDENTITY, origin)  # faces -z
	hostile.velocity = Vector3.ZERO
	mate.velocity = Vector3.ZERO
	mate.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), origin + Vector3(0, 0, -180))  # faces the hostile
	var at_180 := _picks(hai, mate)
	hai._aware.clear()
	_place(mate, origin + Vector3(0, 0, -310))
	var at_210 := _picks(hai, mate)
	_place(mate, origin + Vector3(0, 0, -280))
	var squad_280 := _picks(mai, hostile)
	check(at_180 >= 0 and at_210 < 0, "a hostile engages a target he sees 180 m off (after %d scans), not one 310 m off, past his %.0f m sight"
		% [at_180, SquadAI.SIGHT_RANGE])
	var why := "%s stunned %.1f s, sees him %s, %.0f m, leaves %.1f m, spot %.1f s, aware %.2f, focus %s" % [mate.name, mate.stunned_s,
		mai.can_see(hostile), mate.global_position.distance_to(hostile.global_position), Spotting.foliage_m(mai._zone_scatter(), mate, hostile),
		Spotting.spot_seconds(mate, hostile, Spotting.preset_of(mate), 0.5, false, Soldier._now()), float(mai._aware.get(hostile.get_instance_id(), 0.0)), mai.focus]
	check(squad_280 >= 0, "the squad engages a hostile it sees 280 m off (after %d scans; %s)" % [squad_280, why])
	hostile.queue_free()
	mai._aware.clear()
	mai.process_mode = Node.PROCESS_MODE_INHERIT
	mate.global_transform = saved
	mate.velocity = Vector3.ZERO
	_clear_contact()
	await _frames(2)


## How many of `ai`'s scans (SquadAI._find_target calls, in one frame) it takes to pick `who`
## as its target; -1 if 60 scans (18 s of looking) don't.
func _picks(ai: SquadAI, who: Soldier) -> int:
	for i in 60:
		if ai._find_target() == who:
			return i + 1
	return -1


## Audit A3-04: the building scan cache belongs to one world (and level). The compound's main
## building is found where it stands; another world with only an open floor at the same
## coordinates (as the next zone would be) must not be handed that building from the cache.
func _test_buildings_per_world() -> void:
	print("Buildings: one world's scans stay in it")
	var inside := Vector3(-3, 0.1, -6)  # in the main building
	var here := Buildings.at(player, inside)
	check(Buildings.has_near(player, inside, 3.0), "formation presence scan finds the compound building")
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
	check(not Buildings.has_near(other, inside, 3.0), "presence scan rejects open ground in another world")
	var again := Buildings.at(player, inside)
	check(not here.is_empty() and there.is_empty() and not again.is_empty(),
		"the main building is found in the compound (%d spots); an open floor at the same spot in another world has none (%d); the compound's is still found"
		% [(here.get("spots", []) as Array).size(), (there.get("spots", []) as Array).size()])
	viewport.queue_free()
	await _frames(2)


## Review of the executive audit (2026-10-18): a building made of the same spots is cached by
## those spots alone, so its answer mustn't hang on the height the first scan came from. In a
## world of its own: a closed room (walls round it, no way in) up on a 4 m platform, as a
## watchtower's cabin or a container's top stands, is no building, scanned from 11.5 m up (whose
## reach stops short of the ground) and from the ground, whichever comes first; the same room on
## the ground is one.
func _test_buildings_raised_any_order() -> void:
	print("Buildings: a raised room's answer doesn't hang on which scan came first")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var other := Node3D.new()
	viewport.add_child(other)
	var solid := func(box: AABB) -> void:
		var body := StaticBody3D.new()
		body.collision_layer = Throwables.WORLD_MASK
		body.position = box.get_center()
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = box.size
		shape.shape = cube
		body.add_child(shape)
		other.add_child(body)
	solid.call(AABB(Vector3(-30, -1, -30), Vector3(60, 1, 60)))  # the ground
	var vertices := PackedVector3Array([Vector3(-8, 0, -8), Vector3(-8, 0, 8), Vector3(8, 0, 8), Vector3(8, 0, -8)])  # round the platform
	for room: Vector3 in [Vector3(0, 4.0, 0), Vector3(14, 0.2, 0)]:  # each 6 x 6 m inside, its floor at room.y
		solid.call(AABB(room + Vector3(-3.2, -0.2, -3.2), Vector3(6.4, 0.2, 6.4)))
		for wall: AABB in [AABB(Vector3(-3.2, 0, -3.2), Vector3(6.4, 2, 0.2)), AABB(Vector3(-3.2, 0, 3.0), Vector3(6.4, 2, 0.2)),
				AABB(Vector3(-3.2, 0, -3.0), Vector3(0.2, 2, 6.0)), AABB(Vector3(3.0, 0, -3.0), Vector3(0.2, 2, 6.0))]:
			solid.call(AABB(room + wall.position, wall.size))
		for corner: Vector3 in [Vector3(-2.5, 0, -2.5), Vector3(-2.5, 0, 2.5), Vector3(2.5, 0, 2.5), Vector3(2.5, 0, -2.5)]:
			vertices.append(room + corner)
	var mesh := NavigationMesh.new()
	mesh.set_vertices(vertices)
	for p in 3:
		mesh.add_polygon(PackedInt32Array([p * 4, p * 4 + 1, p * 4 + 2, p * 4 + 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	other.add_child(region)
	# Buildings answer nothing until this world's navigation map has synced with the region in it
	# (Buildings.near), and the walls must be in the physics space: wait for both, not a fixed
	# number of frames (4 frames was too few on CI's slower runners, so every scan found 0).
	var map := other.get_world_3d().navigation_map
	await _wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_regions(map).size() > 0, 10.0)
	await _physics_frames(2)
	var found := func(at: Vector3) -> int: return Buildings.near(other, at, 6.0).size()
	var high := Vector3(0, 11.5, 0)
	var low := Vector3(0, 0.1, 0)
	Buildings.forget()
	var high_first: Array = [found.call(high), found.call(low)]
	Buildings.forget()
	var low_first: Array = [found.call(low), found.call(high)]
	# (The scans did find the raised room's inside spots: only its height above the ground rules it out.)
	var raised_spots := 0
	for kept: Array in Buildings._cells.values():
		raised_spots += (kept[2] as Array).filter(func(s: Vector3) -> bool: return absf(s.y - 4.0) < 0.1).size()
	Buildings.forget()
	var on_ground: int = found.call(Vector3(14, 0.3, 0))
	check(raised_spots >= Buildings.MIN_SPOTS and high_first == [0, 0] and low_first == [0, 0] and on_ground == 1,
		"a closed room up on a 4 m platform (%d inside spots) is no building from 11.5 m up or from the ground, either first (high then low %s, low then high %s); on the ground it is one (%d)"
		% [raised_spots, high_first, low_first, on_ground])
	Buildings.forget()
	viewport.queue_free()
	await _frames(2)


## Audit follow-up F-01: a generated two-storey house with a flat roof (a parapet, a railed
## hatch), stamped in voxels on the open ground south-west of the compound, its navigation
## baked as the game bakes it (the chunks' ground and the voxels as they stand). The scan finds
## its ground floor, the floor above and the roof, and the stairs between; the squad ordered to
## clear it goes floor by floor up to the floor above; a man on the roof behind the parapet
## sees and takes on a hostile in the street.
const STOREY_AT := Vector3(-32, 0, 40)


func _test_multi_storey() -> void:
	print("Buildings: floors, stairs and roofs (F-01)")
	var b := {}
	for seed in range(1, 400):
		var c := BuildingGen.house(seed, "brick")
		if int(c.storeys) == 2 and c.roof_access and (c.yards as Array).is_empty() and c.shape == "rect":
			b = c
			b["seed"] = seed
			break
	if b.is_empty():
		check(false, "a two-storey house with a roof to stand on")
		return
	var upper: float = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == 1)[0].y
	var roof_y: float = b.roof_y
	print("    house seed %d: %.1f x %.1f m, floor above at %.2f m, roof at %.2f m" % [b.seed, b.size.x, b.size.y, upper, roof_y])
	var holder := Node3D.new()
	holder.name = "StoreyHouse"
	holder.position = STOREY_AT
	var world := VoxelWorld.new()
	world.bounds = AABB(Vector3(-120, -10, -120), Vector3(240, 100, 240))  # voxels: 24 x 10 x 24 m
	world.view_distance = 2000
	for bx: Array in b.boxes:
		world.add_box_m(bx[0], bx[1], bx[2])
	level.add_child(holder)
	holder.add_child(world)
	_place(player, STOREY_AT + Vector3(0, 0.1, b.size.y * 0.5 + 6.0))  # the street in front (voxels build round the player)
	var built := await _wait_until(func() -> bool: return world.is_built(), 30.0)
	var space := player.get_world_3d().direct_space_state
	var on_roof := STOREY_AT + Vector3(0, roof_y + 2.0, b.size.y * 0.25)
	var solid := await _wait_until(func() -> bool:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(on_roof, on_roof + Vector3.DOWN * 3.0, 1))
		return not hit.is_empty() and absf((hit.position as Vector3).y - roof_y) < 0.2, 15.0)
	# Its navigation, as NavBuilder bakes a chunk: the ground and the voxels as they stand, and
	# (as ZoneNav adds a town's) ramps over its stairs.
	var nav := level.get_node(^"Navigation") as NavBuilder
	var foot := Rect2(STOREY_AT.x - b.size.x * 0.5 - 3.0, STOREY_AT.z - b.size.y * 0.5 - 3.0, b.size.x + 6.0, b.size.y + 6.0)
	var lo := NavBuilder.chunk_at(Vector3(foot.position.x, 0, foot.position.y))
	var hi := NavBuilder.chunk_at(Vector3(foot.end.x, 0, foot.end.y))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var chunk := Vector2i(cx, cz)
			var source := nav._ground_source(chunk)
			var bounds := NavBuilder._bake_bounds(chunk)
			var local := world.global_transform.affine_inverse() * bounds
			for box in world.solid_boxes_m(local):
				source.add_faces(NavBuilder._box_faces(box), world.global_transform)
			source.add_faces(BuildingGen.ramp_faces(b), world.global_transform)  # as ZoneNav bakes a town's
			var mesh := NavBuilder._new_mesh(chunk)
			NavigationServer3D.bake_from_source_geometry_data(mesh, source)
			nav.region_of(chunk).navigation_mesh = mesh
	await _physics_frames(4)
	Buildings.forget()  # the house and its navmesh are new: no probe made before them counts
	var map := player.get_world_3d().navigation_map
	var street := NavigationServer3D.map_get_closest_point(map, STOREY_AT + Vector3(0, 0, b.size.y * 0.5 + 4.0))
	var roof_goal := NavigationServer3D.map_get_closest_point(map, STOREY_AT + Vector3(0, roof_y + 0.2, b.size.y * 0.25))
	var path := NavigationServer3D.map_get_path(map, street, roof_goal, true)
	check(built and solid and roof_goal.y - roof_y > -0.2 and roof_goal.y - roof_y < Buildings.SURFACE_SNAP_M and path.size() > 2 and path[-1].distance_to(roof_goal) < 0.5,
		"the house stands (%s, %s) and the navmesh runs from the street up the stairs onto its roof (%d points, ends %.1f m off, at %.2f m)"
		% [built, solid, path.size(), path[-1].distance_to(roof_goal) if path.size() > 0 else INF, roof_goal.y])
	# The scan: from the ground floor, three floors (the roof the top one), two stairs.
	var front_room := STOREY_AT + Vector3(0, 0.1, b.size.y * 0.5 - 2.0)
	check(Buildings.has_near(player, front_room, 3.0), "presence scan recognizes a multi-storey building before detailed queries")
	var found := Buildings.nearest(player, front_room, 3.0)
	var same_surfaces := true
	var surface_samples := 0
	Buildings._index_regions(map)
	for y: float in [0.1, upper + 0.1, roof_y + 0.1]:
		for x: float in [-6.0, -2.0, 2.0, 6.0]:
			for z: float in [-6.0, -2.0, 2.0, 6.0]:
				var p := STOREY_AT + Vector3(x, y, z)
				var original := NavigationServer3D.map_get_closest_point(map, p)
				if original.distance_to(p) < Buildings.REGION_MARGIN_M:
					var indexed := Buildings._closest_nav_point(p)
					same_surfaces = same_surfaces and indexed.is_finite() and absf(indexed.distance_to(p) - original.distance_to(p)) < 0.001
					surface_samples += 1
	check(same_surfaces and surface_samples >= 16, "indexed probes agree with the original map query across floors and tile boundaries (%d samples)" % surface_samples)
	var floors: Array = found.get("floors", [])
	var heights: Array = floors.map(func(f: Dictionary) -> String: return "%.2f%s" % [f.y, " roof" if f.roof else ""])
	var stairs: Array = (found.get("stairs", []) as Array).map(func(s: Dictionary) -> String: return "%d-%d" % [s.from, s.to])
	check(floors.size() == 3 and absf(float(floors[1].y) - upper) < 0.4 and absf(float(floors[2].y) - roof_y) < 0.4
		and not floors[0].roof and not floors[1].roof and floors[2].roof and "0-1" in stairs and "1-2" in stairs,
		"the scan finds its ground floor, the floor above and the roof (%s), and the stairs between (%s)" % [heights, stairs])
	var ports: Array = found.get("ports", [])
	var count := func(fi: int, kind: String) -> int: return ports.filter(func(p: Dictionary) -> bool: return int(p.floor) == fi and p.kind == kind).size()
	var rooms_by_floor: Array = floors.map(func(f: Dictionary) -> int: return (f.rooms as Array).size())
	check(count.call(0, "door") >= 1 and count.call(1, "window") >= 1 and count.call(2, "parapet") >= 4
		and rooms_by_floor.size() == 3 and rooms_by_floor.all(func(n: int) -> bool: return n >= 1),
		"doors below, windows on the floor above (%d), the roof's parapet all round (%d), rooms on every floor %s"
		% [count.call(1, "window"), count.call(2, "parapet"), rooms_by_floor])
	# The same building from its roof; the scan cached (A3-04) under its own key, in this world.
	var from_roof := Buildings.at(player, roof_goal)
	var again := Buildings.near(player, roof_goal)
	check((from_roof.get("floors", []) as Array).size() == 3 and from_roof.get("centre", Vector3.INF).distance_to(found.centre) < 1.0
		and is_same(again, Buildings.near(player, roof_goal)),
		"scanned from the roof: the same building, all three floors (cached: the same list again)")
	if found.is_empty():
		return
	# Garrisoned against a threat in the street: men upstairs and on the roof.
	var squad := level.squad_for(&"friendly")
	var mates: Array[SquadAI] = []
	for s: Soldier in _squad():
		if s.vitals.is_up() and s.carrying == null and not is_instance_valid(s.carried_by) and SquadAI.of(s).care == SquadAI.Care.NONE and mates.size() < 4:
			mates.append(SquadAI.of(s))
	var tasks := SquadTactics.garrison_tasks(found, mates, STOREY_AT + Vector3(0, 0, b.size.y * 0.5 + 30.0))
	var up_high := tasks.values().filter(func(t: Dictionary) -> bool: return (t.spot as Vector3).y > upper - 0.5).size()
	check(up_high >= 2, "garrisoning it against the street: %d of %d posts up high (%s)" % [up_high, tasks.size(),
		tasks.values().map(func(t: Dictionary) -> String: return "%s@%.1f" % [t.port, (t.spot as Vector3).y])])
	# Cleared by four: floor by floor, the floor above once the ground floor's done.
	var names := PackedStringArray(mates.map(func(ai: SquadAI) -> String: return String(ai.body.name)))
	var why := squad.order_clear(player, front_room, names)
	var op: Dictionary = mates[0].ordered.get("op", {}) if why == "" else {}
	var up := {"first": -1.0, "gone_at": INF, "who": ""}  # (a lambda can't set the function's locals)
	var visited := await _wait_until(func() -> bool:
		for ai: SquadAI in mates:
			if ai.body.global_position.y > upper - 0.15 and Buildings.contains(found, ai.body.global_position):
				up.first = Soldier._now()
				up.gone_at = float((op.get("floor_go", [INF, INF]) as Array)[1]) if not op.is_empty() else INF
				up.who = String(ai.body.name)
				return true
		return false, 90.0)
	var statuses := mates.map(func(ai: SquadAI) -> String: return "%s %s %.1f" % [ai.body.name, ai.body.ai_status, ai.body.global_position.y])
	check(why == "" and visited and (op.get("floors", []) as Array).size() == 3,
		"ordered to clear it, the team goes up the stairs: %s on the floor above (%s; %s)" % [up.who, why, statuses])
	check(is_finite(float(up.gone_at)) and float(up.gone_at) <= float(up.first),
		"floor by floor: nobody goes up before the ground floor's rooms are done (went up at %.1f, first upstairs at %.1f)" % [up.gone_at, up.first])
	for ai: SquadAI in mates:
		ai.give_tactic({})
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position)
	await _seconds(0.5)
	# A man on the roof behind the parapet sees a hostile in the street and takes him on.
	var watch: Dictionary = {}
	for p: Dictionary in ports:
		if int(p.floor) == 2 and p.kind == "parapet" and (p.dir as Vector3).z > 0.9:
			watch = p
			break
	var gunner := mates[0]
	if watch.is_empty():
		check(false, "a parapet port facing the street (%s)" % [ports.filter(func(p: Dictionary) -> bool: return int(p.floor) == 2).map(func(p: Dictionary) -> Vector3: return p.dir)])
		return
	_clear_contact()
	_place(player, STOREY_AT + Vector3(0, 0.1, -b.size.y * 0.5 - 8.0))  # the rest follow round the back, out of sight of the street
	_place(gunner.body, (watch.point as Vector3) + Vector3.UP * 0.1)
	gunner.give_tactic({"kind": &"garrison", "spot": watch.point, "face": watch.dir, "port": "parapet"})
	var others := _squad().filter(func(s: Soldier) -> bool: return s != gunner.body)
	for s: Soldier in others:
		SquadAI.of(s).hold_fire = true  # the roof's man alone takes him on
	await _seconds(1.0)
	var hostile := level.spawn_soldier({"name": "StreetHostile", "faction": "hostile", "variant": "urban",
		"pos": Vector3((watch.point as Vector3).x, 0.1, (watch.point as Vector3).z) + (watch.dir as Vector3) * 22.0,
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.3, "discipline": 0.5, "guard": true})
	await _frames(2)
	SquadAI.of(hostile).process_mode = Node.PROCESS_MODE_DISABLED
	hostile.set_physics_process(false)  # he stands where he was put (he walked up under the wall)
	var engaged := await _wait_until(func() -> bool:
		return not is_instance_valid(hostile) or not hostile.vitals.is_up() or gunner.target == hostile, 12.0)
	var seen := is_instance_valid(hostile) and Squad.sees(gunner.body, hostile)
	var seen_back := is_instance_valid(hostile) and Squad.sees(hostile, gunner.body)
	check(engaged and gunner.body.global_position.y > roof_y - 0.3,
		"%s on the roof behind the parapet sees the hostile in the street and takes him on (%s; sees him %s, seen back %s)"
		% [gunner.body.name, gunner.body.ai_status, seen, seen_back])
	if is_instance_valid(hostile):
		hostile.queue_free()
	gunner.give_tactic({})
	for s: Soldier in others:
		SquadAI.of(s).hold_fire = false
	_clear_contact()
	_place(gunner.body, STOREY_AT + Vector3(0, 0.1, b.size.y * 0.5 + 4.0))


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
	# foliage_least walks the foliage once for two lines (Spotting.foliage_m: head and chest).
	var eyes := Vector3(1, 1.6, -20)
	var pairs := [[Vector3(0, 0.3, 20), Vector3(0, 1.6, 20)], [Vector3(20, 3.0, 20), Vector3(20, 1.0, 20)],
		[Vector3(0, 0.3, 20), Vector3(20, 3.0, 20)], [Vector3(3, 0.3, 20), Vector3(1, 1.6, -20)]]
	var same := pairs.all(func(p: Array) -> bool: return is_equal_approx(sc.foliage_least(eyes, p[0], p[1]),
		minf(sc.foliage_between(eyes, p[0]), sc.foliage_between(eyes, p[1]))))
	check(same, "foliage for two lines in one walk: the clearer line's, as two walks give")
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
	## A stopped brain leaves its last move_input on the body, and the body keeps moving on it
	## (R0920, R0933: he crawled off prone at 0.35 m/s, out from behind the bush, 1.5 m of
	## leaves down to 0 in 2 s; how far he got by the measure was down to timing).
	bravo.move_input = Vector2.ZERO
	bravo.want_sprint = false
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
	# Facing the observer, so he lies square behind the bush: lying across the line, his head
	# would poke out past its edge (his facing was whatever his AI last turned to).
	bravo.rotation.y = PI
	bravo.want_stance = SoldierMovement.Stance.PRONE
	await _wait_until(func() -> bool: return bravo.movement.is_prone(), 3.0)
	await get_tree().create_timer(0.6).timeout  # the eyes settle down
	var prone_leaves := Spotting.foliage_m(bush, alpha, bravo)
	check(bravo.movement.is_prone() and standing_leaves < 0.2 and prone_leaves >= Spotting.FOLIAGE_OPAQUE_M,
		"a bush hides him prone (%.2f m of leaves; prone %s, eye %.2f m up), not standing (%.1f m: his head shows)" % [prone_leaves,
		bravo.movement.is_prone(), bravo.camera.global_position.y - bravo.global_position.y, standing_leaves])
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
	# Player orders first (Captain, 2026-10-17: "Player orders -> squad tactics -> buddy team
	# tactics -> indiv tactics"; B team "not responding" was this): in contact, a Move order
	# beats fighting where he stands, until he gets there.
	ai.morale = steady
	var move_was := ai._move_point
	ai.order = Squad.Order.MOVE
	ai._move_point = alpha.global_position + Vector3(0, 0, 40)
	ai._choose_intent()
	ai._choose_intent()
	check(ai.fighting() and ai.intent == SquadAI.Intent.MOVE_TO, "in contact, a player's Move order beats fighting where he stands (%s)" % ai.status_text())
	ai._move_point = alpha.global_position
	ai._choose_intent()
	ai._choose_intent()
	# Captain, 2026-10-18 (live playtest, v0.4.41): "theyre running around when i order them to
	# stand somewhere" - an arrived Move used to drop to FOLLOW's own 0.5, so it still fights
	# where it stands (0.7 beats that), but squad tactics (TACTIC_SCORE 0.75), casualty care
	# and escort could pull it off the spot anyway. An arrived Move is now a real Hold order
	# (PLAYER_ORDER_SCORE 0.93), so it stays a Hold through the fight, not just a one-tick win.
	check(ai.order == Squad.Order.HOLD and ai.fighting() and ai.intent == SquadAI.Intent.HOLD,
		"and once there, it becomes a real Hold - still fights from the spot (%s)" % ai.status_text())
	ai._move_point = move_was
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
	# Both on their feet for the muzzle check (combat mode would crouch either of them, and a
	# standing shooter's line passes over a crouched man's head, rightly clear).
	bravo.want_stance = SoldierMovement.Stance.STAND_HIGH
	alpha.want_stance = SoldierMovement.Stance.STAND_HIGH
	alpha.global_transform = saved[0]  # back on the ground while he gets up
	bravo.global_transform = saved[1]
	var standing := await _wait_until(func() -> bool:
		return bravo.movement.stance == SoldierMovement.Stance.STAND_HIGH and alpha.movement.stance == SoldierMovement.Stance.STAND_HIGH, 4.0)
	await _seconds(0.5)  # the head rises to its standing eye
	alpha.global_transform = Transform3D(Basis.IDENTITY, origin)
	var stood_eye := alpha.camera.global_position.y - origin.y
	# On his feet right in front of the muzzle, the line goes through him (playtest P0331: a
	# squadmate was shot in the head at 0 m); beside the shooter he still isn't in it.
	_place(bravo, origin + Vector3(0, 0, -0.35))
	var at_muzzle := ai._friendly_in_line(aim)
	_place(bravo, origin + Vector3(0.6, 0, 0.2))
	check(standing and stood_eye > 1.4 and at_muzzle and not ai._friendly_in_line(aim),
		"a squadmate standing right in front of the muzzle blocks the shot; beside the shooter he doesn't (eye %.2f m)" % stood_eye)
	bravo.want_stance = -1
	alpha.want_stance = -1
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


## Captain, v0.4.6 playtest: "friendlies shoot at and try to shoot through walls, enemies too"
## (the squad inside the compound firing into the 2.6 m concrete wall at a contact 160 m out).
## Suppressive fire on a point outside the compound: with a clear line (through the gate) the
## rounds go; behind the perimeter wall none go, and within a few seconds he moves to a spot
## with a line (by the gate) and fires from there; in a corner with no such spot near, he holds
## fire. Hostiles run the same SquadAI fire code.
func _test_no_fire_into_walls() -> void:
	print("Line of fire: no rounds into walls, a fire position or hold fire")
	_clear_contact()
	var squad := level.squad_for(&"friendly")
	var s := _standing_mate([])
	var ai := SquadAI.of(s)
	var names := PackedStringArray([String(s.name)])
	var saved_player := player.global_transform
	_place(player, Vector3(10, 0.1, -16))  # the rest of the squad follows him, out of every line here
	var rounds := func() -> int: return s.inventory.rounds_in(s.active_slot)
	var trial := func(at: Vector3, aim: Vector3) -> void:
		ai._fire_spot = null
		ai._fire_spot_at = -1000.0
		ai._no_shot_since = -1.0
		ai._fire_line = {}
		_place(s, at)
		squad.give_order(player, Squad.Order.HOLD, at, names)
		var st := s.inventory.state_of(s.active_slot)
		if not st.is_empty():
			var wid: StringName = s.inventory.slots.get(s.active_slot, &"")
			var ammo_id := StringName(ItemDB.get_item(wid).stats.get("ammo", "")) if wid != &"" else &""
			st["rounds"] = ItemDB.get_item(ammo_id).magazine_rounds() if ItemDB.has_item(ammo_id) else 30  # his own full magazine (an M4 holds 30, an M249 box 200): no reload in the middle of it
		squad.order_suppress(player, aim, names)
	# (c) A clear line, out through the gate: he suppresses.
	var gate_aim := Vector3(0, 0, 70)
	trial.call(Vector3(0, 0.1, 15), gate_aim)
	var before: int = rounds.call()
	var fired := await _wait_until(func() -> bool: return rounds.call() < before, 5.0)
	check(fired and ai._fire_spot == null, "Suppress through the gate, a clear line: the rounds go (%d -> %d, %s)" % [before, rounds.call(), s.ai_status])
	# (a) Behind the perimeter wall: nothing goes into it, then (b) he moves to a fire position.
	var wall_aim := Vector3(-10, 0, 70)
	trial.call(Vector3(-10, 0.1, 12), wall_aim)
	before = rounds.call()
	await _seconds(SquadAI.NO_SHOT_MOVE_S - 0.3)
	var held: int = rounds.call()
	var blocked := ai._no_shot_since >= 0.0
	check(held == before and blocked and _flat(s.global_position, Vector3(-10, 0, 12)) < 1.5,
		"Suppress a point behind the compound wall: not one round into the wall while he holds there (%d -> %d, no shot %s, %s)" % [before, held, blocked, s.ai_status])
	var moved := await _wait_until(func() -> bool: return ai._fire_spot != null, 3.0)
	var spot: Vector3 = ai._fire_spot if moved else Vector3.INF
	var spot_ok: bool = moved and ai._fire_line_from(Vector3(spot.x, 0.1, spot.z) + Vector3.UP * (SquadAI.FIRE_EYE_STAND_M if ai._fire_spot_stand else SquadAI.FIRE_EYE_CROUCH_M),
		wall_aim + Vector3.UP, SquadAI.FIRE_LINE_SLACK_M) and _flat(spot, Vector3(-10, 0, 12)) <= SquadAI.FIRE_SPOT_RINGS[-1] + 1.0
	check(spot_ok, "no line for %.1f s: he picks a fire position with one, close by (%s)" % [SquadAI.NO_SHOT_MOVE_S, spot])
	# Every round from here on leaves along a clear line, and some do once he's there.
	var into_wall := 0
	var shots := 0
	var last: int = rounds.call()
	var left := 12.0
	while left > 0.0 and shots < 3:
		await _physics_frames(2)
		left -= 2.0 / Engine.physics_ticks_per_second
		var now_rounds: int = rounds.call()
		if now_rounds < last:
			shots += last - now_rounds
			if not ai._fire_line_from(s.camera.global_position, wall_aim + Vector3.UP, SquadAI.FIRE_LINE_SLACK_M + SquadAI.SUPPRESS_SPREAD_M * 1.5):
				into_wall += last - now_rounds
		last = now_rounds
	check(shots > 0 and into_wall == 0 and spot_ok and _flat(s.global_position, spot) < 2.0,
		"he goes there and suppresses from it: %d round(s), %d with the wall in the way (%.1f m from the spot, %s)" % [shots, into_wall,
			_flat(s.global_position, spot) if spot_ok else -1.0, s.ai_status])
	# In the north-west corner, the north wall in the way and nowhere near with a line: he holds fire.
	var corner_aim := Vector3(-14, 0, -70)
	trial.call(Vector3(-14, 0.1, -16), corner_aim)
	before = rounds.call()
	await _seconds(SquadAI.NO_SHOT_MOVE_S + 1.5)
	check(rounds.call() == before and ai._fire_spot == null and ai._fire_spot_at > 0.0 and s.ai_status == "No shot"
		and _flat(s.global_position, Vector3(-14, 0, -16)) < 1.5,
		"in the corner with no fire position near: he holds fire where he is (%d -> %d, %s)" % [before, rounds.call(), s.ai_status])
	ai.give_tactic({})
	ai._fire_spot = null
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position)
	player.global_transform = saved_player
	_clear_contact()


## Close-range and long-range hostile accuracy (Captain, P0362: squad killed by head and neck
## shots at 2-6 m; one guard downed three at 155 m in 13 s). A hostile at combat 0.45 meets a
## standing man at 2, 4 and 6 m, in front of him or off to the side and behind; the rounds are
## traced against the real hitboxes the way Ballistics does. Up close he should take a moment,
## start low and miss a little, and hit centre mass, with only a few high rounds. At 100-200 m
## he hits less often than before (the old aim, staged the same way, is printed beside it),
## and a skilled man (combat 0.8) still clearly better than him.
func _test_close_range_aim() -> void:
	print("Close-range aim: reaction, first-shot error, snap-aim lag, centre mass; long-range hit rates")
	var spot := Vector3(-70, 0.1, -70)  # a corner of the flat ground, away from the squad
	var diag := Vector3(1, 0, 1).normalized()  # the shooter stands off along this (200 m fits)
	var hostile := level.spawn_soldier({"name": "CqbHostile", "faction": "hostile", "variant": "urban", "pos": spot + diag * 4.0,
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": true})
	var target := level.spawn_soldier({"name": "CqbTarget", "faction": "friendly", "variant": "urban", "pos": spot,
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	var ai := SquadAI.of(hostile)
	ai.set_physics_process(false)
	SquadAI.of(target).set_physics_process(false)
	hostile.remove_from_group(&"combatants")  # the squad leaves him be (they see 120 m)
	hostile.move_input = Vector2.ZERO
	target.move_input = Vector2.ZERO
	hostile.want_aim = true
	_place(target, spot)
	## Square on to the shooter. His facing was whatever his AI turned to in the frames before
	## it was stopped (it turns to the hostile it sees, a different part of the way each run:
	## -0.26, -0.70, -1.04 rad): side on, his arm covers his chest and the centre-mass share
	## swung from 85% to 33% with the aim unchanged (R0612, R0826, R0864).
	target.rotation.y = atan2(-diag.x, -diag.z)
	_place(hostile, spot + diag * 4.0)
	await _physics_frames(15)  # lands (a 10 cm drop) and stands
	hostile.is_aiming = true
	var weapon := hostile.active_weapon()
	check(weapon != null and weapon.type == "weapon" and hostile.is_on_floor() and target.vitals.is_up(),
		"a hostile (%s, combat %.2f) on his feet (%s), aiming (%s), and a standing man to shoot at (%s)" % [
		weapon.id if weapon else "no weapon", ai.combat, hostile.is_on_floor(), hostile.is_aiming, target.vitals.condition_text()])
	if weapon == null:
		hostile.queue_free()
		target.queue_free()
		return
	seed(4242)
	for d: float in [2.0, 4.0, 6.0]:
		_place(hostile, spot + diag * d)
		await _physics_frames(15)
		hostile.is_aiming = true
		check(hostile.is_on_floor(), "%.0f m: he stands on the ground" % d)
		for cqb: bool in [false, true]:
			var fired := 0
			var hits := 0
			var head := 0
			var torso := 0
			var first_chest := 0
			var early := 0
			var quick := 0
			var front_t: Array[float] = []
			var flank_t: Array[float] = []
			for k in 120:
				var flank := k >= 60
				var off := deg_to_rad(randf_range(-60.0, 60.0)) if not flank else deg_to_rad(randf_range(90.0, 180.0)) * (1.0 if k % 2 == 0 else -1.0)
				var r := _cqb_trial(hostile, ai, target, off, cqb)
				fired += r.fired
				hits += r.hits
				head += r.head
				torso += r.torso
				if not flank and r.first_part == Vitals.CHEST:
					first_chest += 1
				if r.first_hit >= 0.0:
					if r.first_hit < 0.35:
						early += 1
					if r.first_hit <= 2.5:
						quick += 1
					(flank_t if flank else front_t).append(r.first_hit)
				else:
					(flank_t if flank else front_t).append(99.0)
			var front_med := _median(front_t)
			var flank_med := _median(flank_t)
			var share := float(hits) / maxf(fired, 1)
			var head_share := float(head) / maxf(hits, 1)
			print("    %.0f m %s: %d rounds, %d hits (%.0f%%), head/face/neck %d (%.1f%% of hits), torso %d, first round in the chest %d/60, first hit median front %.2f s, flank %.2f s" % [
				d, "now   " if cqb else "before", fired, hits, share * 100.0, head, head_share * 100.0, torso, first_chest, front_med, flank_med])
			if not cqb:
				continue
			check(hits > 0 and head_share <= 0.08, "%.0f m: head, face and neck at most 8%% of hits (%d of %d)" % [d, head, hits])
			check(hits > 0 and float(torso) / hits >= 0.75, "%.0f m: chest, abdomen and pelvis at least 75%% of hits (%d of %d)%s" % [d, torso, hits,
				"" if hits > 0 and float(torso) / hits >= 0.75 else "; " + _pose_note(target)])
			check(share >= 0.6, "%.0f m: still hits: at least 60%% of rounds (%.0f%%)" % [d, share * 100.0])
			check(first_chest <= 51, "%.0f m: the first round isn't a sure chest hit (%d of 60 front trials, at most 51)" % [d, first_chest])
			check(early == 0, "%.0f m: no first hit sooner than 0.35 s (%d were)" % [d, early])
			check(front_med >= 0.55 and front_med <= 1.4, "%.0f m: a reaction before the first hit in front: median %.2f s (0.55-1.4)" % [d, front_med])
			check(flank_med >= front_med + 0.1, "%.0f m: a man off to the side or behind takes longer: median %.2f s vs %.2f s in front" % [d, flank_med, front_med])
			check(quick >= 108, "%.0f m: at least 90%% of trials hit within 2.5 s (%d of 120)" % [d, quick])
	# At range: up in the air, clear of the compound's walls (both held there, physics off). Each
	# trial is 20 s of fire at one man in the open, as at 155 m in P0362.
	var sky := spot + Vector3.UP * 40.0
	hostile.set_physics_process(false)
	target.set_physics_process(false)
	_place(target, sky)
	var shares := {}
	for d: float in [100.0, 150.0, 200.0]:
		_place(hostile, sky + diag * d)
		await _physics_frames(2)
		hostile.is_aiming = true
		for skill: float in [0.45, 0.8]:
			ai.combat = skill
			for cqb: bool in [false, true]:
				var fired := 0
				var hits := 0
				var first_t: Array[float] = []
				var third_t: Array[float] = []
				for k in 30:
					var r := _cqb_trial(hostile, ai, target, deg_to_rad(randf_range(-10.0, 10.0)), cqb, 20.0, 0)
					fired += r.fired
					hits += r.hits
					first_t.append(r.first_hit if r.first_hit >= 0.0 else 99.0)
					third_t.append(r.third_hit if r.third_hit >= 0.0 else 99.0)
				var share := float(hits) / maxf(fired, 1)
				shares[str(d, " ", skill, " ", cqb)] = share
				print("    %.0f m, combat %.2f %s: %d rounds, %d hits (%.1f%%), first hit median %.1f s, third hit median %.1f s (99: none in 20 s)" % [
					d, skill, "now   " if cqb else "before", fired, hits, share * 100.0, _median(first_t), _median(third_t)])
				if cqb and is_equal_approx(d, 150.0) and is_equal_approx(skill, 0.45):
					var med := _median(first_t)
					check(share >= 0.04 and share <= 0.15, "150 m, combat 0.45: %.1f%% of rounds hit (4-15%%)" % (share * 100.0))
					check(med >= 2.5 and med <= 12.0, "150 m, combat 0.45: the first hit takes a while: median %.1f s (2.5-12)" % med)
					check(_median(third_t) >= 8.0, "150 m, combat 0.45: three hits take at least 8 s (median %.1f s)" % _median(third_t))
	ai.combat = 0.45
	for d: float in [100.0, 150.0, 200.0]:
		check(shares[str(d, " ", 0.45, " ", true)] < shares[str(d, " ", 0.45, " ", false)] and shares[str(d, " ", 0.8, " ", true)] < shares[str(d, " ", 0.8, " ", false)],
			"%.0f m: fewer hits than before (combat 0.45 %.2f vs %.2f, 0.8 %.2f vs %.2f)" % [d, shares[str(d, " ", 0.45, " ", true)], shares[str(d, " ", 0.45, " ", false)], shares[str(d, " ", 0.8, " ", true)], shares[str(d, " ", 0.8, " ", false)]])
		check(shares[str(d, " ", 0.8, " ", true)] >= shares[str(d, " ", 0.45, " ", true)] * 1.5, "%.0f m: combat 0.8 hits at least 1.5x as often as 0.45 (%.2f vs %.2f)" % [d, shares[str(d, " ", 0.8, " ", true)], shares[str(d, " ", 0.45, " ", true)]])
	randomize()
	# Live: a real 4 m engagement through _shoot. The squad is kept out of earshot (out of the
	# combatants for it) so the shots don't start a fight for the later checks.
	_place(target, spot)
	_place(hostile, spot + diag * 4.0)
	hostile.set_physics_process(true)
	target.set_physics_process(true)
	var deaf: Array[Soldier] = []
	for s: Soldier in _squad():
		if s != target and s.is_in_group(&"combatants"):
			s.remove_from_group(&"combatants")
			deaf.append(s)
	var to := target.global_position - hostile.global_position
	hostile.rotation.y = atan2(-to.x, -to.z)
	hostile.head.rotation.x = 0.0
	target.rotation.y = atan2(-diag.x, -diag.z)
	await _physics_frames(4)
	ai.target = null
	ai._acq_age = 0.0
	ai._next_shot = 0.0
	ai._pause_until = 0.0
	ai._burst_left = 0
	ai.intent = SquadAI.Intent.FIGHT
	ai._cover_cd = 1000.0  # stays where he stands
	var start := Soldier._now()
	ai.set_physics_process(true)
	var hit_at := -1.0
	while Soldier._now() - start < 3.5:
		await get_tree().physics_frame
		if target.vitals.wound_list().size() > 0:
			hit_at = Soldier._now() - start
			break
	ai.set_physics_process(false)
	check(hit_at >= 0.4 and hit_at <= 3.0 and ai._acq_age > 0.0, "live at 4 m: the first wound comes after %.2f s (0.4-3 s), through the close-range aim (age %.2f s)" % [hit_at, ai._acq_age])
	hostile.queue_free()
	target.queue_free()
	for s: Soldier in deaf:
		if is_instance_valid(s):
			s.add_to_group(&"combatants")
	await _frames(2)
	_clear_contact()


## One staged engagement for _test_close_range_aim, run synchronously at 60 Hz the way _shoot
## does it: `hostile` starts `yaw_off` off facing `target`, acquires him, and fires bursts for
## up to `length` seconds (`max_bursts` of them; 0: no limit). `cqb`: the aim as it is now
## (_cqb_aim_point, _aim_for_shot, _gate_open, _new_hold); else the old one as it was on dev
## before P0362 (the chest, an uncapped ease, fire within 6 degrees). Returns rounds fired,
## hits on the target, head (head, face, neck) and torso (chest, abdomen, pelvis) hits, the
## first round's part, and the first and third hits' times (-1: none).
func _cqb_trial(hostile: Soldier, ai: SquadAI, target: Soldier, yaw_off: float, cqb: bool, length := 4.0, max_bursts := 2) -> Dictionary:
	var to := target.aim_point() - hostile.global_position
	hostile.rotation.y = atan2(-to.x, -to.z) + yaw_off
	hostile.head.rotation.x = 0.0
	ai.target = target
	ai._burst_left = 0
	ai._acquire(target)
	var weapon := hostile.active_weapon()
	var auto: bool = weapon.stats.get("auto", false)
	var gap := 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	var res := {"fired": 0, "hits": 0, "head": 0, "torso": 0, "first_part": &"", "first_hit": -1.0, "third_hit": -1.0}
	var dt := 1.0 / 60.0
	var t := 0.0
	var next_t := 0.0
	var pause_t := 0.0
	var bursts := 0
	while t < length:
		t += dt
		var open: bool
		if cqb:
			var aim := ai._cqb_aim_point(target, dt)
			open = ai._gate_open(target, ai._aim_for_shot(aim, target), aim)
		else:
			ai._acq_age += dt
			open = _old_aim_at(hostile, ai, target.aim_point(), dt) <= deg_to_rad(6.0)
		if t < ai._acq_react_s or t < next_t or t < pause_t or not open:
			continue
		next_t = t + gap
		if ai._burst_left <= 0:
			bursts += 1
			ai._burst_left = randi_range(3, 5) if auto else randi_range(2, 3)
			ai._suppress_jitter = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.5), randf_range(-1, 1)) * SquadAI.SUPPRESS_SPREAD_M
			ai._start_burst(target)
		ai._burst_left -= 1
		if ai._burst_left <= 0:
			pause_t = t + randf_range(0.5, 1.1) / lerpf(0.7, 1.3, ai.combat)
			if cqb:
				ai._new_hold()
		var dir: Vector3 = hostile.call(&"ai_spread_direction", weapon) if hostile.has_method(&"ai_spread_direction") else hostile._spread_direction(weapon)
		var extra := deg_to_rad(ai._aim_error_deg(true))
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(extra) * 0.6).normalized()
		var part := _round_part(hostile, target, hostile.camera.global_position, dir)
		res.fired += 1
		if res.fired == 1:
			res.first_part = part
		if part != &"":
			res.hits += 1
			if res.first_hit < 0.0:
				res.first_hit = t
			if res.hits == 3:
				res.third_hit = t
			if part in [Vitals.HEAD, Vitals.FACE, Vitals.NECK]:
				res.head += 1
			elif part in Vitals.TORSO_PARTS:
				res.torso += 1
		if max_bursts > 0 and bursts >= max_bursts and ai._burst_left <= 0:
			break
	return res


## SquadAI._aim_at as it was before P0362 (for the "before" numbers): the same ease, no cap on
## the swing. Returns the angle still off (radians).
static func _old_aim_at(hostile: Soldier, ai: SquadAI, point: Vector3, dt: float) -> float:
	var d := point - hostile.camera.global_position
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var step := 1.0 - exp(-SquadAI.TURN_RATE * lerpf(0.6, 1.4, ai.combat) * dt)
	hostile.rotation.y = lerp_angle(hostile.rotation.y, yaw, step)
	hostile.head.rotation.x = lerpf(hostile.head.rotation.x, clampf(pitch, -1.4, 1.4), step)
	return (-hostile.camera.global_basis.z).angle_to(d.normalized())


## The part of `target` a round from `from` along `dir` meets, as Ballistics._trace finds it
## (the hitbox, then the body inside it), or &"" for a miss (the ground, anyone else).
static func _round_part(shooter: Soldier, target: Soldier, from: Vector3, dir: Vector3) -> StringName:
	var space := shooter.get_world_3d().direct_space_state
	var exclude: Array[RID] = [shooter.get_rid()]
	for child in shooter.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var gear := shooter.get_node_or_null(^"Gear") as GearRig
	if gear:
		exclude.append_array(gear.armor_rids())
	var start := from
	for i in Ballistics.MAX_PENETRATIONS:
		var query := PhysicsRayQueryParameters3D.create(start, from + dir * Ballistics.RANGE, (1 << 0) | (1 << 1) | (1 << 3), exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return &""
		var collider: Object = hit.collider
		if collider is VoxelArmor:
			exclude.append(collider.get_rid())
			start = hit.position
			continue
		var vitals := Vitals.find_on(collider)
		if vitals == null:
			return &""
		var part: StringName = collider.get_meta(&"body_part", Vitals.TORSO)
		if BodyVolume.entry(collider as Node3D, part, hit.position, dir, BodyVolume.body_of(collider)).is_empty():
			exclude.append(collider.get_rid())
			start = hit.position
			continue
		return part if vitals.get_parent() == target else &""
	return &""


## Where `who`'s chest and right upper arm hitboxes sit (his own frame), his model's pose and
## speed: what a centre-mass check that comes out arms-heavy needs to say why.
static func _pose_note(who: Soldier) -> String:
	var at := {}
	for child in who.get_children():
		var area := child as Area3D
		if area and StringName(area.get_meta(&"body_part", &"")) in [Vitals.CHEST, Vitals.UPPER_ARM_R]:
			for shape in area.get_children():
				if shape is CollisionShape3D:
					at[area.get_meta(&"body_part")] = who.to_local((shape as Node3D).global_position).snapped(Vector3.ONE * 0.01)
	return "pose %s, speed %.2f, hitboxes %s, rotation %.2f" % [who.model._last_pose, who.model._speed, at, who.rotation.y]


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return v[int(v.size() / 2.0)]


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


## A human leading fire team B (Captain, co-op playtest 2026-10-15: "B team doesn't follow him
## or his orders very well"): his team forms on him 60 m from the squad lead, and his order
## goes to his team only, without handing the squad's lead to him.
func _test_human_team_lead() -> void:
	print("A human team leader")
	var squad := level.squad_for(&"friendly")
	var lead := squad.leader
	var other := _squad().filter(func(s: Soldier) -> bool: return s.fire_team != (lead.fire_team if lead.fire_team >= 0 else 0) and s.fire_team >= 0)
	check(not other.is_empty(), "there is a second fire team")
	if other.is_empty():
		return
	var team: int = (other[0] as Soldier).fire_team
	var slot := 99
	for s: Soldier in other:
		if s.fire_team == team:
			slot = mini(slot, s.squad_slot) if s.squad_slot >= 0 else slot
	var guest: Soldier = load("res://scenes/soldier.tscn").instantiate()
	guest.name = "2"
	level.players.add_child(guest)
	_place(lead, Vector3(0, 0.1, 12))
	_place(guest, Vector3(60, 0.1, 40))
	guest.fire_team = team
	guest.squad_slot = slot
	guest.global_basis = Basis.looking_at(Vector3(0, 0, -1))
	await _seconds(45.0)
	var mates := _squad().filter(func(s: Soldier) -> bool: return s.fire_team == team and s.squad_slot >= 0)
	var near := mates.filter(func(s: Soldier) -> bool: return _flat(s.global_position, guest.global_position) < 30.0)
	print("    lead %s t%d, guest t%d slot %d ai %s up %s, mates %s" % [lead.name, lead.fire_team, guest.fire_team, guest.squad_slot, guest.is_ai(), guest.vitals.is_up(), mates.map(func(s: Soldier) -> String: return "%s s%d t%d" % [s.name, s.squad_slot, s.fire_team])])
	check(squad.human_team_lead_of(guest) == team, "the guest is recognised as team %d's leader" % team)
	for m: Soldier in mates:
		print("    %s %.1f m from guest, %.1f from lead, slot %s %s" % [m.name, _flat(m.global_position, guest.global_position), _flat(m.global_position, lead.global_position), squad.follow_point(m), m.ai_status])
	check(near.size() == mates.size(), "his team gathers round him, 60 m from the lead (%d of %d within 30 m)" % [near.size(), mates.size()])
	var point := guest.global_position + Vector3(0, 0, -20)
	guest.server_squad_command("hold", point, PackedStringArray())
	check(squad.leader == lead, "his order doesn't make him the squad's lead")
	var held := mates.filter(func(s: Soldier) -> bool: return SquadAI.of(s).order == Squad.Order.HOLD)
	var others_held := _squad().filter(func(s: Soldier) -> bool: return s.fire_team != team and SquadAI.of(s).order == Squad.Order.HOLD)
	check(held.size() == mates.size() and others_held.is_empty(), "his team holds and the lead's team doesn't (%d of %d, %d others)" % [held.size(), mates.size(), others_held.size()])
	await _seconds(3.0)
	check(mates.all(func(s: Soldier) -> bool: return SquadAI.of(s).order == Squad.Order.HOLD), "and keeps holding while the lead is elsewhere")
	guest.queue_free()
	await _frames(2)
