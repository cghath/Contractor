class_name DebriefScreen
extends CanvasLayer
## The debrief after extraction (wave 4, W10), on every peer: pay earned (advance,
## completion, bonuses), penalties (civilian fines), reputation changes, casualties and
## injuries, what was carried out, salvage picks against the salvage budget (MW5-style:
## claim items left in the field), and intel to turn in (opens leads) or sell to another
## faction (risking the client's anger). Choices go to the host (Contracts requests);
## Continue closes it (the host's banks the salvage picks).
##
## Captain, 2026-10-14 (v0.3.1): "this ui needs a pass for sure. its hard to select the items
## you want". So: one centred panel sized to the screen (panel_rect, every resolution and UI
## scale) over a dimmed backdrop, scrolling inside, Continue in its footer; a summary header;
## what was carried out summed per item type in collapsible categories; salvage as a table, one
## row per item type (DebriefCalc.salvage_groups) with the claim controls next to the item,
## a budget bar, sorting and a "claim best value" helper. The claims are still the host's
## per-lot pick/unpick requests: the screen only chooses which lots to ask for.

signal closed

## The panel's widest (so the claim buttons stay next to the items on wide screens).
const MAX_WIDTH := 1100.0
const TITLE_COLOR := Color("c8d6a0")
const DIM_COLOR := Color(0.62, 0.64, 0.6)
const SORTS := ["value", "category", "name"]
const SORT_NAMES := {"value": "Total value", "category": "Category", "name": "Name"}

var _panel: PanelContainer
var _scroll: ScrollContainer
var _title: Label
var _box: VBoxContainer
var _mouse_before := Input.MOUSE_MODE_VISIBLE
## Collapsed sections ("details", "carried", "carried:<category>"), kept across refreshes.
var _collapsed := {}
var _sort := "value"
var _scroll_to := -1
## The size fit() was last given (ZERO: this screen's own viewport, as in the game).
var _view := Vector2.ZERO


func _ready() -> void:
	layer = 12
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## A dimmed backdrop: the panel reads on its own, and the HUD (the squad list bottom left)
	## sits muted under it instead of showing through the text.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.05, 0.96)
	style.border_color = Color(0.3, 0.36, 0.26)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	_panel.add_child(root)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 22)
	_title.add_theme_color_override(&"font_color", TITLE_COLOR)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_title)
	root.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_box)
	root.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 12)
	root.add_child(footer)
	var hint := Label.new()
	hint.text = "Esc also continues. Salvage claims are banked when the host continues."
	hint.add_theme_color_override(&"font_color", DIM_COLOR)
	hint.add_theme_font_size_override(&"font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var cont := Button.new()
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(140, 34)
	cont.pressed.connect(close)
	footer.add_child(cont)
	get_viewport().size_changed.connect(_fit)
	## A container grows to its minimum but never shrinks back: the wrapped title and footer
	## hint ask to be very tall while they're still narrow (before the first layout), and the
	## panel kept that height, running off the bottom of the window until the window's size
	## changed. So it's refitted whenever its minimum changes.
	_panel.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_fit()
	Contracts.changed.connect(refresh)
	refresh()


## Where the panel goes on a `viewport` of that size (in UI units, so the UI scale is already
## in it): centred, at most MAX_WIDTH wide, a margin all round.
static func panel_rect(viewport: Vector2) -> Rect2:
	var margin := clampf(minf(viewport.x, viewport.y) * 0.04, 12.0, 48.0)
	var size := Vector2(minf(MAX_WIDTH, viewport.x - 2.0 * margin), viewport.y - 2.0 * margin)
	return Rect2((viewport - size) * 0.5, size)


## Sizes the panel to `viewport` (default: this screen's visible rect; tests pass sizes).
func fit(viewport := Vector2.ZERO) -> void:
	_view = viewport
	_fit()


func _fit() -> void:
	if not is_instance_valid(_panel) or not is_inside_tree():
		return
	var viewport := _view
	if viewport == Vector2.ZERO:
		viewport = get_viewport().get_visible_rect().size
	var rect := panel_rect(viewport)
	_panel.position = rect.position
	_panel.size = rect.size


## The panel (tests check it fits).
func panel() -> PanelContainer:
	return _panel


func refresh() -> void:
	if not is_instance_valid(_box):
		return
	## Rebuilt on every change (each claim): keep the reader where they were.
	if _scroll_to < 0:
		_scroll_to = _scroll.scroll_vertical
		get_tree().process_frame.connect(_restore_scroll, CONNECT_ONE_SHOT)
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var d := Contracts.last_debrief()
	if d.is_empty():
		_title.text = "DEBRIEF"
		_line("No debrief yet.")
		return
	_title.text = "DEBRIEF - %s (day %d)" % [d.get("zone_name", ""), int(d.get("day", 0))]
	_header(d)
	_carried(d)
	_salvage(d)
	_intel(d)


func _restore_scroll() -> void:
	if is_instance_valid(_scroll) and _scroll_to >= 0:
		_scroll.scroll_vertical = _scroll_to
	_scroll_to = -1


func _header(d: Dictionary) -> void:
	var totals: Dictionary = d.get("totals", {})
	var outcomes := PackedStringArray((d.get("contracts", []) as Array).map(func(c: Dictionary) -> String: return String(c.outcome).to_upper()))
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override(&"h_separation", 28)
	_box.add_child(stats)
	_stat(stats, "Outcome", ", ".join(outcomes) if not outcomes.is_empty() else "-")
	_stat(stats, "Paid now", "$" + DebriefCalc.money(totals.get("paid_now", 0)))
	_stat(stats, "Fines", ("-$" + DebriefCalc.money(d.get("fines", 0))) if int(d.get("fines", 0)) > 0 else "none")
	_stat(stats, "Days", str(int(d.get("days", 0))))
	if d.has("expenses_total"):
		_stat(stats, "Expenses", "-$" + DebriefCalc.money(d.expenses_total))
		_stat(stats, "Net after expenses", "$" + DebriefCalc.money(d.get("net", 0)))
	_line("Got out: %s" % ", ".join(PackedStringArray(d.get("extracted", []))) if not (d.get("extracted", []) as Array).is_empty() else "Got out: (not reported)")
	var casualties: Array = d.get("casualties", [])
	_line("Casualties and injuries: %s" % ("none" if casualties.is_empty() else ", ".join(PackedStringArray(casualties.map(func(c: Dictionary) -> String:
		return "%s (%s%s)" % [c.get("name", "?"), String(c.get("status", "")).to_upper(), ": " + String(c.injury) if String(c.get("injury", "")) != "" else ""])))))
	if d.has("expenses_total") and _section("expenses", "WHERE THE MONEY WENT: -$%s" % DebriefCalc.money(d.expenses_total), 15):
		for l: Dictionary in d.get("expenses", []):
			_line("  %s: -$%s" % [l.what, DebriefCalc.money(l.amount)], 14)
		var bill := Economy.weekly_bill()
		_line("  Next weekly bill: $%s in %d days (wages $%s, upkeep $%s)" % [DebriefCalc.money(bill.total), Economy.days_to_bill(), DebriefCalc.money(bill.wages), DebriefCalc.money(bill.upkeep)], 14)
	if _section("details", "Contract details, pay and reputation", 15):
		for l: String in DebriefCalc.summary(d):
			_line(l, 14)


func _stat(parent: Control, what: String, value: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	parent.add_child(box)
	var key := Label.new()
	key.text = what
	key.add_theme_font_size_override(&"font_size", 12)
	key.add_theme_color_override(&"font_color", DIM_COLOR)
	box.add_child(key)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override(&"font_size", 18)
	box.add_child(val)


## What was carried out, summed per item type, in collapsible categories.
func _carried(d: Dictionary) -> void:
	var groups := DebriefCalc.group_items(d.get("items_out", []))
	var total: int = groups.reduce(func(acc: int, g: Dictionary) -> int: return acc + int(g.count), 0)
	_line("")
	if not _section("carried", "CARRIED OUT (banked at base): %s" % ("nothing" if groups.is_empty() else "%d items, %d kinds" % [total, groups.size()]), 17):
		return
	for cat: String in DebriefCalc.CATEGORIES:
		var mine := groups.filter(func(g: Dictionary) -> bool: return g.category == cat)
		if mine.is_empty():
			continue
		var n: int = mine.reduce(func(acc: int, g: Dictionary) -> int: return acc + int(g.count), 0)
		if not _section("carried:" + cat, "%s (%d)" % [DebriefCalc.CATEGORY_NAMES[cat], n], 15, 16):
			continue
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override(&"h_separation", 22)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override(&"margin_left", 46)
		pad.add_child(flow)
		_box.add_child(pad)
		for g: Dictionary in mine:
			var label := Label.new()
			label.text = "%d x %s" % [int(g.count), g.name]
			label.tooltip_text = item_tip(g.id)
			label.mouse_filter = Control.MOUSE_FILTER_PASS if label.tooltip_text != "" else Control.MOUSE_FILTER_IGNORE
			flow.add_child(label)


## A section heading with a fold button; returns whether it is open.
func _section(key: String, text: String, size := 15, indent := 0) -> bool:
	var row := HBoxContainer.new()
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", indent)
	pad.add_child(row)
	_box.add_child(pad)
	var open: bool = not _collapsed.get(key, false)
	var fold := Button.new()
	fold.text = "-" if open else "+"
	fold.flat = true
	fold.custom_minimum_size = Vector2(26, 0)
	fold.tooltip_text = "Fold" if open else "Unfold"
	fold.pressed.connect(func() -> void:
		_collapsed[key] = open
		refresh())
	row.add_child(fold)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", TITLE_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return open


func _salvage(d: Dictionary) -> void:
	var salvage: Dictionary = d.get("salvage", {})
	var budget := int(salvage.get("budget", 0))
	var spent := int(salvage.get("spent", 0))
	var finished: bool = d.get("finished", false)
	_line("")
	_line("SALVAGE: share %d%% of $%s left in the field" % [roundi(float(salvage.get("share", 0)) * 100.0), DebriefCalc.money(salvage.get("pool_value", 0))], 17, TITLE_COLOR)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override(&"separation", 12)
	_box.add_child(bar_row)
	var bar := ProgressBar.new()
	bar.max_value = maxi(budget, 1)
	bar.value = spent
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "Claimed against the salvage budget"
	bar_row.add_child(bar)
	var budget_label := Label.new()
	budget_label.text = "Claimed $%s of $%s budget ($%s left)" % [DebriefCalc.money(spent), DebriefCalc.money(budget), DebriefCalc.money(budget - spent)]
	budget_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	budget_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(budget_label)
	var groups := DebriefCalc.salvage_groups(d, _sort)
	if groups.is_empty():
		_line("Nothing of value was left in the field.")
		return
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override(&"h_separation", 10)
	_box.add_child(tools)
	var sort_label := Label.new()
	sort_label.text = "Sort by"
	tools.add_child(sort_label)
	var sort := OptionButton.new()
	for s: String in SORTS:
		sort.add_item(SORT_NAMES[s])
	sort.selected = SORTS.find(_sort)
	sort.item_selected.connect(func(i: int) -> void:
		_sort = SORTS[i]
		refresh())
	tools.add_child(sort)
	if not finished:
		var best_picks := DebriefCalc.best_value_picks(d)
		var best := Button.new()
		best.text = "Claim best value"
		best.tooltip_text = "Fill what's left of the budget with the most valuable lots"
		best.disabled = best_picks.is_empty()
		best.pressed.connect(func() -> void: _pick(best_picks))
		tools.add_child(best)
		var picked: Array = (salvage.get("picked", []) as Array).duplicate()
		var none := Button.new()
		none.text = "Return all"
		none.disabled = picked.is_empty()
		none.pressed.connect(func() -> void: _unpick(picked))
		tools.add_child(none)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 4)
	_box.add_child(grid)
	for h: String in ["Item", "Claimed / qty", "Each", "Total", "" if finished else "Claim"]:
		var head := Label.new()
		head.text = h
		head.add_theme_color_override(&"font_color", DIM_COLOR)
		head.add_theme_font_size_override(&"font_size", 13)
		grid.add_child(head)
	for g: Dictionary in groups:
		_salvage_row(grid, d, g, finished)


## One item type's row: name, claimed / quantity, value each and in all, and (still open)
## return one, claim one, claim as many as fit. A row nothing more of fits is dimmed, its
## buttons off with the reason as their tooltip.
func _salvage_row(grid: GridContainer, d: Dictionary, g: Dictionary, finished: bool) -> void:
	var why := DebriefCalc.pick_block_reason(d, g.id)
	var some := int(g.picked_count) > 0
	var all_in: bool = (g.picked as Array).size() == (g.lots as Array).size()
	var tint := Color(0.7, 0.95, 0.6) if some else (Color(1, 1, 1, 0.5) if why != "" else Color.WHITE)
	var lots := (g.lots as Array).size()
	var item := Label.new()
	item.text = String(g.name)
	item.custom_minimum_size = Vector2(230, 0)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	var tip := item_tip(g.id)
	item.tooltip_text = "%s%s, %d lot%s in the field%s" % [(tip + "\n\n") if tip != "" else "", DebriefCalc.CATEGORY_NAMES[g.category], lots,
		"" if lots == 1 else "s", ("\n" + why) if why != "" and not all_in else ""]
	var qty := Label.new()
	qty.text = "%d / %d%s" % [int(g.picked_count), int(g.count), "  CLAIMED" if all_in else ""]
	var each := Label.new()
	each.text = "$" + DebriefCalc.money(g.each)
	var total := Label.new()
	total.text = "$" + DebriefCalc.money(g.value)
	for label: Label in [item, qty, each, total]:
		label.modulate = tint
		grid.add_child(label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 4)
	grid.add_child(controls)
	if finished:
		return
	var less := _small("-", "Return one lot")
	less.disabled = not some
	less.pressed.connect(func() -> void: _unpick(DebriefCalc.unpicks_for(d, g.id, 1)))
	controls.add_child(less)
	var more := _small("+", why if why != "" else "Claim one more lot")
	more.disabled = why != ""
	more.pressed.connect(func() -> void: _pick(DebriefCalc.picks_for(d, g.id, 1)))
	controls.add_child(more)
	var most := _small("Max", why if why != "" else "Claim as many as fit the budget")
	most.disabled = why != ""
	most.pressed.connect(func() -> void: _pick(DebriefCalc.picks_for(d, g.id, -1)))
	controls.add_child(most)


func _small(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(34, 0)
	return b


## Asks the host for these pool lots (in order: each fits after the ones before it).
func _pick(indices: Array) -> void:
	for i: int in indices:
		Contracts.pick_salvage(i)


func _unpick(indices: Array) -> void:
	for i: int in indices:
		Contracts.unpick_salvage(i)


func _intel(d: Dictionary) -> void:
	var intel: Array = d.get("intel", [])
	if intel.is_empty():
		return
	_line("")
	_line("INTEL brought out", 17, TITLE_COLOR)
	var client := String((d.contracts as Array)[0].employer) if not (d.get("contracts", []) as Array).is_empty() else ""
	for i in intel.size():
		var e: Dictionary = intel[i]
		var row := HBoxContainer.new()
		_box.add_child(row)
		var label := Label.new()
		var status := String(e.get("status", "pending"))
		label.text = "%d x %s: %s" % [int(e.count), _name(e.id), {"pending": "undecided", "turned_in": "turned in (new leads on the board)",
			"sold": "sold to %s%s" % [MissionRegistry.faction_name(String(e.get("buyer", ""))), " (the client found out)" if e.get("caught", false) else ""]}.get(status, status)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(160, 0)
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


## A screen to click on, as the contract board is: whatever loads under it, the mouse stays
## free while it's up, and Escape closes it like Continue (Captain, 2026-10-14: a client's
## debrief stayed up after the host moved on, the new level's player took the mouse, and there
## was no getting off it).
func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


## Closes the screen; on the host it also closes the debrief (banks the salvage picks).
func close() -> void:
	if is_queued_for_deletion():
		return
	if Contracts.is_host():
		Contracts.finish_debrief()
	Input.mouse_mode = _mouse_before
	closed.emit()
	queue_free()


## Everything the screen says, as text (tests read it).
func text() -> String:
	var out := PackedStringArray()
	for node in _panel.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return "\n".join(out)


func _line(text: String, size := 15, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", size)
	if color != Color.WHITE:
		label.add_theme_color_override(&"font_color", color)
	_box.add_child(label)


static func _name(id: Variant) -> String:
	return DebriefCalc.item_name(id)


## Item tooltips from the item-info helper (feat/item-info: ItemInfo's tooltip text, or
## ItemDB.describe -> {name, desc, uses, stats}), looked up guarded so this screen works on a
## build without it; "" when neither is there.
const ITEM_INFO := "res://scripts/ui/item_info.gd"


static func item_tip(id: Variant) -> String:
	if ResourceLoader.exists(ITEM_INFO):
		var info: Script = load(ITEM_INFO)
		for method: String in ["tooltip_text", "tooltip"]:
			if info != null and info.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == method):
				var tip: Variant = info.call(method, StringName(id))
				if typeof(tip) == TYPE_STRING and tip != "":
					return tip
	if ItemDB.has_method(&"describe"):
		var described: Variant = ItemDB.call(&"describe", StringName(id))
		if described is Dictionary:
			var lines := PackedStringArray()
			for key: String in ["desc", "uses"]:
				var v: Variant = (described as Dictionary).get(key, "")
				var t := ", ".join(PackedStringArray(v)) if v is Array else str(v)
				if t != "":
					lines.append(t)
			return "\n".join(lines)
	return ""
