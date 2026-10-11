class_name Menu
extends CanvasLayer
## Host / join screen, with the role picker. Hidden once a session starts.

## Joining retries for a few seconds, so a second window started at the same moment as the
## host (Debug > Customize Run Instances) still gets in.
const JOIN_ATTEMPTS := 3
const JOIN_RETRY_S := 1.0

## Main-menu role picker (sets Roles.local_choice).
var role_picker: OptionButton
## People (wave 4): civilians, HVTs and intel in the compound when you host (PeopleLayer.populate).
var people_toggle: CheckBox
var _address: LineEdit
var _status: Label
var _join_address := ""
var _attempts_left := 0


func _ready() -> void:
	# Centred in the window, and scrollable when the window is too small for it (audit L8-01:
	# the panel used to start at the centre and run off a small window).
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "CONTRACTOR v%s (gray box)" % ProjectSettings.get_setting("application/config/version", "dev")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_role_picker())
	box.add_child(_hand_picker())
	box.add_child(_people_toggle())
	box.add_child(_button("Play (host a session)", _plain_host))
	box.add_child(_hint("Solo play is a session nobody else has joined."))
	box.add_child(_button("Play the test contract (briefing, extraction)", host_with_briefing))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address"
	box.add_child(_address)
	box.add_child(_button("Join someone's session", func() -> void: join(_address.text)))
	box.add_child(_button("Reset compound save", _reset_save))
	box.add_child(_button("Contract board (offline)", func() -> void: Contracts.open_board()))  # wave 4 economy, on its own
	# Wave 4 campaign (BaseHub): the company's FOB, its people and stash. Join (above) follows
	# the host into whatever it plays, the campaign included.
	box.add_child(_button("Campaign: host at the base (FOB)", _campaign_host))
	box.add_child(_button("Host test zone (2 km, world scale)", host_test_zone))
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
		_status.text = "Port %d is busy: is another copy of the game already hosting? Join it instead." % Net.port()
	else:
		_status.text = "Could not host on port %d (%s)." % [Net.port(), error_string(err)]


## Hosts the compound as a stand-in contract (W13 test path): the briefing on the map, then
## insertion, the reinforcement timer and extraction (Briefing.debug_open).
func host_with_briefing() -> void:
	host()
	if Net.is_hosting():
		Briefing.debug_open(self)


## Debug entry: hosts the 2 km test zone (data/zones.json "test") instead of the compound.
func host_test_zone() -> void:
	BaseHub.cancel_session()  # never a leftover campaign
	var main := get_parent()
	if main and main.has_method(&"host_zone"):
		GameState.zone_id = "zone_test"
		main.host_zone(ZoneDef.get_def("test"))


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


func _plain_host() -> void:
	BaseHub.cancel_session()  # never a leftover campaign
	host()


func _campaign_host() -> void:
	BaseHub.prepare_session()
	host()
	if not Net.is_hosting():
		BaseHub.cancel_session()


func _reset_save() -> void:
	GameState.delete_save()
	_status.text = "Compound save deleted."


## Your role in the squad (Roles), picked before hosting or joining; the host gets it on join.
func _role_picker() -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Your role"
	row.add_child(label)
	role_picker = OptionButton.new()
	role_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for role in Roles.ids():
		role_picker.add_item(Roles.display_name(role))
		role_picker.set_item_metadata(role_picker.item_count - 1, role)
		if role == Roles.local_choice:
			role_picker.select(role_picker.item_count - 1)
	role_picker.item_selected.connect(func(index: int) -> void: Roles.local_choice = role_picker.get_item_metadata(index))
	row.add_child(role_picker)
	return row


## Which shoulder you shoot from (Handedness), saved between sessions; the host gets it on join.
func _hand_picker() -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "You shoot"
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Right-handed")
	picker.add_item("Left-handed")
	picker.select(1 if Handedness.local_left() else 0)
	picker.item_selected.connect(func(index: int) -> void: Handedness.set_local_left(index == 1))
	row.add_child(picker)
	return row


## People (wave 4): host with the compound's civilians, HVTs and intel, and hostiles who may
## surrender (PeopleLayer.populate and surrender_enabled). Off: the compound as before.
func _people_toggle() -> CheckBox:
	people_toggle = CheckBox.new()
	people_toggle.text = "Civilians, HVTs and intel (wave 4 test)"
	people_toggle.button_pressed = PeopleLayer.populate
	people_toggle.toggled.connect(func(on: bool) -> void:
		PeopleLayer.populate = on
		PeopleLayer.surrender_enabled = on)
	return people_toggle


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
