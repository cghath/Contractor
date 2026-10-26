class_name FallenMap
extends Control
## The survival map (docs/survival.md calls 37 and 45, phase A step 7; survival_world.md
## section 10): one map, continuous zoom from the world down to the zone. MapScreen shows it over
## its zone map when the level is a SurvivalLevel (show_on), and Tab / World zooms it out instead
## of opening the theatre map (on_show_world).
##
## One plane in "world metres": every zone of RegionMap's grid is a SPAN square, its ground
## (map_area) fitted into the square's inner part. Far out it's the world grid: the zones known
## (SurvivalMap.known: visited or told) with their names, the rest fog, the zone being played
## framed, marks as small glyphs. Zooming in (the wheel) blends into the zone under the view's
## centre: the zone being played shows its map picture (MapView's texture, not in headless),
## other known zones a plain shaded square until visited; the explored cells clear, the rest
## fogged; your own position; the marks with their text and age, fainter as they age (faded past
## SurvivalMap.FADE_DAYS). Left or middle drag pans, right click (or a double click) adds a mark
## (its text asked as MapView does), Delete removes the mark under the cursor.
## First form: the real-map relief and roads at the world level and the intel layers are later.

const NODE_NAME := "FallenMap"
## Proposed: a zone's square in world metres and the margin round its ground inside it.
const SPAN := 2400.0
const PAD := 140.0
const ZOOM_STEP := 1.25
## Proposed: how far in past the zone level the wheel goes (times the zone-level zoom).
const MAX_IN := 14.0
const DEFAULT_SIZE_M := 1920.0
const BACKDROP := Color(0.09, 0.1, 0.09)
const ZONE_FILL := Color(0.24, 0.26, 0.2)
const UNVISITED_FILL := Color(0.3, 0.3, 0.27)
const FOG := Color(0.13, 0.14, 0.13)
const FOG_LINE := Color(0.2, 0.21, 0.19)
const CELL_FOG := Color(0.1, 0.11, 0.1, 0.78)
const LINK := Color(0.45, 0.48, 0.42)
const FRAME := Color(0.93, 0.69, 0.27)
const SELF_COLOUR := Color(0.2, 1.0, 1.0)
const MARK_COLOURS := {"safehouse": Color(0.35, 0.9, 0.45), "note": Color(1.0, 0.85, 0.3), "camp": Color(0.95, 0.4, 0.3)}
const HOVER_PX := 10.0

var screen: Node
var level: Node
## The view: the world point at the middle, and pixels per world metre.
var centre := Vector2.ZERO
var zoom := 0.1
## Drawn last frame (for tests and the hover): the zones named at the world level, and the marks.
var drawn_zones: Array[String] = []
var drawn_marks: Array[Dictionary] = []

var _sizes := {}
var _drag := 0
var _drag_moved := 0.0
var _cursor := Vector2.ZERO
var _text: LineEdit
var _text_at := Vector2.ZERO
## Until the view is touched it keeps its framing as the control is laid out: [zone id] or ["world"].
var _framing: Array = []


## MapScreen.open: shows the one map over `p_screen`'s zone map when `on` (a survival zone), at the
## zone level of the zone being played, centred on you; else hides it.
static func show_on(p_screen: Control, on: bool) -> FallenMap:
	var fm := p_screen.get_node_or_null(NODE_NAME) as FallenMap
	if not on:
		if fm:
			fm.visible = false
		return fm
	if fm == null:
		fm = FallenMap.new()
		fm.screen = p_screen
		p_screen.add_child(fm)
		var view: Control = p_screen.get(&"view")
		if view:
			p_screen.move_child(fm, view.get_index() + 1)
	fm.level = MapNodes.level_of(p_screen)
	var v: Control = p_screen.get(&"view")
	fm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if v:
		fm.offset_top = v.offset_top
	fm.visible = true
	fm.zoom_to_zone(SurvivalMap.current_zone())
	var me := MapNodes.local_player(p_screen)
	if me:
		fm.centre = fm.to_world(SurvivalMap.current_zone(), Vector2(me.global_position.x, me.global_position.z))
		fm._clamp()
	fm.grab_focus()
	return fm


## MapScreen.show_world: Tab / World zooms the one map out to the world (or back into the zone);
## returns false when there's no one map showing (the theatre map as ever).
static func on_show_world(p_screen: Node, on: bool) -> bool:
	var fm := p_screen.get_node_or_null(NODE_NAME) as FallenMap
	if fm == null or not fm.visible:
		return false
	if on and not fm.is_world():
		fm.zoom_to_world()
	else:
		fm.zoom_to_zone(fm.focus_zone() if fm.focus_zone() != "" else SurvivalMap.current_zone())
	return true


func _init() -> void:
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


func _ready() -> void:
	_text = LineEdit.new()
	_text.visible = false
	_text.custom_minimum_size = Vector2(200, 0)
	_text.placeholder_text = "Mark text, Enter"
	_text.text_submitted.connect(_on_text_submitted)
	_text.focus_exited.connect(func() -> void: _text.visible = false)
	add_child(_text)
	resized.connect(_on_resized)


func _on_resized() -> void:
	if _framing.is_empty():
		_clamp()
	elif String(_framing[0]) == "world":
		zoom_to_world()
	else:
		var c := centre
		zoom_to_zone(String(_framing[0]))
		centre = c
		_clamp()


# --- The plane -----------------------------------------------------------------------------

func view_size() -> Vector2:
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(1600, 900)


static func grid_size() -> Vector2i:
	var n := Vector2i(1, 1)
	for cell: Vector2i in RegionMap.layout().values():
		n = Vector2i(maxi(n.x, cell.x + 1), maxi(n.y, cell.y + 1))
	return n


## A zone's square in world metres (the whole cell), and the part its ground fills.
static func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * SPAN, Vector2(SPAN, SPAN))


static func inner_rect(cell: Vector2i) -> Rect2:
	return cell_rect(cell).grow(-PAD)


## A zone's ground (x, z): the level's map_area for the zone being played, else its size centred.
func area_of(zone_id: String) -> Rect2:
	if level and level.has_method(&"map_area") and zone_id == SurvivalMap.current_zone():
		return level.call(&"map_area")
	if not _sizes.has(zone_id):
		var spec: Variant = MissionRegistry.zone(zone_id).get("def")
		var s := DEFAULT_SIZE_M
		if spec is Dictionary:
			s = float((spec as Dictionary).get("size_m", ZoneDef.HOT_SIZE_M if String((spec as Dictionary).get("layout", "")) == "hot" else DEFAULT_SIZE_M))
		_sizes[zone_id] = s
	var half := float(_sizes[zone_id]) * 0.5
	return Rect2(-half, -half, half * 2.0, half * 2.0)


## A zone point (x, z) on the world plane.
func to_world(zone_id: String, p: Vector2) -> Vector2:
	var layout := RegionMap.layout()
	if not layout.has(zone_id):
		return p
	var inner := inner_rect(layout[zone_id])
	var a := area_of(zone_id)
	var s := inner.size.x / maxf(maxf(a.size.x, a.size.y), 1.0)
	return inner.get_center() + (p - a.get_center()) * s


## A world point as [zone id, its point in that zone (x, z)]; zone "" off every zone.
func from_world(w: Vector2) -> Array:
	var cell := Vector2i(floori(w.x / SPAN), floori(w.y / SPAN))
	var zone := RegionMap.zone_at(cell)
	if zone == "":
		return ["", Vector2.ZERO]
	var inner := inner_rect(cell)
	var a := area_of(zone)
	var s := inner.size.x / maxf(maxf(a.size.x, a.size.y), 1.0)
	return [zone, a.get_center() + (w - inner.get_center()) / s]


func world_to_screen(w: Vector2) -> Vector2:
	return view_size() * 0.5 + (w - centre) * zoom


func screen_to_world(s: Vector2) -> Vector2:
	return centre + (s - view_size() * 0.5) / zoom


## The zoom that shows the whole grid, and the one where a zone's square fills the view.
func world_zoom() -> float:
	var v := view_size()
	var g := Vector2(grid_size()) * SPAN
	return minf(v.x / g.x, v.y / g.y) * 0.95


func zone_zoom() -> float:
	var v := view_size()
	return minf(v.x, v.y) / SPAN


## 0 the world, 1 the zone: how far the zone layers have blended in.
func blend() -> float:
	var lo := log(world_zoom() * 1.4)
	var hi := log(zone_zoom() * 0.8)
	if hi <= lo:
		return 1.0 if zoom >= zone_zoom() * 0.8 else 0.0
	return clampf((log(zoom) - lo) / (hi - lo), 0.0, 1.0)


func is_world() -> bool:
	return blend() < 0.5


## The zone under the view's middle, or "".
func focus_zone() -> String:
	return String(from_world(centre)[0])


func zoom_to_world() -> void:
	_framing = ["world"]
	zoom = world_zoom()
	centre = Vector2(grid_size()) * SPAN * 0.5
	_clamp()


func zoom_to_zone(zone_id: String) -> void:
	_framing = [zone_id]
	zoom = zone_zoom()
	var layout := RegionMap.layout()
	if layout.has(zone_id):
		centre = cell_rect(layout[zone_id]).get_center()
	_clamp()


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	_framing = []
	var before := screen_to_world(screen_pos)
	zoom = clampf(zoom * factor, world_zoom() * 0.8, zone_zoom() * MAX_IN)
	centre += before - screen_to_world(screen_pos)
	_clamp()


func pan(screen_delta: Vector2) -> void:
	_framing = []
	centre -= screen_delta / zoom
	_clamp()


func _clamp() -> void:
	var g := Vector2(grid_size()) * SPAN
	centre = centre.clamp(Vector2(-SPAN * 0.5, -SPAN * 0.5), g + Vector2(SPAN * 0.5, SPAN * 0.5))
	queue_redraw()


## The zones the world level names: the known ones on the grid.
static func listed_zones() -> Array[String]:
	var out: Array[String] = []
	var layout := RegionMap.layout()
	for id: String in SurvivalMap.known():
		if layout.has(id):
			out.append(id)
	return out


# --- Input ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	var m := event as InputEventMouseMotion
	if m:
		_cursor = m.position
		if _drag != 0:
			_drag_moved += m.relative.length()
			pan(m.relative)
		queue_redraw()
	elif b:
		grab_focus()
		match b.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if b.pressed:
					zoom_at(b.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if b.pressed:
					zoom_at(b.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if b.pressed and b.double_click and b.button_index == MOUSE_BUTTON_LEFT:
					_drag = 0
					ask_text(b.position)
				elif b.pressed:
					_drag = b.button_index
					_drag_moved = 0.0
				elif b.button_index == _drag:
					_drag = 0
					if b.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < 4.0:
						ask_text(b.position)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
		var i := mark_at(_cursor)
		var node := SurvivalMap.of(self)
		if i >= 0 and node:
			node.request_remove_mark(i)
			accept_event()


## Asks the text of a mark at `screen_pos` (on a zone only).
func ask_text(screen_pos: Vector2) -> void:
	if String(from_world(screen_to_world(screen_pos))[0]) == "":
		return
	_text_at = screen_to_world(screen_pos)
	_text.text = ""
	_text.position = (screen_pos + Vector2(10, -14)).clamp(Vector2.ZERO, view_size() - Vector2(210, 32))
	_text.visible = true
	_text.grab_focus()


func _on_text_submitted(text: String) -> void:
	_text.visible = false
	add_mark_at(_text_at, text)
	grab_focus()


## Adds a mark at the world point `w` (through the host).
func add_mark_at(w: Vector2, text: String) -> void:
	var at := from_world(w)
	var node := SurvivalMap.of(self)
	if String(at[0]) != "" and text.strip_edges() != "" and node:
		node.request_add_mark(String(at[0]), at[1], text)
	queue_redraw()


## The index (in SurvivalMap.marks("")) of the mark under `screen_pos`, or -1.
func mark_at(screen_pos: Vector2) -> int:
	for d: Dictionary in drawn_marks:
		if (d.at as Vector2).distance_to(screen_pos) <= HOVER_PX:
			return int(d.index)
	return -1


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()  # you move; the texture comes in


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	drawn_zones.clear()
	drawn_marks.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var t := blend()
	var layout := RegionMap.layout()
	var known := SurvivalMap.known()
	var here := SurvivalMap.current_zone()
	var font := get_theme_default_font()
	var screen_box := Rect2(Vector2.ZERO, view_size())
	for id: String in layout:  # the roads between known zones (the links)
		for l: Dictionary in RegionMap.links(id):
			if id < String(l.to) and known.has(id) and known.has(String(l.to)):
				draw_line(world_to_screen(cell_rect(layout[id]).get_center()), world_to_screen(cell_rect(layout[String(l.to)]).get_center()), Color(LINK, 1.0 - t * 0.7), 2.0)
	for id: String in layout:
		var cell: Vector2i = layout[id]
		var r := Rect2(world_to_screen(inner_rect(cell).position), inner_rect(cell).size * zoom)
		if not r.intersects(screen_box):
			continue
		if not known.has(id):
			draw_rect(r, FOG)
			draw_line(r.position, r.end, FOG_LINE, 1.0)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), FOG_LINE, 1.0)
			continue
		var visited := String((known[id] as Dictionary).get("how", "")) == "visited"
		draw_rect(r, ZONE_FILL if visited else UNVISITED_FILL)
		if t > 0.0:
			_draw_zone(id, r, t)
		draw_rect(r, FRAME if id == here else LINK, false, 3.0 if id == here else 1.0)
		drawn_zones.append(id)
		if t < 1.0:
			var label := RegionMap.zone_name(id) + ("" if visited else " (told)")
			var fs := UiKit.FONT_BODY
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(r.get_center().x - w * 0.5, r.position.y + minf(22.0, r.size.y * 0.5))
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.75 * (1.0 - t)))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.TEXT, 1.0 - t))
	_draw_marks(t, font)
	_draw_self()


## A zone's own layers at blend `t`: its picture (the zone being played) or a plain shade, and
## the fog over the cells nobody has been near.
func _draw_zone(id: String, r: Rect2, t: float) -> void:
	if id == SurvivalMap.current_zone():
		var tex := _texture()
		if tex:
			draw_texture_rect(tex, r, false, Color(1, 1, 1, t))
	var cells := SurvivalMap.explored(id)
	var a := area_of(id)
	var s := r.size.x / maxf(maxf(a.size.x, a.size.y), 1.0)  # screen px per zone metre
	var cell_px := SurvivalMap.CELL_M * s
	if cell_px < 3.0:
		draw_rect(r, Color(CELL_FOG, CELL_FOG.a * t * (0.5 if not cells.is_empty() else 1.0)))
		return
	var fog := Color(CELL_FOG, CELL_FOG.a * t)
	var shown := r.intersection(Rect2(Vector2.ZERO, view_size()))
	var x0 := floori((a.position.x + (shown.position.x - r.position.x) / s) / SurvivalMap.CELL_M)
	var x1 := ceili((a.position.x + (shown.end.x - r.position.x) / s) / SurvivalMap.CELL_M)
	var z0 := floori((a.position.y + (shown.position.y - r.position.y) / s) / SurvivalMap.CELL_M)
	var z1 := ceili((a.position.y + (shown.end.y - r.position.y) / s) / SurvivalMap.CELL_M)
	for cz in range(z0, z1):
		for cx in range(x0, x1):
			if cells.has("%d,%d" % [cx, cz]):
				continue
			var p := r.position + (Vector2(cx, cz) * SurvivalMap.CELL_M - a.position) * s
			draw_rect(Rect2(p, Vector2(cell_px, cell_px)).intersection(r), fog)


## The zone picture (MapView's, made once per level), never in headless.
func _texture() -> Texture2D:
	if DisplayServer.get_name() == "headless" or screen == null:
		return null
	var view: Variant = screen.get(&"view")
	return (view as MapView).texture() if view is MapView else null


func _draw_marks(t: float, font: Font) -> void:
	var known := SurvivalMap.known()
	var all := SurvivalMap.marks("")
	for i in all.size():
		if not all[i] is Dictionary:
			continue
		var m: Dictionary = all[i]
		var zone := String(m.get("zone", ""))
		if not known.has(zone):
			continue
		var at := world_to_screen(to_world(zone, SurvivalMap.mark_pos(m)))
		if not Rect2(Vector2.ZERO, view_size()).grow(20.0).has_point(at):
			continue
		var faded := SurvivalMap.is_faded(m)
		var age := SurvivalMap.age_days(m)
		var alpha := 0.35 if faded else 1.0 - 0.45 * clampf(age / SurvivalMap.FADE_DAYS, 0.0, 1.0)
		var colour := Color(MARK_COLOURS.get(String(m.get("kind", "note")), MARK_COLOURS.note), alpha)
		var r := 4.0 if t < 0.5 else 6.0
		if String(m.get("kind", "")) == "safehouse":
			draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), colour)
		else:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), colour)
		drawn_marks.append({"index": i, "at": at, "faded": faded})
		if t >= 0.5:
			var label := "%s (%s)" % [String(m.get("text", "")), SurvivalMap.age_text(m)]
			var p := at + Vector2(9, 5)
			draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, 3, Color(0, 0, 0, 0.75 * alpha))
			draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, Color(UiKit.TEXT, alpha))


func _draw_self() -> void:
	var me := MapNodes.local_player(self)
	if me == null:
		return
	var s := world_to_screen(to_world(SurvivalMap.current_zone(), Vector2(me.global_position.x, me.global_position.z)))
	var f := -me.global_basis.z
	var dir := Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector2.UP
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([s + dir * 10.0, s - dir * 6.0 + side * 6.0, s - dir * 3.0, s - dir * 6.0 - side * 6.0]), SELF_COLOUR)
