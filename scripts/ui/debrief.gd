class_name DebriefScreen
extends CanvasLayer
## The debrief after extraction (wave 4, W10), on every peer: pay earned (advance,
## completion, bonuses), penalties (civilian fines), reputation changes, casualties and
## injuries, what was carried out, salvage picks against the salvage budget (MW5-style:
## claim items left in the field), and intel to turn in (opens leads) or sell to another
## faction (risking the client's anger). Choices go to the host (Contracts requests);
## Continue closes it (the host's banks the salvage picks).

signal closed

var _box: VBoxContainer
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 12
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		panel.set("offset_" + side, 80.0 if side in ["left", "top"] else -80.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_box)
	Contracts.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_instance_valid(_box):
		return
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var d := Contracts.last_debrief()
	if d.is_empty():
		_line("No debrief yet.")
		_actions()
		return
	_line("DEBRIEF - %s (day %d)" % [d.get("zone_name", ""), int(d.get("day", 0))], 22)
	for l: String in DebriefCalc.summary(d):
		_line(l)
	_line("")
	_line("Got out: %s" % ", ".join(PackedStringArray(d.get("extracted", []))) if not (d.get("extracted", []) as Array).is_empty() else "Got out: (not reported)")
	var casualties: Array = d.get("casualties", [])
	_line("Casualties and injuries: %s" % ("none" if casualties.is_empty() else ", ".join(PackedStringArray(casualties.map(func(c: Dictionary) -> String:
		return "%s (%s%s)" % [c.get("name", "?"), String(c.get("status", "")).to_upper(), ": " + String(c.injury) if String(c.get("injury", "")) != "" else ""])))))
	var items: Array = d.get("items_out", [])
	_line("Carried out (banked at base): %s" % ("nothing" if items.is_empty() else ", ".join(PackedStringArray(items.map(func(e: Dictionary) -> String:
		return "%d x %s" % [int(e.get("count", 1)), _name(e.get("id", ""))])))))
	_salvage(d)
	_intel(d)
	_actions()


func _salvage(d: Dictionary) -> void:
	var salvage: Dictionary = d.get("salvage", {})
	_line("")
	_line("SALVAGE: share %d%% of $%s left in the field: budget $%s, claimed $%s" % [roundi(float(salvage.get("share", 0)) * 100.0),
		DebriefCalc.money(salvage.get("pool_value", 0)), DebriefCalc.money(salvage.get("budget", 0)), DebriefCalc.money(salvage.get("spent", 0))], 17)
	var pool: Array = salvage.get("pool", [])
	var picked: Array = salvage.get("picked", [])
	for i in pool.size():
		var e: Dictionary = pool[i]
		var row := HBoxContainer.new()
		_box.add_child(row)
		var label := Label.new()
		label.text = "%d x %s ($%s)%s" % [int(e.count), _name(e.id), DebriefCalc.money(e.value), "  CLAIMED" if i in picked else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if d.get("finished", false):
			continue
		var button := Button.new()
		button.text = "Return" if i in picked else "Claim"
		button.disabled = not i in picked and not DebriefCalc.can_pick(d, i)
		button.pressed.connect(func() -> void:
			if i in picked:
				Contracts.unpick_salvage(i)
			else:
				Contracts.pick_salvage(i))
		row.add_child(button)


func _intel(d: Dictionary) -> void:
	var intel: Array = d.get("intel", [])
	if intel.is_empty():
		return
	_line("")
	_line("INTEL brought out", 17)
	var client := String((d.contracts as Array)[0].employer) if not (d.get("contracts", []) as Array).is_empty() else ""
	for i in intel.size():
		var e: Dictionary = intel[i]
		var row := HBoxContainer.new()
		_box.add_child(row)
		var label := Label.new()
		var status := String(e.get("status", "pending"))
		label.text = "%d x %s: %s" % [int(e.count), _name(e.id), {"pending": "undecided", "turned_in": "turned in (new leads on the board)",
			"sold": "sold to %s%s" % [MissionRegistry.faction_name(String(e.get("buyer", ""))), " (the client found out)" if e.get("caught", false) else ""]}.get(status, status)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if status != "pending" or d.get("finished", false):
			continue
		var turn_in := Button.new()
		turn_in.text = "Turn in to %s" % MissionRegistry.faction_name(client)
		turn_in.pressed.connect(func() -> void: Contracts.turn_in_intel(i))
		row.add_child(turn_in)
		var buyers := OptionButton.new()
		for f: String in MissionRegistry.faction_ids():
			if f != client:
				buyers.add_item(MissionRegistry.faction_name(f))
				buyers.set_item_metadata(buyers.item_count - 1, f)
		row.add_child(buyers)
		var sell := Button.new()
		sell.text = "Sell ($%s)" % DebriefCalc.money(MissionRegistry.setting_i("intel_sale_price", 6000) * int(e.count))
		sell.pressed.connect(func() -> void:
			if buyers.item_count > 0:
				Contracts.sell_intel(i, String(buyers.get_item_metadata(buyers.selected))))
		row.add_child(sell)


func _actions() -> void:
	var row := HBoxContainer.new()
	_box.add_child(row)
	var cont := Button.new()
	cont.text = "Continue"
	cont.pressed.connect(close)
	row.add_child(cont)


## Closes the screen; on the host it also closes the debrief (banks the salvage picks).
func close() -> void:
	if Contracts.is_host():
		Contracts.finish_debrief()
	Input.mouse_mode = _mouse_before
	closed.emit()
	queue_free()


## Everything the screen says, as text (tests read it).
func text() -> String:
	var out := PackedStringArray()
	for node in _box.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return "\n".join(out)


func _line(text: String, size := 15) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", size)
	_box.add_child(label)


static func _name(id: Variant) -> String:
	var item: ItemData = ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null
	return item.name if item else String(id)
