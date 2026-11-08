class_name RoadDead
extends RefCounted
## Roads as a place the dead gather (docs/survival_world.md section 5, "Roads"): some of a zone's
## crowd (ZoneDead, SHARE of it) drift to the nearest road and linger on it, thickest on the
## asphalt, near towns and round the hulks left on it, so walking the road means walking past them
## while the open country stays nearly empty (FirstHour). A head never picks a road by itself per
## frame: the crowd's own wait-between-moves (ZoneDead._physics_process) calls idle_target, and the
## anchors are built once when the zone comes up. Heads count against ZoneDead.CAP and bodies against
## Survival.LIVE_CAP like any other. Host only. Every number here is Proposed.

## How much a road of each kind draws (the bigger the road the more walk it).
const ROAD_X := {"asphalt": 1.0, "street": 0.85, "dirt": 0.45}
## A lingering spot every this many metres of road; the anchors' grid.
const ANCHOR_M := 40.0
const CELL_M := 64.0
## Near a town or village (metres) the draw rises, up to this extra at its edge.
const TOWN_M := 350.0
const TOWN_X := {"town": 1.0, "village": 0.5}
## Round a hulk on the road (hulks_of: the scatter's) the draw is this many times the road's.
const WRECK_M := 30.0
const WRECK_X := 2.5
## Share of the crowd that takes to the road, how far a head looks for one, and how far it shuffles
## about its spot along the road.
const SHARE := 0.4
const REACH_M := 180.0
const LINGER_M := 9.0
const STEP_M := 12.0
## Heads a spot holds at weight 1 (plus 2); seeded heads per anchor at weight 1, the most seeded a
## zone, and the room kept under ZoneDead.CAP for a horde.
const CAP_PER_WEIGHT := 4.0
const SEED_PER_ANCHOR := 0.5
const SEED_MAX := 100
const SEED_ROOM := 90
## No anchors on the start farm's own stretch (FirstHour's quiet start).
const START_CLEAR_M := 260.0
## The once-a-world journal line: heads this close to a player standing on a road, this many.
const TELL_M := 90.0
const TELL_N := 2

var anchors := PackedVector2Array()
var weights := PackedFloat32Array()
var along := PackedVector2Array()  # the road's direction at each anchor
var used := PackedInt32Array()  # how many heads took each one
var _cells := {}  # Vector2i -> Array[int]


## Host, the level up (Survival.server_level_ready): the zone's anchors, its crowd told who takes to
## the road, and the road's own dead seeded. Once a level.
static func server_level_ready(level: SurvivalLevel) -> void:
	var crowd := ZoneDead.of(level)
	if crowd == null or crowd.roads != null:
		return
	var rd := build(level)
	if rd == null:
		return
	crowd.roads = rd
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(Survival.state().get("zone", "")) + "|roads")
	for d: Dictionary in crowd.dead:
		if not bool(d.get("horde", false)) and not d.has("nest") and rng.randf() < SHARE:
			d.road_on = true
	var seeded := rd.seed_heads(level, crowd, rng)
	SessionLog.note("survival: roads: %d anchors, %d of the dead seeded on them" % [rd.anchors.size(), seeded])


## The zone's road anchors, or null when it has no roads.
static func build(level: ZoneLevel) -> RoadDead:
	var zr := ZoneRoads.of(level)
	if zr == null or zr.net == null:
		return null
	var hulks := hulks_of(level.scatter.items) if level.scatter else PackedVector2Array()
	var sites: Array = []
	for m: ZoneModule in level.modules():
		var base := ZoneModules.base(String(m.type))
		if m.module_id == FirstHour.HOME_ID:
			sites.append([Vector2(m.global_position.x, m.global_position.z), "home"])
		elif TOWN_X.has(base):
			sites.append([Vector2(m.global_position.x, m.global_position.z), base])
	var rd := RoadDead.new()
	for seg: Dictionary in zr.segments():
		var x := float(ROAD_X.get(String(seg.kind), 0.3))
		var pts: PackedVector3Array = seg.points
		var drawn: PackedByteArray = seg.drawn
		var run := 0.0
		for k in range(1, pts.size()):
			var a := pts[k - 1]
			var b := pts[k]
			run += Vector2(b.x - a.x, b.z - a.z).length()
			if run < ANCHOR_M or drawn[k] == 0:
				continue
			run = 0.0
			var at := Vector2(b.x, b.z)
			var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
			rd._add(at, dir, x, sites, hulks)
	return rd


## The burnt-out hulks among the scatter's `items` (x, z): any near a road is one to gather at.
static func hulks_of(items: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item: Dictionary in items:
		if item.has("shape") and String(item.shape).begins_with("hulk"):
			out.append(Vector2((item.pos as Vector3).x, (item.pos as Vector3).z))
	return out


func _add(at: Vector2, dir: Vector2, x: float, sites: Array, hulks: PackedVector2Array) -> void:
	var town := 0.0
	for s: Array in sites:
		var d := (s[0] as Vector2).distance_to(at)
		if String(s[1]) == "home":
			if d < START_CLEAR_M:
				return
		elif d < TOWN_M:
			town = maxf(town, float(TOWN_X[String(s[1])]) * (1.0 - d / TOWN_M))
	if FirstHour.in_quiet(at):
		return
	var w := x * (1.0 + town)
	for h: Vector2 in hulks:
		if h.distance_to(at) <= WRECK_M:
			w *= WRECK_X
			break
	var i := anchors.size()
	anchors.append(at)
	along.append(dir)
	weights.append(w)
	used.append(0)
	var cell := Vector2i(floori(at.x / CELL_M), floori(at.y / CELL_M))
	if not _cells.has(cell):
		_cells[cell] = []
	(_cells[cell] as Array).append(i)


## How many heads spot `i` holds.
func cap_of(i: int) -> int:
	return 2 + roundi(weights[i] * CAP_PER_WEIGHT)


## The best free anchor near `pos` by its weight and how near it is, a little at random; -1 none.
func pick(pos: Vector2, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_score := 0.0
	var c := Vector2i(floori(pos.x / CELL_M), floori(pos.y / CELL_M))
	var r := ceili(REACH_M / CELL_M)
	for cx in range(c.x - r, c.x + r + 1):
		for cy in range(c.y - r, c.y + r + 1):
			var ids: Array = _cells.get(Vector2i(cx, cy), [])
			for i: int in ids:
				if used[i] >= cap_of(i):
					continue
				var d := anchors[i].distance_to(pos)
				if d > REACH_M:
					continue
				var score := weights[i] / (1.0 + d / 60.0) * rng.randf_range(0.5, 1.5)
				if score > best_score:
					best_score = score
					best = i
	return best


## The next place head `d` at `pos` walks to on its way to its spot, or lingering on it; Vector2.INF
## when there's no road for it (it's let off the road and wanders as before).
func idle_target(d: Dictionary, pos: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var i := int(d.get("anchor", -1))
	if i < 0 or i >= anchors.size():
		i = pick(pos, rng)
		if i < 0:
			d.erase("road_on")
			return Vector2.INF
		d.anchor = i
		used[i] += 1
	var to := anchors[i] + along[i] * rng.randf_range(-LINGER_M, LINGER_M) + along[i].orthogonal() * rng.randf_range(-2.0, 2.0)
	var dist := pos.distance_to(to)
	return pos + (to - pos) / dist * minf(STEP_M, dist) if dist > 0.5 else to


## A head left the crowd: its spot is free again.
func release(d: Dictionary) -> void:
	var i := int(d.get("anchor", -1))
	if i >= 0 and i < used.size():
		used[i] = maxi(0, used[i] - 1)


## The road's own dead (Proposed): anchors' weights' worth, by the days (FirstHour.open_pace), the
## months (DeadDecay) and what's been killed there (Survival.thinned), up to SEED_MAX and with room
## left for a horde. Returns how many.
func seed_heads(level: SurvivalLevel, crowd: ZoneDead, rng: RandomNumberGenerator) -> int:
	var made := 0
	var room := mini(SEED_MAX, ZoneDead.CAP - SEED_ROOM - crowd.dead.size())
	var pace := FirstHour.open_pace() * DeadDecay.count_mult()
	var order: Array[int] = []  # (a seeded shuffle: when the room runs out it isn't the later roads that go empty)
	for i in anchors.size():
		order.append(i)
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t := order[k]
		order[k] = order[j]
		order[j] = t
	for i: int in order:
		if made >= room:
			break
		var at := Vector3(anchors[i].x, 0.0, anchors[i].y)
		var want := SEED_PER_ANCHOR * weights[i] * pace * (1.0 - Survival.thinned(at))
		var n := floori(want) + (1 if rng.randf() < fmod(want, 1.0) else 0)
		for k in mini(n, cap_of(i)):
			if made >= room:
				break
			var p := anchors[i] + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			var g := level.ground_point(Vector3(p.x, 0.0, p.y))
			if crowd.server_add(g, Survival.roll_kind(level, g, rng)):
				var d: Dictionary = crowd.dead[crowd.dead.size() - 1]
				d.road_on = true
				d.anchor = i
				used[i] += 1
				made += 1
	return made


## Host, the crowd's convert tick: the first time a player stands on a road with the dead strung out
## along it, the journal says so (once a world). Reads for the player what the far shapes on the road
## already show.
static func server_tell(level: Node, crowd: ZoneDead) -> void:
	if bool(Survival.state().get("roads_told", false)):
		return
	var zr := ZoneRoads.of(level)
	if zr == null:
		return
	for p: Soldier in MapNodes.players(level):
		if not p.vitals.is_up() or zr.distance_to(p.global_position.x, p.global_position.z) > 1.0:
			continue
		var me := Vector2(p.global_position.x, p.global_position.z)
		var near := 0
		for d: Dictionary in crowd.dead:
			if bool(d.alive) and d.has("anchor") and (d.pos as Vector2).distance_to(me) <= TELL_M:
				near += 1
		if near >= TELL_N:
			Survival.state()["roads_told"] = true
			Survival._journal_line("The dead keep to the roads. The fields are slower going, but they're empty.")
			for q: Soldier in MapNodes.players(level):
				Survival._tell(q, "The dead keep to the roads. The fields are emptier")
			return
