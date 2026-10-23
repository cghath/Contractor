class_name VehicleSightOverlay
extends Control
## What a vehicle sight draws over its picture (combined arms A4, cg_brief queue item 2.3;
## docs/combined_arms.md 2.12.2), minimal and in the UiKit HUD look so A5's VehicleHud can restyle
## it: the reticle (a crosshair with mil ticks; the aux sight's stadia per round instead, a mark
## for each range to put on the target), and the readouts:
##   top:    channel, polarity and power | the sight's name | STAB ON / DEGRADED / OFF, LRF READY /
##           MULTIPLE RETURNS / FAULT / NO RETURN
##   bottom: the lased range (first or last return), the round loaded and next, the rounds left,
##           the HE fuze (AIRBURST at the lased range) | the lead and the track, the turret's and
##           hull's headings
## The commander's viewer adds where the gun points against his line and the designate prompt.
## Thermal's look (ThermalView's post-process) is a ColorRect under the reticle. Fits the
## ui_test's 10 resolutions (the gunnery suite checks it). Local only.

const MARGIN := 18.0
const TICK_MILS: Array[float] = [-10.0, -5.0, 5.0, 10.0]
const RETICLE := Color(0.95, 0.35, 0.2, 0.95)
const RETICLE_THERMAL := Color(0.15, 1.0, 0.25, 0.95)

var _post: ColorRect
var _blur: ColorRect
var _top_left: Label
var _top_mid: Label
var _top_right: Label
var _bottom_left: Label
var _bottom_right: Label
var _prompt: Label
var _info: Dictionary = {}
var _thermal := false
var _fov := 30.0


func _init() -> void:
	name = "VehicleSightOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.visible = false
	add_child(_post)
	_blur = ColorRect.new()
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.color = Color(0.6, 0.62, 0.6, 0.35)
	_blur.visible = false
	add_child(_blur)
	_top_left = _label(Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_top_mid = _label(Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_top_right = _label(Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_bottom_left = _label(Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_bottom_right = _label(Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_prompt = _label(Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)


func _label(preset: int, align: HorizontalAlignment) -> Label:
	var l := UiKit.hud_label("", &"HudSmallLabel")
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if preset in [Control.PRESET_TOP_LEFT, Control.PRESET_CENTER_TOP, Control.PRESET_TOP_RIGHT] else VERTICAL_ALIGNMENT_BOTTOM
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM] else \
		(Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT] else Control.GROW_DIRECTION_END)
	l.grow_vertical = Control.GROW_DIRECTION_END if l.vertical_alignment == VERTICAL_ALIGNMENT_TOP else Control.GROW_DIRECTION_BEGIN
	return l


## Shows sight `info` (VehicleGunnery.sight_info) through `sight` (its channel, power, field of view).
func show_info(info: Dictionary, sight: VehicleSight) -> void:
	_info = info
	_thermal = sight.channel == "thermal"
	_fov = sight.fov
	set_text(info, sight.channel, sight.polarity, sight.mag())
	_post.visible = _thermal
	if _thermal:
		_post.material = ThermalView.post_material()
	_blur.visible = bool(info.get("blur", false))
	queue_redraw()


## The readouts' text for `info` on `channel` ("day"/"thermal") at `power` (tests call it straight).
func set_text(info: Dictionary, channel: String, polarity: int, power: float) -> void:
	var name_ := String(info.get("name", ""))
	_top_left.text = "%s  %s%dx" % ["THERMAL" if channel == "thermal" else "DAY", (ThermalView.MODE_NAMES[polarity] + "  ") if channel == "thermal" else "", roundi(power)]
	_top_mid.text = name_ + ("  (back-up sight)" if bool(info.get("fallback", false)) else "")
	var lrf := String(info.get("lrf_state", ""))
	_top_right.text = "STAB %s%s" % [String(info.get("stab", "OFF")), ("    LRF " + lrf) if lrf != "" else ""]
	var l: Dictionary = info.get("lase", {})
	var range_text := "RANGE ----"
	if bool(l.get("ok", false)):
		range_text = "RANGE %d m  (%s)" % [roundi(float(l.get("r", 0.0))), String(info.get("ret", "last"))]
	var sol: Dictionary = info.get("sol", {})
	if bool(sol.get("on", false)) and bool(sol.get("bs", false)):
		range_text = "BATTLESIGHT %d m" % roundi(float(sol.get("r", 0.0)))
	var lines: PackedStringArray = [range_text]
	var loaded := String(info.get("loaded", ""))
	if loaded != "":
		var next := String(info.get("next", ""))
		lines.append("%s  > %s%s" % [loaded, "LOADED" if loaded != "-" else "LOADING", ("        next " + next) if next != "" else ""])
	var counts := String(info.get("rounds", ""))
	var fuze := String(info.get("fuze", ""))
	if counts != "" or fuze != "":
		lines.append(counts + (("    (%s)" % fuze) if fuze != "" else ""))
	_bottom_left.text = "\n".join(lines)
	var right: PackedStringArray = []
	if bool(sol.get("on", false)):
		right.append("LEAD %.1f mil   TRACK %s" % [float(info.get("lead_mil", 0.0)), _bar(float(sol.get("trk", 0.0)))])
	elif bool(info.get("stadia", false)):
		right.append("NO SOLUTION: HOLD OVER")
	right.append("turret %03d   hull %03d" % [int(info.get("turret_deg", 0)), int(info.get("hull_deg", 0))])
	_bottom_right.text = "\n".join(right)
	if bool(info.get("commander", false)):
		var key := OS.get_keycode_string(GameSettings.key_for(&"designate"))
		_prompt.text = "[%s] lay the gun here    gun %+d deg" % [key, roundi(float(info.get("gun_rel_deg", 0.0)))]
	else:
		_prompt.text = ""


## A track bar: a block a fifth of a second, to the lead's full second.
static func _bar(trk: float) -> String:
	var n := clampi(floori(trk / FireControl.LEAD_TRACK_S * 5.0), 0, 5)
	return "[" + "=".repeat(n) + "-".repeat(5 - n) + "]"


func _draw() -> void:
	if _info.is_empty():
		return
	var c := size * 0.5
	var col := RETICLE_THERMAL if _thermal else RETICLE
	var ppm := GunSight.px_per_mil(_fov, size.y)
	if bool(_info.get("stadia", false)):
		# The aux sight: a short bar for each range, as far below the centre as that range's hold-over.
		draw_line(c + Vector2(-60, 0), c + Vector2(60, 0), col, 2.0)
		draw_line(c + Vector2(0, -60), c + Vector2(0, -8), col, 2.0)
		for mark: Array in _info.get("marks", []):
			var y := float(mark[1]) * ppm
			if y > size.y * 0.45:
				continue
			draw_line(c + Vector2(-18, y), c + Vector2(18, y), col, 2.0)
			draw_string(UiKit.FONT_REGULAR, c + Vector2(24, y + 5), "%d" % roundi(float(mark[0]) / 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		return
	var gap := 6.0
	var arm := maxf(ppm * 15.0, 40.0)
	draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, 2.0)
	draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, 2.0)
	draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, arm * 0.6), col, 2.0)
	for m: float in TICK_MILS:
		var x := m * ppm
		if absf(x) < arm:
			draw_line(c + Vector2(x, -5), c + Vector2(x, 5), col, 1.5)
	if bool(_info.get("commander", false)):
		# Where the gun points against his line: an arrowhead at the top edge, by bearing.
		var rel := clampf(float(_info.get("gun_rel_deg", 0.0)) / 90.0, -1.0, 1.0)
		var at := Vector2(c.x + rel * size.x * 0.4, MARGIN + 52.0)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -10), at + Vector2(-8, 6), at + Vector2(8, 6)]), col)
