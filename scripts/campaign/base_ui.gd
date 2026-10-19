class_name BaseUI
extends CanvasLayer
## The base screen (wave 4): one window with a page per terminal at the hub (BaseTerminal):
## squad and deploy (ops desk), roster, hiring board, medbay, shop, armory ledger and motor
## pool. It shows BaseHub.view (the host's copy, sent to every peer) and sends every change as
## a request to the host (BaseHub.request). Esc or Close shuts it; the mouse goes back to the
## view.
##
## Captain, 2026-10-14: "all the UIs need a pass" (docs/ui_audit.md, P0-1, P1-12, P2-23): the
## screen is a UiKit.screen (a solid panel fitted to the window, scrolling when the window or the
## Menu and HUD size leaves too little room) instead of a fixed 980x640 panel that ran off a
## 1280x720 window at 1.2; rows cut long text with "..." and keep it whole in a tooltip (an
## item's ItemInfo tooltip) instead of clipping it silently; the Shop tab is the base's shop
## (filter, prices, Buy and Buy 5, support call prices) instead of a second, plainer shop; and
## the motor pool has a page of its own (it was only an interaction ring).

const PAGES: Array[String] = ["squad", "roster", "hiring", "medbay", "shop", "armory", "motor_pool", "stores"]
const TITLES := {"squad": "Squad & deploy", "roster": "Roster", "hiring": "Hiring board", "medbay": "Medbay",
	"shop": "Shop", "armory": "Armory", "motor_pool": "Motor pool", "stores": "Supply cage"}
## The panel's width and the pages' height when the window has room for them (UiKit fits both
## to the window when it hasn't).
const WIDTH := 1100.0
const PAGE_HEIGHT := 620.0
## What else is in the panel above and below the pages (header, status, key hint, margins), so
## the pages leave room for it on a short window.
const PAGE_RESERVE := 170.0
## The shop's type filter (as ShopScreen's): "" is everything.
const SHOP_TYPES: Array[String] = ["", "weapon", "ammo", "armor", "plate", "pouch", "backpack", "medical", "utility", "launcher"]

var page := "squad"
var _box: VBoxContainer
var _tabs: TabContainer
var _header: Label
var _status: Label
var _pages := {}  # page -> VBoxContainer (its rows)
var _shop_type := ""
var _shop_query := ""  # the shop's search box (kept across rebuilds)


func _ready() -> void:
	layer = 20
	add_child(UiKit.dim(0.35))
	_box = UiKit.screen(self, WIDTH, true)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	_header = UiKit.text("")
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close_button := UiKit.button("Close", close, "Close the base screen (Esc)")
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(close_button)
	_box.add_child(top)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = true
	UiKit.fit_height(_tabs, PAGE_HEIGHT, PAGE_RESERVE)
	_box.add_child(_tabs)
	for p in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = TITLES[p]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override(&"separation", UiKit.SPACE_S)
		scroll.add_child(rows)
		_tabs.add_child(scroll)
		_pages[p] = rows
	_tabs.tab_changed.connect(func(i: int) -> void:
		page = PAGES[i]
		refresh())
	_status = UiKit.text("")
	_box.add_child(_status)
	_box.add_child(UiKit.key_hint("Esc", "Close"))
	BaseHub.view_changed.connect(refresh)
	Economy.changed.connect(refresh)  # the supply cage shows the FOB stocks
	BaseHub.note.connect(func(text: String) -> void: _status.text = text)
	visible = false


func open(p_page := "squad") -> void:
	page = p_page if p_page in PAGES else "squad"
	visible = true
	_tabs.current_tab = PAGES.find(page)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	_focus_page.call_deferred()


## Focuses the open page's first button (UiKit.focus_first's rule), looked up once the frame's
## work is done: a page opened and rebuilt again in the same frame (a tab change, a view
## update) would leave a deferred grab_focus on a row already taken out of the tree.
func _focus_page() -> void:
	if not visible or not is_inside_tree():
		return
	for root: Control in [_pages[page], _box]:
		for b in root.find_children("*", "BaseButton", true, false):
			var c := b as Control
			if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and not (c as BaseButton).disabled:
				c.grab_focus()
				return


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
	var bill_days := int(v.get("bill_in_days", 7))
	_header.text = "Day %d    Funds $%d    Wages $%d/day    Weekly bill $%d in %d day%s" % [int(v.get("day", 1)), int(v.get("funds", 0)),
		int(v.get("daily_wages", 0)), int(v.get("weekly_bill", 0)), bill_days, "" if bill_days == 1 else "s"]
	var rows: VBoxContainer = _pages[page]
	## Out of the tree at once, not at the frame's end: focus_first and the tests look for the new rows.
	for child in rows.get_children():
		rows.remove_child(child)
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
		"motor_pool":
			_build_motor_pool(rows)
		"stores":
			_build_stores(rows)


# --- Pages -----------------------------------------------------------------------------------

func _build_squad(rows: VBoxContainer, v: Dictionary) -> void:
	var prep: Dictionary = v.get("prep", {})
	var roster: Dictionary = v.get("roster", {})
	var contract: Dictionary = prep.get("contract", {})
	var dep: Dictionary = roster.get("deployment", {})
	if dep.get("active", false):
		rows.add_child(UiKit.text("Deployed to %s (%s zone). Respawns used %d of %d free." % [dep.get("zone_id", "?"), dep.get("zone_kind", "contract"),
			int(dep.get("respawns_used", 0)), int(dep.get("respawns_free", 0))]))
		return
	var job := UiKit.section("Contract", rows)
	job.add_child(UiKit.text(String(contract.get("name", contract.get("title", ""))) + " (" + ContractGen.clawback_text(contract) + ")" if not contract.is_empty()
		else "None in prep: prep one from the contract board to deploy."))
	if contract.is_empty():
		for c: Dictionary in v.get("held", []):
			var prep_button := UiKit.button("Prep", func() -> void: BaseHub.request("prep", [String(c.cid)]), "Prep this contract for the next deployment")
			prep_button.disabled = not multiplayer.is_server()  # the host preps
			job.add_child(_line("Held: %s (deploy by day %d)" % [c.title, int(c.deadline_day)], [prep_button]))
	job.add_child(UiKit.button_row([UiKit.button("Contract board", _open_board)]))
	var debrief: Dictionary = roster.get("last_debrief", {})
	if not debrief.is_empty():
		job.add_child(UiKit.hint("Last deployment: %d back, %d MIA, %d KIA, %d respawns (%d bought)" % [debrief.get("extracted", []).size(),
			debrief.get("mia", []).size(), debrief.get("dead", []).size(), int(debrief.get("respawns_used", 0)), int(debrief.get("respawns_bought", 0))]))
	var picked: Array = prep.get("squad", [])
	var members: Dictionary = roster.get("members", {})
	var squad := UiKit.section("Squad for the next deployment (%d of %d AI; players take their own slots)" % [picked_count(picked, members), BaseHub.SQUAD_SIZE - 1], rows)
	var ids := members.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = members[mid]
		if not Roster.is_available(m):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", UiKit.SPACE_M)
		var check := CheckBox.new()
		check.button_pressed = mid in picked
		check.text = "%s  (%s)" % [m.callsign, m.name]
		check.tooltip_text = "Take %s on the next deployment" % check.text
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.custom_minimum_size.x = 220
		check.toggled.connect(func(on: bool) -> void: BaseHub.request("pick", [mid, on]))
		row.add_child(check)
		row.add_child(_role_picker(mid, StringName(m.role)))
		row.add_child(_hx1_cert_button(mid, m))
		row.add_child(_cut(_skills_text(m)))
		squad.add_child(row)
		_add_short_line(squad, String(m.callsign), m)
	var people := UiKit.section("Players", rows)
	var players: Dictionary = roster.get("players", {})
	var me := multiplayer.get_unique_id()
	for peer: String in v.get("players", {}):
		var key := String(v.players[peer])
		var main: Dictionary = players.get(key, {})
		var days := int(main.get("sit_out_days", 0))
		var id := int(peer)
		# FOB ready-up (Captain, 2026-10-14), worded as the briefing's: the host's Deploy is their ready.
		var readiness := "deploys" if id == 1 else ("ready" if BaseHub.is_ready(id) else "not ready")
		people.add_child(UiKit.text("%s (%s): %s; %s" % ["You" if id == me else "Player %d" % id, key, readiness,
			"recovering %d days: plays a squadmate next time" % days if days > 0 else "fit"]))
		_add_short_line(people, key, main)
	var buttons: Array = []
	if not multiplayer.is_server():
		var ready_button := Button.new()
		ready_button.name = "Ready"
		ready_button.toggle_mode = true
		ready_button.set_pressed_no_signal(BaseHub.is_ready(me))
		ready_button.text = "Ready (click to stand down)" if ready_button.button_pressed else "Ready"
		ready_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ready_button.tooltip_text = "The host can deploy once every player is ready"
		ready_button.toggled.connect(func(on: bool) -> void: BaseHub.request("ready", [on]))
		buttons.append(ready_button)
	var deploy := UiKit.button("Deploy", func() -> void: BaseHub.request("deploy"))
	deploy.name = "Deploy"
	var waiting := BaseHub.not_ready_names()
	deploy.disabled = not multiplayer.is_server() or contract.is_empty()
	deploy.tooltip_text = BaseHub.NO_CONTRACT if contract.is_empty() else (BaseHub.WAITING_FOR + ", ".join(PackedStringArray(waiting))
		if not waiting.is_empty() else "The host deploys the squad")
	buttons.append(deploy)
	buttons.append(UiKit.button("Rest a day", func() -> void: BaseHub.request("rest", [1])))
	buttons.append(UiKit.button("Save campaign", func() -> void: BaseHub.request("save")))
	var go := UiKit.section("Deploy", rows)
	go.add_child(UiKit.button_row(buttons))
	# A raid by helicopter (LZ-4): out without a contract to any zone, the flight paid.
	var raid := UiKit.section("Raid (no contract)", rows)
	raid.add_child(UiKit.text("Walk out through a crossing at the base's edge, or fly to any zone ($%d). No pay; you keep what comes home." % int(Prices.support_price("transport"))))
	var pick := OptionButton.new()
	var zone_ids: Array[String] = []
	for z: Dictionary in MissionRegistry.zones():
		zone_ids.append(String(z.zone_id))
		pick.add_item(String(z.get("name", z.zone_id)))
	var fly := UiKit.button("Fly out to raid", func() -> void:
		if pick.selected >= 0:
			BaseHub.request("raid_air", [zone_ids[pick.selected]]))
	fly.disabled = not multiplayer.is_server()
	raid.add_child(UiKit.button_row([pick, fly]))
	# The region map (LZ-2): the zones, their crossings, and where the contracts are. A click picks
	# the zone to fly to.
	var map := RegionMapView.new()
	map.marks = region_marks(v)
	map.selected = zone_ids[pick.selected] if pick.selected >= 0 and pick.selected < zone_ids.size() else ""
	map.zone_picked.connect(func(id: String) -> void:
		var i := zone_ids.find(id)
		if i >= 0:
			pick.select(i))
	pick.item_selected.connect(func(i: int) -> void:
		map.selected = zone_ids[i]
		map.queue_redraw())
	raid.add_child(UiKit.hint("Region map: walk between linked zones through their crossings (2 h a link)."))
	raid.add_child(map)
	# The locals (rebel support, docs/rebel_support.md): their backing per region and what it unlocks.
	var locals := UiKit.section("The locals (rebel support)", rows)
	for r: Dictionary in v.get("rebels", []):
		var calls := ", ".join(PackedStringArray((r.unlocked as Array).map(func(id: String) -> String: return String(RebelSupport.CALLIN_NAMES.get(id, id)))))
		locals.add_child(UiKit.text("%s: %d of 100%s. %s" % [String(r.region).capitalize(), int(r.support),
			"" if int(r.next) < 0 else " (next at %d)" % int(r.next), ("On call: " + calls) if calls != "" else "Nothing on call yet."]))
	locals.add_child(UiKit.hint("Help the people (treat their hurt, clear the gunmen near their villages, their own jobs) and they back you; hurt them and they won't. Favours: %d." % int(v.get("favours", 0))))
	# Base defence (LZ-6): hired guards on the wire, and any assault the heat has booked.
	var defence := UiKit.section("Base defence", rows)
	var g := int(v.get("guards", 0))
	var tier := int(v.get("fob_tier", 1))
	var cap := int(v.get("max_guards", BaseHub.MAX_GUARDS))
	defence.add_child(UiKit.text("FOB tier %d. Guards on the wire: %d of %d ($%d a day each)." % [tier, g, cap, BaseHub.GUARD_DAILY_WAGE]))
	if BaseFob.TIERS.has(tier + 1):
		var up := UiKit.button("Upgrade the FOB to tier %d ($%d)" % [tier + 1, int(BaseFob.TIERS[tier + 1].price)], func() -> void: BaseHub.request("fob_tier"))
		up.disabled = not multiplayer.is_server()
		defence.add_child(up)
	var hire := UiKit.button("Hire a guard", func() -> void: BaseHub.request("guards", [g + 1]))
	hire.disabled = not multiplayer.is_server() or g >= cap
	var drop := UiKit.button("Stand one down", func() -> void: BaseHub.request("guards", [g - 1]))
	drop.disabled = not multiplayer.is_server() or g <= 0
	defence.add_child(UiKit.button_row([hire, drop]))
	var sq := int(v.get("company_squads", 0))
	var sq_cap := int(v.get("max_squads", 0))
	defence.add_child(UiKit.text("Company squads: %d of %d (8 men, $%d a day each; call them from the support menu)." % [sq, sq_cap, BaseHub.COMPANY_SQUAD_DAILY_WAGE]))
	var hire_sq := UiKit.button("Hire a squad", func() -> void: BaseHub.request("squads", [sq + 1]))
	hire_sq.disabled = not multiplayer.is_server() or sq >= sq_cap
	var drop_sq := UiKit.button("Let one go", func() -> void: BaseHub.request("squads", [sq - 1]))
	drop_sq.disabled = not multiplayer.is_server() or sq <= 0
	defence.add_child(UiKit.button_row([hire_sq, drop_sq]))
	var owned: Array = v.get("defences", [])
	for id: String in BaseFob.DEFENCES:
		var d: Dictionary = BaseFob.DEFENCES[id]
		var locked := int(d.get("tier", 1)) > tier
		var placed := owned.filter(func(e: Variant) -> bool: return e is Dictionary and String(e.get("id", "")) == id).size()
		var row: Array[Control] = []
		if id in owned:
			defence.add_child(UiKit.text("%s: built at its slot%s." % [d.name, "" if placed == 0 else ", %d placed" % placed]))
		else:
			var buy := UiKit.button("Build %s ($%d)" % [d.name, int(d.price)] + ("" if not locked else " (tier %d)" % int(d.tier)),
				func() -> void: BaseHub.request("defence", [id]))
			buy.disabled = not multiplayer.is_server() or locked
			row.append(buy)
		# LZ-6: or put one where you want it (DefencePlacer), up to BaseFob.MAX_PLACED of a kind.
		var place_it := func() -> void:
			close()
			DefencePlacer.start(self, id)
		var place := UiKit.button("Place it yourself", place_it, "Walk the base: a block shows where it goes; Enter builds it there ($%d), Esc puts it away" % int(d.price))
		place.disabled = not multiplayer.is_server() or locked or placed >= BaseFob.MAX_PLACED or not BaseHub.in_base()
		row.append(place)
		defence.add_child(UiKit.button_row(row))
	var booked: Dictionary = v.get("assault", {})
	if not booked.is_empty():
		defence.add_child(UiKit.text("Expect an assault on day %d (%s)." % [int(booked.day), String(booked.faction).capitalize()]))
	_add_restock_row(go)
	go.add_child(UiKit.button_row([_loadouts_button()]))


## S0743 (restock left the medic short silently): what someone's last restock couldn't give
## them (Roster.restock_short_of), under their row until a restock fills them (deploying
## without it keeps it: Roster.record_loadout).
## The region map's marks from the view: the zone of the contract in prep (and its other zones,
## LZ-7) and those of the contracts held.
static func region_marks(v: Dictionary) -> Dictionary:
	var marks := {}
	for c: Dictionary in v.get("held", []):
		if String(c.get("zone_id", "")) != "":
			marks[String(c.zone_id)] = "held"
	var contract: Dictionary = (v.get("prep", {}) as Dictionary).get("contract", {})
	for leg: Dictionary in contract.get("legs", []):
		marks[String(leg.get("zone_id", ""))] = "leg"
	if String(contract.get("zone_id", "")) != "":
		marks[String(contract.zone_id)] = "prep"
	return marks


func _add_short_line(rows: VBoxContainer, who: String, person: Dictionary) -> void:
	var short := Roster.restock_short_of(person)
	if short.is_empty():
		return
	var line := UiKit.warn("%s is short after restock: %s" % [who, Restock.list_text(short)])
	line.name = "Short_" + who.validate_node_name()
	rows.add_child(line)


## Playtest S2: kitting up from the stash in one go, the kit each deployed in last time
## (BaseHub.server_restock_player / server_restock_squad). What it did shows in the status line.
func _add_restock_row(rows: VBoxContainer) -> void:
	var mine := UiKit.button("Restock my last loadout", func() -> void: BaseHub.request("restock"),
		"Rebuild the kit you last deployed with from the stash; what the stash is short of is listed")
	var squad := UiKit.button("Restock squad", func() -> void: BaseHub.request("restock_squad"),
		"Rebuild every picked squadmate's last loadout (everyone at the muster line if nobody is picked) from the stash")
	squad.disabled = not multiplayer.is_server()  # the squad leader (the host)
	var row := UiKit.button_row([mine, squad])
	row.name = "Restock"
	rows.add_child(row)


func _build_roster(rows: VBoxContainer, v: Dictionary) -> void:
	var roster: Dictionary = v.get("roster", {})
	var members: Dictionary = roster.get("members", {})
	if members.is_empty():
		rows.add_child(UiKit.text("Nobody on the books yet: hire at the hiring board."))
	var ids := members.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = members[mid]
		var extra: Array = []
		var items := UiKit.hint("%d items" % _item_total(m.get("gear", {})))
		items.autowrap_mode = TextServer.AUTOWRAP_OFF
		extra.append(items)
		if Roster.is_available(m):
			extra.append(UiKit.button("Let go", func() -> void: BaseHub.request("release", [mid]), "Release %s from the company" % m.callsign))
		rows.add_child(_line("%s \"%s\"  %s  %s" % [m.name, m.callsign, Roles.short_name(StringName(m.role)), Roster.status_text(m)], extra))
		var history: Array = m.get("history", [])
		var last := ("  Last: day %d, %s" % [int(history[-1].day), history[-1].text]) if not history.is_empty() else ""
		rows.add_child(_indent(UiKit.hint("%s  missions %d  $%d/day  %s%s" % [Roster.person_text(m), int(m.get("missions", 0)), int(m.get("wage", 0)),
			_skills_text(m), last])))


func _build_hiring(rows: VBoxContainer, v: Dictionary) -> void:
	var pool: Array = v.get("hiring", {}).get("pool", [])
	rows.add_child(UiKit.hint("The board turns over every %d days (last on day %d)." % [Hiring.REFRESH_DAYS, int(v.get("hiring", {}).get("refreshed_day", 1))]))
	if pool.is_empty():
		rows.add_child(UiKit.text("Nobody on the board."))
	for c: Dictionary in pool:
		var veteran := " (veteran)" if int(c.get("missions", 0)) >= 10 else ""
		var cid := String(c.cid)
		var hire := UiKit.button("Hire ($%d)" % int(c.fee), func() -> void: BaseHub.request("hire", [cid]),
			"Hire %s for $%d up front, then $%d a day" % [c.callsign, int(c.fee), int(c.demand)])
		rows.add_child(_line("%s \"%s\"  %s%s  asks $%d/day" % [c.name, c.callsign, Roles.display_name(StringName(c.role)), veteran, int(c.demand)], [hire]))
		rows.add_child(_indent(UiKit.hint("%s  missions %d  %s" % [Roster.person_text(c), int(c.missions), _skills_text(c)])))


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
		var quote := Roster.medbay_quote(person)
		var extra: Array = []
		if quote.is_empty():
			extra.append(UiKit.hint("treated"))
		else:
			var who := String(p[0])
			extra.append(UiKit.button("Treat: %d days sooner ($%d)" % [int(quote.days_saved), int(quote.cost)], func() -> void: BaseHub.request("medbay", [who])))
		rows.add_child(_line("%s: %d days (%s)" % [p[2], int(person.sit_out_days), ", ".join(PackedStringArray(person.get("injuries", [])))], extra))
	if not anyone:
		rows.add_child(UiKit.text("Nobody is recovering."))
	var mia: Array = []
	for m: Dictionary in roster.get("members", {}).values():
		if String(m.get("status", "")) == Roster.MIA:
			mia.append("%s (%s)" % [m.callsign, m.get("mia_zone", "?")])
	if not mia.is_empty():
		rows.add_child(UiKit.warn("Missing in action: %s. Recovery contracts are requested from the board." % ", ".join(PackedStringArray(mia))))


## The base's shop (audit P1-12: this tab was a plainer second shop beside ShopScreen): ShopScreen's
## type filter and support call prices, a row per item with its ItemInfo tooltip, bought through
## the host (BaseHub.request "buy", delivered to the armory counter).
func _build_shop(rows: VBoxContainer, v: Dictionary) -> void:
	rows.add_child(UiKit.hint("Bought items are delivered to the armory counter. Hover an item for what it is and how it's used."))
	var filter := OptionButton.new()
	for type in SHOP_TYPES:
		filter.add_item("Everything" if type == "" else type.capitalize())
		if type == _shop_type:
			filter.select(filter.item_count - 1)
	filter.item_selected.connect(func(i: int) -> void:
		_shop_type = SHOP_TYPES[i]
		refresh())
	rows.add_child(UiKit.row("Show", filter, 120.0))
	# Captain, 2026-10-17: "a sell button and search feature in the shop". The search filters the
	# lines as you type (no rebuild, so the box keeps focus): what's for sale and what you can sell.
	var search := LineEdit.new()
	search.placeholder_text = "Search items"
	search.text = _shop_query
	search.clear_button_enabled = true
	rows.add_child(UiKit.row("Search", search, 120.0))
	var searchable: Array[Control] = []
	search.text_changed.connect(func(q: String) -> void:
		_shop_query = q
		_filter_shop(searchable))
	var shown := 0
	for entry: Dictionary in v.get("catalog", []):
		var id := StringName(entry.get("id", ""))
		var item := ItemDB.get_item(id)
		if item == null or (_shop_type != "" and String(item.type) != _shop_type):
			continue
		shown += 1
		var buy := UiKit.button("Buy", func() -> void: BaseHub.request("buy", [String(id), 1]), "Buy one %s ($%d)" % [item.name, int(entry.price)])
		var buy5 := UiKit.button("Buy 5", func() -> void: BaseHub.request("buy", [String(id), 5]), "Buy five %s ($%d)" % [item.name, 5 * int(entry.price)])
		var line := _line("%s  (%s)  $%d" % [item.name, item.type, int(entry.price)], [buy, buy5])
		ItemInfo.apply(line.get_child(0), id)  # hover: what it is and how to use it (Captain, 2026-10-14: "item descriptions plus uses also needed")
		line.set_meta(&"search", "%s %s %s" % [item.name, item.type, id])
		searchable.append(line)
		rows.add_child(line)
	if shown == 0:
		rows.add_child(UiKit.text("Nothing of that kind for sale."))
	# Selling: what's in the company stash, at the shop's buying price (a damaged piece for less
	# is priced when sold: Economy.server_sell).
	var sell_rows := UiKit.section("Sell from the stash", rows)
	var stock := BaseArmory.counts(v.get("stash", []))
	var ids := stock.keys()
	ids.sort()
	var sellable := 0
	for sid: String in ids:
		var it := ItemDB.get_item(StringName(sid))
		var each := Prices.sell_price(StringName(sid), 1, {})
		if it == null or each <= 0 or (_shop_type != "" and String(it.type) != _shop_type):
			continue
		sellable += 1
		var n := int(stock[sid])
		var sell1 := UiKit.button("Sell", func() -> void: Economy.sell_from_stash(StringName(sid), 1), "Sell one %s ($%d)" % [it.name, each])
		var sell_all := UiKit.button("Sell all", func() -> void: Economy.sell_from_stash(StringName(sid), mini(n, 50)), "Sell all %d %s (about $%d)" % [n, it.name, each * n])
		var sline := _line("%s x%d  $%d each" % [it.name, n, each], [sell1, sell_all])
		ItemInfo.apply(sline.get_child(0), StringName(sid))
		sline.set_meta(&"search", "%s %s %s" % [it.name, it.type, sid])
		searchable.append(sline)
		sell_rows.add_child(sline)
	if sellable == 0:
		sell_rows.add_child(UiKit.hint("Nothing in the stash the shop buys."))
	_filter_shop(searchable)
	rows.add_child(UiKit.hint("Support calls (paid when called, from the contract's support budget first): " + ", ".join(
		Prices.support_kinds().map(func(k: Variant) -> String: return "%s $%s" % [String(k), DebriefCalc.money(Prices.support_price(String(k)))]))))


func _build_armory(rows: VBoxContainer, v: Dictionary) -> void:
	rows.add_child(UiKit.text("The company stash lies in the armory: pick up what you need, drop what you bring back. Anything left in the base counts."))
	rows.add_child(UiKit.button_row([_loadouts_button()]))
	_add_item_lines(UiKit.section("In the stash", rows), BaseArmory.counts(v.get("stash", [])))
	# Pouches on the stash's carriers and what's in them come with the carrier.
	var inside := BaseArmory.contents_counts(v.get("stash", []))
	if not inside.is_empty():
		_add_item_lines(UiKit.section("On the carriers and in their pouches", rows), inside)


## One cut line per item (id -> count), each with its ItemInfo tooltip.
## Shows only the shop lines whose name, type or id has every word of the search in it.
func _filter_shop(lines: Array[Control]) -> void:
	var words := _shop_query.to_lower().split(" ", false)
	for line in lines:
		if not is_instance_valid(line):
			continue
		var hay := String(line.get_meta(&"search", "")).to_lower()
		line.visible = words.is_empty() or Array(words).all(func(w: String) -> bool: return hay.contains(w))


func _add_item_lines(rows: VBoxContainer, counts: Dictionary) -> void:
	var ids := counts.keys()
	ids.sort()
	if ids.is_empty():
		rows.add_child(UiKit.hint("Nothing."))
	for id: String in ids:
		var item := ItemDB.get_item(StringName(id))
		var label := _cut("%s x%d" % [item.name if item else id, int(counts[id])])
		ItemInfo.apply(label, StringName(id))  # hover: what it is and how to use it (Captain, 2026-10-14: "item descriptions plus uses also needed")
		rows.add_child(label)


## Why Service is off away from the motor pool's sign.
const AWAY_FROM_POOL := "Service is booked at the motor pool's sign"


## The motor pool's page (audit P2-23: it had no page, only an interaction ring of one line per
## vehicle): each company vehicle (MotorPoolNode's copy of MotorPool.view()) with its state, and
## a Service button that books it into the workshop (MotorPoolNode.request_repair; the host
## checks the asker is at the motor pool terminal, which only the base has).
func _build_motor_pool(rows: VBoxContainer) -> void:
	rows.add_child(UiKit.hint("The company's vehicles. Take one on a deployment from the briefing's supports; one left in a zone or destroyed there is gone from the pool. Service is booked at the motor pool's sign."))
	# Wave 6 call #1: allied quartermasters sell MRAPs from Trusted (Quartermaster.vehicle_deals).
	var buy := UiKit.section("Buy vehicles (allied quartermasters)", rows)
	var deals := Quartermaster.vehicle_deals()
	if deals.is_empty():
		buy.add_child(UiKit.hint("Nobody sells the company vehicles yet: stand Trusted with an allied force (US, UK, Canadian) for an M-ATV."))
	for d: Dictionary in deals:
		var model := String(d.model)
		var b := UiKit.button("Buy a %s ($%s, %s)" % [String(d.name), DebriefCalc.money(int(d.price)), String(MissionRegistry.faction(String(d.faction)).get("name", d.faction))],
			func() -> void:
				BaseHub.request("buy_vehicle", [model])
				get_tree().create_timer(0.5).timeout.connect(refresh))
		b.disabled = not multiplayer.is_server()
		buy.add_child(b)
	var node := MotorPoolNode.of(self)
	var pool: Array = node.pool if node else []
	if pool.is_empty():
		rows.add_child(UiKit.text("The company owns no vehicles."))
	for e: Dictionary in pool:
		var quote: Dictionary = e.get("quote", {})
		var why := String(e.get("problem", ""))
		var id := String(e.id)
		var service := UiKit.button("Service", func() -> void:
			node.request_repair(id)
			get_tree().create_timer(0.5).timeout.connect(refresh))  # the pool comes back from the host
		service.name = "Service_" + id.validate_node_name()
		if why == "" and (int(quote.get("cost", 0)) > 0 or int(quote.get("days", 0)) > 0):
			service.text = "Service: $%s, %d day%s" % [DebriefCalc.money(int(quote.cost)), int(quote.days), "" if int(quote.days) == 1 else "s"]
			service.tooltip_text = "Fix every hit zone, the battery and the hull and fill the tank: %s" % service.text.trim_prefix("Service: ")
			## Off away from the motor pool's sign (this page is a tab on every terminal's screen,
			## and the host refuses a booking from anywhere else: review of ui/base-hub).
			if not node.local_at_terminal():
				service.disabled = true
				service.tooltip_text = AWAY_FROM_POOL
		else:
			service.disabled = true
			service.tooltip_text = why if why != "" else "Ready: nothing to fix"
		rows.add_child(_line("%s: %d%% damaged, %d L fuel%s" % [String(e.name), roundi(float(e.get("damage", 0.0)) * 100.0), roundi(float(e.get("fuel", 0.0))),
			"" if why == "" else "  (%s)" % why], [service]))
	_build_air_wing(UiKit.section("Air wing", rows))


## The air wing's upgrades (HeliUpgrades, Captain 2026-10-17): each one's name, what it does
## and its price, with Buy (Economy.buy_heli_upgrade: the host pays and records it) or Owned.
func _build_air_wing(rows: VBoxContainer) -> void:
	rows.add_child(UiKit.hint("One-time upgrades to the company's support aircraft. They apply to every support call from the next one on."))
	for d: Dictionary in HeliUpgrades.defs():
		var id := String(d.id)
		var why := HeliUpgrades.problem(id)
		var owned := HeliUpgrades.owned(id)
		var buy := UiKit.button("Owned" if owned else "Buy: $%s" % DebriefCalc.money(int(d.get("cost", 0))), func() -> void:
			Economy.buy_heli_upgrade(id)
			get_tree().create_timer(0.5).timeout.connect(refresh), String(d.get("text", "")))
		buy.name = "Upgrade_" + id.validate_node_name()
		buy.disabled = why != ""
		if why != "" and not owned:
			buy.tooltip_text = why
		rows.add_child(_line("%s: %s" % [String(d.get("name", id)), String(d.get("text", ""))], [buy]))


## The supply cage (feat/pallet-tagging, Pallets): the FOB's own stocks (fuel, parts, ammo,
## supplies, medical), what they do, drawing ammo/supplies/medical into the armory stash, and
## the tagged lots waiting in storage (sell for the better price, gift, or keep as stocks).
func _build_stores(rows: VBoxContainer) -> void:
	rows.add_child(UiKit.hint("Stocks from pallets kept at the FOB. Fuel and parts cover part of support calls and repairs automatically; ammo, supplies and medical can be drawn into the armory stash."))
	for kind: String in Pallets.stock_kinds():
		var n := Economy.stock(kind)
		var controls: Array = []
		if not ((Pallets.data().get("draw", {}) as Dictionary).get(kind, []) as Array).is_empty():
			controls.append(UiKit.button("Draw 1", func() -> void: Contracts.draw_stock(kind, 1), "Move one unit into the armory stash"))
			controls.append(UiKit.button("Draw 5", func() -> void: Contracts.draw_stock(kind, 5), "Move five units into the armory stash"))
			for c: Variant in controls:
				(c as Button).disabled = n <= 0
		rows.add_child(_line("%s: %d units  (covers $%d each)" % [Pallets.stock_name(kind), n, Pallets.offset_per_unit(kind)], controls))
	var store: Array = Economy.pallet_store()
	rows.add_child(UiKit.text("In storage: %s" % ("nothing" if store.is_empty() else "%d lot%s" % [store.size(), "" if store.size() == 1 else "s"])))
	for i in store.size():
		var lot: Dictionary = store[i]
		var factions := OptionButton.new()
		for f: String in Pallets.gift_factions():
			factions.add_item(MissionRegistry.faction_name(f))
			factions.set_item_metadata(factions.item_count - 1, f)
			if f == String(lot.get("faction", "")):
				factions.select(factions.item_count - 1)
		var controls2: Array = [UiKit.button("Sell ($%s)" % DebriefCalc.money(Pallets.sell_price(lot, true)), func() -> void: Contracts.pallet_action("store", i, "sell"),
			"The storage price, better than the quick sale")]
		if Pallets.can_keep(lot):
			controls2.append(UiKit.button("Keep", func() -> void: Contracts.pallet_action("store", i, "keep"), "Add it to the FOB's stocks"))
		controls2.append(factions)
		controls2.append(UiKit.button("Gift (+%d rep)" % Pallets.gift_rep(lot), func() -> void:
			if factions.item_count > 0:
				Contracts.pallet_action("store", i, "gift", String(factions.get_item_metadata(factions.selected))), "Gift it to the faction chosen"))
		rows.add_child(_line(Pallets.lot_text(lot), controls2))


# --- Bits ------------------------------------------------------------------------------------

## The loadout menu (Captain, 2026-10-14: "a menu for equipping yourself better and your
## squadmates how you want to"): this screen steps aside while it's up and comes back after.
func _loadouts_button() -> Button:
	var b := UiKit.button("Loadouts: kit yourself and the squad from the stash", _open_loadouts,
		"Paper doll for you and each squadmate: weapons, optics, armour, pack, ammo, meds, grenades; standing loadouts for Restock")
	b.name = "Loadouts"
	return b


func _open_loadouts() -> void:
	var screen := BaseHub.open_loadout()
	if screen == null:
		return
	visible = false
	screen.closed.connect(func() -> void:
		if is_inside_tree():
			open(page))


func _role_picker(mid: String, current: StringName) -> OptionButton:
	var picker := OptionButton.new()
	picker.tooltip_text = "Role on the next deployment"
	for role in Roles.ids():
		picker.add_item(Roles.display_name(role))
		picker.set_item_metadata(picker.item_count - 1, String(role))
		if role == current:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(i: int) -> void: BaseHub.request("role", [mid, picker.get_item_metadata(i)]))
	return picker


## HX-1 certification (Roster.hx1_certified/hx1_eligible, BaseHub.server_certify_hx1): a
## button to spend the cash once a member's missions clear the bar, a plain note once they're
## certified, nothing once there's neither (keeps the row short for everyone who'll never fly
## the heavy exo).
func _hx1_cert_button(mid: String, m: Dictionary) -> Control:
	if Roster.hx1_certified(m):
		return UiKit.hint("HX-1 certified")
	if not Roster.hx1_eligible(m):
		return UiKit.hint("HX-1: %d/%d missions" % [int(m.get("missions", 0)), Roster.HX1_CERT_MISSIONS])
	var button := UiKit.button("Certify HX-1 ($%d)" % Roster.HX1_CERT_COST,
		func() -> void: BaseHub.request("certify_hx1", [mid]), "Certify %s to pilot the HX-1 Assault Frame" % m.name)
	button.disabled = not multiplayer.is_server()  # the host's call, same as hiring and release
	return button


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


## One line of text that takes the row's spare width and cuts with "..." when there isn't
## enough, the whole text in its tooltip (audit P1-12: rows were 640 to 760 px Labels with
## clip_text, so wages and skills were cut off with no sign and no way to read them).
static func _cut(text: String, tooltip := "") -> Label:
	var label := Label.new()
	label.text = text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.tooltip_text = tooltip if tooltip != "" else text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


## A row: `text` cut to the room left (_cut), then `controls` (buttons) at its end.
static func _line(text: String, controls: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	row.add_child(_cut(text))
	for c: Control in controls:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	return row


## A detail line (wrapping) indented under its row.
static func _indent(label: Label) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", UiKit.SPACE_L)
	m.add_child(label)
	return m
