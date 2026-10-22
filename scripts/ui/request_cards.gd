class_name RequestCards
extends VBoxContainer
## The HUD's request cards (docs/combined_arms.md 4.1 and 4.3; B4): one card per request this
## player has open (who answers, what, its state and the ETA counting down; a counter-offer with
## accept and cancel), and one card for an allied ask waiting on him (the asker, the ask, how far
## and which way, yes or no). Under the objectives, top right. Keys: the high command's approve
## and deny actions (C2 adds "hc_approve" / "hc_deny", Y / N); until they exist, the buttons.
## Every peer, from the RequestBroker's replicated records.

const SHOW_CLOSED_S := 8.0
const STATE_TEXT := {"sent": "asking", "acked": "on it", "declined": "unable", "countered": "counter-offer", "en_route": "on the way",
	"on_station": "on station", "done": "done", "cancelled": "cancelled", "failed": "failed"}

var player: Soldier
var _recv := {}  # request id -> {"at": this peer's clock when its state came, "state"}
var _refresh := 0.0


func _init(p_player: Soldier = null) -> void:
	player = p_player
	name = "RequestCards"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", UiKit.SPACE_XS)


func _ready() -> void:
	var broker := RequestBroker.of(player) if player else null
	if broker:
		broker.changed.connect(rebuild)
	rebuild()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		if visible or not mine().is_empty() or not my_ask().is_empty():
			rebuild()  # the ETAs count down


func _unhandled_input(event: InputEvent) -> void:
	var ask := my_ask()
	var counter := _my_counter()
	for action: StringName in [&"hc_approve", &"hc_deny"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			var yes := action == &"hc_approve"
			var broker := RequestBroker.of(player)
			if broker == null:
				return
			if not ask.is_empty():
				broker.request_answer_ask(int(ask.id), yes)
			elif not counter.is_empty():
				if yes:
					broker.request_accept_counter(int(counter.id))
				else:
					broker.request_cancel(int(counter.id))
			else:
				return
			get_viewport().set_input_as_handled()


func _me() -> int:
	return player.owner_peer() if player else 0


## This player's requests to show: open ones, and closed ones for a few seconds.
func mine() -> Array[Dictionary]:
	var broker := RequestBroker.of(player) if player else null
	var out: Array[Dictionary] = []
	if broker == null:
		return out
	var t := Soldier._now()
	var ids := broker.requests.keys()
	ids.sort()
	for id: int in ids:
		var r: Dictionary = broker.requests[id]
		if r.get("ask", false) or int(r.get("by", -1)) != _me():
			continue
		var seen: Dictionary = _recv.get(id, {})
		if seen.get("state", "") != r.state:
			seen = {"at": t, "state": r.state}
			_recv[id] = seen
		if String(r.state) in RequestBroker.OPEN or t - float(seen.at) <= SHOW_CLOSED_S:
			out.append(r)
	return out


## The ask waiting on this player now ({} for none): one at a time.
func my_ask() -> Dictionary:
	var broker := RequestBroker.of(player) if player else null
	if broker == null:
		return {}
	for r: Dictionary in broker.requests.values():
		if r.get("ask", false) and int(r.to_peer) == _me() and r.state == "asked" and float(r.until) < INF:
			return r
	return {}


func _my_counter() -> Dictionary:
	for r in mine():
		if r.state == "countered":
			return r
	return {}


## A card's text for request `r` ("Iron 2: suppression, on in 40 s").
func card_text(r: Dictionary) -> String:
	var who := String(r.callsign) if String(r.callsign) != "" else "Net"
	var what := String(RequestBroker.spec(String(r.kind)).get("label", r.kind))
	var line := "%s: %s, %s" % [who, what, STATE_TEXT.get(String(r.state), r.state)]
	if r.state in ["acked", "en_route"] and float(r.eta_s) >= 0.0:
		var since := Soldier._now() - float((_recv.get(int(r.id), {}) as Dictionary).get("at", Soldier._now()))
		line += ", %d s" % maxi(roundi(float(r.eta_s) - since), 0)
	if String(r.why) != "" and r.state in ["declined", "countered", "failed"]:
		line += ": " + String(r.why)
	if r.kind == "sitrep" and String(r.text) != "":
		line = String(r.text)
	return line


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var ask := my_ask()
	if not ask.is_empty():
		var card := UiKit.panel()
		var box := VBoxContainer.new()
		card.add_child(box)
		var at: Vector3 = ask.pos
		var d := player.global_position.distance_to(at) if player else 0.0
		box.add_child(UiKit.hud_label("%s  (%d m %s)" % [ask.text, roundi(d), RadioChatter.compass(player.global_position, at) if player else ""]))
		box.add_child(UiKit.button_row([UiKit.button("Yes (Y)", func() -> void: RequestBroker.of(player).request_answer_ask(int(ask.id), true)),
			UiKit.button("No (N)", func() -> void: RequestBroker.of(player).request_answer_ask(int(ask.id), false))]))
		add_child(card)
	for r in mine():
		var card := UiKit.panel()
		var box := VBoxContainer.new()
		card.add_child(box)
		var label := UiKit.hud_label(card_text(r))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
		if r.state == "countered":
			box.add_child(UiKit.button_row([UiKit.button("Accept (Y)", func() -> void: RequestBroker.of(player).request_accept_counter(int(r.id))),
				UiKit.button("Cancel (N)", func() -> void: RequestBroker.of(player).request_cancel(int(r.id)))]))
		elif String(r.state) in RequestBroker.OPEN:
			box.add_child(UiKit.button_row([UiKit.button("Cancel", func() -> void: RequestBroker.of(player).request_cancel(int(r.id)))]))
		add_child(card)
	visible = get_child_count() > 0
