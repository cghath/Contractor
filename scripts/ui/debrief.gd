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
##
## feat/ui-pass (Captain's tasking, 2026-10-19): built from the shared kit (UiKit, the theme)
## with no sizes or colours of its own, nothing under 14 px; the salvage table's item column
## wraps and takes what the numbers leave; a tagged lot's or intel's buttons wrap under its
## line (UiKit.action_row); casualties one each. ui_test's strict checks fit it full.

signal closed

## The panel's widest (so the claim buttons stay next to the items on wide screens).
const MAX_WIDTH := 1100.0
const SORTS := ["value", "category", "name"]
const SORT_NAMES := {"value": "Total value", "category": "Category", "name": "Name"}
## The salvage table's item column at its narrowest (it wraps; the numbers and buttons don't).
const ITEM_MIN := 140.0
## A casualty line's widest before it cuts with "..." (an injury is a longer line than an item).
const CASUALTY_CAP := 480.0

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
	add_child(UiKit.dim(0.72))
	_panel = UiKit.panel(true)
	UiKit.apply(_panel)
	add_child(_panel)
	var root := VBoxContainer.new()
	_panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_title = UiKit.title("")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var help := UiKit.help_panel(PackedStringArray([
		"What the deployment earned and cost: the contract's pay and bonuses, what was carried out, casualties, and every expense.",
		"Salvage: pick which lots the company claims (its salvage share sets how much counts as yours). Claims are banked when the host presses Continue.",
		"Tagged pallets and vehicles go home on a cargo run; intel found opens new leads on the contract board.",
	]), [["Esc", "Continue"], ["Tab / arrows", "Move"], ["Enter", "Press"]])
	help.visible = false
	var q := UiKit.help_button(help)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(q)
	root.add_child(UiKit.subtitle("How the deployment went: what it paid, what it cost, and the salvage to claim.", false))
	root.add_child(help)
	root.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	root.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	root.add_child(HSeparator.new())
	## Continue pinned under the scroll (docs/ui_audit.md P1-16), beside what Esc does.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(footer)
	var keys := VBoxContainer.new()
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_theme_constant_override(&"separation", 0)
	keys.add_child(UiKit.key_hint("Esc", "Continue"))
	keys.add_child(UiKit.hint("Salvage claims are banked when the host continues."))
	footer.add_child(keys)
	var cont := UiKit.accent_button("Continue", close, "Close the debrief (the host's closing banks the salvage claims)")
	cont.name = "Continue"
	cont.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	UiKit.focus_first(_panel)


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
	_tagged(d)
	_intel(d)


func _restore_scroll() -> void:
	if is_instance_valid(_scroll) and _scroll_to >= 0:
		_scroll.scroll_vertical = _scroll_to
	_scroll_to = -1


func _header(d: Dictionary) -> void:
	var totals: Dictionary = d.get("totals", {})
	var outcomes := PackedStringArray((d.get("contracts", []) as Array).map(func(c: Dictionary) -> String: return String(c.outcome).to_upper()))
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override(&"h_separation", UiKit.SPACE_L + UiKit.SPACE_S)
	stats.add_theme_constant_override(&"v_separation", UiKit.SPACE_S)
	_box.add_child(stats)
	stats.add_child(UiKit.stat("Outcome", ", ".join(outcomes) if not outcomes.is_empty() else "-"))
	stats.add_child(UiKit.stat("Paid now", "$" + DebriefCalc.money(totals.get("paid_now", 0))))
	stats.add_child(UiKit.stat("Fines", ("-$" + DebriefCalc.money(d.get("fines", 0))) if int(d.get("fines", 0)) > 0 else "none"))
	stats.add_child(UiKit.stat("Days", str(int(d.get("days", 0)))))
	if d.has("expenses_total"):
		stats.add_child(UiKit.stat("Expenses", "-$" + DebriefCalc.money(d.expenses_total)))
		## Economy overhaul 2026-10-20: the contract's own result; loot and salvage sell later.
		stats.add_child(UiKit.stat("Net (before loot)", "$" + DebriefCalc.money(d.get("net", 0))))
	var sold_here: int = DebriefCalc.money_in(d).filter(func(l: Dictionary) -> bool: return String(l.what).ends_with(" sold")) \
		.reduce(func(acc: int, l: Dictionary) -> int: return acc + int(l.amount), 0)
	if sold_here > 0:
		stats.add_child(UiKit.stat("Sold here", "$" + DebriefCalc.money(sold_here)))
	_line("Got out: %s" % ", ".join(PackedStringArray(d.get("extracted", []))) if not (d.get("extracted", []) as Array).is_empty() else "Got out: (not reported)")
	## One entry each, the dead in the warning colour (one comma-separated run-on line before,
	## docs/ui_audit.md P1-16).
	var casualties: Array = d.get("casualties", [])
	if casualties.is_empty():
		_line("Casualties and injuries: none")
	else:
		_box.add_child(UiKit.hint("Casualties and injuries (%d)" % casualties.size()))
		var list := HFlowContainer.new()
		list.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
		_box.add_child(_indent(list, UiKit.SPACE_L))
		for c: Dictionary in casualties:
			var who := "%s (%s%s)" % [c.get("name", "?"), String(c.get("status", "")).to_upper(), ": " + String(c.injury) if String(c.get("injury", "")) != "" else ""]
			var label := UiKit.cell(who, &"WarnLabel" if String(c.get("status", "")) == "kia" else &"")
			UiKit.fit_label_text(label, CASUALTY_CAP)
			list.add_child(label)
	var income := DebriefCalc.money_in(d)
	var income_total: int = income.reduce(func(acc: int, l: Dictionary) -> int: return acc + int(l.amount), 0)
	if _section("income", "WHERE THE MONEY CAME FROM: $%s" % DebriefCalc.money(income_total)):
		for l: Dictionary in income:
			_line("%s: %s$%s" % [l.what, "-" if int(l.amount) < 0 else "", DebriefCalc.money(absi(int(l.amount)))], UiKit.SPACE_L)
		if income.is_empty():
			_line("Nothing was paid on this deployment.", UiKit.SPACE_L)
		_box.add_child(_indent(UiKit.hint("Loot and salvage brought home sell at the base shop (contraband to a fixer)."), UiKit.SPACE_L))
	if d.has("expenses_total") and _section("expenses", "WHERE THE MONEY WENT: -$%s" % DebriefCalc.money(d.expenses_total)):
		for l: Dictionary in d.get("expenses", []):
			_line("%s: -$%s" % [l.what, DebriefCalc.money(l.amount)], UiKit.SPACE_L)
		var daily := Economy.weekly_bill()
		var week_days := maxi(MissionRegistry.setting_i("week_days", 7), 1)
		var text := "Running costs now: $%s a day (wages $%s, upkeep $%s)" % [DebriefCalc.money(roundi(float(daily.total - daily.loans) / week_days)),
			DebriefCalc.money(roundi(float(daily.wages) / week_days)), DebriefCalc.money(roundi(float(daily.upkeep) / week_days))]
		if int(daily.loans) > 0:
			text += "; loan installments $%s in %d day%s" % [DebriefCalc.money(daily.loans), Economy.days_to_bill(), "" if Economy.days_to_bill() == 1 else "s"]
		_line(text, UiKit.SPACE_L)
	if _section("details", "Contract details, pay and reputation"):
		for l: String in DebriefCalc.summary(d):
			var depth := 2 if l.begins_with("    ") else (1 if l.begins_with("  ") else 0)
			_line(l.strip_edges(), UiKit.SPACE_L + UiKit.SPACE_M * depth)


## What was carried out, summed per item type, in collapsible categories.
func _carried(d: Dictionary) -> void:
	var groups := DebriefCalc.group_items(d.get("items_out", []))
	var total: int = groups.reduce(func(acc: int, g: Dictionary) -> int: return acc + int(g.count), 0)
	if not _section("carried", "CARRIED OUT (banked at base): %s" % ("nothing" if groups.is_empty() else "%d items, %d kinds" % [total, groups.size()])):
		return
	for cat: String in DebriefCalc.CATEGORIES:
		var mine := groups.filter(func(g: Dictionary) -> bool: return g.category == cat)
		if mine.is_empty():
			continue
		var n: int = mine.reduce(func(acc: int, g: Dictionary) -> int: return acc + int(g.count), 0)
		if not _section("carried:" + cat, "%s (%d)" % [DebriefCalc.CATEGORY_NAMES[cat], n], false, UiKit.SPACE_L):
			continue
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
		_box.add_child(_indent(flow, UiKit.SPACE_L * 2))
		for g: Dictionary in mine:
			var label := UiKit.cell("%d x %s" % [int(g.count), g.name])
			label.tooltip_text = item_tip(g.id)
			UiKit.fit_label_text(label)
			flow.add_child(label)


## `control` moved in from the left by `px`.
func _indent(control: Control, px: int) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", px)
	pad.add_child(control)
	return pad


## A section heading with a fold button; returns whether it is open. `top`: a main section
## (the heading style, a gap above it); else a sub-section in body text, `indent` px in.
func _section(key: String, text: String, top := true, indent := 0) -> bool:
	if top:
		_gap()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	_box.add_child(_indent(row, indent))
	var open: bool = not _collapsed.get(key, false)
	var fold := UiKit.button("-" if open else "+", func() -> void:
		_collapsed[key] = open
		refresh(), "Fold" if open else "Unfold")
	fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(fold)
	var label := UiKit.heading(text) if top else UiKit.text(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return open


## A main section's heading without a fold.
func _heading(text: String) -> void:
	_gap()
	_box.add_child(UiKit.heading(text))


## The space above a main section.
func _gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = UiKit.SPACE_S
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(gap)


func _salvage(d: Dictionary) -> void:
	var salvage: Dictionary = d.get("salvage", {})
	var budget := int(salvage.get("budget", 0))
	var spent := int(salvage.get("spent", 0))
	var finished: bool = d.get("finished", false)
	_heading("SALVAGE: share %d%% of $%s left in the field" % [roundi(float(salvage.get("share", 0)) * 100.0), DebriefCalc.money(salvage.get("pool_value", 0))])
	var bar := UiKit.budget_bar(spent, maxi(budget, 1), "Claimed $%s of $%s budget ($%s left)" % [DebriefCalc.money(spent), DebriefCalc.money(budget), DebriefCalc.money(budget - spent)])
	bar.tooltip_text = "Claimed against the salvage budget"
	_box.add_child(bar)
	var groups := DebriefCalc.salvage_groups(d, _sort)
	if groups.is_empty():
		_line("Nothing of value was left in the field.")
		return
	var sort := OptionButton.new()
	for s: String in SORTS:
		sort.add_item(SORT_NAMES[s])
	sort.selected = SORTS.find(_sort)
	sort.tooltip_text = "Sort the salvage table"
	sort.item_selected.connect(func(i: int) -> void:
		_sort = SORTS[i]
		refresh())
	var tools: Array = [UiKit.cell("Sort by"), sort]
	if not finished:
		var best_picks := DebriefCalc.best_value_picks(d)
		var best := UiKit.button("Claim best value", func() -> void: _pick(best_picks), "Fill what's left of the budget with the most valuable lots")
		best.disabled = best_picks.is_empty()
		tools.append(best)
		var picked: Array = (salvage.get("picked", []) as Array).duplicate()
		var none := UiKit.button("Return all", func() -> void: _unpick(picked), "Give back every lot claimed")
		none.disabled = picked.is_empty()
		tools.append(none)
	_box.add_child(UiKit.button_row(tools))
	var grid := UiKit.table(["Item", "Claimed / qty", "Each", "Total"] + ([] if finished else ["Claim"]))
	_box.add_child(grid)
	for g: Dictionary in groups:
		_salvage_row(grid, d, g, finished)


## One item type's row: name, claimed / quantity, value each and in all, and (still open)
## return one, claim one, claim as many as fit. A claimed row is green; a row nothing more of
## fits is dimmed, its buttons off with the reason as their tooltip.
func _salvage_row(grid: GridContainer, d: Dictionary, g: Dictionary, finished: bool) -> void:
	var why := DebriefCalc.pick_block_reason(d, g.id)
	var some := int(g.picked_count) > 0
	var all_in: bool = (g.picked as Array).size() == (g.lots as Array).size()
	var style := &"GoodLabel" if some else (&"MutedLabel" if why != "" else &"")
	var lots := (g.lots as Array).size()
	var item := UiKit.text(String(g.name))
	item.theme_type_variation = style
	item.custom_minimum_size.x = ITEM_MIN
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	var tip := item_tip(g.id)
	item.tooltip_text = "%s%s, %d lot%s in the field%s" % [(tip + "\n\n") if tip != "" else "", DebriefCalc.CATEGORY_NAMES[g.category], lots,
		"" if lots == 1 else "s", ("\n" + why) if why != "" and not all_in else ""]
	grid.add_child(item)
	var qty := UiKit.cell("%d / %d%s" % [int(g.picked_count), int(g.count), "  CLAIMED" if all_in else ""], style)
	grid.add_child(qty)
	grid.add_child(UiKit.cell("$" + DebriefCalc.money(g.each), style))
	grid.add_child(UiKit.cell("$" + DebriefCalc.money(g.value), style))
	if finished:
		return
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", UiKit.SPACE_XS)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(controls)
	var less := UiKit.button("-", func() -> void: _unpick(DebriefCalc.unpicks_for(d, g.id, 1)), "Return one lot")
	less.disabled = not some
	controls.add_child(less)
	var more := UiKit.button("+", func() -> void: _pick(DebriefCalc.picks_for(d, g.id, 1)), why if why != "" else "Claim one more lot")
	more.disabled = why != ""
	controls.add_child(more)
	var most := UiKit.button("Max", func() -> void: _pick(DebriefCalc.picks_for(d, g.id, -1)), why if why != "" else "Claim as many as fit the budget")
	most.disabled = why != ""
	controls.add_child(most)


## Asks the host for these pool lots (in order: each fits after the ones before it).
func _pick(indices: Array) -> void:
	for i: int in indices:
		Contracts.pick_salvage(i)


func _unpick(indices: Array) -> void:
	for i: int in indices:
		Contracts.unpick_salvage(i)


## Tagged pallets and vehicles hauled home (feat/pallet-tagging, Pallets): sell now at the quick
## price, store, gift to a faction, or keep as the FOB's own stocks. A lot's buttons wrap under
## its line (UiKit.action_row): five controls beside the text ran off a narrow panel.
func _tagged(d: Dictionary) -> void:
	var lots: Array = d.get("tagged", [])
	if lots.is_empty():
		return
	_heading("TAGGED PALLETS AND VEHICLES hauled home")
	for i in lots.size():
		var lot: Dictionary = lots[i]
		var status := String(lot.get("status", "pending"))
		var tag := "tagged to sell" if String(lot.get("tag", "")) == "sell" else "tagged for %s" % MissionRegistry.faction_name(String(lot.get("faction", "")))
		var verdict: String = {"pending": "undecided", "sold": "sold", "gifted": "gifted to %s" % MissionRegistry.faction_name(String(lot.get("gifted_to", ""))),
			"kept": "kept for the FOB's stocks", "stored": "in FOB storage"}.get(status, status)
		var text := "%s, %s: %s" % [Pallets.lot_text(lot), tag, verdict]
		if status != "pending" or d.get("finished", false):
			_line(text)
			continue
		var controls: Array = []
		controls.append(UiKit.button("Sell now ($%s)" % DebriefCalc.money(Pallets.sell_price(lot)), func() -> void: Contracts.pallet_action("debrief", i, "sell"),
			"The quick price. In FOB storage it sells for more later ($%s)." % DebriefCalc.money(Pallets.sell_price(lot, true))))
		controls.append(UiKit.button("Store", func() -> void: Contracts.pallet_action("debrief", i, "store"), "Keep it in FOB storage to sell, gift or keep later."))
		if Pallets.can_keep(lot):
			controls.append(UiKit.button("Keep for FOB", func() -> void: Contracts.pallet_action("debrief", i, "keep"),
				"Add it to the FOB's stocks: fuel and parts cut support and repair costs, ammo, supplies and medical restock the stash."))
		var factions := OptionButton.new()
		factions.tooltip_text = "The faction to gift it to"
		for f: String in Pallets.gift_factions():
			factions.add_item(MissionRegistry.faction_name(f))
			factions.set_item_metadata(factions.item_count - 1, f)
			if f == String(lot.get("faction", "")):
				factions.select(factions.item_count - 1)
		controls.append(factions)
		controls.append(UiKit.button("Gift (+%d rep)" % Pallets.gift_rep(lot), func() -> void:
			if factions.item_count > 0:
				Contracts.pallet_action("debrief", i, "gift", String(factions.get_item_metadata(factions.selected))),
			"Give it to the faction picked beside it, for reputation"))
		_box.add_child(UiKit.action_row(text, controls))
	_box.add_child(UiKit.hint("Anything undecided when you continue: a gift tag is gifted, the rest goes to FOB storage."))


func _intel(d: Dictionary) -> void:
	var intel: Array = d.get("intel", [])
	if intel.is_empty() and int(d.get("intel_repeats", 0)) == 0:
		return
	_heading("INTEL brought out")
	if int(d.get("intel_repeats", 0)) > 0:
		_line("%d piece%s already handed over in an earlier debrief: worth nothing now" % [int(d.intel_repeats), "" if int(d.intel_repeats) == 1 else "s"])
	var client := String((d.contracts as Array)[0].employer) if not (d.get("contracts", []) as Array).is_empty() else ""
	for i in intel.size():
		var e: Dictionary = intel[i]
		var status := String(e.get("status", "pending"))
		var text := "%d x %s: %s" % [int(e.count), _name(e.id), {"pending": "undecided", "turned_in": "turned in (new leads on the board)",
			"sold": "sold to %s for $%s%s" % [MissionRegistry.faction_name(String(e.get("buyer", ""))), DebriefCalc.money(e.get("price", 0)),
				" (the client found out)" if e.get("caught", false) else ""]}.get(status, status)]
		if status != "pending" or d.get("finished", false):
			_line(text)
			continue
		var turn_in := UiKit.button("Turn in to %s" % MissionRegistry.faction_name(client), func() -> void: Contracts.turn_in_intel(i),
			"Hand it to the client: new leads on the board")
		var buyers := OptionButton.new()
		buyers.tooltip_text = "Who to sell it to (the client may find out)"
		for f: String in MissionRegistry.faction_ids():
			if f != client:
				buyers.add_item(MissionRegistry.faction_name(f))
				buyers.set_item_metadata(buyers.item_count - 1, f)
		var sell := UiKit.button("Sell ($%s)" % DebriefCalc.money(Prices.intel_sale_value(StringName(e.id), int(e.count))), func() -> void:
			if buyers.item_count > 0:
				Contracts.sell_intel(i, String(buyers.get_item_metadata(buyers.selected))),
			"Sell it to the faction picked beside it (risks the client's anger)")
		_box.add_child(UiKit.action_row(text, [turn_in, buyers, sell]))


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


## A line of body text that wraps, `indent` px in.
func _line(text: String, indent := 0) -> void:
	var label := UiKit.text(text)
	_box.add_child(_indent(label, indent) if indent > 0 else label)


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
