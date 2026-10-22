class_name VehicleHull
extends Node3D
## A vehicle's look and its 5 cm voxels (wave 5): Captain's VehicleArt model, and the damage
## drawn on this vehicle's own copy of it the way VoxelArmor carves plates: holes where
## rounds went through, bright scuffs where they glanced off, scorch around big hits and over
## a burnt-out wreck.
##
## Undamaged, a vehicle shows VehicleArt.instance(): the hull mesh cached per model and paint
## scheme, shared by every vehicle of that look. The voxels behind it (the model's canvas) are
## cached per model too. The first edit switches this vehicle to chunks of CHUNK voxels: the
## untouched chunks show meshes shared per model and scheme (built once, CHUNK at a time,
## inside the frame budget), and only a chunk this vehicle has edits in gets its own mesh,
## rebuilt when it changes. So a hit re-meshes one small chunk (about a millisecond), never the
## whole hull, and never another vehicle's. All meshing goes through one queue that spends at
## most BUDGET_MS a frame (measured in the vehicles suite).
##
## Edits are a list of operations (Vehicle.net_carves: [x, y, z (metres, vehicle frame), radius,
## kind]) applied the same way on every peer, saved with the zone and sent to late joiners.
## The host also marches rounds through the voxels (first_solid), so a round meets the hull
## where the model really is, not just its collision box.
##
## Reads Captain's VehicleArt (scripts/art/vehicle_art.gd): instance() for the look, and its
## canvas builder, mesher and materials (_canvas_for, _get_mesher, _get_material,
## _get_window_material) for the voxels. A canvas has two sets of voxels: `buffer`, what rounds
## meet (first_solid, voxel_at), and `look`, what's drawn: the same with the cabins hollowed and
## furnished and their windows see-through (VehicleInteriors). Edits land on both; a mark
## (scuff, scorch, a hole's ring) is only drawn where the look has a voxel, so a hidden solid
## cabin never shows as a black lump inside.
##
## A turret and its gun (VehicleTurret) are separate parts with their own voxels and meshes
## (the art's "Turret" and "Turret/Gun" nodes): pose_turret() turns them, and first_solid meets
## them where they are now. Edits (holes, marks) land on the hull only.

## Voxels per chunk side. 24 voxels (1.2 m) re-mesh in about 1 ms (32: 2-3 ms; measured on the
## M-ATV, MaxxPro, technical and AAV-7).
const CHUNK := 24
## Meshing spends at most this much of a frame (ms); at least one chunk a frame goes.
const BUDGET_MS := 4.0
## Most voxels one vehicle's edits may touch (a wreck that has taken everything stops there).
const MAX_EDITS := 20000
## Edit kinds (net_carves).
const HOLE := 0     ## a round through: the voxels go, a scorch ring round the hole
const SCUFF := 1    ## a round that glanced off: a bright mark
const SCORCH := 2   ## fire or blast: blackened
## Wreck: the whole hull darkened (albedo times this).
const WRECK_TINT := Color(0.24, 0.22, 0.2)

static var _canvases := {}   # model -> {"buffer": VoxelBuffer, "look": VoxelBuffer, "size": Vector3i, "vs": float}
static var _tasks := {}      # model -> WorkerThreadPool task id (canvas being built)
static var _pending := {}    # model -> Canvas built on a worker
static var _mutex := Mutex.new()
static var _shared := {}     # "model|scheme" -> {chunk Vector3i: Mesh or null}
static var _queue: Array = []  # [weakref(hull) or null, kind "shared"/"own", key, chunk]
static var _pump_frame := -1
## Test readouts: the last frame's meshing time, the slowest single chunk, chunks meshed.
static var last_frame_ms := 0.0
static var worst_chunk_ms := 0.0
static var chunks_meshed := 0

var model := "matv"
var scheme := ""
## VehicleArt.instance(): the hull mesh and rotors.
var art: Node3D
var _hull_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _edits := {}            # Vector3i voxel -> palette index (EMPTY for a hole)
var _applied := 0           # how many ops of the vehicle's list are applied
var _chunked := false
var _chunk_nodes := {}      # chunk -> MeshInstance3D
var _own := {}              # chunk -> VoxelBuffer (this vehicle's copy, with its edits)
var _wrecked := false
## The turret's pose (VehicleTurret, set by the vehicle): where first_solid meets its parts.
var turret: VehicleTurret
var _turret_node: Node3D
var _gun_node: Node3D


func _init(p_model := "matv", p_scheme := "") -> void:
	model = p_model
	scheme = p_scheme if p_scheme != "" else String(VehicleArt.MODELS.get(p_model, ["od"])[0])
	name = "Hull"


func _ready() -> void:
	art = VehicleArt.instance(model, scheme)
	add_child(art)
	_hull_mesh = art.get_node_or_null(^"Hull") as MeshInstance3D
	_material = (VehicleArt._get_material() as StandardMaterial3D).duplicate()
	if _wrecked:
		_material.albedo_color = WRECK_TINT  # set_wrecked came before the tree (a saved wreck)
	_dress(_hull_mesh)
	_turret_node = art.get_node_or_null(^"Turret") as Node3D
	_gun_node = art.get_node_or_null(^"Turret/Gun") as Node3D
	for mi in _part_meshes():
		_dress(mi)
	VehicleHull.prewarm(model)


func _process(_delta: float) -> void:
	VehicleHull._pump()


# --- The model's voxels (cached per model) ------------------------------------------------

## Starts building `model`'s canvas on a worker thread (the first build of each model takes
## 100-300 ms), so it's ready before the first hit needs it.
static func prewarm(p_model: String) -> void:
	if _canvases.has(p_model) or _tasks.has(p_model) or not VehicleArt.MODELS.has(p_model):
		return
	_tasks[p_model] = WorkerThreadPool.add_task(VehicleHull._build_canvas.bind(p_model), false, "VehicleHull canvas")


## Waits for every canvas still building (at quit: GameState._exit_tree). Returns how many were.
static func finish_tasks() -> int:
	var n := _tasks.size()
	for p_model: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[p_model])
	_tasks.clear()
	return n


static func _build_canvas(p_model: String) -> void:
	var c: Variant = VehicleArt._canvas_for(p_model)
	_mutex.lock()
	_pending[p_model] = c
	_mutex.unlock()


## The model's voxels: {"buffer" (VoxelBuffer with VehicleArt's 1-voxel padding: what rounds
## meet), "look" (the same size: what's drawn), "size" (voxels), "vs" (metres per voxel)}. Waits for the worker if it's still building.
static func canvas(p_model: String) -> Dictionary:
	if _canvases.has(p_model):
		return _canvases[p_model]
	if not _tasks.has(p_model):
		prewarm(p_model)
	if _tasks.has(p_model):
		WorkerThreadPool.wait_for_task_completion(_tasks[p_model])
		_tasks.erase(p_model)
	_mutex.lock()
	var c: Variant = _pending.get(p_model)
	_pending.erase(p_model)
	_mutex.unlock()
	if c == null:
		c = VehicleArt._canvas_for(p_model)
	_canvases[p_model] = {"buffer": c.buffer, "look": c.look if c.look else c.buffer, "size": c.size, "vs": c.vs, "parts": c.parts}
	return _canvases[p_model]


## Whether the canvas is built (tests, prewarming).
static func is_ready(p_model: String) -> bool:
	if _canvases.has(p_model):
		return true
	_mutex.lock()
	var done := _pending.has(p_model)
	_mutex.unlock()
	return done


# --- Voxel space ----------------------------------------------------------------------------

## The voxel holding a point in the vehicle's frame (metres).
func voxel_of(local: Vector3) -> Vector3i:
	var c := canvas(model)
	var vs: float = c.vs
	var size: Vector3i = c.size
	return Vector3i(floori(local.x / vs + size.x * 0.5), floori(local.y / vs), floori(local.z / vs + size.z * 0.5))


## A voxel's centre in the vehicle's frame (metres).
func local_of(v: Vector3i) -> Vector3:
	var c := canvas(model)
	var vs: float = c.vs
	var size: Vector3i = c.size
	return Vector3((v.x + 0.5 - size.x * 0.5) * vs, (v.y + 0.5) * vs, (v.z + 0.5 - size.z * 0.5) * vs)


## The palette index (VehicleArt.P) at voxel `v`, this vehicle's edits included.
func voxel_at(v: Vector3i) -> int:
	if _edits.has(v):
		return int(_edits[v])
	var c := canvas(model)
	var size: Vector3i = c.size
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= size.x or v.y >= size.y or v.z >= size.z:
		return VehicleArt.P.EMPTY
	return (c.buffer as VoxelBuffer).get_voxel(v.x + 1, v.y + 1, v.z + 1, VoxelBuffer.CHANNEL_COLOR)


func solid(v: Vector3i) -> bool:
	return voxel_at(v) != VehicleArt.P.EMPTY


## The first solid voxel along a ray in the vehicle's frame, within `max_m` metres:
## {"hit": true, "voxel", "local" (where the ray meets it), "distance", "part" ("" the hull,
## or "Turret"/"Gun": then "voxel" is the part's voxel at rest)} or {"hit": false}.
func first_solid(from: Vector3, dir: Vector3, max_m: float) -> Dictionary:
	var c := canvas(model)
	var vs: float = c.vs
	var step := vs * 0.4
	var d := 0.0
	dir = dir.normalized()
	var last := Vector3i(-99999, 0, 0)
	# The parts at rest: each step's point taken back through the part's pose.
	var parts: Array = []
	if turret:
		for part: Dictionary in c.get("parts", []):
			var gun_part: bool = part.name == "Gun"
			var pose := turret.gun_transform() if gun_part else turret.turret_transform()
			parts.append([part, pose.affine_inverse(), turret.trunnion if gun_part else turret.pivot])
	while d <= max_m:
		var p := from + dir * d
		var v := voxel_of(p)
		if v != last:
			last = v
			if solid(v):
				return {"hit": true, "voxel": v, "local": p, "distance": d, "part": ""}
		for entry: Array in parts:
			var part: Dictionary = entry[0]
			var rest: Vector3 = (entry[1] as Transform3D) * p + (entry[2] as Vector3)
			var pv := voxel_of(rest)
			if _part_voxel(part, pv) != VehicleArt.P.EMPTY:
				return {"hit": true, "voxel": pv, "local": p, "distance": d, "part": String(part.name)}
		d += step
	return {"hit": false}


## A part's voxel (VehicleArt.P) at canvas voxel `v` (at rest).
static func _part_voxel(part: Dictionary, v: Vector3i) -> int:
	var at: Vector3i = v - (part.origin as Vector3i)
	var size: Vector3i = part.size
	if at.x < 0 or at.y < 0 or at.z < 0 or at.x >= size.x or at.y >= size.y or at.z >= size.z:
		return VehicleArt.P.EMPTY
	return (part.buffer as VoxelBuffer).get_voxel(at.x + 1, at.y + 1, at.z + 1, VoxelBuffer.CHANNEL_COLOR)


## Turns the turret's and the gun's meshes to the turret's pose.
func pose_turret() -> void:
	if turret == null:
		return
	if _turret_node:
		_turret_node.rotation = Vector3(0.0, turret.yaw, 0.0)
	if _gun_node:
		_gun_node.rotation = Vector3(turret.pitch, 0.0, 0.0)


## The turret's and gun's mesh nodes (empty without a turret).
func _part_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for path: NodePath in [^"Turret/Mesh", ^"Turret/Gun/Mesh"]:
		var mi := art.get_node_or_null(path) as MeshInstance3D if art else null
		if mi:
			out.append(mi)
	return out


# --- Edits ----------------------------------------------------------------------------------

## Applies the vehicle's edit list from `ops` (its net_carves): only the ones not applied yet.
func apply_ops(ops: Array) -> void:
	if ops.size() < _applied:
		_applied = 0  # a fresh list (a reload): start over
		_edits.clear()
	while _applied < ops.size():
		var op: Array = ops[_applied]
		_applied += 1
		if op.size() >= 5:
			_apply(Vector3(op[0], op[1], op[2]), float(op[3]), int(op[4]))


func edit_count() -> int:
	return _edits.size()


func is_chunked() -> bool:
	return _chunked


func _apply(at: Vector3, radius: float, kind: int) -> void:
	var c := canvas(model)
	var vs: float = c.vs
	var centre := voxel_of(at)
	var touched := {}
	match kind:
		SCUFF:
			_put_voxel(centre, VehicleArt.P.METAL, touched)
		HOLE:
			var r := maxi(roundi(radius / vs), 0)
			var ring := r + maxi(roundi(radius / vs), 1)
			for x in range(-ring, ring + 1):
				for y in range(-ring, ring + 1):
					for z in range(-ring, ring + 1):
						var v := centre + Vector3i(x, y, z)
						var d := Vector3(x, y, z).length()
						if d <= r + 0.5:
							_put_voxel(v, VehicleArt.P.EMPTY, touched)
						elif d <= ring + 0.5 and solid(v):
							_put_voxel(v, VehicleArt.P.BLACK, touched)
		SCORCH:
			var r := maxi(roundi(radius / vs), 1)
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					for z in range(-r, r + 1):
						var v := centre + Vector3i(x, y, z)
						if Vector3(x, y, z).length() <= r + 0.5 and solid(v) and voxel_at(v) != VehicleArt.P.GLASS:
							_put_voxel(v, VehicleArt.P.BLACK if (x + y + z) % 3 != 0 else VehicleArt.P.RUST, touched)
	if touched.is_empty():
		return
	_switch_to_chunks()
	for chunk: Vector3i in touched:
		_own.erase(chunk)  # rebuilt with the edits on its next turn
		_enqueue(self, "own", "", chunk)


func _put_voxel(v: Vector3i, value: int, touched: Dictionary) -> void:
	var size: Vector3i = canvas(model).size
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= size.x or v.y >= size.y or v.z >= size.z:
		return
	if voxel_at(v) == value or (_edits.size() >= MAX_EDITS and not _edits.has(v)):
		return
	_edits[v] = value
	# Every chunk whose padded copy holds this voxel (a voxel on a chunk's edge is in its
	# neighbour's padding too).
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var chunk := Vector3i(floori(float(v.x + dx) / CHUNK), floori(float(v.y + dy) / CHUNK), floori(float(v.z + dz) / CHUNK))
				touched[chunk] = true


## A burnt-out wreck: the whole hull darkened, the windows too (opaque).
func set_wrecked(on: bool) -> void:
	_wrecked = on
	if _material:
		_material.albedo_color = WRECK_TINT if on else Color.WHITE
		_dress(_hull_mesh)
		for chunk: Vector3i in _chunk_nodes:
			_dress(_chunk_nodes[chunk])
		for mi in _part_meshes():
			_dress(mi)


## This hull's materials on a mesh's surfaces: its own (tinted on a wreck) for the hull, the
## shared see-through one for the windows (VehicleArt.P.WINDOW's surface) unless burnt out.
func _dress(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or _material == null:
		return
	var window := VehicleArt._get_window_material()
	for i in mi.mesh.get_surface_count():
		var see_through := mi.mesh.surface_get_material(i) == window and not _wrecked
		mi.set_surface_override_material(i, null if see_through else _material)


# --- Chunked display --------------------------------------------------------------------------

func _key() -> String:
	return "%s|%s" % [model, scheme]


## Chunks covering the model.
func _chunk_range() -> Vector3i:
	var size: Vector3i = canvas(model).size
	return Vector3i(ceili(float(size.x) / CHUNK), ceili(float(size.y) / CHUNK), ceili(float(size.z) / CHUNK))


## The first edit: queue the shared chunks this look still lacks; the whole hull stays up until
## they're all meshed (_show_chunks), so switching never leaves a gap.
func _switch_to_chunks() -> void:
	if _chunked:
		return
	_chunked = true
	var key := _key()
	if not _shared.has(key):
		_shared[key] = {}
	var n := _chunk_range()
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var chunk := Vector3i(x, y, z)
				if not (_shared[key] as Dictionary).has(chunk):
					_enqueue(null, "shared", key, chunk)
	_enqueue(self, "show", "", Vector3i.ZERO)


func _show_chunks() -> void:
	var shared: Dictionary = _shared.get(_key(), {})
	var n := _chunk_range()
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var chunk := Vector3i(x, y, z)
				if not shared.has(chunk):
					_enqueue(self, "show", "", Vector3i.ZERO)  # still meshing: try again after
					return
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var chunk := Vector3i(x, y, z)
				if not _chunk_nodes.has(chunk) and shared[chunk] != null:
					var mi := _chunk_node(chunk)
					mi.mesh = shared[chunk]
					_dress(mi)
	if _hull_mesh:
		_hull_mesh.visible = false


func _chunk_node(chunk: Vector3i) -> MeshInstance3D:
	if _chunk_nodes.has(chunk):
		return _chunk_nodes[chunk]
	var c := canvas(model)
	var vs: float = c.vs
	var size: Vector3i = c.size
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]
	mi.scale = Vector3.ONE * vs
	mi.position = Vector3(-size.x * 0.5 + chunk.x * CHUNK, chunk.y * CHUNK, -size.z * 0.5 + chunk.z * CHUNK) * vs
	art.add_child(mi)
	_chunk_nodes[chunk] = mi
	return mi


## The model's look for one chunk with a voxel of padding all round, as the mesher wants.
static func _chunk_buffer(p_model: String, chunk: Vector3i) -> VoxelBuffer:
	var c := canvas(p_model)
	var src: VoxelBuffer = c.look
	var sub := VoxelBuffer.new()
	sub.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	sub.create(CHUNK + 2, CHUNK + 2, CHUNK + 2)
	sub.fill(VehicleArt.P.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	# Buffer coordinates carry VehicleArt's padding: voxel v sits at v + 1, so this chunk with
	# its padding is buffer [chunk * CHUNK, chunk * CHUNK + CHUNK + 2).
	var lo := chunk * CHUNK
	var src_size := src.get_size()
	var hi := Vector3i(mini(lo.x + CHUNK + 2, src_size.x), mini(lo.y + CHUNK + 2, src_size.y), mini(lo.z + CHUNK + 2, src_size.z))
	if hi.x > lo.x and hi.y > lo.y and hi.z > lo.z:
		sub.copy_channel_from_area(src, lo, hi, Vector3i.ZERO, VoxelBuffer.CHANNEL_COLOR)
	return sub


static func _mesh_of(buffer: VoxelBuffer, p_scheme: String) -> Mesh:
	var mesh: Mesh = VehicleArt._get_mesher(p_scheme).build_mesh(buffer, [])
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh


func _mesh_own(chunk: Vector3i) -> void:
	var buf := _chunk_buffer(model, chunk)
	var lo := chunk * CHUNK - Vector3i.ONE
	for v: Vector3i in _edits:
		var at := v - lo
		if at.x >= 0 and at.y >= 0 and at.z >= 0 and at.x < CHUNK + 2 and at.y < CHUNK + 2 and at.z < CHUNK + 2:
			var value := int(_edits[v])
			# A mark needs a voxel to sit on: none where the look is hollow (a cabin).
			if value != VehicleArt.P.EMPTY and buf.get_voxel(at.x, at.y, at.z, VoxelBuffer.CHANNEL_COLOR) == VehicleArt.P.EMPTY:
				continue
			buf.set_voxel(value, at.x, at.y, at.z, VoxelBuffer.CHANNEL_COLOR)
	_own[chunk] = buf
	var mesh := _mesh_of(buf, scheme)
	if mesh == null:
		if _chunk_nodes.has(chunk):
			(_chunk_nodes[chunk] as MeshInstance3D).mesh = null
		return
	var mi := _chunk_node(chunk)
	mi.mesh = mesh
	_dress(mi)


# --- The meshing queue (one for every vehicle, inside a frame budget) ----------------------------

static func _enqueue(hull: VehicleHull, kind: String, key: String, chunk: Vector3i) -> void:
	for job: Array in _queue:
		if job[1] == kind and job[2] == key and job[3] == chunk and (job[0] == null) == (hull == null) \
				and (hull == null or (job[0] as WeakRef).get_ref() == hull):
			return  # already waiting
	_queue.append([weakref(hull) if hull else null, kind, key, chunk])


## Chunks still waiting to be meshed (tests).
static func pending() -> int:
	return _queue.size()


## Meshes queued chunks until BUDGET_MS of this frame is spent (at least one). Runs once a
## frame, from whichever hull processes first.
static func _pump() -> void:
	var frame := Engine.get_process_frames()
	if frame == _pump_frame:
		return
	_pump_frame = frame
	var start := Time.get_ticks_usec()
	var done := 0
	while not _queue.is_empty():
		var spent := (Time.get_ticks_usec() - start) / 1000.0
		if done > 0 and spent >= BUDGET_MS:
			break
		var job: Array = _queue.pop_front()
		var t0 := Time.get_ticks_usec()
		var hull: VehicleHull = (job[0] as WeakRef).get_ref() if job[0] != null else null
		match String(job[1]):
			"shared":
				var key := String(job[2])
				var parts := key.split("|")
				var table: Dictionary = _shared.get(key, {})
				if not table.has(job[3]):
					table[job[3]] = _mesh_of(_chunk_buffer(parts[0], job[3]), parts[1])
					_shared[key] = table
					chunks_meshed += 1
			"own":
				if is_instance_valid(hull):
					hull._mesh_own(job[3])
					chunks_meshed += 1
			"show":
				if is_instance_valid(hull):
					hull._show_chunks()
		worst_chunk_ms = maxf(worst_chunk_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		done += 1
	last_frame_ms = (Time.get_ticks_usec() - start) / 1000.0


## Meshes everything queued now, whatever it costs (tests, and a level that wants its
## vehicles' damage drawn before play).
static func flush() -> void:
	while not _queue.is_empty():
		_pump_frame = -1
		_pump()
