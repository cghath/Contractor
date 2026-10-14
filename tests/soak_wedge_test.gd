extends "res://tests/coop_soak.gd"
## soak-stuck-bots, the scripted check (review of 25dcf0c/10a41c3: the fix had never run in the
## case it was meant for). S0758: both client bots stood up and unhurt at harbour_yard's town_4
## south wall for 20 minutes, 400 m behind the human. This puts the soak's own bot (the soak
## harness's movement, _track_wedge, _catch_up: this script extends tests/coop_soak.gd) on
## client 1's spot, (232.7, -0.55, -290.9), with a leader where the human was heading,
## (110, -668), and checks:
##   1. with the wedge handling off, the straight walk at the leader makes no headway there
##      although the harness steps the bot at its goal every frame (the pocket is real: the
##      voxel diagnosis, not a goal that stayed null or another gate);
##   2. with it on, the bot is caught up beside the leader within CAUGHT_BY_S;
##   3. after that it keeps up: the leader moves 30 m on and the bot follows within 4 m.
## One process, headless, no garrison:
##   CONTRACTOR_PORT=25490 <voxel godot exe> --headless --path . res://tests/soak_wedge_test.tscn

const POCKET := Vector3(232.7, -0.55, -290.9)  # client 1 in S0758, t 1791989925 on
const LEAD_AT := Vector2(110.0, -668.0)
const CAUGHT_BY_S := 25.0
const NO_WAY_M := 2.0  # headway (m) over 8 s that still counts as wedged in step 1

var _leader: Soldier
var _wedge_off := false
var _caught_at := -1.0
var _problems: Array[String] = []
var _ended := false
var _step_frames := 0  # physics frames the harness stepped the bot at its goal


func _ready() -> void:
	role = "host"
	run_dir = ProjectSettings.globalize_path("user://soak_wedge_test")
	DirAccess.make_dir_recursive_absolute(run_dir)
	_t0 = Recorder.now()
	recorder = Recorder.new()
	recorder.name = "Recorder"
	recorder.out_dir = run_dir
	add_child(recorder)
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_soak_wedge" + tag  # never a real save
	Campaign.campaign_id = "test_soak_wedge_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		_problem("timed out")
		_end())
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("harbour_yard"))
	if not await _wait_for(func() -> bool: return _me() != null, 60.0):
		_problem("no player soldier")
		_end()
		return
	var lvl := _level() as ZoneLevel
	var me := _me()
	_leader = lvl.spawn_soldier({"name": "WedgeLead", "faction": "friendly", "variant": "multicam", "pos": lvl.ground_point(Vector3(LEAD_AT.x, 0.0, LEAD_AT.y)),
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
	_leader.process_mode = Node.PROCESS_MODE_DISABLED  # stays put: a moving leader would blur the headway
	# The bot on the spot until town_4's voxels are in, with their own collision.
	var town := lvl.module_at(POCKET)
	if town == null:
		_problem("no module at %s" % Recorder._v3(POCKET))
		_end()
		return
	if not await _wait_for(func() -> bool:
			_hold(me)
			return town.is_ready(), 120.0):
		_problem("%s never streamed in" % town.module_id)
		_end()
		return
	for i in 30:
		_hold(me)
		await get_tree().physics_frame
	_say("on %s (%s) at %s, leader at %s, %.0f m off" % [town.module_id, town.type, Recorder._v3(me.global_position),
		Recorder._v3(_leader.global_position), _flat(me.global_position, _leader.global_position)])

	# 1. No wedge handling: the straight walk at the leader.
	_wedge_off = true
	var goal := _leader.global_position
	var d0 := _flat(me.global_position, goal)
	_walk(goal, 2.0, RUN_SPEED)
	_step_frames = 0
	var frames := 0
	var strayed := 0.0  # the farthest it got from the spot: steps taken and undone, or none at all
	var until := Recorder.now() + 8.0
	while Recorder.now() < until:
		await get_tree().physics_frame
		frames += 1
		strayed = maxf(strayed, _flat(me.global_position, POCKET))
	var headway := d0 - _flat(me.global_position, goal)
	_say("step 1, wedge handling off: %.1f m headway in 8 s, at %s, at most %.2f m off the spot meanwhile, stepped at the goal %d of %d frames, goal %s" % [
		headway, Recorder._v3(me.global_position), strayed, _step_frames, frames, Recorder._v3(_goal) if _goal != null else "none"])
	if _step_frames < frames / 2:
		_problem("the bot was hardly stepped at its goal (%d of %d frames): a gate (goal, pinned, down, vehicle) held it, not the wall" % [_step_frames, frames])
	if headway > NO_WAY_M:
		_problem("the S0758 spot does not hold a bot walking at the leader (%.1f m headway in 8 s): the pocket diagnosis is wrong" % headway)

	# 2. With it: the detours, then the catch-up.
	_goal = null
	for i in 30:
		_hold(me)
		await get_tree().physics_frame
	_wedge_off = false
	_wedge_last = Vector3.INF
	_detour_until = 0.0
	var t1 := Recorder.now()
	_walk(_leader.global_position, 2.0, RUN_SPEED)
	await _wait_for(func() -> bool: return _caught_at >= 0.0, CAUGHT_BY_S + 5.0)
	if _caught_at < 0.0:
		_problem("not caught up %.0f s after the walk started (at %s, %.0f m from the leader)" % [Recorder.now() - t1,
			Recorder._v3(me.global_position), _flat(me.global_position, _leader.global_position)])
		_end()
		return
	_say("step 2: caught up %.1f s after the walk started" % (_caught_at - t1))
	if _caught_at - t1 > CAUGHT_BY_S:
		_problem("caught up only after %.1f s (want %.0f s)" % [_caught_at - t1, CAUGHT_BY_S])

	# 3. Keeps up: the leader 30 m on, the bot after them.
	var on := _leader.global_position + Vector3(0.0, 0.0, -30.0)
	_leader.global_position = lvl.ground_point(on)
	var kept := await _wait_for(func() -> bool:
		_walk(_leader.global_position, 2.0, RUN_SPEED)
		return _flat(me.global_position, _leader.global_position) <= 4.0, 20.0)
	_say("step 3: %s, %.1f m from the leader" % ["kept up" if kept else "fell behind", _flat(me.global_position, _leader.global_position)])
	if not kept:
		_problem("fell behind after the catch-up: %.1f m from the leader 20 s on" % _flat(me.global_position, _leader.global_position))
	_end()


## Keeps the bot still on POCKET (its own physics would let it settle or slide off meanwhile).
func _hold(me: Soldier) -> void:
	_goal = null
	me.velocity = Vector3.ZERO
	me.global_position = POCKET


func _wedge_leader() -> Soldier:
	return _leader


## Runs every frame the harness may step the bot (not down, not riding); it steps it when
## there is a goal and it isn't pinned.
func _track_wedge(me: Soldier, pinned: bool) -> void:
	if _goal != null and not pinned:
		_step_frames += 1
	if not _wedge_off:
		super(me, pinned)


func _catch_up(me: Soldier, wedged: float) -> bool:
	var moved := super(me, wedged)
	if moved and _caught_at < 0.0:
		_caught_at = Recorder.now()
	return moved


func _problem(text: String) -> void:
	_problems.append(text)
	print("[FAIL] " + text)


func _end() -> void:
	if _ended:
		return
	_ended = true
	if _problems.is_empty():
		print("SOAK_WEDGE TEST PASSED")
	else:
		print("SOAK_WEDGE TEST FAILED: %d problem(s)" % _problems.size())
	recorder.close()
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0 if _problems.is_empty() else 1)
