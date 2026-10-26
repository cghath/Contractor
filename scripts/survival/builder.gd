class_name Builder
extends Node
## The free building system's authority (docs/survival_building.md §1-4, 10; calls 8, 12, 39,
## 70-73): every block and piece built in a zone, placed, worked on, repaired, upgraded,
## dismantled, cracked and fallen, saved with the zone and the same on every peer.
##
## Blocks (BuildPieces: 0.5 m cells, a material and a shape) are records here and voxels in
## BuildVoxels chunks: a block goes in as a site (its materials paid, progress 0) that fills as
## someone works it (the material's build_s; stopping keeps the progress) and is stamped into
## the voxels when done. A blueprint (call 12) is a site nobody has paid for: anyone with the
## materials and the tool builds it later. Pieces (doors, stairs, bunks...) are BuildPiece nodes
## on the grid with a footprint. Dismantling gives DISMANTLE_SHARE back; upgrading a block in
## place (wood to brick) costs the difference (BuildPieces.upgrade_cost) and work at the new
## material's pace, the old block standing meanwhile.
##
## Integrity (BuildIntegrity, call 71): a change marks its cells dirty; the cluster they touch is
## solved on a worker thread and applied here on the main thread. A block over its capacity or
## span cracks (crack marks, "cracked" on its record) and after crack_s falls: its voxels cleared,
## part of its material dropped as debris, and whatever only it held falls with it (the next
## solve finds them FREE). Damage lowers capacity: rounds through or into a block (BuildVoxels),
## blasts (server_blast, from ZoneLevel.server_blast), zombies chewing wood (server_chew_at, an
## API for ZombieAI) and breaching charges. Repair restores it.
##
## Ownership (call 72): no claims; whoever holds the place holds the builds. Doors, shutters,
## hatches and gates lock with a key (a door_key item cut for that lock) or a code, and a locked
## one is broken down (server_hit_piece, server_breach), not opened.
##
## Network: the host is the authority. Owners ask through ask() (Builder.request, any peer ->
## host); the host checks, changes the records and sends each change to every peer
## (_client_block, _client_piece, _client_edit); a late joiner asks for everything once
## (_ask_all). Saves: to_save() goes in the zone save as GameState.builds and comes back through
## server_restore (ZoneLevel._restore_builds). One node per level ("Builder").

const NODE_NAME := "Builder"
const GROUP := &"builder"  # GameState.save_zone finds it here
## Proposed numbers.
const REACH_M := 6.0  # how far from a cell's centre its builder may stand
const DISMANTLE_SHARE := 0.6  # doc §2 DISMANTLE_SHARE
const REPAIR_SHARE := 0.5  # a full repair costs this share of the block's cost
const DEBRIS_SHARE := 0.3  # a fallen block leaves this share of its material as items
const CRACK_S := 20.0  # doc §3 CRACK_S: a cracked block stands this long, then falls
## Zombies chew wood (doc §2 CHEW_WOOD): a block per CHEW_WOOD_S seconds with CHEW_CREW on it.
const CHEW_WOOD_S := 360.0
const CHEW_CREW := 5
## Damage: hp lost per voxel a round goes through a built block, per round stopped in one (a
## mark), and at a blast's centre (times the material's blast share, VoxelWorld.MATERIALS);
## SHOT_TAKES scales the rounds' by material (steel shrugs them off).
const SHOT_DAMAGE := 0.02
const MARK_DAMAGE := 0.02
const BLAST_DAMAGE := 1.5
const SHOT_TAKES := {"wood": 1.0, "scrap": 0.8, "sandbag": 0.4, "brick": 0.4, "concrete": 0.25, "steel": 0.05}
## A piece takes this much from a blast's centre.
const PIECE_BLAST := 300.0
## Chunks of voxels: CHUNK_CELLS blocks (CHUNK_M) a side, streamed in and out round the
## players like ZoneLevel's modules.
const CHUNK_CELLS := 32
const CHUNK_M := 16.0
const STREAM_IN_M := 260.0
const STREAM_OUT_M := 340.0
const STREAM_CHECK_S := 0.5
## A worker keeps working a site while the owner says so at least this often (BuildMode sends
## every WORK_SEND_S while the use key is held).
const WORK_HOLD_S := 0.6
## Doc §10: pieces per zone.
const PIECES_CAP := 600
## A cluster solve takes at most this many blocks (a settlement is a few hundred).
const CLUSTER_MAX := 6000

## How long a cracked block stands (crack_s; tests shorten it).
var crack_s := CRACK_S
## Every peer: cell (Vector3i) -> block record {"m": material key, "s": shape key, "r": quarter
## turns, "hp": 0-1, "prog": 0-1 (1 built), "bp": a blueprint not paid for yet, "paid": its
## materials are in it, "up": the material it's being upgraded to and "uprog" its progress
## (absent when not), "cracked": it's cracked and will fall}.
var blocks := {}
## Every peer: piece id -> {"k": kind, "c": [x, y, z] its base cell, "r", "hp", "prog", "bp",
## "paid", "open", "locked", "lock": {"key": lock id} or {"code": "1234", "knows": [names]}}.
var pieces := {}
## Every peer: chunk key ("x,y,z" of the chunk grid) -> its voxel edit log, in order.
var logs := {}
## The last problem server_place_piece had ("" when it placed).
var last_problem := ""

var _cells := {}  # every peer: cell -> piece id over it
var _chunks := {}  # chunk key -> BuildVoxels (streamed in)
var _piece_nodes := {}  # id -> BuildPiece
var _site_nodes := {}  # cell -> MeshInstance3D (a block site's filling ghost)
var _next_id := 1
var _next_stream := 0.0
# Host:
var _dirty := {}  # cells whose cluster wants solving
var _job: BuildIntegrity.Job
var _status := {}  # cell -> the last solve's result for it
var _crack_at := {}  # cell -> msec it cracked
var _workers := {}  # soldier instance id -> {"s", "kind": "block"/"piece", "at", "until"}
var _grounded := {}  # cell -> grounded() (cleared when a blast may have cut the ground)
var _sending := true  # host: record changes go to the clients as they happen


static func of(from: Node) -> Builder:
	return install(_level_of(from))


## The level's Builder if it has one (never makes one).
static func find(from: Node) -> Builder:
	var level := _level_of(from)
	return level.get_node_or_null(NODE_NAME) as Builder if level else null


## `level`'s Builder, made if it has none (ZoneLevel makes a survival zone's on every peer).
static func install(level: Node) -> Builder:
	if level == null:
		return null
	var b := level.get_node_or_null(NODE_NAME) as Builder
	if b == null:
		b = Builder.new()
		b.name = NODE_NAME
		level.add_child(b)
	return b


## The level `from` is in (its own ancestor first: while one level replaces another both are in
## the tree), else the current one.
static func _level_of(from: Node) -> CompoundLevel:
	if from == null or not from.is_inside_tree():
		return null
	var n := from
	while n:
		if n is CompoundLevel:
			return n
		n = n.get_parent()
	return CompoundLevel.current(from)


func _ready() -> void:
	add_to_group(GROUP)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		(func() -> void: _ask_all.rpc_id(1)).call_deferred()


func _level() -> CompoundLevel:
	return get_parent() as CompoundLevel


func _exit_tree() -> void:
	if _job:
		_job.finish()  # (no solve left running on a worker past the level)
		_job = null


static func _now_ms() -> int:
	return Time.get_ticks_msec()


# --- The grid and the ground ----------------------------------------------------------------

static func chunk_of(c: Vector3i) -> Vector3i:
	return Vector3i(floori(float(c.x) / CHUNK_CELLS), floori(float(c.y) / CHUNK_CELLS), floori(float(c.z) / CHUNK_CELLS))


## Whether cell `c` rests on the ground: the terrain under it reaches its bottom, or the zone's
## own buildings (a module's voxels) are right under or beside it.
func grounded(c: Vector3i) -> bool:
	if not _grounded.has(c):
		_grounded[c] = _grounded_now(c)
	return bool(_grounded[c])


func _grounded_now(c: Vector3i) -> bool:
	var box := BuildPieces.cell_box(c)
	var centre := box.get_center()
	var lvl := _level()
	if lvl == null:
		return false
	var top := -INF
	for o: Vector2 in [Vector2.ZERO, Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
		top = maxf(top, lvl.ground_height(centre.x + o.x, centre.z + o.y))
	if top >= box.position.y - 0.05:
		return true
	var below := centre - Vector3(0, BuildPieces.BLOCK_M * 0.6, 0)
	for p: Vector3 in [below, centre + Vector3(0.3, 0, 0), centre - Vector3(0.3, 0, 0), centre + Vector3(0, 0, 0.3), centre - Vector3(0, 0, 0.3)]:
		if _structure_at(p):
			return true
	return false


## Whether the zone's own structures (not the builds) have a voxel at `p`.
func _structure_at(p: Vector3) -> bool:
	var lvl := _level()
	if lvl is ZoneLevel:
		var m := (lvl as ZoneLevel).module_at(p)
		return m != null and m.voxel_world != null and m.voxel_world.material_at(p) != VoxelWorld.Mat.EMPTY
	for w in lvl.voxel_worlds():
		if w.material_at(p) != VoxelWorld.Mat.EMPTY:
			return true
	return false


## The cell a block placed on the ground at `p` takes: the one the ground's surface is in, so
## it beds in and rests on it (one up when the surface is right at a cell's top: grounded()
## still counts it).
static func ground_cell(p: Vector3) -> Vector3i:
	return BuildPieces.cell_at(p + Vector3(0, 0.03, 0))


func _in_ground(c: Vector3i) -> bool:
	var box := BuildPieces.cell_box(c)
	var centre := box.get_center()
	var lvl := _level()
	return lvl != null and lvl.ground_height(centre.x, centre.z) >= box.end.y - 0.02


func is_built(c: Vector3i) -> bool:
	var rec: Dictionary = blocks.get(c, {})
	return not rec.is_empty() and float(rec.get("prog", 0.0)) >= 1.0 and not bool(rec.get("bp", false))


func is_free(c: Vector3i) -> bool:
	return not blocks.has(c) and not _cells.has(c)


# --- Tools and materials --------------------------------------------------------------------

static func has_tool(s: Soldier, kind: String) -> bool:
	for id: StringName in BuildPieces.TOOLS.get(kind, []):
		if s.inventory.count_of(id) > 0 or s.inventory.slots.values().has(id) or s.inventory.hands == id:
			return true
	return false


static func tool_problem(s: Soldier, kind: String) -> String:
	if has_tool(s, kind):
		return ""
	var ids: Array = BuildPieces.TOOLS.get(kind, [])
	var id: StringName = ids[0] if not ids.is_empty() else &""
	return "You need a %s" % (ItemDB.get_item(id).name.to_lower() if ItemDB.has_item(id) else kind)


static func cost_problem(s: Soldier, cost: Array) -> String:
	for pair: Array in cost:
		if s.inventory.count_of(StringName(pair[0])) < int(pair[1]):
			return "Not enough: it takes %s" % BuildPieces.cost_text(cost)
	return ""


## Host: takes `cost` out of `s`'s inventory (cost_problem first).
static func _pay(s: Soldier, cost: Array) -> void:
	for pair: Array in cost:
		for i in int(pair[1]):
			s.inventory.remove_one(StringName(pair[0]))


## Host: gives `cost` to `s`; what doesn't fit drops at his feet (or, with no one, at `at`).
func _give(s: Soldier, cost: Array, at: Vector3) -> void:
	var lvl := _level()
	for pair: Array in cost:
		var id := StringName(pair[0])
		var n := int(pair[1])
		var taken := s.inventory.take(id, n) if s else 0
		if taken < n and lvl:
			lvl.server_spawn_dropped(id, n - taken, s.global_position + Vector3.UP * 0.3 if s else at)


func _near(s: Soldier, at: Vector3) -> bool:
	return s.global_position.distance_to(at) <= REACH_M


# --- Blocks ---------------------------------------------------------------------------------

## Why `s` can't put a block of `mat` shaped `shape` at `c` ("" when he can). A blueprint needs
## no materials or tool now.
func place_problem(s: Soldier, c: Vector3i, mat: String, shape: String, blueprint := false) -> String:
	if not BuildPieces.MATERIALS.has(mat) or not BuildPieces.SHAPES.has(shape):
		return "Can't build that"
	if s and not s.vitals.is_up():
		return "Not now"
	if s and not _near(s, BuildPieces.cell_centre(c)):
		return "Too far"
	if not is_free(c):
		return "Something's built there"
	if _in_ground(c):
		return "That's in the ground"
	if _structure_at(BuildPieces.cell_centre(c)):
		return "Something's in the way"
	if int(preview(c, mat, shape, true).state) == BuildIntegrity.State.FREE:
		return "Nothing holds it there"
	if not blueprint and s:
		var why := tool_problem(s, String(BuildPieces.MATERIALS[mat].tool))
		if why != "":
			return why
		return cost_problem(s, BuildPieces.block_cost(mat, shape))
	return ""


## Host: `s` lays a block site (or a blueprint) at `c`. Returns why not ("" when laid).
func server_place(s: Soldier, c: Vector3i, mat: String, shape := "block", rot := 0, blueprint := false) -> String:
	var why := place_problem(s, c, mat, shape, blueprint)
	if why != "":
		return why
	if not blueprint:
		_pay(s, BuildPieces.block_cost(mat, shape))
	_set_block(c, {"m": mat, "s": shape, "r": posmod(rot, 4), "hp": 1.0, "prog": 0.0, "bp": blueprint, "paid": not blueprint})
	return ""


## Host: `s` works `seconds` on the site, blueprint or upgrade at `c`. Returns why not ("" while
## it goes on, and when it's done).
func server_work(s: Soldier, c: Vector3i, seconds: float) -> String:
	var rec: Dictionary = blocks.get(c, {})
	if rec.is_empty():
		return "Nothing to build there"
	var upgrading := rec.has("up")
	if not upgrading and is_built(c):
		return "It's built"
	var mat := String(rec.up) if upgrading else String(rec.m)
	var why := tool_problem(s, String(BuildPieces.MATERIALS[mat].tool))
	if why != "":
		return why
	if not bool(rec.get("paid", false)):
		var cost := BuildPieces.block_cost(mat, String(rec.s))
		why = cost_problem(s, cost)
		if why != "":
			return why
		_pay(s, cost)
		rec["paid"] = true
		rec["bp"] = false
	var field := "uprog" if upgrading else "prog"
	var before := float(rec.get(field, 0.0))
	var after := minf(before + seconds / float(BuildPieces.MATERIALS[mat].build_s), 1.0)
	if after >= 1.0 and not upgrading and int(preview(c, mat, String(rec.s)).state) == BuildIntegrity.State.FREE:
		after = minf(after, 0.99)  # nothing holds it yet (the site under it isn't done)
		why = "Nothing holds it yet"
	rec[field] = after
	if after >= 1.0:
		_finish_block(c, rec)
	elif floori(after * 10.0) != floori(before * 10.0):
		_set_block(c, rec)
	return why


## Host: lays and builds a block at once (tests, the dev give).
func server_build_now(s: Soldier, c: Vector3i, mat: String, shape := "block", rot := 0) -> String:
	var why := server_place(s, c, mat, shape, rot)
	return why if why != "" else server_work(s, c, 1000.0)


func _finish_block(c: Vector3i, rec: Dictionary) -> void:
	if rec.has("up"):
		rec["m"] = rec.up
		rec.erase("up")
		rec.erase("uprog")
	rec["prog"] = 1.0
	rec["bp"] = false
	rec["hp"] = 1.0
	rec["cracked"] = false
	_crack_at.erase(c)
	_set_block(c, rec)
	_op(c, {"op": "bset", "s": String(rec.s), "r": int(rec.r), "m": int(BuildPieces.MATERIALS[String(rec.m)].mat)})
	print("[build] %s %s built at %s" % [rec.m, rec.s, c])
	_mark_dirty(c)


## Host: `s` takes the block at `c` down: DISMANTLE_SHARE of its materials back (a site's or an
## upgrade's paid materials come back whole; a blueprint just goes). Returns why not.
func server_dismantle(s: Soldier, c: Vector3i) -> String:
	var rec: Dictionary = blocks.get(c, {})
	if rec.is_empty():
		return "Nothing built there"
	if s and not _near(s, BuildPieces.cell_centre(c)):
		return "Too far"
	var mat := String(rec.m)
	if is_built(c):
		var why := tool_problem(s, String(BuildPieces.MATERIALS[mat].tool)) if s else ""
		if why != "":
			return why
		var back := BuildPieces.scaled(BuildPieces.block_cost(mat, String(rec.s)), DISMANTLE_SHARE)
		if rec.has("up"):
			back.append_array(BuildPieces.upgrade_cost(mat, String(rec.up), String(rec.s)))
		_give(s, back, BuildPieces.cell_centre(c))
		_remove_block(c)
	else:
		if bool(rec.get("paid", false)):
			_give(s, BuildPieces.block_cost(mat, String(rec.s)), BuildPieces.cell_centre(c))
		_remove_block(c)
	return ""


## Host: `s` repairs the block at `c` to whole, for REPAIR_SHARE of its cost times the damage.
func server_repair(s: Soldier, c: Vector3i) -> String:
	if not is_built(c):
		return "Nothing built there"
	var rec: Dictionary = blocks[c]
	if float(rec.hp) >= 0.999:
		return "It's sound"
	var mat := String(rec.m)
	var why := tool_problem(s, String(BuildPieces.MATERIALS[mat].tool))
	if why != "":
		return why
	var full: Array = BuildPieces.block_cost(mat, String(rec.s))[0]
	var cost := [[full[0], maxi(1, ceili(float(full[1]) * REPAIR_SHARE * (1.0 - float(rec.hp))))]]
	why = cost_problem(s, cost)
	if why != "":
		return why
	_pay(s, cost)
	rec["hp"] = 1.0
	_set_block(c, rec)
	_mark_dirty(c)
	return ""


## Host: `s` starts upgrading the block at `c` to `to` in place (call 12): the difference paid
## now, then work at the new material's pace (server_work); the old block stands meanwhile.
func server_upgrade(s: Soldier, c: Vector3i, to: String) -> String:
	if not is_built(c):
		return "Nothing built there"
	var rec: Dictionary = blocks[c]
	if rec.has("up"):
		return "It's being upgraded"
	if not BuildPieces.MATERIALS.has(to):
		return "Can't build that"
	var cost := BuildPieces.upgrade_cost(String(rec.m), to, String(rec.s))
	if cost.is_empty():
		return "That's no upgrade"
	var why := tool_problem(s, String(BuildPieces.MATERIALS[to].tool))
	if why == "":
		why = cost_problem(s, cost)
	if why != "":
		return why
	_pay(s, cost)
	rec["up"] = to
	rec["uprog"] = 0.0
	_set_block(c, rec)
	return ""


func _remove_block(c: Vector3i) -> void:
	var was_built := is_built(c)
	_set_block(c, {})
	_crack_at.erase(c)
	_status.erase(c)
	if was_built:
		_op(c, {"op": "bclr"})
		_mark_dirty(c)
		_check_pieces_near(c)


## Host: the block at `c` falls (over its load or span, cracked through, or held by nothing):
## its voxels go and DEBRIS_SHARE of its material lies where it stood.
func _fail(c: Vector3i, why: String) -> void:
	var rec: Dictionary = blocks.get(c, {})
	if rec.is_empty():
		return
	var lvl := _level()
	var at := BuildPieces.cell_centre(c)
	if lvl and is_built(c):
		for pair: Array in BuildPieces.scaled(BuildPieces.block_cost(String(rec.m), String(rec.s)), DEBRIS_SHARE):
			lvl.server_spawn_dropped(StringName(pair[0]), int(pair[1]), lvl.ground_point(at) + Vector3.UP * 0.2)
	print("[build] the %s %s at %s falls (%s)" % [rec.m, rec.s, c, why])
	_remove_block(c)


# --- Damage ---------------------------------------------------------------------------------

## Host: the block at `c` loses `amount` hp (it falls at none); its capacity drops with it.
func server_damage(c: Vector3i, amount: float) -> void:
	if not is_built(c) or amount <= 0.0:
		return
	var rec: Dictionary = blocks[c]
	var before := float(rec.hp)
	rec["hp"] = before - amount
	if float(rec.hp) <= 0.0:
		_fail(c, "destroyed")
		return
	if floori(float(rec.hp) * 20.0) != floori(before * 20.0):
		_set_block(c, rec)
	_mark_dirty(c)


## Host (BuildVoxels): rounds went through built cells ({cell: voxels}) or stopped in one (mark).
func server_shot_cells(cells: Dictionary, mark := false) -> void:
	for c: Vector3i in cells:
		if is_built(c):
			var takes := float(SHOT_TAKES.get(String(blocks[c].m), 1.0))
			server_damage(c, (MARK_DAMAGE if mark else SHOT_DAMAGE * int(cells[c])) * takes)


## Host (ZoneLevel.server_blast): a blast takes the builds' voxels within its reach and hp from
## the blocks and pieces near it.
func server_blast(pos: Vector3, radius_m: float) -> void:
	_grounded.clear()  # (a crater may have cut the ground under a block)
	for key: String in _chunks:
		var w: BuildVoxels = _chunks[key]
		if AABB(w.global_position, Vector3.ONE * CHUNK_M).grow(radius_m).has_point(pos):
			w.server_blast(pos, radius_m)
	var reach := radius_m + BuildPieces.BLOCK_M * 0.5
	var hit: Array[Vector3i] = []
	for c: Vector3i in blocks:
		if is_built(c) and BuildPieces.cell_centre(c).distance_to(pos) <= reach:
			hit.append(c)
	for c in hit:
		var vmat: int = BuildPieces.MATERIALS[String(blocks[c].m)].mat
		var share := float((VoxelWorld.MATERIALS.get(VoxelWorld.base_mat(vmat), {}) as Dictionary).get("blast", 0.4))
		server_damage(c, BLAST_DAMAGE * share * (1.0 - BuildPieces.cell_centre(c).distance_to(pos) / reach))
	for id: int in pieces.keys():
		var node: BuildPiece = _piece_nodes.get(id)
		if node and node.centre().distance_to(pos) <= radius_m:
			server_hit_piece(id, PIECE_BLAST * (1.0 - node.centre().distance_to(pos) / radius_m))


## Host (ZoneLevel.server_breach): a breaching charge cuts through the builds too: blocks (not
## steel) in its doorway go, and a door, gate or shutter it's on breaks.
func server_breach(pos: Vector3, normal: Vector3, floor_y: float, width_m: float, height_m: float, depth_m: float) -> void:
	var reach := width_m + depth_m
	for c: Vector3i in blocks.keys():
		var p := BuildPieces.cell_centre(c)
		if is_built(c) and String(blocks[c].m) != "steel" and Vector2(p.x - pos.x, p.z - pos.z).length() <= reach * 0.5 + 0.25 \
				and p.y >= floor_y - 0.25 and p.y <= floor_y + height_m:
			_fail(c, "breached")
	for id: int in pieces.keys():
		var node: BuildPiece = _piece_nodes.get(id)
		if node and node.centre().distance_to(pos) <= reach + 1.0:
			server_hit_piece(id, INF)


## Host: zombies chew the block at `c` (doc §2 CHEW_WOOD: wood only; scrap slows them, the rest
## hold): `chewers` of them for `seconds`. Returns whether it took any harm.
func server_chew(c: Vector3i, seconds: float, chewers := 1) -> bool:
	if not is_built(c) or not bool(BuildPieces.MATERIALS[String(blocks[c].m)].chew):
		return false
	server_damage(c, seconds * float(chewers) / (CHEW_WOOD_S * CHEW_CREW))
	return true


## Host, for ZombieAI: `chewers` zombies at `pos` chew the built wood they're against for
## `seconds` (the cell at `pos`, else the nearest built one within half a block). Returns whether
## anything was chewed.
static func server_chew_at(from: Node, pos: Vector3, seconds: float, chewers := 1) -> bool:
	var b := find(from)
	if b == null:
		return false
	var c := BuildPieces.cell_at(pos)
	if not b.is_built(c):
		var best := Vector3i.MAX
		var best_d := BuildPieces.BLOCK_M
		for dir in BuildIntegrity.DIRS:
			var n := c + dir
			var d := BuildPieces.cell_box(n).get_center().distance_to(pos)
			if b.is_built(n) and d <= best_d + BuildPieces.BLOCK_M * 0.5:
				best = n
				best_d = d
		if best == Vector3i.MAX:
			return false
		c = best
	return b.server_chew(c, seconds, chewers)


## A built block's capacity now (BuildIntegrity: its material and shape, lowered by damage).
func capacity(c: Vector3i) -> float:
	return BuildIntegrity.capacity_of(_entry(c)) if is_built(c) else 0.0


## The last solve's result for a built block ({} before one): "state", "ratio", "h", "load", "cap".
func status(c: Vector3i) -> Dictionary:
	return _status.get(c, {})


# --- Integrity ------------------------------------------------------------------------------

func _entry(c: Vector3i) -> Array:
	var rec: Dictionary = blocks[c]
	return BuildIntegrity.entry(String(rec.m), float(BuildPieces.SHAPES[String(rec.s)].frac), float(rec.hp), grounded(c))


## The blocks touching `seeds` and everything they connect to (built ones; with `sites`, sites
## and blueprints too), as a cluster for BuildIntegrity.solve.
func _cluster(seeds: Array, sites := false) -> Dictionary:
	var out := {}
	var stack: Array = []
	for c: Vector3i in seeds:
		stack.append(c)
		for dir in BuildIntegrity.DIRS:
			stack.append(c + dir)
	while not stack.is_empty() and out.size() < CLUSTER_MAX:
		var c: Vector3i = stack.pop_back()
		if out.has(c) or not blocks.has(c) or not (is_built(c) or sites):
			continue
		out[c] = _entry(c)
		for dir in BuildIntegrity.DIRS:
			if not out.has(c + dir):
				stack.append(c + dir)
	return out


## What a block of `mat` and `shape` at `c` would carry, as the ghost shows it (every peer):
## {"state": BuildIntegrity.State, "ratio", "h"}. `sites`: unbuilt sites count as holding it (a
## blueprint laid on a blueprint).
func preview(c: Vector3i, mat: String, shape: String, sites := false) -> Dictionary:
	var cells := _cluster([c], sites)
	cells[c] = BuildIntegrity.entry(mat, float(BuildPieces.SHAPES[shape].frac), 1.0, grounded(c))
	var all := BuildIntegrity.solve(cells)
	var out: Dictionary = all[c]
	# A block that tips one already standing over its capacity shows red too.
	for n: Vector3i in all:
		if n != c and int(all[n].state) == BuildIntegrity.State.OVER and int(_status.get(n, {}).get("state", BuildIntegrity.State.OK)) != BuildIntegrity.State.OVER:
			out = out.duplicate()
			out["state"] = BuildIntegrity.State.OVER
			out["tips"] = n
			break
	return out


func _mark_dirty(c: Vector3i) -> void:
	if multiplayer.is_server():
		_dirty[c] = true


func _take_cluster() -> Dictionary:
	var seeds: Array = _dirty.keys()
	_dirty.clear()
	return _cluster(seeds)


## Host: applies a solve: FREE blocks fall now, OVER ones crack (and fall after crack_s), the
## rest stand (a crack mended by support or a repair closes).
func _apply_solve(result: Dictionary) -> void:
	var falling: Array[Vector3i] = []
	for c: Vector3i in result:
		if not is_built(c):
			continue
		var r: Dictionary = result[c]
		_status[c] = r
		match int(r.state):
			BuildIntegrity.State.FREE:
				falling.append(c)
			BuildIntegrity.State.OVER:
				if not _crack_at.has(c):
					_crack(c)
			_:
				if _crack_at.has(c):
					_crack_at.erase(c)
					blocks[c]["cracked"] = false
					_set_block(c, blocks[c])
	for c in falling:
		_fail(c, "nothing holds it")


func _crack(c: Vector3i) -> void:
	_crack_at[c] = _now_ms()
	var rec: Dictionary = blocks[c]
	rec["cracked"] = true
	_set_block(c, rec)
	var w: BuildVoxels = _chunks.get(_chunk_key(c))
	if w and w.is_built():
		w.quiet = true
		var centre := BuildPieces.cell_centre(c)
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			w.server_mark(centre + dir * (BuildPieces.BLOCK_M * 0.5 - 0.02), dir, int(BuildPieces.MATERIALS[String(rec.m)].mat))
		w.quiet = false
	print("[build] the %s %s at %s cracks (%s)" % [rec.m, rec.s, c, _status.get(c, {})])


## Host: solves every dirty cluster now, on this thread, cascades included (tests; a save).
func flush() -> void:
	if _job:
		_apply_solve(_job.finish())
		_job = null
	var guard := 0
	while not _dirty.is_empty() and guard < 64:
		_apply_solve(BuildIntegrity.solve(_take_cluster()))
		guard += 1


## Host: the cracked blocks whose time is up fall.
func _check_cracks() -> void:
	if _crack_at.is_empty():
		return
	var now := _now_ms()
	var due: Array[Vector3i] = []
	for c: Vector3i in _crack_at:
		if now >= int(_crack_at[c]) + int(crack_s * 1000.0):
			due.append(c)
	for c in due:
		_fail(c, "cracked through")


# --- Pieces ---------------------------------------------------------------------------------

## Why `s` can't put piece `kind` with its base at `c` turned `rot` ("" when he can).
func piece_problem(s: Soldier, kind: String, c: Vector3i, rot: int, blueprint := false) -> String:
	if not BuildPieces.PIECES.has(kind):
		return "Can't build that"
	if pieces.size() >= PIECES_CAP:
		return "No more pieces in this zone"
	var cells := BuildPieces.piece_cells(kind, c, rot)
	if s and not _near(s, BuildPieces.cell_centre(c)):
		return "Too far"
	for cell in cells:
		if not is_free(cell):
			return "Something's built there"
		if _structure_at(BuildPieces.cell_centre(cell)):
			return "Something's in the way"
	if _in_ground(c):
		return "That's in the ground"
	if not _piece_supported(kind, c, rot):
		return "Nothing holds it there"
	var def: Dictionary = BuildPieces.PIECES[kind]
	if not blueprint and s:
		var why := tool_problem(s, String(def.tool))
		return why if why != "" else cost_problem(s, def.cost)
	return ""


func _piece_supported(kind: String, c: Vector3i, rot: int) -> bool:
	var size := BuildPieces.piece_size(kind, rot)
	for z in size.z:
		for x in size.x:
			var cell := c + Vector3i(x, 0, z)
			if grounded(cell) or is_built(cell + Vector3i.DOWN):
				return true
			for side in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				if is_built(cell + side):
					return true  # hung on a wall: a door in its frame, a shutter at a window
	return false


## Host: `s` lays piece `kind` (a site, or a blueprint) at `c`. Returns its id, or -1 (why in
## last_problem).
func server_place_piece(s: Soldier, kind: String, c: Vector3i, rot := 0, blueprint := false) -> int:
	last_problem = piece_problem(s, kind, c, rot, blueprint)
	if last_problem != "":
		return -1
	var def: Dictionary = BuildPieces.PIECES[kind]
	if not blueprint:
		_pay(s, def.cost)
	var id := _next_id
	_next_id += 1
	_set_piece(id, {"k": kind, "c": [c.x, c.y, c.z], "r": posmod(rot, 4), "hp": float(def.hp), "prog": 0.0, "bp": blueprint,
		"paid": not blueprint, "open": false, "locked": false, "lock": {}})
	return id


func is_piece_built(id: int) -> bool:
	var rec: Dictionary = pieces.get(id, {})
	return not rec.is_empty() and float(rec.prog) >= 1.0


## Host: `s` works `seconds` on piece `id`'s site or blueprint.
func server_work_piece(s: Soldier, id: int, seconds: float) -> String:
	var rec: Dictionary = pieces.get(id, {})
	if rec.is_empty():
		return "Nothing to build there"
	if is_piece_built(id):
		return "It's built"
	var def: Dictionary = BuildPieces.PIECES[String(rec.k)]
	var why := tool_problem(s, String(def.tool))
	if why != "":
		return why
	if not bool(rec.paid):
		why = cost_problem(s, def.cost)
		if why != "":
			return why
		_pay(s, def.cost)
		rec["paid"] = true
		rec["bp"] = false
	var before := float(rec.prog)
	rec["prog"] = minf(before + seconds / float(def.build_s), 1.0)
	if float(rec.prog) >= 1.0 or floori(float(rec.prog) * 10.0) != floori(before * 10.0):
		if float(rec.prog) >= 1.0:
			print("[build] %s built at %s" % [rec.k, rec.c])
		_set_piece(id, rec)
	return ""


func server_build_piece_now(s: Soldier, kind: String, c: Vector3i, rot := 0) -> int:
	var id := server_place_piece(s, kind, c, rot)
	if id > 0:
		server_work_piece(s, id, 1000.0)
	return id


## Host: `s` takes piece `id` down (DISMANTLE_SHARE back; a site's paid materials whole).
func server_dismantle_piece(s: Soldier, id: int) -> String:
	var rec: Dictionary = pieces.get(id, {})
	if rec.is_empty():
		return "Nothing built there"
	var def: Dictionary = BuildPieces.PIECES[String(rec.k)]
	var at := _piece_centre(rec)
	if s and not _near(s, at):
		return "Too far"
	if is_piece_built(id):
		if bool(rec.get("locked", false)):
			return "It's locked"
		var why := tool_problem(s, String(def.tool)) if s else ""
		if why != "":
			return why
		_give(s, BuildPieces.scaled(def.cost, DISMANTLE_SHARE), at)
	elif bool(rec.paid):
		_give(s, def.cost, at)
	_set_piece(id, {})
	return ""


## Host: `s` repairs piece `id` (REPAIR_SHARE of its cost times the damage).
func server_repair_piece(s: Soldier, id: int) -> String:
	if not is_piece_built(id):
		return "Nothing built there"
	var rec: Dictionary = pieces[id]
	var def: Dictionary = BuildPieces.PIECES[String(rec.k)]
	var lost := 1.0 - float(rec.hp) / float(def.hp)
	if lost <= 0.001:
		return "It's sound"
	var why := tool_problem(s, String(def.tool))
	var cost := BuildPieces.scaled(def.cost, REPAIR_SHARE * lost)
	if cost.is_empty():
		cost = [def.cost[0].duplicate()]
		cost[0][1] = 1
	if why == "":
		why = cost_problem(s, cost)
	if why != "":
		return why
	_pay(s, cost)
	rec["hp"] = float(def.hp)
	_set_piece(id, rec)
	return ""


## Host: piece `id` takes `damage` (a blast, a breach, a durability hit from the dead later);
## at none it breaks: gone, with DEBRIS_SHARE of it on the ground.
func server_hit_piece(id: int, damage: float) -> void:
	var rec: Dictionary = pieces.get(id, {})
	if rec.is_empty() or damage <= 0.0:
		return
	rec["hp"] = float(rec.hp) - damage
	if float(rec.hp) > 0.0:
		_set_piece(id, rec)
		return
	var lvl := _level()
	var at := _piece_centre(rec)
	if lvl and is_piece_built(id):
		for pair: Array in BuildPieces.scaled(BuildPieces.PIECES[String(rec.k)].cost, DEBRIS_SHARE):
			lvl.server_spawn_dropped(StringName(pair[0]), int(pair[1]), lvl.ground_point(at) + Vector3.UP * 0.2)
	print("[build] the %s at %s breaks" % [rec.k, rec.c])
	_set_piece(id, {})


func _piece_centre(rec: Dictionary) -> Vector3:
	var c := Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2]))
	var size := BuildPieces.piece_size(String(rec.k), int(rec.r))
	return Vector3(c) * BuildPieces.BLOCK_M + Vector3(size) * BuildPieces.BLOCK_M * 0.5


## Host: after the block at `c` went, the pieces it held that nothing else holds fall.
func _check_pieces_near(c: Vector3i) -> void:
	for id: int in pieces.keys():
		var rec: Dictionary = pieces[id]
		var base := Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2]))
		var size := BuildPieces.piece_size(String(rec.k), int(rec.r))
		if not AABB(Vector3(base), Vector3(size)).grow(1.5).has_point(Vector3(c) + Vector3.ONE * 0.5):
			continue
		if not _piece_supported(String(rec.k), base, int(rec.r)):
			server_hit_piece(id, INF)


# --- Doors and locks (call 72) ----------------------------------------------------------------

## Whether `s` (or someone who has `code`) gets through piece `id`'s lock: no lock, or it's
## unlocked, or the key cut for it is in his inventory, or the code is right or known to him.
func can_unlock(s: Soldier, id: int, code := "") -> bool:
	var rec: Dictionary = pieces.get(id, {})
	var lock: Dictionary = rec.get("lock", {})
	if lock.is_empty():
		return true
	if lock.has("code"):
		return (code != "" and code == String(lock.code)) or (s != null and (lock.get("knows", []) as Array).has(s.display_name()))
	return s != null and has_key(s, String(lock.get("key", "")))


static func has_key(s: Soldier, lock_id: String) -> bool:
	for container: StringName in s.inventory.containers:
		for entry: Dictionary in s.inventory.containers[container]:
			if StringName(entry.id) == BuildPieces.KEY_ITEM and String((entry.get("state", {}) as Dictionary).get("lock", "")) == lock_id:
				return true
	return false


## Host: `s` works door (shutter, hatch, gate) `id`: "open" (unlocks it first if he can),
## "close", "lock_key" (fits a key lock and hands him its key), "lock_code" (a code lock: `code`,
## or a new four-digit one he's told), "lock" (locks it again: he has the key or the code),
## "unlock". `s` may be null with `code` (someone at the keypad). Returns why not ("" done).
func server_door(s: Soldier, id: int, action: String, code := "") -> String:
	var rec: Dictionary = pieces.get(id, {})
	if rec.is_empty() or not is_piece_built(id) or not bool(BuildPieces.PIECES[String(rec.k)].get("door", false)):
		return "That doesn't open"
	if s and not _near(s, _piece_centre(rec)):
		return "Too far"
	var lock: Dictionary = rec.get("lock", {})
	match action:
		"open":
			if bool(rec.locked):
				if not can_unlock(s, id, code):
					return "Locked"
				rec["locked"] = false
			rec["open"] = true
		"close":
			rec["open"] = false
		"lock_key", "lock_code":
			if not lock.is_empty():
				return "It has a lock"
			if bool(rec.open):
				return "Shut it first"
			if action == "lock_key":
				var lock_id := "L%d_%05d" % [id, randi() % 100000]
				rec["lock"] = {"key": lock_id}
				if s:
					_give_key(s, lock_id)
			else:
				var new_code := code if code.is_valid_int() and code.length() >= 3 else "%04d" % (randi() % 10000)
				rec["lock"] = {"code": new_code, "knows": [s.display_name()] if s else []}
				if s:
					_tell(s, "Code lock set: %s" % new_code)
			rec["locked"] = true
		"lock":
			if lock.is_empty():
				return "It has no lock"
			if bool(rec.open):
				return "Shut it first"
			if not can_unlock(s, id, code):
				return "You can't lock it"
			rec["locked"] = true
		"unlock":
			if not can_unlock(s, id, code):
				return "Locked"
			rec["locked"] = false
		_:
			return "Can't do that"
	_set_piece(id, rec)
	return ""


func _give_key(s: Soldier, lock_id: String) -> void:
	if s.inventory.take(BuildPieces.KEY_ITEM, 1, {"lock": lock_id}) < 1:
		var lvl := _level()
		if lvl:
			lvl.server_spawn_dropped(BuildPieces.KEY_ITEM, 1, s.global_position + Vector3.UP * 0.3, {"lock": lock_id})


# --- Records, voxels and nodes ----------------------------------------------------------------

## Every peer: block record `rec` at `c` ({} removes it); the host sends it on.
func _set_block(c: Vector3i, rec: Dictionary) -> void:
	if rec.is_empty():
		blocks.erase(c)
	else:
		blocks[c] = rec
	_refresh_site(c)
	if multiplayer.is_server() and _sending:
		_client_block.rpc(BuildPieces.key_of(c), rec)


@rpc("authority", "call_remote", "reliable")
func _client_block(key: String, rec: Dictionary) -> void:
	_set_block(BuildPieces.cell_of(key), rec)


## Every peer: piece record `rec` for `id` ({} removes it), its node made, updated or freed.
func _set_piece(id: int, rec: Dictionary) -> void:
	var old: Dictionary = pieces.get(id, {})
	if not old.is_empty():
		for cell in BuildPieces.piece_cells(String(old.k), Vector3i(int(old.c[0]), int(old.c[1]), int(old.c[2])), int(old.r)):
			_cells.erase(cell)
	if rec.is_empty():
		pieces.erase(id)
		var node: Node = _piece_nodes.get(id)
		if node:
			node.queue_free()
		_piece_nodes.erase(id)
	else:
		pieces[id] = rec
		_next_id = maxi(_next_id, id + 1)
		for cell in BuildPieces.piece_cells(String(rec.k), Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2])), int(rec.r)):
			_cells[cell] = id
		var node: BuildPiece = _piece_nodes.get(id)
		if node == null:
			node = BuildPiece.new()
			node.builder = self
			node.id = id
			node.name = "Piece%d" % id
			_piece_nodes[id] = node
			add_child(node)
		node.apply(rec)
	if multiplayer.is_server() and _sending:
		_client_piece.rpc(id, rec)


@rpc("authority", "call_remote", "reliable")
func _client_piece(id: int, rec: Dictionary) -> void:
	_set_piece(id, rec)


func piece_node(id: int) -> BuildPiece:
	return _piece_nodes.get(id)


## The piece over cell `c` (-1 for none).
func piece_at(c: Vector3i) -> int:
	return int(_cells.get(c, -1))


## A site's ghost: a see-through box filling up with its progress (a blueprint's blue).
func _refresh_site(c: Vector3i) -> void:
	var rec: Dictionary = blocks.get(c, {})
	var unbuilt := not rec.is_empty() and (float(rec.prog) < 1.0 or bool(rec.get("bp", false)) or rec.has("up"))
	var node: MeshInstance3D = _site_nodes.get(c)
	if not unbuilt:
		if node:
			node.queue_free()
			_site_nodes.erase(c)
		return
	if node == null:
		node = MeshInstance3D.new()
		node.mesh = BoxMesh.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		_site_nodes[c] = node
		add_child(node)
	var fill := clampf(float(rec.get("uprog", 0.0)) if rec.has("up") else float(rec.prog), 0.08, 1.0)
	var m := String(rec.get("up", rec.m))
	var colour := Color(0.4, 0.6, 1.0, 0.3) if bool(rec.get("bp", false)) else VoxelWorld.PALETTE[int(BuildPieces.MATERIALS[m].mat)]
	colour.a = 0.3 if bool(rec.get("bp", false)) else 0.55
	(node.material_override as StandardMaterial3D).albedo_color = colour
	var size := Vector3(BuildPieces.BLOCK_M, BuildPieces.BLOCK_M * fill, BuildPieces.BLOCK_M) * 1.02
	(node.mesh as BoxMesh).size = size
	node.position = Vector3(c) * BuildPieces.BLOCK_M + Vector3(BuildPieces.BLOCK_M * 0.5, size.y * 0.5, BuildPieces.BLOCK_M * 0.5)


static func _chunk_key(c: Vector3i) -> String:
	return BuildPieces.key_of(chunk_of(c))


func _log(key: String) -> Array:
	if not logs.has(key):
		logs[key] = []
	return logs[key]


## Host: a build op on cell `c`'s voxels ("bset": the block's shape in its material, "bclr"):
## logged, applied and sent like any voxel edit.
func _op(c: Vector3i, edit: Dictionary) -> void:
	var ch := chunk_of(c)
	var local := (c - ch * CHUNK_CELLS) * BuildPieces.BLOCK_VOX
	edit["c"] = [local.x, local.y, local.z]
	var key := BuildPieces.key_of(ch)
	_chunk(key, true)
	_edit(key, edit)


## Host (a chunk's edit_sink, and _op): logs `edit` for chunk `key`, applies it, sends it on.
func _edit(key: String, edit: Dictionary) -> void:
	_log(key).append(edit)
	var w: BuildVoxels = _chunks.get(key)
	if w:
		w.apply_edit(edit)
	_client_edit.rpc(key, edit)


func _on_chunk_edit(world: VoxelWorld, edit: Dictionary) -> void:
	_edit(world.module_id, edit)


@rpc("authority", "call_remote", "reliable")
func _client_edit(key: String, edit: Dictionary) -> void:
	_log(key).append(edit)
	var w: BuildVoxels = _chunks.get(key)
	if w:
		w.apply_edit(edit)


## The chunk `key`'s voxels (made, its log replayed, when `make`).
func _chunk(key: String, make: bool) -> BuildVoxels:
	var w: BuildVoxels = _chunks.get(key)
	if w or not make:
		return w
	w = BuildVoxels.new()
	w.chunk = BuildPieces.cell_of(key)
	w.name = "Chunk_" + key.replace(",", "_").replace("-", "m")
	w.module_id = key
	w.builder = self
	w.position = Vector3(w.chunk) * CHUNK_M
	w.view_distance = int((STREAM_OUT_M + 80.0) / VoxelWorld.VOXEL_SIZE)
	if multiplayer.is_server():
		w.edit_sink = _on_chunk_edit
	_chunks[key] = w
	add_child(w)
	for edit: Dictionary in logs.get(key, []):
		w.apply_edit(edit)
	return w


## The chunk holding cell `c`, if streamed in.
func chunk_at(c: Vector3i) -> BuildVoxels:
	return _chunks.get(_chunk_key(c))


## The voxel material at a world point in the builds (VoxelWorld.Mat; EMPTY when none).
func material_at(p: Vector3) -> int:
	var w: BuildVoxels = _chunks.get(_chunk_key(BuildPieces.cell_at(p)))
	return w.material_at(p) if w and w.is_built() else VoxelWorld.Mat.EMPTY


## Every peer: chunks stream in near the players (this peer's own, on a client) and out past
## STREAM_OUT_M, rebuilt from their logs.
func _stream() -> void:
	var lvl := _level()
	if lvl == null or logs.is_empty():
		return
	var focus: Array[Vector3] = []
	if multiplayer.is_server():
		for p in lvl.players.get_children():
			if p is Node3D:
				focus.append((p as Node3D).global_position)
	else:
		var me := MapNodes.local_player(self)
		if me:
			focus.append(me.global_position)
	if focus.is_empty():
		return
	for key: String in logs:
		var centre := (Vector3(BuildPieces.cell_of(key)) + Vector3.ONE * 0.5) * CHUNK_M
		var d := INF
		for f in focus:
			d = minf(d, f.distance_to(centre))
		if d <= STREAM_IN_M and not _chunks.has(key):
			_chunk(key, true)
		elif d > STREAM_OUT_M and _chunks.has(key):
			(_chunks[key] as Node).queue_free()
			_chunks.erase(key)


func _process(delta: float) -> void:
	var now := _now_ms() / 1000.0
	if now >= _next_stream:
		_next_stream = now + STREAM_CHECK_S
		_stream()
	if not multiplayer.is_server():
		return
	_advance_workers(delta)
	if _job and _job.done():
		_apply_solve(_job.finish())
		_job = null
	if _job == null and not _dirty.is_empty():
		_job = BuildIntegrity.Job.new(_take_cluster())
		_job.start()
	_check_cracks()


# --- Owners' requests -------------------------------------------------------------------------

## Owner: asks the host for build `action` with `args` (BuildMode, BuildPiece's menu).
static func ask(from: Node, action: String, args: Array) -> void:
	var b := of(from)
	if b == null:
		return
	if b.multiplayer.is_server():
		var me := MapNodes.local_player(b)
		if me:
			var why := b._do(me, action, args)
			if why != "":
				b._tell(me, why)
	else:
		b.request.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func request(action: String, args: Array) -> void:
	if not multiplayer.is_server():
		return
	var lvl := _level()
	var s := lvl.players.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Soldier if lvl else null
	if s == null:
		return
	var why := _do(s, action, args)
	if why != "":
		_tell(s, why)


## Host: one request from `s`. Returns why it didn't happen ("" when it did).
func _do(s: Soldier, action: String, args: Array) -> String:
	if not s.vitals.is_up():
		return "Not now"
	if not args.is_empty() and action in ["place", "work", "dismantle", "repair", "upgrade"] and not args[0] is Vector3i:
		return "?"
	if action == "piece" and args.size() >= 2 and not args[1] is Vector3i:
		return "?"
	match action:
		"place":  # [cell, material, shape, rot, blueprint]
			if args.size() < 5:
				return "?"
			return server_place(s, args[0], String(args[1]), String(args[2]), int(args[3]), bool(args[4]))
		"work":  # [cell]: keep working the site there while asked
			if args.is_empty():
				return "?"
			_workers[s.get_instance_id()] = {"s": s, "kind": "block", "at": args[0], "until": _now_ms() / 1000.0 + WORK_HOLD_S}
			return ""
		"work_piece":  # [id]
			if args.is_empty():
				return "?"
			_workers[s.get_instance_id()] = {"s": s, "kind": "piece", "at": int(args[0]), "until": _now_ms() / 1000.0 + WORK_HOLD_S}
			return ""
		"dismantle":
			return server_dismantle(s, args[0]) if not args.is_empty() else "?"
		"repair":
			return server_repair(s, args[0]) if not args.is_empty() else "?"
		"upgrade":  # [cell, material]
			return server_upgrade(s, args[0], String(args[1])) if args.size() >= 2 else "?"
		"piece":  # [kind, cell, rot, blueprint]
			if args.size() < 4:
				return "?"
			server_place_piece(s, String(args[0]), args[1], int(args[2]), bool(args[3]))
			return last_problem
		"piece_act":  # [id, action, code]
			if args.size() < 2:
				return "?"
			var id := int(args[0])
			var what := String(args[1])
			match what:
				"dismantle":
					return server_dismantle_piece(s, id)
				"repair":
					return server_repair_piece(s, id)
			var extra := Infrastructure.server_piece_act(self, s, id, what)  # (phase D pieces: traps, lures, the pyre)
			if extra != "?":
				return extra
			return server_door(s, id, what, String(args[2]) if args.size() > 2 else "")
		"dev_kit":
			if not DevTools.on():
				return "Dev tools are off"
			server_dev_kit(s)
			return "Building kit given (dev)"
	return "Can't do that"


func _advance_workers(delta: float) -> void:
	if _workers.is_empty():
		return
	var now := _now_ms() / 1000.0
	for key: int in _workers.keys():
		var w: Dictionary = _workers[key]
		var s: Soldier = w.s if is_instance_valid(w.s) else null
		if s == null or now > float(w.until) or not s.vitals.is_up():
			_workers.erase(key)
			continue
		var why := ""
		if w.kind == "block":
			var c: Vector3i = w.at
			if not _near(s, BuildPieces.cell_centre(c)):
				why = "Too far"
			else:
				why = server_work(s, c, delta)
			if why == "It's built":
				why = ""
				_workers.erase(key)
		else:
			var id := int(w.at)
			if pieces.has(id) and not _near(s, _piece_centre(pieces[id])):
				why = "Too far"
			else:
				why = server_work_piece(s, id, delta)
			if why == "It's built":
				why = ""
				_workers.erase(key)
		if why != "":
			_workers.erase(key)
			_tell(s, why)


## Host: a line on `s`'s screen (his HUD's flash).
func _tell(s: Soldier, text: String) -> void:
	var peer := String(s.name).to_int()
	if peer == multiplayer.get_unique_id() or s == MapNodes.local_player(self):
		_show(text)
	elif peer > 0:
		_told.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _told(text: String) -> void:
	_show(text)


func _show(text: String) -> void:
	var me := MapNodes.local_player(self)
	var hud: Variant = me.get(&"_hud") if me else null
	if hud is Object and (hud as Object).has_method(&"flash"):
		(hud as Object).call(&"flash", text)


## Host: a building kit (dev tools and tests, until felling and stripping give materials): the
## tools and some of every material; what doesn't fit lies at his feet.
func server_dev_kit(s: Soldier) -> void:
	_give(s, [[&"hammer", 1], [&"trowel", 1], [&"shovel", 1], [&"cutting_torch", 1], [&"wrench_set", 1], [&"saw", 1],
		[&"planks", 30], [&"scrap_sheet", 12], [&"sandbag", 8], [&"brick", 12], [&"concrete_bag", 6], [&"steel_beam", 4]], s.global_position)


# --- Late joiners ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	_client_all.rpc_id(multiplayer.get_remote_sender_id(), _blocks_out(), _pieces_out(), logs)


@rpc("authority", "call_remote", "reliable")
func _client_all(p_blocks: Dictionary, p_pieces: Dictionary, p_logs: Dictionary) -> void:
	_load(p_blocks, p_pieces, p_logs)


func _blocks_out() -> Dictionary:
	var out := {}
	for c: Vector3i in blocks:
		out[BuildPieces.key_of(c)] = blocks[c]
	return out


func _pieces_out() -> Dictionary:
	var out := {}
	for id: int in pieces:
		out[str(id)] = pieces[id]
	return out


# --- Saves ----------------------------------------------------------------------------------

## The zone save's record of the builds (GameState.builds): every block and piece, and the
## chunks' voxel logs.
func to_save() -> Dictionary:
	return {"blocks": _blocks_out(), "pieces": _pieces_out(), "logs": logs, "next_id": _next_id}


## Whether `v` is a saved builds section (to_save) GameState.read_save keeps: the three
## sections dictionaries (single bad records are dropped on load: _load).
static func save_ok(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and typeof((v as Dictionary).get("blocks", {})) == TYPE_DICTIONARY \
		and typeof((v as Dictionary).get("pieces", {})) == TYPE_DICTIONARY and typeof((v as Dictionary).get("logs", {})) == TYPE_DICTIONARY


## Host: the builds the zone save kept (to_save) back, and to every peer.
func server_restore(saved: Dictionary) -> void:
	if not save_ok(saved):
		return
	_next_id = maxi(_next_id, int(saved.get("next_id", 1)))
	_load(saved.get("blocks", {}), saved.get("pieces", {}), saved.get("logs", {}))
	for c: Vector3i in blocks:
		if is_built(c):
			_mark_dirty(c)
	if not blocks.is_empty() or not pieces.is_empty():
		print("[build] %d blocks and %d pieces back from the save" % [blocks.size(), pieces.size()])
		_client_all.rpc(_blocks_out(), _pieces_out(), logs)


## Every peer: records and logs as saved or sent (JSON numbers come back as floats), checked
## record by record.
func _load(p_blocks: Dictionary, p_pieces: Dictionary, p_logs: Dictionary) -> void:
	for key: Variant in p_logs:
		var list: Variant = p_logs[key]
		if typeof(list) != TYPE_ARRAY:
			continue
		var edits: Array = (list as Array).filter(func(e: Variant) -> bool: return typeof(e) == TYPE_DICTIONARY and typeof((e as Dictionary).get("op")) == TYPE_STRING)
		logs[String(key)] = edits
	for key: Variant in p_blocks:
		var r: Variant = p_blocks[key]
		if typeof(r) != TYPE_DICTIONARY or not BuildPieces.MATERIALS.has(String(r.get("m", ""))) or not BuildPieces.SHAPES.has(String(r.get("s", ""))):
			push_warning("Builder: skipping a bad block record (%s)" % str(r).left(80))
			continue
		var rec := {"m": String(r.m), "s": String(r.s), "r": int(r.get("r", 0)), "hp": float(r.get("hp", 1.0)), "prog": float(r.get("prog", 1.0)),
			"bp": bool(r.get("bp", false)), "paid": bool(r.get("paid", true)), "cracked": false}
		if BuildPieces.MATERIALS.has(String(r.get("up", ""))):
			rec["up"] = String(r.up)
			rec["uprog"] = float(r.get("uprog", 0.0))
		var c := BuildPieces.cell_of(String(key))
		blocks[c] = rec
		_refresh_site(c)
	for key: Variant in p_pieces:
		var r: Variant = p_pieces[key]
		if typeof(r) != TYPE_DICTIONARY or not BuildPieces.PIECES.has(String(r.get("k", ""))) or typeof(r.get("c")) != TYPE_ARRAY or (r.c as Array).size() != 3:
			push_warning("Builder: skipping a bad piece record (%s)" % str(r).left(80))
			continue
		var lock: Variant = r.get("lock", {})
		var rec := {"k": String(r.k), "c": [int(r.c[0]), int(r.c[1]), int(r.c[2])], "r": int(r.get("r", 0)), "hp": float(r.get("hp", 1.0)),
			"prog": float(r.get("prog", 1.0)), "bp": bool(r.get("bp", false)), "paid": bool(r.get("paid", true)), "open": bool(r.get("open", false)),
			"locked": bool(r.get("locked", false)), "lock": lock if typeof(lock) == TYPE_DICTIONARY else {}}
		var id := int(String(key)) if String(key).is_valid_int() else _next_id
		_sending = false  # (the whole set goes at once: server_restore)
		_set_piece(id, rec)
		_sending = true
	for key: String in logs:
		var w: BuildVoxels = _chunks.get(key)
		if w:
			_chunks.erase(key)
			w.queue_free()
	_next_stream = 0.0  # stream the chunks in round the players now


# --- The settlement's work (Settlement, SettlementJobs: docs/survival_building.md §6) ----------

## Host: `seconds` of a settler's work on the block site, blueprint or upgrade at `c` with no
## body in reach: the materials come through `pay` (a cost -> bool: taken from the settlement's
## stock) and the settlement's tools are taken as at hand (Proposed). "" while it goes on or done.
func server_work_from_stock(c: Vector3i, seconds: float, pay: Callable) -> String:
	var rec: Dictionary = blocks.get(c, {})
	if rec.is_empty():
		return "Nothing to build there"
	var upgrading := rec.has("up")
	if not upgrading and is_built(c):
		return "It's built"
	var mat := String(rec.up) if upgrading else String(rec.m)
	if not bool(rec.get("paid", false)):
		if not bool(pay.call(BuildPieces.block_cost(mat, String(rec.s)))):
			return "Short of materials"
		rec["paid"] = true
		rec["bp"] = false
	var field := "uprog" if upgrading else "prog"
	var before := float(rec.get(field, 0.0))
	var after := minf(before + seconds / float(BuildPieces.MATERIALS[mat].build_s), 1.0)
	var why := ""
	if after >= 1.0 and not upgrading and int(preview(c, mat, String(rec.s)).state) == BuildIntegrity.State.FREE:
		after = 0.99
		why = "Nothing holds it yet"
	rec[field] = after
	if after >= 1.0:
		_finish_block(c, rec)
	else:
		_set_block(c, rec)
	return why


## Host: the same for piece `id`'s site or blueprint.
func server_work_piece_from_stock(id: int, seconds: float, pay: Callable) -> String:
	var rec: Dictionary = pieces.get(id, {})
	if rec.is_empty():
		return "Nothing to build there"
	if is_piece_built(id):
		return "It's built"
	var def: Dictionary = BuildPieces.PIECES[String(rec.k)]
	if not bool(rec.paid):
		if not bool(pay.call(def.cost)):
			return "Short of materials"
		rec["paid"] = true
		rec["bp"] = false
	rec["prog"] = minf(float(rec.prog) + seconds / float(def.build_s), 1.0)
	if float(rec.prog) >= 1.0:
		print("[build] %s built at %s (the settlement)" % [rec.k, rec.c])
	_set_piece(id, rec)
	return ""


## Host: the maintain job repairs the block at `c` (or piece `id` when `id` > 0) to whole from
## stock: REPAIR_SHARE of its cost times the damage through `pay`. Returns whether it did.
func server_repair_from_stock(c: Vector3i, id: int, pay: Callable) -> bool:
	if id > 0:
		if not is_piece_built(id):
			return false
		var prec: Dictionary = pieces[id]
		var def: Dictionary = BuildPieces.PIECES[String(prec.k)]
		var lost := 1.0 - float(prec.hp) / float(def.hp)
		if lost <= 0.001:
			return false
		var pcost := BuildPieces.scaled(def.cost, REPAIR_SHARE * lost)
		if pcost.is_empty():
			pcost = [[def.cost[0][0], 1]]
		if not bool(pay.call(pcost)):
			return false
		prec["hp"] = float(def.hp)
		_set_piece(id, prec)
		return true
	if not is_built(c) or float(blocks[c].hp) >= 0.999:
		return false
	var rec: Dictionary = blocks[c]
	var full: Array = BuildPieces.block_cost(String(rec.m), String(rec.s))[0]
	if not bool(pay.call([[full[0], maxi(1, ceili(float(full[1]) * REPAIR_SHARE * (1.0 - float(rec.hp))))]])):
		return false
	rec["hp"] = 1.0
	_set_block(c, rec)
	_mark_dirty(c)
	return true


## Whether a player is working the block site at `c` (or piece `id` when `id` > 0) right now:
## a job he's doing isn't taken over (doc §6).
func worked_by_player(c: Vector3i, id := -1) -> bool:
	for w: Dictionary in _workers.values():
		if id > 0 and String(w.kind) != "block" and int(w.at) == id:
			return true
		if id <= 0 and String(w.kind) == "block" and w.at == c:
			return true
	return false


## The built pieces of `kind` (ids).
func pieces_of(kind: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in pieces:
		if String(pieces[id].k) == kind and is_piece_built(id):
			out.append(id)
	return out


## Where piece `id` is (its middle), for the settlement's radius.
func piece_pos(id: int) -> Vector3:
	return _piece_centre(pieces[id]) if pieces.has(id) else Vector3.INF
