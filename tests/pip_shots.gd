extends Node
## Screenshots of the picture-in-picture scopes (GunSight PiP, art task "PiP scopes"), to judge
## the look: the host's player aimed through a 4x prism and a 3.5-10x scope (at 6x and 10x) at
## soldiers about 150 m off, by day, at dusk and at night through his NVG (the scope's picture
## seen through the goggles: NvgView.scope_material), plus the same by day with PiP off (the
## whole view zoomed behind the ring, as before PiP) and one mid-kick (the lens carried off the
## middle by the gun's own kick: GunSight._lens_shift). Checks as it goes that the picture
## renders at the optic's power and isn't black. Needs a real window, not --headless:
##   <voxel godot exe> --path . --resolution 1600x900 res://tests/pip_shots.tscn -- <output folder>
## Keep the run's log as an S run (docs/debugging.md); the pictures don't go in the repo.

## Where the targets stand and where the player's eye is (m): about 150 m apart, the line of
## sight past the compound (as tests/iff_shots.gd).
const AT := Vector3(-70, 0.1, 65)
const EYE := Vector3(75, 0.0, 30)

var out := "user://pip_shots"
var level: CompoundLevel
var player: Soldier
var sight: GunSight
var failed := false
var _shots := 0


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("[pip] TEST FAILED: deadline passed, quitting")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	var settings := OS.get_user_data_dir().path_join("pip_shots_settings.cfg")
	DirAccess.remove_absolute(settings)
	GameSettings.use_file(settings)  # the defaults, never the player's own
	GameState.zone_id = "pip_shots"
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.player_input.set_physics_process(false)  # the shots hold the aim themselves (no mouse)
	sight = GunSight.of(player)
	for c: Node in player.player_input.hud.get_children():
		if c is CanvasItem and c != sight:
			(c as CanvasItem).visible = false  # only the sight: the shots are of the scope
	_targets()
	var aim_at := level.ground_point(AT) + Vector3(0, 1.2, 0)
	player.global_position = level.ground_point(EYE) + Vector3(0, 0.05, 0)
	player.look_at(Vector3(aim_at.x, player.global_position.y, aim_at.z))
	await _frames(2)
	var eye := player.camera.global_position
	player.set_pitch(atan2(aim_at.y - eye.y, Vector2(aim_at.x - eye.x, aim_at.z - eye.z).length()))
	print("[pip] range %.0f m, window %s" % [eye.distance_to(aim_at), get_window().size])
	var inv := player.inventory
	for light: Array in [["day", 12.0], ["dusk", 18.5]]:
		DayNight.current().server_set(float(light[1]), "clear")
		await _seconds(1.2)
		print("[pip] %s: darkness %.2f" % [light[0], DayNight.darkness_at(AT)])
		await _optics(String(light[0]))
	GameSettings.set_value("video", "scope_pip", "off")
	DayNight.current().server_set(12.0, "clear")
	await _seconds(1.2)
	await _shot_optic("day_pip_off_prism_4x", &"optic_prism_4x", 0, false)
	GameSettings.set_value("video", "scope_pip", "medium")
	await _shot_optic("day_kick_prism_4x", &"optic_prism_4x", 0, true, 0.05)
	# Night through the NVG: a helmet, a Gen 2 NVG mounted and lowered.
	if inv.slots[&"helmet"] == &"":
		inv.take(&"helmet")
	inv.take(&"nvg_gen2")
	player.server_toggle_nvg()
	DayNight.current().server_set(23.0, "clear")
	await _seconds(1.2)
	print("[pip] night: darkness %.2f, NVG on %s" % [DayNight.darkness_at(AT), Nvg.is_on(player)])
	await _optics("night_nvg")
	GameSettings.set_value("video", "scope_pip", "off")
	await _shot_optic("night_nvg_pip_off_prism_4x", &"optic_prism_4x", 0, false)
	GameSettings.use_file("")
	DirAccess.remove_absolute(settings)
	print("[pip] TEST FAILED" if failed else "[pip] PIP SHOTS PASSED")
	print("[pip] done (%d shots in %s)" % [_shots, out])
	get_tree().quit(1 if failed else 0)


## The prism, then the 3.5-10x at 6x (where it starts) and at 10x.
func _optics(light: String) -> void:
	await _shot_optic("%s_prism_4x" % light, &"optic_prism_4x", 0)
	await _shot_optic("%s_scope_6x" % light, &"optic_dmr_3_5_10", 0)
	await _shot_optic("%s_scope_10x" % light, &"optic_dmr_3_5_10", 3)


## Three soldiers side by side at AT, facing the eye.
func _targets() -> void:
	var across := Vector3(EYE.x - AT.x, 0, EYE.z - AT.z).normalized().cross(Vector3.UP)
	var kits := [["Militia", "hostile", "urban", CompoundLevel.hostile_loadout(0)],
		["Vantage", "hostile", "black", CompoundLevel.rival_pmc_loadout(1)],
		["Company", "friendly", "tan", ["plate_carrier", "plate_ceramic_l4", "helmet", "assault_pack", "m4a1"]]]
	for i in kits.size():
		var k: Array = kits[i]
		var s := level.spawn_soldier({"name": k[0], "faction": k[1], "variant": k[2], "pos": level.ground_point(AT + across * 1.6 * (i - 1.0)),
			"loadout": k[3], "combat": 0.5, "discipline": 0.5, "guard": true, "mode": "safe"})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		s.look_at(Vector3(EYE.x, s.global_position.y, EYE.z))


## Aims through `optic` on the M4 (zoomed `steps` from its start), the view model up at the eye
## as PlayerInput would hold it, and saves a shot; `kick`: the gun's own kick (radians up).
func _shot_optic(label: String, optic: StringName, steps: int, pip := true, kick := 0.0) -> void:
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	if inv.slots[&"primary"] != &"m4a1":
		if inv.slots[&"primary"] != &"":
			inv.unequip(&"primary")
		inv.put_on(&"primary", &"m4a1", {"rounds": 30})
	player.active_slot = &"primary"
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), optic))
	sight._zoom.erase(optic)
	GunSight.zoom_step(player, steps)
	player.is_aiming = true
	var weapon := player.active_weapon()
	GunSight.ease_glass(player, GunSight.aimed_fov_of(player, weapon, GameSettings.view_fov()), 1.0)
	var on := GunSight.pip_on(player)
	player.camera.fov = GameSettings.view_fov() if on else sight._glass_fov
	player.camera.rotation = Vector3.ZERO
	player.view_model.position = PlayerInput.ads_view(weapon, inv.state_of(&"primary"))
	player.view_model.rotation = Vector3(kick, 0, 0)
	player.view_model.visible = on or not GunSight.scoped(player)
	await _frames(4)
	await RenderingServer.frame_post_draw
	_shots += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out, _shots, label]
	img.save_png(path)
	var power := GunSight.glass_power(player)
	var want := GunSight.power(player, GunSight.optic_of(player))
	var ok := GunSight.scoped(player) and on == pip and absf(power - want) < 0.05
	var cam := sight.pip_camera()
	if pip and ok:
		var lens := 2.0 * float(GunSight.optic_of(player).stats.get("ring", GunSight.RING))
		var shown := lens * tan(deg_to_rad(GameSettings.view_fov() * 0.5)) / tan(deg_to_rad(cam.fov * 0.5))
		ok = sight.pip_rendering() and absf(shown - want) < 0.05 and not _black_lens(img, sight._lens_shift)
	print("[pip] %s %s: %.2fx (optic at %.2fx), PiP %s, lens shift %s -> %s" % ["[ok]" if ok else "[FAIL]", label, power, want,
		"on %s" % (sight._scope_vp.size if sight._scope_vp else Vector2i.ZERO) if on else "off", sight._lens_shift, path])
	failed = failed or not ok
	if label.begins_with("day_") and kick == 0.0:
		await _measure(label)
	player.is_aiming = false


## The render cost while aimed (GPU and CPU ms, draw calls) of the main view and, with PiP on,
## the scope's picture: averaged over 60 frames.
func _measure(label: String) -> void:
	var vps: Array[Viewport] = [get_viewport()]
	if sight.pip_rendering():
		vps.append(sight._scope_vp)
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	await _frames(10)
	var sums := []
	for vp in vps:
		sums.append([0.0, 0.0, 0])
	for f in 60:
		await RenderingServer.frame_post_draw
		for i in vps.size():
			var rid := vps[i].get_viewport_rid()
			sums[i][0] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			sums[i][1] += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			sums[i][2] += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	for i in vps.size():
		print("[pip] cost %s, %s: GPU %.2f ms, CPU %.2f ms, %d draw calls a frame" % [label, "main view" if i == 0 else "scope picture %s" % vps[i].size,
			sums[i][0] / 60.0, sums[i][1] / 60.0, int(sums[i][2] / 60)])
		RenderingServer.viewport_set_measure_render_time(vps[i].get_viewport_rid(), false)


## True if the lens (the scope picture) is black at four points off the reticle's lines.
func _black_lens(img: Image, shift: Vector2) -> bool:
	var scale := Vector2(img.get_size()) / sight.get_viewport_rect().size
	var centre := (sight.get_viewport_rect().size * 0.5 + shift) * scale
	var reach := img.get_height() * 0.12
	for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var at := centre + dir * reach
		var px := img.get_pixel(int(at.x), int(at.y))
		if px.r > 0.02 or px.g > 0.02 or px.b > 0.02:
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
