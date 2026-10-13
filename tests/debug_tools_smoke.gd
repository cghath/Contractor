extends Node
## Smoke test of the debug tools in a real window (docs/debugging.md; not a CI suite: it renders):
##   CONTRACTOR_SESSION_LOG=1 CONTRACTOR_PORT=25270 <voxel godot exe> --path . res://tests/debug_tools_smoke.tscn
## A session log opens (P<number>, RUNNING) with dev tools on; the bug-report key (Insert) saves
## report-<n>.txt with the note and every soldier, and its screenshot; the AI overlay key
## (Delete) labels the squad; an anomaly writes a state dump; ending the session renames its
## folder and adds a line to index.txt. Prints [ok]/[FAIL] lines and DEBUG TOOLS SMOKE PASSED or
## FAILED, and quits with the failure count.

var failures := 0


func check(condition: bool, what: String) -> void:
	if condition:
		print("  [ok] ", what)
	else:
		failures += 1
		print("  [FAIL] ", what)


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("DEBUG TOOLS SMOKE FAILED (timed out)")
		get_tree().quit(99))
	print("Debug tools smoke")
	check(SessionLog.session_id.begins_with("P") and SessionLog.folder.contains("-RUNNING-"),
		"a session log is open: %s (%s)" % [SessionLog.session_id, SessionLog.folder.get_file()])
	check(DevTools.on(), "dev tools are on (editor build)")
	CompoundLevel.spawn_ai = true
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main.get_node(^"Menu").host()
	var level := CompoundLevel.current(self)
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self)
	var player: Soldier = level.players.get_node(^"1")
	for i in 120:  # the squad spawns and gathers round the player
		await get_tree().process_frame
	var input: Node = player.player_input
	# Bug report: Insert opens the note panel, Enter saves report-<n>.txt and .png.
	var before := _reports()
	_key(KEY_INSERT)
	await get_tree().process_frame
	var report: BugReport = input.bug_report
	check(report != null and report.is_open(), "Insert opens the bug report panel")
	if report and report.is_open():
		report._edit.text = "smoke test: the bug report key"
		report._edit.text_submitted.emit(report._edit.text)
	await get_tree().process_frame
	var after := _reports()
	var n := before.size() + 1
	var text := FileAccess.get_file_as_string(SessionLog.folder.path_join("report-%d.txt" % n))
	check(after.size() == before.size() + 1 and FileAccess.file_exists(SessionLog.folder.path_join("report-%d.png" % n)),
		"Enter saves report-%d.txt and its screenshot in the session folder" % n)
	check(text.contains("Note: smoke test: the bug report key") and text.contains("Player 1") and text.count("\n") > 10,
		"the report has the note and the state: every soldier (%d lines)" % text.count("\n"))
	# AI overlay: Delete labels the AI within 80 m.
	var overlay: AiOverlay = player.get_node_or_null(^"AiOverlay")
	_key(KEY_DELETE)
	for i in 30:
		await get_tree().process_frame
	check(overlay != null and overlay.shown and overlay.labels.size() > 0,
		"Delete shows the AI overlay: %d squadmates labelled" % (overlay.labels.size() if overlay else 0))
	if overlay and not overlay.labels.is_empty():
		var label: Label3D = overlay.labels.values()[0]
		check(label.text.length() > 10, "with intent, status and mode (\"%s\")" % label.text.replace("\n", " | "))
	_key(KEY_DELETE)
	await get_tree().process_frame
	check(overlay != null and not overlay.shown and overlay.labels.is_empty(), "and Delete hides it again")
	# An anomaly writes a state dump.
	SessionLog.anomaly("debug_tools_smoke", "smoke test anomaly (expected)")
	for i in 10:
		await get_tree().process_frame
	var dumps := DirAccess.get_files_at(SessionLog.folder) as Array
	check(dumps.any(func(f: String) -> bool: return f.begins_with("dump-") and f.ends_with("-anomaly.txt")),
		"an anomaly writes a state dump (%s)" % [dumps.filter(func(f: String) -> bool: return f.begins_with("dump-"))])
	var log := FileAccess.get_file_as_string(SessionLog.folder.path_join("session.log"))
	check(log.contains("bug report %d: smoke test" % n) and log.contains("!! ANOMALY: smoke test anomaly"),
		"session.log has the bug report and the anomaly")
	# Ending the session: the folder is renamed (FAIL: the anomaly) and index.txt gets a line.
	var id := SessionLog.session_id
	var parent: String = SessionLog._parent
	SessionLog.finish()
	var index := FileAccess.get_file_as_string(parent.path_join("index.txt"))
	var last := Array(index.strip_edges().split("\n")).back() as String
	check(SessionLog.folder.contains("%s-" % id) and SessionLog.folder.contains("-FAIL-") and DirAccess.dir_exists_absolute(SessionLog.folder),
		"the session ends: its folder is renamed %s" % SessionLog.folder.get_file())
	check(last.begins_with(id) and last.contains("FAIL"), "and index.txt has its line (%s)" % last)
	print("DEBUG TOOLS SMOKE %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _reports() -> Array:
	if SessionLog.folder == "" or not DirAccess.dir_exists_absolute(SessionLog.folder):
		return []
	return Array(DirAccess.get_files_at(SessionLog.folder)).filter(func(f: String) -> bool: return f.begins_with("report-") and f.ends_with(".txt"))
