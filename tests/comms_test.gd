extends Node
## Headless squad comms checks (Captain, 2026-10-14: "bots should act like players,
## communicate with the player"; docs/squad_comms.md). Hosts a real session with the squad
## (hostiles removed, test ones staged by hand):
## - Delivery (Callouts): the side's net budget and the queue's TTL, CRITICAL lines first,
##   one waiting line per speaker and priority, answers to one player only, explanations held
##   while the squad fights, each listener's own "{where}", a group of contacts called once.
## - Answers (SquadComms): an order is acknowledged once, a squadmate carrying a body says why
##   he can't, one on his way to a casualty says he'll come after, a failed order in his own
##   words, Status? to the asker only and in turn, "In position" once there.
## - Unprompted: pinned, hit, low and last magazine, falling behind (one line for those just
##   following), stuck, a move explained, a casualty given up.
## - A firefight's chatter stays inside the budget, with no explanations meanwhile.
##   <voxel godot exe> --headless --path . res://tests/comms_test.tscn
## Exits with the number of failures.

## The firefight's window, and the most it may say (proposed: Callouts' budget allows about
## 40 a minute plus the CRITICAL lines that may overdraw it).
const FIREFIGHT_S := 30.0
const MAX_SIDE_PER_MIN := 55.0
const MAX_SPEAKER_PER_MIN := 20.0

var failures := 0
var level: CompoundLevel
var player: Soldier
var callouts: Callouts
var squad: Squad
var comms: SquadComms


func _ready() -> void:
	GameState.zone_id = "test_comms" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("COMMS TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	callouts = level.callouts
	squad = level.squad_for(&"friendly")
	_remove_hostiles()
	await _frames(10)
	comms = SquadComms.of(squad)
	check(comms != null and squad.comms == comms and SquadComms.of(level.squad_for(&"hostile")) == null,
		"the friendly squad has its comms (the hostile side none)")
	await _test_delivery()
	await _test_order_answers()
	await _test_unprompted()
	await _test_firefight()
	GameState.delete_save()
	print("COMMS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Delivery ---------------------------------------------------------------------------------

func _test_delivery() -> void:
	print("Delivery: priorities, the side's budget, the queue")
	_clear_contact()
	_place(player, Vector3(0, 0.1, 16))
	player.rotation = Vector3.ZERO
	_freeze(true)  # their own callouts would use the budget the checks count
	comms.paused = true
	var u := _squad()
	callouts.reset()
	var now_sent := 0
	for i in 5:
		if callouts.say(u[i], &"moving"):
			now_sent += 1
	check(now_sent == int(Callouts.CHANNEL_BURST) and callouts.waiting().size() == 2,
		"five squadmates at once: %d go now, the other %d wait their turn" % [now_sent, callouts.waiting().size()])
	await _seconds(Callouts.CHANNEL_REFILL_S + 0.3)
	check(_said(&"moving").size() == 4, "the fourth goes once the net has room again (%d said)" % _said(&"moving").size())
	await _seconds(Callouts.TTL_S[Callouts.Prio.TACTICAL])
	check(_said(&"moving").size() == 4 and int(callouts.dropped.get(&"moving", 0)) == 1 and callouts.waiting().is_empty(),
		"the fifth went stale waiting (%.1f s) and is dropped, never said late (%d said, dropped %s)" % [Callouts.TTL_S[Callouts.Prio.TACTICAL],
		_said(&"moving").size(), callouts.dropped])

	callouts.reset()
	for i in 3:
		callouts.say(u[i], &"moving")
	check(not callouts.say(u[3], &"explain", "Going for the kit"), "with the net full, an explanation (INFO) waits")
	check(callouts.say(u[4], &"man_down", "Man down! Test is down"), "a CRITICAL line goes at once all the same")
	await _seconds(Callouts.CHANNEL_REFILL_S + 0.4)
	var order: Array = callouts.sent.map(func(c: Dictionary) -> StringName: return c.id)
	check(order.find(&"explain") > order.find(&"man_down") and order.find(&"man_down") >= 0, "and the explanation follows when there's room (%s)" % [order])

	callouts.reset()
	callouts.say(u[0], &"reloading")
	check(not callouts.say(u[0], &"moving") and not callouts.say(u[0], &"covering"), "a speaker's next lines wait for his gap")
	var mine := func() -> Array: return callouts.waiting().filter(func(p: Dictionary) -> bool: return p.who == String(u[0].name))
	check(mine.call().size() == 1 and mine.call()[0].id == &"covering",
		"the newer line takes the older one's place at the same priority (%s)" % [mine.call().map(func(p: Dictionary) -> StringName: return p.id)])
	callouts.say(u[0], &"explain", "Patching myself up")
	check(mine.call().size() == 2, "a line of another priority waits beside it")

	callouts.reset()
	for i in 3:
		callouts.say(u[i], &"moving")  # the net is full
	check(callouts.say(u[3], &"status", "Holding. 6 mags", "", "", 0.0, {"to": PackedInt32Array([1])}),
		"an answer to the player who asked goes at once, outside the side's budget")
	check(_said(&"status")[-1].to == PackedInt32Array([1]), "to him alone")
	check(callouts.say(u[4], &"status", "Holding", "", "", 0.0, {"to": PackedInt32Array([2])}) and _said(&"status")[-1].to.is_empty(),
		"one to a player who isn't connected goes to nobody")

	callouts.reset()
	squad.note_fired_on()
	check(not callouts.say(u[0], &"explain", "Going for Test's body"), "an explanation waits while the squad is engaged")
	await _frames(10)
	check(_said(&"explain").is_empty() and callouts.waiting().size() == 1, "and isn't said meanwhile")
	squad.engaged_at = -1000.0
	await _frames(10)
	check(_said(&"explain").size() == 1, "once the squad isn't engaged, it is")
	check(not callouts.say(u[1], &"explain", "Patching myself up"), "the side's next explanation waits %.0f s" % Callouts.INFO_GAP_S)
	await _seconds(Callouts.INFO_GAP_S + 0.3)
	check(_said(&"explain").size() == 2, "then it's said")

	var a := Node3D.new()
	var b := Node3D.new()
	add_child(a)
	add_child(b)
	b.rotation.y = PI
	check(Callouts.resolve_where("Contact, {where}", a, Vector3(0, 0, -50)) == "Contact, front, 50 m"
		and Callouts.resolve_where("Contact, {where}", b, Vector3(0, 0, -50)) == "Contact, back, 50 m",
		"one place, two listeners facing opposite ways: \"front\" for one, \"back\" for the other")
	check(Callouts.resolve_where("Falling behind, {where}", a, null) == "Falling behind", "a line without a place leaves it out")
	a.queue_free()
	b.queue_free()
	callouts.reset()
	var was := u[0].global_position
	_place(u[0], player.global_position + Vector3(0, 0, 60))  # behind the player (he faces -z)
	callouts.say(u[0], &"separated", "Falling behind, {where}", "", "", 0.0, {"me": true})
	var line: Dictionary = _said(&"separated")[-1] if not _said(&"separated").is_empty() else {}
	check(String(line.get("text", "")) == "Falling behind, back, 60 m" and String(line.get("texts", {}).get(1, "")) == String(line.get("text", "")),
		"\"{where}\" is worded from where the player stands (%s)" % line.get("text", "nothing"))
	_place(u[0], was)

	callouts.reset()
	var hs: Array[Soldier] = []
	for k in 3:
		hs.append(_spawn_test_hostile("CommsHostile%d" % k, Vector3(-2 + k * 2, 0.1, -44)))  # 60 m before the player
	await _frames(3)
	for h in hs:
		squad.note_enemy(h, h.global_position)
	var called := callouts.contact(u[0], hs[0])
	var said: String = _said(&"contact")[-1].text if not _said(&"contact").is_empty() else "nothing"
	check(called and said == "Contacts, three, front, 60 m", "three enemies together are one call: %s" % said)
	check(not callouts.contact(u[1], hs[2]), "and a squadmate who spots another of them stays quiet")
	for h in hs:
		_free(h)
	squad.known.clear()
	_freeze(false)
	comms.paused = false


# --- Answers to orders ------------------------------------------------------------------------

func _test_order_answers() -> void:
	print("Answers to orders")
	await _back_in_formation()
	var u := _squad()
	var a: Soldier = u[1]
	var b: Soldier = u[2]
	var names := PackedStringArray([String(a.name), String(b.name)])
	callouts.reset()
	var from := callouts.sent.size()
	var given := Soldier._now()
	_order("hold", player.global_position, names)
	await _seconds(1.5)
	var acks := _since(from, &"ack")
	check(acks.size() == 1 and acks[0].text == "Copy, holding" and String(acks[0].speaker) in names and acks[0].to == PackedInt32Array([1])
		and float(acks[0].time) - given <= 1.5,
		"Hold for %s: one answers for both within 1.5 s, \"Copy, holding\" (%s)" % [names, _lines(from)])

	# The Captain's case: told to stop while carrying a body, he says why he can't.
	var dead := await _friendly_body("CommsBody", b.global_position + Vector3(1.0, 0, 0))
	var bai := SquadAI.of(b)
	bai._end_care()
	bai.casualty = dead
	bai.care = SquadAI.Care.BODY
	bai.intent = SquadAI.Intent.CASUALTY
	var picked := b.server_pick_up_body(dead, Soldier.CARRY, 50.0)
	check(picked, "%s picks up a body (body valid %s, queued %s, up %s, carried by %s; %s carrying %s, hands %s, up %s, %.1f m)" % [b.name,
		is_instance_valid(dead), dead.is_queued_for_deletion() if is_instance_valid(dead) else true, dead.vitals.is_up() if is_instance_valid(dead) else false,
		dead.carried_by if is_instance_valid(dead) else null, b.name, b.carrying, b.inventory.hands, b.vitals.is_up(),
		dead.body_point().distance_to(b.global_position) if is_instance_valid(dead) else -1.0])
	await _seconds(1.0)
	from = callouts.sent.size()
	_order("hold", player.global_position, names)
	await _seconds(1.5)
	var no := _since(from, &"refuse")
	var expected := "Can't, carrying %s's body" % bai._name_of(dead)
	check(no.size() == 1 and no[0].speaker == String(b.name) and no[0].text == expected and no[0].to == PackedInt32Array([1]),
		"%s, carrying it, says why to the player who asked: \"%s\" (%s; %s)" % [b.name, expected, _lines(from), b.ai_status])
	acks = _since(from, &"ack")
	check(acks.size() == 1 and acks[0].speaker == String(a.name) and acks[0].text == "Copy, holding", "and %s answers for himself (%s)" % [a.name, _lines(from)])
	b.release_carried()
	bai._end_care()
	_free(dead)

	# On his way to a casualty: he'll come after.
	var c: Soldier = u[3]
	var d: Soldier = u[4]
	_place(c, d.global_position + Vector3(14, 0, 0))
	d.vitals.server_damage(500.0)
	await _seconds(0.5)
	SquadAI.of(c)._take_casualty(d)
	from = callouts.sent.size()
	_order("hold", player.global_position, PackedStringArray([String(c.name)]))
	await _seconds(1.5)
	var later := _since(from, &"defer") + _since(from, &"refuse")
	check(later.size() == 1 and later[0].id == &"defer" and String(later[0].text).ends_with(" first") and String(later[0].text).contains(SquadAI.of(c)._name_of(d)),
		"%s, going to %s, says he'll come after (%s; %s)" % [c.name, d.name, _lines(from), c.ai_status])
	d.vitals.server_reset_health()
	SquadAI.of(c)._end_care()

	# An order that can't be given, in a squadmate's own words.
	from = callouts.sent.size()
	_order("scavenge", Vector3(30, 0, 30), PackedStringArray([String(a.name)]))
	await _seconds(1.2)
	no = _since(from, &"refuse")
	check(_since(from, &"ack").is_empty() and no.size() == 1 and no[0].text == "No body there",
		"Rearm from that body with no body there: no \"Copy\", \"No body there\" (%s)" % [_lines(from)])

	# Status?
	from = callouts.sent.size()
	var expect_a := SquadAI.of(a).status_text()
	var expect_b := SquadAI.of(b).status_text()
	_order("report", player.global_position, names)
	await _seconds(SquadComms.STATUS_GAP_S + 0.6)
	var st := _since(from, &"status")
	check(st.size() == 2 and st.all(func(l: Dictionary) -> bool: return l.to == PackedInt32Array([1]))
		and String(st[0].text).begins_with(expect_a) and String(st[1].text).begins_with(expect_b) and String(st[0].text).contains("mag"),
		"Report status: each answers the asker alone (%s)" % [st.map(func(l: Dictionary) -> String: return "%s: %s" % [l.speaker, l.text])])
	check(st.size() == 2 and float(st[1].time) - float(st[0].time) >= SquadComms.STATUS_GAP_S - 0.05, "one after the other")
	check(_since(from, &"ack").is_empty(), "and no \"Copy\" for a question")

	# Moved, then in position, once.
	from = callouts.sent.size()
	_order("move", Vector3(5, 0, 9), PackedStringArray([String(a.name)]))
	await _wait_for(func() -> bool: return not _since(from, &"in_position").is_empty(), 25.0)
	acks = _since(from, &"ack")
	check(not acks.is_empty() and acks[0].text == "Moving" and _since(from, &"in_position").size() == 1,
		"Move there: \"Moving\", then \"In position\" once there (%s; %s)" % [_lines(from), a.ai_status])
	await _seconds(2.0)
	check(_since(from, &"in_position").size() == 1, "only once")
	_order("follow", player.global_position, PackedStringArray())


# --- Unprompted -------------------------------------------------------------------------------

func _test_unprompted() -> void:
	print("Unprompted: what the players should know")
	await _back_in_formation()
	var u := _squad()
	callouts.reset()
	var from := callouts.sent.size()
	var p: Soldier = u[1]
	var until := Soldier._now() + 4.0
	while Soldier._now() < until:
		p.suppression = 1.0
		await get_tree().physics_frame
	p.suppression = 0.0
	var pinned := _since(from, &"pinned").filter(func(l: Dictionary) -> bool: return l.speaker == String(p.name))
	check(pinned.size() == 1 and pinned[0].text == "I'm pinned!", "pinned down 4 s: %s calls \"I'm pinned!\" once (%s)" % [p.name, _lines(from)])

	var h: Soldier = u[2]
	var g: Soldier = u[3]
	from = callouts.sent.size()
	h.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	g.vitals.server_impact(Vitals.CHEST, Vitals.INTERMEDIATE, 100.0)
	await _seconds(1.5)
	var hit := _since(from, &"hit")
	var by := func(who: Soldier) -> Array: return hit.filter(func(l: Dictionary) -> bool: return l.speaker == String(who.name))
	check(by.call(h).size() == 1 and String(by.call(h)[0].text) in ["Hit, still good", "I'm hit!"], "a fragment in the arm: %s says he's hit (%s)" % [h.name, _lines(from)])
	check(by.call(g).size() == 1 and by.call(g)[0].text == "Armor took it, I'm good", "a round on the plate: %s says it stopped it" % g.name)
	h.vitals.server_reset_health()
	g.vitals.server_reset_health()

	var m: Soldier = u[4]
	var ammo := Soldier._ammo_of(ItemDB.get_item(m.inventory.slots[&"primary"]))
	var removed := 0
	while SquadComms.spare_mags(m) > SquadComms.LOW_MAGS and m.inventory.remove_one(ammo):
		removed += 1
	from = callouts.sent.size()
	var said_by := func(id: StringName, who: Soldier) -> Array: return _since(from, id).filter(func(l: Dictionary) -> bool: return l.speaker == String(who.name))
	await _wait_for(func() -> bool: return not said_by.call(&"low_ammo", m).is_empty(), SquadComms.SUPPLY_EVERY_S + 2.0)
	check(said_by.call(&"low_ammo", m).size() == 1 and said_by.call(&"low_ammo", m)[0].text == "Low on ammo, %d mags" % SquadComms.LOW_MAGS,
		"down to %d spare magazines: %s says so (%s)" % [SquadComms.LOW_MAGS, m.name, _lines(from)])
	while SquadComms.spare_mags(m) > 0 and m.inventory.remove_one(ammo):
		removed += 1
	await _wait_for(func() -> bool: return not said_by.call(&"last_mag", m).is_empty(), SquadComms.SUPPLY_EVERY_S + 2.0)
	check(said_by.call(&"last_mag", m).size() == 1 and said_by.call(&"last_mag", m)[0].text == "Last mag!", "then \"Last mag!\" (%s)" % [_lines(from)])
	m.inventory.take(ammo, removed)

	_freeze(true)  # what follows sets their state by hand
	_clear_contact()
	callouts.reset()
	var keep := player.global_position
	_place(player, keep + Vector3(0, 0, -150))  # the lead runs 150 m ahead
	var healer := SquadAI.of(u[5])
	healer.intent = SquadAI.Intent.HEAL  # "Patching up": kept by something of his own
	from = callouts.sent.size()
	await _seconds(SquadComms.SEPARATED_S + 1.5)
	var behind := _since(from, &"separated")
	var group := behind.filter(func(l: Dictionary) -> bool: return String(l.text).begins_with("Falling behind, "))
	var own := behind.filter(func(l: Dictionary) -> bool: return l.speaker == String(u[5].name))
	check(group.size() == 1 and String(group[0].text).contains(" of us, back, "), "those just following say it once for all (%s)" % [_lines(from)])
	check(own.size() == 1 and String(own[0].text).begins_with("Falling behind: patching up, back"), "one kept by something says what (%s)" % [own.map(func(l: Dictionary) -> String: return l.text)])
	_place(player, keep)
	healer.intent = SquadAI.Intent.FOLLOW

	var stuck := SquadAI.of(u[1])
	stuck._destination = u[1].global_position + Vector3(30, 0, 0)
	stuck._has_destination = true
	from = callouts.sent.size()
	var anomalies := SessionLog.anomalies
	await _seconds(SquadComms.STUCK_S + SquadComms.THINK_S * 3.0)
	var stuck_lines := _since(from, &"stuck").filter(func(l: Dictionary) -> bool: return l.speaker == String(u[1].name))
	check(stuck_lines.size() == 1 and stuck_lines[0].text == "I'm stuck, can't get to you", "not getting any closer for %.0f s: \"I'm stuck\" (%s)" % [SquadComms.STUCK_S, _lines(from)])
	check(SessionLog.session_id == "" or SessionLog.anomalies > anomalies, "and the session log has it as an anomaly")
	stuck._has_destination = false

	var giver := SquadAI.of(u[2])
	var hurt: Soldier = u[3]
	hurt.vitals.server_damage(500.0)
	await _seconds(0.5)
	giver._take_casualty(hurt)
	await _seconds(SquadComms.THINK_S + 0.2)
	from = callouts.sent.size()
	giver._give_up_casualty()
	await _seconds(SquadComms.THINK_S + 0.3)
	var gave := _since(from, &"give_up")
	check(gave.size() == 1 and gave[0].speaker == String(u[2].name) and gave[0].text == "Can't reach %s, someone else take over!" % giver._name_of(hurt),
		"a responder who can't reach his casualty says so (%s)" % [_lines(from)])
	hurt.vitals.server_reset_health()

	var dead := await _friendly_body("CommsBody2", u[4].global_position + Vector3(6, 0, 0))
	_clear_contact()
	var bearer := SquadAI.of(u[4])
	from = callouts.sent.size()
	bearer.casualty = dead
	bearer.care = SquadAI.Care.BODY
	bearer.intent = SquadAI.Intent.CASUALTY
	await _seconds(SquadComms.THINK_S + 0.5)
	var ex := _since(from, &"explain")
	var said := "Going for %s's body%s" % [bearer._name_of(dead), SquadComms.body_destination_words(bearer)]
	check(ex.size() == 1 and ex[0].speaker == String(u[4].name) and ex[0].text == said,
		"going back for a body unordered, he says so: \"%s\" (%s)" % [said, _lines(from)])
	bearer._end_care()
	bearer.intent = SquadAI.Intent.FOLLOW
	_free(dead)
	_freeze(false)


# --- Firefight --------------------------------------------------------------------------------

func _test_firefight() -> void:
	print("A firefight's chatter stays inside the budget")
	await _back_in_formation()
	callouts.reset()
	var hs: Array[Soldier] = []
	for k in 3:
		# In the open inside the compound, south of the main building: in sight of the squad
		# behind the player (z 16); the far side of the north wall is out of sight (R0856).
		var h := level.spawn_soldier({"name": "CommsShooter%d" % k, "faction": "hostile", "variant": "urban", "pos": Vector3(-9 + k * 9, 0.1, -1),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.2, "discipline": 0.5, "guard": true})
		hs.append(h)
	await _frames(3)
	for h in hs:
		h.vitals.shielded = true  # the fight goes on for the whole window
		squad.note_enemy(h, h.global_position)
	var start := Soldier._now()
	await _seconds(FIREFIGHT_S)
	var window := Soldier._now() - start
	var lines := callouts.sent.filter(func(l: Dictionary) -> bool: return not (l.to as PackedInt32Array).is_empty() and float(l.time) >= start)
	var by_speaker := {}
	for l: Dictionary in lines:
		by_speaker[l.speaker] = int(by_speaker.get(l.speaker, 0)) + 1
	var per_min := lines.size() * 60.0 / window
	var busiest := 0
	for who: String in by_speaker:
		busiest = maxi(busiest, by_speaker[who])
	print("    %d lines in %.0f s (%.0f a minute), by speaker %s, dropped %s" % [lines.size(), window, per_min, by_speaker, callouts.dropped])
	for l: Dictionary in lines:
		print("      %.1f %s [%d]: %s" % [float(l.time) - start, l.speaker, int(l.prio), l.text])
	check(lines.size() >= 5, "the squad talks in the fight (%d lines)" % lines.size())
	check(per_min <= MAX_SIDE_PER_MIN, "at most %.0f lines a minute side-wide (%.0f)" % [MAX_SIDE_PER_MIN, per_min])
	check(busiest * 60.0 / window <= MAX_SPEAKER_PER_MIN, "at most %.0f a minute from one squadmate (%.0f)" % [MAX_SPEAKER_PER_MIN, busiest * 60.0 / window])
	check(not lines.any(func(l: Dictionary) -> bool: return int(l.prio) == Callouts.Prio.INFO), "no explanations while they fight")
	for h in hs:
		_free(h)


# --- Helpers ----------------------------------------------------------------------------------

## Lines with callout `id` said since index `from` of Callouts.sent.
func _since(from: int, id: StringName) -> Array:
	return callouts.sent.slice(mini(from, callouts.sent.size())).filter(func(l: Dictionary) -> bool: return l.id == id)


func _said(id: StringName) -> Array:
	return callouts.sent.filter(func(l: Dictionary) -> bool: return l.id == id)


func _lines(from: int) -> Array:
	return callouts.sent.slice(mini(from, callouts.sent.size())).map(func(l: Dictionary) -> String: return "%s: %s" % [l.speaker, l.text])


func _order(cmd: String, point: Vector3, names: PackedStringArray) -> void:
	player._server_squad_command.rpc_id(1, cmd, point, names)


## Everyone on Follow, out of contact, back in formation behind the player.
func _back_in_formation() -> void:
	_remove_hostiles()
	_clear_contact()
	for s: Soldier in _squad():
		if not s.vitals.is_up() and not s.vitals.is_dead():
			s.vitals.server_reset_health()
	_place(player, Vector3(0, 0.1, 16))
	player.rotation = Vector3.ZERO
	_order("follow", player.global_position, PackedStringArray())
	await _wait_for(func() -> bool: return _squad().all(func(s: Soldier) -> bool: return s.global_position.distance_to(squad.follow_point(s)) < 3.0), 20.0)
	_clear_contact()


## A friendly stand-in killed where it stands: a body (a squadmate killed would stay dead).
func _friendly_body(soldier_name: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": soldier_name, "faction": "friendly", "variant": "urban", "pos": pos,
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	await _frames(3)
	SquadAI.of(s).set_physics_process(false)
	_place(s, pos)
	s.vitals.server_kill()
	await _seconds(1.0)
	return s


## Stops the squad's brains (their own lines and moves) or lets them go again.
func _freeze(on: bool) -> void:
	for s: Soldier in _squad():
		var ai := SquadAI.of(s)
		if on:
			ai._stop()
		ai.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT


func _clear_contact() -> void:
	for s: Soldier in _squad():
		s.threat_time = -1000.0
		s.suppression = 0.0
		var ai := SquadAI.of(s)
		ai._last_contact = -1000.0
		ai._fired_on_at = -1000.0
		ai.target = null
	squad.engaged_at = -1000.0
	squad.known.clear()


func _squad() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in level.ai.get_children():
		if s is Soldier and s.faction == &"friendly" and not s.is_queued_for_deletion() and not s.vitals.is_dead() and SquadAI.of(s) != null:
			out.append(s)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.squad_slot < b.squad_slot)
	return out


func _spawn_test_hostile(soldier_name: String, pos: Vector3) -> Soldier:
	var h := level.spawn_soldier({"name": soldier_name, "faction": "hostile", "variant": "urban", "pos": pos,
		"loadout": [], "combat": 0.3, "discipline": 0.5, "guard": true})
	SquadAI.of(h).set_physics_process(false)  # a stand-in: doesn't move or shoot
	return h


func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _free(node: Variant) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
