extends Node
## The LHD as home (docs/lhd_home.md): a new campaign starts aboard the walkable LHD (LhdLevel):
## the hangar's armory stash, muster line and terminals, the ops room on the flight deck, a
## navmesh up the stairs; a client joins aboard; the stash, muster and deploy round trip works
## from it. Taking a zone: its HQ and QRF bases down flip it, the liaison's seize-and-hold
## contract goes on the board (and comes back if lost), winning it moves home to the FOB built on
## that zone's ground; the region map and the save follow. An old save keeps its FOB.

const SEED := 6262
const ZONE := "test_lhd_home_out"
## A hot zone (it has an HQ and QRF bases) to take.
const TAKE := "ridge_hot"
const CLIENT_DONE := "LHD CLIENT DONE"

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var _log: FileAccess  # client: where its checks go


func _ready() -> void:
	GameState.zone_id = "test_lhd_home" + tag
	Campaign.campaign_id = "test_lhd_home" + tag  # never touch a real save
	get_tree().create_timer(800.0).timeout.connect(func() -> void:
		_say("LHD_HOME TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--join" in OS.get_cmdline_user_args():
		await _run_client()
		return
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	BaseHub.lhd_home_mode = 1
	BaseHub.base_zone_mode = 1
	await _run()
	print("LHD_HOME TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	BaseHub.delete_test_campaign_files()
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	_say("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _say(text: String) -> void:
	if _log:
		_log.store_line(text)
		_log.flush()
	else:
		print(text)


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _cheapest(pool: Array) -> Dictionary:
	var best := {}
	for c: Dictionary in pool:
		if best.is_empty() or int(c.fee) < int(best.fee):
			best = c
	return best


func _run() -> void:
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "host_profile"
	_test_layout()
	BaseHub.new_campaign(SEED)
	check(ZoneControl.home_is_lhd() and ZoneControl.fob_zone() == "", "a new campaign's home is the LHD")
	check(not RegionMap.layout().has(RegionMap.BASE), "with no base cell on the region map while home is a ship")
	var nobody_home := true
	for z: Dictionary in MissionRegistry.zones():
		nobody_home = nobody_home and not RegionMap.links(String(z.zone_id)).any(func(l: Dictionary) -> bool: return String(l.to) == RegionMap.BASE)
	check(nobody_home, "so no zone has a crossing to the base")
	for i in 2:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	Campaign.save_campaign()
	var ids := Roster.ids(BaseHub.roster())
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	check(level is LhdLevel and BaseHub.in_base(), "the campaign starts aboard the LHD (%s)" % (level.get_script().get_global_name() if level else "none"))
	var ship := level as LhdLevel
	if ship == null:
		return
	check(ship.level_info() == {"level": "lhd"} and LevelSwitch.scene_for(ship.level_info()) == "res://scenes/levels/lhd.tscn", "it's the \"lhd\" level for joining clients")
	var started := Time.get_ticks_msec()
	var built := await _wait_until(func() -> bool: return ship.fob_ready(), 60.0)
	check(built, "the ship's voxels are built (%d ms)" % (Time.get_ticks_msec() - started))
	await _wait_until(func() -> bool: return ship.players.get_node_or_null(^"1") != null, 5.0)
	var me := ship.players.get_node_or_null(^"1") as Soldier
	check(me != null and LhdLayout.in_hangar(me.global_position) and absf(me.global_position.y) < 1.0,
		"the host's player comes aboard on the hangar deck (%s)" % (me.global_position if me else "missing"))
	var up := await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return ship.muster_soldier(mid) != null), 30.0)
	check(up and ids.all(func(mid: String) -> bool: return LhdLayout.in_hangar(ship.muster_soldier(mid).global_position)),
		"the company's people stand at the muster line in the hangar")
	_test_terminals(ship)
	await _test_physics(ship)
	await _test_nav(ship)
	var laid := BaseArmory.counts(ship.server_collect_stash())
	check(laid == BaseArmory.counts(BaseHub.stash()) and not laid.is_empty(), "the stash lies on the armory floor (%d kinds)" % laid.size())
	var in_armory := ship.items.get_children().filter(func(n: Node) -> bool:
		return n is WorldItem and LhdLayout.ARMORY.has_point(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z)))
	check(in_armory.size() > 0, "in the armory compartment (%d items)" % in_armory.size())
	# The stash: something dropped aboard is stash; a delivery from the shop comes onto the floor.
	ship.server_spawn_dropped(&"m17", 1, Vector3(-9.0, 0.4, -12.0))
	ship.server_deliver(&"ifak", 2)
	await get_tree().create_timer(0.5).timeout
	var now := BaseArmory.counts(ship.server_collect_stash())
	check(int(now.get("m17", 0)) == int(laid.get("m17", 0)) + 1 and int(now.get("ifak", 0)) == int(laid.get("ifak", 0)) + 2,
		"an item dropped in the hangar and a shop delivery count as stash")
	# The muster line: what a squadmate is handed there goes onto their record.
	var s0 := ship.muster_soldier(ids[0])
	var before := Roster.gear_counts(Roster.json_safe(s0.inventory.net_state))
	var gear0: Dictionary = Roster.json_safe(s0.inventory.net_state)
	var pick := ""
	for container: Variant in gear0.get("containers", {}):
		for entry: Dictionary in gear0.containers[container]:
			if pick == "":
				pick = String(entry.id)
	var took := s0.inventory.remove_one(StringName(pick)) if pick != "" else false
	await get_tree().process_frame
	await get_tree().process_frame
	BaseHub.server_save()
	var after := Roster.gear_counts(BaseHub.member(ids[0]).get("gear", {}))
	check(pick != "" and took and int(after.get(pick, 0)) == int(before.get(pick, 0)) - 1,
		"gear taken off a squadmate at the muster line comes off their record (%s)" % pick)
	check(BaseHub.server_buy_defence("mg_pit") == BaseHub.NO_DEFENCES_ABOARD, "the ops desk sells no defences aboard: they come with a FOB")
	var client := _start_client(ship)
	await _finish_client(client)
	# Out and back.
	var stash_out := BaseArmory.counts(ship.server_collect_stash())
	var why := BaseHub.server_deploy({"zone_id": ZONE + tag, "no_contract": true})
	check(why == "", "deploying from the LHD works (%s)" % why)
	await _wait_until(func() -> bool: return not BaseHub.in_base() and not BaseHub.switch_pending(), 30.0)
	check(not BaseHub.in_base(), "and the squad leaves the ship")
	BaseHub.server_end_deployment([])
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending(), 30.0)
	ship = CompoundLevel.current(self) as LhdLevel
	check(ship != null, "home again: back aboard the LHD")
	if ship == null:
		return
	await _wait_until(func() -> bool: return ship.fob_ready(), 60.0)
	await get_tree().create_timer(1.0).timeout
	check(BaseArmory.counts(ship.server_collect_stash()) == stash_out, "the stash came back aboard once, not twice")
	await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return ship.muster_soldier(mid) != null), 30.0)
	check(ids.all(func(mid: String) -> bool: return ship.muster_soldier(mid) != null), "and the muster line stands again")
	await _test_take_zone()
	_test_old_save()


## The plan, without a level: the flight deck is open over the stairs, the armory sits where
## BaseArmory's slots are, every terminal stands aboard.
func _test_layout() -> void:
	var slot0 := BaseArmory.slot_position(0) + LhdLayout.FOB_ORIGIN
	check(LhdLayout.ARMORY.has_point(Vector2(slot0.x, slot0.z)), "the armory floor's slots lie in the armory compartment")
	var deck_ok := true
	for st: Dictionary in LhdLayout.STAIRS:
		var r := LhdLayout.stair_rect(st)
		deck_ok = deck_ok and LhdLayout.ship_rect().encloses(r) and LhdLayout.HANGAR.encloses(r)
		var steps := LhdLayout.steps(st)
		deck_ok = deck_ok and is_equal_approx(float(steps[-1].top), LhdLayout.DECK_Y)
	check(deck_ok and LhdLayout.stair_steps() == 35, "two stairs in the hangar, 35 steps of 0.2 m up to the flight deck")
	var pieces := LhdLayout.slab_pieces(Rect2(0, 0, 10, 10), [Rect2(2, 2, 2, 2)] as Array[Rect2], 20.0)
	var area := 0.0
	for p in pieces:
		area += p.get_area()
	check(is_equal_approx(area, 96.0) and not pieces.any(func(p: Rect2) -> bool: return p.grow(-0.01).intersects(Rect2(2, 2, 2, 2))),
		"a slab less its holes covers everything but the holes")


func _test_terminals(ship: LhdLevel) -> void:
	var terminals := ship.fob.get_children().filter(func(n: Node) -> bool: return n is BaseTerminal)
	var kinds := terminals.map(func(t: BaseTerminal) -> String: return String(t.kind))
	check(terminals.size() == LhdLayout.TERMINALS.size() and kinds.has("ops") and kinds.has("medbay") and kinds.has("hiring") and kinds.has("armory"),
		"every terminal is aboard: %s" % ", ".join(PackedStringArray(kinds)))
	for t: BaseTerminal in terminals:
		var p := t.global_position
		match String(t.kind):
			"ops":
				check(LhdLayout.on_flight_deck(p) and LhdLayout.ISLAND.has_point(Vector2(p.x, p.z)), "the ops desk is in the island on the flight deck (%s)" % p)
			"medbay":
				check(LhdLayout.MEDBAY.has_point(Vector2(p.x, p.z)), "the medbay desk is in the medbay")
			"hiring":
				check(LhdLayout.HIRING.has_point(Vector2(p.x, p.z)), "the hiring board is in the hiring office")
	var helis := ship.find_children("Heli_*", "StaticBody3D", true, false)
	check(helis.size() == LhdLayout.DECK_HELIS.size() and helis.all(func(n: Node3D) -> bool: return LhdLayout.on_flight_deck(n.global_position)),
		"the helicopters stand on the flight deck (%d)" % helis.size())


## Solid where it should be: the flight deck to stand on, the stairwell open over the steps, the
## hangar's sides, the hull's footprint as the ground.
func _test_physics(ship: LhdLevel) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := ship.get_world_3d().direct_space_state
	var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 12, -60), Vector3(0, 0, -60), 1))
	check(not deck.is_empty() and absf((deck.position as Vector3).y - LhdLayout.DECK_Y) < 0.15, "the flight deck is solid at %.1f m" % LhdLayout.DECK_Y)
	var st: Dictionary = LhdLayout.STAIRS[0]
	var well := LhdLayout.stairwell(st)
	var over := Vector3((float(st.x[0]) + float(st.x[1])) * 0.5, 12, well.get_center().y)
	var step := space.intersect_ray(PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * 12.0, 1))
	check(not step.is_empty() and (step.position as Vector3).y < LhdLayout.DECK_Y - 0.1 and (step.position as Vector3).y > 3.0,
		"the stairwell is open over the top steps (a step at %.1f m)" % ((step.position as Vector3).y if not step.is_empty() else -1.0))
	var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2, -40), Vector3(30, 2, -40), 1))
	check(not side.is_empty() and absf((side.position as Vector3).x - (LhdLayout.HALF_BEAM - LhdLayout.WALL_T)) < 0.15, "the hangar's starboard side is a wall")
	check(ship.ground_area() == LhdLayout.ship_rect() and ship.map_area().encloses(LhdLayout.ship_rect()), "the ground and the map are the ship")


## The squad's navmesh reaches the flight deck from the hangar, up the stairs.
func _test_nav(ship: LhdLevel) -> void:
	var nav := ship.get_node_or_null(^"Navigation") as LhdNav
	check(nav != null, "the ship has its navmesh (LhdNav)")
	for i in 4:
		await get_tree().physics_frame
	var map := ship.get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 0))
	var to := NavigationServer3D.map_get_closest_point(map, Vector3(-6, LhdLayout.DECK_Y, -30))
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reached := not path.is_empty() and path[path.size() - 1].distance_to(to) < 1.0 and absf(to.y - LhdLayout.DECK_Y) < 0.8
	var climbs := Array(path).any(func(p: Vector3) -> bool: return p.y > 2.0 and p.y < 6.0)
	check(reached and climbs, "a squadmate's path runs from the hangar up a stair to the flight deck (%d points, ends %s)" % [path.size(), path[path.size() - 1] if not path.is_empty() else "nowhere"])


## A second process joins the host aboard and checks what it sees.
func _start_client(ship: LhdLevel) -> Dictionary:
	print("A client joins aboard")
	var expect := {"items": ship.items.get_child_count(), "muster": ship.fob.server_read_muster_gear().size()}
	var log_path := ProjectSettings.globalize_path("user://lhd_home_client%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/lhd_home_test.tscn", "--", "--join", "127.0.0.1",
		"--expect", Marshalls.utf8_to_base64(JSON.stringify(expect)), "--log", log_path]
	var pid := OS.create_process(OS.get_executable_path(), args)
	return {"pid": pid, "log": log_path}


func _finish_client(client: Dictionary) -> void:
	var pid: int = client.pid
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	if FileAccess.file_exists(client.log):
		for line in FileAccess.get_file_as_string(client.log).split("\n"):
			if line.strip_edges() != "" and line.strip_edges() != CLIENT_DONE:
				print("  (client) " + line.strip_edges())
	check(code == 0, "the client's checks pass (exit %d)" % code)


## Client process: a plain Join lands aboard the LHD in campaign mode, with the host's player, the
## stash and the muster line.
func _run_client() -> void:
	var args := OS.get_cmdline_user_args()
	var expect: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(args[args.find("--expect") + 1]))
	_log = FileAccess.open(args[args.find("--log") + 1], FileAccess.WRITE)
	Campaign.campaign_id = "test_lhd_home_client" + tag
	BaseHub.local_profile = "client_profile"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var followed := await _wait_until(func() -> bool: return CompoundLevel.current(self) is LhdLevel and BaseHub.campaign_running, 30.0)
	check(followed, "a plain Join follows the host aboard the LHD, in campaign mode")
	var ship := CompoundLevel.current(self) as LhdLevel
	if ship:
		var host_seen := await _wait_until(func() -> bool: return ship.players.get_node_or_null(^"1") != null, 20.0)
		check(host_seen and LhdLayout.in_hangar((ship.players.get_node(^"1") as Node3D).global_position), "the client sees the host's player in the hangar")
		var mine := await _wait_until(func() -> bool: return ship.players.get_node_or_null(NodePath(str(multiplayer.get_unique_id()))) != null, 20.0)
		check(mine, "and its own player comes aboard")
		var items := await _wait_until(func() -> bool: return ship.items.get_child_count() >= int(expect.items), 20.0)
		check(items, "the stash lies on the armory floor for the client too (%d of %d items)" % [ship.items.get_child_count(), int(expect.items)])
		var muster := await _wait_until(func() -> bool:
			return ship.ai.get_children().filter(func(n: Node) -> bool: return n is Soldier and LhdLayout.in_hangar((n as Node3D).global_position)).size() >= int(expect.muster), 20.0)
		check(muster, "and the muster line")
		var ops := ship.fob.get_children().filter(func(n: Node) -> bool: return n is BaseTerminal and String((n as BaseTerminal).kind) == "ops")
		check(ops.size() == 1 and LhdLayout.on_flight_deck((ops[0] as Node3D).global_position), "the ops desk is on the flight deck, built locally")
		check(not ZoneControl.home().is_empty() and ZoneControl.home_is_lhd(), "the client reads home from the base screen's view: the LHD")
	_say(CLIENT_DONE)
	get_tree().quit(failures)


## Taking a zone: its HQ and QRF bases down flip it; the liaison's contract; lost, it comes back;
## won, home moves to the FOB there; the save keeps it all.
func _test_take_zone() -> void:
	print("Taking a zone")
	var sites := ZoneControl.flip_sites(TAKE)
	var hq_ids := sites.filter(func(m: String) -> bool: return ZoneModules.base(String(_module(TAKE, m).type)) == "hq")
	check(sites.size() >= 2 and hq_ids.size() == 1, "%s has an HQ and QRF bases: %s" % [TAKE, ", ".join(PackedStringArray(sites))])
	if sites.is_empty():
		return
	for i in sites.size() - 1:
		ZoneControl.server_note_site_down(TAKE, sites[i])
	check(ZoneControl.control(TAKE) == ZoneControl.ENEMY and ZoneControl.progress(TAKE) == {"down": sites.size() - 1, "of": sites.size()},
		"one site short, the zone is still theirs (%d of %d down)" % [sites.size() - 1, sites.size()])
	check(not ZoneControl.server_note_site_down(TAKE, "not_a_site") and not ZoneControl.server_note_site_down(TAKE, sites[0]), "a site counts once, and only its HQ and QRF bases count")
	var flipped := ZoneControl.server_note_site_down(TAKE, sites[-1])
	check(flipped and ZoneControl.control(TAKE) == ZoneControl.COMPANY and ZoneControl.is_company(TAKE), "the last one down flips the zone to the company")
	var c := ZoneControl.seize_contract(TAKE)
	check(not c.is_empty() and String(c.get("source", "")) == ZoneControl.SEIZE_SOURCE and c in (Contracts._s().board as Array), "the liaison's seize-and-hold contract goes on the board: %s" % String(c.get("title", "none")))
	if c.is_empty():
		return
	var kinds: Array = (c.objectives as Array).map(func(o: Dictionary) -> String: return String(o.kind))
	var target := String(c.get("module_id", ""))
	check(kinds == [Objectives.CLEAR_AREA, Objectives.HOLD_POINT] and not hq_ids.is_empty() and target == String(hq_ids[0]),
		"take the HQ, then hold it through the counterattack (%s at %s)" % [", ".join(PackedStringArray(kinds)), target])
	var hold: Dictionary = (c.objectives as Array).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.HOLD_POINT)[0]
	var at: Array = _module(TAKE, target).pos
	check(Vector2(float(hold.params.pos[0]), float(hold.params.pos[2])).distance_to(Vector2(float(at[0]), float(at[1]))) < 1.0, "the position held is the HQ")
	check(ZoneControl.server_offer_seize(TAKE) == String(c.cid) and ZoneControl.seize_contract(TAKE) == c, "offered once, not twice")
	# Lost (expired here): back on the board the next day.
	(Contracts._s().board as Array).erase(c)
	Contracts.contract_closed.emit(c, "expired")
	check(ZoneControl.seize_contract(TAKE).is_empty() and int(ZoneControl._zone(TAKE).get("reoffer_day", 0)) == Economy.day() + ZoneControl.REOFFER_DAYS, "lost, it's off the board until tomorrow")
	ZoneControl.on_day_advanced(Economy.day() + 1, 1)
	var again := ZoneControl.seize_contract(TAKE)
	check(not again.is_empty() and String(again.cid) != String(c.cid), "and the liaison puts it back on the board")
	# The save keeps zone control.
	BaseHub.server_save()
	var saved_home := ZoneControl.home()
	BaseHub.load_or_new()
	check(ZoneControl.home() == saved_home and ZoneControl.control(TAKE) == ZoneControl.COMPANY and ZoneControl.progress(TAKE).down == sites.size(),
		"saved and loaded: home aboard, the zone ours, its sites down")
	again = ZoneControl.seize_contract(TAKE)
	# Won: home moves ashore.
	var cell: Vector2i = RegionMap.layout().get(TAKE, Vector2i(-99, -99))
	(Contracts._s().board as Array).erase(again)
	Contracts.contract_closed.emit(again, "completed")
	check(not ZoneControl.home_is_lhd() and ZoneControl.fob_zone() == TAKE and ZoneControl.control(TAKE) == ZoneControl.FOB, "won: the zone is the company's FOB, home moves ashore")
	check(RegionMap.layout().get(RegionMap.BASE, Vector2i(-1, -1)) == cell and not RegionMap.layout().has(TAKE), "the base takes the zone's cell on the region map")
	var info := BaseHub.base_info()
	var zone := MissionRegistry.zone(TAKE)
	check(String(info.get("level", "")) == "base_zone" and String(info.def.get("region", "")) == String(zone.region) and String(info.def.name).contains(String(zone.name)),
		"home is the base zone, on %s's ground (%s, %s)" % [TAKE, String(info.def.get("name", "")), String(info.def.get("region", ""))])
	var neighbours := RegionMap.links(RegionMap.BASE)
	check(not neighbours.is_empty() and neighbours.all(func(l: Dictionary) -> bool: return RegionMap.links(String(l.to)).any(func(b: Dictionary) -> bool: return String(b.to) == RegionMap.BASE)),
		"and the zones beside it lead home (%d)" % neighbours.size())
	# The board never sends the squad into the zone its FOB stands in.
	var kind := String(zone.get("kind", ""))
	var could := MissionRegistry.types().any(func(t: String) -> bool:
		return MissionRegistry.zones_for(MissionRegistry.type_modules(MissionRegistry.type_def(t)), kind).any(
			func(z: Dictionary) -> bool: return String(z.zone_id) == TAKE))
	(Contracts._s().board as Array).clear()
	Contracts.server_refresh_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var picks: Array = []
	for i in 200:
		picks.append(String(ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "zone_kind": kind}).zone_id))
	var board_zones: Array = (Contracts._s().board as Array).map(func(o: Dictionary) -> String: return String(o.get("zone_id", "")))
	check(could and not board_zones.is_empty() and TAKE not in board_zones and TAKE not in picks,
		"a fresh board has no offer in the FOB's zone (%d offers, 200 %s picks, none in %s)" % [board_zones.size(), kind, TAKE])
	var stash_was := BaseArmory.counts(BaseHub.stash())
	BaseHub.server_return_to_base()
	await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseZoneLevel and not BaseHub.switch_pending(), 60.0)
	var fob := CompoundLevel.current(self) as BaseZoneLevel
	check(fob != null and BaseHub.in_base(), "the squad comes home to the FOB ashore")
	if fob:
		await get_tree().create_timer(1.0).timeout
		check(BaseArmory.counts(fob.server_collect_stash()) == stash_was, "with the stash moved ashore whole")
		check(BaseHub.server_buy_defence("sensor") != BaseHub.NO_DEFENCES_ABOARD, "and defences for sale again")
	BaseHub.server_save()
	BaseHub.load_or_new()
	check(ZoneControl.fob_zone() == TAKE and not ZoneControl.home_is_lhd() and String(BaseHub.base_info().get("level", "")) == "base_zone", "saved and loaded: home is the FOB in %s" % TAKE)


## A campaign saved before zone control keeps its FOB.
func _test_old_save() -> void:
	Campaign._sections.erase(String(ZoneControl.SECTION))
	ZoneControl.server_loaded()
	check(ZoneControl.home() == ZoneControl.HOME_FOB and ZoneControl.fob_zone() == "" and RegionMap.layout().has(RegionMap.BASE),
		"an old save (no zone control) keeps its inland FOB, on the region map as before")
	check(String(BaseHub.base_info().get("level", "")) == "base_zone", "and its home is the base zone")


func _module(zone_id: String, module_id: String) -> Dictionary:
	for m: Dictionary in MissionRegistry.zone_def(zone_id).get("modules", []):
		if String(m.id) == module_id:
			return m
	return {}
