class_name LoadoutEditor
extends Control
## The 3D loadout editor (claude/loadout-3d; Captain, 2026-10-22: "we never made it 3d like i
## told you to", "with the option just built in to buy what you do not own", "saving custom
## loadouts and applying them to units"). docs/loadout_3d.md has the design.
##
## Left, the soldier full size in 3D (LoadoutPreview): drag turns him, the wheel zooms, 1-5
## focus head, torso, legs, weapons or the whole body, and the markers on him are the slots
## (helmet and its NVG mount, carrier, plate pockets, every MOLLE point, pack, guns with their
## rails and muzzle, pockets). Click one: it lights up and the picker on the right lists
## everything that fits there, owned or not, the unowned ones with their price. Picking puts it
## on him at once (the draft); one that isn't owned also offers "Buy now" for its price.
##
## Changes are a draft until Apply (Enter): the draft is rebuilt from the stash through the host
## (BaseHub "loadout" "template"), so the existing rules all hold (litres, kg, two-handed bulky
## items, plates in pockets: Restock.build). "Buy missing: $X" (B) buys everything the draft
## lacks and applies it. Ctrl+Z undoes, R goes back to what he wears.
##
## Saved kits (KitLibrary, on the roster: saved with the campaign and shared in co-op): name
## and save the draft (Ctrl+S); apply a kit to yourself, one squadmate, a fire team, everyone in
## a role, the squad, or a high command squad, with "buy missing" totalled over all of them.
## The stats panel: weight and load tier, litres, protection by NIJ rating, ammo, mobility.
## The last person, kit and target picked are remembered (SETTINGS) for next time.

signal closed

const SETTINGS := "user://loadout_editor.cfg"
const UNDO_MAX := 60
## The preview's share of the width against the side panel.
const PREVIEW_SHARE := 1.6
const REGION_KEYS := [["1", "head"], ["2", "torso"], ["3", "legs"], ["4", "weapon"], ["5", "all"]]
## What the pockets' picker offers to carry, by Loadouts group.
const CARRY_GROUPS: Array[String] = ["ammo", "medical", "grenades", "other"]
const HELP := [
	"Drag the soldier to turn him, use the wheel to zoom, and 1-5 to focus the head, torso, legs, weapons or the whole body.",
	"Click a marker on him to pick that slot. The list on the right shows everything that fits: what the company owns, and what it can buy with its price.",
	"Picking puts it on him straight away as a draft. Apply (Enter) fits the draft from the stash; Buy missing (B) buys what the stash lacks and applies it.",
	"Save the draft as a named kit (Ctrl+S). Apply a kit to anyone in the squad, a fire team, a role or a high command squad; Buy missing there totals what all of them lack.",
	"Ctrl+Z undoes a change, R goes back to what he wears now. The stats show weight, litres, protection, ammo and how much the load slows him.",
]
const KEYS := [["Drag", "Turn"], ["Wheel", "Zoom"], ["1-5", "Focus"], ["Enter", "Apply"], ["B", "Buy missing"], ["Ctrl+Z", "Undo"],
	["Ctrl+S", "Save kit"], ["Esc", "Close"]]

## Whose kit: "player:<key>" or a member id.
var who := ""
## The kit being built (a Restock template) and what they wear now as one.
var draft: Dictionary = {}
var worn: Dictionary = {}
var undo_stack: Array = []
## The marker picked on the model ("" none).
var slot_key := ""
var preview: LoadoutPreview
var person_pick: OptionButton
var picker_title: Label
var picker_list: VBoxContainer
var offer_box: VBoxContainer
var stats_box: VBoxContainer
var kits_box: VBoxContainer
var status: Label
var apply_button: Button
var buy_button: Button
var undo_button: Button
var picker_query := ""
var kit_selected := ""
var target_selected := "self"
## The draft's shortfall against the stash (KitLibrary.shortfall), kept fresh.
var short: Dictionary = {}
var _seen_hash := 0
var _poll := 0.0
var _gear_hash := 0
## The item just picked that the company doesn't own (the "Buy now" offer), "" none.
var _offer := ""
## A draft sent to the host: the next kit change on the body becomes the draft.
var _applied_pending := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.apply(self)
	var panel := UiKit.panel(true)
	panel.name = "Panel"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	var head := UiKit.header("Loadout", "Kit out a soldier on the model itself: click a slot, pick what goes there, buy what the company lacks.",
		PackedStringArray(HELP), KEYS, false)
	var top := head.get_child(0) as HBoxContainer
	person_pick = OptionButton.new()
	person_pick.name = "Person"
	person_pick.tooltip_text = "Whose kit to edit"
	person_pick.fit_to_longest_item = false
	person_pick.item_selected.connect(func(i: int) -> void: select(String(person_pick.get_item_metadata(i))))
	top.add_child(person_pick)
	var close_button := UiKit.button("Close [Esc]", ask_close, "Close the loadout editor (Esc)")
	close_button.name = "Close"
	top.add_child(close_button)
	root.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = PREVIEW_SHARE
	body.add_child(left)
	preview = LoadoutPreview.new()
	preview.name = "Preview"
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.slot_clicked.connect(pick_slot)
	left.add_child(preview)
	var regions: Array = []
	for pair: Array in REGION_KEYS:
		var region := String(pair[1])
		var b := UiKit.button("%s [%s]" % [LoadoutPreview.REGIONS[region][0], pair[0]], focus_region.bind(region), "Focus the %s (%s)" % [String(LoadoutPreview.REGIONS[region][0]).to_lower(), pair[0]])
		b.name = "Focus_" + region
		regions.append(b)
	left.add_child(UiKit.button_row(regions))
	var side_scroll := ScrollContainer.new()
	side_scroll.name = "Side"
	side_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	side_scroll.add_child(side)
	var pick_section := UiKit.section("Slot", side)
	picker_title = pick_section.get_child(0) as Label
	pick_section.add_child(UiKit.search_field("Search what fits...", func(t: String) -> void:
		picker_query = t.strip_edges().to_lower()
		_build_picker()))
	offer_box = VBoxContainer.new()
	offer_box.name = "Offer"
	pick_section.add_child(offer_box)
	picker_list = VBoxContainer.new()
	picker_list.name = "Picker"
	pick_section.add_child(picker_list)
	stats_box = UiKit.section("Stats", side)
	stats_box.name = "Stats"
	kits_box = UiKit.section("Saved kits", side)
	kits_box.name = "Kits"
	status = UiKit.text("")
	status.name = "Status"
	root.add_child(status)
	undo_button = UiKit.button("Undo [Ctrl+Z]", undo, "Take back the last change (Ctrl+Z)")
	undo_button.name = "Undo"
	var revert := UiKit.button("Revert [R]", revert_draft, "Back to what they wear now (R)")
	revert.name = "Revert"
	var last := UiKit.button("Last applied [L]", restore_last, "The last kit you applied to them (L)")
	last.name = "Last"
	buy_button = UiKit.accent_button("Buy missing [B]", buy_missing, "Buy everything the draft needs that the stash lacks, then fit it (B)")
	buy_button.name = "BuyMissing"
	apply_button = UiKit.accent_button("Apply [Enter]", apply_draft, "Fit the draft from the stash (Enter)")
	apply_button.name = "Apply"
	root.add_child(UiKit.button_row([undo_button, revert, last, buy_button, apply_button], true))
	BaseHub.view_changed.connect(_on_view)
	BaseHub.note.connect(_on_note)
	_load_settings()
	var list := LoadoutScreen.people_of(BaseHub.view, multiplayer.get_unique_id())
	var start := who
	if list.filter(func(p: Dictionary) -> bool: return p.who == start).is_empty():
		start = String(list[0].who) if not list.is_empty() else ""
	select(start)
	apply_button.grab_focus.call_deferred()


func _exit_tree() -> void:
	if BaseHub.view_changed.is_connected(_on_view):
		BaseHub.view_changed.disconnect(_on_view)
	if BaseHub.note.is_connected(_on_note):
		BaseHub.note.disconnect(_on_note)
	_save_settings()


# --- People and the draft ---------------------------------------------------------------------

func person() -> Dictionary:
	for p: Dictionary in LoadoutScreen.people_of(BaseHub.view, multiplayer.get_unique_id()):
		if p.who == who:
			return p
	return {}


## What `w` wears now: a player's body at the hub, else the roster's copy (JSON-safe).
func gear_of(w: String) -> Dictionary:
	var roster: Dictionary = BaseHub.view.get("roster", {})
	if w.begins_with("player:"):
		var lvl := CompoundLevel.current(self)
		var key := w.trim_prefix("player:")
		var keys: Dictionary = BaseHub.view.get("players", {})
		for peer: Variant in keys:
			if String(keys[peer]) == key and lvl and lvl.players:
				var body := lvl.players.get_node_or_null(NodePath(str(int(peer)))) as Soldier
				if body and body.inventory:
					return Roster.json_safe(body.inventory.net_state)
		return roster.get("players", {}).get(key, {}).get("gear", {})
	return roster.get("members", {}).get(w, {}).get("gear", {})


## Edits `w`'s kit: the draft starts as what they wear; the model takes their look.
func select(w: String) -> void:
	who = w
	worn = Loadouts.template_of(gear_of(w))
	draft = worn.duplicate(true)
	undo_stack.clear()
	_offer = ""
	_gear_hash = hash(gear_of(w))
	preview.set_look(_look_of(w))
	_fill_people()
	_changed(false)


func _look_of(w: String) -> Dictionary:
	var look := {}
	var lvl := CompoundLevel.current(self)
	var body: Soldier = null
	if lvl and w.begins_with("player:"):
		var keys: Dictionary = BaseHub.view.get("players", {})
		for peer: Variant in keys:
			if "player:" + String(keys[peer]) == w and lvl.players:
				body = lvl.players.get_node_or_null(NodePath(str(int(peer)))) as Soldier
	elif lvl:
		for s: Node in get_tree().get_nodes_in_group(&"combatants"):
			if s is Soldier and String(s.get_meta(&"roster_id", "")) == w:
				body = s
	if body and body.model:
		return {"variant": body.model.variant, "body": body.model.body, "face": body.model.face, "left_handed": body.left_handed,
			"name_tape": body.person_name.to_upper()}
	var m: Dictionary = BaseHub.view.get("roster", {}).get("members", {}).get(w, {})
	if not m.is_empty():
		look["body"] = String(m.get("body", VoxelArt.MALE))
		look["left_handed"] = bool(m.get("left", false))
		look["name_tape"] = String(m.get("surname", "")).to_upper()
	return look


## A change to the draft: kept for undo, shown on the model, the panels rebuilt.
func edit(next: Dictionary) -> void:
	if hash(next) == hash(draft):
		return
	undo_stack.append(draft)
	if undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()
	draft = next
	_changed(true)


func undo() -> void:
	if undo_stack.is_empty():
		_say("Nothing to undo")
		return
	draft = undo_stack.pop_back()
	_offer = ""
	_changed(true)
	_say("Undone")


func revert_draft() -> void:
	edit(worn.duplicate(true))
	_say("Back to what %s wears" % _who_name())


func restore_last() -> void:
	var cfg := _cfg()
	var t: Variant = cfg.get_value("last_applied", who, null)
	if not t is Dictionary:
		_say("Nothing applied to %s from here yet" % _who_name())
		return
	edit(KitLibrary.clean_template(t))
	_say("The last kit applied to %s, as a draft: Apply [Enter] to fit it" % _who_name())


func dirty() -> bool:
	return hash(Roster.json_safe(draft)) != hash(Roster.json_safe(worn))


## The draft on the model (everything it names, as if the stash had it all) and every panel.
func _changed(_by_hand: bool) -> void:
	preview.show_gear(dressed(draft))
	short = KitLibrary.shortfall([{"gear": gear_of(who), "template": draft}], BaseHub.view.get("stash", []))
	_build_picker()
	_build_stats()
	_build_kits()
	_build_bar()


## `t` worn: built from a pool holding exactly what it names, so nothing is short.
static func dressed(t: Dictionary) -> Dictionary:
	var pool: Array = []
	var counts := Restock.counts(t)
	for id: String in counts:
		pool.append({"id": id, "count": int(counts[id])})
	return Restock.build(t, pool).gear


func _on_view() -> void:
	if not is_node_ready():
		return
	var h := hash(gear_of(who))
	if h != _gear_hash:  # applied, or changed by hand: the draft follows when it had no edits of its own
		_gear_hash = h
		var was_clean := not dirty()
		worn = Loadouts.template_of(gear_of(who))
		if was_clean or _applied_pending:
			draft = worn.duplicate(true)
			_applied_pending = false
	_fill_people()
	_changed(false)



func _on_note(text: String) -> void:
	if text != "":
		_say(text)


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		var h := hash(gear_of(who))
		if h != _gear_hash:
			_on_view()


# --- The slot picker --------------------------------------------------------------------------

func focus_region(region: String) -> void:
	preview.focus(region)
	_save_settings()


## Picks marker `key` on the model ("slot:<slot>", "mount:<slot>:<mount>", "point:<id>",
## "pockets"): it lights up and the picker lists what fits.
func pick_slot(key: String) -> void:
	slot_key = key
	preview.selected = key
	preview.overlay.queue_redraw()
	_offer = ""
	_build_picker()


## The label of what `key` is now: "Helmet: Bump Helmet (Light)".
func slot_label(key: String) -> String:
	var g := dressed(draft)
	var parts := key.split(":")
	match parts[0]:
		"slot":
			var id := String(draft.slots.get(parts[1], ""))
			return "%s: %s" % [Loadouts.SLOT_NAMES.get(StringName(parts[1]), parts[1]), _name(id) if id != "" else "empty"]
		"mount":
			var holder := ItemDB.get_item(StringName(String(draft.slots.get(parts[1], ""))))
			var state: Dictionary = g.get("slot_state", {}).get(parts[1], {})
			var on := GearMounts.on(holder, state, parts[2]) if holder else ""
			return "%s %s: %s" % [_name(String(draft.slots.get(parts[1], ""))), String(GearMounts.NAMES.get(parts[2], parts[2])).to_lower(), _name(on) if on != "" else "nothing"]
		"point":
			var att: Dictionary = draft.molle.get(parts[1], {})
			return "MOLLE point %s: %s" % [parts[1], _name(String(att.get("id", ""))) if not att.is_empty() else "empty"]
		"pockets":
			return "Carried: pockets, carrier and pack"
	return "Click a marker on the soldier"


## The ids that go on `key`, owned or for sale: [id], owned first, then by name.
func choices(key: String) -> Array:
	var parts := key.split(":")
	var out: Array = []
	var g := dressed(draft)
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(g.duplicate(true))
	var point := {}
	if parts[0] == "point":
		for p: Dictionary in inv.attach_points():
			if String(p.id) == parts[1]:
				point = p
	var holder: ItemData = null
	if parts[0] == "mount":
		holder = ItemDB.get_item(StringName(String(draft.slots.get(parts[1], ""))))
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		var ok := false
		match parts[0]:
			"slot":
				var slot := StringName(parts[1])
				ok = Loadouts.fits_slot(item, slot) if not slot in Inventory.WEAPON_SLOTS else item.slot == slot
			"mount":
				ok = holder != null and GearMounts.fits(holder, parts[2], item)
			"point":
				ok = not point.is_empty() and Inventory.is_attachable(item) and Inventory.point_types(point).any(func(t: String) -> bool: return t in item.stats.get("attach", []))
			"pockets":
				ok = Loadouts.group_of(item) in CARRY_GROUPS and item.slot == &"" and not Inventory.is_attachable(item) and item.type != "weapon"
		if ok and (owned(String(id)) > 0 or BaseEconomy.item_price(id) > 0):
			out.append(String(id))
	inv.free()
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := owned(a) > 0
		var ob := owned(b) > 0
		return _name(a) < _name(b) if oa == ob else oa)
	return out


## Units of `id` the company has for this person: the stash's and what they wear.
func owned(id: String) -> int:
	return int(Loadouts.units(BaseHub.view.get("stash", []), [gear_of(who)]).get(id, 0))


func _build_picker() -> void:
	if picker_list == null:
		return
	for c: Node in picker_list.get_children():
		c.queue_free()
	for c: Node in offer_box.get_children():
		c.queue_free()
	picker_title.text = slot_label(slot_key) if slot_key != "" else "Click a marker on the soldier"
	if _offer != "":
		_build_offer(_offer)
	if slot_key == "":
		picker_list.add_child(UiKit.hint("Markers show the slots: the helmet, carrier, plates, pouches, pack, guns, their rails and muzzle. Focus a region (1-5) to see all of its slots."))
		return
	var parts := slot_key.split(":")
	if parts[0] == "pockets":
		_build_carried()
	elif parts[0] != "pockets":
		var off := UiKit.button("None: take it off", func() -> void: choose(""), "Leave this slot empty (Del)")
		off.name = "PickNone"
		picker_list.add_child(off)
	var funds := int(BaseHub.view.get("funds", 0))
	var shown := 0
	for id: String in choices(slot_key):
		if picker_query != "" and not UiKit.matches(_name(id), picker_query):
			continue
		var have := owned(id)
		var price := BaseEconomy.item_price(StringName(id))
		var text := "%s   %s" % [_name(id), ("owned %d" % have) if have > 0 else ("$%d, not owned" % price)]
		var b := UiKit.button(text, choose.bind(id), LoadoutScreen.item_tooltip(id) + ("" if have > 0 else "\nNot owned: picking it offers to buy it ($%d; cash $%d)" % [price, funds]))
		b.name = "Pick_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if have <= 0:
			b.add_theme_color_override(&"font_color", UiKit.TEXT_DIM)
		picker_list.add_child(b)
		shown += 1
	if shown == 0:
		picker_list.add_child(UiKit.hint("Nothing the company owns or can buy fits here%s." % (" that matches the search" if picker_query != "" else "")))


## The draft with `id` on the picked slot ("" empties it). An item the company doesn't own goes
## on too, and the offer to buy it shows over the list.
func choose(id: String) -> void:
	if slot_key == "":
		return
	var parts := slot_key.split(":")
	var next := draft
	match parts[0]:
		"slot":
			next = Loadouts.set_slot(draft, StringName(parts[1]), id)
		"mount":
			next = Loadouts.set_mount(draft, StringName(parts[1]), parts[2], id)
		"point":
			next = Loadouts.set_point(draft, parts[1], id)
		"pockets":
			next = Loadouts.add_units(draft, id, 1) if id != "" else draft
	_offer = id if id != "" and owned(id) <= 0 else ""
	edit(next)
	_say("%s%s" % [slot_label(slot_key), "" if _offer == "" else ": not owned, Buy now or Buy missing [B]"])


## The "Buy now" offer for `id`: its price and the cash, one click.
func _build_offer(id: String) -> void:
	var price := BaseEconomy.item_price(StringName(id))
	var funds := int(BaseHub.view.get("funds", 0))
	offer_box.add_child(UiKit.warn("%s isn't owned: $%d (cash $%d)." % [_name(id), price, funds]))
	var buy := UiKit.accent_button("Buy now: $%d" % price, buy_one.bind(id), "Buy one into the stash; Apply then fits it")
	buy.name = "BuyNow"
	buy.disabled = price <= 0 or funds < price
	if buy.disabled:
		buy.tooltip_text = "Not enough cash: $%d of $%d" % [funds, price] if price > 0 else "Nobody sells it to the company"
	offer_box.add_child(buy)


func buy_one(id: String) -> void:
	BaseHub.request("buy", [id, 1])
	_offer = ""
	_say("Buying %s for $%d..." % [_name(id), BaseEconomy.item_price(StringName(id))])
	_build_picker()


## Carried items (pockets, carrier, pack, pouches) with -1 / +1, and the pocket picker below.
func _build_carried() -> void:
	var counts := Restock.counts(draft)
	var worn_ids: Array = draft.slots.values().map(func(v: Variant) -> String: return String(v))
	for m: Dictionary in draft.molle.values():
		worn_ids.append(String(m.id))
	var ids: Array = counts.keys().filter(func(id: String) -> bool:
		return not id in worn_ids and not id in draft.get("optics", {}).values())
	ids.sort_custom(func(a: String, b: String) -> bool: return _name(a) < _name(b))
	for id: String in ids:
		var less := UiKit.button("-1", func() -> void: edit(Loadouts.remove_units(draft, id, 1).template), "One fewer")
		less.name = "Less_" + id
		var more := UiKit.button("+1", func() -> void: edit(Loadouts.add_units(draft, id, 1)), "One more")
		more.name = "More_" + id
		picker_list.add_child(UiKit.action_row("%s x%d" % [_name(id), int(counts[id])], [less, more]))
	var fill := UiKit.button("Fill ammo", func() -> void: edit(Loadouts.fill_ammo(draft, StringName(person().get("role", Roles.RIFLEMAN)))),
		"Magazines for each gun up to the role kit's count")
	fill.name = "FillAmmo"
	var medic := UiKit.button("Medic kit", func() -> void: edit(Loadouts.medic_kit(draft)), "The medic role's medical items and pouches")
	medic.name = "MedicKit"
	picker_list.add_child(UiKit.button_row([fill, medic]))
	picker_list.add_child(UiKit.hint("Add to what they carry:"))


## Puts `id` on the model as a draft where it goes (the armory's "Fit on me"): its slot, a plate
## pocket, a rail or muzzle of the primary (else the sidearm), the helmet's mount, a free MOLLE
## point it fits, or else carried. Picks that slot, so the picker and the buy offer show.
func fit_item(id: String) -> void:
	var item := ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null
	if item == null:
		return
	var key := "pockets"
	var gear := dressed(draft)
	var slot := LoadoutScreen._slot_for(item, gear)
	if slot != &"":
		key = "slot:" + String(slot)
	elif item.slot in Inventory.WEAPON_SLOTS:
		key = "slot:" + String(item.slot)
	elif Nvg.is_nvg(item):
		key = "mount:helmet:nvg"
	elif Optics.is_optic(item) or Suppressors.is_suppressor(item) or GunAttachments.is_attachment(item):
		for s: String in ["primary", "sidearm", "launcher"]:
			var gun := ItemDB.get_item(StringName(String(draft.slots.get(s, ""))))
			for m: String in ["optic"] + GearMounts.mounts_for(gun):
				if key == "pockets" and gun and GearMounts.fits(gun, m, item):
					key = "mount:%s:%s" % [s, m]
	elif Inventory.is_attachable(item):
		var inv := Inventory.new()
		inv.net_state = GameState.from_json(gear.duplicate(true))
		var point := inv.free_point_for(item)
		inv.free()
		if point != &"":
			key = "point:" + String(point)
	pick_slot(key)
	choose(id)


# --- Stats ------------------------------------------------------------------------------------

func _build_stats() -> void:
	for c in stats_box.get_children().slice(1):
		c.queue_free()
	var st := KitLibrary.stats_of(dressed(draft))
	var tier := int(st.tier)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", UiKit.SPACE_M)
	stats_box.add_child(grid)
	var rows := [
		["Weight", "%.1f kg, %s" % [float(st.kg), Loadouts.tier_name(tier)]],
		["Litres", "%.1f of %.1f L" % [float(st.litres_used), float(st.litres)]],
		["Mobility", "%d%% speed%s" % [roundi(float(st.speed) * 100.0), "" if MovementRules.can_sprint_at(tier) else ", can't sprint"]],
	]
	for p: Array in st.protection:
		rows.append([String(p[0]), "%s (NIJ %s)" % [p[1], p[2]]])
	if st.protection.is_empty():
		rows.append(["Protection", "none"])
	for a: Array in st.ammo:
		rows.append([String(a[0]), "%d mags, %d rounds" % [int(a[1]), int(a[2])]])
	for r: Array in rows:
		var k := UiKit.cell(String(r[0]))
		k.add_theme_color_override(&"font_color", UiKit.TEXT_DIM)
		grid.add_child(k)
		var v := UiKit.cell(String(r[1]))
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(v)
	if tier >= MovementRules.Tier.OVERLOADED:
		stats_box.add_child(UiKit.warn("Overloaded: slow, no sprint. Drop weight before you deploy."))


# --- Saved kits -------------------------------------------------------------------------------

func _build_kits() -> void:
	for c in kits_box.get_children().slice(1):
		c.queue_free()
	var roster: Dictionary = BaseHub.view.get("roster", {})
	var name_edit := LineEdit.new()
	name_edit.name = "KitName"
	name_edit.placeholder_text = "Kit name"
	name_edit.max_length = KitLibrary.NAME_MAX
	name_edit.text = kit_selected
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void: save_kit(name_edit.text))
	var save := UiKit.button("Save [Ctrl+S]", func() -> void: save_kit(name_edit.text), "Save the draft as this kit for everyone in the company (Ctrl+S)")
	save.name = "SaveKit"
	kits_box.add_child(UiKit.action_row("Save the draft as a kit", [name_edit, save]))
	var names := KitLibrary.names(roster)
	if names.is_empty():
		kits_box.add_child(UiKit.hint("No saved kits yet. Saved kits go with the campaign and every player sees them."))
		return
	if not kit_selected in names:
		kit_selected = names[0]
	var kit_options: Array = names.map(func(n: String) -> Array: return [n, n])
	var kit_pick := UiKit.picker(kit_options, func(n: Variant) -> void:
		kit_selected = String(n)
		_save_settings()
		_build_kits(), "Which saved kit", kit_selected)
	kit_pick.name = "KitPick"
	var load_button := UiKit.button("Edit", func() -> void:
		edit(KitLibrary.template_of_kit(roster, kit_selected).duplicate(true))
		_say("Kit \"%s\" as the draft" % kit_selected), "Put this kit on the model as the draft")
	load_button.name = "LoadKit"
	var delete := UiKit.danger_button("Delete", func() -> void:
		UiKit.confirm(self, "Delete the saved kit \"%s\" for everyone?" % kit_selected, "Delete", func() -> void:
			BaseHub.request("loadout", [who, "kit_delete", {"name": kit_selected}]))
		, "Delete this saved kit (asks first)")
	delete.name = "DeleteKit"
	kits_box.add_child(UiKit.action_row("Kit", [kit_pick, load_button, delete]))
	var targets: Array = [["self", "%s only" % _who_name()]]
	targets.append_array(KitLibrary.target_choices(roster, BaseHub.view.get("prep", {}).get("squad", [])))
	if targets.filter(func(t: Array) -> bool: return String(t[0]) == target_selected).is_empty():
		target_selected = "self"
	var target_pick := UiKit.picker(targets, func(t: Variant) -> void:
		target_selected = String(t)
		_save_settings()
		_build_kits(), "Who gets the kit", target_selected)
	target_pick.name = "TargetPick"
	var whos := kit_targets()
	var total := kit_shortfall()
	var funds := int(BaseHub.view.get("funds", 0))
	var apply := UiKit.accent_button("Apply to %d" % whos.size(), func() -> void: apply_kit(false), "Fit the kit on them from the stash (what it lacks is named)")
	apply.name = "ApplyKit"
	apply.disabled = whos.is_empty()
	var buy := UiKit.accent_button("Buy missing: $%d" % int(total.cost), func() -> void: apply_kit(true),
		"Buy what all %d of them lack (%d items), then fit the kit" % [whos.size(), int(total.units)])
	buy.name = "BuyKitMissing"
	buy.disabled = whos.is_empty() or int(total.units) <= 0 or funds < int(total.cost)
	if int(total.units) > 0 and funds < int(total.cost):
		buy.tooltip_text = "Not enough cash: $%d of $%d" % [funds, int(total.cost)]
	kits_box.add_child(UiKit.action_row("Apply to", [target_pick, apply, buy]))
	if int(total.units) > 0:
		kits_box.add_child(UiKit.hint("The stash lacks %s for all %d: $%d." % [Restock.list_text(total.missing), whos.size(), int(total.cost)]))


## The people the picked target means now (who-ids).
func kit_targets() -> Array[String]:
	if target_selected == "self":
		var one: Array[String] = [who]
		return one
	return KitLibrary.resolve(BaseHub.view.get("roster", {}), BaseHub.view.get("prep", {}).get("squad", []), [target_selected])


## What the picked kit lacks for everyone the target means, all told (KitLibrary.shortfall).
func kit_shortfall() -> Dictionary:
	var t := KitLibrary.template_of_kit(BaseHub.view.get("roster", {}), kit_selected)
	if t.is_empty():
		return {"missing": {}, "cost": 0, "units": 0}
	var jobs: Array = kit_targets().map(func(w: String) -> Dictionary: return {"gear": gear_of(w), "template": t})
	return KitLibrary.shortfall(jobs, BaseHub.view.get("stash", []))


func save_kit(kit_name: String) -> void:
	var n := KitLibrary.clean_name(kit_name)
	if n == "":
		_say("Name the kit first")
		return
	var send := func() -> void:
		kit_selected = n
		BaseHub.request("loadout", [who, "kit_save", {"name": n, "template": Roster.json_safe(draft)}])
		_say("Saving kit \"%s\"..." % n)
	if n in KitLibrary.names(BaseHub.view.get("roster", {})):
		UiKit.confirm(self, "Replace the saved kit \"%s\" with this draft?" % n, "Replace", send, false)
	else:
		send.call()


func apply_kit(buy: bool) -> void:
	var to: Array = [who] if target_selected == "self" else [target_selected]
	BaseHub.request("loadout", [who, "kit_apply", {"name": kit_selected, "to": to, "buy": buy}])
	_applied_pending = true
	_say("Applying \"%s\"%s..." % [kit_selected, " and buying what's missing" if buy else ""])


# --- Apply and buy ----------------------------------------------------------------------------

func _build_bar() -> void:
	var funds := int(BaseHub.view.get("funds", 0))
	undo_button.disabled = undo_stack.is_empty()
	apply_button.disabled = not dirty()
	var units := int(short.get("units", 0))
	buy_button.text = "Buy missing: $%d [B]" % int(short.get("cost", 0)) if units > 0 else "Buy missing [B]"
	buy_button.disabled = units <= 0 or funds < int(short.get("cost", 0))
	buy_button.tooltip_text = ("Not enough cash: $%d of $%d" % [funds, int(short.cost)]) if units > 0 and funds < int(short.cost) \
		else ("Buy %s, then fit the draft (B)" % Restock.list_text(short.get("missing", {})) if units > 0 else "The stash has everything the draft needs")
	if units > 0 and status.text == "":
		_say("The stash lacks %s ($%d)" % [Restock.list_text(short.missing), int(short.cost)])


func apply_draft() -> void:
	if not dirty():
		_say("Nothing changed to apply")
		return
	_send_draft(false)


func buy_missing() -> void:
	if int(short.get("units", 0)) <= 0:
		_say("The stash has everything the draft needs")
		return
	_send_draft(true)


func _send_draft(buy: bool) -> void:
	var t: Dictionary = Roster.json_safe(draft)
	BaseHub.request("loadout", [who, "template", {"template": t, "buy": buy}])
	var cfg := _cfg()
	cfg.set_value("last_applied", who, t)
	cfg.save(SETTINGS)
	_applied_pending = true
	_say("Fitting the kit%s..." % (" after buying what's missing" if buy else ""))


# --- Keys, closing, settings ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		if is_visible_in_tree() and event.is_action_pressed(&"pause"):
			get_viewport().set_input_as_handled()
			ask_close()
		return
	if find_child("Confirm", false, false) != null:
		return  # the confirm box has the keys
	var k := event as InputEventKey
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if k.ctrl_pressed and k.keycode == KEY_Z:
		undo()
	elif k.ctrl_pressed and k.keycode == KEY_S:
		var edit_box := find_child("KitName", true, false) as LineEdit
		save_kit(edit_box.text if edit_box else kit_selected)
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not typing and not get_viewport().gui_get_focus_owner() is Button:
		apply_draft()
	elif typing:
		return
	elif k.keycode == KEY_B:
		buy_missing()
	elif k.keycode == KEY_R:
		revert_draft()
	elif k.keycode == KEY_L:
		restore_last()
	elif k.keycode == KEY_DELETE and slot_key != "" and not slot_key.begins_with("pockets"):
		choose("")
	elif k.keycode >= KEY_1 and k.keycode <= KEY_5:
		focus_region(String(REGION_KEYS[k.keycode - KEY_1][1]))
	else:
		return
	get_viewport().set_input_as_handled()


## Closes, asking first when the draft has changes not applied.
func ask_close() -> void:
	if dirty() and not _applied_pending:
		UiKit.confirm(self, "Close without applying the changes to %s's kit?" % _who_name(), "Close", close)
	else:
		close()


func close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg


func _load_settings() -> void:
	var cfg := _cfg()
	who = String(cfg.get_value("editor", "who", ""))
	kit_selected = String(cfg.get_value("editor", "kit", ""))
	target_selected = String(cfg.get_value("editor", "target", "self"))
	preview.focus(String(cfg.get_value("editor", "region", "all")))


func _save_settings() -> void:
	if preview == null:
		return
	var cfg := _cfg()
	cfg.set_value("editor", "who", who)
	cfg.set_value("editor", "kit", kit_selected)
	cfg.set_value("editor", "target", target_selected)
	cfg.set_value("editor", "region", preview.region)
	cfg.save(SETTINGS)


func _fill_people() -> void:
	person_pick.clear()
	var list := LoadoutScreen.people_of(BaseHub.view, multiplayer.get_unique_id())
	for p: Dictionary in list:
		person_pick.add_item("%s (%s)" % [p.name, Roles.display_name(StringName(p.role))])
		person_pick.set_item_metadata(person_pick.item_count - 1, String(p.who))
		person_pick.set_item_disabled(person_pick.item_count - 1, not bool(p.get("mine", false)))
		if p.who == who:
			person_pick.select(person_pick.item_count - 1)


func _who_name() -> String:
	var p := person()
	return String(p.get("name", "them")) if not p.is_empty() else "them"


func _say(text: String) -> void:
	status.text = text


static func _name(id: String) -> String:
	var item := ItemDB.get_item(StringName(id)) if id != "" and ItemDB.has_item(StringName(id)) else null
	return item.name if item else id
