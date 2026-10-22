class_name RoadNet
extends RefCounted
## A zone's road network (cg_brief queue item 1.2, Roads), planned from its definition on its
## generated terrain, the same on every peer: ZoneRoads lays it (meshes and collision) and is
## the public face (ZoneRoads.segments() and the rest).
##
## What it plans from: the def's "roads" as ZoneDef made them ([[x, z], [x, z]] links: site to
## site, and the cross-country trails as chains of jittered points), its modules (the sites) and
## its "crossings" (RegionMap: the ways into the linked zones). It keeps the links as they came in
## "road_links" (and "patrol_links"), so planning again (a client, a reload) gives the same roads.
##
## How:
## - Ways: the links chained into ways (site to site, trail end to trail end). A way's kind
##   (data/roads.json): asphalt between the main sites (towns, the HQ, checkpoints...), dirt
##   tracks to farms, compounds and villages and on the trails.
## - Ends: a way leaves a site's pad straight out of its side (a town by the mouth of the street
##   that faces the way, a checkpoint east or west, along its road); a second way leaving a site
##   the same way joins the first further out (a T junction) instead of running beside it.
## - Route: control points every CTRL_M, nudged sideways (SNAKE_STEPS) to the cheapest line:
##   length, climb (grade past GRADE_REF costs), bends (none past MAX_BEND_DEG), off the pads,
##   the water and the zone's edge; then a centripetal Catmull-Rom curve through them, sampled
##   every SAMPLE_M. So the roads curve round hills and follow the valleys.
## - Junctions: where two ways cross (X), where a way joins another (T), where the links met
##   (a node). Near a town (or where four asphalt arms meet) a junction is a roundabout.
## - Crossings: each crossing gets a road from the zone's edge, straight in through the crossing
##   point, on to the nearest road. Its kind comes from the link's two zone ids, so the road that
##   leaves one zone is the same kind and width as the one that enters the next, at its crossing.
## - Every site is on the network (_complete_links), a trail's loose end near a road joins it, and
##   routes keep off the roads already laid (NEAR_COST): roads cross, they don't run alongside.
## - Water: the zone's water plans its bridges, fords and culverts over the links the roads take
##   (water_links, from ZoneTerrain.generate), and each way runs straight through the ones on its
##   links (_anchors: fixed control points, ALIGN_M lined up before them). A later way that would
##   take a crossing an earlier road already has joins that road either side of it (two Ts).
## - Profile: each road's height is the ground along it smoothed over SMOOTH_M (at most CUT_MAX_M
##   off it), solved as a stretched string (_solve, PROFILE_LAMBDA_M) through its pins: flat at its
##   junctions (whose heights are eased so the ramps between them and the pads stay under
##   JUNCTION_RAMP; close ones share one), level with the pads it leaves or passes, drawn toward the
##   roads beside it. Over a bridge it rides the deck and its ramps (pinned to them, not laid or
##   graded there: the deck is the road, F-175); other water (where ZoneTerrain.water_height
##   stands over the ground: a ford, a stream no link crosses) is left out of the targets and not
##   laid (water_crossings() lists the spans).
## - Grade: the terrain is cut and filled to the road: under the road SINK_M below it, a shoulder,
##   then banks back to the natural ground (CUT_BANK, FILL_BANK); last, no height point of a cell a
##   road's surface crosses is left above it.
## - The def: "roads" becomes the curved roads as straight pieces (within DEF_TOL_M of the curve:
##   RoadRoute drives them, ZoneScatter keeps trees off them, the map draws them; each piece's
##   third entry is its kind), and the trails' "patrols" follow their curved roads.

const DATA_PATH := "res://data/roads.json"
## Planning (Proposed): the curve's samples (m), control points (m), their sideways jitter (m),
## the straight lead out of a site (m), the snake's sideways steps (m).
const SAMPLE_M := 4.0
const CTRL_M := 80.0
const JITTER_M := 18.0
const LEAD_M := 22.0
const SNAKE_STEPS: Array[float] = [24.0, 9.0]
## The route's costs (Proposed): grade over GRADE_REF costs GRADE_COST x (grade / ref)^2 a metre;
## a bend BEND_COST x angle^2 x the control spacing; a blocked sample (pad, water, edge) BLOCK_COST;
## no bend sharper than MAX_BEND_DEG.
const GRADE_REF := 0.08
const GRADE_COST := 2.0
const BEND_COST := 0.5
const BLOCK_COST := 4000.0
## Running beside a road already laid (within a block cell of it) costs this much a metre more:
## roads cross, they don't run alongside each other.
const NEAR_COST := 1.5
const MAX_BEND_DEG := 50.0
## Roads keep this far inside the zone's edge (crossing roads excepted), m.
const EDGE_KEEP_M := 40.0
## The route's blocked cells (pads, water, the edge), m.
const BLOCK_CELL_M := 16.0
## A checkpoint this close to a link's line (m) has the link run through it.
const CHECKPOINT_ON_M := 90.0
## A second way leaving a site within MERGE_DEG of a first joins it this far out (m: 30% of its
## length, clamped).
const MERGE_DEG := 32.0
const MERGE_OUT_M := Vector2(60.0, 220.0)
## Profile (Proposed): smoothing window either side (m), the most it cuts or fills (m), flat round
## a junction (m) and the blend back to the profile from a pinned height (m).
const SMOOTH_M := 20.0
const CUT_MAX_M := 3.0
const JUNCTION_FLAT_M := 14.0
## A road is level with the pad it leaves for this far out (m: a cell, so no terrain triangle
## between the pad and the road tilts up through it).
const SITE_FLAT_M := 5.0
## A road this close to a pad's edge past its own (m) is held level with the pad there.
const PAD_BESIDE_M := 4.0
## A trail's loose end this close to another road's edge (m) joins it.
const LOOSE_END_M := 14.0
## Junctions this close together (m) are one cluster, all at one height.
const CLUSTER_M := 30.0
## Junctions on one road: the stretch between their flats is a ramp of at most this (rise per m).
const JUNCTION_RAMP := 0.12
## The profile's stiffness (m): how far a pin's pull reaches along the road (_solve).
const PROFILE_LAMBDA_M := 36.0
## Grading (Proposed): the ground under the road stands SINK_M below its surface; level with it
## FILL_FLAT_M past the edge on the low side and FLAT_EXTRA_M on the high (one cell's diagonal and a
## bit, so no terrain triangle rises through the road's edge), then banks of CUT_BANK (rise per m)
## up and FILL_BANK down, out to GRADE_REACH_M past the edge.
const SINK_M := 0.10
const FILL_FLAT_M := 3.0
const FLAT_EXTRA_M := 6.0
const CUT_BANK := 0.45
const FILL_BANK := 0.45
const GRADE_REACH_M := 13.0
## Roads passing close by each other: held level within this of the other's edge (m), blending
## back over this (m), drawn that hard (_beside).
const NEAR_EXTRA_M := 4.0
const NEAR_BLEND_M := 12.0
const BESIDE_WEIGHT := 20.0
## Crossing roads stop this far inside the edge wall (m).
const EDGE_GAP_M := 3.0
## The def's straight pieces: within this of the curve (m), at most this long (m).
const DEF_TOL_M := 1.0
const DEF_MAX_SEG_M := 80.0
## The query grid (m) and a roundabout ring's sides in the def (RoadRoute drives round them).
const GRID_M := 32.0
const RING_SIDES := 12
## A road keeps straight this far (m) past a bridge's ramps, or either side of a ford or culvert.
const BRIDGE_LEAD_M := 4.0
const FORD_LEAD_M := 10.0
## And lines up this far before that (m): the curve settles straight before the bridge.
const ALIGN_M := 12.0
## A link passing this close (m) to another link's way across, the same way, takes it too.
const SHARE_CROSSING_M := 30.0
## Bumped when the planning changes: part of every road's def entry, so a stale cache is seen.
const VERSION := 1

static var _data := {}

var roads: Array[Dictionary] = []
var junctions: Array[Dictionary] = []
var towns: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var plan_ms := 0.0
var grade_ms := 0.0
## Each step's time (ms), for the costs.
var timings := {}
var _lap := 0
## The water's ways across (terrain.water: ZoneWater.crossings) on the links, for the routes to take:
## [{"link", "pos", "dir", "half" (m either side the road keeps straight)}]; and the bridges' boxes
## (the deck and its ramps: the road isn't laid there, it rides the deck): [{"centre", "along",
## "half_len", "half_w", "top", "ramps"}].
var _water_ways: Array = []
var _bridge_boxes: Array = []
## Where the crossing roads' links start in the water's links (water_links).
var _crossing_link_base := 0
var _gd := PackedFloat32Array()  # grading: per height point, how far past the nearest road's edge (m)
var _gy := PackedFloat32Array()  # and that road's height there
var _touched := PackedInt32Array()
var graded_vertices := 0

var _t: ZoneTerrain
var _def: Dictionary
var _half := 0.0
var _sites: Array[Dictionary] = []
var _pads: Array[Rect2] = []
var _blocked := PackedByteArray()
var _near := PackedByteArray()
var _hs := PackedFloat32Array()
var _beside_mask := PackedByteArray()  # per block cell: 1 within two cells of a road whose profile is done  # the terrain's heights while routing (_hq)  # per blocked cell: 1 within a cell of a road laid already (_leg_cost keeps off)
var _block_n := 0
var _rng := RandomNumberGenerator.new()
var _grid := {}  # Vector2i -> Array of [road index, sample index] (segment from that sample)
var _way_of_trail := {}  # road index -> the trail's original points (patrol matching)
var _trail_parts := {}  # a split trail's first road index -> its roads in order
## The water's ways across a road already takes: _water_ways index -> that road's index.
var _taken := {}


# --- Data ------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {"kinds": {}}
	return _data


## Kind `id`'s data (data/roads.json "kinds"), dirt's if unknown.
static func kind(id: String) -> Dictionary:
	var kinds: Dictionary = data().get("kinds", {})
	return kinds.get(id, kinds.get("dirt", {"width_m": 4.0}))


static func half_width(id: String) -> float:
	return float(kind(id).get("width_m", 4.0)) * 0.5


## The kind of a road out of the crossing between zones `a` and `b`: the same seen from either.
static func crossing_kind(a: String, b: String) -> String:
	var key := a + "|" + b if a < b else b + "|" + a
	var roll := float(posmod(key.hash(), 1000)) / 1000.0
	return "asphalt" if roll < float((data().get("crossings", {}) as Dictionary).get("asphalt_share", 0.6)) else "dirt"


# --- Planning --------------------------------------------------------------------------------

## `def` as ZoneDef made it, before planning wrote its roads in (a copy): "roads" and "patrols"
## back to the links, the planner's own keys gone. For comparing a hosted zone's def with a fresh one.
static func unplanned(def: Dictionary) -> Dictionary:
	var out := def.duplicate(true)
	if out.has("road_links"):
		out["roads"] = out.road_links
		if (out.road_links as Array).is_empty():
			out.erase("roads")  # (a def with no links has no "roads" until planned)
		if out.has("patrols"):
			out["patrols"] = out.get("patrol_links", [])
	out.erase("road_links")
	out.erase("patrol_links")
	out.erase("roads_version")
	return out

## The links the zone's water plans its bridges, fords and culverts over (ZoneTerrain.generate
## hands them to ZoneWater.carve as the def's "roads"): the def's links
## completed (_complete_links: every site joined), then for each crossing two: the zone's edge to the
## crossing point, the crossing point to the nearest site. The planned roads take those ways across
## (the routes pass through them), so the bridges stand on the roads. The same on every peer.
static func water_links(def: Dictionary) -> Array:
	var net := RoadNet.new()
	net._def = def
	net._half = float(def.get("size_m", 2048.0)) * 0.5
	net._read_sites()
	var links: Array = net._complete_links(def.get("road_links", def.get("roads", [])))
	for c: Dictionary in def.get("crossings", []):
		links.append_array(net._crossing_links(c))
	return links


## Crossing `c`'s two water links: [edge, crossing point], [crossing point, the nearest site].
func _crossing_links(c: Dictionary) -> Array:
	var side := int(c.get("side", 0))
	var p := Vector2(float(c.pos[0]), float(c.pos[1]))
	var gap := _half - EDGE_GAP_M
	var edge: Vector2 = [Vector2(p.x, -gap), Vector2(p.x, gap), Vector2(-gap, p.y), Vector2(gap, p.y)][side]
	var to := p
	for site: Dictionary in _sites:
		if to == p or (site.pos as Vector2).distance_to(p) < to.distance_to(p):
			to = site.pos
	return [[[edge.x, edge.y], [p.x, p.y]], [[p.x, p.y], [to.x, to.y]]]


## The network for `def` on `terrain` (generated, before its collision): plans it, cuts and fills
## the terrain to it, and writes the def's "roads" (and the trails' "patrols").
static func plan(def: Dictionary, terrain: ZoneTerrain) -> RoadNet:
	var net := RoadNet.new()
	net._plan(def, terrain)
	return net


func _plan(def: Dictionary, terrain: ZoneTerrain) -> void:
	var started := Time.get_ticks_usec()
	_t = terrain
	_def = def
	_half = terrain.size_m * 0.5
	_rng.seed = int(def.get("seed", 0)) ^ 0x60AD
	if not def.has("road_links"):
		def["road_links"] = (def.get("roads", []) as Array).duplicate(true)
		def["patrol_links"] = (def.get("patrols", []) as Array).duplicate(true)
	for pad: Array in terrain.pads:
		_pads.append(pad[0])
	_hs = terrain.heights  # (shared, read only: routing's heights)
	_read_sites()
	_build_blocked()
	_lap = Time.get_ticks_usec()
	var completed := _complete_links(def.get("road_links", []))
	_crossing_link_base = completed.size()
	_read_water()
	var ways := _ways(completed)
	# Main roads first (their ends are where later ones join), longer before shorter.
	ways.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (String(a.kind) == "asphalt") != (String(b.kind) == "asphalt"):
			return String(a.kind) == "asphalt"
		return float(a.length) > float(b.length))
	_tick("ways")
	for w in ways:
		_route_way(w)
	var crossings: Array = def.get("crossings", [])
	for i in crossings.size():
		_route_crossing(crossings[i], i)
	_tick("route")
	_hs = PackedFloat32Array()
	_snap_loose_ends()
	_cross_points()
	_choose_roundabouts()
	_tick("junctions")
	_profiles()
	_tick("profiles")
	plan_ms = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	_grade()
	grade_ms = (Time.get_ticks_usec() - started) / 1000.0
	_lap = Time.get_ticks_usec()
	_index()
	_write_def(def)
	_tick("def")


func _tick(what: String) -> void:
	timings[what] = float(timings.get(what, 0.0)) + (Time.get_ticks_usec() - _lap) / 1000.0
	_lap = Time.get_ticks_usec()


## The modules as sites: id, type, base type, centre, half size and pad (grown as ZoneTerrain's).
func _read_sites() -> void:
	for m: Dictionary in _def.get("modules", []):
		var type := String(m.type)
		if type.begins_with("fob_"):
			continue  # a base's bought defence (BaseFob): part of the FOB, not a site of its own
		ZoneModules.has_type(type)  # (a generated town fills in its HALF entry)
		var half: Vector2 = ZoneModules.HALF.get(type, Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		var pad := Rect2(p - half, half * 2.0).grow(ZoneTerrain.PAD_MARGIN_M)
		var site := {"id": String(m.id), "type": type, "base": ZoneModules.base(type), "pos": p, "half": half, "pad": pad, "y": _t.height_at(p.x, p.y) if _t else 0.0}
		_sites.append(site)
		if String(site.base) == "town":
			towns.append({"id": site.id, "pos": p, "half": half, "y": site.y, "pad": pad})


## The water's ways across the links (bridges, fords, culverts) and the bridges' boxes.
func _read_water() -> void:
	var water: Variant = _t.get(&"water")
	if water == null:
		return
	var by_id := {}
	var bridges: Variant = water.get(&"bridges")
	if bridges != null:
		for b: Dictionary in bridges.get(&"bridges"):
			by_id[String(b.id)] = b
			var xf: Transform3D = b.xform
			var along := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
			var spec: Dictionary = ZoneBridges.TYPES.get(String(b.type), {})
			_bridge_boxes.append({"centre": Vector2(xf.origin.x, xf.origin.z), "along": along, "half_len": float(b.length) * 0.5,
				"half_w": float(spec.get("deck_w", 7.0)) * 0.5 + 0.5, "top": xf.origin.y, "ramps": b.get("ramps", [])})
	for c: Dictionary in water.get(&"crossings"):
		if int(c.get("road", -1)) < 0:
			continue
		var half := FORD_LEAD_M
		var dir: Vector2 = c.dir
		if by_id.has(String(c.id)):
			var b: Dictionary = by_id[String(c.id)]
			var xf: Transform3D = b.xform
			dir = Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
			half = float(b.length) * 0.5 + ZoneBridges.RAMP_M + BRIDGE_LEAD_M
		_water_ways.append({"link": int(c.road), "pos": c.pos, "dir": dir, "half": half})


## The fixed points a way along `chain` (its links `links`, one a segment) passes to take the
## water's ways across: per segment k, [[t along it, point, _water_ways index], ...] in order
## (four per way across: lined up, onto it, off it, lined up). A way across on the
## segment's own link, or on another link's near it and the same way (the water keeps one crossing
## where two links cross close together: both roads take it).
func _anchors(chain: Array[Vector2], links: Array) -> Dictionary:
	var out := {}
	var arc: Array[float] = [0.0]  # the chain's length up to each node
	for k in range(1, chain.size()):
		arc.append(arc[k - 1] + chain[k - 1].distance_to(chain[k]))
	for wi in _water_ways.size():
		var ww: Dictionary = _water_ways[wi]
		var pos: Vector2 = ww.pos
		var best_k := -1
		var best_d := INF
		for k in chain.size() - 1:
			var seg := chain[k + 1] - chain[k]
			var d := Geometry2D.get_closest_point_to_segment(pos, chain[k], chain[k + 1]).distance_to(pos)
			var own := k < links.size() and int(links[k]) == int(ww.link)
			if d < best_d and ((own and d <= 5.0) or (d <= SHARE_CROSSING_M and absf((ww.dir as Vector2).dot(seg.normalized())) >= 0.7)):
				best_d = d
				best_k = k
		if best_k < 0:
			continue
		var a := chain[best_k]
		var seg := chain[best_k + 1] - a
		var length := seg.length()
		var t := clampf((pos - a).dot(seg) / maxf(length * length, 0.01), 0.0, 1.0)
		var reach := float(ww.half) + ALIGN_M
		var at := arc[best_k] + t * length
		if at < reach + LEAD_M or arc.back() - at < reach + LEAD_M:
			continue  # (too near the way's ends to keep straight: its nodes between are free, passed by)
		var dir: Vector2 = ww.dir
		if dir.dot(seg) < 0.0:
			dir = -dir
		if not out.has(best_k):
			out[best_k] = []
		for d: float in [-reach, -float(ww.half), float(ww.half), reach]:
			out[best_k].append([t + d / length, pos + dir * d, wi])
	for k: int in out:
		(out[k] as Array).sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
	return out


## The route's blocked cells: pads (grown a little) now; water and the band along the edge as
## the route asks (_is_blocked: 255 not looked at yet).
func _build_blocked() -> void:
	_block_n = ceili(_t.size_m / BLOCK_CELL_M)
	_blocked.resize(_block_n * _block_n)
	_blocked.fill(255)
	_near.resize(_block_n * _block_n)
	_near.fill(0)
	for r in _pads:
		var g := r.grow(4.0)
		for j in range(maxi(floori((g.position.y + _half) / BLOCK_CELL_M), 0), mini(ceili((g.end.y + _half) / BLOCK_CELL_M), _block_n)):
			for i in range(maxi(floori((g.position.x + _half) / BLOCK_CELL_M), 0), mini(ceili((g.end.x + _half) / BLOCK_CELL_M), _block_n)):
				_blocked[i + j * _block_n] = 2


func _is_blocked(p: Vector2) -> int:
	var i := floori((p.x + _half) / BLOCK_CELL_M)
	var j := floori((p.y + _half) / BLOCK_CELL_M)
	if i < 0 or j < 0 or i >= _block_n or j >= _block_n:
		return 1
	var b := _blocked[i + j * _block_n]
	if b == 255:
		var x := (i + 0.5) * BLOCK_CELL_M - _half
		var z := (j + 0.5) * BLOCK_CELL_M - _half
		var edge := minf(minf(x + _half, _half - x), minf(z + _half, _half - z))
		b = 1 if edge < EDGE_KEEP_M or _wet(x, z, _t.height_at(x, z)) else 0
		_blocked[i + j * _block_n] = b
	return b


## Water over the ground at (x, z) (the sea; rivers and lakes when the water side's ZoneTerrain
## answers for them in water_height).
func _wet(x: float, z: float, ground: float) -> bool:
	return _t.water_height(x, z) > ground + 0.05


func _site_at(p: Vector2) -> int:
	for i in _sites.size():
		if (_sites[i].pos as Vector2).distance_to(p) < 2.0:
			return i
	return -1


## The def's links, completed: a link that passes a checkpoint goes through it (its road runs
## through the checkpoint), and the links' separate networks are joined, nearest sites first, until
## every site is on one (a hot zone's links only joined the HQ and its outposts; a landmark's link
## to its town can leave the two on their own), so every site is on the roads.
func _complete_links(links: Array) -> Array:
	var out: Array = links.duplicate(true)
	var at := func(p: Array) -> Vector2: return Vector2(float(p[0]), float(p[1]))
	for s in _sites.size():
		if String(_sites[s].base) != "checkpoint":
			continue
		var c: Vector2 = _sites[s].pos
		for li in out.size():
			var a: Vector2 = at.call(out[li][0])
			var b: Vector2 = at.call(out[li][1])
			if a.distance_to(c) < 2.0 or b.distance_to(c) < 2.0:
				continue
			var u := (c - a).dot(b - a) / maxf((b - a).length_squared(), 0.01)
			if u > 0.1 and u < 0.9 and Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < CHECKPOINT_ON_M:
				out.append([[c.x, c.y], out[li][1]])
				out[li] = [out[li][0], [c.x, c.y]]
				break
	# The networks: sites first in `parent`, then the links' other ends.
	var parent: Array[int] = []
	for i in _sites.size():
		parent.append(i)
	var others: Array[Vector2] = []
	for r: Array in out:
		var ends: Array[int] = []
		for p: Array in [r[0], r[1]]:
			var q: Vector2 = at.call(p)
			var s := _site_at(q)
			if s < 0:
				for i in others.size():
					if others[i].distance_to(q) < 2.0:
						s = _sites.size() + i
						break
			if s < 0:
				others.append(q)
				parent.append(parent.size())
				s = parent.size() - 1
			ends.append(s)
		parent[_root(parent, ends[0])] = _root(parent, ends[1])
	while not _sites.is_empty():
		var main := _root(parent, 0)
		var best := Vector2i(-1, -1)
		var best_d := INF
		for i in _sites.size():
			if _root(parent, i) == main:
				continue
			for j in _sites.size():
				if _root(parent, j) != main:
					continue
				var d := (_sites[i].pos as Vector2).distance_to(_sites[j].pos)
				if d < best_d:
					best_d = d
					best = Vector2i(i, j)
		if best.x < 0:
			break
		var pi: Vector2 = _sites[best.x].pos
		var pj: Vector2 = _sites[best.y].pos
		out.append([[pi.x, pi.y], [pj.x, pj.y]])
		parent[_root(parent, best.x)] = main
	return out


static func _root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


## The links as ways: chains between fixed nodes (sites, ends, junctions of the links).
## [{"nodes": Array[Vector2], "a": site index or -1, "b", "kind", "length", "trail"}].
func _ways(links: Array) -> Array[Dictionary]:
	var nodes: Array[Vector2] = []
	var adj := {}
	var link_of := {}  # Vector2i(node, node) -> the link's index
	for li in links.size():
		var r: Array = links[li]
		var a := _node(nodes, Vector2(float(r[0][0]), float(r[0][1])))
		var b := _node(nodes, Vector2(float(r[1][0]), float(r[1][1])))
		if a == b:
			continue
		link_of[Vector2i(mini(a, b), maxi(a, b))] = li
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		if b not in adj[a]:
			adj[a].append(b)
			adj[b].append(a)
	var site := {}
	for n in nodes.size():
		site[n] = _site_at(nodes[n])
	var fixed := func(n: int) -> bool: return int(site[n]) >= 0 or (adj.get(n, []) as Array).size() != 2
	var used := {}
	var chains: Array = []
	var walk := func(start: int, first: int) -> Array:
		var chain: Array[int] = [start, first]
		used[Vector2i(mini(start, first), maxi(start, first))] = true
		while not fixed.call(chain.back()) and chain.size() < 10000:
			var at: int = chain.back()
			var prev: int = chain[chain.size() - 2]
			var next := -1
			for m: int in adj[at]:
				if m != prev and not used.has(Vector2i(mini(at, m), maxi(at, m))):
					next = m
					break
			if next < 0:
				break
			used[Vector2i(mini(at, next), maxi(at, next))] = true
			chain.append(next)
			if next == start:
				break
		return chain
	for n in nodes.size():
		if not fixed.call(n):
			continue
		for m: int in adj.get(n, []):
			if not used.has(Vector2i(mini(n, m), maxi(n, m))):
				chains.append(walk.call(n, m))
	for n in nodes.size():  # loops with no fixed node
		for m: int in adj.get(n, []):
			if not used.has(Vector2i(mini(n, m), maxi(n, m))):
				chains.append(walk.call(n, m))
	var out: Array[Dictionary] = []
	for chain: Array in chains:
		var pts: Array[Vector2] = []
		var chain_links: Array = []
		var length := 0.0
		for k in chain.size():
			pts.append(nodes[chain[k]])
			if k > 0:
				length += pts[k - 1].distance_to(pts[k])
				chain_links.append(int(link_of.get(Vector2i(mini(chain[k - 1], chain[k]), maxi(chain[k - 1], chain[k])), -1)))
		var w := {"nodes": pts, "a": int(site[chain.front()]), "b": int(site[chain.back()]), "length": length,
			"trail": int(site[chain.front()]) < 0 and int(site[chain.back()]) < 0, "links": chain_links}
		w["kind"] = _way_kind(w)
		out.append(w)
	return out


func _node(nodes: Array[Vector2], p: Vector2) -> int:
	for i in nodes.size():
		if nodes[i].distance_to(p) <= 2.0:
			return i
	nodes.append(p)
	return nodes.size() - 1


func _way_kind(w: Dictionary) -> String:
	var d := data()
	if bool(w.trail):
		return String(d.get("trails", "dirt"))
	var hot := String(_def.get("kind", "")) == "hot"
	var best := ""
	for end: int in [int(w.a), int(w.b)]:
		if end < 0:
			continue
		var base := String(_sites[end].base)
		var k := String((d.get("sites", {}) as Dictionary).get(base, d.get("default_hot" if hot else "default", "dirt")))
		if k == "asphalt" or best == "":
			best = k
	return best if best != "" else "dirt"


## Routes way `w` (_ways) and adds it as a road.
func _route_way(w: Dictionary) -> void:
	var nodes: Array[Vector2] = w.nodes
	var ea := _end(int(w.a), nodes[0], nodes[1])
	var eb := _end(int(w.b), nodes[nodes.size() - 1], nodes[nodes.size() - 2])
	# Through the nodes (free), and straight through the water's ways across on its links (fixed).
	# Where an earlier road already takes a way across, this one joins that road either side of
	# it (two Ts) instead of running along it: the way is laid in parts.
	var anchors := _anchors(nodes, w.get("links", []))
	var parts: Array = []  # [[start end or null (ea), [[point, fixed, way across or -1]], end or null (eb)]]
	var part_a: Variant = null
	var items: Array = []
	var shared: Array = []  # per split: [road, near point, far point]
	for k in nodes.size() - 1:
		var list: Array = anchors.get(k, [])
		var g := 0
		while g < list.size():
			var wi := int(list[g][2])
			if _taken.has(wi) and g + 3 < list.size() and int(list[g + 3][2]) == wi:
				shared.append([int(_taken[wi]), list[g][1], list[g + 3][1]])
				parts.append([part_a, items, shared.size() - 1])
				part_a = shared.size() - 1
				items = []
				g += 4
				continue
			items.append([list[g][1], true, wi])
			g += 1
		if k + 1 < nodes.size() - 1 and not _by_crossing(nodes[k + 1], anchors):
			items.append([nodes[k + 1], false, -1])
	parts.append([part_a, items, null])
	var laid: Array[int] = []
	for pi in parts.size():
		var part: Array = parts[pi]
		var its: Array = part[1]
		var a_end := ea
		var b_end := eb
		if part[0] != null:
			var sh: Array = shared[int(part[0])]
			var toward: Vector2 = its[0][0] if not its.is_empty() else (nodes[nodes.size() - 1] if part[2] == null else shared[int(part[2])][1])
			a_end = _join_end(int(sh[0]), _nearest_sample(int(sh[0]), sh[2]), toward)
		if part[2] != null:
			var sh: Array = shared[int(part[2])]
			var toward: Vector2 = its.back()[0] if not its.is_empty() else (a_end.exit as Vector2)
			b_end = _join_end(int(sh[0]), _nearest_sample(int(sh[0]), sh[1]), toward)
		var ctrl: Array[Vector2] = [a_end.exit]
		var fixed: Array[bool] = [true]
		if a_end.has("lead"):
			ctrl.append(a_end.lead)
			fixed.append(true)
		var inner: Array[Vector2] = [ctrl.back()]
		var inner_fixed: Array[bool] = [true]
		for it: Array in its:
			inner.append(it[0])
			inner_fixed.append(bool(it[1]))
		inner.append(b_end.lead if b_end.has("lead") else b_end.exit)
		inner_fixed.append(true)
		_subdivide(inner, ctrl, fixed, inner_fixed)
		if b_end.has("lead"):
			ctrl.append(b_end.lead)
			fixed.append(true)
		ctrl.append(b_end.exit)
		fixed.append(true)
		var road := _add_road(ctrl, fixed, String(w.kind), a_end, b_end)
		laid.append(road)
		for it: Array in its:
			if int(it[2]) >= 0 and not _taken.has(int(it[2])):
				_taken[int(it[2])] = road
	if bool(w.trail):
		_way_of_trail[laid[0]] = nodes
		if laid.size() > 1:
			_trail_parts[laid[0]] = laid


## Whether `p` (a free node of a way) lies by one of the way's ways across (`anchors`): left out,
## the road keeps straight there.
func _by_crossing(p: Vector2, anchors: Dictionary) -> bool:
	for list: Array in anchors.values():
		for an: Array in list:
			var ww: Dictionary = _water_ways[int(an[2])]
			if p.distance_to(ww.pos) < float(ww.half) + ALIGN_M + LEAD_M:
				return true
	return false


## Road `i`'s sample nearest `p`, kept off its ends.
func _nearest_sample(i: int, p: Vector2) -> int:
	var pts: PackedVector2Array = roads[i].pts
	var best := 1
	for k in range(1, pts.size() - 1):
		if pts[k].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = k
	return best


## Appends the control points along `inner` (its first point already in `ctrl`, its last not) to
## `ctrl`, and whether each is fixed to `fixed`: every leg cut into pieces of at most CTRL_M, each
## nudged sideways by up to JITTER_M (free); `inner`'s own points as `inner_fixed` says. A leg
## between two fixed points (over a bridge) stays one straight piece.
func _subdivide(inner: Array[Vector2], ctrl: Array[Vector2], fixed: Array[bool], inner_fixed: Array[bool]) -> void:
	for k in range(1, inner.size()):
		var a := inner[k - 1]
		var b := inner[k]
		var straight := inner_fixed[k - 1] and inner_fixed[k] and k > 1 and k < inner.size() - 1 and a.distance_to(b) <= CTRL_M * 2.0
		var n := 1 if straight else maxi(ceili(a.distance_to(b) / CTRL_M), 1)
		var side := (b - a).orthogonal().normalized()
		for i in range(1, n + 1):
			if k == inner.size() - 1 and i == n:
				break
			var p := a.lerp(b, float(i) / n)
			if i < n:
				p += side * _rng.randf_range(-1.0, 1.0) * JITTER_M
			ctrl.append(p)
			fixed.append(inner_fixed[k] if i == n else false)


## A way's end at site `s` (-1: a plain node at `at`), heading toward `toward`: {"exit" (where the
## drawn road starts), "lead" (a point straight out, when it leaves a pad), "stub" (the def's
## piece from the site's middle to the exit), "site", "join" ([road, sample]: a T onto a road
## already laid)}.
func _end(s: int, at: Vector2, toward: Vector2) -> Dictionary:
	if s < 0:
		return {"exit": at, "stub": PackedVector2Array(), "site": ""}
	var site: Dictionary = _sites[s]
	var c: Vector2 = site.pos
	var pad: Rect2 = site.pad
	var dir := (toward - c).normalized()
	var base := String(site.base)
	var out_dir := Vector2.ZERO
	if base == "town" or base == "checkpoint":
		# Out along the street (a checkpoint: its east-west road): the mouth facing the way.
		var mouths: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0)]
		if base == "town":
			mouths.append_array([Vector2(0, -1), Vector2(0, 1)])
		var best := -INF
		for m in mouths:
			if m.dot(dir) > best:
				best = m.dot(dir)
				out_dir = m
	else:
		# Out of the pad's side the way heads through.
		var h := pad.size * 0.5
		out_dir = Vector2(signf(dir.x), 0) if absf(dir.x) * h.y > absf(dir.y) * h.x else Vector2(0, signf(dir.y))
	var exit := _pad_exit(c, pad, out_dir, dir, base == "town" or base == "checkpoint")
	# A second way out of this site the same way joins the first, further out (a T).
	for i in roads.size():
		var r: Dictionary = roads[i]
		for side: String in ["a", "b"]:
			var e: Dictionary = r[side]
			if String(e.get("site", "")) != String(site.id) or e.has("join"):
				continue
			var other_exit: Vector2 = e.exit
			var same := other_exit.distance_to(exit) < 1.0 if (base == "town" or base == "checkpoint") \
				else absf(rad_to_deg((other_exit - c).angle_to(exit - c))) < MERGE_DEG and absf(rad_to_deg((other_exit - c).angle_to(toward - c))) < MERGE_DEG
			if not same:
				continue
			var pts: PackedVector2Array = r.pts
			var out_m := clampf(c.distance_to(toward) * 0.3, MERGE_OUT_M.x, MERGE_OUT_M.y)
			var k := _sample_at_distance(r, out_m, side == "a")
			if k <= 0 or k >= pts.size() - 1:
				continue
			return _join_end(i, k, toward)
	var stub := PackedVector2Array([c, exit])
	return {"exit": exit, "lead": exit + out_dir * LEAD_M, "stub": stub, "site": String(site.id)}


## A way's end on road `i`'s sample `k` (a T), leaving it square toward `toward`.
func _join_end(i: int, k: int, toward: Vector2) -> Dictionary:
	var pts: PackedVector2Array = roads[i].pts
	var n := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).orthogonal().normalized()
	if n.dot(toward - pts[k]) < 0.0:
		n = -n
	var lead_m := float(roads[i].hw) + LEAD_M
	return {"exit": pts[k], "lead": pts[k] + n * lead_m, "stub": PackedVector2Array(), "site": "", "join": [i, k]}


## Where a road out of the middle `c` along `out_dir` (a street: straight along it; else the way's
## own `dir`, leaving through the side `out_dir` names) meets the pad's edge.
func _pad_exit(c: Vector2, pad: Rect2, out_dir: Vector2, dir: Vector2, street: bool) -> Vector2:
	if street:
		return Vector2(pad.end.x if out_dir.x > 0 else pad.position.x, c.y) if out_dir.x != 0.0 else Vector2(c.x, pad.end.y if out_dir.y > 0 else pad.position.y)
	var t := INF
	if dir.x != 0.0:
		t = minf(t, ((pad.end.x if dir.x > 0 else pad.position.x) - c.x) / dir.x)
	if dir.y != 0.0:
		t = minf(t, ((pad.end.y if dir.y > 0 else pad.position.y) - c.y) / dir.y)
	return c + dir * (t if t < INF else 0.0)


## The sample of road `r` this far (m) along it from its start (`from_a`) or its end.
func _sample_at_distance(r: Dictionary, d: float, from_a: bool) -> int:
	var s: PackedFloat32Array = r.s
	var total := s[s.size() - 1]
	var want := d if from_a else total - d
	for k in s.size():
		if s[k] >= want:
			return k
	return s.size() - 1


## A road from the zone's edge in through crossing `c` (RegionMap) to the nearest road (or site).
func _route_crossing(c: Dictionary, index: int) -> void:
	var side := int(c.get("side", 0))
	var p := Vector2(float(c.pos[0]), float(c.pos[1]))
	var gap := _half - EDGE_GAP_M
	var edge: Vector2 = [Vector2(p.x, -gap), Vector2(p.x, gap), Vector2(-gap, p.y), Vector2(gap, p.y)][side]
	var inward := (p - edge).normalized()
	var me := String(c.get("to_crossing", "")).trim_prefix("to_")
	var kind_id := crossing_kind(me, String(c.get("to", "")))
	var lead := p + inward * LEAD_M
	# The nearest road sample (not on a pad), else the nearest site.
	var best := INF
	var target := Vector2.ZERO
	var join: Array = []
	for i in roads.size():
		var pts: PackedVector2Array = roads[i].pts
		for k in range(1, pts.size() - 1):
			var d := pts[k].distance_squared_to(lead)
			if d < best and _is_blocked(pts[k]) != 2:
				best = d
				target = pts[k]
				join = [i, k]
	var eb: Dictionary
	if join.is_empty():
		var s := -1
		for i in _sites.size():
			if s < 0 or (_sites[i].pos as Vector2).distance_to(lead) < (_sites[s].pos as Vector2).distance_to(lead):
				s = i
		if s < 0:
			return
		eb = _end(s, _sites[s].pos, lead)
		eb.erase("join")
	else:
		eb = _join_end(int(join[0]), int(join[1]), lead)
	var ea := {"exit": edge, "stub": PackedVector2Array(), "site": "", "edge": String(c.get("id", ""))}
	var ctrl: Array[Vector2] = [edge, p, lead]
	var fixed: Array[bool] = [true, true, true]
	# The water's ways across its water link toward the nearest site (water_links), on the way in.
	var water_line := _crossing_links(c)
	var chain: Array[Vector2] = [edge, p, Vector2(float(water_line[1][1][0]), float(water_line[1][1][1]))]
	var anchors := _anchors(chain, [_crossing_link_base + index * 2, _crossing_link_base + index * 2 + 1])
	var inner: Array[Vector2] = [lead]
	var inner_fixed: Array[bool] = [true]
	var end: Vector2 = eb.lead if eb.has("lead") else eb.exit
	var toward := (end - p).normalized()
	var on_way: Array = (anchors.get(1, []) as Array).filter(func(an: Array) -> bool:
		var v: Vector2 = (an[1] as Vector2) - p
		return v.length() > LEAD_M and v.length() < end.distance_to(p) and v.normalized().dot(toward) > 0.8 and not _taken.has(int(an[2])))
	if on_way.size() % 4 == 0:  # (whole crossings only)
		for an: Array in on_way:
			inner.append(an[1])
			inner_fixed.append(true)
	inner.append(end)
	inner_fixed.append(true)
	_subdivide(inner, ctrl, fixed, inner_fixed)
	if eb.has("lead"):
		ctrl.append(eb.lead)
		fixed.append(true)
	ctrl.append(eb.exit)
	fixed.append(true)
	var road := _add_road(ctrl, fixed, kind_id, ea, eb)
	if on_way.size() % 4 == 0:
		for an: Array in on_way:
			_taken[int(an[2])] = road
	exits.append({"crossing": String(c.get("id", "")), "to": String(c.get("to", "")), "side": side, "edge": edge, "pos": p,
		"kind": kind_id, "width": half_width(kind_id) * 2.0, "road": road})


## Optimises the free control points, samples the curve and adds the road; its index.
func _add_road(ctrl: Array[Vector2], fixed: Array[bool], kind_id: String, ea: Dictionary, eb: Dictionary) -> int:
	_snake(ctrl, fixed)
	var curve := _catmull(ctrl, SAMPLE_M)
	var pts := PackedVector2Array([curve[0]])
	for k in range(1, curve.size()):
		if curve[k].distance_to(pts[pts.size() - 1]) >= 0.5 or k == curve.size() - 1:
			if k == curve.size() - 1 and curve[k].distance_to(pts[pts.size() - 1]) < 0.5 and pts.size() > 1:
				pts[pts.size() - 1] = curve[k]  # the end exactly where it was asked for
			else:
				pts.append(curve[k])
	var s := PackedFloat32Array()
	s.resize(pts.size())
	for k in range(1, pts.size()):
		s[k] = s[k - 1] + pts[k - 1].distance_to(pts[k])
	var road := {"id": roads.size(), "kind": kind_id, "hw": half_width(kind_id), "pts": pts, "s": s, "a": ea, "b": eb, "ctrl": ctrl}
	roads.append(road)
	for p in pts:
		var ci := floori((p.x + _half) / BLOCK_CELL_M)
		var cj := floori((p.y + _half) / BLOCK_CELL_M)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if ci + di >= 0 and cj + dj >= 0 and ci + di < _block_n and cj + dj < _block_n:
					_near[ci + di + (cj + dj) * _block_n] = 1
	for e: Dictionary in [ea, eb]:
		if e.has("join"):
			var j := _junction_at(e.exit, "t")
			_link_junction(j, roads.size() - 1)
			_link_junction(j, int(e.join[0]))
	return roads.size() - 1


## The junction at `p` (one within 1 m), made if none: its index.
func _junction_at(p: Vector2, kind_id: String) -> int:
	for i in junctions.size():
		if (junctions[i].pos as Vector2).distance_to(p) < 1.0:
			return i
	junctions.append({"id": junctions.size(), "pos": p, "kind": kind_id, "roads": [], "y": 0.0, "r": 0.0})
	return junctions.size() - 1


func _link_junction(j: int, road: int) -> void:
	if road not in (junctions[j].roads as Array):
		junctions[j].roads.append(road)


# --- The route: the snake ---------------------------------------------------------------------

func _snake(ctrl: Array[Vector2], fixed: Array[bool]) -> void:
	for step in SNAKE_STEPS:
		for sweep in (2 if step == SNAKE_STEPS[0] else 1):
			for i in range(1, ctrl.size() - 1):
				if fixed[i]:
					continue
				var n := (ctrl[i + 1] - ctrl[i - 1]).orthogonal().normalized()
				var here := ctrl[i]
				var best := here
				var best_cost := _local_cost(ctrl, i, here)
				for k: float in [-1.0, 1.0]:
					var cand := here + n * step * k
					var cost := _local_cost(ctrl, i, cand)
					if cost < best_cost:
						best_cost = cost
						best = cand
				ctrl[i] = best


## The cost of control point `i` of `ctrl` standing at `p`: its two legs and the three bends it
## changes.
func _local_cost(ctrl: Array[Vector2], i: int, p: Vector2) -> float:
	var prev := ctrl[i - 1]
	var next := ctrl[i + 1]
	var cost := _leg_cost(prev, p) + _leg_cost(p, next)
	cost += _bend(prev, p, next)
	if i >= 2:
		cost += _bend(ctrl[i - 2], prev, p)
	if i + 2 < ctrl.size():
		cost += _bend(p, next, ctrl[i + 2])
	return cost


func _bend(a: Vector2, b: Vector2, c: Vector2) -> float:
	var u := b - a
	var v := c - b
	if u.length_squared() < 0.01 or v.length_squared() < 0.01:
		return 0.0
	var angle := absf(u.angle_to(v))
	if angle > deg_to_rad(MAX_BEND_DEG):
		return BLOCK_COST + angle * 1000.0
	return BEND_COST * angle * angle * CTRL_M * 10.0


func _leg_cost(a: Vector2, b: Vector2) -> float:
	var length := a.distance_to(b)
	var n := maxi(ceili(length / 20.0), 1)
	var piece := length / n
	var cost := 0.0
	var h0 := _hq(a.x, a.y)
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		var h := _hq(p.x, p.y)
		var grade := absf(h - h0) / maxf(piece, 0.01)
		cost += piece * (1.0 + GRADE_COST * (grade / GRADE_REF) * (grade / GRADE_REF))
		if _is_blocked(p) != 0:
			cost += BLOCK_COST
		var i := floori((p.x + _half) / BLOCK_CELL_M)
		var j := floori((p.y + _half) / BLOCK_CELL_M)
		if i >= 0 and j >= 0 and i < _block_n and j < _block_n and _near[i + j * _block_n] == 1:
			cost += piece * NEAR_COST
		h0 = h
	return cost


## The ground's height at (x, z) for routing: bilinear between the height points (close enough to
## height_at's triangles to judge a route by, and quicker).
func _hq(x: float, z: float) -> float:
	var n := _t.points
	var gx := clampf((x + _half) / ZoneTerrain.CELL_M, 0.0, n - 1.001)
	var gz := clampf((z + _half) / ZoneTerrain.CELL_M, 0.0, n - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var k := i + j * n
	var top := lerpf(_hs[k], _hs[k + 1], fx)
	return lerpf(top, lerpf(_hs[k + n], _hs[k + n + 1], fx), fz)


## A centripetal Catmull-Rom curve through `ctrl`, about every `step` metres.
static func _catmull(ctrl: Array[Vector2], step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in n - 1:
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p0 := ctrl[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := ctrl[i + 2] if i + 2 < n else p2 * 2.0 - p1
		var pieces := maxi(ceili(p1.distance_to(p2) / step), 1)
		for k in pieces:
			out.append(_cr(p0, p1, p2, p3, float(k) / pieces))
	out.append(ctrl[n - 1])
	return out


static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 0.01)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 0.01)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 0.01)
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


# --- Junctions -------------------------------------------------------------------------------

## A trail's end that stops just short of (or on) another road joins it: a T, the end carried on
## to the nearest sample of the other road (LOOSE_END_M).
func _snap_loose_ends() -> void:
	for i in roads.size():
		var r: Dictionary = roads[i]
		for side: String in ["a", "b"]:
			var e: Dictionary = r[side]
			if String(e.get("site", "")) != "" or e.has("join") or e.has("edge"):
				continue
			var pts: PackedVector2Array = r.pts
			var end := pts[0] if side == "a" else pts[pts.size() - 1]
			var best := Vector2i(-1, -1)
			var best_d := LOOSE_END_M + float(r.hw)
			for j in roads.size():
				if j == i:
					continue
				var other: PackedVector2Array = roads[j].pts
				for k in range(1, other.size() - 1):
					var d := other[k].distance_to(end) - float(roads[j].hw)
					if d < best_d:
						best_d = d
						best = Vector2i(j, k)
			if best.x < 0:
				continue
			var at: Vector2 = (roads[best.x].pts as PackedVector2Array)[best.y]
			if side == "a":
				pts.insert(0, at)
			else:
				pts.append(at)
			r.pts = pts
			var arc := PackedFloat32Array()
			arc.resize(pts.size())
			for k in range(1, pts.size()):
				arc[k] = arc[k - 1] + pts[k - 1].distance_to(pts[k])
			r.s = arc
			e["join"] = [best.x, best.y]
			e["exit"] = at
			var jn := _junction_at(at, "t")
			_link_junction(jn, i)
			_link_junction(jn, best.x)


## Where two roads cross: an X junction, the point put into both curves. (Ends meeting are
## T junctions and nodes already.)
func _cross_points() -> void:
	var grid := {}
	for i in roads.size():
		var pts: PackedVector2Array = roads[i].pts
		for k in pts.size() - 1:
			var lo := ((Rect2(pts[k], Vector2.ZERO).expand(pts[k + 1]).position + Vector2(_half, _half)) / GRID_M).floor()
			var hi := ((Rect2(pts[k], Vector2.ZERO).expand(pts[k + 1]).end + Vector2(_half, _half)) / GRID_M).floor()
			for cy in range(int(lo.y), int(hi.y) + 1):
				for cx in range(int(lo.x), int(hi.x) + 1):
					var key := Vector2i(cx, cy)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(Vector2i(i, k))
	var found: Array = []  # [road i, sample k, road j, sample l, point]
	var seen := {}
	for key: Vector2i in grid:
		var list: Array = grid[key]
		for x in list.size():
			for y in range(x + 1, list.size()):
				var p: Vector2i = list[x]
				var q: Vector2i = list[y]
				if p.x == q.x:
					continue
				var tag := "%d:%d:%d:%d" % [p.x, p.y, q.x, q.y] if p.x < q.x else "%d:%d:%d:%d" % [q.x, q.y, p.x, p.y]
				if seen.has(tag):
					continue
				seen[tag] = true
				var a: PackedVector2Array = roads[p.x].pts
				var b: PackedVector2Array = roads[q.x].pts
				var hit: Variant = Geometry2D.segment_intersects_segment(a[p.y], a[p.y + 1], b[q.y], b[q.y + 1])
				if hit == null:
					continue
				found.append([p.x, p.y, q.x, q.y, hit])
	found.sort_custom(func(u: Array, v: Array) -> bool: return Vector4(u[0], u[1], u[2], u[3]) < Vector4(v[0], v[1], v[2], v[3]))
	var inserts := {}  # road -> [[sample, point]]
	for f: Array in found:
		var at: Vector2 = f[4]
		# Not at an end (a T or a node: met already).
		var near := false
		for r: int in [int(f[0]), int(f[2])]:
			var pts: PackedVector2Array = roads[r].pts
			if pts[0].distance_to(at) < 12.0 or pts[pts.size() - 1].distance_to(at) < 12.0:
				near = true
		if near:
			continue
		var j := _junction_at(at, "x")
		_link_junction(j, int(f[0]))
		_link_junction(j, int(f[2]))
		for pair: Array in [[int(f[0]), int(f[1])], [int(f[2]), int(f[3])]]:
			if not inserts.has(pair[0]):
				inserts[pair[0]] = []
			inserts[pair[0]].append([int(pair[1]), at])
	for r: int in inserts:
		var list: Array = inserts[r]
		var pts: PackedVector2Array = roads[r].pts
		# Back to front (so the samples still line up), and on one piece the far point first.
		list.sort_custom(func(u: Array, v: Array) -> bool:
			if int(u[0]) != int(v[0]):
				return int(u[0]) > int(v[0])
			return (u[1] as Vector2).distance_to(pts[int(u[0])]) > (v[1] as Vector2).distance_to(pts[int(v[0])]))
		for ins: Array in list:
			pts.insert(int(ins[0]) + 1, ins[1])
		roads[r].pts = pts
		var s := PackedFloat32Array()
		s.resize(pts.size())
		for k in range(1, pts.size()):
			s[k] = s[k - 1] + pts[k - 1].distance_to(pts[k])
		roads[r].s = s
	# Nodes of the links (three or more ways met there): junctions too.
	var ends := {}
	for i in roads.size():
		for e: Dictionary in [roads[i].a, roads[i].b]:
			if String(e.get("site", "")) != "" or e.has("join") or e.has("edge"):
				continue
			var key := Vector2i(roundi((e.exit as Vector2).x * 2.0), roundi((e.exit as Vector2).y * 2.0))
			if not ends.has(key):
				ends[key] = []
			ends[key].append(i)
	for key: Vector2i in ends:
		var list: Array = ends[key]
		if list.size() >= 2:
			var j := _junction_at(Vector2(key) * 0.5, "node")
			for r: int in list:
				_link_junction(j, r)


## A road's sample at junction `j` (the nearest), -1 if not on it.
func sample_of(road: int, j: int) -> int:
	var pts: PackedVector2Array = roads[road].pts
	var at: Vector2 = junctions[j].pos
	var best := -1
	var best_d := 1.5
	for k in pts.size():
		var d := pts[k].distance_to(at)
		if d < best_d:
			best_d = d
			best = k
	return best


## How many arms meet at junction `j` (a road through it two, one ending there one).
func arms(j: int) -> int:
	var n := 0
	for r: int in junctions[j].roads:
		var k := sample_of(r, j)
		var last := (roads[r].pts as PackedVector2Array).size() - 1
		n += 1 if k == 0 or k == last else 2
	return n


## Roundabouts: a junction of min_arms or more near a town (or four asphalt arms), clear of the pads.
func _choose_roundabouts() -> void:
	var spec: Dictionary = data().get("roundabout", {})
	var island := float(spec.get("island_r_m", 6.0))
	var outer := island + float(spec.get("ring_w_m", 7.0))
	for j in junctions.size():
		var jn: Dictionary = junctions[j]
		var at: Vector2 = jn.pos
		var n := arms(j)
		var asphalt := 0
		for r: int in jn.roads:
			if String(roads[r].kind) == "asphalt":
				asphalt += 1
		var near_town := towns.any(func(t: Dictionary) -> bool: return (t.pos as Vector2).distance_to(at) < float(spec.get("near_town_m", 320.0)))
		var want: bool = asphalt > 0 and n >= int(spec.get("min_arms", 3)) and (near_town or (n >= 4 and asphalt == jn.roads.size()))
		var clear := _pads.all(func(r: Rect2) -> bool: return ZoneTerrain._distance_to_rect(at, r) > outer + 4.0) and _is_blocked(at) == 0
		for k in junctions.size():
			var apart := (junctions[k].pos as Vector2).distance_to(at)
			if k != j and ((String(junctions[k].kind) == "roundabout" and apart < outer * 2.0 + 20.0) or apart < outer + JUNCTION_FLAT_M):
				clear = false
		if want and clear:
			jn.kind = "roundabout"
			jn.r = outer
			jn["island"] = island
		else:
			# A plain junction's patch covers where the arms overlap (narrow angles reach further).
			var widest := 0.0
			for r: int in jn.roads:
				widest = maxf(widest, float(roads[r].hw))
			jn.r = minf(widest * 2.2 + 1.0, JUNCTION_FLAT_M - 2.0)


# --- Heights ---------------------------------------------------------------------------------

## Every road's surface height: the ground along it smoothed (over SMOOTH_M, the target), then
## solved as a stretched string (_solve): held exactly at its pins (the pads it leaves, its
## junctions held flat, a pad it crosses), drawn toward the target elsewhere, toward the roads
## laid before it where it passes close by them (_beside), and straight over water (no target
## there: where the bridge goes).
func _profiles() -> void:
	var targets: Array[PackedFloat32Array] = []
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var raw := PackedFloat32Array()
		var wet := PackedByteArray()
		raw.resize(pts.size())
		wet.resize(pts.size())
		for k in pts.size():
			raw[k] = _t.height_at(pts[k].x, pts[k].y)
			wet[k] = 1 if _wet(pts[k].x, pts[k].y, raw[k]) else 0
		r["raw"] = raw
		r["wet"] = wet
		var win := maxi(roundi(SMOOTH_M / SAMPLE_M), 1)
		var target := PackedFloat32Array()
		target.resize(pts.size())
		for k in pts.size():
			var sum := 0.0
			var n := 0
			for m in range(maxi(k - win, 0), mini(k + win + 1, pts.size())):
				if wet[m] == 0:
					sum += raw[m]
					n += 1
			target[k] = clampf(sum / n, raw[k] - CUT_MAX_M, raw[k] + CUT_MAX_M) if n > 0 else raw[k]
		targets.append(target)
	# Junction heights: the mean of the roads' own there.
	for j in junctions.size():
		var sum := 0.0
		var n := 0
		for r: int in junctions[j].roads:
			var k := sample_of(r, j)
			if k >= 0:
				sum += targets[r][k]
				n += 1
		junctions[j].y = sum / n if n > 0 else _t.height_at(junctions[j].pos.x, junctions[j].pos.y)
	# Junctions near each other on a road: their heights eased toward each other until the stretch
	# between their flats is a ramp of at most JUNCTION_RAMP (a few rounds: one junction can sit on
	# several roads).
	# Pads the road leaves or passes: fixed heights too (their ground isn't graded), in the same
	# lists, so a junction near one eases toward it.
	var pad_pins: Array = []  # per road: [[sample, height, flat m]]
	for r in roads.size():
		pad_pins.append(_pad_pins(roads[r]))
	var along: Array = []  # per road: [[sample, node]] in order (a junction, or a pad's pin)
	for r in roads.size():
		var list: Array = []
		for j in junctions.size():
			if r in (junctions[j].roads as Array):
				var k := sample_of(r, j)
				if k >= 0:
					list.append([k, junctions[j]])
		for pin: Array in pad_pins[r]:
			list.append([int(pin[0]), {"y": float(pin[1]), "flat": float(pin[2]), "fixed": true, "kind": "pad", "r": 0.0}])
		list.sort_custom(func(u: Array, v: Array) -> bool: return int(u[0]) < int(v[0]))
		along.append(list)
	var cluster := range(junctions.size())  # junctions close together: one height
	for a in junctions.size():
		for b in range(a + 1, junctions.size()):
			if (junctions[a].pos as Vector2).distance_to(junctions[b].pos) < CLUSTER_M:
				var ra: int = a
				while cluster[ra] != ra:
					ra = cluster[ra]
				var rb: int = b
				while cluster[rb] != rb:
					rb = cluster[rb]
				cluster[rb] = ra
	for round in 8:
		_level_clusters(cluster)
		for r in roads.size():
			var list: Array = along[r]
			var s: PackedFloat32Array = roads[r].s
			for m in range(1, list.size()):
				var a: Dictionary = list[m - 1][1]
				var b: Dictionary = list[m][1]
				var gap := maxf(s[int(list[m][0])] - s[int(list[m - 1][0])] - _flat_of(a) - _flat_of(b), 0.0)
				var diff := float(a.y) - float(b.y)
				var excess := absf(diff) - gap * JUNCTION_RAMP
				if excess > 0.0:
					var fa := bool(a.get("fixed", false))
					var fb := bool(b.get("fixed", false))
					if fa and fb:
						continue
					var share_a := 0.0 if fa else (1.0 if fb else 0.5)
					a.y = float(a.y) - signf(diff) * excess * share_a
					b.y = float(b.y) + signf(diff) * excess * (1.0 - share_a)
	_level_clusters(cluster)
	var beside := {}  # the roads laid so far: GRID_M cell -> [Vector2i(road, sample)]
	_beside_mask = PackedByteArray()
	_beside_mask.resize(_block_n * _block_n)
	for i in roads.size():
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r.pts
		var s: PackedFloat32Array = r.s
		var wet: PackedByteArray = r.wet
		var n := pts.size()
		var target: PackedFloat32Array = targets[i]
		var weight := PackedFloat32Array()
		weight.resize(n)
		for k in n:
			weight[k] = 0.0 if wet[k] == 1 else 1.0
		var drawn := _beside(i, target, weight, beside)
		target = drawn[0]
		weight = drawn[1]
		var pins: Array = []  # [sample, height, flat m]: the junctions', then the pads' (which win)
		for j in junctions.size():
			if i in (junctions[j].roads as Array):
				var k := sample_of(i, j)
				if k >= 0:
					pins.append([k, float(junctions[j].y), _flat_of(junctions[j])])
		pins.append_array(pad_pins[i])
		# On a bridge's deck: its top; on its ramps: down them (the road isn't laid there).
		var on_bridge := PackedByteArray()
		on_bridge.resize(n)
		for k in n:
			var h := _bridge_height(pts[k], pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
			if not is_nan(h):
				on_bridge[k] = 1
				pins.append([k, h, 0.0])
		r["bridge"] = on_bridge
		var pinned := PackedByteArray()
		pinned.resize(n)
		var pin_h := PackedFloat32Array()
		pin_h.resize(n)
		for p: Array in pins:
			var k0 := int(p[0])
			for dir: int in [-1, 1]:
				var k := k0 if dir == 1 else k0 - 1
				while k >= 0 and k < n and absf(s[k] - s[k0]) <= float(p[2]):
					pinned[k] = 1
					pin_h[k] = float(p[1])
					k += dir
		var ys := _solve(target, weight, pinned, pin_h, PROFILE_LAMBDA_M / SAMPLE_M)
		for sweep in 3:  # (a light 1-2-1 smoothing off the pins: the kinks where a flat meets a slope)
			var was := ys.duplicate()
			for k in range(1, n - 1):
				if pinned[k] == 0 and wet[k] == 0:
					ys[k] = (was[k - 1] + was[k] * 2.0 + was[k + 1]) * 0.25
		var spans: Array = []
		var k := 0
		while k < n:
			if wet[k] == 0:
				k += 1
				continue
			var from := k - 1
			while k < n and wet[k] == 1:
				k += 1
			spans.append([maxi(from, 0), mini(k, n - 1)])
		r["ys"] = ys
		r["water"] = spans
		for m in n:
			if wet[m] == 0:
				var cell := Vector2i(floori((pts[m].x + _half) / GRID_M), floori((pts[m].y + _half) / GRID_M))
				if not beside.has(cell):
					beside[cell] = []
				beside[cell].append(Vector2i(i, m))
				if m % 2 == 1:
					continue
				var bi := floori((pts[m].x + _half) / BLOCK_CELL_M)
				var bj := floori((pts[m].y + _half) / BLOCK_CELL_M)
				for dj in range(-2, 3):
					for di in range(-2, 3):
						if bi + di >= 0 and bj + dj >= 0 and bi + di < _block_n and bj + dj < _block_n:
							_beside_mask[bi + di + (bj + dj) * _block_n] = 1
	# Roundabouts: the arms inside the ring aren't drawn (the ring is).
	for r: Dictionary in roads:
		var skip := PackedByteArray()
		skip.resize((r.pts as PackedVector2Array).size())
		r["skip"] = skip
	for jn: Dictionary in junctions:
		if String(jn.kind) != "roundabout":
			continue
		for ri: int in jn.roads:
			var pts: PackedVector2Array = roads[ri].pts
			var skip: PackedByteArray = roads[ri].skip
			for k in pts.size():
				if pts[k].distance_to(jn.pos) < float(jn.r) - 0.5:
					skip[k] = 1
			roads[ri].skip = skip


## Every cluster of junctions (`cluster`: union-find parents) at one height: a fixed one's (by a
## pad) if it has one, else their mean.
func _level_clusters(cluster: Array) -> void:
	var sums := {}
	for j in junctions.size():
		var root: int = j
		while cluster[root] != root:
			root = cluster[root]
		var acc: Vector3 = sums.get(root, Vector3.ZERO)
		if bool(junctions[j].get("fixed", false)):
			acc = Vector3(float(junctions[j].y) * 1000.0, 1000.0, 1.0) + Vector3(acc.x, acc.y, 0.0) if acc.z < 1.0 else acc
		else:
			acc += Vector3(float(junctions[j].y), 1.0, 0.0)
		sums[root] = acc
	for j in junctions.size():
		var root: int = j
		while cluster[root] != root:
			root = cluster[root]
		var acc: Vector3 = sums[root]
		junctions[j].y = acc.x / acc.y
		if acc.z >= 1.0:
			junctions[j]["fixed"] = true


## Road `r`'s pins at pads: level with the pad it leaves (SITE_FLAT_M out), and wherever it passes
## within PAD_BESIDE_M of a pad's edge (a landing zone it couldn't keep off), whose ground isn't
## graded: [[sample, height, flat m]].
func _pad_pins(r: Dictionary) -> Array:
	var pins: Array = []
	var pts: PackedVector2Array = r.pts
	var s: PackedFloat32Array = r.s
	var n := pts.size()
	for side: String in ["a", "b"]:
		var e: Dictionary = r[side]
		if String(e.get("site", "")) != "":
			var exit: Vector2 = e.exit
			var h := _t.height_at(exit.x, exit.y)
			for pad: Array in _t.pads:
				if (pad[0] as Rect2).grow(0.5).has_point(exit):
					h = float(pad[1])  # (the pad's own height)
					break
			pins.append([0 if side == "a" else n - 1, h, SITE_FLAT_M])
	var k_on := -1
	var hw := float(r.hw)
	for k in n + 1:
		var pad := _pad_near(pts[k], hw + PAD_BESIDE_M) if k < n else -1
		if pad >= 0 and k_on < 0:
			k_on = k
		elif pad < 0 and k_on >= 0:
			var mid := (k_on + k - 1) / 2
			var at := _pad_near(pts[mid], hw + PAD_BESIDE_M)
			if at < 0:
				at = _pad_near(pts[k_on], hw + PAD_BESIDE_M)
			if at >= 0:
				pins.append([mid, float(_t.pads[at][1]), (s[k - 1] - s[k_on]) * 0.5])
			k_on = -1
	return pins


## How far along its roads junction `jn` is held flat (m) (a pad's pin: its own).
static func _flat_of(jn: Dictionary) -> float:
	if jn.has("flat"):
		return float(jn.flat)
	return float(jn.r) + 8.0 if String(jn.kind) == "roundabout" else JUNCTION_FLAT_M


## The stretched string: heights y minimising weight x (y - target)^2 plus lam^2 x (the step
## between neighbours)^2, with the pinned samples held at pin_h. A tridiagonal system, solved
## directly (Thomas): a pin's pull fades over about lam samples either side; with no target (water)
## the string runs straight between the banks.
static func _solve(target: PackedFloat32Array, weight: PackedFloat32Array, pinned: PackedByteArray, pin_h: PackedFloat32Array, lam: float) -> PackedFloat32Array:
	var n := target.size()
	var ws := lam * lam
	var cp := PackedFloat32Array()
	var dp := PackedFloat32Array()
	cp.resize(n)
	dp.resize(n)
	var y := PackedFloat32Array()
	y.resize(n)
	if n == 0:
		return y
	for k in n:
		var a := 0.0
		var b := 1.0
		var c := 0.0
		var d := pin_h[k]
		if pinned[k] == 0:
			a = -ws if k > 0 else 0.0
			c = -ws if k < n - 1 else 0.0
			b = weight[k] - a - c
			d = weight[k] * target[k]
			if b <= 0.0:  # (a lone sample with nothing to hold it)
				b = 1.0
				d = target[k]
		var m := b - (a * cp[k - 1] if k > 0 else 0.0)
		cp[k] = c / m
		dp[k] = (d - (a * dp[k - 1] if k > 0 else 0.0)) / m
	y[n - 1] = dp[n - 1]
	for k in range(n - 2, -1, -1):
		y[k] = dp[k] - cp[k] * y[k + 1]
	return y


## The nearest pad (ZoneTerrain.pads index) within `reach` of `p`, -1 if none.
func _pad_near(p: Vector2, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in _pads.size():
		var d := ZoneTerrain._distance_to_rect(p, _pads[i])
		if d < best_d or (d == 0.0 and best < 0):
			best_d = d
			best = i
	return best


## The height of the bridge (deck or ramp) at `p` for a road heading `heading` along it, NAN off
## every bridge (or across one: a road along the bank under its end isn't on it).
func _bridge_height(p: Vector2, heading: Vector2) -> float:
	for bb: Dictionary in _bridge_boxes:
		var v: Vector2 = p - (bb.centre as Vector2)
		var along: Vector2 = bb.along
		if absf(heading.normalized().dot(along)) < 0.8:
			continue
		var z := v.dot(along)
		var x := v.x * -along.y + v.y * along.x
		var half := float(bb.half_len)
		if absf(x) > float(bb.half_w) or absf(z) > half + ZoneBridges.RAMP_M:
			continue
		if absf(z) <= half:
			return float(bb.top)
		for ramp: Array in bb.ramps:
			if signf(float(ramp[0])) == signf(z):
				return float(bb.top) - float(ramp[2]) * (absf(z) - half) / ZoneBridges.RAMP_M
		return float(bb.top)
	return NAN


## The pad (ZoneTerrain.pads index) under `p`, -1 if none.
func _pad_under(p: Vector2) -> int:
	for i in _pads.size():
		if _pads[i].has_point(p):
			return i
	return -1


## Roads that pass close by each other without meeting at a junction (a road past another's
## junction, two leaving a pad side by side): road `i`'s `target` drawn hard toward the roads laid
## before it (`beside`) where it's within NEAR_EXTRA_M of one's edge, fading out over NEAR_BLEND_M
## (the ground between them can only be graded to one height). Its own pins still hold. Returns
## [target, weight] (packed arrays are values).
func _beside(i: int, target: PackedFloat32Array, weight: PackedFloat32Array, beside: Dictionary) -> Array:
	if beside.is_empty():
		return [target, weight]
	var r: Dictionary = roads[i]
	var pts: PackedVector2Array = r.pts
	var hw := float(r.hw)
	for k in pts.size():
		if weight[k] == 0.0:
			continue
		var bi := floori((pts[k].x + _half) / BLOCK_CELL_M)
		var bj := floori((pts[k].y + _half) / BLOCK_CELL_M)
		if bi < 0 or bj < 0 or bi >= _block_n or bj >= _block_n or _beside_mask[bi + bj * _block_n] == 0:
			continue
		var cell := Vector2i(floori((pts[k].x + _half) / GRID_M), floori((pts[k].y + _half) / GRID_M))
		var best_d := INF
		var best_y := 0.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for rk: Vector2i in beside.get(cell + Vector2i(dx, dy), []):
					var o: Dictionary = roads[rk.x]
					var d := pts[k].distance_to((o.pts as PackedVector2Array)[rk.y]) - hw - float(o.hw)
					if d < best_d:
						best_d = d
						best_y = (o.ys as PackedFloat32Array)[rk.y]
		if best_d < NEAR_EXTRA_M + NEAR_BLEND_M:
			var w := BESIDE_WEIGHT * (1.0 - smoothstep(NEAR_EXTRA_M, NEAR_EXTRA_M + NEAR_BLEND_M, best_d))
			target[k] = (target[k] * weight[k] + best_y * w) / (weight[k] + w)
			weight[k] += w
	return [target, weight]


## Cuts and fills the terrain's heights to the roads (and the roundabouts' discs), then lets the
## terrain take them in. Pads and water are left as they are.
func _grade() -> void:
	var t := _t
	_gd = PackedFloat32Array()
	_gd.resize(t.points * t.points)
	_gd.fill(INF)
	_gy = PackedFloat32Array()
	_gy.resize(t.points * t.points)
	_touched = PackedInt32Array()
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		var wet: PackedByteArray = r.wet
		var hw := float(r.hw)
		# Pieces of three samples (the profile is smooth enough for the chord).
		var k := 0
		while k < pts.size() - 1:
			var k2 := mini(k + 3, pts.size() - 1)
			var dry := true
			var bridge: PackedByteArray = r.get("bridge", PackedByteArray())
			for m in range(k, k2 + 1):
				dry = dry and wet[m] == 0 and (bridge.is_empty() or bridge[m] == 0)
			if dry:
				_consider(pts[k], pts[k2], ys, k, k2, hw)
			else:
				for m in range(k, k2):
					if wet[m] == 0 and wet[m + 1] == 0 and (bridge.is_empty() or (bridge[m] == 0 and bridge[m + 1] == 0)):
						_consider(pts[m], pts[m + 1], ys, m, m + 1, hw)
			k = k2
	for jn: Dictionary in junctions:
		var at: Vector2 = jn.pos
		_consider(at, at, PackedFloat32Array([float(jn.y)]), 0, 0, float(jn.r))
	var heights := t.heights  # (a local copy, written back once: a packed array is a value)
	for idx in _touched:
		var x := (idx % t.points) * ZoneTerrain.CELL_M - _half
		var z := (idx / t.points) * ZoneTerrain.CELL_M - _half
		var p := Vector2(x, z)
		var on_pad := false
		for r in _pads:
			if r.has_point(p):
				on_pad = true
				break
		if on_pad:
			continue
		var h := heights[idx]
		if _wet(x, z, h):
			continue
		var d := _gd[idx]
		var y := _gy[idx] - SINK_M
		var lo := y - maxf(d - FILL_FLAT_M, 0.0) * FILL_BANK
		var hi := y + maxf(d - FLAT_EXTRA_M, 0.0) * CUT_BANK
		heights[idx] = clampf(h, lo, hi)
	# Clearance: no height point of a cell the road's surface crosses stands above it (where two
	# roads overlap at different heights the lower one wins and the higher rides over).
	var n := t.points
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var ys: PackedFloat32Array = r.ys
		var wet: PackedByteArray = r.wet
		var hw := float(r.hw)
		var on_bridge: PackedByteArray = r.get("bridge", PackedByteArray())
		for k in pts.size():
			if wet[k] == 1 or (not on_bridge.is_empty() and on_bridge[k] == 1):
				continue
			var k0 := maxi(k - 1, 0)
			var k1 := mini(k + 1, pts.size() - 1)
			var along := (pts[k1] - pts[k0]).normalized()
			var side := along.orthogonal()
			var grade := (ys[k1] - ys[k0]) / maxf(pts[k0].distance_to(pts[k1]), 0.01)
			for o: float in [-hw, 0.0, hw]:
				var q := pts[k] + side * o
				var ci := floori((q.x + _half) / ZoneTerrain.CELL_M)
				var cj := floori((q.y + _half) / ZoneTerrain.CELL_M)
				for dj in 2:
					for di in 2:
						var i := ci + di
						var j := cj + dj
						if i < 0 or j < 0 or i >= n or j >= n:
							continue
						var idx := i + j * n
						var v := Vector2(i * ZoneTerrain.CELL_M - _half, j * ZoneTerrain.CELL_M - _half)
						var y_v := ys[k] + grade * (v - pts[k]).dot(along)  # (the road's height level with the point)
						if heights[idx] > y_v - SINK_M * 0.5 and _pad_under(v) < 0:
							heights[idx] = y_v - SINK_M
	t.heights = heights
	graded_vertices = _touched.size()
	_gd = PackedFloat32Array()
	_gy = PackedFloat32Array()
	_touched = PackedInt32Array()
	t.heights_changed()


## Grading: every height point near the piece a-b (samples ka to kb of a road with heights `ys`,
## half-width hw) keeps the nearest road's height and how far past its edge it is (_gd, _gy).
func _consider(a: Vector2, b: Vector2, ys: PackedFloat32Array, ka: int, kb: int, hw: float) -> void:
	var n := _t.points
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(hw + GRADE_REACH_M)
	var i0 := maxi(floori((box.position.x + _half) / ZoneTerrain.CELL_M), 0)
	var i1 := mini(ceili((box.end.x + _half) / ZoneTerrain.CELL_M), n - 1)
	var j0 := maxi(floori((box.position.y + _half) / ZoneTerrain.CELL_M), 0)
	var j1 := mini(ceili((box.end.y + _half) / ZoneTerrain.CELL_M), n - 1)
	var abx := b.x - a.x
	var abz := b.y - a.y
	var inv := 1.0 / maxf(abx * abx + abz * abz, 0.0001)
	var reach := hw + GRADE_REACH_M
	var reach2 := reach * reach
	var length := sqrt(abx * abx + abz * abz)
	var tx := abx / maxf(length, 0.0001)
	var tz := abz / maxf(length, 0.0001)
	for j in range(j0, j1 + 1):
		var dz := j * ZoneTerrain.CELL_M - _half - a.y
		# Only the row's stretch inside the capsule (the piece grown by `reach`): the end discs and
		# the band between them.
		var lo := INF
		var hi := -INF
		for end: Vector2 in [Vector2(0.0, dz), Vector2(abx, dz - abz)]:
			if absf(end.y) <= reach:
				var w := sqrt(reach2 - end.y * end.y)
				lo = minf(lo, end.x - w)
				hi = maxf(hi, end.x + w)
		# Band: |dx * tz - dz * tx| <= reach and 0 <= dx * tx + dz * tz <= length (dx from a.x).
		var blo := -INF
		var bhi := INF
		for c: Array in [[tz, -dz * tx, -reach, reach], [tx, dz * tz, 0.0, length]]:
			var coef: float = c[0]
			var off: float = c[1]
			if absf(coef) < 1e-6:
				if off < float(c[2]) or off > float(c[3]):
					blo = INF
				continue
			var x0 := (float(c[2]) - off) / coef
			var x1 := (float(c[3]) - off) / coef
			blo = maxf(blo, minf(x0, x1))
			bhi = minf(bhi, maxf(x0, x1))
		if blo <= bhi:
			lo = minf(lo, blo)
			hi = maxf(hi, bhi)
		if lo > hi:
			continue
		var ia := maxi(i0, ceili((lo + a.x + _half) / ZoneTerrain.CELL_M))
		var ib := mini(i1, floori((hi + a.x + _half) / ZoneTerrain.CELL_M))
		for i in range(ia, ib + 1):
			var dx := i * ZoneTerrain.CELL_M - _half - a.x
			var u := clampf((dx * abx + dz * abz) * inv, 0.0, 1.0)
			var ex := dx - abx * u
			var ez := dz - abz * u
			var e2 := ex * ex + ez * ez
			if e2 > reach2:
				continue
			var d := sqrt(e2) - hw
			var idx := i + j * n
			var was := _gd[idx]
			if d < was:
				if was == INF:
					_touched.append(idx)
				_gd[idx] = d
				# (The road's own height there, sample to sample: not the piece's chord.)
				var f := u * (kb - ka)
				var k := mini(ka + int(f), maxi(kb - 1, ka))
				_gy[idx] = lerpf(ys[k], ys[mini(k + 1, kb)], f - (k - ka))


# --- Queries ---------------------------------------------------------------------------------

func _index() -> void:
	_grid.clear()
	for i in roads.size():
		var pts: PackedVector2Array = roads[i].pts
		var reach := float(roads[i].hw) + 1.0
		for k in pts.size() - 1:
			var box := Rect2(pts[k], Vector2.ZERO).expand(pts[k + 1]).grow(reach)
			for cy in range(floori((box.position.y + _half) / GRID_M), floori((box.end.y + _half) / GRID_M) + 1):
				for cx in range(floori((box.position.x + _half) / GRID_M), floori((box.end.x + _half) / GRID_M) + 1):
					var key := Vector2i(cx, cy)
					if not _grid.has(key):
						_grid[key] = []
					_grid[key].append(Vector2i(i, k))


## The nearest road centreline to (x, z) within `reach` (m): {"road", "sample", "d" (m from the
## centreline), "y" (its surface there), "u" (0..1 along the piece)} or {}.
func nearest(x: float, z: float, reach := 8.0) -> Dictionary:
	var p := Vector2(x, z)
	var key := Vector2i(floori((x + _half) / GRID_M), floori((z + _half) / GRID_M))
	var best := {}
	var cells: Array[Vector2i] = [key]
	if reach > 1.0:
		cells = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cells.append(key + Vector2i(dx, dy))
	var seen := {}
	for cell in cells:
		for rk: Vector2i in _grid.get(cell, []):
			if seen.has(rk):
				continue
			seen[rk] = true
			var r: Dictionary = roads[rk.x]
			var pts: PackedVector2Array = r.pts
			var a := pts[rk.y]
			var b := pts[rk.y + 1]
			var ab := b - a
			var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * u)
			if d <= reach and (best.is_empty() or d < float(best.d)):
				var ys: PackedFloat32Array = r.ys
				best = {"road": rk.x, "sample": rk.y, "d": d, "u": u, "y": lerpf(ys[rk.y], ys[rk.y + 1], u)}
	return best


# --- The def ---------------------------------------------------------------------------------

func _write_def(def: Dictionary) -> void:
	var out: Array = []
	var snap := func(p: Vector2) -> Array: return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	var piece := func(line: PackedVector2Array, kind_id: String) -> void:
		for k in range(1, line.size()):
			if line[k - 1].distance_to(line[k]) > 0.05:
				out.append([snap.call(line[k - 1]), snap.call(line[k]), kind_id])
	var simplified := {}
	for i in roads.size():
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r.pts
		var skip: PackedByteArray = r.skip
		var keep := {0: true, pts.size() - 1: true}
		for j in junctions.size():
			if i in (junctions[j].roads as Array):
				var k := sample_of(i, j)
				if k >= 0:
					keep[k] = true
		# Split round each roundabout: up to the ring, on from the ring (its nearest corner).
		var runs: Array = []  # [PackedVector2Array]
		var run := PackedVector2Array()
		var run_keep: Array = []
		var ring_of := func(p: Vector2) -> Vector2:
			for jn: Dictionary in junctions:
				if String(jn.kind) == "roundabout" and (jn.pos as Vector2).distance_to(p) < float(jn.r) + SAMPLE_M * 2.0:
					return _ring_corner(jn, p)
			return p
		for k in pts.size():
			if skip[k] == 1:
				if not run.is_empty():
					run.append(ring_of.call(run[run.size() - 1]))
					run_keep.append(run.size() - 1)
					runs.append([run, run_keep])
					run = PackedVector2Array()
					run_keep = []
				continue
			if run.is_empty() and k > 0 and skip[k - 1] == 1:
				run.append(ring_of.call(pts[k]))
				run_keep.append(0)
			run.append(pts[k])
			if keep.has(k):
				run_keep.append(run.size() - 1)
		if run.size() >= 2:
			runs.append([run, run_keep])
		var flat := PackedVector2Array()
		for rk: Array in runs:
			var line := _simplify(rk[0], rk[1])
			piece.call(line, String(r.kind))
			flat.append_array(line)
		simplified[i] = flat
		for e: Dictionary in [r.a, r.b]:
			var stub: PackedVector2Array = e.get("stub", PackedVector2Array())
			if stub.size() >= 2:
				piece.call(stub, "street" if _site_base(String(e.site)) == "town" else String(r.kind))
	for jn: Dictionary in junctions:
		if String(jn.kind) != "roundabout":
			continue
		var ring := PackedVector2Array()
		for k in RING_SIDES + 1:
			ring.append(_ring_point(jn, k % RING_SIDES))
		piece.call(ring, "asphalt")
	def["roads"] = out
	def["roads_version"] = VERSION
	# The trails' patrols walk their curved roads.
	var patrols: Array = (def.get("patrol_links", def.get("patrols", [])) as Array).duplicate(true)
	for pi in patrols.size():
		var route: Array = patrols[pi]
		for ri: int in _way_of_trail:
			var nodes: Array[Vector2] = _way_of_trail[ri]
			if nodes.size() != route.size():
				continue
			var same := true
			for k in nodes.size():
				same = same and nodes[k].distance_to(Vector2(float(route[k][0]), float(route[k][1]))) < 2.5
			if same:
				var walk: Array = []
				for part: int in _trail_parts.get(ri, [ri]):  # (a trail laid in parts: across the bridge between them)
					var line: PackedVector2Array = simplified[part]
					for p in line:
						walk.append(snap.call(p))
				patrols[pi] = walk
	if def.has("patrols") or not patrols.is_empty():
		def["patrols"] = patrols


func _site_base(id: String) -> String:
	for s: Dictionary in _sites:
		if String(s.id) == id:
			return String(s.base)
	return ""


## Roundabout `jn`'s ring corner `k` (the ring's middle line, RING_SIDES corners).
func _ring_point(jn: Dictionary, k: int) -> Vector2:
	var r := (float(jn.island) + float(jn.r)) * 0.5
	return (jn.pos as Vector2) + Vector2.from_angle(TAU * k / RING_SIDES) * r


func _ring_corner(jn: Dictionary, p: Vector2) -> Vector2:
	var k := posmod(roundi((p - (jn.pos as Vector2)).angle() / TAU * RING_SIDES), RING_SIDES)
	return _ring_point(jn, k)


## Douglas-Peucker within DEF_TOL_M, keeping the indices in `keep`, no piece over DEF_MAX_SEG_M.
static func _simplify(line: PackedVector2Array, keep: Array) -> PackedVector2Array:
	var n := line.size()
	if n <= 2:
		return line
	var mark := PackedByteArray()
	mark.resize(n)
	mark[0] = 1
	mark[n - 1] = 1
	for k: int in keep:
		if k >= 0 and k < n:
			mark[k] = 1
	var stack: Array[Vector2i] = []
	var a := 0
	for k in range(1, n):
		if mark[k] == 1:
			stack.append(Vector2i(a, k))
			a = k
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1.0
		var at := -1
		for k in range(span.x + 1, span.y):
			var q := Geometry2D.get_closest_point_to_segment(line[k], line[span.x], line[span.y])
			var d := q.distance_to(line[k])
			if d > worst:
				worst = d
				at = k
		if at >= 0 and (worst > DEF_TOL_M or line[span.x].distance_to(line[span.y]) > DEF_MAX_SEG_M):
			mark[at] = 1
			stack.append(Vector2i(span.x, at))
			stack.append(Vector2i(at, span.y))
	var out := PackedVector2Array()
	for k in n:
		if mark[k] == 1:
			out.append(line[k])
	return out
