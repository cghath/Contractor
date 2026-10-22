class_name SettingsMenu
extends CanvasLayer
## The settings screen (Captain, 2026-10-13): tabs for Video, Audio, Controls and Keys, opened
## from the main menu and the Escape menu. Every change takes effect at once and is saved
## (GameSettings); the shooting hand (Handedness) and the get-out key (ControlOptions) are on
## the Controls tab too. Escape or Close goes back to whatever opened it.

signal closed

## Every setting's tooltip, in plain words (ui-modern, Captain 2026-10-20: "all menus should
## have better explanations").
const TIPS := {
	"window_mode": "Windowed, a borderless window the size of the screen, or exclusive fullscreen (can be a little faster, slower to switch away from).",
	"resolution": "The window's size when windowed. Fullscreen modes use the screen's own size.",
	"vsync": "Waits for the screen before showing each frame: no tearing, but the frame rate stops at the screen's refresh rate.",
	"fps_cap": "The most frames a second the game draws. Lower keeps the PC cooler and quieter.",
	"render_scale": "How many pixels the 3D view is drawn with. Lower is faster and softer; over 100% is sharper far off and slower. Menus and the HUD stay sharp either way.",
	"antialiasing": "Smooths jagged edges. FXAA is cheap; MSAA smooths edges; TAA steadies thin far-off detail (trees, wires) but can blur a little in motion.",
	"shadows": "How sharp shadows are and how far out they're drawn. Higher costs more frame rate.",
	"hfov": "How wide you see, across the screen. Wider shows more at the sides but makes far things smaller.",
	"head_bob": "The view moves a little with your steps. Off keeps it steady.",
	"detail": "How far out the woods, rocks and scrub are drawn. Ultra draws the tree canopy to the horizon; High stops it at about 3 km and drops far soldiers' shadows; Medium and Low draw less far out for more frame rate. Up close they all look the same. Takes effect in the next zone.",
	"gore": "How bodies show wounds: Full shows torn limbs, bone and blast damage; Reduced keeps the wounds and lost limbs without bone or gibs; Off draws bodies whole.",
	"ui_scale": "Makes every menu and the HUD bigger or smaller, on top of the size the window picks by itself.",
	"master": "The volume of everything.",
	"effects": "Guns, explosions, footsteps, vehicles and the world.",
	"voice": "Squadmates' callouts, the radio and other voices.",
	"music": "Music, when there is any.",
	"infil_music": "Music on helicopter insertions.",
	"mute_unfocused": "No sound while another window is in front of the game.",
	"mouse_sensitivity": "How fast the view turns with the mouse.",
	"aim_sensitivity": "How fast the view turns while aiming down sights, on top of the mouse sensitivity.",
	"invert_y": "Mouse forward looks down instead of up.",
	"stick_sensitivity": "How fast the view turns with the right stick.",
	"stick_deadzone": "How far the stick must move before it counts (stops a worn stick drifting).",
	"stick_curve": "Higher makes small stick moves finer for aiming, with full speed still at the edge.",
	"stick_invert_y": "Stick forward looks down instead of up.",
	"objective_markers": "Diamonds over where the current objective is, with how far it is. Off: only the hint line under the objectives.",
	"objectives_expanded": "Show every objective in the top-right list, or only the one you're on.",
}

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
	box.add_child(UiKit.header("Settings", "Video, sound, controls, keys and the HUD. Every change takes effect at once and is saved.",
		PackedStringArray(["Pick a tab along the top. Sliders save when you let go; drop-downs and boxes save at once.",
			"Hover any setting for what it does. The Keys tab rebinds keys: click one, then press the new key (Esc keeps the old one).",
			"The HUD tab sets how big and how see-through each part of the HUD is; Reset HUD layout puts them back.",
			"Reset everything to defaults puts every setting and key back (it can't be undone)."]),
		[["Esc", "Close"], ["Tab / arrows", "Move"], ["Enter", "Change"]]))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_build()
	var reset := UiKit.danger_button("Reset everything to defaults", func() -> void:
		UiKit.confirm(self, "Every setting and key binding goes back to its default.", "Reset everything", func() -> void:
			GameSettings.reset_all()
			_rebuild()), "Every setting and key back to its default (asks first)")
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
	_tabs.add_child(_hud_tab())


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
	page.add_child(_slider("Render scale (lower is faster, softer; over 100% supersamples: sharper far off, slower)", "video", "render_scale", func(v: float) -> String: return "%d%%" % roundi(v * 100.0)))
	page.add_child(_choice("Anti-aliasing", "video", "antialiasing", GameSettings.ANTIALIASING))
	page.add_child(_choice("Shadows", "video", "shadows", GameSettings.SHADOWS))
	page.add_child(_slider("Field of view (across, 16:9)", "video", "hfov", func(v: float) -> String: return "%d deg" % roundi(v)))
	page.add_child(_toggle("Head bob (the view moves with your steps)", "video", "head_bob"))
	page.add_child(_choice("Scope picture-in-picture (magnified optics)", "video", "scope_pip", GameSettings.SCOPE_PIP))
	page.add_child(_choice("Gore", "video", "gore", GameSettings.GORE))
	page.add_child(_choice("World detail at distance", "video", "detail", GameSettings.DETAIL))
	page.add_child(_ui_scale_row())
	return page.get_parent()


## The HUD tab (ui-modern, Captain 2026-10-20: "common sense layout tools"): the markers and the
## objectives list, then each part's size and opacity (HudLayout), and a reset.
func _hud_tab() -> Control:
	var page := _page("HUD")
	page.add_child(UiKit.hint("What shows over the game view, and how big and how see-through each part is. Changes show at once, behind this menu."))
	page.add_child(_toggle("Objective markers on screen (the hint line always shows)", "hud", "objective_markers",
		"Diamonds over where the current objective is, with how far it is. Off: only the hint line under the objectives."))
	page.add_child(_toggle("Spot reports in the world", "hud", "spot_diamonds",
		"A diamond over each enemy your side has reported that you can't see yourself: red your tags, amber the rest, fading with age."))
	page.add_child(_slider("Spot reports out to", "hud", "spot_diamond_range_m", func(v: float) -> String: return "%d m" % roundi(v)))
	page.add_child(_toggle("Objectives list starts in full (else one line)", "hud", "objectives_expanded",
		"Show every objective in the top-right list, or only the one you're on (the objectives list key switches it in play)."))
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	for e: Array in HudLayout.ELEMENTS:
		var id := String(e[0])
		page.add_child(UiKit.heading(String(e[1])))
		if bool(e[2]):
			page.add_child(_slider("Size", "hud", id + "_scale", pct, HudLayout.SCALE_RANGE,
				"How big this part is drawn (100% is the normal size; it keeps its corner of the screen)."))
		page.add_child(_slider("Opacity", "hud", id + "_opacity", pct, HudLayout.OPACITY_RANGE,
			"How solid this part is drawn: lower lets more of the world show through."))
	var reset := UiKit.button("Reset HUD layout", func() -> void:
		HudLayout.reset()
		_rebuild()
		_tabs.current_tab = _tabs.get_tab_count() - 1, "Every HUD part back to full size and opacity")
	reset.name = "ResetHud"
	page.add_child(reset)
	return page.get_parent()


## The Menu and HUD size slider and, under it, what this window picks by itself and the size
## that makes (docs/ui_audit.md P1-7: the window height sets the UI scale, the setting
## multiplies it; GameSettings.ui_scale_for).
func _ui_scale_row() -> Control:
	var box := VBoxContainer.new()
	var row := _slider("Menu and HUD size (times the window's own)", "video", "ui_scale", func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	box.add_child(row)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"HintLabel"
	box.add_child(note)
	var show := func(v: float) -> void:
		var window := get_tree().root.size if is_inside_tree() else DisplayServer.window_get_size()
		note.text = "This %d x %d window picks %d%% by itself, so the menus and HUD are at %d%%." % [
			window.x, window.y, roundi(GameSettings.auto_ui_scale(window) * 100.0), roundi(GameSettings.ui_scale_for(window, v) * 100.0)]
	var slider := row.get_child(1) as HSlider
	slider.value_changed.connect(show)
	show.call(slider.value)
	return box


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
	# The gamepad's right stick (wave 7, S4; GameSettings.stick_look).
	page.add_child(UiKit.heading("Gamepad"))
	page.add_child(_slider("Stick look sensitivity", "gamepad", "stick_sensitivity", times))
	page.add_child(_slider("Stick deadzone (ignored near the middle)", "gamepad", "stick_deadzone", func(v: float) -> String: return "%d%%" % roundi(v * 100.0)))
	page.add_child(_slider("Stick response curve (higher: finer near the middle)", "gamepad", "stick_curve", func(v: float) -> String: return "%.1f" % v))
	page.add_child(_toggle("Invert stick up and down", "gamepad", "stick_invert_y"))
	page.add_child(UiKit.hint("Hold View for the pad wheel (the right stick picks); hold Y for the interaction menu."))
	# Co-op assists (Assists): the host's picks, for the whole session.
	page.add_child(UiKit.heading("Co-op assists (the host sets them)"))
	for pair: Array in Assists.NAMES:
		var key: String = pair[0]
		var box := CheckBox.new()
		box.text = pair[1]
		box.button_pressed = Assists.is_on(key)
		box.disabled = not Assists.can_set()
		box.toggled.connect(func(on: bool) -> void: Assists.set_assist(key, on))
		page.add_child(box)
	if not Assists.can_set():
		page.add_child(UiKit.hint("Set by the host for this session."))
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
	row.tooltip_text = TIPS.get(key, "")
	(row.get_child(0) as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	var picker := OptionButton.new()
	picker.tooltip_text = row.tooltip_text
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var now: Variant = GameSettings.get_value(section, key)
	for option: Array in options:
		picker.add_item(String(option[1]))
		if str(option[0]) == str(now):
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: GameSettings.set_value(section, key, options[index][0]))
	row.add_child(picker)
	return row


func _toggle(text: String, section: String, key: String, tip := "") -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tip if tip != "" else TIPS.get(key, "")
	check.button_pressed = bool(GameSettings.get_value(section, key))
	check.toggled.connect(func(on: bool) -> void: GameSettings.set_value(section, key, on))
	return check


## A slider over the setting's range (GameSettings.RANGES) with its value shown by `shown`.
func _slider(text: String, section: String, key: String, shown: Callable, range_spec: Array = [], tip := "") -> Control:
	var row := _row(text)
	if range_spec.is_empty():
		range_spec = GameSettings.RANGES[key]
	row.tooltip_text = tip if tip != "" else TIPS.get(key, "")
	(row.get_child(0) as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = range_spec[0]
	slider.max_value = range_spec[1]
	slider.step = range_spec[2]
	slider.value = float(GameSettings.get_value(section, key))
	slider.tooltip_text = row.tooltip_text
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
			GameSettings.set_value(section, key, v)
		if section == "hud":
			HudLayout._changed())  # the HUD follows while dragging
	slider.drag_started.connect(func() -> void: slider.set_meta(&"dragging", true))
	slider.drag_ended.connect(func(_changed: bool) -> void: slider.remove_meta(&"dragging"))
	row.add_child(slider)
	row.add_child(value)
	return row
