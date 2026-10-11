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
## Body types (CharacterModel.body): "female" parts are the same models with this suffix
## (VoxelArt.body_part), on the same joints but her own shoulders (CharacterModel.shoulder_of).
const FEMALE := "female"
const FEMALE_SUFFIX := "_f"

static var _grids: Dictionary = {}  # "part/body" -> {"origin", "cell", "dims", "entry", "body"}
static var _occupancy: Dictionary = {}  # model -> VoxelArt.occupancy


## Where a round on `direction` that touched `hitbox` (part `part`) at world `position`
## really meets the body: {"position" (world), "depth" (metres of body it crosses before it
## leaves the part's segment)}, or {} if it misses the body inside the box.
static func entry(hitbox: Node3D, part: StringName, position: Vector3, direction: Vector3, body := "") -> Dictionary:
	if not PART_MODELS.has(part) or hitbox == null or not hitbox.is_inside_tree():
		return {"position": position, "depth": BodyMap.CHANNEL_MAX_M}
	var to_rest := hitbox.global_transform.affine_inverse()
	var hit := march(part, to_rest * position, (to_rest.basis * direction).normalized(), body)
	if hit.is_empty():
		return {}
	return {"position": hitbox.global_transform * Vector3(hit.position), "depth": hit.depth}


## The same in the rest pose: the first voxel of `part` on the ray through `point` along
## `dir`, and how far the body (the part's whole segment) goes on from there.
static func march(part: StringName, point: Vector3, dir: Vector3, body := "") -> Dictionary:
	var grid := _grid(part, body)
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


## The voxel model a body part is built from, for a body type ("" or "male": the male
## parts; "female": the female ones).
static func model_of(part: StringName, body := "") -> String:
	return String(PART_MODELS[part]) + (FEMALE_SUFFIX if body == FEMALE else "")


## The body type of the soldier `node` belongs to (its CharacterModel.body; "" before the
## art branch adds body types).
static func body_of(node: Node) -> String:
	var model: Node = node if node is CharacterModel else null
	while node and model == null:
		model = node.get_node_or_null(^"Model") as CharacterModel
		node = node.get_parent()
	return String(model.get("body")) if model and model.get("body") != null else ""


## The skin under rest-pose `point` looking in along -`outward`: the first voxel of the
## part's whole model (so a trail runs on from chest to belly), or null if there is none
## within `reach` of `point` (off the end of a limb).
static func surface(part: StringName, point: Vector3, outward: Vector3, reach := 0.05, body := "") -> Variant:
	if not PART_MODELS.has(part):
		return null
	var grid := _grid(part, body)
	var step: float = grid.cell * STEP_SHARE
	var from := point + outward * reach
	var t := 0.0
	while t <= reach * 2.0:
		var p := from - outward * t
		if _solid(grid, grid.body, p):
			return p
		t += step
	return null


static func _solid(grid: Dictionary, cells: PackedByteArray, p: Vector3) -> bool:
	var c := ((p - Vector3(grid.origin)) / float(grid.cell)).floor()
	var dims: Vector3i = grid.dims
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= dims.x or c.y >= dims.y or c.z >= dims.z:
		return false
	return cells[int(c.x) + dims.x * (int(c.y) + dims.y * int(c.z))] == 1


## A part's grid, built on first use: "body" is every voxel of its model (the channel runs
## through the whole torso or head, BodyMap.SEGMENTS), "entry" only those in this part (a
## torso or head voxel counts for a part inside that part's BodyMap.PART_BOXES).
static func _grid(part: StringName, body := "") -> Dictionary:
	var key := "%s/%s" % [part, body if body == FEMALE else ""]
	if _grids.has(key):
		return _grids[key]
	var model: String = model_of(part, body)
	if not _occupancy.has(model):
		_occupancy[model] = VoxelArt.occupancy(model)
	var occ: Dictionary = _occupancy[model]
	var origin: Vector3 = pivot_at(part, body) - Vector3(occ.pivot)
	var dims: Vector3i = occ.dims
	var cell: float = occ.cell
	var solid: PackedByteArray = occ.solid
	var entry_cells := solid
	if BodyMap.segment_of(part) != part:  # torso or head: only this part's share
		entry_cells = PackedByteArray()
		entry_cells.resize(solid.size())
		for box: Array in BodyMap.PART_BOXES[part]:
			var lo := ((Vector3(box[0]) - Vector3(box[1]) * 0.5 - origin) / cell).floor()
			var hi := ((Vector3(box[0]) + Vector3(box[1]) * 0.5 - origin) / cell).ceil()
			for z in range(maxi(int(lo.z), 0), mini(int(hi.z), dims.z)):
				for y in range(maxi(int(lo.y), 0), mini(int(hi.y), dims.y)):
					for x in range(maxi(int(lo.x), 0), mini(int(hi.x), dims.x)):
						var i := x + dims.x * (y + dims.y * z)
						entry_cells[i] = solid[i]
	var grid := {"origin": origin, "cell": cell, "dims": dims, "entry": entry_cells, "body": solid}
	_grids[key] = grid
	return grid


## Builds every part's grid now (host, at level start) so the first hit doesn't hitch, for each
## body type in `bodies`.
static func warm(bodies: Array = [""]) -> void:
	for body: String in bodies:
		for part: StringName in PART_MODELS:
			_grid(part, body)


## Where the part's model pivot sits in the rest pose (CharacterModel's joints for body type
## `body`; arms hang straight down).
static func pivot_at(part: StringName, body := "") -> Vector3:
	var shoulder := CharacterModel.shoulder_of(body)
	var side := -1.0 if String(part).ends_with("_l") else 1.0
	var flip := Vector3(side, 1, 1)
	match PART_MODELS[part]:
		"head":
			return CharacterModel.TORSO_PIVOT + CharacterModel.HEAD_PIVOT
		"torso":
			return CharacterModel.TORSO_PIVOT
		"upper_arm":
			return CharacterModel.TORSO_PIVOT + shoulder * flip
		"forearm":
			return CharacterModel.TORSO_PIVOT + shoulder * flip - Vector3(0, CharacterModel.UPPER_ARM, 0)
		"thigh":
			return CharacterModel.HIP * flip
		"shin":
			return CharacterModel.HIP * flip - Vector3(0, CharacterModel.THIGH, 0)
	return Vector3.ZERO
