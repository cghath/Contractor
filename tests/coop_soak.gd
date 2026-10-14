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
const EXTRA_STASH := [["assault_pack", 4], ["m4a1", 4], ["plate_carrier", 2], ["helmet", 4], ["mag_556", 24], ["ifak", 6], ["iv_18", 4],
	["saline_500", 6], ["epinephrine", 4], ["morphine", 4], ["tourniquet", 4]]
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
const REVIVE_S := 150.0
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
var wait_human_s := 600.0
const HUMAN_EXTRACT_S := 1200.0

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
	wait_human_s = float(_arg(args, "--soak-wait-human", "600"))
	_t0 = Recorder.now()
	var peer_dir := run_dir.path_join("host" if role == "host" else "client%d" % bot)
	DirAccess.make_dir_recursive_absolute(peer_dir)
	# The harness stops this process by its pid (tools/coop_soak.sh, taskkill) if it outlives the run.
	FileAccess.open(peer_dir.path_join("pid"), FileAccess.WRITE).store_string(str(OS.get_process_id()))
	_log = FileAccess.open(peer_dir.path_join("bot.log"), FileAccess.WRITE)
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
	# Players start in their role's kit (Roles.apply_kit: the play entries' path, both plates in
	# the carrier), and from the second contract restock their last loadout from the stash
	# (BaseHub "restock", the base screen's button). The kit-up walk then only tops up extras.
	CompoundLevel.player_role_kits = true
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
	add_child(main)
	await get_tree().process_frame
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
		await _sleep(3.0)  # the bots post their peer ids (bot<N>.json) just after joining
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


## Connected peers that are no bot of this harness (a real player who joined).
func _humans() -> Array:
	var bot_peers := _bots().values().map(func(st: Dictionary) -> int: return int(st.get("peer", 0)))
	return Array(multiplayer.get_peers()).filter(func(id: int) -> bool: return not id in bot_peers)


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
	var all_ready := await _wait_for(func() -> bool: return briefing != null and briefing.all_ready(), 25.0)
	if briefing:
		briefing.server_start(true)
	result["briefing"] = {"all_ready": all_ready}
	await _wait_for(Contracts.is_deployed, 10.0)
	if not Contracts.is_deployed():
		result.why = "the contract never went live"
		return result
	await _sleep(3.0)  # the garrisons come out over a few frames
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
	result["extract"] = {"gathered": gathered, "left_behind": left_behind, "missing": Array(extraction.missing_at(extraction._nearest_point())) if not gathered else []}
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
	# Debrief.
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
	var best := {}
	var r := DEAD_RING_M.x
	while r <= DEAD_RING_M.y:
		for k in 48:
			var a := TAU * k / 48.0
			var at := target + Vector3(cos(a), 0.0, sin(a)) * r
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
	var up := await _wait_for(func() -> bool:
		var v := _player(victim_peer)
		return v == null or v.vitals.is_up() or v.vitals.is_dead(), REVIVE_S)
	victim = _player(victim_peer)
	out["up"] = victim != null and victim.vitals.is_up()
	out["dead"] = victim != null and victim.vitals.is_dead()
	out["seconds"] = snappedf(Recorder.now() - t, 0.1)
	if victim and not victim.vitals.is_up() and not victim.vitals.is_dead():
		out["still_down"] = victim.vitals.condition_text()
		out["why_unconscious"] = Array(victim.vitals.why_unconscious())
	return out


func _drop_and_pick_up() -> void:
	var me := _me()
	if me == null or not me.vitals.is_up():
		return
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
	_walk(item.global_position, 0.8, WALK_SPEED)
	await _wait_for(func() -> bool: return _me() == null or not is_instance_valid(item) or _flat(_me().global_position, item.global_position) < 1.2, 6.0)
	if is_instance_valid(item) and _me():
		_me()._server_interact.rpc_id(1, item.get_path())
	if not await _wait_for(func() -> bool: return _me() != null and _me().inventory.slots.get(slot, &"") == id, 6.0):
		_fail("picking the dropped %s up again never showed" % id)
	else:
		_say("dropped the %s and picked it up again" % id)


# --- Clients ----------------------------------------------------------------------------------

func _client_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if not await _join():
		_fail("could not join %s:%d" % [address, Net.port()])
		_finish(2)
		return
	_post_status({"joined": Recorder.now()})
	var last_phase := ""
	var done := {}  # what this bot did, by "cycle:phase"
	while true:
		await _sleep(0.25)
		var p := _read_json(run_dir.path_join("phase.json"))
		if not p.is_empty():
			_phase = p
		if bool(_phase.get("quit", false)):
			break
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
	_say("the host says quit")
	_finish(0 if _failures.is_empty() else 1)


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
	add_child(main)
	await get_tree().process_frame
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
		"debrief":
			var want := int(_phase.get("debrief", 0))
			var got := await _wait_for(func() -> bool: return int(Contracts.last_debrief().get("serial", 0)) >= want, 10.0)
			if not got:
				_fail("cycle %d: the debrief (%d) never reached this client (has %d)" % [cycle, want, int(Contracts.last_debrief().get("serial", 0))])
			_post_status({"debrief": int(Contracts.last_debrief().get("serial", 0))})


## Every quarter second during a phase: where to walk.
func _client_tick(ph: String) -> void:
	var me := _me()
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
			var item := _nearest_item(StringName(id), 500.0)
			if item == null:
				break
			_walk(item.global_position, 0.9, RUN_SPEED)
			await _wait_for(func() -> bool: return _me() == null or not is_instance_valid(item) or _flat(_me().global_position, item.global_position) < 1.4, 15.0)
			if not is_instance_valid(item) or _me() == null:
				continue
			var before := _owned(_me(), StringName(id))
			_me()._server_interact.rpc_id(1, item.get_path())
			var took := await _wait_for(func() -> bool: return _me() != null and _owned(_me(), StringName(id)) > before, 3.0)
			if not took:
				_say("could not take %s (%s)" % [id, "gone" if not is_instance_valid(item) else "refused"])
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


func _nearest_item(id: StringName, within: float) -> WorldItem:
	var me := _me()
	if me == null:
		return null
	var best: WorldItem = null
	var best_d := within
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item == null or item.item_id != id or item.is_queued_for_deletion() or not item.is_inside_tree():
			continue
		var d := _flat(me.global_position, item.global_position)
		if d < best_d:
			best_d = d
			best = item
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _walk(to: Vector3, stop := 1.0, speed := WALK_SPEED) -> void:
	_goal = to
	_goal_stop = stop
	_goal_speed = speed


var _treating := false
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
## then the casualty's), until they're up, dead, or REVIVE_S runs out.
func _treat_loop(victim_peer: int) -> void:
	_treating = true
	_said_lacking = false
	var deadline := Recorder.now() + REVIVE_S
	await _wait_for(func() -> bool: return _player(victim_peer) != null and not _player(victim_peer).vitals.is_up(), 25.0)
	var done: Array[String] = []
	while Recorder.now() < deadline:
		var me := _me()
		var victim := _player(victim_peer)
		if me == null or victim == null or victim.vitals.is_up() or victim.vitals.is_dead():
			break
		if not me.vitals.is_up():
			await _sleep(1.0)
			continue
		var body := victim.body_point()
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
			if item != &"":
				task = t
				break
		if task.is_empty():
			var wanted := victim.vitals.care_needed()
			if not wanted.is_empty() and not _said_lacking:
				_said_lacking = true
				_say("medic: %d thing(s) to do on peer %d but nothing to do them with: %s" % [wanted.size(), victim_peer,
					", ".join(wanted.map(func(t: Dictionary) -> String: return "%s (%s)" % [t.get("label", t.get("kind", "?")), str(Vitals.task_items(t))]))])
			await _sleep(1.0)  # nothing to do now: waiting for them to come round
			continue
		var seconds := me.treat_seconds(victim, ItemDB.get_item(item))
		me._server_treat.rpc_id(1, victim.get_path(), item, StringName(task.get("part", &"")), false, their)
		done.append("%s on %s%s" % [item, task.get("part", ""), " (their kit)" if their else ""])
		await _sleep(seconds + 0.6)
	var victim := _player(victim_peer)
	_say("treated peer %d: %s -> %s" % [victim_peer, ", ".join(done), victim.vitals.condition_text() if victim else "gone"])
	_post_status({"treated": done})
	_treating = false


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
		if s and s.vitals.is_up():
			return  # someone could still come
	recorder.event(["give_up", "Players/%d" % multiplayer.get_unique_id()])
	if me.has_method(&"_server_give_up"):
		if not me.can_give_up():
			return
		_say("down %.0f s and every player is down: giving up (the give-up key's request)" % _down_for)
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
	if role != "host" or not _fight or _treating or _dropping or Soldier._now() - _last_clear_shot < HUNT_AFTER_S:
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
		if nearest == me and best < 150.0:
			_say("buddy aid: %s is down (%s), going to treat" % [casualty.name, casualty.vitals.condition_text()])
			recorder.event(["aid", "Players/%s" % casualty.name])
			_treat_loop(peer)
			return


func _physics_process(delta: float) -> void:
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
	if _goal != null and not pinned:
		var to: Vector3 = _goal
		var d := _flat(me.global_position, to)
		if d <= _goal_stop:
			_goal = null
		else:
			var dir := Vector3(to.x - me.global_position.x, 0.0, to.z - me.global_position.z).normalized()
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
