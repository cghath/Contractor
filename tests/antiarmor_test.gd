extends Node
## Headless checks for wave 5's anti-armour launchers (V2) in the real compound: the launcher
## and round data, the launcher slot; every round type against a stub vehicle (HEAT with its
## penetration in mm, a hit it doesn't stop going on into the crew, top attack on the roof),
## against the concrete wall (hole size by kind) and against people (fragments, overpressure,
## a direct hit, a thermobaric round in a room); arming distance; the backblast behind and
## not in front, and off a wall behind the shooter; the Javelin's lock and its climb and dive;
## the NLAW's overfly; the same rounds against V1's real vehicles (zones, armour, hull voxels,
## crews and spall, fire and wrecks, a rocket through an open bed flying on); reloading; an AI
## hostile firing an RPG-7 at a real vehicle and at a group behind cover but never at a lone
## soldier; then a second process joins over ENet and checks the craters made before it came
## (late join), a round's flight and burst, and its own shot.
##   <voxel godot exe> --headless --path . res://tests/antiarmor_test.tscn
## The host starts the client itself (same scene, "-- --join 127.0.0.1"). Exits with the
## number of failures.

const SLOT := Launchers.SLOT

var failures := 0
var level: CompoundLevel
var world: VoxelWorld
var launchers: Launchers
var player: Soldier
## Host -> client, on join: what to check.
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _client_fired := false


## A vehicle for V2's tests until V1's lands: a box on the vehicles layer that keeps the hits
## it gets (Vehicle.server_take_hit's API) and lets through a jet with more than armor_mm.
class StubVehicle extends Vehicle:
	var hits: Array = []
	var armor_mm := 300.0
	var crew: Array = []
	var size := Vector3(5.0, 2.0, 2.4)  # length along x, height, width

	func _ready() -> void:
		add_to_group(GROUP)
		collision_layer = LAYER
		collision_mask = 0
		freeze = true
		set_physics_process(false)
		set_process(false)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y * 0.5
		add_child(shape)

	func server_take_hit(hit: Dictionary) -> Dictionary:
		hits.append(hit)
		var through := float(hit.get("penetration_mm", 0.0)) > armor_mm
		damaged.emit(ZONE_CREW if through else ZONE_HULL, hit)
		return {"stopped": not through, "zone": ZONE_CREW if through else ZONE_HULL, "penetrated": through}

	func occupants() -> Array:
		return crew

	func last() -> Dictionary:
		return hits.back() if not hits.is_empty() else {}


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_antiarmor" + tag  # never touch a real save
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--antiarmor-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("ANTIARMOR TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	# The tests move the player well outside the compound (vehicles at 60 m and more). Voxel
	# blocks only stay loaded near a viewer, and the compound's structures are edits that go
	# when their blocks unload; in play somebody is always in it. Keep a viewer at its middle.
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	world = level.voxel_world
	launchers = Launchers.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	await _wait_for_collision()
	if _want("data"):
		_test_data()
	await _test_slot()
	if _want("stub"):
		await _test_vehicles()
		await _test_crew()
		await _test_javelin()
		await _test_nlaw()
	if _want("real"):
		await _test_real_vehicles()
	if _want("world"):
		await _test_structures()
		await _test_arming()
		await _test_people()
		await _test_backblast()
		await _test_reload()
	if _want("ai"):
		await _test_ai()
	if _want("client"):
		await _test_client()
	GameState.delete_save()
	print("ANTIARMOR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_ANTIARMOR_ONLY="real,ai" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_ANTIARMOR_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The walls' collision comes a few frames after the voxels.
func _wait_for_collision() -> void:
	var lines := [[Vector3(12, 1.2, -18), Vector3(12, 1.2, -21)], [Vector3(6, 1.2, -18), Vector3(6, 1.2, -21)],
		[Vector3(-9, 1.2, -18), Vector3(-9, 1.2, -21)], [Vector3(-15, 1.2, -18), Vector3(-15, 1.2, -21)],
		[Vector3(14.5, 1.2, -18), Vector3(14.5, 1.2, -21)], [Vector3(17.5, 1.0, -12), Vector3(17.5, 1.0, -10)]]
	var deadline := Time.get_ticks_msec() + 15000
	var space := player.get_world_3d()
	while lines.any(func(l: Array) -> bool: return Throwables.clear_line(space, l[0], l[1])) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


# --- Data -----------------------------------------------------------------------------------

func _test_data() -> void:
	print("Launchers and rounds")
	var launcher_ids: Array[StringName] = [&"at4", &"rpg7", &"javelin_clu", &"maaws", &"nlaw", &"smaw"]
	var sound := true
	for id in launcher_ids:
		var item := ItemDB.get_item(id)
		sound = sound and item != null and item.type == "launcher" and item.slot == SLOT and item.stats.has("backblast")
		if item and item.stats.get("disposable", false):
			sound = sound and not Warheads.data(item.stats.loaded).is_empty()
		elif item:
			sound = sound and not Launchers.round_items(item).is_empty() and float(item.stats.get("reload_s", 0.0)) > 0.0
			for w: String in item.stats.get("accepts", []):
				sound = sound and not Warheads.data(w).is_empty()
	check(sound, "six launchers, each with its round(s), a reload time or a single shot, and a backblast")
	check(Launchers.round_items(ItemDB.get_item(&"rpg7")) == [&"pg7v_round", &"og7v_round"]
		and Launchers.round_items(ItemDB.get_item(&"maaws")).size() == 3 and Launchers.round_items(ItemDB.get_item(&"smaw")).size() == 2,
		"the RPG-7 takes PG-7V and OG-7V, the MAAWS HEAT, HE and HEDP, the SMAW HEDP and thermobaric")
	var at4 := ItemDB.get_item(&"at4")
	var nlaw := ItemDB.get_item(&"nlaw")
	check(is_equal_approx(at4.mass_kg, 6.7) and is_equal_approx(float(at4.stats.size_m[2]), 1.02) and int(at4.stats.calibre_mm) == 84
		and is_equal_approx(nlaw.mass_kg, 12.5) and is_equal_approx(ItemDB.get_item(&"javelin_clu").mass_kg + ItemDB.get_item(&"javelin_missile").mass_kg, 22.3),
		"real masses, lengths and calibres (AT4 6.7 kg, 1.02 m, 84 mm; NLAW 12.5 kg; Javelin 22.3 kg with its missile)")
	var pen := func(w: String) -> float: return float(Warheads.data(w).penetration_mm)
	check(pen.call("pg7v") >= 260 and pen.call("pg7v") <= 300 and pen.call("at4_heat") >= 400 and pen.call("at4_heat") <= 420
		and pen.call("javelin") >= 600 and pen.call("javelin") <= 800 and is_equal_approx(pen.call("nlaw"), 500.0)
		and pen.call("ffv551") >= 400 and pen.call("ffv551") <= 500,
		"penetration by round: PG-7V %d, AT4 %d, Javelin %d, NLAW %d, FFV551 %d mm RHA" % [pen.call("pg7v"), pen.call("at4_heat"), pen.call("javelin"), pen.call("nlaw"), pen.call("ffv551")])
	var kinds := {}
	for w: StringName in Warheads.ids():
		kinds[Warheads.kind_of(w)] = true
		var d := Warheads.data(w)
		sound = sound and float(d.arming_m) >= 5.0 and float(d.arming_m) <= 25.0 and float(d.speed_mps) > 0.0 and float(d.max_s) > 0.0
	check(kinds.has(Vehicle.HEAT) and kinds.has(Vehicle.TANDEM_HEAT) and kinds.has(Vehicle.HE) and kinds.has(Vehicle.HEDP) and kinds.has(Vehicle.THERMOBARIC)
		and sound, "every round kind (HEAT, tandem HEAT, HE, HEDP, thermobaric), each arming at 5-25 m")
	check(Prices.price_of(&"at4") == 1800 and Prices.price_of(&"nlaw") == 4000 and Prices.price_of(&"javelin_missile") == 12000
		and Prices.for_sale(&"at4") and Prices.for_sale(&"maaws"), "AT4 1800, NLAW 4000, Javelin missile 12000, in the shop")
	var rounds_ok := true
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if item.tags.has("launcher_round") and id != &"javelin_missile":
			rounds_ok = rounds_ok and Prices.price_of(id) >= 200 and Prices.price_of(id) <= 600
	check(rounds_ok, "rounds 200-600")
	check(not Prices.for_sale(&"rpg7") and not Prices.for_sale(&"pg7v_round") and Prices.price_of(&"rpg7") > 0 and Prices.price_of(&"pg7v_round") > 0,
		"the RPG-7 and its rounds are loot: sell-only")
	var counter := Node.new()
	var first_four := 0
	var armed := 0
	for i in 100:
		var kit := LauncherAI.insurgent_kit(counter)
		if not kit.is_empty():
			armed += 1
			sound = sound and kit.has(&"rpg7") and kit.has(&"pg7v_round") and kit.has(&"og7v_round")
			if i < 4:
				first_four += 1
	counter.free()
	check(armed == 20 and first_four == 0 and sound, "one insurgent in five carries an RPG-7 with PG-7V and OG-7V rounds (%d of 100); the compound's four don't" % armed)


func _test_slot() -> void:
	print("The launcher slot")
	for id: StringName in [&"m4a1", &"plate_carrier", &"ruck_45"]:
		player.inventory.take(id)
	player.inventory.take(&"at4")
	check(player.inventory.slots[SLOT] == &"at4" and Launchers.loaded_of(player) == &"at4_heat",
		"an AT4 goes in the launcher slot, its own round in it")
	check(Inventory.SLOTS.has(SLOT) and player.inventory.slots[&"primary"] != &"", "beside the rifle, not instead of it")
	player.select_weapon(SLOT)
	check(player.active_weapon() != null and player.active_weapon().id == &"at4", "key 3 brings it up (the active weapon)")
	await _seconds(0.4)
	check(player.get_node_or_null(^"LauncherRig") != null, "it's drawn on the soldier (LauncherRig)")
	player.select_weapon(&"primary")


# --- Vehicles ------------------------------------------------------------------------------

func _test_vehicles() -> void:
	print("Every round against a vehicle")
	var stub := _stub(Vector3(40, 0, 40))
	var from := Vector3(-30, 0.1, 40)
	var cases := [
		[&"at4", &"at4_heat", "", Vehicle.HEAT, 420.0],
		[&"rpg7", &"pg7v", "", Vehicle.HEAT, 260.0],
		[&"rpg7", &"og7v", "", Vehicle.HE, 0.0],
		[&"maaws", &"ffv551", "", Vehicle.HEAT, 450.0],
		[&"maaws", &"ffv441", "", Vehicle.HE, 0.0],
		[&"maaws", &"ffv502", "", Vehicle.HEDP, 150.0],
		[&"smaw", &"smaw_hedp", "", Vehicle.HEDP, 200.0],
		[&"smaw", &"smaw_ne", "", Vehicle.THERMOBARIC, 0.0],
		[&"nlaw", &"nlaw", "da", Vehicle.HEAT, 500.0],
	]
	for c: Array in cases:
		var before := stub.hits.size()
		var r := await _shot(c[0], c[1], from, Vector3(40, 1.0, 40), c[2])
		var hit := stub.last() if stub.hits.size() > before else {}
		var d := Warheads.data(c[1])
		check(stub.hits.size() == before + 1 and hit.kind == c[3] and is_equal_approx(float(hit.penetration_mm), c[4])
			and is_equal_approx(float(hit.blast_kg), float(d.blast_kg)) and hit.shooter == player and not hit.top_attack
			and absf((hit.position as Vector3).x - 37.5) < 0.3 and (hit.direction as Vector3).x > 0.9,
			"%s %s: one %s hit on the hull's face, %d mm, %.1f kg (%s)" % [c[0], c[1], c[3], c[4], float(d.blast_kg), _describe(r, hit)])
	check(stub.hits.size() == cases.size(), "and nothing else (%d hits)" % stub.hits.size())
	stub.queue_free()
	await _frames(2)


func _test_crew() -> void:
	print("HEAT that gets through goes on into the crew")
	var stub := _stub(Vector3(40, 0, 50))
	var crew := _dummy(Vector3(40, 0, 50))
	stub.crew = [crew]
	await _frames(3)
	var chest := _chest(crew)
	var from := Vector3(-10, 0.1, 50)
	var r := await _shot(&"rpg7", &"pg7v", from, chest)
	var res: Dictionary = r.get("burst", {}).get("vehicle_result", {})
	check(bool(res.get("stopped", false)) and crew.vitals.is_up() and crew.vitals.wound_list().is_empty(),
		"a PG-7V (260 mm) on 300 mm of armour is stopped: the crew is untouched (%s)" % crew.vitals.condition_text())
	r = await _shot(&"at4", &"at4_heat", from, chest)
	res = r.get("burst", {}).get("vehicle_result", {})
	check(not bool(res.get("stopped", true)) and bool(r.get("burst", {}).get("through", false)) and crew.vitals.is_dead(),
		"an AT4 (420 mm) gets through, and the jet kills the crewman in its path (%s)" % crew.vitals.condition_text())
	stub.queue_free()
	crew.queue_free()
	await _frames(2)


func _test_javelin() -> void:
	print("Javelin: lock, climb and dive")
	var stub := _stub(Vector3(60, 0, 60))
	var from := Vector3(-60, 0.1, 60)
	_arm(&"javelin_clu", &"javelin")
	_place(player, from)
	await _frames(2)
	var eye := player.camera.global_position
	var aim := Launchers.hull_box(stub).get_center()
	player._server_busy_until = 0.0
	var fired := launchers.launched
	var why := launchers.server_fire(player, eye, (aim - eye).normalized(), "top", null)
	check(why == "No lock" and launchers.launched == fired and Launchers.loaded_of(player) == &"javelin", "without a lock it doesn't fire (%s); the missile stays on the CLU" % why)
	var r := await _shot(&"javelin_clu", &"javelin", from, aim, "top", stub, false)
	var hit := stub.last()
	check(r.get("how", "") == "burst" and float(r.get("max_height", 0.0)) > 25.0 and bool(r.get("top_attack", false)) and (r.direction as Vector3).y < -0.5,
		"locked, top attack: it climbs (%.0f m) and dives onto the target (%.2f)" % [float(r.get("max_height", 0.0)), (r.get("direction", Vector3.ZERO) as Vector3).y])
	check(not hit.is_empty() and hit.kind == Vehicle.TOP_ATTACK and hit.warhead_kind == Vehicle.TANDEM_HEAT and is_equal_approx(float(hit.penetration_mm), 750.0)
		and (hit.position as Vector3).y > stub.size.y - 0.15, "a top-attack hit on the roof (y %.2f), tandem HEAT 750 mm" % ((hit.get("position", Vector3.ZERO) as Vector3).y))
	var top_height := float(r.get("max_height", 0.0))
	r = await _shot(&"javelin_clu", &"javelin", from, aim, "direct", stub, false)
	hit = stub.last()
	check(r.get("how", "") == "burst" and float(r.get("max_height", 99.0)) < top_height * 0.6 and hit.kind == Vehicle.TANDEM_HEAT and not hit.top_attack,
		"direct attack flies low (%.0f m) and hits as tandem HEAT (%s)" % [float(r.get("max_height", 0.0)), hit.get("kind", "")])
	stub.queue_free()
	await _frames(2)


func _test_nlaw() -> void:
	print("NLAW: overfly top attack")
	var stub := _stub(Vector3(60, 0, 70))
	var from := Vector3(-40, 0.1, 70)
	var before := stub.hits.size()
	var r := await _shot(&"nlaw", &"nlaw", from, Launchers.hull_box(stub).get_center(), "ota", null, false)
	var hit := stub.last() if stub.hits.size() > before else {}
	check(not hit.is_empty() and hit.kind == Vehicle.TOP_ATTACK and bool(r.get("top_attack", false)) and (hit.position as Vector3).y > stub.size.y - 0.15
		and (hit.direction as Vector3).y < -0.9, "aimed at the hull's middle, it flies over and fires down into the roof (%s)" % _describe(r, hit))
	check(player.inventory.slots[SLOT] == &"", "and the NLAW is spent")
	stub.queue_free()
	await _frames(2)


# --- V1's real vehicles --------------------------------------------------------------------

## The launchers against V1's vehicles (Vehicle via VehicleLayer.server_spawn): their zones,
## armour, hull voxels, crews, fires and wrecks.
func _test_real_vehicles() -> void:
	print("Against V1's real vehicles")
	var rolls := Vehicle.fire_rolls
	Vehicle.fire_rolls = false  # no chance fires: the wreck check makes its own
	_place(player, Vector3(-75, 0.1, -75))  # out of the way while they settle
	await _real_matv()
	await _real_abrams()
	await _real_technical()
	await _real_mrap()
	await _real_open_bed()
	Vehicle.fire_rolls = rolls
	await _frames(2)


## AT4 HEAT into an M-ATV's side, at a rider in the back: the jet goes through, wrecks the
## crew zone, holes the hull and kills the rider on its line; the commander beside him gets
## the spall, once (Vehicle._spall, not a second pass of the launcher's own).
func _real_matv() -> void:
	var matv := await _real("matv", Vector3(40, 0, 40))
	var rear := _soldier("MatvRear", &"friendly", matv.global_position + Vector3(-3, 0.1, 0), [], false)
	var cmdr := _soldier("MatvCmdr", &"friendly", matv.global_position + Vector3(3, 0.1, 0), [], false)
	await get_tree().physics_frame
	check(matv.server_enter(rear, 2) and matv.server_enter(cmdr, 1), "an M-ATV with a rider in the back left and the commander in front")
	await _seated()
	var chest := _chest(rear)
	var holes := _carves(matv, VehicleHull.HOLE)
	# The spall's parts are random: each man's first, deep fragment through the face reaches the
	# brain about one time in nine (S0037) and kills outright, recording no wound
	# (WoundModel.add_hit), which failed this check about one run in 70 (R0019: "0 wounds;
	# Dead"). A seed whose deep fragments aren't the face, whichever man the pass takes first
	# (the rider's 3 to 6 fragments before the commander's, or none), makes it repeatable.
	var spall_seed := 0
	var face := true
	while face:
		spall_seed += 1
		var r := RandomNumberGenerator.new()
		r.seed = spall_seed
		face = false
		for i in 7:
			var p := Vehicle.SPALL_PARTS[r.randi() % Vehicle.SPALL_PARTS.size()]
			face = face or (p == Vitals.FACE and i in [0, 3, 4, 5, 6])
	Vehicle.spall_rng.seed = spall_seed
	# (The tube rides 10 cm right of and below the eye: aim that much the other way to put the
	# rocket, and its jet, through his chest.)
	var r := await _shot(&"at4", &"at4_heat", Vector3(chest.x - 25.0, _ground(chest) + 0.1, chest.z), chest + Vector3(0, 0.1, -0.1))
	var b: Dictionary = r.get("burst", {})
	var res: Dictionary = b.get("vehicle_result", {})
	check(b.get("vehicle") == matv and bool(res.get("penetrated", false)) and res.get("zone") == Vehicle.ZONE_CREW
		and matv.zone_health(Vehicle.ZONE_CREW) < 1.0 and _carves(matv, VehicleHull.HOLE) > holes,
		"AT4 HEAT (420 mm) through the M-ATV's side (32 mm): the crew zone %.0f%%, a hole in the hull (%s)" % [matv.zone_health(Vehicle.ZONE_CREW) * 100.0, _describe(r, b.get("vehicle_hit", {}))])
	check(rear.vitals.is_dead(), "the jet kills the rider on its line (%s)" % rear.vitals.condition_text())
	var spall := cmdr.vitals.wound_list().size()
	Vehicle.spall_rng.randomize()
	check(spall >= 1 and spall <= SPALL_WOUNDS_MAX and not cmdr.vitals.is_dead(),
		"the commander beside him takes the spall, one pass of it (%d wounds; %s)" % [spall, cmdr.vitals.condition_text()])
	await _clear(matv, [rear, cmdr])


## PG-7V into an Abrams' front: stopped, the driver behind it unhurt. A Javelin's top attack
## on the same tank: through the turret roof.
func _real_abrams() -> void:
	var abrams := await _real("abrams", Vector3(60, 0, -60))
	var driver := _soldier("AbramsDriver", &"friendly", abrams.global_position + Vector3(-3, 0.1, 0), [], false)
	await get_tree().physics_frame
	check(abrams.server_enter(driver, 0), "an Abrams with its driver in")
	await _seated()
	var front := abrams.global_transform * Vector3(0.0, 1.0, -3.1)
	var r := await _shot(&"rpg7", &"pg7v", Vector3(front.x, _ground(front) + 0.1, front.z - 30.0), front)
	var b: Dictionary = r.get("burst", {})
	var res: Dictionary = b.get("vehicle_result", {})
	check(b.get("vehicle") == abrams and bool(res.get("stopped", false)) and not bool(res.get("penetrated", true)) and not bool(b.get("through", true)),
		"a PG-7V (260 mm) on the Abrams' front is stopped (%s, zone %s)" % [_describe(r, b.get("vehicle_hit", {})), res.get("zone", "-")])
	check(driver.vitals.is_up() and driver.vitals.wound_list().is_empty() and driver.vitals.deaf_left() == 0.0,
		"the driver behind it is unhurt, the blast outside (%s)" % driver.vitals.condition_text())
	var from := Vector3(-40, 0, -60)
	from.y = _ground(from) + 0.1
	r = await _shot(&"javelin_clu", &"javelin", from, Launchers.hull_box(abrams).get_center(), "top", abrams, false)
	b = r.get("burst", {})
	res = b.get("vehicle_result", {})
	var hit: Dictionary = b.get("vehicle_hit", {})
	check(r.get("how", "") == "burst" and b.get("vehicle") == abrams and hit.get("kind") == Vehicle.TOP_ATTACK and bool(res.get("penetrated", false))
		and (hit.get("position", Vector3.ZERO) as Vector3).y > abrams.global_position.y + 2.0,
		"a Javelin's top attack goes through the Abrams' turret roof (%s, zone %s)" % [_describe(r, hit), res.get("zone", "-")])
	await _clear(abrams, [driver])


## OG-7V on a technical's bed: the hull takes it, the rider in the open bed is blasted, the
## driver in the cab isn't (the hull shields the cab, Warheads.vehicle_occupants). Then AT4s
## until it's destroyed: it burns, and burns out a wreck.
func _real_technical() -> void:
	var tech := await _real("technical_dshk", Vector3(-50, 0, 75))
	var driver := _soldier("TechDriver", &"hostile", tech.global_position + Vector3(-3, 0.1, -1), [], false)
	var rider := _soldier("TechRider", &"hostile", tech.global_position + Vector3(-3, 0.1, 1), [], false)
	await get_tree().physics_frame
	check(tech.server_enter(driver, 0) and tech.server_enter(rider, 2), "a technical with a driver and a rider in the open bed")
	await _seated()
	var bed := tech.global_transform * Vector3(-0.93, 1.0, 1.0)
	var r := await _shot(&"rpg7", &"og7v", Vector3(bed.x - 25.0, _ground(bed) + 0.1, bed.z), bed)
	var b: Dictionary = r.get("burst", {})
	var hit: Dictionary = b.get("vehicle_hit", {})
	check(b.get("vehicle") == tech and hit.get("kind") == Vehicle.HE and tech.zone_health(Vehicle.ZONE_HULL) < 1.0 and not tech.wrecked,
		"OG-7V on the technical: an HE hit on its hull (hull %.0f%%; %s)" % [tech.zone_health(Vehicle.ZONE_HULL) * 100.0, _describe(r, hit)])
	check(rider.vitals.deaf_left() > 0.0, "the rider in the open bed takes the blast (%s)" % rider.vitals.condition_text())
	check(driver.vitals.deaf_left() == 0.0 and driver.vitals.wound_list().is_empty(), "the driver inside the cab doesn't (%s)" % driver.vitals.condition_text())
	var lost := [false]
	tech.destroyed.connect(func(_v: Vehicle) -> void: lost[0] = true)
	var cab := tech.global_transform * Vector3(-0.93, 1.3, -0.5)
	for i in 3:
		if lost[0]:
			break
		await _shot(&"at4", &"at4_heat", Vector3(cab.x - 25.0, _ground(cab) + 0.1, cab.z), cab)
	check(lost[0] and tech.is_burning() and tech.zone_health(Vehicle.ZONE_HULL) <= 0.0, "AT4s destroy it: it's on fire (hull %.0f%%)" % (tech.zone_health(Vehicle.ZONE_HULL) * 100.0))
	tech.burning_s = minf(tech.burning_s, 1.0)  # (it burns Vehicle.FIRE_S; skip to the end)
	await _wait_until(func() -> bool: return tech.wrecked, 10.0)
	check(tech.wrecked and tech.occupants().is_empty() and driver.vitals.is_dead() and rider.vitals.is_dead(),
		"it burns out a wreck, and nobody left aboard lived (%s / %s)" % [driver.vitals.condition_text(), rider.vitals.condition_text()])
	await _clear(tech, [driver, rider])


## HE and HEDP on a MaxxPro: HE (no penetration) only scorches the armour, the rider inside
## untouched; HEDP's small shaped charge (200 mm) goes through its side and into him.
func _real_mrap() -> void:
	var mrap := await _real("maxxpro", Vector3(40, 0, 40))
	var rider := _soldier("MrapRider", &"friendly", mrap.global_position + Vector3(-3, 0.1, 0), [], false)
	await get_tree().physics_frame
	check(mrap.server_enter(rider, 2), "a MaxxPro with a rider in the back")
	await _seated()
	var side := mrap.global_transform * Vector3(-1.26, 1.8, -0.8)
	var r := await _shot(&"maaws", &"ffv441", Vector3(side.x - 25.0, _ground(side) + 0.1, side.z), side)
	var b: Dictionary = r.get("burst", {})
	var res: Dictionary = b.get("vehicle_result", {})
	var zone: StringName = res.get("zone", Vehicle.ZONE_CREW)
	var health := mrap.zone_health(zone)
	check(b.get("vehicle") == mrap and bool(res.get("stopped", false)) and not bool(res.get("penetrated", true)) and health < 1.0 and health > 0.5,
		"FFV441 HE on the MaxxPro's side: stopped, a little damage (%s %.0f%%; %s)" % [zone, health * 100.0, _describe(r, b.get("vehicle_hit", {}))])
	check(rider.vitals.wound_list().is_empty() and rider.vitals.deaf_left() == 0.0, "the rider inside is untouched (%s)" % rider.vitals.condition_text())
	var chest := _chest(rider)
	r = await _shot(&"smaw", &"smaw_hedp", Vector3(chest.x - 25.0, _ground(chest) + 0.1, chest.z), chest)
	b = r.get("burst", {})
	res = b.get("vehicle_result", {})
	check(b.get("vehicle") == mrap and bool(res.get("penetrated", false)) and (b.get("vehicle_hit", {}) as Dictionary).get("kind") == Vehicle.HEDP
		and (rider.vitals.is_dead() or not rider.vitals.wound_list().is_empty()), "SMAW HEDP (200 mm) goes through its side and into the rider (%s; %s; %s)" % [_describe(r, b.get("vehicle_hit", {})), res, rider.vitals.condition_text()])
	await _clear(mrap, [rider])


## A rocket fired across a technical, over its bed through the gun mount's collision box
## where the model has no voxels: it meets nothing of the hull (server_take_hit would say
## missed) and flies on to the wall behind, not a penetration.
func _real_open_bed() -> void:
	var tech := await _real("technical_dshk", Vector3(-50, 0, 40))
	var local := Vector3(0.0, 1.6, 0.6)
	var clear: bool = not tech.hull.first_solid(local + Vector3(-0.6, 0, 0), Vector3.RIGHT, 1.2).hit
	var box := VehicleSpecs.box(tech.spec.boxes[4])
	check(clear and box.has_point(local), "over the bed the gun mount's box holds no voxels at %s" % local)
	var through := tech.global_transform * local
	var wall := _cover_box(Vector3(through.x + 12.0, through.y - 2.0, through.z - 3.0), Vector3(through.x + 12.5, through.y + 2.0, through.z + 3.0))
	var carves := tech.net_carves.size()
	var r := await _shot(&"at4", &"at4_heat", Vector3(through.x - 25.0, _ground(through) + 0.1, through.z), through)
	var b: Dictionary = r.get("burst", {})
	var at: Vector3 = r.get("position", Vector3.ZERO)
	check(r.get("how", "") == "burst" and b.get("vehicle") == null and (r.get("passed", []) as Array).has(tech) and at.x > through.x + 10.0
		and tech.net_carves.size() == carves and tech.zone_health(Vehicle.ZONE_HULL) == 1.0,
		"an AT4 through the technical's open bed flies on and bursts on the wall behind (%s, at x %+.1f m)" % [r.get("how", "?"), at.x - through.x])
	wall.queue_free()
	await _clear(tech, [])


## The most spall wounds V1's Vehicle._spall gives anyone (3 to 6 fragments).
## One pass of spall is at most 6 fragments, and a fragment can open two wounds (a muscle and the
## vessel under it, WoundModel's anatomy); a second pass would add up to 6 more fragments.
const SPALL_WOUNDS_MAX := 12


## Holes (or another kind of edit) carved into a vehicle's hull so far.
func _carves(v: Vehicle, kind: int) -> int:
	return v.net_carves.filter(func(op: Array) -> bool: return int(op[4]) == kind).size()


## The ground's height under `p` (the world only).
func _ground(p: Vector3) -> float:
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(p.x, p.y + 40.0, p.z), Vector3(p.x, p.y - 40.0, p.z), 1))
	return (hit.position as Vector3).y if not hit.is_empty() else 0.0


## Takes everyone out of `v` and frees it and them.
func _clear(v: Vehicle, people: Array) -> void:
	for s: Soldier in v.occupants():
		v.server_exit(s)
	await _physics(2)
	for p: Node in people:
		if is_instance_valid(p):
			p.queue_free()
	v.queue_free()
	await _frames(3)


## Riders just seated: their hitboxes ease into the seat's pose (CharacterModel) before
## anyone measures where their chest is.
func _seated() -> void:
	await _seconds(0.6)


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A vehicle of V1's `model` parked at `pos` (facing -z turned `yaw` degrees), its hull's
## voxels ready, settled.
func _real(model: String, pos: Vector3, yaw := 0.0, faction := &"player") -> Vehicle:
	VehicleHull.prewarm(model)
	var layer := VehicleLayer.of(level)
	pos.y = _ground(pos)
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos + Vector3.UP * 0.3), "", faction,
		"aa_%s_%d" % [model, randi() % 100000])
	await _wait_until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(1.5)  # down on its springs
	return v


# --- Structures ----------------------------------------------------------------------------

func _test_structures() -> void:
	print("Structures: the hole by round kind (the north wall, 30 cm of concrete)")
	var C := VoxelWorld.Mat.CONCRETE
	var E := VoxelWorld.Mat.EMPTY
	var behind := _dummy(Vector3(12, 0, -21.2))
	_place(player, Vector3(12, 0.1, 0))
	await _wait_for_collision()
	check(not Throwables.clear_line(level.get_world_3d(), Vector3(12, 1.2, -18), Vector3(12, 1.2, -21)), "the wall is solid")
	var r := await _shot(&"at4", &"at4_heat", Vector3(12, 0.1, 0), _chest(behind))
	var b: Dictionary = r.get("burst", {})
	var heat_at: Vector3 = r.get("position", Vector3.ZERO)
	var into := Vector3(0, 0, -1)
	var heat_removed := _removed(heat_at)
	check(int(b.get("holes", 0)) > 0 and bool(b.get("through", false)) and world.material_at(heat_at + into * 0.25) == E and world.material_at(heat_at + Vector3(0.45, 0, 0) + into * 0.05) == C,
		"HEAT bores a small deep hole: through the wall, concrete left 45 cm to the side (%d voxels)" % heat_removed)
	check(behind.vitals.is_dead(), "and the jet kills the man behind the wall (%s)" % behind.vitals.condition_text())
	behind.queue_free()
	r = await _shot(&"maaws", &"ffv441", Vector3(6, 0.1, 2), Vector3(6, 1.2, -19.7))
	var he_at: Vector3 = r.get("position", Vector3.ZERO)
	var he_removed := _removed(he_at)
	check(int(r.get("burst", {}).get("holes", -1)) == 0 and world.material_at(he_at + Vector3(0.2, 0, 0) + into * 0.05) == E and he_removed > heat_removed
		and world.material_at(he_at + into * 0.27) == C, "HE blows a wider, shallow crater: no hole through (%d voxels)" % he_removed)
	r = await _shot(&"smaw", &"smaw_hedp", Vector3(-15, 0.1, 0), Vector3(-15, 1.2, -19.7))
	var hedp_at: Vector3 = r.get("position", Vector3.ZERO)
	check(int(r.get("burst", {}).get("holes", 0)) > 0 and _removed(hedp_at) > 0, "HEDP bores and craters (%d voxels)" % _removed(hedp_at))
	r = await _shot(&"smaw", &"smaw_ne", Vector3(-9, 0.1, 0), Vector3(-9, 1.2, -19.7))
	var tb_at: Vector3 = r.get("position", Vector3.ZERO)
	var tb_removed := _removed(tb_at)
	check(tb_removed > he_removed * 3 and world.material_at(tb_at + Vector3(0.6, 0, 0) + into * 0.05) == E,
		"thermobaric takes out far more (%d voxels)" % tb_removed)
	var ops: Array = GameState.voxel_edits.map(func(e: Dictionary) -> String: return e.op)
	check(ops.has("holes") and ops.has("blast"), "all of it in the zone's edit log (saved, sent to joiners)")


## Voxels gone within 0.9 m of `at` on the north wall.
func _removed(at: Vector3) -> int:
	var begin := Vector3i(roundi(at.x * 10.0) - 9, maxi(roundi(at.y * 10.0) - 9, 0), -201)
	var size := Vector3i(19, 19, 4)
	var solid := world.solid_voxels(begin, size).count(1)
	# A pristine stretch of the same wall: 3 voxels deep (z -200..-198), 0..2.6 m high.
	var full := 0
	for y in size.y:
		var vy := begin.y + y
		if vy >= 0 and vy < 26:
			full += size.x * 3
	return full - solid


func _test_arming() -> void:
	print("Arming distance")
	var edits := GameState.voxel_edits.size()
	var r := await _shot(&"at4", &"at4_heat", Vector3(14.5, 0.1, -14.5), Vector3(14.5, 1.2, -19.7))
	check(r.get("how", "") == "dud" and GameState.voxel_edits.size() == edits, "an AT4 at a wall 5 m away doesn't fuse (%s, %d edits)" % [r.get("how", ""), GameState.voxel_edits.size() - edits])


# --- People --------------------------------------------------------------------------------

func _test_people() -> void:
	print("People: fragments and overpressure")
	var near := _dummy(Vector3(1.5, 0, 61))
	var mid := _dummy(Vector3(3.5, 0, 62))
	var far := _dummy(Vector3(0, 0, 86))
	await _frames(3)
	var r := await _shot(&"rpg7", &"og7v", Vector3(-30, 0.1, 60), Vector3(0, 0.05, 60))
	check(r.get("how", "") == "burst" and near.vitals.deaf_left() > 0.0 and not near.vitals.wound_list().is_empty(),
		"an OG-7V burst: fragment wounds and ringing ears 2 m away (%d wounds)" % near.vitals.wound_list().size())
	check(mid.vitals.deaf_left() > 0.0, "overpressure reaches 4 m (%.0f s deaf)" % mid.vitals.deaf_left())
	check(far.vitals.wound_list().is_empty() and far.vitals.deaf_left() == 0.0, "nothing 25 m away")
	for d in [near, mid, far]:
		d.queue_free()
	var target := _dummy(Vector3(0, 0, 70))
	await _frames(3)
	r = await _shot(&"at4", &"at4_heat", Vector3(-25, 0.1, 70), _chest(target))
	check(r.get("burst", {}).get("direct") == target and target.vitals.is_dead(), "a HEAT round straight into a man kills him (%s)" % target.vitals.condition_text())
	target.queue_free()
	print("Thermobaric in a room (the shed)")
	var a := _dummy(Vector3(17.6, 0, -10.2))
	var b := _dummy(Vector3(19.0, 0, -7.7))
	_place(player, Vector3(8, 0.1, -9.0))
	await _wait_for_collision()
	check(Throwables.indoors(level.get_world_3d(), Vector3(18.0, 1.0, -9.0)), "the shed has a roof")
	r = await _shot(&"smaw", &"smaw_ne", Vector3(8, 0.1, -9.0), Vector3(19.65, 1.0, -9.0))
	var hurt := func(d: TargetDummy) -> bool: return d.vitals.deaf_left() > 0.0 and d.vitals.burn_share() > 0.0
	check(r.get("how", "") == "burst" and hurt.call(a) and hurt.call(b),
		"a SMAW-NE through the door burns and blasts everyone inside (%s / %s)" % [a.vitals.condition_text(), b.vitals.condition_text()])
	a.queue_free()
	b.queue_free()
	await _frames(2)


# --- Backblast -----------------------------------------------------------------------------

func _test_backblast() -> void:
	print("Backblast")
	var behind := _dummy(Vector3(-44, 0, 30))
	var front := _dummy(Vector3(-38, 0, 33))
	var far_behind := _dummy(Vector3(-60, 0, 30))
	await _frames(3)
	player.vitals.server_reset_health()
	await _shot(&"at4", &"at4_heat", Vector3(-40, 0.1, 30), Vector3(-10, 0.05, 30))
	# Lethal: internal bleeding, or dead outright (a debris fragment can find the head).
	check(behind.vitals.is_dead() or (behind.vitals.blood_fraction() < 0.7 and behind.vitals.deaf_left() > 0.0),
		"an AT4's backblast 4 m behind: lethal zone (%d%% blood, %s)" % [roundi(behind.vitals.blood_fraction() * 100), behind.vitals.condition_text()])
	check(far_behind.vitals.deaf_left() > 0.0 and far_behind.vitals.blood_fraction() > 0.99, "20 m behind: overpressure only")
	check(front.vitals.deaf_left() == 0.0 and front.vitals.wound_list().is_empty() and front.vitals.blood_fraction() > 0.99, "nothing in front of the shooter")
	check(player.vitals.deaf_left() == 0.0 and player.vitals.blood_fraction() > 0.99 and float(launchers.last_backblast.get("reflected", 0.0)) < 0.0,
		"in the open the shooter is fine")
	for d in [behind, front, far_behind]:
		d.queue_free()
	player.vitals.server_reset_health()
	await _shot(&"at4", &"at4_heat", Vector3(10, 0.1, -19.0), Vector3(10, 0.05, 0))
	check(float(launchers.last_backblast.get("reflected", -1.0)) >= 0.0 and player.vitals.deaf_left() > 0.0 and player.vitals.blood_fraction() < 1.0,
		"with a wall right behind, it comes back at the shooter (%s)" % player.vitals.condition_text())
	player.vitals.server_reset_health()
	await _shot(&"nlaw", &"nlaw", Vector3(10, 0.1, -19.0), Vector3(10, 0.05, 2), "da")
	check(player.vitals.deaf_left() == 0.0 and player.vitals.blood_fraction() > 0.99, "an NLAW's soft launch doesn't (%s)" % player.vitals.condition_text())
	player.vitals.server_reset_health()


# --- Reload --------------------------------------------------------------------------------

func _test_reload() -> void:
	print("Reloading")
	player.inventory.unequip(SLOT)
	player.inventory.take(&"rpg7")
	player.inventory.take(&"pg7v_round", 2)
	player.inventory.take(&"og7v_round", 1)
	_place(player, Vector3(-30, 0.1, 45))
	await _frames(2)
	player._server_busy_until = 0.0
	var eye := player.camera.global_position
	check(Launchers.loaded_of(player) == &"" and launchers.server_fire(player, eye, Vector3(1, 0, 0), "", null).begins_with("Empty"), "an RPG-7 starts empty")
	var secs := launchers.server_reload(player)
	check(is_equal_approx(secs, 4.5), "loading a rocket takes 4.5 s (%.1f)" % secs)
	await _seconds(2.0)
	check(Launchers.loaded_of(player) == &"" and launchers.server_fire(player, eye, Vector3(1, 0, 0), "", null) == "Busy", "half way it can't fire")
	await _seconds(2.8)
	check(Launchers.loaded_of(player) == &"pg7v" and player.inventory.count_of(&"pg7v_round") == 1, "then the PG-7V is in (one left)")
	launchers.server_reload(player)  # R again: swap for the OG-7V
	await _seconds(4.8)
	check(Launchers.loaded_of(player) == &"og7v" and player.inventory.count_of(&"pg7v_round") == 2 and player.inventory.count_of(&"og7v_round") == 0,
		"R again swaps it for the OG-7V; the PG-7V goes back in the kit")
	var r := await _shot(&"rpg7", &"", Vector3(-30, 0.1, 45), Vector3(0, 0.05, 45))
	check(r.get("how", "") == "burst" and player.inventory.slots[SLOT] == &"rpg7" and Launchers.loaded_of(player) == &"", "fired, the RPG-7 is empty again (kept)")
	# Audit A2-02: the rocket goes into the launcher being reloaded, not another RPG-7 picked
	# up meanwhile.
	var rounds_before := player.inventory.count_of(&"pg7v_round") + player.inventory.count_of(&"og7v_round")
	player._server_busy_until = 0.0
	launchers.server_reload(player)
	await _seconds(0.5)
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, SLOT, &"")
	level.server_spawn_dropped(&"rpg7", 1, player.global_position + Vector3.UP * 0.5, {"test_mark": "other_rpg"})
	await _frames(2)
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if node is WorldItem and node.state.get("test_mark", "") == "other_rpg":
			player._server_interact.rpc_id(1, node.get_path())
	check(player.inventory.slots[SLOT] == &"rpg7" and player.inventory.state_of(SLOT).get("test_mark", "") == "other_rpg", "mid-reload: the RPG-7 dropped, another picked up")
	await _seconds(4.8)
	check(Launchers.loaded_of(player) == &"" and player.inventory.count_of(&"pg7v_round") + player.inventory.count_of(&"og7v_round") == rounds_before,
		"the old reload didn't load the other RPG-7 (%s loaded)" % Launchers.loaded_of(player))
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):  # the dropped RPG-7: not part of later tests
		if node is WorldItem and node.item_id == &"rpg7":
			node.queue_free()
	player.inventory.unequip(SLOT)
	player.inventory.take(&"at4")
	await _shot(&"at4", &"", Vector3(-30, 0.1, 45), Vector3(0, 0.05, 45))
	check(player.inventory.slots[SLOT] == &"" and launchers.server_reload(player) < 0.0, "a fired AT4 is spent: nothing left to reload")


# --- AI ------------------------------------------------------------------------------------

func _test_ai() -> void:
	print("AI with an RPG-7")
	# The AI won't fire with a wall right behind (its backblast would come back at them).
	var rpg := ItemDB.get_item(&"rpg7")
	_place(player, Vector3(10, 0.1, -19.0))
	player.rotation.y = PI  # facing south, the north wall at their back
	await _frames(2)
	var walled := LauncherAI.wall_behind(player, rpg)
	_place(player, Vector3(10, 0.1, -12.0))
	await _frames(2)
	check(walled and not LauncherAI.wall_behind(player, rpg) and not LauncherAI.wall_behind(player, ItemDB.get_item(&"nlaw")),
		"the AI sees a wall right behind the tube (not 7 m back, and never for a soft launch)")
	player.rotation.y = 0.0
	_place(player, Vector3(-75, 0.1, -75))  # out of the way
	var fired_by := func(s: Soldier) -> int:
		return launchers.results.values().filter(func(r: Dictionary) -> bool: return r.shooter == s).size()
	var hostile := _soldier("RpgGunner", &"hostile", Vector3(30, 0.1, 30), ["assault_pack", "rpg7", "pg7v_round", "pg7v_round"], true)
	var lone := _soldier("LoneMan", &"friendly", Vector3(30, 0.1, 62), [], false)
	await _seconds(9.0)
	var ai := SquadAI.of(hostile)
	check(ai != null and ai.target == lone, "the hostile has the lone soldier in sight (%s)" % (ai.target.name if ai and ai.target else "none"))
	check(fired_by.call(hostile) == 0 and lone.vitals.is_up(), "and doesn't waste a rocket on him (%s)" % LauncherAI.status(hostile))
	# A real vehicle (V1's M-ATV, the player's side) parks in view.
	var rolls := Vehicle.fire_rolls
	Vehicle.fire_rolls = false
	var matv := await _real("matv", Vector3(55, 0, 55))
	var carves := matv.net_carves.size()
	await _wait_until(func() -> bool: return fired_by.call(hostile) > 0, 25.0)
	var shots: Array = launchers.results.values().filter(func(r: Dictionary) -> bool: return r.shooter == hostile)
	var hit_it: bool = shots.any(func(r: Dictionary) -> bool: return (r.get("burst", {}) as Dictionary).get("vehicle") == matv)
	var near: bool = shots.any(func(r: Dictionary) -> bool: return Launchers.hull_box(matv).grow(3.0).has_point(r.position))
	check(not shots.is_empty() and (hit_it or near) and Launchers.loaded_of(hostile) == &"",
		"an M-ATV parks in view: he fires the RPG-7 at it (%s; hull marks %d -> %d; %s)" % ["hit" if hit_it else ("near" if near else "missed"), carves, matv.net_carves.size(), LauncherAI.status(hostile)])
	var said := level.callouts.sent.any(func(l: Dictionary) -> bool: return String(l.get("text", "")) == "Backblast clear!")
	check(said, "calling \"Backblast clear!\" first")
	for n in [hostile, lone, matv]:
		n.queue_free()
	Vehicle.fire_rolls = rolls
	await _frames(3)
	print("AI: a group behind cover")
	# In the open north-east of the compound: a low wall (a plain world body, 1.1 m high) with a
	# group behind it, two crouched behind it and one standing; an insurgent with his rifle about
	# 29 m off (over LauncherAI.MIN_RANGE_M even after a step or two).
	var cover := _cover_box(Vector3(27, 0, -46.4), Vector3(33, 1.1, -46.0))
	var grenadier := _soldier("RpgGunner2", &"hostile", Vector3(30, 0.1, -75),
		["plate_carrier_light", "assault_pack", "mk18", "mag_556", "mag_556", "rpg7", "og7v_round", "og7v_round"], true)
	var up := _soldier("Standing", &"friendly", Vector3(30, 0.1, -45.2), [], false)
	var low1 := _soldier("Crouched1", &"friendly", Vector3(29.1, 0.1, -45.5), [], false)
	var low2 := _soldier("Crouched2", &"friendly", Vector3(30.9, 0.1, -45.5), [], false)
	low1.want_crouch = true
	low2.want_crouch = true
	await _wait_until(func() -> bool: return fired_by.call(grenadier) > 0, 30.0)
	var shot: Array = launchers.results.values().filter(func(r: Dictionary) -> bool: return r.shooter == grenadier)
	var at: Vector3 = shot[0].position if not shot.is_empty() else Vector3.INF
	check(not shot.is_empty() and at.z > -46.7 and at.z < -45.0 and absf(at.x - 30.0) < 3.0,
		"a hostile fires at a group behind the low wall, into the cover (%s; %s; he's at %s)" % [at, LauncherAI.status(grenadier), grenadier.global_position])
	cover.queue_free()
	for n in [grenadier, up, low1, low2]:
		n.queue_free()
	await _frames(3)
	print("AI: a spare tube packed on top of the ruck")
	var packer := _soldier("Packer", &"friendly", Vector3(-60, 0.1, -60), ["ruck_45", "m4a1"], false)
	await _frames(2)
	var packed := packer.inventory.attach(&"pack_top_1", {"id": &"at4"})
	var empty_before: bool = packer.inventory.slots.get(Launchers.SLOT, &"") == &""
	var took := LauncherAI.unstrap_packed(packer)
	var again := LauncherAI.unstrap_packed(packer)  # nothing left up there
	var unstrapped: bool = packer.inventory.slots.get(Launchers.SLOT, &"") == &"at4"
	check(packed and empty_before and took and not again and unstrapped and packer.inventory.attachment(&"pack_top_1").is_empty()
			and packer._server_busy_until > Soldier._now(),
		"with the shoulder tube gone, the AI unstraps the AT4 off the top of the pack (busy while it does) (packed %s, problem '%s', empty before %s, launcher now '%s', point now %s, busy %.1f s)"
			% [packed, packer.inventory.attach_problem(ItemDB.get_item(&"at4"), &"pack_top_1"), empty_before,
				packer.inventory.slots.get(Launchers.SLOT, &""), packer.inventory.attachment(&"pack_top_1"), packer._server_busy_until - Soldier._now()])
	packer.queue_free()
	await _frames(3)


# --- Replication: a second process joins ---------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	# Before it joins: a HEAT hole in the north wall it must see.
	_place(player, Vector3(-18, 0.1, 0))
	var r := await _shot(&"at4", &"at4_heat", Vector3(-18, 0.1, 0), Vector3(-18, 1.2, -19.7))
	var hole: Vector3 = (r.get("position", Vector3.ZERO) as Vector3) + Vector3(0, 0, -0.15)
	check(world.material_at(hole) == VoxelWorld.Mat.EMPTY, "a crater before anyone joins")
	expect = {"hole": [hole.x, hole.y, hole.z], "solid": [hole.x + 0.6, hole.y, hole.z]}
	# The client asks for these once it has joined (_ask_expect), however many tries joining took.
	var log_path := OS.get_user_data_dir().path_join("antiarmor_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/antiarmor_test.tscn",
		"--", "--antiarmor-join"]  # not main's --join: the client joins by itself (_join_host)
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _wait_until(func() -> bool: return _client_ready, 120.0)
	check(_client_ready, "the client checked the crater it found on joining")
	if _client_ready:
		# Live: a round it watches fly and burst (an OG-7V lobbed high: it self-destructs).
		_place(player, Vector3(-30, 0.1, 40))
		_arm(&"rpg7", &"og7v")
		await _frames(2)
		player._server_busy_until = 0.0
		var eye := player.camera.global_position
		launchers.server_fire(player, eye, Vector3(1, 1.2, 0).normalized(), "", null)
		var id := launchers.last_id
		await _wait_until(func() -> bool: return launchers.results.has(id), 10.0)
		check(launchers.results.get(id, {}).get("how", "") == "burst", "the OG-7V self-destructs in the air")
		_live_done.rpc(id)
		# The client fires its own AT4 (its request goes to the host).
		var them: Soldier = null
		for p in level.players.get_children():
			if p != player:
				them = p
		if them:
			them.inventory.take(&"at4")
			await _wait_until(func() -> bool: return launchers.results.values().any(func(x: Dictionary) -> bool: return x.shooter == them), 20.0)
			check(launchers.results.values().any(func(x: Dictionary) -> bool: return x.shooter == them), "the client fired an AT4 through the host")
	await _wait_until(func() -> bool: return _client_failures >= 0, 45.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _wait_until(func() -> bool: return not OS.is_process_running(pid), 10.0)
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


## Client -> host, once joined: send me what to check (the host answers the asker).
@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_live() -> void:
	_client_ready = true


@rpc("any_peer", "call_remote", "reliable")
func _live_done(id: int) -> void:
	expect["live_id"] = id


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(200.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# This test joins by itself (_join_host), not through the menu's few short tries (two
	# joiners replaced each other's connection), and a dropped attempt must not reload the
	# scene from under it (Main reloads on session_ended).
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	# The menu's few short join attempts can all time out while this process builds its world
	# under load: keep joining until it's in, then ask the host what to check.
	var joined := await _join_host("127.0.0.1", 90.0)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until:
		_ask_expect.rpc_id(1)
		await _wait_until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		launchers = Launchers.of(level)
		world = level.voxel_world
		var hole := Vector3(expect.hole[0], expect.hole[1], expect.hole[2])
		var solid := Vector3(expect.solid[0], expect.solid[1], expect.solid[2])
		await _wait_until(func() -> bool: return world.is_built() and world.material_at(hole) == VoxelWorld.Mat.EMPTY, 30.0)
		note.call(world.is_built() and world.material_at(hole) == VoxelWorld.Mat.EMPTY and world.material_at(solid) == VoxelWorld.Mat.CONCRETE,
			"the crater made before joining is here (late join), the wall around it isn't")
		note.call(launchers != null, "the level's Launchers node is here")
		var seen := [false]
		var watch := func() -> void:
			for id: int in launchers.projectiles:
				seen[0] = true
		get_tree().process_frame.connect(watch)
		_ready_for_live.rpc_id(1)
		await _wait_until(func() -> bool: return expect.has("live_id") and launchers.ends.any(func(e: Dictionary) -> bool: return int(e.id) == int(expect.live_id)), 20.0)
		get_tree().process_frame.disconnect(watch)
		var end: Array = launchers.ends.filter(func(e: Dictionary) -> bool: return expect.has("live_id") and int(e.id) == int(expect.live_id))
		note.call(seen[0] and launchers.launched >= 1, "the host's round flew here (seen in flight)")
		note.call(not end.is_empty() and end[0].how == "burst", "and burst here")
		note.call(launchers.backblasts >= 1, "with its backblast's dust")
		# Our own shot: the host gave us an AT4.
		var me := level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		await _wait_until(func() -> bool: return me != null and me.inventory.slots.get(SLOT, &"") == &"at4", 15.0)
		note.call(me != null and me.inventory.slots.get(SLOT, &"") == &"at4", "the AT4 the host gave us is in our launcher slot")
		if me:
			var eye := me.camera.global_position
			launchers.request_fire.rpc_id(1, eye, Vector3(0, -0.06, 1).normalized(), "", NodePath())
			await _wait_until(func() -> bool: return me.inventory.slots.get(SLOT, &"") == &"", 10.0)
			note.call(me.inventory.slots.get(SLOT, &"") == &"", "we fired it: the spent tube is gone")
	_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


# --- Helpers -------------------------------------------------------------------------------

## Puts `launcher` in the player's launcher slot, loaded with warhead `w` ("" as it is).
func _arm(launcher: StringName, w: StringName) -> void:
	if player.inventory.slots[SLOT] != launcher:
		player.inventory.unequip(SLOT)
		player.inventory.take(launcher)
	if w != &"":
		player.inventory.set_slot_state(SLOT, {"round": String(w)})


## The player fires `launcher` (loaded with `w`) standing at `at`, at `aim` (raised for the
## round's drop unless `compensate` is off), in `mode`, at `target`. Waits for the round to
## end; returns Launchers.results' entry (with "id"), or {"why"} if it didn't fire.
func _shot(launcher: StringName, w: StringName, at: Vector3, aim: Vector3, mode := "", target: Node3D = null, compensate := true) -> Dictionary:
	_arm(launcher, w)
	_place(player, at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if absf(at.x) < 25.0 and absf(at.z) < 25.0:
		await _wait_for_collision()  # the walls' collision only exists near a viewer
	var eye := player.camera.global_position
	var point := aim
	var loaded := Launchers.loaded_of(player)
	if compensate and loaded != &"":
		point += Vector3.UP * float(LauncherProjectile.drop_at(loaded, eye.distance_to(aim)).drop)
	player._server_busy_until = 0.0
	var why := launchers.server_fire(player, eye, (point - eye).normalized(), mode, target)
	if why != "":
		print("    (%s didn't fire: %s)" % [launcher, why])
		return {"why": why}
	var id := launchers.last_id
	await _wait_until(func() -> bool: return launchers.results.has(id), 30.0)
	var r: Dictionary = launchers.results.get(id, {}).duplicate()
	r["id"] = id
	await _frames(2)
	return r


## A plain box of world (layer 1) from `from` to `to` (metres): cover away from the voxels.
func _cover_box(from: Vector3, to: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = to - from
	shape.shape = box
	body.add_child(shape)
	level.add_child(body)
	body.global_position = (from + to) * 0.5
	return body


func _stub(pos: Vector3) -> StubVehicle:
	var stub := StubVehicle.new()
	stub.name = "Stub%d" % randi()
	level.add_child(stub)
	stub.global_position = pos
	return stub


func _dummy(pos: Vector3) -> TargetDummy:
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.respawn_seconds = 999.0
	level.add_child(dummy)
	dummy.global_position = pos
	return dummy


func _chest(body: Node3D) -> Vector3:
	var hitbox := body.get_node_or_null(^"ChestHitbox") as Area3D
	return Warheads.hitbox_point(hitbox, Vector3.ZERO) if hitbox else body.global_position + Vector3.UP * 1.3


func _soldier(callsign: String, faction: StringName, pos: Vector3, loadout: Array, active: bool) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": loadout, "combat": 0.9, "discipline": 0.6, "guard": true})
	if not active:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _describe(r: Dictionary, hit: Dictionary) -> String:
	if r.has("why"):
		return "didn't fire: %s" % r.why
	return "%s after %.0f m%s" % [r.get("how", "?"), float(r.get("flown", 0.0)),
		", at (%.1f, %.2f, %.1f)" % [hit.position.x, hit.position.y, hit.position.z] if hit.has("position") else ", no hit"]


func _place(s: Node3D, pos: Vector3) -> void:
	s.global_position = pos
	if s is CharacterBody3D:
		(s as CharacterBody3D).velocity = Vector3.ZERO


## Client: joins the host at `address`, joining again whenever an attempt has failed, until it
## is in or `seconds` pass. Whether it joined.
func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:  # (or in already)
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
