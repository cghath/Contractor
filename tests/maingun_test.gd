extends Node
## Headless checks for combined arms A3 (cg_brief queue item 2.2; docs/combined_arms.md 2.5, 2.7,
## 9.3): the Abrams' and Bradley's main guns in the real compound. The weapons data and seats;
## ShellFlight's ballistics against 2.7.5's table (pure, and a real round into a wall at 1 km);
## the turrets' traverse and elevation rates and their drive modules (damaged, by hand, on
## batteries); timed seat moves; the loader's cycle (an AI loader by skill, a player's ram window,
## short-crewed loads, a damaged breech, changing rounds, restocking from the hull); the bustle's
## blast doors (a hit while they're open goes up, shut it vents); the Bradley's dual feed, rates
## and ready-box refill; every round fired for real at targets 500 m off through ArmourModel
## (M829A3 and M791 against the STANAG-rated faces, M830A1 HEAT-MP, the TOW-2A) and at people
## (M792 HEI, M1147 AMP, a sabot through a man); the TOW raised, fired, guided, its wire broken by a
## fast traverse and by smoke, reloaded; save and load; the cost of a shot and of 50 rounds in
## flight; then a second process joins over ENet and finds the guns as the host has them (late
## join) and draws a round the host fires.
##   <voxel godot exe> --headless --path . res://tests/maingun_test.tscn
## The host starts the client itself ("-- --maingun-join"). Exits with the number of failures.

## 2.7.5's table: round, muzzle m/s, time of flight 1 km / 2 km (s), drop 1 km / 2 km (m).
const TABLE := [["m829a3", 1555, 0.66, 1.36, 2.1, 9.1], ["m830a1", 1410, 0.75, 1.60, 2.8, 12.6], ["m1147", 1410, 0.75, 1.62, 2.8, 12.9],
	["m791", 1345, 0.78, 1.75, 3.0, 15.0], ["m792", 1100, 1.00, 2.40, 4.9, 28.0], ["3bm42", 1700, 0.60, 1.25, 1.8, 7.7]]
## Budgets (Proposed; docs/combined_arms.md 9.3: "50 shells in flight under 0.5 ms").
const FLIGHT_BUDGET_MS := 0.5
const SHOT_BUDGET_MS := 0.5
## The air rigs: shooters and targets frozen this high, 500 m apart (no ground in the way).
const RIG_Y := 60.0
const RANGE_M := 500.0

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var flight: ShellFlight
var launchers: Launchers
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _n := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_maingun" + tag  # never touch a real save
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--maingun-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(450.0).timeout.connect(func() -> void:
		print("MAINGUN TEST FAILED (timed out)")
		get_tree().quit(99))
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
	flight = ShellFlight.of(level)
	launchers = Launchers.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	player.global_position = Vector3(0, 0.1, 0)
	Vehicle.fire_rolls = true
	for model: String in ["abrams", "bradley"]:
		VehicleHull.prewarm(model)
	_test_data()
	_test_ballistics()
	if _want("air"):
		await _test_wall()
	if _want("turret"):
		await _test_turrets()
		await _test_seats()
	if _want("loader"):
		await _test_loader()
		await _test_doors()
	if _want("feed"):
		await _test_feed()
	if _want("effects"):
		await _test_armour()
		await _test_people()
	if _want("tow"):
		await _test_tow()
	if _want("save"):
		await _test_save()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	GameState.delete_save()
	print("MAINGUN TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_MAINGUN_ONLY="loader,tow" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_MAINGUN_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Data and ballistics (pure) -------------------------------------------------------------------

func _test_data() -> void:
	print("Weapons, rounds and seats in data")
	var mbt := VehicleWeapons.layout(VehicleSpecs.spec("abrams"))
	var ifv := VehicleWeapons.layout(VehicleSpecs.spec("bradley"))
	var ids := func(l: Array) -> Array: return l.map(func(m: Dictionary) -> String: return "%s:%s" % [m.id, m.kind])
	check(ids.call(mbt) == ["main:cannon", "coax:mg", "commander_m2:mg", "loader_m240:mg"] and ids.call(ifv) == ["main:autocannon", "coax:mg", "tow:atgm"],
		"the Abrams: M256, coax, commander's M2, loader's M240; the Bradley: M242, coax, TOW (%s / %s)" % [ids.call(mbt), ids.call(ifv)])
	var ammo: Array = mbt[0].g.ammo
	check(ammo == ["m829a3", "m830a1", "m1147"] and ammo.all(func(s: String) -> bool: return String(Shells.shell(s).get("gun", "")) == "m256"),
		"the M256 fires M829A3 APFSDS, M830A1 HEAT-MP and M1147 AMP (2.4.3)")
	var r := VehicleWeapons.default_racks(VehicleSpecs.spec("abrams"))
	check(r.ammo_rack_bustle == {"m829a3": 16, "m830a1": 10, "m1147": 8} and VehicleWeapons._sum(r.ammo_rack_hull) == 6,
		"the Abrams carries 34 in the bustle (16 sabot, 10 HEAT, 8 AMP) and 6 in the hull (2.7.1)")
	var b := VehicleWeapons.default_racks(VehicleSpecs.spec("bradley"))
	check(b.ready_25 == {"m791": 70, "m792": 230} and VehicleWeapons._sum(b.rack_25) == 600 and b.rack_tow == {"tow2a": 5} and int(ifv[2].ready) == 2,
		"the Bradley: 70 AP and 230 HE ready, 600 stowed, 2 TOW on the launcher and 5 stowed (2.7.1)")
	var kinds := func(m: String) -> Array: return (VehicleSpecs.spec(m).seats as Array).map(func(s: Dictionary) -> String: return String(s.kind))
	check(kinds.call("abrams") == ["driver", "gunner", "commander", "loader"] and (kinds.call("bradley") as Array).slice(0, 3) == ["driver", "gunner", "commander"],
		"the commander's and loader's seats are their own kinds (2.5.1)")
	check(String(Warheads.data(&"tow2a").get("guidance", "")) == "saclos" and float(Warheads.data(&"tow2a").cruise_mps) > 150.0,
		"the TOW-2A is wire-guided (SACLOS), cruising at %d m/s" % int(Warheads.data(&"tow2a").get("cruise_mps", 0)))


func _test_ballistics() -> void:
	print("Shell flight against docs/combined_arms.md 2.7.5 (within 10%)")
	for row: Array in TABLE:
		var a := ShellFlight.flight_to(StringName(row[0]), 1000.0)
		var b := ShellFlight.flight_to(StringName(row[0]), 2000.0)
		var ok := _near(a.time, row[2]) and _near(b.time, row[3]) and _near(a.drop, row[4]) and _near(b.drop, row[5])
		check(ok and int(Shells.shell(row[0]).muzzle_mps) == int(row[1]),
			"%s at %d m/s: 1 km in %.2f s (%.2f), 2 km in %.2f s (%.2f); drop %.1f m (%.1f) and %.1f m (%.1f)" % [row[0], row[1],
			a.time, row[2], b.time, row[3], a.drop, row[4], b.drop, row[5]])


static func _near(got: float, want: float, share := 0.1) -> bool:
	return absf(got - want) <= absf(want) * share


## A real round into a wall 1 km off: the host's flight gives the table's time and drop.
func _test_wall() -> void:
	print("A real M829A3 into a wall 1 km off")
	var origin := Vector3(300, 300, 400)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 60, 1)
	shape.shape = box
	wall.add_child(shape)
	level.add_child(wall)
	wall.global_position = origin + Vector3(0, 0, -1000.5)
	await _physics(2)
	var id := flight.server_fire(&"m829a3", origin, Vector3(0, 0, -1555), null, {})
	await _until(func() -> bool: return flight.results.has(id), 5.0)
	var r: Dictionary = flight.results.get(id, {})
	var drop := origin.y - (r.get("position", origin) as Vector3).y
	check(String(r.get("how", "")) == "world" and _near(float(r.get("time", 0.0)), 0.66) and _near(drop, 2.1),
		"it meets the wall after %.3f s (0.66) and %.2f m below the line (2.1)" % [float(r.get("time", 0.0)), drop])
	wall.queue_free()


# --- Turrets and seats -----------------------------------------------------------------------------

func _test_turrets() -> void:
	print("Turrets: traverse and elevation, and their drives (A2's modules)")
	for row: Array in [["abrams", 40.0, 25.0, -9.0, 20.0], ["bradley", 50.0, 30.0, -9.0, 60.0]]:
		var t := VehicleTurret.of(VehicleSpecs.spec(row[0]))
		var parts: Array = VehicleHull.canvas(row[0]).parts
		var names := parts.map(func(p: Dictionary) -> String: return String(p.name))
		t.aim(PI / 2.0, deg_to_rad(90.0))
		for i in 60:
			t.step(1.0 / 60.0)
		var up := minf(float(row[2]), float(row[4]))  # a second's elevation, or its stop
		check(t != null and _near(rad_to_deg(t.yaw), row[1], 0.02) and _near(rad_to_deg(t.pitch), up, 0.02) and _near(rad_to_deg(t.pitch_min), row[3], 0.01)
			and _near(rad_to_deg(t.pitch_max), row[4], 0.01) and names.slice(0, 2) == ["Turret", "Gun"] and (names.size() == 2 or names == ["Turret", "Gun", "Launcher"]),
			"%s: traverses %.0f degrees in a second (%.0f), elevates %.0f (%.0f; limits %.0f to %.0f), its turret and gun split from the hull (%s)" % [
			row[0], rad_to_deg(t.yaw), row[1], rad_to_deg(t.pitch), up, row[3], row[4], names])
	var v := await _spawn("abrams", Vector3(-60, RIG_Y, 60), 0.0)
	var base := rad_to_deg(v.turret.yaw_rate)
	v.modules.server_set("traverse", 0.4)
	v.modules.server_set("elevation", 0.4)
	var damaged := Vector2(rad_to_deg(v.turret.yaw_rate), rad_to_deg(v.turret.pitch_rate))
	v.modules.server_set("traverse", 0.0)
	var manual := rad_to_deg(v.turret.yaw_rate)
	v.modules.server_reset()
	var whole := rad_to_deg(v.turret.yaw_rate)
	check(_near(base, 40.0, 0.01) and _near(damaged.x, 20.0, 0.01) and _near(damaged.y, 12.5, 0.01) and _near(manual, 6.0, 0.01) and _near(whole, 40.0, 0.01),
		"its drives: whole %.0f deg/s; damaged traverse %.0f and elevation %.1f (x0.5); traverse destroyed, by hand %.0f; repaired %.0f" % [base, damaged.x, damaged.y, manual, whole])
	v.modules.server_set("engine", 0.0)
	await _physics(2)
	var on_battery := rad_to_deg(v.turret.yaw_rate)
	v.weapons._engine_out_s = VehicleWeapons.BATTERY_TURRET_S + 1.0
	await _physics(2)
	var flat := rad_to_deg(v.turret.yaw_rate)
	v.modules.server_reset()
	await _physics(2)
	check(_near(on_battery, 40.0, 0.01) and _near(flat, 6.0, 0.01) and _near(rad_to_deg(v.turret.yaw_rate), 40.0, 0.01),
		"the engine dead: on batteries the turret turns at %.0f, after %d s by hand at %.0f; the engine back, %.0f" % [on_battery, int(VehicleWeapons.BATTERY_TURRET_S), flat, rad_to_deg(v.turret.yaw_rate)])
	# The turret's seats go round with it.
	var crew := await _crew(v, [2])
	var before := v.seat_eye_point(2)
	v.turret.aim(PI / 2.0, 0.0)
	v.turret.settle()
	await _physics(2)
	check(v.turns_with_turret(2) and v.turns_with_turret(3) and not v.turns_with_turret(0) and v.seat_eye_point(2).distance_to(before) > 0.5
		and crew[0].global_position.distance_to(v.global_transform * v.turret.carry(VehicleSpecs.vec(v.spec.seats[2].at) - Vector3(0, Vehicle.seat_eye("sit"), 0))) < 0.3,
		"the commander's and loader's seats turn with the turret (the commander moved %.1f m), the driver's doesn't" % v.seat_eye_point(2).distance_to(before))
	await _clear(v, crew)


func _test_seats() -> void:
	print("Commander and loader seats, timed seat moves (2.5.3)")
	var v := await _spawn("abrams", Vector3(-80, RIG_Y, 60), 0.0)
	var ai: Array[Soldier] = []
	for i in 4:
		ai.append(_soldier("Seat%d" % i, &"friendly", v.global_position + Vector3(4, 0, i)))
	await get_tree().physics_frame
	var seats: Array = []
	for s: Soldier in ai:
		v.server_enter(s)
		seats.append(v.seat_of(s))
	check(seats == [2, 3, 1, 0], "AI board as before: commander, loader, gunner, driver (%s)" % [seats])
	var loader := ai[1]
	v.server_exit(ai[2])  # the gunner's seat free
	await _physics(2)
	check(v.switch_time(3, 1) == 3.0 and v.server_switch(loader, 1) and v.seat_of(loader) == 3 and v.moving_seat(loader),
		"the loader moves to the gunner's seat: 3 s within the turret, still in his own meanwhile")
	await _seconds(3.3)
	check(v.seat_of(loader) == 1 and not v.moving_seat(loader), "and he's on the gun after 3 s")
	v.server_exit(ai[3])  # the driver's seat free
	v.turret.aim(PI / 2.0, 0.0)
	v.turret.settle()
	check(not v.server_switch(loader, 0) and v.seat_of(loader) == 1, "turret to the driver's hatch: refused with the turret off the front")
	v.turret.aim(0.0, 0.0)
	v.turret.settle()
	check(v.switch_time(1, 0) == 10.0 and v.server_switch(loader, 0) and v.move_of(loader).y > 9.0, "turret to the driver's hatch with it to the front: 10 s")
	v._moving[loader.get_instance_id()].at = Soldier._now()
	await _physics(2)
	check(v.seat_of(loader) == 0, "and he's driving")
	await _clear(v, ai)
	var ifv := await _spawn("bradley", Vector3(-100, RIG_Y, 60), 0.0)
	var dismount := _soldier("Dismount", &"friendly", ifv.global_position + Vector3(4, 0, 0))
	await get_tree().physics_frame
	ifv.server_enter(dismount, 4)
	check(ifv.switch_time(4, 2) == 6.0 and ifv.switch_time(4, 5) == 0.0 and ifv.is_rider(4) and not ifv.is_rider(2),
		"the Bradley: a dismount to the commander's seat 6 s, to another troop seat at once")
	await _clear(ifv, [dismount])


# --- The loader --------------------------------------------------------------------------------

func _test_loader() -> void:
	print("The loader: the M256's cycle (2.7.3)")
	var v := await _spawn("abrams", Vector3(-120, RIG_Y, 60), 0.0)
	var crew := await _crew(v, [1, 2, 3])
	var gunner: Soldier = crew[0]
	var commander: Soldier = crew[1]
	var loader: Soldier = crew[2]
	SquadAI.of(loader).combat = 1.0
	var w := v.weapons
	v.turret.aim(0.0, deg_to_rad(15.0))  # into the sky
	v.turret.settle()
	check(w.loaded("main") == "m829a3" and w.rack_total("ammo_rack_bustle") == 33 and v.modules.rounds[v.modules.index_of("ammo_rack_bustle")] == 33,
		"battlecarry: a sabot in the breech, 33 left in the bustle (the module's count the same)")
	var r := w.server_fire(gunner, "main")
	var st: Dictionary = w.state.main
	var empty := w.loaded("main") == ""
	await _physics(2)
	check(bool(r.ok) and empty and String(st.cy) == "load" and _near(float(st.end) - float(st.t0), 5.0, 0.01) and w.doors_open("ammo_rack_bustle"),
		"fired: the skilled loader pulls the next sabot (the bustle doors open) to load it in %.1f s (5)" % (float(st.end) - float(st.t0)))
	await _until(func() -> bool: return w.loaded("main") != "", 8.0)
	var took := Soldier._now() - float(st.t0)
	var t0 := 0.0
	check(w.loaded("main") == "m829a3" and _near(took, 5.0, 0.08) and not w.doors_open("ammo_rack_bustle") and w.rack_total("ammo_rack_bustle") == 32,
		"up in %.1f s; the doors shut after the pull" % took)
	SquadAI.of(loader).combat = 0.0
	v.modules.server_set("breech", 0.4)
	w.server_fire(gunner, "main")
	await _physics(2)
	check(String(st.cy) == "load" and _near(float(st.end) - float(st.t0), 9.0, 0.01), "an unskilled loader with a damaged breech: %.1f s (6 x 1.5)" % (float(st.end) - float(st.t0)))
	v.modules.server_reset()
	st.end = Soldier._now()
	await _until(func() -> bool: return w.loaded("main") != "", 2.0)
	check(w.can_fire(commander, "main") == "" and bool(w.server_fire(commander, "main").ok), "the commander fires the main gun from his seat (the override)")
	# Short-crewed: no loader, then no commander either.
	v.server_exit(loader)
	await _until(func() -> bool: return String(st.cy) == "short", 2.0)
	check(String(st.cy) == "short" and int(st.by) == 2 and _near(float(st.end) - float(st.t0), 15.0, 0.01) and v.server_fire_gun(gunner, -v.global_basis.z).size() > 0,
		"no loader: the commander loads (15 s, off his sight), the gunner keeps the coax")
	v.server_exit(commander)
	await _physics(4)
	check(String(st.cy) == "short" and int(st.by) == 1 and v.server_fire_gun(gunner, -v.global_basis.z).is_empty() and w.can_fire(gunner, "main") != "",
		"the commander gone too: his round goes back and the gunner loads it himself, off his sight (no coax meanwhile)")
	st.end = Soldier._now()
	await _physics(3)
	# A player loader: the three steps on his key, the ram window.
	check(v.server_enter(player, 3), "a player takes the loader's seat")
	await _physics(2)
	w.server_fire(gunner, "main")
	await _physics(2)
	check(w.loaded("main") == "" and String(st.cy) == "", "the gun empties and waits for the player loader's key")
	check(w.server_load_press(player) == "started" and w.doors_open("ammo_rack_bustle") and w.server_load_press(player) == "early"
		and _near(float(st.end) - float(st.t0), 6.5, 0.01), "his key: he pulls a round; rammed too early: the slow load, 6.5 s")
	st.end = Soldier._now()
	await _physics(2)
	w.server_fire(gunner, "main")
	await _physics(2)
	w.server_load_press(player)
	await _until(func() -> bool: return Soldier._now() >= float(st.w0) + 0.1, 4.0)
	var how := w.server_load_press(player)
	t0 = float(st.t0)
	await _until(func() -> bool: return w.loaded("main") != "", 6.0)
	check(how == "rammed" and _near(float(st.end) - t0, 4.5, 0.01) and _near(Soldier._now() - t0, 4.5, 0.08),
		"in the ram window: %s, loaded in %.2f s (4.5)" % [how, Soldier._now() - t0])
	# Changing rounds: the next one is HEAT; the sabot stays until fired or unloaded.
	check(w.server_select_ammo("main", "m830a1") and w.loaded("main") == "m829a3", "HEAT next: the sabot in the breech stays")
	check(w.server_unload(player) and String(st.cy) == "unload" and _near(float(st.end) - float(st.t0), 8.0, 0.01), "unloading takes 8 s")
	st.end = Soldier._now()
	await _physics(2)
	w.server_load_press(player)
	check(String(st.am) == "m830a1", "the sabot back in the bustle, he pulls a HEAT round")
	st.end = Soldier._now()
	await _physics(2)
	v.server_exit(player)
	player.set_physics_process(false)
	# Restocking from the hull: the bustle down to 5, the AI loader between fights.
	var ai_loader := _soldier("Loader2", &"friendly", v.global_position + Vector3(4, 0, 0))
	await get_tree().physics_frame
	v.server_enter(ai_loader, 3)
	w.racks.ammo_rack_bustle = {"m829a3": 5, "m830a1": 0, "m1147": 0}
	w._sync_rack("ammo_rack_bustle")
	w._last_contact = -INF
	v.turret.aim(PI / 2.0, 0.0)
	v.turret.settle()
	await _physics(3)
	check(String(st.cy) == "", "no restock with the turret off the front")
	v.turret.aim(0.0, 0.0)
	v.turret.settle()
	await _physics(3)
	check(String(st.cy) == "restock" and _near(float(st.end) - float(st.t0), 12.0, 0.01) and w.rack_total("ammo_rack_hull") == 5,
		"turret to the front and quiet: he restocks the bustle from the hull, %s, 12 s a round" % VehicleWeapons.short_name(String(st.am)))
	st.end = Soldier._now()
	await _physics(2)
	check(w.rack_total("ammo_rack_bustle") == 6 or String(st.cy) == "restock", "one more in the bustle (%d)" % w.rack_total("ammo_rack_bustle"))
	await _clear(v, crew + [ai_loader])


## The bustle's blast doors (2.10.2): a detonation while the loader has them open is catastrophic;
## shut, the blow-out panels vent it.
func _test_doors() -> void:
	print("The bustle's doors and the catastrophic rule")
	var v := await _spawn("abrams", Vector3(-140, RIG_Y, 60), 0.0)
	var crew := await _crew(v, [1, 2, 3])
	v.turret.aim(0.0, deg_to_rad(15.0))
	v.turret.settle()
	v.set_meta(&"force_detonate", true)
	v.weapons.server_fire(crew[0], "main")
	await _physics(2)
	check(v.weapons.doors_open("ammo_rack_bustle"), "fired: the loader has the doors open")
	_hit(v, "pg7v", Vector3(2.7, 2.0, 3.2), Vector3(-1, 0, 0))
	await _until(func() -> bool: return v.wrecked, 3.0)
	check(v.wrecked and bool(v.modules.flags.get("doors_open", false)) and v.modules.kill_state().catastrophic,
		"a PG-7V into the bustle with the doors open: it goes up (catastrophic), no venting")
	await _clear(v, crew)
	var v2 := await _spawn("abrams", Vector3(-160, RIG_Y, 60), 0.0)
	var crew2 := await _crew(v2, [1, 2, 3])
	v2.set_meta(&"force_detonate", true)
	check(not v2.weapons.doors_open("ammo_rack_bustle"), "loaded, the doors are shut")
	_hit(v2, "pg7v", Vector3(2.7, 2.0, 3.2), Vector3(-1, 0, 0))
	await _physics(3)
	check(not v2.wrecked and bool(v2.modules.flags.get("vented", false)) and v2.weapons.rack_total("ammo_rack_bustle") == 0 and v2.weapons.loaded("main") == "m829a3",
		"the same hit with the doors shut: it vents through the blow-out panels, the bustle's rounds gone, the one in the breech still there")
	await _clear(v2, crew2)


# --- The Bradley's dual feed --------------------------------------------------------------------

func _test_feed() -> void:
	print("The M242's dual feed, rates and ready boxes (2.7.3)")
	var v := await _spawn("bradley", Vector3(-180, RIG_Y, 60), 0.0)
	var crew := await _crew(v, [1, 2, 3])
	var w := v.weapons
	v.turret.aim(0.0, deg_to_rad(20.0))
	v.turret.settle()
	var r := w.server_fire(crew[0], "main")
	check(bool(r.ok) and String(r.round) == "m791" and w.ready_of(w.mount("main"), "m791") == 69, "the AP feed: an M791, 69 left in its box")
	check(w.server_switch_feed() == "he" and w.can_fire(crew[0], "main") == "Switching feed", "switching to HE: no fire for 1.5 s")
	await _seconds(VehicleWeapons.FEED_SWITCH_S + 0.1)
	r = w.server_fire(crew[0], "main")
	check(bool(r.ok) and String(r.round) == "m792" and w.ready_of(w.mount("main"), "m792") == 229, "then M792 HEI, 229 left")
	w.server_set_rate("single")
	w._next.erase("main")
	var one := bool(w.server_fire(crew[0], "main").ok)
	var two := w.server_fire(crew[0], "main")
	await _seconds(0.3)
	check(one and not bool(two.ok) and String(two.why) == "Cycling" and bool(w.server_fire(crew[0], "main").ok), "single shot: one round a pull")
	w.server_set_rate("high")
	w._next.erase("main")
	var fired := 0
	var t0 := Soldier._now()
	while Soldier._now() - t0 < 1.0:
		if bool(w.server_fire(crew[0], "main").ok):
			fired += 1
		await get_tree().physics_frame
	check(fired >= 3 and fired <= 4, "high rate: %d rounds in a second (200 rpm)" % fired)
	# The AP box empty: the gunner and a dismount refill both boxes from the hull.
	w.racks.ready_25.m791 = 0
	w._sync_rack("ready_25")
	w._last_contact = -INF
	await _physics(3)
	var st: Dictionary = w.state.main
	check(float(st.rf) > Soldier._now() + VehicleWeapons.REFILL_S - 2.0 and int(st.rb) == 3 and w.can_fire(crew[0], "main") != "",
		"out of AP, stopped and quiet: the refill starts (120 s, the dismount in seat 3 helping)")
	st.rf = Soldier._now()
	await _physics(2)
	check(w.ready_of(w.mount("main"), "m791") == 70 and int(w.rack_contents("rack_25").m791) == 130, "both boxes full again: 70 AP, the stowage down to 130 AP")
	check(w._feed_shell(w.mount("main"), "ap") == "m791", "without the M919 package the AP feed is M791")
	v.set_meta(ArmourModel.META_PACKAGES, ["m919"])
	w.racks.ready_25.m919 = 10
	check(w._feed_shell(w.mount("main"), "ap") == "m919", "with it, and M919 in the box, the AP feed takes M919")
	v.remove_meta(ArmourModel.META_PACKAGES)
	await _clear(v, crew)


# --- Against armour and people (ArmourModel, Warheads) ----------------------------------------------

func _test_armour() -> void:
	print("Every round flown 500 m into armour through ArmourModel (A1/A2)")
	var mbt := await _spawn("abrams", Vector3(0, RIG_Y, 300), 0.0)
	var mbt_crew := await _crew(mbt, [1, 2, 3])
	SquadAI.of(mbt_crew[2]).combat = 1.0
	var ifv := await _spawn("bradley", Vector3(20, RIG_Y, 300), 0.0)
	var ifv_crew := await _crew(ifv, [1, 2])
	var side := await _spawn("bradley", Vector3(0, RIG_Y, -200), 90.0, &"hostile")
	var front := await _spawn("bradley", Vector3(20, RIG_Y, -200), 180.0, &"hostile")
	var heavy := await _spawn("abrams", Vector3(40, RIG_Y, -200), 180.0, &"hostile")
	for t: Vehicle in [side, front, heavy]:
		t.damage_mult = 0.0001  # (never wrecked: every round meets the same armour)
	# M829A3 into the Bradley's side, and into the Abrams' turret front.
	var r := await _shoot(mbt, mbt_crew[0], "main", side, Vector3(-1.8, 1.3, 0.5), "m829a3")
	_armour_check(r, side, "m829a3", ["pen"], "M829A3 APFSDS through a Bradley's side (KE 3)")
	var pen := float((r.get("result", {}) as Dictionary).get("armour", {}).get("pen", 0.0))
	check(absf(pen - Shells.pen_ke(Shells.shell(&"m829a3"), float(r.get("flown", 0.0)))) < 1.0 and _near(float(r.get("flown", 0.0)), RANGE_M, 0.03),
		"its penetration read at the range it flew: %.0f mm at %.0f m" % [pen, float(r.get("flown", 0.0))])
	await _until(func() -> bool: return mbt.weapons.loaded("main") != "", 8.0)
	r = await _shoot(mbt, mbt_crew[0], "main", heavy, Vector3(0.9, 2.0, -1.7), "m829a3")
	_armour_check(r, heavy, "m829a3", ["non_pen", "shatter"], "M829A3 stopped by an Abrams' turret front (above STANAG KE 6)")
	# M830A1 HEAT-MP into the Bradley's side.
	mbt.weapons.server_select_ammo("main", "m830a1")
	await _until(func() -> bool: return mbt.weapons.loaded("main") == "m830a1", 8.0)
	if mbt.weapons.loaded("main") != "m830a1":
		await _until(func() -> bool: return mbt.weapons.loaded("main") != "", 8.0)
		mbt.weapons.server_fire(mbt_crew[0], "main")
		await _until(func() -> bool: return mbt.weapons.loaded("main") == "m830a1", 8.0)
	r = await _shoot(mbt, mbt_crew[0], "main", side, Vector3(-1.8, 1.3, -0.5), "m830a1")
	_armour_check(r, side, "m830a1", ["pen"], "M830A1 HEAT-MP through a Bradley's side, its tiles or not (600 mm)")
	# The 25 mm's M791 (STANAG KE 5's threat): through the Bradley's front (rated KE 4), not the Abrams' (KE 6).
	r = await _shoot(ifv, ifv_crew[0], "main", front, Vector3(0.4, 1.0, -3.25), "m791")
	_armour_check(r, front, "m791", ["pen"], "M791 APDS (STANAG KE 5's round) through a Bradley's front (rated KE 4) at 500 m")
	await _seconds(0.7)
	r = await _shoot(ifv, ifv_crew[0], "main", heavy, Vector3(-0.6, 1.2, -3.0), "m791")
	_armour_check(r, heavy, "m791", ["non_pen", "shatter", "ricochet"], "M791 stopped by an Abrams' hull front (rated KE 6)")
	# M792 HEI on the Bradley's side: bursts on the outside.
	ifv.weapons.server_switch_feed()
	await _seconds(VehicleWeapons.FEED_SWITCH_S + 0.1)
	r = await _shoot(ifv, ifv_crew[0], "main", side, Vector3(-1.8, 1.3, 1.5), "m792")
	_armour_check(r, side, "m792", ["non_pen", "fuzed_outside"], "M792 HEI bursts on a Bradley's side, not through it")
	await _clear(mbt, mbt_crew)
	await _clear(ifv, ifv_crew)
	for t: Vehicle in [side, front, heavy]:
		t.queue_free()
	await _physics(2)


func _armour_check(r: Dictionary, target: Vehicle, shell: String, outcomes: Array, what: String) -> void:
	var res: Dictionary = r.get("result", {})
	var armour: Dictionary = res.get("armour", {})
	check(String(r.get("how", "")) == "vehicle" and r.get("vehicle") == target and String(armour.get("shell", "")) == shell and String(r.get("outcome", "")) in outcomes,
		"%s: %s on %s (%s, pen %.0f against %.0f mm)" % [what, r.get("outcome", r.get("why", r.get("how", "?"))), armour.get("plate", "?"),
		shell, float(armour.get("pen", 0.0)), float(armour.get("t_eff", 0.0))])


func _test_people() -> void:
	print("Rounds against people (Warheads' blast, fragments and direct hits)")
	var a := _soldier("Target1", &"hostile", Vector3(30, 0.05, 50))
	var b := _soldier("Target2", &"hostile", Vector3(36, 0.05, 50))
	var c := _soldier("Target3", &"hostile", Vector3(44, 0.05, 50))
	await _seconds(0.6)
	var chest := CharacterModel.part_position(a, Vitals.CHEST)
	var from := chest + Vector3(0, 0.4, 40)
	var id := flight.server_fire(&"m792", from, (chest - from).normalized() * 1100.0, null, {})
	await _until(func() -> bool: return flight.results.has(id), 3.0)
	var r: Dictionary = flight.results.get(id, {})
	check(String(r.get("how", "")) == "body" and a.vitals.is_dead(), "M792 HEI on a man: it bursts on him, dead")
	var ground := b.global_position + Vector3(1.5, 0.0, 0.0)
	from = ground + Vector3(0, 6, 45)
	id = flight.server_fire(&"m1147", from, (ground - from).normalized() * 1410.0, null, {})
	await _until(func() -> bool: return flight.results.has(id), 3.0)
	r = flight.results.get(id, {})
	check(String(r.get("how", "")) == "world" and (b.vitals.is_dead() or not b.vitals.wound_list().is_empty()),
		"M1147 AMP bursting 1.5 m from a man: blast and fragments (%s)" % b.vitals.condition_text())
	chest = CharacterModel.part_position(c, Vitals.CHEST)
	from = chest + Vector3(0, 10, 28)  # (from above: into the ground behind him)
	id = flight.server_fire(&"m829a3", from, (chest - from).normalized() * 1555.0, null, {})
	await _until(func() -> bool: return flight.results.has(id), 3.0)
	r = flight.results.get(id, {})
	check(c.vitals.is_dead() and c in (r.get("bodies", []) as Array) and String(r.get("how", "")) != "body",
		"a sabot through a man: dead, and it flies on (%s)" % r.get("how", "?"))
	for s: Soldier in [a, b, c]:
		if is_instance_valid(s):
			s.queue_free()


# --- The TOW ------------------------------------------------------------------------------------

func _test_tow() -> void:
	print("The TOW: raise, fire, guide to the target, the wire, reload (2.7.2, 2.7.3)")
	var ifv := await _spawn("bradley", Vector3(60, RIG_Y, 300), 0.0)
	var crew := await _crew(ifv, [1, 2, 3])
	var target := await _spawn("abrams", Vector3(60, RIG_Y, -200), 180.0, &"hostile")
	target.damage_mult = 0.0001
	var w := ifv.weapons
	check(w.can_fire(crew[0], "tow") == "Launcher down" and w.server_raise(true) == "" and w.can_fire(crew[0], "tow") == "Raising the launcher",
		"down until raised: raising takes 4 s")
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.2)
	check(String(w.state.tow.p) == "up" and w.can_fire(crew[0], "tow") == "", "up")
	var aim_at := target.global_transform * Vector3(0.0, 1.2, -3.0)
	await _aim_sight(ifv, aim_at)
	var r := w.server_fire(crew[0], "tow")
	var id := int(r.get("missile", 0))
	check(bool(r.ok) and int(w.state.tow.rd) == 1 and w.can_fire(crew[0], "tow") == "Guiding a missile", "fired: one left on the launcher, the gunner guiding")
	await _until(func() -> bool: return launchers.results.has(id), 15.0)
	var res: Dictionary = launchers.results.get(id, {})
	var burst: Dictionary = res.get("burst", {})
	check(String(res.get("how", "")) == "burst" and burst.get("vehicle") == target and bool((burst.get("vehicle_result", {}) as Dictionary).get("penetrated", false))
		and not bool(res.get("wire_cut", true)),
		"guided 500 m onto the Abrams' hull front and through it (TOW-2A tandem, %.0f m flown)" % float(res.get("flown", 0.0)))
	# A fast traverse snaps the wire.
	await _physics(3)
	r = w.server_fire(crew[0], "tow")
	id = int(r.get("missile", 0))
	await _seconds(0.6)
	ifv.turret.aim(ifv.turret.yaw + 1.6, ifv.turret.pitch)
	await _until(func() -> bool: return launchers.results.has(id), 25.0)
	res = launchers.results.get(id, {})
	check(bool(r.ok) and bool(res.get("wire_cut", false)) and String(res.get("wire_why", "")) == "the turret slewed too fast"
		and (res.get("burst", {}) as Dictionary).get("vehicle") != target, "the turret slewed while it flew: the wire snaps, a miss (%s)" % res.get("wire_why", "?"))
	# Reload: launcher down, a dismount out of the roof hatch, 45 s a missile.
	check(int(w.state.tow.rd) == 0 and w.server_reload_tow(crew[2]) == "Lower the launcher first", "empty; the launcher must come down to reload")
	w.server_raise(false)
	check(w.server_reload_tow(crew[2]) == "" and _near(float(w.state.tow.rl) - Soldier._now(), VehicleWeapons.TOW_RELOAD_S, 0.02) and w.rack_total("rack_tow") == 4,
		"the dismount reloads it: 45 s, one out of the hull's rack (4 left)")
	w.state.tow.rl = Soldier._now()
	await _physics(2)
	check(int(w.state.tow.rd) == 1 and float(w.state.tow.rl) > Soldier._now() and w.rack_total("rack_tow") == 3, "one on the launcher; he starts the next")
	w.server_raise(true)
	await _physics(2)
	check(float(w.state.tow.rl) == 0.0 and w.rack_total("rack_tow") == 4, "raising it stops the reload: the missile goes back")
	# Moving lowers it.
	var ground := await _spawn("bradley", Vector3(-40, 0.4, 70), 180.0, &"player", false)
	var gcrew := await _crew(ground, [1, 3])
	ground.weapons.server_raise(true)
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.2)
	var was := String(ground.weapons.state.tow.p)
	ground.linear_velocity = -ground.global_basis.z * 3.0
	await _physics(2)
	check(was == "up" and String(ground.weapons.state.tow.p) == "down", "driving off (3 m/s) brings it down")
	# Smoke on the line snaps the wire.
	ground.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ground.freeze = true
	ground.linear_velocity = Vector3.ZERO
	await _physics(3)
	ground.weapons.server_raise(true)
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.2)
	var ahead := ground.global_transform * Vector3(0, 2.6, -22.0)
	level.spawn_smoke.rpc(ahead, "white", 10.0)
	await _seconds(0.6)
	var sight := ground.weapons.sight_origin()
	check(SmokeCloud.blocks(sight, sight + (ahead - sight) * 2.0), "a grown smoke cloud 22 m ahead of the launcher")
	await _aim_sight(ground, ground.global_transform * Vector3(0, 4.0, -300.0))
	r = ground.weapons.server_fire(gcrew[0], "tow")
	id = int(r.get("missile", 0))
	await _until(func() -> bool: return launchers.results.has(id), 25.0)
	res = launchers.results.get(id, {})
	check(bool(r.ok) and bool(res.get("wire_cut", false)) and String(res.get("wire_why", "")) == "smoke on the line",
		"fired through it: the wire breaks, smoke on the line (%s)" % res.get("wire_why", "?"))
	await _clear(ifv, crew)
	await _clear(ground, gcrew)
	target.queue_free()
	await _physics(2)


# --- Saving -------------------------------------------------------------------------------------

func _test_save() -> void:
	print("Saved with the zone")
	var v := await _spawn("bradley", Vector3(-200, RIG_Y, 60), 0.0)
	var w := v.weapons
	w.server_switch_feed()
	w.server_set_rate("high")
	w.racks.ready_25.m791 = 41
	w._sync_rack("ready_25")
	w.state.tow.rd = 1
	var mbt := await _spawn("abrams", Vector3(-220, RIG_Y, 60), 0.0)
	mbt.weapons.state.main.l = "m1147"
	mbt.weapons.state.main.n = "m830a1"
	mbt.weapons.racks.ammo_rack_hull = {"m829a3": 1, "m830a1": 2}
	mbt.weapons._sync_rack("ammo_rack_hull")
	var copies: Array = []
	for x: Vehicle in [v, mbt]:
		var rec: Dictionary = JSON.parse_string(JSON.stringify(x.to_save()))
		rec.erase("pos")
		rec.erase("rot")
		rec.erase("bodies")
		copies.append(layer.server_spawn(x.model, Transform3D(Basis(), x.global_position + Vector3(0, 0, 15)), "", &"player", "%s_copy%d" % [x.vehicle_id, _n], rec))
		_n += 1
	for c: Vehicle in copies:
		c.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		c.freeze = true
	await _physics(3)
	var bw: VehicleWeapons = copies[0].weapons
	var aw: VehicleWeapons = copies[1].weapons
	check(String(bw.state.main.f) == "he" and String(bw.state.main.r) == "high" and int(bw.rack_contents("ready_25").m791) == 41 and int(bw.state.tow.rd) == 1
		and int(copies[0].modules.rounds[copies[0].modules.index_of("ready_25")]) == 41 + 230,
		"the Bradley comes back on its HE feed at high rate, 41 AP in the box, one TOW on the launcher")
	check(aw.loaded("main") == "m1147" and String(aw.state.main.n) == "m830a1" and aw.rack_contents("ammo_rack_hull") == {"m829a3": 1, "m830a1": 2},
		"the Abrams with its AMP in the breech, HEAT next, the hull rack as it was")
	for x: Vehicle in [v, mbt] + copies:
		x.queue_free()
	await _physics(2)


# --- Budgets ------------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Budgets (Proposed)")
	var origin := Vector3(800, 400, 800)
	var best := INF
	for batch in 3:
		for i in 50:
			var a := TAU * float(i) / 50.0
			flight.server_fire(&"m829a3", origin, Vector3(cos(a), 0.6, sin(a)).normalized() * 1555.0, null, {})
		var times: Array = []
		for f in 20:
			await get_tree().physics_frame
			if flight.shells.size() >= 50:
				times.append(flight.last_step_ms)
		times.sort()
		if not times.is_empty():
			best = minf(best, float(times[times.size() / 2]))
		flight.shells.clear()  # (into the empty sky: no need to wait for them to be lost)
	check(best < FLIGHT_BUDGET_MS, "50 shells in flight: %.3f ms a physics step on the host (budget %.1f ms)" % [best, FLIGHT_BUDGET_MS])
	var v := await _spawn("bradley", Vector3(-240, RIG_Y, 60), 0.0)
	var crew := await _crew(v, [1])
	v.turret.aim(0.0, deg_to_rad(30.0))
	v.turret.settle()
	var shots: Array = []
	for i in 30:
		v.weapons._next.erase("main")
		var t0 := Time.get_ticks_usec()
		v.weapons.server_fire(crew[0], "main")
		shots.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().physics_frame
	shots.sort()
	var median := float(shots[shots.size() / 2])
	check(median < SHOT_BUDGET_MS, "a 25 mm shot fired (checks, rack, ShellFlight, sound): %.3f ms (budget %.1f ms)" % [median, SHOT_BUDGET_MS])
	await _clear(v, crew)


# --- Replication ----------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	var ifv := await _spawn("bradley", Vector3(-30, RIG_Y, -60), 0.0)
	var w := ifv.weapons
	w.server_switch_feed()
	w.server_set_rate("single")
	w.racks.ready_25.m791 = 50
	w._sync_rack("ready_25")
	w.server_raise(true)
	var mbt := await _spawn("abrams", Vector3(-50, RIG_Y, -60), 0.0)
	mbt.weapons.state.main.l = "m830a1"
	mbt.weapons.state.main.n = "m1147"
	mbt.turret.aim(1.0, 0.1)
	mbt.turret.settle()
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.3)
	w._publish()
	mbt.weapons._publish()
	expect = {"ifv": String(ifv.vehicle_id), "mbt": String(mbt.vehicle_id), "ifv_state": w.net_state.duplicate(true), "mbt_state": mbt.weapons.net_state.duplicate(true),
		"yaw": mbt.turret.yaw}
	var log_path := OS.get_user_data_dir().path_join("maingun_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/maingun_test.tscn", "--", "--maingun-join"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_ready, 150.0)
	check(_client_ready, "the client checked the guns it found on joining")
	if _client_ready:
		mbt.turret.aim(0.0, deg_to_rad(10.0))
		mbt.turret.settle()
		var crew := await _crew(mbt, [1])
		var r := mbt.weapons.server_fire(crew[0], "main")
		_live_fired.rpc(int(r.get("shell", 0)))
	await _until(func() -> bool: return _client_failures >= 0, 45.0)
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


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_live() -> void:
	_client_ready = true


@rpc("authority", "call_remote", "reliable")
func _live_fired(id: int) -> void:
	expect["live"] = id


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(220.0).timeout.connect(func() -> void: get_tree().quit(99))
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
		flight = ShellFlight.of(level)
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.ifv)) != null and find.call(String(expect.mbt)) != null, 30.0)
		var ifv: Vehicle = find.call(String(expect.ifv))
		var mbt: Vehicle = find.call(String(expect.mbt))
		await _until(func() -> bool: return ifv != null and mbt != null and not ifv.weapons.net_state.is_empty() and mbt.weapons.net_state.get("m", {}).get("main", {}).get("l", "") == "m830a1", 20.0)
		var same := func(a: Dictionary, b: Dictionary) -> bool: return JSON.stringify(a.get("m", {})) == JSON.stringify(b.get("m", {})) and JSON.stringify(a.get("r", {})) == JSON.stringify(b.get("r", {}))
		note.call(ifv != null and same.call(ifv.weapons.net_state, expect.ifv_state) and String(ifv.weapons._view("main").get("f", "")) == "he"
			and String(ifv.weapons._view("tow").get("p", "")) == "up" and int(ifv.weapons.rack_contents("ready_25").get("m791", -1)) == 50,
			"the Bradley as the host has it: HE feed, single shots, 50 AP in the box, the TOW up (late join)")
		note.call(mbt != null and same.call(mbt.weapons.net_state, expect.mbt_state) and mbt.weapons.loaded("main") == "m830a1" and mbt.turret != null
			and absf(wrapf(mbt.turret.yaw - float(expect.yaw), -PI, PI)) < 0.05,
			"the Abrams as the host has it: HEAT-MP in the breech, AMP next, its turret turned")
		note.call(mbt != null and mbt.readout_parts(1).any(func(p: Dictionary) -> bool: return String(p.text).contains("HEAT up")),
			"the gunner's readout here says what's loaded")
		var seen := [0]
		var watch := func() -> void: seen[0] = maxi(seen[0], flight.drawn_count())
		get_tree().process_frame.connect(watch)
		_ready_for_live.rpc_id(1)
		await _until(func() -> bool: return expect.has("live") and seen[0] > 0, 20.0)
		await _until(func() -> bool: return flight.drawn_count() == 0, 10.0)
		get_tree().process_frame.disconnect(watch)
		note.call(seen[0] > 0 and flight.drawn_count() == 0, "the host's 120 mm round flew here and ended")
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

## A vehicle of `model` at `pos` facing -z turned `yaw` degrees: frozen where it is (the air rigs),
## or settling on its springs.
func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player", frozen := true) -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos), "", faction, "mg_%s_%d" % [model, _n])
	if frozen:
		v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		v.freeze = true
	v.server_rearm()  # (a player-side vehicle comes from the motor pool with its belts: MotorPool rearms it)
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(0.3 if frozen else 1.5)
	return v


## AI soldiers in `seats` of `v` (their brains off), seated.
func _crew(v: Vehicle, seats: Array) -> Array:
	var out: Array = []
	for seat: int in seats:
		var s := _soldier("%s%d_%d" % [v.model.capitalize(), seat, _n], &"friendly", v.global_position + Vector3(4.0, 0.0, float(seat)))
		await get_tree().physics_frame
		v.server_enter(s, seat)
		out.append(s)
		_n += 1
	await _seconds(0.5)
	return out


func _soldier(callsign: String, faction: StringName, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


## Lays `v`'s gun so mount `mount`'s round of `shell` hits `point` (held over for its drop).
func _aim(v: Vehicle, mount: String, point: Vector3, shell: String) -> void:
	for i in 4:
		var from := v.weapons.muzzle(mount)
		var to := point + Vector3.UP * float(ShellFlight.flight_to(StringName(shell), from.distance_to(point)).drop)
		v.server_aim(to - from)
		v.turret.settle()
	await _physics(3)


## Lays the gunner's sight on `point` (the TOW's line).
func _aim_sight(v: Vehicle, point: Vector3) -> void:
	for i in 4:
		v.server_aim(point - v.weapons.sight_origin())
		v.turret.settle()
	await _physics(3)


## `v`'s `mount` fired by `s` at `target`'s point `local` (its frame) with `shell`: ShellFlight's result.
func _shoot(v: Vehicle, s: Soldier, mount: String, target: Vehicle, local: Vector3, shell: String) -> Dictionary:
	await _aim(v, mount, target.global_transform * local, shell)
	var r := v.weapons.server_fire(s, mount)
	if not bool(r.ok):
		return {"why": r.why}
	var id := int(r.get("shell", 0))
	await _until(func() -> bool: return flight.results.has(id), 5.0)
	return flight.results.get(id, {"why": "no result"})


## Shell or warhead `id` into `v` at `local` (its frame) along `ldir`, the tiles missed.
func _hit(v: Vehicle, id: String, local: Vector3, ldir: Vector3) -> Dictionary:
	var w := Warheads.data(StringName(id))
	var hit := {"position": v.global_transform * local, "direction": (v.global_basis * ldir).normalized(), "shooter": null, "probe_m": 1.5,
		"force": {"coverage": false, "ricochet": false}}
	if w.is_empty():
		hit.merge({"kind": Vehicle.KINETIC, "shell": id})
	else:
		hit.merge({"kind": Warheads.kind_of(StringName(id)), "warhead": id, "penetration_mm": float(w.get("penetration_mm", 0.0)), "blast_kg": float(w.get("blast_kg", 0.0))})
	return v.server_take_hit(hit)


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
	await _physics(2)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
