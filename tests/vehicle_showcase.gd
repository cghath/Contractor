extends Node3D
## Lines up every vehicle model and saves screenshots. Needs a window (not --headless):
##   <voxel godot exe> --path . res://tests/vehicle_showcase.tscn -- <output folder>

const LINEUP := [
	["uh60", "army", Vector3(-24, 0, 0)],
	["ah1z", "marine_gray", Vector3(-8, 0, 0)],
	["aav7", "od", Vector3(4, 0, -2)],
	["maxxpro", "desert", Vector3(12, 0, -2)],
	["matv", "od", Vector3(19, 0, -2)],
	["technical", "white", Vector3(26, 0, -2)],
]
const SHOTS := [
	["lineup", Vector3(2, 9, 30), Vector3(1, 1, -2)],
	["helicopters", Vector3(-28, 5, 14), Vector3(-16, 2, 0)],
	["ground", Vector3(24, 4, 12), Vector3(16, 1.5, -2)],
]


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6d6a55")
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var started := Time.get_ticks_msec()
	for v: Array in LINEUP:
		var node := VehicleArt.instance(v[0], v[1])
		node.position = v[2]
		node.rotation_degrees.y = -35.0
		add_child(node)
		VehicleArt.spin_rotors(node, 0.05)
	print("built %d vehicles in %d ms" % [LINEUP.size(), Time.get_ticks_msec() - started])
	var camera := Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.current = true
	for shot: Array in SHOTS:
		camera.look_at_from_position(shot[1], shot[2])
		for i in 20:
			await get_tree().process_frame
		var path: String = out.path_join("vehicles_%s.png" % shot[0])
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()
