extends Node
## Headless squad-structure checks: roles and fire teams for 1, 2 and 4 players, role kits,
## the command menu's Target, Combat mode and Team, AI callouts and the HUD roster. Hosts a
## real session with the squad (hostiles removed, test ones staged by hand).
##   <voxel godot exe> --headless --path . res://tests/roles_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var menu: CommandMenu
var callouts: Callouts


func _ready() -> void:
	GameState.zone_id = "test_roles" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.MEDIC  # picked in the main menu before hosting
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("ROLES TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	menu = player._hud.command_menu
	callouts = level.callouts
	_remove_hostiles()
	await _frames(10)
	_test_assignment()
	_test_menu_picker()
	await _test_one_player()
	_test_kits()
	await _test_more_players()
	await _test_stable_slots()
	await _test_combat_modes()
	await _test_target()
	_test_team()
	_test_roster()
	await _test_callout_rules()
	await _test_callout_events()
	GameState.delete_save()
	print("ROLES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Roles and fire teams -------------------------------------------------

func _test_assignment() -> void:
	print("Slot assignment (Roles.assign)")
	var layout := Roles.layout()
	check(layout.size() == 8, "8 slots (%d)" % layout.size())
	for team in 2:
		var roles := layout.filter(func(s: Dictionary) -> bool: return s.team == team).map(func(s: Dictionary) -> StringName: return s.role)
		check(roles.size() == 4 and roles.count(Roles.MEDIC) == 1, "fire team %s: four slots, one medic %s" % [Roles.TEAMS[team], roles])
	check(Roles.ids().size() == 6 and Roles.has(&"grenadier") and Roles.has(&"autorifleman"), "six roles from data/roles.json")
	for picks: Array in [[&"team_leader"], [&"medic"], [&"medic", &"medic"], [&"marksman", &"marksman"],
			[&"team_leader", &"medic", &"marksman", &"grenadier"], [&"medic", &"medic", &"medic", &"rifleman"],
			[&"marksman", &"marksman", &"marksman", &"marksman"]]:
		var plan := Roles.assign(picks)
		var ok := true
		for i in picks.size():
			ok = ok and plan.slots[i] >= 0 and plan.roles[plan.slots[i]] == picks[i]
		ok = ok and Array(plan.slots).filter(func(s: int) -> bool: return s >= 0).size() == picks.size()
		var medics := [0, 0]
		for s in plan.roles.size():
			if plan.roles[s] == Roles.MEDIC:
				medics[layout[s].team] += 1
		check(ok and medics[0] >= 1 and medics[1] >= 1, "%d players %s: everyone gets their role, both teams keep a medic (%s)" % [picks.size(), picks, medics])
	var kept := Roles.assign([&"medic", &"team_leader"], [7, -1])
	check(kept.slots[0] == 7, "a player keeps the slot they already hold")
	var two := Roles.assign([&"marksman", &"marksman"])
	check(two.slots[0] == 5 and two.slots[1] == 6 and two.roles[6] == Roles.MARKSMAN, "two marksmen: the second takes team B's rifleman slot (%s)" % [two.slots])
	var three := Roles.assign([&"marksman", &"marksman", &"rifleman"], [5, 6, -1], [&"marksman", &"marksman", &""])
	check(three.slots[0] == 5 and three.slots[1] == 6 and three.roles[6] == Roles.MARKSMAN and three.slots[2] >= 0 and three.roles[three.slots[2]] == Roles.RIFLEMAN,
		"a rifleman joining doesn't move the marksman out of the converted slot (%s)" % [three.slots])
	var medic_kept := Roles.assign([&"rifleman"], [3], [&"rifleman"])
	check(medic_kept.slots[0] != 3 and medic_kept.roles[3] == Roles.MEDIC, "a non-medic never keeps a medic slot")


func _test_menu_picker() -> void:
	print("Main menu role picker")
	var picker: OptionButton = $Main/Menu.role_picker
	check(picker.item_count == 6 and picker.get_item_metadata(picker.selected) == Roles.MEDIC, "lists the six roles, showing your pick")
	picker.select(picker.item_count - 1)
	picker.item_selected.emit(picker.item_count - 1)
	check(Roles.local_choice == picker.get_item_metadata(picker.item_count - 1), "picking one sets the role sent to the host")
	Roles.local_choice = Roles.MEDIC


func _test_one_player() -> void:
	print("One player")
	check(player.role == Roles.MEDIC and player.fire_team == 0 and player.squad_slot == 3, "the host plays the role picked in the menu: medic, team A")
	check(_squad().size() == 7, "AI fills the other 7 slots (%d)" % _squad().size())
	_check_teams("1 player")
	check(_ai_in_role(Roles.MEDIC).size() == 1 and _ai_in_role(Roles.MEDIC)[0].fire_team == 1, "AI takes only team B's medic slot")
	level.request_role.rpc_id(1, "grenadier")  # the same request a client sends on join
	await _frames(3)
	check(player.role == Roles.GRENADIER and player.fire_team == 0, "picking grenadier moves the player to that slot")
	check(_ai_in_role(Roles.MEDIC).size() == 2 and _squad().size() == 7, "and an AI medic fills team A's medic slot again")
	_check_teams("after the switch")
	check(player.buddy != null and player.buddy.buddy == player and player.buddy.squad_slot == Roles.buddy_slot(player.squad_slot),
		"battle buddies follow the slots")


func _test_kits() -> void:
	print("Role kits")
	var marksman: Soldier = _ai_in_role(Roles.MARKSMAN)[0]
	check(marksman.inventory.slots[&"primary"] == &"m110" and marksman.inventory.count_of(&"mag_762") == 5 and marksman.inventory.slots[&"sidearm"] == &"m17",
		"marksman: M110, 7.62 magazines and an M17")
	var medic: Soldier = _ai_in_role(Roles.MEDIC)[0]
	check(medic.inventory.count_of(&"ifak") >= 3 and medic.inventory.count_of(&"trauma_kit") == 1, "medic: extra IFAKs (%d) and a trauma kit" % medic.inventory.count_of(&"ifak"))
	var rifleman: Soldier = _ai_in_role(Roles.RIFLEMAN)[0]
	check(rifleman.inventory.count_of(&"trauma_kit") == 0, "others carry no trauma kit")
	var grenadier: Soldier = _ai_in_role(Roles.GRENADIER)[0] if not _ai_in_role(Roles.GRENADIER).is_empty() else null
	if grenadier == null:
		grenadier = level.spawn_soldier({"name": "TestGrenadier", "faction": "friendly", "variant": "multicam", "pos": Vector3(30, 0.1, 40),
			"loadout": [], "role": "grenadier", "combat": 0.5, "discipline": 0.5, "guard": true})
	check(grenadier.inventory.count_of(&"frag_grenade") >= 3 and grenadier.inventory.count_of(&"smoke_grenade") >= 3, "grenadier: extra frags and smokes")
	if grenadier.name == &"TestGrenadier":
		grenadier.queue_free()
	var ar: Soldier = _ai_in_role(Roles.AUTORIFLEMAN)[0]
	check(ar.inventory.spare_rounds(&"mag_556") > rifleman.inventory.spare_rounds(&"mag_556"), "autorifleman: extra magazines (%d spare rounds)" % ar.inventory.spare_rounds(&"mag_556"))
	for s: Soldier in _squad():
		check(s.inventory.slots[&"vest"] == &"plate_carrier" and s.inventory.slots[&"helmet"] == &"helmet" and s.active_weapon() != null,
			"%s (%s) wears the base kit and has a weapon" % [s.name, Roles.display_name(s.role)])


func _test_more_players() -> void:
	print("Two and four players")
	level.player_roles[2] = Roles.MEDIC
	var g2 := _add_guest(2)
	level.rebalance_squad()
	await _frames(2)
	check(g2.role == Roles.MEDIC and g2.fire_team == 1, "a second player who picked medic is team B's medic")
	check(_squad().size() == 6 and _ai_in_role(Roles.MEDIC).size() == 1 and _ai_in_role(Roles.MEDIC)[0].fire_team == 0, "the AI medic stays only in team A")
	_check_teams("2 players")
	level.player_roles[3] = Roles.MARKSMAN
	level.player_roles[4] = Roles.MARKSMAN
	CompoundLevel.player_role_kits = true
	var g3 := _add_guest(3)
	var g4 := _add_guest(4)
	level.rebalance_squad()
	await _frames(2)
	CompoundLevel.player_role_kits = false
	check(g3.role == Roles.MARKSMAN and g4.role == Roles.MARKSMAN, "four players: both marksman picks are respected")
	check(_squad().size() == 4 and _ai_in_role(Roles.MARKSMAN).is_empty() and _ai_in_role(Roles.RIFLEMAN).is_empty(),
		"the second marksman takes the rifleman's slot; 4 AI left (%d)" % _squad().size())
	_check_teams("4 players")
	check(g4.inventory.slots[&"primary"] == &"m110", "with player role kits on, a player starts in their role's kit")
	for g: Soldier in [g2, g3, g4]:
		g.queue_free()
	level.player_roles.erase(2)
	level.player_roles.erase(3)
	level.player_roles.erase(4)
	await _frames(1)
	level.rebalance_squad()
	await _frames(2)
	check(_squad().size() == 7 and _ai_in_role(Roles.MEDIC).size() == 2 and _ai_in_role(Roles.RIFLEMAN).size() == 1, "when they leave, AI fills their slots in the slots' roles")
	_check_teams("back to 1 player")


## Players who share a role keep their slots while others join and switch roles, and only
## the AI in the slots that change hands are replaced.
func _test_stable_slots() -> void:
	print("Stable slots as players join and switch")
	level.player_roles[2] = Roles.MARKSMAN
	level.player_roles[3] = Roles.MARKSMAN
	var g2 := _add_guest(2)
	var g3 := _add_guest(3)
	level.rebalance_squad()
	await _frames(2)
	var slot3 := g3.squad_slot
	var team3 := g3.fire_team
	check(g2.role == Roles.MARKSMAN and g3.role == Roles.MARKSMAN and slot3 >= 0, "two marksmen (slots %d, %d)" % [g2.squad_slot, slot3])
	var before := _ai_by_slot()
	var g4 := _add_guest(4)  # joined, pick not here yet
	level.rebalance_squad()
	await _frames(2)
	check(g4.squad_slot == -1 and g4.fire_team == -1 and _ai_by_slot() == before, "a player whose pick hasn't arrived waits outside the squad; no AI is replaced")
	level.player_roles[4] = Roles.RIFLEMAN
	level.rebalance_squad()
	await _frames(2)
	var rifle_slot := g4.squad_slot
	check(rifle_slot >= 0 and g4.role == Roles.RIFLEMAN, "the third player's pick arrives: rifleman (slot %d)" % rifle_slot)
	check(g3.squad_slot == slot3 and g3.fire_team == team3 and g3.role == Roles.MARKSMAN, "the second marksman keeps slot %d and team %s (%d)" % [slot3, Roles.TEAMS[team3], g3.squad_slot])
	check(_ai_changed(before, _ai_by_slot()) == [rifle_slot], "only the AI in the newcomer's slot is replaced (%s)" % [_ai_changed(before, _ai_by_slot())])
	before = _ai_by_slot()
	level.player_roles[4] = Roles.TEAM_LEADER
	level.rebalance_squad()
	await _frames(2)
	var tl_slot := g4.squad_slot
	check(g4.role == Roles.TEAM_LEADER and tl_slot != rifle_slot, "the third player switches to team leader (slot %d)" % tl_slot)
	check(g3.squad_slot == slot3 and g3.fire_team == team3, "the second marksman still holds slot %d" % slot3)
	var changed := _ai_changed(before, _ai_by_slot())
	changed.sort()
	var expected := [rifle_slot, tl_slot]
	expected.sort()
	check(changed == expected, "only the AI in the slots the newcomer left and took change (%s)" % [changed])
	_check_teams("3 players")
	for g: Soldier in [g2, g3, g4]:
		g.queue_free()
	for id in [2, 3, 4]:
		level.player_roles.erase(id)
	await _frames(1)
	level.rebalance_squad()
	await _frames(2)
	check(_squad().size() == 7, "back to one player and 7 AI")


## Slot -> AI instance id, for the friendly AI.
func _ai_by_slot() -> Dictionary:
	var out := {}
	for s: Soldier in _squad():
		out[s.squad_slot] = s.get_instance_id()
	return out


## Slots whose AI differs between two _ai_by_slot() snapshots.
func _ai_changed(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for slot in Roles.slot_count():
		if before.get(slot, 0) != after.get(slot, 0):
			out.append(slot)
	return out


func _check_teams(when: String) -> void:
	var everyone: Array = _squad() + level.players.get_children().filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
	for team in 2:
		var members := everyone.filter(func(s: Soldier) -> bool: return s.fire_team == team)
		var medics := members.filter(func(s: Soldier) -> bool: return s.role == Roles.MEDIC)
		check(members.size() == 4 and medics.size() >= 1, "%s: fire team %s has 4 members and a medic (%d, %d)" % [when, Roles.TEAMS[team], members.size(), medics.size()])


# --- Command menu ----------------------------------------------------------

func _test_combat_modes() -> void:
	print("Combat mode")
	_place(player, Vector3(0, 0.1, 40))
	player.rotation = Vector3.ZERO
	# The removed hostiles were seen at the start: wait for that contact to fade, then settle.
	await _wait_for(func() -> bool: return _squad().all(func(s: Soldier) -> bool: return not SquadAI.of(s).in_contact()), 12.0)
	await _seconds(7.0)
	check(_squad().all(func(s: Soldier) -> bool: return SquadAI.of(s).combat_mode == Squad.CombatMode.COMBAT), "Combat is the default")
	check(_count(func(s: Soldier) -> bool: return s.want_crouch) == 7, "in Combat, halted squadmates crouch (%d of 7)" % _count(func(s: Soldier) -> bool: return s.want_crouch))
	_menu(KEY_QUOTELEFT, [KEY_7, KEY_2])  # Combat mode > Aware
	await _seconds(1.0)
	check(_squad().all(func(s: Soldier) -> bool: return SquadAI.of(s).combat_mode == Squad.CombatMode.AWARE), "~ 7 2 sets everyone to Aware")
	check(_count(func(s: Soldier) -> bool: return s.want_crouch) == 0, "Aware: they stand while halted")
	_menu(KEY_QUOTELEFT, [KEY_7, KEY_4])  # Stealth
	_place(player, Vector3(0, 0.1, 55))
	await _seconds(1.5)
	check(_count(func(s: Soldier) -> bool: return s.want_crouch) == 7 and _count(func(s: Soldier) -> bool: return s.want_sprint) == 0,
		"Stealth: everyone stays crouched and nobody sprints, even moving up")
	_menu(KEY_QUOTELEFT, [KEY_7, KEY_1])  # Safe
	_place(player, Vector3(0, 0.1, 40))
	await _seconds(6.0)
	var hostile := _spawn_test_hostile("SafeTest", Vector3(-8, 0.1, 26))
	await _seconds(2.0)
	var safe := _squad().filter(func(s: Soldier) -> bool: return SquadAI.of(s).target != null)
	check(not safe.is_empty(), "Safe squadmates see the enemy (%d)" % safe.size())
	check(safe.all(func(s: Soldier) -> bool: return not SquadAI.of(s).weapons_free() and not s.want_aim and SquadAI.of(s).intent != SquadAI.Intent.FIGHT),
		"Safe: weapons lowered, they hold fire and don't start a fight")
	check(hostile.vitals.injury() <= 0.0, "nobody has fired at it")
	_set_hold_fire(true)  # the player stands in their line of fire: check, don't shoot
	safe[0].suppress(0.3, hostile.global_position)  # rounds land close
	await _seconds(0.3)
	var returning := safe.all(func(s: Soldier) -> bool:
		var brain := SquadAI.of(s)
		brain.hold_fire = false
		var free := brain.weapons_free()
		brain.hold_fire = true
		return free)
	check(returning and SquadAI.of(safe[-1]).fighting(), "once one of them is fired upon, the squad returns fire")
	_free(hostile)
	await _seconds(0.5)
	_set_hold_fire(false)
	_menu(KEY_QUOTELEFT, [KEY_7, KEY_3])  # back to Combat
	level.squad_for(&"friendly").engaged_at = -1000.0
	check(_squad().all(func(s: Soldier) -> bool: return SquadAI.of(s).combat_mode == Squad.CombatMode.COMBAT), "~ 7 3 puts them back in Combat")


func _test_target() -> void:
	print("Target")
	await _seconds(3.0)
	_set_hold_fire(true)
	var near := _spawn_test_hostile("NearTest", Vector3(2, 0.1, 30))
	var far := _spawn_test_hostile("FarTest", Vector3(14, 0.1, 24))
	await _seconds(1.0)
	var gunner := _slot(1)  # F2: team A's autorifleman
	var lookout := Vector3(6, 0.1, 40)  # open ground with both enemies in sight, the near one closer
	_place(gunner, lookout)
	check(SquadAI.of(gunner)._find_target() == near, "without orders, %s picks the closest enemy" % gunner.name)
	_aim(player, far.global_position + Vector3.UP * 1.2)
	await _frames(3)
	check(menu.enemy_under_crosshair() == far, "the enemy under the crosshair is found")
	_press(KEY_F2)
	_press(KEY_2)
	_press(KEY_1)  # Target > Target that enemy
	check(SquadAI.of(gunner).focus == far and SquadAI.of(_slot(0)).focus == null,
		"F2 2 1: %s focuses on the enemy under the crosshair, %s doesn't" % [gunner.name, _slot(0).name])
	_place(gunner, lookout)
	var aimed_at := SquadAI.of(gunner)._find_target()
	check(aimed_at == far, "and engages it although another enemy is closer (target: %s)" % (aimed_at.name if aimed_at else "none"))
	_aim(player, player.global_position + Vector3(0, 1.4, -40))
	await _frames(2)
	_press(KEY_F2)
	_press(KEY_2)
	_press(KEY_1)
	check(SquadAI.of(gunner).focus == far, "with no enemy under the crosshair, the order isn't sent")
	menu.close()
	_press(KEY_F2)
	_press(KEY_2)
	_press(KEY_2)  # Target > No target
	check(SquadAI.of(gunner).focus == null, "No target clears it")
	var squad := level.squad_for(&"friendly")
	var names := PackedStringArray([String(gunner.name)])
	check(not squad.command(player, "target:%s" % _slot(0).name, Vector3.ZERO, names), "the host won't target a friendly")
	var hidden := _spawn_test_hostile("HiddenTest", Vector3(3, 0.1, -8))  # inside the main building
	await _frames(2)
	check(not Squad.sees(player, hidden) and Squad.sees(player, far), "the main building hides HiddenTest from the player; FarTest is in sight")
	check(not squad.command(player, "target:HiddenTest", Vector3.ZERO, names), "the host won't target an enemy the player can't see")
	player._server_squad_command.rpc_id(1, "target:HiddenTest", Vector3.ZERO, names)
	await _frames(1)
	check(player._hud._message.text == "Can't target that" and SquadAI.of(gunner).focus == null, "a rejected order tells the player")
	_free(hidden)
	check(squad.command(player, "target:FarTest", Vector3.ZERO, names) and SquadAI.of(gunner).focus == far, "the host takes a target by name")
	far.vitals.server_damage(500.0)
	await _seconds(0.5)
	check(SquadAI.of(gunner).focus == null, "a target that goes down is dropped")
	_free(near)
	_free(far)
	_set_hold_fire(false)


func _test_team() -> void:
	print("Team")
	var a := _slot(1)
	var b := _slot(3)
	_press(KEY_F2)
	_press(KEY_F4, true)  # Shift+F4 adds slot 4
	check(menu.selected == PackedStringArray([a.name, b.name]), "F2, Shift+F4 select %s and %s" % [a.name, b.name])
	_press(KEY_9)
	_press(KEY_3)
	_press(KEY_1)  # Team > Assign to team > Red
	check(a.color_team == "red" and b.color_team == "red" and _slot(0).color_team == "", "9 3 1 puts them in the red team")
	_press(KEY_QUOTELEFT)
	_press(KEY_9)
	_press(KEY_4)
	_press(KEY_1)  # Team > Select team > Red
	check(menu.is_open() and menu.selected == PackedStringArray([a.name, b.name]), "~ 9 4 1 selects the red team and keeps the menu open")
	_press(KEY_9)
	_press(KEY_2)  # Team > Select fire team B
	var team_b := PackedStringArray(_squad().filter(func(s: Soldier) -> bool: return s.fire_team == 1).map(func(s: Soldier) -> String: return String(s.name)))
	check(menu.selected == team_b and team_b.size() == 4, "9 2 selects fire team B %s" % [team_b])
	_press(KEY_7)
	_press(KEY_4)  # Combat mode > Stealth, team B only
	check(_squad().all(func(s: Soldier) -> bool: return (SquadAI.of(s).combat_mode == Squad.CombatMode.STEALTH) == (s.fire_team == 1)),
		"orders then go to fire team B only")
	_press(KEY_QUOTELEFT)
	_press(KEY_9)
	_press(KEY_1)  # Team > Select fire team A
	var team_a := PackedStringArray(_squad().filter(func(s: Soldier) -> bool: return s.fire_team == 0).map(func(s: Soldier) -> String: return String(s.name)))
	check(menu.selected == team_a and team_a.size() == 3, "9 1 selects fire team A's squadmates %s" % [team_a])
	menu.close()
	_menu(KEY_QUOTELEFT, [KEY_7, KEY_3])  # everyone back to Combat
	_menu(KEY_F4, [KEY_9, KEY_3, KEY_5])  # slot 4 to White
	check(b.color_team == "" and a.color_team == "red", "White takes %s out of the red team" % b.name)
	var mount: Array = CommandMenu.MENU["items"].filter(func(i: Dictionary) -> bool: return i["label"] == "Mount")
	check(mount.size() == 1 and (mount[0]["items"] as Array).is_empty(), "Mount is listed but not built (vehicles come in wave 5)")


func _test_roster() -> void:
	print("Roster")
	var text := player._hud._squad_lines(player)
	var lines := text.strip_edges().split("\n")
	check(lines.size() == 9, "the HUD roster lists all 8 slots under its header (%d lines)" % lines.size())
	check(text.contains("F1 %s [A, Team Leader]: " % _slot(0).name) and text.contains("F8 %s [B, Medic]: " % _slot(7).name), "lines show fire team and role")
	check(text.contains("F3 You [A, Grenadier]"), "including your own")
	check(text.contains("F2 %s [A, Autorifleman, Red]: " % _slot(1).name), "and colour teams")
	var health_shown := false
	for line in lines:
		health_shown = health_shown or line.contains("HP") or line.contains("%")
	check(not health_shown, "still no health in the roster")
	var roster := menu.roster()
	var ordered := roster.size() == 8
	for i in range(1, roster.size()):
		ordered = ordered and roster[i - 1].squad_slot < roster[i].squad_slot
	check(ordered, "F-keys follow the squad slots (team A, then B)")


# --- Callouts --------------------------------------------------------------

func _test_callout_rules() -> void:
	print("Callouts: rules")
	var first := _slot(0)
	var second := _slot(1)
	var line := "%s: Reloading!" % first.name
	# Squadmates talk on their own too: start from a clean slate and only look at these two.
	callouts._last_by_speaker.clear()
	callouts._last_by_key.clear()
	callouts._last_by_side_key.clear()
	callouts._pending.clear()
	callouts.sent.clear()
	callouts.shown.clear()
	var said := func(who: Soldier, id: StringName) -> Array:
		return callouts.sent.filter(func(c: Dictionary) -> bool: return c.speaker == String(who.name) and c.id == id)
	check(callouts.say(first, &"reloading"), "%s calls Reloading!" % first.name)
	check(said.call(first, &"reloading")[0].to == PackedInt32Array([1]), "sent to the friendly player (peer 1)")
	await _frames(1)
	check(callouts.shown.any(func(c: Dictionary) -> bool: return c.speaker == String(first.name) and c.text == "Reloading!") and line in callouts.current_lines(),
		"and shown here as a subtitle")
	await _frames(2)
	var subtitles: Label = null
	for child in player._hud.get_children():
		if child is Callouts.Subtitles:
			subtitles = child
	check(subtitles != null and subtitles.text.contains(line), "the HUD shows it")
	check(not callouts.say(first, &"moving") and said.call(first, &"moving").is_empty(), "a speaker doesn't talk again right away")
	check(callouts.say(second, &"moving"), "another speaker can")
	check(callouts.say(first, &"frag_out"), "urgent calls (Frag out!) cut in")
	var frag_time := float(said.call(first, &"frag_out")[0].time)
	await _seconds(Callouts.SPEAKER_GAP_S + 0.3)
	var waited: Array = said.call(first, &"moving")
	check(waited.size() == 1 and float(waited[0].time) - frag_time >= Callouts.SPEAKER_GAP_S - 0.05,
		"the held-back Moving! follows once the speaker's gap has passed")
	await _seconds(Callouts.SPEAKER_GAP_S + 0.1)
	check(not callouts.say(first, &"reloading"), "the same callout doesn't repeat within %.0f s" % Callouts.REPEAT_GAP_S)
	await _seconds(0.3)
	check(said.call(first, &"reloading").size() == 1, "and a repeat isn't held back for later either")
	var hostile := _spawn_test_hostile("ChatterTest", Vector3(75, 0.1, -75))  # out of sight
	check(callouts.say(hostile, &"reloading") and said.call(hostile, &"reloading")[0].to.is_empty(), "a hostile callout goes to nobody")
	await _frames(2)
	check(not callouts.shown.any(func(c: Dictionary) -> bool: return c.speaker == "ChatterTest"), "so it isn't shown")
	var guest := _add_guest(2)
	check(callouts.recipients(first) == PackedInt32Array([1]), "players not connected (a fake peer 2) aren't sent anything")
	guest.queue_free()
	var other := _spawn_test_hostile("ChatterTest2", Vector3(-75, 0.1, -75))
	var spotters: Array = _squad().slice(2, 5)  # three AI besides the two above
	for s: Soldier in spotters:
		callouts._last_by_speaker.erase(String(s.name))
		callouts._last_by_key.erase("%s/contact" % s.name)
	callouts._last_by_side_key.clear()
	check(callouts.contact(spotters[0], hostile), "%s spots an enemy and calls the contact" % spotters[0].name)
	check(not callouts.contact(spotters[1], hostile) and said.call(spotters[1], &"contact").is_empty(),
		"a squadmate who spots the same enemy right after stays quiet")
	check(callouts.contact(spotters[2], other), "a different enemy is still called")
	_free(other)
	_free(hostile)
	check(Callouts.play(&"reloading", first) == null, "no audio file yet: Callouts.play stays silent")
	var origin := Node3D.new()
	add_child(origin)
	check(Callouts.direction_word(origin, Vector3(0, 0, -80)) == "front" and Callouts.direction_word(origin, Vector3(30, 0, 0)) == "right"
		and Callouts.round_distance(83.0) == 80, "directions and distances read like Contact, front, 80 m")
	origin.queue_free()




func _test_callout_events() -> void:
	print("Callouts: events")
	_place(player, Vector3(0, 0.1, 16))  # inside the gate, with low cover around
	player.rotation = Vector3.ZERO
	var squad := level.squad_for(&"friendly")
	await _wait_for(func() -> bool: return _squad().all(func(s: Soldier) -> bool: return s.global_position.distance_to(squad.follow_point(s)) < 3.0), 20.0)
	_set_hold_fire(true)  # keep the stand-in alive while they take cover
	callouts.sent.clear()
	var hostile := _spawn_test_hostile("ContactTest", Vector3(0, 0.1, -1))
	await _wait_for(func() -> bool: return not _said(&"contact").is_empty(), 3.0)
	var contact := _said(&"contact")
	check(not contact.is_empty() and contact[0].text.begins_with("Contact, front, ") and contact[0].text.ends_with(" m"),
		"contact: %s" % (contact[0].text if not contact.is_empty() else "nothing"))
	await _wait_for(func() -> bool: return not _said(&"moving").is_empty(), 10.0)
	var moving := _said(&"moving")
	check(not moving.is_empty(), "bounding to cover: Moving! (%s)" % (moving[0].speaker if not moving.is_empty() else "nobody"))
	var answer := func() -> Array:
		return _said(&"covering").filter(func(c: Dictionary) -> bool:
			var mate := _ai(c.speaker)
			return mate != null and mate.buddy != null and _said(&"moving").any(func(m: Dictionary) -> bool: return m.speaker == String(mate.buddy.name)))
	await _wait_for(func() -> bool: return not answer.call().is_empty(), 6.0)
	var answered: Array = answer.call()
	check(not answered.is_empty(), "and the mover's battle buddy answers Covering! (%s)" % (answered[0].speaker if not answered.is_empty() else _log()))
	_free(hostile)
	await _seconds(Callouts.REPEAT_GAP_S)  # the contact fades before they may shoot again
	_set_hold_fire(false)
	var loader := _slot(6)
	while loader.inventory.consume_round(loader.active_slot):
		pass
	var reloaded := func() -> bool: return _said(&"reloading").any(func(c: Dictionary) -> bool: return c.speaker == String(loader.name))
	await _wait_for(reloaded, 8.0)
	check(reloaded.call(), "an empty magazine: %s calls Reloading! (%s, %s)" % [loader.name, loader.ai_status, SquadAI.of(loader).intent])
	var casualty := _slot(4)
	casualty.vitals.server_damage(500.0)
	await _frames(2)
	var down := _said(&"man_down")
	var expected := "Man down! %s is down" % casualty.name
	var buddy_name := String(casualty.buddy.name) if is_instance_valid(casualty.buddy) else "?"
	check(not down.is_empty() and down[-1].text == expected and down[-1].speaker == buddy_name,
		"%s's buddy calls %s" % [casualty.name, expected])
	casualty.vitals.server_revive(100.0)
	var thrower := squad.order_throw(player, &"smoke_grenade", Vector3(0, 0, 4), PackedStringArray())
	check(thrower != "" and _said(&"smoke_out").any(func(c: Dictionary) -> bool: return c.speaker == thrower), "%s throws smoke: Smoke out!" % thrower)
	await _seconds(1.0)
	var leader_ai := String(_slot(0).name)
	_slot(0).inventory.take(&"frag_grenade")  # in case the fight used theirs up
	thrower = squad.order_throw(player, &"frag_grenade", Vector3(0, 0, -2), PackedStringArray([leader_ai]))
	check(thrower == leader_ai and _said(&"frag_out").any(func(c: Dictionary) -> bool: return c.speaker == thrower), "%s throws a frag: Frag out! (thrower: '%s', said: %s)" % [leader_ai, thrower, _said(&"frag_out")])
	check(callouts.sent.all(func(c: Dictionary) -> bool: return c.to == PackedInt32Array([1])), "every squad callout went to the friendly player")




# --- Helpers ----------------------------------------------------------------

func _said(id: StringName) -> Array:
	return callouts.sent.filter(func(c: Dictionary) -> bool: return c.id == id)


func _squad() -> Array:
	var out := level.ai.get_children().filter(func(s: Node) -> bool: return s.faction == &"friendly" and not s.is_queued_for_deletion())
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.squad_slot < b.squad_slot)
	return out


func _ai_in_role(role: StringName) -> Array:
	return _squad().filter(func(s: Soldier) -> bool: return s.role == role)


func _count(condition: Callable) -> int:
	return _squad().filter(condition).size()


func _log() -> String:
	var out := PackedStringArray()
	for c in callouts.sent:
		var s := _ai(c.speaker)
		out.append("%s(buddy %s) %s %.1f" % [c.speaker, s.buddy.name if s and is_instance_valid(s.buddy) else "-", c.id, c.time])
	return ", ".join(out)


## The squadmate in squad slot `slot` (F-key slot + 1), or null.
func _slot(slot: int) -> Soldier:
	for s: Soldier in _squad():
		if s.squad_slot == slot:
			return s
	return null


func _free(node: Variant) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _add_guest(id: int) -> Soldier:
	var guest: Soldier = load("res://scenes/soldier.tscn").instantiate()
	guest.name = str(id)
	guest.position = Vector3(6 + id, 0.1, 30)
	level.players.add_child(guest)
	guest.set_physics_process(false)
	return guest


func _spawn_test_hostile(soldier_name: String, pos: Vector3) -> Soldier:
	var h := level.spawn_soldier({"name": soldier_name, "faction": "hostile", "variant": "urban", "pos": pos,
		"loadout": [], "combat": 0.3, "discipline": 0.5, "guard": true})
	SquadAI.of(h).set_physics_process(false)  # a stand-in: doesn't move or shoot
	return h


func _set_hold_fire(hold: bool) -> void:
	for s: Soldier in _squad():
		SquadAI.of(s).hold_fire = hold


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


## Opens the menu with `open_key` and presses `keys` in it.
func _menu(open_key: Key, keys: Array) -> void:
	_press(open_key)
	for k: Key in keys:
		_press(k)


func _press(key: Key, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	ev.shift_pressed = shift
	menu.handle_input(ev)


func _aim(s: Soldier, point: Vector3) -> void:
	var d := point - s.camera.global_position
	s.rotation.y = atan2(-d.x, -d.z)
	s.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
