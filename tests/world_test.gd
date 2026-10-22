extends Node
## World scale: a 2 km zone (ZoneLevel) on a seeded terrain with streamed voxel modules.
## Two processes over real ENet, like the net suite:
##   <exe> --headless --path . res://tests/world_test.tscn -- --world-host
##   <exe> --headless --path . res://tests/world_test.tscn -- --world-join 127.0.0.1
## The host runs the single-process checks first (generation, streaming over 1 km, edits that
## save and reload, AI pathing from the terrain into a module, shooting into modules, frame
## time and memory budgets) with new connections refused, then lets the client in. The client
## (joining late) checks it generated the same zone and gets the module edits, saved and live.
## Each process prints WORLD TEST PASSED/FAILED and exits with its failure count; the host
## exits when the client leaves.

## Budgets (headless, this machine; see the report for the numbers measured):
## generating the zone (terrain heights, collision, modules' proxies), the worst frame and the
## average frame while a player crosses 1 km with modules streaming in and out, and the
## static memory the zone takes with its modules streaming.
const BUDGET_GENERATE_MS := 1500.0
const BUDGET_WORST_FRAME_MS := 150.0
const BUDGET_AVERAGE_FRAME_MS := 25.0
const BUDGET_MEMORY_MB := 250.0
## The shed's plank wall in the compound module, and the live mark the host makes once the
## client is in (module space, metres).
const SHED_SHOT_FROM := Vector3(17.05, 1.35, -3)
const SHED_SHOT_TO := Vector3(17.05, 1.35, -13)
const SHED_WALL := Vector3(17.05, 1.35, -7.05)
## A breach blown in the shed's south wall, and a spot of that wall left standing.
const SHED_BREACH := Vector3(17.9, 1.2, -10.95)
const SHED_INTACT := Vector3(16.6, 1.2, -10.95)
const LIVE_MARK := Vector3(8.0, 1.2, 29.4)  # the zone compound's south wall, inside (ZoneModules._compound: 60 x 60 m, 0.6 m mud brick)
## Dig phase 2: a crater on open ground this far from the first insertion point (host), and a
## berm next to it; the late joiner checks it gets both.
const CRATER_FROM_INSERTION := Vector3(18, 0, 14)
## Ground guard: the fall spot is clear of everything solid (rocks, trunks) this far round (m):
## the capsule's radius (SoldierMovement.CAPSULE_RADIUS) and then some.
const CLEAR_ROUND_M := 1.0

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier
var _host_digest := {}
var _client_left := false


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_world" + tag  # never touch a real save
	Campaign.campaign_id = "test_world" + tag
	CompoundLevel.spawn_ai = false
	var args := OS.get_cmdline_user_args()
	if "--world-join" in args:
		await _run_client(args[args.find("--world-join") + 1] if args.find("--world-join") + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		await _run_host("--world-host" in args)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _mem_mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0


# --- Host -------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	var mem_before := _mem_mb()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(ZoneDef.get_def("test"))
	check(multiplayer.multiplayer_peer is ENetMultiplayerPeer, "hosting on port %d" % Net.port())
	if not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "hosting the test zone puts a ZoneLevel in place of the compound")
	if level == null:
		_finish()
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	_test_generation(mem_before)
	await _test_streaming()
	await _test_edits()
	await _test_shot_in_module()
	await _test_loot_and_care()
	await _test_frag_and_body()
	await _test_ai_path()
	await _test_ground_guard()
	await _test_craters()
	await _test_reload()
	_test_budget(mem_before)
	if not wait_for_client:
		_finish()
		return
	print("[host] waiting for the client")
	Net.peer_joined.connect(_on_client_joined)
	Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	await _wait_for(func() -> bool: return _client_left, 420.0)
	_finish()


func _test_generation(mem_before: float) -> void:
	print("Generating the zone")
	var t := level.terrain
	var area := level.map_area()
	check(is_equal_approx(area.size.x, 1920.0) and is_equal_approx(area.position.x, -960.0),
		"the test zone is 1920 m square (%.1f km2), and map_area() covers all of it (%s)" % [area.get_area() / 1e6, area])
	check(area.get_area() >= 2e6 and area.get_area() <= 4e6, "a contract zone's size: 2 to 4 km2")
	check(level.generate_ms < BUDGET_GENERATE_MS, "generated in %.0f ms (budget %.0f)" % [level.generate_ms, BUDGET_GENERATE_MS])
	check(t.max_slope_deg() < 30.0 and t.max_height - t.min_height > 8.0,
		"rolling hills: %.1f to %.1f m, steepest %.0f degrees" % [t.min_height, t.max_height, t.max_slope_deg()])
	check(level.modules().size() == 5 and ZoneModules.base(level.get_module("compound").type) == "compound" and ZoneModules.base(level.get_module("village_e").type) == "village",
		"five modules from the definition (%s)" % [level.modules().map(func(m: ZoneModule) -> String: return m.module_id)])
	var flat := true
	for m in level.modules():
		var r := m.footprint()
		for corner in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
			flat = flat and absf(t.height_at(corner.x, corner.y) - m.global_position.y) < 0.01
	check(flat, "every module sits on a flat pad at its origin's height")
	var again := ZoneTerrain.new()
	again.generate(level.def, level._flat_areas())
	var other := ZoneTerrain.new()
	other.generate(level.def.merged({"seed": 99}, true), level._flat_areas())
	check(again.checksum() == t.checksum() and other.checksum() != t.checksum(), "the same seed gives the same ground, another seed different ground")
	again.free()
	other.free()
	var gen := ZoneDef.generate(1234)
	check(ZoneDef.generate(1234).hash() == gen.hash() and gen.modules.size() == 5 and gen.insertion.size() == 2 and gen.extraction.size() == 3,
		"a zone generated from a seed is the same every time (%d modules, %d insertion points, %d extraction candidates)" % [gen.modules.size(), gen.insertion.size(), gen.extraction.size()])
	_test_hot_layout()
	_test_building_gen()
	_test_towns()
	_test_presets()
	_test_ship_placement()
	var ins := level.insertion_points()[0]
	check(player.global_position.distance_to(ins) < 5.0 and absf(player.global_position.y - t.height_at(player.global_position.x, player.global_position.z) - 0.1) < 0.05,
		"the player starts at the insertion point, on the ground (%s)" % player.global_position)
	var space := player.get_world_3d().direct_space_state
	var worst := 0.0
	for k in 50:
		var x := -900.0 + k * 36.7
		var z := 800.0 - k * 31.3
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z), 1))
		worst = maxf(worst, absf(hit.get("position", Vector3.INF).y - t.height_at(x, z)) if not hit.is_empty() else INF)
	check(worst < 0.01, "the ground's collision matches its heights (worst %.4f m)" % worst)
	check(not level.get_module("compound").is_streamed(), "modules far from the player start streamed out, as proxies")
	var proxy_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8, 1.3, 40) + _origin("compound"), Vector3(8, 1.3, -40) + _origin("compound"), 1))
	check(not proxy_hit.is_empty() and absf(proxy_hit.position.z - _origin("compound").z - 30.0) < 0.2,
		"a streamed-out module's proxy still stops sight lines and rounds at its walls")


func _origin(id: String) -> Vector3:
	return level.get_module(id).global_position


## The player crosses the zone past four modules, 1.1 km; modules stream in near them and out
## behind them. Frame times and memory are measured on the way.
func _test_streaming() -> void:
	print("Streaming modules over 1 km")
	var route: Array[Vector3] = [level.insertion_points()[0], _origin("outpost_s") + Vector3(0, 0, 40), _origin("checkpoint_w") + Vector3(40, 0, 0),
		_origin("compound") + Vector3(0, 0, 30), _origin("outpost_n") + Vector3(0, 0, 30)]
	var travelled := 0.0
	var worst := 0.0
	var frames := 0
	var total_ms := 0.0
	var max_streamed := 0
	var all_ok := true
	var seen_in := {}
	var seen_out := {}
	var prev := Time.get_ticks_usec()
	for leg in route.size() - 1:
		var a: Vector3 = route[leg]
		var b: Vector3 = route[leg + 1]
		var steps := ceili(a.distance_to(b) / 4.0)  # 4 m a frame: 240 m/s, far harder than a vehicle
		for i in range(1, steps + 1):
			var p := a.lerp(b, float(i) / steps)
			player.global_position = level.ground_point(p)
			var checked_at: float = level._next_stream
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - prev) / 1000.0
			prev = now
			worst = maxf(worst, ms)
			total_ms += ms
			frames += 1
			max_streamed = maxi(max_streamed, level.streamed_modules().size())
			var checked: bool = level._next_stream != checked_at  # streaming was updated this frame
			for m in level.modules():
				if m.is_streamed():
					seen_in[m.module_id] = true
					if checked and m.distance_to(player.global_position) > ZoneLevel.STREAM_OUT_M:
						all_ok = false
				elif seen_in.has(m.module_id):
					seen_out[m.module_id] = true
		travelled += a.distance_to(b)
		# At each stop the nearest module is in, built, its proxy gone.
		var near := _nearest_module(b)
		var ready := await _wait_for(func() -> bool: return near.is_ready(), 5.0)
		prev = Time.get_ticks_usec()
		check(ready, "next to %s: streamed in and built (%d modules streamed in)" % [near.module_id, level.streamed_modules().size()])
	check(travelled >= 1000.0, "the route is %.0f m" % travelled)
	check(all_ok, "no module stays streamed in past %.0f m from the player" % ZoneLevel.STREAM_OUT_M)
	check(seen_in.size() >= 4 and seen_out.size() >= 2, "modules streamed in (%s) and out behind (%s)" % [seen_in.keys(), seen_out.keys()])
	check(max_streamed <= 3, "at most %d modules in memory at once" % max_streamed)
	_frame_stats = [worst, total_ms / maxi(frames, 1), frames]
	print("  frames while streaming: worst %.1f ms, average %.1f ms over %d frames" % _frame_stats)


var _frame_stats := [0.0, 0.0, 0]


func _nearest_module(p: Vector3) -> ZoneModule:
	var best: ZoneModule = null
	for m in level.modules():
		if best == null or m.distance_to(p) < best.distance_to(p):
			best = m
	return best


func _go_to_module(id: String, offset := Vector3(0, 0, 30)) -> ZoneModule:
	var m := level.get_module(id)
	player.global_position = level.ground_point(m.global_position + offset)
	await _wait_for(func() -> bool: return m.is_ready(), 8.0)
	await _wait_for_collision(m)
	return m


## The voxels' collision comes block by block a few frames after they're built.
func _wait_for_collision(m: ZoneModule) -> void:
	var space := player.get_world_3d().direct_space_state
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.to_global(Vector3(0, 1.3, 40)), m.to_global(Vector3(0, 1.3, -40)), 1))
		if not hit.is_empty() and VoxelWorld.find_on(hit.collider) == m.voxel_world:
			break
		await get_tree().physics_frame
	for i in 3:
		await get_tree().physics_frame


func _fire(from: Vector3, to: Vector3, weapon: StringName) -> Dictionary:
	var shooter := StaticBody3D.new()
	shooter.collision_layer = 0
	level.add_child(shooter)
	shooter.global_position = from
	var result := Ballistics.fire(shooter, from, (to - from).normalized(), ItemDB.get_item(weapon))
	shooter.queue_free()
	return result


## A round through the compound module's shed: a bullet hole in that module's log, applied, saved.
func _test_edits() -> void:
	print("Voxel edits in a module")
	var m := await _go_to_module("compound")
	var world := m.voxel_world
	check(world != null and world.module_id == "compound" and world.material_at(m.to_global(SHED_WALL)) == VoxelWorld.Mat.WOOD,
		"the compound module's voxels are loaded, its shed wall is wood")
	var edits := GameState.voxel_edits.size()
	var result := _fire(m.to_global(SHED_SHOT_FROM), m.to_global(SHED_SHOT_TO), &"m4a1")
	var mine: Array = GameState.voxel_edits.slice(edits)
	check(result.result != "none" and mine.filter(func(e: Dictionary) -> bool: return e.op == "shot").size() == 2 and mine.all(func(e: Dictionary) -> bool: return e.get("w") == "compound"),
		"a round through the shed's planks: shots in the zone's log, tagged with the module (%s)" % [mine.map(func(e: Dictionary) -> String: return "%s@%s" % [e.op, e.get("w")])])
	check(level.edit_logs().get("compound", []).size() == mine.size() and world.holes_through(m.to_global(SHED_WALL)) == 1 and world.bullet_hole_count() >= 4,
		"applied in the module: one round through the plank, %d hole decals" % world.bullet_hole_count())
	world.server_mark(m.to_global(Vector3(-2.95, 1.35, -4.0)), Vector3.BACK, VoxelWorld.Mat.PAINTED)
	check(world.marks_near(m.to_global(Vector3(-2.95, 1.35, -4.0)), 0.05) == 1, "an impact mark on the main building")
	# Audit A3-05: a breach in the shed's south wall stays open in the proxy while it's away.
	world.server_carve(m.to_global(SHED_BREACH), 0.6)
	await get_tree().create_timer(1.0).timeout
	var space := m.get_world_3d()
	var through_breach := [m.to_global(SHED_BREACH + Vector3(0, 0, 1)), m.to_global(SHED_BREACH - Vector3(0, 0, 1))]
	var through_wall := [m.to_global(SHED_INTACT + Vector3(0, 0, 1)), m.to_global(SHED_INTACT - Vector3(0, 0, 1))]
	check(world.material_at(m.to_global(SHED_BREACH)) == VoxelWorld.Mat.EMPTY and Throwables.clear_line(space, through_breach[0], through_breach[1])
		and not Throwables.clear_line(space, through_wall[0], through_wall[1]), "a breach blown in the shed's south wall: clear through it, the rest of the wall stands")
	# Navigation's voxel boxes: structures nothing carved go in as built, unread; the same solid
	# volume as reading every voxel, the breach included.
	var area := AABB(Vector3(-60, -2, -60), Vector3(120, 16, 120))
	var quick := world.solid_boxes_m(area)
	world.read_all_voxels = true
	var full := world.solid_boxes_m(area)
	world.read_all_voxels = false
	var volume := func(boxes: Array[AABB]) -> float: return boxes.reduce(func(sum: float, b: AABB) -> float: return sum + b.get_volume(), 0.0)
	var breach_in := func(boxes: Array[AABB]) -> bool: return boxes.any(func(b: AABB) -> bool: return b.grow(-0.01).has_point(SHED_BREACH))
	check(absf(volume.call(quick) - volume.call(full)) < 0.01 and quick.size() < full.size() and not breach_in.call(quick) and not breach_in.call(full),
		"navigation's voxel boxes: untouched structures unread (%d boxes, read all: %d), the same %.2f m3 (read all: %.2f), the breach open" % [
		quick.size(), full.size(), volume.call(quick), volume.call(full)])
	# Out and back in: rebuilt from its base boxes and its log.
	player.global_position = level.ground_point(m.global_position + Vector3(0, 0, 500))
	await _wait_for(func() -> bool: return not m.is_streamed(), 3.0)
	check(not m.is_streamed() and level.edit_logs().compound.size() == mine.size() + 2, "500 m away it streams out; its log stays")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var breach_local := SHED_BREACH
	check(Throwables.clear_line(space, through_breach[0], through_breach[1]) and not Throwables.clear_line(space, through_wall[0], through_wall[1])
		and m.proxy_boxes().all(func(b: AABB) -> bool: return not b.grow(0.05).has_point(breach_local)),
		"streamed out, its proxy keeps the breach open (sight, rounds, and the navigation baked meanwhile) and the rest of the wall")
	m = await _go_to_module("compound")
	check(m.voxel_world.holes_through(m.to_global(SHED_WALL)) == 1 and m.voxel_world.marks_near(m.to_global(Vector3(-2.95, 1.35, -4.0)), 0.05) == 1,
		"back again: rebuilt with the bullet holes and the mark")


## Soldiers in modules take rounds as in the compound: through a plank wall, and through a
## doorway into a room.
func _test_shot_in_module() -> void:
	print("Shooting soldiers in modules")
	var m := await _go_to_module("village_e", Vector3(-14, 0, 30))
	var victim := level.spawn_soldier({"name": "ShackMan", "person_name": "ShackMan", "faction": "hostile", "variant": "urban", "pos": m.to_global(Vector3(-12.5, 0.1, 9.0)),
		"loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(victim).process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.3).timeout
	var edits := GameState.voxel_edits.size()
	# From the north, through the shack's plank wall at z = 7 into the man standing inside.
	var result := _fire(m.to_global(Vector3(-12.5, 1.3, 2.0)), m.to_global(Vector3(-12.5, 1.3, 9.0)), &"m4a1")
	check(result.result == "body" and not victim.vitals.wound_list().is_empty(),
		"a round through the shack's plank wall hits the man inside (%s, %s)" % [result.result, victim.vitals.condition_text()])
	check(GameState.voxel_edits.slice(edits).any(func(e: Dictionary) -> bool: return e.get("w") == "village_e" and e.op == "shot"),
		"leaving a bullet hole in the village's log")
	var brick := level.spawn_soldier({"name": "BrickMan", "faction": "hostile", "variant": "urban", "pos": m.to_global(Vector3(11.0, 0.1, -9.0)),
		"loadout": ["plate_carrier", "plate_steel_l3"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(brick).process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.3).timeout
	var stopped := _fire(m.to_global(Vector3(11.0, 1.3, 2.0)), m.to_global(Vector3(11.0, 1.3, -9.0)), &"m4a1")
	# Low, at the pelvis, under the plate (at 0.6 m on his centre line it would pass between his legs:
	# hits land on the body's real shape, BodyVolume).
	var through_door := _fire(m.to_global(Vector3(11.0, 0.95, 2.0)), m.to_global(Vector3(11.0, 0.95, -9.0)), &"m4a1")
	check(through_door.result == "body" and not brick.vitals.wound_list().is_empty(),
		"through the brick house's doorway a round reaches the man inside (%s)" % through_door.result)
	check(stopped.result in ["body", "plate"], "and a chest-high round finds him through the doorway too (%s)" % stopped.result)
	_victims = [victim, brick]


var _victims: Array = []


## A module's loot lies in it and is picked up for good; first aid works on a man in one.
func _test_loot_and_care() -> void:
	print("Loot and first aid in modules")
	var m := level.get_module("village_e")
	var item := level.items.get_node_or_null(^"village_e_ifak") as WorldItem
	var spot := m.to_global(Vector3(1, 0, -9.5))
	check(item != null and Vector2(item.global_position.x - spot.x, item.global_position.z - spot.z).length() < 0.6 \
		and absf(item.global_position.y - m.global_position.y) < 0.6,
		"the village's IFAK lies on the floor of its cinder-block house (%s)" % (m.to_local(item.global_position) if item else "missing"))
	var cache := level.get_node_or_null(^"Caches/village_e_box_house") as WorldCache
	check(cache != null and absf(cache.global_position.y - m.global_position.y) < 0.3,
		"village_e's cupboard box sits on the floor of its cinder-block house (%s)" \
		% (m.to_local(cache.global_position) if cache else "missing"))
	if item:
		player.global_position = m.to_global(Vector3(1, 0.1, -8.6))
		player._server_interact.rpc_id(1, item.get_path())
		await get_tree().process_frame
		check(GameState.is_looted("village_e_ifak") and Vitals.has_item(player.inventory, &"ifak"), "picked up from inside the house, it counts as looted (saved)")
	var patient := level.spawn_soldier({"name": "Patient", "faction": "friendly", "variant": "multicam", "pos": m.to_global(Vector3(15.0, 0.1, -9.0)),
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
	SquadAI.of(patient).process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.3).timeout
	patient.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	var task := {}
	for t: Dictionary in patient.vitals.care_needed():
		if t.item == &"pressure_bandage":
			task = t
	check(not task.is_empty(), "a man hit in the brick house's back room needs a bandage (%s)" % [patient.vitals.care_needed()])
	if task.is_empty():
		return
	player.inventory.take(&"pressure_bandage")
	player.global_position = patient.global_position + Vector3(-0.8, 0, 0)
	player._server_treat.rpc_id(1, patient.get_path(), &"pressure_bandage", task.part)
	var part: StringName = task.part
	var treated := await _wait_for(func() -> bool: return not patient.vitals.care_needed().any(
		func(t: Dictionary) -> bool: return t.item == &"pressure_bandage" and t.part == part), 15.0)
	check(treated, "the player bandages him there (%s)" % [patient.vitals.care_needed()])
	patient.queue_free()


## A frag against a module wall is a blast in that module's log; a soldier killed in a module
## leaves a body that's saved with the zone.
func _test_frag_and_body() -> void:
	print("Frags and bodies in modules")
	var m := level.get_module("village_e")
	var edits := GameState.voxel_edits.size()
	Throwables.server_detonate(level, "frag", m.to_global(Vector3(-11.0, 0.05, 6.5)))
	var blasts := GameState.voxel_edits.slice(edits).filter(func(e: Dictionary) -> bool: return e.op == "blast")
	check(blasts.size() == 1 and blasts[0].get("w") == "village_e", "a frag by the shack is one blast in the village's log")
	var victim: Soldier = _victims[0]
	victim.vitals.server_kill()
	await get_tree().create_timer(0.3).timeout
	check(victim.vitals.is_dead() and victim.is_in_group(Soldier.DEAD_GROUP), "the man in the shack dies and leaves a body there")
	_body_pos = victim.global_position


var _body_pos := Vector3.ZERO


## AI walks from open ground on the terrain, through the compound module's gate, into its main
## building, on the navigation baked around it as it goes.
func _test_ai_path() -> void:
	print("AI pathing from the terrain into a module")
	var m := level.get_module("compound")
	var target := m.to_global(Vector3(0, 0, -8))
	player.global_position = level.ground_point(target)
	await _wait_for(func() -> bool: return m.is_ready(), 5.0)
	var start := level.ground_point(m.global_position + Vector3(14, 0, 62))
	var walker := level.spawn_soldier({"name": "Walker", "faction": "friendly", "variant": "multicam", "pos": start,
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": false, "mode": "safe"})
	await get_tree().create_timer(0.5).timeout  # the walker's brain sets up
	level.nav.refresh()
	await _wait_for(func() -> bool: return level.nav.is_settled(), 10.0)
	for i in 3:
		await get_tree().physics_frame  # the navigation map takes the new chunks
	check(level.nav.is_settled() and level.nav.chunk_total() > 20, "navigation baked around the player and the walker (%d chunks)" % level.nav.chunk_total())
	var path := NavigationServer3D.map_get_path(player.get_world_3d().navigation_map, start, target, true)
	var end := path[path.size() - 1] if not path.is_empty() else Vector3.INF
	check(not path.is_empty() and Vector2(end.x - target.x, end.z - target.z).length() < 0.6,
		"a path from the hillside to the building's floor (%d points, ends %.2f m from it)" % [path.size(), Vector2(end.x - target.x, end.z - target.z).length() if not path.is_empty() else INF])
	var gate := m.to_global(Vector3(0, 0, 30))
	var via_gate := false
	for p in path:
		via_gate = via_gate or Vector2(p.x - gate.x, p.z - gate.z).length() < 2.5
	check(via_gate, "through the compound's gate")
	level.squad_for(&"friendly").give_order(player, Squad.Order.MOVE, target, PackedStringArray(["Walker"]))
	var arrived := await _wait_for(func() -> bool: return Vector2(walker.global_position.x - target.x, walker.global_position.z - target.z).length() < 1.5, 60.0)
	check(arrived, "the walker gets there on foot (%.1f m left)" % Vector2(walker.global_position.x - target.x, walker.global_position.z - target.z).length())
	walker.queue_free()


## Captain, 2026-10-14 (falling out of the world): a soldier placed where the ground's chunk
## has no collision yet waits there instead of falling, and lands once it's there; one below the
## terrain or past the zone's edge goes back on the ground (GroundGuard); B-05: the compound's
## fixed placements sit on the terrain, not under it.
func _test_ground_guard() -> void:
	print("Ground: a spawn ahead of its chunk, and the safety net")
	var t := level.terrain
	var chunk_m := ZoneTerrain.CHUNK_CELLS * ZoneTerrain.CELL_M
	var half := t.size_m * 0.5
	# A chunk well inside the zone, clear of every module (their proxies are ground too).
	var c := Vector2i(-1, -1)
	var centre := Vector2.ZERO
	for cz in range(1, t.chunk_count() - 1):
		for cx in range(1, t.chunk_count() - 1):
			var at := Vector2(-half + (cx + 0.5) * chunk_m, -half + (cz + 0.5) * chunk_m)
			if c.x < 0 and level.modules().all(func(m: ZoneModule) -> bool: return m.distance_to(Vector3(at.x, 0.0, at.y)) > 120.0):
				c = Vector2i(cx, cz)
				centre = at
	check(c.x >= 0, "a ground chunk clear of the modules (%s)" % c)
	if c.x < 0:
		return
	var ground := t.get_node("Ground_%d_%d" % [c.x, c.y]) as StaticBody3D
	ground.collision_layer = 0  # this chunk's collision isn't there yet
	await get_tree().physics_frame
	# Clear of the scatter's rocks and trees (they have collision of their own): not just
	# straight under the spot but anywhere under his capsule and round it. Only clear under its
	# middle, he came down on a rock's edge beside it (CI: y 1.4 and 1.9 over ground at 1.0,
	# nothing on the ray straight down).
	var space := level.get_world_3d().direct_space_state
	var round_him := CylinderShape3D.new()
	round_him.radius = CLEAR_ROUND_M
	round_him.height = 8.0
	var near := PhysicsShapeQueryParameters3D.new()
	near.shape = round_him
	near.collision_mask = 1
	for i in 64:
		var at := centre + Vector2(i % 8 - 3.5, i / 8 - 3.5) * 12.0
		near.transform = Transform3D(Basis(), Vector3(at.x, t.height_at(at.x, at.y) + 1.0, at.y))
		if not GroundGuard.floor_below(level.get_world_3d(), Vector3(at.x, t.height_at(at.x, at.y) + 2.0, at.y)) \
				and space.intersect_shape(near, 1).is_empty():
			centre = at
			break
	var h := t.height_at(centre.x, centre.y)
	var guy := level.spawn_soldier({"name": "FallGuy", "person_name": "FallGuy", "faction": "hostile", "variant": "urban",
		"pos": Vector3(centre.x, h + 2.0, centre.y), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(guy).process_mode = Node.PROCESS_MODE_DISABLED
	# He's a hostile hundreds of metres from every player: the far-AI sleep (DynamicSim) froze
	# him mid-fall in the last metre above the ground (CI: y 1.73 over 0.99, falling at 4.9 m/s,
	# not on the floor; docs/audits/followups.md F-07). Not what this checks: it stays off here.
	var sim := DynamicSim.of(level)
	if sim:
		sim.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(1.0).timeout
	check(absf(guy.global_position.y - (h + 2.0)) < 0.2 and guy.movement.holding,
		"spawned where the ground's chunk has no collision yet, he waits there (y %.1f, ground %.1f)" % [guy.global_position.y, h])
	ground.collision_layer = 1
	# He lands on whatever is under him: the ground, or (a slow runner) a rock the scatter's
	# collision streamed in after the spot was picked (CI, a metre up). Either way he stopped
	# holding and stands on it. Waited for as a whole: down, not holding, and on what's under him.
	var seen := [{}]  # (what's under him, as the lambda last saw it)
	var landed := func() -> bool:
		var under: Dictionary = guy.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			guy.global_position + Vector3.UP * 0.5, guy.global_position + Vector3.DOWN * 3.0, 1, [guy.get_rid()]))
		seen[0] = under
		var on := not under.is_empty() and absf(float(under.position.y) - guy.global_position.y) < 0.3
		return guy.is_on_floor() and on and not guy.movement.holding
	await _wait_for(landed, 6.0)
	var under_him: Dictionary = seen[0]
	check(landed.call(), "once it's there he lands on it (at %s, ground %.1f, on %s at %.2f, floor %s, holding %s, velocity %s, slope %.0f deg)" % [
		guy.global_position, h, under_him.get("collider", "nothing"), float(under_him.position.y) if not under_him.is_empty() else INF, guy.is_on_floor(),
		guy.movement.holding, guy.velocity, rad_to_deg(t.normal_at(centre.x, centre.y).angle_to(Vector3.UP))])
	var guard := level.get_node(^"GroundGuard") as GroundGuard
	# Only the test's own check_now() below: the guard's every-CHECK_S round, landing in the
	# physics frame after a teleport, put him back first and the count read before it didn't
	# move (CI: "past the zone's edge" failed at (957, 0.4), right where it puts him).
	guard.set_physics_process(false)
	guy.global_position = Vector3(centre.x, h - 20.0, centre.y)
	await get_tree().physics_frame
	var before := guard.rescued
	guard.check_now()
	check(guard.rescued > before and absf(guy.global_position.y - h) < 1.0,
		"20 m under the terrain, the safety net puts him back on it (y %.1f, ground %.1f)" % [guy.global_position.y, h])
	guy.global_position = Vector3(half + 12.0, h - 5.0, centre.y)
	await get_tree().physics_frame
	var edge_h := t.height_at(half - GroundGuard.INSET_M, centre.y)
	before = guard.rescued
	guard.check_now()
	check(guard.rescued > before and guy.global_position.x <= half - GroundGuard.INSET_M + 0.01 and absf(guy.global_position.y - edge_h) < 1.0,
		"past the zone's edge, back inside on the ground (%.0f, %.1f)" % [guy.global_position.x, guy.global_position.y])
	guard.set_physics_process(true)
	var farid := Vector3(-8, 0.1, 12)  # PeopleLayer.COMPOUND's first civilian
	check(absf(level.above_ground(farid).y - t.height_at(farid.x, farid.z) - 0.1) < 0.01,
		"B-05: the compound's fixed placements go on the terrain in a zone")
	guy.queue_free()
	if sim:
		sim.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().physics_frame


## Saved, then hosted again from the save: module edits and bodies come back.
## Dig phase 2 (GroundCuts): a blast on open ground leaves a crater with real depth: the height
## lookups and the collision follow the bowl, the coarse ground has a hole there, the lip stands
## above the old ground, and a blast high in the air cuts nothing.
func _test_craters() -> void:
	print("Craters")
	var t := level.terrain
	var at := level.insertion_points()[0] + CRATER_FROM_INSERTION
	var was := t.height_at(at.x, at.z)
	var dig := Digging.of(level)
	var post := level.get_module("outpost_n")
	var dug_posts := dig.cut_ops.filter(func(op: Dictionary) -> bool:
		return op.kind == "mound" and Vector2(float(op.x) - post.global_position.x, float(op.z) - post.global_position.z).length() < 40.0)
	check(dug_posts.size() >= 2, "the enemy's outpost starts dug in (%d parapets round it)" % dug_posts.size())
	var before := dig.cut_ops.size()
	level.server_blast(Vector3(at.x, was + 0.1, at.z), 1.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var now := t.height_at(at.x, at.z)
	check(dig.cut_ops.size() == before + 1 and now < was - 0.4,
		"a charge on open ground leaves a crater (%.2f m deep)" % (was - now))
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, was + 10.0, at.z), Vector3(at.x, was - 10.0, at.z))
	var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and absf(float(hit.position.y) - now) < 0.05,
		"the collision follows the bowl (hit at %s, ground %.2f)" % [hit.get("position", "nothing"), now])
	var r := 1.6 * GroundCuts.CRATER_SCALE
	var lip := Vector3(at.x + r * 1.3, 0, at.z)
	check(t.height_at(lip.x, lip.z) > t.plane_height(lip.x, lip.z) + 0.02, "with a lip of earth thrown up round it")
	var far := Vector3(at.x + 40.0, 0, at.z)
	check(is_equal_approx(t.height_at(far.x, far.z), t.plane_height(far.x, far.z)), "and the ground away from it untouched")
	var high := Vector3(at.x - 30.0, 0, at.z)
	level.server_blast(Vector3(high.x, t.height_at(high.x, high.z) + 12.0, high.z), 1.6)
	check(dig.cut_ops.size() == before + 1, "an air burst 12 m up cuts nothing")
	var berms := dig.records.size()
	dig.server_add(level.ground_point(at + Vector3(-6, 0, 0)), 0.0)
	check(dig.records.size() == berms + 1, "and a berm next to it (for the reload and the late joiner)")
	# Dig phase 4: a squadmate told to hold a spot digs in there once he's been there a while.
	var spot := level.ground_point(at + Vector3(10, 0, -8))
	var digger := level.spawn_soldier({"name": "Digger", "faction": "friendly", "variant": "multicam", "pos": spot,
		"combat": 0.5, "discipline": 0.5, "guard": false, "loadout": ["m4a1", "mag_556"]})
	await get_tree().create_timer(0.5).timeout
	level.squad_for(&"friendly").give_order(player, Squad.Order.HOLD, spot, PackedStringArray(["Digger"]))
	var ai := SquadAI.of(digger)
	await _wait_for(func() -> bool: return ai._held_since >= 0.0, 5.0)
	ai._held_since -= SquadAI.DIG_IN_AFTER_S
	await _wait_for(func() -> bool: return dig.digging(digger), 3.0)
	check(dig.digging(digger), "a squadmate holding a spot digs in there (%s)" % ai.status_text() if ai.has_method(&"status_text") else "a squadmate holding a spot digs in there")
	for k in Digging.COVER_STAGES_M.size():
		var key := digger.get_instance_id()
		if dig._digs.has(key):
			dig._digs[key].started = float(dig._digs[key].started) - Digging.DIG_S  # (skip the 20 s)
		await get_tree().physics_frame
		await get_tree().physics_frame
		ai._held_since -= SquadAI.DIG_IN_AFTER_S
		await _wait_for(func() -> bool: return dig.digging(digger), 2.0)
	var p := digger.global_position
	var down := t.cuts.dug_depth(p.x, p.z) if t.cuts else 0.0
	var cover := Digging.cover_at(t, ai._hold_point, ai._dig_way)
	check(cover >= SquadAI.AI_COVER_TO_M - 0.15 and down < 0.05 and not dig.digging(digger),
		"cover built to kneeling height in front of him (%.2f m), the ground under him untouched (%.2f m down) [%s, %s, held %.1f s, %.2f m off the spot]" % [
			cover, down, Digging.problem(digger), ai.status_text(), Soldier._now() - ai._held_since, ai._flat_distance(ai._hold_point)])
	digger.queue_free()


func _test_reload() -> void:
	print("Saving and reloading the zone")
	GameState.save_zone()
	var saved := GameState.voxel_edits.size()
	# F-176: the dug ground comes back from the file, not only from memory: read_save keeps every
	# cut and berm, and drops a bad record without losing the rest.
	var dug := Digging.of(level).cut_ops.size()
	var dug_kinds := {}
	for op: Dictionary in Digging.of(level).cut_ops:
		dug_kinds[String(op.kind)] = true
	var berms_saved := Digging.of(level).records.size()
	var read := GameState.read_save(GameState.save_path())
	check(dug > 0 and (read.get("ground", {}).get("cuts", []) as Array).size() == dug and (read.get("ground", {}).get("berms", []) as Array).size() == berms_saved,
		"the save reads back with its dug ground (%d of %d cuts: %s; %d of %d berms)" % [(read.get("ground", {}).get("cuts", []) as Array).size(), dug,
			", ".join(dug_kinds.keys()), (read.get("ground", {}).get("berms", []) as Array).size(), berms_saved])
	check(not Digging.cut_ok({"kind": "pit", "x": 1.0, "z": NAN, "yaw": 0.0, "depth": 0.5}) and not Digging.cut_ok({"kind": "tunnel", "x": 1.0, "z": 1.0})
		and Digging.cut_ok(GroundCuts.pit_op(Vector3(1, 0, 2), 0.3, 0.5)) and not Digging.berm_ok({"id": 1, "pos": [0, 0], "yaw": 0, "colour": "806040", "hits": 0}),
		"and a cut or berm that makes no sense is dropped (a NaN, an unknown kind, a short position)")
	var def := level.def
	Net.leave()
	var old := level
	main.remove_child(old)
	old.queue_free()
	await get_tree().process_frame
	main.host_zone(def)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	level = CompoundLevel.current(self) as ZoneLevel
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	check(GameState.voxel_edits.size() == saved and level.edit_logs().get("compound", []).size() >= 3 and level.edit_logs().get("village_e", []).size() >= 2,
		"the save gives back every module's log (%d edits: compound %d, village %d)" % [saved, level.edit_logs().get("compound", []).size(), level.edit_logs().get("village_e", []).size()])
	var bodies := level.bodies.get_children().filter(func(b: Node) -> bool: return b is Soldier and (b as Soldier).display_name() == "ShackMan")
	check(bodies.size() == 1 and (bodies[0] as Soldier).global_position.distance_to(_body_pos) < 0.6, "the body in the shack is back where it lay")
	check(level.items.get_node_or_null(^"village_e_ifak") == null and level.items.get_node_or_null(^"village_e_mags") != null,
		"the IFAK taken from the village stays taken; the rest of its loot is back")
	var crater := level.insertion_points()[0] + CRATER_FROM_INSERTION
	var t := level.terrain
	await get_tree().physics_frame
	check(t.height_at(crater.x, crater.z) < t.plane_height(crater.x, crater.z) - 0.4 and Digging.of(level).records.size() >= 1,
		"the crater and the berms are back after the reload (%d berms, %d cuts)" % [Digging.of(level).records.size(), Digging.of(level).cut_ops.size()])
	check(Digging.of(level).cut_ops.size() == dug and Digging.of(level).records.size() == berms_saved,
		"every cut is back from the save, none dug afresh on top (%d of %d cuts, %d of %d berms)" % [Digging.of(level).cut_ops.size(), dug, Digging.of(level).records.size(), berms_saved])
	var m := await _go_to_module("compound")
	check(m.voxel_world.holes_through(m.to_global(SHED_WALL)) == 1 and m.voxel_world.marks_near(m.to_global(Vector3(-2.95, 1.35, -4.0)), 0.05) == 1,
		"after the reload the compound module has its bullet holes and mark")
	var v := await _go_to_module("village_e", Vector3(-14, 0, 30))
	check(v.voxel_world.bullet_hole_count() >= 2, "and the village its own (%d hole decals)" % v.voxel_world.bullet_hole_count())


func _test_budget(mem_before: float) -> void:
	print("Budgets")
	var worst: float = _frame_stats[0]
	var average: float = _frame_stats[1]
	check(worst < BUDGET_WORST_FRAME_MS, "worst frame while streaming %.1f ms (budget %.0f)" % [worst, BUDGET_WORST_FRAME_MS])
	check(average < BUDGET_AVERAGE_FRAME_MS, "average frame while streaming %.1f ms (budget %.0f)" % [average, BUDGET_AVERAGE_FRAME_MS])
	var used := _mem_mb() - mem_before
	check(used < BUDGET_MEMORY_MB, "the zone with its modules streaming takes %.0f MB of static memory (budget %.0f)" % [used, BUDGET_MEMORY_MB])


## Host: once the client is in, a live mark on the compound module's gate wall.
func _on_client_joined(id: int) -> void:
	await get_tree().create_timer(0.6).timeout
	var ins := level.insertion_points()[0]
	var client := level.players.get_node_or_null(str(id)) as Soldier
	check(client != null and client.global_position.distance_to(ins) < 8.0,
		"the late joiner's player is at the insertion point on the host too (%s)" % (client.global_position if client else "missing"))
	check(not client or not level.get_module("compound").is_streamed() or level.get_module("compound").distance_to(player.global_position) <= ZoneLevel.STREAM_IN_M,
		"and its arrival streamed in nothing at the zone's centre")
	await get_tree().create_timer(0.4).timeout
	var m := level.get_module("compound")
	if not m.is_streamed():
		player.global_position = level.ground_point(m.global_position + Vector3(0, 0, 30))
		await _wait_for(func() -> bool: return m.is_ready(), 5.0)
		await _wait_for_collision(m)
	m.voxel_world.server_mark(m.to_global(LIVE_MARK), Vector3.BACK, VoxelWorld.Mat.MUD_BRICK)
	print("[host] live mark for peer %d" % id)


## Client asks: what did the host generate?
@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var modules := {}
	for m in level.modules():
		modules[m.module_id] = [m.type, m.global_position]
	var crater := level.insertion_points()[0] + CRATER_FROM_INSERTION
	var caches := {}  # compound loot: every cache and site box (by name, sorted), and what's in it
	var found := level.find_children("*", "WorldCache", true, false)
	found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for c: Node in found:
		caches[String(c.name)] = (c as WorldCache).cargo_hold.entries().map(func(e: Dictionary) -> String: return "%s x%d" % [e.id, int(e.count)])
	return {"terrain": level.terrain.checksum(), "modules": modules, "map": level.map_area(),
		"crater": snappedf(level.terrain.height_at(crater.x, crater.z), 0.001), "berms": Digging.of(level).records.size(), "caches": caches}


# --- Client -----------------------------------------------------------------------------------

func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 480000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	print("Client joining a zone late")
	check(joined[0], "joined the host's session")
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the host's zone replaced the compound on joining")
	if level == null or not joined[0]:
		_finish()
		return
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 5.0)
	var mine := _digest()
	check(_host_digest.get("terrain") == mine.terrain and _host_digest.get("map") == mine.map,
		"the same terrain from the seed as the host's (checksum %d)" % mine.terrain)
	check(str(_host_digest.get("modules")) == str(mine.modules), "the same modules in the same places (%d)" % (mine.modules as Dictionary).size())
	var host_caches: Dictionary = _host_digest.get("caches", {})
	await _wait_for(func() -> bool: return str(_digest().caches) == str(host_caches), 10.0)
	check(not host_caches.is_empty() and str(_digest().caches) == str(host_caches),
		"the late joiner gets the host's caches and site boxes with what's in them (%d; %s)" % [host_caches.size(), _digest().caches.get("village_e_box_house", "missing")])
	await _wait_for(func() -> bool: return _digest().crater == _host_digest.get("crater") and _digest().berms == _host_digest.get("berms"), 5.0)
	mine = _digest()
	check(mine.crater == _host_digest.get("crater") and int(mine.berms) >= 1,
		"the late joiner gets the host's crater (ground %.2f, host's %s) and berms (%d, host's %s)" % [mine.crater, _host_digest.get("crater"), mine.berms, _host_digest.get("berms")])
	var my_name := str(multiplayer.get_unique_id())
	await _wait_for(func() -> bool: return level.players.get_node_or_null(my_name) != null, 10.0)
	var me := level.players.get_node_or_null(my_name) as Soldier
	check(me != null and me.is_local(), "the client's player spawned")
	if me == null:
		_finish()
		return
	var ins := level.insertion_points()[0]
	check(me.global_position.distance_to(ins) < 8.0, "at the insertion point, not the zone's centre (%.1f m from it)" % me.global_position.distance_to(ins))
	await get_tree().create_timer(1.5).timeout  # the host checks it sees us there too
	me.set_physics_process(false)
	await _wait_for(func() -> bool: return level.streamed_modules().is_empty(), 3.0)
	check(level.streamed_modules().is_empty(), "no module streamed in at the insertion point, far from them all (%s at %s)" % [
		level.streamed_modules().map(func(m: ZoneModule) -> String: return m.module_id), me.global_position])
	var m := level.get_module("compound")
	me.global_position = level.ground_point(m.global_position + Vector3(0, 0, 30))
	await _wait_for(func() -> bool: return m.is_ready(), 10.0)
	check(m.is_ready(), "walking up to the compound module streams it in on the client")
	await _wait_for(func() -> bool: return m.voxel_world and m.voxel_world.marks_near(m.to_global(LIVE_MARK), 0.05) >= 1, 10.0)
	var world := m.voxel_world
	check(world != null and world.holes_through(m.to_global(SHED_WALL)) == 1 and world.bullet_hole_count() >= 4,
		"the late joiner gets the saved bullet holes in the module (%d decals)" % (world.bullet_hole_count() if world else -1))
	check(world != null and world.marks_near(m.to_global(Vector3(-2.95, 1.35, -4.0)), 0.05) == 1, "and the saved mark")
	check(world != null and world.marks_near(m.to_global(LIVE_MARK), 0.05) == 1, "and the host's live one")
	check(level.get_module("village_e").is_streamed() == false and level.edit_logs().get("village_e", []).size() >= 2,
		"a module it hasn't been near stays out, its log already here (%d edits)" % level.edit_logs().get("village_e", []).size())
	_finish()


func _finish() -> void:
	print("WORLD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	if not multiplayer.is_server():
		Net.leave()
		await get_tree().create_timer(0.5).timeout
	if multiplayer.is_server():
		GameState.delete_save()
	get_tree().quit(failures)


## 4B part 3: a hot zone's layout (Captain: 16 km²): the enemy's structure, roads and patrols,
## insertion points well clear of every site, the same from the same seed.
func _test_hot_layout() -> void:
	print("Hot zone layout")
	for seed in [4409, 5503, 77, 1234]:
		var hot := ZoneDef.generate_hot(seed)
		var count := func(type: String) -> int: return (hot.modules as Array).filter(func(m: Dictionary) -> bool: return ZoneModules.base(m.type) == type).size()
		var sites: Array[Vector2] = []
		for m: Dictionary in hot.modules:
			sites.append(Vector2(m.pos[0], m.pos[1]))
		var spaced := true
		for i in sites.size():
			for j in range(i + 1, sites.size()):
				spaced = spaced and sites[i].distance_to(sites[j]) >= ZoneDef.MIN_SPACING_M - ZoneDef.GRID_M
		var clear := (hot.insertion as Array).all(func(p: Array) -> bool: return ZoneDef._clearance(Vector2(p[0], p[1]), sites) >= ZoneDef.HOT_INSERTION_CLEAR_M)
		var first_best := (hot.insertion as Array).size() < 2 or ZoneDef._clearance(Vector2(hot.insertion[0][0], hot.insertion[0][1]), sites) \
			>= ZoneDef._clearance(Vector2(hot.insertion[1][0], hot.insertion[1][1]), sites)
		check(is_equal_approx(float(hot.size_m), 4096.0) and hot.kind == "hot" and count.call("hq") == 1 and count.call("comms") == 1
			and count.call("qrf_base") >= 1 and count.call("outpost") >= 3 and count.call("checkpoint") >= 2 and count.call("village") >= 1
			and count.call("town") == ZoneDef.HOT_TOWNS,
			"seed %d: a 16 km² hot zone: an HQ, a comms site, %d QRF bases, %d outposts, %d checkpoints, %d villages, %d town" % [seed,
			count.call("qrf_base"), count.call("outpost"), count.call("checkpoint"), count.call("village"), count.call("town")])
		check(spaced and clear and first_best and (hot.insertion as Array).size() == 3 and (hot.extraction as Array).size() == 3,
			"seed %d: sites spaced out, 3 insertion points %d m clear of every site (the default the furthest), 3 extractions" % [seed, int(ZoneDef.HOT_INSERTION_CLEAR_M)])
		# Captain, 2026-10-16: trails now cross every zone too (ZoneDef._add_trails, TRAILS of
		# them), each adding its own road segments on top of the one straight to each outpost, so
		# roads no longer land one-for-one with outposts (just at least one each).
		check((hot.roads as Array).size() >= count.call("outpost") and (hot.patrols as Array).size() >= 2
			and ZoneDef.generate_hot(seed).hash() == hot.hash(), "seed %d: roads to every outpost and %d trails (%d roads for %d outposts), %d patrol routes, the same every time" % [seed, ZoneDef.TRAILS, (hot.roads as Array).size(), count.call("outpost"), (hot.patrols as Array).size()])
	# The town is a real module type, with people, loot and a callsign of its own.
	var town: Dictionary = (ZoneDef.generate_hot(4409).modules as Array).filter(func(m: Dictionary) -> bool: return ZoneModules.base(m.type) == "town")[0]
	var ttype := String(town.type)
	var civs: Array = MissionRegistry.module(ttype).get("civilians", [])
	var loot: Array = ZoneModules.LOOT.get(ttype, [])
	var half: Vector2 = ZoneModules.HALF[ttype]
	var in_town := func(a: Array) -> bool: return absf(float(a[0])) <= half.x and absf(float(a[2])) <= half.y
	check(String(town.id).begins_with("town_") and civs.size() >= 3 and civs.all(func(c: Dictionary) -> bool:
			return in_town.call(c.pos) and (c.routine as Array).size() == 3 and (c.routine as Array).all(in_town))
		and loot.size() >= 2 and loot.all(func(l: Dictionary) -> bool: return in_town.call([l.pos.x, l.pos.y, l.pos.z])),
		"a hot zone's town (%s, \"%s\"): %d civilians walking its streets, %d loot spots, all inside it" % [ttype, town.id, civs.size(), loot.size()])
	check(PersonLook.TOWN_SITES.has(ZoneModules.base(ttype)) and MissionRegistry.module("village").get("civilians", []).size() == 3
		and ZoneModules.base("village") == "village", "townsfolk dress local; villages keep their own entry")
	# Contract zones: Harbour yard holds a town, and an HVT capture, hostage rescue or intel grab
	# there plays at sites made from its buildings.
	var harbour: Array = (MissionRegistry.zone_def("harbour_yard").modules as Array).filter(func(m: Dictionary) -> bool: return ZoneModules.base(m.type) == "town")
	var zone_entry: Array = MissionRegistry.zones().filter(func(z: Dictionary) -> bool: return z.zone_id == "harbour_yard")
	check(harbour.size() == 1 and not zone_entry.is_empty() and "town" in zone_entry[0].modules, "Harbour yard holds a town (%s)" % [harbour.map(func(m: Dictionary) -> String: return m.type)])
	if harbour.size() == 1:
		var htype := String(harbour[0].type)
		var hhalf: Vector2 = ZoneModules.HALF[htype]
		var sites_ok := true
		for id: String in ["area", "intel", "docs", "hvt", "hvt_phone", "hostage", "cache"]:
			var site := MissionRegistry.site(htype, id)
			sites_ok = sites_ok and not site.is_empty() and (not site.has("pos") or in_town.call(site.pos))
		var rng := RandomNumberGenerator.new()
		var picked := []
		for type_id: String in ["raid", "hvt_capture", "hostage_rescue", "intel_grab"]:
			for k in 40:
				rng.seed = k
				var target := ContractGen.mission_target(rng, MissionRegistry.type_def(type_id), "harbour_yard")
				if target.module == htype:
					picked.append(type_id)
					sites_ok = sites_ok and (target.objectives as Array).all(func(ob: Dictionary) -> bool: return MissionRegistry.has_site(htype, String(ob.site)))
					break
		var hvt_at: Array = MissionRegistry.site(htype, "hvt").pos
		var hostage_at: Array = MissionRegistry.site(htype, "hostage").pos
		var crates := int(MissionRegistry.site(htype, "cache").get("voxels", 0))
		check(sites_ok and picked.size() == 4 and hvt_at != hostage_at and crates >= 1000,
			"its contract sites come from its buildings (HVT at %s, hostage at %s, a cache of %d voxels), and %s can play there" % [hvt_at, hostage_at, crates, picked])
	# Urban hot zones: a city (queue item 1.5: it took the place of 3-4 towns packed round the HQ),
	# its blocks within reach of the HQ and clear of the other sites, a road in from the HQ, patrols
	# in its streets (tests/city_test.gd checks the city itself).
	for seed in [6607, 4409, 77]:
		var city := ZoneDef.generate_hot(seed, ZoneDef.HOT_SIZE_M, true)
		var mods: Array = city.modules
		var hq_m: Dictionary = mods.filter(func(m: Dictionary) -> bool: return m.type == "hq")[0]
		var hq_at := Vector2(hq_m.pos[0], hq_m.pos[1])
		var blocks: Array = mods.filter(func(m: Dictionary) -> bool: return String(m.type).begins_with(ZoneModules.CITY))
		var cities: Array = city.get("cities", [])
		var at := Vector2(float(cities[0].pos[0]), float(cities[0].pos[1])) if not cities.is_empty() else Vector2.INF
		var c_half: Vector2 = BuildingGen.city_layout(int(cities[0].seed)).half if not cities.is_empty() else Vector2.ZERO
		var area := Rect2(at - c_half, c_half * 2.0)
		var near := at.distance_to(hq_at) <= ZoneDef.URBAN_REACH_M.y + ZoneDef.GRID_M
		var road_in := (city.roads as Array).any(func(r: Array) -> bool: return area.grow(0.5).has_point(Vector2(float(r[1][0]), float(r[1][1]))))
		var patrolled := (city.patrols as Array).any(func(route: Array) -> bool:
			return route.all(func(q: Array) -> bool: return area.has_point(Vector2(q[0], q[1]))))
		var clear := mods.all(func(m: Dictionary) -> bool: return String(m.type).begins_with(ZoneModules.CITY) or not area.grow(ZoneDef.URBAN_CITY_KEEP_M - 1.0).has_point(Vector2(m.pos[0], m.pos[1])))
		check(bool(city.get("urban", false)) and cities.size() == 1 and blocks.size() == BuildingGen.CITY_BLOCKS.x * BuildingGen.CITY_BLOCKS.y and near and road_in and clear
			and patrolled and mods.any(func(m: Dictionary) -> bool: return ZoneModules.base(m.type) == "village") and ZoneDef.generate_hot(seed, ZoneDef.HOT_SIZE_M, true).hash() == city.hash(),
			"urban seed %d: a city of %d blocks within %d m of the HQ, clear of the other sites, a road in, patrols in its streets, a village outside, the same every time" % [seed,
			blocks.size(), int(ZoneDef.URBAN_REACH_M.y)])
	var old_quarter := MissionRegistry.zone_def("city_hot")
	check(bool(old_quarter.get("urban", false)) and old_quarter.get("kind", "") == "hot" and MissionRegistry.zone("city_hot").get("modules", []).has("town"),
		"the campaign has an urban hot zone (%s: %d city blocks)" % [old_quarter.get("name", ""),
		(old_quarter.get("modules", []) as Array).filter(func(m: Dictionary) -> bool: return String(m.type).begins_with(ZoneModules.CITY)).size()])
	var spec := MissionRegistry.zone_def("ridge_hot")
	check(spec.get("kind", "") == "hot" and is_equal_approx(float(spec.size_m), 4096.0), "the campaign's hot zones are 16 km² hot layouts")
	# Terrain visual pass: the roads are drawn, on the ground and off the module pads, and the
	# ground along them takes the road colour (seen past ZoneRoads.SEE_M).
	var def := ZoneDef.normalize(ZoneDef.generate_hot(4409))
	var t := _preset_terrain(def)
	var roads := ZoneRoads.new()
	roads.build(t, def)
	var on_ground := true
	var off_pads := true
	for v in roads.vertices:
		on_ground = on_ground and absf(v.y - t.height_at(v.x, v.z) - ZoneRoads.LIFT_M) < 0.01
		var inside := t.pads.any(func(pad: Array) -> bool:
			return (pad[0] as Rect2).grow(-(ZoneRoads.WIDTH_M * 0.5 + ZoneRoads.STEP_M)).has_point(Vector2(v.x, v.z)))
		off_pads = off_pads and not inside
	var r0: Array = def.roads[0]
	var mid := (Vector2(r0[0][0], r0[0][1]) + Vector2(r0[1][0], r0[1][1])) * 0.5
	var across := (Vector2(r0[1][0], r0[1][1]) - Vector2(r0[0][0], r0[0][1])).normalized().orthogonal()
	check(roads.segments == (def.roads as Array).size() and on_ground and off_pads,
		"hot zone roads drawn: %d of %d, on the ground (%.2f m up), not over the module pads" % [roads.segments, (def.roads as Array).size(), ZoneRoads.LIFT_M])
	# A town's streets are road-coloured on its pad.
	var town_m: Dictionary = (def.modules as Array).filter(func(m: Dictionary) -> bool: return ZoneModules.base(m.type) == "town")[0]
	var tp := Vector2(town_m.pos[0], town_m.pos[1])
	var street_i := roundi((tp.x + 20.0 + t.size_m * 0.5) / ZoneTerrain.CELL_M)
	var street_j := roundi((tp.y + t.size_m * 0.5) / ZoneTerrain.CELL_M)
	var lot_j := roundi((tp.y + 14.0 + t.size_m * 0.5) / ZoneTerrain.CELL_M)
	check(t._ground_colour(street_i, street_j, Vector3.UP) == t.c_road and t._ground_colour(street_i, lot_j, Vector3.UP) == t.c_earth,
		"a town's main street is road-coloured on its pad, its lots bare earth")
	check(is_equal_approx(t.road_weight(mid.x, mid.y), 1.0) and t.road_weight(mid.x + across.x * 20.0, mid.y + across.y * 20.0) == 0.0,
		"the ground on a road takes its colour, and 20 m off it doesn't (%.2f, %.2f)" % [t.road_weight(mid.x, mid.y), t.road_weight(mid.x + across.x * 20.0, mid.y + across.y * 20.0)])
	roads.free()
	t.free()


# --- Procedural buildings (docs/building_gen.md) ----------------------------------------------

## Houses (phase 1) and shops, warehouses, clinics and police stations (phase 2); second
## storeys, roofs, L shapes and yards (phase 3). Over many seeds: the right rooms, every room
## reachable from the street (up the stairs too), the bathroom off one doorway, doorways clear
## of furniture, everything inside the lot, the same building from the same seed, and within a
## voxel budget (per storey).
func _test_building_gen() -> void:
	print("Procedural buildings: houses, shops, warehouses, clinics, police stations")
	var feats := {"two storeys": 0, "roof access": 0, "l shape": 0, "yard": 0}
	var ok_stairs := true
	var ok_rooms := true
	var ok_reach := true
	var ok_doors := true
	var ok_inside := true
	var furnished := 0
	var room_total := 0
	var worst_voxels := 0
	var styles := {}
	var bare := {}  # role -> rooms of it left unfurnished
	var bad := []
	var runs := []
	for seed in range(1, 41):
		runs.append(["house", seed])
	for type: String in ["shop", "warehouse", "clinic", "police"]:
		for seed in range(1, 16 if type != "shop" else 21):
			runs.append([type, seed * 7 + 3])
	for run: Array in runs:
		var type: String = run[0]
		var seed: int = run[1]
		var hs := BuildingGen.building(type, seed)
		var spec: Dictionary = BuildingGen.TYPES[type]
		styles[hs.style] = true
		var rooms: Array = hs.rooms
		var n := rooms.size()
		# The type's rules are the ground floor's; the floor above has rooms of its own.
		var roles: Array = rooms.filter(func(r: Dictionary) -> bool: return int(r.floor) == 0).map(func(r: Dictionary) -> String: return r.role)
		var n0 := roles.size()
		room_total += n
		feats["two storeys"] += 1 if int(hs.storeys) == 2 else 0
		feats["roof access"] += 1 if hs.roof_access else 0
		feats["l shape"] += 1 if hs.shape == "l" else 0
		feats["yard"] += (hs.yards as Array).size()
		# Stairs: no step higher than the navmesh climbs, a stair door for each, each floor's
		# rooms at its height.
		for st: Dictionary in hs.stairs:
			if (float(st.to_y) - float(st.from_y)) / int(st.steps) > 0.25 + 0.001:
				ok_stairs = false
				bad.append("%s %d: stair steps %.2f m" % [type, seed, (float(st.to_y) - float(st.from_y)) / int(st.steps)])
		if (hs.doors as Array).filter(func(dr: Dictionary) -> bool: return dr.get("stair", false)).size() != (hs.stairs as Array).size() \
				or (int(hs.storeys) == 2) != rooms.any(func(r: Dictionary) -> bool: return int(r.floor) == 1) \
				or (hs.roof_access as bool) != (hs.doors as Array).any(func(dr: Dictionary) -> bool: return int(dr.rooms[1]) == -2):
			ok_stairs = false
			bad.append("%s %d: storeys %d, %d stairs, roof %s" % [type, seed, hs.storeys, (hs.stairs as Array).size(), hs.roof_access])
		furnished += rooms.filter(func(r: Dictionary) -> bool: return r.chunk != "").size()
		for r: Dictionary in rooms:
			if r.chunk == "":
				bare["%s %s" % [type, r.role]] = int(bare.get("%s %s" % [type, r.role], 0)) + 1
		var right: bool = n0 >= int(spec.rooms[0]) and n0 <= int(spec.rooms[1]) and roles.count(spec.front) == 1 and roles.count("bathroom") <= 1
		if type == "house":
			right = right and roles.count("kitchen") == 1 and roles.count("bathroom") == 1
		if type == "police":
			right = right and roles.has("armoury") and roles.has("cells")
		if not right:
			ok_rooms = false
			bad.append("%s %d rooms %s" % [type, seed, roles])
		# Reachable from outside through the doorways; the bathroom has one.
		var seen := {-1: true}
		var grew := true
		while grew:
			grew = false
			for dr: Dictionary in hs.doors:
				var a: int = dr.rooms[0]
				var b: int = dr.rooms[1]
				if seen.has(a) != seen.has(b):
					seen[a] = true
					seen[b] = true
					grew = true
		var bath := roles.find("bathroom")
		var bath_doors := (hs.doors as Array).filter(func(dr: Dictionary) -> bool: return bath in dr.rooms).size()
		var front := (hs.doors as Array).any(func(dr: Dictionary) -> bool: return dr.rooms[1] == -1 and (dr.at as Vector3).z > 0.0)
		var reached := seen.keys().filter(func(k: int) -> bool: return k >= 0).size()
		if reached != n or (bath >= 0 and bath_doors != 1) or not front:
			ok_reach = false
			bad.append("%s %d: %d of %d rooms reached, bathroom doors %d, front door %s" % [type, seed, reached, n, bath_doors, front])
		# Doorways clear: the gap itself and a step either side of it.
		var solid := func(q: Vector3) -> bool:
			return (hs.boxes as Array).any(func(bx: Array) -> bool: return AABB(bx[0], (bx[1] as Vector3) - (bx[0] as Vector3)).has_point(q))
		for dr: Dictionary in hs.doors:
			var at: Vector3 = (dr.at as Vector3) + Vector3(0, 0.5, 0)
			var through_x: bool = not solid.call(at + Vector3(0.6, 0, 0)) and not solid.call(at - Vector3(0.6, 0, 0))
			var through_z: bool = not solid.call(at + Vector3(0, 0, 0.6)) and not solid.call(at - Vector3(0, 0, 0.6))
			if solid.call(at) or not (through_x or through_z) and dr.rooms[1] != -1 and not dr.get("stair", false):
				ok_doors = false
				bad.append("%s %d: doorway at %s blocked" % [type, seed, dr.at])
		# Inside the shell, and its size in voxels.
		var half := (hs.size as Vector2) * 0.5
		var top := float(hs.height)
		var voxels := 0
		for bx: Array in hs.boxes:
			var lo: Vector3 = bx[0]
			var hi: Vector3 = bx[1]
			voxels += int((hi - lo).x * (hi - lo).y * (hi - lo).z / pow(VoxelWorld.VOXEL_SIZE, 3))
			if lo.x < -half.x - 0.01 or lo.z < -half.y - 0.01 or hi.x > half.x + 0.01 or hi.z > half.y + 0.01 or hi.y > top + 0.01 or lo.y < -0.01:
				ok_inside = false
		voxels /= int(hs.storeys)
		worst_voxels = maxi(worst_voxels, voxels if type != "warehouse" else voxels / 2)
	check(ok_rooms, "%d buildings: each type's rooms (a house's living room, kitchen and bathroom; a police station's armoury and cells) %s" % [runs.size(), bad.slice(0, 3)])
	check(ok_reach, "every room reachable from the street, a front door on it, the bathroom off one doorway %s" % [bad.slice(0, 3)])
	check(ok_doors, "doorways clear of furniture: walk through each %s" % [bad.slice(0, 3)])
	check(ok_inside and worst_voxels < 150000, "everything inside the lot and under its top; at most %d voxels a storey (budget 150000; a warehouse twice that)" % worst_voxels)
	check(ok_stairs and feats.values().all(func(v: int) -> bool: return v >= 3),
		"phase 3: %s; every stair's steps 0.25 m or less, a stair door for each, one up to the roof when it's used %s" % [feats, bad.slice(0, 3)])
	check(furnished >= room_total - runs.size() / 20 and styles.size() >= 3,
		"rooms furnished from the chunk library (%d of %d; bare: %s), in %d styles" % [furnished, room_total, bare, styles.size()])
	# A second storey's stairwell isn't walled across, and its landing is in the room above.
	var ok_well := true
	for seed in range(1, 61):
		var b := BuildingGen.building(["house", "shop", "clinic", "police"][seed % 4], seed * 13)
		if int(b.storeys) != 2:
			continue
		var foot: Rect2 = (b.stairs as Array)[0].foot
		var y_up := float((b.stairs as Array)[0].to_y)
		for bx: Array in b.boxes:
			var lo: Vector3 = bx[0]
			var hi: Vector3 = bx[1]
			if lo.y >= y_up - 0.01 and lo.y < y_up + 2.0 and Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z).grow(-0.01).intersects(foot.grow(-0.05)):
				ok_well = false
	check(ok_well, "nothing stands in a stairwell on the floor above")
	var again := BuildingGen.house(7)
	check(BuildingGen.house(7).boxes == again.boxes and BuildingGen.house(8).boxes != again.boxes, "the same seed builds the same house, another seed another")


## Towns (phase 2): a street grid of generated buildings, a module type of its own.
func _test_towns() -> void:
	print("Procedural buildings: towns")
	var counts := []
	var ok_mix := true
	var ok_apart := true
	var ok_facing := true
	var ok_inside := true
	var why := []
	for seed: int in [5, 12, 77, 301, 4409, 9001, 23, 640]:
		var t := BuildingGen.town(seed)
		var bs: Array = t.buildings
		counts.append(bs.size())
		var types: Array = bs.map(func(b: Dictionary) -> String: return b.type)
		var fronts := bs.filter(func(b: Dictionary) -> bool: return not b.get("back", false)).size()
		var backs := bs.size() - fronts
		if fronts < 12 or fronts > 20 or backs <= 0 or backs > 20 or types.count("clinic") > 1 or types.count("police") > 1:
			ok_mix = false
			why.append("town %d: %d buildings %s" % [seed, bs.size(), types])
		var rects: Array[Rect2] = []
		for b: Dictionary in bs:
			var size: Vector2 = b.data.size
			var o: Vector3 = b.origin
			var r := Rect2(o.x - size.x * 0.5, o.z - size.y * 0.5, size.x, size.y)
			for q: Rect2 in rects:
				if q.grow(BuildingGen.LOT_GAP * 0.5 - 0.05).intersects(r):
					ok_apart = false
					why.append("town %d: %s overlaps" % [seed, b.type])
			rects.append(r)
			var half: Vector2 = t.half
			if absf(r.position.x) > half.x or absf(r.end.x) > half.x or absf(r.position.y) > half.y or absf(r.end.y) > half.y \
					or (r.position.y < BuildingGen.STREET_W * 0.5 and r.end.y > -BuildingGen.STREET_W * 0.5):
				ok_inside = false
				why.append("town %d: %s outside or in the street" % [seed, b.type])
			# Front rows face the main street; back rows face the outer street.
			var front := (b.data.doors as Array).filter(func(dr: Dictionary) -> bool: return dr.rooms[1] == -1)
			front.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return (p.at as Vector3).z > (q.at as Vector3).z)  # the front wall's door first
			if front.is_empty():
				ok_facing = false
			else:
				var at: Vector3 = front[0].at
				var world_z: float = (-at.z if b.turned else at.z) + o.z
				if (world_z - o.z) * signf(o.z) * (-1.0 if b.get("back", false) else 1.0) > 0.0:
					ok_facing = false
					why.append("town %d: %s faces away" % [seed, b.type])
	check(ok_mix, "towns (8 seeds): 12 to 20 front buildings plus back rows (%s), a clinic and a police station at most once %s" % [counts, why.slice(0, 2)])
	check(ok_apart and ok_inside, "lots don't overlap, inside the town's footprint and off the street %s" % [why.slice(0, 2)])
	check(ok_facing, "every building's front door opens onto its street %s" % [why.slice(0, 2)])
	_test_town_posts()
	var type := "town#4409"
	check(ZoneModules.has_type(type) and not ZoneModules.boxes(type).is_empty() and ZoneModules.HALF.has(type)
		and not (ZoneModules.points(type, "objective") as Array).is_empty() and not (ZoneModules.points(type, "cache") as Array).is_empty()
		and not (ZoneModules.points(type, "intel") as Array).is_empty() and (ZoneModules.GARRISON.get(type, []) as Array).size() >= 6,
		"a town is a module type (\"%s\"): its boxes, footprint %s, objective, cache and intel points, %d garrison posts" % [type,
		ZoneModules.HALF.get(type), (ZoneModules.GARRISON.get(type, []) as Array).size()])
	check(not ZoneModules.has_type("town#x") and BuildingGen.town(12).boxes == BuildingGen.town(12).boxes,
		"a bad seed isn't a type; the same seed builds the same town")
	check((ZoneModules.GARRISON_FACE.get(type, []) as Array).size() == (ZoneModules.GARRISON.get(type, []) as Array).size(),
		"and the way each of its posts looks out (%d)" % (ZoneModules.GARRISON_FACE.get(type, []) as Array).size())
	# Its stairs as ramps for the navmesh bake (ZoneNav): two triangles a stair, every stair.
	var stairs := 0
	for bt: Dictionary in BuildingGen.town(4409).buildings:
		stairs += (bt.data.stairs as Array).size()
	check(stairs > 0 and ZoneModules.ramps(type).size() == stairs * BuildingGen.RAMP_FACES and ZoneModules.ramps("village").is_empty(),
		"its %d stairs have ramps for the navmesh (%d corners); a village has none" % [stairs, ZoneModules.ramps(type).size()])
	# Navigation reaches the roofs (F-01): a zone chunk's bake keeps HEADROOM_M over its highest
	# ground, room for the tallest building's roof and a soldier standing on it.
	var tallest := 0.0
	for seed in range(1, 41):
		var b := BuildingGen.building(["house", "shop", "clinic", "police"][seed % 4], seed * 13)
		if b.roof_access:
			tallest = maxf(tallest, float(b.roof_y))
	check(tallest > 5.0 and tallest + NavBuilder.AGENT_HEIGHT < ZoneNav.HEADROOM_M,
		"a zone's navmesh bakes %.0f m up: a two-storey roof (%.1f m) and a man on it fit" % [ZoneNav.HEADROOM_M, tallest])


## Town garrison posts (audit follow-up F-02): about a third up high, at upper windows and on
## roofs (only roofs with a parapet: those a stair goes up to), each standing on a floor with
## room round him, looking out onto the street; the rest on the ground, most inside front doors.
func _test_town_posts() -> void:
	var seeds: Array = [5, 12, 77, 301, 4409, 9001, 23, 640]
	var shares := []
	var ok_share := true
	var all_high := 0
	var all_posts := 0
	var all_front_posts := 0
	var ok_up := true
	var ok_ground := true
	var roofs := 0
	var windows := 0
	var why := []
	for seed: int in seeds:
		var t := BuildingGen.town(seed)
		var posts: Array = t.garrison
		var faces: Array = t.garrison_face
		var high := 0
		var ground := 0
		for i in posts.size():
			var p: Vector3 = posts[i]
			if p.y < 1.0:
				ground += 1
				continue
			high += 1
			# Which building it stands in, and on what.
			var home := {}
			for b: Dictionary in t.buildings:
				var size: Vector2 = b.data.size
				var o: Vector3 = b.origin
				if absf(p.x - o.x) < size.x * 0.5 and absf(p.z - o.z) < size.y * 0.5:
					home = b
			if home.is_empty():
				ok_up = false
				why.append("town %d: post %s in no building" % [seed, p])
				continue
			var local: Vector3 = p - (home.origin as Vector3)
			if home.turned:
				local = Vector3(-local.x, local.y, -local.z)
			var upper: Array = (home.data.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == 1)
			var on_roof: bool = home.data.roof_access and absf(local.y - float(home.data.roof_y) - 0.1) < 0.05
			var upstairs: bool = int(home.data.storeys) == 2 and not upper.is_empty() and absf(local.y - float(upper[0].y) - 0.1) < 0.05
			roofs += 1 if on_roof else 0
			windows += 1 if upstairs else 0
			var out: Vector3 = faces[i]
			var street := Vector3(0, 0, -signf((home.origin as Vector3).z))  # toward the main street
			if not (on_roof or upstairs) or not BuildingGen._clear_post(home.data.boxes, local) or out.dot(street) < 0.5:
				ok_up = false
				why.append("town %d: post %s (roof %s, upstairs %s, looks %s)" % [seed, local, on_roof, upstairs, out])
		# A third of them, as far as the town has buildings with an upper floor or a roof to stand on.
		var can := 0
		for bi in (t.buildings as Array).size():
			can += 0 if t.buildings[bi].get("back", false) or BuildingGen._high_post(t.buildings[bi].data, bi).is_empty() else 1
		var front_count := (t.buildings as Array).filter(func(b: Dictionary) -> bool: return not b.get("back", false)).size()
		var total := (front_count + 1) / 2 + 2  # as BuildingGen._town_posts counts them
		var want := mini(roundi(total * BuildingGen.TOWN_HIGH_SHARE), can)
		shares.append("%d/%d" % [high, posts.size()])
		all_high += high
		all_posts += posts.size()
		all_front_posts += total
		if high != want or float(high) / maxf(posts.size(), 1.0) > 0.4 or high != int(t.garrison_high):
			ok_share = false
		if ground * 2 < posts.size() or faces.size() != posts.size():
			ok_ground = false
	var all_share := float(all_high) / maxf(all_posts, 1.0)
	check(ok_share and float(all_high) / maxf(all_front_posts, 1.0) >= 0.3 and roofs >= 3 and windows >= 3,
		"town garrisons (8 seeds): the intended share of street posts up high, plus indoor posts where the town has the buildings for it (%s, %.0f%% in all), at upper windows (%d) and on roofs (%d)" % [", ".join(shares), all_share * 100.0, windows, roofs])
	check(ok_up, "each up high stands on a floor or a roof with a parapet, room round him, looking out onto the street %s" % [why.slice(0, 3)])
	check(ok_ground, "the rest on the ground (doors and the crossroads), each with the way it looks")


# --- Terrain presets ----------------------------------------------------------------------------

func _preset_terrain(def: Dictionary) -> ZoneTerrain:
	var flat: Array = []
	for m: Dictionary in def.modules:
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		flat.append(Rect2(p - half, half * 2.0))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	var t := ZoneTerrain.new()
	t.generate(def, flat)
	return t


## The salt pan's look (Captain, 2026-10-14, v0.3.1: "this terrain is an actual eye sore", a
## near-white pan brighter than the sky with nothing on it): the ground darker than the sky,
## the pan gently rolling but flat, a margin with mesas, scatter at the margins and round the
## pads with the open middle bare. `t` and `s` are a salt_flats zone's terrain and scatter.
func _check_salt_flats(t: ZoneTerrain, s: ZoneScatter) -> void:
	var glare := ZoneLevel.ground_glare("salt_flats")
	var palette: Dictionary = t.preset.palette
	var lum := Color(String(palette.grass)).srgb_to_linear().get_luminance()
	check(glare < 0.8 and lum < 0.35 and ZoneLevel.ground_glare("temperate") < 1.0,
		"salt flats: the pan is darker than the sky (ground %.2f of the horizon's brightness, under 0.8; crust luminance %.2f linear, under 0.35)" % [glare, lum])
	var inner := t.margin_m + 60.0
	var pan := Rect2(-t.size_m * 0.5 + inner, -t.size_m * 0.5 + inner, t.size_m - 2.0 * inner, t.size_m - 2.0 * inner)
	var r := t.height_range(pan)
	var points_up := 0
	var band := 0
	for j in range(0, t.points, 2):
		for i in range(0, t.points, 2):
			var x := t.v_x(i)
			var z := t.v_x(j)
			var edge := minf(t.size_m * 0.5 - absf(x), t.size_m * 0.5 - absf(z))
			if edge < t.margin_m:
				band += 1
				if t.height_at(x, z) > 6.0:
					points_up += 1
	var mesa_share := float(points_up) / maxf(band, 1.0)
	check(r.y - r.x > 0.5 and r.y - r.x < 8.0 and t.max_height > 6.0 and t.max_height < 30.0 and mesa_share > 0.01 and mesa_share < 0.35,
		"salt flats: the pan rolls gently (%.1f m from low to high) but is flat; mesas at the margin up to %.1f m (%.0f%% of the margin over 6 m)" % [r.y - r.x, t.max_height, mesa_share * 100.0])
	var at_margin := 0
	var in_open := 0
	for item in s.items:
		var p: Vector3 = item.pos
		if s._open_weight(p.x, p.z) == 0.0:
			in_open += 1
		elif minf(t.size_m * 0.5 - absf(p.x), t.size_m * 0.5 - absf(p.z)) < t.margin_m:
			at_margin += 1
	check(at_margin > 100 and in_open == 0,
		"salt flats: scatter at the margins and round the pads (%d of %d items in the margin band), none on the open pan" % [at_margin, s.total()])
	# The campaign's Salt flats zone itself (4 km): most of the pan open, its scatter and mesas.
	var def := MissionRegistry.zone_def("coast_hot")
	var started := Time.get_ticks_usec()
	var big := _preset_terrain(def)
	var terrain_ms := (Time.get_ticks_usec() - started) / 1000.0
	var bs := ZoneScatter.new()
	bs.generate(big, def)
	var bare := 0
	for item in bs.items:
		if bs._open_weight(item.pos.x, item.pos.z) == 0.0:
			bare += 1
	check(bs._open_share() < 0.6 and bare == 0 and bs.total() > 1000 and big.max_height > 6.0,
		"salt flats zone (%d m): %.0f%% of it has scatter (%d items), the rest open; mesas to %.1f m; heights in %.0f ms" % [int(big.size_m), bs._open_share() * 100.0, bs.total(), big.max_height, terrain_ms])
	bs.free()
	big.free()


func _test_presets() -> void:
	ZoneScatter.clear_cache(true)  # layouts from this run's code, not an older run's disk cache
	# Which preset a zone gets: explicit, name, region, default.
	var pick := func(d: Dictionary) -> String: return TerrainPresets.choose(d)
	check(pick.call({"name": "Salt flats", "region": "coast"}) == "salt_flats"
		and pick.call({"name": "Black Ridge hills", "region": "inland"}) == "rocky_ridge"
		and pick.call({"name": "Wadi farm", "region": "inland"}) == "desert_wadi"
		and pick.call({"name": "Gray-box compound", "region": "coast"}) == "coastal_lowland"
		and pick.call({"name": "Harbour yard", "region": "coast"}) == "coastal_lowland"
		and pick.call({"name": "Somewhere", "region": "inland"}) == "desert_wadi"
		and pick.call({"name": "Somewhere", "region": "coast", "terrain": "scrubland"}) == "scrubland"
		and pick.call({"name": "Somewhere"}) == "temperate",
		"terrain preset by zone: explicit, then name hints, then the region's default, then temperate")
	var expect := {"compound_01": "coastal_lowland", "wadi_farm": "desert_wadi", "harbour_yard": "coastal_lowland", "ridge_hot": "rocky_ridge", "coast_hot": "salt_flats", "city_hot": "city"}
	var mapped := true
	for id: String in expect:
		mapped = mapped and String(MissionRegistry.zone_def(id).get("terrain", "")) == expect[id]
	check(mapped, "the campaign's zones map to their presets (%s)" % [expect.keys().map(func(id: String) -> String: return "%s=%s" % [id, MissionRegistry.zone_def(id).get("terrain", "")])])
	check(String(ZoneDef.get_def("test").terrain) == "plain" and ZoneDef.normalize(ZoneDef.generate(5)).terrain == "temperate",
		"the test zone keeps the plain terrain; a generated zone with no name or region is temperate")
	# Every preset: same seed and preset, same ground and scatter; pads flat; scatter off the pads.
	var by_relief := {}
	for id: String in TerrainPresets.ids():
		var def := ZoneDef.generate(777, 1536.0).merged({"terrain": id}, true)
		def = ZoneDef.normalize(def)
		var a := _preset_terrain(def)
		var b := _preset_terrain(def)
		var other := _preset_terrain(ZoneDef.normalize(def.merged({"seed": 778}, true)))
		var sa := ZoneScatter.new()
		sa.generate(a, def)
		var sb := ZoneScatter.new()
		sb.generate(b, def)
		check(a.checksum() == b.checksum() and a.checksum() != other.checksum() and sa.checksum() == sb.checksum(),
			"preset %s: the same seed gives the same ground and scatter (%d items), another seed other ground" % [id, sa.total()])
		var flat_ok := true
		for pad: Array in a.pads:
			var r: Rect2 = (pad[0] as Rect2).grow(-ZoneTerrain.PAD_MARGIN_M)  # the footprint: the margin's edge is off the grid
			for p in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
				flat_ok = flat_ok and absf(a.height_at(p.x, p.y) - float(pad[1])) < 0.01
		check(flat_ok, "preset %s: every pad stays flat" % id)
		var clear := true
		var dry := true
		for item in sa.items:
			var p := Vector2(item.pos.x, item.pos.z)
			for pad: Array in a.pads:
				clear = clear and not (pad[0] as Rect2).has_point(p)
			dry = dry and (a.sea_side < 0 or a.height_at(p.x, p.y) > a.sea_level)
		check(clear and dry, "preset %s: no scatter on a pad or in the water" % id)
		var want: Dictionary = a.preset.get("scatter", {})
		check(want.is_empty() or sa.counts[ZoneScatter.Kind.SCRUB] + sa.counts[ZoneScatter.Kind.ROCK] > 0, "preset %s: has its scatter (%s)" % [id, sa.counts])
		by_relief[id] = a.max_height - a.min_height
		if a.margin_m > 0.0:
			# The pan inside its margin is what has to stay flat; the margin has the berm and mesas.
			var inner := a.margin_m + 60.0
			var r := a.height_range(Rect2(-a.size_m * 0.5 + inner, -a.size_m * 0.5 + inner, a.size_m - 2.0 * inner, a.size_m - 2.0 * inner))
			by_relief[id] = r.y - r.x
		if id == "salt_flats":
			_check_salt_flats(a, sa)
		if id == "coastal_lowland":
			var water := a.sea_side >= 0 and a.min_height < -3.0 and a.sea_depth_at(a.sea_rect().get_center().x, a.sea_rect().get_center().y) >= 0.0
			var far := Vector2(-a.sea_rect().get_center().x, -a.sea_rect().get_center().y) * 1.0
			check(water and a.sea_depth_at(far.x, far.y) == 0.0 and a.sea_rect().size.x > 0.0,
				"coastal_lowland: sea below 0 along one side (side %d, %.0f m wide), dry ground opposite" % [a.sea_side, a.sea_m])
		sa.free()
		sb.free()
		a.free()
		b.free()
		other.free()
	check(float(by_relief.salt_flats) < float(by_relief.rocky_ridge) * 0.25 and float(by_relief.rocky_ridge) > 25.0,
		"salt flats are flat, the ridge is not (relief %.1f m against %.1f m)" % [by_relief.salt_flats, by_relief.rocky_ridge])
	# A bigger zone gets more scatter; roads and a hot zone's pads stay clear.
	var small := ZoneDef.normalize(ZoneDef.generate(31, 1536.0).merged({"terrain": "desert_wadi"}, true))
	var big := ZoneDef.normalize(ZoneDef.generate(31, 1920.0).merged({"terrain": "desert_wadi"}, true))
	var ts := _preset_terrain(small)
	var tb := _preset_terrain(big)
	var ss := ZoneScatter.new()
	ss.generate(ts, small)
	var sb2 := ZoneScatter.new()
	sb2.generate(tb, big)
	check(sb2.total() > ss.total() * 1.3, "scatter grows with the zone's area (%d items in 1536 m, %d in 1920 m)" % [ss.total(), sb2.total()])
	var hot := ZoneDef.generate_hot(4409)
	hot["name"] = "Black Ridge hills"
	hot.erase("terrain")
	hot = ZoneDef.normalize(hot)
	var th := _preset_terrain(hot)
	var sh := ZoneScatter.new()
	sh.generate(th, hot)
	var off_roads := true
	for item in sh.items:
		for road: Array in hot.roads:
			off_roads = off_roads and Geometry2D.get_closest_point_to_segment(Vector2(item.pos.x, item.pos.z), Vector2(road[0][0], road[0][1]), Vector2(road[1][0], road[1][1])).distance_to(Vector2(item.pos.x, item.pos.z)) >= ZoneScatter.ROAD_KEEP_M - 0.01
	var steepest := _slope_off_cliffs(th)  # (its cliffs are rock faces on purpose: queue item 1.3, terrain_test)
	check(hot.terrain == "rocky_ridge" and off_roads and sh.total() > 1500 and sh.total() < 30000 and steepest < 42.0,  # (budget raised from 22000 for the scrub belts, Captain 2026-10-18)
		"hot zone on the ridge preset: %d scatter items off the roads, steepest %.0f degrees away from its %d cliffs" % [sh.total(), steepest, th.features.cliffs.size() if th.features else 0])
	ss.free()
	sb2.free()
	sh.free()
	ts.free()
	tb.free()
	th.free()
	_test_woods()


## The steepest slope in `t`'s grid (degrees) away from its cliffs (ZoneFeatures: within 12 m of
## one's footprint), ZoneTerrain.max_slope_deg's measure.
static func _slope_off_cliffs(t: ZoneTerrain) -> float:
	var worst := 0.0
	var limit := tan(deg_to_rad(42.0)) * ZoneTerrain.CELL_M  # only steep cells ask where the cliffs are
	for j in t.points - 1:
		for i in t.points - 1:
			var h := t._h(i, j)
			var rise := maxf(absf(t._h(i + 1, j) - h), absf(t._h(i, j + 1) - h))
			if rise <= worst:
				continue
			if rise > limit and t.features:
				var p := Vector2(t.v_x(i), t.v_x(j))
				if t.features.cliffs.any(func(c: Dictionary) -> bool: return t.features._cliff_reach(c, p) < 12.0):
					continue
			worst = rise
	return rad_to_deg(atan(worst / ZoneTerrain.CELL_M))


## Round 4 (Captain, 2026-10-14: "we need copses and groves and such. the terrain is too empty.
## we'll use caching for performance if needed"): trees in clusters, the layout the same twice,
## cached in memory and on disk, nothing on pads, roads, insertion or extraction points, and a
## wood hides a standing man; far stand-ins.
## Every coastal zone's ship (the LHD, Lhd.ship_frame) anchored offshore. Captain, 2026-10-14:
## on harbour_yard it lay a few metres off the sand, "way too close to shore". Every ship's
## footprint over water deeper than its draft and at least Lhd.OFFSHORE_M out from the
## shoreline (none is moored at a quay yet), and its hull's collision no deeper than its draft.
## The zones: every campaign zone, every data/zones.json zone, and each sea preset on a few seeds.
func _test_ship_placement() -> void:
	print("Ships anchored offshore")
	var defs := {}
	for z: Dictionary in MissionRegistry.zones():
		var d := MissionRegistry.zone_def(String(z.zone_id))
		if not d.is_empty():
			defs[String(z.zone_id)] = d
	for id: String in ZoneDef.ids():
		defs["zones.json:" + id] = ZoneDef.get_def(id)
	for preset: String in TerrainPresets.ids():
		if not (TerrainPresets.get_preset(preset).get("sea", {}) as Dictionary).is_empty():
			for seed_value: int in [777, 3301, 7712]:
				defs["%s#%d" % [preset, seed_value]] = ZoneDef.normalize(ZoneDef.generate(seed_value, 1536.0).merged({"terrain": preset}, true))
	var coastal: Array[String] = []
	for key: String in defs:
		var def: Dictionary = defs[key]
		var t := _preset_terrain(def)
		if not t.has_coast():
			t.free()
			continue
		coastal.append(key)
		var frame := Lhd.ship_frame(t, def.get("coast", {}))
		var draft := float(frame.draft)
		var nearest := INF
		var shallow := INF
		var wet := true
		for p in Lhd.footprint(frame.transform, float(frame.length), float(frame.beam)):
			wet = wet and t.water_height(p.x, p.z) == t.sea_level
			nearest = minf(nearest, -t.shore_distance(p.x, p.z))
			shallow = minf(shallow, t.sea_level - t.height_at(p.x, p.z))
		check(wet and shallow > draft and nearest >= Lhd.OFFSHORE_M - 0.01 and absf((frame.transform as Transform3D).origin.y - t.sea_level) < 0.01,
			"%s: the ship is afloat offshore (%.0f m off the shore at its nearest, water %.1f m deep under a %.1f m draft)" % [key, nearest, shallow, draft])
		var art := LhdArt.build(float(frame.length), float(frame.beam), LhdArt.DECK_M, draft)
		var keel := INF
		for shape in art.get_node(^"Hull").get_children():
			var c := shape as CollisionShape3D
			keel = minf(keel, c.position.y - (c.shape as BoxShape3D).size.y * 0.5)
		check(absf(keel + draft) < 0.01, "%s: the hull's collision ends at the keel (%.2f m, draft %.2f m)" % [key, keel, draft])
		art.free()
		t.free()
	check(coastal.has("harbour_yard") and coastal.has("zones.json:coast"), "harbour_yard and the coast zone are coastal (%s)" % [coastal])


func _test_woods() -> void:
	ZoneScatter.clear_cache(true)
	var hot := ZoneDef.generate_hot(4409)
	hot["terrain"] = "temperate"
	hot = ZoneDef.normalize(hot)
	var t := _preset_terrain(hot)
	var started := Time.get_ticks_usec()
	var a := ZoneScatter.new()
	a.generate(t, hot)
	var fresh_ms := (Time.get_ticks_usec() - started) / 1000.0
	ZoneScatter.clear_cache()  # memory only: the same layout made again, then off disk
	ZoneScatter.clear_cache(true)
	var b := ZoneScatter.new()
	b.generate(t, hot)
	check(a.cache_source == "generated" and b.cache_source == "generated" and a.checksum() == b.checksum() and a.total() == b.total(),
		"woods: the same zone lays out the same twice (%d items, %s, %.0f ms)" % [a.total(), a.counts, fresh_ms])
	started = Time.get_ticks_usec()
	var c := ZoneScatter.new()
	c.generate(t, hot)
	var memory_ms := (Time.get_ticks_usec() - started) / 1000.0
	ZoneScatter.clear_cache()
	started = Time.get_ticks_usec()
	var d := ZoneScatter.new()
	d.generate(t, hot)
	var disk_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(c.cache_source == "memory" and c.checksum() == a.checksum() and d.cache_source == "disk" and d.checksum() == a.checksum() and d.solid_count == a.solid_count,
		"woods: the layout comes from memory the second time (%.1f ms), from disk after memory is cleared (%.0f ms; fresh %.0f ms)" % [memory_ms, disk_ms, fresh_ms])
	# Clusters: at least half the trees have 5 or more others within 25 m.
	var grid := {}
	var trees: Array[Vector2] = []
	for item in a.items:
		if int(item.kind) == ZoneScatter.Kind.TREE:
			var q := Vector2(item.pos.x, item.pos.z)
			trees.append(q)
			var g := Vector2i(floori(q.x / 25.0), floori(q.y / 25.0))
			if not grid.has(g):
				grid[g] = []
			(grid[g] as Array).append(q)
	var clustered := 0
	for q in trees:
		var g := Vector2i(floori(q.x / 25.0), floori(q.y / 25.0))
		var n := -1
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for o: Vector2 in grid.get(g + Vector2i(dx, dz), []):
					if o.distance_to(q) < 25.0:
						n += 1
		if n >= 5:
			clustered += 1
	check(trees.size() > 500 and clustered * 2 >= trees.size() and a.counts[ZoneScatter.Kind.THICKET] > 0,
		"woods: trees grow in clusters (%d of %d with 5+ others within 25 m; %d thickets)" % [clustered, trees.size(), a.counts[ZoneScatter.Kind.THICKET]])
	# Nothing on the pads (modules, insertion and extraction points) or the roads.
	var clear := true
	for item in a.items:
		var q := Vector2(item.pos.x, item.pos.z)
		for pad: Array in t.pads:
			clear = clear and not (pad[0] as Rect2).has_point(q)
		for p: Array in hot.insertion + hot.extraction:
			clear = clear and q.distance_to(Vector2(float(p[0]), float(p[1]))) > 8.0
		for road: Array in hot.roads:
			clear = clear and Geometry2D.get_closest_point_to_segment(q, Vector2(road[0][0], road[0][1]), Vector2(road[1][0], road[1][1])).distance_to(q) >= ZoneScatter.ROAD_KEEP_M - 0.01
	check(clear, "woods: nothing on a pad, an insertion or extraction point, or a road")
	# A standing man's eye line (1.6 m above the ground all along, in 5 m pieces) 40 m across a
	# wood or copse (a tree with 20+ others within 25 m) is hidden, in four directions, at most
	# spots (clearings and edges let some through).
	var lines := 0
	var hidden := 0
	for k in range(0, trees.size(), 97):
		var q: Vector2 = trees[k]
		var near := -1
		for o: Vector2 in trees:
			if o.distance_squared_to(q) < 625.0:
				near += 1
		if near < 20:
			continue
		for ang: float in [0.0, PI * 0.25, PI * 0.5, PI * 0.75]:
			var dir := Vector2.from_angle(ang)
			var through := 0.0
			for seg in 8:
				var p0 := q + dir * (-20.0 + seg * 5.0)
				var p1 := q + dir * (-15.0 + seg * 5.0)
				through += a.foliage_between(Vector3(p0.x, t.height_at(p0.x, p0.y) + 1.6, p0.y), Vector3(p1.x, t.height_at(p1.x, p1.y) + 1.6, p1.y))
			lines += 1
			if through >= Spotting.FOLIAGE_OPAQUE_M:
				hidden += 1
	check(lines >= 40 and hidden >= lines * 0.65, "woods: %d of %d eye-height lines 40 m through woods and copses are hidden (%.1f m of foliage or more)" % [hidden, lines, Spotting.FOLIAGE_OPAQUE_M])
	# Captain, 2026-10-14: the copses-as-cover layout is the experimental forest's only; the
	# normal presets keep round 4's copses and caps (their woods' perf pass is queued).
	check(not a._cover and a._cap_trees == ZoneScatter.ROUND4_CAP_TREES and a._cap_thickets == ZoneScatter.ROUND4_CAP_THICKETS and a._cap_solid == ZoneScatter.ROUND4_CAP_SOLID
		and a.counts[ZoneScatter.Kind.TREE] <= ZoneScatter.ROUND4_CAP_TREES,
		"woods: temperate keeps round 4's copses and caps (%d trees, %d copses)" % [a.counts[ZoneScatter.Kind.TREE], a.copse_sites.size()])
	# Far stand-ins: one blob per 24 m square of trees, one MultiMesh per cell (built with the visuals).
	a.build_visuals()
	var far := a.far_counts()
	var squares := {}  # a square split by a cell's edge is a blob each side
	for q in trees:
		var cell := Vector2i(floori((q.x + t.size_m * 0.5) / ZoneScatter.CELL_M), floori((q.y + t.size_m * 0.5) / ZoneScatter.CELL_M))
		var g := Vector2i(floori((q.x + t.size_m * 0.5) / ZoneScatter.FAR_GROUP_M), floori((q.y + t.size_m * 0.5) / ZoneScatter.FAR_GROUP_M))
		squares[[cell, g]] = true
	check(int(far.blobs) == squares.size() and int(far.cells) > 0 and int(far.cells) <= a._cells.size(),
		"woods: far stand-ins, %d canopy blobs in %d cells for %d trees" % [far.blobs, far.cells, trees.size()])
	var built := a.build_near(Vector3.ZERO, 2)
	check(built == 2 and a._entry.visual.size() == 2, "woods: built cells' meshes are kept in the cache (%d)" % a._entry.visual.size())
	for sc in [a, b, c, d]:
		sc.free()
	t.free()
	ZoneScatter.clear_cache()  # the big layouts out of memory before the frame-time checks
	_test_forest_copses()


## The Experimental forest (Captain, 2026-10-14: "include experimental forest mission like we
## dev'd"; data/zones.json forest_experimental, its own preset with "copse_cover"): its copses
## are cover (_test_copse_cover), laid out fresh twice the same.
func _test_forest_copses() -> void:
	var def := ZoneDef.get_def(Menu.FOREST_ZONE)
	check(String(def.get("terrain", "")) == "forest_experimental" and (def.modules as Array).size() == 3,
		"forest: the Experimental forest zone uses the forest_experimental preset (%s, %d modules, %.0f m)" % [def.get("terrain", "?"), (def.get("modules", []) as Array).size(), float(def.get("size_m", 0))])
	var t := _preset_terrain(def)
	ZoneScatter.clear_cache(true)
	var a := ZoneScatter.new()
	a.generate(t, def)
	ZoneScatter.clear_cache(true)
	var b := ZoneScatter.new()
	b.generate(t, def)
	var trees: Array[Vector2] = []
	for item in a.items:
		if int(item.kind) == ZoneScatter.Kind.TREE:
			trees.append(Vector2(item.pos.x, item.pos.z))
	check(a._cover and a._cap_trees == ZoneScatter.CAP_TREES and a.checksum() == b.checksum() and trees.size() > 2000,
		"forest: copses-as-cover layout (%d trees, %d thickets, %d solid; %s)" % [trees.size(), a.counts[ZoneScatter.Kind.THICKET], a.solid_count, a.cache_source])
	_test_copse_cover(a, b, t, trees)
	a.free()
	b.free()
	t.free()
	ZoneScatter.clear_cache()


## Copses are cover (Captain, 2026-10-14, v0.4.0: "the copses of trees are too small and spread
## out to be cover"): every copse of the fresh layout `a` (its copse_sites; `b` the same zone
## laid out again) holds 20-60 trees (Proposed; a few cut short by a road, a pad or the tree
## cap) about 3-3.5 m apart in a compact blob, eye-height lines (1.6 m) through its middle meet
## at least FOLIAGE_OPAQUE_M of foliage at most angles, and a man standing at its middle is
## hidden from 50 m out from most directions.
func _test_copse_cover(a: ZoneScatter, b: ZoneScatter, t: ZoneTerrain, trees: Array[Vector2]) -> void:
	var copses := 0
	var in_bounds := 0
	var tree_sum := 0
	var nn_sum := 0.0
	var nn_n := 0
	var lines := 0
	var blocked := 0
	var views := 0
	var hidden := 0
	var most_r := 0.0
	for site: Dictionary in a.copse_sites:
		if site.grove or int(site.trees) == 0:
			continue
		copses += 1
		var n := int(site.trees)
		tree_sum += n
		if n >= 20 and n <= 60:
			in_bounds += 1
		var c: Vector2 = site.centre
		var r := float(site.r)
		most_r = maxf(most_r, r)
		var mine: Array[Vector2] = []
		for q in trees:
			if q.distance_to(c) <= r + 0.5:
				mine.append(q)
		for q in mine:
			var best := INF
			for o in mine:
				if o != q:
					best = minf(best, o.distance_to(q))
			if best < INF:
				nn_sum += best
				nn_n += 1
		for k in 8:
			var dir := Vector2.from_angle(k * PI / 8.0)
			lines += 1
			if _eye_foliage(a, t, c - dir * (r + 12.0), c + dir * (r + 12.0)) >= Spotting.FOLIAGE_OPAQUE_M:
				blocked += 1
		for k in 12:
			var dir := Vector2.from_angle(k * TAU / 12.0)
			views += 1
			if _eye_foliage(a, t, c + dir * 50.0, c) >= Spotting.FOLIAGE_OPAQUE_M:
				hidden += 1
	var nn := nn_sum / maxi(nn_n, 1)
	# Captain, 2026-10-16: COPSE_SPREAD 1.9 -> 2.6 ("sprawling more") widened a copse's radius
	# without changing its tree count, so trees sit a bit further apart on average (was 3-3.5,
	# now 3-3.8); the upper bound here follows that, not a regression.
	check(copses >= 20 and in_bounds >= copses * 0.8 and tree_sum <= copses * 60 and most_r <= ZoneScatter.COPSE_SPREAD * sqrt(60.0) + 2.01 and nn >= 2.8 and nn <= 3.8,
		"copses: %d copses, %d with 20-60 trees (%.1f a copse), at most %.1f m in radius, trees %.2f m from the nearest (Proposed 3-3.8)" % [copses, in_bounds, float(tree_sum) / maxi(copses, 1), most_r, nn])
	check(lines > 0 and blocked >= lines * 0.85,
		"copses: %d of %d eye-height lines through a copse's middle meet %.1f m of foliage or more" % [blocked, lines, Spotting.FOLIAGE_OPAQUE_M])
	check(views > 0 and hidden >= views * 0.8,
		"copses: a man standing in a copse's middle is hidden from 50 m out on %d of %d lines" % [hidden, views])
	check(a.copse_sites.size() > 0 and str(a.copse_sites) == str(b.copse_sites),
		"copses: the same zone lays its copses out the same twice (%d)" % a.copse_sites.size())


## Metres of foliage on the eye-height line (1.6 m above the ground all along, in 5 m pieces)
## from `p0` to `p1`.
func _eye_foliage(sc: ZoneScatter, t: ZoneTerrain, p0: Vector2, p1: Vector2) -> float:
	var pieces := maxi(1, ceili(p0.distance_to(p1) / 5.0))
	var sum := 0.0
	for k in pieces:
		var u := p0.lerp(p1, float(k) / pieces)
		var v := p0.lerp(p1, float(k + 1) / pieces)
		sum += sc.foliage_between(Vector3(u.x, t.height_at(u.x, u.y) + 1.6, u.y), Vector3(v.x, t.height_at(v.x, v.y) + 1.6, v.y))
	return sum
