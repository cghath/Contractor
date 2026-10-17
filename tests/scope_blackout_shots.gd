extends Node
## One-off visual check (Captain, playtest v0.4.26: scopes "sometimes go black" - NOT the
## by-design black ring mask, the inner magnified picture itself): aims a tube-scoped rifle and a
## holo with its magnifier, then forces the scope's SubViewport through every resize the real game
## does (magnifier flip, optic swap, window resize), screenshotting every single frame right after
## each one and checking the ring's own centre pixel isn't black (gun_sight.gd's _scope_stale
## guard). Needs a real window for the screenshots (shot_window.gd keeps it out of the way); with
## --headless it only runs the checks (no texture to sample, always passes - noted in the output).
##   <voxel godot exe> --path . res://tests/scope_blackout_shots.tscn -- <output folder>

var level: ZoneLevel
var player: Soldier
var sight: GunSight
var headless := false
var failed := false
var _frame := 0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	if not headless:
		preload("res://tests/shot_window.gd").stay_out_of_the_way(self)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[scope] TEST FAILED: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else "res://screenshots/scope"
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "test_scope_shots"  # never touch a real save
	Campaign.campaign_id = "test_scope_shots"
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var def := ZoneDef.generate(42, 512.0)
	def["terrain"] = "temperate"
	def["name"] = "Scope blackout shots"
	$Main.host_zone(ZoneDef.normalize(def))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = level.insertion_points()[0] + Vector3(0, 1.0, 0)
	for i in 10:
		await get_tree().physics_frame
	sight = GunSight.of(player)
	await _run_lpvo_to_prism(out)
	await _run_magnifier(out)
	await _run_window_resize(out)
	if failed:
		print("[scope] TEST FAILED")
	else:
		print("[scope] SCOPE BLACKOUT TEST PASSED")
	get_tree().quit(1 if failed else 0)


## Scoped on the LPVO at 6x, then swapped to the 4x prism mid-aim (ring 0.48 -> 0.42: a resize) -
## the "swap optics" trigger from the bug report.
func _run_lpvo_to_prism(out: String) -> void:
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), &"optic_lpvo"))
	_aim(6.0)
	for i in 4:
		await get_tree().process_frame
	await _shot_and_check(out, "lpvo_steady")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), &"optic_prism_4x"))
	_aim(4.0)
	await _shot_and_check(out, "prism_swap_frame0")  # the very frame of the resize
	for i in 3:
		await get_tree().process_frame
		await _shot_and_check(out, "prism_swap_frame%d" % (i + 1))


## The holo's flip-up magnifier (ring RING -> MAGNIFIER_RING: a resize) - the "toggle a
## magnifier" trigger from the bug report.
func _run_magnifier(out: String) -> void:
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), &"optic_holo"))
	_aim(1.0)
	for i in 4:
		await get_tree().process_frame
	await _shot_and_check(out, "holo_steady")
	GunSight.zoom_step(player, 1)  # magnifier up
	_aim(3.0)
	await _shot_and_check(out, "magnifier_up_frame0")
	for i in 3:
		await get_tree().process_frame
		await _shot_and_check(out, "magnifier_up_frame%d" % (i + 1))


## A window/viewport resize while scoped (ring is a share of screen height: a resize too) - the
## third trigger from the bug report.
func _run_window_resize(out: String) -> void:
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), &"optic_lpvo"))
	_aim(6.0)
	for i in 4:
		await get_tree().process_frame
	await _shot_and_check(out, "resize_before")
	get_window().size = get_window().size + Vector2i(100, 80)
	await get_tree().process_frame
	await _shot_and_check(out, "resize_frame0")
	for i in 3:
		await get_tree().process_frame
		await _shot_and_check(out, "resize_frame%d" % (i + 1))


## Aims `player` through whatever optic is on the primary now, snapping GunSight's eased glass
## fov straight to its target (skips the real multi-second ADS ease - this is a rendering check,
## not an aim-speed one).
func _aim(_mag: float) -> void:
	player.is_aiming = true
	var weapon := player.active_weapon()
	var target := GunSight.aimed_fov_of(player, weapon, GameSettings.view_fov())
	GunSight.ease_glass(player, target, 1.0)


## Samples 4 points inside the ring, off its cross/heavy-post lines (diagonal, a third of the way
## out): the real magnified scene (sky, terrain) behind the reticle ink, which in a lit outdoor
## zone is never near-black unless the PIP texture itself is (the bug) rather than the by-design
## black ring mask further out (untouched, not sampled here).
func _shot_and_check(out: String, label: String) -> void:
	sight.queue_redraw()
	await RenderingServer.frame_post_draw
	_frame += 1
	if headless:
		print("[scope] [skip] %s (headless, nothing to sample)" % label)
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [out, _frame, label])
	var centre := Vector2(img.get_size()) * 0.5
	var reach := centre.y * 0.33
	var black := true
	var sample := Color.BLACK
	for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var at := centre + dir * reach
		var px := img.get_pixel(int(at.x), int(at.y))
		sample = px
		if px.r > 0.02 or px.g > 0.02 or px.b > 0.02:
			black = false
	print("%s %s: sampled %s" % ["[FAIL]" if black else "[ok]", label, sample])
	failed = failed or black
