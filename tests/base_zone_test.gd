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
	get_tree().create_timer(560.0).timeout.connect(func() -> void:
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
	if zone == null or zone is BaseZoneLevel:
		return
	await _wait_until(func() -> bool: return zone.players.get_node_or_null(^"1") != null, 10.0)
	me = zone.players.get_node_or_null(^"1") as Soldier
	var back_c := RegionMap.crossing_of(zone.def, RegionMap.crossing_id(RegionMap.BASE))
	var at := Vector2(float(back_c.pos[0]), float(back_c.pos[1])) if not back_c.is_empty() else Vector2.INF
	check(me != null and Vector2(me.global_position.x, me.global_position.z).distance_to(at) < 25.0,
		"arriving at its crossing from the base (%.0f m from it)" % (Vector2(me.global_position.x, me.global_position.z).distance_to(at) if me else INF))
	var zx := MapNodes.extraction(zone)
	await _wait_until(func() -> bool: return zx.is_active(), 5.0)
	var home: Dictionary = {}
	for p: Dictionary in zx.points:
		if String(p.get("to", "")) == RegionMap.BASE:
			home = p
	check(not home.is_empty(), "and the way home is a crossing there (%s)" % home.get("name", "none"))
	if home.is_empty():
		return
	zx.countdown_s = 0.5
	me.global_position = zone.ground_point(Vector3(home.pos.x, 0, home.pos.y))
	await get_tree().physics_frame
	why = zx.server_confirm(1)
	check(why == "", "walking home through it (%s)" % why)
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending(), 40.0)
	base = CompoundLevel.current(self) as BaseZoneLevel
	check(base != null and not RosterDeployment.is_running(BaseHub.roster()), "back at the base zone, the deployment over")
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
