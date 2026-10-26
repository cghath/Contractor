class_name BuildPieces
extends RefCounted
## The free building system's catalogue (docs/survival_building.md §1-4; calls 8, 12, 39, 70-73):
## the block grid, the block materials and shapes, the pieces, the tools, and what each costs.
## Pure data and helpers, the same on every peer: Builder places and keeps the builds,
## BuildIntegrity solves their load, BuildMode is the player's ghost.
##
## Blocks: BLOCK_M cubes (call 70: 0.5 m, 5 voxels a side) on a world-aligned grid, a cell
## (Vector3i) each: cell c spans c * BLOCK_M to (c + 1) * BLOCK_M. One material (MATERIALS) and a
## shape (SHAPES, turned in quarter turns about the vertical). Pieces (PIECES) are nodes on the
## same grid with a footprint of cells. Every number here is Proposed unless the doc fixes it.

const BLOCK_M := 0.5
const BLOCK_VOX := 5  # voxels a side (VoxelWorld.VOXEL_SIZE 0.1 m)

## Block materials (doc §2; the integrity numbers §3). Keys, in BuildMode's cycle order:
## - mat: the voxel material it's stamped in (rounds and blasts go by it).
## - item: the material item it costs and gives back; cost: how many a full block.
## - tool: the tool kind it needs in the inventory (TOOLS).
## - build_s: seconds of work a block (doc §4: wood 4, brick 8, concrete 12, steel 15; scrap and
##   sandbag Proposed between).
## - mass and cap: a full block's own load and what it carries before it cracks (BuildIntegrity;
##   Proposed, in "blocks of wood"); span: blocks out from a supported column before it fails
##   (doc §2: wood 3, scrap 2, brick 4, concrete 6, steel 8; sandbags stack only: 0).
## - value: its worth against the others, for upgrading in place (the cost is the difference).
## - chew: zombies chew it (Builder.CHEW_WOOD_S; scrap only slows them, the rest hold).
const MATERIALS := {
	"wood": {"name": "Wood", "mat": VoxelWorld.Mat.WOOD, "item": &"planks", "cost": 5, "tool": "hammer", "build_s": 4.0,
		"mass": 1.0, "cap": 12.0, "span": 3, "value": 1.0, "chew": true},
	"scrap": {"name": "Scrap", "mat": VoxelWorld.Mat.SHEET_METAL, "item": &"scrap_sheet", "cost": 3, "tool": "wrench", "build_s": 6.0,
		"mass": 1.2, "cap": 10.0, "span": 2, "value": 1.5, "chew": false},
	"sandbag": {"name": "Sandbag", "mat": VoxelWorld.Mat.SANDBAG, "item": &"sandbag", "cost": 4, "tool": "shovel", "build_s": 5.0,
		"mass": 3.0, "cap": 40.0, "span": 0, "value": 1.5, "chew": false},
	"brick": {"name": "Brick", "mat": VoxelWorld.Mat.BRICK, "item": &"brick", "cost": 4, "tool": "trowel", "build_s": 8.0,
		"mass": 3.0, "cap": 45.0, "span": 4, "value": 3.0, "chew": false},
	"concrete": {"name": "Concrete", "mat": VoxelWorld.Mat.CONCRETE, "item": &"concrete_bag", "cost": 3, "tool": "trowel", "build_s": 12.0,
		"mass": 4.0, "cap": 90.0, "span": 6, "value": 4.0, "chew": false},
	"steel": {"name": "Steel", "mat": VoxelWorld.Mat.STEEL, "item": &"steel_beam", "cost": 2, "tool": "torch", "build_s": 15.0,
		"mass": 3.0, "cap": 140.0, "span": 8, "value": 6.0, "chew": false},
}
const MATERIAL_KEYS: Array[String] = ["wood", "scrap", "sandbag", "brick", "concrete", "steel"]

## Block shapes (call 70): the voxels of the 5x5x5 cell each fills (shape_has), and the share
## of a full block that is (cost, mass and capacity scale by it). A half is the lower three
## rows (0.3 m: five voxels don't halve), a slab the bottom row (0.1 m), a ramp rises along
## its forward edge, a wedge is a corner (a triangle in plan), a pillar the middle 0.3 m square.
const SHAPES := {
	"block": {"name": "Block", "frac": 1.0},
	"half": {"name": "Half block", "frac": 0.6},
	"slab": {"name": "Slab", "frac": 0.2},
	"ramp": {"name": "Ramp", "frac": 0.6},
	"wedge": {"name": "Wedge", "frac": 0.6},
	"pillar": {"name": "Pillar", "frac": 0.36},
}
const SHAPE_KEYS: Array[String] = ["block", "half", "slab", "ramp", "wedge", "pillar"]

## Tools (call 39): a tool kind -> the items that are it. "No tool, no placing that tier."
## Carried counts as in hand until tools get a hand slot (Proposed). The e-tool is a shovel;
## the hacksaw a saw.
const TOOLS := {
	"hammer": [&"hammer"],
	"saw": [&"saw", &"hacksaw"],
	"wrench": [&"wrench_set"],
	"trowel": [&"trowel"],
	"shovel": [&"shovel", &"etool"],
	"torch": [&"cutting_torch"],
}

## Pieces (doc §1): prefab nodes on the grid. Keys:
## - size: the footprint in cells [x, y, z] before turning (a quarter turn swaps x and z).
## - cost: [[item, count], ...]; tool; build_s; hp (what hits it takes: Builder.server_hit_piece).
## - solid: it has collision; door: it opens and shuts (and locks: Builder.server_door).
## - look: how it draws in its footprint ("panel": a thin board at the back edge, "slab": a
##   board on the floor, "steps": a flight rising along z, "frame": a low frame, "full": the
##   whole footprint); mat: the block material it's of (colour, debris).
## The operations lane's field defences come back as the hesco and wire pieces (sandbags are a
## block material). Stash storage, ladder climbing and the workbench's crafting come later.
const PIECES := {
	"door": {"name": "Door", "size": [2, 4, 1], "cost": [[&"planks", 3]], "tool": "hammer", "build_s": 6.0, "hp": 100.0, "solid": true, "door": true, "look": "panel", "mat": "wood"},
	"shutter": {"name": "Window shutter", "size": [2, 2, 1], "cost": [[&"planks", 2]], "tool": "hammer", "build_s": 4.0, "hp": 60.0, "solid": true, "door": true, "look": "panel", "mat": "wood"},
	"hatch": {"name": "Floor hatch", "size": [2, 1, 2], "cost": [[&"planks", 3]], "tool": "hammer", "build_s": 5.0, "hp": 80.0, "solid": true, "door": true, "look": "slab", "mat": "wood"},
	"gate": {"name": "Gate", "size": [4, 4, 1], "cost": [[&"planks", 6], [&"scrap_sheet", 1]], "tool": "hammer", "build_s": 10.0, "hp": 200.0, "solid": true, "door": true, "look": "panel", "mat": "wood"},
	"stairs": {"name": "Stairs", "size": [2, 4, 4], "cost": [[&"planks", 8]], "tool": "hammer", "build_s": 10.0, "hp": 150.0, "solid": true, "look": "steps", "mat": "wood"},
	"ladder": {"name": "Ladder", "size": [1, 4, 1], "cost": [[&"planks", 2]], "tool": "hammer", "build_s": 4.0, "hp": 40.0, "solid": false, "look": "panel", "mat": "wood"},
	"bunk": {"name": "Bunk", "size": [2, 2, 4], "cost": [[&"planks", 6]], "tool": "hammer", "build_s": 10.0, "hp": 80.0, "solid": true, "look": "frame", "mat": "wood"},
	"stash": {"name": "Stash", "size": [2, 2, 1], "cost": [[&"planks", 3]], "tool": "hammer", "build_s": 5.0, "hp": 80.0, "solid": true, "look": "full", "mat": "wood"},
	"workbench": {"name": "Workbench", "size": [4, 2, 2], "cost": [[&"planks", 6], [&"scrap_sheet", 2]], "tool": "hammer", "build_s": 12.0, "hp": 120.0, "solid": true, "look": "frame", "mat": "wood"},
	"fence": {"name": "Fence", "size": [2, 3, 1], "cost": [[&"planks", 2]], "tool": "hammer", "build_s": 4.0, "hp": 50.0, "solid": true, "look": "panel", "mat": "wood"},
	"hesco": {"name": "HESCO", "size": [2, 3, 2], "cost": [[&"sandbag", 6], [&"scrap_sheet", 2]], "tool": "shovel", "build_s": 12.0, "hp": 600.0, "solid": true, "look": "full", "mat": "sandbag"},
	"wire": {"name": "Wire", "size": [4, 2, 1], "cost": [[&"scrap_sheet", 2]], "tool": "wrench", "build_s": 5.0, "hp": 60.0, "solid": false, "look": "full", "mat": "scrap"},
	# The settlement's pieces (docs/survival_building.md §5-6, Settlement; Proposed): a pile (a stock
	# spot for anything, bigger than a stash), a stove (cooking, smoking, boiling), a lookout (a
	# guard post and a tower in the defence value), a farm bed (crops: phase D; the farm job's stub
	# yield), a generator (fuel, loud: the noise footprint) and a lamp (the light footprint).
	"pile": {"name": "Stock pile", "size": [2, 1, 2], "cost": [[&"planks", 1]], "tool": "hammer", "build_s": 2.0, "hp": 40.0, "solid": false, "look": "slab", "mat": "wood"},
	"stove": {"name": "Stove", "size": [2, 2, 2], "cost": [[&"scrap_sheet", 3], [&"brick", 1]], "tool": "wrench", "build_s": 10.0, "hp": 150.0, "solid": true, "look": "full", "mat": "scrap"},
	"lookout": {"name": "Lookout", "size": [2, 6, 2], "cost": [[&"planks", 10]], "tool": "hammer", "build_s": 20.0, "hp": 200.0, "solid": true, "look": "frame", "mat": "wood"},
	"farm_bed": {"name": "Farm bed", "size": [2, 1, 4], "cost": [[&"planks", 2]], "tool": "shovel", "build_s": 6.0, "hp": 40.0, "solid": false, "look": "slab", "mat": "wood"},
	"generator": {"name": "Generator", "size": [2, 2, 2], "cost": [[&"scrap_sheet", 4]], "tool": "wrench", "build_s": 15.0, "hp": 150.0, "solid": true, "look": "full", "mat": "scrap"},
	"lamp": {"name": "Lamp", "size": [1, 3, 1], "cost": [[&"scrap_sheet", 1]], "tool": "wrench", "build_s": 3.0, "hp": 30.0, "solid": false, "look": "panel", "mat": "scrap"},
	# The map table (call 45, the intel lane: MapTable): standing at it, the map shows the reports.
	"map_table": {"name": "Map table", "size": [4, 2, 2], "cost": [[&"planks", 4], [&"scrap_sheet", 1]], "tool": "hammer", "build_s": 8.0, "hp": 80.0, "solid": true, "look": "frame", "mat": "wood"},
}
const PIECE_KEYS: Array[String] = ["door", "shutter", "hatch", "gate", "stairs", "ladder", "bunk", "stash", "workbench", "fence", "hesco", "wire",
	"pile", "stove", "lookout", "farm_bed", "generator", "lamp", "map_table"]

## The key item a key lock hands out (Builder.server_door "lock_key"): its state names the lock.
const KEY_ITEM := &"door_key"


## The world-space box of cell `c`.
static func cell_box(c: Vector3i) -> AABB:
	return AABB(Vector3(c) * BLOCK_M, Vector3.ONE * BLOCK_M)


## The cell a world point is in.
static func cell_at(p: Vector3) -> Vector3i:
	return Vector3i((p / BLOCK_M).floor())


static func cell_centre(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3.ONE * 0.5) * BLOCK_M


static func key_of(c: Vector3i) -> String:
	return "%d,%d,%d" % [c.x, c.y, c.z]


static func cell_of(key: String) -> Vector3i:
	var p := key.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2])) if p.size() == 3 else Vector3i.ZERO


## Whether voxel (x, y, z) of a cell (0..4 each) is filled by `shape` turned `rot` quarter turns.
static func shape_has(shape: String, rot: int, x: int, y: int, z: int) -> bool:
	var n := BLOCK_VOX - 1
	# Turn the voxel back into the shape's own frame.
	var lx := x
	var lz := z
	match posmod(rot, 4):
		1:
			lx = z
			lz = n - x
		2:
			lx = n - x
			lz = n - z
		3:
			lx = n - z
			lz = x
	match shape:
		"half":
			return y <= 2
		"slab":
			return y == 0
		"ramp":
			return y <= lz
		"wedge":
			return lx + lz <= n
		"pillar":
			return lx >= 1 and lx <= 3 and lz >= 1 and lz <= 3
	return true


## The cost of a block: [[item, count]] (a share of a full block's by its shape, at least one).
static func block_cost(mat: String, shape: String) -> Array:
	var m: Dictionary = MATERIALS[mat]
	return [[m.item, maxi(1, ceili(float(m.cost) * float(SHAPES[shape].frac) - 0.001))]]


## Upgrading a block in place from `from` to `to` (call 12: the difference): the share of the new
## material's cost that the old one's value doesn't already cover. [] when it isn't an upgrade.
static func upgrade_cost(from: String, to: String, shape: String) -> Array:
	var a := float(MATERIALS[from].value)
	var b := float(MATERIALS[to].value)
	if b <= a:
		return []
	var full: Array = block_cost(to, shape)[0]
	return [[full[0], maxi(1, ceili(float(full[1]) * (1.0 - a / b) - 0.001))]]


## A piece's footprint size in cells, turned `rot` quarter turns.
static func piece_size(kind: String, rot: int) -> Vector3i:
	var s: Array = PIECES[kind].size
	return Vector3i(int(s[2]), int(s[1]), int(s[0])) if posmod(rot, 2) == 1 else Vector3i(int(s[0]), int(s[1]), int(s[2]))


## The cells a piece at base cell `c` (its footprint's lowest corner) turned `rot` covers.
static func piece_cells(kind: String, c: Vector3i, rot: int) -> Array[Vector3i]:
	var size := piece_size(kind, rot)
	var out: Array[Vector3i] = []
	for y in size.y:
		for z in size.z:
			for x in size.x:
				out.append(c + Vector3i(x, y, z))
	return out


## A cost list scaled by `share` (rounded; entries that round to nothing are left out).
static func scaled(cost: Array, share: float) -> Array:
	var out: Array = []
	for pair: Array in cost:
		var n := roundi(float(pair[1]) * share)
		if n > 0:
			out.append([pair[0], n])
	return out


## A short "5 Wood Planks, 1 Scrap Sheet" line for a cost.
static func cost_text(cost: Array) -> String:
	var parts: PackedStringArray = []
	for pair: Array in cost:
		var id := StringName(pair[0])
		parts.append("%d %s" % [int(pair[1]), ItemDB.get_item(id).name if ItemDB.has_item(id) else String(id)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
