class_name MapView
extends Control
## A top-down map of the current level's map_area(), north up, with an Arma-style grid:
## the picture (MapRender), the grid with its numbers along the edges, objectives,
## extraction points, the briefing's insertion candidates, the shared markers and lines
## (MapMarkers), dead players' gear markers, and your own and your squad's positions. No
## enemy positions except those known from intel or reported (markers).
##
## Mouse: wheel zooms at the cursor, right or middle drag pans, double-click places a marker
## (type its text, Enter), Ctrl + left drag draws a line, left drag moves a marker, Delete
## removes the one under the cursor, right click opens a menu (marker, enemy, extraction
## point here). The grid reference under the cursor is `cursor_reference()`. Works the same
## for a 44 m test level and a 2 km zone: zoom runs from the whole area to MAX_PX_PER_M.
##
## Objectives come from any node in OBJECTIVE_GROUP with map_objectives() -> Array of
## {"id", "title", "pos": Vector2 (x, z), "radius" (m), "state" ("open", "done", "failed")},
## on every peer (the economy's objective tracker implements it; the Briefing does for the
## contract's objectives until then).

signal cursor_moved(reference: String)

const OBJECTIVE_GROUP := &"map_objectives"
const MAX_PX_PER_M := 24.0
const ZOOM_STEP := 1.25
## The furthest out you can zoom, as a share of the zoom that fits the whole area.
const MIN_FIT_SHARE := 0.6
## How far past the area's edge (as a share of its size) the view can pan.
const PAN_MARGIN := 0.25
const HOVER_PX := 10.0
const LINE_STEP_PX := 8.0
const OBJECTIVE_COLOURS := {"open": Color(1.0, 0.85, 0.2), "done": Color(0.35, 0.85, 0.35), "failed": Color(0.9, 0.3, 0.25)}
const EXTRACT_COLOUR := Color(0.62, 0.36, 0.85)
const INSERT_COLOUR := Color(0.3, 0.9, 0.45)
const SQUAD_COLOUR := Color(0.35, 0.6, 1.0)
const SELF_COLOUR := Color(0.2, 1.0, 1.0)
const GEAR_COLOUR := Color("ffd166")
const GRID_MINOR := Color(0, 0, 0, 0.22)
const GRID_MAJOR := Color(0, 0, 0, 0.5)
const BACKDROP := Color(0.12, 0.13, 0.12)

## The level shown (anything with map_area()).
var level: Node
var area := Rect2()
## The map point (x, z) at the middle of the view, and the scale in pixels per metre.
var centre := Vector2.ZERO
var zoom := 1.0
## What a new marker looks like (MapScreen's toolbar sets these).
var marker_colour := "black"
var marker_kind := "point"
## "field" in play, "plan" during the briefing.
var marker_channel := "field"

var _texture: Texture2D
var _cursor := Vector2.ZERO
var _cursor_screen := Vector2.ZERO
var _hover_id := 0
var _drag_id := 0
var _drag_to := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _pan_button := 0
var _pan_moved := 0.0
var _line := PackedVector2Array()
var _text: LineEdit
var _text_at := Vector2.ZERO
var _menu: PopupMenu
var _menu_at := Vector2.ZERO
var _fitted := false  # showing the whole area (fit), until zoomed or panned


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_text = LineEdit.new()
	_text.visible = false
	_text.custom_minimum_size = Vector2(200, 0)
	_text.placeholder_text = "Marker text, Enter"
	_text.text_submitted.connect(_on_text_submitted)
	_text.focus_exited.connect(func() -> void: _text.visible = false)
	add_child(_text)
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	resized.connect(func() -> void:
		if _fitted:
			fit()  # still showing the whole area: keep doing so at the new size
		else:
			_clamp_view())


## Shows `p_level` (anything with map_area()), zoomed to fit. The picture is made on first use.
func setup(p_level: Node) -> void:
	level = p_level
	area = p_level.call(&"map_area") if p_level else Rect2()
	_texture = null
	fit()


## The picture under the grid (made on first use).
func texture() -> Texture2D:
	if _texture == null and level:
		_texture = ImageTexture.create_from_image(MapRender.render(level))
	return _texture


## The size used for view maths: the control's, or a stand-in before it's laid out.
func view_size() -> Vector2:
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(1600, 900)


## Zoom that shows the whole area.
func fit_zoom() -> float:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return 1.0
	var v := view_size()
	return minf(v.x / area.size.x, v.y / area.size.y) * 0.92


func min_zoom() -> float:
	return minf(fit_zoom() * MIN_FIT_SHARE, MAX_PX_PER_M)


func fit() -> void:
	zoom = fit_zoom()
	centre = area.get_center()
	_fitted = true
	queue_redraw()


func map_to_screen(p: Vector2) -> Vector2:
	return view_size() * 0.5 + (p - centre) * zoom


func screen_to_map(s: Vector2) -> Vector2:
	return centre + (s - view_size() * 0.5) / zoom


## Zooms by `factor`, keeping the map point under `screen_pos` where it is.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_map(screen_pos)
	zoom = clampf(zoom * factor, min_zoom(), MAX_PX_PER_M)
	centre += before - screen_to_map(screen_pos)
	_clamp_view()


## Moves the view by a screen distance (dragging the map).
func pan(screen_delta: Vector2) -> void:
	centre -= screen_delta / zoom
	_clamp_view()


## Centres the view on a map point.
func look_at_point(p: Vector2) -> void:
	centre = p
	_clamp_view()


## The map point the view may be centred on: inside the area plus a margin.
func _clamp_view() -> void:
	_fitted = false
	var r := area.grow_individual(area.size.x * PAN_MARGIN, area.size.y * PAN_MARGIN, area.size.x * PAN_MARGIN, area.size.y * PAN_MARGIN)
	centre = centre.clamp(r.position, r.end)
	queue_redraw()


## The map rectangle (x, z) the view shows now.
func visible_rect() -> Rect2:
	var a := screen_to_map(Vector2.ZERO)
	return Rect2(a, view_size() / zoom)


## Grid line spacing at this zoom (1, 10, 100 or 1000 m).
func grid_spacing() -> float:
	return MapGrid.line_spacing(zoom)


## The grid reference at a screen point: 4 digits per axis (10 m) when zoomed in far enough
## to tell 10 m squares apart, else 3 (100 m).
func reference_at(screen_pos: Vector2) -> String:
	var digits := MapGrid.FINE_DIGITS if zoom * 10.0 >= 6.0 else MapGrid.COARSE_DIGITS
	return MapGrid.grid_ref(screen_to_map(screen_pos), area, digits)


func cursor_reference() -> String:
	return reference_at(_cursor_screen)


## Every objective the map shows now (see the class doc).
static func objectives_in(from: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if from == null or not from.is_inside_tree():
		return out
	for node in from.get_tree().get_nodes_in_group(OBJECTIVE_GROUP):
		if node.has_method(&"map_objectives"):
			for o: Dictionary in node.call(&"map_objectives"):
				out.append(o)
	return out


# --- Markers ---------------------------------------------------------------------

## Places a marker at a map point with the current kind and colour (through the host).
func place_marker(at: Vector2, text: String, kind := "") -> void:
	var markers := MapNodes.markers(self)
	if markers:
		var k := kind if kind != "" else marker_kind
		markers.request_add(k, PackedVector2Array([at]), text, "red" if k == "enemy" else marker_colour, marker_channel)


## The marker under a screen point (0 if none).
func marker_at(screen_pos: Vector2) -> int:
	var markers := MapNodes.markers(self)
	if markers == null:
		return 0
	var best := 0
	var best_d := HOVER_PX
	for marker: Dictionary in markers.list():
		var points: PackedVector2Array = marker.points
		var d := INF
		if points.size() == 1:
			d = map_to_screen(points[0]).distance_to(screen_pos)
		else:
			for i in points.size() - 1:
				var c := Geometry2D.get_closest_point_to_segment(screen_pos, map_to_screen(points[i]), map_to_screen(points[i + 1]))
				d = minf(d, c.distance_to(screen_pos))
		if d <= best_d:
			best_d = d
			best = int(marker.id)
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _hover_id != 0:
			MapNodes.markers(self).request_remove(_hover_id)
			_hover_id = 0
			accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	_cursor_screen = event.position
	_cursor = screen_to_map(event.position)
	cursor_moved.emit(cursor_reference())
	if _pan_button != 0:
		_pan_moved += event.relative.length()
		pan(event.relative)
	elif _drag_id != 0:
		_drag_to = _cursor
	elif not _line.is_empty():
		if map_to_screen(_line[-1]).distance_to(event.position) >= LINE_STEP_PX:
			_line.append(_cursor)
	else:
		_hover_id = marker_at(event.position)
	queue_redraw()


func _on_button(event: InputEventMouseButton) -> void:
	grab_focus()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_at(event.position, ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_at(event.position, 1.0 / ZOOM_STEP)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_pan_button = event.button_index
				_pan_moved = 0.0
			elif event.button_index == _pan_button:
				_pan_button = 0
				if event.button_index == MOUSE_BUTTON_RIGHT and _pan_moved < 4.0:
					_open_menu(event.position)
		MOUSE_BUTTON_LEFT:
			if event.pressed and event.double_click:
				_line = PackedVector2Array()
				_drag_id = 0
				_ask_text(event.position)
			elif event.pressed and event.ctrl_pressed:
				_line = PackedVector2Array([screen_to_map(event.position)])
			elif event.pressed:
				_drag_id = marker_at(event.position)
				_drag_to = screen_to_map(event.position)
				_drag_start = _drag_to
				if _drag_id == 0:
					_pick_insertion(event.position)
			else:
				_finish_left()
	accept_event()
	queue_redraw()


func _finish_left() -> void:
	var markers := MapNodes.markers(self)
	if _line.size() >= 2 and markers:
		markers.request_add("line", _line, "", marker_colour, marker_channel)
	elif _drag_id != 0 and markers and markers.markers.has(_drag_id):
		var first: Vector2 = (markers.markers[_drag_id].points as PackedVector2Array)[0]
		if map_to_screen(first).distance_to(map_to_screen(_drag_to)) > 3.0:
			# Lines move by how far they were dragged; points go where they're dropped.
			var grab := _drag_grab(markers.markers[_drag_id])
			markers.request_move(_drag_id, first + (_drag_to - grab))
	_line = PackedVector2Array()
	_drag_id = 0


## Where a marker was picked up (its nearest point to the cursor when the drag started).
func _drag_grab(marker: Dictionary) -> Vector2:
	var points: PackedVector2Array = marker.points
	return points[0] if points.size() == 1 else _drag_start


func _ask_text(screen_pos: Vector2) -> void:
	_text_at = screen_to_map(screen_pos)
	_text.text = ""
	_text.position = (screen_pos + Vector2(10, -14)).clamp(Vector2.ZERO, view_size() - Vector2(210, 32))
	_text.visible = true
	_text.grab_focus()


func _on_text_submitted(text: String) -> void:
	_text.visible = false
	place_marker(_text_at, text)
	grab_focus()


func _open_menu(screen_pos: Vector2) -> void:
	_menu_at = screen_to_map(screen_pos)
	_menu.clear()
	_menu.add_item("Marker here", 0)
	_menu.add_item("Enemy here", 1)
	var extraction := MapNodes.extraction(self)
	if extraction and extraction.is_active():
		_menu.add_item("Extraction point here (%s)" % MapGrid.grid_ref(_menu_at, area), 2)
	if marker_at(screen_pos) != 0:
		_hover_id = marker_at(screen_pos)
		_menu.add_item("Delete marker", 3)
	_menu.position = Vector2i(get_screen_position() + screen_pos)
	_menu.reset_size()
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		0:
			_text_at = _menu_at
			_ask_text(map_to_screen(_menu_at))
		1:
			place_marker(_menu_at, "", "enemy")
		2:
			MapNodes.extraction(self).request_point_at(_menu_at)
		3:
			if _hover_id != 0:
				MapNodes.markers(self).request_remove(_hover_id)


## During the briefing, clicking an insertion candidate picks it.
func _pick_insertion(screen_pos: Vector2) -> void:
	var briefing := MapNodes.briefing(self)
	if briefing == null or not briefing.is_open():
		return
	for point: Dictionary in briefing.insertion_points():
		var p: Array = point.get("pos", [])
		if p.size() >= 2 and map_to_screen(Vector2(float(p[0]), float(p[1]))).distance_to(screen_pos) <= HOVER_PX * 1.5:
			briefing.request_insertion(String(point.get("id", "")))
			return


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()  # soldiers move


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	if area.size.x <= 0.0:
		return
	var tex := texture()
	var map_rect := Rect2(map_to_screen(area.position), area.size * zoom)
	if tex:
		draw_texture_rect(tex, map_rect, false)
	_draw_grid()
	draw_rect(map_rect, Color.BLACK, false, 2.0)
	_draw_objectives()
	_draw_insertion()
	_draw_extraction()
	_draw_markers()
	_draw_gear_markers()
	_draw_squad()
	if _line.size() >= 2:
		_polyline(_line, MapMarkers.colour_value(marker_colour), 2.0)


func _draw_grid() -> void:
	var spacing := grid_spacing()
	var shown := visible_rect().intersection(area)
	if shown.size.x <= 0.0 or shown.size.y <= 0.0:
		return
	var font := get_theme_default_font()
	var top := maxf(map_to_screen(area.position).y, 0.0)
	var left := maxf(map_to_screen(area.position).x, 0.0)
	# Eastings: vertical lines from the west edge.
	var e0 := floori((shown.position.x - area.position.x) / spacing)
	var e1 := ceili((shown.end.x - area.position.x) / spacing)
	for i in range(e0, e1 + 1):
		var x := area.position.x + i * spacing
		if x < area.position.x or x > area.end.x:
			continue
		var a := map_to_screen(Vector2(x, maxf(shown.position.y, area.position.y)))
		var b := map_to_screen(Vector2(x, minf(shown.end.y, area.end.y)))
		var major := i % 10 == 0
		draw_line(a, b, GRID_MAJOR if major else GRID_MINOR, 2.0 if major else 1.0)
		if x < area.end.x:
			draw_string(font, Vector2(a.x + 3, top + 14), MapGrid.line_label(i, spacing), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
	# Northings: horizontal lines from the south edge.
	var n0 := floori((area.end.y - shown.end.y) / spacing)
	var n1 := ceili((area.end.y - shown.position.y) / spacing)
	for j in range(n0, n1 + 1):
		var z := area.end.y - j * spacing
		if z < area.position.y or z > area.end.y:
			continue
		var a := map_to_screen(Vector2(maxf(shown.position.x, area.position.x), z))
		var b := map_to_screen(Vector2(minf(shown.end.x, area.end.x), z))
		var major := j % 10 == 0
		draw_line(a, b, GRID_MAJOR if major else GRID_MINOR, 2.0 if major else 1.0)
		if z > area.position.y:
			draw_string(font, Vector2(left + 3, a.y - 3), MapGrid.line_label(j, spacing), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)


func _draw_objectives() -> void:
	for o: Dictionary in objectives_in(self):
		var at: Vector2 = o.get("pos", Vector2.ZERO)
		var s := map_to_screen(at)
		var colour: Color = OBJECTIVE_COLOURS.get(String(o.get("state", "open")), OBJECTIVE_COLOURS["open"])
		var r := maxf(float(o.get("radius", 0.0)) * zoom, 8.0)
		draw_arc(s, r, 0.0, TAU, 48, colour, 2.0)
		draw_circle(s, 4.0, colour)
		_label(s + Vector2(8, -6), String(o.get("title", "Objective")), colour)


func _draw_insertion() -> void:
	var briefing := MapNodes.briefing(self)
	if briefing == null or briefing.phase == Briefing.Phase.IDLE:
		return
	for point: Dictionary in briefing.insertion_points():
		var p: Array = point.get("pos", [])
		if p.size() < 2:
			continue
		var chosen := String(point.get("id", "")) == briefing.insertion_id
		if briefing.is_deployed() and not chosen:
			continue
		var s := map_to_screen(Vector2(float(p[0]), float(p[1])))
		var tri := PackedVector2Array([s + Vector2(0, -9), s + Vector2(8, 6), s + Vector2(-8, 6)])
		if chosen:
			draw_colored_polygon(tri, INSERT_COLOUR)
		tri.append(tri[0])
		draw_polyline(tri, INSERT_COLOUR.darkened(0.4), 2.0)
		_label(s + Vector2(11, 4), ("INSERT: " if chosen else "") + String(point.get("name", "")), INSERT_COLOUR)


func _draw_extraction() -> void:
	var extraction := MapNodes.extraction(self)
	if extraction == null or not extraction.is_active():
		return
	for point: Dictionary in extraction.points:
		var s := map_to_screen(point.pos)
		var counting := extraction.state == Extraction.State.COUNTDOWN and int(point.id) == extraction.countdown_point
		draw_arc(s, maxf(float(point.radius) * zoom, 10.0), 0.0, TAU, 48, EXTRACT_COLOUR, 4.0 if counting else 2.0)
		draw_line(s + Vector2(-6, -6), s + Vector2(6, 6), EXTRACT_COLOUR, 2.0)
		draw_line(s + Vector2(-6, 6), s + Vector2(6, -6), EXTRACT_COLOUR, 2.0)
		_label(s + Vector2(9, -8), "EXTRACT: %s" % point.name, EXTRACT_COLOUR)


func _draw_markers() -> void:
	var markers := MapNodes.markers(self)
	if markers == null:
		return
	for marker: Dictionary in markers.list():
		var points: PackedVector2Array = marker.points
		if int(marker.id) == _drag_id:
			var shift := _drag_to - _drag_grab(marker)
			var moved := PackedVector2Array()
			for p in points:
				moved.append(p + shift)
			points = moved
		var colour := MapMarkers.colour_value(String(marker.colour))
		var hover := int(marker.id) == _hover_id
		if marker.kind == "line":
			_polyline(points, colour, 3.0 if hover else 2.0)
			continue
		var s := map_to_screen(points[0])
		if marker.kind == "enemy":
			var d := 7.0 if not hover else 9.0
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)]), colour)
		else:
			draw_circle(s, 6.0 if hover else 5.0, colour)
			draw_arc(s, 6.0 if hover else 5.0, 0.0, TAU, 16, Color.WHITE if hover else Color(0, 0, 0, 0.6), 1.0)
		if String(marker.text) != "":
			_label(s + Vector2(9, 4), String(marker.text), colour)


## Dead players' gear on the map (their bodies with a GearMarker): [{"pos": Vector2, "text"}].
static func gear_points(from: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in from.get_tree().get_nodes_in_group(GearMarker.GROUP):
		var marker := node as GearMarker
		var body := marker.body() if marker else null
		if body and not marker.is_queued_for_deletion():
			out.append({"pos": Vector2(body.global_position.x, body.global_position.z), "text": marker.text})
	return out


## The soldiers the map shows: the players and the friendly AI squad, never enemies.
## [{"pos": Vector2, "dir": Vector2 (facing, on the map), "text", "kind" ("self", "player" or
## "squad"), "up" (not down)}].
static func soldier_points(from: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := MapNodes.local_player(from)
	for s: Soldier in MapNodes.squad_ai(from) + MapNodes.players(from):
		var forward := -s.global_basis.z
		var dir := Vector2(forward.x, forward.z).normalized()
		var kind := "squad" if s.is_ai() else ("self" if s == me else "player")
		out.append({"pos": Vector2(s.global_position.x, s.global_position.z), "dir": dir if dir != Vector2.ZERO else Vector2.UP,
			"text": {"self": "You", "player": "Player %s" % s.name}.get(kind, String(s.name)), "kind": kind, "up": s.vitals.is_up()})
	return out


func _draw_gear_markers() -> void:
	for gear: Dictionary in gear_points(self):
		var s := map_to_screen(gear.pos)
		draw_line(s + Vector2(-5, -5), s + Vector2(5, 5), GEAR_COLOUR, 3.0)
		draw_line(s + Vector2(-5, 5), s + Vector2(5, -5), GEAR_COLOUR, 3.0)
		_label(s + Vector2(8, -6), gear.text, GEAR_COLOUR)


func _draw_squad() -> void:
	for point: Dictionary in soldier_points(self):
		var s := map_to_screen(point.pos)
		if point.kind == "squad":
			draw_circle(s, 4.0, SQUAD_COLOUR if point.up else SQUAD_COLOUR.darkened(0.5))
			_label(s + Vector2(6, 4), point.text, SQUAD_COLOUR, 11)
			continue
		var dir: Vector2 = point.dir
		var side := dir.orthogonal()
		var colour := SELF_COLOUR if point.kind == "self" else SQUAD_COLOUR.lightened(0.3)
		draw_colored_polygon(PackedVector2Array([s + dir * 10.0, s - dir * 6.0 + side * 6.0, s - dir * 3.0, s - dir * 6.0 - side * 6.0]), colour)
		_label(s + Vector2(9, 4), point.text, colour, 12)


func _polyline(points: PackedVector2Array, colour: Color, width: float) -> void:
	var screen := PackedVector2Array()
	for p in points:
		screen.append(map_to_screen(p))
	if screen.size() >= 2:
		draw_polyline(screen, colour, width, true)


func _label(at: Vector2, text: String, colour: Color, font_size := 13) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.75))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
