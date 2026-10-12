extends Node
## Headless checks for the session log (SessionLog, autoload/session_log.gd): off in a headless
## run; a session opened in a scratch parent takes the next number from its run_counter.txt;
## prints, warnings, errors and messages shown to the player land in session.log; each kind of
## issue writes one dump with the state of the game; a soldier fallen out of the world is an
## anomaly with its own dump; a session ends PASS when nothing unexpected happened, else FAIL,
## with a line in index.txt.
##   <voxel godot exe> --headless --path . res://tests/session_log_test.tscn
## Exits with the number of failures.

var failures := 0
var parent := ""


func _ready() -> void:
	GameState.zone_id = "test_session_log" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
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
	GameState.delete_save()
	print("SESSION_LOG TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


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
	faller.global_position = Vector3(5, -300, 30)
	await _seconds(SessionLog.CHECK_S * 2.5)
	check(("!! ANOMALY: %s fell out of the world" % faller.display_name()) in _log() and SessionLog.anomalies >= 1, "a soldier out of the world is an anomaly")
	var anomaly := _dumps("anomaly")
	check(anomaly.size() == 1, "with its own dump")
	if anomaly.size() == 1:
		var state := FileAccess.get_file_as_string(SessionLog.folder.path_join(anomaly[0]))
		var line := Array(state.split("\n")).filter(func(l: String) -> bool: return ("%s (friendly" % faller.display_name()) in l)
		check(line.size() == 1 and "at (5.0, -" in line[0] and SquadAI.Intent.keys().any(func(k: String) -> bool: return (k + ":") in line[0]),
			"the dump has the soldier: where, and the AI's intent (%s)" % [line])
		check("Player 1 (friendly" in state or "player 1" in state, "and the player")
	SessionLog.finish()
	check("-FAIL-" in SessionLog.folder.get_file() and DirAccess.dir_exists_absolute(SessionLog.folder), "something unexpected: the folder ends FAIL")
	check(_index().contains("P0043 ") and _index().contains(" FAIL "), "and index.txt says so")
	faller.queue_free()


func _probe_error() -> void:
	push_error("probe error")


func _log() -> String:
	return FileAccess.get_file_as_string(SessionLog.folder.path_join("session.log"))


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
