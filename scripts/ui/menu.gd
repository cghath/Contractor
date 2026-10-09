class_name Menu
extends CanvasLayer
## Host / join screen. Hidden once a session starts.

## Joining retries for a few seconds, so a second window started at the same moment as the
## host (Debug > Customize Run Instances) still gets in.
const JOIN_ATTEMPTS := 3
const JOIN_RETRY_S := 1.0

var _address: LineEdit
var _status: Label
var _join_address := ""
var _attempts_left := 0


func _ready() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "CONTRACTOR v%s (gray box)" % ProjectSettings.get_setting("application/config/version", "dev")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_button("Play (host a session)", host))
	box.add_child(_hint("Solo play is a session nobody else has joined."))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address"
	box.add_child(_address)
	box.add_child(_button("Join someone's session", func() -> void: join(_address.text)))
	box.add_child(_button("Reset compound save", _reset_save))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	Net.joined.connect(hide)
	Net.join_failed.connect(_on_join_failed)


func host() -> void:
	var err := Net.host()
	if err == OK:
		hide()
	elif err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE:
		_status.text = "Port %d is busy: is another copy of the game already hosting? Join it instead." % Net.DEFAULT_PORT
	else:
		_status.text = "Could not host on port %d (%s)." % [Net.DEFAULT_PORT, error_string(err)]


func join(address: String) -> void:
	_join_address = address
	_attempts_left = JOIN_ATTEMPTS
	_try_join()


func _try_join() -> void:
	_attempts_left -= 1
	var err := Net.join(_join_address)
	if err == OK:
		_status.text = "Connecting to %s..." % _join_address
	else:
		_status.text = "Join failed (%s)." % error_string(err)


func _on_join_failed() -> void:
	if _attempts_left > 0:
		_status.text = "No host at %s yet, retrying..." % _join_address
		await get_tree().create_timer(JOIN_RETRY_S).timeout
		_try_join()
		return
	_status.text = "Could not connect to %s.\nJoin needs another copy of the game hosting at that address. To play on your own, use Play (host a session)." % _join_address


func _reset_save() -> void:
	GameState.delete_save()
	_status.text = "Compound save deleted."


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 13)
	label.modulate = Color(1, 1, 1, 0.6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
