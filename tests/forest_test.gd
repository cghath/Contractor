extends Node
## The Experimental forest test zone (Captain, 2026-10-14: "include experimental forest mission
## like we dev'd", "make it a button on the menu, not a regular mission"): the main menu's Test
## zones button hosts it (Menu.host_forest_zone) on the forest_experimental preset with the
## copses-as-cover layout, its stand-in raid briefing opens on the map, and nothing of it is in
## the campaign (not a campaign zone, nothing on the board or in the campaign save). One process:
##   <exe> --headless --path . res://tests/forest_test.tscn
## Prints FOREST TEST PASSED/FAILED and exits with its failure count.

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = "test_forest" + tag  # never touch a real campaign
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("FOREST TEST FAILED (timed out)")
		get_tree().quit(99))
	print("Experimental forest: not in the campaign")
	var campaign_zones: Array = MissionRegistry.zones().map(func(z: Dictionary) -> String: return String(z.zone_id))
	var preset_used := false
	for id: String in campaign_zones:
		preset_used = preset_used or String(MissionRegistry.zone_def(id).get("terrain", "")) == "forest_experimental"
	check(Menu.FOREST_ZONE not in campaign_zones and not preset_used and TerrainPresets.choose({"name": "Black forest", "region": "inland"}) != "forest_experimental",
		"no campaign zone is the forest or uses its preset, and no name hint picks it (%s)" % [campaign_zones])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var button: Button = null
	for b: Node in main.get_node(^"Menu").find_children("*", "Button", true, false):
		if (b as Button).text == Menu.FOREST_BUTTON_TEXT:
			button = b
	check(button != null, "the main menu's Test zones has \"%s\"" % Menu.FOREST_BUTTON_TEXT)
	if button == null:
		_finish()
		return
	var started := Time.get_ticks_msec()
	button.pressed.emit()
	var level := CompoundLevel.current(self) as ZoneLevel
	check(level != null and Net.is_hosting(), "pressing it hosts a zone on port %d (%.1f s)" % [Net.port(), (Time.get_ticks_msec() - started) / 1000.0])
	if level == null or not Net.is_hosting():
		_finish()
		return
	check(String(level.def.get("terrain", "")) == "forest_experimental" and level.modules().size() == 3 and String(level.def.name).contains("Experimental")
		and GameState.zone_id == "test_" + Menu.FOREST_ZONE,
		"it's the Experimental forest: %s, %.0f m, %d modules, preset %s, save %s" % [level.def.name, float(level.def.size_m), level.modules().size(), level.def.get("terrain", "?"), GameState.zone_id])
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	check(level.players.get_node_or_null(^"1") != null, "the host's player is in")
	var scatter: ZoneScatter = null
	for n: Node in level.find_children("*", "", true, false):
		if n is ZoneScatter:
			scatter = n
	check(scatter != null and scatter._cover and scatter.counts[ZoneScatter.Kind.TREE] > 2000 and scatter.counts[ZoneScatter.Kind.THICKET] > 2000,
		"its woods are the denser copses-as-cover layout (%s)" % [scatter.counts if scatter else "no scatter"])
	var briefing := MapNodes.briefing(level)
	var c: Dictionary = briefing.contract if briefing else {}
	check(briefing != null and briefing.is_open() and String(c.get("title", "")).begins_with("EXPERIMENTAL") and (c.get("objectives", []) as Array).size() == 3
		and not briefing.insertion_points().is_empty(),
		"its stand-in raid briefing is open: %s, %d objectives, %d insertion points" % [c.get("title", "?"), (c.get("objectives", []) as Array).size(), briefing.insertion_points().size() if briefing else 0])
	for i in 120:  # a couple of seconds of the zone running (streaming, garrisons)
		await get_tree().process_frame
	check(Campaign.section(Contracts.SECTION).is_empty() and Contracts.board().is_empty(),
		"nothing went into the campaign (no contracts section, no board)")
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	GameState.delete_save()
	print("FOREST TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
