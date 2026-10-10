class_name InventoryScreen
extends PanelContainer
## Tab inventory: what's equipped and what's in each container, with actions. Every button
## is a request to the host (Soldier._server_inventory_action and friends); the screen
## redraws when the replicated inventory changes, so it always shows the host's truth.

const SLOT_NAMES := {
	&"primary": "Primary", &"sidearm": "Sidearm", &"helmet": "Helmet", &"vest": "Carrier",
	&"backpack": "Backpack", &"plate_front": "Front plate", &"plate_back": "Back plate",
	&"plate_left": "Left plate", &"plate_right": "Right plate",
}

var player: Soldier
var _list: VBoxContainer


func _init(p_player: Soldier) -> void:
	player = p_player


func _ready() -> void:
	# Fill the screen minus margins: centring a container before it has a size misplaces it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 200
	offset_right = -200
	offset_top = 60
	offset_bottom = -150
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(_list)
	player.inventory.changed.connect(_redraw)
	visibility_changed.connect(_redraw)
	_redraw()


func _redraw() -> void:
	if not visible or _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var inv := player.inventory
	_header("INVENTORY   %.1f kg carried        Tab / Esc to close" % inv.total_mass())
	for slot in Inventory.SLOTS:
		var id: StringName = inv.slots[slot]
		if id == &"":
			if slot in Inventory.PLATE_SLOTS and not slot in inv.carrier_plate_slots():
				continue  # the carrier has no pocket for it
			_row("%s: -" % SLOT_NAMES[slot], [])
			continue
		var item := ItemDB.get_item(id)
		var actions := []
		if slot != &"vest" and slot != &"backpack":
			actions.append(["Stow", _action.bind("stow_slot", &"", -1, slot, &"")])
		actions.append(["Drop", _action.bind("drop_slot", &"", -1, slot, &"")])
		_row("%s: %s%s" % [SLOT_NAMES[slot], item.name, _detail(item, inv.state_of(slot))], actions)
	if inv.hands != &"":
		_row("Hands: %s" % ItemDB.get_item(inv.hands).name, [["Drop", func() -> void: player._server_drop.rpc_id(1, &"")]])
	for container in Inventory.CONTAINERS:
		if inv.capacity(container) <= 0.0:
			continue
		_header("%s   %.1f / %.1f L" % [String(container).to_upper(), inv.used(container), inv.capacity(container)])
		var entries: Array = inv.containers[container]
		if entries.is_empty():
			_row("  (empty)", [])
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var item := ItemDB.get_item(entry.id)
			var actions := []
			if item.slot != &"":
				actions.append(["Equip", _action.bind("equip_entry", container, i, &"", &"")])
			if item.stats.has("heal"):
				actions.append(["Use", func() -> void: player._server_use_medical.rpc_id(1)])
			if Inventory.is_loose_rounds(item) and inv.loadable_rounds(item.id) > 0:
				actions.append(["Load magazines", load_magazines.bind(item.id)])
			for other in Inventory.CONTAINERS:
				if other != container and inv.capacity(other) > 0.0:
					actions.append(["> " + String(other).capitalize(), _action.bind("move_entry", container, i, &"", other)])
			actions.append(["Drop", _action.bind("drop_entry", container, i, &"", &"")])
			var amount := " x%d" % entry.count if entry.count > 1 else ""
			_row("  %s%s%s   %.1f L" % [item.name, amount, _detail(item, entry.get("state", {})), item.volume_l * entry.count], actions)


func _action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	player._server_inventory_action.rpc_id(1, action, container, index, slot, target)


## "Load magazines" on a stack of loose rounds: the host fills the magazines of that
## calibre, fullest first, as a timed action (Soldier._server_load_mags).
func load_magazines(rounds_id: StringName) -> void:
	player._server_load_mags.rpc_id(1, rounds_id)


static func _detail(item: ItemData, state: Dictionary) -> String:
	if state.has("rounds") and item.type == "weapon":
		return "  [%d loaded]" % int(state.rounds)
	if state.has("rounds") and int(state.rounds) < item.magazine_rounds():
		return "  [%d/%d rds]" % [int(state.rounds), item.magazine_rounds()]
	if item.is_voxel_armor():
		var damage := ArmorRules.state_text(item, state)  # "3 cracks, 46%", "shattered"...
		return "  [%s]" % damage if damage != "" else ""
	return ""


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 17)
	label.add_theme_color_override(&"font_color", Color("e0c27a"))
	_list.add_child(label)


func _row(text: String, actions: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	for action: Array in actions:
		var button := Button.new()
		button.text = action[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(action[1])
		row.add_child(button)
	_list.add_child(row)
