extends Node
## Headless checks of the base hub, the roster and hiring (wave 4, W12):
##   <voxel godot exe> --headless --path . res://tests/base_test.tscn
## The rules first (hiring from a seed, wages, growth after a mission, injuries and the medbay,
## the respawn pool, MIA, stand-ins), then a real session: the hub with its stash and muster
## line, a second process joining it as a client (it must see the same roster and stash, and
## hire through the host), the armory round trip, a deployment into the compound with the
## roster's own people in their own gear, extraction with one MIA and one killed, back to the
## hub, and a save and reload. Exits with the number of failures.
##
## The client is this scene again with `-- --join 127.0.0.1 --expect <base64 JSON>`; it writes
## its checks to a log the host prints.

const SEED := 4242
## Items the test stash holds besides the starting stash.
const EXTRA_STASH := [["m17", 1], ["burn_dressing", 3]]

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var _log: FileAccess  # client: where its checks go


func _ready() -> void:
	GameState.zone_id = "test_base" + tag
	Campaign.campaign_id = "test_base" + tag  # never touch a real save
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		_say("BASE TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--join" in OS.get_cmdline_user_args():
		await _run_client()
		return
	GameState.delete_save()
	Campaign.reset_campaign()
	_test_hiring()
	_test_wages()
	_test_growth()
	_test_injuries_and_medbay()
	_test_respawn_pool()
	_test_resolve()
	_test_stand_ins()
	await _test_session()
	GameState.zone_id = "test_base_zone" + tag
	GameState.delete_save()
	GameState.zone_id = "test_base" + tag
	GameState.delete_save()
	Campaign.reset_campaign()
	print("BASE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
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


# --- The rules -------------------------------------------------------------------------------

func _test_hiring() -> void:
	print("Hiring")
	BaseHub.new_campaign(SEED)
	var pool: Array = Hiring.pool(BaseHub.hiring(), 1)
	check(pool.size() == Hiring.POOL_SIZE and pool == Hiring.draw_pool(SEED, 0), "a new campaign's board: %d contractors drawn from the seed" % pool.size())
	check(Hiring.draw_pool(SEED, 0) == Hiring.draw_pool(SEED, 0) and Hiring.draw_pool(SEED, 1) != pool, "the same seed draws the same board; the next refresh another")
	check(Roster.members(BaseHub.roster()).is_empty(), "no fixed starting squad")
	if BaseEconomy.is_stub():
		check(BaseEconomy.funds() == BaseEconomy.STUB_START_FUNDS, "a small budget to hire with ($%d)" % BaseEconomy.funds())
	var ok := pool.all(func(c: Dictionary) -> bool:
		return Roles.has(StringName(c.role)) and int(c.demand) > 0 and int(c.fee) == int(c.demand) * Hiring.FEE_DAYS \
			and Roster.SKILLS.all(func(s: String) -> bool: return float(c.skills[s]) > 0.0 and float(c.skills[s]) <= 1.0))
	check(ok, "each has a role, skills, a wage demand and a fee of %d days' wage" % Hiring.FEE_DAYS)
	# Veterans cost more.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rookie := []
	var veteran := []
	for i in 400:
		var c := Hiring.candidate(rng)
		if int(c.missions) <= 2:
			rookie.append(int(c.demand))
		elif int(c.missions) >= 10:
			veteran.append(int(c.demand))
	check(not veteran.is_empty() and _mean(veteran) > _mean(rookie) + 20.0, "veterans ask more (about $%d/day against $%d)" % [_mean(veteran), _mean(rookie)])
	# Hire the cheapest.
	var cheapest := _cheapest(pool)
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_hire(String(cheapest.cid))
	var ids := Roster.ids(BaseHub.roster())
	var m := BaseHub.member(ids[0]) if ids.size() == 1 else {}
	check(why == "" and ids.size() == 1 and BaseEconomy.funds() == funds - int(cheapest.fee), "hiring %s costs the $%d fee" % [cheapest.name, int(cheapest.fee)])
	check(not m.is_empty() and m.callsign == cheapest.callsign and m.role == cheapest.role and int(m.wage) == int(cheapest.demand)
		and Roster.gear_counts(m.gear).size() > 3, "they join with their role, skills, wage and their role's kit as their own gear")
	check(Hiring.find(BaseHub.hiring(), String(cheapest.cid), 1).is_empty(), "and leave the board")
	BaseHub.base()["stub_funds"] = 10
	var pricey := _cheapest(Hiring.pool(BaseHub.hiring(), 1))
	check(BaseHub.server_hire(String(pricey.cid)) != "" and Roster.ids(BaseHub.roster()).size() == 1, "no cash, no hire")
	BaseHub.base()["stub_funds"] = BaseEconomy.STUB_START_FUNDS
	BaseHub.server_advance_days(Hiring.REFRESH_DAYS)
	check(int(BaseHub.hiring().refresh) == 1 and Hiring.pool(BaseHub.hiring(), BaseHub.day()) == Hiring.draw_pool(SEED, 1),
		"after %d days the board turns over (refresh 1, from the seed)" % Hiring.REFRESH_DAYS)


func _test_wages() -> void:
	print("Wages")
	BaseHub.new_campaign(SEED)
	for i in 2:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), BaseHub.day())).cid))
	var daily := Roster.daily_wages(BaseHub.roster())
	var funds := BaseEconomy.funds()
	BaseHub.server_advance_days(BaseHub.WAGE_PERIOD_DAYS - 1)
	check(daily > 0 and BaseEconomy.funds() == funds, "wages accrue during the week ($%d/day for two)" % daily)
	BaseHub.server_advance_days(1)
	check(BaseEconomy.funds() == funds - daily * BaseHub.WAGE_PERIOD_DAYS, "and are paid weekly ($%d)" % (daily * BaseHub.WAGE_PERIOD_DAYS))


func _test_growth() -> void:
	print("Skills and wage after a mission")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var m := Hiring.candidate(rng)
	m["missions"] = 0
	m["wage"] = Roster.wage_of(m)
	var before: Dictionary = m.skills.duplicate()
	var wage := int(m.wage)
	var stats := Roster.ai_stats(m)
	Roster.after_mission(m, rng, 2)
	check(Roster.SKILLS.all(func(s: String) -> bool: return float(m.skills[s]) > float(before[s])), "every skill grows (aim %.2f -> %.2f)" % [before.aim, m.skills.aim])
	check(int(m.wage) > wage and int(m.missions) == 1 and int(m.xp) >= Roster.XP_PER_MISSION, "and the wage ($%d -> $%d), a mission and experience" % [wage, int(m.wage)])
	var after := Roster.ai_stats(m)
	check(after.combat > stats.combat and after.discipline > stats.discipline, "the squad AI aims and holds better (combat %.2f -> %.2f)" % [stats.combat, after.combat])


func _test_injuries_and_medbay() -> void:
	print("Injuries and the medbay")
	var leg := {"part": &"shin_l", "kind": "fracture", "name": "tibia"}
	var a := Roster.assess_injuries([leg], 1.0)
	check(int(a.days) == Roster.FRACTURE_DAYS and "broken tibia" in a.injuries, "a broken leg sits out %d days" % int(a.days))
	var b := Roster.assess_injuries([leg, {"part": &"thigh_r", "kind": "arterial", "clamped": true}], 0.62)
	check(int(b.days) == Roster.FRACTURE_DAYS + 2 * Roster.EXTRA_INJURY_DAYS, "with surgery and heavy blood loss: %d days" % int(b.days))
	check(int(Roster.assess_injuries([{"part": &"forearm_l", "kind": "graze"}], 0.95).days) == 0, "a graze and a little blood cost nothing")
	BaseHub.new_campaign(SEED)
	BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var mid := Roster.ids(BaseHub.roster())[0]
	var m := BaseHub.member(mid)
	Roster.injure(m, b, BaseHub.day())
	check(not Roster.is_available(m) and int(m.sit_out_days) == int(b.days), "a wounded squadmate sits out (%s)" % Roster.status_text(m))
	var quote := Roster.medbay_quote(m)
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_medbay(mid)
	check(why == "" and int(m.sit_out_days) == int(b.days) - int(quote.days_saved) and BaseEconomy.funds() == funds - int(quote.cost),
		"the medbay takes %d days off for $%d" % [int(quote.days_saved), int(quote.cost)])
	check(BaseHub.server_medbay(mid) != "", "once per injury")
	BaseHub.server_advance_days(int(m.sit_out_days))
	check(Roster.is_available(m) and (m.injuries as Array).is_empty(), "days pass and they're fit again")
	var main := Roster.main_character(BaseHub.roster(), "medbay_player")
	Roster.injure(main, a, BaseHub.day())
	check(BaseHub.server_medbay("player:medbay_player") == "" and int(main.sit_out_days) == Roster.FRACTURE_DAYS / 2,
		"players' main characters recover the same way (%d days left)" % int(main.sit_out_days))


func _test_respawn_pool() -> void:
	print("Respawn pool")
	BaseHub.new_campaign(SEED)
	var roster := BaseHub.roster()
	RosterDeployment.begin(roster, [], RosterDeployment.CONTRACT, "z", "", 1)
	for i in 4:
		BaseHub.server_count_respawn()
	var funds := BaseEconomy.funds()
	check(RosterDeployment.free_respawns_left(roster) == 0 and BaseEconomy.funds() == funds, "a contract zone: 4 free respawns")
	BaseHub.server_count_respawn()
	var dep := RosterDeployment.active(roster)
	check(int(dep.respawns_bought) == 1 and BaseEconomy.funds() == funds - BaseEconomy.respawn_price(), "the fifth is bought ($%d)" % BaseEconomy.respawn_price())
	BaseHub.base()["stub_funds"] = 0
	BaseHub.server_count_respawn()
	check(int(dep.respawns_bought) == 2 and BaseEconomy.funds() == -BaseEconomy.respawn_price(), "with no cash it goes on credit")
	RosterDeployment.begin(roster, [], RosterDeployment.HOT, "z", "", 1)
	check(RosterDeployment.free_respawns_left(roster) == 8, "a hot zone: 8 free")
	roster["deployment"] = {}


func _test_resolve() -> void:
	print("Extraction: back, MIA, killed")
	BaseHub.new_campaign(SEED)
	for i in 3:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var ids := Roster.ids(BaseHub.roster())
	var roster := BaseHub.roster()
	RosterDeployment.begin(roster, ids, RosterDeployment.CONTRACT, "zone_x", "", 1)
	for mid in ids:
		RosterDeployment.mark_spawned(roster, mid)
	var gear := {"slots": {"primary": "m4a1"}, "containers": {"vest": [], "pockets": [{"id": "frag_grenade", "count": 1}], "backpack": []}, "hands": ""}
	var rng := RandomNumberGenerator.new()
	var report := RosterDeployment.resolve(roster, {"members": {
		ids[0]: {"state": RosterDeployment.EXTRACTED, "gear": gear, "wounds": [], "blood": 1.0},
		ids[1]: {"state": RosterDeployment.LEFT_BEHIND, "gear": gear, "pos": [1.0, 0.0, 2.0]},
		ids[2]: {"state": RosterDeployment.KILLED}}}, rng, 2)
	var back := BaseHub.member(ids[0])
	var mia := BaseHub.member(ids[1])
	var dead := BaseHub.member(ids[2])
	check(Roster.is_available(back) and Roster.gear_counts(back.gear) == {"m4a1": 1, "frag_grenade": 1} and int(back.missions) >= 1,
		"who extracts comes back with what they carry")
	check(String(mia.status) == Roster.MIA and mia.mia_zone == "zone_x" and report.mia == [ids[1]], "who's left behind alive is MIA")
	check(String(dead.status) == Roster.DEAD and (dead.gear as Dictionary).is_empty() and report.dead == [ids[2]], "the dead are lost with their gear")
	check(not RosterDeployment.is_running(roster), "the deployment is over")
	check(RosterDeployment.recovered(roster, ids[1], 3, 4) and Roster.status_text(mia) == "Recovering (4 d)", "a recovery brings the MIA one home, to recover")
	check(not Roster.is_available(dead) and not RosterDeployment.recovered(roster, ids[2], 3), "the dead stay dead")


func _test_stand_ins() -> void:
	print("A recovering player plays a squadmate")
	BaseHub.new_campaign(SEED)
	BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var mid := Roster.ids(BaseHub.roster())[0]
	var main := Roster.main_character(BaseHub.roster(), BaseHub.profile())
	main["sit_out_days"] = 5
	var picks := BaseHub._pick_stand_ins([])
	check(picks.get(BaseHub.profile(), "") == mid, "an available squadmate stands in")
	var funds := BaseEconomy.funds()
	picks = BaseHub._pick_stand_ins([mid])
	var free := BaseHub.member(String(picks.get(BaseHub.profile(), "")))
	check(not free.is_empty() and free.mid != mid and BaseEconomy.funds() == funds and int(free.missions) <= 2,
		"with nobody free, a rookie is provided free (%s)" % free.get("callsign", "none"))


# --- A real session -----------------------------------------------------------------------------

func _test_session() -> void:
	print("The hub")
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "host_profile"
	BaseHub.new_campaign(SEED)
	for i in 3:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	for pair: Array in EXTRA_STASH:
		BaseArmory.add(BaseHub.stash(), StringName(pair[0]), int(pair[1]))
	Campaign.save_campaign()
	var ids := Roster.ids(BaseHub.roster())
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session(true)
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	check(level is BaseLevel, "the campaign starts at the base hub")
	var base := level as BaseLevel
	var up := await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return base.muster_soldier(mid) != null), 30.0)
	check(up, "the company's people stand at the muster line")
	var stash_counts := BaseArmory.counts(BaseHub.stash())
	check(BaseArmory.counts(base.server_collect_stash()) == stash_counts, "the stash lies in the armory as world items (%d kinds)" % stash_counts.size())
	var member0 := BaseHub.member(ids[0])
	var s0 := base.muster_soldier(ids[0])
	check(s0 != null and String(s0.name) == String(member0.callsign) and Roster.gear_counts(Roster.json_safe(s0.inventory.net_state)) == Roster.gear_counts(member0.gear),
		"each in their own gear, by callsign (%s)" % member0.callsign)
	await _run_joining_client(ids, stash_counts)
	await _test_armory(base)
	await _test_deployment()


## Starts a second process that joins the hub as a client and checks what it sees.
func _run_joining_client(ids: Array, stash_counts: Dictionary) -> void:
	print("A client in the hub")
	var callsigns: Array = ids.map(func(mid: String) -> String: return String(BaseHub.member(mid).callsign))
	var hire := _cheapest(Hiring.pool(BaseHub.hiring(), BaseHub.day()))
	var expect := {"callsigns": callsigns, "stash": stash_counts, "cid": String(hire.cid), "hire_callsign": String(hire.callsign)}
	var log_path := ProjectSettings.globalize_path("user://base_test_client%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/base_test.tscn", "--", "--join", "127.0.0.1",
		"--expect", Marshalls.utf8_to_base64(JSON.stringify(expect)), "--log", log_path]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "a client process starts")
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.strip_edges() != "":
				print("  (client) " + line.strip_edges())
	check(code == 0, "the client's checks pass (exit %d)" % code)
	check(Roster.ids(BaseHub.roster()).size() == ids.size() + 1, "the host hired who the client asked for (%d on the books)" % Roster.ids(BaseHub.roster()).size())


## Client process: joins the hub and checks the roster, the stash and a request through the host.
func _run_client() -> void:
	var args := OS.get_cmdline_user_args()
	var expect: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(args[args.find("--expect") + 1]))
	_log = FileAccess.open(args[args.find("--log") + 1], FileAccess.WRITE)
	Campaign.campaign_id = "test_base_client" + tag  # a client never saves, but keep apart anyway
	BaseHub.local_profile = "client_profile"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session(false)
	$Main/Menu.join("127.0.0.1")
	level = CompoundLevel.current(self)
	var got := await _wait_until(func() -> bool: return BaseHub.view.get("roster", {}).get("members", {}).size() == expect.callsigns.size(), 30.0)
	var members: Dictionary = BaseHub.view.get("roster", {}).get("members", {})
	var seen: Array = members.values().map(func(m: Dictionary) -> String: return String(m.callsign))
	seen.sort()
	var wanted: Array = expect.callsigns.duplicate()
	wanted.sort()
	check(got and seen == wanted, "the client sees the same roster: %s" % ", ".join(PackedStringArray(seen)))
	var want_stash: Dictionary = {}
	for id: String in expect.stash:
		want_stash[id] = int(expect.stash[id])
	var stash_ok := await _wait_until(func() -> bool: return BaseArmory.counts(BaseHub.view.get("stash", [])) == want_stash, 10.0)
	check(stash_ok, "and the same stash in the base screen's copy")
	var items_ok := await _wait_until(func() -> bool: return BaseArmory.counts(BaseArmory.from_world_items(level.items.get_children())) == want_stash, 20.0)
	check(items_ok, "and lying in the armory (%d items)" % level.items.get_child_count())
	var muster_ok := await _wait_until(func() -> bool:
		return expect.callsigns.all(func(c: String) -> bool: return level.ai.get_node_or_null(NodePath(c)) != null), 20.0)
	check(muster_ok, "the squadmates stand at the muster line on the client too")
	var known := await _wait_until(func() -> bool: return "client_profile" in BaseHub.view.get("players", {}).values(), 10.0)
	check(known, "the host knows the client's profile")
	BaseHub.request("hire", [String(expect.cid)])
	var hired := await _wait_until(func() -> bool:
		return BaseHub.view.get("roster", {}).get("members", {}).values().any(func(m: Dictionary) -> bool: return String(m.callsign).begins_with(String(expect.hire_callsign))), 10.0)
	check(hired, "a hire asked from the client goes through the host and comes back (%s)" % expect.hire_callsign)
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_log.close()
	Net.leave()
	get_tree().quit(failures)


func _test_armory(base: BaseLevel) -> void:
	print("The armory")
	var player: Soldier = level.players.get_node(^"1")
	var pistol: WorldItem = null
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"m17":
			pistol = n
	check(pistol != null, "the M17 from the stash lies in the armory")
	if pistol == null:
		return
	player.global_position = pistol.global_position + Vector3(0.6, 0, 0)
	player._server_interact.rpc_id(1, pistol.get_path())
	await _frames(3)
	var counts := BaseArmory.counts(base.server_collect_stash())
	check(player.inventory.slots[&"sidearm"] == &"m17" and not counts.has("m17"), "kitting up takes it out of the stash")
	player._server_drop.rpc_id(1, &"sidearm")
	await _frames(3)
	check(BaseArmory.counts(base.server_collect_stash()).get("m17", 0) == 1, "putting it back (dropped in the base) returns it")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	check(BaseArmory.count_of(BaseHub.stash(), &"m17") == 1, "the campaign's stash follows")
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_buy(&"pressure_bandage", 4)
	await _frames(3)
	check(why == "" and BaseArmory.counts(base.server_collect_stash()).get("pressure_bandage", 0) >= 4
		and BaseEconomy.funds() == funds - 4 * BaseEconomy.item_price(&"pressure_bandage"), "the shop delivers to the armory for its price")
	BaseHub.server_save()
	var saved := BaseArmory.counts(BaseHub.stash())
	Campaign.load_campaign()
	check(BaseArmory.counts(BaseHub.stash()) == saved and saved.get("m17", 0) == 1, "the stash survives a save and reload")


func _test_deployment() -> void:
	print("Deployment")
	var base := level as BaseLevel
	var ids := Roster.ids(BaseHub.roster())
	var squad: Array = ids.slice(0, 3)
	var a: String = squad[0]
	var b: String = squad[1]
	var c: String = squad[2]
	var callsign_a := String(BaseHub.member(a).callsign)
	var callsign_b := String(BaseHub.member(b).callsign)
	var callsign_c := String(BaseHub.member(c).callsign)
	base.muster_soldier(a).inventory.take(&"smoke_purple", 1)  # what Give item would do
	var player: Soldier = level.players.get_node(^"1")
	player.inventory.strip()
	player.inventory.take(&"plate_carrier")
	player.inventory.take(&"helmet")
	for mid: String in squad:
		BaseHub.server_pick(mid, true)
	var wage_a := int(BaseHub.member(a).wage)
	var day := BaseHub.day()
	var why := BaseHub.server_deploy({"zone_id": "test_base_zone" + tag})
	check(why == "" and RosterDeployment.is_running(BaseHub.roster()), "deploy starts the deployment")
	level = CompoundLevel.current(self)
	check(level != null and not level is BaseLevel, "and the session moves to the zone")
	var up := await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return _roster_soldier(mid) != null), 40.0)
	check(up, "the squad spawns as the roster's people (%s, %s, %s)" % [callsign_a, callsign_b, callsign_c])
	for s: Node in level.ai.get_children():
		if (s as Soldier).faction == &"hostile":
			s.queue_free()
	var sa := _roster_soldier(a)
	if not up or sa == null:
		return
	check(String(sa.name) == callsign_a and sa.inventory.count_of(&"smoke_purple") == 1, "%s carries the smoke handed over at the base" % callsign_a)
	check(level.ai.get_children().filter(func(n: Node) -> bool: return (n as Soldier).faction == &"friendly" and not n.is_queued_for_deletion()).size() == 3,
		"only the three picked deploy: nobody else fills the other slots")
	check(is_equal_approx(SquadAI.of(sa).combat, Roster.ai_stats(BaseHub.member(a)).combat), "their aim skill drives the AI (combat %.2f)" % SquadAI.of(sa).combat)
	player = level.players.get_node(^"1")
	check(player.inventory.slots[&"vest"] == &"plate_carrier" and player.inventory.slots[&"helmet"] == &"helmet", "the player deploys in the kit from the armory")
	# A player death counts against the pool.
	player.vitals.server_kill()
	await _frames(2)
	check(int(RosterDeployment.active(BaseHub.roster()).get("respawns_used", 0)) == 1, "a player respawn counts (%d free left)" % RosterDeployment.free_respawns_left(BaseHub.roster()))
	# A picks up a frag; C is killed; B wanders off; the rest extract by the player.
	var frags := sa.inventory.count_of(&"frag_grenade") + sa.inventory.take(&"frag_grenade", 1)
	var sc := _roster_soldier(c)
	sc.vitals.server_kill()
	await _frames(2)
	var sb := _roster_soldier(b)
	SquadAI.of(sb).process_mode = Node.PROCESS_MODE_DISABLED
	sb.global_position = player.global_position + Vector3(0, 0, -45)
	SquadAI.of(sa).process_mode = Node.PROCESS_MODE_DISABLED
	sa.global_position = player.global_position + Vector3(1, 0, 1)
	var report := BaseHub.server_extract_near(player.global_position, 20.0)
	check(report.get("extracted", []) == [a] and report.get("mia", []) == [b] and report.get("dead", []) == [c],
		"extraction: %s back, %s MIA, %s killed" % [callsign_a, callsign_b, callsign_c])
	check(String(BaseHub.member(b).status) == Roster.MIA and _recovery_requested(b), "the one left behind is MIA and a recovery contract is requested")
	var zone_save: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/test_base_zone%s.json" % [GameState.SAVE_DIR, tag]))
	var zone_bodies: Array = zone_save.get("bodies", []) if zone_save is Dictionary else []
	check(String(BaseHub.member(c).status) == Roster.DEAD and (BaseHub.member(c).gear as Dictionary).is_empty()
		and zone_bodies.any(func(r: Dictionary) -> bool: return String(r.get("label", "")) == callsign_c and not (r.get("gear", {}) as Dictionary).is_empty()),
		"the dead one is lost, gear and all on the body saved in the zone")
	check(int(BaseHub.member(a).wage) > wage_a and int(BaseHub.member(a).missions) >= 1, "the one who came back earns more ($%d -> $%d)" % [wage_a, int(BaseHub.member(a).wage)])
	check(BaseHub.day() == day + 1, "a day passed")
	level = CompoundLevel.current(self)
	check(level is BaseLevel, "everyone is back at the base")
	base = level as BaseLevel
	var back := await _wait_until(func() -> bool: return base.muster_soldier(a) != null, 30.0)
	var sa_home := base.muster_soldier(a)
	check(back and sa_home.inventory.count_of(&"smoke_purple") == 1 and sa_home.inventory.count_of(&"frag_grenade") == frags,
		"%s's gear came home with them (the smoke, and the frag picked up in the zone)" % callsign_a)
	check(base.muster_soldier(b) == null and base.muster_soldier(c) == null, "the MIA and the dead aren't at the muster line")
	var gear_a := Roster.gear_counts(BaseHub.member(a).gear)
	BaseHub.server_save()
	Campaign.load_campaign()
	check(Roster.gear_counts(BaseHub.member(a).gear) == Roster.gear_counts(Roster.json_safe(sa_home.inventory.net_state)) and gear_a.get("smoke_purple", 0) == 1,
		"their gear survives a save and reload")
	check(String(BaseHub.member(b).status) == Roster.MIA and String(BaseHub.member(c).status) == Roster.DEAD, "and so do MIA and KIA")


func _roster_soldier(mid: String) -> Soldier:
	for n: Node in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and s.has_meta(&"roster_id") and String(s.get_meta(&"roster_id")) == mid and not s.vitals.is_dead():
			return s
	return null


func _recovery_requested(mid: String) -> bool:
	if not BaseEconomy.is_stub():
		return true  # the economy's own contract board has it
	return BaseHub.base().get("recovery_requests", []).any(func(r: Dictionary) -> bool: return String(r.get("mid", "")) == mid)


# --- Helpers --------------------------------------------------------------------------------------

func _cheapest(pool: Array) -> Dictionary:
	var best := {}
	for c: Dictionary in pool:
		if best.is_empty() or int(c.fee) < int(best.fee):
			best = c
	return best


func _mean(values: Array) -> float:
	var total := 0.0
	for v: Variant in values:
		total += float(v)
	return total / maxf(values.size(), 1.0)


## Waits until `cond` holds or `timeout` seconds pass; returns whether it held.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
