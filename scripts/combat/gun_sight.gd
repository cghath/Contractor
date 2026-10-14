class_name GunSight
extends Control
## The local player's rifle and pistol sights (Captain, P0362: "No scope/sights"), drawn over
## the view while aiming. Each weapon names its sight in items.json ("sight"):
## - "iron": the view model's own front post and rear notch line up on the eye (VoxelArt
##   sight_point, PlayerInput.ads_view); a rifle with irons but no modelled post gets a drawn one.
## - "red_dot": you look through the open optic tube; a red dot sits at the middle.
## - "scope": the view zooms in (aimed_fov) until the ring shows what the real scope shows at
##   its power, EYEPIECE_FIELD_DEG / power across (the M110's 3.5-10x: about 6 degrees at 3.5x,
##   2 at 10x), the view model goes (you are looking through the glass) and a scope picture is
##   drawn: black outside the ring, a thin crosshair with mil dots (one a mil out to HOLD_MILS)
##   and heavy posts from POST_MILS. The reticle is in the first focal plane (it grows with the
##   zoom), so a mil is a mil at any power: a 1.8 m man at 300 m stands 6 mils tall. A variable
##   scope ("magnification" to "magnification_max", e.g. the M110's 3.5-10x) zooms with the
##   mouse wheel while aimed through it, starting at "magnification_start" (zoom_by).
## Launchers draw their own (LauncherSight). One per local player, on the HUD.

## The scope picture's ring, as a share of the screen's height, and how far a scope must have
## zoomed in (camera fov within this factor of its aimed fov) before you are "in" the glass.
const SCOPE_RING := 0.46
const SCOPE_IN := 1.35
## A rifle scope's apparent field through the eyepiece, degrees: its true field (what the ring
## shows of the world) is this over its power. A Leupold-type 3.5-10x40 shows about 5.7
## degrees at 3.5x and 2.1 at 10x (Captain, P0362: real magnification).
const EYEPIECE_FIELD_DEG := 20.5
## Mil-dot holds: a dot (DOT_SIZE_MILS across) every DOT_MILS, out to HOLD_MILS each way;
## heavy posts from POST_MILS out to the ring.
const DOT_MILS := 1.0
const DOT_SIZE_MILS := 0.25
const HOLD_MILS := 4.0
const POST_MILS := 5.0
const INK := Color(0.02, 0.02, 0.02, 0.95)
const DOT := Color(1.0, 0.12, 0.08, 0.95)
const DOT_GLOW := Color(1.0, 0.2, 0.1, 0.25)
## A red dot's size, minutes of angle across (a 2 MOA dot), drawn at least DOT_MIN_PX across.
const DOT_MOA := 2.0
const DOT_MIN_PX := 3.0
## One mouse-wheel step of a variable scope's zoom (x or / this).
const ZOOM_STEP := 1.25

var body: Soldier
var _drawn := false
## A variable scope's power, per weapon id (kept while you switch away and back).
var _zoom := {}


func _init(s: Soldier) -> void:
	body = s
	name = "GunSight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The sight `weapon` has: "iron", "red_dot" or "scope" ("iron" when it names none).
static func sight_of(weapon: ItemData) -> String:
	return String(weapon.stats.get("sight", "iron")) if weapon else ""


## A scope's powers: (lowest, highest); both "magnification" for a fixed one.
static func zoom_range(weapon: ItemData) -> Vector2:
	var low := maxf(float(weapon.stats.get("magnification", 4.0)), 1.0)
	return Vector2(low, maxf(float(weapon.stats.get("magnification_max", low)), low))


## The power `s`'s scope on `weapon` is set to: what they last zoomed it to, else its
## "magnification_start" (else its lowest).
static func magnification(s: Soldier, weapon: ItemData) -> float:
	var zr := zoom_range(weapon)
	var sight := of(s)
	var start := float(weapon.stats.get("magnification_start", zr.x))
	return clampf(float(sight._zoom.get(weapon.id, start)) if sight else start, zr.x, zr.y)


## The camera's (vertical) field of view aimed with `weapon`, from the unaimed `base_fov`:
## through a scope at power `mag` (its lowest when 0), so wide that the ring (SCOPE_RING of
## the screen's height each way) spans the scope's true field, EYEPIECE_FIELD_DEG / mag; else
## the weapon's ads_fov.
static func aimed_fov(weapon: ItemData, base_fov: float, mag := 0.0) -> float:
	if sight_of(weapon) == "scope":
		if mag <= 0.0:
			mag = zoom_range(weapon).x
		var field := deg_to_rad(EYEPIECE_FIELD_DEG / maxf(mag, 1.0))
		return rad_to_deg(2.0 * atan(tan(field * 0.5) / (2.0 * SCOPE_RING)))
	return float(weapon.stats.get("ads_fov", 55)) if weapon else base_fov


## The true field (degrees across) the scope's ring shows at camera field of view `fov`.
static func ring_field(fov: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov * 0.5)) * 2.0 * SCOPE_RING))


## `s`'s aimed field of view with `weapon` right now (their scope's power: magnification).
static func aimed_fov_of(s: Soldier, weapon: ItemData, base_fov: float) -> float:
	return aimed_fov(weapon, base_fov, magnification(s, weapon) if sight_of(weapon) == "scope" else 0.0)


## True while `s` is aimed through a scope (zoomed in far enough to be behind the glass).
static func scoped(s: Soldier) -> bool:
	var weapon := s.active_weapon()
	if not s.is_aiming or sight_of(weapon) != "scope" or Launchers.is_launcher(weapon):
		return false
	return s.camera.fov <= aimed_fov(weapon, GameSettings.fov(), zoom_range(weapon).x) * SCOPE_IN


## Mouse wheel while aimed through a variable scope: `steps` up (in) or down (out) a
## ZOOM_STEP each. True if it was taken (the wheel does nothing else then).
static func zoom_by(s: Soldier, steps: int) -> bool:
	var sight := of(s)
	var weapon := s.active_weapon()
	if sight == null or not scoped(s):
		return false
	var zr := zoom_range(weapon)
	if zr.y <= zr.x:
		return false
	var mag := clampf(magnification(s, weapon) * pow(ZOOM_STEP, steps), zr.x, zr.y)
	sight._zoom[weapon.id] = mag
	return true


## Mouse turn scale for the zoom (P0362: sensitivity follows the magnification): through a
## scope, how much the view's tangent has shrunk; 1 otherwise (aim_sensitivity still applies).
static func zoom_turn(s: Soldier) -> float:
	if not scoped(s):
		return 1.0
	return tan(deg_to_rad(s.camera.fov * 0.5)) / tan(deg_to_rad(GameSettings.fov() * 0.5))


## The local player's sight (null for anyone else).
static func of(s: Soldier) -> GunSight:
	var hud: Node = s.player_input.hud if s and s.player_input else null
	return hud.get_node_or_null(^"GunSight") as GunSight if hud else null


func _weapon() -> ItemData:
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon" or Launchers.is_launcher(weapon) or is_instance_valid(body.vehicle):
		return null
	return weapon


func _process(_delta: float) -> void:
	var on := _weapon() != null and body.is_aiming
	if on or _drawn:
		queue_redraw()
	_drawn = on


func _draw() -> void:
	var weapon := _weapon()
	if weapon == null or not body.is_aiming:
		return
	var size := get_viewport_rect().size
	var centre := size * 0.5
	match sight_of(weapon):
		"scope":
			if scoped(body):
				_draw_scope(size, centre)
		"red_dot":
			# DOT_MOA across at this zoom (the view's vertical half-angle spans centre.y pixels).
			var moa := deg_to_rad(1.0 / 60.0) / tan(deg_to_rad(body.camera.fov * 0.5)) * centre.y
			var r := maxf(DOT_MOA * moa, DOT_MIN_PX) * 0.5
			draw_circle(centre, r * 2.0, DOT_GLOW)
			draw_circle(centre, r, DOT)
		_:
			if weapon.slot != &"sidearm":  # a rifle's irons: none modelled, so a drawn post
				var w := maxf(size.y * 0.004, 2.0)
				draw_rect(Rect2(centre + Vector2(-w * 0.5, 0), Vector2(w, size.y * 0.06)), INK)


## The scope picture: black beyond the ring, a thin crosshair with mil dots, heavy posts out
## to the ring.
func _draw_scope(size: Vector2, centre: Vector2) -> void:
	var ring := size.y * SCOPE_RING
	# Black outside the ring: the screen's edges, then a thick circle out to the corners.
	var reach := centre.length() + 2.0
	var band := reach - ring
	draw_arc(centre, ring + band * 0.5, 0.0, TAU, 128, Color.BLACK, band + 2.0, true)
	draw_arc(centre, ring, 0.0, TAU, 128, Color(0.1, 0.1, 0.1), maxf(size.y * 0.006, 3.0), true)
	# Pixels per mil at this zoom (the view's vertical half-angle spans centre.y pixels).
	var px := 0.001 / tan(deg_to_rad(body.camera.fov * 0.5)) * centre.y
	var thin := maxf(size.y * 0.0012, 1.0)
	var heavy := maxf(size.y * 0.006, 3.0)
	var post := minf(POST_MILS * px, ring)
	draw_line(centre + Vector2(-post, 0), centre + Vector2(post, 0), INK, thin, true)
	draw_line(centre + Vector2(0, -post), centre + Vector2(0, post), INK, thin, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * post, centre + dir * ring, INK, heavy)
		var m := DOT_MILS
		while m <= HOLD_MILS + 0.01:
			draw_circle(centre + dir * m * px, maxf(px * DOT_SIZE_MILS * 0.5, 1.5), INK)
			m += DOT_MILS
