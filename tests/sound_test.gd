extends Node
## Headless checks for sound (Sfx, autoload/sfx.gd, data/sounds.json): every sound has a
## generated placeholder; near and far variants by distance; out of range is silent (a
## suppressed shot past what the AI hears); a round passing close cracks, your own doesn't;
## in a hosted level a shot, its impact, a reload and footsteps are heard.
##   <voxel godot exe> --headless --path . res://tests/sound_test.tscn
## Exits with the number of failures.

var failures := 0


func _ready() -> void:
	GameState.zone_id = "test_sound" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("SOUND TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_streams()
	_test_distance()
	_test_crack()
	await _test_in_level()
	Sfx.listener_override = null
	GameState.delete_save()
	print("SOUND TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_streams() -> void:
	print("Streams")
	check(Sfx.defs.size() >= 15, "sounds defined (%d)" % Sfx.defs.size())
	var bad := []
	for id: String in Sfx.defs:
		var options := Sfx.streams(StringName(id))
		if options.size() != Sfx.SYNTH_VARIANTS or (options[0] as AudioStreamWAV).data.size() < 400:
			bad.append(id)
	check(bad.is_empty(), "each has %d generated variants (bad: %s)" % [Sfx.SYNTH_VARIANTS, bad])
	var a := (Sfx.streams(&"shot_rifle")[0] as AudioStreamWAV).data
	var b := (Sfx.streams(&"shot_rifle")[1] as AudioStreamWAV).data
	check(a != b, "variants differ, so repeats don't sound identical")
	check(Sfx.synth(Sfx.defs["step"].synth, 42).data == Sfx.synth(Sfx.defs["step"].synth, 42).data, "the same seed makes the same sound")
	check(AudioServer.get_bus_index(&"SFX") >= 0 and AudioServer.get_bus_index(&"Voice") >= 0 and AudioServer.get_bus_index(&"SFX_Room") >= 0,
		"SFX, Voice and room (reverb) buses exist")
	var engine := Sfx.streams(&"engine_mbt")[0] as AudioStreamWAV
	check(engine.loop_mode == AudioStreamWAV.LOOP_FORWARD and engine.loop_end == SfxSynth.MIX_RATE, "an engine loops seamlessly (exactly 1 s)")
	var tank := Vehicle.new()
	tank.spec = {"class": "mbt"}
	tank.kind = Vehicle.TRACKED
	var truck := Vehicle.new()
	truck.spec = {"class": "unknown"}
	truck.kind = Vehicle.WHEELED
	var heli := Vehicle.new()
	heli.spec = {"class": "aircraft"}
	check(Sfx.engine_id(tank) == &"engine_mbt" and Sfx.engine_id(truck) == &"engine_mrap" and Sfx.engine_id(heli) == &"engine_aircraft",
		"each vehicle class has its own engine (tank turbine, MRAP diesel, rotor)")
	for v: Vehicle in [tank, truck, heli]:
		v.free()


func _test_distance() -> void:
	print("Distance")
	Sfx.listener_override = Vector3.ZERO
	check(Sfx.play_at(&"shot_rifle", Vector3(0, 0, 20)) == &"shot_rifle", "a rifle shot 20 m away: near")
	check(Sfx.play_at(&"shot_rifle", Vector3(0, 0, 120)) == &"shot_rifle_far", "120 m away: the far variant")
	check(Sfx.play_at(&"shot_rifle", Vector3(0, 0, 300)) == &"", "300 m away: past what the AI hears, silent")
	check(Sfx.play_at(&"shot_suppressed", Vector3(0, 0, 30)) == &"shot_suppressed", "a suppressed shot 30 m away: heard")
	check(Sfx.play_at(&"shot_suppressed", Vector3(0, 0, 60)) == &"", "60 m away: not")
	check(Sfx.play_at(&"no_such_sound", Vector3.ZERO) == &"", "an unknown id plays nothing")


func _test_crack() -> void:
	print("Cracks")
	Sfx.listener_override = Vector3.ZERO
	var t := _now()
	Sfx.hear_shot(Vector3(1, 1, 120), Vector3(1, 1, -120), "rifle")
	check(&"crack" in Sfx.heard_since(t) and &"shot_rifle_far" in Sfx.heard_since(t), "a round passing 1.4 m from a distant shooter cracks")
	t = _now()
	Sfx.hear_shot(Vector3(30, 1, 120), Vector3(30, 1, -120), "rifle")
	check(not &"crack" in Sfx.heard_since(t), "one passing 30 m off doesn't")
	t = _now()
	Sfx.hear_shot(Vector3(0, 1.5, 0.2), Vector3(0, 1.5, -200), "rifle")
	check(not &"crack" in Sfx.heard_since(t), "your own round doesn't crack at you")


func _test_in_level() -> void:
	print("In a level")
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	var level := CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 20)
	player.rotation = Vector3.ZERO
	await _frames(5)
	Sfx.listener_override = Vector3(0, 1.6, 20)
	player.inventory.strip()
	player.inventory.take(&"m4a1")
	player.inventory.take(&"mag_556", 2)
	await _frames(3)
	var t := _now()
	player._server_fire.rpc_id(1, player.camera.global_position, Vector3(0, -0.4, -1).normalized(), &"primary")
	await _frames(3)
	var heard := Sfx.heard_since(t)
	check(&"shot_rifle" in heard, "firing: the shot is heard (%s)" % [heard])
	check(heard.any(func(id: StringName) -> bool: return String(id).begins_with("impact_")), "and where it lands")
	t = _now()
	player._server_reload.rpc_id(1, &"primary")
	await _frames(3)
	check(&"reload" in Sfx.heard_since(t), "a reload is heard")
	check(not Sfx.under_roof(Vector3(0, 0.1, 30)), "in the open: no reverb")
	var walker := level.spawn_soldier({"name": "Walker", "faction": "friendly", "variant": "multicam", "pos": Vector3(4, 0.1, 20),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(walker).process_mode = Node.PROCESS_MODE_DISABLED
	walker.set_physics_process(false)
	await _frames(3)
	t = _now()
	for i in 40:
		walker.global_position += Vector3(0, 0, -0.1)  # 4 m at walking pace
		await get_tree().process_frame
	var steps := Sfx.heard_since(t).filter(func(id: StringName) -> bool: return id == &"step").size()
	check(steps >= 3 and steps <= 7, "a soldier walking 4 m: footsteps (%d)" % steps)
	t = _now()
	walker.global_position += Vector3(0, 0, -30)
	await _frames(3)
	check(not &"step" in Sfx.heard_since(t), "a teleport isn't a step")
	walker.queue_free()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
