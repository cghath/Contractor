extends Node
## A stand-in for the Captain in a co-op soak with --human (tools/coop_soak.sh): a plain client
## that joins through the main menu's Join like a player's build does (no soak token, no bot
## status file, so the host takes it for a human). Each deployment it says ready on the
## briefing, stands a while, walks toward the objective, stops, calls an extraction point where
## it stands and confirms it. It checks what the --human bots must do: it got its role's kit,
## the bots stay 10-25 m off it, they come into its extraction point, everyone goes home.
##   CONTRACTOR_PORT=<host port> <godot> --headless --path . res://tests/coop_fake_human.tscn -- --out <dir> [--deployments 2]
## Exit 0 when every check passed.

const WALK_SPEED := 4.0
const STAND_S := 45.0       # standing at the insertion first (the bots come to it)
const WALK_M := 160.0       # then toward the objective
const HOLD_S := 30.0
const GATHER_S := 120.0
const NEAR_M := 30.0        # a bot this close counts as "with the human" (FOLLOW is 10-25 m)

var out_dir := ""
var deployments := 2
var main: Node
var _t0 := 0.0
var _problems: Array[String] = []
var _log: FileAccess
var _samples := 0
var _samples_all_near := 0
var _dist_max := 0.0
var _goal: Variant = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = _arg(args, "--out", ProjectSettings.globalize_path("user://fake_human"))
	deployments = int(_arg(args, "--deployments", "2"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("fake_human.log"), FileAccess.WRITE)
	_t0 = Time.get_unix_time_from_system()
	Campaign.campaign_id = "coop_fake_human"
	GameState.zone_id = "coop_fake_human"
	BaseHub.local_profile = "fake_human"
	Roles.local_choice = Roles.RIFLEMAN
	get_tree().create_timer(5400.0, true, false, true).timeout.connect(func() -> void:
		_problem("timed out")
		_finish())
	main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"  # at /root/Main, as in a player's build (the host has it there too)
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_run()


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _say(text: String) -> void:
	var line := "[human %.1f] %s" % [Time.get_unix_time_from_system() - _t0, text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


func _problem(text: String) -> void:
	_problems.append(text)
	_say("PROBLEM: " + text)


func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(cond: Callable, s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(s * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().create_timer(0.2).timeout
	return true


func _online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
		and (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _level() -> CompoundLevel:
	return CompoundLevel.current(self)


func _me() -> Soldier:
	var lvl := _level()
	if lvl == null or not _online():
		return null
	var players := lvl.get_node_or_null(^"Players")
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if players else null


func _in_zone() -> bool:
	return _level() != null and not (_level() is BaseLevel) and _me() != null


func _run() -> void:
	main.get_node(^"Menu").join("127.0.0.1")
	if not await _wait_for(func() -> bool: return _online() and _me() != null, 120.0):
		_problem("could not join the host on port %d" % Net.port())
		_finish()
		return
	_say("joined as peer %d into the %s" % [multiplayer.get_unique_id(), "base" if _level() is BaseLevel else "zone"])
	for n in range(1, deployments + 1):
		if not await _wait_for(_in_zone, 900.0):
			_problem("deployment %d: the session never went to a zone" % n)
			break
		_say("deployment %d: in the zone" % n)
		await _check_kit(n)
		var briefing := MapNodes.briefing(_level())
		await _wait_for(func() -> bool: return briefing != null and briefing.is_open(), 30.0)
		await _sleep(8.0)  # reading the briefing: the bots must wait for this "ready"
		if briefing:
			briefing.request_set_ready(true)
			_say("ready on the briefing")
		await _wait_for(Contracts.is_deployed, 60.0)
		await _deployment(n)
		if not await _wait_for(func() -> bool: return _level() is BaseLevel, 120.0):
			_problem("deployment %d: never got back to the base" % n)
			break
		_say("deployment %d: back at the base" % n)
	_finish()


func _check_kit(n: int) -> void:
	await _wait_for(func() -> bool: return _me() != null and _me().inventory.slots.get(&"vest", &"") != &"", 30.0)
	var me := _me()
	if me == null:
		return
	var slots: Dictionary = me.inventory.slots
	var line := "carrier=%s front=%s rear=%s helmet=%s primary=%s" % [slots.get(&"vest", &"-"), slots.get(&"plate_front", &"-"),
		slots.get(&"plate_back", &"-"), slots.get(&"helmet", &"-"), slots.get(&"primary", &"-")]
	_say("[kit] deployment %d: %s" % [n, line])
	if slots.get(&"vest", &"") == &"" or slots.get(&"primary", &"") == &"":
		_problem("deployment %d: no role kit (%s)" % [n, line])


## Stand, walk toward the objective, hold, call an extraction point here and confirm it.
func _deployment(n: int) -> void:
	await _watch(STAND_S, "standing at the insertion")
	var me := _me()
	var target := me.global_position + Vector3(0, 0, -WALK_M) if me else Vector3.ZERO
	var objs := MapNodes.briefing(_level()).map_objectives() if MapNodes.briefing(_level()) else []
	if me and not objs.is_empty():
		var o: Vector2 = objs[0].pos
		var dir := Vector3(o.x - me.global_position.x, 0.0, o.y - me.global_position.z)
		var go := minf(WALK_M, maxf(dir.length() - 180.0, 40.0))
		target = me.global_position + dir.normalized() * go
	_goal = target
	await _watch(WALK_M / WALK_SPEED + 10.0, "walking toward the objective")
	_goal = null
	await _watch(HOLD_S, "holding")
	me = _me()
	var extraction := MapNodes.extraction(_level())
	if me == null or extraction == null:
		_problem("deployment %d: no extraction to call" % n)
		return
	extraction.request_point_at(Vector2(me.global_position.x, me.global_position.z))
	_say("called an extraction point where I stand")
	var gathered := false
	var deadline := Time.get_unix_time_from_system() + GATHER_S
	while Time.get_unix_time_from_system() < deadline and not (_level() is BaseLevel):
		await _watch(5.0, "")
		if extraction.state == Extraction.State.COUNTDOWN or _level() is BaseLevel:
			gathered = true
			break
		extraction.request_confirm()  # refused until the squad is in the point
	_say("extraction: %s" % ("confirmed, the bots were in the point" if gathered else "NOT confirmed in %d s" % int(GATHER_S)))
	if not gathered:
		_problem("deployment %d: the bots never got into the extraction point with me" % n)


## Plays `seconds` (moving toward _goal if set) and logs how far each bot is every 5 s.
func _watch(seconds: float, what: String) -> void:
	if what != "":
		_say(what)
	var end := Time.get_unix_time_from_system() + seconds
	var next_note := 0.0
	while Time.get_unix_time_from_system() < end and _in_zone():
		await get_tree().physics_frame
		var me := _me()
		if me == null:
			continue
		if _goal != null and me.vitals.is_up():
			var to: Vector3 = _goal
			var d := Vector2(to.x - me.global_position.x, to.z - me.global_position.z)
			if d.length() < 1.0:
				_goal = null
			else:
				var step := d.normalized() * minf(WALK_SPEED * get_physics_process_delta_time(), d.length())
				var pos := me.global_position + Vector3(step.x, 0.0, step.y)
				var ground := _level().ground_point(pos)
				pos.y = maxf(pos.y, ground.y)
				me.global_position = pos
				me.rotation.y = atan2(-d.x, -d.y)
		if Time.get_unix_time_from_system() >= next_note:
			next_note = Time.get_unix_time_from_system() + 5.0
			_note(me, Time.get_unix_time_from_system() + 20.0 < end or _goal == null)


func _note(me: Soldier, count_it: bool) -> void:
	var parts: Array[String] = []
	var all_near := true
	var players := _level().get_node_or_null(^"Players")
	for c in (players.get_children() if players else []):
		var s := c as Soldier
		if s == null or s == me:
			continue
		var d := Vector2(s.global_position.x - me.global_position.x, s.global_position.z - me.global_position.z).length()
		parts.append("%s %.0f m%s" % [s.name, d, "" if s.vitals.is_up() else " (down)"])
		if s.vitals.is_up():
			_dist_max = maxf(_dist_max, d) if count_it else _dist_max
			all_near = all_near and d <= NEAR_M
	if count_it and not parts.is_empty():
		_samples += 1
		_samples_all_near += 1 if all_near else 0
	_say("me %s; %s" % ["up" if me.vitals.is_up() else me.vitals.condition_text(), ", ".join(parts)])


func _finish() -> void:
	var share := float(_samples_all_near) / float(maxi(_samples, 1))
	_say("summary: %d samples, every bot within %d m in %.0f%% of them; farthest bot %.0f m" % [_samples, int(NEAR_M), share * 100.0, _dist_max])
	if _samples > 0 and share < 0.7:
		_problem("the bots were not with me: all within %d m in only %.0f%% of the samples" % [int(NEAR_M), share * 100.0])
	_say("finished: %d problem(s)%s" % [_problems.size(), (": " + "; ".join(_problems)) if not _problems.is_empty() else ""])
	if _online():
		Net.leave()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if _problems.is_empty() else 1)
