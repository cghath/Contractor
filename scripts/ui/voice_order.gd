class_name VoiceOrder
extends Control
## Push-to-talk squad orders. Hold `voice_order` (T) and say a command; VoiceCommands looks
## it up in its bounded vocabulary and this replays the matching key sequence into the
## command menu through CommandMenu.handle_input, exactly as if it had been typed - see
## VoiceCommands for why that means a voice order can't do anything a key press couldn't.
##
## No offline speech recognition is wired up yet (next step - see docs/contractor_handoff.md
## for the chosen approach and why). Standing in for it, holding T opens a small text box:
## type the order and press Enter to send it, or let go of T (or Esc) to cancel without
## sending anything. Swap `run()`'s caller for a real recognizer's output without touching
## CommandMenu, VoiceCommands, or the tests - they all go through run() already.

var command_menu: CommandMenu
var listening := false
var _box: LineEdit


func _init(p_command_menu: CommandMenu) -> void:
	command_menu = p_command_menu


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = LineEdit.new()
	_box.visible = false
	_box.placeholder_text = "Voice order (testing stand-in - type it, Enter to send)"
	_box.custom_minimum_size = Vector2(320, 0)
	_box.text_submitted.connect(_submit)
	add_child(_box)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_box.position.y -= 150


## Feeds the `voice_order` key state once a frame, the way InteractionMenu.update_keys does
## for Left Ctrl: held opens the box, letting go before Enter cancels without sending.
func update_key(held: bool) -> void:
	if held and not listening:
		listening = true
		_box.text = ""
		_box.visible = true
		_box.grab_focus()
	elif not held and listening and _box.visible:
		cancel()


func cancel() -> void:
	listening = false
	_box.visible = false
	_box.release_focus()


func _submit(text: String) -> void:
	cancel()
	run(text)


## Runs the key sequence a recognized phrase maps to, exactly as if it had been typed on the
## keyboard. Flashes a message if nothing in the bounded vocabulary matched.
func run(text: String) -> void:
	var keys := VoiceCommands.resolve(text)
	if keys.is_empty():
		command_menu.player._hud.flash("Didn't catch that order: \"%s\"" % text)
		return
	for key: String in keys:
		command_menu.handle_input(_key_event(key))


const DIGIT_KEYS := {"1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4, "5": KEY_5,
	"6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9, "0": KEY_0}


static func _key_event(key: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	if key == "`":
		event.physical_keycode = KEY_QUOTELEFT
	elif key == "Backspace":
		event.physical_keycode = KEY_BACKSPACE
	elif key.begins_with("F"):
		event.physical_keycode = CommandMenu.F_KEYS[key.substr(1).to_int() - 1]
	else:
		event.physical_keycode = DIGIT_KEYS[key]
	return event
