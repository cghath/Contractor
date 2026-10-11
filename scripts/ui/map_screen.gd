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
var extraction_panel: MapExtractionPanel
var _reference: Label
var _kind: OptionButton
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
	add_child(_toolbar())
	briefing_panel = BriefingScreen.new()
	briefing_panel.visible = false
	add_child(briefing_panel)
	briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	briefing_panel.offset_left = -BriefingScreen.WIDTH - 8
	briefing_panel.offset_top = TOOLBAR_HEIGHT + 8
	briefing_panel.offset_bottom = -8
	briefing_panel.offset_right = -8
	extraction_panel = MapExtractionPanel.new()
	extraction_panel.visible = false
	add_child(extraction_panel)
	extraction_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	extraction_panel.offset_left = -MapExtractionPanel.WIDTH - 8
	extraction_panel.offset_top = TOOLBAR_HEIGHT + 8
	extraction_panel.offset_right = -8
	_connect_level.call_deferred()


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
	# The map fills what the toolbar and the side panel leave.
	var inset := 0.0
	if briefing_panel.visible:
		inset = BriefingScreen.WIDTH + 16.0
	elif extraction_panel.visible:
		inset = MapExtractionPanel.WIDTH + 16.0
	if view.offset_right != -inset:
		view.offset_right = -inset


func _process(_delta: float) -> void:
	if visible and extraction_panel.visible and Engine.get_process_frames() % 30 == 0:
		_refresh_panels()  # the squad list changes as squadmates fall


func _toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = TOOLBAR_HEIGHT
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	panel.add_child(row)
	var title := Label.new()
	title.text = "MAP  [M] close"
	row.add_child(title)
	_reference = Label.new()
	_reference.custom_minimum_size = Vector2(150, 0)
	_reference.text = "Grid ----"
	row.add_child(_reference)
	_kind = OptionButton.new()
	_kind.add_item("Marker")
	_kind.add_item("Enemy")
	_kind.item_selected.connect(func(index: int) -> void: view.marker_kind = "enemy" if index == 1 else "point")
	row.add_child(_kind)
	for colour_name in COLOUR_ORDER:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.tooltip_text = colour_name.capitalize()
		var style := StyleBoxFlat.new()
		style.bg_color = MapMarkers.colour_value(colour_name)
		swatch.add_theme_stylebox_override(&"normal", style)
		swatch.add_theme_stylebox_override(&"hover", style)
		swatch.pressed.connect(func() -> void: view.marker_colour = colour_name)
		row.add_child(swatch)
	var help := Label.new()
	help.text = "Wheel: zoom   Right drag: pan   Double-click: marker   Ctrl+drag: line   Del: remove   Right click: menu"
	help.modulate = Color(1, 1, 1, 0.6)
	row.add_child(help)
	return panel
