class_name BodyReadout
extends PanelContainer
## The body screen's first form (docs/survival_medical.md section 7, call 58): a panel listing
## every store of the local survivor's body as a word and a number (Needs.readout of
## Survival.my_body). TOGGLE_KEY shows and hides it, in survival only. The figure, its layers and
## the rings come in phases B and D; the skill gate with the medical line.

## Proposed: backslash (every letter near H is taken; Alt+H would also open the medical menu).
const TOGGLE_KEY := KEY_BACKSLASH
const REFRESH_S := 0.5

var label: Label
var _left := 0.0


func _init() -> void:
	name = "BodyReadout"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	label = UiKit.hud_label("", &"HudSmallLabel")
	add_child(label)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position.x = 24.0


## Shows or hides it.
func toggle() -> void:
	visible = not visible and SurvivalLevel.of(self) != null
	refresh()


## The text from this peer's own body now.
func refresh() -> void:
	label.text = Needs.readout(Survival.my_body)


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
		refresh()
