extends Node
## Building (docs/survival_building.md §1-4, 11; Builder, BuildPieces, BuildIntegrity, BuildMode):
## in a hosted survival world, a survivor with materials and a hammer lays a wood block, works
## it (stopping keeps the progress) and it's stamped into the voxels; shapes stamp their own
## voxels; the ghost's load colour is green on a supported cell and red where nothing holds it;
## a cantilever past wood's span cracks and falls as voxels with debris, and taking its post
## away drops what only that held; a wood block upgrades to brick in place for the difference;
## dismantling gives back 60%; a door opens, shuts, takes a code lock and a key lock, keeps a
## stranger out, and breaks; a blueprint laid without materials is built by a later call with
## them; zombies chewing lower a wood block's capacity (and leave brick alone); the builds save
## with the zone and come back on Continue.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var b: Builder
## The test's patch of flat ground: the cell the ground's surface is in at its corner.
var origin := Vector3i.ZERO


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("BUILDING TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if b != null and player != null:
		_test_catalogue()
		await _test_place_and_work()
		await _test_shapes()
		_test_ghost_colour()
		await _test_span_and_fall()
		await _test_upgrade()
		_test_dismantle()
		await _test_door()
		_test_blueprint()
		_test_chew()
		await _test_save_and_reload()
	_finish()


func _test_host() -> void:
	print("A survival world with a Builder")
	var name := "test_building" + tag
	check(Survival.server_new_world(main, name, 4321), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	for i in 120:
		await get_tree().process_frame
	b = Builder.find(level)
	check(b != null and b.is_in_group(Builder.GROUP), "the survival zone has its Builder on every peer")
	_clear_dead()
	check(player.inventory.put_on(&"backpack", &"pack_ruck_60"), "a big pack on for the materials")
	# Flat open ground near the survivor, clear of the zone's own buildings.
	var found := false
	var start := player.global_position
	for ring: float in [6.0, 10.0, 14.0, 20.0, 28.0, 36.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var x := start.x + cos(a) * ring
			var z := start.z + sin(a) * ring
			if _flat_and_clear(x, z):
				origin = Builder.ground_cell(Vector3(x, level.ground_height(x, z), z))
				found = true
				break
		if found:
			break
	check(found, "a patch of flat open ground near the survivor (%s)" % origin)
	_stand_by(origin + Vector3i(0, 0, -3))
	for i in 30:
		await get_tree().process_frame


## Whether 4 m round (x, z) is near level ground with nothing of the zone's on it.
func _flat_and_clear(x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var h := level.ground_height(x + dx * 0.5, z + dz * 0.5)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			for up in [0.3, 1.2, 2.2, 3.2]:
				if b._structure_at(Vector3(x + dx * 0.5, h + up, z + dz * 0.5)):
					return false
	return hi - lo < 0.3


## The cell the ground's surface is in, `dx`, `dz` cells from the origin's column.
func _at(dx: int, dz: int) -> Vector3i:
	var p := BuildPieces.cell_centre(origin + Vector3i(dx, 0, dz))
	return Builder.ground_cell(Vector3(p.x, level.ground_height(p.x, p.z), p.z))


## Puts the survivor on the ground beside cell `c` (within the builder's reach).
func _stand_by(c: Vector3i) -> void:
	var p := BuildPieces.cell_centre(c)
	player.global_position = Vector3(p.x, level.ground_height(p.x, p.z) + 0.1, p.z)
	player.velocity = Vector3.ZERO


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()


func _give(id: StringName, n: int) -> void:
	var got := player.inventory.take(id, n)
	if got < n:
		print("  (only %d of %d %s fit)" % [got, n, id])


func _count(id: StringName) -> int:
	return player.inventory.count_of(id)


## Drops every plank he carries (so a count starts from nothing).
func _drop_all(id: StringName) -> void:
	while player.inventory.remove_one(id):
		pass


func _test_catalogue() -> void:
	print("Materials and tools")
	var missing: Array = []
	for key: String in BuildPieces.MATERIALS:
		var id: StringName = BuildPieces.MATERIALS[key].item
		if not ItemDB.has_item(id) or ItemDB.get_item(id).stack <= 1 and key != "steel" and key != "concrete":
			missing.append(id)
	for kind: String in BuildPieces.TOOLS:
		for id: StringName in BuildPieces.TOOLS[kind]:
			if not ItemDB.has_item(id):
				missing.append(id)
	for kind: String in BuildPieces.PIECES:
		for pair: Array in BuildPieces.PIECES[kind].cost:
			if not ItemDB.has_item(StringName(pair[0])):
				missing.append(pair[0])
	check(missing.is_empty() and ItemDB.has_item(BuildPieces.KEY_ITEM), "every material, tool and piece cost is an item, materials stack (%s)" % [missing])
	check(BuildPieces.block_cost("wood", "block") == [[&"planks", 5]] and BuildPieces.block_cost("wood", "slab") == [[&"planks", 1]], "a wood block costs 5 planks, a slab 1")


func _test_place_and_work() -> void:
	print("A block laid, worked and stamped")
	_clear_dead()
	_give(&"hammer", 1)
	_give(&"planks", 15)
	var c := origin
	var planks := _count(&"planks")
	check(b.server_place(player, c + Vector3i(0, 6, 0), "wood") == "Nothing holds it there", "nothing goes in the air with nothing under it")
	_drop_all(&"hammer")
	check(b.server_place(player, c, "wood").begins_with("You need"), "no hammer, no wood block")
	_give(&"hammer", 1)
	check(b.server_place(player, c, "wood") == "", "a wood block's site laid on the ground")
	check(_count(&"planks") == planks - 5, "its 5 planks paid (%d -> %d)" % [planks, _count(&"planks")])
	check(b.blocks.has(c) and is_zero_approx(float(b.blocks[c].prog)) and not b.is_built(c), "it's a site, not built yet")
	b.server_work(player, c, 1.0)
	b.server_work(player, c, 1.0)
	check(is_equal_approx(float(b.blocks[c].prog), 0.5), "two stops of a second each: half done, the progress kept (%.2f)" % float(b.blocks[c].prog))
	b.server_work(player, c, 2.5)
	check(b.is_built(c), "four seconds of work builds wood")
	var key := Builder._chunk_key(c)
	check((b.logs.get(key, []) as Array).any(func(e: Dictionary) -> bool: return e.op == "bset"), "the block is a voxel edit in its chunk's log")
	check(await _wait_for(func() -> bool: return b.material_at(BuildPieces.cell_centre(c)) == VoxelWorld.Mat.WOOD, 15.0),
		"and its voxels are wood (%d)" % b.material_at(BuildPieces.cell_centre(c)))
	check(b.server_place(player, c, "wood") == "Something's built there", "one block a cell")
	var w := b.chunk_at(c)
	check(w != null and VoxelWorld.find_on(w.terrain) == w, "rounds find it like any voxel world (Ballistics)")


func _test_shapes() -> void:
	print("Shapes")
	var c := _at(4, 0)
	check(b.server_build_now(player, c, "wood", "slab") == "", "a slab built")
	var lo := Vector3(c) * BuildPieces.BLOCK_M
	await _wait_for(func() -> bool: return b.material_at(lo + Vector3(0.25, 0.05, 0.25)) == VoxelWorld.Mat.WOOD, 10.0)
	check(b.material_at(lo + Vector3(0.25, 0.05, 0.25)) == VoxelWorld.Mat.WOOD and b.material_at(lo + Vector3(0.25, 0.35, 0.25)) == VoxelWorld.Mat.EMPTY,
		"its bottom 0.1 m is wood and above it is air")
	check(b.server_dismantle(player, c) == "" and not b.blocks.has(c), "and it comes down")


func _test_ghost_colour() -> void:
	print("The ghost's load colour")
	var on_top := b.preview(origin + Vector3i(0, 1, 0), "wood", "block")
	check(int(on_top.state) == BuildIntegrity.State.OK, "on a block on the ground: green (%s)" % [on_top])
	var floating := b.preview(origin + Vector3i(3, 4, 3), "wood", "block")
	check(int(floating.state) == BuildIntegrity.State.FREE and BuildIntegrity.colour(floating.state) == BuildIntegrity.colour(BuildIntegrity.State.OVER),
		"in the air with nothing under it: red (%s)" % [floating])
	var cells := {Vector3i(0, 0, 0): BuildIntegrity.entry("wood", 1.0, 1.0, true)}
	for y in range(1, 11):
		cells[Vector3i(0, y, 0)] = BuildIntegrity.entry("wood", 1.0, 1.0, false)
	var tower := BuildIntegrity.solve(cells)
	check(int(tower[Vector3i.ZERO].state) == BuildIntegrity.State.OVER and int(tower[Vector3i(0, 4, 0)].state) == BuildIntegrity.State.OK,
		"a wood tower 11 blocks high overloads its foot (load %.1f of %.1f), its middle holds" % [tower[Vector3i.ZERO].load, tower[Vector3i.ZERO].cap])
	var brick := {}
	for y in 11:
		brick[Vector3i(0, y, 0)] = BuildIntegrity.entry("brick", 1.0, 1.0, y == 0)
	check(int(BuildIntegrity.solve(brick)[Vector3i.ZERO].state) != BuildIntegrity.State.OVER, "the same tower in brick stands")


func _test_span_and_fall() -> void:
	print("A span past wood's reach cracks and falls")
	_clear_dead()
	_give(&"planks", 24)
	var c := origin
	b.crack_s = 0.6
	# A post three high on the first block, then a beam four out from its top.
	for y in [1, 2]:
		check(b.server_build_now(player, c + Vector3i(0, y, 0), "wood") == "", "post block %d" % y)
	var beam: Array[Vector3i] = []
	for x in range(1, 5):
		var cell := c + Vector3i(x, 2, 0)
		beam.append(cell)
		if _count(&"planks") < 5:
			_give(&"planks", 10)
		check(b.server_build_now(player, cell, "wood") == "", "beam block %d out" % x)
	b.flush()
	var far: Vector3i = beam[3]
	check(int(b.status(far).get("state", -1)) == BuildIntegrity.State.OVER and int(b.status(far).h) == 4, "the fourth block out is past wood's span of 3: over (%s)" % [b.status(far)])
	check(bool(b.blocks[far].get("cracked", false)), "and cracks")
	check(beam.slice(0, 3).all(func(x: Vector3i) -> bool: return int(b.status(x).get("state", -1)) != BuildIntegrity.State.OVER), "the three nearer hold")
	await _wait_for(func() -> bool: return b.material_at(BuildPieces.cell_centre(far)) == VoxelWorld.Mat.WOOD, 5.0)
	var debris_before := _items_near(&"planks", far, 3.0)
	await _wait_for(func() -> bool: return not b.blocks.has(far), 5.0)
	check(not b.blocks.has(far), "after its crack time it falls")
	await _wait_for(func() -> bool: return b.material_at(BuildPieces.cell_centre(far)) == VoxelWorld.Mat.EMPTY, 5.0)
	check(b.material_at(BuildPieces.cell_centre(far)) == VoxelWorld.Mat.EMPTY, "as voxels: its cell is air")
	await _wait_for(func() -> bool: return _items_near(&"planks", far, 3.0) > debris_before, 3.0)
	check(_items_near(&"planks", far, 3.0) > debris_before, "and leaves planks as debris below")
	check(beam.slice(0, 3).all(func(x: Vector3i) -> bool: return b.is_built(x)), "the rest of the beam stands")
	# Take the post's top away: the beam it alone held falls with it.
	check(b.server_dismantle(player, c + Vector3i(0, 2, 0)) == "", "the post's top block dismantled")
	b.flush()
	check(beam.slice(0, 3).all(func(x: Vector3i) -> bool: return not b.blocks.has(x)), "everything only it held falls at once")
	check(b.server_dismantle(player, c + Vector3i(0, 1, 0)) == "", "(the post's last block down)")
	b.crack_s = Builder.CRACK_S


func _items_near(id: StringName, c: Vector3i, r: float) -> int:
	var at := BuildPieces.cell_centre(c)
	var n := 0
	for i in level.items.get_children():
		if i is WorldItem and (i as WorldItem).item_id == id and Vector2((i as Node3D).global_position.x - at.x, (i as Node3D).global_position.z - at.z).length() <= r:
			n += (i as WorldItem).count
	return n


func _test_upgrade() -> void:
	print("Upgrading in place")
	var c := _at(-3, 0)
	if _count(&"planks") < 5:
		_give(&"planks", 10)
	check(b.server_build_now(player, c, "wood") == "", "a wood block")
	_give(&"trowel", 1)
	_give(&"brick", 5)
	var bricks := _count(&"brick")
	var planks := _count(&"planks")
	check(b.server_upgrade(player, c, "scrap").begins_with("You need"), "an upgrade needs the new material's tool (scrap: a wrench set)")
	check(b.server_upgrade(player, c, "brick") == "", "wood to brick")
	var paid := bricks - _count(&"brick")
	check(paid == 3 and _count(&"planks") == planks, "it costs the difference: 3 bricks, not 4, and no wood back (%d)" % paid)
	check(b.material_at(BuildPieces.cell_centre(c)) == VoxelWorld.Mat.WOOD and b.is_built(c), "the wood block stands while it's upgraded")
	b.server_work(player, c, 20.0)
	check(String(b.blocks[c].m) == "brick" and not b.blocks[c].has("up"), "worked: it's brick")
	check(await _wait_for(func() -> bool: return b.material_at(BuildPieces.cell_centre(c)) == VoxelWorld.Mat.BRICK, 5.0), "its voxels are brick, never torn down")
	check(b.server_upgrade(player, c, "wood") == "That's no upgrade", "brick doesn't go back to wood")


func _test_dismantle() -> void:
	print("Dismantling")
	var c := _at(0, 3)
	if _count(&"planks") < 5:
		_give(&"planks", 10)
	check(b.server_build_now(player, c, "wood") == "", "a wood block")
	var planks := _count(&"planks")
	check(b.server_dismantle(player, c) == "" and not b.blocks.has(c), "dismantled")
	check(_count(&"planks") == planks + 3, "3 of its 5 planks back: 60%% (%d -> %d)" % [planks, _count(&"planks")])
	check((b.logs[Builder._chunk_key(c)] as Array).back().op == "bclr", "its voxels cleared")


func _test_door() -> void:
	print("Doors and locks")
	_give(&"planks", 8)
	var c := _at(2, -2)
	var id := b.server_build_piece_now(player, "door", c, 0)
	check(id > 0 and b.is_piece_built(id) and b.piece_node(id) != null, "a door built (%s)" % b.last_problem)
	if id <= 0:
		return
	var node := b.piece_node(id)
	await get_tree().physics_frame
	check(not node._shape.disabled, "shut, it's solid")
	check(b.server_door(player, id, "open") == "" and bool(b.pieces[id].open), "it opens")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(node._shape.disabled, "open, you walk through")
	check(b.server_door(player, id, "lock_code") == "Shut it first", "an open door takes no lock")
	b.server_door(player, id, "close")
	check(b.server_door(player, id, "lock_code") == "" and bool(b.pieces[id].locked), "a code lock fitted and locked")
	var code := String(b.pieces[id].lock.code)
	check(code.length() == 4 and code.is_valid_int(), "with a four-digit code (%s)" % code)
	check(b.server_door(null, id, "open") == "Locked" and not bool(b.pieces[id].open), "a stranger without the code stays out")
	check(b.server_door(null, id, "open", "0000" if code != "0000" else "1111") == "Locked", "a wrong code too")
	check(b.server_door(null, id, "open", code) == "" and bool(b.pieces[id].open), "the code opens it")
	b.server_door(player, id, "close")
	check(b.server_door(player, id, "lock") == "" and bool(b.pieces[id].locked), "who set it knows it: he locks it again")
	# A key lock on a second door.
	_give(&"planks", 4)
	var id2 := b.server_build_piece_now(player, "door", _at(5, -2), 0)
	check(id2 > 0, "a second door (%s)" % b.last_problem)
	if id2 > 0:
		check(b.server_door(player, id2, "lock_key") == "" and bool(b.pieces[id2].locked), "a key lock fitted")
		var lock_id := String(b.pieces[id2].lock.key)
		check(Builder.has_key(player, lock_id), "and its key cut for him")
		var where := _index_of(BuildPieces.KEY_ITEM)
		var key_entry: Dictionary = player.inventory.remove_entry(where[0], where[1]) if where[1] >= 0 else {}
		check(b.server_door(player, id2, "open") == "Locked", "without the key it stays shut")
		player.inventory.take(BuildPieces.KEY_ITEM, 1, key_entry.get("state", {}))
		check(b.server_door(player, id2, "open") == "" and bool(b.pieces[id2].open), "with it, it opens")
	# Locked doors are broken down.
	check(b.server_dismantle_piece(player, id) == "It's locked", "a locked door isn't taken down")
	b.server_hit_piece(id, 30.0)
	check(b.pieces.has(id) and float(b.pieces[id].hp) < 100.0, "a hit marks it")
	b.server_hit_piece(id, 1000.0)
	await get_tree().process_frame
	check(not b.pieces.has(id) and b.piece_node(id) == null, "enough and it breaks")


func _index_of(id: StringName) -> Array:
	for cn: StringName in Inventory.CONTAINERS:
		var list: Array = player.inventory.containers.get(cn, [])
		for i in list.size():
			if StringName(list[i].id) == id:
				return [cn, i]
	return [&"", -1]


func _test_blueprint() -> void:
	print("Blueprints")
	var c := _at(-3, 3)
	_drop_all(&"planks")
	check(b.server_place(player, c, "wood", "block", 0, true) == "", "a blueprint laid with no planks on him")
	check(bool(b.blocks[c].bp) and not bool(b.blocks[c].paid) and not b.is_built(c), "a ghost, unpaid")
	check(b.server_work(player, c, 10.0).begins_with("Not enough"), "nobody builds it without the materials")
	_give(&"planks", 5)
	check(b.server_work(player, c, 10.0) == "" and b.is_built(c) and _count(&"planks") == 0, "a later call with the planks pays and builds it")


func _test_chew() -> void:
	print("Zombies chew wood")
	var c := _at(-3, 3)
	b.flush()
	var cap := b.capacity(c)
	check(Builder.server_chew_at(level, BuildPieces.cell_centre(c), 60.0, 5), "five chew a minute at the wood block")
	check(b.capacity(c) < cap and absf(float(b.blocks[c].hp) - (1.0 - 300.0 / (Builder.CHEW_WOOD_S * Builder.CHEW_CREW))) < 0.001,
		"its capacity drops (%.2f -> %.2f)" % [cap, b.capacity(c)])
	var brick := _at(-3, 0)
	check(not b.server_chew(brick, 60.0, 5) and is_equal_approx(float(b.blocks[brick].hp), 1.0), "brick holds")
	_give(&"planks", 5)
	check(b.server_repair(player, c) == "" and is_equal_approx(float(b.blocks[c].hp), 1.0), "a repair makes the wood whole")


func _test_save_and_reload() -> void:
	print("Saved with the zone, back on Continue")
	var wood := origin
	var brick := _at(-3, 0)
	var door_id := -1
	for id: int in b.pieces:
		door_id = id
	var n_blocks := b.blocks.size()
	var n_pieces := b.pieces.size()
	Survival.server_save()
	check(not GameState.builds.is_empty() and (GameState.builds.blocks as Dictionary).size() == n_blocks, "the zone save holds the builds (%d blocks, %d pieces)" % [n_blocks, n_pieces])
	var name := Survival.world
	Net.leave()
	await get_tree().process_frame
	await get_tree().process_frame
	check(Survival.server_continue(main, name), "Continue hosts it again")
	level = SurvivalLevel.of(self)
	await _wait_for(func() -> bool: return level != null and level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	b = Builder.find(level)
	check(b != null and b.blocks.size() == n_blocks and b.pieces.size() == n_pieces, "every block and piece is back (%d, %d)" % [b.blocks.size() if b else -1, b.pieces.size() if b else -1])
	if b == null or player == null:
		return
	check(b.is_built(wood) and String(b.blocks[brick].m) == "brick", "as they were: the wood block, the upgraded brick")
	check(door_id < 0 or (bool(b.pieces[door_id].locked) and b.piece_node(door_id) != null), "the door locked as it was left")
	_stand_by(origin + Vector3i(0, 0, -3))
	check(await _wait_for(func() -> bool: return b.material_at(BuildPieces.cell_centre(wood)) == VoxelWorld.Mat.WOOD and b.material_at(BuildPieces.cell_centre(brick)) == VoxelWorld.Mat.BRICK, 20.0),
		"their voxels are rebuilt from the log (%d, %d)" % [b.material_at(BuildPieces.cell_centre(wood)), b.material_at(BuildPieces.cell_centre(brick))])


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("BUILDING TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
