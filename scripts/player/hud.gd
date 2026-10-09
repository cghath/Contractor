class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, ammo, load/volume status, and the Tab
## inventory screen.

## Set by the owning Soldier before the HUD enters the tree.
var player: Soldier
var inventory_screen: InventoryScreen
var _crosshair: Label
var _prompt: Label
var _status: Label
var _ammo: Label
var _downed: Label
var _message: Label
var _message_time := 0.0
var _white: ColorRect
var _white_left := 0.0  # seconds of whiteout remaining


func _ready() -> void:
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
	_ammo = _label("", Control.PRESET_BOTTOM_RIGHT)
	_ammo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.add_theme_font_size_override(&"font_size", 26)
	_ammo.position += Vector2(-20, -16)
	inventory_screen = InventoryScreen.new(player)
	inventory_screen.visible = false
	add_child(inventory_screen)
	_message = _label("", Control.PRESET_CENTER_TOP)
	_message.position.y += 60
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	_message_time -= delta
	_message.visible = _message_time > 0.0
	_white_left = maxf(_white_left - delta, 0.0)
	_white.color.a = clampf(_white_left / 1.5, 0.0, 1.0)


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


func update_status(player: Soldier) -> void:
	var inv := player.inventory
	var weapon := player.active_weapon()
	var lines := PackedStringArray()
	lines.append("HP %d   Load %.1f kg  (speed x%.2f)" % [player.vitals.health, inv.total_mass(), player.load_mult])
	var vols := PackedStringArray()
	for c in Inventory.CONTAINERS:
		if inv.capacity(c) > 0.0:
			vols.append("%s %.1f/%.1f L" % [String(c).capitalize(), inv.used(c), inv.capacity(c)])
	lines.append("   ".join(vols))
	var armor := player.gear.armor_summary()
	if armor != "":
		lines.append("Armor: " + armor)
	if inv.hands != &"":
		lines.append("Carrying %s (G to drop)" % ItemDB.get_item(inv.hands).name)
	var squad := _squad_lines(player)
	if squad != "":
		lines.insert(0, squad)
	_status.text = "\n".join(lines)
	if weapon and weapon.type == "weapon":
		var ammo := StringName(weapon.stats.get("ammo", ""))
		var state := "   RELOADING" if player.is_reloading else ""
		_ammo.text = "%s%s\n%d / %d" % [weapon.name, state, inv.rounds_in(player.active_slot), inv.spare_rounds(ammo)]
	else:
		_ammo.text = ""
	_ammo.text += "\n%s x%d  [T] throw  [3] switch" % [ItemDB.get_item(player.throwable).name, inv.count_of(player.throwable)]
	if player.vitals.is_healing():
		_status.text += "\nHealing..."
	_crosshair.visible = not player.is_aiming and player.vitals.is_up()
	if player.vitals.downed:
		_downed.text = "DOWNED - bleeding out in %d s\nWait for a teammate to revive you, or press F to give up" % player.vitals.bleed_seconds
	else:
		_downed.text = ""


## One line per AI squadmate on the player's side: what it's doing and its health.
func _squad_lines(player: Soldier) -> String:
	var level := CompoundLevel.current(player)
	if level == null:
		return ""
	var lines := PackedStringArray()
	for s: Soldier in level.ai.get_children():
		if s.faction == player.faction:
			lines.append("%s: %s (%d HP)" % [s.name, s.ai_status, s.vitals.health])
	if lines.is_empty():
		return ""
	return "SQUAD  [Z] on me  [X] hold  [V] move there\n" + "\n".join(lines) + "\n"


func _label(text: String, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label
