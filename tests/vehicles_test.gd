extends Node
## Wave 5 V1, vehicle core: driving (wheeled and tracked), seats, cargo, damage by round and
## zone, hull carving and its frame budget, fire and wrecks, saving, AI drivers, ragdolls and
## run-overs. Two processes over real ENet, like the world suite:
##   <exe> --headless --path . res://tests/vehicles_test.tscn -- --vehicles-host
##   <exe> --headless --path . res://tests/vehicles_test.tscn -- --vehicles-join 127.0.0.1
## The host runs its single-process checks on the vehicle range with new connections refused,
## then lets the client in. The client (joining late) checks it sees the vehicles, who sits
## where and the damage, then gets in and drives one; the host checks it moved there too.
## Without arguments only the host's checks run. Each process prints VEHICLES TEST
## PASSED/FAILED and exits with its failure count; the host exits when the client leaves.

## Where the host leaves things for the late joiner.
const LATE_SEATED := "Rider"
const CLIENT_DRIVE_S := 4.0

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var layer: VehicleLayer
var _client_left := false
var _host_digest := {}
var _host_saw := {}
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_vehicles" + tag  # never touch a real save
	Campaign.campaign_id = "test_vehicles" + tag
	CompoundLevel.spawn_ai = false
	Vehicle.local_input = false  # the tests drive by request
	Vehicle.fire_rolls = false  # no chance fires: the fire test starts its own
	ControlOptions._get_out = false  # the menu's Get out, whatever this machine's settings say (never saved)
	ControlOptions._loaded = true
	var args := OS.get_cmdline_user_args()
	if "--vehicles-join" in args:
		var i := args.find("--vehicles-join")
		await _run_client(args[i + 1] if i + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		await _run_host("--vehicles-host" in args)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _finish() -> void:
	if Net.is_hosting() or multiplayer.is_server():
		GameState.delete_save()
	print("VEHICLES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


## While iterating: CONTRACTOR_VEHICLES_ONLY="ragdoll,gun" runs only those host checks.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_VEHICLES_ONLY")
	if only == "":
		return true
	for p in only.split(","):
		if part.begins_with(p):
			return true
	return false


func _vehicle(id: String) -> Vehicle:
	return layer.find(id) if layer else null


## A rifle for shooting at vehicles: an item for `round_id` (data/rounds.json).
static func _gun(round_id: String) -> ItemData:
	return ItemData.from_dict({"id": "test_" + round_id, "type": "weapon", "stats": {"round": round_id, "rpm": 600}})


## Host: an AI soldier (no brain running) at `pos`.
func _soldier(faction: String, pos: Vector3, callsign := "") -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": callsign if callsign != "" else "VT%d" % _made, "faction": faction, "variant": "woodland", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()  # ready for orders (Mount > Get in), then held still
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


## Host: puts a vehicle back where it was parked, whole, empty, stopped.
func _reset(v: Vehicle, pos: Vector3, yaw_deg := 0.0) -> void:
	for s: Soldier in v.occupants():
		v.server_exit(s)
	v.server_stop()
	v.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.sleeping = false
	for z in Vehicle.ZONES:
		v.server_set_zone(z, 1.0)
	v.server_set_fuel(float(v.spec.fuel_l))
	v.server_set_battery(true)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _drive(v: Vehicle, throttle: float, steer: float, brake: bool, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		v.request_drive(throttle, steer, brake)  # the host's own player drives: a local call
		await get_tree().physics_frame


static func _yaw(n: Node3D) -> float:
	var f := -n.global_basis.z
	return atan2(-f.x, -f.z)


# --- Host -------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the vehicle range on port %d" % Net.port())
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the tests move it
	layer = level.get_node(^"Vehicles") as VehicleLayer
	await _wait_for(func() -> bool: return layer.vehicles().size() == 4, 5.0)
	await _wait_for(func() -> bool: return VehicleRange.PARKED.all(func(p: Dictionary) -> bool: return VehicleHull.is_ready(String(p.model))), 20.0)
	await _seconds(1.0)  # settle on their springs
	_test_data()
	if _want("parked"):
		await _test_parked()
	if _want("drive_wheeled"):
		await _test_drive_wheeled()
	if _want("drive_tracked"):
		await _test_drive_tracked()
	if _want("seats"):
		await _test_seats()
	if _want("seated"):
		await _test_seated()
		await _test_boarding()
		await _test_crew_and_belly_turret()
		await _test_fast_rope()
	if _want("cargo"):
		await _test_cargo()
	if _want("interaction"):
		await _test_interaction()
	if _want("charge"):
		await _test_charge()
	if _want("rounds"):
		await _test_rounds()
		await _test_body_vehicle_feedback()
	if _want("fragments"):
		await _test_fragments()
	if _want("damage_effects"):
		await _test_damage_effects()
	if _want("carving_budget"):
		await _test_carving_budget()
	if _want("gun"):
		await _test_gun()
	if _want("vehicle_guns"):
		await _test_vehicle_guns()
		await _test_static_gun()
		await _test_gun_team()
		await _test_mortar_team()
		await _test_weapons_team_orders()
	if _want("chase_camera"):
		await _test_chase_camera()
	if _want("turret"):
		await _test_turret()
	if _want("service"):
		await _test_service()
	if _want("fire"):
		await _test_fire()
	if _want("save_reload"):
		await _test_save_reload()
	if _want("ai_driver"):
		await _test_ai_driver()
		await _test_squad_drivers()
	if _want("ragdoll_and_run_over"):
		await _test_ragdoll_and_run_over()
	if not wait_for_client:
		_finish()
		return
	await _stage_for_client()
	print("[host] waiting for the client")
	Net.peer_joined.connect(_on_client_joined)
	Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	await _wait_for(func() -> bool: return _client_left, 300.0)
	check(_client_left, "the client finished and left")
	check(float(_host_saw.get("moved", 0.0)) > 5.0 and _host_saw.get("driver", "") != "",
		"the host saw the client's driving move the M-ATV %.1f m (driver %s)" % [float(_host_saw.get("moved", 0.0)), _host_saw.get("driver", "")])
	_finish()


func _test_data() -> void:
	print("Vehicle numbers")
	var missing := VehicleArt.MODELS.keys().filter(func(m: String) -> bool: return not VehicleSpecs.has_model(m))
	check(missing.is_empty(), "every VehicleArt model has numbers in data/vehicles.json (missing %s)" % [missing])
	var counts := {}
	for m: String in ["matv", "maxxpro", "technical_dshk", "aav7", "bradley", "abrams", "uh60"]:
		var by := {}
		for seat: Dictionary in VehicleSpecs.spec(m).seats:
			by[String(seat.kind)] = int(by.get(String(seat.kind), 0)) + 1
		counts[m] = by
	check(counts.matv == {"driver": 1, "passenger": 3, "gunner": 1}, "M-ATV: 4 seats and a gunner (%s)" % [counts.matv])
	check(counts.maxxpro == {"driver": 1, "passenger": 5, "gunner": 1}, "MaxxPro: 6 seats and a gunner (%s)" % [counts.maxxpro])
	check(counts.technical_dshk == {"driver": 1, "passenger": 4, "gunner": 1}, "technical: 2 in the cab, 3 in the bed and the DShK gunner (%s)" % [counts.technical_dshk])
	check(counts.aav7 == {"driver": 1, "passenger": 22, "gunner": 1}, "AAV-7: 3 crew and 21 troops (%s)" % [counts.aav7])
	check(counts.bradley == {"driver": 1, "gunner": 1, "passenger": 7}, "Bradley: 3 crew and 6 troops (%s)" % [counts.bradley])
	check(VehicleSpecs.spec("abrams").seats.size() == 4, "Abrams: 4 crew")
	check(counts.uh60 == {"pilot": 2, "gunner": 2, "passenger": 15}, "UH-60: 2 pilots, 2 door gunners, 11 passengers (4 benched, 4 kneeling, 3 standing) and 4 on the door sills (%s)" % [counts.uh60])
	check(VehicleSpecs.round_tier(&"556_m855") == 0 and VehicleSpecs.round_tier(&"762x51_m80") == 0 and VehicleSpecs.round_tier(&"762x54r_lps") == 1
		and VehicleSpecs.round_tier(&"50bmg_m33") == 2, "vehicle threat tiers: small arms 0, 7.62x54R 1, .50 BMG 2 (Captain: 7.62x54R and up)")


func _test_parked() -> void:
	print("Parked on the range")
	var matv := _vehicle("range_matv")
	check(matv != null and matv.model == "matv" and _vehicle("range_maxxpro") != null and _vehicle("range_technical") != null and _vehicle("range_aav7") != null,
		"an M-ATV, a MaxxPro, a technical and an AAV-7 parked")
	if matv == null:
		return
	check(absf(matv.global_position.y) < 0.12 and matv.global_basis.y.dot(Vector3.UP) > 0.995,
		"standing level on its suspension (y %.3f)" % matv.global_position.y)
	check(matv.collision_layer == Vehicle.LAYER and matv.get_node_or_null(^"Hull/matv/Hull") != null,
		"on layer 7 with VehicleArt's look")
	check((matv.cargo() as VehicleCargo).feed_rounds(&"belt_50bmg") == 200, "its hold has two .50 belts (200 rounds)")


func _test_drive_wheeled() -> void:
	print("Driving: wheeled (M-ATV)")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	check(v.server_enter(player, 0) and v.driver() == player, "the host's player takes the driver's seat")
	var start := v.global_position
	var fuel := v.fuel
	await _drive(v, 1.0, 0.0, false, 4.0)
	var speed := v.forward_speed()
	var moved := (v.global_position - start).dot(Vector3.FORWARD)
	check(speed > 4.5 and moved > 8.0, "full throttle for 4 s: %.1f m/s, %.1f m forward (an M-ATV does 0-50 km/h in about 10 s)" % [speed, moved])
	await get_tree().process_frame
	check(player.global_position.distance_to(v.seat_transform("0").origin) < 0.05 and player.vehicle == v,
		"the driver rides with it, at the seat")
	check(v.fuel < fuel, "fuel used (%.2f L)" % (fuel - v.fuel))
	var yaw := _yaw(v)
	await _drive(v, 0.6, 1.0, false, 2.0)
	var turned := rad_to_deg(wrapf(_yaw(v) - yaw, -PI, PI))
	check(turned < -20.0, "steering right turns it right (%.0f degrees)" % turned)
	await _drive(v, 0.0, 0.0, true, 3.0)
	check(absf(v.forward_speed()) < 0.4 and v.linear_velocity.length() < 0.6, "the brakes stop it (%.2f m/s)" % v.linear_velocity.length())
	check(v.global_basis.y.dot(Vector3.UP) > 0.98, "still upright")
	v.server_exit(player)


func _test_drive_tracked() -> void:
	print("Driving: tracked (AAV-7)")
	var v := _vehicle("range_aav7")
	await _reset(v, Vector3(13, 0, 6))
	v.server_enter(player, 0)
	var start := v.global_position
	await _drive(v, 1.0, 0.0, false, 5.0)
	var moved := (v.global_position - start).dot(Vector3.FORWARD)
	check(v.forward_speed() > 4.0 and moved > 10.0, "full throttle for 5 s: %.1f m/s, %.1f m forward" % [v.forward_speed(), moved])
	await _drive(v, 0.0, 0.0, true, 3.0)
	check(v.linear_velocity.length() < 0.6, "the brakes stop it")
	var yaw := _yaw(v)
	var pivot := v.global_position
	await _drive(v, 0.0, 1.0, false, 2.0)
	var turned := rad_to_deg(wrapf(_yaw(v) - yaw, -PI, PI))
	check(turned < -30.0 and v.global_position.distance_to(pivot) < 1.5,
		"skid steering turns it on the spot (%.0f degrees, moved %.2f m)" % [turned, v.global_position.distance_to(pivot)])
	await _drive(v, 0.0, 0.0, true, 1.0)
	v.server_exit(player)


func _test_seats() -> void:
	print("Seats")
	var v := _vehicle("range_maxxpro")
	await _reset(v, Vector3(-4, 0, 6))
	check(v.server_enter(player, 0), "in as driver")
	check(v.server_switch(player, 1) and v.seat_of(player) == 1 and v.occupant(0) == null, "switches to the commander's seat")
	check(not v.server_switch(player, 1), "can't switch to the seat you're in")
	var four: Array[Soldier] = []
	for i in 4:
		four.append(_soldier("friendly", v.global_position + Vector3(3.0, 0.1, -2.0 + i)))
	await get_tree().physics_frame
	var all_in := four.all(func(s: Soldier) -> bool: return v.server_enter(s))
	check(all_in and v.occupants().size() == 5, "carries 4 more (%d aboard)" % v.occupants().size())
	check(four.all(func(s: Soldier) -> bool: return v.seat_kind(v.seat_of(s)) == Vehicle.PASSENGER), "AI take passenger seats first")
	await get_tree().process_frame
	check(four.all(func(s: Soldier) -> bool: return s.collision_layer == 0 and not s.model.visible and SquadAI.of(s).process_mode == Node.PROCESS_MODE_DISABLED),
		"riders don't collide, are hidden inside, and their AI waits")
	v.server_switch(player, 0)
	var start := v.global_position
	await _drive(v, 1.0, 0.0, false, 2.5)
	await _drive(v, 0.0, 0.0, true, 2.0)
	await get_tree().process_frame
	var rode := four.all(func(s: Soldier) -> bool: return s.global_position.distance_to(v.seat_transform(str(v.seat_of(s))).origin) < 0.05)
	check(v.global_position.distance_to(start) > 4.0 and rode, "they ride along at their seats (moved %.1f m)" % v.global_position.distance_to(start))
	var head_ok := four.all(func(s: Soldier) -> bool: return s.get_node(^"ChestHitbox") != null and VehicleSpecs.box(v.spec.boxes[2]).grow(0.2).has_point(v.to_local((s.get_node(^"ChestHitbox/Shape") as Node3D).global_position)))
	check(head_ok, "their hitboxes are inside the hull, where rounds that get through find them")
	v.server_exit(four[0])
	await get_tree().physics_frame
	var out := four[0]
	var hull_box := VehicleSpecs.box(v.spec.boxes[2])
	check(v.seat_of(out) < 0 and out.vehicle == null and out.collision_layer == Soldier.BODY_LAYER and out.model.visible
		and not hull_box.grow(0.25).has_point(v.to_local(out.global_position + Vector3.UP)) and absf(out.global_position.y - v.global_position.y) < 0.4,
		"one gets out by the rear door, on the ground beside it, solid and seen again")
	# Command menu: Mount > Get out, then Get in.
	var names := PackedStringArray(four.map(func(s: Soldier) -> String: return String(s.name)))
	check(layer.server_order_dismount(player, names) == "" and four.all(func(s: Soldier) -> bool: return v.seat_of(s) < 0),
		"Mount > Get out puts the riders out")
	await get_tree().physics_frame
	var far := four[3]
	far.global_position = v.global_position + Vector3(0.5, 0.1, 13)
	SquadAI.of(far).process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().physics_frame
	check(layer.server_order_mount(player, v.global_position, names) == "", "Mount > Get in, at the MaxxPro")
	var near_in := four.slice(0, 3).all(func(s: Soldier) -> bool: return v.seat_of(s) >= 0)
	check(near_in and layer.boarding_count() == 1, "the three beside it get in at once; the far one walks to a door")
	await _wait_for(func() -> bool: return v.seat_of(far) >= 0, 25.0)
	check(v.seat_of(far) >= 0, "and gets in when he's there")
	layer.server_order_dismount(player, names)
	for s in four:
		s.queue_free()
	v.server_exit(player)
	await get_tree().physics_frame
	check(player.vehicle == null and player.movement.stance == SoldierMovement.Stance.STAND_HIGH, "the player gets out standing")
	# Bodies: a casualty loaded into a seat, then pulled out.
	var hurt := _soldier("friendly", v.global_position + Vector3(0, 0.1, 4.5))
	hurt.vitals.server_damage(140.0)
	await _wait_for(func() -> bool: return hurt.vitals.downed, 3.0)
	player.global_position = v.global_position + Vector3(0.5, 0.1, 4.2)
	await get_tree().physics_frame
	check(player.server_pick_up_body(hurt, Soldier.CARRY), "carrying a casualty to the rear door")
	v.request_load_body(-1)
	await get_tree().process_frame
	await get_tree().process_frame
	check(v.seat_kind(v.seat_of(hurt)) == Vehicle.PASSENGER and player.carrying == null and not is_instance_valid(hurt.ragdoll),
		"Load casualty: in a passenger seat, no ragdoll")
	hurt.vitals.server_kill()
	for i in 4:
		await get_tree().physics_frame
	check(hurt.vitals.is_dead() and v.seat_kind(v.seat_of(hurt)) == Vehicle.PASSENGER and not is_instance_valid(hurt.ragdoll),
		"a casualty who dies on the way rides on in the seat (not put out by the road)")
	v.request_pull_out(v.seat_of(hurt))
	check(v.seat_of(hurt) < 0, "Pull out: out again")
	hurt.queue_free()
	# The dead are carried home too: a body loaded already dead stays in its seat.
	var fallen := _soldier("friendly", v.global_position + Vector3(0.5, 0.1, 4.6), "Fallen")
	fallen.vitals.server_kill()
	await _wait_for(func() -> bool: return fallen.is_in_group(Soldier.DEAD_GROUP), 3.0)
	await get_tree().physics_frame
	var rear_door: VehicleActionPoint = null
	for p in v.get_children():
		var ap := p as VehicleActionPoint
		if ap and ap.kind == VehicleActionPoint.DOOR and (rear_door == null
				or ap.global_position.distance_to(player.global_position) < rear_door.global_position.distance_to(player.global_position)):
			rear_door = ap
	check(player.server_pick_up_body(fallen, Soldier.CARRY), "carrying a dead body to the rear door")
	var load_entry := _entry(InteractionMenu.actions_for(player, rear_door), "Load casualty") if rear_door else {}
	check(not load_entry.is_empty() and String(load_entry.disabled) == "", "the door offers Load casualty for the dead too")
	v.request_load_body(-1)
	for i in 6:
		await get_tree().physics_frame
	check(fallen.vitals.is_dead() and v.seat_kind(v.seat_of(fallen)) == Vehicle.PASSENGER and player.carrying == null,
		"the dead body rides in a passenger seat, and stays there")
	v.request_pull_out(v.seat_of(fallen))
	check(v.seat_of(fallen) < 0, "and is pulled out again")
	fallen.queue_free()
	# Helicopters: seats, but pilots are AI only (aircraft are AI-flown).
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), Vector3(30, 0, 40)), "", &"player", "test_heli")
	await get_tree().physics_frame
	check(heli != null and not heli.server_enter(player, 0) and heli.server_enter(player, 2), "a player can't take a UH-60 pilot's seat, only a crew or passenger seat")
	if heli:
		heli.server_exit(player)
		var pilot_door: Array = InteractionMenu.actions_for(player, heli.get_node(^"Point1")).map(func(a: Dictionary) -> String: return "%s (%s)" % [a.label, a.disabled])
		check(pilot_door == ["Get in (Aircraft are flown by AI pilots)", "Open bay doors ()", "Check vehicle ()"],
			"the pilot's door: one greyed Get in saying why, no 'Get in as pilot' (%s)" % [pilot_door])
		heli.queue_free()


## Captain, 2026-10-17: "that get anim is poor, it just floats up". Getting into a UH-60 cabin
## seat from beside its door is a real move (CharacterModel.BOARD): up the step onto the sill, a
## hand on the grab handle, in to the seat and down onto it; from far off (a mission's seating)
## there's no clip.
func _test_boarding() -> void:
	print("Boarding")
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), Vector3(60, 0, 100)), "", &"player", "test_boarding")
	await get_tree().physics_frame
	if heli == null:
		check(false, "spawned a UH-60 to board")
		return
	var seat := 13  # Bench 3: the aft bench's right half, in by the right door
	await _seconds(1.0)  # down on its wheels
	var s := _soldier("friendly", heli.to_global(Vector3(2.6, 0.1, -2.55)))
	await get_tree().physics_frame
	var sill_y := 0.6  # the cabin floor, in the helicopter's frame
	check(heli.server_enter(s, seat) and StringName(s.model.action_net.get("id", &"")) == CharacterModel.BOARD,
		"getting in beside the cabin door plays the boarding clip")
	var lowest := INF
	var highest := -INF
	var gripped := false
	var t0 := Soldier._now()
	while s.model.action_seconds() < CharacterModel.BOARD_STEP_S + 0.1 and Soldier._now() - t0 < 5.0:
		await get_tree().physics_frame
		lowest = minf(lowest, heli.to_local(s.global_position).y)
		highest = maxf(highest, heli.to_local(s.global_position).y)
		gripped = gripped or s.model.board_grip != Vector3.ZERO
	check(lowest < sill_y - 0.5 and highest > sill_y - 0.1,
		"he steps up from the ground onto the cabin floor (%.2f to %.2f m, sill %.2f)" % [lowest, highest, sill_y])
	check(gripped and s.model.is_boarding() and not s.model.is_seated(), "a hand on the grab handle, standing, not seated yet")
	await _seconds(4.0)
	var cushion: Variant = heli.seat_cushion(seat)
	var hips := heli.to_local(s.model.torso.global_position)
	check(s.model.is_seated() and not s.model.is_boarding() and cushion != null and hips.distance_to(cushion as Vector3) < 0.15,
		"then he sits down on his seat (hips %s, cushion %s)" % [hips, cushion])
	var far := _soldier("friendly", heli.to_global(Vector3(20, 0.1, 0)))
	await get_tree().physics_frame
	check(heli.server_enter(far, 4) and StringName(far.model.action_net.get("id", &"")) != CharacterModel.BOARD,
		"put in from far off (a mission's seating): just seated, no clip")
	heli.server_exit(s)
	check(s.model.action_net.is_empty() or StringName(s.model.action_net.get("id", &"")) != CharacterModel.BOARD, "out again: no clip left playing")
	heli.server_exit(far)
	s.queue_free()
	far.queue_free()
	await _test_ffv_crouch(heli)
	heli.queue_free()


## Captain, 2026-10-17: hot drops by fast-rope (a rider to the door, down the rope to the ground
## under it, out there), and the briefing's choice of the edge a helicopter comes in from.
func _test_fast_rope() -> void:
	print("Fast-rope and the way in")
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), level.ground_point(Vector3(60, 0, 100)) + Vector3.UP * 0.3), "", &"player", "test_rope")
	await _seconds(1.0)
	if heli == null:
		check(false, "spawned a UH-60 to rope from")
		return
	var s := _soldier("friendly", heli.to_global(Vector3(20, 0.1, 0)))
	await get_tree().physics_frame
	heli.server_enter(s, 11)
	heli.ropes_out = true
	heli.server_fast_rope(s, -1.0)
	await _seconds(0.3)
	var rope := heli.get_node_or_null(^"Rope0") as Node3D
	check(rope != null and rope.visible and bool(s.model.action_net.get("rope", false)), "the ropes are out and he's on his way down one")
	var t0 := Soldier._now()
	while heli.seat_of(s) >= 0 and Soldier._now() - t0 < 6.0:
		await get_tree().physics_frame
	var at := heli.to_local(s.global_position)  # the moment he's let go
	var floor_y := level.ground_point(s.global_position).y
	check(heli.seat_of(s) < 0 and at.x < -1.4 and absf(s.global_position.y - floor_y) < 1.0,
		"and is off the rope under the left door, on the ground (%s, %.2f m over it)" % [at, s.global_position.y - floor_y])
	heli.ropes_out = false
	# Flares (Captain, 2026-10-17): a salvo from the dispensers, then a gap before the next.
	var helo := heli as Helicopter
	if helo:
		var load0 := helo.flares_left
		check(helo.server_pop_flares() and helo.flares_left == load0 - Helicopter.FLARE_SALVO and int(helo.net_flight.get("flares", 0)) == 1,
			"flares: a salvo of %d, told to every peer" % Helicopter.FLARE_SALVO)
		check(not helo.server_pop_flares() and helo.flares_left == load0 - Helicopter.FLARE_SALVO, "and not another inside %.0f s" % Helicopter.FLARE_GAP_S)
	s.queue_free()
	heli.queue_free()
	var lz := Vector3(0, 0, 0)
	var south := HeliRoute.entry(level, lz, [], 20.0, 0.0, 2)  # (the range is too small for the usual inset)
	var north := HeliRoute.entry(level, lz, [], 20.0, 0.0, 0)
	check((south.at as Vector3).z > 0.0 and (north.at as Vector3).z < 0.0, "a chosen side is where it comes in from (south %s, north %s)" % [south.at, north.at])


## Captain, 2026-10-17: the helicopters show their pilots (drawn, at the controls); the Petrel's
## gun is a belly turret worked from the co-pilot's seat, which doesn't turn with it.
func _test_crew_and_belly_turret() -> void:
	print("Crew and belly turret")
	var uh := layer.server_spawn("uh60", Transform3D(Basis(), Vector3(-60, 0, 100)), "", &"player", "test_crew_uh60")
	var pe := layer.server_spawn("vtol_petrel", Transform3D(Basis(), Vector3(-90, 0, 100)), "", &"player", "test_crew_petrel")
	await get_tree().physics_frame
	if uh == null or pe == null:
		check(false, "spawned a UH-60 and a Petrel")
		return
	check(uh.get_node_or_null(^"Crew0") != null and uh.get_node_or_null(^"Crew1") != null, "the UH-60 shows both pilots")
	check(pe.get_node_or_null(^"Crew0") != null and pe.get_node_or_null(^"Crew1") == null and pe.seat_kind(1) == Vehicle.GUNNER,
		"the Petrel shows its pilot; the co-pilot's seat is the gunner's")
	check(pe.gun_info().get("id", "") == "m2hb" and int(pe.gun_info().seat) == 1 and pe.turret != null, "its gun is a .50 cal belly turret, worked from seat 1")
	var g := _soldier("friendly", pe.to_global(Vector3(-3, 0.1, -5.6)))
	await get_tree().physics_frame
	check(pe.server_enter(g, 1), "a gunner takes the co-pilot's seat")
	var eye := pe.to_local(pe.seat_eye_point(1))
	pe.turret.aim(1.0, -0.3)
	for i in 60:
		await get_tree().physics_frame
	check(absf(pe.turret.yaw - 1.0) < 0.1 and pe.to_local(pe.seat_eye_point(1)).distance_to(eye) < 0.01,
		"the turret turns (%.2f rad) under him; his seat stays put" % pe.turret.yaw)
	pe.server_exit(g)
	g.queue_free()
	uh.queue_free()
	pe.queue_free()


## Captain, 2026-10-17: AI take the FFV door seats first; with the doors shut an FFV rider
## crouches behind the door, and sits (on the sill, legs out, the UH-60's) as they open.
func _test_ffv_crouch(heli: Vehicle) -> void:
	heli.server_set_bay(false)
	await _seconds(1.0)
	var ai := _soldier("friendly", heli.to_global(Vector3(20, 0.1, 0)))
	await get_tree().physics_frame
	var ffv := 15
	check(heli.server_enter(ai, ffv) and String(heli.spec.seats[heli.seat_of(ai)].get("ffv", "")) != "",
		"an AI in an FFV door seat (%s)" % heli.seat_name(heli.seat_of(ai)))
	await _seconds(0.3)
	var crouched_y := heli.to_local(ai.model.torso.global_position).y
	check(ai.model.is_boarding() and not ai.model.is_seated(), "doors shut: crouched behind the door, not sat in it")
	heli.server_set_bay(true)
	await _seconds(VehicleBay.PANEL_S + 0.4)
	var hips := heli.to_local(ai.model.torso.global_position)
	var cushion: Variant = heli.seat_cushion(heli.seat_of(ai))
	check(ai.model.is_seated() and cushion != null and hips.distance_to(cushion as Vector3) < 0.15,
		"doors open: sat on the sill (hips %s, from crouched at %.2f m)" % [hips, crouched_y])
	var feet_y := heli.to_local(ai.model._shin_left.global_transform * Vector3(0, -(CharacterModel.LEG_LENGTH - CharacterModel.THIGH), 0)).y
	check(feet_y < 0.6 - 0.2, "legs hanging off the edge (feet %.2f m, floor 0.6)" % feet_y)
	# Captain, 2026-10-17: AI run out of the doors rather than appearing beside the hull.
	heli.server_run_out(ai)
	check(heli.seat_of(ai) >= 0 and bool(ai.model.action_net.get("out", false)), "told to get out: he runs for the door (still aboard)")
	await _seconds(Vehicle.RUN_OUT_SIT_S + Vehicle.RUN_OUT_STEP_S + 1.5)
	var at := heli.to_local(ai.global_position)
	check(heli.seat_of(ai) < 0 and absf(at.x) > 1.6 and at.y < 0.2, "and is out on the ground at the foot of the step (%s)" % at)
	ai.queue_free()


## Captain, 2026-10-14 (v0.4.0, inside a UH-60M): the riders stood in their seats, through each
## other and the seat frames, rifles pointing across the cabin. Every sitting seat now seats its
## rider: hips on the cushion, head at seated height, feet on the floor under the seat, a rifle
## muzzle down (stations: slung, hands on the controls), and no two upper bodies overlapping.
func _test_seated() -> void:
	print("Seated riders")
	var shin := CharacterModel.LEG_LENGTH - CharacterModel.THIGH
	var standing_head := CharacterModel.TORSO_PIVOT.y + CharacterModel.HEAD_PIVOT.y
	var spawned: Array[Vehicle] = []
	var riders: Array[Soldier] = []
	var k := 0
	for m: String in ["uh60", "matv", "maxxpro", "technical_dshk", "aav7"]:
		var v := layer.server_spawn(m, Transform3D(Basis(), Vector3(-40.0 + 14.0 * k, 0, 70)), "", &"player", "test_seated_" + m)
		k += 1
		if v == null:
			check(false, "spawned a %s" % m)
			continue
		spawned.append(v)
		var defs: Array = v.spec.seats
		for i in mini(defs.size(), 15):  # not the UH-60's FFV door seats (crouched with its doors shut: _test_ffv_crouch)
			if String(defs[i].get("stance", "sit")) in ["stand", "kneel"]:
				continue
			var s := _soldier("friendly", v.global_position + Vector3(4.0, 0.1, -2.0 + 0.5 * i))
			riders.append(s)
			await get_tree().physics_frame
			v.server_enter(s, i)
	await _seconds(4.0)  # boarded (Vehicle.BOARD_FROM_M: they start by the doors), settled on their springs, rifles in hands
	for v in spawned:
		var label := v.short_name()
		var cushion_err := 0.0
		var head_over := -INF
		var feet_ok := true
		var muzzle_dot := INF
		var stations_slung := true
		var boxes: Array[AABB] = []
		var seated := 0
		var worst := ""
		for i in v.seat_count():
			var s := v.occupant(i)
			var cushion: Variant = v.seat_cushion(i)
			if s == null or cushion == null:
				continue
			seated += 1
			var floor_y := v.seat_floor(i)
			var pelvis := v.to_local(s.model.torso.global_position)  # the upper body's pivot is the hips
			var err := pelvis.distance_to(cushion as Vector3)
			if err > cushion_err:
				cushion_err = err
				worst = "seat %d at %s, hips at %s" % [i, cushion, pelvis]
			head_over = maxf(head_over, v.to_local(s.model.head.global_position).y - (cushion as Vector3).y)
			for leg: Node3D in [s.model._shin_left, s.model._shin_right]:
				var sole := v.to_local(leg.global_transform * Vector3(0, -shin, 0))
				if sole.y < floor_y - 0.04 or sole.y > (cushion as Vector3).y:
					feet_ok = false
					worst += " / seat %d sole %.2f (floor %.2f, cushion %.2f)" % [i, sole.y, floor_y, (cushion as Vector3).y]
			if bool(v._seat_poses[i].get("station", false)):
				stations_slung = stations_slung and s.model.hold == CharacterModel.Hold.NONE
			else:
				var held: Node3D = s.model._held
				muzzle_dot = minf(muzzle_dot, (-held.global_basis.z).normalized().dot(Vector3.DOWN) if is_instance_valid(held) else -1.0)
			# The torso's box (VoxelArt torso: 0.52 x 0.66 x 0.22 m about its pivot), in the vehicle's frame.
			var t := v.global_transform.affine_inverse() * s.model.torso.global_transform
			var box := AABB(t * Vector3(-0.26, -0.1, -0.11), Vector3.ZERO)
			for c in 8:
				box = box.expand(t * Vector3(0.26 if c & 1 else -0.26, 0.56 if c & 2 else -0.1, 0.11 if c & 4 else -0.11))
			boxes.append(box)
		var overlaps := 0
		for a in boxes.size():
			for b in range(a + 1, boxes.size()):
				if boxes[a].grow(-0.005).intersects(boxes[b].grow(-0.005)):
					overlaps += 1
		check(seated > 0 and cushion_err < 0.15, "%s: %d riders' hips on their seats (worst %.2f m: %s)" % [label, seated, cushion_err, worst])
		# Over the cushion, not the floor: a commander's seat is up in his cupola, over the cabin floor.
		var stood := standing_head - (Vehicle.seat_eye("sit") - VehicleInteriors.CUSHION_DROP)  # standing where he sits: head over the cushion
		check(head_over < stood - 0.2, "%s: their heads at seated height (%.2f m over the seat; standing %.2f)" % [label, head_over, stood])
		check(feet_ok, "%s: feet on the floor, under the seat %s" % [label, worst])
		if muzzle_dot != INF:
			check(muzzle_dot > 0.5, "%s: rifles muzzle down (worst dot with down %.2f)" % [label, muzzle_dot])
		check(stations_slung, "%s: drivers, pilots and gunners have their rifles slung" % label)
		check(overlaps == 0, "%s: no two riders' upper bodies overlap (%d)" % [label, overlaps])
	# Out again: standing, no seat pose left on them.
	var heli := spawned[0] if not spawned.is_empty() else null
	if heli:
		var out := heli.occupant(11)  # the aft bench
		heli.server_exit(out)
		for i in 3:
			await get_tree().process_frame
		check(out != null and out.seat_pose.is_empty() and not out.model.is_seated(), "out of the seat, not drawn seated")
	for v in spawned:
		for s: Soldier in v.occupants():
			v.server_exit(s)
	for s in riders:
		s.queue_free()
	for v in spawned:
		v.queue_free()
	await get_tree().physics_frame


func _test_cargo() -> void:
	print("Cargo")
	var v := _vehicle("range_technical")
	await _reset(v, Vector3(4, 0, 6))
	var hold := v.cargo() as VehicleCargo
	check(hold != null and is_equal_approx(hold.capacity_l, 1100.0) and is_equal_approx(hold.max_kg, 900.0), "the technical's bed: 1100 L, 900 kg")
	player.global_position = v.global_position + Vector3(0, 0.1, 3.4)
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"repair_kit")
	await get_tree().physics_frame
	var c := _find_entry(player.inventory, &"repair_kit")
	check(v.in_reach(player), "the player stands at the cargo point")
	v.request_cargo_load(c[0], c[1], &"repair_kit")
	check(hold.count_of(&"repair_kit") == 1 and player.inventory.count_of(&"repair_kit") == 0, "Load: a repair kit into the bed")
	v.request_cargo_take(_hold_index(hold, &"repair_kit"), &"repair_kit")
	check(hold.count_of(&"repair_kit") == 0 and player.inventory.count_of(&"repair_kit") == 1, "Cargo > take it back")
	player.inventory.take(&"supply_crate")
	check(player.inventory.hands == &"supply_crate", "carrying a supply crate (two hands)")
	v.request_cargo_load(&"", -1, &"supply_crate")
	check(hold.count_of(&"supply_crate") == 1 and player.inventory.hands == &"", "a crate in your hands goes in too")
	var belts := hold.take(&"belt_50bmg", 200)
	check(belts > 0 and hold.total_mass() <= hold.max_kg + 0.01 and hold.take(&"belt_50bmg", 1) == 0,
		"the mass limit: %d belts fit, %.0f of %.0f kg" % [belts, hold.total_mass(), hold.max_kg])
	hold.clear_all()
	var bulk := hold.take(&"electronics_salvage", 5000)
	check(bulk > 0 and hold.used_litres() <= hold.capacity_l + 0.01 and hold.take(&"electronics_salvage", 1) == 0,
		"the litre limit: %d units, %.0f of %.0f L" % [bulk, hold.used_litres(), hold.capacity_l])
	hold.clear_all()
	hold.take(&"belt_127x108", 2)
	player.inventory.strip()
	player.inventory.take(&"m4a1")


static func _find_entry(inv: Inventory, id: StringName) -> Array:
	for c: StringName in inv.search_containers():
		var list: Array = inv.containers[c]
		for i in list.size():
			if list[i].id == id:
				return [c, i]
	return [&"", -1]


static func _hold_index(hold: VehicleCargo, id: StringName) -> int:
	var list := hold.entries()
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


## The entry of `actions` (or of any submenu in them) whose label starts with `label`, or {}.
static func _entry(actions: Array, label: String) -> Dictionary:
	for a: Dictionary in actions:
		if String(a.label).begins_with(label):
			return a
		for sub: Dictionary in a.get("items", []):
			if String(sub.label).begins_with(label):
				return sub
	return {}


func _test_interaction() -> void:
	print("Left Ctrl: the vehicle's action points")
	var v := _vehicle("range_maxxpro")
	await _reset(v, Vector3(-4, 0, 6))
	var door := v.get_node(^"Point0") as VehicleActionPoint
	player.global_position = v.global_transform * Vector3(-2.6, 0.1, -1.0)
	var to := door.global_position - (player.global_position + Vector3.UP * 1.6)
	player.rotation.y = atan2(-to.x, -to.z)
	player.set_pitch(atan2(to.y, Vector2(to.x, to.z).length()))
	await get_tree().process_frame
	await get_tree().physics_frame
	var points := InteractionMenu.collect_points(player, player.camera)
	check(points.any(func(p: Dictionary) -> bool: return p.target == door), "looking at the driver's door shows its action point")
	check(InteractionMenu.target_kind(player, door) == InteractionMenu.OBJECT, "an interactable, like the base's terminals")
	var acts := InteractionMenu.actions_for(player, door)
	var get_in := _entry(acts, "Get in as driver")
	check(not get_in.is_empty() and String(get_in.disabled) == "" and not _entry(acts, "Check vehicle").is_empty(),
		"the door offers Get in as driver and Check vehicle (%s)" % [acts.map(func(a: Dictionary) -> String: return a.label)])
	InteractionMenu.perform(player, get_in)
	check(v.seat_of(player) == 0, "picking it seats the player through the host request")
	var seat_point := v.get_node(^"Seat0") as VehicleActionPoint
	acts = InteractionMenu.actions_for(player, seat_point)
	check(not _entry(acts, "Get out").is_empty() and not _entry(acts, "Commander").is_empty(), "inside, the seat's point offers Get out and Move to (%s)" % [acts.map(func(a: Dictionary) -> String: return a.label)])
	check(InteractionMenu.actions_for(player, door).is_empty(), "and the doors offer nothing to someone inside")
	InteractionMenu.perform(player, _entry(acts, "Commander"))
	check(v.seat_of(player) == 1, "Move to > Commander")
	InteractionMenu.perform(player, _entry(InteractionMenu.actions_for(player, v.get_node(^"Seat1")), "Get out"))
	check(v.seat_of(player) < 0, "Get out")
	await _test_get_out_key(v)
	await _test_door_declutter(v)
	var cargo := v.get_node(^"Point3") as VehicleActionPoint
	player.global_position = cargo.global_position + Vector3(0, -1.5, 0.8)
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"engine_parts")
	await get_tree().physics_frame
	acts = InteractionMenu.actions_for(player, cargo)
	var load := _entry(acts, "Engine Parts")
	check(not load.is_empty() and not _entry(acts, "Cargo (").is_empty(), "the cargo point lists the hold and what you can load (%s)" % [acts.map(func(a: Dictionary) -> String: return a.label)])
	InteractionMenu.perform(player, load)
	check(v.cargo_hold.count_of(&"engine_parts") == 1 and player.inventory.count_of(&"engine_parts") == 0, "Load > Engine Parts puts them in the hold")
	acts = InteractionMenu.actions_for(player, cargo)
	InteractionMenu.perform(player, _entry((_entry(acts, "Cargo (").get("items", []) as Array), "Engine Parts"))
	check(v.cargo_hold.count_of(&"engine_parts") == 0 and player.inventory.count_of(&"engine_parts") == 1, "Cargo > Engine Parts takes them out again")
	var service := v.get_node(^"Point4") as VehicleActionPoint
	player.global_position = service.global_position + Vector3(0, -1.6, -0.8)
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.3)
	await get_tree().physics_frame
	acts = InteractionMenu.actions_for(player, service)
	var fix := _entry(acts, "Engine Parts: engine")
	check(not fix.is_empty(), "the service point offers to fit the engine parts you carry (%s)" % [acts.map(func(a: Dictionary) -> String: return a.label)])
	player.inventory.take(&"repair_kit")
	var ring := InteractionMenu.grouped(InteractionMenu.actions_for(player, service))
	var repairs: Array = _entry(ring, "Repair").get("items", [])
	check(ring.size() == 2 and repairs.map(func(a: Dictionary) -> String: return a.label) == ["Engine Parts: engine", "Vehicle Repair Kit: engine"]
		and ring[1].label == "Check vehicle", "two repairs share one Repair submenu on the ring, then Check vehicle (%s)" % [ring.map(func(a: Dictionary) -> String: return a.label)])
	InteractionMenu.perform(player, fix)
	check(v.job_left(player) > 55.0, "a timed job (%.0f s)" % v.job_left(player))
	player.global_position += Vector3(0, 0, -3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(v.job_left(player) == 0.0, "walking off stops it")
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	v.server_set_zone(Vehicle.ZONE_ENGINE, 1.0)


## The get-out key (Captain, P0164 queue 8: an option, with the menu decluttered for it): on,
## V gets you out and the seat's menu has no Get out (the HUD line names the key); off, V does
## nothing and Get out is in the menu.
func _test_get_out_key(v: Vehicle) -> void:
	print("The get-out key (an option)")
	var bound := InputMap.action_get_events(ControlOptions.GET_OUT_ACTION)
	check(bound.size() == 1 and bound[0] is InputEventKey and (bound[0] as InputEventKey).physical_keycode == KEY_V and ControlOptions.get_out_key_name() == "V",
		"get_out is bound to V (%s)" % ControlOptions.get_out_key_name())
	var clashes := InputMap.get_actions().filter(func(action: StringName) -> bool:  # the engine's ui_* text-field keys (Ctrl+V paste) aside
		return action != ControlOptions.GET_OUT_ACTION and not String(action).begins_with("ui_") and InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
			return e is InputEventKey and ((e as InputEventKey).physical_keycode == KEY_V or (e as InputEventKey).keycode == KEY_V)))
	check(clashes.is_empty(), "and V does nothing else (%s)" % [clashes])
	check(not ControlOptions.GET_OUT_DEFAULT and not ControlOptions.get_out_key(), "off unless the player turns it on")
	var press := InputEventAction.new()
	press.action = ControlOptions.GET_OUT_ACTION
	press.pressed = true
	check(v.server_enter(player, 0), "back in the driver's seat")
	player.player_input._unhandled_input(press)
	await get_tree().physics_frame
	check(v.seat_of(player) == 0, "off: V does nothing")
	ControlOptions._get_out = true
	var labels: Array = InteractionMenu.actions_for(player, v.get_node(^"Seat0")).map(func(a: Dictionary) -> String: return a.label)
	check(labels == ["Move to", "Check vehicle"], "on: the seat's menu has no Get out (%s)" % [labels])
	check(v.readout(0).ends_with("V: get out"), "and the HUD line names the key (%s)" % v.readout(0))
	var pause := player.player_input.pause_menu
	pause.open()
	check(pause.get_out_toggle.button_pressed and pause.get_out_toggle.text.contains("with V"), "the Escape menu shows the option, on (%s)" % pause.get_out_toggle.text)
	pause.close()
	player.player_input._unhandled_input(press)
	await get_tree().physics_frame
	check(v.seat_of(player) < 0 and Vehicle.ride_of(player) == null, "on: V gets you out")
	ControlOptions._get_out = false
	check(not v.readout(0).contains("get out"), "off: the HUD line doesn't mention it")


## A door's ring (Captain, P0164 queue 8): Get in for each kind of seat it has free, no greyed
## "Driver taken"; one greyed Get in saying why when nothing's free; bodies down in its seats
## under Pull out (one submenu once there are two); Check vehicle last.
func _test_door_declutter(v: Vehicle) -> void:
	print("A door's ring, decluttered")
	var shown := func(point: Node) -> Array:
		return InteractionMenu.actions_for(player, point).map(func(a: Dictionary) -> String: return a.label + (" (%s)" % a.disabled if a.disabled != "" else ""))
	var door := v.get_node(^"Point0") as VehicleActionPoint
	var rear := v.get_node(^"Point2") as VehicleActionPoint
	player.global_position = rear.global_position + Vector3(0, -1.8, 1.0)  # at the rear door (Pull out checks reach)
	check(shown.call(door) == ["Get in as driver", "Check vehicle"], "the driver's door: Get in as driver, Check vehicle (%s)" % [shown.call(door)])
	check(shown.call(rear) == ["Get in as gunner", "Get in", "Check vehicle"], "the rear door: gunner, then the troop seats (%s)" % [shown.call(rear)])
	var driver := _soldier("friendly", v.global_position + Vector3(-4, 0.1, -1), "DoorDriver")
	check(v.server_enter(driver, 0), "someone else takes the wheel")
	check(shown.call(door) == ["Get in (No free seat on this side)", "Check vehicle"], "then one greyed Get in, no 'Driver taken' (%s)" % [shown.call(door)])
	v.burning_s = 30.0
	check(shown.call(rear) == ["Get in (It's on fire)", "Check vehicle"], "on fire: one greyed Get in, not one per seat (%s)" % [shown.call(rear)])
	v.burning_s = 0.0
	var riders: Array[Soldier] = []
	for seat in [2, 3]:
		var rider := _soldier("friendly", v.global_position + Vector3(4, 0.1, seat), "DoorRider%d" % seat)
		v.server_enter(rider, seat)
		rider.vitals.server_damage(500.0)
		riders.append(rider)
	await get_tree().physics_frame
	var ring := InteractionMenu.grouped(InteractionMenu.actions_for(player, rear))
	var pull: Array = _entry(ring, "Pull out").get("items", [])
	check(ring.map(func(a: Dictionary) -> String: return a.label) == ["Get in as gunner", "Get in", "Pull out", "Check vehicle"]
		and pull.map(func(a: Dictionary) -> String: return a.label) == riders.map(func(s: Soldier) -> String: return s.display_name()),
		"two bodies down inside: one Pull out submenu naming them (%s; %s)" % [ring.map(func(a: Dictionary) -> String: return a.label), pull.map(func(a: Dictionary) -> String: return a.label)])
	if not pull.is_empty():
		InteractionMenu.perform(player, pull[0])
	check(v.seat_of(riders[0]) < 0, "and picking one pulls them out")
	ring = InteractionMenu.grouped(InteractionMenu.actions_for(player, rear))
	check(ring.any(func(a: Dictionary) -> bool: return a.label == "Pull out %s" % riders[1].display_name() and not a.has("items")),
		"one left: Pull out on the ring itself (%s)" % [ring.map(func(a: Dictionary) -> String: return a.label)])
	for s: Soldier in [driver] + riders:
		v.server_exit(s)
		s.queue_free()
	await get_tree().physics_frame


func _test_charge() -> void:
	print("A charge on a vehicle")
	# Its own technical: the range's is needed whole by the checks after this one.
	var v := layer.server_spawn("technical_dshk", Transform3D(Basis(), Vector3(-25, 0, 32)), "", &"player", "test_charge_target")
	for i in 3:
		await get_tree().physics_frame
	var charges := Charges.of(level)
	var side := v.global_transform * Vector3(-1.5, 0.9, -0.3)
	player.global_position = side + Vector3(-0.2, -0.9, 0)
	player.inventory.take(Charges.ITEM)
	await get_tree().physics_frame
	var eye := side + Vector3(0, 0.5, 0)
	var spot := Charges.placement(player, eye, (v.global_transform * Vector3(-0.9, 0.9, -0.3) - eye).normalized())
	check(spot.ok and spot.target == v, "a breaching charge can be placed on the technical's door (it rides the vehicle)")
	var hull_before := v.zone_health(Vehicle.ZONE_HULL)
	var scorched := func() -> int: return v.net_carves.filter(func(op: Array) -> bool: return int(op[4]) == VehicleHull.SCORCH).size()
	var scorches_before: int = scorched.call()
	var id := charges.server_place_at(player, Charges.surface_transform(spot.pos, spot.normal, Vector3.RIGHT), spot.target)
	player.global_position += Vector3(-15, 0, 0)
	await get_tree().physics_frame
	charges._detonate(id)
	check(v.zone_health(Vehicle.ZONE_HULL) < hull_before and int(scorched.call()) > scorches_before,
		"it goes off on the vehicle: Vehicle.server_explosion damages and scorches it (hull %.0f%%)" % (v.zone_health(Vehicle.ZONE_HULL) * 100.0))
	v.queue_free()
	await get_tree().physics_frame


## Fires `weapon` from `from` at `to` as `shooter`: Ballistics' result.
func _shoot(shooter: Soldier, from: Vector3, to: Vector3, weapon: ItemData) -> Dictionary:
	return Ballistics.fire(shooter, from, (to - from).normalized(), weapon)


func _test_rounds() -> void:
	print("Rounds against armour")
	var mrap := _vehicle("range_maxxpro")
	var tech := _vehicle("range_technical")
	await _reset(mrap, Vector3(-4, 0, 6))
	await _reset(tech, Vector3(4, 0, 6))
	var shooter := _soldier("hostile", Vector3(-8, 0.1, 12), "Shooter")
	var rider := _soldier("friendly", mrap.global_position + Vector3(3, 0.1, 0), "MrapRider")
	await get_tree().physics_frame
	mrap.server_enter(rider, 2)  # troop seat, left side
	await get_tree().process_frame
	var chest := (rider.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	var from := chest + Vector3(-3.5, 0, 0)  # from the left, between the M-ATV and the MaxxPro
	var m4 := ItemDB.get_item(&"m4a1")
	var m110 := ItemDB.get_item(&"m110")
	var carves := mrap.net_carves.size()
	var r := _shoot(shooter, from, chest, m4)
	check(r.result == "vehicle" and rider.vitals.wound_list().is_empty() and mrap.zone_health(Vehicle.ZONE_CREW) == 1.0,
		"5.56 bounces off the MaxxPro's crew compartment (%s), the rider behind it unhurt" % r.result)
	r = _shoot(shooter, from, chest, m110)
	check(r.result == "vehicle" and rider.vitals.wound_list().is_empty(), "so does 7.62x51 (%s)" % r.result)
	check(mrap.net_carves.size() == carves + 2 and int(mrap.net_carves[-1][4]) == VehicleHull.SCUFF, "each leaves a scuff on the hull")
	var lps := _gun("762x54r_lps")
	r = _shoot(shooter, from, chest, lps)
	check(r.result == "vehicle" and rider.vitals.wound_list().is_empty(), "7.62x54R doesn't go through the MRAP's crew armour (%s)" % r.result)
	var engine := mrap.global_transform * Vector3(0.0, 1.3, -2.6)
	var matv_engine := _vehicle("range_matv").zone_health(Vehicle.ZONE_ENGINE)
	var marks := mrap.net_carves.size()
	r = _shoot(shooter, engine + Vector3(-3.5, 0, 0), engine, lps)
	check(mrap.net_carves.size() == marks + 1, "one round, one hit on the hull (%d marks)" % (mrap.net_carves.size() - marks))
	check(mrap.zone_health(Vehicle.ZONE_ENGINE) < 1.0 and int(mrap.net_carves[-1][4]) == VehicleHull.HOLE,
		"7.62x54R penetrates the MRAP's engine bay, its weak zone (engine %.0f%%)" % (mrap.zone_health(Vehicle.ZONE_ENGINE) * 100.0))
	check(_vehicle("range_matv").zone_health(Vehicle.ZONE_ENGINE) == matv_engine, "(nothing else was in the way)")
	var bmg := _gun("50bmg_m33")
	r = _shoot(shooter, from, chest, bmg)
	check(r.result == "body" and not rider.vitals.wound_list().is_empty(),
		".50 BMG goes through the MRAP's side and into the rider behind it (%s)" % r.result)
	mrap.server_exit(rider)
	rider.queue_free()
	# The technical: soft. 5.56 through the driver's door hits the driver.
	var driver := _soldier("hostile", tech.global_position + Vector3(-3, 0.1, 0), "TechDriver")
	await get_tree().physics_frame
	tech.server_enter(driver, 0)
	await get_tree().process_frame
	var dchest := (driver.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	check(VehicleSpecs.box(tech.spec.boxes[2]).has_point(tech.to_local(dchest)), "the technical's driver sits inside its cab box")
	var aim := dchest + Vector3(0, -0.2, 0)
	r = _shoot(shooter, aim + Vector3(-3.0, 0, 0), aim, m4)
	check(r.result == "body" and not driver.vitals.wound_list().is_empty() and tech.net_carves.size() > 0 and int(tech.net_carves[-1][4]) == VehicleHull.HOLE,
		"5.56 goes through the technical's door (a hole) and hits the driver (%s)" % r.result)
	var tengine := tech.global_transform * Vector3(0.0, 0.95, -2.2)
	r = _shoot(shooter, tengine + Vector3(-3.0, 0, 0), tengine, lps)
	check(tech.zone_health(Vehicle.ZONE_ENGINE) < 1.0, "7.62x54R penetrates the technical's engine (%.0f%%)" % (tech.zone_health(Vehicle.ZONE_ENGINE) * 100.0))
	tech.server_exit(driver)
	driver.queue_free()
	# The AAV-7 (IFV): proof against .50 on its sides.
	var aav := _vehicle("range_aav7")
	await _reset(aav, Vector3(13, 0, 6))
	var side := aav.global_transform * Vector3(-1.66, 1.8, 1.0)
	r = _shoot(shooter, side + Vector3(-3, 0, 0), side + Vector3(0.3, 0, 0), bmg)
	check(r.result == "vehicle" and aav.zone_health(Vehicle.ZONE_CARGO) == 1.0, ".50 BMG doesn't get through the AAV-7's side (%s)" % r.result)
	# A round through an open bed meets nobody's box but the passenger's.
	var bed_rider := _soldier("friendly", tech.global_position + Vector3(2.5, 0.1, 1.0), "BedRider")
	await get_tree().physics_frame
	tech.server_enter(bed_rider, 2)
	# Boarding places the origin before the next body pose and physics-server sync.
	# Aim after the sitting hitboxes have reached the seat, not at the old standing pose.
	await _seconds(0.1)
	check(tech.seat_of(bed_rider) == 2 and not bed_rider.seat_pose.is_empty(), "the open-bed passenger is seated before the shot")
	var bchest := (bed_rider.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	r = _shoot(shooter, bchest + Vector3(0, 6, 8), bchest, m4)
	if r.result != "body":
		print("  [info] open-bed shot: chest %s local %s, struck %s local %s, rider seated %d, wounds %d" % [bchest, tech.to_local(bchest), r.position, tech.to_local(r.position), tech.seat_of(bed_rider), bed_rider.vitals.wound_list().size()])
	check(r.result == "body" and not bed_rider.vitals.wound_list().is_empty(), "a passenger in the open bed can be shot from above and behind (%s)" % r.result)
	tech.server_exit(bed_rider)
	bed_rider.queue_free()
	shooter.queue_free()


## A body pierced before an armoured vehicle is still the shooter's body hit. Use a fresh
## hull and a full-power round so both body types reliably exit into a stopping backstop.
func _test_body_vehicle_feedback() -> void:
	print("A body before an armoured backstop")
	var backstop := layer.server_spawn("aav7", Transform3D(Basis(), Vector3(32, 0, -20)), "", &"player", "feedback_backstop")
	var shooter := _soldier("hostile", Vector3(-20, 0.1, -20), "FeedbackShooter")
	await _seconds(0.25)
	for body_type: String in VoxelArt.BODIES:
		var victim := level.spawn_soldier({"name": "BeforeHull_" + body_type, "person_name": "Feedback " + body_type,
			"faction": "friendly", "variant": "woodland", "body": body_type, "pos": Vector3(28, 0.1, -19),
			"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(victim).process_mode = Node.PROCESS_MODE_DISABLED
		victim.set_physics_process(false)
		victim.rotation.y = PI / 2.0
		await _seconds(0.1)
		var at := backstop.global_transform * Vector3(-1.66, 1.8, 1.0) + Vector3(-2, 0, 0)
		victim.global_position += at - CharacterModel.part_position(victim, Vitals.CHEST)
		await _seconds(0.1)
		await get_tree().physics_frame
		var chest := CharacterModel.part_position(victim, Vitals.CHEST)
		var marks := backstop.net_carves.size()
		var hit := _shoot(shooter, chest + Vector3(-3, 0, 0), chest, ItemDB.get_item(&"m110"))
		check(not victim.vitals.wound_list().is_empty(), "%s: the unarmoured body is wounded before the hull" % body_type)
		check(backstop.net_carves.size() == marks + 1 and int(backstop.net_carves[-1][4]) == VehicleHull.SCUFF,
			"%s: the round exits the body and the armoured backstop stops it" % body_type)
		check(hit.result == "body" and (hit.position as Vector3).distance_to(chest) < 0.8,
			"%s: feedback stays on the earlier body hit (%s)" % [body_type, hit.result])
		victim.queue_free()
		await get_tree().physics_frame
	backstop.queue_free()
	shooter.queue_free()
	await get_tree().process_frame


## Grenade fragments meet a vehicle's hull where its voxels are: an open pickup bed lets them in
## to the riders, an MRAP's armoured cab keeps them out.
func _test_fragments() -> void:
	print("Fragments against hulls")
	var tech := _vehicle("range_technical")
	var mrap := _vehicle("range_maxxpro")
	await _reset(tech, Vector3(4, 0, 6))
	await _reset(mrap, Vector3(-4, 0, 6))
	var space := tech.get_world_3d().direct_space_state
	var in_bed := tech.global_transform * Vector3(0.55, 1.0, 1.4)
	var hit := Throwables._first_hit(space, tech.global_transform * Vector3(0.55, 3.2, 1.4), in_bed)
	check(Vehicle.find_on(hit.get("collider")) == null, "a fragment falling into the technical's open bed isn't stopped by its collision box (%s)" % hit.get("collider"))
	var in_cab := mrap.global_transform * Vector3(0.0, 1.5, 0.0)
	hit = Throwables._first_hit(space, in_cab + Vector3(-4.0, 0, 0), in_cab)
	check(Vehicle.find_on(hit.get("collider")) == mrap, "the MaxxPro's side stops one")
	var bed_rider := _soldier("friendly", tech.global_position + Vector3(2.5, 0.1, 1.0), "BedFrag")
	var cab_rider := _soldier("friendly", mrap.global_position + Vector3(3, 0.1, 0), "CabFrag")
	await get_tree().physics_frame
	tech.server_enter(bed_rider, 2)
	mrap.server_enter(cab_rider, 2)
	await get_tree().process_frame
	await get_tree().physics_frame
	var above := (bed_rider.get_node(^"ChestHitbox/Shape") as Node3D).global_position + Vector3(0.3, 2.0, 0.8)
	var bed_wounds := Throwables.frag_body(bed_rider, bed_rider.vitals, above, 2.2)
	var beside := (cab_rider.get_node(^"ChestHitbox/Shape") as Node3D).global_position + Vector3(-2.0, 0, 0)
	var cab_wounds := Throwables.frag_body(cab_rider, cab_rider.vitals, beside, 2.0)
	check(bed_wounds > 0 and cab_wounds == 0, "a grenade over the bed wounds its rider (%d), one beside the MaxxPro nobody inside (%d)" % [bed_wounds, cab_wounds])
	tech.server_exit(bed_rider)
	mrap.server_exit(cab_rider)
	bed_rider.queue_free()
	cab_rider.queue_free()


func _test_damage_effects() -> void:
	print("Engine and wheel damage")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	var top := v.top_speed()
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.4)
	check(v.top_speed() < top * 0.75 and v.can_drive(), "a damaged engine slows it (%.1f of %.1f m/s)" % [v.top_speed(), top])
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.0)
	check(not v.can_drive(), "a wrecked engine stops it")
	v.server_enter(player, 0)
	var start := v.global_position
	await _drive(v, 1.0, 0.0, false, 2.0)
	check(v.global_position.distance_to(start) < 0.5, "full throttle goes nowhere (moved %.2f m)" % v.global_position.distance_to(start))
	v.server_set_zone(Vehicle.ZONE_ENGINE, 1.0)
	v.server_set_zone(Vehicle.ZONE_WHEELS, 0.0)
	check(v.can_drive() and v.top_speed() < top * 0.2, "wheels shot out: it crawls on its rims (%.1f m/s top)" % v.top_speed())
	await _drive(v, 1.0, 0.0, false, 3.0)
	check(v.forward_speed() < top * 0.2 + 0.5, "and can't go faster (%.1f m/s)" % v.forward_speed())
	await _drive(v, 0.0, 0.0, true, 2.0)
	v.server_exit(player)
	var aav := _vehicle("range_aav7")
	aav.server_set_zone(Vehicle.ZONE_WHEELS, 0.0)
	check(not aav.can_drive(), "a tracked vehicle with its tracks off can't move")
	aav.server_set_zone(Vehicle.ZONE_WHEELS, 1.0)
	v.server_set_fuel(0.0)
	check(not v.can_drive(), "nor can an empty tank")
	v.server_set_fuel(300.0)
	# Hits wear the zones: .50 into the M-ATV's engine bay until it quits.
	var shooter := _soldier("hostile", Vector3(-30, 0.1, 6), "EngineShooter")
	await get_tree().physics_frame
	var bmg := _gun("50bmg_m33")
	var engine := v.global_transform * Vector3(0.0, 1.35, -2.5)
	var shots := 0
	var hull_before := v.zone_health(Vehicle.ZONE_HULL)
	while v.zone_health(Vehicle.ZONE_ENGINE) > 0.0 and shots < 30:
		_shoot(shooter, Vector3(-30, engine.y, engine.z + randf_range(-0.2, 0.2)), engine + Vector3(0, randf_range(-0.15, 0.15), 0), bmg)
		shots += 1
	check(v.zone_health(Vehicle.ZONE_ENGINE) <= 0.0 and shots >= 2 and v.zone_health(Vehicle.ZONE_HULL) < hull_before,
		"%d .50 rounds through the engine bay wreck the engine; the hull took some too (%.0f%%)" % [shots, v.zone_health(Vehicle.ZONE_HULL) * 100.0])
	shooter.queue_free()


func _test_carving_budget() -> void:
	print("Hull damage at 5 cm, on this vehicle only")
	var v := _vehicle("range_matv")
	var twin := layer.server_spawn("matv", Transform3D(Basis(), Vector3(-25, 0, 20)), "", &"player", "test_twin")
	await _wait_for(func() -> bool: return VehicleHull.pending() == 0, 10.0)
	check(v.hull.edit_count() > 0 and v.hull.is_chunked(), "the shot M-ATV's hull has its own damaged copy (%d voxels changed)" % v.hull.edit_count())
	check(twin.hull.edit_count() == 0 and not twin.hull.is_chunked(), "another M-ATV still shows the shared, undamaged mesh")
	var hole: Array = []
	for op: Array in v.net_carves:
		if int(op[4]) == VehicleHull.HOLE:
			hole = op
	if not hole.is_empty():
		check(v.hull.voxel_at(v.hull.voxel_of(Vector3(hole[0], hole[1], hole[2]))) == VehicleArt.P.EMPTY, "a round's hole is a missing voxel")
	# A burst of hits in one frame: meshing spreads over frames within the budget.
	VehicleHull.worst_chunk_ms = 0.0
	for i in 12:
		var at := Vector3(randf_range(-1.1, 1.1), randf_range(1.3, 2.3), randf_range(-1.0, 1.0))
		v._add_carves([[at.x, at.y, at.z, 0.0, VehicleHull.HOLE]])
	var frames := 0
	var worst_frame := 0.0
	while VehicleHull.pending() > 0 and frames < 200:
		await get_tree().process_frame
		worst_frame = maxf(worst_frame, VehicleHull.last_frame_ms)
		frames += 1
	print("    meshing: worst chunk %.2f ms, worst frame %.2f ms, %d frames" % [VehicleHull.worst_chunk_ms, worst_frame, frames])
	check(VehicleHull.pending() == 0 and VehicleHull.worst_chunk_ms < 12.0 and worst_frame < VehicleHull.BUDGET_MS + VehicleHull.worst_chunk_ms + 1.0,
		"12 hits re-mesh in %d frames, each chunk under 12 ms (%.2f), no frame much over the %.0f ms budget (%.2f)" % [frames, VehicleHull.worst_chunk_ms, VehicleHull.BUDGET_MS, worst_frame])
	twin.queue_free()


func _test_gun() -> void:
	print("Mounted gun")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	VehicleCamera.chase = false  # first person: the turret goes where it's sent (server_aim), not after a chase crosshair
	check(v.server_enter(player, 4) and v.gunner() == player, "the player mans the M-ATV's M2")
	var target := _soldier("hostile", v.global_position + Vector3(0, 0.1, -30), "GunTarget")
	await _seconds(0.3)
	var rounds := v.cargo_hold.feed_rounds(&"belt_50bmg")
	var chest := (target.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	v.server_aim(chest - v.gun_origin())
	await _wait_for(func() -> bool: return v.gun_on(chest - v.gun_origin(), 0.3), 3.0)
	var origin := v.gun_origin()
	var hits := 0
	for i in 6:
		var r := v.server_fire_gun(player, (chest - origin).normalized())
		if r.get("result", "") == "body":
			hits += 1
		await _seconds(0.12)
	check(v.cargo_hold.feed_rounds(&"belt_50bmg") == rounds - 6, "6 shots take 6 rounds from the belts in the hold (%d left)" % v.cargo_hold.feed_rounds(&"belt_50bmg"))
	check(hits >= 1 and not target.vitals.wound_list().is_empty(), "and hit the target 30 m out (%d of 6)" % hits)
	await _seconds(0.3)
	var burst := [v.server_fire_gun(player, Vector3.FORWARD), v.server_fire_gun(player, Vector3.FORWARD), v.server_fire_gun(player, Vector3.FORWARD)]
	check(not burst[0].is_empty() and burst[2].is_empty(), "the rate holds: shots sent all at once don't all fire (%s)" % [burst.map(func(b: Dictionary) -> bool: return not b.is_empty())])
	var own := v.zone_health(Vehicle.ZONE_ENGINE)
	v.server_aim(v.global_transform * Vector3(0, 0.8, -3.0) - v.gun_origin())
	await _seconds(0.8)
	v.server_fire_gun(player, (v.global_transform * Vector3(0, 0.8, -3.0) - v.gun_origin()).normalized())
	check(is_equal_approx(v.zone_health(Vehicle.ZONE_ENGINE), own), "a gunner firing down over the bonnet never hits their own vehicle")
	v.server_exit(player)
	VehicleCamera.chase = true
	target.queue_free()


## Captain, 2026-10-15 (v0.4.3 co-op): the UH-60M's door guns couldn't be fired from their
## seats, the .50 cal made no sound, and AI squadmates boarded the M-ATV as passengers and left
## the M2 empty. Now: a mounted gun's shot plays its report (Sfx), a door gunner's fire input
## fires his M240H out of his own door from the hold's rounds, an AI on a door gun engages, and
## an AI squad getting in puts its autorifleman (never the medic) on the M2, which fires at an
## enemy in view; "Take the gun" sends a chosen squadmate to it.
## G-25 part a (docs/static_weapons.md): an M2 on its tripod is a static vehicle: frozen where it
## stands, a gunner seat and nothing to drive; a player fires it and an AI gunner mans it.
func _test_static_gun() -> void:
	print("Static weapons: the M2 on its tripod")
	var at := level.ground_point(Vector3(-80, 0, -80))
	var gun := layer.server_spawn("tripod_m2", Transform3D(Basis(), at), "", &"player", "test_tripod_m2")
	await _wait_for(func() -> bool: return VehicleHull.is_ready("tripod_m2"), 20.0)
	await _seconds(0.5)
	check(gun != null and gun.kind == Vehicle.STATIC and gun.freeze and not gun.can_drive() and gun.gun_seats().size() == 1 and gun.gun_seats()[0] == 0,
		"a static gun: frozen, won't drive, one gun seat (%s)" % [gun.gun_seats() if gun else []])
	if gun == null:
		return
	gun.server_rearm()
	check(gun.server_enter(player, 0) and gun.gunner() == player, "the player gets on the gun")
	await _seconds(0.3)
	var shot := gun.server_fire_gun(player, gun.barrel_direction())
	check(not shot.is_empty(), "and fires it")
	check(not gun.readout_parts(0).any(func(p: Dictionary) -> bool: return String(p.text).begins_with("Fuel")), "no fuel on its readout")
	gun.server_exit(player)
	var foe := _soldier("hostile", at + Vector3(0, 0.1, -60), "TripodFoe")
	var crew := _soldier("friendly", at + Vector3(0, 0.1, 1.5), "TripodGunner")
	check(gun.server_enter(crew, 0), "an AI gunner sits behind it")
	var g := gun.get_node_or_null(NodePath(AavGunner.NODE_NAME)) as AavGunner
	await _wait_for(func() -> bool: return g != null and g.fired > 0, 8.0)
	check(g != null and g.fired > 0, "and engages the enemy 60 m out (%d rounds)" % (g.fired if g else 0))
	check(gun.global_position.distance_to(at) < 0.05, "it hasn't moved an inch firing (%.3f m)" % gun.global_position.distance_to(at))
	gun.server_exit(crew)
	foe.queue_free()
	# Pack up: two men beside it, each takes a load (38 kg gun, 20 kg tripod).
	var brain := SquadAI.of(crew)
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	crew.move_input = Vector2.ZERO
	player.global_position = at + Vector3(0, 0.1, 2.0)
	crew.global_position = at + Vector3(1.0, 0.1, 2.0)
	await _seconds(0.3)
	var sw := StaticWeapons.of(gun)
	var why := sw.server_start_pack(player, gun)
	check(why == "", "packing up starts (%s)" % why)
	await _seconds(StaticWeapons.KITS.tripod_m2.pack_s + 0.6)
	check(not is_instance_valid(gun) or gun.is_queued_for_deletion(), "after 15 s the gun is packed away")
	var loads := [player.inventory.hands, crew.inventory.hands]
	check(&"static_m2_gun" in loads and &"static_m3_tripod" in loads, "the gun in one man's hands, the tripod in the other's (%s)" % [loads])
	# Set up again, the gun and the tripod a few metres apart.
	crew.global_position = player.global_position + Vector3(2.0, 0, 0)
	await _seconds(0.2)
	why = sw.server_start_setup(player)
	check(why == "", "setting it up starts with the other load 2 m off (%s)" % why)
	await _seconds(StaticWeapons.KITS.tripod_m2.set_s + 0.6)
	var again: Vehicle = null
	for x in layer.vehicles():
		if x.model == "tripod_m2" and not x.is_queued_for_deletion():
			again = x
	check(again != null and player.inventory.hands == &"" and crew.inventory.hands == &"",
		"after 20 s it stands again and both men's hands are free (%s, %s)" % [player.inventory.hands, crew.inventory.hands])
	crew.queue_free()
	if again:
		again.queue_free()
	await _seconds(0.3)


## G-25 part b: an AI gun team (GunTeam) with an enemy known carries its loads to a spot with a
## line on him, sets the gun up, mans it and fires.
func _test_gun_team() -> void:
	print("Static weapons: an AI gun team")
	var at := level.ground_point(Vector3(-60, 0, 60))  # (the range is about 160 m deep)
	var a := _soldier("friendly", at + Vector3(0, 0.1, 0), "GunTeamA")
	var b := _soldier("friendly", at + Vector3(1.5, 0.1, 0), "GunTeamB")
	var foe := _soldier("hostile", level.ground_point(Vector3(-60, 0, -70)) + Vector3(0, 0.1, 0), "GunTeamFoe")
	await _seconds(0.3)
	var fb := SquadAI.of(foe)
	if fb:
		fb.process_mode = Node.PROCESS_MODE_DISABLED  # a target that stays put and doesn't shoot back
	foe.vitals.can_go_down = false  # ...and stays up for the gun (the team's rifles would drop him first)
	for s: Soldier in [a, b]:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_INHERIT  # (_soldier holds brains still: this team has to think)
	var team := GunTeam.form(level, a, b, "tripod_m2")
	check(team != null and a.inventory.hands == &"static_m2_gun" and b.inventory.hands == &"static_m3_tripod",
		"a gun team: the gun in the gunner's hands, the tripod in his assistant's")
	if team == null:
		return
	team.squad.note_enemy(foe, foe.global_position)
	await _wait_for(func() -> bool: return team.state == GunTeam.State.MANNED, 100.0)
	if team.state != GunTeam.State.MANNED:
		print("    %s; gunner at %s (spot %s), %s" % [GunTeam.STATE_NAMES[team.state], a.global_position, team.spot, a.ai_status])
	check(team.state == GunTeam.State.MANNED and is_instance_valid(team.gun) and team.gun.gunner() in [a, b],
		"with an enemy %.0f m off it carries the gun to a spot, sets it up and mans it (%s)" % [at.distance_to(foe.global_position), GunTeam.STATE_NAMES[team.state]])
	if is_instance_valid(team.gun):
		var g := team.gun.get_node_or_null(NodePath(AavGunner.NODE_NAME)) as AavGunner
		await _wait_for(func() -> bool: return g != null and g.fired > 0, 20.0)
		if g == null or g.fired == 0:
			var muzzle := team.gun.gun_origin(0)
			var q := PhysicsRayQueryParameters3D.create(muzzle, foe.aim_point(), 1 | Vehicle.LAYER, [team.gun.get_rid()])
			print("    gun at %s, muzzle %s, foe %s (%.0f m), line hit %s" % [team.gun.global_position, muzzle, foe.aim_point(),
				muzzle.distance_to(foe.aim_point()), team.gun.get_world_3d().direct_space_state.intersect_ray(q)])
		check(g != null and g.fired > 0, "and fires on him (%d rounds)" % (g.fired if g else 0))
		var dig := Digging.of(team.gun)
		await _wait_for(func() -> bool: return team._dug, 5.0)
		check(team._dug, "and digs in in front of the gun, or the ground there already covers it (%s)"
			% ("digging" if dig.digging(team.assistant) else ("dug" if not dig.records.is_empty() else "the ground covers it")))
		var on := team.gun.gunner()
		if on:
			team.gun.server_exit(on)
		team.gun.queue_free()
	team.queue_free()
	for s: Soldier in [a, b, foe]:
		s.queue_free()
	await _seconds(0.3)


## G-25 part c: an AI mortar team carries its M224 to a spot in range and out of sight, sets it
## up and ranges in: rounds go out and land.
func _test_mortar_team() -> void:
	print("Static weapons: an AI mortar team")
	check(MortarFire.spec_of(null).is_empty() and StaticWeapons.KITS.mortar_m224.mortar.max_m > 3000.0, "the M224's real range: out to %.0f m" % StaticWeapons.KITS.mortar_m224.mortar.max_m)
	var at := level.ground_point(Vector3(60, 0, 60))
	var a := _soldier("friendly", at + Vector3(0, 0.1, 0), "MortarA")
	var b := _soldier("friendly", at + Vector3(1.5, 0.1, 0), "MortarB")
	var foe := _soldier("hostile", level.ground_point(Vector3(60, 0, -70)) + Vector3(0, 0.1, 0), "MortarFoe")
	await _seconds(0.3)
	var fb := SquadAI.of(foe)
	if fb:
		fb.process_mode = Node.PROCESS_MODE_DISABLED
	foe.vitals.can_go_down = false
	for s: Soldier in [a, b]:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_INHERIT
	var crew: Array[Soldier] = [a, b]
	var team := MortarTeam.form(level, crew, "mortar_m224")
	check(team != null and a.inventory.hands == &"static_m224_tube" and b.inventory.hands == &"static_m224_mount", "a mortar team: the tube and the mount in two men's hands")
	if team == null:
		return
	team.squad.note_enemy(foe, foe.global_position)
	await _wait_for(func() -> bool: return team.state == MortarTeam.State.READY, 100.0)
	check(team.state == MortarTeam.State.READY and is_instance_valid(team.gun), "it sets the mortar up %.0f m from the enemy (%s)" % [
		team.gun.global_position.distance_to(foe.global_position) if is_instance_valid(team.gun) else -1.0, MortarTeam.STATE_NAMES[team.state]])
	var mf := MortarFire.of(level)
	await _wait_for(func() -> bool: return team.rounds < MortarTeam.ROUNDS, 15.0)
	check(team.rounds < MortarTeam.ROUNDS and mf.in_flight() > 0, "and a ranging round goes out (%d left, %d in the air)" % [team.rounds, mf.in_flight()])
	await _wait_for(func() -> bool: return mf.in_flight() == 0, 45.0)
	check(mf.in_flight() == 0, "and lands")
	# Part d: a player lays it by the firing table and fires a round from its hold.
	var m := MortarFire.spec_of(team.gun) if is_instance_valid(team.gun) else {}
	check(not m.is_empty() and absf(MortarTable.range_m(m, 4, 800.0) - float(m.max_m)) < 5.0, "the table: top charge at 800 mils reaches its maximum")
	if is_instance_valid(team.gun):
		var g := team.gun
		team.queue_free()  # the crew stand off: the player fires it
		await _seconds(0.2)
		g.cargo_hold.take(&"round_60mm_he", 2)
		player.global_position = g.global_position + g.global_basis * Vector3(0.6, 0.1, 0.6)
		var to := foe.global_position - g.global_position
		var want := Vector2(to.x, to.z).length()
		var bearing := wrapf(rad_to_deg(atan2(to.x, -to.z)), 0.0, 360.0)
		var best := [1, 1100.0, INF]
		for c in MortarTable.charges(m):
			var e := MortarTable.ELEVATION_MILS.x
			while e <= MortarTable.ELEVATION_MILS.y:
				var off := absf(MortarTable.range_m(m, c, e) - want)
				if off < float(best[2]):
					best = [c, e, off]
				e += 10.0
		var before := g.cargo_hold.feed_rounds(&"round_60mm_he")
		var flying := mf.in_flight()
		g.request_mortar_fire(bearing, int(best[0]), float(best[1]))
		check(mf.in_flight() == flying + 1 and g.cargo_hold.feed_rounds(&"round_60mm_he") == before - 1,
			"laid by hand (bearing %.0f, charge %d, %.0f mils for %.0f m), a round from its hold goes" % [bearing, int(best[0]), float(best[1]), want])
		await _wait_for(func() -> bool: return mf.in_flight() == 0, 45.0)
		g.queue_free()
	if is_instance_valid(team):
		team.queue_free()
	for s: Soldier in [a, b, foe]:
		s.queue_free()
	await _seconds(0.3)


## G-25 part d: the command menu's Weapons team: two squadmates carrying the M2's loads set it
## up where they're told, man it, and pack it up and come back on the order.
func _test_weapons_team_orders() -> void:
	print("Static weapons: weapons team orders")
	var at := level.ground_point(Vector3(-20, 0, 40))
	var a := _soldier("friendly", at + Vector3(0, 0.1, 0), "OrderGunA")
	var b := _soldier("friendly", at + Vector3(1.5, 0.1, 0), "OrderGunB")
	await _seconds(0.3)
	for s: Soldier in [a, b]:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_INHERIT
	a.inventory.release_hands()
	a.inventory.take(&"static_m2_gun")
	b.inventory.release_hands()
	b.inventory.take(&"static_m3_tripod")
	var sw := StaticWeapons.of(level)
	var spot := level.ground_point(at + Vector3(0, 0, -12))
	var why := sw.server_command(player, "wt_setup", spot, PackedStringArray([String(a.name), String(b.name)]))
	check(why == "", "Set up the gun there: the two carrying the M2 take it on (%s)" % why)
	var team: GunTeam = null
	for t in get_tree().get_nodes_in_group(StaticWeapons.TEAMS_GROUP):
		if t is GunTeam and (t as GunTeam).gunner == a:
			team = t
	await _wait_for(func() -> bool: return team != null and team.state == GunTeam.State.MANNED, 70.0)
	check(team != null and team.state == GunTeam.State.MANNED and team.gun.global_position.distance_to(spot) < 3.0,
		"they carry it there, set it up and man it (%s)" % (GunTeam.STATE_NAMES[team.state] if team else "no team"))
	why = sw.server_command(player, "wt_pack", Vector3.ZERO, PackedStringArray([String(a.name), String(b.name)]))
	await _wait_for(func() -> bool: return not is_instance_valid(team), 30.0)
	check(not is_instance_valid(team) and StaticWeapons.kit_of_load(a.inventory.hands) == "tripod_m2" and StaticWeapons.kit_of_load(b.inventory.hands) == "tripod_m2",
		"Pack up and follow: packed, the loads back in their hands, the team done (%s, %s)" % [a.inventory.hands, b.inventory.hands])
	for s: Soldier in [a, b]:
		s.queue_free()
	await _seconds(0.3)


func _test_vehicle_guns() -> void:
	print("Door guns, mounted-gun sound, AI gunners")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	v.server_rearm()
	VehicleCamera.chase = false
	check(v.server_enter(player, 4) and v.gunner() == player, "the player mans the M-ATV's M2")
	await _seconds(0.3)
	Sfx.listener_override = v.global_position
	var heard := Sfx.heard_count()
	var shot := v.server_fire_gun(player, v.barrel_direction())
	var ids := Sfx.heard_after(heard)
	check(not shot.is_empty() and (&"shot_m2" in ids or &"shot_m2_far" in ids), "an M2 shot plays the heavy gun's report (%s)" % [ids])
	v.server_exit(player)
	# The Black Hawk's door guns.
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), Vector3(30, 0, 40)), "", &"player", "test_door_guns")
	await _seconds(0.5)
	heli.server_rearm()
	var rounds := heli.cargo_hold.feed_rounds(&"rounds_762")
	check(heli.gun_seats().size() == 2 and heli.seat_gun(2) == "m240h" and heli.seat_gun(3) == "m240h" and rounds == 1600,
		"the UH-60M's crew chief and door gunner each man an M240H, 1600 rounds in the hold (%s, %d)" % [heli.gun_seats(), rounds])
	check(heli.server_enter(player, 3), "the player sits at the right door gun")
	var foe := _soldier("hostile", heli.global_transform * Vector3(25, 0, -4.5) + Vector3(0, 0.1, 0), "DoorFoe")
	await _seconds(0.3)
	heard = Sfx.heard_count()
	Sfx.listener_override = heli.global_position
	heli.request_gun((foe.aim_point() - heli.gun_origin(3)).normalized())  # the seat's fire input (on the host)
	ids = Sfx.heard_after(heard)
	check(heli.cargo_hold.feed_rounds(&"rounds_762") == rounds - 1 and (&"shot_m240" in ids or &"shot_m240_far" in ids),
		"its fire input fires the M240H out of the right door: a round from the hold, heard (%d left, %s)" % [heli.cargo_hold.feed_rounds(&"rounds_762"), ids])
	await _seconds(0.3)
	var hits := 0
	for i in 6:
		if heli.server_fire_gun(player, (foe.aim_point() - heli.gun_origin(3)).normalized()).get("result", "") == "body":
			hits += 1
		await _seconds(0.12)
	check(hits >= 1, "and its rounds reach the enemy 25 m out (%d of 6 hit)" % hits)
	await _seconds(0.3)
	check(heli.server_fire_gun(player, -heli.global_basis.x).is_empty(), "but never back through the cabin out of the left door")
	heli.server_exit(player)
	foe.queue_free()  # downed by those hits: a fresh one for the AI
	foe = _soldier("hostile", heli.global_transform * Vector3(-30, 0, -4.5) + Vector3(0, 0.1, 0), "DoorFoe2")
	var chief := _soldier("friendly", heli.global_transform * Vector3(-3, 0, -2.4) + Vector3(0, 0.1, 0), "DoorChief")
	check(heli.server_enter(chief, 2), "an AI crew chief on the left door gun")
	var hg := heli.get_node_or_null(NodePath(AavGunner.NODE_NAME)) as AavGunner
	await _wait_for(func() -> bool: return hg != null and hg.fired > 0, 8.0)
	check(hg != null and hg.fired > 0, "engages the enemy out of his door (%d rounds)" % (hg.fired if hg else 0))
	heli.server_exit(chief)
	chief.queue_free()
	heli.queue_free()
	# The squad mounts the M-ATV: the autorifleman takes the M2, never the medic.
	await _reset(v, Vector3(-12, 0, 6))
	var door := layer._nearest_door(v, v.global_position - v.global_basis.x * 4.0)
	var team: Array[Soldier] = []
	for p: Array in [["GunA_Medic", Roles.MEDIC], ["GunB_Rifle", Roles.RIFLEMAN], ["GunC_AR", Roles.AUTORIFLEMAN]]:
		var s := _soldier("friendly", door + Vector3(0, 0.1, 0.4 * team.size()), String(p[0]))
		s.role = p[1]
		team.append(s)
	await get_tree().physics_frame
	foe.queue_free()
	foe = _soldier("hostile", v.global_position + Vector3(0, 0.1, -30), "GunFoe")
	var names := PackedStringArray(["GunA_Medic", "GunB_Rifle", "GunC_AR"])
	check(layer.server_order_mount(player, v.global_position, names) == "" and v.gunner() == team[2] and team.all(func(s: Soldier) -> bool: return v.seat_of(s) >= 0),
		"Mount > Get in: all three aboard, the autorifleman on the M2 (gunner %s)" % [v.gunner().name if v.gunner() else "none"])
	var g := v.get_node_or_null(NodePath(AavGunner.NODE_NAME)) as AavGunner
	var belt := v.cargo_hold.feed_rounds(&"belt_50bmg")
	await _wait_for(func() -> bool: return g != null and g.fired > 0, 10.0)
	check(g != null and g.fired > 0 and v.cargo_hold.feed_rounds(&"belt_50bmg") < belt, "and fires at an enemy in view (%d rounds)" % (g.fired if g else 0))
	check(layer.server_order_mount(player, v.global_position, PackedStringArray(["GunB_Rifle"]), true) == "Someone's already on the gun",
		"Take the gun: refused while someone's on it")
	v.server_exit(team[2])
	check(layer.server_order_mount(player, v.global_position, PackedStringArray(["GunB_Rifle"]), true) == "" and v.gunner() == team[1],
		"Take the gun: the rifleman, aboard, moves over to the M2")
	for s in team:
		v.server_exit(s)
	check(v.server_enter(player, 4), "a player on the M2")
	check(layer.server_order_mount(player, v.global_position, names) == "" and v.gunner() == player, "then the squad gets in and leaves him on it")
	for s in team:
		v.server_exit(s)
		s.queue_free()
	v.server_exit(player)
	foe.queue_free()
	Sfx.listener_override = null
	VehicleCamera.chase = true
	await _reset(v, Vector3(-12, 0, 6))


## Turrets turn (VehicleTurret; Captain, 2026-10-13): at the mount's speed, within its
## elevation limits, the mesh, gun and gunner with it; first person is the gun's view; rounds
## leave the real muzzle along the barrel; rounds meet the turret where it is now; an AI gunner
## turns onto its target at the same speed before it fires.
func _test_turret() -> void:
	print("Turrets")
	for id: String in ["range_matv", "range_maxxpro", "range_aav7"]:
		var tv := _vehicle(id)
		check(tv != null and tv.turret != null and tv.hull.art.get_node_or_null(^"Turret/Mesh") != null and tv.hull.art.get_node_or_null(^"Turret/Gun/Mesh") != null,
			"%s: a turret and a gun of their own" % id)
	var tech := VehicleSpecs.spec("technical_dshk")
	check(VehicleTurret.of(tech) != null and VehicleTurret.of(VehicleSpecs.spec("technical_zu23")) == null, "a technical's DShK turns; the ones without a working gun don't")
	# A mount with traverse limits (a pintle that can't swing over the cab): held inside them,
	# never wrapping round the short way through the dead arc, and turning at its speed.
	var lim := VehicleTurret.of({"gun": {"weapon": "dshk", "at": [0, 1.8, -1.0]}, "turret": {"pivot": [0, 1.7, 0],
		"traverse_deg": [-120, 120], "elevation_deg": [-5, 60], "traverse_dps": 90, "elevation_dps": 60}})
	lim.aim(deg_to_rad(170.0), deg_to_rad(80.0))
	check(is_equal_approx(lim.target_yaw, deg_to_rad(120.0)) and is_equal_approx(lim.target_pitch, deg_to_rad(60.0)), "a limited mount stops at its traverse and elevation limits")
	lim.aim(deg_to_rad(110.0), 0.0)
	lim.settle()
	lim.aim(deg_to_rad(-110.0), 0.0)
	lim.step(0.5)
	check(is_equal_approx(lim.yaw, deg_to_rad(65.0)), "and turns back the long way, not through the dead arc, at 90 degrees a second (%.0f)" % rad_to_deg(lim.yaw))
	# The turrets' windows, vision blocks and gun ports are see-through glass in the drawn mesh
	# only: the voxels rounds meet stay glass (P.GLASS), the look has P.WINDOW there.
	for model: String in ["matv", "maxxpro", "aav7"]:
		var parts: Array = VehicleHull.canvas(model).get("parts", [])
		var seen := {}
		var hit := {}
		for part: Dictionary in parts:
			if part.name != "Turret":
				continue
			var sz: Vector3i = part.size
			for x in sz.x:
				for y in sz.y:
					for z in sz.z:
						seen[(part.look as VoxelBuffer).get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)] = true
						hit[(part.buffer as VoxelBuffer).get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)] = true
		check(seen.has(VehicleArt.P.WINDOW) and not seen.has(VehicleArt.P.GLASS) and not seen.has(VehicleArt.P.BLACK) and hit.has(VehicleArt.P.GLASS) and not hit.has(VehicleArt.P.WINDOW),
			"%s: the turret's glass is see-through in its look, still glass to rounds" % model)
	## Captain, 2026-10-14 ("part of the turret doesn't move on the matv"): the whole gun shield
	## (front plate, angled wings, side plates, windows; the AAV's vision blocks) turns with the
	## ring, none of it left standing on the roof: no hull voxel above the ring in the shield's
	## footprint ([half width, front, back] about the pivot, metres), and the Turret part spans it.
	var shields := {"matv": [0.88, -0.88, 0.35], "maxxpro": [0.95, -0.95, 0.38], "aav7": [0.62, -0.75, 0.62]}
	for model: String in shields:
		var cv := VehicleHull.canvas(model)
		var vs: float = cv.vs
		var csize: Vector3i = cv.size
		var piv := VehicleSpecs.vec(VehicleSpecs.spec(model).turret.pivot)
		var top := float(VehicleSpecs.spec(model).turret.get("top", piv.y + 1.0))
		var box: Array = shields[model]
		var left := 0
		for buf: VoxelBuffer in [cv.buffer, cv.look]:
			for x in csize.x:
				var mx := (x + 0.5 - csize.x * 0.5) * vs
				if absf(mx - piv.x) > float(box[0]):
					continue
				for z in csize.z:
					var mz := (z + 0.5) * vs - csize.z * vs * 0.5 - piv.z
					if mz < float(box[1]) or mz > float(box[2]):
						continue
					for y in range(floori(piv.y / vs), mini(ceili(top / vs), csize.y)):
						if (y + 0.5) * vs >= piv.y and buf.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) != VehicleArt.P.EMPTY:
							left += 1
		var span := 0.0
		for part: Dictionary in cv.parts:
			if part.name == "Turret":
				span = (part.size as Vector3i).x * vs
		check(left == 0 and span >= float(box[0]) * 2.0 - vs, "%s: the whole shield turns with the turret (%d voxels left on the roof, part %.2f m wide)" % [model, left, span])
	## Captain, 2026-10-14 ("clear guns on the blackhawk"): a mounted gun is never drawn in the
	## windows' see-through glass, on any vehicle: no voxel that is gun metal to rounds is
	## P.WINDOW in the look, the turning guns' look has no P.WINDOW, and their meshes' materials
	## are opaque.
	for model: String in VehicleArt.MODELS:
		var gc := VehicleHull.canvas(model)
		var gsize: Vector3i = gc.size
		var clear_gun := 0
		var hit_buf: VoxelBuffer = gc.buffer
		var look_buf: VoxelBuffer = gc.look
		if look_buf != hit_buf:
			for x in gsize.x:
				for y in gsize.y:
					for z in gsize.z:
						if hit_buf.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) == VehicleArt.P.GUN 								and look_buf.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) == VehicleArt.P.WINDOW:
							clear_gun += 1
		for part: Dictionary in gc.parts:
			if part.name != "Gun":
				continue
			var psz: Vector3i = part.size
			for x in psz.x:
				for y in psz.y:
					for z in psz.z:
						if (part.look as VoxelBuffer).get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) == VehicleArt.P.WINDOW:
							clear_gun += 1
		check(clear_gun == 0, "%s: its guns are solid, not see-through glass (%d clear gun voxels)" % [model, clear_gun])
	for id: String in ["range_matv", "range_maxxpro", "range_aav7"]:
		var gun_mesh := _vehicle(id).hull.art.get_node_or_null(^"Turret/Gun/Mesh") as MeshInstance3D
		var see_through := 0
		if gun_mesh and gun_mesh.mesh:
			for si in gun_mesh.mesh.get_surface_count():
				var mat := gun_mesh.get_active_material(si) as BaseMaterial3D
				if mat and (mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.albedo_color.a < 1.0):
					see_through += 1
		check(gun_mesh != null and see_through == 0, "%s: the mounted gun's materials are opaque (%d see-through surfaces)" % [id, see_through])
	# And it turns as one: the shield's mesh follows the ring's yaw.
	var sv := _vehicle("range_maxxpro")
	sv.turret.aim(deg_to_rad(70.0), 0.0)
	sv.turret.settle()
	sv.hull.pose_turret()
	var shield_mesh := sv.hull.art.get_node(^"Turret/Mesh") as Node3D
	var want := (sv.hull.art as Node3D).global_basis.orthonormalized() * Basis(Vector3.UP, sv.turret.yaw)
	check(shield_mesh.global_basis.orthonormalized().z.dot(want.z) > 0.999, "the shield's mesh turns with the gun's yaw (70 degrees)")
	sv.turret.aim(0.0, 0.0)
	sv.turret.settle()
	sv.hull.pose_turret()
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	VehicleCamera.chase = false
	check(v.server_enter(player, 4), "the player mans the M-ATV's turret, first person")
	var t := v.turret
	t.aim(0.0, 0.0)
	t.settle()
	await _seconds(Vehicle.EXIT_GRACE_S + 0.1)
	# Traverse: 90 degrees to the right takes 1.5 s at 60 a second.
	var right := v.global_basis.x
	v.server_aim(right)
	var t0 := Soldier._now()
	await _seconds(0.5)
	var turned := absf(t.yaw)
	var most := t.yaw_rate * (Soldier._now() - t0) + 0.05
	check(turned > t.yaw_rate * 0.35 and turned <= most,
		"it traverses at its speed: %.0f degrees in %.2f s (at most %.0f)" % [rad_to_deg(turned), Soldier._now() - t0, rad_to_deg(most)])
	var turret_node := v.hull.art.get_node(^"Turret") as Node3D
	check(is_equal_approx(turret_node.rotation.y, t.yaw), "the turret's mesh turns with it")
	await _wait_for(func() -> bool: return absf(t.yaw + PI * 0.5) < 0.01, 3.0)
	check(absf(t.yaw + PI * 0.5) < 0.01 and v.barrel_direction().dot(right) > 0.99, "and stops on the target, the barrel to the right")
	var seat := v.seat_transform("4").origin
	check(player.global_position.distance_to(seat) < 0.05 and seat.distance_to(v.global_transform * t.carry(VehicleSpecs.vec(v.spec.seats[4].at) - Vector3(0, Vehicle.seat_eye("stand"), 0))) < 0.01,
		"the gunner stands at the ring, turned with it")
	for i in 3:
		await get_tree().process_frame
	check((-player.camera.global_basis.z).dot(v.barrel_direction()) > 0.99, "first person: the gunner looks along the gun")
	# The mouse turns the turret, not the view: a turn of the body goes to where the turret's going.
	player.rotation.y += deg_to_rad(30.0)
	await get_tree().process_frame
	check(absf(wrapf(t.target_yaw - (-PI * 0.5 + deg_to_rad(30.0)), -PI, PI)) < 0.02, "a mouse turn of 30 degrees sends the turret 30 degrees on")
	await _seconds(0.1)
	check((-player.camera.global_basis.z).dot(v.barrel_direction()) > 0.99, "and the view stays the gun's while it turns")
	# Elevation limits.
	v.server_aim(Vector3.UP + v.global_basis.z * -0.01)
	await _wait_for(func() -> bool: return is_equal_approx(t.pitch, t.pitch_max), 3.0)
	check(is_equal_approx(t.pitch, t.pitch_max) and is_equal_approx(t.target_pitch, t.pitch_max), "straight up: the gun stops at its highest (%.0f degrees)" % rad_to_deg(t.pitch_max))
	v.server_aim(Vector3.DOWN - v.global_basis.z * 0.01)
	await _wait_for(func() -> bool: return is_equal_approx(t.pitch, t.pitch_min), 3.0)
	check(is_equal_approx(t.pitch, t.pitch_min), "straight down: at its lowest (%.0f degrees)" % rad_to_deg(t.pitch_min))
	check(is_equal_approx((v.hull.art.get_node(^"Turret/Gun") as Node3D).rotation.x, t.pitch), "the gun's mesh elevates with it")
	# Rounds leave the muzzle along the barrel: turned 60 degrees left and a little down, whatever direction the shot names.
	t.aim(deg_to_rad(60.0), deg_to_rad(-6.0))
	t.settle()
	await get_tree().physics_frame
	var muzzle := v.gun_origin()
	check(muzzle.distance_to(v.global_transform * (t.gun_transform() * (t.muzzle - t.trunnion))) < 0.001 and (muzzle - v.global_transform * t.pivot).dot(v.barrel_direction()) > 1.0,
		"the muzzle is out at the barrel's end")
	await _seconds(0.3)
	var shot := v.server_fire_gun(player, -v.global_basis.z)
	var at: Vector3 = shot.get("position", muzzle)
	var off := ((at - muzzle) - v.barrel_direction() * (at - muzzle).dot(v.barrel_direction())).length()
	var spread := tan(deg_to_rad(float(VehicleSpecs.gun_item("m2hb").stats.get("spread_deg", 0.3)))) * 1.5
	check(shot.get("result", "none") != "none" and (at - muzzle).dot(v.barrel_direction()) > 2.0 and off < (at - muzzle).length() * spread + 0.05,
		"a round leaves the muzzle along the barrel, not where the shot asked (%.2f m off the line at %.1f m)" % [off, (at - muzzle).length()])
	# Rounds meet the turret where it is: the front plate, straight ahead, then behind.
	var ahead := v.hull.first_solid(Vector3(0, 3.05, -2.5), Vector3.BACK, 4.0)
	t.aim(0.0, 0.0)
	t.settle()
	ahead = v.hull.first_solid(Vector3(0, 3.05, -2.5), Vector3.BACK, 4.0)
	t.aim(PI, 0.0)
	t.settle()
	var behind := v.hull.first_solid(Vector3(0, 3.05, -2.5), Vector3.BACK, 4.0)
	check(ahead.get("part", "") == "Turret" and absf(float(ahead.local.z) - (t.pivot.z - 0.88)) < 0.1, "a round from ahead meets the shield's front plate (%s)" % [ahead.get("local")])
	check(behind.get("part", "") == "Turret" and float(behind.local.z) > t.pivot.z + 0.6, "turned round, the same round meets it behind the ring (%s)" % [behind.get("local")])
	t.aim(0.0, 0.0)
	t.settle()
	v.server_exit(player)
	VehicleCamera.chase = true
	# An AI gunner turns onto its target at the weapon station's speed before it fires.
	var aav := _vehicle("range_aav7")
	await _reset(aav, Vector3(18, 0, -10))
	aav.turret.aim(0.0, 0.0)
	aav.turret.settle()
	var crew := _soldier("player", aav.global_position + aav.global_basis.x * 3.0, "TurretAI")
	check(aav.server_enter(crew, 2), "an AI gunner in the AAV's weapon station")
	var foe := _soldier("hostile", aav.global_position + aav.global_basis.x * 40.0 + Vector3(0, 0.1, 0), "TurretFoe")
	var gunner := AavGunner.attach(aav)
	await _seconds(0.6)
	var early := gunner.fired
	var turned_ai := absf(aav.turret.yaw)
	check(early == 0 and turned_ai > 0.05 and turned_ai <= aav.turret.yaw_rate * 0.7 + 0.05,
		"it doesn't fire while still turning (%d rounds, %.0f degrees in 0.6 s)" % [early, rad_to_deg(turned_ai)])
	await _wait_for(func() -> bool: return gunner.fired > 0, 6.0)
	var to_foe := foe.global_position - aav.gun_origin()
	check(gunner.fired > 0 and aav.barrel_direction().dot(Vector3(to_foe.x, 0, to_foe.z).normalized()) > 0.97,
		"then fires with the gun on it (%d rounds)" % gunner.fired)
	gunner.queue_free()
	aav.server_exit(crew)
	crew.queue_free()
	foe.queue_free()
	aav.turret.aim(0.0, 0.0)
	aav.turret.settle()


## Seated players see out through a chase camera (VehicleCamera; Captain, 2026-10-13: the
## hulls are solid, so first person showed only the inside): on by default, B switches to first
## person at the seat's eye and back, getting out gives the on-foot view back, the gunner's
## rounds go where the chase camera looks, and the camera stays out of walls and the ground.
func _test_chase_camera() -> void:
	print("Chase camera")
	var bound := InputMap.action_get_events(VehicleCamera.ACTION)
	check(bound.size() == 1 and bound[0] is InputEventKey and (bound[0] as InputEventKey).physical_keycode == KEY_B
		and GameSettings.BINDABLE.any(func(pair: Array) -> bool: return pair[0] == VehicleCamera.ACTION),
		"the vehicle view is on B, and rebindable")
	var clashes := InputMap.get_actions().filter(func(action: StringName) -> bool:
		return action != VehicleCamera.ACTION and not String(action).begins_with("ui_") and InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
			return e is InputEventKey and ((e as InputEventKey).physical_keycode == KEY_B or (e as InputEventKey).keycode == KEY_B)))
	check(clashes.is_empty(), "and B does nothing else (%s)" % [clashes])
	check(VehicleCamera.FIRST_PERSON_DEFAULT, "a session starts in first person now the cabins are hollow and glazed (Captain); B gives the chase view")
	VehicleCamera.chase = true  # the checks below start from the chase view
	# Out of the M2 a moment ago (the gun checks): the exit's grace runs out first (a body that
	# just got out isn't placed at a seat for EXIT_GRACE_S), and the camera has a frame to notice.
	await _seconds(Vehicle.EXIT_GRACE_S + 0.1)
	var cam := VehicleCamera.of(player)
	check(cam != null and not cam.active and player.camera.current, "on foot: the soldier's own camera")
	if cam == null:
		return
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	check(v.server_enter(player, 0), "the player drives the M-ATV")
	player.set_pitch(0.0)
	for i in 3:
		await get_tree().process_frame
	var fwd := -v.global_basis.z
	var rel := cam.global_position - v.global_position
	var box := VehicleCamera.hull_box(v)
	check(cam.active and cam.current and get_viewport().get_camera_3d() == cam, "seated: the chase camera is the view")
	check(rel.dot(fwd) < -box.size.z * 0.5 and cam.global_position.y > v.global_position.y + box.end.y,
		"behind the vehicle (%.1f m) and above its roof (%.1f m)" % [-rel.dot(fwd), cam.global_position.y - v.global_position.y])
	check((-cam.global_basis.z).dot(fwd) > 0.99, "looking where the driver looks: ahead")
	for i in 2:  # physics_frame fires before the tick's _physics_process: wait one through
		await get_tree().physics_frame
	check(not player.view_model.visible, "no first-person weapon floating in the chase view")
	var readout := v.readout(0)
	check(readout.contains("B: 1st person"), "the HUD line names the key and the view it switches to (%s)" % readout)
	# Turning the head orbits the camera round the vehicle.
	player.rotation.y += deg_to_rad(90.0)
	for i in 3:
		await get_tree().process_frame
	rel = cam.global_position - v.global_position
	var right := v.global_basis.x
	check(rel.dot(right) > 2.0 and (-cam.global_basis.z).dot(-right) > 0.95,
		"looking left, the camera swings round to the right side (%.1f m)" % rel.dot(right))
	player.rotation.y -= deg_to_rad(90.0)
	var press := InputEventAction.new()
	press.action = VehicleCamera.ACTION
	press.pressed = true
	player.player_input._unhandled_input(press)
	for i in 2:
		await get_tree().process_frame
	for i in 2:  # physics_frame fires before the tick's _physics_process: wait one through
		await get_tree().physics_frame
	check(not VehicleCamera.chase and not cam.active and player.camera.current and get_viewport().get_camera_3d() == player.camera,
		"B: first person")
	check(player.camera.global_position.distance_to(v.seat_eye_point(0)) < 0.15 and not player.view_model.visible,
		"at the seat's eye, as before, with no rifle in view (it can't fire from a seat; it hid the cabin) (%.2f m off)" % player.camera.global_position.distance_to(v.seat_eye_point(0)))
	player.player_input._unhandled_input(press)
	for i in 2:
		await get_tree().process_frame
	check(VehicleCamera.chase and cam.active and cam.current, "B again: back to the chase view")
	# A passenger: the same chase view, and B works there too.
	check(v.server_switch(player, 2), "over to a rear passenger seat")
	player.rotation.y = _yaw(v)
	player.set_pitch(0.0)
	for i in 3:
		await get_tree().process_frame
	check(cam.active and get_viewport().get_camera_3d() == cam and (cam.global_position - v.global_position).dot(fwd) < -box.size.z * 0.5,
		"a passenger sees through the chase camera too, behind the vehicle")
	player.player_input._unhandled_input(press)
	for i in 2:
		await get_tree().process_frame
	for i in 2:  # physics_frame fires before the tick's _physics_process: wait one through
		await get_tree().physics_frame
	check(not cam.active and get_viewport().get_camera_3d() == player.camera and player.camera.global_position.distance_to(v.seat_eye_point(2)) < 0.15,
		"B in the passenger seat: first person at that seat's eye (%.2f m off)" % player.camera.global_position.distance_to(v.seat_eye_point(2)))
	player.player_input._unhandled_input(press)
	for i in 2:
		await get_tree().process_frame
	check(cam.active, "and B back to the chase view")
	# The gunner's rounds go where the chase camera looks.
	check(v.server_switch(player, 4) and v.gunner() == player, "over to the M2")
	await get_tree().process_frame
	var target := _soldier("hostile", v.global_transform * Vector3(-8, 0.1, -30), "ChaseTarget")
	await _seconds(0.3)
	var chest := (target.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	for i in 4:  # aim the camera's crosshair at the chest (the camera moves a little with the look)
		var to := chest - cam.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		player.set_pitch(atan2(to.y, Vector2(to.x, to.z).length()))
		for k in 2:
			await get_tree().process_frame
	var aim := v.gun_direction(player)
	var on := cam.aim_point()
	var miss := ((on - v.gun_origin()) - aim * (on - v.gun_origin()).dot(aim)).length()
	check(on.distance_to(chest) < 0.6, "the chase crosshair is on the target (%.2f m off)" % on.distance_to(chest))
	check(miss < 0.05 and aim.dot(-cam.global_basis.z) > 0.95, "the gun aims from its mount at the crosshair, not along a parallel line (%.3f m off)" % miss)
	var hits := 0
	await _seconds(0.3)
	for i in 6:
		if v.server_fire_gun(player, v.gun_direction(player)).get("result", "") == "body":
			hits += 1
		await _seconds(0.12)
	check(hits >= 1, "and its rounds hit what the camera looks at (%d of 6)" % hits)
	target.queue_free()
	VehicleCamera.chase = false
	await get_tree().process_frame
	check(v.gun_direction(player).dot(-player.camera.global_basis.z) > 0.999, "in first person the gun goes along the view, as before")
	VehicleCamera.chase = true
	v.server_switch(player, 0)
	# Out of walls: a voxel wall just behind the vehicle pulls the camera in front of it.
	var tool := level.voxel_world.terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	tool.mode = VoxelTool.MODE_SET
	var back_z := v.global_position.z + box.end.z + 1.2
	var lo := Vector3i(level.voxel_world.terrain.to_local(Vector3(-17, 0, back_z)).round())
	var hi := Vector3i(level.voxel_world.terrain.to_local(Vector3(-7, 5, back_z + 0.6)).round())
	tool.value = VoxelWorld.Mat.CONCRETE
	tool.do_box(lo, hi)
	var space := player.get_world_3d().direct_space_state
	var probe := func() -> bool:
		return not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-12, 2.5, back_z - 2), Vector3(-12, 2.5, back_z + 2), 1)).is_empty()
	await _wait_for(probe, 10.0)
	check(probe.call(), "a 5 m concrete wall %.1f m behind the M-ATV's tail" % (back_z - v.global_position.z - box.end.z))
	player.set_pitch(0.0)
	player.rotation.y = _yaw(v)
	for i in 30:
		await get_tree().process_frame
	var pivot := VehicleCamera.pivot_of(v)
	var through := space.intersect_ray(PhysicsRayQueryParameters3D.create(pivot, cam.global_position, 1))
	check(cam.global_position.z < back_z - VehicleCamera.ARM_RADIUS * 0.5 and through.is_empty(),
		"the camera stays this side of it (%.2f m short), nothing between it and the vehicle" % (back_z - cam.global_position.z))
	check(cam.global_position.distance_to(pivot) < VehicleCamera.arm_length(v) - 0.5, "pulled in (%.1f of %.1f m)" % [cam.global_position.distance_to(pivot), VehicleCamera.arm_length(v)])
	tool.value = VoxelWorld.Mat.EMPTY
	tool.do_box(lo, hi)
	await _wait_for(func() -> bool: return not probe.call(), 10.0)
	await _seconds(1.0)
	check(cam.global_position.distance_to(VehicleCamera.pivot_of(v)) > VehicleCamera.arm_length(v) - 0.3, "the wall gone, the arm eases back out")
	# Out of the ground: looking up from a helicopter (a long arm) keeps the camera above it.
	var heli := layer.server_spawn("uh60", Transform3D(Basis(), Vector3(30, 0, 40)), "", &"player", "test_chase_heli")
	for i in 2:  # physics_frame fires before the tick's _physics_process: wait one through
		await get_tree().physics_frame
	check(heli != null and heli.server_enter(player, 2), "into a UH-60's crew seat")
	if heli:
		player.rotation.y = _yaw(heli)
		player.set_pitch(Soldier.MAX_PITCH)
		for i in 30:
			await get_tree().process_frame
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position + Vector3.UP * 20.0, cam.global_position + Vector3.DOWN * 20.0, 1, [heli.get_rid()]))
		var above: float = cam.global_position.y - (ground.position.y if not ground.is_empty() else -INF)
		check(cam.active and above > VehicleCamera.ARM_RADIUS * 0.5, "looking up, the camera stays above the ground (%.2f m)" % above)
		var behind := (cam.global_position - heli.global_position).dot(heli.global_basis.z)
		check(behind > 6.0, "behind a helicopter, further for its size (%.1f m)" % behind)
		await _seconds(Vehicle.EXIT_GRACE_S + 0.1)  # seated for real (out of the M-ATV's grace)
		player.rotation.y = _yaw(heli) + deg_to_rad(150.0)
		player.set_pitch(-0.2)
		for i in 30:
			await get_tree().process_frame
		var side := (cam.global_position - heli.global_position).dot(heli.global_basis.x)
		check(side > 4.0, "looking back over the left shoulder from the crew seat (held at the seat's limit), the camera swings round to the helicopter's right (%.1f m)" % side)
		heli.server_exit(player)
		heli.queue_free()
	else:
		v.server_exit(player)
	for i in 3:
		await get_tree().process_frame
	check(Vehicle.ride_of(player) == null and not cam.active and player.camera.current and get_viewport().get_camera_3d() == player.camera,
		"getting out: the on-foot camera again")
	player.set_pitch(0.0)


func _test_service() -> void:
	print("Fuel and field repairs")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	player.global_position = v.global_position + Vector3(0, 0.1, -3.9)
	player.inventory.take(&"ruck_45")
	player.inventory.take(&"jerrycan")
	player.inventory.take(&"repair_kit")
	await get_tree().physics_frame
	v.server_set_fuel(250.0)
	check(v.server_start_job(player, "refuel", &"", &"jerrycan") == "" and v.job_left(player) > 7.0, "refuelling from a jerrycan takes 8 s")
	check(VehicleService.finish(v, player, "refuel", &"", &"jerrycan").begins_with("Refuelled 20") and is_equal_approx(v.fuel, 270.0)
		and VehicleService.jerrycan_fuel(player) == 0.0 and player.inventory.count_of(&"jerrycan") == 1,
		"20 L in (%.0f L); the can stays, empty" % v.fuel)
	player.global_position += Vector3(3, 0, 0)
	await _seconds(0.1)
	check(v.job_left(player) == 0.0, "walking off stops the job")
	player.global_position -= Vector3(3, 0, 0)
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.2)
	check(VehicleService.repair_problem(v, player, Vehicle.ZONE_ENGINE, &"repair_kit") == "" and VehicleService.repair_problem(v, player, Vehicle.ZONE_ENGINE, &"engine_parts") != "",
		"a repair kit can patch the engine; engine parts you don't carry can't")
	check(VehicleService.finish(v, player, "repair", Vehicle.ZONE_ENGINE, &"repair_kit") != "" and is_equal_approx(v.zone_health(Vehicle.ZONE_ENGINE), 0.6)
		and player.inventory.count_of(&"repair_kit") == 0, "the kit is used and the engine is back to 60%")
	player.inventory.take(&"spare_wheel")
	v.server_set_zone(Vehicle.ZONE_WHEELS, 0.0)
	VehicleService.finish(v, player, "repair", Vehicle.ZONE_WHEELS, &"spare_wheel")
	check(is_equal_approx(v.zone_health(Vehicle.ZONE_WHEELS), 0.5) and player.inventory.hands == &"", "a spare wheel from your hands: wheels at 50%")
	v.server_set_battery(false)
	check(not v.can_drive(), "a dead battery: it won't start")
	player.inventory.take(&"vehicle_battery")
	check(player.inventory.count_of(&"vehicle_battery") == 1, "carrying a battery")
	VehicleService.finish(v, player, "repair", &"battery", &"vehicle_battery")
	check(v.can_drive(), "a new battery fitted")
	await _test_service_vehicle_leaves(v)
	var aav := _vehicle("range_aav7")
	player.inventory.take(&"track_links")
	check(VehicleService.repair_problem(aav, player, Vehicle.ZONE_WHEELS, &"spare_wheel") != "" or not VehicleService.has_part(player, &"spare_wheel"),
		"a spare wheel doesn't fit a tracked vehicle")
	aav.server_set_zone(Vehicle.ZONE_WHEELS, 0.0)
	check(VehicleService.repair_problem(aav, player, Vehicle.ZONE_WHEELS, &"track_links") == "", "track links fix tracks")
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	aav.server_set_zone(Vehicle.ZONE_WHEELS, 1.0)
	await _reset(v, Vector3(-12, 0, 6))


## Audit A3-06: a service job asked for the real way (the service menu's request) runs to the
## end with the vehicle standing there, and stops, doing nothing, once the vehicle drives off
## from the worker (repairs and refuelling alike).
func _test_service_vehicle_leaves(v: Vehicle) -> void:
	var home := v.global_transform
	var me := player.get_instance_id()
	player.global_position = v.global_position + Vector3(0, 0.1, -3.9)
	while player.inventory.count_of(&"jerrycan") > 0:
		player.inventory.remove_one(&"jerrycan")  # the empty one from before
	player.inventory.take(&"jerrycan")
	v.server_set_fuel(250.0)
	await get_tree().physics_frame
	check(v.in_reach(player), "standing by the vehicle to work on it")
	v.request_service.rpc_id(1, "refuel", &"", VehicleService.JERRYCAN)
	var started := v.job_left(player)
	await _wait_for(func() -> bool: return not v._jobs.has(me), 12.0)
	check(started > 7.0 and v.fuel > 260.0, "a refuel left to run: done where it stands (%.0f s, %.0f L)" % [started, v.fuel])
	player.inventory.take(&"repair_kit")
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.3)
	v.request_service.rpc_id(1, "repair", Vehicle.ZONE_ENGINE, &"repair_kit")
	started = v.job_left(player)
	v.global_position += Vector3(30, 0, 0)  # driven off
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(started > 0.0 and v.job_left(player) == 0.0 and is_equal_approx(v.zone_health(Vehicle.ZONE_ENGINE), 0.3) and player.inventory.count_of(&"repair_kit") == 1,
		"a repair under way stops when the vehicle drives off: engine untouched, kit kept (%.0f s)" % started)
	v.global_transform = home
	v.linear_velocity = Vector3.ZERO
	await get_tree().physics_frame
	while player.inventory.count_of(&"jerrycan") > 0:
		player.inventory.remove_one(&"jerrycan")
	player.inventory.take(&"jerrycan")  # a full one
	v.server_set_fuel(250.0)
	var why := v.server_start_job(player, "refuel", &"", VehicleService.JERRYCAN) if v.in_reach(player) else "out of reach"
	started = v.job_left(player)
	v.global_position += Vector3(30, 0, 0)  # driven off
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(started > 0.0 and v.job_left(player) == 0.0 and v.fuel < 251.0,  # the idling engine may burn a little
		"and a refuel too: not a drop goes in (%.0f L; %.0f s%s; %.0f m off, %.0f s left)" % [v.fuel, started, "" if why == "" else ", " + why,
			v.global_position.distance_to(home.origin), v.job_left(player)])
	v.global_transform = home
	v.linear_velocity = Vector3.ZERO
	player.inventory.remove_one(&"jerrycan")
	player.inventory.remove_one(&"repair_kit")
	await get_tree().physics_frame


func _test_fire() -> void:
	print("Fire and wrecks")
	var v := _vehicle("range_technical")
	await _reset(v, Vector3(4, 0, 6))
	var passenger := _soldier("friendly", v.global_position + Vector3(2.5, 0.1, 0), "LeftInside")
	var escaped := _soldier("friendly", v.global_position + Vector3(-2.5, 0.1, 0), "GotOut")
	await get_tree().physics_frame
	v.server_enter(passenger, 1)
	v.server_enter(escaped, 0)
	v.cargo_hold.take(&"engine_parts", 2)
	var lost := [false]
	v.destroyed.connect(func(_v: Vehicle) -> void: lost[0] = true)
	v.server_start_fire(3.0)
	check(v.is_burning() and lost[0], "set on fire: it's lost (destroyed signal)")
	v.server_exit(escaped)
	await _seconds(1.5)
	check(passenger.vitals.burn_share() > 0.0 and escaped.vitals.burn_share() == 0.0, "the one left inside is burning (%.0f%%), the one who got out isn't" % (passenger.vitals.burn_share() * 100.0))
	await _wait_for(func() -> bool: return v.wrecked, 5.0)
	await get_tree().physics_frame
	check(v.wrecked and passenger.vitals.is_dead() and not escaped.vitals.is_dead(), "it burns out: a wreck, and the passenger left inside is dead")
	check(v.cargo_hold.entries().is_empty(), "its cargo burned with it")
	check(v.seat_of(passenger) < 0 and passenger.is_in_group(Soldier.DEAD_GROUP) and passenger.global_position.distance_to(v.global_position) > 1.0,
		"his body lies beside the wreck")
	check(v.freeze and not v.server_enter(escaped, 0), "the wreck is immobile and nobody gets in")
	check(v.hull.edit_count() > 0, "and blackened")
	escaped.queue_free()


func _test_save_reload() -> void:
	print("Wrecks and damage saved with the zone")
	var wreck := _vehicle("range_technical")
	var mrap := _vehicle("range_maxxpro")
	var wreck_pos := wreck.global_position
	var carves := wreck.net_carves.size()
	var mrap_engine := mrap.zone_health(Vehicle.ZONE_ENGINE)
	mrap.cargo_hold.take(&"jerrycan", 2)
	var mrap_cargo := mrap.cargo_hold.count_of(&"jerrycan")
	# A body riding in the MaxxPro when the zone is left.
	var kia := _soldier("friendly", mrap.global_position + Vector3(3, 0.1, 0), "KIA")
	kia.vitals.server_kill()
	await _wait_for(func() -> bool: return kia.is_in_group(Soldier.DEAD_GROUP), 3.0)
	mrap.server_enter(kia, -1)
	var kia_seat := mrap.seat_of(kia)
	var kia_uid := kia.body_uid
	check(kia_seat >= 0 and kia_uid != "", "a dead body rides in the MaxxPro's seat %d" % kia_seat)
	GameState.save_zone()
	var saved := GameState.read_save(GameState.save_path())
	check((saved.get("vehicles", []) as Array).size() == layer.vehicles().size(), "the save holds every vehicle (%d)" % (saved.get("vehicles", []) as Array).size())
	# Leave the zone and come back as a campaign does (BaseHub._do_switch): a fresh level whose
	# own _on_hosted loads the zone save. Net.hosted isn't emitted; nothing is restored by hand.
	level = LevelSwitch.load_level(main, level.level_info(), true) as VehicleRange
	level._on_hosted()
	layer = level.get_node(^"Vehicles") as VehicleLayer
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	await _wait_for(func() -> bool: return level.voxel_world.is_built() and layer.vehicles().size() >= VehicleRange.PARKED.size(), 30.0)
	await _wait_for(func() -> bool: return _seated_uid("range_maxxpro", kia_seat) == kia_uid, 10.0)
	await get_tree().physics_frame
	check(layer.vehicles().size() == (saved.get("vehicles", []) as Array).size(),
		"after leaving and coming back every vehicle is there again (%d)" % layer.vehicles().size())
	var back := _vehicle("range_technical")
	check(back != null and back.wrecked and back.freeze and back.global_position.distance_to(wreck_pos) < 0.05 and back.net_carves.size() == carves,
		"the wreck comes back where it burned, a wreck, with its damage (%d marks)" % (back.net_carves.size() if back else -1))
	var mrap_back := _vehicle("range_maxxpro")
	check(mrap_back != null and is_equal_approx(mrap_back.zone_health(Vehicle.ZONE_ENGINE), mrap_engine) and mrap_back.cargo_hold.count_of(&"jerrycan") == mrap_cargo,
		"the MaxxPro's engine damage (%.0f%%) and cargo come back too" % (mrap_engine * 100.0))
	check(_seated_uid("range_maxxpro", kia_seat) == kia_uid, "the dead body is back in its seat")
	check(layer.server_place_parked(VehicleRange.PARKED).is_empty(), "parking the range again adds nothing the save already holds")
	if mrap_back and mrap_back.occupant(kia_seat):
		var body := mrap_back.occupant(kia_seat)
		mrap_back.server_exit(body)
		body.queue_free()
	await _wait_for(func() -> bool: return VehicleHull.pending() == 0, 10.0)
	await _seconds(0.8)
	if back:
		# Audit A3-06: salvage stops too once the worker isn't by the wreck any more (here the
		# job started out of reach, as nothing in the menu allows): nothing comes off it.
		player.global_position = back.global_position + Vector3(0, 0.1, -40.0)
		var far_job := back.server_start_job(player, "salvage", &"", &"")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(far_job == "" and back.job_left(player) == 0.0 and not back.salvaged, "salvaging a wreck out of reach stops at once, nothing taken")
		var salvage_job := back.server_start_job(player, "salvage", &"", &"")
		player.global_position = back.global_position + Vector3(0, 0.1, -3.2)
		check(VehicleService.finish(back, player, "salvage", &"", &"") != "" and back.salvaged
			and VehicleService.finish(back, player, "salvage", &"", &"") == "Nothing left to salvage", "the wreck yields parts once (%s)" % salvage_job)


## The body uid of the dead riding in seat `seat` of vehicle `id` ("" if none).
func _seated_uid(id: String, seat: int) -> String:
	var v := _vehicle(id)
	var s := v.occupant(seat) if v and seat >= 0 else null
	return s.body_uid if s and s.vitals.is_dead() else ""


func _test_ai_driver() -> void:
	print("AI driver")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	var ai_driver := _soldier("friendly", v.global_position + Vector3(-3, 0.1, 0), "AIDriver")
	await get_tree().physics_frame
	v.server_enter(ai_driver, 0)
	var goal := Vector3(-12, 0, -22)
	v.server_drive_to(goal)
	await _wait_for(func() -> bool: return v.ai.status == "arrived", 30.0)
	var d := Vector2(v.global_position.x, v.global_position.z).distance_to(Vector2(goal.x, goal.z))
	check(v.ai.status == "arrived" and d < VehicleAI.ARRIVE_M + 1.5 and v.linear_velocity.length() < 0.6,
		"the AI drives to a point 28 m off and stops there (%.1f m from it, %s)" % [d, v.ai.status])
	var turn_goal := Vector3(14, 0, -22)
	v.server_follow_path(PackedVector3Array([Vector3(0, 0, -36), turn_goal]))
	await _wait_for(func() -> bool: return v.ai.status == "arrived", 40.0)
	d = Vector2(v.global_position.x, v.global_position.z).distance_to(Vector2(turn_goal.x, turn_goal.z))
	check(v.ai.status == "arrived" and d < VehicleAI.ARRIVE_M + 2.0, "and follows a path with a turn (%.1f m off at the end)" % d)
	# Something in the way: it stops short rather than ploughing on.
	var aav := _vehicle("range_aav7")
	await _reset(aav, Vector3(20, 0, -20), 90.0)  # across the way
	await _reset(v, Vector3(20, 0, 2))
	v.server_enter(ai_driver, 0)
	v.server_drive_to(Vector3(20, 0, -40))
	await _wait_for(func() -> bool: return v.ai.status == "blocked" or v.ai.status == "arrived", 20.0)
	var gap := v.global_position.distance_to(aav.global_position)
	check(v.ai.status == "blocked" and gap > 5.0 and gap < 15.0, "an AAV-7 parked across its way: it stops short (%.1f m between them, %s)" % [gap, v.ai.status])
	v.server_stop()
	v.server_exit(ai_driver)
	ai_driver.queue_free()
	await _reset(aav, Vector3(13, 0, 6))
	await _reset(v, Vector3(-12, 0, 6))


## The squad's AI at the wheel (SquadDrivers; Captain, 2026-10-19): take the wheel, drive there,
## a column behind the commander, come pick us up, the contact drill, stop.
func _test_squad_drivers() -> void:
	print("Squad drivers")
	var drivers := SquadDrivers.of(level)
	check(drivers != null, "every level's vehicles have the squad's drivers")
	if drivers == null:
		return
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-12, 0, 6))
	var door := layer._nearest_door(v, v.global_position - v.global_basis.x * 4.0)
	var medic := _soldier("friendly", door + Vector3(0, 0.1, 0), "DrvMedic")
	medic.role = Roles.MEDIC
	var rifle := _soldier("friendly", door + Vector3(0, 0.1, 0.5), "DrvRifle")
	rifle.role = Roles.RIFLEMAN
	await get_tree().physics_frame
	player.global_position = v.global_position + Vector3(0, 0.1, 14)
	var why := drivers.server_command(player, "take_wheel", v.global_position, PackedStringArray(["DrvMedic", "DrvRifle"]))
	await _wait_for(func() -> bool: return v.driver() != null, 10.0)
	check(why == "" and v.driver() == rifle, "Take the wheel: the rifleman drives, not the medic (%s, %s)" % [why, v.driver().name if v.driver() else "nobody"])
	check(drivers.server_command(player, "take_wheel", v.global_position, PackedStringArray()).contains("already has the wheel"), "and once he has it, nobody else is sent")
	# Drive there: the commander on foot sends every vehicle the squad drives.
	var goal := Vector3(-12, 0, -20)
	why = drivers.server_command(player, "drive_to", goal, PackedStringArray())
	await _wait_for(func() -> bool: return v.ai.status == "arrived", 30.0)
	var d := Vector2(v.global_position.x - goal.x, v.global_position.z - goal.z).length()
	check(why == "" and v.ai.status == "arrived" and d < VehicleAI.ARRIVE_M + 2.0, "Drive there: it goes and stops (%.1f m off, %s)" % [d, why])
	# Pick us up: it comes to the commander, stops short, and a squadmate on foot gets in.
	player.global_position = Vector3(10, 0.1, 4)
	var walker := _soldier("friendly", player.global_position + Vector3(2, 0, 2), "DrvWalker")
	await get_tree().physics_frame
	why = drivers.server_command(player, "pickup", Vector3.ZERO, PackedStringArray())
	await _wait_for(func() -> bool: return drivers.order_of(v) == SquadDrivers.Order.HOLD, 30.0)
	var gap := Vector2(v.global_position.x - player.global_position.x, v.global_position.z - player.global_position.z).length()
	check(why == "" and drivers.order_of(v) == SquadDrivers.Order.HOLD and gap < SquadDrivers.PICKUP_STOP_M + 7.0,
		"Come pick us up: it pulls up %.0f m from him (%s)" % [gap, why])
	await _wait_for(func() -> bool: return v.seat_of(walker) >= 0 or layer.boarding_count() > 0, 5.0)
	check(v.seat_of(walker) >= 0 or layer.boarding_count() > 0, "and the squadmates on foot are sent to get in (%d on their way)" % layer.boarding_count())
	layer.server_cancel_boarding(v)
	if v.seat_of(walker) < 0:
		v.server_enter(walker)  # (the range has no navmesh to walk them over: seat him for the contact drill)
	# Contact: under orders and hit, it stops and the passengers get out; the driver stays.
	drivers.server_command(player, "drive_to", Vector3(-12, 0, -20), PackedStringArray())
	await _seconds(1.0)
	v.damaged.emit(&"hull", {})
	await _wait_for(func() -> bool: return drivers.order_of(v) == SquadDrivers.Order.HOLD and v.seat_of(walker) < 0, 6.0)
	check(drivers.order_of(v) == SquadDrivers.Order.HOLD and v.seat_of(walker) < 0 and v.driver() == rifle,
		"hit on the move: it stops, the squadmate in the back gets out, the driver stays")
	# A column behind the commander (on foot).
	player.global_position = Vector3(-30, 0.1, -10)
	await _seconds(0.5)
	why = drivers.server_command(player, "convoy", Vector3.ZERO, PackedStringArray())
	var near_enough := SquadDrivers.CONVOY_GAP_M + SquadDrivers.CONVOY_HOLD_M + 8.0  # (and the M-ATV's own length)
	await _wait_for(func() -> bool: return v.global_position.distance_to(player.global_position) < near_enough and v.linear_velocity.length() < 0.8, 30.0)
	gap = v.global_position.distance_to(player.global_position)
	check(why == "" and gap < near_enough and gap > 10.0, "Follow me: it comes up behind him and waits, not on top of him (%.0f m)" % gap)
	check(drivers.server_command(player, "drive_stop", Vector3.ZERO, PackedStringArray()) == "" and drivers.order_of(v) == SquadDrivers.Order.HOLD, "Stop the vehicles")
	check(drivers.server_command(player, "contact_dismount", Vector3.ZERO, PackedStringArray()).ends_with("off") and not drivers.dismount_on_contact, "the contact drill can be turned off")
	drivers.dismount_on_contact = true
	# The high command's elements (AlliedTroops "mount", "drive", "dismount") use the same tools.
	for s: Soldier in v.occupants():
		v.server_exit(s)
	for s: Soldier in [medic, rifle, walker]:
		s.global_position = Vector3(40, 0.1, 40) + Vector3(randf() * 4.0, 0, 0)  # (clear of its way: a bump is a hit, and a hit is contact)
	await _reset(v, Vector3(-12, 0, 6))
	var element := Squad.new()
	element.name = "TestElement"
	element.faction = &"friendly"
	level.add_child(element)
	var door2 := layer._nearest_door(v, v.global_position - v.global_basis.x * 4.0)
	var men: Array[Soldier] = []
	for k in 2:
		var man := _soldier("friendly", door2 + Vector3(0, 0.1, 0.6 * k), "Elem%d" % k)
		man.role = Roles.RIFLEMAN
		SquadAI.of(man).squad = element
		men.append(man)
	await get_tree().physics_frame
	why = drivers.server_squad_mount(player, element, v.global_position + Vector3(-8, 0, 0))
	check(why == "" and v.driver() in men and men.all(func(m: Soldier) -> bool: return v.seat_of(m) >= 0),
		"an element told to mount the vehicle 8 m off: one at the wheel, the other aboard (%s)" % why)
	drivers._hit_at.clear()  # (the hit staged above is still inside CONTACT_S: it would stop this drive too)
	why = drivers.server_squad_drive(player, element, Vector3(-12, 0, -20))
	await _wait_for(func() -> bool: return v.ai.status == "arrived", 30.0)
	check(why == "" and v.ai.status == "arrived", "and drives where the high command says (%s, order %d)" % [v.ai.status, drivers.order_of(v)])
	why = drivers.server_squad_dismount(player, element)
	await get_tree().physics_frame
	check(why == "" and men.all(func(m: Soldier) -> bool: return v.seat_of(m) < 0), "and gets out on the word (%s)" % why)
	for m in men:
		m.queue_free()
	element.queue_free()
	# By road (RoadRoute): a long drive with a road near both ends goes along it.
	var def := {"roads": [[[0, 0], [600, 0]], [[600, 0], [600, 600]], [[0, 0], [0, -400]]]}
	var way := RoadRoute.route(def, Vector2(-40, 30), Vector2(630, 560))
	var via_corner := way.size() > 0 and Array(way).any(func(p: Vector2) -> bool: return p.distance_to(Vector2(600, 0)) < 1.0)
	check(via_corner and way[way.size() - 1].distance_to(Vector2(630, 560)) < 1.0 and way[0].distance_to(Vector2(0, 0)) < 45.0,
		"by road: onto the road near the start, round the corner, off at the goal (%d points)" % way.size())
	check(RoadRoute.route(def, Vector2(-40, 30), Vector2(60, 30)).is_empty(), "a short drive goes straight")
	check(RoadRoute.route(def, Vector2(-40, 30), Vector2(300, 400)).is_empty(), "and so does one with no road near the goal")
	check(RoadRoute.route({"roads": [[[0, 0], [0, 900]], [[0, 900], [900, 900]], [[900, 900], [900, 0]]]}, Vector2(0, -20), Vector2(900, -20)).is_empty(),
		"or one the roads would take far round")
	# A player at the wheel keeps it.
	v.server_exit(rifle)
	check(v.server_enter(player, 0), "a player takes the wheel")
	check(drivers.server_command(player, "take_wheel", v.global_position, PackedStringArray(["DrvRifle"])) == "A player is driving it", "and nobody's sent to take it from him")
	v.server_exit(player)
	for s: Soldier in [medic, rifle, walker]:
		if v.seat_of(s) >= 0:
			v.server_exit(s)
		s.queue_free()
	player.global_position = Vector3(0, 0.1, 10)
	await _reset(v, Vector3(-12, 0, 6))


func _test_ragdoll_and_run_over() -> void:
	print("Ragdolls and run-overs")
	var v := _vehicle("range_matv")
	await _reset(v, Vector3(-30, 0, 0), 90.0)  # facing -x
	var dead := _soldier("hostile", Vector3(-40, 0.1, 0), "Lying")
	await get_tree().physics_frame
	dead.vitals.server_kill()
	var settled := await _wait_for(func() -> bool: return is_instance_valid(dead.ragdoll) and dead.ragdoll.frozen, 12.0)
	check(settled, "a body lies settled (a frozen ragdoll) in front of the M-ATV")
	var woke := false
	v.server_enter(player, 0)
	var end := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < end and v.global_position.x > -46.0:
		v.request_drive(0.6, 0.0, false)
		if is_instance_valid(dead.ragdoll) and not dead.ragdoll.frozen:
			woke = true
		await get_tree().physics_frame
	check(woke, "driving at it unfreezes the ragdoll")
	check(v.global_position.x < -42.0, "and the M-ATV pushes on past where it lay, not stopped as by a wall (x %.1f)" % v.global_position.x)
	await _drive(v, 0.0, 0.0, true, 2.0)
	dead.queue_free()
	# A soldier standing in its path.
	await _reset(v, Vector3(-30, 0, -20), 90.0)
	v.server_enter(player, 0)
	var walker := _soldier("hostile", v.global_position + (-v.global_basis.z) * 16.0 + Vector3(0, 0.1, 0), "InThePath")
	await get_tree().physics_frame
	var start_pain := walker.vitals.pain()
	end = Time.get_ticks_msec() + 6000
	var top := 0.0
	while Time.get_ticks_msec() < end and walker.vitals.pain() <= start_pain:
		v.request_drive(1.0, 0.0, false)
		top = maxf(top, v.forward_speed())
		await get_tree().physics_frame
	check(walker.vitals.pain() > start_pain, "running a soldier over at %.1f m/s is blunt trauma through the wound model (pain %.2f, %s)" % [top, walker.vitals.pain(), walker.vitals.condition_text()])
	await _drive(v, 0.0, 0.0, true, 2.5)
	v.server_exit(player)
	walker.queue_free()
	# A soldier standing in the way of one moving at a crawl: shoved aside, unhurt, not driven through.
	await _reset(v, Vector3(-30, 0, -40), 90.0)
	v.server_enter(player, 0)
	var stander := _soldier("hostile", v.global_position + (-v.global_basis.z) * 6.0 + Vector3(0, 0.1, 0), "Stander")
	await get_tree().physics_frame
	var stand_pain := stander.vitals.pain()
	var stand_x := stander.global_position.x
	var inside := 0
	var crawl_top := 0.0
	var half := VehicleArt.size_m(v.model) * 0.5
	end = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < end and v.global_position.x > stand_x - half.z - 2.0:
		v.request_drive(0.5 if v.forward_speed() < 1.6 else 0.0, 0.0, false)
		crawl_top = maxf(crawl_top, v.forward_speed())
		var at := v.to_local(stander.global_position)
		if absf(at.x) < half.x - 0.2 and absf(at.z) < half.z - 0.2:
			inside += 1
		await get_tree().physics_frame
	var off := absf(v.to_local(stander.global_position).x)
	check(v.global_position.x <= stand_x - half.z - 2.0 and crawl_top < Vehicle.RUN_OVER_MIN_MS,
		"the M-ATV crawls on past where he stood (%.1f m/s at most)" % crawl_top)
	check(inside == 0 and off > half.x and is_equal_approx(stander.vitals.pain(), stand_pain) and stander.vitals.is_up(),
		"a soldier standing in its way is shoved aside, clear of its side (%.2f m off the centreline), unhurt, never inside the hull (%d frames)" % [off, inside])
	await _drive(v, 0.0, 0.0, true, 1.5)
	v.server_exit(player)
	stander.queue_free()
	await _reset(v, Vector3(-12, 0, 6))


# --- Host: the late joiner -----------------------------------------------------------------------

## Before the client joins: a rider in the MaxxPro's seat 3, damage on it, the wreck from the
## fire test stays.
func _stage_for_client() -> void:
	var mrap := _vehicle("range_maxxpro")
	await _reset(mrap, Vector3(-4, 0, 6))
	var rider := _soldier("friendly", mrap.global_position + Vector3(3, 0.1, 0), LATE_SEATED)
	await get_tree().physics_frame
	mrap.server_enter(rider, 3)
	mrap.server_set_zone(Vehicle.ZONE_ENGINE, 0.55)
	mrap._add_carves([[0.0, 2.0, -1.0, 0.1, VehicleHull.HOLE]])
	mrap.turret.aim(1.2, 0.2)  # the MaxxPro's turret turned left and up: the late joiner sees it so
	mrap.turret.settle()
	var matv := _vehicle("range_matv")
	await _reset(matv, Vector3(-12, 0, 6))
	matv.turret.aim(0.0, 0.0)
	matv.turret.settle()
	player.global_position = Vector3(0, 0.1, 20)


func _on_client_joined(id: int) -> void:
	print("[host] client %d joined" % id)


## Client asks: what does the host have?
@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var out := {}
	for v in layer.vehicles():
		var seated := {}
		for i in v.seat_count():
			if v.occupant(i):
				seated[str(i)] = String(v.occupant(i).name)
		out[v.vehicle_id] = {"model": v.model, "wrecked": v.wrecked, "carves": v.net_carves.size(), "engine": v.zone_health(Vehicle.ZONE_ENGINE),
			"seated": seated, "pos": v.global_position, "turret": Vector2(v.turret.yaw, v.turret.pitch) if v.turret else Vector2.ZERO}
	return out


## Client tells the host what it drove: the host checks it saw the M-ATV move there too.
@rpc("any_peer", "reliable")
func _client_drove(id: String, start: Vector3) -> void:
	var v := _vehicle(id)
	var d := v.driver() if v else null
	_host_saw = {"moved": v.global_position.distance_to(start) if v else 0.0, "driver": String(d.name) if d else ""}


# --- Client ----------------------------------------------------------------------------------------

func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 420000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	print("Client joining the vehicle range late")
	check(joined[0], "joined the host's session")
	level = CompoundLevel.current(self) as VehicleRange
	check(level != null, "the host's vehicle range replaced the compound on joining")
	if level == null:
		_finish()
		return
	layer = level.get_node(^"Vehicles") as VehicleLayer
	var me_id := str(multiplayer.get_unique_id())
	await _wait_for(func() -> bool: return level.players.get_node_or_null(me_id) != null, 10.0)
	player = level.players.get_node_or_null(me_id)
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 10.0)
	await _wait_for(func() -> bool: return layer.vehicles().size() == _host_digest.size(), 10.0)
	check(layer.vehicles().size() == _host_digest.size() and _host_digest.size() >= 4, "the late joiner has every vehicle (%d)" % layer.vehicles().size())
	await _seconds(1.0)
	var same := true
	for id: String in _host_digest:
		var h: Dictionary = _host_digest[id]
		var v := _vehicle(id)
		if v == null or v.model != h.model or v.wrecked != h.wrecked or v.net_carves.size() != int(h.carves) or absf(v.zone_health(Vehicle.ZONE_ENGINE) - float(h.engine)) > 0.01 \
				or v.global_position.distance_to(h.pos) > 0.3:
			same = false
			print("    differs: %s %s vs host %s" % [id, [v.model, v.wrecked, v.net_carves.size(), v.zone_health(Vehicle.ZONE_ENGINE), v.global_position] if v else "missing", h])
	check(same, "each as the host has it: model, place, wreck, damage marks, engine health")
	var mrap := _vehicle("range_maxxpro")
	var rider := mrap.occupant(3) if mrap else null
	check(rider != null and String(rider.name) == LATE_SEATED and rider.global_position.distance_to(mrap.seat_transform("3").origin) < 0.1 and not rider.model.visible,
		"who sits where: the MaxxPro's rider in seat 3, at the seat, hidden inside")
	await _wait_for(func() -> bool: return mrap.hull.edit_count() > 0, 5.0)
	check(mrap.hull.edit_count() > 0, "and the MaxxPro's hull damage is drawn here too")
	var wreck := _vehicle("range_technical")
	check(wreck != null and wreck.wrecked and wreck.freeze, "the wreck is a wreck here too")
	var host_aim: Vector2 = (_host_digest.get("range_maxxpro", {}) as Dictionary).get("turret", Vector2.ZERO)
	var mrap_turret := mrap.hull.art.get_node(^"Turret") as Node3D if mrap else null
	check(mrap and mrap.turret and Vector2(mrap.turret.yaw, mrap.turret.pitch).distance_to(host_aim) < 0.02 and mrap_turret and absf(mrap_turret.rotation.y - host_aim.x) < 0.02,
		"the MaxxPro's turret points where the host has it (%s, host %s)" % [Vector2(mrap.turret.yaw, mrap.turret.pitch) if mrap and mrap.turret else null, host_aim])
	if player == null:
		_finish()
		return
	# Drive the M-ATV.
	var matv := _vehicle("range_matv")
	player.set_physics_process(false)
	player.global_position = matv.global_position + Vector3(-1.5, 0.1, -0.5)
	await _seconds(0.5)  # the host sees us at the door
	check(not VehicleCamera.chase, "a fresh session starts in first person (Captain: FIRST_PERSON_DEFAULT)")
	VehicleCamera.chase = true  # the chase checks below (as B would)
	matv.request_enter.rpc_id(1, 0)
	await _wait_for(func() -> bool: return matv.seat_of(player) == 0, 5.0)
	check(matv.seat_of(player) == 0 and player.vehicle == matv, "the client gets in as driver (through the host)")
	var start := matv.global_position
	var end := Time.get_ticks_msec() + int(CLIENT_DRIVE_S * 1000)
	var seat_err := 0.0
	await get_tree().process_frame
	while Time.get_ticks_msec() < end:
		matv.request_drive.rpc_id(1, 1.0, 0.0, false)
		await get_tree().process_frame  # as drawn: the vehicle and its rider placed this frame
		seat_err = maxf(seat_err, player.global_position.distance_to(matv.seat_transform("0").origin))
	var moved := matv.global_position.distance_to(start)
	check(moved > 8.0, "it drives: the client sees the M-ATV move %.1f m" % moved)
	check(seat_err < 0.05, "and its own player rides at the seat all the way (%.3f m off at worst)" % seat_err)
	# The chase camera is client side: the client's own seated player sees through it, following
	# the vehicle as the client draws it (VehicleCamera).
	var cam := VehicleCamera.of(player)
	var arm := VehicleCamera.arm_length(matv)
	var cam_off := (cam.global_position - VehicleCamera.pivot_of(matv)).length() if cam else INF
	check(cam != null and cam.active and get_viewport().get_camera_3d() == cam and cam_off < arm + 1.5
		and (cam.global_position - matv.global_position).dot(-matv.global_basis.z) < 0.0,
		"the client's driver sees through the chase camera, behind the M-ATV as it drives (%.1f m from the pivot, arm %.1f m)" % [cam_off, arm])
	var jumps := 0
	var last := matv.global_position
	for i in 30:
		matv.request_drive.rpc_id(1, 0.8, 0.0, false)
		await get_tree().process_frame
		if matv.global_position.distance_to(last) > 1.2:
			jumps += 1
		last = matv.global_position
	check(jumps == 0, "smoothly: no jumps between frames")
	_client_drove.rpc_id(1, "range_matv", start)
	end = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end:
		matv.request_drive.rpc_id(1, 0.0, 0.0, true)
		await get_tree().physics_frame
	matv.request_exit.rpc_id(1)
	await _wait_for(func() -> bool: return player.vehicle == null and matv.seat_of(player) < 0, 5.0)
	check(player.vehicle == null and player.global_position.distance_to(matv.global_position) > 1.2, "and gets out beside it")
	await get_tree().process_frame
	check(cam != null and not cam.active and get_viewport().get_camera_3d() == player.camera, "and sees through their own eyes again")
	await _client_turret(matv)
	await _seconds(0.5)
	_finish()


## Client: mans the M-ATV's turret (first person) and turns it: it turns here at once and
## smoothly, at the mount's speed, the host's turns there too, and the view is the gun's.
func _client_turret(matv: Vehicle) -> void:
	VehicleCamera.chase = false
	await _seconds(Vehicle.EXIT_GRACE_S + 0.2)
	matv.request_enter.rpc_id(1, 4)
	await _wait_for(func() -> bool: return matv.seat_of(player) == 4, 5.0)
	check(matv.seat_of(player) == 4 and matv.turret != null, "the client mans the M-ATV's turret (through the host)")
	if matv.seat_of(player) != 4:
		return
	await _seconds(0.3)
	matv.turret.aim(-1.0, 0.15)  # as the mouse would: the gunner's own peer sets where it goes
	var worst := 0.0
	var last := matv.turret.yaw
	var end := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame
		worst = maxf(worst, absf(wrapf(matv.turret.yaw - last, -PI, PI)))
		last = matv.turret.yaw
	check(absf(matv.turret.yaw + 1.0) < 0.01 and absf(matv.turret.pitch - 0.15) < 0.01, "the client's turret turns there (%.2f, %.2f)" % [matv.turret.yaw, matv.turret.pitch])
	check(worst <= matv.turret.yaw_rate / Engine.physics_ticks_per_second * 1.05 + 0.001,
		"smoothly, never faster than the mount (worst %.3f rad a tick)" % worst)
	check((-player.camera.global_basis.z).dot(matv.barrel_direction()) > 0.99 and player.global_position.distance_to(matv.seat_transform("4").origin) < 0.05,
		"first person: the client looks along the gun, standing at the turned ring")
	_host_digest = {}
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 10.0)
	var host_aim: Vector2 = (_host_digest.get("range_matv", {}) as Dictionary).get("turret", Vector2(INF, INF))
	check(host_aim.distance_to(Vector2(-1.0, 0.15)) < 0.02, "and the host's turret is there too (%s)" % host_aim)
	matv.request_exit.rpc_id(1)
	await _wait_for(func() -> bool: return player.vehicle == null, 5.0)
	VehicleCamera.chase = true
