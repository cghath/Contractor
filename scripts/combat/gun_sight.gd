class_name GunSight
extends Control
## The local player's rifle and pistol sights (Captain, P0362: "No scope/sights"), drawn over
## the view while aiming. Each weapon names its sight in items.json ("sight"):
## - "iron": the view model's own front post and rear notch line up on the eye (VoxelArt
##   sight_point, PlayerInput.ads_view); a rifle with irons but no modelled post gets a drawn one.
## - "red_dot": you look through the open optic tube; a red dot sits at the middle.
## - "scope": the view zooms to the scope's "magnification" (aimed_fov), the view model goes
##   (you are looking through the glass) and a scope picture is drawn: black outside the ring,
##   a thin crosshair with mil-dot holds and heavy posts towards the edge.
## Launchers draw their own (LauncherSight). One per local player, on the HUD.

## The scope picture's ring, as a share of the screen's height, and how far a scope must have
## zoomed in (camera fov within this factor of its aimed fov) before you are "in" the glass.
const SCOPE_RING := 0.46
const SCOPE_IN := 1.35
## Mil-dot holds: a dot every DOT_MILS, out to HOLD_MILS each way; heavy posts beyond POST_MILS.
const DOT_MILS := 2.0
const HOLD_MILS := 10.0
const POST_MILS := 24.0
const INK := Color(0.02, 0.02, 0.02, 0.95)
const DOT := Color(1.0, 0.12, 0.08, 0.95)
const DOT_GLOW := Color(1.0, 0.2, 0.1, 0.25)

var body: Soldier
var _drawn := false


func _init(s: Soldier) -> void:
	body = s
	name = "GunSight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The sight `weapon` has: "iron", "red_dot" or "scope" ("iron" when it names none).
static func sight_of(weapon: ItemData) -> String:
	return String(weapon.stats.get("sight", "iron")) if weapon else ""


## The camera's field of view aimed with `weapon`, from the unaimed `base_fov`: a scope's
## magnification (how much smaller the view's tangent gets), else the weapon's ads_fov.
static func aimed_fov(weapon: ItemData, base_fov: float) -> float:
	if sight_of(weapon) == "scope":
		var mag := maxf(float(weapon.stats.get("magnification", 4.0)), 1.0)
		return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov * 0.5)) / mag))
	return float(weapon.stats.get("ads_fov", 55)) if weapon else base_fov


## True while `s` is aimed through a scope (zoomed in far enough to be behind the glass).
static func scoped(s: Soldier) -> bool:
	var weapon := s.active_weapon()
	if not s.is_aiming or sight_of(weapon) != "scope" or Launchers.is_launcher(weapon):
		return false
	return s.camera.fov <= aimed_fov(weapon, GameSettings.fov()) * SCOPE_IN


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
			var r := maxf(size.y * 0.0025, 2.0)
			draw_circle(centre, r * 2.2, DOT_GLOW)
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
	var post := POST_MILS * px
	draw_line(centre + Vector2(-post, 0), centre + Vector2(post, 0), INK, thin, true)
	draw_line(centre + Vector2(0, -post), centre + Vector2(0, post), INK, thin, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * post, centre + dir * ring, INK, heavy)
		var m := DOT_MILS
		while m <= HOLD_MILS + 0.01:
			draw_circle(centre + dir * m * px, maxf(px * 0.4, 2.5), INK)
			m += DOT_MILS
