class_name ContractBoard
extends CanvasLayer
## The regional contract board (wave 4, W10): offers from the board, fixers and intel leads,
## each with its difficulty rating, what the briefing knows and the pay; MW5-style
## negotiation (pay, salvage share and support budget against negotiation points, and the
## advance); the contracts the company holds (renegotiate or abort when the briefing lied);
## cash, the day, loans and reputation. Every peer can open it (it shows the replicated
## state); what it does goes to the host (Contracts.accept and the other requests).
##
## The host also gets the debug controls that stand in for the rest of the loop until wave
## 4B joins it up: deploy on a held contract, end the deployment with everyone getting out
## (a debrief), let days pass, reset the campaign. The base agent places the board in the hub.

signal closed

var _header: Label
var _offers: ItemList
var _held: ItemList
var _details: Label
var _pay: SpinBox
var _salvage: SpinBox
var _support: SpinBox
var _advance: SpinBox
var _deal: Label
var _notice: Label
var _accept: Button
var _renegotiate: Button
var _abort: Button
var _deploy: Button
var _host_row: HBoxContainer
var _selected := ""          # cid
var _selected_held := false
var _offer_ids: Array[String] = []
var _held_ids: Array[String] = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _refreshing := false


func _ready() -> void:
	layer = 10
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		panel.set("offset_" + side, 40.0 if side in ["left", "top"] else -40.0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	panel.add_child(root)
	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 16)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	body.add_child(left)
	left.add_child(_title("Offers (board, fixers, leads)"))
	_offers = _list(left)
	_offers.item_selected.connect(func(i: int) -> void: _select(_offer_ids[i], false))
	left.add_child(_title("Held contracts"))
	_held = _list(left)
	_held.item_selected.connect(func(i: int) -> void: _select(_held_ids[i], true))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_details)
	right.add_child(_title("Negotiation"))
	var grid := GridContainer.new()
	grid.columns = 4
	right.add_child(grid)
	_pay = _spin(grid, "Pay points", 0, 10, 1)
	_salvage = _spin(grid, "Salvage points", 0, 10, 1)
	_support = _spin(grid, "Support points", 0, 10, 1)
	_advance = _spin(grid, "Advance %", 10, 50, 10)
	_deal = Label.new()
	_deal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_deal)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	_accept = _button(actions, "Accept contract", accept_selected)
	_renegotiate = _button(actions, "Renegotiate", func() -> void: Contracts.renegotiate(_selected))
	_abort = _button(actions, "Abort", func() -> void: Contracts.abort(_selected))
	_deploy = _button(actions, "Deploy (debug)", _debug_deploy)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_button(bottom, "Shop", func() -> void: get_tree().root.add_child(ShopScreen.new()))
	_button(bottom, "Take a loan", func() -> void: Economy.take_loan())
	_host_row = HBoxContainer.new()
	bottom.add_child(_host_row)
	_button(_host_row, "Wait a day", func() -> void: Economy.advance_days(1, "waiting at base"))
	_button(_host_row, "Wait a week", func() -> void: Economy.advance_days(MissionRegistry.setting_i("week_days", 7), "waiting at base"))
	_button(_host_row, "End deployment (debug)", _debug_extract)
	_button(_host_row, "Reset campaign", func() -> void: Contracts.new_full_campaign())
	_button(bottom, "Close", close)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.modulate = Color("ffd35a")
	root.add_child(_notice)
	Contracts.changed.connect(refresh)
	Economy.changed.connect(refresh)
	Contracts.notice.connect(_on_notice)
	Economy.notice.connect(_on_notice)
	refresh()


func close() -> void:
	Input.mouse_mode = _mouse_before
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


## Rebuilds the lists and the details from the replicated state.
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var host := Contracts.is_host()
	_host_row.visible = host
	_deploy.visible = host
	var e := Economy
	var reps := PackedStringArray()
	for f: String in MissionRegistry.faction_ids():
		reps.append("%s %+d (tier %d)" % [MissionRegistry.faction_name(f), e.reputation(f), e.tier(f)])
	_header.text = "CONTRACT BOARD   Day %d (week %d, bill in %d days)   Cash $%s   Owed $%s%s\nReputation: %s   Locals %+d" % [
		e.day(), e.week(), e.days_to_bill(), DebriefCalc.money(e.cash()), DebriefCalc.money(e.loans_owed()),
		"   DEPLOYED: %s" % Contracts.deployment().zone_name if Contracts.is_deployed() else "", "   ".join(reps), e.locals()]
	_offer_ids.clear()
	_offers.clear()
	for c: Dictionary in Contracts.board():
		_offer_ids.append(String(c.cid))
		_offers.add_item(offer_line(c))
	_held_ids.clear()
	_held.clear()
	for c: Dictionary in Contracts.held():
		_held_ids.append(String(c.cid))
		_held.add_item("%s  [%s]" % [offer_line(c), String(c.state).to_upper()])
	if _selected != "" and Contracts.contract(_selected).is_empty():
		_selected = ""
	_show_details()
	_refreshing = false


## One offer in a line: rating, zone kind, title, employer, pay.
static func offer_line(c: Dictionary) -> String:
	var stars := "*".repeat(int(c.get("rated", 1))) + ".".repeat(5 - int(c.get("rated", 1)))
	var tag: String = {"fixer": "FIXER %s: " % c.get("fixer", ""), "safe": "LOW RISK: ", "lead": ""}.get(String(c.get("source", "")), "")
	return "[%s] %s%s%s - %s - $%s" % [stars, "HOT ZONE " if c.get("zone_kind") == "hot" else "", tag, c.get("title", ""),
		MissionRegistry.faction_name(String(c.get("employer", ""))), DebriefCalc.money(c.get("base_pay", 0))]


func _select(cid: String, from_held: bool) -> void:
	_selected = cid
	_selected_held = from_held
	_show_details()


func _show_details() -> void:
	var c: Dictionary = Contracts.contract(_selected) if _selected != "" else {}
	var offer: bool = not c.is_empty() and c.get("state") == "offered"
	for w: Control in [_pay, _salvage, _support, _advance, _accept]:
		w.visible = offer
	_renegotiate.visible = not offer and c.get("revealed", false) and not c.get("renegotiated", false)
	_abort.visible = not c.is_empty() and c.get("state") in [Contracts.ACCEPTED, Contracts.DEPLOYED]
	_deploy.visible = Contracts.is_host() and c.get("state") == Contracts.ACCEPTED and not Contracts.is_deployed()
	if c.is_empty():
		_details.text = "Pick an offer to see its briefing and negotiate."
		_deal.text = ""
		return
	var lines := PackedStringArray([String(c.title), String(c.brief), ""])
	lines.append("Client: %s   Target: %s" % [MissionRegistry.faction_name(String(c.employer)), MissionRegistry.faction_name(String(c.target))])
	lines.append("Zone: %s (%s zone, %s)   %d day%s plus travel" % [c.zone_name, c.zone_kind, MissionRegistry.region(String(c.region)).get("name", c.region),
		int(c.days), "" if int(c.days) == 1 else "s"])
	lines.append("Difficulty %d/5   Intel accuracy %d%%" % [int(c.rated), roundi(float(c.intel_accuracy) * 100.0)])
	lines.append("Briefing: " + ContractGen.estimate_text(c))
	if c.get("revealed", false) and c.has("true_rating"):
		lines.append("ACTUAL THREAT: difficulty %d/5, %d fighters" % [int(c.true_rating), int(c.enemy_count)])
	lines.append("Objectives:")
	for o: Dictionary in c.get("objectives", []):
		lines.append("  - " + String(o.get("text", "")))
	if not offer:
		var deal: Dictionary = c.get("deal", {})
		lines.append("Terms: pay $%s (advance $%s paid, $%s on completion%s), salvage %d%%, support budget $%s left" % [
			DebriefCalc.money(deal.get("pay_total", 0)), DebriefCalc.money(deal.get("advance", 0)), DebriefCalc.money(deal.get("completion", 0)),
			" +$%s renegotiated" % DebriefCalc.money(c.raise) if c.has("raise") else "", roundi(float(deal.get("salvage_share", 0)) * 100.0),
			DebriefCalc.money(c.get("support_left", 0))])
		lines.append("Deploy by day %d" % int(c.get("deadline_day", 0)))
	else:
		lines.append("Offer open until day %d" % int(c.expires_day))
	_details.text = "\n".join(lines)
	_update_deal()


func _update_deal() -> void:
	var c := Contracts.contract(_selected)
	if c.is_empty() or c.get("state") != "offered":
		_deal.text = ""
		return
	var rep := Economy.reputation(String(c.employer))
	var points := ContractGen.max_points(rep)
	var t := terms()
	var deal := ContractGen.deal(c, t)
	var problem := ContractGen.terms_problem(t, rep)
	_deal.text = "Points %d of %d.   Pay $%s: advance $%s now (kept if it fails), $%s on completion.   Salvage %d%%.   Support budget $%s.%s" % [
		ContractGen.terms_cost(t), points, DebriefCalc.money(deal.pay_total), DebriefCalc.money(deal.advance), DebriefCalc.money(deal.completion),
		roundi(deal.salvage_share * 100.0), DebriefCalc.money(deal.support_budget), "\n" + problem if problem != "" else ""]
	_accept.disabled = problem != ""


## The terms set in the negotiation controls.
func terms() -> Dictionary:
	return {"pay_points": int(_pay.value), "salvage_points": int(_salvage.value), "support_points": int(_support.value),
		"advance_share": _advance.value / 100.0}


func set_terms(t: Dictionary) -> void:
	_pay.value = int(t.get("pay_points", 0))
	_salvage.value = int(t.get("salvage_points", 0))
	_support.value = int(t.get("support_points", 0))
	_advance.value = roundi(float(t.get("advance_share", 0.3)) * 100.0)
	_update_deal()


func select_offer(index: int) -> void:
	_offers.select(index)
	_select(_offer_ids[index], false)


func accept_selected() -> void:
	if _selected != "":
		Contracts.accept(_selected, terms())


func offer_count() -> int:
	return _offers.item_count


func held_count() -> int:
	return _held.item_count


func header_text() -> String:
	return _header.text


func details_text() -> String:
	return _details.text


func _debug_deploy() -> void:
	var why := Contracts.server_start_deployment([_selected])
	_on_notice(why if why != "" else "Deployed (debug): objectives are live")


## Host debug: everyone in the level (players and living squadmates) gets out now.
func _debug_extract() -> void:
	if not Contracts.is_deployed():
		_on_notice("Not deployed")
		return
	var level := CompoundLevel.current(self)
	var report := {}
	if level:
		var out: Array = []
		for node in level.get_tree().get_nodes_in_group(&"combatants"):
			var s := node as Soldier
			if s and s.faction == &"friendly" and not s.vitals.is_dead():
				out.append(s)
		report = Contracts.report_from_level(level, out)
	Contracts.server_end_deployment(report)


func _on_notice(text: String) -> void:
	if is_instance_valid(_notice):
		_notice.text = text


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 15)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _list(parent: Control) -> ItemList:
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 160)
	parent.add_child(list)
	return list


func _spin(parent: Control, label_text: String, lo: float, hi: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = lo if label_text != "Advance %" else roundi(MissionRegistry.setting_f("advance_share", 0.3) * 100.0)
	spin.value_changed.connect(func(_v: float) -> void: _update_deal())
	parent.add_child(spin)
	return spin


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
