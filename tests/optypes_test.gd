extends Node
## The operation types (docs/combined_arms.md 6.4, 6.1, 6.5, 9.3's D4/D5 rows; cg_brief queue item
## 3.3): the `optypes` suite. Two processes over real ENet, like the operations suite:
##   <exe> --headless --path . res://tests/optypes_test.tscn -- --optypes-host
##   <exe> --headless --path . res://tests/optypes_test.tscn -- --optypes-join 127.0.0.1
## The host checks the five types' offer rules (who posts which, where, at what standing) and their
## site selectors on their own, then plays each type in turn in its own 8 km zone: offered and taken
## (20% on signing), its zone, its phases advancing on their tasks (by test hooks: the player put on
## each objective, the run's clock moved on), its own mechanic, its pay into the bank phase by phase,
## a save and load mid-operation (the mechanic picking up from the run), its debrief (its own lines),
## the war fed, and the mechanics' budgets:
##   phased_invasion  the attached Abrams section (out, crewed, overwatching the company's task, a
##                    player taking its gun and giving it back), allied fires (the preparation, the
##                    company's call, danger close refused, the allied commander's smoke), the fuel
##                    truck at the logistics point, the employer's Dustoff, the HQ's commander taken
##                    alive for phase 4's bonus: completed;
##   armoured_thrust  the column down the axis with the attached Bradleys, halting short of a blocking
##                    position until it's clear, waiting for the company to mount, a bypass off-road,
##                    the 45 minutes running out: partial;
##   seize_crossing   the bridge's charges and firing point, the firing team seeing us and its fuse,
##                    the wire cut, the bridge kept intact (its +40%), the armour crossing, the charges
##                    blowing it when they fire: completed;
##   hold_town        the town taken over, the defence budget spent (six pieces, a seventh refused, a
##                    piece too far refused, none after the prep), the pieces solid, the enemy seeing
##                    a piece, its axis chosen round what it has seen, the waves and their mortar, the
##                    centre held: completed;
##   beach_landing    dawn, the AAV waves out of the well deck with the company and the allies aboard,
##                    the fires and smoke before H-hour, the waves landing and H-hour with them, wave
##                    2, the exits and the harbour, the beachhead lost: partial.
## The client joins late, in the first operation, and then follows the host into each zone: in each
## it asks for the run and checks the type's own state matches the host's (the attached armour, the
## column, the bridge, the field defences built on it, the AAVs it sees). Each process prints OPTYPES
## TEST PASSED/FAILED and exits with its failure count. Never touches a real save. OPTYPES_ONLY
## (types, comma-separated) plays only those, for a local look: the client is then never let in.

const ORDER := ["phased_invasion", "armoured_thrust", "seize_crossing", "hold_town", "beach_landing"]
## Small OOBs (D3-20): the checks stay quick; each type keeps the entries its mechanic needs.
const OOB := {
	"phased_invasion": {
		"friendly_oob": [{"kind": "rifle_squad", "groups": 2, "men": 3, "callsign": "Saber", "kit": "allied_us"},
			{"kind": "mortar_section", "groups": 1, "vehicles": ["mortar_m224"], "crew": 1, "men": 0, "callsign": "Mortar", "kit": "allied_us"},
			{"kind": "transport", "groups": 1, "vehicles": ["maxxpro"], "crew": 1, "men": 0, "callsign": "Bowser", "kit": "allied_us", "logistics": "fuel", "wave": 1}],
		"enemy_oob": [{"kind": "rifle_squad", "groups": 1, "men": 2, "bands": ["keep"], "callsign": "Roamer", "kit": "rifles"}]},
	"armoured_thrust": {
		"friendly_oob": [{"kind": "armour_section", "groups": 1, "vehicles": ["abrams"], "crew": 2, "men": 0, "callsign": "Iron", "kit": "allied_us"},
			{"kind": "mech_infantry", "groups": 1, "vehicles": ["bradley"], "crew": 2, "men": 2, "callsign": "Hammer", "kit": "allied_us"}],
		"enemy_oob": [{"kind": "rifle_squad", "groups": 1, "men": 2, "bands": ["keep"], "callsign": "Roamer", "kit": "rifles"}]},
	"seize_crossing": {
		"friendly_oob": [{"kind": "rifle_squad", "groups": 1, "men": 3, "callsign": "Saber", "kit": "allied_vm"},
			{"kind": "armour_section", "groups": 1, "vehicles": ["bradley"], "crew": 2, "men": 0, "callsign": "Iron", "kit": "allied_vm", "reserve": true}],
		"enemy_oob": [{"kind": "engineers", "groups": 1, "men": 2, "at": {"site": "cp_bridge"}, "callsign": "Fuse", "kit": "rifles"}]},
	"hold_town": {
		"friendly_oob": [{"kind": "rifle_squad", "groups": 1, "men": 3, "callsign": "Saber", "kit": "allied_vm", "at": {"site": "@town"}},
			{"kind": "mortar_section", "groups": 1, "vehicles": ["mortar_m224"], "crew": 1, "men": 0, "callsign": "Mortar", "kit": "allied_vm", "at": {"site": "@town"}}],
		"enemy_oob": [{"kind": "weapons_team", "groups": 1, "men": 2, "bands": ["keep"], "callsign": "Mortar", "kit": "rifles"}]},
	"beach_landing": {
		"friendly_oob": [{"kind": "rifle_squad", "groups": 2, "men": 3, "callsign": "Saber", "kit": "allied_us", "carrier": "aav"},
			{"kind": "rifle_squad", "groups": 1, "men": 3, "callsign": "Lancer", "kit": "allied_us", "carrier": "aav", "wave": 4}],
		"enemy_oob": [{"kind": "gun_team", "groups": 1, "men": 2, "bands": ["outposts"], "callsign": "Anvil", "kit": "mg", "known": true}]},
}

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var ops: Operations
var cid := ""
var zone_id := ""
var front := {}  # op type -> its front zone
var _hosted := false
var _client_in := false
var _client_left := false
var _acks := {}
var _host_digest := {}
var _war := []  # [sites, war]: the war as the offers left it


static func _door_file() -> String:
	return "user://optypes_test_door%s_%d.txt" % [OS.get_environment("CONTRACTOR_TEST_TAG"), Net.port()]


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_optypes" + tag
	Campaign.campaign_id = "test_optypes" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	Contracts.autosave = false
	var args := OS.get_cmdline_user_args()
	get_tree().create_timer(1650.0, true, false, true).timeout.connect(func() -> void:
		print("OPTYPES TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--optypes-join" in args:
		await _run_client(args[args.find("--optypes-join") + 1] if args.find("--optypes-join") + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		DirAccess.remove_absolute(_door_file())
		await _run_host("--optypes-host" in args)


func check(condition: bool, what: String) -> void:
	if not is_inside_tree():
		return
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while is_inside_tree() and not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return is_inside_tree() and condition.call()


func _finish() -> void:
	GameState.delete_save()
	if not "--optypes-join" in OS.get_cmdline_user_args():
		var done := FileAccess.open(_door_file(), FileAccess.WRITE)  # (a client still waiting for the door gives up)
		if done:
			done.store_string("closed")
			done.close()
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		for t: String in ORDER:
			Operations.unregister_type(t)
		BaseHub.delete_test_campaign_files()
	print("OPTYPES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _set_rep(faction: String, value: int) -> void:
	var rep: Dictionary = Economy.state().get("rep", {})
	rep[faction] = value
	Economy.state()["rep"] = rep


# --- Host ---------------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	Contracts.new_full_campaign(4242, 600000)
	_set_rep("us_forces", 40)
	_set_rep("vessmark", 40)
	if not _test_offers():
		_finish()
		return
	_test_selectors()
	_war = [Campaign.section(WorldSites.SECTION).duplicate(true), Campaign.section(WorldSites.WAR).duplicate(true)]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	for t: String in ORDER:
		var o: Dictionary = OOB[t]
		var extra := o.duplicate(true)
		if t == "beach_landing":
			var l: Dictionary = (Operations.type_def(t).get("landing", {}) as Dictionary).duplicate(true)
			l["allied_aavs"] = 2
			l["wave2_aavs"] = 1
			extra["landing"] = l
		Operations.register_type(t, extra)
	var only := OS.get_environment("OPTYPES_ONLY").split(",", false)  # (a local look at some of them: the client then isn't let in)
	for t: String in ORDER:
		if not only.is_empty() and not t in only:
			continue
		print("== %s ==" % t)
		if not await _begin(t):
			continue
		match t:
			"phased_invasion":
				await _invasion()
				if wait_for_client:
					await _let_client_in()
			"armoured_thrust":
				await _thrust()
			"seize_crossing":
				await _crossing()
			"hold_town":
				await _town()
			"beach_landing":
				await _landing()
		await _client_ack(t)
		_test_budgets(t)
		await _save_load(t)
		_debrief_and_war(t)
		for pair: Array in [[WorldSites.SECTION, _war[0]], [WorldSites.WAR, _war[1]]]:
			var sec := Campaign.section(pair[0])
			sec.clear()
			sec.merge((pair[1] as Dictionary).duplicate(true))
	if _client_in:
		await _wait_for(func() -> bool: return _client_left, 120.0)
	_finish()


## The offer rules (6.1, 6.4): who posts what, on which front, at what standing.
func _test_offers() -> bool:
	print("Offers: who posts which type where")
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	var inland := ""
	var coast := ""
	for z in WorldSites.war_zones():
		if not String(MissionRegistry.zone(z).get("kind", "")) == "contract" or WorldSites.holder_now(z) in ["us_forces", "", ZoneControl.PLAYER, WorldSites.REBELS]:
			continue
		if not MissionRegistry.faction(WorldSites.holder_now(z)).has("id"):
			continue
		if String(MissionRegistry.zone(z).get("region", "")) == "coast":
			if coast == "" or z < coast:
				coast = z
		elif inland == "" or z < inland:
			inland = z
	check(inland != "" and coast != "", "an inland front (%s) and a coastal one (%s)" % [inland, coast])
	if inland == "" or coast == "":
		return false
	for t: String in ["phased_invasion", "armoured_thrust", "seize_crossing", "hold_town"]:
		front[t] = inland
	front["beach_landing"] = coast
	for z: String in [inland, coast]:
		WorldSites.site(z)["front"] = {"by": "us_forces", "since": Economy.day(), "progress": WorldSites.FRONT_START}
	Campaign.mark_changed(WorldSites.SECTION)
	var us_in := Operations.offered_types("us_forces", inland)
	var us_coast := Operations.offered_types("us_forces", coast)
	var vm := Operations.offered_types("vessmark", inland)
	check("phased_invasion" in us_in and "armoured_thrust" in us_in and not "beach_landing" in us_in,
		"inland the US posts the phased invasion and the armoured thrust, never a beach landing: %s" % [us_in])
	check("beach_landing" in us_coast and "phased_invasion" in us_coast and not "armoured_thrust" in us_coast,
		"on the coast the beach landing and the invasion, never a thrust: %s" % [us_coast])
	check(Array(vm) == ["seize_crossing", "hold_town"], "Vessmark posts its smaller ones, seizing a crossing and holding a town: %s" % [vm])
	check(OpTypes.eligible("beach_landing", inland, "us_forces") != "" and OpTypes.eligible("armoured_thrust", coast, "us_forces") != "",
		"the rules say why: %s; %s" % [OpTypes.eligible("beach_landing", inland, "us_forces"), OpTypes.eligible("armoured_thrust", coast, "us_forces")])
	_set_rep("vessmark", 20)
	check(Operations.offered_types("vessmark", inland).is_empty() and OpTypes.eligible("hold_town", inland, "vessmark").contains("reputation"),
		"under trusted, none: %s" % OpTypes.eligible("hold_town", inland, "vessmark"))
	_set_rep("vessmark", 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var offers := Contracts.operation_offers(rng, Economy.day(), [])
	var vm_ops := offers.filter(func(c: Dictionary) -> bool: return String(c.employer) == "vessmark")
	check(not vm_ops.is_empty() and vm_ops.all(func(c: Dictionary) -> bool: return Operations.is_operation(c) and String(c.op_type) in ["seize_crossing", "hold_town"]),
		"Vessmark's offer beside a US front is a real operation now (D7's stand-in retired): %s" % [vm_ops.map(func(c: Dictionary) -> String: return String(c.title))])
	var beach := offers.filter(func(c: Dictionary) -> bool: return String(c.get("op_front", "")) == coast and String(c.employer) == "us_forces")
	check(not beach.is_empty() and String(beach[0].op_type) in us_coast, "the coast's US front posts one of its coast types (%s)" % (String(beach[0].op_type) if not beach.is_empty() else "none"))
	for t: String in ORDER:
		var def := Operations.type_def(t)
		var shares := 0.0
		for p: Dictionary in def.get("phases", []):
			shares += float(p.pay_share)
		check(bool(def.get("offer", false)) and is_equal_approx(shares, 1.0) and Operations.hook(t, "start").is_valid() and Operations.hook(t, "task").is_valid(),
			"%s: on offer, $%s base, H-hour %s, %d phases whose shares make the whole, its hooks registered" % [t, DebriefCalc.money(def.base_pay), String(def.h_hour), (def.phases as Array).size()])
	check(OpTypes.wave_men("hold_town") == 34 and OpTypes.wave_men("phased_invasion") == 0, "a type's counterattack waves count toward its rating (holding a town: %d men)" % OpTypes.wave_men("hold_town"))
	return true


## The selectors the types add (beach exits, banks, the harbour, the firing point) on generated zones.
func _test_selectors() -> void:
	print("Site selectors")
	var beach := OperationGen.generate(77, "beach_landing", [front.beach_landing])
	var l := OpTypes.resolve_extra(beach, {"exit": "left"})
	var r := OpTypes.resolve_extra(beach, {"exit": "right"})
	check(l.size() == 1 and r.size() == 1 and OperationGen.across(beach, Vector2(l[0].pos[0], l[0].pos[1])) > OperationGen.across(beach, Vector2(r[0].pos[0], r[0].pos[1]))
		and OperationGen.band_at(beach, Vector2(l[0].pos[0], l[0].pos[1])) == "start", "two beach exits in the start band, the left one left of the axis")
	var h := OpTypes.resolve_extra(beach, {"site": "@harbour"})
	check(h.size() == 1 and String(h[0].module_id) != "", "the harbour (or the coastal village): %s" % (String(h[0].module_id) if not h.is_empty() else "none"))
	var land := OperationGen.generate(78, "seize_crossing", [front.seize_crossing])
	var fp := OpTypes.firing_point(land)
	var x := OpTypes.crossing(land)
	var river := float(land.op.river_at_m)
	check(fp.is_finite() and OperationGen.along(land, fp) > river + 100.0 and Vector2(float(x.pos[0]), float(x.pos[1])).distance_to(fp) < 260.0,
		"the firing point on the far bank, %.0f m past the river, %.0f m from the bridge" % [OperationGen.along(land, fp) - river, Vector2(float(x.pos[0]), float(x.pos[1])).distance_to(fp)])
	var near := OpTypes.resolve_extra(land, {"bank": "near"})
	var far := OpTypes.resolve_extra(land, {"bank": "far"})
	check(OperationGen.along(land, Vector2(near[0].pos[0], near[0].pos[1])) < river and OperationGen.along(land, Vector2(far[0].pos[0], far[0].pos[1])) > river, "the near and far banks either side of the river")
	var built := Operations.build_phases(beach, "beach_landing")
	check(built.size() == 3 and String(built[0].tasks[0].text).contains("left beach exit") and String(built[2].tasks[0].kind) == Operations.HOLD_LINE,
		"the beach landing's phases resolve: %s" % [built.map(func(p: Dictionary) -> String: return String(p.tasks[0].text) if not (p.tasks as Array).is_empty() else "")])


## Offered, taken, its zone, deployed and hosted, its run started.
func _begin(t: String) -> bool:
	var zone := String(front[t])
	var employer := "vessmark" if t in ["seize_crossing", "hold_town"] else "us_forces"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([t, 5])
	var offer := Operations.make_offer(rng, Economy.day(), zone, "us_forces", WorldSites.holder_now(zone), employer, t)
	check(not offer.is_empty() and Operations.is_operation(offer) and String(offer.op_type) == t and int(offer.base_pay) > 0,
		"%s offered by %s at %s: %s, $%s" % [t, employer, zone, String(offer.get("title", "")), DebriefCalc.money(offer.get("base_pay", 0))])
	if offer.is_empty():
		return false
	var c := Contracts._add_offer(offer)
	cid = String(c.cid)
	zone_id = String(c.op_zone)
	var cash := Economy.cash()
	check(Contracts.server_accept(cid, ContractGen.default_terms()) == "", "taken")
	var d: Dictionary = Contracts.contract(cid).deal
	check(int(d.advance) == roundi(int(d.pay_total) * 0.2) and Economy.cash() - cash == int(d.advance), "20%% on signing ($%s)" % DebriefCalc.money(d.advance))
	var zdef := MissionRegistry.zone_def(zone_id)
	check(OperationGen.is_operation(zdef) and String(zdef.op_type) == t and is_equal_approx(float(zdef.size_m), 8192.0) and String(zdef.controller) == String(c.target),
		"its zone %s: 8 km, a %s, the target %s holding it" % [zone_id, t, zdef.controller])
	match t:
		"beach_landing":
			check(bool(zdef.op.coast) and String(zdef.op.fob) == "" and absf(float(c.get("hour", -1.0)) - 4.5) < 0.01, "on the coast, no FOB (the LHD stands off), the deployment at %.1f h before dawn" % float(c.get("hour", -1.0)))
		"hold_town":
			var at := Operations.resolve(zdef, {"site": "@town"})
			var ins: Array = zdef.insertion[0]
			check(String(zdef.op.town) == "city" and not at.is_empty() and Vector2(float(ins[0]), float(ins[1])).distance_to(Vector2(float(at[0].pos[0]), float(at[0].pos[1]))) < 900.0,
				"a city (D1-12), the company inserting in it, %.0f m from its centre" % Vector2(float(ins[0]), float(ins[1])).distance_to(Vector2(float(at[0].pos[0]), float(at[0].pos[1]))))
		"seize_crossing":
			check(not OpTypes.crossing(zdef).is_empty() and String(OpTypes.crossing(zdef).kind) == ZoneBridges.CONCRETE, "the MSR's concrete bridge on its river")
	if not _hosted:
		check(Contracts.server_start_deployment([cid], zone_id) == "", "deployed")
		main.host_zone(BaseHub.contract_level_info(Contracts.contract(cid)).def)
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
		_hosted = true
	else:
		check(Contracts.server_start_deployment([cid], zone_id) == "", "deployed")
		BaseHub.server_switch_level(BaseHub.contract_level_info(Contracts.contract(cid)), zone_id)
	var t0 := Time.get_ticks_msec()
	await _wait_for(func() -> bool:
		var lvl := CompoundLevel.current(self) as ZoneLevel
		return lvl != null and String(lvl.def.get("id", "")) == zone_id and lvl.players.get_node_or_null(^"1") != null, 240.0)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and String(level.def.get("id", "")) == zone_id, "hosted (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if level == null or String(level.def.get("id", "")) != zone_id:
		return false
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	ops = Operations.of(level)
	await _wait_for(func() -> bool: return ops != null and ops.active(), 30.0)
	check(ops != null and ops.active() and ops.get_node_or_null(OpTypes.MECHANIC) != null and ops.get_node_or_null(OpSupport.NODE_NAME) != null,
		"its run is on, with its own mechanic (%s) and the support every type has" % (ops.get_node(OpTypes.MECHANIC).get_script().get_global_name() if ops and ops.get_node_or_null(OpTypes.MECHANIC) else "none"))
	return ops != null and ops.active()


func _sup() -> OpSupport:
	return ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport


func _mech() -> OpBase:
	return ops.get_node_or_null(OpTypes.MECHANIC) as OpBase


func _run() -> Dictionary:
	return Operations.run_of(Contracts.contract(cid))


func _task_pos(k: int, i := 0) -> Vector3:
	var c := Contracts.contract(cid)
	var t: Dictionary = (c.phases[k] as Dictionary).tasks[i]
	return level.ground_point(Vector3(float(t.pos[0]), 0, float(t.pos[1])))


## The player on phase `k`'s task: seized after the hold (D3's seize_site).
func _take(k: int, at := Vector3.INF) -> bool:
	player.global_position = at if at.is_finite() else _task_pos(k)

	ops.server_advance(Operations.knob("run", "seize_hold_s", 60.0) + 6.0)
	var run := _run()
	var rec: Dictionary = run.phases[k]
	var paid_in := Economy.ledger().slice(-8).filter(func(e: Dictionary) -> bool: return String(e.what).contains("phase %d (" % (k + 1)))
	check(String(rec.state) == Operations.DONE and int(rec.pay) > 0 and not paid_in.is_empty() and int((paid_in.back() as Dictionary).get("amount", 0)) == int(rec.pay),
		"phase %d done on its task, $%s into the bank, a ledger line of its own (%s)" % [k + 1, DebriefCalc.money(rec.get("pay", 0)), (rec.get("lines", []) as Array).map(func(l: Dictionary) -> String: return String(l.text))])
	return String(rec.state) == Operations.DONE


# --- The phased invasion (D4) -------------------------------------------------------------------------

func _invasion() -> void:
	var sup := _sup()
	ops.server_advance(1.0)
	var run := _run()
	check(String(run.state) == Operations.RUNNING and int(run.phase) == 0, "H-hour now: phase 1 runs")
	# Attached armour.
	ops.server_advance(4.0)
	var att := sup.attached()
	var v := sup.vehicle_of(String(att[0].id)) if not att.is_empty() else null
	check(att.size() == 2 and String(att[0].model) == "abrams" and String(att[0].state) == "live" and v != null,
		"the Abrams section is attached to the company and out at the start line (%s)" % [att.map(func(e: Dictionary) -> String: return "%s %s" % [e.callsign, e.state])])
	if v:
		var crew := v.occupants().filter(func(s: Soldier) -> bool: return s.has_meta(&"vehicle_crew"))
		var commander := OpSupport._seat_of_kind_any(v, Vehicle.COMMANDER)
		check(crew.size() == 3 and v.occupant(commander) == null, "crewed by the allies (driver, gunner, loader: %d), the commander's hatch left for a player" % crew.size())
		var ow := sup.overwatch_point(0)
		var task := _task_pos(0)
		var axis := ops._axis()
		check(ow.is_finite() and OperationGen.along(ops.def, Vector2(ow.x, ow.z)) < OperationGen.along(ops.def, Vector2(task.x, task.z)) and is_instance_valid(v.ai) and v.ai.active,
			"following the company's task: on its way to overwatch %.0f m short of it on our side" % Vector2(ow.x - task.x, ow.z - task.z).length())
		# A player takes its gun.
		v.server_enter(player, commander)
		check(sup.server_take_gun(player) == "", "a player aboard takes its gun")
		await _wait_for(func() -> bool: return v.occupant(int(v.spec.gun.seat)) == player, 15.0)
		await _frames(5)
		ops.server_advance(2.0)
		check(v.occupant(int(v.spec.gun.seat)) == player and v.occupant(commander) != null and v.occupant(commander).has_meta(&"vehicle_crew"),
			"on the gun, its AI gunner moved to his seat")
		check(sup.server_give_gun(player) == "", "and gives it back")
		await _wait_for(func() -> bool: return v.occupant(int(v.spec.gun.seat)) != player, 15.0)
		await _frames(5)
		ops.server_advance(2.0)
		var g := v.occupant(int(v.spec.gun.seat))
		check(g != null and g.has_meta(&"vehicle_crew"), "its gunner back on the gun")
		v.server_exit(player)
		check(sup.server_order(player, OpSupport.HOLD, Vector3.INF) == "" and String(sup.attached()[0].order) == OpSupport.HOLD, "the company's orders reach it (hold)")
		sup.server_order(player, OpSupport.FOLLOW_TASK, Vector3.INF)
	# Allied fires.
	var fs := FireSupport.of(level)
	var preps := fs.rounds.filter(func(r: Dictionary) -> bool: return bool(r.get("allied", false)))
	check(not preps.is_empty() and sup.fires_left("artillery") < int((Contracts.contract(cid).allied_fires as Dictionary).artillery),
		"preparation fires on phase 1's objectives (%d rounds on the way; %d artillery left)" % [preps.size(), sup.fires_left("artillery")])
	var far := level.ground_point(_task_pos(2) + Vector3(0, 0, 0))
	var before := fs.rounds.size()
	check(sup._cmd_op_fire(player, "artillery", far, PackedStringArray()) == "" and fs.rounds.size() > before, "the company calls the employer's guns there (%d rounds)" % (fs.rounds.size() - before))
	var again := sup._cmd_op_fire(player, "artillery", far, PackedStringArray())
	check(again.contains("again"), "not again before its cooldown: %s" % again)
	var close := sup.fire("mortar", player.global_position, 3, "he", "test")
	check(close.contains("friendlies") or close.contains("range"), "never danger close to friendlies: %s" % close)
	var smoke0 := fs.rounds.filter(func(r: Dictionary) -> bool: return String(r.shell) == "smoke").size()
	ops.friendly.fire_support_wanted.emit(far, "smoke on the outpost's ports for the breach")
	check(fs.rounds.filter(func(r: Dictionary) -> bool: return String(r.shell) == "smoke").size() > smoke0, "the allied commander's call for smoke is fired (B2's fire_support_wanted)")
	# The employer's Dustoff.
	var cash := Economy.cash()
	check(Economy.server_pay_support("medevac", cid) and Economy.cash() == cash and int(sup.mine().medevac_left) == 1, "the company's medevac call is on the employer's Dustoff (1 of 2 left)")
	# The fuel truck, at the logistics point.
	await _wait_for(func() -> bool: return (_run().oob as Array).any(func(e: Dictionary) -> bool: return String(e.get("logistics", "")) != "" and String(e.state) == "live"), 90.0)
	ops.server_advance(61.0)
	await _wait_for(func() -> bool: return (_run().oob as Array).any(func(e: Dictionary) -> bool: return String(e.get("logistics", "")) != "" and String(e.state) == "live"), 30.0)
	var truck: Vehicle = null
	for e: Dictionary in _run().oob:
		if String(e.get("logistics", "")) == "fuel" and String(e.state) == "live":
			truck = (ops.records[String(e.id)].vehicles as Array)[0]
	check(truck != null, "the fuel truck came up behind the start line")
	if truck and v:
		var lp := sup.logistics_point()
		truck.global_position = lp + Vector3.UP * 0.5
		v.global_position = lp + Vector3(8, 0.6, 0)
		v.fuel = 50.0
		await _frames(3)
		ops.server_advance(4.0)
		check(v.fuel > 50.0, "at the logistics point it refuels the attached armour (%.0f l)" % v.fuel)
	# The phases, on their tasks; the commander alive.
	for k in 3:
		_take(k)
	run = _run()
	check(int(run.phase) == 3, "phases 1-3 done; PL STEEL begins")
	var inv := _mech() as OpInvasion
	check(inv.commander != null and is_instance_valid(inv.commander) and inv.commander.has_meta(OpInvasion.COMMANDER_META), "the HQ's commander is at the HQ")
	if inv.commander:
		inv.commander.vitals.downed = true
		player.global_position = inv.commander.global_position + Vector3(2, 0, 0)
		ops.server_advance(2.0)
		var alive := Contracts.objectives.for_contract(cid).filter(func(o: Dictionary) -> bool: return String(o.kind) == OpInvasion.TAKE_ALIVE)
		check(not alive.is_empty() and String(alive[0].state) == Objectives.DONE, "taken down alive and secured: the bonus task done")
	_take(3, _task_pos(3))
	var rec4: Dictionary = _run().phases[3]
	check((rec4.get("lines", []) as Array).any(func(l: Dictionary) -> bool: return String(l.text).contains("commander")), "phase 4 pays its commander bonus")
	check(String(_run().state) == Operations.DONE, "every phase done")


# --- The armoured thrust (D4) -------------------------------------------------------------------------

func _thrust() -> void:
	var th := _mech() as OpThrust
	ops.server_advance(2.0)
	check(String(_run().state) == Operations.WAITING, "H-hour waits for the company to cross the line of departure")
	var start := level.ground_point(ops._v3(ops.def.op.start))
	var axis := Vector3(ops._axis().x, 0, ops._axis().y)
	player.global_position = level.ground_point(start + axis * (OperationGen.band_range(ops.def, "start").y - OperationGen.along(ops.def, Vector2(start.x, start.z)) + 100.0))
	ops.server_advance(2.0)
	check(String(_run().state) == Operations.RUNNING, "across it: H-hour")
	player.global_position = start
	await _wait_for(func() -> bool: return th.column().size() >= 4, 90.0)
	ops.server_advance(3.0)
	var vs := th.column()
	check(vs.size() >= 4 and vs.any(func(v: Vehicle) -> bool: return v.has_meta(OpSupport.ATTACHED_META)), "the column: the allied armour and the attached Bradleys (%d vehicles)" % vs.size())
	var halt := th.halt_point(0)
	var bp := th.position_of(0)
	check(halt.is_finite() and OperationGen.along(ops.def, Vector2(halt.x, halt.z)) < OperationGen.along(ops.def, Vector2(bp.x, bp.z)) and vs.all(func(v: Vehicle) -> bool: return is_instance_valid(v.ai) and v.ai.active),
		"down the axis to halt %.0f m short of the first blocking position" % Vector2(halt.x - bp.x, halt.z - bp.z).length())
	for i in vs.size():  # (as if they drove there)
		vs[i].global_position = th._on_msr(halt - axis * 30.0 * i) + Vector3.UP * 0.6
		vs[i].server_stop()
	await _frames(3)
	ops.server_advance(3.0)
	check((th.mine().halted_at as Dictionary).has("0"), "halted short of it: it won't drive through an uncleared position")
	_take(0)
	ops.server_advance(3.0)
	check(int(th.mine().get("went_for", -1)) == 0 and String(_run().state) == Operations.RUNNING, "position clear: the column waits for the company to mount")
	var bradley: Vehicle = null
	for v: Vehicle in th.column():
		if v.has_meta(OpSupport.ATTACHED_META):
			bradley = v
	var seated := bradley.server_enter(player, -1) if bradley else false  # (the host's player only: the client's may still be loading the zone)
	ops.server_advance(3.0)
	var halt2 := th.halt_point(1)
	if ops._players().size() > 1:
		check(int(th.mine().get("went_for", -1)) == 0, "one player of %d aboard: the column still waits" % ops._players().size())
		th.mine().cleared_at = float(_run().clock_s) - th.num("column", "wait_mount_s", 90.0) - 1.0  # (as if the wait were over)
		ops.server_advance(3.0)
		check(int(th.mine().get("went_for", -1)) == 1 and Vehicle.ride_of(player) == bradley, "the wait over: it moves on for the second position (%s) [%s, went_for %d, seated %s]"
			% [ops._grid_ref(halt2), String(_run().state), int(th.mine().get("went_for", -1)), seated])
	else:
		check(int(th.mine().get("went_for", -1)) == 1 and Vehicle.ride_of(player) == bradley, "everyone aboard: it moves on for the second position (%s) [%s, went_for %d, seated %s]"
			% [ops._grid_ref(halt2), String(_run().state), int(th.mine().get("went_for", -1)), seated])
	if bradley:
		bradley.server_exit(player)
	var why := th.server_bypass(player)
	if why == "":
		check(String(_run().phases[1].state) == Operations.DONE and "1" in (th.mine().bypassed as Array) and ops.grid.owner_at(Vector2(th.position_of(1).x, th.position_of(1).z)) == FrontGrid.HOSTILE,
			"bypassed off-road: the position counts passed, its ground left to the enemy behind the front")
	else:
		check(why.contains("ground"), "a bypass the ground won't take is refused: %s" % why)
	var limit := th.num("column", "time_limit_min", 45.0) * 60.0
	var shift := maxf(limit - float(_run().clock_s), 0.0)  # (as if the thrust had been under way that long: the clock on, the phase begun as long ago)
	_run().clock_s = float(_run().clock_s) + shift
	for rec: Dictionary in _run().phases:
		if rec.has("started_s"):
			rec.started_s = float(rec.started_s) + shift
	_run().hhour_s = float(_run().clock_s) - limit + 3.0
	ops.server_advance(OpThrust.TICK_S * 3.0 + 2.0)
	check(String(_run().state) == Operations.STALLED and (_run().get("notes", []) as Array).any(func(n: String) -> bool: return n.contains("ran out of time")),
		"the 45 minutes run out with the depth target not taken: it stalls [%s, %.0f s of %.0f, notes %s]" % [String(_run().state), float(_run().clock_s) - float(_run().hhour_s), limit, str(_run().get("notes", []))])


# --- Seizing a crossing (D5) ---------------------------------------------------------------------------

func _crossing() -> void:
	var cr := _mech() as OpCrossing
	var m := cr.mine()
	var demo := Demolitions.of(level)
	check((m.charges as Array).size() == 3 and (m.charges as Array).all(func(id: Variant) -> bool: return demo.records.has(String(id))) and int(m.bridge) >= 0,
		"three demo blocks under the bridge's middle span, live on a firing device")
	var fp := cr.firing_pos()
	var eng: Array = (_run().oob as Array).filter(func(e: Dictionary) -> bool: return String(e.kind) == "engineers")
	check(not eng.is_empty() and Vector2(float(eng[0].pos[0]) - fp.x, float(eng[0].pos[1]) - fp.z).length() < 2.0 and (m.wire as Array).size() == 2,
		"wired to the firing point on the far bank where its engineers stand; two cut points on the wire")
	var markers := MapNodes.markers(level)
	check(markers and markers.list("intel").filter(func(x: Dictionary) -> bool: return String(x.text).begins_with("Firing wire")).size() == 2, "the cut points marked on the map")
	var axis := Vector3(ops._axis().x, 0, ops._axis().y)
	var bridge := level.ground_point(ops._v3(OpTypes.crossing(ops.def).pos))
	player.global_position = level.ground_point(bridge - axis * 1500.0)
	ops.server_advance(5.0)
	check(String(m.state) == OpCrossing.ARMED, "far off, they don't see us")
	# H-hour (the player across the line), phase 1 on its checkpoint.
	var start := level.ground_point(ops._v3(ops.def.op.start))
	player.global_position = level.ground_point(start + axis * (OperationGen.band_range(ops.def, "start").y - OperationGen.along(ops.def, Vector2(start.x, start.z)) + 100.0))
	ops.server_advance(2.0)
	_take(0)
	player.global_position = level.ground_point(fp - axis * 300.0)
	ops.server_advance(3.0)
	check(String(m.state) == OpCrossing.COUNTING and float(m.fuse_at) - float(_run().clock_s) <= cr.num("crossing", "fuse_s", 90.0), "a friendly within reach: the firing team's fuse starts (%.0f s)" % (float(m.fuse_at) - float(_run().clock_s)))
	check(OperationStrip.strip_text(ops.view, ops.clock_now()).contains("Bridge:") or String(ops.view.get("special", "")).contains("Bridge"), "the strip says so: %s" % String(ops.view.get("special", "")))
	ops.server_advance(20.0)
	check(String(m.state) == OpCrossing.COUNTING, "still counting")
	var not_there := cr.server_cut(player)
	var w: Array = m.wire[1]
	player.global_position = level.ground_point(Vector3(float(w[0]), 0, float(w[1])))
	check(not_there.contains("firing wire") and cr.server_cut(player) == "" and String(m.state) == OpCrossing.CUT, "at a cut point the company cuts the firing wire: the bridge is safe")
	ops.server_advance(cr.num("crossing", "fuse_s", 90.0))
	check(not cr.bridge_down(), "its fuse runs out and nothing happens")
	# Phase 2: the bridge and the far bank, intact.
	var far := level.ground_point(ops._v3(OpTypes.resolve_extra(ops.def, {"bank": "far"})[0].pos))
	_take(1, bridge.lerp(far, 0.5))
	var rec: Dictionary = _run().phases[1]
	check((rec.lines as Array).any(func(l: Dictionary) -> bool: return String(l.text).contains("intact") and int(l.amount) >= roundi(int(rec.base) * 0.39)), "the bridge intact pays its +40%")
	ops.server_advance(4.0)
	await _wait_for(func() -> bool: return (_run().oob as Array).any(func(e: Dictionary) -> bool: return String(e.kind) == "armour_section" and String(e.state) == "live"), 60.0)
	player.global_position = bridge.lerp(far, 0.5)
	ops.server_advance(65.0)
	var moving := false
	for e: Dictionary in _run().oob:
		if String(e.kind) == "armour_section" and String(e.state) == "live":
			for v: Variant in ops.records[String(e.id)].vehicles:
				moving = moving or (is_instance_valid(v) and (v as Vehicle).get_meta(&"op_crossing", false))
	check(moving, "phase 3: the allied armour drives across")
	check((cr.mine().get("waves", {}) as Dictionary).size() >= 1, "and the enemy counterattacks the crossing (%d wave)" % (cr.mine().get("waves", {}) as Dictionary).size())
	# Had they fired it: the charges drop the span, and the armour goes by the ford.
	m.state = OpCrossing.ARMED
	cr._blow("(test: fired)")
	await _frames(3)
	check(cr.bridge_down() and String(m.state) == OpCrossing.BLOWN and (_run().notes as Array).any(func(n: String) -> bool: return n.contains("was blown")), "fired, its charges drop the middle span")
	var b := ops._bridges()
	check(b.bridge_mlc(int(m.bridge)) == 0.0, "the column's roads leave it out: the armour goes by the ford")
	player.global_position = bridge
	ops.server_advance(cr.num("crossing", "hold_fail_s", 60.0) + 1.0)
	check(String(_run().state) == Operations.RUNNING, "while we hold a bank it isn't lost")
	var hold_at := _task_pos(2)
	for md: Dictionary in ops.def.get("modules", []):  # (the sites by the bridge cleared: this suite's zones spawn no garrisons)
		var mp := Vector2(float(md.pos[0]), float(md.pos[1]))
		if mp.distance_to(Vector2(hold_at.x, hold_at.z)) < 400.0 and not String(md.id) in (_run().taken as Array):
			(_run().taken as Array).append(String(md.id))
	for i in 90:  # (the counterattack and any infiltrators kept out of it, as if beaten off)
		if String(_run().state) != Operations.RUNNING:
			break
		_clear_hostiles(hold_at, 900.0)
		var moved := ops.grid.set_cells(ops.grid.cells_within(Vector2(hold_at.x, hold_at.z), 200.0), FrontGrid.FRIENDLY)  # (its ground ours again once they're beaten off)
		if not moved.is_empty():
			ops._front_moved(moved)
		ops.server_advance(10.0)
		if i % 9 == 0:
			print("    (holding: owner %d, hostiles near %d, %s)" % [ops.grid.owner_at(Vector2(hold_at.x, hold_at.z)), ops._hostiles_near(hold_at, 200.0, ""), _tasks_text(2)])
	check(String(_run().state) == Operations.DONE, "the crossing held for its minutes: every phase done [%s, phase %d: %s]" % [String(_run().state), int(_run().phase), _tasks_text(2)])


# --- Holding a town (D5) --------------------------------------------------------------------------------

func _town() -> void:
	var town := _mech() as OpTown
	ops.server_advance(1.0)
	var c := town.centre()
	var r := _run()
	check((r.taken as Array).any(func(id: String) -> bool: return id.begins_with("city")) and ops.grid.owner_at(Vector2(c.x, c.z)) == FrontGrid.FRIENDLY,
		"the town is ours at the start: its blocks taken, its cells ours")
	var ins := level.insertion_points()[0]
	check(Vector2(ins.x - c.x, ins.z - c.z).length() < 900.0, "the company inserts in the town (%.0f m from its centre)" % Vector2(ins.x - c.x, ins.z - c.z).length())
	await _wait_for(func() -> bool: return (_run().oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "friendly").all(func(e: Dictionary) -> bool: return String(e.state) == "live"), 60.0)
	var garrison := true
	for e: Dictionary in _run().oob:
		if String(e.side) == "friendly":
			garrison = garrison and Vector2(float(e.pos[0]) - c.x, float(e.pos[1]) - c.z).length() < 400.0
	check(garrison, "the allied platoon and its mortars stand in the town with the company")
	player.global_position = c
	var kinds := ["sandbags", "hesco", "wire", "sandbags", "hesco", "sandbags"]
	var placed := 0
	for i in kinds.size():
		if town.server_place(kinds[i], c + Vector3(-15.0 + 6.0 * i, 0, 0), 0.0, player) == "":
			placed += 1
	check(placed == 6 and town.pieces().size() == 6, "six pieces of field defences placed from the budget")
	var seventh := town.server_place("sandbags", c + Vector3(30, 0, -30), 0.0, player)
	check(seventh.contains("budget"), "a seventh is refused: %s" % seventh)
	town.mine().pieces.pop_back()
	var too_far := town.server_place("wire", c + Vector3(400, 0, 0), 0.0, player)
	check(too_far.contains("Too far"), "and one too far from the centre: %s" % too_far)
	town.server_place("sandbags", c + Vector3(15, 0, 0), 0.0, player)
	await _frames(2)
	var bodies := get_tree().get_nodes_in_group(OpTown.NODE_GROUP)
	check(bodies.size() == 6, "each a solid piece in the world (%d)" % bodies.size())
	var p0: Dictionary = town.pieces()[0]
	var at := Vector3(float(p0.pos[0]), float(p0.pos[1]) + 0.5, float(p0.pos[2]))
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0, -1.5), at + Vector3(0, 0, 1.5), 1))
	check(not hit.is_empty() and (hit.collider as Node).is_in_group(OpTown.NODE_GROUP), "cover that stops a line through it")
	# What the enemy sees, and the axis it picks round it.
	var response := EnemyResponse.of(level)
	var sq := response._new_squad("Scout")
	var scout: Array = response._spawn_team(sq, "OptScout", 1, at + Vector3(-40, 0, 0), at, CompoundLevel.HOSTILE_LOADOUT.duplicate(), 0.5, 0.5, "aware")
	await _frames(3)
	town._look()
	check(bool((town.pieces()[0] as Dictionary).seen) and not bool((town.pieces()[5] as Dictionary).seen),
		"an enemy in sight of a piece sees it, not the one hidden behind the others (%d seen)" % town.seen_points().size())
	for s: Variant in scout:
		(s as Node).queue_free()
	sq.queue_free()
	await _frames(2)
	var dir := ops._axis()
	var straight := c + Vector3(dir.x, 0, dir.y) * 200.0
	var pick := town.pick_axis(c, dir, [straight, straight + Vector3(5, 0, 0)])
	var pick0 := town.pick_axis(c, dir, [])
	check(int(pick.index) != 1 and pick0 != {}, "its axis goes round what it has seen of the defence (approach %d of 3, not the one through it)" % (int(pick.index) + 1))
	# The prep runs out: phase 2, the waves.
	ops.server_advance(601.0)
	check(int(_run().phase) == 1 and String(_run().phases[0].state) == Operations.DONE, "ten minutes to prepare: phase 1 done, the counterattack comes")
	var late := town.server_place("hesco", c + Vector3(-25, 0, -25), 0.0, player)
	check(late.contains("over"), "no more defences once the prep is over: %s" % late)
	ops.server_advance(35.0)
	check((town.mine().waves as Dictionary).size() == 1, "wave 1 on its way")
	for k in 2:
		for e: Dictionary in _run().oob:
			if String(e.get("wave", "")) != "":
				e.state = "gone"  # (beaten off)
		ops.server_advance(600.0)
	for e: Dictionary in _run().oob:
		if String(e.get("wave", "")) != "":
			e.state = "gone"
	check((town.mine().waves as Dictionary).size() == 3 and int(_sup().mine().get("enemy_fired", 0)) > 0, "three waves, the second with its technical and its mortar first (%d rounds)" % int(_sup().mine().get("enemy_fired", 0)))
	ops.server_advance(5.0)
	check(String(_run().state) == Operations.DONE, "every wave beaten off: the centre held, every phase done")


# --- The beach landing (D5) ------------------------------------------------------------------------------

func _landing() -> void:
	var la := _mech() as OpLanding
	var dn := DayNight.current()
	check(dn != null and absf(dn.hour - 4.5) < 0.3, "the deployment starts before dawn (%.2f h)" % (dn.hour if dn else -1.0))
	var lhd := Lhd.of(level)
	check(lhd != null and lhd.is_ship(), "the LHD stands off the coast")
	ops.server_advance(28.0)
	var waves := la.waves()
	var w1 := waves.filter(func(a: Dictionary) -> bool: return int(a.wave) == 1)
	var out := w1.filter(func(a: Dictionary) -> bool: return String(a.state) == "afloat")
	check(w1.size() == 4 and out.size() == 4, "wave 1 out of the well deck: %d AAVs afloat" % out.size())
	var mine := w1.filter(func(a: Dictionary) -> bool: return String(a.role) == "company")
	var aav := la.aav_of(String(mine[0].id)) if not mine.is_empty() else null
	check(aav != null and Vehicle.ride_of(player) != null and (Vehicle.ride_of(player).get_meta(&"op_aav", "") as String) != "",
		"the company starts in its AAVs: the player aboard %s" % (String(Vehicle.ride_of(player).get_meta(&"op_aav", "")) if Vehicle.ride_of(player) else "none"))
	var terrain := level.terrain
	if aav:
		var p := aav.global_position
		check(terrain.water_height(p.x, p.z) > terrain.height_at(p.x, p.z) and is_instance_valid(aav.ai) and aav.ai.active, "afloat at the stern, swimming for the beach")
	var allied := w1.filter(func(a: Dictionary) -> bool: return String(a.role) == "allied")
	var aboard := 0
	for a: Dictionary in allied:
		var v := la.aav_of(String(a.id))
		if v:
			aboard += v.occupants().filter(func(s: Soldier) -> bool: return s.has_meta(&"op_allied") and not s.has_meta(&"vehicle_crew")).size()
	check(aboard >= 6, "the allied squads aboard theirs (%d men)" % aboard)
	check(String(_run().state) == Operations.WAITING, "H-hour is still to come")
	var fs := FireSupport.of(level)
	ops.server_advance(la.num("landing", "lead_s", 600.0) - la.num("landing", "prep_s", 120.0) - float(_run().clock_s) + 2.0)
	var preps := fs.rounds.filter(func(r: Dictionary) -> bool: return String(r.unit) in ["allied_artillery", "naval_gun"])
	check(bool(la.mine().prep) and not preps.is_empty(), "two minutes before H-hour, the artillery and naval gunfire on the known beach defences (%d rounds)" % preps.size())
	var w2 := waves.filter(func(a: Dictionary) -> bool: return int(a.wave) == 2)
	ops.server_advance(5.0)
	check(not w2.is_empty() and w2.all(func(a: Dictionary) -> bool: return String(a.state) == "afloat"), "wave 2 follows four minutes later")
	# Wave 1 hits the beach (put on its lane's sand, as if it swam in).
	for a: Dictionary in w1:
		var v := la.aav_of(String(a.id))
		if v:
			var end: Array = a.path[1]
			v.global_position = level.ground_point(Vector3(float(end[0]), 0, float(end[1]))) + Vector3.UP * 0.8
			v.server_stop()
	await _frames(3)
	ops.server_advance(2.0)
	check(int(la.mine().landed) >= 1 and String(_run().state) == Operations.RUNNING and int(_run().phase) == 0, "the waves land: H-hour, phase 1 runs")
	var dismounted := true
	for a: Dictionary in allied:
		var v := la.aav_of(String(a.id))
		if v:
			dismounted = dismounted and v.occupants().all(func(s: Soldier) -> bool: return s.has_meta(&"vehicle_crew") or not s.is_ai())
	check(dismounted and Vehicle.ride_of(player) != null, "ramps down: the AI out, the players get out themselves")
	if Vehicle.ride_of(player):
		Vehicle.ride_of(player).server_exit(player)
	await _client_ack("beach_landing")
	_take(0)
	for o: Dictionary in (Contracts.contract(cid).phases[1] as Dictionary).objectives:  # (the allies take the coastal village)
		ops.plan.taken[String(o.id)] = ops.friendly.now()
	_take(1)
	# Phase 3: the counterattack takes the beachhead back.
	var bh := la.beachhead()
	player.global_position = level.ground_point(bh + Vector3(0, 0, 900))
	for a: Dictionary in waves:  # (the AAVs and their crews off the beach, for the check)
		var v := la.aav_of(String(a.id))
		if v:
			for s: Soldier in v.occupants():
				v.server_exit(s)
				s.queue_free()
			v.queue_free()
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s != player and s.faction == &"friendly" and Vector2(s.global_position.x - bh.x, s.global_position.z - bh.z).length() < 260.0:
			s.queue_free()
	await _frames(3)
	var response := EnemyResponse.of(level)
	var sq := response._new_squad("Breach")
	response._spawn_team(sq, "OptBreach", 2, bh, bh + Vector3(1, 0, 0), CompoundLevel.HOSTILE_LOADOUT.duplicate(), 0.5, 0.5, "aware")
	await _frames(3)
	ops.server_advance(la.num("landing", "hold_fail_s", 60.0) + 3.0)
	check(String(_run().state) == Operations.STALLED and String(_run().phases[2].state) == Operations.FAILED, "the enemy holds the beachhead with none of ours: phase 3 is lost, it stalls")


# --- Common -----------------------------------------------------------------------------------------------

## The enemy's waves and infiltrators gone, and its men within `r` of `at` (as if beaten off).
## Phase `k`'s objectives as "state (progress)", for a failed check's message.
func _tasks_text(k: int) -> String:
	var out := PackedStringArray()
	for o: Dictionary in Contracts.objectives.for_contract(cid):
		if int((o.get("params", {}) as Dictionary).get("phase", -1)) == k:
			out.append("%s %s (%s)" % [String(o.kind), String(o.state), String(o.get("progress", ""))])
	return ", ".join(out)


func _clear_hostiles(at: Vector3, r: float) -> void:
	for e: Dictionary in _run().oob:
		if String(e.side) == "hostile" and (String(e.get("wave", "")) != "" or String(e.callsign).begins_with("Ghost") or String(e.callsign).begins_with("Wave")):
			e.state = "gone"
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"hostile" and s.global_position.distance_to(at) < r:
			s.queue_free()

func _test_budgets(t: String) -> void:
	var slack := Operations.knob("front", "budget_slack", 3.0)
	var budget := float((Operations.data().get("support", {}) as Dictionary).get("budget_ms", 0.5)) * 1000.0
	var mech_budget := float((Operations.data().get("support", {}) as Dictionary).get("mech_budget_ms", 2.0)) * 1000.0
	var m := _mech()
	var s := _sup()
	check(m.worst_us <= mech_budget * slack and s.worst_us <= budget * slack, "%s's ticks: its mechanic %.0f µs at worst (budget %.0f µs), the support %.0f µs (budget %.0f µs; x%.0f allowed)%s" % [t, m.worst_us, mech_budget, s.worst_us, budget, slack,
		" [%s]" % m.worst_what if m.worst_what != "" else ""])


## A save mid-operation and a load: the run and its mechanics' records come back; a new run
## picks the mechanics up where they were.
func _save_load(t: String) -> void:
	ops.server_save_state()
	var before: Dictionary = (_run().get("mech", {}) as Dictionary).duplicate(true)
	check(Campaign.save_campaign() and Campaign.load_campaign(), "%s: the campaign saves and loads mid-operation" % t)
	var after: Dictionary = _run().get("mech", {})
	var keys := func(d: Dictionary) -> Array:
		var out := d.keys()
		out.sort()
		return out
	var same: bool = keys.call(after) == keys.call(before)
	for k: Variant in before:
		same = same and after.get(k) is Dictionary and keys.call(after[k]) == keys.call(before[k])
	check(same, "its mechanics' records came back as saved (%s)" % [before.keys()])
	# A fresh node: what the old one put in the world goes, the new one picks up.
	var sup := _sup()
	for e: Dictionary in sup.attached():
		var v := sup.vehicle_of(String(e.id))
		if v:
			for s: Soldier in v.occupants():
				if s != player:
					s.queue_free()
			if Vehicle.ride_of(player) == v:
				v.server_exit(player)
			v.queue_free()
	for r: Dictionary in ops.records.values():
		for s: Variant in r.get("soldiers", []):
			if is_instance_valid(s):
				(s as Node).queue_free()
		for v: Variant in r.get("vehicles", []):
			if is_instance_valid(v):
				(v as Node).queue_free()
	for n in [ops, ops.friendly, ops.hostile]:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	await _frames(3)
	Operations.install(level, level.def)
	ops = Operations.of(level)
	await _wait_for(func() -> bool: return ops != null and ops.active(), 15.0)
	ops.server_advance(5.0)
	var back := _mech()
	check(ops != null and back != null and keys.call((_run().get("mech", {}) as Dictionary).get(OpTypes.MECHANIC, {})) == keys.call(before.get(OpTypes.MECHANIC, {})),
		"a new run picks its mechanic up (%s)" % back.strip_line() if back else "none")
	match t:
		"phased_invasion":
			check(_sup().attached().all(func(e: Dictionary) -> bool: return String(e.state) in ["live", "lost"]), "the attached armour comes back out where it was")
		"armoured_thrust":
			check(_sup().attached().all(func(e: Dictionary) -> bool: return String(e.state) in [Operations.PENDING, "live", "lost"]) and _mech().mine().has("bypassed"),
				"its attached armour and its column's record come back")
		"hold_town":
			await _frames(2)
			check(get_tree().get_nodes_in_group(OpTown.NODE_GROUP).size() == 6, "the field defences stand again")
		"seize_crossing":
			check(String((back as OpCrossing).mine().state) == OpCrossing.BLOWN, "the bridge's demolition as it was (blown)")
		"beach_landing":
			check((back as OpLanding).waves().size() == 5, "its AAV waves' record as it was")


func _debrief_and_war(t: String) -> void:
	var c := Contracts.contract(cid)
	var done := Operations.phases_done(c)
	var paid := int(Operations.run_of(c).paid)
	var war0: Dictionary = WorldSites.front(String(c.op_front)).duplicate(true)
	var holder0 := WorldSites.holder(String(c.op_front))
	var debrief := Contracts.server_end_deployment({"items": [], "extracted": ["Player 1"], "casualties": []})
	var line: Dictionary = (debrief.get("contracts", [{}]) as Array)[0]
	var want := "completed" if done >= (c.phases as Array).size() else ("partial" if done > 0 else "failed")
	check(String(line.outcome) == want and int(line.paid_at_phases) == paid, "%s's debrief: %s, %d of %d phases, $%s paid as they were done" % [t, want, done, (c.phases as Array).size(), DebriefCalc.money(paid)])
	var summary := DebriefCalc.summary(debrief)
	var own: Array = line.get("notes", [])
	check(not own.is_empty() and Array(summary).any(func(l: String) -> bool: return l.contains(String(own[0]))), "its own lines in the debrief: %s" % " | ".join(PackedStringArray(own.slice(0, 4))))
	var war1 := WorldSites.front(String(c.op_front))
	var moved := WorldSites.holder(String(c.op_front)) != holder0 or float(war1.get("progress", 0.0)) != float(war0.get("progress", 0.0)) or bool(war1.get("sieged", false))
	check(moved or (debrief.get("war", []) as Array).size() > 0, "the war fed: %s" % [debrief.get("war", [])])


# --- The late joiner ---------------------------------------------------------------------------------------

func _let_client_in() -> void:
	print("[host] letting the client in")
	Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
	Net.peer_joined.connect(func(_id: int) -> void: _client_in = true)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	var door := FileAccess.open(_door_file(), FileAccess.WRITE)
	if door:
		door.store_string("open")
		door.close()
	await _wait_for(func() -> bool: return _client_in, 300.0)
	DirAccess.remove_absolute(_door_file())
	check(_client_in, "the client joined late")


## Host: waits (a while) for the client to say it has this type's zone and run.
func _client_ack(t: String) -> void:
	if not _client_in or _client_left or _acks.has(t):
		return
	await _wait_for(func() -> bool: return bool(_acks.get(t, false)) or _client_left, 240.0)
	check(bool(_acks.get(t, false)), "the client got %s's run and its state" % t)
	if not bool(_acks.get(t, false)):
		_client_left = true  # (no more waiting on it)


@rpc("any_peer", "reliable")
func _ack(t: String, fails: int) -> void:
	_acks[t] = true
	if fails > 0:
		print("[host] the client saw %d failures in %s" % [fails, t])


@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var o := Operations.of(self)
	if o == null:
		return {}
	var mech := o.get_node_or_null(OpTypes.MECHANIC) as OpBase
	var sup := o.get_node_or_null(OpSupport.NODE_NAME) as OpBase
	return {"type": String(o.def.get("op_type", "")), "front": o.grid.to_bytes(), "phase": int(o.view.get("phase", -1)), "mech": mech.state if mech else {},
		"support": sup.state if sup else {}}


func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var open_by := Time.get_ticks_msec() + 1300000
	while not FileAccess.file_exists(_door_file()) and Time.get_ticks_msec() < open_by:
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree():
			return
	if FileAccess.get_file_as_string(_door_file()) == "closed":
		check(false, "the host finished without letting the client in")
		_finish()
		return
	var deadline := Time.get_ticks_msec() + 120000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree():
			return
	print("Client joining late")
	multiplayer.server_disconnected.connect(func() -> void: print("[client] the host dropped the connection (%d ms in)" % Time.get_ticks_msec()))
	check(joined[0], "joined the host")
	if not joined[0]:
		_finish()
		return
	for t: String in ORDER:
		var f0 := failures
		var until := Time.get_ticks_msec() + 360000
		var said := 0
		while is_inside_tree() and Time.get_ticks_msec() < until:
			var cur := CompoundLevel.current(self)
			var zl := cur as ZoneLevel if is_instance_valid(cur) else null
			var oo := Operations.of(zl) if zl and zl.is_inside_tree() else null
			if zl and String(zl.def.get("op_type", "")) == t and oo != null and not oo.view.is_empty():
				break
			if Time.get_ticks_msec() > said:
				said = Time.get_ticks_msec() + 20000
				print("[client] waiting for %s: level %s (%s), operations %s, view %s" % [t, String(zl.def.get("id", "")) if zl else "none",
					String(zl.def.get("op_type", "")) if zl else "", "yes" if oo else "no", String(oo.view.get("type", "")) if oo else ""])
			await get_tree().process_frame
		if not is_inside_tree():
			return
		var lvl := CompoundLevel.current(self) as ZoneLevel
		var o := Operations.of(lvl) if lvl else null
		check(o != null and not o.view.is_empty() and String(o.view.get("type", "")) == t, "%s: the zone loaded and the run came (%s)" % [t, OperationStrip.strip_text(o.view, o.clock_now()).replace("\n", " | ") if o else "none"])
		if o == null:
			continue
		var mech := o.get_node_or_null(OpTypes.MECHANIC) as OpBase
		await _wait_for(func() -> bool: return mech != null and not mech.state.is_empty(), 30.0)
		_host_digest = {}
		_ask_digest.rpc_id(1)
		await _wait_for(func() -> bool: return not _host_digest.is_empty(), 20.0)
		check(String(_host_digest.get("type", "")) == t and o.grid.to_bytes() == _host_digest.get("front"), "the same front as the host's")
		await _wait_for(func() -> bool: return mech != null and str(mech.state) == str(_host_digest.get("mech")), 20.0)
		check(mech != null and str(mech.state) == str(_host_digest.get("mech")), "its mechanic's state as the host has it")
		match t:
			"phased_invasion":
				var sup := o.get_node_or_null(OpSupport.NODE_NAME) as OpBase
				check(sup and (sup.state.get("attached", []) as Array).size() == 2, "the attached Abrams section on its view")
			"hold_town":
				await _wait_for(func() -> bool: return get_tree().get_nodes_in_group(OpTown.NODE_GROUP).size() == (mech.state.get("pieces", []) as Array).size(), 20.0)
				check(get_tree().get_nodes_in_group(OpTown.NODE_GROUP).size() == (mech.state.get("pieces", []) as Array).size() and not (mech.state.pieces as Array).is_empty(),
					"the field defences stand on the client too (%d)" % get_tree().get_nodes_in_group(OpTown.NODE_GROUP).size())
			"seize_crossing":
				check(String(mech.state.get("demolition", "")) != "" and (mech.state.get("wire", []) as Array).size() == 2, "the bridge's firing wire and its state (%s)" % String(mech.state.get("demolition", "")))
			"beach_landing":
				var layer := VehicleLayer.of(lvl)
				var seen := (mech.state.get("aavs", []) as Array).filter(func(a: Dictionary) -> bool: return String(a.vid) != "" and layer and layer.find(String(a.vid)) != null).size()
				check(seen >= 1, "the AAVs in the water (%d)" % seen)
		_ack.rpc_id(1, t, failures - f0)
	_finish()
