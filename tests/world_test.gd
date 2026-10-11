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
const LIVE_MARK := Vector3(0.0, 1.2, 19.7)

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
	check(level.modules().size() == 5 and level.get_module("compound").type == "compound" and level.get_module("village_e").type == "village",
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
	var proxy_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8, 1.3, 30) + _origin("compound"), Vector3(8, 1.3, -30) + _origin("compound"), 1))
	check(not proxy_hit.is_empty() and absf(proxy_hit.position.z - _origin("compound").z - 20.0) < 0.2,
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
	# Out and back in: rebuilt from its base boxes and its log.
	player.global_position = level.ground_point(m.global_position + Vector3(0, 0, 500))
	await _wait_for(func() -> bool: return not m.is_streamed(), 3.0)
	check(not m.is_streamed() and level.edit_logs().compound.size() == mine.size() + 1, "500 m away it streams out; its log stays")
	m = await _go_to_module("compound")
	check(m.voxel_world.holes_through(m.to_global(SHED_WALL)) == 1 and m.voxel_world.marks_near(m.to_global(Vector3(-2.95, 1.35, -4.0)), 0.05) == 1,
		"back again: rebuilt with the bullet holes and the mark")


## Soldiers in modules take rounds as in the compound: through a plank wall, and through a
## doorway into a room.
func _test_shot_in_module() -> void:
	print("Shooting soldiers in modules")
	var m := await _go_to_module("village_e", Vector3(-14, 0, 30))
	var victim := level.spawn_soldier({"name": "ShackMan", "faction": "hostile", "variant": "urban", "pos": m.to_global(Vector3(-12.5, 0.1, 9.0)),
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
	var through_door := _fire(m.to_global(Vector3(11.0, 0.6, 2.0)), m.to_global(Vector3(11.0, 0.6, -9.0)), &"m4a1")
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
	var gate := m.to_global(Vector3(0, 0, 20))
	var via_gate := false
	for p in path:
		via_gate = via_gate or Vector2(p.x - gate.x, p.z - gate.z).length() < 2.5
	check(via_gate, "through the compound's gate")
	level.squad_for(&"friendly").give_order(player, Squad.Order.MOVE, target, PackedStringArray(["Walker"]))
	var arrived := await _wait_for(func() -> bool: return Vector2(walker.global_position.x - target.x, walker.global_position.z - target.z).length() < 1.5, 60.0)
	check(arrived, "the walker gets there on foot (%.1f m left)" % Vector2(walker.global_position.x - target.x, walker.global_position.z - target.z).length())
	walker.queue_free()


## Saved, then hosted again from the save: module edits and bodies come back.
func _test_reload() -> void:
	print("Saving and reloading the zone")
	GameState.save_zone()
	var saved := GameState.voxel_edits.size()
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
	m.voxel_world.server_mark(m.to_global(LIVE_MARK), Vector3.BACK, VoxelWorld.Mat.CONCRETE)
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
	return {"terrain": level.terrain.checksum(), "modules": modules, "map": level.map_area()}


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
