class_name ControlOptions
extends RefCounted
## The player's control options, saved in settings.cfg beside the shooting hand (Handedness)
## and picked on the main menu or the Escape menu.
##
## The get-out key (Captain, P0164 queue 8: an option, with the menu decluttered for it):
## when it's on, GET_OUT_ACTION (Controls: V) gets you out of the vehicle you sit in
## (Vehicle.request_exit), and the seat's Left Ctrl point leaves Get out off its ring. When it's
## off, the key does nothing and Get out stays in the menu, as before.

const SECTION := "controls"
const GET_OUT_KEY := "get_out_key"
## The input action the get-out key is bound to (Controls.KEYS).
const GET_OUT_ACTION := &"get_out"
## Whether the get-out key is on for someone who never picked (proposed: off, so the menu's
## Get out stays where players learnt it until they turn the key on).
const GET_OUT_DEFAULT := false

static var _get_out := GET_OUT_DEFAULT
static var _loaded := false


## Whether the get-out key is on (from settings.cfg the first time).
static func get_out_key() -> bool:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(Handedness.SETTINGS_PATH) == OK:
			_get_out = bool(cfg.get_value(SECTION, GET_OUT_KEY, GET_OUT_DEFAULT))
	return _get_out


## Turns the get-out key on or off and saves it (other settings in the file are kept).
static func set_get_out_key(on: bool) -> void:
	_get_out = on
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(Handedness.SETTINGS_PATH)
	cfg.set_value(SECTION, GET_OUT_KEY, on)
	cfg.save(Handedness.SETTINGS_PATH)


## The get-out key's name as the keyboard shows it ("V"), for the menus and the HUD.
static func get_out_key_name() -> String:
	if not InputMap.has_action(GET_OUT_ACTION):
		return "?"
	for event in InputMap.action_get_events(GET_OUT_ACTION):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	return "?"


## The checkbox the main menu and the Escape menu show for the get-out key.
static func get_out_toggle() -> CheckBox:
	var box := CheckBox.new()
	box.text = "Get out of vehicles with %s (not the Ctrl menu)" % get_out_key_name()
	box.button_pressed = get_out_key()
	box.toggled.connect(set_get_out_key)
	return box
