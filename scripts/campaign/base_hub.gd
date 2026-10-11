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
##   in place, players keep their gear across (their main character's, or their stand-in's).
##
## Entry points: the main menu's campaign buttons (prepare_session), begin_prep() (the
## contract board, when a contract is accepted), server_deploy(), server_end_deployment() (the
## map's extraction), server_recover_member() / server_write_off_member() (recovery
## contracts). A non-campaign session (the compound as before, and every older suite) never
## sets campaign_running, so none of this touches it.

## The base screen's copy of the campaign changed (every peer).
signal view_changed
## A message for this machine's player (an answer to a request).
signal note(text: String)
## Host: a deployment was settled (the report RosterDeployment.resolve returns).
signal deployment_ended(report: Dictionary)

const BASE_SCENE := "res://scenes/levels/base_fob.tscn"
const COMPOUND_SCENE := "res://scenes/levels/compound.tscn"
const SQUAD_SIZE := CompoundLevel.SQUAD_SIZE
## The zone a deployment goes to when nothing says otherwise.
const DEFAULT_ZONE_ID := "compound_01"
## Proposed (design doc: "wages and upkeep are paid weekly, like MW5"): wages accrue daily
## and are paid every WAGE_PERIOD_DAYS.
const WAGE_PERIOD_DAYS := 7
## How often the host reads the stash back from the hub's world items.
const STASH_POLL_S := 1.0
## Proposed: what a new company owns besides its hiring budget (enough to kit two players).
const STARTING_STASH := [["plate_carrier", 2], ["plate_ceramic_l4", 4], ["helmet", 2], ["assault_pack", 2], ["m4a1", 2],
	["mag_556", 12], ["ifak", 4], ["smoke_grenade", 2], ["frag_grenade", 2]]
## Debug builds: End extracts everyone within this many metres of the host (until the map's
## extraction calls server_end_deployment).
const DEBUG_EXTRACT_M := 60.0

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
var _broadcast_queued := false
var _stash_poll := 0.0
var _ui: BaseUI


func _ready() -> void:
	rng.randomize()
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.session_ended.connect(_on_session_ended)
	Campaign.changed.connect(func(_name: StringName) -> void: _queue_broadcast())


# --- Campaign state -------------------------------------------------------------------------

func roster() -> Dictionary:
	return Campaign.section(&"roster")


func hiring() -> Dictionary:
	return Campaign.section(&"hiring")


func base() -> Dictionary:
	return Campaign.section(&"base")


func day() -> int:
	return int(base().get("day", 1))


func member(mid: String) -> Dictionary:
	return Roster.get_member(roster(), mid)


func stash() -> Array:
	if not base().has("stash"):
		base()["stash"] = []
	return base()["stash"]


## Host: a fresh campaign (the save for Campaign.campaign_id is deleted): day 1, the starting
## stash, an empty roster and a hiring board drawn from `hiring_seed` (random if negative).
func new_campaign(hiring_seed := -1) -> void:
	Campaign.reset_campaign()
	var b := base()
	b["day"] = 1
	b["stash"] = []
	for pair: Array in STARTING_STASH:
		BaseArmory.add(b.stash, StringName(pair[0]), int(pair[1]))
	b["prep"] = _empty_prep()
	b["wages_owed"] = 0
	b["wage_days"] = 0
	BaseEconomy.funds()  # the stand-in's starting budget, when there's no economy yet
	var h := hiring()
	h["seed"] = hiring_seed if hiring_seed >= 0 else randi()
	h["refresh"] = 0
	Hiring.redraw(h, 1)
	Roster.members(roster())
	Roster.players(roster())
	_changed_all()


## Host: the saved campaign for Campaign.campaign_id, or a new one if there's none.
func load_or_new() -> void:
	if not Campaign.load_campaign() or not base().has("day"):
		new_campaign()
	_changed_all()


## Host: saves the campaign (the hub's stash and people read back first).
func server_save() -> void:
	_read_back_base()
	Campaign.save_campaign()


func base_zone_id() -> String:
	return "fob_" + Campaign.campaign_id


static func _empty_prep() -> Dictionary:
	return {"squad": [], "contract": {}, "zone_kind": RosterDeployment.CONTRACT, "zone_id": "", "scene": ""}


func _prep() -> Dictionary:
	if not base().has("prep"):
		base()["prep"] = _empty_prep()
	return base()["prep"]


## Host (the contract board): a contract was accepted; the prep phase at the base starts.
## `contract` is kept as it is and handed to the deployment; `zone_kind` is "contract" or
## "hot"; `zone_id` and `scene` name the zone's save and level ("" for the test compound).
## The squad pick starts from the default (RosterDeployment.auto_squad) if it's empty.
func begin_prep(contract: Dictionary, zone_kind := RosterDeployment.CONTRACT, zone_id := "", scene := "") -> void:
	var prep := _prep()
	prep["contract"] = contract.duplicate(true)
	prep["zone_kind"] = zone_kind
	prep["zone_id"] = zone_id
	prep["scene"] = scene
	if (prep.squad as Array).is_empty():
		prep["squad"] = RosterDeployment.auto_squad(roster(), SQUAD_SIZE - _player_count())
	_changed(&"base")


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


## A deployment is running and this is the host (CompoundLevel's hooks ask this).
func deployment_running() -> bool:
	return campaign_running and multiplayer.is_server() and RosterDeployment.is_running(roster())


## Main menu (before hosting or joining): this session is the campaign. Swaps the level for
## the base hub; the host loads the campaign save (or starts one).
func prepare_session(as_host: bool) -> void:
	campaign_running = true
	if as_host:
		load_or_new()
		GameState.zone_id = base_zone_id()
	if not in_base():
		_swap_level(BASE_SCENE)


## Host: every peer swaps the running level for `scene_path`; the new level then starts as if
## hosted, and every connected player is added back (with their role and their gear).
func server_switch_level(scene_path: String) -> CompoundLevel:
	var old := level()
	var roles: Dictionary = old.player_roles.duplicate() if old else {}
	_gear_applied.clear()
	if is_instance_valid(_ui):
		_ui.close()
	var fresh := _swap_level(scene_path)
	_client_switch_level.rpc(scene_path)
	fresh.player_roles = roles
	fresh._on_hosted()
	for id in multiplayer.get_peers():
		fresh._on_peer_joined(id)
	_queue_broadcast()
	return fresh


@rpc("authority", "call_remote", "reliable")
func _client_switch_level(scene_path: String) -> void:
	campaign_running = true
	if is_instance_valid(_ui):
		_ui.close()
	_swap_level(scene_path)


## Replaces the running level with a new `scene_path` under the same parent (this peer only).
func _swap_level(scene_path: String) -> CompoundLevel:
	var old := level()
	if old == null:
		push_error("BaseHub: no level to swap")
		return null
	var parent := old.get_parent()
	var index := old.get_index()
	# The old level stays in the tree to the end of the frame (the voxel terrain wants its world
	# while it shuts down), but it gives up its name, the "level" group and Net's signals
	# (hosting right after a swap would start it too).
	for sig: Signal in [Net.hosted, Net.joined, Net.peer_joined, Net.peer_left]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == old:
				sig.disconnect(c.callable)
	old.remove_from_group(&"level")
	old.name = "%s_old_%d" % [old.name, old.get_instance_id()]
	old.process_mode = Node.PROCESS_MODE_DISABLED
	old.queue_free()
	var fresh: CompoundLevel = (load(scene_path) as PackedScene).instantiate()
	parent.add_child(fresh)
	parent.move_child(fresh, index)
	return fresh


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
		if p is Soldier and not p.is_queued_for_deletion():
			var main := Roster.main_character(roster(), player_key(p.name.to_int()))
			main["gear"] = Roster.json_safe((p as Soldier).inventory.net_state.duplicate(true))


func _process(delta: float) -> void:
	if not campaign_running or not multiplayer.is_server() or not in_base():
		return
	_stash_poll -= delta
	if _stash_poll > 0.0:
		return
	_stash_poll = STASH_POLL_S
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
	view = {}
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
	player._client_message.rpc_id(player.name.to_int(), text)


## Host: counts one player respawn against the pool. Returns the line the player sees.
func server_count_respawn() -> String:
	var price := BaseEconomy.respawn_price()
	var cost := RosterDeployment.respawn_cost(roster(), price)
	var text := ""
	if cost == 0:
		text = "Respawn: %d free left" % RosterDeployment.count_respawn(roster(), false)
	elif BaseEconomy.try_spend(cost, "Respawn"):
		RosterDeployment.count_respawn(roster(), true)
		text = "Respawn bought ($%d)" % cost
	else:
		BaseEconomy.charge(cost, "Respawn on credit")
		RosterDeployment.count_respawn(roster(), true)
		text = "No free respawns and no cash: $%d on credit" % cost
	_changed(&"roster")
	return text


# --- Deployments -------------------------------------------------------------------------------

## Host: takes the picked squad into the zone. `options` may override the prep: "squad"
## (member ids), "zone_kind", "zone_id", "scene". Players whose main character is recovering
## get a stand-in (an available member not in the squad, else a free rookie). Returns "" or
## why it can't.
func server_deploy(options := {}) -> String:
	if not multiplayer.is_server():
		return "Only the host deploys"
	if RosterDeployment.is_running(roster()):
		return "A deployment is already running"
	_read_back_base()
	var prep := _prep()
	var scene := String(options.get("scene", prep.get("scene", "")))
	if scene == "":
		scene = COMPOUND_SCENE
	var zone_kind := String(options.get("zone_kind", prep.get("zone_kind", RosterDeployment.CONTRACT)))
	var zone_id := String(options.get("zone_id", prep.get("zone_id", "")))
	if zone_id == "":
		zone_id = DEFAULT_ZONE_ID
	var squad: Array = options.get("squad", prep.get("squad", []))
	squad = squad.slice(0, maxi(SQUAD_SIZE - _player_count(), 0))
	var stand_ins := _pick_stand_ins(squad)
	RosterDeployment.begin(roster(), squad, zone_kind, zone_id, scene, day(), prep.get("contract", {}), stand_ins)
	prep["contract"] = {}
	_changed_all()
	GameState.zone_id = zone_id
	server_switch_level(scene)
	return ""


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
	var present := {}
	for n: Node in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id") and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			present[String(s.get_meta(&"roster_id"))] = true
	var mid := RosterDeployment.member_for_slot(roster(), role, present)
	if mid == "":
		return null
	var m := member(mid)
	if lvl.ai.get_node_or_null(NodePath(String(m.callsign))) != null:
		return null  # a node by that name is still there (freed this frame)
	var squad := lvl.squad_for(&"friendly")
	var anchor: Node3D = squad.leader if squad and is_instance_valid(squad.leader) else null
	var wedge: Array = Squad.FORMATIONS["wedge"]
	var pos: Vector3 = anchor.global_transform * (wedge[maxi(slot - 1, 0) % wedge.size()] as Vector3) if anchor \
		else lvl.next_spawn_point() + Vector3(0, 0, 3)
	var stats := Roster.ai_stats(m)
	var s := lvl.spawn_soldier({"name": String(m.callsign), "faction": "friendly", "variant": "multicam", "pos": pos, "loadout": [],
		"role": "", "team": team, "slot": slot, "combat": stats.combat, "discipline": stats.discipline, "guard": false})
	s.role = role
	s.set_meta(&"roster_id", mid)
	s.inventory.net_state = GameState.from_json(m.get("gear", {}).duplicate(true))
	RosterDeployment.mark_spawned(roster(), mid)
	_changed(&"roster")
	return s


## Host hook (CompoundLevel._remove_squadmate): a roster squadmate leaves the zone early (a
## player took the slot): they keep their gear and didn't deploy after all.
func server_squadmate_leaving(s: Soldier) -> void:
	if not s.has_meta(&"roster_id") or not RosterDeployment.is_running(roster()):
		return
	var mid := String(s.get_meta(&"roster_id"))
	server_store_member_gear(mid, s.inventory.net_state)
	RosterDeployment.unmark_spawned(roster(), mid)
	_changed(&"roster")


## Host hook (CompoundLevel._on_died_for_good): a roster squadmate was killed.
func server_squadmate_died(s: Soldier) -> void:
	if s.has_meta(&"roster_id") and RosterDeployment.is_running(roster()):
		RosterDeployment.mark_fallen(roster(), String(s.get_meta(&"roster_id")))
		_changed(&"roster")


## Host (the map's extraction): the deployment ends. `extracted` are the soldiers who made it
## out (AI squadmates and players; players are always counted back). Every roster squadmate
## who deployed is settled (RosterDeployment.resolve): dead ones are lost with their gear on
## their body in the zone, those alive but not in `extracted` go MIA (a recovery contract is
## requested), the rest come back with their gear, experience and wounds. Days pass, the zone
## and the campaign are saved, and with `return_to_base` everyone goes back to the hub.
## Returns the debrief report ({} if no deployment was running).
func server_end_deployment(extracted: Array, return_to_base := true) -> Dictionary:
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
			o["state"] = RosterDeployment.EXTRACTED if made_it.has(s.get_instance_id()) else RosterDeployment.LEFT_BEHIND
			o["gear"] = s.inventory.net_state.duplicate(true)
			o["wounds"] = s.vitals.wound_list()
			o["blood"] = s.vitals.blood_fraction()
			o["pos"] = [s.global_position.x, s.global_position.y, s.global_position.z]
		outcomes.members[mid] = o
	for n: Node in lvl.players.get_children():
		var p := n as Soldier
		if p and not p.is_queued_for_deletion():
			outcomes.players[player_key(p.name.to_int())] = {"gear": p.inventory.net_state.duplicate(true),
				"wounds": p.vitals.wound_list(), "blood": p.vitals.blood_fraction()}
	var report := RosterDeployment.resolve(roster(), outcomes, rng, day())
	for mid: String in report.mia:
		var m := member(mid)
		BaseEconomy.request_recovery_contract({"mid": mid, "name": m.name, "callsign": m.callsign, "role": m.role,
			"zone_id": report.zone_id, "day": day(), "pos": m.get("mia_pos", [])})
	GameState.save_zone()  # the zone keeps its bodies, loot and damage
	server_advance_days(int(RosterDeployment.DAYS.get(report.zone_kind, 1)))
	_changed_all()
	Campaign.save_campaign()
	deployment_ended.emit(report)
	if return_to_base:
		GameState.zone_id = base_zone_id()
		server_switch_level(BASE_SCENE)
	return report


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

## Host: `days` campaign days pass: the wounded recover, the hiring board turns over every
## Hiring.REFRESH_DAYS, wages accrue and are paid every WAGE_PERIOD_DAYS.
func server_advance_days(days: int) -> void:
	if days <= 0:
		return
	var b := base()
	b["day"] = day() + days
	Roster.advance_days(roster(), days, day())
	Hiring.refresh_if_due(hiring(), day())
	b["wages_owed"] = int(b.get("wages_owed", 0)) + Roster.daily_wages(roster()) * days
	b["wage_days"] = int(b.get("wage_days", 0)) + days
	if int(b.wage_days) >= WAGE_PERIOD_DAYS:
		BaseEconomy.pay_wages(int(b.wages_owed), int(b.wage_days))
		b["wages_owed"] = 0
		b["wage_days"] = 0
	_changed_all()
	_refresh_muster()


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


## Host: buys `count` of `id` at the shop into the stash. Returns "" or why not.
func server_buy(id: StringName, count := 1) -> String:
	if not ItemDB.has_item(id) or count <= 0:
		return "Not for sale"
	var price := BaseEconomy.item_price(id) * count
	if price <= 0:
		return "Not for sale"
	if not BaseEconomy.try_spend(price, "Bought %d %s" % [count, ItemDB.get_item(id).name]):
		return "Not enough cash: $%d" % price
	server_add_to_stash(id, count)
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


# --- Requests from the base screen ---------------------------------------------------------

## Any peer: asks the host to do something at the base. `action`: "hire" [cid], "release"
## [mid], "medbay" [mid or "player:<key>"], "pick" [mid, bool], "role" [mid, role], "buy"
## [item id, count], "rest" [days], "deploy" [], "save" []. The answer comes back as `note`.
func request(action: String, args: Array = []) -> void:
	_server_request.rpc_id(1, action, args)


@rpc("any_peer", "call_local", "reliable")
func _server_request(action: String, args: Array) -> void:
	if not multiplayer.is_server() or not campaign_running:
		return
	var sender := multiplayer.get_remote_sender_id()
	var why := ""
	var at_base := in_base() and not RosterDeployment.is_running(roster())
	if action not in ["save"] and not at_base:
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
				why = server_buy(StringName(args[0]), int(args[1]) if args.size() > 1 else 1)
			"rest":
				server_advance_days(clampi(int(args[0]) if not args.is_empty() else 1, 1, 30))
			"deploy":
				why = "Only the host deploys" if sender != 1 else server_deploy()
			"save":
				server_save()
				why = "Campaign saved"
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
	var b := base()
	var keys := {}
	keys["1"] = player_key(1)
	for peer in multiplayer.get_peers():
		keys[str(peer)] = player_key(peer)
	return {
		"day": day(), "funds": BaseEconomy.funds(), "stub_economy": BaseEconomy.is_stub(),
		"roster": roster(), "hiring": {"pool": Hiring.pool(hiring(), day()), "refreshed_day": int(hiring().get("refreshed_day", 1))},
		"stash": stash(), "prep": _prep(), "catalog": BaseEconomy.shop_catalog(),
		"recovery_requests": b.get("recovery_requests", []), "wages_owed": int(b.get("wages_owed", 0)),
		"wage_days": int(b.get("wage_days", 0)), "daily_wages": Roster.daily_wages(roster()),
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


func _unhandled_input(event: InputEvent) -> void:
	if not campaign_running or not Net.is_hosting():
		return
	if event.is_action_pressed(&"quick_save"):
		server_save()
		note.emit("Campaign saved")
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_END and deployment_running():
		var me := level().players.get_node_or_null(^"1") as Node3D
		if me:
			server_extract_near(me.global_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and campaign_running and Net.is_hosting():
		server_save()
