class_name ArmorReadout
extends Control
## Armor and helmet condition at a glance (Captain, 2026-10-16: "we need armor helmet condition
## indicators"), in the HUD's bottom-right corner over the AmmoReadout: one row per piece worn
## (front, back, side plates, helmet), its name and rating, a bar of what's left (GearRig
## armor_integrity: green, amber under WARN, red under BAD) and its percent, a ceramic plate's
## cracks, or BROKEN when it's shattered. Nothing worn: nothing drawn.

const WARN := 0.6
const BAD := 0.3
const GOOD_COLOUR := Color("7fc77a")
const WARN_COLOUR := Color("e0b44a")
const BAD_COLOUR := Color("e0574a")
const COLOUR := Color(UiKit.TEXT, 0.95)
const DIM_COLOUR := Color(UiKit.TEXT, 0.7)
const OUTLINE := Color(0, 0, 0, 0.7)
const ROW := 22.0
const BAR := Vector2(70, 7)
const NAME_W := 104.0
const WIDTH := 280.0
const MAX_ROWS := 5
const REFRESH_S := 0.25

var player: Soldier
## What's shown: [{"name", "rating", "left" (0..1), "cracks", "broken"}], refreshed REFRESH_S.
var shown: Array = []
var _refresh := 0.0


func _init(p: Soldier = null) -> void:
	player = p
	name = "ArmorReadout"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	var height := ROW * MAX_ROWS
	offset_left = -Hud.MARGIN - WIDTH
	offset_right = -Hud.MARGIN
	offset_bottom = -Hud.MARGIN - AmmoReadout.HEIGHT - 8.0
	offset_top = offset_bottom - height


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_S
	var now := rows(player)
	if now != shown:
		shown = now
		queue_redraw()


## The pieces `p` wears and their condition, front plate first, helmet last.
static func rows(p: Soldier) -> Array:
	var out: Array = []
	if p == null or not is_instance_valid(p) or p.gear == null:
		return out
	for slot: StringName in GearRig.ARMOR_SLOTS:
		var left := p.gear.armor_integrity(slot)
		if left < 0.0:
			continue
		var item := ItemDB.get_item(p.inventory.slots.get(slot, &""))
		var state := p.inventory.state_of(slot)
		out.append({"name": GearRig.ARMOR_SLOTS[slot], "rating": ArmorRules.rating(item) if item else "",
			"left": clampf(left, 0.0, 1.0), "cracks": ArmorRules.cracks(state).size(), "broken": ArmorRules.is_shattered(state)})
	return out


static func colour_for(left: float, broken: bool) -> Color:
	if broken or left < BAD:
		return BAD_COLOUR
	return WARN_COLOUR if left < WARN else GOOD_COLOUR


func _draw() -> void:
	if shown.is_empty():
		return
	var font := get_theme_default_font()
	var fs := UiKit.FONT_BODY
	var y := size.y - ROW * shown.size()
	for row: Dictionary in shown:
		var base := y + ROW * 0.75
		var label := "%s %s" % [row.name, row.rating]
		var x := size.x - NAME_W - BAR.x - 56.0
		draw_string_outline(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, NAME_W, fs, 3, OUTLINE)
		draw_string(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, NAME_W, fs, COLOUR)
		var bar := Rect2(Vector2(x + NAME_W, base - BAR.y - 2.0), BAR)
		var tint := colour_for(row.left, row.broken)
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(BAR.x * (0.0 if row.broken else float(row.left)), BAR.y)), tint)
		var tail := "BROKEN" if row.broken else "%d%%%s" % [roundi(float(row.left) * 100.0), (" %dx" % row.cracks) if int(row.cracks) > 0 else ""]
		draw_string_outline(font, Vector2(bar.end.x + 6.0, base), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, OUTLINE)
		draw_string(font, Vector2(bar.end.x + 6.0, base), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint if row.broken or row.left < WARN else DIM_COLOUR)
		y += ROW
