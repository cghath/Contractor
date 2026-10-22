extends Node
## Timing script (not a suite; perf pass 2026-10-22): what one soldier's spawn costs the main
## thread, and where it goes. Headless:
##   <voxel godot exe> --headless --path . res://tests/perf_spawn.tscn
## Hosts harbour_yard with no AI, then spawns soldiers one a frame (hostile urban, hostile
## woodland, friendly multicam, by turns) and prints each spawn's time with what FrameCost
## counted in it (models: VoxelArt meshes built; armour: VoxelArmor meshes), then the averages
## for the first of each look and the rest. Never touches a real save.

const SPAWNS := 18

var level: ZoneLevel


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_perf_spawn" + tag
	Campaign.campaign_id = "test_perf_spawn_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("spawn: TIMED OUT")
		get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("harbour_yard"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player := level.players.get_node(^"1") as Soldier
	for i in 120:
		await get_tree().process_frame
	FrameCost.on = true
	var looks := [["hostile", "urban"], ["hostile", "woodland"], ["friendly", "multicam"]]
	var firsts: Array[float] = []
	var rest: Array[float] = []
	for i in SPAWNS:
		var look: Array = looks[i % looks.size()]
		await get_tree().process_frame
		FrameCost.take()
		var t := Time.get_ticks_usec()
		var d := {"name": "SpawnT%d" % i, "faction": look[0], "variant": look[1],
			"pos": level.ground_point(player.global_position + Vector3(-20.0 + i * 2.5, 0, 25)),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": true,
			"person_name": "Test %d" % i, "nation": "", "body": VoxelArt.MALE, "face": SoldierLook.make(i * 77, "", VoxelArt.MALE)}
		var t_make := Time.get_ticks_usec()
		var s := level._make_soldier(d) as Soldier
		FrameCost.spent(&"PT_make", t_make)
		var t_add := Time.get_ticks_usec()
		level.ai.add_child(s, true)
		FrameCost.spent(&"PT_add_child", t_add)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		var c := FrameCost.take()
		await get_tree().process_frame
		var c2 := FrameCost.take()
		var parts: Array[String] = []
		for k in c:
			parts.append("%s %.1f" % [k, int(c[k]) / 1000.0])
		var after: Array[String] = []
		for k in c2:
			after.append("%s %.1f" % [k, int(c2[k]) / 1000.0])
		print("spawn: %d %s/%s %.1f ms (in it: %s; next frame: %s)%s" % [i, look[0], look[1], ms, ", ".join(parts), ", ".join(after), "" if s else " NO SOLDIER"])
		if i < looks.size():
			firsts.append(ms)
		else:
			rest.append(ms)
	var avg := func(a: Array[float]) -> float: return a.reduce(func(x: float, y: float) -> float: return x + y, 0.0) / maxf(a.size(), 1)
	print("spawn: first of each look %.1f ms average, the rest %.1f ms average, worst %.1f" % [avg.call(firsts), avg.call(rest), rest.max()])
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)
