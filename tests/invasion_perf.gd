extends Node
## Timing script (not a suite): the "invasion" case of docs/combined_arms.md 6.2.3 (phase D2). Headless:
##   <voxel godot exe> --headless --path . res://tests/invasion_perf.tscn [-- --zone hot]
## Hosts an 8 km operation zone (ZoneDef.generate_operation; with "--zone hot", today's 4 km hot
## zone ridge_hot instead, the case to hold against), the player at its insertion point, and loads it:
## - two armour columns moving: COLUMN vehicles each (an Abrams pair and a Bradley pair, then four
##   Bradleys), each with an AI driver, driving the MSR and the truss route (a hot zone: its roads);
## - LIVE_AI live soldiers: half friendly round the player, half hostile in teams 250-450 m ahead
##   (they fight);
## - VIRTUAL_AI hostiles in teams of TEAM at least FAR_M from the player, tracked by the
##   Virtualizer, which takes them virtual.
## After SETTLE_S, times FRAMES frames and prints "invasion:" lines: frame average, 99th percentile
## and worst (wall clock: the host's simulation, no rendering), process and physics time, how many
## soldiers and vehicles are live and virtual, the ground streaming's worst tick, collision chunks
## and cover cells, and each against the 6.2.3 host budget (14 ms average, 33 ms 99th). Never touches
## a real save.

const COLUMN := 4
const LIVE_AI := 60
const VIRTUAL_AI := 200
const TEAM := 4
const FAR_M := 1500.0
const SETTLE_S := 8.0
const FRAMES := 900
const BUDGET_AVG_MS := 14.0
const BUDGET_P99_MS := 33.0

var level: ZoneLevel
var player: Soldier
var _made := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameState.zone_id = "test_invasion_perf"
	Campaign.campaign_id = "test_invasion_perf_campaign"
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("invasion: TIMED OUT")
		get_tree().quit(99))
	var hot := "--zone" in OS.get_cmdline_user_args() and "hot" in OS.get_cmdline_user_args()
	var def := MissionRegistry.zone_def("ridge_hot") if hot else ZoneDef.generate_operation(11, "phased_invasion", ["ashfield", "red_mesa", "salt_pan"])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var t := Time.get_ticks_msec()
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	print("invasion: zone %s, %.0f m across, %d modules, hosted in %d ms (generated in %.0f)" % [def.get("id", ""), level.terrain.size_m,
		level.modules().size(), Time.get_ticks_msec() - t, level.generate_ms])
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	_rng.seed = 2026
	await _columns(def)
	_live()
	_virtual()
	await _seconds(SETTLE_S)
	await _measure()
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Two columns of COLUMN vehicles, each with an AI driver, driving a road: the MSR and the truss
## route in an operation zone, the two longest roads in a hot zone.
func _columns(def: Dictionary) -> void:
	var routes: Array = []
	if OperationGen.is_operation(def):
		routes = [def.op.msr, def.op.route]
	else:
		var roads: Array = (def.get("roads", []) as Array).duplicate()
		roads.sort_custom(func(a: Array, b: Array) -> bool:
			return Vector2(a[0][0], a[0][1]).distance_to(Vector2(a[1][0], a[1][1])) > Vector2(b[0][0], b[0][1]).distance_to(Vector2(b[1][0], b[1][1])))
		routes = roads.slice(0, 2)
	var layer := VehicleLayer.of(level)
	var models := [["abrams", "abrams", "bradley", "bradley"], ["bradley", "bradley", "bradley", "bradley"]]
	for c in routes.size():
		var pts := PackedVector3Array()
		for p: Array in routes[c]:
			pts.append(level.ground_point(Vector3(float(p[0]), 0.0, float(p[1]))))
		var dir := (pts[1] - pts[0]).normalized()
		for k in COLUMN:
			var at := level.ground_point(pts[0] - dir * (14.0 + k * 30.0)) + Vector3(0, 1.0, 0)
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), at)
			var v := layer.server_spawn(String(models[c][k]), xf, "", &"friendly")
			if v == null:
				continue
			await get_tree().physics_frame
			var driver := level.spawn_soldier({"name": "ColumnDriver%d_%d" % [c, k], "faction": "friendly", "variant": "multicam",
				"pos": at + Vector3(3, 0, 0), "loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "guard": false})
			await get_tree().physics_frame
			if driver:
				v.server_enter(driver, 0)
			v.server_follow_path(pts.slice(1), 30.0)


## LIVE_AI soldiers: half friendly round the player, half hostile in teams 250-450 m ahead.
func _live() -> void:
	var at := player.global_position
	var ahead := Vector3.FORWARD
	for i in LIVE_AI / 2:
		level.spawn_soldier({"name": "InvFriend%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(at + Vector3(-20.0 + (i % 10) * 4.0, 0, 6.0 + (i / 10) * 4.0)), "loadout": CompoundLevel.HOSTILE_LOADOUT,
			"combat": 0.5, "discipline": 0.6, "guard": true})
	var er := EnemyResponse.of(level)
	var map := level.map_area()
	ahead = Vector3(-map.get_center().x + at.x, 0, -map.get_center().y + at.z).normalized() * -1.0  # toward the middle
	for t in (LIVE_AI / 2) / TEAM:
		var pos := at + ahead.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * _rng.randf_range(250.0, 450.0)
		_team(er, level.ground_point(pos), false)


## VIRTUAL_AI hostiles in teams at least FAR_M from the player, tracked (they go virtual).
func _virtual() -> void:
	var er := EnemyResponse.of(level)
	var area := level.map_area().grow(-200.0)
	var at := player.global_position
	for t in VIRTUAL_AI / TEAM:
		var pos := Vector3.ZERO
		for k in 200:
			pos = Vector3(_rng.randf_range(area.position.x, area.end.x), 0, _rng.randf_range(area.position.y, area.end.y))
			if Vector2(pos.x - at.x, pos.z - at.z).length() >= FAR_M:
				break
		_team(er, level.ground_point(pos), true)


func _team(er: EnemyResponse, pos: Vector3, virtualize: bool) -> void:
	_made += 1
	var callsign := "IV%d" % _made
	var squad := er._new_squad(callsign)
	var a := _rng.randf() * TAU
	var route: Array[Vector3] = [pos, level.ground_point(pos + Vector3(cos(a), 0, sin(a)) * 150.0)]
	squad.patrol = route
	var soldiers := er._spawn_team(squad, callsign, TEAM, pos, route[1], CompoundLevel.HOSTILE_LOADOUT, 0.45, 0.5, "safe")
	if virtualize:
		Virtualizer.of(level).track({"squad": squad, "soldiers": soldiers}, "patrol")


func _measure() -> void:
	var frame_ms: Array[float] = []
	var proc := 0.0
	var phys := 0.0
	var stream := level.get_node_or_null(^"BigZoneStreaming") as BigZoneStreaming
	var worst_stream := 0.0
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if stream:
			worst_stream = maxf(worst_stream, stream.last_ms)
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for f in frame_ms:
		sum += f
	var avg := sum / frame_ms.size()
	var p99: float = sorted[int(sorted.size() * 0.99)]
	var live := 0
	for n in level.ai.get_children():
		if n is Soldier and not n.is_queued_for_deletion() and not (n as Soldier).vitals.is_dead():
			live += 1
	var vehicles := get_tree().get_nodes_in_group(Vehicle.GROUP).filter(func(v: Node) -> bool: return level.is_ancestor_of(v)).size()
	var moved := 0
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v is Vehicle and (v as Vehicle).linear_velocity.length() > 1.0:
			moved += 1
	print("invasion: frame avg %.2f ms, 99th %.1f ms, worst %.1f ms | process %.2f ms, physics %.2f ms" % [avg, p99, sorted.back(), proc / FRAMES, phys / FRAMES])
	print("invasion: live AI %d, virtual %d, vehicles %d (%d moving)" % [live, Virtualizer.of(level).virtual_count(), vehicles, moved])
	if stream:
		print("invasion: ground streaming worst tick %.1f ms, %d collision chunks of %d, %d cover cells" % [worst_stream,
			level.terrain.collision_chunks(), level.terrain.chunk_count() * level.terrain.chunk_count(), level.scatter.cover_cells()])
	print("invasion: budget (6.2.3 host): average %.2f / %.0f ms %s, 99th %.1f / %.0f ms %s" % [avg, BUDGET_AVG_MS, "OK" if avg <= BUDGET_AVG_MS else "OVER",
		p99, BUDGET_P99_MS, "OK" if p99 <= BUDGET_P99_MS else "OVER"])
