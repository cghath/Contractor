extends Node
## Frame-rate benchmark (not a suite): a group playtest night's heaviest scene, measured.
##   tools/frame_bench.sh [label] [-- extra godot args, e.g. --gpu-index 1]
## or by hand (needs a real window, not --headless):
##   <voxel godot exe> --path . res://tests/frame_bench.tscn -- --out <folder> [--windowed WxH] [--vsync]
##
## The scene: Black Ridge hills (ridge_hot, a 16 km² hot zone) with its town streamed in and
## garrisoned (topped up to HOSTILES_UP hostiles inside it), four player bodies (the host's
## and three puppets standing in for remote players: what a host draws on a group night),
## the eight squad AI in a firefight with the garrison from the town's edge, the town's
## civilians walking their routines, and the bodies the fight leaves. After WARM_S seconds of
## fighting a camera flies a fixed path for PATH_S seconds: down the street at eye height
## ("street"), round the town at 30 m ("orbit"), out to 150 m ("far"). Every frame is
## measured: its time, the engine's process and physics time, the main viewport's measured
## CPU and GPU render time, the frame setup time, draw calls, primitives and objects drawn.
##
## Prints BENCH lines, and writes bench.txt (the summary), frames.csv (every frame) and three
## screenshots (street, orbit, far) into the --out folder. Video settings come from a settings
## file of its own (GameSettings.use_file, defaults) with: fullscreen exclusive at the screen's
## own size unless --windowed, vsync off and no frame cap unless --vsync (then the screen's
## rate). Never touches the player's settings or saves.

const WARM_S := 20.0
const PATH_S := 36.0
const SEGMENTS := [["street", 0.0, 12.0], ["orbit", 12.0, 24.0], ["far", 24.0, 36.0]]
const SHOTS := {"street": 6.0, "orbit": 18.0, "far": 33.0}
const HOSTILES_UP := 16
const FRIENDLIES_UP := 8
const PUPPETS := 3
const TOP_UP_S := 3.0
const ZONE := "ridge_hot"
const SETTINGS := "user://frame_bench_settings.cfg"
## Seconds per probe phase (_probe).
const PROBE_S := 3.0
## FrameCost's systems, per frame.
## Calls per body per function in _unit_costs.
const UNIT_CALLS := 20
const COST_SYSTEMS: Array[StringName] = [&"ai", &"nav", &"models", &"sfx", &"voxels"]

var level: ZoneLevel
var town: ZoneModule
var cam: Camera3D
var out_dir := ""
var _rng := RandomNumberGenerator.new()
var _spawned := 0
var _reinforced := 0
var _centre := Vector3.ZERO
var _street_dir := Vector3.FORWARD
var _frames: Array = []
var _puppets: Array[Soldier] = []
var _probe_lines: PackedStringArray = []
var _models_before: Array = []
var _unit_lines: PackedStringArray = []
## Per-frame timing of the game's own scripts (the engine's TIME_* monitors are a 1 s maximum,
## not this frame's): markers at the very front and back of the process and physics orders.
var _t := {"phys_script": 0, "phys_ticks": 0, "phys_start": 0, "proc_start": 0, "proc_end": 0, "phys_tick_start": 0}


class Marker extends Node:
	var bench: Node
	var first := true
	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		if first:
			bench._t.proc_start = now
		else:
			bench._t.proc_end = now
	func _physics_process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		if first:
			bench._t.phys_tick_start = now
			if bench._t.phys_ticks == 0:
				bench._t.phys_start = now
			bench._t.phys_ticks += 1
		else:
			bench._t.phys_script += now - int(bench._t.phys_tick_start)


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)  # no focus, no cursor capture
	for first: bool in [true, false]:
		var m := Marker.new()
		m.bench = self
		m.first = first
		m.process_priority = -1000000 if first else 1000000
		m.process_physics_priority = -1000000 if first else 1000000
		add_child(m)
	_rng.seed = 2026
	seed(2026)
	var args := OS.get_cmdline_user_args()
	out_dir = _arg(args, "--out", OS.get_user_data_dir().path_join("frame_bench"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(WARM_S + PATH_S + 240.0).timeout.connect(func() -> void:
		print("BENCH FAILED (timed out)")
		_end(99))
	# Video: a settings file of the bench's own, at its defaults, then the bench's mode.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameSettings.use_file(SETTINGS)
	var windowed := _arg(args, "--windowed", "")
	if windowed != "":
		GameSettings.set_value("video", "window_mode", "windowed")
		GameSettings.set_value("video", "resolution", windowed)
	else:
		GameSettings.set_value("video", "window_mode", "fullscreen")
	GameSettings.set_value("video", "vsync", "--vsync" in args)
	GameSettings.set_value("video", "fps_cap", 0)
	FrameCost.on = true
	GameState.zone_id = "test_frame_bench"
	Campaign.campaign_id = "test_frame_bench_campaign"
	Contracts.auto_show_debrief = false
	CompoundLevel.spawn_ai = true
	GameState.delete_save()
	Campaign.reset_campaign()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameSettings.apply_video()  # the menu applied them too; again, in case it ran first
	main.host_zone(MissionRegistry.zone_def(ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	for m in level.modules():
		if ZoneModules.base(m.type) == "town":
			town = m
	if town == null:
		print("BENCH FAILED (no town in %s)" % ZONE)
		_end(1)
		return
	_centre = level.ground_point(town.global_position)
	var rect := town.footprint()
	_street_dir = Vector3(0, 0, -1)
	var me := level.players.get_node(^"1") as Soldier
	me.global_position = _centre + Vector3(1.5, 0.3, 4.0)  # streams the town in and garrisons it
	print("BENCH town %s at %s, footprint %s" % [town.module_id, _centre, rect])
	var t0 := Time.get_ticks_msec()
	while not level.garrison_spawned(town.module_id) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	var people := PeopleLayer.find(level)
	if people and people.people().is_empty():
		people._spawn_civilians()
	# The town's voxels drawn as for a player standing in it (the host's own body stands back, out
	# of the fire; medics would drag it about): a viewer of the host's kind at the town's middle.
	var eyes := VoxelViewer.new()
	eyes.view_distance = VoxelWorld.VIEW_DISTANCE
	eyes.requires_visuals = true
	eyes.requires_collisions = false
	add_child(eyes)
	eyes.global_position = _centre + Vector3.UP * 1.7
	# The host's own body behind the squad, out of the fire (a downed host blacks the screen out).
	var behind := rect.size.y * 0.5 + 30.0
	me.global_position = level.ground_point(_centre + Vector3(4.0, 0, behind)) + Vector3.UP * 0.2
	me.set_physics_process(false)
	# The squad on the town's south edge, facing in.
	var i := 0
	for s: Soldier in _side(&"friendly"):
		s.global_position = level.ground_point(_centre + Vector3(lerpf(-10.0, 10.0, i / 7.0), 0, rect.size.y * 0.5 + 12.0)) + Vector3.UP * 0.2
		i += 1
	# Three more player bodies (what a host draws for the other players on a group night): soldiers
	# with no brain, standing in the squad's line.
	for k in PUPPETS:
		var p := level.spawn_soldier({"name": "BenchPlayer%d" % (k + 2), "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(_centre + Vector3(-6.0 + k * 6.0, 0, rect.size.y * 0.5 + 16.0)) + Vector3.UP * 0.2,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.6, "discipline": 0.6, "guard": true})
		var brain := SquadAI.of(p)
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		_puppets.append(p)
	_top_up()
	await get_tree().create_timer(1.0).timeout
	_tell_both_sides()
	# Warm up: the fight starts, bodies fall, every mesh and sound is built.
	var warm_end := Time.get_ticks_msec() + int(WARM_S * 1000.0)
	var next_top := 0
	while Time.get_ticks_msec() < warm_end:
		await get_tree().process_frame
		if Time.get_ticks_msec() >= next_top:
			next_top = Time.get_ticks_msec() + int(TOP_UP_S * 1000.0)
			_top_up()
			_tell_both_sides()
	# The camera path.
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.fov = GameSettings.fov()
	cam.cull_mask = 1
	add_child(cam)
	cam.make_current()
	_hide_hud()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_models_before = VoxelArt._meshes.keys()
	var shots_left := SHOTS.duplicate()
	var start := Time.get_ticks_usec()
	var last := start
	while true:
		var t := (Time.get_ticks_usec() - start) / 1000000.0
		if t >= PATH_S:
			break
		_place_camera(t)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var f := _sample(now - last)
		f["t"] = t
		f["seg"] = _segment(t)
		_frames.append(f)
		last = now
		if Time.get_ticks_msec() >= next_top and not "--no-topup" in args:
			next_top = Time.get_ticks_msec() + int(TOP_UP_S * 1000.0)
			_top_up()
			_tell_both_sides()
		for name: String in shots_left.keys():
			if t >= float(shots_left[name]):
				shots_left.erase(name)
				_hide_hud()
				var img := get_viewport().get_texture().get_image()
				img.save_png(out_dir.path_join("%s.png" % name))
				last = Time.get_ticks_usec()  # the save isn't the game's frame
	if "--lod-shots" in args:
		await _lod_shots()
	if not "--no-probe" in args:
		await _probe()
		_unit_costs()
	_report()
	_end(0)


## Screenshots of one soldier from either side of each level-of-detail distance
## (VoxelArt.LOD_M), zoomed so he fills the frame ("lod_<m>m_zoom.png": what a pop would look
## like through an optic), and at the normal field of view ("lod_<m>m.png").
func _lod_shots() -> void:
	# A soldier of his own, standing on open ground away from the fight, brainless.
	var spot := level.ground_point(_centre + Vector3(0, 0, town.footprint().size.y * 0.5 + 200.0))
	var who := level.spawn_soldier({"name": "BenchModel", "faction": "friendly", "variant": "multicam", "pos": spot + Vector3.UP * 0.2,
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.6, "discipline": 0.6, "guard": true})
	if who == null:
		return
	var brain := SquadAI.of(who)
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	for k in 30:
		await get_tree().process_frame
	var chest := who.global_position + Vector3.UP * 1.0
	var away := Vector3(-0.5, 0.0, -0.85).normalized()  # from in front of him, a little to his side
	for d: float in [6.0, 11.5, 12.5, 38.0, 39.5, 40.5, 145.0, 155.0, 300.0]:
		for zoom: bool in [true, false]:
			cam.fov = rad_to_deg(2.0 * atan(1.3 / d)) if zoom else GameSettings.fov()
			cam.global_position = chest + (who.global_basis * away) * d + Vector3.UP * (0.3 + d * 0.03)  # over the rises between
			cam.look_at(chest, Vector3.UP)
			for k in 4:
				await get_tree().process_frame
			_hide_hud()
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("lod_%04.1fm%s.png" % [d, "_zoom" if zoom else ""]))
	cam.fov = GameSettings.fov()


## Where the frame goes: from the orbit's 18 s spot, PROBE_S seconds with each part of the
## per-frame work switched off in turn (then back on), against the same seconds with all of it
## on. A part's cost is roughly what its row saves on "all on". (The fight goes on meanwhile,
## so it's rough; it names the big costs.)
func _probe() -> void:
	_place_camera(18.0)
	var of := func(cls: Variant) -> Array:
		return get_tree().root.find_children("*", "", true, false).filter(func(n: Node) -> bool: return is_instance_of(n, cls))
	var sun: DirectionalLight3D = get_tree().root.find_children("*", "DirectionalLight3D", true, false).front() if not get_tree().root.find_children("*", "DirectionalLight3D", true, false).is_empty() else null
	var frozen := {}
	var phases := [
		["all on", func(_on: bool) -> void: pass],
		["all on (vis ranges re-set)", func(on: bool) -> void:
			if not on:
				for g: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					var gi := g as GeometryInstance3D
					if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
						var b := gi.visibility_range_begin
						var e := gi.visibility_range_end
						gi.visibility_range_begin = b + 0.001
						gi.visibility_range_end = e + 0.001 if e > 0.0 else 0.0
						gi.visibility_range_begin = b
						gi.visibility_range_end = e],
		["AI brains off", func(on: bool) -> void:
			for n: Node in of.call(SquadAI) + of.call(CivilianAI):
				n.set_physics_process(on)],
		["body models off", func(on: bool) -> void:
			for n: Node in of.call(CharacterModel):
				n.set_process(on)],
		["gear rigs off", func(on: bool) -> void:
			for n: Node in of.call(GearRig):
				n.set_process(on)
				n.set_physics_process(on)],
		["wound marks off", func(on: bool) -> void:
			for n: Node in of.call(WoundMarks):
				n.set_process(on)],
		["soldier process off", func(on: bool) -> void:
			for n: Node in of.call(Soldier):
				n.set_process(on)],
		["soldier physics off", func(on: bool) -> void:
			for n: Node in of.call(Soldier):
				n.set_physics_process(on)],
		["ragdolls off", func(on: bool) -> void:
			for n: Node in of.call(Ragdoll):
				n.set_physics_process(on)
				for b: Node in n.find_children("*", "RigidBody3D", true, false):
					if not on:
						frozen[b] = (b as RigidBody3D).freeze
					(b as RigidBody3D).freeze = true if not on else bool(frozen.get(b, false))],
		["people hidden", func(on: bool) -> void:
			for n: Node in of.call(Soldier):
				(n as Node3D).visible = on],
		["voxel structures hidden", func(on: bool) -> void:
			for n: Node in get_tree().root.find_children("*", "VoxelTerrain", true, false):
				(n as Node3D).visible = on],
		["scatter hidden", func(on: bool) -> void:
			var scatter := level.get_node_or_null(^"Scatter") as Node3D
			if scatter:
				scatter.visible = on],
		["ground mesh hidden", func(on: bool) -> void:
			var ground := level.get_node_or_null(^"Terrain") as Node3D
			if ground:
				ground.visible = on],
		["smoke clouds hidden", func(on: bool) -> void:
			for n: Node in of.call(SmokeCloud):
				(n as Node3D).visible = on],
		["a smoke cloud added", func(on: bool) -> void:
			if not on:
				level.spawn_smoke(_centre + Vector3(0, 0.2, 0), "white", 5.0)
			else:
				for n: Node in of.call(SmokeCloud):
					if (n as SmokeCloud).age < 30.0 and (n as Node3D).global_position.distance_to(_centre + Vector3(0, 0.2, 0)) < 0.5:
						n.queue_free()],
		["sun shadows off", func(on: bool) -> void:
			if sun:
				sun.shadow_enabled = on],
	]
	for ph: Array in phases:
		var toggle: Callable = ph[1]
		toggle.call(false)
		for k in 10:
			await get_tree().process_frame
		var frames: Array = []
		var until := Time.get_ticks_msec() + int(PROBE_S * 1000.0)
		var last := Time.get_ticks_usec()
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append(_sample(now - last))
			last = now
		toggle.call(true)
		_probe_lines.append(_line(ph[0], _stats(frames)))
		for k in 10:
			await get_tree().process_frame


## One frame's numbers: its time; physics: the ticks it ran, their scripts, and all of them
## with the physics engine's steps; the process scripts; the render's CPU and GPU.
## What each per-frame and per-tick function costs one body, called UNIT_CALLS times on every
## body of each kind (standing, moving, down or dead; in microseconds a call, averaged): which
## of a body's own costs are worth cutting. Called directly, out of the engine's order, after
## the measured run (the fight's state is moved on a little; nothing measured after it).
func _unit_costs() -> void:
	var kinds := {"standing": [], "moving": [], "down/dead": []}
	for n in level.ai.get_children() + level.players.get_children() + (PeopleLayer.find(level).people() if PeopleLayer.find(level) else []):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion():
			continue
		if not s.vitals.is_up():
			kinds["down/dead"].append(s)
		elif Vector2(s.velocity.x, s.velocity.z).length() > 0.3:
			kinds["moving"].append(s)
		else:
			kinds["standing"].append(s)
	var d := 1.0 / 60.0
	_unit_lines.append("BENCH unit costs (us a call, %d calls on each body, avg; ticks are 60 a second):" % UNIT_CALLS)
	for kind: String in kinds:
		var bodies: Array = kinds[kind]
		if bodies.is_empty():
			continue
		var parts := {"Soldier._process": [], "Soldier._physics_process (tick)": [], "CharacterModel._process": [],
			"GearRig._process": [], "GearRig._physics_process (tick)": [], "SquadAI/CivilianAI tick": [], "Ragdoll tick": []}
		for s: Soldier in bodies:
			var calls := {"Soldier._process": [s, &"_process"], "Soldier._physics_process (tick)": [s, &"_physics_process"],
				"CharacterModel._process": [s.model, &"_process"]}
			for g: Node in s.find_children("*", "", true, false):
				if g is GearRig:
					calls["GearRig._process"] = [g, &"_process"]
					calls["GearRig._physics_process (tick)"] = [g, &"_physics_process"]
				elif g is SquadAI or g is CivilianAI:
					if g.is_physics_processing():
						calls["SquadAI/CivilianAI tick"] = [g, &"_physics_process"]
			if is_instance_valid(s.ragdoll):
				calls["Ragdoll tick"] = [s.ragdoll, &"_physics_process"]
			for key: String in calls:
				var node: Node = calls[key][0]
				if not is_instance_valid(node) or not node.has_method(calls[key][1]):
					continue
				if (key.ends_with("tick)") or key.ends_with("tick")) and not node.is_physics_processing():
					continue
				if not key.ends_with("tick)") and not key.ends_with("tick") and not node.is_processing():
					continue
				var t0 := Time.get_ticks_usec()
				for k in UNIT_CALLS:
					node.call(calls[key][1], d)
				(parts[key] as Array).append(float(Time.get_ticks_usec() - t0) / UNIT_CALLS)
		var text := PackedStringArray()
		for key: String in parts:
			var v: Array = parts[key]
			if v.is_empty():
				continue
			var sum := 0.0
			for x: float in v:
				sum += x
			text.append("%s %.0f (%d)" % [key, sum / v.size(), v.size()])
		_unit_lines.append("BENCH   %-9s %2d bodies: %s" % [kind, bodies.size(), ", ".join(text)])


func _sample(usec: int) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var ticks := int(_t.phys_ticks)
	# Called from process_frame, which comes after this frame's physics ticks and before its
	# process: so physics is this frame's (first tick to now), process the frame before's.
	var phys_all := (Time.get_ticks_usec() - int(_t.phys_start)) / 1000.0 if ticks > 0 else 0.0
	var out := {"ms": usec / 1000.0,
		"ticks": ticks, "phys_script_ms": int(_t.phys_script) / 1000.0, "phys_all_ms": phys_all,
		"process_ms": (int(_t.proc_end) - int(_t.proc_start)) / 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"shadow_draws": RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"main_draws": RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	_t.phys_ticks = 0
	_t.phys_script = 0
	# The game's own counted systems (FrameCost) since the session log last took them (in its
	# _process, the frame before; this frame's physics ticks since): when it runs. Else the bench takes them.
	var costs: Dictionary = FrameCost._costs.duplicate() if SessionLog.session_id != "" else FrameCost.take()
	for sys: StringName in COST_SYSTEMS:
		out[String(sys) + "_ms"] = int(costs.get(sys, 0)) / 1000.0
	out["costs"] = costs.duplicate()
	return out


## Where the camera is `t` seconds into the path.
func _place_camera(t: float) -> void:
	var rect := town.footprint()
	var half := rect.size.y * 0.5
	if t < 12.0:  # down the street at eye height, from the edge to the middle and on
		var k := t / 12.0
		var at := _centre + Vector3(0.0, 0, lerpf(half + 6.0, -half * 0.5, k))
		var eye := level.ground_point(at) + Vector3.UP * 1.7
		cam.global_position = eye
		cam.look_at(eye + Vector3(0.15 * sin(t * 0.9), -0.05, -1.0), Vector3.UP)
	elif t < 24.0:  # round the town at 30 m, 8 m up
		var a := (t - 12.0) / 12.0 * TAU
		cam.global_position = _centre + Vector3(sin(a) * 30.0, 8.0, cos(a) * 30.0)
		cam.look_at(_centre + Vector3.UP * 1.5, Vector3.UP)
	else:  # out to 150 m, 25 m up
		var k := clampf((t - 24.0) / 8.0, 0.0, 1.0)
		var d := lerpf(40.0, 150.0, k)
		cam.global_position = _centre + Vector3(d * 0.6, lerpf(10.0, 25.0, k), d * 0.8)
		cam.look_at(_centre + Vector3.UP * 1.5, Vector3.UP)


## Visible geometry by what it belongs to (a soldier, an item on the ground, a smoke cloud...,
## else the level's child it's under): where the draw calls come from.
func _owners() -> String:
	var count := {}
	for g: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not (g as GeometryInstance3D).is_visible_in_tree():
			continue
		var kind := "other"
		var n: Node = g.get_parent()
		while n:
			if n is Soldier:
				kind = "soldiers"
				break
			if n is WorldItem or n is SmokeCloud or n is Ragdoll:
				kind = n.get_script().get_global_name()
				break
			if n.get_parent() == level:
				kind = "level/" + String(n.name).rstrip("0123456789")
				break
			n = n.get_parent()
		count[kind] = int(count.get(kind, 0)) + 1
	var keys := count.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(count[a]) > int(count[b]))
	return ", ".join(PackedStringArray(keys.map(func(k: String) -> String: return "%s %d" % [k, count[k]])))


## The HUD and menus off: the bench measures the 3D scene, and its screenshots show it.
func _hide_hud() -> void:
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false


func _segment(t: float) -> String:
	for s: Array in SEGMENTS:
		if t >= float(s[1]) and t < float(s[2]):
			return s[0]
	return "far"


func _stats(frames: Array) -> Dictionary:
	var ms: Array = frames.map(func(f: Dictionary) -> float: return f.ms)
	ms.sort()
	var n := ms.size()
	var total := 0.0
	for v: float in ms:
		total += v
	var worst_n := maxi(1, n / 100)
	var worst_total := 0.0
	for k in worst_n:
		worst_total += ms[n - 1 - k]
	var avg := func(key: String) -> float:
		var s := 0.0
		for f: Dictionary in frames:
			s += float(f[key])
		return s / maxf(n, 1)
	return {"n": n, "avg_ms": total / maxf(n, 1), "fps": 1000.0 * n / maxf(total, 0.001),
		"low1_fps": 1000.0 / maxf(worst_total / worst_n, 0.001), "worst_ms": ms[n - 1] if n > 0 else 0.0,
		"process_ms": avg.call("process_ms"), "ticks": avg.call("ticks"), "phys_script_ms": avg.call("phys_script_ms"), "phys_all_ms": avg.call("phys_all_ms"),
		"ai_ms": avg.call("ai_ms"), "nav_ms": avg.call("nav_ms"), "models_ms": avg.call("models_ms"), "models_worst": frames.reduce(func(a: float, f: Dictionary) -> float: return maxf(a, f.models_ms), 0.0), "render_cpu_ms": avg.call("render_cpu_ms"),
		"gpu_ms": avg.call("gpu_ms"), "draws": avg.call("draws"), "prims": avg.call("prims"), "objects": avg.call("objects"), "shadow_draws": avg.call("shadow_draws"), "main_draws": avg.call("main_draws")}


func _line(name: String, s: Dictionary) -> String:
	return "%-20s %5d frames  avg %6.2f ms (%5.0f fps)  1%% low %5.0f fps  worst %6.1f ms | physics %4.1f ticks: scripts %6.2f, all %6.2f ms (%5.2f a tick) | ai %5.2f nav %4.2f models %4.2f (worst %5.1f) | process %5.2f  render-cpu %5.2f  gpu %5.2f ms | draws %6.0f (main %5.0f, shadows %5.0f)  prims %9.0f  objects %6.0f" % [
		name, s.n, s.avg_ms, s.fps, s.low1_fps, s.worst_ms, s.ticks, s.phys_script_ms, s.phys_all_ms, s.phys_all_ms / maxf(s.ticks, 0.01), s.ai_ms, s.nav_ms, s.models_ms, s.models_worst, s.process_ms, s.render_cpu_ms, s.gpu_ms, s.draws, s.main_draws, s.shadow_draws, s.prims, s.objects]


func _report() -> void:
	var lines := PackedStringArray()
	var adapter := "%s / %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()]
	var size := get_viewport().get_visible_rect().size
	var root := get_tree().root
	lines.append("BENCH commit %s, %s, %s, window %dx%d (%s, 3D scale %.2f), vsync %s, max_fps %d" % [
		OS.get_environment("BENCH_SHA"), Time.get_datetime_string_from_system(), adapter, int(size.x), int(size.y),
		["windowed", "minimized", "maximized", "fullscreen", "exclusive fullscreen"][DisplayServer.window_get_mode()],
		root.scaling_3d_scale, DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, Engine.max_fps])
	var alive := 0
	var dead := 0
	var civs := 0
	for n in level.ai.get_children() + level.players.get_children():
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion():
			continue
		if s.is_in_group(Soldier.DEAD_GROUP) or s.vitals.is_dead():
			dead += 1
		else:
			alive += 1
	var people := PeopleLayer.find(level)
	if people:
		for s: Soldier in people.people():
			if s.vitals.is_dead():
				dead += 1
			else:
				civs += 1
	var meshes := get_tree().root.find_children("*", "MeshInstance3D", true, false).size()
	lines.append("BENCH scene: %d soldiers up (incl. %d player bodies), %d civilians, %d bodies, %d hostiles spawned in all, %d friendly reinforcements; %d MeshInstance3D, %d nodes, %d objects" % [
		alive, level.players.get_child_count() + _puppets.size(), civs, dead, _spawned, _reinforced, meshes,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])
	var streamed := level.modules().filter(func(m: ZoneModule) -> bool: return m.is_streamed())
	lines.append("BENCH modules streamed in: %d of %d (%s); VoxelTerrain nodes %d" % [streamed.size(), level.modules().size(),
		", ".join(PackedStringArray(streamed.map(func(m: ZoneModule) -> String: return "%s %.0f m" % [m.module_id, m.distance_to(_centre)]))),
		get_tree().root.find_children("*", "VoxelTerrain", true, false).size()])
	lines.append("BENCH drawn things by owner (visible GeometryInstance3D): %s" % _owners())
	lines.append("BENCH " + _line("all", _stats(_frames)))
	for seg: Array in SEGMENTS:
		lines.append("BENCH " + _line(seg[0], _stats(_frames.filter(func(f: Dictionary) -> bool: return f.seg == seg[0]))))
	# The slowest frames and what the game's counted systems (FrameCost) spent in them.
	var slow := _frames.duplicate()
	slow.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	for f: Dictionary in slow.slice(0, 8):
		var costs: Dictionary = f.costs
		var keys := costs.keys()
		keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(costs[a]) > int(costs[b]))
		lines.append("BENCH slow frame at %.1f s: %.1f ms, %d ticks (scripts %.1f ms, all %.1f), process %.1f; counted: %s" % [f.t, f.ms, f.ticks,
			f.phys_script_ms, f.phys_all_ms, f.process_ms, ", ".join(PackedStringArray(keys.slice(0, 5).map(func(k: StringName) -> String: return "%s %.1f" % [k, int(costs[k]) / 1000.0])))])
	var built: Array = VoxelArt._meshes.keys().filter(func(k: String) -> bool: return not k in _models_before)
	lines.append("BENCH voxel models first built after the warm-up: %d %s" % [built.size(), ", ".join(PackedStringArray(built.slice(0, 40)))])
	if not _probe_lines.is_empty():
		lines.append("BENCH probe (orbit spot, %.0f s each, one part off at a time):" % PROBE_S)
		for l in _probe_lines:
			lines.append("BENCH   " + l)
	lines.append_array(_unit_lines)
	for line in lines:
		print(line)
	var out := FileAccess.open(out_dir.path_join("bench.txt"), FileAccess.WRITE)
	if out:
		out.store_string("\n".join(lines) + "\n")
		out.close()
	var csv := FileAccess.open(out_dir.path_join("frames.csv"), FileAccess.WRITE)
	if csv:
		csv.store_line("t,seg,ms,ticks,phys_script_ms,phys_all_ms,process_ms,render_cpu_ms,gpu_ms,draws,prims,objects,ai_ms,nav_ms,models_ms,sfx_ms,voxels_ms")
		for f: Dictionary in _frames:
			csv.store_line("%.3f,%s,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f" % [f.t, f.seg, f.ms, f.ticks, f.phys_script_ms, f.phys_all_ms, f.process_ms, f.render_cpu_ms, f.gpu_ms, f.draws, f.prims, f.objects, f.ai_ms, f.nav_ms, f.models_ms, f.sfx_ms, f.voxels_ms])
		csv.close()
	print("BENCH DONE")


func _side(faction: StringName) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and s.faction == faction and s.vitals.is_up() and not s.is_queued_for_deletion() and not s.name.begins_with("Civ_") \
				and not s.name.begins_with("Person_"):
			out.append(s)
	return out


func _top_up() -> void:
	var posts: Array = ZoneModules.GARRISON.get(town.type, [])
	var up := _side(&"hostile").size()
	while up < HOSTILES_UP and not posts.is_empty():
		_spawned += 1
		var post: Vector3 = town.to_global(posts[_rng.randi() % posts.size()])
		var pos := level.ground_point(post + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))) + Vector3.UP * 0.2
		level.spawn_soldier({"name": "BenchHostile%d" % _spawned, "faction": "hostile", "variant": "urban", "pos": pos,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": true, "mode": "aware"})
		up += 1
	up = _side(&"friendly").size()
	var half := town.footprint().size.y * 0.5
	while up < FRIENDLIES_UP:
		_reinforced += 1
		var pos := level.ground_point(_centre + Vector3(_rng.randf_range(-12.0, 12.0), 0, half + _rng.randf_range(14.0, 20.0))) + Vector3.UP * 0.2
		level.spawn_soldier({"name": "BenchFriend%d" % _reinforced, "faction": "friendly", "variant": "multicam", "pos": pos,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.6, "discipline": 0.6, "guard": false})
		up += 1


func _tell_both_sides() -> void:
	var friends := level.squad_for(&"friendly")
	var foes := level.squad_for(&"hostile")
	for h: Soldier in _side(&"hostile"):
		if friends:
			friends.note_enemy(h, h.global_position)
	for f: Soldier in _side(&"friendly"):
		if foes:
			foes.note_enemy(f, f.global_position)


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _end(code: int) -> void:
	GameSettings.use_file("")
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().quit(code)
