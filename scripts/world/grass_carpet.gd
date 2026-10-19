class_name GrassCarpet
extends MultiMeshInstance3D
## Grass near the camera (Captain, 2026-10-18: "the terrain itself, the ground and our props also
## need a pass"): ZoneScatter's tufts are laid per 128 m cell at about one per 16 m² (too few to
## read as grass up close, and more across a 16 km² zone would cost too much), so this lays a
## carpet of small tufts only round the camera: one every SPACING_M on a grid (jittered by the
## cell, so it stays put as you move), out to RADIUS_M, thinning over the last EDGE_SHARE of it
## so there's no edge. Re-laid when the camera has moved SNAP_M. Off roads and pads, out of the
## water, off steep ground, out of craters and dug earth (GroundCuts.bare; re-laid when the
## ground is cut), in the scatter's tuft colours. Visual only: no collision, no sight
## blocking. Never on a headless server (ZoneLevel adds it with the visuals).

const RADIUS_M := 28.0
const SPACING_M := 0.75
const EDGE_SHARE := 0.35
const SNAP_M := 6.0
const SIZE := Vector2(0.35, 0.75)
const MIN_UP := 0.8

var _scatter: ZoneScatter
var _terrain: ZoneTerrain
var _centre := Vector2(INF, INF)
var _colours: Array[Color] = []
var _cut_seen := 0  # GroundCuts.version the carpet was laid for


func setup(scatter: ZoneScatter, terrain: ZoneTerrain, mesh: Mesh, material: Material, colours: Array[Color]) -> void:
	_scatter = scatter
	_terrain = terrain
	_colours = colours if not colours.is_empty() else ([Color("6f7040")] as Array[Color])
	name = "GrassCarpet"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _terrain == null:
		return
	var at := Vector2(camera.global_position.x, camera.global_position.z)
	var cut_now := _terrain.cuts.version if _terrain.cuts else 0
	if at.distance_to(_centre) < SNAP_M and cut_now == _cut_seen:
		return
	_cut_seen = cut_now
	_centre = (at / SNAP_M).round() * SNAP_M
	lay(_centre)


## Lays the carpet round `centre` (x, z). Returns how many tufts.
func lay(centre: Vector2) -> int:
	var list: Array = []
	var n := int(ceil(RADIUS_M / SPACING_M))
	var gx0 := int(floor(centre.x / SPACING_M))
	var gz0 := int(floor(centre.y / SPACING_M))
	var half := _terrain.size_m * 0.5
	for gz in range(gz0 - n, gz0 + n + 1):
		for gx in range(gx0 - n, gx0 + n + 1):
			var h1 := _hash(gx, gz)
			var x := (gx + h1) * SPACING_M
			var z := (gz + fposmod(h1 * 7.31, 1.0)) * SPACING_M
			var d := Vector2(x, z).distance_to(centre)
			if d > RADIUS_M or absf(x) > half - 2.0 or absf(z) > half - 2.0:
				continue
			var edge := clampf((RADIUS_M - d) / (RADIUS_M * EDGE_SHARE), 0.0, 1.0)
			if fposmod(h1 * 13.7, 1.0) > edge:
				continue  # thinner toward the edge: no ring
			if _scatter and _scatter._ground_blocked(x, z):
				continue
			var h := _terrain.height_at(x, z)
			if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.4:
				continue
			if _terrain.normal_at(x, z).y < MIN_UP:
				continue
			if _terrain.cuts and _terrain.cuts.bare(x, z):
				continue
			var s := lerpf(SIZE.x, SIZE.y, fposmod(h1 * 3.97, 1.0))
			var basis := Basis(Vector3.UP, h1 * TAU).scaled(Vector3(s, s * lerpf(0.8, 1.4, fposmod(h1 * 5.3, 1.0)), s))
			var c: Color = _colours[int(fposmod(h1 * 17.0, 1.0) * _colours.size()) % _colours.size()]
			c = c.darkened(fposmod(h1 * 23.0, 1.0) * 0.18)
			list.append([Transform3D(basis, Vector3(x, h - 0.03, z)), c])
	multimesh.instance_count = list.size()
	for k in list.size():
		multimesh.set_instance_transform(k, list[k][0])
		multimesh.set_instance_color(k, list[k][1])
	return list.size()


static func _hash(x: int, z: int) -> float:
	return fposmod(sin(float(x) * 127.1 + float(z) * 311.7) * 43758.5453, 1.0)
