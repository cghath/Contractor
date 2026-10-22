class_name MapHcPanel
extends PanelContainer
## The high command side panel on the map (docs/high_command.md 10, modelled on
## MapExtractionPanel): a card per squad (callsign, hero, strength, CE, order and its state or
## why) with Report / Regroup on me / Follow me / Cancel, who has command, and the company net's
## last lines. Shown while a high command group is out. In the shared look (UiKit).

const WIDTH := 300.0
const NET_LINES := 6

var _hc: HighCommand
var _box: VBoxContainer
var _cards: VBoxContainer
var _commander: Label
var _take: Button
var _net: Label
var _go_row: HFlowContainer
var _go_pick: OptionButton
var _asks: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	add_child(_box)
	var head := Label.new()
	head.text = "HIGH COMMAND"
	head.theme_type_variation = &"HeadingLabel"
	_box.add_child(head)
	_box.add_child(UiKit.subtitle("Right click the map to order a squad", false))
	_commander = UiKit.hint("")
	_box.add_child(_commander)
	_take = UiKit.button("Take command", func() -> void:
		if _hc:
			_hc.request_command(), "Hold the commander token: only its holder orders the squads")
	_box.add_child(_take)
	var dev := UiKit.button("Spawn a test squad (dev)", func() -> void:
		var me := MapNodes.local_player(self)
		if me:
			me._server_squad_command.rpc_id(1, "support:hc_dev_spawn", me.global_position, PackedStringArray()), "Dev tools: a hero squad of 4 beside you (not on the roster)")
	dev.visible = DevTools.on() and multiplayer.is_server()
	_box.add_child(dev)
	_box.add_child(UiKit.button("3D view [Shift+M]", func() -> void:
		var me := MapNodes.local_player(self)
		var screen := get_parent() as MapScreen
		if me and screen:
			screen.close()
			HcCamera.toggle(me), "The 3D high command camera over the zone: known enemies and our squads only"))
	_asks = VBoxContainer.new()
	_box.add_child(_asks)
	_go_pick = OptionButton.new()
	for label: String in ["Next order: now", "Next order: on Alpha", "Next order: on Bravo", "Next order: on Charlie"]:
		_go_pick.add_item(label)
	_go_pick.tooltip_text = "Hold the next order until its go code (Attack and Support by fire move to their position and wait)"
	_go_pick.item_selected.connect(func(i: int) -> void: MapCommandLayer.next_go = ["", "alpha", "bravo", "charlie"][i])
	_box.add_child(_go_pick)
	_go_row = HFlowContainer.new()
	_box.add_child(_go_row)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	_box.add_child(_cards)
	_box.add_child(UiKit.hint("Company net"))
	_net = UiKit.text("")
	_net.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_net)


## Shows `hc`'s state (call again whenever it changes).
func show_command(hc: HighCommand) -> void:
	_hc = hc
	if hc == null:
		return
	_commander.text = "Commander: %s" % ("you" if hc.is_commander() else "Player %d" % hc.commander)
	_take.visible = not hc.is_commander()
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for e: Dictionary in hc.view:
		_cards.add_child(_card(e))
	for c in _asks.get_children() + _go_row.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if hc.is_commander():
		for r: Dictionary in hc.requests:
			var rid := int(r.id)
			_asks.add_child(UiKit.text("%s: %s" % [r.callsign, r.text]))
			_asks.add_child(UiKit.button_row([UiKit.button("Approve (Shift+Y)", func() -> void: _hc.request_answer(rid, true), "Let them do it"),
				UiKit.button("Deny (Shift+N)", func() -> void: _hc.request_answer(rid, false), "They carry on with the order")]))
		for code: String in ["alpha", "bravo", "charlie"]:
			var n := _waiting(hc, code)
			var b := UiKit.button("Go %s (%d)" % [code.capitalize(), n], func() -> void: _hc.request_go(code), "Every squad waiting on %s goes now" % code.capitalize())
			b.disabled = n == 0
			_go_row.add_child(b)
	_go_pick.visible = hc.is_commander()
	var lines := PackedStringArray()
	for line: Dictionary in hc.net_log.slice(maxi(hc.net_log.size() - NET_LINES, 0)):
		lines.append(String(line.text))
	_net.text = "\n".join(lines) if not lines.is_empty() else "(quiet)"


## Orders waiting on go code `code`, from the view (every peer).
static func _waiting(hc: HighCommand, code: String) -> int:
	return hc.view.filter(func(e: Dictionary) -> bool: return String(e.get("order", {}).get("go", "")) == code and String(e.get("order", {}).get("state", "")) in ["waiting", "set"]).size()


func _card(e: Dictionary) -> Control:
	var card := VBoxContainer.new()
	var o: Dictionary = e.get("order", {})
	var title := UiKit.text("%s  %d/%d  %s%s" % [e.callsign, int(e.up), int(e.total), String(e.get("band", "")).to_upper(),
		"  CONTACT" if bool(e.get("contact", false)) else ""])
	card.add_child(title)
	var doing := "Idle"
	if not o.is_empty():
		doing = "%s: %s%s" % [HcOrder.verb_text(String(o.verb)).capitalize(), String(o.state), " (%s)" % o.why if String(o.get("why", "")) != "" else ""]
	if int(e.get("queue", 0)) > 0:
		doing += ", %d queued" % int(e.queue)
	card.add_child(UiKit.hint(("Led by %s. " % e.hero if String(e.get("hero", "")) != "" else "") + doing))
	if _hc.is_commander():
		var id := String(e.id)
		var me := MapNodes.local_player(self)
		var buttons: Array = [
			UiKit.button("Report", func() -> void: MapCommandLayer.send(_hc, id, "report", Vector2.INF), "Ask for a sitrep on the net"),
			UiKit.button("Regroup on me", func() -> void:
				if me:
					MapCommandLayer.send(_hc, id, "regroup", Vector2(me.global_position.x, me.global_position.z)), "Gather on you, treat and cross-load"),
			UiKit.button("Follow me", func() -> void: MapCommandLayer.send(_hc, id, "follow", Vector2.INF), "Keep station 30-60 m off you"),
			UiKit.button("Cancel", func() -> void: MapCommandLayer.send(_hc, id, "cancel", Vector2.INF), "Cancel its current order: it holds"),
		]
		card.add_child(UiKit.button_row(buttons))
	return card
