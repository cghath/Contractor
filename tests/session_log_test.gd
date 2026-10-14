extends Node
## Headless checks for the session log (SessionLog, autoload/session_log.gd): off in a headless
## run; a session opened in a scratch parent takes the next number from its run_counter.txt;
## prints, warnings, errors and messages shown to the player land in session.log; each kind of
## issue writes one dump with the state of the game; a soldier fallen out of the world is an
## anomaly with its own dump; treatment lines say how far the casualty is and, when one is cut
## short, why (who dragged or put the casualty down); same-named hostiles, a body spawned as one
## and a target dummy each read as themselves; a session ends PASS when nothing unexpected
## happened, else FAIL, with a line in index.txt.
##   <voxel godot exe> --headless --path . res://tests/session_log_test.tscn
## Exits with the number of failures.

var failures := 0
var parent := ""


func _ready() -> void:
	GameState.zone_id = "test_session_log" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	Soldier.respawn_delay_s = 0.0  # these checks want the old instant respawn (the wait and spawn
	Soldier.spawn_protect_s = 0.0  # protection have their own checks in gameplay and missions)
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("SESSION_LOG TEST FAILED (timed out)")
		get_tree().quit(99))
	parent = OS.get_user_data_dir().path_join("session_log_test" + OS.get_environment("CONTRACTOR_TEST_TAG"))
	_remove(parent)  # this test's own scratch folder, never the real logs
	DirAccess.make_dir_recursive_absolute(parent)
	var counter := FileAccess.open(parent.path_join("run_counter.txt"), FileAccess.WRITE)
	counter.store_line("41")
	counter.close()
	check(SessionLog.session_id == "", "off in a headless run")
	await _test_quiet_session()
	await _test_issues()
	await _test_stuck_folder()
	await _test_settings()
	await _test_counter_lock()
	GameState.delete_save()
	print("SESSION_LOG TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## The settings menu (GameSettings, SettingsMenu; Captain, 2026-10-13), on a settings file of
## its own: defaults, saved and read back (keeping the file's other sections), volumes on the
## buses, video on the viewport, shadows on a sun, key rebinding with swaps, and the screen.
func _test_settings() -> void:
	print("Settings")
	var file := parent.path_join("settings_test.cfg")
	var other := ConfigFile.new()
	other.set_value("hand", "left", true)
	other.set_value(ControlOptions.SECTION, ControlOptions.GET_OUT_KEY, true)
	other.save(file)
	GameSettings.use_file(file)
	check(GameSettings.settings_path() == file, "on a settings file of its own (%s), never the player's" % GameSettings.settings_path())
	var base := 0.0025
	check(is_equal_approx(GameSettings.fov(), 80.0) and is_equal_approx(GameSettings.mouse_turn(base, false), base)
		and is_equal_approx(GameSettings.mouse_turn(base, true), base * 0.75) and not GameSettings.invert_y(),
		"defaults: 80 deg view, sensitivity 1x, 0.75x down sights, not inverted")
	GameSettings.set_value("video", "fov", 95.0)
	GameSettings.set_value("controls", "mouse_sensitivity", 1.5)
	GameSettings.reload()
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.settings_path())
	check(is_equal_approx(GameSettings.fov(), 95.0) and is_equal_approx(GameSettings.mouse_turn(base, false), base * 1.5)
		and cfg.get_value("hand", "left", false) == true and cfg.get_value(ControlOptions.SECTION, ControlOptions.GET_OUT_KEY, false) == true, "saved and read back, the file's other sections kept (fov %s, turn %s, hand %s, file %s)" % [GameSettings.fov(), GameSettings.mouse_turn(base, false), cfg.get_value("hand", "left", "none"), GameSettings.settings_path()])
	GameSettings.set_value("hud", "objective_markers", false)
	var markers_off := not bool(GameSettings.get_value("hud", "objective_markers"))
	GameSettings.set_value("hud", "objective_markers", true)
	check(markers_off, "the objective markers can be turned off")
	GameSettings.set_value("audio", "master", 0.5)
	GameSettings.set_value("audio", "effects", 0.0)
	var master := AudioServer.get_bus_index(&"Master")
	var sfx := AudioServer.get_bus_index(&"SFX")
	check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.01 and sfx >= 0 and AudioServer.is_bus_mute(sfx),
		"volumes go on the buses (master at half, effects off: muted)")
	GameSettings.set_value("video", "render_scale", 0.7)
	GameSettings.set_value("video", "antialiasing", "msaa4")
	var root := get_tree().root
	check(is_equal_approx(root.scaling_3d_scale, 0.7) and root.msaa_3d == Viewport.MSAA_4X, "render scale and anti-aliasing on the view")
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	GameSettings.set_value("video", "shadows", "off")
	GameSettings.apply_sun(sun)
	var off := not sun.shadow_enabled
	GameSettings.set_value("video", "shadows", "high")
	GameSettings.apply_sun(sun)
	check(off and sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 400.0), "shadows off, then high (400 m)")
	sun.free()
	var on_key := func(action: StringName, key: Key) -> bool:
		return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
			return e is InputEventKey and (e as InputEventKey).physical_keycode == key and not (e as InputEventKey).shift_pressed)
	GameSettings.bind(&"reload", KEY_T)
	var moved: bool = on_key.call(&"reload", KEY_T) and not on_key.call(&"reload", KEY_R)
	var swapped := GameSettings.bind(&"jump", KEY_T)
	check(moved and swapped == &"reload" and on_key.call(&"jump", KEY_T) and on_key.call(&"reload", KEY_SPACE),
		"rebinding: reload on T, then jump on T swaps reload to jump's old key (Space)")
	GameSettings.reload()
	GameSettings.apply_keys()
	check(on_key.call(&"jump", KEY_T) and GameSettings.key_for(&"reload") == KEY_SPACE, "and the bindings are saved")
	var shifted := InputMap.action_get_events(&"quick_treat").any(func(e: InputEvent) -> bool: return e is InputEventKey and (e as InputEventKey).shift_pressed)
	GameSettings.reset_keys()
	check(on_key.call(&"reload", KEY_R) and on_key.call(&"jump", KEY_SPACE) and shifted, "reset keys: R and Space again; Shift+H untouched")
	var screen := SettingsMenu.new()
	get_tree().root.add_child(screen)
	screen.open()
	await get_tree().process_frame
	var tabs := screen.find_children("*", "TabContainer", true, false)
	check(screen.is_open() and not tabs.is_empty() and (tabs[0] as TabContainer).get_tab_count() == 4 and screen._key_buttons.size() == GameSettings.BINDABLE.size(),
		"the settings screen: Video, Audio, Controls and Keys, a button for every bindable key")
	screen.close()
	check(not screen.is_open(), "and closes")
	screen.queue_free()
	GameSettings.reset_all()
	GameSettings.use_file("")
	GameSettings.apply_all()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The run counter's lock, shared with tools/run_log.sh (two runs in the same second both got
## R0232): a number waits for a live lock, and a killed run's stale lock is taken over.
func _test_counter_lock() -> void:
	print("The run counter's lock")
	var p := parent + "_counter"
	_remove(p)
	DirAccess.make_dir_recursive_absolute(p)
	var lock := p.path_join("run_counter.lock")
	DirAccess.make_dir_absolute(lock)  # another run is numbering
	var got := [0]
	var worker := Thread.new()
	worker.start(func() -> void: got[0] = SessionLog._next_number(p))
	await _seconds(0.5)
	var waited := worker.is_alive() and not FileAccess.file_exists(p.path_join("run_counter.txt"))
	DirAccess.remove_absolute(lock)  # it's done
	worker.wait_to_finish()
	check(waited and got[0] == 1 and not DirAccess.dir_exists_absolute(lock), "a session's number waits for a live lock, then takes 1 (%d)" % got[0])
	DirAccess.make_dir_absolute(lock)  # left by a killed run
	var stamped := FileAccess.get_modified_time(lock)
	var stale_was := SessionLog.counter_lock_stale_s
	SessionLog.counter_lock_stale_s = 1
	await _seconds(2.2)
	var started := Time.get_ticks_msec()
	var n := SessionLog._next_number(p)
	SessionLog.counter_lock_stale_s = stale_was
	check(stamped > 0 and n == 2 and Time.get_ticks_msec() - started < 3000 and not DirAccess.dir_exists_absolute(lock),
		"a stale lock is taken over: 2 at once (%d ms)" % (Time.get_ticks_msec() - started))
	_remove(p)


func _test_quiet_session() -> void:
	print("A quiet session")
	SessionLog.start(parent)
	check(SessionLog.session_id == "P0042", "numbered from the parent's counter (%s)" % SessionLog.session_id)
	check(FileAccess.get_file_as_string(parent.path_join("run_counter.txt")).strip_edges() == "42", "and the counter moves on")
	check(SessionLog.folder.get_file().begins_with("P0042-") and "-RUNNING-" in SessionLog.folder.get_file()
		and DirAccess.dir_exists_absolute(SessionLog.folder), "its folder is RUNNING while it's open")
	print("probe: a line the game prints")
	await _frames(3)
	var text := _log()
	check("session P0042 started" in text and "build " in text, "session.log starts with the session and the build")
	check("probe: a line the game prints" in text, "what the game prints is in it")
	SessionLog.finish()
	check(SessionLog.session_id == "" and "-PASS-" in SessionLog.folder.get_file() and DirAccess.dir_exists_absolute(SessionLog.folder),
		"nothing unexpected: the folder ends PASS")
	check(_index().contains("P0042 ") and _index().contains(" PASS "), "with a line in index.txt")


func _test_issues() -> void:
	print("A session where things go wrong")
	SessionLog.start(parent)
	check(SessionLog.session_id == "P0043", "the next session is P0043")
	push_warning("probe warning")
	for i in 2:
		_probe_error()  # the same error twice: logged twice, dumped once
	await _frames(3)
	var text := _log()
	check("!! WARNING: probe warning" in text and SessionLog.warnings >= 1, "a warning is logged")
	check(text.count("!! ERROR: probe error") == 2 and SessionLog.errors >= 2, "an error is logged every time")
	check("GDScript backtrace" in text or "_probe_error" in text, "with where it came from")
	check(_dumps("warning").size() == 1 and _dumps("error").size() == 1, "one dump per kind of issue (%s)" % [_dumps("")])
	var dump := FileAccess.get_file_as_string(SessionLog.folder.path_join(_dumps("error")[0]))
	check(dump.begins_with("Why: probe error") and "Soldiers (" in dump and "Last " in dump and "probe warning" in dump,
		"a dump says why, lists the soldiers and ends with the log")
	# A level with a soldier, who falls out of the world.
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	var level := CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.player_input.flash("probe flash")
	check("shown to the player: probe flash" in _log(), "what the player is shown is logged")
	var faller := level.spawn_soldier({"name": "Faller", "faction": "friendly", "variant": "multicam", "pos": Vector3(0, 0.1, 30),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(faller).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(5)
	faller.player_input.flash("probe AI message")  # an AI's own message (what it treats): no screen
	check(("%s (AI): probe AI message" % faller.log_name()) in _log() and not "shown to the player: probe AI message" in _log(),
		"an AI's message is logged as the AI's, never as shown to the player")
	# The safety net would put him back on the ground first (GroundGuard): this checks the
	# detection behind it, so it stands aside.
	level.get_node(^"GroundGuard").process_mode = Node.PROCESS_MODE_DISABLED
	faller.global_position = Vector3(5, -300, 30)
	await _seconds(SessionLog.CHECK_S * 2.5)
	check(("!! ANOMALY: %s fell out of the world" % faller.log_name()) in _log() and SessionLog.anomalies >= 1, "a soldier out of the world is an anomaly")
	var anomaly := _dumps("anomaly")
	check(anomaly.size() == 1, "with its own dump")
	if anomaly.size() == 1:
		var state := FileAccess.get_file_as_string(SessionLog.folder.path_join(anomaly[0]))
		var line := Array(state.split("\n")).filter(func(l: String) -> bool: return ("%s (friendly" % faller.log_name()) in l)
		check(line.size() == 1 and "at (5.0, -" in line[0] and SquadAI.Intent.keys().any(func(k: String) -> bool: return (k + ":") in line[0]),
			"the dump has the soldier: where, and the AI's intent (%s)" % [line])
		check("Player 1 (friendly" in state or "player 1" in state, "and the player")
	# Casualties and care (host side lines).
	var victim := level.spawn_soldier({"name": "Victim", "faction": "friendly", "variant": "multicam", "pos": player.global_position + Vector3(0.6, 0, 0),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(victim).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(5)
	victim.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.PISTOL, "distance": 12.0})
	await _frames(2)
	player.inventory.take(&"tourniquet")
	await player._treat(victim, &"tourniquet", Vitals.THIGH_L, true)
	var care := _lines_with("%s treats %s: tourniquet on %s at " % [player.log_name(), victim.log_name(), Vitals.part_name(Vitals.THIGH_L)])
	check(care.size() == 2 and ", started (" in care[0] and care[1].ends_with(" m, done") and _metres(care[0]) < Soldier.TREAT_REACH,
		"a treatment is logged as it starts and when it's done: who, whom, item, part, how far (%s)" % [care])
	await player._treat(victim, &"morphine", Vitals.THIGH_L, false)  # none carried
	check(("%s treats %s: morphine on" % [player.log_name(), victim.log_name()]) in _log() and "refused: " in _log(), "a refused treatment says why")
	var dying := level.spawn_soldier({"name": "Dying", "faction": "enemy", "variant": "multicam", "pos": player.global_position + Vector3(-2, 0, 0),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(dying).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(5)
	Harm.note_hit(dying, player)
	dying.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.FULL_POWER, "distance": 42.0})
	await _frames(3)
	var gone_down := _log()
	check(("%s died (enemy): round (full_power), head, by %s (friendly) at 42 m" % [dying.log_name(), player.log_name()]) in gone_down
		or ("%s went down (enemy): round (full_power), head, by %s (friendly) at 42 m" % [dying.log_name(), player.log_name()]) in gone_down,
		"a soldier going down or dying is logged: who, cause, body part, attacker, distance")
	victim.queue_free()
	dying.queue_free()
	await _test_care_lines(player, level)
	await _test_names(player, level)
	await _test_bug_report(player, level, faller)
	await _test_group_night(player, level)
	SessionLog.finish()
	check("-FAIL-" in SessionLog.folder.get_file() and DirAccess.dir_exists_absolute(SessionLog.folder), "something unexpected: the folder ends FAIL")
	check(_index().contains("P0043 ") and _index().contains(" FAIL "), "and index.txt says so")
	faller.queue_free()


## Treatment lines (Captain, P0164 queue 7): each says how far the casualty is, and one cut
## short says why: who dragged or put the casualty down, or how far the treater moved.
func _test_care_lines(player: Soldier, level: CompoundLevel) -> void:
	print("Treatment lines: how far, and who moved the casualty")
	var hurt := _quiet_soldier(level, "Hurt", "friendly", player.global_position + Vector3(1.5, 0, 0))
	var bearer := _quiet_soldier(level, "Bearer", "friendly", player.global_position + Vector3(2.5, 0, 0))
	await _frames(5)
	hurt.carriable_while_up = true  # can be lifted without knocking him out first
	hurt.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.PISTOL, "distance": 12.0})
	await _frames(2)
	player.inventory.take(&"tourniquet", 3)
	var on := "%s treats %s: tourniquet on %s at " % [player.log_name(), hurt.log_name(), Vitals.part_name(Vitals.THIGH_L)]
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, hurt.get_path(), &"tourniquet", Vitals.THIGH_L)  # 4 s: cut short
	await _seconds(0.3)
	var started := _lines_with(on)
	check(started.size() == 1 and ", started (" in started[0] and absf(_metres(started[0]) - 1.5) < 0.3,
		"a treatment starting says how far the casualty is (%s)" % [started])
	bearer.server_pick_up_body(hurt, Soldier.DRAG, INF)
	await _seconds(0.3)
	var dragged := _lines_with(on).filter(func(l: String) -> bool: return ", interrupted: " in l)
	check(dragged.size() == 1 and dragged[0].contains("interrupted: they were moved: dragged by %s (" % bearer.log_name()),
		"cut short by a drag: the line says who dragged them (%s)" % [dragged])
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, hurt.get_path(), &"tourniquet", Vitals.THIGH_L)  # while the bearer holds him
	await _seconds(0.3)
	bearer.release_carried()
	await _seconds(0.3)
	var put_down := _lines_with(on).filter(func(l: String) -> bool: return ", interrupted: " in l)
	check(put_down.size() == 2 and put_down[1].contains("interrupted: they were moved: put down by %s (" % bearer.log_name()),
		"cut short by the bearer putting him down: the line says who (%s)" % [put_down])
	hurt.global_position = player.global_position + Vector3(1.5, 0, 0)
	player._server_busy_until = 0.0
	player._server_treat.rpc_id(1, hurt.get_path(), &"tourniquet", Vitals.THIGH_L)
	await _seconds(0.3)
	var stood := player.global_position
	player.global_position = stood + Vector3(0, 0, 1.6)
	await _seconds(0.3)
	var moved := _lines_with(on).filter(func(l: String) -> bool: return ", interrupted: " in l)
	check(moved.size() == 3 and moved[2].contains("interrupted: you moved 1."), "cut short by the treater moving: how far he went (%s)" % [moved])
	player.global_position = stood
	hurt.queue_free()
	bearer.queue_free()


## Telling soldiers apart in the log (Captain, P0164 queue 9): two hostiles with one surname
## read apart by their callsigns; a body spawned as one has a tag of its own (and its spawning
## isn't logged as a second death); a target dummy reads as one, never "someone".
func _test_names(player: Soldier, level: CompoundLevel) -> void:
	print("Telling soldiers apart in the log")
	var a := _quiet_soldier(level, "HostileA", "hostile", player.global_position + Vector3(-6, 0, 8), "Hassan")
	var b := _quiet_soldier(level, "HostileB", "hostile", player.global_position + Vector3(-9, 0, 8), "Hassan")
	await _frames(5)
	check(a.display_name() == "Hassan" and b.display_name() == "Hassan" and a.log_name() == "Hassan [HostileA]" and b.log_name() == "Hassan [HostileB]",
		"two hostiles both named Hassan read apart in the log (%s, %s)" % [a.log_name(), b.log_name()])
	b.player_input.flash("probe hostile message")
	check(_has("Hassan [HostileB] (AI): probe hostile message"), "an AI's message is under its log name")
	Harm.note_hit(a, b)
	a.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.FULL_POWER, "distance": 3.0})
	await _frames(3)
	check(_lines_with("Hassan [HostileA] ").any(func(l: String) -> bool: return " (hostile): round (full_power), head, by Hassan [HostileB] (hostile) at 3 m" in l),
		"a casualty line names the casualty and who hit him by their log names (%s)" % [_lines_with("Hassan [")])
	var deaths := _log().count(" died (")
	var record := a.body_record()
	record.uid = GameState.new_uid()
	var corpse := level.server_spawn_body(record)
	await _frames(3)
	check(corpse != null and corpse.log_name().begins_with("Hassan [body ") and corpse.log_name() != a.log_name(),
		"a body spawned as one (a player's left behind, one from the save) has a tag of its own (%s)" % (corpse.log_name() if corpse else "none"))
	check(_log().count(" died (") == deaths, "and its spawning isn't logged as a second death (%s)" % [_lines_with(" died (")])
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.name = "ProbeDummy"
	dummy.position = player.global_position + Vector3(0, 0, -1.5)
	level.add_child(dummy)
	await _frames(3)
	check(SessionLog.who(dummy) == "target dummy ProbeDummy" and SessionLog.who(null) == "nobody", "a target dummy is named as one (%s)" % SessionLog.who(dummy))
	var bone := dummy.vitals._model._add_fracture(Vitals.SHIN_L, &"tibia_l")
	dummy.vitals._model._open_break(bone, "probe")
	dummy.vitals._log_open_breaks()
	check(_has("target dummy ProbeDummy: open fracture") and not _has("someone: "), "its lines name it, never \"someone\" (%s)" % [_lines_with("ProbeDummy")])
	player._server_busy_until = 0.0
	await player._treat(dummy, &"morphine", Vitals.TORSO, false)  # none carried: refused
	check(_has("%s treats target dummy ProbeDummy: morphine on " % player.log_name()), "and so does a treatment of it (%s)" % [_lines_with("treats target dummy")])
	for n: Node in [a, b, corpse, dummy]:
		if is_instance_valid(n):
			n.queue_free()


func _test_bug_report(player: Soldier, level: CompoundLevel, faller: Soldier) -> void:
	print("The bug-report key and the AI overlay")
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	var n := BugReport.save("probe: the door sticks", player)
	var report := SessionLog.folder.path_join("report-1.txt")
	check(n == 1 and FileAccess.file_exists(report), "report-1.txt is saved in the session folder")
	var text := FileAccess.get_file_as_string(report)
	check("Note: probe: the door sticks" in text and "Time: " in text and "Zone: " in text, "it has the note, the time and the zone")
	check("Soldiers (" in text and "Why: bug report: probe: the door sticks" in text and ("%s (friendly" % faller.log_name()) in text, "and the soldiers list")
	check("  inventory:" in text and "  wounds (" in text and "forearm" in text.to_lower(), "and the player's inventory and wounds")
	check("bug report 1: probe: the door sticks" in _log(), "the log says so")
	check(BugReport.save("second", player) == 2 and FileAccess.file_exists(SessionLog.folder.path_join("report-2.txt")), "the next report is report-2")
	var scout := level.spawn_soldier({"name": "Scout", "faction": "friendly", "variant": "multicam", "pos": player.global_position + Vector3(0, 0.1, 8),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(5)
	var overlay := AiOverlay.new()
	add_child(overlay)
	check(overlay.labels.is_empty(), "the overlay shows nothing until it is switched on")
	overlay.set_shown(true)
	overlay.refresh()
	var label: Label3D = overlay.labels.get(scout)
	check(label != null and SquadAI.Intent.keys()[SquadAI.of(scout).intent] in label.text and "suppr" in label.text and "aware" in label.text,
		"it has a label with the intent and what it's spotting over a nearby AI (%s)" % [label.text.replace("\n", " | ") if label else "none"])
	check(not overlay.labels.has(faller), "and none over one far away")
	overlay.set_shown(false)
	check(overlay.labels.is_empty(), "switched off, the labels go")
	# Performance lines (every SessionLog.PERF_S): frame times, AI, what's streamed in.
	await _frames(10)
	var perf := SessionLog.perf_line()
	check(perf.begins_with("perf: frame ") and " ms avg" in perf and " AI, " in perf and "nav rebakes" in perf and "memory" in perf,
		"a performance line: %s" % perf)
	check("; worst frame: " in perf and " draws, " in perf, "it says what the worst frame went on")
	var spent := SessionLog.costs_text({&"nav": 3100, &"ai": 212400, &"sfx": 40}, {"physics": 215.0, "process": 4.2, "draws": 812, "primitives": 1200000})
	check(spent == "ai 212.4 ms, nav 3.1 ms; engine physics 215.0 ms, process 4.2 ms, 812 draws, 1.20M primitives",
		"costliest system first, under 0.1 ms left out: %s" % spent)
	var t := Time.get_ticks_usec()
	OS.delay_msec(2)
	FrameCost.spent(&"probe", t)
	check(int(FrameCost.take().get(&"probe", 0)) >= 2000 and FrameCost.take().is_empty(), "FrameCost counts a system's time while a session is open, and starts afresh")
	# Memory a release build can read too (Captain P0362: release builds logged "memory 0 MB";
	# the engine's static count is debug-only), with no child process (no console window).
	var debug_mem := SessionLog.memory_text()
	var release_mem := SessionLog.memory_text(0.0)  # as a release build reads the engine's count
	var rss := SessionLog.process_memory_mb()
	check(debug_mem.begins_with("memory ") and not "memory 0 MB" in release_mem and " video " in " " + release_mem
		and "system memory " in release_mem and not "memory -" in release_mem and " objects, " in release_mem and (rss > 10.0 or OS.get_name() not in ["Linux", "Android", "FreeBSD"])
		and (release_mem.begins_with("memory ") == (rss > 0.0)),
		"memory in the perf line, release-safe: %s | as release: %s (process %.0f MB)" % [debug_mem, release_mem, rss])
	overlay.queue_free()
	scout.queue_free()


## What a group night needs in the log (S3, P0331 triage; the deployment's own lines are
## checked in the base suite's contract loop): where the logs are, on the pause menu;
## extraction opening and being called; the debrief's line; a player's death and respawn.
func _test_group_night(player: Soldier, level: CompoundLevel) -> void:
	print("A group night in the log")
	var path := player.player_input.pause_menu.find_child("SessionLogFolder", true, false) as LineEdit
	check(path != null and path.text == SessionLog.logs_folder() and SessionLog.folder.get_base_dir() == path.text
		and DirAccess.dir_exists_absolute(path.text), "the pause menu shows where the session logs are (%s)" % (path.text if path else "no path"))
	var extraction := MapNodes.extraction(level)
	if extraction:
		var at := player.global_position
		extraction.server_begin({"contract": {"id": "c_probe"}, "zone": {"extraction_points": [{"name": "LZ Probe", "pos": [at.x, at.z]}]}})
		var why := extraction.server_confirm()
		check(_has("extraction open: contract c_probe, 1 preset points") and (why != "" or _has("extraction called at LZ Probe")),
			"extraction opening and being called are logged (%s)" % ("called" if why == "" else why))
		extraction.server_cancel()
	else:
		check(false, "the level has an extraction")
	var line := Contracts.debrief_log_line({"zone_name": "Probe Yard", "contracts": [{"title": "Hold Fast", "outcome": "completed", "pay": 1200,
		"clawback": 300}], "fines": 50, "civilians": 1, "days": 2}, {"extracted": ["Player 1", "Gunny"], "casualties": [{"name": "Reaper", "status": "kia"}]})
	check(line == "debrief: Probe Yard: Hold Fast completed, paid $1200, $300 advance clawed back; fines $50 (1 civilians); 2 days; out: Player 1, Gunny; casualties: Reaper kia",
		"the debrief's line: pay, clawback, fines and losses (%s)" % line)
	# The respawn waits (gameplay/respawn): the death and the wait are logged at once, the
	# respawn line when it really happens, with the point it uses.
	Soldier.respawn_delay_s = 0.5
	player.vitals.server_kill()
	await _frames(5)
	check(_has("%s died (friendly)" % player.log_name()) and _has("%s waits 0.5 s to respawn" % player.log_name()) and not _has("%s respawns at (" % player.log_name()),
		"a player's death and the wait to respawn are logged, not the respawn yet (%s)" % [_lines_with("respawn")])
	await get_tree().create_timer(1.0).timeout
	Soldier.respawn_delay_s = 0.0
	check(_has("%s respawns at (" % player.log_name()),
		"and the respawn when it happens (%s)" % [_lines_with("respawns at")])


## A session whose folder can't be renamed at its end (P0331, P0362: something held a file in
## it open, and it stayed RUNNING with no word why): the rename is retried, the failure is in
## session.log and index.txt, and the next session renames it.
func _test_stuck_folder() -> void:
	print("A folder that can't be renamed at the end")
	SessionLog.start(parent)
	var id := SessionLog.session_id
	var running := SessionLog.folder
	check(SessionLog.errors + SessionLog.warnings + SessionLog.anomalies == 0, "a new session counts its own issues (none yet)")
	var blocker := running.replace("-RUNNING-", "-PASS-")  # the name it wants, taken: the rename fails anywhere
	DirAccess.make_dir_recursive_absolute(blocker)
	var f := FileAccess.open(blocker.path_join("in_the_way.txt"), FileAccess.WRITE)
	f.store_line("probe")
	f.close()
	SessionLog.finish()
	var text := FileAccess.get_file_as_string(running.path_join("session.log"))
	check(SessionLog.folder == running and DirAccess.dir_exists_absolute(running) and "!! could not rename the folder to " in text,
		"the rename fails: the folder stays RUNNING and session.log says why")
	check(_index().contains("%s " % id) and _index().contains("folder left RUNNING: rename failed"), "and so does index.txt")
	DirAccess.remove_absolute(blocker.path_join("in_the_way.txt"))
	DirAccess.remove_absolute(blocker)
	SessionLog.start(parent)
	check(not DirAccess.dir_exists_absolute(running) and DirAccess.dir_exists_absolute(blocker) and _has("%s's folder was left RUNNING after it ended PASS: renamed to " % id),
		"the next session renames it and says so")
	SessionLog.finish()


func _probe_error() -> void:
	push_error("probe error")


func _log() -> String:
	return FileAccess.get_file_as_string(SessionLog.folder.path_join("session.log"))


## The session.log lines with `text` in them, but for this test's own checks (printed, so logged too).
func _lines_with(text: String) -> Array:
	return Array(_log().split("\n")).filter(func(l: String) -> bool: return text in l and not "  [ok] " in l and not "  [FAIL] " in l)


func _has(text: String) -> bool:
	return not _lines_with(text).is_empty()


## The distance in a treatment line ("... at 1.5 m, ..."), or -1.
func _metres(line: String) -> float:
	var m := RegEx.create_from_string(" at ([0-9.]+) m,").search(line)
	return m.get_string(1).to_float() if m else -1.0


## An AI soldier for these checks, its brain off so it stays put; `surname` sets its name.
func _quiet_soldier(level: CompoundLevel, callsign: String, faction: String, pos: Vector3, surname := "") -> Soldier:
	var data := {"name": callsign, "faction": faction, "variant": "multicam", "pos": pos, "loadout": ["m4a1"],
		"combat": 0.5, "discipline": 0.5, "guard": true}
	if surname != "":
		data["person_name"] = surname
	var s := level.spawn_soldier(data)
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _index() -> String:
	return FileAccess.get_file_as_string(parent.path_join("index.txt"))


## The session's dump-*.txt files whose name has `what` in it.
func _dumps(what: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(SessionLog.folder):
		if f.begins_with("dump-") and f.ends_with(".txt") and what in f:
			out.append(f)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Removes this test's scratch folder (under user://, made by this test).
static func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
