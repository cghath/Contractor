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
## Client: everything the host put in the new level when it swapped (its players, world items
## and bodies) is here, and the loading screen is gone (_client_level_synced; B-04). `summary`
## is what the host had: {"level", "players": {name: [x, y, z]}, "items": count, "bodies": count}.
signal level_synced(summary: Dictionary)

const BASE_SCENE := "res://scenes/levels/base_fob.tscn"
const COMPOUND_SCENE := "res://scenes/levels/compound.tscn"
const SQUAD_SIZE := CompoundLevel.SQUAD_SIZE
## The zone a deployment goes to when nothing says otherwise. A campaign's zone saves are its
## own (zone_save_id), apart from the plain session's and other campaigns'.
const DEFAULT_ZONE_ID := "compound_01"
## Why Deploy waits (the button's tooltip and server_deploy's answer).
const NO_CONTRACT := "Prep a contract first"
## What a refused Deploy starts with while a player at the FOB isn't ready ("Waiting for: Player 2").
const WAITING_FOR := "Waiting for: "
## A squadmate left behind (a recovery contract's) joins the squad when a player comes this
## close (metres). Proposed.
const FOUND_M := 4.0
## How often the host reads the stash back from the hub's world items.
const STASH_POLL_S := 1.0
## Proposed: what a new company owns besides its hiring budget (enough to kit two players).
## Its carriers come with the base kit's MOLLE pouches on (BaseArmory.kitted_carrier_state),
## so magazines and the tourniquet go into them when picked up.
const STARTING_STASH := [["plate_carrier", 2], ["plate_ceramic_l4", 4], ["helmet", 2], ["assault_pack", 2], ["m4a1", 2],
	["mag_556", 12], ["ifak", 4], ["tourniquet", 6], ["smoke_grenade", 2], ["frag_grenade", 2],
	# Captain, 2026-10-14: the FOB starts with medical supplies, so a medic who used his kit on a
	# contract can restock it (before, only IFAKs and tourniquets were ever in the stash).
	["hemostatic_gauze", 8], ["pressure_bandage", 12], ["chest_seal", 6], ["splint", 4], ["burn_dressing", 4],
	["morphine", 8], ["npa", 4], ["epinephrine", 6], ["iv_18", 6], ["io_kit", 2], ["saline_500", 4], ["blood_500", 2]]
## Debug builds: Shift+End extracts everyone within this many metres of the host (until the map's
## extraction calls server_end_deployment).
const DEBUG_EXTRACT_M := 60.0
## A level switch waits at most this long for clients to stop sending (server_switch_level).
## B-04: 1 s is short on a lossy link or a loaded host; a client still sending its old player's
## Sync after the host swapped is the likely source of the 26 'Node not found:
## ".../Players/<id>/Sync"' errors on every peer in S0743. Going ahead without someone is logged.
const SWITCH_WAIT_S := 3.0
## Client: the loading screen after a level switch goes after this long even if the host's
## "all sent" never came (_client_level_synced), so a lost session can't leave it up.
const LOADING_MAX_S := 30.0
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
## Every peer: the ENet peers given LevelSwitch.LOAD_TIMEOUT for a switch into an 8 km zone, and
## when that runs out (msec) (_hold_timeouts).
var _timeouts_held := {}
var _zone_before := ""     # host: GameState.zone_id before the campaign took over (restored after)
var _host_notice := ""     # host: what loading the campaign has to tell the host (shown again on open_ui)
var _loading: CanvasLayer  # client: the loading screen while a switched level arrives (B-04)
var _loading_serial := 0
## Client: the host's summary of the last level it switched to (level_synced), for tests.
var last_switch_summary := {}
var _ready_peers := {}     # host: peer id -> true for each player ready to deploy (FOB ready-up)
## Host: who got out at an extraction whose debrief waits on the host's choice (a base assault
## due in its days; server_assault_choice), [Soldier]; and while the chosen days pass, whether
## the squad counts as home for the assault.
var _held_end: Array = []
var _squad_home_for_assault := false
## Host: the member ids whose dog tags (or bodies) came out at the extraction being settled
## (_collect_tags; Fallen), and whether it has been looked at yet.
var _tags_out := {}
var _tags_collected := false


func _ready() -> void:
	rng.randomize()
	add_to_group(Extraction.END_GROUP)  # end_deployment
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.session_ended.connect(_on_session_ended)
	Campaign.changed.connect(func(_name: StringName) -> void: _queue_broadcast())
	People.civilian_casualty.connect(RebelSupport.on_civilian_casualty)  # the locals remember (rebel support)
	Contracts.contract_closed.connect(RebelSupport.on_contract_closed)  # their own jobs done (part 3)
	Economy.changed.connect(_queue_broadcast)
	Economy.day_advanced.connect(_on_day_advanced)
	Contracts.contract_accepted.connect(_on_contract_accepted)
	Contracts.contract_closed.connect(_on_contract_closed)
	Contracts.contract_closed.connect(ZoneControl.on_contract_closed)  # a seize-and-hold won moves home (docs/lhd_home.md)
	Economy.day_advanced.connect(ZoneControl.on_day_advanced)  # the liaison's offer comes back
	Contracts.contract_closed.connect(FobBusiness.on_contract_closed)  # claude/income: a business's protection job done (or not)
	Contracts.contract_closed.connect(BlackMarket.on_contract_closed)  # claude/income: the last job's region opens its market
	Contracts.contract_closed.connect(Story.on_contract_closed)  # a story contract done moves the story on (docs/story.md)
	Economy.day_advanced.connect(Story.on_day_advanced)  # a failed story contract comes back; an act opens
	view_changed.connect(ZoneControl.on_view_changed)  # clients: the region map follows home


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
	_set_aside_old_saves()
	Campaign.reset_campaign()  # its files are aside by now: this only empties it in memory
	Contracts.new_full_campaign()
	ZoneControl.server_start(lhd_home_on_new())  # home: aboard the LHD (docs/lhd_home.md)
	Story.server_start()  # act 1's first story contract on the board (docs/story.md)
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
	# Two standing high command squads from the start (combined_arms.md 5.2), and 14 days of
	# their wages on top of the start cash so the first fortnight isn't a trap.
	var standing_rng := RandomNumberGenerator.new()
	standing_rng.seed = hash([int(h.seed), "standing"])
	if standing_squads:
		Heroes.seed_standing(roster(), day(), standing_rng)
		Economy.add_cash(Heroes.standing_wages(roster()) * Heroes.START_WAGE_DAYS, "Standing squads: their first fortnight")
	_hook_economy(true)
	_changed_all()


## Host: the saved campaign for Campaign.campaign_id, or a new one if there's none. A save that
## can't be read isn't taken as leave to start over on top of it (audit A1-01): load_campaign
## keeps its files aside and falls back on its backup; only with nothing readable does a new
## campaign start, its zone saves kept aside too, and the host is told (note, and on open_ui).
func load_or_new() -> void:
	var loaded := Campaign.load_campaign()
	if loaded:
		var renamed := Roster.rename_numbered_callsigns(roster())
		if renamed > 0:
			SessionLog.note("roster: %d numbered callsign(s) renamed (no \"Saint 2\"s)" % renamed)
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
	ZoneControl.server_loaded()  # a save from before zone control keeps its FOB
	Story.server_loaded()  # a save from before the story starts it now
	_hook_economy(true)
	var dep := RosterDeployment.active(roster())
	if not dep.is_empty() and not resume_info().is_empty():
		SessionLog.note("campaign loaded mid-deployment: resuming in %s" % String(dep.resume.zone_id))  # (LZ-4: prepare_session goes back there)
	elif not dep.is_empty():
		# Saved mid-deployment and not ended: everyone who went is back as they left the base.
		for mid: String in dep.squad:
			var m := member(mid)
			if not m.is_empty() and dep.get("fallen", {}).has(mid):
				m["status"] = Roster.DEAD
				m["gear"] = {}
				Roster.add_history(m, day(), "Killed in action in %s" % dep.get("zone_id", "?"))
		roster()["deployment"] = {}
		Contracts.server_abandon_deployment()
	_prune_prep_squad()  # a save from before the pick was kept clean may still hold the fallen
	_changed_all()


## Host: saves the campaign (the hub's stash and people read back first). Never one that was
## never loaded or started (no "day"): that would write an empty campaign over the save.
## Returns whether it was saved (audit A1-04: Campaign.save_error says why not).
func server_save() -> bool:
	if not started():
		push_warning("BaseHub: no campaign loaded; not saving over %s" % Campaign.save_path())
		return false
	if Contracts.assault_pending():
		return false  # (the debrief is paid but its days haven't passed: save_note says why)
	_read_back_base()
	_note_resume()
	return Campaign.save_campaign()


## Host, saving while out (docs/linked_zones.md call 11: "resume where you were"): the deployment
## remembers the zone it's in and the crossing it came in by ("resume"), the zone is saved as it
## stands, and everyone's gear goes onto their records (players' main characters, squadmates'),
## so loading puts the squad back there (resume_info), each with their wounds as they were
## ("vitals": Vitals.server_snapshot as var_to_str text, by "pk:<player key>" and "m:<member id>",
## put back as they spawn: _apply_resume). Live support cooldowns and losses are saved too.
func _note_resume() -> void:
	if not RosterDeployment.is_running(roster()) or in_base():
		return
	var lvl := level() as ZoneLevel
	if lvl == null:
		return
	var dep := RosterDeployment.active(roster())
	var vitals := {}
	dep["resume"] = {"zone_id": String(lvl.def.get("id", dep.get("zone_id", ""))), "arrive": String(dep.get("last_crossing", "")), "vitals": vitals}
	var helis := HeliSupports.of(lvl)
	dep["support_limits"] = helis.limits() if helis else {}
	GameState.save_zone()
	for p: Node in lvl.players.get_children():
		var s := p as Soldier
		if s and not s.vitals.is_dead():
			var main := Roster.main_character(roster(), player_key(s.name.to_int()))
			if not main.is_empty():
				main["gear"] = Roster.json_safe(s.inventory.net_state.duplicate(true))
			vitals["pk:" + player_key(s.name.to_int())] = var_to_str(s.vitals.server_snapshot())
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and not s.vitals.is_dead():
			server_store_member_gear(String(s.get_meta(&"roster_id")), s.inventory.net_state)
			vitals["m:" + String(s.get_meta(&"roster_id"))] = var_to_str(s.vitals.server_snapshot())


## Host: a body spawning in a resumed deployment (`key` "pk:<player key>" or "m:<member id>")
## gets the wounds it was saved with (_note_resume), once.
func _apply_resume(key: String, s: Soldier) -> void:
	var saved: Dictionary = (RosterDeployment.active(roster()).get("resume", {}) as Dictionary).get("vitals", {})
	if not saved.has(key):
		return
	var snap: Variant = str_to_var(String(saved[key]))
	saved.erase(key)
	if snap is Dictionary:
		s.vitals.server_restore(snap)


## The level a resumed deployment loads into (resume above), or {} for none.
func resume_info() -> Dictionary:
	var dep := RosterDeployment.active(roster())
	var r: Dictionary = dep.get("resume", {})
	var def := MissionRegistry.zone_def(String(r.get("zone_id", "")))
	if r.is_empty() or def.is_empty():
		return {}
	var info_def := def.duplicate(true)
	if String(r.get("arrive", "")) != "":
		info_def = _arrive_def(def, String(r.zone_id), String(r.arrive))
	return {"level": "zone", "def": info_def}


## Host: what to tell the player after server_save returned `saved`.
static func save_note(saved: bool) -> String:
	if not saved and Contracts.assault_pending():
		return "Campaign NOT saved: choose on the debrief first (a base assault falls due in its days)"
	return "Campaign saved" if saved else "Campaign NOT saved: %s" % (Campaign.save_error if Campaign.save_error != "" else "no campaign loaded")


## The zone save (GameState.zone_id) of the campaign's zone `zone_id`: each campaign keeps its
## own zones, apart from the plain session's ("compound_01") and other campaigns'.
func zone_save_id(zone_id: String) -> String:
	return "%s__%s" % [Campaign.campaign_id, zone_id]


func base_zone_id() -> String:
	return zone_save_id("fob")


## Whatever a new campaign in Campaign.campaign_id's name would otherwise load: the old save
## (with backup and interrupted write) and every zone save of it (a backup left behind would
## load as the new campaign's zone) are set aside (GameState.set_aside, "<file>.replaced-<date>-
## <time>"), never deleted (Captain, 2026-10-14). Usually there's nothing: New campaign archives
## first, and an unreadable save is kept aside by load_campaign.
func _set_aside_old_saves() -> void:
	for path: String in GameState.save_candidates(Campaign.save_path()):
		if FileAccess.file_exists(path):
			GameState.set_aside(path, "replaced")
	for path in _zone_save_files():
		GameState.set_aside(path, "replaced")


## Moves every zone save of the current campaign aside (GameState.set_aside): the campaign they
## belong to couldn't be read, and a new one starting in its name mustn't load them or delete them.
func set_aside_zone_saves() -> void:
	for path in _zone_save_files():
		push_warning("BaseHub: kept %s aside (its campaign couldn't be read)" % GameState.set_aside(path, "orphaned").get_file())


## The main menu's "New campaign (archive current saves)" (Captain, 2026-10-14): the current
## campaign (Campaign.campaign_id) is put away, never deleted: its save and every zone save of
## it (the FOB's included), with their backups, interrupted writes and copies kept aside, move
## into user://saves/archive-<date>/ (archive-<date>-<time>/ when that already holds a file of
## the same name), and the campaign in memory empties, so the next campaign host starts a new
## one. Outside a session only. Returns {"dir": the archive folder (global path), "moved": file
## names, "failed": file names that couldn't be moved and stay where they were}. `into` (a
## folder) instead of the dated one: for tests, which mustn't share the real archive folder.
func archive_campaign(into := "") -> Dictionary:
	var out := {"dir": "", "moved": [], "failed": []}
	if Net.is_hosting():
		push_warning("BaseHub: not archiving the campaign during a session")
		return out
	var files := _campaign_files()
	if files.is_empty():
		Campaign.restore({})
		return out
	var t := Time.get_datetime_dict_from_system()
	var dir := into if into != "" else "%s/archive-%04d-%02d-%02d" % [Campaign.SAVE_DIR, t.year, t.month, t.day]
	if files.any(func(f: String) -> bool: return FileAccess.file_exists("%s/%s" % [dir, f])):
		dir += "-%02d%02d%02d" % [t.hour, t.minute, t.second]
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in files:
		if DirAccess.rename_absolute("%s/%s" % [Campaign.SAVE_DIR, f], "%s/%s" % [dir, f]) == OK:
			(out.moved as Array).append(f)
		else:
			(out.failed as Array).append(f)
			push_error("BaseHub: couldn't move %s into %s; it stays where it is" % [f, dir])
	out["dir"] = ProjectSettings.globalize_path(dir)
	Campaign.restore({})  # nothing deleted: whatever couldn't move stays on disk
	campaign_running = false
	view = {}
	return out


## Every file of the current campaign in the saves folder: its save (with backup, interrupted
## write and copies kept aside) and each of its zone saves (likewise). File names.
func _campaign_files() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(Campaign.SAVE_DIR):
		return out
	var own := Campaign.campaign_id + ".json"
	var zones := zone_save_id("")
	for file in DirAccess.get_files_at(Campaign.SAVE_DIR):
		if file == own or file.begins_with(own + ".") or file.begins_with(zones):
			out.append(file)
	return out


## TEST ONLY: deletes every file of the current campaign (_campaign_files: its save and zone
## saves, the FOB's included, with backups, interrupted writes and copies kept aside) and empties
## it in memory. The game never deletes a save (Captain, 2026-10-14: new_campaign and each
## deployment set the old ones aside), so tests would pile those up run after run without this.
## Refuses (returns -1, deletes nothing) unless the campaign is a test's: campaign_id begins with
## "test_", so a real save (campaign_01) is never touched. Returns how many files went.
func delete_test_campaign_files() -> int:
	if not Campaign.campaign_id.begins_with("test_"):
		push_error("BaseHub: not deleting the files of '%s': only a test campaign's (test_...) are ever deleted" % Campaign.campaign_id)
		return -1
	var n := 0
	for f in _campaign_files():
		if DirAccess.remove_absolute("%s/%s" % [Campaign.SAVE_DIR, f]) == OK:
			n += 1
	Campaign.reset_campaign()  # nothing of it is left on disk: this only empties it in memory
	return n


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
	_prune_prep_squad()
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
	begin_prep(ContractGen.public_view(c), String(c.get("zone_kind", RosterDeployment.CONTRACT)), zone_id, "", contract_level_info(c))
	return ""


## The level a deployment on contract `c` loads into ({} for a zone with no layout): its zone's
## layout, with the contract's own night start or bad weather when it rolled any (missions 2,
## ContractGen.roll_conditions), which DayNight takes over the zone's save (DayNight.CONTRACT_SKY).
static func contract_level_info(c: Dictionary) -> Dictionary:
	var layout := MissionRegistry.zone_def(String(c.get("zone_id", "")))
	if layout.is_empty():
		return {}
	if c.has("hour") or c.has("weather"):
		layout = layout.duplicate(true)
		for key: String in ["hour", "weather"]:
			if c.has(key):
				layout[key] = c[key]
		layout[DayNight.CONTRACT_SKY] = true
	return {"level": "zone", "def": layout}


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
	var l := level()
	return l != null and l.is_base()


## The base level (BaseLevel or BaseZoneLevel, both with the FOB's public face), or null outside it.
func base_level():
	return level() if in_base() else null


## Which base to play (docs/linked_zones.md LZ-1): -1 the base zone except under a test scene (the
## suites keep BaseLevel until the base zone is proven, BaseLevel the fallback), 0 BaseLevel, 1 the
## base zone.
static var base_zone_mode := -1
## A new campaign starts with the two standing high command squads (combined_arms.md 5.2).
## Suites about the roster's own mechanics (base_test's hiring and counts) turn it off.
static var standing_squads := true
## Whether a new campaign starts aboard the LHD (docs/lhd_home.md; ZoneControl.home): -1 yes except
## under a test scene (the suites keep their base, as base_zone_mode), 0 no (the FOB, as before), 1 yes.
static var lhd_home_mode := -1
## Host: the crossing the next level the squad goes to puts them at (set_arrival; LZ-2).
var _next_arrival := ""
## Host (a crossing on, LZ-2): what each crosser brings into the next zone, put on their new body
## there: "p:<peer>" / "m:<member id>" -> {"gear": inventory net_state, "vitals": Vitals.server_snapshot}.
var _carry := {}
## Host: the switch under way is a crossing on (no second briefing in the next zone).
var _crossing_on := false
## The HVTs and hostages walking on with the squad (PeopleLayer.server_take_across), brought in
## when the next zone is up (server_land_people).
var _carry_people: Array = []
## The squad's vehicles driving on with it (_take_vehicles_across), and those waiting for their
## riders to be seated in the next zone (_seat_riders).
var _carry_vehicles: Array = []
var _seating: Array = []
## The supports following the squad on (_take_supports_across): {"helis": [kinds], "allied":
## [...], "aav": condition}, brought in FOLLOW_DELAY_S after it arrives (call 19: within 2 game
## minutes; one game minute at the zones' 6x clock), where it arrived (_arrived_at).
var _followers := {}
var _followers_at_ms := -1
var _arrived_at := Vector3.ZERO
const FOLLOW_DELAY_S := 10.0
const SEAT_WAIT_S := 15.0


## Whether the base is the base zone (BaseZoneLevel) rather than BaseLevel.
func base_as_zone() -> bool:
	if base_zone_mode >= 0:
		return base_zone_mode == 1
	var scene := get_tree().current_scene
	return scene == null or not scene.scene_file_path.begins_with("res://tests/")


## Whether a campaign started now starts aboard the LHD (lhd_home_mode).
func lhd_home_on_new() -> bool:
	if lhd_home_mode >= 0:
		return lhd_home_mode == 1
	var scene := get_tree().current_scene
	return scene == null or not scene.scene_file_path.begins_with("res://tests/")


## Whether home is the LHD (ZoneControl.home): until a zone is taken for the FOB.
func home_is_lhd() -> bool:
	return ZoneControl.home_is_lhd()


## The level_info() the base is played from: the LHD while it's home (LhdLevel), else the base
## (come home through a crossing: arriving at it, set_arrival).
func base_info() -> Dictionary:
	var arrive := _next_arrival
	_next_arrival = ""
	if home_is_lhd():
		return {"level": "lhd"}
	if base_as_zone():
		var def := BaseZoneLevel.def_for(Contracts.campaign_seed())
		if arrive != "":
			def["arrive"] = arrive
		return {"level": "base_zone", "def": def}
	return {"level": "base"}


## Host (Extraction, a crossing): the next level the squad goes to puts them at crossing `id`.
func set_arrival(id: String) -> void:
	_next_arrival = id


## Host (Extraction, a crossing on mid-deployment; docs/linked_zones.md LZ-2): everyone at it walks
## on into zone `to`, arriving at its crossing `to_crossing`, as they are: each player's and
## squadmate's gear and wounds come with them (_carry), the zone left is saved as it stands (its
## memory), the deployment and its contract go on. Returns "" or why not.
func server_cross_on(to: String, to_crossing: String, extraction: Extraction, air_point := {}) -> String:
	var def := MissionRegistry.zone_def(to)
	if def.is_empty():
		return "Nothing lies that way"
	var lvl := level()
	var point: Dictionary = air_point if not air_point.is_empty() else extraction.point_by_id(extraction.countdown_point) if extraction else {}
	var by_air := not air_point.is_empty()
	_carry.clear()
	for p: Node in lvl.players.get_children():
		var s := p as Soldier
		if s and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			_carry["p:%d" % s.name.to_int()] = {"gear": s.inventory.net_state.duplicate(true), "vitals": s.vitals.server_snapshot()}
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and not s.vitals.is_dead() and not s.is_queued_for_deletion():
			var mid := String(s.get_meta(&"roster_id"))
			server_store_member_gear(mid, s.inventory.net_state)
			if extraction and not point.is_empty() and not extraction.inside(point, s.body_point()):
				_leave_in_zone(s, String((lvl.get(&"def") as Dictionary).get("id", "")))  # left at the crossing: they wait here
				continue
			_carry["m:" + mid] = {"gear": s.inventory.net_state.duplicate(true), "vitals": s.vitals.server_snapshot()}
	_carry_vehicles = _take_vehicles_across(lvl, point)
	_followers = _take_supports_across(lvl)
	var people := lvl.get_node_or_null(^"People") as PeopleLayer
	_carry_people = people.server_take_across(point.pos, float(point.get("radius", Extraction.RADIUS_M)) * 2.0) \
		if people and point.get("pos") is Vector2 else []
	_tally_raid(lvl)  # what the raid hit here, before the zone goes (LZ-4)
	GameState.save_zone()  # the zone keeps what's in it while it remembers (zone memory)
	var dep := RosterDeployment.active(roster())
	dep["zone_id"] = to
	dep["last_crossing"] = to_crossing
	dep.erase("resume")
	var arrive := _arrive_def(def, to, to_crossing)
	if by_air:
		arrive.erase("arrive")
		arrive["air_insert"] = true  # flown in to its insertion LZ (server_land_people)
	var helis := lvl.get_node_or_null(NodePath(HeliSupports.NODE_NAME)) as HeliSupports
	dep["support_limits"] = helis.limits() if helis else {}  # cooldowns and losses go on with the deployment (LZ-3)
	# Travel time (call 7: 2 h a link on foot, 1 h when every player drove over, half an hour by
	# helicopter): the next zone's sky moves on by it, and the campaign's days turn over at each
	# midnight passed.
	var riding := 0
	for c: Dictionary in _carry_vehicles:
		riding += (c.seats as Dictionary).values().filter(func(k: String) -> bool: return k.begins_with("p:")).size()
	var leg_h := TRAVEL_VEHICLE_H if riding > 0 and riding >= _carry.keys().filter(func(k: String) -> bool: return k.begins_with("p:")).size() else TRAVEL_FOOT_H
	if by_air:
		leg_h = TRAVEL_AIR_H
	_travel_wound_s = minf(leg_h * TRAVEL_WOUND_S_PER_H, TRAVEL_WOUND_MAX_S)
	var hours := float(dep.get("travel_h", 0.0)) + leg_h
	var sky := DayNight.current()
	var hour_now: float = sky.hour if sky else float(def.get("hour", 9.0))
	arrive["hour"] = fposmod(hour_now + leg_h, 24.0)
	arrive[DayNight.TRAVELLED] = true  # that hour, not the one a remembered zone was left at (A2-08)
	if hour_now + leg_h >= 24.0:
		server_advance_days(1, "walking on to %s" % to)
	dep["travel_h"] = hours
	_fade_zone_save(to)
	_crossing_on = true
	SessionLog.note("crossing: the squad walks on from %s into %s (%d players, %d squadmates)" % [String(point.get("name", "?")), to,
		_carry.keys().filter(func(k: String) -> bool: return k.begins_with("p:")).size(), _carry.keys().filter(func(k: String) -> bool: return k.begins_with("m:")).size()])
	_changed_all()
	server_switch_level({"level": "zone", "def": arrive}, zone_save_id(to))
	return ""


## A raid's cost in standing (docs/linked_zones.md call 8: "a faction's sites cost standing with
## it and its allies"): with the zone's enemy faction, RAID_REP_PER_KILLS kills cost a point and
## each site taken out RAID_REP_PER_SITE (its allies follow through Economy.change_reputation's
## ripple). Heat comes from the kills and sites already (Pressure). Proposed.
const RAID_REP_PER_KILLS := 10
const RAID_REP_PER_SITE := 2


## Host: on a raid, what was hit in `lvl` (its Pressure's kills and sites down, against its enemy
## faction) is added to the deployment's "raid_hits" (faction -> {"kills", "sites"}), zone by zone.
func _tally_raid(lvl: CompoundLevel) -> void:
	var dep := RosterDeployment.active(roster())
	if String(dep.get("zone_kind", "")) != RosterDeployment.RAID or lvl == null:
		return
	var pressure := lvl.get_node_or_null(^"Pressure")
	var response := lvl.get_node_or_null(^"EnemyResponse")
	if pressure == null:
		return
	var faction := String(response.get(&"enemy_faction")) if response else "black_ridge"
	if not dep.has("raid_hits"):
		dep["raid_hits"] = {}
	var hits: Dictionary = dep.raid_hits.get(faction, {"kills": 0, "sites": 0})
	hits["kills"] = int(hits.kills) + (pressure.get(&"_counted_dead") as Dictionary).size()
	hits["sites"] = int(hits.sites) + (pressure.get(&"_down") as Dictionary).size()
	dep.raid_hits[faction] = hits


## Host, a raid's end: the standing it cost (RAID_REP_PER_KILLS, RAID_REP_PER_SITE).
func _settle_raid(dep: Dictionary) -> void:
	for faction: String in dep.get("raid_hits", {}):
		var hits: Dictionary = dep.raid_hits[faction]
		var cost := int(hits.kills) / RAID_REP_PER_KILLS + int(hits.sites) * RAID_REP_PER_SITE
		if cost > 0:
			Economy.change_reputation(faction, -cost, "raid: %d killed, %d sites" % [int(hits.kills), int(hits.sites)])


## Hours a crossing takes on foot (docs/linked_zones.md call 7; by vehicle and heli come with LZ-3).
const TRAVEL_FOOT_H := 2.0
const TRAVEL_VEHICLE_H := 1.0
const TRAVEL_AIR_H := 0.5


## Host (HeliCall, a transport told to fly the squad on: LZ-3): the squad goes on to zone `to` by
## air, everyone aboard the helicopter at `at` (x, z) crossing with it (those not aboard stay, as at
## a crossing), half an hour on the clock, flown in to the zone's insertion LZ. Returns "" or why not.
func server_fly_on(to: String, at: Vector2) -> String:
	if not deployment_running() or in_base():
		return "Not out on a deployment"
	if to == RegionMap.BASE:
		return "The base is a flight home: call extraction"
	return server_cross_on(to, "", MapNodes.extraction(level()), {"id": -1, "name": "the air", "pos": at, "radius": 12.0, "source": "heli"})


## Zone `to`'s def for walking in at its crossing `to_crossing` (LZ-2): "arrive" set, and its
## supports coming in from the base's side of it on the region map ("fob_side"; docs/linked_zones.md
## section 4), unless the zone names its own.
func _arrive_def(def: Dictionary, to: String, to_crossing: String) -> Dictionary:
	var out := def.duplicate(true)
	out["arrive"] = to_crossing
	var side := RegionMap.side_toward_base(to)
	if side != "" and not def.has("fob_side"):
		out["fob_side"] = side
	return out


## Host: the support helicopters' cooldowns and losses the running deployment carried across a
## crossing (HeliSupports.limits; LZ-3), {} with none.
func carried_support_limits() -> Dictionary:
	if not campaign_running or not RosterDeployment.is_running(roster()):
		return {}
	return RosterDeployment.active(roster()).get("support_limits", {})


## Host: what `key` ("p:<peer>" / "m:<member id>") carried across a crossing goes onto `s`.
## Host (server_cross_on): squadmate `s`, left at the crossing (Extraction's second confirm),
## stays in zone `zone_id` while the squad walks on: the deployment's "away" keeps where they
## are, their gear and their wounds. They wait there (_spawn_away) until the squad comes back for
## them; if the deployment ends first they're left behind (MIA there, a recovery contract).
func _leave_in_zone(s: Soldier, zone_id: String) -> void:
	var dep := RosterDeployment.active(roster())
	var mid := String(s.get_meta(&"roster_id"))
	var p := s.global_position
	if not dep.has("away"):
		dep["away"] = {}
	dep.away[mid] = {"zone_id": zone_id, "pos": [p.x, p.y, p.z], "gear": Roster.json_safe(s.inventory.net_state.duplicate(true)),
		"vitals": s.vitals.server_snapshot()}
	SessionLog.note("crossing: %s stays behind in %s" % [String(s.name), zone_id])


## Host, a zone up mid-deployment: squadmates left here at a crossing (_leave_in_zone) wait
## where they were, hurt as they were, until a player reaches them (_check_recovery_targets:
## then they follow and are back with the squad).
func _spawn_away(lvl: CompoundLevel) -> void:
	var dep := RosterDeployment.active(roster())
	var zone_id := String(lvl.get(&"def").get("id", "")) if lvl.get(&"def") is Dictionary else ""
	for mid: String in dep.get("away", {}):
		var a: Dictionary = dep.away[mid]
		var m := member(mid)
		if String(a.zone_id) != zone_id or m.is_empty() or lvl.ai.get_node_or_null(NodePath(String(m.callsign))):
			continue
		var stats := Roster.ai_stats(m)
		var data := {"name": String(m.callsign), "faction": "friendly", "variant": Soldier.COMPANY_VARIANT, "pos": Vector3(float(a.pos[0]), float(a.pos[1]) + 0.1, float(a.pos[2])),
			"loadout": [], "role": "", "team": 0, "slot": -1, "combat": stats.combat, "discipline": stats.discipline, "guard": true}
		data.merge(Roster.identity(m))
		var s: Soldier = lvl.spawn_soldier(data)
		s.role = StringName(m.get("role", Roles.RIFLEMAN))
		s.set_meta(&"roster_id", mid)
		s.set_meta(&"recovery", true)
		s.set_meta(&"away", true)
		s.dog_tags = Fallen.tags_of(m)
		s.inventory.net_state = GameState.from_json((a.gear as Dictionary).duplicate(true))
		s.vitals.server_restore(a.get("vitals", {}))
		var brain := SquadAI.of(s)
		if brain:
			brain.order = Squad.Order.HOLD


## Host (server_cross_on): the squad's vehicles in the crossing (docs/linked_zones.md "what
## crosses": vehicles driven in): a motor-pool vehicle, or any vehicle with one of the squad
## aboard, not a wreck or a support's. Each one's state (damage, fuel, cargo, its pool id) and who
## sits where ("p:<peer>", "m:<member id>") is kept, and it leaves this zone (not saved in it).
func _take_vehicles_across(lvl: CompoundLevel, point: Dictionary) -> Array:
	var out: Array = []
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null or not point.get("pos") is Vector2:
		return out
	for v: Vehicle in layer.vehicles():
		if v.wrecked or v.is_burning() or v.kind in [Vehicle.HELICOPTER, Vehicle.STATIC] or v.has_meta(&"support") or not Extraction.inside(point, v.global_position):
			continue
		var seats := {}
		for s: Soldier in v.occupants():
			if not s.vitals.is_dead() and not s.is_ai():
				seats[str(v.seat_of(s))] = "p:%d" % s.name.to_int()
			elif not s.vitals.is_dead() and s.has_meta(&"roster_id"):
				seats[str(v.seat_of(s))] = "m:" + String(s.get_meta(&"roster_id"))
		if seats.is_empty() and MotorPool.pool_id(v) == "":
			continue  # nobody of ours aboard and not the company's: it stays
		var rec := v.to_save()
		rec.erase("pos")
		rec.erase("rot")
		rec.erase("bodies")
		out.append({"model": v.model, "scheme": v.scheme, "faction": String(v.faction), "id": v.vehicle_id, "record": rec,
			"pool_id": MotorPool.pool_id(v), "seats": seats})
		for s: Soldier in v.occupants():
			v.server_exit(s)
		v.set_meta(&"no_save", true)
		v.queue_free()
	return out


## Host: the squad flown on to `lvl` (server_fly_on) comes in aboard a helicopter landing at its
## insertion LZ (HeliSupports.server_insert, as a briefing's heli insertion), once its squadmates
## are in; on foot there if it can't fly.
func _fly_in(lvl: CompoundLevel) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(lvl) or lvl != level():
		return
	var ins: Array = (lvl.get(&"def") as Dictionary).get("insertion", [])
	var at: Variant = lvl.call(&"insertion_points")[0] if lvl.has_method(&"insertion_points") else Vector3.ZERO
	var p: Vector3 = at
	if not HeliSupports.server_insert(lvl, Vector2(p.x, p.z)):
		SessionLog.note("crossing by air: no helicopter could fly them in; on foot at the insertion point (%d listed)" % ins.size())


## Host (server_cross_on): the supports out with the squad follow it (docs/linked_zones.md section
## 4: helicopters airborne and empty, the AAV, allied elements).
func _take_supports_across(lvl: CompoundLevel) -> Dictionary:
	var out := {}
	var helis := HeliSupports.of(lvl)
	var allied := AlliedTroops.current(lvl)
	var aav := AavSupport.of(lvl)
	if helis:
		out["helis"] = helis.server_take_followers()
	if allied:
		out["allied"] = allied.server_take_followers()
	if aav:
		out["aav"] = aav.server_take_follower()
	return out


## Host (_process): the followers come in once FOLLOW_DELAY_S has passed since the squad arrived.
func _land_followers() -> void:
	if _followers_at_ms < 0 or Time.get_ticks_msec() < _followers_at_ms:
		return
	_followers_at_ms = -1
	var lvl := level()
	var host := lvl.players.get_node_or_null(^"1") as Soldier if lvl else null
	if host == null:
		_followers = {}
		return
	var helis := HeliSupports.of(lvl)
	var allied := AlliedTroops.current(lvl)
	var aav := AavSupport.of(lvl)
	if helis and not (_followers.get("helis", []) as Array).is_empty():
		helis.server_follow_in(_followers.helis, host)
	if allied and not (_followers.get("allied", []) as Array).is_empty():
		allied.server_follow_in(_followers.allied, host, _arrived_at)
	if aav:
		aav.server_follow_in(_followers.get("aav", {}), host)
	SessionLog.note("crossing: supports followed (%s)" % str(_followers))
	_followers = {}


## Host, a zone up after a crossing on: the vehicles that drove on with the squad are parked by the
## host's player, as they were, their riders seated again as they arrive (_seat_riders).
func _land_vehicles(lvl: CompoundLevel, at: Vector3) -> void:
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null:
		_carry_vehicles = []
		return
	var centre := Vector3.ZERO
	var dir := (centre - at)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP)
	for i in _carry_vehicles.size():
		var c: Dictionary = _carry_vehicles[i]
		var pos := lvl.above_ground(at + dir * 10.0 + side * (float(i) - (_carry_vehicles.size() - 1) * 0.5) * 7.0) + Vector3(0, 0.6, 0)
		var xform := Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
		var v := layer.server_spawn(String(c.model), xform, String(c.scheme), StringName(String(c.faction)), String(c.id), c.record)
		if v == null:
			continue
		if String(c.pool_id) != "":
			v.set_meta(&"pool_id", String(c.pool_id))
			v.set_meta(&"no_save", true)
		var ext := MapNodes.extraction(lvl)
		if ext:
			ext.mark_driven_in(v)  # it came in with the squad: it can drive them out again
		_seating.append({"vehicle": v, "seats": (c.seats as Dictionary).duplicate(), "until": Time.get_ticks_msec() + int(SEAT_WAIT_S * 1000.0)})
	SessionLog.note("crossing: %d vehicle(s) drove on with the squad" % _carry_vehicles.size())
	_carry_vehicles = []


## Host (_process): riders of vehicles that drove on get back in their seats once they're in the
## zone (players spawn as they load in, squadmates as the squad fills), for up to SEAT_WAIT_S.
func _seat_riders() -> void:
	var lvl := level()
	for w: Dictionary in _seating.duplicate():
		var v := w.vehicle as Vehicle
		if lvl == null or not is_instance_valid(v) or Time.get_ticks_msec() > int(w.until):
			_seating.erase(w)
			continue
		for seat: String in (w.seats as Dictionary).keys():
			var key := String(w.seats[seat])
			var s: Soldier = null
			if key.begins_with("p:"):
				s = lvl.players.get_node_or_null(NodePath(key.substr(2))) as Soldier
			else:
				for n: Node in lvl.ai.get_children():
					if n is Soldier and String(n.get_meta(&"roster_id", "")) == key.substr(2):
						s = n
			if s and not s.vitals.is_dead() and Vehicle.ride_of(s) == null and v.server_enter(s, int(seat)):
				w.seats.erase(seat)
		if (w.seats as Dictionary).is_empty():
			_seating.erase(w)


## Host, a zone up after a crossing on (ZoneLevel): the HVTs and hostages who came along arrive
## by the host's player, following whoever led them; squadmates left here earlier are waiting;
## vehicles that drove on are parked by them.
func server_land_people(lvl: CompoundLevel) -> void:
	_spawn_away(lvl)
	var zone_def: Variant = lvl.get(&"def")
	if zone_def is Dictionary and (zone_def as Dictionary).get("air_insert", false):
		_fly_in.call_deferred(lvl)
	if not _followers.is_empty():
		var first := lvl.players.get_node_or_null(^"1") as Soldier
		_arrived_at = first.global_position if first else Vector3.ZERO
		_followers_at_ms = Time.get_ticks_msec() + int(FOLLOW_DELAY_S * 1000.0)
	if not _carry_vehicles.is_empty():
		var host := lvl.players.get_node_or_null(^"1") as Soldier
		_land_vehicles(lvl, host.global_position if host else Vector3.ZERO)
	if _carry_people.is_empty():
		return
	var people := lvl.get_node_or_null(^"People") as PeopleLayer
	var me := lvl.players.get_node_or_null(^"1") as Soldier
	if people:
		people.server_bring_in(_carry_people, me.global_position if me else Vector3.ZERO, me)
		SessionLog.note("crossing: %d HVT(s)/hostage(s) came along" % _carry_people.size())
	_carry_people = []


func _apply_carry(key: String, s: Soldier) -> void:
	var c: Dictionary = _carry.get(key, {})
	if c.is_empty():
		return
	_carry.erase(key)
	s.inventory.net_state = (c.gear as Dictionary).duplicate(true)
	s.vitals.server_restore(c.get("vitals", {}))
	_travel_wounds(s)


## Wounds on the way over (Captain, 2026-10-19: "tick, but capped"): TRAVEL_WOUND_S_PER_H of the
## wound model's time for each hour the crossing took, at most TRAVEL_WOUND_MAX_S, and never past
## going down or TRAVEL_BLOOD_FLOOR of the blood: a warning to treat before crossing, not a death
## on the road. Proposed numbers.
const TRAVEL_WOUND_S_PER_H := 90.0
const TRAVEL_WOUND_MAX_S := 180.0
const TRAVEL_BLOOD_FLOOR := 0.55
var _travel_wound_s := 0.0


func _travel_wounds(s: Soldier) -> void:
	var left := _travel_wound_s
	while left > 0.0 and s.vitals.is_up() and s.vitals.blood_fraction() > TRAVEL_BLOOD_FLOOR:
		var step := minf(left, 5.0)
		s.vitals.server_advance(step)
		left -= step


## Host (Extraction, a crossing confirmed in the base zone; docs/linked_zones.md LZ-2): the squad
## walks out into zone `to`, arriving at its crossing `to_crossing`: a deployment there, with the
## prepped contract if it's for that zone, else none (a raid's rules come with LZ-4). Standing in
## the crossing together is the ready-up. Returns "" or why not.
func server_cross_from_base(to: String, to_crossing: String) -> String:
	var def := MissionRegistry.zone_def(to)
	if def.is_empty():
		return "Nothing lies that way"
	var prep := _prep()
	var contract: Dictionary = prep.get("contract", {})
	var options := {"crossing": true, "zone_id": to}
	if contract.is_empty() or String(contract.get("zone_id", "")) != to:
		options["no_contract"] = true
		options["zone_kind"] = RosterDeployment.RAID  # out without a contract: a raid (LZ-4)
	var arrive := _arrive_def(def, to, to_crossing)
	options["level"] = {"level": "zone", "def": arrive}
	if not contract.is_empty() and String(contract.get("zone_id", "")) == to:
		var prepped: Dictionary = prep.get("level", {})
		if prepped.has("def"):
			options["level"] = {"level": "zone", "def": _arrive_def(prepped.def, to, to_crossing)}
	SessionLog.note("crossing: the squad walks out of the base into %s" % to)
	var why := server_deploy(options)
	if why == "":
		RosterDeployment.active(roster())["last_crossing"] = to_crossing  # (a save while out resumes here)
	return why


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
	var resume := resume_info()
	if not resume.is_empty():
		GameState.zone_id = zone_save_id(String(resume.def.id))  # back where the squad was (LZ-4)
		_swap_level(resume)
		return
	GameState.zone_id = base_zone_id()
	if not in_base():
		_swap_level(base_info())


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
	if _switch_to.get("def") is Dictionary and not (_switch_to.def as Dictionary).has("season"):
		_switch_to.def["season"] = Season.of_day(day())  # the campaign's season: crops, the snow line (queue item 1.3)
	_switch_zone = zone_id
	_switch_waiting = {}
	for id in multiplayer.get_peers():
		_switch_waiting[id] = true
	if _switch_waiting.is_empty():
		_do_switch()
		return
	if LevelSwitch._big(_switch_to):  # (cg_brief 3.3, F-302: the clients kept in while every end makes the 8 km zone)
		_hold_timeouts(Array(multiplayer.get_peers()))
		_client_hold_timeouts.rpc()
	_client_hold_sync.rpc()
	var serial := _switch_serial + 1
	_switch_serial = serial
	get_tree().create_timer(SWITCH_WAIT_S).timeout.connect(func() -> void:
		if _switch_serial == serial and switch_pending():
			push_warning("BaseHub: level switch went ahead without peers %s (B-04)" % [_switch_waiting.keys()])
			_do_switch())


## Host: a level switch is waiting for clients.
func switch_pending() -> bool:
	return not _switch_to.is_empty()


func _do_switch() -> void:
	# What players picked up or dropped at the hub while the switch waited counts (the stash
	# poll stops while it waits, and server_deploy read the hub back before it).
	_read_back_base()
	if level() is BaseZoneLevel and campaign_running:
		GameState.save_zone()  # the base zone keeps what lies outside the wire (its "fob" save, never set aside)
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
	_close_screens_for(fresh)
	_client_switch_level.rpc(info)
	fresh.player_roles = roles
	fresh._on_hosted()
	for id in multiplayer.get_peers():
		fresh._on_peer_joined(id)
	if not fresh.is_base() and RosterDeployment.is_running(roster()) and not _crossing_on:
		_open_briefing(fresh)
	_crossing_on = false
	_queue_broadcast()
	# Last on the same reliable channel as everything the new level spawned above: a client
	# that gets this has all of that, so its loading screen can go (B-04).
	_client_level_synced.rpc(switch_summary(fresh))
	level_switched.emit(fresh)


## What `lvl` holds that a client must have before it plays (_client_level_synced): its players
## where they stand, and how many world items and bodies.
static func switch_summary(lvl: CompoundLevel) -> Dictionary:
	var players := {}
	for p: Node in lvl.players.get_children():
		if p is Soldier and not p.is_queued_for_deletion():
			var at := (p as Soldier).position
			players[String(p.name)] = [at.x, at.y, at.z]
	var live := func(n: Node) -> bool: return not n.is_queued_for_deletion()
	return {"level": String(lvl.level_info().get("level", "")), "players": players,
		"items": lvl.items.get_children().filter(live).size(), "bodies": lvl.bodies.get_children().filter(live).size()}


## Host: the squad arrived in the zone on a contract: the briefing opens for everyone on the
## zone's map (the contract's objectives and what intel knows of the enemy; insertion points
## from the zone). Its start (_on_briefing_started) makes the contract live.
func _open_briefing(lvl: CompoundLevel) -> void:
	var c: Dictionary = RosterDeployment.active(roster()).get("contract", {})
	var briefing := MapNodes.briefing(lvl)
	Contracts.heal_module_id(Contracts.contract(String(c.get("cid", ""))), lvl)  # an older build's contract may name a module this layout lacks
	if c.is_empty() or briefing == null:
		return
	briefing.server_open(briefing_contract(String(c.get("cid", ""))), briefing_zone(lvl, c))
	briefing.deployment_started.connect(_on_briefing_started.bind(String(c.get("cid", ""))), CONNECT_ONE_SHOT)


## A held contract as the briefing shows it (Briefing's contract shape): its objectives on
## the map (at its target module) and its brief; what intel knows of the enemy.
static func briefing_contract(cid: String) -> Dictionary:
	var c := Contracts.contract(cid)
	var objectives: Array = []
	for o: Dictionary in Objectives.placed(Objectives.from_contract(c, Contracts.module_origin(c))):  # (a leg next door has no place on this map: LZ-7)
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
		if lvl is ZoneLevel and String(c.get("module_id", "")) != "":  # Captain, 2026-10-15: within a sensible walk of the target
			var at := Contracts.module_origin(c)
			var near := ZoneDef.insertion_options((lvl as ZoneLevel).def, Vector2(at.x, at.z))
			if not near.is_empty():
				ins = []
				for i in near.size():
					var spot := near[i]
					ins.append({"id": "insertion_%d" % (i + 1), "name": "Insertion %d (%s, %d m from the target)" % [i + 1, "closer" if i == 0 else "safer", roundi(spot.distance_to(Vector2(at.x, at.z)))],
						"pos": [spot.x, spot.y], "method": "foot"})
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
	var me: Node = lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) if lvl else null
	var sync := me.get_node_or_null(^"Sync") as MultiplayerSynchronizer if me else null
	if sync:
		sync.public_visibility = false
	_server_switch_ready.rpc_id(1)


## A switch into an 8 km zone (LevelSwitch._big) holds each end's frames 10-60 s while it makes the
## zone, the host's first; past ENet's 5 s a client was dropped mid-switch (the optypes suite's, as
## it followed the host from one operation to the next). Both ends give each other
## LevelSwitch.LOAD_TIMEOUT from the switch's start until the client has the level and
## LevelSwitch.LOAD_SETTLE_S more (at most LOAD_TIMEOUT's max), then Net.ENET_TIMEOUT again, as a
## late joiner gets (D3-21). cg_brief 3.3, F-302; Proposed.
func _hold_timeouts(ids: Array) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var t: Array = LevelSwitch.LOAD_TIMEOUT
	for id: int in ids:
		if enet.get_peer(id):
			enet.get_peer(id).set_timeout(int(t[0]), int(t[1]), int(t[2]))
			_timeouts_held[id] = Time.get_ticks_msec() + int(t[2])
	get_tree().create_timer(float(t[2]) / 1000.0 + 1.0).timeout.connect(_release_timeouts.bind(ids, true))


func _release_timeouts(ids: Array, only_overdue := false) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for id: int in ids:
		if not _timeouts_held.has(id) or (only_overdue and Time.get_ticks_msec() < int(_timeouts_held[id])):
			continue
		_timeouts_held.erase(id)
		if enet and enet.get_peer(id):
			enet.get_peer(id).set_timeout(Net.ENET_TIMEOUT[0], Net.ENET_TIMEOUT[1], Net.ENET_TIMEOUT[2])


@rpc("authority", "call_remote", "reliable")
func _client_hold_timeouts() -> void:
	_hold_timeouts([MultiplayerPeer.TARGET_PEER_SERVER])


## Host: a client has the 8 km zone it switched to: its timeouts back once it has settled.
@rpc("any_peer", "call_remote", "reliable")
func _server_level_loaded() -> void:
	if multiplayer.is_server():
		get_tree().create_timer(LevelSwitch.LOAD_SETTLE_S).timeout.connect(_release_timeouts.bind([multiplayer.get_remote_sender_id()]))


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
	_show_loading(String(info.get("level", "")))
	var fresh := _swap_level(info)
	_close_screens_for(fresh)
	level_switched.emit(fresh)


## Client: the host sent everything the switched level started with (after
## _client_switch_level, on the same reliable channel, so it all came first): the loading
## screen goes.
@rpc("authority", "call_remote", "reliable")
func _client_level_synced(summary: Dictionary) -> void:
	last_switch_summary = summary
	_hide_loading()
	if _timeouts_held.has(MultiplayerPeer.TARGET_PEER_SERVER):  # (F-302)
		_server_level_loaded.rpc_id(1)
		get_tree().create_timer(LevelSwitch.LOAD_SETTLE_S).timeout.connect(_release_timeouts.bind([MultiplayerPeer.TARGET_PEER_SERVER]))
	level_synced.emit(summary)


## Client: whether the loading screen is up (a level switch still arriving).
func loading() -> bool:
	return is_instance_valid(_loading)


## Client: covers the screen while a switched level's players, items and objectives arrive, so
## nobody plays in a half-sent level (players at the origin, items missing) on a slow link.
func _show_loading(kind: String) -> void:
	_hide_loading()
	_loading = CanvasLayer.new()
	_loading.name = "LevelLoading"
	_loading.layer = 120
	## In the shared look (Captain, 2026-10-14: "all the UIs need a pass"; docs/ui_audit.md
	## branch 2): the theme's title text, wrapping across the whole window and centred in it,
	## over the kit's dim, instead of a default-theme label anchored at the centre.
	var shade := UiKit.dim(0.94)
	UiKit.apply(shade)
	_loading.add_child(shade)
	var label := UiKit.title("Loading %s..." % {"base": "the base", "zone": "the zone", "base_zone": "the base", "lhd": "the LHD"}.get(kind, "the level"))
	label.name = "Label"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(label)
	add_child(_loading)
	_loading_serial += 1
	var serial := _loading_serial
	get_tree().create_timer(LOADING_MAX_S).timeout.connect(func() -> void:
		if serial == _loading_serial and loading():
			push_warning("BaseHub: the level switch's last spawns never arrived; loading screen taken down")
			_hide_loading())


func _hide_loading() -> void:
	if is_instance_valid(_loading):
		_loading.queue_free()
	_loading = null


## Every peer: heading into a zone, the contract screens close (Contracts.close_screens): a
## debrief still up from the last deployment doesn't hold this player at it (Captain,
## 2026-10-14). Back at the base the debrief stays: that's where it's read.
func _close_screens_for(fresh: CompoundLevel) -> void:
	if fresh != null and not fresh.is_base():
		Contracts.close_screens()


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
	var lvl = base_level()
	if lvl == null or not campaign_running:
		return
	base()["stash"] = lvl.server_collect_stash()
	var gear: Dictionary = lvl.server_read_muster_gear()
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
			_seat_riders()
			_land_followers()
			BaseAssault.server_tick_out(STASH_POLL_S)  # the base holding out while the squad is near (LZ-5)
			ZoneControl.server_scan(level())  # HQ and QRF bases down flip the zone (docs/lhd_home.md)
		return
	var now: Array = base_level().server_collect_stash()
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
	var p: Soldier = lvl.players.get_node_or_null(str(peer)) as Soldier if lvl else null
	if p and campaign_running:
		_apply_player_gear(peer, p)
	_queue_broadcast()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and campaign_running:
		server_clear_ready()  # someone new at the FOB: everyone readies again, with them in the plan
		_client_view.rpc_id(id, JSON.stringify(build_view()))


# --- FOB ready-up -------------------------------------------------------------------------------
# Captain, 2026-10-14: "should be a ready up button instead in the fob". In co-op the host took
# the next contract and deployed while a client was still reading the debrief, and left them
# behind. Every player at the FOB now readies up (the in-zone briefing's pattern, Briefing.
# ready_peers / all_ready); the host's Deploy is refused, naming who isn't ready, until all are.
# The host's own Deploy is their ready, so a host alone deploys as before.

## The players in this session, by peer id (the host is 1). Clients read it from the view.
func session_peers() -> Array:
	if not multiplayer.is_server():
		var keys: Array = view.get("players", {}).keys().map(func(k: Variant) -> int: return int(k))
		keys.sort()
		return keys
	var peers: Array = [1]
	if multiplayer.has_multiplayer_peer():
		for id in multiplayer.get_peers():
			if id != 1:
				peers.append(id)
	peers.sort()
	return peers


## The peers who said they're ready (host: the live set; clients: the view's copy).
func ready_peers() -> Array:
	if not multiplayer.is_server():
		return (view.get("ready", []) as Array).map(func(id: Variant) -> int: return int(id))
	return _ready_peers.keys()


## Whether `peer` counts as ready. The host always does: pressing Deploy is the host's ready.
func is_ready(peer: int) -> bool:
	return peer == 1 or peer in ready_peers()


## The players a Deploy waits for, by name as the briefing shows them ("Player 2").
func not_ready_names() -> Array[String]:
	var out: Array[String] = []
	for id: int in session_peers():
		if not is_ready(id):
			out.append("Player %d" % id)
	return out


## Every player in the session is ready (always so for a host alone).
func all_ready() -> bool:
	return not_ready_names().is_empty()


## Host: `peer` is ready to deploy, or stands down. Everyone sees it through the view.
func server_set_ready(peer: int, is_ready_now: bool) -> void:
	if not multiplayer.is_server():
		return
	if is_ready_now:
		_ready_peers[peer] = true
	else:
		_ready_peers.erase(peer)
	_queue_broadcast()


## Host: nobody is ready any more (after a deployment starts, and when a player joins).
func server_clear_ready() -> void:
	if _ready_peers.is_empty():
		return
	_ready_peers.clear()
	_queue_broadcast()


## Host: a player leaving keeps what they stand up in (on their main character, or their
## stand-in); one leaving while down leaves it on their body (CompoundLevel).
func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server() or not campaign_running:
		return
	var lvl := level()
	var p: Soldier = lvl.players.get_node_or_null(str(id)) as Soldier if lvl else null
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
	if _ready_peers.erase(id):
		_queue_broadcast()


func _on_session_ended() -> void:
	_hide_loading()
	campaign_running = false
	_hook_economy(false)
	view = {}
	_restore_zone_id()
	_profiles.clear()
	_gear_applied.clear()
	_ready_peers.clear()
	_held_end = []


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


## B-23: in a campaign a player's saved gear (their main character's, or their stand-in's) is
## the one source of what they carry: it replaces whatever the body had, and no role kit is
## stacked on top (CompoundLevel.rebalance_squad leaves campaign players to server_give_due_kit).
## A brand-new main character has no gear yet, so they owe their role's kit once ("kit_due"),
## given as soon as their squad role is known.
func _apply_player_gear(peer: int, player: Soldier) -> void:
	if _gear_applied.has(peer):
		return
	_gear_applied[peer] = true
	var key := player_key(peer)
	var fresh := not Roster.players(roster()).has(key)
	var main := Roster.main_character(roster(), key, Roles.local_choice if peer == 1 else Roles.RIFLEMAN)
	if fresh:
		main["kit_due"] = true
	player.face = Roster.player_face(main)  # their own face all campaign (replicated)
	var gear: Dictionary = main.get("gear", {})
	var dep := RosterDeployment.active(roster())
	var stand_in: bool = dep.has("stand_ins") and dep.stand_ins.has(key) and not member(String(dep.stand_ins[key])).is_empty()
	if stand_in:
		var sm := member(String(dep.stand_ins[key]))
		var own: Dictionary = main.get("gear", {})
		var own_kit := not Restock.is_blank(Restock.template_of(own))
		if own_kit and not (dep.get("stand_in_gear", {}) as Dictionary).has(key):
			# Captain, 2026-10-15 (loadouts reset on infiltration): a recovering player plays the
			# stand-in in his OWN kit, not the stand-in's. It moves (never copies) onto the
			# stand-in for the deployment; RosterDeployment.resolve moves it home again.
			if not dep.has("stand_in_gear"):
				dep["stand_in_gear"] = {}
			dep.stand_in_gear[key] = Roster.json_safe((sm.get("gear", {}) as Dictionary).duplicate(true))
			sm["gear"] = own.duplicate(true)
			main["gear"] = {}
		gear = sm.get("gear", {})
		var who := Roster.identity(sm)
		player.face = SoldierLook.make(int(who.look_seed), String(who.nation), String(who.body))  # they are the stand-in
		var msg := "%s is recovering: you play %s%s" % [main.name, sm.callsign, ", in your own kit" if (dep.get("stand_in_gear", {}) as Dictionary).has(key) else ""]
		SessionLog.note("%s: %s" % [player_key(peer), msg])
		player._client_message.rpc_id(peer, msg)
	elif main.get("kit_due", false) and not Restock.is_blank(Restock.template_of(gear)):
		main.erase("kit_due")  # they already have gear of their own: that wins
	player.inventory.net_state = GameState.from_json(gear.duplicate(true))
	player.dog_tags = Fallen.tags_of(member(String(dep.stand_ins[key]))) if stand_in else Fallen.player_tags(key, main)  # every company soldier wears tags
	_apply_carry("p:%d" % peer, player)  # came on through a crossing: as they were (LZ-2)
	_apply_resume("pk:" + player_key(peer), player)  # a saved deployment resumed: wounds as saved (LZ-4)
	if fresh:
		_changed(&"roster")
	server_give_due_kit(player)


## Host (B-23): a campaign player whose brand-new main character still owes their role's kit
## gets it, once, on top of their (empty) saved gear. Waits until their gear is on
## (_apply_player_gear) and their squad role is known (CompoundLevel.rebalance_squad), in
## whichever order those come; a stand-in plays in the stand-in's own gear. Returns whether
## the kit went on. This is the campaign's only role-kit path: a test harness that kits its
## players itself (tests/coop_soak.gd _kit_players on test/coop-soak, its B-23 workaround) must
## stand down in a campaign when BaseHub.has_method(&"server_give_due_kit"), or a brand-new
## player carries two kits (review of B-23, 2026-10-14).
func server_give_due_kit(player: Soldier) -> bool:
	if not campaign_running or not is_instance_valid(player) or player.role == &"":
		return false
	var peer := player.name.to_int()
	if not _gear_applied.has(peer):
		return false
	var key := player_key(peer)
	var main: Dictionary = Roster.players(roster()).get(key, {})
	if not main.get("kit_due", false):
		return false
	var dep := RosterDeployment.active(roster())
	if dep.has("stand_ins") and dep.stand_ins.has(key) and not member(String(dep.stand_ins[key])).is_empty():
		return false
	main.erase("kit_due")
	Roles.apply_kit(player.inventory, player.role)
	SessionLog.note("%s is new to the company: their %s kit, once" % [SessionLog.who(player), player.role])
	_changed(&"roster")
	return true


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
	var cost := RosterDeployment.respawn_cost(roster(), BaseEconomy.respawn_price(), Prices.respawn_rise(), Prices.respawn_max())
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
## contract, leaving any prepared job for later (raids; the Deploy request never sends it).
## Every player must be ready first (FOB ready-up): it returns WAITING_FOR and who isn't,
## and readiness clears once
## the deployment starts. Players whose main character is recovering get a stand-in (an
## available member not in the squad, else a free rookie). Returns "" or why it can't.
func server_deploy(options := {}) -> String:
	if not multiplayer.is_server():
		return "Only the host deploys"
	if RosterDeployment.is_running(roster()):
		return "A deployment is already running"
	RebelSupport.on_deployment_started()
	_read_back_base()
	var prep := _prep()
	var contract: Dictionary = {} if options.get("no_contract", false) else prep.get("contract", {})
	# Without a contract there's no briefing, so no extraction and no way home (P0331): refuse.
	if contract.is_empty() and not options.get("no_contract", false):
		return NO_CONTRACT
	if not all_ready() and not options.get("crossing", false):  # walking out through a crossing together is the ready-up (LZ-2)
		return WAITING_FOR + ", ".join(PackedStringArray(not_ready_names()))
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
	var dep := RosterDeployment.begin(roster(), squad, zone_kind, zone_id, scene, day(), contract, stand_ins)
	dep["detachments"] = Heroes.deploying(roster(), Heroes.squads_max(int(contract.get("rated", 3)), zone_kind == RosterDeployment.HOT,
		bool(contract.get("operation", false))))  # high command squads (5.2): the standing two unless left at home
	_record_loadouts(dep)  # S2: what everyone deploys in, for "Restock last loadout" back at the base
	SessionLog.note("deployment started: zone %s (%s), contract %s, day %d; squad %s; %d player%s; %d free respawns" % [zone_id, zone_kind,
		_contract_text(contract), day(), _callsigns(dep.squad), _player_count(), "" if _player_count() == 1 else "s",
		int(dep.respawns_free)])
	if not contract.is_empty():
		prep["contract"] = {}
		prep["level"] = {}
	_ready_peers.clear()  # back at the FOB everyone readies again for the next one
	_changed_all()
	_fade_zone_save(zone_id)  # zone memory (LZ-2): fresh after a week, emptier before that
	server_switch_level(info, zone_save_id(zone_id))
	return ""


## Zone memory (docs/linked_zones.md 2b, call 5: "fades over a week"): a zone left this many
## campaign days ago comes back fresh (its save set aside, never deleted); this many, without its
## bodies and the gear lying about (the damage and cleared sites stay). The base never fades.
const ZONE_FRESH_DAYS := 7
const ZONE_LOOSE_DAYS := 3


## Host: before zone `zone_id` loads, how much of it is remembered (ZONE_FRESH_DAYS,
## ZONE_LOOSE_DAYS, from its save's "left_day"). A save without one (from before zone memory, or
## an earlier campaign build) is set aside, as every contract's zone used to be.
func _fade_zone_save(zone_id: String) -> void:
	GameState.fade_loose = false
	if zone_save_id(zone_id) == base_zone_id():
		return
	var path := "%s/%s.json" % [GameState.SAVE_DIR, zone_save_id(zone_id)]
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var stamped: bool = data is Dictionary and data.has("left_day") and int(data.left_day) >= 0
	var age := day() - int(data.left_day) if stamped else ZONE_FRESH_DAYS
	if age >= ZONE_FRESH_DAYS:
		set_aside_zone_save(zone_id)
	elif age >= ZONE_LOOSE_DAYS:
		GameState.fade_loose = true
		SessionLog.note("zone %s remembered from %d days ago: its bodies and loose gear are gone" % [zone_id, age])


## Host (server_deploy): the campaign's save of zone `zone_id`, with its backup and any
## interrupted write, is set aside (GameState.set_aside, "<file>.earlier-deployment-<date>-<time>",
## kept beside it and never loaded again; never deleted, Captain 2026-10-14), so the deployment
## starting there finds the zone as generated. Captain,
## 2026-10-14: zones are fresh each contract: no bodies, vehicles, dropped gear, loot taken or
## voxel damage from earlier deployments. (The zone is still saved when a deployment ends, and
## by the host's quick save or quit; a campaign loaded with a deployment running ends that
## deployment at the base (load_or_new), so there is no mid-deployment save to resume into.)
## Never the FOB's save. Returns how many files were set aside.
func set_aside_zone_save(zone_id: String) -> int:
	var path := "%s/%s.json" % [GameState.SAVE_DIR, zone_save_id(zone_id)]
	if zone_save_id(zone_id) == base_zone_id():
		return 0
	var n := 0
	for p: String in GameState.save_candidates(path):
		if FileAccess.file_exists(p) and GameState.set_aside(p, "earlier-deployment") != "":
			n += 1
	if n > 0:
		SessionLog.note("zone %s starts fresh: its save from an earlier deployment is set aside" % zone_id)
	return n


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
		# The same stand-in as last time first (Captain, 2026-10-15: a new free hire every
		# deployment piled up "copies of us", in the players' kit, at the muster line).
		for mid in Roster.available_ids(roster()):
			if String(member(mid).get("stand_in_for", "")) == key and mid not in squad and mid not in out.values():
				pick = mid
				break
		for mid in Roster.available_ids(roster()):
			if pick != "" and String(member(pick).get("stand_in_for", "")) == key:
				break
			if mid in squad or mid in out.values():
				continue
			if pick == "" or StringName(member(mid).role) == role:
				pick = mid
				if StringName(member(mid).role) == role:
					break
		if pick == "":
			pick = Hiring.provide_free(roster(), role, day(), int(hiring().get("seed", 0)))
		if pick != "" and not member(pick).is_empty():
			member(pick)["stand_in_for"] = key
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
	var squad: Squad = lvl.squad_for(&"friendly")
	var anchor: Node3D = squad.leader if squad and is_instance_valid(squad.leader) else null
	var wedge: Array = Squad.FORMATIONS["wedge"]
	var pos: Vector3 = anchor.global_transform * (wedge[maxi(slot - 1, 0) % wedge.size()] as Vector3) if anchor \
		else lvl.next_spawn_point() + Vector3(0, 0, 3)
	var stats := Roster.ai_stats(m)
	var data := {"name": String(m.callsign), "faction": "friendly", "variant": Soldier.COMPANY_VARIANT, "pos": pos, "loadout": [],
		"role": "", "team": team, "slot": slot, "combat": stats.combat, "discipline": stats.discipline, "guard": false}
	data.merge(Roster.identity(m))  # the same person every deployment: name tape, nationality, hand, body
	var s: Soldier = lvl.spawn_soldier(data)
	s.role = role
	s.set_meta(&"roster_id", mid)
	s.dog_tags = Fallen.tags_of(m)  # his tags: taken off his body and carried out, he's killed in action, not missing
	s.inventory.net_state = GameState.from_json(m.get("gear", {}).duplicate(true))
	_apply_carry("m:" + mid, s)  # came on through a crossing: as they were (LZ-2)
	_apply_resume("m:" + mid, s)  # a saved deployment resumed: wounds as saved (LZ-4)
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
		var data := {"name": String(m.callsign), "faction": "friendly", "variant": Soldier.COMPANY_VARIANT, "pos": Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2])),
			"loadout": [], "role": "", "team": 0, "slot": -1, "combat": stats.combat, "discipline": stats.discipline, "guard": true}
		data.merge(Roster.identity(m))
		var s: Soldier = lvl.spawn_soldier(data)
		s.role = StringName(m.get("role", Roles.RIFLEMAN))
		s.set_meta(&"roster_id", mid)
		s.set_meta(&"recovery", true)
		s.dog_tags = Fallen.tags_of(m)
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
				if s.has_meta(&"away"):  # left at a crossing, back with the squad (LZ-2)
					RosterDeployment.active(roster()).get("away", {}).erase(String(s.get_meta(&"roster_id")))
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


## Host (HighCommand, the deployment's start): detachment `did`'s ready men spawn round `at` as
## a hero squad, each in their own identity, gear and skills, on the deployment's books
## (dep.spawned: resolve() settles them as it does the player squad's). Returns the Squad.
func server_spawn_detachment(lvl: Node, did: String, at: Vector3) -> Squad:
	var d := Heroes.get_detachment(roster(), did)
	var mids := Heroes.deploy_members(roster(), did)
	if d.is_empty() or mids.is_empty() or lvl == null:
		return null
	var members: Array = []
	for mid in mids:
		var m := member(mid)
		var stats := Roster.ai_stats(m)
		var data := {"name": String(m.callsign), "role": String(m.get("role", "rifleman")), "combat": stats.combat, "discipline": stats.discipline}
		data.merge(Roster.identity(m))
		members.append(data)
	var hc_id := "hc_" + did
	var sq := HighCommand.server_spawn_squad(lvl, {"id": hc_id, "callsign": String(d.callsign), "members": members, "size": members.size(), "did": did}, at)
	if sq == null:
		return null
	for s: Soldier in sq.members():
		var i := mids.find(_mid_by_callsign(String(s.name)))
		if i < 0:
			continue
		var mid := mids[i]
		var m := member(mid)
		s.role = StringName(m.get("role", "rifleman"))
		s.set_meta(&"roster_id", mid)
		s.dog_tags = Fallen.tags_of(m)
		s.inventory.net_state = GameState.from_json(m.get("gear", {}).duplicate(true))
		RosterDeployment.mark_spawned(roster(), mid)
	_changed(&"roster")
	SessionLog.note("[hc] %s deployed: %d men at (%.0f, %.0f)" % [d.callsign, sq.members().size(), at.x, at.z])
	return sq


func _mid_by_callsign(callsign: String) -> String:
	for mid: String in Roster.members(roster()):
		if String(Roster.members(roster())[mid].get("callsign", "")) == callsign:
			return mid
	return ""


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
	_tally_raid(lvl)  # (a raid's last zone; LZ-4)
	_settle_raid(RosterDeployment.active(roster()))
	var extracted: Array = []
	for record: Dictionary in (report.get("players", []) as Array) + (report.get("squad", []) as Array):
		var parent: Node = lvl.players if int(record.get("peer", 0)) != 0 else lvl.ai
		var s := parent.get_node_or_null(NodePath(String(record.get("node", "")))) as Soldier
		if s:
			extracted.append(s)
	# Dog tags first (Fallen): whose came out, and the death benefits they settle, before the
	# debrief counts the expenses (each benefit is a line of its own there) and the people's gear
	# goes home (the tags go to the company's records, not into anyone's kit or the stash).
	_collect_tags(lvl, extracted, report)
	_settle_tags(Contracts.is_deployed())
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
	# Intel still stowed on whoever got out is banked now, as at an extraction point: it goes to
	# the debrief (sold or turned in, once), not home in their packs to be carried out again
	# (economy overhaul 2026-10-20).
	if lvl.people and Contracts.is_deployed():
		for s: Soldier in extracted:
			lvl.people.server_bank_intel(s)
	# The people bring their own gear home; what else came out (bodies carried in, items set
	# down at the point, a helicopter's hold) goes to the stash, and so leaves the zone: it isn't
	# salvage too, and the zone save doesn't keep it to be banked again (the loop test caught
	# both). A raid has no contract but banks the same (audit A2-07); with a contract the
	# debrief banks it, once.
	var bank: Array = []
	var banked := {}
	for body: Dictionary in report.get("bodies", []):
		banked[String(body.get("uid", ""))] = true
		bank.append_array(Fallen.without_tags(body.get("items", [])))
	for entry: Dictionary in report.get("deposited", []):
		banked[String(entry.get("uid", ""))] = true
		bank.append_array(Fallen.without_tags([entry]))
	banked.erase("")
	var contract_ran := Contracts.is_deployed()
	if contract_ran:
		var debrief_report := Contracts.report_from_level(lvl, extracted, banked)  # (before the bodies go: its casualties)
		_mark_fallen(lvl, debrief_report)
		debrief_report["hvts"] = hvts
		debrief_report["bank"] = bank
		debrief_report["driven_out"] = report.get("driven_out", [])  # B-18: in a pool vehicle's hold going home (it stays there)
		_take_out_of_zone(banked)
		var debrief := Contracts.server_end_deployment(debrief_report, true)
		if Contracts.assault_pending() and String(debrief.get("key", "")) == String(Contracts.last_debrief().get("key", "")):
			_held_end = extracted  # the rest waits for the host's choice (server_assault_choice)
			return
	else:
		_take_out_of_zone(banked)
		Economy.bank_items(bank, "carried out")
	server_end_deployment(extracted, true, not contract_ran)


## Host (the debrief's warning; cghath's call on audit A2-04, "warn, then resolve"): a base assault
## falls due in the debrief's days, and the host chose how they pass. The debrief (pay, salvage,
## expenses, the days and the weekly bills in them) and the roster's settling are the same either
## way, in the same order; only the assault differs:
## - BaseAssault.HOME, head home first: the squad is counted home for the assault while the days
##   pass, so it stays booked (server_day_passed, at_base) and the deployment ends straight after:
##   back at the base zone, it comes in live against the squad (BaseAssault.server_check_due).
## - BaseAssault.CARRY_ON: as before the warning, the days pass with the squad out and it's
##   settled without them (held off-screen, or holding out when they're near).
## Then the deployment ends as any contract's does (server_end_deployment). Returns "" or why not.
func server_assault_choice(choice: String) -> String:
	if not multiplayer.is_server():
		return "Only the host can do that"
	if choice not in [BaseAssault.HOME, BaseAssault.CARRY_ON]:
		return "No such choice"
	if not Contracts.assault_pending() or not RosterDeployment.is_running(roster()):
		return "Nothing waiting on that"
	var extracted := _held_end.filter(func(n: Variant) -> bool: return is_instance_valid(n))
	_held_end = []
	SessionLog.note("base assault in the debrief's days: the host chose %s" % choice)
	_squad_home_for_assault = choice == BaseAssault.HOME
	if not Contracts.server_pass_held_days(choice):
		push_warning("BaseHub: the debrief's held days were gone; the deployment ends without them")
	_squad_home_for_assault = false
	server_end_deployment(extracted, true, false)
	return ""


## Host: items (WorldItem.uid) and bodies (Soldier.body_uid) in `uids` came out at extraction
## and were banked: they leave the zone (GameState.save_zone skips what's going).
func _take_out_of_zone(uids: Dictionary) -> void:
	if uids.is_empty():
		return
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := n as WorldItem
		if item and uids.has(item.uid) and not item.is_queued_for_deletion():
			GameState.item_taken(item.uid)
			item.queue_free()
	for n: Node in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var body := n as Soldier
		if body and uids.has(body.body_uid) and not body.is_queued_for_deletion():
			body.queue_free()


## Host (the map's extraction): the deployment ends. `extracted` are the soldiers who made it
## out (AI squadmates and players). A player not among them was left behind down or dead
## (Captain, 2026-10-14: Extraction leaves them at a second confirm): a stand-in they played goes
## MIA like a squadmate; their own main character makes it home (RosterDeployment.resolve). Every roster squadmate
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
	if not _tags_collected:  # (called straight, not through the map's extraction: debug, tests)
		_collect_tags(lvl, extracted, {})
		_settle_tags(false)
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
		var away: Dictionary = dep.get("away", {}).get(mid, {})
		if s == null and not away.is_empty() and not dep.get("fallen", {}).has(mid):
			# Left in another zone at a crossing and never fetched (LZ-2): missing there.
			outcomes.members[mid] = {"state": RosterDeployment.LEFT_BEHIND, "gear": away.gear, "pos": away.pos, "zone_id": away.zone_id}
			continue
		if dep.get("fallen", {}).has(mid) or s == null or s.vitals.is_dead():
			o["state"] = RosterDeployment.KILLED
			o["tags"] = _tags_out.has(mid)  # his tags or his body came out: killed in action; else missing (Fallen)
		else:
			o = _outcome_of(s)
			o["state"] = RosterDeployment.EXTRACTED if made_it.has(s.get_instance_id()) else RosterDeployment.LEFT_BEHIND
			o["pos"] = [s.global_position.x, s.global_position.y, s.global_position.z]
		outcomes.members[mid] = o
	for n: Node in lvl.players.get_children():
		var p := n as Soldier
		if p and not p.is_queued_for_deletion():
			var o := _outcome_of(p)
			if not made_it.has(p.get_instance_id()):
				o["state"] = RosterDeployment.LEFT_BEHIND
				o["pos"] = [p.global_position.x, p.global_position.y, p.global_position.z]
			outcomes.players[player_key(p.name.to_int())] = o
	var report := RosterDeployment.resolve(roster(), outcomes, rng, day())
	_prune_prep_squad()  # the killed and the missing leave the pick for the next one
	SessionLog.note("deployment ended: zone %s (%s); back %s; MIA %s; KIA %s; respawns %d used (%d bought)" % [report.zone_id,
		report.zone_kind, _callsigns(report.extracted), _callsigns(report.mia), _callsigns(report.dead), int(report.respawns_used),
		int(report.respawns_bought)])
	for mid: String in report.dead:
		server_pay_death_benefit(mid, "killed in action, tags recovered")  # (paid already when his tags came out: once)
	for mid: String in report.presumed:
		Contracts._notify_all("%s is missing: he fell, and neither his tags nor his body came out. Declared dead in %d days unless they come home."
			% [String(member(mid).callsign), Fallen.DECLARE_DAYS])
	for mid: String in report.mia:
		var m := member(mid)
		if Fallen.presumed(m):
			continue  # nobody to bring back: only his tags close it (Fallen)
		BaseEconomy.request_recovery_contract({"mid": mid, "name": m.name, "callsign": m.callsign, "role": m.role,
			"zone_id": String(m.get("mia_zone", report.zone_id)), "day": day(), "pos": m.get("mia_pos", [])})
	_tags_out = {}
	_tags_collected = false
	GameState.save_zone()  # the zone keeps its bodies, loot and damage
	if advance_days:
		server_advance_days(int(RosterDeployment.DAYS.get(report.zone_kind, 1)))
	_changed_all()
	if not Campaign.save_campaign():
		note.emit(save_note(false))  # the host's player hears it (audit A1-04)
	deployment_ended.emit(report)
	if return_to_base:
		server_switch_level(base_info(), base_zone_id())
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
	_held_end = []  # (a debrief waiting on the host's choice is undone with the rest)
	_tags_out = {}
	_tags_collected = false
	Contracts.objectives.server_clear()
	_changed_all()
	server_switch_level(base_info(), base_zone_id())
	return ""


## Host: everyone goes back to the hub (after server_end_deployment(..., false) and a debrief).
func server_return_to_base() -> void:
	SessionLog.note("Return to Base: everyone goes back to the hub")
	server_switch_level(base_info(), base_zone_id())


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
	if ok:
		server_pay_death_benefit(mid, "never recovered, written off")
	_changed(&"roster")
	return ok


# --- The fallen: dog tags, the memorial wall, death benefits (Fallen) -----------------------

## Host (the extraction, before anything else of it): the dog tags that came out are taken in.
## Tags in the gear of everyone who got out (taken out of it: they're the company's records),
## on bodies brought out (still worn, or in their gear), set down in the point or aboard the
## ride home, and in the holds driven home (`report`: the map's extraction report; {} when the
## deployment is ended straight). Their member ids go in _tags_out.
func _collect_tags(lvl: CompoundLevel, extracted: Array, report: Dictionary) -> void:
	_tags_collected = true
	var found: Array = []
	for n: Variant in extracted:
		if n is Soldier and is_instance_valid(n):
			found.append_array(Fallen.take_tags_from((n as Soldier).inventory))
	var uids := {}
	for body: Dictionary in report.get("bodies", []):
		uids[String(body.get("uid", ""))] = true
		found.append_array(Fallen.tags_in(body.get("items", [])))
	if lvl and not uids.is_empty():
		for n: Node in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
			var b := n as Soldier
			if b and uids.has(b.body_uid) and not b.dog_tags.is_empty():
				found.append(b.dog_tags.duplicate())
	found.append_array(Fallen.tags_in(report.get("deposited", [])))
	found.append_array(Fallen.tags_in(report.get("driven_out", [])))
	var names := PackedStringArray()
	for tags: Variant in found:
		var mid := Fallen.mid_of(tags)
		if mid != "" and not _tags_out.has(mid):
			_tags_out[mid] = true
			names.append(Fallen.tags_text(tags))
	if not names.is_empty():
		SessionLog.note("dog tags out: %s" % ", ".join(names))


## Host: the members killed in the running deployment (as server_end_deployment settles them:
## marked fallen, or their body is gone or dead), member id -> true.
func _killed_now(lvl: CompoundLevel) -> Dictionary:
	var dep := RosterDeployment.active(roster())
	var alive := {}
	if lvl:
		for n: Node in lvl.ai.get_children():
			var s := n as Soldier
			if s and s.has_meta(&"roster_id") and not s.is_queued_for_deletion() and not s.vitals.is_dead():
				alive[String(s.get_meta(&"roster_id"))] = true
	var out := {}
	for mid: String in dep.get("spawned", {}):
		var away: Dictionary = dep.get("away", {}).get(mid, {})
		if dep.get("fallen", {}).has(mid) or (not alive.has(mid) and away.is_empty()):
			out[mid] = true
	return out


## Host: the deaths the tags brought home are settled. A man killed this deployment whose tags
## (or body) came out has his death benefit paid now: in the debrief, as a line of its own, when
## a contract ran (`in_debrief`: Economy.charge_run), else straight from the cash. One who fell on
## an earlier deployment and was missing is killed in action now (Fallen.tags_home), paid the
## same; one already declared dead gets his tags on the wall.
func _settle_tags(in_debrief: bool) -> void:
	var killed := _killed_now(level())
	for mid: String in _tags_out:
		var m := member(mid)
		if m.is_empty():
			continue
		if killed.has(mid):
			server_pay_death_benefit(mid, "killed in action, tags recovered", in_debrief)
			continue
		match Fallen.tags_home(roster(), mid, day()):
			"confirmed":
				Contracts._notify_all("%s's tags came home: killed in action, on the memorial wall" % String(m.callsign))
				server_pay_death_benefit(mid, "killed in action, tags recovered", in_debrief)
			"recovered":
				Contracts._notify_all("%s's tags came home: on the memorial wall with them now" % String(m.callsign))
				_changed(&"roster")


## Host: the debrief's casualties say which of the fallen came home as tags (`report`:
## Contracts.report_from_level's): a roster member killed now is "kia" with his tags out, "mia"
## without them (Fallen), and the report says the benefits are paid per man ("benefits_paid":
## DebriefCalc.expenses lists the run's own lines, not a count of the dead).
func _mark_fallen(lvl: CompoundLevel, report: Dictionary) -> void:
	report["benefits_paid"] = true
	var killed := _killed_now(lvl)
	var by_name := {}
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and killed.has(String(s.get_meta(&"roster_id"))):
			by_name[s.display_name()] = String(s.get_meta(&"roster_id"))
	for c: Dictionary in report.get("casualties", []):
		var mid := String(by_name.get(String(c.get("name", "")), ""))
		if mid == "" or String(c.get("status", "")) != "kia":
			continue
		var out := _tags_out.has(mid)
		c["tags"] = Fallen.RECOVERED if out else Fallen.MISSING
		c["status"] = "kia" if out else "mia"
		c["injury"] = "killed, tags recovered" if out else "fell, tags not brought out"


## Host: the family of member `mid` is paid his death benefit (Prices.operations "kia_benefit"),
## once ("benefit_paid"), as "Death benefit: <callsign> (`why`)" in the books, with a notice for
## everyone. `in_debrief`: listed in the running deployment's debrief too (Economy.charge_run).
## Returns what was paid (0: nothing due, or paid before).
func server_pay_death_benefit(mid: String, why: String, in_debrief := false) -> int:
	var m := member(mid)
	if m.is_empty() or m.has("benefit_paid"):
		return 0
	var amount := Prices.operations("kia_benefit")
	m["benefit_paid"] = day()
	var what := "Death benefit: %s (%s)" % [String(m.get("callsign", mid)), why]
	if in_debrief:
		Economy.charge_run(amount, what)
	else:
		Economy.add_cash(-amount, what)
	Roster.add_history(m, day(), "Death benefit paid to the family ($%s)" % DebriefCalc.money(amount))
	SessionLog.note("%s: $%d" % [what, amount])
	Contracts._notify_all("Death benefit for %s paid to the family: $%s (%s)" % [Fallen.tags_text(Fallen.tags_of(m)), DebriefCalc.money(amount), why])
	_changed(&"roster")
	return amount


# --- Days, hiring, medbay, shop -----------------------------------------------------------

## Host: `days` campaign days pass at the base (resting), on the economy's clock: the weekly
## bill falls due on its day (the roster's wages in it), and the roster, the hiring board,
## assaults on the base and the locals' week follow (_on_day_advanced).
func server_advance_days(days: int, reason := "at the base") -> void:
	if days > 0:
		Economy.advance_days(days, reason)


## Host (Economy.day_advanced): `days` days passed, whatever moved the clock (resting, a
## deployment's debrief, the contract board's waits, travel): the wounded recover, the hiring
## board turns over every Hiring.REFRESH_DAYS, heat brings assaults on the base (LZ-5) and each
## week passed cools the locals on the company. These live here, not in server_advance_days,
## so every path that moves the clock has the same consequences (audit A2-04: a debrief and the
## board's waits went straight to Economy.advance_days, and never booked an assault).
func _on_day_advanced(today: int, days: int) -> void:
	if not started() or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()):
		return
	Roster.advance_days(roster(), days, today)
	for mid in Fallen.declare_due(roster(), today):  # missing since he fell: declared dead, his benefit paid now
		if Fallen.declare_dead(roster(), mid, today):
			server_pay_death_benefit(mid, "missing %d days, declared dead" % Fallen.DECLARE_DAYS)
	Hiring.refresh_if_due(hiring(), today)
	# (a debrief's days: the squad was out, unless the host headed home first: server_assault_choice)
	BaseAssault.server_day_passed(_squad_home_for_assault or not RosterDeployment.is_running(roster()))
	var week := today / maxi(MissionRegistry.setting_i("week_days", 7), 1)
	var last := int(base().get("rebel_week", week - 1))
	if week > last:
		base()["rebel_week"] = week
		for i in week - last:
			RebelSupport.on_week()  # heat cools the locals on the company (rebel support), once a week
	_changed_all()
	_refresh_muster()


## Host (Economy.wages_provider): the roster's wages for a week.
func _weekly_wages() -> int:
	return (Roster.daily_wages(roster()) + guards() * GUARD_DAILY_WAGE + company_squads() * COMPANY_SQUAD_DAILY_WAGE) \
		* maxi(MissionRegistry.setting_i("week_days", 7), 1)


## Hired company squads (docs/linked_zones.md 1b / LZ-6; call 20: "4-8 men each ... wages at the
## roster's rates, up to 1 per FOB tier to start"): how many the company keeps (BaseFob.TIERS
## "squads" caps it), each COMPANY_SQUAD_DAILY_WAGE a day. Called in from the support menu
## (AlliedTroops, company), under the host's high command. Proposed.
const COMPANY_SQUAD_DAILY_WAGE := 800


func company_squads() -> int:
	return clampi(int(base().get("company_squads", 0)), 0, int(BaseFob.TIERS[fob_tier()].squads))


## Host (the ops desk): the company keeps `n` squads of its own.
func server_set_company_squads(n: int) -> String:
	var cap := int(BaseFob.TIERS[fob_tier()].squads)
	if n > cap:
		return "The FOB keeps %d squad%s at tier %d: upgrade it for more" % [cap, "" if cap == 1 else "s", fob_tier()]
	base()["company_squads"] = clampi(n, 0, cap)
	_changed(&"base")
	return ""


## Hired guards (docs/linked_zones.md 1b / LZ-6: "hired guards who man the base while the squad is
## out (wages, part of the weekly bill)"): how many, up to MAX_GUARDS, each GUARD_DAILY_WAGE a day.
## They stand at the FOB's posts (BaseZoneLevel) and hold it off-screen (BaseAssault). Proposed.
const MAX_GUARDS := 8
const GUARD_DAILY_WAGE := 120


func guards() -> int:
	return clampi(int(base().get("guards", 0)), 0, max_guards())


## The FOB's tier (BaseFob.TIERS), 1 to start.
func fob_tier() -> int:
	return clampi(int(base().get("fob_tier", 1)), 1, BaseFob.TIERS.size())


## The most guards this tier keeps (MAX_GUARDS at the top).
func max_guards() -> int:
	return mini(int(BaseFob.TIERS[fob_tier()].guards), MAX_GUARDS)


## Host (the ops desk): the FOB goes up a tier. Returns "" or why not.
func server_upgrade_fob() -> String:
	var next := fob_tier() + 1
	if not BaseFob.TIERS.has(next):
		return "The FOB is as big as it gets"
	var price := int(BaseFob.TIERS[next].price)
	if not BaseEconomy.try_spend(price, "FOB upgrade to tier %d" % next):
		return "Can't afford the upgrade ($%d)" % price
	base()["fob_tier"] = next
	_changed(&"base")
	SessionLog.note("FOB upgraded to tier %d" % next)
	return ""


## Aboard the LHD (docs/lhd_home.md): the ship is never attacked; defences come with a FOB ashore.
const NO_DEFENCES_ABOARD := "The LHD needs no defences: they come with a FOB ashore (take a zone)"


## Host (the ops desk): buys defence `id` (BaseFob.DEFENCES) for the FOB. The engineers put it up
## at once: the base zone reloads with it. Returns "" or why not.
func server_buy_defence(id: String) -> String:
	if not BaseFob.DEFENCES.has(id):
		return "No such defence"
	if home_is_lhd():
		return NO_DEFENCES_ABOARD
	var owned: Array = base().get("defences", [])
	if id in owned:
		return "Already built"
	var clash := BaseFob.placement_problem(id, Vector2(float(BaseFob.DEFENCES[id].slot[0]), float(BaseFob.DEFENCES[id].slot[1])) if BaseFob.DEFENCES.has(id) else Vector2.ZERO,
		owned.filter(func(e: Variant) -> bool: return e is Dictionary))
	if BaseFob.DEFENCES.has(id) and clash == "another defence stands there":
		return "One you placed stands on its slot"
	var d: Dictionary = BaseFob.DEFENCES[id]
	if int(d.get("tier", 1)) > fob_tier():
		return "The %s needs the FOB at tier %d" % [String(d.name), int(d.tier)]
	if not BaseEconomy.try_spend(int(d.price), String(d.name)):
		return "Can't afford the %s ($%d)" % [String(d.name), int(d.price)]
	owned.append(id)
	base()["defences"] = owned
	_changed(&"base")
	if level() is BaseZoneLevel:
		server_switch_level(base_info(), base_zone_id())  # the engineers put it up
	return ""


## Host (the motor pool page, wave 6 call #1): the company buys a `model` from the allied
## quartermaster with the best deal (Quartermaster.vehicle_deals) into its motor pool. "" or why not.
func server_buy_vehicle(model: String) -> String:
	var deal := {}
	for d: Dictionary in Quartermaster.vehicle_deals():
		if String(d.model) == model:
			deal = d
	if deal.is_empty():
		return "Nobody sells the company that yet (an allied quartermaster, at Trusted or better)"
	if not BaseEconomy.try_spend(int(deal.price), "%s from %s" % [String(deal.name), String(MissionRegistry.faction(String(deal.faction)).get("name", deal.faction))]):
		return "Can't afford the %s ($%d)" % [String(deal.name), int(deal.price)]
	var id := MotorPool.add(model)
	SessionLog.note("vehicle bought: %s (%s) for $%d" % [model, id, int(deal.price)])
	_changed(&"base")
	return ""


## Host (DefencePlacer, LZ-6): defence `id` built where a player placed it, `at` (zone metres,
## snapped to the zones' grid), paid as at its slot; the base reloads with it. "" or why not.
func server_place_defence(id: String, at: Vector2) -> String:
	if not BaseFob.DEFENCES.has(id):
		return "No such defence"
	if home_is_lhd():
		return NO_DEFENCES_ABOARD
	var d: Dictionary = BaseFob.DEFENCES[id]
	if int(d.get("tier", 1)) > fob_tier():
		return "The %s needs the FOB at tier %d" % [String(d.name), int(d.tier)]
	at = Vector2(snappedf(at.x, ZoneDef.GRID_M), snappedf(at.y, ZoneDef.GRID_M))
	var owned: Array = base().get("defences", [])
	var why := BaseFob.placement_problem(id, at, owned)
	if why != "":
		return "Can't build it there: %s" % why
	if not BaseEconomy.try_spend(int(d.price), String(d.name)):
		return "Can't afford the %s ($%d)" % [String(d.name), int(d.price)]
	owned.append({"id": id, "pos": [at.x, at.y]})
	base()["defences"] = owned
	_changed(&"base")
	SessionLog.note("defence placed: %s at (%.0f, %.0f)" % [id, at.x, at.y])
	if level() is BaseZoneLevel:
		server_switch_level(base_info(), base_zone_id())  # the engineers put it up
	return ""


## Host (the ops desk, LZ-4: "pick 'Raid' at the ops desk for a heli insertion (paid)"): the squad
## flies out to raid zone `zone_id` (any zone: the helicopter is the shortcut over the region map),
## landing at its insertion point. The flight is the transport's price (Prices "transport"); the
## raid's rules (RosterDeployment.RAID) as when walking out. Everyone ready first. Returns "" or why not.
func server_raid_by_air(zone_id: String) -> String:
	var def := MissionRegistry.zone_def(zone_id)
	if def.is_empty() or zone_id == RegionMap.BASE:
		return "No such zone to raid"
	if not all_ready():
		return WAITING_FOR + ", ".join(PackedStringArray(not_ready_names()))
	var price := int(Prices.support_price("transport"))
	if not BaseEconomy.try_spend(price, "Helicopter out to raid %s" % RegionMap.zone_name(zone_id)):
		return "Can't afford the flight ($%d)" % price
	var why := server_deploy({"zone_id": zone_id, "no_contract": true, "zone_kind": RosterDeployment.RAID, "level": {"level": "zone", "def": def}})
	if why != "":
		BaseEconomy.credit(price, "Raid flight refunded")  # (charge_run ignores a negative amount: the refund never landed)
	return why


## Host (the ops desk): the company keeps `n` guards.
func server_set_guards(n: int) -> String:
	if n > max_guards():
		return "The FOB keeps %d guards at tier %d: upgrade it for more" % [max_guards(), fob_tier()]
	base()["guards"] = clampi(n, 0, max_guards())
	_changed(&"base")
	var lvl := level()
	if lvl is BaseZoneLevel:
		(lvl as BaseZoneLevel).server_post_guards()
	return ""


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


## Host: lets a member go (available ones only): they take the kit they were issued, the rest of
## their gear goes into the stash (Hiring.release_split).
func server_release(mid: String) -> String:
	var m := member(mid)
	if m.is_empty() or not Roster.is_available(m):
		return "Only someone fit and at the base can be let go"
	var lvl = base_level()
	var s: Soldier = lvl.muster_soldier(mid) if lvl else null
	var gear: Dictionary = s.inventory.net_state if s else m.get("gear", {})
	# They take the kit they were issued on joining (Hiring.release_split); the company keeps what
	# it added. Issued kit not on them comes out of the stash, or what the shop would pay for it is
	# charged (economy overhaul 2026-10-20: hire-and-release was free kit).
	var split := Hiring.release_split(m.get("issued", []), _gear_entries(GameState.from_json(gear.duplicate(true))))
	for entry: Dictionary in split.to_stash:
		server_add_to_stash(StringName(entry.id), int(entry.count), entry.get("state", {}))
	var owed_value := 0
	for id: String in split.owed:
		var left := int(split.owed[id]) - server_take_from_stash(StringName(id), int(split.owed[id]))
		if left > 0:
			owed_value += Prices.sell_price(StringName(id), left)
	if owed_value > 0:
		Economy.add_cash(-owed_value, "%s's issued kit not returned" % String(m.get("name", mid)))
	if s:
		s.inventory.strip()
	Roster.members(roster()).erase(mid)
	(_prep().squad as Array).erase(mid)
	_changed_all()
	_refresh_muster()
	return ""


## Everything in an Inventory.net_state, as entries ({"id", "count", "state"}).
func _gear_entries(gear: Dictionary) -> Array:
	var inv := Inventory.new()
	inv.net_state = gear
	var out: Array = inv.strip()
	inv.free()
	return out


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
	var lvl = base_level()
	if lvl and campaign_running:
		lvl.server_deliver(id, count, state)
	else:
		BaseArmory.add(stash(), id, count, state)
	_changed(&"base")


## Host: sells `count` of `id` out of the stash to the shop (Captain, 2026-10-16: "sell loot";
## Economy.server_sell prices it, a damaged piece for less). At the hub the armory's items go
## (_apply_stash); elsewhere the stash list. Returns what it fetched, 0 if none was there.
func server_sell_from_stash(id: StringName, count := 1) -> int:
	var took := server_take_from_stash(id, count)
	if took <= 0:
		return 0
	var got := Economy.server_sell(id, took)
	Fixers.server_sold_at_base(id)  # contraband sold openly: lawful employers notice (wave 6)
	return got


## Host: takes up to `count` of `id` out of the company stash (the armory's at the hub, else the
## stash list). Returns how many it took.
func server_take_from_stash(id: StringName, count := 1) -> int:
	var lvl = base_level()
	var took := 0
	if lvl and campaign_running:
		var before: Array = lvl.server_collect_stash()
		var pool: Array = before.duplicate(true)
		took = BaseArmory.remove(pool, id, count)
		if took > 0:
			_apply_stash(lvl, before, pool)
	else:
		took = BaseArmory.remove(stash(), id, count)
	if took > 0:
		_changed(&"base")
	return took


## Host: puts a member in or out of the squad picked for the next deployment.
func server_pick(mid: String, in_squad: bool) -> String:
	_prune_prep_squad()  # the dead and missing don't hold a slot ("The squad is full" over three names)
	var squad: Array = _prep().squad
	if not in_squad:
		squad.erase(mid)
	elif mid not in squad:
		if not Roster.is_available(member(mid)):
			return "They can't deploy now"
		if Heroes.in_detachment(roster(), mid):
			return "They deploy with their high command squad"
		if squad.size() >= SQUAD_SIZE - 1:
			return "The squad is full"
		squad.append(mid)
	_changed(&"base")
	return ""


## Host: the squad picked for the next deployment keeps only members who can deploy now. The
## pick outlives a deployment, so without this the killed, the MIA and the recovering stayed in
## it: the Ops desk counted them ("6 of 7 AI" over three names) and they held squad slots.
## Returns whether anyone was taken out.
func _prune_prep_squad() -> bool:
	var squad: Array = _prep().squad
	var gone := squad.filter(func(mid: Variant) -> bool: return not Roster.is_available(member(String(mid))) or Heroes.in_detachment(roster(), String(mid)))
	for mid: Variant in gone:
		squad.erase(mid)
	return not gone.is_empty()


## Host: a member's role in the squad from now on.
func server_set_role(mid: String, role: StringName) -> String:
	var m := member(mid)
	if m.is_empty() or not Roles.has(role):
		return "No such role"
	m["role"] = String(role)
	Roster.add_history(m, day(), "Now a %s" % Roles.display_name(role))
	var lvl = base_level()
	var s: Soldier = lvl.muster_soldier(mid) if lvl else null
	if s:
		s.role = role
	_changed(&"roster")
	return ""


## Host: certifies roster member `mid` to pilot the HX-1 Assault Frame (Captain, 2026-10-17:
## pilot training/certification, docs/near_future_hardware.md 2.3a) — a one-time cash cost,
## gated on being a veteran (Roster.hx1_eligible: missions survived), not a new timed state.
func server_certify_hx1(mid: String) -> String:
	var m := member(mid)
	if m.is_empty():
		return "No such member"
	if Roster.hx1_certified(m):
		return "Already certified"
	if not Roster.hx1_eligible(m):
		return "Not experienced enough yet (%d missions)" % Roster.HX1_CERT_MISSIONS
	if not Economy.spend(Roster.HX1_CERT_COST, "HX-1 certification: %s" % m.name):
		return "Can't afford it"
	Roster.certify_hx1(m, day())
	_changed(&"roster")
	return ""


func _refresh_muster() -> void:
	var lvl = base_level()
	if lvl and campaign_running and lvl.fob_ready():
		lvl.server_show_roster()


# --- Restocking the last loadout (playtest S2) -----------------------------------------------
# Kitting up at the base took 5-12 minutes a player (P0339, P0164, P0331, P0362). At deploy each
# player's main character and each squadmate gets their kit written down ("loadout" on their
# roster entry, Roster.record_loadout); back at the base one button rebuilds it from the stash
# (Restock.build): what they wear now goes into the pool first, the loadout is drawn from it,
# and what's left over lies in the armory as stash. What the stash is short of is listed.

## Host (server_deploy): writes down what everyone deploys in: the squad's members and each
## player's main character (not one sitting this one out: they play a stand-in). What a short
## restock couldn't give them stays in it (Roster.record_loadout).
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
## did (Restock.report_text), or why not; the player sees it too. What it couldn't give them
## stays on their roster entry for the squad page, and the host hears of it (S0743: a client
## medic came back short and only he was told). What the stash is short of is shared with the
## medics who aren't restocking now (_medic_needs): a medic draws first, anyone else leaves
## them their share.
func server_restock_player(peer: int) -> String:
	var lvl = base_level()
	if lvl == null or not campaign_running or RosterDeployment.is_running(roster()):
		return "Only at the base"
	var s: Soldier = lvl.players.get_node_or_null(NodePath(str(peer))) as Soldier
	if s == null or not s.vitals.is_up():
		return "You can't kit up now"
	var main := Roster.main_character(roster(), player_key(peer))
	var loadout := Roster.loadout_of(main)
	if Restock.is_blank(loadout):
		return "No loadout yet: the kit you deploy in is written down for next time"
	var medic := StringName(main.get("role", "")) == Roles.MEDIC
	var res: Dictionary = _restock_bodies(lvl, [{"soldier": s, "loadout": loadout, "who": "your loadout", "medic": medic}],
		_medic_needs(lvl, [], player_key(peer)))[0]
	main["gear"] = Roster.json_safe(s.inventory.net_state.duplicate(true))
	var short := Restock.short_of(res)
	Roster.record_restock_short(main, short)
	_changed(&"roster")
	s._client_message.rpc_id(peer, String(res.text))
	if peer != 1 and not short.is_empty():
		note.emit("Restock: %s is short of %s" % [player_key(peer), Restock.list_text(short)])  # the host's status line
	return String(res.text)


## Host: rebuilds member `mid`'s last loadout on them at the muster line. "" if they have none
## or aren't standing there; else what it did.
func server_restock_member(mid: String) -> String:
	var lines := _restock_members([mid])
	return lines[0] if not lines.is_empty() else ""


## Host (the squad leader's "Restock squad"): every AI squadmate picked for the next deployment
## (everyone at the muster line when nobody is picked yet), together from one pool: everyone's
## kit goes in first, and what the stash is short of is shared out fairly, medics first
## (Restock.fair_caps; S0743: restocked one after the other, the medic came out short). Returns
## one line each.
func server_restock_squad() -> String:
	if not in_base() or RosterDeployment.is_running(roster()):
		return "Only at the base"
	var mids := _restock_squad_ids()
	var none := PackedStringArray()
	var here: Array[String] = []
	var lvl = base_level()
	for mid: Variant in mids:
		if lvl.muster_soldier(String(mid)) == null:
			continue  # not here: missing, dead, recovering
		if Restock.is_blank(Roster.loadout_of(member(String(mid)))):
			none.append(String(member(String(mid)).callsign))
		else:
			here.append(String(mid))
	var lines := _restock_members(here)
	if not none.is_empty():
		lines.append("No loadout yet for %s (written down when they deploy)" % ", ".join(none))
	return "\n".join(lines) if not lines.is_empty() else "Nobody to restock"


## The squadmates Restock squad kits up: those picked for the next deployment, everyone at the
## muster line when nobody is picked yet.
func _restock_squad_ids() -> Array:
	var picked: Array = _prep().get("squad", [])
	return picked if not picked.is_empty() else Array(muster_ids())


## Host: what each medic who isn't restocking now still needs of their loadout (Restock.needs:
## the loadout less what they carry): the players' medics here (not `skip_key`'s) and the
## squad's medics at the muster line (not `skip_mids`). Restock deals what the stash is short
## of round them too (Restock.fair_shares), so whoever restocks first doesn't take a medic's
## share (review of S0736: a rifleman player restocked just before the medic player and took
## the last knife; Restock squad before a client medic took his tourniquets).
func _medic_needs(lvl, skip_mids: Array, skip_key := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Node in lvl.players.get_children():
		var peer := p.name.to_int()
		var key := player_key(peer)
		if not p is Soldier or p.is_queued_for_deletion() or not _gear_applied.has(peer) or key == skip_key \
				or not Roster.players(roster()).has(key) or Roster.main_recovering(roster(), key):
			continue
		var main := Roster.main_character(roster(), key)
		if StringName(main.get("role", "")) == Roles.MEDIC:
			var need := Restock.needs(Roster.loadout_of(main), Roster.json_safe((p as Soldier).inventory.net_state))
			if not need.is_empty():
				out.append(need)
	for mid: Variant in _restock_squad_ids():
		var m := member(String(mid))
		var s: Soldier = lvl.muster_soldier(String(mid))
		if s == null or String(mid) in skip_mids or StringName(m.get("role", "")) != Roles.MEDIC:
			continue
		var need := Restock.needs(Roster.loadout_of(m), Roster.json_safe(s.inventory.net_state))
		if not need.is_empty():
			out.append(need)
	return out


## Host: restocks members `mids` (at the muster line, with a loadout; others are skipped) from
## one pool, medics first; each one's gear and what they're short of go on the roster. Returns
## one line each (Restock.report_text).
func _restock_members(mids: Array[String]) -> PackedStringArray:
	var lines := PackedStringArray()
	var lvl = base_level()
	if lvl == null or not campaign_running or RosterDeployment.is_running(roster()):
		return lines
	var people: Array = []
	for mid in mids:
		var m := member(mid)
		var s: Soldier = lvl.muster_soldier(mid)
		if s != null and not m.is_empty() and not Restock.is_blank(Roster.loadout_of(m)):
			people.append({"mid": mid, "soldier": s, "loadout": Roster.loadout_of(m), "who": String(m.callsign),
				"medic": StringName(m.get("role", "")) == Roles.MEDIC})
	if people.is_empty():
		return lines
	# Medics first, the rest in the order asked (fair_shares deals each round starting with them).
	people = people.filter(func(p: Dictionary) -> bool: return p.medic) + people.filter(func(p: Dictionary) -> bool: return not p.medic)
	var results := _restock_bodies(lvl, people, _medic_needs(lvl, mids))
	for i in people.size():
		var mid := String(people[i].mid)
		server_store_member_gear(mid, (people[i].soldier as Soldier).inventory.net_state)
		Roster.record_restock_short(member(mid), Restock.short_of(results[i]))
		lines.append(String(results[i].text))
	_changed(&"roster")
	return lines


## Host: each of `people` ({"soldier", "loadout", "who", "medic"}) gets their kit rebuilt from
## the hub's stash: what they all wear now goes into one pool first, what the pool can't fill
## for all of them and the medics not restocking (`medic_needs`, _medic_needs) is shared
## (Restock.fair_shares: the medics restocking, then those needs, then the rest), and the
## armory's world items follow. Returns each one's Restock.build result with its report ("text").
func _restock_bodies(lvl, people: Array, medic_needs: Array[Dictionary] = []) -> Array:
	var before: Array = lvl.server_collect_stash()
	var pool: Array = before.duplicate(true)
	for p: Dictionary in people:
		var own := Inventory.new()
		own.net_state = (p.soldier as Soldier).inventory.net_state
		for e: Dictionary in own.strip():
			BaseArmory.add(pool, StringName(e.id), int(e.count), e.get("state", {}))
		own.free()
	var wants: Array[Dictionary] = []
	var at := {}  # people index -> its place in wants
	for medics: bool in [true, false]:
		for i in people.size():
			if bool(people[i].get("medic", false)) == medics:
				at[i] = wants.size()
				wants.append(Restock.counts(people[i].loadout))
		if medics:
			wants.append_array(medic_needs)
	var caps: Array[Dictionary] = Restock.fair_shares(wants, pool)
	var results: Array = []
	for i in people.size():
		results.append(Restock.build(people[i].loadout, pool, caps[int(at[i])]))
	# Review of c33712a: a share someone couldn't use (drawn with no room on him) is back in the
	# pool; it goes round to those it was kept from (Restock.top_up), less what's kept for the
	# medics not restocking, and they're built again with it.
	var reserved := {}
	for j in wants.size():
		if not j in at.values():
			for id: String in caps[j]:
				reserved[id] = int(reserved.get(id, 0)) + int(caps[j][id])
	var order: Array = range(people.size())
	order.sort_custom(func(x: int, y: int) -> bool: return int(at[x]) < int(at[y]))
	var extra := Restock.top_up(order.map(func(i: int) -> Dictionary: return results[i].held_back), pool, reserved)
	for k in order.size():
		var i: int = order[k]
		if extra[k].is_empty():
			continue
		var own := Inventory.new()
		own.net_state = GameState.from_json(results[i].gear)
		for e: Dictionary in own.strip():
			BaseArmory.add(pool, StringName(e.id), int(e.count), e.get("state", {}))
		own.free()
		var more: Dictionary = caps[int(at[i])].duplicate()
		for id: String in extra[k]:
			more[id] = int(more.get(id, 0)) + int(extra[k][id])
		results[i] = Restock.build(people[i].loadout, pool, more)
	for i in people.size():
		var s: Soldier = people[i].soldier
		var res: Dictionary = results[i]
		s.inventory.net_state = GameState.from_json(res.gear)
		res["text"] = Restock.report_text(String(people[i].who), res)
		SessionLog.note("restock: %s: %s" % [SessionLog.who(s), res.text])
	_apply_stash(lvl, before, pool)
	return results


## Host: makes the hub's world items `after` where they were `before` (both stash entries):
## what went is taken off the armory's items, what came back (old kit, pouches or an optic
## swapped off) is put down at the armory counter.
func _apply_stash(lvl, before: Array, after: Array) -> void:
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
	for entry: Dictionary in after:
		var key := Restock.stash_key(StringName(String(entry.id)), entry.get("state", {}))
		var n := mini(int(come.get(key, 0)), int(entry.count))
		if n <= 0:
			continue
		come[key] = int(come[key]) - n
		lvl.server_deliver(StringName(String(entry.id)), n, GameState.from_json(entry.get("state", {})))
	base()["stash"] = Roster.json_safe(after)
	_changed(&"base")


# --- The loadout menu (Captain, 2026-10-14; docs/loadout_menu.md) ----------------------------
# "We need a menu for equipping yourself better and your squadmates how you want to as well."
# Every change is a template edit rebuilt from the stash (Loadouts.rebuild: the kits go into one
# pool with the stash, Restock.build draws the edited ones from it), applied to the bodies and to
# the armory's world items (_apply_stash), so nothing is made or lost and a short stash is named
# in Restock's words.

## Ops that change only the standing loadout (what Restock refills to), not the kit worn now.
const STANDING_OPS: Array[String] = ["save", "standing_role", "copy_standing", "restock"]
## Saved kits (KitLibrary; claude/loadout-3d): "kit_save" [name, template?], "kit_delete" [name],
## "kit_apply" [name, to: KitLibrary targets, buy: bool].
const KIT_OPS: Array[String] = ["kit_save", "kit_delete", "kit_apply"]


## Host: `who` at the hub (a member id at the muster line, or "player:<key>" for a player here):
## {"who", "name", "role", "person" (roster entry), "soldier", "peer" (players; 0 for a member)},
## or {} if they aren't standing here.
func loadout_person(who: String) -> Dictionary:
	var lvl = base_level()
	if lvl == null:
		return {}
	if who.begins_with("player:"):
		var key := who.trim_prefix("player:")
		for p: Node in lvl.players.get_children():
			var peer := p.name.to_int()
			if p is Soldier and not p.is_queued_for_deletion() and player_key(peer) == key:
				var main := Roster.main_character(roster(), key)
				return {"who": who, "name": key, "role": StringName(main.get("role", Roles.RIFLEMAN)), "person": main, "soldier": p, "peer": peer}
		return {}
	var m := member(who)
	var s: Soldier = lvl.muster_soldier(who)
	if m.is_empty() or s == null:
		return {}
	return {"who": who, "name": String(m.callsign), "role": StringName(m.get("role", Roles.RIFLEMAN)), "person": m, "soldier": s, "peer": 0}


## Whether player `sender` may change `a`'s kit or standing loadout: their own and any AI
## squadmate's, never another player's.
static func may_change_loadout(sender: int, a: Dictionary) -> bool:
	return int(a.get("peer", 0)) == 0 or int(a.peer) == sender


## Host: the loadout menu's request `op` on `who` from player `sender` (docs/loadout_menu.md,
## Network). Returns what happened, or why not.
func server_loadout(sender: int, who: String, op: String, p: Dictionary) -> String:
	var lvl = base_level()
	if lvl == null or not campaign_running or RosterDeployment.is_running(roster()):
		return "Only at the base"
	if op == "sync":
		var gear: Dictionary = lvl.server_read_muster_gear()
		for mid: String in gear:
			server_store_member_gear(mid, gear[mid])
		_changed(&"roster")
		return ""
	var a := loadout_person(who)
	if a.is_empty():
		return "They aren't at the base"
	if not may_change_loadout(sender, a):
		return "%s sets their own kit" % a.name
	var s: Soldier = a.soldier
	if not s.vitals.is_up():
		return "%s can't kit up now" % a.name
	if op == "buy_missing":
		return _server_buy_missing(lvl, sender, a, String(p.get("id", "")))
	if op in STANDING_OPS:
		return _server_standing(sender, a, op, p)
	if op in KIT_OPS:
		return _server_kit(lvl, sender, a, op, p)
	var t := Loadouts.template_of(Roster.json_safe(s.inventory.net_state))
	var people: Array = [a]
	var what := ""
	match op:
		"slot":
			var slot := StringName(String(p.get("slot", "")))
			var id := String(p.get("id", ""))
			if not slot in Loadouts.DOLL_SLOTS or (id != "" and not Loadouts.fits_slot(ItemDB.get_item(StringName(id)), slot)):
				return "That doesn't go there"
			t = Loadouts.set_slot(t, slot, id)
			what = "%s: %s" % [Loadouts.SLOT_NAMES[slot], ItemDB.get_item(StringName(id)).name if id != "" else "back to the stash"]
		"optic":
			var slot := StringName(String(p.get("slot", "")))
			var id := String(p.get("id", ""))
			if not slot in Inventory.WEAPON_SLOTS or (id != "" and not Optics.is_optic(ItemDB.get_item(StringName(id)))):
				return "That isn't an optic"
			t = Loadouts.set_optic(t, slot, id)
			what = "%s on the %s" % [ItemDB.get_item(StringName(id)).name if id != "" else "Irons", String(Loadouts.SLOT_NAMES[slot]).to_lower()]
		"mount":
			var slot := StringName(String(p.get("slot", "")))
			var mount := String(p.get("mount", ""))
			var id := String(p.get("id", ""))
			var holder := ItemDB.get_item(StringName(String(t.slots.get(String(slot), ""))))
			if holder == null or (id != "" and not GearMounts.fits(holder, mount, ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null)):
				return "That doesn't go there"
			t = Loadouts.set_mount(t, slot, mount, id)
			what = "%s: %s" % [GearMounts.NAMES.get(mount, mount), ItemDB.get_item(StringName(id)).name if id != "" else "off"]
		"template":
			# The 3D editor's whole draft at once (LoadoutEditor), buying what the stash lacks first when asked.
			t = KitLibrary.clean_template(p.get("template", {}))
			if bool(p.get("buy", false)):
				var bought := _server_buy_shortfall(lvl, sender, [{"gear": _person_gear(a), "template": t}])
				if bought.begins_with("!"):
					return bought.substr(1)
				what = bought
			what = "kit fitted" if what == "" else what + ", kit fitted"
		"add", "remove", "give":
			var id := String(p.get("id", ""))
			var n := clampi(int(p.get("count", 1)), 1, 50)
			if not ItemDB.has_item(StringName(id)):
				return "No such item"
			var item_name := ItemDB.get_item(StringName(id)).name
			if op == "add":
				t = Loadouts.add_units(t, id, n)
				what = "+%d %s" % [n, item_name]
			else:
				var took := Loadouts.remove_units(t, id, n)
				if int(took.removed) <= 0:
					return "%s has no %s" % [a.name, item_name]
				t = took.template
				what = "%d %s back to the stash" % [int(took.removed), item_name]
				if op == "give":
					var b := loadout_person(String(p.get("to", "")))
					if b.is_empty() or b.who == a.who:
						return "Nobody to give it to"
					b["template"] = Loadouts.add_units(Loadouts.template_of(Roster.json_safe((b.soldier as Soldier).inventory.net_state)), id, int(took.removed))
					people.append(b)
					what = "gave %d %s to %s" % [int(took.removed), item_name, b.name]
		"fill_ammo":
			t = Loadouts.fill_ammo(t, a.role)
			what = "ammo filled"
		"medic_kit":
			t = Loadouts.medic_kit(t)
			what = "medic kit"
		"role_kit":
			var role := StringName(String(p.get("role", a.role)))
			if not Roles.has(role):
				return "No such role"
			t = Loadouts.role_template(role)
			what = "%s kit" % Roles.display_name(role)
		"copy_kit":
			var c := loadout_person(String(p.get("from", "")))
			if c.is_empty():
				return "Nobody to copy"
			t = Loadouts.template_of(Roster.json_safe((c.soldier as Soldier).inventory.net_state))
			what = "kit copied from %s" % c.name
		_:
			return "Unknown request"
	a["template"] = t
	var lines := _loadout_apply(lvl, people)
	var text := "%s: %s%s" % [a.name, what, (". " + lines[0]) if lines[0] != "" else ""]
	if people.size() > 1 and lines[1] != "":
		text += "\n%s: %s" % [people[1].name, lines[1]]
	return text


## Host: `people` (loadout_person entries with their edited "template") rebuilt from the hub's
## stash together; their bodies, roster gear and the armory follow. One short_text each.
func _loadout_apply(lvl, people: Array) -> PackedStringArray:
	var before: Array = lvl.server_collect_stash()
	var pool: Array = before.duplicate(true)
	var jobs: Array = people.map(func(a: Dictionary) -> Dictionary:
		return {"gear": _person_gear(a), "template": a.template})
	var results := Loadouts.rebuild(jobs, pool)
	var lines := PackedStringArray()
	for i in people.size():
		var a: Dictionary = people[i]
		var s: Soldier = a.get("soldier")
		if s:
			s.inventory.net_state = GameState.from_json(results[i].gear)
		if int(a.peer) == 0:
			server_store_member_gear(String(a.who), GameState.from_json(results[i].gear))
		else:
			a.person["gear"] = Roster.json_safe(results[i].gear.duplicate(true))
		lines.append(Loadouts.short_text(results[i]))
		_note_edit_missing(a, results[i])
		SessionLog.note("loadout: %s: %s" % [SessionLog.who(s) if s else String(a.name), lines[i] if lines[i] != "" else "changed"])
	_apply_stash(lvl, before, pool)
	_changed(&"roster")
	return lines


## What `a` (a loadout_person entry) wears now, JSON-safe: the body's, or the roster's for a
## squadmate not standing at the muster line (a high command squad's man).
static func _person_gear(a: Dictionary) -> Dictionary:
	var s: Soldier = a.get("soldier")
	return Roster.json_safe(s.inventory.net_state if s else a.person.get("gear", {}))


## Host: buys what the stash lacks to put `jobs` ([{"gear", "template"}]) on everyone at once
## (KitLibrary.shortfall). "" when nothing was missing, "bought N items for $X", or "!" + why
## not (not enough cash: nothing is bought then).
func _server_buy_shortfall(lvl, sender: int, jobs: Array) -> String:
	var short := KitLibrary.shortfall(jobs, lvl.server_collect_stash())
	if int(short.units) <= 0:
		return ""
	if BaseEconomy.funds() < int(short.cost):
		return "!Not enough cash: $%d needed, $%d in the account" % [int(short.cost), BaseEconomy.funds()]
	for id: String in short.missing:
		if not id in short.unbuyable:
			Economy.server_buy(StringName(id), int(short.missing[id]), sender)
	return "bought %d items for $%d" % [int(short.units), int(short.cost)]


## Host: the saved-kit ops (KitLibrary, KIT_OPS). `a` is the one asking's own person here.
func _server_kit(lvl, sender: int, a: Dictionary, op: String, p: Dictionary) -> String:
	var data := roster()
	var kit_name := KitLibrary.clean_name(String(p.get("name", "")))
	match op:
		"kit_save":
			var t: Variant = p.get("template", null)
			if not t is Dictionary:
				t = Loadouts.template_of(_person_gear(a))
			var why := KitLibrary.save(data, kit_name, t, String(a.name), String(a.role))
			if why != "":
				return why
			_changed(&"roster")
			return "Saved kit \"%s\"" % kit_name
		"kit_delete":
			if not KitLibrary.delete(data, kit_name):
				return "No kit called \"%s\"" % kit_name
			_changed(&"roster")
			return "Deleted kit \"%s\"" % kit_name
		"kit_apply":
			var t := KitLibrary.template_of_kit(data, kit_name)
			if Restock.is_blank(t):
				return "No kit called \"%s\"" % kit_name
			var people: Array = []
			var skipped := PackedStringArray()
			for who: String in KitLibrary.resolve(data, _prep().get("squad", []), p.get("to", [])):
				var b := loadout_person(who)
				if b.is_empty() and not who.begins_with("player:") and not member(who).is_empty():
					var m := member(who)  # away from the muster line (a high command squad): their roster kit
					b = {"who": who, "name": String(m.callsign), "role": StringName(m.get("role", Roles.RIFLEMAN)), "person": m, "soldier": null, "peer": 0}
				if b.is_empty() or not may_change_loadout(sender, b) or (b.soldier != null and not (b.soldier as Soldier).vitals.is_up()):
					if not b.is_empty():
						skipped.append(String(b.name))
					continue
				b["template"] = t.duplicate(true)
				people.append(b)
			if people.is_empty():
				return "Nobody to put \"%s\" on" % kit_name
			var bought := ""
			if bool(p.get("buy", false)):
				bought = _server_buy_shortfall(lvl, sender, people.map(func(b: Dictionary) -> Dictionary: return {"gear": _person_gear(b), "template": b.template}))
				if bought.begins_with("!"):
					return bought.substr(1)
			var lines := _loadout_apply(lvl, people)
			var short := PackedStringArray()
			for i in people.size():
				people[i].person["loadout"] = t.duplicate(true)  # their standing loadout too: Restock refills to it
				Roster.record_restock_short(people[i].person, {})
				if lines[i] != "":
					short.append("%s: %s" % [people[i].name, lines[i]])
			_changed(&"roster")
			var text := "Kit \"%s\" on %s%s" % [kit_name, ", ".join(people.map(func(b: Dictionary) -> String: return String(b.name))), (" (" + bought + ")") if bought != "" else ""]
			if not skipped.is_empty():
				text += ". Not changed: " + ", ".join(skipped)
			if not short.is_empty():
				text += "\n" + "\n".join(short)
			return text
	return "Unknown request"


## Host: the standing-loadout ops (what Restock refills to): "save" (the kit worn now),
## "standing_role" [role] (a role's kit, whatever the stash has), "copy_standing" [to: whos]
## (this one's standing loadout for them too), "restock" (rebuild the kit to it).
func _server_standing(sender: int, a: Dictionary, op: String, p: Dictionary) -> String:
	var person: Dictionary = a.person
	match op:
		"save":
			var t := Loadouts.template_of(Roster.json_safe((a.soldier as Soldier).inventory.net_state))
			if Restock.is_blank(t):
				return "%s carries nothing to save" % a.name
			person["loadout"] = t
			Roster.record_restock_short(person, {})
			_changed(&"roster")
			return "Saved %s's standing loadout: Restock refills to this (%d items)" % [a.name, _units_in(t)]
		"standing_role":
			var role := StringName(String(p.get("role", a.role)))
			if not Roles.has(role):
				return "No such role"
			person["loadout"] = Loadouts.role_template(role)
			Roster.record_restock_short(person, {})
			_changed(&"roster")
			return "%s's standing loadout is the %s kit: Restock draws it from the stash" % [a.name, Roles.display_name(role)]
		"copy_standing":
			var from := Roster.loadout_of(person)
			if Restock.is_blank(from):
				return "%s has no standing loadout to copy" % a.name
			var done := PackedStringArray()
			for to: Variant in p.get("to", []):
				var b := loadout_person(String(to))
				if b.is_empty() or b.who == a.who or not may_change_loadout(sender, b):
					continue
				b.person["loadout"] = from.duplicate(true)
				Roster.record_restock_short(b.person, {})
				done.append(String(b.name))
			_changed(&"roster")
			return "%s's standing loadout copied to %s" % [a.name, ", ".join(done)] if not done.is_empty() else "Nobody to copy it to"
		"restock":
			if Restock.is_blank(Roster.loadout_of(person)):
				return "%s has no standing loadout yet: Save one first" % a.name
			if int(a.peer) != 0:
				return server_restock_player(int(a.peer))
			return server_restock_member(String(a.who))
	return "Unknown request"


static func _units_in(t: Dictionary) -> int:
	var n := 0
	for c: Variant in Restock.counts(t).values():
		n += int(c)
	return n


# --- Requests from the base screen ---------------------------------------------------------

## Any peer: asks the host to do something at the base. `action`: "hire" [cid], "release"
## [mid], "medbay" [mid or "player:<key>"], "pick" [mid, bool], "role" [mid, role], "buy"
## [item id, count], "rest" [days], "prep" [held contract id], "deploy" [], "save" [], "restock"
## [] (the sender's last loadout), "restock_squad" [], "ready" [bool] (the sender, FOB ready-up), "loadout" [who, op,
## params] (the loadout menu: server_loadout); "deploy", "rest", "release", "prep",
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
	var needs: int = {"hire": 1, "release": 1, "medbay": 1, "pick": 2, "role": 2, "buy": 1, "prep": 1, "ready": 1, "loadout": 3, "certify_hx1": 1}.get(action, 0)
	if args.size() < needs:
		why = "Bad request"
	elif action in ["deploy", "rest", "release", "save", "prep", "restock_squad"] and sender != 1:
		why = "Only the host can do that"  # the company's big decisions are the host's
	elif action == "income":
		why = Income.server_request(String(args[0]) if not args.is_empty() else "", args.slice(1), sender if sender != 0 else 1)  # side work: from anywhere (Income checks)
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
			"certify_hx1":
				why = server_certify_hx1(String(args[0]))
			"buy":
				why = server_buy(StringName(args[0]), int(args[1]) if args.size() > 1 else 1, sender)
			"rest":
				server_advance_days(clampi(int(args[0]) if not args.is_empty() else 1, 1, 30))
			"defence":
				why = server_buy_defence(String(args[0])) if sender == 1 and not args.is_empty() else "Only the host can do that"
			"rebel_upgrade":
				why = RebelSupport.server_upgrade(String(args[0])) if sender == 1 and not args.is_empty() else "Only the host can do that"
			"buy_vehicle":
				why = server_buy_vehicle(String(args[0])) if sender == 1 and not args.is_empty() else "Only the host can do that"
			"place_defence":
				why = server_place_defence(String(args[0]), Vector2(float(args[1]), float(args[2]))) if sender == 1 and args.size() >= 3 else "Only the host can do that"
			"raid_air":
				why = server_raid_by_air(String(args[0])) if sender == 1 and not args.is_empty() else "Only the host can do that"
			"squads":
				why = server_set_company_squads(int(args[0]) if not args.is_empty() else 0) if sender == 1 else "Only the host can do that"
			"fob_tier":
				why = server_upgrade_fob() if sender == 1 else "Only the host can do that"
			"hc_home":
				why = ("" if Heroes.set_home(roster(), String(args[0]), bool(args[1])) else "No such squad") if sender == 1 and args.size() >= 2 else "Only the host can do that"
				_changed(&"roster")
			"hc_rename":
				why = "" if sender == 1 and args.size() >= 2 and Heroes.rename(roster(), String(args[0]), String(args[1])) != "" else "Only the host can do that"
				_changed(&"roster")
			"guards":
				why = server_set_guards(int(args[0]) if not args.is_empty() else 0) if sender == 1 else "Only the host can do that"
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
			"ready":
				server_set_ready(sender if sender != 0 else 1, bool(args[0]))
			"loadout":
				why = server_loadout(sender if sender != 0 else 1, String(args[0]), String(args[1]), args[2] if args[2] is Dictionary else {})
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
			held.append({"cid": String(c.cid), "title": String(c.get("title", "")), "deadline_day": int(c.get("deadline_day", 0)),
				"zone_id": String(c.get("zone_id", ""))})
	return {
		"day": day(), "funds": BaseEconomy.funds(),
		"roster": roster(), "hiring": {"pool": Hiring.pool(hiring(), day()), "refreshed_day": int(hiring().get("refreshed_day", 1))},
		"stash": stash(), "prep": _prep(), "catalog": BaseEconomy.shop_catalog(), "held": held,
		"daily_wages": Roster.daily_wages(roster()), "bill_in_days": Economy.days_to_bill(), "weekly_bill": int(Economy.weekly_bill().total),
		"players": keys, "in_base": in_base(), "ready": _ready_peers.keys(),
		"guards": guards(), "assault": base().get("assault", {}), "defences": base().get("defences", []), "fob_tier": fob_tier(), "max_guards": max_guards(),
		"rebels": RebelSupport.view(), "favours": int(RebelSupport._s().get("favours", 0)), "rebel_upgrades": RebelSupport.upgrades_view(),
		"company_squads": company_squads(), "max_squads": int(BaseFob.TIERS[fob_tier()].squads),
		"home": ZoneControl.home(), "zone_control": ZoneControl.view(),  # docs/lhd_home.md
		"pool_models": MotorPool.view().map(func(v: Dictionary) -> String: return String(v.model)),  # the LHD's vehicle park
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


## This machine: opens the loadout menu (LoadoutScreen) on its own layer over everything, and
## returns it (closed: it frees itself and its layer). Only at the base between deployments.
func open_loadout() -> LoadoutScreen:
	if not campaign_running or not in_base() or RosterDeployment.is_running(view.get("roster", {})):
		note.emit("Loadouts are at the base, between deployments")
		return null
	var layer := CanvasLayer.new()
	layer.name = "LoadoutLayer"
	layer.layer = 21  # over the base screen (20)
	get_tree().root.add_child(layer)
	var screen := LoadoutScreen.new()
	screen.name = "LoadoutScreen"
	screen.closed.connect(layer.queue_free)
	layer.add_child(screen)
	return screen


## This machine: opens the 3D loadout editor (LoadoutEditor) on its own layer, `fit` (an item
## id, "" none) put on the model as a draft (the armory's "Fit on me"). Only at the base between
## deployments, like the loadout menu.
func open_loadout_3d(fit := "") -> LoadoutEditor:
	if not campaign_running or not in_base() or RosterDeployment.is_running(view.get("roster", {})):
		note.emit("Loadouts are at the base, between deployments")
		return null
	var layer := CanvasLayer.new()
	layer.name = "LoadoutEditorLayer"
	layer.layer = 22  # over the base screen (20) and the loadout menu (21)
	get_tree().root.add_child(layer)
	var editor := LoadoutEditor.new()
	editor.name = "LoadoutEditor"
	editor.closed.connect(layer.queue_free)
	layer.add_child(editor)
	if fit != "":
		editor.fit_item(fit)
	return editor


## This machine: opens the 3D armory (ArmoryRoom) on its own layer. Only at the base.
func open_armory() -> ArmoryRoom:
	if not campaign_running or not in_base() or RosterDeployment.is_running(view.get("roster", {})):
		note.emit("The armory is at the base, between deployments")
		return null
	var layer := CanvasLayer.new()
	layer.name = "ArmoryLayer"
	layer.layer = 21
	get_tree().root.add_child(layer)
	var room := ArmoryRoom.new()
	room.name = "ArmoryRoom"
	room.closed.connect(layer.queue_free)
	layer.add_child(room)
	return room


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


# --- Buying what an edit is short of (Captain, 2026-10-15) ----------------------------------
# "Need the purchase option in the loadout editor so we aren't constrained by a lack of items
# but have to buy them." What the last edit could not draw from the stash is written on the
# roster entry ("edit_missing", {item id: units}, replicated with the roster so every client's
# menu can price it) with the edit's template kept here on the host; "buy_missing" buys it at
# the shop's prices with company money and redoes the edit.

var _edit_wants := {}  # who -> the template the last short edit asked for


func _note_edit_missing(a: Dictionary, res: Dictionary) -> void:
	var missing: Dictionary = {}
	for id: Variant in res.get("missing", {}):
		if int(res.missing[id]) > 0:
			missing[String(id)] = int(res.missing[id])
	if missing.is_empty():
		a.person.erase("edit_missing")
		_edit_wants.erase(a.who)
	else:
		a.person["edit_missing"] = missing
		_edit_wants[a.who] = a.template.duplicate(true)


## What buying `missing` ({id: units}) costs, over the items the shop sells ({"cost", "units",
## "unbuyable": [ids]}).
static func missing_cost(missing: Dictionary) -> Dictionary:
	var cost := 0
	var units := 0
	var unbuyable: Array = []
	for id: String in missing:
		var price := BaseEconomy.item_price(StringName(id))
		if price <= 0:
			unbuyable.append(id)
			continue
		cost += price * int(missing[id])
		units += int(missing[id])
	return {"cost": cost, "units": units, "unbuyable": unbuyable}


## Host: buys what `a`'s last edit was short of (only `only_id` when given), then redoes the
## edit. Returns what happened, or why not.
func _server_buy_missing(lvl, sender: int, a: Dictionary, only_id := "") -> String:
	var missing: Dictionary = a.person.get("edit_missing", {})
	if missing.is_empty() or not _edit_wants.has(a.who):
		return "Nothing missing to buy"
	var want := {}
	for id: String in missing:
		if only_id == "" or only_id == id:
			want[id] = int(missing[id])
	var price := missing_cost(want)
	if int(price.units) <= 0:
		return "The shop doesn't sell that"
	if BaseEconomy.funds() < int(price.cost):
		return "Not enough cash: $%d needed" % int(price.cost)
	for id: String in want:
		if id not in price.unbuyable:
			Economy.server_buy(StringName(id), int(want[id]), sender)
	a["template"] = _edit_wants[a.who]
	var lines := _loadout_apply(lvl, [a])
	return "%s: bought %d items for $%d%s" % [a.name, int(price.units), int(price.cost), (". " + lines[0]) if lines[0] != "" else ""]
