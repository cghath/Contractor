class_name GunSight
extends Control
## The local player's sight picture (Captain, P0362: "No scope/sights"), drawn over the view
## while aiming. What it shows is the optic mounted on the weapon in hand (Optics: an item in
## the gun's state), or the gun's irons with none:
## - irons: the view model's own sights line up on the eye (VoxelArt.sight_point,
##   PlayerInput.ads_view): a pistol's post and notch, a rifle's back-up aperture and post.
## - an open optic ("view": "open"): you look through it and its lit reticle sits in the
##   middle: a red dot ("dot", dot_moa across) or a holographic ring and dot ("holo"). A
##   holographic sight's flip-up magnifier ("magnifier", its power) flips up on zoom in and
##   down on zoom out (zoom_step), and while it's up you look through its glass.
## - a tube optic ("view": "tube": LPVO, prism, DMR scopes): once zoomed in you're behind the
##   glass: a real picture-in-picture (P0362 PIP rework, Captain: "better scopes and PIP"; art
##   task "PiP scopes") — a SubViewport with its own Camera3D at the optic's actual
##   magnification, synced to the eye every frame, shown in the eyepiece ring ("ring", a share of
##   the screen's height) with the optic's reticle drawn over it: "lpvo" (lit centre dot,
##   crosshair with mil hashes, heavy posts), "chevron" (a lit chevron and its BDC holds, "bdc")
##   or "mil_dot". The player's own camera stays at the peripheral (unaimed) field of view, so
##   the gun and its surroundings around the scope picture don't narrow with it — only the glass
##   magnifies. The picture looks where the eye does (the aim sway and the recoil turn the eye
##   itself, Soldier.aim_sway and _kick: where the shot goes); the gun's own kick and settle
##   carry the lens about on the screen with it (_lens_shift). Under NVG the picture is seen
##   through the goggles like the rest (NvgView.scope_material). The video setting "scope_pip"
##   (GameSettings.scope_pip_scale) sets its resolution or turns it off, and it's off headless:
##   off, the whole view zooms behind the ring as it did before PiP (pip_on).
## Power (Captain, 2026-10-13) is against the player's own unaimed view: 10x makes things ten
## times bigger than the base field of view shows them (its tangent over 10: about 6.4 degrees
## at the default 58.7 vertical, 90 across 16:9), the same rule for every magnified optic; at 1x the weapon's ads_fov, or
## an open 1x optic's own wider "ads_fov" (red dot, holo; Captain, 2026-10-14: aimed through a
## red dot it still looked big, the M4's 50 degrees drawing it twice its size at the hip, so a
## 1x sight zooms in a little less).
## A variable optic steps through its powers on zoom in and out (the side mouse buttons by
## default, Controls.BUTTONS; zoom_step) from its "magnification_start". Mils
## and MOA are worked out from the field of view actually shown, so every reticle reads true
## at any power (a 1.8 m man at 300 m is 6 mils tall). The heavy posts start POST_SHARE of the
## way out to the ring, and the fine cross between carries mil marks a mil apart, or 2, 5, 10
## or 20 where that would crowd them (mark_step). Launchers draw their own
## (LauncherSight). One per local player, on the HUD.

## How far a tube optic must have zoomed in (camera fov within this factor of its aimed fov at
## its lowest power) before you are behind the glass.
const SCOPE_IN := 1.35
## One zoom step of a variable optic (x or / this).
const ZOOM_STEP := 1.25
## The eyepiece ring when an optic names none, and a magnifier's.
const RING := 0.46
const MAGNIFIER_RING := 0.4
## Mil marks on the fine cross, out to the heavy posts (POST_SHARE of the ring): the finest
## spacing of MARK_STEPS (mils) that keeps them MIN_MARK_PX apart and at most MAX_MARKS each
## way; every fifth mark is bigger.
const POST_SHARE := 0.4
const MARK_STEPS := [1.0, 2.0, 5.0, 10.0, 20.0]
const MIN_MARK_PX := 6.0
const MAX_MARKS := 16
const DOT_SIZE_MILS := 0.25
## Lit reticles: drawn at least LIT_MIN_PX across.
const LIT_MIN_PX := 3.0
const INK := Color(0.02, 0.02, 0.02, 0.95)
const LIT := Color(1.0, 0.12, 0.08, 0.95)
const LIT_GLOW := Color(1.0, 0.2, 0.1, 0.25)
## A man's shoulders (m): a BDC hold's stadia line is this wide at its range.
const SHOULDERS_M := 0.48
const MOA_PER_MIL := 3.4377
## The scope picture's render size (PiP), in real pixels: the lens' size on screen times the
## setting's scale (GameSettings.scope_pip_scale: a scope is read through a narrow, slightly
## soft tube anyway, so a little under the displayed size costs less for no real loss), never
## more than the render scale, within these.
const SCOPE_MIN_PX := 64
const SCOPE_MAX_PX := 2048
## How far the gun's own kick and settle can carry the lens off the middle of the screen, as a
## share of the ring (_lens_shift).
const LENS_SHIFT_MAX := 0.35

## Test-only (DevTools.on(): the test runs): builds and drives the scope picture where nothing
## renders (headless), so a test can watch it switch on and off. Never set in a player's game.
static var _force_pip := false

var body: Soldier
var _drawn := false
## A variable optic's power, per optic id (kept while you switch away and back).
var _zoom := {}
## Flip-up magnifiers that are in, per optic id.
var _magnified := {}
## The sight's own eased "behind the glass" field of view (ease_glass): drives SCOPE_IN and the
## scope SubViewport's camera. 0 until first aimed. Not the player's real camera.fov, which a
## tube optic keeps at the peripheral view (PIP rework) instead of narrowing with this.
var _glass_fov := 0.0
## The scope's own render (PIP rework): a SubViewport with a Camera3D synced to the player's
## camera every frame while behind a tube optic's glass, instead of the whole screen zooming.
var _scope_vp: SubViewport
var _scope_cam: Camera3D
## The scope picture on the screen: _scope_vp's texture in the lens, drawn behind the sight's own
## ring and reticle (show_behind_parent), with the goggles' effect on it under NVG (_nvg_material).
var _scope_pic: TextureRect
var _nvg_material: ShaderMaterial
## Where the lens sits off the middle of the screen (pixels): the gun's own kick and settle
## (the view model's turn off the eye's line), at most LENS_SHIFT_MAX of the ring. 0 without PiP.
var _lens_shift := Vector2.ZERO
## True for the one frame right after _scope_vp is made or resized: Godot doesn't repaint a
## SubViewport in the same frame as that, so its texture is stale or blank that frame (Captain,
## playtest v0.4.26: scopes "sometimes go black" on a magnifier flip, an optic swap, or a window
## resize - all of which resize it). Hide the picture that one frame rather than show the bad
## texture; the ring mask (by-design black) still draws either way.
var _scope_stale := false


func _init(s: Soldier) -> void:
	body = s
	name = "GunSight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_priority = 110  # after the view has turned and moved this frame (PlayerInput; VehicleCamera is 100)


## Test-only: see _force_pip. Ignored outside DevTools.on().
static func force_pip_for_tests(on: bool) -> void:
	_force_pip = on and DevTools.on()


## The optic on `s`'s weapon in hand (null: irons, or not a gun).
static func optic_of(s: Soldier) -> ItemData:
	var weapon := s.active_weapon()
	if weapon == null or weapon.type != "weapon" or Launchers.is_launcher(weapon):
		return null
	return Optics.mounted(weapon, s.inventory.state_of(s.active_slot))


## "iron", or the optic's view: "open" or "tube".
static func view_of(optic: ItemData) -> String:
	return String(optic.stats.get("view", "open")) if optic else "iron"


## An optic's powers: (lowest, highest); both "magnification" for a fixed one (1: none).
static func zoom_range(optic: ItemData) -> Vector2:
	if optic == null:
		return Vector2.ONE
	var low := maxf(float(optic.stats.get("magnification", 1.0)), 1.0)
	return Vector2(low, maxf(float(optic.stats.get("magnification_max", low)), low))


## The local player's sight (null for anyone else).
static func of(s: Soldier) -> GunSight:
	var hud: Node = s.player_input.hud if s and s.player_input else null
	return hud.get_node_or_null(^"GunSight") as GunSight if hud else null


## True while `optic`'s flip-up magnifier is in (for `s`, the local player).
static func magnified(s: Soldier, optic: ItemData) -> bool:
	var sight := of(s)
	return optic != null and optic.stats.has("magnifier") and sight != null and bool(sight._magnified.get(optic.id, false))


## The power `s` sees through `optic` at: its magnifier's while that's in, else what they
## last zoomed it to (else its "magnification_start", else its lowest).
static func power(s: Soldier, optic: ItemData) -> float:
	if optic == null:
		return 1.0
	if magnified(s, optic):
		return float(optic.stats.magnifier)
	var zr := zoom_range(optic)
	var sight := of(s)
	var start := float(optic.stats.get("magnification_start", zr.x))
	return clampf(float(sight._zoom.get(optic.id, start)) if sight else start, zr.x, zr.y)


## The camera's (vertical) field of view aimed with `weapon` at power `mag`, from the unaimed
## `base_fov`: the view's tangent over the power (no wider than the weapon's ads_fov). At 1x
## `optic` may widen it to its own "ads_fov" (never wider than `base_fov`).
static func aimed_fov(weapon: ItemData, base_fov: float, mag := 1.0, optic: ItemData = null) -> float:
	var ads := float(weapon.stats.get("ads_fov", 55)) if weapon else base_fov
	if optic and optic.stats.has("ads_fov"):
		ads = maxf(ads, minf(float(optic.stats.ads_fov), base_fov))
	if mag <= 1.0:
		return ads
	return minf(ads, rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov * 0.5)) / mag)))


## `s`'s aimed field of view with `weapon` right now (their optic's power).
static func aimed_fov_of(s: Soldier, weapon: ItemData, base_fov: float) -> float:
	var optic := optic_of(s)
	return aimed_fov(weapon, base_fov, power(s, optic), optic)


## True while `s` is aimed through glass: a tube optic, or a magnifier that's in, zoomed in
## far enough (SCOPE_IN) to be behind it. Checked against the sight's own eased "glass" field of
## view (ease_glass), not the real camera: a tube optic's periphery no longer narrows with it
## (PIP rework), only the scope's own SubViewport does. Never down or dead, nor in a vehicle's
## seat but a fire-from-vehicle one seen through your own eyes (Captain, 2026-10-17: "scopes dont
## work in ffv"; _active already drew the sight there, but with no glass a tube optic zoomed the
## whole view with no reticle).
static func scoped(s: Soldier) -> bool:
	if not s.is_aiming or (s.vitals and not s.vitals.is_up()) or s.respawn_state == Soldier.RESPAWN_WAITING:
		return false
	if is_instance_valid(s.vehicle) and not (s.vehicle.ffv_seat(s) and s.camera.current):
		return false
	var optic := optic_of(s)
	var magnifier := magnified(s, optic)
	if view_of(optic) != "tube" and not magnifier:
		return false
	var lowest := float(optic.stats.magnifier) if magnifier else zoom_range(optic).x
	var sight := of(s)
	var glass := sight._glass_fov if sight and sight._glass_fov > 0.0 else GameSettings.view_fov()
	return glass <= aimed_fov(s.active_weapon(), GameSettings.view_fov(), lowest, optic) * SCOPE_IN


## True while `s` should see a magnified optic's own picture (picture-in-picture): behind its
## glass (scoped: a tube optic, or a holographic sight's magnifier while it's up; never a red dot
## or a holographic sight at 1x) with the setting on (GameSettings.scope_pip_scale). Whether it
## can render here is pip_on's.
static func pip_wanted(s: Soldier) -> bool:
	return GameSettings.scope_pip_scale() > 0.0 and scoped(s)


## pip_wanted where a picture can render: never headless (unless a test forces it,
## force_pip_for_tests). Off, the whole view zooms behind the ring instead, as before PiP
## (PlayerInput._update_aim).
static func pip_on(s: Soldier) -> bool:
	return pip_wanted(s) and (ItemIcons.can_render() or _force_pip)


## The power the glass shows now: the unaimed view's tangent over the sight's eased "glass"
## field of view (ease_glass); 1 before it's first aimed. The optic's power once eased in.
static func glass_power(s: Soldier) -> float:
	var sight := of(s)
	if sight == null or sight._glass_fov <= 0.0:
		return 1.0
	return tan(deg_to_rad(GameSettings.view_fov() * 0.5)) / tan(deg_to_rad(sight._glass_fov * 0.5))


## The scope picture camera's (vertical) field of view for a glass field of view `glass` shown
## in a lens `lens_share` of the screen's height across: what that much of a screen zoomed to
## `glass` would show, so things are exactly the optic's power bigger than the unaimed view shows
## them, as with PiP off (and the reticle's mils read the same either way).
static func picture_fov(glass: float, lens_share: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(glass * 0.5)) * lens_share))


## Eases `s`'s sight's "glass" field of view toward `target` by `k` (0–1, this frame's lerp
## weight): called from the real camera.fov's own lerp (PlayerInput._update_aim) so the two stay
## in step, but kept apart from it — a tube optic's camera.fov eases to the peripheral view
## instead once scoped (PIP rework), while this keeps easing to the full magnified target.
static func ease_glass(s: Soldier, target: float, k: float) -> void:
	var sight := of(s)
	if sight == null:
		return
	if sight._glass_fov <= 0.0:
		sight._glass_fov = target
	sight._glass_fov = lerpf(sight._glass_fov, target, k)


## Zoom in (`steps` > 0) or out on the optic in hand: a magnifier flips up on zoom in and down
## on zoom out; a variable optic steps a ZOOM_STEP each, within its range. Returns what to show
## ("LPVO 1-6x: 2.4x", "Magnifier up"), or "" when nothing changed.
static func zoom_step(s: Soldier, steps: int) -> String:
	var sight := of(s)
	var optic := optic_of(s)
	if sight == null or optic == null or steps == 0:
		return ""
	if optic.stats.has("magnifier"):
		var up := steps > 0
		if up == magnified(s, optic):
			return ""
		sight._magnified[optic.id] = up
		return "Magnifier up (%dx)" % roundi(float(optic.stats.magnifier)) if up else "Magnifier down"
	var zr := zoom_range(optic)
	if zr.y <= zr.x:
		return ""
	var was := power(s, optic)
	sight._zoom[optic.id] = clampf(was * pow(ZOOM_STEP, steps), zr.x, zr.y)
	var now := power(s, optic)
	return "%s: %.1fx" % [optic.name, now] if not is_equal_approx(now, was) else ""


## Mouse turn scale for the zoom (P0362: sensitivity follows the magnification): behind glass,
## how much the view's tangent has shrunk from the weapon's plain aimed view (the settings'
## aim sensitivity covers that); 1 otherwise. Against the sight's own "glass" field of view
## (ease_glass), not the real camera, which no longer narrows for a tube optic (PIP rework) —
## the picture inside the scope still turns fast relative to the (unmagnified) mouse motion.
static func zoom_turn(s: Soldier) -> float:
	if not scoped(s):
		return 1.0
	var sight := of(s)
	var glass := sight._glass_fov if sight and sight._glass_fov > 0.0 else s.camera.fov
	var ads := aimed_fov(s.active_weapon(), GameSettings.view_fov(), 1.0, optic_of(s))
	return minf(tan(deg_to_rad(glass * 0.5)) / tan(deg_to_rad(ads * 0.5)), 1.0)


## Pixels per mil at camera field of view `fov` on a screen `height` pixels tall.
static func px_per_mil(fov: float, height: float) -> float:
	return 0.001 / tan(deg_to_rad(fov * 0.5)) * height * 0.5


## The spacing (mils) of mil marks at `px` pixels a mil out to `reach` pixels: the finest of
## MARK_STEPS that keeps them MIN_MARK_PX apart and no more than MAX_MARKS.
static func mark_step(px: float, reach := 0.0) -> float:
	for step: float in MARK_STEPS:
		if step * px >= MIN_MARK_PX and (reach <= 0.0 or reach / (step * px) <= MAX_MARKS):
			return step
	return MARK_STEPS[-1]


func _active() -> bool:
	var weapon := body.active_weapon()
	return body.is_aiming and weapon != null and weapon.type == "weapon" and not Launchers.is_launcher(weapon) \
		and (not is_instance_valid(body.vehicle) or body.vehicle.ffv_seat(body))  # a fire-from-vehicle seat: the scope's glass too (Captain, 2026-10-17: "scopes dont work in ffv")


func _process(_delta: float) -> void:
	var on := _active()
	if on or _drawn:
		queue_redraw()
	_drawn = on
	_update_pip(on)


## The scope picture on and in step this frame while pip_on, else off: not aimed, irons or an
## open sight, another weapon in hand, down or dead, in a vehicle's seat, the setting off, or
## headless. Off, it costs nothing: no render (UPDATE_DISABLED) and nothing drawn.
func _update_pip(active: bool) -> void:
	var optic := optic_of(body) if active else null
	if optic and pip_on(body):
		_sync_scope_viewport(_ring_px(optic))
		return
	_lens_shift = Vector2.ZERO
	if _scope_vp:
		_scope_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_scope_pic.visible = false


## True while the scope picture renders (a test's view of _update_pip).
func pip_rendering() -> bool:
	return _scope_vp != null and _scope_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS


## The scope picture's camera (null until first shown): for tests.
func pip_camera() -> Camera3D:
	return _scope_cam


## The eyepiece ring's radius (pixels) for `optic`: its own "ring" share of the screen's height,
## a magnifier's while that's up.
func _ring_px(optic: ItemData) -> float:
	return get_viewport_rect().size.y * (MAGNIFIER_RING if magnified(body, optic) else float(optic.stats.get("ring", RING)))


func _draw() -> void:
	if not _active():
		return
	var optic := optic_of(body)
	if optic == null:
		return  # irons: the view model's own
	var size := get_viewport_rect().size
	var centre := size * 0.5
	var reticle := String(optic.stats.get("reticle", "dot"))
	if scoped(body):
		var ring := _ring_px(optic)
		# Mils against the glass over the whole screen's height: with PiP the picture shows that
		# much of it in the lens (picture_fov), without it the real camera is zoomed to it.
		var px := px_per_mil(_glass_fov if _glass_fov > 0.0 else body.camera.fov, size.y)
		var pip := pip_rendering()
		var lens := centre + _lens_shift
		_draw_ring(lens, ring, ring * sqrt(2.0) + 2.0 if pip else centre.length() + 2.0)
		match reticle:
			"lpvo": _draw_lpvo(lens, ring, px)
			"chevron": _draw_chevron(lens, ring, px, optic.stats.get("bdc", []))
			"mil_dot": _draw_scale(lens, ring, px, true)
			_: _draw_lit(lens, px, optic)  # a magnified red dot or holographic reticle
	elif view_of(optic) == "open":
		var px := px_per_mil(body.camera.fov, size.y)
		_draw_lit(centre, px, optic)


## Makes (once) the scope's SubViewport, its own Camera3D and the picture that shows it, then
## keeps them in step with the player's real camera: the same eye and look (the aim sway and the
## recoil turn the eye itself, so a plain transform copy points the glass where the shot goes),
## at picture_fov of the sight's eased glass. It shares the level's World3D (a SubViewport's by
## default), skips VIEW_MODEL_LAYER (the gun would show up huge, in the way, inside its own
## picture), renders at the setting's share of the lens' real pixels (GameSettings.scope_pip_scale,
## no more than the render scale) with no MSAA or TAA (FXAA), and only while shown (_update_pip).
func _sync_scope_viewport(ring: float) -> void:
	_scope_stale = false
	var root := get_viewport()
	if _scope_vp == null:
		_scope_vp = SubViewport.new()
		_scope_vp.name = "ScopeView"
		_scope_vp.msaa_3d = Viewport.MSAA_DISABLED
		_scope_vp.use_taa = false
		_scope_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_scope_vp.positional_shadow_atlas_size = 1024
		_scope_vp.gui_disable_input = true
		_scope_vp.mesh_lod_threshold = root.mesh_lod_threshold
		_scope_vp.use_occlusion_culling = root.use_occlusion_culling
		add_child(_scope_vp)
		_scope_cam = Camera3D.new()
		_scope_vp.add_child(_scope_cam)
		_scope_cam.current = true
		_scope_pic = TextureRect.new()
		_scope_pic.name = "ScopePicture"
		_scope_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scope_pic.show_behind_parent = true  # under the ring and the reticle (this Control's own _draw)
		_scope_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_scope_pic.stretch_mode = TextureRect.STRETCH_SCALE
		_scope_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_scope_pic.texture = _scope_vp.get_texture()
		add_child(_scope_pic)
		_scope_stale = true  # not rendered even once yet
	var size := get_viewport_rect().size
	var real_px := float(get_tree().root.size.y)  # the window's own pixels: the UI scale shrinks `size`
	var scale := GameSettings.scope_pip_scale() * minf(root.scaling_3d_scale, 1.0) * (real_px / size.y if size.y > 0.0 else 1.0)
	var side := clampi(roundi(ring * 2.0 * scale), SCOPE_MIN_PX, SCOPE_MAX_PX)
	if _scope_vp.size.x != side:
		_scope_vp.size = Vector2i(side, side)
		_scope_stale = true  # resized: repaints next frame, not this one
	_scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := body.camera
	_scope_cam.cull_mask = cam.cull_mask & ~PlayerInput.VIEW_MODEL_LAYER & ~PlayerInput.LOCAL_BODY_LAYER
	_scope_cam.near = cam.near
	_scope_cam.far = cam.far
	_scope_cam.environment = cam.environment
	_scope_cam.attributes = cam.attributes
	_scope_cam.h_offset = cam.h_offset
	_scope_cam.v_offset = cam.v_offset
	var glass := _glass_fov if _glass_fov > 0.0 else cam.fov
	_scope_cam.fov = clampf(picture_fov(glass, ring * 2.0 / size.y if size.y > 0.0 else 1.0), 0.1, 170.0)
	_scope_cam.global_transform = cam.global_transform
	_lens_shift = _lens_shift_px(ring, size)
	_scope_pic.position = size * 0.5 + _lens_shift - Vector2.ONE * ring
	_scope_pic.size = Vector2.ONE * ring * 2.0
	_scope_pic.visible = not _scope_stale
	if Nvg.is_on(body):  # seen through the goggles like the rest, the eyepiece filling the tube
		if _nvg_material == null:
			_nvg_material = NvgView.scope_material()
		NvgView.set_view(_nvg_material, body, size, (ring + _lens_shift.length()) / (size.y * 0.5) * 1.08 if size.y > 0.0 else 0.0)
		_scope_pic.material = _nvg_material
	else:
		_scope_pic.material = null


## Where the gun's own kick and settle (the view model turned off the eye's line: PlayerInput's
## VIEW_KICK_PITCH, SoldierMovement.weapon_sway) put the lens on a screen `size` across, off its
## middle: where the optic's line points in the real (unzoomed) view, at most LENS_SHIFT_MAX of
## the `ring`. The picture inside stays on the eye's line, so the reticle still shows where the
## shot goes; the eyepiece just moves about with the gun.
func _lens_shift_px(ring: float, size: Vector2) -> Vector2:
	var vm := body.view_model
	if vm == null or not vm.visible:
		return Vector2.ZERO
	var d := vm.basis.orthonormalized() * Vector3.FORWARD  # the view model hangs off the camera
	if d.z > -0.2:
		return Vector2.ZERO
	var half := size.y * 0.5 / tan(deg_to_rad(body.camera.fov * 0.5))
	return (Vector2(d.x, -d.y) / -d.z * half).limit_length(ring * LENS_SHIFT_MAX)


## Black beyond the eyepiece ring (`ring` pixels across the middle) out to `reach`: a thick
## circle, then a thin ring at the boundary.
func _draw_ring(centre: Vector2, ring: float, reach: float) -> void:
	var band := reach - ring
	draw_arc(centre, ring + band * 0.5, 0.0, TAU, 128, Color.BLACK, band + 2.0, true)
	draw_arc(centre, ring, 0.0, TAU, 128, Color(0.1, 0.1, 0.1), maxf(get_viewport_rect().size.y * 0.006, 3.0), true)


## A lit dot (dot_moa across), and a holographic sight's ring (ring_moa) around it.
func _draw_lit(centre: Vector2, px: float, optic: ItemData) -> void:
	var moa := px / MOA_PER_MIL
	var r := maxf(float(optic.stats.get("dot_moa", 2.0)) * moa, LIT_MIN_PX) * 0.5
	draw_circle(centre, r * 2.0, LIT_GLOW)
	draw_circle(centre, r, LIT)
	if optic.stats.has("ring_moa"):
		var ring := float(optic.stats.ring_moa) * moa * 0.5
		draw_arc(centre, ring, 0.0, TAU, 96, LIT_GLOW, maxf(r * 2.4, 2.0), true)
		draw_arc(centre, ring, 0.0, TAU, 96, LIT, maxf(r * 1.2, 1.0), true)


## Thin cross with mil marks (mark_step) out to the heavy posts, which run from POST_SHARE of
## the ring out to it; `dots`: round mil dots, else short hashes.
func _draw_scale(centre: Vector2, ring: float, px: float, dots: bool) -> void:
	var height := get_viewport_rect().size.y
	var thin := maxf(height * 0.0012, 1.0)
	var heavy := maxf(height * 0.006, 3.0)
	var post := ring * POST_SHARE
	var step := mark_step(px, post)
	draw_line(centre + Vector2(-post, 0), centre + Vector2(post, 0), INK, thin, true)
	draw_line(centre + Vector2(0, -post), centre + Vector2(0, post), INK, thin, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * post, centre + dir * ring, INK, heavy)
		var k := 1
		while k * step * px < post - 2.0:
			var at := centre + dir * k * step * px
			var big := 1.6 if k % 5 == 0 else 1.0
			if dots:
				draw_circle(at, maxf(px * DOT_SIZE_MILS * 0.5, 1.5) * big, INK)
			else:
				var across := Vector2(dir.y, dir.x) * maxf(px * 0.3, 3.0) * big
				draw_line(at - across, at + across, INK, thin, true)
			k += 1


## An LPVO: a lit centre dot (usable at 1x) on a hashed cross with heavy posts.
func _draw_lpvo(centre: Vector2, ring: float, px: float) -> void:
	_draw_scale(centre, ring, px, false)
	var r := maxf(0.5 * px, LIT_MIN_PX * 1.3) * 0.5
	draw_circle(centre, r * 2.0, LIT_GLOW)
	draw_circle(centre, r, LIT)


## A prism's lit chevron (its tip the aim point) on a thin post, with its BDC holds below:
## each `bdc` entry [range m, mils below] a line as wide as a man's shoulders at that range,
## its hundreds of metres beside it; heavy side posts out to the ring.
func _draw_chevron(centre: Vector2, ring: float, px: float, bdc: Array) -> void:
	var height := get_viewport_rect().size.y
	var w := maxf(px * 0.75, height * 0.007)  # the chevron's half-width
	var line := maxf(px * 0.2, height * 0.0015)
	for c: Color in [LIT_GLOW, LIT]:
		var t := line * (2.2 if c == LIT_GLOW else 1.0)
		draw_line(centre, centre + Vector2(-w, w), c, t, true)
		draw_line(centre, centre + Vector2(w, w), c, t, true)
	var lowest := centre.y + w
	var font := get_theme_default_font()
	for hold: Array in bdc:
		# True to its mils: one that would sit under the chevron or crowd the one above (at low
		# power, against a wide base view) is left out.
		var y := centre.y + float(hold[1]) * px
		if y > centre.y + ring - 4.0 or y < lowest + 12.0:
			continue
		var half := SHOULDERS_M / float(hold[0]) * 1000.0 * px * 0.5
		draw_line(Vector2(centre.x - half, y), Vector2(centre.x + half, y), INK, maxf(line * 0.6, 1.0), true)
		if font:
			draw_string(font, Vector2(centre.x + half + 4.0, y + 4.0), str(roundi(float(hold[0]) / 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
		lowest = y
	draw_line(Vector2(centre.x, centre.y + line), Vector2(centre.x, lowest), INK, maxf(line * 0.6, 1.0), true)
	var heavy := maxf(height * 0.006, 3.0)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT]:
		draw_line(centre + dir * ring * 0.55, centre + dir * ring, INK, heavy)
