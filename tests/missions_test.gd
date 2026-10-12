extends Node
## Headless checks for wave 4B part 2, missions in zones: Captain's first four mission types
## (raid, HVT capture, hostage rescue, intel grab) generated into the contract zones' layouts,
## their objectives placed at their target modules in a hosted world-scale zone, the people
## and intel each puts there, the People ledger reaching the contracts (deliveries at a
## landing zone, intel carried out, civilian casualties counted once each, a dead HVT), the
## clock on timed objectives, breaching charges (placed on any surface, riding a person they
## were stuck to, destroying a raid target), reinforcements sized from the true force and
## coming in at the zone's edge, and the briefing's markers.
##   <voxel godot exe> --headless --path . res://tests/missions_test.tscn
## Exits with the number of failures.

const ZONE := "ridge_hot"

var failures := 0
var level: ZoneLevel
var player: Soldier
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_missions" + tag  # never touch a real save
	Campaign.campaign_id = "test_missions_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	_test_generation()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	if level == null or not await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0):
		check(false, "the zone hosts with a player")
		_finish()
		return
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	await _frames(10)
	await _test_deployment()
	await _test_charges()
	await _test_failures()
	await _test_no_cuffs()
	await _test_alert()
	await _test_pressure()
	await _test_enemy_response()
	await _test_radio_chatter()
	await _test_field_radio()
	await _test_hq_posts()
	_finish()


func _finish() -> void:
	Campaign.reset_campaign()
	GameState.delete_save()
	print("MISSIONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Generation (no level) --------------------------------------------------------------------

func _test_generation() -> void:
	print("Mission types in the zones")
	var four: Array[String] = ["raid", "hvt_capture", "hostage_rescue", "intel_grab"]
	check(MissionRegistry.types() == four,
		"Captain's first four mission types (%s)" % [MissionRegistry.types()])
	var sound := true
	var zones_ok := true
	for z: Dictionary in MissionRegistry.zones():
		var layout := MissionRegistry.zone_def(String(z.zone_id))
		var hot := String(z.get("kind", "")) == "hot"
		zones_ok = zones_ok and not layout.is_empty() and (layout.modules as Array).size() >= 4 and (z.modules as Array).size() == (6 if hot else 4)
		zones_ok = zones_ok and layout == MissionRegistry.zone_def(String(z.zone_id))
		var size := float(layout.get("size_m", 0))
		zones_ok = zones_ok and (is_equal_approx(size, ZoneDef.HOT_SIZE_M) if hot else size * size >= 2.0e6 and size * size <= 4.0e6)
	check(zones_ok, "every zone is a generated layout, the same every time: contract zones 2-4 km² with all four module types, hot zones 16 km² with the enemy's structure too")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sites := {}
	for i in 200:
		var c := ContractGen.generate(rng, {"day": 1, "source": "board"})
		var layout := MissionRegistry.zone_def(String(c.zone_id))
		var module: Array = (layout.modules as Array).filter(func(m: Dictionary) -> bool: return m.id == c.module_id)
		sound = sound and module.size() == 1 and module[0].type == c.module and c.module in MissionRegistry.type_modules(MissionRegistry.type_def(c.type))
		for o: Dictionary in c.objectives:
			sound = sound and MissionRegistry.has_site(String(c.module), String(o.site)) and not String(o.text).contains("{")
			sites["%s/%s" % [c.type, o.site]] = true
			if c.type in ["hvt_capture", "hostage_rescue"] and not o.get("optional", false):
				sound = sound and is_equal_approx(float(o.get("time_limit_s", 0)), float(MissionRegistry.type_def(c.type).time_limit_min) * 60.0)
	check(sound, "each contract targets one of its zone's modules of a type it plays in; every objective has a site there and its text filled in")
	check(sites.has("raid/aa") and sites.has("raid/cache") and sites.has("hvt_capture/hvt") and sites.has("hostage_rescue/hostage") and sites.has("intel_grab/intel"),
		"raids hit AA guns and caches; HVTs, hostages and intel all come up (%d site kinds)" % sites.size())
	var crates := MissionRegistry.site("village", "cache")
	var outpost := MissionRegistry.site("outpost", "cache")
	var aa := MissionRegistry.site("outpost", "aa")
	check(int(crates.voxels) == 3600 and int(MissionRegistry.site("checkpoint", "cache").voxels) == 3600 and int(outpost.voxels) == 3000 and int(aa.voxels) > 300,
		"cache sites count their pristine voxels: three crates 3600, the outpost's stack 3000, the AA gun %d" % int(aa.voxels))
	var a := Contracts.contract(_add(_offer("hvt_capture")))
	var b := Contracts.contract(_add(_offer("hvt_capture")))
	var oa: Array = Objectives.from_contract(a)
	var ob: Array = Objectives.from_contract(b)
	check(oa[0].params.hvt != ob[0].params.hvt and String(oa[0].params.hvt).begins_with(String(MissionRegistry.site(a.module, "hvt").hvt)),
		"each HVT contract has its own person, even on the same site (%s, %s)" % [oa[0].params.hvt, ob[0].params.hvt])
	var phone: Array = oa.filter(func(o: Dictionary) -> bool: return o.kind == Objectives.EXTRACT_ITEM)
	check(not phone.is_empty() and phone[0].params.intel_ids == ["%s:intel_phone" % oa[0].params.hvt] and oa[0].params.person.intel[0].intel_id == phone[0].params.intel_ids[0],
		"the bonus phone is the one that HVT carries")
	check(String(oa[0].params.person.label).begins_with("HVT (") and String(a.title).begins_with("HVT capture"), "they have a name (%s)" % oa[0].params.person.label)
	var hvt_name := String(oa[0].params.person.name).split(" ")
	check(hvt_name.size() == 2 and hvt_name[1] in Names.INSURGENT and hvt_name[0] in Names.LOCAL_FIRST["insurgent"][Names.MALE],
		"a real name from the target faction's people (%s)" % oa[0].params.person.name)
	var nations := {}
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for i in 60:
		var surname := Names.mission_person(rng2, "hostage").split(" ")[1]
		for n: String in ["US", "UK", "CA", "insurgent"]:
			if surname in Names.POOLS[n]:
				nations[n] = true
	check(nations.size() >= 3, "hostages come from mixed nationalities (%s)" % [nations.keys()])


# --- A deployment in the zone ---------------------------------------------------------------

func _test_deployment() -> void:
	print("Four contracts in one zone")
	Contracts.new_full_campaign(77, 300000)
	var cids := {}
	for type: String in ["raid", "hvt_capture", "hostage_rescue", "intel_grab"]:
		cids[type] = _add(_offer(type))
		check(Contracts.server_accept(cids[type], ContractGen.default_terms()) == "", "accepted: %s" % Contracts.contract(cids[type]).title)
	var briefing := BaseHub.briefing_contract(cids.raid)
	var raid := Contracts.contract(cids.raid)
	var module := level.get_module(String(raid.module_id))
	var marker: Array = briefing.objectives[0].pos
	check(module != null and module.distance_to(Vector3(float(marker[0]), 0, float(marker[1]))) <= 0.5 and not (briefing.known_enemies as Array).is_empty(),
		"the briefing marks the raid at its module (%s) and what intel knows of the enemy there" % raid.module_id)
	# The raid's module streamed in (its first garrison out) before the briefing; the true force
	# is bigger than its own four posts.
	raid.enemy_count = 10
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	level._spawn_garrison(module)
	var first := _garrison(module).size()
	check(Contracts.server_start_deployment([], ZONE) == "" and Contracts.deployment().cids.size() == 4, "deployed on all four (a hot zone)")
	CompoundLevel.spawn_ai = false
	var garrison := _garrison(module)
	var apart := true
	for i in garrison.size():
		for j in range(i + 1, garrison.size()):
			apart = apart and garrison[i].global_position.distance_to(garrison[j].global_position) > 0.7
	var targeted: Array = Contracts.deployment().cids.map(func(cid: String) -> String: return String(Contracts.contract(cid).module_id))
	var other := level.modules().filter(func(m: ZoneModule) -> bool: return not m.module_id in targeted)[0] as ZoneModule
	var posts := (ZoneModules.GARRISON[module.type] as Array).size()
	var other_posts := (ZoneModules.GARRISON[other.type] as Array).size()
	check(first == posts and garrison.size() == 10 and apart and level.garrison_size(module.module_id) == 10 and level.garrison_size(other.module_id) == other_posts,
		"the raid's module (%s) holds the true count: its %d posts, topped up on deployment, none on top of another; other modules keep their own posts (%d)" % [module.type, posts, garrison.size()])
	check(garrison.all(func(s: Soldier) -> bool: return s.buddy != null), "each with a buddy")
	for s: Soldier in garrison:
		s.queue_free()  # the rest of this suite runs without AI
	var placed := true
	for o: Dictionary in Contracts.objectives.list:
		var m := level.get_module(String(o.params.get("module_id", "")))
		var p: Array = o.pos
		placed = placed and m != null and m.distance_to(Vector3(float(p[0]), float(p[1]), float(p[2]))) <= 0.5
	check(placed, "every objective sits in its module of the zone (%d)" % Contracts.objectives.list.size())
	await _frames(5)
	var people := level.people
	var hvt_o: Dictionary = Contracts.objectives.for_contract(cids.hvt_capture)[0]
	var hostage_o: Dictionary = Contracts.objectives.for_contract(cids.hostage_rescue)[0]
	var intel_o: Dictionary = Contracts.objectives.for_contract(cids.intel_grab)[0]
	var hvt := people.hvt(String(hvt_o.params.hvt))
	var hostage := people.hvt(String(hostage_o.params.hvt))
	check(hvt != null and Person.side_of(hvt) == Person.HOSTILE and hvt.inventory.count_of(&"intel_phone") == 1
		and hvt.global_position.distance_to(_v(hvt_o.pos)) < 1.0, "the HVT is where the contract says, with their phone (%s)" % (hvt.display_name() if hvt else "none"))
	check(hostage != null and Person.side_of(hostage) == Person.FRIENDLY, "the hostage is held there (%s)" % (hostage.display_name() if hostage else "none"))
	var laptop := _item(String(intel_o.params.intel_ids[0]))
	check(laptop != null and laptop.item_id == &"intel_laptop", "the laptop is placed")
	var civilians := people.people().filter(func(s: Soldier) -> bool: return Person.is_civilian(s))
	var points := get_tree().get_nodes_in_group(DeliveryPoint.GROUP)
	var civ_names := {}
	var civ_real := true
	for s: Soldier in civilians:
		var n := s.display_name().trim_prefix("Civilian (").trim_suffix(")")
		civ_real = civ_real and n.split(" ").size() == 2 and n.split(" ")[1] in Names.INSURGENT
		civ_names[n] = true
	check(civ_real and civ_names.size() == civilians.size(), "civilians have real names of the region, none twice (%s)" % [civ_names.keys()])
	check(civilians.size() >= 3 and points.size() == level.extraction_points().size(),
		"civilians go about their day in the zone's modules (%d) and every landing zone takes deliveries (%d)" % [civilians.size(), points.size()])
	for s: Soldier in [hvt, hostage]:
		if s:
			s.get_node(^"PersonAI").process_mode = Node.PROCESS_MODE_DISABLED
	var lz := level.extraction_points()[0]
	# The HVT, cuffed, brought to the landing zone.
	if hvt:
		people.server_set_state(hvt, {"cuffed": true})
		_place(player, lz + Vector3(1, 0, 0))
		_place(hvt, lz)
		await _wait_for(func() -> bool: return Contracts.objectives.get_objective(hvt_o.oid).state == Objectives.DONE, 3.0)
	check(Contracts.objectives.get_objective(hvt_o.oid).state == Objectives.DONE, "the HVT brought in cuffed: captured")
	if hostage:
		_place(hostage, lz + Vector3(-1, 0, 0))
		await _wait_for(func() -> bool: return Contracts.objectives.get_objective(hostage_o.oid).state == Objectives.DONE, 3.0)
	check(Contracts.objectives.get_objective(hostage_o.oid).state == Objectives.DONE, "the hostage brought out: rescued")
	# Intel: a laptop that isn't the one doesn't count; the one does, banked at the landing zone.
	player.inventory.take(&"assault_pack")
	player.inventory.take(&"intel_laptop", 1, {"intel_id": "someone_elses_laptop"})
	await _seconds(0.8)
	check(Contracts.objectives.get_objective(intel_o.oid).state == Objectives.ACTIVE and player.inventory.count_of(&"intel_laptop") == 0,
		"another laptop carried out is banked but isn't the contract's")
	if laptop:
		player.inventory.take(&"intel_laptop", 1, laptop.state)
		laptop.queue_free()
	await _wait_for(func() -> bool: return Contracts.objectives.get_objective(intel_o.oid).state == Objectives.DONE, 3.0)
	check(Contracts.objectives.get_objective(intel_o.oid).state == Objectives.DONE, "the contract's laptop carried to the landing zone: done")
	# A civilian hurt by the squad and then killed counts once.
	var civ: Soldier = civilians[0] if not civilians.is_empty() else null
	if civ:
		Harm.note_hit(civ, player)
		civ.vitals.server_kill()
		await _frames(3)
	check(int(Contracts.deployment().get("civilians", 0)) == 1 and People.casualties.size() == 2,
		"a civilian the squad wounded and killed is one casualty for the contract (%d events)" % People.casualties.size())
	# The raid: a charge set against the target.
	var raid_o: Dictionary = Contracts.objectives.for_contract(cids.raid)[0]
	var settings: Dictionary = MissionRegistry.data().settings
	var fuse: Variant = settings.charge_fuse_s
	settings.charge_fuse_s = 0.5
	_place(player, _v(raid_o.pos) + Vector3(1.5, 0, 0))
	player.inventory.take(&"plate_carrier")
	player.inventory.take(Charges.ITEM, 1)
	check(Contracts.objectives.server_place_charge(player, raid_o.oid), "a charge set: %s" % raid_o.text)
	_place(player, _v(raid_o.pos) + Vector3(40, 0, 0))  # and clear of the blast
	await _wait_for(func() -> bool: return Contracts.objectives.get_objective(raid_o.oid).state == Objectives.DONE, 3.0)
	check(Contracts.objectives.get_objective(raid_o.oid).state == Objectives.DONE, "it goes off: the raid's target is destroyed")
	settings.charge_fuse_s = fuse
	var tuning := Contracts.reinforcement_tuning(cids.raid)
	var force := Contracts.enemy_force(cids.raid)
	check(float(tuning.first_wave_s) >= 240.0 and float(tuning.first_wave_s) <= 420.0 and int(tuning.max_alive) == mini(int(force.count) + 8, 30)
		and is_equal_approx(float(tuning.combat), float(force.quality)), "reinforcements sized from the true force (%s)" % [tuning])
	var edge := level.reinforcement_edge([Vector2(player.global_position.x, player.global_position.z)])
	check(level.map_area().has_point(Vector2(edge.x, edge.z)) and Vector2(edge.x, edge.z).distance_to(Vector2(player.global_position.x, player.global_position.z)) >= ZoneLevel.REINFORCE_MIN_M,
		"waves come in at the zone's edge, inside the terrain and out of the squad's way (%.0f m off)" % Vector2(edge.x, edge.z).distance_to(Vector2(player.global_position.x, player.global_position.z)))
	var d := Contracts.server_end_deployment(Contracts.report_from_level(level, [player]))
	var outcomes := {}
	for line: Dictionary in d.get("contracts", []):
		outcomes[line.cid] = line.outcome
	check(cids.values().all(func(cid: String) -> bool: return outcomes.get(cid) == "completed") and int(d.civilians) == 1,
		"the debrief: all four completed, one civilian casualty (%s)" % [outcomes.values()])
	check((d.get("intel", []) as Array).any(func(e: Dictionary) -> bool: return e.id == "intel_laptop"), "and the laptop is intel to decide on")
	Contracts.server_finish_debrief()


# --- Charges ------------------------------------------------------------------------------------

func _test_charges() -> void:
	print("Breaching charges")
	var charges := Charges.of(level)
	var settings: Dictionary = MissionRegistry.data().settings
	var fuse: Variant = settings.charge_fuse_s
	settings.charge_fuse_s = 30.0
	var at := level.insertion_points()[0] + Vector3(20, 0, 0)
	_place(player, at)
	await _frames(2)
	var eye := player.camera.global_position
	var down := Charges.placement(player, eye, Vector3(0.3, -1, 0).normalized())
	check(down.ok and down.target == null and absf(down.pos.y - level.ground_height(down.pos.x, down.pos.z)) < 0.3,
		"looking down: it can go on the ground, which holds still")
	var air := Charges.placement(player, eye, Vector3.UP)
	check(not air.ok, "nothing to put it on looking at the sky")
	var host := level.spawn_soldier({"name": "Carrier1", "faction": "hostile", "variant": "urban", "pos": player.global_position + Vector3(0, 0, -1.2),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(host).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	var dir := (host.aim_point() - eye).normalized()
	var on_him := Charges.placement(player, eye, dir)
	var rides := on_him.target as Node
	check(on_him.ok and rides != null and (rides == host or rides.get_parent() == host), "looking at a person: it sticks to them (%s)" % (rides.name if rides else "nothing"))
	player.inventory.take(Charges.ITEM, 1)
	var id := charges.server_place_at(player, Charges.surface_transform(on_him.pos, on_him.normal, dir), on_him.target)
	await _frames(2)
	var node := charges.get_charge_node(id)
	var before := node.global_position if node else Vector3.ZERO
	host.global_position += Vector3(6, 0, 0)
	await _frames(2)
	node = charges.get_charge_node(id)
	check(id != "" and node != null and node.global_position.distance_to(before + Vector3(6, 0, 0)) < 0.3 and player.inventory.count_of(Charges.ITEM) == 0,
		"placed on him, it rides along as he moves; one charge used")
	_place(player, at + Vector3(-30, 0, 0))  # clear of the blast
	charges._due[id] = Charges._now()
	await _frames(3)
	check(charges.get_charge_node(id) == null and not charges.records.has(id) and host.vitals.injury() > 0.0, "it goes off on him")
	settings.charge_fuse_s = fuse
	host.queue_free()


# --- What fails a mission -------------------------------------------------------------------

func _test_failures() -> void:
	print("A dead HVT, a clock that runs out")
	var hvt_cid := _add(_offer("hvt_capture"))
	var hostage_cid := _add(_offer("hostage_rescue"))
	for cid: String in [hvt_cid, hostage_cid]:
		Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([], ZONE)
	await _frames(5)
	var hvt_o: Dictionary = Contracts.objectives.for_contract(hvt_cid)[0]
	var hvt := level.people.hvt(String(hvt_o.params.hvt))
	if hvt:
		hvt.vitals.server_kill()
	await _frames(3)
	check(Contracts.objectives.get_objective(hvt_o.oid).state == Objectives.FAILED, "the HVT killed: the capture fails")
	var hostage_o: Dictionary = Contracts.objectives.for_contract(hostage_cid)[0]
	await _seconds(0.7)
	check(String(Contracts.objectives.get_objective(hostage_o.oid).progress).ends_with("min left"), "a timed objective shows its clock (%s)" % Contracts.objectives.get_objective(hostage_o.oid).progress)
	Contracts.objectives.get_objective(hostage_o.oid).params.time_limit_s = 1.0
	await _seconds(1.5)
	check(Contracts.objectives.get_objective(hostage_o.oid).state == Objectives.FAILED, "and fails when it runs out")
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()


# --- A capture without zip cuffs -------------------------------------------------------------

func _test_no_cuffs() -> void:
	print("An HVT taken without zip cuffs")
	var cid := _add(_offer("hvt_capture"))
	Contracts.server_accept(cid, ContractGen.default_terms())
	Contracts.server_start_deployment([], ZONE)
	await _frames(5)
	var o: Dictionary = Contracts.objectives.for_contract(cid)[0]
	var people := level.people
	var hvt := people.hvt(String(o.params.hvt))
	if hvt == null:
		check(false, "the HVT is there")
		return
	var brain := hvt.get_node(^"PersonAI") as HvtAI
	while player.inventory.count_of(Person.ZIP_CUFFS) > 0:
		player.inventory.remove_one(Person.ZIP_CUFFS)
	var spot := level.extraction_points()[0] + Vector3(30, 0, 0)  # clear of the landing zone
	_place(hvt, spot)
	_place(player, spot + Vector3(1.5, 0, 0))
	people.server_surrender(hvt, "test")
	check(people.server_lead(player, hvt).ends_with("follows you") and not Person.is_cuffed(hvt), "he gave up: with no cuffs on him, he still follows when led")
	await _seconds(3.0)
	check(brain.bolts == 0 and Person.is_captive(hvt), "watched (someone within %.0f m), he stays" % HvtAI.WATCH_M)
	# Left alone: he takes it back and runs.
	people.server_order(player, hvt, "stop")
	_place(player, spot + Vector3(40, 0, 0))
	brain.bolt_scale = 100.0
	await _wait_for(func() -> bool: return brain.bolts > 0, HvtAI.BOLT_GRACE_S + HvtAI.BOLT_CHECK_S * 2 + 1.0)
	check(brain.bolts == 1 and not Person.is_captive(hvt) and String(Person.state(hvt).get("led_by", "")) == "",
		"left alone, the uncuffed HVT takes his surrender back and bolts (bolts %d, watched %s, uncuffed captive %s, will %.2f, %.1f m, mode %d)" % [brain.bolts, brain.watched(), brain.uncuffed_captive(), brain.bolt_will(), hvt.global_position.distance_to(player.global_position), brain.mode])
	brain.bolt_scale = 1.0
	# Cornered again, led to the landing zone uncuffed: captured.
	people.server_surrender(hvt, "test")
	brain.process_mode = Node.PROCESS_MODE_DISABLED  # the walk is ours
	people.server_lead(player, hvt)
	var lz := level.extraction_points()[0]
	_place(player, lz + Vector3(1, 0, 0))
	_place(hvt, lz)
	await _wait_for(func() -> bool: return Contracts.objectives.get_objective(o.oid).state == Objectives.DONE, 3.0)
	var delivered: Array = People.deliveries.filter(func(d: Dictionary) -> bool: return d.hvt_id == String(o.params.hvt))
	check(Contracts.objectives.get_objective(o.oid).state == Objectives.DONE and delivered.size() == 1 and not bool(delivered[0].cuffed),
		"brought in uncuffed: captured all the same")
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()


# --- Helpers ------------------------------------------------------------------------------------

func _offer(type: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + _made
	_made += 1
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type, "zone_id": ZONE})
	c.understated = false
	c.true_rating = c.rated
	c.enemy_count = c.enemy_est
	return c


func _add(c: Dictionary) -> String:
	return Contracts.server_add_offer(c)


## A module's garrison soldiers (callsigns "<module id>_H<n>"), their brains off.
func _garrison(module: ZoneModule) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and String(s.name).begins_with(("%s_H" % module.module_id).validate_node_name()) and not s.is_queued_for_deletion():
			if SquadAI.of(s):
				SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
			out.append(s)
	return out


func _item(uid: String) -> WorldItem:
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := n as WorldItem
		if item and item.uid == uid and not item.is_queued_for_deletion():
			return item
	return null


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = level.ground_point(pos)
	s.velocity = Vector3.ZERO


static func _v(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


# --- The hot zone's alert (4B part 3) --------------------------------------------------------

## Captain: the enemy knows only what its people see, hear and report, with radio delays.
func _test_alert() -> void:
	print("Alert")
	var alert := Alert.of(level)
	check(alert != null and alert.zone_state == Alert.State.NORMAL, "a hot zone has an alert, calm to start")
	if alert == null:
		return
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "outpost")[0]
	var spawn := func(n: String, at: Vector3) -> Soldier:
		var s := level.spawn_soldier({"name": "%s_A%s" % [site.module_id, n], "faction": "hostile", "variant": "urban",
			"pos": level.ground_point(at), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": alert.mode_at(at)})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		return s
	var a: Soldier = spawn.call("1", site.global_position)
	var b: Soldier = spawn.call("2", site.global_position + Vector3(4, 0, 0))
	await _frames(3)
	check(SquadAI.of(a).combat_mode == Squad.CombatMode.SAFE, "a calm site's guards are relaxed (safe)")
	var far := site.global_position + Vector3(250, 0, 0)
	Alert.server_noise(player, far, Alert.SHOT, true)
	check(alert._pending.is_empty(), "a suppressed shot 250 m off isn't heard")
	Alert.server_noise(player, far, Alert.SHOT)
	check(alert._pending.size() == 2 and alert.state_of(site.module_id) == Alert.State.SUSPICIOUS and alert.zone_state == Alert.State.NORMAL,
		"an unsuppressed one is: the site stands to at once (suspicious), the zone doesn't know yet")
	check(SquadAI.of(a).combat_mode == Squad.CombatMode.AWARE, "its guards are aware")
	b.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	alert.advance(70.0)
	check(alert.reports.size() == 1 and String(alert.reports[0].by) == String(a.name) and alert.zone_state == Alert.State.SUSPICIOUS,
		"after the radio delay one report reaches the net (the man killed first never sent his): the zone is suspicious")
	check(not alert.last_known().is_empty() and (alert.last_known().pos as Vector3).distance_to(far) < 1.0, "the enemy's last known position is the noise")
	Alert.server_sighting(a, player.global_position)
	alert.advance(70.0)
	check(alert.zone_state == Alert.State.ENGAGED and SquadAI.of(a).combat_mode == Squad.CombatMode.COMBAT, "a sighting reported: engaged, guards in combat mode")
	var r0 := float(alert.last_known().radius)
	alert.advance(60.0)
	check(float(alert.last_known().radius) > r0, "the last known position gets less certain with time (%.0f m -> %.0f m)" % [r0, float(alert.last_known().radius)])
	alert.advance(Alert.ENGAGED_COOL_S + 10.0)
	check(alert.state_of(site.module_id) == Alert.State.ALERTED, "20 minutes without contact: back to alerted, not calm")
	alert.advance(Alert.ALERTED_COOL_S + 10.0)
	check(alert.state_of(site.module_id) == Alert.State.SUSPICIOUS and alert.zone_state >= Alert.State.SUSPICIOUS, "hours later only suspicious: a loud zone stays twitchy")
	# A fallen comrade found by his own.
	alert.advance(Alert.SCAN_S + 0.1)
	alert.advance(70.0)
	check(alert.reports.any(func(r: Dictionary) -> bool: return r.kind == &"body"), "the body is found and reported")
	for s: Soldier in [a, b]:
		if is_instance_valid(s):
			s.queue_free()
	await _frames(2)



# --- Pressure, the enemy's answer, looted radios (4B part 3) ---------------------------------

## Captain: pressure builds from what the squad does, not from the clock; tiers bring the enemy's
## answer.
func _test_pressure() -> void:
	print("Pressure")
	var pressure := Pressure.of(level)
	var alert := Alert.of(level)
	check(pressure != null, "a hot zone keeps a pressure count")
	if pressure == null or alert == null:
		return
	_clear_waves()
	await _frames(2)
	_calm()
	var before := level.ai.get_children()
	var t := pressure.now()
	pressure.note_contact(true, t)
	pressure.note_contact(true, t + 30.0)
	check(is_equal_approx(pressure.points, Pressure.GAINS.firefight), "contact starts a firefight: +2 once, not per shot (%.1f)" % pressure.points)
	for k in range(60, int(Pressure.FIREFIGHT_LONG_S) + 1, 60):  # contact kept up, never a gap
		pressure.note_contact(true, t + k)
	check(is_equal_approx(pressure.points, 3.0), "a long firefight: +1 more per 3 minutes it lasts (%.1f)" % pressure.points)
	pressure.note_contact(true, t + Pressure.FIREFIGHT_LONG_S + Pressure.FIREFIGHT_GAP_S + 1.0)
	check(is_equal_approx(pressure.points, 5.0), "contact again after a quiet spell is a new firefight (%.1f)" % pressure.points)
	var p0 := pressure.points
	var foe := level.spawn_soldier({"name": "PressureFoe", "faction": "hostile", "variant": "urban",
		"pos": level.ground_point(player.global_position + Vector3(0, 0, 60)), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
	SquadAI.of(foe).process_mode = Node.PROCESS_MODE_DISABLED
	_kill(foe)
	pressure.server_tick()
	check(foe.vitals.is_dead() and is_equal_approx(pressure.points - p0, Pressure.GAINS.kill), "a hostile killed: +0.5 (%.1f)" % (pressure.points - p0))
	p0 = pressure.points
	Alert.server_noise(player, player.global_position + Vector3(5, 0, 0), Alert.BLAST)
	check(is_equal_approx(pressure.points - p0, Pressure.GAINS.explosion), "an explosion of ours: +1 (%.1f)" % (pressure.points - p0))
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "outpost")[0]
	p0 = pressure.points
	alert._receive({"kind": &"body", "pos": site.global_position, "area": site.module_id, "by": ""})
	check(alert.zone_state == Alert.State.ALERTED and is_equal_approx(pressure.points - p0, Pressure.GAINS.alarm),
		"the zone alerted (an alarm raised): +3 (%.1f)" % (pressure.points - p0))
	p0 = pressure.points
	alert.advance(Pressure.QUIET_S + 1.0)
	pressure.server_tick()
	check(is_equal_approx(pressure.points - p0, -Pressure.QUIET_LOSS), "10 quiet minutes: -1 (%.1f)" % (pressure.points - p0))
	alert.comms_down = true
	p0 = pressure.points
	pressure.server_add("explosion")
	check(is_equal_approx(pressure.points - p0, Pressure.GAINS.explosion * Pressure.COMMS_DOWN_GAIN), "with the comms site down every gain is halved (%.1f)" % (pressure.points - p0))
	alert.comms_down = false
	pressure.points = 9.9
	var below := pressure.tier()
	pressure.points = 10.0
	check(below == 0 and pressure.tier() == 1, "tier 1 from 10 points")
	pressure.points = 0.0
	pressure._tier = 0
	var tiers := []
	var on_tier := func(tier: int) -> void: tiers.append(tier)
	pressure.tier_changed.connect(on_tier)
	for i in 10:
		pressure.server_add("objective")
	pressure.tier_changed.disconnect(on_tier)
	check(tiers == [1, 2, 3, 4] and pressure.tier() == 4, "objectives done climb the tiers at 10, 20, 35 and 50 (%s)" % [tiers])
	_free_new(before)
	_calm()
	await _frames(2)


## Captain: patrols, checkpoints, the QRF from its bases, hunters at tier 3.
func _test_enemy_response() -> void:
	print("Enemy response")
	var er := EnemyResponse.of(level)
	var alert := Alert.of(level)
	var pressure := Pressure.of(level)
	check(er != null and er.reinforcements != null and er.reinforcements.driven, "a hot zone has an enemy response, driving its reinforcements (no timer waves)")
	if er == null or alert == null or pressure == null or er.reinforcements == null:
		return
	_clear_waves()
	_calm()
	er._last_qrf = -INF
	er._last_hunter = -INF
	var before := level.ai.get_children()
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	er.server_start()
	var routes: Array = level.def.get("patrols", [])
	var out := er.patrols.filter(func(r: Dictionary) -> bool: return not r.pending)
	check(not routes.is_empty() and er.patrols.size() == routes.size() and not out.is_empty()
		and out.all(func(r: Dictionary) -> bool: return r.soldiers.size() == EnemyResponse.PATROL_SIZE and (r.squad as Squad).patrol.size() >= 2),
		"roaming patrols set out: a pair on each route (%d routes, %d patrols, %d out)" % [routes.size(), er.patrols.size(), out.size()])
	var unseen := true
	for r: Dictionary in out:
		for s: Soldier in r.soldiers:
			unseen = unseen and Vector2(s.global_position.x - player.global_position.x, s.global_position.z - player.global_position.z).length() >= EnemyResponse.SPAWN_UNSEEN_M - 5.0
	check(unseen, "out of sight: none spawns within %.0f m of a player" % EnemyResponse.SPAWN_UNSEEN_M)
	er.server_tick()
	check(not er.checkpoints_closed, "calm and under tier 2, the checkpoints stay open")
	pressure.server_add("objective", 4.0)
	var checkpoints := level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "checkpoint")
	check(pressure.tier() == 2 and er.checkpoints_closed and not checkpoints.is_empty()
		and checkpoints.all(func(m: ZoneModule) -> bool: return alert.state_of(m.module_id) >= Alert.State.ALERTED) and alert.zone_state == Alert.State.NORMAL,
		"tier 2: checkpoints closed, their posts stood to (the zone itself still calm)")
	var twins := er.patrols.filter(func(r: Dictionary) -> bool: return r.second and not r.pending)
	check(not twins.is_empty() and twins.all(func(r: Dictionary) -> bool:
			return r.soldiers.size() == EnemyResponse.PATROL_SIZE and String((r.soldiers[0] as Soldier).name).begins_with("P%dB_" % int(r.k))),
		"tier 1 and up: patrols go in pairs, a second team walking each route the other way (%d)" % twins.size())
	var rec: Dictionary = out[0]
	var p0 := pressure.points
	for s: Soldier in rec.soldiers:
		_kill(s)
	er.server_tick()
	check(rec.lost and is_equal_approx(pressure.points - p0, Pressure.GAINS.patrol_lost), "a patrol wiped out: lost, +3 pressure (%.1f)" % (pressure.points - p0))
	var heard := alert.reports.size()
	alert.advance(Alert.CHECK_IN_S.y + Alert.CHECK_IN_CALL_S + 1.0)
	check(alert.reports.size() > heard and alert.reports.back().kind == &"missed_checkin" and alert.reports.back().get("patrol", false),
		"the wiped patrol misses its check-in: the net hears of it (on the alert's clock)")
	# A patrol goes to look at what was reported.
	var looker: Dictionary = {}
	for r: Dictionary in er.patrols:
		if not r.pending and not r.lost and not er._living(r.soldiers).is_empty():
			looker = r
			break
	if not looker.is_empty():
		for r: Dictionary in er.patrols:
			r.looking_until = -INF
		var spot := (er._living(looker.soldiers)[0] as Soldier).global_position + Vector3(40, 0, 0)
		alert._receive({"kind": &"shot", "pos": spot, "area": alert.area_of(spot), "by": ""})
		var looking := er.patrols.filter(func(r: Dictionary) -> bool: return float(r.looking_until) > er.now())
		check(looking.size() == 1 and (looking[0].squad as Squad).patrol.size() == 1 + EnemyResponse.LOOK_POINTS
			and Vector2((looking[0].squad as Squad).patrol[0].x - spot.x, (looking[0].squad as Squad).patrol[0].z - spot.z).length() < 2.0,
			"shots reported: the nearest patrol goes to look")
		alert.advance(EnemyResponse.LOOK_S + 1.0)
		er.server_tick()
		check(float(looking[0].looking_until) == -INF and (looking[0].squad as Squad).patrol == looking[0].walk, "after a look it goes back to its route")
	# The QRF.
	_calm()
	er._zone_was = Alert.State.NORMAL
	er._qrf_due = INF
	var lk := level.ground_point(player.global_position + Vector3(0, 0, -20))
	var bases := level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "qrf_base")
	bases.sort_custom(func(a: ZoneModule, b: ZoneModule) -> bool: return a.global_position.distance_to(lk) < b.global_position.distance_to(lk))
	var contact := {"kind": &"contact", "pos": lk, "area": alert.area_of(lk), "by": ""}
	var n := er.qrf_launches.size()
	alert._receive(contact)
	check(er.qrf_launches.size() == n and er._qrf_due < INF, "caught cold (calm straight to engaged): the QRF turns out first, nothing launched yet")
	alert.advance(EnemyResponse.QRF_TURNOUT_S + 1.0)
	er.server_tick()
	var launch: Dictionary = er.qrf_launches.back() if er.qrf_launches.size() > n else {}
	check(alert.zone_state == Alert.State.ENGAGED and er.qrf_launches.size() == n + 1 and not bases.is_empty()
		and String(launch.get("from", "")) == (bases[0] as ZoneModule).module_id and not (launch.get("soldiers", []) as Array).is_empty(),
		"engaged: the QRF launches from the nearest QRF base (%s, %d men)" % [launch.get("from", "none"), (launch.get("soldiers", []) as Array).size()])
	var wave: Dictionary = er.reinforcements.waves.back() if not er.reinforcements.waves.is_empty() else {}
	var squad := wave.get("squad") as Squad
	check(squad != null and squad.patrol.any(func(p: Vector3) -> bool: return Vector2(p.x - lk.x, p.z - lk.z).length() < 2.0),
		"the wave heads for the enemy's last known position")
	if bases.is_empty():
		await _end_response(er, before)
		return
	var first: ZoneModule = bases[0]
	level._spawn_garrison(first)
	var g := _garrison(first)
	for s in g:
		_kill(s)
	check(not g.is_empty() and level.site_down(first.module_id), "the nearest QRF base's garrison killed: the site is down")
	pressure.points = 0.0
	pressure._tier = 0
	er._last_qrf = -INF
	n = er.qrf_launches.size()
	alert.zone_state = Alert.State.ALERTED  # on standby: an alerted zone's QRF goes at once
	er._zone_was = Alert.State.ALERTED
	alert._receive(contact)
	if bases.size() >= 2:
		check(er.qrf_launches.size() == n + 1 and String(er.qrf_launches.back().from) == (bases[1] as ZoneModule).module_id,
			"on standby the next QRF goes at once, from the other base, none from the dead one")
	for m: ZoneModule in bases.slice(1):
		level._spawn_garrison(m)
		for s in _garrison(m):
			_kill(s)
	pressure.points = 0.0
	pressure._tier = 0
	er._last_qrf = -INF
	n = er.qrf_launches.size()
	alert._receive(contact)
	check(er.qrf_launches.size() == n, "every QRF base taken out: no QRF waves")
	pressure.server_add("objective", 4.0)
	er._last_qrf = -INF
	alert._receive(contact)
	check(pressure.tier() >= 2 and er.qrf_launches.size() == n, "not even at tier 2: the HQ doesn't stand in for dead QRF bases")
	er.server_tick()
	check(is_equal_approx(er.coordination(), maxf(1.0 - EnemyResponse.OFFICER_LOSS * bases.size(), EnemyResponse.MIN_COORDINATION)),
		"each QRF base's officer killed costs the enemy coordination (%.1f)" % er.coordination())
	# Hunters.
	pressure.points = 0.0
	pressure._tier = 0
	er._last_hunter = -INF
	pressure.server_add("objective", 7.0)
	var team: Dictionary = er.hunters[0] if er.hunters.size() == 1 else {}
	var hunters: Array = team.get("soldiers", [])
	var hsquad := team.get("squad") as Squad
	check(pressure.tier() == 3 and er.hunters.size() == 1 and hunters.size() >= EnemyResponse.HUNTER_SIZE.x and hunters.size() <= EnemyResponse.HUNTER_SIZE.y,
		"tier 3: a hunter team of 4 to 6 sets out (%d)" % hunters.size())
	check(hsquad != null and hsquad.patrol.any(func(p: Vector3) -> bool: return Vector2(p.x - lk.x, p.z - lk.z).length() < 2.0)
		and hunters.all(func(s: Soldier) -> bool: return s.inventory.count_of(EnemyResponse.SMOKE) > 0),
		"the hunters head for the last known position, carrying smoke")
	await _end_response(er, before)


func _end_response(er: EnemyResponse, before: Array) -> void:
	_free_new(before)
	er.patrols.clear()
	er.hunters.clear()
	er.reinforcement_pairs.clear()
	er._started = false
	for c in er.get_children():
		if c is Squad:
			c.queue_free()
	CompoundLevel.spawn_ai = false
	_calm()
	await _frames(3)


## Captain: no meter; a looted enemy radio lets the squad hear the enemy's net until it switches.
func _test_radio_chatter() -> void:
	print("Enemy radio chatter")
	var rc := RadioChatter.of(level)
	var alert := Alert.of(level)
	check(rc != null, "a hot zone has enemy radio chatter")
	if rc == null or alert == null:
		return
	_calm()
	_drop_all(player, &"enemy_radio")
	rc.server_tick()
	check(not rc.tuned, "without an enemy radio the squad hears nothing of the enemy's net")
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "outpost")[0]
	check(player.inventory.take(&"enemy_radio") == 1, "an enemy radio taken off a body")
	rc.server_tick()
	check(rc.tuned and not rc.lines.is_empty() and String(rc.lines.back().text).contains("radio check"), "taken: the squad is on the enemy's net")
	var n := rc.lines.size()
	var shot := {"kind": &"shot", "pos": site.global_position + Vector3(0, 0, -200), "area": site.module_id, "by": "test"}
	for i in 4:
		alert._receive(shot)
		await _frames(1)  # lines raised by a state change come after the report
		alert.advance(RadioChatter.LINE_GAP_S + 0.1)
		rc.server_tick()
	var shots := rc.lines.slice(n).filter(func(l: Dictionary) -> bool: return String(l.text).contains("shots heard, to the north"))
	check(not shots.is_empty() and String(shots[0].text).begins_with(rc._callsign(site.module_id)),
		"chatter flows: reports reach the squad, vague (%s)" % (shots[0].text if not shots.is_empty() else "nothing"))
	var callouts := Callouts.of(level)
	check(callouts != null and callouts.shown.any(func(l: Dictionary) -> bool: return String(l.speaker) == RadioChatter.SPEAKER),
		"it shows as subtitles from the enemy radio")
	alert._receive({"kind": &"body", "pos": site.global_position, "area": site.module_id, "by": ""})
	await _frames(1)
	alert.advance(RadioChatter.FREQ_SWITCH_S.y + 1.0)
	rc.server_tick()
	for i in RadioChatter.QUEUE_MAX + 1:
		alert.advance(RadioChatter.LINE_GAP_S + 0.1)
		rc.server_tick()
	check(not rc.tuned and String(rc.lines.back().text).contains("go to alternate"), "a body found: minutes later the enemy changes frequency (%s)" % rc.lines.back().text)
	var after := rc.lines.size()
	alert._receive(shot)
	await _frames(1)
	for i in 2:
		alert.advance(RadioChatter.LINE_GAP_S + 0.1)
		rc.server_tick()
	check(rc.lines.size() == after, "after the switch the old radio hears nothing")
	player.inventory.take(&"enemy_radio")
	rc.server_tick()
	check(rc.tuned, "another radio taken listens in again")
	_drop_all(player, &"enemy_radio")
	rc.server_tick()
	_calm()
	await _frames(2)


## Captain: radio contracts need the squad's own field radio.
func _test_field_radio() -> void:
	print("Radio contracts and the field radio")
	check(Contracts.radio_contract_problem() == "Radio contracts come in only in a hot zone", "no radio contracts outside a hot zone deployment")
	var cid := _add(_offer("raid"))
	Contracts.server_accept(cid, ContractGen.default_terms())
	check(Contracts.server_start_deployment([], ZONE) == "", "deployed to the hot zone")
	await _frames(5)
	var had := player.inventory.count_of(&"radio")
	_drop_all(player, &"radio")
	player.inventory.take(&"enemy_radio")
	check(Contracts.radio_contract_problem() == "No field radio in the squad" and Contracts.server_radio_contract() == "",
		"a looted enemy set can't reach the employer: no radio contract without a field radio")
	player.inventory.take(&"radio")
	var cids := (Contracts.deployment().cids as Array).size()
	check(Contracts.radio_contract_problem() == "" and Contracts.server_radio_contract() != "" and (Contracts.deployment().cids as Array).size() == cids + 1,
		"with the field radio along, a radio contract comes in and joins the deployment")
	check(InteractionMenu._check(&"field_radio", player, player) == "", "the player sees 'Radio for a contract' in his own menu")
	player._server_radio_contract.rpc_id(1)
	await _frames(2)
	check((Contracts.deployment().cids as Array).size() == cids + 2, "and using it brings in another")
	var debug := level.get_node_or_null(^"HotZoneDebug") as HotZoneDebug
	if debug:
		var t := Alert.of(level).now()
		debug.skip(HotZoneDebug.SKIP_S)
		check(debug.text().begins_with("HOT ZONE") and Alert.of(level).now() >= t + HotZoneDebug.SKIP_S - 0.1,
			"debug builds: the hot zone readout, and Page Down skips the enemy's clock")
	_drop_all(player, &"enemy_radio")
	_drop_all(player, &"radio")
	if had > 0:
		player.inventory.take(&"radio", had)
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()
	await _frames(2)


## Captain (2026-10-12): the HQ's corner towers have their parapets on their outer sides, and
## garrison posts face out of their site: the gate guards stand behind the sandbags, facing the gate.
func _test_hq_posts() -> void:
	print("HQ posts")
	var towers := {"ne": Vector2(15.2, -17.6), "sw": Vector2(-17.6, 15.2)}
	var outer := {"ne": [AABB(Vector3(15.2, 3.1, -17.6), Vector3(2.6, 0.7, 0.3)), AABB(Vector3(17.5, 3.1, -17.6), Vector3(0.3, 0.7, 2.6))],
		"sw": [AABB(Vector3(-17.6, 3.1, 17.5), Vector3(2.6, 0.7, 0.3)), AABB(Vector3(-17.6, 3.1, 15.2), Vector3(0.3, 0.7, 2.6))]}
	# The inner sides, short of the corners where the outer parapets end.
	var inner := {"ne": [AABB(Vector3(15.55, 3.1, -15.3), Vector3(1.9, 0.7, 0.3)), AABB(Vector3(15.2, 3.1, -17.25), Vector3(0.3, 0.7, 1.9))],
		"sw": [AABB(Vector3(-17.25, 3.1, 15.2), Vector3(1.9, 0.7, 0.3)), AABB(Vector3(-15.3, 3.1, 15.55), Vector3(0.3, 0.7, 1.9))]}
	var ok := true
	for k: String in towers:
		for box: AABB in outer[k]:
			ok = ok and ZoneModules.solid_voxels_in("hq", box.grow(-0.05)) > 0
		for box: AABB in inner[k]:
			ok = ok and ZoneModules.solid_voxels_in("hq", box.grow(-0.05)) == 0
	check(ok, "the HQ's corner towers: parapets on their two outer sides, none facing in")
	var hq: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "hq")[0]
	var gate := [ZoneModules.GARRISON.hq[4], ZoneModules.GARRISON.hq[5]]
	var facing := true
	for p: Vector3 in gate:
		var yaw := ZoneLevel.post_yaw(hq, hq.to_global(p))
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		facing = facing and forward.dot(Vector3(0, 0, 1)) > 0.7 and p.z < 15.6  # the gate is south (+z); sandbags from z 15.6
	check(facing, "the gate guards stand behind the sandbags, facing the gate")


## Back to calm: the alert's areas and the pressure points reset (no check-ins come due).
func _calm() -> void:
	var alert := Alert.of(level)
	var pressure := Pressure.of(level)
	if alert:
		alert.areas = {}
		alert.zone_state = Alert.State.NORMAL
		alert.lkp = {}
		alert._pending.clear()
		alert._overdue.clear()
		alert.comms_down = false
		for m: ZoneModule in level.modules():
			alert._check_ins[m.module_id] = INF
	if pressure:
		var t := pressure.now()
		pressure.points = 0.0
		pressure._tier = 0
		pressure._zone_state = Alert.State.NORMAL
		pressure._start = t
		pressure._last_quiet = t
		pressure._last_gain = t
		pressure._times_paid = 0
		pressure._contact_last = -INF
		pressure._long_paid = 0


## The reinforcement waves' soldiers gone (the alert test launched a QRF).
func _clear_waves() -> void:
	var reinforcements := MapNodes.reinforcements(level)
	if reinforcements == null:
		return
	for wave: Dictionary in reinforcements.waves:
		for s: Variant in wave.soldiers:
			if is_instance_valid(s):
				(s as Node).queue_free()


## Every hostile spawned since `before` (level.ai's children then) gone.
func _free_new(before: Array) -> void:
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and not before.has(s) and not s.is_queued_for_deletion():
			s.queue_free()


func _kill(s: Soldier) -> void:
	for i in 5:
		if s.vitals.is_dead():
			return
		s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})


func _drop_all(s: Soldier, id: StringName) -> void:
	while s.inventory.count_of(id) > 0:
		s.inventory.remove_one(id)
