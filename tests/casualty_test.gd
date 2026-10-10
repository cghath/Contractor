extends Node
## Headless AI casualty-care scenarios (W7): care order, medic choice, medic loadouts,
## self-tourniquet and "Medic!", treatment through Soldier._server_treat, the stopgap revive,
## enemies ignoring unconscious foes except while clearing, dead bodies staying and being
## carried, the body cap, a soak where the squad follows the lead around the compound, and
## an engagement where a downed squadmate is reached and treated in time.
##   <voxel godot exe> --headless --path . res://tests/casualty_test.tscn
## Exits with the number of failures.

## Proposed time limits for the engagement test (seconds).
const TOURNIQUET_WITHIN_S := 25.0
const TREATED_WITHIN_S := 60.0
## Where the lead stands in the engagement: beside the formation's way to Delta at (-3, 15).
const ENGAGEMENT_LEAD := Vector3(8, 0.1, 24)
## Proposed: with a player standing on the direct route, the medic still reaches the casualty
## within this long; a responder that can't get closer at all hands the casualty on.
const BLOCKED_REACH_S := 15.0
## The soak: how many times the lead walks the route, at what pace, how much faster than
## real time it runs, and the least simulated time it must take (about two minutes a lap).
const SOAK_LAPS := 2
const LEADER_SPEED := 3.0
const SOAK_SCALE := 3.0
const SOAK_MIN_S := 200.0
## A squadmate further than this from its formation spot that moved less than STUCK_MOVE_M in
## STUCK_WINDOW_S simulated seconds is stuck.
const STUCK_FAR_M := 5.0
const STUCK_MOVE_M := 0.6
const STUCK_WINDOW_S := 8

var failures := 0
var level: CompoundLevel
var player: Soldier
## Simulated incoming fire: while set, every friendly AI keeps hearing fire from `_threat`.
var _firing := false
var _threat := Vector3.ZERO
## The lead's route (soak): points to walk through, and the simulated time spent walking.
var _route := PackedVector3Array()
var _route_index := 0
var _sim_s := 0.0


func _ready() -> void:
	GameState.zone_id = "test_casualty" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(420.0, true, false, true).timeout.connect(func() -> void:
		print("CASUALTY TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test moves the lead by hand
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	_remove_hostiles()
	_place(player, Vector3(0, 0.1, 22))
	await _seconds(1.0)
	await _out_of_contact()  # they may have seen the hostiles before they went
	_test_plan_care()
	_test_loadouts()
	await _test_medic_choice()
	await _test_dead_check()
	await _test_body_cap()
	await _test_soak()
	await _test_self_tourniquet()
	await _test_engagement()
	await _test_dead_bodies()
	await _test_downed_player()
	GameState.delete_save()
	print("CASUALTY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _physics_process(delta: float) -> void:
	if _firing:
		for s: Soldier in _squad():
			s.threat_pos = _threat
			s.threat_time = Soldier._now()
	if _route_index < _route.size():
		_sim_s += delta
		var to := _route[_route_index] - player.global_position
		to.y = 0.0
		if to.length() < 0.2:
			_route_index += 1
			return
		var step := minf(LEADER_SPEED * delta, to.length())
		player.global_position += to.normalized() * step
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))


# --- Pure rules -------------------------------------------------------------

func _test_plan_care() -> void:
	print("Care order")
	var tasks: Array[Dictionary] = [
		{"part": Vitals.FOREARM_L, "kind": "graze", "item": &"pressure_bandage"},
		{"part": Vitals.TORSO, "kind": "pain", "item": &"morphine"},
		{"part": Vitals.SHIN_R, "kind": "fracture", "item": &"splint"},
		{"part": Vitals.CHEST, "kind": "chest", "item": &"chest_seal"},
		{"part": Vitals.THIGH_R, "kind": "arterial", "item": &"tourniquet"},
		{"part": Vitals.FACE, "kind": "airway", "item": &"npa"},
		{"part": Vitals.NECK, "kind": "junctional", "item": &"hemostatic_gauze"},
	]
	var safe := _kinds(SquadAI.plan_care(tasks, false, true))
	check(safe == ["arterial", "airway", "chest", "junctional", "graze", "fracture", "pain"],
		"once safe: massive bleeding, airway, chest seal, bandages and gauze, splint, then morphine (%s)" % [safe])
	var under_fire := _kinds(SquadAI.plan_care(tasks, true, true))
	check(under_fire == ["arterial"], "under fire: only the tourniquet for massive bleeding (%s)" % [under_fire])
	var out := _kinds(SquadAI.plan_care(tasks, false, false))
	check("pain" not in out and out.size() == 6, "no morphine for an unconscious casualty (%s)" % [out])


func _test_loadouts() -> void:
	print("Medic loadouts")
	var kit := {}
	for pair: Array in Roles.kit(Roles.MEDIC):
		kit[pair[0]] = int(kit.get(pair[0], 0)) + int(pair[1])
	var extras: Array[StringName] = [&"tourniquet", &"hemostatic_gauze", &"chest_seal", &"splint", &"morphine", &"npa"]
	check(kit.get(&"trauma_kit", 0) == 1 and extras.all(func(id: StringName) -> bool: return kit.get(id, 0) >= 1) and kit.get(&"tourniquet", 0) >= 2,
		"the medic kit: a trauma kit plus extra tourniquets, gauze, chest seals, splints, morphine and NPAs (%s)" % [kit])
	var others_ok := true
	for role in Roles.ids():
		if role == Roles.MEDIC:
			continue
		var ids := Roles.kit(role).map(func(pair: Array) -> StringName: return pair[0])
		if &"ifak" not in ids or &"trauma_kit" in ids:
			others_ok = false
	check(others_ok, "every other role carries an IFAK and no trauma kit")
	var golf := _ai("Golf")
	check(golf.role == Roles.MEDIC and golf.inventory.count_of(&"trauma_kit") == 1 and golf.inventory.count_of(&"chest_seal") >= 1
		and golf.inventory.count_of(&"npa") >= 1, "AI medics spawn in it (Golf)")
	check(_ai("Echo").inventory.count_of(&"ifak") == 1, "AI riflemen and the rest spawn with an IFAK (Echo)")


# --- Medic choice and targeting (brains paused) -------------------------------

func _test_medic_choice() -> void:
	print("Who answers")
	_freeze()
	var delta := _ai("Delta")  # team B; buddy Echo; team medic Golf
	var echo := _ai("Echo")
	var golf := _ai("Golf")
	var charlie := _ai("Charlie")  # team A's medic
	var foxtrot := _ai("Foxtrot")
	var saved := _positions()
	_place(delta, Vector3(10, 0.1, 26))
	_place(echo, Vector3(14, 0.1, 26))
	_place(foxtrot, Vector3(11, 0.1, 27))
	_place(charlie, Vector3(-6, 0.1, 26))
	_place(golf, Vector3(6, 0.1, 27))
	check(SquadAI.responder_for(delta) == golf, "the fire team's medic answers first (%s)" % _name(SquadAI.responder_for(delta)))
	_place(golf, Vector3(-30, 0.1, -10))
	check(SquadAI.responder_for(delta) == echo, "with the medic far away, the battle buddy answers (%s)" % _name(SquadAI.responder_for(delta)))
	var echo_ai := SquadAI.of(echo)
	echo_ai.care = SquadAI.Care.GUARD
	echo_ai.casualty = foxtrot
	check(SquadAI.responder_for(delta) == charlie, "with the buddy busy too, the other team's medic (%s)" % _name(SquadAI.responder_for(delta)))
	SquadAI.of(charlie).care = SquadAI.Care.TREAT
	SquadAI.of(charlie).casualty = echo
	SquadAI.of(golf).care = SquadAI.Care.TREAT
	SquadAI.of(golf).casualty = echo
	check(SquadAI.responder_for(delta) == foxtrot, "with every medic busy, the nearest free squadmate (%s)" % _name(SquadAI.responder_for(delta)))
	for ai: SquadAI in [echo_ai, SquadAI.of(charlie), SquadAI.of(golf)]:
		ai.care = SquadAI.Care.NONE
		ai.casualty = null
	_place(golf, Vector3(6, 0.1, 27))
	golf.vitals.server_damage(500.0)
	check(SquadAI.responder_for(delta) == echo, "with the team's medic down, the buddy answers (%s)" % _name(SquadAI.responder_for(delta)))
	check(SquadAI.medic_for(delta, [&"trauma_kit"]) == charlie, "and the other team's medic is the one to take over (%s)" % _name(SquadAI.medic_for(delta, [&"trauma_kit"])))
	golf.vitals.server_reset_health()
	check(SquadAI.medic_for(delta, [&"trauma_kit"]) == golf, "a carer's call for a trauma kit goes to the team's medic once it's up again")
	var kit := golf.inventory.remove_one(&"trauma_kit")
	check(SquadAI.medic_for(delta, [&"trauma_kit"]) == charlie, "unless it doesn't have one")
	if kit:
		golf.inventory.take(&"trauma_kit")
	check(SquadAI.of(golf)._can_revive() and not SquadAI.of(echo)._can_revive() and not SquadAI.of(foxtrot)._can_revive(),
		"only a medic with a trauma kit uses the stopgap revive")
	_restore(saved)
	_unfreeze()
	await _seconds(0.5)


func _test_dead_check() -> void:
	print("Unconscious foes")
	_freeze()
	var saved := _positions()
	var foxtrot := _ai("Foxtrot")
	var i := 0
	for s: Soldier in _squad():
		if s != foxtrot:
			_place(s, Vector3(40 + i, 0.1, 55))
			i += 1
	_place(player, Vector3(45, 0.1, 58))
	var hostile := level.spawn_soldier({"name": "CheckHostile", "faction": "hostile", "variant": "urban", "pos": Vector3(-15, 0.1, -15),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	var ai := SquadAI.of(hostile)
	ai.set_physics_process(false)
	hostile.move_input = Vector2.ZERO
	_place(foxtrot, Vector3(-11, 0.1, -15))
	foxtrot.vitals.server_damage(500.0)
	await _frames(2)
	ai.intent = SquadAI.Intent.PATROL
	ai._advancing = false
	check(foxtrot.vitals.downed and ai._find_target() == null, "a patrolling enemy ignores an unconscious foe 4 m away")
	ai._advancing = true
	check(ai._find_target() == foxtrot, "but dead-checks him while assaulting through the position")
	ai._advancing = false
	ai.intent = SquadAI.Intent.INVESTIGATE
	check(ai._find_target() == foxtrot, "and while clearing (searching where contact was)")
	_place(foxtrot, Vector3(-15, 0.1, -15 + SquadAI.DEAD_CHECK_M + 3.0))
	await _frames(2)
	check(ai._find_target() == null, "but not from further than %.0f m" % SquadAI.DEAD_CHECK_M)
	foxtrot.vitals.server_reset_health()
	_place(foxtrot, Vector3(40, 0.1, 60))
	# In play: an advancing hostile keeps the body targeted and actually shoots it. The body
	# is a stand-in friendly (a squadmate killed here would stay dead for the later tests).
	var victim := level.spawn_soldier({"name": "CheckVictim", "faction": "friendly", "variant": "urban", "pos": Vector3(-11, 0.1, -15),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	SquadAI.of(victim).set_physics_process(false)
	_place(victim, Vector3(-11, 0.1, -15))
	victim.vitals.server_damage(500.0)
	await _frames(2)
	var wounds_before := victim.vitals.wound_list().size()
	ai._dead_check = null
	ai.target = null
	ai.intent = SquadAI.Intent.FIGHT
	ai._advancing = true
	ai._advance_anchor = Vector3(-15, 0.1, -15)
	ai._no_los_s = 0.0
	ai._last_contact = Soldier._now()
	hostile.threat_pos = victim.global_position
	hostile.threat_time = Soldier._now()
	var contact_at := ai._last_contact
	check(victim.vitals.downed, "a stand-in body lies unconscious 4 m from an advancing hostile (%s)" % victim.vitals.condition_text())
	ai._cover_cd = 1000.0  # stays where it stands, 4 m off, instead of looking for cover
	ai.set_physics_process(true)
	var spotted := await _wait_until(func() -> bool: return ai.target == victim, 3.0)
	check(spotted, "an advancing hostile picks the unconscious body for a dead-check")
	ai._advancing = false  # the advance ends (it reached cover, say): the dead-check goes on
	await _seconds(SquadAI.SCAN_S * 3.0)
	check(ai.target == victim or victim.vitals.is_dead(), "and keeps it targeted over the next scans (%s)" % _name(ai.target))
	var shot := await _wait_until(func() -> bool:
		return victim.vitals.is_dead() or victim.vitals.wound_list().size() >= wounds_before + 3, 12.0)
	check(shot, "shooting it (%s, %d -> %d wounds)" % [victim.vitals.condition_text(), wounds_before, victim.vitals.wound_list().size()])
	check(ai._last_contact <= contact_at + 0.01, "a dead-check doesn't count as contact")
	ai.set_physics_process(false)
	hostile.queue_free()
	if is_instance_valid(victim):
		if victim.vitals.is_dead():
			victim.server_remove_body()
		else:
			victim.queue_free()
	_restore(saved)
	_place(player, Vector3(0, 0.1, 22))
	_unfreeze()
	await _seconds(0.5)


func _test_body_cap() -> void:
	print("Body cap")
	var before := _bodies().size()
	var died := [0]
	Soldier.body_cap = before + 2
	var dead: Array[Soldier] = []
	for k in 3:
		var s := level.spawn_soldier({"name": "CapHostile%d" % k, "faction": "hostile", "variant": "urban", "pos": Vector3(-30 - k * 3, 0.1, -60),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
		s.died_for_good.connect(func(_who: Soldier) -> void: died[0] += 1)
		dead.append(s)
	await _frames(2)
	var items_before := get_tree().get_nodes_in_group(WorldItem.GROUP).size()
	for s in dead:
		s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
		await _seconds(0.05)
	check(died[0] == 3, "died_for_good fires for each (%d)" % died[0])
	check(not is_instance_valid(dead[0]) or dead[0].is_queued_for_deletion(), "past the cap the oldest body goes")
	check(is_instance_valid(dead[1]) and not dead[1].is_queued_for_deletion() and is_instance_valid(dead[2]) and not dead[2].is_queued_for_deletion(),
		"the newer ones stay")
	await _frames(2)
	check(get_tree().get_nodes_in_group(WorldItem.GROUP).size() > items_before, "the removed body's gear stays on the ground")
	Soldier.body_cap = Soldier.MAX_BODIES
	for s in dead:
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			s.server_remove_body()
	await _frames(2)


# --- Soak --------------------------------------------------------------------

func _test_soak() -> void:
	print("Soak: the squad follows the lead around and through the compound")
	var map := player.get_world_3d().navigation_map
	var waypoints: Array[Vector3] = [Vector3(0, 0, 22), Vector3(0, 0, 14), Vector3(-12, 0, 8), Vector3(-14, 0, -14), Vector3(0, 0, -16),
		Vector3(14, 0, -14), Vector3(14, 0, 8), Vector3(0, 0, 0), Vector3(0, 0, -8), Vector3(0, 0, 2), Vector3(0, 0, 23),
		Vector3(26, 0, 26), Vector3(26, 0, -26), Vector3(-26, 0, -26), Vector3(-26, 0, 26), Vector3(0, 0, 26)]
	var route := PackedVector3Array()
	for lap in SOAK_LAPS:
		for k in range(1, waypoints.size()):
			route.append_array(NavigationServer3D.map_get_path(map, waypoints[k - 1], waypoints[k], true))
	_place(player, Vector3(0, 0.1, 22))
	var squad := level.squad_for(&"friendly")
	var history := {}  # name -> Array of positions, one per simulated second
	var stuck := {}
	var fell := {}
	var died := {}
	var worst := {}
	Engine.physics_ticks_per_second = roundi(60 * SOAK_SCALE)
	Engine.time_scale = SOAK_SCALE
	var real_start := Time.get_ticks_msec()
	var said_from := level.callouts.sent.size()
	_sim_s = 0.0
	_route = route
	_route_index = 0
	var seconds := 0
	while _route_index < _route.size() and _sim_s < SOAK_MIN_S * 2.0:
		await _seconds(1.0)
		seconds += 1
		for s: Soldier in _squad():
			var who := String(s.name)
			if s.global_position.y < -2.0:
				fell[who] = true
			if not s.vitals.is_up():
				if not died.has(who):
					print("    %s went down at %s after %.0f s: %s; callouts %s" % [who, s.global_position, _sim_s, _wound_kinds(s), _lines(said_from)])
				died[who] = s.vitals.condition_text()
			var list: Array = history.get(who, [])
			list.append(s.global_position)
			history[who] = list
			var far := _flat(s.global_position, squad.follow_point(s))
			worst[who] = maxf(float(worst.get(who, 0.0)), far)
			if list.size() > STUCK_WINDOW_S and far > STUCK_FAR_M and _flat(list[-1], list[-1 - STUCK_WINDOW_S]) < STUCK_MOVE_M:
				var ai := SquadAI.of(s)
				stuck[who] = "%s at %s (%s) slot %s dest %s path %d/%d next %s input %s vel %s lead %s" % [who, s.global_position, s.ai_status, squad.follow_point(s),
					ai._destination, ai._path_index, ai._path.size(), ai._path[ai._path_index] if ai._path_index < ai._path.size() else Vector3.INF,
					s.move_input, s.velocity, player.global_position]
	var walked := _sim_s
	await _seconds(12.0)  # let them settle in formation at the end
	var settled := _squad().filter(func(s: Soldier) -> bool: return _flat(s.global_position, squad.follow_point(s)) > 4.0)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_route = PackedVector3Array()
	var real_s := (Time.get_ticks_msec() - real_start) / 1000.0
	print("    %.0f s simulated in %.0f s real; furthest behind: %s" % [walked + 12.0, real_s, worst])
	check(walked >= SOAK_MIN_S, "the lead walked the route %d times, %.0f simulated seconds" % [SOAK_LAPS, walked])
	check(stuck.is_empty(), "nobody got stuck on the way (%s)" % [stuck.values()])
	check(fell.is_empty(), "nobody fell out of the world (%s)" % [fell.keys()])
	check(died.is_empty(), "nobody died or went down (%s)" % [died])
	check(settled.is_empty(), "everyone is back in formation at the end (%s)" % [settled.map(func(s: Soldier) -> String: return "%s %s" % [s.name, s.ai_status])])


# --- Self-care and the medic ---------------------------------------------------

func _test_self_tourniquet() -> void:
	print("Self-tourniquet under fire, then the medic")
	_place(player, Vector3(0, 0.1, 24))
	player.rotation.y = 0.0
	await _seconds(4.0)
	var alpha := _ai("Alpha")
	var charlie := _ai("Charlie")
	alpha.inventory.take(&"tourniquet")
	# Nothing but the tourniquet: no stopgap kit and no bandages, so what he can't do himself
	# (the seeded hit below always opens a vein too) waits for the medic.
	var taken: Array[StringName] = []
	for id: StringName in [&"ifak", &"pressure_bandage", &"hemostatic_gauze"]:
		while alpha.inventory.remove_one(id):
			taken.append(id)
	var morphine_before := charlie.inventory.count_of(&"morphine")
	var splints_before := charlie.inventory.count_of(&"splint")
	var bandages_before := charlie.inventory.count_of(&"pressure_bandage")
	_threat = Vector3(0, 1.5, -2)
	_hold_fire(true)
	_firing = true
	await _seconds(0.6)
	var sent_from := level.callouts.sent.size()
	_shoot_femoral(alpha, 3)
	check(alpha.vitals.is_up() and _bleeding(alpha, "arterial"), "Alpha takes a femoral hit and stays conscious (%s)" % [_wound_kinds(alpha)])
	var statuses := {}
	var stopped := await _wait_until(func() -> bool:
		statuses[alpha.ai_status] = true
		return not _bleeding(alpha, "arterial"), 10.0)
	check(stopped and alpha.inventory.count_of(&"tourniquet") == 0 and statuses.has("Treating self"),
		"under fire, he puts his own tourniquet on at once (%s, %s)" % [alpha.ai_status, statuses.keys()])
	var needs := _kinds(alpha.vitals.care_needed())
	var call := await _wait_until(func() -> bool: return _said(sent_from, "Alpha", &"medic"), 8.0)
	check("venous" in needs, "the seeded hit leaves a venous bleed he has no bandage for (%s)" % [needs])
	check(call, "and he calls \"Medic!\" for what he can't fix himself (%s)" % [_lines(sent_from)])
	_firing = false
	var helped := await _wait_until(func() -> bool:
		return alpha.vitals.care_needed().is_empty(), 40.0)
	check(helped and (charlie.inventory.count_of(&"morphine") < morphine_before or charlie.inventory.count_of(&"splint") < splints_before
		or charlie.inventory.count_of(&"pressure_bandage") < bandages_before),
		"once it's quiet, his team's medic Charlie treats him (%s left; Charlie: %s)" % [_kinds(alpha.vitals.care_needed()), charlie.ai_status])
	check(_said(sent_from, "Charlie", &"moving_to") and _said(sent_from, "Charlie", &"treating"),
		"Charlie answers: \"Moving to Alpha\", then \"Treating Alpha\" (%s)" % [_lines(sent_from)])
	for id in taken:
		alpha.inventory.take(id)
	await _out_of_contact()
	_hold_fire(false)


# --- Engagement ---------------------------------------------------------------

func _test_engagement() -> void:
	print("Engagement: a squadmate down in the open under fire")
	# The lead stands off to the side, clear of the medic's way from the formation to Delta
	# (a player in the way is _test_blocked_route's job).
	_place(player, ENGAGEMENT_LEAD)
	player.rotation.y = 0.0
	await _seconds(3.0)
	var delta := _ai("Delta")
	var golf := _ai("Golf")
	var counts := {}
	for id: StringName in [&"tourniquet", &"pressure_bandage", &"smoke_grenade", &"trauma_kit", &"splint"]:
		counts[id] = golf.inventory.count_of(id)
	_threat = Vector3(-3, 1.5, 0)
	_hold_fire(true)
	_firing = true
	await _seconds(0.6)
	var sent_from := level.callouts.sent.size()
	_place(delta, Vector3(-3, 0.1, 15))
	_shoot_femoral(delta, 5)
	delta.vitals.rng.seed = 9
	delta.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	var sim := 0.0
	while not delta.vitals.downed and sim < 400.0:
		delta.vitals.server_advance(1.0)
		sim += 1.0
	var start := Soldier._now()
	check(delta.vitals.downed and _bleeding(delta, "arterial"), "Delta bleeds out from his femoral artery until he's unconscious (%s, %s)" % [delta.vitals.condition_text(), _wound_kinds(delta)])
	var seen := {"drag": false, "status": {}}
	var other_open_at_tq := []
	var tq := await _wait_until(func() -> bool:
		if delta.carried_by == golf and golf.carry_mode == Soldier.DRAG:
			seen.drag = true
		seen.status[golf.ai_status] = true
		if not _bleeding(delta, "arterial"):
			other_open_at_tq.append(delta.vitals.care_needed().filter(func(t: Dictionary) -> bool: return t.kind != "pain").size())
			return true
		return false, TOURNIQUET_WITHIN_S)
	var tq_s := Soldier._now() - start
	check(tq and golf.inventory.count_of(&"tourniquet") < counts[&"tourniquet"],
		"his team's medic Golf reaches him and puts a tourniquet on under fire in %.0f s (limit %.0f; %s)" % [tq_s, TOURNIQUET_WITHIN_S, seen.status.keys()])
	check(golf.inventory.count_of(&"smoke_grenade") < counts[&"smoke_grenade"] and _said(sent_from, "Golf", &"smoke_out"), "Golf throws smoke between him and the threat")
	check(seen.drag, "and drags him into cover")
	check(not other_open_at_tq.is_empty() and other_open_at_tq[0] > 0, "under fire nothing but the tourniquet: his other wounds wait (%s open)" % [other_open_at_tq])
	await _seconds(2.0)
	_firing = false
	var treated := await _wait_until(func() -> bool:
		seen.status[golf.ai_status] = true
		return delta.vitals.is_up() and delta.vitals.care_needed().filter(func(t: Dictionary) -> bool: return t.kind != "pain").is_empty(), TREATED_WITHIN_S)
	var all_s := Soldier._now() - start
	check(treated, "once it's quiet he's patched up and revived within %.0f s (%.0f s; Delta: %s, %s; Golf: %s)" % [TREATED_WITHIN_S, all_s,
		delta.vitals.condition_text(), _kinds(delta.vitals.care_needed()), golf.ai_status])
	check(golf.inventory.count_of(&"pressure_bandage") < counts[&"pressure_bandage"], "the treatment went through _server_treat: Golf's bandages were used on him")
	check(golf.inventory.count_of(&"trauma_kit") < counts[&"trauma_kit"] and seen.status.has("Reviving Delta"),
		"still out with the bleeding controlled, Golf uses the stopgap revive (%s)" % [seen.status.keys()])
	check(_said(sent_from, "Golf", &"moving_to") and _said(sent_from, "Golf", &"treating"), "Golf calls it: \"Moving to Delta\", \"Treating Delta\" (%s)" % [_lines(sent_from)])
	await _out_of_contact()
	_hold_fire(false)


# --- Dead bodies -----------------------------------------------------------------

func _test_dead_bodies() -> void:
	print("Dead friendlies")
	_firing = false
	_place(player, Vector3(0, 0.1, 22))
	await _out_of_contact()
	var echo := _ai("Echo")
	var gone := [false]
	echo.died_for_good.connect(func(_who: Soldier) -> void: gone[0] = true)
	echo.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(3)
	check(gone[0] and is_instance_valid(echo) and not echo.is_queued_for_deletion() and echo.is_in_group(Soldier.DEAD_GROUP),
		"a squadmate killed outright stays as a body (died_for_good still fires)")
	check(echo.collision_layer == 0 and not echo.vitals.is_up(), "lying, and not blocking anyone")
	check(echo.inventory.slots[&"primary"] == &"m110" and echo.inventory.count_of(&"mag_762") > 0, "with his gear still on him")
	var ids := InteractionMenu.actions_for(player, echo).map(func(a: Dictionary) -> StringName: return a.id)
	check(ids == [&"loot", &"carry", &"drag"], "the interaction menu offers Loot, Carry and Drag (%s)" % [ids])
	var carried := await _wait_until(func() -> bool: return is_instance_valid(echo.carried_by) and echo.carried_by.is_ai(), 25.0)
	var bearer := echo.carried_by
	check(carried, "out of contact a squadmate picks his body up (%s)" % (bearer.ai_status if bearer else "nobody"))
	_place(player, Vector3(-8, 0.1, 4))
	await _seconds(10.0)
	check(_flat(echo.global_position, player.global_position) < 12.0, "and carries it after the lead (%.1f m)" % _flat(echo.global_position, player.global_position))
	check(SquadAI.of(echo) != null and echo.ai_status == "Dead", "the roster shows him dead (%s)" % echo.ai_status)
	if is_instance_valid(bearer):
		SquadAI.of(bearer)._end_care()
		SquadAI.of(bearer).set_physics_process(false)  # stop picking it up again while we loot
	await _frames(2)
	_place(player, echo.global_position + Vector3(1.0, 0.1, 0.0))
	var items_before := get_tree().get_nodes_in_group(WorldItem.GROUP).size()
	player._server_loot_body.rpc_id(1, echo.get_path())
	await _frames(3)
	check(echo.inventory.slots[&"primary"] == &"" and get_tree().get_nodes_in_group(WorldItem.GROUP).size() > items_before,
		"Loot puts his gear on the ground")
	if is_instance_valid(bearer):
		SquadAI.of(bearer).set_physics_process(true)


func _test_downed_player() -> void:
	print("A downed player")
	_place(player, Vector3(-6, 0.1, 6))
	await _seconds(3.0)
	var tourniquets: int = _squad().reduce(func(n: int, s: Soldier) -> int: return n + s.inventory.count_of(&"tourniquet"), 0)
	_shoot_femoral(player, 11)
	var sim := 0.0
	while not player.vitals.downed and sim < 400.0:
		player.vitals.server_advance(1.0)
		sim += 1.0
	check(player.vitals.downed and _bleeding(player, "arterial"), "the lead bleeds out from a femoral hit (%s)" % player.vitals.condition_text())
	var stopped := await _wait_until(func() -> bool: return not _bleeding(player, "arterial"), 30.0)
	var used: int = tourniquets - _squad().reduce(func(n: int, s: Soldier) -> int: return n + s.inventory.count_of(&"tourniquet"), 0)
	check(stopped and used >= 1 and is_instance_valid(player.care_by) and player.care_by.is_ai(),
		"squadmates treat a downed player like anyone else (%s, by %s)" % [_wound_kinds(player), _name(player.care_by) if is_instance_valid(player.care_by) else "nobody"])
	player.vitals.server_reset_health()


# --- Helpers ----------------------------------------------------------------------

## A rifle round straight through the right femoral artery (BodyMap rest pose), with seeded dice.
func _shoot_femoral(s: Soldier, seed_value: int) -> void:
	s.vitals.rng.seed = seed_value
	s.vitals.server_hit(Vitals.THIGH_R, {"round_class": Vitals.INTERMEDIATE, "position": s.global_transform * Vector3(0.0578, 0.70, -0.11),
		"direction": s.global_basis * Vector3.BACK, "distance": 50.0})


func _bleeding(s: Soldier, kind: String) -> bool:
	return s.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.kind == kind and w.bleeding)


func _wound_kinds(s: Soldier) -> Array:
	return s.vitals.wound_list().map(func(w: Dictionary) -> String: return "%s%s" % [w.kind, "*" if w.bleeding else ""])


func _kinds(tasks: Array) -> Array:
	return tasks.map(func(t: Dictionary) -> String: return String(t.kind))


## Whether `speaker` said callout `id` since `from` (an index into Callouts.sent).
func _said(from: int, speaker: String, id: StringName) -> bool:
	var sent: Array[Dictionary] = level.callouts.sent
	for k in range(mini(from, sent.size()), sent.size()):
		if sent[k].speaker == speaker and sent[k].id == id:
			return true
	return false


func _lines(from: int) -> Array:
	var sent: Array[Dictionary] = level.callouts.sent
	return sent.slice(mini(from, sent.size())).map(func(l: Dictionary) -> String: return "%s: %s" % [l.speaker, l.text])


func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == &"friendly" and not s.is_queued_for_deletion() and not s.vitals.is_dead())


func _bodies() -> Array:
	return get_tree().get_nodes_in_group(Soldier.DEAD_GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func _ai(callsign: String) -> Soldier:
	var s := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	return s if s and not s.is_queued_for_deletion() else null


func _name(s: Soldier) -> String:
	return String(s.name) if s else "nobody"


## Pauses every squadmate's brain (and stops them walking) so a test can stage things.
func _freeze() -> void:
	for s: Soldier in _squad():
		SquadAI.of(s).set_physics_process(false)
		s.move_input = Vector2.ZERO
		s.want_sprint = false


## Simulated fire has no real shooter: squadmates hold their own fire meanwhile, so their
## covering fire doesn't hit whoever is out treating.
func _hold_fire(hold: bool) -> void:
	for s: Soldier in _squad():
		SquadAI.of(s).hold_fire = hold


## Waits until no squadmate is in contact any more.
func _out_of_contact() -> void:
	_firing = false
	var quiet := await _wait_until(func() -> bool: return not _squad().any(func(s: Soldier) -> bool: return SquadAI.of(s).in_contact()), 20.0)
	if not quiet:
		print("    still in contact: %s" % [_squad().filter(func(s: Soldier) -> bool: return SquadAI.of(s).in_contact()).map(func(s: Soldier) -> String: return "%s (%s)" % [s.name, s.ai_status])])


func _unfreeze() -> void:
	for s: Soldier in _squad():
		SquadAI.of(s).set_physics_process(true)


func _positions() -> Dictionary:
	var out := {}
	for s: Soldier in _squad():
		out[s] = s.global_position
	return out


func _restore(saved: Dictionary) -> void:
	for s: Soldier in saved:
		if is_instance_valid(s):
			_place(s, saved[s])


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Waits until `cond` holds or `timeout` seconds pass; returns whether it held.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
