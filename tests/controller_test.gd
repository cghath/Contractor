extends Node
## Controller support and co-op assists (wave 7, S4). On the vehicle range, as its host:
## - every gameplay action has a gamepad button or stick, or a pad wheel slice (Controls);
## - the right stick turns the view: nothing inside the deadzone, the full rate at full
##   deflection, down is down (and up with invert), fed as real joypad motion events;
## - the stick settings save and load with the rest (GameSettings, on a file of its own);
## - the pad wheel picks a slice by stick direction and presses its action on letting go;
## - the assists are off by default, the host sets them, a sync or request from anyone else
##   is refused;
## - aim slowdown slows the stick only with the assist on and an enemy under the crosshair;
## - wound hints name the worst wound only with the assist on.
##   <godot> --headless --path . res://tests/controller_test.tscn

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var settings_file := ""


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_controller" + tag
	Campaign.campaign_id = "test_controller" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("CONTROLLER TEST FAILED (timed out)")
		get_tree().quit(99))
	settings_file = "user://controller_test%s.cfg" % tag
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))
	GameSettings.use_file(settings_file)
	_test_bindings()
	_test_settings()
	await _test_wheel()
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
	player.set_physics_process(false)
	await _frames(2)
	await _test_stick_look()
	_test_assists()
	await _test_aim_slowdown()
	_test_wound_hints()
	_finish()


func _test_bindings() -> void:
	var actions: Array[StringName] = []
	for group: Dictionary in [Controls.KEYS, Controls.SHIFT_KEYS, Controls.MOUSE, Controls.BUTTONS]:
		for action: StringName in group:
			actions.append(action)
	for binding: Array in Controls.LEFT_KEYS:
		actions.append(binding[0])
	var missing: Array[StringName] = []
	for action in actions:
		if not Controls.PAD_EXEMPT.has(action) and not Controls.on_pad(action):
			missing.append(action)
	check(missing.is_empty(), "every gameplay action (%d) is on the pad: a button, a stick or a wheel slice (missing %s)" % [actions.size(), missing])
	for slice: Array in Controls.PAD_WHEEL:
		check(InputMap.has_action(slice[0]), "the wheel's %s is an input action" % slice[0])
	check(_has_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0) and _has_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0), "moving is on the left stick")
	check(_has_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0) and _has_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0), "looking is on the right stick")
	check(_has_axis(&"fire", JOY_AXIS_TRIGGER_RIGHT, 1.0) and _has_axis(&"aim", JOY_AXIS_TRIGGER_LEFT, 1.0), "fire on RT, aim on LT")
	check(_has_button(&"sprint", JOY_BUTTON_LEFT_STICK) and _has_button(&"jump", JOY_BUTTON_A) and _has_button(&"interact", JOY_BUTTON_Y), "sprint on L3, jump on A, interact on Y")
	var keys_kept := InputMap.action_get_events(&"move_forward").any(func(e: InputEvent) -> bool: return e is InputEventKey) \
		and InputMap.action_get_events(&"fire").any(func(e: InputEvent) -> bool: return e is InputEventMouseButton)
	check(keys_kept, "the keys and mouse buttons are still there beside them")
	GameSettings.apply_keys()  # rebinding keys leaves the pad alone
	check(_has_button(&"jump", JOY_BUTTON_A), "putting the key bindings into effect keeps the pad's")


func _test_settings() -> void:
	check(not bool(GameSettings.get_value("assists", "aim_slowdown")) and not bool(GameSettings.get_value("assists", "wound_hints")), "the assists' saved picks are off by default")
	check(is_equal_approx(float(GameSettings.get_value("gamepad", "stick_deadzone")), 0.15), "the stick deadzone defaults to 15%")
	GameSettings.set_value("gamepad", "stick_sensitivity", 1.75)
	GameSettings.set_value("gamepad", "stick_invert_y", true)
	GameSettings.reload()
	check(is_equal_approx(float(GameSettings.get_value("gamepad", "stick_sensitivity")), 1.75) and bool(GameSettings.get_value("gamepad", "stick_invert_y")), "the stick settings are saved and read back")
	GameSettings.set_value("gamepad", "stick_sensitivity", 1.0)
	GameSettings.set_value("gamepad", "stick_invert_y", false)
	check(GameSettings.stick_look(Vector2(0.1, 0.05)) == Vector2.ZERO, "inside the deadzone the stick does nothing")
	check(GameSettings.stick_look(Vector2(1, 0)).is_equal_approx(Vector2(1, 0)), "all the way over is the full rate")
	var half := GameSettings.stick_look(Vector2(0.5, 0)).x
	check(half > 0.0 and half < (0.5 - 0.15) / 0.85, "the curve keeps half travel finer than straight (%.3f)" % half)
	GameSettings.set_value("gamepad", "stick_invert_y", true)
	check(GameSettings.stick_look(Vector2(0, 1)).y < 0.0, "invert flips up and down")
	GameSettings.set_value("gamepad", "stick_invert_y", false)


func _test_wheel() -> void:
	var count := Controls.PAD_WHEEL.size()
	check(PadWheel.pick(Vector2(0, -1), count) == 0 and PadWheel.pick(Vector2(0.1, 0.1), count, 3) == 3, "the wheel: up picks the top slice, the middle keeps the last")
	var right := PadWheel.pick(Vector2(1, 0), count)
	check(right == roundi(count / 4.0) % count, "pushed right picks the slice at a quarter turn (%d)" % right)
	var wheel := PadWheel.new()
	add_child(wheel)
	var fire_mode := Controls.PAD_WHEEL.map(func(s: Array) -> StringName: return s[0]).find(&"fire_mode")
	var towards := Vector2.UP.rotated(TAU * fire_mode / count)  # (0,-1) turned clockwise
	check(wheel.update(true, towards) and wheel.chosen == fire_mode, "held, the stick lights the slice it points at (%d)" % wheel.chosen)
	wheel.update(false, Vector2.ZERO)
	await _frames(1)
	check(Input.is_action_pressed(&"fire_mode"), "let go, the slice's action is pressed")
	wheel.update(false, Vector2.ZERO)
	await _frames(1)
	check(not Input.is_action_pressed(&"fire_mode") and not wheel.is_open(), "and let go again the frame after")
	wheel.queue_free()


func _test_stick_look() -> void:
	var pi := player.player_input
	check(pi != null and pi.pad_wheel != null and pi.assist_line != null, "the player has the pad wheel and the assist line")
	var yaw := player.rotation.y
	await _stick(JOY_AXIS_RIGHT_X, 0.1)
	pi.update_pad(0.1)
	await _frames(2)
	check(is_equal_approx(player.rotation.y, yaw), "the right stick inside the deadzone doesn't turn the view")
	await _stick(JOY_AXIS_RIGHT_X, 1.0)
	pi.update_pad(0.1)
	await _frames(3)
	var turned := angle_difference(yaw, player.rotation.y)
	check(pi.stick.x > 0.99, "the stick reads all the way right (%.2f)" % pi.stick.x)
	check(absf(-turned - GameSettings.STICK_TURN_RATE * 0.1) < 0.05, "all the way right turns right at the full rate (%.3f rad in 0.1 s)" % -turned)
	await _stick(JOY_AXIS_RIGHT_X, 0.0)
	var pitch := player.head.rotation.x
	await _stick(JOY_AXIS_RIGHT_Y, 0.8)
	pi.update_pad(0.1)
	check(player.head.rotation.x < pitch, "down on the stick looks down (%.3f -> %.3f)" % [pitch, player.head.rotation.x])
	GameSettings.set_value("gamepad", "stick_invert_y", true)
	pitch = player.head.rotation.x
	pi.update_pad(0.1)
	check(player.head.rotation.x > pitch, "inverted, down on the stick looks up")
	GameSettings.set_value("gamepad", "stick_invert_y", false)
	await _stick(JOY_AXIS_RIGHT_Y, 0.0)
	pi.update_pad(0.1)
	check(pi.stick == Vector2.ZERO, "the stick back in the middle")


func _test_assists() -> void:
	check(not Assists.is_on("aim_slowdown") and not Assists.is_on("wound_hints"), "hosting, the assists start off")
	check(Assists.can_set(), "the host sets them")
	check(Assists.set_assist("wound_hints", true) and Assists.is_on("wound_hints"), "the host turns wound hints on")
	check(bool(GameSettings.get_value("assists", "wound_hints")), "and it's saved as the host's pick")
	check(Assists.set_assist("wound_hints", false) and not Assists.is_on("wound_hints"), "and off again")
	check(not Assists.set_assist("no_such_assist", true), "an unknown assist is refused")
	check(not Assists.accepts_sync_from(2) and not Assists.accepts_sync_from(3) and Assists.accepts_sync_from(1), "assists are taken only from the host (peer 1)")
	check(not Assists.accepts_request_from(2) and not Assists.accepts_request_from(4), "a client's request to change them is refused")
	var before: Dictionary = Assists.state.duplicate()
	Assists.request_assist("aim_slowdown", true)  # as if a client had sent it: changes nothing
	check(Assists.state == before, "a request changes nothing")
	Assists.receive({"aim_slowdown": 1, "junk": true})
	check(Assists.is_on("aim_slowdown") and not Assists.state.has("junk"), "a host's sync is taken, only its known keys")
	Assists.receive(Assists.defaults())


func _test_aim_slowdown() -> void:
	var cam := player.camera
	var ahead := cam.global_position - cam.global_basis.z * 20.0
	var hostile := level.spawn_soldier({"name": "PadTarget", "person_name": "PadTarget", "faction": "hostile", "variant": "woodland",
		"pos": Vector3(ahead.x, player.global_position.y, ahead.z), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(hostile).process_mode = Node.PROCESS_MODE_DISABLED
	hostile.set_physics_process(false)
	await _frames(2)
	hostile.global_position = Vector3(ahead.x, cam.global_position.y - 1.3, ahead.z)
	check(Assists.aim_slowdown_mult(player, cam) == 1.0, "aim slowdown off: no slowdown with an enemy under the crosshair")
	Assists.set_assist("aim_slowdown", true)
	var on_target := Assists.aim_slowdown_mult(player, cam)
	check(on_target < 0.6, "on: the stick slows over the enemy (x%.2f)" % on_target)
	var away := Assists.slowdown_near(player, cam.global_position, cam.global_basis.z)
	check(away == 1.0, "looking away, no slowdown")
	var yaw := player.rotation.y
	await _stick(JOY_AXIS_RIGHT_X, 1.0)
	player.player_input.update_pad(0.1)
	await _frames(3)
	var turned := absf(angle_difference(yaw, player.rotation.y))
	check(turned < GameSettings.STICK_TURN_RATE * 0.1 * 0.7, "the stick turns slower over the enemy (%.3f rad in 0.1 s)" % turned)
	await _stick(JOY_AXIS_RIGHT_X, 0.0)
	hostile.global_position = Vector3(0, -500, 0)
	check(Assists.slowdown_near(player, cam.global_position, -cam.global_basis.z) == 1.0, "no enemy near: no slowdown")
	Assists.set_assist("aim_slowdown", false)
	hostile.queue_free()


func _test_wound_hints() -> void:
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.INTERMEDIATE})
	check(not player.vitals.care_needed().is_empty(), "the player has a wound to treat")
	check(Assists.wound_hint(player) == "", "wound hints off: no hint")
	Assists.set_assist("wound_hints", true)
	var hint := Assists.wound_hint(player)
	check(hint.begins_with("Worst: ") and hint.contains("Use "), "on: the hint names the worst wound and what to use (%s)" % hint)
	Assists.set_assist("wound_hints", false)


func _stick(axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = 0
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)
	await _frames(1)


func _has_axis(action: StringName, axis: JoyAxis, dir: float) -> bool:
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == axis and signf((e as InputEventJoypadMotion).axis_value) == dir)


func _has_button(action: StringName, button: JoyButton) -> bool:
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button)


func check(condition: bool, what: String) -> void:
	if what == "":
		return
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	Assists.receive(Assists.defaults())
	GameState.delete_save()
	GameSettings.use_file("")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))
	print("CONTROLLER TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
