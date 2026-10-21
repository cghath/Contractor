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
	HotZoneOps.enabled = false  # one contract at a time below; _test_hot_zone_ops turns it on
	EnemyDrones.enabled = false  # none on their own (wave 6): _test_enemy_drones sends its own
	# None on their own either (R2255: once the living war hands the zone to the Shura or the Banner,
	# a random bomber walked in mid-test and broke the alert, pressure and bomber checks); the
	# enemy response section sends its own.
	Bombers.enabled = false
	Virtualizer.enabled = false  # the response's groups stay real here (they're checked man by man); virtualization_test has its own
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
	await _test_clear_unvisited()
	await _test_charges()
	await _test_failures()
	await _test_scenarios()
	await _test_no_cuffs()
	await _test_alert()
	await _test_pressure()
	await _test_command_qrf()
	# These drive the response and the enemy's net by hand: EnemyCommand's own strategic orders
	# (probes, counterattacks, guards, refills on its clock) would take their spawn slots and
	# reserves, so it stands down around them. Everything else runs with it.
	_command_on(false)
	await _test_enemy_response()
	await _test_radio_chatter()
	_command_on(true)
	await _test_field_radio()
	_command_on(false)
	await _test_hot_zone_ops()
	_command_on(true)
	await _test_hq_posts()
	_test_zone_enemy()
	await _test_rival_team()
	await _test_faction_skirmish()
	await _test_roadside_ieds()
	_test_enemy_drones()
	_test_strongbox()
	await _test_cartel_site()
	await _test_variety_played()  # late: it blows the comms site's mast, which stays down (the hot zone ops checks want it standing)
	await _test_forward_observer()  # fire support (2026-10-20): its own section at the end
	await _test_respawn_points()
	await _test_scenario_resume()
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
	var nine: Array[String] = ["raid", "hvt_capture", "hostage_rescue", "intel_grab", "convoy_ambush", "defend_hold", "crew_rescue", "sabotage", "recon", "psd_escort", "supply_line", "manhunt", "convoy_chase", "locals_checkpoint", "locals_missing", "locals_stores", "forward_observer"]
	check(MissionRegistry.types() == nine,
		"Captain's first four mission types, then mission variety's convoy ambush, hold the line, crew rescue, sabotage and recon, the client escort, the supply line, the manhunt, the convoy chase, the locals' own three jobs and the forward observer (%s)" % [MissionRegistry.types()])
	var sound := true
	var zones_ok := true
	for z: Dictionary in MissionRegistry.zones():
		var layout := MissionRegistry.zone_def(String(z.zone_id))
		var hot := String(z.get("kind", "")) == "hot"
		zones_ok = zones_ok and not layout.is_empty() and (layout.modules as Array).size() >= 4 			and ["compound", "outpost", "village", "checkpoint"].all(func(t: String) -> bool: return t in z.modules or (hot and t == "compound")) 			and (z.modules as Array).size() == (7 if hot else (5 if "town" in z.modules else 4))
		zones_ok = zones_ok and layout == MissionRegistry.zone_def(String(z.zone_id))
		var size := float(layout.get("size_m", 0))
		# Up to 6.0e6 m² (~2.45 km a side): "Five more contract zones" (2026-10-16) added
		# salt_pan/thornveld at 2304 m with more sites (count 6/7) than the usual 5, deliberately
		# bigger to fit them ("1920-2304 m, 5-7 sites each") - 4.0e6 (2 km a side) was too tight.
		zones_ok = zones_ok and (is_equal_approx(size, ZoneDef.HOT_SIZE_M) if hot else size * size >= 2.0e6 and size * size <= 6.0e6)
	check(zones_ok, "every zone is a generated layout, the same every time: contract zones 2-6 km² with all four module types (a town in some), hot zones 16 km² with the enemy's structure, villages and a town")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sites := {}
	for i in 200:
		var c := ContractGen.generate(rng, {"day": 1, "source": "board", "type": ["raid", "hvt_capture", "hostage_rescue", "intel_grab"][i % 4]})
		var layout := MissionRegistry.zone_def(String(c.zone_id))
		var module: Array = (layout.modules as Array).filter(func(m: Dictionary) -> bool: return m.id == c.module_id)
		sound = sound and module.size() == 1 and module[0].type == c.module and ZoneModules.base(c.module) in MissionRegistry.type_modules(MissionRegistry.type_def(c.type))
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
	var nation := String(MissionRegistry.faction(String(a.target)).get("nation", "insurgent"))  # (wave 6b: targets aren't all the militia)
	if not Names.POOLS.has(nation):
		nation = "insurgent"
	var firsts: Array = (Names.FIRST.get(nation, Names.LOCAL_FIRST.get(nation, Names.LOCAL_FIRST["insurgent"])) as Dictionary)[Names.MALE]
	check(hvt_name.size() == 2 and hvt_name[1] in (Names.POOLS[nation] as Array) and hvt_name[0] in firsts,
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
	# Garrisons come out a few a frame (P0362): until the last is out the site isn't put in yet
	# (a clear-area objective waits) and isn't down.
	var coming := level.garrison_pending(module.module_id)
	check(coming > 0 and not level.garrison_spawned(module.module_id) and not level.site_down(module.module_id),
		"a garrison put in comes out over the next frames (%d coming): not spawned yet, not down" % coming)
	await _garrison_out(module)
	var first := _garrison(module).size()
	var people_before := level.people.people().size()
	var deploy_started := Time.get_ticks_usec()
	check(Contracts.server_start_deployment([], ZONE) == "" and Contracts.deployment().cids.size() == 4, "deployed on all four (a hot zone)")
	var deploy_ms := (Time.get_ticks_usec() - deploy_started) / 1000.0
	CompoundLevel.spawn_ai = false
	# Captain P0362: the zone's civilians all spawning in the deploy frame (with the navigation
	# rebaking under each) was a 3.4 s hitch. They're queued and come out a few a frame, the
	# navigation held till the last is out and then rebaked once per chunk.
	var queued := level.people.spawning()
	var held := level.nav.is_held()
	var spawn_frames := 0
	var worst_ms := 0.0
	var last := Time.get_ticks_usec()
	while level.people.spawning() > 0 and spawn_frames < 600:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, (now - last) / 1000.0)
		last = now
		spawn_frames += 1
	check(queued >= 3 and held and level.people.spawning() == 0 and spawn_frames >= 2 and not level.nav.is_held(),
		"the zone's %d civilians come out over %d frames (deploy call %.0f ms, worst frame after %.0f ms), the navigation held meanwhile and released after"
		% [queued, spawn_frames, deploy_ms, worst_ms])
	check(level.people.people().size() >= people_before + queued, "every queued civilian is out (%d people)" % level.people.people().size())
	# What made each one slow: rasterising a 0.5 cm body for every new outfit. Plain clothes share
	# one raster per body part (only the palette differs), so a new outfit is only meshed.
	var rasters := VoxelArt._plain_rasters.size()
	var outfit_started := Time.get_ticks_usec()
	var torso_a := VoxelArt.mesh("torso", PersonLook._variant("123456", "654321", "c8996f", "6b4a2b"))
	var torso_b := VoxelArt.mesh("torso", PersonLook._variant("abcdef", "654321", "c8996f", "6b4a2b"))
	var outfit_ms := (Time.get_ticks_usec() - outfit_started) / 1000.0
	var colours_a: PackedColorArray = torso_a.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var colours_b: PackedColorArray = torso_b.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(rasters > 0 and VoxelArt._plain_rasters.size() == rasters and torso_a.get_surface_count() == torso_b.get_surface_count()
		and colours_a.size() == colours_b.size() and colours_a != colours_b,
		"two new shirts reuse the torso's plain raster (%d rasters), meshed in their own colours (%.0f ms for both)" % [rasters, outfit_ms])
	await _garrison_out(module)
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
	# LZ-4 (docs/linked_zones.md 3b): the squad leaves the zone and comes back; the HVT isn't in
	# the zone's save, so arriving again puts him back where the contract says, once.
	if hvt:
		hvt.queue_free()
		await _frames(2)
	Contracts.server_arrived(ZONE)
	Contracts.server_arrived(ZONE)
	await _frames(2)
	var again := people.people().filter(func(s: Soldier) -> bool: return String(people.state_of(s).get("hvt_id", "")) == String(hvt_o.params.hvt))
	check(again.size() == 1 and (again[0] as Soldier).global_position.distance_to(_v(hvt_o.pos)) < 1.0,
		"back in the contract's zone, the HVT is there again, once (%d)" % again.size())
	hvt = people.hvt(String(hvt_o.params.hvt))
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


## Audit A3-01: a raid deployed while its target module has never streamed in (no garrison
## yet). Its "leave no fighter standing" bonus must wait for the garrison, not pay out because
## an unvisited rect is empty; arriving puts the garrison in, and clearing it completes it.
func _test_clear_unvisited() -> void:
	print("Clear-area bonus at a site nobody has been to")
	var before := level.ai.get_children()
	var cid := ""
	var module: ZoneModule = null
	for i in 12:  # a raid on a module that hasn't streamed in or had a garrison
		var c := _offer("raid")
		var m := level.get_module(String(c.get("module_id", "")))
		if m and not m.is_streamed() and not level._garrisoned.has(m.module_id):
			cid = _add(c)
			module = m
			break
	if module == null:
		check(false, "a raid on a module nobody has been to")
		return
	var far: ZoneModule = null
	for m in level.modules():
		if far == null or m.distance_to(module.global_position) > far.distance_to(module.global_position):
			far = m
	_place(player, far.global_position)
	await _wait_for(func() -> bool: return far.is_ready(), 20.0)  # streamed in with AI off: nobody there
	check(Contracts.server_accept(cid, ContractGen.default_terms()) == "", "accepted: %s" % Contracts.contract(cid).title)
	var settings: Dictionary = MissionRegistry.data().settings
	var arm_s: Variant = settings.clear_arm_timeout_s
	settings.clear_arm_timeout_s = 1.0
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	check(Contracts.server_start_deployment([], ZONE) == "", "deployed with AI on, %.0f m from the target" % module.distance_to(player.global_position))
	var clear: Array = Contracts.objectives.for_contract(cid).filter(func(o: Dictionary) -> bool: return o.kind == Objectives.CLEAR_AREA)
	if clear.is_empty():
		check(false, "the raid has a clear-area bonus")
	else:
		var oid := String(clear[0].oid)
		await _seconds(2.5)  # past the arm timeout, several polls
		check(not module.is_streamed() and Contracts.objectives.get_objective(oid).state == Objectives.ACTIVE,
			"far from the unvisited target, the clear-area bonus stays open (%s)" % Contracts.objectives.get_objective(oid).state)
		_place(player, module.global_position + Vector3(0, 0, 30))
		await _wait_for(func() -> bool: return module.is_ready(), 20.0)
		CompoundLevel.spawn_ai = false  # the target's garrison only; modules beside it stay empty
		await _garrison_out(module)
		var garrison := _garrison(module)
		await _seconds(1.0)
		check(module.is_ready() and garrison.size() > 0 and Contracts.objectives.get_objective(oid).state == Objectives.ACTIVE,
			"arriving puts its garrison in (%d) and the bonus is still to earn" % garrison.size())
		for s: Soldier in garrison:
			_kill(s)
		await _wait_for(func() -> bool: return Contracts.objectives.get_objective(oid).state == Objectives.DONE, 3.0)
		check(Contracts.objectives.get_objective(oid).state == Objectives.DONE, "every one of them down: the bonus is earned")
	settings.clear_arm_timeout_s = arm_s
	CompoundLevel.spawn_ai = false
	Contracts.server_end_deployment(Contracts.report_from_level(level, [player]))
	Contracts.server_finish_debrief()
	_free_new(before)
	await _frames(3)


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
	var host_was := host.global_position
	host.global_position += Vector3(6, 0, 0)
	await _frames(2)
	node = charges.get_charge_node(id)
	# Along with him as he actually moved: on sloping ground (the rocky_ridge preset) the body
	# settles onto the ground 6 m on, up or down a little (R0042: 0.3 m up).
	check(id != "" and node != null and node.global_position.distance_to(before + (host.global_position - host_was)) < 0.3 and player.inventory.count_of(Charges.ITEM) == 0,
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
	people.server_order(player, hvt, "stop")
	# Calmer (Captain, 2026-10-14): a fight right by him, odds forced up, but one of the squad
	# within NO_BOLT_M: he stays.
	brain.bolt_scale = 100.0
	var fire := func() -> void: brain.hear(hvt.global_position + Vector3(0, 0, 5))
	fire.call()
	await _seconds(HvtAI.BOLT_CHECK_S * 2 + 0.5)
	check(brain.bolts == 0 and Person.is_captive(hvt), "gunfire close but one of the squad within %.0f m: he never bolts (bolts %d)" % [HvtAI.NO_BOLT_M, brain.bolts])
	# Grabbed: held until let go, even with his holder a step beyond NO_BOLT_M.
	_place(player, hvt.global_position + Vector3(HvtAI.NO_BOLT_M + 1.0, 0, 0))
	brain.held_by = player
	fire.call()
	await _seconds(HvtAI.BOLT_CHECK_S * 2 + 0.5)
	check(brain.bolts == 0 and Person.is_captive(hvt) and brain.held(), "grabbed: he stays until let go (bolts %d)" % brain.bolts)
	brain.held_by = null
	# Left alone: he takes it back and runs.
	_place(player, spot + Vector3(40, 0, 0))
	await _wait_for(func() -> bool: return brain.bolts > 0, HvtAI.BOLT_GRACE_S + HvtAI.BOLT_CHECK_S * 2 + 1.0)
	check(brain.bolts == 1 and not Person.is_captive(hvt) and String(Person.state(hvt).get("led_by", "")) == "",
		"left alone, the uncuffed HVT takes his surrender back and bolts (bolts %d, watched %s, uncuffed captive %s, will %.2f, %.1f m, mode %d)" % [brain.bolts, brain.watched(), brain.uncuffed_captive(), brain.bolt_will(), hvt.global_position.distance_to(player.global_position), brain.mode])
	# Chased: one of the squad within CAUGHT_M after BOLT_MIN_RUN_S and he gives up again.
	await _seconds(1.0)
	check(not Person.is_captive(hvt), "he runs a while first")
	var bolted := brain.bolted_at
	var chase := func() -> bool:
		if not Person.is_captive(hvt):
			_place(player, hvt.global_position + Vector3(HvtAI.CAUGHT_M - 2.0, 0, 0))
		return Person.is_captive(hvt)
	await _wait_for(chase, HvtAI.BOLT_MIN_RUN_S + 3.0)
	var chase_s := Soldier._now() - bolted
	check(Person.is_captive(hvt) and brain.bolted_at < 0.0 and chase_s >= HvtAI.BOLT_MIN_RUN_S - 0.5,
		"chased (one of the squad within %.0f m), he gives up again %.1f s after bolting" % [HvtAI.CAUGHT_M, chase_s])
	# At most one bolt a deployment: left alone again with the odds forced up, he stays.
	_place(player, hvt.global_position + Vector3(40, 0, 0))
	fire.call()
	await _seconds(HvtAI.BOLT_GRACE_S + HvtAI.BOLT_CHECK_S * 3 + 0.5)
	check(brain.bolts == 1 and Person.is_captive(hvt), "he bolts at most %d time(s) a deployment (bolts %d)" % [HvtAI.MAX_BOLTS, brain.bolts])
	# Nobody chasing: he still gives up after BOLT_RUN_S on the run.
	brain.bolt("test")
	check(not Person.is_captive(hvt), "(made to bolt again)")
	brain.bolted_at = Soldier._now() - HvtAI.BOLT_RUN_S + 0.5
	await _wait_for(func() -> bool: return Person.is_captive(hvt), 3.0)
	check(Person.is_captive(hvt) and brain.bolted_at < 0.0, "unchased, he gives up after %.0f s on the run" % HvtAI.BOLT_RUN_S)
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

func _offer(type: String, avoid: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + _made
	_made += 1
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type, "zone_id": ZONE, "avoid_modules": avoid})
	c.understated = false
	c.true_rating = c.rated
	c.enemy_count = c.enemy_est
	return c


func _add(c: Dictionary) -> String:
	return Contracts.server_add_offer(c)


## Waits for module `module`'s garrison to be all out (ZoneLevel.garrison_pending).
func _garrison_out(module: ZoneModule) -> void:
	await _wait_for(func() -> bool: return level.garrison_pending(module.module_id) == 0, 10.0)


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
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return ZoneModules.base(m.type) == "outpost")[0]
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
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return ZoneModules.base(m.type) == "outpost")[0]
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


## End to end, EnemyCommand running on its own clock: a contact report in an engaged zone at
## tier 2 launches the QRF; the commander approves it once (one operation for the whole launch,
## however many waves the budget lets go), and the reserves pay exactly the men who spawned.
func _test_command_qrf() -> void:
	print("Enemy command: a QRF approved end to end")
	var er := EnemyResponse.of(level)
	var alert := Alert.of(level)
	var pressure := Pressure.of(level)
	var command := EnemyCommand.of(level)
	check(command != null and command.is_processing(), "a hot zone has an enemy command, making its own decisions")
	if er == null or alert == null or pressure == null or command == null or er.reinforcements == null:
		return
	_clear_waves()
	await _frames(2)
	_calm()
	command.set_process(true)
	command._tick = 0.0  # its next decision now, on its own clock
	await _frames(2)
	check(command.can_decide() and not command.consolidated and command._last_tick != INF, "the commander has decided at least once (%s)" % command.commander_state)
	pressure.points = float(Pressure.TIERS[1])  # tier 2: a second wave if the budget has room
	alert.zone_state = Alert.State.ALERTED  # on standby: the QRF goes at once
	er._zone_was = Alert.State.ALERTED
	er._turnout = false
	er._qrf_due = INF
	er._last_qrf = -INF
	var lk := level.ground_point(player.global_position + Vector3(0, 0, -20))
	var n := er.qrf_launches.size()
	var before := command.reserves
	alert._receive({"kind": &"contact", "pos": lk, "area": alert.area_of(lk), "by": ""})
	var spent := before - command.reserves
	var sent := er.qrf_launches.slice(n)
	var spawned := 0
	for l: Dictionary in sent:
		spawned += (l.soldiers as Array).size()
	var hunts := command.operations.filter(func(o: Dictionary) -> bool: return o.kind == "hunt:qrf")
	check(not sent.is_empty() and spawned > 0 and hunts.size() == 1 and hunts[0].state == "approved",
		"engaged: the commander approves the QRF, one operation for the launch (%d waves from %s, %d men; %s)"
			% [sent.size(), sent.map(func(l: Dictionary) -> String: return l.from), spawned, hunts.map(func(o: Dictionary) -> String: return "%s: %s" % [o.state, o.why])])
	check(is_equal_approx(spent, spawned), "the reserves pay exactly the men who spawned (%.0f spent, %d spawned)" % [spent, spawned])
	command._tick = 0.0
	await _frames(2)
	hunts = command.operations.filter(func(o: Dictionary) -> bool: return o.kind == "hunt:qrf")
	check(hunts.size() == 1, "and its next decision doesn't count the launch twice (%d QRF operations)" % hunts.size())
	_clear_waves()
	_calm()
	er._last_qrf = -INF
	er._zone_was = Alert.State.NORMAL
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
	# Escalation ramp (Captain, 2026-10-16: "a steady patrol or two that escalates"): fresh, a patrol
	# or two; then the rest of this test plays a zone the squad has been in a long while.
	check(er.spawn_budget() == EnemyResponse.RAMP_START and er.alive_total() <= EnemyResponse.RAMP_START,
		"just in: the zone's answer is a patrol or two (%d out, budget %d)" % [er.alive_total(), er.spawn_budget()])
	var fresh_at := er._started_at
	er._started_at = fresh_at - EnemyResponse.ESCALATE_S * 0.5
	var midway := er.spawn_budget()
	er._started_at = fresh_at - EnemyResponse.ESCALATE_S
	check(midway > EnemyResponse.RAMP_START and midway < EnemyResponse.SPAWN_BUDGET.back(),
		"halfway through the ramp the budget is partway up (%d)" % midway)
	for record: Dictionary in er.patrols:
		if record.pending:
			er._try_patrol(record)  # the rest set out now the budget allows
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
	# Dynamic simulation (Captain, 2026-10-18): far from every player an AI sleeps, near it wakes.
	if not looker.is_empty():
		var walker: Soldier = er._living(looker.soldiers)[0]
		var at := walker.global_position
		var far: Array[Vector3] = [at + Vector3(DynamicSim.SLEEP_M + 400.0, 0, 0)]
		var near: Array[Vector3] = [at + Vector3(DynamicSim.WAKE_M - 100.0, 0, 0)]
		var between: Array[Vector3] = [at + Vector3((DynamicSim.SLEEP_M + DynamicSim.WAKE_M) * 0.5, 0, 0)]
		check(DynamicSim.of(level) != null and DynamicSim.should_sleep(walker, far, false) and not DynamicSim.should_sleep(walker, near, true)
			and DynamicSim.should_sleep(walker, between, true) and not DynamicSim.should_sleep(walker, between, false),
			"dynamic sim: a patrol far from every player sleeps, wakes as one comes near (between the two it stays as it was)")
		# G-26: half the patrols lie in wait when they suspect someone; the same for every man of one.
		var pai := SquadAI.of(walker)
		var same := (er._living(looker.soldiers) as Array).all(func(m: Soldier) -> bool: return SquadAI.of(m) == null or SquadAI.of(m).ambusher() == pai.ambusher())
		check(same and pai.post == null, "a patrol ambushes or goes to look as one (this one: %s)" % ("lies in wait" if pai.ambusher() else "goes to look"))
		# Going to sleep he settles first (Captain, 2026-10-19: frozen walking poses in MP): brain
		# off, standing still, so the model eases out of its stride before the body freezes.
		var wb := SquadAI.of(walker)
		walker.move_input = Vector2(0, -1)
		DynamicSim._settle(walker)
		check(walker.has_meta(DynamicSim.SETTLE_META) and wb.process_mode == Node.PROCESS_MODE_DISABLED and walker.move_input == Vector2.ZERO
			and walker.velocity == Vector3.ZERO, "settling to sleep: brain off, no input, no speed")
		DynamicSim._wake_brain(walker)
		check(not walker.has_meta(DynamicSim.SETTLE_META) and wb.process_mode == Node.PROCESS_MODE_INHERIT, "and woken, his brain is back on")
		check(not walker._smooths(), "the host never smooths its own AI (clients do: Soldier._smooths)")
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
		# Captain, 2026-10-18 ("swarmy"): one contact, one look; more patrols rally, then go in together.
		var free := er.patrols.filter(func(r: Dictionary) -> bool: return not r.pending and not r.lost and not er._living(r.soldiers).is_empty())
		if free.size() >= 2:
			for r: Dictionary in er.patrols:
				r.looking_until = -INF
				r.erase("look_rally")
			er.looks.clear()
			var was_state := alert.zone_state
			var spot2 := (er._living(free[0].soldiers)[0] as Soldier).global_position + Vector3(0, 0, 300)
			for i in 6:
				alert._receive({"kind": &"shot", "pos": spot2 + Vector3(i * 3.0, 0, 0), "area": alert.area_of(spot2), "by": ""})
			var on_it := er.patrols.filter(func(r: Dictionary) -> bool: return float(r.looking_until) > er.now())
			check(on_it.size() == 1 and er.looks.size() == 1, "a burst of shots in one spot sends one patrol, not one per shot (%d)" % on_it.size())
			alert.zone_state = Alert.State.ALERTED
			if not er.looks.is_empty():
				er.looks[0].added_at = er.now() - EnemyResponse.LOOK_ESCALATE_S - 1.0
			alert._receive({"kind": &"shot", "pos": spot2, "area": alert.area_of(spot2), "by": ""})
			on_it = er.patrols.filter(func(r: Dictionary) -> bool: return float(r.looking_until) > er.now())
			var rallying := on_it.filter(func(r: Dictionary) -> bool: return r.has("look_rally"))
			check(on_it.size() == 2 and not rallying.is_empty() and rallying.all(func(r: Dictionary) -> bool:
					return (r.squad as Squad).patrol.size() == 1 and absf(Vector2(r.look_rally.x - spot2.x, r.look_rally.z - spot2.z).length() - EnemyResponse.LOOK_RALLY_M) < 3.0),
				"alerted, a minute on: a second patrol joins, and they rally %d m short first" % int(EnemyResponse.LOOK_RALLY_M))
			for r: Dictionary in rallying:
				r.look_rally = (er._living(r.soldiers)[0] as Soldier).global_position  # say they're there
			er._tick_looks()
			check(on_it.all(func(r: Dictionary) -> bool: return not r.has("look_rally") and (r.squad as Squad).patrol.size() == 1 + EnemyResponse.LOOK_POINTS),
				"all at their rally points: they go in together")
			alert.zone_state = was_state
			for r: Dictionary in er.patrols:
				r.looking_until = -INF
				r.erase("look_rally")
				if not r.pending and is_instance_valid(r.squad):
					er._set_route(r.squad, er._living(r.soldiers), r.walk)
			er.looks.clear()
		# Trackers (Captain, 2026-10-18; inspired by S.O.G. Prairie Fire's): a patrol out on a look
		# that comes across the squad's trail signals, follows it mark by mark, and loses it on a road.
		var trail := SquadTrail.of(level)
		check(trail != null, "the zone keeps the squad's trail")
		if trail and not looker.is_empty() and not er._living(looker.soldiers).is_empty():
			var lead: Soldier = er._living(looker.soldiers)[0]
			var start := lead.global_position
			trail.set_process(false)  # (the squad's own live marks stay out of this one)
			trail.marks.clear()
			for i in 4:
				trail.marks.append({"pos": start + Vector3(5.0 + 20.0 * i, 0, 0), "t": Soldier._now() - 60.0 + i, "broken": false})
			trail.marks.append({"pos": start + Vector3(85.0, 0, 0), "t": Soldier._now() - 55.0, "broken": true})  # a road
			looker.looking_until = er.now() + 120.0
			var signals := alert.reports.size()
			check(er._track(looker, er._living(looker.soldiers)) and looker.has("trail_mark")
				and alert.reports.size() > signals and alert.reports.back().kind == &"signal",
				"a patrol out looking picks up the trail beside it and fires signal shots (a report on the net)")
			for step in 4:
				if looker.get("trail_mark") == trail.marks[3]:
					break
				lead.global_position = looker.trail_mark.pos
				looker.track_next = 0.0
				er._track(looker, er._living(looker.soldiers))
			check(looker.get("trail_mark") == trail.marks[3], "and follows it, mark by mark")
			lead.global_position = looker.trail_mark.pos
			looker.track_next = 0.0
			check(not er._track(looker, er._living(looker.soldiers)) and not looker.has("trail_mark"), "where it crosses a road the prints stop: the trail is lost")
			trail.marks.clear()
			trail.set_process(true)
			looker.looking_until = -INF
			er._set_route(looker.squad, er._living(looker.soldiers), looker.walk)
	# Suicide bombers (wave 6f): no rifle, a heavy vest, straight at the squad; at TRIGGER_M he goes off.
	var bombers := Bombers.of(level)
	var unhurt := player.vitals.server_snapshot()  # (the bomber below goes off 5 m from him)
	check(bombers != null, "the zone can send suicide bombers")
	if bombers:
		var far := bombers.server_send(level.ground_point(player.global_position + Vector3(40, 0, 0)))
		check(far != null and far.inventory.slots.get(&"primary", &"") == &"" and far.inventory.slots.get(&"vest", &"") == &"plate_carrier_heavy",
			"a bomber: no rifle, a bulky heavy vest (the tells)")
		bombers.server_tick()
		var squad_route: Array = (bombers.out[0].squad as Squad).patrol if not bombers.out.is_empty() else []
		check(not squad_route.is_empty() and Vector2(squad_route[0].x - player.global_position.x, squad_route[0].z - player.global_position.z).length() < 1.0,
			"he walks straight at the nearest of the squad")
		var gone := bombers.detonated
		far.global_position = player.global_position + Vector3(5, 0, 0)
		bombers.server_tick()
		check(bombers.detonated == gone + 1 and bombers.out.is_empty() and not far.vitals.is_up(), "within %d m he goes off" % int(Bombers.TRIGGER_M))
		var shot := bombers.server_send(level.ground_point(player.global_position + Vector3(40, 0, 0)))
		shot.vitals.server_damage(1000.0)
		shot.global_position = player.global_position + Vector3(5, 0, 0)
		bombers.server_tick()
		check(bombers.detonated == gone + 1 and bombers.out.is_empty(), "shot down first, nothing goes off")
		# VBIEDs: a technical with one driver drives at the squad and goes off close in.
		var truck := bombers.server_send_vbied(level.ground_point(player.global_position + Vector3(80, 0, 0)))
		check(truck != null and bombers.vbieds.size() == 1 and truck.model == Bombers.VBIED_MODEL, "a VBIED: a technical with a driver sets out")
		if truck and not bombers.vbieds.is_empty():
			player.vitals.server_restore(unhurt)  # (up again: a VBIED only drives at the squad that's up)
			await _frames(2)
			var off := bombers.detonated
			truck.global_position = player.global_position + Vector3(9, 0.3, 0)
			bombers.server_tick()
			check(bombers.detonated == off + 1 and bombers.vbieds.is_empty(), "within %d m it goes off" % int(Bombers.VBIED_TRIGGER_M))
		player.vitals.server_reset_health()
	# The QRF.
	# Patrol behavior was checked above. Release those slots so this phase exercises
	# an authorized launch, rather than the commander's correct refusal at a full budget.
	for patrol: Dictionary in er.patrols:
		for s: Soldier in er._living(patrol.soldiers):
			s.queue_free()
	er.patrols.clear()
	await _frames(2)
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
	var fresh := not level._garrisoned.has(first.module_id)
	level._spawn_garrison(first)
	await get_tree().process_frame  # the first of them out, the rest still coming
	var early := _garrison(first)
	for s in early:
		_kill(s)
	var still := level.garrison_pending(first.module_id)
	if fresh:
		check(still > 0 and not level.site_down(first.module_id) and not level.garrison_spawned(first.module_id),
			"the ones out killed while %d are still coming: the site isn't down" % still)
	await _garrison_out(first)
	var g := _garrison(first)
	for s in g:
		_kill(s)
	check(not g.is_empty() and level.site_down(first.module_id) and early.size() + g.size() >= level.garrison_size(first.module_id),
		"the nearest QRF base's garrison killed: the site is down (%d + %d of %d)" % [early.size(), g.size(), level.garrison_size(first.module_id)])
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
		await _garrison_out(m)
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
	# Heading for the last known position, or (with an earlier QRF wave still out on the same
	# spot) rallying with it to go in together (_join_push / _rally_push): its route is then the
	# rally point until the push goes.
	var heading := hsquad != null and (hsquad.patrol.any(func(p: Vector3) -> bool: return Vector2(p.x - lk.x, p.z - lk.z).length() < 2.0)
		or (team.has("rally") and hsquad.patrol.size() == 1))
	check(heading and hunters.all(func(s: Soldier) -> bool: return s.inventory.count_of(EnemyResponse.SMOKE) > 0),
		"the hunters head for the last known position (or rally with the push on it), carrying smoke (%s)" % ("rallying" if team.has("rally") else "%d route points" % (hsquad.patrol.size() if hsquad else -1)))
	# Captain, 2026-10-18 ("add the changes to the hotzone ai"): the QRF and the hunters on one
	# contact are one push: they wait at their rally points and go in together.
	var push: Dictionary = {}
	for pu: Dictionary in er.pushes:
		if (pu.groups as Array).any(func(g: Dictionary) -> bool: return g.ref == team):
			push = pu
	if not push.is_empty() and (push.groups as Array).size() >= 2:
		var rallying := (push.groups as Array).filter(func(g: Dictionary) -> bool: return (g.ref as Dictionary).has("rally"))
		check(not rallying.is_empty() and float(push.go_at) < INF, "the QRF and the hunters on one contact are one push: %d of %d groups wait at rally points" % [rallying.size(), (push.groups as Array).size()])
		push.go_at = er.now() - 1.0
		er._tick_pushes()
		check((push.groups as Array).all(func(g: Dictionary) -> bool: return not (g.ref as Dictionary).has("rally")), "then go in together")
	else:
		check(not push.is_empty(), "the hunters join a push on the contact (%d groups)" % ((push.get("groups", []) as Array).size()))
	# One shared budget (Captain, 2026-10-16: "too many ai in hot zones spawning and coming for the player").
	check(er.alive_total() <= er.spawn_budget(),
		"everything spawned (patrols, hunters, HQ pairs, QRF waves) within the shared budget (%d of %d)" % [er.alive_total(), er.spawn_budget()])
	var launched := er.qrf_launches.size()
	er._last_qrf = er.now()
	alert.zone_state = Alert.State.ENGAGED
	er.server_alert_extraction(lk)
	check(er.qrf_launches.size() == launched, "extraction right after a QRF: no second QRF inside QRF_RELAUNCH_S")
	var old: Dictionary = {}
	for w: Dictionary in er.reinforcements.waves:
		if is_instance_valid(w.squad) and not (w.soldiers as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Soldier).vitals.is_dead()).is_empty():
			old = w
			break
	if not old.is_empty():
		old.sent_at = er.now() - EnemyResponse.WAVE_HUNT_S - 1.0
		var kept: Array[Vector3] = (old.squad as Squad).patrol.duplicate()
		er.reinforcements._retarget_waves()
		check((old.squad as Squad).patrol == kept, "a wave out longer than WAVE_HUNT_S stops being pointed at the last known position")
	await _end_response(er, before)


func _end_response(er: EnemyResponse, before: Array) -> void:
	_free_new(before)
	er.patrols.clear()
	er.looks.clear()
	er.pushes.clear()
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
	var site: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return ZoneModules.base(m.type) == "outpost")[0]
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
	var cash := Economy.cash()
	check(Contracts.radio_contract_problem() == "" and Contracts.server_radio_contract() != "" and (Contracts.deployment().cids as Array).size() == cids + 1,
		"with the field radio along, a radio contract comes in and joins the deployment")
	var radioed := Contracts.contract(String((Contracts.deployment().cids as Array).back()))
	check(int(radioed.deal.advance) == 0 and int(radioed.deal.completion) == int(radioed.deal.pay_total) and Economy.cash() == cash,
		"it pays nothing up front, all on completion (economy overhaul: radioing for contract after contract kept 30%% each)")
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


## Wave 6, factions fight each other in the field (FactionSkirmish): a team of a faction at war
## with the zone's holder hits one of its sites away from the squad, under the rival tag.
func _test_faction_skirmish() -> void:
	print("Faction skirmish")
	var sk := FactionSkirmish.of(level)
	check(sk != null, "a zone has the skirmishes")
	if sk == null:
		return
	var holder := FactionSkirmish.holder_of(level)
	var rivals: Array = MissionRegistry.enemies_of(holder)
	check(not rivals.is_empty(), "the holder (%s) has enemies of its own (%s)" % [holder, rivals])
	if rivals.is_empty():
		return
	var why := sk.server_start(String(rivals[0]))
	await _frames(3)
	var men: Array = sk.team.filter(func(s: Variant) -> bool: return is_instance_valid(s))
	var target_xz := Vector2(float(sk.last.get("at", [0, 0])[0]), float(sk.last.get("at", [0, 0])[1]))
	var side := FactionSkirmish.side_of(String(rivals[0]))
	check(why == "" and men.size() == FactionSkirmish.TEAM and men.all(func(s: Soldier) -> bool: return s.faction == side and s.faction != &"hostile"),
		"%s come in, %d of them, as %s (by the company's standing with them; %s)" % [rivals[0], men.size(), side, why])
	check(target_xz.distance_to(Vector2(player.global_position.x, player.global_position.z)) >= FactionSkirmish.AWAY_M,
		"at a site of the holder's away from the squad (%s, %.0f m off)" % [sk.last.get("site", "?"), target_xz.distance_to(Vector2(player.global_position.x, player.global_position.z))])
	for s: Soldier in men:
		s.queue_free()
	sk.team.clear()
	await _frames(2)


## Captain (2026-10-15: "flesh out HZs too, remember multiple missions per and our design"):
## several of the faction's contracts live at once, follow-ups over the radio reacting to what
## the squad did, the alert easing and the checkpoints with it, pressure rising with time, and
## extraction lapsing what's left (hazard pay on what's done).
func _test_hot_zone_ops() -> void:
	print("Hot zone: in on one contract, radio follow-ups, alert, staying")
	var ops := HotZoneOps.of(level)
	var alert := Alert.of(level)
	var pressure := Pressure.of(level)
	var er := EnemyResponse.of(level)
	check(ops != null, "a hot zone runs its ops")
	if ops == null or alert == null or pressure == null or er == null:
		return
	HotZoneOps.enabled = true
	_calm()
	# Not at the zone's QRF base: the follow-up below needs one no live contract holds.
	var qrf_ids: Array = level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "qrf_base").map(func(m: ZoneModule) -> String: return m.module_id)
	var cid := _add(_offer("raid", qrf_ids))
	Contracts.server_accept(cid, ContractGen.default_terms())
	check(Contracts.server_start_deployment([], ZONE) == "", "deployed to the hot zone on one contract from the board")
	await _frames(5)
	var cids: Array = Contracts.deployment().cids
	var sites := {}
	for c: String in cids:
		sites[String(Contracts.contract(c).module_id)] = true
	var faction := String(MissionRegistry.zone(ZONE).faction)
	check(cids == [cid] and Contracts.contract(cid).employer == faction,
		"the squad goes in on the one contract it took, no top-up on arrival (more come in over the radio)")
	var had := player.inventory.count_of(&"radio")
	if had == 0:
		player.inventory.take(&"radio")
	ops.server_tick()  # sites taken out by the tests before: not ours
	ops.queue.clear()
	# A QRF base taken out: "you hit their QRF, now hit the HQ".
	var base: ZoneModule = null
	for m: ZoneModule in level.modules():
		if m.type == "qrf_base" and not sites.has(m.module_id):
			base = m  # one the tests before took out is taken out again here
	if base:
		ops._seen.erase(base.module_id)
	if base == null:
		check(false, "a QRF base to take out (QRF bases %s, held by live contracts %s)" % [level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "qrf_base").map(func(m: ZoneModule) -> String: return m.module_id), sites.keys()])
	else:
		for s: Soldier in _garrison(base):
			_kill(s)
		level._garrisoned[base.module_id] = maxi(1, int(level._garrisoned.get(base.module_id, 0)))
		ops.server_tick()
		check(level.site_down(base.module_id) and ops.queue.size() == 1 and ops.queue[0].trigger == "qrf_base" and ops.follow_ups.is_empty(),
			"the QRF base taken out: a follow-up is on its way over the radio, not at once")
		alert.advance(HotZoneOps.FOLLOW_UP_DELAY_S + 1.0)
		ops.server_tick()
		var f: Dictionary = ops.follow_ups.back() if not ops.follow_ups.is_empty() else {}
		var at := level.get_module(String(f.get("site", "")))
		check(not f.is_empty() and f.trigger == "qrf_base" and String(f.cid) in Contracts.deployment().cids and at != null
			and at.type in ["hq", "outpost"] and String(Contracts.contract(String(f.cid)).module_id) == at.module_id,
			"%.0f s later the employer radios a new contract at the %s (%s)" % [HotZoneOps.FOLLOW_UP_DELAY_S, at.type if at else "?",
				Contracts.contract(String(f.get("cid", ""))).get("title", "none")])
		check(not er._living_sites("qrf_base", base.global_position).has(base), "and the base taken out sends no more QRF waves")
	# A contract done sets one off too; without a field radio it waits.
	var done_cid := ""
	for c: String in Contracts.deployment().cids:
		if not ops._seen.has(String(Contracts.contract(c).module_id)) and not Contracts.objectives.contract_done(c):
			done_cid = c
			break
	check(done_cid != "", "a live contract to finish")
	if done_cid != "":
		for o: Dictionary in Contracts.objectives.for_contract(done_cid):
			if not o.optional:
				Contracts.objectives.server_set_state(String(o.oid), Objectives.DONE)
		_drop_all(player, &"radio")
		var n := ops.follow_ups.size()
		ops.server_tick()
		alert.advance(HotZoneOps.FOLLOW_UP_DELAY_S + HotZoneOps.FOLLOW_UP_GAP_S + 1.0)
		ops.server_tick()
		check(ops.follow_ups.size() == n and ops.queue.size() == 1 and ops.queue[0].trigger == "contract",
			"a contract done: its follow-up waits while the squad has no field radio")
		player.inventory.take(&"radio")
		ops.server_tick()
		check(ops.follow_ups.size() == n + 1 and ops.follow_ups.back().trigger == "contract", "the field radio back: it comes in")
	# The comms site's mast down: reports slow, and a follow-up.
	var a := level.spawn_soldier({"name": "OpsGuard", "faction": "hostile", "variant": "urban",
		"pos": level.ground_point(player.global_position + Vector3(60, 0, 0)), "loadout": [], "combat": 0.5, "discipline": 1.0, "guard": true})
	alert._pending.clear()
	alert._perceive(a, &"shot", a.global_position)
	var quick := float(alert._pending.back().due) - alert.now() if not alert._pending.is_empty() else 0.0
	alert._pending.clear()
	alert._last_report.clear()
	alert.comms_down = true
	alert._perceive(a, &"shot", a.global_position)
	var slow := float(alert._pending.back().due) - alert.now() if not alert._pending.is_empty() else 0.0
	check(quick > 0.0 and absf(slow - quick * Alert.COMMS_DOWN_MULT) < 0.5,  # read a moment apart on a live clock: not exact
		"the comms site down: reports reach the net %.0fx slower (%.0f s, not %.0f)" % [Alert.COMMS_DOWN_MULT, slow, quick])
	alert._pending.clear()
	a.queue_free()
	var n2 := ops.follow_ups.size()
	ops.server_tick()
	alert.advance(HotZoneOps.FOLLOW_UP_DELAY_S + HotZoneOps.FOLLOW_UP_GAP_S + 1.0)
	ops.server_tick()
	check(ops.follow_ups.size() == n2 + 1 and ops.follow_ups.back().trigger == "comms", "and the employer radios what to hit while their net is down")
	# The alert eases when the squad goes quiet, and the checkpoints with it.
	_calm()
	var outpost: ZoneModule = level.modules().filter(func(m: ZoneModule) -> bool: return ZoneModules.base(m.type) == "outpost")[0]
	alert._receive({"kind": &"body", "pos": outpost.global_position, "area": outpost.module_id, "by": ""})
	er.server_tick()
	check(alert.zone_state == Alert.State.ALERTED and er.checkpoints_closed, "a body found: the zone alerted, checkpoints closed")
	alert.advance(Alert.ALERTED_COOL_S + 10.0)
	pressure.points = 0.0
	pressure._tier = 0
	er.server_tick()
	check(alert.zone_state == Alert.State.SUSPICIOUS and not er.checkpoints_closed, "quiet for hours: the zone eases to suspicious and the roads open again")
	# Staying: pressure rises with time even when quiet, and pays.
	_calm()
	alert.advance(Pressure.STAY_FLOOR_S * 4.0 + 1.0)
	pressure.server_tick()
	await _frames(1)
	check(pressure.points >= Pressure.STAY_FLOOR * 4.0 - 0.01 and pressure.tier() >= 1,
		"two quiet hours in the zone: the enemy still commits more (%.1f, tier %d)" % [pressure.points, pressure.tier()])
	check(int(Contracts.deployment().get("hazard_tier", 0)) >= 1, "the deployment notes the tier reached, for hazard pay")
	# Extraction ends it: what's done pays (with hazard pay), the rest lapses.
	var d := Contracts.server_end_deployment({})
	var lines: Array = d.get("contracts", [])
	var done_lines := lines.filter(func(l: Dictionary) -> bool: return l.outcome == "completed")
	var lapsed := lines.filter(func(l: Dictionary) -> bool: return l.outcome == "lapsed")
	check(not Contracts.is_deployed() and not done_lines.is_empty() and lapsed.size() == lines.size() - done_lines.size()
		and done_lines.all(func(l: Dictionary) -> bool: return (l.bonuses as Array).any(func(b: Dictionary) -> bool: return String(b.text).begins_with("Hazard pay"))),
		"extracted: %d done with hazard pay, %d unfinished lapse" % [done_lines.size(), lapsed.size()])
	Contracts.server_finish_debrief()
	_drop_all(player, &"radio")
	if had > 0:
		player.inventory.take(&"radio", had)
	HotZoneOps.enabled = false
	_calm()
	await _frames(2)


## Captain (2026-10-12): the HQ's corner towers have their parapets on their outer sides, and
## garrison posts face out of their site: the gate guards stand behind the sandbags, facing the gate.
## Wave 6b's open item: the zone knows whose men it holds as it loads (ZoneLevel._zone_enemy),
## so a garrison spawned before any contract goes live already wears that faction's kit: a
## deployment contract's kitted target first, else a hot zone's holder (only read, never seeded).
func _test_zone_enemy() -> void:
	print("Whose kit the zone's garrisons wear before a contract goes live")
	var zl := level as ZoneLevel
	if zl == null:
		check(false, "a zone level")
		return
	var zid := GameState.zone_id  # the zone's save id (a test id here, never a real save)
	var cs := Campaign.section(Contracts.SECTION)
	var held_before: Array = cs.get("held", [])
	var dep_before: Dictionary = cs.get("deployment", {})
	var ws := Campaign.section(WorldSites.SECTION)
	var site_before: Variant = ws.get(zid)
	cs.held = []
	cs.deployment = {"cids": []}
	ws[zid] = {"holder": "black_ridge", "grip": 0.8, "flashpoint": false}
	check(zl._zone_enemy() == "black_ridge", "held by Black Ridge: the militia")
	# Terror groups (2026-10-20): a zone held by one of them is theirs; a front splits its sites.
	ws[zid] = {"holder": "valley_shura", "grip": 0.8, "flashpoint": false}
	check(zl._zone_enemy() == "valley_shura" and Kits.sends_bombers("valley_shura"), "held by the Valley Shura: its men, and its bombers")
	ws[zid] = {"holder": "valley_shura", "grip": 0.5, "flashpoint": false, "front": {"by": "kestrel", "since": 1, "progress": 0.5}}
	zl._attacker_sites = {}
	var by_site := {}
	for mod: ZoneModule in zl.modules():
		by_site[zl.module_faction(mod)] = int(by_site.get(zl.module_faction(mod), 0)) + 1
	check(zl._zone_attacker() == "kestrel" and int(by_site.get("kestrel", 0)) >= 1 and int(by_site.get(String(zl._enemy_response.enemy_faction), 0)) >= 1,
		"a front here: the attacker's men hold some of the sites already (%s)" % by_site)
	zl._attacker_sites = {}
	var flags := zl.get_node_or_null(^"FactionFlags")
	check(flags != null and flags.get_child_count() > 0, "the holder's flags fly over its sites (%d)" % (flags.get_child_count() if flags else 0))
	ws[zid] = {"holder": "eastern_concord", "grip": 0.8, "flashpoint": false}
	check(zl._zone_enemy() == "eastern_concord", "held by the Eastern Concord Forces: their kit from the first spawn")
	cs.held = [{"cid": "TZE1", "zone_id": zid, "target": "vantage_group"}]
	cs.deployment = {"cids": ["TZE1"]}
	check(zl._zone_enemy() == "vantage_group", "a deployment contract against Vantage wins over the holder")
	cs.held = held_before
	cs.deployment = dep_before
	if site_before == null:
		ws.erase(zid)
	else:
		ws[zid] = site_before


## Wave 6: a rival PMC team races the squad to a contract's site. Comes in Vantage's black kit,
## takes the site if it holds it a minute uncontested (the contract fails), and is beaten once
## all its men are down. Which contracts draw one is fixed by the contract id.
func _test_rival_team() -> void:
	print("Rival contractors: a Vantage team racing for the site")
	var rival := RivalTeam.of(level)
	check(rival != null, "every zone has one")
	if rival == null:
		return
	var some := range(200).filter(func(i: int) -> bool: return RivalTeam.races_on({"cid": "C%d" % i, "type": "intel_grab", "target": "black_ridge"}))
	check(some.size() > 20 and some.size() < 100 and not RivalTeam.races_on({"cid": "C1", "type": "intel_grab", "target": RivalTeam.RIVAL})
		and not RivalTeam.races_on({"cid": "C1", "type": "defend_hold", "target": "black_ridge"}) and RivalTeam.races_on({"cid": "C%d" % some[0], "type": "intel_grab", "target": "black_ridge"}),
		"about %d%% of race-type contracts draw one (%d of 200), always the same ones; never against Vantage itself or on a hold job" % [RivalTeam.CHANCE_PCT, some.size()])
	# The site furthest from the players, so nobody contests it.
	var far: ZoneModule = null
	for m: ZoneModule in level.modules():
		if far == null or _flat_m(m.global_position, player.global_position) > _flat_m(far.global_position, player.global_position):
			far = m
	var r := {"cid": "TRIVAL1", "title": "the test job", "site": far.global_position, "go_at": INF, "squad": null, "soldiers": [], "held": 0.0, "state": "pending"}
	rival.races.append(r)
	check(rival.server_send(r) and (r.soldiers as Array).size() == RivalTeam.SIZE and (r.soldiers[0] as Soldier).inventory.count_of(RivalTeam.LEDGER) == 1
		and (r.soldiers as Array).all(func(s: Soldier) -> bool: return s.model.variant == "black"), "the team comes in: %d men in Vantage black" % (r.soldiers as Array).size())
	check((r.soldiers as Array).all(func(s: Soldier) -> bool: return String(s.get_meta(&"faction_id", "")) == RivalTeam.RIVAL and SquadAI.of(s) != null and SquadAI.of(s)._doctrine_id() == &"pmc"),
		"Vantage's men are Vantage's, whoever holds the zone, and fight by its PMC doctrine (%s)" % [(r.soldiers as Array).map(func(s: Soldier) -> String: return "%s %s" % [s.get_meta(&"faction_id", ""), SquadAI.of(s)._doctrine_id() if SquadAI.of(s) else &""])])
	for s: Soldier in r.soldiers:
		s.global_position = level.ground_point(far.global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	rival.server_step(r, RivalTeam.SECURE_S * 0.5)
	check(r.state == "out" and float(r.held) > 0.0, "on the site, nobody near: they start securing it")
	rival.server_step(r, RivalTeam.SECURE_S)
	check(r.state == "won", "held a minute: Vantage got there first")
	var r2 := {"cid": "TRIVAL2", "title": "another", "site": far.global_position, "go_at": INF, "squad": null, "soldiers": [], "held": 0.0, "state": "pending"}
	rival.races.append(r2)
	rival.server_send(r2)
	for s: Soldier in r2.soldiers:
		s.vitals.server_kill()
	rival.server_step(r2, 1.0)
	check(r2.state == "beaten", "all its men down: beaten, the job goes on")
	for rr: Dictionary in [r, r2]:
		for s: Variant in rr.soldiers:
			if is_instance_valid(s):
				(s as Soldier).queue_free()
	rival.races.erase(r)
	rival.races.erase(r2)
	await _frames(2)


## Wave 6: a contract's "IEDs" threat is real: buried on the roads near its site, spotted by
## someone moving carefully nearby, disarmed by a player crouched beside it, or set off.
func _test_roadside_ieds() -> void:
	print("IEDs on the roads")
	var ieds := RoadsideIeds.of(level)
	check(ieds != null, "every zone has them")
	if ieds == null:
		return
	# The site with the most road near it.
	var site := Vector3.INF
	var best := 0
	for m: ZoneModule in level.modules():
		var n := ieds.road_spots(m.global_position).size()
		if n > best:
			best = n
			site = m.global_position
	var before := ieds.ieds.size()
	var n := ieds.server_plant("TIED1", site) if site.is_finite() else 0
	var mine := ieds.ieds.slice(before)
	check(n >= RoadsideIeds.COUNT.x and n <= RoadsideIeds.COUNT.y and mine.size() == n
		and mine.all(func(e: Dictionary) -> bool: return Charges.of(level).records.has(String(e.charge)) and not Charges.of(level)._due.has(String(e.charge))),
		"%d IEDs buried on the roads near the site (devices placed, no fuse)" % n)
	if mine.size() < 2:
		return
	var back := player.global_position
	var e: Dictionary = mine[0]
	player.global_position = level.ground_point(e.pos + Vector3(7.0, 0, 0))
	player.velocity = Vector3.ZERO
	ieds.server_step(0.2)
	check(e.state == "spotted", "standing still 7 m off, the player spots it")
	player.movement.stance = SoldierMovement.Stance.CROUCH_MID
	player.global_position = level.ground_point(e.pos + Vector3(1.0, 0, 0))
	ieds.server_step(RoadsideIeds.DISARM_S * 0.5)
	check(e.state == "spotted" and float(e.disarm) > 0.0, "crouched beside it: disarming, not setting it off")
	ieds.server_step(RoadsideIeds.DISARM_S)
	check(e.state == "disarmed" and not Charges.of(level).records.has(String(e.charge)), "disarmed: the device is gone")
	player.movement.stance = SoldierMovement.Stance.STAND_HIGH
	player.global_position = back
	var f: Dictionary = mine[1]
	ieds.server_set_off(f, "test")
	check(f.state == "off" and not Charges.of(level).records.has(String(f.charge)), "set off: it goes, the device with it")
	for g: Dictionary in mine.slice(2):
		ieds.server_disarm(g)
	await _frames(2)


## Wave 6: the enemy's recon drones: up from the HQ, over the squad, reporting it to the net;
## two rounds bring one down, a jammer in the squad cuts its link.
func _test_enemy_drones() -> void:
	print("Enemy recon drones and the jammer")
	var drones := EnemyDrones.of(level)
	var alert := Alert.of(level)
	check(drones != null and alert != null, "a hot zone has them")
	if drones == null or alert == null:
		return
	var id := drones.server_launch(player.global_position + Vector3(300, 0, 0))
	check(id > 0 and drones.drones[id].pos.y > player.global_position.y + 30.0, "a drone goes up, high over the ground")
	var reports := alert.reports.size()
	for k in 40:
		drones.server_fly(id, 1.0)
	check(Vector2(drones.drones[id].pos.x - player.global_position.x, drones.drones[id].pos.z - player.global_position.z).length() <= EnemyDrones.SEE_M
		and alert.reports.size() > reports and String(alert.reports[-1].get("by", "")) == "drone",
		"it flies to the squad and reports it to the enemy's net (%d reports)" % (alert.reports.size() - reports))
	var body: Node = drones.drones[id].body
	check(body != null and body.has_meta(&"on_bullet"), "it can be shot (a body rounds hit)")
	for k in EnemyDrones.HITS:
		(body.get_meta(&"on_bullet") as Callable).call(drones.drones[id].pos, player)
	check(String(drones.drones[id].state) == "falling", "%d hits: it comes down" % EnemyDrones.HITS)
	for k in 20:
		drones.server_fly(id, 1.0)
	check(String(drones.drones[id].state) == "gone", "and crashes")
	var id2 := drones.server_launch(player.global_position + Vector3(100, 0, 0))
	check(player.inventory.take(EnemyDrones.JAMMER) == 1, "the player carries a jammer")
	for k in 10:
		drones.server_fly(id2, 1.0)
	check(String(drones.drones[id2].state) in ["falling", "gone"], "a jammer in the squad: its link is cut and it falls")
	player.inventory.remove_one(EnemyDrones.JAMMER)
	drones.drones.erase(id)
	drones.drones.erase(id2)


## Wave 6, keys: the HQ's strongbox stays shut to anyone without its key, and opens (for good)
## for whoever carries it; valuables, contraband and intel inside.
func _test_strongbox() -> void:
	print("Keys: the HQ strongbox")
	var box: WorldCache = null
	for n: Node in level.find_children("*", "WorldCache", true, false):
		if (n as WorldCache).key_id == WorldValuables.STRONGBOX_KEY:
			box = n
			break
	check(box != null and box.display_name() == WorldValuables.STRONGBOX_LABEL, "the HQ has a strongbox")
	if box == null:
		return
	var ids := box.cargo_hold.entries().map(func(e: Dictionary) -> String: return String(e.id))
	# (The loot rotation, 2026-10-20: its valuables are rolled by tier now, not always gold bars.)
	var valuable := ids.any(func(id: String) -> bool: return ItemDB.has_item(StringName(id)) and ItemDB.get_item(StringName(id)).type == "valuable" and not Fixers.is_contraband(StringName(id)))
	check(valuable and ids.any(func(id: String) -> bool: return Fixers.is_contraband(StringName(id))), "valuables and contraband inside (%s)" % [ids])
	player.inventory.remove_one(WorldValuables.STRONGBOX_KEY)
	check(box.is_locked() and box.lock_problem(player).contains("Locked") and box.server_open_for(player) != "" and box.is_locked(), "without the key it stays shut")
	check(player.inventory.take(WorldValuables.STRONGBOX_KEY) == 1 and box.server_open_for(player) == "" and not box.is_locked(), "the officer's key opens it")
	player.inventory.remove_one(WorldValuables.STRONGBOX_KEY)
	check(box.lock_problem(player) == "", "and it stays open")


## Terror groups follow-ups (2026-10-20): a raid on the Kestrel Cartel played here. Its cache is a
## drug lab or a warehouse, a box of its goods stands beside it once the contract is live, and
## every third man of the site's garrison carries some (and fights by the cartel doctrine).
func _test_cartel_site() -> void:
	print("A cartel's site: its drug lab, its stash, its men's pockets")
	var c: Dictionary = {}
	for i in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4400 + i
		var o := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": "raid", "zone_id": ZONE, "target": "kestrel"})
		var mod := level.get_module(String(o.module_id))
		if mod and not level._garrisoned.has(mod.module_id) and not ZoneModules.GARRISON.get(mod.type, []).is_empty() \
				and (o.objectives as Array).any(func(x: Dictionary) -> bool: return String(x.get("site", "")) == "cache"):
			c = o
			break
	if c.is_empty():
		check(false, "a raid on the Kestrel Cartel at a site not garrisoned yet")
		return
	c.understated = false
	c.true_rating = c.rated
	c.enemy_count = c.enemy_est
	var module := level.get_module(String(c.module_id))
	var d := await _deploy_offer(c)
	var cache_o: Dictionary = (d.objectives as Array).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.DESTROY_CACHE)[0]
	var name := String(cache_o.params.get("name", ""))
	check(d.why == "" and name in ["drug lab", "warehouse"] and String(cache_o.text) == "Destroy the %s" % name and String(cache_o.params.get("loot_of", "")) == "kestrel",
		"live: %s at the %s" % [cache_o.text, module.module_id])
	var stash := level.find_child(("contraband_%s" % String(cache_o.oid)).validate_node_name(), true, false) as WorldCache
	var ids: Array = stash.cargo_hold.entries().map(func(e: Dictionary) -> String: return String(e.id)) if stash else []
	var box: Array = cache_o.params.box
	var beside := stash != null and stash.global_position.x > maxf(float(box[0][0]), float(box[1][0])) \
		and absf(stash.global_position.z - (float(box[0][2]) + float(box[1][2])) * 0.5) < 0.1
	check(stash != null and stash.display_name() == "Drug stash" and not ids.is_empty() and ids.any(func(id: String) -> bool: return Fixers.is_contraband(StringName(id))) and beside,
		"a drug stash stands beside it (%s)" % [ids])
	level.people.server_contract_content(d.objectives)
	check(level.find_children(("contraband_%s" % String(cache_o.oid)).validate_node_name(), "WorldCache", true, false).size() == 1, "and only one, whatever puts the contract's content in again")
	CompoundLevel.spawn_ai = true
	level._ai_ready = true
	level._spawn_garrison(module)
	await _garrison_out(module)
	CompoundLevel.spawn_ai = false
	var men := _garrison(module)
	var goods := ["hashish", "captagon", "heroin_bricks", "counterfeit_dollars"]
	var carrying := men.filter(func(s: Soldier) -> bool: return goods.any(func(id: String) -> bool: return s.inventory.count_of(StringName(id)) > 0))
	check(men.size() >= 3 and not carrying.is_empty() and carrying.size() < men.size()
		and men.all(func(s: Soldier) -> bool: return String(s.get_meta(&"faction_id", "")) == "kestrel" and SquadAI.of(s)._doctrine_id() == &"cartel"),
		"the cartel's men hold it, fighting by its doctrine, %d of %d with goods in their pockets" % [carrying.size(), men.size()])
	_end_deployment()
	for s in men:
		s.queue_free()
	level._garrisoned.erase(module.module_id)
	if stash:
		stash.queue_free()
	await _frames(2)


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


## Captain, playtest P0362: a dead player respawned at once at the zone's first insertion point
## with his killer standing on it. He now comes back (CompoundLevel.respawn_point) at the
## briefing's chosen insertion point if no enemy is within RESPAWN_SAFE_M of it or can see it,
## else at another insertion or extraction point, else the FOB, after the wait (Soldier).
func _test_respawn_points() -> void:
	print("Respawn points")
	_free_new([])  # no hostiles about but ours
	await _frames(2)
	var saved_delay := Soldier.respawn_delay_s
	var saved_protect := Soldier.spawn_protect_s
	var ins := level.insertion_points()
	var ext := level.extraction_points()
	var briefing := MapNodes.briefing(level)
	var saved_zone := briefing.zone
	var saved_id := briefing.insertion_id
	briefing.zone = {"insertion_points": [{"id": "a", "pos": [ins[0].x, ins[0].z]}, {"id": "b", "pos": [ins[1].x, ins[1].z]}]}
	briefing.insertion_id = "b"  # the briefing chose the second one
	var cands := level.respawn_candidates()
	check(cands.size() == ins.size() + ext.size() and _flat_m(cands[0], ins[1]) < 1.0,
		"candidates: the briefing's insertion first, then the zone's insertion and extraction points (%d)" % cands.size())
	var p := level.respawn_point(player)
	check(_flat_m(p, ins[1]) < 8.0, "nobody about: the briefing's insertion point (%.0f m off; %s)" % [_flat_m(p, ins[1]), level.last_respawn.get("why", "")])
	var hostile := func(at: Vector3, callsign: String) -> Soldier:
		var s := level.spawn_soldier({"name": callsign, "faction": "hostile", "variant": "woodland", "pos": at,
			"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		s.set_physics_process(false)  # stays put, even in mid-air
		return s
	var camper: Soldier = hostile.call(level.ground_point(ins[1] + Vector3(6, 0, 0)), "RespawnCamper")
	await _frames(2)
	p = level.respawn_point(player)
	var foes := level.respawn_enemies(player)
	check(_flat_m(p, ins[1]) > CompoundLevel.RESPAWN_SAFE_M and level.respawn_clearance(level.last_respawn.point, foes) >= CompoundLevel.RESPAWN_SAFE_M,
		"an enemy on it: another point, none near or in sight (%.0f m away; %s)" % [_flat_m(p, ins[1]), level.last_respawn.get("why", "")])
	# One that can see a point from 200 m (high above the ground, nothing in the way) makes it hot too.
	var next: Vector3 = level.last_respawn.point
	var watcher: Soldier = hostile.call(next + Vector3(200, 60, 0), "RespawnWatcher")
	await _frames(2)
	foes = level.respawn_enemies(player)
	check(level.respawn_clearance(next, foes) < CompoundLevel.RESPAWN_SAFE_M, "an enemy 200 m off who can see a point makes it hot (%.0f)" % level.respawn_clearance(next, foes))
	p = level.respawn_point(player)
	check(_flat_m(p, next) > 8.0 and _flat_m(p, ins[1]) > CompoundLevel.RESPAWN_SAFE_M, "so it goes to another (%s)" % level.last_respawn.get("why", ""))
	# Every insertion and extraction point hot: the FOB, if it's safe; else the least dangerous.
	var campers: Array[Soldier] = [camper, watcher]
	for i in cands.size():
		campers.append(hostile.call(level.ground_point(cands[i] + Vector3(6, 0, 6)), "RespawnCamper%d" % i))
	await _frames(2)
	foes = level.respawn_enemies(player)
	var fob: Variant = level.respawn_fallback()
	p = level.respawn_point(player)
	if fob != null and level.respawn_clearance(fob, foes) >= CompoundLevel.RESPAWN_SAFE_M:
		check(_flat_m(p, fob) < 8.0, "every insertion and extraction point hot: the FOB (%s)" % level.last_respawn.get("why", ""))
	else:  # (ridge_hot: an insertion point lies near the FOB, so its camper makes the FOB hot too)
		check(String(level.last_respawn.get("why", "")).begins_with("every point hot"), "every point hot, the FOB too: the least dangerous (%s)" % level.last_respawn.get("why", ""))
	# The campers that make the FOB hot step back from it, still near (or in sight of) their point:
	# every insertion and extraction point hot, the FOB not: the FOB.
	if fob != null:
		for s in campers:
			var own := s.global_position
			var away := Vector3(own.x - (fob as Vector3).x, 0.0, own.z - (fob as Vector3).z).normalized()
			var just: Array[Soldier] = [s]
			for k in 14:
				if level.respawn_clearance(fob, just) >= CompoundLevel.RESPAWN_SAFE_M:
					break
				s.global_position = level.ground_point(own + away * 10.0 * (k + 1)) + Vector3.UP * 1.0
		foes = level.respawn_enemies(player)
		var all_hot := cands.all(func(c: Vector3) -> bool: return level.respawn_clearance(c, foes) < CompoundLevel.RESPAWN_SAFE_M)
		p = level.respawn_point(player)
		check(all_hot and level.respawn_clearance(fob, foes) >= CompoundLevel.RESPAWN_SAFE_M and _flat_m(p, fob) < 8.0,
			"every insertion and extraction point hot, the FOB not: the FOB (%s)" % level.last_respawn.get("why", ""))
	for s in campers:
		s.queue_free()
	await _frames(2)
	# The whole death: the wait, then the briefing's point (nobody about now), protected.
	Soldier.respawn_delay_s = 1.0
	Soldier.spawn_protect_s = 1.0
	player.global_position = level.ground_point(ins[0] + Vector3(20, 0, 20))
	await _frames(2)
	player.vitals.server_kill()
	await _frames(2)
	check(player.respawn_state == Soldier.RESPAWN_WAITING and _flat_m(player.global_position, ins[1]) > 20.0, "killed: waiting, not moved yet")
	await _wait_for(func() -> bool: return player.respawn_state != Soldier.RESPAWN_WAITING, 3.0)
	check(player.respawn_state == Soldier.RESPAWN_PROTECTED and _flat_m(player.global_position, ins[1]) < 8.0,
		"then back at the briefing's insertion point, protected (%.0f m off)" % _flat_m(player.global_position, ins[1]))
	await _wait_for(func() -> bool: return player.respawn_state == Soldier.RESPAWN_NONE, 3.0)
	Soldier.respawn_delay_s = saved_delay
	Soldier.spawn_protect_s = saved_protect
	briefing.zone = saved_zone
	briefing.insertion_id = saved_id


func _flat_m(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
	var command := EnemyCommand.of(level)
	if command:
		command.operations.clear()
		command.reserves = EnemyCommand.RESERVE_POOL[0]
		command.commander_state = "commanding"
		command.consolidated = false
		command.caution = 0.0
		command.seen_cp = 0.0
		command._contacts.clear()
		command._noise.clear()
		command._last_contact.clear()


## EnemyCommand making its own decisions on its clock (true) or standing down (false).
func _command_on(on: bool) -> void:
	var command := EnemyCommand.of(level)
	if command:
		command.set_process(on)


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


# --- Mission variety: convoy, hold, crew rescue, sabotage, recon ----------------------------------

const NEW_TYPES: Array[String] = ["convoy_ambush", "defend_hold", "crew_rescue", "sabotage", "recon", "psd_escort"]


## Deploys a new contract of `type` in the zone and returns {"cid", "why", "objectives"}.
func _deploy_new(type: String) -> Dictionary:
	var cid := _add(_offer(type))
	Contracts.server_accept(cid, ContractGen.default_terms())
	var why := Contracts.server_start_deployment([cid], ZONE)
	await _frames(3)
	return {"cid": cid, "why": why, "objectives": Contracts.objectives.for_contract(cid)}


func _kind(list: Array, kind: String, optional := false) -> Dictionary:
	for o: Dictionary in list:
		if o.kind == kind and bool(o.optional) == optional:
			return Contracts.objectives.get_objective(String(o.oid))
	return {}


## Ends the deployment as the squad leaving with `player`, finishes the debrief and returns it.
func _end_deployment() -> Dictionary:
	var d := Contracts.server_end_deployment(Contracts.report_from_level(level, [player]))
	Contracts.server_finish_debrief()
	return d


func _bonus_texts(d: Dictionary) -> String:
	var out := PackedStringArray()
	for line: Dictionary in d.contracts:
		for b: Dictionary in line.bonuses:
			out.append(String(b.text))
	return " | ".join(out)


func _clean_scenario(before: Array) -> void:
	_clear_waves()
	_free_new(before)
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer:
		for v in layer.vehicles():
			if v.faction in [&"hostile", &"friendly"]:
				v.queue_free()
	for n in level.people.people():
		if String(n.name).begins_with("Person_crew"):
			n.queue_free()
	await _frames(3)


func _test_scenarios() -> void:
	print("Mission variety")
	var scen := MissionScenario.of(level)
	check(scen != null, "the level has its MissionScenario node")
	_test_scenario_generation()
	if scen == null:
		return
	Contracts.new_full_campaign(88, 900000)
	var r := MapNodes.reinforcements(level)
	r.params.max_alive = 8  # keep the waves small: this is a check, not a siege
	r.params.max_pairs = 1
	var before := level.ai.get_children()
	var zone_half := float(MissionRegistry.zone_def(ZONE).size_m) * 0.5
	_place(player, level.insertion_points()[0])

	# Convoy ambush: sets out after its time, stopped when the cargo trucks are out, crate seized.
	var d := await _deploy_new("convoy_ambush")
	var main := _kind(d.objectives, Objectives.CONVOY)
	check(d.why == "" and not main.is_empty() and String(main.progress).contains("due in"), "a convoy contract deploys: waiting for the convoy (%s)" % main.get("progress", ""))
	var run := scen.run_of(String(main.oid))
	check(String(run.get("phase", "")) == "waiting" and (run.vehicles as Array).is_empty(), "no convoy yet")
	scen.server_advance(float(main.params.depart_s) + 2.0)
	run = scen.run_of(String(main.oid))
	var vehicles: Array = run.vehicles
	var hostile_crews := vehicles.all(func(e: Dictionary) -> bool: return (e.v as Vehicle).faction == &"hostile" and not (e.crew as Array).is_empty())
	check(String(run.phase) == "rolling" and vehicles.size() >= 2 and hostile_crews,
		"it sets out on time: %d hostile vehicles with crews, driving the route" % vehicles.size())
	var cargo: Array = vehicles.filter(func(e: Dictionary) -> bool: return bool(e.cargo))
	check(not cargo.is_empty() and Contracts.objectives.get_objective(main.oid).state == Objectives.ACTIVE,
		"%d cargo truck%s still moving, the objective open" % [cargo.size(), "" if cargo.size() == 1 else "s"])
	# AI virtualization (phase 3): out of everyone's way the rolling convoy is a profile, vehicles and
	# all; the objective stays open, it drives on, and it comes back as it was, crews in their seats.
	var vz := Virtualizer.of(level)
	var ids: Array = vehicles.map(func(e: Dictionary) -> String: return (e.v as Vehicle).vehicle_id)
	var went := vz != null and run.has("group") and vz.server_virtualize(run.group, true)
	await _frames(2)
	scen.server_advance(1.0)
	check(went and vehicles.all(func(e: Dictionary) -> bool: return not is_instance_valid(e.v)) and Contracts.objectives.get_objective(main.oid).state == Objectives.ACTIVE,
		"virtual, the convoy's vehicles leave the world and the objective stays open (not read as stopped)")
	if went:
		var from := Virtualizer.lead(run.group)
		vz.server_advance(20.0)
		check(Virtualizer._flat(from, Virtualizer.lead(run.group)) > 30.0, "it drives on along its route off-screen (%.0f m in 20 s)" % Virtualizer._flat(from, Virtualizer.lead(run.group)))
		vz.server_wake(run.group)
		vz.server_flush()
		await _frames(2)
		var driving := func(e: Dictionary) -> bool:
			var tv := e.v as Vehicle if is_instance_valid(e.v) else null
			return tv != null and ids.has(tv.vehicle_id) and tv.driver() != null and is_instance_valid(tv.ai) and tv.ai.active
		check(vehicles.all(driving), "back in the world: the same vehicles, each with its driver, driving the rest of the route")
	scen.server_neutralize_convoy(String(main.oid))
	scen.server_advance(1.0)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.DONE, "every cargo truck out of action: the convoy is stopped")
	var crate_id := String(main.params.cargo_ids[0])
	check(bool(run.dropped) and _item(crate_id) != null, "the cargo crate is on the ground to seize")
	var bonus := _kind(d.objectives, Objectives.EXTRACT_ITEM, true)
	Contracts.objectives.server_items_out([{"id": ScenarioGen.CONVOY_CARGO, "count": 1, "state": {}}])  # (a two-handed carry keeps no state)
	check(Contracts.objectives.get_objective(bonus.oid).state == Objectives.DONE, "carrying the crate out earns the bonus")
	var debrief := _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("cargo"),
		"debrief: convoy stopped and cargo out is completed with the cargo bonus (%s)" % _bonus_texts(debrief))
	await _clean_scenario(before)
	# The convoy that gets away.
	d = await _deploy_new("convoy_ambush")
	main = _kind(d.objectives, Objectives.CONVOY)
	scen.server_advance(float(main.params.depart_s) + 2.0)
	run = scen.run_of(String(main.oid))
	var end := _v(main.params.route[(main.params.route as Array).size() - 1])
	for e: Dictionary in run.vehicles:
		if bool(e.cargo):
			(e.v as Vehicle).global_position = level.ground_point(end)
	scen.server_advance(1.0)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.FAILED and String(Contracts.objectives.get_objective(main.oid).progress).contains("got away"),
		"a cargo truck that reaches the far end has got away: the objective fails")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0,
		"debrief: the convoy got away, no completion pay (%s)" % debrief.contracts[0].outcome)
	await _clean_scenario(before)
	# A virtual convoy gets away too: its profile reaching the far end fails the objective.
	d = await _deploy_new("convoy_ambush")
	main = _kind(d.objectives, Objectives.CONVOY)
	scen.server_advance(float(main.params.depart_s) + 2.0)
	run = scen.run_of(String(main.oid))
	if vz and run.has("group") and vz.server_virtualize(run.group, true):
		vz.server_advance(3600.0)
		scen.server_advance(1.0)
		check(Contracts.objectives.get_objective(main.oid).state == Objectives.FAILED and not Virtualizer.is_virtual(run.group),
			"a virtual convoy that drives to the far end gets away: the objective fails, the profile goes")
	else:
		check(false, "a rolling convoy can go virtual")
	_end_deployment()
	await _clean_scenario(before)

	# Hold the line: the clock runs while we hold, waves from several sides, the position can fall.
	d = await _deploy_new("defend_hold")
	main = _kind(d.objectives, Objectives.HOLD_POINT)
	var point := _v(main.params.pos)
	var module := level.get_module(String(Contracts.contract(d.cid).module_id))
	check(not main.is_empty() and module != null and level.garrison_size(module.module_id) == 0 and module.distance_to(point) <= 0.5,
		"a hold contract: the position is its module's (%s), which has no garrison" % Contracts.contract(d.cid).module_id)
	var waves_before := r.waves.size()
	_place(player, point)
	scen.server_advance(float(main.params.hold_s) * 0.6)
	var edges := {}
	for w in range(waves_before, r.waves.size()):
		var e: Vector3 = r.waves[w].edge
		edges[int(roundf(rad_to_deg(atan2(e.z - point.z, e.x - point.x)) / 40.0))] = true
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.ACTIVE and r.waves.size() - waves_before >= 3 and edges.size() >= 3,
		"holding: the clock runs, %d waves came from %d directions (%s)" % [r.waves.size() - waves_before, edges.size(), Contracts.objectives.get_objective(main.oid).progress])
	scen.server_advance(float(main.params.hold_s) * 0.5)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.DONE, "the time held: done")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and int(debrief.contracts[0].completion) > 0, "debrief: the line held is completed and paid")
	await _clean_scenario(before)
	d = await _deploy_new("defend_hold")
	main = _kind(d.objectives, Objectives.HOLD_POINT)
	point = _v(main.params.pos)
	_place(player, point)
	scen.server_advance(5.0)
	_place(player, point + Vector3(zone_half * 0.5, 0, 0))
	var foe := level.spawn_soldier({"name": "Intruder", "faction": "hostile", "variant": "urban", "pos": level.ground_point(point + Vector3(3, 0, 0)),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(foe).process_mode = Node.PROCESS_MODE_DISABLED
	scen.server_advance(MissionScenario.LOSE_S + 2.0)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.FAILED and String(Contracts.objectives.get_objective(main.oid).progress).contains("fell"),
		"nobody of ours in it and the enemy standing there: the position falls")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0, "debrief: a lost position pays nothing (%s)" % debrief.contracts[0].outcome)
	foe.queue_free()
	await _clean_scenario(before)

	# Downed crew: the wreck, the crew (some hurt), waves converging, need N out.
	d = await _deploy_new("crew_rescue")
	main = _kind(d.objectives, Objectives.RESCUE_CREW)
	var all := _kind(d.objectives, Objectives.RESCUE_CREW, true)
	run = scen.run_of(String(main.oid))
	var crew: Array = main.params.crew
	var wreck := run.get("wreck") as Vehicle
	var hurt := 0
	for s: Soldier in run.crew:
		if s.vitals.injury() > 0.0:
			hurt += 1
	check(wreck != null and wreck.wrecked and wreck.model == "uh60" and (run.crew as Array).size() == crew.size() and crew.size() >= 2 and crew.size() <= 4 and hurt >= 1,
		"a rescue: the UH-60 as a wreck with %d crew, %d of them wounded" % [crew.size(), hurt])
	check(level.people.hvt(String(crew[0].hvt)) != null and level.people.hvt(String(crew[0].hvt)).faction == Person.FACTION,
		"the crew are people of the friendly side, each their own HVT id")
	var waves_start := r.waves.size()
	scen.server_advance(float(main.params.first_wave_s) + 1.0)
	check(r.waves.size() > waves_start, "enemies converge on the site: a wave in after %.0f s" % float(main.params.first_wave_s))
	for i in crew.size() - 1:
		Contracts.server_hvt_delivered(String(crew[i].hvt), true)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.DONE and Contracts.objectives.get_objective(all.oid).state == Objectives.ACTIVE,
		"all but one out: the rescue is done, the whole-crew bonus still open (%s)" % Contracts.objectives.get_objective(all.oid).progress)
	Contracts.server_hvt_delivered(String(crew[crew.size() - 1].hvt), true)
	check(Contracts.objectives.get_objective(all.oid).state == Objectives.DONE, "the last one out: the bonus too")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("whole crew"), "debrief: completed with the whole-crew bonus (%s)" % _bonus_texts(debrief))
	await _clean_scenario(before)
	d = await _deploy_new("crew_rescue")
	main = _kind(d.objectives, Objectives.RESCUE_CREW)
	run = scen.run_of(String(main.oid))
	for i in 2:
		_kill(run.crew[i])
	await _frames(3)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.FAILED, "two of the crew dead: the rescue fails (%s)" % Contracts.objectives.get_objective(main.oid).progress)
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0, "debrief: no pay for a lost crew (%s)" % debrief.contracts[0].outcome)
	await _clean_scenario(before)

	# Client escort (Captain, 2026-10-17: real-world inspired): one client, no wreck, an ambush on
	# the way out, waves after the client; the bonus for bringing them out unhurt.
	var escort_waves := r.waves.size()
	d = await _deploy_new("psd_escort")
	main = _kind(d.objectives, Objectives.RESCUE_CREW)
	var unhurt := _kind(d.objectives, Objectives.RESCUE_CREW, true)
	run = scen.run_of(String(main.oid))
	check(not main.is_empty() and (main.params.crew as Array).size() == 1 and int(main.params.need) == 1 and run.get("wreck") == null
		and (run.crew as Array).size() == 1 and not unhurt.is_empty() and bool(unhurt.params.get("unhurt", false)),
		"an escort: one client to bring out, no wreck, an unhurt bonus")
	check(r.waves.size() > escort_waves and (run.get("ambush", []) as Array).size() >= 1, "an ambush team goes out to lie in wait (%d)" % (run.get("ambush", []) as Array).size())
	var client: Soldier = run.crew[0]
	check(level.people.hvt(String(main.params.crew[0].hvt)) == client and client.faction == Person.FACTION, "the client is a person of the friendly side")
	client.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	scen.server_advance(1.0)
	check(Contracts.objectives.get_objective(unhurt.oid).state == Objectives.FAILED, "hurt on the way: the unhurt bonus is gone")
	Contracts.server_hvt_delivered(String(main.params.crew[0].hvt), true)
	check(Contracts.objectives.get_objective(main.oid).state == Objectives.DONE, "delivered alive: the escort is done")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed", "debrief: completed (%s)" % debrief.contracts[0].outcome)
	await _clean_scenario(before)

	# Recon: observe the sites; the bonus for never being spotted.
	d = await _deploy_new("recon")
	var sites: Array = d.objectives.filter(func(o: Dictionary) -> bool: return o.kind == Objectives.RECON_SITE)
	var unseen := _kind(d.objectives, Objectives.UNDETECTED, true)
	check(sites.size() >= 2 and not unseen.is_empty() and Contracts.contract(d.cid).module_id == "",
		"a recon contract: %d sites to observe and a never-spotted bonus" % sites.size())
	var first_site := Contracts.objectives.get_objective(String(sites[0].oid))
	_place(player, _v(first_site.params.pos) + Vector3(0, 0, 18))
	scen.server_advance(float(first_site.params.dwell_s) + 1.0)
	check(Contracts.objectives.get_objective(first_site.oid).state == Objectives.DONE or float(scen.run_of(String(first_site.oid)).get("dwell", 0.0)) > 0.0,
		"standing in sight of a site long enough marks it (%s)" % Contracts.objectives.get_objective(first_site.oid).progress)
	for o: Dictionary in sites:
		scen.server_mark_site(String(o.oid))
	check(Contracts.objectives.contract_done(d.cid), "every site observed: the required objectives are done")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("never spotted"), "debrief: completed, with the never-spotted bonus (%s)" % _bonus_texts(debrief))
	await _clean_scenario(before)
	d = await _deploy_new("recon")
	sites = d.objectives.filter(func(o: Dictionary) -> bool: return o.kind == Objectives.RECON_SITE)
	scen.server_spotted()
	for o: Dictionary in sites:
		scen.server_mark_site(String(o.oid))
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and not _bonus_texts(debrief).contains("never spotted"), "spotted: still completed, but no bonus (%s)" % _bonus_texts(debrief))
	d = await _deploy_new("recon")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0, "no site observed: not completed (%s)" % debrief.contracts[0].outcome)
	await _clean_scenario(before)

	# Sabotage: destroy the target; the unseen bonus.
	d = await _deploy_new("sabotage")
	main = _sabotage_target(d.objectives)
	unseen = _kind(d.objectives, Objectives.UNDETECTED, true)
	check(not main.is_empty() and not unseen.is_empty(), "a sabotage contract: a target to destroy (%s) and an unseen bonus" % main.get("text", ""))
	Contracts.server_cache_destroyed(String(main.params.cache))
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("unseen"), "debrief: target destroyed and never spotted: completed with the bonus (%s)" % _bonus_texts(debrief))
	d = await _deploy_new("sabotage")
	main = _sabotage_target(d.objectives)
	scen.server_spotted()
	Contracts.server_cache_destroyed(String(main.params.cache))
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome == "completed" and not _bonus_texts(debrief).contains("unseen"), "spotted: the target down but no bonus (%s)" % _bonus_texts(debrief))
	d = await _deploy_new("sabotage")
	debrief = _end_deployment()
	check(debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0, "target left standing: not completed (%s)" % debrief.contracts[0].outcome)
	await _clean_scenario(before)
	r.params = Reinforcements.DEFAULTS.duplicate()


func _scenario_nodes(run: Dictionary) -> Array:
	var out: Array = []
	for key: String in ["crew", "ambush", "waves"]:
		out.append_array(run.get(key, []))
	if is_instance_valid(run.get("wreck")):
		out.append(run.wreck)
	for e: Dictionary in run.get("vehicles", []):
		out.append_array(e.crew)
		if is_instance_valid(e.v):
			out.append(e.v)
	return out


## A2-03: serialize partial runs, retire their controller/entities, load the campaign and
## return. This covers every scenario family and repeated arrival events without respawning.
func _test_scenario_resume() -> void:
	print("Scenario checkpoints across return and reload (A2-03)")
	_clear_waves()
	for type: String in ["recon", "defend_hold", "convoy_ambush", "crew_rescue", "psd_escort"]:
		Contracts.new_full_campaign(88, 900000)
		var d := await _deploy_new(type)
		var scen := MissionScenario.of(level)
		scen.set_physics_process(false)
		var kind := Objectives.RECON_SITE if type == "recon" else Objectives.HOLD_POINT if type == "defend_hold" else Objectives.CONVOY if type == "convoy_ambush" else Objectives.RESCUE_CREW
		var main := _kind(d.objectives, kind)
		var oid := String(main.oid)
		var run := scen.run_of(oid)
		if kind == Objectives.RECON_SITE:
			run.dwell = 7.0
		elif kind == Objectives.HOLD_POINT:
			run.clock = 7.0
			run.started = true
			run.away_s = 3.0
			run.lose_s = 2.0
		elif kind == Objectives.CONVOY:
			scen.server_advance(float(main.params.depart_s) + 1.0)
			run = scen.run_of(oid)
			run.ambushed = true
		else:
			run.t = 7.0
			run.wave = 1
		var before: Array = _scenario_nodes(run)
		var ids: Array = (run.get("vehicles", []) as Array).map(func(e: Dictionary) -> String: return (e.v as Vehicle).vehicle_id)
		check(GameState.save_zone() and Campaign.save_campaign(), "A2-03: %s checkpoint saves to disk" % type)
		var saved: Dictionary = Campaign.section(&"contracts").deployment.scenario_runs[oid].duplicate(true)
		check(not Contracts.deployment().has("scenario_runs"), "A2-03: private entity checkpoints stay out of the public deployment")
		# Returning while this controller is still present must not reset or duplicate anything.
		Contracts.server_arrived(ZONE)
		check(scen.run_of(oid) == run and _scenario_nodes(run).size() == before.size(), "A2-03: repeated %s arrival is idempotent" % type)
		for n: Variant in before:
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n.queue_free()
		scen.queue_free()
		await _frames(2)
		check(Campaign.load_campaign(), "A2-03: %s campaign loads from disk" % type)
		if kind == Objectives.CONVOY:
			# The normal world loader restores the vehicles first; the scenario must reuse them.
			BaseHub.server_switch_level(level.level_info(), GameState.zone_id)
			level = CompoundLevel.current(self) as ZoneLevel
			player = level.players.get_node(^"1") as Soldier
			player.set_physics_process(false)
			scen = MissionScenario.of(level)
		else:
			scen = MissionScenario.new()
			level.add_child(scen)
		scen.set_physics_process(false)
		Contracts.server_arrived(ZONE)
		var restored := scen.run_of(oid)
		check(not restored.is_empty(), "A2-03: %s active controller returns" % type)
		if restored.is_empty():
			continue
		for key: String in ["t", "dwell", "clock", "started", "wave", "away_s", "lose_s", "phase", "ambushed", "dropped"]:
			if saved.has(key):
				check(restored.get(key) == saved[key], "A2-03: %s preserves %s" % [type, key])
		var entities := _scenario_nodes(restored)
		check(entities.size() == before.size() and entities.all(func(n: Variant) -> bool: return is_instance_valid(n)),
			"A2-03: %s tracked entities return exactly once" % type)
		if kind == Objectives.CONVOY:
			check((restored.vehicles as Array).map(func(e: Dictionary) -> String: return (e.v as Vehicle).vehicle_id) == ids,
				"A2-03: convoy vehicle identities survive")
			check((restored.vehicles as Array).all(func(e: Dictionary) -> bool: return (e.v as Vehicle).driver() != null), "A2-03: convoy crews regain their seats")
		Contracts.server_arrived(ZONE)
		check(_scenario_nodes(scen.run_of(oid)) == entities, "A2-03: second %s return duplicates no entities" % type)
		var terminal := main.duplicate(true)
		terminal.oid = oid + "_finished"
		terminal.state = Objectives.DONE
		var elsewhere := main.duplicate(true)
		elsewhere.oid = oid + "_elsewhere"
		elsewhere.params = main.params.duplicate(true)
		elsewhere.params.zone_id = "another_zone"
		Contracts.contract_returned.emit(String(d.cid), [terminal, elsewhere])
		check(scen.run_of(String(terminal.oid)).is_empty() and scen.run_of(String(elsewhere.oid)).is_empty(), "A2-03: completed and other-zone scenarios stay inactive")
		Contracts.server_abandon_deployment()
		for n: Variant in entities:
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n.queue_free()
		scen.runs.clear()
		await _frames(2)
	# Actual level replacement: a partial recon must remain completable after a cold load.
	Contracts.new_full_campaign(88, 900000)
	var d := await _deploy_new("recon")
	var scen := MissionScenario.of(level)
	scen.set_physics_process(false)
	var main := _kind(d.objectives, Objectives.RECON_SITE)
	var oid := String(main.oid)
	var clear_spot: Vector3 = level.insertion_points()[0]
	main.params.pos = [clear_spot.x, clear_spot.y, clear_spot.z]
	scen.run_of(oid).dwell = 7.0
	Contracts.store_objectives(Contracts.objectives.list)
	check(GameState.save_zone() and Campaign.save_campaign() and Campaign.load_campaign(), "A2-03: recon saves and cold-loads before level replacement")
	var old_id := level.get_instance_id()
	BaseHub.server_switch_level(level.level_info(), GameState.zone_id)
	level = CompoundLevel.current(self) as ZoneLevel
	player = level.players.get_node(^"1") as Soldier
	player.set_physics_process(false)
	scen = MissionScenario.of(level)
	scen.set_physics_process(false)
	Contracts.server_arrived(ZONE)
	check(level.get_instance_id() != old_id and float(scen.run_of(oid).get("dwell", 0.0)) == 7.0,
		"A2-03: a replacement level restores partial recon")
	_place(player, _v(main.params.pos) + Vector3.UP * 4.0)
	scen.server_advance(float(main.params.dwell_s))
	check(Contracts.objectives.get_objective(oid).state == Objectives.DONE, "A2-03: restored recon can finish")


## Generation, no deployment: every new type in every zone, positions inside the zone, text filled
## in, pay and rating in range.
func _test_scenario_generation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var sound := true
	var bad := {}
	var kinds := {}
	for type: String in NEW_TYPES:
		for z: Dictionary in MissionRegistry.zones():
			for i in 6:
				var was := sound
				var c := ContractGen.generate(rng, {"day": 1, "source": "board", "type": type, "zone_id": z.zone_id})
				var half := float(MissionRegistry.zone_def(String(z.zone_id)).size_m) * 0.5
				sound = sound and c.type == type and (c.objectives as Array).size() >= 1 and int(c.rated) >= 1 and int(c.rated) <= 5 and int(c.base_pay) > 0
				for o: Dictionary in c.objectives:
					kinds[o.kind] = true
					sound = sound and not String(o.text).contains("{") and String(o.text) != ""
					var pos: Array = (o.get("params", {}) as Dictionary).get("pos", [0, 0, 0])
					sound = sound and absf(float(pos[0])) <= half and absf(float(pos[2])) <= half
				if type == "convoy_ambush":
					var route: Array = c.objectives[0].params.route
					sound = sound and route.size() >= 3 and route.all(func(p: Array) -> bool: return absf(float(p[0])) <= half and absf(float(p[2])) <= half)
				if type == "recon":
					var sites := (c.objectives as Array).filter(func(o: Dictionary) -> bool: return o.kind == Objectives.RECON_SITE)
					var ids := {}
					for o: Dictionary in sites:
						ids[o.params.module_id] = true
					sound = sound and sites.size() >= 2 and ids.size() == sites.size()
				if was and not sound:
					bad["%s in %s" % [type, z.zone_id]] = c.objectives.map(func(o: Dictionary) -> Variant: return [o.kind, o.get("params", {}).get("pos")])
	check(sound, "convoy, hold, rescue, sabotage and recon generate in every zone: objectives with positions inside the zone, text filled in, a 1-5 rating (%s)" % [bad])
	check(["convoy", "hold_point", "rescue_crew", "recon_site", "undetected", "destroy_cache", "extract_item"].all(func(k: String) -> bool: return kinds.has(k)),
		"their objective kinds (%s)" % [kinds.keys()])
	var board := {}
	for seed_i in 40:
		for o: Dictionary in ContractGen.generate_board(500 + seed_i, 1, {}, 6):
			board[o.type] = true
	check(NEW_TYPES.all(func(t: String) -> bool: return board.has(t)), "the contract board offers all of them (%s)" % [board.keys()])


# --- Mission variety, from the board and played through (task 8, 2026-10-20) ---------------------

const FIVE: Array[String] = ["convoy_ambush", "defend_hold", "crew_rescue", "sabotage", "recon"]


## Sabotage's required target: a fuel store or a mast (destroy_cache) or a vehicle park
## (destroy_vehicles), as it stands now.
func _sabotage_target(list: Array) -> Dictionary:
	for o: Dictionary in list:
		if String(o.kind) in [Objectives.DESTROY_CACHE, Objectives.DESTROY_VEHICLES] and not bool(o.optional):
			return Contracts.objectives.get_objective(String(o.oid))
	return {}


## An offer as the board makes them for this zone (ContractGen.generate as
## Contracts.server_refresh_board calls it, no type asked for; the zone fixed as the faction war's
## own offers fix it): the first of `type` that `want` (the offer) takes, briefed truthfully. {} if
## none came up in `tries` offers.
func _board_offer(type: String, want := Callable(), tries := 500) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100 + _made
	_made += 1
	for i in tries:
		var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "zone_id": ZONE})
		if c.type == type and (not want.is_valid() or bool(want.call(c))):
			c.understated = false
			c.true_rating = c.rated
			c.enemy_count = c.enemy_est
			return c
	return {}


func _deploy_offer(c: Dictionary) -> Dictionary:
	var cid := _add(c)
	Contracts.server_accept(cid, ContractGen.default_terms())
	var why := Contracts.server_start_deployment([cid], ZONE)
	await _frames(3)
	return {"cid": cid, "why": why, "objectives": Contracts.objectives.for_contract(cid)}


## The sabotage target site an offer picked ("fuel", "park", "mast").
static func _sabotage_site(c: Dictionary) -> String:
	for o: Dictionary in c.get("objectives", []):
		if not bool(o.get("optional", false)) and String(o.kind) in [Objectives.DESTROY_CACHE, Objectives.DESTROY_VEHICLES]:
			return String(o.get("site", ""))
	return ""


## Task 8 (Captain's tasking, 2026-10-19): convoy ambush, hold the line, downed crew rescue,
## sabotage and recon each taken as the board offers it here and played to the end through the
## objective code itself (no test hooks): the convoy's crews killed in the ambush, the crate
## carried out; the position held on the clock; the crew walked to a landing zone and delivered by
## the People ledger; every recon site watched in line of sight; sabotage's fuel store and mast
## blown by a placed charge, its vehicle park by a charge on each vehicle. Each then extracts, with
## the debrief and pay, and a vehicle park left standing pays nothing.
func _test_variety_played() -> void:
	print("Mission variety: from the board, played through")
	var scen := MissionScenario.of(level)
	if scen == null:
		check(false, "the level has its MissionScenario node")
		return
	Contracts.new_full_campaign(89, 900000)
	_command_on(false)  # the enemy's own orders stand down: the contracts below play alone
	_calm()
	_clear_waves()
	var r := MapNodes.reinforcements(level)
	r.params.max_alive = 8  # keep the waves small
	r.params.max_pairs = 1
	var before := level.ai.get_children()
	var charges := Charges.of(level)
	var settings: Dictionary = MissionRegistry.data().settings
	var fuse: Variant = settings.charge_fuse_s
	settings.charge_fuse_s = 0.5
	var lz := level.extraction_points()[0]
	var offers := {}
	for type: String in FIVE:
		offers[type] = _board_offer(type)
	for site: String in ["fuel", "park", "mast"]:
		offers["sabotage_" + site] = _board_offer("sabotage", func(x: Dictionary) -> bool: return _sabotage_site(x) == site)
	var titles: Array = offers.values().map(func(x: Dictionary) -> String: return String(x.get("title", "none")))
	check(offers.values().all(func(x: Dictionary) -> bool: return not x.is_empty()),
		"the board offers each of the five here, and sabotage at a fuel store, a vehicle park and a radio mast (%s)" % [titles])

	# Convoy ambush: every crew killed in the ambush stops it; the crate goes out with the squad.
	var c: Dictionary = offers.convoy_ambush
	if not c.is_empty():
		_place(player, level.insertion_points()[0])
		var d := await _deploy_offer(c)
		var main := _kind(d.objectives, Objectives.CONVOY)
		scen.server_advance(float(main.params.depart_s) + 2.0)
		var run := scen.run_of(String(main.oid))
		var crews := 0
		for e: Dictionary in run.get("vehicles", []):
			for s: Variant in e.crew:
				if is_instance_valid(s) and (s as Soldier).vitals.is_up():
					(s as Soldier).vitals.server_kill()
					crews += 1
		await _frames(2)
		scen.server_advance(1.0)
		main = Contracts.objectives.get_objective(String(main.oid))
		check(d.why == "" and crews > 0 and main.state == Objectives.DONE,
			"convoy from the board: its %d crew killed in the ambush, the convoy is stopped (%s)" % [crews, main.progress])
		var crate := _item(String(main.params.cargo_ids[0]))
		check(crate != null and crate.item_id == StringName(ScenarioGen.CONVOY_CARGO), "its cargo crate lies by the first cargo truck")
		if crate:
			_drop_all(player, StringName(ScenarioGen.CONVOY_CARGO))
			player.inventory.release_hands()
			check(player.inventory.take(crate.item_id, 1, crate.state) == 1, "picked up in both hands")
			crate.queue_free()
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("cargo") and int(debrief.contracts[0].completion) > 0,
			"carried out at extraction: completed and paid, with the cargo bonus (%s)" % _bonus_texts(debrief))
		player.inventory.release_hands()
		await _clean_scenario(before)

	# Hold the line: the clock runs out with one of ours in the position, waves or not.
	c = offers.defend_hold
	if not c.is_empty():
		var d := await _deploy_offer(c)
		var main := _kind(d.objectives, Objectives.HOLD_POINT)
		var point := _v(main.params.pos)
		_place(player, point)
		scen.server_advance(float(main.params.hold_s) + 1.0)
		main = Contracts.objectives.get_objective(String(main.oid))
		check(d.why == "" and main.state == Objectives.DONE,
			"hold from the board: held for %d min at the %s, done (%s)" % [roundi(float(main.params.hold_s) / 60.0), String(main.params.name), main.progress])
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and int(debrief.contracts[0].completion) > 0, "extracted: completed and paid (%s)" % debrief.contracts[0].outcome)
		await _clean_scenario(before)

	# Downed crew: each one walked to the landing zone, delivered through the People ledger.
	c = offers.crew_rescue
	if not c.is_empty():
		var d := await _deploy_offer(c)
		var main := _kind(d.objectives, Objectives.RESCUE_CREW)
		var all := _kind(d.objectives, Objectives.RESCUE_CREW, true)
		var crew: Array = scen.run_of(String(main.oid)).get("crew", [])
		_place(player, lz + Vector3(1.5, 0, 0))
		var k := 0
		for s: Variant in crew:
			if not is_instance_valid(s):
				continue
			var person := s as Soldier
			var brain := person.get_node_or_null(^"PersonAI")
			if brain:
				brain.process_mode = Node.PROCESS_MODE_DISABLED  # the walk is ours
			level.people.server_lead(player, person)
			_place(person, lz + Vector3(-1.0 - k, 0, 1.0))
			k += 1
		await _wait_for(func() -> bool: return Contracts.objectives.get_objective(String(all.oid)).state != Objectives.ACTIVE, 4.0)
		main = Contracts.objectives.get_objective(String(main.oid))
		all = Contracts.objectives.get_objective(String(all.oid))
		check(d.why == "" and crew.size() >= 2 and main.state == Objectives.DONE and all.state == Objectives.DONE,
			"crew rescue from the board: all %d crew brought to %s, delivered: done with the whole-crew bonus (%s)" % [crew.size(), "the landing zone", all.progress])
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("whole crew"), "extracted: completed, the bonus paid (%s)" % _bonus_texts(debrief))
		await _clean_scenario(before)

	# Recon: each site watched from close by, in line of sight, until its dwell is done.
	c = offers.recon
	if not c.is_empty():
		var d := await _deploy_offer(c)
		var sites: Array = d.objectives.filter(func(x: Dictionary) -> bool: return x.kind == Objectives.RECON_SITE)
		var watched := 0
		for site_o: Dictionary in sites:
			_place(player, _v(site_o.params.pos) + Vector3(0, 0, 4))
			await _frames(2)
			scen.server_advance(float(site_o.params.dwell_s) + 1.0)
			if Contracts.objectives.get_objective(String(site_o.oid)).state == Objectives.DONE:
				watched += 1
		check(d.why == "" and sites.size() >= 2 and watched == sites.size() and Contracts.objectives.contract_done(d.cid),
			"recon from the board: %d of %d sites watched in line of sight, each done" % [watched, sites.size()])
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and _bonus_texts(debrief).contains("never spotted"), "extracted unseen: completed with the bonus (%s)" % _bonus_texts(debrief))
		await _clean_scenario(before)

	# Sabotage: a fuel store and a mast blown by a placed charge.
	for site: String in ["fuel", "mast"]:
		c = offers["sabotage_" + site]
		if c.is_empty():
			continue
		var d := await _deploy_offer(c)
		var main := _sabotage_target(d.objectives)
		var at := _v(main.pos)
		_place(player, at + Vector3(1.8, 0, 0))
		player.inventory.take(Charges.ITEM, 1)
		var placed_ok := Contracts.objectives.server_place_charge(player, String(main.oid))
		_place(player, at + Vector3(40, 0, 0))  # clear of the blast
		await _wait_for(func() -> bool: return Contracts.objectives.get_objective(String(main.oid)).state == Objectives.DONE, 3.0)
		check(d.why == "" and main.kind == Objectives.DESTROY_CACHE and placed_ok and Contracts.objectives.get_objective(String(main.oid)).state == Objectives.DONE,
			"sabotage from the board (%s): a charge set on the %s goes off, it's destroyed" % [c.title, String(main.params.name)])
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and int(debrief.contracts[0].completion) > 0 and _bonus_texts(debrief).contains("unseen"),
			"extracted: completed and paid, never seen (%s)" % _bonus_texts(debrief))
		await _clean_scenario(before)

	# Sabotage: a vehicle park, a charge on each vehicle; and one left standing pays nothing.
	c = offers.sabotage_park
	if not c.is_empty():
		var d := await _deploy_offer(c)
		var main := _sabotage_target(d.objectives)
		var parked := scen.park_vehicles(String(main.oid))
		var centre := _v(main.params.pos)
		var sound := parked.size() == (main.params.vehicles as Array).size()
		for v: Vehicle in parked:
			sound = sound and v.faction == &"hostile" and v.occupants().is_empty() and v.can_drive() and not v.wrecked and _flat_m(v.global_position, centre) < 12.0
		check(d.why == "" and main.kind == Objectives.DESTROY_VEHICLES and sound and main.state == Objectives.ACTIVE,
			"sabotage from the board (%s): %d vehicles parked there, hostile, empty and whole (%s)" % [c.title, parked.size(), main.progress])
		await _frames(30)
		var still := parked.all(func(x: Vehicle) -> bool: return is_instance_valid(x) and _flat_m(x.global_position, centre) < 12.0 and x.global_position.y > level.ground_height(x.global_position.x, x.global_position.z) - 1.0)
		check(still, "they stay parked, on the ground")
		var used := 0
		for v: Vehicle in parked:
			for attempt in 3:
				if not is_instance_valid(v) or v.wrecked or v.is_burning() or not v.can_drive():
					break
				player.inventory.take(Charges.ITEM, 1)
				_place(player, v.global_position + Vector3(2.5, 0, 0))
				var id := charges.server_place_at(player, Transform3D(Basis.IDENTITY, v.global_position + Vector3.UP * 1.0), v)
				_place(player, centre + Vector3(45, 0, 0))  # clear of the blast
				if id == "":
					break
				used += 1
				charges._due[id] = Charges._now()
				await _frames(3)
		scen.server_advance(1.0)
		main = Contracts.objectives.get_objective(String(main.oid))
		check(main.state == Objectives.DONE and used <= parked.size() * 2,
			"a charge set on each vehicle (%d for %d): every one out of action, the park is done (%s)" % [used, parked.size(), main.progress])
		var debrief := _end_deployment()
		check(debrief.contracts[0].outcome == "completed" and int(debrief.contracts[0].completion) > 0, "extracted: completed and paid (%s)" % debrief.contracts[0].outcome)
		await _clean_scenario(before)
		# The same park left standing.
		d = await _deploy_offer(_board_offer("sabotage", func(x: Dictionary) -> bool: return _sabotage_site(x) == "park"))
		main = _sabotage_target(d.objectives)
		scen.server_advance(2.0)
		var standing := String(Contracts.objectives.get_objective(String(main.oid)).get("state", ""))
		debrief = _end_deployment()
		check(standing == Objectives.ACTIVE and debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0,
			"a vehicle park left standing: not completed, no pay (%s)" % debrief.contracts[0].outcome)
		await _clean_scenario(before)
	settings.charge_fuse_s = fuse
	r.params = Reinforcements.DEFAULTS.duplicate()
	_command_on(true)


# --- The forward observer (fire support, 2026-10-20) -----------------------------------------------

## The forward observer contract (ObserverMission; FireSupport's fire missions): it comes up on the
## board in zones holding a module it plays in, its targets the first one required and each other a
## bonus; taken here, its targets are parked in the target area (hostile, empty, whole), the squad
## gets eyes on the area from an observation post a few hundred metres out, and calls the mortars
## (paid per round, the real gates on) onto each target: every one destroyed by the guns is done,
## and the debrief pays the job plus a bonus per further target and the never-spotted bonus. A
## target put out of action any other way (set burning here) fails: no pay.
func _test_forward_observer() -> void:
	print("The forward observer: from the board, played through")
	var scen := MissionScenario.of(level)
	var obs := ObserverMission.of(level)
	var fs := FireSupport.of(level)
	if scen == null or obs == null or fs == null:
		check(false, "the level has its MissionScenario, ObserverMission and FireSupport nodes")
		return
	var def := MissionRegistry.type_def("forward_observer")
	var count := 0
	var fitting := true
	var kinds := {}
	for seed_i in 60:
		for o: Dictionary in ContractGen.generate_board(900 + seed_i, 1, {}, 6):
			if String(o.type) != "forward_observer":
				continue
			count += 1
			kinds[String(o.zone_kind)] = true
			var zone := MissionRegistry.zone(String(o.zone_id))
			var targets: Array = (o.objectives as Array).filter(func(x: Dictionary) -> bool: return String(x.kind) == Objectives.FIRE_TARGET)
			fitting = fitting and ZoneModules.base(String(o.module)) in MissionRegistry.type_modules(def) and ZoneModules.base(String(o.module)) in zone.modules \
				and targets.size() >= 3 and not bool(targets[0].get("optional", false)) \
				and targets.slice(1).all(func(x: Dictionary) -> bool: return bool(x.get("optional", false)) and float(x.get("bonus_share", 0.0)) > 0.0) \
				and (o.objectives as Array).any(func(x: Dictionary) -> bool: return String(x.kind) == Objectives.RECON_SITE) \
				and (o.objectives as Array).any(func(x: Dictionary) -> bool: return String(x.kind) == Objectives.UNDETECTED)
	check(count > 0 and fitting and kinds.has("contract") and kinds.has("hot"),
		"the board offers it (%d in 60 boards), in contract and hot zones holding a module it plays in: eyes on the area, the first target the job, each other a bonus, never spotted a bonus" % count)
	Contracts.new_full_campaign(90, 900000)
	_command_on(false)
	_calm()
	_clear_waves()
	var before := level.ai.get_children()
	var c := _board_offer("forward_observer")
	check(not c.is_empty(), "the board offers one here (%s)" % String(c.get("title", "none")))
	if c.is_empty():
		_command_on(true)
		return
	c.employer = "us_forces"  # (a neutral standing lends the mortars; the battery wants Trusted)
	var d := await _deploy_offer(c)
	var area := _kind(d.objectives, Objectives.RECON_SITE)
	var targets: Array = d.objectives.filter(func(x: Dictionary) -> bool: return String(x.kind) == Objectives.FIRE_TARGET).map(
		func(x: Dictionary) -> Dictionary: return Contracts.objectives.get_objective(String(x.oid)))
	var parked := true
	for t: Dictionary in targets:
		var v := obs.target_vehicle(String(t.oid))
		parked = parked and v != null and v.faction == &"hostile" and v.occupants().is_empty() and not v.wrecked and _flat_m(v.global_position, _v(t.params.pos)) < 8.0
	check(d.why == "" and targets.size() >= 3 and parked and String(targets[0].state) == Objectives.ACTIVE,
		"deployed (%s): %d targets parked in the target area, hostile, empty and whole" % [c.title, targets.size()])
	# Eyes on the targets counts though the middle of the area is walled in (Captain, 2026-10-21: "im
	# in the area observing it but nothing"): a box round the middle, the post seeing a target.
	var centre := _v(area.params.pos)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(8, 8, 8)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	level.add_child(wall)
	wall.global_position = level.ground_point(centre) + Vector3.UP * 2.0
	await get_tree().physics_frame
	var points := scen.sight_points(area)
	var target_at: Vector3 = points[1] if points.size() > 1 else Vector3.INF
	var hidden_middle := not scen._line_of_sight(target_at + Vector3(0, 30, 0), points[0]) if target_at.is_finite() else false
	var seen_post := _observation_post(scen, (target_at - Vector3.UP * 1.2) if target_at.is_finite() else centre, target_at)
	if seen_post.is_finite() and hidden_middle:
		_place(player, seen_post)
		await get_tree().physics_frame
		scen.server_advance(float(area.params.dwell_s) + 1.0)
		check(Contracts.objectives.get_objective(String(area.oid)).state == Objectives.DONE and not scen._line_of_sight(seen_post + Vector3.UP * 1.6, points[0]),
			"eyes on a target counts though the middle of the area is walled in (%d sight points)" % points.size())
	else:
		check(points.size() >= 1 + targets.size(), "the area's sight points take in its targets (%d points; no post to try from here)" % points.size())
	wall.queue_free()
	await get_tree().physics_frame
	# Eyes on, from an observation post out of the guns' danger close.
	var post := _observation_post(scen, centre)
	if post.is_finite():
		_place(player, post)
		scen.server_advance(float(area.params.dwell_s) + 1.0)
	else:
		_place(player, centre + Vector3(0, 0, 300))
		scen.server_mark_site(String(area.oid))  # (no line of sight from any post round it on this terrain)
	area = Contracts.objectives.get_objective(String(area.oid))
	check(area.state == Objectives.DONE, "eyes on the target area from %s %d m out" % ["a post" if post.is_finite() else "(marked) a spot", roundi(_flat_m(player.global_position, centre))])
	# The guns onto each target: paid per round, the real gates on.
	FireSupport.free_calls = 0
	FireSupport.gated = 1
	FireSupport.dispersion_mult = 0.1  # (accuracy is the firesupport suite's: here each target is hit)
	fs.server_reset_limits()
	var funds := Economy.cash() + int(Contracts.contract(d.cid).get("support_left", 0))
	var fired := 0
	var why_all := ""
	var destroyed := 0
	var states := PackedStringArray()
	for t: Dictionary in targets:
		var v := obs.target_vehicle(String(t.oid))
		if v == null:
			continue
		var why := Supports.server_command(player, "support:fire:call:mortar:here", v.global_position, PackedStringArray())
		fs.server_set_bias("mortar", Vector3.ZERO)
		await _fs_land(fs)
		why += Supports.server_command(player, "support:fire:ffe:mortar:he:4", Vector3.INF, PackedStringArray())
		await _fs_land(fs)
		fired += 5
		fs.server_advance(FireSupport.SPLASH_WARN_S + float(FireMission.unit("mortar").cooldown_s) + 2.0)  # the mission over, the section ready again
		await _frames(3)
		obs.server_check()
		why_all += why
		var now_o := Contracts.objectives.get_objective(String(t.oid))
		if now_o.state == Objectives.DONE:
			destroyed += 1
		var left := obs.target_vehicle(String(t.oid))
		states.append("%s: %s (%s)%s" % [String(t.params.model), String(now_o.state), String(now_o.progress),
			"" if left == null else ", hull %d%%%s" % [roundi(left.zone_health(Vehicle.ZONE_HULL) * 100.0), ", burning" if left.is_burning() else ""]])
	var spent := funds - Economy.cash() - int(Contracts.contract(d.cid).get("support_left", 0))
	check(why_all == "" and destroyed == targets.size(), "the mortars called onto each target in turn: %d of %d destroyed by the guns ('%s'; %s)" % [destroyed, targets.size(), why_all, "; ".join(states)])
	check(spent == fired * Prices.support_price("mortar_round"), "the %d rounds paid from the support budget and cash ($%d)" % [fired, spent])
	var debrief := _end_deployment()
	var target_bonuses := (debrief.contracts[0].bonuses as Array).filter(func(b: Dictionary) -> bool: return String(b.text).contains("Bring fire")).size()
	check(debrief.contracts[0].outcome == "completed" and int(debrief.contracts[0].completion) > 0 and target_bonuses == targets.size() - 1
		and _bonus_texts(debrief).contains("never spotted"),
		"extracted: completed and paid, a bonus for each further target (%d) and for never being spotted (%s)" % [target_bonuses, _bonus_texts(debrief)])
	await _clean_scenario(before)
	# A target put out of action any other way.
	c = _board_offer("forward_observer")
	if not c.is_empty():
		c.employer = "us_forces"
		d = await _deploy_offer(c)
		var first: Dictionary = d.objectives.filter(func(x: Dictionary) -> bool: return String(x.kind) == Objectives.FIRE_TARGET)[0]
		var v := obs.target_vehicle(String(first.oid))
		if v:
			v.server_start_fire()  # (a charge, a rocket: not the guns)
		obs.server_check()
		var state := String(Contracts.objectives.get_objective(String(first.oid)).get("state", ""))
		debrief = _end_deployment()
		check(v != null and state == Objectives.FAILED and debrief.contracts[0].outcome != "completed" and int(debrief.contracts[0].pay) == 0,
			"a target burned by anything but the guns doesn't count: failed, no pay (%s)" % debrief.contracts[0].outcome)
		await _clean_scenario(before)
	FireSupport.free_calls = -1
	FireSupport.gated = -1
	FireSupport.dispersion_mult = 1.0
	FireSupport.offset_s = 0.0
	_command_on(true)


## A spot 250-450 m from `centre` with a line of sight to it (MissionScenario's, as recon's), or INF.
func _observation_post(scen: MissionScenario, centre: Vector3, look_at := Vector3.INF) -> Vector3:
	var area: Rect2 = level.ground_area().grow(-150.0)
	var to := look_at if look_at.is_finite() else level.ground_point(centre) + Vector3.UP * 2.0
	for r: float in [300.0, 400.0, 250.0, 450.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := centre + Vector3(cos(a), 0.0, sin(a)) * r
			if not area.has_point(Vector2(p.x, p.z)):
				continue
			var g := level.ground_point(p)
			if scen._line_of_sight(g + Vector3.UP * 1.6, to):
				return g
	return Vector3.INF


## Fire support's clock on until no round is in the air (at most two minutes).
func _fs_land(fs: FireSupport) -> void:
	var t := 0.0
	while t < 120.0 and not fs.rounds.is_empty():
		fs.server_advance(1.0)
		t += 1.0
	await _frames(2)
