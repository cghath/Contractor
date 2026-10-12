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
const DRESSING := &"dressing"
const SEAL := &"seal"
const IV := &"iv"
const IO := &"io"
const MARKER_TEXT := {TOURNIQUET: "TQ", SPLINT: "SPL", DRESSING: "DR", SEAL: "SEAL", IV: "IV", IO: "IO"}
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
const PANEL_SIZE := Vector2(1080.0, 620.0)
const ROW_H := 24.0
const MAX_LOG := 14
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
		part = p
		refresh()


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
	_watch(Vitals.find_on(target))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"medical_menu") or event.is_action_pressed(&"pause"):
		close()
	if event is InputEventKey:
		get_viewport().set_input_as_handled()  # the menu has the keys: no reloading or throwing behind it


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row := _row_at(event.position)
		if row != _hover:
			_hover = row
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := part_at(event.position)
		if p != &"":
			select_part(p)
		elif triage_at(event.position) != &"":
			set_triage(triage_at(event.position))
		else:
			var text := choose(_row_at(event.position))
			if text != "" and actor.player_input:
				actor.player_input.flash(text)
		accept_event()


# --- What it shows (static: tests and other views use these) -------------------------------

## The person `actor` looks at within treatment reach (Soldier._in_treat_reach: to the body,
## Soldier.body_point, where a ragdoll lies), or null. Nearest the middle of the view first.
static func looked_at(actor: Soldier, camera: Camera3D) -> Node3D:
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best: Node3D = null
	var best_angle := deg_to_rad(InteractionMenu.VIEW_CONE_DEG)
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
		if angle < best_angle and actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			best = s
			best_angle = angle
	return best


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


## One part's state: "state" (OK, BLEEDING, UNTREATED, TREATED), "severity" (0, or 1..3 while
## bleeding) and "markers" (TOURNIQUET, SPLINT, DRESSING, SEAL, IV, IO).
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
			var marker: StringName = SPLINT if kind == "fracture" else (SEAL if kind == "chest" else (DRESSING if kind in DRESSED_KINDS else &""))
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
		if not Vitals.has_item(treater.inventory, id):
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

func _panel() -> Rect2:
	var screen := get_viewport_rect().size
	return Rect2((screen - PANEL_SIZE) * 0.5, PANEL_SIZE)


func _figure_origin() -> Vector2:
	return _panel().position + Vector2(30, 70)


## The body part under `pos` (this control's coordinates), or &"".
func part_at(pos: Vector2) -> StringName:
	var local := pos - _figure_origin()
	for p: StringName in PART_RECTS:
		if (PART_RECTS[p] as Rect2).has_point(local):
			return p
	return &""


func _rows_origin() -> Vector2:
	return _panel().position + Vector2(290, 230)


func _row_rect(i: int) -> Rect2:
	return Rect2(_rows_origin() + Vector2(0, i * ROW_H), Vector2(400, ROW_H - 2))


## The triage card buttons along the panel's foot (Vitals.TRIAGE_CARDS, in order).
func _triage_rect(i: int) -> Rect2:
	return Rect2(_panel().position + Vector2(290 + i * 84, PANEL_SIZE.y - 44), Vector2(80, 28))


## The triage card button under `pos`, or &"".
func triage_at(pos: Vector2) -> StringName:
	for i in Vitals.TRIAGE_CARDS.size():
		if _triage_rect(i).has_point(pos):
			return Vitals.TRIAGE_CARDS[i]
	return &""


func _row_at(pos: Vector2) -> int:
	for i in options.size():
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _draw() -> void:
	if not visible or not is_instance_valid(target):
		return
	var vitals := Vitals.find_on(target)
	if vitals == null:
		return
	var font := get_theme_default_font()
	var panel := _panel()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.45))
	draw_rect(panel, Color(0.08, 0.09, 0.1, 0.94))
	draw_rect(panel, Color(0.4, 0.42, 0.45), false, 1.0)
	var top := panel.position
	draw_string(font, top + Vector2(20, 32), "Medical: %s  (%s)" % [_who(), vitals.condition_text()], HORIZONTAL_ALIGNMENT_LEFT, 760, 20)
	draw_string(font, top + Vector2(PANEL_SIZE.x - 210, 32), "H / Esc to close", HORIZONTAL_ALIGNMENT_RIGHT, 190, 14, Color(0.7, 0.7, 0.7))
	# Body diagram.
	var origin := _figure_origin()
	for p: StringName in PART_RECTS:
		var r: Rect2 = PART_RECTS[p]
		r.position += origin
		var state := part_state(vitals, p)
		draw_rect(r, state_color(state))
		draw_rect(r, Color.WHITE if p == part else Color(0.15, 0.15, 0.15), false, 3.0 if p == part else 1.0)
		var y := r.position.y + 13.0
		for m: StringName in state.markers:
			if m == TOURNIQUET:
				draw_rect(Rect2(r.position.x - 2, r.position.y + 4, r.size.x + 4, 5), Color(0.05, 0.05, 0.05))
			draw_string(font, Vector2(r.position.x + 2, y + 8), MARKER_TEXT[m], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 11, Color.WHITE)
			y += 12.0
	draw_string(font, origin + Vector2(30, FIGURE_SIZE.y + 22), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
	draw_string(font, origin + Vector2(180, FIGURE_SIZE.y + 22), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
	draw_string(font, origin + Vector2(0, FIGURE_SIZE.y + 44), "Red: bleeding  Amber: untreated  Green: treated", HORIZONTAL_ALIGNMENT_LEFT, 250, 11, Color(0.7, 0.7, 0.7))
	# The chosen part: injuries and items.
	var mid := top + Vector2(290, 70)
	draw_string(font, mid, InteractionMenu.part_name(part), HORIZONTAL_ALIGNMENT_LEFT, 400, 18)
	draw_multiline_string(font, mid + Vector2(0, 24), injuries_text(vitals, part), HORIZONTAL_ALIGNMENT_LEFT, 400, 14, 6)
	draw_string(font, _rows_origin() - Vector2(0, 8), "Your medical items", HORIZONTAL_ALIGNMENT_LEFT, 400, 15, Color(0.8, 0.8, 0.8))
	if options.is_empty():
		draw_string(font, _rows_origin() + Vector2(0, 16), "You carry no medical items", HORIZONTAL_ALIGNMENT_LEFT, 400, 14, Color(0.6, 0.6, 0.6))
	for i in options.size():
		var rect := _row_rect(i)
		if rect.end.y > panel.end.y - 52:
			break
		var entry := options[i]
		var greyed := String(entry.disabled) != ""
		if i == _hover and not greyed:
			draw_rect(rect, Color(0.25, 0.4, 0.3))
		var text: String = entry.label + ("  -  " + String(entry.disabled) if greyed else "")
		draw_string(font, rect.position + Vector2(6, 16), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 13,
			Color(0.5, 0.5, 0.5) if greyed else Color.WHITE)
	# Triage card buttons.
	var card := vitals.triage()
	for i in Vitals.TRIAGE_CARDS.size():
		var id: StringName = Vitals.TRIAGE_CARDS[i]
		var tr := _triage_rect(i)
		draw_rect(tr, Vitals.TRIAGE_COLORS[id].darkened(0.0 if id == card else 0.55))
		draw_rect(tr, Color.WHITE if id == card else Color(0.15, 0.15, 0.15), false, 3.0 if id == card else 1.0)
		draw_string(font, tr.position + Vector2(4, 19), id.capitalize(), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x - 8, 12,
			Color.BLACK if id in [Vitals.TRIAGE_MINIMAL, Vitals.TRIAGE_DELAYED] else Color.WHITE)
	# Signs (numbers only with a pulse oximeter) and the activity log.
	var right := top + Vector2(720, 70)
	draw_string(font, right, "Signs", HORIZONTAL_ALIGNMENT_LEFT, 340, 16)
	var sign_lines := signs_lines(vitals, target == actor, InteractionMenu.has_oximeter(actor))
	draw_multiline_string(font, right + Vector2(0, 22), "\n".join(sign_lines), HORIZONTAL_ALIGNMENT_LEFT, 340, 13, 8)
	var log_top := right + Vector2(0, 240)
	draw_string(font, log_top, "Activity (this menu, your view)", HORIZONTAL_ALIGNMENT_LEFT, 340, 16)
	draw_multiline_string(font, log_top + Vector2(0, 22), "\n".join(log_lines), HORIZONTAL_ALIGNMENT_LEFT, 340, 12, MAX_LOG, Color(0.8, 0.8, 0.8))
