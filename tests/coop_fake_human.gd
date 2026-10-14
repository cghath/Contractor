extends Node
## A stand-in for the Captain in a co-op soak with --human (tools/coop_soak.sh): a plain client
## that joins through the main menu's Join like a player's build does (no bot status file, so
## the host takes it for a human). Each deployment it says ready on the briefing, stands a
## while, walks toward the objective, stops, calls an extraction point where it stands and
## confirms it. It checks what the --human bots must do: it got its role's kit, the bots stay
## 10-25 m off it, they come into its extraction point, everyone goes home.
##   CONTRACTOR_PORT=<host port> <godot> --headless --path . res://tests/coop_fake_human.tscn -- --out <dir> [--deployments 2]
##     [--run <soak run folder>] [--checks]
## Exit 0 when every check passed.
##
## --checks (tools/coop_soak.sh --checks; Captain, 2026-10-14: automated checks of the day's
## co-op fixes, so he doesn't find regressions by playing). Each goes to <out>/checks.jsonl as
## PASS, FAIL, SKIPPED (not in this build: every new call is feature-detected, has_method/get,
## so the harness still runs bots from an older build's commit) or NOT RUN (the run couldn't get
## to it; tried again in a later deployment), and the soak's report.md lists them:
##   fob_ready        (feat/fob-ready-up) at the FOB the host's Deploy is refused naming this
##                    client while it isn't ready (the host's part: host/checks.jsonl), its own
##                    view says it's waited for; after its Ready the squad deploys
##   heli_lz          (fix/coop-extraction) a helicopter extraction it calls shows only its LZ
##                    (Extraction.shown_points/heli_point); sent home, every point shows again
##   extract_confirm  (fix/coop-extraction) its confirm from outside every point is refused;
##                    from inside one, with the bots in, its confirm starts the countdown (the
##                    host doesn't confirm for it on such a build: tests/coop_soak.gd)
##   respawn_kit      (fix/respawn-own-kit) it dies (dev tools' hurt), respawns in the kit it
##                    died in, and no player body is left
##   leave_behind     (fix/coop-extraction) the host knocks out a bot player (asked through
##                    <run>/human_ask.json); it calls a point away from them: its first confirm
##                    warns "Leaving behind" naming them, a second one starts the countdown
## Deployment 1 runs heli_lz and extract_confirm, deployment 2 respawn_kit and leave_behind; a
## third one retries what was NOT RUN.

const WALK_SPEED := 4.0
const STAND_S := 45.0       # standing at the insertion first (the bots come to it)
const WALK_M := 160.0       # then toward the objective
const HOLD_S := 30.0
const GATHER_S := 120.0
const NEAR_M := 30.0        # a bot this close counts as "with the human" (FOLLOW is 10-25 m)
## --checks: a shorter walk out (less time near the hostiles before the checks).
const CHECKS_WALK_M := 60.0
## --checks: where a check's extraction point lies (extract_confirm: this far ahead, so the
## fake human starts outside it; leave_behind: this far from the downed bot, well outside 20 m).
const CHECK_POINT_M := 45.0
const LEAVE_POINT_M := 55.0
const CHECK_IDS: Array[String] = ["fob_ready", "heli_lz", "extract_confirm", "respawn_kit", "leave_behind"]

var out_dir := ""
var deployments := 2
var run_dir := ""           # the soak's run folder (--run): phase.json to read, human_ask.json to write
var checks := false
var main: Node
var _t0 := 0.0
var _problems: Array[String] = []
var _log: FileAccess
var _checks_file: FileAccess
var _results := {}          # check id -> [result, ...] in order
var _samples := 0
var _samples_all_near := 0
var _dist_max := 0.0
var _goal: Variant = null
var _heading := Vector3(0, 0, -1)  # the way this deployment walked (toward the objective)
var _flashes: Array[Dictionary] = []  # every HUD message seen: {"t": unix s, "text": ...}
var _flash_text := ""
var _flash_time := 0.0
var _ask_serial := 0
var _ready_cycle := 0       # the host's cycle whose FOB ready-up this client answered last


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = _arg(args, "--out", ProjectSettings.globalize_path("user://fake_human"))
	deployments = int(_arg(args, "--deployments", "2"))
	run_dir = _arg(args, "--run", "")
	checks = "--checks" in args
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("fake_human.log"), FileAccess.WRITE)
	if checks:
		_checks_file = FileAccess.open(out_dir.path_join("checks.jsonl"), FileAccess.WRITE)
	if run_dir != "":
		# tools/coop_soak.sh stops a leftover instance by this pid.
		FileAccess.open(out_dir.path_join("pid"), FileAccess.WRITE).store_string(str(OS.get_process_id()))
	_t0 = _now()
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


static func _now() -> float:
	return Time.get_unix_time_from_system()


func _say(text: String) -> void:
	var line := "[human %.1f] %s" % [_now() - _t0, text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


func _problem(text: String) -> void:
	_problems.append(text)
	_say("PROBLEM: " + text)


## One check's result (see the class doc): logged, and a line in <out>/checks.jsonl.
func _check(id: String, result: String, detail: String) -> void:
	if not _results.has(id):
		_results[id] = []
	(_results[id] as Array).append(result)
	_say("CHECK %s %s: %s" % [id, result, detail])
	if _checks_file:
		_checks_file.store_line(JSON.stringify({"check": id, "result": result, "detail": detail, "by": "human", "t": _now()}))
		_checks_file.flush()


## Whether check `id` still wants a try: --checks and no PASS, FAIL or SKIPPED for it yet.
func _pending(id: String) -> bool:
	return checks and not (_results.get(id, []) as Array).any(func(r: String) -> bool: return r != "NOT RUN")


func _any_pending() -> bool:
	return CHECK_IDS.any(func(id: String) -> bool: return id != "fob_ready" and _pending(id))


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


## The other players' soldiers in the level (the bots).
func _others() -> Array[Soldier]:
	var out: Array[Soldier] = []
	var me := _me()
	var players := _level().get_node_or_null(^"Players") if _level() else null
	for c in (players.get_children() if players else []):
		var s := c as Soldier
		if s and s != me and not s.is_queued_for_deletion():
			out.append(s)
	return out


func _player_named(peer_name: String) -> Soldier:
	for s: Soldier in _others():
		if String(s.name) == peer_name:
			return s
	return null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Soldier.respawn_state (1: dead, waiting to respawn), 0 on builds without it.
static func _respawn_state(s: Soldier) -> int:
	var v: Variant = s.get(&"respawn_state")
	return int(v) if v != null else 0


## Every HUD message this client is shown (Hud.flash: the host's answers, "Leaving behind", the
## countdown), polled from the HUD's message label each frame: a new text, or the same one again
## (its timer restarts).
func _process(_delta: float) -> void:
	var me := _me()
	if me == null or me.player_input == null:
		return
	var hud: Variant = me.player_input.get(&"hud")
	if not (hud is Node):
		return
	var label := (hud as Node).get(&"_message") as Label
	if label == null:
		return
	var t := float((hud as Node).get(&"_message_time"))
	if label.text != "" and (label.text != _flash_text or t > _flash_time + 0.05):
		_flashes.append({"t": _now(), "text": label.text})
		_say("[shown] %s" % label.text)
	_flash_text = label.text
	_flash_time = t


## The first HUD message since `since` that contains `needle`, or "".
func _flash_since(since: float, needle: String) -> String:
	for f: Dictionary in _flashes:
		if float(f.t) >= since and String(f.text).contains(needle):
			return String(f.text)
	return ""


## The HUD messages since `since` (the countdown's left out), for a check's detail.
func _flashes_text(since: float) -> String:
	var texts: Array[String] = []
	for f: Dictionary in _flashes:
		if float(f.t) >= since and not String(f.text).begins_with("Extraction in "):
			texts.append("\"%s\"" % f.text)
	return "; ".join(texts) if not texts.is_empty() else "none"


func _read_phase() -> Dictionary:
	var path := run_dir.path_join("phase.json")
	if run_dir == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Asks the soak host for something: it reads <run>/human_ask.json while the human leads
## (tests/coop_soak.gd, _checks_tick).
func _ask(what: String, extra := {}) -> void:
	_ask_serial += 1
	var data := {"ask": what, "serial": _ask_serial, "t": _now()}
	data.merge(extra)
	var path := run_dir.path_join("human_ask.json")
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


func _run() -> void:
	main.get_node(^"Menu").join("127.0.0.1")
	if not await _wait_for(func() -> bool: return _online() and _me() != null, 120.0):
		_problem("could not join the host on port %d" % Net.port())
		_finish()
		return
	_say("joined as peer %d into the %s" % [multiplayer.get_unique_id(), "base" if _level() is BaseLevel else "zone"])
	var n := 0
	while n < deployments or (checks and n < 3 and _any_pending()):
		n += 1
		if not _in_zone():
			await _fob_ready_up()
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


## At the FOB before a deployment: the FOB ready-up (feat/fob-ready-up, Captain 2026-10-14:
## Deploy waits until every player is ready). With the soak's run folder, waits for the host to
## post "ready_up" (it has tried to Deploy with this client not ready: tests/coop_soak.gd), checks
## its own view says it's waited for (fob_ready), then presses Ready. Builds without it: nothing.
func _fob_ready_up() -> void:
	if not BaseHub.has_method(&"server_set_ready"):
		if _pending("fob_ready"):
			_check("fob_ready", "SKIPPED", "not in this build (no BaseHub.server_set_ready)")
		return
	var me_id := multiplayer.get_unique_id()
	var my_name := "Player %d" % me_id
	if run_dir == "":
		# By hand (no host phase to read): Ready once the host has a contract prepped.
		await _wait_for(func() -> bool:
			return _in_zone() or not ((BaseHub.view.get("prep", {}) as Dictionary).get("contract", {}) as Dictionary).is_empty(), 900.0)
		if not _in_zone():
			await _sleep(5.0)
			BaseHub.request("ready", [true])
			_say("pressed Ready at the FOB")
		return
	var posted := await _wait_for(func() -> bool:
		var p := _read_phase()
		return _in_zone() or (String(p.get("phase", "")) == "ready_up" and int(p.get("cycle", 0)) > _ready_cycle), 900.0)
	if _in_zone():
		if checks:
			_check("fob_ready", "FAIL", "the session deployed while this client hadn't pressed Ready")
		return
	if not posted:
		if checks:
			_check("fob_ready", "NOT RUN", "the host never posted its ready-up in 900 s")
		BaseHub.request("ready", [true])
		return
	var ph := _read_phase()
	_ready_cycle = int(ph.get("cycle", 0))
	var refused := String(ph.get("refused", ""))
	await _sleep(2.0)  # the host's view (nobody ready yet) reaches this client
	var waiting: Array = BaseHub.call(&"not_ready_names")
	var me_ready := bool(BaseHub.call(&"is_ready", me_id))
	await _sleep(3.0)
	var t := _now()
	BaseHub.request("ready", [true])
	_say("pressed Ready at the FOB (the host's Deploy had said \"%s\")" % refused)
	var deployed := await _wait_for(_in_zone, 180.0)
	if checks:
		var ok := refused.contains(my_name) and waiting.has(my_name) and not me_ready and deployed
		_check("fob_ready", "PASS" if ok else "FAIL", "the host's Deploy before this client's Ready: \"%s\"; its FOB view: waiting for %s, ready %s; after Ready: %s" % [
			refused, waiting, me_ready, "deployed in %.0f s" % (_now() - t) if deployed else "NOT deployed in 180 s"])


## Stand, walk toward the objective, hold; this deployment's checks (--checks); then call an
## extraction point here and confirm it, unless a check started the extraction already.
func _deployment(n: int) -> void:
	await _watch(STAND_S, "standing at the insertion")
	var me := _me()
	var walk := CHECKS_WALK_M if checks else WALK_M
	var target := me.global_position + Vector3(0, 0, -walk) if me else Vector3.ZERO
	_heading = Vector3(0, 0, -1)
	var objs := MapNodes.briefing(_level()).map_objectives() if MapNodes.briefing(_level()) else []
	if me and not objs.is_empty():
		var o: Vector2 = objs[0].pos
		var dir := Vector3(o.x - me.global_position.x, 0.0, o.y - me.global_position.z)
		var go := minf(walk, maxf(dir.length() - 180.0, 40.0))
		if dir.length() > 1.0:
			_heading = dir.normalized()
		target = me.global_position + _heading * go
	_goal = target
	await _watch(walk / WALK_SPEED + 10.0, "walking toward the objective")
	_goal = null
	await _watch(HOLD_S, "holding")
	if checks and _in_zone():
		if _pending("heli_lz"):
			await _check_heli_lz()
		if n >= 2 and _pending("respawn_kit"):
			await _check_respawn_kit()
		var started := false
		if _pending("extract_confirm"):
			started = await _check_extract_confirm()
		elif _pending("leave_behind"):
			started = await _check_leave_behind()
		if started or not _in_zone():
			await _wait_for(func() -> bool: return _level() is BaseLevel, 60.0)
			return
	me = _me()
	var extraction := MapNodes.extraction(_level())
	if me == null or extraction == null:
		_problem("deployment %d: no extraction to call" % n)
		return
	extraction.request_point_at(Vector2(me.global_position.x, me.global_position.z))
	_say("called an extraction point where I stand")
	var gathered := false
	var deadline := _now() + GATHER_S
	while _now() < deadline and not (_level() is BaseLevel):
		await _watch(5.0, "")
		if not is_instance_valid(extraction) or extraction.state == Extraction.State.COUNTDOWN or _level() is BaseLevel:
			gathered = true
			break
		extraction.request_confirm()  # refused until the squad is in the point
	_say("extraction: %s" % ("confirmed, the bots were in the point" if gathered else "NOT confirmed in %d s" % int(GATHER_S)))
	if not gathered:
		_problem("deployment %d: the bots never got into the extraction point with me" % n)


## Plays `seconds` (moving toward _goal if set) and logs how far each bot is every 5 s.
## `until_there`: stops once _goal is reached. `count`: the bots' distances count toward the
## summary (not during a check: the fake human walks off from a downed bot, or respawns far).
func _watch(seconds: float, what: String, until_there := false, count := true) -> void:
	if what != "":
		_say(what)
	var end := _now() + seconds
	var next_note := 0.0
	while _now() < end and _in_zone():
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
		if until_there and _goal == null:
			break
		if _now() >= next_note:
			next_note = _now() + 5.0
			_note(me, count and (_now() + 20.0 < end or _goal == null))


## Walks to `to` (at most `seconds`).
func _walk_to(to: Vector3, seconds: float, what: String) -> void:
	_goal = to
	await _watch(seconds, what, true, false)
	_goal = null


func _note(me: Soldier, count_it: bool) -> void:
	var parts: Array[String] = []
	var all_near := true
	for s: Soldier in _others():
		var d := _flat(s.global_position, me.global_position)
		parts.append("%s %.0f m%s" % [s.name, d, "" if s.vitals.is_up() else " (down)"])
		if s.vitals.is_up():
			_dist_max = maxf(_dist_max, d) if count_it else _dist_max
			all_near = all_near and d <= NEAR_M
	if count_it and not parts.is_empty():
		_samples += 1
		_samples_all_near += 1 if all_near else 0
	_say("me %s; %s" % ["up" if me.vitals.is_up() else me.vitals.condition_text(), ", ".join(parts)])


# --- Checks (--checks) ---------------------------------------------------------------------------

## The extraction points shown now (Extraction.shown_points where the build has it, else all).
static func _shown(extraction: Extraction) -> Array:
	return extraction.call(&"shown_points") if extraction.has_method(&"shown_points") else extraction.points


static func _inside_any(extraction: Extraction, pos: Vector3) -> bool:
	return _shown(extraction).any(func(p: Dictionary) -> bool: return Extraction.inside(p, pos))


## The shown point within 6 m of `at` (one this client just asked for), or {}.
static func _point_near(extraction: Extraction, at: Vector3) -> Dictionary:
	for p: Dictionary in _shown(extraction):
		if (p.pos as Vector2).distance_to(Vector2(at.x, at.z)) < 6.0:
			return p
	return {}


func _ground(pos: Vector3) -> Vector3:
	return _level().ground_point(pos) if _level() else pos


## Where to call a check's point: `centre`, moved on along `dir` (30 m at a time) while another
## shown point lies within 50 m of it: overlapping points would make "the point this player
## stands in" (Extraction.point_of_player) another one than the check's.
func _clear_spot(extraction: Extraction, centre: Vector3, dir: Vector3) -> Vector3:
	for step in 5:
		if not _shown(extraction).any(func(p: Dictionary) -> bool: return (p.pos as Vector2).distance_to(Vector2(centre.x, centre.z)) < 50.0):
			break
		centre = _ground(centre + dir * 30.0)
	return centre


## Every other player who is up (not `except`) stands inside `point`.
func _others_up_inside(point: Dictionary, except: Soldier = null) -> bool:
	return _others().all(func(s: Soldier) -> bool:
		return s == except or not s.vitals.is_up() or _respawn_state(s) == 1 or Extraction.inside(point, s.global_position))


func _where_others(point: Dictionary) -> String:
	var parts: Array[String] = []
	for s: Soldier in _others():
		var d := (point.pos as Vector2).distance_to(Vector2(s.global_position.x, s.global_position.z))
		parts.append("%s %.0f m from its centre%s" % [s.name, d, "" if s.vitals.is_up() else " (down)"])
	return ", ".join(parts)


## heli_lz (fix/coop-extraction, Captain 2026-10-14: "when heli extract is selected make sure
## it's the only one shown"): calls a helicopter extraction 40 m ahead (the command menu's
## Support > Extraction, "here"), waits for its LZ, checks this client shows only that point
## (none while it has no LZ yet), sends it home and checks every point shows again.
func _check_heli_lz() -> void:
	var extraction := MapNodes.extraction(_level())
	var me := _me()
	if extraction == null or me == null or not me.vitals.is_up() or not extraction.is_active():
		_check("heli_lz", "NOT RUN", "no active extraction, or the fake human is down")
		return
	if not extraction.has_method(&"shown_points") or extraction.get(&"heli_point") == null:
		_check("heli_lz", "SKIPPED", "not in this build (no Extraction.shown_points / heli_point)")
		return
	var spot := _ground(me.global_position + _heading * 40.0)
	var t := _now()
	me._server_squad_command.rpc_id(1, "support:extraction:here", spot, PackedStringArray())
	_say("called a helicopter extraction 40 m ahead")
	var seen := {"no_lz": 0, "no_lz_shown": 0}  # samples with the call's LZ not set yet, and of those how many showed a point
	var got := await _wait_for(func() -> bool:
		var hp_now := int(extraction.get(&"heli_point"))
		if hp_now == 0:
			seen["no_lz"] += 1
			seen["no_lz_shown"] += 0 if _shown(extraction).is_empty() else 1
		return hp_now > 0 and not extraction.point_by_id(hp_now).is_empty(), 45.0)
	if not got:
		_check("heli_lz", "NOT RUN", "no helicopter LZ in 45 s (heli_point %d; shown: %s)" % [int(extraction.get(&"heli_point")), _flashes_text(t)])
		_send_heli_home(me)
		return
	var hp := int(extraction.get(&"heli_point"))
	var shown := _shown(extraction).map(func(p: Dictionary) -> String: return "%d %s" % [int(p.id), p.get("name", "")])
	var only_lz := shown.size() == 1 and int(_shown(extraction)[0].id) == hp
	var hidden := extraction.points.size() - shown.size()
	_say("helicopter LZ: point %d; shown %s of %d point(s)" % [hp, shown, extraction.points.size()])
	await _sleep(2.0)
	_send_heli_home(me)
	var back := await _wait_for(func() -> bool:
		return int(extraction.get(&"heli_point")) < 0 and _shown(extraction).size() == extraction.points.size(), 30.0)
	var ok: bool = only_lz and back and int(seen.no_lz_shown) == 0
	var before_lz := "not seen" if int(seen.no_lz) == 0 else ("nothing shown" if int(seen.no_lz_shown) == 0
		else "a point shown in %d of %d samples" % [int(seen.no_lz_shown), int(seen.no_lz)])
	var home := "every point shown again (%d)" % extraction.points.size() if back else "still hiding (heli_point %d, shown %d of %d)" % [
		int(extraction.get(&"heli_point")), _shown(extraction).size(), extraction.points.size()]
	_check("heli_lz", "PASS" if ok else "FAIL", "LZ point %d: shown %s, %d other point(s) hidden%s; before its LZ: %s; sent home: %s" % [
		hp, shown, hidden, "" if hidden > 0 else " (the zone had no other point to hide)", before_lz, home])


func _send_heli_home(me: Soldier) -> void:
	if is_instance_valid(me):
		me._server_squad_command.rpc_id(1, "support:extraction:cancel", me.global_position, PackedStringArray())
		_say("sent the helicopter home")


## Gets out of every shown extraction point (a preset one may lie on the insertion): 40 m
## steps along the heading, then sideways. Whether it's outside them all.
func _leave_points(extraction: Extraction) -> bool:
	for step in 4:
		var me := _me()
		if me == null or not _inside_any(extraction, me.global_position):
			return me != null
		var dir := _heading if step < 2 else _heading.cross(Vector3.UP)
		await _walk_to(me.global_position + dir * 40.0, 15.0, "out of the extraction point")
	return _me() != null and not _inside_any(extraction, _me().global_position)


## Confirms (as the extraction panel's button does) until the countdown starts or `tries` run
## out; returns how many it took (0: it never started).
func _confirm_until_countdown(extraction: Extraction, tries: int) -> int:
	for i in tries:
		extraction.request_confirm()
		if await _wait_for(func() -> bool: return not _in_zone() or extraction.state == Extraction.State.COUNTDOWN, 3.5):
			return i + 1
	return 0


## extract_confirm (fix/coop-extraction, Captain 2026-10-14: any player inside a point
## confirms): calls a point ahead, confirms from outside it (refused, nothing starts), walks in,
## and once the bots are in confirms again: the countdown starts. Returns whether it started.
func _check_extract_confirm() -> bool:
	var extraction := MapNodes.extraction(_level())
	var me := _me()
	if extraction == null or me == null or not me.vitals.is_up() or not extraction.is_active():
		_check("extract_confirm", "NOT RUN", "no active extraction, or the fake human is down")
		return false
	if not extraction.has_method(&"point_of_player"):
		_check("extract_confirm", "SKIPPED", "not in this build (no Extraction.point_of_player: only the host confirms)")
		return false
	if not await _leave_points(extraction):
		_check("extract_confirm", "NOT RUN", "couldn't get out of the extraction points to start outside one")
		return false
	me = _me()
	var centre := _clear_spot(extraction, _ground(me.global_position + _heading * CHECK_POINT_M), _heading)
	var t := _now()
	extraction.request_point_at(Vector2(centre.x, centre.z))
	if not await _wait_for(func() -> bool: return not _point_near(extraction, centre).is_empty(), 15.0):
		_check("extract_confirm", "NOT RUN", "the point asked for never showed (shown: %s)" % _flashes_text(t))
		return false
	if _inside_any(extraction, _me().global_position):
		_check("extract_confirm", "NOT RUN", "the fake human stood inside a point when it meant to confirm from outside")
		return false
	t = _now()
	extraction.request_confirm()
	await _wait_for(func() -> bool: return _flash_since(t, "inside an extraction point") != "" or extraction.state != Extraction.State.ACTIVE, 6.0)
	await _sleep(1.0)
	var refusal := _flash_since(t, "inside an extraction point")
	var stayed := extraction.state == Extraction.State.ACTIVE
	var outside_ok := refusal != "" and stayed
	_say("confirm from outside: %s, extraction %s" % ["refused: \"%s\"" % refusal if refusal != "" else "no refusal shown", "still waiting" if stayed else "STARTED"])
	if not stayed:
		_check("extract_confirm", "FAIL", "a confirm from %.0f m outside the point started the extraction (shown: %s)" % [CHECK_POINT_M, _flashes_text(t)])
		return true
	var point := _point_near(extraction, centre)
	await _walk_to(centre, 60.0, "into the extraction point")
	var all_in := await _wait_for(func() -> bool: return _in_zone() and _others_up_inside(point), 75.0)
	if not all_in or not _in_zone():
		_check("extract_confirm", "NOT RUN" if outside_ok else "FAIL", "outside: %s; inside: the bots never all got into the point in 75 s (%s)" % [
			"refused as it should be" if outside_ok else "NO refusal shown (shown: %s)" % _flashes_text(t), _where_others(point) if _in_zone() else "left the zone"])
		return false
	var t2 := _now()
	var took := await _confirm_until_countdown(extraction, 4)
	var ok := outside_ok and took > 0
	_check("extract_confirm", "PASS" if ok else "FAIL", "outside: %s; inside with the bots: %s (shown: %s)" % [
		"refused (\"%s\"), still waiting" % refusal if outside_ok else "NO refusal shown (shown: %s)" % _flashes_text(t),
		"the countdown started after %d confirm(s)" % took if took > 0 else "NO countdown after 4 confirms", _flashes_text(t2)])
	return took > 0


## respawn_kit (fix/respawn-own-kit, Captain 2026-10-14: "respawn with the kit you had on.
## delete old player/bot bodies"): dies through dev tools' hurt (the K key's request), waits for
## the respawn, and compares what it wears and carries with before (medical items a bot used on
## it in between may be gone; the hands item drops); no new player body (one with a gear marker)
## may carry its name or lie where it fell.
func _check_respawn_kit() -> void:
	var me := _me()
	if me == null or not me.vitals.is_up():
		_check("respawn_kit", "NOT RUN", "the fake human is down or gone")
		return
	if (me.get_script() as Script).get_script_constant_map().has("DEFAULT_KIT") or me.get(&"respawn_state") == null:
		_check("respawn_kit", "SKIPPED", "not in this build (a dead player respawns in Soldier.DEFAULT_KIT and leaves a body)")
		return
	var label := me.display_name()
	var slots_before: Dictionary = me.inventory.slots.duplicate()
	var gear_before := _gear(me)
	var bodies_before := _player_bodies()
	var fell_at := me.global_position
	var died := false
	for attempt in 4:
		me = _me()
		if me == null:
			break
		if _respawn_state(me) == 1 or me.vitals.is_dead():
			died = true
			break
		_say("dying (dev tools' hurt, 1000)")
		me._server_debug_hurt.rpc_id(1, 1000.0)
		died = await _wait_for(func() -> bool: return _me() != null and (_respawn_state(_me()) == 1 or _me().vitals.is_dead()), 4.0)
		if died:
			break
	if not died and _me() != null and _me().has_method(&"can_give_up"):
		# Only down: give up as the give-up key does, once it may.
		if await _wait_for(func() -> bool: return _me() != null and bool(_me().call(&"can_give_up")), 25.0):
			_say("giving up (the give-up key's request)")
			_me().rpc_id(1, &"_server_give_up")
			died = await _wait_for(func() -> bool: return _me() != null and (_respawn_state(_me()) == 1 or _me().vitals.is_dead()), 5.0)
	if not died:
		_check("respawn_kit", "NOT RUN", "couldn't die: dev tools' hurt didn't kill (%s)" % (_me().vitals.condition_text() if _me() else "gone"))
		return
	var back := await _wait_for(func() -> bool: return _me() != null and _respawn_state(_me()) != 1 and _me().vitals.is_up(), 45.0)
	if not back:
		_check("respawn_kit", "FAIL", "never came back in 45 s after dying")
		return
	await _sleep(3.0)  # the inventory's replication settles
	me = _me()
	var slot_diff: Array[String] = []
	for slot: Variant in slots_before:
		if me.inventory.slots.get(slot, &"") != slots_before[slot]:
			slot_diff.append("%s %s -> %s" % [slot, slots_before[slot], me.inventory.slots.get(slot, &"")])
	var gear_after := _gear(me)
	var changed: Array[String] = []
	var used: Array[String] = []
	for id: Variant in _union(gear_before, gear_after):
		var d := int(gear_after.get(id, 0)) - int(gear_before.get(id, 0))
		if d == 0:
			continue
		var item := ItemDB.get_item(StringName(str(id)))
		if d < 0 and item != null and item.type in ["medical", "tq"]:
			used.append("%s %d" % [id, d])
		else:
			changed.append("%s %+d" % [id, d])
	var new_bodies := _player_bodies().filter(func(b: Soldier) -> bool: return b not in bodies_before)
	var mine := new_bodies.filter(func(b: Soldier) -> bool: return b.body_label == label or _flat(b.global_position, fell_at) < 5.0)
	var ok := slot_diff.is_empty() and changed.is_empty() and mine.is_empty()
	var bodies_text := "none of it" if mine.is_empty() else "A PLAYER BODY of it: %s" % [
		mine.map(func(b: Soldier) -> String: return "%s at %.0f m from where it fell" % [b.body_label, _flat(b.global_position, fell_at)])]
	_check("respawn_kit", "PASS" if ok else "FAIL", "respawned %.0f m from where it fell; worn: %s; carried: %s%s; bodies: %s" % [
		_flat(me.global_position, fell_at), "the same (%s)" % _slots_line(me) if slot_diff.is_empty() else "CHANGED %s" % [slot_diff],
		"the same" if changed.is_empty() else "CHANGED %s" % [changed], " (medical used on it: %s)" % [used] if not used.is_empty() else "",
		bodies_text])


## What `s` wears and carries ({item id: count}, Roster.gear_counts), the hands item left out.
static func _gear(s: Soldier) -> Dictionary:
	var state: Dictionary = Roster.json_safe(s.inventory.net_state)
	state.erase("hands")
	return Roster.gear_counts(state)


static func _union(a: Dictionary, b: Dictionary) -> Array:
	var out := a.keys()
	for k: Variant in b:
		if k not in out:
			out.append(k)
	return out


static func _slots_line(s: Soldier) -> String:
	var slots: Dictionary = s.inventory.slots
	return "carrier %s, plates %s/%s, helmet %s, primary %s" % [slots.get(&"vest", &"-"), slots.get(&"plate_front", &"-"),
		slots.get(&"plate_back", &"-"), slots.get(&"helmet", &"-"), slots.get(&"primary", &"-")]


## Dead players' bodies in the level (the ones with a gear marker).
func _player_bodies() -> Array:
	var bodies: Variant = _level().get(&"bodies") if _level() else null
	if not (bodies is Node):
		return []
	return (bodies as Node).get_children().filter(func(b: Node) -> bool: return b is Soldier and (b as Soldier).has_gear_marker)


## leave_behind (fix/coop-extraction, Captain 2026-10-14: players down or dead outside the point
## don't block; the first confirm warns who'd be left, a second extracts without them): asks the
## soak host to knock a bot player out and keep them down, calls a point LEAVE_POINT_M from them,
## walks in with the other bots and confirms twice. Returns whether the extraction started.
func _check_leave_behind() -> bool:
	var extraction := MapNodes.extraction(_level())
	var me := _me()
	if extraction == null or me == null or not me.vitals.is_up() or not extraction.is_active():
		_check("leave_behind", "NOT RUN", "no active extraction, or the fake human is down")
		return false
	if not extraction.has_method(&"point_of_player"):
		_check("leave_behind", "SKIPPED", "not in this build (no Extraction.point_of_player: a player down outside the point blocks it)")
		return false
	if run_dir == "":
		_check("leave_behind", "NOT RUN", "needs the soak's host to knock a bot out (--run)")
		return false
	# The bots come back to it first (after its respawn they may be far off).
	await _wait_for(func() -> bool:
		var at := _me()
		return at == null or _others().all(func(s: Soldier) -> bool: return not s.vitals.is_up() or _flat(s.global_position, at.global_position) < 35.0), 120.0)
	me = _me()
	if me == null or not _in_zone():
		_check("leave_behind", "NOT RUN", "the fake human left the zone")
		return false
	var victim: Soldier = null
	for s: Soldier in _others():
		if s.vitals.is_up() and _respawn_state(s) != 1 and (victim == null or (String(victim.name) == "1" and String(s.name) != "1")):
			victim = s  # a client's bot rather than the host's own
	if victim == null:
		_check("leave_behind", "NOT RUN", "no bot player up to knock out")
		return false
	var victim_name := String(victim.name)
	_ask("down", {"peer": int(victim_name)})
	_say("asked the host to knock out Player %s" % victim_name)
	if not await _wait_for(func() -> bool: return _player_named(victim_name) != null and not _player_named(victim_name).vitals.is_up(), 25.0):
		_ask("release")
		_check("leave_behind", "NOT RUN", "Player %s never went down (the host's knock-out)" % victim_name)
		return false
	victim = _player_named(victim_name)
	me = _me()
	if victim == null or me == null:
		_ask("release")
		_check("leave_behind", "NOT RUN", "Player %s or the fake human is gone" % victim_name)
		return false
	var at := victim.body_point()
	var away := Vector3(me.global_position.x - at.x, 0.0, me.global_position.z - at.z)
	var dir := away.normalized() if away.length() > 1.0 else _heading
	var centre := _clear_spot(extraction, _ground(at + dir * LEAVE_POINT_M), dir)
	extraction.request_point_at(Vector2(centre.x, centre.z))
	if not await _wait_for(func() -> bool: return not _point_near(extraction, centre).is_empty(), 15.0):
		_ask("release")
		_check("leave_behind", "NOT RUN", "the point asked for never showed")
		return false
	var point := _point_near(extraction, centre)
	await _walk_to(centre, 70.0, "to a point %.0f m from the downed Player %s" % [LEAVE_POINT_M, victim_name])
	await _wait_for(func() -> bool: return _in_zone() and _others_up_inside(point, _player_named(victim_name)), 75.0)
	victim = _player_named(victim_name)
	me = _me()
	var why_not := ""
	if me == null or not _in_zone():
		why_not = "the fake human left the zone"
	elif not me.vitals.is_up() or not Extraction.inside(point, me.global_position):
		why_not = "the fake human isn't up inside the point"
	elif victim == null:
		why_not = "Player %s is gone" % victim_name
	elif victim.vitals.is_up() and _respawn_state(victim) != 1:
		why_not = "Player %s is up again" % victim_name
	elif Extraction.inside(point, victim.body_point()):
		why_not = "Player %s lies inside the point" % victim_name
	elif not _others_up_inside(point, victim):
		why_not = "the other bots never all got into the point (%s)" % _where_others(point)
	if why_not != "":
		_ask("release")
		_check("leave_behind", "NOT RUN", why_not)
		return false
	var off_m := (point.pos as Vector2).distance_to(Vector2(victim.body_point().x, victim.body_point().z))
	var t := _now()
	extraction.request_confirm()
	await _wait_for(func() -> bool: return _flash_since(t, "Leaving behind") != "" or extraction.state != Extraction.State.ACTIVE, 5.0)
	var warning := _flash_since(t, "Leaving behind")
	var held := extraction.state == Extraction.State.ACTIVE
	var names_them := warning.contains("Player %s" % victim_name)
	extraction.request_confirm()
	var started := await _wait_for(func() -> bool: return not _in_zone() or extraction.state == Extraction.State.COUNTDOWN, 6.0)
	var ok := warning != "" and names_them and held and started
	var report := ""
	if started:
		# Who the extraction left behind (Extraction.last_report, sent to every peer at the end).
		await _wait_for(func() -> bool: return not _in_zone() or not is_instance_valid(extraction) or not extraction.last_report.is_empty(), 20.0)
		if is_instance_valid(extraction) and not extraction.last_report.is_empty():
			var left: Array = extraction.last_report.get("left", [])
			var listed := left.any(func(e: Dictionary) -> bool: return bool(e.get("player", false)) and str(e.get("peer", "")) == victim_name)
			report = "; the report lists Player %s left behind: %s" % [victim_name, "yes" if listed else "NO (left: %s)" % [
				left.map(func(e: Dictionary) -> String: return String(e.get("name", "?")))]]
	_ask("release")
	_check("leave_behind", "PASS" if ok else "FAIL", "Player %s down %.0f m from the point's centre; first confirm: %s%s; second: %s%s (shown: %s)" % [
		victim_name, off_m, "\"%s\"" % warning if warning != "" else "NO \"Leaving behind\" warning",
		"" if held else " and the extraction STARTED at once", "the countdown started" if started else "NO countdown", report, _flashes_text(t)])
	return started or not held


func _finish() -> void:
	var share := float(_samples_all_near) / float(maxi(_samples, 1))
	_say("summary: %d samples, every bot within %d m in %.0f%% of them; farthest bot %.0f m" % [_samples, int(NEAR_M), share * 100.0, _dist_max])
	if _samples > 0 and share < 0.7:
		_problem("the bots were not with me: all within %d m in only %.0f%% of the samples" % [int(NEAR_M), share * 100.0])
	if checks:
		for id: String in CHECK_IDS:
			if not _results.has(id):
				_check(id, "NOT RUN", "the run ended before it")
		var lines := PackedStringArray()
		for id: String in CHECK_IDS:
			lines.append("%s %s" % [id, "/".join(PackedStringArray(_results.get(id, [])))])
		_say("checks: %s" % ", ".join(lines))
	_say("finished: %d problem(s)%s" % [_problems.size(), (": " + "; ".join(_problems)) if not _problems.is_empty() else ""])
	var summary := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	if summary:
		summary.store_string(JSON.stringify({"problems": _problems, "samples": _samples, "near_share": share, "farthest_m": _dist_max}))
		summary.close()
	if _online():
		Net.leave()
	await get_tree().create_timer(0.5).timeout
	var failed := _results.values().any(func(rs: Array) -> bool: return "FAIL" in rs)
	get_tree().quit(0 if _problems.is_empty() and not failed else 1)
