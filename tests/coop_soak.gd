extends Node
## Co-op soak: one headless host and up to three headless clients, each its own Godot process,
## play the campaign loop together through the game's own requests and RPCs, for as long as
## asked, while each peer records snapshots, metrics and a replay (coop_soak_recorder.gd).
## A stand-in for a group playtest on one machine. Run it through tools/coop_soak.sh (it starts
## the processes, puts a lossy UDP relay between each client and the host, and writes the
## report); by hand:
##   CONTRACTOR_PORT=25347 <godot> --headless --path . res://tests/coop_soak.tscn -- --soak-role host --soak-run <dir> --soak-duration 600
##   CONTRACTOR_PORT=<relay port> <godot> --headless --path . res://tests/coop_soak.tscn -- --soak-role client --soak-bot 1 --soak-run <dir>
##
## Each cycle (the host leads it and posts the phase in <run>/phase.json, the out-of-band
## "voice chat" the bots coordinate by; each client posts what it did in <run>/bot<N>.json):
##   kit     every bot walks to the armory at the base and picks up a rifle, magazines, armour
##           and medical kit (world items, _server_interact)
##   contract bot 1 accepts the offer on the board (Contracts.accept, a client request) and bot 2
##           picks the squad (BaseHub.request "pick"); the host deploys (BaseHub.server_deploy)
##   briefing the clients say ready (Briefing.request_set_ready), the host starts it
##   advance  the host's bot walks toward the contract's objective, the others follow it
##   fight    everyone shoots at hostiles in sight (_server_fire, _server_reload); one player is
##           knocked out (_server_debug_hurt, a dev-tools request) and another treats them back
##           up (_server_treat with what care_needed() lists); in the first cycle bot 2 leaves
##           and joins again, and bot 3 joins late (tools/coop_soak.sh starts it once the
##           first deployment is under way)
##   items    each bot drops its helmet and picks it up again
##   extract  the host marks an extraction point where it stands, everyone gathers there, bot 1
##           confirms (Extraction.request_confirm), back to the base
##   debrief  every peer checks it got the debrief; the host closes it
## Cycles repeat until --soak-duration seconds have passed (at least two contracts), then the
## host posts "quit" and everyone leaves. Exit code 0 when the bot's own part ran through.

const Recorder := preload("res://tests/coop_soak_recorder.gd")

const SEED := 4711
## What the base's stash holds on top of the starting stash, so four players can kit up.
const EXTRA_STASH := [["assault_pack", 4], ["plate_ceramic_l4", 8], ["m4a1", 4], ["plate_carrier", 2], ["helmet", 4], ["mag_556", 24], ["ifak", 6], ["iv_18", 4],
	["saline_500", 6], ["epinephrine", 4], ["morphine", 4], ["tourniquet", 4],
	["npa", 4], ["io_kit", 4], ["pressure_bag", 3], ["hypothermia_blanket", 3], ["blood_500", 3]]  # the medic's consumables (S0736: its restock had no bag or blanket left)
## What each bot picks up at the armory: id -> how many it wants on it.
const KIT := {"assault_pack": 1, "ifak": 1, "iv_18": 1, "saline_500": 1, "epinephrine": 1, "plate_carrier": 1, "helmet": 1, "m4a1": 1, "mag_556": 3}
## The game's own paces (SoldierMovement.WALK_SPEED, SPRINT_SPEED).
const WALK_SPEED := 4.0
const RUN_SPEED := 6.5
## How long each phase may take at most (s).
const KIT_S := 75.0
const ADVANCE_S := 210.0
const FIGHT_S := 120.0
const ITEMS_S := 25.0
const EXTRACT_S := 150.0
## Engage hostiles this close (m), firing about this often (s).
const ENGAGE_M := 140.0
const SHOT_GAP_S := 0.28
## In the fight the host's bot (the others follow it) closes in on the nearest hostile when it
## has had no clear shot for HUNT_AFTER_S, stopping this far from it (m).
const HUNT_STOP_M := 45.0
const HUNT_AFTER_S := 4.0
## Fireteam (the Captain, after S0578: the bots stood in a 3 m clump, upright, walking at the
## hostiles): a wedge on the leader (the host's bot) with 8 m between bots; in contact the team
## bounds in pairs, one pair moving BOUND_M while the other holds and fires, swapping every
## BOUND_S; a bot that was just hit stops and gets down for PINNED_S.
const WEDGE := {1: Vector2(-8.0, 6.0), 2: Vector2(8.0, 6.0), 3: Vector2(-16.0, 12.0)}  # (right, back) m
const BOUND_S := 8.0
## Line abreast for the advance (the Captain): each bot's place right (+) or left of the
## leader, facing the objective; the squad's AI on the game's own line formation.
const LINE := {0: 0.0, 1: -9.0, 2: 9.0, 3: -18.0}
## Dead ground: looked for this far from the objective (m), the rim measured this far out,
## and only hostiles this close counted as watching (their sight is 200 m).
const DEAD_RING_M := Vector2(200.0, 450.0)
const DEAD_RIM_M := 35.0
const SIGHT_M := 250.0
const BOUND_M := 15.0
const PINNED_S := 4.0
## The knock-out (a dev-tools hurt, like the K key): enough to go down, and more if not.
const DOWN_DAMAGE := 70.0
## The medic bot keeps treating while there is something to do, and gives up only after
## MEDIC_IDLE_S with nothing it could do (B-01: a flat 150 s from the start cut off a medic that
## was still working); MEDIC_MAX_S caps the whole treatment. The same item on the same part is
## used at most SAME_CARE_MAX times (B-09: "npa on head" x42 in one go).
const MEDIC_IDLE_S := 150.0
const MEDIC_MAX_S := 420.0
const SAME_CARE_MAX := 2
## Bot 2 leaves this long into the first fight and comes back after RECONNECT_GAP_S.
const LEAVE_AT_S := 12.0
const RECONNECT_GAP_S := 20.0

var role := "host"
var bot := 0
var run_dir := ""
var duration_s := 600.0
var address := "127.0.0.1"
var expect_clients := 2
var reconnects := false
var late := false
## A real player plays along (tools/coop_soak.sh --human): the host waits for them before the
## first contract (up to wait_human_s) and waits for them at the extraction as long as it takes
## (up to HUMAN_EXTRACT_S); nothing here ever targets them (no planned knock-out, no give-up).
var human := false
## Bots join a human-hosted game (tools/coop_soak.sh --join): there is no bot host writing
## phase.json; each client runs its own phases (_join_phase): at the base it readies up, in a
## zone it follows the host's player (peer 1), readies up in the briefing, and never takes a
## contract or confirms an extraction (the human does). It quits at its duration, or when the
## host is gone for good.
var join := false
## Join mode: leaves the game (as at its duration) once this file exists (--soak-quit-file; the
## botsjoin suite's host says when its bot goes).
var quit_file := ""
var _join_level := 0
var _join_cycle := 0
var _join_ready_at := -INF
const JOIN_READY_GAP_S := 5.0
var wait_human_s := 600.0
const HUMAN_EXTRACT_S := 1200.0
## Time at the FOB between contracts once the human is back (the debrief, kitting up).
const HUMAN_BASE_S := 60.0
## With the FOB ready-up, how long the host waits for the human's Ready before going anyway.
const HUMAN_READY_S := 900.0
## With a human in (--human), the human leads each deployment: the bots keep a loose formation
## 10-25 m off them (FOLLOW: right, back in m, turned the way the human faces), fight what they
## see, treat them when they go down, board a vehicle or get in an extraction point with them.
## The host still takes the contract and runs the briefing (it waits for the human's "ready"),
## but there is no scripted advance, fight or extraction: the human decides. Gives up on a
## deployment after HUMAN_DEPLOY_S, or 60 s after the human left it.
const FOLLOW := {0: Vector2(-12.0, 8.0), 1: Vector2(10.0, 10.0), 2: Vector2(-5.0, 17.0), 3: Vector2(17.0, 18.0)}
const FOLLOW_NEAR_M := 10.0
const FOLLOW_FAR_M := 25.0
const HUMAN_DEPLOY_S := 7200.0

var recorder: Node
var level: CompoundLevel
var main: Node
var _t0 := 0.0
var _phase := {}          # the phase as posted (host) or last read (clients)
var _goal: Variant = null  # Vector3 the bot walks to, or null
var _goal_stop := 1.0
var _goal_speed := WALK_SPEED
var _fight := false
var _next_shot := 0.0
var _status := {}          # this bot's posted status
var _log: FileAccess
var _failures: Array[String] = []
var _cycle_log: FileAccess
var _rejoining := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = _arg(args, "--soak-role", "host")
	bot = int(_arg(args, "--soak-bot", "0"))
	run_dir = _arg(args, "--soak-run", ProjectSettings.globalize_path("user://coop_soak"))
	duration_s = float(_arg(args, "--soak-duration", "600"))
	address = _arg(args, "--soak-address", "127.0.0.1")
	expect_clients = int(_arg(args, "--soak-expect", "2"))
	reconnects = "--soak-reconnect" in args
	late = "--soak-late" in args
	human = "--soak-human" in args
	join = "--soak-join" in args
	quit_file = _arg(args, "--soak-quit-file", "")
	wait_human_s = float(_arg(args, "--soak-wait-human", "600"))
	_t0 = Recorder.now()
	var peer_dir := run_dir.path_join("host" if role == "host" else "client%d" % bot)
	DirAccess.make_dir_recursive_absolute(peer_dir)
	# The harness stops this process by its pid (tools/coop_soak.sh, taskkill) if it outlives the run.
	FileAccess.open(peer_dir.path_join("pid"), FileAccess.WRITE).store_string(str(OS.get_process_id()))
	_log = FileAccess.open(peer_dir.path_join("bot.log"), FileAccess.WRITE)
	# Never this PC's own settings (F-332): a bot can run beside a player's game on the same
	# machine (coop_soak.sh --join, the botsjoin suite in every local run). Each reads and saves a
	# settings file of its own in its run folder, at the defaults, shoots right-handed and keeps
	# the get-out key at its default whatever the player's settings.cfg says (a left-handed one
	# broke the pistol draw, CLAUDE.md); those two are pinned, never saved (animations_test does
	# the same).
	GameSettings.use_file(peer_dir.path_join("settings.cfg"))
	GameSettings.reset_all()
	Handedness._left = false
	Handedness._loaded = true
	ControlOptions._get_out = ControlOptions.GET_OUT_DEFAULT
	ControlOptions._loaded = true
	recorder = Recorder.new()
	recorder.name = "Recorder"
	recorder.out_dir = peer_dir
	recorder.bot = bot
	add_child(recorder)
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = "coop_soak" + tag  # never a real save
	GameState.zone_id = "coop_soak" + tag
	Contracts.auto_show_debrief = false
	BaseHub.local_profile = "soak_bot%d" % bot
	Roles.local_choice = [Roles.TEAM_LEADER, Roles.MEDIC, Roles.RIFLEMAN, Roles.AUTORIFLEMAN][clampi(bot, 0, 3)]
	# The whole run's hard deadline: nothing here may hang (the harness kills it too).
	get_tree().create_timer(duration_s + 1500.0, true, false, true).timeout.connect(func() -> void:
		_say("SOAK TIMED OUT")
		_finish(3))
	if role == "host":
		_host_main()
	else:
		_client_main()


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _say(text: String) -> void:
	var line := "[soak %s %.1f] %s" % ["host" if role == "host" else "bot%d" % bot, Recorder.now() - _t0, text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()
	if recorder:
		recorder.event(["note", text])


func _fail(text: String) -> void:
	_failures.append(text)
	_say("PROBLEM: " + text)


func _set_phase(ph: String, extra := {}) -> void:
	recorder.phase = "%d:%s" % [int(_phase.get("cycle", 0)), ph]
	if role != "host":
		return
	_phase["phase"] = ph
	_phase["t"] = Recorder.now()
	for k: String in extra:
		_phase[k] = extra[k]
	_write_json(run_dir.path_join("phase.json"), _phase)
	_say("phase %s %s" % [ph, JSON.stringify(extra) if not extra.is_empty() else ""])


static func _write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _post_status(extra: Dictionary) -> void:
	for k: String in extra:
		_status[k] = extra[k]
	_status["bot"] = bot
	_status["peer"] = multiplayer.get_unique_id() if _online() else 0
	_status["t"] = Recorder.now()
	_write_json(run_dir.path_join("bot%d.json" % bot), _status)


func _online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
		and (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().create_timer(0.1).timeout
	return true


## main.tscn goes in at /root/Main, where a player's build has it, so the host's node paths
## (RPCs, spawners) are the ones a real client has (S0745: the Captain's build joined a soak host
## whose world was at /root/CoopSoak/Main: "Node not found: CoopSoak/Main/Base/ItemSpawner",
## nothing replicated to him). Bots and a build can then share one session.
func _add_main(node: Node) -> void:
	node.name = "Main"
	get_tree().root.add_child.call_deferred(node)
	await get_tree().process_frame
	await get_tree().process_frame


func _level() -> CompoundLevel:
	level = CompoundLevel.current(self)
	return level


func _me() -> Soldier:
	var lvl := _level()
	if lvl == null or not multiplayer.has_multiplayer_peer() or (role != "host" and not _online()):
		return null
	var players := lvl.get_node_or_null(^"Players")
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if players else null


func _player(peer: int) -> Soldier:
	var lvl := _level()
	var players := lvl.get_node_or_null(^"Players") if lvl else null
	return players.get_node_or_null(str(peer)) as Soldier if players else null


func _in_base() -> bool:
	return _level() is BaseLevel


func _finish(code: int) -> void:
	_say("finished: exit %d, %d problem(s)%s" % [code, _failures.size(), (": " + "; ".join(_failures)) if not _failures.is_empty() else ""])
	_post_status({"finished": true, "problems": _failures})
	recorder.close()
	if _log:
		_log.flush()
	if _online():
		Net.leave()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(code)


# --- The host ---------------------------------------------------------------------------------

func _host_main() -> void:
	_cycle_log = FileAccess.open(run_dir.path_join("host").path_join("cycles.jsonl"), FileAccess.WRITE)
	_phase = {"cycle": 0, "phase": "starting", "quit": false}
	_set_phase("starting")
	Campaign.reset_campaign()
	# The campaign's own gear path (player_role_kits off: a player's gear is their main
	# character's, BaseHub._apply_player_gear). Each bot player gets its role's kit once, through
	# Roles.apply_kit, after BaseHub has put its saved gear on (_kit_players: at the start, a late
	# joiner, a rejoin). From the second contract the bots restock their last loadout from the
	# stash (BaseHub "restock", the base screen's button); the kit-up walk only tops up to KIT's
	# quantities. With player_role_kits on, the level's kit went on first and the saved gear then
	# replaced the whole inventory: a late joiner deployed with nothing (B-23).
	CompoundLevel.player_role_kits = false
	CompoundLevel.clean_loot = false
	CompoundLevel.spawn_ai = true
	BaseHub.new_campaign(SEED)
	for i in 4:
		var pool := Hiring.pool(BaseHub.hiring(), BaseHub.day())
		if pool.is_empty():
			break
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("wage", 0)) < int(b.get("wage", 0)))
		var why := BaseHub.server_hire(String(pool[0].cid))
		if why != "":
			_say("hiring: %s" % why)
	for pair: Array in EXTRA_STASH:
		BaseArmory.add(BaseHub.stash(), StringName(pair[0]), int(pair[1]))
	Campaign.save_campaign()
	main = load("res://scenes/main.tscn").instantiate()
	await _add_main(main)
	BaseHub.prepare_session()
	main.get_node(^"Menu").host()
	if not Net.is_hosting():
		_fail("could not host on port %d" % Net.port())
		_finish(2)
		return
	_say("hosting on port %d, roster %s" % [Net.port(), Roster.ids(BaseHub.roster())])
	await _wait_for(func() -> bool: return _me() != null and (_level() as BaseLevel) != null, 30.0)
	FileAccess.open(run_dir.path_join("host_ready"), FileAccess.WRITE).store_string(str(Net.port()))
	var joined := await _wait_for(func() -> bool: return multiplayer.get_peers().size() >= expect_clients, 120.0)
	_say("%d client(s) in (%s)%s" % [multiplayer.get_peers().size(), multiplayer.get_peers(), "" if joined else ": fewer than expected"])
	Net.peer_joined.connect(func(id: int) -> void: _say("peer %d joined" % id); recorder.event(["join", id]))

	if human:
		# The bots post their peer ids (bot<N>.json) just after joining; until every one has, a
		# bot not posted yet looks like the human (S0757: bot 2 was taken for him, and the
		# contract started without him).
		if not await _wait_for(func() -> bool: return _bots().size() >= expect_clients, 30.0):
			_say("only %d of %d bots posted their peer ids: a late one may be taken for the human" % [_bots().size(), expect_clients])
		_say("waiting up to %d s for the human player to join (port %d)" % [int(wait_human_s), Net.port()])
		var came := await _wait_for(func() -> bool: return not _humans().is_empty(), wait_human_s)
		_say("human player %s" % (("in: peer %s" % [_humans()]) if came else "not in yet: starting without them (they can join any time)"))
	Net.peer_left.connect(func(id: int) -> void: _say("peer %d left" % id); recorder.event(["leave", id]))
	var cycle := 0
	while true:
		cycle += 1
		_phase["cycle"] = cycle
		var started := Recorder.now()
		var result := await _host_cycle(cycle)
		result["cycle"] = cycle
		result["seconds"] = snappedf(Recorder.now() - started, 0.1)
		_cycle_log.store_line(JSON.stringify(result))
		_cycle_log.flush()
		_say("cycle %d: %s" % [cycle, JSON.stringify(result)])
		if not result.get("ok", false):
			_fail("cycle %d did not complete: %s" % [cycle, result.get("why", "?")])
			if not _in_base():
				break
		var elapsed := Recorder.now() - _t0
		var cycle_s := Recorder.now() - started
		if cycle >= 2 and elapsed + cycle_s * 0.8 > duration_s:
			break
		if cycle >= (40 if human else 12):
			break
		if human and not _humans().is_empty():
			# S0758: the host took the next contract at once, and the human was left on the
			# debrief in the old zone. Wait at the FOB until they're in it, then give them
			# time to read the debrief and kit up before the next contract.
			_say("back at the FOB: waiting for the human to arrive")
			await _wait_for(func() -> bool: return _in_base() and _human_lead() != 0, 600.0)
			if not BaseHub.has_method(&"server_set_ready"):
				_say("this build has no FOB ready-up: %d s before the next contract" % int(HUMAN_BASE_S))
				await _sleep(HUMAN_BASE_S)
	_set_phase("quit", {"quit": true})
	await _wait_for(func() -> bool: return multiplayer.get_peers().is_empty(), 30.0)
	_finish(0 if _failures.is_empty() else 1)


## Host, from the second contract on: what each player lost (gear stays on a body in the zone
## when a player dies and respawns; the armory doesn't refill) is put down in front of them,
## like a quartermaster, so every bot can kit up again by picking it up.
func _restock() -> void:
	var players := _level().get_node_or_null(^"Players") if _level() else null
	for node in (players.get_children() if players else []):
		var s := node as Soldier
		if s == null:
			continue
		var given := {}
		for id: String in KIT:
			var short := int(KIT[id]) - _owned(s, StringName(id))
			if short > 0:
				s._server_spawn_in_front(StringName(id), short)
				given[id] = short
		if not given.is_empty():
			_say("restock for %s: %s" % [s.name, JSON.stringify(given)])


## Host, before deploying: the FOB ready-up (feat/fob-ready-up, Captain 2026-10-14: deploy
## waits until every player is ready). The bots ready up at once; a human readies up with the
## Ready button on the squad page (up to HUMAN_READY_S, then the bots go without waiting).
## Builds from before the ready-up have nothing to wait for.
func _ready_up() -> void:
	if not BaseHub.has_method(&"server_set_ready"):
		return
	for n: int in _bots():
		BaseHub.call(&"server_set_ready", _bot_peer(n), true)
	if human and not _humans().is_empty() and not BaseHub.call(&"all_ready"):
		_say("FOB: waiting for the human to press Ready (up to %d s)" % int(HUMAN_READY_S))
		if not await _wait_for(func() -> bool: return BaseHub.call(&"all_ready"), HUMAN_READY_S):
			_say("FOB: still waiting for %s: deploying anyway would be refused, so marking them ready" % [BaseHub.call(&"not_ready_names")])
			for peer: int in _humans():
				BaseHub.call(&"server_set_ready", peer, true)


## Connected peers that are no bot of this harness (a real player who joined).
func _humans() -> Array:
	var bot_peers := _bots().values().map(func(st: Dictionary) -> int: return int(st.get("peer", 0)))
	return Array(multiplayer.get_peers()).filter(func(id: int) -> bool: return not id in bot_peers)


## Host: one line per player and friendly squad AI with what they wear (the Captain: are the
## plates on?): carrier, each plate pocket, helmet, pack, primary + optic. At each deployment
## and after each respawn (Net/level: a player's soldier came back).
func _log_kits(when: String) -> void:
	var lvl := _level()
	if lvl == null:
		return
	for holder: String in ["Players", "AI"]:
		var node := lvl.get_node_or_null(NodePath(holder))
		for c in (node.get_children() if node else []):
			var s := c as Soldier
			if s == null or s.faction != &"friendly" or s.vitals.is_dead():
				continue
			_say("[kit] %s %s: %s" % [_kit_name(s), String(s.role).replace("_", " "), _kit_line(s)])


func _kit_name(s: Soldier) -> String:
	if not s.is_ai():
		var peer := int(String(s.name)) if String(s.name).is_valid_int() else 0
		if peer == 1:
			return "Host (bot 0)"
		for n: int in _bots():
			if int(_bots()[n].get("peer", 0)) == peer:
				return "Bot %d" % n
		return "Player %s" % s.name
	return s.display_name()


static func _kit_line(s: Soldier) -> String:
	var slots: Dictionary = s.inventory.slots
	var parts: Array[String] = []
	parts.append(String(slots.get(&"vest", &"")) if slots.get(&"vest", &"") != &"" else "NO CARRIER")
	for pocket: StringName in Inventory.PLATE_SLOTS:
		var pname: String = {&"plate_front": "front", &"plate_back": "rear", &"plate_left": "left", &"plate_right": "right"}[pocket]
		parts.append("%s=%s" % [pname, String(slots.get(pocket, &"")) if slots.get(pocket, &"") != &"" else "-"])
	parts.append("helmet=%s" % (String(slots.get(&"helmet", &"")) if slots.get(&"helmet", &"") != &"" else "-"))
	parts.append("pack=%s" % (String(slots.get(&"backpack", &"")) if slots.get(&"backpack", &"") != &"" else "-"))
	var optic := GunSight.optic_of(s)
	parts.append("%s%s" % [String(slots.get(&"primary", &"")) if slots.get(&"primary", &"") != &"" else "no primary", ("+" + String(optic.id)) if optic else ""])
	return " ".join(parts)


## Every connected client's posted status, by bot number.
func _bots() -> Dictionary:
	var out := {}
	for n in range(1, 4):
		var s := _read_json(run_dir.path_join("bot%d.json" % n))
		if not s.is_empty() and int(s.get("peer", 0)) in multiplayer.get_peers():
			out[n] = s
	return out


func _bot_peer(n: int) -> int:
	return int(_bots().get(n, {}).get("peer", 0))


func _host_cycle(cycle: int) -> Dictionary:
	var result := {"ok": false}
	if not await _wait_for(_in_base, 40.0):
		result.why = "not at the base"
		return result
	# Kit up.
	_set_phase("kit", {"down": {}, "cid": "", "pick": [], "rally": [], "spawn": [], "facing": 0.0})
	await _kit_up(cycle)
	await _wait_for(func() -> bool: return _bots().values().all(func(s: Dictionary) -> bool: return int(s.get("kit", 0)) >= cycle), KIT_S)
	result["kit"] = {"host": _kit_summary(_me())}
	for n: int in _bots():
		result.kit["bot%d" % n] = _bots()[n].get("kit_summary", {})
	# The contract: bot 1 accepts it, bot 2 picks the squad.
	var offer := _pick_offer()
	if offer.is_empty():
		result.why = "no contract on the board"
		return result
	var cid := String(offer.cid)
	_set_phase("contract", {"cid": cid})
	var accepted_by := "bot1"
	if _bot_peer(1) == 0 or not await _wait_for(func() -> bool: return not Contracts.contract(cid).is_empty() and Contracts.held().any(func(c: Dictionary) -> bool: return c.cid == cid), 15.0):
		accepted_by = "host"
		var why := Contracts.server_accept(cid, ContractGen.default_terms())
		if why != "":
			result.why = "accepting: %s" % why
			return result
	result["contract"] = {"cid": cid, "title": String(offer.get("title", "")), "type": String(offer.get("type", "")), "zone": String(offer.get("zone_id", "")), "accepted_by": accepted_by}
	await _sleep(1.0)
	var squad: Array = Roster.available_ids(BaseHub.roster()).slice(0, 2)
	for mid: String in (BaseHub._prep().squad as Array).duplicate():
		BaseHub.server_pick(mid, false)  # the prep may come with a squad: bot 2 picks it again
	_set_phase("pick", {"pick": squad})
	var picked_by := "bot2"
	if _bot_peer(2) == 0 or not await _wait_for(func() -> bool: return squad.all(func(mid: String) -> bool: return mid in BaseHub._prep().squad), 15.0):
		picked_by = "host"
		for mid: String in squad:
			BaseHub.server_pick(mid, true)
	result.contract["squad"] = squad
	result.contract["picked_by"] = picked_by
	await _ready_up()
	var why_deploy := BaseHub.server_deploy()
	if why_deploy != "":
		result.why = "deploy: %s" % why_deploy
		return result
	_set_phase("deploying")
	if not await _wait_for(func() -> bool: return _level() != null and not _in_base() and _me() != null, 60.0):
		result.why = "the session never reached the zone"
		return result
	var briefing := MapNodes.briefing(_level())
	await _wait_for(func() -> bool: return briefing != null and briefing.is_open(), 20.0)
	_set_phase("briefing")
	if briefing:
		_pick_insertion(briefing)
	if briefing:
		briefing.server_set_ready(1, true)
	var ready_wait := 25.0
	if human and not _humans().is_empty():
		ready_wait = wait_human_s  # the human says when to go
		_say("briefing: waiting up to %d s for the human to say ready" % int(ready_wait))
	var all_ready := await _wait_for(func() -> bool: return briefing != null and briefing.all_ready(), ready_wait)
	if briefing:
		briefing.server_start(true)
	result["briefing"] = {"all_ready": all_ready}
	await _wait_for(Contracts.is_deployed, 10.0)
	if not Contracts.is_deployed():
		result.why = "the contract never went live"
		return result
	await _sleep(3.0)  # the garrisons come out over a few frames
	if human and _human_lead() != 0:
		return await _host_follow_human(result)
	var target: Variant = _objective_point()
	result["objective"] = Recorder._v3(target) if target != null else null
	# Start in dead ground out of the hostiles' sight (Captain: the insertion put the team in
	# the open 50 m from the village, in contact at once), facing the objective.
	_report_insertions(target)
	var start := _dead_ground(target) if target != null else {}
	var deployed := {"zone": String(Contracts.deployment().get("zone_id", ""))}
	if not start.is_empty():
		var at: Vector3 = start.pos
		var to_obj := Vector3((target as Vector3).x - at.x, 0.0, (target as Vector3).z - at.z).normalized()
		deployed["spawn"] = [at.x, at.y, at.z]
		deployed["facing"] = atan2(-to_obj.x, -to_obj.z)
		result["start"] = {"pos": Recorder._v3(at), "score": start.score, "rim": start.rim, "hidden": start.hidden,
			"dist": start.dist, "nearest_hostile": start.nearest_hostile}
		recorder.event(["spawn_point", snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1), start.score])
	_set_phase("deployed", deployed)
	if deployed.has("spawn"):
		_go_to_start()
		_line_up_squad()
	await _sleep(4.0)
	_log_kits("deploy")
	# Advance toward the objective: in line, at a walk.
	_set_phase("advance")
	var me := _me()
	if target != null and me:
		_walk(target, 40.0, WALK_SPEED)
		await _wait_for(func() -> bool: return _me() == null or _flat(_me().global_position, target) < 70.0 or _hostile_in_range(_me(), HUNT_STOP_M * 2.0) != null, ADVANCE_S)
	# Fight, with a knock-out and a revive.
	_fight = true
	_set_phase("fight")
	var fight_start := Recorder.now()
	await _sleep(15.0)
	var victim_bot := 1 if cycle % 2 == 1 else 0
	var medic_bot := 0 if victim_bot == 1 else 1
	if _bot_peer(1) == 0:
		victim_bot = 0
		medic_bot = 2 if _bot_peer(2) != 0 else (3 if _bot_peer(3) != 0 else -1)
	var victim_peer := 1 if victim_bot == 0 else _bot_peer(victim_bot)
	var medic_peer := 1 if medic_bot == 0 else (_bot_peer(medic_bot) if medic_bot > 0 else 0)
	_set_phase("fight", {"down": {"victim": victim_peer, "medic": medic_peer, "victim_bot": victim_bot, "medic_bot": medic_bot}})
	var revive := await _down_and_revive(victim_peer, medic_peer)
	result["revive"] = revive
	var left := FIGHT_S - (Recorder.now() - fight_start)
	if left > 0.0:
		await _sleep(left)
	_fight = false
	_stop_fighting()
	# Items.
	_set_phase("items", {"down": {}})
	await _drop_and_pick_up()
	await _sleep(maxf(ITEMS_S - 8.0, 2.0))
	# Extract where the host stands.
	me = _me()
	var extraction := MapNodes.extraction(_level())
	if me == null or extraction == null or not extraction.is_active():
		result.why = "no extraction to call (%s)" % ("no player" if me == null else "extraction not active")
		return result
	var at := me.global_position
	_goal = null
	extraction.server_add_point(Vector2(at.x, at.z))
	_set_phase("extract", {"rally": [at.x, at.y, at.z]})
	# Long enough for a player who respawned at the insertion (~1 km) to come back on foot.
	var gathered := await _wait_for(func() -> bool: return not extraction.point_with_squad().is_empty(), HUMAN_EXTRACT_S if human and not _humans().is_empty() else 300.0)
	var left_behind: Array = []
	if not gathered:
		var point := extraction._nearest_point()
		for mate: Soldier in extraction.required().ai:
			if not Extraction.inside(point, mate.body_point()):
				extraction.server_set_bring(String(mate.name), false)
				left_behind.append(String(mate.name))
		gathered = await _wait_for(func() -> bool: return not extraction.point_with_squad().is_empty(), 45.0)
	if not gathered:
		# S0736: the team was wiped near the objective, everyone gave up and respawned at the
		# insertion, far from the rally point, after the wait above ran out. Gather again where
		# the team now is: once every player is up, a new point where the host stands.
		var all_up := await _wait_for(func() -> bool:
			var ps := _level().get_node_or_null(^"Players") if _level() else null
			return ps != null and ps.get_children().all(func(p: Node) -> bool: return not (p is Soldier) or (p as Soldier).vitals.is_up()), 180.0)
		me = _me()
		if all_up and me != null and extraction.is_active():
			var again := me.global_position
			extraction.server_add_point(Vector2(again.x, again.z))
			_set_phase("extract", {"rally": [again.x, again.y, again.z]})
			_say("gathering again at %s (everyone up again after a wipe)" % Recorder._v3(again))
			gathered = await _wait_for(func() -> bool: return not extraction.point_with_squad().is_empty(), 150.0)
			left_behind.append("(regathered %s)" % ("ok" if gathered else "failed"))
	result["extract"] = {"gathered": gathered, "left_behind": left_behind, "missing": Array(extraction.missing_at(extraction._nearest_point())) if not gathered else []}
	if human and _human_lead() != 0 and not _in_base():
		# S0755: the human joined mid-contract; the scripted run went on to confirm without
		# them (refused, then the run quit). The bots never extract without the human
		# (Captain, 2026-10-14): from here the human leads, as if they'd been in from the start.
		_say("the human is in the zone: they lead the rest of this contract")
		return await _host_follow_human(result)
	var confirmed_by := "bot1"
	_set_phase("confirm")
	if _bot_peer(1) == 0 or not await _wait_for(func() -> bool: return extraction.state == Extraction.State.COUNTDOWN or _in_base(), 8.0):
		confirmed_by = "host"
		var tries := 0
		while not _in_base() and extraction.state != Extraction.State.COUNTDOWN and tries < 20:
			var why := extraction.server_confirm()
			if why == "":
				break
			tries += 1
			await _sleep(3.0)
	result.extract["confirmed_by"] = confirmed_by
	var serial_before := int(Contracts.last_debrief().get("serial", 0))
	if not await _wait_for(_in_base, 60.0):
		result.why = "never got back to the base (extraction state %d)" % extraction.state
		return result
	return await _host_debrief(result, serial_before)


## Host: back at the base after a deployment: every peer gets the debrief, the host closes it.
func _host_debrief(result: Dictionary, serial_before: int) -> Dictionary:
	await _wait_for(func() -> bool: return int(Contracts.last_debrief().get("serial", 0)) > serial_before, 10.0)
	var debrief := Contracts.last_debrief()
	_set_phase("debrief", {"debrief": int(debrief.get("serial", 0))})
	var serial := int(debrief.get("serial", 0))
	await _wait_for(func() -> bool: return _bots().values().all(func(s: Dictionary) -> bool: return int(s.get("debrief", 0)) >= serial), 15.0)
	var seen := {}
	for n: int in _bots():
		seen["bot%d" % n] = int(_bots()[n].get("debrief", 0)) >= serial
	var lines: Array = debrief.get("contracts", [])
	result["debrief"] = {"serial": serial, "outcome": String(lines[0].get("outcome", "")) if not lines.is_empty() else "", "seen": seen,
		"extracted": debrief.get("extracted", [])}
	Contracts.finish_debrief()
	await _sleep(3.0)
	result.ok = true
	return result


## The human the bots follow (--human): the first connected peer that is no bot and has a
## soldier in the level; 0 if none.
func _human_lead() -> int:
	for peer: int in _humans():
		if _player(peer) != null:
			return peer
	return 0


## Host, --human with a human in: the human leads the deployment (FOLLOW). Waits until the
## session is back at the base (the human extracted), then the debrief as usual.
func _host_follow_human(result: Dictionary) -> Dictionary:
	var lead := _human_lead()
	var serial_before := int(Contracts.last_debrief().get("serial", 0))
	_set_phase("follow", {"leader": lead, "down": {}})
	_say("the human (peer %d) leads: the bots keep %d-%d m off them, fight what they see, treat them, board and extract with them" % [lead, int(FOLLOW_NEAR_M), int(FOLLOW_FAR_M)])
	_fight = true
	var started := Recorder.now()
	var gone_since := -1.0
	var note_at := 0.0
	# The zone's preset extraction points (one may lie on the insertion): only a point the human
	# calls, or a preset one they come back to after going out, means "extract now".
	var extraction := MapNodes.extraction(_level())
	_preset_points = extraction.points.map(func(p: Dictionary) -> int: return int(p.get("id", -1))) if extraction else []
	_human_start = _player(lead).global_position if _player(lead) else Vector3.ZERO
	_human_went_out = false
	_human_in_point_since = -1.0
	while not _in_base() and Recorder.now() - started < HUMAN_DEPLOY_S:
		await _sleep(0.25)
		var now_lead := _human_lead()
		if now_lead == 0:
			if gone_since < 0.0:
				gone_since = Recorder.now()
				_say("the human is not in the deployment: waiting 60 s for them")
			if Recorder.now() - gone_since > 60.0:
				break
			continue
		gone_since = -1.0
		if now_lead != int(_phase.get("leader", 0)):
			_set_phase("follow", {"leader": now_lead})
		if _me() != null and _me().vitals.is_up():
			_stuck_note(_me(), now_lead)  # the host bot can be wedged too (soak-stuck-bots)
		_follow_tick(_me(), now_lead)
		_extract_with_human(now_lead)
		if Recorder.now() >= note_at:
			note_at = Recorder.now() + 30.0
			_say("follow: %s" % _follow_note(now_lead))
	_fight = false
	_stop_fighting()
	result["follow"] = {"seconds": snappedf(Recorder.now() - started, 0.1), "human": lead}
	if not await _wait_for(_in_base, 60.0):
		result.why = "the human never extracted (%s)" % ("left the deployment" if _human_lead() == 0 else "%d s passed" % int(HUMAN_DEPLOY_S))
		return result
	return await _host_debrief(result, serial_before)


## Host: how far each bot is from the human, for the log ("host 14 m, bot1 19 m (down)").
func _follow_note(lead: int) -> String:
	var human_s := _player(lead)
	if human_s == null:
		return "no human"
	var parts: Array[String] = []
	var peers := {"host": 1}
	for n: int in _bots():
		peers["bot%d" % n] = int(_bots()[n].get("peer", 0))
	for who: String in peers:
		var s := _player(int(peers[who]))
		if s == null:
			continue
		var state := "" if s.vitals.is_up() else (" (dead)" if s.vitals.is_dead() else " (down)")
		if Vehicle.ride_of(s) != null:
			state += " (in %s)" % Vehicle.ride_of(s).name
		parts.append("%s %.0f m%s" % [who, _flat(s.global_position, human_s.global_position), state])
	return "human %s%s; %s" % ["up" if human_s.vitals.is_up() else human_s.vitals.condition_text(),
		(" in %s" % Vehicle.ride_of(human_s).name) if Vehicle.ride_of(human_s) != null else "", ", ".join(parts)]


## Every bot (host's and clients'), with a human leading: keep a loose place 10-25 m off the
## leader; in contact hold and fight; get in the leader's vehicle, or out with them; get inside
## the extraction point the leader stands in.
func _follow_tick(me: Soldier, leader_peer: int) -> void:
	if me == null or not me.vitals.is_up() or _treating or _dropping or _casevac != "":
		return
	var leader := _player(leader_peer)
	if leader == null:
		return
	var ride := Vehicle.ride_of(leader)
	var mine := Vehicle.ride_of(me)
	var now := Recorder.now()
	if ride != null:
		if mine == ride:
			_goal = null
			return
		if mine != null:
			if now >= _board_next:
				_board_next = now + 2.0
				mine.request_exit.rpc_id(1)
			return
		var door := _door_of(ride, me)
		if me.global_position.distance_to(door) > 3.0:
			_walk(door, 1.0, RUN_SPEED)
		elif now >= _board_next:
			_board_next = now + 2.0
			_goal = null
			_say("boarding %s with the human" % ride.name)
			ride.request_enter.rpc_id(1, -1)
		return
	if mine != null:
		if now >= _board_next:
			_board_next = now + 2.0
			_say("getting out of %s with the human" % mine.name)
			mine.request_exit.rpc_id(1)
		return
	var extraction := MapNodes.extraction(_level()) if _level() else null
	if extraction and extraction.is_active():
		for point: Dictionary in extraction.points:
			if Extraction.inside(point, leader.global_position):
				var p: Vector2 = point.pos
				var r := float(point.get("radius", Extraction.RADIUS_M)) * 0.4
				var a := TAU * float(bot) / 4.0 + 0.4
				var in_point := Vector3(p.x + cos(a) * r, me.global_position.y, p.y + sin(a) * r)
				if _flat(me.global_position, in_point) > 1.5:
					_walk(in_point, 1.0, RUN_SPEED)
				return
	var to_leader := _flat(me.global_position, leader.global_position)
	var spot := _follow_spot(leader)
	if _in_contact(me) and to_leader <= FOLLOW_FAR_M:
		_goal = null  # in contact: hold and fight
	elif to_leader > FOLLOW_FAR_M or to_leader < FOLLOW_NEAR_M * 0.6 or _flat(me.global_position, spot) > 8.0:
		_walk(spot, 2.0, RUN_SPEED if to_leader > FOLLOW_FAR_M + 10.0 else WALK_SPEED)


var _stuck_at := Vector3.INF
var _stuck_since := 0.0
var _stuck_said := 0.0


## S0758: both bots stood still, up and unhurt, 400 m behind the human for 20 minutes with
## nothing in their logs. Far from the leader and not moving for 15 s: say what holds them.
func _stuck_note(me: Soldier, leader_peer: int) -> void:
	var leader := _player(leader_peer)
	var now := Recorder.now()
	if leader == null or _flat(me.global_position, leader.global_position) <= FOLLOW_FAR_M or _flat(me.global_position, _stuck_at) > 1.0:
		_stuck_at = me.global_position
		_stuck_since = now
		return
	if now - _stuck_since < 15.0 or now - _stuck_said < 30.0:
		return
	_stuck_said = now
	_say("stuck %.0f s, %.0f m from the leader at %s: goal %s, treating %s, dropping %s, casevac '%s', pinned %s, fight %s, contact %s, vehicle %s, hands '%s', carry '%s'" % [
		now - _stuck_since, _flat(me.global_position, leader.global_position), Recorder._v3(me.global_position),
		Recorder._v3(_goal) if _goal != null else "none", _treating, _dropping, _casevac, Soldier._now() < _pinned_until, _fight,
		_in_contact(me), is_instance_valid(me.vehicle), me.inventory.hands, me.carry_mode])


var _board_next := 0.0
var _human_in_point_since := -1.0
var _confirm_next := 0.0
var _preset_points: Array = []  # extraction point ids there at the deployment's start
var _human_start := Vector3.ZERO
var _human_went_out := false     # the human went HUMAN_OUT_M from where they started
const HUMAN_OUT_M := 150.0


## Host, a human leading: only the host may confirm an extraction (Extraction._server_confirm),
## so when the human stands in an extraction point and every player is in it too, the host
## confirms it for them (S0751: the human called a point, everyone was in it, nothing happened).
## Squad AI still out of the point after 90 s is left behind, as a squad leader would decide.
func _extract_with_human(lead: int) -> void:
	var extraction := MapNodes.extraction(_level()) if _level() else null
	var h := _player(lead)
	if extraction == null or h == null or extraction.state != Extraction.State.ACTIVE:
		_human_in_point_since = -1.0
		return
	if not _human_went_out and _flat(h.global_position, _human_start) > HUMAN_OUT_M:
		_human_went_out = true
	var point := {}
	for p: Dictionary in extraction.points:
		if Extraction.inside(p, h.global_position):
			point = p
			break
	if point.is_empty():
		_human_in_point_since = -1.0
		return
	var now := Recorder.now()
	var called := not int(point.get("id", -1)) in _preset_points
	if not called and not _human_went_out:
		_human_in_point_since = -1.0
		return  # a preset point at the insertion they haven't left yet: not an extraction call (S0752)
	if _human_in_point_since < 0.0:
		_human_in_point_since = now
		_say("the human is in extraction point %s (%s): the bots get in, the host confirms once everyone is in" % [point.get("name", "?"),
			"called by them" if called else "a preset point, back from %.0f m out" % HUMAN_OUT_M])
	if now < _confirm_next:
		return
	_confirm_next = now + 3.0
	var missing := extraction.missing_at(point)
	if missing.is_empty() and now - _human_in_point_since > (5.0 if called else 20.0):
		var why := extraction.server_confirm()
		_say("extraction confirmed for the human" if why == "" else "extraction not confirmed: %s" % why)
	elif not missing.is_empty() and now - _human_in_point_since > 90.0:
		for mate: Soldier in extraction.required().ai:
			if not Extraction.inside(point, mate.body_point()):
				extraction.server_set_bring(String(mate.name), false)
				_say("left %s behind (not at the extraction point after 90 s)" % mate.name)


## This bot's loose place off `leader` (FOLLOW), turned the way the leader faces.
func _follow_spot(leader: Soldier) -> Vector3:
	var o: Vector2 = FOLLOW.get(bot, Vector2(0.0, 15.0))
	var yaw := leader.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return leader.global_position + right * o.x - fwd * o.y


## Where `me` gets in `v`: its nearest door or hatch (an action point that is no seat).
static func _door_of(v: Vehicle, me: Soldier) -> Vector3:
	var best := v.global_position
	var best_d := INF
	for p in v.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind != VehicleActionPoint.SEAT:
			var d := me.global_position.distance_to((p as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = (p as Node3D).global_position
	return best


## A peer of this harness's bots (the host's or a client's), from the posted statuses: works on
## clients too (they see only the host as a peer).
func _is_bot_peer(peer: int) -> bool:
	if peer == 1:
		return true
	for n in range(1, 4):
		if int(_read_json(run_dir.path_join("bot%d.json" % n)).get("peer", 0)) == peer:
			return true
	return false


## The insertion point on foot nearest the contract's first objective (what a squad picks on
## the briefing map), so the walk in is short and the fight comes soon.
func _pick_insertion(briefing: Briefing) -> void:
	var objs := briefing.map_objectives()
	if objs.is_empty():
		return
	var target: Vector2 = objs[0].pos
	var best := ""
	var best_d := INF
	for point: Dictionary in briefing.insertion_points():
		var p: Array = point.get("pos", [])
		if p.size() < 2 or String(point.get("method", "foot")) != "foot":
			continue
		var d := Vector2(float(p[0]), float(p[1])).distance_to(target)
		if d < best_d:
			best_d = d
			best = String(point.get("id", ""))
	if best != "" and briefing.server_set_insertion(best):
		_say("insertion %s, %.0f m from the objective" % [best, best_d])


## Host: every insertion point of this zone, how far from the objective and the nearest
## hostile, and whether it is in dead ground (the Captain asked whether the real ones are).
func _report_insertions(target: Variant) -> void:
	var briefing := MapNodes.briefing(_level())
	if briefing == null or target == null:
		return
	var posts := _hostile_posts()
	for point: Dictionary in briefing.insertion_points():
		var p: Array = point.get("pos", [])
		if p.size() < 2:
			continue
		var at := Vector3(float(p[0]), 0.0, float(p[1]))
		at.y = _ground_h(at)
		var near := INF
		var watching: Array[Vector3] = []
		for q: Vector3 in posts:
			near = minf(near, _flat(at, q))
			if _flat(at, q) < SIGHT_M:
				watching.append(q)
		_say("insertion %s (%s): %.0f m from the objective, nearest hostile %.0f m, %d hostiles within %d m, hidden from %d%% of them, rim %+.1f m" % [
			point.get("id", "?"), point.get("method", "foot"), _flat(at, target), near, watching.size(), int(SIGHT_M),
			int(_hidden_fraction(at, watching) * 100.0), _rim(at)])


## Where the hostiles watch from: every module's garrison posts (ZoneModules.GARRISON, as many
## as the module's garrison; a garrison comes out only once players are near, so the soldiers
## alone would leave most of them out), and every hostile soldier up in the level.
func _hostile_posts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var zone := _level() as ZoneLevel
	if zone:
		for m: ZoneModule in zone.modules():
			if not m.is_inside_tree():
				continue
			var spots: Array = ZoneModules.GARRISON.get(m.type, [])
			for i in mini(zone.garrison_size(m.module_id), spots.size()):
				out.append(m.to_global(spots[i]))
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_queued_for_deletion():
			out.append(s.global_position)
	return out


func _ground_h(at: Vector3) -> float:
	var lvl := _level()
	return lvl.ground_point(at).y - 0.1 if lvl else at.y


## How far the ground around `at` (DEAD_RIM_M out, 8 ways) rises above it at the lowest:
## positive means a basin, rimmed on every side.
func _rim(at: Vector3) -> float:
	var lowest := INF
	for k in 8:
		var a := TAU * k / 8.0
		lowest = minf(lowest, _ground_h(at + Vector3(cos(a), 0.0, sin(a)) * DEAD_RIM_M) - at.y)
	return lowest


## The share of `posts` that can't see a man standing at `at` (eye to eye, 1.7 m, over the
## terrain's heights; buildings and trees aren't counted, so this is the ground's cover only).
func _hidden_fraction(at: Vector3, posts: Array[Vector3]) -> float:
	if posts.is_empty():
		return 1.0
	var hidden := 0
	var eye := at + Vector3.UP * 1.7
	for q: Vector3 in posts:
		var other := q + Vector3.UP * 1.7
		var steps := clampi(int(_flat(at, q) / 8.0), 4, 80)
		for i in range(1, steps):
			var p := eye.lerp(other, float(i) / steps)
			if _ground_h(p) > p.y:
				hidden += 1
				break
	return float(hidden) / posts.size()


## Host: the best dead ground in a ring DEAD_RING_M around the objective: low (a basin with a
## rim on every side), hidden from the hostiles within sight (SIGHT_M), about 325 m out, never
## within 150 m of a hostile. {"pos", "score", "rim", "hidden", "dist", ...}, or {} off a zone.
func _dead_ground(target: Vector3) -> Dictionary:
	if not (_level() is ZoneLevel):
		return {}
	var posts := _hostile_posts()
	# Well inside the map: S0672/S0697 picked points at or past the zone's edge (no ground
	# there), and the bots and squad AI put there fell out of the world.
	var inside := (_level() as ZoneLevel).map_area().grow(-80.0)
	var best := {}
	var r := DEAD_RING_M.x
	while r <= DEAD_RING_M.y:
		for k in 48:
			var a := TAU * k / 48.0
			var at := target + Vector3(cos(a), 0.0, sin(a)) * r
			if not inside.has_point(Vector2(at.x, at.z)):
				continue
			at.y = _ground_h(at)
			var near: Array[Vector3] = []
			var nearest := INF
			for q: Vector3 in posts:
				var d := _flat(at, q)
				nearest = minf(nearest, d)
				if d < SIGHT_M:
					near.append(q)
			if nearest < 150.0:
				continue
			var rim := _rim(at)
			var hidden := _hidden_fraction(at, near)
			var score := hidden * 10.0 + clampf(rim, -3.0, 6.0) - absf(r - 325.0) / 100.0 + minf(nearest, 400.0) / 200.0
			if best.is_empty() or score > float(best.score):
				best = {"pos": at, "score": snappedf(score, 0.01), "rim": snappedf(rim, 0.1), "hidden": snappedf(hidden, 0.01),
					"dist": snappedf(r, 1.0), "nearest_hostile": snappedf(nearest, 1.0), "watching": near.size()}
		r += 25.0
	if not best.is_empty():
		_say("start in dead ground at %s: score %.2f, rim %+.1f m, hidden from %d%% of the %d hostiles within %d m, %.0f m from the objective, nearest hostile %.0f m" % [
			Recorder._v3(best.pos), best.score, best.rim, int(float(best.hidden) * 100.0), best.watching, int(SIGHT_M), best.dist, best.nearest_hostile])
	return best


## Every bot: to its place in the line at the posted start, facing the objective.
func _go_to_start() -> void:
	var me := _me()
	var spot: Variant = _line_spot_at_start()
	if me == null or spot == null:
		return
	_goal = null
	me.global_position = _level().ground_point(spot)
	me.rotation.y = float(_phase.get("facing", 0.0))
	_say("at the start, in line")


func _line_spot_at_start() -> Variant:
	var sp: Array = _phase.get("spawn", [])
	if sp.size() != 3:
		return null
	return Vector3(float(sp[0]), float(sp[1]), float(sp[2])) + _line_right() * float(LINE.get(bot, 0.0))


## Right of the line (the line faces the objective).
func _line_right() -> Vector3:
	var yaw := float(_phase.get("facing", 0.0))
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Host: the squad's AI to the start too, beside the bots, and on the line formation.
func _line_up_squad() -> void:
	var me := _me()
	var lvl := _level()
	if me == null or lvl == null:
		return
	var sp: Array = _phase.get("spawn", [])
	var ai := lvl.get_node_or_null(^"AI")
	var n := 0
	for node in (ai.get_children() if ai else []):
		var s := node as Soldier
		if s and s.faction == &"friendly" and s.vitals.is_up():
			var side := 1.0 if n % 2 == 0 else -1.0
			var at := Vector3(float(sp[0]), float(sp[1]), float(sp[2])) + _line_right() * side * (18.0 + 9.0 * floorf(n / 2.0))
			s.global_position = lvl.ground_point(at)
			s.rotation.y = float(_phase.get("facing", 0.0))
			n += 1
	me._server_squad_command.rpc_id(1, "formation:line", me.global_position, PackedStringArray())
	me._server_squad_command.rpc_id(1, "follow", me.global_position, PackedStringArray())


func _pick_offer() -> Dictionary:
	var offers := Contracts.board().filter(func(c: Dictionary) -> bool: return c.get("zone_kind", "") == "contract" and String(c.get("recover_mid", "")) == "")
	if offers.is_empty():
		Contracts.server_refresh_board()
		offers = Contracts.board().filter(func(c: Dictionary) -> bool: return c.get("zone_kind", "") == "contract" and String(c.get("recover_mid", "")) == "")
	for c: Dictionary in offers:
		if String(c.get("type", "")) == "clear_compound":
			return c
	return offers[0] if not offers.is_empty() else {}


func _objective_point() -> Variant:
	for m: Dictionary in Contracts.objectives.markers():
		if m.state == Objectives.ACTIVE and not m.optional and (m.pos as Vector3) != Vector3.ZERO:
			return m.pos
	var me := _me()
	var best: Soldier = _hostile_in_range(me, 5000.0) if me else null
	return best.global_position if best else null


## Host: `victim_peer` knocks itself out (its own machine sends the hurt), `medic_peer` treats
## them back up. Both are told through the phase; the host watches from the replicated state.
func _down_and_revive(victim_peer: int, medic_peer: int) -> Dictionary:
	var out := {"victim": victim_peer, "medic": medic_peer}
	if victim_peer == 1:
		_down_self()
	if medic_peer == 1:
		_treat_loop(victim_peer)
	var victim := _player(victim_peer)
	var went_down := await _wait_for(func() -> bool: return _player(victim_peer) != null and _player(victim_peer).vitals.downed, 25.0)
	out["went_down"] = went_down
	if not went_down:
		return out
	var t := Recorder.now()
	await _wait_for(func() -> bool:
		var v := _player(victim_peer)
		return v == null or v.vitals.is_up() or v.vitals.is_dead() or _medic_done(medic_peer, t), MEDIC_MAX_S + 30.0)
	victim = _player(victim_peer)
	out["up"] = victim != null and victim.vitals.is_up()
	out["dead"] = victim != null and victim.vitals.is_dead()
	out["seconds"] = snappedf(Recorder.now() - t, 0.1)
	if victim and not victim.vitals.is_up() and not victim.vitals.is_dead():
		out["still_down"] = victim.vitals.condition_text()
		out["why_unconscious"] = Array(victim.vitals.why_unconscious())
	return out


## Host: the medic's treatment loop has ended since `since` (it gave up, or the casualty is up).
func _medic_done(medic_peer: int, since: float) -> bool:
	if medic_peer == 1:
		return not _treating and Recorder.now() - since > 2.0
	for n: int in _bots():
		var st: Dictionary = _bots()[n]
		if int(st.get("peer", 0)) == medic_peer:
			return float(st.get("treat_end", 0.0)) > since
	return medic_peer == 0 and Recorder.now() - since > MEDIC_IDLE_S  # no medic at all


func _drop_and_pick_up() -> void:
	var me := _me()
	if me == null or not me.vitals.is_up():
		return
	_dropping = true  # the follow tick leaves this bot alone meanwhile (B-07: it never was set)
	await _drop_and_pick_up_inner(me)
	_dropping = false


func _drop_and_pick_up_inner(me: Soldier) -> void:
	var slot := &"helmet" if me.inventory.slots.get(&"helmet", &"") != &"" else &""
	if slot == &"":
		return
	var id: StringName = me.inventory.slots[slot]
	me._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, slot, &"")
	if not await _wait_for(func() -> bool: return _me() != null and _me().inventory.slots.get(slot, &"") == &"", 5.0):
		_fail("dropping the %s never showed" % id)
		return
	var item: WorldItem = null
	var deadline := Time.get_ticks_msec() + 5000
	while item == null and Time.get_ticks_msec() < deadline:
		item = _nearest_item(id, 4.0)
		await get_tree().create_timer(0.1).timeout
	if item == null:
		_fail("the dropped %s never appeared in the world" % id)
		return
	await _sleep(1.0)
	me = _me()
	if me == null:
		return
	var ref: WeakRef = weakref(item)
	_walk(item.global_position, 0.8, WALK_SPEED)
	await _wait_for(func() -> bool: return _me() == null or not _alive(ref) or _flat(_me().global_position, (ref.get_ref() as Node3D).global_position) < 1.2, 6.0)
	if _alive(ref) and _me():
		_me()._server_interact.rpc_id(1, (ref.get_ref() as Node).get_path())
	if not await _wait_for(func() -> bool: return _me() != null and _me().inventory.slots.get(slot, &"") == id, 6.0):
		_fail("picking the dropped %s up again never showed" % id)
	else:
		_say("dropped the %s and picked it up again" % id)


# --- Clients ----------------------------------------------------------------------------------

func _client_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	await _add_main(main)
	if not await _join():
		_fail("could not join %s:%d" % [address, Net.port()])
		_finish(2)
		return
	_post_status({"joined": Recorder.now()})
	var last_phase := ""
	var done := {}  # what this bot did, by "cycle:phase"
	while true:
		await _sleep(0.25)
		var p := _join_phase() if join else _read_json(run_dir.path_join("phase.json"))
		if not p.is_empty():
			_phase = p
		if bool(_phase.get("quit", false)):
			break
		if join:
			_join_tick()
			_post_place()
		if _rejoining:
			continue
		if not _online():
			_say("lost the connection to the host")
			recorder.event(["lost"])
			if not await _rejoin(5.0):
				_fail("could not get back in after losing the connection")
				_finish(2)
				return
			continue
		var cycle := int(_phase.get("cycle", 0))
		var ph := String(_phase.get("phase", ""))
		var key := "%d:%s" % [cycle, ph]
		if ph == "fight" and not (_phase.get("down", {}) as Dictionary).is_empty():
			key += "+down"  # the host posts the fight again with who goes down: a new job
		if key != last_phase:
			last_phase = key
			recorder.phase = key
			_say("phase %s" % key)
		if done.has(key):
			_client_tick(ph)
			continue
		done[key] = true
		_client_phase(cycle, ph)
	_say("time's up: leaving the game" if join else "the host says quit")
	_finish(0 if _failures.is_empty() else 1)


## Join mode: this bot's phase from where it is (no bot host to say): "base" at the base, else
## "follow" behind the host's player (peer 1); "quit" past its duration. The cycle steps on each
## level change, so a phase's one-time work runs again in each new place.
func _join_phase() -> Dictionary:
	if Recorder.now() - _t0 > duration_s or (quit_file != "" and FileAccess.file_exists(quit_file)):
		return {"quit": true}
	var lvl := _level()
	var id := lvl.get_instance_id() if lvl else 0
	if id != _join_level:
		_join_level = id
		_join_cycle += 1
	if lvl == null:
		return {"phase": "wait", "cycle": _join_cycle}
	if _in_base():
		return {"phase": "base", "cycle": _join_cycle}
	return {"phase": "follow", "cycle": _join_cycle, "leader": 1, "down": {}}


## Join mode, every quarter second: ready at the FOB (the ready-up button), ready in the briefing.
func _join_tick() -> void:
	if Recorder.now() - _join_ready_at < JOIN_READY_GAP_S:
		return
	_join_ready_at = Recorder.now()
	if _in_base():
		BaseHub.request("ready", [true])
	var briefing := MapNodes.briefing(_level()) if _level() else null
	if briefing and briefing.is_open():
		briefing.request_set_ready(true)


## Join mode: this bot's place in the squad as it sees it (its slot, role and fire team as the
## host replicates them, and whoever it sees in its buddy's slot), posted in its status ("place")
## whenever it changes: the botsjoin suite's host checks it sees the same (F-352).
func _post_place() -> void:
	var me := _me()
	if me == null:
		return
	var place := {"slot": me.squad_slot, "role": String(me.role), "team": me.fire_team, "buddy": _buddy_seen(me)}
	if place != _status.get("place", {}):
		_post_status({"place": place})
		_say("my place: slot %d, %s, team %d, buddy %s" % [me.squad_slot, me.role, me.fire_team, place["buddy"] if place["buddy"] != "" else "none"])


## The name of the living soldier on `me`'s side this peer sees in `me`'s buddy slot (a player or
## an AI squadmate), or "" (Soldier.buddy is the host's alone; slots are replicated, ServerSync).
func _buddy_seen(me: Soldier) -> String:
	if me.squad_slot < 0 or _level() == null:
		return ""
	var want := Roles.buddy_slot(me.squad_slot)
	for parent: Node in [_level().players, _level().ai]:
		for n: Node in parent.get_children():
			var s := n as Soldier
			if s and s != me and s.squad_slot == want and s.faction == me.faction and not s.vitals.is_dead() and not s.is_queued_for_deletion():
				return String(s.name)
	return ""


func _join() -> bool:
	main.get_node(^"Menu").join(address)
	var ok := await _wait_for(func() -> bool: return _online() and _me() != null, 60.0)
	if ok:
		_say("joined as peer %d into the %s" % [multiplayer.get_unique_id(), String(_level().level_info().get("level", "?"))])
		recorder.event(["joined", multiplayer.get_unique_id()])
	return ok


## Leaves as the Escape menu's "Main menu" does, then joins again after `gap` seconds.
func _rejoin(gap: float) -> bool:
	_rejoining = true
	_goal = null
	_fight = false
	if _online():
		Net.leave()
	BaseHub.cancel_session()
	main.queue_free()
	main = null
	await _sleep(gap)
	main = load("res://scenes/main.tscn").instantiate()
	await _add_main(main)
	var ok := await _join()
	_rejoining = false
	if ok:
		_post_status({"rejoined": Recorder.now()})
	return ok


## A phase's one-time work, run without blocking the loop.
func _client_phase(cycle: int, ph: String) -> void:
	match ph:
		"kit":
			await _kit_up(cycle)
			_post_status({"kit": cycle, "kit_summary": _kit_summary(_me())})
		"contract":
			if bot == 1:
				var cid := String(_phase.get("cid", ""))
				await _wait_for(func() -> bool: return Contracts.board().any(func(c: Dictionary) -> bool: return c.cid == cid), 5.0)
				Contracts.accept(cid, ContractGen.default_terms())
				_say("asked to accept %s" % cid)
		"pick":
			if bot == 2:
				for mid: String in _phase.get("pick", []):
					BaseHub.request("pick", [mid, true])
				_say("asked to pick %s" % [_phase.get("pick", [])])
		"briefing":
			# The zone may still be loading here: look the briefing up again until it's open.
			var open := await _wait_for(func() -> bool: return _level() != null and MapNodes.briefing(_level()) != null 				and MapNodes.briefing(_level()).is_open(), 20.0)
			var briefing := MapNodes.briefing(_level()) if _level() else null
			if briefing:
				briefing.request_set_ready(true)
			_say("briefing: ready%s" % ("" if open else " (the briefing never showed open here)"))
		"fight":
			_fight = true
			var down: Dictionary = _phase.get("down", {})
			var me_peer := multiplayer.get_unique_id()
			if not down.is_empty():
				if int(down.get("victim", 0)) == me_peer:
					_down_self()
				elif int(down.get("medic", 0)) == me_peer:
					_treat_loop(int(down.victim))
			elif reconnects and cycle == 1 and not _status.has("rejoined"):
				await _sleep(LEAVE_AT_S)
				_say("leaving mid-deployment (as the Escape menu's Main menu does), back in %d s" % int(RECONNECT_GAP_S))
				recorder.event(["leave_on_purpose"])
				var ok := await _rejoin(RECONNECT_GAP_S)
				if not ok:
					_fail("rejoining after leaving failed")
		"deployed":
			if _phase.has("spawn"):
				await _wait_for(func() -> bool: return _me() != null, 10.0)
				_go_to_start()
		"items":
			_fight = false
			_stop_fighting()
			await _sleep(float(bot) * 2.0)
			await _drop_and_pick_up()
		"extract":
			_fight = false
			_stop_fighting()
		"confirm":
			if bot == 1:
				var extraction := MapNodes.extraction(_level())
				if extraction:
					extraction.request_confirm()
					_say("asked to confirm the extraction")
		"follow":
			_fight = true
		"debrief":
			_fight = false
			_stop_fighting()
			var want := int(_phase.get("debrief", 0))
			var got := await _wait_for(func() -> bool: return int(Contracts.last_debrief().get("serial", 0)) >= want, 10.0)
			if not got:
				_fail("cycle %d: the debrief (%d) never reached this client (has %d)" % [cycle, want, int(Contracts.last_debrief().get("serial", 0))])
			_post_status({"debrief": int(Contracts.last_debrief().get("serial", 0))})


## Every quarter second during a phase: where to walk.
func _client_tick(ph: String) -> void:
	var me := _me()
	if ph == "follow" and me != null and me.vitals.is_up():
		_stuck_note(me, int(_phase.get("leader", 1)))  # before the treating check: it may be what holds them
	if me == null or not me.vitals.is_up() or _treating:
		return
	if ph in ["advance", "fight", "deployed", "items"]:
		var leader := _player(1)
		if leader:
			var spot := leader.global_position + _line_right() * float(LINE.get(bot, 0.0)) if _phase.has("facing") else _wedge_spot(leader)
			var off := _flat(me.global_position, spot)
			# In contact only this bot's pair moves (or anyone left far behind).
			var may_move := not _in_contact(me) or _pair_moving() or off > 25.0
			if off > 3.0 and not _dropping and may_move:
				_walk(spot, 1.5, RUN_SPEED if off > 15.0 else WALK_SPEED)
			elif not may_move:
				_goal = null
	elif ph == "follow":
		_follow_tick(me, int(_phase.get("leader", 1)))
	elif ph in ["extract", "confirm"] and _casevac == "":
		var rally: Array = _phase.get("rally", [])
		if rally.size() == 3:
			var at := Vector3(float(rally[0]), float(rally[1]), float(rally[2]))
			var angle := TAU * float(bot) / 4.0
			_walk(at + Vector3(cos(angle), 0.0, sin(angle)) * 3.0, 0.8, RUN_SPEED)


# --- What every bot does ----------------------------------------------------------------------

## Walks to the armory's world items and picks up what KIT says it lacks.
func _kit_up(cycle: int) -> void:
	var deadline := Recorder.now() + KIT_S - 10.0
	# A late joiner may still be loading the base here (its kit phase lasted 0.2 s, B-23), and
	# the host gives the role kit a moment after the body appears: wait for both.
	await _wait_for(func() -> bool: return _me() != null and _me().inventory.slots.get(&"vest", &"") != &"", 20.0)
	if cycle > 1:
		BaseHub.request("restock")  # last contract's loadout, from the stash (the game's own path)
		await _sleep(2.0)
	for id: String in KIT:
		while Recorder.now() < deadline:
			var me := _me()
			if me == null:
				return
			if _owned(me, StringName(id)) >= int(KIT[id]):
				break
			# Only what the kit still lacks: a whole armory stack (ifak x10) is left for the others.
			var item := _nearest_item(StringName(id), 500.0, int(KIT[id]) - _owned(me, StringName(id)))
			if item == null:
				break
			_walk(item.global_position, 0.9, RUN_SPEED)
			# A weak reference: the item may be freed while waiting (B-17, "Lambda capture freed").
			var ref: WeakRef = weakref(item)
			await _wait_for(func() -> bool: return _me() == null or not _alive(ref) or _flat(_me().global_position, (ref.get_ref() as Node3D).global_position) < 1.4, 15.0)
			if not _alive(ref) or _me() == null:
				continue
			var before := _owned(_me(), StringName(id))
			_me()._server_interact.rpc_id(1, (ref.get_ref() as Node).get_path())
			var took := await _wait_for(func() -> bool: return _me() != null and _owned(_me(), StringName(id)) > before, 3.0)
			if not took:
				_say("could not take %s (%s)" % [id, "gone" if not _alive(ref) else "refused"])
				break
	_goal = null
	_say("kit: %s" % JSON.stringify(_kit_summary(_me())))


## Units of `id` on `me`: worn in a slot or stowed.
static func _owned(me: Soldier, id: StringName) -> int:
	var n := me.inventory.count_of(id)
	for slot: StringName in me.inventory.slots:
		if me.inventory.slots[slot] == id:
			n += 1
	return n


func _kit_summary(me: Soldier) -> Dictionary:
	if me == null:
		return {}
	var out := {}
	for id: String in KIT:
		out[id] = _owned(me, StringName(id))
	out["rounds"] = me.inventory.rounds_in(&"primary")
	return out


func _nearest_item(id: StringName, within: float, at_most := 1 << 30) -> WorldItem:
	var me := _me()
	if me == null:
		return null
	var best: WorldItem = null
	var best_d := within
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item == null or item.item_id != id or item.is_queued_for_deletion() or not item.is_inside_tree() or item.count > at_most:
			continue
		var d := _flat(me.global_position, item.global_position)
		if d < best_d:
			best_d = d
			best = item
	return best


static func _alive(ref: WeakRef) -> bool:
	var n := ref.get_ref() as Node
	return n != null and n.is_inside_tree() and not n.is_queued_for_deletion()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _walk(to: Vector3, stop := 1.0, speed := WALK_SPEED) -> void:
	_goal = to
	_goal_stop = stop
	_goal_speed = speed


var _treating := false
var _medic_note_at := 0.0
var _said_lacking := false
var _dropping := false


## This player knocks itself out (dev tools' hurt, the K key's request), more if it stays up.
func _down_self() -> void:
	for attempt in 4:
		var me := _me()
		if me == null or not me.vitals.is_up():
			break
		_say("knocking myself out (%.0f)" % DOWN_DAMAGE)
		recorder.event(["self_hurt", DOWN_DAMAGE])
		me._server_debug_hurt.rpc_id(1, DOWN_DAMAGE)
		await _wait_for(func() -> bool: return _me() == null or not _me().vitals.is_up(), 4.0)
	var me := _me()
	_say("down: %s" % (me.vitals.condition_text() if me else "no player"))


## Goes to `victim_peer`'s body and treats it with what its care list asks for (own kit first,
## then the casualty's), until they're up or dead, or it had nothing to do for MEDIC_IDLE_S.
func _treat_loop(victim_peer: int) -> void:
	if _treating:
		# Already treating (buddy aid got there first, S0733: the planned medic then ran a second
		# loop on the same casualty beside it): that loop carries on.
		_say("medic: already treating, not starting a second treatment of peer %d" % victim_peer)
		return
	_treating = true
	_said_lacking = false
	var hard_stop := Recorder.now() + MEDIC_MAX_S
	await _wait_for(func() -> bool: return _player(victim_peer) != null and not _player(victim_peer).vitals.is_up(), 25.0)
	var idle_until := Recorder.now() + MEDIC_IDLE_S  # pushed back by every treatment
	var done: Array[String] = []
	var times := {}  # "item@part" -> how often used
	var why_stop := "time"
	while Recorder.now() < minf(idle_until, hard_stop):
		var me := _me()
		var victim := _player(victim_peer)
		if me == null or victim == null or victim.vitals.is_up() or victim.vitals.is_dead():
			why_stop = "up" if victim != null and victim.vitals.is_up() else ("dead" if victim != null else "gone")
			break
		if not me.vitals.is_up():
			await _sleep(1.0)
			continue
		var body := victim.body_point()
		if Recorder.now() >= _medic_note_at:
			_medic_note_at = Recorder.now() + 20.0
			_say("medic: peer %d %s, %.1f m from the body, care list %s" % [victim_peer, victim.vitals.condition_text(),
				_flat(me.global_position, body), str(victim.vitals.care_needed().map(func(t: Dictionary) -> String: return "%s:%s" % [t.get("kind", "?"), t.get("part", "")]))])
		if _flat(me.global_position, body) > 1.3:
			_walk(body, 0.9, RUN_SPEED)
			await _sleep(0.3)
			continue
		_goal = null
		var task := {}
		var item := &""
		var their := false
		for t: Dictionary in victim.vitals.care_needed():
			item = Vitals.pick_item(t, me.inventory)
			their = false
			if item == &"":
				item = Vitals.pick_item(t, victim.inventory)
				their = item != &""
			if item != &"" and int(times.get("%s@%s" % [item, t.get("part", "")], 0)) >= SAME_CARE_MAX:
				item = &""  # done twice already and still listed: it isn't taking (B-09)
			if item != &"":
				task = t
				break
		if task.is_empty():
			var wanted := victim.vitals.care_needed()
			if not wanted.is_empty() and not _said_lacking:
				_said_lacking = true
				_say("medic: %d thing(s) to do on peer %d but nothing to do them with: %s" % [wanted.size(), victim_peer,
					", ".join(wanted.map(func(t: Dictionary) -> String: return "%s (%s)" % [t.get("label", t.get("kind", "?")), str(Vitals.task_items(t))]))])
				# What this medic holds of them, as this machine sees it (S0735: a medic whose kit
				# summary had 3 IVs found none here).
				var held := {}
				for t: Dictionary in wanted:
					for id: StringName in Vitals.task_items(t):
						var n := me.inventory.medical_count(id)
						if n > 0:
							held[String(id)] = n
				_say("medic: holds %s; containers %s; slots %s" % [JSON.stringify(held), str(me.inventory.search_containers()),
					str(me.inventory.slots.values().filter(func(v: StringName) -> bool: return v != &""))])
			await _sleep(1.0)  # nothing to do now: waiting for them to come round
			continue
		var seconds := me.treat_seconds(victim, ItemDB.get_item(item))
		me._server_treat.rpc_id(1, victim.get_path(), item, StringName(task.get("part", &"")), false, their)
		var care_key := "%s@%s" % [item, task.get("part", "")]
		times[care_key] = int(times.get(care_key, 0)) + 1
		done.append("%s on %s%s" % [item, task.get("part", ""), " (their kit)" if their else ""])
		idle_until = Recorder.now() + seconds + MEDIC_IDLE_S
		await _sleep(seconds + 0.6)
	var victim := _player(victim_peer)
	if why_stop == "time":
		why_stop = "nothing to do for %d s" % int(MEDIC_IDLE_S) if Recorder.now() >= idle_until else "the %d s cap" % int(MEDIC_MAX_S)
	_say("treated peer %d: %s -> %s (stopped: %s)" % [victim_peer, ", ".join(done), victim.vitals.condition_text() if victim else "gone", why_stop])
	_treating = false
	_post_status({"treated": done, "treat_end": Recorder.now()})


func _hostile_in_range(me: Soldier, within: float) -> Soldier:
	if me == null:
		return null
	var best: Soldier = null
	var best_d := within
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or s.faction != &"hostile" or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		var d := me.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _stop_fighting() -> void:
	var me := _me()
	if me:
		me.is_aiming = false
		if me.vitals.is_up():
			me.movement.set_stance(SoldierMovement.Stance.STAND_HIGH)


## Buddy aid: once a second while deployed, a player down that nobody planned (shot by the
## hostiles) gets treated by the nearest player still up, as a squad would.
var _aid_left := 1.0
var _last_clear_shot := 0.0
var _pinned_until := 0.0
var _last_blood := 1.0


## This bot's pair (host and bot 2, bot 1 and bot 3) is the one moving now (wall clock, so all
## processes on this machine agree).
func _pair_moving() -> bool:
	return int(Time.get_unix_time_from_system() / BOUND_S) % 2 == bot % 2


## This bot's place in the wedge behind `leader`, turned the way the leader faces.
func _wedge_spot(leader: Soldier) -> Vector3:
	var o: Vector2 = WEDGE.get(bot, Vector2(0.0, 8.0))
	var yaw := leader.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return leader.global_position + right * o.x - fwd * o.y


func _in_contact(me: Soldier) -> bool:
	return _fight and _hostile_in_range(me, ENGAGE_M) != null
var _down_for := 0.0
var _give_up_left := 0.0
## Down this long with every player down (nobody can help), a bot gives up: dev tools' hurt
## until it dies and respawns. Dev has no give-up yet (B3, on gameplay/respawn); without
## this a squad wipe leaves the soak waiting at an extraction nobody can reach.
const GIVE_UP_S := 45.0
## With a human in (--human), a bot down this long gives up even with others still up: nobody
## came for it, and lying there blocks the human's extraction (S0758: both bots down 400 m
## from the LZ for 20 minutes).
const GIVE_UP_ALONE_S := 120.0


func _give_up_tick(me: Soldier, delta: float) -> void:
	if me.vitals.is_up() or me.vitals.is_dead() or _in_base():
		_down_for = 0.0
		return
	_down_for += delta
	_give_up_left -= delta
	if _down_for < GIVE_UP_S or _give_up_left > 0.0:
		return
	_give_up_left = 5.0
	var players := _level().get_node_or_null(^"Players")
	for node in (players.get_children() if players else []):
		var s := node as Soldier
		if s and s.vitals.is_up() and not (human and _down_for >= GIVE_UP_ALONE_S):
			return  # someone could still come
	recorder.event(["give_up", "Players/%d" % multiplayer.get_unique_id()])
	if me.has_method(&"_server_give_up"):
		if not me.can_give_up():
			return
		_say("down %.0f s and %s: giving up (the give-up key's request)" % [_down_for, "nobody came" if human and _down_for >= GIVE_UP_ALONE_S else "every player is down"])
		me._server_give_up.rpc_id(1)
	else:  # code from before gameplay/respawn: no give-up, so die through the dev hurt
		_say("B3: down %.0f s and every player is down: giving up (dev hurt until dead, then respawn)" % _down_for)
		me._server_debug_hurt.rpc_id(1, 1000.0)


var _casevac := ""          # the downed player this bot is carrying to the extraction, or ""
var _casevac_since := 0.0
var _casevac_left := 0.0


## Extraction with a player still down (nobody could bring them round): the nearest player up
## carries them to the rally point, as a squad would (the extraction waits for every player).
func _casevac_tick(me: Soldier, delta: float) -> void:
	var ph := String(_phase.get("phase", ""))
	if ph not in ["extract", "confirm"]:
		_casevac = ""
		return
	var rally: Array = _phase.get("rally", [])
	if rally.size() != 3:
		return
	var at := Vector3(float(rally[0]), float(rally[1]), float(rally[2]))
	if _casevac != "":
		var victim := _player(int(_casevac))
		if victim == null or victim.vitals.is_up():
			_casevac = ""
			return
		if me.carry_mode != &"":
			# Lifting takes a moment (the carrier stands still), then to the rally point.
			if Soldier._now() - _casevac_since > Soldier.CARRY_LIFT_S + 0.5:
				_walk(at, 1.5, WALK_SPEED)
			return
		_casevac_left -= delta
		if _casevac_left > 0.0:
			return
		_casevac_left = 0.5
		var body := victim.body_point()
		if _flat(me.global_position, body) > 1.2:
			_walk(body, 0.8, RUN_SPEED)
		else:
			_goal = null
			me._server_carry_body.rpc_id(1, victim.get_path())
			_casevac_since = Soldier._now()
		return
	_casevac_left -= delta
	if _casevac_left > 0.0 or _treating or me.carry_mode != &"":
		return
	_casevac_left = 1.0
	if role == "host" and _goal == null and _flat(me.global_position, at) > 4.0:
		_walk(at, 2.0, RUN_SPEED)  # back to the rally point (after a respawn, say)
	var players := _level().get_node_or_null(^"Players")
	if players == null:
		return
	for node in players.get_children():
		var casualty := node as Soldier
		if casualty == null or casualty == me or casualty.vitals.is_up() or _flat(casualty.body_point(), at) < 8.0 				or StringName(casualty.model.carry_net.get("mode", &"")) in [CharacterModel.CARRIED, CharacterModel.DRAGGED]:
			continue  # up, already at the rally point, or someone has them
		var nearest: Soldier = null
		var best := INF
		for other in players.get_children():
			var s := other as Soldier
			if s and s.vitals.is_up() and s.carry_mode == &"":
				var d := _flat(s.global_position, casualty.body_point())
				if d < best:
					best = d
					nearest = s
		if nearest == me:
			_casevac = String(casualty.name)
			_say("casevac: carrying %s (%s) to the extraction" % [casualty.name, casualty.vitals.condition_text()])
			recorder.event(["casevac", "Players/%s" % casualty.name])
			return
var _hunt_left := 0.0


## Host, in the fight: no clear shot for a while, walk toward the nearest hostile (a squad
## pushing on; a fight with nobody in sight shows nothing).
func _hunt(me: Soldier, delta: float) -> void:
	_hunt_left -= delta
	if _hunt_left > 0.0:
		return
	_hunt_left = 1.0
	if role != "host" or not _fight or _treating or _dropping or Soldier._now() - _last_clear_shot < HUNT_AFTER_S \
			or String(_phase.get("phase", "")) == "follow":  # with a human leading, the bots stay with them
		return
	var foe := _hostile_in_range(me, 800.0)
	if foe == null:
		return
	var d := _flat(me.global_position, foe.global_position)
	if d <= HUNT_STOP_M:
		return
	if _in_contact(me) and not _pair_moving():
		return  # the other pair is moving: hold and cover them
	# One bound toward them (not the whole way in one walk).
	var dir := Vector3(foe.global_position.x - me.global_position.x, 0.0, foe.global_position.z - me.global_position.z).normalized()
	_walk(me.global_position + dir * minf(BOUND_M, d - HUNT_STOP_M), 1.0, RUN_SPEED)


func _buddy_aid(me: Soldier, delta: float) -> void:
	_aid_left -= delta
	if _aid_left > 0.0:
		return
	_aid_left = 1.0
	if _treating or _rejoining or _in_base() or not me.vitals.is_up() or not Contracts.is_deployed() 			or String(_phase.get("phase", "")) in ["extract", "confirm"] or _casevac != "":
		return  # at the extraction a casualty is carried in instead (_casevac_tick)
	var planned: Dictionary = _phase.get("down", {})
	var players := _level().get_node_or_null(^"Players")
	if players == null:
		return
	for node in players.get_children():
		var casualty := node as Soldier
		if casualty == null or casualty == me or casualty.vitals.is_up() or casualty.vitals.is_dead():
			continue
		var peer := int(String(casualty.name)) if String(casualty.name).is_valid_int() else 0
		if peer == int(planned.get("victim", -1)):
			continue  # the planned knock-out has its own medic
		var nearest: Soldier = null
		var best := INF
		for other in players.get_children():
			var s := other as Soldier
			if s and s.vitals.is_up():
				var d := _flat(s.global_position, casualty.body_point())
				if d < best:
					best = d
					nearest = s
		var for_human := String(_phase.get("phase", "")) == "follow" and not _is_bot_peer(peer) and me.role == Roles.MEDIC \
			and _flat(me.global_position, casualty.body_point()) < 400.0  # the medic goes to the human, whoever is nearer
		if (nearest == me and best < 150.0) or for_human:
			_say("buddy aid: %s is down (%s), going to treat" % [casualty.name, casualty.vitals.condition_text()])
			recorder.event(["aid", "Players/%s" % casualty.name])
			_treat_loop(peer)
			return


var _was_dead := {}  # host: player name -> true while dead (a respawn: dead, then up again)
var _respawn_left := 2.0


## Host: a player who died and is up again has respawned: log the kit they came back in.
func _watch_respawns(delta: float) -> void:
	_respawn_left -= delta
	if _respawn_left > 0.0 or role != "host" or not (_level() is ZoneLevel):
		return
	_respawn_left = 2.0
	var players := _level().get_node_or_null(^"Players")
	for c in (players.get_children() if players else []):
		var s := c as Soldier
		if s == null:
			continue
		if s.vitals.is_dead():
			_was_dead[s.name] = true
		elif _was_dead.has(s.name) and s.vitals.is_up():
			_was_dead.erase(s.name)
			_say("[kit] respawned %s %s: %s" % [_kit_name(s), String(s.role).replace("_", " "), _kit_line(s)])


var _role_kitted := {}  # host: profile key -> true once that bot got its role's kit
var _kit_check_left := 1.0


## Host: each bot player gets its role's kit once (Roles.apply_kit, the game's own kit path), as
## soon as its soldier has a role and BaseHub has put its saved gear on (that replaces the whole
## inventory, so a kit given before it is lost): at the start, a late joiner (in the zone), a bot
## that rejoined under a new peer id (the same profile: its own gear comes back, no second kit).
## A real player (--human) plays in their own gear.
func _kit_players(delta: float) -> void:
	_kit_check_left -= delta
	if _kit_check_left > 0.0 or role != "host":
		return
	_kit_check_left = 1.0
	var lvl := _level()
	var players := lvl.get_node_or_null(^"Players") if lvl else null
	if players == null:
		return
	var bot_of := {1: 0}
	var bots := _bots()
	for n: int in bots:
		bot_of[int(bots[n].get("peer", 0))] = n
	for c in players.get_children():
		var s := c as Soldier
		if s == null or s.is_queued_for_deletion() or s.role == &"" or not s.vitals.is_up():
			continue
		var peer := int(String(s.name)) if String(s.name).is_valid_int() else 0
		if not bot_of.has(peer) and not human:
			continue  # a bot that hasn't posted its peer id yet (with --human: a human gets the kit too)
		if BaseHub.campaign_running and not BaseHub._gear_applied.has(peer):
			continue  # its saved gear goes on first
		var key := BaseHub.player_key(peer) if BaseHub.campaign_running else str(peer)
		if _role_kitted.has(key):
			continue
		_role_kitted[key] = true
		Roles.apply_kit(s.inventory, s.role)
		_say("[kit] role kit (Roles.apply_kit) for %s %s%s: %s" % [_kit_name(s) if bot_of.has(peer) else "the human (peer %d)" % peer, String(s.role).replace("_", " "),
			"" if _in_base() else " (joined in the zone)", _kit_line(s)])


func _physics_process(delta: float) -> void:
	_watch_respawns(delta)
	_kit_players(delta)
	var me := _me()
	if me == null or not me.is_local():
		return
	_buddy_aid(me, delta)
	_give_up_tick(me, delta)
	if me.vitals.is_up():
		_hunt(me, delta)
		_casevac_tick(me, delta)
	if not me.vitals.is_up() or is_instance_valid(me.vehicle):
		return
	var blood := me.vitals.blood_fraction()
	if blood < _last_blood - 0.004 and not _in_base():
		_pinned_until = Soldier._now() + PINNED_S  # hit: stop and get down
	_last_blood = blood
	var pinned := Soldier._now() < _pinned_until and _casevac == "" and not _treating
	_track_wedge(me, pinned)
	if _goal != null and not pinned:
		var to: Vector3 = _goal
		var d := _flat(me.global_position, to)
		if d <= _goal_stop:
			_goal = null
		else:
			var dir := Vector3(to.x - me.global_position.x, 0.0, to.z - me.global_position.z).normalized()
			if Recorder.now() < _detour_until:
				dir = _detour_dir  # wedged: a few metres off the straight line first
			var step := minf(_goal_speed * delta, d - _goal_stop * 0.5)
			var pos := me.global_position + dir * step
			var ground := _level().ground_point(pos)
			if pos.y < ground.y:
				pos.y = ground.y
			me.global_position = pos
			if not _fight or not me.is_aiming:
				me.rotation.y = atan2(-dir.x, -dir.z)
	if _fight:
		_fight_tick(me)


## soak-stuck-bots (S0758): a bot walks by stepping its position straight at the goal, and its
## own move_and_slide pushes it back out of whatever it stepped into. At harbour_yard's town_4
## both client bots stepped into the voxel pockets of a quayside building (walls 0.3-0.7 m off
## on every side, a floor 3 m overhead) and stood there for 20 minutes, up and unhurt, 400 m
## behind the human, every step undone by the wall. Wedged (no headway toward the goal for
## WEDGED_S): a few metres off the straight line, a different way each time (DETOUR_DEG); still
## wedged after CATCH_UP_S: caught up beside the leader (the human in FOLLOW, the host
## otherwise), as a player would be teleported out of a spot they cannot leave.
const WEDGED_S := 4.0
const DETOUR_S := 1.5
const DETOUR_DEG: Array[float] = [75.0, -75.0, 135.0, -135.0, 180.0]
const CATCH_UP_S := 20.0
const CATCH_UP_MIN_M := 8.0  # no catch-up this close to the leader: the detours will do
var _wedge_last := Vector3.INF
var _wedge_gain := 0.0     # metres made toward the goal since _wedge_since
var _wedge_since := 0.0
var _detour_until := 0.0
var _detour_dir := Vector3.ZERO
var _detour_n := 0
var _wedge_tick := 0.0     # when _track_wedge last ran (it doesn't while down or riding)


## Every physics frame: the headway made toward the goal; wedged, a detour, then a catch-up.
## Not called while down or riding: a gap of more than half a second starts over (S0794: a bot
## that gave up after 120 s down was "wedged 121 s" the moment it stood up again).
func _track_wedge(me: Soldier, pinned: bool) -> void:
	var now := Recorder.now()
	var pos := me.global_position
	var last := _wedge_last
	var gap := now - _wedge_tick
	_wedge_last = pos
	_wedge_tick = now
	if _goal == null or pinned or _treating or _dropping or me.carry_mode != &"" or is_instance_valid(me.vehicle) \
			or me.respawn_state == Soldier.RESPAWN_WAITING or gap > 0.5 \
			or last == Vector3.INF or last.distance_to(pos) > 5.0:  # a respawn or a warp: start over
		_wedge_gain = 0.0
		_wedge_since = now
		_detour_n = 0
		return
	var to: Vector3 = _goal
	var ahead := Vector3(to.x - pos.x, 0.0, to.z - pos.z)
	if ahead.length() > 0.01:
		_wedge_gain += Vector3(pos.x - last.x, 0.0, pos.z - last.z).dot(ahead.normalized())
	if _wedge_gain >= 1.0:
		_wedge_gain = 0.0
		_wedge_since = now
		_detour_n = 0
		return
	var wedged := now - _wedge_since
	if wedged >= CATCH_UP_S and _catch_up(me, wedged):
		return
	if wedged >= WEDGED_S and now >= _detour_until:
		var angle := deg_to_rad(DETOUR_DEG[_detour_n % DETOUR_DEG.size()])
		_detour_n += 1
		_detour_dir = ahead.normalized().rotated(Vector3.UP, angle)
		_detour_until = now + DETOUR_S


## The leader a wedged bot catches up with: the human in FOLLOW, else the host (for its clients).
func _wedge_leader() -> Soldier:
	if String(_phase.get("phase", "")) == "follow":
		return _player(int(_phase.get("leader", 0)))
	return _player(1) if role != "host" else null


## Wedged CATCH_UP_S in the zone: put the bot beside the leader (on foot, up, and not right
## here), on the first spot round them with open air between the two. True once it moved.
func _catch_up(me: Soldier, wedged: float) -> bool:
	var lead := _wedge_leader()
	if lead == null or lead == me or not lead.vitals.is_up() or Vehicle.ride_of(lead) != null or _in_base() \
			or _flat(lead.global_position, me.global_position) < CATCH_UP_MIN_M:
		return false
	var yaw := lead.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var space := me.get_world_3d().direct_space_state
	var chest := lead.global_position + Vector3.UP * 1.2
	for off: Vector3 in [-fwd * 2.0, right * 2.0, -right * 2.0, -fwd * 1.2 + right * 1.2]:
		var spot := lead.global_position + off
		var q := PhysicsRayQueryParameters3D.create(chest, spot + Vector3.UP * 1.2, 1)
		q.exclude = [me.get_rid(), lead.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue  # a wall between: not this side
		_say("wedged %.0f s at %s (goal %s, %.0f m from the leader): caught up beside %s at %s" % [wedged, Recorder._v3(me.global_position),
			Recorder._v3(_goal), _flat(lead.global_position, me.global_position), lead.name, Recorder._v3(spot)])
		recorder.event(["caught_up", "Players/%d" % multiplayer.get_unique_id(), snappedf(wedged, 0.1)])
		me.velocity = Vector3.ZERO
		me.global_position = spot + Vector3.UP * 0.1
		_wedge_last = Vector3.INF
		_detour_until = 0.0
		return true
	return false


func _fight_tick(me: Soldier) -> void:
	var now := Soldier._now()
	if _treating or me.inventory.hands != &"" or me.carry_mode != &"":
		me.is_aiming = false
		return
	var target := _hostile_in_range(me, ENGAGE_M)
	# Crouched while there is something to shoot at (a smaller target, as a player would be).
	# Moving: crouched. Holding with a clear shot, or just hit: prone; else kneeling, to see over.
	var stance := SoldierMovement.Stance.STAND_HIGH
	if target != null or now < _pinned_until:
		var holding := _goal == null or now < _pinned_until
		stance = SoldierMovement.Stance.CROUCH_MID
		if holding and (now < _pinned_until or now - _last_clear_shot < 2.0):
			stance = SoldierMovement.Stance.PRONE
		elif holding:
			stance = SoldierMovement.Stance.CROUCH_LOW
	if me.movement.stance != stance:
		me.movement.set_stance(stance)
	if target == null:
		me.is_aiming = false
		return
	var chest := target.global_position + Vector3.UP * 1.25
	var eye := me.camera.global_position
	var to := chest - eye
	me.rotation.y = atan2(-to.x, -to.z)
	me.head.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -Soldier.MAX_PITCH, Soldier.MAX_PITCH)
	var weapon := me.active_weapon()
	me.is_aiming = weapon != null and not me.is_reloading
	if weapon == null or weapon.type != "weapon" or now < _next_shot or now < me._busy_until:
		return
	if me.inventory.rounds_in(me.active_slot) <= 0:
		var ammo := Soldier._ammo_of(weapon)
		if me.inventory.spare_rounds(ammo) > 0:
			me._busy_until = now + me.reload_seconds(weapon)
			me.is_reloading = true
			me._server_reload.rpc_id(1, me.active_slot)
		return
	# Only through open air: a wall in the way wastes rounds (the AI holds fire too).
	var space := me.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, chest, 1)
	query.exclude = [me.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and (hit.position as Vector3).distance_to(chest) > 1.0:
		return
	_last_clear_shot = now
	_next_shot = now + SHOT_GAP_S
	me._server_fire.rpc_id(1, eye, to.normalized(), me.active_slot)
