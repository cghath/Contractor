class_name VoxelWorld
extends Node3D
## Destructible structures made of 10 cm voxels. Every peer builds the same base structures
## locally, then applies the host's ordered edit log, so only small edit events cross the
## network, and the same log is what gets saved.
##
## There is no voxel stream yet, so a block that unloads would come back without its
## edits: keep BOUNDS small enough that viewers always cover all of it.

signal structures_built

const VOXEL_SIZE := 0.1
enum Mat { EMPTY, CONCRETE, PAINTED, WOOD, STEEL }
## Index 0 must stay transparent: the cubes mesher treats it as empty.
const PALETTE: Array[Color] = [Color(0, 0, 0, 0), Color("8a8577"), Color("5f6b58"), Color("8c6a46"), Color("4a4d50")]
## Edit area, in voxels.
const BOUNDS := AABB(Vector3(-220, -8, -220), Vector3(440, 56, 440))
## Viewer range, in voxels. Must reach every corner of BOUNDS from anywhere players go.
const VIEW_DISTANCE := 640

var terrain: VoxelTerrain
var _tool: VoxelTool
var _structures: Array = []  # [begin: Vector3i, end: Vector3i, mat]
var _structure_area := AABB()
var _built := false
var _pending: Array = []


static func find_on(node: Object) -> VoxelWorld:
	var n := node as Node
	while n:
		if n is VoxelWorld:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	terrain = VoxelTerrain.new()
	terrain.name = "Terrain"
	terrain.scale = Vector3.ONE * VOXEL_SIZE
	var generator := VoxelGeneratorFlat.new()
	generator.channel = VoxelBuffer.CHANNEL_COLOR
	generator.height = -1000.0  # all air: ground is a plain collider, voxels are for structures
	terrain.generator = generator
	var palette := VoxelColorPalette.new()
	for i in PALETTE.size():
		palette.set_color(i, PALETTE[i])
	var mesher := VoxelMesherCubes.new()
	mesher.palette = palette
	mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
	terrain.mesher = mesher
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true  # palette colours are authored in sRGB
	material.roughness = 0.9
	terrain.material_override = material
	terrain.bounds = BOUNDS
	terrain.max_view_distance = VIEW_DISTANCE
	terrain.collision_layer = 1
	add_child(terrain)
	_tool = terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_COLOR


## Adds a solid box, in metres, relative to this node. Call before structures are built.
func add_box_m(from_m: Vector3, to_m: Vector3, mat: Mat) -> void:
	var a := Vector3i((from_m / VOXEL_SIZE).round())
	var b := Vector3i((to_m / VOXEL_SIZE).round())
	_structures.append([a.min(b), a.max(b) - Vector3i.ONE, mat])
	var box := AABB(Vector3(a.min(b)), Vector3((a - b).abs()))
	_structure_area = box if _structures.size() == 1 else _structure_area.merge(box)


func is_built() -> bool:
	return _built


## The base structures as boxes in metres, in this node's space (for navigation baking).
func structure_boxes_m() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for s: Array in _structures:
		var begin := Vector3(s[0]) * VOXEL_SIZE
		var end := Vector3(s[1] + Vector3i.ONE) * VOXEL_SIZE
		boxes.append(AABB(begin, end - begin))
	return boxes


func _process(_delta: float) -> void:
	if _built or _structures.is_empty():
		return
	# Blocks only exist once a VoxelViewer (on a player) has loaded them.
	if not _tool.is_area_editable(_structure_area):
		return
	_tool.mode = VoxelTool.MODE_SET
	for s: Array in _structures:
		_tool.value = s[2]
		_tool.do_box(s[0], s[1])
	_built = true
	set_process(false)
	for edit: Dictionary in _pending:
		_apply(edit)
	_pending.clear()
	print("[world] voxel structures built (%d boxes)" % _structures.size())
	structures_built.emit()


## Host only. Removes a sphere of voxels around a world-space point.
func server_carve(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	var edit := {"op": "carve", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE}
	GameState.voxel_edits.append(edit)
	apply_edit.rpc(edit)


## Host only. Replays a saved edit log locally (the log itself is already in GameState).
func load_edits(edits: Array) -> void:
	for edit: Dictionary in edits:
		apply_edit(edit)


func send_edit_log_to(peer_id: int) -> void:
	_receive_edit_log.rpc_id(peer_id, GameState.voxel_edits)


@rpc("authority", "call_local", "reliable")
func apply_edit(edit: Dictionary) -> void:
	if _built:
		_apply(edit)
	else:
		_pending.append(edit)


@rpc("authority", "reliable")
func _receive_edit_log(edits: Array) -> void:
	load_edits(edits)


func _apply(edit: Dictionary) -> void:
	match edit.get("op"):
		"carve":
			var c: Array = edit["c"]
			# SET to EMPTY rather than MODE_REMOVE: on the color channel REMOVE doesn't
			# reliably clear voxels once `value` has been used for building.
			_tool.mode = VoxelTool.MODE_SET
			_tool.value = Mat.EMPTY
			_tool.do_sphere(Vector3(c[0], c[1], c[2]), float(edit["r"]))
