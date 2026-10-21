extends Node
## Voxel smoke (SmokeCloud, S5 in docs/ChrisPlan_handoff.md): hosts the compound, builds test
## rooms of its own east of it (static boxes on the world layer, a ceiling each) and checks that
## a cloud fills a closed room and stops at its walls; goes out through a door; fills the
## compound's own voxel shed and comes out of its doorway; blocks sight only where it's dense (a
## room's smoke blocks a look through its door once it fills the door); thins over time and is
## gone by its end; drifts with the wind; takes a hole from a frag (through the level's blast
## hook) that refills from the rim; parts along a round's line for a moment; keeps its colour
## (purple, for extraction); grows the same from the same seed, for a late joiner (age, seed and
## events) and after an event that came late. Last, the cost: CLOUDS clouds at once within the
## step budget, and sight checks through them.
##   <voxel godot exe> --headless --path . res://tests/smokecloud_test.tscn

## Open ground west of the compound (its walls are at +-20 m, the ground pad +-80 m).
const FIELD := Vector3(-55, 0.1, 0)
## Proposed budgets: CLOUDS clouds growing at once cost at most STEP_MS_PER_S of steps a second
## all told, 95% of physics ticks at most TICK_P95_MS of it (the shared step budget,
## SmokeCloud.BUDGET_USEC, plus a step) and none more than TICK_MS, and a sight check through
## them at most SIGHT_US on average. Locally (R0339, R0343, on a machine shared with other runs):
## 71-78 ms a second, worst tick 8.4-11.7 ms (one growing step: ~140 rays and ~450 cells still
## changing), 29 us a sight check. Room left for CI's slower runners.
const CLOUDS := 8
const STEP_MS_PER_S := 160.0
const TICK_P95_MS := 6.0
const TICK_MS := 30.0
const SIGHT_US := 80.0

var level: CompoundLevel
var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_smokecloud" + tag  # never touch a real save
	Campaign.campaign_id = "test_smokecloud_campaign" + tag
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func() -> void:
		print("SMOKECLOUD TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var waited := 0
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_meshed():
		await get_tree().process_frame
		waited += 1
		if waited > 3000:
			break
	var player := level.players.get_node(^"1") as Soldier
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 70)
	SmokeCloud.wind_override = Vector3.ZERO
	await _physics(5)
	await _test_closed_room()
	await _test_door_room()
	await _test_voxel_shed()
	await _test_sight()
	await _test_thinning()
	await _test_wind()
	await _test_blast()
	await _test_gunfire()
	await _test_colour()
	await _test_same_seed()
	await _test_cost()
	SmokeCloud.wind_override = null
	GameState.delete_save()
	print("SMOKECLOUD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A cloud as the level spawns one (local call), driven by the test (run_to), not by the clock.
func _cloud(pos: Vector3, cloud_seed := 0, colour := "white", driven := true) -> SmokeCloud:
	var s := cloud_seed if cloud_seed != 0 else SmokeCloud.seed_at(pos, colour)
	level.spawn_smoke(pos, colour, 0.0, s, SmokeCloud.wind_here(level))
	var cloud := level.get_node(NodePath(SmokeCloud.node_name(s))) as SmokeCloud
	cloud.set_physics_process(not driven)
	return cloud


func _clear() -> void:
	for cloud in SmokeCloud.active.duplicate():
		if is_instance_valid(cloud):
			cloud.queue_free()
	await get_tree().process_frame


func _box(from: Vector3, to: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = to - from
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var look := BoxMesh.new()
	look.size = to - from
	mesh.mesh = look
	body.add_child(mesh)
	level.add_child(body)
	body.global_position = (from + to) * 0.5


## A room on the ground: its inside from `lo` (a floor corner), `size`, 0.2 m walls and a
## ceiling; with `door`, a doorway 1 m wide and 2 m high in the middle of its +z wall.
func _room(lo: Vector3, size: Vector3, door: bool) -> AABB:
	var t := 0.2
	var hi := lo + size
	_box(Vector3(lo.x - t, 0, lo.z - t), Vector3(hi.x + t, hi.y, lo.z))
	_box(Vector3(lo.x - t, 0, lo.z), Vector3(lo.x, hi.y, hi.z))
	_box(Vector3(hi.x, 0, lo.z), Vector3(hi.x + t, hi.y, hi.z))
	if door:
		var mid := (lo.x + hi.x) * 0.5
		_box(Vector3(lo.x - t, 0, hi.z), Vector3(mid - 0.5, hi.y, hi.z + t))
		_box(Vector3(mid + 0.5, 0, hi.z), Vector3(hi.x + t, hi.y, hi.z + t))
		_box(Vector3(mid - 0.5, 2.0, hi.z), Vector3(mid + 0.5, hi.y, hi.z + t))
	else:
		_box(Vector3(lo.x - t, 0, hi.z), Vector3(hi.x + t, hi.y, hi.z + t))
	_box(Vector3(lo.x - t, hi.y, lo.z - t), Vector3(hi.x + t, hi.y + t, hi.z + t))
	return AABB(lo, size)


## How many of a cloud's grid cells have their centres inside `box` (not on its faces: a wall's).
func _grid_cells_in(cloud: SmokeCloud, box: AABB) -> int:
	var origin := cloud.global_position + Vector3(0, SmokeCloud.BASE_UP, 0)
	box = box.grow(-0.02)
	var n := 0
	for x in range(-SmokeCloud.REACH_CELLS, SmokeCloud.REACH_CELLS + 1):
		for y in range(-SmokeCloud.DOWN_CELLS, SmokeCloud.UP_CELLS + 1):
			for z in range(-SmokeCloud.REACH_CELLS, SmokeCloud.REACH_CELLS + 1):
				if box.has_point(origin + Vector3(x, y, z) * SmokeCloud.CELL):
					n += 1
	return n


func _count_in(cloud: SmokeCloud, box: AABB) -> int:
	var n := 0
	for p in cloud.cell_points():
		if box.has_point(p):
			n += 1
	return n


func _test_closed_room() -> void:
	print("A closed room")
	var room := _room(Vector3(50, 0, -30), Vector3(4, 2.6, 4), false)
	await _physics(3)
	var cloud := _cloud(Vector3(52, 0.1, -28))
	cloud.run_to(12.0)
	var room_cells := _grid_cells_in(cloud, room)
	var inside := _count_in(cloud, room)
	var outside := cloud.cell_count() - inside
	check(inside >= room_cells * 0.95 and outside == 0,
		"smoke in a closed room fills it (%d of its %d cells) and stops at its walls, floor and ceiling (%d cells outside)" % [inside, room_cells, outside])
	check(cloud.density_at(Vector3(50.3, 2.2, -29.7)) > 0.5 and cloud.density_at(Vector3(53.7, 0.4, -26.3)) > 0.5,
		"right into its corners, top and bottom (%.2f, %.2f)" % [cloud.density_at(Vector3(50.3, 2.2, -29.7)), cloud.density_at(Vector3(53.7, 0.4, -26.3))])
	check(not SmokeCloud.blocks(Vector3(47, 1.5, -33), Vector3(57, 1.5, -33)), "a look past the room's outside isn't blocked")
	await _clear()


func _test_door_room() -> void:
	print("A room with a door")
	var room := _room(Vector3(50, 0, 0), Vector3(4, 2.6, 4), true)  # its doorway at z 4, x 51.5..52.5
	await _physics(3)
	var cloud := _cloud(Vector3(52, 0.1, 1.5))
	cloud.run_to(8.0)
	var room_cells := _grid_cells_in(cloud, room)
	var inside := _count_in(cloud, room)
	var front := _count_in(cloud, AABB(Vector3(40, -2, 4.2), Vector3(24, 8, 20)))
	var back := _count_in(cloud, AABB(Vector3(40, -2, -20), Vector3(24, 8, 19.8)))
	print("  door room: %d cells, %d of the room's %d inside, %d in front, %d behind" % [cloud.cell_count(), inside, room_cells, front, back])
	check(inside >= room_cells * 0.9, "the room fills (%d of %d cells)" % [inside, room_cells])
	check(front > 200 and front > back * 5, "and the rest goes out through the door (%d cells in front of it, %d behind the room)" % [front, back])
	var at_door := cloud.density_at(Vector3(52, 1.0, 4.7))
	var behind := cloud.density_at(Vector3(52, 1.0, -0.7))
	check(at_door > 0.6 and behind < at_door * 0.5, "thick just outside the doorway (%.2f), not behind the back wall (%.2f)" % [at_door, behind])
	await _clear()


## The compound's lean-to shed (CompoundLevel.SHED): voxel plank walls, a sheet-metal roof, a
## doorway in its west wall at x 16, z -9.6..-8.4, 2 m high.
func _test_voxel_shed() -> void:
	print("The compound's voxel shed")
	var cloud := _cloud(Vector3(18.5, 0.1, -9.0))
	cloud.run_to(8.0)
	var shed := AABB(Vector3(16.1, 0, -10.9), Vector3(3.6, 2.4, 3.8))
	var inside := _count_in(cloud, shed)
	var shed_cells := _grid_cells_in(cloud, shed)
	var corner := cloud.density_at(Vector3(19.4, 1.5, -10.6))
	var out_door := cloud.density_at(Vector3(15.5, 1.0, -9.0))
	print("  shed: %d cells, %d of its %d inside, corner %.2f, out of the door %.2f" % [cloud.cell_count(), inside, shed_cells, corner, out_door])
	check(inside >= shed_cells * 0.85 and corner > 0.5, "smoke in the voxel shed fills it (%d of %d cells, its far corner %.2f)" % [inside, shed_cells, corner])
	check(out_door > 0.5, "and comes out of its doorway (%.2f)" % out_door)
	await _clear()


func _test_sight() -> void:
	print("Sight")
	var cloud := _cloud(FIELD)
	cloud.run_to(6.0)
	var c := FIELD
	check(SmokeCloud.blocks(c + Vector3(-8, 1.4, 0), c + Vector3(8, 1.4, 0)), "a sight line through the cloud's middle is blocked (depth %.1f)" % SmokeCloud.depth_between(c + Vector3(-8, 1.4, 0), c + Vector3(8, 1.4, 0)))
	check(not SmokeCloud.blocks(c + Vector3(-8, 1.4, 12), c + Vector3(8, 1.4, 12)), "one well clear of it isn't")
	# Out from the middle the lines get thinner, and the cloud's outer layer is thin: half a metre
	# of it doesn't block a look, where half a metre of its body does.
	var last := INF
	var falls := true
	for i in 40:
		var off := 0.25 * i
		var depth := SmokeCloud.depth_between(c + Vector3(-12, 1.4, off), c + Vector3(12, 1.4, off))
		if depth > last + 2.0:
			falls = false
		last = depth
	check(falls, "the smoke on a line thins out from the cloud's middle to its edge")
	var edge := c + Vector3(0, 1.4, 0)
	while cloud.density_at(edge + Vector3(0, 0, 0.5)) > 0.0:
		edge.z += 0.5
	var outside := edge + Vector3(0, 0, 0.75)
	var thin := SmokeCloud.depth_between(outside, edge - Vector3(0, 0, 0.1))
	var thick := SmokeCloud.depth_between(c + Vector3(0, 1.4, 0.75), c + Vector3(0, 1.4, -0.1))
	check(cloud.density_at(edge) < 0.5 and not SmokeCloud.blocks(outside, edge - Vector3(0, 0, 0.1)),
		"its outer layer is thin (%.2f): a look into it from outside isn't blocked (depth %.2f)" % [cloud.density_at(edge), thin])
	check(SmokeCloud.blocks(c + Vector3(0, 1.4, 0.75), c + Vector3(0, 1.4, -0.1)), "as far through its body is (depth %.1f)" % thick)
	await _clear()
	# A room filling from its back corner: a look in through its doorway is blocked only once the
	# smoke fills the doorway.
	_room(Vector3(50, 0, 25), Vector3(4, 2.6, 4), true)  # its doorway at z 29, x 51.5..52.5
	await _physics(3)
	var room := _cloud(Vector3(50.4, 0.1, 25.4))
	room.run_to(0.75)
	var eye := Vector3(52.2, 1.4, 34)
	var into := Vector3(52.0, 1.2, 28.6)
	check(not SmokeCloud.blocks(eye, into), "a look in through the doorway while the smoke is still at the back isn't blocked (depth %.2f)" % SmokeCloud.depth_between(eye, into))
	room.run_to(8.0)
	check(SmokeCloud.blocks(eye, into), "once the smoke fills the doorway it is (depth %.1f)" % SmokeCloud.depth_between(eye, into))
	await _clear()


func _test_thinning() -> void:
	print("Thinning")
	var cloud := _cloud(FIELD + Vector3(0, 0, 30))
	var mid := FIELD + Vector3(0, 0.9, 30)
	cloud.run_to(10.0)
	var full := cloud.density_at(mid)
	var total_full := cloud.total_smoke()
	cloud.run_to(25.0)
	var later := cloud.density_at(mid)
	cloud.run_to(29.5)
	var end := cloud.total_smoke()
	print("  thinning: middle %.2f at 10 s, %.2f at 25 s; all of it %d at 10 s, %d at 29.5 s" % [full, later, total_full, end])
	check(full > 0.9 and later < full - 0.15, "it thins after it burns out (%.2f -> %.2f in the middle)" % [full, later])
	check(end < total_full * 0.2, "and has nearly gone by its end (%d of %d)" % [end, total_full])
	cloud.set_physics_process(true)
	cloud.age = SmokeCloud.DURATION_S - 0.05
	await _physics(10)
	check(not is_instance_valid(cloud) or cloud.is_queued_for_deletion(), "then it goes")
	await _clear()


func _test_wind() -> void:
	print("Wind")
	var still := _cloud(FIELD + Vector3(0, 0, -30))
	still.run_to(20.0)
	var still_off := still.centroid() - still.global_position
	await _clear()
	SmokeCloud.wind_override = Vector3(1.5, 0, 0)
	var cloud := _cloud(FIELD + Vector3(0, 0, -30))
	cloud.run_to(8.0)
	var early := cloud.centroid().x - cloud.global_position.x
	cloud.run_to(20.0)
	var late := cloud.centroid() - cloud.global_position
	SmokeCloud.wind_override = Vector3.ZERO
	print("  wind: still cloud's middle off by %s; in 1.5 m/s of wind +x: %.2f m at 8 s, %s at 20 s" % [still_off, early, late])
	check(absf(still_off.x) < 0.5 and absf(still_off.z) < 0.5, "with no wind the cloud sits round the grenade")
	check(early > 0.4 and late.x > early + 1.0 and absf(late.z) < 1.0, "in a wind it leans downwind and drifts on (%.1f m, then %.1f m)" % [early, late.x])
	await _clear()


func _test_blast() -> void:
	print("A blast")
	var at := FIELD + Vector3(0, 0, -60)
	var cloud := _cloud(at)
	cloud.run_to(6.0)
	var bang := at + Vector3(1.0, 0, 0.5)
	var mid := bang + Vector3(0, 0.8, 0)
	var rim := bang + Vector3(2.0, 0.8, 0.5)
	var before := cloud.density_at(mid)
	Throwables.server_detonate(level, "frag", bang)  # through CompoundLevel.server_blast
	check(cloud.events.size() == 1 and int(cloud.events[0][1]) == SmokeCloud.BLAST, "a frag in the smoke makes a blast event in it")
	cloud.run_to(6.0 + 3.0 / SmokeCloud.HZ)
	var holed := cloud.density_at(mid)
	check(before > 0.8 and holed < 0.2, "it pushes a hole in the smoke (%.2f -> %.2f)" % [before, holed])
	cloud.run_to(7.25)
	var mid_soon := cloud.density_at(mid)
	var rim_soon := cloud.density_at(rim)
	check(rim_soon > mid_soon, "that refills from its rim in (rim %.2f, middle %.2f)" % [rim_soon, mid_soon])
	cloud.run_to(10.0)
	check(cloud.density_at(mid) > 0.8, "and is full again (%.2f)" % cloud.density_at(mid))
	await _clear()


func _test_gunfire() -> void:
	print("Gunfire")
	var at := FIELD + Vector3(0, 0, 60)
	var cloud := _cloud(at)
	cloud.run_to(6.0)
	var from := at + Vector3(-10, 1.3, 0.2)
	var to := at + Vector3(10, 1.3, -0.3)
	check(SmokeCloud.blocks(from, to), "a line through the smoke is blocked")
	level.show_tracer(from, Vector3.ZERO, &"", to, false)  # a round along it (the host's tracer, straight)
	cloud.run_to(6.0 + 3.0 / SmokeCloud.HZ)
	check(not SmokeCloud.blocks(from, to), "a round through it parts it along its line for a moment (depth %.2f)" % SmokeCloud.depth_between(from, to))
	cloud.run_to(8.0)
	check(SmokeCloud.blocks(from, to), "then it closes again (depth %.1f)" % SmokeCloud.depth_between(from, to))
	await _clear()


func _test_colour() -> void:
	print("Colour")
	var at := Vector3(-60, 0.1, 40)
	Throwables.server_detonate(level, "smoke", at, &"smoke_purple")
	await _physics(2)
	var purple := SmokeCloud.clouds_of("purple")
	check(purple.size() == 1 and purple[0].global_position.distance_to(at) < 0.01, "a purple smoke grenade makes a purple cloud where it went off (extraction's)")
	if purple.size() == 1:
		var shown := purple[0].display_colour()
		var want: Color = SmokeCloud.COLOURS["purple"]
		check(absf(shown.r - want.r) < 0.01 and absf(shown.g - want.g) < 0.01 and absf(shown.b - want.b) < 0.01, "its boxes show purple")
		purple[0].run_to(4.0)
		check(SmokeCloud.blocks(at + Vector3(-8, 1.4, 0), at + Vector3(8, 1.4, 0)), "and it blocks sight like white")
	await _clear()


func _test_same_seed() -> void:
	print("Same seed, same cloud")
	_room(Vector3(50, 0, 50), Vector3(5, 2.6, 4), true)  # walls for the rays to meet
	await _physics(3)
	var at := Vector3(51.5, 0.1, 51.0)
	var a := _cloud(at, 777)
	a.run_to(8.0)
	var a_digest := a.digest()
	var a_cells := a.cell_count()
	a.queue_free()
	await get_tree().process_frame
	var b := _cloud(at, 777)
	b.run_to(8.0)
	check(b.digest() == a_digest and b.cell_count() == a_cells, "the same seed grows the same cloud (%d cells)" % a_cells)
	b.queue_free()
	await get_tree().process_frame
	var other := _cloud(at, 778)
	other.run_to(8.0)
	check(other.digest() != a_digest, "another seed a different one")
	other.queue_free()
	await get_tree().process_frame
	# The host's cloud, with a blast in it; a late joiner's copy from its age, seed and events.
	var host := _cloud(at, 901)
	host.run_to(3.0)
	host.add_event([host.step + SmokeCloud.EVENT_LEAD, SmokeCloud.BLAST, at + Vector3(1, 0.6, 1), Vector3(3.0, 0.45, 0)])
	host.run_to(8.0)
	var events := host.events.duplicate(true)
	host.name = "HostsCloud"  # (out of the way of the joiner's copy, which takes the seed's name)
	level.spawn_smoke(at, "white", 8.0, 901, Vector3.ZERO, events)
	var joiner := level.get_node(NodePath(SmokeCloud.node_name(901))) as SmokeCloud
	for i in 30:  # straight to within MAX_LAG of its age, then the rest within the step budget
		await get_tree().physics_frame
		if joiner.step >= int(joiner.age * SmokeCloud.HZ) and joiner.step >= 64:
			break
	joiner.set_physics_process(false)
	host.run_to(float(joiner.step) / SmokeCloud.HZ)
	var host_step := host.step
	var host_digest := host.digest()
	check(joiner.step == host_step and joiner.digest() == host_digest,
		"a late joiner's copy (age, seed and the blast) steps up to the host's cloud (step %d, the host's %d)" % [joiner.step, host_step])
	joiner.queue_free()
	await get_tree().process_frame
	var late := _cloud(at, 901)
	late.run_to(float(host_step) / SmokeCloud.HZ)
	late.add_event(events[0])  # long after its step: rebuilt
	check(late.rebuilds == 1 and late.step == host_step and late.digest() == host_digest, "an event that comes after its step rebuilds the cloud to the same")
	await _clear()


func _test_cost() -> void:
	print("Cost")
	# Four in the open, one in the voxel shed, two in the test rooms, one in the shipping container.
	var spots: Array[Vector3] = [FIELD + Vector3(0, 0, -60), FIELD + Vector3(0, 0, -30), FIELD, FIELD + Vector3(0, 0, 30),
		Vector3(18.5, 0.1, -9.0), Vector3(52, 0.1, 1.5), Vector3(52, 0.1, -28), Vector3(-17.3, 0.1, 11.0)]
	var clouds: Array[SmokeCloud] = []
	for i in spots.size():
		clouds.append(_cloud(spots[i], 5000 + i, "white", false))
	var spent := SmokeCloud.spent_usec
	var rays_before := SmokeCloud.rays
	SmokeCloud.worst_step_usec = 0
	var t0 := Time.get_ticks_usec()
	var worst := 0
	var ticks := 0
	var per_tick: Array[int] = []
	while Time.get_ticks_usec() - t0 < 12_000_000:
		var before := SmokeCloud.spent_usec
		await get_tree().physics_frame
		per_tick.append(SmokeCloud.spent_usec - before)
		worst = maxi(worst, SmokeCloud.spent_usec - before)
		ticks += 1
	per_tick.sort()
	var p95 := per_tick[int(per_tick.size() * 0.95)] / 1000.0
	var seconds := (Time.get_ticks_usec() - t0) / 1e6
	var per_s := (SmokeCloud.spent_usec - spent) / 1000.0 / seconds
	var cells := 0
	for c in clouds:
		cells += c.cell_count()
	var moving := 0
	for c in clouds:
		moving += c.moving_count()
	print("  cost: %d clouds, %d cells (%d still changing), %.1f ms of steps a second over %.1f s (%d ticks), 95th percentile tick %.2f ms, worst tick %.2f ms, worst step %.2f ms, %d rays in all; steps behind: %s"
		% [clouds.size(), cells, moving, per_s, seconds, ticks, p95, worst / 1000.0, SmokeCloud.worst_step_usec / 1000.0, SmokeCloud.rays - rays_before,
		clouds.map(func(c: SmokeCloud) -> int: return int(c.age * SmokeCloud.HZ) - c.step)])
	check(per_s <= STEP_MS_PER_S, "%d clouds growing at once take %.1f ms of steps a second (Proposed budget %.0f)" % [CLOUDS, per_s, STEP_MS_PER_S])
	check(p95 <= TICK_P95_MS and worst / 1000.0 <= TICK_MS, "95%% of physics ticks spend at most %.2f ms on them, none more than %.2f ms (Proposed budgets %.0f, %.0f)"
		% [p95, worst / 1000.0, TICK_P95_MS, TICK_MS])
	var behind := 0
	for c in clouds:
		behind = maxi(behind, int(c.age * SmokeCloud.HZ) - c.step)
	check(behind <= SmokeCloud.MAX_LAG + 1, "and they keep up with the clock (at most %d steps behind)" % behind)
	var lines := 2000
	var t := Time.get_ticks_usec()
	var blocked := 0
	for i in lines:
		var c: Vector3 = spots[i % spots.size()]
		var a := c + Vector3(-12, 0.5 + (i % 7) * 0.4, -6 + (i % 13))
		var b := c + Vector3(12, 1.0 + (i % 5) * 0.3, 6 - (i % 11))
		if SmokeCloud.blocks(a, b):
			blocked += 1
	var us := float(Time.get_ticks_usec() - t) / lines
	check(us <= SIGHT_US, "a sight check through them takes %.1f us on average (Proposed budget %.0f; %d of %d blocked)" % [us, SIGHT_US, blocked, lines])
	await _clear()

