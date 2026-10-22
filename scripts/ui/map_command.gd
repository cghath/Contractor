class_name MapCommandLayer
extends RefCounted
## High command on the map (docs/high_command.md 10, combined_arms.md 5.4): the squad frames, the
## order graphics and the one flow for every order, kept out of MapView (which hands it its
## input first and calls draw(); one hook each).
##
## The flow (5.4.1): Select (click a frame, Shift adds, drag a box, 1-4, ] cycles) > Order (the
## order bar's buttons, each with its key and a tooltip; the contextual ones first; Space repeats
## the last) > Place (a ghost follows the cursor and says what's wrong: "off the map") > Face
## (drag from the point; a plain click keeps the default) > Confirm (release: the ghost turns
## dotted until the host's "copy", then the squad's order line; a refusal flashes red with its
## reason). Shift queues, right-click cancels the placing, Backspace cancels the selected squads'
## orders, Ctrl+Z undoes the last order within 10 s if it hasn't started. Tab turns command mode
## off and on. Place gun (G) draws the cone of fire (Viewshed: what the gun sees, dead ground
## hatched, a crest within 30 m red) and range rings; the wheel widens or narrows the arc.
##
## The frame is inspired by APP-6: a rectangle with the infantry cross, the callsign and strength
## beside it, a CE pip; the current order a solid line to its point, one not yet acknowledged
## dotted, a failed one red.

const FRAME := Vector2(26, 16)
const COLOUR := Color(0.35, 0.75, 1.0)
const ALLIED := Color(0.45, 0.85, 0.5)
const SELECTED := Color(1.0, 0.9, 0.3)
const GHOST := Color(1.0, 1.0, 1.0, 0.85)
const BAD := Color(0.95, 0.3, 0.25)
const SEEN := Color(0.3, 0.9, 0.35, 0.22)
const DEAD := Color(0.05, 0.05, 0.05, 0.35)
const CE_COLOURS := {"green": Color(0.3, 0.85, 0.35), "amber": Color(1.0, 0.75, 0.2), "red": Color(0.95, 0.25, 0.2)}
const FAILED := Color(0.95, 0.3, 0.25)
## The order bar: [verb, label, key, needs a point, tooltip].
const BAR := [
	["move", "Move", KEY_M, true, "Move there; drag to set the facing"],
	["defend", "Defend", KEY_D, true, "Hold the ground there: garrison a building, else a line; drag for the facing"],
	["attack", "Attack", KEY_A, true, "Take the objective: an attack position, then in"],
	["sbf", "Support by fire", KEY_S, true, "Click where it fires from, then the target"],
	["bound", "Bound", KEY_B, true, "Bound there by pairs"],
	["fall_back", "Fall back", KEY_F, true, "Break contact by pairs back to there"],
	["defend_frontage", "Frontage", KEY_W, true, "Drag the frontage to defend: a sector per buddy pair"],
	["hold", "Hold", KEY_H, false, "Stop and hold where it is"],
	["regroup", "Regroup", KEY_R, true, "Gather there, treat and cross-load"],
	["extract", "Extract", KEY_X, true, "Go to the extraction point there and hold inside"],
	["follow", "Follow me", KEY_Y, false, "Keep station 30-60 m off you"],
	["gun", "Place gun", KEY_G, true, "Place the squad's gun: drag its facing, the wheel widens or narrows the arc"],
]
const DRAG_PX := 8.0
## Gun placement (5.4.2): arc default and limits; the cone is recast at most this often.
const ARC_DEFAULT := 60.0
const ARC_MIN := 20.0
const ARC_MAX := 120.0
const CONE_EVERY_MS := 100
## Undo window (shown in the help line; the host enforces it).
const UNDO_S := 10.0

## The go code the next order waits on ("" none; the HC panel sets it).
static var next_go := ""

var view: MapView
var on := true
var selected := PackedStringArray()
var placing := ""
var last_verb := ""
var arc_deg := ARC_DEFAULT
## Client: orders sent and not yet acknowledged, by squad: {"verb", "point": Vector2, "at": msec, "seen_ack": bool}.
var pending := {}
var _press := Vector2.INF  # where the placing click went down (map)
var _press_screen := Vector2.INF
var _first := Vector2.INF  # SBF's firing position (the first click)
var _box := Vector2.INF  # a box select's start (screen)
var _cursor := Vector2.ZERO  # map
var _cone := {}
var _cone_ms := 0
var _cone_key := ""
var _last_order_squad := ""
var _last_first: Array[String] = []
var _flash := ""
var _flash_until := 0
var _bar: PanelContainer
var _bar_title: Label
var _bar_buttons: HFlowContainer
var _bar_help: Label


func _init(p_view: MapView = null) -> void:
	view = p_view


## The order bar under the map (built once; MapView calls this from its _ready).
func attach(p_view: MapView) -> void:
	view = p_view
	_bar = PanelContainer.new()
	_bar.name = "OrderBar"
	_bar.visible = false
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	_bar.add_child(box)
	_bar_title = UiKit.text("")
	box.add_child(_bar_title)
	_bar_buttons = HFlowContainer.new()
	box.add_child(_bar_buttons)
	_bar_help = UiKit.hint("")
	box.add_child(_bar_help)
	view.add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_left = 8
	_bar.offset_right = -8
	_bar.offset_bottom = -8


func hc() -> HighCommand:
	return HighCommand.of(view) if view else null


## Whether this peer orders squads here now: command mode on, a squad out, the commander token.
func active() -> bool:
	var h := hc()
	return on and h != null and h.is_commander() and not heroes().is_empty()


func heroes() -> Array:
	var h := hc()
	return h.view.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) in ["hero", "allied"]) if h else []


# --- Input ---------------------------------------------------------------------------------------

## MapView._gui_input hands every event here first; true when it was ours.
func handle(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and not event.ctrl_pressed and hc() and not heroes().is_empty():
		on = not on
		cancel_placing()
		_say("Command mode %s" % ("on" if on else "off"))
		refresh()
		return true
	if not active():
		return false
	if event is InputEventMouseMotion:
		_cursor = view.screen_to_map(event.position)
		var first := context_first(_cursor)
		if first != _last_first:
			_last_first = first
			refresh()  # the bar's first buttons follow what's under the cursor
		return false  # (MapView still tracks the cursor; the ghost redraws)
	if event is InputEventMouseButton:
		return _button(event)
	if event is InputEventKey and event.pressed and not event.echo:
		return _key(event)
	return false


func _key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE and placing != "":
		cancel_placing()
		return true
	if e.keycode == KEY_Z and e.ctrl_pressed:
		undo()
		return true
	if e.keycode == KEY_SPACE:
		if last_verb != "":
			begin(last_verb)
		return true
	if e.keycode == KEY_BACKSPACE and view._hover_id == 0:
		for id in _targets():
			MapCommandLayer.send(hc(), id, "cancel", Vector2.INF)
		_say("Cancelled")
		return true
	if e.keycode >= KEY_1 and e.keycode <= KEY_4:
		var list := heroes()
		var i := e.keycode - KEY_1
		if i < list.size():
			select([String(list[i].id)], e.shift_pressed)
		return true
	if e.keycode == KEY_BRACKETRIGHT:
		_cycle()
		return true
	if e.ctrl_pressed or e.alt_pressed:
		return false
	for b: Array in BAR:
		if e.keycode == b[2]:
			begin(String(b[0]))
			return true
	return false


func _button(e: InputEventMouseButton) -> bool:
	var at := view.screen_to_map(e.position)
	_cursor = at
	if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and placing != "":
		cancel_placing()
		_say("Cancelled")
		return true
	if placing == "gun" and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		arc_deg = clampf(arc_deg + (10.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -10.0), ARC_MIN, ARC_MAX)
		_cone_key = ""
		return true
	if e.button_index != MOUSE_BUTTON_LEFT or e.double_click or e.ctrl_pressed:
		return false
	if placing != "":
		if e.pressed:
			press(at, e.position)
		else:
			release(at, e.shift_pressed, e.position)
		return true
	if e.pressed:
		var hit := frame_at(e.position)
		if hit != "":
			select([hit], e.shift_pressed)
			return true
		var b := MapNodes.briefing(view)
		if view.marker_at(e.position) == 0 and not (b and b.is_open()):
			_box = e.position  # a box select (released below)
			return false
		return false
	if _box.is_finite():
		var r := Rect2(_box, Vector2.ZERO).expand(e.position)
		_box = Vector2.INF
		if r.size.length() > DRAG_PX:
			var ids: Array = []
			for f: Dictionary in heroes():
				if r.has_point(_screen_of(f)):
					ids.append(String(f.id))
			if not ids.is_empty():
				select(ids, e.shift_pressed)
				return true
	return false


# --- The flow (also the tests' way in) ----------------------------------------------------------

func select(ids: Array, add := false) -> void:
	if not add:
		selected = PackedStringArray()
	for id: Variant in ids:
		if String(id) not in selected:
			selected.append(String(id))
	refresh()


func _cycle() -> void:
	var list := heroes()
	if list.is_empty():
		return
	var i := -1
	if not selected.is_empty():
		for k in list.size():
			if String(list[k].id) == selected[-1]:
				i = k
	select([String(list[(i + 1) % list.size()].id)])


## Starts order `verb` for the selection (no point: sent at once).
func begin(verb: String) -> void:
	if _targets().is_empty() and verb != "gun":
		_say("Select a squad first (click its frame, or 1-4)")
		return
	var spec := _spec(verb)
	if spec.is_empty():
		return
	last_verb = verb
	_first = Vector2.INF
	_press = Vector2.INF
	if not bool(spec[3]):
		for id in _targets():
			_send(id, verb, Vector2.INF, false, Vector2.ZERO)
		placing = ""
		refresh()
		return
	placing = verb
	arc_deg = ARC_DEFAULT
	_cone_key = ""
	refresh()


func cancel_placing() -> void:
	placing = ""
	_press = Vector2.INF
	_first = Vector2.INF
	refresh()


func press(at: Vector2, screen := Vector2.INF) -> void:
	_press = at
	_press_screen = screen if screen.is_finite() else view.map_to_screen(at) if view else Vector2.ZERO


## The placing click comes up at `at`: a drag from the press sets the facing (or, for a frontage,
## its far end); then it's sent. `queue`: Shift held.
func release(at: Vector2, queue := false, screen := Vector2.INF) -> void:
	if not _press.is_finite():
		_press = at
	var from := _press
	var drag := at - from
	var px := (screen - _press_screen).length() if screen.is_finite() and _press_screen.is_finite() else drag.length()
	var facing := drag.normalized() if px > DRAG_PX else Vector2.ZERO
	_press = Vector2.INF
	var problem := problem_at(from)
	if problem != "":
		_say(problem, true)
		return
	match placing:
		"sbf":
			if not _first.is_finite():
				_first = from
				_say("Now click the target")
				return
			for id in _targets():
				_send_points(id, "sbf", [_first, from], queue)
			_first = Vector2.INF
		"defend_frontage":
			if px <= DRAG_PX:
				_say("Drag the frontage from one end to the other", true)
				return
			for id in _targets():
				_send_points(id, "defend_frontage", [from, at], queue, facing.orthogonal())
		"gun":
			_place_gun(from, facing)
		_:
			for id in _targets():
				_send(id, placing, from, queue, facing)
	if not queue:
		placing = ""
	refresh()


## Ctrl+Z: undo the last order (the host checks it hasn't started, within 10 s).
func undo() -> void:
	var id := _last_order_squad if _last_order_squad != "" else (selected[-1] if not selected.is_empty() else "")
	if id == "":
		_say("Nothing to undo", true)
		return
	hc().request_undo(id)
	pending.erase(id)
	_say("Undo: %s" % _callsign(id))


# --- Sending -------------------------------------------------------------------------------------

func _send(id: String, verb: String, at: Vector2, queue: bool, facing: Vector2) -> void:
	MapCommandLayer.send(hc(), id, verb, at, queue, facing)
	_note_sent(id, verb, at)


func _send_points(id: String, verb: String, pts: Array, queue: bool, facing := Vector2.ZERO) -> void:
	var o := HcOrder.make(id, verb, pts.map(func(p: Vector2) -> Array: return [p.x, p.y]))
	if facing.length() > 0.01:
		o.facing = [facing.x, facing.y]
	if next_go != "":
		o.go = next_go
	o.id = -1
	hc().request_order(o, queue)
	_note_sent(id, verb, pts[0])


func _note_sent(id: String, verb: String, at: Vector2) -> void:
	pending[id] = {"verb": verb, "point": at, "at": Time.get_ticks_msec(), "seen_ack": false}
	_last_order_squad = id


## Sends `verb` for group `id` at map point `at` (INF: none) through the host's validated path.
static func send(h: HighCommand, id: String, verb: String, at: Vector2, append := false, facing := Vector2.ZERO) -> void:
	if h == null:
		return
	if verb == "cancel":
		h.request_cancel(id, 0)
		return
	var pts: Array = [[at.x, at.y]] if at.is_finite() else []
	if verb == "sbf" and at.is_finite():
		var e := h.status(id)
		var p: Array = e.get("pos", [at.x, at.y])
		pts = [[float(p[0]), float(p[1])], [at.x, at.y]]  # from where it is, onto the spot
	var o := HcOrder.make(id, verb, pts)
	if facing.length() > 0.01:
		o.facing = [facing.x, facing.y]
	if next_go != "" and verb not in ["cancel", "report", "posture"]:
		o.go = next_go
	o.id = -1  # the host numbers it
	h.request_order(o, append)


## Place gun: the player squad's gun loads set up at `at` covering the drawn arc (StaticWeapons
## "wt_setup:<left>:<right>", GunTeam.sector).
func _place_gun(at: Vector2, facing: Vector2) -> void:
	var me := MapNodes.local_player(view)
	if me == null:
		return
	var mid := Viewshed.bearing_of(facing) if facing.length() > 0.01 else _default_bearing(at)
	var left := fposmod(mid - arc_deg * 0.5, 360.0)
	var right := fposmod(mid + arc_deg * 0.5, 360.0)
	me._server_squad_command.rpc_id(1, "wt_setup:%.0f:%.0f" % [left, right], Vector3(at.x, 0.0, at.y), PackedStringArray())
	_say("Gun: set up at %s, covering %03d-%03d" % [MapGrid.grid_ref(at, view.area, 6), int(left), int(right)])


# --- Checks and feedback -------------------------------------------------------------------------

## What's wrong with ordering to map point `p` ("" for nothing): off the map, under water.
func problem_at(p: Vector2) -> String:
	if not view.area.has_point(p):
		return "Off the map"
	var lvl := view.level
	var water: Variant = lvl.get(&"water") if lvl else null
	if water and water.has_method(&"depth_at") and float(water.call(&"depth_at", Vector3(p.x, 0.0, p.y))) > 1.2:
		return "Under water"
	return ""


## The default facing: toward the nearest known enemy marker, else north.
func _default_bearing(at: Vector2) -> float:
	var marks := MapNodes.markers(view)
	var best := Vector2.INF
	if marks:
		for m: Dictionary in marks.markers.values():
			var pts: PackedVector2Array = m.get("points", PackedVector2Array())
			if String(m.get("kind", "")) == "enemy" and not pts.is_empty() and (not best.is_finite() or pts[0].distance_to(at) < best.distance_to(at)):
				best = pts[0]
	return Viewshed.bearing_of(best - at) if best.is_finite() and best.distance_to(at) > 1.0 else 0.0


func _say(text: String, bad := false) -> void:
	_flash = ("! " if bad else "") + text
	_flash_until = Time.get_ticks_msec() + 2500
	if view:
		view.queue_redraw()


## Client, each draw: pending orders the host has acknowledged ("Hawk 2, copy") or refused.
func _check_pending() -> void:
	var h := hc()
	if h == null:
		return
	for id: String in pending.keys():
		var p: Dictionary = pending[id]
		var e := h.status(id)
		var o: Dictionary = e.get("order", {})
		var pts: Array = o.get("points", [])
		var hit := String(o.get("verb", "")) == String(p.verb) and (not (p.point as Vector2).is_finite() or (not pts.is_empty()
			and Vector2(float(pts[0][0]), float(pts[0][1])).distance_to(p.point) < 3.0))
		if hit and not bool(p.seen_ack):
			pending.erase(id)
			_say("%s, copy" % _callsign(id))
		elif Time.get_ticks_msec() - int(p.at) > 4000:
			pending.erase(id)
			if h.last_message != "":
				_say("%s: %s" % [_callsign(id), h.last_message], true)


## The squads an order goes to: the selection still out.
func _targets() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Dictionary in heroes():
		if String(f.id) in selected:
			out.append(String(f.id))
	return out


func _callsign(id: String) -> String:
	var e := hc().status(id) if hc() else {}
	return String(e.get("callsign", id))


func _spec(verb: String) -> Array:
	for b: Array in BAR:
		if String(b[0]) == verb:
			return b
	return []


## The group whose frame is under screen point `s`, or "".
func frame_at(s: Vector2) -> String:
	for f: Dictionary in heroes():
		if Rect2(_screen_of(f) - FRAME * 0.75, FRAME * 1.5).has_point(s):
			return String(f.id)
	return ""


func _screen_of(f: Dictionary) -> Vector2:
	var p: Array = f.get("pos", [0, 0])
	return view.map_to_screen(Vector2(float(p[0]), float(p[1])))


# --- The order bar -------------------------------------------------------------------------------

## The verbs to show first for what's under the cursor (C6's ContextResolver takes this over).
func context_first(at: Vector2) -> Array[String]:
	var marks := MapNodes.markers(view)
	if marks:
		for m: Dictionary in marks.markers.values():
			var pts: PackedVector2Array = m.get("points", PackedVector2Array())
			if String(m.get("kind", "")) == "enemy" and not pts.is_empty() and pts[0].distance_to(at) < 40.0:
				return ["attack", "sbf"]
	var ex := MapNodes.extraction(view)
	if ex:
		for p: Dictionary in ex.points:
			if Extraction.inside(p, Vector3(at.x, 0.0, at.y)):
				return ["extract"]
	return ["move", "defend"]


func refresh() -> void:
	if _bar == null:
		return
	_bar.visible = active()
	if not _bar.visible:
		return
	var names := PackedStringArray()
	for id in _targets():
		var e := hc().status(id)
		names.append("%s (%d/%d, %s)" % [String(e.get("callsign", id)).to_upper(), int(e.get("up", 0)), int(e.get("total", 0)), e.get("band", "")])
	_bar_title.text = ", ".join(names) if not names.is_empty() else "No squad selected: click a frame, drag a box, or 1-4"
	for c in _bar_buttons.get_children():
		_bar_buttons.remove_child(c)
		c.queue_free()
	var first := context_first(_cursor)
	var order: Array = BAR.filter(func(b: Array) -> bool: return String(b[0]) in first)
	order.append_array(BAR.filter(func(b: Array) -> bool: return String(b[0]) not in first))
	var loads := view._our_weapon_loads()
	for b: Array in order:
		var verb := String(b[0])
		var btn := UiKit.button("%s [%s]" % [b[1], OS.get_keycode_string(b[2])], begin.bind(verb), String(b[4]))
		btn.toggle_mode = true
		btn.set_pressed_no_signal(verb == placing)
		if verb == "gun":
			btn.disabled = not loads.has("gun")
			if btn.disabled:
				btn.tooltip_text = "Nobody in the squad carries a gun's loads"
		elif names.is_empty():
			btn.disabled = true
		_bar_buttons.add_child(btn)
	var go := " (on %s)" % next_go.capitalize() if next_go != "" else ""
	_bar_help.text = ("Placing %s%s: click the point, drag to face, release to confirm. " % [_spec(placing)[1], go] if placing != "" else "") \
		+ "Right-click: cancel   Shift: queue   Ctrl+Z: undo (%d s)   Backspace: cancel orders   Space: repeat last%s   C: command mode" % [int(UNDO_S),
			" (%s)" % _spec(last_verb)[1] if last_verb != "" else ""]


# --- Drawing -------------------------------------------------------------------------------------

## Draws every group, the selection, the ghost and the cone (MapView._draw).
func draw() -> void:
	if view == null:
		return
	MapCommandLayer.draw_groups(view, selected)
	if not active():
		return
	_check_pending()
	for id: String in pending:
		var e := hc().status(id)
		var p: Array = e.get("pos", [0, 0])
		var to: Vector2 = pending[id].point
		if to.is_finite():
			view.draw_dashed_line(view.map_to_screen(Vector2(float(p[0]), float(p[1]))), view.map_to_screen(to), GHOST, 1.5, 3.0)  # sent: dotted till the copy
	if _box.is_finite():
		var r := Rect2(_box, Vector2.ZERO).expand(view.get_local_mouse_position())
		view.draw_rect(r, Color(SELECTED, 0.15))
		view.draw_rect(r, SELECTED, false, 1.0)
	if placing != "":
		_draw_ghost()
	if Time.get_ticks_msec() < _flash_until:
		var bad := _flash.begins_with("! ")
		view.call(&"_label_raw", view.get_local_mouse_position() + Vector2(16, -18), _flash.trim_prefix("! "), BAD if bad else SELECTED, UiKit.FONT_SMALL)


func _draw_ghost() -> void:
	var at := _press if _press.is_finite() else _cursor
	var s := view.map_to_screen(at)
	var problem := problem_at(at)
	var colour := BAD if problem != "" else GHOST
	var mouse := view.map_to_screen(_cursor)
	if placing == "gun":
		var facing := (_cursor - _press) if _press.is_finite() and (mouse - s).length() > DRAG_PX else Vector2.ZERO
		var mid := Viewshed.bearing_of(facing) if facing.length() > 0.01 else _default_bearing(at)
		_draw_cone(at, mid)
	else:
		for id in _targets():
			var e := hc().status(id)
			var p: Array = e.get("pos", [0, 0])
			var from := view.map_to_screen(Vector2(float(p[0]), float(p[1])))
			view.draw_dashed_line(from, view.map_to_screen(_first) if placing == "sbf" and _first.is_finite() else s, colour, 1.5, 4.0)
		if placing == "sbf" and _first.is_finite():
			var f := view.map_to_screen(_first)
			view.draw_line(f, mouse, BAD, 1.0)
			view.draw_arc(mouse, 10.0, 0.0, TAU, 20, BAD, 1.5)
		view.draw_rect(Rect2(s - FRAME * 0.5, FRAME), colour, false, 1.5)
		if _press.is_finite() and (mouse - s).length() > DRAG_PX:
			view.draw_line(s, mouse, colour, 2.0)
			var dir := (mouse - s).normalized()
			view.draw_line(mouse, mouse - dir.rotated(0.5) * 10.0, colour, 2.0)
			view.draw_line(mouse, mouse - dir.rotated(-0.5) * 10.0, colour, 2.0)
	var label := "%s -> %s" % [_spec(placing)[1], MapGrid.grid_ref(at, view.area, 6)]
	if placing == "sbf":
		label += ": click the target" if _first.is_finite() else ": click where it fires from"
	elif placing == "defend_frontage":
		label += ": drag to the other end"
	elif placing == "gun":
		label += ": arc %d deg (wheel)" % int(arc_deg)
	else:
		label += ", drag to face, release to confirm"
	view.call(&"_label_raw", s + Vector2(14, 14), problem if problem != "" else label, colour, UiKit.FONT_SMALL)


## The gun's cone at `at` facing bearing `mid`: what it sees (green), dead ground (dark), a crest
## within 30 m (red edge), range rings, and the read-outs.
func _draw_cone(at: Vector2, mid: float) -> void:
	var kit := "tripod_m2"
	var rng := Viewshed.ranges(kit)
	var eff := float(rng.get("effective_m", 800.0))
	var key := "%.0f,%.0f,%.0f,%.0f" % [at.x, at.y, mid, arc_deg]
	if key != _cone_key and Time.get_ticks_msec() - _cone_ms >= CONE_EVERY_MS:
		_cone_key = key
		_cone_ms = Time.get_ticks_msec()
		_cone = Viewshed.cast(Vector3(at.x, 0.0, at.y), mid, arc_deg, eff, _height_fn())
	if _cone.is_empty():
		return
	var o: Vector3 = _cone.origin
	var origin := view.map_to_screen(Vector2(o.x, o.z))
	var rays: Array = _cone.rays
	var step := float(_cone.step)
	for i in rays.size() - 1:
		var a: Dictionary = rays[i]
		var b: Dictionary = rays[i + 1]
		var da := Viewshed.dir_of(float(a.bearing))
		var db := Viewshed.dir_of(float(b.bearing))
		var seen: PackedByteArray = a.seen
		var j := 0
		while j < seen.size():
			var k := j
			while k + 1 < seen.size() and seen[k + 1] == seen[j]:
				k += 1
			var r0 := j * step
			var r1 := (k + 1) * step
			var pa0 := Vector2(o.x, o.z) + da * r0
			var pa1 := Vector2(o.x, o.z) + da * r1
			var pb1 := Vector2(o.x, o.z) + db * r1
			var pb0 := Vector2(o.x, o.z) + db * r0
			var poly := PackedVector2Array([view.map_to_screen(pa0), view.map_to_screen(pa1), view.map_to_screen(pb1), view.map_to_screen(pb0)])
			view.draw_colored_polygon(poly, SEEN if seen[j] == 1 else DEAD)
			j = k + 1
		if bool(a.close):
			view.draw_line(origin, view.map_to_screen(Vector2(o.x, o.z) + da * 30.0), BAD, 3.0)
	for ring: float in [eff, float(rng.get("max_m", eff))]:
		var rad := (view.map_to_screen(Vector2(o.x + ring, o.z)) - origin).length()
		view.draw_arc(origin, rad, deg_to_rad(mid - arc_deg * 0.5 - 90.0), deg_to_rad(mid + arc_deg * 0.5 - 90.0), 32, GHOST, 1.0)
	var reads := cone_readouts(Vector3(o.x, 0.0, o.z), _cone)
	view.call(&"_label_raw", origin + Vector2(14, 32), "HEIGHT %+.0f m   SEEN BY: %d known enemy position%s   %s" % [float(reads.height),
		int(reads.seen_by), "" if int(reads.seen_by) == 1 else "s", "BLOCKED CLOSE IN" if int(_cone.blocked_close) > rays.size() / 4 else ""], GHOST, UiKit.FONT_SMALL)


## The cone's read-outs: height over the ground it covers, and how many known enemy positions
## (DeadGround.known_watchers: intel, never the truth) can see the spot.
func cone_readouts(at: Vector3, cone: Dictionary) -> Dictionary:
	var h := _height_fn()
	var base := float(h.call(at.x, at.z))
	var sum := 0.0
	var n := 0
	for r: Dictionary in cone.rays:
		var d := Viewshed.dir_of(float(r.bearing)) * float(cone.range) * 0.75
		sum += float(h.call(at.x + d.x, at.z + d.y))
		n += 1
	var seen_by := 0
	for w: Vector3 in DeadGround.known_watchers(view.level):
		if Viewshed.line_clear(w, Vector3(at.x, base, at.z), h):
			seen_by += 1
	return {"height": base - (sum / n if n > 0 else base), "seen_by": seen_by}


## The ground's height at (x, z): the zone's terrain, else flat.
func _height_fn() -> Callable:
	var lvl := view.level if view else null
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if terrain is ZoneTerrain:
		return func(x: float, z: float) -> float: return (terrain as ZoneTerrain).height_at(x, z)
	return func(_x: float, _z: float) -> float: return 0.0


## Draws every high command group on `view` with `selected` outlined (also the HC camera's 2D
## fallback).
static func draw_groups(view: MapView, selected := PackedStringArray()) -> void:
	var h := HighCommand.of(view)
	if h == null:
		return
	for e: Dictionary in h.view:
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
				if String(o.state) in ["sent", "queued", "waiting"]:
					view.draw_dashed_line(last, to, line_colour, 1.5, 3.0)
				else:
					view.draw_line(last, to, line_colour, 2.0)
				last = to
			view.draw_circle(last, 4.0, line_colour)
			if String(o.get("go", "")) != "":
				view.call(&"_label_raw", last + Vector2(6, -6), String(o.go).left(1).to_upper(), line_colour, UiKit.FONT_SMALL)
		for m: Variant in e.get("men", []):
			view.draw_circle(view.map_to_screen(Vector2(float(m[0]), float(m[1]))), 2.0, colour)
		var r := Rect2(at - FRAME * 0.5, FRAME)
		var dark := bool(e.get("dark", false))
		view.draw_rect(r, Color(colour, 0.25 if not dark else 0.08))
		view.draw_rect(r, Color(1, 0.3, 0.3) if bool(e.get("contact", false)) else (Color(0.6, 0.6, 0.6) if dark else colour), false, 2.0)
		if String(e.id) in selected:
			view.draw_rect(r.grow(4.0), SELECTED, false, 2.0)
		view.draw_line(r.position, r.end, colour, 1.5)
		view.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), colour, 1.5)
		view.draw_circle(r.position + Vector2(r.size.x + 4.0, 0.0), 4.0, CE_COLOURS.get(String(e.get("band", "green")), Color.WHITE))
		var state := String(o.get("verb", "")) + (" (%s)" % o.state if String(o.get("state", "")) not in ["", "active"] else "") if not o.is_empty() else "idle"
		if String(o.get("state", "")) == "failed" and String(o.get("why", "")) != "":
			state += ": " + String(o.why)
		view.call(&"_label", at, "%s %d/%d: %s" % [String(e.callsign).to_upper(), int(e.up), int(e.total), state], colour, "squad", MapView.LABEL_FONT)


## Adds the squads' orders to the map's right-click menu `menu` for map point `at` (the old
## submenus, kept beside the order bar). Only the commander gets them.
static func add_orders(view: MapView, menu: PopupMenu, at: Vector2) -> Array[PopupMenu]:
	var made: Array[PopupMenu] = []
	var h := HighCommand.of(view)
	if h == null or h.view.is_empty() or not h.is_commander():
		return made
	var list := h.view.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "hero")
	if list.is_empty():
		return made
	menu.add_separator("High command (%s)" % MapGrid.grid_ref(at, view.area))
	for e: Dictionary in list:
		var sub := PopupMenu.new()
		var verbs: Array = []
		for b: Array in BAR:
			if String(b[0]) not in ["gun", "defend_frontage"]:
				sub.add_item("%s%s" % [b[1], " here" if bool(b[3]) else ""], verbs.size())
				verbs.append(b)
		sub.add_item("Report", verbs.size())
		verbs.append(["report", "Report", 0, false])
		sub.add_item("Cancel its order", verbs.size())
		verbs.append(["cancel", "Cancel", 0, false])
		var id := String(e.id)
		sub.id_pressed.connect(func(i: int) -> void: send(h, id, String(verbs[i][0]), at if bool(verbs[i][3]) else Vector2.INF))
		menu.add_child(sub)
		menu.add_submenu_node_item("%s (%d/%d)" % [e.callsign, int(e.up), int(e.total)], sub)
		made.append(sub)
	return made
