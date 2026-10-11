class_name BriefingScreen
extends PanelContainer
## The briefing's side panel on the map (MapScreen): the contract, its objectives, how many
## enemy positions intel gives (red on the map), the insertion point, the supports to bring,
## who is ready, a Ready button for everyone and Start for the host. Plan marks are drawn on
## the map itself. Everything goes through Briefing's requests; the host decides.

const WIDTH := 360.0

var _briefing: Briefing
var _box: VBoxContainer
var _title: Label
var _summary: Label
var _objectives: Label
var _intel: Label
var _insertion: OptionButton
var _supports: VBoxContainer
var _players: Label
var _ready_button: Button
var _start: Button


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_box)
	_title = _add_label("", 20)
	_summary = _add_label("", 14)
	_add_label("OBJECTIVES", 13).modulate = Color(1, 1, 1, 0.6)
	_objectives = _add_label("", 14)
	_intel = _add_label("", 14)
	_add_label("INSERTION", 13).modulate = Color(1, 1, 1, 0.6)
	_insertion = OptionButton.new()
	_insertion.item_selected.connect(func(index: int) -> void:
		if _briefing:
			_briefing.request_insertion(String(_insertion.get_item_metadata(index))))
	_box.add_child(_insertion)
	_add_label("SUPPORTS (wave 5 builds them)", 13).modulate = Color(1, 1, 1, 0.6)
	_supports = VBoxContainer.new()
	_box.add_child(_supports)
	_add_label("PLAYERS", 13).modulate = Color(1, 1, 1, 0.6)
	_players = _add_label("", 14)
	_ready_button = Button.new()
	_ready_button.toggle_mode = true
	_ready_button.text = "Ready"
	_ready_button.toggled.connect(func(on: bool) -> void:
		if _briefing:
			_briefing.request_set_ready(on))
	_box.add_child(_ready_button)
	_start = Button.new()
	_start.text = "Start deployment"
	_start.pressed.connect(func() -> void:
		if _briefing:
			_briefing.request_start())
	_box.add_child(_start)
	_add_label("Plan on the map: double-click for a marker, Ctrl + drag for a line, drag to move, Delete to remove. Click a green triangle to pick the insertion point.", 12).modulate = Color(1, 1, 1, 0.6)


## Shows `briefing`'s state (call again whenever it changes).
func show_briefing(briefing: Briefing) -> void:
	_briefing = briefing
	if briefing == null:
		return
	var c := briefing.contract
	var stars := int(c.get("difficulty", 0))
	_title.text = String(c.get("title", "Contract")) + ("  " + "*".repeat(stars) if stars > 0 else "")
	_summary.text = String(c.get("summary", ""))
	var lines := PackedStringArray()
	for o: Dictionary in c.get("objectives", []):
		lines.append("- %s" % String(o.get("title", "")))
	_objectives.text = "\n".join(lines) if not lines.is_empty() else "(none given)"
	var known: int = c.get("known_enemies", []).size()
	_intel.text = "Intel: %d known enemy position%s (red on the map)" % [known, "" if known == 1 else "s"] if known > 0 else "Intel: no known enemy positions"
	_insertion.clear()
	for point: Dictionary in briefing.insertion_points():
		_insertion.add_item("%s (%s)" % [String(point.get("name", "")), String(point.get("method", "foot"))])
		_insertion.set_item_metadata(_insertion.item_count - 1, String(point.get("id", "")))
		if String(point.get("id", "")) == briefing.insertion_id:
			_insertion.select(_insertion.item_count - 1)
	for child in _supports.get_children():
		child.queue_free()
	for id: String in briefing.available_supports():
		var box := CheckBox.new()
		box.text = String(Briefing.SUPPORTS[id].name)
		box.set_pressed_no_signal(id in briefing.supports)
		box.toggled.connect(func(on: bool) -> void: briefing.request_support(id, on))
		_supports.add_child(box)
	var me := multiplayer.get_unique_id()
	var who := PackedStringArray()
	for id: int in briefing.session_peers():
		who.append("%s: %s" % ["You" if id == me else "Player %d" % id, "ready" if briefing.ready_peers.has(id) else "not ready"])
	_players.text = "\n".join(who)
	_ready_button.set_pressed_no_signal(briefing.ready_peers.has(me))
	_ready_button.text = "Ready (click to stand down)" if _ready_button.button_pressed else "Ready"
	_start.visible = multiplayer.is_server()
	_start.disabled = not briefing.all_ready()


func _add_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 30.0, 0)
	label.add_theme_font_size_override(&"font_size", font_size)
	_box.add_child(label)
	return label
