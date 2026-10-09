class_name Menu
extends CanvasLayer
## Host / join screen. Hidden once a session starts.

var _address: LineEdit
var _status: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "CONTRACTOR (gray box)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_button("Host co-op", host))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address"
	box.add_child(_address)
	box.add_child(_button("Join", func() -> void: join(_address.text)))
	box.add_child(_button("Reset compound save", _reset_save))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	Net.joined.connect(hide)
	Net.join_failed.connect(func() -> void: _status.text = "Could not connect.")


func host() -> void:
	var err := Net.host()
	if err == OK:
		hide()
	else:
		_status.text = "Could not host on port %d (%s)." % [Net.DEFAULT_PORT, error_string(err)]


func join(address: String) -> void:
	var err := Net.join(address)
	_status.text = "Connecting to %s..." % address if err == OK else "Join failed (%s)." % error_string(err)


func _reset_save() -> void:
	GameState.delete_save()
	_status.text = "Compound save deleted."


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button
