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
##   glass: a real picture-in-picture (P0362 PIP rework, Captain: "better scopes and PIP") — a
##   SubViewport with its own Camera3D at the optic's actual magnification, synced to the eye
##   every frame, composited into the eyepiece ring ("ring", a share of the screen's height) with
##   the optic's reticle drawn over it: "lpvo" (lit centre dot, crosshair with mil hashes, heavy
##   posts), "chevron" (a lit chevron and its BDC holds, "bdc") or "mil_dot". The player's own
##   camera stays at the peripheral (unaimed) field of view the whole time, so the gun and its
##   surroundings around the scope picture don't narrow with it — only the glass magnifies.
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
## The scope SubViewport's render size against the ring it's shown at (PIP rework): a scope is
## read through a narrow, slightly soft tube anyway, so rendering it a little under the
## displayed size (and letting the texture stretch up) costs less for no real loss of clarity.
const SCOPE_RENDER_SCALE := 0.65

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
## True for the one _draw() right after _scope_vp is made or resized: Godot doesn't repaint a
## SubViewport in the same frame as that, so its texture is stale or blank that frame (Captain,
## playtest v0.4.26: scopes "sometimes go black" on a magnifier flip, an optic swap, or a window
## resize - all of which resize it). Skip compositing it that one frame rather than draw the bad
## texture; the ring mask (by-design black) still draws either way.
var _scope_stale := false


func _init(s: Soldier) -> void:
	body = s
	name = "GunSight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
## (PIP rework), only the scope's own SubViewport does.
static func scoped(s: Soldier) -> bool:
	if not s.is_aiming or is_instance_valid(s.vehicle):
		return false
	var optic := optic_of(s)
	var magnifier := magnified(s, optic)
	if view_of(optic) != "tube" and not magnifier:
		return false
	var lowest := float(optic.stats.magnifier) if magnifier else zoom_range(optic).x
	var sight := of(s)
	var glass := sight._glass_fov if sight and sight._glass_fov > 0.0 else GameSettings.view_fov()
	return glass <= aimed_fov(s.active_weapon(), GameSettings.view_fov(), lowest, optic) * SCOPE_IN


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
	if _scope_vp and not (on and scoped(body)):
		_scope_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # not behind glass: don't pay for the extra render


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
		var magnifier := magnified(body, optic)
		var ring := size.y * (MAGNIFIER_RING if magnifier else float(optic.stats.get("ring", RING)))
		var px := px_per_mil(_glass_fov, ring * 2.0)  # the magnified picture's own scale, not the (now peripheral) real camera's
		_draw_scope_pip(centre, ring)
		match reticle:
			"lpvo": _draw_lpvo(centre, ring, px)
			"chevron": _draw_chevron(centre, ring, px, optic.stats.get("bdc", []))
			"mil_dot": _draw_scale(centre, ring, px, true)
			_: _draw_lit(centre, px, optic)  # a magnified red dot or holographic reticle
	elif view_of(optic) == "open":
		var px := px_per_mil(body.camera.fov, size.y)
		_draw_lit(centre, px, optic)


## The scope's magnified picture (PIP rework): a SubViewport with its own Camera3D, synced to
## the player's every frame and rendered at SCOPE_RENDER_SCALE of the ring's screen size,
## composited into the eyepiece ring with the same black-corner mask the old whole-screen ring
## used, just over a render sized to the ring instead of the full screen. Falls back to the old
## bare mask where nothing can render (headless runs): the real camera's own (unmagnified, with
## PIP) picture shows through undecorated rather than nothing at all.
func _draw_scope_pip(centre: Vector2, ring: float) -> void:
	_sync_scope_viewport(ring)
	if _scope_vp and not _scope_stale:
		draw_texture_rect(_scope_vp.get_texture(), Rect2(centre - Vector2.ONE * ring, Vector2.ONE * ring * 2.0), false)
	_draw_ring(centre, ring, ring * sqrt(2.0) + 2.0 if _scope_vp else centre.length() + 2.0)


## Makes (once) the scope's SubViewport and its own Camera3D, sized to the ring and kept in
## step with the player's real camera (same place and look — weapon sway only moves the view
## model, not the camera itself, so a plain transform copy lines the glass up) at the sight's
## own magnified field of view (_glass_fov). Its cull_mask drops VIEW_MODEL_LAYER so the gun
## doesn't show up (huge, in the way) inside its own magnified picture. No-ops where nothing
## can render (headless runs: ItemIcons.can_render()).
func _sync_scope_viewport(ring: float) -> void:
	_scope_stale = false
	if _scope_vp == null:
		if not ItemIcons.can_render():
			return
		_scope_vp = SubViewport.new()
		_scope_vp.name = "ScopeView"
		add_child(_scope_vp)
		_scope_cam = Camera3D.new()
		_scope_vp.add_child(_scope_cam)
		_scope_cam.cull_mask = body.camera.cull_mask & ~PlayerInput.VIEW_MODEL_LAYER
		_scope_cam.near = body.camera.near
		_scope_cam.current = true
		_scope_stale = true  # not rendered even once yet
	var side := maxi(roundi(ring * 2.0 * SCOPE_RENDER_SCALE), 2)
	if _scope_vp.size.x != side:
		_scope_vp.size = Vector2i(side, side)
		_scope_stale = true  # resized: repaints next frame, not this one
	_scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_scope_cam.fov = clampf(_glass_fov if _glass_fov > 0.0 else body.camera.fov, 0.1, 170.0)
	_scope_cam.global_transform = body.camera.global_transform


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
