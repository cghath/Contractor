extends Node
## Headless end-to-end check of the contract loop's payoff half, through the real code paths
## (the playtest triage, 2026-10-13: no contract had ever been completed in a playtest, so
## objective -> extraction -> debrief -> salvage, pay, roster experience, MIA, recovery and the
## medbay were unexercised by players):
##   <voxel godot exe> --headless --path . res://tests/loop_test.tscn
## A campaign hosted as the main menu's Campaign button does, at the base hub. For each mission
## type (intel grab, raid, recovery, HVT capture, hostage rescue): an offer taken from the board,
## the prep (squad picked, kit taken from the armory), deploy into the contract's zone, the
## briefing (everyone ready, start), the objective done through the game's own calls (items
## picked up, a charge set, an HVT cornered, cuffed, searched and led, a hostage led, a
## squadmate found), the squad at a landing zone, extraction confirmed, and back at the base
## the debrief checked: the pay in the bank, objectives marked done, salvage picked and in the
## stash, what was set down at the point in the stash, experience for those who came back, a
## burned squadmate sitting out and treated in the medbay, one left behind MIA with a recovery
## contract on the board, and that recovery bringing them home. Hostiles are killed by hits as
## they spawn (the fight isn't what this suite tests). Before the session: what the board's
## guaranteed safe offer (settings.safe_offers) is. Exits with the number of failures.

const SEED := 5151
## The order the missions run in: the recovery right after the raid that leaves someone behind
## (its offer runs recovery_offer_days).
## "heli": an intel grab flown in and out by the UH-60 (the staged insertion and helicopter
## extraction, design doc "Missions"): the briefing's helicopter insertion, its LZ in dead ground
## 200-450 m from the objective, the squad seated aboard, flown in low, landed and out; the
## intel taken; a squadmate knocked down and carried; the extraction called "near us", its first
## LZ made hot by an enemy in sight of it (it waves off and picks another, as the radio says);
## the casualty carried aboard, a dead hostile set by the door and a rifle set down in the
## point loaded, a second body left in the point; lifting off ends the deployment; the debrief
## pays, banks what was aboard and offers only what stayed on the ground as salvage.
const ORDER: Array[String] = ["intel_grab", "raid", "recovery", "hvt_capture", "hostage_rescue", "heli"]
const HIRES := 6
## The heli mission's flights run this much faster (Helicopter.pace), so it fits the suite's time.
const HELI_PACE := 3.0

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var player: Soldier
## Mission type -> "completed end to end" or what broke.
var results := {}
var _team: Array[String] = []  # hired member ids
var _mia := ""                  # the member left behind on the raid
var _failures_at_start := 0
## The launch watch (CI run 38666966001: the player was 1420 m up at the hostage rescue's
## landing zone, a moment after being put on the ground there): anyone in a zone, outside a
## vehicle, higher than LAUNCH_M above the ground at any tick is a body thrown or put where
## nobody can be. The first time each one is, by instance id -> what was seen.
const LAUNCH_M := 50.0
var _launched := {}
## Each body's position on the tick before (instance id -> Vector3): a launch or a teleport.
var _last_at := {}
var _mission_type := ""
var _trace_n := 0  # TEMP trace
var _ring: Array[String] = []
var _ring_done := false


func _ready() -> void:
	GameState.zone_id = "test_loop" + tag
	Campaign.campaign_id = "test_loop" + tag  # never touch a real save
	get_tree().create_timer(450.0).timeout.connect(func() -> void:
		print("LOOP TEST FAILED (timed out)")
		_cleanup()
		get_tree().quit(99))
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()  # whatever a run cut short left behind
	_test_safe_offer()
	await _start_campaign()
	if level is BaseLevel:
		await _kit_up()
		var only := OS.get_environment("CONTRACTOR_LOOP_ONLY")  # while iterating: "heli" runs only that mission
		for type in ORDER:
			if only != "" and type not in only.split(","):
				continue
			_failures_at_start = failures
			var launched_before := _launched.size()
			var why: String = await _mission(type)
			var thrown: Array = _launched.values().slice(launched_before)
			check(thrown.is_empty(), "%s: nobody outside a vehicle was ever more than %d m above the ground (%s)" % [
				type, int(LAUNCH_M), "; ".join(PackedStringArray(thrown)) if not thrown.is_empty() else "none"])
			if why == "" and failures > _failures_at_start:
				why = "%d check(s) failed" % (failures - _failures_at_start)
			results[type] = "completed end to end" if why == "" else why
			if not CompoundLevel.current(self) is BaseLevel:
				break  # stuck in a zone: nothing after this can run
	print("End to end, by mission type:")
	for type in ORDER:
		print("  %s: %s" % [type, results.get(type, "not run")])
	_cleanup()
	print("LOOP TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## The launch watch, every physics tick in a zone: everyone outside a vehicle, up or down.
func _physics_process(_delta: float) -> void:
	var zone: ZoneLevel = level as ZoneLevel if is_instance_valid(level) else null
	if zone == null or not zone.is_inside_tree() or zone.terrain == null:
		_last_at.clear()
		return
	_trace_n += 1  # TEMP trace
	if _trace_n % 30 == 0 and is_instance_valid(player):
		var p := player.global_position
		print("    TRACE %s t%d player (%.1f, %.1f, %.1f) ground %.1f vel %s veh %s" % [_mission_type, _trace_n, p.x, p.y, p.z, zone.ground_height(p.x, p.z), player.velocity, is_instance_valid(player.vehicle)])
	if is_instance_valid(player):  # TEMP trace
		var col := player.get_last_slide_collision()
		var fl: Variant = col.get_collider() if col else null
		_ring.append("t%d pos %s vel %s floor %s plat %s col %s rv %s" % [_trace_n, player.global_position, player.velocity, player.is_on_floor(), player.get_platform_velocity(),
			(fl as Node).get_path() if fl is Node else str(fl), col.get_collider_velocity() if col else Vector3.ZERO])
		if _ring.size() > 40:
			_ring.remove_at(0)
		if player.global_position.y - zone.ground_height(player.global_position.x, player.global_position.z) > LAUNCH_M and not _ring_done:
			_ring_done = true
			print("    TRACE RING:
      " + "
      ".join(PackedStringArray(_ring)))
	for group in [&"combatants", Soldier.DEAD_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var s := node as Soldier
			if s == null or s.is_queued_for_deletion():
				continue
			var key := s.get_instance_id()
			var at := s.global_position
			var before: Vector3 = _last_at.get(key, at)
			_last_at[key] = at
			if is_instance_valid(s.vehicle) or _launched.has(key):
				continue
			var above := at.y - zone.ground_height(at.x, at.z)
			if above > LAUNCH_M:
				_launched[key] = "%s %.0f m above the ground at (%.0f, %.1f, %.0f) in %s (the tick before at (%.0f, %.1f, %.0f), velocity %s%s)" % [
					s.log_name(), above, at.x, at.y, at.z, _mission_type, before.x, before.y, before.z, s.velocity,
					", ragdoll" if is_instance_valid(s.ragdoll) else ""]
				if s == player:  # TEMP trace
					_launched[key] += " NEAR " + _near_dump(before) + " RING " + " | ".join(PackedStringArray(_ring.slice(-14)))
				print("  [info] launched: %s" % _launched[key])


func _near_dump(at: Vector3) -> String:  # TEMP trace
	var shape := SphereShape3D.new()
	shape.radius = 3.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at + Vector3.UP)
	q.collision_mask = 0xFFFFFFFF
	var out := PackedStringArray()
	for hit: Dictionary in level.get_world_3d().direct_space_state.intersect_shape(q, 24):
		var c: Object = hit.collider
		var v := (c as RigidBody3D).linear_velocity if c is RigidBody3D else Vector3.ZERO
		out.append("%s[%s] at %s v %s" % [(c as Node).get_path() if c is Node else str(c), c.get_class() if c else "?", (c as Node3D).global_position if c is Node3D else Vector3.ZERO, v])
	return ", ".join(out)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func info(what: String) -> void:
	print("  [info] %s" % what)


func _cleanup() -> void:
	Contracts.auto_show_debrief = true
	BaseHub.delete_test_campaign_files()  # the game only sets saves aside: a test deletes its own
	GameState.zone_id = "test_loop" + tag
	GameState.delete_save()


# --- The safe offer -----------------------------------------------------------------------------

## What the board's guaranteed low-risk offer is (Contracts.server_refresh_board puts one on
## whenever none is left; settings.safe_offers counts them for ContractGen.generate_board), and
## how far its target sits from the zone's default insertion point.
func _test_safe_offer() -> void:
	print("The safe offer (settings.safe_offers = %d)" % MissionRegistry.setting_i("safe_offers", -1))
	Contracts.new_full_campaign(SEED)
	var safes: Array = Contracts.board().filter(func(c: Dictionary) -> bool: return c.source == "safe")
	check(safes.size() == 1, "today's board holds one safe offer (%d of %d offers)" % [safes.size(), Contracts.board().size()])
	if safes.is_empty():
		return
	var c := Contracts.contract(String(safes[0].cid))
	var def := MissionRegistry.type_def(String(c.type))
	check(int(c.true_rating) == 1 and int(c.rated) == 1 and (c.threats as Array).is_empty() and not bool(c.understated)
		and int(c.enemy_count) == int((def.enemy_count as Array)[0]) and is_equal_approx(float(c.intel_accuracy), 0.95)
		and c.zone_kind == "contract" and c.clawback == ContractGen.FULL_CLAWBACK,
		"it is low-risk: rated 1, the type's fewest enemies (%d) at its lowest quality, no threats, 95%% intel, a contract zone, advance returned if voided (%s)" % [int(c.enemy_count), c.title])
	# Over many boards: what type, how far from insertion, on the clock or not.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var dists: Array[float] = []
	var nearest: Array[float] = []
	var types := {}
	var timed := 0
	for i in 300:
		var s := ContractGen.generate(rng, {"day": 1, "source": "safe"})
		types[s.type] = int(types.get(s.type, 0)) + 1
		if int(def_limit(String(s.type))) > 0:
			timed += 1
		var layout := MissionRegistry.zone_def(String(s.zone_id))
		var points: Array = layout.get("insertion", [])
		for m: Dictionary in layout.get("modules", []):
			if String(m.id) != String(s.module_id) or points.is_empty():
				continue
			var at := Vector2(float(m.pos[0]), float(m.pos[1]))
			var first: Array = points[0]
			dists.append(at.distance_to(Vector2(float(first[0]), float(first[1]))))
			var best := INF
			for p: Array in points:
				best = minf(best, at.distance_to(Vector2(float(p[0]), float(p[1]))))
			nearest.append(best)
	info("300 safe offers: types %s; %d on the clock (HVT capture 90 min, hostage rescue 75 min)" % [types, timed])
	for pair: Array in [["the default insertion", dists], ["the nearest insertion point (picked at the briefing)", nearest]]:
		var d: Array[float] = pair[1]
		d.sort()
		if not d.is_empty():
			info("target to %s: min %.0f m, median %.0f m, max %.0f m; within 300 m: %d of %d" % [
				pair[0], d[0], d[d.size() / 2], d[-1], d.filter(func(x: float) -> bool: return x <= 300.0).size(), d.size()])
	info("the safe offer is never placed by distance: any type, any contract zone, any module of its type (ContractGen.generate/mission_target)")


static func def_limit(type: String) -> int:
	return int(MissionRegistry.type_def(type).get("time_limit_min", 0))


# --- The campaign session ----------------------------------------------------------------------

## A new campaign with HIRES people, hosted as the main menu's Campaign button does.
func _start_campaign() -> void:
	print("A campaign at the base")
	CompoundLevel.spawn_ai = true
	PeopleLayer.populate = true  # as in play (the menu turns them on outside headless runs)
	PeopleLayer.surrender_enabled = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "loop_host"
	BaseHub.new_campaign(SEED)
	Contracts.new_campaign(SEED)  # the same board every run
	for i in HIRES:
		var pool := Hiring.pool(BaseHub.hiring(), BaseHub.day())
		var cheapest := {}
		for c: Dictionary in pool:
			if cheapest.is_empty() or int(c.fee) < int(cheapest.fee):
				cheapest = c
		if not cheapest.is_empty():
			BaseHub.server_hire(String(cheapest.cid))
	_team = Roster.ids(BaseHub.roster())
	Campaign.save_campaign()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu._campaign_host()
	level = CompoundLevel.current(self)
	check(level is BaseLevel and Net.is_hosting() and _team.size() == HIRES, "hosted at the base hub with %d hired" % _team.size())
	if level is BaseLevel:
		await _wait_until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
		player = level.players.get_node_or_null(^"1")
		await _seconds(1.0)
		var people: Array = level.people.people() if level.people else []
		check(people.is_empty(), "nobody but the company at the hub: no placeholder civilians, HVT or hostage (%s)" % ", ".join(PackedStringArray(
			people.map(func(s: Soldier) -> String: return s.display_name()))))


## The player kits up at the armory: a carrier, a pack and a rifle from the stash, and a breaching charge and zip
## cuffs bought at the shop (they're delivered to the armory counter).
func _kit_up() -> void:
	print("Kitting up at the base")
	info("the player starts with: %s" % _kit_text(player))
	var charges := player.inventory.count_of(Objectives.CHARGE_ITEM)
	var cuffs := player.inventory.count_of(Person.ZIP_CUFFS)
	check(BaseHub.server_buy(Objectives.CHARGE_ITEM, 1) == "" and BaseHub.server_buy(Person.ZIP_CUFFS, 2) == "",
		"the shop sells a breaching charge and zip cuffs")
	await _frames(3)
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1", Objectives.CHARGE_ITEM, Person.ZIP_CUFFS]:
		var item := _world_item(id)
		if item == null:
			check(false, "%s lies in the armory" % id)
			continue
		player.global_position = item.global_position + Vector3(0.6, 0, 0)
		await _frames(2)
		player._server_interact.rpc_id(1, item.get_path())
		await _frames(3)
	check(player.inventory.slots[&"primary"] == &"m4a1" and player.inventory.count_of(Objectives.CHARGE_ITEM) == charges + 1
		and player.inventory.count_of(Person.ZIP_CUFFS) == cuffs + 2, "the player takes a rifle, the charge and the cuffs from the armory (%s)" % _kit_text(player))
	await _seconds(BaseHub.STASH_POLL_S + 0.3)


func _world_item(id: StringName) -> WorldItem:
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == id and not n.is_queued_for_deletion():
			return n
	return null


# --- One mission, the whole loop ----------------------------------------------------------------

## Runs mission `type` through the loop. Returns "" or what broke.
func _mission(type: String) -> String:
	print("Mission: %s" % type)
	_mission_type = type
	var heli := type == "heli"
	var squad := _squad_for(type)
	if squad.is_empty():
		return "no squad to send"
	if heli:
		type = "intel_grab"
	var cid := _take_offer(type)
	if cid == "":
		return "no offer taken from the board"
	var c := Contracts.contract(cid)
	var title := String(c.title)
	if not await _deploy(cid, squad, heli):
		return "the deployment didn't start"
	if heli and not await _heli_insert(squad):
		return "the helicopter insertion"
	var mates := {}
	for mid in squad:
		mates[mid] = _roster_soldier(mid)
	var xp_before := {}
	for mid in squad:
		xp_before[mid] = int(BaseHub.member(mid).get("xp", 0))
	# The objective, through the game's own calls.
	var done := {}
	match type:
		"intel_grab":
			done = await _do_intel(cid)
		"raid":
			done = await _do_raid(cid)
		"hvt_capture":
			done = await _do_hvt(cid)
		"hostage_rescue":
			done = await _do_hostage(cid)
		"recovery":
			done = await _do_recovery(cid)
	if not done.get("ok", false):
		return "the objective: %s" % done.get("why", "not done")
	# Who comes out how.
	var wounded := ""
	var left := ""
	var bring: Array = squad.duplicate()
	var casualty := ""
	if heli:
		casualty = squad[1]
		bring.erase(casualty)  # back wounded: checked on its own below
	elif type == "intel_grab":
		wounded = squad[1]
		(mates[wounded] as Soldier).vitals.shielded = false  # (_shield: this one's meant)
		(mates[wounded] as Soldier).vitals.server_burn(0.3)  # caught in a fire: burns sit them out
	if type == "raid":
		left = squad[squad.size() - 1]
		bring.erase(left)
	var deposit := type == "raid" or heli  # the rifle set down at the point goes to the stash
	# B-18: the HVT's phone goes out in the hold of the pool's M-ATV, not on the player.
	var stow: Array = [&"intel_phone"] if type == "hvt_capture" else []
	var cash_before := Economy.cash()
	var stash_before := BaseArmory.counts(BaseHub.stash())
	var bills := [0]
	var on_week := func(_week: int, bill: Dictionary) -> void: bills[0] += int(bill.total) - int(bill.get("loan_taken", 0))
	Economy.week_paid.connect(on_week)
	var out: Dictionary
	if heli:
		out = await _extract_heli(squad, casualty)
	else:
		out = await _extract(bring, done.get("cargo", []), left, deposit, stow)
	Economy.week_paid.disconnect(on_week)
	if not out.get("ok", false):
		return "extraction: %s" % out.get("why", "")
	if heli:
		var m := BaseHub.member(casualty)
		check(String(m.get("status", "")) not in [Roster.MIA, ""] and int(m.get("xp", 0)) == int(xp_before[casualty]) + Roster.XP_PER_MISSION,
			"%s, carried aboard down, came home with the squad (%s, %d experience)" % [m.get("callsign", "?"), Roster.status_text(m), int(m.get("xp", 0))])
		var left_body := String(out.get("left_body", ""))
		var bodies_out: Array = (out.get("bodies", []) as Array).map(func(b: Dictionary) -> String: return String(b.get("uid", "")))
		check(left_body != "" and left_body not in bodies_out and not bodies_out.is_empty(),  # ("none": only one body)
			"the body left lying in the point didn't come out (only the one aboard is banked: %d)" % bodies_out.size())
	# The debrief.
	var debrief := Contracts.last_debrief()
	var lines: Array = (debrief.get("contracts", []) as Array).filter(func(l: Dictionary) -> bool: return l.cid == cid)
	var line: Dictionary = lines[0] if not lines.is_empty() else {}
	check(String(line.get("outcome", "")) == "completed", "the debrief: %s %s" % [title, String(line.get("outcome", "missing")).to_upper()])
	var objectives: Array = line.get("objectives", [])
	var required: Array = (c.objectives as Array).filter(func(o: Dictionary) -> bool: return not o.get("optional", false))
	var marked := objectives.filter(func(l: String) -> bool: return l.begins_with("[x]")).size()
	check(not objectives.is_empty() and marked >= required.size() and objectives.slice(0, required.size()).all(func(l: String) -> bool: return l.begins_with("[x]")),
		"objectives marked done: %s" % " | ".join(PackedStringArray(objectives)))
	var pay := int(line.get("pay", 0))
	var ledger_has := Economy.ledger().any(func(e: Dictionary) -> bool: return String(e.what) == "Completion: %s" % title and int(e.amount) == pay)
	if type == "recovery":
		check(pay == 0 and int(c.base_pay) == 0, "the company's own job pays nothing")
	else:
		check(pay > 0 and ledger_has, "pay credited: $%s (completion $%s + bonuses %s), in the ledger" % [
			DebriefCalc.money(pay), DebriefCalc.money(line.get("completion", 0)), (line.get("bonuses", []) as Array).map(func(b: Dictionary) -> String: return "%s $%s" % [b.text, DebriefCalc.money(b.amount)])])
	check(Economy.cash() == cash_before + int(debrief.totals.paid_now) - bills[0],
		"the bank moved by what the debrief paid ($%s, bills $%s)" % [DebriefCalc.money(debrief.totals.paid_now), DebriefCalc.money(bills[0])])
	check(Contracts.history().any(func(h: Dictionary) -> bool: return h.cid == cid and h.outcome == "completed"), "the contract closes as completed in the history")
	if not stow.is_empty():
		var pool_id := String(out.get("pool_id", ""))
		var aboard: Array = []
		for list: Variant in (((MotorPool.entry(pool_id).get("record", {}) as Dictionary).get("cargo", {}) as Dictionary).get("containers", {}) as Dictionary).values():
			for e: Dictionary in list:
				aboard.append(String(e.id))
		var counts := BaseArmory.counts(BaseHub.stash())
		check(bool(out.get("stowed", false)) and (line.get("bonuses", []) as Array).any(func(b: Dictionary) -> bool: return String(b.text).contains("phone"))
			and pool_id != "" and String(MotorPool.entry(pool_id).get("out", "?")) == "" and "intel_phone" in aboard
			and int(counts.get("intel_phone", 0)) == int(stash_before.get("intel_phone", 0)),
			"the phone driven out in the M-ATV's hold counts for the bonus; the M-ATV is home with it aboard, not banked as well (B-18; aboard %s)" % [aboard])
	# The roster.
	var grew := true
	for mid in bring:
		var m := BaseHub.member(mid)
		grew = grew and int(m.get("xp", 0)) == int(xp_before[mid]) + Roster.XP_PER_MISSION and String(m.status) == Roster.READY
	check(grew, "everyone who came back gains %d experience (%s)" % [Roster.XP_PER_MISSION, ", ".join(PackedStringArray(bring.map(func(mid: String) -> String:
		return "%s %d" % [BaseHub.member(mid).callsign, int(BaseHub.member(mid).get("xp", 0))])))])
	if wounded != "":
		var m := BaseHub.member(wounded)
		var days := int(m.get("sit_out_days", 0))
		check(days > 0 and not Roster.is_available(m) and "burns" in (m.get("injuries", []) as Array),
			"%s came back burned and sits out %d days (%s)" % [m.callsign, days, Roster.status_text(m)])
		var quote := Roster.medbay_quote(m)
		var funds := BaseEconomy.funds()
		var why := BaseHub.server_medbay(wounded)
		check(why == "" and not quote.is_empty() and int(m.sit_out_days) == days - int(quote.days_saved) and BaseEconomy.funds() == funds - int(quote.cost),
			"the medbay treats them: %d days sooner for $%d (%s)" % [int(quote.get("days_saved", 0)), int(quote.get("cost", 0)), why])
	if left != "":
		var m := BaseHub.member(left)
		var recovery: Array = Contracts.board().filter(func(o: Dictionary) -> bool: return String(o.get("recover_mid", "")) == left)
		check(String(m.status) == Roster.MIA and not recovery.is_empty(),
			"%s, left behind alive, is MIA and a recovery contract is on the board (%s)" % [m.callsign, recovery[0].title if not recovery.is_empty() else "none"])
		_mia = left
	if type == "recovery":
		var m := BaseHub.member(String(c.get("recover_mid", "")))
		check(String(m.get("status", "")) == Roster.READY and not m.has("mia_zone"), "%s is back on the roster" % m.get("callsign", "?"))
	# Loot set down at the point, and salvage.
	if deposit:
		var deposited: Array = out.get("deposited", [])
		var bodies: Array = out.get("bodies", [])
		var back := BaseArmory.counts(BaseHub.stash())
		var expected := stash_before.duplicate()
		expected["m4a1"] = int(expected.get("m4a1", 0)) + 1
		var body_items: Dictionary = out.get("body_items", {})
		for id: String in body_items:
			expected[id] = int(expected.get(id, 0)) + int(body_items[id])
		var banked := expected.keys().all(func(id: String) -> bool: return int(back.get(id, 0)) >= int(expected[id]))
		check(not deposited.is_empty() and not bodies.is_empty() and banked,
			"the rifle set down inside the point and the dead hostile brought there are banked in the stash (M4A1 %d -> %d; the body's %s)" % [
				int(stash_before.get("m4a1", 0)), int(back.get("m4a1", 0)), body_items])
	# Salvage is what was left in the field, never what came out.
	var pool_counts := {}
	for e: Dictionary in debrief.salvage.pool:
		pool_counts[String(e.id)] = int(pool_counts.get(String(e.id), 0)) + int(e.count)
	var field: Dictionary = out.get("field", {})
	var extra := pool_counts.keys().filter(func(id: String) -> bool: return int(pool_counts[id]) > int(field.get(id, 0)))
	check(extra.is_empty(), "the salvage pool is only what was left in the field (%s)" % (
		"%d kinds" % pool_counts.size() if extra.is_empty() else ", ".join(PackedStringArray(extra.map(func(id: String) -> String:
			return "%s: %d in the pool, %d in the field" % [id, int(pool_counts[id]), int(field.get(id, 0))])))))
	if deposit:
		var zone_save: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id(String(c.zone_id))]))
		var lz: Vector2 = out.get("lz", Vector2.ZERO)
		var left_there := 0
		var body_uids: Array = (out.get("bodies", []) as Array).map(func(b: Dictionary) -> String: return String(b.get("uid", "")))
		if zone_save is Dictionary:
			for uid: String in (zone_save.get("dropped", {}) as Dictionary):
				var d: Dictionary = zone_save.dropped[uid]
				if Vector2(float(d.pos[0]), float(d.pos[2])).distance_to(lz) <= Extraction.RADIUS_M:
					left_there += 1
			for b: Dictionary in zone_save.get("bodies", []):
				if String(b.get("uid", "")) in body_uids:
					left_there += 1
		check(zone_save is Dictionary and left_there == 0,
			"and they're gone from the zone: its save keeps nothing that was banked (%d still there)" % left_there)
	await _salvage(debrief)
	return ""


## A refused confirm on a slow CI runner (CI run 38661497369: "Waiting for: Player 1" at LZ 3,
## passing locally) said nothing of where anyone was: where each one required stands from `lz`,
## and the points shown, so the [FAIL] line itself tells.
func _where_all(extraction: Extraction, lz: Vector2) -> String:
	var need := extraction.required()
	var out := PackedStringArray()
	for s: Soldier in need.players + need.ai:
		var at := s.body_point()
		out.append("%s %.1f m off at (%.0f, %.1f, %.0f)%s%s%s%s" % [Extraction._soldier_name(s), Vector2(at.x, at.z).distance_to(lz), at.x, at.y, at.z,
			"" if s.is_ai() or s == player else " (not the test's player)", " aboard" if is_instance_valid(s.vehicle) else "",
			" ragdoll" if is_instance_valid(s.ragdoll) else "", "" if s.vitals.is_up() else " down"])
	var shown := PackedStringArray(extraction.shown_points().map(func(p: Dictionary) -> String:
		return "%s %.0f m off" % [p.name, (p.pos as Vector2).distance_to(lz)]))
	return "; %s; shown: %s; heli point %d" % [", ".join(out), ", ".join(shown), extraction.heli_point]


## Member ids for `type`'s squad (who's available).
func _squad_for(type: String) -> Array:
	var ready: Array = _team.filter(func(mid: String) -> bool: return Roster.is_available(BaseHub.member(mid)))
	var want := {"intel_grab": 2, "raid": 3, "recovery": 1, "hvt_capture": 2, "hostage_rescue": 2, "heli": 3}
	return ready.slice(0, mini(int(want.get(type, 2)), ready.size()))


## Takes an offer of `type` (a contract zone) from the board: today's if there is one, else one
## put there the way the faction war posts jobs (Contracts.server_add_offer); a recovery is the
## one the raid left. Accepted on standard terms. Returns its id, or "".
func _take_offer(type: String) -> String:
	var offer := {}
	for c: Dictionary in Contracts.board():
		if (type == "recovery" and String(c.get("recover_mid", "")) == _mia and _mia != "") \
				or (type != "recovery" and c.type == type and c.zone_kind == "contract" and c.source in ["board", "safe"]):
			offer = c
			break
	if offer.is_empty() and type != "recovery":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([SEED, type])
		var cid := Contracts.server_add_offer(ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": type, "zone_kind": "contract"}))
		offer = Contracts.contract(cid)
		info("no %s on today's board: one posted to it (%s)" % [type, offer.title])
	if offer.is_empty():
		check(false, "a %s offer on the board" % type)
		return ""
	var cid := String(offer.cid)
	var advance_cash := Economy.cash()
	var why := Contracts.server_accept(cid, ContractGen.default_terms())
	var c := Contracts.contract(cid)
	check(why == "" and c.get("state") == Contracts.ACCEPTED and Economy.cash() == advance_cash + int(c.deal.advance),
		"taken from the board: %s (%s, %s, advance $%s)" % [c.title, c.zone_name, c.get("module_name", ""), DebriefCalc.money(c.deal.advance)])
	return cid if why == "" else ""


## Prep, deploy, the briefing and its start. Returns whether the contract is live with the squad up.
func _deploy(cid: String, squad: Array, heli := false) -> bool:
	check(String(BaseHub.prep_contract().get("cid", "")) == cid, "accepting it starts the prep at the base")
	for mid: String in (BaseHub._prep().squad as Array).duplicate():
		BaseHub.server_pick(mid, false)
	for mid: String in squad:
		BaseHub.server_pick(mid, true)
	var why := BaseHub.server_deploy()
	var moved := await _wait_until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel, 30.0)
	level = CompoundLevel.current(self)
	if why != "" or not moved:
		check(false, "deploying moves the squad into the zone (%s)" % why)
		return false
	level.ai.child_entered_tree.connect(_on_ai_added)
	var briefing := MapNodes.briefing(level)
	var open := await _wait_until(func() -> bool: return briefing != null and briefing.is_open(), 15.0)
	var up := await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return _roster_soldier(mid) != null), 40.0)
	player = level.players.get_node_or_null(^"1")
	check(open and up and player != null, "in the zone: the briefing is open and the squad is there (%s)" % ", ".join(PackedStringArray(
		squad.map(func(mid: String) -> String: return String(BaseHub.member(mid).callsign)))))
	if not open or not up or player == null:
		return false
	if heli and not _pick_heli_insertion(briefing):
		return false
	briefing.server_set_ready(1, true)
	var started := briefing.server_start()
	await _frames(3)
	var extraction := MapNodes.extraction(level)
	check(started and Contracts.is_deployed() and cid in Contracts.deployment().get("cids", []) and extraction.is_active()
		and not Contracts.objectives.for_contract(cid).is_empty(), "everyone ready, the briefing starts: the contract is live and extraction open")
	_shield(player)
	for mid: String in squad:
		_hold(_roster_soldier(mid))
		_shield(_roster_soldier(mid))
	for n: Node in level.ai.get_children():
		_on_ai_added(n)
	return started and Contracts.is_deployed()


## Hostiles are killed by hits as they come in (the fight isn't what this suite checks).
func _on_ai_added(n: Node) -> void:
	var s := n as Soldier
	if s == null:
		return
	get_tree().create_timer(0.8).timeout.connect(_kill_hostile.bind(s))  # after an objective poll has seen them


func _kill_hostile(s: Soldier) -> void:
	if not is_instance_valid(s) or s.faction != &"hostile" or s.vitals.is_dead() or s.is_queued_for_deletion() or s.has_meta(&"loop_keep"):
		return
	for i in 6:
		if s.vitals.is_dead():
			break
		s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	print("    (%s %s)" % [s.name, "down" if s.vitals.is_dead() else "still up after six head hits"])


## An AI squadmate stands where we put them.
func _hold(s: Soldier) -> void:
	if s and SquadAI.of(s):
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED


## Rounds, blasts and falls do nothing to `s` (Vitals.shielded, what spawn protection uses) for
## the rest of the deployment: a hostile who sees the player or a squadmate in the moment before
## _kill_hostile gets to him can shoot them down mid-step (a slow CI runner gives him longer),
## and a player who's down can't pick up the intel or the casualty (R0800, CI run 38646615024).
## The fight isn't what this suite checks; the injuries it means are dealt on purpose, unshielded.
func _shield(s: Soldier) -> void:
	if s:
		s.vitals.shielded = true


## Hostiles up within `r` m of `at` that _kill_hostile will put down.
func _hostiles_up_near(at: Vector3, r: float) -> int:
	var n := 0
	for c: Node in level.ai.get_children():
		var s := c as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and not s.has_meta(&"loop_keep") and s.vitals.is_up() 				and _flat(s.global_position, at) <= r:
			n += 1
	return n


func _required(cid: String, kind: String) -> Dictionary:
	for o: Dictionary in Contracts.objectives.for_contract(cid):
		if o.kind == kind and not o.optional:
			return o
	return {}


func _state(oid: String) -> String:
	return String(Contracts.objectives.get_objective(oid).get("state", ""))


## Goes to `at` (the squad with the player) and waits for the module there to stream in.
func _go_to(at: Vector3, squad_too := true) -> void:
	_put(player, at)
	if squad_too:
		var i := 0
		for s: Soldier in MapNodes.squad_ai(level):
			i += 1
			_put(s, at + Vector3(-1.5 * i, 0, 2.0))
	var zone := level as ZoneLevel
	var module := zone.module_at(at) if zone else null
	if module:
		await _wait_until(func() -> bool: return module.is_ready(), 20.0)
	await _seconds(0.6)  # its garrison spawns
	## and falls (_kill_hostile, 0.8 s after each comes in): waited on, not a fixed sleep, so a
	## slow runner doesn't start the step with the garrison still up and shooting.
	await _wait_until(func() -> bool: return _hostiles_up_near(at, 150.0) == 0, 10.0)


func _put(s: Soldier, at: Vector3) -> void:
	if s == null:
		return
	var zone := level as ZoneLevel
	s.global_position = zone.ground_point(at) if zone else at
	s.velocity = Vector3.ZERO


# --- The objectives -----------------------------------------------------------------------------

## The intel: picked up where it lies (the item the contract placed, or the site's case), carried out.
func _do_intel(cid: String) -> Dictionary:
	var o := _required(cid, Objectives.EXTRACT_ITEM)
	if o.is_empty():
		return {"why": "no intel objective"}
	var at := _v(o.pos)
	await _go_to(at)
	var item := _objective_item(o)
	if item == null:
		await _seconds(1.0)
		item = _objective_item(o)
	if item == null:
		return {"why": "the intel (%s) isn't there to pick up" % o.params.get("items", [])}
	player.global_position = item.global_position + Vector3(0.7, -0.3, 0)
	player.velocity = Vector3.ZERO
	await _frames(2)
	var id := item.item_id
	player._server_interact.rpc_id(1, item.get_path())
	await _frames(3)
	var has := player.inventory.count_of(id) > 0 or player.inventory.hands == id
	check(has, "the %s is picked up (%.1f m off; %s)" % [ItemDB.get_item(id).name, player.global_position.distance_to(item.global_position) if is_instance_valid(item) else -1.0, _kit_text(player)])
	# The bonus piece, if the site has one.
	for b: Dictionary in Contracts.objectives.for_contract(cid):
		if b.optional and b.kind == Objectives.EXTRACT_ITEM:
			var extra := _objective_item(b)
			if extra and player.inventory.hands == &"":
				player.global_position = extra.global_position + Vector3(0.7, -0.3, 0)
				await _frames(2)
				player._server_interact.rpc_id(1, extra.get_path())
				await _frames(3)
	return {"ok": has} if has else {"why": "the intel couldn't be picked up"}


## The item an EXTRACT_ITEM objective wants, lying in the zone.
func _objective_item(o: Dictionary) -> WorldItem:
	var ids: Array = o.params.get("intel_ids", [])
	var best: WorldItem = null
	for n: Node in level.items.get_children():
		var item := n as WorldItem
		if item == null or item.is_queued_for_deletion():
			continue
		if not ids.is_empty():
			if String(item.state.get("intel_id", "")) in ids:
				return item
		elif Objectives.item_matches(o.params, item.item_id) and item.global_position.distance_to(_v(o.pos)) < 30.0:
			if best == null or item.global_position.distance_to(_v(o.pos)) < best.global_position.distance_to(_v(o.pos)):
				best = item
	return best


## The raid: a breaching charge set against the target, the squad clear of it, and it goes off.
func _do_raid(cid: String) -> Dictionary:
	var o := _required(cid, Objectives.DESTROY_CACHE)
	if o.is_empty():
		return {"why": "no target to destroy"}
	var box: Array = o.params.get("box", [])
	var centre := (_v(box[0]) + _v(box[1])) * 0.5 if box.size() == 2 else _v(o.pos)
	await _go_to(centre + Vector3(2.0, 0, 0))
	var placed := Contracts.objectives.server_place_charge(player, String(o.oid))
	check(placed and player.inventory.count_of(Objectives.CHARGE_ITEM) == 0, "a breaching charge set against the %s" % o.text.trim_prefix("Destroy the "))
	if not placed:
		return {"why": "the charge couldn't be set (%.1f m from the target)" % player.global_position.distance_to(centre)}
	await _go_to(centre + Vector3(45.0, 0, 0))
	var fuse := MissionRegistry.setting_f("charge_fuse_s", 10.0)
	var gone := await _wait_until(func() -> bool: return _state(String(o.oid)) == Objectives.DONE, fuse + 5.0)
	check(gone, "it goes off: the target is destroyed")
	return {"ok": gone} if gone else {"why": "the charge went off but the target isn't destroyed (%s)" % _state(String(o.oid))}


## The HVT: cornered (someone close, nobody of his up near him), cuffed, searched for his
## phone and led; brought to the landing zone with the squad.
func _do_hvt(cid: String) -> Dictionary:
	var o := _required(cid, Objectives.DELIVER_HVT)
	if o.is_empty():
		return {"why": "no HVT objective"}
	await _go_to(_v(o.pos))
	var people := level.people
	var hvt := people.hvt(String(o.params.hvt)) if people else null
	if hvt == null:
		return {"why": "the HVT isn't in the zone"}
	## He never takes his surrender back here: an uncuffed captive may bolt even while watched
	## (HvtAI.BOLT_CHAOS, for CHAOS_S after close gunfire; never with a player within NO_BOLT_M since 2026-10-14), a coin toss every BOLT_CHECK_S
	## that walked him off mid-cuff (R0746: moved 3.9 m, then 7.2 m). Bolting is missions_test's.
	var brain := hvt.get_node_or_null(^"PersonAI") as HvtAI
	if brain:
		brain.bolt_scale = 0.0
	# Cornered: a player stays within HvtAI.CORNERED_M of him, behind him, until he gives up.
	var gave_up := false
	var t := 0.0
	while t < HvtAI.CORNERED_S + 4.0 and not gave_up:
		player.global_position = hvt.global_position + hvt.global_basis.z * 1.5
		player.velocity = Vector3.ZERO
		await _seconds(0.25)
		t += 0.25
		gave_up = Person.is_captive(hvt)
	check(gave_up, "cornered with nobody of his left standing, %s gives up" % hvt.display_name())
	if not gave_up:
		return {"why": "the HVT never gave up when cornered"}
	# Cuffing takes PeopleLayer.CUFF_S standing still; a body set down against a wall can be
	# pushed clear and interrupt it, so (as a player would) try again from another side.
	var cuffed := false
	var cuffs_before := player.inventory.count_of(Person.ZIP_CUFFS)
	var tries: Array[String] = []
	for side: Vector3 in [hvt.global_basis.z, hvt.global_basis.x, -hvt.global_basis.x, -hvt.global_basis.z]:
		player.global_position = hvt.global_position + side * 1.2
		player.velocity = Vector3.ZERO
		await _frames(8)
		var p0 := player.global_position
		var h0 := hvt.global_position
		var problem := Person.cuff_problem(player, hvt)
		people.request.rpc_id(1, "cuff", people.get_path_to(hvt))
		cuffed = await _wait_until(func() -> bool: return Person.is_cuffed(hvt), PeopleLayer.CUFF_S + 2.0)
		tries.append("problem '%s', player moved %.1f m, HVT moved %.1f m" % [problem, player.global_position.distance_to(p0), hvt.global_position.distance_to(h0)])
		if cuffed:
			break
	check(cuffed and player.inventory.count_of(Person.ZIP_CUFFS) == cuffs_before - 1, "zip-cuffed, one pair used (%d tr%s: %s)" % [tries.size(), "y" if tries.size() == 1 else "ies", "; ".join(PackedStringArray(tries))])
	people.request.rpc_id(1, "search", people.get_path_to(hvt))
	await _frames(3)
	check(player.inventory.count_of(&"intel_phone") == 1, "searched: his phone is ours")
	people.request.rpc_id(1, "lead", people.get_path_to(hvt))
	await _frames(3)
	var led := String(Person.state(hvt).get("led_by", "")) != ""
	check(led, "and he follows when led")
	if not cuffed or not led:
		return {"why": "cuffed %s, led %s" % [cuffed, led]}
	return {"ok": true, "cargo": [hvt], "oid": o.oid}


## The hostage: found, led, brought to the landing zone.
func _do_hostage(cid: String) -> Dictionary:
	var o := _required(cid, Objectives.DELIVER_HVT)
	if o.is_empty():
		return {"why": "no hostage objective"}
	await _go_to(_v(o.pos))
	var people := level.people
	var hostage := people.hvt(String(o.params.hvt)) if people else null
	if hostage == null:
		return {"why": "the hostage isn't in the zone"}
	player.global_position = hostage.global_position + Vector3(1.2, 0, 0)
	player.velocity = Vector3.ZERO
	await _frames(3)
	people.request.rpc_id(1, "lead", people.get_path_to(hostage))
	await _frames(3)
	var led := String(Person.state(hostage).get("led_by", "")) != ""
	check(led, "%s follows when led" % hostage.display_name())
	return {"ok": true, "cargo": [hostage]} if led else {"why": "the hostage won't follow"}


## The recovery: the squadmate left behind waits where they were; a player reaching them finds them.
func _do_recovery(cid: String) -> Dictionary:
	var c := Contracts.contract(cid)
	var mid := String(c.get("recover_mid", ""))
	await _wait_until(func() -> bool: return _recovery_target(mid) != null, 10.0)
	var target := _recovery_target(mid)
	if target == null:
		return {"why": "the squadmate isn't waiting in the zone"}
	var p: Array = (c.objectives[0] as Dictionary).params.pos
	check(target.global_position.distance_to(_v(p)) < 3.0, "%s waits where they were left" % target.name)
	_shield(target)
	_put(player, target.global_position + Vector3(1.5, 0, 0))
	var found := await _wait_until(func() -> bool: return target.has_meta(&"found"), 5.0)
	check(found, "a player reaching them finds them")
	_hold(target)
	return {"ok": true, "cargo": [target]} if found else {"why": "never found"}


# --- Extraction ---------------------------------------------------------------------------------

## The player, the squadmates in `bring` and `cargo` (HVTs, hostages, a found squadmate) at the
## zone's landing zone nearest the player; `left` (a member id) stays behind, 60 m off; with
## `deposit` the player sets his rifle down inside the point and a dead hostile is brought
## there; `stow` (item ids in the player's kit) goes into the hold of the pool's M-ATV, brought
## beside the point before anyone walks in (_load_truck). Extraction confirmed, and back
## at the base. {"ok", "why", "deposited", "bodies", "body_items", "field" (what was left outside the point), "lz",
## "pool_id", "stowed"}.
func _extract(bring: Array, cargo: Array, left: String, deposit: bool, stow: Array = []) -> Dictionary:
	var extraction := MapNodes.extraction(level)
	var zone_points: Array = extraction.points.filter(func(p: Dictionary) -> bool: return p.source == "zone")
	if zone_points.is_empty():
		return {"why": "the zone has no landing zone to extract from"}
	var here := Vector2(player.global_position.x, player.global_position.z)
	zone_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.pos as Vector2).distance_to(here) < (b.pos as Vector2).distance_to(here))
	var lz: Vector2 = zone_points[0].pos
	var at := Vector3(lz.x, 0, lz.y)
	var truck := {}
	if not stow.is_empty():
		truck = await _load_truck(stow, at)
	_put(player, at)
	var i := 0
	for mid: String in bring:
		i += 1
		var s := _roster_soldier(mid)
		_hold(s)
		_put(s, at + Vector3(-1.5 * i, 0, 1.5))
	for s: Soldier in cargo:
		if is_instance_valid(s):
			_put(s, at + Vector3(1.5, 0, 1.0))
	if left != "":
		var s := _roster_soldier(left)
		_hold(s)
		_put(s, at + Vector3(0, 0, -60))
		extraction.server_set_bring(String(s.name), false)
	var deposited_ok := true
	var body_items := {}
	if deposit:
		player._server_drop.rpc_id(1, &"primary")
		await _frames(3)
		deposited_ok = player.inventory.slots[&"primary"] == &""
		var body := _hostile_body()  # and a dead hostile brought to the point
		if body:
			for e: Dictionary in Contracts.inventory_items(body.inventory):
				body_items[String(e.id)] = int(body_items.get(String(e.id), 0)) + int(e.get("count", 1))
			_put(body, at + Vector3(3.0, 0, -2.0))
		deposited_ok = deposited_ok and body != null
	await _seconds(1.0)  # the people layer delivers HVTs and banks intel at the landing zone
	var field := _field_counts(lz)
	for o: Dictionary in Contracts.objectives.list:
		print("    objective before extraction: %s" % Objectives.line(o))
	var report := {}
	extraction.deployment_ended.connect(func(r: Dictionary) -> void: report.merge(r, true))
	extraction.countdown_s = 0.5
	var why := extraction.server_confirm()
	check(why == "" and deposited_ok, "at %s with everyone who's coming: extraction confirmed (%s)" % [zone_points[0].name, why + (_where_all(extraction, lz) if why != "" else "")])
	if why != "":
		return {"why": why}
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 30.0)
	level = CompoundLevel.current(self)
	check(home and not Contracts.is_deployed() and not RosterDeployment.is_running(BaseHub.roster()), "extracted: the deployment ends and everyone is back at the base")
	if not home:
		return {"why": "never back at the base"}
	await _wait_until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node_or_null(^"1")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	return {"ok": true, "deposited": report.get("deposited", []), "bodies": report.get("bodies", []), "body_items": body_items,
		"field": field, "lz": lz, "pool_id": truck.get("pool_id", ""), "stowed": truck.get("stowed", false)}


## B-18: the pool's M-ATV brought beside the landing zone at `at`, and `ids` moved from the
## player's kit into its hold the way a player loads it (Vehicle.server_load): it goes home with
## the squad, and what's aboard counts as carried out. {"pool_id", "stowed" (all of them aboard)}.
func _load_truck(ids: Array, at: Vector3) -> Dictionary:
	var free := MotorPool.list().filter(func(e: Dictionary) -> bool: return MotorPool.problem(String(e.id)) == "")
	var zone := level as ZoneLevel
	var spot := at + Vector3(8, 0, 6)
	var v: Vehicle = MotorPool.server_bring(String(free[0].id), level, Transform3D(Basis(), (zone.ground_point(spot) if zone else spot) + Vector3.UP * 0.3)) if not free.is_empty() else null
	if v == null:
		check(false, "the pool's M-ATV is brought beside the landing zone")
		return {}
	await _frames(3)
	var stowed := true
	for id: StringName in ids:
		var said := ""
		for container: StringName in player.inventory.search_containers():
			var list: Array = player.inventory.containers[container]
			for k in list.size():
				if StringName(list[k].id) == id:
					said = v.server_load(player, container, k, id)
					break
			if said != "":
				break
		stowed = stowed and said.begins_with("Loaded") and v.cargo_hold.count_of(id) > 0 and player.inventory.count_of(id) == 0
	check(stowed, "the %s loaded into the hold of the pool's M-ATV beside the landing zone" % ", ".join(PackedStringArray(ids.map(func(id: StringName) -> String: return ItemDB.get_item(id).name))))
	return {"pool_id": MotorPool.pool_id(v), "stowed": stowed}


## A dead hostile's body in the zone with something on it, or null.
func _hostile_body() -> Soldier:
	for n: Node in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and not Contracts.inventory_items(s.inventory).is_empty():
			return s
	return null


# --- By helicopter ---------------------------------------------------------------------------------

## The briefing offers a helicopter insertion from each insertion point on this contract zone,
## each with its LZ in dead ground 200-450 m from the objective; the one nearest the objective
## is picked. Returns whether it was.
func _pick_heli_insertion(briefing: Briefing) -> bool:
	var objective: Variant = Briefing.objective_point(briefing.contract)
	var helis: Array = briefing.insertion_points().filter(func(p: Dictionary) -> bool: return p.get("method", "") == Briefing.HELI)
	check(objective != null and not helis.is_empty() and helis.all(func(p: Dictionary) -> bool: return p.get("lz", "") == "dead_ground"),
		"the briefing offers %d helicopter insertion(s) on this contract zone (%s)" % [helis.size(), ", ".join(PackedStringArray(helis.map(func(p: Dictionary) -> String: return String(p.name))))])
	if objective == null or helis.is_empty():
		return false
	var obj: Vector2 = objective
	var watch := DeadGround.watchers(level)
	var lines := PackedStringArray()
	var all_ok := true
	var best: Dictionary = {}
	for p: Dictionary in helis:
		var at := Vector3(float(p.pos[0]), 0.0, float(p.pos[1]))
		at.y = LandingZone.terrain_y(level, at)
		var d := Vector2(at.x, at.z).distance_to(obj)
		var seen := DeadGround.seen_by(level, at, watch)
		var lz := LandingZone.check(level, at)
		# Seen: only if the zone has no dead ground in the ring that takes a landing (the plan's
		# fallback, named so in the briefing).
		var missed: Variant = null if seen == 0 or bool(p.get("hidden", true)) else _dead_ground_in_ring(Vector3(obj.x, 0.0, obj.y), watch)
		all_ok = all_ok and d >= DeadGround.OBJECTIVE_RING_M.x - 1.0 and d <= DeadGround.OBJECTIVE_RING_M.y + 1.0 and lz.ok 			and (seen == 0) == bool(p.get("hidden", false)) and missed == null
		lines.append("%s: %.0f m from the objective, seen by %d of %d posts%s, slope %.0f°%s" % [p.id, d, seen, watch.size(),
			"" if seen == 0 else (" (no dead ground in the ring)" if missed == null else " (missed dead ground at %s)" % str(missed)),
			float(lz.slope_deg), "" if lz.ok else ", " + String(lz.why)])
		if best.is_empty() or d < float(best.d):
			best = {"id": String(p.id), "d": d}
	check(all_ok, "every LZ is 200-450 m from the objective, takes a landing and no garrison post sees it (eye to eye, 1.7 m), or the zone has no such spot: %s" % "; ".join(lines))
	check(briefing.server_set_insertion(String(best.id)), "the helicopter insertion %s is picked" % best.id)
	return true


## A spot in the insertion ring round `centre` that no post in `watch` sees and that takes a
## landing (a coarse scan: every 25 m out, 32 round), or null.
func _dead_ground_in_ring(centre: Vector3, watch: Array[Vector3]) -> Variant:
	var inside: Rect2 = level.map_area().grow(-DeadGround.EDGE_KEEP_M)
	var r := DeadGround.OBJECTIVE_RING_M.x
	while r <= DeadGround.OBJECTIVE_RING_M.y:
		for k in 32:
			var a := TAU * k / 32.0
			var at := centre + Vector3(cos(a), 0.0, sin(a)) * r
			if not inside.has_point(Vector2(at.x, at.z)) or watch.any(func(q: Vector3) -> bool: return _flat(at, q) < DeadGround.POST_KEEP_M):
				continue
			at.y = LandingZone.terrain_y(level, at)
			if DeadGround.seen_by(level, at, watch, 1) == 0 and LandingZone.check(level, at).ok:
				return Vector2i(roundi(at.x), roundi(at.z))
		r += 25.0
	return null


## The squad starts seated in a UH-60 that flies in low by the insertion point, flares, lands
## at the LZ, puts everyone out and leaves. Returns whether they're on the ground at the LZ.
func _heli_insert(squad: Array) -> bool:
	Helicopter.pace = HELI_PACE
	var sup := HeliSupports.of(level)
	var briefing := MapNodes.briefing(level)
	var point := briefing.insertion()
	var lz := Vector3(float(point.pos[0]), 0.0, float(point.pos[1]))
	var c := sup.active("insertion") if sup else null
	var mates: Array = squad.map(func(mid: String) -> Soldier: return _roster_soldier(mid))
	var aboard := c != null and Vehicle.ride_of(player) == c.heli and mates.all(func(s: Soldier) -> bool: return s != null and Vehicle.ride_of(s) == c.heli)
	check(aboard and c.heli.is_flying(), "the squad starts seated in a UH-60 in the air (%d aboard)" % (c.heli.occupants().size() if c else 0))
	if c == null:
		return false
	var via: Vector3 = c.route[0] if not c.route.is_empty() else Vector3.INF
	# Captain, 2026-10-14 (harbour_yard: "came in from wrong side of the map", "it turned
	# around"): it comes in from the zone's edge nearest the LZ (HeliRoute.entry), by a point
	# between there and the LZ, no turn of more than 120 degrees before the hook, the way in at
	# most 1.6 times the straight line; the map draws that way in.
	var start := c.exit  # where it was put in the air (the edge: its way out until it leaves), a few frames back
	var inside := HeliRoute.inside(level)
	var on_edge := absf(start.x - inside.position.x) < 1.0 or absf(start.x - inside.end.x) < 1.0 \
		or absf(start.z - inside.position.y) < 1.0 or absf(start.z - inside.end.y) < 1.0
	var far_post: Array[Vector3] = [Vector3(1e6, 0.0, 1e6)]  # (nobody watching: the nearest edge)
	var nearest := HeliRoute.entry(level, lz, far_post)
	check(on_edge and _flat(start, lz) <= float(nearest.run) + HeliRoute.ENTRY_SLACK_M + HeliCall.SPAWN_SPACING_M + 1.0,
		"it comes in from the zone's edge by the LZ, not across the map (started at (%.0f, %.0f), %.0f m out; the nearest edge %.0f m)" % [
		start.x, start.z, _flat(start, lz), float(nearest.run)])
	var line: Array[Vector3] = [Vector3(start.x, 0.0, start.z)]
	line.append_array(c.route)
	line.append(lz)
	check(HeliRoute.path_ratio(line) <= 1.6 and HeliRoute.max_turn_deg(line) <= 120.0,
		"its route: %.2f times the straight line, at most %.0f degrees of turn before the hook" % [HeliRoute.path_ratio(line), HeliRoute.max_turn_deg(line)])
	var drawn := MapView.insertion_routes(level)
	check(not drawn.is_empty() and (drawn[0].points as PackedVector2Array).size() == line.size()
		and (drawn[0].points as PackedVector2Array)[0].distance_to(Vector2(start.x, start.z)) < 1.0,
		"the map draws its way in: entry, the point it comes in low by, the LZ (%s)" % [drawn[0].points if not drawn.is_empty() else "nothing"])
	var first_dir := Vector2.ZERO
	var reversal := 0.0
	var flown := 0.0
	var ratio := 0.0
	var prev := start
	var low_agl := INF
	var high_agl := 0.0
	var passed_by := INF
	var flare := 0.0
	var t := 0.0
	while t < 120.0 and is_instance_valid(c.heli) and not c.heli.is_landed():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var h := c.heli
		var far := Vector2(h.global_position.x - lz.x, h.global_position.z - lz.z).length()
		if ratio == 0.0 and h.has_meta(&"landing"):  # the J-hook from here
			ratio = (flown + far) / maxf(_flat(start, lz), 1.0)
		elif ratio == 0.0:
			var go := Vector2(h.global_position.x - prev.x, h.global_position.z - prev.z)
			flown += go.length()
			if first_dir == Vector2.ZERO and _flat(h.global_position, start) > 30.0:
				first_dir = Vector2(h.global_position.x - start.x, h.global_position.z - start.z).normalized()
			elif first_dir != Vector2.ZERO and go.length() > 0.05:
				reversal = maxf(reversal, rad_to_deg(absf(first_dir.angle_to(go))))
		prev = h.global_position
		if via != Vector3.INF:
			passed_by = minf(passed_by, Vector2(h.global_position.x - via.x, h.global_position.z - via.z).length())
		if far > 300.0:
			var agl := h.global_position.y - LandingZone.terrain_y(level, h.global_position)
			low_agl = minf(low_agl, agl)
			high_agl = maxf(high_agl, agl)
		elif far > 15.0:
			flare = maxf(flare, rad_to_deg(asin(clampf(-h.global_basis.z.y, -1.0, 1.0))))  # nose up while slowing
	var landed := is_instance_valid(c.heli) and c.heli.is_landed()
	check(via == Vector3.INF or passed_by < HeliCall.ROUTE_PASS_M + 10.0, "it flew in by the insertion point (%.0f m from it)" % passed_by)
	# Captain, 2026-10-14: "fly in no higher than 10m" (contour flight; a little more only to clear
	# what stands taller in its way), never down in the dirt.
	check(low_agl > 1.0 and high_agl < 12.0, "low over the terrain on the way in: %.0f-%.0f m above the ground" % [low_agl, high_agl])
	check(flare > 3.0, "it flared, nose up, coming in to land (%.0f°)" % flare)
	check(ratio > 0.0 and ratio <= 1.6 and reversal <= 120.0,
		"flown in without turning back: %.2f times the straight line before the hook, at most %.0f degrees off the way it set off" % [ratio, reversal])
	check(landed and Vector2(c.heli.global_position.x - lz.x, c.heli.global_position.z - lz.z).length() < 15.0,
		"it lands at the LZ (%.0f s)" % t)
	if not landed:
		return false
	await _wait_until(func() -> bool: return mates.all(func(s: Soldier) -> bool: return Vehicle.ride_of(s) == null), 10.0)
	check(mates.all(func(s: Soldier) -> bool: return Vehicle.ride_of(s) == null), "the AI get out")
	check(sup.heard_line("Out, out, out"), "the radio: on the ground, out, out, out")
	c.heli.server_exit(player)  # the player's own get-out
	await _frames(3)
	check(Vehicle.ride_of(player) == null and Vector2(player.global_position.x - lz.x, player.global_position.z - lz.z).length() < 15.0,
		"the player is out at the LZ")
	var leaving := await _wait_until(func() -> bool: return c.phase in [HeliCall.Phase.TAKEOFF, HeliCall.Phase.LEAVING, HeliCall.Phase.GONE], 10.0)
	check(leaving, "and the helicopter lifts off and leaves")
	for s: Soldier in mates:
		_hold(s)
	return true


## A spot `from` 70-140 m off `lz` where a man sees it (eye to eye, past the world), or INF.
func _spot_seeing(lz: Vector3) -> Vector3:
	# (within DeadGround.HOT_CLOSE_M: since 2026-10-14 only an enemy close by makes an LZ hot)
	for r: float in [110.0, 130.0, 90.0, 140.0, 70.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var at := lz + Vector3(cos(a), 0, sin(a)) * r
			at.y = LandingZone.terrain_y(level, at)
			if level.map_area().grow(-60.0).has_point(Vector2(at.x, at.z)) and DeadGround.sees(level, lz, at, true):
				return at
	return Vector3.INF


## The helicopter extraction (see ORDER's note): returns _extract's shape plus "left_body".
func _extract_heli(squad: Array, casualty: String) -> Dictionary:
	var sup := HeliSupports.of(level)
	var extraction := MapNodes.extraction(level)
	HeliCall.board_direct_s = 2.0
	HeliSupports.free_calls = 1  # (the bank check counts only what the debrief paid)
	var hurt := _roster_soldier(casualty)
	if hurt == null:
		return {"why": "no casualty"}
	_put(hurt, player.global_position + Vector3(2.0, 0, 0))
	hurt.vitals.shielded = false  # (_shield: this one's meant)
	hurt.vitals.server_damage(70.0)
	await _frames(3)
	check(not hurt.vitals.is_up(), "%s goes down" % hurt.name)
	# The call: the pilot picks an LZ near us.
	var why := Supports.server_command(player, "support:extraction:near", player.global_position, PackedStringArray())
	var c := sup.active("extraction")
	check(why == "" and c != null and c.mark.has("pos"), "helicopter extraction called near us (%s)" % why)
	if c == null:
		return {"why": why}
	var first := c.lz
	var hidden := bool(c.mark.get("hidden", false))  # (no dead ground near: the fewest posts see it, the radio says so)
	var seen_first := DeadGround.seen_by(level, first, DeadGround.watchers(level))
	check(_flat(first, player.global_position) <= DeadGround.SQUAD_RING_M.y + 10.0 and (seen_first == 0) == hidden,
		"its LZ is %.0f m from us, %s" % [_flat(first, player.global_position), "out of the enemy's sight" if hidden else "seen from %d post(s): no dead ground near" % seen_first])
	# An enemy in sight of the LZ: hot.
	var spot := _spot_seeing(first)
	if spot == Vector3.INF:
		check(false, "a spot that sees the LZ, for the enemy")
		return {"why": "no spot to make the LZ hot from"}
	var spotter := level.spawn_soldier({"name": "LoopSpotter", "faction": "hostile", "variant": "urban", "pos": level.ground_point(spot),
		"loadout": ["mk18"], "combat": 0.1, "discipline": 0.5, "guard": true})
	spotter.set_meta(&"loop_keep", true)
	await _frames(2)
	_hold(spotter)
	var waved := await _wait_until(func() -> bool: return not c.waved_off.is_empty(), 90.0)
	check(waved and sup.heard_line("is hot, enemy in sight of it. Waving off"), "the LZ is hot: it waves off (radio: %s)" % (sup.heard[-1] if not sup.heard.is_empty() else "nothing"))
	var lz := c.lz
	check(waved and _flat(lz, first) >= HeliCall.WAVE_OFF_AVOID_M and DeadGround.hot_watcher(level, lz) == null and not extraction.point_by_id(c.point_id).is_empty()
		and Extraction.inside(extraction.point_by_id(c.point_id), lz), "and picks another LZ %.0f m off, out of his sight; the extraction point moves there" % _flat(lz, first))
	spotter.vitals.server_kill()
	var landed := await _wait_until(func() -> bool: return c.heli != null and is_instance_valid(c.heli) and c.heli.is_landed(), 90.0)
	check(landed and _flat(c.heli.global_position, lz) < 15.0, "it lands at the new LZ")
	if not landed:
		return {"why": "never landed"}
	check(sup.heard_line("Get everyone aboard"), "the radio: on the ground, get everyone aboard")
	# The squad comes over; the player sets his rifle down in the point, carries the casualty in.
	var door := c.heli.global_transform * Vector3(-2.2, 0.0, -2.4)
	var by_door := level.ground_point(door)
	_put(player, by_door + Vector3(-6.0, 0, 3.0))
	var i := 0
	for mid: String in squad:
		if mid == casualty:
			continue
		i += 1
		_put(_roster_soldier(mid), by_door + Vector3(-4.0 - 1.5 * i, 0, -3.0))
	_put(hurt, player.global_position + Vector3(1.2, 0, 0))
	if player.inventory.slots[&"primary"] == &"":  # (the raid left his rifle at its point: the spare from the pack)
		for container: StringName in player.inventory.search_containers():
			var at: int = (player.inventory.containers.get(container, []) as Array).find_custom(func(e: Dictionary) -> bool: return e.id == &"m4a1")
			if at >= 0 and player.inventory.equip_entry(container, at):
				break
	check(player.inventory.slots[&"primary"] == &"m4a1", "the player has a rifle to set down (%s)" % _kit_text(player))
	player._server_drop.rpc_id(1, &"primary")
	await _frames(3)
	var bodies: Array = get_tree().get_nodes_in_group(Soldier.DEAD_GROUP).filter(func(n: Node) -> bool:
		var s := n as Soldier
		return s and s.faction == &"hostile" and s != spotter and not s.is_queued_for_deletion() and not Contracts.inventory_items(s.inventory).is_empty())
	if bodies.is_empty():
		check(false, "a dead hostile to bring")
		return {"why": "no body to bring"}
	var loot := bodies[0] as Soldier
	var left := bodies[1] as Soldier if bodies.size() > 1 else null
	if left == null:
		info("only one dead hostile with gear: no body left lying in the point to check")
	var body_items := {}
	for e: Dictionary in Contracts.inventory_items(loot.inventory):
		body_items[String(e.id)] = int(body_items.get(String(e.id), 0)) + int(e.get("count", 1))
	_put(loot, by_door)  # set down by the door: loaded
	if left:
		_put(left, c.heli.global_position + Vector3(10.0, 0, 9.0))  # in the point, away from the doors: stays
	await _frames(3)
	var lifted := player.server_pick_up_body(hurt, Soldier.CARRY, 3.0)
	check(lifted, "the player picks up the casualty (%.1f m off; casualty up=%s wake in %.0f s (%s), carried by %s; player up=%s hands=%s carrying %s)" % [
		hurt.body_point().distance_to(player.global_position), hurt.vitals.is_up(), hurt.vitals.wake_eta(), ", ".join(PackedStringArray(hurt.vitals.why_unconscious())),
		hurt.carried_by.name if is_instance_valid(hurt.carried_by) else "nobody", player.vitals.is_up(), player.inventory.hands,
		player.carrying.name if is_instance_valid(player.carrying) else "nobody"])
	await _seconds(2.0)
	_put(player, by_door + Vector3(-1.0, 0, 0))
	var loaded := await _wait_until(func() -> bool:
		var hold := c.heli.cargo_hold.entries().map(func(x: Dictionary) -> String: return String(x.id))
		return Vehicle.ride_of(hurt) == c.heli and Vehicle.ride_of(loot) == c.heli and "m4a1" in hold, 15.0)
	check(Vehicle.ride_of(hurt) == c.heli, "the carried casualty is loaded aboard (%s)" % _kit_text(hurt))
	check(Vehicle.ride_of(loot) == c.heli and (left == null or Vehicle.ride_of(left) == null), "the dead hostile by the door is loaded; the one lying off in the point isn't")
	check("m4a1" in c.heli.cargo_hold.entries().map(func(x: Dictionary) -> String: return String(x.id)), "the rifle set down in the point goes into the hold")
	if not loaded:
		return {"why": "the casualty, the body or the rifle wasn't loaded"}
	var mates_in := await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return Vehicle.ride_of(_roster_soldier(mid)) == c.heli), 20.0)
	check(mates_in, "the squadmates board")
	var field := {}
	var report := {}
	var heard_all := [false]  # (read as the deployment ends: the zone and its supports go right after)
	extraction.deployment_ended.connect(func(r: Dictionary) -> void:
		heard_all[0] = is_instance_valid(sup) and sup.heard_line("Everyone's aboard")
		field.merge(_field_counts_heli(c.heli), true)  # as it ends (the squad's AI may still drop someone while boarding)
		report.merge(r, true))
	c.heli.server_enter(player)  # the player gets in last
	var out := await _wait_until(func() -> bool: return not report.is_empty(), 20.0)
	check(out and heard_all[0], "everyone aboard: it lifts off and the deployment ends")
	if not out:
		return {"why": "the deployment never ended"}
	var lz2 := Vector2(lz.x, lz.z)
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 60.0)
	level = CompoundLevel.current(self)
	Helicopter.pace = 1.0
	HeliCall.board_direct_s = 45.0
	HeliSupports.free_calls = -1
	check(home and not Contracts.is_deployed(), "flown out: the deployment ends and everyone is back at the base")
	if not home:
		return {"why": "never back at the base"}
	await _wait_until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node_or_null(^"1")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	return {"ok": true, "deposited": report.get("deposited", []), "bodies": report.get("bodies", []), "body_items": body_items,
		"field": field, "lz": lz2, "left_body": left.body_uid if left else "none"}


## What's left in the zone, not aboard `heli`, by item id: loose items and what's on the dead.
func _field_counts_heli(heli: Helicopter) -> Dictionary:
	var out := {}
	var add := func(entries: Array) -> void:
		for e: Dictionary in entries:
			out[String(e.id)] = int(out.get(String(e.id), 0)) + int(e.get("count", 1))
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := n as WorldItem
		if item and not item.is_queued_for_deletion():
			add.call(Contracts.flatten_entry({"id": item.item_id, "count": item.count, "state": item.state}))
	var seen := {}
	for n: Node in get_tree().get_nodes_in_group(&"combatants") + get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s == null or seen.has(s) or s.is_queued_for_deletion() or not s.vitals.is_dead() or s.has_meta(&"vehicle_crew") or Vehicle.ride_of(s) == heli:
			continue
		seen[s] = true
		add.call(Contracts.inventory_items(s.inventory))
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## What's left in the field outside the landing zone at `lz` (x, z), by item id: loose items
## and what's on the dead (Contracts.report_from_level's "field_items" should be this).
func _field_counts(lz: Vector2) -> Dictionary:
	var out := {}
	var add := func(entries: Array) -> void:
		for e: Dictionary in entries:
			out[String(e.id)] = int(out.get(String(e.id), 0)) + int(e.get("count", 1))
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := n as WorldItem
		if item and not item.is_queued_for_deletion() and Vector2(item.global_position.x, item.global_position.z).distance_to(lz) > Extraction.RADIUS_M:
			add.call(Contracts.flatten_entry({"id": item.item_id, "count": item.count, "state": item.state}))
	var seen := {}
	for n: Node in get_tree().get_nodes_in_group(&"combatants") + get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s == null or seen.has(s) or s.is_queued_for_deletion() or not s.vitals.is_dead() or s.has_meta(&"vehicle_crew"):
			continue
		seen[s] = true
		var at := s.body_point()
		if Vector2(at.x, at.z).distance_to(lz) > Extraction.RADIUS_M:
			add.call(Contracts.inventory_items(s.inventory))
	return out


## Picks salvage that fits the budget, closes the debrief and checks the picks reach the stash.
func _salvage(debrief: Dictionary) -> void:
	var salvage: Dictionary = debrief.get("salvage", {})
	var pool: Array = salvage.get("pool", [])
	var picked := {}
	for i in pool.size():
		if Contracts.server_pick_salvage(i):
			picked[String(pool[i].id)] = int(picked.get(String(pool[i].id), 0)) + int(pool[i].count)
	var before := BaseArmory.counts(BaseHub.stash())
	var leads_before := Contracts.board().filter(func(c: Dictionary) -> bool: return String(c.title).begins_with("Lead: ")).size()
	var intel := (debrief.get("intel", []) as Array).size()
	Contracts.server_finish_debrief()
	await _seconds(BaseHub.STASH_POLL_S + 0.5)
	var after := BaseArmory.counts(BaseHub.stash())
	var all_in := true
	for id: String in picked:
		all_in = all_in and int(after.get(id, 0)) - int(before.get(id, 0)) >= int(picked[id])
	if pool.is_empty() or int(salvage.get("budget", 0)) <= 0:
		info("no salvage to pick (pool $%s, budget $%s)" % [DebriefCalc.money(salvage.get("pool_value", 0)), DebriefCalc.money(salvage.get("budget", 0))])
	else:
		check(not picked.is_empty() and all_in and bool(Contracts.last_debrief().get("finished", false)),
			"salvage: picked %s (budget $%s of a $%s pool); closing the debrief puts them in the stash" % [picked, DebriefCalc.money(salvage.budget), DebriefCalc.money(salvage.pool_value)])
	if intel > 0:
		var leads := Contracts.board().filter(func(c: Dictionary) -> bool: return String(c.title).begins_with("Lead: ")).size()
		check(leads > leads_before, "the intel brought out is turned in at the close: %d new lead(s) on the board" % (leads - leads_before))


# --- Helpers ------------------------------------------------------------------------------------

## What a soldier carries, in words (for a failed check).
static func _kit_text(s: Soldier) -> String:
	if s == null:
		return "nobody"
	var parts := PackedStringArray()
	for slot: StringName in Inventory.SLOTS:
		if s.inventory.slots.get(slot, &"") != &"":
			parts.append("%s=%s" % [slot, s.inventory.slots[slot]])
	for c: StringName in s.inventory.containers:
		for e: Dictionary in s.inventory.containers[c]:
			parts.append("%s:%s x%d" % [c, e.id, int(e.get("count", 1))])
	parts.append("hands=%s up=%s" % [s.inventory.hands, s.vitals.is_up()])
	return ", ".join(parts)

func _roster_soldier(mid: String) -> Soldier:
	if level == null:
		return null
	for n: Node in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and s.has_meta(&"roster_id") and String(s.get_meta(&"roster_id")) == mid \
				and not s.vitals.is_dead() and not s.has_meta(&"recovery"):
			return s
	return null


func _recovery_target(mid: String) -> Soldier:
	for n: Node in level.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"recovery") and String(s.get_meta(&"roster_id")) == mid and not s.vitals.is_dead():
			return s
	return null


static func _v(p: Variant) -> Vector3:
	if p is Vector3:
		return p
	var a: Array = p
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Waits until `cond` holds or `timeout` seconds pass; returns whether it held.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.1)
		left -= 0.1
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
