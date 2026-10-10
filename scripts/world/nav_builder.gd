class_name NavBuilder
extends RefCounted
## Host-side navigation mesh for the compound, baked at runtime from the flat ground and
## the voxel structures' boxes. A bullet hole doesn't change paths. Rebaking when a wall
## is breached is left for later; until then AI treats walls as intact.

const AREA := AABB(Vector3(-45, -1, -45), Vector3(90, 8, 90))
const GROUND_HALF := 80.0


static func build(level: CompoundLevel) -> NavigationRegion3D:
	var nav := NavigationMesh.new()
	# Multiples of the default 0.25 m cell size and height, so nothing gets rounded.
	nav.agent_radius = 0.25  # the building doorway is 1.2 m wide
	nav.agent_height = 1.75
	nav.agent_max_climb = 0.25
	nav.filter_baking_aabb = AREA
	var source := NavigationMeshSourceGeometryData3D.new()
	var g := GROUND_HALF
	source.add_faces(PackedVector3Array([
		Vector3(-g, 0, -g), Vector3(g, 0, -g), Vector3(g, 0, g),
		Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(-g, 0, g),
	]), Transform3D.IDENTITY)
	var xform := level.voxel_world.global_transform
	for box in level.voxel_world.structure_boxes_m():
		source.add_faces(_box_faces(box), xform)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nav
	level.add_child(region)
	return region


static func _box_faces(box: AABB) -> PackedVector3Array:
	var a := box.position
	var b := box.end
	var c := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),  # bottom
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),  # top
	]
	var quads := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
	var faces := PackedVector3Array()
	for q: Array in quads:
		faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return faces
