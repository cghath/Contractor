class_name BaseUI
extends CanvasLayer
## The base screen (wave 4): one window with a page per terminal at the hub (BaseTerminal):
## squad and deploy (ops desk), roster, hiring board, medbay, shop and armory ledger. It
## shows BaseHub.view (the host's copy, sent to every peer) and sends every change as a
## request to the host (BaseHub.request). Esc or Close shuts it; the mouse goes back to the
## view.

const PAGES: Array[String] = ["squad", "roster", "hiring", "medbay", "shop", "armory"]
const TITLES := {"squad": "Squad & deploy", "roster": "Roster", "hiring": "Hiring board", "medbay": "Medbay",
	"shop": "Shop", "armory": "Armory"}
const SIZE := Vector2(980, 640)

var page := "squad"
var _tabs: TabContainer
var _header: Label
var _status: Label
var _pages := {}  # page -> VBoxContainer (its rows)


func _ready() -> void:
	layer = 20
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SIZE
	panel.size = SIZE
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	var top := HBoxContainer.new()
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	top.add_child(_button("Close (Esc)", close))
	box.add_child(top)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for p in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = TITLES[p]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		_tabs.add_child(scroll)
		_pages[p] = rows
	_tabs.tab_changed.connect(func(i: int) -> void:
		page = PAGES[i]
		refresh())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	BaseHub.view_changed.connect(refresh)
	BaseHub.note.connect(func(text: String) -> void: _status.text = text)
	visible = false


func open(p_page := "squad") -> void:
	page = p_page if p_page in PAGES else "squad"
	visible = true
	_tabs.current_tab = PAGES.find(page)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


## The contract board over the base screen (Captain, P0362: closing this screen to see the
## board whole took the mouse away from the board). This screen steps aside while the board
## is up and comes back, with the mouse, when it closes.
func _open_board() -> void:
	var board := Contracts.open_board()
	visible = false
	board.closed.connect(func() -> void:
		if is_inside_tree():
			open(page))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


## Rebuilds the page showing from BaseHub.view.
func refresh() -> void:
	if not visible or not is_node_ready():
		return
	var v := BaseHub.view
	_header.text = "Day %d    Funds $%d    Wages $%d/day    Weekly bill $%d in %d day%s" % [int(v.get("day", 1)), int(v.get("funds", 0)),
		int(v.get("daily_wages", 0)), int(v.get("weekly_bill", 0)), int(v.get("bill_in_days", 7)), "" if int(v.get("bill_in_days", 7)) == 1 else "s"]
	var rows: VBoxContainer = _pages[page]
	for child in rows.get_children():
		child.queue_free()
	match page:
		"squad":
			_build_squad(rows, v)
		"roster":
			_build_roster(rows, v)
		"hiring":
			_build_hiring(rows, v)
		"medbay":
			_build_medbay(rows, v)
		"shop":
			_build_shop(rows, v)
		"armory":
			_build_armory(rows, v)


# --- Pages -----------------------------------------------------------------------------------

func _build_squad(rows: VBoxContainer, v: Dictionary) -> void:
	var prep: Dictionary = v.get("prep", {})
	var roster: Dictionary = v.get("roster", {})
	var contract: Dictionary = prep.get("contract", {})
	var dep: Dictionary = roster.get("deployment", {})
	if dep.get("active", false):
		rows.add_child(_text("Deployed to %s (%s zone). Respawns used %d of %d free." % [dep.get("zone_id", "?"), dep.get("zone_kind", "contract"),
			int(dep.get("respawns_used", 0)), int(dep.get("respawns_free", 0))]))
		return
	rows.add_child(_text("Contract: %s" % (String(contract.get("name", contract.get("title", ""))) + " (" + ContractGen.clawback_text(contract) + ")" if not contract.is_empty()
		else "none in prep: prep one from the contract board to deploy")))
	var board := Button.new()
	board.text = "Contract board"
	board.pressed.connect(_open_board)
	rows.add_child(board)
	if contract.is_empty():
		for c: Dictionary in v.get("held", []):
			var row := HBoxContainer.new()
			row.add_child(_text("Held: %s (deploy by day %d)" % [c.title, int(c.deadline_day)]))
			var prep_button := Button.new()
			prep_button.text = "Prep"
			prep_button.disabled = not multiplayer.is_server()  # the host preps
			prep_button.pressed.connect(func() -> void: BaseHub.request("prep", [String(c.cid)]))
			row.add_child(prep_button)
			rows.add_child(row)
	var debrief: Dictionary = roster.get("last_debrief", {})
	if not debrief.is_empty():
		rows.add_child(_text("Last deployment: %d back, %d MIA, %d KIA, %d respawns (%d bought)" % [debrief.get("extracted", []).size(),
			debrief.get("mia", []).size(), debrief.get("dead", []).size(), int(debrief.get("respawns_used", 0)), int(debrief.get("respawns_bought", 0))]))
	var picked: Array = prep.get("squad", [])
	var members: Dictionary = roster.get("members", {})
	rows.add_child(_heading("Squad for the next deployment (%d of %d AI; players take their own slots)" % [picked_count(picked, members), BaseHub.SQUAD_SIZE - 1]))
	var ids := members.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = members[mid]
		if not Roster.is_available(m):
			continue
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.button_pressed = mid in picked
		check.text = "%s  (%s)" % [m.callsign, m.name]
		check.custom_minimum_size.x = 300
		check.toggled.connect(func(on: bool) -> void: BaseHub.request("pick", [mid, on]))
		row.add_child(check)
		row.add_child(_role_picker(mid, StringName(m.role)))
		row.add_child(_text(_skills_text(m)))
		rows.add_child(row)
	rows.add_child(_heading("Players"))
	var players: Dictionary = roster.get("players", {})
	var me := multiplayer.get_unique_id()
	for peer: String in v.get("players", {}):
		var key := String(v.players[peer])
		var main: Dictionary = players.get(key, {})
		var days := int(main.get("sit_out_days", 0))
		var id := int(peer)
		# FOB ready-up (Captain, 2026-10-14), worded as the briefing's: the host's Deploy is their ready.
		var readiness := "deploys" if id == 1 else ("ready" if BaseHub.is_ready(id) else "not ready")
		rows.add_child(_text("%s (%s): %s; %s" % ["You" if id == me else "Player %d" % id, key, readiness,
			"recovering %d days: plays a squadmate next time" % days if days > 0 else "fit"]))
	var buttons := HBoxContainer.new()
	if not multiplayer.is_server():
		var ready_button := Button.new()
		ready_button.name = "Ready"
		ready_button.toggle_mode = true
		ready_button.set_pressed_no_signal(BaseHub.is_ready(me))
		ready_button.text = "Ready (click to stand down)" if ready_button.button_pressed else "Ready"
		ready_button.tooltip_text = "The host can deploy once every player is ready"
		ready_button.toggled.connect(func(on: bool) -> void: BaseHub.request("ready", [on]))
		buttons.add_child(ready_button)
	var deploy := _button("Deploy", func() -> void: BaseHub.request("deploy"))
	deploy.name = "Deploy"
	var waiting := BaseHub.not_ready_names()
	deploy.disabled = not multiplayer.is_server() or contract.is_empty()
	deploy.tooltip_text = BaseHub.NO_CONTRACT if contract.is_empty() else (BaseHub.WAITING_FOR + ", ".join(PackedStringArray(waiting))
		if not waiting.is_empty() else "The host deploys the squad")
	buttons.add_child(deploy)
	buttons.add_child(_button("Rest a day", func() -> void: BaseHub.request("rest", [1])))
	buttons.add_child(_button("Save campaign", func() -> void: BaseHub.request("save")))
	rows.add_child(buttons)
	_add_restock_row(rows)


## Playtest S2: kitting up from the stash in one go, the kit each deployed in last time
## (BaseHub.server_restock_player / server_restock_squad). What it did shows in the status line.
func _add_restock_row(rows: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Restock"
	var mine := _button("Restock my last loadout", func() -> void: BaseHub.request("restock"))
	mine.tooltip_text = "Rebuild the kit you last deployed with from the stash; what the stash is short of is listed"
	row.add_child(mine)
	var squad := _button("Restock squad", func() -> void: BaseHub.request("restock_squad"))
	squad.disabled = not multiplayer.is_server()  # the squad leader (the host)
	squad.tooltip_text = "Rebuild every picked squadmate's last loadout (everyone at the muster line if nobody is picked) from the stash"
	row.add_child(squad)
	rows.add_child(row)


func _build_roster(rows: VBoxContainer, v: Dictionary) -> void:
	var roster: Dictionary = v.get("roster", {})
	var members: Dictionary = roster.get("members", {})
	if members.is_empty():
		rows.add_child(_text("Nobody on the books yet: hire at the hiring board."))
	var ids := members.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = members[mid]
		var row := HBoxContainer.new()
		row.add_child(_text("%s \"%s\"  %s  %s  %s  missions %d  $%d/day  %s" % [m.name, m.callsign, Roster.person_text(m), Roles.short_name(StringName(m.role)),
			Roster.status_text(m), int(m.get("missions", 0)), int(m.get("wage", 0)), _skills_text(m)], 700))
		row.add_child(_text("%d items" % _item_total(m.get("gear", {})), 80))
		if Roster.is_available(m):
			row.add_child(_button("Let go", func() -> void: BaseHub.request("release", [mid])))
		rows.add_child(row)
		var history: Array = m.get("history", [])
		if not history.is_empty():
			var last: Dictionary = history[-1]
			rows.add_child(_text("      day %d: %s" % [int(last.day), last.text]))


func _build_hiring(rows: VBoxContainer, v: Dictionary) -> void:
	var pool: Array = v.get("hiring", {}).get("pool", [])
	rows.add_child(_text("The board turns over every %d days (last on day %d)." % [Hiring.REFRESH_DAYS, int(v.get("hiring", {}).get("refreshed_day", 1))]))
	if pool.is_empty():
		rows.add_child(_text("Nobody on the board."))
	for c: Dictionary in pool:
		var row := HBoxContainer.new()
		var veteran := " (veteran)" if int(c.get("missions", 0)) >= 10 else ""
		row.add_child(_text("%s \"%s\"  %s  %s%s  missions %d  %s  asks $%d/day" % [c.name, c.callsign, Roster.person_text(c), Roles.display_name(StringName(c.role)),
			veteran, int(c.missions), _skills_text(c), int(c.demand)], 760))
		var cid := String(c.cid)
		row.add_child(_button("Hire ($%d)" % int(c.fee), func() -> void: BaseHub.request("hire", [cid])))
		rows.add_child(row)


func _build_medbay(rows: VBoxContainer, v: Dictionary) -> void:
	var roster: Dictionary = v.get("roster", {})
	var anyone := false
	var people := []
	for mid: String in roster.get("members", {}):
		people.append([mid, roster.members[mid], String(roster.members[mid].callsign)])
	for key: String in roster.get("players", {}):
		people.append(["player:" + key, roster.players[key], key])
	for p: Array in people:
		var person: Dictionary = p[1]
		if int(person.get("sit_out_days", 0)) <= 0 or String(person.get("status", Roster.READY)) != Roster.READY:
			continue
		anyone = true
		var row := HBoxContainer.new()
		row.add_child(_text("%s: %d days (%s)" % [p[2], int(person.sit_out_days), ", ".join(PackedStringArray(person.get("injuries", [])))], 640))
		var quote := Roster.medbay_quote(person)
		if quote.is_empty():
			row.add_child(_text("treated"))
		else:
			var who := String(p[0])
			row.add_child(_button("Treat: %d days sooner ($%d)" % [int(quote.days_saved), int(quote.cost)], func() -> void: BaseHub.request("medbay", [who])))
		rows.add_child(row)
	if not anyone:
		rows.add_child(_text("Nobody is recovering."))
	var mia: Array = []
	for m: Dictionary in roster.get("members", {}).values():
		if String(m.get("status", "")) == Roster.MIA:
			mia.append("%s (%s)" % [m.callsign, m.get("mia_zone", "?")])
	if not mia.is_empty():
		rows.add_child(_text("Missing in action: %s. Recovery contracts are requested from the board." % ", ".join(PackedStringArray(mia))))


func _build_shop(rows: VBoxContainer, v: Dictionary) -> void:
	rows.add_child(_text("Bought items are delivered to the armory counter."))
	for entry: Dictionary in v.get("catalog", []):
		var id := StringName(entry.get("id", ""))
		var item := ItemDB.get_item(id)
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.add_child(_text("%s  $%d" % [item.name, int(entry.price)], 420))
		row.add_child(_button("Buy", func() -> void: BaseHub.request("buy", [String(id), 1])))
		row.add_child(_button("Buy 5", func() -> void: BaseHub.request("buy", [String(id), 5])))
		rows.add_child(row)


func _build_armory(rows: VBoxContainer, v: Dictionary) -> void:
	rows.add_child(_text("The company stash lies in the armory: pick up what you need, drop what you bring back. Anything left in the base counts."))
	var counts := BaseArmory.counts(v.get("stash", []))
	var ids := counts.keys()
	ids.sort()
	for id: String in ids:
		var item := ItemDB.get_item(StringName(id))
		rows.add_child(_text("%s x%d" % [item.name if item else id, int(counts[id])]))
	# Pouches on the stash's carriers and what's in them come with the carrier.
	var inside := BaseArmory.contents_counts(v.get("stash", []))
	if not inside.is_empty():
		rows.add_child(_heading("On the carriers and in their pouches"))
		var inside_ids := inside.keys()
		inside_ids.sort()
		for id: String in inside_ids:
			var item := ItemDB.get_item(StringName(id))
			rows.add_child(_text("%s x%d" % [item.name if item else id, int(inside[id])]))


# --- Bits ------------------------------------------------------------------------------------

func _role_picker(mid: String, current: StringName) -> OptionButton:
	var picker := OptionButton.new()
	for role in Roles.ids():
		picker.add_item(Roles.display_name(role))
		picker.set_item_metadata(picker.item_count - 1, String(role))
		if role == current:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(i: int) -> void: BaseHub.request("role", [mid, picker.get_item_metadata(i)]))
	return picker


## How many of the picked squad (`picked`, member ids) can deploy, so are listed under the
## heading: a pick whose member has since been killed, gone MIA or is recovering doesn't count
## (Captain, 2026-10-14: "6 of 7 AI" over three names, the other three KIA).
static func picked_count(picked: Array, members: Dictionary) -> int:
	return picked.filter(func(mid: Variant) -> bool: return members.has(mid) and Roster.is_available(members[mid])).size()


static func _skills_text(m: Dictionary) -> String:
	var s: Dictionary = m.get("skills", {})
	return "aim %d nerve %d med %d move %d" % [roundi(100 * float(s.get("aim", 0))), roundi(100 * float(s.get("nerve", 0))),
		roundi(100 * float(s.get("medical", 0))), roundi(100 * float(s.get("movement", 0)))]


static func _item_total(gear: Dictionary) -> int:
	var n := 0
	for c: int in Roster.gear_counts(gear).values():
		n += c
	return n


func _text(text: String, width := 0) -> Label:
	var label := Label.new()
	label.text = text
	if width > 0:
		label.custom_minimum_size.x = width
		label.clip_text = true
	return label


func _heading(text: String) -> Label:
	var label := _text(text)
	label.add_theme_color_override(&"font_color", Color("ffd35a"))
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button
