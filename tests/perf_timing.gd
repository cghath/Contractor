extends Node
## Timing script (not a suite): the main-thread costs behind mid-game hitches (research report
## 2026-10-13, Part B). Headless:
##   <voxel godot exe> --headless --path . res://tests/perf_timing.tscn
## Prints, as "timing:" lines:
## - sounds: the main-thread cost of the first play of each heavy sound, and of every
##   synthesised sound's first use, 3 s after boot (the first game starts later than that);
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
var _timing_nav := false
var _worst_ai := ""
## The whole game's worst frame in the fight (FrameCost, as the session log's
## perf line has it).
var _frame_usec := 0
var _worst_frame_ms := 0.0
var _worst_frame := ""


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var costs := FrameCost.take()
	if FrameCost.on and _frame_usec > 0 and (now - _frame_usec) / 1000.0 > _worst_frame_ms:
		_worst_frame_ms = (now - _frame_usec) / 1000.0
		_worst_frame = SessionLog.costs_text(costs, SessionLog.engine_counts())
	_frame_usec = now


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
	await get_tree().create_timer(3.0).timeout  # the main menu is up at least this long
	_time_sounds("3 s after boot")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("harbour_yard"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player := level.players.get_node(^"1") as Soldier
	# Stand just outside the biggest module (most boxes), so it streams in and the fight's
	# navigation reads its voxels.
	var module: ZoneModule = null
	for m in level.modules():
		if module == null or ZoneModules.boxes(m.type).size() > ZoneModules.boxes(module.type).size():
			module = m
	var edge := module.footprint()
	var at := level.ground_point(Vector3(edge.get_center().x, 0, edge.end.y + 4.0))
	player.global_position = at + Vector3(0, 0, -2)
	# The zone's navigation, run (and timed) from here from now on: the chunks around the
	# player bake as the module streams in.
	_nav = level.get_node_or_null(^"Navigation")
	if _nav:
		_nav.set_physics_process(false)
	_timing_nav = true
	for i in 1200:
		await get_tree().physics_frame
		if module.is_ready() and _nav and _nav.is_settled():
			break
	_report("ZoneNav per frame while %s streams in (%d chunks)" % [module.type, _nav.chunk_total() if _nav else 0], _nav_ms)
	_nav_ms.clear()
	if not module.is_ready():
		print("timing: module %s didn't stream in" % module.module_id)
	else:
		_time_nav_reads(module)
	# The fight: friendlies along the module's edge, hostiles 40 m out.
	for i in 8:
		level.spawn_soldier({"name": "TimingHostile%d" % i, "faction": "hostile", "variant": "urban",
			"pos": level.ground_point(at + Vector3(-12.0 + i * 3.0, 0, 45)),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true})
		level.spawn_soldier({"name": "TimingFriend%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(at + Vector3(-12.0 + i * 3.0, 0, 0)), "loadout": CompoundLevel.HOSTILE_LOADOUT,
			"combat": 0.5, "discipline": 0.6, "guard": true})
	await get_tree().physics_frame
	for s in level.ai.get_children():
		var ai := SquadAI.of(s)
		if ai:
			ai.set_physics_process(false)  # run (and timed) from here instead
			_ais.append(ai)
	FrameCost.on = true
	_timing = true
	for i in FRAMES:
		await get_tree().physics_frame
	_timing = false
	_timing_nav = false
	_report("AI per frame (%d SquadAI)" % _ais.size(), _ai_ms)
	var worst := _ai_ms.find(_ai_ms.max())
	print("timing: the AI's worst frame is fight frame %d (%s)" % [worst, _worst_ai])
	_report("ZoneNav per frame in the fight", _nav_ms)
	print("timing: the worst frame in the fight: %.1f ms (%s)" % [_worst_frame_ms, _worst_frame])
	_time_calls()
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	if _timing:
		var t0 := Time.get_ticks_usec()
		var top := 0
		var top_name := ""
		var before := FrameCost.take()
		for ai in _ais:
			if is_instance_valid(ai):
				var t := Time.get_ticks_usec()
				ai._physics_process(delta)
				if Time.get_ticks_usec() - t > top:
					top = Time.get_ticks_usec() - t
					top_name = "%s %.1f ms, %s" % [ai.get_parent().name, top / 1000.0, ai.body.ai_status if ai.body else ""]
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var mine := FrameCost.take()
		for k in before:  # back for the frame's own count
			FrameCost._costs[k] = before[k] + int(mine.get(k, 0))
		for k in mine:
			if not before.has(k):
				FrameCost._costs[k] = mine[k]
		if _ai_ms.is_empty() or ms > _ai_ms.max():
			_worst_ai = "slowest: %s; the AI's costs: %s" % [top_name, SessionLog.costs_text(mine, {})]
		_ai_ms.append(ms)
	if _timing_nav and is_instance_valid(_nav):
		var t1 := Time.get_ticks_usec()
		_nav._physics_process(delta)
		_nav_ms.append((Time.get_ticks_usec() - t1) / 1000.0)


func _time_sounds(when: String) -> void:
	Sfx.listener_override = Vector3.ZERO
	var total := 0.0
	var parts: Array[String] = []
	for id: StringName in HEAVY:
		var t := Time.get_ticks_usec()
		if id == &"engine_mbt":
			Sfx.streams(id)
		else:
			Sfx.play_at(id, Vector3.ZERO)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		total += ms
		parts.append("%s %.1f" % [id, ms])
	print("timing: sounds' first play %s: %.1f ms on the main thread (%s)" % [when, total, ", ".join(parts)])
	Sfx.listener_override = null
	var t_all := Time.get_ticks_usec()
	var n := 0
	for id: String in Sfx.defs:
		if not ((Sfx.defs[id] as Dictionary).get("synth", {}) as Dictionary).is_empty():
			Sfx.streams(StringName(id))
			n += 1
	print("timing: every synthesised sound's first use (%d sounds) %s: %.1f ms on the main thread" % [n, when, (Time.get_ticks_usec() - t_all) / 1000.0])


func _time_nav_reads(module: ZoneModule) -> void:
	var world := module.voxel_world
	var r := module.footprint()
	for read_all in [true, false]:
		world.read_all_voxels = read_all
		var total := 0.0
		var worst := 0.0
		var boxes := 0
		var chunks := 0
		var volume := 0.0
		var x := r.position.x
		while x < r.end.x:
			var z := r.position.y
			while z < r.end.y:
				var bounds := AABB(Vector3(x - 1.0, module.global_position.y - 2.0, z - 1.0), Vector3(14.0, 16.0, 14.0))
				var local := world.global_transform.affine_inverse() * bounds
				var t := Time.get_ticks_usec()
				var got := world.solid_boxes_m(local)
				var ms := (Time.get_ticks_usec() - t) / 1000.0
				boxes += got.size()
				for b in got:
					volume += b.get_volume()
				total += ms
				worst = maxf(worst, ms)
				chunks += 1
				z += 12.0
			x += 12.0
		print("timing: nav voxel reads (%s), module %s: %d chunks, %.1f ms in all, worst chunk %.1f ms, %d boxes, %.1f m3" % [
			"every voxel read" if read_all else "uncarved structures unread", module.type, chunks, total, worst, boxes, volume])
	world.read_all_voxels = false


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
