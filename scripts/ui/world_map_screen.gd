class_name WorldMapScreen
extends Control
## The theatre map screen (Captain, 2026-10-20): the WorldMapView, a bar along the top (title,
## Zone map when it was opened from the zone map, Fit, "?" for the controls, Close) and a side
## column: the picked zone explained (Theatre.describe: controller, threat, contracts, fights,
## rebel support), the legend, and the controls when "?" is pressed. Opened from the zone map
## (MapScreen: the World button, or Tab) and from the ops desk's region map (RegionMapView,
## open_overlay). In the shared look (UiKit).

## Closed (Esc, Close, the pad's B).
signal closed
## Back to the zone map (Zone map, Tab, the pad's Y).
signal back_to_zone
## A zone was opened (double-click, Enter, the pad's A).
signal zone_picked(zone_id: String)

const SIDE_SHARE := 0.3
const SIDE_MIN := 230.0
const SIDE_MAX := 360.0
## The controls, as the "?" panel lists them: [key, what it does].
const HELP: Array = [["Wheel", "zoom at the cursor"], ["Drag", "pan (any mouse button)"], ["Click", "pick a zone: it's explained on the right"],
	["Hover", "a zone's tooltip"], ["2x click", "open the zone"], ["Arrows", "move between zones"], ["Shift+Arr", "pan"], ["WASD", "pan"],
	["+ / -", "zoom"], ["F", "fit the whole map"], ["Enter", "open the picked zone"], ["Tab", "back to the zone map"], ["Esc", "close"],
	["Pad", "d-pad or left stick: zones; right stick: pan; LB/RB: zoom; A: open; B: close; Y: zone map"]]

var view: WorldMapView
var from_zone_map := false
var bar: PanelContainer
var side: PanelContainer
var _info_title: Label
var _info: Label
var _help: VBoxContainer
var _help_button: Button
var _back_button: Button


func _init(p_from_zone_map := false) -> void:
	from_zone_map = p_from_zone_map
	name = "WorldMapScreen"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.apply(self)
	var backdrop := ColorRect.new()
	backdrop.color = WorldMapView.BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 0)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar = _bar()
	root.add_child(bar)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 0)
	root.add_child(body)
	view = WorldMapView.new()
	body.add_child(view)
	view.zone_focused.connect(_show_zone)
	view.zone_picked.connect(func(id: String) -> void: zone_picked.emit(id))
	view.close_requested.connect(close)
	view.back_requested.connect(func() -> void:
		if from_zone_map:
			back_to_zone.emit())
	side = _side()
	body.add_child(side)
	resized.connect(_layout)
	_layout()
	_show_zone.call_deferred(view.selected)
	view.grab_focus.call_deferred()


## Opens the theatre map over everything (the ops desk): its own CanvasLayer under the root,
## freed when it closes.
static func open_overlay(from: Node) -> WorldMapScreen:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.name = "WorldMapLayer"
	var screen := WorldMapScreen.new()
	layer.add_child(screen)
	screen.closed.connect(layer.queue_free)
	from.get_tree().root.add_child(layer)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return screen


func close() -> void:
	closed.emit()


func _layout() -> void:
	if side == null:
		return
	var w := size.x if size.x > 1.0 else get_viewport_rect().size.x
	side.custom_minimum_size.x = clampf(w * SIDE_SHARE, SIDE_MIN, SIDE_MAX)


func _bar() -> PanelContainer:
	var panel := PanelContainer.new()
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", UiKit.SPACE_S)
	panel.add_child(flow)
	var title := UiKit.heading("THEATRE MAP")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(title)
	var what := UiKit.subtitle("Who holds each zone, and where the fighting is", false)  # (ui-modern: what it's for)
	what.autowrap_mode = TextServer.AUTOWRAP_OFF
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(what)
	_back_button = UiKit.button("Zone map  [Tab]", func() -> void: back_to_zone.emit(), "Back to the map of the zone you're in")
	_back_button.visible = from_zone_map
	flow.add_child(_back_button)
	flow.add_child(UiKit.button("Fit  [F]", func() -> void: view.fit(), "Show the whole theatre"))
	_help_button = UiKit.button("?", func() -> void: show_help(not _help.visible), "The map's mouse, key and pad controls")
	_help_button.custom_minimum_size.x = 40
	flow.add_child(_help_button)
	flow.add_child(UiKit.button("Close  [Esc]", close))
	return panel


func _side() -> PanelContainer:
	var panel := PanelContainer.new()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	scroll.add_child(box)
	_help = VBoxContainer.new()
	_help.visible = false
	_help.add_child(UiKit.heading("Controls"))
	_help.add_child(help_grid(HELP))
	box.add_child(_help)
	_info_title = UiKit.heading("")
	box.add_child(_info_title)
	_info = UiKit.text("")
	box.add_child(_info)
	box.add_child(UiKit.heading("Legend"))
	for s: String in ZoneControl.SIDES:
		box.add_child(_legend_row(LegendIcon.new("side", ZoneControl.SIDE_COLOURS[s], s == "contested"), "%s%s" % [ZoneControl.SIDE_NAMES[s],
			{"player": " (contractors)", "allied": " (employers and their allies)", "militia": " (Black Ridge)", "hostile": " (armies, rival PMC)",
			"neutral": "", "contested": ": being fought over"}[s]]))
	for kind: String in WorldMapView.BADGES:
		box.add_child(_legend_row(LegendIcon.new(kind), String(WorldMapView.BADGES[kind].name)))
	box.add_child(_legend_row(LegendIcon.new("squad", WorldMapView.SQUAD), "The squad's zone"))
	box.add_child(_legend_row(LegendIcon.new("home", ZoneControl.SIDE_COLOURS.player), "Home: the FOB (star) or the LHD offshore"))
	box.add_child(_legend_row(LegendIcon.new("link", WorldMapView.LINK), "Link and its crossing: %d h on foot" % Theatre.LINK_HOURS))
	box.add_child(_legend_row(LegendIcon.new("region", WorldMapView.REGION_EDGE), "Region border (its name gives the travel days from home)"))
	return panel


func _legend_row(icon: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	row.add_child(icon)
	var label := UiKit.hint(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## A two-column list of controls: the key in an accent chip, then what it does (wrapping).
static func help_grid(pairs: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", UiKit.SPACE_S)
	grid.add_theme_constant_override(&"v_separation", UiKit.SPACE_XS)
	for pair: Array in pairs:
		var chip := Label.new()
		chip.text = " %s " % pair[0]
		chip.theme_type_variation = &"KeyLabel"
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(chip)
		var what := UiKit.hint(String(pair[1]))
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	return grid


## Shows or hides the controls ("?"), at the top of the side column.
func show_help(on: bool) -> void:
	_help.visible = on
	_help_button.text = "?" if not on else "? (hide)"


## The side column explains zone `id` (Theatre.describe).
func _show_zone(id: String) -> void:
	if not view.rows.has(id):
		_info_title.text = "Theatre"
		_info.text = "Pick a zone to see who holds it and what's going on there."
		return
	var row: Dictionary = view.rows[id]
	_info_title.text = String(row.name)
	var lines := Theatre.describe(row).split("\n")
	lines.remove_at(0)  # (the name: it's the heading)
	_info.text = "%s, %s\n%s" % [row.region_name, {"base": "the base", "hot": "hot zone", "contract": "contract zone"}.get(row.kind, row.kind), "\n".join(lines)]


func _process(_delta: float) -> void:
	if is_visible_in_tree() and Engine.get_process_frames() % 120 == 0 and view.selected != "":
		_show_zone(view.selected)  # (the rows refresh every few seconds)


## The legend's little pictures, drawn as the map draws them.
class LegendIcon extends Control:
	var kind := ""
	var colour := Color.WHITE
	var hatched := false

	func _init(p_kind: String, p_colour := Color.WHITE, p_hatched := false) -> void:
		kind = p_kind
		colour = p_colour
		hatched = p_hatched
		custom_minimum_size = Vector2(36, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var font := get_theme_default_font()
		match kind:
			"side":
				var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
				draw_rect(r, WorldMapView.LAND.lerp(colour, 0.55) if not hatched else WorldMapView.LAND.lerp(ZoneControl.SIDE_COLOURS.neutral, 0.55))
				if hatched:
					var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
					for x in range(-int(r.size.y), int(r.size.x), 7):
						var line := PackedVector2Array([r.position + Vector2(x, r.size.y), r.position + Vector2(x + r.size.y, 0)])
						for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, box):
							draw_polyline(piece, Color(colour, 0.8), 2.0)
				draw_rect(r, WorldMapView.ZONE_EDGE, false, 1.5)
			"squad":
				draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), colour, false, 4.0)
			"home":
				var star := PackedVector2Array()
				for i in 10:
					star.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (10.0 if i % 2 == 0 else 4.5))
				draw_colored_polygon(star, colour.lightened(0.35))
			"link":
				draw_dashed_line(Vector2(2, c.y), Vector2(size.x - 2, c.y), colour, 2.0, 5.0)
				draw_circle(c, 5.0, WorldMapView.ZONE_EDGE)
				draw_circle(c, 3.5, colour.lightened(0.3))
			"region":
				draw_line(Vector2(2, c.y), Vector2(size.x - 2, c.y), colour, 3.0)
			_:
				WorldMapView.draw_badge(self, font, kind, c, "")
