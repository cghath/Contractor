extends Node
## Headless checks for people on the map (wave 4, W11): civilians, HVTs, intel, the radio
## report and surrender, on a real hosted session; then a second process joins over ENet and
## checks that all of it reached it (late join) and that a live change does too.
##   <voxel godot exe> --headless --path . res://tests/people_test.tscn
## The host starts the client itself (same scene, "-- --join 127.0.0.1"); the client sends
## its results back by RPC. Exits with the number of failures.

const CIVILIAN := "civilian"
## Where the client's checks come from (host -> client, on join).
var expect: Dictionary = {}
var failures := 0
var level: CompoundLevel
var layer: PeopleLayer
var player: Soldier
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_live := false
var _listener: Listener


## Counts the engine's errors whose text has `match` in it (RPCs to a peer that isn't there).
class ErrorCount extends Logger:
	var match := ""
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if match in code or match in rationale:
			count += 1


## A mission listener (People.LISTENER_GROUP), as the economy would add.
class Listener extends Node:
	var casualties: Array = []
	var intel: Array = []
	var deliveries: Array = []

	func _ready() -> void:
		add_to_group(&"mission_listeners")

	func on_civilian_casualty(event: Dictionary) -> void:
		casualties.append(event)

	func on_intel_banked(entry: Dictionary) -> void:
		intel.append(entry)

	func on_hvt_delivered(event: Dictionary) -> void:
		deliveries.append(event)


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_people" + tag  # never touch a real save
	Campaign.campaign_id = "test_people" + tag
	CompoundLevel.spawn_ai = false  # we place everyone by hand
	PeopleLayer.populate = false
	PeopleLayer.surrender_enabled = false
	if "--people-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	Campaign.reset_campaign()
	People.reset_all()
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("PEOPLE TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	layer = level.people
	while not level.voxel_world.is_built() or level.get_node_or_null(^"Navigation") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1"]:
		player.inventory.take(id)
	player.inventory.take(&"mag_556", 3)
	_listener = Listener.new()
	add_child(_listener)
	await _frames(5)
	_test_setup()
	await _test_civilians_ignored_by_hostiles()
	await _test_civilians_flee_gunfire()
	await _test_casualties()
	await _test_fire_discipline()
	await _test_hostile_hvt()
	await _test_friendly_hvt()
	await _test_intel()
	await _test_radio_report()
	await _test_surrender()
	await _test_scavenge_intel()
	await _test_escort()
	await _test_escort_two_medics()
	await _test_ride_with_leader()
	await _test_carried_owner_gone()
	await _test_client()
	await _test_compound_content()
	await _test_blast_casualty()
	GameState.delete_save()
	Campaign.reset_campaign()
	print("PEOPLE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Host checks ---------------------------------------------------------------------------

func _test_setup() -> void:
	print("Setup")
	check(layer != null and layer.name == "People" and PeopleLayer.find(player) == layer, "the level has its people layer")
	var officer: Dictionary = CompoundLevel.HOSTILES[0]
	check(officer.get("rank") == "officer" and "intel_phone" in officer.get("intel", []), "the compound's officer carries intel (hostile data)")
	for id: StringName in [&"zip_cuffs", &"intel_laptop", &"intel_phone", &"intel_documents"]:
		check(ItemDB.has_item(id), "item %s exists" % id)
	check(ItemDB.get_item(&"intel_laptop").type == "intel" and int(ItemDB.get_item(&"intel_laptop").stats.intel_value) > 0, "intel items are type intel, with a value")


## Hostile AI never targets a civilian, even right in front of it.
func _test_civilians_ignored_by_hostiles() -> void:
	print("Hostiles ignore civilians")
	_place(player, Vector3(40, 0.1, 40))  # out of everyone's sight
	var civ := _person({"name": "CivNear", "kind": CIVILIAN, "pos": Vector3(-6, 0.1, 10)})
	_brain(civ).process_mode = Node.PROCESS_MODE_DISABLED
	var hostile := _soldier("HostA", &"hostile", Vector3(-6, 0.1, 4), ["m4a1", "mag_556"], true)
	hostile.rotation.y = PI  # facing the civilian (+z)
	var rounds := hostile.inventory.rounds_in(&"primary")
	await _seconds(3.0)
	check(Person.is_noncombatant(civ) and Person.is_civilian(civ) and civ.faction == Person.FACTION, "a civilian is a non-combatant in the civilian faction")
	check(SquadAI.of(hostile).target == null and civ.vitals.injury() == 0.0 and hostile.inventory.rounds_in(&"primary") == rounds,
		"a hostile with a civilian in plain sight doesn't target or shoot them")
	hostile.queue_free()
	civ.queue_free()
	await _frames(2)


## Civilians walk their routine, run from gunfire to a spot hidden from it and cower there;
## they carry no weapon and have no fighting brain.
func _test_civilians_flee_gunfire() -> void:
	print("Civilians flee gunfire")
	var routine := [Vector3(-10, 0, 13), Vector3(-4, 0, 13)]
	var civ := _person({"name": "CivWalker", "kind": CIVILIAN, "pos": Vector3(-10, 0.1, 13), "routine": routine})
	var start := civ.global_position
	await _wait_until(func() -> bool: return _flat(civ.global_position, start) > 1.5, 12.0)
	check(_flat(civ.global_position, start) > 1.5 and _brain(civ).mode == CivilianAI.Mode.ROUTINE, "walks the routine (%.1f m)" % _flat(civ.global_position, start))
	check(civ.inventory.slots[&"primary"] == &"" and civ.inventory.slots[&"sidearm"] == &"" and SquadAI.of(civ) == null and _brain(civ) != null,
		"no weapon and no fighting brain (CivilianAI only)")
	_place(player, Vector3(2, 0.1, 16))
	player.rotation.y = 0.0
	var origin := player.camera.global_position
	for i in 3:
		player._server_fire.rpc_id(1, origin, Vector3(0, 0.3, -1).normalized(), &"primary")
		await _seconds(0.2)
	await _wait_until(func() -> bool: return _brain(civ).mode == CivilianAI.Mode.COWER, 10.0)
	var brain := _brain(civ)
	check(brain.threatened() and brain.threat_pos.distance_to(origin) < 0.5, "hears the shots and knows where from")
	check(brain.mode == CivilianAI.Mode.COWER and brain._hides_from(civ.global_position, origin),
		"ran to a spot the shooter can't see and cowers there (%s, at %s)" % [CivilianAI.Mode.keys()[brain.mode], civ.global_position])
	await _frames(10)
	check(civ.movement.stance <= SoldierMovement.Stance.CROUCH_MID, "crouched low (stance %d)" % civ.movement.stance)
	check(not layer.said.is_empty(), "and someone shouted (%s)" % [layer.said.back() if not layer.said.is_empty() else "nothing"])
	civ.queue_free()
	await _frames(2)


## Only casualties from our side count: a squad AI's round, a player's round, a player's
## grenade; a hostile's round doesn't. Each civilian once wounded, once killed.
func _test_casualties() -> void:
	print("Civilian casualties")
	_place(player, Vector3(0, 0.1, 40))
	var victim := _person({"name": "CivByAI", "kind": CIVILIAN, "pos": Vector3(10, 0.1, 32)})
	var by_hostile := _person({"name": "CivByHostile", "kind": CIVILIAN, "pos": Vector3(-10, 0.1, 32)})
	for c: Soldier in [victim, by_hostile]:
		_brain(c).process_mode = Node.PROCESS_MODE_DISABLED
	var alpha := _soldier("Alpha", &"friendly", Vector3(10, 0.1, 27), ["m4a1", "mag_556"], false)
	var hostile := _soldier("HostB", &"hostile", Vector3(-10, 0.1, 27), ["m4a1", "mag_556"], false)
	await _frames(3)
	_shoot(alpha, victim)
	_shoot(hostile, by_hostile)
	await _frames(3)
	var events := People.casualties.filter(func(e: Dictionary) -> bool: return e.civilian == victim.display_name())
	check(victim.vitals.injury() > 0.0 and events.size() == 1 and events[0].kind == People.WOUNDED and events[0].shooter == "Alpha"
		and events[0].shooter_faction == "friendly" and not events[0].shooter_player,
		"a civilian hit by a squad AI is a casualty, with the shooter (%s)" % [events])
	check(by_hostile.vitals.injury() > 0.0 and not People.casualties.any(func(e: Dictionary) -> bool: return e.civilian == by_hostile.display_name()),
		"one hit by a hostile isn't")
	check(_listener.casualties.size() == 1 and String(Harm.last(by_hostile).get("faction", "")) == "hostile", "the listener heard of it; the hostile's hit is noted as his")
	# Captain, 2026-10-19: only the company's hits count, never an allied element's or a rebel's.
	var ally := _soldier("AllyC", &"friendly", Vector3(20, 0.1, 27), ["m4a1", "mag_556"], false)
	ally.iff = &"allied"
	var by_ally := _person({"name": "CivByAlly", "kind": CIVILIAN, "pos": Vector3(20, 0.1, 32)})
	_brain(by_ally).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	check(Harm.is_company(alpha) and Harm.is_company(player) and not Harm.is_company(ally) and not Harm.is_company(hostile),
		"the company is the players and our own squad, not an allied element or the enemy")
	_shoot(ally, by_ally)
	await _frames(3)
	check(by_ally.vitals.injury() > 0.0 and not People.casualties.any(func(e: Dictionary) -> bool: return e.civilian == by_ally.display_name()),
		"one hit by an allied element isn't the company's casualty either")
	by_ally.vitals.server_kill()
	await _frames(2)
	check(not People.casualties.any(func(e: Dictionary) -> bool: return e.civilian == by_ally.display_name()), "nor when he dies of it")
	ally.queue_free()
	victim.vitals.server_kill()
	by_hostile.vitals.server_kill()
	await _frames(3)
	var killed := People.casualties.filter(func(e: Dictionary) -> bool: return e.kind == People.KILLED)
	check(killed.size() == 1 and killed[0].civilian == victim.display_name() and killed[0].shooter == "Alpha",
		"dying after our hit adds a killed event; dying after a hostile's doesn't (%d killed)" % killed.size())
	var by_player := _person({"name": "CivByPlayer", "kind": CIVILIAN, "pos": Vector3(0, 0.1, 46)})
	_brain(by_player).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	_place(player, Vector3(0, 0.1, 40))
	var eye := player.camera.global_position
	player._server_fire.rpc_id(1, eye, (by_player.aim_point() - eye).normalized(), &"primary")
	await _frames(3)
	var mine := People.casualties.filter(func(e: Dictionary) -> bool: return e.civilian == by_player.display_name())
	check(mine.size() == 1 and mine[0].shooter_player and mine[0].shooter_peer == 1 and mine[0].shooter == "Player 1",
		"a player's round: the casualty names the player and their peer (%s)" % [mine])
	var by_frag := _person({"name": "CivByFrag", "kind": CIVILIAN, "pos": Vector3(-20, 0.1, 46)})
	_brain(by_frag).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	level.server_throw(&"frag_grenade", by_frag.global_position + Vector3(0.6, 0.3, 0.0), Vector3.ZERO, player)
	await _wait_until(func() -> bool: return by_frag.vitals.injury() > 0.0, 6.0)
	await _frames(3)
	var frag := People.casualties.filter(func(e: Dictionary) -> bool: return e.civilian == by_frag.display_name())
	check(not frag.is_empty() and frag[0].shooter == "Player 1", "a player's grenade counts against the thrower (%s)" % [frag])
	check(People.casualty_count() == 3 and People.summary().civilian_casualties == 3 and not People.summary().contract_voided,
		"three different civilians count (%d)" % People.casualty_count())
	check(frag.filter(func(e: Dictionary) -> bool: return e.kind == People.WOUNDED).size() == 1,
		"blast and fragments together: still one wounded event for that civilian (%d)" % frag.size())
	alpha.queue_free()
	hostile.queue_free()
	await _frames(2)


## Audit A3-02: a grenade's blast alone. A wall stops every fragment, but the overpressure
## burns the civilian behind it: still the thrower's casualty, wounded and then killed. (Last,
## after the client has come and gone: kept out of the replication checks' way.)
func _test_blast_casualty() -> void:
	print("A civilian hurt by a grenade's blast alone")
	for n in level.ai.get_children():  # the compound's people hold still: no stray rounds
		if n is Soldier and SquadAI.of(n):
			SquadAI.of(n).process_mode = Node.PROCESS_MODE_DISABLED
	_place(player, Vector3(0, 0.1, 40))
	var by_blast := _person({"name": "CivByBlast", "kind": CIVILIAN, "pos": Vector3(-20, 0.1, 54)})
	_brain(by_blast).process_mode = Node.PROCESS_MODE_DISABLED
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	(wall_shape.shape as BoxShape3D).size = Vector3(0.2, 5.0, 5.0)
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = by_blast.global_position + Vector3(0.6, 1.4, 0.0)
	await _frames(3)
	level.server_throw(&"frag_grenade", by_blast.global_position + Vector3(1.0, 0.2, 0.0), Vector3.ZERO, player)
	await _wait_until(func() -> bool: return by_blast.vitals.injury() > 0.0 or by_blast.vitals._model.burn > 0.0, 6.0)
	await _frames(3)
	var blast := People.casualties.filter(func(e: Dictionary) -> bool: return e.civilian == by_blast.display_name())
	# The fragments come after the blast: had one got through, it would be the last cause. (The
	# blast itself may break his pelvis: a wound, but the blast's.)
	var cause := String(by_blast.vitals.last_cause.get("cause", ""))
	check(by_blast.vitals._model.burn > 0.0 and cause == "blast",
		"behind a wall: burned by the blast, no fragment got through (burns %.2f, last cause %s, %d wounds)" % [by_blast.vitals._model.burn, cause, by_blast.vitals.wound_list().size()])
	check(blast.size() == 1 and blast[0].kind == People.WOUNDED and blast[0].shooter == "Player 1" and String(Harm.last(by_blast).get("faction", "")) == "friendly",
		"a blast-only injury counts against the thrower too (%s)" % [blast])
	wall.queue_free()  # out of the way before the body falls
	await _frames(3)
	by_blast.vitals.server_kill()
	await _frames(3)
	var blast_killed := People.casualties.filter(func(e: Dictionary) -> bool: return e.civilian == by_blast.display_name() and e.kind == People.KILLED)
	check(blast_killed.size() == 1 and blast_killed[0].shooter == "Player 1", "and dying of it later names the thrower (%s)" % [blast_killed])
	await _frames(2)


## Squad AI holds fire while a civilian stands between it and its target, and fires once the
## line is clear.
func _test_fire_discipline() -> void:
	print("Fire discipline")
	_place(player, Vector3(-40, 0.1, 40))
	var bravo := _soldier("Bravo", &"friendly", Vector3(20, 0.1, 40), ["m4a1", "mag_556", "mag_556"], true)
	bravo.rotation.y = PI  # facing +z
	var target := _soldier("Target1", &"hostile", Vector3(20, 0.1, 54), [], false)
	var shield := _person({"name": "CivShield", "kind": CIVILIAN, "pos": Vector3(20, 0.1, 47)})
	_brain(shield).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)  # the brain sets itself up first
	SquadAI.of(bravo).on_order(Squad.Order.HOLD, bravo.global_position)
	var rounds := bravo.inventory.rounds_in(&"primary")
	await _seconds(4.0)
	var ai := SquadAI.of(bravo)
	check(ai.target == target and ai._friendly_in_line(target.aim_point()), "Bravo has the hostile as his target, with the civilian in the line of fire")
	check(bravo.inventory.rounds_in(&"primary") == rounds and shield.vitals.injury() == 0.0 and target.vitals.injury() == 0.0,
		"and doesn't shoot through the civilian (%d rounds left)" % bravo.inventory.rounds_in(&"primary"))
	_place(shield, Vector3(25, 0.1, 47))
	await _wait_until(func() -> bool: return bravo.inventory.rounds_in(&"primary") < rounds, 6.0)
	check(bravo.inventory.rounds_in(&"primary") < rounds, "with the line clear, he fires (%d rounds left)" % bravo.inventory.rounds_in(&"primary"))
	bravo.queue_free()
	target.queue_free()
	shield.queue_free()
	await _frames(2)


## A hostile HVT spots the squad, shouts, gives it away to his men and runs to them; can only
## be cuffed from behind; cuffed, he can be carried and follows when led; brought to an
## extraction point he's delivered (the objective hook).
func _test_hostile_hvt() -> void:
	print("Hostile HVT")
	_place(player, Vector3(35, 0.1, 50))
	var guard1 := _soldier("Guard1", &"hostile", Vector3(35, 0.1, -15), ["m4a1"], false)
	var guard2 := _soldier("Guard2", &"hostile", Vector3(37, 0.1, -16), ["m4a1"], false)
	var hvt := _person({"name": "HvtTestCommander", "kind": "hvt", "side": "hostile", "hvt_id": "hvt_test_commander",
		"label": "HVT (the Commander)", "pos": Vector3(35, 0.1, 0), "rot_y": PI, "intel": ["intel_phone"]})
	var brain := _brain(hvt) as HvtAI
	check(brain != null and Person.is_hvt(hvt) and Person.side_of(hvt) == Person.HOSTILE and Person.cuffable(hvt), "a hostile HVT, cuffable")
	check(hvt.inventory.count_of(&"intel_phone") == 1, "carrying intel")
	await _seconds(1.0)
	var before := Soldier._now()
	_place(player, Vector3(35, 0.1, 15))  # in front of him, in sight
	await _wait_until(func() -> bool: return brain.shouts > 0, 4.0)
	check(brain.shouts > 0 and layer.said.any(func(l: Dictionary) -> bool: return l.speaker == hvt.display_name()), "he spots the squad and shouts")
	check(guard1.threat_time >= before and guard1.threat_pos.distance_to(player.global_position) < 2.0 and guard2.threat_time >= before,
		"his men learn where the squad is (exposed)")
	await _wait_until(func() -> bool: return hvt.global_position.distance_to(guard1.global_position) < 4.5, 12.0)
	check(hvt.global_position.distance_to(guard1.global_position) < 4.5, "and he runs to them (%.1f m from Guard1)" % hvt.global_position.distance_to(guard1.global_position))
	await _wait_until(func() -> bool: return brain.mode == CivilianAI.Mode.COWER, 4.0)
	await _seconds(0.5)
	player.inventory.take(Person.ZIP_CUFFS, 3)
	# In front of him: he sees it coming.
	var facing := -hvt.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	_place(player, hvt.global_position + facing * 1.8)
	check(Person.cuff_problem(player, hvt).contains("behind"), "from the front: no (%s)" % Person.cuff_problem(player, hvt))
	check(_ids(player, hvt).has(&"cuff") and _action(player, hvt, &"cuff").disabled != "", "the menu shows Zip-cuff greyed out")
	# From behind.
	facing = -hvt.global_basis.z
	facing.y = 0.0
	_place(player, hvt.global_position - facing.normalized() * 1.8)
	await _frames(2)
	check(Person.cuff_problem(player, hvt) == "", "from behind: yes")
	InteractionMenu.perform(player, _action(player, hvt, &"cuff"))
	await _wait_until(func() -> bool: return Person.is_cuffed(hvt), 6.0)
	check(Person.is_cuffed(hvt) and player.inventory.count_of(Person.ZIP_CUFFS) == 2, "cuffed after the zip cuff's time, one zip cuff used")
	check(Person.is_noncombatant(hvt) and hvt.carriable_while_up and not _ids(player, hvt).has(&"cuff"), "cuffed: a captive, carriable, no more Zip-cuff in the menu")
	guard1.queue_free()
	guard2.queue_free()
	await _frames(2)
	# Carried, and put down.
	player._server_carry_body.rpc_id(1, hvt.get_path())
	await _frames(3)
	_end_carry_phase(player)  # up on the shoulder (the host counts it down in the player's physics, off here)
	check(player.carrying == hvt and hvt.carried_by == player, "a cuffed HVT can be carried")
	var on_shoulder := _ids(player, hvt)
	check(not on_shoulder.is_empty() and on_shoulder[0] == &"put_down" and not &"lead" in on_shoulder and not &"cover" in on_shoulder,
		"carrying him, his menu has Put down first and no orders (%s)" % [on_shoulder])
	player._server_release_body.rpc_id(1)
	await _frames(3)
	_end_carry_phase(player)  # lowered off the shoulder
	check(player.carrying == null and hvt.carried_by == null and hvt.vitals.is_up(), "and put down again, still conscious")
	# Carried off and put down somewhere else, he stays there (Captain, 2026-10-14: he walked back
	# to where he was picked up).
	var picked_at := hvt.global_position
	player._server_carry_body.rpc_id(1, hvt.get_path())
	await _frames(3)
	_end_carry_phase(player)
	_place(player, player.global_position + Vector3(6, 0, 0))
	await _frames(2)
	player._server_release_body.rpc_id(1)
	await _frames(3)
	_end_carry_phase(player)
	var set_down := hvt.global_position
	await _seconds(5.0)
	check(hvt.carried_by == null and _flat(set_down, picked_at) > 4.0 and _flat(hvt.global_position, set_down) < 0.6,
		"carried %.1f m and put down, he stays where he's set down (%.2f m off it)" % [_flat(set_down, picked_at), _flat(hvt.global_position, set_down)])
	# Seated in a vehicle and unloaded somewhere else, he stays where he got out.
	var car := Node3D.new()
	car.name = "HoldTestCar"
	level.add_child(car)
	check(layer.server_seat_in_vehicle(hvt, car, "1"), "seated in a vehicle")
	await _seconds(0.6)
	_place(hvt, hvt.global_position + Vector3(0, 0, 5))  # driven off: the vehicle's exit spot
	layer.server_unseat(hvt)
	var got_out := hvt.global_position
	await _seconds(2.5)
	check(String(Person.state(hvt).get("seated_in", "")) == "" and _flat(hvt.global_position, got_out) < 0.6,
		"unloaded from the vehicle, he stays where he got out (%.2f m off it)" % _flat(hvt.global_position, got_out))
	car.queue_free()
	_place(player, hvt.global_position - Vector3(0, 0, 1.8))
	await _frames(2)
	# Led.
	InteractionMenu.perform(player, _action(player, hvt, &"lead"))
	await _frames(3)
	check(String(Person.state(hvt).get("led_by", "")) == "Players/1" and Person.state(hvt).get("order") == "follow", "Follow me: he's led by the player")
	check(not _ids(player, hvt).has(&"lead") and _ids(player, hvt).has(&"stop"), "following you: Stop, no Follow me again (%s)" % [_ids(player, hvt)])
	var point := layer.server_add_point(Vector3(35, 0, 22), 4.0, "Test extraction", "TestExtraction")
	for step in 20:
		if _flat(player.global_position, Vector3(35, 0, 22)) < 0.5:
			break
		_place(player, player.global_position.move_toward(Vector3(35, 0.1, 22), 2.5))
		await _seconds(0.6)
	await _wait_until(func() -> bool: return People.is_delivered("hvt_test_commander"), 8.0)
	check(_flat(hvt.global_position, player.global_position) < 4.5, "he follows the player (%.1f m behind)" % _flat(hvt.global_position, player.global_position))
	check(People.is_delivered("hvt_test_commander") and _listener.deliveries.size() == 1 and _listener.deliveries[0].hvt_id == "hvt_test_commander"
		and _listener.deliveries[0].cuffed and _listener.deliveries[0].by == "Player 1",
		"brought into the extraction point: delivered, the objective hook fires (%s)" % [_listener.deliveries])
	check(bool(Person.state(hvt).get("delivered", false)) and point.is_in_group(DeliveryPoint.GROUP), "he's marked delivered and waits there")
	# A hostile HVT shot down can be cuffed from any side.
	var downed := _person({"name": "HvtTestDowned", "kind": "hvt", "side": "hostile", "hvt_id": "hvt_test_downed", "pos": Vector3(45, 0.1, 30), "rot_y": PI})
	await _frames(3)
	downed.vitals.server_damage(70.0)  # 42% of blood lost: out at once
	await _wait_until(func() -> bool: return not downed.vitals.is_up(), 3.0)
	_place(player, downed.global_position + Vector3(0, 0, 1.5))
	await _frames(2)
	check(not downed.vitals.is_up() and not downed.vitals.is_dead() and Person.cuff_problem(player, downed) == "" and _ids(player, downed).has(&"cuff"),
		"a downed hostile HVT can be cuffed from the front (the menu offers it on the body)")
	check(InteractionMenu.has_regions(player, downed) and InteractionMenu.general_actions(player, downed).any(func(a: Dictionary) -> bool: return a.id == &"cuff"),
		"on his waist point")
	InteractionMenu.perform(player, _action(player, downed, &"cuff"))
	await _wait_until(func() -> bool: return Person.is_cuffed(downed), 6.0)
	check(Person.is_cuffed(downed), "and is")


## A friendly HVT follows when told, stops, and gets in cover.
func _test_friendly_hvt() -> void:
	print("Friendly HVT")
	var hvt := _person({"name": "HvtTestEngineer", "kind": "hvt", "side": "friendly", "hvt_id": "hvt_test_engineer",
		"label": "HVT (the Engineer)", "pos": Vector3(-35, 0.1, 0)})
	_place(player, Vector3(-35, 0.1, 2))
	await _frames(3)
	check(Person.leadable(hvt) and not Person.cuffable(hvt) and _ids(player, hvt).has(&"lead") and not _ids(player, hvt).has(&"cuff"),
		"leadable, not cuffable")
	var general := InteractionMenu.general_actions(player, hvt).map(func(a: Dictionary) -> StringName: return a.id)
	check(InteractionMenu.has_regions(player, hvt) and &"lead" in general and &"cover" in general and not &"treat" in general,
		"his body points: the people actions on the waist point, treatment on the regions (%s)" % [general])
	InteractionMenu.perform(player, _action(player, hvt, &"lead"))
	for step in 6:
		_place(player, player.global_position + Vector3(0, 0, 2))
		await _seconds(0.6)
	await _seconds(2.0)
	check(_flat(hvt.global_position, player.global_position) < 4.0, "follows the player (%.1f m behind)" % _flat(hvt.global_position, player.global_position))
	InteractionMenu.perform(player, _action(player, hvt, &"stop"))
	await _frames(3)
	var held := hvt.global_position
	_place(player, player.global_position + Vector3(0, 0, 10))
	await _seconds(2.0)
	check(Person.state(hvt).get("order") == "stop" and _flat(hvt.global_position, held) < 1.0, "Stop: stays put while the player walks off")
	_place(player, hvt.global_position + Vector3(1.5, 0, 0))
	InteractionMenu.perform(player, _action(player, hvt, &"cover"))
	PeopleLayer.server_noise(player, hvt.global_position + Vector3(0, 0, -20))
	await _seconds(2.0)
	check(_brain(hvt).mode == CivilianAI.Mode.COVER and hvt.movement.stance <= SoldierMovement.Stance.CROUCH_MID, "Get in cover: down in cover")
	check(not _ids(player, hvt).has(&"cover") and _ids(player, hvt).has(&"lead"), "in cover: Follow me, no Get in cover again (%s)" % [_ids(player, hvt)])


## Intel from an officer's body and a placed laptop, carried out to an extraction point.
func _test_intel() -> void:
	print("Intel")
	var officer := _soldier("Officer", &"hostile", Vector3(25, 0.1, -30), CompoundLevel.HOSTILE_LOADOUT, false)
	check(layer.server_give_intel(officer, &"intel_documents", "officer"), "an officer carries documents")
	officer.vitals.server_kill()
	await _frames(3)
	_place(player, officer.global_position + Vector3(1.0, 0, 0))
	await _frames(2)
	var where := _where(officer, &"intel_documents")
	player._server_loot_item.rpc_id(1, officer.get_path(), where[0], where[1], &"intel_documents")
	await _frames(3)
	check(player.inventory.count_of(&"intel_documents") == 1, "looted from his body")
	check(_into_pouch(player, &"intel_documents"), "and moved into a pouch on the player's carrier")
	layer.server_place_intel(&"intel_laptop", Vector3(25, 0.5, -26), "test outpost", "test_people_laptop")
	await _frames(3)
	var laptop := _world_item("test_people_laptop")
	check(laptop != null and String(laptop.state.get("intel_id", "")) != "" and laptop.state.get("source") == "test outpost", "a laptop placed at an outpost, with its intel id")
	if laptop:
		_place(player, laptop.global_position + Vector3(1.0, -0.4, 0))
		player._server_interact.rpc_id(1, laptop.get_path())
		await _frames(3)
	check(player.inventory.count_of(&"intel_laptop") == 1, "picked up")
	var before := People.intel.size()
	_place(player, Vector3(35, 0.1, 22))  # the test extraction point
	await _wait_until(func() -> bool: return People.intel.size() >= before + 2, 3.0)
	var carried := People.intel.filter(func(e: Dictionary) -> bool: return e.how == "carried")
	var items := carried.map(func(e: Dictionary) -> String: return e.item)
	check(People.intel.size() == before + 2 and "intel_laptop" in items and "intel_documents" in items
		and player.inventory.count_of(&"intel_laptop") == 0 and player.inventory.count_of(&"intel_documents") == 0,
		"carried into the extraction point: both banked and handed in (%s)" % [items])
	check(carried.all(func(e: Dictionary) -> bool: return String(e.intel_id) != "" and int(e.value) > 0 and e.by == "Player 1"),
		"each with its intel id, value and who brought it")
	check(People.summary().intel_value >= 3800 and _listener.intel.size() == People.intel.size(), "the debrief's value and the listener agree (%d)" % People.summary().intel_value)
	check(not Campaign.section(People.SECTION).get("archive", []).is_empty(), "and the campaign keeps it (People section)")
	officer.queue_free()


## Marking an enemy group by radio banks it at once; the same group again doesn't.
func _test_radio_report() -> void:
	print("Radio report")
	var s1 := _soldier("Spot1", &"hostile", Vector3(0, 0.1, -40), [], false)
	var s2 := _soldier("Spot2", &"hostile", Vector3(3, 0.1, -41), [], false)
	_place(player, Vector3(0, 0.1, -60))
	var before := People.intel.size()
	layer.request_report.rpc_id(1, Vector3(1, 0, -40))
	await _frames(2)
	var reports := People.intel.filter(func(e: Dictionary) -> bool: return e.how == "reported")
	check(People.intel.size() == before + 1 and reports.size() == 1 and int(reports[0].count) == 2 and int(reports[0].value) == 2 * PeopleLayer.REPORT_VALUE,
		"two enemies reported by radio, banked at once (%s)" % [reports])
	layer.request_report.rpc_id(1, Vector3(1, 0, -40))
	await _frames(2)
	check(People.intel.size() == before + 1, "the same group again isn't banked twice")
	check(layer.server_report(player, Vector3(30, 0, -60)).has("why"), "nobody there: nothing to report")
	s1.queue_free()
	s2.queue_free()


## A badly hurt, isolated hostile who sees the squad gives up: drops his weapon, nobody
## targets him, he can be cuffed from the front and searched.
func _test_surrender() -> void:
	print("Surrender")
	var quitter := _soldier("Quitter", &"hostile", Vector3(-35, 0.1, -30), CompoundLevel.HOSTILE_LOADOUT, true)
	SquadAI.of(quitter).hold_fire = true
	layer.server_give_intel(quitter, &"intel_documents", "Quitter")
	check(_into_pouch(quitter, &"intel_documents"), "his documents are in a pouch on his carrier")
	_place(player, Vector3(-35, 0.1, -20))
	await _frames(3)
	check(layer.surrender_reason(quitter) == "", "unhurt, he fights on")
	quitter.vitals.server_damage(45.0)
	await _frames(3)
	check(layer.surrender_reason(quitter) != "", "badly hurt, alone and seen: he would give up (%s; pain %.2f, blood %.2f)" % [layer.surrender_reason(quitter), quitter.vitals.pain(), quitter.vitals.blood_fraction()])
	PeopleLayer.surrender_enabled = true
	await _wait_until(func() -> bool: return Person.is_captive(quitter), 20.0)
	PeopleLayer.surrender_enabled = false
	check(Person.is_captive(quitter) and Person.kind_of(quitter) == Person.SOLDIER and SquadAI.of(quitter) == null and _brain(quitter) != null,
		"he surrenders: a captive with a captive's brain")
	await _frames(3)
	check(quitter.inventory.slots[&"primary"] == &"" and Person.is_noncombatant(quitter), "drops his rifle and is no longer a target")
	var charlie := _soldier("Charlie", &"friendly", Vector3(-35, 0.1, -24), ["m4a1", "mag_556"], true)
	charlie.rotation.y = 0.0  # facing -z, at him
	await _seconds(2.0)
	check(SquadAI.of(charlie).target != quitter, "a squad AI looking at him doesn't target him")
	charlie.queue_free()
	_place(player, quitter.global_position - quitter.global_basis.z * 1.5)  # in front of him
	await _frames(2)
	check(Person.cuff_problem(player, quitter) == "", "a surrendered man can be cuffed from the front")
	layer.request.rpc_id(1, "cuff", quitter.get_path())
	await _wait_until(func() -> bool: return Person.is_cuffed(quitter), 6.0)
	check(Person.is_cuffed(quitter), "cuffed")
	check(_ids(player, quitter).has(&"search"), "the menu offers Search for intel")
	check(InteractionMenu.has_regions(player, quitter) and InteractionMenu.general_actions(player, quitter).any(func(a: Dictionary) -> bool: return a.id == &"search"),
		"on his waist point")
	InteractionMenu.perform(player, _action(player, quitter, &"search"))
	await _frames(3)
	check(player.inventory.count_of(&"intel_documents") == 1 and quitter.inventory.count_of(&"intel_documents") == 0, "searched: his documents are now the player's")


## AI scavenging (Scavenge) takes intel off a body and keeps its intel id, so it banks as
## the same piece (People.has_intel) when the squadmate carries it out.
func _test_scavenge_intel() -> void:
	print("Scavenged intel")
	var body := _soldier("ScavOfficer", &"hostile", Vector3(30, 0.1, -50), CompoundLevel.HOSTILE_LOADOUT, false)
	layer.server_give_intel(body, &"intel_phone", "officer (scavenge)")
	var where := _where(body, &"intel_phone")
	var intel_id := String(body.inventory.containers[where[0]][where[1]].get("state", {}).get("intel_id", "")) if int(where[1]) >= 0 else ""
	body.vitals.server_kill()
	var echo := _soldier("Echo", &"friendly", Vector3(31, 0.1, -50), ["plate_carrier", "m4a1", "mag_556"], false)
	echo.inventory.take(&"mag_556", 6)  # a full basic load: the intel is what he wants
	await _frames(3)
	var pick := Scavenge.best_pick(echo, body, false)
	check(pick.get("kind") == "intel" and pick.get("id") == &"intel_phone", "a squadmate scavenging the body picks the intel (%s)" % [pick])
	check(Scavenge.apply(echo, body, pick) == 1 and echo.inventory.count_of(&"intel_phone") == 1 and body.inventory.count_of(&"intel_phone") == 0, "and takes it")
	var mine := _where(echo, &"intel_phone")
	var kept := String(echo.inventory.containers[mine[0]][mine[1]].get("state", {}).get("intel_id", "")) if int(mine[1]) >= 0 else ""
	check(intel_id != "" and kept == intel_id, "with its intel id (%s)" % kept)
	var banked := layer.server_bank_intel(echo)
	check(banked.size() == 1 and banked[0].intel_id == intel_id and People.has_intel(intel_id), "it banks as that piece")
	echo.queue_free()
	body.queue_free()
	await _frames(2)


## The compound's own content (PeopleLayer.COMPOUND, the main menu's checkbox) with its AI:
## officers carry their intel, everyone spawns, and no hostile ever targets a civilian or an HVT.
func _test_compound_content() -> void:
	print("The compound's people")
	_place(player, Vector3(0, 0.1, 24))
	var before := layer.people().size()
	layer.server_populate(PeopleLayer.COMPOUND)
	level._spawn_ai()
	await _frames(5)
	check(layer.people().size() == before + 6 and layer.persons.get_node_or_null(^"Extraction") is DeliveryPoint, "4 civilians, 2 HVTs and the extraction point")
	check(_world_item("c01_intel_laptop") != null and _world_item("c01_zip_cuffs") != null, "the laptop and zip cuffs lie in the compound")
	var officer := level.ai.get_node(^"Hostile1") as Soldier
	var leader := level.ai.get_node(^"Hostile3") as Soldier
	check(officer.inventory.count_of(&"intel_phone") == 1 and officer.inventory.count_of(&"intel_documents") == 1 and leader.inventory.count_of(&"intel_documents") == 1,
		"the officer carries a phone and documents, the patrol leader documents")
	var stamped := _where(officer, &"intel_phone")
	var entry: Dictionary = officer.inventory.containers[stamped[0]][stamped[1]] if stamped[1] >= 0 else {}
	check(String(entry.get("state", {}).get("intel_id", "")) != "" and String(entry.state.get("source", "")).contains("officer"), "each with its intel id and source (%s)" % [entry.get("state", {})])
	var targeted := false
	for i in 20:
		await _seconds(0.3)
		for n in get_tree().get_nodes_in_group(&"combatants"):
			var ai := SquadAI.of(n)
			if ai and ai.target and Person.is_noncombatant(ai.target):
				targeted = true
	check(not targeted, "for 6 s of AI, nobody targets a civilian or an HVT")
	for n in level.ai.get_children():
		n.queue_free()
	await _frames(2)


# --- Replication: a second process joins -------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	var keep := _person({"name": "CivKeep", "kind": CIVILIAN, "pos": Vector3(-40, 0.1, 20)})
	_brain(keep).process_mode = Node.PROCESS_MODE_DISABLED
	layer.server_place_intel(&"intel_documents", Vector3(-40, 0.5, 24), "test checkpoint", "test_people_docs")
	await _frames(3)
	expect = {"civilian": "CivKeep", "cuffed_hvt": "HvtTestCommander", "captive": "Quitter", "friendly_hvt": "HvtTestEngineer",
		"casualties": People.casualty_count(), "intel": People.intel.size(), "delivered": "hvt_test_commander",
		"point": "TestExtraction", "intel_uid": "test_people_docs"}
	# The client asks for these once it has joined (_ask_expect): a push on peer_joined was lost
	# when the client's first join attempts timed out while it was still building its world.
	var log_path := OS.get_user_data_dir().path_join("people_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/people_test.tscn",
		"--", "--people-join"]  # not main's --join: the client joins by itself (_join_host)
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _wait_until(func() -> bool: return _client_live, 120.0)
	check(_client_live, "the client checked what it found on joining")
	if _client_live:
		# Live changes once the client is in: a new casualty, and an order to the friendly HVT.
		var live := _person({"name": "CivLive", "kind": CIVILIAN, "pos": Vector3(-30, 0.1, 50)})
		_brain(live).process_mode = Node.PROCESS_MODE_DISABLED
		var delta := _soldier("Delta", &"friendly", Vector3(-30, 0.1, 44), ["m4a1", "mag_556"], false)
		await _frames(3)
		_shoot(delta, live)
		var engineer := layer.persons.get_node(^"HvtTestEngineer") as Soldier
		layer.server_lead(player, engineer)
		_live_done.rpc(People.casualty_count())
	await _wait_until(func() -> bool: return _client_failures >= 0, 45.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _wait_until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	# The client's own script errors fail the test too.
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


## Client -> host, once joined: send me what to check (the host answers the asker).
@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _client_checked() -> void:
	_client_live = true


@rpc("any_peer", "call_remote", "reliable")
func _live_done(casualties: int) -> void:
	expect["live_casualties"] = casualties


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# This test joins by itself (_join_host), not through the menu's few short tries (two
	# joiners replaced each other's connection), and a dropped attempt must not reload the
	# scene from under it (Main reloads on session_ended).
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	# Under load the menu's few short join attempts (Menu.JOIN_ATTEMPTS) can all time out while
	# this process is still building its world: keep joining until it's in, then ask for the
	# expectations (as the world suite does).
	var joined := await _join_host("127.0.0.1", 90.0)
	level = CompoundLevel.current(self)
	layer = level.people
	if joined:
		var asked_until := Time.get_ticks_msec() + 60000
		while expect.is_empty() and Time.get_ticks_msec() < asked_until:
			_ask_expect.rpc_id(1)
			await _wait_until(func() -> bool: return not expect.is_empty(), 3.0)
	await _wait_until(func() -> bool: return not expect.is_empty() and layer.persons.get_node_or_null(NodePath(String(expect.civilian))) != null \
		and People.casualty_count() == int(expect.casualties) and not layer.states.is_empty(), 60.0)
	if expect.is_empty():
		note.call(false, "the host's expectations arrived (joined: %s, connection %d)" % [joined,
			multiplayer.multiplayer_peer.get_connection_status() if multiplayer.multiplayer_peer else -1])
	else:
		var civ := layer.persons.get_node_or_null(NodePath(String(expect.civilian))) as Soldier
		var hvt := layer.persons.get_node_or_null(NodePath(String(expect.cuffed_hvt))) as Soldier
		var engineer := layer.persons.get_node_or_null(NodePath(String(expect.friendly_hvt))) as Soldier
		var captive := level.ai.get_node_or_null(NodePath(String(expect.captive))) as Soldier
		note.call(civ != null and civ.faction == Person.FACTION and Person.is_civilian(civ) and civ.get_node_or_null(NodePath(PeopleLayer.BRAIN)) == null,
			"a civilian spawned here, a civilian by the replicated state (no brain on a client)")
		note.call(hvt != null and Person.is_hvt(hvt) and Person.is_cuffed(hvt) and bool(Person.state(hvt).get("delivered", false)),
			"the HVT is here, cuffed and delivered")
		note.call(captive != null and Person.is_captive(captive) and Person.is_cuffed(captive) and Person.is_noncombatant(captive),
			"the hostile who surrendered is a cuffed captive here too")
		var me := level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		if me and captive:
			var ids := InteractionMenu.actions_for(me, captive).map(func(a: Dictionary) -> StringName: return a.id)
			note.call(&"lead" in ids and &"carry" in ids and &"search" in ids and not &"cuff" in ids, "the client's interaction menu reads it: %s" % [ids])
		note.call(People.casualty_count() == int(expect.casualties) and People.intel.size() == int(expect.intel) and People.is_delivered(String(expect.delivered)),
			"the ledger: %d casualties, %d intel, the delivery" % [People.casualty_count(), People.intel.size()])
		var point := level.find_child(String(expect.point), true, false)
		note.call(point is DeliveryPoint and point.is_in_group(DeliveryPoint.GROUP), "the extraction point is here")
		var docs: WorldItem = null
		for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
			if node.uid == String(expect.intel_uid):
				docs = node
		note.call(docs != null and String(docs.state.get("intel_id", "")) != "", "the placed intel lies here with its intel id")
		_client_checked.rpc_id(1)
		await _wait_until(func() -> bool: return expect.has("live_casualties") and People.casualty_count() == int(expect.live_casualties) \
			and engineer != null and Person.state(engineer).get("order") == "follow", 15.0)
		note.call(People.casualty_count() == int(expect.get("live_casualties", -1)), "a live casualty reached the client (%d)" % People.casualty_count())
		note.call(engineer != null and Person.state(engineer).get("order") == "follow" and String(Person.state(engineer).get("led_by", "")) == "Players/1",
			"a live order (Follow me) reached the client")
	_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


## Up to two AI squadmates escort an HVT (Captain, 2026-10-11): ordered from the command menu,
## they keep him with the squad, go after him when he bolts (not at once), and a wounded HVT
## is treated by them until a medic, pulled to him first, takes over.
func _test_escort() -> void:
	print("HVT escort")
	for n in layer.people():
		if Person.is_hvt(n) and not n.vitals.is_up():
			n.queue_free()  # an earlier check's downed captive HVT would draw the medic
	await _frames(2)
	var at := Vector3(-40, 0.1, 30)
	_place(player, at + Vector3(0, 0, 6))
	var e1 := _squadmate("Esc1", Roles.RIFLEMAN, at + Vector3(1.5, 0, 2))
	var e2 := _squadmate("Esc2", Roles.RIFLEMAN, at + Vector3(-1.5, 0, 2))
	var medic := _squadmate("EscMedic", Roles.MEDIC, at + Vector3(0, 0, 25))
	var hvt := _person({"name": "HvtTestCourier", "kind": "hvt", "side": "hostile", "hvt_id": "hvt_test_courier",
		"label": "HVT (the Courier)", "pos": at})
	var brain := _brain(hvt) as HvtAI
	await _frames(3)
	layer.server_surrender(hvt, "test")
	var squad := level.squad_for(&"friendly")
	check(squad.order_escort(player, String(hvt.name), PackedStringArray(["Esc1", "Esc2", "EscMedic"])), "Escort that HVT: ordered")
	var escorts := SquadAI.escorts_of(hvt)
	check(escorts.size() == 2 and SquadAI.of(medic).escorting == null, "the two nearest take him; no more than two (%s)" % [escorts.map(func(a: SquadAI) -> String: return a.body.name)])
	await _wait_until(func() -> bool: return String(Person.state(hvt).get("led_by", "")) == layer.key_of(escorts[0].body), 4.0)
	check(String(Person.state(hvt).get("led_by", "")) == layer.key_of(escorts[0].body) and not Person.is_cuffed(hvt), "the first escort leads him, uncuffed")
	# The squad moves on: he comes along with his escorts.
	_place(player, at + Vector3(0, 0, 18))
	await _wait_until(func() -> bool: return _flat(hvt.global_position, player.global_position) < 9.0 and escorts.all(func(a: SquadAI) -> bool: return _flat(a.body.global_position, hvt.global_position) < HvtAI.WATCH_M), 15.0)
	check(_flat(hvt.global_position, player.global_position) < 9.0 and escorts.all(func(a: SquadAI) -> bool: return _flat(a.body.global_position, hvt.global_position) < HvtAI.WATCH_M),
		"the squad moves on and he comes along, his escorts close (%.1f m from the player; escorts %s m)" % [_flat(hvt.global_position, player.global_position), escorts.map(func(a: SquadAI) -> String: return "%.1f %s" % [_flat(a.body.global_position, hvt.global_position), a.body.ai_status])])
	check(brain.watched() and brain.bolts == 0, "watched all the way: he stays")
	# He bolts anyway: they go after him, not at once.
	# One of his men close by: he runs to him (and isn't cornered while he's up); the escorts hold fire.
	var refuge := _soldier("CourierGuard", &"hostile", hvt.global_position + Vector3(10, 0, 0), [], false)
	for a in escorts:
		a.grab_scale = 10.0
		a.hold_fire = true
	layer.server_take_back_surrender(hvt)
	brain.spotted = player
	brain.spotted_pos = player.global_position
	brain.spotted_at = Soldier._now()
	await _frames(2)
	check(escorts.all(func(a: SquadAI) -> bool: return a.grabs == 0 and (a._react_at < 0.0 or a._react_at > Soldier._now())) and not Person.is_captive(hvt),
		"he bolts: his escorts take a moment to react (nobody has him the instant he moves)")
	await _seconds(SquadAI.ESCORT_REACT_S.x + 0.3)
	check(escorts.all(func(a: SquadAI) -> bool: return a.body.ai_status.begins_with("Going after")), "then they go after him, weapons down (%s)" % [escorts.map(func(a: SquadAI) -> String: return a.body.ai_status)])
	# A footrace can go either way (he may get away); within reach, they grab him.
	_place(hvt, escorts[0].body.global_position + Vector3(0.8, 0, 0))
	await _wait_until(func() -> bool: return escorts.any(func(a: SquadAI) -> bool: return a.grabs > 0), 4.0)
	check(escorts.any(func(a: SquadAI) -> bool: return a.grabs > 0) and Person.is_captive(hvt), "caught up with, he's grabbed: he gives up again")
	refuge.queue_free()
	for a in escorts:
		a.hold_fire = false
	# Wounded: the escorts see to him, a medic is pulled to him and takes over.
	var medic_at := NavigationServer3D.map_get_closest_point(hvt.get_world_3d().navigation_map, hvt.global_position + Vector3(18, 0, 0))
	_place(medic, medic_at + Vector3.UP * 0.1)
	await _frames(2)
	check(medic.global_position.distance_to(hvt.global_position) > 8.0, "the medic starts away from the wounded HVT")
	hvt.vitals.server_damage(70.0)
	await _wait_until(func() -> bool: return not hvt.vitals.is_up(), 3.0)
	# Remembered contact must not keep an escort on the escort intent: care beats
	# escorting, including the intent-switch hysteresis. No live shooter is needed.
	var responder := SquadAI.of(SquadAI.responder_for(hvt))
	if responder != null and responder.escorting == hvt:
		responder._last_contact = Soldier._now()
		responder.intent = SquadAI.Intent.ESCORT
		responder._choose_intent()
		check(responder.intent == SquadAI.Intent.CASUALTY, "remembered contact: an escort switches to his wounded HVT's care")
	else:
		check(false, "a wounded HVT has an escort responder")
	await _wait_until(func() -> bool: return is_instance_valid(hvt.care_by), 6.0)
	var first: Soldier = hvt.care_by
	check(first == e1 or first == e2, "down: an escort is on him first (%s)" % (first.name if first else "nobody"))
	await _wait_until(func() -> bool: return SquadAI.of(medic).casualty == hvt, 5.0)
	check(SquadAI.of(medic).care == SquadAI.Care.REACH and (hvt.care_by == e1 or hvt.care_by == e2),
		"the escort keeps care while the medic is on the way")
	await _wait_until(func() -> bool: return hvt.care_by == medic, 25.0)
	check(hvt.care_by != medic or medic.global_position.distance_to(hvt.body_point()) <= SquadAI.CASUALTY_REACH + 0.25,
		"the medic takes care over only after reaching the HVT's actual body")
	check(hvt.care_by == medic and SquadAI.of(medic).casualty == hvt, "the medic is pulled to him and takes over (%s; medic: %s, intent %d, care %d, %.1f m, candidate %s, free %s, cares %s)" % [hvt.care_by.name if hvt.care_by else "nobody", medic.ai_status, SquadAI.of(medic).intent, SquadAI.of(medic).care, medic.global_position.distance_to(hvt.global_position), SquadAI.of(medic)._find_casualty(), SquadAI.of(medic)._free_for(hvt), SquadAI.of(medic)._cares_for(hvt)])
	check(escorts.all(func(a: SquadAI) -> bool: return a.escorting == hvt), "his escorts stay on him")
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position, PackedStringArray(["Esc1"]))
	check(SquadAI.of(e1).escorting == null and SquadAI.of(e2).escorting == hvt, "a movement order takes a squadmate off the escort")
	for s: Soldier in [e1, e2, medic, hvt]:
		s.queue_free()
	await _frames(3)


## Review of the escort handoff (2026-10-18): while a medic walks in on a wounded HVT, his
## escort keeps care_by; the other free medics must leave him to that one (before, every free
## medic converged on him), and one takes over if the medic walking in goes down.
func _test_escort_two_medics() -> void:
	print("HVT escort: one medic walks in at a time")
	for n in layer.people():
		if Person.is_hvt(n) and not n.vitals.is_up():
			n.queue_free()
	await _frames(2)
	var at := Vector3(-40, 0.1, 30)
	_place(player, at + Vector3(0, 0, 6))
	var e1 := _squadmate("Esc3", Roles.RIFLEMAN, at + Vector3(1.5, 0, 2))
	var e2 := _squadmate("Esc4", Roles.RIFLEMAN, at + Vector3(-1.5, 0, 2))
	var map := player.get_world_3d().navigation_map
	var m1 := _squadmate("EscMedicA", Roles.MEDIC, NavigationServer3D.map_get_closest_point(map, at + Vector3(30, 0, 3)) + Vector3.UP * 0.1)
	var m2 := _squadmate("EscMedicB", Roles.MEDIC, NavigationServer3D.map_get_closest_point(map, at + Vector3(30, 0, -3)) + Vector3.UP * 0.1)
	var hvt := _person({"name": "HvtTestBanker", "kind": "hvt", "side": "hostile", "hvt_id": "hvt_test_banker",
		"label": "HVT (the Banker)", "pos": at})
	await _frames(3)
	layer.server_surrender(hvt, "test")
	var squad := level.squad_for(&"friendly")
	check(squad.order_escort(player, String(hvt.name), PackedStringArray(["Esc3", "Esc4"])) and SquadAI.escorts_of(hvt).size() == 2,
		"two escorts on a second HVT")
	await _frames(2)
	var medics: Array[Soldier] = [m1, m2]
	check(medics.all(func(m: Soldier) -> bool: return m.global_position.distance_to(hvt.global_position) > 15.0),
		"both medics start well away from him (%s m)" % [medics.map(func(m: Soldier) -> String: return "%.0f" % m.global_position.distance_to(hvt.global_position))])
	hvt.vitals.server_damage(70.0)
	await _wait_until(func() -> bool: return not hvt.vitals.is_up(), 3.0)
	await _wait_until(func() -> bool: return hvt.care_by == e1 or hvt.care_by == e2, 6.0)
	check(hvt.care_by == e1 or hvt.care_by == e2, "down: an escort is on him first")
	var walking := func() -> Array:
		return medics.filter(func(m: Soldier) -> bool: return SquadAI.of(m).casualty == hvt)
	await _wait_until(func() -> bool: return not walking.call().is_empty(), 6.0)
	var first: Array = walking.call()
	var walker: Soldier = first[0] if first.size() == 1 else null
	var claimed := walker != null and SquadAI.of(walker).care == SquadAI.Care.REACH and SquadAI.handoff_medic(hvt) == walker
	var most := first.size()
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline and (hvt.care_by == e1 or hvt.care_by == e2):
		most = maxi(most, (walking.call() as Array).size())
		await get_tree().process_frame
	check(claimed and most == 1 and walking.call() == first,
		"two free medics: only one walks in on the HVT, the other leaves him to him (at most %d at once; %s)" % [most, [first.map(func(m: Soldier) -> String: return m.name)]])
	check(walker != null and SquadAI.of(walker).care == SquadAI.Care.REACH and (hvt.care_by == e1 or hvt.care_by == e2),
		"the escort still treating while that medic is on his way")
	if walker == null:
		for s: Soldier in [e1, e2, m1, m2, hvt]:
			s.queue_free()
		await _frames(3)
		return
	var other: Soldier = m2 if walker == m1 else m1
	walker.vitals.server_kill()
	await _wait_until(func() -> bool: return SquadAI.of(other).casualty == hvt, 6.0)
	check(SquadAI.of(other).casualty == hvt and SquadAI.handoff_medic(hvt) == other and (hvt.care_by == e1 or hvt.care_by == e2),
		"the medic walking in goes down: the other medic takes the handoff on, the escort still treating")
	await _wait_until(func() -> bool: return hvt.care_by == other, 30.0)
	check(hvt.care_by == other and not hvt.has_meta(SquadAI.HANDOFF_META),
		"and takes him over once he's there (%s, %.1f m)" % [hvt.care_by.name if hvt.care_by else "nobody", _flat(other.global_position, hvt.body_point())])
	for s: Soldier in [e1, e2, m1, m2, hvt]:
		s.queue_free()
	await _frames(3)


## Captain, 2026-10-15 (v0.4.11): HVTs and hostages didn't get into AAVs or M-ATVs. Whoever a
## squadmate leads or escorts gets in with him (a free passenger seat) and out with him.
func _test_ride_with_leader() -> void:
	print("Riding with the squad")
	var vl := level.get_node(^"Vehicles") as VehicleLayer
	var at := Vector3(-60, 0.1, -30)
	var matv := vl.server_spawn("matv", Transform3D(Basis(), at + Vector3(6, 0, 0)), "", &"player", "ride_matv")
	var aav := vl.server_spawn("aav7", Transform3D(Basis(), at + Vector3(-10, 0, 0)), "", &"player", "ride_aav")
	await _frames(3)
	var hvt := _person({"name": "HvtTestPilot", "kind": "hvt", "side": "friendly", "hvt_id": "hvt_test_pilot",
		"label": "HVT (the Pilot)", "pos": at})
	_place(player, at + Vector3(2, 0, 0))
	await _frames(3)
	layer.server_lead(player, hvt)
	check(matv.server_enter(player), "the player gets into the M-ATV")
	check(Vehicle.ride_of(hvt) == matv and matv.seat_kind(matv.seat_of(hvt)) == Vehicle.PASSENGER
		and String(Person.state(hvt).get("seated_in", "")) == layer.key_of(matv), "the HVT he leads gets in with him, in the back")
	matv.server_exit(player)
	await _frames(2)
	check(Vehicle.ride_of(hvt) == null and String(Person.state(hvt).get("led_by", "")) == layer.key_of(player),
		"he gets out when the player does, and follows him again")
	# A hostage escorted by a squadmate: into the AAV with his escort, out with him.
	var hostage := _person({"name": "HostageTest", "kind": "hvt", "side": "friendly", "hvt_id": "hvt_test_hostage",
		"label": "Hostage", "pos": at + Vector3(-4, 0, 3)})
	var esc := _squadmate("RideEsc", Roles.RIFLEMAN, at + Vector3(-5, 0, 3))
	await _frames(3)
	SquadAI.of(esc).set_escort(hostage)
	check(aav.server_enter(esc), "the escort gets into the AAV")
	check(Vehicle.ride_of(hostage) == aav and aav.seat_kind(aav.seat_of(hostage)) == Vehicle.PASSENGER, "the hostage he escorts gets in with him")
	check(Vehicle.ride_of(hvt) == null, "someone nobody leads stays out")
	vl.server_order_dismount(player, PackedStringArray(["RideEsc"]))
	await _frames(2)
	check(Vehicle.ride_of(esc) == null and Vehicle.ride_of(hostage) == null, "Dismount: the hostage gets out with his escort")
	for n: Node in [esc, hostage, hvt, matv, aav]:
		n.queue_free()
	await _frames(3)


## B-06 (P0583: 1456 "Attempt to call RPC with unknown peer ID" from _update_carried): a
## player's body carried while its player isn't in the session (a frame bench's stand-in, or
## the moment a player drops) is the host's: no RPC to the gone peer every tick, and the host
## moves the body with its carrier itself, as it does an AI's.
func _test_carried_owner_gone() -> void:
	print("A carried player's body whose player isn't here (B-06)")
	var at := Vector3(-46, 0.1, 30)
	var gone := 4242  # no such peer
	check(not gone in multiplayer.get_peers(), "peer %d isn't in the session" % gone)
	var body := CompoundLevel.PLAYER_SCENE.instantiate() as Soldier
	body.name = str(gone)
	body.position = at
	level.players.add_child(body, true)
	await _frames(2)
	check(not body.owner_connected() and player.owner_connected(), "owner_connected: no for the stand-in, yes for the host's own player")
	body.vitals.server_damage(500.0)
	await _frames(3)
	var bearer := _soldier("Bearer", &"friendly", at + Vector3(0.8, 0, 0), ["m4a1"], false)
	await _frames(3)
	var errors := ErrorCount.new()
	errors.match = "unknown peer"
	OS.add_logger(errors)
	check(bearer.server_pick_up_body(body, Soldier.CARRY, 4.0), "an AI picks the body up")
	_end_carry_phase(bearer)
	bearer.global_position = at + Vector3(3.0, 0, 2.0)
	await _seconds(0.5)
	var held := bearer.carry_transform().origin
	check(body.global_position.distance_to(held) < 0.2, "the host carries it along on the shoulder (%.2f m off)" % body.global_position.distance_to(held))
	bearer.server_put_down()
	await _seconds(Soldier.CARRY_LOWER_S + 0.3)
	check(body.carried_by == null and _flat(body.global_position, bearer.global_position) < 1.5, "and puts it down in front of the bearer")
	OS.remove_logger(errors)
	check(errors.count == 0, "no RPC to the gone peer (%d errors)" % errors.count)
	body.queue_free()
	bearer.queue_free()
	await _frames(2)


func _squadmate(callsign: String, role: StringName, pos: Vector3) -> Soldier:
	return level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": [], "role": String(role), "team": 0, "combat": 0.6, "discipline": 0.6, "guard": false})


# --- Helpers -------------------------------------------------------------------------------

func _person(data: Dictionary) -> Soldier:
	return layer.server_spawn_person(data)


func _brain(s: Soldier) -> CivilianAI:
	return s.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI


func _soldier(callsign: String, faction: StringName, pos: Vector3, loadout: Array, active: bool) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": loadout, "combat": 0.9, "discipline": 0.6, "guard": true})
	if not active:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


## `shooter` fires one round at `target`'s chest (the host request AI uses).
func _shoot(shooter: Soldier, target: Soldier) -> void:
	var eye := shooter.camera.global_position
	shooter._server_fire.rpc_id(1, eye, (target.aim_point() - eye).normalized(), &"primary")


func _ids(actor: Soldier, target: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for a in InteractionMenu.actions_for(actor, target):
		ids.append(a.id)
	return ids


func _action(actor: Soldier, target: Node, id: StringName) -> Dictionary:
	for a in InteractionMenu.actions_for(actor, target):
		if a.id == id:
			return a
	return {}


## [container, index] of the first stowed `id` on `s`.
func _where(s: Soldier, id: StringName) -> Array:
	for container in s.inventory.search_containers():  # MOLLE pouches too
		var list: Array = s.inventory.containers[container]
		for i in list.size():
			if list[i].id == id:
				return [container, i]
	return [&"", -1]


## Hangs a GP pouch on a free utility point of `s`'s carrier (if none is there yet) and moves
## the first stowed `id` into it. True if it ended up in a pouch.
func _into_pouch(s: Soldier, id: StringName) -> bool:
	var inv := s.inventory
	var pouch := &""
	for p: Dictionary in inv.attach_points():
		if pouch != &"" or String(p.type) != "utility":
			continue
		var att := inv.attachment(StringName(p.id))
		if att.is_empty():
			if inv.attach(StringName(p.id), {"id": &"pouch_utility"}):
				pouch = Inventory.pouch_container(StringName(p.id))
		elif StringName(att.id) == &"pouch_utility":
			pouch = Inventory.pouch_container(StringName(p.id))
	var at := _where(s, id)
	if pouch == &"" or int(at[1]) < 0:
		return false
	if at[0] == pouch:
		return true
	var entry := inv.remove_entry(at[0], at[1], 1)
	if inv.insert_entry(pouch, entry):
		return true
	inv.insert_entry(at[0], entry)
	return false


func _world_item(uid: String) -> WorldItem:
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if node.uid == uid and not node.is_queued_for_deletion():
			return node
	return null


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Client: joins the host at `address`, joining again whenever an attempt has failed, until it
## is in or `seconds` pass. Whether it joined.
func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:  # (or in already)
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The pick-up or put-down `s` is in is over (Soldier.CARRY_LIFT_S, CARRY_LOWER_S: the host
## counts them down in the carrier's physics step).
func _end_carry_phase(s: Soldier) -> void:
	s._carry_phase_left = 0.0
	s.carry_busy_until = 0.0
	s._update_carried(0.0)
