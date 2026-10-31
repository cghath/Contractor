extends Node
## Bots joining a human-hosted game (Captain's open item 7, docs/captain_side_now.md "Next"; the
## co-op soak's --join, tools/coop_soak.sh). This process is the human: it hosts the way the
## build's menu does, and starts the soak bot (tests/coop_soak.tscn --soak-join, a second
## process) that joins it as a player would. Two sessions:
## - "Play (host a session)": the human alone gets 7 AI squadmates; the bot (a medic) takes the
##   AI medic's slot in its fire team, with the medic's kit and that slot's battle buddy, and the
##   AI it replaced leaves; the bot sees itself in the slot, role, team and buddy the host has it
##   in (its posted status); it follows the human; when it leaves, an AI medic takes the slot
##   back; it joins again as the same player (not a second profile) into the same slot.
## - "Campaign: host at the base": the bot joins the FOB as its own main character, gets its
##   role's kit once and readies up with the human; leaving keeps its gear on its record (and in
##   the campaign save); joining again brings the same gear back, no second kit.
## The bot runs on its own settings file (coop_soak.gd, F-332), never this PC's; its engine logs
## are kept in the run's log folder (CONTRACTOR_RUN_LOGS, tools/run_tests.sh) and each is checked
## for script errors and problems; on a failure the last lines of the bot's log are printed.
##   <voxel godot exe> --headless --path . res://tests/botsjoin_test.tscn
## Exits with the number of failures.

## How long the bot gets to join and be given its slot (it loads the level first), and to walk to
## its place off the human.
const JOIN_WAIT_S := 150.0
const FOLLOW_WAIT_S := 75.0
## Where the human stands for the follow check: open ground south of the compound, ~40 m from
## where a joiner comes in (CompoundLevel.SPAWN_POINTS).
const HUMAN_AT := Vector3(25, 0.1, 55)

var failures := 0
var level: CompoundLevel
var human: Soldier
var _tag := ""
var _run_dir := ""
var _joined: Array[int] = []
var _left: Array[int] = []
var _bot_runs := 0
## The bot's process while one runs (0 when none): killed if this test times out, so no bot is
## left running.
var _bot_pid := 0
## The run's own log folder (tools/run_tests.sh), where the bot's logs are kept beside this
## suite's (docs/debugging.md); "" outside the runner (then they stay in _run_dir).
var _logs_dir := ""


func _ready() -> void:
	_tag = OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_botsjoin" + _tag  # never touch a real save
	Campaign.campaign_id = "test_botsjoin" + _tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_botsjoin_settings%s.cfg" % _tag))  # never the player's
	GameSettings.reset_all()
	Handedness._left = false  # right-handed whatever this machine's settings say (never saved)
	Handedness._loaded = true
	ControlOptions._get_out = ControlOptions.GET_OUT_DEFAULT
	ControlOptions._loaded = true
	_logs_dir = OS.get_environment("CONTRACTOR_RUN_LOGS")
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "botsjoin_human"
	BaseHub.standing_squads = false
	PeopleLayer.populate = false
	CompoundLevel.spawn_ai = true
	_run_dir = OS.get_user_data_dir().path_join("botsjoin%s" % _tag)
	DirAccess.make_dir_recursive_absolute(_run_dir)
	get_tree().create_timer(720.0).timeout.connect(func() -> void:
		_print_bot_tail()
		_stop_bot(_bot_pid)
		print("BOTSJOIN TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	Net.peer_joined.connect(func(id: int) -> void: _joined.append(id))
	Net.peer_left.connect(func(id: int) -> void: _left.append(id))
	await _test_plain_session()
	await _end_session()
	await _test_campaign()
	await _end_session()
	GameState.zone_id = "test_botsjoin" + _tag
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	GameSettings.reset_all()
	GameSettings.use_file("")
	print("BOTSJOIN TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Play (host a session) -----------------------------------------------------------------------

func _test_plain_session() -> void:
	print("A human hosts a session; AI fills the squad")
	var menu := await _add_main()
	menu._plain_host()  # the menu's "Play (host a session)"
	level = CompoundLevel.current(self)
	var up := await _until(func() -> bool: return level.players.get_node_or_null(^"1") != null and _squad().size() == Roles.slot_count() - 1, 60.0)
	human = level.players.get_node_or_null(^"1")
	check(up and human != null, "the session is up with the human in it (%d AI)" % _squad().size())
	if not up or human == null:
		return
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()  # the bot fights what it sees: no fight here
	human.global_position = HUMAN_AT
	var layout := Roles.layout()
	var slots_ok := human.squad_slot == 0
	for s: Soldier in _squad():
		slots_ok = slots_ok and s.squad_slot > 0 and s.role == layout[s.squad_slot].role and s.fire_team == int(layout[s.squad_slot].team)
	check(slots_ok and human.buddy != null and human.buddy.squad_slot == Roles.buddy_slot(0),
		"alone, the human leads 7 AI squadmates, one in each other slot in its role, paired as buddies")
	var medic_b := _in_slot(7)
	check(medic_b != null and medic_b.role == Roles.MEDIC, "team B's medic slot is an AI's (%s)" % (String(medic_b.name) if medic_b else "nobody"))

	print("A bot joins the human's session (a medic)")
	var pid := _start_bot()
	var peer := await _wait_joined(JOIN_WAIT_S)
	var bot: Soldier = level.players.get_node_or_null(str(peer)) if peer > 0 else null
	var placed := await _until(func() -> bool: return is_instance_valid(bot) and bot.squad_slot >= 0 and bot.inventory.count_of(&"trauma_kit") > 0, 20.0)
	check(placed, "the bot joined and has a slot (peer %d, slot %d)" % [peer, bot.squad_slot if is_instance_valid(bot) else -2])
	if not placed:
		_print_bot_tail()
		_stop_bot(pid)
		return
	var first_key := BaseHub.player_key(peer)
	await _frames(3)
	check(bot.role == Roles.MEDIC and bot.squad_slot == 7 and bot.fire_team == 1,
		"it takes team B's medic slot (the fire team with no player yet): slot %d, %s, team %d" % [bot.squad_slot, bot.role, bot.fire_team])
	check(not is_instance_valid(medic_b) or medic_b.is_queued_for_deletion(), "the AI medic who held the slot leaves the session")
	check(_squad().size() == Roles.slot_count() - 2 and _in_slot(7) == null, "6 AI squadmates now, none in the bot's slot (%d)" % _squad().size())
	var buddy := _in_slot(6)
	check(buddy != null and bot.buddy == buddy and buddy.buddy == bot, "the bot pairs with the slot's battle buddy (%s)" % (String(buddy.name) if buddy else "nobody"))
	var seen := await _until(func() -> bool: return _place_matches(bot), 15.0)
	check(seen, "the bot sees itself where the host has it: slot, role, team and buddy (bot: %s; host: %s)" % [_bot_place(), _host_place(bot)])
	check(bot.inventory.count_of(&"trauma_kit") >= 1 and bot.inventory.count_of(&"tourniquet") >= 5 and bot.inventory.slots.get(&"primary", &"") == &"m4a1",
		"in the medic's kit (%d tourniquets, %s)" % [bot.inventory.count_of(&"tourniquet"), bot.inventory.slots.get(&"primary", &"")])
	var came_in := bot.global_position
	var follows := await _until(func() -> bool:
		if not is_instance_valid(bot):
			return false
		var d := _flat(bot.global_position, human.global_position)
		return d <= 28.0 and d >= 4.0 and _flat(bot.global_position, came_in) > 10.0, FOLLOW_WAIT_S)
	check(follows, "it walks over to keep its place off the human (%.1f m off them, came in %.1f m off)"
		% [_flat(bot.global_position, human.global_position) if is_instance_valid(bot) else -1.0, _flat(came_in, human.global_position)])

	print("The bot leaves")
	var gone := await _bot_leaves(pid, peer)
	check(gone, "it leaves the session (peer %d)" % peer)
	await _frames(3)
	var back := await _until(func() -> bool: return _squad().size() == Roles.slot_count() - 1 and _in_slot(7) != null, 10.0)
	var refill := _in_slot(7)
	check(back and refill != null and refill.role == Roles.MEDIC and refill.inventory.count_of(&"trauma_kit") >= 1,
		"an AI medic takes its slot back, in the medic's kit (%d AI, slot 7: %s)" % [_squad().size(), String(refill.name) if refill else "nobody"])
	var mate := _in_slot(6)
	check(refill != null and mate != null and refill.buddy == mate and mate.buddy == refill,
		"and pairs with the slot's buddy again (%s)" % (String(mate.name) if mate else "nobody in slot 6"))
	check(level.players.get_node_or_null(str(peer)) == null, "the bot's body went with it (it left on its feet)")
	_check_bot_log()

	# Coming back is the same player, not a second profile ("soak_bot1_2"): BaseHub forgets a
	# plain session's profile when its player leaves.
	print("The bot joins again")
	pid = _start_bot()
	var again := await _wait_joined(JOIN_WAIT_S)
	var bot2: Soldier = level.players.get_node_or_null(str(again)) if again > 0 else null
	var placed2 := await _until(func() -> bool: return is_instance_valid(bot2) and bot2.squad_slot >= 0, 20.0)
	var keyed := await _until(func() -> bool: return BaseHub.player_key(again) == "soak_bot1", 10.0)
	check(placed2 and keyed and first_key == "soak_bot1",
		"it comes back as the same player (%s, first time %s), in a slot (%d)" % [BaseHub.player_key(again), first_key, bot2.squad_slot if is_instance_valid(bot2) else -2])
	if placed2:
		await _frames(3)
		check(bot2.squad_slot == 7 and bot2.role == Roles.MEDIC and _in_slot(7) == null,
			"in team B's medic slot again, the AI medic gone (slot %d, %s)" % [bot2.squad_slot, bot2.role])
		var seen2 := await _until(func() -> bool: return _place_matches(bot2), 15.0)
		check(seen2, "and sees itself where the host has it (bot: %s; host: %s)" % [_bot_place(), _host_place(bot2)])
	else:
		_print_bot_tail()
	check(await _bot_leaves(pid, again), "it leaves again (peer %d)" % again)
	_check_bot_log()


# --- Campaign: host at the base ------------------------------------------------------------------

func _test_campaign() -> void:
	print("A human hosts the campaign at the FOB; a bot joins")
	var menu := await _add_main()
	menu._campaign_host()  # the menu's "Campaign: host at the base (FOB)"
	var up := await _until(func() -> bool:
		level = CompoundLevel.current(self)
		return level is BaseLevel and level.players.get_node_or_null(^"1") != null, 60.0)
	check(up and BaseHub.campaign_running, "the campaign is up at the base")
	if not up:
		return
	human = level.players.get_node(^"1")
	var pid := _start_bot()
	var peer := await _wait_joined(JOIN_WAIT_S)
	var bot: Soldier = level.players.get_node_or_null(str(peer)) if peer > 0 else null
	var kitted := await _until(func() -> bool: return is_instance_valid(bot) and bot.role == Roles.MEDIC and bot.inventory.count_of(&"trauma_kit") > 0, 30.0)
	var key := BaseHub.player_key(peer)
	check(kitted and key == "soak_bot1" and Roster.players(BaseHub.roster()).has(key),
		"the bot joins the FOB as its own main character (%s), in its role's kit (%s, %d trauma kits, %s)" % [key, bot.role if is_instance_valid(bot) else &"-",
		bot.inventory.count_of(&"trauma_kit") if is_instance_valid(bot) else -1, bot.inventory.slots if is_instance_valid(bot) else {}])
	if not kitted:
		_print_bot_tail()
		_stop_bot(pid)
		return
	var tq := bot.inventory.count_of(&"tourniquet")
	var mags := bot.inventory.count_of(&"mag_556")
	var ready := await _until(func() -> bool: return peer in BaseHub.ready_peers(), 30.0)
	check(ready and BaseHub.all_ready(), "it readies up at the FOB, so the human can deploy (%s)" % [BaseHub.ready_peers()])

	print("The bot leaves, then comes back")
	var gone := await _bot_leaves(pid, peer)
	check(gone, "it leaves the session")
	_check_bot_log()
	await _frames(3)
	var gear: Dictionary = Roster.players(BaseHub.roster()).get("soak_bot1", {}).get("gear", {})
	check(JSON.stringify(gear).contains("\"trauma_kit\""), "its gear stays on its record (left on its feet)")
	check(BaseHub.server_save(), "the campaign saves")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Campaign.save_path()))
	var saved_gear: Variant = saved.get("sections", {}).get("roster", {}).get("players", {}).get("soak_bot1", {}).get("gear", {}) if saved is Dictionary else {}
	check(JSON.stringify(saved_gear).contains("\"trauma_kit\""), "and in the campaign save")
	pid = _start_bot()
	var again := await _wait_joined(JOIN_WAIT_S)
	var bot2: Soldier = level.players.get_node_or_null(str(again)) if again > 0 else null
	var geared := await _until(func() -> bool: return is_instance_valid(bot2) and bot2.role == Roles.MEDIC and bot2.inventory.count_of(&"trauma_kit") > 0, 30.0)
	await _seconds(2.0)  # (a second kit, if one came, would be on by now)
	check(geared and BaseHub.player_key(again) == "soak_bot1", "it joins again as the same main character (%s)" % BaseHub.player_key(again))
	if not geared:
		_print_bot_tail()
	if geared:
		check(bot2.inventory.count_of(&"tourniquet") == tq and bot2.inventory.count_of(&"mag_556") == mags,
			"with the gear it left in, no second kit (%d/%d tourniquets, %d/%d mags)" % [bot2.inventory.count_of(&"tourniquet"), tq, bot2.inventory.count_of(&"mag_556"), mags])
	var ready2 := await _until(func() -> bool: return again in BaseHub.ready_peers(), 30.0)
	check(ready2, "and readies up again")
	check(await _bot_leaves(pid, again), "it leaves again")
	_check_bot_log()


# --- The bot -------------------------------------------------------------------------------------

## Starts the soak bot (bot 1, a medic) joining this session; it leaves when _quit_file() exists.
func _start_bot() -> int:
	_bot_runs += 1
	DirAccess.remove_absolute(_quit_file())
	DirAccess.remove_absolute(_bot_log())
	DirAccess.remove_absolute(_bot_status_file())  # (the last run's place is not this one's)
	var args :=["--headless", "--log-file", _bot_log(), "--path", ProjectSettings.globalize_path("res://"), "res://tests/coop_soak.tscn", "--",
		"--soak-role", "client", "--soak-bot", "1", "--soak-run", _run_dir, "--soak-duration", "600", "--soak-human", "--soak-join",
		"--soak-address", "127.0.0.1", "--soak-quit-file", _quit_file()]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the bot's process (run %d, log %s)" % [_bot_runs, _bot_log()])
	_bot_pid = pid
	return pid


func _quit_file() -> String:
	return _run_dir.path_join("quit")


## The bot's engine log for this run of it: in the run's log folder beside this suite's log when
## run_tests.sh keeps one (docs/debugging.md), else in _run_dir.
func _bot_log() -> String:
	if _logs_dir != "":
		return _logs_dir.path_join("botsjoin-bot_run%d.log" % _bot_runs)
	return _run_dir.path_join("bot_run%d.log" % _bot_runs)


## The soak bot's posted status (coop_soak.gd _post_status: bot 1's).
func _bot_status_file() -> String:
	return _run_dir.path_join("bot1.json")


## The bot's place in the squad as it sees it itself (coop_soak.gd _post_place: slot, role, team
## and the name of whoever it sees in its buddy slot); {} until it has posted one.
func _bot_place() -> Dictionary:
	var path := _bot_status_file()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var place: Variant = parsed.get("place", {}) if parsed is Dictionary else {}
	return place if place is Dictionary else {}


## The same as the host has it for `bot` (Soldier.buddy is the host's own).
func _host_place(bot: Soldier) -> Dictionary:
	if not is_instance_valid(bot):
		return {}
	return {"slot": bot.squad_slot, "role": String(bot.role), "team": bot.fire_team, "buddy": String(bot.buddy.name) if is_instance_valid(bot.buddy) else ""}


## Whether the bot sees itself where the host has it (JSON numbers come back as floats).
func _place_matches(bot: Soldier) -> bool:
	var seen := _bot_place()
	var host := _host_place(bot)
	return not seen.is_empty() and not host.is_empty() and int(seen.get("slot", -9)) == int(host.slot) \
		and String(seen.get("role", "")) == String(host.role) and int(seen.get("team", -9)) == int(host.team) \
		and String(seen.get("buddy", "?")) == String(host.buddy)


## The next peer to join within `seconds` (0 if none did).
func _wait_joined(seconds: float) -> int:
	var before := _joined.size()
	await _until(func() -> bool: return _joined.size() > before, seconds)
	return _joined[before] if _joined.size() > before else 0


## Tells the bot to go and waits for its peer to leave and its process to end.
func _bot_leaves(pid: int, peer: int) -> bool:
	FileAccess.open(_quit_file(), FileAccess.WRITE).store_string("go")
	var left := await _until(func() -> bool: return peer in _left, 30.0)
	await _until(func() -> bool: return pid <= 0 or not OS.is_process_running(pid), 20.0)
	_stop_bot(pid)
	return left


func _stop_bot(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	if pid == _bot_pid:
		_bot_pid = 0


## The bot's own log: no script errors, and its harness saw no problem.
func _check_bot_log() -> void:
	var errors := PackedStringArray()
	var problems := PackedStringArray()
	if FileAccess.file_exists(_bot_log()):
		for line in FileAccess.get_file_as_string(_bot_log()).split("\n"):
			if line.contains("SCRIPT ERROR"):
				errors.append(line)
			elif line.contains("PROBLEM:"):
				problems.append(line)
	for line in errors + problems:
		print("    bot: %s" % line)
	var clean := FileAccess.file_exists(_bot_log()) and errors.is_empty() and problems.is_empty()
	check(clean, "no script errors or problems in the bot's log, run %d (%d, %d)" % [_bot_runs, errors.size(), problems.size()])
	if not clean:
		_print_bot_tail()


## The last lines of the bot's log, for a failure: what it was doing when it went wrong.
func _print_bot_tail(lines := 40) -> void:
	if _bot_runs == 0:
		return
	if not FileAccess.file_exists(_bot_log()):
		print("    (no bot log at %s)" % _bot_log())
		return
	var all := FileAccess.get_file_as_string(_bot_log()).split("\n")
	print("    the bot's log, run %d, last %d lines (%s):" % [_bot_runs, mini(lines, all.size()), _bot_log()])
	for line in all.slice(maxi(all.size() - lines, 0)):
		print("    bot| %s" % line)


## The game's Main at /root/Main, where the build has it: RPCs go by node path, and the bot's is
## there (coop_soak.gd _add_main). Returns its menu.
func _add_main() -> Menu:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)  # (the root is busy while this test's _ready runs)
	await get_tree().process_frame
	await get_tree().process_frame
	return main.get_node(^"Menu") as Menu


## Ends the hosted session as the pause menu's "Main menu" does, for the next one.
func _end_session() -> void:
	Net.leave()
	var main := get_tree().root.get_node_or_null(^"Main")
	if main:
		main.queue_free()
	await _frames(3)
	BaseHub.cancel_session()
	level = null
	human = null


# --- Helpers -------------------------------------------------------------------------------------

## Living friendly AI squadmates on the player squad (CompoundLevel._squad_ai's rule).
func _squad() -> Array:
	if level == null:
		return []
	return level._squad_ai().filter(func(s: Soldier) -> bool: return not s.is_queued_for_deletion())


func _in_slot(slot: int) -> Soldier:
	for s: Soldier in _squad():
		if s.squad_slot == slot:
			return s
	return null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
