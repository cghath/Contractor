class_name LoadoutScreen
extends Control
## The loadout menu at the FOB (Captain, 2026-10-14: "we need a menu for equipping yourself
## better and your squadmates how you want to as well"; docs/loadout_menu.md). Three columns:
## the people (you, the other players, the squad picked for the next deployment), the selected
## one's paper doll (worn slots with what the stash has for them, what they carry by group, the
## helpers and their standing loadout) and the stash. It shows BaseHub.view and the bodies at
## the hub, and every change is a request to the host ("loadout": BaseHub.server_loadout), so
## everything comes out of and goes back into the stash.
##
## It fills whatever window it's in (BaseHub.open_loadout puts it on its own layer): the columns
## share the width and scroll on their own, and every row of buttons wraps (HFlowContainer), so
## it fits 1280x720 to 3840x2160 at UI scale 0.75 to 1.5 (the loadout suite's fit check).
## Keyboard: Tab / arrows move between the controls, Enter presses, Esc closes; the first
## button has the focus when it opens.
##
## feat/ui-pass (Captain's tasking, 2026-10-19): in the shared look (UiKit, the theme) with no
## colours or sizes of its own; no text clipped silently (the title, headings and status wrap,
## a person's button cuts with "..." and has the whole line in its tooltip, a drop-down is as
## wide as its prompt); every row's buttons wrap under it (UiKit.action_row). ui_test fits it.
##
## ui-modern (Captain, 2026-10-20: "common sense layout tools", "better explanations"): a
## subtitle and a "?" help panel; the stash has a search box, a kind filter and a sort; every
## row has the item's picture (ItemIcons, in a windowed game) and its ItemInfo tooltip; a stash
## row dragged onto the Kit column goes on the selected person (as its Wear / Mount / +1 button
## does) and a kit row dragged onto the Stash column goes back; Sell asks first.

signal closed

## The columns' share of the width (people, doll, stash).
const RATIOS := [1.0, 2.0, 1.4]
## How often the selected person's kit is looked at for changes made by hand (seconds).
const POLL_S := 0.5
## A row's item picture (logical px).
const ICON := 36
## The stash's sorts: [id, label].
const SORTS := [["name", "Sort: name"], ["count", "Sort: most first"], ["weight", "Sort: heaviest first"], ["value", "Sort: most valuable"]]
const HELP := [
	"Pick a person on the left; the middle shows what they wear and carry, the right what the company's stash holds.",
	"Wear, Mount and +1 move an item from the stash onto them; -1 and Take off put it back. Or drag a stash row onto the Kit column, or a kit row onto the Stash column.",
	"Quick kit fills ammo, a medic kit or a whole role kit from the stash. The standing loadout is what Restock refills them to after a deployment.",
	"Search, filter and sort the stash from the boxes over it. Hover any row for what the item is and does.",
	"Sell sells one item to the shop for the price shown (it asks first). Other players set their own kit; you can give them items.",
]

## The person shown: a member id or "player:<key>".
var selected := ""
var people_box: VBoxContainer
var doll_box: VBoxContainer
var stash_box: VBoxContainer
var columns: Array[Control] = []
var status: Label
var _poll := 0.0
var _seen_hash := 0
## The stash's search text (lowered), kind filter ("" all, else a Loadouts group) and sort.
var stash_query := ""
var stash_group := ""
var stash_sort := "name"
var _icons_waiting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.apply(self)
	var panel := UiKit.panel(true)  # opaque: it opens over the base screen
	panel.name = "Panel"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	var head := UiKit.header("Loadouts", "Kit yourself and your squad from the company stash before the next deployment.",
		PackedStringArray(HELP), [["Esc", "Close"], ["Tab / arrows", "Move"], ["Enter", "Press"], ["Drag", "Stash to kit and back"]], false)
	var top := head.get_child(0) as HBoxContainer
	var close_button := UiKit.button("Close", close, "Close the loadouts (Esc)")
	close_button.name = "Close"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(close_button)
	root.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(body)
	people_box = _column(body, "People", RATIOS[0])
	doll_box = _column(body, "Kit", RATIOS[1])
	stash_box = _column(body, "Stash", RATIOS[2], _stash_tools())
	_drop_zone(columns[1], "kit")
	_drop_zone(columns[2], "stash")
	status = UiKit.text("")
	status.name = "Status"
	root.add_child(status)
	root.add_child(UiKit.key_hints([["Esc", "Close"], ["Drag", "Stash to kit and back"], ["Hover", "What an item is"]]))
	BaseHub.view_changed.connect(refresh)
	BaseHub.note.connect(_on_note)
	BaseHub.request("loadout", ["", "sync", {}])  # the muster line's gear into the roster's copy
	refresh()
	UiKit.focus_first(people_box)  # the people first (Close would shut it on Enter)


func _exit_tree() -> void:
	if BaseHub.view_changed.is_connected(refresh):
		BaseHub.view_changed.disconnect(refresh)
	if BaseHub.note.is_connected(_on_note):
		BaseHub.note.disconnect(_on_note)


## Back to the view (the base screen, opened from, takes the mouse again on `closed`; from the
## inventory screen it's already shut).
func close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_poll += delta
	if _poll < POLL_S:
		return
	_poll = 0.0
	var h := hash([gear_of(selected), BaseHub.view.get("stash", [])])  # kit picked up or dropped by hand
	if h != _seen_hash:
		refresh()


func _on_note(text: String) -> void:
	if text != "":
		status.text = text


# --- People ---------------------------------------------------------------------------------

## Everyone the menu lists: [{"who", "name", "role", "mine": may change, "player": bool}], you
## first, then the other players, then the squad picked for the next deployment (everyone at
## the muster line if nobody is picked).
func people() -> Array:
	var v := BaseHub.view
	var out: Array = []
	var me := multiplayer.get_unique_id()
	var keys: Dictionary = v.get("players", {})
	var players: Dictionary = v.get("roster", {}).get("players", {})
	var peers := keys.keys()
	peers.sort_custom(func(a: Variant, b: Variant) -> bool: return (int(a) == me and int(b) != me) or (int(a) != me and int(b) != me and int(a) < int(b)))
	for peer: Variant in peers:
		var key := String(keys[peer])
		out.append({"who": "player:" + key, "name": "You (%s)" % key if int(peer) == me else key,
			"role": StringName(players.get(key, {}).get("role", Roles.RIFLEMAN)), "mine": int(peer) == me, "player": true, "peer": int(peer)})
	var members: Dictionary = v.get("roster", {}).get("members", {})
	var picked: Array = v.get("prep", {}).get("squad", []).filter(func(mid: Variant) -> bool:
		return members.has(mid) and Roster.is_available(members[mid]))
	var ids: Array = picked if not picked.is_empty() else members.keys().filter(func(mid: Variant) -> bool: return Roster.is_available(members[mid]))
	if picked.is_empty():
		ids.sort()
	for mid: Variant in ids:
		var m: Dictionary = members[mid]
		out.append({"who": String(mid), "name": String(m.callsign), "role": StringName(m.get("role", Roles.RIFLEMAN)), "mine": true, "player": false})
	return out


func _person(who: String) -> Dictionary:
	for p: Dictionary in people():
		if p.who == who:
			return p
	return {}


## The roster entry of `who` in the view.
func entry_of(who: String) -> Dictionary:
	var roster: Dictionary = BaseHub.view.get("roster", {})
	if who.begins_with("player:"):
		return roster.get("players", {}).get(who.trim_prefix("player:"), {})
	return roster.get("members", {}).get(who, {})


## What `who` wears and carries now (an Inventory.net_state, JSON-safe): a player's body at the
## hub (it has what they picked up by hand), else the roster's copy.
func gear_of(who: String) -> Dictionary:
	var p := _person(who)
	var lvl := CompoundLevel.current(self)
	if p.get("player", false) and lvl:
		var body := lvl.players.get_node_or_null(NodePath(str(int(p.peer)))) as Soldier
		if body and body.inventory:
			return Roster.json_safe(body.inventory.net_state)
	return entry_of(who).get("gear", {})


# --- Building the columns ---------------------------------------------------------------------

## Rebuilds the three columns from BaseHub.view (keeps the keyboard focus where it was).
func refresh() -> void:
	if not is_node_ready():
		return
	var list := people()
	if list.is_empty():
		selected = ""
	elif _person(selected).is_empty():
		selected = String(list[0].who)
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var focus_path := String(get_path_to(focus)) if focus and is_ancestor_of(focus) else ""
	for box: VBoxContainer in [people_box, doll_box, stash_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_build_people(list)
	_build_doll(_person(selected))
	_build_stash(_person(selected))
	_seen_hash = hash([gear_of(selected), BaseHub.view.get("stash", [])])
	if focus_path != "":
		var again := get_node_or_null(NodePath(focus_path)) as Control
		if again and again.focus_mode != Control.FOCUS_NONE:
			again.grab_focus.call_deferred()


func _build_people(list: Array) -> void:
	if list.is_empty():
		people_box.add_child(UiKit.text("Nobody here: the menu works at the FOB, between deployments."))
		return
	var picked: Array = BaseHub.view.get("prep", {}).get("squad", [])
	for p: Dictionary in list:
		var gear := gear_of(String(p.who))
		var load := Loadouts.load_of(gear)
		var b := Button.new()
		b.text = "%s  %s\n%.1f kg %s%s" % [p.name, Roles.short_name(p.role), float(load.kg), Loadouts.tier_name(int(load.tier)),
			"  (short)" if not Roster.restock_short_of(entry_of(String(p.who))).is_empty() else ""]
		b.pressed.connect(func() -> void: select(String(p.who)))
		b.name = "Person_" + String(p.who).validate_node_name()
		b.toggle_mode = true
		## The column can be narrow (1280x720 at UI scale 1.5): the text cuts with "..." and the
		## tooltip has it whole (it was clipped silently before).
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = b.text
		b.set_pressed_no_signal(p.who == selected)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		people_box.add_child(b)
	if picked.is_empty():
		people_box.add_child(UiKit.hint("Nobody picked for the next deployment yet: everyone at the muster line is listed."))


func select(who: String) -> void:
	selected = who
	refresh()


## Sends a loadout request for the selected person.
func ask(op: String, params := {}) -> void:
	status.text = "..."
	BaseHub.request("loadout", [selected, op, params])


func _build_doll(p: Dictionary) -> void:
	if p.is_empty():
		return
	var who := String(p.who)
	var gear := gear_of(who)
	var editable: bool = p.mine
	var load := Loadouts.load_of(gear)
	doll_box.add_child(UiKit.heading("%s, %s" % [p.name, Roles.display_name(p.role)]))
	doll_box.add_child(UiKit.text("Load %.1f kg: %s (movement: %s)" % [float(load.kg), Loadouts.tier_name(int(load.tier)), _tier_hint(int(load.tier))]))
	if not editable:
		doll_box.add_child(UiKit.hint("View only: other players set their own kit (you can give them items)."))
	if editable:
		_build_buy(who)
	var stash: Array = BaseHub.view.get("stash", [])
	var have := BaseArmory.counts(stash)
	# Worn: each slot with what the stash has for it.
	doll_box.add_child(UiKit.heading("Worn"))
	var slots: Dictionary = gear.get("slots", {})
	var slot_state: Dictionary = gear.get("slot_state", {})
	var carrier := ItemDB.get_item(StringName(String(slots.get("vest", ""))))
	var pockets: Array = carrier.stats.get("plate_slots", []) if carrier else []
	for slot in Loadouts.DOLL_SLOTS:
		if slot in Inventory.PLATE_SLOTS and not String(slot) in pockets:
			continue
		var id := String(slots.get(String(slot), ""))
		var item := ItemDB.get_item(StringName(id)) if id != "" else null
		var text := "%s: %s" % [Loadouts.SLOT_NAMES[slot], item.name if item else "-"]
		if item and Optics.has_rail(item):
			var optic := Optics.mounted(item, slot_state.get(String(slot), {}))
			text += " (%s)" % (optic.name if optic else "irons")
		var row := _row(text, id)
		if editable and item:
			_draggable(row, {"from": "worn", "id": id, "slot": String(slot)})
		if editable:
			var choices: Array = [["Swap...", ""]]
			if item:
				choices.append(["Take off (to stash)", "-"])
			for sid: String in _sorted(have.keys()):
				var it := ItemDB.get_item(StringName(sid))
				if Loadouts.fits_slot(it, slot) and sid != id:
					choices.append(["%s (x%d)" % [it.name, int(have[sid])], sid])
			if choices.size() > 1:
				var s := slot
				row.get_meta(&"controls").add_child(_picker("Swap_" + String(slot), choices, func(v: String) -> void:
					ask("slot", {"slot": String(s), "id": "" if v == "-" else v})))
			if item and Optics.has_rail(item):
				var optics: Array = [["Optic...", ""], ["Irons (optic to stash)", "-"]]
				for sid: String in _sorted(have.keys()):
					if Optics.is_optic(ItemDB.get_item(StringName(sid))):
						optics.append(["%s (x%d)" % [ItemDB.get_item(StringName(sid)).name, int(have[sid])], sid])
				var s2 := slot
				row.get_meta(&"controls").add_child(_picker("Optic_" + String(slot), optics, func(v: String) -> void:
					ask("optic", {"slot": String(s2), "id": "" if v == "-" else v})))
		doll_box.add_child(row)
	# Carried, by group.
	var carried := Roster.gear_counts(gear)
	for slot: Variant in slots:
		var worn := String(slots[slot])
		if worn != "" and carried.has(worn):
			carried[worn] = int(carried[worn]) - 1
			if int(carried[worn]) <= 0:
				carried.erase(worn)
	var others: Array = people().filter(func(o: Dictionary) -> bool: return o.who != who)
	for group in Loadouts.GROUPS:
		var ids: Array = _sorted(carried.keys()).filter(func(id: String) -> bool: return Loadouts.group_of(ItemDB.get_item(StringName(id))) == group)
		if ids.is_empty():
			continue
		doll_box.add_child(UiKit.heading(Loadouts.GROUP_NAMES[group]))
		for id: String in ids:
			var row := _row("%s x%d" % [_name(id), int(carried[id])], id)
			if editable:
				var flow: HFlowContainer = row.get_meta(&"controls")
				var minus := UiKit.button("-1", func() -> void: ask("remove", {"id": id, "count": 1}), "One back to the stash")
				minus.name = "Remove_" + id
				flow.add_child(minus)
				_draggable(row, {"from": "kit", "id": id})
				if not others.is_empty():
					var to: Array = [["Give 1 to...", ""]]
					for o: Dictionary in others:
						to.append([String(o.name), String(o.who)])
					flow.add_child(_picker("Give_" + id, to, func(v: String) -> void: ask("give", {"id": id, "count": 1, "to": v})))
			doll_box.add_child(row)
	if carried.is_empty():
		doll_box.add_child(UiKit.hint("Carrying nothing else."))
	if not editable:
		return
	# Helpers.
	doll_box.add_child(UiKit.heading("Quick kit (from the stash)"))
	var helpers := UiKit.button_row([])
	var fill := UiKit.button("Fill ammo", func() -> void: ask("fill_ammo"))
	fill.name = "FillAmmo"
	fill.tooltip_text = "Each gun's magazines up to the role kit's count (full ones from the stash first)"
	helpers.add_child(fill)
	var medic := UiKit.button("Medic kit", func() -> void: ask("medic_kit"))
	medic.name = "MedicKit"
	medic.tooltip_text = "The medic kit's medical items, aid bag and sustainment pouch, as far as the stash has them"
	helpers.add_child(medic)
	var roles: Array = [["Role kit...", ""]]
	for role in Roles.ids():
		roles.append([Roles.display_name(role), String(role)])
	helpers.add_child(_picker("RoleKit", roles, func(v: String) -> void: ask("role_kit", {"role": v})))
	var froms: Array = [["Copy kit from...", ""]]
	for o: Dictionary in others:
		froms.append([String(o.name), String(o.who)])
	if froms.size() > 1:
		helpers.add_child(_picker("CopyKit", froms, func(v: String) -> void: ask("copy_kit", {"from": v})))
	doll_box.add_child(helpers)
	# The standing loadout: what Restock refills to.
	doll_box.add_child(UiKit.heading("Standing loadout (what Restock refills to)"))
	var entry := entry_of(who)
	var standing := Roster.loadout_of(entry)
	var n := 0
	for c: Variant in Restock.counts(standing).values():
		n += int(c)
	doll_box.add_child(UiKit.text("%d items saved" % n if n > 0 else "None yet: save this kit, pick a role kit, or deploy (the kit you deploy in is written down)."))
	var short := Roster.restock_short_of(entry)
	if not short.is_empty():
		doll_box.add_child(UiKit.warn("Short after the last restock: " + Restock.list_text(short)))
	var standing_row := UiKit.button_row([])
	var save := UiKit.button("Save as standing", func() -> void: ask("save"))
	save.name = "SaveStanding"
	save.tooltip_text = "Write down this kit as what Restock refills to after each deployment"
	standing_row.add_child(save)
	var role_standing: Array = [["Standing = role kit...", ""]]
	for role in Roles.ids():
		role_standing.append([Roles.display_name(role), String(role)])
	standing_row.add_child(_picker("StandingRole", role_standing, func(v: String) -> void: ask("standing_role", {"role": v})))
	var squad: Array = others.filter(func(o: Dictionary) -> bool: return not o.player)
	if not squad.is_empty() and n > 0:
		var copy := UiKit.button("Copy standing to squad", func() -> void:
			ask("copy_standing", {"to": squad.map(func(o: Dictionary) -> String: return String(o.who))}))
		copy.name = "CopyStanding"
		copy.tooltip_text = "Give every listed squadmate this standing loadout (Restock then draws it for them)"
		standing_row.add_child(copy)
	var restock := UiKit.button("Restock to standing", func() -> void: ask("restock"))
	restock.name = "RestockStanding"
	restock.disabled = n == 0
	restock.tooltip_text = "Fill this kit back up to the standing loadout from the stash" if n > 0 else "Save a standing loadout first"
	standing_row.add_child(restock)
	doll_box.add_child(standing_row)


func _build_stash(p: Dictionary) -> void:
	var stash: Array = BaseHub.view.get("stash", [])
	var have := BaseArmory.counts(stash)
	if have.is_empty():
		stash_box.add_child(UiKit.hint("The stash is empty: buy at the shop, or bring kit back."))
		return
	var editable: bool = not p.is_empty() and p.mine
	if not p.is_empty():
		stash_box.add_child(UiKit.hint("Onto %s:" % p.name))
	var shown := 0
	for group in Loadouts.GROUPS:
		if stash_group != "" and group != stash_group:
			continue
		var ids: Array = stash_order(have, stash_sort).filter(func(id: String) -> bool:
			return Loadouts.group_of(ItemDB.get_item(StringName(id))) == group and UiKit.matches(_name(id), stash_query))
		if ids.is_empty():
			continue
		shown += ids.size()
		stash_box.add_child(UiKit.heading(Loadouts.GROUP_NAMES[group]))
		for id: String in ids:
			var row := _row("%s x%d" % [_name(id), int(have[id])], id)
			if editable:
				var flow: HFlowContainer = row.get_meta(&"controls")
				var item := ItemDB.get_item(StringName(id))
				var slot := _slot_for(item, gear_of(selected))
				if slot != &"":
					var wear := UiKit.button("Wear", func() -> void: ask("slot", {"slot": String(slot), "id": id}),
						"Put it on %s (what's worn there goes back to the stash)" % p.name)
					wear.name = "Wear_" + id
					flow.add_child(wear)
				elif Optics.is_optic(item):
					var mount := UiKit.button("Mount", func() -> void: ask("optic", {"slot": "primary", "id": id}),
						"Mount it on %s's primary weapon (the old optic goes back to the stash)" % p.name)
					mount.name = "Mount_" + id
					flow.add_child(mount)
				else:
					var one := UiKit.button("+1", func() -> void: ask("add", {"id": id, "count": 1}), "One onto %s, from the stash" % p.name)
					one.name = "Add_" + id
					flow.add_child(one)
					if group in ["ammo", "medical", "grenades"] and int(have[id]) > 1:
						var bulk := UiKit.button("+%d" % Loadouts.BULK, func() -> void: ask("add", {"id": id, "count": Loadouts.BULK}),
							"%d onto %s, from the stash" % [Loadouts.BULK, p.name])
						bulk.name = "AddBulk_" + id
						flow.add_child(bulk)
				_draggable(row, {"from": "stash", "id": id})
			var sell_flow: HFlowContainer = row.get_meta(&"controls")
			var price := Prices.sell_price(StringName(id), 1, {})
			if sell_flow and price > 0:
				var sell := UiKit.danger_button("Sell $%s" % DebriefCalc.money(price), func() -> void: ask_sell(id, price))
				sell.name = "Sell_" + id
				sell.tooltip_text = "Sell one %s to the shop for $%s (asks first)" % [_name(id), DebriefCalc.money(price)]
				sell_flow.add_child(sell)
			stash_box.add_child(row)
	if shown == 0:
		stash_box.add_child(UiKit.hint("Nothing in the stash matches the search or filter."))
	var inside := BaseArmory.contents_counts(stash)
	if not inside.is_empty():
		var n := 0
		for c: Variant in inside.values():
			n += int(c)
		stash_box.add_child(UiKit.hint("Plus %d items on the stash's carriers and packs and in their pouches (drawn when needed)." % n))


## The body slot a stash item goes in from the "Wear" button (a plate's first pocket of its
## kind on the carrier), or &"".
static func _slot_for(item: ItemData, gear: Dictionary) -> StringName:
	if item == null or item.slot == &"":
		return &""
	if item.slot == &"plate" or item.slot == &"side_plate":
		var carrier := ItemDB.get_item(StringName(String(gear.get("slots", {}).get("vest", ""))))
		if carrier == null:
			return &""
		var first := &""
		for pocket: String in carrier.stats.get("plate_slots", []):
			if Loadouts.fits_slot(item, StringName(pocket)):
				if String(gear.get("slots", {}).get(pocket, "")) == "":
					return StringName(pocket)
				if first == &"":
					first = StringName(pocket)
		return first
	return item.slot if item.slot in Loadouts.DOLL_SLOTS else &""


static func _tier_hint(tier: int) -> String:
	return ["full speed", "slower, tires faster", "much slower, short sprints", "barely moving"][clampi(tier, 0, 3)]


# --- Bits ------------------------------------------------------------------------------------

func _column(parent: HBoxContainer, title: String, ratio: float, tools: Control = null) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = title
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	columns.append(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiKit.heading(title))
	if tools:
		box.add_child(tools)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


## A row: its text (wrapping) and a wrapping row of controls under it (UiKit.action_row, meta
## "controls").
func _row(text: String, id: String) -> Control:
	var label := UiKit.text(text)
	label.tooltip_text = ItemInfo.tooltip(StringName(id)) if ItemDB.has_item(StringName(id)) else item_tooltip(id)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var inner := UiKit.action_row(text, [], label)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_icon(id))
	row.add_child(inner)
	row.set_meta(&"controls", inner.get_meta(&"controls"))
	return row


## The item's picture (ItemIcons), or an empty square while it's made (the screen refreshes
## when it's ready) and in a headless run.
func _icon(id: String) -> Control:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(ICON, ICON)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if id == "" or not ItemDB.has_item(StringName(id)):
		return rect
	rect.texture = ItemIcons.get_icon(StringName(id))
	if rect.texture == null and ItemIcons.can_render():
		var icons := ItemIcons.instance()
		if icons and not icons.icon_ready.is_connected(_on_icon_ready):
			icons.icon_ready.connect(_on_icon_ready)
	return rect


func _on_icon_ready(_id: StringName) -> void:
	if _icons_waiting:
		return
	_icons_waiting = true
	(func() -> void:
		_icons_waiting = false
		if is_inside_tree():
			refresh()).call_deferred()


## The stash's search box, kind filter and sort, over its list.
func _stash_tools() -> Control:
	var flow := HFlowContainer.new()
	flow.name = "StashTools"
	flow.add_theme_constant_override(&"h_separation", UiKit.SPACE_S)
	flow.add_theme_constant_override(&"v_separation", UiKit.SPACE_XS)
	var search := UiKit.search_field("Search the stash...", func(q: String) -> void:
		stash_query = q
		refresh())
	search.name = "StashSearch"
	flow.add_child(search)
	var kinds: Array = [["", "All kinds"]]
	for g: String in Loadouts.GROUPS:
		kinds.append([g, Loadouts.GROUP_NAMES[g]])
	var kind := UiKit.picker(kinds, func(v: Variant) -> void:
		stash_group = String(v)
		refresh(), "Show one kind of item only", stash_group)
	kind.name = "StashKind"
	flow.add_child(kind)
	var sort := UiKit.picker(SORTS, func(v: Variant) -> void:
		stash_sort = String(v)
		refresh(), "The order the stash lists items in, within each kind", stash_sort)
	sort.name = "StashSort"
	flow.add_child(sort)
	return flow


## `have`'s item ids (id -> count) in `sort` order: "name", "count" (most first), "weight"
## (heaviest first) or "value" (best sell price first); ties by name.
static func stash_order(have: Dictionary, sort: String) -> Array:
	var ids := _sorted(have.keys())
	var key := func(id: String) -> float:
		match sort:
			"count":
				return float(have[id])
			"weight":
				var it := ItemDB.get_item(StringName(id))
				return it.mass_kg if it else 0.0
			"value":
				return float(Prices.sell_price(StringName(id), 1, {}))
		return 0.0
	if sort != "name":
		ids.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ka: float = key.call(String(a))
			var kb: float = key.call(String(b))
			return ka > kb or (is_equal_approx(ka, kb) and _name(String(a)) < _name(String(b))))
	return ids


## Asks before selling one `id` from the stash for `price`.
func ask_sell(id: String, price: int) -> void:
	UiKit.confirm(self, "Sell one %s to the shop for $%s? It leaves the stash for good." % [_name(id), DebriefCalc.money(price)],
		"Sell for $%s" % DebriefCalc.money(price), func() -> void: Economy.sell_from_stash(StringName(id), 1))


## Makes `row` draggable with `data` ({"from": "stash" | "kit" | "worn", "id", "slot"}).
func _draggable(row: Control, data: Dictionary) -> void:
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	row.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var preview := UiKit.cell(_name(String(data.id)))
		preview.theme_type_variation = &"HeadingLabel"
		row.set_drag_preview(preview)
		return {"loadout": data}, Callable(), Callable())


## Makes `column` (and what's in it) take dropped rows for `side` ("kit" or "stash").
func _drop_zone(column: Control, side: String) -> void:
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	# The column and its scroll area (which stops the mouse, so a drop on a row ends there).
	for c: Control in [column] + column.find_children("*", "ScrollContainer", true, false):
		c.set_drag_forwarding(Callable(),
			func(_at: Vector2, d: Variant) -> bool: return can_drop(d, side),
			func(_at: Vector2, d: Variant) -> void: drop(d, side))


## Whether dropped `d` goes somewhere on `side`: a stash row on the kit, a kit or worn row on
## the stash, for someone whose kit you may change.
func can_drop(d: Variant, side: String) -> bool:
	if not (d is Dictionary and d.has("loadout")) or not _person(selected).get("mine", false):
		return false
	var from := String(d.loadout.get("from", ""))
	return (side == "kit" and from == "stash") or (side == "stash" and from in ["kit", "worn"])


## Does a drop: the same request as the row's own button.
func drop(d: Variant, side: String) -> void:
	if not can_drop(d, side):
		return
	var data: Dictionary = d.loadout
	var id := String(data.id)
	match String(data.from):
		"stash":
			var item := ItemDB.get_item(StringName(id))
			var slot := _slot_for(item, gear_of(selected))
			if slot != &"":
				ask("slot", {"slot": String(slot), "id": id})
			elif Optics.is_optic(item):
				ask("optic", {"slot": "primary", "id": id})
			else:
				ask("add", {"id": id, "count": 1})
		"kit":
			ask("remove", {"id": id, "count": 1})
		"worn":
			ask("slot", {"slot": String(data.slot), "id": ""})


## An item's tooltip: its name, and its description and uses when ItemDB has them
## (ItemDB.describe, branch feat/item-info; until it lands the name and type are all there is).
static func item_tooltip(id: String) -> String:
	var item := ItemDB.get_item(StringName(id)) if id != "" else null
	if item == null:
		return ""
	if ItemDB.has_method(&"describe"):
		var d: Variant = ItemDB.call(&"describe", StringName(id))
		if d is Dictionary:
			var parts := PackedStringArray([String(d.get("name", item.name))])
			for key: String in ["desc", "uses"]:
				var v: Variant = d.get(key, "")
				var text := ", ".join(PackedStringArray(v)) if v is Array else String(v)
				if text != "":
					parts.append(text)
			return "\n".join(parts)
	return "%s (%s, %.2f kg)" % [item.name, item.type, item.mass_kg]


## A drop-down whose first entry is its prompt; picking another sends `value` and goes back.
func _picker(node_name: String, choices: Array, on_pick: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name.validate_node_name()
	## As wide as its prompt (the entry it always shows): it was cut at 120 px, with no tooltip.
	picker.fit_to_longest_item = false
	picker.tooltip_text = String(choices[0][0]).trim_suffix("...")
	for c: Array in choices:
		picker.add_item(String(c[0]))
		picker.set_item_metadata(picker.item_count - 1, String(c[1]))
		var id := String(c[1])
		if ItemDB.has_item(StringName(id)):
			picker.set_item_tooltip(picker.item_count - 1, item_tooltip(id))
	picker.select(0)
	picker.item_selected.connect(func(i: int) -> void:
		var v := String(picker.get_item_metadata(i))
		picker.select(0)
		if i > 0 and v != "":
			on_pick.call(v))
	return picker


static func _name(id: String) -> String:
	var item := ItemDB.get_item(StringName(id))
	return item.name if item else id


static func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return _name(String(a)) < _name(String(b)))
	return out


## What the last edit was short of, with a Buy button for all of it (company money, the shop's
## prices, through the host) and one per item; disabled with the reason when funds fall short.
func _build_buy(who: String) -> void:
	var missing: Dictionary = entry_of(who).get("edit_missing", {})
	if missing.is_empty():
		return
	var funds := int(BaseHub.view.get("funds", 0))
	var all := BaseHub.missing_cost(missing)
	doll_box.add_child(UiKit.warn("Short of: " + Restock.list_text(missing)))
	if int(all.units) <= 0:
		doll_box.add_child(UiKit.hint("The shop doesn't sell these."))
		return
	var buy := UiKit.button("Buy missing (%d items, $%d)" % [int(all.units), int(all.cost)], func() -> void: ask("buy_missing"))
	buy.name = "BuyMissing"
	buy.disabled = funds < int(all.cost)
	buy.tooltip_text = "Not enough cash: $%d of $%d" % [funds, int(all.cost)] if buy.disabled else "Buy it all from the shop, then redo the change"
	doll_box.add_child(buy)
	if buy.disabled:
		doll_box.add_child(UiKit.warn("Not enough cash: $%d of the $%d needed." % [funds, int(all.cost)]))
	if missing.size() > 1:
		var row := UiKit.button_row([])
		for id: String in _sorted(missing.keys()):
			var price := BaseEconomy.item_price(StringName(id)) * int(missing[id])
			if price <= 0:
				continue
			var one := UiKit.button("Buy %s x%d ($%d)" % [_name(id), int(missing[id]), price], func() -> void: ask("buy_missing", {"id": id}))
			one.name = "BuyOne_" + id
			one.disabled = funds < price
			row.add_child(one)
		doll_box.add_child(row)
