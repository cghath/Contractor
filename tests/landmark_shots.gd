extends Node
## Pictures of every landmark (queue item 1.4; docs/building_gen.md "Landmarks"), headless: no
## window opens (Captain may be playing on this PC), so instead of the renderer it draws the
## boxes itself, an orthographic view from the front-right and above, each box face flat-shaded
## in its material's palette colour (VoxelWorld.PALETTE) with its edges darkened, through a depth
## buffer. Not the game's look (no lighting, no voxel jitter): the shapes, colours and layout.
##   <voxel godot exe> --headless --path . res://tests/landmark_shots.tscn -- [output folder] [seed]
## Default folder: %TEMP%\contractor_world_shots (never the repo). One PNG a site kind and state
## (BuildingGen.site: <kind>_intact.png, _ruined.png, _bombed.png); SHOTS_ONLY=mosque,church
## for some. Keep the run as an S run (docs/debugging.md) when it's for a record.

const W := 1200
const H := 900
## The view: looking this way (from the front-right, above).
const VIEW := Vector3(-0.55, -0.62, -1.0)
const SKY := Color("c9d6dc")
const GROUND := Color("9a9a7c")

var out := ""
var _rgb := PackedByteArray()
var _depth := PackedFloat32Array()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 and String(args[0]) != "" else OS.get_environment("TEMP").path_join("contractor_world_shots")
	var seed_value := int(args[1]) if args.size() > 1 else 5
	DirAccess.make_dir_recursive_absolute(out)
	var kinds: Array = BuildingGen.SITE_KINDS
	var only := OS.get_environment("SHOTS_ONLY")
	if only != "":
		kinds = only.split(",")
	for kind: String in kinds:
		for state in 3:
			var started := Time.get_ticks_msec()
			var s := BuildingGen.site(kind, seed_value, state)
			var path := out.path_join("%s_%s.png" % [kind, ["intact", "ruined", "bombed"][state]])
			_draw(s, path)
			print("[shots] %s: %d boxes, %d skin, %d ms" % [path, (s.boxes as Array).size(), (s.skin as Array).size(), Time.get_ticks_msec() - started])
	print("[shots] done: %s" % out)
	get_tree().quit()


## The basis of the view: right, up, forward (into the scene).
func _basis() -> Array[Vector3]:
	var f := VIEW.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f).normalized()
	return [r, u, f]


## Site `s` drawn to `path`: its boxes and skin on its ground (its pad; a harbour's sea round it).
func _draw(s: Dictionary, path: String) -> void:
	var boxes: Array = s.boxes
	var skin: Array = s.skin
	var streets: Array = s.streets
	var b := _basis()
	var r: Vector3 = b[0]
	var u: Vector3 = b[1]
	var f: Vector3 = b[2]
	# Fit everything (and a ground plate under it) in the picture.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for list: Array in [boxes, skin]:
		for bx: Array in list:
			lo = lo.min(bx[0])
			hi = hi.max(bx[1])
	var plate := [Vector3(lo.x - 3.0, -0.05, lo.z - 3.0), Vector3(hi.x + 3.0, 0.0, hi.z + 3.0)]
	var min_s := Vector2(INF, INF)
	var max_s := Vector2(-INF, -INF)
	for corner in 8:
		var p := Vector3(plate[0].x if corner & 1 == 0 else plate[1].x, lo.y if corner & 2 == 0 else hi.y, plate[0].z if corner & 4 == 0 else plate[1].z)
		var q := Vector2(p.dot(r), -p.dot(u))
		min_s = min_s.min(q)
		max_s = max_s.max(q)
	var scale := minf((W - 40.0) / (max_s.x - min_s.x), (H - 40.0) / (max_s.y - min_s.y))
	var off := Vector2(W, H) * 0.5 - (min_s + max_s) * 0.5 * scale
	_rgb.resize(W * H * 3)
	_depth.resize(W * H)
	for i in W * H:
		_rgb[i * 3] = int(SKY.r8)
		_rgb[i * 3 + 1] = int(SKY.g8)
		_rgb[i * 3 + 2] = int(SKY.b8)
		_depth[i] = INF
	if is_nan(float(s.pad_sea)):
		_box(plate[0], plate[1], GROUND, r, u, f, scale, off, 0.0)
	else:  # the sea, and the harbour's land built up out of it
		var sea := -float(s.pad_sea)
		_box(Vector3(plate[0].x, sea - 0.05, plate[0].z), Vector3(plate[1].x, sea, plate[1].z), Color("3f6d8c"), r, u, f, scale, off, 0.0)
		var pad: Rect2 = (s.pad as Rect2).grow(ZoneTerrain.PAD_MARGIN_M)
		_box(Vector3(pad.position.x, sea - 0.05, pad.position.y), Vector3(pad.end.x, -0.01, pad.end.y), GROUND, r, u, f, scale, off, 0.0)
	for st: Rect2 in streets:  # hard standing: a runway, a forecourt, a quay
		_box(Vector3(st.position.x, -0.04, st.position.y), Vector3(st.end.x, 0.005, st.end.y), Color("6f6e66"), r, u, f, scale, off, 0.0)
	for bx: Array in boxes:
		_box(bx[0], bx[1], VoxelWorld.PALETTE[int(bx[2])], r, u, f, scale, off, 0.0)
	for bx: Array in skin:
		_box(bx[0], bx[1], VoxelWorld.PALETTE[int(bx[2])], r, u, f, scale, off, 0.02)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, _rgb)
	img.save_png(path)


## Box `a`-`c` in colour `col`: its three faces toward the view, each a parallelogram filled
## through the depth buffer (`bias`: drawn over faces it lies on, as a skin does).
func _box(a: Vector3, c: Vector3, col: Color, r: Vector3, u: Vector3, f: Vector3, scale: float, off: Vector2, bias: float) -> void:
	var size := c - a
	# The faces toward the view (it looks along -x, -y, -z): +x, +y, +z. [corner, edge 1, edge 2, shade]
	var faces := [
		[Vector3(c.x, a.y, a.z), Vector3(0, size.y, 0), Vector3(0, 0, size.z), 0.7],
		[Vector3(a.x, c.y, a.z), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), 1.0],
		[Vector3(a.x, a.y, c.z), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), 0.84],
	]
	for face: Array in faces:
		var p0: Vector3 = face[0]
		var e1: Vector3 = face[1]
		var e2: Vector3 = face[2]
		var shade: float = face[3]
		var s0 := Vector2(p0.dot(r), -p0.dot(u)) * scale + off
		var s1 := Vector2(e1.dot(r), -e1.dot(u)) * scale
		var s2 := Vector2(e2.dot(r), -e2.dot(u)) * scale
		var det := s1.x * s2.y - s1.y * s2.x
		if absf(det) < 0.01:
			continue
		var d0 := p0.dot(f) - bias
		var d1 := e1.dot(f)
		var d2 := e2.dot(f)
		var x0 := maxi(0, floori(minf(minf(s0.x, s0.x + s1.x), minf(s0.x + s2.x, s0.x + s1.x + s2.x))))
		var x1 := mini(W - 1, ceili(maxf(maxf(s0.x, s0.x + s1.x), maxf(s0.x + s2.x, s0.x + s1.x + s2.x))))
		var y0 := maxi(0, floori(minf(minf(s0.y, s0.y + s1.y), minf(s0.y + s2.y, s0.y + s1.y + s2.y))))
		var y1 := mini(H - 1, ceili(maxf(maxf(s0.y, s0.y + s1.y), maxf(s0.y + s2.y, s0.y + s1.y + s2.y))))
		var edge_s := 1.2 / maxf(s1.length(), 1.0)
		var edge_t := 1.2 / maxf(s2.length(), 1.0)
		var base := col * shade
		var dark := base * 0.72
		var cr := [int(clampf(base.r, 0, 1) * 255), int(clampf(base.g, 0, 1) * 255), int(clampf(base.b, 0, 1) * 255)]
		var dr := [int(clampf(dark.r, 0, 1) * 255), int(clampf(dark.g, 0, 1) * 255), int(clampf(dark.b, 0, 1) * 255)]
		for y in range(y0, y1 + 1):
			var py := y + 0.5 - s0.y
			for x in range(x0, x1 + 1):
				var px := x + 0.5 - s0.x
				var s := (px * s2.y - py * s2.x) / det
				if s < 0.0 or s > 1.0:
					continue
				var t := (py * s1.x - px * s1.y) / det
				if t < 0.0 or t > 1.0:
					continue
				var depth := d0 + s * d1 + t * d2
				var i := y * W + x
				if depth >= _depth[i]:
					continue
				_depth[i] = depth
				var edge := s < edge_s or s > 1.0 - edge_s or t < edge_t or t > 1.0 - edge_t
				var px3 := i * 3
				var cc: Array = dr if edge else cr
				_rgb[px3] = cc[0]
				_rgb[px3 + 1] = cc[1]
				_rgb[px3 + 2] = cc[2]
