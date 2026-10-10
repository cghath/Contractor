class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, messages, and the Tab inventory screen.

## Set by the PlayerInput driver before the HUD enters the tree.
var player: Soldier
var inventory_screen: InventoryScreen
var _crosshair: Label
var _prompt: Label
var _status: Label
var _downed: Label
var _message: Label
var _message_time := 0.0


func _ready() -> void:
	_crosshair = _label("+", Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed = _label("", Control.PRESET_CENTER)
	_downed.position.y -= 80
	_downed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed.add_theme_font_size_override(&"font_size", 28)
	_downed.add_theme_color_override(&"font_color", Color("ff6b5e"))
	_prompt = _label("", Control.PRESET_CENTER)
	_prompt.position.y += 40
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = _label("", Control.PRESET_BOTTOM_LEFT)
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.position += Vector2(16, -16)
	inventory_screen = InventoryScreen.new(player)
	inventory_screen.visible = false
	add_child(inventory_screen)
	_message = _label("", Control.PRESET_CENTER_TOP)
	_message.position.y += 60
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	_message_time -= delta
	_message.visible = _message_time > 0.0


func set_prompt(text: String) -> void:
	_prompt.text = text


func flash(text: String) -> void:
	_message.text = text
	_message_time = 2.5


func is_inventory_open() -> bool:
	return inventory_screen.visible


func toggle_detail() -> void:
	inventory_screen.visible = not inventory_screen.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_screen.visible else Input.MOUSE_MODE_CAPTURED


## Minimal HUD, as in Arma with ACE: no health bar, ammo counter or load readout. Weight,
## litres, rounds loaded and armor damage are on the inventory screen (Tab).
func update_status(player: Soldier) -> void:
	var hands := player.inventory.hands
	_status.text = "Carrying %s (G to drop)" % ItemDB.get_item(hands).name if hands != &"" else ""
	_crosshair.visible = not player.is_aiming and player.vitals.is_up()
	if player.vitals.downed:
		_downed.text = "DOWNED - bleeding out in %d s\nWait for a teammate to revive you, or press F to give up" % player.vitals.bleed_seconds
	else:
		_downed.text = ""


func _label(text: String, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label
