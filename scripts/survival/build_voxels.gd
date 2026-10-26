class_name BuildVoxels
extends VoxelWorld
## One chunk of the builds' voxels (Builder, docs/survival_building.md §1): a VoxelWorld
## CHUNK_M a side at a whole-chunk corner of the world grid, so a block (BuildPieces.BLOCK_M, 5
## voxels) never straddles two. Its voxels are its edit log, replayed: Builder's own "bset" (a
## block's shape stamped in its material) and "bclr" (a cell cleared) beside the voxel world's
## shots, marks, holes and blasts, in the order they happened. Rounds and blasts take it like
## any voxel world (Ballistics finds it by its collider); a round through or into a built block
## also tells Builder, which lowers the block's hp (server_shot, server_mark).
##
## Host: edit_sink is Builder's, which logs, applies and sends every edit (the host never calls
## apply_edit's RPC). Streamed in and out by Builder around the players, rebuilt from the log.

## Voxels a chunk spans (Builder.CHUNK_CELLS blocks).
const SIZE_VOX := 160
var builder: Node
## The chunk's index on the chunk grid (its corner is chunk * Builder.CHUNK_M).
var chunk := Vector3i.ZERO
## Host: set while Builder makes its own marks (cracks), so they don't count as damage.
var quiet := false


func _init() -> void:
	bounds = AABB(Vector3.ZERO, Vector3.ONE * SIZE_VOX)
	# A voxel world builds (and starts applying its log) once its structures are stamped; a
	# chunk has none of its own, so one empty voxel stands in.
	add_box_m(Vector3.ZERO, Vector3.ONE * VOXEL_SIZE, Mat.EMPTY)


## The world cell (BuildPieces) a voxel of this chunk lies in.
func cell_of_voxel(v: Vector3i) -> Vector3i:
	return chunk * (SIZE_VOX / BuildPieces.BLOCK_VOX) + Vector3i((Vector3(v) / BuildPieces.BLOCK_VOX).floor())


func server_shot(entry: Vector3, entry_normal: Vector3, exit: Vector3, exit_normal: Vector3, calibre_m: float, voxels: Array, mat: int) -> void:
	if builder and not quiet:
		var cells := {}
		for v: Vector3i in voxels:
			var c := cell_of_voxel(v)
			cells[c] = int(cells.get(c, 0)) + 1
		builder.call(&"server_shot_cells", cells)
	super.server_shot(entry, entry_normal, exit, exit_normal, calibre_m, voxels, mat)


func server_mark(world_position: Vector3, normal: Vector3, mat: int) -> bool:
	if builder and not quiet:
		builder.call(&"server_shot_cells", {BuildPieces.cell_at(world_position - normal * 0.05): 1}, true)
	return super.server_mark(world_position, normal, mat)


func _apply(edit: Dictionary) -> void:
	match edit.get("op"):
		"bset":
			var c: Array = edit["c"]
			var lo := Vector3i(int(c[0]), int(c[1]), int(c[2]))
			var shape := String(edit.get("s", "block"))
			var rot := int(edit.get("r", 0))
			var mat := int(edit.get("m", Mat.WOOD))
			var n := BuildPieces.BLOCK_VOX
			_tool.mode = VoxelTool.MODE_SET
			for y in n:
				for z in n:
					for x in n:
						_tool.set_voxel(lo + Vector3i(x, y, z), mat if BuildPieces.shape_has(shape, rot, x, y, z) else Mat.EMPTY)
		"bclr":
			var c: Array = edit["c"]
			var lo := Vector3i(int(c[0]), int(c[1]), int(c[2]))
			var hi := lo + Vector3i.ONE * (BuildPieces.BLOCK_VOX - 1)
			_tool.mode = VoxelTool.MODE_SET
			_tool.value = Mat.EMPTY
			_tool.do_box(lo, hi)
			_carved(AABB(Vector3(lo), Vector3.ONE * BuildPieces.BLOCK_VOX))
		_:
			super._apply(edit)
