extends Node
## Operation contracts (docs/combined_arms.md 6.1, 6.3-6.6, 3.5 and 9.3's D3 row; cg_brief queue item
## 3.2): the `operations` suite. Two processes over real ENet, like the world and props suites:
##   <exe> --headless --path . res://tests/operations_test.tscn -- --operations-host
##   <exe> --headless --path . res://tests/operations_test.tscn -- --operations-join 127.0.0.1
## The host checks, in order: the front grid on its own (flips, garrisons, objectives falling,
## consolidation, giving back, the line, replication, saves) and the strip's text; an operation
## offered by a US front to a trusted company (none untrusted; Vessmark's stand-in beside it) and
## taken (20% on signing); its 8 km zone generated from the contract (MissionRegistry.zone_def's
## hook, the controller from the war); then, hosting that zone with the deployment on (new
## connections refused): the run and its commanders (B2's SideCommand: an OperationPlan from the
## phases with its reserve, a DefencePlan over the sites), the OOB coming out within the live caps
## and to their commanders, the enemy's groups waiting by the front's rules, phases advancing on
## their objectives (fast, then late) and paying into the one bank each, the front moving and the
## commander's phase with it, the line on the map, a save and load mid-operation; then lets a client
## in (it checks the front, the strip and the line it got); then a phase stalling on time, the side
## falling back, the debrief phase by phase (nothing paid twice), the war fed (WorldSites), the API
## for D4/D5 and the budgets. Each process prints OPERATIONS TEST PASSED/FAILED and exits with its
## failure count. Never touches a real save (a test campaign of its own, deleted at the end).

## The test's operation: a small OOB (the API D4/D5 use: Operations.register_type), so the run's
## checks stay quick: three allied rifle teams and a Bradley section; the enemy's groups far back.
const TEST_FRIENDLY := [
	{"kind": "rifle_squad", "groups": 3, "men": 4, "callsign": "Saber", "kit": "allied_us"},
	{"kind": "mech_infantry", "groups": 1, "vehicles": ["bradley"], "crew": 3, "men": 0, "callsign": "Hammer", "kit": "allied_us"},
]
const TEST_ENEMY := [
	{"kind": "rifle_squad", "groups": 2, "men": 3, "bands": ["keep"], "callsign": "Roamer", "kit": "rifles"},
	{"kind": "light_armour", "groups": 1, "vehicles": ["technical"], "crew": 2, "men": 0, "bands": ["keep"], "callsign": "Hornet", "kit": "rifles", "reserve": true},
]

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var ops: Operations
var cid := ""
var zone_id := ""
var front_zone := ""
var _host_digest := {}
var _client_left := false
var _spawn_frames := {}  # process frame -> men spawned in it


## The host's sign that its door is open (the late-joiner part): the client waits for it before it
## joins, so it isn't let in and dropped (its 8 km zone loaded each time) while the host's checks run.
static func _door_file() -> String:
	return "user://operations_test_door%s_%d.txt" % [OS.get_environment("CONTRACTOR_TEST_TAG"), Net.port()]


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_operations" + tag  # never touch a real save
	Campaign.campaign_id = "test_operations" + tag
	CompoundLevel.spawn_ai = false  # the sites' garrisons stay out: the run's own rules are what's checked
	Contracts.auto_show_debrief = false
	Contracts.autosave = false
	var args := OS.get_cmdline_user_args()
	get_tree().create_timer(1380.0, true, false, true).timeout.connect(func() -> void:
		print("OPERATIONS TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--operations-join" in args:
		await _run_client(args[args.find("--operations-join") + 1] if args.find("--operations-join") + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		DirAccess.remove_absolute(_door_file())
		await _run_host("--operations-host" in args)


func check(condition: bool, what: String) -> void:
	if not is_inside_tree():
		return  # (a client dropped while the host's door was shut reloads its scene: the old run's checks don't count)
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
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		for t: String in ["phased_invasion", "armoured_thrust", "beach_landing"]:
			Operations.unregister_type(t)
		BaseHub.delete_test_campaign_files()
	print("OPERATIONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


# --- Host ---------------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	_test_grid()
	_test_strip_text()
	_test_api()
	Contracts.new_full_campaign(3177, 400000)
	Operations.register_type("phased_invasion", {"friendly_oob": TEST_FRIENDLY, "enemy_oob": TEST_ENEMY})
	for t: String in ["armoured_thrust", "beach_landing"]:  # (the US's other types are the optypes suite's: this one plays the invasion)
		Operations.register_type(t, {"offer": false})
	if not _test_offer():
		_finish()
		return
	_test_zone()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check(Contracts.server_start_deployment([cid], zone_id) == "", "the operation deploys")
	main.host_zone(MissionRegistry.zone_def(zone_id))
	# No one in until the late-joiner part: a client let in while the zone loads would be dropped
	# when the door shuts, and its scene reloaded under its checks.
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	var t0 := Time.get_ticks_msec()
	await _wait_for(func() -> bool:
		var lvl := CompoundLevel.current(self) as ZoneLevel
		return lvl != null and String(lvl.def.get("id", "")) == zone_id and lvl.players.get_node_or_null(^"1") != null, 180.0)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and multiplayer.multiplayer_peer is ENetMultiplayerPeer, "the operation zone %s is hosted on port %d (%.1f s)" % [zone_id, Net.port(), (Time.get_ticks_msec() - t0) / 1000.0])
	if level == null:
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	level.ai.child_entered_tree.connect(func(_n: Node) -> void:
		var f := Engine.get_process_frames()
		_spawn_frames[f] = int(_spawn_frames.get(f, 0)) + 1)
	await _test_run_start()
	await _test_phase_one()
	await _test_phase_two_late()
	_test_front_moved()
	await _test_save_load()
	if wait_for_client:
		print("[host] waiting for the client")
		Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
		var door := FileAccess.open(_door_file(), FileAccess.WRITE)
		if door:
			door.store_string("open")
			door.close()
		await _wait_for(func() -> bool: return _client_left, 420.0)
		DirAccess.remove_absolute(_door_file())
		check(_client_left, "the late joiner came and went")
	_test_stall()
	_test_fall_back()
	_test_budgets()  # (while the contract is still held: after its debrief the run is over)
	_test_debrief_and_war()
	_finish()


## The front grid on its own (6.3): 32 x 32 cells of 256 m; a flip at twice the presence for 60 s
## and never while a garrison stands; objectives falling, consolidation behind a phase line, giving
## back on a withdrawal; the line; replication and saves.
func _test_grid() -> void:
	print("The front grid")
	var g := FrontGrid.new()
	g.setup(8192.0, 32, Vector2(0, 1), 800.0)
	check(g.cells == 32 and is_equal_approx(g.cell_m, 256.0) and g.owner.size() == 1024 and is_equal_approx(g.share(FrontGrid.FRIENDLY), 3.0 / 32.0),
		"32 x 32 cells of 256 m; the friendly side starts with the start band (%d%%)" % roundi(g.share(FrontGrid.FRIENDLY) * 100.0))
	var p := Vector2(100.0, -4096.0 + 1300.0)  # a hostile cell in the outposts band
	var i := g.index_of(p)
	var pres := [{"pos": p, "side": FrontGrid.FRIENDLY, "cp": 8.0}, {"pos": p, "side": FrontGrid.HOSTILE, "cp": 4.0}]
	check(g.cycle(pres, [], 0.0).is_empty() and g.since[i] == 0.0 and g.owner[i] == FrontGrid.HOSTILE, "twice the defender's presence starts the clock")
	check(g.cycle(pres, [], 59.0).is_empty() and g.owner[i] == FrontGrid.HOSTILE, "not before 60 s")
	var flipped := g.cycle(pres, [], 61.0)
	check(i in flipped and g.owner[i] == FrontGrid.FRIENDLY and g.flips >= 1, "at 60 s the cell is ours (%d cells flipped)" % flipped.size())
	var j := g.index_of(p + Vector2(0, 1024.0))
	var site := [{"pos": p + Vector2(0, 1024.0), "side": FrontGrid.HOSTILE, "cp": 2.0, "standing": true}]
	var pres2 := [{"pos": p + Vector2(0, 1024.0), "side": FrontGrid.FRIENDLY, "cp": 20.0}]
	g.cycle(pres2, site, 100.0)
	g.cycle(pres2, site, 200.0)
	check(g.owner[j] == FrontGrid.HOSTILE, "a standing garrison keeps its cell whatever comes")
	var weak := [{"pos": p + Vector2(0, 1024.0), "side": FrontGrid.FRIENDLY, "cp": 3.0}, {"pos": p + Vector2(0, 1024.0), "side": FrontGrid.HOSTILE, "cp": 2.0}]
	g.cycle(weak, [], 300.0)
	g.cycle(weak, [], 400.0)
	check(g.owner[j] == FrontGrid.HOSTILE, "under twice the presence it holds")
	var fell := g.set_cells(g.cells_within(p + Vector2(0, 2048.0), 200.0), FrontGrid.FRIENDLY)
	check(fell.size() >= 4 and g.owner_at(p + Vector2(0, 2048.0)) == FrontGrid.FRIENDLY, "an objective falling hands its cells over at once (%d)" % fell.size())
	var line0 := g.front_m()
	var moved := g.consolidate(2500.0, FrontGrid.FRIENDLY)
	check(not moved.is_empty() and g.front_m() > line0 and g.owner_at(Vector2(-3000.0, -4096.0 + 2000.0)) == FrontGrid.FRIENDLY,
		"a phase done consolidates everything short of its line with no enemy in it (%d cells; the front %.0f m to %.0f m)" % [moved.size(), line0, g.front_m()])
	var pocket := g.index_of(p + Vector2(0, 1024.0))
	check(g.owner[pocket] == FrontGrid.HOSTILE, "a bypassed pocket stays the enemy's")
	check(g.front_line().size() == 32 and absf(g.front_line()[0].y - (-4096.0 + 2560.0)) < 1.0,
		"the front line: one point a column, at the far edge of the connected friendly cells (%.0f)" % g.front_line()[0].y)
	var given := g.give_back(1500.0)
	check(not given.is_empty() and g.owner_at(Vector2(-3000.0, -4096.0 + 2000.0)) == FrontGrid.HOSTILE and g.owner_at(Vector2(-3000.0, -4096.0 + 600.0)) == FrontGrid.FRIENDLY,
		"falling back gives back every friendly cell past the line held with none of ours in it (%d)" % given.size())
	var copy := FrontGrid.new()
	copy.setup(8192.0, 32, Vector2(0, 1), 800.0)
	check(copy.from_bytes(g.to_bytes()) and copy.owner == g.owner and copy.front_line() == g.front_line(), "the whole grid goes as bytes (a late joiner), the same line from it")
	var other := FrontGrid.new()
	other.setup(8192.0, 32, Vector2(0, 1), 800.0)
	other.from_save(g.to_save())
	var c2 := FrontGrid.new()
	c2.setup(8192.0, 32, Vector2(0, 1), 800.0)
	c2.from_bytes(copy.to_bytes())
	var changed := g.set_cells(PackedInt32Array([5, 6, 7]), FrontGrid.HOSTILE)
	c2.apply_delta(g.delta(changed))
	check(other.owner == copy.owner and changed.size() == 3 and c2.owner == g.owner, "it saves as base64; deltas of [cell, owner] keep a copy in step")
	var east := FrontGrid.new()
	east.setup(8192.0, 32, Vector2(-1, 0), 800.0)
	check(east.owner_at(Vector2(3900.0, 0.0)) == FrontGrid.FRIENDLY and east.owner_at(Vector2(-3900.0, 0.0)) == FrontGrid.HOSTILE
		and absf(east.front_line()[5].x - (4096.0 - 768.0)) < 1.0, "an axis from the east: the start on the east edge, the line 768 m in")
	# The budget: a loaded cycle as a fight has it, 160 groups and 30 sites, most of the groups
	# within a kilometre of the front (each side's own half), a few deep; then the same groups
	# scattered over the whole zone, each in a cell of its own (printed: the worst case).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sites := []
	for k in 30:
		sites.append({"pos": Vector2(rng.randf_range(-4000, 4000), rng.randf_range(-2000, 4000)), "side": FrontGrid.HOSTILE, "cp": 6.0, "standing": k % 3 != 0})
	var front := -4096.0 + 800.0  # (g's line: the start band's far edge, 800 m in from the south)
	var fight := []
	var spread := []
	for k in 160:
		var side := 1 + k % 2
		var deep := k % 8 == 0
		var depth := rng.randf_range(1000.0, 3000.0) if deep else rng.randf_range(0.0, 1000.0)
		var z := front - depth if side == FrontGrid.FRIENDLY else front + depth
		fight.append({"pos": Vector2(rng.randf_range(-4000, 4000), clampf(z, -4090.0, 4090.0)), "side": side, "cp": rng.randf_range(2.0, 8.0)})
		spread.append({"pos": Vector2(rng.randf_range(-4000, 4000), rng.randf_range(-4000, 4000)), "side": side, "cp": rng.randf_range(2.0, 8.0)})
	var budget := Operations.knob("front", "budget_fight_ms", 0.6) * 1000.0
	var slack := Operations.knob("front", "budget_slack", 3.0)
	var costs := []
	for groups: Array in [fight, spread]:
		var h := FrontGrid.new()
		h.setup(8192.0, 32, Vector2(0, 1), 800.0)
		var worst := 0.0
		var sum := 0.0
		for k in 20:
			h.cycle(groups, sites, 500.0 + k * 10.0)
			worst = maxf(worst, h.last_us)
			sum += h.last_us
		costs.append([sum / 20.0, worst])
	check(float(costs[0][0]) <= budget * slack, "a front cycle with 160 groups (most within 1 km of the front) and 30 sites: %.0f µs on average, %.0f at worst (budget %.0f µs; %.0fx allowed on a loaded machine)"
		% [costs[0][0], costs[0][1], budget, slack])
	print("    (the same groups scattered over the zone, one a cell: %.0f µs on average, %.0f at worst; a cycle is every %.0f s)" % [costs[1][0], costs[1][1], Operations.knob("front", "cycle_s", 10.0)])


## The strip's lines (pure).
func _test_strip_text() -> void:
	print("The operation strip's text")
	var v := {"codename": "GREY LANCE", "state": "running", "phase": 1, "clock_s": 1460.0, "front_m": 3120.0, "share": 0.34, "allied": "Saber 1 assault",
		"phases": [{"name": "PL COPPER", "state": "done", "limit_s": 1500.0, "started_s": 0.0}, {"name": "PL BRASS", "state": "running", "limit_s": 1500.0, "started_s": 700.0},
			{"name": "PL IRON", "state": "pending", "limit_s": 1800.0}, {"name": "PL STEEL", "state": "pending", "limit_s": 1800.0}],
		"task": ["Seize the bridge on the MSR at 041 052"]}
	var text := OperationStrip.strip_text(v, 1460.0)
	check(text.begins_with("OP GREY LANCE  PH2/4 BRASS  12:40 / 25:00") and text.contains("[x] COPPER  [>] BRASS  [ ] IRON  [ ] STEEL")
		and text.contains("Task: Seize the bridge") and text.contains("Front 3.1 km in, 34% ours"), "the strip: %s" % text.replace("\n", " | "))
	v.state = "stalled"
	check(OperationStrip.strip_text(v, 0.0).contains("STALLED"), "a stalled operation says so")


## The API for D4/D5: a type of its own with its phases hook builds and offers through D3's code.
func _test_api() -> void:
	print("The API for the mission types (D4, D5)")
	var called := [0]
	Operations.register_type("test_raid_op", {"name": "Test op", "offer": true, "base_pay": 100000, "days": 1, "h_hour": "now",
		"friendly_oob": [], "enemy_oob": []}, {"phases": func(zdef: Dictionary, _t: String) -> Array:
			called[0] += 1
			var hq := Operations.resolve(zdef, {"site": "@hq"})
			return [{"index": 0, "name": "PL ONLY", "line_m": 7600.0, "limit_s": 600.0, "pay_share": 1.0,
				"objectives": [{"id": "hq", "label": "the HQ", "pos": hq[0].pos, "module_id": "hq", "radius": 60.0, "required": true, "town": false}],
				"tasks": [{"kind": Operations.SEIZE_SITE, "text": "Seize the HQ", "pos": hq[0].pos, "module_id": "hq", "radius": 60.0, "optional": false, "bonus_share": 0.0, "hold_s": 0.0}]}]})
	var zdef := OperationGen.generate(5, "phased_invasion", ["ashfield"])
	var phases := Operations.build_phases(zdef, "test_raid_op")
	check(called[0] == 1 and phases.size() == 1 and String(phases[0].name) == "PL ONLY", "a registered type's phases hook replaces the generic phases")
	check(Operations.type_def("test_raid_op").get("name") == "Test op" and "test_raid_op" in Operations.type_ids(), "its data is a type like the file's")
	Operations.unregister_type("test_raid_op")
	check(Operations.type_def("test_raid_op").is_empty() and not Operations.hook("test_raid_op", "phases").is_valid(), "and unregistering takes it out")
	var built := Operations.build_phases(zdef, "phased_invasion")
	var shares := 0.0
	for p: Dictionary in built:
		shares += float(p.pay_share)
	check(built.size() == 4 and is_equal_approx(shares, 1.0) and (built[1].tasks as Array).any(func(t: Dictionary) -> bool: return String(t.kind) == Operations.KEEP_INTACT),
		"the phased invasion: four phases whose shares add to the whole (20/25/25/30), the bridge to keep in phase 2")
	var lines_ok := true
	for k in range(1, built.size()):
		lines_ok = lines_ok and float(built[k].line_m) >= float(built[k - 1].line_m)
	check(lines_ok, "its phase lines run down the axis: %s" % [built.map(func(p: Dictionary) -> String: return "%s %.0f m" % [p.name, p.line_m])])


## An operation offered by a US front to a trusted company, and taken.
func _test_offer() -> bool:
	print("An operation offered and taken")
	Campaign.section(WorldSites.SECTION).clear()
	Campaign.section(WorldSites.WAR).clear()
	var best := ""
	var best_n := -1
	for z in WorldSites.war_zones():
		if WorldSites.holder(z) != "ashen_banner" or not String(MissionRegistry.zone(z).get("kind", "")) == "contract":
			continue
		var n := Operations.covers_for(z, "ashen_banner").size()
		if n > best_n or (n == best_n and z < best):
			best = z
			best_n = n
	front_zone = best
	WorldSites.site(front_zone)["front"] = {"by": "us_forces", "since": Economy.day(), "progress": WorldSites.FRONT_START}
	Campaign.mark_changed(WorldSites.SECTION)
	_set_rep("us_forces", 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	check(Contracts.operation_offers(rng, Economy.day(), []).is_empty(), "no operation for a company the US doesn't trust yet")
	_set_rep("us_forces", 35)
	_set_rep("vessmark", 35)
	Contracts.server_refresh_board()
	var board: Array = Campaign.section(Contracts.SECTION).board
	var ops_on: Array = board.filter(func(c: Dictionary) -> bool: return String(c.get("op_front", "")) == front_zone)
	var us: Array = ops_on.filter(func(c: Dictionary) -> bool: return Operations.is_operation(c) and String(c.employer) == "us_forces")
	var vm: Array = ops_on.filter(func(c: Dictionary) -> bool: return String(c.employer) == "vessmark")
	check(us.size() == 1 and String(us[0].employer) == "us_forces" and String(us[0].op_type) == "phased_invasion" and String(us[0].target) == "ashen_banner",
		"a US front at %s posts an operation contract to a trusted company (%s)" % [front_zone, String(us[0].title) if not us.is_empty() else "none"])
	check(vm.size() == 1 and Operations.is_operation(vm[0]) and String(vm[0].op_type) in ["seize_crossing", "hold_town"],
		"Vessmark's beside it is an operation of its own types now (D5, cg_brief 3.3): %s" % (String(vm[0].title) if not vm.is_empty() else "none"))
	if us.is_empty():
		return false
	var c: Dictionary = us[0]
	cid = String(c.cid)
	zone_id = String(c.op_zone)
	var public := ContractGen.public_view(c)
	check(not public.has("enemy_oob") and public.has("phases") and (public.phases as Array).size() == 4 and (c.covers as Array)[0] == front_zone,
		"the board shows its phases and covered zones (%s), not the enemy's OOB" % [c.covers])
	var want_pay := roundi(320000.0 * float((MissionRegistry.setting("difficulty_pay") as Array)[int(c.rated)]) / 500.0) * 500
	if not is_equal_approx(Economy.pay_mult("us_forces"), 1.0):
		want_pay = roundi(want_pay * Economy.pay_mult("us_forces") / 500.0) * 500  # (Contracts._add_offer: the tier's)
	check(int(c.base_pay) == want_pay and int(c.days) == 2 and int(c.expires_day) == Economy.day() + Contracts.OP_OFFER_DAYS and bool(c.war_driven),
		"pay: $320,000 x the rating's %.2f x the tier's %.2f = $%s; 2 days; up %d days" % [float((MissionRegistry.setting("difficulty_pay") as Array)[int(c.rated)]),
			Economy.pay_mult("us_forces"), DebriefCalc.money(c.base_pay), Contracts.OP_OFFER_DAYS])
	_set_rep("us_forces", 20)
	check(Contracts.server_accept(cid, ContractGen.default_terms()) != "", "it can't be signed under trusted")
	_set_rep("us_forces", 35)
	var cash := Economy.cash()
	check(Contracts.server_accept(cid, ContractGen.default_terms()) == "", "it's signed at trusted")
	var held := Contracts.contract(cid)
	var d: Dictionary = held.deal
	check(int(d.advance) == roundi(int(d.pay_total) * 0.2) and int(d.completion) == int(d.pay_total) - int(d.advance) and Economy.cash() - cash == int(d.advance),
		"20%% on signing ($%s of $%s), the rest by phase" % [DebriefCalc.money(d.advance), DebriefCalc.money(d.pay_total)])
	return true


## Its zone, from the contract: 8 km, the target the war's holder, its phases on the ground.
func _test_zone() -> void:
	print("Its zone")
	var c := Contracts.contract(cid)
	var zdef := MissionRegistry.zone_def(zone_id)
	check(OperationGen.is_operation(zdef) and is_equal_approx(float(zdef.size_m), 8192.0) and String(zdef.id) == zone_id and zdef.covers == c.covers,
		"MissionRegistry.zone_def answers for %s: an 8,192 m operation zone over %s" % [zone_id, zdef.get("covers", [])])
	check(String(zdef.controller) == WorldSites.holder_now(front_zone) and String(zdef.controller) == String(c.target),
		"its controller is the target as the war has it (%s)" % zdef.controller)
	var phases: Array = c.phases
	var in_band := true
	for o: Dictionary in phases[0].objectives:
		in_band = in_band and OperationGen.band_at(zdef, Vector2(float(o.pos[0]), float(o.pos[1]))) in ["outposts", "start"]
	check(in_band and String(phases[0].tasks[0].text).contains("checkpoint") and (c.objectives as Array).size() >= 1,
		"phase 1's objectives in the outposts band; the company's task: %s" % String(phases[0].tasks[0].text))


func _set_rep(faction: String, value: int) -> void:
	var rep: Dictionary = Economy.state().get("rep", {})
	rep[faction] = value
	Economy.state()["rep"] = rep


## The run starts: its commanders (B2) and the OOB coming out within the caps.
func _test_run_start() -> void:
	print("The run, its commanders and the OOB")
	ops = Operations.of(level)
	await _wait_for(func() -> bool: return ops != null and ops.active(), 20.0)
	check(ops != null and ops.active() and ops.grid.cells == 32, "the zone runs its operation")
	if ops == null or not ops.active():
		return
	ops.server_advance(1.0)
	var run := Operations.run_of(Contracts.contract(cid))
	check(String(run.state) == Operations.RUNNING and int(run.phase) == 0 and Contracts.objectives.for_contract(cid).size() >= 1,
		"H-hour now: phase 1 runs, its task live (%s)" % [Contracts.objectives.for_contract(cid).map(func(o: Dictionary) -> String: return o.text)])
	check(SideCommand.of(level, &"friendly") == ops.friendly and ops.friendly.plan is OperationPlan and (ops.plan.phases() as Array).size() == 4,
		"the friendly commander runs an OperationPlan from the four phases")
	check(SideCommand.of(level, &"hostile") == ops.hostile and ops.hostile.plan is DefencePlan and (ops.defence.sites() as Array).size() >= 8,
		"the hostile commander a DefencePlan over the enemy's %d sites" % (ops.defence.sites() as Array).size())
	var friendly_n := (run.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "friendly").size()
	await _wait_for(func() -> bool: return (run.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "friendly" and String(e.state) == "live").size() == friendly_n, 120.0)
	var live: Array = (run.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "friendly" and String(e.state) == "live")
	check(live.size() == friendly_n and ops.friendly.groups.size() == friendly_n, "the allied OOB came out at the start and went to its commander (%d groups, %d commanded)" % [live.size(), ops.friendly.groups.size()])
	var bradley := get_tree().get_nodes_in_group(Vehicle.GROUP).filter(func(v: Node) -> bool: return level.is_ancestor_of(v) and String((v as Vehicle).get_meta(&"op_group", "")) != "")
	check(not bradley.is_empty() and not (bradley[0] as Vehicle).occupants().is_empty(), "with its vehicles crewed (%d)" % bradley.size())
	var most := 0
	for f: int in _spawn_frames:
		most = maxi(most, int(_spawn_frames[f]))
	var stream := level.get_node_or_null(NodePath(BigZoneStreaming.NODE_NAME)) as BigZoneStreaming
	check(most <= int(Operations.knob("run", "spawn_men_frame", 2.0)) + 1 and stream != null and stream.live_soldiers <= 80 and stream.live_vehicles <= 16,
		"a few men a frame (at most %d), within the live caps (%d soldiers, %d vehicles)" % [most, stream.live_soldiers if stream else -1, stream.live_vehicles if stream else -1])
	var enemy: Array = (run.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "hostile")
	check(not enemy.is_empty() and enemy.all(func(e: Dictionary) -> bool: return String(e.state) == Operations.PENDING),
		"the enemy's groups wait far off, out of the world, until the front comes near them (%d)" % enemy.size())
	var e0: Dictionary = enemy[0]
	var at := level.ground_point(Vector3(float(e0.pos[0]), 0, float(e0.pos[1])))
	var keep := player.global_position
	player.global_position = at + Vector3(300, 0, 0)
	check(not ops._due(e0, run), "an enemy group never comes out within 600 m of a player")
	player.global_position = at + Vector3(4000, 0, 0).rotated(Vector3.UP, 0.3)
	check(not ops._due(e0, run), "nor while every player is past 2.6 km")
	player.global_position = keep
	ops.friendly.advance(0.5)
	check(ops.plan.started and not ops.plan.reserve.is_empty(), "the commander's phase 1 begins, a reserve held (%s)" % ", ".join(PackedStringArray(ops.plan.reserve.keys())))


## Phase 1 on its objective: the company holds the MSR checkpoint, fast; it pays into the bank.
func _test_phase_one() -> void:
	print("Phase 1: on its objective, fast")
	var c := Contracts.contract(cid)
	var task: Dictionary = (c.phases[0] as Dictionary).tasks[0]
	var at := level.ground_point(Vector3(float(task.pos[0]), 0, float(task.pos[1])))
	player.global_position = at
	var cash := Economy.cash()
	var share0 := ops.grid.share(FrontGrid.FRIENDLY)
	ops.server_advance(30.0)
	var o: Dictionary = Contracts.objectives.for_contract(cid)[0]
	check(String(o.state) == Objectives.ACTIVE and String(o.progress).begins_with("holding"), "holding the checkpoint (%s)" % o.progress)
	ops.server_advance(40.0)
	var run := Operations.run_of(Contracts.contract(cid))
	var rec: Dictionary = run.phases[0]
	check(String(rec.state) == Operations.DONE and int(run.phase) == 1, "the checkpoint seized: phase 1 done, phase 2 begins")
	var d: Dictionary = Contracts.contract(cid).deal
	var base := roundi(int(d.completion) * 0.2)
	var lines: Array = rec.get("lines", [])
	check(int(rec.base) == base and lines.any(func(l: Dictionary) -> bool: return String(l.text).begins_with("fast")) and int(rec.pay) > base,
		"it pays its 20%% ($%s) and the fast bonus: $%s (%s)" % [DebriefCalc.money(base), DebriefCalc.money(rec.pay), lines.map(func(l: Dictionary) -> String: return l.text)])
	check(Economy.cash() - cash == int(rec.pay) and (Economy.ledger().back() as Dictionary).what.contains("phase 1 (PL COPPER)")
		and Economy.ledger_kind(String((Economy.ledger().back() as Dictionary).what)) == "Contract pay",
		"into the one bank, a ledger line of its own: %s" % String((Economy.ledger().back() as Dictionary).what))
	check(ops.grid.share(FrontGrid.FRIENDLY) > share0 and ops.grid.owner_at(Vector2(at.x, at.z)) == FrontGrid.FRIENDLY,
		"the front moves: the checkpoint's cells are ours, and the band behind the line (%d%% to %d%%)" % [roundi(share0 * 100.0), roundi(ops.grid.share(FrontGrid.FRIENDLY) * 100.0)])
	ops.friendly.advance(1.0)
	check(ops.plan.phase >= 1, "the commander's plan moves on to phase 2 with it (phase %d)" % (ops.plan.phase + 1))
	check(Contracts.objectives.for_contract(cid).filter(func(x: Dictionary) -> bool: return int((x.params as Dictionary).get("phase", -1)) == 1).size() == 2,
		"phase 2's tasks come in: the bridge, and keeping it standing")
	check(ops.said.any(func(l: String) -> bool: return l.contains("PL COPPER done")), "Citadel says so on the net: %s" % (ops.said.filter(func(l: String) -> bool: return l.contains("done")).back() if ops.said.any(func(l: String) -> bool: return l.contains("done")) else ""))


## Phase 2 done late: past its limit it pays less; the bridge standing pays its bonus. The enemy's
## reinforcements come by the front meanwhile.
func _test_phase_two_late() -> void:
	print("Phase 2: on time, late")
	var c := Contracts.contract(cid)
	var start := level.ground_point(Vector3(float(c.phases[0].tasks[0].pos[0]), 0, float(c.phases[0].tasks[0].pos[1])))
	player.global_position = start
	var limit := float(c.phases[1].limit_s)
	ops.server_advance(limit + 20.0)
	var run := Operations.run_of(Contracts.contract(cid))
	check(int(run.phase) == 1 and String(run.phases[1].state) == Operations.RUNNING and ops.said.any(func(l: String) -> bool: return l.contains("past its time")),
		"past its limit the phase runs on, said to be late")
	check(int(run.reinforced) >= 1, "the enemy's reinforcements came by the front meanwhile (%d)" % int(run.reinforced))
	var waves: Array = (run.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.callsign).begins_with("Wave"))
	var ok := not waves.is_empty()
	for e: Dictionary in waves:
		var p := Vector2(float(e.pos[0]), float(e.pos[1]))
		ok = ok and ops.grid.owner_at(p) == FrontGrid.HOSTILE and Vector2(start.x, start.z).distance_to(p) >= Operations.knob("run", "spawn_far_m", 600.0) - 1.0
	check(ok, "each on the enemy's side of the front, at least 600 m from every player (%s)" % [waves.map(func(e: Dictionary) -> Array: return e.pos)])
	for e: Dictionary in (run.oob as Array):
		if String(e.callsign).begins_with("Wave") or String(e.callsign).begins_with("Ghost"):
			e.state = "gone"  # (kept out of the world for the rest of the test)
	var task: Dictionary = (c.phases[1] as Dictionary).tasks[0]
	player.global_position = level.ground_point(Vector3(float(task.pos[0]), 0, float(task.pos[1])))
	var cash := Economy.cash()
	ops.server_advance(65.0)
	var rec: Dictionary = run.phases[1]
	var lines: Array = rec.get("lines", [])
	check(String(rec.state) == Operations.DONE and bool(rec.late) and lines.any(func(l: Dictionary) -> bool: return String(l.text).begins_with("done late") and int(l.amount) < 0),
		"the bridge seized late: phase 2 pays less (%s)" % [lines.map(func(l: Dictionary) -> String: return "%s %d" % [l.text, l.amount])])
	check(lines.any(func(l: Dictionary) -> bool: return String(l.text).contains("bridge") and int(l.amount) > 0),
		"the bridge standing pays its share")
	check(Economy.cash() - cash == int(rec.pay) and int(run.phase) == 2, "paid in (+$%s); phase 3 begins" % DebriefCalc.money(rec.pay))


## The front on the map and its line.
func _test_front_moved() -> void:
	print("The front")
	ops.server_front_cycle()
	var markers := MapNodes.markers(level)
	var lines: Array = markers.list("intel").filter(func(m: Dictionary) -> bool: return String(m.kind) == "line" and String(m.text) == "Front") if markers else []
	check(lines.size() == 1 and (lines[0].points as PackedVector2Array).size() == 32, "the front line is one line on the map's intel channel (%d points)" % ((lines[0].points as PackedVector2Array).size() if not lines.is_empty() else 0))
	var c := Contracts.contract(cid)
	check(ops.grid.front_m() >= float(c.phases[0].line_m) - 300.0, "the front stands past phase 1's line (%.0f m in; PL COPPER at %.0f m)" % [ops.grid.front_m(), float(c.phases[0].line_m)])
	check(String(ops.view.get("state", "")) == Operations.RUNNING and int(ops.view.phase) == 2 and OperationStrip.strip_text(ops.view, ops.clock_now()).contains("PH3/4 IRON"),
		"the host's strip: %s" % OperationStrip.strip_text(ops.view, ops.clock_now()).replace("\n", " | "))


## A save mid-operation and a load: the run picks up where it was.
func _test_save_load() -> void:
	print("Save and load mid-operation")
	ops.server_save_state()
	var before: Dictionary = Operations.run_of(Contracts.contract(cid)).duplicate(true)
	var front := ops.grid.to_bytes()
	check(Campaign.save_campaign(), "the campaign saves mid-operation")
	check(Campaign.load_campaign(), "and loads again")
	var after := Operations.run_of(Contracts.contract(cid))
	check(int(after.phase) == int(before.phase) and is_equal_approx(float(after.clock_s), float(before.clock_s)) and String(after.front) == String(before.front)
		and (after.oob as Array).size() == (before.oob as Array).size() and int(after.paid) == int(before.paid),
		"the contract's run came back as saved: phase %d, %s on the clock, $%s paid, %d OOB groups" % [int(after.phase) + 1, Operations.clock_text(float(after.clock_s)), DebriefCalc.money(after.paid), (after.oob as Array).size()])
	# A fresh level would make a fresh node: the old one and what it put in the world go.
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
	await _wait_for(func() -> bool: return ops != null and ops.active(), 10.0)
	check(ops != null and ops.active() and ops.grid.to_bytes() == front and int(ops.view.get("phase", -1)) == int(before.phase),
		"a new run picks it up: the same front, phase %d" % (int(ops.view.get("phase", -1)) + 1))
	var back := Operations.run_of(Contracts.contract(cid))
	check((back.oob as Array).filter(func(e: Dictionary) -> bool: return String(e.side) == "friendly" and String(e.state) == Operations.PENDING).size() >= 1,
		"its allied groups come back where they were, by the same rules")
	await _wait_for(func() -> bool: return ops.friendly.groups.size() >= 1, 60.0)
	check(ops.friendly != null and ops.friendly.groups.size() >= 1 and (ops.plan.phases() as Array).size() == 4, "under a commander again (%d groups)" % ops.friendly.groups.size())


## Phase 3 stalls on time: at side_command.json phase_fail_share x its limit with its town not taken.
func _test_stall() -> void:
	print("Phase 3: stalls on time")
	var c := Contracts.contract(cid)
	player.global_position = level.ground_point(Vector3(float(c.phases[0].tasks[0].pos[0]), 0, float(c.phases[0].tasks[0].pos[1])))
	var limit := float(c.phases[2].limit_s)
	ops.server_advance(limit * SideCommand.num("phase_fail_share", 1.5) + 5.0)
	var run := Operations.run_of(Contracts.contract(cid))
	var mine := Contracts.objectives.for_contract(cid).filter(func(o: Dictionary) -> bool: return int((o.params as Dictionary).get("phase", -1)) == 2)
	check(String(run.state) == Operations.STALLED and String(run.phases[2].state) == Operations.FAILED and mine.all(func(o: Dictionary) -> bool: return String(o.state) == Objectives.FAILED),
		"phase 3 stalls at %s: its task failed, the operation stops there" % Operations.clock_text(limit * SideCommand.num("phase_fail_share", 1.5)))
	check(OperationStrip.strip_text(ops.view, 0.0).contains("STALLED"), "the strip says so")


## The commander's side falls back (B2's withdrawal): the front gives back past the last line held.
func _test_fall_back() -> void:
	print("Falling back")
	var c := Contracts.contract(cid)
	var share0 := ops.grid.share(FrontGrid.FRIENDLY)
	ops.friendly.withdrawn = true
	ops.plan.withdraw(ops.friendly, ops.friendly.now())
	ops.server_front_cycle()
	var run := Operations.run_of(Contracts.contract(cid))
	check(bool(run.withdrawn) and ops.said.any(func(l: String) -> bool: return l.contains("fall back to PL BRASS")),
		"the side withdraws: \"fall back to PL BRASS\"")
	check(ops.grid.share(FrontGrid.FRIENDLY) <= share0 and ops.grid.front_m() <= float(c.phases[1].line_m) + 300.0,
		"the front gives back to the last line held (%.0f m in; PL BRASS at %.0f m)" % [ops.grid.front_m(), float(c.phases[1].line_m)])


## The debrief phase by phase, nothing paid twice, and the war fed.
func _test_debrief_and_war() -> void:
	print("The debrief and the war")
	var c := Contracts.contract(cid)
	var run := Operations.run_of(c)
	var paid := int(run.paid)
	# What the debrief tells the war (the days after it move the war on, so it's read here first).
	var snap_sites: Dictionary = Campaign.section(WorldSites.SECTION).duplicate(true)
	var snap_war: Dictionary = Campaign.section(WorldSites.WAR).duplicate(true)
	var progress0 := float(WorldSites.front(front_zone).get("progress", 0.0))
	var grip0 := WorldSites.grip(front_zone)
	WorldSites.server_operation_ended(c, Operations.phases_done(c))
	var f := WorldSites.front(front_zone)
	check(String(f.get("by", "")) == "us_forces" and float(f.get("progress", 0.0)) >= minf(progress0 + 0.5, 0.9) - 0.001 and WorldSites.grip(front_zone) <= grip0 - WorldSites.OP_PARTIAL_GRIP + 0.001,
		"the war fed: half the phases move the US's front at %s (%.2f to %.2f) and cut the Banner's grip (%.2f to %.2f)" % [front_zone, progress0, float(f.get("progress", 0.0)), grip0, WorldSites.grip(front_zone)])
	var carried := c.duplicate(true)
	WorldSites.server_operation_ended(carried, 4)
	var flipped := (c.covers as Array).filter(func(z: Variant) -> bool: return WorldSites.holder(String(z)) == "us_forces" or bool(WorldSites.front(String(z)).get("sieged", false)))
	check(flipped.size() == (c.covers as Array).size(), "carried, it flips its covered zones to the US (or sieges a last one): %s" % [flipped])
	for pair: Array in [[WorldSites.SECTION, snap_sites], [WorldSites.WAR, snap_war]]:
		var sec := Campaign.section(pair[0])
		sec.clear()
		sec.merge((pair[1] as Dictionary).duplicate(true))
	var ledger_n := Economy.ledger().size()
	var debrief := Contracts.server_end_deployment({"items": [], "extracted": ["Player 1"], "casualties": []})
	var line: Dictionary = (debrief.get("contracts", [{}]) as Array)[0]
	check(String(line.outcome) == "partial" and int(line.phases_done) == 2 and int(line.paid_at_phases) == paid and (line.phases as Array).size() == 4,
		"the debrief: partial, 2 of 4 phases, $%s paid as they were done" % DebriefCalc.money(paid))
	var sum := 0
	for p: Dictionary in line.phases:
		sum += int(p.pay)
	check(int(line.pay) == sum and sum == paid, "its line is phase by phase: the completion and bonuses add up to what was paid ($%s)" % DebriefCalc.money(line.pay))
	var since: Array = Economy.ledger().slice(ledger_n)
	check(not since.any(func(e: Dictionary) -> bool: return String(e.what).begins_with("Completion:")), "nothing paid twice: no completion pay at the debrief (%s)" % [since.map(func(e: Dictionary) -> String: return e.what)])
	var summary := DebriefCalc.summary(debrief)
	check(Array(summary).any(func(l: String) -> bool: return l.contains("PH1 PL COPPER: done in")) and Array(summary).any(func(l: String) -> bool: return l.contains("PH3 PL IRON: stalled"))
		and Array(summary).any(func(l: String) -> bool: return l.contains("PH4 PL STEEL: not reached")), "the summary says each phase: %s" % " | ".join(summary.slice(0, 6)))
	var ledger := DebriefScreen.ledger_lines(debrief)
	check(ledger.any(func(l: Dictionary) -> bool: return String(l.what) == "PH2 PL BRASS"), "and the debrief screen's ledger lists them")
	check((debrief.get("war", []) as Array).any(func(l: String) -> bool: return l.contains("moved its front")), "the debrief says what it did to the war: %s" % [debrief.get("war", [])])


## The budgets (Proposed): the front's cycle in the zone, the strip's refresh.
func _test_budgets() -> void:
	print("Budgets")
	var slack := Operations.knob("front", "budget_slack", 3.0)
	if ops and is_instance_valid(ops):
		# Five cycles, the median of each (one may carry an event: a site taken off-screen, said on the net).
		var grid_us: Array[float] = []
		var all_us: Array[float] = []
		var parts := {}
		for k in 5:
			ops.cycle_us = -1.0  # (stays so if the cycle didn't run)
			ops.server_front_cycle()
			grid_us.append(ops.grid.last_us)
			all_us.append(ops.cycle_us)
			parts[ops.cycle_us] = ops.cycle_parts
		grid_us.sort()
		all_us.sort()
		check(all_us[0] >= 0.0 and grid_us[2] <= Operations.knob("front", "budget_ms", 0.2) * 1000.0 * slack and all_us[2] <= Operations.knob("front", "budget_gather_ms", 1.0) * 1000.0 * slack,
			"the zone's front cycle (median of 5): the grid %.0f µs (budget %.0f, x%.0f allowed); all of it %.0f µs (budget %.0f: %s; worst %.0f)" % [grid_us[2], Operations.knob("front", "budget_ms", 0.2) * 1000.0, slack, all_us[2], Operations.knob("front", "budget_gather_ms", 1.0) * 1000.0, parts[all_us[2]], all_us[4]])
	var strip: OperationStrip = null
	if player and player._hud:
		for n in player._hud.zone_top_right.get_children():
			if n is OperationStrip:
				strip = n
	if strip:
		var worst := 0.0
		for k in 10:
			strip.refresh()
			worst = maxf(worst, strip.cost_us)
		check(worst <= Operations.knob("hud", "budget_ms", 0.3) * 1000.0 * slack, "the strip's refresh: %.0f µs at worst (budget %.0f µs)" % [worst, Operations.knob("hud", "budget_ms", 0.3) * 1000.0])
	else:
		print("    (no HUD on this headless player: the strip's cost is ui_test's)")


# --- The late joiner --------------------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var o := Operations.of(self)
	return {"front": o.grid.to_bytes() if o else PackedByteArray(), "phase": int(o.view.get("phase", -1)) if o else -1, "name": String(o.view.get("name", "")) if o else ""}


func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var open_by := Time.get_ticks_msec() + 1150000
	while not FileAccess.file_exists(_door_file()) and Time.get_ticks_msec() < open_by:
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree():
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
	check(joined[0], "joined the host")
	if not joined[0]:
		_finish()
		return
	await _wait_for(func() -> bool: return CompoundLevel.current(self) is ZoneLevel and OperationGen.is_operation((CompoundLevel.current(self) as ZoneLevel).def), 120.0)
	if not is_inside_tree():
		return
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the operation zone loaded on the client")
	if level == null:
		_finish()
		return
	await _wait_for(func() -> bool: return is_instance_valid(level) and Operations.of(level) != null and not Operations.of(level).view.is_empty(), 60.0)
	if not is_inside_tree():
		return
	var o := Operations.of(level)
	check(o != null and not o.view.is_empty(), "the late joiner asked for the run and got it")
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 15.0)
	if not is_inside_tree():
		return
	check(o != null and o.grid.to_bytes() == _host_digest.get("front") and int(o.view.get("phase", -2)) == int(_host_digest.get("phase", -1)),
		"the same front as the host's (%d%% ours) and the same phase (%d)" % [roundi(o.grid.share(FrontGrid.FRIENDLY) * 100.0) if o else 0, int(o.view.get("phase", -2)) + 1 if o else -1])
	var text := OperationStrip.strip_text(o.view, o.clock_now()) if o else ""
	check(text.contains("PH3/4 IRON") and text.contains(String(_host_digest.get("name", "?")).trim_prefix("Operation ")), "its strip: %s" % text.replace("\n", " | "))
	var me := level.players.get_node_or_null(NodePath(str(multiplayer.get_unique_id()))) as Soldier
	await _wait_for(func() -> bool: return me != null and me._hud != null, 10.0)
	if not is_inside_tree():
		return
	if me and me._hud:
		var strip: OperationStrip = null
		for n in me._hud.zone_top_right.get_children():
			if n is OperationStrip:
				strip = n
		if strip:
			strip.refresh()
		check(strip != null and strip.visible and strip._label.text.contains("PH3/4"), "on its HUD, over the objectives")
	await _wait_for(func() -> bool:
		var m := MapNodes.markers(level)
		return m != null and m.list("intel").any(func(x: Dictionary) -> bool: return String(x.kind) == "line" and String(x.text) == "Front"), 15.0)
	if not is_inside_tree():
		return
	var markers := MapNodes.markers(level)
	check(markers != null and markers.list("intel").any(func(x: Dictionary) -> bool: return String(x.kind) == "line" and String(x.text) == "Front"), "and the front line on its map")
	_finish()
