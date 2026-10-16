extends Node3D
## The VT-14 Petrel (vtol_petrel) next to the UH-60 it replaces, on a flat pad under daylight,
## photographed from a few angles (needs a real window; with --headless it only builds them).
##   <voxel godot exe> --path . res://tests/vtol_shots.tscn -- <output folder>
## Saves petrel_*.png (front 3/4, side, rear 3/4, top, cabin-level close-up) and compare_*.png
## (both airframes side by side). Keep the output as an S run (docs/debugging.md).

const SHOTS := [
	# [file, look-at offset from the Petrel, camera offset, fov]
	["petrel_front34", Vector3(0, 1.6, 0), Vector3(-11, 4.5, 13), 50.0],
	["petrel_side", Vector3(0, 1.6, 0), Vector3(-17, 2.2, 0), 45.0],
	["petrel_rear34", Vector3(0, 1.6, 0), Vector3(10, 5.0, -13), 50.0],
	["petrel_top", Vector3(0, 0, 0), Vector3(0.01, 24, 0), 45.0],
	["petrel_nose_close", Vector3(0, 1.8, 4), Vector3(-4, 2.4, 9), 55.0],
	["petrel_pod_close", Vector3(4, 2.4, 0), Vector3(9, 3.8, 5), 50.0],
]


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[vtol] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/vtol"
	DirAccess.make_dir_recursive_absolute(out)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.84)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.86)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.40, 0.30)
	plane.material = gm
	ground.mesh = plane
	add_child(ground)

	var petrel := VehicleArt.instance("vtol_petrel")
	add_child(petrel)
	var uh60 := VehicleArt.instance("uh60")
	uh60.position = Vector3(22, 0, 0)
	add_child(uh60)
	print("[vtol] petrel size_m=%s  uh60 size_m=%s" % [VehicleArt.size_m("vtol_petrel"), VehicleArt.size_m("uh60")])
	print("[vtol] petrel children: %s" % [petrel.get_children().map(func(n: Node) -> String: return n.name)])

	var camera := Camera3D.new()
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	if headless:
		print("[vtol] headless: built both airframes, no shots")
		get_tree().quit(0)
		return
	for s: Array in SHOTS:
		_aim(camera, s[1], s[2], s[3])
		await _settle()
		_save(out, s[0])
	# Side by side: Petrel (left) and UH-60 (right).
	_aim(camera, Vector3(11, 1.8, 0), Vector3(11, 9, 34), 50.0)
	await _settle()
	_save(out, "compare_side_by_side")
	_aim(camera, Vector3(11, 0, 0), Vector3(11.01, 40, 0), 50.0)
	await _settle()
	_save(out, "compare_top")
	print("[vtol] done: %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _aim(camera: Camera3D, target: Vector3, offset: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(out: String, file: String) -> void:
	var path := out.path_join(file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[vtol] saved %s" % path)
