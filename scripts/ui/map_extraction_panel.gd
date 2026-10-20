class_name MapExtractionPanel
extends PanelContainer
## The extraction side panel on the map (MapScreen) while a deployment is on: the extraction
## points, which AI squadmates come along (untick to leave one behind), what's happening,
## and the Extract button that confirms once the squad is at a point (Captain, 2026-10-14: any
## player standing inside a point, not only the host; the host says why when it can't).
## Points are set on the map (right click) or by throwing a purple smoke. In the shared look
## (UiKit, from MapScreen): nothing under 14 px.

const WIDTH := 300.0

var _extraction: Extraction
var _box: VBoxContainer
var _points: Label
var _status: Label
var _mates: VBoxContainer
var _confirm: Button


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	add_child(_box)
	_add_label("EXTRACTION", &"HeadingLabel")
	_points = _add_label("")
	_add_label("Bring along (untick to leave behind):", &"HintLabel")
	_mates = VBoxContainer.new()
	_box.add_child(_mates)
	_status = _add_label("")
	_confirm = Button.new()
	_confirm.text = "Extract (squad at the point)"
	_confirm.pressed.connect(func() -> void:
		if _extraction:
			_extraction.request_confirm())
	_box.add_child(_confirm)
	_add_label("Right click the map for a grid extraction point, or throw a purple smoke.", &"HintLabel")
	# Captain, 2026-10-14: walking out only at the zone's edge.
	_add_label("On foot only at the zone edge; further in a point is a helicopter LZ. Or drive out across the edge.", &"HintLabel")


## Shows `extraction`'s state (call again whenever it changes).
func show_extraction(extraction: Extraction) -> void:
	_extraction = extraction
	if extraction == null:
		return
	var area := MapNodes.area_of(self)
	var lines := PackedStringArray()
	for point: Dictionary in extraction.shown_points():  # a helicopter extraction: its LZ only
		lines.append("%s  %s" % [point.name, MapGrid.grid_ref(point.pos, area)])
	_points.text = "\n".join(lines) if not lines.is_empty() else "No extraction point yet"
	var names := MapNodes.squad_ai(self).map(func(s: Soldier) -> String: return String(s.name))
	if _mates.get_child_count() != names.size() or _mates.get_children().any(func(c: Node) -> bool: return (c as CheckBox).text not in names):
		for child in _mates.get_children():
			child.queue_free()
			_mates.remove_child(child)
		for mate: String in names:
			var box := CheckBox.new()
			box.text = mate
			box.toggled.connect(func(on: bool) -> void: extraction.request_bring(mate, on))
			_mates.add_child(box)
	for child in _mates.get_children():
		var box := child as CheckBox
		box.set_pressed_no_signal(not extraction.leave.has(box.text))
	match extraction.state:
		Extraction.State.COUNTDOWN:
			_status.text = "Extracting in %d s: stay inside" % ceili(extraction.countdown_left)
		Extraction.State.ENDED:
			_status.text = Extraction.summary(extraction.last_report)
		_:
			_status.text = ""
	_confirm.visible = extraction.state == Extraction.State.ACTIVE


## A wrapping line of text in label style `variation` ("" for body text).
func _add_label(text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # (the panel's width, less the theme's padding)
	if variation != &"":
		label.theme_type_variation = variation
	_box.add_child(label)
	return label
