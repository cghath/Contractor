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
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
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
	var again := ZoneDef.normalize(BaseZoneLevel.def_for(Contracts.campaign_seed()))
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
	BaseHub.server_return_to_base()
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


func _cheapest(pool: Array) -> Dictionary:
	var best := {}
	for c: Dictionary in pool:
		if best.is_empty() or int(c.fee) < int(best.fee):
			best = c
	return best
