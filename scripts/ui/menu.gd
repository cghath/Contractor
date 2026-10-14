class_name Menu
extends CanvasLayer
## Host / join screen, with the role picker. Hidden once a session starts.

## Joining retries for a few seconds, so a second window started at the same moment as the
## host (Debug > Customize Run Instances) still gets in.
const JOIN_ATTEMPTS := 3
const JOIN_RETRY_S := 1.0
## "New campaign" asks for a second click within this many seconds before it archives.
const CONFIRM_S := 5.0
## The plain session's zone save (Play (host a session)), apart from any campaign's.
const PLAIN_ZONE_ID := "compound_01"
const NEW_CAMPAIGN_TEXT := "New campaign (archive current saves)"
const NEW_CAMPAIGN_CONFIRM := "Click again to archive the campaign and start a new one"

## Main-menu role picker (sets Roles.local_choice).
var role_picker: OptionButton
var _address: LineEdit
var _status: Label
## The settings screen (GameSettings), over the menu.
var settings_menu: SettingsMenu
var _join_address := ""
var _attempts_left := 0
## The "New campaign" button; armed (waiting for the confirming click) until _armed_until.
var new_campaign_button: Button
var _armed_until := 0.0


func _ready() -> void:
	# People (wave 4) are always on in play (Captain, 2026-10-13: no checkbox): civilians, HVTs
	# and intel in the compound, and hostiles who may surrender. Contracts bring their own
	# people either way. Headless runs (the test suites) keep them off unless a test sets them.
	if DisplayServer.get_name() != "headless":
		PeopleLayer.populate = true
		PeopleLayer.surrender_enabled = true
	GameSettings.apply_all()  # the saved video, audio and key settings, from the start
	settings_menu = SettingsMenu.new()
	add_child(settings_menu)
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
	box.add_child(ControlOptions.get_out_toggle())  # the get-out key (an option, saved)
	box.add_child(_button("Settings", func() -> void: settings_menu.open()))
	box.add_child(_button("Play (host a session)", _plain_host))
	box.add_child(_hint("Solo play is a session nobody else has joined."))
	box.add_child(_button("Play the test contract (briefing, extraction)", host_with_briefing))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address"
	box.add_child(_address)
	box.add_child(_button("Join someone's session", func() -> void: join(_address.text)))
	# Only the plain session's compound (the test contract starts fresh on its own); the
	# campaign's saves are the "New campaign" button's (Captain, 2026-10-14: this button was
	# taken for a campaign reset and left KIA mercs, bodies and vehicles in place).
	box.add_child(_button("Reset plain-session compound save (not the campaign)", _reset_save))
	box.add_child(_button("Contract board (offline)", func() -> void: Contracts.open_board()))  # wave 4 economy, on its own
	# Wave 4 campaign (BaseHub): the company's FOB, its people and stash. Join (above) follows
	# the host into whatever it plays, the campaign included.
	box.add_child(_button("Campaign: host at the base (FOB)", _campaign_host))
	new_campaign_button = _button(NEW_CAMPAIGN_TEXT, new_campaign_pressed)
	new_campaign_button.tooltip_text = "Moves the campaign save and all its zone saves into an archive folder (nothing is deleted); the next campaign host starts a new company"
	box.add_child(new_campaign_button)
	box.add_child(_button("Host test zone (2 km, world scale)", host_test_zone))
	# Procedural towns to look at without waiting for the board to offer them (Captain, 2026-10-13).
	box.add_child(_button("Host Old Quarter (city hot zone, test)", func() -> void: host_campaign_zone("city_hot")))
	box.add_child(_button("Host Harbour yard (town, test)", func() -> void: host_campaign_zone("harbour_yard")))
	box.add_child(_button("Host vehicle range (wave 5)", func() -> void: VehicleRange.host_from_menu(self)))
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
	BaseHub.cancel_session()
	GameState.delete_save()  # the test contract starts fresh every time: no bodies or drops from last time
	_clean_test_session()
	host()
	if Net.is_hosting():
		Briefing.debug_open(self)


## Debug entry: hosts the 2 km test zone (data/zones.json "test") instead of the compound.
func host_test_zone() -> void:
	BaseHub.cancel_session()  # never a leftover campaign
	_clean_test_session()
	var main := get_parent()
	if main and main.has_method(&"host_zone"):
		GameState.zone_id = "zone_test"
		main.host_zone(ZoneDef.get_def("test"))


## Debug entry: hosts one of the campaign's zones (MissionRegistry.zone_def) on its own, no
## contract, under a save of its own ("test_<zone>") so the campaign's zone save is untouched.
func host_campaign_zone(zone_id: String) -> void:
	BaseHub.cancel_session()  # never a leftover campaign
	_clean_test_session()
	var main := get_parent()
	var def := MissionRegistry.zone_def(zone_id)
	if main and main.has_method(&"host_zone") and not def.is_empty():
		GameState.zone_id = "test_" + zone_id
		main.host_zone(def)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		GameSettings.focus_changed(what == NOTIFICATION_APPLICATION_FOCUS_IN)


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
	_clean_test_session()
	host()


## The play and test entries (not the test suites, which host through host()): players come
## in their role's kit, and the level lays out its clean loot (CompoundLevel.CLEAN_LOOT).
static func _clean_test_session() -> void:
	CompoundLevel.player_role_kits = true
	CompoundLevel.clean_loot = true


func _campaign_host() -> void:
	CompoundLevel.player_role_kits = false  # the campaign gives each player their own gear
	CompoundLevel.clean_loot = false
	BaseHub.prepare_session()
	host()
	if not Net.is_hosting():
		BaseHub.cancel_session()


## Deletes the plain session's compound save (PLAIN_ZONE_ID), whatever zone the last session
## left GameState.zone_id on. Never a campaign's.
func _reset_save() -> void:
	var was := GameState.zone_id
	GameState.zone_id = PLAIN_ZONE_ID
	GameState.delete_save()
	GameState.zone_id = was
	_status.text = "Plain-session compound save deleted (the campaign is untouched)."


## "New campaign (archive current saves)": the first click asks, a second within CONFIRM_S
## archives the campaign (BaseHub.archive_campaign: moved, never deleted).
func new_campaign_pressed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now > _armed_until:
		_armed_until = now + CONFIRM_S
		new_campaign_button.text = NEW_CAMPAIGN_CONFIRM
		_status.text = "This archives the current campaign (its save and every zone save) and the next campaign host starts a new company. Click again within %d s to go ahead." % int(CONFIRM_S)
		get_tree().create_timer(CONFIRM_S).timeout.connect(func() -> void:
			if Time.get_ticks_msec() / 1000.0 >= _armed_until and is_instance_valid(new_campaign_button):
				new_campaign_button.text = NEW_CAMPAIGN_TEXT)
		return
	_armed_until = 0.0
	new_campaign_button.text = NEW_CAMPAIGN_TEXT
	var done := BaseHub.archive_campaign()
	if (done.moved as Array).is_empty() and (done.failed as Array).is_empty():
		_status.text = "No campaign saves to archive: the next campaign host starts a new company."
	elif (done.failed as Array).is_empty():
		_status.text = "Campaign archived (%d files) in %s. The next campaign host starts a new company." % [(done.moved as Array).size(), done.dir]
	else:
		_status.text = "Archived %d files in %s, but %s couldn't be moved and stay in the saves folder." % [(done.moved as Array).size(), done.dir,
			", ".join(PackedStringArray(done.failed))]


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
