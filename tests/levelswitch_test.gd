extends Node
## B-04 (co-op despawn and rejoin errors, S0743/S0758): a player leaving and a level switch
## log no replication errors on the peers that stay. Two processes over real ENet, like the
## net suite, plus a third the host starts itself (a second client that joins and leaves):
##   <exe> --headless --path . res://tests/levelswitch_test.tscn -- --levelswitch-host
##   <exe> --headless --path . res://tests/levelswitch_test.tscn -- --levelswitch-join 127.0.0.1
## The host stages a few AI (spawner-tracked nodes) once the client is in, starts the leaver,
## and once it has come and gone switches the level (BaseHub.server_switch_level) with the
## client still in. The client checks that the leaver's player went with the host's despawn
## and that neither the leave nor the switch logged a B-04 error: a despawn for a node it had
## already freed ('!pinfo.recv_nodes.has(net_id)'), a delta for a synchronizer gone with the
## old level ('Ignoring delta'), or a Sync of the old level's player ('Node not found' .../Sync).
## Each process prints LEVELSWITCH TEST PASSED/FAILED and exits with its failure count; the
## host exits when the client leaves.

## What a B-04 error says (the engine's condition or message), any one of them.
const B04_PATTERNS := ["recv_nodes", "Ignoring delta", "went ahead without peers"]
## How long the host waits for each step before failing it.
const STEP_S := 60.0
## AI the host stages, so the old level has spawner-tracked nodes to despawn on the switch.
const STAGED_AI := 3

var failures := 0
var level: CompoundLevel
var main: Node
var _catcher: _Catcher
var _leaver_pid := -1
var _leaver_log := ""


## Every engine and script error and warning this process logs, on whatever thread logs it.
class _Catcher extends Logger:
	var mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		lines.append("%s %s (%s, %s:%d)" % [code, rationale, function, file.get_file(), line])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## The lines caught since `from` that are B-04's (B04_PATTERNS, or a Sync node not found).
	func b04_since(from: int) -> Array[String]:
		mutex.lock()
		var out: Array[String] = []
		for i in range(from, lines.size()):
			var text := lines[i]
			if B04_PATTERNS.any(func(p: String) -> bool: return text.contains(p)) or (text.contains("Node not found") and text.contains("/Sync")):
				out.append(text)
		mutex.unlock()
		return out

	func count() -> int:
		mutex.lock()
		var n := lines.size()
		mutex.unlock()
		return n


func _ready() -> void:
	_catcher = _Catcher.new()
	OS.add_logger(_catcher)
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_levelswitch" + tag  # never touch a real save
	Campaign.campaign_id = "test_levelswitch" + tag
	CompoundLevel.spawn_ai = false
	var args := OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	for flag: String in ["--levelswitch-join", "--levelswitch-leaver"]:
		if flag in args:
			var i := args.find(flag)
			add_child(main)
			await get_tree().process_frame
			level = CompoundLevel.current(self)
			main.menu.join(args[i + 1] if i + 1 < args.size() else "127.0.0.1")
			if flag == "--levelswitch-leaver":
				await _run_leaver()
			else:
				await _run_client()
			return
	GameState.delete_save()
	add_child(main)
	await get_tree().process_frame
	level = CompoundLevel.current(self)
	await _run_host()


func _exit_tree() -> void:
	OS.remove_logger(_catcher)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The players a client has, by peer id, in the level running now.
func _player(id: int) -> Soldier:
	var lvl := CompoundLevel.current(self)
	return lvl.players.get_node_or_null(str(id)) as Soldier if lvl else null


func _finish() -> void:
	print("LEVELSWITCH TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


# --- host ---------------------------------------------------------------------------------

func _run_host() -> void:
	var joined: Array[int] = []
	var left: Array[int] = []
	Net.peer_joined.connect(func(id: int) -> void: joined.append(id))
	Net.peer_left.connect(func(id: int) -> void: left.append(id))
	main.menu.host()
	check(Net.is_hosting(), "hosting on port %d" % Net.port())
	if not Net.is_hosting():
		_finish()
		return
	# The client from the runner first.
	await _wait_for(func() -> bool: return joined.size() >= 1 and level.players.get_node_or_null(str(joined[0])) != null, STEP_S)
	check(joined.size() >= 1, "the client joined")
	if joined.is_empty():
		_finish()
		return
	var client := joined[0]
	await _wait_for(func() -> bool: return level.voxel_world.is_built(), STEP_S)
	for i in STAGED_AI:
		var s := level.spawn_soldier({"name": "Staged%d" % i, "faction": "hostile", "variant": "woodland", "pos": Vector3(10 + 2 * i, 0.1, 30),
			"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	# A second client joins and leaves on its feet (_run_leaver).
	_start_leaver()
	await _wait_for(func() -> bool: return joined.size() >= 2, STEP_S)
	check(joined.size() >= 2, "a second client (the leaver) joined (pid %d)" % _leaver_pid)
	if joined.size() >= 2:
		var leaver := joined[1]
		await _wait_for(func() -> bool: return leaver in left, STEP_S)
		check(leaver in left, "and left")
		await _wait_for(func() -> bool: return level.players.get_node_or_null(str(leaver)) == null, 3.0)
		check(level.players.get_node_or_null(str(leaver)) == null, "its player went with it (left on its feet)")
	await _seconds(1.0)
	# The switch, with the client still in: it holds its Sync and says so, the host swaps.
	var errors_from := _catcher.count()
	var switched: Array[CompoundLevel] = []
	# What the old level still replicates when the switch RPC has gone out (level_switched is
	# emitted right after it): its spawners and the host's own synchronizers must already be out
	# of it, so the despawns went out first. On a clean localhost link the RPC and the despawns
	# land in one poll and the client's errors never show; on a lossy or loaded one the despawns
	# came after the client had freed the old level (S0743), and deltas inside the poll that ran
	# the switch reached nodes already despawned (S0830).
	var old := level
	var left_in_old := {}
	BaseHub.level_switched.connect(func(fresh: CompoundLevel) -> void:
		switched.append(fresh)
		left_in_old["spawners"] = old.find_children("*", "MultiplayerSpawner", true, false).size()
		left_in_old["syncs"] = old.find_children("*", "MultiplayerSynchronizer", true, false).filter(
			func(n: Node) -> bool: return n.is_multiplayer_authority()).size(), CONNECT_ONE_SHOT)
	var spawners_before := old.find_children("*", "MultiplayerSpawner", true, false).size()
	BaseHub.server_switch_level(level.level_info())
	await _wait_for(func() -> bool: return not switched.is_empty(), STEP_S)
	check(not switched.is_empty() and switched[0] != level, "the host switched the level with the client in")
	check(spawners_before > 0 and left_in_old.get("spawners", -1) == 0 and left_in_old.get("syncs", -1) == 0,
		"the old level's spawners (%d) and the host's synchronizers were gone before the switch RPC went out (left: %s)" % [spawners_before, left_in_old])
	if not switched.is_empty():
		level = switched[0]
	await _wait_for(func() -> bool: return client in left, STEP_S)  # the client checks and goes
	await _seconds(0.5)
	var b04 := _catcher.b04_since(errors_from)
	check(b04.is_empty(), "host: the switch went ahead with the client ready, and no Sync of its old player arrived after it (%d B-04 lines%s)" % [
		b04.size(), "" if b04.is_empty() else ": %s" % b04[0]])
	_stop_leaver()
	_finish()


## Starts the leaver: this scene in a third headless process (never a window: the Captain may be
## gaming), its log in user data so the host can show it.
func _start_leaver() -> void:
	_leaver_log = ProjectSettings.globalize_path("user://levelswitch_leaver%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(_leaver_log)
	_leaver_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", _leaver_log, "res://tests/levelswitch_test.tscn", "--", "--levelswitch-leaver", "127.0.0.1"])
	print("[host] started the leaver (pid %d)" % _leaver_pid)


func _stop_leaver() -> void:
	if _leaver_pid > 0 and OS.is_process_running(_leaver_pid):
		OS.kill(_leaver_pid)
	var text := FileAccess.get_file_as_string(_leaver_log)
	for line in text.split("\n"):
		if line.contains("[leaver]") or line.contains("ERROR"):
			print("  [leaver log] %s" % line)


# --- leaver -------------------------------------------------------------------------------

func _run_leaver() -> void:
	await _wait_for(func() -> bool: return multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and _player(multiplayer.get_unique_id()) != null, STEP_S)
	print("[leaver] in as peer %d: %s" % [multiplayer.get_unique_id(), _player(multiplayer.get_unique_id()) != null])
	await _seconds(2.0)
	print("[leaver] leaving")
	Net.leave()
	await _seconds(0.5)
	get_tree().quit(0)


# --- client -------------------------------------------------------------------------------

func _run_client() -> void:
	var others: Array[int] = []
	var gone: Array[int] = []
	Net.peer_joined.connect(func(id: int) -> void:
		if id != 1:
			others.append(id))
	Net.peer_left.connect(func(id: int) -> void: gone.append(id))
	var switched: Array[CompoundLevel] = []
	BaseHub.level_switched.connect(func(fresh: CompoundLevel) -> void: switched.append(fresh))
	await _wait_for(func() -> bool: return multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and _player(multiplayer.get_unique_id()) != null, STEP_S)
	var me := multiplayer.get_unique_id()
	check(_player(me) != null, "joined as peer %d, with its player" % me)
	if _player(me) == null:
		_finish()
		return
	# The leaver comes and goes.
	await _wait_for(func() -> bool: return not others.is_empty() and _player(others[0]) != null, STEP_S)
	check(not others.is_empty() and _player(others[0]) != null, "the second client's player spawned here")
	if not others.is_empty():
		var leaver := others[0]
		var errors_from := _catcher.count()
		await _wait_for(func() -> bool: return leaver in gone, STEP_S)
		await _wait_for(func() -> bool: return _player(leaver) == null, 5.0)
		await _seconds(1.5)  # a late despawn would land by now
		var b04 := _catcher.b04_since(errors_from)
		check(leaver in gone and _player(leaver) == null and b04.is_empty(),
			"a client leaving: its player goes here with the host's despawn, no errors (%d B-04 lines%s)" % [b04.size(), "" if b04.is_empty() else ": %s" % b04[0]])
	# The host switches the level.
	var switch_from := _catcher.count()
	await _wait_for(func() -> bool: return not switched.is_empty(), STEP_S)
	check(not switched.is_empty(), "the host's level switch reached this client")
	if not switched.is_empty():
		var fresh := switched[0]
		await _wait_for(func() -> bool: return fresh.players.get_node_or_null(str(me)) != null and fresh.players.get_node_or_null(^"1") != null, 15.0)
		check(fresh.players.get_node_or_null(str(me)) != null and fresh.players.get_node_or_null(^"1") != null,
			"its player and the host's are back in the new level")
		await _seconds(3.0)  # deltas and despawns for the old level would land by now
		var b04 := _catcher.b04_since(switch_from)
		check(b04.is_empty(), "the switch logged no despawn, delta or Sync errors here (%d B-04 lines%s)" % [b04.size(), "" if b04.is_empty() else ": %s" % b04[0]])
		for line in b04.slice(0, 5):
			print("    %s" % line)
	_finish()
