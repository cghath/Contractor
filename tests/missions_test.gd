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
