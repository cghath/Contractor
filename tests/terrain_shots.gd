extends Node
## Pictures of the terrain presets and features (queue item 1.3; docs/terrain_presets.md), headless:
## no window opens (Captain may be playing on this PC), so instead of the renderer it draws the
## ground itself from the heights, the ground's own vertex colours (ZoneTerrain.vertex_colour: the
## palette, fields and crops, marsh, snow, gullies, roads), the water (blue; ice pale) and the crops
## and reed beds standing on it, lit by a low sun with haze:
## - <name>_map.png: the whole zone from above (hill-shaded), the scatter's trees and rocks as dots;
## - <name>_view.png: a perspective view from a man's height a little up a rise, toward its most
##   telling feature (a cliff's face, a gully, the fields, the marsh), drawn column by column
##   front to back (a height-field "voxel space" render). Not the game's look (no shader breakup, no
##   tree meshes): the shapes, colours and layout.
##   <voxel godot exe> --headless --path . res://tests/terrain_shots.tscn -- [output folder] [only]
## Default folder: %TEMP%\contractor_world_shots (never the repo); `only`: a comma list of the shot
## names below. Keep the run as an S run (docs/debugging.md) when it's for a record.

const MAP_PX := 720
const VIEW_W := 960
const VIEW_H := 540
const VIEW_FAR_M := 900.0
const SUN := Vector3(-0.55, 0.62, -0.56)
const SKY := Color("b9c9d6")
const WATER := Color("3f6f80")
const ICE := Color("c9dbe4")

## The shots: name -> [preset, seed, season, what to look at].
const SHOTS := {
	"marsh": ["marsh", 11917, "summer", "marsh"],
	"snow_winter": ["snow_mountain", 12018, "winter", "cliff"],
	"snow_summer": ["snow_mountain", 12018, "summer", "cliff"],
	"farmland_spring": ["farmland", 12119, "spring", "fields"],
	"farmland_summer": ["farmland", 12119, "summer", "fields"],
	"farmland_autumn": ["farmland", 12119, "autumn", "fields"],
	"farmland_winter": ["farmland", 12119, "winter", "fields"],
	"ridge_cliffs": ["rocky_ridge", 8801, "summer", "cliff"],
	"temperate_gully": ["temperate", 7701, "summer", "gully"],
}

var out := ""
var _colours := PackedColorArray()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = String(args[0]) if args.size() > 0 and String(args[0]) != "" else OS.get_environment("TEMP").path_join("contractor_world_shots")
	var only: Array = String(args[1]).split(",") if args.size() > 1 else []
	DirAccess.make_dir_recursive_absolute(out)
	for shot: String in SHOTS:
		if not only.is_empty() and not shot in only:
			continue
		var spec: Array = SHOTS[shot]
		var started := Time.get_ticks_msec()
		var def := ZoneDef.normalize(ZoneDef.generate(int(spec[1]), 1536.0).merged({"terrain": spec[0], "id": "shots", "name": "Shots", "season": spec[2]}, true))
		var t := ZoneTerrain.new()
		t.generate(def, _flat(def))
		var s := ZoneScatter.new()
		s.generate(t, def)
		_cache_colours(t)
		_map(t, s, out.path_join("%s_map.png" % shot))
		var eye := _view_from(t, String(spec[3]))
		_view(t, eye[0], eye[1], out.path_join("%s_view.png" % shot))
		var f := t.features
		print("[shots] %s (%s, %s): %d cliffs, %d gullies/ditches, %d fields, %d water bodies, %d scatter items, %d ms" % [shot, spec[0], spec[2],
			f.cliffs.size() if f else 0, f.lines.size() if f else 0, f.field_crops.size() if f else 0, t.water.bodies.size() if t.water else 0, s.total(),
			Time.get_ticks_msec() - started])
		s.free()
		t.free()
	print("[shots] done: %s" % out)
	get_tree().quit(0)


static func _flat(def: Dictionary) -> Array:
	var flat: Array = []
	for m: Dictionary in def.modules:
		flat.append(ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))))
	for p: Array in def.extraction:
		flat.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.insertion:
		flat.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return flat


func _cache_colours(t: ZoneTerrain) -> void:
	_colours.resize(t.points * t.points)
	for j in t.points:
		for i in t.points:
			_colours[i + j * t.points] = t.vertex_colour(i, j)


## The ground's colour at (x, z): the nearest height points' colours blended, water over it.
func _ground(t: ZoneTerrain, x: float, z: float) -> Color:
	var g := Vector2((x + t.size_m * 0.5) / ZoneTerrain.CELL_M, (z + t.size_m * 0.5) / ZoneTerrain.CELL_M)
	var i := clampi(floori(g.x), 0, t.points - 2)
	var j := clampi(floori(g.y), 0, t.points - 2)
	var fx := clampf(g.x - i, 0.0, 1.0)
	var fz := clampf(g.y - j, 0.0, 1.0)
	var n := t.points
	var c := _colours[i + j * n].lerp(_colours[i + 1 + j * n], fx).lerp(_colours[i + (j + 1) * n].lerp(_colours[i + 1 + (j + 1) * n], fx), fz)
	var shade := clampf(t.normal_at(x, z).dot(SUN.normalized()), 0.0, 1.0)
	c = c * (0.45 + 0.75 * shade)
	var w := t.water_height(x, z)
	if w > t.height_at(x, z):
		c = c.lerp(WATER, clampf(0.55 + (w - t.height_at(x, z)) * 0.3, 0.0, 0.9))
	elif t.water and t.water._ice.has(_index(t, x, z)):
		c = c.lerp(ICE, 0.85)
	return c


static func _index(t: ZoneTerrain, x: float, z: float) -> int:
	var i := clampi(roundi((x + t.size_m * 0.5) / ZoneTerrain.CELL_M), 0, t.points - 1)
	var j := clampi(roundi((z + t.size_m * 0.5) / ZoneTerrain.CELL_M), 0, t.points - 1)
	return i + j * t.points


func _map(t: ZoneTerrain, s: ZoneScatter, path: String) -> void:
	var img := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGB8)
	var m := t.size_m / MAP_PX
	for py in MAP_PX:
		for px in MAP_PX:
			var x := (px + 0.5) * m - t.size_m * 0.5
			var z := (py + 0.5) * m - t.size_m * 0.5
			img.set_pixel(px, py, _ground(t, x, z))
	for item: Dictionary in s.items:
		var kind := int(item.kind)
		if kind != ZoneScatter.Kind.TREE and not (kind == ZoneScatter.Kind.ROCK and bool(item.solid)):
			continue
		var p: Vector3 = item.pos
		var px := int((p.x + t.size_m * 0.5) / m)
		var py := int((p.z + t.size_m * 0.5) / m)
		if px >= 0 and py >= 0 and px < MAP_PX and py < MAP_PX:
			img.set_pixel(px, py, (item.colour as Color).darkened(0.35) if kind == ZoneScatter.Kind.TREE else Color("8a8780"))
	img.save_png(path)


## Where to stand and look from for `what`: [eye (Vector3), the way it looks (Vector2, unit)].
func _view_from(t: ZoneTerrain, what: String) -> Array:
	var f := t.features
	var target := Vector2.ZERO
	var from := Vector2(0.0, 300.0)
	var up := 9.0
	if f and what == "cliff" and not f.cliffs.is_empty():
		var c: Dictionary = f.cliffs[0]
		var foot := f.cliff_point(c, 0.5, -1.0)
		target = Vector2(foot.x, foot.z)
		from = target - (c.normal as Vector2) * 110.0 + (c.dir as Vector2) * 50.0
		up = 16.0
	elif f and what == "gully":
		for l: Dictionary in f.lines:
			if String(l.kind) == "gully":
				var pts: PackedVector2Array = l.pts
				target = pts[pts.size() / 2]
				var along := (pts[pts.size() / 2 + 1] - pts[pts.size() / 2 - 1]).normalized()
				from = target - along * 45.0 + Vector2(-along.y, along.x) * 18.0
				break
	elif f and what == "fields":
		var d := Vector2(1.0, -1.0).normalized()
		for k in 600:
			var p := Vector2(fposmod(k * 37.1, t.size_m * 0.6) - t.size_m * 0.3, fposmod(k * 53.9, t.size_m * 0.6) - t.size_m * 0.3)
			if f.field_at(p.x, p.y) >= 0 and f.field_at(p.x + d.x * 120.0, p.y + d.y * 120.0) >= 0 and f.field_at(p.x + d.x * 240.0, p.y + d.y * 240.0) >= 0:
				from = p
				target = p + d * 240.0
				break
		up = 5.0
	elif f and what == "marsh":
		for k in 400:
			var p := Vector2(fposmod(k * 37.1, t.size_m * 0.6) - t.size_m * 0.3, fposmod(k * 53.9, t.size_m * 0.6) - t.size_m * 0.3)
			if f.reeds_at(p.x, p.y) > 0.6:
				target = p
				from = p + Vector2(-90.0, 90.0)
				break
	var eye := Vector3(from.x, t.height_at(from.x, from.y) + up, from.y)
	return [eye, (target - from).normalized()]


## A perspective view from `eye` looking along `look` (flat), the ground drawn column by column
## front to back with what stands on it (crops, reeds) and haze.
func _view(t: ZoneTerrain, eye: Vector3, look: Vector2, path: String) -> void:
	var img := Image.create(VIEW_W, VIEW_H, false, Image.FORMAT_RGB8)
	for py in VIEW_H:
		var sky := SKY.lerp(Color("6f8fb5"), clampf(1.0 - float(py) / (VIEW_H * 0.45), 0.0, 1.0))
		for px in VIEW_W:
			img.set_pixel(px, py, sky)
	var horizon := VIEW_H * 0.42
	var focal := VIEW_W * 0.5 / tan(deg_to_rad(35.0))
	var right := Vector2(-look.y, look.x)
	var f := t.features
	for px in VIEW_W:
		var a := (px - VIEW_W * 0.5) / focal
		var dir := (look + right * a)
		var lowest := VIEW_H
		var dz := 0.5
		var z := 4.0
		while z < VIEW_FAR_M and lowest > 0:
			var p := Vector2(eye.x, eye.z) + dir * z
			if absf(p.x) > t.size_m * 0.5 or absf(p.y) > t.size_m * 0.5:
				break
			var h := maxf(t.height_at(p.x, p.y), t.water_height(p.x, p.y))
			var colour := _ground(t, p.x, p.y)
			if f:
				var cover := f.cover_at(p.x, p.y)
				var crop := f.crop_of(f.field_at(p.x, p.y)) if not f.field_cols.is_empty() else {}
				if not crop.is_empty() and float(crop.height) > 0.12:
					h += float(crop.height)
					colour = (crop.colour as Color) * 0.95
				elif cover.x > 0.0:
					h += cover.x
					colour = Color("7d7a46")
			var sy := int(horizon - (h - eye.y) / z * focal)
			if sy < lowest:
				var haze := clampf(z / VIEW_FAR_M, 0.0, 1.0)
				var c := colour.lerp(SKY, haze * 0.75)
				for y in range(maxi(sy, 0), lowest):
					img.set_pixel(px, y, c)
				lowest = maxi(sy, 0)
			z += dz
			dz = minf(dz * 1.012, 4.0)
	img.save_png(path)
