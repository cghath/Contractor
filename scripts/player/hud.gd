class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, messages, and the Tab inventory screen.

## Set by the owning Soldier before the HUD enters the tree.
var player: Soldier
var inventory_screen: InventoryScreen
var command_menu: CommandMenu
var _crosshair: Label
var _prompt: Label
var _status: Label
var _downed: Label
var _message: Label
var _message_time := 0.0
var _white: ColorRect
var _white_left := 0.0  # seconds of whiteout remaining
## Blood loss, concussion and unconsciousness drawn over the view (Vitals.vision).
var _vision: ColorRect
var _vision_material: ShaderMaterial


## Fades colour, greys and closes in the edges, blurs and blacks out the screen.
const VISION_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float fade = 0.0;    // 15-30% blood lost: colour fades slightly
uniform float tunnel = 0.0;  // 30-40%: grey edges close in
uniform float blur = 0.0;    // concussion
uniform float black = 0.0;   // unconscious
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, blur * 2.5).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), 0.35 * fade + 0.45 * tunnel);
	float r = mix(0.75, 0.35, tunnel);
	float edge = 1.0 - smoothstep(r - 0.25, r, distance(UV, vec2(0.5)));
	c = mix(vec3(grey * 0.35), c, mix(1.0, edge, tunnel));
	COLOR = vec4(mix(c, vec3(0.0), black), 1.0);
}
"""


func _ready() -> void:
	_vision = ColorRect.new()
	_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vision_material = ShaderMaterial.new()
	_vision_material.shader = Shader.new()
	_vision_material.shader.code = VISION_SHADER
	_vision.material = _vision_material
	_vision.visible = false
	add_child(_vision)
	_vision.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	command_menu = CommandMenu.new(player)
	add_child(command_menu)
	add_child(Callouts.Subtitles.new())  # squadmates' callouts
	_message = _label("", Control.PRESET_CENTER_TOP)
	_message.position.y += 60
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	_message_time -= delta
	_message.visible = _message_time > 0.0
	_white_left = maxf(_white_left - delta, 0.0)
	_white.color.a = clampf(_white_left / 1.5, 0.0, 1.0)
	_update_vision()


## Draws what blood loss, concussion and being out do to the local player's view.
func _update_vision() -> void:
	if player == null:
		return
	var vision := player.vitals.vision()
	var any := false
	for key: String in vision:
		_vision_material.set_shader_parameter(key, vision[key])
		any = any or vision[key] > 0.0
	_vision.visible = any


## Flashbang: `amount` 0..1 sets how long the screen stays white (up to about 5 s).
func whiteout(amount: float) -> void:
	_white_left = maxf(_white_left, 0.5 + 4.5 * amount)


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
	var lines := PackedStringArray()
	var squad := _squad_lines(player)
	if squad != "":
		lines.append(squad)
	if player.inventory.hands != &"":
		lines.append("Carrying %s (Alt+G to drop)" % ItemDB.get_item(player.inventory.hands).name)
	_status.text = "\n".join(lines)
	_crosshair.visible = not player.is_aiming and player.vitals.is_up()
	_downed.text = downed_text(player.vitals)


## The text over a downed player's black screen: no health, just what is happening. You
## come round on your own once your body lets you (treatment helps); there is no revive.
static func downed_text(vitals: Vitals) -> String:
	if not vitals.downed:
		return ""
	if vitals.in_cardiac_arrest():
		var s := ceili(maxf(vitals.seconds_to_death(), 0.0))
		return "CARDIAC ARREST - %d:%02d\nYour heart has stopped" % [floori(s / 60.0), s % 60]
	if vitals.wake_eta() > 0.0:
		return "UNCONSCIOUS\nComing round..."
	return "UNCONSCIOUS\nYour team can treat you; you'll come round when your body recovers"


## The squad by F-key number, with each member's fire team and role (and colour team), and
## what each squadmate is doing. A ">" marks units selected in the command menu. No health:
## the handoff's HUD has no health readout.
func _squad_lines(player: Soldier) -> String:
	var units := command_menu.roster()
	if units.size() <= 1:
		return ""
	var lines := PackedStringArray()
	for i in units.size():
		var s := units[i]
		var mark := ">" if String(s.name) in command_menu.selected and command_menu.is_open() else " "
		var tag := CommandMenu.unit_tag(s)
		tag = " [%s]" % tag if tag != "" else ""
		if s.is_ai():
			lines.append("%s F%d %s%s: %s" % [mark, i + 1, s.name, tag, s.ai_status])
		else:
			lines.append("  F%d %s%s" % [i + 1, "You" if s == player else "Player %s" % s.name, tag])
	return "SQUAD  [F-keys] select  [~] all\n" + "\n".join(lines) + "\n"


func _label(text: String, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label
