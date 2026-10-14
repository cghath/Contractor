class_name MapScreen
extends Control
## The full-screen map (M): MapView, a toolbar (marker colour and kind, the grid reference
## under the cursor) and side panels: the briefing while one is open, extraction while a
## deployment is on. The briefing opens it on every player's screen and keeps it open until
## the deployment starts. Lives on the local player's HUD; while it's open the mouse is free
## and you stand still, as with the inventory screen.

const COLOUR_ORDER: Array[String] = ["black", "red", "blue", "green", "orange", "purple", "white"]
const TOOLBAR_HEIGHT := 44.0

var player: Soldier
var view: MapView
var briefing_panel: BriefingScreen
var toolbar: PanelContainer
var extraction_panel: MapExtractionPanel
var _reference: Label
var _kind: OptionButton
var _swatches := {}  # colour name -> its Button
var _help: PanelContainer
var _help_button: Button
var _close_button: Button
var _level: Node
var _forced := false  # opened by the briefing


func _init(p_player: Soldier = null) -> void:
	player = p_player
	name = "MapScreen"


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = MapView.BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = MapView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_top = TOOLBAR_HEIGHT
	view.cursor_moved.connect(func(ref: String) -> void: _reference.text = "Grid %s" % ref)
	toolbar = _toolbar()
	add_child(toolbar)
	_help = _help_panel()
	add_child(_help)
	briefing_panel = BriefingScreen.new()
	briefing_panel.visible = false
	add_child(briefing_panel)
	briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	# Captain, 2026-10-14 (B0912): the panel ran off the window's right edge. It grows to the
	# left if anything in it is ever wider, and its width follows the window (_layout_panels).
	briefing_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	briefing_panel.offset_top = TOOLBAR_HEIGHT + 8
	briefing_panel.offset_bottom = -8
	briefing_panel.offset_right = -8
	extraction_panel = MapExtractionPanel.new()
	extraction_panel.visible = false
	add_child(extraction_panel)
	extraction_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	extraction_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	extraction_panel.offset_left = -MapExtractionPanel.WIDTH - 8
	extraction_panel.offset_top = TOOLBAR_HEIGHT + 8
	extraction_panel.offset_right = -8
	resized.connect(_layout_panels)
	_layout_panels()
	_connect_level.call_deferred()


## The briefing panel's width for this window (BriefingScreen.width_for), and the map beside it.
func _layout_panels() -> void:
	if briefing_panel == null:
		return
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
	if _forced:
		return
	visible = false
	if player == null or player._hud == null or not player._hud.is_inventory_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"inventory"):
		get_viewport().set_input_as_handled()  # one screen at a time: the inventory would take the mouse back


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
	_refresh_inset()


## The map fills what the toolbar and the side panel leave.
func _refresh_inset() -> void:
	var inset := 0.0
	if briefing_panel.visible:
		inset = briefing_panel.custom_minimum_size.x + 16.0
	elif extraction_panel.visible:
		inset = MapExtractionPanel.WIDTH + 16.0
	if view.offset_right != -inset:
		view.offset_right = -inset
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
	panel.offset_bottom = TOOLBAR_HEIGHT
	panel.clip_contents = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = "MAP"
	title.add_theme_font_size_override(&"font_size", 18)
	row.add_child(title)
	row.add_child(VSeparator.new())
	_reference = Label.new()
	_reference.custom_minimum_size = Vector2(140, 0)
	_reference.text = "Grid ----"
	_reference.tooltip_text = "The grid reference under the cursor"
	row.add_child(_reference)
	row.add_child(VSeparator.new())
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
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_help_button = Button.new()
	_help_button.text = "Controls"
	_help_button.toggle_mode = true
	_help_button.tooltip_text = "Show the map's mouse and key controls"
	_help_button.toggled.connect(func(on: bool) -> void: _help.visible = on)
	row.add_child(_help_button)
	_close_button = Button.new()
	_close_button.text = "Close  [M]"
	_close_button.pressed.connect(close)
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


## The controls help, under the bar's right end; hidden until Controls is pressed.
func _help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = TOOLBAR_HEIGHT + 8
	panel.offset_right = -8
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 14)
	panel.add_child(grid)
	for pair: Array in [["Wheel", "zoom"], ["Right drag", "pan"], ["Double-click", "place a marker"], ["Ctrl + drag", "draw a line"],
			["Drag a marker", "move it"], ["Delete", "remove the marker under the cursor"], ["Right click", "menu (marker, enemy, extraction point)"]]:
		var key := Label.new()
		key.text = pair[0]
		key.modulate = Color(1, 0.85, 0.4)
		grid.add_child(key)
		var what := Label.new()
		what.text = pair[1]
		grid.add_child(what)
	return panel
