extends Node
## Day and night, weather (wave 7 S1, DayNight). In the compound, hosted:
## - darkness: none at noon and mid-morning, full at midnight, between at dusk; clouds add to it;
## - the sun climbs and sets with the hour; at night the moon (dim, blue) lights the level;
## - spotting (Spotting.sight_x): no change by day in clear weather; at night slower and nobody
##   seen past the night's sight unless they fire; fog hides anyone past its sight, flash or not;
## - footsteps carry less in rain;
## - a storm grounds helicopters (Supports.can_fly, HeliSupports refuses with a message);
## - the time passes in a contract zone (advance), not past 24;
## - saved with the zone and restored over the definition's;
## - the host's sync (DayNight._sync, what a client gets) sets the time and weather.
##   <godot> --headless --path . res://tests/daynight_test.tscn

var failures := 0
var level: CompoundLevel
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_daynight" + tag
	Campaign.campaign_id = "test_daynight" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("DAYNIGHT TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "compound"})
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the compound")
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	await get_tree().process_frame
	_run()
	_finish()


func _run() -> void:
	var dn := DayNight.current()
	check(dn != null and dn.get_parent() == level and dn.name == DayNight.NODE_NAME, "the level has its DayNight")
	if dn == null:
		return
	check(is_equal_approx(dn.hour, DayNight.DEFAULT_HOUR) and dn.weather == "clear" and not dn.passing,
		"the compound: %.1f h, %s, the time standing (no contract)" % [dn.hour, dn.weather])
	# Darkness.
	check(DayNight.night_of(12.0) == 0.0 and DayNight.night_of(DayNight.DEFAULT_HOUR) == 0.0, "no darkness at noon or mid-morning")
	check(DayNight.night_of(0.0) == 1.0 and DayNight.night_of(2.0) == 1.0, "full darkness at midnight and 02:00")
	var dusk := DayNight.night_of(18.3)
	check(dusk > 0.1 and dusk < 0.9, "dusk is between (18:18: %.2f)" % dusk)
	check(absf(DayNight.sun_elevation_deg(DayNight.DEFAULT_HOUR) - ZoneLevel.SUN_ELEVATION_DEG) < 1.5,
		"mid-morning's sun is where zones were lit before (%.1f deg)" % DayNight.sun_elevation_deg(DayNight.DEFAULT_HOUR))
	dn.server_set(12.0, "clear")
	check(DayNight.darkness_at(player.global_position) == 0.0, "noon: darkness_at 0")
	var sun := _sun()
	var day_energy := sun.light_energy if sun else 0.0
	dn.server_set(0.0, "clear")
	check(DayNight.darkness_at(player.global_position) == 1.0, "midnight: darkness_at 1")
	check(sun != null and sun.light_color.is_equal_approx(DayNight.MOON_COLOUR) and sun.light_energy < day_energy * 0.2,
		"midnight: the moon lights it (%.2f, by day %.2f)" % [sun.light_energy if sun else -1.0, day_energy])
	dn.server_set(17.0, "overcast")
	var cloudy := DayNight.darkness_at(Vector3.ZERO)
	dn.server_set(17.0, "clear")
	check(cloudy > DayNight.darkness_at(Vector3.ZERO), "clouds make the evening darker (%.2f > %.2f)" % [cloudy, DayNight.darkness_at(Vector3.ZERO)])
	# Spotting.
	dn.server_set(12.0, "clear")
	check(Spotting.sight_x(null, Vector3.ZERO, 300.0) == 1.0, "noon, clear: spotting as before (x1 at 300 m)")
	dn.server_set(0.0, "clear")
	check(Spotting.sight_x(null, Vector3.ZERO, 100.0) == INF, "midnight: nobody seen at 100 m")
	var near := Spotting.sight_x(null, Vector3.ZERO, 40.0)
	check(near > 1.0 and near < INF, "midnight: seen at 40 m, slower (x%.1f)" % near)
	check(Spotting.sight_x(null, Vector3.ZERO, 100.0, true) < INF, "midnight: a muzzle flash at 100 m is seen")
	check(Spotting.night_sight_m(1.0) < Spotting.night_sight_m(0.3) and Spotting.night_sight_m(0.3) < Spotting.night_sight_m(0.0),
		"the darker, the shorter the sight (%.0f < %.0f m < day)" % [Spotting.night_sight_m(1.0), Spotting.night_sight_m(0.3)])
	dn.server_set(12.0, "fog")
	check(Spotting.sight_x(null, Vector3.ZERO, 200.0, true) == INF, "fog at noon: nobody seen at 200 m, flash or not")
	check(Spotting.sight_x(null, Vector3.ZERO, 100.0) > 1.0 and Spotting.sight_x(null, Vector3.ZERO, 100.0) < INF, "fog: seen at 100 m, slower")
	var env := _env()
	check(env != null and env.fog_enabled and env.fog_density > 0.005, "fog: the Environment's fog is thick (%.4f)" % (env.fog_density if env else -1.0))
	dn.server_set(12.0, "clear")
	var dry := DayNight.hearing_x()
	dn.server_set(12.0, "rain")
	check(DayNight.hearing_x() < dry, "rain: footsteps carry less (x%.2f)" % DayNight.hearing_x())
	# Helicopters.
	check(Supports.can_fly(level) and not DayNight.grounds_aircraft(), "rain: helicopters still fly")
	dn.server_set(12.0, "storm")
	check(DayNight.grounds_aircraft() and not Supports.can_fly(level), "a storm grounds helicopters")
	var heli := HeliSupports.of(level)
	var why := heli.server_call("resupply", player, "here", player.global_position) if heli else ""
	check(why.contains("grounded"), "a storm: the resupply helicopter is refused (\"%s\")" % why)
	check(heli != null and heli.active("resupply") == null, "and none is out")
	dn.server_set(12.0, "clear")
	check(Supports.can_fly(level), "clear again: they fly")
	# Time passing.
	dn.server_set(23.5, "clear")
	dn.advance(600.0)  # ten real minutes: an hour
	check(absf(dn.hour - 0.5) < 0.01, "an hour passes in ten minutes, round past midnight (%.2f h)" % dn.hour)
	# Saved with the zone.
	dn.server_set(21.0, "rain")
	check(GameState.save_zone(), "the zone saves")
	dn.server_set(9.0, "clear")
	GameState.load_zone()
	dn.server_restore()
	check(absf(dn.hour - 21.0) < 0.01 and dn.weather == "rain", "loaded: 21:00 and rain again (%.2f h, %s)" % [dn.hour, dn.weather])
	# What a client gets.
	dn._sync(4.0, "fog")
	check(is_equal_approx(dn.hour, 4.0) and dn.weather == "fog", "the host's sync sets it (%.1f h, %s)" % [dn.hour, dn.weather])
	dn._sync(5.0, "hail")
	check(dn.weather == DayNight.DEFAULT_WEATHER, "an unknown weather falls back to clear")
	dn.server_set(DayNight.DEFAULT_HOUR, "clear")


func _sun() -> DirectionalLight3D:
	for c in level.get_children():
		if c is DirectionalLight3D:
			return c
	return null


func _env() -> Environment:
	for c in level.get_children():
		if c is WorldEnvironment:
			return (c as WorldEnvironment).environment
	return null


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("DAYNIGHT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()
