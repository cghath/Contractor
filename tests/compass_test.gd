extends Node
## Headless checks for the compass bearing strip (Compass): the pure bearing_of() function
## against a bare Node3D, and that the HUD's live compass tracks the player's facing.
##   <voxel godot exe> --headless --path . res://tests/compass_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_compass" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("COMPASS TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_bearing_of()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we turn the player by hand
	await _frames(5)
	await _test_hud_compass()
	GameState.delete_save()
	print("COMPASS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_bearing_of() -> void:
	print("Compass.bearing_of")
	var body := Node3D.new()
	add_child(body)
	check(is_equal_approx(Compass.bearing_of(body), 0.0), "facing spawn-forward (-Z) is north, 0 degrees")
	body.rotation.y = -PI / 2.0  # the mouse-right convention (PlayerInput.turn_view): a right turn
	check(is_equal_approx(Compass.bearing_of(body), 90.0), "a quarter turn right is east, 90 degrees")
	body.rotation.y = PI
	check(is_equal_approx(fposmod(Compass.bearing_of(body), 360.0), 180.0), "about-face is south, 180 degrees")
	body.rotation.y = PI / 2.0
	check(is_equal_approx(Compass.bearing_of(body), 270.0), "a quarter turn left is west, 270 degrees")
	body.queue_free()


func _test_hud_compass() -> void:
	print("HUD compass")
	var compass := player._hud.compass
	check(compass != null and compass.player == player, "the HUD has a compass tracking the player")
	player.rotation = Vector3.ZERO
	compass._process(0.0)
	check(is_equal_approx(compass._heading, 0.0), "facing spawn-forward reads as north")
	player.rotation.y = -PI / 2.0
	compass._process(0.0)
	check(is_equal_approx(compass._heading, 90.0), "turning right updates the heading (east)")
	check(compass.visible, "shown while up")
	player.vitals.server_damage(500.0)
	await _frames(2)
	compass._process(0.0)
	check(not compass.visible, "hidden while downed")
	player.vitals.server_reset_health()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
