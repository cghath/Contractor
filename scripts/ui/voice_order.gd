class_name VoiceOrder
extends Control
## Push-to-talk squad orders, and asking a friendly or civilian a question. Hold
## `voice_order` (T) and say something; if a living friendly or civilian is under the
## crosshair and it's one of VoiceQuestions' bounded questions, they answer with their own
## live state (ammo, status, what they've seen) - never a canned line. Otherwise it's
## VoiceCommands looking the phrase up in its bounded vocabulary and this replaying the
## matching key sequence into the command menu through CommandMenu.handle_input, exactly as
## if it had been typed - see VoiceCommands for why that means a voice order can't do
## anything a key press couldn't.
##
## No offline speech recognition is wired up yet (next step - see docs/contractor_handoff.md
## for the chosen approach and why). Standing in for it, holding T opens a small text box:
## type the order or question and press Enter to send it, or let go of T (or Esc) to cancel
## without sending anything. Swap `run()`'s caller for a real recognizer's output without
## touching CommandMenu, VoiceCommands, VoiceQuestions or the tests - they all go through
## run() already.

## How long after a soldier last took fire or got a contact report they'll still answer
## "where are the enemies" with it, instead of "Nothing to report."
const CONTACT_RECENCY_S := 45.0

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


## A question, if someone's there to ask: a living friendly or civilian answers with their
## own live state. Otherwise runs the key sequence a recognized order maps to, exactly as if
## it had been typed on the keyboard. Flashes a message if nothing in either bounded
## vocabulary matched.
func run(text: String) -> void:
	var target := askable_target()
	if target != null:
		var qid := VoiceQuestions.resolve(text)
		if qid != &"":
			command_menu.player._hud.flash("%s: %s" % [target.display_name(), _answer_text(target, qid)])
			return
	var keys := VoiceCommands.resolve(text)
	if keys.is_empty():
		command_menu.player._hud.flash("Didn't catch that order: \"%s\"" % text)
		return
	for key: String in keys:
		command_menu.handle_input(_key_event(key))


## The living friendly or civilian under the crosshair, if any - someone it makes sense to
## ask a question (not yourself, not a downed body, not an active hostile).
func askable_target() -> Soldier:
	var player := command_menu.player
	var target := command_menu.soldier_under_crosshair()
	if target == null or target == player or not target.vitals.is_up():
		return null
	return target if target.faction == player.faction or Person.is_noncombatant(target) else null


## What `target` says back, from their own live state - ammo (AmmoReadout, the same numbers
## the HUD shows), status (ai_status and condition_text, as CommandMenu._report reads them),
## or the last contact they called in (threat_pos/threat_time), recent enough to still matter.
static func _answer_text(target: Soldier, qid: StringName) -> String:
	match qid:
		&"ammo":
			var weapon := target.active_weapon()
			if weapon == null or weapon.type != "weapon":
				return "I'm not carrying a weapon."
			return AmmoReadout.text_of(AmmoReadout.summary(target))
		&"status":
			var condition := target.vitals.condition_text()
			return "%s, %s" % [target.ai_status, condition] if target.ai_status != "" else condition
		&"contact":
			if Soldier._now() - target.threat_time > CONTACT_RECENCY_S:
				return "Nothing to report."
			var distance := Callouts.round_distance(target.global_position.distance_to(target.threat_pos))
			return "Contact, %s, %d m" % [Callouts.direction_word(target, target.threat_pos), distance]
	return ""


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
