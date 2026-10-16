class_name BodyDeform
extends Node
## Procedural body damage (Captain, 2026-10-16: "the wounds are really engaging but we also need
## something else there, maybe more body deform?" ... "the body deform stuff should be
## procedural"): every hole a round makes is carved out of the hit part's own voxels, not drawn
## from pre-made damage. An entry knocks out a ragged crater; an exit blows out a bigger one.
## Each crater's edge is torn flesh (WOUND, darker at the bottom), its shape jagged by a noise
## seeded from the spot, so no two match and every peer carves the same ones.
##
## Piece by piece (Captain: "it takes a lot of 556 to lose an arm, or head but not as much 308,
## injuries can still be packed and such so dont make it too extreme until after someone is
## dead"): each round scores its energy on the part it hit (Vitals.round_damage: 5.56 ~1, .308 and
## 7.62x54R ~2, .338 ~4; a .50 just kills, Vitals.LETHAL_J). Craters size to it and widen as the
## part's score climbs, so a limb visibly tears up before it goes. Alive, a limb comes off only
## when the host tears it off (Vitals._check_amputation: a broken bone and SEVER_ALIVE points), as
## an arterial "amputation" bleed a tourniquet stops, so a good medic can save him. Dead, the
## round that takes a part past SEVER_DEAD cuts it, and the head can go (HEAD_DEAD). The cut is where the
## craters are; SEVER_SLAB voxels are torn away, both faces torn flesh, and everything past the
## cut (the rest of the part and what it carries: shin and boot, forearm and glove, the helmet)
## drops as one loose piece. All of it from the replicated wounds (part, "at"/"out", round
## class) and Vitals.is_dead, so every peer cuts the same limb at the same place.
##
## The first hole on a part gives that soldier their own raster of it (VoxelArt.raster_copy);
## later holes carve the same raster. Rasterising, carving and meshing run on a worker thread
## (a 0.5 cm part is tens of ms); the mesh goes on when it's done. With every wound gone (reset,
## respawn) the parts go back to the shared mesh, hidden parts show again, pieces go.

## Crater radius in the body's 0.5 cm voxels, and how far the jagged edge strays from it.
const ENTRY_R := 2.4
const EXIT_R := 4.6
const JAG := 0.45
## The torn-flesh rim round each crater, in voxels.
const RIM := 1.6
## How far in from the skin a crater is centred (voxels): it bites into the part.
const SINK := 1.0
## A round's crater size by class, and how much wider craters get on a part that's taken a lot
## (up to WIDEN at the part's sever score) and on the dead (DEAD_SIZE).
const CLASS_SIZE := {&"pistol": 0.8, &"intermediate": 1.0, &"full_power": 1.5, &"fragment": 0.7}
const WIDEN := 0.6
const DEAD_SIZE := 1.25
## Points a round scores on the part it hits, by class (unknown: intermediate).
const DAMAGE := {&"pistol": 0.5, &"intermediate": 1.0, &"full_power": 2.5, &"fragment": 0.6}
const SEVER_ALIVE := 10.0
const SEVER_DEAD := 4.0
const HEAD_DEAD := 3.0
const SEVER_SLAB := 2
const LIMBS: Array[StringName] = [Vitals.THIGH_L, Vitals.THIGH_R, Vitals.SHIN_L, Vitals.SHIN_R,
	Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]
const HEAD_PARTS: Array[StringName] = [Vitals.HEAD, Vitals.FACE]
## Craters a part takes before more stop changing it.
const MAX_PER_PART := 18
## A loose piece's push off the body, and how many lie about per body at most.
const PIECE_PUSH := 1.4
const MAX_PIECES := 5
const PIECE_LIFE_S := Vector2(360.0, 420.0)

var model: CharacterModel
var vitals: Vitals
var body := ""
var _done := {}       # hole key -> true
var _parts := {}      # part pivot (Node3D) -> {"buffer", "model", "variant", "todo", "busy", "count", "ys"}
var _score := {}      # part -> points (DAMAGE)
var _severed := {}    # part -> true
var _pieces: Array[Node3D] = []   # loose pieces in the world
var _hidden: Array[Node3D] = []   # parts hidden because they went with a piece
var _tasks: Array[int] = []  # worker tasks not waited for yet (WorkerThreadPool wants every one waited for, or the game can't quit)


func setup(p_model: CharacterModel, p_vitals: Vitals) -> void:
	model = p_model
	vitals = p_vitals
	body = BodyVolume.body_of(p_model)
	vitals.changed.connect(_rebuild)
	_rebuild()


## Craters carved on `part` so far (tests, debug).
func craters_on(part: StringName) -> int:
	var pivot := model.part_node(part) if model else null
	return int((_parts.get(pivot, {}) as Dictionary).get("count", 0))


## Points `part` has taken (DAMAGE), and the limbs / head cut off so far.
func score_of(part: StringName) -> float:
	return float(_score.get(_bone_part(part), 0.0))


func severed() -> Array:
	return _severed.keys()


func pieces() -> Array[Node3D]:
	return _pieces


func _rebuild() -> void:
	if not is_instance_valid(vitals) or not is_instance_valid(model):
		return
	var dead := vitals.is_dead()
	var any := false
	var score := {}
	var broken := {}
	var counted := {}
	var amputated := {}  # part -> true: the host tore it off (Vitals.AMPUTATION)
	var fresh := false  # a round landed since last time
	for w: Dictionary in vitals.wound_list():
		var part := _bone_part(w.part)
		if String(w.kind) == "fracture":
			broken[part] = true
		if w.get("name") == Vitals.AMPUTATION:
			amputated[part] = true
		var at: Variant = w.get("at")
		if not at is Vector3:
			continue
		any = true
		var rc := StringName(w.get("round_class", &""))
		var key := "%s%s" % [w.part, at]
		if not counted.has(key):  # one round, however many wounds it made
			counted[key] = true
			score[part] = float(score.get(part, 0.0)) + _points(w, rc)
		if _done.has(key):
			continue
		_done[key] = true
		fresh = true
		_score = score.duplicate()  # craters size to the damage so far (this round included)
		var size := _crater_size(w, rc) * (DEAD_SIZE if dead else 1.0) * (1.0 + WIDEN * clampf(float(score.get(part, 0.0)) / _threshold(part, dead), 0.0, 1.0))
		_queue(w.part, at, false, size)
		var out: Variant = w.get("out")
		if out is Vector3:
			_queue(w.part, out, true, size)
	_score = score
	if not any and not _done.is_empty():
		_restore()
		return
	for part: StringName in LIMBS + [Vitals.HEAD]:
		if _severed.has(part) or _gone(part):
			continue
		# Alive: only what the host tore off (it bleeds, a tourniquet saves him). Dead: enough
		# damage, cut by the round that tipped it (not the moment he dies).
		if amputated.has(part) or (dead and fresh and float(score.get(part, 0.0)) >= _threshold(part, true)):
			_severed[part] = true
			_queue_sever(part)


## What a round scored on its part: its energy (Vitals.round_damage: 5.56 ~1, 7.62x51 and x54R
## ~2, .338 ~4, .50 ~10), else by class (DAMAGE).
static func _points(w: Dictionary, rc: StringName) -> float:
	var dmg := float(w.get("dmg", 0.0))
	return dmg if dmg > 0.0 else float(DAMAGE.get(rc, DAMAGE[&"intermediate"]))


## A round's crater size: bigger with its energy (a 5.56 1, a .308 ~1.3, capped at 2.2), else by class.
static func _crater_size(w: Dictionary, rc: StringName) -> float:
	var dmg := float(w.get("dmg", 0.0))
	return clampf(0.7 + 0.3 * dmg, 0.7, 2.2) if dmg > 0.0 else float(CLASS_SIZE.get(rc, 1.0))

## Points at which `part` comes off.
static func _threshold(part: StringName, dead: bool) -> float:
	if part == Vitals.HEAD:
		return HEAD_DEAD if dead else INF
	return SEVER_DEAD if dead else SEVER_ALIVE


## The part whose bone carries `part` (face and neck hits count on the head).
static func _bone_part(part: StringName) -> StringName:
	return Vitals.HEAD if part in HEAD_PARTS or part == Vitals.NECK else part


## Whether `part` already went with a piece cut off above it (a shin when the thigh went).
func _gone(part: StringName) -> bool:
	var pivot := model.part_node(part)
	if pivot == null:
		return true
	var n: Node = pivot
	while n != null and n != model:
		if n in _hidden:
			return true
		n = n.get_parent()
	return false


## Every carved part back to the shared mesh, hidden parts shown, pieces gone (wounds reset).
func _restore() -> void:
	_done.clear()
	_score.clear()
	_severed.clear()
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()
	for part_node in _hidden:
		if is_instance_valid(part_node):
			part_node.visible = true
	_hidden.clear()
	for pivot: Node3D in _parts.keys():
		var state: Dictionary = _parts[pivot]
		state.todo.clear()
		state.count = 0
		state.ys = []
		state.buffer = null
		var mi := _mesh_of(pivot)
		if mi and not state.busy:
			mi.mesh = VoxelArt.mesh(state.model, state.variant)


func _state_for(pivot: Node3D) -> Dictionary:
	var state: Dictionary = _parts.get(pivot, {})
	if state.is_empty():
		state = {"buffer": null, "model": String(pivot.get_meta(&"voxel_model")), "variant": String(pivot.get_meta(&"voxel_variant", "")),
			"todo": [], "busy": false, "count": 0, "ys": []}
		_parts[pivot] = state
	return state


func _queue(part: StringName, at: Vector3, exit: bool, size: float) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model") or _gone(part):
		return
	var state := _state_for(pivot)
	if int(state.count) >= MAX_PER_PART:
		return
	state.count = int(state.count) + 1
	# Rest-pose body point -> the part's mesh voxels (as WoundMarks places its marks on the bone).
	var n := WoundMarks._outward(part, at)
	var skin: Variant = BodyVolume.surface(part, at, n, 0.05, body)
	var p: Vector3 = (skin if skin is Vector3 else at) - BodyVolume.pivot_at(part, body)
	var centre := (p - mi.position) / mi.scale.x + Vector3.ONE  # +1: the raster's mesher padding
	var inward := -(mi.basis.inverse() * n).normalized()
	(state.ys as Array).append(centre.y)
	state.todo.append({"centre": centre + inward * SINK, "r": (EXIT_R if exit else ENTRY_R) * size, "salt": hash("%s%s%s" % [part, at, exit])})
	_kick(pivot)


## Cuts `part` through: a limb where its craters are, the head low on the neck.
func _queue_sever(part: StringName) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model"):
		return
	var state := _state_for(pivot)
	var ys: Array = state.ys
	var cut := -1.0  # worker picks: the head just above its lowest voxels
	if part != Vitals.HEAD and not ys.is_empty():
		cut = 0.0
		for y: float in ys:
			cut += y
		cut /= ys.size()
	state.todo.append({"sever": true, "cut": cut, "far_up": part == Vitals.HEAD})
	_kick(pivot)


## Lets go of finished worker tasks; `all` waits for the rest too (leaving the tree).
func _reap(all := false) -> void:
	for task in _tasks.duplicate():
		if all or WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(task)


func _exit_tree() -> void:
	_reap(true)

## Starts the part's worker if it's idle and has work waiting.
func _kick(pivot: Node3D) -> void:
	var state: Dictionary = _parts.get(pivot, {})
	if state.is_empty() or state.busy or (state.todo as Array).is_empty():
		return
	state.busy = true
	var jobs: Array = state.todo.duplicate()
	state.todo.clear()
	state.task = WorkerThreadPool.add_task(BodyDeform._work.bind(weakref(self), pivot, state.buffer, state.model, state.variant, jobs))
	_tasks.append(state.task)


## Worker thread: (the first time) rasterise the part, carve, cut. Meshing is the main thread's.
static func _work(ref: WeakRef, pivot: Node3D, buffer: VoxelBuffer, model_name: String, variant: String, jobs: Array) -> void:
	if buffer == null:
		buffer = VoxelArt.raster_copy(model_name, variant)
	var piece: VoxelBuffer = null
	for job: Dictionary in jobs:
		if job.get("sever", false):
			var cut := float(job.cut)
			if cut < 0.0:
				cut = _lowest_solid(buffer) + 4.0
			piece = split(buffer, roundi(cut), bool(job.far_up))
		else:
			carve(buffer, job.centre, float(job.r), int(job.salt))
	BodyDeform._deliver.call_deferred(ref, pivot, buffer, piece)  # meshing goes through the renderer: main thread only


## Main thread: hands the worker's result back, unless the body went while it worked.
static func _deliver(ref: WeakRef, pivot: Variant, buffer: VoxelBuffer, piece: VoxelBuffer) -> void:
	var me := ref.get_ref() as BodyDeform
	if me and is_instance_valid(me) and is_instance_valid(pivot):
		me._done_work(pivot, buffer, piece)


func _done_work(pivot: Node3D, buffer: VoxelBuffer, piece: VoxelBuffer) -> void:
	_reap()
	if not is_instance_valid(pivot) or not _parts.has(pivot):
		return
	var state: Dictionary = _parts[pivot]
	state.busy = false
	if int(state.count) == 0 and _severed.is_empty():  # reset while it worked
		var shared := _mesh_of(pivot)
		if shared:
			shared.mesh = VoxelArt.mesh(state.model, state.variant)
		return
	state.buffer = buffer
	var mesher := VoxelArt.mesher_for(state.model, state.variant)
	var mesh := mesher.build_mesh(buffer, [])
	var piece_mesh: Mesh = mesher.build_mesh(piece, []) if piece else null
	var mi := _mesh_of(pivot)
	if mi and mesh:
		mi.mesh = mesh
	if piece_mesh and mi:
		_drop(pivot, mi, piece_mesh)
	_kick(pivot)


## The cut-off piece as a loose body in the world: the far side of the part's raster plus the
## parts and gear it carries (copied, the originals hidden), pushed off the body.
func _drop(pivot: Node3D, mi: MeshInstance3D, piece_mesh: Mesh) -> void:
	var world := model.get_tree().current_scene if model.is_inside_tree() else null
	var level := CompoundLevel.current(model) if model.is_inside_tree() else null
	var parent: Node = level if level else world
	if parent == null:
		return
	while _pieces.size() >= MAX_PIECES:
		var old: Node3D = _pieces.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var rb := RigidBody3D.new()
	rb.name = "Severed_%s" % pivot.name
	rb.collision_layer = Ragdoll.LAYER
	rb.collision_mask = 1
	rb.mass = 4.0
	var look := MeshInstance3D.new()
	look.mesh = piece_mesh
	look.material_override = mi.material_override
	look.layers = mi.layers
	look.transform = mi.transform
	rb.add_child(look)
	for i in range(1, pivot.get_child_count()):
		var child := pivot.get_child(i) as Node3D
		if child == null or not child.visible or child is MultiMeshInstance3D:
			continue  # wound marks stay with the body
		var copy := child.duplicate() as Node3D
		rb.add_child(copy)
		child.visible = false
		_hidden.append(child)
	var box := _bounds(rb)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size.max(Vector3.ONE * 0.04)
	shape.shape = b
	shape.position = box.get_center()
	rb.add_child(shape)
	parent.add_child(rb)
	rb.global_transform = pivot.global_transform
	var away := pivot.global_position - model.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	rb.apply_central_impulse((away * PIECE_PUSH + Vector3.UP * 0.6) * rb.mass * 0.5)
	rb.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.3)
	_pieces.append(rb)
	var ref: WeakRef = weakref(rb)
	rb.get_tree().create_timer(randf_range(PIECE_LIFE_S.x, PIECE_LIFE_S.y)).timeout.connect(func() -> void:
		var p := ref.get_ref() as Node
		if p and is_instance_valid(p):
			p.queue_free())  # Captain, 2026-10-16: ~6-7 min for most things


## Every mesh under `root` in its space, merged (empty meshes skipped).
static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var t: Transform3D = item[1]
		for child in node.get_children():
			var c3 := child as Node3D
			if c3 == null:
				continue
			var ct := t * c3.transform
			var vi := c3 as MeshInstance3D
			if vi and vi.mesh:
				var a: AABB = ct * vi.mesh.get_aabb()
				box = a if first else box.merge(a)
				first = false
			stack.append([c3, ct])
	return box if not first else AABB(Vector3(-0.05, -0.2, -0.05), Vector3(0.1, 0.2, 0.1))


## A ragged crater in `buffer` round `centre` (voxels) of about radius `r`: solid voxels inside
## go, those just outside it turn to torn flesh (darker deeper in). Noise from `salt` jags the
## edge, so the same hole always carves the same way. Returns the voxels knocked out.
static func carve(buffer: VoxelBuffer, centre: Vector3, r: float, salt: int) -> int:
	var size := buffer.get_size()
	var reach := int(ceil(r * (1.0 + JAG) + RIM))
	var c := Vector3i(roundi(centre.x), roundi(centre.y), roundi(centre.z))
	var removed := 0
	for x in range(maxi(c.x - reach, 1), mini(c.x + reach + 1, size.x - 1)):
		for y in range(maxi(c.y - reach, 1), mini(c.y + reach + 1, size.y - 1)):
			for z in range(maxi(c.z - reach, 1), mini(c.z + reach + 1, size.z - 1)):
				var v := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR)
				if v == VoxelArt.C.EMPTY:
					continue
				var d := Vector3(x, y, z) - centre
				var dist := d.length()
				var edge := r * (1.0 + JAG * _jag(d, salt))
				if dist <= edge:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					removed += 1
				elif dist <= edge + RIM:
					var deep := dist - edge < RIM * 0.5
					buffer.set_voxel(VoxelArt.C.WOUND_DARK if deep else VoxelArt.C.WOUND, x, y, z, VoxelBuffer.CHANNEL_COLOR)
	return removed


## Cuts `buffer` through at layer `cut` (voxel y): the far side (below the cut for a limb, above
## it with `far_up`: the head) moves into a new buffer, returned; SEVER_SLAB layers each side of
## the cut are torn away, ragged; the two faces left turn to torn flesh.
static func split(buffer: VoxelBuffer, cut: int, far_up := false) -> VoxelBuffer:
	var size := buffer.get_size()
	var piece := VoxelBuffer.new()
	piece.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	piece.create(size.x, size.y, size.z)
	piece.fill(VoxelArt.C.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	for x in range(1, size.x - 1):
		for z in range(1, size.z - 1):
			var ragged := int(round(sin(x * 1.7 + z * 0.9) + cos(z * 2.3 - x * 0.4)))  # -2..2 layers
			for y in range(1, size.y - 1):
				var v := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR)
				if v == VoxelArt.C.EMPTY:
					continue
				var off := (y - cut) * (-1 if far_up else 1)  # > 0: the body's side; < 0: the far side
				if absi(off - ragged) <= SEVER_SLAB:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off < ragged:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					var face := off - ragged >= -SEVER_SLAB - 2
					piece.set_voxel(VoxelArt.C.WOUND if face else v, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off - ragged <= SEVER_SLAB + 2:
					buffer.set_voxel(VoxelArt.C.WOUND_DARK if off - ragged <= SEVER_SLAB + 1 else VoxelArt.C.WOUND, x, y, z, VoxelBuffer.CHANNEL_COLOR)
	return piece


## The lowest layer (voxel y) with anything in it.
static func _lowest_solid(buffer: VoxelBuffer) -> int:
	var size := buffer.get_size()
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			for z in range(1, size.z - 1):
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
					return y
	return 1


## -1..1 by direction from the centre: a few lumps round the crater, seeded.
static func _jag(d: Vector3, salt: int) -> float:
	if d.length_squared() < 0.0001:
		return 0.0
	var u := d.normalized()
	var a := float(salt % 997) * 0.37
	var b := float((salt / 997) % 991) * 0.53
	return clampf(0.6 * sin(u.x * 3.1 + a) * cos(u.y * 2.7 + b) + 0.4 * sin(u.z * 4.3 + a * 1.7 + u.x * 2.0), -1.0, 1.0)


static func _mesh_of(pivot: Node3D) -> MeshInstance3D:
	if pivot == null or not is_instance_valid(pivot) or pivot.get_child_count() == 0:
		return null
	return pivot.get_child(0) as MeshInstance3D
