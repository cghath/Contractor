extends Node
## Regression coverage for the October 17 executive audit. Uses isolated test saves.
var failures := 0
var level: ZoneLevel
var player: Soldier
var command: EnemyCommand

func check(ok: bool, text: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		failures += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("AUDIT_FIXES TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.zone_id = "test_audit_fixes_" + OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = GameState.zone_id
	Campaign.reset_campaign()
	GameState.delete_save()
	probe_legacy_save()
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	PeopleLayer.surrender_enabled = false
	probe_closed_duplication()
	probe_board_validation()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(1)
	main.host_zone({"id": "audit", "name": "Executive audit", "kind": "hot", "seed": 4417,
		"size_m": 768.0, "relief_m": 0.0, "terrain": "plain", "no_pallets": true,
		"modules": [{"id": "audit_hq", "type": "hq", "pos": [0, 0]},
			{"id": "audit_qrf", "type": "qrf_base", "pos": [-240, -120]},
			{"id": "audit_town", "type": "town#5", "pos": [-240, 240]},
			{"id": "audit_compound", "type": "compound", "pos": [192, 144]}],
		"insertion": [[300, -300]], "extraction": [[300, -300]]})
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1") as Soldier
	player.set_physics_process(false)
	player.player_input.set_process(false)
	player.player_input.set_physics_process(false)
	command = EnemyCommand.of(level)
	command.set_process(false)
	var response := EnemyResponse.of(level)
	response.set_process(false)
	level.get_node(^"ZoneCleanup").set_process(false)
	await frames(4)
	await probe_commander_registration()
	probe_reserve_accounting()
	await frames(3)
	await probe_urban_defence()
	await probe_cleanup_persistence()
	GameState.delete_save()
	Campaign.reset_campaign()
	print("AUDIT_FIXES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)

func probe_board_validation() -> void:
	var offers := ContractGen.generate_board(1234, 1, {"meridian": 10, "black_ridge": -60, "salvage_union": 0}, 6)
	for o: Dictionary in offers:
		var zone := MissionRegistry.zone(o.zone_id)
		var def := MissionRegistry.type_def(o.type)
		var conditions := {"rated": int(o.rated) >= 1 and int(o.rated) <= 5,
			"truth": int(o.true_rating) >= int(o.rated), "pay": int(o.base_pay) > 0,
			"objectives": not (o.objectives as Array).is_empty(),
			"type_allows_module": ZoneModules.base(o.module) in MissionRegistry.type_modules(def),
			"zone_has_module": ZoneModules.base(o.module) in zone.modules,
			"has_target": String(o.module_id) != "" or def.has("scenario"),
			"employer": o.employer in MissionRegistry.employers() and o.employer != o.target, "enemy": o.target in MissionRegistry.enemies(),
			"zone_kind": o.zone_kind == zone.kind}
		check(conditions.values().all(func(ok: bool) -> bool: return ok), "valid contract parties and target: " + String(o.title))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for bad in ["black_ridge", "missing"]:
		var o := ContractGen.generate(rng, {"zone_id": "pass_hot", "employer": bad})
		check(o.employer in MissionRegistry.employers() and o.employer != o.target, "invalid explicit employer falls back to a valid client")


func probe_legacy_save() -> void:
	var legacy := {"version": 1, "bodies": [{"uid": "legacy_body", "label": "Hostile2", "faction": "hostile", "pos": [0, 0, 0]}]}
	check(GameState.write_safely(GameState.save_path(), JSON.stringify(legacy)), "legacy save fixture written")
	GameState.load_zone()
	check(GameState.post_is_fallen("Hostile2") and GameState.bodies.size() == 1, "older callsign-labelled corpses migrate into the fallen-post ledger")
	GameState.delete_save()
	GameState.load_zone()
	check(GameState.fallen_posts.is_empty(), "loading an empty zone resets the fallen-post ledger")

func probe_closed_duplication() -> void:
	var dead := Soldier.new()
	var looter := Soldier.new()
	dead.inventory = Inventory.new()
	looter.inventory = Inventory.new()
	dead.inventory.take(&"assault_pack")
	dead.inventory.take(&"aid_bag", 1, {"held": [{"id": &"pressure_bandage", "count": 2}]})
	var before := dead.inventory.medical_count(&"pressure_bandage")
	looter._loot_all_at_once(dead, dead.gear_entries())
	var after := looter.inventory.medical_count(&"pressure_bandage") + dead.inventory.medical_count(&"pressure_bandage")
	check(before == 2 and after == 2, "prior high-priority aid-bag duplication is fixed: two bandages remain two")
	dead.inventory.free()
	looter.inventory.free()
	dead.free()
	looter.free()

func probe_commander_registration() -> void:
	var layer := PeopleLayer.find(level)
	var hq := level.get_module("audit_hq")
	for fate in ["dead", "cuffed", "surrendered", "delivered"]:
		command._commander_hvt = ""
		command.commander_state = "commanding"
		var id: String = "audit_commander_" + String(fate)
		var hvt := layer.server_spawn_person({"name": id, "kind": "hvt", "side": "hostile",
			"hvt_id": id, "pos": hq.global_position + Vector3.UP * 0.1})
		hvt.set_physics_process(false)
		hvt.get_node(NodePath(PeopleLayer.BRAIN)).set_physics_process(false)
		check(Person.is_hvt(hvt) and command._commander_hvt == id, "HQ commander registered before the first tick: " + fate)
		if fate == "dead":
			hvt.vitals.server_kill()
		else:
			layer.server_set_state(hvt, {fate: true})
		command._watch_command()
		check(command.commander_state == "headless", "immediate commander loss causes headless state: " + fate)
		hvt.queue_free()
		await frames(2)

func probe_reserve_accounting() -> void:
	command.commander_state = "commanding"
	command.consolidated = false
	command.caution = 0.0
	command.operations.clear()
	command.reserves = 3.0
	var target := player.global_position
	command._on_reported({"kind": &"contact", "pos": target, "seen": 1, "exo": 0})
	command.alert.lkp = {"pos": target, "time": command.now(), "radius": 50.0}
	var response := EnemyResponse.of(level)
	var r := response.reinforcements
	r.params = Reinforcements.DEFAULTS.duplicate()
	r.waves_sent = 6 # later-wave state, using normal wave-size calculation and default caps
	var before := command.reserves
	var total := r.hostiles_alive()
	response._launch_qrf()
	var spawned := r.hostiles_alive() - total
	print("  reserves before %.0f, soldiers spawned %d, reserves after %.0f" % [before, spawned, command.reserves])
	check(spawned == 2 and is_equal_approx(command.reserves, before - spawned), "later QRF wave is capped to whole pairs within actual reserves")
	command.operations.clear()
	var after := command.reserves
	response._launch_qrf()
	check(is_equal_approx(command.reserves, after) and r.hostiles_alive() - total == spawned, "insufficient reserves launch nobody and spend nothing")
	command.reserves = 8.0
	command.operations.clear()
	check(command.approve("hunters", target, 4) and command.reserves == 4.0, "hunt authorizes its actual planned allocation")
	command.refund_men(2)
	check(command.reserves == 6.0, "unspawned allocation returns to reserves")
	for w: Dictionary in r.waves:
		for s: Soldier in w.soldiers:
			s.queue_free()

func probe_cleanup_persistence() -> void:
	var module := level.get_module("audit_compound")
	var callsign := level._garrison_callsign(module, 0)
	var dead := level.spawn_soldier({"name": callsign, "faction": "hostile", "variant": "urban",
		"pos": module.global_position + Vector3(0, 0.1, 25), "loadout": ["akm"], "combat": 0.5, "discipline": 0.5, "guard": true})
	dead.set_physics_process(false)
	SquadAI.of(dead).set_physics_process(false)
	dead.vitals.server_kill()
	await frames(4)
	var dead_uid := dead.body_uid
	check(GameState.save_zone() and GameState.bodies.any(func(b: Dictionary) -> bool: return b.uid == dead_uid),
		"dead garrison post is initially recorded in the saved zone")
	var record: Dictionary = GameState.bodies.filter(func(b: Dictionary) -> bool: return b.uid == dead_uid)[0].duplicate(true)
	print("  saved garrison: node %s, saved label %s" % [callsign, record.label])
	check(record.label != callsign and record.spawn_id == callsign and GameState.post_is_fallen(callsign), "saved display name retains the stable original post separately")
	GameState.fallen_posts.clear()
	GameState.load_zone()
	check(GameState.post_is_fallen(callsign), "a cold load restores the fallen-post ledger")
	dead.queue_free()
	await frames(2)
	dead = level.server_spawn_body(record) # the production restoration used on zone load
	await frames(4)
	level._ai_ready = true
	CompoundLevel.spawn_ai = true
	level._garrisoned.erase(module.module_id)
	level._spawn_garrison(module)
	while level.garrison_pending(module.module_id) > 0:
		await get_tree().process_frame
	var duplicate := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	check(duplicate == null and is_instance_valid(dead) and dead.spawn_id == callsign,
		"restoring a renamed corpse does not respawn its original post")
	for n in level.ai.get_children():
		n.queue_free()
	CompoundLevel.spawn_ai = false
	await frames(3)
	if not is_instance_valid(dead.ragdoll):
		check(false, "cleanup probe has a ragdoll")
		return
	for part: RigidBody3D in dead.ragdoll.parts.values():
		part.freeze = true
		part.global_position += Vector3.RIGHT * 30.0
	dead.ragdoll._send(true)
	await frames(5)
	player.global_position = dead.body_point()
	var gap := dead.body_point().distance_to(dead.global_position)
	check(gap > ZoneCleanup.NEAR_M and player.global_position.distance_to(dead.body_point()) < 1.0,
		"player is beside visible corpse, over 20 m from its old capsule (%.1f m)" % gap)
	var cleanup := level.get_node(^"ZoneCleanup") as ZoneCleanup
	cleanup.server_sweep(dead.died_at + ZoneCleanup.LIFE_S.y + 1.0)
	check(not dead.is_queued_for_deletion(), "cleanup preserves a corpse while a player is beside its visible body")
	player.global_position += Vector3.RIGHT * 100.0
	dead.carried_by = player
	cleanup.server_sweep(dead.died_at + ZoneCleanup.LIFE_S.y + 1.0)
	check(not dead.is_queued_for_deletion(), "cleanup preserves a carried corpse")
	dead.carried_by = null
	cleanup.server_sweep(dead.died_at + ZoneCleanup.LIFE_S.y + 1.0)
	check(dead.is_queued_for_deletion(), "cleanup removes an old uncarried corpse with nobody near it")
	check(GameState.save_zone() and not GameState.bodies.any(func(b: Dictionary) -> bool: return b.uid == dead_uid),
		"save after cleanup removes the physical corpse")
	await frames(3)
	GameState.load_zone()
	level._garrisoned.erase(module.module_id)
	level._ai_ready = true
	CompoundLevel.spawn_ai = true
	level._spawn_garrison(module) # same initializer used on a fresh zone visit
	while level.garrison_pending(module.module_id) > 0:
		await get_tree().process_frame
	var returned := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	check(returned == null and GameState.post_is_fallen(callsign), "fallen post stays cleared after corpse cleanup, saving and cold loading")


func probe_urban_defence() -> void:
	var town := level.get_module("audit_town")
	var defence := level.get_node(^"UrbanDefence") as UrbanDefence
	defence.set_process(false)
	command.commander_state = "headless"  # exercise local defenders without strategic relief
	var reserve := ZoneModules.town_reserve(town.type)
	var points: Array[Vector3] = []
	for p: Vector3 in ZoneModules.town_fallback(town.type):
		points.append(town.to_global(p))
	check(reserve.size() == 2 and not points.is_empty(), "town has a reserve pair and indoor fallback positions")
	if reserve.size() != 2 or points.is_empty():
		return
	var target := town.global_position
	var men: Array[Soldier] = []
	for i: int in [0, reserve[0], reserve[1]]:
		var s := level.spawn_soldier({"name": level._garrison_callsign(town, i), "faction": "hostile", "variant": "urban",
			"pos": target + Vector3(0, 0.1, 5), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
		s.set_physics_process(false)
		SquadAI.of(s).set_physics_process(false)
		men.append(s)
	level._garrisoned[town.module_id] = int(reserve.back()) + 1
	var alert := Alert.of(level)
	alert.lkp = {"pos": target, "time": command.now(), "radius": 50.0}
	alert.areas[town.module_id] = {"state": Alert.State.ENGAGED, "since": command.now(), "contact": command.now()}
	var defender := men[0]
	defender.buddy = men[1]
	men[1].vitals.server_kill()
	defence.server_tick()
	var reserve_brain := SquadAI.of(men[2])
	check(not reserve_brain.guard and reserve_brain.squad != null and reserve_brain.squad.patrol.size() == 1
		and reserve_brain.squad.patrol[0].distance_to(UrbanDefence._nearest(points, target)) < 1.0,
		"engaged town sends its surviving reserve toward the side being hit")
	check(int(defender.get_meta(&"fell_back", 0)) == 1 and not SquadAI.of(defender).guard,
		"a defender whose buddy falls moves to a safer indoor fallback")
	var teams := defence._teams
	defence.server_tick()
	check(defence._teams <= teams + 1, "town reserve is committed only once")
	for s in men:
		s.queue_free()
	await frames(2)
