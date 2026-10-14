extends Node
## Headless checks for movement and stance: hosts a real session and drives the host
## player's Movement node through its functions (not real keys), plus an AI-named body
## driven through its intent fields.
##   <voxel godot exe> --headless --path . res://tests/movement_test.tscn
## Exits with the number of failures.

const S := SoldierMovement.Stance
const SPOT := Vector3(30, 0.1, 40)  # open ground outside the compound

var failures := 0
var level: CompoundLevel
var player: Soldier
var move: SoldierMovement
var mover: Soldier  # AI-named body: moves from move_input on the host


func _ready() -> void:
	GameState.zone_id = "test_movement" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("MOVEMENT TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	move = player.movement
	player.global_position = SPOT
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	for i in 20:  # settle onto the ground
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
	await _frames(5)
	_test_bindings()
	await _test_stances()
	await _test_side_stances()
	await _test_hitboxes()
	await _test_lean()
	await _test_mount()
	_test_fire_modes()
	await _test_momentum()
	await _test_falls()
	await _test_stamina()
	await _test_load_tiers()
	_test_directions()
	_test_arms_and_ads()
	_test_turn_cap()
	await _test_wall_pull()
	await _test_ai_body()
	GameState.delete_save()
	print("MOVEMENT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_bindings() -> void:
	print("Key bindings")
	var expect := {
		&"crouch": [KEY_X], &"prone": [KEY_Z], &"stance_adjust": [KEY_CAPSLOCK], &"lean_left": [KEY_Q],
		&"lean_right": [KEY_E], &"mount": [KEY_C], &"fire_mode": [KEY_F], &"interact": [KEY_CTRL],
	}
	for action: StringName in expect:
		check(_keys(action) == expect[action], "%s on %s" % [action, _keys(action).map(func(k: int) -> String: return OS.get_keycode_string(k))])
	check(not KEY_CTRL in _keys(&"crouch") and not KEY_C in _keys(&"crouch"), "Ctrl and C no longer crouch")
	# Hold breath (movement phase 1): Shift, shared with sprint on purpose (no sprint aimed), and
	# clear of the vehicle view (B), the fire mode and command menu (F), get out (V), J and the
	# side mouse buttons (optic zoom).
	var others := []
	for action: StringName in [&"vehicle_view", &"fire_mode", &"get_out", &"zoom_in", &"zoom_out"]:
		others.append_array(_keys(action))
	check(_keys(&"hold_breath") == [KEY_SHIFT] and _keys(&"sprint") == [KEY_SHIFT] and not KEY_SHIFT in others and not KEY_J in _keys(&"hold_breath")
		and GameSettings.BINDABLE.any(func(p: Array) -> bool: return p[0] == &"hold_breath") and GameSettings.shares_key(&"hold_breath", &"sprint")
		and not GameSettings.shares_key(&"hold_breath", &"jump"),
		"hold breath on Shift (with sprint, never aimed), rebindable, clear of B, F, V, J and Mouse 4/5")


func _test_stances() -> void:
	print("Stances")
	check(move.stance == S.STAND_HIGH, "starts standing tall")
	var eyes: Array[float] = []
	for s in 7:
		eyes.append(CharacterModel.eye_position(SoldierMovement.pose_for(s, 0, 0.0)).y)
	var rising := true
	for s in range(1, 7):
		rising = rising and eyes[s] > eyes[s - 1] + 0.05
	check(rising, "seven stances, each eye level higher than the last (%s)" % [eyes.map(func(e: float) -> String: return "%.2f" % e)])
	check(absf(eyes[S.STAND_HIGH] - 1.65) < 0.01 and absf(eyes[S.CROUCH_MID] - 1.0) < 0.01 and eyes[S.PRONE] < 0.45,
		"stand 1.65 m, crouch 1.0 m, prone %.2f m" % eyes[S.PRONE])
	for s in 7:
		var eye := CharacterModel.eye_position(SoldierMovement.pose_for(s, 0, 0.0))
		if absf(eye.z) > SoldierMovement.EYE_FORWARD + 0.01 and s != S.PRONE:
			check(false, "eyes stay over the body in stance %d (z %.2f)" % [s, eye.z])
	move.toggle_crouch()
	check(move.stance == S.CROUCH_MID and player.is_crouching(), "X crouches")
	await _settle_pose(1.0)
	check(absf(player.head.position.y - 1.0) < 0.02, "camera at crouch height (%.2f)" % player.head.position.y)
	var capsule: CapsuleShape3D = player.get_node(^"Collision").shape
	check(is_equal_approx(capsule.height, SoldierMovement.STANCE_CAPSULE[S.CROUCH_MID]), "capsule shrinks to %.2f m" % capsule.height)
	check(not move.can_jump(), "no jump while crouched")
	move.toggle_crouch()
	check(move.stance == S.STAND_HIGH, "X again stands up")
	move.toggle_prone()
	check(move.stance == S.PRONE and player.is_crouching(), "Z goes prone")
	await _settle_pose(1.0)
	check(player.head.position.y < 0.45, "camera near the ground (%.2f)" % player.head.position.y)
	var collision: CollisionShape3D = player.get_node(^"Collision")
	check(absf(collision.global_basis.y.y) < 0.01, "capsule lies down")
	check(absf(move.top_speed(false, false) - 0.8) < 0.01, "prone crawl at 0.8 m/s")
	move.toggle_prone()
	check(move.stance == S.STAND_HIGH, "Z again returns to standing")
	move.toggle_crouch()
	move.toggle_prone()
	move.toggle_prone()
	check(move.stance == S.CROUCH_MID, "...or to the crouch you went prone from")
	move.set_stance(S.PRONE)
	var seen: Array[int] = [move.stance]
	for i in 8:
		move.step_stance(1)
		seen.append(move.stance)
	check(seen == [0, 1, 2, 3, 4, 5, 6, 6, 6], "Caps Lock + W steps up through every stance (%s)" % [seen])
	move.step_stance(-1)
	check(move.stance == S.STAND_MID, "Caps Lock + S steps down")
	await _settle_pose(1.0)
	check(absf(player.head.position.y - 1.5) < 0.02, "camera at the middle standing height (%.2f)" % player.head.position.y)
	move.set_stance(S.STAND_HIGH)
	check(player.get_node(^"Collision").shape != null and capsule != _new_soldier_capsule(), "each body resizes its own capsule")
	# Headroom: can't stand up under a low ceiling.
	move.set_stance(S.CROUCH_MID)
	var roof := _box(SPOT + Vector3(0, 1.45, 0), Vector3(2, 0.2, 2))
	await _frames(2)
	check(not move.toggle_crouch() and move.stance == S.CROUCH_MID, "no standing up under a 1.35 m ceiling")
	roof.free()
	await _frames(2)
	check(move.toggle_crouch() and move.stance == S.STAND_HIGH, "stands once it's gone")
	await _settle_pose(1.0)


func _test_side_stances() -> void:
	print("Side stances")
	move.shift_side(-1)
	check(move.side == -1, "Caps Lock + A: side stance left")
	var left := CharacterModel.eye_position(SoldierMovement.pose_for(move.stance, move.side, 0.0))
	move.shift_side(-1)
	check(move.side == -1, "can't go further left")
	move.shift_side(1)
	check(move.side == 0, "Caps Lock + D: back to centre")
	move.shift_side(1)
	var right := CharacterModel.eye_position(SoldierMovement.pose_for(move.stance, move.side, 0.0))
	check(left.x < -0.2 and right.x > 0.2, "head shifts out to the side (%.2f / %.2f)" % [left.x, right.x])
	check(move.top_speed(false, false) < SoldierMovement.WALK_SPEED, "slower in a side stance")
	move.set_stance(S.CROUCH_MID)
	var crouch_side := CharacterModel.eye_position(SoldierMovement.pose_for(move.stance, move.side, 0.0))
	check(crouch_side.x > 0.15 and crouch_side.y < 1.05, "crouching side stance (%.2f, %.2f)" % [crouch_side.x, crouch_side.y])
	move.set_stance(S.PRONE)
	var pose := SoldierMovement.pose_for(move.stance, move.side, 0.0)
	var root: Transform3D = CharacterModel.pose_bones(pose, false).root
	check(absf(pose.prone_roll) > 0.5 and absf(root.basis.x.y) > 0.5, "prone side stance rolls onto a side")
	move.shift_side(-1)
	move.set_stance(S.STAND_HIGH)
	check(move.side == 0, "back to centre")


func _test_hitboxes() -> void:
	print("Hitboxes follow the pose")
	var head := _hitbox(Vitals.HEAD)
	var torso := _hitbox(Vitals.CHEST)
	check(head != null and torso != null, "found hitboxes by their body_part meta")
	if head == null or torso == null:
		return
	await _frames(2)
	var rest_head := _shape_position(head)
	var rest_torso := torso.transform
	move.set_stance(S.CROUCH_MID)
	await _frames(2)
	check(_shape_position(head).y < rest_head.y - 0.5, "crouched: head hitbox drops (%.2f -> %.2f)" % [rest_head.y, _shape_position(head).y])
	move.set_stance(S.PRONE)
	await _frames(2)
	var prone_head := player.to_local(_shape_position(head))
	check(prone_head.y < 0.5 and prone_head.z < -0.3, "prone: head hitbox low and forward (%.2f, %.2f)" % [prone_head.y, prone_head.z])
	check(absf(torso.global_basis.y.y) < 0.3, "prone: torso hitbox lies flat")
	var eye := CharacterModel.eye_position(SoldierMovement.pose_for(S.PRONE, 0, 0.0))
	check(prone_head.distance_to(eye) < 0.3, "and sits where the camera is (%.2f m away)" % prone_head.distance_to(eye))
	var stood := player.global_transform
	player.vitals.server_damage(500.0)
	# A ragdoll now: it falls from the pose it was drawn in, so wait until it has come to rest.
	var left := 10.0
	while left > 0.0 and not (is_instance_valid(player.ragdoll) and player.ragdoll.frozen):
		await _seconds(0.1)
		left -= 0.1
	check(player.vitals.downed and absf(torso.global_basis.y.y) < 0.35, "downed still lays hitboxes down (lying flat with the body, a ragdoll now: up %.2f)" % torso.global_basis.y.y)
	player.vitals.server_reset_health()
	# Wait for the ragdoll to go: it moves the body to where it lay (Soldier._stand_where_ragdoll_lay)
	# on whichever frame it notices, so moving the body back before then loses to it (the flake).
	var gone := 120
	while is_instance_valid(player.ragdoll) and gone > 0:
		await get_tree().process_frame
		gone -= 1
	await _frames(2)
	# Up again: back to where it stood, which the later checks build their walls round, and
	# settled onto the ground (we drive the body; its own physics is off).
	player.global_transform = stood
	player.velocity = Vector3.ZERO
	move.set_stance(S.STAND_HIGH)
	for i in 20:
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
	await _settle_pose(0.6)
	check(torso.transform.is_equal_approx(rest_torso) and _shape_position(head).distance_to(rest_head) < 0.01, "standing again: back at rest")
	move.press_lean(-1)
	for i in 30:
		move.update_pose(1.0 / 60.0)
	await _frames(2)
	check(_shape_position(head).x < rest_head.x - 0.2, "leaning left moves the head hitbox left (%.2f)" % (_shape_position(head).x - rest_head.x))
	move.release_lean(-1)
	await _settle_pose(0.6)


func _test_lean() -> void:
	print("Lean")
	await _settle_pose(0.5)
	move.press_lean(-1)
	await _settle_pose(0.5)
	check(player.head.position.x < -0.25, "hold Q: head leans left (%.2f)" % player.head.position.x)
	check(player.head.rotation.z > 0.1, "and the view tilts left (%.2f)" % player.head.rotation.z)
	move.release_lean(-1)
	await _settle_pose(0.5)
	check(absf(player.head.position.x) < 0.01, "release: back upright")
	move.press_lean(1)
	await _settle_pose(0.5)
	check(player.head.position.x > 0.25 and player.head.rotation.z < -0.1, "hold E: head leans right (%.2f)" % player.head.position.x)
	move.release_lean(1)
	await _settle_pose(0.5)
	move.press_lean(1)
	move.release_lean(1)
	move.press_lean(1)
	move.release_lean(1)
	await _settle_pose(0.5)
	check(move.lean_target() == 1 and player.head.position.x > 0.25, "double-tap E: stays leaned after letting go")
	move.press_lean(1)
	move.release_lean(1)
	await _settle_pose(0.5)
	check(move.lean_target() == 0 and absf(player.head.position.x) < 0.01, "tap E again: back upright")
	move.press_lean(-1)
	move.release_lean(-1)
	await _seconds(0.4)
	move.press_lean(-1)
	move.release_lean(-1)
	check(move.lean_target() == 0, "two slow taps don't latch")
	# A wall on the right stops the lean short of it.
	var wall := _box(SPOT + Vector3(0.35, 1.5, 0), Vector3(0.1, 1, 1))
	await _frames(2)
	move.press_lean(1)
	await _settle_pose(0.5)
	check(player.head.position.x > 0.05 and player.head.position.x < 0.25, "a wall cuts the lean short (%.2f)" % player.head.position.x)
	move.release_lean(1)
	wall.free()
	await _settle_pose(0.5)


func _test_mount() -> void:
	print("Weapon mount")
	player.inventory.take(&"m4a1")
	await _frames(2)
	check(not move.toggle_mount() and not move.mounted, "nothing to rest on in the open")
	var spread := move.spread_mult()
	var recoil := move.recoil_mult()
	var sill := _box(SPOT + Vector3(0, 0.7, -0.5), Vector3(1, 1.4, 0.3))  # a wall top at 1.4 m
	await _frames(2)
	check(move.toggle_mount() and move.mounted, "C mounts on a wall top under the muzzle")
	check(is_equal_approx(move.spread_mult(), spread * 0.5) and is_equal_approx(move.recoil_mult(), recoil * 0.5),
		"mounted: half the sway and recoil (%.2f, %.2f)" % [move.spread_mult() / spread, move.recoil_mult() / recoil])
	var kicks: Array[float] = []
	for mounted in [false, true]:
		move.mounted = mounted
		player.head.rotation.x = 0.0
		player._kick(ItemDB.get_item(&"m4a1"))
		kicks.append(player.head.rotation.x)
	check(absf(kicks[1] - kicks[0] * 0.5) < 0.0001, "the view kicks half as far (%.4f vs %.4f rad)" % [kicks[1], kicks[0]])
	player.head.rotation.x = 0.0
	for i in 10:
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
	check(move.mounted, "stays mounted while still")
	move.set_stance(S.CROUCH_HIGH)
	check(not move.mounted, "changing stance unmounts")
	await _settle_pose(1.0)
	check(move.toggle_mount(), "crouched behind it: rests against the wall in front")
	move.toggle_mount()
	check(not move.mounted, "C again takes it off")
	sill.free()
	move.set_stance(S.STAND_HIGH)
	await _settle_pose(1.0)


func _test_fire_modes() -> void:
	print("Fire modes")
	check(Soldier.fire_modes_of(ItemDB.get_item(&"m4a1")) == PackedStringArray(["semi", "auto"])
		and Soldier.fire_modes_of(ItemDB.get_item(&"mk18")) == PackedStringArray(["semi", "auto"]), "M4 and Mk18: semi and auto")
	check(Soldier.fire_modes_of(ItemDB.get_item(&"m110")) == PackedStringArray(["semi"])
		and Soldier.fire_modes_of(ItemDB.get_item(&"m17")) == PackedStringArray(["semi"]), "M110 and M17: semi only")
	player.select_weapon(&"primary")
	check(player.fire_mode() == "semi", "M4 starts on semi")
	check(player.cycle_fire_mode() == "auto" and player.fire_mode() == "auto", "F: auto")
	check(player.cycle_fire_mode() == "semi", "F again: semi")
	player.cycle_fire_mode()
	player.inventory.take(&"m17")
	player.select_weapon(&"sidearm")
	check(player.fire_mode() == "semi" and player.cycle_fire_mode() == "semi", "pistol stays on semi")
	player.select_weapon(&"primary")
	check(player.fire_mode() == "auto", "each weapon keeps its own selector")
	check(not Soldier.trigger_fires("semi", true, false) and Soldier.trigger_fires("semi", true, true), "semi: one shot per pull")
	check(Soldier.trigger_fires("auto", true, false) and not Soldier.trigger_fires("auto", false, false), "auto: fires while held")
	check(ItemDB.get_item(&"m4a1").stats.get("auto", false), "AI keeps its own trigger logic (stats.auto unchanged)")


func _test_momentum() -> void:
	print("Momentum")
	var saved := player.load_mult
	player.load_mult = 1.0
	var light := _time_to(4.0 * 0.95)
	var light_stop := _time_to_stop()
	player.load_mult = Soldier.MIN_LOAD_MULT  # a full load
	var heavy := _time_to(4.0 * 0.95)
	var heavy_stop := _time_to_stop()
	var heavy_slide := _stop_distance(4.0)
	player.load_mult = 1.0
	var slide := _stop_distance(4.0)
	var sprint_slide := _stop_distance(SoldierMovement.SPRINT_SPEED)
	player.load_mult = saved
	check(light > 0.2 and light < 0.4, "unloaded: a jog in %.2f s" % light)
	check(light_stop > 0.1 and light_stop < 0.25, "unloaded: stops in %.2f s" % light_stop)
	check(heavy / light > 1.7 and heavy / light < 2.3 and heavy_stop / light_stop > 1.7, "a full load roughly doubles both (%.2f s, %.2f s)" % [heavy, heavy_stop])
	check(slide > 0.2 and slide < 0.5 and sprint_slide < 0.9 and heavy_slide < 0.9,
		"stops over a short distance, no ice (jog %.2f m, sprint %.2f m, loaded jog %.2f m)" % [slide, sprint_slide, heavy_slide])
	var turned := move.next_velocity(Vector3(0, 0, -4), Vector3(4, 0, 0), 1.0 / 60.0)
	check(turned.z < -3.0, "momentum carries into a turn (%.1f m/s still forward)" % -turned.z)
	var drift := _turn_drift(Vector3(4, 0, 0))
	check(drift > 0.05 and drift < 0.3, "a 90 degree turn drifts the old way only %.2f m" % drift)
	var back := _turn_drift(Vector3(0, 0, 4))
	check(back < 0.5, "turning right round brakes first (%.2f m on)" % back)
	var v := Vector3(0, 0, -4)
	var slowest := 4.0
	for i in 30:
		v = move.next_velocity(v, Vector3(0, 0, -4).rotated(Vector3.UP, deg_to_rad(30)), 1.0 / 120.0)
		slowest = minf(slowest, v.length())
	check(slowest > 3.4, "a gentle turn keeps its pace (%.1f m/s at the slowest)" % slowest)


## Falls (design doc "Other damage"): the owner reports the drop on landing, the host applies it.
func _test_falls() -> void:
	print("Falls")
	player.vitals.server_reset_health()
	await _drop(2.0)
	check(player.vitals.pain() == 0.0 and player.vitals.wound_list().is_empty(), "a 2 m drop: nothing")
	await _drop(5.0)
	check(player.vitals.pain() >= WoundModel.FALL_PAIN.x, "a 5 m drop hurts the legs (pain %.2f, %s)" % [player.vitals.pain(), player.vitals.wound_list().map(func(w: Dictionary) -> String: return w.kind)])
	player.vitals.server_reset_health()
	player.global_position = SPOT
	await _frames(2)


## Puts the player `height` metres up over SPOT and steps them until they land.
func _drop(height: float) -> void:
	player.global_position = SPOT + Vector3.UP * height
	player.velocity = Vector3.ZERO
	for i in 300:
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
		if player.is_on_floor() and i > 2:
			break


func _test_stamina() -> void:
	print("Stamina")
	move.stamina = 1.0
	var saved := player.load_kg
	player.load_kg = 10.0
	move.update_stamina(1.0, true, true)
	var light_drain := 1.0 - move.stamina
	move.stamina = 1.0
	player.load_kg = 30.0
	move.update_stamina(1.0, true, true)
	var burdened_drain := 1.0 - move.stamina
	move.stamina = 1.0
	player.load_kg = 45.0
	move.update_stamina(1.0, true, true)
	var heavy_drain := 1.0 - move.stamina
	player.load_kg = 10.0
	check(light_drain > 0.0 and absf(burdened_drain / light_drain - 1.5) < 0.05 and absf(heavy_drain / light_drain - 2.0) < 0.05,
		"sprinting drains stamina: x1.5 burdened, x2 overloaded (%.3f, %.3f, %.3f a second)" % [light_drain, burdened_drain, heavy_drain])
	move.set_stance(S.CROUCH_MID)
	move.stamina = 0.5
	move.update_stamina(1.0, false, false)
	var crouched := move.stamina - 0.5
	move.set_stance(S.PRONE)
	move.stamina = 0.5
	move.update_stamina(1.0, false, false)
	var prone := move.stamina - 0.5
	move.set_stance(S.STAND_HIGH)
	move.stamina = 0.5
	move.update_stamina(1.0, false, false)
	var standing := move.stamina - 0.5
	check(absf(crouched / standing - 1.25) < 0.02 and absf(prone / standing - 1.45) < 0.02,
		"stamina comes back x1.25 crouched, x1.45 prone (Tarkov's rates)")
	move.stamina = 1.0
	var seconds := 0
	while move.stamina > 0.0 and seconds < 100:
		move.update_stamina(1.0, true, true)
		seconds += 1
	check(seconds >= 10 and seconds <= 20 and not move.can_sprint(), "empty after %d s of sprint: no sprint" % seconds)
	move.update_stamina(1.0, false, false)
	check(move.stamina > 0.0 and not move.can_sprint(), "recovering, but not enough to sprint yet")
	move.update_stamina(2.0, false, false)
	check(move.can_sprint(), "rested: can sprint again")
	move.stamina = 1.0
	player.load_kg = saved


## Load tiers (movement phase 1, MovementRules): light, burdened, overloaded, critical.
func _test_load_tiers() -> void:
	print("Load tiers")
	check(MovementRules.tier_of(10.0) == MovementRules.Tier.LIGHT and MovementRules.tier_of(24.9) == MovementRules.Tier.LIGHT
		and MovementRules.tier_of(25.0) == MovementRules.Tier.BURDENED and MovementRules.tier_of(39.9) == MovementRules.Tier.BURDENED
		and MovementRules.tier_of(40.0) == MovementRules.Tier.OVERLOADED and MovementRules.tier_of(55.0) == MovementRules.Tier.CRITICAL,
		"tiers start at 25, 40 and 55 kg")
	var speeds := [MovementRules.load_speed_mult(20.0), MovementRules.load_speed_mult(40.0), MovementRules.load_speed_mult(55.0),
		MovementRules.load_speed_mult(70.0), MovementRules.load_speed_mult(90.0)]
	var smooth := true
	var last := 1.0
	for i in 200:
		var m := MovementRules.load_speed_mult(i * 0.5)
		smooth = smooth and m <= last + 0.0001 and last - m < 0.01
		last = m
	check(is_equal_approx(speeds[0], 1.0) and is_equal_approx(speeds[1], 0.9) and is_equal_approx(speeds[2], 0.75)
		and is_equal_approx(speeds[3], 0.55) and is_equal_approx(speeds[4], 0.55) and smooth,
		"speed x1 to 25 kg, x0.9 at 40, x0.75 at 55, x0.55 at 70, no step anywhere (%s)" % [speeds])
	player._on_inventory_changed()
	check(is_equal_approx(player.load_kg, player.inventory.total_mass()) and player.load_tier() == MovementRules.tier_of(player.load_kg),
		"the body's load is its inventory's mass (%.1f kg, tier %d)" % [player.load_kg, player.load_tier()])
	var saved_kg := player.load_kg
	var saved_mult := player.load_mult
	for i in 10:  # on the ground, so the jump checks mean something
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
	var sprints := []
	var jumps := []
	for kg: float in [10.0, 30.0, 45.0, 60.0]:
		player.load_kg = kg
		move.stamina = 1.0
		sprints.append(move.can_sprint())
		jumps.append(move.can_jump())
	check(sprints == [true, true, false, false], "sprint while light or burdened, not overloaded or critical (%s)" % [sprints])
	check(jumps == [true, true, true, false], "jump unless critical (%s)" % [jumps])
	player.load_kg = 10.0
	player.load_mult = 1.0
	move.sprint_ramp = 1.0
	var light_sprint := move.top_speed(true, false)
	player.load_kg = 39.0
	var burdened_sprint := move.top_speed(true, false)
	check(absf(light_sprint - SoldierMovement.SPRINT_SPEED) < 0.01 and burdened_sprint < light_sprint - 0.5 and burdened_sprint > SoldierMovement.WALK_SPEED,
		"burdened, sprint loses some of its edge (%.2f m/s light, %.2f near overloaded, before the load's own slowing)" % [light_sprint, burdened_sprint])
	move.sprint_ramp = 0.0
	check(absf(move.top_speed(true, false) - SoldierMovement.WALK_SPEED) < 0.01, "a sprint starts from a jog (sprint ramp)")
	player.load_kg = 10.0
	move.stamina = 1.0
	move.jump()
	var light_cost := 1.0 - move.stamina
	player.load_kg = 30.0
	move.stamina = 1.0
	move.jump()
	var burdened_cost := 1.0 - move.stamina
	check(absf(light_cost - 14.0 / 115.0) < 0.001 and absf(burdened_cost / light_cost - 1.5) < 0.01,
		"a jump costs %.0f%% of the legs (Tarkov's 14 of 115), x1.5 burdened" % (light_cost * 100.0))
	player.load_kg = 10.0
	move.stamina = move.jump_cost() * 0.5
	check(not move.can_jump(), "no jump without the legs for it")
	player.velocity = Vector3.ZERO
	for i in 30:
		await get_tree().physics_frame
		move.step(get_physics_process_delta_time())
	move.stamina = 1.0
	player.load_kg = 45.0
	check(absf(move.fall_scale() - 3.0 / 1.75) < 0.01, "overloaded, a 1.75 m drop lands like 3 m (Tarkov)")
	player.load_kg = 10.0
	check(move.fall_scale() == 1.0, "lighter, drops land as they are")
	player.load_kg = saved_kg
	player.load_mult = saved_mult


## Which way you move (movement phase 1): slower sideways and backwards, sprint forward only.
func _test_directions() -> void:
	print("Directional speed")
	var side := MovementRules.direction_mult(Vector2(1, 0))
	var back := MovementRules.direction_mult(Vector2(0, 1))
	var diag := MovementRules.direction_mult(Vector2(1, -1))
	check(is_equal_approx(MovementRules.direction_mult(Vector2(0, -1)), 1.0) and is_equal_approx(side, 0.85) and is_equal_approx(back, 0.7)
		and diag > 0.85 and diag < 1.0, "forward x1, strafe x0.85, backpedal x0.7, a forward diagonal between (%.2f)" % diag)
	check(is_equal_approx(MovementRules.direction_mult(Vector2(0, 1), MovementRules.MAX_LOAD_KG), 0.6), "backpedalling under a full load x0.6")
	check(MovementRules.sprint_direction_ok(Vector2(0, -1)) and MovementRules.sprint_direction_ok(Vector2(1, -1))
		and not MovementRules.sprint_direction_ok(Vector2(1, 0)) and not MovementRules.sprint_direction_ok(Vector2(0, 1))
		and not MovementRules.sprint_direction_ok(Vector2(1, -0.5)),
		"sprint only within 45 degrees of straight ahead")
	var saved := player.load_kg
	player.load_kg = 10.0
	var forward := move.top_speed(false, false, Vector2(0, -1))
	var strafe := move.top_speed(false, false, Vector2(1, 0))
	var backwards := move.top_speed(false, false, Vector2(0, 1))
	check(absf(strafe / forward - 0.85) < 0.01 and absf(backwards / forward - 0.7) < 0.01,
		"the body's top speed follows (jog %.2f, strafe %.2f, back %.2f m/s)" % [forward, strafe, backwards])
	player.load_kg = saved


## Arm stamina, ADS time by weapon mass, breathing and holding the breath (movement phase 1).
func _test_arms_and_ads() -> void:
	print("Arms, ADS time and breath")
	var m4 := ItemDB.get_item(&"m4a1")
	var pistol := ItemDB.get_item(&"m17")
	var m110 := ItemDB.get_item(&"m110")
	var scoped := Optics.with_optic(m4, {}, &"optic_dmr_3_15")
	check(is_equal_approx(MovementRules.weapon_mass(m4), m4.mass_kg) and MovementRules.weapon_mass(m4, scoped) > m4.mass_kg + 0.5,
		"a weapon's handling mass counts its mounted optic (M4 %.2f kg, with a 3-15x %.2f kg)" % [MovementRules.weapon_mass(m4), MovementRules.weapon_mass(m4, scoped)])
	var times := [MovementRules.ads_seconds(MovementRules.weapon_mass(pistol)), MovementRules.ads_seconds(MovementRules.weapon_mass(m4)),
		MovementRules.ads_seconds(MovementRules.weapon_mass(m4, scoped)), MovementRules.ads_seconds(MovementRules.weapon_mass(m110))]
	check(times[0] < times[1] and times[1] < times[2] and times[2] < times[3] and times[0] >= MovementRules.ADS_LIGHT_S and times[0] < 0.3
		and times[1] > 0.28 and times[1] < 0.4 and is_equal_approx(MovementRules.ads_seconds(MovementRules.ADS_HEAVY_KG), MovementRules.ADS_HEAVY_S),
		"ADS time rises with mass: pistol %.2f s, M4 %.2f s, M4 + 3-15x %.2f s, M110 %.2f s" % times)
	check(absf(MovementRules.ads_seconds(3.4, 0.0) / MovementRules.ads_seconds(3.4, 1.0) - 1.5) < 0.01, "empty arms: ADS x1.5 slower")
	player.select_weapon(&"primary")
	var rifle_kg := MovementRules.weapon_mass(player.active_weapon(), player.inventory.state_of(&"primary"))
	check(player.active_weapon() != null and absf(move.held_weapon_mass() - rifle_kg) < 0.001
		and absf(move.ads_seconds() - MovementRules.ads_seconds(rifle_kg)) < 0.001,
		"the body's ADS time is its rifle's (%.2f kg, %.2f s)" % [rifle_kg, move.ads_seconds()])
	var kg := move.held_weapon_mass()
	move.arm_stamina = 1.0
	move.update_arms(10.0, true, false)
	var standing := 1.0 - move.arm_stamina
	check(kg > 0.0 and absf(standing - 10.0 * MovementRules.arm_drain(kg)) < 0.001 and standing > 0.1 and standing < 0.3,
		"aiming the rifle 10 s uses %.0f%% of the arms (empty in about %.0f s)" % [standing * 100.0, 1.0 / maxf(MovementRules.arm_drain(kg), 0.0001)])
	move.update_arms(30.0, false, false)
	move.set_stance(S.PRONE)
	move.arm_stamina = 1.0
	move.update_arms(10.0, true, false)
	var prone := 1.0 - move.arm_stamina
	move.set_stance(S.STAND_HIGH)
	check(standing > 0.0 and absf(prone / standing - 0.15) < 0.01, "prone, the arms tire at x0.15 (Tarkov)")
	move.arm_stamina = 0.5
	var before := move.arm_stamina
	move.update_arms(5.0, false, false)
	check(move.arm_stamina > before + 0.2, "lowered, the arms come back")
	move.arm_stamina = 0.0
	move.stamina = 1.0
	move.update_arms(5.0, true, false)
	check(move.stamina < 1.0 and move.arm_stamina == 0.0, "arms empty: aiming drains the legs instead (%.3f)" % (1.0 - move.stamina))
	move.arm_stamina = 1.0
	move.stamina = 1.0
	move.update_arms(5.0, false, false)
	# Breath: hold, run out, gasp, let go, hold again.
	check(not move.breath_held and is_equal_approx(move.breath_sway_mult(), 1.0), "breathing normally")
	move.update_arms(0.1, false, true)
	check(not move.breath_held, "no holding the breath unaimed")
	move.update_arms(0.1, true, true)
	check(move.breath_held and is_equal_approx(move.breath_sway_mult(), MovementRules.BREATH_HOLD_SWAY), "aimed, the key holds the breath: sway x%.2f" % move.breath_sway_mult())
	var held := 0.1
	while move.breath_held and held < 20.0:
		move.update_arms(0.1, true, true)
		held += 0.1
	check(held > MovementRules.BREATH_HOLD_S - 0.5 and held < MovementRules.BREATH_HOLD_S + 0.5 and move.gasp_left() > 0.0 and move.breath_sway_mult() > 1.0,
		"fresh, a breath holds %.1f s, then a gasp: sway x%.1f" % [held, move.breath_sway_mult()])
	move.update_arms(3.0, true, true)
	check(not move.breath_held, "keeping the key down after it runs out doesn't hold again")
	move.update_arms(0.1, true, false)
	move.update_arms(0.1, true, true)
	check(move.breath_held, "let go and press again: holding again")
	move.update_arms(0.1, true, false)
	move.update_arms(5.0, false, false)
	move.stamina = 0.0
	var winded_hold := 0.0
	move.update_arms(0.1, true, true)
	while move.breath_held and winded_hold < 20.0:
		move.update_arms(0.1, true, true)
		winded_hold += 0.1
	check(winded_hold < MovementRules.BREATH_HOLD_MIN_S + 0.5, "out of breath, it holds only %.1f s" % winded_hold)
	move.update_arms(0.1, true, false)
	move.update_arms(5.0, false, false)
	# Breathing in the aim: bigger with tired arms and out of breath.
	player.is_aiming = true
	move.stamina = 1.0
	move.arm_stamina = 1.0
	var rested := player.breath_sway_deg(m4)
	move.arm_stamina = 0.0
	var tired_arms := player.breath_sway_deg(m4)
	move.stamina = 0.0
	var spent := player.breath_sway_deg(m4)
	player.is_aiming = false
	check(rested > 0.0 and tired_arms > rested * 2.5 and spent > tired_arms and player.breath_sway_deg(m4) == 0.0,
		"aimed, the breath moves the sight: %.3f deg rested, %.3f tired arms, %.3f spent; none unaimed" % [rested, tired_arms, spent])
	move.stamina = 1.0
	move.arm_stamina = 1.0
	move.update_stamina(0.0, false, false)


## Turn cap under load (players, movement phase 1): a light soldier flicks at once, a loaded
## one swings round at MAX_YAW_RATE, with nothing lost.
func _test_turn_cap() -> void:
	print("Turn cap")
	var input := player.player_input
	input.set_process(false)
	var saved := player.load_kg
	player.load_kg = 10.0
	input.advance_turn(1.0 / 60.0)
	var start := player.rotation.y
	input.turn_view(PI / 2.0)
	var light := absf(angle_difference(start, player.rotation.y))
	check(is_inf(input.max_yaw_rate()) and absf(light - PI / 2.0) < 0.001, "light: a 90 degree flick turns at once")
	player.load_kg = 60.0
	input.advance_turn(1.0 / 60.0)
	start = player.rotation.y
	input.turn_view(PI / 2.0)
	var first := rad_to_deg(absf(angle_difference(start, player.rotation.y)))
	for i in 6:
		input.advance_turn(1.0 / 60.0)
	var after := rad_to_deg(absf(angle_difference(start, player.rotation.y)))
	for i in 60:
		input.advance_turn(1.0 / 60.0)
	var done := rad_to_deg(absf(angle_difference(start, player.rotation.y)))
	var cap: float = MovementRules.MAX_YAW_RATE[MovementRules.Tier.CRITICAL]
	check(absf(first - cap / 60.0) < 0.01 and absf(after - cap * 7.0 / 60.0) < 0.05 and absf(done - 90.0) < 0.01,
		"critical load: %.1f deg in the first frame, %.1f in 7 frames (%.0f deg/s), all 90 in the end (%.1f)" % [first, after, cap, done])
	input.advance_turn(1.0 / 60.0)
	start = player.rotation.y
	input.turn_view(deg_to_rad(0.5))
	check(absf(rad_to_deg(angle_difference(start, player.rotation.y)) - 0.5) < 0.001, "small aiming moves aren't held back")
	check(MovementRules.MAX_YAW_RATE[MovementRules.Tier.BURDENED] > MovementRules.MAX_YAW_RATE[MovementRules.Tier.OVERLOADED]
		and MovementRules.MAX_YAW_RATE[MovementRules.Tier.OVERLOADED] > cap, "heavier tiers turn slower")
	player.load_kg = saved
	input.advance_turn(1.0 / 60.0)
	player.rotation = Vector3.ZERO
	input.set_process(true)


## The weapon pulls back from a wall close ahead (movement phase 1).
func _test_wall_pull() -> void:
	print("Weapon near a wall")
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await get_tree().physics_frame
	check(player.player_input.wall_pull_at() == 0.0, "open ground: no pull")
	var eye := player.camera.global_position
	var wall := _box(eye + Vector3(0, 0, -0.45), Vector3(2, 2, 0.1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pull := player.player_input.wall_pull_at()
	check(pull > 0.5 and pull <= 1.0, "a wall 0.4 m ahead pulls the weapon back (%.2f)" % pull)
	wall.free()
	await get_tree().physics_frame


func _test_ai_body() -> void:
	print("AI body (intent fields)")
	mover = load("res://scenes/soldier.tscn").instantiate()
	mover.name = "MoveTest"
	mover.position = SPOT + Vector3(6, 0, 0)
	level.add_child(mover)
	await _seconds(0.5)
	var m := mover.movement
	mover.move_input = Vector2(0, -1)
	await _seconds(0.15)
	var early := _speed(mover)
	await _seconds(0.5)
	var full := _speed(mover)
	check(early > 0.8 and early < 3.5 and full > 3.8, "picks up speed over time (%.1f then %.1f m/s)" % [early, full])
	mover.move_input = Vector2.ZERO
	await _seconds(0.15)
	check(_speed(mover) < 2.5, "and slows down over time too (%.1f m/s after 0.15 s)" % _speed(mover))
	await _seconds(0.25)
	check(m.settle > 0.3 and m.spread_mult() > SoldierMovement.STANCE_SPREAD[m.stance], "a stop leaves a little sway (%.2f)" % m.settle)
	await _seconds(1.0)
	check(m.settle < 0.01, "which settles")
	mover.move_input = Vector2(0, -1)
	mover.want_sprint = true
	await _seconds(1.0)
	check(m.is_sprinting and m.stamina < 1.0 and _speed(mover) > 5.0, "sprints, using stamina (%.2f left)" % m.stamina)
	mover.want_crouch = true
	await _seconds(0.8)
	check(m.stance == S.CROUCH_MID and not m.is_sprinting and _speed(mover) <= SoldierMovement.CROUCH_SPEED + 0.05, "want_crouch: crouches, no sprint (%.1f m/s)" % _speed(mover))
	mover.want_stance = S.PRONE
	await _seconds(1.5)
	check(m.stance == S.PRONE and absf(_speed(mover) - SoldierMovement.PRONE_SPEED) < 0.05, "want_stance prone: crawls at %.2f m/s" % _speed(mover))
	# Audit L4-02: no sprint where there's no room to stand up (low standing under a 1.68 m roof).
	var low_roof := _box(mover.global_position + Vector3(0, 1.78, 0), Vector3(40, 0.2, 40))
	mover.move_input = Vector2.ZERO
	mover.want_crouch = false
	mover.want_sprint = false
	mover.want_stance = S.STAND_LOW
	await _seconds(1.0)
	var rested := m.stamina
	mover.move_input = Vector2(0, -1)
	mover.want_sprint = true
	await _seconds(1.0)
	check(m.stance == S.STAND_LOW and not m.is_sprinting and _speed(mover) < 4.0 and m.stamina >= rested,
		"under a low roof it can't stand tall, so no sprint: no sprint speed, no stamina used (%.1f m/s)" % _speed(mover))
	low_roof.free()
	mover.want_stance = -1
	await _seconds(1.0)
	check(m.is_sprinting and _speed(mover) > 5.0, "out from under it, it sprints again (%.1f m/s)" % _speed(mover))
	# Movement phase 1 for the AI, through the same step: a sprint ramps up from a jog, sideways
	# and backwards are slower, no sprint sideways, none overloaded.
	mover.want_stance = -1
	mover.want_crouch = false
	mover.want_sprint = false
	mover.move_input = Vector2(0, -1)
	await _seconds(0.8)
	var jog := _speed(mover)
	mover.want_sprint = true
	await _seconds(0.12)
	var ramping := _speed(mover)
	await _seconds(0.6)
	var sprinting := _speed(mover)
	check(jog < 4.1 and ramping < 5.6 and sprinting > 6.2, "sprint builds from a jog (%.1f, %.1f after 0.12 s, %.1f m/s)" % [jog, ramping, sprinting])
	mover.move_input = Vector2(1, 0)
	await _seconds(0.8)
	var strafe := _speed(mover)
	check(not m.is_sprinting and absf(strafe - SoldierMovement.WALK_SPEED * 0.85) < 0.15, "sideways: no sprint, x0.85 (%.2f m/s)" % strafe)
	mover.move_input = Vector2(0, 1)
	await _seconds(0.8)
	var back := _speed(mover)
	check(not m.is_sprinting and absf(back - SoldierMovement.WALK_SPEED * 0.7) < 0.15, "backwards: x0.7 (%.2f m/s)" % back)
	mover.move_input = Vector2(0, -1)
	mover.load_kg = 45.0
	mover.load_mult = MovementRules.load_speed_mult(45.0)
	await _seconds(0.8)
	check(not m.is_sprinting and _speed(mover) < SoldierMovement.WALK_SPEED * 0.9 + 0.05, "overloaded, it doesn't sprint (%.2f m/s)" % _speed(mover))
	mover._on_inventory_changed()
	mover.want_stance = -1
	mover.want_crouch = false
	mover.want_sprint = false
	mover.move_input = Vector2.ZERO
	await _seconds(1.0)
	check(m.stance == S.STAND_HIGH, "stands back up")
	mover.inventory.take(&"m4a1")
	var wall := _box(mover.global_position + Vector3(0, 1.0, -0.6), Vector3(1, 2, 0.2))
	await _seconds(0.5)
	check(m.toggle_mount(), "mounts on the wall in front")
	mover.move_input = Vector2(1, 0)
	await _seconds(0.2)
	check(not m.mounted, "moving unmounts")
	mover.move_input = Vector2.ZERO
	wall.free()
	var config: SceneReplicationConfig = player.get_node(^"Sync").replication_config
	var synced := true
	for property in ["stance", "side", "lean", "mounted"]:
		synced = synced and config.has_property(NodePath("Movement:" + property))
	check(synced, "stance, side, lean and mounted replicate through Sync")
	mover.queue_free()


# --- Helpers ----------------------------------------------------------------------------

func _keys(action: StringName) -> Array:
	var keys := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(event.physical_keycode)
	return keys


func _hitbox(part: StringName) -> Area3D:
	for child in player.get_children():
		if child is Area3D and child.get_meta(&"body_part", &"") == part:
			return child
	return null


func _shape_position(area: Area3D) -> Vector3:
	for child in area.get_children():
		if child is CollisionShape3D:
			return child.global_position
	return area.global_position


func _new_soldier_capsule() -> Shape3D:
	var fresh: Node = load("res://scenes/soldier.tscn").instantiate()
	var shape: Shape3D = fresh.get_node(^"Collision").shape
	fresh.free()
	return shape


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	level.add_child(body)
	body.global_position = pos
	return body


## Eases the player's lean and camera for `seconds` of physics frames (no input read), and
## lets real time pass so the next lean key press isn't taken as a double-tap.
func _settle_pose(seconds: float) -> void:
	for i in int(seconds * 60.0):
		move.update_pose(1.0 / 60.0)
	await _seconds(SoldierMovement.DOUBLE_TAP_S + 0.05)


func _time_to(speed: float) -> float:
	var v := Vector3.ZERO
	var t := 0.0
	while v.length() < speed and t < 5.0:
		v = move.next_velocity(v, Vector3(0, 0, -4), 1.0 / 120.0)
		t += 1.0 / 120.0
	return t


func _time_to_stop() -> float:
	var v := Vector3(0, 0, -4)
	var t := 0.0
	while v.length() > 0.2 and t < 5.0:
		v = move.next_velocity(v, Vector3.ZERO, 1.0 / 120.0)
		t += 1.0 / 120.0
	return t


## Metres covered stopping from `speed` (m/s).
func _stop_distance(speed: float) -> float:
	var v := Vector3(0, 0, -speed)
	var travelled := 0.0
	for i in 600:
		v = move.next_velocity(v, Vector3.ZERO, 1.0 / 120.0)
		travelled += v.length() / 120.0
	return travelled


## Metres carried along the old heading (-z, at a jog) after turning to `target`.
func _turn_drift(target: Vector3) -> float:
	var v := Vector3(0, 0, -4)
	var travelled := 0.0
	for i in 600:
		v = move.next_velocity(v, target, 1.0 / 120.0)
		travelled += maxf(-v.z, 0.0) / 120.0
	return travelled


func _speed(body: Soldier) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
