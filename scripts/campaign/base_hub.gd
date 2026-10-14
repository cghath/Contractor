extends Node
## Autoload BaseHub: the company's home and its people at runtime (wave 4, W12). The host
## owns the campaign's "roster", "hiring" and "base" sections (Campaign) and runs everything
## that changes them; every peer gets a copy (`view`, sent whole on each change and to late
## joiners) for the base screen (BaseUI). Clients ask through request(), which the host checks.
##
## What it runs:
## - The hub: the base level (BaseLevel) with the armory stash, the muster line and the
##   terminals; hiring, medbay, shop purchases, squad picks, days passing (recovery, the
##   hiring board, wages).
## - Deployments: server_deploy() takes the picked squad (RosterDeployment) into a zone level;
##   CompoundLevel's hooks spawn the roster's people there in their own gear
##   (server_spawn_roster_squadmate); server_end_deployment() settles who came back, who's
##   MIA and who died, then returns everyone to the hub.
## - Level switching for the whole session (server_switch_level): every peer swaps the level
##   in place (LevelSwitch.load_level), players keep their gear across (their main
##   character's, or their stand-in's). A deployment goes to the compound or to a zone
##   (a ZoneLevel made from its definition: begin_prep's `level_info`).
##
## Entry points: the main menu's campaign button (prepare_session), begin_prep() (the
## contract board, when a contract is accepted), server_deploy(), server_end_deployment() (the
## map's extraction), server_recover_member() / server_write_off_member() (recovery
## contracts). A non-campaign session (the compound as before, and every older suite) never
## sets campaign_running, so none of this touches it.
##
## The loop (wave 4B, part 1): one bank and one clock, the Economy autoload's (the roster's
## wages go into its weekly bill, the shop's purchases into the stash, days pass through
## Economy.advance_days and the roster and hiring board follow day_advanced). A contract
## accepted on the board starts the prep (begin_prep_contract); deploying takes the squad into
## the contract's zone, where the briefing opens for everyone (on the zone's own map); its
## start makes the contract's objectives live (Contracts.server_start_deployment) and the
## briefing moves the squad in and opens extraction. Extraction's end (end_deployment, an
## Extraction.END_GROUP handler) settles it once: the debrief (Contracts.server_end_deployment:
## pay, clawback, reputation, days), then the roster (server_end_deployment: MIA and recovery
## contracts, gear home), then back to the base. A squadmate left behind is waiting where they
## were left when the squad deploys on their recovery contract, and joins whoever finds them.
##
## Joining: the host decides which level a joining client plays in. LevelSwitch's handshake
## (SceneMultiplayer's authentication step, before anything replicates to the client) sends the
## host's level and whether a campaign is running, after a switch in progress (switch_pending);
## the client follows the campaign mode (follow_host) and swaps to that level first. So a plain
## Join reaches a campaign host at the base or deployed, and a late joiner sees the same level
## as everyone else.

## The base screen's copy of the campaign changed (every peer).
signal view_changed
## A message for this machine's player (an answer to a request).
signal note(text: String)
## Host: a deployment was settled (the report RosterDeployment.resolve returns).
signal deployment_ended(report: Dictionary)
## Every peer: the session's level was swapped (server_switch_level).
signal level_switched(new_level: CompoundLevel)

const BASE_SCENE := "res://scenes/levels/base_fob.tscn"
const COMPOUND_SCENE := "res://scenes/levels/compound.tscn"
const SQUAD_SIZE := CompoundLevel.SQUAD_SIZE
## The zone a deployment goes to when nothing says otherwise. A campaign's zone saves are its
## own (zone_save_id), apart from the plain session's and other campaigns'.
const DEFAULT_ZONE_ID := "compound_01"
## Why Deploy waits (the button's tooltip and server_deploy's answer).
const NO_CONTRACT := "Prep a contract first"
## A squadmate left behind (a recovery contract's) joins the squad when a player comes this
## close (metres). Proposed.
const FOUND_M := 4.0
## How often the host reads the stash back from the hub's world items.
const STASH_POLL_S := 1.0
## Proposed: what a new company owns besides its hiring budget (enough to kit two players).
## Its carriers come with the base kit's MOLLE pouches on (BaseArmory.kitted_carrier_state),
## so magazines and the tourniquet go into them when picked up.
const STARTING_STASH := [["plate_carrier", 2], ["plate_ceramic_l4", 4], ["helmet", 2], ["assault_pack", 2], ["m4a1", 2],
	["mag_556", 12], ["ifak", 4], ["tourniquet", 2], ["smoke_grenade", 2], ["frag_grenade", 2]]
## Debug builds: Shift+End extracts everyone within this many metres of the host (until the map's
## extraction calls server_end_deployment).
const DEBUG_EXTRACT_M := 60.0
## A level switch waits at most this long for clients to stop sending (server_switch_level).
const SWITCH_WAIT_S := 1.0
## A roster squadmate removed this frame comes back for a free slot after this long (their
## body's name is taken until it's freed).
const REFILL_RETRY_S := 0.2

## A campaign session is running (the hub or a deployment). Set on every peer.
var campaign_running := false
## This machine's player profile (their one main character). Set before joining; defaults
## to one made from the machine's id.
var local_profile := ""
## Every peer: the campaign as the base screen shows it (build_view).
var view: Dictionary = {}
## Host: randomness for skill growth.
var rng := RandomNumberGenerator.new()

var _profiles := {}      # host: peer id -> player key
var _gear_applied := {}  # host: peer ids whose gear is on their body in this level
## Host: the campaign as it stood just before the running deployment left the base (server_deploy),
## so the Escape menu's "Return to Base (revert)" can put everything back (Captain, 2026-10-12).
var _before_deploy := {}
var _broadcast_queued := false
var _stash_poll := 0.0
var _ui: BaseUI
var _switch_to := {}       # host: the level (level_info) a switch is waiting to swap in
var _switch_zone := ""     # host: and the zone save it goes with ("" keeps GameState.zone_id)
var _switch_waiting := {}  # host: peers not ready for it yet
var _switch_serial := 0
var _zone_before := ""     # host: GameState.zone_id before the campaign took over (restored after)
var _host_notice := ""     # host: what loading the campaign has to tell the host (shown again on open_ui)


func _ready() -> void:
	rng.randomize()
	add_to_group(Extraction.END_GROUP)  # end_deployment
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.session_ended.connect(_on_session_ended)
	Campaign.changed.connect(func(_name: StringName) -> void: _queue_broadcast())
	Economy.changed.connect(_queue_broadcast)
	Economy.day_advanced.connect(_on_day_advanced)
	Contracts.contract_accepted.connect(_on_contract_accepted)
	Contracts.contract_closed.connect(_on_contract_closed)


# --- Campaign state -------------------------------------------------------------------------

func roster() -> Dictionary:
	return Campaign.section(&"roster")


func hiring() -> Dictionary:
	return Campaign.section(&"hiring")


func base() -> Dictionary:
	return Campaign.section(&"base")


## The campaign day: the economy's clock, the only one.
func day() -> int:
	return Economy.day()


## The base has a campaign loaded or started (a save from before the one clock kept its own
## "day" here).
func started() -> bool:
	return base().has("started") or base().has("day")


func member(mid: String) -> Dictionary:
	return Roster.get_member(roster(), mid)


func stash() -> Array:
	if not base().has("stash"):
		base()["stash"] = []
	return base()["stash"]


## Host: a fresh campaign (the save for Campaign.campaign_id and its zone saves are deleted):
## a new economy and contract board (day 1, the starting cash), the starting stash, an empty
## roster and a hiring board drawn from `hiring_seed` (random if negative).
func new_campaign(hiring_seed := -1) -> void:
	Campaign.reset_campaign()
	_delete_zone_saves()
	Contracts.new_full_campaign()
	var b := base()
	b["started"] = true
	b["stash"] = []
	for pair: Array in STARTING_STASH:
		var id := StringName(pair[0])
		if ItemDB.get_item(id).slot == &"vest":
			for i in int(pair[1]):
				BaseArmory.add(b.stash, id, 1, BaseArmory.kitted_carrier_state(id))
		else:
			BaseArmory.add(b.stash, id, int(pair[1]))
	b["prep"] = _empty_prep()
	var h := hiring()
	h["seed"] = hiring_seed if hiring_seed >= 0 else randi()
	h["refresh"] = 0
	Hiring.redraw(h, day())
	Roster.members(roster())
	Roster.players(roster())
	_hook_economy(true)
	_changed_all()


## Host: the saved campaign for Campaign.campaign_id, or a new one if there's none. A save that
## can't be read isn't taken as leave to start over on top of it (audit A1-01): load_campaign
## keeps its files aside and falls back on its backup; only with nothing readable does a new
## campaign start, its zone saves kept aside too, and the host is told (note, and on open_ui).
func load_or_new() -> void:
	var loaded := Campaign.load_campaign()
	_host_notice = Campaign.load_notice
	if not loaded and Campaign.last_load == Campaign.Loaded.UNREADABLE:
		set_aside_zone_saves()
	if _host_notice != "":
		note.emit(_host_notice)
	if not loaded or not started():
		new_campaign()
	elif base().has("day"):
		# A save from before the one clock: the base's own day and wage count give way to the
		# economy's (which a save that never had one starts, below).
		for key: String in ["day", "wages_owed", "wage_days", "stub_funds", "stub_ledger", "recovery_requests"]:
			base().erase(key)
		base()["started"] = true
	Contracts.ensure_campaign()
	_hook_economy(true)
	var dep := RosterDeployment.active(roster())
	if not dep.is_empty():
		# Saved mid-deployment and not ended: everyone who went is back as they left the base.
		for mid: String in dep.squad:
			var m := member(mid)
			if not m.is_empty() and dep.get("fallen", {}).has(mid):
				m["status"] = Roster.DEAD
				m["gear"] = {}
				Roster.add_history(m, day(), "Killed in action in %s" % dep.get("zone_id", "?"))
		roster()["deployment"] = {}
		Contracts.server_abandon_deployment()
	_changed_all()


## Host: saves the campaign (the hub's stash and people read back first). Never one that was
## never loaded or started (no "day"): that would write an empty campaign over the save.
## Returns whether it was saved (audit A1-04: Campaign.save_error says why not).
func server_save() -> bool:
	if not started():
		push_warning("BaseHub: no campaign loaded; not saving over %s" % Campaign.save_path())
		return false
	_read_back_base()
	return Campaign.save_campaign()


## Host: what to tell the player after server_save returned `saved`.
static func save_note(saved: bool) -> String:
	return "Campaign saved" if saved else "Campaign NOT saved: %s" % (Campaign.save_error if Campaign.save_error != "" else "no campaign loaded")


## The zone save (GameState.zone_id) of the campaign's zone `zone_id`: each campaign keeps its
## own zones, apart from the plain session's ("compound_01") and other campaigns'.
func zone_save_id(zone_id: String) -> String:
	return "%s__%s" % [Campaign.campaign_id, zone_id]


func base_zone_id() -> String:
	return zone_save_id("fob")


## Deletes every zone save of the current campaign (zone_save_id), with their backups and
## interrupted writes (a backup left behind would load as the new campaign's zone).
func _delete_zone_saves() -> void:
	for path in _zone_save_files():
		DirAccess.remove_absolute(path)


## Moves every zone save of the current campaign aside (GameState.set_aside): the campaign they
## belong to couldn't be read, and a new one starting in its name mustn't load them or delete them.
func set_aside_zone_saves() -> void:
	for path in _zone_save_files():
		push_warning("BaseHub: kept %s aside (its campaign couldn't be read)" % GameState.set_aside(path, "orphaned").get_file())


## The current campaign's zone save files: each save, backup and interrupted write.
func _zone_save_files() -> Array[String]:
	var out: Array[String] = []
	var prefix := zone_save_id("")
	if not DirAccess.dir_exists_absolute(GameState.SAVE_DIR):
		return out
	for file in DirAccess.get_files_at(GameState.SAVE_DIR):
		if file.begins_with(prefix) and (file.ends_with(".json") or file.ends_with(".json.bak") or file.ends_with(".json.tmp")):
			out.append("%s/%s" % [GameState.SAVE_DIR, file])
	return out


static func _empty_prep() -> Dictionary:
	return {"squad": [], "contract": {}, "zone_kind": RosterDeployment.CONTRACT, "zone_id": "", "scene": "", "level": {}}


func _prep() -> Dictionary:
	if not base().has("prep"):
		base()["prep"] = _empty_prep()
	return base()["prep"]


## Host (the contract board): a contract was accepted; the prep phase at the base starts.
## `contract` is kept as it is and handed to the deployment; `zone_kind` is "contract" or
## "hot"; `zone_id` and `scene` name the zone's save and level ("" for the test compound);
## `level_info`, a level_info() such as {"level": "zone", "def": ZoneDef.get_def(id)}, names
## the level instead of `scene` (a zone needs its definition). The squad pick starts from the
## default (RosterDeployment.auto_squad) if it's empty.
func begin_prep(contract: Dictionary, zone_kind := RosterDeployment.CONTRACT, zone_id := "", scene := "", level_info := {}) -> void:
	var prep := _prep()
	prep["contract"] = contract.duplicate(true)
	prep["zone_kind"] = zone_kind
	prep["zone_id"] = zone_id
	prep["scene"] = scene
	prep["level"] = level_info.duplicate(true)
	if (prep.squad as Array).is_empty():
		prep["squad"] = RosterDeployment.auto_squad(roster(), SQUAD_SIZE - _player_count())
	_changed(&"base")


## Host: preps the held contract `cid` for the next deployment (the board: "Prepare
## deployment", and a contract accepted with none in prep). The prep keeps its public view
## (it goes out in the view; the real threat stays with Contracts) and deploys into the
## contract zone's generated layout (MissionRegistry.zone_def). Returns "" or why not.
func begin_prep_contract(cid: String) -> String:
	var c := Contracts.contract(cid)
	if c.is_empty() or c.get("state") != Contracts.ACCEPTED:
		return "No such contract held"
	if RosterDeployment.is_running(roster()):
		return "A deployment is already running"
	var zone_id := String(c.get("zone_id", ""))
	var layout := MissionRegistry.zone_def(zone_id)
	begin_prep(ContractGen.public_view(c), String(c.get("zone_kind", RosterDeployment.CONTRACT)), zone_id, "",
		{"level": "zone", "def": layout} if not layout.is_empty() else {})
	return ""


## The contract in prep ({} if none).
func prep_contract() -> Dictionary:
	return _prep().get("contract", {})


func _on_contract_accepted(cid: String) -> void:
	if campaign_running and multiplayer.is_server() and prep_contract().is_empty():
		begin_prep_contract(cid)
		note.emit("Prepping %s: pick the squad and kit up, then deploy" % String(Contracts.contract(cid).get("title", cid)))


## The member ids standing at the hub's muster line: everyone available, in hiring order.
func muster_ids() -> Array[String]:
	return Roster.available_ids(roster())


## Host: a member's gear is now `net_state` (read back from their body).
func server_store_member_gear(mid: String, net_state: Dictionary) -> void:
	var m := member(mid)
	if not m.is_empty():
		m["gear"] = Roster.json_safe(net_state.duplicate(true))


# --- Levels -----------------------------------------------------------------------------------

func level() -> CompoundLevel:
	return CompoundLevel.current(self)


func in_base() -> bool:
	return level() is BaseLevel


## A deployment is running and this is the host.
func deployment_running() -> bool:
	return campaign_running and multiplayer.is_server() and RosterDeployment.is_running(roster())


## Host hook (CompoundLevel._spawn_squadmate): in a campaign the squad's AI are the company's
## people (server_spawn_roster_squadmate), never generated ones; outside a deployment nobody.
func campaign_squad() -> bool:
	return campaign_running and multiplayer.is_server()


## Main menu (before hosting): this session is the campaign. Loads the campaign save (or
## starts one) and swaps the level for the base hub. Clients don't call this: they follow the
## host when they join (follow_host). Undo with cancel_session (hosting failed).
func prepare_session() -> void:
	if not campaign_running:
		_zone_before = GameState.zone_id
	campaign_running = true
	load_or_new()
	GameState.zone_id = base_zone_id()
	if not in_base():
		_swap_level({"level": "base"})


## This machine leaves campaign mode outside a session (hosting or joining failed, or a plain
## session starts): back to the plain compound and its zone save, with nothing of the
## campaign left to save.
func cancel_session() -> void:
	if Net.is_hosting():
		return
	campaign_running = false
	_hook_economy(false)
	view = {}
	_restore_zone_id()
	var lvl := level()
	if lvl and String(lvl.level_info().get("level", "")) != "compound":
		_swap_level({"level": "compound"})


func _restore_zone_id() -> void:
	if _zone_before != "":
		GameState.zone_id = _zone_before
		_zone_before = ""


## Host: every peer swaps the running level for `level_info` (a level_info() Dictionary, or a
## level scene's path: LevelSwitch.info_for_scene), with `zone_id` as its zone save ("" keeps
## GameState.zone_id); the new level then starts as if hosted, and every connected player is
## added back (with their role and their gear). With
## clients connected it first asks them to stop sending their own player's movement (which
## would otherwise reach the host for a level it no longer has) and swaps once they all say so,
## or after SWITCH_WAIT_S: watch `level_switched`. Alone, it swaps at once.
func server_switch_level(level_info: Variant, zone_id := "") -> void:
	_switch_to = (level_info as Dictionary).duplicate(true) if level_info is Dictionary else LevelSwitch.info_for_scene(String(level_info))
	_switch_zone = zone_id
	_switch_waiting = {}
	for id in multiplayer.get_peers():
		_switch_waiting[id] = true
	if _switch_waiting.is_empty():
		_do_switch()
		return
	_client_hold_sync.rpc()
	var serial := _switch_serial + 1
	_switch_serial = serial
	get_tree().create_timer(SWITCH_WAIT_S).timeout.connect(func() -> void:
		if _switch_serial == serial and switch_pending():
			_do_switch())


## Host: a level switch is waiting for clients.
func switch_pending() -> bool:
	return not _switch_to.is_empty()


func _do_switch() -> void:
	# What players picked up or dropped at the hub while the switch waited counts (the stash
	# poll stops while it waits, and server_deploy read the hub back before it).
	_read_back_base()
	var info := _switch_to
	_switch_to = {}
	if _switch_zone != "":
		GameState.zone_id = _switch_zone  # the new level loads (or skips) its zone save
	_switch_serial += 1
	var old := level()
	var roles: Dictionary = old.player_roles.duplicate() if old else {}
	_gear_applied.clear()
	if is_instance_valid(_ui):
		_ui.close()
	var fresh := _swap_level(info)
	_client_switch_level.rpc(info)
	fresh.player_roles = roles
	fresh._on_hosted()
	for id in multiplayer.get_peers():
		fresh._on_peer_joined(id)
	if not (fresh is BaseLevel) and RosterDeployment.is_running(roster()):
		_open_briefing(fresh)
	_queue_broadcast()
	level_switched.emit(fresh)


## Host: the squad arrived in the zone on a contract: the briefing opens for everyone on the
## zone's map (the contract's objectives and what intel knows of the enemy; insertion points
## from the zone). Its start (_on_briefing_started) makes the contract live.
func _open_briefing(lvl: CompoundLevel) -> void:
	var c: Dictionary = RosterDeployment.active(roster()).get("contract", {})
	var briefing := MapNodes.briefing(lvl)
	if c.is_empty() or briefing == null:
		return
	briefing.server_open(briefing_contract(String(c.get("cid", ""))), briefing_zone(lvl, c))
	briefing.deployment_started.connect(_on_briefing_started.bind(String(c.get("cid", ""))), CONNECT_ONE_SHOT)


## A held contract as the briefing shows it (Briefing's contract shape): its objectives on
## the map (at its target module) and its brief; what intel knows of the enemy.
static func briefing_contract(cid: String) -> Dictionary:
	var c := Contracts.contract(cid)
	var objectives: Array = []
	for o: Dictionary in Objectives.from_contract(c, Contracts.module_origin(c)):
		var p: Array = o.get("pos", [])
		objectives.append({"id": String(o.oid), "title": String(o.text), "text": String(o.text),
			"pos": [float(p[0]), float(p[2])] if p.size() == 3 else [0.0, 0.0], "radius": 6.0})
	return {"id": cid, "title": String(c.get("title", "")), "type": String(c.get("type", "")), "employer": String(c.get("employer", "")),
		"summary": "%s\n%s. Terms: %s." % [String(c.get("brief", "")), ContractGen.estimate_text(c), ContractGen.clawback_text(c)],
		"difficulty": int(c.get("rated", 1)), "objectives": objectives, "known_enemies": known_enemies(c)}


## What intel knows of the enemy, for the briefing's map: the target module held, with the
## briefing's estimate (which may understate it). Empty for a contract with no target module.
static func known_enemies(c: Dictionary) -> Array:
	if String(c.get("module_id", "")) == "":
		return []
	var at := Contracts.module_origin(c)
	return [{"pos": [at.x, at.z], "text": "Hostiles at the %s: %s" % [String(c.get("module_name", "site")), ContractGen.estimate_text(c)]}]


## The zone as the briefing shows it: the level's own insertion and extraction points (a
## generated zone), else the test compound's.
static func briefing_zone(lvl: Node, c: Dictionary) -> Dictionary:
	var zone := Briefing.DEBUG_ZONE.duplicate(true)
	if lvl.has_method(&"insertion_points"):
		var ins: Array = []
		for p: Vector3 in lvl.call(&"insertion_points"):
			ins.append({"id": "insertion_%d" % (ins.size() + 1), "name": "Insertion %d" % (ins.size() + 1), "pos": [p.x, p.z], "method": "foot"})
		var lzs: Array = []
		for p: Vector3 in lvl.call(&"extraction_points"):
			lzs.append({"name": "LZ %d" % (lzs.size() + 1), "pos": [p.x, p.z], "radius": Extraction.RADIUS_M})
		if not ins.is_empty():
			zone.insertion_points = ins
			zone.extraction_points = lzs
	zone.id = String(c.get("zone_id", zone.id))
	zone.name = String(c.get("zone_name", zone.name))
	zone.kind = String(c.get("zone_kind", zone.kind))
	return zone


## Host: the briefing started (everyone ready): the contract goes live (its objectives), and
## a recovery contract's squadmate is out there waiting. The briefing itself moves the squad
## to the insertion point and opens extraction.
func _on_briefing_started(_plan: Dictionary, cid: String) -> void:
	if not deployment_running():
		return
	var why := Contracts.server_start_deployment([cid], String(Contracts.contract(cid).get("zone_id", "")))
	if why != "":
		push_warning("BaseHub: %s" % why)
		return
	SessionLog.note("deployment: briefing done, contract %s is live" % _contract_text(Contracts.contract(cid)))
	_spawn_recovery_targets(level())
	_size_reinforcements.call_deferred(cid)  # after the briefing's own flow started the timer


## Host: the reinforcement timer sized from the contract's true force (seam 7).
func _size_reinforcements(cid: String) -> void:
	var lvl := level()
	var reinforcements := MapNodes.reinforcements(lvl) if lvl else null
	var tuning := Contracts.reinforcement_tuning(cid)
	if reinforcements and not tuning.is_empty():
		reinforcements.server_start(tuning)


## Client: a level switch is coming: this player's own movement stops going out until the
## new level's player arrives.
@rpc("authority", "call_remote", "reliable")
func _client_hold_sync() -> void:
	var lvl := level()
	var me := lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) if lvl else null
	var sync := me.get_node_or_null(^"Sync") as MultiplayerSynchronizer if me else null
	if sync:
		sync.public_visibility = false
	_server_switch_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _server_switch_ready() -> void:
	if not multiplayer.is_server() or not switch_pending():
		return
	_switch_waiting.erase(multiplayer.get_remote_sender_id())
	if _switch_waiting.is_empty():
		_do_switch()


@rpc("authority", "call_remote", "reliable")
func _client_switch_level(info: Dictionary) -> void:
	campaign_running = true
	if is_instance_valid(_ui):
		_ui.close()
	var fresh := _swap_level(info)
	level_switched.emit(fresh)


## Replaces the running level with a new one playing `info` (level_info()) under the same
## parent (this peer only; LevelSwitch.load_level retires the old one).
func _swap_level(info: Dictionary) -> CompoundLevel:
	var old := level()
	if old == null:
		push_error("BaseHub: no level to swap")
		return null
	return LevelSwitch.load_level(old.get_parent(), info, true)


## Host (BaseLevel): the hub is built and its people stand at the muster line.
func server_level_ready(_level: CompoundLevel) -> void:
	_queue_broadcast()


## Host: reads the hub back into the campaign: the stash from its world items, the muster
## line's gear, and each player's gear onto their main character.
func _read_back_base() -> void:
	var lvl := level() as BaseLevel
	if lvl == null or not campaign_running:
		return
	base()["stash"] = lvl.server_collect_stash()
	var gear := lvl.server_read_muster_gear()
	for mid: String in gear:
		server_store_member_gear(mid, gear[mid])
	for p: Node in lvl.players.get_children():
		if p is Soldier and not p.is_queued_for_deletion() and _gear_applied.has(p.name.to_int()):
			var main := Roster.main_character(roster(), player_key(p.name.to_int()))
			main["gear"] = Roster.json_safe((p as Soldier).inventory.net_state.duplicate(true))


func _process(delta: float) -> void:
	if not campaign_running or not multiplayer.is_server() or switch_pending():
		return
	_stash_poll -= delta
	if _stash_poll > 0.0:
		return
	_stash_poll = STASH_POLL_S
	if not in_base():
		if RosterDeployment.is_running(roster()):
			_check_recovery_targets()
		return
	var now := (level() as BaseLevel).server_collect_stash()
	if now != Roster.json_safe(stash()):
		base()["stash"] = now
		_changed(&"base")


# --- Players ----------------------------------------------------------------------------------

## This machine's profile key.
func profile() -> String:
	if local_profile == "":
		local_profile = "player_" + OS.get_unique_id().md5_text().left(8)
	return local_profile


## Host: the profile (main character) of the player on `peer`.
func player_key(peer: int) -> String:
	if peer == 1:
		return profile()
	return String(_profiles.get(peer, "peer_%d" % peer))


func _player_count() -> int:
	return 1 + multiplayer.get_peers().size()


func _on_joined() -> void:
	_server_hello.rpc_id(1, profile())


## Client (connecting; LevelSwitch's handshake): the host's session is a campaign or not.
## This machine follows it before it loads the host's level.
func follow_host(campaign: bool) -> void:
	campaign_running = campaign
	if not campaign:
		view = {}


## Client: the connection failed (the menu may try again): nothing of a campaign stays.
func _on_join_failed() -> void:
	if campaign_running:
		cancel_session()


## A client says which profile it plays (sent on join).
@rpc("any_peer", "call_remote", "reliable")
func _server_hello(key: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var k := key if key.strip_edges() != "" else "peer_%d" % peer
	var taken: Array = _profiles.values() + [profile()]
	var base_key := k
	var n := 2
	while k in taken:
		k = "%s_%d" % [base_key, n]
		n += 1
	_profiles[peer] = k
	SessionLog.note("player joined: Player %d plays profile %s (%d players)" % [peer, k, _player_count()])
	var lvl := level()
	var p := lvl.players.get_node_or_null(str(peer)) as Soldier if lvl else null
	if p and campaign_running:
		_apply_player_gear(peer, p)
	_queue_broadcast()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and campaign_running:
		_client_view.rpc_id(id, JSON.stringify(build_view()))


## Host: a player leaving keeps what they stand up in (on their main character, or their
## stand-in); one leaving while down leaves it on their body (CompoundLevel).
func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server() or not campaign_running:
		return
	var lvl := level()
	var p := lvl.players.get_node_or_null(str(id)) as Soldier if lvl else null
	SessionLog.note("player left: Player %d (profile %s)%s" % [id, player_key(id),
		"" if p == null else ", %s" % p.vitals.condition_text()])
	if p and _gear_applied.has(id):
		var gear: Dictionary = Roster.json_safe(p.inventory.net_state.duplicate(true)) if p.vitals.is_up() else {}
		var key := player_key(id)
		var dep := RosterDeployment.active(roster())
		if dep.has("stand_ins") and dep.stand_ins.has(key):
			server_store_member_gear(String(dep.stand_ins[key]), gear)
		else:
			Roster.main_character(roster(), key)["gear"] = gear
		_changed(&"roster")
	_gear_applied.erase(id)
	_profiles.erase(id)


func _on_session_ended() -> void:
	campaign_running = false
	_hook_economy(false)
	view = {}
	_restore_zone_id()
	_profiles.clear()
	_gear_applied.clear()


## Host hook (CompoundLevel._add_player): a player's body was added. In a campaign it gets
## their gear (their main character's, or their stand-in's in a deployment), and in a
## deployment their deaths count against the respawn pool.
func server_player_added(_lvl: CompoundLevel, player: Soldier) -> void:
	if not campaign_running:
		return
	var peer := player.name.to_int()
	if peer == 1 or _profiles.has(peer):
		_apply_player_gear(peer, player)
	if RosterDeployment.is_running(roster()):
		player.vitals.died.connect(_on_player_died.bind(player))


func _apply_player_gear(peer: int, player: Soldier) -> void:
	if _gear_applied.has(peer):
		return
	_gear_applied[peer] = true
	var key := player_key(peer)
	var main := Roster.main_character(roster(), key, Roles.local_choice if peer == 1 else Roles.RIFLEMAN)
	var gear: Dictionary = main.get("gear", {})
	var dep := RosterDeployment.active(roster())
	if dep.has("stand_ins") and dep.stand_ins.has(key) and not member(String(dep.stand_ins[key])).is_empty():
		gear = member(String(dep.stand_ins[key])).get("gear", {})
		player._client_message.rpc_id(peer, "%s is recovering: you play %s" % [main.name, member(String(dep.stand_ins[key])).callsign])
	player.inventory.net_state = GameState.from_json(gear.duplicate(true))


## Host: a player died in a deployment: the respawn pool counts it (free ones first, then
## bought; with no cash it goes on credit).
func _on_player_died(player: Soldier) -> void:
	if not RosterDeployment.is_running(roster()) or not is_instance_valid(player):
		return
	var text := server_count_respawn()
	SessionLog.note("respawn pool: %s died (%s): %s" % [SessionLog.who(player), player_key(player.name.to_int()), text])
	player._client_message.rpc_id(player.name.to_int(), text)


## Host: counts one player respawn against the pool. Past the free ones each is bought, at a
## price that rises with each (RosterDeployment.respawn_cost), paid from cash first, then from
## the deployed contract's support budget (Captain), and what neither covers goes on credit.
## Returns the line the player sees.
func server_count_respawn() -> String:
	var cost := RosterDeployment.respawn_cost(roster(), BaseEconomy.respawn_price(), Prices.respawn_rise())
	if cost == 0:
		var left := RosterDeployment.count_respawn(roster(), false)
		_changed(&"roster")
		return "Respawn: %d free left" % left
	var from_cash := clampi(Economy.cash(), 0, cost)
	var cids: Array = Contracts.deployment().get("cids", [])
	var from_budget := Contracts.server_draw_support(String(cids[0]), cost - from_cash) if not cids.is_empty() and cost > from_cash else 0
	var on_credit := cost - from_cash - from_budget
	if from_cash > 0:
		BaseEconomy.charge(from_cash, "Respawn")
	if on_credit > 0:
		BaseEconomy.charge(on_credit, "Respawn on credit")
	RosterDeployment.count_respawn(roster(), true)
	_changed(&"roster")
	var parts := PackedStringArray()
	for pair: Array in [[from_cash, "cash"], [from_budget, "support budget"], [on_credit, "on credit"]]:
		if int(pair[0]) > 0:
			parts.append("$%d %s" % [int(pair[0]), pair[1]])
	return "Respawn bought: %s" % ", ".join(parts)


# --- Deployments -------------------------------------------------------------------------------

## Host: takes the picked squad into the zone. `options` may override the prep: "squad"
## (member ids), "zone_kind", "zone_id", "scene"; "no_contract": true deploys without a prepped
## contract (code and tests only: the Deploy request never sends it). Players whose main
## character is recovering get a stand-in (an available member not in the squad, else a free
## rookie). Returns "" or why it can't.
func server_deploy(options := {}) -> String:
	if not multiplayer.is_server():
		return "Only the host deploys"
	if RosterDeployment.is_running(roster()):
		return "A deployment is already running"
	_read_back_base()
	var prep := _prep()
	# Without a contract there's no briefing, so no extraction and no way home (P0331): refuse.
	if (prep.get("contract", {}) as Dictionary).is_empty() and not options.get("no_contract", false):
		return NO_CONTRACT
	var info: Dictionary = options.get("level", prep.get("level", {}))
	var scene := String(options.get("scene", prep.get("scene", "")))
	if not info.is_empty():
		scene = LevelSwitch.scene_for(info)
	else:
		if scene == "":
			scene = COMPOUND_SCENE
		info = LevelSwitch.info_for_scene(scene)
	var zone_kind := String(options.get("zone_kind", prep.get("zone_kind", RosterDeployment.CONTRACT)))
	var zone_id := String(options.get("zone_id", prep.get("zone_id", "")))
	if zone_id == "":
		zone_id = DEFAULT_ZONE_ID
	_before_deploy = Campaign.snapshot()  # before anything of the deployment is written
	var squad: Array = options.get("squad", prep.get("squad", []))
	squad = squad.slice(0, maxi(SQUAD_SIZE - _player_count(), 0))
	var stand_ins := _pick_stand_ins(squad)
	var dep := RosterDeployment.begin(roster(), squad, zone_kind, zone_id, scene, day(), prep.get("contract", {}), stand_ins)
	_record_loadouts(dep)  # S2: what everyone deploys in, for "Restock last loadout" back at the base
	SessionLog.note("deployment started: zone %s (%s), contract %s, day %d; squad %s; %d player%s; %d free respawns" % [zone_id, zone_kind,
		_contract_text(prep.get("contract", {})), day(), _callsigns(dep.squad), _player_count(), "" if _player_count() == 1 else "s",
		int(dep.respawns_free)])
	prep["contract"] = {}
	prep["level"] = {}
	_changed_all()
	server_switch_level(info, zone_save_id(zone_id))
	return ""


## For the session log: "Hold the Line [c12]", or "none".
static func _contract_text(c: Dictionary) -> String:
	if c.is_empty():
		return "none"
	return "%s [%s]" % [String(c.get("title", c.get("name", "?"))), String(c.get("cid", "?"))]


## For the session log: the members' callsigns, or "none".
func _callsigns(mids: Array) -> String:
	var names := PackedStringArray()
	for mid: Variant in mids:
		names.append(String(member(String(mid)).get("callsign", mid)))
	return ", ".join(names) if not names.is_empty() else "none"


func _pick_stand_ins(squad: Array) -> Dictionary:
	var out := {}
	var keys: Array[String] = [player_key(1)]
	for peer in multiplayer.get_peers():
		keys.append(player_key(peer))
	for key in keys:
		if not Roster.main_recovering(roster(), key):
			continue
		var role := StringName(Roster.main_character(roster(), key).get("role", Roles.RIFLEMAN))
		var pick := ""
		for mid in Roster.available_ids(roster()):
			if mid in squad or mid in out.values():
				continue
			if pick == "" or StringName(member(mid).role) == role:
				pick = mid
				if StringName(member(mid).role) == role:
					break
		if pick == "":
			pick = Hiring.provide_free(roster(), role, day(), int(hiring().get("seed", 0)))
		out[key] = pick
	return out


## Host hook (CompoundLevel._spawn_squadmate during a deployment): the roster member who
## fills `slot` (RosterDeployment.member_for_slot), spawned as themselves: their callsign as
## the body's name, their own gear and no role kit on top, their skills as AI stats. Null when
## nobody is left to fill it.
func server_spawn_roster_squadmate(lvl: CompoundLevel, slot: int, role: StringName, team: int) -> Soldier:
	# Who's in the zone already, and who was just removed (rebalance_squad: their body keeps
	# its name, the callsign, until it's freed at the end of the frame).
	var present := {}
	var leaving := false
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and not s.vitals.is_dead():
			present[String(s.get_meta(&"roster_id"))] = true
			leaving = leaving or s.is_queued_for_deletion()
	var mid := RosterDeployment.member_for_slot(roster(), role, present)
	if mid == "" or lvl.ai.get_node_or_null(NodePath(String(member(mid).callsign))) != null:
		if leaving:  # one just removed may fill it once they're gone
			get_tree().create_timer(REFILL_RETRY_S).timeout.connect(func() -> void:
				if is_instance_valid(lvl) and lvl == level() and RosterDeployment.is_running(roster()):
					lvl.rebalance_squad())
		return null
	var m := member(mid)
	var squad := lvl.squad_for(&"friendly")
	var anchor: Node3D = squad.leader if squad and is_instance_valid(squad.leader) else null
	var wedge: Array = Squad.FORMATIONS["wedge"]
	var pos: Vector3 = anchor.global_transform * (wedge[maxi(slot - 1, 0) % wedge.size()] as Vector3) if anchor \
		else lvl.next_spawn_point() + Vector3(0, 0, 3)
	var stats := Roster.ai_stats(m)
	var data := {"name": String(m.callsign), "faction": "friendly", "variant": "multicam", "pos": pos, "loadout": [],
		"role": "", "team": team, "slot": slot, "combat": stats.combat, "discipline": stats.discipline, "guard": false}
	data.merge(Roster.identity(m))  # the same person every deployment: name tape, nationality, hand, body
	var s := lvl.spawn_soldier(data)
	s.role = role
	s.set_meta(&"roster_id", mid)
	s.inventory.net_state = GameState.from_json(m.get("gear", {}).duplicate(true))
	RosterDeployment.mark_spawned(roster(), mid)
	_changed(&"roster")
	return s


## Host: the squadmates the deployment's recovery contracts are about wait where they were
## left (the objective's position), in their own gear, holding there until a player finds
## them (_process: within FOUND_M), then following the squad. Outside the squad's slots.
func _spawn_recovery_targets(lvl: CompoundLevel) -> void:
	for cid: String in Contracts.deployment().get("cids", []):
		var c := Contracts.contract(cid)
		var mid := String(c.get("recover_mid", ""))
		var m := member(mid)
		if mid == "" or m.is_empty() or String(m.get("status", "")) != Roster.MIA or lvl.ai.get_node_or_null(NodePath(String(m.callsign))):
			continue
		var p: Array = (c.objectives[0] as Dictionary).get("params", {}).get("pos", [0.0, 0.0, 0.0])
		var stats := Roster.ai_stats(m)
		var data := {"name": String(m.callsign), "faction": "friendly", "variant": "multicam", "pos": Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2])),
			"loadout": [], "role": "", "team": 0, "slot": -1, "combat": stats.combat, "discipline": stats.discipline, "guard": true}
		data.merge(Roster.identity(m))
		var s := lvl.spawn_soldier(data)
		s.role = StringName(m.get("role", Roles.RIFLEMAN))
		s.set_meta(&"roster_id", mid)
		s.set_meta(&"recovery", true)
		s.inventory.net_state = GameState.from_json(m.get("gear", {}).duplicate(true))
		var brain := SquadAI.of(s)
		if brain:
			brain.order = Squad.Order.HOLD  # where they stand (the brain takes its hold point there when it sets up)


## Host: a waiting squadmate a player reached follows the squad from now on.
func _check_recovery_targets() -> void:
	var lvl := level()
	if lvl == null:
		return
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s == null or not s.has_meta(&"recovery") or s.has_meta(&"found") or s.vitals.is_dead():
			continue
		for p: Node in lvl.players.get_children():
			if p is Soldier and (p as Soldier).global_position.distance_to(s.global_position) <= FOUND_M:
				s.set_meta(&"found", true)
				var brain := SquadAI.of(s)
				if brain:
					brain.on_order(Squad.Order.FOLLOW, s.global_position, 0, 1)
				(p as Soldier)._client_message.rpc_id(p.name.to_int(), "Found %s: they're with you" % String(s.name))
				break


## Host hook (CompoundLevel._remove_squadmate): a roster squadmate leaves the zone early (a
## player took the slot, or its role changed): they keep their gear and their wounds, and
## didn't deploy after all. Unhurt, they may come back for another slot (refilled shortly).
func server_squadmate_leaving(s: Soldier) -> void:
	if not s.has_meta(&"roster_id") or not RosterDeployment.is_running(roster()):
		return
	var mid := String(s.get_meta(&"roster_id"))
	server_store_member_gear(mid, s.inventory.net_state)
	Roster.injure(member(mid), Roster.assess_outcome(_outcome_of(s)), day())
	RosterDeployment.unmark_spawned(roster(), mid)
	_changed(&"roster")


## Host hook (CompoundLevel._on_died_for_good): a roster squadmate was killed.
func server_squadmate_died(s: Soldier) -> void:
	if s.has_meta(&"roster_id") and RosterDeployment.is_running(roster()):
		RosterDeployment.mark_fallen(roster(), String(s.get_meta(&"roster_id")))
		_changed(&"roster")


## Host (Extraction.END_GROUP): the squad got out. The one end of a campaign deployment, in
## order: the debrief on the contract (Contracts.server_end_deployment: pay, clawback, fines,
## reputation, salvage, intel, and the days it took), then the roster (server_end_deployment:
## who's back, MIA and recovery contracts, gear home), then everyone back at the base. A
## recovery contract's squadmate counts as brought out when they're alive inside the point.
func end_deployment(report: Dictionary) -> void:
	if not campaign_running or not multiplayer.is_server() or not RosterDeployment.is_running(roster()):
		return
	var lvl := level()
	var extracted: Array = []
	for record: Dictionary in (report.get("players", []) as Array) + (report.get("squad", []) as Array):
		var parent: Node = lvl.players if int(record.get("peer", 0)) != 0 else lvl.ai
		var s := parent.get_node_or_null(NodePath(String(record.get("node", "")))) as Soldier
		if s:
			extracted.append(s)
	var point: Array = report.get("point", {}).get("pos", [])
	var hvts: Array = []
	for h: Dictionary in report.get("hvts", []):
		hvts.append({"hvt": String(h.get("hvt", h.get("name", ""))), "alive": bool(h.get("alive", true))})
	if lvl.people and point.size() == 2:  # people: an HVT or hostage brought to a point the squad picked
		hvts.append_array(lvl.people.hvts_out(Vector2(float(point[0]), float(point[1])), Extraction.RADIUS_M, extracted))
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"recovery") and not s.vitals.is_dead() and point.size() == 2 \
				and Vector2(s.global_position.x, s.global_position.z).distance_to(Vector2(float(point[0]), float(point[1]))) <= Extraction.RADIUS_M:
			hvts.append({"hvt": Contracts.MIA_HVT_PREFIX + String(s.get_meta(&"roster_id")), "alive": true})
			server_store_member_gear(String(s.get_meta(&"roster_id")), s.inventory.net_state)
	var contract_ran := Contracts.is_deployed()
	if contract_ran:
		var debrief_report := Contracts.report_from_level(lvl, extracted)
		debrief_report["hvts"] = hvts
		# The people bring their own gear home; what else came out (bodies carried in, items set
		# down at the point) goes to the stash.
		var bank: Array = []
		for body: Dictionary in report.get("bodies", []):
			for entry: Dictionary in body.get("items", []):
				bank.append_array(Contracts.flatten_entry(entry))
		for entry: Dictionary in report.get("deposited", []):
			bank.append_array(Contracts.flatten_entry(entry))
		debrief_report["bank"] = bank
		Contracts.server_end_deployment(debrief_report)
	server_end_deployment(extracted, true, not contract_ran)


## Host (the map's extraction): the deployment ends. `extracted` are the soldiers who made it
## out (AI squadmates and players; players are always counted back). Every roster squadmate
## who deployed is settled (RosterDeployment.resolve): dead ones are lost with their gear on
## their body in the zone, those alive but not in `extracted` go MIA (a recovery contract is
## requested), the rest come back with their gear, experience and wounds. Days pass (with
## `advance_days`: a contract's debrief has already moved the clock on for its days), the zone
## and the campaign are saved, and with `return_to_base` everyone goes back to the hub.
## Returns the debrief report ({} if no deployment was running).
func server_end_deployment(extracted: Array, return_to_base := true, advance_days := true) -> Dictionary:
	var dep := RosterDeployment.active(roster())
	if dep.is_empty() or not multiplayer.is_server():
		return {}
	var lvl := level()
	var made_it := {}
	for n: Variant in extracted:
		if n is Soldier and is_instance_valid(n):
			made_it[(n as Soldier).get_instance_id()] = true
	var bodies := {}  # member id -> their Soldier (the living one if any)
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and not s.is_queued_for_deletion():
			var mid := String(s.get_meta(&"roster_id"))
			if not bodies.has(mid) or not s.vitals.is_dead():
				bodies[mid] = s
	var outcomes := {"members": {}, "players": {}}
	for mid: String in dep.spawned:
		var s: Soldier = bodies.get(mid)
		var o := {}
		if dep.get("fallen", {}).has(mid) or s == null or s.vitals.is_dead():
			o["state"] = RosterDeployment.KILLED
		else:
			o = _outcome_of(s)
			o["state"] = RosterDeployment.EXTRACTED if made_it.has(s.get_instance_id()) else RosterDeployment.LEFT_BEHIND
			o["pos"] = [s.global_position.x, s.global_position.y, s.global_position.z]
		outcomes.members[mid] = o
	for n: Node in lvl.players.get_children():
		var p := n as Soldier
		if p and not p.is_queued_for_deletion():
			outcomes.players[player_key(p.name.to_int())] = _outcome_of(p)
	var report := RosterDeployment.resolve(roster(), outcomes, rng, day())
	SessionLog.note("deployment ended: zone %s (%s); back %s; MIA %s; KIA %s; respawns %d used (%d bought)" % [report.zone_id,
		report.zone_kind, _callsigns(report.extracted), _callsigns(report.mia), _callsigns(report.dead), int(report.respawns_used),
		int(report.respawns_bought)])
	for mid: String in report.mia:
		var m := member(mid)
		BaseEconomy.request_recovery_contract({"mid": mid, "name": m.name, "callsign": m.callsign, "role": m.role,
			"zone_id": report.zone_id, "day": day(), "pos": m.get("mia_pos", [])})
	GameState.save_zone()  # the zone keeps its bodies, loot and damage
	if advance_days:
		server_advance_days(int(RosterDeployment.DAYS.get(report.zone_kind, 1)))
	_changed_all()
	if not Campaign.save_campaign():
		note.emit(save_note(false))  # the host's player hears it (audit A1-04)
	deployment_ended.emit(report)
	if return_to_base:
		server_switch_level({"level": "base"}, base_zone_id())
	return report


## What a soldier brings back (RosterDeployment.resolve's outcome): their gear (the carrier's
## pouches and what's in them travel in its state) and their body's state at the end.
static func _outcome_of(s: Soldier) -> Dictionary:
	return {"gear": s.inventory.net_state.duplicate(true), "wounds": s.vitals.wound_list(), "blood": s.vitals.blood_fraction(),
		"burn": s.vitals.burn_share(), "blast_lung": s.vitals.has_blast_lung()}


## Host (the Escape menu's "Return to Base (revert)", Captain 2026-10-12): back to just before the
## running deployment: the campaign as it was when it left the base (cash, roster and their gear,
## held contracts, the stash, the day), the deployment and its objectives gone, everyone at the
## base. The zone keeps no trace either (it saves only when a deployment ends). Returns why not,
## or "".
func server_revert_deployment() -> String:
	if not multiplayer.is_server():
		return "Only the host can do that"
	if not RosterDeployment.is_running(roster()) or _before_deploy.is_empty():
		return "No deployment to revert"
	SessionLog.note("Return to Base (revert): the deployment is undone, the campaign is back as it was at the base")
	Campaign.restore(_before_deploy)
	_before_deploy = {}
	Contracts.objectives.server_clear()
	_changed_all()
	server_switch_level({"level": "base"}, base_zone_id())
	return ""


## Host: everyone goes back to the hub (after server_end_deployment(..., false) and a debrief).
func server_return_to_base() -> void:
	SessionLog.note("Return to Base: everyone goes back to the hub")
	server_switch_level({"level": "base"}, base_zone_id())


## Host (debug, and a stand-in for the map's extraction): ends the deployment with everyone
## alive within `radius` metres of `point` extracted.
func server_extract_near(point: Vector3, radius := DEBUG_EXTRACT_M) -> Dictionary:
	var lvl := level()
	var out: Array = []
	for n: Node in lvl.ai.get_children() + lvl.players.get_children():
		var s := n as Soldier
		if s and s.faction == &"friendly" and not s.vitals.is_dead() and s.global_position.distance_to(point) <= radius:
			out.append(s)
	return server_end_deployment(out)


## Host (Contracts.contract_closed): a recovery contract that came off the board or the held
## list settles its squadmate: brought out (completed), they're back; otherwise (failed,
## voided, aborted, lapsed, or the offer ran out) they're lost. Any other contract in prep
## leaves the prep.
func _on_contract_closed(c: Dictionary, outcome: String) -> void:
	if not started() or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()):
		return
	if String(prep_contract().get("cid", "")) == String(c.get("cid", "")):
		_prep()["contract"] = {}
		_changed(&"base")
	var mid := String(c.get("recover_mid", ""))
	if mid == "" or String(member(mid).get("status", "")) != Roster.MIA:
		return
	if outcome == "completed":
		server_recover_member(mid)
	else:
		server_write_off_member(mid)


## Host (a recovery contract succeeded): the MIA member is back, with `sit_out_days` to recover.
func server_recover_member(mid: String, sit_out_days := 0) -> bool:
	var ok := RosterDeployment.recovered(roster(), mid, day(), sit_out_days)
	_changed(&"roster")
	return ok


## Host (a recovery contract failed or lapsed): the MIA member is lost.
func server_write_off_member(mid: String) -> bool:
	var ok := RosterDeployment.written_off(roster(), mid, day())
	_changed(&"roster")
	return ok


# --- Days, hiring, medbay, shop -----------------------------------------------------------

## Host: `days` campaign days pass at the base (resting), on the economy's clock: the weekly
## bill falls due on its day (the roster's wages in it), and the roster and hiring board
## follow (_on_day_advanced).
func server_advance_days(days: int, reason := "at the base") -> void:
	if days > 0:
		Economy.advance_days(days, reason)


## Host (Economy.day_advanced): `days` days passed, whatever moved the clock (resting, a
## deployment's debrief, travel): the wounded recover, the hiring board turns over every
## Hiring.REFRESH_DAYS.
func _on_day_advanced(today: int, days: int) -> void:
	if not started() or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()):
		return
	Roster.advance_days(roster(), days, today)
	Hiring.refresh_if_due(hiring(), today)
	_changed_all()
	_refresh_muster()


## Host (Economy.wages_provider): the roster's wages for a week.
func _weekly_wages() -> int:
	return Roster.daily_wages(roster()) * maxi(MissionRegistry.setting_i("week_days", 7), 1)


## Host (Economy.purchase_sink and stash_sink): bought, salvaged or brought-out items go into
## the stash (onto the armory counter at the hub).
func _purchase_into_stash(id: StringName, count: int, _peer: int) -> bool:
	if not started():
		return false
	server_add_to_stash(id, count)
	return true


func _bank_into_stash(items: Array) -> bool:
	if not started():
		return false
	for entry: Dictionary in items:
		if ItemDB.has_item(StringName(entry.get("id", ""))):
			server_add_to_stash(StringName(entry.id), int(entry.get("count", 1)), entry.get("state", {}))
	return true


## Host: the base runs on the economy (the wage bill, the shop and the stash); off again
## when the campaign session ends.
func _hook_economy(on: bool) -> void:
	Economy.wages_provider = _weekly_wages if on else Callable()
	Economy.purchase_sink = _purchase_into_stash if on else Callable()
	Economy.stash_sink = _bank_into_stash if on else Callable()


## Host: hires candidate `cid` off the board for their sign-on fee. Returns "" or why not.
func server_hire(cid: String) -> String:
	var c := Hiring.find(hiring(), cid, day())
	if c.is_empty():
		return "They've moved on"
	if not BaseEconomy.try_spend(int(c.fee), "Hired %s" % c.name):
		return "Not enough cash for the $%d sign-on fee" % int(c.fee)
	var mid := Hiring.hire(hiring(), roster(), cid, day())
	_changed_all()
	_refresh_muster()
	return "" if mid != "" else "They've moved on"


## Host: lets a member go (available ones only); their gear goes into the stash.
func server_release(mid: String) -> String:
	var m := member(mid)
	if m.is_empty() or not Roster.is_available(m):
		return "Only someone fit and at the base can be let go"
	var lvl := level() as BaseLevel
	var s: Soldier = lvl.muster_soldier(mid) if lvl else null
	var gear: Dictionary = s.inventory.net_state if s else m.get("gear", {})
	_stash_gear(GameState.from_json(gear.duplicate(true)))
	if s:
		s.inventory.strip()
	Roster.members(roster()).erase(mid)
	(_prep().squad as Array).erase(mid)
	_changed_all()
	_refresh_muster()
	return ""


## Puts everything in an Inventory.net_state into the stash.
func _stash_gear(gear: Dictionary) -> void:
	var inv := Inventory.new()
	inv.net_state = gear
	for entry: Dictionary in inv.strip():
		server_add_to_stash(StringName(entry.id), int(entry.count), entry.get("state", {}))
	inv.free()


## Host: the medbay treats a member (member id) or a player's main character ("player:<key>")
## for its price (Roster.medbay_quote). Returns "" or why not.
func server_medbay(who: String) -> String:
	var person := Roster.main_character(roster(), who.trim_prefix("player:")) if who.begins_with("player:") else member(who)
	var quote := Roster.medbay_quote(person)
	if quote.is_empty():
		return "Nothing the medbay can do for them now"
	if not BaseEconomy.try_spend(int(quote.cost), "Medbay"):
		return "Not enough cash: $%d" % int(quote.cost)
	Roster.medbay_treat(person, day())
	_changed(&"roster")
	_refresh_muster()
	return ""


## Host: buys `count` of `id` at the shop (Economy.server_buy) into the stash
## (_purchase_into_stash). Returns "" or why not.
func server_buy(id: StringName, count := 1, peer := 1) -> String:
	if not ItemDB.has_item(id) or count <= 0:
		return "Not for sale"
	var price := BaseEconomy.item_price(id) * count
	if price <= 0:
		return "Not for sale"
	if not Economy.server_buy(id, count, peer):
		return "Not enough cash: $%d" % price
	return ""


## Host: an item joins the stash: delivered to the armory counter at the hub, or straight into
## the stash list anywhere else.
func server_add_to_stash(id: StringName, count := 1, state := {}) -> void:
	var lvl := level() as BaseLevel
	if lvl and campaign_running:
		lvl.server_deliver(id, count, state)
	else:
		BaseArmory.add(stash(), id, count, state)
	_changed(&"base")


## Host: puts a member in or out of the squad picked for the next deployment.
func server_pick(mid: String, in_squad: bool) -> String:
	var squad: Array = _prep().squad
	if not in_squad:
		squad.erase(mid)
	elif mid not in squad:
		if not Roster.is_available(member(mid)):
			return "They can't deploy now"
		if squad.size() >= SQUAD_SIZE - 1:
			return "The squad is full"
		squad.append(mid)
	_changed(&"base")
	return ""


## Host: a member's role in the squad from now on.
func server_set_role(mid: String, role: StringName) -> String:
	var m := member(mid)
	if m.is_empty() or not Roles.has(role):
		return "No such role"
	m["role"] = String(role)
	Roster.add_history(m, day(), "Now a %s" % Roles.display_name(role))
	var lvl := level() as BaseLevel
	var s := lvl.muster_soldier(mid) if lvl else null
	if s:
		s.role = role
	_changed(&"roster")
	return ""


func _refresh_muster() -> void:
	var lvl := level() as BaseLevel
	if lvl and campaign_running and lvl.voxel_world.is_built():
		lvl.server_show_roster()


# --- Restocking the last loadout (playtest S2) -----------------------------------------------
# Kitting up at the base took 5-12 minutes a player (P0339, P0164, P0331, P0362). At deploy each
# player's main character and each squadmate gets their kit written down ("loadout" on their
# roster entry, Roster.record_loadout); back at the base one button rebuilds it from the stash
# (Restock.build): what they wear now goes into the pool first, the loadout is drawn from it,
# and what's left over lies in the armory as stash. What the stash is short of is listed.

## Host (server_deploy): writes down what everyone deploys in: the squad's members and each
## player's main character (not one sitting this one out: they play a stand-in).
func _record_loadouts(dep: Dictionary) -> void:
	for mid: Variant in dep.get("squad", []):
		var m := member(String(mid))
		if not m.is_empty():
			Roster.record_loadout(m, m.get("gear", {}))
	var keys: Array[String] = [player_key(1)]
	for peer: int in _gear_applied:
		if not player_key(peer) in keys:
			keys.append(player_key(peer))
	for key in keys:
		if Roster.players(roster()).has(key) and not Roster.main_recovering(roster(), key):
			var main := Roster.main_character(roster(), key)
			Roster.record_loadout(main, main.get("gear", {}))


## Host: rebuilds player `peer`'s last loadout on their body from the stash. Returns what it
## did (Restock.report_text), or why not; the player sees it too.
func server_restock_player(peer: int) -> String:
	var lvl := level() as BaseLevel
	if lvl == null or not campaign_running or RosterDeployment.is_running(roster()):
		return "Only at the base"
	var s := lvl.players.get_node_or_null(NodePath(str(peer))) as Soldier
	if s == null or not s.vitals.is_up():
		return "You can't kit up now"
	var main := Roster.main_character(roster(), player_key(peer))
	var loadout := Roster.loadout_of(main)
	if Restock.is_blank(loadout):
		return "No loadout yet: the kit you deploy in is written down for next time"
	var text := _restock_body(lvl, s, loadout, "your loadout")
	main["gear"] = Roster.json_safe(s.inventory.net_state.duplicate(true))
	_changed(&"roster")
	s._client_message.rpc_id(peer, text)
	return text


## Host: rebuilds member `mid`'s last loadout on them at the muster line. "" if they have none
## or aren't standing there; else what it did.
func server_restock_member(mid: String) -> String:
	var lvl := level() as BaseLevel
	var s: Soldier = lvl.muster_soldier(mid) if lvl and campaign_running and not RosterDeployment.is_running(roster()) else null
	var m := member(mid)
	if s == null or m.is_empty() or Restock.is_blank(Roster.loadout_of(m)):
		return ""
	var text := _restock_body(lvl, s, Roster.loadout_of(m), String(m.callsign))
	server_store_member_gear(mid, s.inventory.net_state)
	_changed(&"roster")
	return text


## Host (the squad leader's "Restock squad"): every AI squadmate picked for the next deployment
## (everyone at the muster line when nobody is picked yet), one after the other, from the
## stash. Returns one line each.
func server_restock_squad() -> String:
	if not in_base() or RosterDeployment.is_running(roster()):
		return "Only at the base"
	var picked: Array = _prep().get("squad", [])
	var mids: Array = picked if not picked.is_empty() else Array(muster_ids())
	var lines := PackedStringArray()
	var none := PackedStringArray()
	var lvl := level() as BaseLevel
	for mid: Variant in mids:
		if lvl.muster_soldier(String(mid)) == null:
			continue  # not here: missing, dead, recovering
		var text := server_restock_member(String(mid))
		if text != "":
			lines.append(text)
		else:
			none.append(String(member(String(mid)).callsign))
	if not none.is_empty():
		lines.append("No loadout yet for %s (written down when they deploy)" % ", ".join(none))
	return "\n".join(lines) if not lines.is_empty() else "Nobody to restock"


## Host: `s`'s kit becomes `loadout` drawn from the hub's stash (what they wear now goes into
## the pool first); the armory's world items follow. Returns Restock.report_text.
func _restock_body(lvl: BaseLevel, s: Soldier, loadout: Dictionary, who: String) -> String:
	var before := lvl.server_collect_stash()
	var pool: Array = before.duplicate(true)
	var own := Inventory.new()
	own.net_state = s.inventory.net_state
	for e: Dictionary in own.strip():
		BaseArmory.add(pool, StringName(e.id), int(e.count), e.get("state", {}))
	own.free()
	var res := Restock.build(loadout, pool)
	s.inventory.net_state = GameState.from_json(res.gear)
	_apply_stash(lvl, before, pool)
	var text := Restock.report_text(who, res)
	SessionLog.note("restock: %s: %s" % [SessionLog.who(s), text])
	return text


## Host: makes the hub's world items `after` where they were `before` (both stash entries):
## what went is taken off the armory's items, what came back (old kit, pouches or an optic
## swapped off) is put down at the armory counter.
func _apply_stash(lvl: BaseLevel, before: Array, after: Array) -> void:
	var had := Restock.stash_units(before)
	var now := Restock.stash_units(after)
	var gone := {}
	for key: String in had:
		if int(had[key]) > int(now.get(key, 0)):
			gone[key] = int(had[key]) - int(now.get(key, 0))
	for node: Node in lvl.items.get_children():
		var w := node as WorldItem
		if w == null or w.is_queued_for_deletion():
			continue
		var key := Restock.stash_key(w.item_id, w.state)
		var n := mini(int(gone.get(key, 0)), w.count)
		if n <= 0:
			continue
		gone[key] = int(gone[key]) - n
		if n >= w.count:
			GameState.item_taken(w.uid)
			w.queue_free()
		else:
			w.count -= n
	var come := {}
	for key: String in now:
		if int(now[key]) > int(had.get(key, 0)):
			come[key] = int(now[key]) - int(had.get(key, 0))
	var i := 0
	for entry: Dictionary in after:
		var key := Restock.stash_key(StringName(String(entry.id)), entry.get("state", {}))
		var n := mini(int(come.get(key, 0)), int(entry.count))
		if n <= 0:
			continue
		come[key] = int(come[key]) - n
		var jitter := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.3, 0.3))
		lvl.spawn_item(StringName(String(entry.id)), n, BaseLevel.DELIVERY + jitter, "stash_r_%d_%d" % [Time.get_ticks_usec(), i],
			GameState.from_json(entry.get("state", {})))
		i += 1
	base()["stash"] = Roster.json_safe(after)
	_changed(&"base")


# --- Requests from the base screen ---------------------------------------------------------

## Any peer: asks the host to do something at the base. `action`: "hire" [cid], "release"
## [mid], "medbay" [mid or "player:<key>"], "pick" [mid, bool], "role" [mid, role], "buy"
## [item id, count], "rest" [days], "prep" [held contract id], "deploy" [], "save" [], "restock"
## [] (the sender's last loadout), "restock_squad" []; "deploy", "rest", "release", "prep",
## "save" and "restock_squad" only from the host. The answer comes back as `note`.
func request(action: String, args: Array = []) -> void:
	_server_request.rpc_id(1, action, args)


@rpc("any_peer", "call_local", "reliable")
func _server_request(action: String, args: Array) -> void:
	if not multiplayer.is_server() or not campaign_running:
		return
	var sender := multiplayer.get_remote_sender_id()
	var why := ""
	var at_base := in_base() and not RosterDeployment.is_running(roster())
	var needs: int = {"hire": 1, "release": 1, "medbay": 1, "pick": 2, "role": 2, "buy": 1, "prep": 1}.get(action, 0)
	if args.size() < needs:
		why = "Bad request"
	elif action in ["deploy", "rest", "release", "save", "prep", "restock_squad"] and sender != 1:
		why = "Only the host can do that"  # the company's big decisions are the host's
	elif action not in ["save"] and not at_base:
		why = "Only at the base"
	else:
		match action:
			"hire":
				why = server_hire(String(args[0]))
			"release":
				why = server_release(String(args[0]))
			"medbay":
				why = server_medbay(String(args[0]))
			"pick":
				why = server_pick(String(args[0]), bool(args[1]))
			"role":
				why = server_set_role(String(args[0]), StringName(args[1]))
			"buy":
				why = server_buy(StringName(args[0]), int(args[1]) if args.size() > 1 else 1, sender)
			"rest":
				server_advance_days(clampi(int(args[0]) if not args.is_empty() else 1, 1, 30))
			"deploy":
				why = server_deploy()
			"prep":
				why = begin_prep_contract(String(args[0]))
				if why == "":
					why = "Prepping %s" % String(prep_contract().get("title", ""))
			"save":
				why = save_note(server_save())
			"restock":
				why = server_restock_player(sender if sender != 0 else 1)
			"restock_squad":
				why = server_restock_squad()
			_:
				why = "Unknown request"
	if why != "":
		_client_note.rpc_id(sender, why)


@rpc("authority", "call_local", "reliable")
func _client_note(text: String) -> void:
	note.emit(text)


# --- The view every peer gets ---------------------------------------------------------------

## What the base screen shows (host side; clients get it whole through _client_view).
func build_view() -> Dictionary:
	var keys := {}
	keys["1"] = player_key(1)
	for peer in multiplayer.get_peers():
		keys[str(peer)] = player_key(peer)
	var held: Array = []
	for c: Dictionary in Contracts.held():
		if c.get("state") == Contracts.ACCEPTED:
			held.append({"cid": String(c.cid), "title": String(c.get("title", "")), "deadline_day": int(c.get("deadline_day", 0))})
	return {
		"day": day(), "funds": BaseEconomy.funds(),
		"roster": roster(), "hiring": {"pool": Hiring.pool(hiring(), day()), "refreshed_day": int(hiring().get("refreshed_day", 1))},
		"stash": stash(), "prep": _prep(), "catalog": BaseEconomy.shop_catalog(), "held": held,
		"daily_wages": Roster.daily_wages(roster()), "bill_in_days": Economy.days_to_bill(), "weekly_bill": int(Economy.weekly_bill().total),
		"players": keys, "in_base": in_base(),
	}


func _changed(section_name: StringName) -> void:
	Campaign.mark_changed(section_name)  # -> _queue_broadcast


func _changed_all() -> void:
	for s: StringName in [&"base", &"roster", &"hiring"]:
		Campaign.mark_changed(s)


func _queue_broadcast() -> void:
	if _broadcast_queued or not campaign_running:
		return
	_broadcast_queued = true
	_broadcast.call_deferred()


func _broadcast() -> void:
	_broadcast_queued = false
	if not campaign_running or not multiplayer.is_server():
		return
	var text := JSON.stringify(build_view())
	_set_view(text)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_client_view.rpc(text)


@rpc("authority", "call_remote", "reliable")
func _client_view(text: String) -> void:
	_set_view(text)


func _set_view(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		view = GameState.from_json(parsed)
		view_changed.emit()


# --- The base screen and keys ----------------------------------------------------------------

## This machine: opens the base screen on `page` (BaseUI.PAGES).
func open_ui(page := "squad") -> void:
	if not is_instance_valid(_ui):
		_ui = BaseUI.new()
		get_tree().root.add_child(_ui)
	_ui.open(page)
	if _host_notice != "":
		note.emit(_host_notice)  # loading had something to say before the screen existed (load_or_new)
		_host_notice = ""


func _unhandled_input(event: InputEvent) -> void:
	if not campaign_running or not Net.is_hosting():
		return
	if event.is_action_pressed(&"quick_save"):
		note.emit(save_note(server_save()))
	elif DevTools.on() and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_END and (event as InputEventKey).shift_pressed and deployment_running():
		var me := level().players.get_node_or_null(^"1") as Node3D
		if me:
			server_extract_near(me.global_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and campaign_running and Net.is_hosting():
		server_save()
