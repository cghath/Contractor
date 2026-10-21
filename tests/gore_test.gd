extends Node
## Headless checks for blast dismemberment and synced severed pieces (blast-gore, 2026-10-20):
## BlastGore (what blasts, .50s and vehicles do to a body's shape), BodyDeform (carving it: inner
## layers, hanging limbs, pieces), SeveredPiece (the host settles a piece and records where it
## lies), Ragdoll.cut (no corpse propped on a limb that's gone), the gore setting and zone saves.
## Hosts a real session and blasts hostiles standing in the open.
##   <voxel godot exe> --headless --path . res://tests/gore_test.tscn
## Exits with the number of failures.

## Where the test men stand: far enough apart that one's blast doesn't reach another.
const SPOTS := [Vector3(-30, 0.1, 30), Vector3(-15, 0.1, 30), Vector3(0, 0.1, 30), Vector3(15, 0.1, 30), Vector3(30, 0.1, 30),
	Vector3(-30, 0.1, 45), Vector3(-15, 0.1, 45), Vector3(0, 0.1, 45), Vector3(15, 0.1, 45), Vector3(30, 0.1, 45),
	Vector3(-30, 0.1, 60), Vector3(-15, 0.1, 60), Vector3(0, 0.1, 60), Vector3(15, 0.1, 60), Vector3(30, 0.1, 60)]

var failures := 0
var level: CompoundLevel
var _spot := 0


func _ready() -> void:
	GameState.zone_id = "test_gore" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	BodyDeform.gore_override = "full"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 80)
	player.vitals.shielded = true
	_test_voxels()
	await _test_collapse()
	await _test_frag_alive()
	await _test_dead_he()
	await _test_point_blank()
	await _test_heavy_and_crush()
	await _test_hanging()
	await _test_heads_and_marks()
	await _test_gore_setting()
	await _test_save_round_trip()
	print("GORE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	BodyDeform.gore_override = ""
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## A hostile standing at the next spot, its brain off, no armour (so blasts reach the body).
func _man(name_: String, loadout: Array = []) -> Soldier:
	var at: Vector3 = SPOTS[_spot % SPOTS.size()]
	_spot += 1
	var s := level.spawn_soldier({"name": name_, "faction": "hostile", "variant": "woodland", "pos": at,
		"loadout": loadout, "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	s.set_physics_process(false)
	return s


func _deform(s: Soldier) -> BodyDeform:
	return s.model.get_node(^"BodyDeform") as BodyDeform


func _hitbox_point(s: Soldier, part: StringName) -> Vector3:
	var hb := BlastGore._hitbox(s, part)
	return Warheads.hitbox_point(hb, Vector3.ZERO) if hb else s.global_position


func _records(s: Soldier, kind: String) -> Array:
	return s.vitals.gore_list().filter(func(g: Dictionary) -> bool: return String(g.get("k", "")) == kind)


## Every "s" record has its rest pose and the piece lies exactly there.
func _pieces_at_records(s: Soldier) -> Array:
	var wrong: Array = []
	var deform := _deform(s)
	for g: Dictionary in _records(s, "s"):
		if g.get("np", false):
			continue
		var piece := deform.piece_of(StringName(g.p))
		var q: Array = g.get("q", [])
		if piece == null or q.size() != 7:
			wrong.append("%s: %s" % [g.p, "no piece" if piece == null else "no pose yet"])
			continue
		var at := SeveredPiece.pose_transform(q)
		if piece.global_position.distance_to(at.origin) > 0.01 or not piece.is_settled:
			wrong.append("%s: %.3f m off" % [g.p, piece.global_position.distance_to(at.origin)])
	return wrong


func _settled(s: Soldier) -> bool:
	return _pieces_at_records(s).is_empty()


# --- Voxels -------------------------------------------------------------------------------

func _test_voxels() -> void:
	print("Inside a part: skin, fat, flesh, bone")
	var raster := VoxelArt.raster_copy("thigh", "woodland")
	var prof := BodyDeform.profile(raster)
	var size := raster.get_size()
	var mid := roundi(BodyDeform._middle(raster))
	var piece := BodyDeform.split(raster, mid, false, prof, BodyDeform.K_LIMB, true)
	var stump := _colours_near(raster, mid + BodyDeform.SEVER_SLAB + 1, 3)
	check(stump.has(VoxelArt.C.BONE) and stump.has(VoxelArt.C.FAT) and (stump.has(VoxelArt.C.FLESH) or stump.has(VoxelArt.C.WOUND_DARK)),
		"a thigh's stump shows bone at the core, fat under the skin and flesh between (%s)" % [stump.keys()])
	var bone_out := _colours_near(raster, mid - 1, 1)
	check(bone_out.has(VoxelArt.C.BONE) or bone_out.has(VoxelArt.C.BONE_SHADE), "and the bone sticks out past the torn flesh (%s)" % [bone_out.keys()])
	check(_count(piece) > 0 and _count(raster) > 0, "the far side of the cut is its own piece")
	var plain := VoxelArt.raster_copy("thigh", "woodland")
	BodyDeform.split(plain, mid, false, BodyDeform.profile(plain), BodyDeform.K_LIMB, false)
	check(not _colours_near(plain, mid + BodyDeform.SEVER_SLAB + 1, 3).has(VoxelArt.C.BONE), "reduced gore: no bone on the stump")
	var crater := VoxelArt.raster_copy("thigh", "woodland")
	var cprof := BodyDeform.profile(crater)
	var centre := Vector3(cprof[mid * 4] + cprof[mid * 4 + 2] * 0.6, mid, cprof[mid * 4 + 1])
	BodyDeform.carve(crater, centre, BodyDeform.EXIT_R * 2.0, 3, cprof, BodyDeform.K_LIMB, true)
	var walls := _all_colours(crater)
	check(walls.has(VoxelArt.C.FLESH) or walls.has(VoxelArt.C.FAT), "a deep crater shows what's under the skin (%s)" % [walls.keys()])
	var charred := VoxelArt.raster_copy("shin", "woodland")
	check(BodyDeform.scorch(charred, Vector3.FORWARD, 1.0, 5) > 20 and _all_colours(charred).has(VoxelArt.C.CHAR), "charring blackens the side facing a blast")
	var peppered := VoxelArt.raster_copy("shin", "woodland")
	var before := _count(peppered)
	check(BodyDeform.pepper(peppered, Vector3.FORWARD, 8, 11) == 8 and _count(peppered) < before, "fragments pepper it with small pocks")
	var hang := VoxelArt.raster_copy("forearm", "woodland")
	var hprof := BodyDeform.profile(hang)
	var h := BodyDeform.dangle_split(hang, roundi(BodyDeform._middle(hang)), 2, hprof)
	check(not h.is_empty() and _count(h.buffer) > 0 and _count(hang) > 0, "a hanging cut leaves two parts joined by a strip (%d / %d voxels)" % [_count(h.buffer) if not h.is_empty() else 0, _count(hang)])
	var hull := BodyDeform.hull_points(piece)
	check(hull.size() >= 8, "a piece's collider fits its voxels (%d hull points)" % hull.size())


func _colours_near(buffer: VoxelBuffer, y: int, band: int) -> Dictionary:
	var out := {}
	var size := buffer.get_size()
	for yy in range(maxi(y - band, 1), mini(y + band + 1, size.y - 1)):
		for x in range(1, size.x - 1):
			for z in range(1, size.z - 1):
				var v := buffer.get_voxel(x, yy, z, VoxelBuffer.CHANNEL_COLOR)
				if v != VoxelArt.C.EMPTY:
					out[v] = true
	return out


func _all_colours(buffer: VoxelBuffer) -> Dictionary:
	return _colours_near(buffer, buffer.get_size().y / 2, buffer.get_size().y)


func _count(buffer: VoxelBuffer) -> int:
	var n := 0
	var size := buffer.get_size()
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
					n += 1
	return n


# --- Deaths ------------------------------------------------------------------------------

## Men killed standing: each body collapses, torso down near the ground (not left upright on its
## knees), the way it was pushed: shot from the front it goes back, running it pitches forward,
## a blast throws it away from the burst, nothing at all and it still goes down.
func _test_collapse() -> void:
	print("Deaths collapse")
	var cases := []
	var shot := _man("FallShot")
	var run := _man("FallRun")
	var blasted := _man("FallBlast")
	var still := _man("FallStill")
	await _seconds(0.5)
	var starts := {}
	for s: Soldier in [shot, run, blasted, still]:
		starts[s] = s.global_position
	# Shot in the chest from the front (from its -z side): it goes back (+z).
	var chest := _hitbox_point(shot, Vitals.CHEST)
	var into := shot.global_basis.z
	shot.vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.FULL_POWER, "position": chest - into * 0.1, "direction": into,
		"hitbox": BlastGore._hitbox(shot, Vitals.CHEST), "distance": 50.0})
	shot.vitals.server_kill()
	cases.append([shot, into, "shot from the front, it falls back"])
	# Running forward (-z) at 5 m/s.
	run.velocity = -run.global_basis.z * 5.0
	run.vitals.server_kill()
	cases.append([run, -run.global_basis.z, "running, it pitches forward"])
	# A blast 1.2 m to its right (+x): thrown to its left.
	var centre := blasted.global_position + blasted.global_basis.x * 1.2 + Vector3.UP * 0.4
	Ragdoll.note_blast(blasted, centre, 0.3)
	blasted.vitals.server_kill()
	cases.append([blasted, -blasted.global_basis.x, "a blast throws it away from the burst"])
	still.vitals.server_kill()
	cases.append([still, -still.global_basis.z, "dropped where it stood, it slumps forward"])
	await _wait_for(func() -> bool: return cases.all(func(c: Array) -> bool: return is_instance_valid((c[0] as Soldier).ragdoll) and (c[0] as Soldier).ragdoll.frozen), 20.0)
	for c: Array in cases:
		var s: Soldier = c[0]
		var torso := s.ragdoll.parts.get("torso") as Node3D if is_instance_valid(s.ragdoll) else null
		if torso == null:
			check(false, "%s: no ragdoll" % c[2])
			continue
		var height := torso.global_position.y - _ground_y(torso.global_position)
		var up := torso.global_basis.y.dot(Vector3.UP)
		var moved := torso.global_position - (starts[s] as Vector3)
		moved.y = 0.0
		var way: Vector3 = c[1]
		var along := moved.dot(way) if way.length() > 0.1 else 1.0
		check(s.ragdoll.frozen and height < 0.4 and absf(up) < 0.75 and along > 0.15,
			"%s: torso down %.2f m off the ground, %.0f deg from upright, %.2f m along its push" % [c[2], height, rad_to_deg(acos(clampf(up, -1.0, 1.0))), along])
	# A knee bends only backwards: in the thigh's frame the shin runs down and back (+z), never
	# forward past straight (a little slack for the joints' give).
	var worst := 0.0
	var who := ""
	for c: Array in cases:
		var s: Soldier = c[0]
		for side: String in ["l", "r"]:
			var leg := s.ragdoll.parts.get("leg_" + side) as Node3D
			var shin := s.ragdoll.parts.get("shin_" + side) as Node3D
			if leg and shin:
				var down := (leg.global_basis.orthonormalized().inverse() * shin.global_basis.orthonormalized()) * Vector3.DOWN
				if -down.z > worst:
					worst = -down.z
					who = "%s %s" % [s.name, side]
	check(worst < 0.25, "no knee bent the wrong way (worst %.2f forward of straight, %s)" % [worst, who])
	for c: Array in cases:  # out of the way: the blasts below use these spots
		(c[0] as Soldier).queue_free()
	_spot = 0
	await _seconds(0.3)


# --- Blasts -------------------------------------------------------------------------------

## A frag at a living man's feet: a foot or leg goes below the knee (an amputation a tourniquet
## stops), never more while he lives.
func _test_frag_alive() -> void:
	print("A frag at a living man's feet")
	var s := _man("GoreAlive")
	await _seconds(0.5)
	var feet := (_hitbox_point(s, Vitals.SHIN_L) + _hitbox_point(s, Vitals.SHIN_R)) * 0.5
	Throwables.server_detonate(level, "frag", Vector3(feet.x, s.global_position.y, feet.z) + s.global_basis.z * -0.15)
	await _seconds(0.5)
	var deform := _deform(s)
	var cut := deform.severed()
	var amputations := s.vitals.wound_list().filter(func(w: Dictionary) -> bool: return w.get("name") == Vitals.AMPUTATION)
	check(cut.any(func(p: StringName) -> bool: return p in [Vitals.SHIN_L, Vitals.SHIN_R]) and not amputations.is_empty(),
		"a close frag takes a leg below the knee (%s), an amputation to treat (%d)" % [cut, amputations.size()])
	if not s.vitals.is_dead():
		check(cut.all(func(p: StringName) -> bool: return p in BlastGore.DISTAL or p in deform.dangling()) and not Vitals.HEAD in cut,
			"alive: nothing worse than a shin or forearm off (%s)" % [cut])
	check(not _records(s, "h").is_empty() and not _records(s, "p").is_empty(), "the side facing it is scorched and peppered (%d, %d)" % [_records(s, "h").size(), _records(s, "p").size()])
	await _wait_for(func() -> bool: return _settled(s), 10.0)
	check(_settled(s), "each piece settles and the host records where it lies (%s)" % [_pieces_at_records(s)])


## HE beside a dead man: a whole limb or the head goes, and his ragdoll loses it.
func _test_dead_he() -> void:
	print("HE beside a corpse")
	var s := _man("GoreDead")
	await _seconds(0.3)
	s.vitals.server_kill()
	await _wait_for(func() -> bool: return is_instance_valid(s.ragdoll) and s.ragdoll.frozen, 10.0)
	var knee := _hitbox_point(s, Vitals.THIGH_R)
	Warheads.server_burst(level, &"og7v", knee + Vector3.UP * 0.3, Vector3.DOWN, null, null)
	await _seconds(0.5)
	var cut := _deform(s).severed()
	check(not cut.is_empty(), "a close HE burst takes a limb off the dead (%s)" % [cut])
	var gone_keys: Array = s.ragdoll.cut_away.keys() if is_instance_valid(s.ragdoll) else []
	var disabled := true
	for key: String in gone_keys:
		for c in (s.ragdoll.parts[key] as Node).get_children():
			if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
				disabled = false
	var shortened := false
	for part: StringName in cut:
		var key: String = Ragdoll.CUT_KEY.get(part, "")
		if key != "" and is_instance_valid(s.ragdoll) and not s.ragdoll.cut_away.has(key):
			shortened = true
	check(is_instance_valid(s.ragdoll) and (not gone_keys.is_empty() or shortened) and disabled,
		"his ragdoll lost it: %s gone (no colliders), the stump shortened %s" % [gone_keys, shortened])
	await _wait_for(func() -> bool: return is_instance_valid(s.ragdoll) and s.ragdoll.frozen, 10.0)
	var torso := s.ragdoll.parts.get("torso") as Node3D if is_instance_valid(s.ragdoll) else null
	var ground := _ground_y(torso.global_position) if torso else 0.0
	check(torso != null and torso.global_position.y - ground < 0.4, "the corpse lies down again on what's left, not propped on a cut limb (torso %.2f m up)" % [(torso.global_position.y - ground) if torso else -1.0])
	await _wait_for(func() -> bool: return _settled(s), 10.0)
	check(_settled(s), "its pieces settle where the host recorded (%s)" % [_pieces_at_records(s)])


func _ground_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 5.0, 1)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else 0.0


## A grenade going off against a man: he's dead and comes apart.
func _test_point_blank() -> void:
	print("Point-blank")
	var s := _man("GoreGib")
	await _seconds(0.3)
	Throwables.server_detonate(level, "frag", Throwables.body_point(s) + s.global_basis.z * -0.15 - Vector3.UP * 0.25)
	await _seconds(0.6)
	var cut := _deform(s).severed()
	check(s.vitals.is_dead() and not _records(s, "g").is_empty() and cut.size() >= 5 and Vitals.HEAD in cut,
		"gibbed: dead, head, arms and legs off (%s)" % [cut])
	check(_deform(s).pieces().size() >= 4, "flung as pieces (%d)" % _deform(s).pieces().size())
	await _wait_for(func() -> bool: return _settled(s), 10.0)
	check(_settled(s), "every piece settled and recorded (%s)" % [_pieces_at_records(s)])
	check(s.vitals.gore_list().size() <= BlastGore.MAX_ENTRIES, "its gore stays under the cap (%d entries)" % s.vitals.gore_list().size())


## A .50 through a dead man's arm takes it; a heavy vehicle over his head pulps it.
func _test_heavy_and_crush() -> void:
	print(".50s and vehicles")
	var s := _man("GoreHeavy", ["helmet"])
	await _seconds(0.3)
	var arm := _hitbox_point(s, Vitals.UPPER_ARM_L)
	s.vitals.server_hit(Vitals.UPPER_ARM_L, {"round_class": Vitals.FULL_POWER, "position": arm, "direction": s.global_basis.x,
		"hitbox": BlastGore._hitbox(s, Vitals.UPPER_ARM_L), "distance": 300.0, "energy_j": 15000.0, "channel_depth": 0.1})
	await _seconds(0.4)
	check(s.vitals.is_dead() and Vitals.UPPER_ARM_L in _deform(s).severed(), "a .50 kills and takes the arm it hit (%s)" % [_deform(s).severed()])
	BlastGore.server_crush(s, "head", 9000.0, 5.0)
	await _seconds(0.4)
	var heads := _records(s, "s").filter(func(g: Dictionary) -> bool: return g.p == "head")
	check(Vitals.HEAD in _deform(s).severed() and not heads.is_empty() and heads[0].get("np", false) and _deform(s).piece_of(Vitals.HEAD) == null,
		"an APC over his head crushes it: gone, no piece left of it")
	var helmets := get_tree().get_nodes_in_group(WorldItem.GROUP).filter(func(n: Node) -> bool:
		return n is WorldItem and (n as WorldItem).item_id == &"helmet" and (n as Node3D).global_position.distance_to(s.global_position) < 4.0)
	check(s.inventory.slots[&"helmet"] == &"" and helmets.size() == 1, "the helmet came off with the head, an item to pick up (%d near)" % helmets.size())


## Captain, 2026-10-21: "the first headshot doesnt leave a wound"; "theres no model for a neck
## which had its head severed by an rpg round. it carves a crater out in the body"; "blood marks
## on a body stay where a limb was after it dismembers when shooting with weapons".
func _test_heads_and_marks() -> void:
	print("Heads, necks and marks past a cut")
	var s := _man("GoreHeadshot")
	await _seconds(0.3)
	var head := _hitbox_point(s, Vitals.HEAD)
	s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE, "position": head, "direction": s.global_basis.z,
		"hitbox": BlastGore._hitbox(s, Vitals.HEAD), "distance": 50.0, "channel_depth": 0.08})
	await _seconds(0.3)
	var marks := s.model.get_node(^"WoundMarks") as WoundMarks
	var on_head := s.vitals.wound_list().filter(func(w: Dictionary) -> bool: return w.part == Vitals.HEAD and w.get("at") is Vector3)
	check(s.vitals.is_dead() and not on_head.is_empty() and marks.holes_on(Vitals.HEAD) >= 1,
		"the first, killing headshot leaves its wound (%d on the head, %d holes drawn)" % [on_head.size(), marks.holes_on(Vitals.HEAD)])
	# A warhead on the head: the head goes, a neck stump stays, the torso isn't gibbed or cratered.
	var r := _man("GoreRpgHead")
	await _seconds(0.3)
	var at := _hitbox_point(r, Vitals.HEAD)
	r.vitals.server_kill()
	BlastGore.server_direct(r, Vitals.HEAD, at, r.global_basis.z, 0.7)
	await _wait_for(func() -> bool: return _deform(r).cut_bounds(Vitals.HEAD) is AABB, 5.0)
	var cut := _deform(r).severed()
	var torso_craters := _records(r, "c").filter(func(g: Dictionary) -> bool: return StringName(g.p) in BlastGore.TORSO_PARTS)
	var neck: Variant = _deform(r).cut_bounds(Vitals.HEAD)
	check(cut == [Vitals.HEAD] and _records(r, "g").is_empty() and torso_craters.is_empty(),
		"an RPG on the head takes the head and only the head (%s), no gib, no crater in the torso (%d)" % [cut, torso_craters.size()])
	check(neck is AABB and (neck as AABB).size.y > 0.03 and (neck as AABB).size.y < 0.1,
		"a neck stump stands where it was (%.1f cm)" % ((neck as AABB).size.y * 100.0 if neck is AABB else -1.0))
	# Marks low on a thigh, then the thigh cut high: the marks past the cut go with it.
	var m := _man("GoreMarks")
	await _seconds(0.3)
	m.vitals.server_kill()
	var hb := BlastGore._hitbox(m, Vitals.THIGH_L)
	var low := Warheads.hitbox_point(hb, Vector3(0, -0.15, 0))
	m.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.INTERMEDIATE, "position": low, "direction": m.global_basis.z, "hitbox": hb, "distance": 50.0, "channel_depth": 0.05})
	await _seconds(0.3)
	var thigh := m.model.part_node(Vitals.THIGH_L)
	var drawn := func() -> int:
		var mm := thigh.get_node_or_null(^"WoundMark") as MultiMeshInstance3D
		return mm.multimesh.visible_instance_count if mm else 0
	var before: int = drawn.call()
	var top: Array = BodyMap.PART_BOXES[Vitals.THIGH_L][0]
	var high := (top[0] as Vector3) + Vector3(0, (top[1] as Vector3).y * 0.35, 0)
	m.vitals.server_gore_add({"k": "s", "p": String(Vitals.THIGH_L), "a": BlastGore.vec(high), "np": true}, false)
	m.vitals.server_gore_flush()
	await _wait_for(func() -> bool: return _deform(m).cut_bounds(Vitals.THIGH_L) is AABB and drawn.call() == 0, 5.0)
	check(before > 0 and drawn.call() == 0, "cut above its wound, the thigh's marks go with what was cut off (%d drawn, then %d)" % [before, drawn.call()])


## Rounds into a dead man's broken thigh: hanging by tissue first, then off.
func _test_hanging() -> void:
	print("Hanging by tissue")
	var s := _man("GoreHang")
	await _seconds(0.3)
	s.vitals.server_kill()
	await _seconds(0.3)
	var deform := _deform(s)
	var hb := BlastGore._hitbox(s, Vitals.THIGH_L)
	var shoot := func(n: int) -> void:
		for i in n:
			var p := Warheads.hitbox_point(hb, Vector3(0.1 * (i % 3 - 1), 0.05 * (i % 5 - 2), -0.5))
			s.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.FULL_POWER, "position": p, "direction": s.global_basis.z * -1.0,
				"hitbox": hb, "distance": 50.0, "energy_j": 3300.0})
	# The dead take holes but no new fractures: put the break the rounds would have made.
	s.vitals._model._add_wound(Vitals.THIGH_L, "fracture", 0.0, &"femur_l")
	shoot.call(4)  # 8 points: past DANGLE_SHARE of SEVER_DEAD
	await _wait_for(func() -> bool: return Vitals.THIGH_L in deform.dangling(), 3.0)
	check(Vitals.THIGH_L in deform.dangling() and not Vitals.THIGH_L in deform.severed(), "a torn-up thigh hangs by tissue (%s)" % [deform.dangling()])
	await _seconds(0.5)
	var hinge := s.model.part_node(Vitals.THIGH_L).get_node_or_null(^"Hang_thigh_l")
	check(hinge != null and absf(rad_to_deg((hinge as Node3D).basis.get_euler().length())) > 10.0, "its lower part swings off the stump")
	shoot.call(2)
	await _wait_for(func() -> bool: return Vitals.THIGH_L in deform.severed(), 3.0)
	await _seconds(0.5)
	check(Vitals.THIGH_L in deform.severed() and deform.piece_of(Vitals.THIGH_L) != null and not is_instance_valid(hinge),
		"more rounds cut it through: what hung drops as a piece")


## Gore off draws every body whole; full again puts it all back where it was.
func _test_gore_setting() -> void:
	print("The gore setting")
	var bodies := get_tree().get_nodes_in_group(&"combatants").filter(func(n: Node) -> bool: return n is Soldier and String(n.name).begins_with("Gore"))
	BodyDeform.gore_override = "off"
	for b: Soldier in bodies:
		_deform(b)._rebuild()
	await _seconds(0.3)
	var pieces := get_tree().get_nodes_in_group(SeveredPiece.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var carved := 0
	var hidden := 0
	for b: Soldier in bodies:
		for part: StringName in BodyDeform.LIMBS + [Vitals.HEAD, Vitals.CHEST]:
			var pivot := b.model.part_node(part)
			var mi := BodyDeform._mesh_of(pivot)
			if mi and mi.mesh != VoxelArt.mesh(String(pivot.get_meta(&"voxel_model")), String(pivot.get_meta(&"voxel_variant", ""))):
				carved += 1
			if pivot and not pivot.is_visible_in_tree() and b.model.visible:
				hidden += 1
	check(pieces.is_empty() and carved == 0 and hidden == 0, "off: no pieces, no carved part, nothing hidden (%d pieces, %d carved, %d hidden)" % [pieces.size(), carved, hidden])
	var gib := bodies.filter(func(b: Soldier) -> bool: return b.name == "GoreGib")
	check(not gib.is_empty() and (gib[0] as Soldier).vitals.is_dead() and _deform(gib[0]).severed().size() >= 5, "what's cut is still known (the ragdoll keeps it)")
	BodyDeform.gore_override = "full"
	for b: Soldier in bodies:
		_deform(b)._rebuild()
	await _wait_for(func() -> bool: return gib.is_empty() or _settled(gib[0]), 5.0)
	check(not gib.is_empty() and _settled(gib[0]), "full again: the pieces are back exactly where they lay (%s)" % [_pieces_at_records(gib[0]) if not gib.is_empty() else "no body"])


## A gibbed body saved with the zone and put back: the same parts gone, its pieces where they lay.
func _test_save_round_trip() -> void:
	print("Zone save round trip")
	var gib: Soldier = null
	for n in get_tree().get_nodes_in_group(&"combatants"):
		if n is Soldier and n.name == "GoreGib":
			gib = n
	if gib == null:
		check(false, "no gibbed body to save")
		return
	var record := gib.body_record()
	var text := JSON.stringify(record)  # through JSON, as GameState saves it
	var back: Dictionary = JSON.parse_string(text)
	back["uid"] = "gore_saved_1"
	var cut_before := _deform(gib).severed()
	var poses := {}
	for g: Dictionary in _records(gib, "s"):
		poses[g.p] = g.get("q", [])
	gib.queue_free()
	for piece in get_tree().get_nodes_in_group(SeveredPiece.GROUP):
		piece.queue_free()
	await _seconds(0.3)
	var restored := level.server_spawn_body(back)
	await _seconds(1.0)
	var deform := _deform(restored)
	var same := cut_before.all(func(p: StringName) -> bool: return p in deform.severed())
	check(same and deform.severed().size() == cut_before.size(), "restored: the same parts gone (%s)" % [deform.severed()])
	var off := []
	for part: String in poses:
		var piece := deform.piece_of(StringName(part))
		var q: Array = poses[part]
		if q.size() == 7 and (piece == null or piece.global_position.distance_to(SeveredPiece.pose_transform(q).origin) > 0.01):
			off.append(part)
	check(off.is_empty() and deform.pieces().size() >= 4, "and its pieces lie where they lay (%s off)" % [off])
	check(deform.craters_on(Vitals.CHEST) > 0, "its torso still torn open (%d craters)" % deform.craters_on(Vitals.CHEST))
