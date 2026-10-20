extends Node
## Headless checks for voice squad orders: the bounded vocabulary (VoiceCommands), the
## push-to-talk key binding and box (VoiceOrder), and that a recognized phrase drives the
## squad exactly the way the matching keyboard order already does.
##   <voxel godot exe> --headless --path . res://tests/voice_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var voice: VoiceOrder


func _ready() -> void:
	GameState.zone_id = "test_voice" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("VOICE TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_vocabulary()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Alpha") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand for the question tests
	voice = player._hud.voice_order
	_remove_hostiles()
	await _frames(10)
	_test_key_binding()
	await _test_push_to_talk_box()
	await _test_order_dispatch()
	_test_unmatched_phrase()
	await _test_questions()
	GameState.delete_save()
	print("VOICE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_vocabulary() -> void:
	print("Vocabulary (VoiceCommands.resolve)")
	check(VoiceCommands.resolve("Select Three") == ["F3"], "case-insensitive: \"Select Three\" -> F3")
	check(VoiceCommands.resolve("  hold   position! ") == ["1", "3"], "punctuation and extra spaces are ignored")
	check(VoiceCommands.resolve("report") == ["5", "1"] and VoiceCommands.resolve("sitrep") == ["5", "1"], "aliases resolve to the same keys")
	check(VoiceCommands.resolve("go stealth") == ["7", "4"], "mode phrase")
	check(VoiceCommands.resolve("wedge up") == ["8", "1"], "formation phrase")
	check(VoiceCommands.resolve("dynamic formation") == ["8", "6"], "the newer formation entries resolve too")
	check(VoiceCommands.resolve("take cover") == ["1", "5"], "take cover")
	check(VoiceCommands.resolve("fall back") == ["1", "6"], "fall back")
	check(VoiceCommands.resolve("radio report") == ["5", "2"], "radio report (Status > Report enemy position)")
	check(VoiceCommands.resolve("heal up") == ["6", "5"], "heal up (Action > Heal up)")
	check(VoiceCommands.resolve("cancel") == ["Backspace"], "cancel is Backspace")
	check(VoiceCommands.resolve("all") == ["`"], "all is the select-all key")
	check(VoiceCommands.resolve("").is_empty(), "empty text matches nothing")
	check(VoiceCommands.resolve("cover me").is_empty(), "a phrase with no matching command (not yet in CommandMenu.MENU) matches nothing")
	check(VoiceCommands.resolve("go frag everyone forever").is_empty(), "nothing in the bounded vocabulary matches garbage text")


func _test_key_binding() -> void:
	print("Key binding")
	var events := InputMap.action_get_events(&"voice_order")
	check(events.size() == 1 and events[0] is InputEventKey and events[0].physical_keycode == KEY_T, "voice_order is T")


func _test_push_to_talk_box() -> void:
	print("Push-to-talk box")
	check(not voice.listening, "not listening at rest")
	voice.update_key(true)
	check(voice.listening and voice._box.visible, "holding T opens the text box")
	voice.update_key(false)
	check(not voice.listening and not voice._box.visible, "letting go without Enter cancels")
	check(player._hud._message.text == "", "and nothing was sent")

	voice.update_key(true)
	voice._box.text = "select all"
	voice._box.emit_signal("text_submitted", "select all")
	check(not voice.listening and player._hud.command_menu.selected.size() == level.ai.get_children().size(), "Enter in the box runs the typed order (select all)")
	voice.run("return to formation")  # back to a clean slate
	await _frames(1)


func _test_order_dispatch() -> void:
	print("Order dispatch matches the keyboard path (squad_test's F3/1/3 case)")
	var menu := player._hud.command_menu
	voice.run("select three")
	check(menu.is_open() and menu.selected == PackedStringArray(["Bravo"]), "\"select three\" selects Bravo and opens the menu (F1 is you, F2 Alpha, F3 Bravo)")
	voice.run("hold position")
	check(SquadAI.of(_ai("Bravo")).order == Squad.Order.HOLD and SquadAI.of(_ai("Alpha")).order == Squad.Order.FOLLOW,
		"\"select three\" then \"hold position\" holds only Bravo")
	check(not menu.is_open(), "the menu closes after the order, same as the keyboard path")
	voice.run("select all")
	voice.run("return to formation")
	check(SquadAI.of(_ai("Bravo")).order == Squad.Order.FOLLOW, "\"return to formation\" clears the hold")

	voice.run("select all")
	voice.run("hold fire")
	check(SquadAI.of(_ai("Alpha")).hold_fire, "\"hold fire\" reaches the squad")
	voice.run("select all")
	voice.run("open fire")
	check(not SquadAI.of(_ai("Alpha")).hold_fire, "\"open fire\" un-holds it")

	voice.run("select all")
	voice.run("wedge up")
	await _frames(1)
	check(level.squad_for(&"friendly").formation == "wedge", "\"wedge up\" sets the formation")


func _test_unmatched_phrase() -> void:
	print("Unmatched phrase")
	var menu := player._hud.command_menu
	menu.close()
	voice.run("do a barrel roll")
	check(not menu.is_open(), "garbage text opens nothing")
	check(player._hud._message.text.begins_with("Didn't catch"), "and the player is told (%s)" % player._hud._message.text)


func _test_questions() -> void:
	print("Asking a question (VoiceQuestions)")
	check(VoiceQuestions.resolve("How's your ammo?") == &"ammo", "ammo phrase")
	check(VoiceQuestions.resolve("You okay") == &"status", "status phrase")
	check(VoiceQuestions.resolve("any contacts") == &"contact", "contact phrase")
	check(VoiceQuestions.resolve("what's the weather").is_empty(), "garbage question text matches nothing")

	var alpha := _ai("Alpha")
	SquadAI.of(alpha).process_mode = Node.PROCESS_MODE_DISABLED  # we hand-place Alpha; don't fight the AI for it
	await _place_looking_at(alpha)
	check(voice.askable_target() == alpha, "a friendly under the crosshair is askable")
	voice.run("how much ammo do you have")
	var expect := "%s: %s" % [alpha.display_name(), AmmoReadout.text_of(AmmoReadout.summary(alpha))]
	check(player._hud._message.text == expect, "ammo answers with Alpha's real loadout (%s)" % player._hud._message.text)

	voice.run("whats your status")
	check(player._hud._message.text.begins_with(alpha.display_name() + ": "), "status answers too (%s)" % player._hud._message.text)

	alpha.threat_time = -1000.0
	voice.run("any contacts")
	check(player._hud._message.text == "%s: Nothing to report." % alpha.display_name(), "no recent contact: nothing to report")

	alpha.threat_pos = alpha.global_position + Vector3(10.0, 0, 0)
	alpha.threat_time = Soldier._now()
	voice.run("any contacts")
	check(player._hud._message.text.begins_with(alpha.display_name() + ": Contact,"), "a recent contact is reported (%s)" % player._hud._message.text)

	# Orders still work even with a squadmate in the crosshair: only a recognized question
	# phrase takes the "ask" path (askable_target alone isn't enough).
	voice.run("select all")
	check(player._hud.command_menu.selected.size() == level.ai.get_children().size(), "an order phrase still dispatches as an order, not a question")

	var civ := level.spawn_soldier({"name": "Civ1", "faction": "civilian", "variant": "multicam",
		"pos": alpha.global_position, "loadout": [], "combat": 0.0, "discipline": 0.0, "guard": false})
	await _frames(3)
	await _place_looking_at(civ)
	check(voice.askable_target() == civ, "a civilian under the crosshair is askable too")
	voice.run("whats your status")
	check(player._hud._message.text.begins_with(civ.display_name() + ": "), "a civilian answers too (%s)" % player._hud._message.text)
	civ.queue_free()


# --- Helpers --------------------------------------------------------------

## Stands the player 3 m from `target` (if any), looking straight at it, both level, and
## waits until the crosshair finds it (CommandMenu.soldier_under_crosshair, what asking aims
## with): the new transforms reach the physics server and the target's hitboxes their pose a
## frame or more later, and a squadmate following the player can be crossing the line (CI and
## R0245: three frames weren't always enough, and the question went to the order parser).
## Anyone else standing on the line (the civilian spawns where Alpha was put) steps aside first.
func _place_looking_at(target: Soldier) -> void:
	var stand := Vector3(0, 0.1, 30)
	var put := func() -> void:
		player.global_position = stand
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
		player.velocity = Vector3.ZERO
		if target:
			target.global_position = stand + Vector3(0, 0, -3.0)
			target.velocity = Vector3.ZERO
	put.call()
	if target:
		for s: Soldier in level.ai.get_children():
			if s != target and not s.is_queued_for_deletion() and absf(s.global_position.x - stand.x) < 1.5 \
					and s.global_position.z > stand.z - 4.5 and s.global_position.z < stand.z + 0.5:
				s.global_position = s.global_position + Vector3(4.0, 0, 0)
	await _frames(3)
	if target == null:
		return
	var deadline := Time.get_ticks_msec() + 3000
	while menu_crosshair() != target and Time.get_ticks_msec() < deadline:
		put.call()
		await get_tree().physics_frame
	if menu_crosshair() != target:
		var under := menu_crosshair()
		print("  (under the crosshair: %s, not %s at %s)" % [under.name if under else "nobody", target.name, target.global_position])


## Who the command menu's crosshair ray finds now (VoiceOrder.askable_target asks it).
func menu_crosshair() -> Soldier:
	return player._hud.command_menu.soldier_under_crosshair()


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
