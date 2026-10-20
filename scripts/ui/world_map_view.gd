class_name WorldMapView
extends Control
## The theatre map (Captain, 2026-10-20: "a visual world map that shows boundaries and
## conflicts"; WorldMapScreen holds it): every zone of the region map (RegionMap) as a shaped
## area, neighbours sharing their borders (each cell's corners and edges are nudged by a fixed
## hash, so the land looks drawn rather than gridded, the same every time), the sea to the west
## with the LHD offshore, region borders and names with their travel days, the links and their
## crossings, each zone filled with its controller's colour (ZoneControl: the IFF palette, plus
## neutral grey and hatched contested), and the conflicts on it as badges (Theatre: hot zone,
## contracts held and offered, a skirmish now, the enemy's alert, fights of the last week, a
## flashpoint), the squad's zone ringed and home marked. Hovering a zone explains it (tooltip).
##
## Mouse: wheel zooms at the cursor, any drag pans, a click picks a zone, a double-click opens it
## (zone_picked). Keys: arrows (or the pad's d-pad / left stick) move between zones, WASD pans,
## + and - (or the pad's shoulders) zoom, F fits the whole map, Enter (pad A) opens. The pad's
## right stick pans.

## A zone was picked (click, arrows, pad): the info panel follows it.
signal zone_focused(zone_id: String)
## A zone was opened (double-click, Enter, pad A).
signal zone_picked(zone_id: String)
## Esc or the pad's B.
signal close_requested
## Tab or the pad's Y: back to the zone map.
signal back_requested

const FONT_NAME := UiKit.FONT_BODY
const FONT_BADGE := UiKit.FONT_SMALL
const FONT_REGION := UiKit.FONT_HEADING
## How far (cells) the grid's corners and its edges' midpoints wander, and into how many pieces
## each edge is broken.
const JITTER := 0.16
const WIGGLE := 0.06
const SEGMENTS := 4
## The sea's width west of the coast (cells), and the room kept around the land.
const SEA_W := 1.8
const MARGIN := Vector2(0.35, 0.75)
const ZOOM_STEP := 1.2
const MIN_ZOOM := 0.7  # of the fitted scale
const MAX_ZOOM := 5.0
const KEY_PAN_PX := 80.0
const PAD_PAN_PX_S := 700.0
const DRAG_PX := 5.0
const REFRESH_S := 2.0
const BACKDROP := Color(0.08, 0.09, 0.08)
const SEA := Color(0.09, 0.16, 0.23)
const SEA_TEXT := Color(0.45, 0.6, 0.72)
const LAND := Color(0.2, 0.21, 0.17)
const ZONE_EDGE := Color(0.03, 0.04, 0.03, 0.95)
const REGION_EDGE := Color(0.88, 0.84, 0.7)
const LINK := Color(0.92, 0.92, 0.86, 0.6)
const SQUAD := Color(0.45, 0.75, 1.0)
const HOT := Color(0.86, 0.22, 0.16)
## Badges, in the order they're drawn: their colour and what the legend calls them.
const BADGES := {
	"hot": {"colour": Color(0.86, 0.22, 0.16), "glyph": "HOT", "name": "Hot zone (several contracts at once, the enemy pushes back)"},
	"held": {"colour": UiKit.ACCENT, "glyph": "C", "name": "Contracts held there (count)"},
	"offered": {"colour": UiKit.ACCENT, "glyph": "o", "name": "Contracts offered there (count)"},
	"skirmish": {"colour": Color(0.95, 0.35, 0.3), "glyph": "X", "name": "A faction skirmish going on now"},
	"alert": {"colour": Color(0.95, 0.6, 0.2), "glyph": "!", "name": "The enemy's alert while you're there"},
	"recent": {"colour": Color(0.75, 0.55, 0.5), "glyph": "F", "name": "Fights there this week (count)"},
	"flashpoint": {"colour": Color(0.85, 0.7, 0.23), "glyph": "!!", "name": "Flashpoint: a faction just took it"},
}

var rows := {}  # zone id -> Theatre.zone row
var selected := ""
var hovered := ""
var scale_px := 100.0
var centre := Vector2.ZERO  # the world point (cells) at the view's middle
var _fit_scale := 100.0
var _fitted := true
var _polys := {}  # zone id -> PackedVector2Array (cells)
var _press := Vector2.ZERO
var _pressed := 0  # the mouse button held, 0 for none
var _moved := 0.0
var _refresh_left := 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(160, 120)
	tooltip_text = "Theatre map"  # (the zone under the cursor's, from _get_tooltip)
	resized.connect(func() -> void:
		if _fitted:
			fit()
		else:
			_clamp_view()
		queue_redraw())


func _ready() -> void:
	_build_shapes()
	refresh()
	fit()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_S
		refresh()
	if has_focus():
		var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if stick.length() > 0.25:
			pan(-stick * PAD_PAN_PX_S * delta)


## Reads every zone's row again (Theatre) and redraws.
func refresh() -> void:
	rows = Theatre.zones(self if is_inside_tree() else null)
	if selected == "" or not rows.has(selected):
		selected = Theatre.squad_zone()
	queue_redraw()


# --- Shapes (cells: x east, y south; the region grid's cell (x, y) spans x..x+1, y..y+1) -----

static func grid_size() -> Vector2i:
	var n := Vector2i.ZERO
	for cell: Vector2i in RegionMap.layout().values():
		n = Vector2i(maxi(n.x, cell.x + 1), maxi(n.y, cell.y + 1))
	return n


## The world (cells) the map shows: the sea west of the land, and a margin round it.
static func world_rect() -> Rect2:
	var n := grid_size()
	return Rect2(Vector2(-SEA_W, -MARGIN.y), Vector2(n.x + SEA_W + MARGIN.x, n.y + MARGIN.y * 1.6))


static func _noise(a: int, b: int, c: int) -> float:
	return float(hash(Vector3i(a, b, c)) & 0xffff) / 65535.0 - 0.5


## Grid corner (x, y), nudged (outer corners slide along the map's edge only).
static func _corner(x: int, y: int) -> Vector2:
	var n := grid_size()
	var j := Vector2(_noise(x, y, 1), _noise(x, y, 2)) * JITTER * 2.0
	if x == n.x:  # (the west edge is the shore: it wanders)
		j.x = 0.0
	if y == 0 or y == n.y:
		j.y = 0.0
	return Vector2(x, y) + j


## The border between corners `a` and `b`, wiggled the same way whichever side asks.
static func _edge(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	var flip := a.x > b.x or (a.x == b.x and a.y > b.y)
	var p := b if flip else a
	var q := a if flip else b
	var from := _corner(p.x, p.y)
	var to := _corner(q.x, q.y)
	var normal := (to - from).orthogonal().normalized()
	var out := PackedVector2Array([from])
	for i in range(1, SEGMENTS):
		out.append(from.lerp(to, float(i) / SEGMENTS) + normal * _noise(p.x * 7 + q.x, p.y * 7 + q.y, i + 10) * WIGGLE * 2.0)
	out.append(to)
	if flip:
		out.reverse()
	return out


## A grid cell's outline: its four edges, clockwise from the north-west corner.
static func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
	for i in 4:
		var e := _edge(corners[i], corners[(i + 1) % 4])
		e.remove_at(e.size() - 1)
		out.append_array(e)
	return out


## The shared border of grid cells `cell` and the one on its `side` (RegionMap.SIDE_STEP).
static func cell_side(cell: Vector2i, side: int) -> PackedVector2Array:
	var nw := cell
	var ne := cell + Vector2i(1, 0)
	var se := cell + Vector2i(1, 1)
	var sw := cell + Vector2i(0, 1)
	return [_edge(nw, ne), _edge(sw, se), _edge(nw, sw), _edge(ne, se)][side]


func _build_shapes() -> void:
	_polys.clear()
	for id: String in RegionMap.layout():
		_polys[id] = cell_polygon(RegionMap.layout()[id])


## A zone's middle (cells).
static func zone_centre(zone_id: String) -> Vector2:
	var cell: Vector2i = RegionMap.layout().get(zone_id, Vector2i.ZERO)
	return Vector2(cell) + Vector2(0.5, 0.5)


## Where the LHD sits: in the sea, level with the middle of the coast.
static func lhd_point() -> Vector2:
	var rows_coast := 0
	for id: String in RegionMap.layout():
		if String(ZoneControl._zone(id).get("region", "")) == "coast":
			rows_coast = maxi(rows_coast, (RegionMap.layout()[id] as Vector2i).y + 1)
	return Vector2(-SEA_W * 0.5, maxf(rows_coast, 1) * 0.5)


# --- View ---------------------------------------------------------------------------------

func to_screen(p: Vector2) -> Vector2:
	return (p - centre) * scale_px + size * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / scale_px + centre


## Shows the whole map.
func fit() -> void:
	var w := world_rect()
	var room := size.max(Vector2(1, 1))
	_fit_scale = maxf(minf(room.x / w.size.x, room.y / w.size.y), 1.0)
	scale_px = _fit_scale
	centre = w.get_center()
	_fitted = true
	queue_redraw()


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := to_world(screen_pos)
	scale_px = clampf(scale_px * factor, _fit_scale * MIN_ZOOM, _fit_scale * MAX_ZOOM)
	centre += before - to_world(screen_pos)
	_fitted = false
	_clamp_view()
	queue_redraw()


func pan(screen_delta: Vector2) -> void:
	centre -= screen_delta / scale_px
	_fitted = false
	_clamp_view()
	queue_redraw()


## The view's middle stays over the map.
func _clamp_view() -> void:
	var w := world_rect()
	centre = centre.clamp(w.position, w.end)


## The zone under `screen_pos`, or "".
func zone_at(screen_pos: Vector2) -> String:
	var p := to_world(screen_pos)
	for id: String in _polys:
		if Geometry2D.is_point_in_polygon(p, _polys[id]):
			return id
	return ""


## Picks zone `id` (as a click does) and brings it into view.
func select(id: String) -> void:
	if not RegionMap.layout().has(id):
		return
	selected = id
	var s := to_screen(zone_centre(id))
	if size.x > 1.0 and not Rect2(Vector2.ZERO, size).grow(-scale_px * 0.4).has_point(s):  # (not laid out yet: the fit shows it)
		centre = zone_centre(id)
		_fitted = false
		_clamp_view()
	queue_redraw()
	zone_focused.emit(id)


## The zone next to the selected one in direction `dir` (screen: +x east, +y south): the
## nearest whose middle lies that way, or "".
func neighbour(dir: Vector2) -> String:
	var from := zone_centre(selected if selected != "" else Theatre.squad_zone())
	var best := ""
	var best_cost := INF
	for id: String in RegionMap.layout():
		var d := zone_centre(id) - from
		var along := d.dot(dir)
		if along < 0.3:
			continue
		var cost := along + absf(d.dot(dir.orthogonal())) * 2.0
		if cost < best_cost:
			best_cost = cost
			best = id
	return best


func _get_tooltip(at_position: Vector2) -> String:
	if to_screen(lhd_point()).distance_to(at_position) <= 18.0:
		return "The LHD, offshore%s: helicopters, the AAVs and the landing craft come from her deck (coast supports)." % (
			" - HOME" if ZoneControl.home() == ZoneControl.HOME_LHD else "")
	var id := zone_at(at_position)
	if id == "" or not rows.has(id):
		return ""
	return Theatre.describe(rows[id])


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if not has_focus():
			grab_focus()
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_at(button.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_at(button.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if button.pressed and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
					var id := zone_at(button.position)
					if id != "":
						select(id)
						zone_picked.emit(id)
					_pressed = 0
				elif button.pressed:
					_pressed = button.button_index
					_press = button.position
					_moved = 0.0
				elif button.button_index == _pressed:
					_pressed = 0
					if button.button_index == MOUSE_BUTTON_LEFT and _moved < DRAG_PX:
						var id := zone_at(button.position)
						if id != "":
							select(id)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion:
		if _pressed != 0:
			_moved += motion.relative.length()
			if _moved >= DRAG_PX:
				pan(motion.relative)
		var over := zone_at(motion.position)
		if over != hovered:
			hovered = over
			queue_redraw()
		return
	if _keys(event):
		accept_event()


## Keyboard and pad. True when `event` was used.
func _keys(event: InputEvent) -> bool:
	if not event.is_pressed() or (event.is_echo() and not event is InputEventKey):  # (keys repeat)
		return false
	var key := event as InputEventKey
	if key and key.shift_pressed:
		for pair: Array in [[&"ui_left", Vector2(1, 0)], [&"ui_right", Vector2(-1, 0)], [&"ui_up", Vector2(0, 1)], [&"ui_down", Vector2(0, -1)]]:
			if event.is_action_pressed(pair[0], true):
				pan(pair[1] * KEY_PAN_PX)
				return true
	for pair: Array in [[&"ui_left", Vector2(-1, 0)], [&"ui_right", Vector2(1, 0)], [&"ui_up", Vector2(0, -1)], [&"ui_down", Vector2(0, 1)]]:
		if event.is_action_pressed(pair[0], true):
			var to := neighbour(pair[1])
			if to != "":
				select(to)
			return true
	if event.is_action_pressed(&"ui_accept"):
		if selected != "":
			zone_picked.emit(selected)
		return true
	if event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		return true
	if key:
		match key.physical_keycode:
			KEY_W: pan(Vector2(0, KEY_PAN_PX))
			KEY_S: pan(Vector2(0, -KEY_PAN_PX))
			KEY_A: pan(Vector2(KEY_PAN_PX, 0))
			KEY_D: pan(Vector2(-KEY_PAN_PX, 0))
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP: zoom_at(size * 0.5, ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN: zoom_at(size * 0.5, 1.0 / ZOOM_STEP)
			KEY_F, KEY_HOME: fit()
			KEY_TAB: back_requested.emit()
			_: return false
		return true
	var pad := event as InputEventJoypadButton
	if pad:
		match pad.button_index:
			JOY_BUTTON_RIGHT_SHOULDER: zoom_at(size * 0.5, ZOOM_STEP)
			JOY_BUTTON_LEFT_SHOULDER: zoom_at(size * 0.5, 1.0 / ZOOM_STEP)
			JOY_BUTTON_B: close_requested.emit()
			JOY_BUTTON_Y: back_requested.emit()
			JOY_BUTTON_RIGHT_STICK: fit()
			_: return false
		return true
	return false


# --- Drawing ------------------------------------------------------------------------------

func _poly_screen(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(to_screen(p))
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var layout := RegionMap.layout()
	if layout.is_empty():
		return
	var font := get_theme_default_font()
	_draw_sea(font)
	for id: String in _polys:
		var row: Dictionary = rows.get(id, {})
		var side := String(row.get("side", "neutral"))
		var poly := _poly_screen(_polys[id])
		var base_side := ZoneControl.side_of_faction(String(row.get("controller", ""))) if side == "contested" else side
		var fill: Color = LAND.lerp(ZoneControl.SIDE_COLOURS.get(base_side, ZoneControl.SIDE_COLOURS.neutral), 0.55)
		if id == hovered:
			fill = fill.lightened(0.12)
		draw_colored_polygon(poly, fill)
		if side == "contested":
			_hatch(poly, ZoneControl.SIDE_COLOURS.contested)
	for id: String in _polys:
		var poly := _poly_screen(_polys[id])
		poly.append(poly[0])
		draw_polyline(poly, ZONE_EDGE, 1.5, true)
		if String((rows.get(id, {}) as Dictionary).get("kind", "")) == "hot":
			var inner := _poly_screen(_inset(_polys[id], 0.06))
			inner.append(inner[0])
			draw_polyline(inner, Color(HOT, 0.85), 2.5, true)
	_draw_region_borders()
	_draw_links()
	for id: String in _polys:
		_draw_zone(id, font)
	_draw_homes(font)
	_draw_region_names(font)


func _draw_sea(font: Font) -> void:
	var n := grid_size()
	var sea := PackedVector2Array([to_screen(Vector2(-SEA_W - 1.0, -MARGIN.y - 1.0)), to_screen(Vector2(0, -MARGIN.y - 1.0))])
	var rows_coast := int(lhd_point().y * 2.0)
	for y in rows_coast:  # the shore: the coast's own west edges, so land and sea meet exactly
		var e := _edge(Vector2i(0, y), Vector2i(0, y + 1))
		e.remove_at(e.size() - 1)
		sea.append_array(_poly_screen(e))
	sea.append(to_screen(_corner(0, rows_coast)))
	sea.append_array(PackedVector2Array([to_screen(Vector2(0, n.y + MARGIN.y + 1.0)), to_screen(Vector2(-SEA_W - 1.0, n.y + MARGIN.y + 1.0))]))
	draw_colored_polygon(sea, SEA)
	_text_centred(font, to_screen(Vector2(-SEA_W * 0.5, maxf(lhd_point().y * 2.0, 1.0) + 0.45)), "SEA", FONT_BADGE, SEA_TEXT, scale_px * SEA_W)


## Thick light lines where a zone's neighbour is in another region, or there is none.
func _draw_region_borders() -> void:
	var layout := RegionMap.layout()
	for id: String in layout:
		var cell: Vector2i = layout[id]
		var region := String(ZoneControl._zone(id).get("region", RegionMap.BASE_REGION if id == RegionMap.BASE else ""))
		for side in 4:
			var other := RegionMap.zone_at(cell + RegionMap.SIDE_STEP[side])
			var other_region := String(ZoneControl._zone(other).get("region", RegionMap.BASE_REGION if other == RegionMap.BASE else ""))
			if other == "" or other_region != region:
				draw_polyline(_poly_screen(cell_side(cell, side)), REGION_EDGE, 3.0, true)


## The links between zones (dashed, middle to middle) and their crossings (a pip on the border).
func _draw_links() -> void:
	var layout := RegionMap.layout()
	for id: String in layout:
		for l: Dictionary in RegionMap.links(id):
			var to := String(l.to)
			if id > to:
				continue
			var border := cell_side(layout[id], int(l.side))
			var crossing := to_screen(border[border.size() / 2])
			draw_dashed_line(to_screen(zone_centre(id)), crossing, LINK, 2.0, 6.0)
			draw_dashed_line(crossing, to_screen(zone_centre(to)), LINK, 2.0, 6.0)
			draw_circle(crossing, 5.0, ZONE_EDGE)
			draw_circle(crossing, 3.5, LINK.lightened(0.3))


func _draw_zone(id: String, font: Font) -> void:
	var row: Dictionary = rows.get(id, {})
	var poly := _poly_screen(_polys[id])
	if bool(row.get("squad", false)):
		var ring := poly.duplicate()
		ring.append(poly[0])
		draw_polyline(ring, SQUAD, 5.0, true)
	if id == selected:
		var ring := poly.duplicate()
		ring.append(poly[0])
		draw_polyline(ring, Color.WHITE, 2.5, true)
	var c := to_screen(zone_centre(id))
	var width := scale_px * 0.92
	var lines := _name_lines(font, String(row.get("name", RegionMap.zone_name(id))), width)
	var y := c.y - (lines.size() - 1) * (FONT_NAME + 2) * 0.5 - 6.0
	for line in lines:
		_text_centred(font, Vector2(c.x, y), line, FONT_NAME, UiKit.TEXT, width)
		y += FONT_NAME + 2
	var badges := badges_of(row)
	if bool(row.get("squad", false)):
		_pill(font, Vector2(c.x, c.y - (lines.size() + 1) * (FONT_NAME + 2) * 0.5 - 12.0), "SQUAD", SQUAD)
	var bw := 26.0
	var x := c.x - (badges.size() - 1) * bw * 0.5
	for b: Array in badges:
		draw_badge(self, font, String(b[0]), Vector2(x, y + 8.0), String(b[1]))
		x += bw


## A zone row's badges: [[kind, count text ("" for none)]], in BADGES order.
static func badges_of(row: Dictionary) -> Array:
	var out: Array = []
	if String(row.get("kind", "")) == "hot":
		out.append(["hot", ""])
	if not (row.get("held", []) as Array).is_empty():
		out.append(["held", str((row.held as Array).size())])
	if not (row.get("offered", []) as Array).is_empty():
		out.append(["offered", str((row.offered as Array).size())])
	if String(row.get("skirmish", "")) != "":
		out.append(["skirmish", ""])
	if String(row.get("alert", "")) not in ["", "normal"]:
		out.append(["alert", String(row.alert).left(1).to_upper()])
	if not (row.get("recent", []) as Array).is_empty():
		out.append(["recent", str((row.recent as Array).size())])
	if bool(row.get("flashpoint", false)):
		out.append(["flashpoint", ""])
	return out


## Draws badge `kind` (BADGES) centred at `at` on `ci`, with `count` beside its glyph.
static func draw_badge(ci: CanvasItem, font: Font, kind: String, at: Vector2, count := "") -> void:
	var b: Dictionary = BADGES.get(kind, BADGES.hot)
	var colour: Color = b.colour
	var glyph := count if count != "" else String(b.glyph)
	if kind == "hot":
		var w := font.get_string_size("HOT", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE).x + 8.0
		ci.draw_rect(Rect2(at - Vector2(w * 0.5, 9), Vector2(w, 18)), colour)
		ci.draw_string(font, at + Vector2(-w * 0.5 + 4.0, 5), "HOT", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE, Color.WHITE)
		return
	if kind in ["held", "offered"]:
		var d := PackedVector2Array([at + Vector2(0, -11), at + Vector2(11, 0), at + Vector2(0, 11), at + Vector2(-11, 0)])
		if kind == "held":
			ci.draw_colored_polygon(d, colour)
		else:
			ci.draw_colored_polygon(d, Color(0.06, 0.06, 0.05, 0.9))
			d.append(d[0])
			ci.draw_polyline(d, colour, 2.0, true)
	else:
		ci.draw_circle(at, 10.0, Color(0.06, 0.06, 0.05, 0.92))
		ci.draw_arc(at, 10.0, 0.0, TAU, 20, colour, 2.0, true)
		if kind == "skirmish":
			ci.draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), colour, 2.5, true)
			ci.draw_line(at + Vector2(5, -5), at + Vector2(-5, 5), colour, 2.5, true)
			return
	var text_colour := Color(0.08, 0.06, 0.02) if kind == "held" else colour.lightened(0.2)
	var tw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE).x
	ci.draw_string(font, at + Vector2(-tw * 0.5, 5), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE, text_colour)


func _draw_homes(font: Font) -> void:
	var home := ZoneControl.home()
	# The LHD offshore: a hull and her island.
	var p := to_screen(lhd_point())
	var k := clampf(scale_px * 0.12, 6.0, 16.0)
	var hull := PackedVector2Array([p + Vector2(-3.2, -0.8) * k, p + Vector2(2.6, -0.8) * k, p + Vector2(3.4, 0) * k, p + Vector2(2.6, 0.8) * k,
		p + Vector2(-3.2, 0.8) * k])
	draw_colored_polygon(hull, Color(0.55, 0.58, 0.6))
	draw_rect(Rect2(p + Vector2(0.6, -1.4) * k, Vector2(1.0, 0.8) * k), Color(0.7, 0.72, 0.74))
	_text_centred(font, p + Vector2(0, 1.6 * k + FONT_BADGE), "LHD", FONT_BADGE, UiKit.TEXT, scale_px * SEA_W)
	if home == ZoneControl.HOME_LHD:
		_pill(font, p - Vector2(0, 1.6 * k + 12.0), "HOME", ZoneControl.SIDE_COLOURS.player)
	# The FOB: a star on the base zone.
	if RegionMap.layout().has(RegionMap.BASE):
		var c := to_screen(zone_centre(RegionMap.BASE)) + Vector2(0, -scale_px * 0.3)
		var star := PackedVector2Array()
		for i in 10:
			var r := 9.0 if i % 2 == 0 else 4.0
			star.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * r)
		draw_colored_polygon(star, ZoneControl.SIDE_COLOURS.player.lightened(0.35))
		if home == ZoneControl.HOME_FOB and scale_px > 60.0:
			_pill(font, c + Vector2(0, -20), "HOME", ZoneControl.SIDE_COLOURS.player)


## Each region's name over its block, with its travel days from home.
func _draw_region_names(font: Font) -> void:
	var spans := {}  # region -> Vector2(min x, max x)
	for id: String in RegionMap.layout():
		var region := String(ZoneControl._zone(id).get("region", RegionMap.BASE_REGION if id == RegionMap.BASE else ""))
		var x := float((RegionMap.layout()[id] as Vector2i).x)
		var span: Vector2 = spans.get(region, Vector2(x, x + 1.0))
		spans[region] = Vector2(minf(span.x, x), maxf(span.y, x + 1.0))
	for region: String in spans:
		var span: Vector2 = spans[region]
		var days := Theatre.travel_days(region)
		var text := "%s  -  %d day%s from home" % [Theatre.region_name(region).to_upper(), days, "" if days == 1 else "s"]
		var at := to_screen(Vector2((span.x + span.y) * 0.5, -0.38))
		_text_centred(font, at, text, FONT_REGION, REGION_EDGE, (span.y - span.x) * scale_px - 8.0)


## Diagonal hatching across `poly` (screen), for a contested zone.
func _hatch(poly: PackedVector2Array, colour: Color) -> void:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var step := 9.0
	var t := -box.size.y
	while t < box.size.x:
		var line := PackedVector2Array([box.position + Vector2(t, box.size.y), box.position + Vector2(t + box.size.y, 0)])
		for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, poly):
			draw_polyline(piece, Color(colour, 0.55), 2.0, true)
		t += step


## `poly` (cells) pulled in towards its middle by `by` cells.
static func _inset(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(poly, -by)
	return out[0] if not out.is_empty() else poly


## `text` in one or two lines no wider than `width` px, each cut with "..." if it must be.
static func _name_lines(font: Font, text: String, width: float) -> PackedStringArray:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_NAME).x <= width or not " " in text:
		return PackedStringArray([_cut(font, text, width, FONT_NAME)])
	var words := text.split(" ")
	var best := PackedStringArray([_cut(font, text, width, FONT_NAME)])
	var best_w := INF
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var w := maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_NAME).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_NAME).x)
		if w < best_w:
			best_w = w
			best = PackedStringArray([_cut(font, a, width, FONT_NAME), _cut(font, b, width, FONT_NAME)])
	return best


## `text` cut to `width` px with "..." (whole if it fits; "" if not even one letter does).
static func _cut(font: Font, text: String, width: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	for n in range(text.length() - 1, 0, -1):
		var t := text.left(n).strip_edges() + "..."
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return t
	return ""


## `text` centred on `at` (its baseline a little below), outlined dark, cut to `width`.
func _text_centred(font: Font, at: Vector2, text: String, font_size: int, colour: Color, width: float) -> void:
	var shown := _cut(font, text, maxf(width, 0.0), font_size)
	if shown == "":
		return
	var w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := at + Vector2(-w * 0.5, font_size * 0.35)
	draw_string_outline(font, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


## A small filled tag (SQUAD, HOME) centred on `at`.
func _pill(font: Font, at: Vector2, text: String, colour: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE).x + 10.0
	draw_rect(Rect2(at - Vector2(w * 0.5, 10), Vector2(w, 20)), colour)
	draw_string(font, at + Vector2(-w * 0.5 + 5.0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BADGE, Color.WHITE)
