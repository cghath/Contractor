class_name RegionMapView
extends Control
## The region map on the ops desk (docs/linked_zones.md LZ-2): every zone on its cell of the
## region grid (RegionMap), the links between them (each one a crossing on both edges), the base,
## the hot zones, and where the company's contracts are ("marks"). Clicking a zone picks it
## (zone_picked: the ops desk's raid flight takes it). Sized to the width it's given.

signal zone_picked(zone_id: String)

const CELL_H := 52.0
const GAP := 10.0
const FONT_SIZE := 13
const BASE_FILL := Color(0.16, 0.26, 0.36)
const HOT_FILL := Color(0.36, 0.14, 0.12)
const ZONE_FILL := Color(0.15, 0.17, 0.14)
const LINK := Color(0.45, 0.48, 0.42)
## Marks: zone id -> "prep" (the contract in prep), "leg" (its next zone over) or "held".
const MARK_LINES := {"prep": "contract in prep", "leg": "contract: next zone", "held": "contract held"}

var marks := {}
var selected := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, _rows() * (CELL_H + GAP))
	resized.connect(queue_redraw)


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
	return Rect2(Vector2(cell.x * (w + GAP), cell.y * (CELL_H + GAP)), Vector2(w, CELL_H))


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
		var mark := String(marks.get(id, ""))
		var edge := UiKit.ACCENT if mark != "" else LINK
		draw_rect(r, Color.WHITE if id == selected else edge, false, 3.0 if id == selected or mark == "prep" else 1.5)
		var line2 := "The base" if id == RegionMap.BASE else String(MARK_LINES.get(mark, "hot zone" if hot else ""))
		draw_string(font, r.position + Vector2(6, 19), RegionMap.zone_name(id), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, FONT_SIZE, UiKit.TEXT)
		if line2 != "":
			draw_string(font, r.position + Vector2(6, 38), line2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, FONT_SIZE - 2,
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
