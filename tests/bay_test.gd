extends Node
## The VTOLs' walk-in bays (VehicleBay; Captain 2026-10-16: bay doors that toggle, FFV seats for
## players and AI, walkable "if not the Petrel the Razorback for sure", landed only, and "make
## sure safety checks ensure they dont shoot our helo"). On the vehicle range, for the Petrel
## and the Razorback, landed:
## - shut, a walker can't get in through a door (or the Razorback's ramp);
## - open, a walker (a soldier-sized capsule on the same masks) goes up the boarding step
##   through each door into the cabin and back out, and up the Razorback's ramp;
## - a player in a door seat fires out of the open door, not inboard, not through the wall
##   beside the door, not into a nacelle, and not at all with the bay shut;
## - getting up with the bay open, a player stands in the aisle; at liftoff they're seated;
## - an AI in a door seat fires at an enemy out of that door.
##   <godot> --headless --path . res://tests/bay_test.tscn

const MODELS := ["vtol_petrel", "vtol_razorback"]
const WALK_SPEED := 2.5
const WALK_S := 7.0

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var layer: VehicleLayer
var _made := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_bay" + tag  # never touch a real save
	Campaign.campaign_id = "test_bay" + tag
	CompoundLevel.spawn_ai = false
	Vehicle.local_input = false
	Vehicle.fire_rolls = false
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("BAY TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the vehicle range")
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test moves it
	layer = level.get_node(^"Vehicles") as VehicleLayer
	for k in MODELS.size():
		await _model(String(MODELS[k]), Vector3(-60.0 + 40.0 * k, 0.0, -60.0))
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("BAY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _model(m: String, at: Vector3) -> void:
	print(m)
	# A solid floor plate under it at the ground its gear stands on (local y 0): on the range the
	# drawn ground stands ~1 m over the collision plane, so a body put on it dropped a metre (a
	# range quirk, not the bay's business); it's moved under the vehicle once that has settled.
	var plate := StaticBody3D.new()
	var plate_col := CollisionShape3D.new()
	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(40, 1, 50)
	plate_col.shape = plate_box
	plate.add_child(plate_col)
	level.add_child(plate)
	plate.global_position = level.ground_point(at) + Vector3.DOWN * 0.5
	player.global_position = level.ground_point(at + Vector3(0, 0, 14)) + Vector3.UP * 0.1
	await _seconds(0.5)
	var v := layer.server_spawn(m, Transform3D(Basis(), at), "", &"player", "test_bay_" + m)
	check(v != null and v.bay != null, "%s spawns with a bay" % m)
	if v == null or v.bay == null:
		return
	await _wait_for(func() -> bool: return VehicleHull.is_ready(m), 30.0)
	await _seconds(1.5)  # settle on the gear
	plate.global_transform = Transform3D(v.global_basis, v.global_transform * Vector3(0, -0.5, 0))
	await get_tree().physics_frame
	var bay := v.bay
	var spec: Dictionary = v.spec.bay
	var cabin := VehicleSpecs.box(spec.cabin)
	var middle := Vector3(0.0, cabin.position.y + 0.05, cabin.get_center().z)
	# Shut: no way in.
	v.server_set_bay(false)
	await _seconds(VehicleBay.PANEL_S + 0.3)
	for d: Dictionary in spec.doors:
		var door := VehicleSpecs.box(d.box)
		var side := signf(door.get_center().x)
		var z := door.get_center().z
		var got := await _walk(v, [Vector3(side * 5.5, 0.0, z), Vector3(side * 1.6, cabin.position.y, z), middle])
		check(not bay.inside(got), "%s shut: no way in through the %s door (stopped at %s)" % [m, d.name, _local(v, got)])
		got.queue_free()
	if spec.has("ramp"):
		var got := await _walk(v, [Vector3(0, 0, cabin.end.z + 4.0), Vector3(0, 0, cabin.end.z - 1.0), middle])
		check(not bay.inside(got) or _local(v, got).z > 5.2, "%s shut: no way in up the ramp (stopped at %s)" % [m, _local(v, got)])
		got.queue_free()
	# Open: in through each door, out again; up the ramp.
	var sat_at := v.global_position.y
	v.server_set_bay(true)
	check(bool(v.net_state.get("bay", false)), "%s: the bay's open state goes out to every peer" % m)
	await _seconds(maxf(VehicleBay.PANEL_S, VehicleBay.STEP_S) + 0.8)
	check(absf(v.global_position.y - sat_at) < 0.1, "%s: the ramps down on the ground don't lift it (%.2f m)" % [m, v.global_position.y - sat_at])
	var ramps_down := true
	for i in (spec.get("steps", []) as Array).size():
		var shape := v.get_node_or_null(NodePath("BayDeck/BayStep%d" % i)) as CollisionShape3D
		ramps_down = ramps_down and shape != null and not shape.disabled
	check(ramps_down, "%s open, landed: the boarding ramps are out and down" % m)
	for d: Dictionary in spec.doors:
		var door := VehicleSpecs.box(d.box)
		var side := signf(door.get_center().x)
		var z := door.get_center().z
		var got := await _walk(v, [Vector3(side * 5.5, 0.0, z), Vector3(side * 1.6, cabin.position.y, z), middle])
		check(bay.inside(got), "%s open: up the step and in through the %s door (at %s)" % [m, d.name, _local(v, got)])
		if not bay.inside(got):
			_what_blocks(v, got, Vector3(-side, 0, 0))
		var out_to := Vector3(side * 5.5, 0.0, z)
		await _walk_on(v, got, [Vector3(side * 1.6, cabin.position.y, z), out_to])
		var flat := _local(v, got)
		check(not bay.inside(got) and absf(flat.x) > 3.0 and flat.y < 0.4, "%s open: back out of the %s door to the ground (at %s)" % [m, d.name, flat])
		got.queue_free()
	if spec.has("ramp"):
		if OS.get_environment("BAY_TRACE") != "":
			var e := v.global_basis.get_euler() * 180.0 / PI
			print("    tilt deg %s, origin %s" % [e.snapped(Vector3.ONE * 0.1), v.global_position.snapped(Vector3.ONE * 0.01)])
			for gz: float in [-8.0, 1.5, 5.0, 8.5, 11.0]:
				var gp := level.ground_point(v.global_transform * Vector3(0, 0, gz))
				print("    ground at local z %.1f: local y %.2f" % [gz, (v.global_transform.affine_inverse() * gp).y])
			var rs := v.get_node(^"BayDeck/BayRamp") as CollisionShape3D
			print("    ramp shape %s disabled=%s" % [rs.transform.origin.snapped(Vector3.ONE * 0.01), rs.disabled])
		var got := await _walk(v, [Vector3(0, 0, cabin.end.z + 4.0), Vector3(0, 0, cabin.end.z - 1.0), middle])
		check(bay.inside(got) and _local(v, got).y > cabin.position.y - 0.3, "%s open: up the ramp into the cabin (at %s)" % [m, _local(v, got)])
		got.queue_free()
	await _ffv(v, m)
	await _stand_and_lift(v, m)
	await _ai_ffv(v, m)
	v.queue_free()
	plate.queue_free()
	await get_tree().physics_frame


## A soldier-sized walker (the soldier's capsule, the living's masks) at local `points[0]`,
## walked through the rest.
func _walk(v: Vehicle, points: Array) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	b.add_child(col)
	b.collision_layer = 0
	b.collision_mask = SoldierMovement.UP_MASK
	b.floor_snap_length = 0.3
	level.add_child(b)
	var start := v.global_transform * ((points[0] as Vector3) + Vector3.UP * 0.1)  # on the plate (local y 0)
	b.global_position = start
	await get_tree().physics_frame
	await _walk_on(v, b, points.slice(1))
	return b


func _walk_on(v: Vehicle, b: CharacterBody3D, points: Array) -> void:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for p: Vector3 in points:
		var deadline := Time.get_ticks_msec() + int(WALK_S * 1000)
		while Time.get_ticks_msec() < deadline:
			var target := v.global_transform * p
			var flat := Vector3(target.x - b.global_position.x, 0, target.z - b.global_position.z)
			if flat.length() < 0.25:
				break
			var vel := flat.normalized() * WALK_SPEED
			vel.y = b.velocity.y - g * get_physics_process_delta_time() if not b.is_on_floor() else -0.5
			b.velocity = vel
			b.move_and_slide()
			if OS.get_environment("BAY_TRACE") != "" and Engine.get_physics_frames() % 15 == 0:
				var hits := PackedStringArray()
				for i in b.get_slide_collision_count():
					var c := b.get_slide_collision(i)
					var co := c.get_collider() as CollisionObject3D
					var sh := "?"
					if co:
						sh = String((co.shape_owner_get_owner(co.shape_find_owner(c.get_collider_shape_index())) as Node).name)
					hits.append("%s(%s L%d) n=%s" % [sh, co.get_path() if co else "?", co.collision_layer if co else -1, c.get_normal().snapped(Vector3.ONE * 0.01)])
				print("    trace %s floor=%s %s" % [_local(v, b), b.is_on_floor(), ", ".join(hits)])
			await get_tree().physics_frame


## Debug for a failed walk: what the walker runs into, inboard of it.
func _what_blocks(v: Vehicle, b: Node3D, dir_local: Vector3) -> void:
	var space := b.get_world_3d().direct_space_state
	for h: float in [0.1, 0.5, 0.9, 1.5]:
		var from := b.global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + v.global_basis * dir_local * 2.0, SoldierMovement.UP_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("    probe %.1f m: clear" % h)
			continue
		var co := hit.collider as CollisionObject3D
		var owner_name := "?"
		if co and hit.has("shape"):
			var owner_id := co.shape_find_owner(int(hit.shape))
			owner_name = String((co.shape_owner_get_owner(owner_id) as Node).name)
		print("    probe %.1f m: %s / %s at %s" % [h, co.name if co else "?", owner_name, _local(v, b) + (v.global_transform.affine_inverse() * (hit.position as Vector3) - _local(v, b))])


func _local(v: Vehicle, n: Node3D) -> Vector3:
	return (v.global_transform.affine_inverse() * n.global_position).snapped(Vector3.ONE * 0.01)


## Fire-from-vehicle and the no-shooting-our-own-helo checks, a player in a left door seat.
func _ffv(v: Vehicle, m: String) -> void:
	var seat := -1
	for i in v.seat_count():
		if String(v.spec.seats[i].get("ffv", "")) == "left":
			seat = i
			break
	check(seat >= 0, "%s has a left door seat" % m)
	if seat < 0:
		return
	check(v.server_enter(player, seat), "%s: the player sits in %s" % [m, v.seat_name(seat)])
	await _seconds(0.3)
	var eye := player.camera.global_position
	var left := -v.global_basis.x
	check(v.ffv_seat(player), "%s: the door seat is live with the bay open" % m)
	check(v.ffv_ok(player, (left + Vector3.DOWN * 0.15).normalized()), "%s: fires out of the left door" % m)
	check(not v.ffv_ok(player, v.global_basis.x), "%s: never inboard, across the cabin" % m)
	check(not v.ffv_ok(player, (left * 0.45 - v.global_basis.z).normalized()), "%s: never through the wall beside the door" % m)
	# Into our own nacelle or wing: the nearest rotor zone on this side, seen from the eye.
	var nacelle := Vector3.ZERO
	for z: Dictionary in v.spec.zones:
		if String(z.zone) == "rotor":
			var c := VehicleSpecs.box(z.box).get_center()
			if c.x < 0.0 and (nacelle == Vector3.ZERO or (v.global_transform * c).distance_to(eye) < (v.global_transform * nacelle).distance_to(eye)):
				nacelle = c
	var at_nacelle := (v.global_transform * nacelle - eye).normalized()
	check(not v.ffv_ok(player, at_nacelle), "%s: never into our own nacelle (%s)" % [m, nacelle])
	var rounds := player.inventory.rounds_in(player.active_slot)
	player._server_fire(eye, at_nacelle, player.active_slot)
	check(player.inventory.rounds_in(player.active_slot) == rounds, "%s: the host refuses a shot at our own nacelle (no round spent)" % m)
	v.server_set_bay(false)
	await _seconds(0.1)
	check(not v.ffv_ok(player, (left + Vector3.DOWN * 0.15).normalized()), "%s: bay shut, no firing from the seat" % m)
	check(not v.seat_open(seat), "%s: bay shut, the door seat counts as inside" % m)
	v.server_set_bay(true)
	await _seconds(0.1)
	check(v.seat_open(seat), "%s: bay open, the door seat is out in the open (seen, hit)" % m)


## Getting up in the open bay, then liftoff.
func _stand_and_lift(v: Vehicle, m: String) -> void:
	if v.seat_of(player) < 0:
		v.server_enter(player, v.bay.nearest_free_seat(v.global_position))
	v.server_exit(player)
	await _seconds(0.2)
	check(v.seat_of(player) < 0 and v.bay.inside(player), "%s: getting up with the bay open, the player stands in the aisle (at %s)" % [m, _local(v, player)])
	var heli := v as Helicopter
	var was := heli.mode
	var parked_at := v.global_transform
	v.freeze = true  # held where it is: FLYING would fly it off (the flight itself isn't this test's)
	heli.mode = Helicopter.Mode.FLYING  # lifting off
	await _wait_for(func() -> bool: return v.seat_of(player) >= 0, 2.0)
	check(v.seat_of(player) >= 0, "%s: at liftoff the player standing in the bay is seated (%s)" % [m, v.seat_name(v.seat_of(player)) if v.seat_of(player) >= 0 else "no seat"])
	await _seconds(VehicleBay.STEP_S + 0.2)
	var stowed := true
	for i in (v.spec.bay.get("steps", []) as Array).size():
		var shape := v.get_node_or_null(NodePath("BayDeck/BayStep%d" % i)) as CollisionShape3D
		stowed = stowed and shape != null and shape.disabled
	check(stowed, "%s: in the air the boarding ramps are stowed (the bay still open for FFV)" % m)
	heli.mode = was
	v.global_transform = parked_at
	v.freeze = false
	heli.mode = was
	v.server_exit(player)
	player.global_position = v.global_transform * Vector3(0, 0.1, 14)
	await _seconds(0.5)


## An AI in a right door seat fights an enemy standing off the right door.
func _ai_ffv(v: Vehicle, m: String) -> void:
	var seat := -1
	for i in v.seat_count():
		if String(v.spec.seats[i].get("ffv", "")) == "right" and v.occupant(i) == null:
			seat = i
			break
	var friend := _soldier("friendly", v.global_transform * Vector3(6, 0.1, 0))
	var foe := _soldier("hostile", v.global_transform * Vector3(30, 0.1, -2))
	check(v.server_enter(friend, seat), "%s: an AI sits in the right door seat" % m)
	var gunner := v.get_node_or_null(^"FfvGunner") as FfvGunner
	check(gunner != null, "%s: the host's FFV gunner is aboard" % m)
	if gunner == null:
		return
	var before := gunner.fired
	await _wait_for(func() -> bool: return gunner.fired > before, 6.0)
	check(gunner.fired > before, "%s: the AI fires at the enemy off the right door (%d rounds)" % [m, gunner.fired - before])
	v.server_set_bay(false)
	await _seconds(0.2)
	var shut := gunner.fired
	await _seconds(1.5)
	check(gunner.fired == shut, "%s: bay shut, the AI holds fire" % m)
	v.server_exit(friend)
	friend.queue_free()
	foe.queue_free()


func _soldier(faction: String, pos: Vector3) -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": "BT%d" % _made, "faction": faction, "variant": "woodland", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s
