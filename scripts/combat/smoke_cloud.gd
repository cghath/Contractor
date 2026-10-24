class_name SmokeCloud
extends Node3D
## A smoke screen as a volume on a coarse grid of cells (S5, docs/ChrisPlan_handoff.md: "Voxel
## smoke (CS2-style)"). Spawned on every peer (CompoundLevel.spawn_smoke) and simulated the same
## on each from its seed and its events, so what a player sees and what blocks AI line of sight
## (blocks) follow the one cloud. Coloured smokes (green, yellow, blue, purple) block the same
## way; their colour is what the helicopter supports and extraction look for (clouds_of).
##
## - The grid: CELL-metre cells lined up on where the grenade lies, out to REACH_CELLS round it,
##   UP_CELLS above and DOWN_CELLS below. Smoke passes between two neighbouring cells only if a
##   ray between their centres meets nothing of the world (physics layer 1: voxel walls, the
##   buildings, terrain, the ground), tested once per pair the first time the cloud gets there
##   and kept (_edges). So it stops at walls, floors and ceilings, and gets out of a room only
##   through its doorways, windows and holes.
## - Growth (the grenade's burn): the cloud claims cells best-first from the grenade's, over open
##   pairs only, up to its volume now (volume_at: GROWN_SHARE of MAX_CELLS by GROW_S, all of it
##   by EMIT_S, then spreading on to SPREAD_CELLS as it thins). Best is nearest (rounder than
##   steps along the grid would make it; flatter, as going up costs COST_UP; reaching downwind),
##   plus any detour the path takes round walls, plus a ragged edge from the seed. A closed room
##   fills and it stops there; from a room with a door, what doesn't fit goes out of the door.
## - Density: each claimed cell eases (RATE_UP, RATE_DOWN a step) towards the cloud's density
##   now (target_at: full while it burns, THIN by DURATION_S - FADE_S, gone by DURATION_S), RIM
##   of it in the cloud's outer layer (a cell with an open neighbour the cloud hasn't taken), less
##   in a hole, and once it's burnt out the wind thins the upwind side first, a line moving
##   downwind (drift_line): the cloud drifts off. A cell that has eased to the cloud's body (or
##   outer layer) settles: from then on the cloud moves all of those together (_core, _rim), and
##   only the cells still changing cost a step anything.
## - Events: a blast (CompoundLevel.server_blast: frags, warheads, charges, bombs) clears the
##   cells round it (a hole: HOLE_MAX at its middle, refilling HOLE_REFILL a step, so it closes
##   from the rim in) and, RELINK_STEPS later, tests the pairs round it again (a wall it blew
##   open lets the smoke through). A round through the smoke (CompoundLevel.show_tracer) parts
##   the cells on its line (CS2's: you can see down it for a moment), refilling within about a
##   second and a half (SHOT_HOLE).
## - Sight: blocks() adds up the smoke along a line through every cloud's cells (optical depth:
##   SIGMA_M a metre at full density) and blocks at BLOCK_DEPTH. Full smoke blocks within a few
##   tens of centimetres, a cloud's thin outer layer only over a metre or more, a doorway only
##   if the smoke fills it.
## - Looks: one MultiMesh of boxes a cloud (the voxel style, smoke_cloud.gdshader), one box a
##   claimed cell, each as opaque as its cell's smoke over one cell (the same optical depth),
##   eased between steps on the GPU; tinted by colour.
## - Network: the host picks the seed and the wind (CompoundLevel.server_spawn_smoke) and sends
##   each event with the step it happens at, EVENT_LEAD steps ahead (CompoundLevel.smoke_event);
##   clients run CLIENT_LAG steps behind the clock. A late joiner gets the seed, wind, age and
##   every event (CompoundLevel._send_smoke_to) and steps up to its age at once. Same seed,
##   events and world: the same cloud on every peer (integer densities, no transcendental maths
##   in a step). An event that arrives after its step rebuilds the cloud from the start
##   (rebuilds).
## - Cost: HZ steps a second; every cloud's steps share BUDGET_USEC a physics tick; a cloud more
##   than MAX_LAG steps behind catches up at once. Rays only for pairs not yet tested.
## Every number is proposed, for Captain's playtests.

const CELL := 0.5
## The grenade's cell's centre sits this far over it (it lies on the ground).
const BASE_UP := 0.25
const REACH_CELLS := 28
const UP_CELLS := 7
const DOWN_CELLS := 6
const HZ := 8
const GROW_S := 3.0
const EMIT_S := 12.0
const DURATION_S := 30.0
const FADE_S := 7.0
const MAX_CELLS := 1300
const SPREAD_CELLS := 1600
const GROWN_SHARE := 0.75
const MAX_CLAIM_PER_STEP := 90
## Discovered cells (claimed and waiting at the flood's edge) at most.
const MAX_FOUND := 6000
## Density of a full cell.
const FULL := 1000
const THIN := 0.7
## How fast a cell's smoke eases to its target, in 256ths a step; within SETTLE of the cloud's
## body (or outer layer) it settles.
const RATE_UP := 90
const RATE_DOWN := 40
const SETTLE := 20
## The cloud's outer layer is this thin (256ths of its body).
const RIM := 64
## Flood costs of a step between cells (100 = one cell sideways), and how much a m/s of wind
## along a sideways step takes off it (adds against the wind).
const COST_SIDE := 100
const COST_UP := 112
const COST_DOWN := 150
const WIND_COST := 18
const JITTER_CELL := 30
const JITTER_BLOCK := 60
## Once burnt out, the upwind side thins first: cells further upwind than drift_line, which
## starts DRIFT_START_CELLS upwind of the grenade and moves downwind at the wind's speed.
const DRIFT_START_CELLS := 6.0
const DRIFT_X := 1.0
## Holes: a blast clears HOLE_MAX (256ths, past 256 a while) at its middle, nothing at its edge;
## every hole refills HOLE_REFILL a step. A blast pushes BLAST_PUSH_M plus BLAST_PUSH_X its
## crater's radius (at most BLAST_PUSH_MAX_M). A round parts the cells on its line by SHOT_HOLE.
const HOLE_MAX := 480
const HOLE_REFILL := 24
const BLAST_PUSH_M := 2.0
const BLAST_PUSH_X := 2.5
const BLAST_PUSH_MAX_M := 6.0
const SHOT_HOLE := 300
## A round parts a cloud only through this much of it (optical depth).
const SHOT_MIN_DEPTH := 0.3
const RELINK_STEPS := 4
const EVENT_LEAD := 2
const CLIENT_LAG := 2
const MAX_EVENTS := 96
const MAX_SHOT_EVENTS := 64
const BLAST := 0
const SHOT := 1
## Optical depth a metre of full smoke, and the depth a sight line can't see through.
const SIGMA_M := 10.0
const BLOCK_DEPTH := 3.0
const BUDGET_USEC := 2000
const MAX_LAG := 6
const WORLD_MASK := 1
const BUCKET_COST := 8
const BUCKETS := 4096
## Drift by weather (m/s near the ground), from one of eight directions by zone (wind_here).
const WIND_MPS := {"clear": 0.5, "overcast": 0.8, "fog": 0.2, "rain": 1.2, "storm": 2.0}
const WIND_DIRS: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0.70710677, 0, 0.70710677), Vector3(0, 0, 1),
	Vector3(-0.70710677, 0, 0.70710677), Vector3(-1, 0, 0), Vector3(-0.70710677, 0, -0.70710677), Vector3(0, 0, -1),
	Vector3(0.70710677, 0, -0.70710677)]
## Cloud colour by name (a smoke grenade's "smoke_colour" stat). Unknown names show white.
const COLOURS := {
	"white": Color(0.8, 0.82, 0.82),
	"green": Color(0.36, 0.62, 0.3),
	"yellow": Color(0.92, 0.8, 0.3),
	"blue": Color(0.33, 0.5, 0.86),
	"purple": Color(0.56, 0.34, 0.72),
	"multispectral": Color(0.62, 0.6, 0.55),  # (combined arms A7: the vehicles' dischargers, ThermalView.MULTISPECTRAL)
}
## +x, -x, +y, -y, +z, -z: a direction's opposite is k ^ 1.
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## A claimed cell: still changing (its own density), settled in the body or the outer layer
## (the cloud's _core or _rim), or gone (blown away upwind).
const MOVING := 0
const CORE := 1
const OUTER := 2
const GONE := 3
const SHADER := preload("res://scripts/combat/smoke_cloud.gdshader")

static var active: Array[SmokeCloud] = []
## Tests: the wind every new cloud gets (null: by the weather, wind_here).
static var wind_override: Variant = null
## Microseconds every cloud's steps took, ever (perf checks).
static var spent_usec := 0
## The longest one step took (us), and rays cast for pairs of cells, ever (perf checks).
static var worst_step_usec := 0
static var rays := 0
static var _budget_frame := -1
static var _budget_left := 0

## A name in COLOURS. Set before the cloud enters the tree (CompoundLevel.spawn_smoke).
var colour := "white"
## Seconds since it went off. A late joiner's copy starts at the host's age (spawn_smoke).
var age := 0.0
## The host's pick (or one from where and what it is: seed_at); the same on every peer.
var cloud_seed := 1
## The wind it drifts with (m/s, flat).
var wind := Vector3.ZERO
## [step, BLAST or SHOT, a, b]: a blast at a (b.x its push radius, b.y its crater's), a round
## from a to b. In the order the host made them.
var events: Array = []
## How far the claimed cells reach sideways from the grenade (m).
var radius := 0.0
## Steps simulated.
var step := 0
## Times an event came after its step and the cloud was rebuilt from the start.
var rebuilds := 0
var _shot_events := 0
var _started := false
var _origin := Vector3.ZERO  # the grenade's cell's centre
var _step_cost := PackedInt32Array()
var _wind_speed := 0.0
# Cells, by number: grid coordinates, density (a moving cell's), flood cost and priority base,
# hole, upwind distance (cells), slot in the claimed list (-1: not claimed), state, open
# neighbours not claimed yet, place in the moving list (-1: none) and the six neighbours (-1: not
# looked at yet, -2: closed or out of reach).
var _index := {}
var _cx := PackedInt32Array()
var _cy := PackedInt32Array()
var _cz := PackedInt32Array()
var _d := PackedInt32Array()
var _g := PackedInt32Array()
var _base := PackedInt32Array()
var _hole := PackedInt32Array()
var _upw := PackedFloat32Array()
var _slot := PackedInt32Array()
var _state := PackedInt32Array()
var _out := PackedInt32Array()
var _at := PackedInt32Array()
var _nb := PackedInt32Array()
var _claimed := PackedInt32Array()
var _moving := PackedInt32Array()
## The settled body's and outer layer's density, this step and the one before.
var _core := 0
var _rim := 0
var _core_was := 0
var _rim_was := 0
var _lo := Vector3i.ZERO
var _hi := Vector3i.ZERO
# The flood's edge: buckets by priority, each a list through _q_next.
var _head := PackedInt32Array()
var _q_cell := PackedInt32Array()
var _q_next := PackedInt32Array()
var _cursor := 0
# Claimed cells by how far upwind they are (furthest first: keys are minus that), and how many
# of them the drift has reached.
var _upw_keys := PackedFloat32Array()
var _by_upw := PackedInt32Array()
var _drifted := 0
## Pair key -> open (kept through a rebuild: the world, not the cloud).
var _edges := {}
var _ray: PhysicsRayQueryParameters3D
var _space: PhysicsDirectSpaceState3D
var _mm: MultiMesh
var _mat: ShaderMaterial
var _buf := PackedFloat32Array()
var _drawn := false
var _no_cells: Array[int] = []


## True when the sight line between the two points is blocked by smoke: BLOCK_DEPTH or more of
## it along the line, through any clouds.
static func blocks(from: Vector3, to: Vector3) -> bool:
	return depth_between(from, to, BLOCK_DEPTH) >= BLOCK_DEPTH


## The smoke's optical depth along the line from `from` to `to`, every cloud's (it stops adding
## once it reaches `enough`). The light through is exp(-depth).
static func depth_between(from: Vector3, to: Vector3, enough := INF) -> float:
	var depth := 0.0
	for cloud in active:
		if is_instance_valid(cloud):
			depth += cloud.depth_along(from, to, enough - depth)
			if depth >= enough:
				break
	return depth


## The live clouds of one colour ("green", "purple"...), oldest first.
static func clouds_of(colour_name: String) -> Array[SmokeCloud]:
	var found: Array[SmokeCloud] = []
	for cloud in active:
		if is_instance_valid(cloud) and cloud.colour == colour_name:
			found.append(cloud)
	return found


## The display colour for a colour name (white if unknown).
static func colour_value(colour_name: String) -> Color:
	return COLOURS.get(colour_name, COLOURS["white"])


## The cloud colour a smoke grenade item makes ("white" for anything else).
static func colour_of(item_id: StringName) -> String:
	var item := ItemDB.get_item(item_id)
	return String(item.stats.get("smoke_colour", "white")) if item else "white"


## A seed from where a smoke went off and its colour, for clouds spawned without one: every
## peer works out the same.
static func seed_at(pos: Vector3, colour_name: String) -> int:
	var h := _mix(roundi(pos.x * 100.0) & 0xfffff)
	h = _mix(h ^ (roundi(pos.y * 100.0) & 0xfffff))
	h = _mix(h ^ (roundi(pos.z * 100.0) & 0xfffff))
	h = _mix(h ^ (colour_name.hash() & 0x7fffffff))
	return maxi(1, h & 0x7fffffff)


## Host: a new seed no cloud under `level` has yet.
static func new_seed(level: Node) -> int:
	var s := maxi(1, randi() & 0x7fffffff)
	while level.has_node(NodePath(node_name(s))):
		s = maxi(1, (s + 1) & 0x7fffffff)
	return s


## A cloud's node name: the same on every peer, so events find it.
static func node_name(s: int) -> String:
	return "Smoke_%d" % s


## The wind a smoke drifts with here: by the weather (WIND_MPS), from one of WIND_DIRS by zone.
static func wind_here(_level: Node) -> Vector3:
	if wind_override != null:
		return wind_override
	var day := DayNight.current()
	var weather := day.weather if day else "clear"
	var dir: Vector3 = WIND_DIRS[(String(GameState.zone_id).hash() & 0x7fffffff) % WIND_DIRS.size()]
	return dir * float(WIND_MPS.get(weather, WIND_MPS["clear"]))


## Host (CompoundLevel.server_blast): a blast at `pos` with a crater of `carve_m` pushes a hole
## in every cloud it reaches.
static func server_blast(pos: Vector3, carve_m: float) -> void:
	var push := minf(BLAST_PUSH_M + carve_m * BLAST_PUSH_X, BLAST_PUSH_MAX_M)
	for cloud in active.duplicate():
		if is_instance_valid(cloud) and cloud._started and cloud.reaches(pos, push):
			cloud._server_event([cloud.step + EVENT_LEAD, BLAST, pos, Vector3(push, carve_m, 0.0)])


## Host (CompoundLevel.show_tracer): a round from `from` to `to` parts the smoke it goes through.
static func server_shot(from: Vector3, to: Vector3) -> void:
	for cloud in active.duplicate():
		if is_instance_valid(cloud) and cloud._started and cloud._shot_events < MAX_SHOT_EVENTS \
				and cloud.depth_along(from, to, SHOT_MIN_DEPTH) >= SHOT_MIN_DEPTH:
			cloud._shot_events += 1
			cloud._server_event([cloud.step + EVENT_LEAD, SHOT, from, to])


## How many cells a cloud fills at step `s`.
static func volume_at(s: int) -> int:
	var t := float(s) / HZ
	var v: float
	if t < GROW_S:
		v = MAX_CELLS * GROWN_SHARE * t / GROW_S
	elif t < EMIT_S:
		v = MAX_CELLS * (GROWN_SHARE + (1.0 - GROWN_SHARE) * (t - GROW_S) / (EMIT_S - GROW_S))
	else:
		v = MAX_CELLS + (SPREAD_CELLS - MAX_CELLS) * minf((t - EMIT_S) / (DURATION_S - FADE_S - EMIT_S), 1.0)
	return clampi(int(v), 1, SPREAD_CELLS)


## The density a cloud's body eases to at step `s`.
static func target_at(s: int) -> int:
	var t := float(s) / HZ
	if t < EMIT_S:
		return FULL
	if t < DURATION_S - FADE_S:
		return int(FULL * (1.0 - (1.0 - THIN) * (t - EMIT_S) / (DURATION_S - FADE_S - EMIT_S)))
	return int(FULL * THIN * maxf((DURATION_S - t) / FADE_S, 0.0))


static func _mix(a: int) -> int:
	a = ((a ^ (a >> 16)) * 0x45d9f3b) & 0xffffffff
	a = ((a ^ (a >> 16)) * 0x45d9f3b) & 0xffffffff
	return a ^ (a >> 16)


static func _pack(x: int, y: int, z: int) -> int:
	return (x + 64) | ((y + 64) << 7) | ((z + 64) << 14)


static func _ease(d: int, t: int) -> int:
	return d + (((t - d) * (RATE_UP if t > d else RATE_DOWN)) >> 8)


func _ready() -> void:
	active.append(self)


func _exit_tree() -> void:
	active.erase(self)


## The cloud's colour, as it shows (its boxes' tint once it's started).
func display_colour() -> Color:
	return _mat.get_shader_parameter(&"tint") if _mat else colour_value(colour)


## Tests: `seconds` old now, stepped straight up to it (the same cloud as stepping there in time).
func run_to(seconds: float) -> void:
	if not _started:
		_start()
	age = seconds
	var target := mini(int(age * HZ), int(DURATION_S * HZ))
	while step < target:
		var t := Time.get_ticks_usec()
		_step()
		spent_usec += Time.get_ticks_usec() - t
	_upload()


## Whether the claimed cells, grown by `margin` metres, take in `pos`.
func reaches(pos: Vector3, margin: float) -> bool:
	return not _claimed.is_empty() and bounds().grow(margin).has_point(pos)


## The box round the claimed cells, in world space.
func bounds() -> AABB:
	var lo := _origin + Vector3(_lo) * CELL - Vector3.ONE * CELL * 0.5
	return AABB(lo, Vector3(_hi - _lo + Vector3i.ONE) * CELL)


## Cells claimed.
func cell_count() -> int:
	return _claimed.size()


## Cells still changing (the ones a step costs).
func moving_count() -> int:
	return _moving.size()


## The smoke in all the claimed cells (FULL a full cell).
func total_smoke() -> int:
	var sum := 0
	for i in _claimed:
		sum += _density(i)
	return sum


## The smoke in the cell at world point `pos` (0..1, 0 outside the cloud).
func density_at(pos: Vector3) -> float:
	if not _started:
		return 0.0
	var g := (pos - _origin) / CELL
	var c := Vector3i(roundi(g.x), roundi(g.y), roundi(g.z))
	if not _in_reach(c.x, c.y, c.z):
		return 0.0
	var i: int = _index.get(_pack(c.x, c.y, c.z), -1)
	return float(_density(i)) / FULL if i >= 0 and _slot[i] >= 0 else 0.0


## The claimed cells' centres (world space), in the order the cloud took them.
func cell_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _claimed:
		out.append(_origin + Vector3(_cx[i], _cy[i], _cz[i]) * CELL)
	return out


## The smoke-weighted middle of the cloud (world space).
func centroid() -> Vector3:
	var sum := Vector3.ZERO
	var w := 0.0
	for i in _claimed:
		var d := float(_density(i))
		sum += Vector3(_cx[i], _cy[i], _cz[i]) * d
		w += d
	return _origin + (sum / w) * CELL if w > 0.0 else global_position


## A digest of the cloud's state (cells, where, how dense), for same-seed-same-cloud checks.
func digest() -> int:
	var h := _mix(step)
	for i in _claimed:
		h = _mix(h ^ _pack(_cx[i], _cy[i], _cz[i]))
		h = _mix(h ^ _density(i))
	return h


## An event (the host's, or one it sent). One for a step already simulated here rebuilds the
## cloud up to where it was.
func add_event(event: Array) -> void:
	events.append(event)
	if _started and int(event[0]) <= step:
		var to := step
		rebuilds += 1
		_reset()
		while step < to:
			_step()
		_upload()


func _server_event(event: Array) -> void:
	if events.size() >= MAX_EVENTS:
		return
	add_event(event)
	var level := get_parent() as CompoundLevel
	if level and level.multiplayer.has_multiplayer_peer():
		level.smoke_event.rpc(String(name), event)


func _physics_process(delta: float) -> void:
	age += delta
	if age > DURATION_S:
		queue_free()
		return
	if not _started:
		_start()
	var lag := 0 if multiplayer.is_server() else CLIENT_LAG
	var want := mini(int(age * HZ) - lag, int(DURATION_S * HZ))
	_advance(want)
	_mat.set_shader_parameter(&"blend", clampf(age * HZ - lag - step, 0.0, 1.0))


## Steps up to `want`, within this physics tick's budget (all clouds share it) unless it's more
## than MAX_LAG behind.
func _advance(want: int) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_left = BUDGET_USEC
	var stepped := false
	while step < want:
		if _budget_left <= 0 and want - step <= MAX_LAG:
			break
		var t := Time.get_ticks_usec()
		_step()
		stepped = true
		var used := Time.get_ticks_usec() - t
		worst_step_usec = maxi(worst_step_usec, used)
		_budget_left -= used
		spent_usec += used
		FrameCost.spent(&"smoke", t)
	if stepped:
		var t := Time.get_ticks_usec()
		_upload()
		spent_usec += Time.get_ticks_usec() - t


func _start() -> void:
	_started = true
	_origin = global_position + Vector3(0, BASE_UP, 0)
	_space = get_world_3d().direct_space_state
	_ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ONE, WORLD_MASK)
	_ray.hit_back_faces = true
	_ray.hit_from_inside = true
	_wind_speed = Vector2(wind.x, wind.z).length()
	_step_cost.resize(6)
	_step_cost[0] = clampi(roundi(COST_SIDE - WIND_COST * wind.x), 55, 170)
	_step_cost[1] = clampi(roundi(COST_SIDE + WIND_COST * wind.x), 55, 170)
	_step_cost[2] = COST_UP
	_step_cost[3] = COST_DOWN
	_step_cost[4] = clampi(roundi(COST_SIDE - WIND_COST * wind.z), 55, 170)
	_step_cost[5] = clampi(roundi(COST_SIDE + WIND_COST * wind.z), 55, 170)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"tint", colour_value(colour))
	_mat.set_shader_parameter(&"sigma_cell", SIGMA_M * CELL)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CELL
	_mm.mesh = box
	_mm.instance_count = SPREAD_CELLS
	_mm.visible_instance_count = 0
	_buf.resize(SPREAD_CELLS * 16)
	var draw := MultiMeshInstance3D.new()
	draw.name = "Boxes"
	draw.multimesh = _mm
	draw.material_override = _mat
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draw.custom_aabb = AABB(Vector3(-REACH_CELLS - 1, -DOWN_CELLS - 1, -REACH_CELLS - 1) * CELL + Vector3(0, BASE_UP, 0),
		Vector3(REACH_CELLS * 2 + 2, UP_CELLS + DOWN_CELLS + 2, REACH_CELLS * 2 + 2) * CELL)
	add_child(draw)
	_reset()


## Back to the grenade's one cell at step 0 (the pairs tested stay known).
func _reset() -> void:
	step = 0
	_index.clear()
	_cx = PackedInt32Array()
	_cy = PackedInt32Array()
	_cz = PackedInt32Array()
	_d = PackedInt32Array()
	_g = PackedInt32Array()
	_base = PackedInt32Array()
	_hole = PackedInt32Array()
	_upw = PackedFloat32Array()
	_slot = PackedInt32Array()
	_state = PackedInt32Array()
	_out = PackedInt32Array()
	_at = PackedInt32Array()
	_nb = PackedInt32Array()
	_claimed = PackedInt32Array()
	_moving = PackedInt32Array()
	_q_cell = PackedInt32Array()
	_q_next = PackedInt32Array()
	_upw_keys = PackedFloat32Array()
	_by_upw = PackedInt32Array()
	_drifted = 0
	_head = PackedInt32Array()
	_head.resize(BUCKETS)
	_head.fill(-1)
	_cursor = 0
	_core = 0
	_rim = 0
	_core_was = 0
	_rim_was = 0
	_lo = Vector3i.ZERO
	_hi = Vector3i.ZERO
	radius = 0.0
	_buf.fill(0.0)
	_drawn = false
	var first := _found(Vector3i.ZERO)
	_g[first] = 0
	_push(first, maxi(_base[first], 0))


func _in_reach(x: int, y: int, z: int) -> bool:
	return absi(x) <= REACH_CELLS and absi(z) <= REACH_CELLS and y <= UP_CELLS and y >= -DOWN_CELLS


## Cell `i`'s smoke now (FULL a full cell).
func _density(i: int) -> int:
	match _state[i]:
		CORE:
			return _core
		OUTER:
			return _rim
		GONE:
			return 0
	return _d[i]


## A newly found cell at grid `c`: its number.
func _found(c: Vector3i) -> int:
	var i := _cx.size()
	_cx.append(c.x)
	_cy.append(c.y)
	_cz.append(c.z)
	_d.append(0)
	_g.append(1 << 30)
	_hole.append(0)
	_slot.append(-1)
	_state.append(MOVING)
	_out.append(0)
	_at.append(-1)
	for k in 6:
		_nb.append(-1)
	var key := _pack(c.x, c.y, c.z)
	_index[key] = i
	# Its priority over its flood cost: how far it is (round, not along the grid) less the grid
	# distance (so the cost of a detour round a wall still counts), plus the ragged edge.
	var sx := _step_cost[0] if c.x > 0 else _step_cost[1]
	var sy := _step_cost[2] if c.y > 0 else _step_cost[3]
	var sz := _step_cost[4] if c.z > 0 else _step_cost[5]
	var ax := float(absi(c.x) * sx)
	var ay := float(absi(c.y) * sy)
	var az := float(absi(c.z) * sz)
	var round_cost := int(sqrt(ax * ax + ay * ay + az * az))
	var h := _mix(key ^ cloud_seed)
	var hb := _mix(_pack(c.x >> 1, c.y >> 1, c.z >> 1) ^ (cloud_seed * 31))
	_base.append(round_cost - int(ax + ay + az) + h % JITTER_CELL + hb % JITTER_BLOCK)
	_upw.append(-(c.x * wind.x + c.z * wind.z) / _wind_speed if _wind_speed > 0.05 else 0.0)
	return i


func _push(i: int, priority: int) -> void:
	var b := mini(priority / BUCKET_COST, BUCKETS - 1)
	_q_cell.append(i)
	_q_next.append(_head[b])
	_head[b] = _q_cell.size() - 1
	if b < _cursor:
		_cursor = b


## The next cell to claim from the flood's edge, or -1.
func _pop() -> int:
	while _cursor < BUCKETS:
		var e := _head[_cursor]
		if e < 0:
			_cursor += 1
			continue
		_head[_cursor] = _q_next[e]
		var i := _q_cell[e]
		if _slot[i] < 0:
			return i
	return -1


func _claim(i: int) -> void:
	var s := _claimed.size()
	_slot[i] = s
	_claimed.append(i)
	_state[i] = MOVING
	_at[i] = _moving.size()
	_moving.append(i)
	var c := Vector3i(_cx[i], _cy[i], _cz[i])
	if s == 0:
		_lo = c
		_hi = c
	else:
		_lo = _lo.min(c)
		_hi = _hi.max(c)
	radius = maxf(radius, maxi(absi(c.x), absi(c.z)) * CELL)
	var h := _mix(_pack(c.x, c.y, c.z) ^ (cloud_seed * 7))
	var size := 1.0 + float(h % 7) / 100.0
	var at := Vector3(c) * CELL + Vector3(0, BASE_UP, 0)
	var o := s * 16
	_buf[o] = size
	_buf[o + 3] = at.x
	_buf[o + 5] = size
	_buf[o + 7] = at.y
	_buf[o + 10] = size
	_buf[o + 11] = at.z
	_buf[o + 14] = 0.86 + float((h >> 8) % 15) / 100.0
	if _wind_speed > 0.05:
		var key := -_upw[i]
		var pos := _upw_keys.bsearch(key)
		_upw_keys.insert(pos, key)
		_by_upw.insert(pos, i)
		if pos < _drifted:
			_drifted += 1
	_spread_from(i)
	# Its neighbours in the cloud lose an open way out; it has the rest.
	for k in 6:
		var j := _nb[i * 6 + k]
		if j >= 0 and _slot[j] >= 0:
			_out[j] -= 1
			if _out[j] == 0 and _state[j] == OUTER:
				_unsettle(j)
	_out[i] = _ways_out(i)


## Open neighbours of cell `i` the cloud hasn't claimed.
func _ways_out(i: int) -> int:
	var n := 0
	for k in 6:
		var j := _nb[i * 6 + k]
		if j >= 0 and _slot[j] < 0:
			n += 1
	return n


## Opens the way from claimed cell `i` to its neighbours (rays for pairs not tested yet) and
## offers each it reaches to the flood.
func _spread_from(i: int) -> void:
	for k in 6:
		var j := _nb[i * 6 + k]
		if j == -2:
			continue
		if j == -1:
			j = _link(i, k)
			if j < 0:
				continue
		if _slot[j] >= 0:
			continue
		var g := _g[i] + _step_cost[k]
		if g < _g[j]:
			_g[j] = g
			_push(j, maxi(g + _base[j], 0))


## Tests the pair from cell `i` in direction `k`: the neighbour's number, or -2 (closed).
func _link(i: int, k: int) -> int:
	var d := DIRS[k]
	var x := _cx[i] + d.x
	var y := _cy[i] + d.y
	var z := _cz[i] + d.z
	if not _in_reach(x, y, z):
		_nb[i * 6 + k] = -2
		return -2
	var key := _pack(x, y, z)
	var j: int = _index.get(key, -1)
	var edge := (_pack(_cx[i], _cy[i], _cz[i]) * 4 + k / 2) if k % 2 == 0 else (key * 4 + k / 2)
	var open: Variant = _edges.get(edge)
	if open == null:
		_ray.from = _origin + Vector3(_cx[i], _cy[i], _cz[i]) * CELL
		_ray.to = _origin + Vector3(x, y, z) * CELL
		open = _space.intersect_ray(_ray).is_empty()
		rays += 1
		_edges[edge] = open
	if not open:
		_nb[i * 6 + k] = -2
		if j >= 0:
			_nb[j * 6 + (k ^ 1)] = -2
		return -2
	if j < 0:
		if _cx.size() >= MAX_FOUND:
			return -2  # (not kept: the pair is open, the cloud just can't take more)
		j = _found(Vector3i(x, y, z))
	_nb[i * 6 + k] = j
	_nb[j * 6 + (k ^ 1)] = i
	return j


## Settled cell `i` changes on its own again (from what it was), or a gone one comes back.
func _unsettle(i: int) -> void:
	if _state[i] == MOVING:
		return
	_d[i] = _density(i)
	_state[i] = MOVING
	_at[i] = _moving.size()
	_moving.append(i)
	var o := _slot[i] * 16
	_buf[o + 12] = _d[i] * (1.0 / FULL)
	_buf[o + 13] = _buf[o + 12]
	_buf[o + 15] = 0.0


## Takes moving cell `i` (at `n` in the moving list) out of it, as `state`.
func _settle(i: int, n: int, state: int) -> void:
	var last := _moving[_moving.size() - 1]
	_moving[n] = last
	_at[last] = n
	_moving.resize(_moving.size() - 1)
	_at[i] = -1
	_state[i] = state
	_buf[_slot[i] * 16 + 15] = float(state)


## Cells further upwind than this (cells) thin at step `s` (INF: none).
func drift_line(s: int) -> float:
	var t := float(s) / HZ
	if _wind_speed <= 0.05 or t <= EMIT_S:
		return INF
	return DRIFT_START_CELLS - _wind_speed * DRIFT_X / CELL * (t - EMIT_S)


func _step() -> void:
	step += 1
	for event: Array in events:
		var due := int(event[0])
		if due == step:
			if int(event[1]) == BLAST:
				_blast(event[2], (event[3] as Vector3).x)
			else:
				_shot(event[2], event[3])
		elif int(event[1]) == BLAST and due + RELINK_STEPS == step:
			_relink(event[2], (event[3] as Vector3).y + CELL * 2.0)
	var want := volume_at(step)
	var n := 0
	while _claimed.size() < want and n < MAX_CLAIM_PER_STEP:
		var c := _pop()
		if c < 0:
			break
		_claim(c)
		n += 1
	# The drift reaches more cells (a cell within a cell of its line stops settling).
	var line := drift_line(step)
	while _drifted < _by_upw.size() and -_upw_keys[_drifted] - line > -1.0:
		_unsettle(_by_upw[_drifted])
		_drifted += 1
	var target := target_at(step)
	var outer := (target * RIM) >> 8
	_core_was = _core
	_rim_was = _rim
	_core = _ease(_core, target)
	_rim = _ease(_rim, outer)
	var m := _moving.size() - 1
	while m >= 0:
		var i := _moving[m]
		var rim := _out[i] > 0
		var t := outer if rim else target
		var u := _upw[i] - line
		var h := _hole[i]
		if u > 0.0:
			t = (t * maxi(0, 256 - int(u * 128.0))) >> 8
		if h > 0:
			t = (t * maxi(0, 256 - h)) >> 8
			_hole[i] = maxi(0, h - HOLE_REFILL)
		var d := _d[i]
		var nd := _ease(d, t)
		var o := _slot[i] * 16
		if h <= HOLE_REFILL and u <= -1.0:
			var body := _rim if rim else _core
			if absi(nd - body) <= SETTLE:
				_settle(i, m, OUTER if rim else CORE)
				m -= 1
				continue
		elif nd <= 0 and t <= 0 and u > 0.0:
			_d[i] = 0
			_settle(i, m, GONE)
			m -= 1
			continue
		_d[i] = nd
		_buf[o + 12] = d * (1.0 / FULL)
		_buf[o + 13] = nd * (1.0 / FULL)
		m -= 1
	_drawn = false


func _upload() -> void:
	if _drawn or _mm == null:
		return
	_drawn = true
	_mm.visible_instance_count = _claimed.size()
	_mm.buffer = _buf
	_mat.set_shader_parameter(&"core", Vector2(_core_was, _core) * (1.0 / FULL))
	_mat.set_shader_parameter(&"rim", Vector2(_rim_was, _rim) * (1.0 / FULL))


func _blast(pos: Vector3, push_m: float) -> void:
	var r2 := push_m * push_m
	for i in _claimed:
		var at := _origin + Vector3(_cx[i], _cy[i], _cz[i]) * CELL
		var d2 := at.distance_squared_to(pos)
		if d2 < r2:
			var h := int(HOLE_MAX * (1.0 - d2 / r2))
			_unsettle(i)
			_hole[i] = maxi(_hole[i], h)
			_d[i] = (_d[i] * maxi(0, 256 - h)) >> 8


## The pairs round a blast (within `within_m`) are tested again: what was closed may be open now.
func _relink(pos: Vector3, within_m: float) -> void:
	var r2 := within_m * within_m
	var again: Array[int] = []
	for i in _cx.size():
		var at := _origin + Vector3(_cx[i], _cy[i], _cz[i]) * CELL
		if at.distance_squared_to(pos) > r2:
			continue
		for k in 6:
			if _nb[i * 6 + k] == -2:
				_nb[i * 6 + k] = -1
				var d := DIRS[k]
				var key := _pack(_cx[i] + d.x, _cy[i] + d.y, _cz[i] + d.z)
				_edges.erase((_pack(_cx[i], _cy[i], _cz[i]) * 4 + k / 2) if k % 2 == 0 else (key * 4 + k / 2))
		if _slot[i] >= 0:
			again.append(i)
	for i in again:
		_spread_from(i)
	for i in again:
		_out[i] = _ways_out(i)
		if _out[i] > 0 and _state[i] == CORE:
			_unsettle(i)


func _shot(from: Vector3, to: Vector3) -> void:
	for i in _cells_on(from, to):
		_unsettle(i)
		_hole[i] = maxi(_hole[i], SHOT_HOLE)
		_d[i] = (_d[i] * maxi(0, 256 - SHOT_HOLE)) >> 8


## The claimed cells the line from `from` to `to` goes through.
func _cells_on(from: Vector3, to: Vector3) -> Array[int]:
	var out: Array[int] = []
	_walk(from, to, INF, out, true)
	return out


## The smoke's optical depth along the line from `from` to `to` through this cloud (stops once
## it reaches `enough`).
func depth_along(from: Vector3, to: Vector3, enough := INF) -> float:
	if not _started or _claimed.is_empty():
		return 0.0
	return _walk(from, to, enough, _no_cells, false)


## Walks the line from `from` to `to` through the claimed cells' box, cell by cell (a 3D DDA):
## the optical depth of the smoke along it (stopping once it reaches `enough`), and with
## `collect` each claimed cell it crosses into `cells`.
func _walk(from: Vector3, to: Vector3, enough: float, cells: Array[int], collect: bool) -> float:
	if _claimed.is_empty():
		return 0.0
	var a := (from - _origin) / CELL + Vector3(0.5, 0.5, 0.5)
	var b := (to - _origin) / CELL + Vector3(0.5, 0.5, 0.5)
	var dir := b - a
	var t0 := 0.0
	var t1 := 1.0
	for ax in 3:
		var lo := float(_lo[ax])
		var hi := float(_hi[ax] + 1)
		if absf(dir[ax]) < 1e-9:
			if a[ax] < lo or a[ax] > hi:
				return 0.0
			continue
		var ta := (lo - a[ax]) / dir[ax]
		var tb := (hi - a[ax]) / dir[ax]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return 0.0
	var k := SIGMA_M * from.distance_to(to) / FULL
	var p := a + dir * t0
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z)).clamp(_lo, _hi)
	var step_by := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for ax in 3:
		if dir[ax] > 0.0:
			step_by[ax] = 1
			t_max[ax] = (cell[ax] + 1 - a[ax]) / dir[ax]
			t_delta[ax] = 1.0 / dir[ax]
		elif dir[ax] < 0.0:
			step_by[ax] = -1
			t_max[ax] = (cell[ax] - a[ax]) / dir[ax]
			t_delta[ax] = -1.0 / dir[ax]
	var depth := 0.0
	var t := t0
	while t < t1:
		var next := minf(minf(t_max.x, t_max.y), minf(t_max.z, t1))
		var i: int = _index.get(_pack(cell.x, cell.y, cell.z), -1)
		if i >= 0 and _slot[i] >= 0 and next > t:
			depth += _density(i) * k * (next - t)
			if collect:
				cells.append(i)
			elif depth >= enough:
				return depth
		t = next
		if t >= t1:
			break
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			cell.x += step_by.x
			t_max.x += t_delta.x
		elif t_max.y <= t_max.z:
			cell.y += step_by.y
			t_max.y += t_delta.y
		else:
			cell.z += step_by.z
			t_max.z += t_delta.z
		if cell.x < _lo.x or cell.x > _hi.x or cell.y < _lo.y or cell.y > _hi.y or cell.z < _lo.z or cell.z > _hi.z:
			break
	return depth
