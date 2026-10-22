class_name ZoneWater
extends Node3D
## A zone's water (queue item 1.1 of docs/cg_brief.md): rivers and streams that cut their own
## valleys into the heightmap and flow downhill, lakes and ponds, and the ways across them
## (ZoneBridges: concrete, steel truss and foot bridges, fords and culverts where the def's roads
## cross a river or stream, and fords or footbridges every CROSSING_GAP_M along a river so the
## AI's navigation never loses half the zone). From the terrain preset's "water" (data/
## terrain_presets.json, docs/terrain_presets.md) and the zone's seed only, so every peer and
## late joiner builds the same water; ZoneTerrain.generate calls carve() once the pads are flat.
##
## A river runs edge to edge: a seeded line with a meander (an offset per STEP_M along it, so a
## grid point finds its place on the river in O(1)), pushed off the module pads. Its surface
## comes down from the higher end in a running minimum of the ground along it, at least
## "grade" a metre and never more than "drop_max_m" in all, so it always flows downhill; its
## channel is cut "depth_m" under that, its banks rise "bank_h_m" over "bank_w_m", and its
## valley blends back into the land over "valley_w_m" (low ground beside it fills up to the
## floodplain, high ground is cut back): the valley it would have cut. A stream springs from a
## seeded point and wanders downhill toward the river (or a lake, or the zone's edge), joining
## it at the river's level. A lake or pond is a wobbly bowl whose level is its lowest rim.
## Pads keep their ground: the valley fades out within PAD_KEEP_FAR_M of one, and every
## river or stream keeps its channel PAD_CLEAR_M off them.
##
## Queries (any peer): surface_at(x, z) (ZoneTerrain.water_height adds it to the sea's),
## depth_at, flow_at; too_deep() keeps deep water out of the navigation mesh
## (ZoneTerrain.triangles_in), nav_faces_in() puts the bridges in (ZoneNav), keeps_clear() keeps
## the scatter out of the water (ZoneScatter). Numbers Proposed.

## Samples along a river or stream (m).
const STEP_M := 8.0
## A river's or stream's channel keeps this far (m) beyond its banks off every pad, and a river
## CORNER_CLEAR_M off every corner of a road or trail (a patrol's waypoints).
const PAD_CLEAR_M := 14.0
const CORNER_CLEAR_M := 6.0
## A push off a pad tapers back over this far along the river (m).
const PAD_PUSH_RAMP_M := 140.0
## The valley carve fades out between these distances from a pad (m): pads keep their ground.
const PAD_KEEP_NEAR_M := 4.0
const PAD_KEEP_FAR_M := 42.0
const KEEP_STEP_M := 8.0
## Candidate lines tried for a river: the one furthest from the pads wins.
const RIVER_TRIES := 10
## The water mesh reaches this share of the bank's width past the water's edge (under the bank).
const STRIP_BANK_SHARE := 0.6
## A stream's first stretch (m) widens and deepens from a spring.
const SPRING_M := 48.0
## A stream whose surface would be held up over lower ground for more than this share of it (it
## joins a lake higher than the land it crosses) is tried again from another spring.
const PERCHED_MAX := 0.1
## Lakes keep this far (m) from the zone's edge, pads, roads, rivers and each other.
const LAKE_EDGE_M := 220.0
const LAKE_GAP_M := 30.0
## Ground deeper under the water than this (m) is left out of the navigation mesh (the sea's
## ZoneTerrain.NAV_WATER_M): the AI wades fords and shallows, and crosses deep water on bridges.
const NAV_WATER_M := 0.9
## The water's look: shallow and deep colours (water_surface.gdshader).
const SHADER := preload("res://scripts/world/water_surface.gdshader")
const REED_SEE_M := 260.0
## Bump when what the water keeps the scatter off changes (keeps_clear, ZoneBridges.covers).
const LAYOUT_VERSION := 1
## The riparian band (m past the banks) where ZoneScatter's "wadi_groves" grow: marked in the
## terrain's riverbed weight (ZoneTerrain.bed_at) at RIPARIAN_BED, under the sand tint's start.
const RIPARIAN_M := 45.0
const RIPARIAN_BED := 38

## Defaults for a preset's "water" parts (each key optional in the data).
const RIVER_DEFAULTS := {"count": 1, "width_m": [22.0, 30.0], "depth_m": 2.1, "bank_h_m": 1.5, "bank_w_m": 7.0, "valley_m": 3.0,
	"valley_w_m": 130.0, "meander_m": 170.0, "meander_wavelength_m": 560.0, "grade": 0.0015, "drop_max_m": 6.0, "flow_ms": 0.8, "reeds": 0.3}
const STREAM_DEFAULTS := {"count": [1, 1], "width_m": [4.5, 6.5], "depth_m": 0.45, "bank_h_m": 0.6, "bank_w_m": 4.0, "valley_m": 1.2,
	"valley_w_m": 24.0, "length_m": [350.0, 900.0], "grade": 0.006, "drop_max_m": 14.0, "flow_ms": 0.5, "reeds": 0.45}
const LAKE_DEFAULTS := {"count": [0, 1], "radius_m": [45.0, 80.0], "depth_m": 3.5, "bank_h_m": 0.8, "bank_w_m": 6.0, "valley_w_m": 40.0, "reeds": 0.35}
## Farmland's irrigation channels (the preset's water "channels"; their lines are ZoneFeatures'
## field edges, queue item 1.3): shallow, narrow, slow, in a low cut. Proposed.
const CHANNEL_DEFAULTS := {"width_m": [2.2, 2.8], "depth_m": 0.3, "bank_h_m": 0.35, "bank_w_m": 2.5, "valley_m": 0.55, "valley_w_m": 6.0,
	"grade": 0.0005, "drop_max_m": 4.0, "flow_ms": 0.25, "reeds": 0.04}
## Frozen water (a part's "frozen": true, the snow preset; queue item 1.3): ice to walk on, drawn
## ICE_DROP_M under the surface (the part's depth is a little more: the ice lies on the bed), never
## waded or swum (it's not in the wet map: surface_at and the navigation see dry ground).
const ICE_DROP_M := 0.05
const POND_DEFAULTS := {"count": [1, 2], "radius_m": [12.0, 22.0], "depth_m": 1.4, "bank_h_m": 0.5, "bank_w_m": 4.0, "valley_w_m": 18.0, "reeds": 0.6}
## Along a river with no crossing for this far (m), a ford or footbridge is added.
const CROSSING_GAP_M := 450.0
## Two crossings of one river closer than this (m) are one.
const CROSSING_MIN_GAP_M := 45.0
## Crossings keep this far (m) inside the zone's edge.
const CROSSING_EDGE_M := 90.0
## A ford: the river shallows to FORD_DEPTH_M over FORD_HALF_M either side, widens by
## FORD_WIDEN and its banks ease out to FORD_BANK_W_M (a vehicle drives down and up them).
const FORD_DEPTH_M := 0.45
const STREAM_FORD_DEPTH_M := 0.3
const FORD_HALF_M := 16.0
const FORD_WIDEN := 1.3
const FORD_BANK_W_M := 11.0
## A culvert: the road crosses a stream on an embankment over a pipe (CULVERT_TOP_M over the
## water, ROAD_HALF_M wide on top, sides sloping 1 in EMBANK_RUN).
const CULVERT_MAX_W_M := 7.0
const CULVERT_TOP_M := 1.4
const ROAD_HALF_M := 3.6
const EMBANK_RUN := 1.6

var terrain: ZoneTerrain
var spec := {}
## Every body of water, in carve order: rivers, then lakes and ponds, then streams. A river or
## stream: {"kind", "pts" (PackedVector2Array), "w" (surface), "half" (half the water's width),
## "depth", "bank_w" (per sample), "bank_h", "valley_w", "flow_ms", "down" (+1: flows toward
## higher samples), "lo", "hi" (the samples inside the zone)}; a river also "dir", "perp", "t0",
## "off". A lake or pond: {"kind", "centre", "r", "shape" (radius per LAKE_BINS of angle),
## "level", "depth", "bank_h", "bank_w", "valley_w"}.
var bodies: Array = []
## The ways across (ZoneBridges builds them): {"id", "kind" (ZoneBridges.CONCRETE, TRUSS, FOOT,
## FORD, CULVERT), "body", "u" (sample), "pos" (Vector2), "dir" (Vector2: the way across),
## "road" (index in the def's roads, -1 for an added one)}.
var crossings: Array = []
var bridges: ZoneBridges
## Grid vertex index -> Vector3(surface, body, sample) where there is water over it.
var _wet := {}
## The same for frozen water (_ice), and the frozen bodies' indices.
var _ice := {}
var _frozen := {}
var _mask := PackedByteArray()  # 1 where a body's water lies (later bodies only cut deeper there)
var _shore := PackedByteArray()  # 0..255: how much the ground is a wet bank (ZoneTerrain colours)
var _keep := PackedFloat32Array()  # the pad keep weight on a KEEP_STEP_M grid
var _keep_n := 0
var _half := 0.0
var _rng := RandomNumberGenerator.new()
var _built_visuals := false
var _roads: Array = []  # the def's roads as [Vector2, Vector2]
var _surface_grid := PackedFloat32Array()
## How long each part of the carve took (ms), for checks and the zone's log line.
var timings := {}

const LAKE_BINS := 48


## Carves `t`'s water into its heights (after the pads; before its min/max and shore) and plans
## the crossings over `def`'s roads. Null when the preset has no water.
static func carve(t: ZoneTerrain, def: Dictionary) -> ZoneWater:
	var water_spec: Dictionary = t.preset.get("water", {})
	if water_spec.is_empty() or def.get("no_water", false):
		return null
	var w := ZoneWater.new()
	w.name = "Water"
	w.terrain = t
	w.spec = water_spec
	w._generate(def)
	return w


func _generate(def: Dictionary) -> void:
	_half = terrain.size_m * 0.5
	_rng.seed = terrain.seed_value ^ 0x5A7E12
	var n := terrain.points
	_mask.resize(n * n)
	_shore.resize(n * n)
	var started := Time.get_ticks_usec()
	_build_keep()
	_lap("keep", started)
	var roads: Array = []
	for road: Array in def.get("roads", []):
		roads.append([Vector2(float(road[0][0]), float(road[0][1])), Vector2(float(road[1][0]), float(road[1][1]))])
	_roads = roads
	var river_spec: Dictionary = RIVER_DEFAULTS.merged(spec.get("rivers", {}), true) if spec.has("rivers") else {}
	if not river_spec.is_empty():
		for k in int(river_spec.count):
			started = Time.get_ticks_usec()
			var r := _make_river(river_spec, k)
			_lap("river_line", started)
			if r.is_empty():
				continue
			bodies.append(r)
			_plan_crossings(bodies.size() - 1, roads)
			started = Time.get_ticks_usec()
			_carve_line(bodies.size() - 1)
			_lap("river_carve", started)
	for part: String in ["lakes", "ponds"]:
		if not spec.has(part):
			continue
		var s: Dictionary = (LAKE_DEFAULTS if part == "lakes" else POND_DEFAULTS).merged(spec[part], true)
		for k in _count(s.count):
			started = Time.get_ticks_usec()
			var lake := _make_lake(s, part == "ponds", roads)
			if not lake.is_empty():
				_freeze_next(s, lake)
				bodies.append(lake)
				_carve_lake(bodies.size() - 1)
			_lap("lakes", started)
	if spec.has("streams"):
		var s: Dictionary = STREAM_DEFAULTS.merged(spec.streams, true)
		for k in _count(s.count):
			started = Time.get_ticks_usec()
			var stream := _make_stream(s, k)
			_lap("stream_line", started)
			if stream.is_empty():
				continue
			_freeze_next(s, stream)
			bodies.append(stream)
			_plan_crossings(bodies.size() - 1, roads)
			started = Time.get_ticks_usec()
			_carve_line(bodies.size() - 1)
			_lap("stream_carve", started)
	if spec.has("channels") and terrain.features:
		# Farmland's irrigation channels along its field edges (ZoneFeatures, queue item 1.3).
		var s: Dictionary = CHANNEL_DEFAULTS.merged(spec.channels, true)
		started = Time.get_ticks_usec()
		for pts: PackedVector2Array in terrain.features.channel_lines():
			add_line("channel", pts, s)
		_lap("channels", started)
	for c: Dictionary in crossings:
		if String(c.kind) == ZoneBridges.CULVERT:
			_embank(c)
	started = Time.get_ticks_usec()
	bridges = ZoneBridges.new()
	bridges.name = "Bridges"
	add_child(bridges)
	bridges.setup(self)
	_lap("bridges", started)


## The body about to be appended (`body`, of a part with spec `s`) is frozen if the part says so.
func _freeze_next(s: Dictionary, body: Dictionary) -> void:
	if bool(s.get("frozen", false)):
		body["frozen"] = true
		_frozen[bodies.size()] = true


## A watercourse laid out by another script (ZoneFeatures: farmland's irrigation channels, kind
## "channel"): `pts` a polyline about STEP_M a step inside the zone, its surface filled (_fill_line)
## and carved like a stream's with spec `s`, its road crossings culverts or fords. Called while the
## water is carved (_generate), before the culverts' embankments and the bridges. Its body index,
## -1 if it's too short or would run perched over lower ground.
func add_line(kind: String, pts: PackedVector2Array, s: Dictionary) -> int:
	if pts.size() < 4:
		return -1
	var body := {"kind": kind, "pts": pts, "lo": 0, "hi": pts.size() - 1}
	_fill_line(body, s, _range(s.width_m))
	if float(body.perched) > PERCHED_MAX:
		return -1
	_freeze_next(s, body)
	bodies.append(body)
	_plan_crossings(bodies.size() - 1, _roads)
	_carve_line(bodies.size() - 1)
	return bodies.size() - 1


func _lap(part: String, since: int) -> void:
	timings[part] = float(timings.get(part, 0.0)) + (Time.get_ticks_usec() - since) / 1000.0


## The carve's total time (ms).
func carve_ms() -> float:
	var total := 0.0
	for k: String in timings:
		total += float(timings[k])
	return total


func _count(v: Variant) -> int:
	if v is Array:
		return _rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


func _range(v: Variant) -> float:
	if v is Array:
		return _rng.randf_range(float(v[0]), float(v[1]))
	return float(v)


# --- Pads keep their ground -----------------------------------------------------------------

## The pad keep weight on a KEEP_STEP_M grid: 0 within PAD_KEEP_NEAR_M of a pad, 1 from
## PAD_KEEP_FAR_M (and everywhere away from them).
func _build_keep() -> void:
	_keep_n = ceili(terrain.size_m / KEEP_STEP_M) + 1
	_keep.resize(_keep_n * _keep_n)
	_keep.fill(1.0)
	for pad: Array in terrain.pads:
		var r: Rect2 = pad[0]
		var reach := r.grow(PAD_KEEP_FAR_M)
		var i0 := clampi(floori((reach.position.x + _half) / KEEP_STEP_M), 0, _keep_n - 1)
		var i1 := clampi(ceili((reach.end.x + _half) / KEEP_STEP_M), 0, _keep_n - 1)
		var j0 := clampi(floori((reach.position.y + _half) / KEEP_STEP_M), 0, _keep_n - 1)
		var j1 := clampi(ceili((reach.end.y + _half) / KEEP_STEP_M), 0, _keep_n - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(i * KEEP_STEP_M - _half, j * KEEP_STEP_M - _half)
				var k := smoothstep(PAD_KEEP_NEAR_M, PAD_KEEP_FAR_M, ZoneTerrain._distance_to_rect(p, r))
				_keep[i + j * _keep_n] = minf(_keep[i + j * _keep_n], k)


## The distance from `p` to the nearest pad (INF with none).
func _pad_distance(p: Vector2) -> float:
	var d := INF
	for pad: Array in terrain.pads:
		d = minf(d, ZoneTerrain._distance_to_rect(p, pad[0]))
	return d


func _inside(p: Vector2, margin := 0.0) -> bool:
	return absf(p.x) <= _half - margin and absf(p.y) <= _half - margin


# --- Rivers ---------------------------------------------------------------------------------

## A river edge to edge: RIVER_TRIES seeded lines (direction, offset), the one whose meander
## keeps furthest from the pads, then pushed off any it still comes near. {} if none fits.
func _make_river(s: Dictionary, k: int) -> Dictionary:
	var meander := FastNoiseLite.new()
	meander.seed = terrain.seed_value + 40 + k
	meander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	meander.fractal_type = FastNoiseLite.FRACTAL_FBM
	meander.fractal_octaves = 2
	meander.frequency = 1.0 / float(s.meander_wavelength_m)
	var width := _range(s.width_m)
	var bank_w := float(s.bank_w_m)
	var need := width * 0.5 + bank_w + PAD_CLEAR_M
	var best := {}
	var best_clear := -INF
	for attempt in RIVER_TRIES:
		var dir := Vector2.from_angle(_rng.randf() * PI)
		var offset := _rng.randf_range(-0.28, 0.28) * terrain.size_m
		var perp := Vector2(-dir.y, dir.x)
		var reach := _half * (absf(dir.x) + absf(dir.y)) + STEP_M * 2.0
		var n := ceili(2.0 * reach / STEP_M) + 1
		var off := PackedFloat32Array()
		off.resize(n)
		var clear := INF
		for i in n:
			var t := -reach + i * STEP_M
			off[i] = offset + meander.get_noise_1d(t + attempt * 977.0) * float(s.meander_m)
			var p := dir * t + perp * off[i]
			if _inside(p):
				clear = minf(clear, _pad_distance(p))
		if clear > best_clear:
			best_clear = clear
			best = {"dir": dir, "perp": perp, "t0": -reach, "off": off}
	if best.is_empty():
		return {}
	var body := {"kind": "river", "dir": best.dir, "perp": best.perp, "t0": best.t0, "off": best.off}
	var corners: Array = []
	for road: Array in _roads:
		for p: Vector2 in road:
			corners.append([Rect2(p, Vector2.ZERO), width * 0.5 + bank_w + CORNER_CLEAR_M])
	_push_off(body, corners)
	var pads: Array = []
	for pad: Array in terrain.pads:
		pads.append([pad[0], need])
	_push_off(body, pads)
	var off: PackedFloat32Array = body.off
	var n := off.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	var lo := n
	var hi := -1
	for i in n:
		pts[i] = (body.dir as Vector2) * (float(body.t0) + i * STEP_M) + (body.perp as Vector2) * off[i]
		if _inside(pts[i]):
			lo = mini(lo, i)
			hi = maxi(hi, i)
	if hi - lo < 20:
		return {}
	body.lo = maxi(lo - 1, 0)
	body.hi = mini(hi + 1, n - 1)
	body.pts = pts
	_fill_line(body, s, width)
	return body


## Pushes a river's offsets off every rect in `keep` ([Rect2, how far to keep off it]) it comes
## near, on the side it was nearer, easing back over PAD_PUSH_RAMP_M along it.
func _push_off(body: Dictionary, keep: Array) -> void:
	var dir: Vector2 = body.dir
	var perp: Vector2 = body.perp
	var off: PackedFloat32Array = body.off
	var t0 := float(body.t0)
	for entry: Array in keep:
		var r: Rect2 = entry[0]
		var need := float(entry[1])
		var a_lo := INF
		var a_hi := -INF
		var s_lo := INF
		var s_hi := -INF
		for c: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			a_lo = minf(a_lo, c.dot(dir))
			a_hi = maxf(a_hi, c.dot(dir))
			s_lo = minf(s_lo, c.dot(perp))
			s_hi = maxf(s_hi, c.dot(perp))
		var mid_i := clampi(roundi(((a_lo + a_hi) * 0.5 - t0) / STEP_M), 0, off.size() - 1)
		var up := off[mid_i] > (s_lo + s_hi) * 0.5  # the river passes on the pad's +perp side
		var bound := (s_hi + need) if up else (s_lo - need)
		for i in off.size():
			var t := t0 + i * STEP_M
			var gap := maxf(maxf(a_lo - need - t, t - a_hi - need), 0.0)
			var weight := 1.0 - smoothstep(0.0, PAD_PUSH_RAMP_M, gap)
			if weight <= 0.0:
				continue
			var pushed := lerpf(off[i], bound, weight)
			off[i] = maxf(off[i], pushed) if up else minf(off[i], pushed)
	body.off = off


## A river's or stream's surface, width, depth and banks per sample: the surface a running
## minimum of the ground along it (smoothed) less "valley_m", falling at least "grade" a metre
## from the higher end and at most "drop_max_m" in all.
func _fill_line(body: Dictionary, s: Dictionary, width: float) -> void:
	var pts: PackedVector2Array = body.pts
	var n := pts.size()
	var lo := int(body.lo)
	var hi := int(body.hi)
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		var p := pts[clampi(i, lo, hi)]
		g[i] = terrain.plane_height(p.x, p.y)
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		var sum := 0.0
		var count := 0
		for k in range(maxi(i - 4, lo), mini(i + 5, hi + 1)):
			sum += g[k]
			count += 1
		smooth[i] = sum / maxf(count, 1)
	var down := int(body.get("down", 0))
	if down == 0:
		var third := maxi((hi - lo) / 3, 1)
		var first := 0.0
		var last := 0.0
		for k in third:
			first += smooth[lo + k]
			last += smooth[hi - k]
		down = 1 if first >= last else -1
	body.down = down
	var grade := float(s.grade) * STEP_M
	var vd := float(s.valley_m)
	var drop_max := float(s.drop_max_m)
	var w := PackedFloat32Array()
	w.resize(n)
	var start := lo if down > 0 else hi
	var top := smooth[start] - vd
	var prev := top + grade
	var length := float(hi - lo)
	var floor_level: float = body.get("end_level", -INF)
	var perched := 0
	for k in range(hi - lo + 1):
		var i := lo + k if down > 0 else hi - k
		var v := minf(prev - grade, smooth[i] - vd)
		v = maxf(v, top - drop_max * (k / maxf(length, 1.0)) - 1.0)
		if floor_level - v > 0.5:
			perched += 1  # held up by what it runs into, over lower ground
		v = maxf(v, floor_level)
		w[i] = v
		prev = v
	body.perched = float(perched) / maxf(length, 1.0)
	for i in range(0, lo):
		w[i] = w[lo]
	for i in range(hi + 1, n):
		w[i] = w[hi]
	var half := PackedFloat32Array()
	var depth := PackedFloat32Array()
	var bank_w := PackedFloat32Array()
	half.resize(n)
	depth.resize(n)
	bank_w.resize(n)
	var wobble := FastNoiseLite.new()
	wobble.seed = terrain.seed_value + 61 + bodies.size()
	wobble.frequency = 1.0 / 240.0
	var spring := String(body.kind) == "stream"
	for i in n:
		var taper := 1.0
		if spring:
			var from_source := absf(i - start) * STEP_M
			taper = lerpf(0.4, 1.0, smoothstep(0.0, SPRING_M, from_source))
		half[i] = width * 0.5 * (1.0 + 0.15 * wobble.get_noise_1d(i * STEP_M)) * taper
		depth[i] = float(s.depth_m) * taper
		bank_w[i] = float(s.bank_w_m)
	body.w = w
	body.half = half
	body.depth = depth
	body.bank_w = bank_w
	body.bank_h = float(s.bank_h_m)
	body.valley_w = float(s.valley_w_m)
	body.flow_ms = float(s.flow_ms)
	body.reeds = float(s.reeds)


# --- Streams --------------------------------------------------------------------------------

## A stream from a seeded spring, wandering downhill toward the nearest river (or lake, or the
## zone's edge) and ending in it. {} if no spring fits or it never gets there.
func _make_stream(s: Dictionary, k: int) -> Dictionary:
	var width := _range(s.width_m)
	var need := width * 0.5 + float(s.bank_w_m) + PAD_CLEAR_M
	var wiggle := FastNoiseLite.new()
	wiggle.seed = terrain.seed_value + 90 + k
	wiggle.frequency = 1.0 / 90.0
	for attempt in 24:
		var length := _range(s.length_m)
		var src := Vector2(_rng.randf_range(-_half + 200.0, _half - 200.0), _rng.randf_range(-_half + 200.0, _half - 200.0))
		if _pad_distance(src) < need + 20.0 or _wet_near(src, 30.0):
			continue
		var target := _stream_target(src)
		var dist := src.distance_to(target)
		if dist < length * 0.5 or dist > length * 1.6:
			continue
		var pts := PackedVector2Array([src])
		var dir := (target - src).normalized()
		var joined := -1  # the body it ends in (-2: the edge)
		var end_level := -INF
		for step in int(dist * 2.0 / STEP_M):
			var p: Vector2 = pts[pts.size() - 1]
			var to_target := (target - p).normalized()
			var e := 3.0
			var downhill := Vector2(terrain.plane_height(p.x - e, p.y) - terrain.plane_height(p.x + e, p.y),
				terrain.plane_height(p.x, p.y - e) - terrain.plane_height(p.x, p.y + e))
			downhill = downhill.normalized() if downhill.length() > 0.02 else Vector2.ZERO
			var want := (to_target * 0.6 + downhill * 0.4).normalized().rotated(wiggle.get_noise_1d(step * STEP_M) * 0.9)
			for turn in 6:  # round a pad
				var next := p + want * STEP_M
				if _pad_distance(next) >= need:
					break
				want = want.rotated(0.5 if turn % 2 == 0 else -1.0)
			dir = dir.slerp(want, 0.35).normalized()
			var q := p + dir * STEP_M
			pts.append(q)
			if not _inside(q, 10.0):
				joined = -2
				break
			var hit := _water_body_at(q)
			if hit >= 0:
				joined = hit
				end_level = _surface_of(hit, q)
				break
		if joined == -1 or pts.size() < 25:
			continue
		var body := {"kind": "stream", "pts": pts, "lo": 0, "hi": pts.size() - 1, "down": 1, "end_level": end_level, "joins": joined}
		_fill_line(body, s, width)
		if float(body.perched) > PERCHED_MAX:
			continue  # it would run on a dyke over lower ground to reach what it joins: another spring
		return body
	return {}


## Where a stream from `src` heads: the nearest point of a river's water, else of a lake's,
## else the nearest edge.
func _stream_target(src: Vector2) -> Vector2:
	var best := INF
	var at := src
	for b: Dictionary in bodies:
		if String(b.kind) == "river":
			var pts: PackedVector2Array = b.pts
			for i in range(int(b.lo), int(b.hi) + 1, 4):
				if _inside(pts[i], 150.0) and pts[i].distance_to(src) < best:
					best = pts[i].distance_to(src)
					at = pts[i]
		elif String(b.kind) == "lake" and terrain.plane_height(src.x, src.y) > float(b.level) + 4.0:
			var c: Vector2 = b.centre
			if c.distance_to(src) < best:
				best = c.distance_to(src)
				at = c
	if best < INF:
		return at
	var edges := [Vector2(src.x, -_half), Vector2(src.x, _half), Vector2(-_half, src.y), Vector2(_half, src.y)]
	edges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(src) < b.distance_to(src))
	return edges[0]


## The body whose water is at `p` (a grid vertex near it is wet), -1 for none.
func _water_body_at(p: Vector2) -> int:
	var i := roundi((p.x + _half) / ZoneTerrain.CELL_M)
	var j := roundi((p.y + _half) / ZoneTerrain.CELL_M)
	var idx := clampi(i, 0, terrain.points - 1) + clampi(j, 0, terrain.points - 1) * terrain.points
	var found: Variant = _wet.get(idx, _ice.get(idx))  # (a stream runs into a frozen pond too)
	if found != null:
		var v: Vector3 = found
		if not _wet.has(idx) or v.x - terrain.plane_height(p.x, p.y) > 0.2:  # (ice lies on its bed: any of it)
			return int(v.y)
	return -1


func _wet_near(p: Vector2, r: float) -> bool:
	for d: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if _water_body_at(p + d) >= 0:
			return true
	return false


func _surface_of(body_i: int, p: Vector2) -> float:
	var i := roundi((p.x + _half) / ZoneTerrain.CELL_M)
	var j := roundi((p.y + _half) / ZoneTerrain.CELL_M)
	var idx := clampi(i, 0, terrain.points - 1) + clampi(j, 0, terrain.points - 1) * terrain.points
	var found: Variant = _wet.get(idx, _ice.get(idx))
	return float((found as Vector3).x) if found != null else -INF


# --- Lakes and ponds ------------------------------------------------------------------------

func _make_lake(s: Dictionary, pond: bool, roads: Array) -> Dictionary:
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = terrain.seed_value + (130 if pond else 120) + bodies.size()
	shape_noise.frequency = 0.9
	for attempt in 40:
		var r := _range(s.radius_m)
		var rim := r + float(s.bank_w_m) + 6.0
		var c := Vector2(_rng.randf_range(-_half + LAKE_EDGE_M, _half - LAKE_EDGE_M), _rng.randf_range(-_half + LAKE_EDGE_M, _half - LAKE_EDGE_M))
		if _pad_distance(c) < rim + LAKE_GAP_M:
			continue
		var clear := true
		for road: Array in roads:
			clear = clear and Geometry2D.get_closest_point_to_segment(c, road[0], road[1]).distance_to(c) > rim + 12.0
		for b: Dictionary in bodies:
			if String(b.kind) == "lake":
				clear = clear and c.distance_to(b.centre) > rim + float(b.r) + LAKE_GAP_M * 2.0
			else:
				var pts: PackedVector2Array = b.pts
				for i in range(int(b.lo), int(b.hi) + 1, 2):
					clear = clear and pts[i].distance_to(c) > rim + float((b.half as PackedFloat32Array)[i]) + float((b.bank_w as PackedFloat32Array)[i]) + LAKE_GAP_M
		if not clear:
			continue
		# Its level: the lowest of its rim, so it never spills; not on a steep slope.
		var low := INF
		var high := -INF
		var shape := PackedFloat32Array()
		shape.resize(LAKE_BINS)
		for a in LAKE_BINS:
			var ang := a * TAU / LAKE_BINS
			shape[a] = r * (1.0 + 0.2 * shape_noise.get_noise_2d(cos(ang) * 1.3 + attempt * 5.0, sin(ang) * 1.3))
			var p := c + Vector2.from_angle(ang) * (shape[a] + float(s.bank_w_m))
			var h := terrain.plane_height(p.x, p.y)
			low = minf(low, h)
			high = maxf(high, h)
		if high - low > r * 0.1 + 2.0:
			continue
		return {"kind": "lake", "pond": pond, "centre": c, "r": r, "shape": shape, "level": low - float(s.bank_h_m) * 0.5,
			"depth": float(s.depth_m), "bank_h": float(s.bank_h_m), "bank_w": float(s.bank_w_m), "valley_w": float(s.valley_w_m), "reeds": float(s.reeds), "flow_ms": 0.0}
	return {}


## Lake `b`'s shore radius toward angle `ang`.
static func lake_radius(b: Dictionary, ang: float) -> float:
	var shape: PackedFloat32Array = b.shape
	var f := fposmod(ang / TAU * LAKE_BINS, LAKE_BINS)
	var i := floori(f) % LAKE_BINS
	return lerpf(shape[i], shape[(i + 1) % LAKE_BINS], f - floori(f))


# --- Crossings ------------------------------------------------------------------------------

## The ways across body `bi`: where a road crosses it (a bridge over a river, a culvert or ford
## over a stream), and on a river a ford or footbridge in every stretch CROSSING_GAP_M long
## without one. Fords shape the channel (before it's carved).
func _plan_crossings(bi: int, roads: Array) -> void:
	var b: Dictionary = bodies[bi]
	var pts: PackedVector2Array = b.pts
	var river := String(b.kind) == "river"
	var at: Array[float] = []
	for ri in roads.size():
		var a: Vector2 = roads[ri][0]
		var e: Vector2 = roads[ri][1]
		for i in range(int(b.lo), int(b.hi)):
			var hit: Variant = Geometry2D.segment_intersects_segment(a, e, pts[i], pts[i + 1])
			if hit == null or not _inside(hit, CROSSING_EDGE_M):
				continue
			var u := i + (hit as Vector2).distance_to(pts[i]) / maxf(pts[i].distance_to(pts[i + 1]), 0.01)
			if at.any(func(v: float) -> bool: return absf(v - u) * STEP_M < CROSSING_MIN_GAP_M):
				continue
			var kind := ""
			if river:
				var weights: Dictionary = spec.get("bridges", {"concrete": 0.6, "truss": 0.4})
				kind = ZoneBridges.CONCRETE if _rng.randf() < float(weights.get("concrete", 0.6)) / maxf(float(weights.get("concrete", 0.6)) + float(weights.get("truss", 0.4)), 0.01) else ZoneBridges.TRUSS
			else:
				var narrow := float((b.half as PackedFloat32Array)[i]) * 2.0 <= CULVERT_MAX_W_M
				kind = ZoneBridges.CULVERT if narrow and _rng.randf() < float(spec.get("culvert_share", 0.65)) else ZoneBridges.FORD
			at.append(u)
			_add_crossing(bi, u, kind, (e - a).normalized(), ri)
	if river:
		_fill_gaps(bi, at)


## River `bi`'s added crossings (fords and footbridges): no stretch longer than the gap goes
## without one between its road crossings `at` (samples), and none of its ends inside the zone
## further than half the gap from one.
func _fill_gaps(bi: int, at: Array[float]) -> void:
	var b: Dictionary = bodies[bi]
	var pts: PackedVector2Array = b.pts
	var gap := float(spec.get("crossing_gap_m", CROSSING_GAP_M)) / STEP_M
	var first := -1.0
	var last := -1.0
	for u in range(int(b.lo), int(b.hi)):
		if _inside(pts[u], CROSSING_EDGE_M + 40.0):
			if first < 0.0:
				first = u
			last = u
	if first < 0.0 or last <= first:
		return
	var marks := at.duplicate()
	marks.sort()
	var wanted: Array[float] = []
	if marks.is_empty():
		var n := maxi(ceili((last - first) / gap), 1)
		for k in n:
			wanted.append(first + (last - first) * (k + 0.5) / n)
	else:
		var u: float = marks[0]
		while u - first > gap * 0.5:
			u = maxf(u - gap, first)
			wanted.append(u)
		for k in range(1, marks.size()):
			var a: float = marks[k - 1]
			var e: float = marks[k]
			var n := ceili((e - a) / gap) - 1
			for m in n:
				wanted.append(a + (e - a) * (m + 1) / (n + 1))
		u = marks[marks.size() - 1]
		while last - u > gap * 0.5:
			u = minf(u + gap, last)
			wanted.append(u)
	for u in wanted:
		var kind := ZoneBridges.FOOT if _rng.randf() < float(spec.get("footbridge_share", 0.5)) else ZoneBridges.FORD
		var along := tangent(b, u)
		_add_crossing(bi, u, kind, Vector2(-along.y, along.x), -1)


func _add_crossing(bi: int, u: float, kind: String, dir: Vector2, road: int) -> void:
	var b: Dictionary = bodies[bi]
	var pts: PackedVector2Array = b.pts
	var i := clampi(floori(u), 0, pts.size() - 2)
	var pos := pts[i].lerp(pts[i + 1], u - i)
	crossings.append({"id": "x%d" % crossings.size(), "kind": kind, "body": bi, "u": u, "pos": pos, "dir": dir, "road": road})
	if kind == ZoneBridges.FORD:
		var river := String(b.kind) == "river"
		var depth: PackedFloat32Array = b.depth
		var half: PackedFloat32Array = b.half
		var bank_w: PackedFloat32Array = b.bank_w
		var reach := ceili(FORD_HALF_M * 2.0 / STEP_M)
		for k in range(maxi(i - reach, 0), mini(i + reach + 2, pts.size())):
			var t := 1.0 - smoothstep(FORD_HALF_M * 0.5, FORD_HALF_M * 2.0, absf(k - u) * STEP_M)
			depth[k] = lerpf(depth[k], minf(depth[k], FORD_DEPTH_M if river else STREAM_FORD_DEPTH_M), t)
			half[k] *= lerpf(1.0, FORD_WIDEN, t)
			bank_w[k] = lerpf(bank_w[k], maxf(bank_w[k], FORD_BANK_W_M if river else FORD_BANK_W_M * 0.6), t)
		b.depth = depth
		b.half = half
		b.bank_w = bank_w


## A culvert's embankment: the ground along the road over the stream raised to the road's level
## over its pipe (CULVERT_TOP_M over the water), sloping down 1 in EMBANK_RUN either side.
func _embank(c: Dictionary) -> void:
	var b: Dictionary = bodies[int(c.body)]
	var u := float(c.u)
	var i := clampi(floori(u), 0, (b.pts as PackedVector2Array).size() - 2)
	var w := lerpf((b.w as PackedFloat32Array)[i], (b.w as PackedFloat32Array)[i + 1], u - i)
	var reach := float((b.half as PackedFloat32Array)[i]) + float((b.bank_w as PackedFloat32Array)[i]) + 6.0
	var top := maxf(w + CULVERT_TOP_M, w + float(b.bank_h))
	c["top"] = top
	c["water"] = w
	var pos: Vector2 = c.pos
	var along: Vector2 = c.dir
	var side := Vector2(-along.y, along.x)
	var width := ROAD_HALF_M + (top - (w - float((b.depth as PackedFloat32Array)[i]))) * EMBANK_RUN + 2.0
	var n := terrain.points
	var lo := Vector2i(floori((pos.x - reach - width + _half) / ZoneTerrain.CELL_M), floori((pos.y - reach - width + _half) / ZoneTerrain.CELL_M))
	var hi := Vector2i(ceili((pos.x + reach + width + _half) / ZoneTerrain.CELL_M), ceili((pos.y + reach + width + _half) / ZoneTerrain.CELL_M))
	for j in range(maxi(lo.y, 0), mini(hi.y + 1, n)):
		for ii in range(maxi(lo.x, 0), mini(hi.x + 1, n)):
			var p := Vector2(ii * ZoneTerrain.CELL_M - _half, j * ZoneTerrain.CELL_M - _half) - pos
			var a := absf(p.dot(along))
			var s := absf(p.dot(side))
			if a > reach or s > width:
				continue
			var idx := ii + j * n
			var h := terrain.heights[idx]
			var raise := top - maxf(s - ROAD_HALF_M, 0.0) / EMBANK_RUN
			raise = lerpf(raise, h, smoothstep(reach - 6.0, reach, a))
			if raise > h:
				terrain.heights[idx] = raise
				if _wet.has(idx) and raise > float((_wet[idx] as Vector3).x) + 0.05:
					_wet.erase(idx)
					_mask[idx] = 0


# --- Carving --------------------------------------------------------------------------------

## The ground's target at distance `d` from the water's middle (or a lake's shore, `d` from its
## centre line outward: see _carve_lake) over ground `h`: the channel (full depth to 45% of the
## half width, easing up to just under the surface at the water's edge), the bank rising to the
## floor (surface + bank_h) over bank_w, then the valley blending back into the land.
static func profile(h: float, d: float, w: float, half: float, depth: float, bank_w: float, bank_h: float, valley_w: float) -> float:
	var edge := w - minf(0.25, depth * 0.5)
	var floor_h := w + bank_h
	if d <= half:
		return lerpf(w - depth, edge, smoothstep(half * 0.45, half, d))
	if d <= half + bank_w:
		return lerpf(edge, floor_h, smoothstep(half, half + bank_w, d))
	return lerpf(floor_h, h, smoothstep(0.0, valley_w, d - half - bank_w))


## Sets grid vertex `idx` (at (x, z), in `heights`, the terrain's own array) for a body `d` from
## its water's middle: the profile (inlined: this runs for every vertex of every valley), the
## valley faded out near pads, only ever cutting deeper where an earlier body's water lies, and
## the wet map, the bank tint and the riparian band marked.
func _apply(heights: PackedFloat32Array, bed: PackedByteArray, idx: int, x: float, z: float, d: float, w: float, half: float, depth: float, bank_w: float, bank_h: float, valley_w: float, body_i: int, u: float) -> void:
	var h := heights[idx]
	var inner := half + bank_w
	var t := 0.0
	if d <= half:
		var a := clampf((d - half * 0.45) / (half * 0.55), 0.0, 1.0)
		t = w - depth + (depth - minf(0.25, depth * 0.5)) * a * a * (3.0 - 2.0 * a)
	elif d <= inner:
		var a := (d - half) / bank_w
		var edge := w - minf(0.25, depth * 0.5)
		t = edge + (bank_h + minf(0.25, depth * 0.5)) * a * a * (3.0 - 2.0 * a)
	else:
		var a := minf((d - inner) / valley_w, 1.0)
		var floor_h := w + bank_h
		t = floor_h + (h - floor_h) * a * a * (3.0 - 2.0 * a)
		# Pads keep their ground (the keep grid, bilinear).
		var gx := clampf((x + _half) / KEEP_STEP_M, 0.0, _keep_n - 1.001)
		var gz := clampf((z + _half) / KEEP_STEP_M, 0.0, _keep_n - 1.001)
		var ki := int(gx)
		var kj := int(gz)
		var fx := gx - ki
		var fz := gz - kj
		var r0 := ki + kj * _keep_n
		var r1 := r0 + _keep_n
		var keep := (_keep[r0] + (_keep[r0 + 1] - _keep[r0]) * fx) * (1.0 - fz) + (_keep[r1] + (_keep[r1 + 1] - _keep[r1]) * fx) * fz
		t = h + (t - h) * keep
	heights[idx] = minf(h, t) if _mask[idx] != 0 else t
	if d < half + bank_w * STRIP_BANK_SHARE:
		var into := _ice if _frozen.has(body_i) else _wet  # frozen water: ice, not water to wade
		var old: Variant = into.get(idx)
		if old == null or (old as Vector3).x < w:
			into[idx] = Vector3(w, body_i, u)
		_mask[idx] = 1
	if d < inner + 3.0:
		var a := clampf((d - half * 0.8) / (inner + 3.0 - half * 0.8), 0.0, 1.0)
		_shore[idx] = maxi(_shore[idx], int(255.0 * (1.0 - a * a * (3.0 - 2.0 * a))))
	elif d < inner + RIPARIAN_M and not bed.is_empty() and bed[idx] < RIPARIAN_BED:
		bed[idx] = RIPARIAN_BED  # ZoneScatter's groves grow along it (bed_at), under the sand tint


## The rows (z grid index) a polyline's band of `reach` covers, each with its x index range.
func _row_spans(pts: PackedVector2Array, lo: int, hi: int, reach: float) -> Dictionary:
	var rows := {}
	var n := terrain.points
	for i in range(lo, hi + 1):
		var p := pts[i]
		var j0 := maxi(floori((p.y - reach + _half) / ZoneTerrain.CELL_M), 0)
		var j1 := mini(ceili((p.y + reach + _half) / ZoneTerrain.CELL_M), n - 1)
		var i0 := maxi(floori((p.x - reach + _half) / ZoneTerrain.CELL_M), 0)
		var i1 := mini(ceili((p.x + reach + _half) / ZoneTerrain.CELL_M), n - 1)
		for j in range(j0, j1 + 1):
			if rows.has(j):
				var r: Vector2i = rows[j]
				rows[j] = Vector2i(mini(r.x, i0), maxi(r.y, i1))
			else:
				rows[j] = Vector2i(i0, i1)
	return rows


## Carves river or stream `bi` into the heights. A river finds each vertex's place along it in
## O(1) (its line and meander offsets, inlined); a stream by its segments near the vertex.
func _carve_line(bi: int) -> void:
	var b: Dictionary = bodies[bi]
	var pts: PackedVector2Array = b.pts
	var w: PackedFloat32Array = b.w
	var half: PackedFloat32Array = b.half
	var depth: PackedFloat32Array = b.depth
	var bank_w: PackedFloat32Array = b.bank_w
	var bank_h := float(b.bank_h)
	var valley_w := float(b.valley_w)
	var widest := 0.0
	for i in pts.size():
		widest = maxf(widest, half[i] + bank_w[i])
	var reach := widest + valley_w
	var rows := _row_spans(pts, int(b.lo), int(b.hi), reach)
	var n := terrain.points
	var cell := ZoneTerrain.CELL_M
	var heights := terrain.heights
	var bed := terrain._bed if terrain._bed.size() == heights.size() else PackedByteArray()
	var river := String(b.kind) == "river"
	var grid := {} if river else _segment_grid(pts, reach)
	var dir: Vector2 = b.get("dir", Vector2.ZERO)
	var perp: Vector2 = b.get("perp", Vector2.ZERO)
	var off: PackedFloat32Array = b.get("off", PackedFloat32Array())
	var t0 := float(b.get("t0", 0.0))
	var inv := 1.0 / STEP_M
	var max_u := pts.size() - 1.001
	for j: int in rows:
		var span: Vector2i = rows[j]
		var z := j * cell - _half
		for i in range(span.x, span.y + 1):
			var x := i * cell - _half
			var d := 0.0
			var u := 0.0
			if river:
				u = clampf((x * dir.x + z * dir.y - t0) * inv, 0.0, max_u)
				var k0 := int(u)
				var o0 := off[k0]
				var o1 := off[k0 + 1]
				var sl := (o1 - o0) * inv
				d = absf(x * perp.x + z * perp.y - o0 - (o1 - o0) * (u - k0)) / sqrt(1.0 + sl * sl)
			else:
				var near := _nearest_on_line(pts, grid, x, z)
				d = near.x
				u = clampf(near.y, 0.0, max_u)
			if d > reach:
				continue
			var k := int(u)
			var f := u - k
			var hw := half[k] + (half[k + 1] - half[k]) * f
			var bw := bank_w[k] + (bank_w[k + 1] - bank_w[k]) * f
			if d > hw + bw + valley_w:
				continue
			_apply(heights, bed, i + j * n, x, z, d, w[k] + (w[k + 1] - w[k]) * f, hw, depth[k] + (depth[k + 1] - depth[k]) * f, bw, bank_h, valley_w, bi, u)
	terrain.heights = heights


const SEG_CELL_M := 16.0


## Polyline segments by SEG_CELL_M cell, each listed in every cell its box grown by `reach` covers.
func _segment_grid(pts: PackedVector2Array, reach: float) -> Dictionary:
	var grid := {}
	for i in pts.size() - 1:
		var box := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(reach)
		for cz in range(floori(box.position.y / SEG_CELL_M), floori(box.end.y / SEG_CELL_M) + 1):
			for cx in range(floori(box.position.x / SEG_CELL_M), floori(box.end.x / SEG_CELL_M) + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				var list: PackedInt32Array = grid[key]
				list.append(i)
				grid[key] = list
	return grid


func _nearest_on_line(pts: PackedVector2Array, grid: Dictionary, x: float, z: float) -> Vector2:
	var key := Vector2i(floori(x / SEG_CELL_M), floori(z / SEG_CELL_M))
	if not grid.has(key):
		return Vector2(INF, 0.0)
	var p := Vector2(x, z)
	var best := Vector2(INF, 0.0)
	for i: int in grid[key]:
		var a := pts[i]
		var e := pts[i + 1]
		var ab := e - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(p)
		if d < best.x:
			best = Vector2(d, i + t)
	return best


## Carves lake or pond `bi`: the same profile out from its shore (d = half at the shore line).
func _carve_lake(bi: int) -> void:
	var b: Dictionary = bodies[bi]
	var c: Vector2 = b.centre
	var r := float(b.r)
	var reach := r * 1.25 + float(b.bank_w) + float(b.valley_w)
	var n := terrain.points
	var i0 := maxi(floori((c.x - reach + _half) / ZoneTerrain.CELL_M), 0)
	var i1 := mini(ceili((c.x + reach + _half) / ZoneTerrain.CELL_M), n - 1)
	var j0 := maxi(floori((c.y - reach + _half) / ZoneTerrain.CELL_M), 0)
	var j1 := mini(ceili((c.y + reach + _half) / ZoneTerrain.CELL_M), n - 1)
	var heights := terrain.heights
	var bed := terrain._bed if terrain._bed.size() == heights.size() else PackedByteArray()
	var level := float(b.level)
	var depth := float(b.depth)
	var bank_w := float(b.bank_w)
	var bank_h := float(b.bank_h)
	var valley_w := float(b.valley_w)
	for j in range(j0, j1 + 1):
		var z := j * ZoneTerrain.CELL_M - _half
		for i in range(i0, i1 + 1):
			var x := i * ZoneTerrain.CELL_M - _half
			var v := Vector2(x, z) - c
			var shore := lake_radius(b, v.angle())
			# In the lake's own measure: `half` is its shore radius, `d` how far out from the centre.
			_apply(heights, bed, i + j * n, x, z, v.length(), level, shore, depth, bank_w, bank_h, valley_w, bi, 0.0)


# --- Queries (any peer) ---------------------------------------------------------------------

## The water's surface at (x, z): the highest wet grid corner round it, -INF where there's none.
## Under dry ground (a bank, an embankment) it's below the ground: depth_at is 0 there.
func surface_at(x: float, z: float) -> float:
	var gx := (x + _half) / ZoneTerrain.CELL_M
	var gz := (z + _half) / ZoneTerrain.CELL_M
	var n := terrain.points
	if gx < 0.0 or gz < 0.0 or gx > n - 1 or gz > n - 1:
		return -INF
	var k := mini(int(gx), n - 2) + mini(int(gz), n - 2) * n
	var best := -INF
	for idx: int in [k, k + 1, k + n, k + n + 1]:
		var v: Variant = _wet.get(idx)
		if v != null:
			best = maxf(best, (v as Vector3).x)
	return best


## The water's surface at every grid vertex (-INF where dry), row by row as the terrain's heights
## (the map paints it: MapRender). Built once, when first asked.
func surface_grid() -> PackedFloat32Array:
	if _surface_grid.is_empty():
		_surface_grid.resize(terrain.points * terrain.points)
		_surface_grid.fill(-INF)
		for idx: int in _wet:
			_surface_grid[idx] = (_wet[idx] as Vector3).x
	return _surface_grid


## How deep the water is over the ground at (x, z) (m; 0 where dry).
func depth_at(x: float, z: float) -> float:
	var s := surface_at(x, z)
	return maxf(s - terrain.height_at(x, z), 0.0) if s > -INF else 0.0


## The current at (x, z) (m/s along the ground; zero in a lake or where dry).
func flow_at(x: float, z: float) -> Vector3:
	var n := terrain.points
	var i := clampi(roundi((x + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	var j := clampi(roundi((z + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	var idx := i + j * n
	if not _wet.has(idx):
		return Vector3.ZERO
	var v: Vector3 = _wet[idx]
	var b: Dictionary = bodies[int(v.y)]
	if String(b.kind) == "lake":
		return Vector3.ZERO
	var t := tangent(b, v.z) * float(b.down) * float(b.flow_ms)
	return Vector3(t.x, 0.0, t.y)


## Body `b`'s direction along its samples at sample `u` (unit, toward higher samples).
static func tangent(b: Dictionary, u: float) -> Vector2:
	var pts: PackedVector2Array = b.pts
	var k := clampi(floori(u), 0, pts.size() - 2)
	return (pts[k + 1] - pts[k]).normalized()


## Surface, ground and how deep, at a sample of river or stream `bi` (checks).
func sample_at(bi: int, u: float) -> Dictionary:
	var b: Dictionary = bodies[bi]
	var pts: PackedVector2Array = b.pts
	var k := clampi(floori(u), 0, pts.size() - 2)
	var p := pts[k].lerp(pts[k + 1], u - k)
	var w := lerpf((b.w as PackedFloat32Array)[k], (b.w as PackedFloat32Array)[k + 1], u - k)
	return {"pos": p, "surface": w, "ground": terrain.height_at(p.x, p.y), "depth": w - terrain.height_at(p.x, p.y)}


## Whether a navigation triangle over the ground (grid vertices `p`, `q`, `r`) lies under
## deeper water than NAV_WATER_M on average (ZoneTerrain.triangles_in leaves it out).
func too_deep(p: Vector3, q: Vector3, r: Vector3) -> bool:
	var n := terrain.points
	var best := -INF
	for v: Vector3 in [p, q, r]:
		var idx := clampi(roundi((v.x + _half) / ZoneTerrain.CELL_M), 0, n - 1) + clampi(roundi((v.z + _half) / ZoneTerrain.CELL_M), 0, n - 1) * n
		var wet: Variant = _wet.get(idx)
		if wet != null:
			best = maxf(best, (wet as Vector3).x)
	return best - (p.y + q.y + r.y) / 3.0 > NAV_WATER_M


## Whether scatter (rocks, trees, scrub, grass, props) keeps off (x, z): in the water or on its
## wet bank, or on a bridge's or culvert's way.
func keeps_clear(x: float, z: float) -> bool:
	var n := terrain.points
	var i := clampi(roundi((x + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	var j := clampi(roundi((z + _half) / ZoneTerrain.CELL_M), 0, n - 1)
	if _shore[i + j * n] > 60:
		return true
	return bridges != null and bridges.covers(Vector2(x, z))


## 0..1: how much grid vertex (i, j) is a wet bank (ZoneTerrain tints it toward mud and gravel).
func shore_weight(i: int, j: int) -> float:
	return float(_shore[clampi(i, 0, terrain.points - 1) + clampi(j, 0, terrain.points - 1) * terrain.points]) / 255.0


## The navigation faces of the bridges standing in `area` (ZoneNav bakes them with the ground).
func nav_faces_in(area: Rect2) -> PackedVector3Array:
	return bridges.nav_faces_in(area) if bridges else PackedVector3Array()


## Host: a blast at `pos` (ZoneLevel.server_blast): bridges near it take damage.
func server_blast(pos: Vector3, radius_m: float) -> void:
	if bridges:
		bridges.server_blast(pos, radius_m)


## Rivers, streams and lakes by kind (checks and the map).
func count_of(kind: String) -> int:
	return bodies.filter(func(b: Dictionary) -> bool: return String(b.kind) == kind).size()


## A hash of the water: two peers that built the same zone have the same. LAYOUT_VERSION goes
## in it, so ZoneScatter's cached layouts (keyed on the terrain's checksum) are laid out again
## when what the water keeps clear changes.
func checksum() -> int:
	var parts: Array = [LAYOUT_VERSION]
	for b: Dictionary in bodies:
		parts.append([b.kind, b.get("pts", b.get("centre")), b.get("w", b.get("level"))])
		if b.get("frozen", false):
			parts.append("ice")
	for c: Dictionary in crossings:
		parts.append([c.kind, c.pos])
	return hash(str(parts))


# --- Collision and visuals ------------------------------------------------------------------

## The bridges' and culverts' collision (every peer, headless too).
func build_collision() -> void:
	if bridges:
		bridges.build_collision()


## The water's surfaces, the reeds, and the bridges' looks. Not on a headless server.
func build_visuals() -> void:
	if _built_visuals:
		return
	_built_visuals = true
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var ice := StandardMaterial3D.new()  # frozen water (queue item 1.3): a pale, glossy sheet
	ice.albedo_color = Color("c9dbe4")
	ice.roughness = 0.12
	ice.metallic_specular = 0.7
	for bi in bodies.size():
		var b: Dictionary = bodies[bi]
		var mesh := _lake_mesh(b) if String(b.kind) == "lake" else _line_mesh(b)
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.name = "Surface_%d" % bi
		node.mesh = mesh
		node.material_override = ice if b.get("frozen", false) else material
		if b.get("frozen", false):
			node.position.y = -ICE_DROP_M
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	var reeds := _reeds()
	if reeds:
		add_child(reeds)
	if bridges:
		bridges.build_visuals()


## A river's or stream's surface: a strip along its samples out under its banks, UV.y the
## distance downstream (the shader scrolls the ripples along it), UV2.x the current's speed.
func _line_mesh(b: Dictionary) -> ArrayMesh:
	var pts: PackedVector2Array = b.pts
	var lo := int(b.lo)
	var hi := int(b.hi)
	if hi - lo < 1:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev: Array = []
	for i in range(lo, hi + 1):
		var t := tangent(b, i)
		var side := Vector2(-t.y, t.x)
		var reach := float((b.half as PackedFloat32Array)[i]) + float((b.bank_w as PackedFloat32Array)[i]) * STRIP_BANK_SHARE
		var y := float((b.w as PackedFloat32Array)[i])
		if i > lo:
			along += pts[i].distance_to(pts[i - 1])
		var v := along * float(b.down)
		var row := [[Vector3(pts[i].x - side.x * reach, y, pts[i].y - side.y * reach), Vector2(-1.0, v)],
			[Vector3(pts[i].x + side.x * reach, y, pts[i].y + side.y * reach), Vector2(1.0, v)]]
		if not prev.is_empty():
			for q: Array in [prev[0], row[0], prev[1], prev[1], row[0], row[1]]:
				st.set_normal(Vector3.UP)
				st.set_uv(q[1])
				st.set_uv2(Vector2(float(b.flow_ms), reach))
				st.add_vertex(q[0])
		prev = row
	return st.commit()


## A lake's or pond's surface: a fan out under its banks, still water (UV2.x 0).
func _lake_mesh(b: Dictionary) -> ArrayMesh:
	var c: Vector2 = b.centre
	var y := float(b.level)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in LAKE_BINS:
		var a0 := a * TAU / LAKE_BINS
		var a1 := (a + 1) * TAU / LAKE_BINS
		var r0 := lake_radius(b, a0) + float(b.bank_w) * STRIP_BANK_SHARE
		var r1 := lake_radius(b, a1) + float(b.bank_w) * STRIP_BANK_SHARE
		var p0 := c + Vector2.from_angle(a0) * r0
		var p1 := c + Vector2.from_angle(a1) * r1
		for p: Vector2 in [c, p0, p1]:  # clockwise from above
			st.set_normal(Vector3.UP)
			st.set_uv(p - c)
			st.set_uv2(Vector2(0.0, float(b.r)))
			st.add_vertex(Vector3(p.x, y, p.y))
	return st.commit()


## Reeds along the banks: clumps of blocky stalks in the shallows and at the water's edge
## (each body's "reeds": clumps a metre of bank), seeded by where they stand. Looks only.
func _reeds() -> MultiMeshInstance3D:
	var list: Array[Transform3D] = []
	var colours: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value ^ 0x2EED5
	var palette := [Color("6f7a3e"), Color("7d8446"), Color("5f6b36"), Color("8a8450")]
	for b: Dictionary in bodies:
		var per_m := float(b.get("reeds", 0.0))
		if per_m <= 0.0:
			continue
		var spots: Array[Vector2] = []
		if String(b.kind) == "lake":
			var c: Vector2 = b.centre
			var around := TAU * float(b.r)
			for k in int(around * per_m):
				var a := rng.randf() * TAU
				spots.append(c + Vector2.from_angle(a) * (lake_radius(b, a) + rng.randf_range(-2.5, 1.5)))
		else:
			var pts: PackedVector2Array = b.pts
			for i in range(int(b.lo), int(b.hi)):
				for k in int(STEP_M * 2.0 * per_m + rng.randf()):
					var u := i + rng.randf()
					var t := tangent(b, u)
					var side := Vector2(-t.y, t.x) * (1.0 if rng.randf() < 0.5 else -1.0)
					var half := lerpf((b.half as PackedFloat32Array)[i], (b.half as PackedFloat32Array)[i + 1], u - i)
					spots.append(pts[i].lerp(pts[i + 1], u - i) + side * (half + rng.randf_range(-2.0, 1.2)))
		for p in spots:
			if not _inside(p, 4.0) or (bridges and bridges.covers(p)):
				continue
			var h := terrain.height_at(p.x, p.y)
			var s := surface_at(p.x, p.y)
			if s == -INF or h < s - 0.6 or h > s + 0.5:
				continue  # reeds stand in the shallows and at the edge, not in deep water or up the bank
			var size := rng.randf_range(0.8, 1.5)
			list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.9, 1.4), size)), Vector3(p.x, h - 0.05, p.y)))
			colours.append((palette[rng.randi() % palette.size()] as Color).darkened(rng.randf() * 0.15))
	if list.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = reed_mesh()
	mm.instance_count = list.size()
	for k in list.size():
		mm.set_instance_transform(k, list[k])
		mm.set_instance_color(k, colours[k])
	var node := MultiMeshInstance3D.new()
	node.name = "Reeds"
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = REED_SEE_M
	node.visibility_range_end_margin = 30.0
	return node


## A reed clump: seven thin square stalks of different heights leaning a little, flat shaded,
## in the voxel look (lighter tops), standing on y = 0.
static func reed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for k in 7:
		var at := Vector2.from_angle(k * 2.4) * rng.randf_range(0.0, 0.28)
		var height := rng.randf_range(0.9, 1.7)
		var lean := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.05, 0.2)
		var r := 0.025
		var base := Vector3(at.x, 0.0, at.y)
		var top := Vector3(at.x + lean.x, height, at.y + lean.y)
		var corners: Array[Vector2] = [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]
		for q in 4:
			var a: Vector2 = corners[q]
			var b: Vector2 = corners[(q + 1) % 4]
			var n := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
			var quad := [base + Vector3(a.x, 0, a.y), top + Vector3(a.x, 0, a.y), top + Vector3(b.x, 0, b.y), base + Vector3(b.x, 0, b.y)]
			var shades := [0.7, 1.05, 1.05, 0.7]
			for v: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(Color.WHITE * float(shades[v]))
				st.set_normal(n)
				st.add_vertex(quad[v])
		if k % 3 == 0:  # a seed head
			for q in 4:
				var a: Vector2 = corners[q] * 2.0
				var b: Vector2 = corners[(q + 1) % 4] * 2.0
				var n := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
				var lo := top - Vector3(0, 0.22, 0)
				var quad := [lo + Vector3(a.x, 0, a.y), top + Vector3(a.x, 0, a.y), top + Vector3(b.x, 0, b.y), lo + Vector3(b.x, 0, b.y)]
				for v: int in [0, 2, 1, 0, 3, 2]:
					st.set_color(Color(0.55, 0.42, 0.3))
					st.set_normal(n)
					st.add_vertex(quad[v])
	return st.commit()
