class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, ammo, load/volume status, and the Tab
## inventory screen.

## Set by the owning Player before the HUD enters the tree.
var player: Player
var inventory_screen: InventoryScreen
var _prompt: Label
var _status: Label
var _ammo: Label
var _message: Label
var _message_time := 0.0


func _ready() -> void:
	var crosshair := _label("+", Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


func update_status(player: Player) -> void:
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
	_status.text = "\n".join(lines)
	if weapon and weapon.type == "weapon":
		var ammo := StringName(weapon.stats.get("ammo", ""))
		var state := "   RELOADING" if player.is_reloading else ""
		_ammo.text = "%s%s\n%d / %d" % [weapon.name, state, inv.rounds_in(player.active_slot), inv.spare_rounds(ammo)]
	else:
		_ammo.text = ""
	if player.vitals.is_healing():
		_status.text += "\nHealing..."


func _label(text: String, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label
