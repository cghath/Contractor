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
	if _want("cargo"):
		await _test_cargo()
	if _want("interaction"):
		await _test_interaction()
	if _want("charge"):
		await _test_charge()
	if _want("rounds"):
		await _test_rounds()
	if _want("fragments"):
		await _test_fragments()
	if _want("damage_effects"):
		await _test_damage_effects()
	if _want("carving_budget"):
		await _test_carving_budget()
	if _want("gun"):
		await _test_gun()
	if _want("service"):
		await _test_service()
	if _want("fire"):
		await _test_fire()
	if _want("save_reload"):
		await _test_save_reload()
	if _want("ai_driver"):
		await _test_ai_driver()
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
	check(counts.uh60 == {"pilot": 2, "passenger": 13}, "UH-60: 2 pilots, 2 crew and 11 passengers (%s)" % [counts.uh60])
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
		check(pilot_door == ["Get in (Aircraft are flown by AI pilots)", "Check vehicle ()"],
			"the pilot's door: one greyed Get in saying why, no 'Get in as pilot' (%s)" % [pilot_door])
		heli.queue_free()


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
	await get_tree().process_frame
	var bchest := (bed_rider.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	r = _shoot(shooter, bchest + Vector3(0, 6, 8), bchest, m4)
	check(r.result == "body" and not bed_rider.vitals.wound_list().is_empty(), "a passenger in the open bed can be shot from above and behind (%s)" % r.result)
	tech.server_exit(bed_rider)
	bed_rider.queue_free()
	shooter.queue_free()


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
	check(v.server_enter(player, 4) and v.gunner() == player, "the player mans the M-ATV's M2")
	var target := _soldier("hostile", v.global_position + Vector3(0, 0.1, -30), "GunTarget")
	await _seconds(0.3)
	var rounds := v.cargo_hold.feed_rounds(&"belt_50bmg")
	var chest := (target.get_node(^"ChestHitbox/Shape") as Node3D).global_position
	var origin := v.global_transform * VehicleSpecs.vec(v.spec.gun.at)
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
	await _seconds(0.2)
	v.server_fire_gun(player, (v.global_transform * Vector3(0, 0.8, -3.0) - origin).normalized())
	check(is_equal_approx(v.zone_health(Vehicle.ZONE_ENGINE), own), "a gunner firing down over the bonnet never hits their own vehicle")
	v.server_exit(player)
	target.queue_free()


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
	var matv := _vehicle("range_matv")
	await _reset(matv, Vector3(-12, 0, 6))
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
			"seated": seated, "pos": v.global_position}
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
	if player == null:
		_finish()
		return
	# Drive the M-ATV.
	var matv := _vehicle("range_matv")
	player.set_physics_process(false)
	player.global_position = matv.global_position + Vector3(-1.5, 0.1, -0.5)
	await _seconds(0.5)  # the host sees us at the door
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
	await _seconds(0.5)
	_finish()
