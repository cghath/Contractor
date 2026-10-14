extends Node
## Timing script (not a suite): the main-thread costs behind mid-game hitches (research report
## 2026-10-13, Part B). Headless:
##   <voxel godot exe> --headless --path . res://tests/perf_timing.tscn
## Prints, as "timing:" lines:
## - sounds: the main-thread cost of the first play of each heavy sound right at boot, and again
##   after 3 s (Sfx builds them on a worker at boot; it used to synthesise them at first play);
## - voxels for navigation: VoxelWorld.solid_boxes_m over every 12 m chunk of a streamed module;
## - a zone fight: 8 hostiles and 8 friendlies spawned in one frame in sight of each other, then
##   600 physics frames with every SquadAI and the zone's navigation run (and timed) from here:
##   each frame's AI total and navigation total, worst and average;
## - aim_point and foliage per call.
## Never touches a real save.

const HEAVY := [&"explosion", &"explosion_far", &"shot_rifle", &"shot_rifle_far", &"flashbang", &"reload", &"engine_mbt"]
const FRAMES := 600

var level: ZoneLevel
var _ais: Array[Node] = []
var _nav: Node
var _ai_ms: Array[float] = []
var _nav_ms: Array[float] = []
var _timing := false


func _ready() -> void:
	GameState.zone_id = "test_perf_timing"
	Campaign.campaign_id = "test_perf_timing_campaign"
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("timing: TIMED OUT")
		get_tree().quit(99))
	_time_sounds("at boot")
	await get_tree().create_timer(3.0).timeout
	_time_sounds("after 3 s")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("harbour_yard"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player := level.players.get_node(^"1") as Soldier
	var module: ZoneModule = null
	for i in 1200:
		await get_tree().process_frame
		for m in level.streamed_modules():
			if m.is_ready():
				module = m
		if module:
			break
	if module == null:
		print("timing: no module streamed in")
	else:
		_time_nav_reads(module)
	# The fight: on open ground beside the player.
	var at := player.global_position
	for i in 8:
		level.spawn_soldier({"name": "TimingHostile%d" % i, "faction": "hostile", "variant": "urban",
			"pos": level.ground_point(at + Vector3(-12.0 + i * 3.0, 0, 45)),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true})
		level.spawn_soldier({"name": "TimingFriend%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(at + Vector3(-12.0 + i * 3.0, 0, 5)), "loadout": CompoundLevel.HOSTILE_LOADOUT,
			"combat": 0.5, "discipline": 0.6, "guard": true})
	await get_tree().physics_frame
	for s in level.ai.get_children():
		var ai := SquadAI.of(s)
		if ai:
			ai.set_physics_process(false)  # run (and timed) from here instead
			_ais.append(ai)
	_nav = level.get_node_or_null(^"Navigation")
	if _nav:
		_nav.set_physics_process(false)
	_timing = true
	for i in FRAMES:
		await get_tree().physics_frame
	_timing = false
	_report("AI per frame (%d SquadAI)" % _ais.size(), _ai_ms)
	_report("ZoneNav per frame", _nav_ms)
	_time_calls()
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	if not _timing:
		return
	var t0 := Time.get_ticks_usec()
	for ai in _ais:
		if is_instance_valid(ai):
			ai._physics_process(delta)
	var t1 := Time.get_ticks_usec()
	if is_instance_valid(_nav):
		_nav._physics_process(delta)
	var t2 := Time.get_ticks_usec()
	_ai_ms.append((t1 - t0) / 1000.0)
	_nav_ms.append((t2 - t1) / 1000.0)


func _time_sounds(when: String) -> void:
	Sfx.listener_override = Vector3.ZERO
	var total := 0.0
	var parts: Array[String] = []
	for id: StringName in HEAVY:
		var t := Time.get_ticks_usec()
		if id == &"engine_mbt":
			Sfx.streams(id) if not Sfx.has_method(&"ready_streams") else Sfx.call(&"ready_streams", id)
		else:
			Sfx.play_at(id, Vector3.ZERO)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		total += ms
		parts.append("%s %.1f" % [id, ms])
	print("timing: sounds' first play %s: %.1f ms on the main thread (%s)" % [when, total, ", ".join(parts)])
	Sfx.listener_override = null


func _time_nav_reads(module: ZoneModule) -> void:
	var world := module.voxel_world
	var r := module.footprint()
	var total := 0.0
	var worst := 0.0
	var boxes := 0
	var chunks := 0
	var x := r.position.x
	while x < r.end.x:
		var z := r.position.y
		while z < r.end.y:
			var bounds := AABB(Vector3(x - 1.0, -2.0, z - 1.0), Vector3(14.0, 14.0, 14.0))
			var local := world.global_transform.affine_inverse() * bounds
			var t := Time.get_ticks_usec()
			boxes += world.solid_boxes_m(local).size()
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			chunks += 1
			z += 12.0
		x += 12.0
	print("timing: nav voxel reads, module %s: %d chunks, %.1f ms in all, worst chunk %.1f ms, %d boxes" % [module.type, chunks, total, worst, boxes])


func _time_calls() -> void:
	var soldiers: Array[Soldier] = []
	for s in level.ai.get_children():
		if s is Soldier:
			soldiers.append(s)
	if soldiers.size() < 2:
		return
	var t := Time.get_ticks_usec()
	for i in 10000:
		soldiers[i % soldiers.size()].aim_point()
	print("timing: aim_point %.2f us a call" % [(Time.get_ticks_usec() - t) / 10000.0])
	var scatter := level.scatter
	t = Time.get_ticks_usec()
	var n := 0
	for a in soldiers:
		for b in soldiers:
			if a != b:
				Spotting.foliage_m(scatter, a, b)
				n += 1
	print("timing: foliage_m %.1f us a pair (%d pairs)" % [(Time.get_ticks_usec() - t) / float(n), n])


func _report(what: String, ms: Array[float]) -> void:
	if ms.is_empty():
		return
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	var over := 0
	for v in ms:
		sum += v
		if v > 4.0:
			over += 1
	print("timing: %s: worst %.2f ms, 99th %.2f ms, 95th %.2f ms, average %.3f ms, %d of %d frames over 4 ms" % [
		what, sorted[-1], sorted[int(sorted.size() * 0.99)], sorted[int(sorted.size() * 0.95)], sum / ms.size(), over, ms.size()])
