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
## The intel layer (phase C, call 37/45/98): each known zone is washed faintly in the colour of
## the group that holds most of its region (political_colour, from WorldSim.region_holders); a
## told mark names its teller; the zone zoom draws the zone's landmarks (Landmarks); standing at
## the settlement's map table (MapTable.near) adds its reports: allies' sightings (red crosses),
## trade routes (dashed lines between homes), known group movements (dots, fainter with age) and
## a list of them at the top left.
## Still to come: the real-map relief and roads at the world level.

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
const MARK_COLOURS := {"safehouse": Color(0.35, 0.9, 0.45), "note": Color(1.0, 0.85, 0.3), "camp": Color(0.95, 0.4, 0.3), "village": Color(0.6, 0.8, 1.0),
	"told": Color(0.85, 0.72, 1.0), "radio": Color(0.55, 0.95, 0.85)}
const HOVER_PX := 10.0
## Proposed: the political wash's colours by the holder's kind, and its strength.
const KIND_COLOURS := {"settlers": Color(0.35, 0.8, 0.4), "raiders": Color(0.9, 0.25, 0.2), "scavengers": Color(0.9, 0.8, 0.3),
	"cultists": Color(0.65, 0.35, 0.85), "enclave": Color(0.3, 0.55, 1.0), "player": Color(0.2, 1.0, 1.0), "lone": Color(0.7, 0.7, 0.7)}
const POLITICAL_ALPHA := 0.16
const LANDMARK_COLOUR := Color(0.85, 0.82, 0.7)
const TABLE_COLOUR := Color(1.0, 0.45, 0.35)
const ROUTE_COLOUR := Color(0.95, 0.85, 0.45)
## Proposed: how often (real s) the map table's reports are read again while you stand at it.
const TABLE_READ_S := 1.0

var screen: Node
var level: Node
## The view: the world point at the middle, and pixels per world metre.
var centre := Vector2.ZERO
var zoom := 0.1
## Drawn last frame (for tests and the hover): the zones named at the world level, and the marks.
var drawn_zones: Array[String] = []
var drawn_marks: Array[Dictionary] = []
## Drawn last frame: landmarks ({"name", "at"}) and, at a map table, its reports (MapTable.reports).
var drawn_landmarks: Array[Dictionary] = []
var table_reports := {}
var _table_t := -100.0
var _region_colours := {}

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
		fm.zoom_to_zone(SurvivalMap.current_zone())  # (back to where you are; the wheel goes into any other)
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
	drawn_landmarks.clear()
	_region_colours.clear()
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
		var pc := _political(id)
		if pc.a > 0.0:
			draw_rect(r, Color(pc, pc.a * (1.0 - 0.6 * t)))
		if t >= 0.5 and visited:
			_draw_landmarks(id, font, t)
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
	_draw_table(font)
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
			var teller := String(m.get("teller", ""))
			var label := "%s (%s%s)" % [String(m.get("text", "")), SurvivalMap.age_text(m), (", told by " + teller) if teller != "" else ""]
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


# --- The intel layer -----------------------------------------------------------------------------

## The faint colour of `region_id`'s holder: the group holding the most places in it
## (WorldSim.region_holders), by its kind (KIND_COLOURS); clear when nobody holds any.
static func region_colour(region_id: String) -> Color:
	if region_id == "" or not WorldSim.is_set_up():
		return Color(0, 0, 0, 0)
	var holders := WorldSim.region_holders(region_id)
	var best := ""
	var most := 0
	var keys := holders.keys()
	keys.sort()
	for gid: String in keys:
		if int(holders[gid]) > most:
			most = int(holders[gid])
			best = gid
	if best == "":
		return Color(0, 0, 0, 0)
	var kind := "player" if best == "player" else String(WorldSim.group(best).get("kind", "lone"))
	var c: Color = KIND_COLOURS.get(kind, KIND_COLOURS.lone)
	return Color(c, POLITICAL_ALPHA)


## A zone's political wash: its region's colour.
static func political_colour(zone_id: String) -> Color:
	return region_colour(WorldSim.region_of(zone_id)) if WorldSim.is_set_up() else Color(0, 0, 0, 0)


func _political(zone_id: String) -> Color:
	var region := WorldSim.region_of(zone_id) if WorldSim.is_set_up() else ""
	if not _region_colours.has(region):
		_region_colours[region] = region_colour(region)
	return _region_colours[region]


## A zone's landmarks (Landmarks) as small triangles with their names (the zone zoom).
func _draw_landmarks(zone_id: String, font: Font, t: float) -> void:
	var box := Rect2(Vector2.ZERO, view_size()).grow(20.0)
	var colour := Color(LANDMARK_COLOUR, clampf((t - 0.5) * 2.0, 0.0, 1.0))
	for l: Dictionary in Landmarks.of(zone_id):
		var at := world_to_screen(to_world(zone_id, l.pos as Vector2))
		if not box.has_point(at):
			continue
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 4), at + Vector2(-5, 4)]), colour)
		var p := at + Vector2(8, -4)
		draw_string_outline(font, p, String(l.name), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, 3, Color(0, 0, 0, 0.7 * colour.a))
		draw_string(font, p, String(l.name), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, colour)
		drawn_landmarks.append({"name": String(l.name), "at": at})


## At the settlement's map table (host: MapTable.near): its reports over the map, and listed.
func _draw_table(font: Font) -> void:
	var me := MapNodes.local_player(self)
	if not Survival.running or me == null or not MapTable.near(me):
		table_reports = {}
		return
	var real := Time.get_ticks_msec() / 1000.0
	if real - _table_t >= TABLE_READ_S or table_reports.is_empty():
		_table_t = real
		table_reports = MapTable.reports()
	var layout := RegionMap.layout()
	var centre_of := func(z: String) -> Vector2:
		return world_to_screen(cell_rect(layout[z]).get_center()) if layout.has(z) else Vector2(-1000, -1000)
	for r: Dictionary in table_reports.get("routes", []):
		var a: Vector2 = centre_of.call(String(r.a_zone))
		var b: Vector2 = centre_of.call(String(r.b_zone))
		if a != b:
			draw_dashed_line(a, b, ROUTE_COLOUR, 2.0, 8.0)
	for sgt: Dictionary in table_reports.get("sightings", []):
		var at: Vector2 = centre_of.call(String(sgt.zone))
		draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), TABLE_COLOUR, 2.0)
		draw_line(at + Vector2(-6, 6), at + Vector2(6, -6), TABLE_COLOUR, 2.0)
	for m: Dictionary in table_reports.get("movements", []):
		var at: Vector2 = centre_of.call(String(m.zone)) + Vector2(10, 10)
		var alpha := clampf(1.0 - float(m.age) / MapTable.MOVE_DAYS, 0.25, 1.0)
		draw_circle(at, 4.0, Color(TABLE_COLOUR, alpha))
		draw_string(font, at + Vector2(6, 4), String(m.name), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, Color(UiKit.TEXT, alpha))
	var y := 24.0
	draw_string(font, Vector2(12, y), "Map table", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_BODY, UiKit.ACCENT)
	for line: String in MapTable.lines(table_reports).slice(0, 14):
		y += 18.0
		draw_string_outline(font, Vector2(12, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, 3, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(12, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, UiKit.TEXT)
