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
	_test_allocation()
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
	await _test_commander()
	await _test_defence()
	await _test_armour_infantry()
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


# --- B2: the commander ----------------------------------------------------------------------------

func _b2_row(id: String, kind: String, pos: Vector3, extra := {}) -> Dictionary:
	var r := {"id": id, "kind": kind, "pos": pos, "ce": 1.0, "ce_band": "green", "ammo_band": "green", "strength_cp": 6.0, "at_cp": 0.0,
		"mounted_in": [], "vehicle_kinds": [], "need": "", "availability": 1.0, "up": 8}
	r.merge(extra, true)
	return r


func _test_allocation() -> void:
	print("B2: allocation on staged boards (3.4.3)")
	var obj := Vector3(0, 0, 0)
	var needs := [{"id": "brass", "role": "assault", "pos": obj, "target": obj, "pair": "brass:sbf", "priority": 10.0},
		{"id": "brass:sbf", "role": "sbf", "pos": obj + Vector3(0, 0, 250), "target": obj, "priority": 10.0}]
	var rows := [_b2_row("saber1", "rifle_squad", Vector3(0, 0, 400)), _b2_row("hammer1", "weapons_team", Vector3(50, 0, 400))]
	var got := SideCommand.allocate(needs, rows)
	var by := {}
	for a: Dictionary in got:
		by[String(a.need.id)] = String(a.row.id)
	check(by.get("brass") == "saber1" and by.get("brass:sbf") == "hammer1", "the rifle squad assaults, the weapons team supports by fire")
	check(SideCommand.allocate(needs, [_b2_row("saber1", "rifle_squad", Vector3(0, 0, 400))]).is_empty(), "an Assault is never sent without its SBF")
	var armour := needs.duplicate(true)
	for n: Dictionary in armour:
		n["armour"] = true
	var at_rows := [_b2_row("saber1", "rifle_squad", Vector3(0, 0, 400)), _b2_row("hammer1", "weapons_team", Vector3(50, 0, 400), {"at_cp": 2.0})]
	check(SideCommand.allocate(armour, at_rows).is_empty(), "no group without AT power goes at known armour (the rifle squad has none)")
	var s := SideCommand.score(_b2_row("saber1", "rifle_squad", Vector3(0, 0, 750), {"ce": 0.8, "availability": 0.5}), needs[0])
	check(is_equal_approx(s, 1.0 * 0.8 * 0.5 * 0.5), "score = suitability x CE x (1 - distance / reach) x availability (%.3f)" % s)
	var busy := SideCommand.score(_b2_row("saber1", "rifle_squad", Vector3(0, 0, 0), {"need": "other"}), needs[0])
	check(is_equal_approx(busy, 1.0 - 0.2), "a group tasked elsewhere pays the 0.2 commitment (hysteresis)")
	var mech := _b2_row("iron1", "mech_infantry", Vector3(0, 0, 3000), {"mounted_in": ["v1"]})
	check(SideCommand.score(mech, needs[0]) > 0.0 and SideCommand.score(_b2_row("saber9", "rifle_squad", Vector3(0, 0, 3000)), needs[0]) == 0.0,
		"mounted groups reach 4 km, on foot 1.5 km")
	check(SideCommand.suitability("armour_section", "assault", true) == 0.2 and SideCommand.suitability("armour_section", "assault") == 0.7,
		"tanks assault in the open (0.7), not into a town (0.2)")
	check(SideCommand.score(_b2_row("x", "rifle_squad", obj), {"id": "r", "role": "reserve", "pos": obj, "only": "y"}) == 0.0, "a need for one group takes no other")
	print("B2: off-screen fights by the armour table (3.8)")
	check(is_equal_approx(SideCommand.fight_factor("rifle_squad", "mbt"), 1.0 / 6.0), "rifles against a tank: 1/6 the hits")
	check(is_equal_approx(SideCommand.fight_factor("at_team", "mbt"), 1.0), "an AT team against a tank: full")
	check(is_equal_approx(SideCommand.fight_factor("mbt", "rifle_squad"), 1.0), "a tank against infantry: its soft attack")
	check(is_equal_approx(SideCommand.fight_factor("rifle_squad", "mrap"), 0.5), "rifles against an MRAP: half")
	print("B2: tasking budget")
	var many_rows: Array = []
	var many_needs: Array = []
	for i in 40:
		many_rows.append(_b2_row("g%d" % i, ["rifle_squad", "weapons_team", "mech_infantry", "at_team"][i % 4], Vector3(i * 30.0, 0, 500)))
	for i in 5:  # a company's plan: 5 objectives with their SBF and screens, 5 more tasks (20 needs)
		many_needs.append({"id": "o%d" % i, "role": "assault", "pos": Vector3(i * 100.0, 0, 0), "pair": "o%d:sbf" % i, "priority": 10.0 - i})
		many_needs.append({"id": "o%d:sbf" % i, "role": "sbf", "pos": Vector3(i * 100.0, 0, 250), "priority": 10.0 - i})
		many_needs.append({"id": "s%d" % i, "role": "screen", "pos": Vector3(i * 100.0, 0, -300), "priority": 5.0})
		many_needs.append({"id": "r%d" % i, "role": ["reserve", "recon", "defend", "overwatch", "resupply"][i], "pos": Vector3(i * 80.0, 0, 600), "priority": 4.0})
	var us := INF
	for batch in 5:  # the best of five batches: other runs share this machine
		var t0 := Time.get_ticks_usec()
		for k in 4:
			SideCommand.allocate(many_needs, many_rows)
		us = minf(us, (Time.get_ticks_usec() - t0) / 4.0)
	print("    allocate: %.0f us for 40 groups and 20 needs" % us)
	check(us < 1000.0, "a tasking cycle's allocation is under 1 ms for 40 groups (%.0f us)" % us)


## A commanded group of `n` men at `at` (frozen: the test drives what happens).
func _b2_group(cmd: SideCommand, nm: String, faction: String, at: Vector3, kind: String, loadout: Array = ["m4a1"], n := 4) -> String:
	var sq := Squad.new()
	sq.name = nm
	sq.faction = StringName(faction)
	level.add_child(sq)
	var men: Array[Soldier] = []
	for i in n:
		men.append(_spawn("%s_%d" % [nm, i], faction, at + Vector3(i * 1.5, 0, 0), loadout))
	await _frames(3)
	for s in men:
		_freeze(s)
		SquadAI.of(s).squad = sq
		var w := s.active_weapon()
		if w:
			s.inventory.take(Soldier._ammo_of(w), 8)
	sq.leader = men[0]
	return cmd.server_register(sq, kind, nm.capitalize())


func _test_commander() -> void:
	print("B2: the friendly commander in play")
	var obj := Vector3(-30, 0, -40)
	var spec := {"phases": [{"name": "the farm", "limit_s": 100.0, "axis": [Vector3(0, 0, 40), obj], "main": "farm",
		"objectives": [{"id": "farm", "label": "OBJ BRASS", "pos": obj, "radius": 15.0, "required": true}]}],
		"ld": Vector3(0, 0, 40), "rally": Vector3(20, 0, 45), "hhour_s": 0.0, "flanks": false}
	var plan := OperationPlan.new(spec)
	var cmd := SideCommand.install(level, &"friendly", plan)
	check(SideCommand.of(level, &"friendly") == cmd and RequestBroker.of(level).executor.is_valid(), "the friendly commander is in, and the broker's executor")
	var saber := await _b2_group(cmd, "saber1", "friendly", Vector3(-10, 0.1, 30), "rifle_squad", ["m4a1"], 6)
	var hammer := await _b2_group(cmd, "hammer1", "friendly", Vector3(10, 0.1, 30), "weapons_team", ["m249"], 4)
	var res := await _b2_group(cmd, "saber2", "friendly", Vector3(25, 0.1, 40), "rifle_squad", ["m4a1"], 4)
	SideIntel.of(level).picture.submit({"kind": "inf", "count": 3, "pos": obj}, SideIntel.of(level).now())  # the farm is held
	cmd.advance(0.1)
	check(plan.started and not plan.reserve.is_empty(), "phase 1 begins and a reserve is held (%s)" % ", ".join(PackedStringArray(plan.reserve.keys())))
	var ga: Dictionary = cmd.groups[saber]
	var gs: Dictionary = cmd.groups[hammer]
	if plan.reserve.has(saber) or plan.reserve.has(hammer):
		print("    (the reserve took an assault group: %s)" % ", ".join(PackedStringArray(plan.reserve.keys())))
	check(ga.role == "assault" and (ga.orders as SquadOrders).order.get("verb") == "attack" and (ga.orders as SquadOrders).order.get("go") == "alpha",
		"Saber 1 assaults, held for its support (go alpha)")
	check(gs.role == "sbf" and (gs.orders as SquadOrders).order.get("verb") == "sbf", "Hammer 1 supports by fire")
	check(cmd.lines.any(func(l: Dictionary) -> bool: return String(l.text).contains("ASSAULT on OBJ BRASS: score")), "the decision is a [cmd] line with its score")
	print("B2: the assault waits for its SBF (3.5.1)")
	var so_a := ga.orders as SquadOrders
	var so_s := gs.orders as SquadOrders
	so_a.order.state = "set"
	so_a.order.phase = "set"
	so_s.order.phase = "route"
	cmd.advance(10.0)
	check(String(so_a.order.state) == "set", "set at its attack position, it waits while the SBF isn't firing")
	so_s.order.phase = "execute"
	cmd.advance(1.0)
	check(String(so_a.order.state) != "set" and String(so_a.order.get("go", "")) == "", "the SBF is set: the assault goes")
	check(cmd.net.any(func(l: Dictionary) -> bool: return String(l.text) == "Hammer 1 is set.") and cmd.net.any(func(l: Dictionary) -> bool: return String(l.text) == "Saber 1, go."),
		"\"Hammer 1 is set.\" \"Saber 1, go.\"")
	print("B2: the reserve commits on a stall (3.5.2)")
	cmd.advance(61.0)
	check(not plan.committed.is_empty() and cmd.lines.any(func(l: Dictionary) -> bool: return String(l.text).contains("reserve committed to farm")),
		"past 60% of the phase's limit with the farm still held: the reserve goes in")
	cmd.advance(45.0)
	check(cmd.lines.any(func(l: Dictionary) -> bool: return String(l.text).contains("paused 5 min for fire support")), "at the limit: fire support and a pause")
	print("B2: RED falls back and reconstitutes (3.5.3)")
	var b := SideIntel.of(level).board
	for gid: String in [saber, res]:
		b.rows[gid].ce_band = "red"
		b.rows[gid].pos = Vector3(15, 0, 40)
	var before := cmd.groups.size()
	cmd.server_cycle()
	check(cmd.net.any(func(l: Dictionary) -> bool: return String(l.text).begins_with("Saber 1 is red")), "\"Saber 1 is red, falling back\"")
	check(cmd.groups.size() == before - 1, "two RED rifle squads at the rally merge into one")
	print("B2: the commander and requests (4.2.10)")
	var row_s: Dictionary = b.rows[hammer]
	gs.role = "sbf"
	(gs.orders as SquadOrders).order.state = "active"
	check(cmd.can_spare(row_s, {"kind": "suppress"}).get("delay_s", 0.0) > 0.0, "a group mid-SBF offers to come later")
	check(cmd.can_spare({"id": "nobody"}, {}).is_empty(), "a group it doesn't command: no say")
	cmd.withdrawn = false
	level.remove_child(cmd)
	cmd.free()
	for gid: String in [saber, hammer, res]:
		var sq := level.get_node_or_null(NodePath(gid)) as Squad
		if sq:
			for s: Soldier in sq.members():
				s.queue_free()
			sq.queue_free()
	await _frames(2)


func _test_defence() -> void:
	print("B2: counterattack ratios (3.7)")
	var site_pos := Vector3(-20, 0, -30)
	var plan := DefencePlan.new({"sites": [{"id": "ridge", "label": "the ridge", "pos": site_pos, "radius": 20.0, "line": 0}],
		"rally": Vector3(30, 0, 40)}, 7)
	var cmd := SideCommand.install(level, &"hostile", plan)
	var h1 := await _b2_group(cmd, "banner1", "hostile", Vector3(30, 0.1, 30), "rifle_squad")
	var h2 := await _b2_group(cmd, "banner2", "hostile", Vector3(35, 0.1, 30), "rifle_squad")
	var b := cmd.board()
	for gid: String in [h1, h2]:
		b.rows[gid].strength_cp = 5.0
		b.rows[gid].at_cp = 0.0
	var pic := cmd.picture()
	var t := cmd.now()
	pic.submit({"kind": "inf", "count": 2, "pos": site_pos}, t)
	plan._decide(cmd, plan.site("ridge"), t)
	var op: Dictionary = plan.ops.back()
	check(op.state == "assembling" and (op.groups as Array).size() == 2, "2 seen there (3 CP): 10 CP is enough at 3:1, it assembles")
	var rally: Vector3 = op.rally
	var d := SideCommand._flat(rally, site_pos)
	check(d >= 600.0 - 1.0 and d <= 1200.0 + 1.0, "the rally is 600-1,200 m short (%.0f m)" % d)
	var wait := float(op.go_at) - t
	check(wait >= 300.0 and wait <= 720.0, "it goes 5-12 minutes after the loss (%.0f s)" % wait)
	b.rows[h2].strength_cp = 1.0
	plan.ops.clear()
	plan._decide(cmd, plan.site("ridge"), t)
	check(plan.ops.back().state == "contained", "6 CP against 3 seen: under 3:1, contained (%s)" % plan.ops.back().why)
	b.rows[h2].strength_cp = 100.0
	pic.submit({"kind": "mbt", "count": 1, "pos": site_pos + Vector3(5, 0, 0)}, t)
	plan.ops.clear()
	plan._decide(cmd, plan.site("ridge"), t)
	check(plan.ops.back().state == "contained", "a tank seen there and no AT power: contained however many men (%s)" % plan.ops.back().why)
	b.rows[h1].at_cp = 6.0
	plan.ops.clear()
	plan._decide(cmd, plan.site("ridge"), t)
	check(plan.ops.back().state == "assembling", "with AT power at a quarter of the armour's CP it goes")
	var attack: Dictionary = plan.ops.back()
	attack.state = "attacking"
	b.rows[h1].strength_cp = 1.0
	b.rows[h2].strength_cp = 1.0
	plan._step(cmd, attack, t)
	check(attack.state == "called off", "cut under 1.5:1 while attacking: called off")
	print("B2: a stale picture gets a probe first")
	var stale := SidePicture.new(&"hostile")
	cmd._own_picture = stale
	stale.submit({"kind": "inf", "count": 1, "pos": site_pos, "seen_at": t - 400.0}, t)
	plan.ops.clear()
	plan._decide(cmd, plan.site("ridge"), t)
	check(plan.ops.back().state == "probing", "nothing fresh there: a probe")
	print("B2: virtual groups are tasked through their route")
	var sq := Squad.new()
	sq.name = "banner_v"
	sq.faction = &"hostile"
	level.add_child(sq)
	var rec := {"squad": sq, "soldiers": [], "virtual": {"members": [{"name": "v1"}], "pos": Vector3(40, 0, 40), "side": "hostile"}}
	var vid := cmd.server_register(sq, "rifle_squad", "Banner V")
	cmd.groups[vid].record = rec  # (a staged profile: not handed to the Virtualizer)
	cmd._issue({"id": "hold:x", "role": "defend", "pos": site_pos}, {"id": vid, "pos": Vector3(40, 0, 40), "kind": "rifle_squad"}, 1.0)
	check(sq.patrol.size() == 1 and sq.patrol[0].is_equal_approx(site_pos), "a virtual group walks its profile's route to its task")
	check(rec.get("vf_kind") == "rifle_squad", "and fights off-screen by the armour table as what it is")
	print("B2: a hot zone keeps EnemyCommand's rules")
	var hz := HotZonePolicy.new()
	check(hz.needs(cmd, t).is_empty() and is_equal_approx(hz.task_s(), 30.0), "HotZonePolicy tasks nothing itself; hot zones keep 30 s")
	level.remove_child(cmd)
	cmd.free()


# --- B3: armour with infantry ---------------------------------------------------------------------

func _test_armour_infantry() -> void:
	print("B3: pairing and who leads by ground (3.6)")
	var rows := [_b2_row("anvil1", "armour_section", Vector3(0, 0, 0)), _b2_row("saber1", "rifle_squad", Vector3(30, 0, 0)),
		_b2_row("saber2", "rifle_squad", Vector3(400, 0, 0)), _b2_row("anvil2", "armour_section", Vector3(390, 0, 0))]
	var pairs := ArmourInfantry.pair(rows)
	check(pairs.get("anvil1") == "saber1" and pairs.get("anvil2") == "saber2", "each tank section is paired with the nearest infantry group")
	var dir := Vector3(0, 0, -1)
	var inf := Vector3(0, 0, 0)
	var obj := Vector3(0, 0, -1500)
	var woods := ArmourInfantry.escort_spot("woods", inf, obj, dir)
	check(is_equal_approx(SideCommand._flat(woods, inf), 150.0) and woods.z > inf.z, "woods: the armour follows 150 m behind its infantry")
	var town := ArmourInfantry.escort_spot("town", inf, obj, dir)
	check(is_equal_approx(SideCommand._flat(town, inf), 75.0) and town.z > inf.z, "a town: 75 m behind")
	var open := ArmourInfantry.escort_spot("open", inf, obj, dir)
	check(is_equal_approx(SideCommand._flat(open, obj), 1000.0), "open ground: overwatch 1 km off the objective (it leads)")
	print("B3: armour stops at a town's edge")
	var stub := Node3D.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar mods := []\nfunc modules() -> Array:\n\treturn mods\n"
	gs.reload()
	stub.set_script(gs)
	add_child(stub)
	var village := ZoneModule.new()
	village.type = "village"
	village.position = Vector3(0, 0, -300)
	stub.add_child(village)
	stub.set(&"mods", [village])
	var half: Vector2 = ZoneModules.HALF.get("village", Vector2(20, 20))
	var inside := Vector3(0, 0, -300)
	var from := Vector3(0, 0, -100)
	var held := ArmourInfantry.town_edge(stub, inside, from, Vector3(0, 0, -120))
	check(held.z > -300.0 + half.y and held.z <= -300.0 + half.y + 20.0, "its screen still outside: held at the edge (%.0f m from the centre)" % absf(held.z + 300.0))
	var going := ArmourInfantry.town_edge(stub, inside, from, Vector3(0, 0, -290))
	check(going.is_equal_approx(inside), "its screen in the town: it follows in")
	check(ArmourInfantry.ground(stub, Vector3(0, 0, -300)) == "town" and ArmourInfantry.ground(stub, Vector3(0, 0, 500)) == "open", "the ground: town inside the village, open away from it")
	stub.queue_free()
	print("B3: a paired tank stays with its screen; a hand-off; armour asks for infantry")
	var spec := {"phases": [{"name": "the ridge", "limit_s": 900.0, "axis": [Vector3(0, 0, 40), Vector3(0, 0, -40)], "main": "ridge",
		"objectives": [{"id": "ridge", "label": "OBJ IRON", "pos": Vector3(0, 0, -40), "radius": 10.0}]}], "ld": Vector3(0, 0, 40),
		"rally": Vector3(30, 0, 45), "hhour_s": 0.0, "flanks": false}
	var cmd := SideCommand.install(level, &"friendly", OperationPlan.new(spec))
	var saber := await _b2_group(cmd, "saber3", "friendly", Vector3(-5, 0.1, 20), "rifle_squad", ["m4a1"], 4)
	var hammer := await _b2_group(cmd, "hammer3", "friendly", Vector3(10, 0.1, 25), "weapons_team", ["m249"], 3)
	var anvil := await _b2_group(cmd, "anvil3", "friendly", Vector3(-20, 0.1, 35), "armour_section", ["m4a1"], 2)
	var b := SideIntel.of(level).board
	b.rows[anvil].at_cp = 12.0
	cmd.advance(1.0)
	check(cmd.pairs.has(anvil), "the armour section is paired (%s)" % cmd.pairs.get(anvil, "none"))
	var screen := String(cmd.pairs.get(anvil, ""))
	var ga: Dictionary = cmd.groups[anvil]
	check(String(ga.role) == "overwatch" and String(ga.need) == "escort:" + anvil, "its task is escorting its screen")
	var spot: Array = ((ga.orders as SquadOrders).order.get("points", [[0, 0]]) as Array)[0]
	var sp: Vector3 = b.rows[screen].pos
	var d := Vector2(float(spot[0]) - sp.x, float(spot[1]) - sp.z).length()
	check(d <= 160.0, "and it's sent to within 150 m of the screen (%.0f m; open ground clamps to the map)" % d)
	b.rows[screen].pos = sp + Vector3(0, 0, -20)
	b.rows[screen].ce_band = "amber"
	var sg: Dictionary = cmd.groups[screen]
	(sg.orders as SquadOrders)._target = Vector3(0, 0, -40)
	sg.role = "assault"
	SideIntel.of(level).picture.submit({"kind": "mg", "count": 1, "pos": Vector3(2, 0, -42)}, SideIntel.of(level).now())
	cmd.server_cycle()
	check(String(ga.need).begins_with("handoff:") and (ga.orders as SquadOrders).order.get("verb") == "sbf", "the infantry, held by an MG on its objective, hands it to its armour: an SBF on it")
	check(cmd.net.any(func(l: Dictionary) -> bool: return String(l.text).contains("MG at ") and String(l.text).ends_with("my tracer.")), "\"... MG at <grid>, <n> metres, my tracer.\"")
	b.rows[screen].ce_band = "green"
	SideIntel.of(level).picture.submit({"kind": "at", "count": 2, "pos": b.rows[anvil].pos + Vector3(60, 0, 0)}, SideIntel.of(level).now())
	cmd.server_cycle()
	check(String(sg.need).begins_with("clear_at:"), "an AT team near the armour: its screen goes after it")
	check(cmd.net.any(func(l: Dictionary) -> bool: return String(l.text).contains("AT team at ") and String(l.text).contains("need it cleared")), "\"AT team at <grid>, need it cleared before we move.\"")
	level.remove_child(cmd)
	cmd.free()
	for gid: String in [saber, hammer, anvil]:
		var sq := level.get_node_or_null(NodePath(gid)) as Squad
		if sq:
			for s: Soldier in sq.members():
				s.queue_free()
			sq.queue_free()
	await _frames(2)
