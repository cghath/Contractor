class_name MapScreen
extends Control
## The full-screen map (M): MapView, a toolbar (marker colour and kind, the grid reference
## under the cursor) and side panels: the briefing while one is open, extraction while a
## deployment is on. The briefing opens it on every player's screen and keeps it open until
## the deployment starts. Lives on the local player's HUD; while it's open the mouse is free
## and you stand still, as with the inventory screen. In the shared look (UiKit); World (or Tab)
## switches to the theatre map (WorldMapScreen) and back.

const COLOUR_ORDER: Array[String] = ["black", "red", "blue", "green", "orange", "purple", "white"]
## The controls, as "?" lists them: [key, what it does].
const HELP: Array = [["Wheel", "zoom"], ["Right drag", "pan"], ["Double-click", "place a marker"], ["Ctrl + drag", "draw a line"],
	["Drag a marker", "move it"], ["Delete", "remove the marker under the cursor"], ["Right click", "menu (marker, enemy, extraction point, orders)"],
	["Tab", "the theatre map (World)"], ["M / Esc", "close"]]

var player: Soldier
var view: MapView
var briefing_panel: BriefingScreen
var toolbar: PanelContainer
var extraction_panel: MapExtractionPanel
## High command (MapHcPanel): on the left while a squad is out.
var hc_panel: MapHcPanel
var _reference: Label
var _kind: OptionButton
var _swatches := {}  # colour name -> its Button
var _help: PanelContainer
var _help_scroll: ScrollContainer
var _help_box: VBoxContainer
var _help_button: Button
var _close_button: Button
## The theatre map, made the first time World is pressed.
var world: WorldMapScreen
var _level: Node
var _forced := false  # opened by the briefing


func _init(p_player: Soldier = null) -> void:
	player = p_player
	name = "MapScreen"


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.apply(self)
	var backdrop := ColorRect.new()
	backdrop.color = MapView.BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = MapView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.cursor_moved.connect(func(ref: String) -> void: _reference.text = "Grid %s" % ref)
	toolbar = _toolbar()
	add_child(toolbar)
	toolbar.resized.connect(_layout_panels)  # (it wraps onto more lines in a narrow window)
	_help = _help_panel()
	add_child(_help)
	_help.visibility_changed.connect(_layout_panels)
	briefing_panel = BriefingScreen.new()
	briefing_panel.visible = false
	add_child(briefing_panel)
	briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	# Captain, 2026-10-14 (B0912): the panel ran off the window's right edge. It grows to the
	# left if anything in it is ever wider, and its width follows the window (_layout_panels).
	briefing_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	briefing_panel.offset_bottom = -8
	briefing_panel.offset_right = -8
	extraction_panel = MapExtractionPanel.new()
	extraction_panel.visible = false
	add_child(extraction_panel)
	extraction_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	extraction_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	extraction_panel.offset_left = -MapExtractionPanel.WIDTH - 8
	extraction_panel.offset_right = -8
	hc_panel = MapHcPanel.new()
	hc_panel.visible = false
	add_child(hc_panel)
	hc_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hc_panel.offset_left = 8
	hc_panel.offset_right = 8 + MapHcPanel.WIDTH
	resized.connect(_layout_panels)
	_layout_panels()
	_connect_level.call_deferred()


## The briefing panel's width for this window (BriefingScreen.width_for), and the map beside it;
## everything starts under the toolbar, however many lines it takes.
func _layout_panels() -> void:
	if briefing_panel == null:
		return
	var top := toolbar.size.y if toolbar.size.y > 0.0 else toolbar.get_combined_minimum_size().y
	view.offset_top = top
	briefing_panel.offset_top = top + 8
	extraction_panel.offset_top = top + 8
	hc_panel.offset_top = top + 8
	_help.offset_top = top + 8
	var room := (size.y if size.y > 1.0 else get_viewport_rect().size.y) - top - 32.0
	_help_scroll.custom_minimum_size.y = clampf(_help_box.get_combined_minimum_size().y, 60.0, maxf(room, 60.0))
	var w := BriefingScreen.width_for(size.x if size.x > 1.0 else get_viewport_rect().size.x)
	briefing_panel.set_panel_width(w)
	briefing_panel.offset_left = -w - 8
	_refresh_inset()


func _connect_level() -> void:
	_level = MapNodes.level_of(self)
	var briefing := MapNodes.briefing(self)
	if briefing:
		briefing.changed.connect(_on_briefing_changed)
		_on_briefing_changed()
	var extraction := MapNodes.extraction(self)
	if extraction:
		extraction.changed.connect(_refresh_panels)
	var hc := MapNodes.high_command(self)
	if hc:
		hc.changed.connect(_refresh_hc)


func is_open() -> bool:
	return visible


## Opens or closes the map (M). The briefing keeps it open.
func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	var level := MapNodes.level_of(self)
	if level == null:
		return
	if level != view.level:
		view.setup(level)
	visible = true
	_refresh_panels()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	view.grab_focus()
	var me := MapNodes.local_player(self)
	if me and not _forced:
		view.look_at_point(Vector2(me.global_position.x, me.global_position.z))


func close() -> void:
	show_world(false)
	if _forced:
		return
	visible = false
	if player == null or player._hud == null or not player._hud.is_inventory_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(HcCamera.ACTION):
		return  # Shift+M is the 3D camera's (PlayerInput), not the map's M
	if event.is_action_pressed(&"map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"inventory"):
		get_viewport().set_input_as_handled()  # one screen at a time: the inventory would take the mouse back


## Tab: the theatre map and back. Before the GUI sees it, which would move the focus with it.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"inventory"):
		show_world(not is_world_open())
		get_viewport().set_input_as_handled()


func is_world_open() -> bool:
	return world != null and world.visible


## Shows the theatre map over the zone map (World, Tab), or goes back to the zone map.
func show_world(on: bool) -> void:
	if on and world == null:
		world = WorldMapScreen.new(true)
		world.visible = false
		add_child(world)
		world.back_to_zone.connect(show_world.bind(false))
		world.closed.connect(close)
	if world == null:
		return
	world.visible = on
	if on:
		world.view.refresh()
		world.view.grab_focus()
	elif visible:
		view.grab_focus()


func _on_briefing_changed() -> void:
	var briefing := MapNodes.briefing(self)
	var briefing_open := briefing != null and briefing.is_open()
	view.marker_channel = "plan" if briefing_open else "field"
	if briefing_open and not _forced:
		_forced = true
		open()
		view.fit()
	elif not briefing_open and _forced:
		_forced = false
		close()
	_refresh_panels()


func _refresh_panels() -> void:
	var briefing := MapNodes.briefing(self)
	briefing_panel.visible = briefing != null and briefing.is_open()
	if briefing_panel.visible:
		briefing_panel.show_briefing(briefing)
	var extraction := MapNodes.extraction(self)
	extraction_panel.visible = not briefing_panel.visible and extraction != null and extraction.state != Extraction.State.IDLE
	if extraction_panel.visible:
		extraction_panel.show_extraction(extraction)
	_close_button.disabled = _forced  # the briefing keeps the map open
	_refresh_hc()
	_refresh_inset()


## The 3D mission map (HcCamera map mode, combined_arms.md 5.3): over the map view, or gone.
var map_3d: SubViewportContainer


func toggle_3d_map() -> void:
	if map_3d:
		map_3d.queue_free()
		map_3d = null
		return
	var lvl := MapNodes.level_of(self)
	if lvl == null:
		return
	var marks: Array = []
	for o: Dictionary in MapView.objectives_in(self):
		var p: Variant = o.get("pos")
		if p is Array and (p as Array).size() >= 2:
			marks.append({"pos": Vector3(float(p[0]), 0.0, float(p[1])), "label": String(o.get("title", "Objective")), "colour": Color(1.0, 0.85, 0.3)})
	var b := MapNodes.briefing(self)
	if b:
		for point: Dictionary in b.insertion_points():
			var q: Array = point.get("pos", [])
			if q.size() >= 2:
				marks.append({"pos": Vector3(float(q[0]), 0.0, float(q[1])), "label": String(point.get("name", "Insertion")), "colour": Color(0.4, 0.95, 0.5)})
	for m: Dictionary in marks:
		m.pos = Vector3(m.pos.x, HcCamera._height_fn(lvl).call(m.pos.x, m.pos.z), m.pos.z)
	map_3d = HcCamera.open_map_mode(lvl, marks)
	add_child(map_3d)
	map_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_3d.offset_top = view.offset_top
	map_3d.offset_left = view.offset_left
	map_3d.offset_right = view.offset_right
	map_3d.offset_bottom = view.offset_bottom


## The high command panel: shown while any group is out (MapHcPanel).
func _refresh_hc() -> void:
	var hc := MapNodes.high_command(self)
	var want := visible and hc != null and (not hc.view.is_empty() or (DevTools.on() and multiplayer.is_server())) and not briefing_panel.visible
	if hc_panel.visible != want:
		hc_panel.visible = want
		_refresh_inset()
	if want:
		hc_panel.show_command(hc)
		view.queue_redraw()
	view.command.refresh()


## The map fills what the toolbar and the side panel leave.
func _refresh_inset() -> void:
	var inset := 0.0
	if briefing_panel.visible:
		inset = briefing_panel.custom_minimum_size.x + 16.0
	elif extraction_panel.visible:
		inset = MapExtractionPanel.WIDTH + 16.0
	if view.offset_right != -inset:
		view.offset_right = -inset
	var left := MapHcPanel.WIDTH + 16.0 if hc_panel and hc_panel.visible else 0.0
	if view.offset_left != left:
		view.offset_left = left
	if _help:
		_help.offset_right = -inset - 8.0


func _process(_delta: float) -> void:
	if visible and extraction_panel.visible and Engine.get_process_frames() % 30 == 0:
		_refresh_panels()  # the squad list changes as squadmates fall


## The bar along the top (Captain, 2026-10-14: it was one run-on line of hints): the title and
## the grid reference under the cursor on the left, the marker tools (kind and colour, the
## picked colour ringed) in the middle, and Controls (the mouse help, hidden until asked for)
## and Close on the right.
func _toolbar() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var row := HFlowContainer.new()  # (wraps onto a second line in a narrow window or at a big UI scale)
	row.add_theme_constant_override(&"h_separation", UiKit.SPACE_S)
	panel.add_child(row)
	var title := UiKit.heading("MAP")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var what := UiKit.subtitle("Plan, mark and order in this zone", false)  # (ui-modern: every menu says what it's for)
	what.autowrap_mode = TextServer.AUTOWRAP_OFF
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(what)
	_reference = Label.new()
	_reference.custom_minimum_size = Vector2(150, 0)
	_reference.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reference.text = "Grid ----"
	_reference.tooltip_text = "The grid reference under the cursor"
	row.add_child(_reference)
	_kind = OptionButton.new()
	_kind.add_item("Marker")
	_kind.add_item("Enemy")
	_kind.tooltip_text = "What a double-click places"
	_kind.item_selected.connect(func(index: int) -> void: view.marker_kind = "enemy" if index == 1 else "point")
	row.add_child(_kind)
	for colour_name in COLOUR_ORDER:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.tooltip_text = colour_name.capitalize()
		swatch.pressed.connect(func() -> void:
			view.marker_colour = colour_name
			_show_picked_colour())
		row.add_child(swatch)
		_swatches[colour_name] = swatch
	_show_picked_colour()
	row.add_child(UiKit.button("World  [Tab]", func() -> void: show_world(true), "The theatre map: every zone, who holds it and where the fighting is"))
	_help_button = Button.new()
	_help_button.text = "?"
	_help_button.custom_minimum_size = Vector2(40, 0)
	_help_button.toggle_mode = true
	_help_button.tooltip_text = "Show the map's mouse and key controls"
	_help_button.toggled.connect(func(on: bool) -> void: _help.visible = on)
	row.add_child(_help_button)
	_close_button = UiKit.button("Close  [M]", close)
	row.add_child(_close_button)
	return panel


## Rings the picked marker colour's swatch.
func _show_picked_colour() -> void:
	var picked := view.marker_colour if view else "black"
	for colour_name: String in _swatches:
		var style := StyleBoxFlat.new()
		style.bg_color = MapMarkers.colour_value(colour_name)
		style.set_corner_radius_all(3)
		var on := colour_name == picked
		style.set_border_width_all(2 if on else 1)
		style.border_color = Color(1, 0.85, 0.3) if on else Color(1, 1, 1, 0.25)
		var swatch: Button = _swatches[colour_name]
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			swatch.add_theme_stylebox_override(state, style)


## The controls help ("?"), under the bar's right end; hidden until asked for.
func _help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8
	_help_scroll = ScrollContainer.new()  # (a short window or a big UI scale: it scrolls)
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_help_scroll)
	_help_box = VBoxContainer.new()
	_help_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_scroll.add_child(_help_box)
	_help_box.add_child(UiKit.heading("Map controls"))
	_help_box.add_child(WorldMapScreen.help_grid(HELP))
	UiKit.fit_width(_help_scroll, 400.0)
	return panel
