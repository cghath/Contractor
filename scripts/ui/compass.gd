class_name Compass
extends Control
## A scrolling bearing strip across the top of the screen (Arma/Squad-style): cardinal and
## intermediate directions slide past a fixed centre marker as the player turns, with the
## exact heading in degrees under it. Reads the player body's yaw each frame - the body is
## what turns (PlayerInput.turn_view/body.rotate_y); the head only pitches, so looking up or
## down doesn't move the compass. No state of its own beyond the heading last drawn.

## The strip's size (logical px) and how many degrees of world bearing it spans.
const HEIGHT := 30.0
const SPAN_DEG := 180.0
## A tick every this many degrees; a cardinal/intermediate direction every 45.
const TICK_DEG := 15.0
const DIRECTIONS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
## ui-modern (2026-10-20): the minor ticks were at 55%, the letters 14 px; now brighter, 16 px, outlined.
const COLOUR := Color(UiKit.TEXT_BRIGHT, 0.97)
const DIM_COLOUR := Color(UiKit.TEXT, 0.85)
const OUTLINE := UiKit.OUTLINE

var player: Soldier
var _heading := 0.0


func _init(p: Soldier = null) -> void:
	player = p
	name = "Compass"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)


## `body`'s bearing (0 north, 90 east, clockwise, degrees): its own yaw, not whatever its
## camera is pitched to.
static func bearing_of(body: Node3D) -> float:
	var forward := -body.global_basis.z
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		visible = false
		return
	visible = player.vitals.is_up()
	if not visible:
		return
	var heading := bearing_of(player)
	if not is_equal_approx(heading, _heading):
		_heading = heading
		queue_redraw()


func _draw() -> void:
	var mid := size.x * 0.5
	if mid <= 0.0:
		return
	var px_per_deg := size.x / SPAN_DEG
	var font := UiKit.FONT_STRONG
	var fs := UiKit.FONT_HUD_SMALL
	var half := SPAN_DEG * 0.5
	var deg := ceilf((_heading - half) / TICK_DEG) * TICK_DEG
	while deg <= _heading + half:
		var x := mid + (deg - _heading) * px_per_deg
		var norm := int(roundf(fposmod(deg, 360.0))) % 360
		var label: String = DIRECTIONS.get(norm, "")
		var major := label != ""
		var h := HEIGHT * (0.55 if major else 0.3)
		draw_line(Vector2(x, HEIGHT - h), Vector2(x, HEIGHT), OUTLINE, 4.0 if major else 3.0)  # an edge, for bright sky
		draw_line(Vector2(x, HEIGHT - h), Vector2(x, HEIGHT), COLOUR if major else DIM_COLOUR, 2.0 if major else 1.5)
		if label != "":
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(x - w * 0.5, HEIGHT - h - 3.0)
			draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, OUTLINE)
			draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.ACCENT_HOT if norm == 0 else COLOUR)
		deg += TICK_DEG
	draw_line(Vector2(mid, 0.0), Vector2(mid, HEIGHT), OUTLINE, 5.0)
	draw_line(Vector2(mid, 0.0), Vector2(mid, HEIGHT), UiKit.ACCENT, 3.0)
	var text := "%03d" % (int(roundf(_heading)) % 360)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tpos := Vector2(mid - tw * 0.5, HEIGHT + 16.0)
	draw_string_outline(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, OUTLINE)
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.ACCENT)
