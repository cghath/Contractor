class_name ItemInfo
extends RefCounted
## What an item is and what it's for, for any screen (Captain, 2026-10-14: "item descriptions
## plus uses also needed"). Reads ItemDB.describe (data/items.json's "desc" and "uses" with the
## numbers that apply) and gives it back as:
## - tooltip(id): plain text for a Control's tooltip_text (Godot tooltips don't do markup),
##   or apply(control, id) to set it and let the mouse through to show it;
## - bbcode(id): the same with markup, for a RichTextLabel;
## - summary(id): one short line (what it is), for prompts and hints;
## - panel(id) / show_inspect(parent, id): the inspect panel (name, description, uses, numbers)
##   as a Control any screen can add, or put over the middle of `parent` and take away again
##   (hide_inspect). Pure view: nothing here changes anything.

const PANEL_NAME := &"ItemInspect"
const PANEL_W := 420.0
## The kit's colours for the markup (ui-modern, 2026-10-20: it kept the old teal look): the
## name in the accent, the numbers dim. The panel is the theme's (SolidPanel).
static var COL_TITLE := UiKit.ACCENT.to_html(false)
static var COL_MUTED := UiKit.TEXT_DIM.to_html(false)
## An item's rarity (data/items.json "rarity", from the loot work): its word and the colour its
## name is written in. An item without one keeps the accent.
const RARITY := {
	"common": ["Common", Color(0.92, 0.93, 0.89)], "uncommon": ["Uncommon", Color(0.5, 0.8, 0.45)],
	"rare": ["Rare", Color(0.45, 0.68, 0.98)], "very_rare": ["Very rare", Color(0.78, 0.55, 0.98)],
}


## The rarity word for `id` ("Rare"), or "" when it has none.
static func rarity_text(id: StringName) -> String:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	var r: Array = RARITY.get(String(item.stats.get("rarity", "")), []) if item else []
	return String(r[0]) if not r.is_empty() else ""


## The colour `id`'s name is written in: its rarity's, else the accent.
static func name_colour(id: StringName) -> Color:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	var r: Array = RARITY.get(String(item.stats.get("rarity", "")), []) if item else []
	return r[1] if not r.is_empty() else UiKit.ACCENT

const TYPE_NAMES := {
	"weapon": "Weapon", "optic": "Optic", "ammo": "Ammunition", "armor": "Armour", "plate": "Armour plate",
	"pouch": "Pouch", "backpack": "Backpack", "medical": "Medical", "utility": "Utility", "objective": "Objective",
	"salvage": "Salvage", "intel": "Intel", "vehicle": "Vehicle part", "launcher": "Launcher", "consumable": "Consumable", "barter": "Barter",
}
const SLOT_NAMES := {
	"primary": "Primary", "sidearm": "Sidearm", "helmet": "Helmet", "vest": "Carrier", "backpack": "Backpack",
	"plate": "Plate pocket", "side_plate": "Side plate pocket", "launcher": "Launcher",
}
## Wound kinds and care tasks a medical item's "treats" names (WoundModel), in words.
const TREAT_TEXT := {
	"arterial": "arterial bleeds", "junctional": "junctional bleeds", "internal": "internal bleeding",
	"venous": "venous bleeds", "muscle": "muscle wounds", "graze": "grazes", "fracture": "broken bones",
	"chest": "open chest wounds", "rib": "cracked ribs", "pelvis": "broken pelvis", "pain": "pain",
	"airway": "blocked airway", "access": "IV/IO access", "fluids": "blood loss (fluids)",
	"pressure": "slow fluids", "tension": "tension pneumothorax", "epinephrine": "cardiac arrest (with CPR/defib)",
	"wake": "knocked out", "slow_heart": "slow heart", "racing": "racing heart", "defib": "cardiac arrest",
	"cpr": "cardiac arrest", "burn": "burns", "hypothermia": "hypothermia",
}


## The numbers worth showing for `id`, one short line ("3.4 kg · 12 L · $1,400 · Primary slot").
static func stats_text(id: StringName) -> String:
	var info := ItemDB.describe(id)
	if info.is_empty():
		return ""
	var s: Dictionary = info.stats
	var parts := PackedStringArray()
	var rarity := rarity_text(id)
	parts.append(TYPE_NAMES.get(s.type, String(s.type).capitalize()) + (" (%s)" % rarity.to_lower() if rarity != "" else ""))
	if s.has("slot"):
		parts.append("%s slot" % SLOT_NAMES.get(s.slot, String(s.slot).capitalize()))
	parts.append("%s kg" % _num(s.weight))
	parts.append("%s L" % _num(s.volume))
	if s.has("stack"):
		parts.append("stacks of %d" % int(s.stack))
	if s.get("two_handed", false):
		parts.append("carried in both hands")
	if int(s.value) > 0:
		parts.append("$%s" % money(s.value))
	return "  ·  ".join(parts)


## Type-specific numbers, one line each ("Magnification 3.5-10x", "Treats: arterial bleeds").
static func detail_lines(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var info := ItemDB.describe(id)
	if info.is_empty():
		return out
	var s: Dictionary = info.stats
	if s.has("ammo"):
		out.append("Ammunition: %s" % s.ammo)
	if s.has("rounds"):
		out.append("Holds %d rounds" % int(s.rounds))
	if s.has("calibre"):
		out.append("Calibre: %s" % s.calibre)
	if s.has("reload_s"):
		out.append("Reload: %s s" % _num(s.reload_s))
	if s.has("magnification"):
		var low := float(s.magnification)
		out.append("Magnification: %s" % ("%s-%sx" % [_num(low), _num(s.magnification_max)] if s.has("magnification_max") else "%sx" % _num(low)))
	if s.has("rating"):
		out.append("Rating: %s%s" % [s.rating, " (%s)" % s.material if s.has("material") else ""])
	if s.has("fits"):
		out.append("Fits %s carriers" % " and ".join(PackedStringArray(s.fits)))
	if s.has("capacity"):
		out.append("Storage: %s L" % _num(s.capacity))
	if s.has("treats"):
		out.append("Treats: %s" % ", ".join(PackedStringArray(Array(s.treats).map(func(k: String) -> String: return TREAT_TEXT.get(k, k)))))
	if s.has("treat_s"):
		out.append("Time to apply: %s s" % _num(s.treat_s))
	if s.has("contents"):
		var inside := PackedStringArray()
		for item_name: String in s.contents:
			inside.append("%s x%d" % [item_name, int(s.contents[item_name])])
		out.append("Contains: %s" % ", ".join(inside))
	if s.has("fuse_s"):
		out.append("Fuse: %s s" % _num(s.fuse_s))
	return out


## Plain-text tooltip: name, what it is, how to use it, the numbers. "" for an unknown id.
static func tooltip(id: StringName) -> String:
	var info := ItemDB.describe(id)
	if info.is_empty():
		return ""
	var lines := PackedStringArray([info.name])
	if info.desc != "":
		lines.append(info.desc)
	for use: String in info.uses:
		lines.append("- " + use)
	lines.append(stats_text(id))
	return "\n".join(lines)


## The inspect text with RichTextLabel markup.
static func bbcode(id: StringName) -> String:
	var info := ItemDB.describe(id)
	if info.is_empty():
		return ""
	var out := "[b][color=#%s]%s[/color][/b]\n" % [name_colour(id).to_html(false), _escape(info.name)]
	if info.desc != "":
		out += _escape(info.desc) + "\n"
	if not info.uses.is_empty():
		out += "\n[b]Uses[/b]\n"
		for use: String in info.uses:
			out += "• %s\n" % _escape(use)
	var details := detail_lines(id)
	out += "\n[color=#%s]%s" % [COL_MUTED, _escape(stats_text(id))]
	for line in details:
		out += "\n" + _escape(line)
	return out + "[/color]"


## One short line: what it is (the description's first sentence), for prompts and hints.
static func summary(id: StringName) -> String:
	var info := ItemDB.describe(id)
	if info.is_empty():
		return ""
	var desc: String = info.desc
	var stop := desc.find(". ")
	return desc.substr(0, stop + 1) if stop >= 0 else desc


## What it does, for a treatment row or an action: the first use line (or the summary).
static func use_hint(id: StringName) -> String:
	var info := ItemDB.describe(id)
	if info.is_empty():
		return ""
	return String(info.uses[0]) if not info.uses.is_empty() else summary(id)


## Gives `control` the item's tooltip, and lets the mouse reach it so the tooltip shows (a
## Label ignores the mouse by default).
static func apply(control: Control, id: StringName) -> void:
	control.tooltip_text = tooltip(id)
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS


## The inspect panel for `id`: a box with the name, description, uses and numbers. `footer`
## goes under it in small print (how to close it, say). Add it anywhere.
static func panel(id: StringName, footer := "", width := PANEL_W) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = PANEL_NAME
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply(box)
	box.theme_type_variation = &"SolidPanel"
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.custom_minimum_size.x = width
	text.text = bbcode(id) + ("\n\n[color=#%s][i]%s[/i][/color]" % [COL_MUTED, _escape(footer)] if footer != "" else "")
	box.add_child(text)
	box.set_meta(&"item_id", id)
	return box


## Puts the inspect panel for `id` over the middle of `parent` (replacing one already there)
## and returns it.
static func show_inspect(parent: Node, id: StringName, footer := "") -> PanelContainer:
	hide_inspect(parent)
	var box := panel(id, footer)
	parent.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	return box


## Takes away `parent`'s inspect panel, if it has one.
static func hide_inspect(parent: Node) -> void:
	var old := parent.get_node_or_null(NodePath(PANEL_NAME))
	if old:
		parent.remove_child(old)
		old.queue_free()


## The item id `parent`'s inspect panel shows, or &"" with none up.
static func inspected(parent: Node) -> StringName:
	var box := parent.get_node_or_null(NodePath(PANEL_NAME))
	return StringName(box.get_meta(&"item_id", &"")) if box else &""


## Dollars with thousands commas ("1,400").
static func money(amount: Variant) -> String:
	var digits := str(absi(int(amount)))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if int(amount) < 0 else "") + digits + out


## "3.4", "12", "0.25": no trailing zeros.
static func _num(v: Variant) -> String:
	var text := "%.2f" % float(v)
	text = text.rstrip("0").rstrip(".")
	return text if text != "" else "0"


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
