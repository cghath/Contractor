extends Node
## Player fire support (FireSupport, FireMission, UavSupport; the Captain's list of 2026-10-20:
## "player artillery and UAV calls"). The sums first (corrections along the observer's line, time
## of flight, where the guns stand, who lends what), then on a small zone hosted here:
## - the menu's Support > Fire support entries;
## - calling a fire mission: the first adjusting round flies its time of flight and lands within
##   its dispersion of the aim plus the mission's starting error; paid per round from cash;
## - adjusting: the correction read off the burst ("add .., right ..") brings the next round onto
##   the target; then a fire for effect of six, after which the mission ends and the cooldown runs
##   (a new call is refused), and a call that can't be paid is refused;
## - dispersion: every round of three fires for effect (mortar and battery) within the stated radius;
## - danger close: a mission on a point near the squad waits for the confirmation, then fires;
## - smoke rounds: a white cloud each, no blast;
## - the blast: a hostile beside the burst is hurt or keeps his head down, a technical is hit (and
##   marked as the guns' work);
## - who lends what where: the region, the deployment, the standing;
## - the UAV: inbound, on station, the hostile in its view tagged, the one outside it not; its feed's
##   camera above the point looking down; it leaves after its time, and its cooldown holds a new call;
## - storms ground it (a call refused) and send one up home; shot down, it falls and is gone;
## - the cooldown kept in the deployment (where the supports keep theirs).
##   <voxel godot exe> --headless --path . res://tests/firesupport_test.tscn
## Exits with the number of failures.

const DEF := {"id": "firesupport_test", "name": "Fire support test", "kind": "contract", "size_m": 1280, "seed": 31, "relief_m": 2.0, "folds_m": 0.0,
	"modules": [], "insertion": [[0.0, 300.0]], "extraction": [[0.0, -420.0]]}
## Where the player stands, and the target 450 m north of him.
const HOME := Vector3(0, 0, 300)
const TARGET := Vector3(0, 0, -150)

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var fs: FireSupport
var uav: UavSupport
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_firesupport" + tag  # never touch a real save
	Campaign.campaign_id = "test_firesupport_campaign" + tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_firesupport_settings%s.cfg" % tag))  # never the player's
	CompoundLevel.spawn_ai = false
	PeopleLayer.contract_people = false
	Contracts.auto_show_debrief = false
	Vehicle.fire_rolls = false
	EnemyDrones.enabled = false
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("FIRESUPPORT TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	Campaign.reset_campaign()
	_test_sums()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = _host_zone()
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the suite's zone")
	if level == null or not Net.is_hosting() or not await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0):
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place him
	_put_player(HOME)
	await _frames(5)
	fs = FireSupport.of(level)
	uav = UavSupport.of(level)
	check(fs != null and uav != null and ObserverMission.of(level) != null, "the level has its FireSupport, UavSupport and ObserverMission nodes")
	if fs == null or uav == null:
		_finish()
		return
	Contracts.new_full_campaign(51, 200000)
	_test_menu()
	await _test_call_adjust_ffe()
	await _test_dispersion()
	await _test_danger_close()
	await _test_smoke()
	await _test_blast()
	_test_gates()
	await _test_uav()
	await _test_storm()
	await _test_shot_down()
	_test_saved()
	_finish()


func _finish() -> void:
	FireSupport.free_calls = -1
	FireSupport.gated = -1
	FireSupport.dispersion_mult = 1.0
	FireSupport.region_override = ""
	FireSupport.offset_s = 0.0
	Campaign.reset_campaign()
	GameState.delete_save()
	print("FIRESUPPORT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- The sums (no level) ----------------------------------------------------------------------

func _test_sums() -> void:
	print("Fire mission sums")
	check(FireMission.units() == ["mortar", "artillery"] and not FireMission.uav().is_empty(), "two firing units (the 81 mm section, the 105 mm battery) and the UAV in data/fire_support.json")
	var a := FireMission.parse("add 50, left 25")
	var b := FireMission.parse("drop100 r50")
	check(a.get("move") == Vector2(-25, 50) and b.get("move") == Vector2(50, -100), "corrections read: \"add 50, left 25\" %s, \"drop100 r50\" %s" % [a.get("move"), b.get("move")])
	check(FireMission.parse("left 25 right 10").has("why") and FireMission.parse("up 50").has("why") and FireMission.parse("add").has("why")
		and FireMission.parse("add 2000").has("why") and FireMission.parse("repeat").get("move") == Vector2.ZERO, "bad corrections refused (two line corrections, up, no metres, too far); repeat moves nothing")
	var observer := Vector3(0, 0, 100)
	var aim := Vector3.ZERO  # north of him (-z)
	var added := FireMission.corrected(aim, observer, Vector2(0, 50))
	var lefted := FireMission.corrected(aim, observer, Vector2(-25, 0))
	check(added.is_equal_approx(Vector3(0, 0, -50)) and lefted.is_equal_approx(Vector3(-25, 0, 0)),
		"along the observer's line: add 50 is 50 m further (%s), left 25 is 25 m to his left (%s)" % [added, lefted])
	check(is_equal_approx(FireMission.bearing(observer, aim), 0.0) and is_equal_approx(FireMission.bearing(Vector3.ZERO, Vector3(10, 0, 0)), 90.0), "bearings from north")
	var mortar := FireMission.unit("mortar")
	var arty := FireMission.unit("artillery")
	var m15 := FireMission.flight_s(1500.0, float(mortar.elevation_mils))
	var m4k := FireMission.flight_s(4000.0, float(mortar.elevation_mils))
	var a6k := FireMission.flight_s(6000.0, float(arty.elevation_mils))
	check(m15 > 18.0 and m15 < 30.0 and m4k > m15 and a6k > 15.0 and a6k < 35.0,
		"real times of flight: the mortar's high angle %.0f s at 1.5 km, %.0f s at 4 km; the 105s %.0f s at 6 km" % [m15, m4k, a6k])
	var gun := FireMission.gun_point(Rect2(-640, -640, 1280, 1280), Vector3.ZERO, Vector3(0, 0, 2000), 600.0)
	check(gun.is_equal_approx(Vector3(0, 0, 1240)), "the guns stand off the map past its edge, on the supports' side (%s)" % gun)
	check(FireMission.danger_close(Vector3.ZERO, [Vector3(100, 0, 0), Vector3(200, 0, 0)], 150.0) == 1, "danger close counts who's within its radius")
	var tiers := MissionRegistry.reputation_tiers()
	var index := func(id: String) -> int:
		for i in tiers.size():
			if String(tiers[i].id) == id:
				return i
		return -1
	check(FireSupport.lends(mortar, index.call("neutral")) and not FireSupport.lends(arty, index.call("neutral")) and FireSupport.lends(arty, index.call("trusted"))
		and not FireSupport.lends(mortar, -1), "the mortars come with any working standing, the battery from Trusted, nothing without a deployment")


# --- The menu ----------------------------------------------------------------------------------

func _test_menu() -> void:
	print("The support menu")
	var support: Dictionary = _entry(CommandMenu.MENU, "Support")
	var fire: Dictionary = _entry(support, "Fire support")
	var cmds := PackedStringArray()
	_cmds(fire, cmds)
	check(cmds.has("support:fire:call:mortar:marker") and cmds.has("support:fire:call:artillery:here") and cmds.has("support:fire:adjust::add 50")
		and cmds.has("support:fire:ffe::smoke:3") and cmds.has("support:fire:confirm:") and cmds.has("support:fire:end:") and cmds.has("local:fire_panel")
		and cmds.has("support:uav:here") and cmds.has("local:uav_feed") and cmds.has("support:uav:home"),
		"Support > Fire support: calls on a marker or a point, adjust, fire for effect, danger close, end, the panel, the UAV and its feed (%d entries)" % cmds.size())


func _entry(level_def: Dictionary, label: String) -> Dictionary:
	for item: Dictionary in level_def.get("items", []):
		if String(item.label) == label:
			return item
	return {}


func _cmds(level_def: Dictionary, out: PackedStringArray) -> void:
	for item: Dictionary in level_def.get("items", []):
		if item.has("items"):
			_cmds(item, out)
		elif item.has("cmd"):
			out.append(String(item.cmd))


# --- Fire missions -----------------------------------------------------------------------------

func _cmd(cmd: String, point := Vector3.INF) -> String:
	return Supports.server_command(player, cmd, point, PackedStringArray())


## Advances fire support until no round of `unit` is in the air (at most `seconds`).
func _land_all(unit: String, seconds := 120.0) -> void:
	var t := 0.0
	while t < seconds and fs.rounds.any(func(r: Dictionary) -> bool: return String(r.unit) == unit):
		fs.server_advance(1.0)
		t += 1.0
	await _frames(2)


func _test_call_adjust_ffe() -> void:
	print("A fire mission: call, adjust, fire for effect")
	FireSupport.free_calls = 0
	FireSupport.gated = 0
	fs.server_reset_limits()
	var target := level.ground_point(TARGET)
	var u := FireMission.unit("mortar")
	var cash := Economy.cash()
	var why := _cmd("support:fire:call:mortar:here", target)
	var m := fs.mission("mortar")
	check(why == "" and not m.is_empty() and fs.rounds.size() == 1 and fs.heard_line("Fire mission, grid"),
		"called on the point looked at: the mission is open, one adjusting round on its way, the call on the radio ('%s')" % why)
	check(Economy.cash() == cash - Prices.support_price("mortar_round"), "the round is paid from cash ($%d)" % (cash - Economy.cash()))
	if m.is_empty():
		return
	var bias := Vector3(60, 0, 45)  # the guns' starting error, known here
	fs.server_set_bias("mortar", bias)
	var range_m := FireMission.flat(m.gun, target)
	var spread := FireMission.dispersion_m(u, range_m)
	var r0: Dictionary = fs.rounds[0]
	var flight := float(r0.when) - float(r0.fire_at)
	check(is_equal_approx(flight, FireMission.flight_s(range_m, float(u.elevation_mils))) and float(r0.fire_at) - FireSupport.now() > float(u.response_s) - 1.0,
		"it fires after the section's response (%d s) and flies %.0f s over %d m from the guns off the map" % [int(u.response_s), flight, roundi(range_m)])
	await _land_all("mortar")
	check(fs.heard_line("Shot, over") and fs.heard_line("Splash, over"), "shot and splash on the radio")
	var burst: Vector3 = fs.impacts.back().pos if not fs.impacts.is_empty() else Vector3.INF
	check(burst.is_finite() and FireMission.flat(burst, target + bias) <= spread + 1.0,
		"the adjusting round lands off by the mission's error, within the dispersion (%.0f m of %.0f)" % [FireMission.flat(burst, target + bias), spread])
	var first_off := FireMission.flat(burst, target)
	# Read the correction off the burst, along his line to the target.
	var ot := FireMission.ot_dir(player.global_position, m.aim)
	var right := Vector3(-ot.z, 0.0, ot.x)
	var delta := target - burst
	var add := roundi(delta.dot(ot) / 5.0) * 5
	var side := roundi(delta.dot(right) / 5.0) * 5
	var text := "%s %d, %s %d" % ["add" if add >= 0 else "drop", absi(add), "right" if side >= 0 else "left", absi(side)]
	why = _cmd("support:fire:adjust:mortar:" + text)
	check(why == "" and fs.heard_line("adjusting"), "adjust: \"%s\" ('%s')" % [text, why])
	await _land_all("mortar")
	var second: Vector3 = fs.impacts.back().pos
	check(FireMission.flat(second, target) < first_off and FireMission.flat(second, target) <= spread * 2.0 + 2.0,
		"the next round comes onto the target (%.0f m off, the first %.0f)" % [FireMission.flat(second, target), first_off])
	cash = Economy.cash()
	var before := fs.impacts.size()
	why = _cmd("support:fire:ffe:mortar:he:6")
	check(why == "" and fs.rounds.size() == 6 and Economy.cash() == cash - 6 * Prices.support_price("mortar_round"),
		"fire for effect, six HE: six rounds on their way, paid ($%d)" % (cash - Economy.cash()))
	await _land_all("mortar")
	fs.server_advance(FireSupport.SPLASH_WARN_S + 1.0)
	await _frames(2)
	check(fs.impacts.size() - before == 6 and fs.mission("mortar").is_empty() and fs.heard_line("End of mission"),
		"all six land, then the mission ends (end of mission on the radio)")
	check(fs.cooldown_left("mortar") > float(u.cooldown_s) - 30.0, "the section's cooldown runs (%d s)" % ceili(fs.cooldown_left("mortar")))
	why = _cmd("support:fire:call:mortar:here", target)
	check(why.contains("another mission in"), "a new call waits for it ('%s')" % why)
	check(fs.rounds_left("mortar", "he") == int(u.rounds_per_op.he) - 8, "eight HE rounds given of the deployment's %d" % int(u.rounds_per_op.he))
	# Can't pay.
	fs.server_reset_limits()
	Economy.add_cash(100 - Economy.cash(), "test: broke")
	why = _cmd("support:fire:call:mortar:here", target)
	check(why.begins_with("Can't pay") and fs.mission("mortar").is_empty() and fs.rounds.is_empty(), "with no money for a round, refused ('%s')" % why)
	Economy.add_cash(200000 - Economy.cash(), "test: funds back")
	FireSupport.free_calls = 1


func _test_dispersion() -> void:
	print("Dispersion")
	var target := level.ground_point(TARGET)
	var inside := true
	var widest := {}
	var count := 0
	for unit: String in ["mortar", "artillery", "artillery"]:
		fs.server_reset_limits()
		var why := _cmd("support:fire:call:%s:here" % unit, target)
		fs.server_set_bias(unit, Vector3.ZERO)
		await _land_all(unit)
		var before := fs.impacts.size()
		why += _cmd("support:fire:ffe:%s:he:%d" % [unit, int(FireMission.unit(unit).max_rounds)])
		await _land_all(unit)
		if why != "":
			check(false, "%s mission ('%s')" % [unit, why])
		for i in range(before, fs.impacts.size()):
			var hit: Dictionary = fs.impacts[i]
			var r := FireMission.dispersion_m(FireMission.unit(unit), float(hit.range_m))
			var off := FireMission.flat(hit.pos, hit.aim)
			inside = inside and off <= r + 0.5
			widest[unit] = maxf(float(widest.get(unit, 0.0)), off / r)
			count += 1
		fs.server_advance(FireSupport.SPLASH_WARN_S + 1.0)
	check(count == 8 + 12 and inside, "%d rounds, every one within its stated radius of the aim (the mortar's %.0f m, the battery's %.0f m)" % [count,
		FireMission.dispersion_m(FireMission.unit("mortar"), 1090.0), FireMission.dispersion_m(FireMission.unit("artillery"), 5000.0)])
	check(float(widest.get("mortar", 0.0)) > 0.3 and float(widest.get("artillery", 0.0)) > 0.3, "and spread over it, not all on the aim (%s)" % [widest])


func _test_danger_close() -> void:
	print("Danger close")
	fs.server_reset_limits()
	var near := level.ground_point(HOME + Vector3(0, 0, -100))  # 100 m from the player
	var why := _cmd("support:fire:call:mortar:here", near)
	check(why.begins_with("Danger close") and fs.rounds.is_empty() and fs.heard_line("Danger close") and bool(fs.summary().mortar.held),
		"a mission 100 m from the squad waits: danger close, asking for confirmation ('%s')" % why)
	why = _cmd("support:fire:confirm:")
	check(why == "" and fs.rounds.size() == 1, "confirmed, the round goes ('%s')" % why)
	why = _cmd("support:fire:ffe::he:2")
	check(why == "" and fs.rounds.size() == 3, "and the rest of the mission fires without asking again ('%s')" % why)
	await _land_all("mortar")
	fs.server_advance(FireSupport.SPLASH_WARN_S + 1.0)
	check(fs.mission("mortar").is_empty(), "the mission ends")


func _test_smoke() -> void:
	print("Smoke rounds")
	fs.server_reset_limits()
	var target := level.ground_point(TARGET)
	var clouds := _clouds()
	var why := _cmd("support:fire:call:mortar:here", target)
	await _land_all("mortar")
	var before := fs.impacts.size()
	why += _cmd("support:fire:ffe::smoke:3")
	await _land_all("mortar")
	fs.server_advance(FireSupport.SPLASH_WARN_S + 1.0)
	await _frames(3)
	var smoke := fs.impacts.slice(before).filter(func(h: Dictionary) -> bool: return String(h.shell) == "smoke")
	check(why == "" and smoke.size() == 3 and _clouds() - clouds >= 3, "three smoke rounds: three white clouds on the target (%d new)" % (_clouds() - clouds))
	check(fs.rounds_left("mortar", "smoke") == int(FireMission.unit("mortar").rounds_per_op.smoke) - 3, "counted against the smoke the section has")


func _clouds() -> int:
	return level.get_children().filter(func(n: Node) -> bool: return n is SmokeCloud).size()


func _test_blast() -> void:
	print("What a round does")
	fs.server_reset_limits()
	FireSupport.dispersion_mult = 0.05
	var target := level.ground_point(TARGET + Vector3(0, 0, -60))
	var man := _dummy("hostile", target + Vector3(7, 0, 0))
	var layer := VehicleLayer.of(level)
	var truck := layer.server_spawn("technical_dshk", Transform3D(Basis.IDENTITY, target + Vector3(-3, 0.6, 2)), "", &"hostile")
	await _frames(5)
	var why := _cmd("support:fire:call:artillery:here", target)
	fs.server_set_bias("artillery", Vector3.ZERO)
	await _land_all("artillery")
	why += _cmd("support:fire:ffe::he:2")
	await _land_all("artillery")
	fs.server_advance(FireSupport.SPLASH_WARN_S + 1.0)
	await _frames(3)
	check(why == "" and man != null and (not man.vitals.is_up() or not man.vitals.wound_list().is_empty() or man.suppression > 0.0),
		"a hostile 7 m from the bursts is hurt or keeps his head down (up %s, %d wounds, suppression %.2f)" % [man.vitals.is_up(), man.vitals.wound_list().size(), man.suppression])
	check(truck != null and FireSupport.hit_lately(truck, 60.0) and (truck.wrecked or truck.zone_health(Vehicle.ZONE_HULL) < 1.0),
		"a technical beside them is hit (%s, hull %d%%), marked as the guns' work" % ["wrecked" if truck and truck.wrecked else "standing", roundi(truck.zone_health(Vehicle.ZONE_HULL) * 100.0) if truck else -1])
	FireSupport.dispersion_mult = 1.0
	if is_instance_valid(man):
		man.queue_free()
	if is_instance_valid(truck):
		truck.queue_free()
	await _frames(2)


func _test_gates() -> void:
	print("Who lends what, where")
	fs.server_reset_limits()
	FireSupport.gated = 1
	FireSupport.region_override = "coast"
	var why := _cmd("support:fire:call:artillery:here", level.ground_point(TARGET))
	check(why.contains("can't reach the coast"), "the 105s at the inland FOB don't reach the coast ('%s')" % why)
	FireSupport.region_override = "inland"
	why = _cmd("support:fire:call:mortar:here", level.ground_point(TARGET))
	check(why.contains("outside a deployment"), "no fire support outside a deployment ('%s')" % why)
	why = _cmd("support:uav:here", level.ground_point(TARGET))
	check(why.contains("outside a deployment"), "nor the UAV ('%s')" % why)
	FireSupport.region_override = ""
	FireSupport.gated = 0


# --- The UAV ----------------------------------------------------------------------------------

func _test_uav() -> void:
	print("The recon UAV")
	fs.server_reset_limits()
	DayNight.current().server_set(12.0, "clear")
	var s := FireMission.uav()
	var centre := level.ground_point(Vector3(0, 0, -100))
	var seen := _dummy("hostile", centre + Vector3(12, 0, 6))
	var far := _dummy("hostile", centre + Vector3(0, 0, float(s.sensor_m) + 150.0))
	await _frames(3)
	var why := _cmd("support:uav:here", centre)
	check(why == "" and uav.is_up() and String(uav.drone.state) == "inbound" and fs.heard_line("On the way"), "called over a point: it's on the way ('%s')" % why)
	await _frames(3)
	check(not uav.shown.is_empty() and uav.get_node_or_null(^"UavVisual") != null, "every peer draws it")
	var t := 0.0
	while t < 120.0 and uav.is_up() and String(uav.drone.state) != "station":
		uav.server_advance(1.0)
		t += 1.0
	check(uav.is_up() and String(uav.drone.state) == "station" and fs.heard_line("On station"), "on station over the point after %d s" % int(t))
	var height := float(uav.drone.pos.y) - centre.y
	check(height > float(s.alt_m) - 20.0 and FireMission.flat(uav.drone.pos, centre) < float(s.orbit_m) * 1.3,
		"circling %d m up, %d m out" % [roundi(height), roundi(FireMission.flat(uav.drone.pos, centre))])
	var tags := EnemyTags.of(level)
	t = 0.0
	while t < 30.0 and not tags.is_tagged(String(seen.name)):
		uav.server_advance(0.5)
		t += 0.5
	check(tags.is_tagged(String(seen.name)) and not tags.is_tagged(String(far.name)),
		"the hostile in its view is tagged for the squad after %.1f s (EnemyTags); the one outside it isn't" % t)
	uav.server_advance(2.0)
	await _frames(3)
	UavFeed.toggle(player)
	await _frames(3)
	var feed := get_tree().root.get_node_or_null(^"UavFeed") as UavFeed
	check(feed != null and feed.camera.current and feed.camera.global_position.distance_to(uav.shown.pos) < 1.0 and (-feed.camera.global_basis.z).y < -0.5
		and FireMission.flat(feed.looking_at(centre.y), centre) < 5.0, "its feed: a camera at the UAV looking down on the point")
	UavFeed.toggle(player)
	# Its time on station runs out: home, and gone.
	uav.server_advance(float(s.loiter_s) + 1.0)
	check(not uav.is_up() or String(uav.drone.state) == "home", "after %d min on station it heads home" % roundi(float(s.loiter_s) / 60.0))
	t = 0.0
	while t < 200.0 and not uav.drone.is_empty():
		uav.server_advance(1.0)
		t += 1.0
	await _frames(3)
	check(uav.drone.is_empty() and uav.shown.is_empty() and uav.get_node_or_null(^"UavVisual") == null and fs.heard_line("Off station"), "and leaves (gone from every peer's sky)")
	why = _cmd("support:uav:here", centre)
	check(why.contains("can go up again"), "its cooldown holds the next call ('%s')" % why)
	seen.queue_free()
	far.queue_free()


func _test_storm() -> void:
	print("Storms ground it")
	fs.server_reset_limits()
	var centre := level.ground_point(Vector3(0, 0, -100))
	DayNight.current().server_set(12.0, "storm")
	var why := _cmd("support:uav:here", centre)
	check(why.contains("grounded") and not uav.is_up(), "in a storm a call is refused ('%s')" % why)
	DayNight.current().server_set(12.0, "clear")
	why = _cmd("support:uav:here", centre)
	uav.server_advance(5.0)
	DayNight.current().server_set(12.0, "storm")
	uav.server_advance(1.0)
	check(why == "" and String(uav.drone.get("state", "")) == "home" and fs.heard_line("Weather's closing in"), "one up when the storm comes heads home")
	DayNight.current().server_set(12.0, "clear")
	var t := 0.0
	while t < 200.0 and not uav.drone.is_empty():
		uav.server_advance(1.0)
		t += 1.0
	check(uav.drone.is_empty(), "and lands")


func _test_shot_down() -> void:
	print("Shot down")
	fs.server_reset_limits()
	var why := _cmd("support:uav:me")
	var body: Node = uav.drone.get("body")
	check(why == "" and is_instance_valid(body) and body.has_meta(&"on_bullet"), "up again, a body rounds hit (Ballistics' on_bullet)")
	for i in int(FireMission.uav().hits):
		if is_instance_valid(body):
			(body.get_meta(&"on_bullet") as Callable).call(Vector3.ZERO, null)
	check(String(uav.drone.get("state", "")) == "falling" and fs.heard_line("lost the UAV"), "%d hits bring it down" % int(FireMission.uav().hits))
	var t := 0.0
	while t < 60.0 and not uav.drone.is_empty():
		uav.server_advance(0.5)
		t += 0.5
	check(uav.drone.is_empty() and uav.cooldown_left() > 0.0, "it crashes and is gone, the cooldown running")


func _test_saved() -> void:
	print("Saved with the deployment")
	var roster := BaseHub.roster()
	var had: Variant = roster.get("deployment")
	var was := BaseHub.campaign_running
	BaseHub.campaign_running = true
	roster["deployment"] = {"active": true}
	fs._set_cooldown("artillery", 50.0)
	var dep: Dictionary = roster.deployment
	check(dep.has("fire_support") and absf(fs.cooldown_left("artillery") - 50.0) < 1.0, "a deployment keeps the cooldowns (and rounds given) under \"fire_support\", where the rebels' call-ins keep theirs")
	BaseHub.campaign_running = was
	if had == null:
		roster.erase("deployment")
	else:
		roster["deployment"] = had


# --- Helpers ----------------------------------------------------------------------------------

## Hosts the suite's zone in place of main's compound (as supports_test does).
func _host_zone() -> ZoneLevel:
	var current: CompoundLevel = null
	for child in main.get_children():
		if child is CompoundLevel and child.is_in_group(&"level"):
			current = child
	var lvl := (load(LevelSwitch.scene_for({"level": "zone"})) as PackedScene).instantiate() as ZoneLevel
	lvl.configure(DEF)
	var index := 0
	if current:
		index = current.get_index()
		LevelSwitch._retire(current)
	main.add_child(lvl)
	main.move_child(lvl, index)
	return lvl


## A soldier whose brain doesn't run.
func _dummy(faction: String, pos: Vector3) -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": "FsDummy%d" % _made, "faction": faction, "variant": "urban", "pos": level.ground_point(pos),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _put_player(pos: Vector3) -> void:
	player.global_position = level.ground_point(pos) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
