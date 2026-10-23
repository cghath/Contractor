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
## own live state. Otherwise a go code ("alpha go") or an order to a high command squad by its
## callsign ("Hawk two, move there"), sent as the map's orders are (HighCommand: its own
## "copy" comes back over the net); else the key sequence a recognized order maps to, exactly
## as if it had been typed on the keyboard, after selecting whoever it was addressed to
## ("Bravo, hold"; nobody named and nobody selected: everyone), and the one who got it
## confirms ("Holding."). Flashes a message if nothing in the bounded vocabularies matched.
func run(text: String) -> void:
	var target := askable_target()
	if target != null:
		var qid := VoiceQuestions.resolve(text)
		if qid != &"":
			command_menu.player._hud.flash("%s: %s" % [target.display_name(), _answer_text(target, qid)])
			return
	var hud := command_menu.player._hud
	var code := VoiceCommands.go_code(text)
	var hc := HighCommand.of(command_menu.player)
	if code != "" and hc:
		hc.request_go(code)
		hud.flash("%s, go" % ("H-hour" if code == "hhour" else code.capitalize()))
		return
	var names := addressees()
	var split := VoiceCommands.split_addressee(text, names)
	var to: Variant = split.to
	if to is Dictionary and hc:  # a high command squad
		_hc_order(hc, to as Dictionary, String(split.rest))
		return
	var keys := VoiceCommands.resolve(String(split.rest) if to != null else text)
	if keys.is_empty():
		hud.flash("Didn't catch that order: \"%s\"" % text)
		return
	var picks := keys[0].begins_with("F") or keys[0] in ["`", "Backspace"]
	if to is String:
		command_menu.close()
		command_menu.handle_input(_key_event(String(to)))
	elif not picks and not command_menu.is_open():
		command_menu.handle_input(_key_event("`"))  # an order to nobody in particular: the squad
	var who := command_menu.selected.duplicate()
	for key: String in keys:
		command_menu.handle_input(_key_event(key))
	var ack := VoiceCommands.ack_for(keys)
	if not picks and not ack.is_empty():
		_confirm(who, String(ack[0]), String(ack[1]))


## Who a voice order can be addressed to, as spoken: each AI squadmate's callsign (its select
## key, F<n>), the whole squad (`), and each high command squad out ({"id", "callsign"}).
func addressees() -> Dictionary:
	var out := {}
	var units := command_menu.roster()
	for i in mini(units.size(), CommandMenu.F_KEYS.size()):
		if units[i].is_ai():
			out[VoiceCommands.spoken(String(units[i].name))] = "F%d" % (i + 1)
	for w: String in VoiceCommands.EVERYONE:
		out[w] = "`"
	var hc := HighCommand.of(command_menu.player)
	if hc:
		for v: Dictionary in hc.view:
			if String(v.get("callsign", "")) != "":
				out[VoiceCommands.spoken(String(v.callsign))] = {"id": String(v.id), "callsign": String(v.callsign)}
	return out


## An order to high command squad `g` ({"id", "callsign"}) from what was said after its callsign.
func _hc_order(hc: HighCommand, g: Dictionary, rest: String) -> void:
	var hud := command_menu.player._hud
	var said := VoiceCommands.hc_order(rest)
	if said.is_empty():
		hud.flash("Didn't catch the order for %s: \"%s\"" % [g.callsign, rest])
		return
	var points: Array = []
	if String(said.verb) in HcOrder.POINTED:
		var hit: Variant = command_menu.player.crosshair_ground()
		if hit == null:
			hud.flash("Look at a spot on the ground")
			return
		points = [[(hit as Vector3).x, (hit as Vector3).z]]
	hc.request_order(HcOrder.make(String(g.id), String(said.verb), points, {"go": String(said.go)}))
	hud.flash("%s: %s%s" % [g.callsign, HcOrder.verb_text(String(said.verb)), " on %s" % String(said.go).capitalize() if String(said.go) != "" else ""])


## The first of `who` (callsigns selected for the order) still up confirms it out loud.
func _confirm(who: PackedStringArray, what: String, line: String) -> void:
	var callouts := Callouts.of(command_menu.player)
	var level := CompoundLevel.current(command_menu.player)
	if callouts == null or level == null:
		return
	for name in who:
		var s := level.ai.get_node_or_null(NodePath(name)) as Soldier
		if s and s.vitals.is_up():
			callouts.request_ack(s, what, line)
			return


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
