extends Node
## The base as a zone (docs/linked_zones.md LZ-1, BaseZoneLevel): a campaign hosted with the base
## zone on starts in a 2304 m zone from the campaign seed with the FOB as its "fob" module (its
## terminals, the stash on the armory floor, the muster line), nothing hostile, players inside the
## gate, loaded inside LOAD_BUDGET_MS. Only items inside the wire are stash. A deployment and the
## way back keep what lies outside the wire (the base zone's "fob" save) without doubling the stash.

const SEED := 5151
const ZONE := "test_base_zone_lz1"
## docs/linked_zones.md section 6: a contract zone under 5 s (the base zone is one).
const LOAD_BUDGET_MS := 5000.0

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel


func _ready() -> void:
	GameState.zone_id = "test_base_lz1" + tag
	Campaign.campaign_id = "test_base_lz1" + tag  # never touch a real save
	get_tree().create_timer(800.0).timeout.connect(func() -> void:
		print("BASE_ZONE TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	BaseHub.base_zone_mode = 1
	await _run()
	print("BASE_ZONE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	BaseHub.delete_test_campaign_files()
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "host_profile"
	BaseHub.new_campaign(SEED)
	for i in 2:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	Campaign.save_campaign()
	var ids := Roster.ids(BaseHub.roster())
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	check(level is BaseZoneLevel and BaseHub.in_base(), "the campaign starts at the base, a zone")
	var base := level as BaseZoneLevel
	if base == null:
		return
	check(String(base.def.id) == BaseZoneLevel.ZONE_ID and float(base.def.size_m) == BaseZoneLevel.SIZE_M and String(base.def.get("region", "")) == BaseZoneLevel.REGION,
		"2304 m, its id \"fob\", in the FOB's region (%s, %.0f m)" % [base.def.id, float(base.def.size_m)])
	check(base.generate_ms < LOAD_BUDGET_MS, "it loads within %.0f s (%.0f ms)" % [LOAD_BUDGET_MS / 1000.0, base.generate_ms])
	var again := BaseZoneLevel.def_for(Contracts.campaign_seed())
	check(again.hash() == base.def.hash(), "the same base zone from the same campaign seed")
	var m := base.get_module("fob")
	check(m != null and base.fob != null and base.fob.global_position.distance_to(m.global_position) < 0.01, "the FOB is its \"fob\" module")
	var terminals := base.fob.get_children().filter(func(n: Node) -> bool: return n is BaseTerminal)
	check(terminals.size() == BaseFob.TERMINALS.size(), "with all %d terminals in it" % terminals.size())
	var origin := Supports.origin_for(base, &"heli")
	var pad := base.fob.to_global(Vector3(BaseFob.HELIPAD.get_center().x, 0, BaseFob.HELIPAD.get_center().y))
	check(Vector2(origin.origin.x, origin.origin.z).distance_to(Vector2(pad.x, pad.z)) < 2.0,
		"support helicopters come and go from the helipad (%.0f m off it)" % Vector2(origin.origin.x, origin.origin.z).distance_to(Vector2(pad.x, pad.z)))
	var facing_ok := true
	for l: Dictionary in RegionMap.links(RegionMap.BASE):
		var side := String(BaseHub._arrive_def(MissionRegistry.zone_def(String(l.to)), String(l.to), "x").get("fob_side", ""))
		facing_ok = facing_ok and side == RegionMap.SIDE_NAMES[RegionMap.opposite(int(l.side))]
	check(facing_ok, "a zone beside the base has its supports come from the base's side")
	var me := base.players.get_node_or_null(^"1") as Soldier
	await _wait_until(func() -> bool: return base.players.get_node_or_null(^"1") != null, 5.0)
	me = base.players.get_node_or_null(^"1") as Soldier
	check(me != null and base.fob.holds(me.global_position), "the host's player stands inside the gate (%s)" % (me.global_position if me else "missing"))
	var up := await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return base.muster_soldier(mid) != null), 20.0)
	check(up and ids.all(func(mid: String) -> bool: return base.fob.holds(base.muster_soldier(mid).global_position)),
		"the company's people stand at the muster line, inside the wire")
	await get_tree().create_timer(3.0).timeout
	var hostiles := base.ai.get_children().filter(func(n: Node) -> bool: return n is Soldier and (n as Soldier).faction == &"hostile")
	check(hostiles.is_empty(), "nothing hostile in the base zone (%d)" % hostiles.size())
	var laid := BaseArmory.counts(base.server_collect_stash())
	check(laid == BaseArmory.counts(BaseHub.stash()), "the stash lies on the armory floor (%d kinds)" % laid.size())
	# Only items inside the wire are stash.
	var outside := base.fob.to_global(Vector3(0, 0.4, BaseFob.PERIMETER_HALF + 25.0))
	var inside := base.fob.to_global(BaseFob.DELIVERY + Vector3(1.0, 0.0, 2.0))
	base.server_spawn_dropped(&"ifak", 3, outside)
	base.server_spawn_dropped(&"m17", 1, inside)
	await get_tree().create_timer(0.5).timeout
	var stash_now := BaseArmory.counts(base.server_collect_stash())
	check(int(stash_now.get(&"ifak", 0)) == int(laid.get(&"ifak", 0)) and int(stash_now.get(&"m17", 0)) == int(laid.get(&"m17", 0)) + 1,
		"an item dropped outside the wire isn't stash; one inside is")
	# Out and back: the base zone keeps what lies outside the wire, and the stash isn't doubled.
	var why := BaseHub.server_deploy({"zone_id": ZONE + tag, "no_contract": true})
	check(why == "", "deploying from the base zone works as before (%s)" % why)
	await _wait_until(func() -> bool: return not BaseHub.in_base() and not BaseHub.switch_pending(), 30.0)
	check(not BaseHub.in_base(), "and the session moves to the zone")
	var stash_out := BaseArmory.counts(BaseHub.stash())
	BaseHub.server_end_deployment([])  # ended, and everyone home
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending(), 30.0)
	base = CompoundLevel.current(self) as BaseZoneLevel
	check(base != null, "back at the base zone")
	if base == null:
		return
	await get_tree().create_timer(1.0).timeout
	var outside_back := base.items.get_children().filter(func(n: Node) -> bool:
		return n is WorldItem and (n as WorldItem).item_id == &"ifak" and (n as WorldItem).global_position.distance_to(outside) < 1.5)
	check(outside_back.size() == 1, "the IFAKs dropped outside the wire are still there (%d)" % outside_back.size())
	var back := BaseArmory.counts(base.server_collect_stash())
	check(back == stash_out, "the stash came back once, not twice (%s)" % str(back.get(&"m17", 0)))
	_test_region_map()
	_test_zone_memory()
	await _test_crossings()


## LZ-2: every zone on the region grid, linked to 2-4 neighbours both ways, a crossing on the
## edge facing each.
func _test_region_map() -> void:
	print("The region map")
	var layout := RegionMap.layout()
	var zones := MissionRegistry.data().get("zones", []) as Array
	check(layout.size() == zones.size() + 1 and layout.has(RegionMap.BASE), "every zone and the base on the region grid (%d)" % layout.size())
	var counts_ok := true
	var both_ways := true
	for id: String in layout:
		var links := RegionMap.links(id)
		counts_ok = counts_ok and links.size() >= 1 and links.size() <= 4
		for l: Dictionary in links:
			both_ways = both_ways and RegionMap.links(String(l.to)).any(func(b: Dictionary) -> bool:
				return String(b.to) == id and int(b.side) == RegionMap.opposite(int(l.side)))
	check(counts_ok, "each zone links to 1-4 neighbours")
	check(both_ways, "every link runs both ways, edge to opposite edge")
	var base_def := BaseZoneLevel.def_for(Contracts.campaign_seed())
	var crossings: Array = base_def.get("crossings", [])
	var half := float(base_def.size_m) * 0.5
	var on_edge := crossings.all(func(c: Dictionary) -> bool:
		var p := Vector2(float(c.pos[0]), float(c.pos[1]))
		var side := int(c.side)
		var d: float = [p.y + half, half - p.y, p.x + half, half - p.x][side]
		return d <= ZoneDef.EDGE_POINT_IN_M + 1.0 or base_def.get("sea_side", -1) == side)
	check(crossings.size() == RegionMap.links(RegionMap.BASE).size() and crossings.size() >= 2 and on_edge,
		"the base zone has a crossing on each linked edge (%s)" % ", ".join(crossings.map(func(c: Dictionary) -> String: return String(c.name))))


## LZ-2: out of the base through a crossing into the next zone, arriving at its matching crossing;
## and back home through that zone's crossing to the base, arriving at the base's.
func _test_crossings() -> void:
	print("Crossings")
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var extraction := MapNodes.extraction(base)
	var out_point: Dictionary = {}
	for p: Dictionary in extraction.points:
		if String(p.get("source", "")) == "crossing":
			out_point = p
			break
	check(extraction.is_active() and not out_point.is_empty(), "the base zone's crossings are open (%s)" % out_point.get("name", "none"))
	if out_point.is_empty():
		return
	var to := String(out_point.to)
	var pick := BaseHub.server_pick(Roster.ids(BaseHub.roster())[0], true) if not Roster.ids(BaseHub.roster()).is_empty() else "no roster"
	check(pick == "" or pick.contains("already"), "a squadmate picked to come along (%s)" % pick)
	extraction.countdown_s = 0.5
	var me := base.players.get_node(^"1") as Soldier
	me.global_position = base.ground_point(Vector3(out_point.pos.x, 0, out_point.pos.y))
	await get_tree().physics_frame
	var why := extraction.server_confirm(1)
	check(why == "", "standing in it, the player confirms the crossing (%s)" % why)
	await _wait_until(func() -> bool: return not BaseHub.in_base() and not BaseHub.switch_pending() and CompoundLevel.current(self) is ZoneLevel, 40.0)
	var zone := CompoundLevel.current(self) as ZoneLevel
	check(zone != null and not zone is BaseZoneLevel and String(zone.def.id) == to and RosterDeployment.is_running(BaseHub.roster()),
		"the squad is in %s, on a deployment" % to)
	var dep := RosterDeployment.active(BaseHub.roster())
	check(String(dep.get("zone_kind", "")) == RosterDeployment.RAID and int(dep.get("respawns_free", 0)) == 2,
		"out without a contract it's a raid: 2 free respawns (%s, %d)" % [dep.get("zone_kind", "?"), int(dep.get("respawns_free", 0))])
	if zone == null or zone is BaseZoneLevel:
		return
	await _wait_until(func() -> bool: return zone.players.get_node_or_null(^"1") != null, 10.0)
	me = zone.players.get_node_or_null(^"1") as Soldier
	var back_c := RegionMap.crossing_of(zone.def, RegionMap.crossing_id(RegionMap.BASE))
	var at := Vector2(float(back_c.pos[0]), float(back_c.pos[1])) if not back_c.is_empty() else Vector2.INF
	check(me != null and Vector2(me.global_position.x, me.global_position.z).distance_to(at) < 25.0,
		"arriving at its crossing from the base (%.0f m from it)" % (Vector2(me.global_position.x, me.global_position.z).distance_to(at) if me else INF))
	zone = await _test_cross_on(zone, to)
	if zone == null:
		return
	me = zone.players.get_node_or_null(^"1") as Soldier
	var zx := MapNodes.extraction(zone)
	await _wait_until(func() -> bool: return zx.is_active(), 5.0)
	var home: Dictionary = {}
	for p: Dictionary in zx.points:
		if String(p.get("to", "")) == RegionMap.BASE:
			home = p
	check(not home.is_empty(), "and the way home is a crossing there (%s)" % home.get("name", "none"))
	if home.is_empty():
		return
	# What the raid hit costs standing when it comes home (LZ-4).
	var hit_dep := RosterDeployment.active(BaseHub.roster())
	hit_dep["raid_hits"] = {"black_ridge": {"kills": 20, "sites": 1}}
	var rep_before := Economy.reputation("black_ridge")
	zx.countdown_s = 0.5
	me.global_position = zone.ground_point(Vector3(home.pos.x, 0, home.pos.y))
	var k := 0
	for n: Node in zone.ai.get_children():
		if n is Soldier and (n as Soldier).has_meta(&"roster_id") and not (n as Soldier).vitals.is_dead():
			(n as Soldier).global_position = me.global_position + Vector3(k * 1.5 - 1.0, 0, 1.5)  # the squad comes home too
			k += 1
	await get_tree().physics_frame
	why = zx.server_confirm(1)
	check(why == "", "walking home through it (%s)" % why)
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending(), 40.0)
	base = CompoundLevel.current(self) as BaseZoneLevel
	check(base != null and not RosterDeployment.is_running(BaseHub.roster()), "back at the base zone, the deployment over")
	var lost := rep_before - Economy.reputation("black_ridge")
	check(lost > 0,  # (-4 for this raid; the day turning over drifts standing a little too)
		"the raid cost standing with the faction it hit (%d)" % lost)
	if base == null:
		return
	await _wait_until(func() -> bool: return base.players.get_node_or_null(^"1") != null, 10.0)
	me = base.players.get_node_or_null(^"1") as Soldier
	var mine := RegionMap.crossing_of(base.def, RegionMap.crossing_id(to))
	var at2 := Vector2(float(mine.pos[0]), float(mine.pos[1])) if not mine.is_empty() else Vector2.INF
	check(me != null and Vector2(me.global_position.x, me.global_position.z).distance_to(at2) < 25.0,
		"arriving at the base's crossing from %s, not the gate (%.0f m from it)" % [to, Vector2(me.global_position.x, me.global_position.z).distance_to(at2) if me else INF])


func _cheapest(pool: Array) -> Dictionary:
	var best := {}
	for c: Dictionary in pool:
		if best.is_empty() or int(c.fee) < int(best.fee):
			best = c
	return best


## LZ-2: on from `from_zone` into a neighbour that isn't the base and back, mid-deployment: the
## squad crosses as it is (gear and wounds), the deployment and the zone it's in move with it, no
## second briefing. Returns the level back in `from_id`.
func _test_cross_on(zone: ZoneLevel, from_id: String) -> ZoneLevel:
	print("Crossing on, zone to zone")
	var zx := MapNodes.extraction(zone)
	await _wait_until(func() -> bool: return zx.is_active(), 5.0)
	var on: Dictionary = {}
	for p: Dictionary in zx.points:
		if String(p.get("source", "")) == "crossing" and String(p.get("to", "")) != RegionMap.BASE:
			on = p
	check(not on.is_empty(), "%s has crossings on into its other neighbours (%s)" % [from_id, on.get("name", "none")])
	if on.is_empty():
		return null
	var me := zone.players.get_node(^"1") as Soldier
	var mates := zone.ai.get_children().filter(func(n: Node) -> bool: return n is Soldier and (n as Soldier).has_meta(&"roster_id") and not (n as Soldier).vitals.is_dead())
	# Hurt, with something extra on him: both come along.
	me.vitals.server_hit(Vitals.UPPER_ARM_L, {"round_class": Vitals.PISTOL})
	me.inventory.take(&"burn_dressing")
	await get_tree().create_timer(0.3).timeout
	var blood_before := me.vitals.blood_fraction()
	var wounds_before := me.vitals.wound_list().size()
	var dressings_before := me.inventory.count_of(&"burn_dressing")
	var mate_names := mates.map(func(m: Node) -> String: return String(m.name))
	var at := zone.ground_point(Vector3(on.pos.x, 0, on.pos.y))
	me.global_position = at
	for k in mates.size():
		(mates[k] as Soldier).global_position = at + Vector3(k * 1.5 - 1.0, 0, 1.5)
	await get_tree().physics_frame
	# A helicopter lost and a cooldown running: both go on with the deployment (LZ-3).
	var helis := HeliSupports.of(zone)
	helis.server_restore_limits({"cooldown": {"resupply": 300.0}, "lost": ["transport"]})
	zx.countdown_s = 0.5
	var why := zx.server_confirm(1)
	check(why == "", "everyone at the crossing on to %s confirms it (%s)" % [String(on.to), why])
	var next_id := String(on.to)
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == next_id and not BaseHub.switch_pending(), 40.0)
	var next := CompoundLevel.current(self) as ZoneLevel
	check(next != null and String(next.def.id) == next_id and RosterDeployment.is_running(BaseHub.roster())
		and String(RosterDeployment.active(BaseHub.roster()).get("zone_id", "")) == next_id,
		"the squad walks on into %s, still on the same deployment" % next_id)
	if next == null:
		return null
	await _wait_until(func() -> bool: return next.players.get_node_or_null(^"1") != null, 10.0)
	await get_tree().create_timer(1.5).timeout
	me = next.players.get_node_or_null(^"1") as Soldier
	check(me != null and me.vitals.wound_list().size() == wounds_before and absf(me.vitals.blood_fraction() - blood_before) < 0.05,
		"the player comes in as he went: %d wound(s), %.0f%% blood (were %d, %.0f%%)" % [me.vitals.wound_list().size() if me else -1,
			(me.vitals.blood_fraction() if me else 0.0) * 100.0, wounds_before, blood_before * 100.0])
	check(me != null and me.inventory.count_of(&"burn_dressing") == dressings_before, "with what he carried (%d burn dressings)" % dressings_before)
	var came := mate_names.filter(func(n: String) -> bool: return next.ai.get_node_or_null(NodePath(n)) != null)
	check(came.size() == mate_names.size(), "and his squadmates with him (%s)" % ", ".join(came))
	var helis_next := HeliSupports.of(next)
	check(helis_next != null and helis_next.is_lost("transport") and helis_next.cooldown_left("resupply") > 200.0,
		"the lost helicopter and the cooldown come along (%.0f s left)" % (helis_next.cooldown_left("resupply") if helis_next else 0.0))
	var briefing := MapNodes.briefing(next)
	check(briefing == null or not briefing.is_open(), "no second briefing")
	# And back the way they came.
	var nx := MapNodes.extraction(next)
	await _wait_until(func() -> bool: return nx.is_active(), 5.0)
	var back := {}
	for p: Dictionary in nx.points:
		if String(p.get("to", "")) == from_id:
			back = p
	check(not back.is_empty(), "the crossing back to %s is there" % from_id)
	if back.is_empty():
		return null
	var at2 := next.ground_point(Vector3(back.pos.x, 0, back.pos.y))
	me.global_position = at2
	for k in came.size():
		(next.ai.get_node(NodePath(came[k])) as Soldier).global_position = at2 + Vector3(k * 1.5 - 1.0, 0, 1.5)
	await get_tree().physics_frame
	nx.countdown_s = 0.5
	why = nx.server_confirm(1)
	check(why == "", "and back (%s)" % why)
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == from_id and not BaseHub.switch_pending(), 40.0)
	var again := CompoundLevel.current(self) as ZoneLevel
	check(again != null and String(again.def.id) == from_id, "back in %s" % from_id)
	await _wait_until(func() -> bool: return again != null and again.players.get_node_or_null(^"1") != null, 10.0)
	return again


## LZ-2 zone memory (call 5): a zone left a day ago comes back as it was; after ZONE_LOOSE_DAYS
## without its bodies and loose gear; after ZONE_FRESH_DAYS fresh (the save set aside, kept).
func _test_zone_memory() -> void:
	print("Zone memory")
	BaseHub.server_advance_days(10, "the zone memory checks")  # (days to look back over)
	var zid := "test_lz2_memory" + tag
	var path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id(zid)]
	var write := func(age: int) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"version": 1, "looted": [], "dropped": {}, "voxel_edits": [], "bodies": [], "fallen_posts": [],
			"vehicles": [], "left_day": BaseHub.day() - age}))
		f.close()
	write.call(1)
	BaseHub._fade_zone_save(zid)
	check(FileAccess.file_exists(path) and not GameState.fade_loose, "a zone left a day ago is remembered as it was")
	write.call(BaseHub.ZONE_LOOSE_DAYS + 1)
	BaseHub._fade_zone_save(zid)
	check(FileAccess.file_exists(path) and GameState.fade_loose, "after %d days its bodies and loose gear are gone" % (BaseHub.ZONE_LOOSE_DAYS + 1))
	write.call(BaseHub.ZONE_FRESH_DAYS + 1)
	BaseHub._fade_zone_save(zid)
	check(not FileAccess.file_exists(path) and not GameState.kept_copies(path).is_empty(), "after %d days it's fresh, its save kept aside" % (BaseHub.ZONE_FRESH_DAYS + 1))
	GameState.fade_loose = false
