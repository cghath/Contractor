extends Node
## Headless AI casualty-care scenarios (W7, on Captain's playtest rules): care order, medic
## choice, medic loadouts, a medic keeping the squad's only items, no revive anywhere,
## self-tourniquet and "Medic!", treatment through Soldier._server_treat, enemies ignoring
## unconscious foes except while clearing (dead-checks), the body cap, a soak where the squad
## follows the lead around the compound, a player standing in the medic's way, an engagement
## where the medic goes to a downed squadmate under fire (smoke, drag, tourniquet, the rest)
## and the squad carries him until he wakes, and bodies: a dead squadmate, player and enemy
## each keep all their gear (looted one item or all at once), and survive a zone save and load.
##   <voxel godot exe> --headless --path . res://tests/casualty_test.tscn
## Exits with the number of failures.

## Proposed time limits for the engagement test (seconds).
const TOURNIQUET_WITHIN_S := 25.0
const TREATED_WITHIN_S := 90.0  # bleeding, airway, chest, then a line, a bag and a pressure bag
## Where the lead stands in the engagement: beside the formation's way to Delta at (-3, 15).
const ENGAGEMENT_LEAD := Vector3(8, 0.1, 24)
## Delta bleeds down to this share of his blood (past the 40% lost that knocks you out), so
## once treated he's stable but won't wake soon: he's carried with the squad.
const ENGAGEMENT_BLOOD := 0.58
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
	Soldier.respawn_delay_s = 0.0  # these checks want the old instant respawn (the wait and spawn
	Soldier.spawn_protect_s = 0.0  # protection have their own checks in gameplay and missions)
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func() -> void:
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
	_test_no_revive()
	await _test_medic_choice()
	await _test_triage()
	_test_medic_keeps_kit()
	_test_hold_for_medic()
	_test_medic_fights_only_close()
	await _out_of_contact()
	await _test_dead_check()
	await _test_body_cap()
	await _test_soak()
	await _test_blocked_route()
	await _test_self_tourniquet()
	await _test_engagement()
	await _test_dead_bodies()
	await _test_player_and_enemy_bodies()
	await _test_body_persistence()
	await _test_downed_player()
	await _test_ragdolls()
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
	check(SquadAI.medic_for(delta, [&"splint"]) == charlie, "and the other team's medic is the one to take over (%s)" % _name(SquadAI.medic_for(delta, [&"splint"])))
	golf.vitals.server_reset_health()
	check(SquadAI.medic_for(delta, [&"splint"]) == golf, "a carer's call for a splint goes to the team's medic once it's up again")
	var golf_gear := golf.inventory.net_state.duplicate(true)
	golf.inventory.strip()
	check(SquadAI.medic_for(delta, [&"splint"]) == charlie, "unless it doesn't carry one (%s)" % _name(SquadAI.medic_for(delta, [&"splint"])))
	golf.inventory.net_state = golf_gear
	check(SquadAI.of(echo)._carries_any([&"tourniquet", &"pressure_bandage"] as Array[StringName]),
		"a rifleman's IFAK counts: what's in it is his to treat with")
	_restore(saved)
	_unfreeze()
	await _seconds(0.5)


## Triage cards order who the responder takes first.
func _test_triage() -> void:
	print("Triage cards")
	_freeze()
	var delta := _ai("Delta")
	var echo := _ai("Echo")
	var golf := _ai("Golf")
	var saved := _positions()
	_place(golf, Vector3(6, 0.1, 27))
	_place(delta, Vector3(10, 0.1, 26))
	_place(echo, Vector3(14, 0.1, 26))
	delta.vitals.server_damage(70.0)
	echo.vitals.server_damage(70.0)
	await _frames(2)
	var ai := SquadAI.of(golf)
	check(ai._find_casualty() == delta, "no cards: the nearer casualty first (%s)" % _name(ai._find_casualty()))
	echo.vitals.server_set_triage(Vitals.TRIAGE_IMMEDIATE)
	check(ai._find_casualty() == echo, "marked immediate, the farther one goes first (%s)" % _name(ai._find_casualty()))
	echo.vitals.server_set_triage(Vitals.TRIAGE_EXPECTANT)
	check(ai._find_casualty() == delta, "expectant is skipped while another needs care (%s)" % _name(ai._find_casualty()))
	delta.vitals.server_set_triage(Vitals.TRIAGE_MINIMAL)
	check(ai._find_casualty() == delta, "minimal still comes before expectant (%s)" % _name(ai._find_casualty()))
	echo.vitals.server_set_triage(Vitals.TRIAGE_DELAYED)
	check(ai._find_casualty() == echo, "delayed comes before minimal (%s)" % _name(ai._find_casualty()))
	delta.vitals.server_reset_health()
	echo.vitals.server_set_triage(Vitals.TRIAGE_EXPECTANT)
	check(ai._find_casualty() == echo, "expectant alone is still tended (%s)" % _name(ai._find_casualty()))
	echo.vitals.server_reset_health()
	_restore(saved)
	_unfreeze()
	await _seconds(0.5)


func _test_medic_keeps_kit() -> void:
	print("A medic's own kit")
	var golf := _ai("Golf")
	var charlie := _ai("Charlie")
	var golf_ai := SquadAI.of(golf)
	check(not golf_ai._kept_for_squad(&"splint", "fracture"), "a medic splints itself while the other medic carries splints too")
	var charlie_gear := charlie.inventory.net_state.duplicate(true)
	charlie.inventory.strip()
	var player_gear := player.inventory.net_state.duplicate(true)
	player.inventory.strip()
	check(golf_ai._kept_for_squad(&"splint", "fracture") and golf_ai._kept_for_squad(&"morphine", "pain"),
		"but keeps its splints and morphine for the squad when nobody else has any")
	check(not golf_ai._kept_for_squad(&"tourniquet", "arterial") and not golf_ai._kept_for_squad(&"hemostatic_gauze", "junctional"),
		"massive bleeding aside: it tourniquets itself with the last tourniquet")
	check(not SquadAI.of(_ai("Echo"))._kept_for_squad(&"pressure_bandage", "venous"), "only medics keep their kit")
	charlie.inventory.net_state = charlie_gear
	player.inventory.net_state = player_gear


## cghath's test (P0164 queue 14): AI carried a teammate who was still bleeding (internal
## bleeding: the clamp is medic-only for AI) after the leader. Staged in one frame: a rifleman
## with such a casualty holds and calls the medic instead.
func _test_hold_for_medic() -> void:
	print("A bleed the carer can't stop: hold for the medic, don't carry")
	var echo := _ai("Echo")
	var delta := _ai("Delta")
	var echo_ai := SquadAI.of(echo)
	echo_ai.casualty = delta
	echo_ai.wanted.clear()
	delta.vitals._model._add_wound(Vitals.ABDOMEN, "internal", 0.8, &"renal_l")
	delta.vitals._model.update_state(0.0)
	delta.vitals._after_change(true)
	check(echo.role != Roles.MEDIC and delta.vitals.bleed_rate() > 0.0 and echo_ai._holds_for_medic() and not echo_ai._should_carry(),
		"Echo (no clamp of his own to use) holds beside bleeding Delta for the medic instead of carrying him (wants %s)" % [echo_ai.wanted])
	delta.vitals.server_reset_health()
	echo_ai.wanted.clear()
	check(not echo_ai._holds_for_medic(), "not bleeding: nothing to hold for")
	echo_ai.casualty = null


## Staged in one frame (no brain runs in between): whom a medic on its way to a casualty
## fights, when it holds back to suppress, and the squad covering it.
func _test_medic_fights_only_close() -> void:
	print("A medic going to a casualty")
	var saved := _positions()
	var golf := _ai("Golf")
	var foxtrot := _ai("Foxtrot")
	var echo := _ai("Echo")
	var ai := SquadAI.of(golf)
	var enemy := level.spawn_soldier({"name": "MedicTestHostile", "faction": "hostile", "variant": "urban", "pos": Vector3(10, 0.1, 75),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(enemy).set_physics_process(false)
	_place(golf, Vector3(10, 0.1, 45))
	_place(foxtrot, Vector3(10, 0.1, 53))
	_place(echo, Vector3(12, 0.1, 43))
	foxtrot.vitals.server_damage(65.0)
	foxtrot.vitals.server_advance(WoundModel.PAIN_KNOCKOUT_S + 0.1)  # the pain held long enough to knock him out
	ai.intent = SquadAI.Intent.CASUALTY
	ai.casualty = foxtrot
	ai.care = SquadAI.Care.REACH
	ai.target = enemy
	check(ai._foe() == null, "an enemy 30 m off is left to the squad while it goes to the casualty")
	_place(enemy, Vector3(10, 0.1, 50))
	check(ai._foe() == enemy, "one within %.0f m is fought" % SquadAI.MEDIC_DEFEND_M)
	_place(enemy, Vector3(10, 0.1, 75))
	ai.care = SquadAI.Care.GUARD
	check(ai._foe() == enemy, "guarding the casualty it fights as usual")
	ai._start_reach()
	var echo_ai := SquadAI.of(echo)
	echo_ai._last_contact = Soldier._now()
	check(echo_ai._medic_needs_cover(), "a squadmate in contact covers a medic out reaching a casualty")
	# Pinned down, with the casualty lying in the open: suppress before going out.
	golf.threat_pos = Vector3(10, 1.0, 68)
	golf.suppression = 1.0
	ai._smoke_used = true  # (nothing to throw: the smoke itself is the engagement's job)
	ai._last_contact = Soldier._now()
	ai._suppressing = false
	ai._care_reach(true)
	check(ai._suppressing and not ai._has_destination and ai.status_text() == "Covering " + ai.casualty.display_name(),
		"pinned with the casualty in the open, it holds and suppresses first (%s)" % ai.status_text())
	golf.suppression = 0.0
	ai._suppressing = false
	ai._care_reach(true)
	check(not ai._suppressing and ai._has_destination, "and goes as soon as it isn't pinned")
	ai.target = null
	ai._end_care()
	ai.intent = SquadAI.Intent.FOLLOW
	ai._last_contact = -1000.0
	echo_ai._last_contact = -1000.0
	golf.threat_time = -1000.0
	foxtrot.vitals.server_reset_health()
	enemy.queue_free()
	_restore(saved)


func _test_no_revive() -> void:
	print("No revive")
	var script: Script = SquadAI
	var constants := script.get_script_constant_map()
	var gone := ["MEDIC_REVIVE_KIT", "REVIVE_KITS", "REVIVE_WAIT_S"].filter(func(c: String) -> bool: return constants.has(c))
	var methods := script.get_script_method_list().map(func(m: Dictionary) -> String: return String(m.name))
	gone.append_array(["_can_revive", "_start_revive", "_revive_kit"].filter(func(m: String) -> bool: return m in methods))
	check(gone.is_empty(), "the AI has no revive left: no revive kit, no revive wait, no revive step (%s)" % [gone])
	var calls := []
	for path: String in ["res://scripts/ai/squad_ai.gd", "res://scripts/ai/squad.gd", "res://scripts/ai/roles.gd", "res://scripts/world/compound_level.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for word: String in ["_server_revive", "server_revive(", "revive_problem", "_best_revive_kit", "take_kit_revive", "revive_kit(", "kit_revives"]:
			if word in text:
				calls.append("%s: %s" % [path.get_file(), word])
	check(calls.is_empty(), "nothing in the squad AI or the level calls a revive (%s)" % [calls])


## A player standing on the medic's direct way to a casualty (something the navmesh doesn't
## know about): the medic sidesteps and gets there. A responder that can't get any closer
## hands the casualty on.
func _test_blocked_route() -> void:
	print("A player in the medic's way")
	await _out_of_contact()
	_freeze()
	var saved := _positions()
	var golf := _ai("Golf")
	var echo := _ai("Echo")  # team B, like Golf
	var i := 0
	for s: Soldier in _squad():
		if s != golf and s != echo:
			_place(s, Vector3(-30 + i * 1.5, 0.1, 40))
			i += 1
	_place(golf, Vector3(6, 0.1, 30))
	_place(echo, Vector3(-6, 0.1, 30))
	_place(player, Vector3(0, 0.1, 30))  # right on the straight line between them
	player.rotation.y = 0.0
	await _frames(2)
	echo.vitals.server_damage(65.0)  # out cold from pain, with blood to spare and nothing bleeding
	echo.vitals.server_advance(WoundModel.PAIN_KNOCKOUT_S + 0.1)  # the pain held long enough to knock him out
	await _frames(2)
	check(echo.vitals.downed and SquadAI.responder_for(echo) == golf, "Echo is down; his team's medic Golf answers (%s)" % _name(SquadAI.responder_for(echo)))
	var golf_ai := SquadAI.of(golf)
	golf_ai.set_physics_process(true)
	var start := Soldier._now()
	var statuses := {}
	var reached := await _wait_until(func() -> bool:
		statuses[golf.ai_status] = true
		return golf_ai.casualty == echo and golf_ai.care in [SquadAI.Care.TREAT, SquadAI.Care.GUARD, SquadAI.Care.CARRY] \
			and _flat(golf.global_position, echo.global_position) <= SquadAI.CASUALTY_REACH + 0.5, BLOCKED_REACH_S)
	check(reached, "Golf gets round the player and reaches Echo in %.1f s (limit %.0f; %s)" % [Soldier._now() - start, BLOCKED_REACH_S, statuses.keys()])
	# Knocked out by pain with blood to spare, and the lead close by: watched over where he lies.
	var watched := await _wait_until(func() -> bool: return golf.ai_status == "Watching over " + echo.display_name(), 40.0)  # NPA, a line, a bag, then morphine
	await _seconds(2.0)
	check(watched and golf_ai.casualty == echo and echo.carried_by == null and _flat(golf.global_position, echo.global_position) <= SquadAI.CASUALTY_REACH + 0.5,
		"once his airway is seen to, Golf stays with him where he lies (%s, %s)" % [golf.ai_status, echo.vitals.wound_list().size()])
	golf_ai.set_physics_process(false)
	golf_ai._end_care()
	golf.move_input = Vector2.ZERO
	# One that can't get closer at all gives up after REACH_GIVE_UP_S and hands him on.
	_place(golf, Vector3(6, 0.1, 30))
	golf_ai._take_casualty(echo)
	golf_ai._reach_progress(12.0, echo.global_position, golf_ai._give_up_casualty)
	golf_ai._reach_progress_at -= SquadAI.REACH_GIVE_UP_S + 0.1
	var kept := golf_ai._reach_progress(12.0, echo.global_position, golf_ai._give_up_casualty)
	check(not kept and golf_ai.casualty == null and echo.care_by != golf and golf_ai._skipping(echo),
		"a responder stuck for %.0f s lets go of the casualty and leaves him to others for a while" % SquadAI.REACH_GIVE_UP_S)
	var next := SquadAI.responder_for(echo)
	check(next != null and next != golf, "and someone else answers instead (%s)" % _name(next))
	golf_ai._skip.clear()
	echo.vitals.server_reset_health()
	_restore(saved)
	_place(player, Vector3(0, 0.1, 22))
	_unfreeze()
	await _seconds(1.0)


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
	# In play: an advancing hostile picks the body, looks, then fires DEAD_CHECK_ROUNDS
	# deliberate rounds at the torso and moves on (Captain, P0362: dead-checks used to fire bursts
	# until the body died, nearly always of a head or neck round). The body is a stand-in friendly
	# (a squadmate killed here would stay dead for the later tests).
	var victim := level.spawn_soldier({"name": "CheckVictim", "faction": "friendly", "variant": "urban", "pos": Vector3(-11, 0.1, -15),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	SquadAI.of(victim).set_physics_process(false)
	_place(victim, Vector3(-11, 0.1, -15))
	victim.vitals.server_damage(500.0)
	await _seconds(1.5)  # the ragdoll comes to rest
	# Stand him 4 m off to the side of the body (head to pelvis), where the torso shows.
	var side := _body_side(victim)
	var centre: Vector3 = SquadAI._part_point(victim, Vitals.ABDOMEN) if SquadAI._part_point(victim, Vitals.ABDOMEN) != null else victim.body_point()
	var stand := Vector3(centre.x, 0.1, centre.z) + side * 4.0
	_place(hostile, stand)
	var face := centre - stand
	hostile.rotation.y = atan2(-face.x, -face.z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var wounds_before := victim.vitals.wound_list().size()
	var rounds_before := hostile.inventory.rounds_in(hostile.active_slot)
	ai._dead_check = null
	ai._checked.clear()
	ai.target = null
	ai.intent = SquadAI.Intent.FIGHT
	ai._advancing = true
	ai._advance_anchor = stand
	ai._no_los_s = 0.0
	ai._last_contact = Soldier._now()
	hostile.threat_pos = victim.global_position
	hostile.threat_time = Soldier._now()
	var contact_at := ai._last_contact
	check(victim.vitals.downed, "a stand-in body lies unconscious 4 m from an advancing hostile (%s)" % victim.vitals.condition_text())
	ai._cover_cd = 1000.0  # stays where it stands, 4 m off, instead of looking for cover
	ai.set_physics_process(true)
	var picked_at := -1.0
	var wounded_at := -1.0
	var start := Soldier._now()
	while Soldier._now() - start < 15.0:
		await get_tree().physics_frame
		if picked_at < 0.0 and ai.target == victim:
			picked_at = Soldier._now()
			ai._advancing = false  # the advance ends (it reached cover, say): the dead-check goes on
		if wounded_at < 0.0 and victim.vitals.wound_list().size() > wounds_before:
			wounded_at = Soldier._now()
		if picked_at >= 0.0 and wounded_at >= 0.0 and ai.target != victim:
			break
	check(picked_at >= 0.0 and picked_at - start <= 3.0, "an advancing hostile picks the unconscious body for a dead-check")
	check(wounded_at >= 0.0 and wounded_at - picked_at <= 12.0, "and shoots it (%s, %d -> %d wounds)" % [victim.vitals.condition_text(), wounds_before, victim.vitals.wound_list().size()])
	check(wounded_at < 0.0 or wounded_at - picked_at >= 1.0, "after a look first: the first round %.2f s after picking it (at least 1 s)" % (wounded_at - picked_at))
	var spent := rounds_before - hostile.inventory.rounds_in(hostile.active_slot)
	check(spent >= 1 and spent <= SquadAI.DEAD_CHECK_ROUNDS, "deliberate single rounds: %d spent (at most %d)" % [spent, SquadAI.DEAD_CHECK_ROUNDS])
	ai._advancing = true
	check(ai.target != victim and ai._find_target() != victim, "then the body counts as checked: dropped, and not picked again while still clearing (%s)" % _name(ai.target))
	ai._advancing = false
	var cause: Dictionary = victim.vitals.last_cause
	check(not victim.vitals.is_dead() or cause.get("part", &"") not in [Vitals.HEAD, Vitals.FACE, Vitals.NECK],
		"not killed by a head or neck round (%s, %s)" % [victim.vitals.condition_text(), cause.get("part", "-")])
	check(ai._last_contact <= contact_at + 0.01, "a dead-check doesn't count as contact")
	ai.set_physics_process(false)
	await _dead_check_odds(hostile, ai, victim)
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


## Flat, unit: across the body lying as `s`'s ragdoll (square to his head-to-pelvis line).
static func _body_side(s: Soldier) -> Vector3:
	var head: Variant = SquadAI._part_point(s, Vitals.HEAD)
	var pelvis: Variant = SquadAI._part_point(s, Vitals.PELVIS)
	if head == null or pelvis == null:
		return Vector3.RIGHT
	var along := (head as Vector3) - (pelvis as Vector3)
	along.y = 0.0
	if along.length() < 0.05:
		return Vector3.RIGHT
	return along.normalized().cross(Vector3.UP)


## The dead-check odds (Captain, P0362): around the same body at rest, a hostile at 2, 4, 6 and
## 8 m on 8 bearings (from beyond the head round), 5 checks each, run synchronously at 60 Hz the
## way _shoot does it, with the rounds traced against the real hitboxes. Few rounds to the
## head, never more than DEAD_CHECK_ROUNDS, none before the look is over, and from the side up
## close the check still happens.
func _dead_check_odds(hostile: Soldier, ai: SquadAI, victim: Soldier) -> void:
	hostile.want_crouch = false  # on his feet, as he'd stand over a body
	hostile.move_input = Vector2.ZERO
	await _seconds(1.0)  # the ragdoll settles after the live rounds
	var side := _body_side(victim)
	var along := side.cross(Vector3.DOWN)  # pelvis to head, flat
	var centre: Vector3 = SquadAI._part_point(victim, Vitals.ABDOMEN) if SquadAI._part_point(victim, Vitals.ABDOMEN) != null else victim.body_point()
	var weapon := hostile.active_weapon()
	if weapon == null:
		check(false, "dead-check odds: the hostile has a weapon")
		return
	var auto: bool = weapon.stats.get("auto", false)
	var gap := 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	hostile.want_aim = true
	seed(4242)
	var fired := 0
	var head := 0
	var over := 0
	var early := 0
	var side_checks := 0
	var side_fired := 0
	var line := ""
	for d: float in [2.0, 4.0, 6.0, 8.0]:
		line += "
    %.0f m:" % d
		for b in 8:
			var dir := along.rotated(Vector3.UP, b * PI / 4.0)
			_place(hostile, Vector3(centre.x, 0.1, centre.z) + dir * d)
			await get_tree().physics_frame
			await get_tree().physics_frame
			await get_tree().physics_frame
			hostile.is_aiming = true
			var here := 0
			for k in 5:
				var to := centre - hostile.global_position
				hostile.rotation.y = atan2(-to.x, -to.z) + deg_to_rad(randf_range(-30.0, 30.0))
				hostile.head.rotation.x = 0.0
				ai.target = victim
				ai._burst_left = 0
				ai._dead_check_rounds = 0
				ai._checked.clear()
				ai._acquire(victim)
				var t := 0.0
				var next_t := 0.0
				var pause_t := 0.0
				var shots := 0
				while t < ai._acq_react_s + SquadAI.DEAD_CHECK_GIVE_UP_S:
					t += 1.0 / 60.0
					var err := ai._aim_for_shot(ai._cqb_aim_point(victim, 1.0 / 60.0), victim)
					if t < ai._acq_react_s or t < next_t or t < pause_t or not ai._gate_open(victim, err):
						continue
					next_t = t + gap
					if ai._burst_left <= 0:
						ai._burst_left = randi_range(3, 5) if auto else randi_range(2, 3)
						ai._suppress_jitter = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.5), randf_range(-1, 1)) * SquadAI.SUPPRESS_SPREAD_M
						ai._start_burst(victim)
					ai._burst_left -= 1
					if ai._burst_left <= 0:
						pause_t = t + randf_range(0.5, 1.1) / lerpf(0.7, 1.3, ai.combat)
					var ray: Vector3 = hostile.call(&"ai_spread_direction", weapon) if hostile.has_method(&"ai_spread_direction") else hostile._spread_direction(weapon)
					var extra := deg_to_rad(ai._aim_error_deg(true))
					ray = (ray + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(extra) * 0.6).normalized()
					var part := _round_part(hostile, victim, hostile.camera.global_position, ray)
					shots += 1
					if t < 1.0:
						early += 1
					if part in [Vitals.HEAD, Vitals.FACE, Vitals.NECK]:
						head += 1
					if ai._dead_check_rounds >= SquadAI.DEAD_CHECK_ROUNDS and ai._burst_left <= 0:
						break
				fired += shots
				here += shots
				if shots > SquadAI.DEAD_CHECK_ROUNDS:
					over += 1
				if d <= 4.0 and b % 4 == 2:
					side_checks += 1
					if shots > 0:
						side_fired += 1
			line += " %d" % here
	randomize()
	ai.target = null
	ai._checked.clear()
	print("    rounds fired per bearing (5 checks; bearing 0 beyond the head, 4 beyond the feet):" + line)
	check(fired > 0 and float(head) / fired <= 0.05, "dead-checks: head, face or neck at most 5%% of rounds (%d of %d)" % [head, fired])
	check(over == 0, "no check fires more than %d rounds (%d did)" % [SquadAI.DEAD_CHECK_ROUNDS, over])
	check(early == 0, "no round before a 1 s look (%d were)" % early)
	check(side_fired >= 0.8 * side_checks, "from the side at 2-4 m the check happens: %d of %d fire" % [side_fired, side_checks])


## The part of `target` a round from `from` along `dir` meets, as Ballistics._trace finds it
## (the hitbox, then the body inside it), or &"" for a miss (the ground, anyone else).
static func _round_part(shooter: Soldier, target: Soldier, from: Vector3, dir: Vector3) -> StringName:
	var space := shooter.get_world_3d().direct_space_state
	var exclude: Array[RID] = [shooter.get_rid()]
	for child in shooter.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var gear := shooter.get_node_or_null(^"Gear") as GearRig
	if gear:
		exclude.append_array(gear.armor_rids())
	var start := from
	for i in Ballistics.MAX_PENETRATIONS:
		var query := PhysicsRayQueryParameters3D.create(start, from + dir * Ballistics.RANGE, (1 << 0) | (1 << 1) | (1 << 3), exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return &""
		var collider: Object = hit.collider
		if collider is VoxelArmor:
			exclude.append(collider.get_rid())
			start = hit.position
			continue
		var vitals := Vitals.find_on(collider)
		if vitals == null:
			return &""
		var part: StringName = collider.get_meta(&"body_part", Vitals.TORSO)
		if BodyVolume.entry(collider as Node3D, part, hit.position, dir, BodyVolume.body_of(collider)).is_empty():
			exclude.append(collider.get_rid())
			start = hit.position
			continue
		return part if vitals.get_parent() == target else &""
	return &""


func _test_body_cap() -> void:
	print("Body cap")
	# Bodies left by earlier scenes would be older than these three, and go first.
	for b: Soldier in _bodies():
		b.server_remove_body()
	await _frames(2)
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
	_clear_contact()
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
	_clear_contact()
	_place(player, Vector3(0, 0.1, 24))
	player.rotation.y = 0.0
	await _seconds(4.0)
	var alpha := _ai("Alpha")
	var charlie := _ai("Charlie")
	# Nothing but the tourniquet: no stopgap kit and no bandages, so what he can't do himself
	# (the seeded hit below always opens a vein too) waits for the medic.
	var taken: Array[StringName] = []
	for id: StringName in [&"tourniquet", &"ifak", &"pressure_bandage", &"hemostatic_gauze"]:
		while alpha.inventory.remove_one(id):
			taken.append(id)
	alpha.inventory.take(&"tourniquet")  # just the one (the base kit's holder has another)
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
	var needs := _kinds(alpha.vitals.care_needed())
	check("venous" in needs, "the seeded hit also opens a vein he has no bandage for (%s)" % [needs])
	var statuses := {}
	var own := await _wait_until(func() -> bool:
		statuses[alpha.ai_status] = true
		return alpha.inventory.count_of(&"tourniquet") == 0 and alpha.vitals.tourniquets().has(Vitals.THIGH_R), 10.0)
	check(own and statuses.has("Treating self"),
		"under fire, he puts his own tourniquet on at once (%s, %s, %s)" % [alpha.ai_status, statuses.keys(), alpha.vitals.tourniquets()])
	var call := await _wait_until(func() -> bool: return _said(sent_from, "Alpha", &"medic"), 8.0)
	check(call, "and he calls \"Medic!\" for what he can't fix himself (%s)" % [_lines(sent_from)])
	# Put on in a hurry under fire, his tourniquet may still let some through: the medic,
	# who comes under fire too, adds the second one.
	var stopped := await _wait_until(func() -> bool: return not _bleeding(alpha, "arterial"), 20.0)
	check(stopped, "and the arterial bleeding stops (%s)" % [alpha.vitals.tourniquets()])
	check(_said(sent_from, "Charlie", &"moving_to"),
		"his team's medic Charlie comes to him while the shooting is still going on (%s)" % [_lines(sent_from)])
	_firing = false
	var helped := await _wait_until(func() -> bool:
		return alpha.vitals.care_needed().is_empty(), 40.0)
	check(helped and (charlie.inventory.count_of(&"morphine") < morphine_before or charlie.inventory.count_of(&"splint") < splints_before
		or charlie.inventory.count_of(&"pressure_bandage") < bandages_before),
		"and treats him: nothing left to do (%s left; Charlie: %s)" % [_kinds(alpha.vitals.care_needed()), charlie.ai_status])
	check(_said(sent_from, "Charlie", &"moving_to") and _said(sent_from, "Charlie", &"treating"),
		"Charlie answers: \"Moving to Alpha\", then \"Treating Alpha\" (%s)" % [_lines(sent_from)])
	for id in taken:
		alpha.inventory.take(id)
	await _out_of_contact()
	_hold_fire(false)


# --- Engagement ---------------------------------------------------------------

func _test_engagement() -> void:
	print("Engagement: a squadmate down in the open under fire")
	_clear_contact()
	# The lead stands off to the side, clear of the medic's way from the formation to Delta
	# (a player in the way is _test_blocked_route's job).
	_place(player, ENGAGEMENT_LEAD)
	player.rotation.y = 0.0
	await _seconds(3.0)
	var delta := _ai("Delta")
	var golf := _ai("Golf")
	var counts := {}
	var his := {}  # Delta's own kit: a carer uses it first (queue 17)
	for id: StringName in [&"tourniquet", &"pressure_bandage", &"smoke_grenade", &"splint", &"npa"]:
		counts[id] = golf.inventory.medical_count(id)
		his[id] = delta.inventory.medical_count(id)
	_threat = Vector3(-3, 1.5, 0)
	_hold_fire(true)
	_firing = true
	await _seconds(0.6)
	print("  callout log before the engagement: %d of %d lines" % [level.callouts.sent.size(), Callouts.LOG_SIZE])
	level.callouts.sent.clear()  # the log keeps only its last LOG_SIZE lines: start empty so sent_from stays valid as the scene's chatter trims it
	var sent_from := level.callouts.sent.size()
	_place(delta, Vector3(-3, 0.1, 15))
	_shoot_femoral(delta, 5)
	delta.vitals.rng.seed = 9
	delta.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	var sim := 0.0
	while (not delta.vitals.downed or delta.vitals.blood_fraction() > ENGAGEMENT_BLOOD) and sim < 400.0:
		delta.vitals.server_advance(1.0)
		sim += 1.0
	var start := Soldier._now()
	check(delta.vitals.downed and _bleeding(delta, "arterial") and delta.vitals.blood_fraction() <= ENGAGEMENT_BLOOD,
		"Delta bleeds out from his femoral artery until he's unconscious, %.0f%% of his blood lost (%s, %s)" % [(1.0 - delta.vitals.blood_fraction()) * 100.0,
		delta.vitals.condition_text(), _wound_kinds(delta)])
	var seen := {"drag": false, "status": {}, "blood_min": 1.0, "woke": false}
	var watch := func() -> void:
		seen.status[golf.ai_status] = true
		seen.blood_min = minf(seen.blood_min, delta.vitals.blood_fraction())
		if delta.vitals.is_up():
			seen.woke = true
	var going := await _wait_until(func() -> bool:
		watch.call()
		return SquadAI.of(golf).casualty == delta, 2.0)
	check(going, "under fire his team's medic Golf goes to him at once (%s)" % [seen.status.keys()])
	var other_open_at_tq := []
	var tq := await _wait_until(func() -> bool:
		watch.call()
		if delta.carried_by == golf and golf.carry_mode == Soldier.DRAG:
			seen.drag = true
		if not _bleeding(delta, "arterial"):
			other_open_at_tq.append(delta.vitals.care_needed().filter(func(t: Dictionary) -> bool: return t.kind != "pain").size())
			return true
		return false, TOURNIQUET_WITHIN_S)
	var tq_s := Soldier._now() - start
	check(tq and delta.inventory.medical_count(&"tourniquet") < his[&"tourniquet"] and golf.inventory.medical_count(&"tourniquet") == counts[&"tourniquet"],
		"Golf reaches him and puts a tourniquet on under fire in %.0f s (limit %.0f; %s), Delta's own first (Delta %d -> %d, Golf %d -> %d)" % [tq_s,
		TOURNIQUET_WITHIN_S, seen.status.keys(), his[&"tourniquet"], delta.inventory.medical_count(&"tourniquet"), counts[&"tourniquet"], golf.inventory.medical_count(&"tourniquet")])
	check(golf.inventory.count_of(&"smoke_grenade") < counts[&"smoke_grenade"] and _said(sent_from, "Golf", &"smoke_out"), "Golf throws smoke between him and the threat")
	check(seen.drag, "and drags him out of the line of fire")
	check(not other_open_at_tq.is_empty() and other_open_at_tq[0] > 0, "massive bleeding first: his other wounds wait for the tourniquet (%s open)" % [other_open_at_tq])
	# Read now: the callout log keeps only its last Callouts.LOG_SIZE lines, and the squad's
	# chatter through the rest of the scene pushes these early ones out.
	var called := _said(sent_from, "Golf", &"moving_to") and _said(sent_from, "Golf", &"treating")
	var called_lines := _lines(sent_from)
	await _seconds(2.0)
	_firing = false
	var treated := await _wait_until(func() -> bool:
		watch.call()
		return delta.vitals.care_needed().filter(func(t: Dictionary) -> bool: return t.kind != "pain").is_empty(), TREATED_WITHIN_S)
	var all_s := Soldier._now() - start
	check(treated, "then the rest in the care order: patched up within %.0f s (%.0f s; Delta: %s, %s; Golf: %s)" % [TREATED_WITHIN_S, all_s,
		delta.vitals.condition_text(), _kinds(delta.vitals.care_needed()), golf.ai_status])
	var his_bandages := delta.inventory.medical_count(&"pressure_bandage")
	check(his_bandages < his[&"pressure_bandage"] and (golf.inventory.medical_count(&"pressure_bandage") == counts[&"pressure_bandage"] or his_bandages == 0)
		and golf.inventory.medical_count(&"npa") < counts[&"npa"],
		"through _server_treat: Delta's own bandages first (%d -> %d; Golf's %d -> %d), then Golf's NPA (Delta carries none)" % [his[&"pressure_bandage"], his_bandages,
		counts[&"pressure_bandage"], golf.inventory.medical_count(&"pressure_bandage")])
	check(called, "Golf calls it: \"Moving to Delta\", \"Treating Delta\" (%s)" % [called_lines])
	await _out_of_contact()
	_hold_fire(false)
	# Nobody revives him: past 40% of his blood lost he stays out, and the squad takes him along.
	var carried := await _wait_until(func() -> bool:
		watch.call()
		return is_instance_valid(delta.carried_by) and delta.carried_by.is_ai() and delta.carried_by.carry_mode == Soldier.CARRY, 20.0)
	var bearer := delta.carried_by
	check(carried, "still out, he's carried with the squad (%s)" % (bearer.ai_status if bearer else golf.ai_status))
	_place(player, Vector3(-8, 0.1, 4))
	var along := await _wait_until(func() -> bool:
		watch.call()
		return _flat(delta.global_position, player.global_position) < 12.0, 30.0)
	check(along, "after the lead (%.1f m from him)" % _flat(delta.global_position, player.global_position))
	check(not seen.woke and delta.vitals.downed and delta.vitals.blood_fraction() <= seen.blood_min + 0.02 and not seen.status.has("Reviving Delta"),
		"no revive: he stayed unconscious, his blood only creeping back (%.0f%% -> %.0f%%)" % [seen.blood_min * 100.0, delta.vitals.blood_fraction() * 100.0])
	# Captain (P0164 queue 16): ordered to move while carrying him, the bearer goes there and
	# lays him down in cover nearby, and stays with him.
	if bearer and SquadAI.of(bearer):
		var bearer_ai := SquadAI.of(bearer)
		var move_to := Vector3(-3, 0.1, 15)  # where he went down: open, walkable ground
		bearer_ai.on_order(Squad.Order.MOVE, move_to)
		var laid := await _wait_until(func() -> bool:
			return not is_instance_valid(delta.carried_by) and _flat(delta.global_position, move_to) <= SquadAI.LAY_DOWN_M + SquadAI.LAY_NEAR_M, 30.0)
		check(laid and bearer_ai.casualty == delta, "ordered to move while carrying him, %s lays him down near the order point (%.1f m) and stays (%s)"
			% [_name(bearer), _flat(delta.global_position, move_to), bearer.ai_status])
		# He lies where his ragdoll settled (body_point), up to ~3 m from the lay spot: the bearer
		# must take that as laid there, not lift him again to bring him closer (R0123-R0125).
		var lifted_by := []
		await _wait_until(func() -> bool:
			if is_instance_valid(delta.carried_by) and delta.carried_by not in lifted_by:
				lifted_by.append(delta.carried_by)
			return false, 2.0)
		var lay: Variant = bearer_ai._lay_spot
		check(lifted_by.is_empty() and not is_instance_valid(delta.carried_by), "and doesn't pick him up again while the order stands (lifted by %s; lying %s m from the lay spot)"
			% [lifted_by.map(func(s: Soldier) -> String: return _name(s)), ("%.1f" % _flat(delta.body_point(), lay)) if lay != null else "-"])
		bearer_ai.on_order(Squad.Order.FOLLOW, player.global_position)
	# He comes round on his own (the wound model decides when; the test stands in for it).
	delta.vitals.server_reset_health()
	var put_down := await _wait_until(func() -> bool: return not is_instance_valid(delta.carried_by) and SquadAI.of(golf).casualty != delta, 5.0)
	check(put_down, "once he wakes he's put down and on his own feet again (%s)" % golf.ai_status)
	_place(player, Vector3(0, 0.1, 22))
	await _seconds(2.0)


# --- Dead bodies -----------------------------------------------------------------

func _test_dead_bodies() -> void:
	print("Dead friendlies")
	# Bodies keep their gear here: nobody cross-loads from them (scavenge_test covers that).
	level.squad_for(&"friendly").set_scavenge(player, false)
	_firing = false
	_place(player, Vector3(0, 0.1, 22))
	await _out_of_contact()
	var echo := _ai("Echo")
	var gear_before := _gear_of(echo)
	var items_before := _item_ids()
	var gone := [false]
	echo.died_for_good.connect(func(_who: Soldier) -> void: gone[0] = true)
	echo.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(3)
	check(gone[0] and is_instance_valid(echo) and not echo.is_queued_for_deletion() and echo.is_in_group(Soldier.DEAD_GROUP),
		"a squadmate killed outright stays as a body (died_for_good still fires)")
	check(echo.collision_layer == 0 and not echo.vitals.is_up(), "lying, and not blocking anyone")
	check(_gear_of(echo) == gear_before and echo.inventory.slots[&"primary"] == &"m110" and echo.inventory.count_of(&"mag_762") > 0,
		"with all his gear still on him (%d things)" % gear_before.size())
	check(_new_items(items_before, echo.global_position, 10.0).is_empty(), "and nothing on the ground")
	check(echo.squad_slot == -1 and echo not in level.squad_for(&"friendly").members(), "he leaves the squad: no slot, no formation place, no orders")
	var slots_before := level._squad_ai().size()
	level.rebalance_squad()
	await _frames(2)
	check(is_instance_valid(echo) and not echo.is_queued_for_deletion() and _gear_of(echo) == gear_before and level._squad_ai().size() == slots_before,
		"a squad rebalance leaves his body and gear alone and fills no slot for him")
	var ids := InteractionMenu.actions_for(player, echo).map(func(a: Dictionary) -> StringName: return a.id)
	check(ids == [&"loot", &"loot_all", &"carry", &"drag"], "the interaction menu offers Loot, Loot all, Carry and Drag (%s)" % [ids])
	var listed := InteractionMenu.body_items(echo).map(func(e: Dictionary) -> String: return e.label)
	check(listed.any(func(l: String) -> bool: return l.begins_with("Primary: M110")) and listed.any(func(l: String) -> bool: return "Magazine" in l or "mag" in l.to_lower()),
		"Loot lists what's on him, like the inventory screen (%s)" % [listed])
	var carried := await _wait_until(func() -> bool: return is_instance_valid(echo.carried_by) and echo.carried_by.is_ai(), 25.0)
	var bearer := echo.carried_by
	check(carried, "out of contact a squadmate picks his body up (%s; squad: %s)" % [bearer.ai_status if bearer else "nobody", _squad().map(func(s: Soldier) -> String: return "%s %s %.1f m at %s v%.1f in%s hits %s busy %.1f" % [s.name, s.ai_status, _flat(s.global_position, echo.global_position), s.global_position, s.velocity.length(), s.move_input, range(s.get_slide_collision_count()).map(func(i: int) -> String: return str(s.get_slide_collision(i).get_collider())), s._busy_until - Soldier._now()])])
	if not carried:
		print("    squad: %s" % [_squad().map(func(s: Soldier) -> String: return "%s %s %s/%s contact %s" % [s.name, s.ai_status,
			SquadAI.Intent.keys()[SquadAI.of(s).intent], SquadAI.Care.keys()[SquadAI.of(s).care], SquadAI.of(s).in_contact()])])
	_place(player, Vector3(-8, 0.1, 4))
	var along := await _wait_until(func() -> bool: return _flat(echo.global_position, player.global_position) < 12.0, 30.0)
	check(along, "and carries it after the lead (%.1f m)" % _flat(echo.global_position, player.global_position))
	check(SquadAI.of(echo) != null and echo.ai_status == "Dead" and echo not in player._hud.command_menu.roster(),
		"he shows as dead and has left the HUD roster, F-keys and Select all (%s)" % echo.ai_status)
	if is_instance_valid(bearer):
		SquadAI.of(bearer)._end_care()
		SquadAI.of(bearer).set_physics_process(false)  # stop picking it up again while we loot
	await _frames(2)
	check(_gear_of(echo) == gear_before, "carried, he still has everything on him")
	# Loot one thing, then everything.
	_place(player, echo.global_position + Vector3(1.0, 0.1, 0.0))
	var mags := _entry_index(echo, &"mag_762")
	var mags_on := echo.inventory.count_of(&"mag_762")
	var player_mags := player.inventory.count_of(&"mag_762")
	var ground := _item_ids()
	var echo_gear := _gear_of(echo)
	var player_gear := _gear_of(player)
	player._server_loot_item.rpc_id(1, echo.get_path(), mags[0], mags[1], &"m110")  # a stale pick: that's no rifle there
	await _frames(3)
	check(_gear_of(echo) == echo_gear and _gear_of(player) == player_gear,
		"Loot > one entry that someone else took first (another item there now) moves nothing")
	player._server_loot_item.rpc_id(1, echo.get_path(), mags[0], mags[1], &"mag_762")
	await _frames(3)
	check(mags[1] >= 0 and player.inventory.count_of(&"mag_762") > player_mags and echo.inventory.count_of(&"mag_762") < mags_on,
		"Loot > one entry: his 7.62 magazines go into the looter's pouches (%d -> %d)" % [player_mags, player.inventory.count_of(&"mag_762")])
	var looter_gear := player.inventory.net_state.duplicate(true)
	player.inventory.strip()  # room for everything: nothing worn yet
	var left_before := _items_of(echo)
	player._server_loot_body.rpc_id(1, echo.get_path())
	await _frames(3)
	var got := _items_of(player)
	check(not echo.has_gear() and got == left_before, "Loot all: everything he had is now on the looter (%d things)" % got.size())
	if got != left_before:
		print("    had %s\n    got %s\n    left on him %s" % [left_before, got, _items_of(echo)])
	# A looter with gear of his own: what fits comes over, the rest stays on the body.
	var second := level.spawn_soldier({"name": "LootHostile", "faction": "hostile", "variant": "urban", "pos": echo.global_position + Vector3(0, 0, 1.5),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	SquadAI.of(second).set_physics_process(false)
	second.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(2)
	player.inventory.take(&"rounds_556", 5000)  # pouches and pack full to the brim
	var both_before := _items_in([second, player])
	var ground_2 := _item_ids()
	player._server_loot_body.rpc_id(1, second.get_path())
	await _frames(3)
	var both_after := _items_in([second, player])
	check(_items_of(second).size() > 0 and both_after == both_before and _new_items(ground_2, second.global_position, 10.0).is_empty(),
		"with his pouches already full the looter takes what fits and the rest stays on the body, none on the ground (%d left)" % _items_of(second).size())
	if both_after != both_before:
		print("    before %s\n    after %s" % [both_before.filter(func(l: String) -> bool: return l not in both_after),
			both_after.filter(func(l: String) -> bool: return l not in both_before)])
	second.remove_from_group(Soldier.DEAD_GROUP)  # test cleanup: gone without dropping anything
	second.queue_free()
	check(_new_items(ground, echo.global_position, 10.0).is_empty(), "and nothing went on the ground (%s)" % [_new_items(ground, echo.global_position, 10.0)])
	player.inventory.net_state = looter_gear
	if is_instance_valid(bearer):
		SquadAI.of(bearer).set_physics_process(true)
	level.squad_for(&"friendly").set_scavenge(player, true)


## A dead player leaves no body and respawns with everything he had on (only the hands item
## drops: Captain, 2026-10-14, "respawn with the kit you had on. delete old player/bot bodies");
## a dead enemy's body keeps its gear.
func _test_player_and_enemy_bodies() -> void:
	print("Dead players and enemies")
	_place(player, Vector3(-4, 0.1, 30))
	await _frames(2)
	for id: StringName in [&"assault_pack", &"ifak", &"mag_556", &"plate_ceramic_l4"]:
		player.inventory.take(id)
	player.inventory.take(&"hvt_case")
	var gear_before := _gear_of(player)
	var spot := player.global_position
	var items_before := _item_ids()
	var bodies_before := level.bodies.get_child_count()
	var markers_before := get_tree().get_nodes_in_group(GearMarker.GROUP).size()
	player.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.FULL_POWER})
	await _frames(3)
	check(level.bodies.get_child_count() == bodies_before and get_tree().get_nodes_in_group(GearMarker.GROUP).size() == markers_before,
		"a dead player leaves no body and no gear marker (%d bodies, %d before)" % [level.bodies.get_child_count(), bodies_before])
	var without_case := gear_before.filter(func(g: String) -> bool: return not g.begins_with("hands:"))
	var on_him := _gear_of(player)
	check(player.vitals.is_up() and on_him == without_case,
		"he respawned with everything he had on but the case in his hands (%d things)%s" % [on_him.size(),
		"" if on_him == without_case else ": %s -> %s" % [without_case, on_him]])
	var new_items := _new_items(items_before, spot, 10.0)
	check(new_items == ["hvt_case"], "only what was in his hands dropped (%s)" % [new_items])
	# An enemy's body.
	var hostile := level.spawn_soldier({"name": "BodyHostile", "faction": "hostile", "variant": "urban", "pos": Vector3(20, 0.1, 30),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	SquadAI.of(hostile).set_physics_process(false)
	var hostile_gear := _gear_of(hostile)
	var hostile_items := _item_ids()
	hostile.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(3)
	check(is_instance_valid(hostile) and hostile.is_in_group(Soldier.DEAD_GROUP) and _gear_of(hostile) == hostile_gear
		and _new_items(hostile_items, hostile.global_position, 10.0).is_empty(), "a dead enemy's body keeps all its gear, none of it on the ground (%d things)" % hostile_gear.size())


## Bodies and what's on them are saved with the zone and come back on load.
func _test_body_persistence() -> void:
	print("Bodies in the zone save")
	# Nothing moves around the save: whoever carries a body puts it down and the squad holds
	# still, so every body lies where it's recorded.
	for s: Soldier in _squad():
		if SquadAI.of(s).care != SquadAI.Care.NONE:
			SquadAI.of(s)._end_care()
		s.release_carried()
	_freeze()
	await _seconds(1.0)  # bodies put down settle on the ground
	check(_bodies().all(func(b: Soldier) -> bool: return not is_instance_valid(b.carried_by)), "nobody is carrying a body")
	# A player who left the session while down leaves his body and a gear marker (a player who
	# dies leaves none since Captain, 2026-10-14); stand one in for the save.
	var left_body := player.server_leave_body()
	await _frames(2)
	check(left_body != null and left_body.has_gear_marker, "a body left by a player who left while down")
	var before := {}
	for b: Soldier in _bodies():
		before[b.body_uid] = {"label": b.display_name(), "log": b.log_name(), "gear": _gear_of(b), "pos": b.global_position}
	check(before.size() >= 3, "bodies lying around: %s" % [before.values().map(func(v: Dictionary) -> String: return v.label)])
	GameState.save_zone()
	# A reload: the bodies go (without dropping anything) and the save brings them back.
	for b: Soldier in _bodies():
		b.remove_from_group(Soldier.DEAD_GROUP)
		b.queue_free()
	await _frames(2)
	GameState.load_zone()
	level._restore_bodies()
	await _frames(3)
	var after := {}
	for b: Soldier in _bodies():
		after[b.body_uid] = {"label": b.display_name(), "log": b.log_name(), "gear": _gear_of(b), "pos": b.global_position}
	check(after.keys().size() == before.keys().size() and before.keys().all(func(uid: String) -> bool: return after.has(uid)),
		"every body is back (%d of %d)" % [after.size(), before.size()])
	var differ := PackedStringArray()
	for uid: String in before:
		if not after.has(uid) or after[uid].label != before[uid].label or after[uid].gear != before[uid].gear \
				or _flat(after[uid].pos, before[uid].pos) > 0.3:
			differ.append("%s: %s -> %s" % [uid, before[uid], after.get(uid)])
	# The differences go in the check's own line: run_tests.sh only shows [FAIL] lines.
	check(differ.is_empty(), "where they lay, with the same gear (rounds, plates and kits included)%s"
		% ("" if differ.is_empty() else ": " + " | ".join(differ)))
	var renamed := before.keys().filter(func(uid: String) -> bool: return "[body " in String(before[uid].log) and after.has(uid) and after[uid].log != before[uid].log)
	check(renamed.is_empty() and after.values().all(func(v: Dictionary) -> bool: return String(v.log).begins_with(String(v.label) + " [body ")),
		"in the session log each reads as its name and its uid's tag, the same as before the load (%s)" % [after.values().map(func(v: Dictionary) -> String: return v.log)])
	check(_bodies().all(func(b: Soldier) -> bool: return b.vitals.is_dead() and b.collision_layer == 0 and SquadAI.of(b) == null),
		"dead, lying and brainless")
	var markers := get_tree().get_nodes_in_group(GearMarker.GROUP).filter(func(m: Node) -> bool: return not m.is_queued_for_deletion())
	check(markers.size() == 1 and "Player 1" in (markers[0] as GearMarker).text, "the dead player's body has its gear marker again")
	# A hostile whose body is in the save isn't spawned again on load (no second set of his gear).
	GameState.bodies.append({"uid": "test_hostile2", "label": "Hostile2", "faction": "hostile"})
	var hostiles := level.hostiles_to_spawn().map(func(h: Dictionary) -> String: return h.name)
	check(hostiles.size() == CompoundLevel.HOSTILES.size() - 1 and "Hostile2" not in hostiles,
		"a hostile whose body the save holds stays dead on load (spawning %s)" % [hostiles])
	GameState.bodies.pop_back()
	_unfreeze()


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


## Everything on `s`, independent of which pouch it's in: "slot:<slot>=<id> <state>" for what's
## worn, "item:<id> <state>=<count>" for what's stowed (summed over stacks), "hands:<id>".
## States go through GameState.from_json, so a body saved and loaded compares equal.
func _gear_of(s: Soldier) -> Array:
	var out := []
	var inv := s.inventory
	for slot in Inventory.SLOTS:
		if inv.slots[slot] != &"":
			out.append("slot:%s=%s %s" % [slot, inv.slots[slot], JSON.stringify(GameState.from_json(_worn_state(inv, slot)), "", true)])
	for p: Dictionary in inv.attach_points():
		var att := inv.attachment(StringName(p.id))
		if not att.is_empty():
			out.append("molle:%s" % att.id)
	var stowed := {}
	for container in inv.search_containers():
		for entry: Dictionary in inv.containers[container]:
			var key := "item:%s %s" % [entry.id, JSON.stringify(GameState.from_json(entry.get("state", {})), "", true)]
			stowed[key] = int(stowed.get(key, 0)) + int(entry.count)
	for key: String in stowed:
		out.append("%s=%d" % [key, stowed[key]])
	if inv.hands != &"":
		out.append("hands:%s" % inv.hands)
	out.sort()
	return out


## Everything on `s` wherever it is (worn or stowed), as sorted "<id> <state> x<count>" lines
## (stacks summed), for comparing what moved between two inventories.
func _items_of(s: Soldier) -> Array:
	return _items_in([s])


## _items_of for several soldiers together.
func _items_in(soldiers: Array) -> Array:
	var counts := {}
	var add := func(id: StringName, state: Dictionary, n: int) -> void:
		if state == ItemDB.get_item(id).default_state():
			state = {}  # a plate fresh in its pocket is the same plate stowed
		var key := "%s %s" % [id, JSON.stringify(GameState.from_json(state), "", true)]
		counts[key] = int(counts.get(key, 0)) + n
	for s: Soldier in soldiers:
		var inv := s.inventory
		for slot in Inventory.SLOTS:
			if inv.slots[slot] != &"":
				add.call(inv.slots[slot], _worn_state(inv, slot), 1)
		for p: Dictionary in inv.attach_points():
			var att := inv.attachment(StringName(p.id))
			if not att.is_empty():
				add.call(StringName(att.id), {}, 1)
		for container in inv.search_containers():
			for entry: Dictionary in inv.containers[container]:
				add.call(entry.id, entry.get("state", {}), int(entry.count))
		if inv.hands != &"":
			add.call(inv.hands, {}, 1)
	var out := []
	for key: String in counts:
		out.append("%s x%d" % [key, counts[key]])
	out.sort()
	return out


## The world items there are now (instance id -> true), to spot new ones later (_new_items).
func _item_ids() -> Dictionary:
	var out := {}
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		out[node.get_instance_id()] = true
	return out


## Item ids of the world items that weren't there in `before` (_item_ids) and lie within
## `radius` of `pos`, sorted. Loot already lying about can roll; only new items count.
func _new_items(before: Dictionary, pos: Vector3, radius: float) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if not before.has(node.get_instance_id()) and not node.is_queued_for_deletion() \
				and _flat((node as Node3D).global_position, pos) <= radius:
			out.append(String((node as WorldItem).item_id))
	out.sort()
	return out


## A worn item's state as the gear helpers compare it: a carrier's without its MOLLE (they
## count what's on it and in its pouches on their own, whichever pouch it's in).
static func _worn_state(inv: Inventory, slot: StringName) -> Dictionary:
	var state := inv.state_of(slot).duplicate(true)
	state.erase("molle")
	return state


## [container, index] of the first stowed entry of `id` on `s`, or [&"", -1].
func _entry_index(s: Soldier, id: StringName) -> Array:
	for container in s.inventory.search_containers():
		var list: Array = s.inventory.containers[container]
		for i in list.size():
			if list[i].id == id:
				return [container, i]
	return [&"", -1]


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
	var quiet := await _wait_until(func() -> bool: return not _squad().any(func(s: Soldier) -> bool: return SquadAI.of(s).in_contact()),
		SquadAI.SQUAD_CONTACT_MEMORY_S + 5.0)
	if not quiet:
		print("    still in contact: %s" % [_squad().filter(func(s: Soldier) -> bool: return SquadAI.of(s).in_contact()).map(func(s: Soldier) -> String: return "%s (%s)" % [s.name, s.ai_status])])


## Everyone out of contact at once, between staged scenes: the squad now hears gunfire and
## remembers contact SQUAD_CONTACT_MEMORY_S, so one scene's shooting would carry into the next.
func _clear_contact() -> void:
	_firing = false
	for s: Soldier in _squad():
		s.threat_time = -1000.0
		var ai := SquadAI.of(s)
		ai._last_contact = -1000.0
		ai._fired_on_at = -1000.0
		ai.target = null
	level.squad_for(&"friendly").engaged_at = -1000.0


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


## Physics ticks until `s` stands on the ground, at most `ticks`. A soldier spawns 0.1 m up, and
## one shot before he lands goes down with that fall's speed (his ragdoll starts with it). Render
## frames don't count here: headless, two frames can pass inside one physics tick on a fast
## machine and span several on a slow one (CI), so a wait of frames gave each machine its own
## start.
func _until_on_floor(s: Soldier, ticks := 60) -> void:
	for i in ticks:
		await get_tree().physics_frame
		if s.is_on_floor():
			return


## The lowest (x) and highest (y) point of a ragdoll's part shapes, world height, as they'd be
## moved by `moved`.
func _ragdoll_span(r: Ragdoll, moved := Transform3D.IDENTITY) -> Vector2:
	var span := Vector2(INF, -INF)
	for p: Node3D in r.parts.values():
		var cs := p.get_child(0) as CollisionShape3D
		var t := moved * cs.global_transform
		var corners: Array[Vector3] = []
		if cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size / 2.0
			for i in 8:
				corners.append(t * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		else:
			var radius := (cs.shape as SphereShape3D).radius
			corners.append(t.origin + Vector3.UP * radius)
			corners.append(t.origin - Vector3.UP * radius)
		for c in corners:
			span = Vector2(minf(span.x, c.y), maxf(span.y, c.y))
	return span


## Captain: bodies that fall on each other rest on each other (ragdolls), nothing shoves a body
## lying there, and the living step over them.
func _test_ragdolls() -> void:
	print("Ragdolls")
	var spot := Vector3(25, 0.1, 40)
	var first := level.spawn_soldier({"name": "RagdollA", "faction": "hostile", "variant": "urban", "pos": spot,
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(first).process_mode = Node.PROCESS_MODE_DISABLED
	await _until_on_floor(first)  # shot standing, not still dropping from his spawn height
	first.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	var settled := await _wait_until(func() -> bool: return is_instance_valid(first.ragdoll) and first.ragdoll.frozen, 10.0)
	check(settled and first.model.ragdolled(), "a dead body falls as a ragdoll and settles")
	check(first.collision_layer == 0, "its capsule stands aside")
	var torso_a: Node3D = first.ragdoll.parts["torso"]
	check(torso_a.global_position.y < spot.y + 0.4, "lying on the ground (torso %.2f m up)" % (torso_a.global_position.y - spot.y))
	var chest := first.get_node(^"ChestHitbox") as Node3D
	var gap := (chest.global_transform * Vector3(0, 1.31, 0.11)).distance_to(torso_a.global_transform * Vector3(0, 0.41, 0.11))
	check(gap < 0.1,
		"its hitboxes lie with it (the chest %.2f m off its torso part)" % gap)
	# A second one goes down onto the first and comes to rest on top of him: not inside him, not
	# slid off. He dies a few metres off; then he's put lying along the first, torso over torso,
	# a little clear of him, and let go. (He used to be shot standing over the first, but which
	# way a standing body folds over one 0.34 m wide is chance: now and then on CI he fell
	# beside him, 0.05-0.09 m up, CI runs 158-180. Locally, moving his spawn 3 cm took his
	# highest part anywhere from 0.26 to 0.51 m, the torsos 0.31 to 1.30 m apart, R0454; laid
	# like this, 0.24-0.27 and 0.21-0.22 every time, R0449.)
	var second := level.spawn_soldier({"name": "RagdollB", "faction": "hostile", "variant": "urban", "pos": spot + Vector3(0, 0, -4.0),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(second).process_mode = Node.PROCESS_MODE_DISABLED
	await _until_on_floor(second)
	second.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	settled = await _wait_until(func() -> bool: return is_instance_valid(second.ragdoll) and second.ragdoll.frozen, 10.0)
	check(settled, "a second body goes down a few metres off")
	var torso_b: Node3D = second.ragdoll.parts["torso"]
	var along_a := Vector3(torso_a.global_basis.y.x, 0.0, torso_a.global_basis.y.z)  # pelvis to neck, flat
	var along_b := Vector3(torso_b.global_basis.y.x, 0.0, torso_b.global_basis.y.z)
	var turn := Basis(Vector3.UP, along_b.signed_angle_to(along_a, Vector3.UP))
	var chest_a := (torso_a.get_child(0) as Node3D).global_position  # the torso box's middle
	var lay := Transform3D(turn, chest_a - turn * (torso_b.get_child(0) as Node3D).global_position)
	lay.origin.y += _ragdoll_span(first.ragdoll).y - _ragdoll_span(second.ragdoll, lay).x + 0.1
	second.ragdoll.unfreeze()
	for p: RigidBody3D in second.ragdoll.parts.values():
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	second.global_transform = lay * second.global_transform  # his ragdoll takes its parts along
	settled = await _wait_until(func() -> bool: return second.ragdoll.frozen, 10.0)
	check(settled, "laid over the first and let go, he settles too")
	var top := -INF
	for p: Node3D in second.ragdoll.parts.values():
		top = maxf(top, p.global_position.y)
	check(top > torso_a.global_position.y + 0.1, "and rests on the first (his highest part %.2f m above the first's torso)" % (top - torso_a.global_position.y))
	var down := PhysicsRayQueryParameters3D.create(chest_a + Vector3.UP * 1.5, chest_a + Vector3.DOWN * 0.5, Ragdoll.LAYER)
	var met := first.get_world_3d().direct_space_state.intersect_ray(down)
	var met_body: Soldier = Ragdoll.body_of(met.collider) if not met.is_empty() else null
	check(met_body == second, "on top of him (straight down onto the first's chest, the first body met is %s)" % (met_body.name if met_body else "none"))
	# Torso flat on torso, their pivots are a torso's depth apart (0.22 m) less the few
	# millimetres physics lets bodies sink into each other; inside him, much less.
	check(torso_a.global_position.distance_to(torso_b.global_position) > 0.17, "not inside him (torsos %.2f m apart)" % torso_a.global_position.distance_to(torso_b.global_position))
	# Walking into the pile: the first body doesn't move. (The walker is one of ours: a hostile
	# one was shot by the squad 25-30 m off mid-walk and lay down short of the pile, R0160.)
	var before := torso_a.global_transform
	var walker := level.spawn_soldier({"name": "RagdollWalker", "faction": "friendly", "variant": "urban", "pos": spot + Vector3(-2.5, 0, 0),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(walker).process_mode = Node.PROCESS_MODE_DISABLED
	walker.move_input = Vector2(0, -1)
	walker.look_at(spot + Vector3(2.5, 0, 0) + Vector3(0, walker.global_position.y - spot.y, 0), Vector3.UP)
	# (Until he's past the pile, up to 6 s: a walk of 3 m takes about 2 s. A fixed 2.5 s hid
	# soldiers stuck at the pile's edge, R0142.)
	var started := Time.get_ticks_msec()
	var trail: Array[String] = []  # every 0.5 s: x, height over the ground, on the floor or not
	var past := false
	for tick in 13:
		trail.append("%.2f/%.2f%s" % [walker.global_position.x, walker.global_position.y - spot.y, "" if walker.is_on_floor() else "^"])
		past = walker.global_position.x > spot.x + 0.5
		if past:
			break
		await _seconds(0.5)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	# What he's against now (each: a body part or not, its name, the contact's height over his
	# feet and its normal's y): a stuck walker says why.
	var against: Array[String] = []
	for i in walker.get_slide_collision_count():
		var hit := walker.get_slide_collision(i)
		var collider := hit.get_collider() as Node
		against.append("%s %s %.2f m n.y %.2f" % ["body" if Ragdoll.body_of(collider) != null else "other",
			collider.name if collider != null else "?", hit.get_position().y - walker.global_position.y, hit.get_normal().y])
	walker.move_input = Vector2.ZERO
	check(torso_a.global_transform.origin.distance_to(before.origin) < 0.02, "walking into a body doesn't shove it")
	check(past, "the walker went on over the bodies (x %.2f, the pile at %.2f, %.1f s; against: %s)%s" % [walker.global_position.x, spot.x, took,
		", ".join(against) if not against.is_empty() else "nothing", "" if past else "; x/height (^ in the air): %s; he's %s%s, last hurt by %s" % [" ".join(trail),
		walker.vitals.condition_text(), " (a ragdoll)" if is_instance_valid(walker.ragdoll) else "", walker.vitals.last_cause]])
	for s: Soldier in [first, second, walker]:
		if is_instance_valid(s):
			s.queue_free()
	await _frames(2)
