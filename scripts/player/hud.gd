class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, load/volume status, and a Tab detail view.

var _prompt: Label
var _status: Label
var _detail: Label
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
	_detail = _label("", Control.PRESET_TOP_RIGHT)
	_detail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_detail.position += Vector2(-16, 16)
	_detail.visible = false
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


func toggle_detail() -> void:
	_detail.visible = not _detail.visible


func update_status(player: Player) -> void:
	var inv := player.inventory
	var weapon := player.active_weapon()
	var lines := PackedStringArray()
	lines.append("HP %d   Load %.1f kg  (speed x%.2f)" % [player.vitals.health, inv.total_mass(), player.load_mult])
	lines.append("Weapon: %s" % (weapon.name if weapon else "none"))
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
	if _detail.visible:
		_detail.text = _detail_text(inv)


func _detail_text(inv: Inventory) -> String:
	var lines := PackedStringArray(["EQUIPPED"])
	for slot in Inventory.SLOTS:
		var id: StringName = inv.slots[slot]
		lines.append("  %-12s %s" % [slot, ItemDB.get_item(id).name if id != &"" else "-"])
	for c in Inventory.CONTAINERS:
		if inv.capacity(c) <= 0.0:
			continue
		lines.append("%s  %.1f / %.1f L" % [String(c).to_upper(), inv.used(c), inv.capacity(c)])
		for entry: Dictionary in inv.containers[c]:
			lines.append("  %s x%d" % [ItemDB.get_item(entry.id).name, entry.count])
	return "\n".join(lines)


func _label(text: String, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label
