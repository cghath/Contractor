class_name PadWheel
extends Control
## The gamepad's wheel (wave 7, S4: radial menus on the sticks): hold View and the controls
## the pad has no button for (Controls.PAD_WHEEL) ring the middle of the screen; push the right
## stick towards one and let go of View to do it (pressed for a moment, as its key would be).
## Let go with the stick in the middle and nothing happens. PlayerInput drives it (update).

const RADIUS_PX := 170.0
## How far the stick must be pushed for a slice to light up.
const PICK_DEADZONE := 0.5

var slices: Array = Controls.PAD_WHEEL
## The lit slice (-1: none).
var chosen := -1
var _labels: Array[Label] = []
var _release: StringName = &""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for slice: Array in slices:
		var label := UiKit.hud_label(slice[1], &"HudSmallLabel")
		add_child(label)
		_labels.append(label)


func is_open() -> bool:
	return visible


## Each frame: `held` is View down, `stick` the right stick (x right, y down). Returns true
## while the wheel has the stick (open), so the view doesn't turn under it. Letting go presses
## the lit slice's action (the frame after, it's let go again).
func update(held: bool, stick: Vector2) -> bool:
	if _release != &"":
		_send(_release, false)
		_release = &""
	if held:
		if not visible:
			visible = true
			chosen = -1
		chosen = pick(stick, slices.size(), chosen)
		_layout()
		return true
	if visible:
		visible = false
		if chosen >= 0:
			_release = slices[chosen][0]
			_send(_release, true)
		chosen = -1
	return false


## The slice the stick points at, clockwise from the top (`keep` when it's near the middle).
static func pick(stick: Vector2, count: int, keep := -1) -> int:
	if stick.length() < PICK_DEADZONE or count <= 0:
		return keep
	var angle := fposmod(atan2(stick.x, -stick.y), TAU)  # 0 at the top, growing clockwise
	return int(round(angle / (TAU / count))) % count


## Where slice `i` of `count` sits from the middle.
static func slice_offset(i: int, count: int) -> Vector2:
	var angle := TAU * i / count
	return Vector2(sin(angle), -cos(angle)) * RADIUS_PX


func _layout() -> void:
	var centre := size * 0.5
	for i in _labels.size():
		var label := _labels[i]
		label.reset_size()
		label.position = centre + slice_offset(i, _labels.size()) - label.size * 0.5
		label.modulate = UiKit.ACCENT if i == chosen else Color.WHITE


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
