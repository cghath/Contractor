class_name ZoneModule
extends Node3D
## One hand-built combat space on a zone's terrain (a ZoneModules type: compound, outpost,
## village, checkpoint), at its origin on a flat pad.
##
## Streamed: while anyone is near (ZoneLevel decides), it's a VoxelWorld of its own at 10 cm,
## built from the type's boxes and then its own edit log (the zone keeps every module's log,
## on every peer, and saves them with the zone). While nobody is near, the voxels are freed
## and a proxy stands in: the base boxes as one plain mesh, seen from up to PROXY_VIEW_M, with
## box collision so rounds and sight lines still stop at its walls. The proxy goes once the
## voxels are built and their collision has had PROXY_HOLD_S to come in.

## Emitted on the peer where it happens.
signal streamed_in(module: ZoneModule)
signal streamed_out(module: ZoneModule)

const PROXY_VIEW_M := 2500.0
const PROXY_HOLD_S := 0.5

var module_id := ""
var type := ""
## The loaded voxels (null while streamed out).
var voxel_world: VoxelWorld
## How many entries of this module's edit log are applied to voxel_world.
var applied := 0
## The voxel terrain's view distance cap (voxels), set by the zone from its streaming range.
var view_voxels := 4000

var _proxy_mesh: MeshInstance3D
var _proxy_body: StaticBody3D
var _ready_at := -1.0  # Time (s) the proxy can go, once the voxels are built
var _proxy_up := true


func setup(id: String, p_type: String, origin: Vector3) -> void:
	module_id = id
	type = p_type
	name = id.validate_node_name()
	position = origin


func _ready() -> void:
	_build_proxy()
	set_process(false)


## The footprint on the ground (x, z in metres, world space).
func footprint() -> Rect2:
	var half: Vector2 = ZoneModules.HALF.get(type, Vector2(20, 20))
	return Rect2(position.x - half.x, position.z - half.y, half.x * 2.0, half.y * 2.0)


## Flat distance (m) from `pos` to the footprint (0 inside).
func distance_to(pos: Vector3) -> float:
	return ZoneTerrain._distance_to_rect(Vector2(pos.x, pos.z), footprint())


## A named point of this module in world space (ZoneModules.POINTS: "objective", "cache",
## "intel"), or the origin if it has none.
func point(kind: String, index := 0) -> Vector3:
	var list := ZoneModules.points(type, kind)
	return to_global(list[index % list.size()]) if not list.is_empty() else global_position


func points(kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in ZoneModules.points(type, kind):
		out.append(to_global(p))
	return out


func is_streamed() -> bool:
	return voxel_world != null


## Streamed in, built, and the proxy gone (its own collision in place).
func is_ready() -> bool:
	return voxel_world != null and voxel_world.is_built() and not _proxy_up


## Makes the voxels (the type's boxes, then `log` from the start, then whatever the zone sends
## as it comes). `sink`: the host's edit sink (VoxelWorld.edit_sink), none on a client.
func stream_in(log: Array, sink: Callable) -> void:
	if voxel_world:
		return
	var world := VoxelWorld.new()
	world.name = "Voxels"
	world.module_id = module_id
	world.bounds = ZoneModules.bounds_voxels(type)
	world.view_distance = view_voxels
	world.edit_sink = sink
	for box: Array in ZoneModules.boxes(type):
		world.add_box_m(box[0], box[1], box[2])
	voxel_world = world
	applied = 0
	add_child(world)
	world.structures_built.connect(_on_built, CONNECT_ONE_SHOT)
	sync(log)


## Applies the entries of this module's edit log not applied yet (queued by the voxel world
## until it's built).
func sync(log: Array) -> void:
	if voxel_world == null:
		return
	for i in range(applied, log.size()):
		voxel_world.apply_edit(log[i])
	applied = log.size()


func stream_out() -> void:
	if voxel_world == null:
		return
	voxel_world.queue_free()
	remove_child(voxel_world)
	voxel_world = null
	applied = 0
	_ready_at = -1.0
	set_process(false)
	_show_proxy(true)
	streamed_out.emit(self)


func _on_built() -> void:
	_ready_at = Time.get_ticks_msec() / 1000.0 + PROXY_HOLD_S
	set_process(true)


func _process(_delta: float) -> void:
	if voxel_world and voxel_world.is_built() and Time.get_ticks_msec() / 1000.0 >= _ready_at:
		set_process(false)
		_show_proxy(false)
		streamed_in.emit(self)


func _show_proxy(on: bool) -> void:
	_proxy_up = on
	_proxy_mesh.visible = on
	_proxy_body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_proxy_body.collision_layer = 1 if on else 0


## The stand-in while streamed out: the base boxes as one mesh in their materials' colours,
## and as box shapes on the world layer. Placeholder art: replace this one function.
func _build_proxy() -> void:
	var boxes := ZoneModules.boxes_m(type)
	var mats := ZoneModules.boxes(type)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_proxy_body = StaticBody3D.new()
	_proxy_body.name = "Proxy"
	_proxy_body.collision_layer = 1
	_proxy_body.collision_mask = 0
	for i in boxes.size():
		var box: AABB = boxes[i]
		var colour: Color = VoxelWorld.PALETTE[int(mats[i][2])]
		st.set_color(colour)
		var faces := NavBuilder._box_faces(box)
		for k in range(0, faces.size(), 3):
			var n := (faces[k + 1] - faces[k]).cross(faces[k + 2] - faces[k]).normalized()
			st.set_normal(-n)  # NavBuilder's faces are clockwise from outside (Godot's front faces)
			st.add_vertex(faces[k])
			st.add_vertex(faces[k + 1])
			st.add_vertex(faces[k + 2])
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = box.size
		shape.shape = cube
		shape.position = box.get_center()
		_proxy_body.add_child(shape)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	_proxy_mesh = MeshInstance3D.new()
	_proxy_mesh.name = "ProxyMesh"
	_proxy_mesh.mesh = st.commit()
	_proxy_mesh.material_override = material
	_proxy_mesh.visibility_range_end = PROXY_VIEW_M
	add_child(_proxy_mesh)
	add_child(_proxy_body)
