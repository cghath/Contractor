extends Node
## Headless checks for high command (docs/high_command.md, combined_arms.md section 5; phases C1
## and on). C1: the groundwork G1-G12 (a second friendly squad of 4 beside the player squad is
## ignored by the player squad's orders, rebalance, roster, extraction and voice range, and
## fights from its own picture), and the section 9 lifts (FollowBrain, ProgressWatch,
## CareRules, DeadGround) on staged inputs.
##   <voxel godot exe> --headless --path . res://tests/high_command_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_high_command" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("HIGH_COMMAND TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_follow_brain()
	_test_progress_watch()
	_test_care_rules()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()
	await _frames(5)
	await _test_dead_ground()
	await _test_groundwork()
	GameState.delete_save()
	print("HIGH_COMMAND TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Pure: the section 9 lifts -------------------------------------------------------------------

func _test_follow_brain() -> void:
	print("FollowBrain")
	var base := {"me": Vector3(0, 0, 40), "lead": Vector3.ZERO, "lead_yaw": 0.0, "offset": Vector2(0, 15), "near_m": 10.0, "far_m": 25.0}
	var d := FollowBrain.decide(base)
	check(d.kind == "walk" and d.speed == FollowBrain.RUN, "40 m behind (far 25): run to the station")
	check(FollowBrain.flat(d.point, Vector3(0, 0, 15)) < 0.01, "the station is 15 m behind a leader facing -z")
	var c := base.duplicate()
	c.me = Vector3(0, 0, 18)
	c.contact = true
	check(FollowBrain.decide(c).kind == "hold", "in contact inside the band: hold and fight")
	var ok := base.duplicate()
	ok.me = Vector3(1, 0, 16)
	check(FollowBrain.decide(ok).kind == "none", "on station: nothing to do")
	var ride := base.duplicate()
	ride.lead_ride = "truck"
	ride.door = Vector3(2, 0, 0)
	check(FollowBrain.decide(ride).kind == "walk", "the leader got in a vehicle: walk to its door")
	ride.me = Vector3(3, 0, 0)
	check(FollowBrain.decide(ride).kind == "board", "at the door: board")
	ride.my_ride = "truck"
	check(FollowBrain.decide(ride).kind == "none", "aboard his vehicle: nothing")
	var out := base.duplicate()
	out.my_ride = "truck"
	check(FollowBrain.decide(out).kind == "exit", "the leader is on foot: get out")
	var lz := base.duplicate()
	lz.points = [{"pos": Vector2(0, 0), "radius": 20.0}]
	var into := FollowBrain.decide(lz)
	check(into.kind == "walk" and Vector2(into.point.x, into.point.z).length() <= 20.0, "the leader stands in an extraction point: get inside it")
	var sup := FollowBrain.offset_for("support")
	check(sup.length() >= 60.0 and sup.length() <= 120.0 * 1.2, "Support me keeps a 60-120 m echelon")


func _test_progress_watch() -> void:
	print("ProgressWatch")
	var w := ProgressWatch.new()
	var goal := Vector3(100, 0, 0)
	w.feed(Vector3.ZERO, goal, 0.0)
	var t := 0.0
	var pos := Vector3.ZERO
	for i in 10:  # 1 m/s toward the goal
		t += 1.0
		pos.x += 1.0
		w.feed(pos, goal, t)
	check(w.state == ProgressWatch.OK, "headway: ok")
	for i in 5:
		t += 1.0
		w.feed(pos, goal, t)
	check(w.state == ProgressWatch.WEDGED and w.detour != Vector3.ZERO, "5 s with no headway: wedged, with a detour")
	var first := w.detour
	t += 2.0
	w.feed(pos, goal, t)
	check(w.detour != first, "the next detour goes another way")
	t += 30.0
	w.feed(pos, goal, t)
	check(w.state == ProgressWatch.HELD_UP and "held up" in w.note, "past 30 s: held up, with a note")
	t += 60.0
	w.feed(pos, goal, t)
	check(w.state == ProgressWatch.UNABLE, "past 90 s: unable")
	w.feed(pos + Vector3(20, 0, 0), goal, t + 1.0)
	check(w.state == ProgressWatch.OK, "a jump (ride, respawn) starts the watch over")


func _test_care_rules() -> void:
	print("CareRules")
	var next := CareRules.next_casualty([{"id": "a", "dist": 3.0}, {"id": "b", "dist": 20.0, "urgent": true},
		{"id": "c", "dist": 40.0, "bleeding": true}])
	check(next.get("id") == "c", "massive bleeding first, however far")
	next = CareRules.next_casualty([{"id": "a", "dist": 3.0, "being_treated": true}, {"id": "b", "dist": 20.0}])
	check(next.get("id") == "b", "one already being treated waits")
	check(not CareRules.give_up(30.0, 0), "not before 45 s")
	check(CareRules.give_up(50.0, 0), "45 s down and nobody up: give up")
	check(not CareRules.give_up(60.0, 2) and CareRules.give_up(130.0, 2, true), "others up: only past 120 s when nobody came")
	check(CareRules.casevac_carrier(Vector3(50, 0, 0), Vector3.ZERO, [{"id": "x", "pos": Vector3(40, 0, 0)},
		{"id": "y", "pos": Vector3(49, 0, 0), "carrying": true}, {"id": "z", "pos": Vector3(0, 0, 0)}]) == "x", "the nearest free carrier")
	check(CareRules.casevac_carrier(Vector3(3, 0, 0), Vector3.ZERO, [{"id": "x", "pos": Vector3.ZERO}]) == "", "already at the rally point: nobody")


func _test_dead_ground() -> void:
	print("DeadGround, knowledge-fair (lift 4)")
	var marks := MapNodes.markers(level)
	var hidden_enemy := level.spawn_soldier({"name": "HC_Hidden", "faction": "hostile", "variant": "desert", "pos": level.ground_point(Vector3(60, 0, 60)),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(2)
	check(DeadGround.known_watchers(level, [level.squad_for(&"friendly")]).filter(func(p: Vector3) -> bool: return p.distance_to(hidden_enemy.global_position) < 1.0).is_empty(),
		"an enemy nobody has reported isn't a known watcher")
	var id := marks.server_report_enemy(Vector3(60, 0, 60), "test")
	check(DeadGround.known_watchers(level).size() >= 1, "an enemy intel marker is one")
	marks.server_remove(id)
	hidden_enemy.queue_free()
	await _frames(2)


# --- In a level: the groundwork G1-G12 ----------------------------------------------------------

func _test_groundwork() -> void:
	print("Groundwork (G1-G12)")
	var mine := level.squad_for(&"friendly")
	player.global_position = level.ground_point(Vector3(0, 0, 0))
	await _frames(3)
	var before := mine.members().size()
	var hawk := HighCommand.server_spawn_squad(level, {"id": "hawk2", "callsign": "Hawk 2"}, player.global_position + Vector3(30, 0, 0))
	await _frames(5)
	check(hawk != null and hawk.members().size() == 4, "a hero squad of 4 spawns on its own Squad")
	check(hawk.hc_id == &"hawk2" and hawk.is_in_group(Squad.HC_GROUP), "it carries its hc_id and joins the group")
	var men := hawk.members()
	check(men.all(func(s: Soldier) -> bool: return s.hc_id == &"hawk2"), "its men carry Soldier.hc_id (from the spawn data, on every peer)")
	check(hawk.hero == men[0] and hawk.leader == men[0], "its first man is its hero and leader")
	# G1: disjoint members
	var overlap := mine.members().filter(func(s: Soldier) -> bool: return s in men)
	check(overlap.is_empty() and mine.members().size() == before, "G1: the player squad's members() leave the hero squad out")
	check(mine.is_player_squad() and not hawk.is_player_squad(), "is_player_squad tells them apart")
	check(level.squad_for(&"friendly") == mine, "G12: squad_for still means the player squad")
	check(level.squad_of(men[1]) == hawk and level.squad_of(mine.members()[0]) == mine, "G12: squad_of is the soldier's own squad")
	check(not Squad.is_squadmate(men[1]) and Squad.is_squadmate(mine.members()[0]), "is_squadmate: player squad AI only")
	# G2: rebalance keeps them
	level.rebalance_squad()
	await _frames(3)
	check(hawk.members().size() == 4, "G2: rebalance_squad keeps the hero squad's men")
	# G3: command menu roster
	var menu: CommandMenu = player._hud.command_menu
	check(menu.roster().filter(func(s: Soldier) -> bool: return s.hc_id != &"").is_empty(), "G3: the command menu's roster lists none of them")
	# G11: extraction and squad_ai
	check(MapNodes.squad_ai(level).filter(func(s: Soldier) -> bool: return s in men).is_empty(), "MapNodes.squad_ai leaves them out")
	check(MapNodes.hc_ai(level, &"hawk2").size() == 4, "MapNodes.hc_ai finds them")
	var ex := MapNodes.extraction(level)
	check(ex.required().ai.filter(func(s: Soldier) -> bool: return s in men).is_empty(), "G11: extraction doesn't wait for them")
	var far_point := {"pos": Vector2(5000, 5000), "radius": 20.0}
	check(ex.missing_of(far_point, men).size() == 4, "missing_of names a group outside a point (lift 5)")
	# G4: assess counts only its own men
	if hawk.tactics == null:
		hawk.tactics = SquadTactics.new(hawk)
	check(int(hawk.tactics.assess().up) == 4, "G4: its assess() counts its 4, not the humans")
	# G5: voice range
	var callouts := level.callouts
	men[1].global_position = player.global_position + Vector3(200, 0, 0)
	check(callouts.recipients(men[1]).is_empty(), "G5: a hero squad man 200 m away isn't heard")
	men[1].global_position = player.global_position + Vector3(20, 0, 0)
	check(callouts.recipients(men[1]).size() == 1, "G5: at 20 m he is")
	# G6: QRF watchers
	var er := level.get_node_or_null(^"EnemyResponse")
	if er and er.has_method(&"_watchers"):
		check(men[0] in er._watchers(), "G6: the hero squad watches for QRF spawns")
	# G8: streaming focus (zones only)
	if level is ZoneLevel:
		check(hawk.hero.global_position in (level as ZoneLevel).stream_focus(), "G8: its hero is in stream_focus")
	# G9: the hero keeps his own place
	check(hawk.follow_point(hawk.hero) == hawk.hero.global_position, "G9: the hero never chases his own slot")
	# orders on one squad don't move the other
	mine.give_order(player, Squad.Order.HOLD, player.global_position)
	check(men.all(func(s: Soldier) -> bool: return SquadAI.of(s).order == Squad.Order.FOLLOW), "an order to the player squad doesn't reach the hero squad")
	hawk.give_order(hawk.hero, Squad.Order.HOLD, hawk.hero.global_position)
	check(mine.members().all(func(s: Soldier) -> bool: return SquadAI.of(s).order == Squad.Order.HOLD), "and the other way round")
	check(hawk.tasking.is_empty(), "an empty tasking (nothing changes)")
	mine.give_order(player, Squad.Order.FOLLOW, player.global_position)
	for s in hawk.members():
		s.queue_free()
	hawk.queue_free()
	await _frames(2)
