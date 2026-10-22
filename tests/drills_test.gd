extends Node
## Headless checks for the reels' team and squad drills (docs/ai_tactics.md T1-T10) in
## SquadTactics: the near ambush, break contact as Battle Drill 3, rally points, fire superiority
## first, sectors of fire with shift and lift, assault lanes and consolidation, contact reports'
## third D, and doctrine by faction. The drills are staged on real squads (frozen men) and driven
## through SquadTactics' own steps; squad_test keeps the live fights.
##   <voxel godot exe> --headless --path . res://tests/drills_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel


func _ready() -> void:
	GameState.zone_id = "test_drills" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("DRILLS TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_scores()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	await _frames(5)
	await _test_drills()
	GameState.delete_save()
	print("DRILLS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sit(extra := {}) -> Dictionary:
	var s := {"up": 4, "down": 0, "contact": true, "known": 3, "fresh": true, "stale": false, "cluster": {"centre": Vector3.ZERO}, "range": 20.0,
		"enemy_building": {}, "home_building": {}, "in_home": false, "suppression": 0.1, "morale": 1.0, "ammo": 1.0, "cover": 0.0,
		"order": -1, "weapons_free": true, "centre": Vector3(0, 0, 20), "lead": null, "age": 0.0}
	s.merge(extra, true)
	return s


func _test_scores() -> void:
	print("T1: the near ambush is scored only when it applies")
	var d: Dictionary = SquadTactics.DOCTRINES[Doctrine.REGULAR]
	var hit := SquadTactics.score(_sit({"near_ambush": true}), d)
	check(SquadTactics._best(hit.scores) == SquadTactics.Option.NEAR_AMBUSH, "ambushed at 20 m while moving, in the open: assault through (%s)" % hit.why.get(SquadTactics.Option.NEAR_AMBUSH, ""))
	check(not SquadTactics.score(_sit(), d).scores.has(SquadTactics.Option.NEAR_AMBUSH), "a contact that wasn't an ambush: the usual drills")
	check(not SquadTactics.score(_sit({"near_ambush": true, "cover": 0.75}), d).scores.has(SquadTactics.Option.NEAR_AMBUSH), "already in cover: fight from it")
	check(not SquadTactics.score(_sit({"near_ambush": true, "range": 60.0}), d).scores.has(SquadTactics.Option.NEAR_AMBUSH), "60 m off: a far ambush (cover, fire, flank)")
	print("T10: doctrine by faction")
	for k: StringName in [&"jihadist", &"guerrilla", &"cartel"]:
		check(SquadTactics.DOCTRINES.has(k), "SquadTactics knows the %s doctrine" % k)
	check(float(SquadTactics.DOCTRINES[&"guerrilla"].break) > float(SquadTactics.DOCTRINES[&"jihadist"].break), "guerrillas break contact sooner than jihadists (hit and run)")


func _squad(nm: String, faction: String, at: Vector3, n: int) -> Squad:
	var sq := Squad.new()
	sq.name = nm
	sq.faction = StringName(faction)
	level.add_child(sq)
	var men: Array[Soldier] = []
	for i in n:
		var s := level.spawn_soldier({"name": "%s_%d" % [nm, i], "faction": faction, "variant": "urban", "pos": at + Vector3(i * 3.0, 0.1, i * 2.0),
			"loadout": ["m249" if i == 0 else "m4a1", "frag_grenade", "smoke_grenade"], "combat": 0.6, "discipline": 0.6, "guard": true})
		men.append(s)
	await _frames(3)
	for s in men:
		s.set_physics_process(false)
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		SquadAI.of(s).squad = sq
	if men.size() > 1:
		men[1].role = Roles.GRENADIER
	sq.leader = men[0]
	return sq


func _test_drills() -> void:
	var sq := await _squad("DrillSaber", "hostile", Vector3(-20, 0, 20), 4)
	var tac := SquadTactics.new(sq)
	tac.situation = tac.assess()
	var units := tac._free_units()
	var enemy := Vector3(-10, 0, -20)
	var aim := enemy + Vector3.UP
	var now := Soldier._now()
	print("T1: near ambush in play")
	tac.since = now
	tac._near_ambush(units, enemy, aim, "na", now)
	var base := units.filter(func(ai: SquadAI) -> bool: return StringName(ai.task.get("kind", &"")) == &"base")
	var charging := units.filter(func(ai: SquadAI) -> bool: return StringName(ai.task.get("kind", &"")) == &"near_ambush")
	check(base.size() == 2 and charging.size() == 2, "the gun and his buddy fire, the other two go through")
	var c0: Vector3 = charging[0].task.point
	check(float(charging[0].task.go_at) - now >= SquadTactics.CHARGE_DELAY_S - 0.01, "frags first: the charge goes %.1f s later" % (float(charging[0].task.go_at) - now))
	check(c0.distance_to(tac.situation.centre) > enemy.distance_to(tac.situation.centre), "through the enemy line, not to it")
	print("T1: whether a contact is a near ambush")
	tac._contact_was = false
	tac._centres = [{"at": now - 2.5, "pos": Vector3(-30, 0, 30)}]
	tac.situation = _sit({"centre": Vector3(-20, 0, 20), "range": 20.0})
	tac._track_contact(now)
	check(bool(tac.situation.near_ambush), "a moving squad fired on from 20 m: a near ambush")
	tac._contact_was = false
	tac._centres = [{"at": now - 2.5, "pos": Vector3(-20, 0, 20)}]
	tac.situation = _sit({"centre": Vector3(-20, 0, 20), "range": 20.0})
	tac._track_contact(now)
	check(not bool(tac.situation.near_ambush), "a squad lying still that opens up: not ambushed, it's the ambusher")
	print("T2: break contact, Battle Drill 3")
	tac.situation = tac.assess()
	tac.plan = {}
	tac._break_contact(units, enemy, aim, "bc", now)
	var order: Array = tac.plan.order
	var far0 := (order[0] as SquadAI).body.global_position.distance_to(enemy)
	check(units.all(func(ai: SquadAI) -> bool: return ai.body.global_position.distance_to(enemy) <= far0 + 0.01), "the man furthest back goes first")
	check(StringName((order[0] as SquadAI).task.kind) == &"break" and (order.slice(1) as Array).all(func(ai: SquadAI) -> bool: return StringName(ai.task.kind) == &"base"),
		"one moves, the rest keep firing")
	var rally: Vector3 = tac.plan.rally
	check(rally.distance_to(enemy) > (tac.situation.centre as Vector3).distance_to(enemy), "the rally point is away from the enemy")
	(order[0] as SquadAI).body.global_position = tac.plan.spots[order[0]]
	tac._break_contact(units, enemy, aim, "bc", now + 1.0)
	check(StringName((order[0] as SquadAI).task.kind) == &"garrison" and StringName((order[1] as SquadAI).task.kind) == &"break", "\"Set!\": he holds facing the enemy and the next goes")
	tac._break_contact(units, enemy, aim, "bc", now + 1.1 + SquadTactics.BD3_MOVER_S)
	check(int(tac.plan.idx) == 2, "a man who can't get there in 15 s doesn't hold the rest up")
	print("T3: rally points on the move")
	sq.remove_meta(&"rally")
	tac._rally_from = Vector3(-20, 0, 200)
	tac.situation = _sit({"contact": false, "centre": Vector3(-20, 0, 20)})
	tac._rally_points(now)
	var rp: Variant = sq.get_meta(&"rally", null)
	check(rp is Vector3 and (rp as Vector3).z > 20.0 and (rp as Vector3).distance_to(Vector3(-20, 0, 20)) <= SquadTactics.RALLY_BACK_M + 16.0,
		"150 m on: a rally point about 45 m back the way it came")
	print("T4: fire superiority first")
	tac.situation = tac.assess()
	tac.situation.cluster = {"centre": enemy}
	tac.plan = {"enemy": enemy, "names": units.map(func(ai: SquadAI) -> String: return String(ai.body.name)), "base": [units[0], units[1]], "moving": [units[2], units[3]],
		"route": [units[2].body.global_position, enemy + Vector3(20, 0, 0)], "side": "right", "lanes": {}, "base_spot": null, "drawn_at": now}
	tac._plan_at = now
	for ai in units:
		ai._next_shot = now - 5.0
	tac._flank(units, enemy, aim, "fl", now + 1.0)
	check(StringName(units[2].task.kind) == &"base" and not tac.plan.has("set_at"), "the base isn't firing yet: the flankers wait in cover, firing")
	units[0]._next_shot = now + 2.0
	tac._flank(units, enemy, aim, "fl", now + 2.0)
	check(tac.plan.has("set_at") and StringName(units[2].task.kind) == &"maneuver", "\"Base is set, move!\": now they go")
	print("T5: sectors of fire, shift and lift")
	var aims := SquadTactics.sector_aims([units[0], units[1], units[2]], enemy)
	var pts: Array = aims.values()
	var spread := 0.0
	for a: Vector3 in pts:
		for b: Vector3 in pts:
			spread = maxf(spread, a.distance_to(b))
	check(pts.size() == 3 and spread >= SquadTactics.SECTOR_EXTRA_M * 2.0, "three guns on three aims across the enemy and past its flanks (%.0f m wide)" % spread)
	units[2].body.global_position = enemy + Vector3(0, 0, 40)
	check(tac._base_shift([units[2]], enemy, [units[0]]).length() > 0.0, "a flanker within 50 m: the base shifts its fire beyond the objective")
	units[2].body.global_position = enemy + Vector3(0, 0, 20)
	check(SquadTactics._lifted([units[2]], enemy), "within 25 m: it lifts")
	print("T6: lanes and the limit of advance")
	var lanes := SquadTactics.assault_lanes([units[1], units[2], units[3]], enemy, Vector3(-10, 0, 20))
	var lp: Array = lanes.values()
	lp.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	check(lp.size() == 3 and absf((lp[1] as Vector3).distance_to(lp[0]) - SquadTactics.LANE_W) < 0.5, "each assaulter a lane 6 m from the next")
	check((lp[1] as Vector3).z < enemy.z, "through the position to its far side")
	check((lp[1] as Vector3).distance_to(enemy) <= SquadTactics.THROUGH_M, "no further than the limit of advance")
	tac._consolidate_until = now + 20.0
	tac._consolidate_at = enemy
	tac._consolidate(units, now)
	var faces := units.map(func(ai: SquadAI) -> Vector3: return ai.task.get("face", Vector3.ZERO))
	check(units.all(func(ai: SquadAI) -> bool: return StringName(ai.task.kind) == &"garrison") and (faces[0] as Vector3).dot(faces[2]) < -0.5,
		"consolidation: all-round security, each man facing his own way")
	print("T7: the contact report's third D")
	var friend := await _squad("DrillFriend", "friendly", Vector3(30, 0, 30), 1)
	var foes := await _squad("DrillFoes", "hostile", Vector3(30, 0, -20), 3)
	for f: Soldier in foes.members():
		friend.note_enemy(f, f.global_position)
	var text := Callouts._what_seen(friend, foes.members()[0])
	check(text.begins_with(", three men"), "\"Contact, twelve o'clock, 50 m, three men, MG\" (%s)" % text)
	print("T10: a squad's doctrine is its men's")
	for s: Soldier in sq.members():
		s.set_meta(&"faction_id", &"valley_shura")
	var dd := tac.doctrine()
	check(not dd.is_empty(), "the squad's biases come from its men's faction (%s)" % sq.members()[0].get_meta(&"faction_id"))
