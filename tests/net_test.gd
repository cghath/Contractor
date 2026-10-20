extends Node
## Two-process co-op check over real ENet: one instance hosts, one joins, and the client
## drives its player through RPCs and checks what replicates back.
##   <exe> --headless --path . res://tests/net_test.tscn -- --host
##   <exe> --headless --path . res://tests/net_test.tscn -- --join 127.0.0.1
## The client prints NET TEST PASSED/FAILED and exits with the failure count; the host
## exits when the client leaves while down (a leave on its feet is the rejoin check's).
## Later checks: leaving and joining again, then dropping and picking up a helmet (B-07), and
## the session switching level twice, compound -> zone -> compound, as the campaign's
## deploy and return do (B-04): no despawn for a node the client never had, everything the
## host had at the switch here once the loading screen goes, other players where the host put
## them (not at the origin).

const KIT: Array[StringName] = [&"plate_carrier", &"plate_ceramic_l4", &"m4a1", &"helmet", &"assault_pack"]
## A dead player's body in the zone save the host loads (as Soldier.body_record writes it), so
## the client, joining late, finds it there with its gear.
const SAVED_BODY := {"uid": "test_net_body_1", "label": "Player 9", "faction": "friendly", "variant": "desert", "role": "",
	"pos": [0.0, 0.1, 26.5], "rot_y": 0.0, "age_s": 30.0, "marker": true,
	"gear": {"slots": {"primary": "m4a1", "vest": "plate_carrier", "helmet": "helmet"}, "slot_state": {"primary": {"rounds": 21}},
		"containers": {"vest": [{"id": "mag_556", "count": 3}], "pockets": [], "backpack": []}, "hands": ""}}
## Voxel edits in the same save: an impact mark on the main building's concrete and a bullet
## hole in the shed's plank wall (voxel coordinates, an old save's whole-voxel hole), plus a
## calibre-sized bullet hole through the next voxel, which the late joiner gets in the log.
const SAVED_EDITS := [{"op": "mark", "p": [-29.5, 13.5, -40.0], "n": [0.0, 0.0, 1.0], "m": 2},
	{"op": "holes", "v": [175, 13, -71]},
	{"op": "shot", "a": [177.5, 13.5, -70.0], "an": [0.0, 0.0, 1.0], "b": [177.5, 13.5, -71.0], "bn": [0.0, 0.0, -1.0], "d": 0.0057, "m": 3, "v": [177, 13, -71]}]
## Where the host marks the perimeter wall's inner face once the client is in (live, by RPC).
const LIVE_MARK := Vector3(6.0, 1.2, 19.7)
## How old the purple smoke the host throws before the client joins already is (spawn_smoke's
## age): the client's copy must be at least this old.
const SMOKE_AGE_S := 3.0

## A hostile pair the host puts in the zone and turns into a profile (Virtualizer) before the client
## gets there: the client must see none of it until the host brings it back, and then both men
## with the rounds they had (VIRTUAL_ROUNDS).
const VIRTUAL_MEN: Array[String] = ["NetVirtual_1", "NetVirtual_2"]
const VIRTUAL_ROUNDS := 13
var _virtual_group := {}

## Two AI the host stages before the client joins: one dragging the other (_stage_drag).
const DRAGGER := "Dragger"
const DRAGGED := "Dragged"
## A hostile the host stages aiming its rifle (_stage_drag), for the client to shoot and loot
## (_check_looted_rifle).
const AIMER := "Aimer"
const AIMER_AT := Vector3(4, 0.1, 33)
## Rounds the aimer has left after firing some before the client joins: the counts
## (Inventory.net_ammo) say so, whatever snapshot (net_gear) came with them (playtest blocker B2).
const AIMER_ROUNDS := 23
## Fix B-08 (co-op soak S0706: clients a round above the host while it fired): once the client
## is in, the host fires the dragger's rifle dry a round a frame or so, picking up a magazine
## halfway (a whole new snapshot, net_gear, among the counts); the client must end on 0 too.
const DRY_SHOT_S := 0.07
const DRY_MAG_AT := 15

## A player body the host adds after each level switch for a peer that isn't connected: its
## position is its owner's to send, so only its spawn_position puts it where the host did.
const GHOST := 4243


## Counts the engine's errors whose text has one of `matches` in it.
class ErrorCount extends Logger:
	var matches: Array[String] = []
	var counts := {}

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		for m in matches:
			if m in code or m in rationale:
				counts[m] = int(counts.get(m, 0)) + 1

	func count(m: String) -> int:
		return int(counts.get(m, 0))

var failures := 0
var level: CompoundLevel
## Host: its save fixture (SAVED_BODY, SAVED_EDITS) was there to load when hosting started.
var _fixture_loaded := false
## Client: where the host put GHOST in the level it switched to (_ghost_at).
var _ghost_pos: Variant = null
var _errors: ErrorCount


func _ready() -> void:
	GameState.zone_id = "test_net" + OS.get_environment("CONTRACTOR_TEST_TAG")
	CompoundLevel.spawn_ai = false
	if "--join" in OS.get_cmdline_user_args():
		# Both processes share the zone name and user data: the save fixture is the host's alone
		# (audit A1-06: a client deleting it raced the host's loading it). Checked at the end.
		Roles.local_choice = Roles.MARKSMAN  # the client's pick in the main menu, sent on join
	else:
		GameState.delete_save()
		_write_save_with_body()
	add_child(load("res://scenes/main.tscn").instantiate())  # main reads --host/--join
	await get_tree().process_frame
	level = CompoundLevel.current(self)
	if Net.is_hosting():
		Net.peer_joined.connect(_give_kit)
		Net.peer_left.connect(_on_client_left)
		BaseHub.level_switched.connect(_on_host_switched)
		get_tree().create_timer(240.0).timeout.connect(func() -> void: get_tree().quit(1))
		_stage_drag()
	else:
		_run_client()


## Host: the client left while down (it knocks itself out first), so its body stays behind
## with its gear. The host's exit code says whether it did (run_tests.sh checks it).
func _on_client_left(id: int) -> void:
	var was: Soldier = level.players.get_node_or_null(str(id))
	if was and was.vitals.is_up():
		print("[host] peer %d left on its feet: the rejoin check" % id)
		return
	await get_tree().process_frame
	var left := level.bodies.get_children().filter(func(b: Node) -> bool:
		return b is Soldier and (b as Soldier).display_name() == "Player %d" % id and (b as Soldier).vitals.is_dead() \
			and (b as Soldier).inventory.slots[&"primary"] == &"m4a1")
	print("[host] peer %d left while down: %s" % [id, "its body stayed, gear and all" if left.size() == 1 else "NO BODY"])
	get_tree().quit(0 if left.size() == 1 and _fixture_loaded else 1)


## Host: a zone save holding one body (SAVED_BODY), loaded when hosting starts.
func _write_save_with_body() -> void:
	DirAccess.make_dir_recursive_absolute(GameState.SAVE_DIR)
	var file := FileAccess.open(GameState.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": GameState.SAVE_VERSION, "looted": [], "dropped": {}, "voxel_edits": SAVED_EDITS, "bodies": [SAVED_BODY]}))
	file.close()


## Host, before anyone joins: an AI drags a downed one (DRAGGER, DRAGGED), so the late
## joiner has to see the drag from the replicated state alone.
func _stage_drag() -> void:
	while not level.voxel_world.is_built():
		await get_tree().process_frame
	# Audit A1-06: the saved body and wall edits are this host's to load; if they're missing the
	# client's checks of them would fail for a reason that isn't replication.
	_fixture_loaded = GameState.bodies.size() == 1 and String(GameState.bodies[0].get("uid", "")) == SAVED_BODY.uid \
		and GameState.voxel_edits.size() == SAVED_EDITS.size()
	print("[host] %s" % ("loaded its saved body and wall edits" if _fixture_loaded else "FAILED to load its saved body and wall edits (the fixture was gone)"))
	var make := func(callsign: String, pos: Vector3) -> Soldier:
		var s := level.spawn_soldier({"name": callsign, "faction": "hostile", "variant": "woodland", "pos": pos,
			"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		return s
	var dragger: Soldier = make.call(DRAGGER, Vector3(12, 0.1, 30))
	var dragged: Soldier = make.call(DRAGGED, Vector3(12, 0.1, 31.1))
	await get_tree().create_timer(0.3).timeout
	dragged.vitals.server_damage(500.0)
	print("[host] staged a drag: %s" % dragger.server_pick_up_body(dragged, Soldier.DRAG, INF))
	var aimer: Soldier = make.call(AIMER, AIMER_AT)
	aimer.want_aim = true  # its rifle shouldered when the client shoots it
	while aimer.inventory.rounds_in(&"primary") > AIMER_ROUNDS:
		aimer.inventory.consume_round(&"primary")
	# Smoke already out when the client joins (audit L2-01): it must see it too, as old as here.
	# It starts SMOKE_AGE_S old, so the check doesn't hang on how long the client takes to join
	# (a quick join reached the client at 1.6 s, under the old 2 s mark, and failed).
	level.spawn_smoke.rpc(Vector3(-12, 0.1, 30), "purple", SMOKE_AGE_S)


func _give_kit(id: int) -> void:
	await get_tree().create_timer(0.5).timeout  # let the player spawn
	var player: Soldier = level.players.get_node_or_null(str(id))
	_kit_up(player)
	player.vitals.server_damage(40.0)
	# A small fragment wound in the left forearm to treat (and maybe a fracture).
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	level.voxel_world.server_mark(LIVE_MARK, Vector3.FORWARD, VoxelWorld.Mat.CONCRETE)
	print("[host] gave peer %d a kit" % id)
	_fire_dragger_dry()


## Host: B-08. The dragger's rifle fired to empty while the client watches (see DRY_SHOT_S).
func _fire_dragger_dry() -> void:
	await get_tree().create_timer(1.0).timeout
	var dragger: Soldier = _combatant(DRAGGER)
	if dragger == null:
		print("[host] no dragger to fire dry")
		return
	var shots := 0
	while dragger.inventory.consume_round(&"primary"):
		shots += 1
		if dragger.inventory.rounds_in(&"primary") == DRY_MAG_AT:
			dragger.inventory.take(&"mag_556")
		await get_tree().create_timer(DRY_SHOT_S).timeout
	print("[host] fired the dragger's rifle dry: %d shots, %d left, counts %s" % [shots, dragger.inventory.rounds_in(&"primary"), dragger.inventory.net_ammo])


func _kit_up(player: Soldier) -> void:
	for item in KIT:
		player.inventory.take(item)
	player.inventory.take(&"mag_556", 2)
	player.inventory.take(&"ifak")
	player.inventory.take(&"morphine")


## Host: the client asks for a level switch, as a deploy or a return to base does (BaseHub's
## server_switch_level): to the test zone (its own zone save, emptied first) or back to the
## compound (this test's save).
@rpc("any_peer", "call_remote", "reliable")
func _host_switch(kind: String) -> void:
	if not multiplayer.is_server():
		return
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	if kind == "zone":
		var keep := GameState.zone_id
		GameState.zone_id = "test_net_switch" + tag
		GameState.delete_save()
		GameState.zone_id = keep
		BaseHub.server_switch_level({"level": "zone", "def": ZoneDef.get_def("test")}, "test_net_switch" + tag)
	else:
		BaseHub.server_switch_level({"level": "compound"}, "test_net" + tag)


## Host: the session switched level: the players there get their kit again (a plain session
## carries no gear across), and a player body for a peer that isn't here (GHOST) comes in near
## the level's start.
func _on_host_switched(fresh: CompoundLevel) -> void:
	level = fresh
	for p: Node in level.players.get_children():
		if p is Soldier and p.name != &"1":
			_kit_up(p as Soldier)
	var ghost := CompoundLevel.PLAYER_SCENE.instantiate() as Soldier
	ghost.name = str(GHOST)
	ghost.position = level._player_start(GHOST) + Vector3(6.0, 0.0, 0.0)
	ghost.spawn_position = ghost.position
	level.players.add_child(ghost, true)
	_ghost_at.rpc(ghost.position)
	print("[host] switched to %s; stand-in player body at %s" % [level.level_info().level, ghost.position])
	if fresh is ZoneLevel:
		_stage_virtual(fresh as ZoneLevel)


## Host, in the zone: VIRTUAL_MEN go into a profile at once (nothing of them is sent to anyone).
func _stage_virtual(zone: ZoneLevel) -> void:
	var v := Virtualizer.of(zone)
	if v == null:
		print("[host] the zone has no virtualizer")
		return
	Virtualizer.enabled = false  # it waits for the client's word, not for distances
	var squad := Squad.new()
	squad.name = "NetVirtual"
	squad.faction = &"hostile"
	zone.add_child(squad)
	var men: Array = []
	for i in VIRTUAL_MEN.size():
		var s := zone.spawn_soldier({"name": VIRTUAL_MEN[i], "faction": "hostile", "variant": "urban", "pos": zone.spawn_point(0) + Vector3(30.0 + i * 2.0, 0.0, 30.0),
			"loadout": ["plate_carrier", "m4a1", "mag_556"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).squad = squad
		while s.inventory.rounds_in(&"primary") > VIRTUAL_ROUNDS:
			s.inventory.consume_round(&"primary")
		men.append(s)
	_virtual_group = {"squad": squad, "soldiers": men}
	v.track(_virtual_group, "patrol", false)
	print("[host] %s" % ("staged a virtual pair" if v.server_virtualize(_virtual_group, true) else "FAILED to virtualize the pair"))


## Host: the client has looked; the virtual pair comes back.
@rpc("any_peer", "call_remote", "reliable")
func _host_wake_virtual() -> void:
	var v := Virtualizer.of(level)
	if multiplayer.is_server() and v and not _virtual_group.is_empty():
		v.server_wake(_virtual_group)
		v.server_flush()
		Virtualizer.enabled = true


@rpc("authority", "call_remote", "reliable")
func _ghost_at(pos: Vector3) -> void:
	_ghost_pos = pos


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _run_client() -> void:
	_errors = ErrorCount.new()
	_errors.matches = ["recv_nodes", "Ignoring delta", "unknown peer"]
	OS.add_logger(_errors)
	var deadline := Time.get_ticks_msec() + 20000
	var me: Soldier
	while Time.get_ticks_msec() < deadline:
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me and me.inventory.slots[&"primary"] == &"m4a1":
			break
		await get_tree().process_frame
	print("Client over ENet")
	check(me != null and me.inventory.slots[&"primary"] == &"m4a1", "kit given by the host replicated to the client")
	var smoke := SmokeCloud.clouds_of("purple")
	check(smoke.size() == 1 and smoke[0].age >= SMOKE_AGE_S and smoke[0].global_position.distance_to(Vector3(-12, 0.1, 30)) < 0.1,
		"smoke that went off before joining is here, as old as on the host (%s)" % ["%.1f s" % smoke[0].age if smoke.size() == 1 else "none"])
	if me == null:
		_finish()
		return
	me.set_physics_process(false)
	await _wait_for(func() -> bool: return me.role == Roles.MARKSMAN, 3.0)
	check(me.role == Roles.MARKSMAN and me.fire_team == 1, "the role picked before joining reached the host: marksman, team B (%s, %d)" % [me.role, me.fire_team])
	await _check_late_drag()
	var gear: GearRig = me.get_node(^"Gear")
	check(gear.armor_integrity(&"plate_front") == 1.0 and gear.armor_integrity(&"helmet") == 1.0, "client built the worn voxel armor")
	for i in 3:
		me._server_fire.rpc_id(1, me.head.global_position, -me.global_basis.z, &"primary")
		await get_tree().create_timer(0.15).timeout
	await _wait_for(func() -> bool: return me.inventory.rounds_in(&"primary") == 27, 3.0)
	check(me.inventory.rounds_in(&"primary") == 27, "3 shots: host's ammo count replicated back (27)")
	# Feel round 2: the reload's phases come from the host (_reload_began: the weapon, the empty
	# flag, the length), so the third-person model plays the same keys here. Nothing begins it on
	# this side: the host's word alone must.
	me.is_reloading = true
	me._busy_until = Soldier._now() + me.reload_seconds(ItemDB.get_item(&"m4a1"), false)
	me._server_reload.rpc_id(1, &"primary")
	var phases := {"keys": false, "u": -1.0, "pose": false}
	await _wait_for(func() -> bool:
		phases.keys = phases.keys or (me.reload_item == &"m4a1" and not me.reload_empty and str(me.model.reload_keys) == str(Reloads.keys(Reloads.AR, false)))
		phases.u = maxf(phases.u, me.model.reload_u)
		phases.pose = phases.pose or not me.model.reload_pose().is_empty()
		return me.inventory.rounds_in(&"primary") == 30, 5.0)
	me.is_reloading = false  # (its physics, which would end it, is off here)
	check(me.inventory.rounds_in(&"primary") == 30 and me.inventory.spare_rounds(&"mag_556") == 57, "reload over the network (30 loaded, 57 spare)")
	check(phases.keys and phases.u > 0.5 and phases.pose,
		"its phases replicated: the M4's tactical keys from the host, played here (to %.2f), the rifle posed on them" % phases.u)
	var dry: Soldier = _combatant(DRAGGER)
	await _wait_for(func() -> bool: return dry != null and dry.inventory.rounds_in(&"primary") == 0, 8.0)
	check(dry != null and dry.inventory.rounds_in(&"primary") == 0 and dry.inventory.count_of(&"mag_556") == 1,
		"B-08: a rifle the host fires dry, a magazine picked up halfway, ends on 0 here too (%s left, counts %s)" % [
			dry.inventory.rounds_in(&"primary") if dry else -1, dry.inventory.net_ammo if dry else PackedInt32Array()])
	# The host's K-style trauma (40): 24% of blood lost and 0.4 pain, plus a fragment wound in
	# the left forearm, replicated in net_state.
	await _wait_for(func() -> bool: return me.vitals.pain() > 0.45, 3.0)
	var wounds := me.vitals.wound_list()
	check(absf(me.vitals.blood_fraction() - 0.76) < 0.02 and me.vitals.pain() > 0.45 and me.vitals.is_up() and me.vitals.condition_text() == "Bleeding"
		and not wounds.is_empty() and wounds[0].part == Vitals.FOREARM_L and wounds[0].kind == "muscle" and wounds[0].bleeding,
		"wound-model state replicated to the client (blood %.0f%%, pain %.2f, %s, %s)" % [me.vitals.blood_fraction() * 100.0, me.vitals.pain(), me.vitals.condition_text(), wounds])
	var tasks := me.vitals.care_needed()
	check(not tasks.is_empty() and tasks[0].item == &"pressure_bandage" and me.inventory.medical_count(&"pressure_bandage") == 2,
		"the client reads what it needs (%s) and that its IFAK holds 2 bandages" % [tasks])
	if not tasks.is_empty():
		me._server_treat.rpc_id(1, me.get_path(), tasks[0].item, tasks[0].part)  # rushed left at its default
		await _wait_for(func() -> bool: return me.vitals.is_healing(), 2.0)
		check(me.vitals.is_healing(), "the host started the treatment (replicated)")
		# action_net arrives on its own sync, possibly a frame or two after net_state.
		await _wait_for(func() -> bool: return me.model.action_shown() == CharacterModel.TREAT, 1.0)
		check(me.model.action_shown() == CharacterModel.TREAT, "and its animation: hands at the wound (replicated action_net)")
		await _wait_for(func() -> bool: return me.vitals.wound_list()[0].treated, 8.0)
		check(me.vitals.wound_list()[0].treated and not me.vitals.wound_list()[0].bleeding and not me.vitals.is_healing(), "a remote treatment through the host: bandaged after 5 s")
		await _wait_for(func() -> bool: return me.inventory.medical_count(&"pressure_bandage") == 1, 2.0)
		check(me.inventory.medical_count(&"pressure_bandage") == 1 and me.inventory.count_of(&"ifak") == 1, "drawn from the IFAK, which stays with one bandage left")
	# The medical model's hidden values reach the client too, so its checks and cues match.
	me._server_treat.rpc_id(1, me.get_path(), &"morphine", Vitals.TORSO)
	await _wait_for(func() -> bool: return me.vitals.morphine_level() > 0.2, 12.0)
	check(me.vitals.morphine_level() > 0.2 and me.inventory.count_of(&"morphine") == 0, "a morphine dose: the level in the blood replicates (%.2f)" % me.vitals.morphine_level())
	check(me.vitals.spo2() < WoundModel.SPO2_NORMAL and me.vitals.spo2() > WoundModel.SPO2_LABOURED and me.vitals.trauma_level() > 0.0 and me.vitals.why_unconscious().is_empty(),
		"SpO2 (%.1f%%, down a little with 24%% lost) and trauma (%.2f) replicate" % [me.vitals.spo2(), me.vitals.trauma_level()])
	me._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"helmet", &"")
	await _wait_for(func() -> bool: return me.inventory.slots[&"helmet"] == &"", 3.0)
	await _wait_for(func() -> bool: return _dropped_helmet() != null, 3.0)
	check(_dropped_helmet() != null, "dropped helmet spawned on the client")
	await _shoot_dropped_helmet(me)
	await _check_saved_body(me)
	await _check_looted_rifle(me)
	await _check_world_edits()
	me = await _check_rejoin_pickup(me)
	me = await _check_level_switches(me)
	if me == null:
		_finish()
		return
	# Knocked out, then gone: the host keeps this player's body (see _on_client_left).
	me._server_debug_hurt.rpc_id(1, 140.0)
	await _wait_for(func() -> bool: return me.vitals.downed, 3.0)
	check(me.vitals.downed, "knocked out before leaving (%s)" % me.vitals.condition_text())
	# Giving up (Captain, P0362): the host's player stands close by and he's only just down, so
	# not yet (the client reads it from replicated state), and the host refuses one asked early.
	await _wait_for(func() -> bool: return me.seconds_down() > 0.0, 1.0)
	check(me.help_near() and not me.can_give_up() and me.respawn_state == Soldier.RESPAWN_NONE,
		"down beside the host's player: no giving up yet (%.1f s down)" % me.seconds_down())
	me._server_give_up.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	check(me.vitals.downed and not me.vitals.is_dead(), "the host refuses a give-up asked too early: still down")
	_finish()


## The body from the host's zone save, seen by this late joiner, and looted over the network.
func _check_saved_body(me: Soldier) -> void:
	await _wait_for(func() -> bool: return level.bodies.get_child_count() > 0 and (level.bodies.get_child(0) as Soldier).inventory.slots[&"vest"] != &"", 3.0)
	var body: Soldier = level.bodies.get_child(0) if level.bodies.get_child_count() > 0 else null
	check(body != null and body.display_name() == "Player 9" and body.vitals.is_dead() and body.inventory.slots[&"vest"] == &"plate_carrier"
		and body.inventory.rounds_in(&"primary") == 21 and body.inventory.count_of(&"mag_556") == 3,
		"a body in the zone save is there for a late joiner, dead, with its gear (%s)" % [body.inventory.net_state if body else "none"])
	if body == null:
		return
	var marker := body.get_children().filter(func(n: Node) -> bool: return n is GearMarker)
	check(body.collision_layer == 0 and body.global_position.distance_to(Vector3(0, 0.1, 26.5)) < 0.5 and marker.size() == 1,
		"lying where it was saved, with its gear marker")
	me.global_position = body.global_position + Vector3(1.0, 0.0, 0.0)
	await get_tree().create_timer(0.4).timeout  # the host sees us there
	var mags := me.inventory.count_of(&"mag_556")
	me._server_loot_item.rpc_id(1, body.get_path(), &"vest", 0, &"mag_556")
	await _wait_for(func() -> bool: return body.inventory.count_of(&"mag_556") == 0, 3.0)
	check(body.inventory.count_of(&"mag_556") == 0 and me.inventory.count_of(&"mag_556") == mags + 3,
		"looting its magazines over the network moves them onto the looter (%d -> %d)" % [mags, me.inventory.count_of(&"mag_556")])


## An AI shot dead with its rifle shouldered and then looted over the network: on this client
## too, nothing of the rifle stays drawn on the body (Captain, P0164 queue 15).
func _check_looted_rifle(me: Soldier) -> void:
	var aimer: Soldier = _combatant(AIMER)
	await _wait_for(func() -> bool: return aimer != null and aimer.is_aiming and aimer.gear._held_key == &"primary", 3.0)
	check(aimer != null and aimer.is_aiming and aimer.gear._held_key == &"primary", "a hostile aims its rifle: shouldered here too")
	if aimer:
		var sent := int(aimer.inventory.net_gear.get("state", {}).get("slot_state", {}).get("primary", {}).get("rounds", -1))
		check(aimer.inventory.rounds_in(&"primary") == AIMER_ROUNDS and aimer.inventory.net_ammo.size() == Inventory.WEAPON_SLOTS.size() + 1
			and aimer.inventory.net_ammo[1] == AIMER_ROUNDS,
			"late join: the rounds it fired before we joined count here too (%d left; counts %s, snapshot %d)" % [aimer.inventory.rounds_in(&"primary"), aimer.inventory.net_ammo, sent])
	if aimer == null:
		return
	me.global_position = aimer.global_position + Vector3(0.0, 0.0, 2.5)
	await get_tree().create_timer(0.4).timeout  # the host sees us there
	for shot in 5:
		var head := CharacterModel.part_position(aimer, Vitals.HEAD)
		var eye := me.camera.global_position
		var direction := (head - eye).normalized()
		# Rounds leave the muzzle. At 2.5 m a parallel camera ray misses a head-sized
		# target; solve the barrel direction while retaining the real network fire RPC.
		for correction in 4:
			var muzzle := Soldier.muzzle_point(eye, direction, false, me.left_handed, me.is_aiming)
			direction = (head - muzzle).normalized()
		me._server_fire.rpc_id(1, eye, direction, &"primary")
		await _wait_for(func() -> bool: return aimer.vitals.is_dead(), 1.0)
		if aimer.vitals.is_dead():
			break
	check(aimer.vitals.is_dead() and not _rifle_drawn(aimer).is_empty(), "shot dead while aiming, its rifle still on the body (dead: %s)" % aimer.vitals.is_dead())
	await get_tree().create_timer(1.0).timeout  # it falls
	var chest := aimer.body_point()
	me.global_position = Vector3(chest.x + 0.8, AIMER_AT.y, chest.z)
	await get_tree().create_timer(0.4).timeout
	me._server_loot_item.rpc_id(1, aimer.get_path(), &"primary", -1, &"m4a1")
	await _wait_for(func() -> bool: return aimer.inventory.slots[&"primary"] == &"", 3.0)
	for i in 3:
		await get_tree().process_frame
	var left := _rifle_drawn(aimer)
	check(aimer.inventory.slots[&"primary"] == &"" and left.is_empty(),
		"looted over the network: nothing of the rifle stays drawn on the body here (%s)" % [left])


## The soldier named `callsign` (players and AI), or null.
func _combatant(callsign: String) -> Soldier:
	for node in get_tree().get_nodes_in_group(&"combatants"):
		if node is Soldier and String(node.name) == callsign:
			return node
	return null


## Where an M4's voxel model is drawn on `s` now (shown, not on its way out), as paths from `s`.
func _rifle_drawn(s: Soldier) -> Array[String]:
	var mesh := VoxelArt.mesh(VoxelArt.model_for(ItemDB.get_item(&"m4a1")), s.model.variant)
	var out: Array[String] = []
	for n: Node in s.find_children("*", "MeshInstance3D", true, false):
		var going := false
		var up := n
		while up != null and up != s:
			going = going or up.is_queued_for_deletion()
			up = up.get_parent()
		if (n as MeshInstance3D).mesh == mesh and (n as Node3D).is_visible_in_tree() and not going:
			out.append(String(s.get_path_to(n)))
	return out


## Armor on the ground is a target: a round the host resolves against the dropped helmet
## damages it, and the damage reaches this client's copy.
func _shoot_dropped_helmet(me: Soldier) -> void:
	var helmet := _dropped_helmet()
	if helmet == null:
		return
	await get_tree().create_timer(1.0).timeout  # settled on the host, synced here
	for attempt in 3:
		var eye := me.head.global_position
		me._server_fire.rpc_id(1, eye, (helmet.global_position - eye).normalized(), &"primary")
		await _wait_for(func() -> bool: return not helmet.state.get("chips", []).is_empty(), 1.0)
		if not helmet.state.get("chips", []).is_empty():
			break
	var piece: VoxelArmor = helmet.find_children("*", "VoxelArmor", false, false).front()
	check(helmet.state.get("chips", []).size() == 1 and piece and piece.voxels_removed() > 0,
		"a round into the dropped helmet damages it, and the client sees it (%d voxels)" % (piece.voxels_removed() if piece else -1))


## Impact marks and bullet holes reach the client: the saved ones in the edit log sent on
## join, the live one by RPC.
func _check_world_edits() -> void:
	var world := level.voxel_world
	var saved := Vector3(-2.95, 1.35, -4.0)
	await _wait_for(func() -> bool: return world.is_built() and world.marks_near(saved, 0.05) >= 1 and world.marks_near(LIVE_MARK, 0.05) >= 1, 10.0)
	# (The three shots fired earlier marked the perimeter wall too.)
	check(world.marks_near(saved, 0.05) == 1 and world.marks_near(LIVE_MARK, 0.05) == 1,
		"impact marks replicate: the saved one on the building and the host's live one (%d marks in all)" % world.mark_count())
	check(world.material_at(Vector3(17.55, 1.35, -7.05)) == VoxelWorld.Mat.EMPTY and world.material_at(Vector3(17.65, 1.35, -7.05)) == VoxelWorld.Mat.WOOD,
		"and the saved bullet hole in the shed wall")
	check(world.bullet_hole_count() >= 2 and world.material_at(Vector3(17.75, 1.35, -7.05)) == VoxelWorld.Mat.WOOD and world.holes_through(Vector3(17.75, 1.35, -7.05)) == 1,
		"and the saved calibre-sized one, in and out, the voxel still there (%d hole decals)" % world.bullet_hole_count())


## The drag the host staged before this client joined shows here: both poses from the
## replicated carry_net (the host-only carried_by and carrying never reach a client).
func _check_late_drag() -> void:
	await _wait_for(func() -> bool:
		var d: Soldier = _combatant(DRAGGED)
		return d != null and d.model.carry_shown().get("mode") == CharacterModel.DRAGGED, 3.0)
	var dragger: Soldier = _combatant(DRAGGER)
	var dragged: Soldier = _combatant(DRAGGED)
	check(dragger != null and dragged != null and dragger.model.carry_net.get("mode") == CharacterModel.DRAG
		and dragged.model.carry_shown().get("mode") == CharacterModel.DRAGGED and dragged.carried_by == null,
		"a late joiner sees a drag that started before it joined, from replicated state alone")
	if dragger == null or dragged == null:
		return
	await get_tree().create_timer(0.6).timeout
	var strap := dragged.model.torso.to_global(CharacterModel.STRAP_POINTS[0])
	check(dragger.model.hand_position(true).distance_to(strap) < 0.08 and dragged.model.torso.global_basis.z.dot(Vector3.UP) < -0.6,
		"drawn on the client: the casualty on its back, the dragger's hands on its straps")
	check(dragged.collision_layer == 0, "and the dragged body doesn't block (no collision) for a late joiner either (audit L2-02)")


## AI virtualization in co-op (docs/virtualization.md): a group the host holds as a profile isn't
## in this client's world at all (nothing replicated, late or not); brought back, its men are here
## like any AI, with what they had.
func _check_virtual() -> void:
	await get_tree().create_timer(1.0).timeout
	var none := VIRTUAL_MEN.all(func(n: String) -> bool: return level.ai.get_node_or_null(NodePath(n)) == null)
	check(none, "  a group the host holds virtual isn't here: nothing of it replicates")
	_host_wake_virtual.rpc_id(1)
	var here := func() -> bool:
		return VIRTUAL_MEN.all(func(n: String) -> bool:
			var s := level.ai.get_node_or_null(NodePath(n)) as Soldier
			return s != null and s.inventory.rounds_in(&"primary") == VIRTUAL_ROUNDS)
	await _wait_for(here, 8.0)
	check(here.call(), "  brought back by the host, both men are here with the rounds they had (%d)" % VIRTUAL_ROUNDS)


## B-07 (co-op soak S0520, S0578, S0672: a rejoined client "never saw" its dropped helmet
## picked up again): this client leaves on its feet and joins again (a new peer id; the host
## kits the new body), sees the helmet it dropped and shot before leaving, damage and all,
## then drops its new helmet and picks that one up again.
func _check_rejoin_pickup(me: Soldier) -> Soldier:
	print("Leaving and joining again (B-07)")
	var old_helmet := _dropped_helmet()
	var old_uid := old_helmet.uid if old_helmet else ""
	var old_id := multiplayer.get_unique_id()
	Net.leave()
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1")
	await _wait_for(func() -> bool: return multiplayer.get_unique_id() != old_id and 1 in multiplayer.get_peers(), 15.0)
	level = CompoundLevel.current(self)
	var found: Array = [null]
	await _wait_for(func() -> bool:
		found[0] = level.players.get_node_or_null(str(multiplayer.get_unique_id())) if level else null
		return found[0] != null and (found[0] as Soldier).inventory.slots[&"helmet"] == &"helmet", 15.0)
	me = found[0]
	check(me != null and multiplayer.get_unique_id() != old_id and me.inventory.slots[&"helmet"] == &"helmet",
		"left and joined again as a new peer (%d -> %d), kitted" % [old_id, multiplayer.get_unique_id()])
	if me == null:
		return null
	me.set_physics_process(false)
	await _wait_for(func() -> bool: return _item_by_uid(old_uid) != null, 5.0)
	var seen := _item_by_uid(old_uid)
	check(seen != null and seen.state.get("chips", []).size() == 1, "the helmet dropped before leaving lies here for the rejoined client, damage and all")
	var before := _helmets_in_world()
	me._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"helmet", &"")
	var dropped: Array = [null]
	await _wait_for(func() -> bool:
		for item: WorldItem in _helmets_in_world():
			if not item in before:
				dropped[0] = item
		return dropped[0] != null and me.inventory.slots[&"helmet"] == &"", 5.0)
	var helmet: WorldItem = dropped[0]
	check(helmet != null and me.inventory.slots[&"helmet"] == &"", "dropped its helmet: off its head, on the ground here")
	if helmet == null:
		return me
	me.global_position = helmet.global_position + Vector3(0.6, 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout  # the host sees us there
	var uid := helmet.uid
	me._server_interact.rpc_id(1, helmet.get_path())
	await _wait_for(func() -> bool: return me.inventory.slots[&"helmet"] == &"helmet" and _item_by_uid(uid) == null, 5.0)
	check(me.inventory.slots[&"helmet"] == &"helmet" and _item_by_uid(uid) == null, "picked it up again: on its head, gone from the ground, here too")
	return me


func _helmets_in_world() -> Array:
	return get_tree().get_nodes_in_group(&"world_items").filter(func(n: Node) -> bool:
		return n is WorldItem and n.item_id == &"helmet" and not n.is_queued_for_deletion())


func _item_by_uid(uid: String) -> WorldItem:
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node is WorldItem and node.uid == uid and not node.is_queued_for_deletion():
			return node
	return null


## B-04 (every co-op soak: after each switch between the base and a zone, clients saw other
## players at (0, 0, 0), no objectives and half the world items for 5-15 s, and logged a burst
## of "on_despawn_receive ... ERR_UNAUTHORIZED"): the host switches compound -> zone ->
## compound. Each time: the host's despawns of the old level came before the switch (nothing
## the host spawned is left in the old level as this client swaps); a loading screen until the
## host's "all sent"; then every player the host had, where the host had them, and as many
## world items and bodies; a player whose owner isn't here at its spawn, not the origin.
## Returns this client's player in the last level.
func _check_level_switches(me: Soldier) -> Soldier:
	for kind: String in ["zone", "compound"]:
		var old := level
		var at_swap := {}
		var at_synced := {}
		var on_swap := func(_fresh: CompoundLevel) -> void:
			at_swap["left"] = _replicated_in(old)
			at_swap["loading"] = BaseHub.loading()
		var on_synced := func(summary: Dictionary) -> void:
			var lvl := CompoundLevel.current(self)
			var players := {}
			for p: Node in lvl.players.get_children():
				if p is Soldier and not p.is_queued_for_deletion():
					players[String(p.name)] = (p as Soldier).position
			var live := func(n: Node) -> bool: return not n.is_queued_for_deletion()
			at_synced["summary"] = summary
			at_synced["players"] = players
			at_synced["items"] = lvl.items.get_children().filter(live).size()
			at_synced["bodies"] = lvl.bodies.get_children().filter(live).size()
			at_synced["loading"] = BaseHub.loading()
		BaseHub.level_switched.connect(on_swap, CONNECT_ONE_SHOT)
		BaseHub.level_synced.connect(on_synced, CONNECT_ONE_SHOT)
		_ghost_pos = null
		_host_switch.rpc_id(1, kind)
		await _wait_for(func() -> bool: return not at_synced.is_empty() and _ghost_pos != null, 40.0)
		if BaseHub.level_switched.is_connected(on_swap):
			BaseHub.level_switched.disconnect(on_swap)
		if BaseHub.level_synced.is_connected(on_synced):
			BaseHub.level_synced.disconnect(on_synced)
		level = CompoundLevel.current(self)
		print("Level switch to the %s (B-04)" % kind)
		check(not at_swap.is_empty() and int(at_swap.left) == 0 and bool(at_swap.loading),
			"  the old level's replicated nodes were despawned before the swap (%s left), and the loading screen is up" % [at_swap.get("left", "?")])
		check(not at_synced.is_empty() and String(at_synced.summary.get("level", "")) == kind and not bool(at_synced.loading),
			"  the host's \"all sent\" came and the loading screen went (%s)" % [at_synced.get("summary", {}).get("level", "nothing")])
		if at_synced.is_empty():
			return null
		var off := []
		var host_players: Dictionary = at_synced.summary.players
		for pname: String in host_players:
			var p: Array = host_players[pname]
			var host_at := Vector3(float(p[0]), float(p[1]), float(p[2]))
			if not at_synced.players.has(pname) or (at_synced.players[pname] as Vector3).distance_to(host_at) > 1.0:
				off.append("%s: host %s, here %s" % [pname, host_at, at_synced.players.get(pname, "missing")])
		check(off.is_empty() and host_players.size() == at_synced.players.size(),
			"  every player the host had is here, where the host had them (%d; %s)" % [host_players.size(), off])
		check(int(at_synced.items) == int(at_synced.summary.items) and int(at_synced.bodies) == int(at_synced.summary.bodies) and int(at_synced.summary.items) > 0,
			"  as many world items (%d of %d) and bodies (%d of %d) as the host had" % [int(at_synced.items), int(at_synced.summary.items), int(at_synced.bodies), int(at_synced.summary.bodies)])
		var found: Array = [null]
		await _wait_for(func() -> bool:
			found[0] = level.players.get_node_or_null(str(GHOST))
			return found[0] != null, 5.0)
		var ghost := found[0] as Soldier
		check(ghost != null and _ghost_pos != null and ghost.position.distance_to(_ghost_pos) < 0.05,
			"  a player whose owner sends no position stands where the host put it, not at the origin (%s, host %s)" % [ghost.position if ghost else "missing", _ghost_pos])
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		if kind == "zone":
			await _check_virtual()
	if me:
		me.set_physics_process(false)
		var mine := me
		await _wait_for(func() -> bool: return mine.inventory.slots[&"primary"] == &"m4a1", 5.0)
	return me


## Nodes the host spawned that are still in `lvl` here (players, AI, bodies, world items).
func _replicated_in(lvl: Node) -> int:
	if not is_instance_valid(lvl):
		return 0
	var n := 0
	for holder: String in ["Players", "AI", "Bodies", "Items"]:
		var at := lvl.get_node_or_null(NodePath(holder))
		if at:
			n += at.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()
	return n


func _dropped_helmet() -> WorldItem:
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node.item_id == &"helmet" and node.uid.begins_with("test_net"):
			return node
	return null


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _finish() -> void:
	# Audit A1-06: the client shares the host's user data but never touches the host's saves.
	check(FileAccess.file_exists(GameState.save_path()), "the host's zone save is still there: the client never deleted it")
	if _errors:
		OS.remove_logger(_errors)
		check(_errors.count("recv_nodes") == 0 and _errors.count("unknown peer") == 0,
			"no despawn for a node this client didn't have (ERR_UNAUTHORIZED: %d) and no RPC to a missing peer (%d) all session"
			% [_errors.count("recv_nodes"), _errors.count("unknown peer")])
		print("  (sync deltas ignored for a missing synchronizer: %d)" % _errors.count("Ignoring delta"))
	print("NET TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)
