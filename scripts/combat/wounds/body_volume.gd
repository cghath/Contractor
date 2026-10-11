class_name BodyVolume
extends RefCounted
## The soldier's real shape for hits: each hitbox part's voxels from the character model
## (VoxelArt, 0.5 cm), in the body's rest pose (BodyMap's frame: feet at the origin, facing
## -Z). A hitbox box is only the first, cheap test; a round that crosses the box but misses
## the body inside it (between the legs, beside a wrist) passes on, and one that hits enters
## where the voxels start and its wound channel ends where they do.
##
## A hitbox Area3D's own space is the rest pose for its part (BodyMap), so a ray is marched
## in that space against that part's voxels; posing moves the Area3D and the test follows.

## Each part's model and where that model's pivot sits in the rest pose.
const PART_MODELS := {
	&"head": "head", &"face": "head", &"neck": "head",
	&"chest": "torso", &"abdomen": "torso", &"pelvis": "torso",
	&"upper_arm_l": "upper_arm", &"upper_arm_r": "upper_arm",
	&"forearm_l": "forearm", &"forearm_r": "forearm",
	&"thigh_l": "thigh", &"thigh_r": "thigh",
	&"shin_l": "shin", &"shin_r": "shin",
}
## How far before the box hit the march starts (a round can meet the box before the body),
## and how far it goes at most.
const LEAD_M := 0.3
const REACH_M := 0.8
## The march samples every half built voxel.
const STEP_SHARE := 0.5

static var _grids: Dictionary = {}  # part -> {"origin", "cell", "dims", "entry", "body"}
static var _occupancy: Dictionary = {}  # model -> VoxelArt.occupancy


## Where a round on `direction` that touched `hitbox` (part `part`) at world `position`
## really meets the body: {"position" (world), "depth" (metres of body it crosses before it
## leaves the part's segment)}, or {} if it misses the body inside the box.
static func entry(hitbox: Node3D, part: StringName, position: Vector3, direction: Vector3) -> Dictionary:
	if not PART_MODELS.has(part) or hitbox == null or not hitbox.is_inside_tree():
		return {"position": position, "depth": BodyMap.CHANNEL_MAX_M}
	var to_rest := hitbox.global_transform.affine_inverse()
	var hit := march(part, to_rest * position, (to_rest.basis * direction).normalized())
	if hit.is_empty():
		return {}
	return {"position": hitbox.global_transform * Vector3(hit.position), "depth": hit.depth}


## The same in the rest pose: the first voxel of `part` on the ray through `point` along
## `dir`, and how far the body (the part's whole segment) goes on from there.
static func march(part: StringName, point: Vector3, dir: Vector3) -> Dictionary:
	var grid := _grid(part)
	var step: float = grid.cell * STEP_SHARE
	var t := -LEAD_M
	var entered := -1.0
	while t <= REACH_M:
		var p := point + dir * t
		if entered < 0.0:
			if _solid(grid, grid.entry, p):
				entered = t
		elif not _solid(grid, grid.body, p) and not _solid(grid, grid.body, p + dir * step):
			return {"position": point + dir * entered, "depth": t - entered}
		t += step
	if entered < 0.0:
		return {}
	return {"position": point + dir * entered, "depth": REACH_M - entered}


static func _solid(grid: Dictionary, cells: PackedByteArray, p: Vector3) -> bool:
	var c := ((p - Vector3(grid.origin)) / float(grid.cell)).floor()
	var dims: Vector3i = grid.dims
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= dims.x or c.y >= dims.y or c.z >= dims.z:
		return false
	return cells[int(c.x) + dims.x * (int(c.y) + dims.y * int(c.z))] == 1


## A part's grid, built on first use: "body" is every voxel of its model (the channel runs
## through the whole torso or head, BodyMap.SEGMENTS), "entry" only those in this part (a
## torso or head voxel counts for a part inside that part's BodyMap.PART_BOXES).
static func _grid(part: StringName) -> Dictionary:
	if _grids.has(part):
		return _grids[part]
	var model: String = PART_MODELS[part]
	if not _occupancy.has(model):
		_occupancy[model] = VoxelArt.occupancy(model)
	var occ: Dictionary = _occupancy[model]
	var origin: Vector3 = pivot_at(part) - Vector3(occ.pivot)
	var dims: Vector3i = occ.dims
	var cell: float = occ.cell
	var body: PackedByteArray = occ.solid
	var entry_cells := body
	if BodyMap.segment_of(part) != part:  # torso or head: only this part's share
		entry_cells = PackedByteArray()
		entry_cells.resize(body.size())
		for box: Array in BodyMap.PART_BOXES[part]:
			var lo := ((Vector3(box[0]) - Vector3(box[1]) * 0.5 - origin) / cell).floor()
			var hi := ((Vector3(box[0]) + Vector3(box[1]) * 0.5 - origin) / cell).ceil()
			for z in range(maxi(int(lo.z), 0), mini(int(hi.z), dims.z)):
				for y in range(maxi(int(lo.y), 0), mini(int(hi.y), dims.y)):
					for x in range(maxi(int(lo.x), 0), mini(int(hi.x), dims.x)):
						var i := x + dims.x * (y + dims.y * z)
						entry_cells[i] = body[i]
	var grid := {"origin": origin, "cell": cell, "dims": dims, "entry": entry_cells, "body": body}
	_grids[part] = grid
	return grid


## Builds every part's grid now (host, at level start) so the first hit doesn't hitch.
static func warm() -> void:
	for part: StringName in PART_MODELS:
		_grid(part)


## Where the part's model pivot sits in the rest pose (CharacterModel's joints; arms hang
## straight down).
static func pivot_at(part: StringName) -> Vector3:
	var side := -1.0 if String(part).ends_with("_l") else 1.0
	var flip := Vector3(side, 1, 1)
	match PART_MODELS[part]:
		"head":
			return CharacterModel.TORSO_PIVOT + CharacterModel.HEAD_PIVOT
		"torso":
			return CharacterModel.TORSO_PIVOT
		"upper_arm":
			return CharacterModel.TORSO_PIVOT + CharacterModel.SHOULDER * flip
		"forearm":
			return CharacterModel.TORSO_PIVOT + CharacterModel.SHOULDER * flip - Vector3(0, CharacterModel.UPPER_ARM, 0)
		"thigh":
			return CharacterModel.HIP * flip
		"shin":
			return CharacterModel.HIP * flip - Vector3(0, CharacterModel.THIGH, 0)
	return Vector3.ZERO
