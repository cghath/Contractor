class_name AmmoReadout
extends Control
## Mags and roughly how full, in the HUD's bottom-right corner (Captain 2026-10-13: "show mags
## and an estimate of ammo in the mags not an exact count"). Kept minimal: the loaded
## magazine's fill in words (FILL_WORDS), a small pip for each spare magazine for the weapon
## in hand (a part-used one dimmer, an empty one hollow), and the grenades carried. Exact
## round counts stay on the inventory screen (Tab).
##
## The inventory keeps each magazine's own rounds (an entry's state "rounds", none for a full
## one), so every pip is that magazine's own estimate. A belt reads the same with "belt" for
## "mag"; a launcher shows the round loaded and how many more are carried (one or two, a count
## is fine); so does the M320 under a rifle with the trigger on it (Underbarrel), and a
## shotgun's tube reads its fill and the shell up next, with the shells carried; grenades are
## a count.

## The fill words, fullest first: a magazine at least this share full gets the word. Above
## nothing it's "Nearly empty"; with no rounds at all "Empty". Proposed thresholds.
const FILL_WORDS: Array = [[0.95, "Full"], [0.65, "Nearly full"], [0.35, "About half"], [0.15, "Low"]]
const NEARLY_EMPTY := "Nearly empty"
const EMPTY := "Empty"
## Pips past this many show as "+n".
const MAX_PIPS := 8
## Sizes and colours (docs/ui_audit.md P1-14: the pips were 4 px wide, the fill word 14 px at
## 75% and the grenade line 12 px at 40%, drawn under the control's own box).
const PIP := Vector2(6, 14)
const PIP_GAP := 3.0
## ui-modern (2026-10-20): the spare and grenade lines were 14 px at 70%; now 16 px at 88%, outlined.
const COLOUR := Color(UiKit.TEXT_BRIGHT, 0.97)
const DIM_COLOUR := Color(UiKit.TEXT, 0.88)
const OUTLINE := UiKit.OUTLINE
## Its box (logical px) in the HUD's bottom-right zone: the pips and fill word over the grenades.
const WIDTH := 280.0
const HEIGHT := 56.0

var player: Soldier
## What's shown (summary()), worked out a few times a second.
var shown: Dictionary = {}
var _refresh := 0.0


func _init(p: Soldier = null) -> void:
	player = p
	name = "AmmoReadout"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -Hud.MARGIN - WIDTH
	offset_right = -Hud.MARGIN
	offset_top = -Hud.MARGIN - HEIGHT
	offset_bottom = -Hud.MARGIN


## The word for a magazine with `rounds` of `full` in it.
static func fill_word(rounds: int, full: int) -> String:
	if rounds <= 0 or full <= 0:
		return EMPTY
	var share := float(rounds) / float(full)
	for step: Array in FILL_WORDS:
		if share >= float(step[0]):
			return String(step[1])
	return NEARLY_EMPTY


## What the readout shows for `s` ({} with nothing to show): "kind" ("mag", "belt",
## "launcher"), "loaded" (the word, or for a launcher the round's name or "Empty"), "spares"
## (each spare's fill share, fullest first; a launcher's spare rounds count as 1.0 each),
## "unit" ("mag", "belt", "round") and "grenades" ({"frag": 2, "smoke": 1}).
static func summary(s: Soldier) -> Dictionary:
	if s == null:
		return {}
	var inv := s.inventory
	var out := {}
	var weapon := s.active_weapon()
	if weapon and Launchers.is_launcher(weapon):
		var w := Launchers.loaded_of(s)
		var spares: Array = []
		for id in Launchers.round_items(weapon):
			for i in inv.count_of(id):
				spares.append(1.0)
		out = {"kind": "launcher", "loaded": Launchers.warhead_name(w) if w != &"" else EMPTY, "spares": spares, "unit": "round"}
	elif weapon and s.underbarrel_up and Shotguns.key_of(s) != null:
		# The trigger on the Skeleton Key under the rifle: its tube, the shell up next, shells carried.
		var key := Shotguns.key_of(s)
		var tube := Shotguns.key_list(key, inv.state_of(s.active_slot))
		var spares: Array = []
		for i in Shotguns.spare_shells(inv, key):
			spares.append(1.0)
		var next := StringName(String(tube.back())) if not tube.is_empty() else &""
		out = {"kind": "tube", "loaded": fill_word(tube.size(), Shotguns.capacity(key)) + (" (%s)" % ItemDB.get_item(next).name.trim_prefix("12 ga ") if next != &"" else ""),
			"spares": spares, "unit": "shell"}
	elif weapon and s.underbarrel_up and Underbarrel.on_gun(s) != null:
		# The trigger on the M320 under the rifle: the grenade in it and the ones carried.
		var w := Underbarrel.loaded_of(s)
		var spares: Array = []
		for id in Launchers.round_items(Underbarrel.on_gun(s)):
			for i in inv.count_of(id):
				spares.append(1.0)
		out = {"kind": "launcher", "loaded": Launchers.warhead_name(w) if w != &"" else EMPTY, "spares": spares, "unit": "grenade"}
	elif Shotguns.is_tube(weapon):
		# A shotgun: how full its tube is, the shell up next, and the shells it takes carried
		# (loose and in its speed loaders).
		var spares: Array = []
		for i in Shotguns.spare_shells(inv, weapon):
			spares.append(1.0)
		var next := Shotguns.next_shell(inv.state_of(s.active_slot))
		var word := fill_word(inv.rounds_in(s.active_slot), Shotguns.capacity(weapon))
		out = {"kind": "tube", "loaded": word + (" (%s)" % ItemDB.get_item(next).name.trim_prefix("12 ga ") if next != &"" else ""),
			"spares": spares, "unit": "shell"}
	elif weapon and weapon.type == "weapon":
		var ammo_id := StringName(weapon.stats.get("ammo", ""))
		if ItemDB.has_item(ammo_id):
			var mag := ItemDB.get_item(ammo_id)
			var full := mag.magazine_rounds()
			var spares: Array = []
			for container in inv.search_containers():
				for entry: Dictionary in inv.containers.get(container, []):
					if entry.id == ammo_id:
						for i in int(entry.get("count", 1)):
							spares.append(clampf(float((entry.get("state", {}) as Dictionary).get("rounds", full)) / maxf(full, 1.0), 0.0, 1.0))
			spares.sort()
			spares.reverse()
			var belt := bool(mag.stats.get("belt", false))
			out = {"kind": "belt" if belt else "mag", "loaded": fill_word(inv.rounds_in(s.active_slot), full), "spares": spares,
				"unit": "belt" if belt else "mag"}
	var grenades := {}
	for container in inv.search_containers():
		for entry: Dictionary in inv.containers.get(container, []):
			var item := ItemDB.get_item(entry.id) if ItemDB.has_item(entry.id) else null
			if item and item.stats.has("throwable"):
				var kind := String(item.stats.throwable)
				grenades[kind] = int(grenades.get(kind, 0)) + int(entry.get("count", 1))
	if not grenades.is_empty():
		out["grenades"] = grenades
	return out


## The readout in words (tests read it): "Nearly full | 4 mags (1 part-used, 1 empty) | 2 frag".
static func text_of(sum: Dictionary) -> String:
	if sum.is_empty():
		return ""
	var parts := PackedStringArray()
	if sum.has("loaded"):
		parts.append(String(sum.loaded))
		var spares: Array = sum.spares
		var unit := String(sum.unit)
		var have := spares.filter(func(f: float) -> bool: return f > 0.0)
		var part := have.filter(func(f: float) -> bool: return f < 0.95)
		var empty := spares.size() - have.size()
		var extra := PackedStringArray()
		if not part.is_empty() and unit != "round":
			extra.append("%d part-used" % part.size())
		if empty > 0:
			extra.append("%d empty" % empty)
		parts.append("%d %s%s%s" % [have.size(), unit, "" if have.size() == 1 else "s", " (%s)" % ", ".join(extra) if not extra.is_empty() else ""])
	var grenades: Dictionary = sum.get("grenades", {})
	if not grenades.is_empty():
		var g := PackedStringArray()
		for kind: String in grenades:
			g.append("%d %s" % [int(grenades[kind]), kind])
		parts.append(", ".join(g))
	return " | ".join(parts)


func text() -> String:
	return text_of(shown) if visible else ""


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.2
	var hud := Hud.of(self)
	var up := player != null and is_instance_valid(player) and player.vitals.is_up()
	var was := shown
	shown = summary(player) if up else {}
	visible = not shown.is_empty() and not (hud and (hud.is_inventory_open() or (hud.map_screen and hud.map_screen.visible)))
	if shown != was:
		queue_redraw()


func _draw() -> void:
	if shown.is_empty():
		return
	var font := UiKit.FONT_STRONG
	var right := size.x
	var y := 4.0  # the pips' top; the word sits on their baseline, the grenades a line under
	var body := UiKit.FONT_HUD_SMALL
	var small := UiKit.FONT_HUD_SMALL
	if shown.has("loaded"):
		# Pips, right to left: fullest on the right; a part-used one dimmer, an empty one hollow.
		var spares: Array = shown.spares
		var x := right
		var n := mini(spares.size(), MAX_PIPS)
		if spares.size() > MAX_PIPS:
			var more := "+%d" % (spares.size() - MAX_PIPS)
			var mw := font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
			x -= mw
			draw_string_outline(font, Vector2(x, y + PIP.y), more, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 3, OUTLINE)
			draw_string(font, Vector2(x, y + PIP.y), more, HORIZONTAL_ALIGNMENT_LEFT, -1, small, DIM_COLOUR)
			x -= PIP_GAP + 2.0
		for i in n:
			var f: float = spares[i]
			x -= PIP.x
			var r := Rect2(Vector2(x, y), PIP)
			draw_rect(r.grow(1.0), Color(0, 0, 0, 0.5), false, 1.0)  # a faint edge, so a pip shows on bright ground
			if f <= 0.0:
				draw_rect(r, DIM_COLOUR, false, 1.0)
			else:
				var c := COLOUR if f >= 0.95 else Color(COLOUR, lerpf(0.4, 0.7, f))
				draw_rect(r, c)
			x -= PIP_GAP
		var word := String(shown.loaded)
		var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, body).x
		var wx := x - 6.0 - ww
		draw_string_outline(font, Vector2(wx, y + PIP.y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, body, 4, OUTLINE)
		draw_string(font, Vector2(wx, y + PIP.y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, body, COLOUR)
	var grenades: Dictionary = shown.get("grenades", {})
	if not grenades.is_empty():
		var g := PackedStringArray()
		for kind: String in grenades:
			g.append("%d %s" % [int(grenades[kind]), kind])
		var line := ", ".join(g)
		var gw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string_outline(font, Vector2(right - gw, y + PIP.y + 22.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 3, OUTLINE)
		draw_string(font, Vector2(right - gw, y + PIP.y + 22.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, small, DIM_COLOUR)
