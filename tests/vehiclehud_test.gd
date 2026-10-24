extends Node
## Headless checks for combined arms A5 (cg_brief queue item 2.4; docs/combined_arms.md 2.6, 2.11,
## 2.12, 9.3): the armoured vehicles' HUDs and the x-ray, in the real compound. HitReport from a
## HitEvent and its JSON round trip; the HUD per seat (the Abrams' driver, gunner, commander and
## loader, a Bradley rider, an M-ATV; a technical keeps the strip); the crew pips, the damage word
## and the alerts following the modules, the kill states and the crew; the Blue Force Tracker's
## chevrons and a radio going down; the x-ray drawing a real hit's path from its HitEvent (the card
## by the setting, the full view, the protection analysis against ArmourModel.resolve); muffled
## hearing buttoned up against turned out; the vision blocks, the driver's periscopes and night
## channel, the loader's view; the sight overlay with the crew pips at the ui_test's 10
## resolutions; the cost against its budget; then a second process joins over ENet and finds the
## damage, the crew and a dead radio as the host has them (late join), and the next hit's report.
##   <voxel godot exe> --headless --path . res://tests/vehiclehud_test.tscn
## The host starts the client itself ("-- --vehiclehud-join"). Exits with the number of failures.

## The air rigs: vehicles frozen this high (nothing in the way).
const RIG_Y := 150.0
## 9.3: "HUD under 0.3 ms" (VehicleHud.BUDGET_MS); locally under load, this much slack.
const LOCAL_SLACK := 2.0

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _n := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_vehiclehud" + tag  # never touch a real save
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_vehiclehud_settings%s.cfg" % tag))  # never the player's
	GameSettings.reset_all()
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--vehiclehud-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(460.0).timeout.connect(func() -> void:
		print("VEHICLEHUD TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_pure()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	layer = VehicleLayer.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 0)
	VehicleCamera.chase = false
	for model: String in ["abrams", "bradley", "matv"]:
		VehicleHull.prewarm(model)
	if _want("seats"):
		await _test_seats()
	if _want("states"):
		await _test_states()
	if _want("bft"):
		await _test_bft()
	if _want("xray"):
		await _test_xray()
	if _want("muffle"):
		await _test_muffle()
	if _want("vision"):
		await _test_vision()
	if _want("overlay"):
		await _test_overlay()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	GameState.delete_save()
	GameSettings.reset_all()
	GameSettings.use_file("")
	print("VEHICLEHUD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_VEHICLEHUD_ONLY="seats,xray" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_VEHICLEHUD_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Pure -------------------------------------------------------------------------------------------

func _test_pure() -> void:
	print("HitReport, the selector and crew lines (pure)")
	var spec := VehicleSpecs.spec("abrams")
	var mods := VehicleModules.layout_of("abrams", spec)
	var health := PackedFloat32Array()
	health.resize(mods.size())
	health.fill(1.0)
	var idx := func(id: String) -> int:
		for m: Dictionary in mods:
			if String(m.id) == id:
				return int(m.i)
		return -1
	var tr: int = idx.call("transmission")
	var en: int = idx.call("engine")
	health[tr] = 0.0
	health[en] = 0.4
	var ev := {"o": "pen", "p": [0.0, 1.0, 4.95], "pl": "hull_rear", "sh": "m829a3", "t": 30, "pen": 780, "s": 7, "m": [tr * 4 + 2, en * 4 + 1], "c": [3],
		"d": [0.0, 0.0, -1.0], "th": 0, "r": 1000, "by": "1", "x": [[tr, 0.15, 0.85], [en, 0.85, 2.15]], "sp": [[0.1, 0.0, -0.99, 1.2]], "k": VehicleModules.MOBILITY}
	var r := HitReport.build("abrams", spec, mods, health, ev, {3: "wounded"}, {3: "loader"})
	check(String(r.outcome) == "pen" and String(r.plate_name) == "Hull rear" and int(r.figure_mm) == 30 and String(r.column) == "ke"
		and (r.path as Array).size() == 2 and String(r.path[0].id) == "transmission" and String(r.path[0].state) == "destroyed" and String(r.path[1].state) == "damaged",
		"a report from a HitEvent: the plate (%s, %d mm KE), the path in order with each module's state after (%s)" % [r.plate_name, int(r.figure_mm), r.path])
	var line := HitReport.line(r)
	check(line.begins_with("PEN: ") and line.contains("transmission destroyed") and line.contains("engine damaged") and line.contains("loader wounded") and line.contains("[mobility]"),
		"the card's line: '%s'" % line)
	var text := HitReport.panel_text(r)
	check(text.begins_with("Hull rear, 30 mm KE at 0 degrees: 30 mm effective.") and text.contains("M829A3 at 1000 m: 780 mm. PENETRATION."),
		"the full view's text (2.11's shape): '%s'" % text.split("\n")[0] + " / " + text.split("\n")[1])
	var back := HitReport.from_json(HitReport.to_json(r))
	check(HitReport.line(back) == line and HitReport.panel_text(back) == text and (back.path as Array).size() == 2 and (back.spall as Array).size() == 1,
		"a HitReport's JSON round trip gives the same report")
	var bounce := HitReport.build("abrams", spec, mods, health, {"o": "ricochet", "pl": "turret_side_fwd_r", "sh": "m791", "th": 81, "m": [], "c": []})
	check(HitReport.line(bounce) == "RICOCHET: Turret side (front, right), 81 degrees", "a ricochet's line: '%s'" % HitReport.line(bounce))
	var sel := {"rounds": [{"name": "SABOT", "n": 14, "loaded": true, "next": false}, {"name": "HEAT", "n": 9, "loaded": false, "next": true},
		{"name": "HE", "n": 8, "loaded": false, "next": false}], "reload": [0.6, 3.1]}
	check(VehicleHud.selector_text(sel) == "[SABOT 14]  HEAT 9  HE 8   next HEAT   loading [======----] 3.1 s",
		"the round selector: '%s'" % VehicleHud.selector_text(sel))
	var crew := [{"letter": "D", "name": "Okafor", "state": "up", "you": false}, {"letter": "C", "name": "", "state": "up", "you": true},
		{"letter": "L", "name": "Hale", "state": "wounded", "you": false}, {"letter": "R", "n": 4, "of": 6, "state": "up"}]
	check(VehicleHud.crew_text(crew) == "CREW  D Okafor *  C you *  L Hale + wounded  R 4/6", "the crew line: '%s'" % VehicleHud.crew_text(crew))
	check(VehicleSightOverlay.bracketed("SABOT 14   HEAT 9   HE 8", "HEAT") == "SABOT 14   [HEAT 9]   HE 8", "the sight brackets the loaded round")


# --- Per seat ---------------------------------------------------------------------------------------

func _hud() -> Hud:
	return player.player_input.hud


## Puts the player in `seat` of `v` with `crew` (AI) in `others`, everyone else out.
func _seat(v: Vehicle, seat: int, crew: Array, others: Array) -> void:
	for s: Soldier in v.occupants():
		v.server_exit(s)
	await _physics(2)
	v.server_enter(player, seat)
	for i in others.size():
		v.server_enter(crew[i], int(others[i]))
	await _seconds(VehicleHud.GATHER_S * 3.0)


func _test_seats() -> void:
	print("The HUD in each seat (2.12)")
	var v := await _spawn("abrams", Vector3(-200, RIG_Y, -300), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(3, v)
	var hud := _hud()
	var want := {0: ["Driver", "D", ["hatch", "view", "last hit"], ["lase"], "vision"], 1: ["Gunner", "G", ["sight", "lase", "view"], ["hatch", "designate"], "first"],
		2: ["Commander", "C", ["sight", "lase", "designate", "hatch"], [], "vision"], 3: ["Loader", "L", ["hatch", "view"], ["lase"], "vision"]}
	for seat: int in [0, 1, 2, 3]:
		await _seat(v, seat, crew, [0, 1, 2, 3].filter(func(i: int) -> bool: return i != seat))
		var vh := VehicleHud.of(player)
		var w: Array = want[seat]
		var view: Dictionary = vh.view if vh else {}
		var keys: Array = (view.get("keys", []) as Array).map(func(k: Array) -> String: return String(k[1]))
		var pips: Array = view.get("crew", [])
		var you: Array = pips.filter(func(c: Dictionary) -> bool: return bool(c.get("you", false)))
		check(vh != null and vh.panel.visible and not hud._vehicle.visible and String(view.get("title", "")).ends_with(String(w[0]))
			and pips.map(func(c: Dictionary) -> String: return String(c.letter)) == ["D", "G", "C", "L"] and you.size() == 1 and String(you[0].letter) == String(w[1])
			and (w[2] as Array).all(func(k: String) -> bool: return k in keys) and not (w[3] as Array).any(func(k: String) -> bool: return k in keys)
			and vh.mode == String(w[4]) and String(view.get("damage", "")) == "none",
			"%s: the panel in the strip's place, crew pips D G C L with you at %s, keys %s, view %s" % [w[0], w[1], keys, vh.mode if vh else "-"])
		if seat == 1:
			var sel: Dictionary = view.get("selector", {})
			check(not (sel.get("rounds", []) as Array).is_empty() and VehicleHud.selector_text(sel).contains("[SABOT") and vh._title.text.contains("DMG none")
				and vh._weapon.text.contains("M256") and vh._drive.text.contains("FUEL") and vh._crew.text.begins_with("CREW"),
				"the gunner's panel: the selector '%s', the gun, the drive and crew lines" % VehicleHud.selector_text(sel))
			var marks: Array = hud.compass.vehicle_marks
			check(marks.any(func(m: Array) -> bool: return String(m[1]) == "hull") and marks.any(func(m: Array) -> bool: return String(m[1]) == "turret"),
				"the compass carries the hull's caret and the turret's bracket (%s)" % [marks])
			var sight := VehicleSight.open_for(player, v.gunnery, 1)
			await _frames(3)
			check(vh.mode == "sight" and not vh.panel.visible and sight.overlay._bottom_right.text.contains("CREW D* G* C* L*   DMG none")
				and sight.overlay._bottom_left.text.contains("[SABOT"),
				"through the GPS: the panel gives way to the sight, which carries the crew pips and the damage word ('%s')" % sight.overlay._bottom_right.text.replace("\n", " | "))
			sight.close()
			VehicleCamera.chase = true
			await _seconds(VehicleHud.GATHER_S * 2.0)
			check(vh.mode == "chase" and vh.panel.visible, "the chase view: the third-person HUD")
			VehicleCamera.chase = false
		if seat == 3:
			var sel3: Dictionary = view.get("selector", {})
			check(bool(sel3.get("loader", false)) and (sel3.get("rounds", []) as Array).size() == 3, "the loader's selector: the M256's three rounds")
	for s: Soldier in v.occupants():
		v.server_exit(s)
	# A Bradley rider; an M-ATV; a technical (the strip).
	var ifv := await _spawn("bradley", Vector3(-230, RIG_Y, -300), 0.0)
	var rider := -1
	for i in (ifv.spec.seats as Array).size():
		if ifv.seat_kind(i) == Vehicle.PASSENGER and rider < 0:
			rider = i
	await _seat(ifv, rider, crew, [0, 1])
	var vh2 := VehicleHud.of(player)
	check(vh2 != null and vh2.panel.visible and vh2._crew.text.contains("R 1/") and not (vh2.view.get("crew", []) as Array).any(func(c: Dictionary) -> bool: return bool(c.you)),
		"a Bradley rider: the crew line counts the riders ('%s')" % (vh2._crew.text if vh2 else ""))
	for s: Soldier in ifv.occupants():
		ifv.server_exit(s)
	var mrap := await _spawn("matv", Vector3(-260, RIG_Y, -300), 0.0)
	await _seat(mrap, 0, crew, [])
	check(VehicleHud.of(player) != null and VehicleHud.of(player).panel.visible and not hud._vehicle.visible, "an M-ATV (its modules) has the panel too")
	mrap.server_exit(player)
	var tech := await _spawn("technical_dshk", Vector3(-290, RIG_Y, -300), 0.0)
	await _seat(tech, 0, crew, [])
	await _seconds(VehicleHud.SHOW_S + 0.2)
	check(not VehicleHud.applies(tech) and hud.vehicle_text() != "" and not VehicleHud.of(player).panel.visible,
		"a technical (zones, no modules) keeps the text strip ('%s')" % hud.vehicle_text())
	tech.server_exit(player)
	await _physics(2)
	player.global_position = Vector3(0, 0.1, 0)
	for x: Vehicle in [v, ifv, mrap, tech]:
		x.queue_free()
	for s: Soldier in crew:
		s.queue_free()
	await _physics(2)


# --- Following the modules, the kill states and the crew -------------------------------------------

func _test_states() -> void:
	print("Crew pips, the damage word and the alerts follow the modules and the crew")
	var v := await _spawn("abrams", Vector3(-320, RIG_Y, -300), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(3, v)
	await _seat(v, 2, crew, [0, 1, 3])
	var g := func() -> Dictionary: return VehicleHud.gather(v, player, 2)
	var pip := func(view: Dictionary, letter: String) -> String:
		for c: Dictionary in view.crew:
			if String(c.letter) == letter:
				return String(c.state)
		return ""
	var a: Dictionary = g.call()
	check(String(a.damage) == "none" and (a.alerts as PackedStringArray).is_empty(), "whole: DMG none, no alerts (%s)" % [a.alerts])
	v.modules.server_set("engine", 0.3)
	a = g.call()
	check(String(a.damage) == "damaged" and String(a.drive).contains("ENGINE damaged"), "the engine damaged: DMG damaged, ENGINE damaged ('%s')" % a.drive)
	v.modules.server_set("track_l", 0.0)
	a = g.call()
	check(String(a.damage) == "mobility" and "TRACK THROWN" in (a.alerts as PackedStringArray), "a track thrown: DMG mobility, TRACK THROWN (%s, %s)" % [a.damage, a.alerts])
	v.server_exit(crew[1])
	(crew[2] as Soldier).vitals.downed = true
	await _physics(2)
	a = g.call()
	check(pip.call(a, "G") == "empty" and pip.call(a, "L") == "down" and "SHORT-CREWED" in (a.alerts as PackedStringArray),
		"the gunner gone, the loader down: their pips empty and down, SHORT-CREWED (%s)" % [a.crew])
	v.modules.server_set("radio", 0.0)
	a = g.call()
	check("NO RADIO" in (a.alerts as PackedStringArray) and bool(v.get_meta(&"radio_down", false)), "the radio destroyed: NO RADIO")
	await _seconds(VehicleHud.GATHER_S * 2.0)
	var vh := VehicleHud.of(player)
	check(vh != null and vh._alerts.visible and vh._alerts.text.contains("NO RADIO") and vh._title.text.contains("DMG mobility"),
		"the panel shows them ('%s' / '%s')" % [vh._alerts.text if vh else "", vh._title.text if vh else ""])
	(crew[2] as Soldier).vitals.downed = false
	v.modules.server_reset()
	v.server_enter(crew[1], 1)
	await _physics(2)
	a = g.call()
	check(String(a.damage) == "none" and (a.alerts as PackedStringArray).is_empty() and pip.call(a, "G") == "up", "repaired and crewed: back to none")
	await _clear(v, crew)


# --- Blue Force Tracker chevrons --------------------------------------------------------------------

func _test_bft() -> void:
	print("Blue Force Tracker chevrons in the sight (B5.6, 4.5)")
	var v := await _spawn("abrams", Vector3(-400, RIG_Y, -300), 0.0)
	var friend := await _spawn("bradley", Vector3(-400, RIG_Y, -600), 0.0)
	var foe := await _spawn("bradley", Vector3(-385, RIG_Y, -600), 0.0, &"hostile")
	var crew := await _men(1, v)
	await _seat(v, 1, crew, [0])
	var sight := VehicleSight.open_for(player, v.gunnery, 1)
	await _frames(3)
	var size := get_viewport().get_visible_rect().size
	var ids := func() -> Array: return VehicleHud.bft_marks(v, player, sight, size).map(func(m: Array) -> String: return String(m[2]))
	var seen: Array = ids.call()
	check(friend.vehicle_id in seen and not foe.vehicle_id in seen and not v.vehicle_id in seen,
		"a chevron over the friendly Bradley 300 m out, none over the enemy's or our own (%s)" % [seen])
	friend.modules.server_set("radio", 0.0)
	var dark: Array = ids.call()
	friend.modules.server_reset()
	var back: Array = ids.call()
	check(not friend.vehicle_id in dark and friend.vehicle_id in back, "its radio destroyed (radio_down), it drops off the tracker; repaired, it's back")
	sight.close()
	await _clear(v, crew)
	friend.queue_free()
	foe.queue_free()
	await _physics(2)


# --- The x-ray ----------------------------------------------------------------------------------

func _test_xray() -> void:
	print("The x-ray: a real hit's path from its HitEvent (2.11, F-239)")
	var v := await _spawn("abrams", Vector3(-480, RIG_Y, -300), 0.0)
	var crew := await _men(4, v)
	for i in 4:
		v.server_enter(crew[i], i)
	await _physics(2)
	var x := VehicleXray.of(player)
	GameSettings.set_value("hud", VehicleXray.SETTING, "mine_and_me")
	var before := x.reports.size()
	var out := _hit(v, "m829a3", Vector3(0.0, 1.0, 5.4), Vector3(0, 0, -1), player)
	await _frames(2)
	var ev: Dictionary = v.modules.events.back() if not v.modules.events.is_empty() else {}
	var r: Dictionary = x.reports.back() if x.reports.size() > before else {}
	var arm: Dictionary = out.get("armour", {})
	var path_ids: Array = (ev.get("x", []) as Array).map(func(e: Array) -> String: return String(v.modules.mods[int(e[0])].id))
	check(not r.is_empty() and String(r.outcome) == String(arm.get("outcome", "?")) and int(r.t_eff) == roundi(float(arm.get("t_eff", -1.0)))
		and int(r.pen) == roundi(float(arm.get("pen", -1.0))) and int(r.angle) == roundi(float(arm.get("theta_deg", -1.0))) and String(r.plate) == String(arm.get("plate", "?")),
		"the report reads the host's own HitResult: %s on %s, %d mm effective, %d mm pen, %d deg" % [r.get("outcome", "-"), r.get("plate", "-"), int(r.get("t_eff", 0)), int(r.get("pen", 0)), int(r.get("angle", 0))])
	check(not path_ids.is_empty() and (r.get("path", []) as Array).map(func(e: Dictionary) -> String: return String(e.id)) == path_ids and "transmission" in path_ids,
		"its path is the event's trace, in order (%s)" % [path_ids])
	check(HitReport.line(HitReport.of_event(v, ev)) == HitReport.line(r) and x.card.visible and x._card_line.text == HitReport.line(r) and x._card_title.text.begins_with("YOUR HIT"),
		"my shot: the card for 6 s ('%s')" % x._card_line.text)
	check(x.open_latest() and x.is_open() and x.shown == r and x._root3d.get_child_count() >= 20 and x._text.text.contains("Hull rear"),
		"the full view: the model, the shot and the text (%d parts drawn)" % x._root3d.get_child_count())
	x.close()
	check(not x.is_open(), "Esc or the key closes it")
	# The setting.
	var card_for := func(which: String, shooter: Node) -> bool:
		GameSettings.set_value("hud", VehicleXray.SETTING, which)
		x._card_left = 0.0
		await _frames(1)
		_hit(v, "m791", Vector3(2.3, 0.8, 1.0), Vector3(-1, 0, 0), shooter)
		await _frames(2)
		return x.card.visible
	var off: bool = await card_for.call("off", player)
	var mine_other: bool = await card_for.call("mine", null)
	var all_other: bool = await card_for.call("all", null)
	for s: Soldier in v.occupants():
		if s == crew[2]:
			v.server_exit(s)
	v.server_enter(player, 2)
	await _physics(2)
	var me_mine: bool = await card_for.call("mine", null)
	var me_both: bool = await card_for.call("mine_and_me", null)
	check(not off and not mine_other and all_other and not me_mine and me_both and x._card_title.text.begins_with("HIT ON YOU"),
		"the setting: off none; my shots only mine; every hit any; my shots and hits on me: a hit on my tank")
	check(x.reports.size() == mini(before + 6, VehicleXray.KEEP), "every hit kept for the pause menu's list (%d)" % x.reports.size())
	# Protection analysis against ArmourModel.resolve.
	var spec := VehicleSpecs.spec("abrams")
	var local := Vector3(2.05, 0.9, 1.0)
	var ldir := Vector3(-1, 0, 0)
	var p := VehicleXray.predict("abrams", "m791", 1000.0, local, ldir)
	var direct := ArmourModel.resolve(Shells.shell("m791"), ArmourModel.plate_at(spec, local, ldir),
		{"dir": ldir, "range_m": 1000.0, "check_arming": true, "seed": VehicleXray.ANALYSIS_SEED, "tiles": ArmourModel.tiles_at(spec, local, [], {})})
	check(not p.is_empty() and p.outcome == direct.outcome and is_equal_approx(float(p.t_eff), float(direct.t_eff)) and is_equal_approx(float(p.pen), float(direct.pen)),
		"protection analysis matches resolve: %s" % VehicleXray.analysis_text(p))
	var a := deg_to_rad(82.0)
	var glance := VehicleXray.predict("abrams", "m829a3", 1000.0, local, Vector3(-cos(a), 0, -sin(a)))
	check(float(glance.get("ricochet_chance", 0.0)) > 0.0 and float(glance.get("ricochet_chance", 0.0)) <= 1.0,
		"at 82 degrees it gives a ricochet chance (%d%%)" % roundi(float(glance.get("ricochet_chance", 0.0)) * 100.0))
	x.open_analysis("abrams")
	await _frames(2)
	var clicked := x.analyse_at(Vector2(x._vp.size) * 0.5)
	check(x.is_open() and x._analysis_box.visible and not clicked.is_empty() and x._result.text.contains(" m on "),
		"the analysis view: a click on the model gives the outcome there ('%s')" % x._result.text)
	x.close()
	GameSettings.set_value("hud", VehicleXray.SETTING, "mine_and_me")
	await _clear(v, crew)


## Shell `id` into `v` at `local` (its frame) along `ldir`, by `shooter`, the tiles missed.
func _hit(v: Vehicle, id: String, local: Vector3, ldir: Vector3, shooter: Node) -> Dictionary:
	return v.server_take_hit({"position": v.global_transform * local, "direction": (v.global_basis * ldir).normalized(), "shooter": shooter, "probe_m": 1.5,
		"force": {"coverage": false, "ricochet": false}, "kind": Vehicle.KINETIC, "shell": id})


# --- Hearing ------------------------------------------------------------------------------------

func _test_muffle() -> void:
	print("Hearing: muffled buttoned up (2.6)")
	var v := await _spawn("abrams", Vector3(-560, RIG_Y, -300), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(1, v)
	await _seat(v, 2, crew, [0])
	var inside := Sfx.muffle_active()
	v.hatches.server_set(2, true, true)
	await _frames(3)
	var out := Sfx.muffle_active()
	v.hatches.server_set(2, false, true)
	await _frames(3)
	var again := Sfx.muffle_active()
	v.server_exit(player)
	await _seconds(VehicleHud.SHOW_S + 0.3)
	check(inside and not out and again and not Sfx.muffle_active(), "buttoned up -12 dB and low-passed; turned out, clear; out of the vehicle, clear")
	var mrap := await _spawn("matv", Vector3(-590, RIG_Y, -300), 0.0)
	var gun := mrap.gun_seats()[0]
	var cab := -1
	for i in (mrap.spec.seats as Array).size():
		if cab < 0 and i != gun and i != 0 and not mrap.seat_open(i):
			cab = i
	await _seat(mrap, gun, crew, [])
	var open_gun := Sfx.muffle_active()
	await _seat(mrap, cab, crew, [])
	check(not open_gun and Sfx.muffle_active(), "the M-ATV's open gunner's hatch: clear; its closed cab: muffled")
	mrap.server_exit(player)
	await _seconds(VehicleHud.SHOW_S + 0.3)
	mrap.queue_free()
	await _clear(v, crew)


# --- Vision blocks, periscopes, the night channel, the loader --------------------------------------

func _test_vision() -> void:
	print("Vision blocks, the driver's periscopes and night channel, the loader's view")
	var v := await _spawn("abrams", Vector3(-640, RIG_Y, -300), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(1, v)
	await _seat(v, 0, crew, [1])
	var vv := VehicleVision.of(player)
	var vh := VehicleHud.of(player)
	check(vv != null and vv.up and vv.current and vv.blocks().size() == 3 and is_equal_approx(vv.fov, player.camera.fov) and vh.mode == "vision",
		"the driver buttoned up: three periscopes over his 100 degrees, at 1x (%d)" % (vv.blocks().size() if vv else 0))
	player.rotation.y += deg_to_rad(40.0)
	await _frames(3)
	var fwd := v.global_basis.inverse() * -vv.global_basis.z
	var yaw := rad_to_deg(atan2(-fwd.x, -fwd.z))
	check(vv.block == 2 and absf(yaw - float(vv.blocks()[2][0])) < 1.0, "looking 40 degrees left: the left periscope (%.0f deg)" % yaw)
	var told := vv.cycle_channel()
	await _frames(3)
	check(told.contains("night") and vv.mode() == "night" and vh._night.visible and is_equal_approx(vh.panel.modulate.a, VehicleHud.NIGHT_DIM),
		"the night channel: the intensifier over the glass, the rest of the HUD dimmed ('%s')" % told)
	v.modules.server_set("driver_vision", 0.4)
	await _frames(2)
	var lost := vv.cycle_channel()
	var day := vv.mode()
	v.modules.server_set("driver_vision", 0.0)
	await _frames(2)
	check(lost.contains("lost") and day == "day" and vv.mode() == "out" and not vh._night.visible,
		"the periscope damaged: day only ('%s'); destroyed: out, turn out to drive" % lost)
	v.modules.server_reset()
	v.hatches.server_set(0, true, true)
	await _frames(3)
	check(not vv.up and player.camera.current, "turned out: his own eye again")
	v.hatches.server_set(0, false, true)
	VehicleCamera.chase = true
	await _frames(3)
	check(not vv.up, "the chase view is never cut")
	VehicleCamera.chase = false
	await _seat(v, 2, crew, [0])
	check(VehicleVision.up_for(player) and VehicleVision.of(player).blocks().size() == 6, "the commander: six blocks round the cupola")
	await _seat(v, 3, crew, [0])
	var sel: Dictionary = VehicleHud.of(player).view.get("selector", {})
	check(VehicleVision.up_for(player) and VehicleVision.of(player).blocks().size() == 1 and bool(sel.get("loader", false)) and sel.has("doors"),
		"the loader turned in: his periscope, the bustle doors and the round selector")
	v.server_exit(player)
	await _seconds(VehicleHud.SHOW_S + 0.3)
	check(not VehicleVision.up_for(player) and player.camera.current, "out of the tank: his own view")
	await _clear(v, crew)


# --- The sight overlay at the ui_test's resolutions ---------------------------------------------------

func _test_overlay() -> void:
	print("The sight overlay with the crew pips at the ui_test's 10 resolutions")
	var sizes: Array = (load("res://tests/ui_test.gd") as GDScript).get_script_constant_map().get("SIZES", [])
	var host := Control.new()
	add_child(host)
	var o := VehicleSightOverlay.new()
	host.add_child(o)
	var info := {"name": "GPS", "stab": "DEGRADED", "lrf_state": "MULTIPLE RETURNS", "ret": "last", "lase": {"ok": true, "r": 1874.0},
		"sol": {"on": true, "bs": false, "trk": 1.2}, "lead_mil": 2.1, "loaded": "SABOT", "next": "HEAT", "rounds": "SABOT 14   HEAT 9   HE 8",
		"fuze": "AIRBURST 1874 m", "turret_deg": 12, "hull_deg": 346, "commander": true, "gun_rel_deg": -35.0,
		"crew_line": "CREW D* G+ Cx L-   DMG knocked out"}
	var bad: Array = []
	for res: Vector2i in sizes:
		for ui_scale: float in [1.0, 1.5, 2.0]:
			var logical := Vector2(res) / GameSettings.ui_scale_for(res, ui_scale)
			host.size = logical
			o.set_text(info, "thermal", ThermalView.BLACK_HOT, 25.0)
			await get_tree().process_frame
			var screen := Rect2(Vector2.ZERO, logical)
			var rects: Array = []
			for l: Label in [o._top_left, o._top_mid, o._top_right, o._bottom_left, o._bottom_right, o._prompt]:
				var r := Rect2(l.position, l.get_combined_minimum_size())
				if not screen.encloses(r):
					bad.append("%s@%.1f: %s off %s" % [res, ui_scale, l.text.split("\n")[0], logical])
				rects.append(r)
			for i in rects.size():
				for j in range(i + 1, rects.size()):
					if (rects[i] as Rect2).grow(-1.0).intersects(rects[j]):
						bad.append("%s@%.1f: overlap %d/%d" % [res, ui_scale, i, j])
	check(sizes.size() == 10 and bad.is_empty() and o._bottom_right.text.contains("DMG knocked out") and o._bottom_left.text.contains("[SABOT 14]"),
		"every readout on screen and apart at %d resolutions and 3 UI scales, the crew line in (%s)" % [sizes.size(), bad])
	host.queue_free()


# --- The cost -----------------------------------------------------------------------------------

func _test_budget() -> void:
	print("The HUD's cost (9.3: under 0.3 ms)")
	var v := await _spawn("abrams", Vector3(-720, RIG_Y, -300), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(3, v)
	var worst := 0.0
	for p: Array in [[2, false], [1, false], [1, true]]:
		VehicleCamera.chase = bool(p[1])
		await _seat(v, int(p[0]), crew, [0, 1, 2, 3].filter(func(i: int) -> bool: return i != int(p[0])).slice(0, 3))
		var vh := VehicleHud.of(player)
		vh.cost_avg_ms = 0.0
		vh._cost_n = 0
		for i in 90:
			await get_tree().process_frame
		worst = maxf(worst, vh.cost_avg_ms)
	VehicleCamera.chase = false
	var k := 1.0 if OS.get_environment("GITHUB_ACTIONS") != "" else LOCAL_SLACK
	check(worst <= VehicleHud.BUDGET_MS * k, "the HUD costs %.3f ms a frame at worst (commander, gunner, chase; Proposed budget %.2f)" % [worst, VehicleHud.BUDGET_MS * k])
	await _clear(v, crew)


# --- A client joins ------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	var v := await _spawn("abrams", Vector3(-800, RIG_Y, -300), 0.0)
	var ifv := await _spawn("bradley", Vector3(-830, RIG_Y, -300), 0.0)
	var crew := await _men(4, v)
	for i in 4:
		v.server_enter(crew[i], i)
	await _physics(2)
	v.modules.server_set("engine", 0.3)
	v.modules.server_set("track_r", 0.0)
	(crew[3] as Soldier).vitals.downed = true
	ifv.modules.server_set("radio", 0.0)
	await _seconds(0.5)
	var pips: Array = VehicleHud.crew_pips(v).map(func(c: Dictionary) -> String: return String(c.state))
	expect = {"mbt": v.vehicle_id, "ifv": ifv.vehicle_id, "dmg": VehicleHud.damage_word(v), "pips": pips, "drive": VehicleHud.drive_line(v).get_slice("FUEL", 0)}
	var log_path := OS.get_user_data_dir().path_join("vehiclehud_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/vehiclehud_test.tscn", "--", "--vehiclehud-join"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_ready or _client_failures >= 0, 200.0)
	if _client_ready:
		var out := _hit(v, "m829a3", Vector3(0.0, 1.0, 5.4), Vector3(0, 0, -1), null)
		await _frames(2)
		var r := HitReport.of_event(v, v.modules.events.back())
		_expect.rpc(expect.merged({"hit": {"outcome": String(r.outcome), "plate": String(r.plate), "t_eff": int(r.t_eff), "modules": r.modules,
			"shown": not out.is_empty()}}))
	await _until(func() -> bool: return _client_failures >= 0, 120.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())
	(crew[3] as Soldier).vitals.downed = false
	await _clear(v, crew)
	ifv.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_hit() -> void:
	_client_ready = true


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(190.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 120.0)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.mbt)) != null and find.call(String(expect.ifv)) != null, 30.0)
		var v: Vehicle = find.call(String(expect.mbt))
		var ifv: Vehicle = find.call(String(expect.ifv))
		await _until(func() -> bool: return v != null and v.occupant(3) != null and VehicleHud.damage_word(v) == String(expect.dmg), 20.0)
		await _seconds(1.0)
		var pips: Array = VehicleHud.crew_pips(v).map(func(c: Dictionary) -> String: return String(c.state)) if v else []
		note.call(v != null and VehicleHud.damage_word(v) == String(expect.dmg), "the damage word as the host has it (%s)" % (VehicleHud.damage_word(v) if v else "-"))
		note.call(pips == (expect.pips as Array), "the crew pips as the host has them (%s / %s)" % [pips, expect.pips])
		note.call(v != null and VehicleHud.drive_line(v).get_slice("FUEL", 0) == String(expect.drive) and VehicleHud.drive_line(v).contains("ENGINE damaged"),
			"the drive line ('%s')" % (VehicleHud.drive_line(v) if v else ""))
		note.call(ifv != null and bool(ifv.get_meta(&"radio_down", false)) and not SideIntel.radio_ok(ifv) and "NO RADIO" in VehicleHud.alerts(ifv, 0),
			"the Bradley's dead radio: off the tracker, NO RADIO, here too (late join)")
		# The next hit, live: its HitEvent reaches this peer and its report is the host's.
		var seen := v.modules.events_seen if v else 0
		_ready_for_hit.rpc_id(1)
		await _until(func() -> bool: return v != null and v.modules.events_seen > seen and expect.has("hit"), 30.0)
		var h: Dictionary = expect.get("hit", {})
		var r := HitReport.of_event(v, v.modules.events.back()) if v and v.modules.events_seen > seen else {}
		note.call(not r.is_empty() and String(r.outcome) == String(h.get("outcome", "?")) and String(r.plate) == String(h.get("plate", "?"))
			and int(r.t_eff) == int(h.get("t_eff", -1)) and JSON.stringify(r.modules) == JSON.stringify(h.get("modules", [])),
			"the next hit's HitEvent came here: the same report (%s)" % (HitReport.line(r) if not r.is_empty() else "none"))
		var me := level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		var x := VehicleXray.of(me)
		await _frames(2)
		var kept: Dictionary = x.reports.back() if x != null and not x.reports.is_empty() else {}
		note.call(not kept.is_empty() and String(kept.get("outcome", "")) == String(r.get("outcome", "?")) and String(kept.get("plate", "")) == String(r.get("plate", "?")),
			"and this player's x-ray kept it (%d reports: %s)" % [x.reports.size() if x else -1, HitReport.line(kept) if not kept.is_empty() else "none"])
	_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


# --- Helpers ------------------------------------------------------------------------------------

func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player") -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos), "", faction, "vh_%s_%d" % [model, _n])
	v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	v.freeze = true
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(0.3)
	return v


## `n` AI men beside `v`, not seated.
func _men(n: int, v: Vehicle) -> Array:
	var out: Array = []
	for i in n:
		_n += 1
		var s := level.spawn_soldier({"name": "VhCrew%d" % _n, "person_name": "Crew %d" % _n, "faction": "friendly", "variant": "woodland",
			"pos": v.global_position + Vector3(5.0, 0.0, float(i)), "loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		out.append(s)
	await _physics(2)
	return out


func _clear(v: Vehicle, people: Array) -> void:
	if is_instance_valid(v):
		for s: Soldier in v.occupants():
			v.server_exit(s)
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	player.global_position = Vector3(0, 0.1, 0)
	await _seconds(VehicleHud.SHOW_S + 0.2)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
