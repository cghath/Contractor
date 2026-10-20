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
var _contra: ItemList
var _contra_ids: Array[StringName] = []
## The picked item's one-line summary (ItemInfo), under the list.
var _info: Label
var _ids: Array[StringName] = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 11
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The shared look (UiKit; Captain, 2026-10-14: "all of the UIs need a pass"; docs/ui_audit.md
	# P0-4): an opaque themed panel over the contract board, fitted to the window (the fixed
	# 620x560 box put its title and filter above a 1280x720 window at a 1.5 Menu and HUD size).
	add_child(UiKit.dim(0.45))
	var box := UiKit.screen(self, 620.0, true)
	box.add_child(UiKit.header("Base shop", "Buy kit into the company stash with company cash, and sell contraband to the fixer.",
		PackedStringArray(["Pick a kind under Show, pick an item in the list, set how many, then Buy: it goes into the stash, ready for the loadouts.",
			"Hover or pick an item for what it is and how it's used. Prices are what the shop charges today.",
			"Contraband found on deployments can't go on the open market: the fixer buys it, one at a time, at the price shown.",
			"Support calls aren't bought here: they're paid when called, from the contract's support budget first."]),
		[["Esc", "Close"], ["Tab / arrows", "Move"], ["Enter", "Press"]]))
	_cash = UiKit.text("")
	box.add_child(_cash)
	_filter = OptionButton.new()
	_filter.add_item("Everything")
	for type: String in ["weapon", "ammo", "armor", "plate", "pouch", "backpack", "medical", "utility", "launcher"]:  # launcher: wave 5
		_filter.add_item(type.capitalize())
		_filter.set_item_metadata(_filter.item_count - 1, type)
	_filter.item_selected.connect(func(_i: int) -> void: refresh())
	_filter.tooltip_text = "Show one kind of item only"
	box.add_child(UiKit.row("Show", _filter, 80.0))
	_list = UiKit.list(120.0)
	UiKit.fit_height(_list, 320.0, 330.0)  # the list gives way first on a short window
	_list.item_selected.connect(_show_info)
	_list.tooltip_text = "What the shop sells, with today's price. Pick one, then Buy"
	box.add_child(_list)
	_info = UiKit.hint("Hover an item for what it is and how to use it.")
	box.add_child(_info)
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 100
	_count.tooltip_text = "How many to buy"
	box.add_child(UiKit.button_row([_count, UiKit.accent_button("Buy", buy_selected, "Buy that many of the picked item into the stash"),
		UiKit.button("Close", close, "Back to the contract board (Esc)")]))
	# Wave 6: contraband in the stash, and what the fixer who buys it pays (Fixers).
	box.add_child(UiKit.heading("Contraband in the stash"))
	_contra = UiKit.list(60.0)
	UiKit.fit_height(_contra, 90.0, 100.0)
	box.add_child(_contra)
	_contra.tooltip_text = "Contraband in the stash and what the fixer pays for one"
	box.add_child(UiKit.button_row([UiKit.danger_button("Sell one to the fixer", sell_contraband_selected, "Sell one of the picked contraband to the fixer, for the price shown")]))
	box.add_child(UiKit.hint("Support calls (paid when called, from the contract's support budget first): " + ", ".join(
		Prices.support_kinds().map(func(k: Variant) -> String: return "%s $%s" % [String(k), DebriefCalc.money(Prices.support_price(String(k)))]))))
	_notice = UiKit.text("")
	box.add_child(_notice)
	box.add_child(UiKit.key_hint("Esc", "Close"))
	Economy.changed.connect(refresh)
	Economy.notice.connect(func(text: String) -> void: _notice.text = text)
	refresh()
	UiKit.focus_first(box.get_parent())  # keyboard: Tab/arrows and Enter work at once


## Esc closes the shop only, not the contract board under it (P0-4: it fell through).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func _show_info(index: int) -> void:
	if index >= 0 and index < _ids.size():
		_info.text = ItemInfo.summary(_ids[index])


func refresh() -> void:
	_cash.text = "BASE SHOP   Cash $%s" % DebriefCalc.money(Economy.cash())
	var type: Variant = _filter.get_item_metadata(_filter.selected) if _filter.selected > 0 else null
	var keep := _list.get_selected_items()
	_ids.clear()
	_list.clear()
	for id: StringName in Quartermaster.catalog():  # the base shop plus what allied quartermasters sell us (wave 6)
		var item := ItemDB.get_item(id)
		if type != null and item.type != type:
			continue
		_ids.append(id)
		var seller := Quartermaster.seller_text(id)
		_list.add_item("%s  (%s)  $%s%s" % [item.name, item.type, DebriefCalc.money(Quartermaster.price(id)), "   [%s]" % seller if seller != "" else ""])
		_list.set_item_tooltip(_list.item_count - 1, ItemInfo.tooltip(id))  # hover: what it is and how to use it (Captain, 2026-10-14: "item descriptions plus uses also needed")
	if not keep.is_empty() and keep[0] < _list.item_count:
		_list.select(keep[0])
	_refresh_contraband()


## The stash's contraband and the fixer's offer for each (wave 6).
func _refresh_contraband() -> void:
	if _contra == null:
		return
	_contra_ids.clear()
	_contra.clear()
	var fixer := Fixers.buyer()
	var counts := BaseArmory.counts(BaseHub.stash())
	for id: String in counts:
		if not Fixers.is_contraband(StringName(id)) or int(counts[id]) <= 0:
			continue
		_contra_ids.append(StringName(id))
		var offer := "%s pays $%s each" % [String(fixer.fixer), DebriefCalc.money(Fixers.offer(StringName(id)))] if not fixer.is_empty() else "no fixer will deal with us"
		_contra.add_item("%s x%d   %s (at the base: $%s, and lawful employers think less of us)" % [ItemDB.get_item(StringName(id)).name, int(counts[id]), offer,
			DebriefCalc.money(Prices.sell_price(StringName(id)))])
	if _contra_ids.is_empty():
		_contra.add_item("None: contraband turns up at checkpoints, compounds and HQs")


## Contraband listed now (tests).
func contraband_listed() -> Array[StringName]:
	return _contra_ids


func sell_contraband_selected() -> void:
	var picked := _contra.get_selected_items()
	if picked.is_empty() or picked[0] >= _contra_ids.size():
		_notice.text = "Pick some contraband to sell"
		return
	Economy.sell_contraband(_contra_ids[picked[0]], 1)


## Items listed now (tests).
func listed() -> Array[StringName]:
	return _ids


func select(id: StringName) -> void:
	var i := _ids.find(id)
	if i >= 0:
		_list.select(i)
		_show_info(i)


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
