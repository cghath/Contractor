class_name MedicalMenu
extends Control
## The medical menu (H; inspired by ACE3's): the person you look at within treatment reach,
## else yourself. A body diagram of the 14 parts (Vitals.BODY_PARTS) coloured by state
## (bleeding by severity, untreated, treated) with markers for tourniquets, splints,
## dressings and seals, and an IV or IO line; the chosen part's injuries in words and every
## medical item you carry, usable or greyed out with the reason; the signs (numbers only with
## a pulse oximeter, as Check condition); and an activity log. A view over Vitals: choosing an
## item sends the same host request as the interaction menu's Treat (Soldier._server_treat,
## through InteractionMenu.perform), so nothing new decides anything. Everything shown reads
## replicated state, so it works the same on clients.
## The activity log is local to the treater for now: what you chose here, and the changes you
## saw on the casualty while the menu was open (a shared log comes with the triage card).
## H or Escape closes it; while open it has the mouse and the keys.

## Part state, for the diagram's colours.
const OK := &"ok"
const BLEEDING := &"bleeding"
const UNTREATED := &"untreated"
const TREATED := &"treated"
## Bleeding severity 1..3 by the worst bleeding wound's rate (L/min at full blood; proposed:
## 3 for an arterial or junctional bleed, 2 for venous or muscle, 1 for a graze).
const SEVERE_RATE := 0.8
const MODERATE_RATE := 0.2
const BLEED_COLORS := [Color(0.8, 0.35, 0.35), Color(0.85, 0.45, 0.3), Color(0.85, 0.2, 0.15), Color(0.65, 0.0, 0.0)]
const STATE_COLORS := {OK: Color(0.55, 0.57, 0.6), UNTREATED: Color(0.9, 0.65, 0.15), TREATED: Color(0.3, 0.65, 0.35)}
## Markers on a part.
const TOURNIQUET := &"tourniquet"
const SPLINT := &"splint"
const BINDER := &"binder"
const DRESSING := &"dressing"
const SEAL := &"seal"
const IV := &"iv"
const IO := &"io"
const MARKER_TEXT := {TOURNIQUET: "TQ", SPLINT: "SPL", BINDER: "BND", DRESSING: "DR", SEAL: "SEAL", IV: "IV", IO: "IO"}
const DRESSED_KINDS := ["venous", "muscle", "graze", "junctional", "arterial", "burn"]
## The diagram: each part's box in a 220 x 400 figure, the casualty facing you (their right
## arm on your left).
const FIGURE_SIZE := Vector2(220.0, 400.0)
const PART_RECTS := {
	&"head": Rect2(88, 0, 44, 30), &"face": Rect2(92, 30, 36, 16), &"neck": Rect2(98, 46, 24, 14),
	&"chest": Rect2(70, 60, 80, 58), &"abdomen": Rect2(74, 118, 72, 38), &"pelvis": Rect2(74, 156, 72, 32),
	&"upper_arm_r": Rect2(38, 62, 30, 66), &"forearm_r": Rect2(30, 130, 30, 68),
	&"upper_arm_l": Rect2(152, 62, 30, 66), &"forearm_l": Rect2(160, 130, 30, 68),
	&"thigh_r": Rect2(76, 190, 32, 100), &"thigh_l": Rect2(112, 190, 32, 100),
	&"shin_r": Rect2(78, 292, 28, 106), &"shin_l": Rect2(114, 292, 28, 106),
}
## The panel at full size (Captain, 2026-10-14: "all the UIs need a pass"; P0-2 in
## docs/ui_audit.md): in a smaller window, or at a bigger Menu and HUD size, it shrinks to the
## window less PANEL_MARGIN on each side, the body diagram draws smaller, the middle and
## right-hand columns narrow (their text wraps or cuts with "...") and the item list shows
## fewer rows and scrolls.
const PANEL_SIZE := Vector2(1080.0, 620.0)
const PANEL_MARGIN := UiKit.SPACE_M
## The smallest window height the layout is made for: 1280 x 720 at UI scale 1.5 (480 px)
## less the margins.
const PANEL_MIN_H := 456.0
## The layout, from the panel's top left: the figure's left edge and top (the first headings'
## baseline too), the gap right of it, the item list's top and width at full size, the gap
## before the right-hand column, the log's heading, and what the legend under the figure takes.
const FIGURE_X := 30.0
const FIGURE_TOP := 70.0
const FIGURE_GAP := 40.0
const ROWS_Y := 230.0
const ITEMS_W := 414.0
const COLUMN_GAP := 16.0
const LEGEND_H := 88.0
const CLOSE_HINT_W := 150.0
## Most lines of the chosen part's injuries, and of the signs.
const INJURY_LINES := 5
const SIGN_LINES := 8
## The activity log's text size (UiKit's smallest: nothing under 14 px).
const LOG_FONT := UiKit.FONT_SMALL
## The theme's panel border, and the hovered row (the accent, faint).
const BORDER := Color(0.32, 0.35, 0.29)
const HOVER_BG := Color(0.91, 0.67, 0.25, 0.25)
const ROW_H := 24.0
## The item list's scroll bar, right of the rows (click above or below the thumb: a page).
const SCROLL_BAR_W := 10.0
const MAX_LOG := 14
## The activity log's heading, below the panel's top (right-hand column, under the signs).
const LOG_Y := 310.0
const REFRESH_S := 0.25

## The treater (the local player).
var actor: Soldier
## Who the menu is open on (actor for yourself).
var target: Node3D
var part: StringName = &"chest"
## The chosen part's item rows (item_options) as last refreshed.
var options: Array[Dictionary] = []
## Activity log lines, newest last.
var log_lines: PackedStringArray = []
## The first item row shown. More rows than fit (a medic's full kit) scroll: the mouse
## wheel, the scroll bar, or the up and down keys (audit A2-05: rows past the panel's foot
## couldn't be reached, yet were still clickable unseen).
var scroll := 0
var _hover := -1
var _refresh_left := 0.0
var _seen := {}  # part -> its summary last refresh, for the log


func _init(p_actor: Soldier = null) -> void:
	actor = p_actor
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_open() -> bool:
	return visible


## Opens on `who` (a body with Vitals; null or anything else: yourself).
func open(who: Node3D) -> void:
	target = who if who != null and Vitals.find_on(who) != null else actor
	part = worst_part(Vitals.find_on(target))
	if target != _last_target():
		log_lines.clear()
		_seen.clear()
		_add_log("Opened on %s" % _who())
	_log_target = target
	scroll = 0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


var _log_target: Node3D


func _last_target() -> Node3D:
	return _log_target if is_instance_valid(_log_target) else null


func select_part(p: StringName) -> void:
	if Vitals.BODY_PARTS.has(p):
		if p != part:
			scroll = 0
		part = p
		refresh()


## Scrolls the item list by `rows` (negative: up), kept within the list.
func scroll_rows(rows: int) -> void:
	scroll += rows
	_clamp_scroll()
	queue_redraw()


func _clamp_scroll() -> void:
	scroll = clampi(scroll, 0, maxi(options.size() - visible_rows(), 0))


## Chooses option row `index`: sends its host request, logs it. Returns the text to show
## (the reason, for a greyed-out row).
func choose(index: int) -> String:
	if index < 0 or index >= options.size():
		return ""
	var entry := options[index]
	var text := InteractionMenu.perform(actor, entry)
	if text == "":
		_add_log("You: %s" % entry.label.split("  ")[0])
	return text


## Puts triage card `card` on the casualty (host checks reach); logs it.
func set_triage(card: StringName) -> void:
	if is_instance_valid(target) and actor.vitals.is_up():
		actor.rpc_id(1, &"_server_set_triage", target.get_path(), card)
		_add_log("You: triage %s" % String(Vitals.TRIAGE_TEXT.get(card, card)).to_lower())


func _process(delta: float) -> void:
	if not visible:
		return
	if actor == null or not is_instance_valid(actor) or not actor.vitals.is_up() or not is_instance_valid(target):
		close()
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		refresh()


func refresh() -> void:
	_refresh_left = REFRESH_S
	if not is_instance_valid(target):
		return
	options = item_options(actor, target, part)
	_clamp_scroll()
	_watch(Vitals.find_on(target))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"medical_menu") or event.is_action_pressed(&"pause"):
		close()
	elif event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_down", true):
		scroll_rows(-1 if event.is_action(&"ui_up") else 1)
	elif event.is_action_pressed(&"ui_page_up", true) or event.is_action_pressed(&"ui_page_down", true):
		scroll_rows(visible_rows() * (-1 if event.is_action(&"ui_page_up") else 1))
	if event is InputEventKey:
		get_viewport().set_input_as_handled()  # the menu has the keys: no reloading or throwing behind it


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row := _row_at(event.position)
		if row != _hover:
			_hover = row
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		scroll_rows(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		_hover = _row_at(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := part_at(event.position)
		if p != &"":
			select_part(p)
		elif triage_at(event.position) != &"":
			set_triage(triage_at(event.position))
		elif _scroll_bar_rect().has_point(event.position):
			var thumb := _scroll_thumb_rect()
			if event.position.y < thumb.position.y or event.position.y > thumb.end.y:
				scroll_rows(visible_rows() * (-1 if event.position.y < thumb.position.y else 1))
		else:
			var text := choose(_row_at(event.position))
			if text != "" and actor.player_input:
				actor.player_input.flash(text)
		accept_event()


# --- What it shows (static: tests and other views use these) -------------------------------

## The person `actor` looks at within treatment reach (Soldier._in_treat_reach: to the body,
## Soldier.body_point, where a ragdoll lies), or null. Nearest the middle of the view first,
## the living before the dead: a body nearer the crosshair than the casualty used to take the
## menu, and every item said "Too late" (Captain's playtest P0164). A body alone in view is
## still picked, to check it.
static func looked_at(actor: Soldier, camera: Camera3D) -> Node3D:
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best: Node3D = null
	var best_angle := deg_to_rad(InteractionMenu.VIEW_CONE_DEG)
	var dead_best: Node3D = null
	var dead_angle := best_angle
	for node: Node in actor.get_tree().get_nodes_in_group(&"combatants"):
		if node == actor or not node is Soldier or node.is_queued_for_deletion() or Vitals.find_on(node) == null:
			continue
		var s := node as Soldier
		if is_instance_valid(s.carried_by) and s.carried_by != actor:
			continue  # on someone else's shoulder
		if not actor._in_treat_reach(s):
			continue
		var at := s.body_point() if is_instance_valid(s.ragdoll) else InteractionMenu.action_point(s)
		var angle := forward.angle_to(at - eye)
		var ray := PhysicsRayQueryParameters3D.create(eye, at, 1, [actor.get_rid(), s.get_rid()])  # a wall between, not their own capsule
		var dead := s.vitals.is_dead()
		if angle < (dead_angle if dead else best_angle) and actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			if dead:
				dead_best = s
				dead_angle = angle
			else:
				best = s
				best_angle = angle
	return best if best != null else dead_best


## The part to show first: the most urgent task's, else the worst-looking one, else the chest.
static func worst_part(vitals: Vitals) -> StringName:
	if vitals == null:
		return &"chest"
	for task in vitals.care_needed():
		if Vitals.BODY_PARTS.has(task.part):
			return task.part
	for p: StringName in Vitals.BODY_PARTS:
		if part_state(vitals, p).state != OK:
			return p
	return &"chest"


## Draws the body diagram on `ci` at `origin`, `k` times full size: each part coloured by state, the
## `selected` part outlined, markers written when big enough. With `only` (non-empty) just those
## parts are coloured, the rest drawn faint (the HUD silhouette).
static func draw_diagram(ci: CanvasItem, vitals: Vitals, origin: Vector2, k: float, selected: StringName = &"",
		only: Array[StringName] = []) -> void:
	var font := ThemeDB.fallback_font
	for p: StringName in PART_RECTS:
		var r: Rect2 = PART_RECTS[p]
		r = Rect2(origin + r.position * k, r.size * k)
		var state := part_state(vitals, p)
		var faint := not only.is_empty() and not only.has(p)
		var fill := state_color(state)
		if faint:
			fill = Color(0.55, 0.57, 0.6, 0.3)
		ci.draw_rect(r, fill)
		ci.draw_rect(r, Color.WHITE if p == selected else Color(0.15, 0.15, 0.15, 0.4 if faint else 1.0), false, 3.0 if p == selected else 1.0)
		var y := r.position.y + 13.0 * k
		for m: StringName in state.markers:
			if m == TOURNIQUET:
				ci.draw_rect(Rect2(r.position.x - 2.0 * k, r.position.y + 4.0 * k, r.size.x + 4.0 * k, 5.0 * k), Color(0.05, 0.05, 0.05))
			if k >= 0.7:  # the menu's figure (smaller in a short window), not the HUD silhouette
				ci.draw_string(font, Vector2(r.position.x + 2, y + 8), MARKER_TEXT[m], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2, UiKit.FONT_SMALL, Color.WHITE)
				y += UiKit.FONT_SMALL


## The parts the HUD silhouette highlights: an untreated bleed, an unsplinted fracture, a tourniquet.
static func hud_parts(vitals: Vitals) -> Array[StringName]:
	var out: Array[StringName] = []
	for p: StringName in PART_RECTS:
		var state := part_state(vitals, p)
		var fracture := false
		for w in vitals.wound_list():
			if w.part == p and String(w.kind) == "fracture" and not w.treated:
				fracture = true
		if state.state == BLEEDING or state.markers.has(TOURNIQUET) or fracture:
			out.append(p)
	return out


## One part's state: "state" (OK, BLEEDING, UNTREATED, TREATED), "severity" (0, or 1..3 while
## bleeding) and "markers" (TOURNIQUET, SPLINT, BINDER, DRESSING, SEAL, IV, IO).
static func part_state(vitals: Vitals, p: StringName) -> Dictionary:
	var severity := 0
	var untreated := false
	var any := false
	var markers: Array[StringName] = []
	for w in vitals.wound_list():
		if w.part != p:
			continue
		any = true
		var rate := float(w.rate)
		if w.bleeding:
			severity = maxi(severity, 3 if rate >= SEVERE_RATE else (2 if rate >= MODERATE_RATE else 1))
		elif not w.treated and not w.get("pneumo", false):
			untreated = true
		if w.treated:
			var kind := String(w.kind)
			var marker: StringName = (BINDER if w.name == BodyMap.PELVIS_BONE else SPLINT) if kind == "fracture" else (SEAL if kind == "chest" else (DRESSING if kind in DRESSED_KINDS else &""))
			if marker != &"" and not markers.has(marker):
				markers.append(marker)
	if vitals.tourniquets().has(p):
		markers.push_front(TOURNIQUET)
	var line := vitals.access()
	if not line.is_empty() and line.get("part", &"") == p:
		markers.append(IO if line.kind == "io" else IV)
	var state := OK
	if severity > 0:
		state = BLEEDING
	elif untreated:
		state = UNTREATED
	elif any:
		state = TREATED
	return {"state": state, "severity": severity, "markers": markers}


static func state_color(state: Dictionary) -> Color:
	if state.state == BLEEDING:
		return BLEED_COLORS[clampi(int(state.severity), 1, 3)]
	return STATE_COLORS.get(state.state, STATE_COLORS[OK])


## Every treatment item id (ItemDB items with a treat_s), in ItemDB's order.
static func medical_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ItemDB.all_ids():
		var item := ItemDB.get_item(StringName(id))
		if item and item.stats.has("treat_s"):
			out.append(StringName(id))
	return out


## The rows for `p` of `who`: every medical item `treater` carries (Vitals.has_item: loose or
## in a kit; hands-only CPR too), each an InteractionMenu.perform action for _server_treat
## with "disabled" set to why it can't be used now (the host's own checks in Soldier._treat:
## reach, someone else's hands, Vitals.treatment_problem; an IV goes in a forearm or lower
## leg, an IO always in the sternum). A tourniquet also as a rushed row, and Remove
## tourniquet while one is on. Usable rows first.
static func item_options(treater: Soldier, who: Node3D, p: StringName) -> Array[Dictionary]:
	var usable: Array[Dictionary] = []
	var greyed: Array[Dictionary] = []
	var vitals := Vitals.find_on(who)
	if vitals == null:
		return usable
	var reach := "" if treater._in_treat_reach(who) else "Too far away"
	for id in medical_ids():
		if not Soldier.kit_has(treater, who, id):
			continue
		var item := ItemDB.get_item(id)
		var at := WoundModel.IO_PART if id == WoundModel.IO_KIT else p
		var why := reach
		if why == "" and who == treater and Vitals.needs_other_hands(id):
			why = "Someone else has to place that"
		if why == "" and WoundModel.IV_GAUGES.has(id) and not WoundModel.IV_SITES.has(p):
			why = "An IV goes in a forearm or lower leg"
		if why == "" and WoundModel.IV_GAUGES.has(id) and not vitals.iv_site_ok(p):
			why = "Not below a tourniquet"
		if why == "":
			why = vitals.treatment_problem(id, at)
		var rows := [false, true] if id == WoundModel.TOURNIQUET else [false]
		for rushed: bool in rows:
			var seconds := treater.treat_seconds(who, item, rushed)
			var label := "%s%s (%.1f s)" % [item.name, " rushed" if rushed else "", seconds]
			if id == WoundModel.IO_KIT:
				label += ", sternum"
			var row := {"id": &"treat_item", "label": label, "request": &"_server_treat", "with": &"treatment",
				"target": who, "item": id, "part": at, "rushed": rushed, "disabled": why}
			(usable if why == "" else greyed).append(row)
	if vitals.tourniquets().has(p):
		var why := reach if reach != "" else vitals.removal_problem(p)
		var row := {"id": &"remove_tourniquet", "label": "Remove tourniquet", "request": &"_server_remove_tourniquet",
			"with": &"target_part", "target": who, "part": p, "disabled": why}
		(usable if why == "" else greyed).append(row)
	return usable + greyed


## `p`'s injuries in words ("Arterial bleed, held by tourniquet"), or "No injuries found".
static func injuries_text(vitals: Vitals, p: StringName) -> String:
	var lines := PackedStringArray()
	for w in vitals.wound_list():
		if w.part == p:
			var text := InteractionMenu._kind_text(w) + InteractionMenu._wound_status(w)
			lines.append(text.substr(0, 1).to_upper() + text.substr(1))
	var t: Dictionary = vitals.tourniquets().get(p, {})
	if not t.is_empty():
		lines.append("%s on" % ("Two tourniquets" if int(t.count) > 1 else "Tourniquet"))
	var line := vitals.access()
	if not line.is_empty() and line.get("part", &"") == p:
		lines.append("IO line in" if line.kind == "io" else "IV line in (%d g)" % int(line.gauge))
	return "\n".join(lines) if not lines.is_empty() else "No injuries found"


## The signs in words (Vitals.signs), the pulse oximeter's reading first when `oximeter`
## (the only numbers, as in Check condition), the airway, or "No signs of note".
static func signs_lines(vitals: Vitals, on_self: bool, oximeter: bool) -> PackedStringArray:
	var out := vitals.signs(on_self)
	if oximeter:
		var reading := "no reading" if vitals.in_cardiac_arrest() or vitals.is_dead() \
			else "SpO2 %d%%, pulse %d" % [roundi(vitals.spo2()), roundi(vitals.heart_rate())]
		out.insert(0, "Pulse oximeter: %s" % reading)
	if vitals.has_npa():
		out.append("NPA in")
	elif vitals.airway_blocked():
		out.append("Airway blocked: needs an NPA")
	if out.is_empty():
		out.append("No signs of note")
	return out


# --- Activity log ----------------------------------------------------------------------------

func _add_log(text: String) -> void:
	var t := Time.get_time_dict_from_system()
	log_lines.append("%02d:%02d:%02d  %s" % [t.hour, t.minute, t.second, text])
	while log_lines.size() > MAX_LOG:
		log_lines.remove_at(0)
	queue_redraw()


## Logs what changed on the casualty since the last look: a part starting or stopping
## bleeding, a marker going on or coming off.
func _watch(vitals: Vitals) -> void:
	if vitals == null:
		return
	var first := _seen.is_empty()
	for p: StringName in Vitals.BODY_PARTS:
		var now := part_state(vitals, p)
		var before: Dictionary = _seen.get(p, {})
		_seen[p] = now
		if first or before.is_empty():
			continue
		var where := InteractionMenu.part_name(p)
		if now.state == BLEEDING and before.state != BLEEDING:
			_add_log("%s: bleeding" % where)
		elif before.state == BLEEDING and now.state != BLEEDING:
			_add_log("%s: bleeding stopped" % where)
		for m: StringName in now.markers:
			if not before.markers.has(m):
				_add_log("%s: %s on" % [where, MARKER_TEXT[m]])
		for m: StringName in before.markers:
			if not now.markers.has(m):
				_add_log("%s: %s off" % [where, MARKER_TEXT[m]])


func _who() -> String:
	return "yourself" if target == actor else InteractionMenu.display_name(target)


# --- Drawing ----------------------------------------------------------------------------------

## The panel: PANEL_SIZE, or the window less PANEL_MARGIN on each side when that's smaller
## (P0-2, docs/ui_audit.md: the fixed 1080 x 620 panel ran off a 1280 x 720 window at the
## Captain's 1.2, and its signs and log columns with it). Centred in the visible rect.
func _panel() -> Rect2:
	var screen := get_viewport_rect().size
	var dims := PANEL_SIZE.min(screen - Vector2.ONE * PANEL_MARGIN * 2.0).max(Vector2.ZERO)
	return Rect2(((screen - dims) * 0.5).max(Vector2.ZERO), dims)


## How big the body diagram is drawn: full size when the panel is tall enough, smaller in a
## short one so it and its legend end above the panel's foot.
func _figure_k() -> float:
	var room := _panel().size.y - FIGURE_TOP - LEGEND_H
	return clampf(room / FIGURE_SIZE.y, 0.5, 1.0)


## The middle column (the chosen part, its items, the triage cards) starts right of the figure.
func _mid_x() -> float:
	return FIGURE_X + FIGURE_SIZE.x * _figure_k() + FIGURE_GAP


## The legend's width: under the figure, short of the middle column.
func _legend_w() -> float:
	return FIGURE_SIZE.x * _figure_k() + FIGURE_GAP - UiKit.SPACE_M


## The middle column's width: ITEMS_W where there's room (the full panel), else a share of
## what's left beside the signs column.
func _mid_w() -> float:
	var room := _panel().size.x - UiKit.SPACE_L - _mid_x() - COLUMN_GAP
	return clampf(room * 0.55, 160.0, ITEMS_W)


## The right-hand column (signs, the activity log, the hover box): its left edge and width.
func _right_x() -> float:
	return _mid_x() + _mid_w() + COLUMN_GAP


func _right_w() -> float:
	return maxf(_panel().size.x - UiKit.SPACE_L - _right_x(), 120.0)


## Where the activity log's lines must end: the panel's foot, or above the triage cards when
## they reach under the right-hand column (a narrow panel).
func _log_bottom() -> float:
	var panel := _panel()
	var cards := _triage_rect(Vitals.TRIAGE_CARDS.size() - 1)
	if cards.end.x > panel.position.x + _right_x():
		return cards.position.y - UiKit.SPACE_S
	return panel.end.y - UiKit.SPACE_S


## How many activity log lines are drawn: as many as fit between the log's heading and its
## foot (fewer in a short window), at most MAX_LOG. The newest are the ones shown, one line
## each (cut with "..." to the column).
func log_lines_shown(font: Font) -> int:
	var panel := _panel()
	var first := panel.position.y + LOG_Y + 22.0  # the first line's baseline
	var room := _log_bottom() - font.get_descent(LOG_FONT) - first
	return clampi(int(floor(room / font.get_height(LOG_FONT))) + 1, 0, mini(MAX_LOG, log_lines.size()))


func _figure_origin() -> Vector2:
	return _panel().position + Vector2(FIGURE_X, FIGURE_TOP)


## The body part under `pos` (this control's coordinates), or &"".
func part_at(pos: Vector2) -> StringName:
	var local := (pos - _figure_origin()) / _figure_k()
	for p: StringName in PART_RECTS:
		if (PART_RECTS[p] as Rect2).has_point(local):
			return p
	return &""


func _rows_origin() -> Vector2:
	return _panel().position + Vector2(_mid_x(), ROWS_Y)


## How many item rows fit between the list's top and the triage cards.
func visible_rows() -> int:
	return maxi(int((_panel().end.y - 52.0 - _rows_origin().y) / ROW_H), 1)


## Whether option row `i` is on screen now (scrolled into the list).
func row_shown(i: int) -> bool:
	return i >= scroll and i < mini(scroll + visible_rows(), options.size())


## Where option row `i` is drawn (scrolled; only meaningful while row_shown).
func _row_rect(i: int) -> Rect2:
	return Rect2(_rows_origin() + Vector2(0, (i - scroll) * ROW_H), Vector2(_mid_w() - SCROLL_BAR_W - 4.0, ROW_H - 2))


## The scroll bar beside the rows (there whether or not the list overflows; drawn only then).
func _scroll_bar_rect() -> Rect2:
	return Rect2(_rows_origin() + Vector2(_mid_w() - SCROLL_BAR_W, 0), Vector2(SCROLL_BAR_W, visible_rows() * ROW_H - 2))


func _scroll_thumb_rect() -> Rect2:
	var bar := _scroll_bar_rect()
	var total := maxi(options.size(), 1)
	var shown := float(mini(visible_rows(), total)) / total
	return Rect2(bar.position + Vector2(0, bar.size.y * scroll / total), Vector2(bar.size.x, bar.size.y * shown))


## The triage card buttons along the panel's foot (Vitals.TRIAGE_CARDS, in order): 80 px
## each, narrower when the panel is (they stay inside it).
func _triage_rect(i: int) -> Rect2:
	var panel := _panel()
	var n := Vitals.TRIAGE_CARDS.size()
	var room := panel.size.x - UiKit.SPACE_L - _mid_x()
	var w := minf(80.0, (room - 4.0 * (n - 1)) / n)
	return Rect2(panel.position + Vector2(_mid_x() + i * (w + 4.0), panel.size.y - 44), Vector2(w, 28))


## The triage card button under `pos`, or &"".
func triage_at(pos: Vector2) -> StringName:
	for i in Vitals.TRIAGE_CARDS.size():
		if _triage_rect(i).has_point(pos):
			return Vitals.TRIAGE_CARDS[i]
	return &""


## The option row under `pos`, or -1: only rows on screen (row_shown) are hit.
func _row_at(pos: Vector2) -> int:
	for i in range(scroll, mini(scroll + visible_rows(), options.size())):
		if _row_rect(i).has_point(pos):
			return i
	return -1


## Every box the menu draws text or buttons in, by name, at the current window size (the ui
## suite checks they're all inside the window at every size and UI scale: P0-2). The item rows
## are the list's full height, filled or not.
func layout_rects() -> Dictionary:
	var panel := _panel()
	var top := panel.position
	var k := _figure_k()
	var out := {"panel": panel,
		"title": Rect2(top + Vector2(UiKit.SPACE_L, 32.0 - UiKit.FONT_HEADING), Vector2(_title_w(), UiKit.FONT_HEADING + 6)),
		"close hint": Rect2(top + Vector2(panel.size.x - UiKit.SPACE_L - CLOSE_HINT_W, 32.0 - UiKit.FONT_SMALL), Vector2(CLOSE_HINT_W, UiKit.FONT_SMALL + 6)),
		"figure": Rect2(_figure_origin(), FIGURE_SIZE * k),
		"legend": Rect2(_figure_origin() + Vector2(0, FIGURE_SIZE.y * k), Vector2(_legend_w(), LEGEND_H - UiKit.SPACE_S)),
		"part": Rect2(top + Vector2(_mid_x(), FIGURE_TOP - UiKit.FONT_HEADING), Vector2(_mid_w(), _rows_origin().y - top.y - FIGURE_TOP)),
		"items": Rect2(_rows_origin(), Vector2(_mid_w(), visible_rows() * ROW_H)),
		"signs": Rect2(top + Vector2(_right_x(), FIGURE_TOP - UiKit.FONT_BODY), Vector2(_right_w(), LOG_Y - FIGURE_TOP)),
		"log": Rect2(top + Vector2(_right_x(), LOG_Y - UiKit.FONT_BODY), Vector2(_right_w(), _log_bottom() - top.y - LOG_Y + UiKit.FONT_BODY)),
		"hover box": _hint_column()}
	for i in Vitals.TRIAGE_CARDS.size():
		out["triage %d" % i] = _triage_rect(i)
	return out


## The title's width: the panel less the close hint.
func _title_w() -> float:
	return maxf(_panel().size.x - UiKit.SPACE_L * 2.0 - CLOSE_HINT_W - UiKit.SPACE_S, 80.0)


## The hover box's column: over the right-hand column, the panel's height.
func _hint_column() -> Rect2:
	var panel := _panel()
	return Rect2(Vector2(panel.position.x + _right_x() - UiKit.SPACE_S, panel.position.y + UiKit.SPACE_XS),
		Vector2(_right_w() + UiKit.SPACE_S * 2.0, panel.size.y - UiKit.SPACE_XS * 2.0))


## `text` cut with "..." to fit `width` at `size` (one line, never past its box).
static func elide(font: Font, text: String, width: float, font_size: int) -> String:
	if width <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:  # the longest start that fits with the dots
		var mid := int((lo + hi + 1) / 2.0)
		if font.get_string_size(text.left(mid) + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges(false, true) + "..."


func _draw() -> void:
	if not visible or not is_instance_valid(target):
		return
	var vitals := Vitals.find_on(target)
	if vitals == null:
		return
	var font := get_theme_default_font()
	var panel := _panel()
	var small := UiKit.FONT_SMALL
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), UiKit.DIM_BG)
	draw_rect(panel, UiKit.PANEL_BG)
	draw_rect(panel, BORDER, false, 1.0)
	var top := panel.position
	draw_string(font, top + Vector2(UiKit.SPACE_L, 32), elide(font, "Medical: %s  (%s)" % [_who(), vitals.condition_text()], _title_w(), UiKit.FONT_HEADING),
		HORIZONTAL_ALIGNMENT_LEFT, _title_w(), UiKit.FONT_HEADING, UiKit.TEXT)
	draw_string(font, top + Vector2(panel.size.x - UiKit.SPACE_L - CLOSE_HINT_W, 32), "H / Esc to close", HORIZONTAL_ALIGNMENT_RIGHT, CLOSE_HINT_W, small, UiKit.TEXT_DIM)
	# Body diagram.
	var origin := _figure_origin()
	var k := _figure_k()
	draw_diagram(self, vitals, origin, k, part)
	var foot := origin.y + FIGURE_SIZE.y * k
	draw_string(font, Vector2(origin.x + 30 * k, foot + 20), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiKit.TEXT_DIM)
	draw_string(font, Vector2(origin.x + 180 * k, foot + 20), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiKit.TEXT_DIM)
	draw_multiline_string(font, Vector2(origin.x, foot + 40), "Red: bleeding\nAmber: untreated  Green: treated", HORIZONTAL_ALIGNMENT_LEFT, _legend_w(), small, 3, UiKit.TEXT_DIM)
	# The chosen part: injuries and items.
	var mid_w := _mid_w()
	var mid := top + Vector2(_mid_x(), FIGURE_TOP)
	draw_string(font, mid, elide(font, InteractionMenu.part_name(part), mid_w, UiKit.FONT_HEADING), HORIZONTAL_ALIGNMENT_LEFT, mid_w, UiKit.FONT_HEADING, UiKit.TEXT)
	draw_multiline_string(font, mid + Vector2(0, 24), injuries_text(vitals, part), HORIZONTAL_ALIGNMENT_LEFT, mid_w, small, INJURY_LINES, UiKit.TEXT)
	var overflow := options.size() > visible_rows()
	var heading := "Your medical items"
	if overflow:
		heading += "  (%d-%d of %d: scroll)" % [scroll + 1, mini(scroll + visible_rows(), options.size()), options.size()]
	draw_string(font, _rows_origin() - Vector2(0, 8), elide(font, heading, mid_w, small), HORIZONTAL_ALIGNMENT_LEFT, mid_w, small, UiKit.ACCENT)
	if options.is_empty():
		draw_string(font, _rows_origin() + Vector2(0, 16), "You carry no medical items", HORIZONTAL_ALIGNMENT_LEFT, mid_w, small, UiKit.TEXT_DIM)
	if overflow:
		draw_rect(_scroll_bar_rect(), BORDER.darkened(0.4))
		draw_rect(_scroll_thumb_rect(), UiKit.TEXT_DIM)
	for i in range(scroll, mini(scroll + visible_rows(), options.size())):
		var rect := _row_rect(i)
		var entry := options[i]
		var greyed := String(entry.disabled) != ""
		if i == _hover and not greyed:
			draw_rect(rect, HOVER_BG)
		var text: String = entry.label + ("  -  " + String(entry.disabled) if greyed else "")
		var baseline := rect.position.y + (rect.size.y + font.get_ascent(small) - font.get_descent(small)) * 0.5
		draw_string(font, Vector2(rect.position.x + 6, baseline), elide(font, text, rect.size.x - 10, small), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, small,
			UiKit.TEXT_DIM if greyed else UiKit.TEXT)
	# Triage card buttons.
	var card := vitals.triage()
	for i in Vitals.TRIAGE_CARDS.size():
		var id: StringName = Vitals.TRIAGE_CARDS[i]
		var tr := _triage_rect(i)
		draw_rect(tr, Vitals.TRIAGE_COLORS[id].darkened(0.0 if id == card else 0.55))
		draw_rect(tr, Color.WHITE if id == card else Color(0.15, 0.15, 0.15), false, 3.0 if id == card else 1.0)
		var baseline := tr.position.y + (tr.size.y + font.get_ascent(small) - font.get_descent(small)) * 0.5
		draw_string(font, Vector2(tr.position.x + 2, baseline), elide(font, id.capitalize(), tr.size.x - 4, small), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x - 4, small,
			Color.BLACK if id in [Vitals.TRIAGE_MINIMAL, Vitals.TRIAGE_DELAYED] else Color.WHITE)
	# Signs (numbers only with a pulse oximeter) and the activity log.
	var right_w := _right_w()
	var right := top + Vector2(_right_x(), FIGURE_TOP)
	draw_string(font, right, "Signs", HORIZONTAL_ALIGNMENT_LEFT, right_w, UiKit.FONT_BODY, UiKit.ACCENT)
	var sign_lines := signs_lines(vitals, target == actor, InteractionMenu.has_oximeter(actor))
	draw_multiline_string(font, right + Vector2(0, 22), "\n".join(sign_lines), HORIZONTAL_ALIGNMENT_LEFT, right_w, small, SIGN_LINES, UiKit.TEXT)
	var log_top := top + Vector2(_right_x(), LOG_Y)
	draw_string(font, log_top, elide(font, "Activity (this menu, your view)", right_w, UiKit.FONT_BODY), HORIZONTAL_ALIGNMENT_LEFT, right_w, UiKit.FONT_BODY, UiKit.ACCENT)
	var shown := log_lines_shown(font)
	var line_h := font.get_height(LOG_FONT)
	for n in shown:  # the newest lines, as many as fit above the log's foot, one line each
		var line := log_lines[log_lines.size() - shown + n]
		draw_string(font, log_top + Vector2(0, 22 + n * line_h), elide(font, line, right_w, LOG_FONT), HORIZONTAL_ALIGNMENT_LEFT, right_w, LOG_FONT, UiKit.TEXT_DIM)
	# The row under the mouse: why it's greyed out, and what that treatment does, over the
	# right-hand column (a narrow row cuts the reason short; the box has it whole).
	if _hover >= 0 and _hover < options.size() and row_shown(_hover):
		var hint := row_hint(options[_hover])
		var why := String(options[_hover].get("disabled", ""))
		if why != "":
			hint = why + ("\n" + hint if hint != "" else "")
		if hint != "":
			var column := _hint_column()
			var text_w := column.size.x - 16.0
			var text_h := font.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, text_w, small).y
			var box := Rect2(Vector2(column.position.x, _row_rect(_hover).position.y), Vector2(column.size.x, minf(text_h + 16, column.size.y)))
			box.position.y = clampf(box.position.y, column.position.y, column.end.y - box.size.y)
			var lines := maxi(int((box.size.y - 16) / font.get_height(small)), 1)
			draw_rect(box, UiKit.PANEL_BG.lerp(Color.BLACK, 0.4))
			draw_rect(box, UiKit.ACCENT, false, 1.0)
			draw_multiline_string(font, box.position + Vector2(8, 8 + font.get_ascent(small)), hint, HORIZONTAL_ALIGNMENT_LEFT, text_w, small,
				lines, UiKit.TEXT)


## What a row does, in words, for the hover box (Captain, 2026-10-14: "item descriptions plus
## uses also needed"): an item's description and uses (ItemInfo), or Remove tourniquet's rule.
## Kept short: one line per use, wrapped by the box.
static func row_hint(entry: Dictionary) -> String:
	if entry.get("id", &"") == &"remove_tourniquet":
		var tq := ItemDB.get_item(WoundModel.TOURNIQUET)
		return "Takes the tourniquets off this limb (%.0f s) once every arterial bleed under them is packed with gauze. They go back in your kit." % float(tq.stats.get("remove_s", 3.0))
	var id: StringName = entry.get("item", &"")
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	if item == null:
		return ""
	var lines := PackedStringArray([item.desc]) if item.desc != "" else PackedStringArray()
	for use in item.uses:
		lines.append("- " + use)
	return "\n".join(lines)
