class_name OperationGen
extends RefCounted
## Operation zones (docs/combined_arms.md 6.2, phase D1): an 8,192 m square made fresh for an
## operation contract (ZoneDef.generate_operation) from the contract zones it covers: their
## region, terrain, assets and landmarks. Laid out in bands along an axis of advance from the
## friendly edge (or the sea) to the enemy's depth (PATH "bands"):
##   start     the allied FOB inland, the beach and its exit on the coast; the insertion points
##   outposts  outposts and checkpoints, villages, the MSR's checkpoint, the first lateral
##   crossing  a river across the axis: the MSR's concrete bridge, a steel truss on a second
##             route, one or two ford tracks, footbridges between; the bridge's far-bank
##             checkpoint and an outpost over it
##   town      the town, villages, the second lateral
##   depth     the HQ with its comms site and QRF bases, the depth target (an airfield, an oil
##             site or a fuel depot)
##   keep      the enemy's rear
## The main supply route (MSR) runs the length: start, the MSR checkpoint, the bridge, the town,
## the HQ, the depth target. Two laterals cross it; every other site has a track to the nearest
## road. The river and its bridges are cghath's ZoneWater and ZoneBridges, given one hint: the
## def's "river_hint" ({"axis", "at_m": where the river crosses it, "water": merged into the
## preset's water spec, "crossings": [{"pos", "kind", "role"}] the kind each planned road crossing
## gets and the role it carries onto the bridge, "default": the kind any other road crossing
## gets, "match_m"}). Landmarks come from the covered zones (data/landmarks.json by their assets
## and ids) and go in the band PATH's "landmark_bands" gives their kind (ZoneModules.place_landmarks
## asks landmark_area). The same seed, type and covers give the same zone. Numbers in
## data/operation_zones.json, all Proposed.

const PATH := "res://data/operation_zones.json"
const KIND := "operation"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d
		else:
			push_error("OperationGen: cannot read %s" % PATH)
	return _data


## The way into the zone from friendly edge `side` (ZoneDef's sides: 0 north -z, 1 south +z,
## 2 west -x, 3 east +x).
static func axis_of(side: int) -> Vector2:
	return [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)][side]


## Zone metres (x, z) of the point `s` m along `axis` from the friendly edge and `l` m across it
## (to the axis's left) in a zone `half` m from centre to edge.
static func _pt(axis: Vector2, half: float, s: float, l: float) -> Vector2:
	return axis * (s - half) + Vector2(-axis.y, axis.x) * l


static func _axis(def: Dictionary) -> Vector2:
	var a: Array = (def.get("op", {}) as Dictionary).get("axis", [0, 1])
	return Vector2(float(a[0]), float(a[1]))


## Whether `def` is an operation zone's.
static func is_operation(def: Dictionary) -> bool:
	return String(def.get("kind", "")) == KIND and def.has("op")


## How far `p` (x, z) lies along operation zone `def`'s axis from its friendly edge (m).
static func along(def: Dictionary, p: Vector2) -> float:
	return _axis(def).dot(p) + float(def.get("size_m", 0.0)) * 0.5


## How far `p` lies across `def`'s axis from its middle line (m, to the axis's left).
static func across(def: Dictionary, p: Vector2) -> float:
	var a := _axis(def)
	return Vector2(-a.y, a.x).dot(p)


## Band `id`'s [from, to] (m along the axis) in `def`, Vector2(-1, -1) if it has none.
static func band_range(def: Dictionary, id: String) -> Vector2:
	for b: Dictionary in (def.get("op", {}) as Dictionary).get("bands", []):
		if String(b.id) == id:
			return Vector2(float(b.from_m), float(b.to_m))
	return Vector2(-1, -1)


## The band `p` (x, z) lies in, "" outside every band or in a zone that isn't an operation's.
static func band_at(def: Dictionary, p: Vector2) -> String:
	var s := along(def, p)
	for b: Dictionary in (def.get("op", {}) as Dictionary).get("bands", []):
		if s >= float(b.from_m) and s < float(b.to_m):
			return String(b.id)
	return ""


## Where a landmark of `kind` (half size `h`) may stand in zone `def` (ZoneModules.place_landmarks'
## band hint): its band ("landmark_bands"), "landmark_band_keep_m" inside the band's ends and
## "landmark_side_keep_m" inside the zone's sides. An empty Rect2 (anywhere, as before) for a
## zone that isn't an operation's or a kind with no band.
static func landmark_area(def: Dictionary, kind: String, h: Vector2) -> Rect2:
	if not is_operation(def):
		return Rect2()
	var d := data()
	var band := String((d.get("landmark_bands", {}) as Dictionary).get(kind, ""))
	var r := band_range(def, band)
	if band == "" or r.x < 0.0:
		return Rect2()
	var reach := maxf(h.x, h.y)
	var s0 := r.x + float(d.get("landmark_band_keep_m", 150.0)) + reach
	var s1 := r.y - float(d.get("landmark_band_keep_m", 150.0)) - reach
	var half := float(def.size_m) * 0.5
	var lat := half - float(d.get("landmark_side_keep_m", 400.0)) - reach
	if s1 <= s0 or lat <= 0.0:
		return Rect2()
	var axis := _axis(def)
	return Rect2(_pt(axis, half, s0, -lat), Vector2.ZERO).expand(_pt(axis, half, s1, lat))


## An operation zone (ZoneDef.generate_operation): `op_type` one of PATH's "op_types", `covers`
## the contract zones (data/contracts.json ids, 2-4 neighbours held by the target faction) it is
## made from and flips. "kind": "operation"; "op" holds its layout (type, friendly side, axis,
## bands, the river's place, the MSR's points and road indices, the laterals, the truss route,
## the ford tracks, start, FOB, town, HQ and depth target ids); "river_hint" is ZoneWater's.
static func generate(seed: int, op_type: String, covers: Array) -> Dictionary:
	var d := data()
	var types: Array = d.get("op_types", ["phased_invasion"])
	if not op_type in types:
		push_warning("OperationGen: unknown operation type %s" % op_type)
		op_type = String(types[0])
	var zones: Array = []
	var cover_ids: Array = []
	for id: Variant in covers.slice(0, 4):
		var z: Dictionary = MissionRegistry.zone(String(id))
		if z.is_empty():
			push_warning("OperationGen: no zone %s to cover" % id)
			continue
		zones.append(z)
		cover_ids.append(String(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, op_type, "operation"])
	var coastal := op_type in (d.get("coast_types", []) as Array) or (not zones.is_empty()
		and zones.all(func(z: Dictionary) -> bool: return String(z.get("region", "")) == "coast"))
	var region := "coast" if coastal else "inland"
	var terrain := _terrain(d, region, zones)
	var sea: Dictionary = TerrainPresets.get_preset(terrain).get("sea", {})
	var sea_w := float(sea.get("width_m", 0.0)) if not sea.is_empty() else 0.0
	var size := float(d.get("size_m", 8192.0))
	var half := size * 0.5
	var side := rng.randi() % 4
	var axis := axis_of(side)
	var pt := func(s: float, l: float) -> Vector2: return _pt(axis, half, s, l)
	var bands: Array = []
	var from := 0.0
	for b: Dictionary in d.bands:
		bands.append({"id": String(b.id), "from_m": from, "to_m": float(b.to_m)})
		from = float(b.to_m)
	var band := func(id: String) -> Vector2:
		for b: Dictionary in bands:
			if b.id == id:
				return Vector2(b.from_m, b.to_m)
		return Vector2.ZERO
	var b1: Vector2 = band.call("outposts")
	var b2: Vector2 = band.call("crossing")
	var b3: Vector2 = band.call("town")
	var b4: Vector2 = band.call("depth")
	var lat := half - float(d.side_keep_m)
	var spacing := float(d.spacing_m)

	# The lines: the MSR's lateral, the bridge's, the river's place, the laterals.
	var msr: Dictionary = d.msr
	var l0 := rng.randf_range(-float(msr.lateral_m), float(msr.lateral_m))
	var lb := clampf(l0 + rng.randf_range(-float(msr.bridge_jitter_m), float(msr.bridge_jitter_m)), -lat, lat)
	var river: Dictionary = d.river
	var river_at := rng.randf_range(float(river.at_m[0]), float(river.at_m[1]))
	var laterals: Array = []  # each [Vector2(s, l), ...] across the zone
	var lat_spec: Dictionary = d.laterals
	for range_m: Array in lat_spec.at_m:
		var s_lat := rng.randf_range(float(range_m[0]), float(range_m[1]))
		var n := int(lat_spec.points)
		var edge := half - float(lat_spec.edge_m)
		var line: Array = []
		for k in n:
			line.append(Vector2(s_lat + rng.randf_range(-1.0, 1.0) * float(lat_spec.jitter_m), lerpf(-edge, edge, float(k) / (n - 1))))
		laterals.append(line)
	var cross: Dictionary = d.crossings
	var lat2 := half - float(cross.edge_m)
	var lt2 := lb + float(cross.truss_gap_m) * (1.0 if lb < 0.0 else -1.0)
	for attempt in 60:
		var l := rng.randf_range(-lat2, lat2)
		if absf(l - lb) >= float(cross.truss_gap_m):
			lt2 = l
			break
	var ford_ls: Array[float] = []
	for k in rng.randi_range(int(cross.fords[0]), int(cross.fords[1])):
		for attempt in 60:
			var l := rng.randf_range(-lat2, lat2)
			var gap := float(cross.ford_gap_m)
			if absf(l - lb) >= gap and absf(l - lt2) >= gap and ford_ls.all(func(o: float) -> bool: return absf(l - o) >= gap):
				ford_ls.append(l)
				break

	# Sites.
	var modules: Array = []
	var placed: Array[Vector2] = []
	var place := func(id: String, type: String, p: Vector2, gap: float) -> bool:
		var q := Vector2(snappedf(p.x, ZoneDef.GRID_M), snappedf(p.y, ZoneDef.GRID_M))
		if absf(q.x) > half - ZoneDef.EDGE_KEEP_M or absf(q.y) > half - ZoneDef.EDGE_KEEP_M:
			return false
		if placed.any(func(o: Vector2) -> bool: return o.distance_to(q) < gap):
			return false
		placed.append(q)
		modules.append({"id": id, "type": type, "pos": [q.x, q.y]})
		return true
	var pos_of := func(id: String) -> Vector2:
		for m: Dictionary in modules:
			if m.id == id:
				return Vector2(float(m.pos[0]), float(m.pos[1]))
		return Vector2.INF
	var s_start := sea_w + float(d.beach_exit_m) if sea_w > 0.0 else float(d.fob_at_m)
	var start: Vector2 = pt.call(s_start, l0)
	if sea_w <= 0.0:
		place.call("fob", "fob", start, spacing)  # the allied staging FOB (docs/combined_arms.md 8)
	place.call("cp_msr", "checkpoint", pt.call(rng.randf_range(float(msr.checkpoint_at_m[0]), float(msr.checkpoint_at_m[1])), l0 + rng.randf_range(-150.0, 150.0)), spacing)
	place.call("cp_bridge", "checkpoint", pt.call(float(msr.far_checkpoint_m), lb), spacing)
	var lt := clampf(lb + rng.randf_range(-1.0, 1.0) * float(d.town_lateral_m), -lat, lat)
	var town_type := "%s%d" % [ZoneModules.TOWN, absi(hash([seed, "op_town"])) % 1000000]
	place.call("town", town_type, pt.call(rng.randf_range(float(d.town_at_m[0]), float(d.town_at_m[1])), lt), float(d.town_spacing_m))
	var lh := clampf(lt + rng.randf_range(-1.0, 1.0) * float(d.hq_lateral_m), -lat, lat)
	var s_h := rng.randf_range(float(d.hq_at_m[0]), float(d.hq_at_m[1]))
	place.call("hq", "hq", pt.call(s_h, lh), spacing)
	var ring := func(id: String, type: String, ring_m: Array) -> void:
		for attempt in 200:
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(ring_m[0]), float(ring_m[1]))
			var s := clampf(s_h + off.x, b4.x + 100.0, b4.y - 100.0)
			if place.call(id, type, pt.call(s, clampf(lh + off.y, -lat, lat)), spacing * 0.8):
				return
	var sites: Dictionary = d.sites
	for k in int(sites.comms):
		ring.call("comms_%d" % k, "comms", d.comms_ring_m)
	for k in rng.randi_range(int(sites.qrf_bases[0]), int(sites.qrf_bases[1])):
		ring.call("qrf_%d" % k, "qrf_base", d.qrf_ring_m)
	# Where a band's scattered sites may go (m along the axis), clear of the beach on the coast.
	var span := func(b: Vector2) -> Vector2:
		return Vector2(maxf(b.x + 100.0, sea_w + float(d.coast_keep_m)), b.y - 120.0)
	var scatter := func(id: String, type: String, s_span: Vector2) -> void:
		for attempt in 300:
			if place.call(id, type, pt.call(rng.randf_range(s_span.x, s_span.y), rng.randf_range(-lat, lat)), spacing):
				return
	var on_lateral := func(id: String, line: Array) -> void:
		for attempt in 100:
			var l := rng.randf_range(-lat, lat)
			if place.call(id, "checkpoint", pt.call(_lateral_s(line, l), l), spacing):
				return
	var n_sites := rng.randi_range(int(sites.outposts_checkpoints[0]), int(sites.outposts_checkpoints[1]))
	var rest := maxi(n_sites - 3, 0)  # the MSR's and the bridge's checkpoints, the outpost over the bridge
	var share: Dictionary = d.band_share
	var n1 := roundi(rest * float(share.outposts))
	var n3 := roundi(rest * float(share.town))
	var n4 := maxi(rest - n1 - n3, 0)
	for k in 200:
		var s := rng.randf_range(float(msr.far_checkpoint_m) - 80.0, b2.y - 20.0)
		var l := lb + rng.randf_range(300.0, 900.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		if place.call("outpost_%d" % modules.size(), "outpost", pt.call(s, clampf(l, -lat, lat)), spacing):
			break
	for group: Array in [[n1, b1, laterals[0]], [n3, b3, laterals[1]], [n4, b4, null]]:
		for k in int(group[0]):
			if group[2] != null and rng.randf() < float(sites.checkpoint_share):
				on_lateral.call("checkpoint_%d" % modules.size(), group[2])
			else:
				scatter.call("outpost_%d" % modules.size(), "outpost", span.call(group[1]))
	var village_bands: Array = sites.village_bands
	for k in rng.randi_range(int(sites.villages[0]), int(sites.villages[1])):
		scatter.call("village_%d" % modules.size(), "village", span.call(band.call(String(village_bands[k % village_bands.size()]))))

	# Roads: the MSR, the laterals, the truss route and the ford tracks, then a track from every
	# other site to the nearest of them.
	var to_world := func(line: Array) -> Array:
		var out: Array = []
		for v: Vector2 in line:
			var p: Vector2 = pt.call(v.x, v.y)
			out.append([p.x, p.y])
		return out
	var msr_line: Array = [start, pos_of.call("cp_msr"), pt.call(b2.x - float(msr.approach_m), lb),
		pt.call(b2.y + float(msr.approach_m), lb), pos_of.call("town"), pos_of.call("hq")]
	msr_line = msr_line.filter(func(p: Vector2) -> bool: return p.is_finite()).map(func(p: Vector2) -> Array: return [p.x, p.y])
	var across_line := func(l: float) -> Array:
		return to_world.call([Vector2(_lateral_s(laterals[0], l), l), Vector2(b2.x - float(msr.approach_m), l),
			Vector2(b2.y + float(msr.approach_m), l), Vector2(_lateral_s(laterals[1], l), l)])
	var route: Array = across_line.call(lt2)
	var fords: Array = []
	for l in ford_ls:
		fords.append(across_line.call(l))
	var roads: Array = []
	var add_line := func(line: Array) -> Array:
		var idx: Array = []
		for k in range(1, line.size()):
			idx.append(roads.size())
			roads.append([line[k - 1], line[k]])
		return idx
	var msr_roads: Array = add_line.call(msr_line)
	var lateral_lines: Array = []
	for line: Array in laterals:
		lateral_lines.append(to_world.call(line))
		add_line.call(lateral_lines.back())
	add_line.call(route)
	for f: Array in fords:
		add_line.call(f)
	var mains := roads.duplicate()
	for m: Dictionary in modules:
		if String(m.id) in ["fob", "cp_msr", "cp_bridge", "town", "hq"]:
			continue
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		var best := Vector2.INF
		for r: Array in mains:
			var q := Geometry2D.get_closest_point_to_segment(p, Vector2(r[0][0], r[0][1]), Vector2(r[1][0], r[1][1]))
			if not best.is_finite() or q.distance_to(p) < best.distance_to(p):
				best = q
		if best.is_finite() and best.distance_to(p) > 30.0:
			roads.append([[p.x, p.y], [snappedf(best.x, 1.0), snappedf(best.y, 1.0)]])

	# Patrols between neighbouring enemy sites, in their own band when it has two more.
	var enemy := modules.filter(func(m: Dictionary) -> bool:
		return not ZoneModules.base(String(m.type)) in ["village", "town", "fob"])
	var band_of := func(m: Dictionary) -> float:
		return axis.dot(Vector2(float(m.pos[0]), float(m.pos[1]))) + half
	var patrols: Array = []
	for k in rng.randi_range(int(d.patrols[0]), int(d.patrols[1])):
		if enemy.size() < 3:
			break
		var a: Dictionary = enemy[rng.randi() % enemy.size()]
		var pa := Vector2(float(a.pos[0]), float(a.pos[1]))
		var sa: float = band_of.call(a)
		var near := enemy.filter(func(m: Dictionary) -> bool: return m != a)
		var same := near.filter(func(m: Dictionary) -> bool: return absf(float(band_of.call(m)) - sa) < 900.0)
		if same.size() >= 2:
			near = same
		near.sort_custom(func(m: Dictionary, n: Dictionary) -> bool:
			return pa.distance_to(Vector2(m.pos[0], m.pos[1])) < pa.distance_to(Vector2(n.pos[0], n.pos[1])))
		var walk: Array = [[pa.x, pa.y]]
		for m: Dictionary in near.slice(0, 2):
			walk.append([float(m.pos[0]), float(m.pos[1])])
		patrols.append(walk)

	# Insertion and extraction at the start: the friendly edge inland, the beach on the coast.
	var s_pts := s_start if sea_w > 0.0 else ZoneDef.EDGE_POINT_IN_M
	var edge_pt := func(l: float) -> Array:
		var p: Vector2 = pt.call(s_pts, clampf(l, -lat, lat))
		return [snappedf(p.x, 1.0), snappedf(p.y, 1.0)]
	var insertion: Array = [edge_pt.call(l0), edge_pt.call(l0 + 1300.0), edge_pt.call(l0 - 1300.0)]
	var extraction: Array = [edge_pt.call(l0 + 650.0), edge_pt.call(l0 - 650.0), edge_pt.call(l0 + 2200.0)]

	# Landmarks from the covered zones: their assets and ids (ZoneModules.landmark_kinds), placed in
	# their bands by normalize (ZoneModules.place_landmarks, landmark_area); a depth target added
	# when none of them brings one.
	var assets: Array = []
	for z: Dictionary in zones:
		for a: Variant in z.get("assets", []):
			if not String(a) in assets:
				assets.append(String(a))
	var controller := String(zones[0].get("controller", "")) if not zones.is_empty() else ""
	var def := {"id": "op_%d" % seed, "name": "Operation zone %d" % seed, "seed": seed, "size_m": size, "relief_m": float(d.relief_m),
		"kind": KIND, "op_type": op_type, "covers": cover_ids, "region": region, "terrain": terrain, "controller": controller,
		"assets": assets, "landmark_max": int(d.landmark_max), "modules": modules, "insertion": insertion, "extraction": extraction,
		"roads": roads, "patrols": patrols, "op": {"type": op_type, "side": side, "axis": [axis.x, axis.y], "bands": bands}}
	var depth_kinds: Array = d.depth_targets
	if not ZoneModules.landmark_kinds(def).any(func(k: String) -> bool: return k in depth_kinds):
		def["landmarks"] = [String(d.depth_fallback)]
	if sea_w > 0.0:
		def["sea_side_pref"] = side  # the beach is the friendly edge (ZoneDef._choose_sea)
	def = ZoneDef.normalize(def)

	# The MSR's last leg: the HQ to the depth target.
	var depth := "hq"
	for k: String in depth_kinds:
		if (def.modules as Array).any(func(m: Dictionary) -> bool: return String(m.id) == "lm_" + k):
			depth = "lm_" + k
			break
	if depth != "hq":
		for m: Dictionary in def.modules:
			if String(m.id) == depth:
				msr_line.append([float(m.pos[0]), float(m.pos[1])])
				msr_roads.append((def.roads as Array).size())
				(def.roads as Array).append([msr_line[msr_line.size() - 2], msr_line.back()])
	var river_pos := func(l: float) -> Array:
		var p: Vector2 = pt.call(river_at, l)
		return [p.x, p.y]
	var planned: Array = [{"pos": river_pos.call(lb), "kind": ZoneBridges.CONCRETE, "role": "msr"},
		{"pos": river_pos.call(lt2), "kind": ZoneBridges.TRUSS, "role": "route"}]
	for l in ford_ls:
		planned.append({"pos": river_pos.call(l), "kind": ZoneBridges.FORD, "role": "ford"})
	def["river_hint"] = {"axis": [axis.x, axis.y], "at_m": river_at, "water": river.water, "crossings": planned,
		"default": String(river.default), "match_m": float(river.match_m)}
	var op: Dictionary = def.op
	op["coast"] = sea_w > 0.0
	op["band2"] = "river"
	op["river_at_m"] = river_at
	op["start"] = [start.x, start.y]
	op["msr"] = msr_line
	op["msr_roads"] = msr_roads
	op["laterals"] = lateral_lines
	op["route"] = route
	op["fords"] = fords
	op["fob"] = "fob" if sea_w <= 0.0 else ""
	op["town"] = "town"
	op["hq"] = "hq"
	op["depth"] = depth
	return def


## The terrain preset an operation in `region` takes from its covered `zones`: the first of theirs
## that PATH's "terrain" lists for the region, else the first of those that exists.
static func _terrain(d: Dictionary, region: String, zones: Array) -> String:
	var allowed: Array = (d.get("terrain", {}) as Dictionary).get(region, [])
	for z: Dictionary in zones:
		var t := String(z.get("terrain", ""))
		if t in allowed and TerrainPresets.has(t):
			return t
	for t: Variant in allowed:
		if TerrainPresets.has(String(t)):
			return String(t)
	return TerrainPresets.choose({"region": region})


## Where lateral `line` ([Vector2(s, l)], l rising) is along the axis at `l` across it.
static func _lateral_s(line: Array, l: float) -> float:
	for k in range(1, line.size()):
		var a: Vector2 = line[k - 1]
		var b: Vector2 = line[k]
		if l <= b.y or k == line.size() - 1:
			return lerpf(a.x, b.x, clampf(inverse_lerp(a.y, b.y, l), 0.0, 1.0))
	return (line[0] as Vector2).x
