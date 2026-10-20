extends Node
## Timing script (not a suite): what AI virtualization (Virtualizer, docs/virtualization.md) saves on
## a big zone. Headless:
##   <voxel godot exe> --headless --path . res://tests/virtualization_perf.tscn
## Hosts the 4 km hot zone (ZONE), the player at its insertion point, and puts hostiles in teams of
## TEAM all over it, each walking a route of its own (as the zone's patrols do), a NEAR_SHARE of
## them within NEAR_M of the player. Then, after SETTLE_S, times FRAMES frames of each case:
##   today      BASE_MEN hostiles, virtualization off (DynamicSim sleeps the far ones, as now);
##   3x plain   3 x BASE_MEN, virtualization off (what the bigger force would cost without it);
##   3x virtual 3 x BASE_MEN, virtualization on.
## Prints, as "perf:" lines, each case's average and worst frame (wall clock), its process and
## physics time (Performance), and how many soldiers were in the world, asleep and virtual.
## Never touches a real save.

const ZONE := "ridge_hot"
const BASE_MEN := 40
const TEAM := 4
const NEAR_M := 450.0
const NEAR_SHARE := 0.15
const SETTLE_S := 6.0
const FRAMES := 600

var level: ZoneLevel
var player: Soldier
var v: Virtualizer
var er: EnemyResponse
var _made := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameState.zone_id = "test_virtualization_perf"
	Campaign.campaign_id = "test_virtualization_perf_campaign"
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("perf: TIMED OUT")
		get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	v = Virtualizer.of(level)
	er = EnemyResponse.of(level)
	await _seconds(3.0)
	print("perf: zone %s, %.0f m across, %d modules" % [ZONE, level.terrain.size_m, level.modules().size()])
	var results := []
	results.append(await _case("today (%d, no virtualization)" % BASE_MEN, BASE_MEN, false))
	results.append(await _case("3x plain (%d, no virtualization)" % (BASE_MEN * 3), BASE_MEN * 3, false))
	results.append(await _case("3x virtual (%d, virtualization on)" % (BASE_MEN * 3), BASE_MEN * 3, true))
	for r: Dictionary in results:
		print("perf: %-36s frame avg %.2f ms, worst %.1f ms | process %.2f ms, physics %.2f ms | in the world %d (asleep %d), virtual %d"
			% [r.name, r.avg, r.worst, r.process, r.physics, r.live, r.asleep, r.virtual])
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## One case: `men` hostiles spread over the zone (the same spots every case: a fixed seed), with or
## without virtualization; FRAMES frames timed after SETTLE_S.
func _case(name: String, men: int, virtualize: bool) -> Dictionary:
	_clear()
	await _seconds(1.0)
	Virtualizer.enabled = virtualize
	_rng.seed = 2026
	var area := level.map_area().grow(-150.0)
	var at := player.global_position
	for t in men / TEAM:
		var pos: Vector3
		if _rng.randf() < NEAR_SHARE:
			var a := _rng.randf() * TAU
			pos = at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(150.0, NEAR_M)
		else:
			pos = Vector3(_rng.randf_range(area.position.x, area.end.x), 0, _rng.randf_range(area.position.y, area.end.y))
		pos.x = clampf(pos.x, area.position.x, area.end.x)
		pos.z = clampf(pos.z, area.position.y, area.end.y)
		_team(level.ground_point(pos), virtualize)
	await _seconds(SETTLE_S)
	var frame_ms: Array[float] = []
	var proc := 0.0
	var phys := 0.0
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var live := 0
	var asleep := 0
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion():
			live += 1
			if s.process_mode == Node.PROCESS_MODE_DISABLED:
				asleep += 1
	var sum := 0.0
	for f in frame_ms:
		sum += f
	return {"name": name, "avg": sum / frame_ms.size(), "worst": frame_ms.max(), "process": proc / FRAMES, "physics": phys / FRAMES,
		"live": live, "asleep": asleep, "virtual": v.virtual_count()}


## A team of TEAM walking a 2-point route 150 m long from `pos`, tracked if `virtualize`.
func _team(pos: Vector3, virtualize: bool) -> void:
	_made += 1
	var callsign := "PF%d" % _made
	var squad := er._new_squad(callsign)
	var a := _rng.randf() * TAU
	var route: Array[Vector3] = [pos, level.ground_point(pos + Vector3(cos(a), 0, sin(a)) * 150.0)]
	squad.patrol = route
	var soldiers := er._spawn_team(squad, callsign, TEAM, pos, route[1], CompoundLevel.HOSTILE_LOADOUT, 0.45, 0.5, "safe")
	if virtualize:
		v.track({"squad": squad, "soldiers": soldiers}, "patrol")


func _clear() -> void:
	for r: Dictionary in v.groups:
		r.erase("virtual")
	v.groups.clear()
	v._queue.clear()
	for n in level.ai.get_children():
		n.queue_free()
	for n in er.get_children():
		if n is Squad:
			n.queue_free()
