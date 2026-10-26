class_name BodyReadout
extends PanelContainer
## The body screen's panel (docs/survival_medical.md section 7, call 58): TOGGLE_KEY shows and
## hides it, in survival only. Phase D: the body screen itself (BodyScreen: the figure with its
## layers, words gated by medical skill, numbers on hover, the rings, the treatments) on yourself
## or on the companion or casualty you look at, and below it every store as a word and a number
## (Needs.readout of the shown body). The mouse is free while it's up.

## Proposed: backslash (every letter near H is taken; Alt+H would also open the medical menu).
const TOGGLE_KEY := KEY_BACKSLASH
const REFRESH_S := 0.5

var label: Label
var screen: BodyScreen
var _left := 0.0


func _init() -> void:
	name = "BodyReadout"
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	screen = BodyScreen.new()
	box.add_child(screen)
	label = UiKit.hud_label("", &"HudSmallLabel")
	box.add_child(label)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position.x = 24.0


## Shows or hides it (on whoever you look at within reach, else yourself).
func toggle() -> void:
	visible = not visible and SurvivalLevel.of(self) != null
	if visible:
		screen.pick_target()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh()


## The text from the shown body now.
func refresh() -> void:
	if visible:
		screen.refresh()
	label.text = Needs.readout(screen.body())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == TOGGLE_KEY and SurvivalLevel.of(self) != null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if SurvivalLevel.of(self) == null:
		visible = false
		return
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		label.text = Needs.readout(screen.body())
