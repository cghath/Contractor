extends Node
## Headless screenshots of the prop library (cghath's queue item 1.7): a town street and the town
## from above, the countryside with its pylon line, burnt-out hulks by a road, a farm with its pen
## and animals, a cemetery, a site's containers, and catalogue rows of every prop. --headless has
## no renderer and no window may open on this machine (docs/cg_brief.md: headless only), so this
## draws them itself: a small software rasteriser (flat-shaded triangles, a depth buffer, sun
## and fog) over the zone's own ground, buildings (their voxel boxes), roads and scatter meshes.
## It's for looking at the layout and shapes, not the game's lighting.
##   <exe> --headless --path . res://tests/props_shots.tscn -- <output folder> [preset] [seed]
## Writes <shot>.png into the folder and prints a line per shot; keep the output as an S run.

const W := 720
const H := 405
const FOV_DEG := 62.0
const NEAR := 0.25
const SUN := Vector3(-0.42, 0.82, -0.38)
const SKY_TOP := Color("6f93b8")
const SKY_LOW := Color("c9d6dc")
const FOG_M := 900.0
## Scatter and props are drawn out to this far (pylons further), ground near at 4 m cells, far at 16.
const SEE_M := 420.0
const SEE_BIG_M := 1300.0
const NEAR_GROUND_M := 160.0
const FAR_GROUND_M := 900.0

var terrain: ZoneTerrain
var scatter: ZoneScatter
var def := {}
var out := ""
var _img: Image
var _depth := PackedFloat32Array()
var _cam := Transform3D()
var _view := Transform3D()
var _focal := 1.0
var _sun := SUN.normalized()
var _arrays := {}  # mesh key -> [vertices, colours]
var _tris := 0


func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 else OS.get_environment("TEMP").path_join("contractor_world_shots")
	var presets: Array = [String(args[1])] if args.size() > 1 else ["temperate", "desert_wadi"]
	var seed_value := int(args[2]) if args.size() > 2 else 4242
	DirAccess.make_dir_recursive_absolute(out)
	_focal = (H * 0.5) / tan(deg_to_rad(FOV_DEG) * 0.5)
	await _catalogue()
	for preset: String in presets:
		_zone(preset, seed_value)
		await _zone_shots(preset)
	print("[props_shots] done: %s" % out)
	get_tree().quit(0)


# --- The zone ----------------------------------------------------------------------------------

func _zone(preset: String, seed_value: int) -> void:
	var mods := [
		{"id": "compound", "type": "compound", "pos": [-300, -264]},
		{"id": "outpost", "type": "outpost", "pos": [264, -300]},
		{"id": "village", "type": "village", "pos": [-288, 264]},
		{"id": "hq", "type": "hq", "pos": [276, 264]},
		{"id": "town", "type": "%s%d" % [ZoneModules.TOWN, seed_value], "pos": [0, 0]},
	]
	var roads: Array = []
	for m: Dictionary in mods.slice(0, 4):
		roads.append([[0.0, 0.0], [float(m.pos[0]), float(m.pos[1])]])
	def = ZoneDef.normalize({"id": "props_shots", "name": "Prop shots", "seed": seed_value, "size_m": 1536.0, "relief_m": 14.0, "terrain": preset,
		"modules": mods, "insertion": [[0.0, 640.0]], "extraction": [[0.0, -640.0]]})
	def["roads"] = roads
	var flat: Array = []
	for m: Dictionary in def.modules:
		ZoneModules.has_type(String(m.type))
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		flat.append(Rect2(Vector2(float(m.pos[0]), float(m.pos[1])) - half, half * 2.0))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	terrain = ZoneTerrain.new()
	terrain.generate(def, flat)
	ZoneScatter.clear_cache(true)  # (this code's layout, not a cached one)
	scatter = ZoneScatter.new()
	scatter.generate(terrain, def)
	scatter._meshes = scatter._shared_meshes(String((terrain.preset.get("scatter", {}) as Dictionary).get("colours", {}).get("trunk", "4f3e2c")))
	var report := scatter.props_report.duplicate()
	report.erase("rejected")
	print("[props_shots] %s seed %d: %d items, %d library props, %s" % [preset, seed_value, scatter.total(), scatter.library_count, report])


func _zone_shots(preset: String) -> void:
	var town: Dictionary = def.modules[4]
	var o := Vector3(float(town.pos[0]), terrain.height_at(float(town.pos[0]), float(town.pos[1])), float(town.pos[1]))
	await _shot("%s_town_street" % preset, o + Vector3(-36, 1.7, 0.6), o + Vector3(10, 1.4, 0.0))
	await _shot("%s_town_above" % preset, o + Vector3(-30, 26, 34), o + Vector3(6, 0, 0))
	var pylon := _find(["pylon"], o)
	if not pylon.is_empty():
		var p: Vector3 = pylon.pos
		var along := ZoneScatter.library_transform(pylon).basis.z.normalized()
		var side := along.cross(Vector3.UP).normalized()
		var eye := p - along * 30.0 + side * 55.0
		eye.y = terrain.height_at(eye.x, eye.z) + 3.0
		await _shot("%s_countryside_pylons" % preset, eye, p + along * 120.0 + Vector3(0, 8, 0))
	for kinds: Array in [["hulk_car", "hulk_truck", "hulk_van"], ["car_sedan", "car_hatch", "van", "pickup_civ", "truck_cargo", "truck_tanker", "tractor"]]:
		var v := _find(kinds, o, 30.0)
		if not v.is_empty():
			var p: Vector3 = v.pos
			var xf := ZoneScatter.library_transform(v)
			var eye := p + xf.basis.z.normalized() * 7.5 + xf.basis.x.normalized() * 5.0
			eye.y = terrain.height_at(eye.x, eye.z) + 2.2
			await _shot("%s_%s" % [preset, "hulks" if kinds[0].begins_with("hulk") else "vehicles"], eye, p + Vector3(0, 0.8, 0))
	var pen := _find_marker(["sheep", "goat"])
	if not pen.is_empty():
		var p: Vector3 = pen.pos
		var eye := p + Vector3(16, 7, 14)
		await _shot("%s_farm" % preset, eye, p)
	var grave := _find(["headstone", "grave_cross", "tomb", "grave_stele", "grave_mound"], o)
	if not grave.is_empty():
		var p: Vector3 = grave.pos
		await _shot("%s_cemetery" % preset, p + Vector3(14, 9, 12), p)
	var box := _find(["container_20", "container_40", "container_stack"], Vector3(276, 0, 264))
	if not box.is_empty():
		var p: Vector3 = box.pos
		await _shot("%s_site" % preset, p + Vector3(12, 6, 10), p + Vector3(0, 1, 0))


## The library item of one of `shapes` nearest `near` (at least `min_m` off it).
func _find(shapes: Array, near: Vector3, min_m := 0.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for item: Dictionary in scatter.items:
		if not item.has("shape") or int(item.kind) != ZoneScatter.Kind.PROP or not String(item.shape) in shapes:
			continue
		var d := Vector2((item.pos as Vector3).x - near.x, (item.pos as Vector3).z - near.z).length()
		if d >= min_m and d < best_d:
			best_d = d
			best = item
	return best


func _find_marker(species: Array) -> Dictionary:
	for item: Dictionary in scatter.items:
		if int(item.kind) == ZoneScatter.Kind.ANIMAL and String(item.shape) in species:
			return item
	return {}


# --- Catalogue ---------------------------------------------------------------------------------

## Every prop in rows on a flat grey plane, by group, in its first paint (vehicles in two).
func _catalogue() -> void:
	terrain = null
	scatter = null
	var groups := {
		"catalogue_street_market": ["street_lamp", "lamp_double", "utility_pole", "pole_transformer", "sign_stop", "sign_warn", "sign_direction", "bus_shelter",
			"bench", "bollard", "dumpster", "kiosk", "jersey_barrier", "billboard", "market_stall", "stall_canopy", "shop_awning", "produce_crates", "hand_cart"],
		"catalogue_fences_power": ["fence_rail", "fence_board", "fence_chainlink", "fence_barbed", "fence_corrugated", "wall_stone", "wall_block", "wall_mud",
			"gate_farm", "gate_steel", "gate_wood", "power_pole_h", "pylon"],
		"catalogue_farm_water": ["well", "water_tower", "cistern", "trough", "hay_round", "hay_square", "irrigation_channel", "irrigation_pipe", "sluice_gate",
			"windpump", "pen_shelter", "goat", "sheep", "dog"],
		"catalogue_vehicles": ["car_sedan", "car_hatch", "van", "pickup_civ", "truck_cargo", "truck_tanker", "tractor", "hulk_car", "hulk_van", "hulk_truck"],
		"catalogue_hulks": ["hulk_car", "hulk_van", "hulk_truck", "car_sedan"],
		"catalogue_containers_graves_sites": ["container_20", "container_40", "container_stack", "grave_mound", "headstone", "grave_cross", "tomb", "grave_stele",
			"generator", "sat_dish", "laundry_line", "fuel_tank", "gas_cylinders", "pallet_stack", "tyre_pile", "latrine"],
	}
	for name: String in groups:
		var list: Array = groups[name]
		var placed: Array = []  # [shape, transform, paint]
		var x := 0.0
		var row_z := 0.0
		var row_w := 0.0
		var widest := 0.0
		for shape: String in list:
			var b := PropArt.shape(shape).bounds as AABB
			var w := b.size.x + 1.6
			if x + w > 34.0:
				x = 0.0
				row_z += widest + 2.5
				widest = 0.0
			placed.append([shape, Transform3D(Basis.IDENTITY, Vector3(x - b.position.x, 0, row_z - b.position.z)), 0])
			x += w
			row_w = maxf(row_w, x)
			widest = maxf(widest, b.size.z)
		var depth := row_z + widest
		var centre := Vector3(row_w * 0.5, 0, depth * 0.5)
		var tall := 1.0
		for p: Array in placed:
			tall = maxf(tall, (PropArt.shape(p[0]).bounds as AABB).end.y)
		var eye := centre + Vector3(-row_w * 0.05, maxf(row_w, depth) * 0.26 + tall * 0.5, depth * 0.5 + maxf(row_w, depth) * 0.42)
		_begin(eye, centre + Vector3(0, tall * 0.18, 0))
		var plane := PackedVector3Array([Vector3(-10, 0, -10), Vector3(row_w + 10, 0, -10), Vector3(row_w + 10, 0, depth + 10), Vector3(-10, 0, depth + 10)])
		_triangle(plane[0], plane[1], plane[2], Color("8d8a80"))
		_triangle(plane[0], plane[2], plane[3], Color("8d8a80"))
		for p: Array in placed:
			_mesh("lib:%s#%d" % [p[0], p[2]], p[1], Color.WHITE)
		_save(name)
		await get_tree().process_frame


# --- Drawing -----------------------------------------------------------------------------------

func _shot(name: String, eye: Vector3, target: Vector3) -> void:
	var started := Time.get_ticks_msec()
	_begin(eye, target)
	_ground(eye, target)
	_modules(eye)
	_roads()
	_scatter(eye)
	_animals(eye)
	_save(name, started)
	await get_tree().process_frame


func _begin(eye: Vector3, target: Vector3) -> void:
	_cam = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	_view = _cam.affine_inverse()
	_img = Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var c := SKY_TOP.lerp(SKY_LOW, float(y) / H)
		for x in W:
			_img.set_pixel(x, y, c)
	_depth = PackedFloat32Array()
	_depth.resize(W * H)
	_depth.fill(0.0)
	_tris = 0


func _save(name: String, started := -1) -> void:
	var path := out.path_join(name + ".png")
	_img.save_png(path)
	print("[props_shots] %s: %d triangles%s -> %s" % [name, _tris, "" if started < 0 else ", %d ms" % (Time.get_ticks_msec() - started), path])


## The ground round the view: 4 m cells near (the zone's own triangles and colours), 16 m far.
func _ground(eye: Vector3, target: Vector3) -> void:
	var look := Vector2(target.x - eye.x, target.z - eye.z).normalized()
	var mid := Vector2(eye.x, eye.z) + look * NEAR_GROUND_M * 0.6
	var near := Rect2(mid - Vector2(NEAR_GROUND_M, NEAR_GROUND_M), Vector2(NEAR_GROUND_M, NEAR_GROUND_M) * 2.0)
	var faces := terrain.triangles_in(near)
	var half := terrain.size_m * 0.5
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var i := clampi(roundi((a.x + half) / ZoneTerrain.CELL_M), 0, terrain.points - 1)
		var j := clampi(roundi((a.z + half) / ZoneTerrain.CELL_M), 0, terrain.points - 1)
		_triangle(a, faces[t + 1], faces[t + 2], terrain.vertex_colour(i, j))
	var step := 16.0
	var far := Rect2(Vector2(eye.x, eye.z) + look * FAR_GROUND_M * 0.45 - Vector2(FAR_GROUND_M, FAR_GROUND_M) * 0.6, Vector2(FAR_GROUND_M, FAR_GROUND_M) * 1.2)
	var z := far.position.y
	while z < far.end.y:
		var x := far.position.x
		while x < far.end.x:
			if not near.grow(-2.0).encloses(Rect2(x, z, step, step)) and absf(x) < half and absf(z) < half:
				var p00 := Vector3(x, terrain.height_at(x, z), z)
				var p10 := Vector3(x + step, terrain.height_at(x + step, z), z)
				var p01 := Vector3(x, terrain.height_at(x, z + step), z + step)
				var p11 := Vector3(x + step, terrain.height_at(x + step, z + step), z + step)
				var i := clampi(roundi((x + half) / ZoneTerrain.CELL_M), 0, terrain.points - 1)
				var j := clampi(roundi((z + half) / ZoneTerrain.CELL_M), 0, terrain.points - 1)
				var c := terrain.vertex_colour(i, j)
				_triangle(p00, p10, p01, c)
				_triangle(p10, p11, p01, c)
			x += step
		z += step


## The modules' voxel boxes (their structure and dress), in their materials' colours.
func _modules(eye: Vector3) -> void:
	for m: Dictionary in def.modules:
		var o := Vector3(float(m.pos[0]), terrain.height_at(float(m.pos[0]), float(m.pos[1])), float(m.pos[1]))
		if Vector2(o.x - eye.x, o.z - eye.z).length() > SEE_M + 80.0:
			continue
		var type := String(m.type)
		for list: Array in [ZoneModules.boxes(type), ZoneModules.skin(type)]:
			for bx: Array in list:
				var lo: Vector3 = (bx[0] as Vector3).min(bx[1]) + o
				var hi: Vector3 = (bx[0] as Vector3).max(bx[1]) + o
				var colour: Color = VoxelWorld.PALETTE[clampi(int(bx[2]), 0, VoxelWorld.PALETTE.size() - 1)]
				_box(lo, hi, colour)


func _box(lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for q: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]:
		_triangle(p[q[0]], p[q[1]], p[q[2]], c)
		_triangle(p[q[0]], p[q[2]], p[q[3]], c)


## The roads as strips of packed earth over the ground (as ZoneRoads lays them).
func _roads() -> void:
	for road: Array in def.get("roads", []):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		var length := a.distance_to(b)
		var d := (b - a) / length
		var side := Vector2(-d.y, d.x) * ZoneRoads.WIDTH_M * 0.5
		var t := 0.0
		while t < length:
			var p0 := a + d * t
			var p1 := a + d * minf(t + 4.0, length)
			if not ZoneRoads._on_pad(terrain, p0) and not ZoneRoads._on_pad(terrain, p1):
				var q := [p0 - side, p0 + side, p1 + side, p1 - side]
				var v: Array = []
				for e: Vector2 in q:
					v.append(Vector3(e.x, terrain.height_at(e.x, e.y) + 0.06, e.y))
				_triangle(v[0], v[1], v[2], terrain.c_road)
				_triangle(v[0], v[2], v[3], terrain.c_road)
			t += 4.0


## The scatter round the view, as visual_parts draws it, and the wires between poles.
func _scatter(eye: Vector3) -> void:
	var fwd := -_cam.basis.z
	for index in scatter.items.size():
		var item: Dictionary = scatter.items[index]
		var p: Vector3 = item.pos
		var d := Vector2(p.x - eye.x, p.z - eye.z)
		var big := String(item.get("shape", "")) in ["pylon", "power_pole_h", "water_tower", "windpump", "billboard"]
		if d.length() > (SEE_BIG_M if big else SEE_M):
			continue
		if d.length() > 12.0 and Vector2(fwd.x, fwd.z).normalized().dot(d.normalized()) < 0.35:
			continue  # behind the camera
		for part: Array in scatter.visual_parts(item):
			_mesh(part[0], part[1], part[2])
		if int(item.get("link", 0)) == 1 and index > 0:
			var list: Array = []
			scatter._wires(scatter.items[index - 1], item, list)
			for w: Array in list:
				var xf: Transform3D = w[0]
				_line(xf.origin, xf * Vector3(0, 0, 1), Color("2a2b2e"))


func _animals(eye: Vector3) -> void:
	var zoo := ZoneAnimals.new()
	zoo.setup(scatter, terrain)
	for a: Dictionary in zoo.animals:
		var p: Vector2 = a.pos
		if p.distance_to(Vector2(eye.x, eye.z)) > 200.0:
			continue
		_mesh("lib:%s#%d" % [a.species, a.coat], Transform3D(Basis(Vector3.UP, float(a.face)), Vector3(p.x, terrain.height_at(p.x, p.y), p.y)), Color.WHITE)
	zoo.free()


## A mesh by group key (a library prop's, or the scatter's own), placed by `xf`, tinted `tint`.
func _mesh(key: Variant, xf: Transform3D, tint: Color) -> void:
	if not _arrays.has(key):
		var mesh: Mesh = null
		if key is String and String(key).begins_with(ZoneScatter.LIBRARY):
			var np := String(key).trim_prefix(ZoneScatter.LIBRARY)
			mesh = PropArt.mesh(np.get_slice("#", 0), int(np.get_slice("#", 1)))
		elif scatter:
			mesh = scatter._meshes.get(key)
		if mesh == null:
			_arrays[key] = null
		else:
			var arrays := mesh.surface_get_arrays(0)
			_arrays[key] = [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR]]
	var a: Variant = _arrays[key]
	if a == null:
		return
	var verts: PackedVector3Array = a[0]
	var cols: PackedColorArray = a[1]
	for t in range(0, verts.size(), 3):
		var c := cols[t] * tint if cols.size() > t else tint
		_triangle(xf * verts[t], xf * verts[t + 1], xf * verts[t + 2], c)


## A triangle in the world: lit by the sun by its facing, fogged by distance, clipped at the near
## plane, filled into the depth buffer.
func _triangle(a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var mid := (a + b + c) / 3.0
	if n.dot(_cam.origin - mid) < 0.0:
		n = -n  # (the side we see)
	var light := 0.42 + 0.58 * maxf(n.dot(_sun), 0.0)
	var shade := Color(colour.r * light, colour.g * light, colour.b * light)
	var fog := 1.0 - exp(-mid.distance_to(_cam.origin) / FOG_M)
	shade = shade.lerp(SKY_LOW, clampf(fog, 0.0, 0.85))
	var pa := _view * a
	var pb := _view * b
	var pc := _view * c
	var poly: Array = [pa, pb, pc]
	if pa.z > -NEAR or pb.z > -NEAR or pc.z > -NEAR:
		poly = _clip(poly)
		if poly.size() < 3:
			return
	for i in range(1, poly.size() - 1):
		_fill(poly[0], poly[i], poly[i + 1], shade)
	_tris += 1


## `poly` (camera space) clipped to in front of the near plane.
static func _clip(poly: Array) -> Array:
	var outp: Array = []
	for i in poly.size():
		var p: Vector3 = poly[i]
		var q: Vector3 = poly[(i + 1) % poly.size()]
		var pin := p.z <= -NEAR
		var qin := q.z <= -NEAR
		if pin:
			outp.append(p)
		if pin != qin:
			var t := (-NEAR - p.z) / (q.z - p.z)
			outp.append(p.lerp(q, t))
	return outp


func _fill(a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var za := 1.0 / -a.z
	var zb := 1.0 / -b.z
	var zc := 1.0 / -c.z
	var ax := W * 0.5 + _focal * a.x * za
	var ay := H * 0.5 - _focal * a.y * za
	var bx := W * 0.5 + _focal * b.x * zb
	var by := H * 0.5 - _focal * b.y * zb
	var cx := W * 0.5 + _focal * c.x * zc
	var cy := H * 0.5 - _focal * c.y * zc
	var area := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	if absf(area) < 1e-6:
		return
	var x0 := maxi(int(floorf(minf(ax, minf(bx, cx)))), 0)
	var x1 := mini(int(ceilf(maxf(ax, maxf(bx, cx)))), W - 1)
	var y0 := maxi(int(floorf(minf(ay, minf(by, cy)))), 0)
	var y1 := mini(int(ceilf(maxf(ay, maxf(by, cy)))), H - 1)
	if x0 > x1 or y0 > y1:
		return
	var inv := 1.0 / area
	for y in range(y0, y1 + 1):
		var py := y + 0.5
		for x in range(x0, x1 + 1):
			var px := x + 0.5
			var w0 := ((bx - px) * (cy - py) - (by - py) * (cx - px)) * inv
			var w1 := ((cx - px) * (ay - py) - (cy - py) * (ax - px)) * inv
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var depth := w0 * za + w1 * zb + w2 * zc
			var k := y * W + x
			if depth <= _depth[k]:
				continue
			_depth[k] = depth
			_img.set_pixel(x, y, colour)


## A one-pixel line (wires), depth tested.
func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	var pa := _view * a
	var pb := _view * b
	if pa.z > -NEAR or pb.z > -NEAR:
		return
	var steps := 0
	var sa := Vector2(W * 0.5 + _focal * pa.x / -pa.z, H * 0.5 - _focal * pa.y / -pa.z)
	var sb := Vector2(W * 0.5 + _focal * pb.x / -pb.z, H * 0.5 - _focal * pb.y / -pb.z)
	steps = int(maxf(absf(sb.x - sa.x), absf(sb.y - sa.y))) + 1
	if steps > 4000:
		return
	for i in steps + 1:
		var t := float(i) / steps
		var s := sa.lerp(sb, t)
		var x := int(s.x)
		var y := int(s.y)
		if x < 0 or y < 0 or x >= W or y >= H:
			continue
		var depth := 1.0 / lerpf(-pa.z, -pb.z, t)
		if depth + 0.0005 < _depth[y * W + x]:
			continue
		_img.set_pixel(x, y, colour)
