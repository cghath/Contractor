class_name RegionMapView
extends Control
## The region map on the ops desk (docs/linked_zones.md LZ-2): every zone on its cell of the
## region grid (RegionMap), the links between them (each one a crossing on both edges), the base,
## the hot zones, and where the company's contracts are ("marks"). Clicking a zone picks it
## (zone_picked: the ops desk's raid flight takes it). Sized to the width it's given. Each cell
## carries its controller's colour down its left side (ZoneControl); "Theatre map" over it opens
## the full world map (WorldMapScreen), where picking a zone picks it here too.

signal zone_picked(zone_id: String)

const CELL_H := 60.0
const GAP := 10.0
const FONT_SIZE := UiKit.FONT_BODY
const SMALL_SIZE := UiKit.FONT_SMALL
## Room over the cells for the Theatre map button.
const HEADER_H := 44.0
const STRIP_W := 6.0
const BASE_FILL := Color(0.16, 0.26, 0.36)
const HOT_FILL := Color(0.36, 0.14, 0.12)
const ZONE_FILL := Color(0.15, 0.17, 0.14)
const LINK := Color(0.45, 0.48, 0.42)
## Marks: zone id -> "prep" (the contract in prep), "leg" (its next zone over) or "held".
const MARK_LINES := {"prep": "contract in prep", "leg": "contract: next zone", "held": "contract held"}

var marks := {}
var selected := ""
var theatre_button: Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, HEADER_H + _rows() * (CELL_H + GAP))
	resized.connect(queue_redraw)
	theatre_button = UiKit.button("Theatre map", open_theatre, "Every zone on one map: who holds it, the fighting, contracts, travel")
	add_child(theatre_button)


## Opens the world map over the base; a zone opened there is picked here.
func open_theatre() -> WorldMapScreen:
	var screen := WorldMapScreen.open_overlay(self)
	if selected != "":
		screen.view.select(selected)
	screen.zone_picked.connect(func(id: String) -> void:
		if id != RegionMap.BASE and is_instance_valid(self):
			pick(id)
		screen.close())
	return screen


static func _cols() -> int:
	var n := 0
	for cell: Vector2i in RegionMap.layout().values():
		n = maxi(n, cell.x + 1)
	return n


static func _rows() -> int:
	var n := 0
	for cell: Vector2i in RegionMap.layout().values():
		n = maxi(n, cell.y + 1)
	return n


## The rectangle of grid cell `cell` at this width.
func cell_rect(cell: Vector2i) -> Rect2:
	var w := maxf((size.x - GAP * (_cols() - 1)) / maxf(_cols(), 1.0), 40.0)
	return Rect2(Vector2(cell.x * (w + GAP), HEADER_H + cell.y * (CELL_H + GAP)), Vector2(w, CELL_H))


## The zone under `at` (local), or "".
func zone_at(at: Vector2) -> String:
	var layout := RegionMap.layout()
	for id: String in layout:
		if cell_rect(layout[id]).has_point(at):
			return id
	return ""


func _draw() -> void:
	var layout := RegionMap.layout()
	var font := get_theme_default_font()
	for id: String in layout:
		for l: Dictionary in RegionMap.links(id):
			if id < String(l.to):
				draw_line(cell_rect(layout[id]).get_center(), cell_rect(layout[String(l.to)]).get_center(), LINK, 2.0)
	for id: String in layout:
		var r := cell_rect(layout[id])
		var hot := String(MissionRegistry.zone(id).get("kind", "")) == "hot"
		draw_rect(r, BASE_FILL if id == RegionMap.BASE else HOT_FILL if hot else ZONE_FILL)
		draw_rect(Rect2(r.position, Vector2(STRIP_W, r.size.y)), ZoneControl.SIDE_COLOURS.get(ZoneControl.side(id), ZoneControl.SIDE_COLOURS.neutral))
		var mark := String(marks.get(id, ""))
		var edge := UiKit.ACCENT if mark != "" else LINK
		draw_rect(r, Color.WHITE if id == selected else edge, false, 3.0 if id == selected or mark == "prep" else 1.5)
		var line2 := "The base" if id == RegionMap.BASE else String(MARK_LINES.get(mark, "hot zone" if hot else ""))
		var left := STRIP_W + 6.0
		draw_string(font, r.position + Vector2(left, 22), RegionMap.zone_name(id), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - left - 6.0, FONT_SIZE, UiKit.TEXT)
		if line2 != "":
			draw_string(font, r.position + Vector2(left, 44), line2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - left - 6.0, SMALL_SIZE,
				UiKit.ACCENT if mark != "" else UiKit.TEXT_DIM)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var id := zone_at(click.position)
		if id != "" and id != RegionMap.BASE:
			pick(id)
			accept_event()


## Selects zone `id` (as a click does).
func pick(id: String) -> void:
	selected = id
	queue_redraw()
	zone_picked.emit(id)
