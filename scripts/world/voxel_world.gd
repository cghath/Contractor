class_name VoxelWorld
extends Node3D
## Destructible structures made of 10 cm voxels. Every peer builds the same base structures
## locally, then applies the host's ordered edit log, so only small edit events cross the
## network, and the same log is what gets saved.
##
## Every voxel has a material (Mat, MATERIALS): rounds go through wood and sheet metal
## (leaving calibre-sized bullet holes; a voxel breaks only after many rounds through it) and stop in concrete, steel or deep
## enough stacks, leaving only a small impact mark there (Ballistics, trace_round). Blasts
## take out each material within its own share of the radius (server_blast).
##
## The host checks every carve for a breach, a gap a soldier now fits through, and reports
## it with `breached` so the navigation around it is rebaked (NavBuilder).
##
## There is no voxel stream, so a block that unloads would come back without its edits: keep
## the bounds small enough that viewers always cover all of it. A zone (ZoneLevel) holds
## many small voxel worlds, one per module, and streams whole worlds in and out instead:
## each one is rebuilt from its base structures and its own edit log (module_id, edit_sink).

signal structures_built
## Host only. Carving opened a gap in a structure that a soldier fits through; `area_m` is
## the gap (this node's space, metres). NavBuilder rebakes the navigation around it.
signal breached(area_m: AABB)
## Every peer: voxels in `box` (voxel units, terrain space) were just cleared, by an edit or
## its replay (a zone module keeps its streamed-out proxy up to date from it).
signal carved(box: AABB)

const VOXEL_SIZE := 0.1
## World materials, set by the structure that places the voxels (add_box_m). PAINTED is
## painted concrete; STEEL is thick steel (stops rounds like concrete); SHEET_METAL is thin
## sheet (a container's walls, a roof); SANDBAG is filled sandbags or packed earth.
## Append new materials at the end: edit logs and saves store these values.
## MUD_BRICK to DIRT_BERM come from the faction pack's worldspace material registry (colours
## only so far: without a MATERIALS entry they stop rounds like concrete).
enum Mat {
	EMPTY, CONCRETE, PAINTED, WOOD, STEEL,
	MUD_BRICK, STONE, LIMESTONE, BASALT, TUFF, CORAL_STONE, BRICK, CINDER_BLOCK, PLASTER,
	ROOF_TILE, FIBRE_CEMENT, CORRUGATED_IRON, THATCH, TARP, GLASS, SANDBAG, HESCO, DIRT_BERM,
	SHEET_METAL,
	# Colour variants (world visual pass, 2026-10-20): each takes rounds and blasts exactly as the
	# material it's a shade of (VARIANT_OF, base_mat), so a building's own wall colour, its window
	# frames, plinth and signs, sandbags' bag pattern and HESCO's frames change nothing in a fight.
	MUD_LIGHT, MUD_RED, MUD_WASH, MUD_DARK, BRICK_DARK, BRICK_TAN,
	RENDER_CREAM, RENDER_OCHRE, RENDER_BLUE, RENDER_GREEN, RENDER_PINK, BLOCK_DIRTY,
	STONE_WARM, STONE_GREY, TRIM_WHITE, TRIM_DARK, WOOD_GREEN, WOOD_BLUE, WOOD_DARK,
	SIGN_RED, SIGN_YELLOW, SIGN_BLUE, SANDBAG_DARK, HESCO_FRAME, STEEL_OLIVE, SHEET_RUST, SHEET_GREEN,
}
## One colour per Mat, in the same order. Index 0 must stay transparent: the cubes mesher
## treats it as empty.
const PALETTE: Array[Color] = [
	Color(0, 0, 0, 0), Color("8a8577"), Color("5f6b58"), Color("8c6a46"), Color("4a4d50"),
	Color("a47e57"), Color("8f8676"), Color("d6caa8"), Color("4b4845"), Color("c48a6a"),
	Color("cbbf9f"), Color("9c5a3c"), Color("9a978f"), Color("e3dccb"), Color("a4553b"),
	Color("a5a49c"), Color("8b8e8c"), Color("b49a5e"), Color("3f6d8c"), Color("9fbcc4"),
	Color("b8a378"), Color("a99a6c"), Color("8a6f4e"),
	Color("7b8a8c"),
	Color("b8956a"), Color("94634a"), Color("d2c6a6"), Color("7a5a3f"), Color("7a4431"), Color("b3895e"),
	Color("ddd2b2"), Color("c9a468"), Color("9fb3bb"), Color("a9b493"), Color("c99d86"), Color("78756d"),
	Color("a59478"), Color("74726c"), Color("e4ddcb"), Color("514d47"), Color("4d6a55"), Color("4a6580"), Color("5a4231"),
	Color("a33f2e"), Color("c9a238"), Color("3d5d88"), Color("8d7a50"), Color("7b7358"), Color("586243"), Color("8a5b3e"), Color("5e6d58"),
]
## The material each colour variant is a shade of: rounds, blasts, chips and holes go by that
## (base_mat). Anything not listed is its own.
const VARIANT_OF := {
	Mat.MUD_LIGHT: Mat.MUD_BRICK, Mat.MUD_RED: Mat.MUD_BRICK, Mat.MUD_WASH: Mat.MUD_BRICK, Mat.MUD_DARK: Mat.MUD_BRICK,
	Mat.BRICK_DARK: Mat.BRICK, Mat.BRICK_TAN: Mat.BRICK,
	Mat.RENDER_CREAM: Mat.CINDER_BLOCK, Mat.RENDER_OCHRE: Mat.CINDER_BLOCK, Mat.RENDER_BLUE: Mat.CINDER_BLOCK,
	Mat.RENDER_GREEN: Mat.CINDER_BLOCK, Mat.RENDER_PINK: Mat.CINDER_BLOCK, Mat.BLOCK_DIRTY: Mat.CINDER_BLOCK,
	Mat.STONE_WARM: Mat.STONE, Mat.STONE_GREY: Mat.STONE, Mat.TRIM_WHITE: Mat.CONCRETE, Mat.TRIM_DARK: Mat.CONCRETE,
	Mat.WOOD_GREEN: Mat.WOOD, Mat.WOOD_BLUE: Mat.WOOD, Mat.WOOD_DARK: Mat.WOOD,
	Mat.SIGN_RED: Mat.PAINTED, Mat.SIGN_YELLOW: Mat.PAINTED, Mat.SIGN_BLUE: Mat.PAINTED,
	Mat.SANDBAG_DARK: Mat.SANDBAG, Mat.HESCO_FRAME: Mat.HESCO, Mat.STEEL_OLIVE: Mat.STEEL,
	Mat.SHEET_RUST: Mat.SHEET_METAL, Mat.SHEET_GREEN: Mat.SHEET_METAL,
}
## How each material takes fire (Ballistics walks a round through the voxels, trace_round):
## - "loss_j_per_m": energy a round loses per metre of it. INF stops every small-arms round:
##   no hole, only a small surface mark (server_mark). A round that runs out of energy inside
##   any material stops there with a mark too; one that gets through leaves a bullet hole
##   the size of its calibre where it went in and came out (server_shot) and carries on with
##   what it has left. A voxel only breaks out once HOLES_TO_BREAK rounds have gone through it.
## - "blast": share of a blast's radius (server_blast) that takes this material out.
## - "mark": colour of the impact mark a stopped round leaves.
## Proposed values against data/rounds.json (M855 about 1650 J at the muzzle, 9 mm about
## 550 J, M80 about 3350 J): a 10 cm wood wall costs 250 J (a 9 mm gets through two), 66 cm
## of wood stops an M855 and 1.4 m an M80 (a crate stack), a sheet-metal wall costs 150 J,
## 40 cm of sandbags stops anything, concrete and steel stop everything.
const MATERIALS := {
	Mat.CONCRETE: {"name": "concrete", "loss_j_per_m": INF, "blast": 0.4, "mark": Color("3b3935")},
	Mat.PAINTED: {"name": "painted concrete", "loss_j_per_m": INF, "blast": 0.4, "mark": Color("3b3935")},
	Mat.WOOD: {"name": "wood", "loss_j_per_m": 2500.0, "blast": 1.0, "mark": Color("2e2014")},
	Mat.STEEL: {"name": "steel", "loss_j_per_m": INF, "blast": 0.15, "mark": Color("b9bcbf")},
	Mat.SHEET_METAL: {"name": "sheet metal", "loss_j_per_m": 1500.0, "blast": 1.0, "mark": Color("1d2022")},
	Mat.SANDBAG: {"name": "sandbags", "loss_j_per_m": 12000.0, "blast": 0.6, "mark": Color("54472f")},
	# Captain, 2026-10-18 ("reintroduce easier voxel damage for wooden buildings, maybe mud
	# buildings too"): mud brick and plaster were falling back to concrete (stop everything,
	# never break). Mud brick soaks a round in about 25 cm (a 7.62x54R gets through a thin wall)
	# and crumbles to blasts; plaster less; thatch and tarp next to nothing.
	Mat.MUD_BRICK: {"name": "mud brick", "loss_j_per_m": 14000.0, "blast": 0.8, "mark": Color("5a4630")},
	Mat.PLASTER: {"name": "plaster", "loss_j_per_m": 6000.0, "blast": 0.9, "mark": Color("8a8478")},
	Mat.THATCH: {"name": "thatch", "loss_j_per_m": 800.0, "blast": 1.0, "mark": Color("4a3c20")},
	Mat.TARP: {"name": "tarp", "loss_j_per_m": 200.0, "blast": 1.0, "mark": Color("2a3a44")},
}
## Rounds stopped in a surface voxel of these materials chip it, and it breaks out after this
## many (mud and plaster crumble under fire; server_mark).
const CHIPS_TO_BREAK := {Mat.MUD_BRICK: 5, Mat.PLASTER: 4}
## Impact marks: a stopped round leaves a small crack or chip on the surface (MARK_SIZE_M
## across, nothing carved), kept in the edit log like any other edit. The host records at
## most MARKS_PER_VOXEL in one surface voxel (sustained fire on one spot doesn't grow the
## log), and only the newest MAX_MARKS are shown. A mark goes when its voxel is carved away.
const MARK_SIZE_M := 0.05
const MARKS_PER_VOXEL := 6
const MAX_MARKS := 8192
## Bullet holes (Captain's playtest call: close to the calibre, not a whole 10 cm voxel): a
## round through wood or sheet metal leaves a hole decal on the way in and out, a dark core
## the round's diameter (HOLE_DECAL_SCALE times it across, the rest a splintered or bare-metal
## rim), bigger on the way out of wood. At most HOLE_MARKS_PER_VOXEL show on one voxel face,
## and the voxel breaks out after HOLES_TO_BREAK rounds through it.
const HOLE_DECAL_SCALE := 2.5
const HOLE_EXIT_SCALE := {Mat.WOOD: 1.6, Mat.SHEET_METAL: 1.15}
const HOLE_MARKS_PER_VOXEL := 16
const HOLES_TO_BREAK := {Mat.WOOD: 4, Mat.SHEET_METAL: 16, Mat.MUD_BRICK: 3, Mat.PLASTER: 3, Mat.THATCH: 2, Mat.TARP: 1}  # wood was 10 (Captain, 2026-10-18: easier)
## Rim colour of a bullet hole by material (the core is near black).
const HOLE_RIM := {Mat.WOOD: Color("c9a877"), Mat.SHEET_METAL: Color("b8bcc0")}
## trace_round: a round walks at most WALK_MAX_M through solid voxels (deeper counts as
## stopped), and looks SEEK_M past where the collider said it hit for the first solid voxel
## (the collider can lag a fresh hole by a frame or two).
const WALK_MAX_M := 4.0
const SEEK_M := 0.25
## Edit area, in voxels (the compound's; a zone module sets its own `bounds`).
const BOUNDS := AABB(Vector3(-220, -8, -220), Vector3(440, 56, 440))
## Viewer range. A VoxelViewer's view_distance is in metres (measured: 64 loads a block 50 m
## away on this 0.1-scaled terrain); the terrain's max_view_distance caps it in voxels. Must
## reach every corner of the bounds from anywhere players go.
const VIEW_DISTANCE := 640
## Voxels a mesh block spans (VoxelTerrain: 16 or 32). 32 is 3.2 m: an eighth as many blocks to draw.
const MESH_BLOCK := 32
## Breach detection (host, after every carve, see _check_breaches). A soldier (NavBuilder's
## agent: radius 0.25 m, height 1.75 m) fits through where a column that used to be wall
## has clear columns BREACH_HALF_WIDTH either side (0.5 m wide in all), clear from
## BREACH_FLOOR (lower rubble is stepped over: agent_max_climb is 0.25 m) up to
## BREACH_TOP. Voxels, measured from the ground. A bullet hole is far too small, so bullet
## holes never count; checks run at most every BREACH_CHECK_S.
const BREACH_HALF_WIDTH := 2
const BREACH_FLOOR := 2
const BREACH_TOP := 18
const BREACH_CHECK_S := 0.25

var terrain: VoxelTerrain
## Set before the node enters the tree: the edit area (voxels) and the terrain's view
## distance cap (voxels). A zone module sets its own (ZoneModules.bounds_voxels).
var bounds := BOUNDS
var view_distance := VIEW_DISTANCE
## A zone module's id (empty for the compound). With an edit_sink, the host's edits go to
## the sink (the zone, which logs them per module and sends them to every peer) instead of
## GameState.voxel_edits and this node's own RPC: a module may not exist on every peer.
var module_id := ""
## Host only: func(world: VoxelWorld, edit: Dictionary), which must apply the edit here too.
var edit_sink := Callable()
var _tool: VoxelTool
var _structures: Array = []  # [begin: Vector3i, end: Vector3i, mat]
## 1 for each of _structures that is skin (add_box_m's `skin`): stamped like the rest, but not a
## structure of its own for navigation (structure_boxes_m, solid_boxes_m).
var _skin := PackedByteArray()
## Host: 1 for each of _structures that carving (or a later empty box) may have changed since
## it was stamped; 0: still solid as built, so solid_boxes_m needn't read its voxels.
var _touched := PackedByteArray()
## Tests: solid_boxes_m reads every structure's voxels, carved or not.
var read_all_voxels := false
var _structure_area := AABB()
var _built := false
var _next_structure := 0  # how many of _structures are stamped so far
## The base structures are stamped a few at a time, at most BUILD_BUDGET_MS a frame (a
## generated town is over a thousand boxes: all at once held a frame for half a second).
const BUILD_BUDGET_MS := 4.0
## On slow frames the budget grows to this share of the last frame, up to BUILD_BUDGET_MAX_MS:
## at 2-3 frames a second a fixed 4 ms stamped a city's blocks for minutes (F-233: CI's
## perfcases, and a slow PC's city the same). Over ~12 fps it stays BUILD_BUDGET_MS. Proposed.
const BUILD_FRAME_SHARE := 0.03
const BUILD_BUDGET_MAX_MS := 12.0
## The voxel engine loads a data block (all air: the generator makes none) only while a
## VoxelViewer covers it, keeping its own count of who covers what, and ranks the loading by the
## distance to the nearest viewer. With a hundred-odd AI viewers coming and going a far block can
## wait behind everything nearer (on CI's city most of a block's area was still to load at 5 s) or
## be lost from that count for good, and a build waiting on its area waited forever (F-303: one
## city block a run never built on CI). A build whose area has been short of blocks LOAD_WAIT_S
## puts the missing ones in itself, empty, as the generator would have (_fill_missing_blocks); a
## block lost after stamping started takes its boxes with it, so the stamping starts over. Proposed.
const LOAD_WAIT_S := 5.0
var _area_short_since := -1.0  # Time (s) the build's area was first seen short of blocks, -1 while whole
var _filled_blocks := 0  # data blocks the build put in itself (build_progress)
var _to_fill: Array[Vector3i] = []  # the blocks this round of filling still has to put in
var _fill_round := Vector3i.ZERO  # this round: missing at its start, put in, usec spent
var _pending: Array = []
var _dirty: Array[AABB] = []  # host: carved voxel boxes not checked for breaches yet
var _breached := {}           # host: Vector2i columns already reported as part of a gap
var _next_breach_check := 0.0
## Impact marks, oldest first: serial -> [position, normal (voxel units, terrain space), Mat,
## the surface voxel it sits on]. Every peer builds the same from the edit log.
var _marks := {}
var _mark_serial := 0
var _mark_cells := {}  # surface voxel (Vector3i) -> Array of mark serials on it
var _marks_dirty := false
var _mark_mesh: MultiMeshInstance3D
var _hole_mesh: MultiMeshInstance3D
var _hole_hits := {}  # voxel (Vector3i) -> rounds that have gone through it (every peer)


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
	terrain.material_override = surface_material()
	terrain.bounds = aligned(bounds, MESH_BLOCK)  # whole mesh blocks: a block past the edge has no data (VoxelTerrain asserts)
	terrain.max_view_distance = view_distance
	terrain.mesh_block_size = MESH_BLOCK  # (perf, 2026-10-19: 16-voxel blocks made a town thousands of draws, each again per shadow cascade)
	terrain.collision_layer = 1
	add_child(terrain)
	_tool = terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_COLOR
	add_to_group(&"voxel_worlds")
	_mark_mesh = _make_mark_mesh()
	terrain.add_child(_mark_mesh)  # in the terrain's space: voxel units
	_hole_mesh = _make_mark_mesh(_hole_texture(), "BulletHoles")
	terrain.add_child(_hole_mesh)


## `box` (voxels) grown out to whole blocks of `size` voxels.
static func aligned(box: AABB, size: int) -> AABB:
	var lo := (box.position / size).floor() * size
	var hi := (box.end / size).ceil() * size
	return AABB(lo, hi - lo)


## Grows the edit area (`bounds`) to hold every structure added so far, FIT_MARGIN voxels round
## them, and the view distance to reach across all of it, before the structures are built; a
## world whose structures are inside its bounds is left as it is. F-121 (cghath's queue item 1.8):
## the vehicle range's concrete blocks and sandbag wall (z -30 and -45 m) lay outside the
## compound's 22 m bounds, so they were never built (no voxels, no collision); CompoundLevel calls
## this once its structures are added. Returns whether it grew.
const FIT_MARGIN := 20
func fit_structures() -> bool:
	if _structures.is_empty() or _built or bounds.encloses(_structure_area):
		return false
	bounds = bounds.merge(_structure_area.grow(FIT_MARGIN))
	var across := Vector2(bounds.size.x, bounds.size.z).length()
	view_distance = maxi(view_distance, ceili(across))
	if terrain:
		terrain.bounds = aligned(bounds, MESH_BLOCK)
		terrain.max_view_distance = view_distance
	print("[world] edit area grown to hold its structures: %s voxels, view %d" % [bounds, view_distance])
	return true


## Adds a solid box, in metres, relative to this node. Call before structures are built.
## `skin`: a box that only dresses the structures (a building's window frames, a cornice, a
## sandbag wall's bag pattern: ZoneModules.skin), recolouring voxels they already have or standing
## above head height: stamped after them like any box, carved like any voxel, but left out of the
## boxes navigation is baked from (structure_boxes_m, solid_boxes_m).
func add_box_m(from_m: Vector3, to_m: Vector3, mat: Mat, skin := false) -> void:
	var a := Vector3i((from_m / VOXEL_SIZE).round())
	var b := Vector3i((to_m / VOXEL_SIZE).round())
	if skin and (a.x == b.x or a.y == b.y or a.z == b.z):
		return  # a skin box thinner than half a voxel rounds away to nothing
	_structures.append([a.min(b), a.max(b) - Vector3i.ONE, mat])
	_skin.append(1 if skin else 0)
	var box := AABB(Vector3(a.min(b)), Vector3((a - b).abs()))
	_structure_area = box if _structures.size() == 1 else _structure_area.merge(box)
	_touched.append(1 if mat == Mat.EMPTY else 0)
	if mat == Mat.EMPTY:
		_touch(box)  # an empty box stamped over earlier ones takes voxels out of them


## Marks the structures that `box` (voxel units) reaches as no longer as built (solid_boxes_m).
func _touch(box: AABB) -> void:
	var area := box.grow(1.0)
	for i in _structures.size():
		var s: Array = _structures[i]
		if _touched[i] == 0 and area.intersects(AABB(Vector3(s[0]), Vector3(s[1] - s[0] + Vector3i.ONE))):
			_touched[i] = 1


func is_built() -> bool:
	return _built


## How far the build has got, for a test's message: "built", or how many boxes are stamped and
## whether the voxel engine has loaded the build's area yet (nothing is stamped till it has: how
## many of its data blocks are missing), and how many blocks the build put in itself.
func build_progress() -> String:
	var filled := (", %d data blocks put in by the build" % _filled_blocks) if _filled_blocks > 0 else ""
	if _built:
		return "built" + filled
	var area := "not loaded"
	if _tool != null and not _structures.is_empty():
		var missing := missing_blocks().size()
		area = "loaded" if missing == 0 else "%d of %d data blocks not loaded" % [missing, _area_blocks().get_volume()]
	return "building: %d of %d boxes stamped, area %s%s" % [_next_structure, _structures.size(), area, filled]


## The build's time a frame (ms): BUILD_BUDGET_MS, or more on slow frames (BUILD_FRAME_SHARE).
static func _build_budget_ms(delta: float) -> float:
	return clampf(delta * 1000.0 * BUILD_FRAME_SHARE, BUILD_BUDGET_MS, BUILD_BUDGET_MAX_MS)


## The voxels the build needs loaded (voxel units): the structures' area out to whole mesh blocks
## and the voxel round them the mesher reads (so their meshes and collision can be made), inside
## the terrain's bounds. Nothing is stamped till every data block of it is loaded.
func _build_area() -> AABB:
	return aligned(_structure_area, MESH_BLOCK).grow(1.0).intersection(terrain.bounds)


## _build_area in data blocks, as the voxel engine counts it for is_area_editable.
func _area_blocks() -> AABB:
	var bs := float(terrain.get_data_block_size())
	var area := _build_area()
	var lo := (area.position / bs).floor()
	return AABB(lo, (area.end / bs).ceil() - lo)


## The data blocks of the build's area the voxel engine hasn't got loaded (block coordinates).
func missing_blocks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var box := _area_blocks()
	var lo := Vector3i(box.position)
	var hi := Vector3i(box.end)
	for z in range(lo.z, hi.z):
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				if not terrain.has_data_block(Vector3i(x, y, z)):
					out.append(Vector3i(x, y, z))
	return out


## Puts the data blocks of the build's area the voxel engine hasn't loaded in itself, empty,
## as the generator makes them (LOAD_WAIT_S), till the frame's build budget is spent (`until`,
## usec: on CI's city most of a block's area, 7000-odd blocks at about 4 us each, was still to
## load at 5 s); returns whether this round is done. The engine counts the viewers covering each one
## (try_set_block_data), so they unload as any block does; a block no viewer covers stays out
## (nobody is near enough for it to be loaded).
func _fill_missing_blocks(waited_s: float, until: int) -> bool:
	var started := Time.get_ticks_usec()
	if _to_fill.is_empty():
		_to_fill = missing_blocks()
		_fill_round = Vector3i(_to_fill.size(), 0, 0)
	var bs := terrain.get_data_block_size()
	var n := 0
	while not _to_fill.is_empty() and (n % 64 != 0 or Time.get_ticks_usec() < until):
		var b: Vector3i = _to_fill.pop_back()
		n += 1
		if terrain.has_data_block(b):
			continue  # the engine got there meanwhile
		var empty := VoxelBuffer.new()  # (one each: the terrain keeps the buffer itself)
		empty.create(bs, bs, bs)
		if terrain.try_set_block_data(b, empty):
			_fill_round.y += 1
		elif _fill_round.y == 0 and n >= 16:
			_to_fill.clear()  # no viewer near (e.g. a client's compound before it joins): try again later
	_fill_round.z += Time.get_ticks_usec() - started
	FrameCost.spent(&"voxels", started)
	if not _to_fill.is_empty():
		return false
	_filled_blocks += _fill_round.y
	if _fill_round.y > 0:  # (none: no viewer near yet, e.g. a client's compound before it joins)
		print("[world] %s: %d of %d data blocks of the build's area not loaded by the voxel engine in %.0f s; put in empty: %d in %.1f ms (the rest no viewer covers or had loaded)" % [
			module_id if module_id != "" else String(name), _fill_round.x, _area_blocks().get_volume(), waited_s, _fill_round.y, _fill_round.z / 1000.0])
	return true


## Whether every mesh block of the structures is meshed as its voxels now stand, and the voxel
## engine has no meshing or main-thread work (applying meshes and their collision) left queued:
## the collision is as the voxels are. (The engine's queues are every terrain's: a caller should
## give up waiting after a while, as ZoneModule does.)
func is_meshed() -> bool:
	if not _built or not terrain.is_area_meshed(_structure_area):
		return false
	var tasks: Dictionary = VoxelEngine.get_stats().get("tasks", {})
	return int(tasks.get("meshing", 0)) == 0 and int(tasks.get("main_thread", 0)) == 0


## The base structures as boxes in metres, in this node's space (for navigation baking).
func structure_boxes_m() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for i in _structures.size():
		if _skin[i] == 1:
			continue
		var s: Array = _structures[i]
		var begin := Vector3(s[0]) * VOXEL_SIZE
		var end := Vector3(s[1] + Vector3i.ONE) * VOXEL_SIZE
		boxes.append(AABB(begin, end - begin))
	return boxes


func _process(delta: float) -> void:
	if _built:
		_check_breaches()
		return
	if _structures.is_empty():
		return
	# Blocks only exist once a VoxelViewer (on a player) has loaded them, or the build put them in
	# (LOAD_WAIT_S).
	if not _tool.is_area_editable(_build_area()):
		var now := Time.get_ticks_msec() / 1000.0
		if _next_structure > 0:
			print("[world] %s: a data block of the build's area went after %d of %d boxes were stamped; stamping again" % [
				module_id if module_id != "" else String(name), _next_structure, _structures.size()])
			_next_structure = 0  # its stamped voxels went with it (every box again, in order, comes out the same)
		if _area_short_since < 0.0:
			_area_short_since = now
		elif now - _area_short_since >= LOAD_WAIT_S:
			if _fill_missing_blocks(now - _area_short_since, Time.get_ticks_usec() + int(_build_budget_ms(delta) * 1000.0)):
				_area_short_since = now  # (blocks no viewer covers: tried again after as long)
		return
	_area_short_since = -1.0
	_tool.mode = VoxelTool.MODE_SET
	var started := Time.get_ticks_usec()
	var until := started + int(_build_budget_ms(delta) * 1000.0)
	while _next_structure < _structures.size():
		var s: Array = _structures[_next_structure]
		_tool.value = s[2]
		_tool.do_box(s[0], s[1])
		_next_structure += 1
		if Time.get_ticks_usec() >= until:
			FrameCost.spent(&"voxels", started)
			return
	_built = true
	set_process(not _dirty.is_empty())
	for edit: Dictionary in _pending:
		_apply(edit)  # saved or early edits: the host checks them for breaches too
	_pending.clear()
	FrameCost.spent(&"voxels", started)
	print("[world] voxel structures built (%d boxes)" % _structures.size())
	structures_built.emit()


## The structures' look (Captain, 2026-10-18: "all of our buildings need a pass so they look
## better"): the palette colour (sRGB) with each voxel a little lighter or darker than its
## neighbours (VOXEL_JITTER) so a wall stops reading as one flat slab, and on the rougher, lighter
## materials (sandbags, mud brick, block, plaster: brighter than COURSE_MIN_LUMA) a darker course
## line every COURSE_VOXELS voxels up a wall. Shared by every voxel world.
const VOXEL_JITTER := 0.13
const COURSE_VOXELS := 2.0
const COURSE_LINE := 0.12
const COURSE_DARK := 0.86
const COURSE_MIN_LUMA := 0.33
static var _surface: ShaderMaterial


static func surface_material() -> ShaderMaterial:
	if _surface == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode diffuse_burley;
uniform float jitter = %f;
uniform float course_voxels = %f;
uniform float course_line = %f;
uniform float course_dark = %f;
uniform float course_min_luma = %f;
varying vec3 local_pos;
varying vec3 local_normal;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void vertex() {
	local_pos = VERTEX;   // voxel units (the terrain is scaled by the voxel size)
	local_normal = NORMAL;
}
void fragment() {
	vec3 srgb = COLOR.rgb;
	vec3 cell = floor(local_pos - local_normal * 0.5);
	float k = 1.0 + (hash(cell) - 0.5) * jitter;
	float luma = dot(srgb, vec3(0.299, 0.587, 0.114));
	if (abs(local_normal.y) < 0.5 && luma > course_min_luma && fract(local_pos.y / course_voxels) < course_line) {
		k *= course_dark;
	}
	ALBEDO = pow(clamp(srgb * k, 0.0, 1.0), vec3(2.2));
	ROUGHNESS = 0.9;
}
""" % [VOXEL_JITTER, COURSE_VOXELS, COURSE_LINE, COURSE_DARK, COURSE_MIN_LUMA]
		_surface = ShaderMaterial.new()
		_surface.shader = shader
	return _surface


## Host only. Removes a sphere of voxels of any material around a world-space point.
func server_carve(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	_server_edit({"op": "carve", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE})


## Host only. A blast (a frag) at a world-space point: takes out each material within its
## share of `radius_m` (MATERIALS "blast"), so wood and sheet metal go and concrete chips.
func server_blast(world_position: Vector3, radius_m: float) -> void:
	var c := terrain.to_local(world_position)
	_server_edit({"op": "blast", "c": [c.x, c.y, c.z], "r": radius_m / VOXEL_SIZE})


## Host only. Clears single voxels (voxel coordinates, as trace_round gives them): the hole
## a round made going through.
func server_holes(voxels: Array) -> void:
	if voxels.is_empty():
		return
	var flat: Array = []
	for v: Vector3i in voxels:
		flat.append_array([v.x, v.y, v.z])
	_server_edit({"op": "holes", "v": flat})


## Host only. A round went through wood or sheet metal: a bullet hole `calibre_m` across
## where it went in (`entry`, facing `entry_normal`) and came out (`exit`, facing
## `exit_normal`), and one more round through each of `voxels` (trace_round's), which break
## out once they reach HOLES_TO_BREAK.
func server_shot(entry: Vector3, entry_normal: Vector3, exit: Vector3, exit_normal: Vector3, calibre_m: float, voxels: Array, mat: int) -> void:
	var a := terrain.to_local(entry)
	var b := terrain.to_local(exit)
	var basis := terrain.global_basis.inverse()
	var an := (basis * entry_normal).normalized()
	var bn := (basis * exit_normal).normalized()
	var flat: Array = []
	for v: Vector3i in voxels:
		flat.append_array([v.x, v.y, v.z])
	_server_edit({"op": "shot", "a": _snap3(a), "an": _snap3(an), "b": _snap3(b), "bn": _snap3(bn),
		"d": snappedf(calibre_m, 0.0001), "m": mat, "v": flat})


static func _snap3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Rounds that have gone through the voxel at a world-space point (it breaks out at
## HOLES_TO_BREAK).
func holes_through(world_position: Vector3) -> int:
	return int(_hole_hits.get(Vector3i(terrain.to_local(world_position).floor()), 0))


## How many bullet hole decals there are (every peer has the same).
func bullet_hole_count() -> int:
	return _hole_count


## Host only. A small impact mark (a crack or chip, nothing carved) where a round stopped on
## the surface at `world_position` facing `normal`, in `mat`'s colour. Returns false when the
## surface voxel there already has MARKS_PER_VOXEL marks (nothing is recorded).
func server_mark(world_position: Vector3, normal: Vector3, mat: int) -> bool:
	var p := terrain.to_local(world_position)
	var n := (terrain.global_basis.inverse() * normal).normalized()
	if n.is_zero_approx():
		n = Vector3.UP
	if (_mark_cells.get(_mark_cell(p, n), []) as Array).size() >= MARKS_PER_VOXEL:
		return false
	_server_edit({"op": "mark", "p": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)],
		"n": [snappedf(n.x, 0.001), snappedf(n.y, 0.001), snappedf(n.z, 0.001)], "m": mat})
	if CHIPS_TO_BREAK.has(base_mat(mat)) and (_mark_cells.get(_mark_cell(p, n), []) as Array).size() >= int(CHIPS_TO_BREAK[base_mat(mat)]):
		server_holes([Vector3i((p - n * 0.5).floor())])  # chipped through: the voxel crumbles out
	return true


func _server_edit(edit: Dictionary) -> void:
	if edit_sink.is_valid():
		edit_sink.call(self, edit)
		return
	GameState.voxel_edits.append(edit)
	apply_edit.rpc(edit)


## How many impact marks there are (every peer has the same).
func mark_count() -> int:
	return _marks.size()


## How many impact marks lie within `radius_m` of a world-space point.
func marks_near(world_position: Vector3, radius_m: float) -> int:
	var p := terrain.to_local(world_position)
	var r := radius_m / VOXEL_SIZE
	var count := 0
	for serial: int in _marks:
		if (_marks[serial][0] as Vector3).distance_to(p) <= r:
			count += 1
	return count


## The material of the voxel at a world-space point (Mat.EMPTY for air or unloaded voxels).
func material_at(world_position: Vector3) -> int:
	var v := Vector3i(terrain.to_local(world_position).floor())
	if not is_area_readable(AABB(Vector3(v), Vector3.ONE)):
		return Mat.EMPTY
	return _tool.get_voxel(v)


## Energy (J) a round loses per metre of material `mat`: INF for what stops every
## small-arms round (concrete, steel, and anything unknown).
static func loss_per_m(mat: int) -> float:
	return float((MATERIALS.get(base_mat(mat), {}) as Dictionary).get("loss_j_per_m", INF))


## The material `mat` takes fire as: itself, or for a colour variant the material it's a shade of
## (VARIANT_OF).
static func base_mat(mat: int) -> int:
	return int(VARIANT_OF.get(mat, mat))


## Host only. Walks a round into the voxels from `entry` (world space, where its ray met a
## structure) along `direction` with `energy_j` joules. Returns:
## - "stopped": it ran out of energy inside (or the material stops everything, or it's
##   deeper than WALK_MAX_M, or the voxels aren't loaded);
## - "material": the first solid voxel's material (Mat.EMPTY if none was found);
## - "voxels": the voxels it passed through (empty when stopped: a stop makes no hole);
## - "exit": where it came out (world space), past the last solid voxel;
## - "exit_normal": the outward normal of the face it came out of (world space);
## - "lost_j": the energy it lost.
## A stretch of solid voxels ends at the first empty one; whatever is behind is a separate
## hit for the ray.
func trace_round(entry: Vector3, direction: Vector3, energy_j: float) -> Dictionary:
	var result := {"stopped": false, "material": Mat.EMPTY, "voxels": [], "exit": entry, "exit_normal": direction, "lost_j": 0.0}
	var dir := terrain.global_basis.inverse() * direction
	var units_per_m := dir.length()
	if units_per_m <= 0.0:
		result.stopped = true
		return result
	dir /= units_per_m
	var start := terrain.to_local(entry) + dir * 0.01
	var max_t := WALK_MAX_M * units_per_m
	var reach := AABB(start, Vector3.ZERO).expand(start + dir * max_t).grow(1.0)
	if not is_area_readable(reach):
		result.stopped = true
		result.material = Mat.CONCRETE
		return result
	var cell := Vector3i(start.floor())
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for axis in 3:
		if dir[axis] > 0.0:
			t_max[axis] = (cell[axis] + 1 - start[axis]) / dir[axis]
			t_delta[axis] = 1.0 / dir[axis]
		elif dir[axis] < 0.0:
			t_max[axis] = (start[axis] - cell[axis]) / -dir[axis]
			t_delta[axis] = -1.0 / dir[axis]
		else:
			t_max[axis] = INF
			t_delta[axis] = INF
	var seek_t := SEEK_M * units_per_m
	var remaining := energy_j
	var inside := false
	var t := 0.0
	var passed: Array[Vector3i] = []
	var crossed := Vector3.ZERO  # the face the walk last stepped through (voxel axes)
	while t < max_t:
		var t_next := minf(t_max.x, minf(t_max.y, t_max.z))
		var mat := int(_tool.get_voxel(cell))
		if mat != Mat.EMPTY:
			if not inside:
				inside = true
				result.material = mat
			var per_m := loss_per_m(mat)
			var loss := per_m * maxf(t_next - t, 0.0) / units_per_m if per_m != INF else INF
			if loss >= remaining:
				result.stopped = true
				result.lost_j = maxf(energy_j, 0.0)
				return result
			remaining -= loss
			passed.append(cell)
		elif inside or t > seek_t:
			# Out the far side (or nothing solid here: a hole the collider hasn't caught up with).
			result.voxels = passed
			result.exit = terrain.to_global(start + dir * t)
			result.exit_normal = (terrain.global_basis * crossed).normalized() if not crossed.is_zero_approx() else direction.normalized()
			result.lost_j = energy_j - remaining
			return result
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			cell.x += step.x
			crossed = Vector3(step.x, 0, 0)
			t = t_max.x
			t_max.x += t_delta.x
		elif t_max.y <= t_max.z:
			cell.y += step.y
			crossed = Vector3(0, step.y, 0)
			t = t_max.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			crossed = Vector3(0, 0, step.z)
			t = t_max.z
			t_max.z += t_delta.z
	result.stopped = true
	result.lost_j = maxf(energy_j, 0.0)
	return result


## Host only. Whether the structures between two world-space points stop a round arriving
## with `energy_j` joules: the line meets a structure (or other world geometry) it can't get
## through. Points in the clear, or behind only wood or sheet metal thin enough to shoot
## through, return false. For cover choices (SquadAI).
func stops_round(from: Vector3, to: Vector3, energy_j: float) -> bool:
	var space := get_world_3d().direct_space_state
	var direction := (to - from).normalized()
	var energy := energy_j
	var at := from
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1))
		if hit.is_empty():
			return false
		if VoxelWorld.find_on(hit.collider) != self:
			return true  # the ground or other solid world geometry
		var through := trace_round(hit.position, direction, energy)
		if through.stopped:
			return true
		energy -= float(through.lost_j)
		at = (through.exit as Vector3) + direction * 0.01
		if (at - from).dot(direction) >= (to - from).length():
			return false
	return true


## Host only. stops_round across every voxel world on the line (a zone has one per module):
## whether a round arriving with `energy_j` joules is stopped between the two points by voxels
## it can't get through or by other world geometry (the ground, a module's proxy).
static func stops_round_in(node: Node, from: Vector3, to: Vector3, energy_j: float) -> bool:
	var space := (node as Node3D).get_world_3d().direct_space_state if node is Node3D else null
	if space == null:
		var world := node.get_tree().get_first_node_in_group(&"voxel_worlds") as VoxelWorld
		return world.stops_round(from, to, energy_j) if world else true
	var direction := (to - from).normalized()
	var energy := energy_j
	var at := from
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1))
		if hit.is_empty():
			return false
		var world := VoxelWorld.find_on(hit.collider)
		if world == null:
			var prop := ZoneScatter.round_through(hit, direction, energy)  # a library prop by its material
			if prop.is_empty() or prop.stopped:
				return true  # the ground or other solid world geometry
			energy -= float(prop.lost_j)
			at = (prop.exit as Vector3) + direction * 0.01
			if (at - from).dot(direction) >= (to - from).length():
				return false
			continue
		var through := world.trace_round(hit.position, direction, energy)
		if through.stopped:
			return true
		energy -= float(through.lost_j)
		at = (through.exit as Vector3) + direction * 0.01
		if (at - from).dot(direction) >= (to - from).length():
			return false
	return true


## Host only. Replays a saved edit log locally (the log itself is already in GameState).
func load_edits(edits: Array) -> void:
	for edit: Dictionary in edits:
		apply_edit(edit)


func send_edit_log_to(peer_id: int) -> void:
	_receive_edit_log.rpc_id(peer_id, GameState.voxel_edits)


## Host only. A breaching charge on a wall (Charges, Captain 2026-10-20: "breaching charges need
## to stop leaving big craters in the ground with a small line of unbroken fence or wall that
## cannot be walked past or over by AI"): a doorway cut through the wall behind `world_position`,
## `width_m` wide, from `floor_y` (the ground or floor at the wall's foot, never below it) up
## `height_m`, `depth_m` into the wall along -`normal` (the wall's outer face), every material but
## steel, so a plinth or coping the blast's sphere only chips goes too and nothing is left to trip on.
func server_breach(world_position: Vector3, normal: Vector3, floor_y: float, width_m: float, height_m: float, depth_m: float) -> void:
	var c := terrain.to_local(world_position)
	var f := terrain.to_local(Vector3(world_position.x, floor_y, world_position.z))
	var basis := terrain.global_basis.inverse()
	var n := basis * Vector3(normal.x, 0.0, normal.z).normalized()
	var up := (basis * Vector3.UP).normalized()
	_server_edit({"op": "breach", "c": _snap3(c), "f": _snap3(f), "n": _snap3(n.normalized()), "u": _snap3(up),
		"bw": width_m / VOXEL_SIZE, "bh": height_m / VOXEL_SIZE, "bd": depth_m / VOXEL_SIZE})  # (not "w": a zone keeps its module id there)


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
			var centre := Vector3(c[0], c[1], c[2])
			var r := float(edit["r"])
			_tool.do_sphere(centre, r)
			_carved(AABB(centre - Vector3.ONE * r, Vector3.ONE * r * 2.0))
		"blast":
			var c: Array = edit["c"]
			var centre := Vector3(c[0], c[1], c[2])
			var r := float(edit["r"])
			_blast(centre, r)
			_carved(AABB(centre - Vector3.ONE * r, Vector3.ONE * r * 2.0))
		"breach":
			_apply_breach(edit)
		"holes":
			var v: Array = edit["v"]
			var box := AABB()
			for i in range(0, v.size() - 2, 3):
				var cell := Vector3i(int(v[i]), int(v[i + 1]), int(v[i + 2]))
				_tool.set_voxel(cell, Mat.EMPTY)
				box = AABB(Vector3(cell), Vector3.ONE) if i == 0 else box.merge(AABB(Vector3(cell), Vector3.ONE))
			if v.size() >= 3:
				_carved(box)
		"shot":
			_apply_shot(edit)
		"mark":
			var p: Array = edit["p"]
			var n: Array = edit["n"]
			_add_mark(Vector3(p[0], p[1], p[2]), Vector3(n[0], n[1], n[2]), int(edit.get("m", Mat.CONCRETE)))


## A round through wood or sheet metal (server_shot): hole decals in and out, and voxels
## that have now had HOLES_TO_BREAK rounds through them break out.
func _apply_shot(edit: Dictionary) -> void:
	var mat := int(edit.get("m", Mat.WOOD))
	var size := float(edit.get("d", 0.0057)) * HOLE_DECAL_SCALE
	var a: Array = edit["a"]
	var an: Array = edit["an"]
	var b: Array = edit["b"]
	var bn: Array = edit["bn"]
	_add_hole(Vector3(a[0], a[1], a[2]), Vector3(an[0], an[1], an[2]), mat, size)
	_add_hole(Vector3(b[0], b[1], b[2]), Vector3(bn[0], bn[1], bn[2]), mat, size * float(HOLE_EXIT_SCALE.get(base_mat(mat), 1.0)))
	var v: Array = edit["v"]
	var box := AABB()
	var broke := false
	for i in range(0, v.size() - 2, 3):
		var cell := Vector3i(int(v[i]), int(v[i + 1]), int(v[i + 2]))
		var hits := int(_hole_hits.get(cell, 0)) + 1
		var cell_mat := base_mat(int(_tool.get_voxel(cell)))
		if hits >= int(HOLES_TO_BREAK.get(cell_mat, HOLES_TO_BREAK[Mat.WOOD])):
			_hole_hits.erase(cell)
			_tool.set_voxel(cell, Mat.EMPTY)
			box = AABB(Vector3(cell), Vector3.ONE) if not broke else box.merge(AABB(Vector3(cell), Vector3.ONE))
			broke = true
		else:
			_hole_hits[cell] = hits
	if broke:
		_carved(box)


## A breaching charge's doorway (server_breach): every voxel but steel whose centre lies in the
## box across the wall ("bw" wide, "bd" deep behind "c", "bh" up from the floor point "f"; voxel units).
func _apply_breach(edit: Dictionary) -> void:
	var c := Vector3(edit.c[0], edit.c[1], edit.c[2])
	var f := Vector3(edit.f[0], edit.f[1], edit.f[2])
	var n := Vector3(edit.n[0], edit.n[1], edit.n[2])
	var up := Vector3(edit.u[0], edit.u[1], edit.u[2])
	var along := up.cross(n).normalized()
	var half_w := float(edit.bw) * 0.5
	var h := float(edit.bh)
	var d := float(edit.bd)
	var box := AABB(f, Vector3.ZERO)
	for corner: Vector3 in [c + along * half_w + n, c - along * half_w + n, c + along * half_w - n * d, c - along * half_w - n * d]:
		var flat := corner + up * (f - corner).dot(up)
		box = box.expand(flat).expand(flat + up * h)
	var lo := Vector3i(box.position.floor())
	var hi := Vector3i(box.end.ceil())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var cell := Vector3i(x, y, z)
				var p := Vector3(cell) + Vector3.ONE * 0.5
				var rel := p - c
				var high := (p - f).dot(up)
				var into := -rel.dot(n)
				if high < 0.0 or high > h or absf(rel.dot(along)) > half_w or into < -5.0 or into > d:
					continue
				var mat := base_mat(int(_tool.get_voxel(cell)))
				if mat != Mat.EMPTY and mat != Mat.STEEL:
					_tool.set_voxel(cell, Mat.EMPTY)
	_carved(box)


## Takes out each material within its share of radius `r` around `centre` (voxel units).
## Perf pass (2026-10-22): the blast's box is copied out once, only the sphere's rows are walked in
## it, and the voxels it takes out go back in one paste (a voxel tool read and write per voxel of
## the whole box before: a mortar round was ~130k of each in one frame). The same voxels go.
const _KEEP := 255  # (no material: "leave this voxel be" in the paste)


func _blast(centre: Vector3, r: float) -> void:
	var lo := Vector3i((centre - Vector3.ONE * r).floor())
	var hi := Vector3i((centre + Vector3.ONE * r).ceil())
	var size := hi - lo + Vector3i.ONE
	var src := VoxelBuffer.new()
	src.create(size.x, size.y, size.z)
	_tool.copy(lo, src, 1 << VoxelBuffer.CHANNEL_COLOR, false)
	if src.is_uniform(VoxelBuffer.CHANNEL_COLOR) and int(src.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_COLOR)) == Mat.EMPTY:
		return  # nothing there
	var out := VoxelBuffer.new()
	out.create(size.x, size.y, size.z)
	out.fill(_KEEP, VoxelBuffer.CHANNEL_COLOR)
	var reach := {}  # base material -> (its share of r)^2
	var any := false
	var c := centre - Vector3(lo) - Vector3.ONE * 0.5  # the centre in the box's cells
	var r2 := r * r
	for z in size.z:
		var dz := float(z) - c.z
		if dz * dz > r2:
			continue
		for y in size.y:
			var dy := float(y) - c.y
			var row := r2 - dz * dz - dy * dy
			if row < 0.0:
				continue
			var half := sqrt(row)
			for x in range(maxi(ceili(c.x - half), 0), mini(floori(c.x + half), size.x - 1) + 1):
				var raw := int(src.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR))
				if raw == Mat.EMPTY:
					continue
				var mat := base_mat(raw)
				var lim: float = reach.get(mat, -1.0)
				if lim < 0.0:
					lim = pow(r * float((MATERIALS.get(mat, {}) as Dictionary).get("blast", 1.0)), 2.0)
					reach[mat] = lim
				var dx := float(x) - c.x
				if dx * dx + dy * dy + dz * dz <= lim:
					out.set_voxel(Mat.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					any = true
	if any:
		_tool.paste_masked(lo, out, 1 << VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.CHANNEL_COLOR, _KEEP)


## After voxels in `box` (voxel units) were cleared: marks on voxels that are gone go too,
## and the host checks the area for a breach.
func _carved(box: AABB) -> void:
	carved.emit(box)
	var gone: Array[Vector3i] = []
	var area := box.grow(1.0)
	for cell: Vector3i in _mark_cells:
		if area.has_point(Vector3(cell) + Vector3.ONE * 0.5) and int(_tool.get_voxel(cell)) == Mat.EMPTY:
			gone.append(cell)
	for cell in gone:
		for serial: int in _mark_cells[cell]:
			_drop_mark(serial)
		_mark_cells.erase(cell)
	if multiplayer.is_server():
		_touch(box)
		_dirty.append(box)
		set_process(true)


# --- Impact marks --------------------------------------------------------------------------

## The voxel a mark at `p` facing `n` (voxel units) sits on.
static func _mark_cell(p: Vector3, n: Vector3) -> Vector3i:
	return Vector3i((p - n * 0.5).floor())


func _add_mark(p: Vector3, n: Vector3, mat: int, size_m := MARK_SIZE_M, hole := false) -> void:
	n = n.normalized() if not n.is_zero_approx() else Vector3.UP
	var cell := _mark_cell(p, n)
	_mark_serial += 1
	var mark := [p, n, mat, cell, size_m, hole, -1]  # [6]: its slot in its multimesh (_show_mark)
	_marks[_mark_serial] = mark
	if hole:
		_hole_count += 1
	if not _mark_cells.has(cell):
		_mark_cells[cell] = []
	(_mark_cells[cell] as Array).append(_mark_serial)
	while _marks.size() > MAX_MARKS:
		while not _marks.has(_oldest_mark):
			_oldest_mark += 1  # (serials only grow: the oldest still here is the lowest)
		var oldest := _oldest_mark
		var on: Array = _mark_cells.get(_marks[oldest][3], [])
		on.erase(oldest)
		if on.is_empty():
			_mark_cells.erase(_marks[oldest][3])
		_drop_mark(oldest)
	_show_mark(mark)


## Takes mark `serial` away (its slot hidden and free for the next).
func _drop_mark(serial: int) -> void:
	var mark: Array = _marks.get(serial, [])
	if mark.is_empty():
		return
	_marks.erase(serial)
	var hole := _is_hole(mark)
	if hole:
		_hole_count -= 1
	var slot := int(mark[6]) if mark.size() > 6 else -1
	if slot < 0 or _marks_dirty:
		return
	var mm := (_hole_mesh if hole else _mark_mesh).multimesh
	mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	(_free_holes if hole else _free_marks).append(slot)


## A bullet hole decal `size_m` across, unless that voxel face already shows
## HOLE_MARKS_PER_VOXEL of them.
func _add_hole(p: Vector3, n: Vector3, mat: int, size_m: float) -> void:
	n = n.normalized() if not n.is_zero_approx() else Vector3.UP
	if (_mark_cells.get(_mark_cell(p, n), []) as Array).size() >= HOLE_MARKS_PER_VOXEL:
		return
	_add_mark(p, n, mat, size_m, true)


func _queue_mark_rebuild() -> void:
	if not _marks_dirty:
		_marks_dirty = true
		_rebuild_marks.call_deferred()


## Perf pass (2026-10-22): every mark keeps a slot in its multimesh. A new mark is drawn into a
## free slot (or the next one), a mark that goes hides its slot for the next; the multimeshes
## grow by doubling (a full rebuild then, as every change was before: thousands of marks laid
## again for each new one in a firefight). Marks look the same.
const MARK_SLOTS_MIN := 256
var _hole_count := 0
var _oldest_mark := 1
var _free_marks: Array[int] = []
var _free_holes: Array[int] = []


## Draws `mark` in a slot of its multimesh (a rebuild is due instead when none is free).
func _show_mark(mark: Array) -> void:
	if _marks_dirty:
		return  # the rebuild draws it
	var hole := _is_hole(mark)
	var mm := (_hole_mesh if hole else _mark_mesh).multimesh
	var free := _free_holes if hole else _free_marks
	var slot := -1
	var shown := _shown(mm)
	if not free.is_empty():
		slot = free.pop_back()
	elif shown < mm.instance_count:
		slot = shown
		mm.visible_instance_count = slot + 1
	else:
		_queue_mark_rebuild()  # full: it grows
		return
	mark[6] = slot
	_draw_mark(mm, slot, mark)


## Mark `mark`'s quad in slot `slot` of `mm`: flat on its surface, turned and sized by its
## position so every peer draws it the same.
func _draw_mark(mm: MultiMesh, slot: int, mark: Array) -> void:
	var size := float(mark[4]) / VOXEL_SIZE if mark.size() > 4 else MARK_SIZE_M / VOXEL_SIZE
	var p: Vector3 = mark[0]
	var n: Vector3 = mark[1]
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(n).normalized()
	var basis := Basis(x, n.cross(x), n)
	var h := absi(hash(Vector3i((p * 100.0).round())))
	basis = basis.rotated(n, float(h % 628) / 100.0)
	if _is_hole(mark):
		basis = basis.scaled(Vector3.ONE * size * (0.9 + float(floori(h / 628.0) % 20) / 100.0))
		mm.set_instance_transform(slot, Transform3D(basis, p + n * 0.02))
		mm.set_instance_color(slot, HOLE_RIM.get(base_mat(int(mark[2])), Color("c9a877")))
		return
	basis = basis.scaled(Vector3.ONE * size * (0.7 + float(floori(h / 628.0) % 60) / 100.0))
	mm.set_instance_transform(slot, Transform3D(basis, p + n * 0.03))
	mm.set_instance_color(slot, (MATERIALS.get(base_mat(int(mark[2])), {}) as Dictionary).get("mark", Color("3b3935")))


## Every mark laid again: impact marks in one multimesh, bullet holes in the other, each with
## room to grow (doubling from MARK_SLOTS_MIN).
func _rebuild_marks() -> void:
	_marks_dirty = false
	var holes := _hole_count
	var marks := _marks.size() - holes
	var mm := _mark_mesh.multimesh
	var hm := _hole_mesh.multimesh
	mm.instance_count = _room_for(marks)
	hm.instance_count = _room_for(holes)
	mm.visible_instance_count = marks
	hm.visible_instance_count = holes
	_free_marks.clear()
	_free_holes.clear()
	var i := 0
	var j := 0
	for serial: int in _marks:
		var mark: Array = _marks[serial]
		if _is_hole(mark):
			mark[6] = j
			_draw_mark(hm, j, mark)
			j += 1
		else:
			mark[6] = i
			_draw_mark(mm, i, mark)
			i += 1


## The slots of `mm` in use (visible_instance_count, -1 meaning all of them).
static func _shown(mm: MultiMesh) -> int:
	return mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count


## How many impact marks (not bullet holes) are drawn (tests).
func drawn_marks() -> int:
	return _shown(_mark_mesh.multimesh) - _free_marks.size() if _mark_mesh else 0


## Slots for `n` marks: room to double before the next rebuild.
static func _room_for(n: int) -> int:
	var room := MARK_SLOTS_MIN
	while room < n * 2:
		room *= 2
	return mini(room, MAX_MARKS * 2)


static func _is_hole(mark: Array) -> bool:
	return mark.size() > 5 and bool(mark[5])


func _make_mark_mesh(texture: Texture2D = null, node_name := "ImpactMarks") -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture if texture else _crack_texture()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	quad.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A bullet hole: a near-black core (the round's diameter: 1 / HOLE_DECAL_SCALE of the
## texture across) inside a ragged rim the mark's colour tints (splinters for wood, bare
## metal for sheet metal).
static func _hole_texture() -> ImageTexture:
	const S := 64
	var image := Image.create(S, S, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5560
	var c := Vector2(S, S) * 0.5
	var core := S / (2.0 * HOLE_DECAL_SCALE)
	for y in S:
		for x in S:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var ragged := core * 2.0 + rng.randf_range(-2.0, 3.0) + 3.0 * sin(atan2(p.y - c.y, p.x - c.x) * 5.0)
			if d <= core:
				image.set_pixel(x, y, Color(0.04, 0.04, 0.04))
			elif d <= ragged:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


## A small chip with hairline cracks running out of it (white on clear; each mark tints it).
static func _crack_texture() -> ImageTexture:
	const S := 32
	var image := Image.create(S, S, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1771
	var c := Vector2(S, S) * 0.5
	for y in S:
		for x in S:
			if Vector2(x + 0.5, y + 0.5).distance_to(c) < 3.6 + rng.randf() * 1.2:
				image.set_pixel(x, y, Color.WHITE)
	for k in 6:
		var p := c
		var heading := TAU * k / 6.0 + rng.randf_range(-0.4, 0.4)
		for s in rng.randi_range(7, 13):
			heading += rng.randf_range(-0.6, 0.6)
			p += Vector2.from_angle(heading)
			if p.x < 0.0 or p.y < 0.0 or p.x >= S or p.y >= S:
				break
			image.set_pixel(int(p.x), int(p.y), Color.WHITE)
	return ImageTexture.create_from_image(image)


# --- Breach detection (host) -----------------------------------------------------------

## Host only. Checks the carves since the last check (at most every BREACH_CHECK_S) for a
## gap a soldier now fits through, and reports each new one with `breached`.
func _check_breaches() -> void:
	if _dirty.is_empty():
		set_process(false)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_breach_check:
		return
	_next_breach_check = now + BREACH_CHECK_S
	var boxes := _dirty.duplicate()
	_dirty.clear()
	for box: AABB in boxes:
		var gap: Variant = find_breach(box)
		if gap == null and not is_area_readable(box):
			_dirty.append(box)  # not loaded yet: try again later
		elif gap != null:
			breached.emit(gap)


## Host only. Whether carving in `carved` (a voxel box) opened a new gap a soldier fits
## through in a structure: returns the gap as an AABB in metres (this node's space), or
## null. Columns of a gap found once aren't reported again, so later bullet holes around
## a breach don't count as new ones.
func find_breach(carved: AABB) -> Variant:
	if carved.end.y < BREACH_FLOOR or carved.position.y >= BREACH_TOP:
		return null  # below the rubble line or over head height
	var hw := BREACH_HALF_WIDTH
	var lo := Vector3i(floori(carved.position.x) - 2 * hw, BREACH_FLOOR, floori(carved.position.z) - 2 * hw)
	var hi := Vector3i(ceili(carved.end.x) + 2 * hw + 1, BREACH_TOP, ceili(carved.end.z) + 2 * hw + 1)
	var size := hi - lo
	# Columns that were wall in the soldier's band before any carving.
	var was_wall := PackedByteArray()
	was_wall.resize(size.x * size.z)
	var any_wall := false
	for s: Array in _structures:
		var a: Vector3i = s[0]
		var b: Vector3i = s[1]  # inclusive
		if b.y < BREACH_FLOOR or a.y >= BREACH_TOP:
			continue
		for z in range(maxi(a.z, lo.z), mini(b.z + 1, hi.z)):
			for x in range(maxi(a.x, lo.x), mini(b.x + 1, hi.x)):
				was_wall[(x - lo.x) + size.x * (z - lo.z)] = 1
				any_wall = true
	if not any_wall or not is_area_readable(AABB(lo, size)):
		return null
	# Columns with anything solid in the band now.
	var solid := solid_voxels(lo, size)
	var blocked := PackedByteArray()
	blocked.resize(size.x * size.z)
	for z in size.z:
		for x in size.x:
			var base := size.y * (x + size.x * z)
			for y in size.y:
				if solid[base + y] != 0:
					blocked[x + size.x * z] = 1
					break
	var opened := AABB()
	var found := false
	for z in range(hw, size.z - hw):
		for x in range(hw, size.x - hw):
			var column := Vector2i(lo.x + x, lo.z + z)
			if was_wall[x + size.x * z] == 0 or _breached.has(column) or not _clear_square(blocked, size.x, x, z, hw):
				continue
			_breached[column] = true
			var cell := AABB(Vector3(column.x, 0, column.y) * VOXEL_SIZE, Vector3(VOXEL_SIZE, BREACH_TOP * VOXEL_SIZE, VOXEL_SIZE))
			opened = cell if not found else opened.merge(cell)
			found = true
	if not found:
		return null
	return opened.grow(hw * VOXEL_SIZE)


func _clear_square(blocked: PackedByteArray, width: int, cx: int, cz: int, hw: int) -> bool:
	for z in range(cz - hw, cz + hw + 1):
		for x in range(cx - hw, cx + hw + 1):
			if blocked[x + width * z] != 0:
				return false
	return true


## Whether the structures' voxels in `box` (voxel coordinates) are built, loaded and can be
## read. Only the structures' area matters: everywhere else is always empty.
func is_area_readable(box: AABB) -> bool:
	if not _built:
		return false
	var need := box.intersection(_structure_area)
	return not need.has_volume() or _tool.is_area_editable(need)


## 1 where a voxel is solid and 0 where it's empty, for the box at `begin` (voxel
## coordinates) of `size`, indexed [y + size.y * (x + size.x * z)].
func solid_voxels(begin: Vector3i, size: Vector3i) -> PackedByteArray:
	var count := size.x * size.y * size.z
	var result := PackedByteArray()
	result.resize(count)
	if count <= 0:
		return result
	var buffer := VoxelBuffer.new()
	buffer.create(size.x, size.y, size.z)
	_tool.copy(begin, buffer, 1 << VoxelBuffer.CHANNEL_COLOR, false)
	if buffer.is_uniform(VoxelBuffer.CHANNEL_COLOR):
		if buffer.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_COLOR) != Mat.EMPTY:
			result.fill(1)
		return result
	var bytes := buffer.get_channel_as_byte_array(VoxelBuffer.CHANNEL_COLOR)
	var per := bytes.size() / count  # bytes per voxel (the channel's depth)
	for i in count:
		for k in per:
			if bytes[i * per + k] != 0:
				result[i] = 1
				break
	return result


## Host only. The structures' voxels as they are now (carving included), as boxes in metres
## in this node's space, for the part inside `area_m`: one box per vertical run of solid
## voxels, merged along x where neighbouring columns match. For navigation rebakes. A structure
## nothing has carved (_touched) is still solid as built: its box goes in as it is, unread
## (research 2026-10-13 B2.3: reading a town's voxels took up to 126 ms a chunk).
func solid_boxes_m(area_m: AABB) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var area_lo := Vector3i((area_m.position / VOXEL_SIZE).floor())
	var area_hi := Vector3i((area_m.end / VOXEL_SIZE).ceil())
	for i in _structures.size():
		if _skin[i] == 1:
			continue
		var s: Array = _structures[i]
		var lo: Vector3i = (s[0] as Vector3i).max(area_lo)
		var hi: Vector3i = (s[1] as Vector3i + Vector3i.ONE).min(area_hi)
		var size := hi - lo
		if size.x <= 0 or size.y <= 0 or size.z <= 0:
			continue
		if _touched[i] == 0 and not read_all_voxels:
			boxes.append(_box_m(lo, size))
			continue
		var solid := solid_voxels(lo, size)
		for z in size.z:
			var open := {}  # run start y -> [run end y, first x]
			var prev: Array = []
			for x in size.x + 1:
				var runs: Array = _runs(solid, size, x, z) if x < size.x else []
				if runs != prev:
					# The runs that end here become boxes from where they started.
					for run: Array in prev:
						var key := Vector2i(run[0], run[1])
						if not runs.has(run):
							var x0: int = open[key]
							boxes.append(_box_m(lo + Vector3i(x0, run[0], z), Vector3i(x - x0, run[1] - run[0], 1)))
							open.erase(key)
					for run: Array in runs:
						var key := Vector2i(run[0], run[1])
						if not open.has(key):
							open[key] = x
					prev = runs
	return boxes


## Vertical runs of solid voxels in one column, as [start y, end y) pairs.
static func _runs(solid: PackedByteArray, size: Vector3i, x: int, z: int) -> Array:
	var runs: Array = []
	var base := size.y * (x + size.x * z)
	var start := -1
	for y in size.y + 1:
		var filled := y < size.y and solid[base + y] != 0
		if filled and start < 0:
			start = y
		elif not filled and start >= 0:
			runs.append([start, y])
			start = -1
	return runs


static func _box_m(begin: Vector3i, size: Vector3i) -> AABB:
	return AABB(Vector3(begin) * VOXEL_SIZE, Vector3(size) * VOXEL_SIZE)
