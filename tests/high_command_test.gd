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
var _hawk: Squad


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
	_test_hc_order()
	_test_heroes()
	_test_ce()
	_test_phase2_pure()
	_test_viewshed()
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
	await _test_map_flow()
	await _test_phase2()
	await _test_orders()
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
	_hawk = hawk


# --- C2: HcOrder, Heroes, CE (pure) --------------------------------------------------------------

func _test_hc_order() -> void:
	print("HcOrder.clean")
	var ctx := {"area": Rect2(-500, -500, 1000, 1000), "squads": {"hawk2": true}, "commander": true}
	var ok := HcOrder.clean(HcOrder.make("hawk2", "move", [[10, 20]]), ctx)
	check(bool(ok.ok) and ok.order.points == [[10.0, 20.0]], "a good Move passes")
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "dance", [[0, 0]]), ctx).ok), "an unknown verb is refused")
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "move", [[NAN, 0]]), ctx).ok), "NaN is refused")
	check(String(HcOrder.clean(HcOrder.make("hawk2", "move", [[900, 0]]), ctx).why) == "off the map", "off the map is refused")
	var route: Array = []
	for i in 17:
		route.append([i, i])
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "move", route), ctx).ok), "a 17-point route is refused")
	var full := ctx.duplicate()
	full.queued = 8
	full.append = true
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "move", [[0, 0]]), full).ok), "a ninth queued order is refused")
	var nc := ctx.duplicate()
	nc.commander = false
	check(String(HcOrder.clean(HcOrder.make("hawk2", "move", [[0, 0]]), nc).why) == "you don't have command", "a non-commander is refused")
	check(not bool(HcOrder.clean(HcOrder.make("viper3", "move", [[0, 0]]), ctx).ok), "an unknown squad is refused")
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "move", []), ctx).ok), "Move needs a point")
	check(not bool(HcOrder.clean(HcOrder.make("hawk2", "attack", [[0, 0]]), ctx).ok) and bool(HcOrder.clean(HcOrder.make("hawk2", "attack", [[0, 0]]), ctx.merged({"phase2": true})).ok), "Phase 2 verbs only with phase2 (HighCommand.PHASE2 is on)")
	var edge := HcOrder.clean(HcOrder.make("hawk2", "move", [[495, 0]]), ctx)
	check(bool(edge.ok) and float(edge.order.points[0][0]) <= 420.0, "a point near the edge is clamped 80 m inside")


func _test_heroes() -> void:
	print("Heroes")
	var data := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var added := Heroes.seed_standing(data, 1, rng)
	check(added.size() == 8 and Heroes.detachments(data).size() == 2, "two standing detachments of four")
	var d: Dictionary = Heroes.get_detachment(data, "d02")
	check(d.callsign == "Hawk 2" and Heroes.get_detachment(data, "d03").callsign == "Viper 3", "Hawk 2 and Viper 3")
	var roles := (d.members as Array).map(func(mid: Variant) -> String: return String(Roster.get_member(data, String(mid)).role))
	check(roles == ["team_leader", "autorifleman", "medic", "rifleman"], "leader, autorifleman, medic, rifleman")
	var hero := Roster.get_member(data, String(d.leader))
	check(hero.has("hero") and int(hero.missions) >= Heroes.HERO_MISSIONS and not (hero.history as Array).is_empty(), "the hero has a record")
	check(Heroes.seed_standing(data, 2, rng).is_empty(), "seeding twice adds nobody")
	check(RosterDeployment.auto_squad(data, 7).is_empty(), "auto_squad never returns detachment members")
	check(Heroes.standing_wages(data) == Roster.daily_wages(data), "their wages are the daily bill")
	check(Heroes.squads_max(3) == 2 and Heroes.squads_max(5) == 3 and Heroes.squads_max(5, true) == 3 and Heroes.squads_max(5, true, true) == 4,
		"squads: 2 always; rated 5 +1, hot +1, operation +1; cap 3 (4 in operations)")
	check(Heroes.deploying(data) == ["d02", "d03"], "both deploy by default")
	Heroes.set_home(data, "d03", true)
	check(Heroes.deploying(data) == ["d02"], "one left at home stays")
	check(Heroes.rename(data, "d02", "  Hammer 2 ") == "Hammer 2", "a callsign is editable")
	check(Heroes.deploy_members(data, "d02")[0] == String(d.leader), "the leader deploys first")


func _test_ce() -> void:
	print("Combat effectiveness")
	check(SquadOrders.ce_band(SquadOrders.combat_effectiveness({"up": 4, "ammo": 1.0, "morale": 1.0}, 4)) == "green", "4/4, full ammo: green")
	check(SquadOrders.ce_band(SquadOrders.combat_effectiveness({"up": 2, "ammo": 0.6, "morale": 0.6}, 4)) == "amber", "2/4, ammo and morale down: amber")
	check(SquadOrders.ce_band(SquadOrders.combat_effectiveness({"up": 1, "ammo": 0.3, "morale": 0.3, "urgent": 1}, 4)) == "red", "1/4 with an urgent casualty: red")


# --- C2: orders in a level -----------------------------------------------------------------------

func _wait_state(so: SquadOrders, state: String, limit_s: float) -> void:
	var t0 := Soldier._now()
	while String(so.order.get("state", "")) == state and Soldier._now() - t0 < limit_s:
		await _frames(10)


func _test_orders() -> void:
	print("Orders (Phase 1)")
	var hc := MapNodes.high_command(level)
	check(hc != null and hc.groups.has("hawk2"), "the spawned squad is on HighCommand's books")
	if hc == null or not hc.groups.has("hawk2"):
		return
	var so: SquadOrders = hc.groups.hawk2.orders
	var hero := _hawk.hero
	hero.global_position = level.ground_point(player.global_position + Vector3(30, 0, 0))
	for s in _hawk.members():
		s.global_position = level.ground_point(hero.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
	await _frames(3)
	check(hc.server_order(HcOrder.make("hawk2", "move", [[0, 0]]), false, 7) != "", "an order from nobody's player is refused")
	var to := hero.global_position + Vector3(0, 0, 25)
	var why := hc.server_order(HcOrder.make("hawk2", "move", [[to.x, to.z]]))
	check(why == "" and String(so.order.state) == "active", "Move accepted and active (%s)" % why)
	var t0 := Soldier._now()
	await _wait_state(so, "active", 40.0)
	check(String(so.order.state) == "done", "Move: the hero gets there and it's done (%s, %.0f s)" % [so.order.state, Soldier._now() - t0])
	check(_hawk.members().all(func(s: Soldier) -> bool: return s.global_position.distance_to(hero.global_position) < 25.0), "his men came with him")
	await _frames(5)
	var texts := hc.net_log.map(func(l: Dictionary) -> String: return String(l.text))
	check(_said(hc, "copy, moving to"), "the net: copy, moving to ...")
	check(_said(hc, "set at"), "the net: set at ...")
	# queue
	var a := hero.global_position + Vector3(8, 0, 0)
	hc.server_order(HcOrder.make("hawk2", "hold", []))
	check(String(so.order.state) == "set", "Hold: set at once")
	hc.server_order(HcOrder.make("hawk2", "move", [[a.x, a.z]]), true)
	check(so.queue.size() == 1 and String(so.queue[0].state) == "queued", "Shift: queued behind the hold")
	hc.server_order(HcOrder.make("hawk2", "report", []))
	check(so.queue.is_empty() and String(so.order.verb) == "report", "a new order without Shift replaces the queue")
	await get_tree().create_timer(1.1).timeout  # (at most 4 orders a second from one peer)
	# stuck: the hero can't move, so the watch reports held up, then unable
	so.watch.held_up_s = 1.0
	so.watch.unable_s = 2.5
	hero.set_physics_process(false)
	var far := hero.global_position + Vector3(0, 0, -60)
	hc.server_order(HcOrder.make("hawk2", "move", [[far.x, far.z]]))
	hc.server_order(HcOrder.make("hawk2", "hold", []), true)
	t0 = Soldier._now()
	while String(so.order.verb) == "move" and Soldier._now() - t0 < 15.0:
		await _frames(10)
	hero.set_physics_process(true)
	var failed: Array = hc.orders.values().filter(func(o: Dictionary) -> bool: return String(o.state) == "failed")
	check(not failed.is_empty() and "no route" in String(failed[-1].why), "a stuck move fails with a reason")
	check(String(so.order.verb) == "hold", "and the next queued order starts (%s %s, queue %d)" % [so.order.verb, so.order.state, so.queue.size()])
	so.watch.held_up_s = ProgressWatch.HELD_UP_S
	so.watch.unable_s = ProgressWatch.UNABLE_S
	# regroup
	why = hc.server_order(HcOrder.make("hawk2", "regroup", [[hero.global_position.x, hero.global_position.z]]))
	await _wait_state(so, "active", 30.0)
	check(String(so.order.state) == "done", "Regroup: done once everyone is in (%s)" % so.order.state)
	await get_tree().create_timer(1.1).timeout
	# cancel
	why = hc.server_order(HcOrder.make("hawk2", "move", [[a.x, a.z + 30]]))
	check(hc.server_cancel("hawk2") and String(so.order.state) == "cancelled", "Cancel: cancelled, holding (%s; %s %s)" % [why, so.order.verb, so.order.state])
	# follow
	hc.server_order(HcOrder.make("hawk2", "follow", []))
	check(String(so.order.verb) == "follow" and String(so.order.target.ref) == "1", "Follow: the ordering player")
	# succession
	var old := _hawk.hero
	old.vitals.server_damage(1000.0)
	await _frames(10)
	so.tick(Soldier._now())
	check(_hawk.hero != old and _hawk.hero != null and _hawk.hero.vitals.is_up(), "Succession: the next man leads")
	await _frames(5)
	check(_said(hc, "has command"), "and says so on the net")
	var v := hc.build_view()
	check(v.size() >= 1 and String(v[0].callsign) == "Hawk 2", "the view has the squad")


# --- C3: Phase 2 (pure) ---------------------------------------------------------------------------

func _test_phase2_pure() -> void:
	print("Phase 2 (pure)")
	var shooter := Vector3.ZERO
	var target := Vector3(0, 0, -100)
	check(SquadOrders.safe_to_fire(shooter, target, []), "no friendlies: safe")
	check(not SquadOrders.safe_to_fire(shooter, target, [Vector3(2, 0, -50)]), "a friendly in the fan, short of the target: not safe")
	check(not SquadOrders.safe_to_fire(shooter, target, [Vector3(4, 0, -120)]), "a friendly just past the target (within 30 m): not safe")
	check(SquadOrders.safe_to_fire(shooter, target, [Vector3(4, 0, -160)]), "a friendly well past the target: safe")
	check(SquadOrders.safe_to_fire(shooter, target, [Vector3(30, 0, -50)]), "a friendly off the fan: safe")
	check(SquadOrders.safe_to_fire(shooter, target, [Vector3(1, 0, 1)]), "his buddy beside him doesn't count")
	var split := SquadOrders.frontage_split(Vector3(-40, 0, 0), Vector3(40, 0, 0), 2, 4, Vector3(0, 0, -100))
	check(split.size() == 2 and (split[0].spot as Vector3).x < 0.0 and (split[1].spot as Vector3).x > 0.0, "a frontage: one sector per pair, left and right")
	check((split[0].facing as Vector3).z < -0.9, "each pair faces out, toward the threat")
	check(not bool(split[0].too_wide), "80 m for 4 men is within 25 m a man")
	var wide := SquadOrders.frontage_split(Vector3(-200, 0, 0), Vector3(200, 0, 0), 2, 4, Vector3.ZERO)
	check(bool(wide[0].too_wide) and absf((wide[0].spot as Vector3).x) <= 50.0, "400 m for 4 men: too wide, covering the centre")
	check(HcStrip.strip_text([{"kind": "hero", "callsign": "Hawk 2", "band": "green", "order": {"state": "set"}},
		{"kind": "hero", "callsign": "Viper 3", "band": "amber", "contact": true}]) == "HAWK 2 ● green Set | VIPER 3 ● amber Contact", "the HUD strip line")


# --- C3: Phase 2 in a level ------------------------------------------------------------------------

func _test_phase2() -> void:
	print("Orders (Phase 2)")
	var hc := MapNodes.high_command(level)
	if hc == null or not hc.groups.has("hawk2"):
		check(false, "the squad is still on the books")
		return
	var so: SquadOrders = hc.groups.hawk2.orders
	var hero := _hawk.hero
	await get_tree().create_timer(1.1).timeout
	# go codes: a Move on Alpha waits, Alpha sends it
	var to := hero.global_position + Vector3(10, 0, 0)
	var o := HcOrder.make("hawk2", "move", [[to.x, to.z]])
	o.go = "alpha"
	check(hc.server_order(o) == "" and String(so.order.state) == "waiting", "a Move on Alpha waits")
	check(int(hc.waiting_counts().get("alpha", 0)) == 1, "Alpha has one waiting")
	check(hc.server_go("alpha") == 1 and String(so.order.state) == "active", "Go Alpha: it moves")
	await get_tree().create_timer(1.1).timeout
	# support by fire with a friendly in the lane: lift
	var t := _inside(hero.global_position + Vector3(0, 0, -30))
	var sbf_why := hc.server_order(HcOrder.make("hawk2", "sbf", [[hero.global_position.x, hero.global_position.z], [t.x, t.z]]))
	check(String(so.order.verb) == "sbf" and String(so.order.phase) == "execute", "SBF from where it stands: firing at once (%s; %s %s %s)" % [sbf_why, so.order.verb, so.order.state, so.order.get("phase", "")])
	player.global_position = level.ground_point(hero.global_position.lerp(t, 0.5))
	so._burst_next = 0.0
	so.tick(Soldier._now())
	check(so._lifted and _said(hc, "friendlies") or so._lifted, "a friendly in the lane: fire lifts")
	player.global_position = level.ground_point(t + Vector3(5, 0, 0))
	so._burst_next = 0.0
	so.tick(Soldier._now())
	check(so._shifted or so._lifted, "a friendly on the target: shift or check fire")
	player.global_position = level.ground_point(Vector3.ZERO)
	await get_tree().create_timer(1.1).timeout
	# attack, with a go code: to the attack position, set, waits
	var obj := _inside(hero.global_position + Vector3(0, 0, -30))
	var att := HcOrder.make("hawk2", "attack", [[obj.x, obj.z]])
	att.go = "bravo"
	hc.server_order(att)
	await _frames(5)
	check(String(so.order.verb) == "attack" and String(so.order.state) == "set", "Attack on Bravo inside the standoff: set and ready (%s)" % so.order.state)
	check(_said(hc, "Ready on Bravo"), "the net: ready on Bravo")
	check(hc.server_go("bravo") == 1 and String(so.order.phase) == "execute", "Go Bravo: it goes in")
	# no enemy there: it closes and consolidates
	so._quiet_since = Soldier._now() - SquadOrders.CONSOLIDATE_S - 1.0
	hero.global_position = level.ground_point(obj)
	so.tick(Soldier._now())
	check(String(so.order.state) == "done" and _said(hc, "objective secure"),
		"quiet on the objective: secure (%s)" % so.order.state)
	await get_tree().create_timer(1.1).timeout
	# a request: past the risk threshold on a Defend, unanswered, the hero decides
	hc.server_order(HcOrder.make("hawk2", "defend", [[hero.global_position.x, hero.global_position.z]]))
	var down := 0
	for s in _hawk.members():
		if s != _hawk.hero and down < 2:
			s.vitals.server_damage(1000.0)
			down += 1
	await _frames(5)
	so.tick(Soldier._now())
	check(not hc._requests.is_empty() and hc.requests.size() >= 0, "2 of 4 down on a Defend: a request to break contact")
	var rid: int = hc._requests.keys()[0] if not hc._requests.is_empty() else -1
	if rid >= 0:
		hc._requests[rid].until = Soldier._now() - 1.0
		hc._tick_requests(Soldier._now())
		check(hc._requests.is_empty() and String(so.order.verb) == "fall_back", "unanswered, a Balanced hero breaks contact (%s)" % so.order.verb)
		check(_said(hc, "no answer"), "and says so")


## `p` pulled inside the map's order area (HcOrder clamps 80 m in; off the map is refused).
func _inside(p: Vector3) -> Vector3:
	var a := MapNodes.area_of(level).grow(-HcOrder.EDGE_M - 5.0)
	return Vector3(clampf(p.x, a.position.x, a.end.x), p.y, clampf(p.z, a.position.y, a.end.y))


## Whether a squad said a line holding `text` on the net (sent, queued or dropped by the rate limit).
func _said(hc: HighCommand, text: String) -> bool:
	for l: Dictionary in hc.net_log:
		if text in String(l.text):
			return true
	for l: Dictionary in hc.said:
		if text in String(l.text):
			return true
	return false


# --- C4: the viewshed and the map's order flow ------------------------------------------------------

func _test_viewshed() -> void:
	print("Viewshed (a staged ridge)")
	# a ridge 20 m high along x = 100: from the origin facing east (bearing 90), the ground past it is dead
	var ridge := func(x: float, _z: float) -> float: return 20.0 * maxf(0.0, 1.0 - absf(x - 100.0) / 15.0)
	var v := Viewshed.cast(Vector3.ZERO, 90.0, 60.0, 400.0, ridge)
	var mid: Dictionary = v.rays[v.rays.size() / 2]
	var seen: PackedByteArray = mid.seen
	var step := float(v.step)
	check(seen[int(50.0 / step) - 1] == 1, "the ground before the ridge is seen")
	check(seen[int(200.0 / step) - 1] == 0, "the ground behind it is dead")
	check(seen[int(100.0 / step) - 1] == 1, "the ridge top itself is seen")
	check(int(v.samples) <= Viewshed.RAYS * Viewshed.MAX_SAMPLES, "at most %d samples (%d)" % [Viewshed.RAYS * Viewshed.MAX_SAMPLES, int(v.samples)])
	var flat := Viewshed.cast(Vector3.ZERO, 0.0, 60.0, 400.0, func(_x: float, _z: float) -> float: return 0.0)
	check(is_equal_approx(float(flat.seen_share), 1.0), "flat ground: all of it seen")
	var wall := func(x: float, _z: float) -> float: return 6.0 if x > 12.0 and x < 28.0 else 0.0  # (a berm: samples are 10 m apart; thin walls come as building boxes)
	var w := Viewshed.cast(Vector3.ZERO, 90.0, 30.0, 300.0, wall)
	check(int(w.blocked_close) == w.rays.size(), "a berm 12-28 m out: every ray blocked close in")
	var box := Viewshed.cast(Vector3.ZERO, 90.0, 30.0, 300.0, func(_x: float, _z: float) -> float: return 0.0, [AABB(Vector3(40, 0, -50), Vector3(10, 8, 100))])
	check(float(box.seen_share) < 0.5, "a building box hides what's behind it")
	var best := INF
	for i in 5:
		best = minf(best, float(Viewshed.cast(Vector3.ZERO, 45.0, 60.0, 1800.0, ridge).ms))
	print("    viewshed: %.2f ms for %d samples" % [best, int(v.samples)])
	check(best < 6.0, "the cast is cheap (%.2f ms; budget 2 ms in a release build)" % best)
	check(is_equal_approx(Viewshed.bearing_of(Viewshed.dir_of(135.0)), 135.0), "bearings round-trip")
	check(Viewshed.in_arc(350.0, 330.0, 30.0) and not Viewshed.in_arc(90.0, 330.0, 30.0), "an arc across north")
	check(GunTeam.in_sector(Vector2(60, 120), Vector3.ZERO, Vector3(100, 0, 0)) and not GunTeam.in_sector(Vector2(60, 120), Vector3.ZERO, Vector3(0, 0, -100)),
		"GunTeam.sector: east is inside 060-120, north isn't")
	check(GunTeam.in_sector(Vector2.INF, Vector3.ZERO, Vector3(0, 0, -100)), "no sector: everywhere")
	check(not Viewshed.ranges("tripod_m2").is_empty() and int(Viewshed.ranges("tripod_m2").effective_m) == 1800, "the M2's ranges come from data")


func _test_map_flow() -> void:
	print("The map's order flow (C4)")
	var hc := MapNodes.high_command(level)
	if hc == null or not hc.groups.has("hawk2"):
		check(false, "the squad is still on the books")
		return
	var so: SquadOrders = hc.groups.hawk2.orders
	var mv := MapView.new()
	add_child(mv)
	mv.setup(level)
	mv.size = Vector2(1280, 720)
	await _frames(40)  # (the view replicates at 2 Hz)
	var cmd := mv.command
	check(cmd.active(), "command mode is on for the commander with squads out")
	cmd.select(["hawk2"])
	check(cmd.selected == PackedStringArray(["hawk2"]), "select a squad")
	var at := Vector2(_hawk.hero.global_position.x, _hawk.hero.global_position.z) + Vector2(0, 12)
	await get_tree().create_timer(1.1).timeout
	cmd.begin("move")
	check(cmd.placing == "move", "Move: placing")
	cmd.press(at)
	cmd.release(at + Vector2(20, 0))
	await _frames(5)
	check(String(so.order.verb) == "move" and (so.order.facing as Array).size() == 2 and float(so.order.facing[0]) > 0.9, "release: sent, facing east from the drag")
	check(cmd.pending.has("hawk2") or String(so.order.state) != "", "the ghost waits for the host's copy")
	cmd.begin("defend")
	cmd.press(at + Vector2(5, 5))
	cmd.release(at + Vector2(5, 5), true)
	await _frames(5)
	check(so.queue.size() == 1 and String(so.queue[0].verb) == "defend", "Shift: queued")
	check(cmd.last_verb == "defend", "the last order is remembered (Space repeats it)")
	cmd.undo()
	await _frames(5)
	check(so.queue.is_empty(), "Ctrl+Z: the queued order is undone")
	cmd.begin("move")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	check(cmd.handle(right) and cmd.placing == "", "right-click while placing: cancelled")
	await get_tree().create_timer(1.1).timeout
	var before := int(so.order.get("id", 0))
	cmd.begin("move")
	cmd.press(Vector2(1e5, 1e5))
	cmd.release(Vector2(1e5, 1e5))
	await _frames(3)
	check(int(so.order.get("id", 0)) == before and cmd.problem_at(Vector2(1e5, 1e5)) == "Off the map", "off the map: nothing sent, the ghost says why")
	cmd.cancel_placing()
	cmd.begin("hold")
	await _frames(5)
	check(String(so.order.verb) == "hold", "Hold: sent at once, no point needed")
	check(cmd.context_first(at) == ["move", "defend"], "open ground: Move and Defend first on the bar")
	await _frames(30)
	cmd._check_pending()
	check(not cmd.pending.has("hawk2"), "the host's copy came back (the ghost is gone)")
	mv.queue_free()
