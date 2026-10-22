extends Node
## Headless checks for requests between players and friendly units (docs/combined_arms.md 4.1-4.3,
## 4.6; phase B4's skeleton): who answers, each answer and refusal with its reason, counter-offers,
## the lifecycle states, limits and merges, the decline cooldown, radios, sitreps, allies' asks
## raised, answered, done and expired, the HUD cards and RadioVoice's words. B2 adds the jobs
## themselves (SideCommand as the executor) and B5 the scripted combined fight.
##   <voxel godot exe> --headless --path . res://tests/requests_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var broker: RequestBroker
var intel: SideIntel


func _ready() -> void:
	GameState.zone_id = "test_requests" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(360.0).timeout.connect(func() -> void:
		print("REQUESTS TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_decide()
	_test_voice_words()
	_test_deconfliction_pure()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	await _frames(5)
	broker = RequestBroker.of(level)
	intel = SideIntel.of(level)
	check(broker != null, "every level has a RequestBroker")
	if broker == null or intel == null:
		print("REQUESTS TEST FAILED (no broker)")
		get_tree().quit(1)
		return
	await _test_flow()
	_test_asks()
	await _test_deconfliction_play()
	await _test_combined_fight()
	_test_lines_voiced()
	GameState.delete_save()
	print("REQUESTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Pure ----------------------------------------------------------------------------------------

func _row(extra := {}) -> Dictionary:
	var row := {"id": "Saber", "kind": "rifle_squad", "callsign": "Saber", "pos": Vector3.ZERO, "up": 8, "ce": 0.9, "ce_band": "green",
		"ammo_band": "green", "mgs": 1, "launchers": 0, "medics": 1, "smoke": 2, "vehicle_kinds": [], "mounted_in": [], "in_contact": false,
		"role": "", "sitrep_at": 0.0}
	row.merge(extra, true)
	return row


func _req(kind: String, at := Vector3(0, 0, 100)) -> Dictionary:
	return {"kind": kind, "target": {"pos": at}, "by": 1}


func _test_decide() -> void:
	print("Who can answer what (4.2)")
	check(RequestBroker.capable(_row(), "suppress") and not RequestBroker.capable(_row({"mgs": 0}), "suppress"), "suppression needs an MG (or armour, or a gun team)")
	check(RequestBroker.capable(_row({"mgs": 0, "vehicle_kinds": ["ifv"]}), "suppress"), "an IFV can suppress")
	check(RequestBroker.capable(_row(), "medic") and not RequestBroker.capable(_row({"medics": 0}), "medic"), "a medic request needs a medic")
	check(RequestBroker.capable(_row({"kind": "mortar_section", "smoke": 0}), "smoke"), "a mortar section can lay smoke")
	check(RequestBroker.capable(_row({"vehicle_kinds": ["mbt"]}), "armour") and not RequestBroker.capable(_row(), "armour"), "armour support needs armour")
	print("Answers and refusals, in a real unit's order")
	var a := RequestBroker.decide(_row(), _req("suppress"))
	check(a.state == "acked" and float(a.eta_s) <= 10.0, "an MG team 100 m off: yes, on it now (ETA %.0f s)" % float(a.get("eta_s", -1)))
	check(RequestBroker.decide(_row({"role": "assault"}), _req("suppress")).why == "Committed to an assault", "mid-assault: committed")
	check(RequestBroker.decide(_row({"in_contact": true, "ce_band": "red"}), _req("suppress")).why == "We're pinned", "in contact and RED: pinned")
	check(RequestBroker.decide(_row({"ammo_band": "red"}), _req("suppress")).why == "Ammo black", "red on ammo: ammo black")
	check(RequestBroker.decide(_row({"ammo_band": "amber"}), _req("ammo")).why == "We're amber ourselves", "asked for ammo while amber: amber ourselves")
	check(RequestBroker.decide(_row({"medics": 0}), _req("medic", Vector3(0, 0, 50))).why == "No medic free", "no medic: no medic free")
	check(RequestBroker.decide(_row({"smoke": 0}), _req("smoke", Vector3(0, 0, 50))).why == "No smoke left", "no smoke: no smoke left")
	check(RequestBroker.decide(_row(), _req("suppress", Vector3(0, 0, 2000))).why == "Out of range", "2 km off: out of range")
	var c := RequestBroker.decide(_row(), _req("suppress", Vector3(0, 0, 1200)))
	check(c.state == "countered" and float(c.counter.eta_s) > 120.0, "a long walk: a counter-offer with its ETA (%s)" % c.get("why", ""))
	var spared := RequestBroker.decide(_row(), _req("suppress"), {"ok": false, "why": "Our orders are to push", "delay_s": 120.0})
	check(spared.state == "countered" and spared.why == "Our orders are to push", "the commander needs it a while: a delay offered (B2's can_spare)")
	check(RequestBroker.decide(_row(), _req("suppress"), {"ok": false, "why": "Last reserve"}).state == "declined", "the commander can't spare it: declined")
	var mounted := RequestBroker.eta_of(_row({"mounted_in": ["v1"]}), _req("armour", Vector3(0, 0, 800)))
	check(is_equal_approx(mounted, 100.0), "mounted, 800 m is 100 s at 8 m/s")


func _test_voice_words() -> void:
	print("RadioVoice")
	check(RadioVoice.tokens("Saber 2, copy, on in 40 seconds.") == PackedStringArray(["saber", "two", "copy", "on", "in", "four", "zero", "seconds"]),
		"numbers go digit by digit, punctuation drops")
	check(RadioVoice.tokens("041 053, north-east") == PackedStringArray(["zero", "four", "one", "zero", "five", "three", "north", "east"]),
		"grids and compass words split into clips")
	check(RadioVoice.missing("Saber 2, unable. We're pinned.").is_empty(), "a refusal's words are all in the vocabulary")
	check(RadioVoice.clips("zzz unknown", 0).is_empty(), "a word without a clip: no audio, the subtitle alone")


# --- In a level ----------------------------------------------------------------------------------

func _spawn(nm: String, pos: Vector3, loadout: Array) -> Soldier:
	return level.spawn_soldier({"name": nm, "faction": "friendly", "variant": "urban", "pos": pos, "loadout": loadout, "combat": 0.7,
		"discipline": 0.6, "guard": true})


func _test_flow() -> void:
	print("A request's life")
	var sq := Squad.new()
	sq.name = "ReqSaber"
	sq.faction = &"friendly"
	level.add_child(sq)
	var gunner := _spawn("ReqGunner", Vector3(-10, 0.1, 10), ["m249"])
	var rifle := _spawn("ReqRifle", Vector3(-9, 0.1, 10), ["m4a1"])
	await _frames(3)
	for s: Soldier in [gunner, rifle]:
		s.set_physics_process(false)
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		SquadAI.of(s).squad = sq
		var w := s.active_weapon()
		if w:
			s.inventory.take(Soldier._ammo_of(w), 8)  # a full load: not black on ammo
	sq.leader = gunner
	intel.server_feed()
	var gid := GroupBoard.group_id(sq)
	check(intel.board.rows.has(gid) and int(intel.board.rows[gid].mgs) == 1, "the group is on the board with its MG")
	var me := player.owner_peer()
	var target := Vector3(10, 0, -10)
	var r := broker.server_request(me, "suppress", target, player.global_position)
	check(r.get("state") == "sent" and r.group == gid, "suppression asked: the MG group will answer (%s)" % r.get("callsign", ""))
	var wait := float(r.answer_at) - broker.now()
	check(wait >= 2.0 - 0.01 and wait <= 6.0 * 1.5 + 0.01, "it answers after a radio delay (%.1f s)" % wait)
	var cards := player._hud.find_child("RequestCards", true, false) as RequestCards
	check(cards != null and cards.mine().any(func(x: Dictionary) -> bool: return int(x.id) == int(r.id)), "the player sees it as a card")
	broker.advance(wait + 0.1)
	check(r.state == "acked" and float(r.eta_s) >= 0.0, "accepted with an ETA")
	check(broker.lines.back().text.begins_with(String(r.callsign) + ", copy, suppression at "), "said on the net: \"%s\"" % broker.lines.back().text)
	check(cards.card_text(r).contains("on it"), "the card reads \"%s\"" % cards.card_text(r))
	var again := broker.server_request(me, "suppress", target + Vector3(5, 0, 0), player.global_position)
	check(int(again.id) == int(r.id) and int(r.merged) == 1, "the same request again merges")
	check(broker.server_progress(int(r.id), "en_route") and r.state == "en_route", "the job: en route")
	check(broker.server_progress(int(r.id), "on_station") and r.state == "on_station", "on station")
	broker.advance(61.0)
	check(r.state == "done", "done when its 60 s of suppression run out")
	print("Refusals, cooldown, counter-offers, cancel, limits")
	var m := broker.server_request(me, "medic", Vector3(-8, 0, 12), player.global_position, gid)
	broker.advance(10.0)
	check(m.state == "declined" and m.why == "No medic free", "a medic from a group without one: \"%s\"" % m.why)
	var m2 := broker.server_request(me, "medic", Vector3(-8, 0, 12), player.global_position, gid)
	check(m2.get("nobody", false), "the same group isn't asked again for 30 s")
	broker.advance(10.0)
	check(m2.state == "declined" and String(m2.why).begins_with("No unit can give"), "and with nobody else: \"%s\"" % m2.why)
	var far := broker.server_request(me, "suppress", Vector3(-10, 0, 1250), player.global_position)
	broker.advance(10.0)
	check(far.state == "countered" and not (far.counter as Dictionary).is_empty(), "a long walk: \"%s\"" % far.why)
	check(broker.server_accept_counter(me, int(far.id)) and far.state == "acked", "the player takes the counter-offer")
	var c := broker.server_request(me, "suppress", Vector3(15, 0, -15), player.global_position)
	var d := broker.server_request(me, "suppress", Vector3(-25, 0, -15), player.global_position)
	var e := broker.server_request(me, "suppress", Vector3(15, 0, 25), player.global_position)
	check(e.has("why") and not e.has("id"), "a fourth open request: \"%s\"" % e.get("why", ""))
	check(broker.server_cancel(me, int(c.id)) and c.state == "cancelled", "cancelled from the card")
	broker.advance(10.0)
	check(d.state == "acked", "the other is accepted")
	broker.advance(RequestBroker.num("until_s", 600.0))
	check(d.state == "failed" and d.why == "Timed out" and far.state == "failed", "with no job started it fails at its limit (B2 runs the jobs)")
	print("Sitrep (4.2.9)")
	var s := broker.server_request(me, "sitrep", gunner.global_position, player.global_position, gid)
	broker.advance(10.0)
	check(s.state == "done" and String(s.text).contains(" up, ammo "), "\"%s\"" % s.text)
	print("Radios")
	sq.set_meta(&"no_radio", true)
	player.global_position = Vector3(0, 0.1, 0)
	gunner.global_position = Vector3(-200, 0.1, 200)
	rifle.global_position = Vector3(-201, 0.1, 200)
	intel.advance(31.0)  # its next sitrep puts it out there
	var n := broker.server_request(me, "suppress", Vector3(-190, 0, 190), player.global_position)
	check(n.get("nobody", false), "a group with no radio, out of earshot, isn't asked")
	sq.remove_meta(&"no_radio")
	broker.set_meta(&"test_squad", sq)


func _test_asks() -> void:
	print("Allies asking players (4.3)")
	var sq := broker.get_meta(&"test_squad") as Squad
	var gid := GroupBoard.group_id(sq)
	var row: Dictionary = intel.board.rows[gid]
	player.global_position = (row.pos as Vector3) + Vector3(100, 0, 0)
	row.in_contact = true
	row.ce_band = "amber"
	broker._asked.clear()
	broker._scan_asks()
	var cards := player._hud.find_child("RequestCards", true, false) as RequestCards
	var ask := cards.my_ask()
	check(not ask.is_empty() and ask.kind == "ask_support", "an AMBER group in contact asks the nearest player: \"%s\"" % ask.get("text", ""))
	if ask.is_empty():
		return
	check(broker.server_answer_ask(player.owner_peer(), int(ask.id), true) and ask.state == "accepted", "he says yes")
	check(int(broker.cooperation.get(player.owner_peer(), 0)) == 1, "an answered ask counts toward his cooperation")
	row.in_contact = false
	broker._check_asks()
	check(ask.state == "done", "done once the group is out of contact")
	row.ammo_band = "red"
	broker._scan_asks()
	var ammo := cards.my_ask()
	check(not ammo.is_empty() and ammo.kind == "ask_ammo", "red on ammo near him: \"%s\"" % ammo.get("text", ""))
	broker.advance(31.0)
	check(not ammo.is_empty() and ammo.state == "expired", "unanswered for 30 s, it lapses (declining costs nothing)")


func _test_lines_voiced() -> void:
	print("Every line on the net is in RadioVoice's words")
	var gaps := {}
	for l: Dictionary in broker.lines:
		for w in RadioVoice.missing(String(l.text)):
			if not String(l.text).contains(w.capitalize()):  # a man's name: that line is a subtitle alone (RadioVoice)
				gaps[w] = true
	check(gaps.is_empty(), "%d lines said, words missing: %s" % [broker.lines.size(), ", ".join(PackedStringArray(gaps.keys()))])


# --- B5: deconfliction (4.5) ----------------------------------------------------------------------

func _test_deconfliction_pure() -> void:
	print("B5: sectors, lanes, bubbles, check fire")
	var a := Deconfliction.sector_of(Vector3(0, 0, 0), Vector3(0, 0, -200))
	check(is_equal_approx(float(a.half), 30.0) and Deconfliction.in_sector(a, Vector3(20, 0, -100)) and not Deconfliction.in_sector(a, Vector3(50, 0, -100)),
		"a sector is a corridor at least 30 m either side of the axis")
	check(Deconfliction.crosses(a, Vector3(-100, 0, -100), Vector3(100, 0, -100)) and not Deconfliction.crosses(a, Vector3(100, 0, 0), Vector3(100, 0, -200)),
		"a shot across it crosses it; one alongside doesn't")
	var b := Deconfliction.sector_of(Vector3(20, 0, 0), Vector3(20, 0, -200))
	check(Deconfliction.overlap(a, b), "two lanes 20 m apart overlap")
	check(not Deconfliction.overlap(a, Deconfliction.sector_of(Vector3(20, 0, 0), Vector3(200, 0, -150))), "two that start together and part don't")
	var c := Deconfliction.shift_clear(b, [a])
	check(not Deconfliction.overlap(a, c), "the second lane is shifted clear (%.0f m)" % (c.to as Vector2).distance_to(b.to))
	var bends := Deconfliction.detour(Vector3(0, 0, 0), Vector3(0, 0, -400), [Vector3(10, 0, -200)])
	check(bends.size() == 1 and SideCommand._flat(bends[0], Vector3(10, 0, -200)) > Deconfliction.BUBBLE_M, "a move through a player's bubble bends round it")
	check(Deconfliction.detour(Vector3(0, 0, 0), Vector3(0, 0, -400), [Vector3(300, 0, -200)]).is_empty(), "one that misses it doesn't")
	var p := Vector3(500, 0, 500)
	Deconfliction.server_check_fire(p, &"friendly", "test")
	check(Deconfliction.checked(p + Vector3(60, 0, 0)) and not Deconfliction.checked(p + Vector3(150, 0, 0)), "check fire: everything into 100 m of the point stops")
	check(not Deconfliction.checked(p, &"hostile"), "only our side's fire")
	Deconfliction.offset += 31.0
	check(not Deconfliction.checked(p), "for 30 s")
	Deconfliction.offset -= 31.0


func _test_deconfliction_play() -> void:
	print("B5: holding fire in play")
	var sq := Squad.new()
	sq.name = "DeconSaber"
	sq.faction = &"friendly"
	level.add_child(sq)
	var man := _spawn("DeconA", Vector3(-30, 0.1, 30), ["m249"])
	await _frames(3)
	man.set_physics_process(false)
	SquadAI.of(man).process_mode = Node.PROCESS_MODE_DISABLED
	SquadAI.of(man).squad = sq
	sq.set_meta(&"sector", Deconfliction.sector_of(Vector3(-30, 0, 30), Vector3(-30, 0, -40)))
	player.global_position = Vector3(-30, 0.1, -20)
	check(Deconfliction.holds_fire(man, Vector3(-30, 1, -30), true), "an allied group won't suppress a point in a player's bubble")
	check(not Deconfliction.holds_fire(man, Vector3(-30, 1, -30), false), "but fires at an enemy it sees there (the fan and the line guard that shot)")
	player.global_position = Vector3(40, 0.1, 40)
	var other := Squad.new()
	other.name = "DeconOther"
	other.faction = &"friendly"
	level.add_child(other)
	other.hc_id = &"decon_other"
	other.set_meta(&"sector", Deconfliction.sector_of(Vector3(0, 0, 40), Vector3(0, 0, -40)))
	check(Deconfliction.holds_fire(man, Vector3(30, 1, 0), false), "a shot across another group's sector, at a target outside its own, is held")
	check(not Deconfliction.holds_fire(man, Vector3(-30, 1, -10), false), "one inside its own sector isn't")
	Deconfliction.server_check_fire(Vector3(-30, 0, -10), &"friendly", "test")
	check(Deconfliction.holds_fire(man, Vector3(-30, 1, -10), false), "a check fire stops it, even at a man it sees")
	Deconfliction.check_fires.clear()
	print("B5: the FDC checks fire")
	var fs := FireSupport.of(level)
	if fs:
		var aim := Vector3(0, 0, 0)
		fs.missions["mortar"] = {"unit": "mortar", "by": null, "aim": aim, "confirmed": false, "fired": 1, "ends_at": INF, "last_at": FireSupport.now(), "gun": Vector3(0, 0, 900)}
		fs.rounds.append({"unit": "mortar", "land": aim, "aim": aim, "spread": 5.0, "fire_at": FireSupport.now() - 0.1, "when": FireSupport.now() + 20.0, "shell": "he",
			"by": null, "first": true, "last": true, "ffe": true, "shot": false, "warned": false, "range_m": 900.0})
		player.global_position = Vector3(10, 0.1, 10)  # a friendly in the target area
		fs._step()
		check(fs.rounds.filter(func(r: Dictionary) -> bool: return String(r.unit) == "mortar").is_empty(), "a friendly walks into the target area: the rounds not yet fired stop")
		fs.missions.erase("mortar")
	print("B5: a check fire from a player")
	var cf := broker.server_request(player.owner_peer(), "check_fire", Vector3(0, 0, -30), player.global_position)
	check(cf.get("state") == "done" and Deconfliction.checked(Vector3(10, 0, -30)), "\"All stations, check fire\": in force at once")
	Deconfliction.check_fires.clear()
	man.queue_free()
	sq.queue_free()
	other.queue_free()
	await _frames(2)


## A scripted combined fight (B5's test): two allied groups (one supporting by fire, one
## assaulting), a squadmate beside the lane, against three hostiles; it runs live for a while and no
## friendly may be hit by a friendly. Then a check fire on the hostiles stops the allies' fire
## within a second.
func _test_combined_fight() -> void:
	print("B5: a scripted combined fight: no blue on blue")
	Deconfliction.incidents.clear()
	var foes: Array[Soldier] = []
	for i in 3:
		foes.append(level.spawn_soldier({"name": "FightFoe%d" % i, "faction": "hostile", "variant": "urban", "pos": Vector3(-6 + i * 4, 0.1, -38),
			"loadout": ["akm"], "combat": 0.3, "discipline": 0.5, "guard": true}))
	var cmd := SideCommand.install(level, &"friendly", OperationPlan.new({"phases": [{"name": "fight", "limit_s": 900.0,
		"axis": [Vector3(0, 0, 30), Vector3(0, 0, -38)], "main": "line", "objectives": [{"id": "line", "label": "the line", "pos": Vector3(0, 0, -38), "radius": 12.0}]}],
		"ld": Vector3(0, 0, 30), "rally": Vector3(30, 0, 40), "hhour_s": 0.0, "flanks": false}))
	var groups: Array[Squad] = []
	for k in 2:
		var sq := Squad.new()
		sq.name = "FightAllied%d" % k
		sq.faction = &"friendly"
		level.add_child(sq)
		groups.append(sq)
		var men: Array[Soldier] = []
		for i in 4:
			men.append(_spawn("FightA%d_%d" % [k, i], Vector3(-20 + k * 30 + i * 2, 0.1, 25), ["m249" if i == 0 else "m4a1"]))
		await _frames(2)
		for s in men:
			SquadAI.of(s).squad = sq
			var w := s.active_weapon()
			if w:
				s.inventory.take(Soldier._ammo_of(w), 8)
		sq.leader = men[0]
		cmd.server_register(sq, "weapons_team" if k == 0 else "rifle_squad", "Saber %d" % (k + 5))
	var mate := _spawn("FightMate", Vector3(14, 0.1, -10), ["m4a1"])  # beside the lane, in the fight
	player.global_position = Vector3(40, 0.1, 30)
	for f in foes:
		SideIntel.of(level).picture.submit({"kind": "inf", "count": 1, "pos": f.global_position}, SideIntel.of(level).now())
	var t_end := Soldier._now() + 25.0
	while Soldier._now() < t_end:
		await get_tree().process_frame
	check(Deconfliction.incidents.is_empty(), "25 s of a fight with two allied groups and a squadmate: no friendly hit a friendly (%d incidents)" % Deconfliction.incidents.size())
	var rounds := func() -> int:
		var n := 0
		for sq in groups:
			for s: Soldier in sq.members():
				var w := s.active_weapon()
				if w:
					n += s.inventory.rounds_in(s.active_slot) + s.inventory.spare_rounds(Soldier._ammo_of(w), w)
		return n
	for f in foes:
		Deconfliction.server_check_fire(f.global_position, &"friendly", "test")
	var t_cf := Soldier._now()
	while Soldier._now() < t_cf + 1.0:
		await get_tree().process_frame
	var held: int = rounds.call()
	while Soldier._now() < t_cf + 6.0:
		await get_tree().process_frame
	check(int(rounds.call()) == held, "a check fire on the hostiles: from 1 s on the allies fire no more at them")
	Deconfliction.check_fires.clear()
	level.remove_child(cmd)
	cmd.free()
	for f in foes:
		if is_instance_valid(f):
			f.queue_free()
	mate.queue_free()
	for sq in groups:
		for s: Soldier in sq.members():
			s.queue_free()
		sq.queue_free()
	await _frames(2)
