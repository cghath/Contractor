extends Node
## Soldier model sheets without a window (model realism pass, 2026-10-26): screenshot scripts
## (tests/*_shots.gd) need a real window, so this draws the soldiers' meshes itself, headless,
## into PNGs: each soldier front, three-quarter, side and back, orthographic, flat-lit from the
## vertex colours. Run it as an S run (docs/debugging.md):
##   <voxel godot exe> --headless --path . res://tools/model_render.tscn -- <output folder> [px per m]
## Small gear past SMALL_GEAR_M and the far LOD never draw here (everything is at the camera).

const PX_PER_M := 420.0
## [name, body, role ("" none: the uniform alone), variant, (optional) more item ids to give,
## (optional) a launcher shouldered as LauncherRig holds it]
const SOLDIERS := [
	["uniform_m", "male", "", "multicam"],
	["uniform_f", "female", "", "multicam"],
	["rifleman_m", "male", "rifleman", "multicam"],
	["rifleman_f", "female", "rifleman", "multicam"],
	["medic_m", "male", "medic", "woodland"],
	["leader_f", "female", "team_leader", "desert"],
	["gunner_m", "male", "autorifleman", "black"],
	["headset_m", "male", "", "woodland", ["ear_comtac", "m17", "mag_9mm", "mag_9mm"]],
	["rpg_m", "male", "", "urban", [], "rpg7"],
	["at4_f", "female", "rifleman", "multicam", [], "at4"],
	["maaws_m", "male", "", "desert", [], "maaws"],
]
## [label, view direction (camera into the scene), up]
const VIEWS := [
	["front", Vector3(0, 0, 1)],
	["three_quarter", Vector3(-0.7071, 0, 0.7071)],
	["side", Vector3(-1, 0, 0)],
	["back", Vector3(0, 0, -1)],
]
const LIGHT := Vector3(-0.45, 0.75, -0.5)

var out := "user://model_render"
var px_per_m := PX_PER_M
var crop := Vector2(-INF, INF)  # "crop=<lo>,<hi>": only that band of heights (m), e.g. the upper body


func _ready() -> void:
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		print("[render] deadline passed, quitting")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	if args.size() > 1:
		px_per_m = float(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	var only := args.slice(2)
	for a: String in only.duplicate():
		if a.begins_with("crop="):
			var r := a.trim_prefix("crop=").split(",")
			crop = Vector2(float(r[0]), float(r[1]))
			only.erase(a)
	for s: Array in SOLDIERS:
		if not only.is_empty() and not only.has(s[0]):
			continue
		var root := await _dress(s)
		var sheet := _sheet(root)
		var path := out.path_join("%s.png" % s[0])
		sheet.save_png(path)
		print("[render] wrote ", path)
		root.queue_free()
		await get_tree().process_frame
	print("[render] done")
	get_tree().quit(0)


func _dress(s: Array) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	root.add_child(inventory)
	var model := CharacterModel.new()
	model.name = "Model"
	model.variant = String(s[3])
	model.body = String(s[1])
	model.name_tape = "REYES"
	model.iff = GearRig.iff_of(&"friendly", &"", model.variant)
	model.lod = false
	root.add_child(model)
	var gear := GearRig.new()
	gear.name = "Gear"
	gear.inventory = inventory
	gear.model = model
	root.add_child(gear)
	if String(s[2]) != "":
		Roles.apply_kit(inventory, StringName(s[2]))
	for id: String in (s[4] if s.size() > 4 else []):
		Roles.give(inventory, StringName(id), 1)
	model.hold = CharacterModel.Hold.NONE
	var tube: Node3D = null
	var item: ItemData = ItemDB.get_item(StringName(s[5])) if s.size() > 5 else null
	if item:
		tube = LauncherRig.make_model(item)
		root.add_child(tube)
	for i in 40:
		if tube:  # (as LauncherRig does, every frame)
			var hold := LauncherRig.hold_points(item)
			tube.global_transform = model.hands_anchor.global_transform * Transform3D(Basis.IDENTITY, LauncherRig.SHOULDER - hold[0])
			model.set_held(tube, hold[1], hold[2])
		await get_tree().process_frame
	VoxelArt.finish_warm()
	for i in 10:
		await get_tree().process_frame
	if s.size() > 5:
		print("[render] %s held %s: hold %s, hand error %.3f m" % [s[0], s[5], LauncherRig.hold_points(ItemDB.get_item(StringName(s[5]))), model.hand_error()])
	return root


## Every drawn triangle under `root`, world space, with its colours: [a, b, c, colour a, b, c].
func _triangles(root: Node) -> Array:
	var tris: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n.name == VoxelArt.FAR_LOD:
			continue
		for c in n.get_children():
			stack.append(c)
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		var albedo := Color.WHITE
		var mat := mi.material_override as StandardMaterial3D
		var use_vc := true
		if mat and not mat.vertex_color_use_as_albedo:
			use_vc = false
			albedo = mat.albedo_color
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if not use_vc or cols.size() != verts.size():
				var smat := mi.mesh.surface_get_material(si) as StandardMaterial3D
				if smat and not use_vc:
					albedo = smat.albedo_color
				cols = PackedColorArray()
				cols.resize(verts.size())
				cols.fill(albedo)
			var w := PackedVector3Array()
			w.resize(verts.size())
			for i in verts.size():
				w[i] = xf * verts[i]
			var count := idx.size() if not idx.is_empty() else verts.size()
			for t in range(0, count, 3):
				var i0 := idx[t] if not idx.is_empty() else t
				var i1 := idx[t + 1] if not idx.is_empty() else t + 1
				var i2 := idx[t + 2] if not idx.is_empty() else t + 2
				tris.append([w[i0], w[i1], w[i2], cols[i0]])
	return tris


func _sheet(root: Node3D) -> Image:
	var tris := _triangles(root)
	var box := AABB()
	var first := true
	for t: Array in tris:
		for k in 3:
			if first:
				box = AABB(t[k], Vector3.ZERO)
				first = false
			else:
				box = box.expand(t[k])
	if crop.x > box.position.y or crop.y < box.end.y:
		var lo := maxf(crop.x, box.position.y)
		var hi := minf(crop.y, box.end.y)
		box = AABB(Vector3(box.position.x, lo, box.position.z), Vector3(box.size.x, hi - lo, box.size.z))
	var centre := box.get_center()
	var half := maxf(box.size.x, box.size.z) * 0.75 + 0.05
	var w := int(ceil(half * 2.0 * px_per_m))
	var h := int(ceil((box.size.y + 0.1) * px_per_m))
	var sheet := Image.create(w * VIEWS.size(), h + 18, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.83, 0.85, 0.87))
	for vi in VIEWS.size():
		var d: Vector3 = (VIEWS[vi][1] as Vector3).normalized()
		var right := d.cross(Vector3.UP).normalized()
		var img := _draw(tris, d, right, centre, box.position.y - 0.05, w, h)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(vi * w, 18))
		# a grid line every 10 cm up the side of each view
		for cm in range(0, int(box.size.y * 100.0) + 10, 10):
			var y := 18 + h - 1 - int(cm * 0.01 * px_per_m)
			if y >= 18 and y < h + 18:
				for x in range(vi * w, vi * w + (8 if cm % 50 else 16)):
					sheet.set_pixel(x, y, Color(0.3, 0.3, 0.3))
	return sheet


func _draw(tris: Array, d: Vector3, right: Vector3, centre: Vector3, floor_y: float, w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.83, 0.85, 0.87))
	var depth := PackedFloat32Array()
	depth.resize(w * h)
	depth.fill(INF)
	var light := LIGHT.normalized()
	for t: Array in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		if n.dot(d) > 0.0:
			n = -n  # (a two-sided view: the face towards the camera)
		var shade := 0.5 + 0.5 * maxf(0.0, n.dot(light)) + 0.12 * maxf(0.0, -n.dot(d))
		var col: Color = t[3]
		col = Color(col.r * shade, col.g * shade, col.b * shade)
		var p := [_project(a, d, right, centre, floor_y, w, h), _project(b, d, right, centre, floor_y, w, h), _project(c, d, right, centre, floor_y, w, h)]
		var x0 := maxi(0, int(floor(minf(p[0].x, minf(p[1].x, p[2].x)))))
		var x1 := mini(w - 1, int(ceil(maxf(p[0].x, maxf(p[1].x, p[2].x)))))
		var y0 := maxi(0, int(floor(minf(p[0].y, minf(p[1].y, p[2].y)))))
		var y1 := mini(h - 1, int(ceil(maxf(p[0].y, maxf(p[1].y, p[2].y)))))
		var p0: Vector3 = p[0]
		var p1: Vector3 = p[1]
		var p2: Vector3 = p[2]
		var area := (p1.x - p0.x) * (p2.y - p0.y) - (p1.y - p0.y) * (p2.x - p0.x)
		if absf(area) < 1e-9:
			continue
		for y in range(y0, y1 + 1):
			var py := y + 0.5
			for x in range(x0, x1 + 1):
				var px := x + 0.5
				var w0 := ((p1.x - px) * (p2.y - py) - (p1.y - py) * (p2.x - px)) / area
				var w1 := ((p2.x - px) * (p0.y - py) - (p2.y - py) * (p0.x - px)) / area
				var w2 := 1.0 - w0 - w1
				if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
					continue
				var z := w0 * p0.z + w1 * p1.z + w2 * p2.z
				var k := y * w + x
				if z < depth[k]:
					depth[k] = z
					img.set_pixel(x, y, col)
	return img


func _project(v: Vector3, d: Vector3, right: Vector3, centre: Vector3, floor_y: float, w: int, h: int) -> Vector3:
	var rel := v - centre
	return Vector3(w * 0.5 + rel.dot(right) * px_per_m, h - (v.y - floor_y) * px_per_m, rel.dot(d))
