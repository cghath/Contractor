class_name MapCommandLayer
extends RefCounted
## High command on the map (docs/high_command.md 10, combined_arms.md 5.4): the squad frames, the
## order graphics and the right-click orders, kept out of MapView (which calls draw() and
## add_orders() through one hook each). C4 grows this into the full select > order > place >
## face > confirm flow.
##
## The frame is inspired by APP-6: a rectangle with the infantry cross, the callsign and
## strength beside it ("HAWK 2 4/4"), a CE pip (green, amber, red); the current order is a solid
## line to its point, an order not yet acknowledged dotted, a failed one red with its why.

const FRAME := Vector2(26, 16)
const COLOUR := Color(0.35, 0.75, 1.0)
const ALLIED := Color(0.45, 0.85, 0.5)
const CE_COLOURS := {"green": Color(0.3, 0.85, 0.35), "amber": Color(1.0, 0.75, 0.2), "red": Color(0.95, 0.25, 0.2)}
const FAILED := Color(0.95, 0.3, 0.25)
## The right-click orders on a hero squad (menu text, verb, needs the point).
const ORDERS := [["Move here", "move", true], ["Defend here", "defend", true], ["Attack here", "attack", true],
	["Support by fire on here (from where it is)", "sbf", true], ["Bound here", "bound", true], ["Fall back here", "fall_back", true],
	["Regroup here", "regroup", true], ["Extract here", "extract", true], ["Hold where it is", "hold", false],
	["Follow me", "follow", false], ["Support me", "support", false], ["Report", "report", false], ["Cancel its order", "cancel", false]]
## The go code the next order waits on ("" none; the HC panel sets it, C4's order bar too).
static var next_go := ""


## Draws every high command group on `view` (MapView._draw).
static func draw(view: MapView) -> void:
	var hc := HighCommand.of(view)
	if hc == null:
		return
	for e: Dictionary in hc.view:
		var colour := ALLIED if String(e.get("kind", "")) == "allied" else COLOUR
		var p: Array = e.get("pos", [0, 0])
		var at := view.map_to_screen(Vector2(float(p[0]), float(p[1])))
		var o: Dictionary = e.get("order", {})
		var pts: Array = o.get("points", [])
		if not pts.is_empty() and String(o.get("state", "")) not in ["done", "cancelled"]:
			var line_colour := FAILED if String(o.state) == "failed" else colour
			var last := at
			for q: Variant in pts:
				var to := view.map_to_screen(Vector2(float(q[0]), float(q[1])))
				if String(o.state) == "sent":
					view.draw_dashed_line(last, to, line_colour, 1.5, 3.0)
				else:
					view.draw_line(last, to, line_colour, 2.0)
				last = to
			view.draw_circle(last, 4.0, line_colour)
		for m: Variant in e.get("men", []):
			view.draw_circle(view.map_to_screen(Vector2(float(m[0]), float(m[1]))), 2.0, colour)
		var r := Rect2(at - FRAME * 0.5, FRAME)
		view.draw_rect(r, Color(colour, 0.25))
		view.draw_rect(r, Color(1, 0.3, 0.3) if bool(e.get("contact", false)) else colour, false, 2.0)
		view.draw_line(r.position, r.end, colour, 1.5)
		view.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), colour, 1.5)
		view.draw_circle(r.position + Vector2(r.size.x + 4.0, 0.0), 4.0, CE_COLOURS.get(String(e.get("band", "green")), Color.WHITE))
		var state := String(o.get("verb", "")) + (" (%s)" % o.state if String(o.get("state", "")) not in ["", "active"] else "") if not o.is_empty() else "idle"
		view.call(&"_label", at, "%s %d/%d: %s" % [String(e.callsign).to_upper(), int(e.up), int(e.total), state], colour, "squad", MapView.LABEL_FONT)


## Adds the hero squads' orders to the map's right-click menu `menu` for map point `at`
## (MapView._open_menu). Only the commander gets them. Returns the submenus made.
static func add_orders(view: MapView, menu: PopupMenu, at: Vector2) -> Array[PopupMenu]:
	var made: Array[PopupMenu] = []
	var hc := HighCommand.of(view)
	if hc == null or hc.view.is_empty() or not hc.is_commander():
		return made
	var heroes := hc.view.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "hero")
	if heroes.is_empty():
		return made
	menu.add_separator("High command (%s)" % MapGrid.grid_ref(at, view.area))
	for e: Dictionary in heroes:
		var sub := PopupMenu.new()
		for i in ORDERS.size():
			sub.add_item(String(ORDERS[i][0]), i)
		var id := String(e.id)
		sub.id_pressed.connect(func(i: int) -> void: send(hc, id, String(ORDERS[i][1]), at if bool(ORDERS[i][2]) else Vector2.INF))
		menu.add_child(sub)
		menu.add_submenu_node_item("%s (%d/%d)" % [e.callsign, int(e.up), int(e.total)], sub)
		made.append(sub)
	return made


## Sends `verb` for group `id` at map point `at` (INF: none) through the host's validated path.
static func send(hc: HighCommand, id: String, verb: String, at: Vector2, append := false, facing := Vector2.ZERO) -> void:
	if verb == "cancel":
		hc.request_cancel(id, 0)
		return
	var pts: Array = [[at.x, at.y]] if at.is_finite() else []
	if verb == "sbf" and at.is_finite():
		var e := hc.status(id)
		var p: Array = e.get("pos", [at.x, at.y])
		pts = [[float(p[0]), float(p[1])], [at.x, at.y]]  # from where it is, onto the spot
	var o := HcOrder.make(id, verb, pts)
	if next_go != "" and verb not in ["cancel", "report", "posture"]:
		o.go = next_go
	if facing.length() > 0.01:
		o.facing = [facing.x, facing.y]
	o.id = -1  # the host numbers it
	hc.request_order(o, append)
