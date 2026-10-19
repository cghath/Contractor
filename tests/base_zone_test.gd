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


## The squadmate left in another zone at a crossing (_test_cross_on), and that zone.
var _left_mid := ""
var _left_zone := ""


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
	var local: Array = (base.def.modules as Array).filter(func(m: Dictionary) -> bool: return String(m.type) != "fob")
	check(local.size() == BaseZoneLevel.LOCAL_SITES.size(), "the base's local area: %s" % ", ".join(local.map(func(m: Dictionary) -> String: return String(m.id))))
	var folk := base.find_children("*", "CharacterBody3D", true, false).filter(func(n: Node) -> bool: return n is Soldier and (n as Soldier).faction == Person.FACTION)
	check(folk.size() > 0, "with villagers about (%d)" % folk.size())
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
	_test_rebel_support()
	_test_supply_line()
	_test_zone_memory()
	_test_threats()
	await _test_assault()
	await _test_defences()
	await _test_placed_defences()
	await _test_rebel_calls()
	await _test_raid_by_air()
	await _test_airframes()
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
	# The region map on the ops desk: every zone a cell, a click picks the zone under it.
	var view := RegionMapView.new()
	view.size = Vector2(900, view.custom_minimum_size.y)
	var some := String(RegionMap.links(RegionMap.BASE)[0].to)
	var picked := [""]
	view.zone_picked.connect(func(id: String) -> void: picked[0] = id)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.cell_rect(RegionMap.layout()[some]).get_center()
	view._gui_input(click)
	var rects := RegionMap.layout().values().map(func(c: Vector2i) -> Rect2: return view.cell_rect(c))
	var apart := true
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			apart = apart and not (rects[i] as Rect2).intersects(rects[j])
	check(picked[0] == some and view.selected == some and apart and view.zone_at(view.cell_rect(RegionMap.layout()[RegionMap.BASE]).get_center()) == RegionMap.BASE,
		"the ops desk's region map: each zone its own cell, a click picks it (%s)" % picked[0])
	var marks := BaseUI.region_marks({"held": [{"zone_id": "a"}], "prep": {"contract": {"zone_id": "b", "legs": [{"zone_id": "c"}]}}})
	check(marks == {"a": "held", "b": "prep", "c": "leg"}, "marking the contracts held, the one in prep and its next zone (%s)" % marks)
	view.free()


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
	# Saved while out (LZ-4, call 11): the deployment remembers where to resume, wounds and all.
	var whole := me.vitals.server_snapshot()
	me.vitals.server_hit(Vitals.UPPER_ARM_R, {"round_class": Vitals.PISTOL})
	await get_tree().create_timer(0.3).timeout
	BaseHub.server_save()
	var kept: Dictionary = (RosterDeployment.active(BaseHub.roster()).get("resume", {}) as Dictionary).get("vitals", {})
	var my_snap: Variant = str_to_var(String(kept.get("pk:" + BaseHub.player_key(1), "")))
	var before_wounds := me.vitals.wound_list().size()
	check(my_snap is Dictionary and (my_snap as Dictionary).has("model") and before_wounds > 0, "and each one's wounds (%d kept)" % kept.size())
	# What a resumed spawn does with them: onto a body, then gone from the save.
	if my_snap is Dictionary:
		BaseHub._apply_resume("pk:" + BaseHub.player_key(1), me)
		check(me.vitals.wound_list().size() == before_wounds and not kept.has("pk:" + BaseHub.player_key(1)),
			"put back on the body as they were, once (%d wounds)" % me.vitals.wound_list().size())
	me.vitals.server_restore(whole)  # (whole again for the rest of the walk)
	var resume := BaseHub.resume_info()
	check(not resume.is_empty() and String(resume.def.id) == to and String(resume.def.get("arrive", "")) == RegionMap.crossing_id(RegionMap.BASE),
		"saved out in %s, a load would resume there, at the crossing they came in by" % to)
	_test_assault_near()
	zone = await _test_cross_on(zone, to)
	if zone == null:
		return
	zone = await _test_fly_on(zone)
	if zone == null:
		return
	to = String(zone.def.id)  # (home from where they flew to)
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
	if _left_mid != "":
		var lm := BaseHub.member(_left_mid)
		var recover := Contracts.board().filter(func(c: Dictionary) -> bool: return String(c.get("recover_mid", "")) == _left_mid)
		check(String(lm.get("status", "")) == Roster.MIA and String(lm.get("mia_zone", "")) == _left_zone
			and not recover.is_empty() and String(recover[0].zone_id) == _left_zone,
			"never fetched, they're missing in %s, a recovery contract there (%s, %s)" % [_left_zone, lm.get("status", "?"), lm.get("mia_zone", "?")])
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


## Rebel support part 1 (docs/rebel_support.md): support per region, its tiers and what they
## unlock, and a civilian casualty costing it.
func _test_rebel_support() -> void:
	print("Rebel support")
	var start := RebelSupport.support("inland")
	check(is_equal_approx(start, RebelSupport.START) and RebelSupport.unlocked("inland").is_empty() and RebelSupport.region_here(self) == "inland",
		"each region starts at %d with nothing on call; the base is inland" % int(RebelSupport.START))
	RebelSupport.change("inland", 15.0, "test")
	check(RebelSupport.tier("inland") == 1 and RebelSupport.unlocked("inland") == ["lookouts"] and is_equal_approx(RebelSupport.support("coast"), RebelSupport.START),
		"at 25 inland: the Lookouts on call there, and the coast untouched")
	RebelSupport.on_civilian_casualty({"shooter_player": true})
	check(is_equal_approx(RebelSupport.support("inland"), start + 15.0 - RebelSupport.PER_CASUALTY) and RebelSupport.unlocked("inland").is_empty(),
		"a civilian our side hurt costs %d, and back under the tier (%.0f)" % [int(RebelSupport.PER_CASUALTY), RebelSupport.support("inland")])
	var v := RebelSupport.view()
	check(v.size() == 2 and int(v[1].next) == 20, "the ops desk's Locals view: both regions, the next tier (%s)" % [v])
	RebelSupport.change("inland", start - RebelSupport.support("inland"), "test reset")


## LZ-7: a supply line's cache here and its leg's in a neighbouring zone, listed from the start,
## the leg checked only once the squad is in its zone and placed there.
func _test_supply_line() -> void:
	print("Supply line (LZ-7)")
	var c := {}
	for z: Dictionary in MissionRegistry.zones():
		if String(z.get("kind", "")) != "contract":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(z.zone_id))
		var o := ContractGen.generate(rng, {"type": "supply_line", "zone_id": String(z.zone_id), "source": "safe"})
		if not (o.get("legs", []) as Array).is_empty():
			c = o
			break
	check(not c.is_empty(), "a supply line generates with a leg in a neighbouring zone")
	if c.is_empty():
		return
	var leg: Dictionary = c.legs[0]
	var linked := RegionMap.links(String(c.zone_id)).any(func(l: Dictionary) -> bool: return String(l.to) == String(leg.zone_id))
	check(linked and String(leg.zone_id) != String(c.zone_id) and String(leg.module_id) != "" and not (leg.objectives as Array).is_empty(),
		"its leg is next door, at a module of its own (%s, %s in %s)" % [c.title, leg.module_id, leg.zone_id])
	check(String(c.title).contains(String(leg.zone_name)), "and the title names both zones (%s)" % c.title)
	c["cid"] = "sl1"
	var objs := Objectives.from_contract(c)
	var pending := objs.filter(func(o: Dictionary) -> bool: return o.has("leg"))
	check(pending.size() == (leg.objectives as Array).size() and pending.all(func(o: Dictionary) -> bool:
		return o.params.get("pending", false) and (o.pos as Array).is_empty() and String(o.text).contains(String(leg.zone_name)) and o.cid == "sl1"),
		"the leg is listed from the start, with no place yet, named by its zone")
	check(Objectives.placed(objs).size() == objs.size() - pending.size() and not Objectives.placed(objs).any(func(o: Dictionary) -> bool: return o.has("leg")),
		"and only what's placed goes live at the start (no leg's HVT or convoy in the first zone)")
	var main_obj: Dictionary = objs[0]
	var fake := ZoneLevel.new()
	fake.def = {"id": String(c.zone_id), "crossings": [{}]}
	check(Objectives.here(main_obj, fake) and not Objectives.here(pending[0], fake), "in the contract's zone its cache counts, the leg's doesn't")
	var placed := Objectives.leg_objectives(c, 0, Vector3(100, 0, 0), false)
	fake.def = {"id": String(leg.zone_id), "crossings": [{}]}
	check(Objectives.here(placed[0], fake) and not Objectives.here(main_obj, fake) and String(placed[0].oid) == String(pending[0].oid),
		"walked into the leg's zone it counts there, the first cache doesn't (same objective, placed)")
	fake.free()
	# The manhunt: the intel here, the man next door (its own leg objectives).
	var hunt := {}
	for z: Dictionary in MissionRegistry.zones():
		if String(z.get("kind", "")) != "contract":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(z.zone_id) + "hunt")
		var o := ContractGen.generate(rng, {"type": "manhunt", "zone_id": String(z.zone_id), "source": "safe"})
		if not (o.get("legs", []) as Array).is_empty():
			hunt = o
			break
	var hunt_leg: Dictionary = hunt.legs[0] if not hunt.is_empty() else {}
	check(not hunt.is_empty() and String(hunt.objectives[0].kind) == Objectives.EXTRACT_ITEM
		and String((hunt_leg.objectives as Array)[0].kind) == Objectives.DELIVER_HVT and (hunt_leg.objectives[0] as Dictionary).has("person"),
		"a manhunt: the intel in %s, the man to take alive in %s" % [hunt.get("zone_name", "?"), hunt_leg.get("zone_name", "?")])
	# The convoy chase: here a bonus, the convoy next door the job (already rolling).
	var chase := {}
	for z: Dictionary in MissionRegistry.zones():
		if String(z.get("kind", "")) != "contract":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(z.zone_id) + "chase")
		var o := ContractGen.generate(rng, {"type": "convoy_chase", "zone_id": String(z.zone_id), "source": "safe"})
		if not (o.get("legs", []) as Array).is_empty():
			chase = o
			break
	var here_convoy: Array = (chase.get("objectives", []) as Array).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.CONVOY)
	var leg_convoy: Array = ((chase.legs[0].objectives if not chase.is_empty() else []) as Array).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.CONVOY)
	check(not here_convoy.is_empty() and bool(here_convoy[0].get("optional", false)) and not leg_convoy.is_empty() and not bool(leg_convoy[0].get("optional", false))
		and float(leg_convoy[0].params.depart_s) <= 90.0,
		"a convoy chase: stopping it here a bonus, the one next door the job, rolling within %.0f s" % (float(leg_convoy[0].params.depart_s) if not leg_convoy.is_empty() else -1.0))


## LZ-3, heli transport between zones: from `zone` the squad flies on to the base's other
## neighbour (BaseHub.server_fly_on, as a transport told "zone" does): the deployment goes there,
## half an hour passes, and they come in aboard a helicopter landing at its insertion LZ.
## Returns the level there (on foot again), or null.
func _test_fly_on(zone: ZoneLevel) -> ZoneLevel:
	print("Flying on to another zone (LZ-3)")
	var to := ""
	for l: Dictionary in RegionMap.links(RegionMap.BASE):
		if String(l.to) != String(zone.def.id):
			to = String(l.to)
			break
	check(to != "", "the base has another neighbour to fly to")
	if to == "":
		return null
	var me := zone.players.get_node(^"1") as Soldier
	var k := 0
	for n: Node in zone.ai.get_children():
		if n is Soldier and (n as Soldier).has_meta(&"roster_id") and not (n as Soldier).vitals.is_dead():
			(n as Soldier).global_position = me.global_position + Vector3(k * 1.5 - 1.0, 0, 1.5)  # aboard with him
			k += 1
	await get_tree().physics_frame
	var hours_before := float(RosterDeployment.active(BaseHub.roster()).get("travel_h", 0.0))
	var why := BaseHub.server_fly_on(to, Vector2(me.global_position.x, me.global_position.z))
	check(why == "", "a transport flies the squad on to %s (%s)" % [to, why])
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == to and not BaseHub.switch_pending(), 40.0)
	var there := CompoundLevel.current(self) as ZoneLevel
	var dep := RosterDeployment.active(BaseHub.roster())
	check(there != null and String(there.def.id) == to and String(dep.get("zone_id", "")) == to
		and absf(float(dep.get("travel_h", 0.0)) - hours_before - BaseHub.TRAVEL_AIR_H) < 0.01,
		"in %s, half an hour on the clock (%.1f h travelled)" % [to, float(dep.get("travel_h", 0.0))])
	if there == null:
		return null
	await _wait_until(func() -> bool: return there.players.get_node_or_null(^"1") != null, 10.0)
	me = there.players.get_node_or_null(^"1") as Soldier
	var aboard := await _wait_until(func() -> bool: return me != null and Vehicle.ride_of(me) is Helicopter, 25.0)  # (CI runs slower)
	check(aboard, "flown in aboard a helicopter to its insertion LZ")
	HeliSupports.of(there).server_dismiss_all()  # (the test walks on from here: everyone out, on the ground)
	await get_tree().create_timer(1.5).timeout
	HeliSupports.of(there).server_dismiss_all()  # (one launched late doesn't board him after all)
	await get_tree().create_timer(0.5).timeout
	if me:
		me.global_position = there.ground_point(me.global_position)
	for n: Node in there.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"roster_id"):
			s.global_position = there.ground_point(s.global_position)
	await get_tree().physics_frame
	return there


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
	# A captured HVT, cuffed and led by the player: he comes along (LZ-2).
	var layer := zone.get_node(^"People") as PeopleLayer
	var captive := layer.server_spawn_person({"name": "Person_xing_hvt", "kind": "hvt", "side": Person.HOSTILE, "label": "HVT (Crossing)",
		"pos": at + Vector3(0, 0, -2.0), "hvt_id": "xing_hvt"})
	layer.server_set_state(captive, {"cuffed": true, "surrendered": true})
	layer.server_lead(me, captive)
	# And he's at the wheel of a vehicle in the crossing: it drives on with him (LZ-2).
	var vl := zone.get_node(^"Vehicles") as VehicleLayer
	var truck := vl.server_spawn("matv", Transform3D(Basis.IDENTITY, zone.above_ground(at + Vector3(4.0, 0, 0)) + Vector3(0, 0.6, 0)))
	await get_tree().physics_frame
	truck.server_set_fuel(37.0)
	var truck_id := truck.vehicle_id
	truck.server_enter(me, 0)
	await get_tree().physics_frame
	# A helicopter lost and a cooldown running: both go on with the deployment (LZ-3).
	var helis := HeliSupports.of(zone)
	helis.server_restore_limits({"cooldown": {"resupply": 300.0}, "lost": ["transport"]})
	# A medevac helicopter on its way and an allied element out: both follow (LZ-3, call 19).
	var medevac := HeliCall.new(helis, "medevac", me, {"source": "smoke"})
	var flying := medevac.server_launch()
	if flying:
		helis.calls.append(medevac)
	var troops := AlliedTroops.current(zone)
	var allied_called := troops.server_call(me, true, "rifle") if troops else "no AlliedTroops"
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
	check(me != null and me.vitals.wound_list().size() == wounds_before and me.vitals.is_up()
		and me.vitals.blood_fraction() <= blood_before + 0.001 and me.vitals.blood_fraction() >= minf(blood_before, BaseHub.TRAVEL_BLOOD_FLOOR) - 0.05,
		"the player comes in with his wounds, bled a little on the way but up (capped): %d wound(s), %.0f%% blood (were %d, %.0f%%)" % [me.vitals.wound_list().size() if me else -1,
			(me.vitals.blood_fraction() if me else 0.0) * 100.0, wounds_before, blood_before * 100.0])
	check(me != null and me.inventory.count_of(&"burn_dressing") == dressings_before, "with what he carried (%d burn dressings)" % dressings_before)
	var came := mate_names.filter(func(n: String) -> bool: return next.ai.get_node_or_null(NodePath(n)) != null)
	check(came.size() == mate_names.size(), "and his squadmates with him (%s)" % ", ".join(came))
	var helis_next := HeliSupports.of(next)
	check(helis_next != null and helis_next.is_lost("transport") and helis_next.cooldown_left("resupply") > 200.0,
		"the lost helicopter and the cooldown come along (%.0f s left)" % (helis_next.cooldown_left("resupply") if helis_next else 0.0))
	var briefing := MapNodes.briefing(next)
	check(briefing == null or not briefing.is_open(), "no second briefing")
	# The followers, a game minute after the squad (BaseHub.FOLLOW_DELAY_S).
	await get_tree().create_timer(BaseHub.FOLLOW_DELAY_S + 3.0).timeout
	var helis_followed := HeliSupports.of(next)
	var troops2 := AlliedTroops.current(next)
	check(flying and helis_followed != null and helis_followed.active("medevac") != null,
		"the medevac helicopter on its way follows the squad over (%s)" % ("launched" if flying else "didn't launch"))
	check(allied_called == "" and troops2 != null and troops2.out().size() == 1
		and (troops2.out()[0].squad as Squad).members().any(func(s: Soldier) -> bool: return s.global_position.distance_to(me.global_position) < 60.0),
		"and the allied element out comes in where the squad did (%s, %d out)" % [allied_called, troops2.out().size() if troops2 else -1])
	var vl2 := next.get_node_or_null(^"Vehicles") as VehicleLayer
	await _wait_until(func() -> bool: return vl2 != null and vl2.find(truck_id) != null and Vehicle.ride_of(me) == vl2.find(truck_id), 6.0)
	var truck2: Vehicle = vl2.find(truck_id) if vl2 else null
	check(truck2 != null and absf(truck2.fuel - 37.0) < 0.5 and Vehicle.ride_of(me) == truck2,
		"the vehicle he drove in drives on with him, fuel as it was (%.0f l), him back at the wheel" % (truck2.fuel if truck2 else -1.0))
	check(not is_instance_valid(zone) or zone.get_node(^"Vehicles").find(truck_id) == null, "and isn't left in the zone behind")
	if truck2 and Vehicle.ride_of(me) == truck2:
		truck2.server_exit(me)
		await get_tree().physics_frame
	var layer2 := next.get_node_or_null(^"People") as PeopleLayer
	var hvt2: Soldier = layer2.hvt("xing_hvt") if layer2 else null
	check(hvt2 != null and bool(layer2.state_of(hvt2).get("cuffed", false)) and String(layer2.state_of(hvt2).get("led_by", "")) == layer2.key_of(me)
		and hvt2.global_position.distance_to(me.global_position) < 20.0,
		"the cuffed HVT he led comes along, still cuffed and following him")
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
	if hvt2:
		hvt2.global_position = at2 + Vector3(0, 0, -2.0)
	# The first squadmate stays behind in this zone (LZ-2: left at the crossing, they wait here).
	for k in came.size():
		var mate := next.ai.get_node(NodePath(came[k])) as Soldier
		mate.global_position = at2 + Vector3(k * 1.5 - 1.0, 0, 1.5) if k > 0 else next.ground_point(at2 + Vector3(0, 0, 150.0))
		if k == 0:
			_left_mid = String(mate.get_meta(&"roster_id"))
			_left_zone = next_id
			var brain := SquadAI.of(mate)
			if brain:
				brain.order = Squad.Order.HOLD
	await get_tree().physics_frame
	nx.countdown_s = 0.5
	why = nx.server_confirm(1)
	if _left_mid != "":
		check(why.begins_with("Leaving behind"), "a squadmate away from the crossing: warned first (%s)" % why)
		why = nx.server_confirm(1)
	check(why == "", "and back (%s)" % why)
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == from_id and not BaseHub.switch_pending(), 40.0)
	var again := CompoundLevel.current(self) as ZoneLevel
	check(again != null and String(again.def.id) == from_id, "back in %s" % from_id)
	if _left_mid != "":
		var away: Dictionary = RosterDeployment.active(BaseHub.roster()).get("away", {}).get(_left_mid, {})
		var callsign := String(BaseHub.member(_left_mid).callsign)
		check(String(away.get("zone_id", "")) == _left_zone and again.ai.get_node_or_null(NodePath(callsign)) == null,
			"the squadmate left at the crossing stays in %s, not with the squad (%s)" % [_left_zone, away.get("zone_id", "none")])
	var layer3 := again.get_node_or_null(^"People") as PeopleLayer if again else null
	var hvts_back: Array = layer3.people().filter(func(s: Soldier) -> bool: return String(layer3.state_of(s).get("hvt_id", "")) == "xing_hvt") if layer3 else []
	check(hvts_back.size() == 1, "and back with them, once (%d)" % hvts_back.size())
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


## LZ-3 (call 15): a support helicopter's airframe keeps its fuel and damage; badly damaged it's
## in the workshop for days, nearly dry it's refuelling for a while, and calls wait for it.
func _test_airframes() -> void:
	print("Airframes")
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var layer := base.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null:
		check(false, "the base zone has a vehicle layer")
		return
	var at := base.fob.to_global(Vector3(BaseFob.HELIPAD.get_center().x, 0.5, BaseFob.HELIPAD.get_center().y))
	var heli := layer.server_spawn(HeliSupports.MODEL, Transform3D(Basis.IDENTITY, at), "", &"player") as Vehicle
	await get_tree().physics_frame
	heli._zones[Vehicle.ZONE_HULL] = 0.3
	HeliSupports.airframe_back("resupply", heli)
	var why := HeliSupports.airframe_problem("resupply")
	check(why.contains("workshop"), "a helicopter back badly shot up goes to the workshop (%s)" % why)
	heli._zones[Vehicle.ZONE_HULL] = 1.0
	heli.fuel = float(heli.spec.get("fuel_l", 1000.0)) * 0.1
	HeliSupports.airframe_back("cargo", heli, 5.0)
	why = HeliSupports.airframe_problem("cargo")
	check(why.contains("refuelling"), "one back nearly dry is refuelling for a while (%s)" % why)
	check(float(HeliSupports.airframe("cargo").cond.fuel) >= float(heli.spec.get("fuel_l", 1.0)) * 0.99, "and comes back full")
	heli.queue_free()
	HeliSupports.airframes().clear()


## LZ-5 (call 17): heat brings the enemy to the base: patrols in the far area from 30, a probe on
## the wire from 50; none with the company quiet.
func _test_threats() -> void:
	print("Threats to the base")
	var seed := Contracts.campaign_seed()
	var heat: Dictionary = Campaign.section(&"economy").get("heat", {})
	var saved := heat.duplicate()
	heat.clear()
	check(not BaseZoneLevel.def_for(seed).has("patrols") or (BaseZoneLevel.def_for(seed).patrols as Array).is_empty(), "quiet: nobody comes near the base")
	Economy.add_heat("black_ridge", 35.0)
	var def := BaseZoneLevel.def_for(seed)
	var routes: Array = def.get("patrols", [])
	var far := routes.all(func(r: Array) -> bool: return r.all(func(p: Array) -> bool: return Vector2(float(p[0]), float(p[1])).length() >= BaseZoneLevel.QUIET_M))
	check(routes.size() == 1 and far and String(def.get("threat_faction", "")) == "black_ridge",
		"heat 35: a Black Ridge patrol roams the far base area (%d route(s))" % routes.size())
	Economy.add_heat("black_ridge", 20.0)
	routes = BaseZoneLevel.def_for(seed).get("patrols", [])
	var near := routes.any(func(r: Array) -> bool: return r.any(func(p: Array) -> bool: return Vector2(float(p[0]), float(p[1])).length() <= BaseFob.MODULE_HALF.x + BaseZoneLevel.PROBE_M))
	check(routes.size() == 3 and near, "heat 55: two patrols and a probe that comes up to the wire (%d routes)" % routes.size())
	heat.clear()
	heat.merge(saved)


## LZ-5 (calls 12, 17): heat 70+ books an assault for tomorrow; out on the day, it resolves
## off-screen (the wire's piles pay); at the base, it comes in live and is beaten off.
## LZ-5 (call 12): an assault due while the squad is out a link or two away holds out for them,
## the radio says so, and runs out into the off-screen result if nobody comes.
func _test_assault_near() -> void:
	print("Assault while out nearby")
	var near_zone := String(RegionMap.links(RegionMap.BASE)[0].to)
	check(RegionMap.distance(near_zone, RegionMap.BASE) == 1 and RegionMap.distance(RegionMap.BASE, RegionMap.BASE) == 0,
		"the region map knows how far a zone is from the base")
	var dep := RosterDeployment.active(BaseHub.roster())
	if dep.is_empty():
		return
	var was := String(dep.get("zone_id", ""))
	dep["zone_id"] = near_zone
	BaseHub.base()["assault"] = {"faction": "black_ridge", "day": BaseHub.day()}
	var said := BaseAssault.server_day_passed(false)
	var booked: Dictionary = BaseHub.base().get("assault", {})
	check(said.contains("return recommended") and float(booked.get("hold_left_s", 0.0)) > 0.0,
		"a link out, the base holds out for them and the radio says so (%s)" % said)
	var stash_piles := BaseHub.stash().size()
	BaseAssault.server_tick_out(float(booked.hold_left_s) + 1.0)
	check(not BaseHub.base().has("assault") and BaseHub.stash().size() <= stash_piles, "nobody came: it resolves off-screen")
	dep["zone_id"] = was


## LZ-6: defences placed by the players: on the grid, in the build area, clear of the pads and of
## each other; paid, and the base comes back with them.
func _test_placed_defences() -> void:
	print("Placed defences (LZ-6)")
	var owned: Array = BaseHub.base().get("defences", [])
	check(BaseFob.placement_problem("mg_pit", Vector2(200, 0), owned).contains("build area"), "outside the build area: no")
	check(BaseFob.placement_problem("mg_pit", BaseFob.HELIPAD.get_center(), owned).contains("helipad"), "on the helipad: no")
	var spot := Vector2(-48, -48)
	check(BaseFob.placement_problem("mg_pit", spot, owned) == "", "a clear cell: yes")
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_place_defence("mg_pit", spot + Vector2(3, -4))
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending() and CompoundLevel.current(self) is BaseZoneLevel, 40.0)
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var placed_mod := (base.def.modules as Array).filter(func(m: Dictionary) -> bool:
		return String(m.type) == "fob_mg_pit" and Vector2(float(m.pos[0]), float(m.pos[1])) == spot) if base else []
	check(why == "" and BaseEconomy.funds() < funds and placed_mod.size() == 1,
		"placed (snapped to the grid), paid for, and standing there when the base comes back (%s)" % why)
	check(BaseFob.placement_problem("mg_pit", spot, BaseHub.base().get("defences", [])).contains("another defence"), "and nothing else goes on top of it")
	# Vehicles from an allied quartermaster into the motor pool (wave 6 call #1: MRAPs at Trusted).
	var us0 := Economy.reputation("us_forces")
	check(BaseHub.server_buy_vehicle("matv") != "", "no M-ATV for sale before the company stands Trusted with an allied force")
	Economy.change_reputation("us_forces", 35 - us0, "test", false)
	BaseEconomy.credit(100000, "test: funds for an M-ATV")
	var pool_before := MotorPool.list().size()
	var cash0 := BaseEconomy.funds()
	var bought := BaseHub.server_buy_vehicle("matv")
	check(bought == "" and MotorPool.list().size() == pool_before + 1 and String(MotorPool.list().back().model) == "matv" and BaseEconomy.funds() < cash0,
		"Trusted with the US: an M-ATV bought into the motor pool (%s)" % bought)
	Economy.change_reputation("us_forces", us0 - Economy.reputation("us_forces"), "test cleanup", false)
	# Mortar pits count double on the wire; sensors count for nothing there but watch.
	check(BaseFob.defence_cover(["mortar_pit", "sensor", "mg_pit"]) == 3, "a mortar pit counts double, a sensor not at all (%d)" % BaseFob.defence_cover(["mortar_pit", "sensor", "mg_pit"]))
	var line := BaseFob.sensor_report(Vector3.ZERO, [Vector3(0, 0, -250), Vector3(10, 0, -240), Vector3(900, 0, 0)])
	check(line.contains("2 contacts") and line.contains("north"), "sensors report what's close, and which way (%s)" % line)
	check(BaseFob.sensor_report(Vector3.ZERO, [Vector3(900, 0, 0)]) == "", "and nothing for what's far off")


## Rebel support part 2 (RebelCalls): the call-ins, by the region's support, with cooldowns.
func _test_rebel_calls() -> void:
	print("Rebel call-ins")
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var calls := RebelCalls.of(base)
	var me := base.players.get_node_or_null(^"1") as Soldier if base else null
	check(calls != null and me != null, "every level has the rebels' call-ins")
	if calls == null or me == null:
		return
	var was := RebelSupport.support("inland")
	check(calls.server_call("lookouts", me, Vector3.INF).contains("won't"), "below the tier: the locals won't")
	RebelSupport.change("inland", 85.0 - was, "test")
	check(calls.server_call("lookouts", me, Vector3.INF) == "", "at 85 inland: the lookouts watch")
	check(calls.server_call("lookouts", me, Vector3.INF).contains("again in"), "and not again until their cooldown's out")
	var spot := me.global_position + Vector3(10, 0, 10)
	var layer := VehicleLayer.of(base)
	var before := layer.vehicles().filter(func(v: Vehicle) -> bool: return v.model == RebelCalls.VEHICLE).size()
	check(calls.server_call("vehicle_drop", me, spot) == "" and layer.vehicles().filter(func(v: Vehicle) -> bool: return v.model == RebelCalls.VEHICLE).size() == before + 1,
		"a vehicle drop leaves a technical where marked")
	check(calls.server_call("mortar", me, Vector3.INF) != "", "the mortar needs a mark")
	check(calls.server_call("mortar", me, me.global_position + Vector3(0, 0, 80)) == "" and calls._mortar.size() == RebelCalls.MORTAR_ROUNDS,
		"and with one, %d rounds on it after the warning" % RebelCalls.MORTAR_ROUNDS)
	calls._mortar.clear()
	check(calls.server_call("diversion", me, me.global_position + Vector3(0, 0, 200)) == "" and not calls._diversion.is_empty(), "a diversion opens fire where marked")
	var allies := AlliedTroops.current(base)
	var out_before := allies.out().size() if allies else 0
	var why := calls.server_call("fighters", me, Vector3.INF)
	await get_tree().create_timer(0.5).timeout
	var e: Dictionary = allies.out().back() if allies and allies.out().size() > out_before else {}
	var men: Array = (e.squad as Squad).members() if not e.is_empty() else []
	check(why == "" and men.size() == RebelCalls.FIGHTERS and men.all(func(m: Soldier) -> bool: return m.iff == &"rebel" and not Harm.is_company(m)),
		"rebel fighters come under the high command, in their own marks (never the company's: %d, %s)" % [men.size(), why])
	if allies:
		allies.server_release(me)
	RebelSupport.change("inland", was - RebelSupport.support("inland"), "test reset")


func _test_assault() -> void:
	print("Assaults on the base")
	var heat: Dictionary = Campaign.section(&"economy").get("heat", {})
	var saved := heat.duplicate()
	var base_sec := BaseHub.base()
	base_sec.erase("assault")
	base_sec.erase("last_assault_day")
	heat.clear()
	Economy.add_heat("black_ridge", 75.0)
	var warn := BaseAssault.server_day_passed(true)
	var booked: Dictionary = base_sec.get("assault", {})
	check(not booked.is_empty() and int(booked.day) == BaseHub.day() + 1 and warn.contains("tomorrow"), "heat 75: an assault on the FOB is booked for tomorrow, with a warning (%s)" % warn)
	var piles_before := BaseArmory.counts(BaseHub.stash())
	Economy.advance_days(1, "the assault check")
	var report := BaseAssault.server_day_passed(false)
	var piles_after := BaseArmory.counts(BaseHub.stash())
	check(report.contains("Situation report") and not base_sec.has("assault") and piles_after != piles_before,
		"out on the day: it resolves off-screen, a situation report, some stash lost at the wire")
	base_sec["assault"] = {"faction": "black_ridge", "day": BaseHub.day()}
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var node := base.get_node_or_null(NodePath(BaseAssault.NODE_NAME)) as BaseAssault
	node.server_check_due()
	var attackers: Array = []
	for men: Array in node.teams:
		attackers.append_array(men)
	check(attackers.size() >= 4, "at the base on the day it comes in live (%d men)" % attackers.size())
	for s: Variant in attackers:
		if is_instance_valid(s):
			(s as Soldier).vitals.server_kill()
	await _wait_until(func() -> bool: return node.teams.is_empty(), 6.0)
	check(node.teams.is_empty() and not base_sec.has("assault"), "beaten off, the booking's cleared")
	# Hired guards (LZ-6): they stand on the wire, and hold an assault off-screen.
	check(BaseHub.server_set_guards(5) != "" and BaseHub.guards() == 0, "tier 1 keeps no more than %d guards" % int(BaseFob.TIERS[1].guards))
	check(BaseHub.server_buy_defence("bunker").contains("tier 2"), "and the bunker waits for tier 2")
	check(BaseHub.server_set_company_squads(1) != "" and BaseHub.company_squads() == 0, "tier 1 keeps no company squad")
	check(BaseHub.server_upgrade_fob() == "" and BaseHub.fob_tier() == 2 and BaseHub.max_guards() == 8, "the FOB goes up to tier 2")
	check(BaseHub.server_set_company_squads(1) == "" and BaseHub.company_squads() == 1, "and keeps a company squad of its own")
	var troops := AlliedTroops.current(base)
	var me := base.players.get_node(^"1") as Soldier
	var funds := BaseEconomy.funds()
	var called := troops.server_call(me, false, "rifle", true) if troops else "no AlliedTroops"
	var company_men := base.ai.get_children().filter(func(n: Node) -> bool: return n is Soldier and String(n.name).begins_with("A") and (n as Soldier).iff == &"")
	check(called == "" and BaseEconomy.funds() == funds and company_men.size() >= 4,
		"called in from the support menu, it comes free in the company's own marks (%s, %d men)" % [called, company_men.size()])
	check(troops.server_call(me, false, "rifle", true).contains("out"), "and only as many as the company keeps")
	troops.server_release(me)
	BaseHub.server_set_guards(3)
	await get_tree().create_timer(0.5).timeout
	var posted := base.ai.get_children().filter(func(n: Node) -> bool: return n is Soldier and (n as Soldier).has_meta(&"base_guard") and not n.is_queued_for_deletion())
	check(posted.size() == 3 and posted.all(func(g: Soldier) -> bool: return base.fob.holds(g.global_position) or g.global_position.distance_to(base.fob.global_position) < 30.0),
		"three guards hired stand on the wire (%d)" % posted.size())
	BaseHub.server_set_guards(4)
	base_sec["assault"] = {"faction": "black_ridge", "day": BaseHub.day()}
	var before := BaseArmory.counts(BaseHub.stash())
	var held := BaseAssault.server_day_passed(false)
	check(held.contains("guards (4) held") and BaseArmory.counts(BaseHub.stash()) == before, "with four guards an assault while you're out costs nothing (%s)" % held)
	BaseHub.server_set_guards(0)
	heat.clear()
	heat.merge(saved)


## LZ-6: a defence bought at the ops desk goes up at its slot (the base reloads with it), paid for.
func _test_defences() -> void:
	print("Defences")
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_buy_defence("mg_pit")
	check(why == "" and BaseEconomy.funds() == funds - int(BaseFob.DEFENCES.mg_pit.price), "the MG pit is bought ($%d)" % int(BaseFob.DEFENCES.mg_pit.price))
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as BaseZoneLevel
		return BaseHub.in_base() and not BaseHub.switch_pending() and l != null and l.get_module("def_mg_pit") != null, 20.0)
	var base := CompoundLevel.current(self) as BaseZoneLevel
	var pit := base.get_module("def_mg_pit") if base else null
	var slot: Array = BaseFob.DEFENCES.mg_pit.slot
	check(pit != null and Vector2(pit.global_position.x, pit.global_position.z).distance_to(Vector2(base.fob.global_position.x + float(slot[0]), base.fob.global_position.z + float(slot[1]))) < 1.0,
		"and stands at its slot by the gate when the base is back up")
	check(BaseHub.server_buy_defence("mg_pit") == "Already built", "a second one isn't sold")
	await _wait_until(func() -> bool: return base.players.get_node_or_null(^"1") != null, 10.0)


## LZ-4: a raid by helicopter from the ops desk: any zone, the flight paid, a raid's rules.
func _test_raid_by_air() -> void:
	print("Raid by air")
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_raid_by_air("wadi_farm")
	check(why == "" and BaseEconomy.funds() == funds - int(Prices.support_price("transport")), "flying out to raid Wadi Farm, the flight paid (%s)" % why)
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == "wadi_farm" and not BaseHub.switch_pending(), 30.0)
	var dep := RosterDeployment.active(BaseHub.roster())
	check(String(dep.get("zone_kind", "")) == RosterDeployment.RAID and String(dep.get("zone_id", "")) == "wadi_farm", "a raid there")
	BaseHub.server_end_deployment([])
	await _wait_until(func() -> bool: return BaseHub.in_base() and not BaseHub.switch_pending(), 30.0)
	var home := CompoundLevel.current(self) as BaseZoneLevel
	await _wait_until(func() -> bool: return home != null and home.players.get_node_or_null(^"1") != null, 10.0)
