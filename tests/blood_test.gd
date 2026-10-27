extends Node3D
## Headless checks that blood never floats and the wounds read (Captain, 2026-10-26: "i want the
## visible wounds to get better and blood to stop floating too"; blood dripping onto helmets and
## backpacks should stain them, not "float in the air/stay stacked"). One check per way blood was
## drawn off the surface it belongs to, positions against the surface itself:
## - marks on a slim and a broad build (the part's mesh is widened for the build, the marks were not);
## - marks as the body lies down (they ride the bones);
## - drips starting on the skin of a slim build;
## - a chest seal and a trunk pad on the curve of the chest (they were flat, standing off its edges);
## - hand blood on the hand as it's posed (it was laid on the relaxed hand, off a gripping one);
## - pools on a slope (flat cells on a tilted floor) and smears;
## - a drop flying off a ledge (it "landed" at the ledge's height in the air);
## - pools whose ground went from under them (re-seated or gone);
## - drops on someone's helmet and pack (they stacked as cells on him: now they stain the gear).
## And the new look: the wound painted into the body's voxels (WoundSkin) on its part and the next
## one as it soaks on, on the face's parts, bruises from armour stops (gore "b"), reduced gore.
##   <voxel godot exe> --headless --path . res://tests/blood_test.tscn
## Exits with the number of failures.

const SPOT := Vector3(0, 0.1, 20)
## A test stand in the air, away from the yard: a slope, a ledge over a floor, a shelf to remove.
const STAND := Vector3(60, 30, -60)

var failures := 0
var level: CompoundLevel
var player: Soldier
var _faces: Dictionary = {}  # MeshInstance3D -> its triangles' corners, world (as when cached)


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("BLOOD TEST FAILED (timed out)")
		get_tree().quit(99))
	await _start_session()
	await _test_builds()
	await _test_lying()
	await _test_dressings_on_chest()
	await _test_hands_posed()
	await _test_slope()
	await _test_ledge()
	await _test_ground_gone()
	await _test_gear_stains()
	await _test_painted()
	await _test_face()
	await _test_bruises()
	await _test_reduced()
	await _test_runs_follow_gravity()
	await _test_spurts()
	await _test_seeping_dressing()
	GameState.delete_save()
	BodyDeform.gore_override = ""
	print("BLOOD TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _start_session() -> void:
	GameState.zone_id = "test_blood" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	BodyDeform.gore_override = "full"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = SPOT + Vector3(0, 0, 30)
	player.vitals.shielded = true


var _n := 0


## A friendly standing at `at`, its brain off, its build `build` (SoldierLook: 0 slim .. 2 heavy).
func _man(at: Vector3, build := 1, loadout: Array = ["m4a1"]) -> Soldier:
	_n += 1
	var s := level.spawn_soldier({"name": "Blood%d" % _n, "faction": "friendly", "variant": "multicam", "pos": at,
		"loadout": loadout, "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	s.set_physics_process(false)
	await _frames(5)
	var f := (s.face if s.face != "" else s.model.face).split(":")
	if f.size() == 6:
		f[4] = str(build)
		s.face = ":".join(f)  # (the body's own, replicated: the model follows it)
	await _frames(3)
	return s


# --- Surfaces ---------------------------------------------------------------------------------

## The corners of `mi`'s triangles in the world, as it's drawn now.
func _tris(mi: MeshInstance3D) -> PackedVector3Array:
	return mi.global_transform * mi.mesh.get_faces()


## How far world point `p` is from the drawn surface of `mi` (m).
func _gap(mi: MeshInstance3D, p: Vector3, tris := PackedVector3Array()) -> float:
	if tris.is_empty():
		tris = _tris(mi)
	var best := INF
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var lo := a.min(tris[i + 1]).min(tris[i + 2]) - Vector3.ONE * minf(best, 0.05)
		var hi := a.max(tris[i + 1]).max(tris[i + 2]) + Vector3.ONE * minf(best, 0.05)
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue  # (its box is further than the best so far)
		best = minf(best, _point_tri(p, a, tris[i + 1], tris[i + 2]))
	return best


## The distance from `p` to triangle a, b, c.
static func _point_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var q: Vector3 = Geometry3D.get_closest_point_to_segment(p, a, b)
	var n := (b - a).cross(c - a)
	if n.length_squared() > 1e-14:
		n = n.normalized()
		var on_plane := p - n * (p - a).dot(n)
		var inside := (b - a).cross(on_plane - a).dot(n) >= 0.0 and (c - b).cross(on_plane - b).dot(n) >= 0.0 and (a - c).cross(on_plane - c).dot(n) >= 0.0
		if inside:
			return p.distance_to(on_plane)
	var best := p.distance_to(q)
	best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
	best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))
	return best


## The world points of the cells `inst` draws (each cell's centre).
func _cells(inst: Variant) -> Array[Vector3]:
	return WoundMarks.drawn_cells(inst)


## The worst gap of `points` from `mi` (m), and how many points.
func _worst(mi: MeshInstance3D, points: Array[Vector3]) -> float:
	var tris := _tris(mi)
	var worst := 0.0
	for p: Vector3 in points:
		worst = maxf(worst, _gap(mi, p, tris))
	return worst


func _marks(s: Soldier) -> WoundMarks:
	return s.model.get_node(^"WoundMarks")


func _mesh(s: Soldier, part: StringName) -> MeshInstance3D:
	return WoundSkin.mesh_of(s.model.part_node(part))


func _wound(s: Soldier, part: StringName, kind: String, rate: float, name: StringName, at: Variant = null, out: Variant = null) -> Dictionary:
	var m: WoundModel = s.vitals._model
	var w := m._add_wound(part, kind, rate, name)
	if at is Vector3:
		w["at"] = at
	if out is Vector3:
		w["out"] = out
	m.update_state(0.0)
	s.vitals._after_change(true)
	return w


## The world's ground under `p` (y), or NAN.
func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * 0.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else NAN


## Every pool cell has its ground just under it (within `tol`): [ok, the worst, how many].
func _pools_on_ground(marks: WoundMarks, tol := 0.003) -> Array:
	var worst := 0.0
	var cells := marks.pool_cells()
	for p: Vector3 in cells:
		var g := _ground_y(p)
		worst = maxf(worst, INF if is_nan(g) else absf(p.y - g))
	return [worst <= tol, worst, cells.size()]


func _box(at: Vector3, size: Vector3, tilt_x := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, tilt_x), at)
	return body


## Drops let fall from `from` (each a little apart), with velocity `vel`, until all have landed.
func _drop(marks: WoundMarks, from: Vector3, n: int, vel := Vector3.ZERO, spread := 0.06) -> void:
	for i in n:
		var p := from + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
		marks._drips.append({"pos": p, "vel": vel, "floor": marks._floor_below(p), "y0": p.y})
	marks.set_process(true)
	var t0 := Time.get_ticks_msec()
	while marks.drops_in_air() > 0 and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame


# --- Floating -------------------------------------------------------------------------------

func _test_builds() -> void:
	print("Marks on a slim and a broad build")
	for build: int in [0, 2]:
		var s := await _man(SPOT + Vector3(build * 2.0 - 2.0, 0, 0), build)
		var marks := _marks(s)
		_wound(s, Vitals.CHEST, "muscle", 0.6, &"", Vector3(0.06, 1.25, -0.11))
		_wound(s, Vitals.THIGH_L, "venous", 0.8, &"", Vector3(-0.075, 0.62, -0.085))
		await _seconds(1.5)
		var chest_mi := _mesh(s, Vitals.CHEST)
		var torso := s.model.part_node(Vitals.CHEST)
		var cells := _cells(torso.get_node_or_null(^"WoundMark"))
		var worst := _worst(chest_mi, cells)
		check(not cells.is_empty() and worst < 0.008, "%s build (girth %.2f): the chest's blood and hole voxels lie on its skin (%d, worst %.1f mm off)"
			% [["slim", "", "broad"][build], s.model.girth("torso"), cells.size(), worst * 1000.0])
		var drop_from: Array[Vector3] = []
		for i in 6:
			marks._spawn_drip()
			if not marks._drips.is_empty():
				drop_from.append(Vector3(marks._drips[-1].pos))
		var gap := 0.0  # the worst drop's distance from the nearest part it could start on
		for p: Vector3 in drop_from:
			var best := INF
			for part: StringName in [Vitals.CHEST, Vitals.THIGH_L, Vitals.SHIN_L]:
				best = minf(best, _gap(_mesh(s, part), p))
			gap = maxf(gap, best)
		check(not drop_from.is_empty() and gap < 0.012, "and its drips start on the skin (%d, worst %.1f mm off)" % [drop_from.size(), gap * 1000.0])
		s.vitals.server_reset_health()
		s.queue_free()
	await _frames(3)


func _test_lying() -> void:
	print("Marks on a body lying down")
	var s := await _man(SPOT + Vector3(4, 0, 0), 0)
	_wound(s, Vitals.THIGH_L, "venous", 0.8, &"", Vector3(-0.075, 0.62, -0.085))
	await _seconds(1.0)
	CharacterModel.lay_down(s, s.model, true)
	await _seconds(1.5)
	var thigh := s.model.part_node(Vitals.THIGH_L)
	var cells := _cells(thigh.get_node_or_null(^"WoundMark"))
	var worst := _worst(_mesh(s, Vitals.THIGH_L), cells)
	check(not cells.is_empty() and worst < 0.008, "lying down, the thigh's blood stays on the thigh (%d voxels, worst %.1f mm off)" % [cells.size(), worst * 1000.0])
	var skin_node := _marks(s).skin.drawn().get(thigh) as MeshInstance3D
	check(skin_node != null and skin_node.get_parent() == _mesh(s, Vitals.THIGH_L) and skin_node.mesh == _mesh(s, Vitals.THIGH_L).mesh,
		"its painted wound is the thigh's own mesh, moving with it")
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _test_dressings_on_chest() -> void:
	print("A chest seal and a pad on the curve of the chest")
	var s := await _man(SPOT + Vector3(6, 0, 0), 0)
	_wound(s, Vitals.CHEST, "chest", 0.15, &"lung_r", Vector3(0.11, 1.3, -0.1))
	s.vitals.server_apply_treatment(&"chest_seal", Vitals.CHEST)
	_wound(s, Vitals.ABDOMEN, "muscle", 0.3, &"", Vector3(-0.09, 1.02, -0.1))
	s.vitals.server_apply_treatment(&"pressure_bandage", Vitals.ABDOMEN)
	await _frames(3)
	var torso := s.model.part_node(Vitals.CHEST)
	var dress := torso.get_node_or_null(^"WoundDressing") as MultiMeshInstance3D
	var cells := _cells(dress)
	var worst := _worst(_mesh(s, Vitals.CHEST), cells)
	check(_marks(s).dressing_on(Vitals.CHEST) == &"seal" and cells.size() > 60 and worst < 0.013,
		"the seal and the bandage pad lie on the chest's curve, not flat off it (%d voxels, worst %.1f mm off)" % [cells.size(), worst * 1000.0])
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _test_hands_posed() -> void:
	print("Blood on a gripping hand")
	var s := await _man(SPOT + Vector3(8, 0, 0), 0)
	var marks := _marks(s)
	marks._hand_blood = 6.0
	marks._hand_until = WoundMarks._now() + 60.0
	marks._hand_wet_until = WoundMarks._now() + 60.0
	marks._grow_hands()
	s.model._show_hand(0, HandPose.GRIP)
	await _seconds(0.7)  # the hands' tick sees the new pose
	var points := marks.hand_blood_points(true)
	var worst := _worst(_mesh(s, Vitals.FOREARM_R), points)
	check(not points.is_empty() and worst < 0.006, "on the hand as it grips, not where the relaxed hand was (%d voxels, worst %.1f mm off)" % [points.size(), worst * 1000.0])
	s.queue_free()
	await _frames(3)


func _test_slope() -> void:
	print("Pools on a slope")
	var s := await _man(SPOT + Vector3(10, 0, 0))
	var marks := _marks(s)
	var slope := _box(STAND, Vector3(3, 0.2, 3), deg_to_rad(25.0))
	await _frames(3)
	await _drop(marks, STAND + Vector3(0, 0.6, 0), 30)
	var on := _pools_on_ground(marks)
	var normal := slope.global_basis.y.normalized()
	var tilted := true
	var mm: MultiMesh = marks._pool_mesh.multimesh if marks._pool_mesh else null
	var least := 1.0
	for cell: Vector2i in marks._pool:  # (how each is drawn: WoundMarks._redraw_pool)
		least = minf(least, WoundMarks._on_ground(marks._pool[cell].n).y.normalized().dot(normal))
	tilted = least > 0.99
	check(on[0] and int(on[2]) > 3 and mm != null and tilted, "every pool cell lies on the 25-degree slope and tilts with it (%d cells, worst %.1f mm off, least aligned %.3f)" % [on[2], float(on[1]) * 1000.0, least])
	slope.queue_free()
	s.queue_free()
	await _frames(3)


func _test_ledge() -> void:
	print("A drop flying off a ledge")
	var s := await _man(SPOT + Vector3(12, 0, 0))
	var marks := _marks(s)
	var floor_box := _box(STAND + Vector3(0, -1.5, 0), Vector3(6, 0.2, 6))
	var shelf := _box(STAND, Vector3(1, 0.2, 1))
	await _frames(3)
	# Starts over the shelf's edge (its floor the shelf), flies off it.
	await _drop(marks, STAND + Vector3(0.45, 0.15, 0), 6, Vector3(1.6, 0.4, 0), 0.01)
	var on := _pools_on_ground(marks)
	var low := marks.pool_cells().all(func(p: Vector3) -> bool: return p.y < STAND.y - 1.0)
	check(on[0] and int(on[2]) > 0 and low, "it falls on past the edge to the floor below, not left at the shelf's height (%d cells, worst %.1f mm off)" % [on[2], float(on[1]) * 1000.0])
	shelf.queue_free()
	floor_box.queue_free()
	s.queue_free()
	await _frames(3)


func _test_ground_gone() -> void:
	print("Pools whose ground goes")
	var s := await _man(SPOT + Vector3(14, 0, 0))
	var marks := _marks(s)
	var floor_box := _box(STAND + Vector3(0, -0.7, 0), Vector3(4, 0.2, 4))
	var crate := _box(STAND, Vector3(0.6, 0.2, 0.6))
	await _frames(3)
	await _drop(marks, STAND + Vector3(0, 0.5, 0), 20, Vector3.ZERO, 0.1)
	var before := marks.pool_size()
	crate.free()
	await _frames(3)
	for i in 10:
		marks._settle()
	var on := _pools_on_ground(marks)
	check(before > 0 and marks.pool_size() > 0 and on[0], "the crate under it gone, the pool lies on the floor under it, none left hanging (%d cells, worst %.1f mm off)"
		% [marks.pool_size(), float(on[1]) * 1000.0])
	floor_box.free()
	await _frames(3)
	for i in 10:
		marks._settle()
	check(marks.pool_size() == 0, "its floor gone too, nothing under it: it goes (%d left)" % marks.pool_size())
	s.queue_free()
	await _frames(3)


func _test_gear_stains() -> void:
	print("Blood dripping onto someone's helmet and pack")
	var bleeder := await _man(SPOT + Vector3(16, 0, 3))
	var marks := _marks(bleeder)
	var under := await _man(SPOT + Vector3(16, 0, 0), 1, ["m4a1", "helmet", "backpack", "plate_carrier"])
	await _frames(10)
	var head := under.model.part_node(Vitals.HEAD).global_position
	await _drop(marks, head + Vector3(0, 0.6, 0), 8, Vector3.ZERO, 0.02)
	var pack_at := under.global_position + under.global_basis.z * 0.2 + Vector3.UP * 1.5
	await _drop(marks, pack_at + Vector3(0, 0.5, 0), 8, Vector3.ZERO, 0.03)
	var stacked := under.find_children("BloodOn", "", true, false).size()
	var stains := marks.stained()
	var on_him := stains.filter(func(st: BloodStain) -> bool: return under.is_ancestor_of(st))
	var parts := []
	for st: BloodStain in on_him:
		parts.append(String(st.get_parent().get_parent().name))
	var gear := on_him.any(func(st: BloodStain) -> bool:
		return not (st.get_parent().get_parent() as Node3D in [under.model.part_node(Vitals.HEAD), under.model.part_node(Vitals.CHEST)] and WoundSkin.mesh_of(st.get_parent().get_parent()) == st.get_parent()))
	var near := true
	for st: BloodStain in on_him:
		var mi := st.get_parent() as MeshInstance3D
		for e: Dictionary in st.stains():
			near = near and BloodStain._distance_to_box(mi.global_transform * mi.get_aabb(), e.at) < 0.1
	check(stacked == 0 and not on_him.is_empty() and gear and near,
		"the drops stain his gear where they fell (%d stained: %s), none stacked on him as cells (%d)" % [on_him.size(), parts, stacked])
	var hanging := _pools_on_ground(marks, 0.003)
	check(hanging[0], "and whatever ran past him lies on the ground (%d cells, worst %.1f mm off)" % [hanging[2], float(hanging[1]) * 1000.0])
	under.queue_free()
	bleeder.queue_free()
	await _frames(3)


# --- The look -------------------------------------------------------------------------------------

func _test_painted() -> void:
	print("The wound painted into the body")
	var s := await _man(SPOT + Vector3(18, 0, 0))
	var marks := _marks(s)
	_wound(s, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l", Vector3(-0.075, 0.62, -0.085), Vector3(-0.075, 0.6, 0.075))
	await _frames(3)
	var thigh := s.model.part_node(Vitals.THIGH_L)
	var shin := s.model.part_node(Vitals.SHIN_L)
	var mat := marks.skin.material_of(thigh)
	check(marks.skin.drawn().has(thigh) and mat != null and int(mat.get_shader_parameter(&"spot_count")) == 2,
		"an entry and an exit painted on the thigh's own voxels")
	var a: PackedVector4Array = mat.get_shader_parameter(&"spot_a") if mat else PackedVector4Array()
	var mi := _mesh(s, Vitals.THIGH_L)
	var worst := 0.0
	for i in 2:
		var p := mi.global_transform * Vector3(a[i].x, a[i].y, a[i].z)
		worst = maxf(worst, _gap(mi, p))
	check(a.size() >= 2 and worst < 0.005, "both holes centred on the skin (worst %.1f mm off)" % (worst * 1000.0))
	var soak0 := float((mat.get_shader_parameter(&"spot_b") as PackedVector4Array)[0].w) if mat else 0.0
	for spot: Dictionary in marks._spots.values():
		spot.lost = 1.0  # a litre out of the femoral
	marks.paint_skin()
	var soak1 := float((mat.get_shader_parameter(&"spot_b") as PackedVector4Array)[0].w) if mat else 0.0
	check(soak1 > soak0 * 4.0 and marks.skin.drawn().has(shin), "a litre lost: the soak spreads (%.0f -> %.0f units) and runs on down onto the shin" % [soak0, soak1])
	var c: PackedVector4Array = mat.get_shader_parameter(&"spot_c")
	check(c[0].y > 0.99, "wet while it bleeds")
	s.vitals.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	s.vitals.server_apply_treatment(&"hemostatic_gauze", Vitals.THIGH_L)
	for spot: Dictionary in marks._spots.values():
		spot.stopped = WoundMarks._now() - WoundSkin.DRY_S * 0.5
	marks.paint_skin()
	c = mat.get_shader_parameter(&"spot_c")
	var flows: Array = marks._spots.values().map(func(sp: Dictionary) -> float: return float(sp.flow))
	check(c[0].y < 0.6 and c[0].y > 0.4, "stopped: it dries (%.2f wet half-way through; flow now %s)" % [c[0].y, flows])
	s.vitals.server_reset_health()
	await _frames(2)
	check(not marks.skin.drawn().has(thigh), "healed: the paint goes")
	s.queue_free()
	await _frames(3)


func _test_face() -> void:
	print("A wound on the face")
	var s := await _man(SPOT + Vector3(20, 0, 0))
	var marks := _marks(s)
	_wound(s, Vitals.FACE, "muscle", 0.3, &"", Vector3(0.04, 1.6, -0.11))
	await _seconds(1.0)
	var head := s.model.part_node(Vitals.HEAD)
	var head_mi := _mesh(s, Vitals.HEAD)
	var faces := 0
	for f: Node in head_mi.get_children():
		if String(f.name).begins_with("Face_") and f.get_node_or_null(^"WoundSkin") != null and (f.get_node(^"WoundSkin") as MeshInstance3D).visible:
			faces += 1
	check(marks.skin.drawn().has(head) and faces > 0, "painted on the head and on the face's moving parts (%d of them)" % faces)
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _test_bruises() -> void:
	print("Bruises from armour stops")
	var s := await _man(SPOT + Vector3(22, 0, 0), 1, ["m4a1", "helmet", "plate_carrier"])
	var marks := _marks(s)
	var hb := BlastGore._hitbox(s, Vitals.HEAD)
	var at := Warheads.hitbox_point(hb, Vector3(0, 0.03, -0.1))
	s.vitals.server_impact(Vitals.HEAD, Vitals.INTERMEDIATE, 300.0, 400.0, at)
	s.vitals.server_impact(Vitals.HEAD, Vitals.INTERMEDIATE, 300.0, 400.0, at)  # the same spot: deeper, not another
	await _seconds(1.0)
	var recs := marks.bruise_records()
	var skin_gap := INF
	if recs.size() == 1 and _mesh(s, Vitals.HEAD) != null:
		skin_gap = _gap(_mesh(s, Vitals.HEAD), marks.to_world(Vitals.HEAD, BlastGore.to_vec(recs[0].a)))
	check(recs.size() == 1 and float(recs[0].s) > 0.6 and skin_gap < 0.01,
		"a helmet stop bruises the head under it, twice in one spot deeper (%s, %.1f mm off the skin)" % [recs, skin_gap * 1000.0])
	var mat := marks.skin.material_of(s.model.part_node(Vitals.HEAD))
	check(mat != null and int(mat.get_shader_parameter(&"bruise_count")) >= 1, "and it's painted there (on bare skin only, under the helmet)")
	var chest_hb := BlastGore._hitbox(s, Vitals.CHEST)
	if chest_hb:
		s.vitals.server_impact(Vitals.CHEST, Vitals.FULL_POWER, 300.0, 1500.0, Warheads.hitbox_point(chest_hb, Vector3(0, 0, -0.1)))
	await _seconds(1.0)
	check(marks.bruise_records().size() == 2, "a plate stop bruises the chest too (%d)" % marks.bruise_records().size())
	check(s.vitals.net_vitals.get("z", []).filter(func(g: Dictionary) -> bool: return String(g.get("k", "")) == "b").size() == 2,
		"both go out to every peer with the body's gore records")
	s.vitals.server_reset_health()
	await _frames(2)
	check(marks.bruise_records().is_empty(), "healed: gone")
	s.queue_free()
	await _frames(3)


func _test_reduced() -> void:
	print("Reduced gore")
	BodyDeform.gore_override = "reduced"
	var s := await _man(SPOT + Vector3(24, 0, 0))
	var marks := _marks(s)
	_wound(s, Vitals.THIGH_L, "venous", 0.6, &"", Vector3(-0.075, 0.62, -0.085))
	await _frames(3)
	var mat := marks.skin.material_of(s.model.part_node(Vitals.THIGH_L))
	var a: PackedVector4Array = mat.get_shader_parameter(&"spot_a") if mat else PackedVector4Array()
	var unit := 1.0 / WoundSkin.base_of(_mesh(s, Vitals.THIGH_L)).basis.get_scale().x
	check(mat != null and float(mat.get_shader_parameter(&"torn")) == 0.0 and absf(a[0].w - WoundMarks.ENTRY_SIZE * 0.5 * WoundSkin.REDUCED_HOLE * unit) < 0.01,
		"no torn flesh or cloth, the hole smaller")
	BodyDeform.gore_override = "full"
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


# --- How it works (Captain, 2026-10-27: "more realistic in how it works") -------------------------

func _test_runs_follow_gravity() -> void:
	print("Blood runs the way down is now")
	var s := await _man(SPOT + Vector3(26, 0, 0))
	var marks := _marks(s)
	_wound(s, Vitals.THIGH_L, "venous", 0.8, &"", Vector3(-0.075, 0.62, -0.085))
	await _seconds(1.0)
	var hole: Dictionary = marks._spots.values()[0].holes[0]
	var standing := (hole.runs as Array).size()
	var low: Variant = marks._lowest_point(marks._spots.values()[0])
	var hole_y := marks.to_world(Vitals.THIGH_L, hole.at).y
	check(standing == 1 and low is Vector3 and (low as Vector3).y < hole_y - 0.03,
		"standing: one run down the leg, and it drips from below the hole, where the blood gets to (%.2f m under it)" % [hole_y - (low as Vector3).y if low is Vector3 else -1.0])
	var m: WoundModel = s.vitals._model
	m.knockout_left = 120.0  # knocked out: he goes down (the ragdoll) and lies there
	m.update_state(0.0)
	s.vitals._after_change(true)
	s.set_physics_process(true)
	await _seconds(3.0)
	var runs: Array = hole.runs
	check(runs.size() >= 2 and runs.size() <= WoundMarks.MAX_RUNS and rad_to_deg(Vector3(runs[0].dir).angle_to(runs[-1].dir)) > WoundMarks.RUN_TURN_DEG and float(runs[0].to) >= 0.0,
		"down on the ground: a new run the way down is now, the first left where it ran (%d runs, %.0f degrees apart)"
		% [runs.size(), rad_to_deg(Vector3(runs[0].dir).angle_to(runs[-1].dir)) if runs.size() > 1 else 0.0])
	var mat := marks.skin.material_of(s.model.part_node(Vitals.THIGH_L))
	check(mat != null and int(mat.get_shader_parameter(&"spot_count")) >= 2, "both runs painted")
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _test_spurts() -> void:
	print("An arterial bleed spurts with the heartbeat")
	var s := await _man(SPOT + Vector3(28, 0, 0))
	var marks := _marks(s)
	_wound(s, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l", Vector3(-0.075, 0.62, -0.085))
	var fast := 0
	for i in 60:
		await get_tree().process_frame
		for d: Dictionary in marks._drips:
			if Vector3(d.vel).length() > 0.8 and d.get("speck", false):
				fast += 1
	check(fast > 0, "jets of drops out of the hole (%d seen in the air)" % fast)
	s.vitals._model.arrest = true
	s.vitals._model.heart_rate = 0.0
	await _seconds(0.3)
	marks._drips.clear()
	var after := 0
	for i in 40:
		await get_tree().process_frame
		for d: Dictionary in marks._drips:
			if Vector3(d.vel).length() > 0.8:
				after += 1
	check(after == 0, "the heart stopped: no more spurts (%d)" % after)
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _test_seeping_dressing() -> void:
	print("Blood through a dressing")
	var s := await _man(SPOT + Vector3(30, 0, 0))
	var marks := _marks(s)
	var at := Vector3(0.25, 0.95, -0.05)
	_wound(s, Vitals.FOREARM_R, "muscle", 0.3, &"", at)
	await _seconds(1.0)
	s.vitals.server_apply_treatment(&"pressure_bandage", Vitals.FOREARM_R)
	await _frames(3)
	var spot: Dictionary = marks._spots.values()[0]
	var hole: Dictionary = spot.holes[0]
	var pivot := BodyVolume.pivot_at(Vitals.FOREARM_R)
	var bloody := func() -> int:
		var n := 0
		var plain: Array = hole.dressing
		var now: Array = marks._bloodied(spot, hole, pivot)
		for i in mini(plain.size(), now.size()):
			if Color(now[i][2]) != Color(plain[i][2]):
				n += 1
		return n
	var clean: int = bloody.call()
	check(marks.dressing_on(Vitals.FOREARM_R) == &"bandage" and float(spot.seep) == 0.0, "bandaged and controlled: nothing comes through (%d bloodied at its edges)" % clean)
	# A vein under it the bandage doesn't hold.
	_wound(s, Vitals.FOREARM_R, "venous", 0.9, &"", at)
	for sp: Dictionary in marks._spots.values():
		sp.lost = maxf(float(sp.lost), 0.0)
	await _seconds(2.0)
	var seeped: int = bloody.call()
	check(float(spot.seep) > 0.0 and seeped > clean + 5, "still bleeding under it: it reddens from the middle (%d cells, %.3f L through)" % [seeped, float(spot.seep)])
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
