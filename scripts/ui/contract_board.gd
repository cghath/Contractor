class_name ContractBoard
extends CanvasLayer
## The regional contract board (wave 4, W10): offers from the board, fixers and intel leads,
## each with its difficulty rating, what the briefing knows and the pay; MW5-style
## negotiation (pay, salvage share and support budget against negotiation points, and the
## advance); the contracts the company holds (renegotiate or abort when the briefing lied);
## cash, the day, loans and reputation. Every peer can open it (it shows the replicated
## state); what it does goes to the host (Contracts.accept and the other requests).
##
## The host also gets: in a campaign, "Prepare deployment" (the held contract goes into the
## base's prep, BaseHub) and letting days pass; offline, the debug controls that stand in for
## the rest of the loop: deploy on a held contract, end the deployment with everyone getting
## out (a debrief), let days pass, reset the campaign.

signal closed

var _header: Label
var _offers: ItemList
var _held: ItemList
var _details: Label
## Who holds each hot zone and how firmly (wave 6c).
var _zones: Label
var _leads: Label  # the story: act, evidence, clues (docs/story.md)
## The details' scroll area (P0-5: a long briefing ran the panel off a small window).
var _details_scroll: ScrollContainer
## Offers / held and details side by side on a wide window, one above the other on a narrow one.
var _body: BoxContainer
var _left: VBoxContainer
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
## The facts at a glance over the details (ContractGlance), rebuilt with them.
var _glance: VBoxContainer
## The cid to pick once it shows up held (an offer just accepted: Prepare deployment is next).
var _pick_when_held := ""
var _panel: PanelContainer
## The host's buttons in the bottom row (wait, and offline the debug ones).
var _host_buttons: Array[Button] = []
## The shop opened from here: Esc closes it first, and it goes when the board does (P0-4).
var _shop: ShopScreen
var _selected := ""          # cid
var _selected_held := false
var _offer_ids: Array[String] = []
var _held_ids: Array[String] = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _refreshing := false


## Below this logical width (window / Menu and HUD size) the lists go above the details.
const NARROW_WIDTH := 1000.0
## What each negotiation field does (ui-modern: every field gets a tooltip).
const SPIN_TIPS := {
	"Pay points": "More cash when the contract is done.",
	"Salvage points": "A bigger share of what you bring back counts as yours (the rest goes to the client).",
	"Support points": "A bigger budget for support calls (helicopters, fire support) during the job.",
	"Advance %": "How much of the pay comes up front when you accept; the rest on completion.",
}


func _ready() -> void:
	layer = 10
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The shared look (UiKit; Captain, 2026-10-14: "all of the UIs need a pass"; docs/ui_audit.md
	# P0-5): a themed full-window panel whose middle scrolls, the lists beside the details on a wide
	# window and above them on a narrow one, and the bottom row of buttons wrapping, so nothing
	# runs off a 1280x720 window at a 1.5 Menu and HUD size.
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply(frame)
	add_child(frame)
	frame.add_child(UiKit.dim(0.45))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiKit.EDGE)
	frame.add_child(margin)
	var panel := UiKit.panel()
	_panel = panel
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	root.add_child(UiKit.header("Contract board", "Pick the company's next job: compare offers, negotiate the terms, accept, then prepare the deployment.",
		PackedStringArray([
			"Offers come from the regional board, fixers and intel leads. Pick one for what the briefing knows, its difficulty and the pay.",
			"Negotiation: spend the points between pay, salvage share (how much of what you bring back is yours) and support budget (paid support calls). Advance % is paid when you accept, the rest on completion.",
			"Held contracts are the ones the company has taken. Renegotiate (once, when the briefing understated the threat) or Abort one; Prepare deployment sends it to the base's prep.",
			"Hot zones shows who holds each zone and how firmly; it shifts while days pass. Shop buys kit into the stash; a loan gives cash now, paid back with interest.",
		]), [["Esc", "Close"], ["Tab / arrows", "Move"], ["Enter", "Press"]]))  # (each button prints its own hotkey)
	_header = UiKit.text("")
	root.add_child(_header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_body = BoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", UiKit.SPACE_L)
	scroll.add_child(_body)
	_left = VBoxContainer.new()
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_left)
	_left.add_child(UiKit.heading("Offers (board, fixers, leads)"))
	_offers = UiKit.list(140.0)
	_offers.tooltip_text = "Contracts on offer. Pick one to see its briefing and negotiate it"
	_left.add_child(_offers)
	_offers.item_selected.connect(func(i: int) -> void: _select(_offer_ids[i], false))
	_offers.item_activated.connect(func(i: int) -> void:  # Enter / double-click: on to its next step (the button, not the deed)
		_select(_offer_ids[i], false)
		_focus_primary())
	_left.add_child(UiKit.heading("Held contracts"))
	_held = UiKit.list(140.0)
	_held.tooltip_text = "Contracts the company holds. Pick one to see it, renegotiate, abort or deploy"
	_left.add_child(_held)
	_held.item_selected.connect(func(i: int) -> void: _select(_held_ids[i], true))
	_held.item_activated.connect(func(i: int) -> void:
		_select(_held_ids[i], true)
		_focus_primary())
	_left.add_child(UiKit.heading("Hot zones: who holds them"))  # wave 6c: WorldSites, the faction war between deployments
	_zones = UiKit.text("")
	_left.add_child(_zones)
	_left.add_child(UiKit.heading("Leads"))  # the story (docs/story.md): what the intel has said so far
	_leads = UiKit.text("")
	_left.add_child(_leads)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(right)
	right.add_child(ContractGlance.flow("Board"))  # in the scrolling part: the open help still fits a small window
	_glance = VBoxContainer.new()
	_glance.add_theme_constant_override(&"separation", UiKit.SPACE_XS)
	right.add_child(_glance)
	var details := UiKit.scroll(160.0)
	_details_scroll = details.get_parent() as ScrollContainer
	_details = UiKit.text("")
	details.add_child(_details)
	right.add_child(_details_scroll)
	right.add_child(UiKit.heading("Negotiation"))
	var fields := HFlowContainer.new()  # the four fields wrap two by two (or one) when narrow
	fields.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
	fields.add_theme_constant_override(&"v_separation", UiKit.SPACE_S)
	right.add_child(fields)
	_pay = _spin(fields, "Pay points", 0, 10, 1)
	_salvage = _spin(fields, "Salvage points", 0, 10, 1)
	_support = _spin(fields, "Support points", 0, 10, 1)
	_advance = _spin(fields, "Advance %", 10, 50, 10)
	_deal = UiKit.text("")
	right.add_child(_deal)
	# The picked contract's next step first and lit (an offer: Accept; a held one: Prepare), the rest after.
	_accept = UiKit.hotkey(UiKit.accent_button("Accept contract", accept_selected, "Take the picked offer on the terms set above (the advance is paid now)"), KEY_A, panel)
	_renegotiate = UiKit.hotkey(UiKit.button("Renegotiate", func() -> void: Contracts.renegotiate(_selected),
		"Once per contract, when the briefing understated the threat: the pay on completion goes up"), KEY_R, panel)
	_abort = UiKit.hotkey(UiKit.danger_button("Abort", _confirm_abort, "Give the held contract up. The advance is kept; your standing with the employer drops, unless the briefing was shown to have lied"), KEY_X, panel)
	_deploy = UiKit.hotkey(UiKit.accent_button("Prepare deployment" if BaseHub.campaign_running else "Deploy (debug)", _deploy_selected,
		"Send the held contract to the base's deployment prep: pick the squad and kit there, then the briefing"), KEY_P, panel)
	right.add_child(UiKit.button_row([_accept, _deploy, _renegotiate, _abort]))
	# The bottom row's seven buttons wrap onto a second line rather than off the window (P0-5).
	var bottom: Array = [UiKit.hotkey(UiKit.button("Shop", open_shop, "Buy kit into the company stash"), KEY_S, panel),
		UiKit.hotkey(UiKit.button("Take a loan", _confirm_loan, "Cash now from a lender, paid back with interest a share each week"), KEY_L, panel)]
	_host_buttons.append(UiKit.hotkey(UiKit.button("Wait a day", func() -> void: Economy.advance_days(1, "waiting at base"),
		"Let a day pass: offers expire and new ones come, the hot zones shift, and each week the bill (wages, upkeep, loans) falls due"), KEY_W, panel))
	_host_buttons.append(UiKit.hotkey(UiKit.button("Wait a week", func() -> void: Economy.advance_days(MissionRegistry.setting_i("week_days", 7), "waiting at base"),
		"Let a week pass (as Wait a day, seven times)"), KEY_W, panel, true))
	if not BaseHub.campaign_running:  # a campaign deploys from the base and ends at extraction
		_host_buttons.append(UiKit.button("End deployment (debug)", _debug_extract))
		_host_buttons.append(UiKit.button("Reset campaign", func() -> void: Contracts.new_full_campaign()))
	bottom.append_array(_host_buttons)
	bottom.append(UiKit.button("Close", close, "Close the board (Esc)"))
	var esc := UiKit.key_hint("Esc", "Close")  # in the row, not a line of its own (room for the open help)
	esc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.append(esc)
	root.add_child(UiKit.button_row(bottom))
	_notice = UiKit.text("")
	_notice.name = "Notice"
	root.add_child(_notice)
	_layout()
	get_viewport().size_changed.connect(_layout)
	Contracts.changed.connect(refresh)
	Economy.changed.connect(refresh)
	Contracts.notice.connect(_on_notice)
	Economy.notice.connect(_on_notice)
	_restore_choices()
	refresh()
	UiKit.focus_first(panel)  # keyboard: Tab/arrows and Enter work at once


## Lists beside the details on a wide window (the left column up to 460 px), above them on a
## narrow one; follows window resizes and the Menu and HUD size.
func _layout() -> void:
	if not is_inside_tree():
		return
	var width := get_viewport().get_visible_rect().size.x
	var narrow := width < NARROW_WIDTH
	_body.vertical = narrow
	_left.custom_minimum_size.x = 0.0 if narrow else clampf(width * 0.4, 320.0, 460.0)


## Opens the shop over the board (one at a time) and returns it.
func open_shop() -> ShopScreen:
	if not is_instance_valid(_shop) or _shop.is_queued_for_deletion():
		_shop = ShopScreen.new()
		get_tree().root.add_child(_shop)
	return _shop


## A screen to click on: whatever else opens or closes under it, the mouse stays free while
## it's up (P0362: the base screen closing under it took the mouse).
func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if is_instance_valid(_shop) and not _shop.is_queued_for_deletion():
		_shop.close()
	Input.mouse_mode = _mouse_before
	closed.emit()
	queue_free()


## Esc closes the top-most screen only: the shop opened from here first, then the board (P0-4:
## Esc fell through the shop and closed the board under it).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_shop) and not _shop.is_queued_for_deletion():
			_shop.close()
		else:
			close()


## Rebuilds the lists and the details from the replicated state.
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var host := Contracts.is_host()
	for b: Button in _host_buttons:
		b.visible = host
	_deploy.visible = host
	var e := Economy
	var reps := PackedStringArray()
	for f: String in MissionRegistry.faction_ids():
		reps.append("%s %+d (tier %d)" % [MissionRegistry.faction_name(f), e.reputation(f), e.tier(f)])
	var week := e.weekly_bill()
	_header.text = "Day %d (week %d)   Cash $%s   Costs $%s/day   Owed $%s%s\nReputation: %s   Locals %+d" % [
		e.day(), e.week(), DebriefCalc.money(e.cash()), DebriefCalc.money(roundi(float(int(week.wages) + int(week.upkeep)) / maxi(MissionRegistry.setting_i("week_days", 7), 1))),
		DebriefCalc.money(e.loans_owed()),
		"   DEPLOYED: %s" % Contracts.deployment().zone_name if Contracts.is_deployed() else "", "   ".join(reps), e.locals()]
	_offer_ids.clear()
	_offers.clear()
	for c: Dictionary in Contracts.board():
		_offer_ids.append(String(c.cid))
		_offers.add_item(offer_line(c))
		_offers.set_item_tooltip(_offers.item_count - 1, _tooltip(c))  # the whole line (cut with "..." when narrow) and the brief
	_held_ids.clear()
	_held.clear()
	for c: Dictionary in Contracts.held():
		_held_ids.append(String(c.cid))
		_held.add_item("%s  [%s]" % [offer_line(c), String(c.state).to_upper()])
		_held.set_item_tooltip(_held.item_count - 1, "[%s] %s" % [String(c.state).to_upper(), _tooltip(c)])
	_zones.text = zones_text()
	_leads.text = Story.leads_text()
	if _pick_when_held != "" and _pick_when_held in _held_ids:
		_selected = _pick_when_held
		_selected_held = true
		_pick_when_held = ""
	if _selected != "" and Contracts.contract(_selected).is_empty():
		_selected = ""
	if _selected == "":  # fewer clicks: the board opens on a contract, not on nothing
		if not _held_ids.is_empty() and Contracts.contract(_held_ids[0]).get("state") == Contracts.ACCEPTED:
			_selected = _held_ids[0]
			_selected_held = true
		elif not _offer_ids.is_empty():
			_selected = _offer_ids[0]
			_selected_held = false
	_mark_selected()
	_show_details()
	_refreshing = false


## A list row's tooltip: the whole line (the list cuts it with "...") and the brief.
static func _tooltip(c: Dictionary) -> String:
	return "%s\n%s" % [offer_line(c), String(c.get("brief", ""))]


## One offer in a line: rating, zone kind, its night or weather ("NIGHT FOG ", missions 2),
## title, employer, pay.
static func offer_line(c: Dictionary) -> String:
	var stars := "*".repeat(int(c.get("rated", 1))) + ".".repeat(5 - int(c.get("rated", 1)))
	var tag: String = {"fixer": "FIXER %s: " % c.get("fixer", ""), "safe": "LOW RISK: ", "lead": "", "recovery": "RECOVERY: "}.get(String(c.get("source", "")), "")
	return "[%s] %s%s%s%s - %s - $%s" % [stars, "HOT ZONE " if c.get("zone_kind") == "hot" else "", ContractGen.conditions_tag(c), tag, c.get("title", ""),
		MissionRegistry.faction_name(String(c.get("employer", ""))), DebriefCalc.money(c.get("base_pay", 0))]


func _select(cid: String, from_held: bool) -> void:
	_selected = cid
	_selected_held = from_held
	_remember("board_pick", cid)
	_mark_selected()
	_show_details()


## The lists' selection follows _selected (a pick made in code, or after a refresh).
func _mark_selected() -> void:
	_offers.deselect_all()
	_held.deselect_all()
	var i := _offer_ids.find(_selected)
	if i >= 0:
		_offers.select(i)
	var j := _held_ids.find(_selected)
	if j >= 0:
		_held.select(j)


## Focuses the picked contract's next step (Accept for an offer, Prepare for a held one).
func _focus_primary() -> void:
	for b: Button in [_accept, _deploy]:
		if b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()
			return


func _show_details() -> void:
	var c: Dictionary = Contracts.contract(_selected) if _selected != "" else {}
	var offer: bool = not c.is_empty() and c.get("state") == "offered"
	for w: Control in [_pay.get_parent(), _salvage.get_parent(), _support.get_parent(), _advance.get_parent(), _accept]:  # a field with its label
		w.visible = offer
	_renegotiate.visible = not offer and c.get("revealed", false) and not c.get("renegotiated", false)
	_abort.visible = not c.is_empty() and c.get("state") in [Contracts.ACCEPTED, Contracts.DEPLOYED]
	_deploy.visible = Contracts.is_host() and c.get("state") == Contracts.ACCEPTED and not Contracts.is_deployed()
	for child in _glance.get_children():
		_glance.remove_child(child)
		child.queue_free()
	if c.is_empty():
		_details.text = "Pick an offer to see its briefing and negotiate."
		_deal.text = ""
		return
	var title := UiKit.heading(String(c.title))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_glance.add_child(title)
	_glance.add_child(ContractGlance.strip(c))
	var lines := PackedStringArray([String(c.brief), ""])
	lines.append("Client: %s   Target: %s" % [MissionRegistry.faction_name(String(c.employer)), MissionRegistry.faction_name(String(c.target))])
	lines.append("Zone: %s (%s zone, %s)   %d day%s plus travel" % [c.zone_name, c.zone_kind, MissionRegistry.region(String(c.region)).get("name", c.region),
		int(c.days), "" if int(c.days) == 1 else "s"])
	lines.append("Difficulty %d/5   Intel accuracy %d%%   Terms: %s" % [int(c.rated), roundi(float(c.intel_accuracy) * 100.0), ContractGen.clawback_text(c)])
	lines.append("Briefing: " + ContractGen.estimate_text(c))
	if c.get("revealed", false) and c.has("true_rating"):
		lines.append("ACTUAL THREAT: difficulty %d/5, %d fighters" % [int(c.true_rating), int(c.enemy_count)])
	lines.append("Objectives:")
	for o: Dictionary in c.get("objectives", []):
		lines.append("  - " + objective_tag(o) + String(o.get("text", "")))
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
	_deal.text = "Points %d of %d.   Pay $%s: advance $%s now (kept if it fails; %s), $%s on completion.   Salvage %d%%.   Support budget $%s.%s" % [
		ContractGen.terms_cost(t), points, DebriefCalc.money(deal.pay_total), DebriefCalc.money(deal.advance), ContractGen.clawback_text(c), DebriefCalc.money(deal.completion),
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
	if _selected != "" and not _accept.disabled:
		_pick_when_held = _selected  # once signed, the board moves on to it: Prepare deployment is next
		_remember("board_terms", terms())
		_on_notice("Accepting %s..." % String(Contracts.contract(_selected).get("title", "the contract")))
		Contracts.accept(_selected, terms())


## "BONUS: " or "OPTIONAL: " before an objective that isn't required (and doesn't say so itself).
static func objective_tag(o: Dictionary) -> String:
	if not bool(o.get("optional", false)) or String(o.get("text", "")).begins_with("Bonus"):
		return ""
	return "BONUS: " if float(o.get("bonus_share", 0.0)) > 0.0 else "OPTIONAL: "


func offer_count() -> int:
	return _offers.item_count


func held_count() -> int:
	return _held.item_count


## The hot zones' holders and grip, one a line (wave 6c); a contested zone can fall to a rival.
func zones_text() -> String:
	var lines := PackedStringArray()
	for r: Dictionary in Economy.world_sites():
		lines.append(WorldSites.row_text(r))
	return "
".join(lines) if not lines.is_empty() else "No hot zones known yet"


func leads_text() -> String:
	return _leads.text


func header_text() -> String:
	return _header.text


func details_text() -> String:
	return _details.text


## In a campaign: the held contract goes into the base's prep (BaseHub); offline: the debug
## deployment right here.
func _deploy_selected() -> void:
	if BaseHub.campaign_running:
		BaseHub.request("prep", [_selected])
	else:
		_debug_deploy()


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
			if s and s.faction == &"friendly" and not s.vitals.is_dead() and not s.has_meta(&"vehicle_crew"):  # (wave 5b: not a support's crew)
				out.append(s)
		report = Contracts.report_from_level(level, out)
	Contracts.server_end_deployment(report)


## A message from the host (signed, refused, paid...): shown under the buttons, lit for a moment.
func _on_notice(text: String) -> void:
	if is_instance_valid(_notice):
		_notice.text = text
		_notice.modulate = Color(UiKit.ACCENT_HOT, 1.0)
		if _notice.is_inside_tree():
			_notice.create_tween().tween_property(_notice, "modulate", Color.WHITE, 1.2)


## Abort asks first: it can't be undone and costs standing.
func _confirm_abort() -> void:
	var c := Contracts.contract(_selected)
	if c.is_empty():
		return
	var cid := _selected
	UiKit.confirm(_panel, "Abort %s? The advance is kept, but %s thinks less of the company (unless the briefing lied)." % [String(c.title),
		MissionRegistry.faction_name(String(c.get("employer", "")))], "Abort", func() -> void: Contracts.abort(cid))


## A loan asks first: it's paid back with interest every week.
func _confirm_loan() -> void:
	UiKit.confirm(_panel, "Take a loan? The cash comes now; it is paid back with interest a share each week.", "Take the loan",
		func() -> void: Economy.take_loan(), false)


## The terms and pick the player last used (GameSettings "mission_ui").
func _restore_choices() -> void:
	var t: Variant = GameSettings.get_value("mission_ui", "board_terms")
	if t is Dictionary and not (t as Dictionary).is_empty():
		_pay.set_value_no_signal(int(t.get("pay_points", 0)))
		_salvage.set_value_no_signal(int(t.get("salvage_points", 0)))
		_support.set_value_no_signal(int(t.get("support_points", 0)))
		_advance.set_value_no_signal(roundi(float(t.get("advance_share", 0.3)) * 100.0))
	var pick := String(GameSettings.get_value("mission_ui", "board_pick"))
	if pick != "" and not Contracts.contract(pick).is_empty():
		_selected = pick
		_selected_held = Contracts.contract(pick).get("state") != "offered"


static func _remember(key: String, value: Variant) -> void:
	if GameSettings.get_value("mission_ui", key) != value:
		GameSettings.set_value("mission_ui", key, value)


## A negotiation field: its label and SpinBox together, so the pair wraps as one.
func _spin(parent: Control, label_text: String, lo: float, hi: float, step: float) -> SpinBox:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	parent.add_child(pair)
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = SPIN_TIPS.get(label_text, "")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	pair.add_child(label)
	var spin := SpinBox.new()
	spin.tooltip_text = label.tooltip_text
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = lo if label_text != "Advance %" else roundi(MissionRegistry.setting_f("advance_share", 0.3) * 100.0)
	spin.value_changed.connect(func(_v: float) -> void: _update_deal())
	pair.add_child(spin)
	return spin

