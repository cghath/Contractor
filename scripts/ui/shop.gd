class_name ShopScreen
extends CanvasLayer
## The base shop (wave 4, W10): gear, ammunition, medical supplies and explosives at
## data/prices.json's prices, bought with the company's cash (Economy.buy, which the host
## decides), plus what support calls cost. Bought items go to the base agent's armory
## (Economy.purchase_sink) or wait in the base inbox. The base agent places it in the hub.

signal closed

var _cash: Label
var _filter: OptionButton
var _list: ItemList
var _count: SpinBox
var _notice: Label
var _ids: Array[StringName] = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 11
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 560)
	panel.position -= panel.custom_minimum_size * 0.5
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	_cash = Label.new()
	box.add_child(_cash)
	_filter = OptionButton.new()
	_filter.add_item("Everything")
	for type: String in ["weapon", "ammo", "armor", "plate", "pouch", "backpack", "medical", "utility"]:
		_filter.add_item(type.capitalize())
		_filter.set_item_metadata(_filter.item_count - 1, type)
	_filter.item_selected.connect(func(_i: int) -> void: refresh())
	box.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	var row := HBoxContainer.new()
	box.add_child(row)
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 100
	row.add_child(_count)
	var buy := Button.new()
	buy.text = "Buy"
	buy.pressed.connect(buy_selected)
	row.add_child(buy)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	var supports := Label.new()
	supports.text = "Support calls (paid when called, from the contract's support budget first): " + ", ".join(
		Prices.support_kinds().map(func(k: Variant) -> String: return "%s $%s" % [String(k), DebriefCalc.money(Prices.support_price(String(k)))]))
	supports.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(supports)
	_notice = Label.new()
	_notice.modulate = Color("ffd35a")
	box.add_child(_notice)
	Economy.changed.connect(refresh)
	Economy.notice.connect(func(text: String) -> void: _notice.text = text)
	refresh()


func refresh() -> void:
	_cash.text = "BASE SHOP   Cash $%s" % DebriefCalc.money(Economy.cash())
	var type: Variant = _filter.get_item_metadata(_filter.selected) if _filter.selected > 0 else null
	var keep := _list.get_selected_items()
	_ids.clear()
	_list.clear()
	for id: StringName in Prices.shop_items():
		var item := ItemDB.get_item(id)
		if type != null and item.type != type:
			continue
		_ids.append(id)
		_list.add_item("%s  (%s)  $%s" % [item.name, item.type, DebriefCalc.money(Prices.price_of(id))])
	if not keep.is_empty() and keep[0] < _list.item_count:
		_list.select(keep[0])


## Items listed now (tests).
func listed() -> Array[StringName]:
	return _ids


func select(id: StringName) -> void:
	var i := _ids.find(id)
	if i >= 0:
		_list.select(i)


func buy_selected() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_notice.text = "Pick something to buy"
		return
	Economy.buy(_ids[picked[0]], int(_count.value))


func close() -> void:
	Input.mouse_mode = _mouse_before
	closed.emit()
	queue_free()
