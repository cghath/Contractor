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
## How much of the view the whole area fills when fitted (Captain, 2026-10-14: the map sat
## small in the middle of a lot of empty space; what's around it is now drawn too).
const FIT_SHARE := 0.97
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
## Labels (Captain, 2026-10-14, B0912: labels at one spot were drawn over each other and over
## other symbols). Every label is queued while drawing and laid out last (_layout_labels): beside
## its symbol where there's room, else stacked off it with a leader line, never over another
## label or symbol and always inside the map; one wider than LABEL_MAX_PX is cut short with "..."
## and shows whole while the cursor is on it or its symbol.
const LABEL_MAX_PX := 230.0
const LABEL_GAP_PX := 8.0
const SYMBOL_PX := 9.0  # half the box a symbol keeps clear of labels
## What a label's symbol is, most important first: which keeps the best spot.
const LABEL_PRIORITY := {"self": 9, "objective": 8, "insert_chosen": 7, "extract": 6, "intel": 5, "marker": 4, "insert": 3, "player": 3, "gear": 2, "squad": 1}

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
## The zone picture being made on a worker thread (-1: none).
var _render_task := -1
var _render_inputs := {}
var _render_image: Image
var _surround := {}
## This frame's labels and symbol boxes (queued while drawing), and where the last draw put
## each label: [{"rect": Rect2, "text" (as shown), "full", "anchor": Vector2, "leader": bool}].
var _labels: Array[Dictionary] = []
var _symbols: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []


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
	_surround = MapRender.surround(p_level) if p_level else {}
	fit()


## The level's cached map picture (made once per level; Captain, 2026-10-14: never per frame).
const IMAGE_META := &"map_render_image"


## The picture under the grid (made on first use and kept on the level). A zone's is made on
## a worker thread: null until it's ready (texture_pending()); `wait` makes it here instead.
func texture(wait := false) -> Texture2D:
	if _texture != null or level == null:
		return _texture
	if level.has_meta(IMAGE_META):
		_texture = ImageTexture.create_from_image(level.get_meta(IMAGE_META))
		return _texture
	if not MapRender.is_zone(level) or wait:
		if _render_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_render_task)
			_render_task = -1
		var image := _render_image if _render_image else MapRender.render(level)
		_render_image = null
		level.set_meta(IMAGE_META, image)
		_texture = ImageTexture.create_from_image(image)
		return _texture
	if _render_task < 0:
		_render_inputs = MapRender.zone_inputs(level)
		_render_image = null
		_render_task = WorkerThreadPool.add_task(func() -> void: _render_image = MapRender.compose_zone(_render_inputs), false, "map render")
	elif WorkerThreadPool.is_task_completed(_render_task):
		WorkerThreadPool.wait_for_task_completion(_render_task)
		_render_task = -1
		_render_inputs = {}
		if _render_image:
			level.set_meta(IMAGE_META, _render_image)
			_texture = ImageTexture.create_from_image(_render_image)
			_render_image = null
	return _texture


## Whether the picture is still being made.
func texture_pending() -> bool:
	return _render_task >= 0


func _exit_tree() -> void:
	if _render_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_render_task)
		_render_task = -1


## The size used for view maths: the control's, or a stand-in before it's laid out.
func view_size() -> Vector2:
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(1600, 900)


## Zoom that shows the whole area.
func fit_zoom() -> float:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return 1.0
	var v := view_size()
	return minf(v.x / area.size.x, v.y / area.size.y) * FIT_SHARE


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
	_labels.clear()
	_symbols.clear()
	var map_rect := Rect2(map_to_screen(area.position), area.size * zoom)
	_draw_surround(map_rect)
	if area.size.x <= 0.0:
		return
	var tex := texture()
	if tex:
		draw_texture_rect(tex, map_rect, false)
	else:
		draw_rect(map_rect, MapRender.GROUND)
		_label_raw(map_rect.get_center() - Vector2(40, 0), "Drawing the map...", Color(1, 1, 1, 0.7), 14)
	_draw_grid()
	draw_rect(map_rect, Color(0, 0, 0, 0.8), false, 2.0)
	_draw_objectives()
	_draw_insertion()
	_draw_extraction()
	_draw_markers()
	_draw_gear_markers()
	_draw_squad()
	if _line.size() >= 2:
		_polyline(_line, MapMarkers.colour_value(marker_colour), 2.0)
	_layout_labels(map_rect)


## Around the map: the ground past a zone's edge (and the sea past its coast), dimmed, so the
## view is never a small square in a lot of empty space.
func _draw_surround(map_rect: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _surround.get("ground", BACKDROP))
	var side := int(_surround.get("sea_side", -1))
	if side >= 0:
		var v := Rect2(Vector2.ZERO, size)
		var sea: Rect2 = [Rect2(v.position, Vector2(v.size.x, map_rect.position.y)), Rect2(Vector2(0, map_rect.end.y), Vector2(v.size.x, v.size.y - map_rect.end.y)),
			Rect2(v.position, Vector2(map_rect.position.x, v.size.y)), Rect2(Vector2(map_rect.end.x, 0), Vector2(v.size.x - map_rect.end.x, v.size.y))][side]
		if sea.size.x > 0.0 and sea.size.y > 0.0:
			draw_rect(sea, _surround.get("sea", BACKDROP))


func _draw_grid() -> void:
	var spacing := grid_spacing()
	var shown := visible_rect().intersection(area)
	if shown.size.x <= 0.0 or shown.size.y <= 0.0:
		return
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
		if x < area.end.x and a.x + 3 > left + 28:  # clear of the northings' column
			_grid_label(Vector2(a.x + 3, top + 14), MapGrid.line_label(i, spacing))
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
		if z > area.position.y and a.y - 3 > top + 30:  # clear of the eastings' row
			_grid_label(Vector2(left + 3, a.y - 3), MapGrid.line_label(j, spacing))


## A grid number: dark on a light halo, readable on any ground.
func _grid_label(at: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(1, 1, 1, 0.45))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.9))


func _draw_objectives() -> void:
	for o: Dictionary in objectives_in(self):
		var at: Vector2 = o.get("pos", Vector2.ZERO)
		var s := map_to_screen(at)
		var colour: Color = OBJECTIVE_COLOURS.get(String(o.get("state", "open")), OBJECTIVE_COLOURS["open"])
		var r := maxf(float(o.get("radius", 0.0)) * zoom, 8.0)
		draw_arc(s, r, 0.0, TAU, 48, colour, 2.0)
		draw_circle(s, 4.0, colour)
		_label(s, String(o.get("title", "Objective")), colour, "objective")


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
		_label(s, ("INSERT: " if chosen else "") + String(point.get("name", "")), INSERT_COLOUR, "insert_chosen" if chosen else "insert")


func _draw_extraction() -> void:
	var extraction := MapNodes.extraction(self)
	if extraction == null or not extraction.is_active():
		return
	for point: Dictionary in extraction.shown_points():  # a helicopter extraction: its LZ only
		var s := map_to_screen(point.pos)
		var counting := extraction.state == Extraction.State.COUNTDOWN and int(point.id) == extraction.countdown_point
		draw_arc(s, maxf(float(point.radius) * zoom, 10.0), 0.0, TAU, 48, EXTRACT_COLOUR, 4.0 if counting else 2.0)
		draw_line(s + Vector2(-6, -6), s + Vector2(6, 6), EXTRACT_COLOUR, 2.0)
		draw_line(s + Vector2(-6, 6), s + Vector2(6, -6), EXTRACT_COLOUR, 2.0)
		_label(s, "EXTRACT: %s" % point.name, EXTRACT_COLOUR, "extract")


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
		_symbol(s)
		if marker.kind == "enemy":
			var d := 7.0 if not hover else 9.0
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)]), colour)
		else:
			draw_circle(s, 6.0 if hover else 5.0, colour)
			draw_arc(s, 6.0 if hover else 5.0, 0.0, TAU, 16, Color.WHITE if hover else Color(0, 0, 0, 0.6), 1.0)
		if String(marker.text) != "":
			_label(s, String(marker.text), colour, "intel" if marker.channel == "intel" else "marker")


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
		_label(s, gear.text, GEAR_COLOUR, "gear")


func _draw_squad() -> void:
	for point: Dictionary in soldier_points(self):
		var s := map_to_screen(point.pos)
		if point.kind == "squad":
			draw_circle(s, 4.0, SQUAD_COLOUR if point.up else SQUAD_COLOUR.darkened(0.5))
			_label(s, point.text, SQUAD_COLOUR, "squad", 11)
			continue
		var dir: Vector2 = point.dir
		var side := dir.orthogonal()
		var colour := SELF_COLOUR if point.kind == "self" else SQUAD_COLOUR.lightened(0.3)
		draw_colored_polygon(PackedVector2Array([s + dir * 10.0, s - dir * 6.0 + side * 6.0, s - dir * 3.0, s - dir * 6.0 - side * 6.0]), colour)
		_label(s, point.text, colour, String(point.kind), 12)


func _polyline(points: PackedVector2Array, colour: Color, width: float) -> void:
	var screen := PackedVector2Array()
	for p in points:
		screen.append(map_to_screen(p))
	if screen.size() >= 2:
		draw_polyline(screen, colour, width, true)


## Queues a label for the symbol at `anchor` (screen); `kind` is a LABEL_PRIORITY key. Laid
## out and drawn at the end of the frame (_layout_labels).
func _label(anchor: Vector2, text: String, colour: Color, kind := "marker", font_size := 13) -> void:
	_symbol(anchor)
	if text != "":
		_labels.append({"anchor": anchor, "text": text, "colour": colour, "size": font_size,
			"prio": int(LABEL_PRIORITY.get(kind, 0)), "order": _labels.size()})


## A symbol's box, kept clear of labels.
func _symbol(at: Vector2) -> void:
	_symbols.append(Rect2(at - Vector2(SYMBOL_PX, SYMBOL_PX), Vector2(SYMBOL_PX, SYMBOL_PX) * 2.0))


func _label_raw(at: Vector2, text: String, colour: Color, font_size := 13) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.75))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


## `text` cut to fit `max_px` with "..." (whole if it fits).
func _fit_text(text: String, font_size: int, max_px: float) -> String:
	var font := get_theme_default_font()
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_px:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if font.get_string_size(text.left(mid).strip_edges() + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_px:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges() + "..."


## Places this frame's labels, most important first: beside the symbol (right, left, above,
## below) where that's clear of every other label and symbol and inside the map; else off it
## in a stack below or above with a leader line; never outside the visible map.
func _layout_labels(map_rect: Rect2) -> void:
	drawn_labels.clear()
	var bounds := map_rect.intersection(Rect2(Vector2.ZERO, size)).grow(-2.0)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var font := get_theme_default_font()
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.prio > b.prio or (a.prio == b.prio and a.order < b.order))
	var taken: Array[Rect2] = []
	var hovered: Dictionary = {}
	for lab: Dictionary in _labels:
		var font_size: int = lab.size
		var shown := _fit_text(lab.text, font_size, minf(LABEL_MAX_PX, bounds.size.x - 4.0))
		var box := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(4, 2)
		var a: Vector2 = lab.anchor
		var g := LABEL_GAP_PX
		var spots: Array[Vector2] = [a + Vector2(g, -box.y * 0.5), a + Vector2(-g - box.x, -box.y * 0.5),
			a + Vector2(-box.x * 0.5, -g - box.y), a + Vector2(-box.x * 0.5, g), a + Vector2(g, -g - box.y), a + Vector2(g, g)]
		for k in range(1, 9):  # off the symbol, with a leader line
			spots.append(a + Vector2(g + 6.0, g + k * (box.y + 2.0)))
			spots.append(a + Vector2(g + 6.0, -g - box.y - k * (box.y + 2.0)))
			spots.append(a + Vector2(-g - 6.0 - box.x, g + k * (box.y + 2.0)))
		var placed := Rect2()
		var found := false
		for spot in spots:
			var r := _clamp_rect(Rect2(spot, box), bounds)
			if not _overlaps(r, taken) and not _overlaps(r, _symbols, a):
				placed = r
				found = true
				break
		if not found:
			placed = _clamp_rect(Rect2(spots[0], box), bounds)  # crowded: beside it anyway
		taken.append(placed)
		var leader := placed.grow(2.0).has_point(a) == false and _gap(a, placed) > g + 2.0
		var entry := {"rect": placed, "text": shown, "full": String(lab.text), "anchor": a, "leader": leader, "colour": lab.colour, "size": font_size}
		drawn_labels.append(entry)
		if (placed.has_point(_cursor_screen) or a.distance_to(_cursor_screen) <= HOVER_PX) and shown != lab.text and hovered.is_empty():
			hovered = entry
	for entry: Dictionary in drawn_labels:
		var r: Rect2 = entry.rect
		var colour: Color = entry.colour
		if entry.leader:
			var to := Vector2(clampf(entry.anchor.x, r.position.x, r.end.x), clampf(entry.anchor.y, r.position.y, r.end.y))
			draw_line(entry.anchor, to, Color(colour, 0.8), 1.0, true)
		draw_rect(r, Color(0.06, 0.06, 0.05, 0.72))  # dark plate: readable on the pale map
		_label_raw(r.position + Vector2(2, r.size.y - 5), entry.text, colour, entry.size)
	if not hovered.is_empty():  # the whole text of a label cut short, under the cursor
		var full_box := font.get_string_size(hovered.full, HORIZONTAL_ALIGNMENT_LEFT, -1, 13) + Vector2(12, 8)
		var tip := _clamp_rect(Rect2(_cursor_screen + Vector2(14, 14), full_box), Rect2(Vector2.ZERO, size))
		draw_rect(tip, Color(0.05, 0.05, 0.05, 0.92))
		draw_rect(tip, Color(hovered.colour, 0.9), false, 1.0)
		_label_raw(tip.position + Vector2(6, full_box.y - 8), hovered.full, Color.WHITE, 13)


static func _clamp_rect(r: Rect2, bounds: Rect2) -> Rect2:
	var p := r.position.clamp(bounds.position, (bounds.end - r.size).max(bounds.position))
	return Rect2(p, r.size)


## Whether `r` overlaps any of `rects` (a symbol box at `own` doesn't count: the label's own).
static func _overlaps(r: Rect2, rects: Array[Rect2], own := Vector2.INF) -> bool:
	for other in rects:
		if other.intersects(r) and not (own != Vector2.INF and other.get_center().is_equal_approx(own)):
			return true
	return false


static func _gap(p: Vector2, r: Rect2) -> float:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)).distance_to(p)
