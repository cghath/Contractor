extends Node3D
## The primaries' ground models (ItemArt.ground_node: the same VoxelArt model as in the hands,
## lying on its side) on a bare floor, away from any zone's props, so a model's shape is easy to
## judge (Captain, 2026-10-16: the M249 "is just missing a lot of its model"). Needs a real window
## for the shots; it never takes focus (shot_window):
##   <voxel godot exe> --path . res://tests/weapon_shots.tscn -- <output folder>
## Saves sheet_top.png (all of them from above, labelled) and <id>_top.png / <id>_angle.png
## close-ups. weapons_test checks each model is one piece; this is for the eye.
const GUNS := ["m249", "m240b", "l85a2", "pkm", "c8", "hk416", "mosin9130", "springfield_hs", "m4a1", "scar_h"]

func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/weapons"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.38)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var nodes := []
	for i in GUNS.size():
		var item := ItemDB.get_item(StringName(GUNS[i]))
		var holder := ItemArt.ground_node(item)
		var size := ItemArt.ground_size(item)
		holder.position = Vector3(-0.85 + (i / 5) * 1.75, size.y * 0.5, -0.72 + (i % 5) * 0.36)
		holder.rotation.y = -PI * 0.5
		add_child(holder)
		nodes.append(holder)
		var label := Label3D.new()
		label.text = GUNS[i]
		label.font_size = 40
		label.pixel_size = 0.0015
		label.modulate = Color.BLACK
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.position = holder.position + Vector3(-0.6, 0.01, -0.14)
		add_child(label)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.95
	cam.position = Vector3(0.0, 3.0, 0.001)
	cam.look_at(Vector3.ZERO)
	await _settle()
	get_viewport().get_texture().get_image().save_png("%s/sheet_top.png" % out)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	for i in GUNS.size():
		var p: Vector3 = nodes[i].position
		cam.position = p + Vector3(0, 0.95, 0.001)
		cam.look_at(p)
		await _settle()
		get_viewport().get_texture().get_image().save_png("%s/%s_top.png" % [out, GUNS[i]])
		cam.position = p + Vector3(0.25, 0.4, 0.75)
		cam.look_at(p)
		await _settle()
		get_viewport().get_texture().get_image().save_png("%s/%s_angle.png" % [out, GUNS[i]])
	get_tree().quit()

func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
