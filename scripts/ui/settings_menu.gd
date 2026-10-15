class_name SettingsMenu
extends CanvasLayer
## The settings screen (Captain, 2026-10-13): tabs for Video, Audio, Controls and Keys, opened
## from the main menu and the Escape menu. Every change takes effect at once and is saved
## (GameSettings); the shooting hand (Handedness) and the get-out key (ControlOptions) are on
## the Controls tab too. Escape or Close goes back to whatever opened it.

signal closed

var _tabs: TabContainer
## The Keys tab's buttons, by action, and the action waiting for a key press (or &"").
var _key_buttons := {}
var _listening := &""
var _key_status: Label


func _init() -> void:
	name = "SettingsMenu"
	layer = 30
	visible = false


func _ready() -> void:
	# The shared look (UiKit; Captain, 2026-10-14: "all of the UIs need a pass"). Opaque (solid):
	# whatever opened it doesn't show through. Its size follows the window: the old fixed 620x560
	# ran off a 1280x720 or 1366x768 window at a 150% Menu and HUD size (tests/ui_test.gd).
	add_child(UiKit.dim(0.7))
	var box := UiKit.screen(self, 680.0, true)
	UiKit.fit_height(box, 560.0, 40.0)
	box.add_child(UiKit.title("Settings"))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_build()
	var reset := UiKit.button("Reset everything to defaults", func() -> void:
		GameSettings.reset_all()
		_rebuild())
	var done := UiKit.button("Close", close)
	var row := HBoxContainer.new()
	var keys := UiKit.key_hint("Esc", "Close")
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(keys)
	row.add_child(UiKit.button_row([reset, done], true))
	(row.get_child(1) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)


func is_open() -> bool:
	return visible


func open() -> void:
	_rebuild()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_listening = &""
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening != &"" and event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		# A side or middle mouse button (the left and right ones fire and aim; P0362).
		get_viewport().set_input_as_handled()
		var code := GameSettings.MOUSE_BIND | int((event as InputEventMouseButton).button_index)
		var moved := GameSettings.bind(_listening, code)
		_key_status.text = "%s on %s%s." % [_label_of(_listening), GameSettings.binding_name(code),
			(", %s moved to %s" % [_label_of(moved), GameSettings.binding_name(GameSettings.key_for(moved))]) if moved != &"" else ""]
		_listening = &""
		_refresh_keys()
	elif _listening != &"" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			_key_status.text = "Kept %s on %s." % [_label_of(_listening), GameSettings.binding_name(GameSettings.key_for(_listening))]
		elif key in [KEY_CTRL, KEY_ALT, KEY_META]:
			_key_status.text = "Ctrl and Alt hold the interaction menus: pick another key."
			return
		else:
			var swapped := GameSettings.bind(_listening, key)
			_key_status.text = "%s on %s%s." % [_label_of(_listening), OS.get_keycode_string(key),
				(", %s moved to %s" % [_label_of(swapped), GameSettings.binding_name(GameSettings.key_for(swapped))]) if swapped != &"" else ""]
		_listening = &""
		_refresh_keys()
	elif event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


# --- Building the tabs ------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_build()


func _build() -> void:
	_key_buttons = {}
	_tabs.add_child(_video_tab())
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_controls_tab())
	_tabs.add_child(_keys_tab())


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 6)
	scroll.add_child(page)
	return page


func _video_tab() -> Control:
	var page := _page("Video")
	page.add_child(_choice("Window", "video", "window_mode", GameSettings.WINDOW_MODES))
	var sizes := GameSettings.RESOLUTIONS.map(func(r: String) -> Array: return [r, r.replace("x", " x ")])
	page.add_child(_choice("Window size (windowed)", "video", "resolution", sizes))
	page.add_child(_toggle("VSync (no tearing; caps the frame rate at the screen's)", "video", "vsync"))
	page.add_child(_choice("Frame rate cap", "video", "fps_cap", GameSettings.FPS_CAPS))
	page.add_child(_slider("Render scale (lower is faster, softer)", "video", "render_scale", func(v: float) -> String: return "%d%%" % roundi(v * 100.0)))
	page.add_child(_choice("Anti-aliasing", "video", "antialiasing", GameSettings.ANTIALIASING))
	page.add_child(_choice("Shadows", "video", "shadows", GameSettings.SHADOWS))
	page.add_child(_slider("Field of view", "video", "fov", func(v: float) -> String: return "%d deg" % roundi(v)))
	page.add_child(_slider("Menu and HUD size", "video", "ui_scale", func(v: float) -> String: return "%d%%" % roundi(v * 100.0)))
	page.add_child(_toggle("Objective markers on screen (the hint line always shows)", "hud", "objective_markers"))
	return page.get_parent()


func _audio_tab() -> Control:
	var page := _page("Audio")
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	page.add_child(_slider("Master volume", "audio", "master", pct))
	page.add_child(_slider("Effects (guns, blasts, footsteps)", "audio", "effects", pct))
	page.add_child(_slider("Voices and radio", "audio", "voice", pct))
	page.add_child(_slider("Music", "audio", "music", pct))
	page.add_child(_toggle("Infil music (Ride of the Valkyries)", "audio", "infil_music"))  # Captain, 2026-10-14: temporary
	page.add_child(_toggle("Mute when the game window isn't in front", "audio", "mute_unfocused"))
	return page.get_parent()


func _controls_tab() -> Control:
	var page := _page("Controls")
	var times := func(v: float) -> String: return "%.2fx" % v
	page.add_child(_slider("Mouse sensitivity", "controls", "mouse_sensitivity", times))
	page.add_child(_slider("Aiming sensitivity (down sights, on top)", "controls", "aim_sensitivity", times))
	page.add_child(_toggle("Invert mouse up and down", "controls", "invert_y"))
	var hand := _row("You shoot")
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Right-handed")
	picker.add_item("Left-handed")
	picker.select(1 if Handedness.local_left() else 0)
	picker.item_selected.connect(func(index: int) -> void: Handedness.set_local_left(index == 1))
	hand.add_child(picker)
	page.add_child(hand)
	page.add_child(ControlOptions.get_out_toggle())
	return page.get_parent()


func _keys_tab() -> Control:
	var page := _page("Keys")
	_key_status = Label.new()
	_key_status.text = "Click a key, then press the new one, or a side or middle mouse button (Escape keeps it). Taken keys swap."
	_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	page.add_child(_key_status)
	for pair: Array in GameSettings.BINDABLE:
		var action: StringName = pair[0]
		var row := _row(String(pair[1]))
		var button := Button.new()
		button.custom_minimum_size = Vector2(160, 0)
		button.pressed.connect(func() -> void:
			_listening = action
			_refresh_keys()
			button.text = "Press a key...")
		row.add_child(button)
		_key_buttons[action] = button
		page.add_child(row)
	var fixed := Label.new()
	fixed.text = "Fixed: Escape (menu), Left Ctrl / Ctrl+Alt (interaction), left and right mouse buttons (fire, aim), Shift+H (treat yourself), F-keys (squad commands)."
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD
	fixed.theme_type_variation = &"HintLabel"
	page.add_child(fixed)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(func() -> void:
		GameSettings.reset_keys()
		_listening = &""
		_key_status.text = "Keys back to defaults."
		_refresh_keys())
	page.add_child(reset)
	_refresh_keys()
	return page.get_parent()


func _refresh_keys() -> void:
	for action: StringName in _key_buttons:
		(_key_buttons[action] as Button).text = GameSettings.binding_name(GameSettings.key_for(action))


func _label_of(action: StringName) -> String:
	for pair: Array in GameSettings.BINDABLE:
		if pair[0] == action:
			return String(pair[1])
	return String(action)


# --- Controls ---------------------------------------------------------------------------------

func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(240, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row


## A dropdown of `options` ([value, label]) for a setting.
func _choice(text: String, section: String, key: String, options: Array) -> Control:
	var row := _row(text)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var now: Variant = GameSettings.get_value(section, key)
	for option: Array in options:
		picker.add_item(String(option[1]))
		if str(option[0]) == str(now):
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: GameSettings.set_value(section, key, options[index][0]))
	row.add_child(picker)
	return row


func _toggle(text: String, section: String, key: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = bool(GameSettings.get_value(section, key))
	check.toggled.connect(func(on: bool) -> void: GameSettings.set_value(section, key, on))
	return check


## A slider over the setting's range (GameSettings.RANGES) with its value shown by `shown`.
func _slider(text: String, section: String, key: String, shown: Callable) -> Control:
	var row := _row(text)
	var range_spec: Array = GameSettings.RANGES[key]
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = range_spec[0]
	slider.max_value = range_spec[1]
	slider.step = range_spec[2]
	slider.value = float(GameSettings.get_value(section, key))
	var value := Label.new()
	value.custom_minimum_size = Vector2(64, 0)
	value.text = shown.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void: value.text = shown.call(v))
	# Saved when the drag ends (or on a click/arrow key), not on every step of a drag.
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			GameSettings.set_value(section, key, slider.value))
	slider.value_changed.connect(func(v: float) -> void:
		if not slider.has_meta(&"dragging"):
			GameSettings.set_value(section, key, v))
	slider.drag_started.connect(func() -> void: slider.set_meta(&"dragging", true))
	slider.drag_ended.connect(func(_changed: bool) -> void: slider.remove_meta(&"dragging"))
	row.add_child(slider)
	row.add_child(value)
	return row
