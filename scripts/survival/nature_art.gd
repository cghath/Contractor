class_name NatureArt
extends RefCounted
## Blocky voxel bodies for the wildlife and the fire (PropArt's look: a few boxes each, vertex
## colours, one shared material), built once per species and kept. Nature draws them as MultiMeshes.

static var _meshes := {}
static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


## The body of species `sp` (Nature's fauna data's size and colour; "crow" a small black bird).
static func animal_mesh(sp: String) -> ArrayMesh:
	if _meshes.has(sp):
		return _meshes[sp]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var data: Dictionary = (Nature.fauna().get("species", {}) as Dictionary).get(sp, {})
	var size := Vector3(0.3, 0.15, 0.4)
	var colour := Color("1c1c1e")
	if not data.is_empty():
		var s: Array = data.get("size", [0.8, 0.5, 0.3])
		size = Vector3(float(s[0]), float(s[1]), float(s[2]))
		colour = Color(String(data.get("colour", "777777")))
	if sp == "crow":
		_box(st, Vector3(-0.1, -0.04, -0.06), Vector3(0.1, 0.04, 0.06), colour)
		_box(st, Vector3(-0.04, -0.01, -0.3), Vector3(0.04, 0.01, 0.3), colour.lightened(0.05))
	elif sp == "bird":
		_box(st, Vector3(-0.08, 0.02, -0.05), Vector3(0.08, 0.1, 0.05), colour)
	else:
		# Body (x along its length), legs, head forward and up.
		var l := size.x
		var h := size.y
		var w := size.z
		var leg := h * 0.45
		_box(st, Vector3(-l * 0.4, leg, -w * 0.5), Vector3(l * 0.4, h * 0.85, w * 0.5), colour)
		for lx: float in [-l * 0.3, l * 0.3]:
			for lz: float in [-w * 0.3, w * 0.3]:
				_box(st, Vector3(lx - 0.03, 0.0, lz - 0.03), Vector3(lx + 0.03, leg, lz + 0.03), colour.darkened(0.25))
		_box(st, Vector3(l * 0.38, h * 0.7, -w * 0.3), Vector3(l * 0.6, h, w * 0.3), colour.darkened(0.1))
		if sp == "deer":
			_box(st, Vector3(l * 0.45, h, -0.02), Vector3(l * 0.5, h * 1.3, 0.02), Color("d8c9a8"))
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[sp] = mesh
	return mesh


## A flame block (unit size: Nature scales it to a burning cell).
static func flame_mesh() -> ArrayMesh:
	if _meshes.has("_flame"):
		return _meshes["_flame"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.4, 0.5), Color("e2611d"))
	_box(st, Vector3(-0.3, 0.4, -0.3), Vector3(0.3, 0.8, 0.3), Color("f0a020"))
	_box(st, Vector3(-0.12, 0.8, -0.12), Vector3(0.12, 1.0, 0.12), Color("f7d24a"))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_meshes["_flame"] = mesh
	return mesh


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z)]
	for q: Array in PropArt.QUADS:
		var a: Vector3 = p[int(q[0])]
		var b: Vector3 = p[int(q[1])]
		var cc: Vector3 = p[int(q[2])]
		var d: Vector3 = p[int(q[3])]
		var n := (b - a).cross(cc - a).normalized()
		st.set_color(c)
		for v: Vector3 in [a, b, cc, a, cc, d]:
			st.set_normal(n)
			st.set_color(c)
			st.add_vertex(v)
