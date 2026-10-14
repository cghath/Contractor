extends Node
## Session logs (Captain, 2026-10-12: "when anything unexpected happens while I'm playtesting,
## it's logged in a file"). Every run that isn't headless (a playtest: the editor or a test
## build) opens a numbered session, P<number>, in the same parent folder and counter as the test
## runs (docs/debugging.md):
##   <parent>/<date>/P0047-<HHMMSS>-RUNNING-<build>-<sha>/session.log
## session.log gets every engine and script error and warning (with its script backtrace),
## everything the game prints, slow frames, hosting/joining/disconnects, zone changes and every
## message the player was shown. Anything unexpected (an error, a warning, a soldier somewhere
## impossible) also writes dump-<n>-<what>.txt (every soldier: where, condition, the AI's intent,
## target and mode; the hot zone's state; the last log lines) and a screenshot, once per kind of
## issue. On quit the folder becomes PASS (nothing unexpected) or FAIL; a session that crashed
## keeps RUNNING. The pause menu shows the session number.
##
## Off when headless (test suites) or running a -s script; CONTRACTOR_SESSION_LOG=0 turns it
## off, =1 on. CONTRACTOR_TEST_LOGS picks the parent (as for the test runner); otherwise the
## first Contractor-test-logs folder found going up from the game (B:\Contractor-test-logs for
## builds under B:\Contractor\builds), else user://session-logs.

const ENV := "CONTRACTOR_SESSION_LOG"
const PARENT_NAME := "Contractor-test-logs"
## A frame this long (seconds) is logged as slow.
const SLOW_FRAME_S := 0.5
## How often soldiers are checked for impossible positions, and the zone for a change (seconds).
const CHECK_S := 1.0
## A performance line this often (s): frame times, AI count, modules streamed in, nav rebakes.
const PERF_S := 60.0
## The process's memory is read this long before each performance line, off the main thread
## (process_memory_mb).
const MEMORY_LEAD_S := 5.0
## Below this a soldier has fallen out of the world.
const FELL_Y := -100.0
## Log lines kept for the dumps.
const TAIL_LINES := 200
## At most this many dumps (and screenshots) per session.
const MAX_DUMPS := 20
const ERROR_NAMES := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

## "P0047" while a session is open, else "".
var session_id := ""
## The session's folder (absolute; renamed PASS or FAIL when it ends).
var folder := ""
var errors := 0
var warnings := 0
var anomalies := 0
var dumps := 0

var _parent := ""
var _file: FileAccess
var _catcher: _Catcher
var _mutex := Mutex.new()
var _in_write := false
var _tail: Array[String] = []
var _pending: Array[Dictionary] = []  # issues caught off the main thread, dumped in _process
var _dumped := {}  # issue key -> true: one dump per kind
var _flagged := {}  # soldier anomaly key -> true
var _started_usec := 0
var _last_frame_usec := 0
var _check_left := CHECK_S
var _zone := ""
var _net_watched := false
## Performance lines (docs/debugging.md, planned item 4): every PERF_S, the frames since the last
## line, the AI, what's streamed in and the navigation rebakes.
var _perf_left := PERF_S
var _perf_frames := 0
var _perf_sum := 0.0
var _perf_worst := 0.0
var _rebakes := 0
var _nav_watched: Node
## The process's resident memory (MB) last read (-1: not known), the read running (-1: none),
## and whether it's been read for the coming line.
var _rss_mb := -1.0
var _rss_task := -1
var _rss_read := false


## Catches what the engine logs, on whatever thread logs it.
class _Catcher extends Logger:
	var log_node: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var trace := ""
		for bt in script_backtraces:
			trace += bt.format(3, 6)
		log_node.caught_error(error_type, code, rationale, function, file, line, trace)

	func _log_message(message: String, error: bool) -> void:
		log_node.caught_message(message, error)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _wanted():
		start(_find_parent())


## Whether this run should keep a session log: a playtest, not a test suite or a script.
static func _wanted() -> bool:
	var env := OS.get_environment(ENV)
	if env == "0":
		return false
	if env == "1":
		return true
	if DisplayServer.get_name() == "headless" or OS.get_environment("CONTRACTOR_TEST_LOGS") == "none":
		return false
	var args := OS.get_cmdline_args()
	return not ("-s" in args or "--script" in args)


## Opens a session under `parent` (made if missing). The tests call this with their own folder.
func start(parent: String) -> void:
	if session_id != "":
		return
	_parent = parent
	DirAccess.make_dir_recursive_absolute(parent)
	var number := _next_number(parent)
	session_id = "P%04d" % number
	var build := _build_name()
	var now := Time.get_datetime_dict_from_system()
	var day := "%04d-%02d-%02d" % [now.year, now.month, now.day]
	var time := "%02d%02d%02d" % [now.hour, now.minute, now.second]
	folder = parent.path_join(day).path_join("%s-%s-RUNNING-%s" % [session_id, time, build])
	DirAccess.make_dir_recursive_absolute(folder)
	_file = FileAccess.open(folder.path_join("session.log"), FileAccess.WRITE)
	if _file == null:
		session_id = ""
		return
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	_catcher = _Catcher.new()
	_catcher.log_node = self
	OS.add_logger(_catcher)
	_write("session %s started %s %s" % [session_id, day, time])
	_write("build %s, Contractor %s, %s, %s" % [build, ProjectSettings.get_setting("application/config/version", "?"),
		Engine.get_version_info().string, OS.get_name()])
	_write("args %s %s; dev tools %s" % [OS.get_cmdline_args(), OS.get_cmdline_user_args(), "on" if DevTools.on() else "off"])
	_write("logging to %s" % folder)
	_watch_net.call_deferred()  # this autoload loads first (to catch the others' errors); Net comes later


func _watch_net() -> void:
	if _net_watched:
		return
	_net_watched = true
	for sig: String in ["hosted", "joined", "join_failed", "session_ended"]:
		Net.connect(sig, note.bind("net: %s" % sig.replace("_", " ")))
	Net.peer_joined.connect(func(id: int) -> void: note("net: peer %d joined" % id))
	Net.peer_left.connect(func(id: int) -> void: note("net: peer %d left" % id))


## Closes the session: PASS if nothing unexpected happened, else FAIL, and a line in index.txt.
func finish() -> void:
	if session_id == "":
		return
	if _rss_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_rss_task)
		_rss_task = -1
	var verdict := "PASS" if errors + warnings + anomalies == 0 else "FAIL"
	_write("session %s ended after %s: %s (%d errors, %d warnings, %d anomalies, %d dumps)" % [session_id,
		_clock(), verdict, errors, warnings, anomalies, dumps])
	OS.remove_logger(_catcher)
	_mutex.lock()
	_file.close()
	_file = null
	_mutex.unlock()
	var done := folder.replace("-RUNNING-", "-%s-" % verdict)
	if DirAccess.rename_absolute(folder, done) == OK:
		folder = done
	var index := FileAccess.open(_parent.path_join("index.txt"), FileAccess.READ_WRITE)
	if index == null:
		index = FileAccess.open(_parent.path_join("index.txt"), FileAccess.WRITE)
	if index:
		index.seek_end()
		var name_parts := folder.get_file().split("-")
		index.store_line("%s %s %s %s %s playtest session: %d errors, %d warnings, %d anomalies" % [session_id,
			folder.get_base_dir().get_file(), name_parts[1], verdict, "-".join(name_parts.slice(3)), errors, warnings, anomalies])
		index.close()
	session_id = ""


## A line in the session log (any thread). Does nothing without a session.
func note(text: String) -> void:
	if session_id != "":
		_write(text)


## How the log names `body` (Captain, P0164 queue 9): its log_name() (a Soldier: "Rahimi
## [Hostile3]", so same-named hostiles read apart; a TargetDummy: "target dummy LightDummy"),
## else its node's name, or "nobody" (null or freed: a Variant, so a freed body can be passed).
static func who(body: Variant) -> String:
	if not is_instance_valid(body):
		return "nobody"
	return body.log_name() if body.has_method(&"log_name") else String(body.name)


## Something unexpected the game itself noticed: logged, counted, and dumped once per `key`.
func anomaly(key: String, text: String) -> void:
	if session_id == "":
		return
	anomalies += 1
	_write("!! ANOMALY: " + text)
	_queue_dump(key, "anomaly", text)


func caught_error(error_type: int, code: String, rationale: String, function: String, file: String, line: int, trace: String) -> void:
	if session_id == "" or _in_write:
		return
	var kind: String = ERROR_NAMES[error_type] if error_type < ERROR_NAMES.size() else "ERROR"
	if kind == "WARNING":
		warnings += 1
	else:
		errors += 1
	var what := code if rationale == "" else "%s (%s)" % [code, rationale]
	_write("!! %s: %s\n   at: %s (%s:%d)%s" % [kind, what, function, file, line, ("\n" + trace.trim_suffix("\n")) if trace != "" else ""])
	_queue_dump("%s %s:%d" % [kind, file, line], kind.to_lower().replace(" ", "-"), what)


func caught_message(message: String, error: bool) -> void:
	if session_id == "" or _in_write:
		return
	_write(("stderr: " if error else "") + message.trim_suffix("\n"))


func _process(delta: float) -> void:
	if session_id == "":
		return
	var now := Time.get_ticks_usec()
	var frame_s := (now - _last_frame_usec) / 1000000.0
	_last_frame_usec = now
	if frame_s >= SLOW_FRAME_S:
		_write("slow frame: %.2f s" % frame_s)
	_perf_frames += 1
	_perf_sum += frame_s
	_perf_worst = maxf(_perf_worst, frame_s)
	_perf_left -= delta
	if _rss_task >= 0 and WorkerThreadPool.is_task_completed(_rss_task):
		WorkerThreadPool.wait_for_task_completion(_rss_task)
		_rss_task = -1
		_rss_read = true
	if _perf_left <= MEMORY_LEAD_S and _rss_task < 0 and not _rss_read:
		_rss_task = WorkerThreadPool.add_task(_read_rss, false, "SessionLog memory")
	if _perf_left <= 0.0:
		_perf_left = PERF_S
		_write(perf_line())
		_rss_read = false
	_mutex.lock()
	var pending := _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	for p: Dictionary in pending:
		_dump(p.what, p.text)
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_S
		_check()


## Once a second: a zone change, and soldiers somewhere impossible.
func _check() -> void:
	if GameState.zone_id != _zone:
		_zone = GameState.zone_id
		note("zone: %s" % _zone)
	var level := CompoundLevel.current(get_tree().root)
	var nav: Node = level.get_node_or_null(^"Navigation") if level else null
	if nav != _nav_watched:
		_nav_watched = nav
		if nav and nav.has_signal(&"rebaked"):
			nav.rebaked.connect(func(_chunk: Vector2i) -> void: _rebakes += 1)
	for s in _soldiers():
		var pos: Vector3 = s.global_position
		if not pos.is_finite():
			_flag(s, "nan", "%s's position is not a number (%s)" % [s.log_name(), pos])
		elif pos.y < FELL_Y:
			_flag(s, "fell", "%s fell out of the world (y %.0f m at %.0f, %.0f)" % [s.log_name(), pos.y, pos.x, pos.z])


func _flag(s: Soldier, kind: String, text: String) -> void:
	var key := "%s %s" % [kind, s.get_instance_id()]
	if not _flagged.has(key):
		_flagged[key] = true
		anomaly("%s %s" % [kind, s.log_name()], text)


func _soldiers() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for group in [&"combatants", Soldier.DEAD_GROUP]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Soldier and not out.has(n) and n.is_inside_tree():
				out.append(n)
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_CRASH and session_id != "":
		_write("!! CRASH: the engine is crashing (the folder stays RUNNING)")
	elif what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		finish()


# --- Writing and dumps ------------------------------------------------------------------------

func _write(text: String) -> void:
	_mutex.lock()
	if _file and not _in_write:
		_in_write = true
		var line := "[%s] %s" % [_clock(), text]
		_file.store_line(line)
		_file.flush()
		_tail.append(line)
		if _tail.size() > TAIL_LINES:
			_tail.pop_front()
		_in_write = false
	_mutex.unlock()


func _queue_dump(key: String, what: String, text: String) -> void:
	_mutex.lock()
	if not _dumped.has(key) and dumps + _pending.size() < MAX_DUMPS:
		_dumped[key] = true
		_pending.append({"what": what, "text": text})
	_mutex.unlock()


## Writes dump-<n>-<what>.txt (state_text) and, with a screen, dump-<n>-<what>.png.
func _dump(what: String, text: String) -> void:
	dumps += 1
	var base := folder.path_join("dump-%02d-%s" % [dumps, what])
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if f:
		f.store_string(state_text(text))
		f.close()
	if DisplayServer.get_name() != "headless":
		var texture := get_viewport().get_texture()
		var image := texture.get_image() if texture else null
		if image:
			image.save_png(base + ".png")
	note("dump %d written: %s" % [dumps, (base + ".txt").get_file()])


## The performance line for the frames since the last one (and starts counting afresh):
## "perf: frame 12.3 ms avg, 40.2 ms worst (81 fps); 14 AI, 1 player; modules 3/12 streamed;
## nav rebakes 2; memory 512 MB".
func perf_line() -> String:
	var avg := _perf_sum / maxi(_perf_frames, 1)
	var ai := 0
	var players := 0
	for s in _soldiers():
		if s.vitals.is_up():
			if s.is_ai():
				ai += 1
			else:
				players += 1
	var level := CompoundLevel.current(get_tree().root)
	var modules := "no modules"
	if level and level.has_method(&"streamed_modules") and level.has_method(&"modules"):
		modules = "modules %d/%d streamed" % [level.call(&"streamed_modules").size(), level.call(&"modules").size()]
	var text := "perf: frame %.1f ms avg, %.1f ms worst (%.0f fps); %d AI, %d player%s; %s; nav rebakes %d; %s" % [
		avg * 1000.0, _perf_worst * 1000.0, 1.0 / maxf(avg, 0.0001), ai, players, "" if players == 1 else "s", modules, _rebakes,
		memory_text()]
	_perf_frames = 0
	_perf_sum = 0.0
	_perf_worst = 0.0
	_rebakes = 0
	return text


## "memory 812 MB, video 240 MB": the process's resident memory (process_memory_mb, read off
## the main thread before each line; the engine's own count where that isn't known), and the
## video memory in use. Captain P0362: the engine's static count (Performance.MEMORY_STATIC,
## OS.get_static_memory_usage) is only kept in debug builds, so a release build read 0 MB.
func memory_text() -> String:
	var mb := _rss_mb
	if mb <= 0.0:
		mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	return "memory %s MB, video %.0f MB" % ["%.0f" % mb if mb > 0.0 else "?", video]


func _read_rss() -> void:
	_rss_mb = process_memory_mb()


## The process's resident memory (MB), or -1 if it can't be read: Linux from /proc/self/status,
## Windows from tasklist, macOS from ps. Blocks for a moment on Windows and macOS (a process
## runs): call it off the main thread.
static func process_memory_mb() -> float:
	var pid := OS.get_process_id()
	match OS.get_name():
		"Linux", "FreeBSD", "Android":
			for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
				if line.begins_with("VmRSS:"):
					return _digits(line) / 1024.0
		"Windows":
			var out: Array = []
			if OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], out) == 0 and not out.is_empty():
				var fields := String(out[0]).strip_edges().split("\",\"")
				if fields.size() >= 5:
					return _digits(fields[fields.size() - 1]) / 1024.0  # "1,234,567 K"
		"macOS":
			var out: Array = []
			if OS.execute("ps", ["-o", "rss=", "-p", str(pid)], out) == 0 and not out.is_empty():
				return _digits(String(out[0])) / 1024.0
	return -1.0


## The digits in `text` as a number (thousands separators of any locale dropped), or -1.
static func _digits(text: String) -> float:
	var d := ""
	for c in text:
		if c >= "0" and c <= "9":
			d += c
	return float(d.to_int()) if d != "" else -1.0


## What's going on now, for a dump (and the bug-report key, planned): the session, the zone, the
## network, every soldier, the hot zone's state, and the last log lines.
func state_text(reason: String) -> String:
	var lines: Array[String] = []
	lines.append("Why: %s" % reason)
	lines.append("Session %s, %s in; %d errors, %d warnings, %d anomalies; %d fps" % [session_id, _clock(), errors, warnings,
		anomalies, Engine.get_frames_per_second()])
	var scene := get_tree().current_scene
	lines.append("Zone %s; scene %s" % [GameState.zone_id, scene.scene_file_path if scene else "none"])
	var peer := multiplayer.multiplayer_peer
	var online := peer != null and not peer is OfflineMultiplayerPeer
	lines.append("Net: %s" % ("offline" if not online else "%s, peer %d, peers %s" % ["host" if multiplayer.is_server() else "client",
		multiplayer.get_unique_id(), multiplayer.get_peers()]))
	var soldiers := _soldiers()
	lines.append("")
	lines.append("Soldiers (%d):" % soldiers.size())
	for s in soldiers:
		lines.append("  " + _soldier_line(s))
	var mine := player_text()
	if mine != "":
		lines.append("")
		lines.append(mine)
	var readout := HotZoneDebug.readout(self)
	if readout != "":
		lines.append("")
		lines.append(readout)
	var helicopters := HeliSupports.readout(self)  # wave 5b: each helicopter support's state
	if helicopters != "":
		lines.append("")
		lines.append(helicopters)
	var vehicles := AavSupport.state_text(self)  # wave 5b: every vehicle, the AAV support
	if vehicles != "":
		lines.append("")
		lines.append(vehicles)
	lines.append("")
	lines.append("Last %d log lines:" % _tail.size())
	_mutex.lock()
	lines.append_array(_tail)
	_mutex.unlock()
	return "\n".join(lines) + "\n"


## The local (human) player's condition, signs, wounds (per part) and inventory, or "".
func player_text() -> String:
	var me: Soldier
	for s in _soldiers():
		if not s.is_ai() and s.is_local():
			me = s
	if me == null:
		return ""
	var lines: Array[String] = ["%s: %s" % [me.log_name(), me.vitals.condition_text()]]
	var signs := me.vitals.signs(true)
	lines.append("  signs: %s" % (", ".join(signs) if not signs.is_empty() else "none"))
	var wounds := me.vitals.wound_list()
	lines.append("  wounds (%d):" % wounds.size())
	for w: Dictionary in wounds:
		var flags: Array[String] = []
		for k: String in ["bleeding", "treated", "tourniquet", "packed", "tension", "clamped", "closed"]:
			if w.get(k, false):
				flags.append(k)
		lines.append("    %s: %s %s%s" % [w.part, w.kind, w.name, (" (%s)" % ", ".join(flags)) if not flags.is_empty() else ""])
	lines.append("  inventory:")
	var inv := me.inventory
	for slot: StringName in inv.slots:
		if inv.slots[slot] != &"":
			lines.append("    %s: %s" % [slot, inv.slots[slot]])
	for container: StringName in inv.containers:
		var items: Array[String] = []
		for e: Dictionary in inv.containers[container]:
			items.append("%s x%d" % [e.id, e.get("count", 1)])
		if not items.is_empty():
			lines.append("    %s: %s" % [container, ", ".join(items)])
	if inv.hands != &"":
		lines.append("    hands: %s" % inv.hands)
	return "\n".join(lines)


func _soldier_line(s: Soldier) -> String:
	var p := s.global_position
	var driver := "AI" if s.is_ai() else "player %d" % s.owner_peer()
	var parts: Array[String] = ["%s (%s %s, %s)" % [s.log_name(), s.faction, String(s.role) if s.role != &"" else "-", driver],
		"at (%.1f, %.1f, %.1f)" % [p.x, p.y, p.z], s.vitals.condition_text()]
	var ai := SquadAI.of(s)
	if ai:
		parts.append("%s: %s" % [SquadAI.Intent.keys()[ai.intent], ai.status_text()])
		parts.append("target %s" % (who(ai.target) if is_instance_valid(ai.target) else "none"))
		parts.append("mode %s" % Squad.CombatMode.keys()[ai.combat_mode])
	if is_instance_valid(s.carrying):
		parts.append("carrying %s" % s.carrying.log_name())
	if is_instance_valid(s.carried_by):
		parts.append("carried by %s" % s.carried_by.log_name())
	if s.inventory.hands != &"":
		parts.append("hands %s" % s.inventory.hands)
	return " | ".join(parts)


func _clock() -> String:
	var s := int((Time.get_ticks_usec() - _started_usec) / 1000000)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


# --- Where and what number --------------------------------------------------------------------

## CONTRACTOR_TEST_LOGS, else the first Contractor-test-logs going up from the game, else
## user://session-logs.
static func _find_parent() -> String:
	var env := OS.get_environment("CONTRACTOR_TEST_LOGS")
	if env != "" and env != "none":
		return env
	var dir := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	while dir != "":
		var candidate := dir.path_join(PARENT_NAME)
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
		var up := dir.get_base_dir()
		if up == dir:
			break
		dir = up
	return ProjectSettings.globalize_path("user://session-logs")


## The next number from `parent`/run_counter.txt (shared with the test runs), saved back.
static func _next_number(parent: String) -> int:
	var path := parent.path_join("run_counter.txt")
	var n := 0
	if FileAccess.file_exists(path):
		n = FileAccess.get_file_as_string(path).strip_edges().to_int()
	n += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line(str(n))
		f.close()
	return n


## "B0046-dev-983b844" from a test build's folder name, "editor-<sha>" in the editor, else "build".
static func _build_name() -> String:
	if OS.has_feature("editor"):
		return "editor-" + _git_sha(ProjectSettings.globalize_path("res://"))
	var m := RegEx.create_from_string("-(B\\d+-.+)$").search(OS.get_executable_path().get_base_dir().get_file())
	return m.get_string(1) if m else "build"


## The checked-out commit (7 characters) of the git checkout or worktree at `dir`, or "nosha".
static func _git_sha(dir: String) -> String:
	var git := dir.path_join(".git")
	if FileAccess.file_exists(git):  # a worktree: "gitdir: <path>"
		git = FileAccess.get_file_as_string(git).strip_edges().trim_prefix("gitdir:").strip_edges()
	var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
	if head.begins_with("ref:"):
		var ref := head.trim_prefix("ref:").strip_edges()
		var common := git
		if FileAccess.file_exists(git.path_join("commondir")):
			common = git.path_join(FileAccess.get_file_as_string(git.path_join("commondir")).strip_edges()).simplify_path()
		head = FileAccess.get_file_as_string(common.path_join(ref)).strip_edges()
		if head == "":
			for line in FileAccess.get_file_as_string(common.path_join("packed-refs")).split("\n"):
				if line.ends_with(" " + ref):
					head = line.get_slice(" ", 0)
	return head.substr(0, 7) if head.length() >= 7 else "nosha"
