class_name ZoneRoads
extends Node3D
## The hot zone's roads (the def's "roads": [[x, z], [x, z]] segments from the HQ to the
## outposts) drawn on the ground: a strip of packed earth that follows the terrain, left off
## the module pads. Looks only: no collision, vehicles drive on the terrain under it. Out past
## SEE_M the terrain's own colours carry them (ZoneTerrain.road_weight).

## Road width (m), samples along it (m), and how far above the ground it sits (m).
const WIDTH_M := 5.0
const STEP_M := 2.0
const LIFT_M := 0.08
## Drawn out to this distance; the terrain's coarser levels take over past LOD0_BUILD_M.
const SEE_M := 600.0
## Wheel ruts: the strip's middle is this much darker than its edges.
const RUT_DARKEN := 0.12

var segments := 0
## Every vertex laid (for checks: a headless renderer keeps no mesh arrays).
var vertices := PackedVector3Array()


## Builds a mesh per road from `def` on `terrain` (generated). Display only.
func build(terrain: ZoneTerrain, def: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # seen from above whichever way a quad winds
	var colour := terrain.c_road
	for road: Array in def.get("roads", []):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		var mesh := _strip(terrain, a, b, colour)
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = SEE_M
		node.visibility_range_end_margin = 40.0
		add_child(node)
		segments += 1


## One road from `a` to `b`: three points across (edge, middle, edge) every STEP_M, broken
## where it crosses a pad. Null if all of it is on pads.
func _strip(terrain: ZoneTerrain, a: Vector2, b: Vector2, colour: Color) -> ArrayMesh:
	var length := a.distance_to(b)
	if length < STEP_M:
		return null
	var along := (b - a) / length
	var side := Vector2(-along.y, along.x) * WIDTH_M * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ceili(length / STEP_M)
	var prev: Array = []  # the last row's three vertices, [] after a gap
	var tris := 0
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		if _on_pad(terrain, p):
			prev = []
			continue
		var row: Array = []
		for s: float in [-1.0, 0.0, 1.0]:
			var q := p + side * s
			row.append(Vector3(q.x, terrain.height_at(q.x, q.y) + LIFT_M, q.y))
		if not prev.is_empty():
			for c in 2:
				_quad(st, terrain, prev[c], prev[c + 1], row[c], row[c + 1], colour, c)
				tris += 2
		prev = row
	if tris == 0:
		return null
	return st.commit()


func _quad(st: SurfaceTool, terrain: ZoneTerrain, p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3, colour: Color, column: int) -> void:
	# column 0 runs edge -> middle, column 1 middle -> edge: the middle vertex is the darker one.
	var rut := colour.darkened(RUT_DARKEN)
	var c0 := colour if column == 0 else rut
	var c1 := rut if column == 0 else colour
	for v: Array in [[p0, c0], [q0, c0], [p1, c1], [p1, c1], [q0, c0], [q1, c1]]:
		var at: Vector3 = v[0]
		st.set_color(v[1])
		st.set_normal(terrain.normal_at(at.x, at.z))
		st.add_vertex(at)
		vertices.append(at)


static func _on_pad(terrain: ZoneTerrain, p: Vector2) -> bool:
	for pad: Array in terrain.pads:
		if (pad[0] as Rect2).has_point(p):
			return true
	return false
