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
const ORDER: Array[String] = ["intel_grab", "raid", "recovery", "hvt_capture", "hostage_rescue"]
const HIRES := 6

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var player: Soldier
## Mission type -> "completed end to end" or what broke.
var results := {}
var _team: Array[String] = []  # hired member ids
var _mia := ""                  # the member left behind on the raid
var _failures_at_start := 0


func _ready() -> void:
	GameState.zone_id = "test_loop" + tag
	Campaign.campaign_id = "test_loop" + tag  # never touch a real save
	get_tree().create_timer(450.0).timeout.connect(func() -> void:
		print("LOOP TEST FAILED (timed out)")
		_cleanup()
		get_tree().quit(99))
	GameState.delete_save()
	Campaign.reset_campaign()
	_test_safe_offer()
	await _start_campaign()
	if level is BaseLevel:
		await _kit_up()
		for type in ORDER:
			_failures_at_start = failures
			var why: String = await _mission(type)
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


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func info(what: String) -> void:
	print("  [info] %s" % what)


func _cleanup() -> void:
	Contracts.auto_show_debrief = true
	if Net.is_hosting():
		BaseHub._delete_zone_saves()
	Campaign.reset_campaign()
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
	var squad := _squad_for(type)
	if squad.is_empty():
		return "no squad to send"
	var cid := _take_offer(type)
	if cid == "":
		return "no offer taken from the board"
	var c := Contracts.contract(cid)
	var title := String(c.title)
	if not await _deploy(cid, squad):
		return "the deployment didn't start"
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
	if type == "intel_grab":
		wounded = squad[1]
		(mates[wounded] as Soldier).vitals.server_burn(0.3)  # caught in a fire: burns sit them out
	if type == "raid":
		left = squad[squad.size() - 1]
		bring.erase(left)
	var deposit := type == "raid"  # the rifle set down at the point goes to the stash
	var cash_before := Economy.cash()
	var stash_before := BaseArmory.counts(BaseHub.stash())
	var bills := [0]
	var on_week := func(_week: int, bill: Dictionary) -> void: bills[0] += int(bill.total) - int(bill.get("loan_taken", 0))
	Economy.week_paid.connect(on_week)
	var out := await _extract(bring, done.get("cargo", []), left, deposit)
	Economy.week_paid.disconnect(on_week)
	if not out.get("ok", false):
		return "extraction: %s" % out.get("why", "")
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


## Member ids for `type`'s squad (who's available).
func _squad_for(type: String) -> Array:
	var ready: Array = _team.filter(func(mid: String) -> bool: return Roster.is_available(BaseHub.member(mid)))
	var want := {"intel_grab": 2, "raid": 3, "recovery": 1, "hvt_capture": 2, "hostage_rescue": 2}
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
func _deploy(cid: String, squad: Array) -> bool:
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
	briefing.server_set_ready(1, true)
	var started := briefing.server_start()
	await _frames(3)
	var extraction := MapNodes.extraction(level)
	check(started and Contracts.is_deployed() and cid in Contracts.deployment().get("cids", []) and extraction.is_active()
		and not Contracts.objectives.for_contract(cid).is_empty(), "everyone ready, the briefing starts: the contract is live and extraction open")
	for mid: String in squad:
		_hold(_roster_soldier(mid))
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
	if not is_instance_valid(s) or s.faction != &"hostile" or s.vitals.is_dead() or s.is_queued_for_deletion():
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
	await _seconds(0.6)  # its garrison spawns and falls


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
	_put(player, target.global_position + Vector3(1.5, 0, 0))
	var found := await _wait_until(func() -> bool: return target.has_meta(&"found"), 5.0)
	check(found, "a player reaching them finds them")
	_hold(target)
	return {"ok": true, "cargo": [target]} if found else {"why": "never found"}


# --- Extraction ---------------------------------------------------------------------------------

## The player, the squadmates in `bring` and `cargo` (HVTs, hostages, a found squadmate) at the
## zone's landing zone nearest the player; `left` (a member id) stays behind, 60 m off; with
## `deposit` the player sets his rifle down inside the point and a dead hostile is brought
## there. Extraction confirmed, and back
## at the base. {"ok", "why", "deposited", "bodies", "body_items", "field" (what was left outside the point), "lz"}.
func _extract(bring: Array, cargo: Array, left: String, deposit: bool) -> Dictionary:
	var extraction := MapNodes.extraction(level)
	var zone_points: Array = extraction.points.filter(func(p: Dictionary) -> bool: return p.source == "zone")
	if zone_points.is_empty():
		return {"why": "the zone has no landing zone to extract from"}
	var here := Vector2(player.global_position.x, player.global_position.z)
	zone_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.pos as Vector2).distance_to(here) < (b.pos as Vector2).distance_to(here))
	var lz: Vector2 = zone_points[0].pos
	var at := Vector3(lz.x, 0, lz.y)
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
	check(why == "" and deposited_ok, "at %s with everyone who's coming: extraction confirmed (%s)" % [zone_points[0].name, why])
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
		"field": field, "lz": lz}


## A dead hostile's body in the zone with something on it, or null.
func _hostile_body() -> Soldier:
	for n: Node in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and not Contracts.inventory_items(s.inventory).is_empty():
			return s
	return null


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
