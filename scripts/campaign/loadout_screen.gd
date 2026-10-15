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
## Keyboard: Tab / arrows move between the controls, Enter presses, Esc closes.

signal closed

## The columns' share of the width (people, doll, stash).
const RATIOS := [1.0, 2.0, 1.4]
const MARGIN := 16
const COL_HEAD := Color("ffd35a")
const COL_SHORT := Color(1.0, 0.75, 0.4)
const COL_DIM := Color(0.7, 0.7, 0.7)
## How often the selected person's kit is looked at for changes made by hand (seconds).
const POLL_S := 0.5

## The person shown: a member id or "player:<key>".
var selected := ""
var people_box: VBoxContainer
var doll_box: VBoxContainer
var stash_box: VBoxContainer
var columns: Array[Control] = []
var status: Label
var _poll := 0.0
var _seen_hash := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := PanelContainer.new()
	panel.name = "Panel"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	margin.add_child(root)
	var top := HBoxContainer.new()
	var title := _label("Loadouts: kit yourself and your squad from the stash", COL_HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := _button("Close (Esc)", close)
	close_button.name = "Close"
	top.add_child(close_button)
	root.add_child(top)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	root.add_child(body)
	people_box = _column(body, "People", RATIOS[0])
	doll_box = _column(body, "Kit", RATIOS[1])
	stash_box = _column(body, "Stash", RATIOS[2])
	status = _label("", COL_SHORT)
	status.name = "Status"
	root.add_child(status)
	BaseHub.view_changed.connect(refresh)
	BaseHub.note.connect(_on_note)
	BaseHub.request("loadout", ["", "sync", {}])  # the muster line's gear into the roster's copy
	refresh()


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
		people_box.add_child(_wrap("Nobody here: the menu works at the FOB, between deployments."))
		return
	var picked: Array = BaseHub.view.get("prep", {}).get("squad", [])
	for p: Dictionary in list:
		var gear := gear_of(String(p.who))
		var load := Loadouts.load_of(gear)
		var b := _button("%s  %s\n%.1f kg %s%s" % [p.name, Roles.short_name(p.role), float(load.kg), Loadouts.tier_name(int(load.tier)),
			"  (short)" if not Roster.restock_short_of(entry_of(String(p.who))).is_empty() else ""], func() -> void: select(String(p.who)))
		b.name = "Person_" + String(p.who).validate_node_name()
		b.toggle_mode = true
		b.clip_text = true  # the column can be narrow (1280x720 at UI scale 1.5)
		b.set_pressed_no_signal(p.who == selected)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		people_box.add_child(b)
	if picked.is_empty():
		people_box.add_child(_wrap("Nobody picked for the next deployment yet: everyone at the muster line is listed.", COL_DIM))


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
	doll_box.add_child(_label("%s, %s" % [p.name, Roles.display_name(p.role)], COL_HEAD))
	doll_box.add_child(_wrap("Load %.1f kg: %s (movement: %s)" % [float(load.kg), Loadouts.tier_name(int(load.tier)), _tier_hint(int(load.tier))]))
	if not editable:
		doll_box.add_child(_wrap("View only: other players set their own kit (you can give them items).", COL_DIM))
	if editable:
		_build_buy(who)
	var stash: Array = BaseHub.view.get("stash", [])
	var have := BaseArmory.counts(stash)
	# Worn: each slot with what the stash has for it.
	doll_box.add_child(_heading("Worn"))
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
				row.get_meta(&"flow").add_child(_picker("Swap_" + String(slot), choices, func(v: String) -> void:
					ask("slot", {"slot": String(s), "id": "" if v == "-" else v})))
			if item and Optics.has_rail(item):
				var optics: Array = [["Optic...", ""], ["Irons (optic to stash)", "-"]]
				for sid: String in _sorted(have.keys()):
					if Optics.is_optic(ItemDB.get_item(StringName(sid))):
						optics.append(["%s (x%d)" % [ItemDB.get_item(StringName(sid)).name, int(have[sid])], sid])
				var s2 := slot
				row.get_meta(&"flow").add_child(_picker("Optic_" + String(slot), optics, func(v: String) -> void:
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
		doll_box.add_child(_heading(Loadouts.GROUP_NAMES[group]))
		for id: String in ids:
			var row := _row("%s x%d" % [_name(id), int(carried[id])], id)
			if editable:
				var flow: HFlowContainer = row.get_meta(&"flow")
				var minus := _button("-1", func() -> void: ask("remove", {"id": id, "count": 1}))
				minus.name = "Remove_" + id
				minus.tooltip_text = "One back to the stash"
				flow.add_child(minus)
				if not others.is_empty():
					var to: Array = [["Give 1 to...", ""]]
					for o: Dictionary in others:
						to.append([String(o.name), String(o.who)])
					flow.add_child(_picker("Give_" + id, to, func(v: String) -> void: ask("give", {"id": id, "count": 1, "to": v})))
			doll_box.add_child(row)
	if carried.is_empty():
		doll_box.add_child(_wrap("Carrying nothing else.", COL_DIM))
	if not editable:
		return
	# Helpers.
	doll_box.add_child(_heading("Quick kit (from the stash)"))
	var helpers := _flow()
	var fill := _button("Fill ammo", func() -> void: ask("fill_ammo"))
	fill.name = "FillAmmo"
	fill.tooltip_text = "Each gun's magazines up to the role kit's count (full ones from the stash first)"
	helpers.add_child(fill)
	var medic := _button("Medic kit", func() -> void: ask("medic_kit"))
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
	doll_box.add_child(_heading("Standing loadout (what Restock refills to)"))
	var entry := entry_of(who)
	var standing := Roster.loadout_of(entry)
	var n := 0
	for c: Variant in Restock.counts(standing).values():
		n += int(c)
	doll_box.add_child(_wrap("%d items saved" % n if n > 0 else "None yet: save this kit, pick a role kit, or deploy (the kit you deploy in is written down)."))
	var short := Roster.restock_short_of(entry)
	if not short.is_empty():
		doll_box.add_child(_wrap("Short after the last restock: " + Restock.list_text(short), COL_SHORT))
	var standing_row := _flow()
	var save := _button("Save as standing", func() -> void: ask("save"))
	save.name = "SaveStanding"
	standing_row.add_child(save)
	var role_standing: Array = [["Standing = role kit...", ""]]
	for role in Roles.ids():
		role_standing.append([Roles.display_name(role), String(role)])
	standing_row.add_child(_picker("StandingRole", role_standing, func(v: String) -> void: ask("standing_role", {"role": v})))
	var squad: Array = others.filter(func(o: Dictionary) -> bool: return not o.player)
	if not squad.is_empty() and n > 0:
		var copy := _button("Copy standing to squad", func() -> void:
			ask("copy_standing", {"to": squad.map(func(o: Dictionary) -> String: return String(o.who))}))
		copy.name = "CopyStanding"
		copy.tooltip_text = "Give every listed squadmate this standing loadout (Restock then draws it for them)"
		standing_row.add_child(copy)
	var restock := _button("Restock to standing", func() -> void: ask("restock"))
	restock.name = "RestockStanding"
	restock.disabled = n == 0
	standing_row.add_child(restock)
	doll_box.add_child(standing_row)


func _build_stash(p: Dictionary) -> void:
	var stash: Array = BaseHub.view.get("stash", [])
	var have := BaseArmory.counts(stash)
	if have.is_empty():
		stash_box.add_child(_wrap("The stash is empty: buy at the shop, or bring kit back.", COL_DIM))
		return
	var editable: bool = not p.is_empty() and p.mine
	if not p.is_empty():
		stash_box.add_child(_wrap("Onto %s:" % p.name, COL_DIM))
	for group in Loadouts.GROUPS:
		var ids: Array = _sorted(have.keys()).filter(func(id: String) -> bool: return Loadouts.group_of(ItemDB.get_item(StringName(id))) == group)
		if ids.is_empty():
			continue
		stash_box.add_child(_heading(Loadouts.GROUP_NAMES[group]))
		for id: String in ids:
			var row := _row("%s x%d" % [_name(id), int(have[id])], id)
			if editable:
				var flow: HFlowContainer = row.get_meta(&"flow")
				var item := ItemDB.get_item(StringName(id))
				var slot := _slot_for(item, gear_of(selected))
				if slot != &"":
					var wear := _button("Wear", func() -> void: ask("slot", {"slot": String(slot), "id": id}))
					wear.name = "Wear_" + id
					flow.add_child(wear)
				elif Optics.is_optic(item):
					var mount := _button("Mount", func() -> void: ask("optic", {"slot": "primary", "id": id}))
					mount.name = "Mount_" + id
					mount.tooltip_text = "On the primary"
					flow.add_child(mount)
				else:
					var one := _button("+1", func() -> void: ask("add", {"id": id, "count": 1}))
					one.name = "Add_" + id
					flow.add_child(one)
					if group in ["ammo", "medical", "grenades"] and int(have[id]) > 1:
						var bulk := _button("+%d" % Loadouts.BULK, func() -> void: ask("add", {"id": id, "count": Loadouts.BULK}))
						bulk.name = "AddBulk_" + id
						flow.add_child(bulk)
			stash_box.add_child(row)
	var inside := BaseArmory.contents_counts(stash)
	if not inside.is_empty():
		var n := 0
		for c: Variant in inside.values():
			n += int(c)
		stash_box.add_child(_wrap("Plus %d items on the stash's carriers and packs and in their pouches (drawn when needed)." % n, COL_DIM))


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

func _column(parent: HBoxContainer, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = title
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	columns.append(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label(title, COL_HEAD))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


## A row: its text (wrapping) and a flow of controls under it (meta "flow").
func _row(text: String, id: String) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	var label := _wrap(text)
	label.tooltip_text = item_tooltip(id)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var flow := _flow()
	row.add_child(flow)
	row.set_meta(&"flow", flow)
	return row


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


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 4)
	flow.add_theme_constant_override(&"v_separation", 4)
	return flow


## A drop-down whose first entry is its prompt; picking another sends `value` and goes back.
func _picker(node_name: String, choices: Array, on_pick: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name.validate_node_name()
	picker.clip_text = true
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = 120
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


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _label(text: String, colour := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.custom_minimum_size.x = 40
	if colour != Color.WHITE:
		label.add_theme_color_override(&"font_color", colour)
	return label


func _wrap(text: String, colour := Color.WHITE) -> Label:
	var label := _label(text, colour)
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _heading(text: String) -> Label:
	return _label(text, COL_HEAD)


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
	doll_box.add_child(_wrap("Short of: " + Restock.list_text(missing), COL_SHORT))
	if int(all.units) <= 0:
		doll_box.add_child(_wrap("The shop doesn't sell these.", COL_DIM))
		return
	var buy := _button("Buy missing (%d items, $%d)" % [int(all.units), int(all.cost)], func() -> void: ask("buy_missing"))
	buy.name = "BuyMissing"
	buy.disabled = funds < int(all.cost)
	buy.tooltip_text = "Not enough cash: $%d of $%d" % [funds, int(all.cost)] if buy.disabled else "Buy it all from the shop, then redo the change"
	doll_box.add_child(buy)
	if buy.disabled:
		doll_box.add_child(_wrap("Not enough cash: $%d of the $%d needed." % [funds, int(all.cost)], COL_SHORT))
	if missing.size() > 1:
		var row := _flow()
		for id: String in _sorted(missing.keys()):
			var price := BaseEconomy.item_price(StringName(id)) * int(missing[id])
			if price <= 0:
				continue
			var one := _button("Buy %s x%d ($%d)" % [_name(id), int(missing[id]), price], func() -> void: ask("buy_missing", {"id": id}))
			one.name = "BuyOne_" + id
			one.disabled = funds < price
			row.add_child(one)
		doll_box.add_child(row)
