extends Node
## Headless checks for the AI commander's side picture (docs/combined_arms.md 3.2, 3.3, 4.4; phase
## B1): SidePicture merging, ageing, latency by side, comms down x3, Blue Force Tracker, fairness
## (every entry and every marker a player sees traces to a report) and its budget; GroupBoard's
## scales and sitreps; SideIntel's feeds from the groups, players' tags and reports, radios and
## relays; the hostile picture under EnemyCommand; spot markers and world diamonds.
##   <voxel godot exe> --headless --path . res://tests/side_command_test.tscn
## Exits with the number of failures. B2 adds the commander's own checks here.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_side_command" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("SIDE_COMMAND TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_latency()
	_test_merging()
	_test_ageing()
	_test_bft_pure()
	_test_fairness_pure()
	_test_budget()
	_test_board_scales()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	await _frames(5)
	await _test_level_feed()
	await _test_radio()
	await _test_bft_level()
	await _test_board_level()
	_test_hostile_picture()
	await _test_diamonds()
	GameState.delete_save()
	print("SIDE_COMMAND TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Pure ----------------------------------------------------------------------------------------

func _test_latency() -> void:
	print("Latency by side")
	check(SidePicture.profile_of(&"us_forces") == "regular" and SidePicture.profile_of(&"friendly") == "regular", "the company and US forces are regulars")
	check(SidePicture.profile_of(&"eastern_concord") == "concord", "Eastern Concord has its own band")
	check(SidePicture.profile_of(&"kestrel") == "irregular" and SidePicture.profile_of(&"black_ridge") == "irregular", "cartels and Black Ridge are irregular")
	check(SidePicture.profile_of(&"ashen_banner") == "insurgent" and SidePicture.profile_of(&"hostile") == "insurgent", "insurgents as Alert")
	var bands := {"regular": [8.0, 3.0], "concord": [20.0, 8.0], "irregular": [45.0, 15.0], "insurgent": [60.0, 15.0]}
	for p: String in bands:
		var slow := SidePicture.delay_s(p, 0.0)
		var fast := SidePicture.delay_s(p, 1.0)
		check(is_equal_approx(slow, bands[p][0]) and is_equal_approx(fast, bands[p][1]), "%s: %.0f s unskilled, %.0f s skilled" % [p, slow, fast])
	check(is_equal_approx(SidePicture.delay_s("insurgent", 1.0, true), 22.5), "an insurgent under fire takes x1.5 (Alert's rule)")
	check(is_equal_approx(SidePicture.delay_s("regular", 1.0, true), 3.0), "regulars don't slow under fire")
	print("Comms down x3")
	for p: String in ["regular", "concord", "insurgent"]:
		check(is_equal_approx(SidePicture.delay_s(p, 0.5, false, true), SidePicture.delay_s(p, 0.5) * 3.0), "%s: comms down triples the delay" % p)
	var pic := SidePicture.new(&"friendly")
	pic.comms_down = true
	check(is_equal_approx(pic.delay_for(1.0), 9.0), "a side with its net down reports in 9 s, not 3")
	print("A report arrives after its delay")
	pic = SidePicture.new(&"friendly")
	pic.submit({"kind": "inf", "count": 3, "pos": Vector3(100, 0, 100)}, 0.0, pic.delay_for(0.0))
	pic.step(7.9)
	check(pic.entries.is_empty() and pic.pending.size() == 1, "not in the picture before 8 s (an unskilled leader)")
	pic.step(8.0)
	check(pic.entries.size() == 1 and pic.pending.is_empty(), "in the picture at 8 s")
	var alive := [true]
	pic.submit({"kind": "inf", "pos": Vector3(500, 0, 500)}, 10.0, 5.0, func() -> bool: return alive[0])
	alive[0] = false
	pic.step(20.0)
	check(pic.entries.size() == 1, "a report whose sender went down first never gets out")


func _test_merging() -> void:
	print("Merging")
	var pic := SidePicture.new(&"friendly")
	pic.submit({"kind": "inf", "count": 2, "pos": Vector3(0, 0, 0), "seen_at": 0.0, "unc0": 20.0, "by": "Saber 1"}, 0.0)
	pic.submit({"kind": "inf", "count": 4, "pos": Vector3(10, 0, 5), "seen_at": 5.0, "unc0": 5.0, "by": "Saber 2"}, 5.0)
	check(pic.entries.size() == 1, "infantry 11 m apart within 60 s merge")
	var e: Dictionary = pic.entries[0]
	check(int(e.count) == 4, "count takes the higher")
	check((e.pos as Vector3).is_equal_approx(Vector3(10, 0, 5)) and e.by == "Saber 2", "position the fresher")
	check(is_equal_approx(pic.uncertainty(e, 5.0), 5.0), "uncertainty the smaller (5 m, not 27.5)")
	pic.submit({"kind": "inf", "count": 1, "pos": Vector3(0, 0, 0), "seen_at": 1.0}, 6.0)
	check((pic.entries[0].pos as Vector3).is_equal_approx(Vector3(10, 0, 5)), "a later report of an older sighting doesn't move it back")
	pic.submit({"kind": "inf", "pos": Vector3(40, 0, 0)}, 7.0)
	check(pic.entries.size() == 2, "infantry 30 m off is another entry")
	pic.submit({"kind": "mg", "pos": Vector3(10, 0, 5)}, 8.0)
	check(pic.entries.size() == 3, "another kind is another entry")
	pic.submit({"kind": "mbt", "pos": Vector3(500, 0, 0)}, 9.0)
	pic.submit({"kind": "mbt", "pos": Vector3(550, 0, 0)}, 10.0)
	check(pic.entries.size() == 4, "vehicles 50 m apart merge (60 m)")
	pic.submit({"kind": "mbt", "pos": Vector3(620, 0, 0)}, 11.0)
	check(pic.entries.size() == 5, "vehicles 70 m off don't")
	pic.submit({"kind": "inf", "pos": Vector3(12, 0, 5), "seen_at": 80.0}, 80.0)
	check(pic.entries.size() == 6, "an entry not seen for over 60 s isn't merged into")
	pic.submit({"kind": "inf", "pos": Vector3(64.5, 0, 0)}, 81.0)
	pic.submit({"kind": "inf", "pos": Vector3(63.5, 0, 0)}, 81.0)
	check(pic.entries.size() == 7, "merging works across a hash cell's edge")


func _test_ageing() -> void:
	print("Ageing")
	var pic := SidePicture.new(&"friendly")
	pic.submit({"kind": "inf", "pos": Vector3.ZERO, "seen_at": 0.0, "unc0": 5.0}, 0.0)
	pic.submit({"kind": "ifv", "pos": Vector3(1000, 0, 0), "seen_at": 0.0, "unc0": 5.0}, 0.0)
	var inf: Dictionary = pic.entries[0]
	var ifv: Dictionary = pic.entries[1]
	check(is_equal_approx(pic.uncertainty(inf, 100.0), 155.0), "infantry: 1.5 m/s (155 m at 100 s)")
	check(is_equal_approx(pic.uncertainty(ifv, 100.0), 505.0), "vehicles: 5 m/s (505 m at 100 s)")
	check(is_equal_approx(pic.uncertainty(ifv, 1000.0), 600.0), "capped at 600 m")
	check(pic.band(inf, 29.0) == "fresh" and pic.band(inf, 31.0) == "aged" and pic.band(inf, 179.0) == "aged" and pic.band(inf, 181.0) == "stale",
		"fresh under 30 s, aged under 3 min, stale after")
	pic.step(599.0)
	check(pic.entries.size() == 2, "both kept at 599 s")
	pic.step(601.0)
	check(pic.entries.size() == 1 and pic.entries[0].kind == "ifv", "infantry dropped 10 min after its last report")
	pic.step(899.0)
	check(pic.entries.size() == 1, "the vehicle kept at 899 s")
	pic.step(901.0)
	check(pic.entries.is_empty(), "vehicles dropped after 15 min")


func _test_bft_pure() -> void:
	print("Blue Force Tracker (pure)")
	var pic := SidePicture.new(&"friendly")
	pic.bft_vehicle("v:1", Vector3(10, 0, 10), "M-ATV", true, 0.0)
	pic.bft_vehicle("v:1", Vector3(20, 0, 10), "M-ATV", true, 1.0)
	check((pic.bft["v:1"].pos as Vector3).is_equal_approx(Vector3(20, 0, 10)) and not pic.bft["v:1"].grey, "a vehicle with a radio is tracked where it is")
	pic.bft_vehicle("v:1", Vector3(90, 0, 10), "M-ATV", false, 2.0)
	check((pic.bft["v:1"].pos as Vector3).is_equal_approx(Vector3(20, 0, 10)) and pic.bft["v:1"].grey, "radio out: grey where it was last tracked")
	pic.bft_keep({})
	check(pic.bft.is_empty(), "gone vehicles leave the tracker")


func _test_fairness_pure() -> void:
	print("Fairness (pure): every entry traces to its reports")
	var pic := SidePicture.new(&"friendly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2210
	var t := 0.0
	for i in 400:
		t += rng.randf_range(0.0, 4.0)
		var kind: String = ["inf", "mg", "at", "ifv", "mbt"][rng.randi_range(0, 4)]
		pic.submit({"kind": kind, "count": rng.randi_range(1, 6), "pos": Vector3(rng.randf_range(0, 600), 0, rng.randf_range(0, 600)),
			"seen_at": t - rng.randf_range(0.0, 20.0)}, t, rng.randf_range(0.0, 10.0))
		pic.step(t)
	check(not pic.entries.is_empty(), "the picture has %d entries after 400 reports" % pic.entries.size())
	check(pic.entries.all(func(e: Dictionary) -> bool: return pic.traces(e)), "every entry's reports are in the log, at its freshest report's position")


func _test_budget() -> void:
	print("Budget")
	# A full picture (64 entries) taking 5 reports a step: 40 groups (3.8's tasking load) each
	# reporting a fresh cluster every 30 s is 1.3 a second, so this is a heavy fight's burst.
	var avg := _bench(5)
	var heavy := _bench(20)
	print("    step: %.0f us average at 5 reports a step, %.0f us at 20" % [avg, heavy])
	check(avg < 300.0, "the picture's step is under 0.3 ms per side (%.0f us: 64 entries, 5 reports due a step)" % avg)


## Average step cost (us) over 50 steps of a full picture with `per_step` reports due each.
func _bench(per_step: int) -> float:
	var pic := SidePicture.new(&"friendly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 64:
		pic.submit({"kind": "inf", "pos": Vector3(i * 40.0, 0, 0)}, 0.0)
	var total := 0
	for run in 50:
		var t := 1.0 + run
		for k in per_step:
			pic.submit({"kind": ["inf", "mg"][k % 2], "count": 2, "pos": Vector3(rng.randf_range(0, 2560), 0, rng.randf_range(-30, 30))}, t - 0.5, 0.5)
		pic.step(t)
		total += pic.step_usec
	return total / 50.0


func _test_board_scales() -> void:
	print("GroupBoard scales")
	check(is_equal_approx(GroupBoard.man_cp({"skill": 1.0, "armour": true}), 1.5), "an armoured man at full skill is EnemyCommand's 1.5 CP")
	check(is_equal_approx(GroupBoard.man_cp({"skill": 0.6, "armour": false}), 0.6), "an unarmoured man at 0.6 skill is 0.6")
	check(GroupBoard.vehicle_cp("soft_vehicle") == 4.0 and GroupBoard.vehicle_cp("light_armour") == 4.0 and GroupBoard.vehicle_cp("ifv") == 8.0
		and GroupBoard.vehicle_cp("mbt") == 16.0, "a technical or MRAP 4, an IFV 8, an MBT 16")
	check(GroupBoard.man_at_cp("default") == 1.0 and GroupBoard.man_at_cp("guided") == 3.0 and GroupBoard.man_at_cp("") == 0.0, "AT: an AT4 or RPG 1, a guided launcher 3")
	check(GroupBoard.vehicle_at_cp("ifv", true) == 4.0 and GroupBoard.vehicle_at_cp("ifv", false) == 0.0 and GroupBoard.vehicle_at_cp("mbt", false) == 6.0,
		"AT: an IFV with an ATGM 4, an MBT 6")
	check(is_equal_approx(GroupBoard.infantry_ce(8, 8, 1.0, 1.0, 0), 1.0) and GroupBoard.ce_band(1.0) == "green", "a whole, stocked, steady squad is GREEN")
	var ce := GroupBoard.infantry_ce(4, 8, 0.5, 0.5, 1)
	check(is_equal_approx(ce, 0.4) and GroupBoard.ce_band(ce) == "red", "half up, half ammo, shaken, one urgent: 0.4, RED")
	check(GroupBoard.ce_band(0.5) == "amber", "0.5 is AMBER")
	check(is_equal_approx(GroupBoard.vehicle_ce(1.0, 0.0, 1.0, 1.0), 0.8), "a vehicle that can't move loses its mobility share")
	check(GroupBoard.vehicle_kind("abrams") == "mbt" and GroupBoard.vehicle_kind("bradley") == "ifv" and GroupBoard.vehicle_kind("matv") == "light_armour"
		and GroupBoard.vehicle_kind("technical_dshk") == "soft_vehicle" and GroupBoard.vehicle_kind("mortar_2b14") == "mortar", "vehicle kinds from their class")


# --- In a level ----------------------------------------------------------------------------------

func _spawn(nm: String, faction: String, pos: Vector3, loadout: Array = ["m4a1"], combat := 0.6) -> Soldier:
	var s := level.spawn_soldier({"name": nm, "faction": faction, "variant": "urban", "pos": pos, "loadout": loadout, "combat": combat,
		"discipline": 0.6, "guard": true})
	return s


## Stops `s` thinking and moving: the test drives what he knows.
func _freeze(s: Soldier) -> void:
	s.set_physics_process(false)
	var brain := SquadAI.of(s)
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED


func _test_level_feed() -> void:
	print("SideIntel: a group's sighting reaches the picture and the map")
	var intel := SideIntel.of(level)
	check(intel != null and SideIntel.picture_of(level, &"friendly") == intel.picture, "every level has the friendly side's picture")
	var f1 := _spawn("SideF1", "friendly", Vector3(-6, 0.1, 6))
	var h1 := _spawn("SideH1", "hostile", Vector3(6, 0.1, -12), ["m249"])
	var h2 := _spawn("SideH2", "hostile", Vector3(-12, 0.1, -14))
	await _frames(3)
	for s in [f1, h1, h2]:
		_freeze(s)
	var company := level.squad_for(&"friendly")
	company.known.clear()
	intel.server_feed()
	check(intel.picture.entries.is_empty(), "nothing seen, nothing in the picture")
	company.note_enemy(h1, h1.global_position)
	intel.server_feed()
	check(intel.picture.entries.is_empty() and intel.picture.pending.size() == 1, "a fresh sighting goes on the radio, not straight into the picture")
	var due := float(intel.picture.pending[0].due) - intel.now()
	check(due >= 3.0 - 0.01 and due <= 8.0 + 0.01, "regulars: 3-8 s by the leader's skill (%.1f s)" % due)
	intel.advance(due + 0.1)
	check(intel.picture.entries.size() == 1, "it reaches the picture after the delay")
	var e: Dictionary = intel.picture.entries[0] if not intel.picture.entries.is_empty() else {}
	check(not e.is_empty() and e.kind == "mg" and int(e.count) == 1, "reported as one MG (what he carries)")
	intel.advance(5.0)
	check(intel.picture.entries.size() == 1 and intel.picture.pending.is_empty(), "the same cluster isn't reported again within 30 s")
	var markers := MapNodes.markers(level)
	var spots := markers.list("intel").filter(func(m: Dictionary) -> bool: return m.kind == "spot")
	check(spots.size() == 1, "one spot marker on the map's intel channel")
	print("Fairness: every marker a player sees traces to a report")
	_check_markers_trace(intel)
	var reported_at := h1.global_position
	h1.global_position += Vector3(8, 0, 0)  # he moves; nobody sees it
	company.known.clear()
	intel.advance(40.0)
	var spot: Dictionary = markers.list("intel").filter(func(m: Dictionary) -> bool: return m.kind == "spot")[0]
	check((spot.points[0] as Vector2).is_equal_approx(Vector2(reported_at.x, reported_at.z)), "the marker stays where he was reported, not where he is")
	check(not markers.list("intel").any(func(m: Dictionary) -> bool:
		return m.kind == "spot" and (m.points[0] as Vector2).distance_to(Vector2(h2.global_position.x, h2.global_position.z)) < 5.0),
		"an enemy nobody reported has no marker")
	var player_move := markers.markers.size()
	markers._server_remove(int(spot.id))
	check(markers.markers.size() == player_move, "players can't delete a spot report")
	print("Players feed it: a tag, a report")
	var tags := EnemyTags.of(level)
	if not EnemyTags.has_radio(player):
		player.inventory.take(&"radio", 1)
	player.global_position = Vector3(0, 0.1, 0)
	tags._last_tag.clear()
	var before := intel.picture.received.size()
	intel.server_report_tag(player, h2)
	intel.advance(3.1)
	check(intel.picture.received.size() == before + 1 and String(intel.picture.received.back().source) == "tag", "a tag is a report (3 s on the player's radio)")
	var tagged := intel.picture.entries.filter(func(x: Dictionary) -> bool: return bool(x.tag))
	check(tagged.size() == 1 and (tagged[0].tag_names as Array).has(String(h2.name)), "its entry is a tag (red), naming the man tagged")
	intel.server_report_position(player, Vector3(30, 0, 30), [h1, h2])
	intel.advance(3.1)
	check(intel.picture.received.back().source == "report" and int(intel.picture.received.back().count) == 2, "\"Report enemy position\" is a report of what was there")
	_check_markers_trace(intel)


func _check_markers_trace(intel: SideIntel) -> void:
	var markers := MapNodes.markers(level)
	var ok := true
	var n := 0
	for m: Dictionary in markers.list():
		if m.kind != "spot":
			continue
		n += 1
		var e := intel.picture.entry(int(m.spot.entry))
		var ids: Array = m.spot.reports
		if e.is_empty() or ids.is_empty() or not intel.picture.traces(e):
			ok = false
		for id: int in ids:
			var r := intel.picture.report(id)
			if r.is_empty():
				ok = false
		var freshest := intel.picture.report(int(ids.back())) if not ids.is_empty() else {}
		if freshest.is_empty() or (m.points[0] as Vector2).distance_to(Vector2(e.pos.x, e.pos.z)) > 0.01:
			ok = false
	check(n > 0 and ok, "all %d spot markers trace to an entry and its reports in the log" % n)


func _test_radio() -> void:
	print("Radios: a sender down, no radio, a relay")
	var intel := SideIntel.of(level)
	var sq := Squad.new()
	sq.name = "TestSaber"
	sq.faction = &"friendly"
	level.add_child(sq)
	var a := _spawn("SaberA", "friendly", Vector3(-15, 0.1, 15))
	var b := _spawn("SaberB", "friendly", Vector3(-14, 0.1, 15))
	var foe := _spawn("SaberFoe", "hostile", Vector3(15, 0.1, -15))
	await _frames(3)
	for s in [a, b, foe]:
		_freeze(s)
		if SquadAI.of(s) and s.faction == &"friendly":
			SquadAI.of(s).squad = sq
	sq.leader = a
	check(intel.radio_man(sq) == a, "a regular group's leader carries its issued set")
	sq.note_enemy(foe, foe.global_position)
	var pending := intel.picture.pending.size()
	intel._report_clusters(sq, intel.now())
	check(intel.picture.pending.size() == pending + 1, "the group's sighting is on its way")
	a.vitals.server_damage(500.0)
	await _frames(2)
	var entries := intel.picture.received.size()
	intel.advance(10.0)
	check(intel.picture.received.size() == entries, "its radio man went down before it got out: the report died with him")
	check(intel.radio_man(sq) == b, "the next man up takes the radio")
	a.vitals.server_reset_health()
	sq.set_meta(&"no_radio", true)
	intel._sent.erase(GroupBoard.group_id(sq))
	sq.note_enemy(foe, foe.global_position + Vector3(1, 0, 0))
	pending = intel.picture.pending.size()
	intel._report_clusters(sq, intel.now())
	check(intel.picture.pending.size() == pending and (intel._held.get(GroupBoard.group_id(sq), []) as Array).size() == 1, "no radio: the report is held")
	var squads: Array[Squad] = [sq]
	for s in [a, b]:
		s.global_position += Vector3(-300, 0, 300)  # far from everyone with a radio
	player.global_position = Vector3(0, 0.1, 0)
	intel._relay_held(squads, intel.now())
	check(intel._held.has(GroupBoard.group_id(sq)), "held while nobody with a radio is within shouting distance")
	player.global_position = b.global_position + Vector3(40, 0, 0)  # the player (with a radio) within 80 m
	intel._relay_held(squads, intel.now())
	check(not intel._held.has(GroupBoard.group_id(sq)) and intel.picture.pending.back().report.get("relayed_by", "") != "",
		"a player with a radio within 80 m passes it on")
	player.global_position = Vector3(0, 0.1, 0)
	for s in [a, b, foe]:
		s.queue_free()
	sq.queue_free()
	await _frames(2)


func _test_bft_level() -> void:
	print("Blue Force Tracker")
	var intel := SideIntel.of(level)
	var layer := VehicleLayer.of(level)
	var v := layer.server_spawn("matv", Transform3D(Basis.IDENTITY, Vector3(12, 0.5, 12)), "", &"player") if layer else null
	await _frames(3)
	check(v != null, "an M-ATV of ours")
	if v == null:
		return
	v.freeze = true
	intel.server_feed()
	var key := "v:" + v.vehicle_id
	check(intel.picture.bft.has(key) and (intel.picture.bft[key].pos as Vector3).distance_to(v.global_position) < 0.01 and not intel.picture.bft[key].grey,
		"our vehicle with a working radio is in the picture where it is")
	v.set_meta(&"radio_down", true)
	var was: Vector3 = intel.picture.bft[key].pos
	v.global_position += Vector3(5, 0, 0)
	intel.server_feed()
	check(intel.picture.bft[key].grey and (intel.picture.bft[key].pos as Vector3).is_equal_approx(was), "its radio out: grey where it was last tracked")
	var company_key := "g:" + GroupBoard.group_id(level.squad_for(&"friendly"))
	check(intel.picture.bft.has(company_key), "our groups are tracked by their sitreps")
	v.queue_free()
	await _frames(2)
	intel.server_feed()
	check(not intel.picture.bft.has(key), "a vehicle gone leaves the tracker")


func _test_board_level() -> void:
	print("GroupBoard in play")
	var intel := SideIntel.of(level)
	var company_id := GroupBoard.group_id(level.squad_for(&"friendly"))
	var row: Dictionary = intel.board.rows.get(company_id, {})
	check(not row.is_empty() and row.kind == "company" and not row.taskable, "the company is on the board, not the commander's to task")
	check(not row.is_empty() and float(row.strength_cp) > 0.0 and row.ce_band in ["green", "amber", "red"], "with its CP (%.1f) and CE band (%s)" % [float(row.get("strength_cp", 0.0)), row.get("ce_band", "")])
	var at: Vector3 = row.get("pos", Vector3.ZERO)
	var f1 := level.ai.get_node_or_null(^"SideF1") as Soldier
	if f1:
		f1.global_position += Vector3(4, 0, 0)
	intel.advance(5.0)
	check((intel.board.rows[company_id].pos as Vector3).is_equal_approx(at), "between sitreps the board keeps the last reported position")
	intel.advance(30.0)
	check(f1 == null or (intel.board.rows[company_id].pos as Vector3).is_equal_approx(f1.global_position), "the next sitrep (30 s) brings it up to date")


func _test_hostile_picture() -> void:
	print("The hostile picture under EnemyCommand")
	var command := EnemyCommand.new()
	level.add_child(command)
	check(SideIntel.picture_of(level, &"hostile") == command.picture and command.picture.profile == "insurgent", "the hostile side's picture is EnemyCommand's")
	var at := Vector3(200, 0, 200)
	command._on_reported({"kind": &"contact", "pos": at, "seen": 2, "exo": 0, "by": "Banner 3"})
	check(command.picture.entries.size() == 1 and int(command.picture.entries[0].count) == 2, "Alert's contact report is an entry (Alert already held it for the delay)")
	check(is_equal_approx(command.threat_cp(at, EnemyCommand.SITE_THREAT_M), 2.0 * EnemyCommand.SQUAD_MAN_CP), "threat_cp reads the same CP from the picture's log")
	command._on_reported({"kind": &"shot", "pos": at + Vector3(20, 0, 0)})
	check(command.picture.entries.size() == 1 and command.picture.received.back().noise, "a shot heard is in the log, never an entry")
	command._contacts.clear()
	check(command.threat_cp(at, EnemyCommand.SITE_THREAT_M) == 0.0, "clearing _contacts (the tests' hook) still clears what threat_cp reads")
	level.remove_child(command)
	command.free()


func _test_diamonds() -> void:
	print("Spot reports in the world")
	var hud := player._hud
	var diamonds := hud.get_node_or_null(^"SpotDiamonds") as SpotDiamonds if hud else null
	check(diamonds != null, "the HUD has the spot diamonds")
	if diamonds == null:
		return
	var cam := get_viewport().get_camera_3d()
	var markers := MapNodes.markers(level)
	var spots := markers.list("intel").filter(func(m: Dictionary) -> bool: return m.kind == "spot")
	diamonds.own_sight.clear()
	var shown := diamonds.shown(cam) if cam else []
	check(cam == null or shown.size() <= spots.size(), "no more diamonds than spot reports")
	for d: Dictionary in shown:
		check(spots.any(func(m: Dictionary) -> bool: return int(m.id) == int(d.id)), "diamond %d traces to a spot marker" % int(d.id))
	if not shown.is_empty():
		diamonds.own_sight[int(shown[0].id)] = true
		check(not diamonds.shown(cam).any(func(d: Dictionary) -> bool: return int(d.id) == int(shown[0].id)), "one the player sees himself gets none")
		diamonds.own_sight.clear()
	GameSettings.get_value("hud", "spot_diamonds")
	if not GameSettings._values.has("hud"):
		GameSettings._values["hud"] = {}
	var had: Variant = (GameSettings._values["hud"] as Dictionary).get("spot_diamonds")
	GameSettings._values["hud"]["spot_diamonds"] = false  # (not saved)
	check(diamonds.shown(cam).is_empty(), "the setting's off switch hides them all")
	if had == null:
		(GameSettings._values["hud"] as Dictionary).erase("spot_diamonds")
	else:
		GameSettings._values["hud"]["spot_diamonds"] = had
	await _frames(2)
