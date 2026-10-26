class_name TradeScreen
extends PanelContainer
## The barter screen (docs/survival_world.md section 8, call 26): opened from the talk menu's
## "Trade" on a trader (the host sends the deal: Barter.deal). Two columns, yours and theirs, each
## item with its price to this trader (theirs at what they ask, yours at what they pay: their need
## and their standing with you move both; cash is cash) and a count to put on the table; a running
## balance; Confirm when the balance favours them or comes out even (they refuse anything less on
## the host too). Escape or Close shuts it. Headless-safe; text() is what tests read.

static var _current: TradeScreen = null

var deal := {}
## On the table: {item id: n} of yours, and of theirs.
var give := {}
var take := {}
var _box: VBoxContainer


static func current() -> TradeScreen:
	return _current if _current != null and is_instance_valid(_current) else null


func _init() -> void:
	name = "TradeScreen"
	visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _enter_tree() -> void:
	_current = self


## Shows `d` (a fresh deal, or the same trader's after a swap: what's on the table is cleared).
func open(d: Dictionary) -> void:
	var same := String(d.get("trader", "")) == String(deal.get("trader", "")) and visible
	deal = d
	give.clear()
	take.clear()
	visible = true
	if not same and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## What's on the table is worth to them (>= 0: they'll take it): Barter.balance.
func balance() -> float:
	return Barter.balance(deal, give, take)


func can_confirm() -> bool:
	return String(deal.get("why", "")) == "" and (not give.is_empty() or not take.is_empty()) and balance() >= -0.01


## Puts `n` more (or fewer) of item `id` on the table from `side` ("yours" | "theirs").
func put(side: String, id: String, n: int) -> void:
	var table := give if side == "yours" else take
	var have := 0
	for row: Dictionary in deal.get(side, []):
		if String(row.id) == id:
			have = int(row.count)
	var now := clampi(int(table.get(id, 0)) + n, 0, have)
	if now == 0:
		table.erase(id)
	else:
		table[id] = now
	refresh()


func confirm() -> void:
	if not can_confirm():
		return
	var intel := Intel.get_intel()
	if intel:
		intel.request_trade(String(deal.trader), give.duplicate(), take.duplicate())


func refresh() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var who := String(deal.get("name", "Trader"))
	if String(deal.get("group_name", "")) != "":
		who += " (%s)" % String(deal.group_name)
	_box.add_child(UiKit.heading("Trading with %s" % who))
	if String(deal.get("said", "")) != "":
		_box.add_child(UiKit.hint("\"%s\"" % String(deal.said)))
	if String(deal.get("why", "")) != "":
		_box.add_child(UiKit.warn(String(deal.why)))
	var cols := HBoxContainer.new()
	cols.add_child(_column("yours", "Yours (what they'd pay)", give))
	cols.add_child(_column("theirs", "Theirs (what they ask)", take))
	_box.add_child(cols)
	var bal := balance()
	var line := "Balance: $%d %s" % [absi(roundi(bal)), "in their favour" if bal > 0.5 else ("in yours: they won't take it" if bal < -0.5 else "even")]
	_box.add_child(UiKit.warn(line) if bal < -0.01 else UiKit.text(line))
	var ok := UiKit.button("Confirm", confirm, "Swap what's on the table")
	ok.disabled = not can_confirm()
	_box.add_child(UiKit.button_row([ok, UiKit.button("Close", close, "Walk away")]))


func _column(side: String, title: String, table: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.heading(title))
	var rows: Array = deal.get(side, [])
	if rows.is_empty():
		col.add_child(UiKit.hint("Nothing"))
	for row: Dictionary in rows:
		var id := String(row.id)
		var r := HBoxContainer.new()
		var on := int(table.get(id, 0))
		var label := UiKit.text("%s x%d  $%d%s" % [String(row.name), int(row.count), roundi(float(row.price)), ("  [%d on the table]" % on) if on > 0 else ""])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(label)
		r.add_child(UiKit.button("-", func() -> void: put(side, id, -1), "One less"))
		r.add_child(UiKit.button("+", func() -> void: put(side, id, 1), "One more"))
		col.add_child(r)
	return col


## The screen's words, top to bottom (tests).
func text() -> String:
	var out := PackedStringArray()
	for c in _box.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(CharacterScreen._text_of(c))
	return "\n".join(out)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and SurvivalLevel.of(self) == null:
		visible = false
