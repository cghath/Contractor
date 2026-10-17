extends Node
## Audit observations: PASS means a suspected defect was reproduced, not fixed.
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
		print("EXECUTIVE_AUDIT TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.zone_id = "test_executive_" + OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = GameState.zone_id
	Campaign.reset_campaign()
	GameState.delete_save()
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
	await probe_cleanup_persistence()
	GameState.delete_save()
	Campaign.reset_campaign()
	print("EXECUTIVE_AUDIT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
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
			"employer": o.employer in MissionRegistry.employers(), "enemy": o.target in MissionRegistry.enemies(),
			"zone_kind": o.zone_kind == zone.kind}
		for key: String in conditions:
			if not conditions[key]:
				print("  board diagnostic: %s, %s, %s, employer %s, target %s, failed %s" % [o.title, o.type, o.module, o.employer, o.target, key])

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
	var hvt := layer.server_spawn_person({"name": "AuditCommanderKilledBeforeTick", "kind": "hvt", "side": "hostile",
		"hvt_id": "audit_unobserved", "pos": hq.global_position + Vector3.UP * 0.1})
	hvt.set_physics_process(false)
	hvt.get_node(NodePath(PeopleLayer.BRAIN)).set_physics_process(false)
	check(Person.is_hvt(hvt) and command._commander_hvt == "", "hostile HVT commander spawned at HQ between command ticks")
	hvt.vitals.server_kill()
	command._watch_command()
	check(hvt.vitals.is_dead() and not command._find_commander_hvt() and command.commander_state == "commanding",
		"commander killed before discovery never causes headless state")
	var control := layer.server_spawn_person({"name": "AuditCommanderObserved", "kind": "hvt", "side": "hostile",
		"hvt_id": "audit_observed", "pos": hq.global_position + Vector3.UP * 0.1})
	control.set_physics_process(false)
	control.get_node(NodePath(PeopleLayer.BRAIN)).set_physics_process(false)
	check(command._find_commander_hvt(), "positive control: live commander is discovered")
	control.vitals.server_kill()
	command._watch_command()
	check(command.commander_state == "headless", "positive control: observed commander death causes headless state")
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
	check(spawned > before and command.reserves == 0.0, "QRF spawns more soldiers than the commander's remaining reserves")
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
	check(record.label != callsign, "saved human name differs from the stable post id that the garrison's exclusion checks")
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
	check(duplicate != null and duplicate.vitals.is_up() and is_instance_valid(dead),
		"restoring the saved corpse then initializing garrison also creates the same post alive")
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
	check(dead.is_queued_for_deletion(), "cleanup deletes the corpse while player is beside its visible body")
	check(GameState.save_zone() and not GameState.bodies.any(func(b: Dictionary) -> bool: return b.uid == dead_uid),
		"save after cleanup no longer records the killed garrison post")
	await frames(3)
	GameState.load_zone()
	level._garrisoned.erase(module.module_id)
	level._ai_ready = true
	CompoundLevel.spawn_ai = true
	level._spawn_garrison(module) # same initializer used on a fresh zone visit
	while level.garrison_pending(module.module_id) > 0:
		await get_tree().process_frame
	var returned := level.ai.get_node_or_null(NodePath(callsign)) as Soldier
	check(returned != null and returned.vitals.is_up(), "garrison initialization respawns the killed post from the cleaned save")
