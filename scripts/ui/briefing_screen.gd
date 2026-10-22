class_name BriefingScreen
extends PanelContainer
## The briefing's side panel on the map (MapScreen): the contract, its objectives, how many
## enemy positions intel gives (red on the map), the insertion point, the supports to bring,
## who is ready, a Ready button for everyone and Start for the host. Plan marks are drawn on
## the map itself. Everything goes through Briefing's requests; the host decides. In the shared
## look (UiKit, from MapScreen): body text 16 px, section heads and notes 14 px, nothing smaller
## and nothing faded (the UI audit found 12-13 px at 60%).

## The panel's widest, and narrowest (Captain, 2026-10-14, B0912: the panel ran off the window's
## right edge: the insertion list was as wide as its longest name). Its width follows the window
## (width_for); text wraps, a long choice is cut short with "..." (its whole text in a tooltip),
## and a tall panel scrolls.
const WIDTH := 360.0
const MIN_WIDTH := 240.0
## The most of the window's width it takes.
const MAX_SHARE := 0.3

var _briefing: Briefing
var _box: VBoxContainer
var _title: Label
var _summary: Label
var _objectives: Label
var _intel: Label
var _insertion: OptionButton
var _approach: OptionButton
var _drop: OptionButton
var _supports: VBoxContainer
var _players: Label
var _ready_button: Button
var _start: Button
var _width := WIDTH
## claude/mission-ui: the job at a glance (ContractGlance), the 3D look at the plan, and the
## last plan's drop, approach and supports in one click.
var _glance: VBoxContainer
var _relief: Button
var _last_plan: Button
var _players_head: Label
## The figures the narrow panel shows (ContractGlance keys); the board shows them all.
const GLANCE_KEYS := ["pay", "risk", "threat", "intel", "conditions", "time", "squads"]


## The panel's width in a window (or map screen) `screen_width` wide.
static func width_for(screen_width: float) -> float:
	return clampf(screen_width * MAX_SHARE, MIN_WIDTH, WIDTH)


## Sets the panel's width (MapScreen, as the window changes).
func set_panel_width(w: float) -> void:
	_width = w
	custom_minimum_size = Vector2(w, 0)


func _ready() -> void:
	custom_minimum_size = Vector2(_width, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	scroll.add_child(_box)
	_box.add_child(ContractGlance.flow("Brief"))
	_title = _add_label("", &"HeadingLabel")
	_box.add_child(UiKit.subtitle("Plan the insertion: how you go in, where, and which supports come with you", false))  # (ui-modern)
	_glance = VBoxContainer.new()
	_box.add_child(_glance)
	_summary = _add_label("")
	_add_head("OBJECTIVES")
	_objectives = _add_label("")
	_intel = _add_label("")
	# The natural next step after reading the job: look at the plan on the ground (C5's 3D map).
	_relief = Button.new()
	_fit_button(_relief)
	_relief.name = "LookAtPlan"
	_relief.theme_type_variation = &"AccentButton"
	_relief.text = "Look at the plan in 3D"
	_relief.tooltip_text = "The plan in relief: objectives, insertion points and known enemies on the zone's ground. Wheel: zoom, middle-drag: orbit, WASD: pan"
	_relief.pressed.connect(func() -> void:
		var screen := get_parent() as MapScreen
		if screen:
			screen.toggle_3d_map()
		_relief_text())
	UiKit.hotkey(_relief, KEY_V)
	_box.add_child(_relief)
	_add_head("INSERTION")
	_insertion = OptionButton.new()
	_insertion.fit_to_longest_item = false
	_insertion.clip_text = true
	_insertion.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_insertion.tooltip_text = "Where the squad goes in (a green triangle on the map)"
	_insertion.item_selected.connect(func(index: int) -> void:
		if _briefing:
			_briefing.request_insertion(String(_insertion.get_item_metadata(index))))
	_box.add_child(_insertion)
	## A helicopter insertion's way in and down (Captain, 2026-10-17).
	_approach = OptionButton.new()
	_approach.add_item("Helicopter comes in: planner's pick")
	_approach.set_item_metadata(0, -1)
	for i in HeliRoute.SIDES.size():
		_approach.add_item("Helicopter comes in from the %s" % HeliRoute.SIDES[i])
		_approach.set_item_metadata(i + 1, i)
	_approach.tooltip_text = "The side the helicopter comes in from"
	_approach.item_selected.connect(func(index: int) -> void:
		if _briefing:
			_remember("briefing_approach", int(_approach.get_item_metadata(index)))
			_briefing.request_approach(int(_approach.get_item_metadata(index))))
	_box.add_child(_approach)
	_drop = OptionButton.new()
	_drop.add_item("Helicopter lands (hot drop: in fast, out the doors)")
	_drop.set_item_metadata(0, "land")
	_drop.add_item("Fast-rope from the hover")
	_drop.set_item_metadata(1, "rope")
	_drop.tooltip_text = "How the squad gets off the helicopter"
	_drop.item_selected.connect(func(index: int) -> void:
		if _briefing:
			_remember("briefing_drop", String(_drop.get_item_metadata(index)))
			_briefing.request_drop(String(_drop.get_item_metadata(index))))
	_box.add_child(_drop)
	_add_head("SUPPORTS")
	_supports = VBoxContainer.new()
	_box.add_child(_supports)
	_last_plan = Button.new()
	_fit_button(_last_plan)
	_last_plan.name = "LastPlan"
	_last_plan.text = "Use my last plan"
	_last_plan.tooltip_text = "The helicopter drop, approach and supports you picked last time"
	_last_plan.pressed.connect(use_last_plan)
	UiKit.hotkey(_last_plan, KEY_L)
	_box.add_child(_last_plan)
	_players_head = _add_head("PLAYERS")
	_players = _add_label("")
	_ready_button = Button.new()
	_ready_button.name = "Ready"
	_ready_button.toggle_mode = true
	_fit_button(_ready_button)
	_ready_button.theme_type_variation = &"AccentButton"
	_ready_button.text = "Ready"
	_ready_button.toggled.connect(func(on: bool) -> void:
		if _briefing:
			_briefing.request_set_ready(on))
	UiKit.hotkey(_ready_button, KEY_R)
	_box.add_child(_ready_button)
	_start = Button.new()
	_start.name = "Start"
	_fit_button(_start)
	_start.theme_type_variation = &"AccentButton"
	_start.text = "Start deployment"
	_start.pressed.connect(func() -> void:
		if _briefing:
			_briefing.request_start())
	UiKit.hotkey(_start, KEY_G)
	_box.add_child(_start)
	_add_label("Plan on the map: double-click for a marker, Ctrl + drag for a line, drag to move, Delete to remove. Click a green triangle to pick the insertion point. \"?\" lists every control.", &"HintLabel")


## Shows `briefing`'s state (call again whenever it changes).
func show_briefing(briefing: Briefing) -> void:
	_briefing = briefing
	if briefing == null:
		return
	var c := briefing.contract
	var stars := int(c.get("difficulty", 0))
	_title.text = String(c.get("title", "Contract")) + ("  " + "*".repeat(stars) if stars > 0 else "")
	_summary.text = String(c.get("summary", ""))
	# The held contract behind the briefing (its pay, intel, conditions...), else the briefing's own.
	var held := Contracts.contract(String(c.get("id", ""))) if String(c.get("id", "")) != "" else {}
	for child in _glance.get_children():
		_glance.remove_child(child)
		child.queue_free()
	var shown := held if not held.is_empty() else {"rated": stars, "state": "accepted"}
	if not held.is_empty() or stars > 0:
		_glance.add_child(ContractGlance.strip(shown, GLANCE_KEYS))
	var lines := PackedStringArray()
	var templates: Array = held.get("objectives", [])
	if not templates.is_empty():
		for o: Dictionary in templates:
			lines.append("- %s%s" % [ContractBoard.objective_tag(o), String(o.get("text", ""))])
	else:
		for o: Dictionary in c.get("objectives", []):
			lines.append("- %s" % String(o.get("title", "")))
	_objectives.text = "\n".join(lines) if not lines.is_empty() else "(none given)"
	_relief_text()
	var known: int = c.get("known_enemies", []).size()
	_intel.text = "Intel: %d known enemy position%s (red on the map)" % [known, "" if known == 1 else "s"] if known > 0 else "Intel: no known enemy positions"
	_insertion.clear()
	for point: Dictionary in briefing.insertion_points():
		_insertion.add_item("%s (%s)" % [String(point.get("name", "")), Briefing.method_text(point)])  # wave 5b
		_insertion.set_item_metadata(_insertion.item_count - 1, String(point.get("id", "")))
		if String(point.get("id", "")) == briefing.insertion_id:
			_insertion.select(_insertion.item_count - 1)
	_insertion.tooltip_text = _insertion.text
	var heli := String(briefing.insertion().get("method", "foot")) == Briefing.HELI
	_approach.visible = heli
	_drop.visible = heli
	_approach.select(briefing.approach + 1)
	_drop.select(maxi(Briefing.DROPS.find(briefing.drop), 0))
	for child in _supports.get_children():
		child.queue_free()
	for id: String in briefing.available_supports():
		var box := CheckBox.new()
		_fit_button(box)
		box.text = briefing.support_name(id)  # wave 5b: motor pool vehicles too
		box.tooltip_text = box.text
		box.set_pressed_no_signal(id in briefing.supports)
		box.toggled.connect(func(on: bool) -> void:
			var picked: Array = briefing.supports.duplicate()
			if on and not id in picked:
				picked.append(id)
			elif not on:
				picked.erase(id)
			_remember("briefing_supports", picked)
			briefing.request_support(id, on))
		_supports.add_child(box)
	if _supports.get_child_count() == 0:
		var none := Label.new()
		none.text = "None allowed on this job"
		none.theme_type_variation = &"HintLabel"
		_supports.add_child(none)
	_last_plan.visible = not last_plan_differs(briefing).is_empty()
	var me := multiplayer.get_unique_id()
	var who := PackedStringArray()
	var waiting := PackedStringArray()
	var peers := briefing.session_peers()
	for id: int in peers:
		var who_name := "You" if id == me else "Player %d" % id
		who.append("%s: %s" % [who_name, "ready" if briefing.ready_peers.has(id) else "not ready"])
		if not briefing.ready_peers.has(id):
			waiting.append(who_name)
	_players_head.text = "PLAYERS: %d OF %d READY" % [peers.size() - waiting.size(), peers.size()]
	_players.text = "\n".join(who)
	_ready_button.set_pressed_no_signal(briefing.ready_peers.has(me))
	_ready_button.text = ("Ready (click to stand down)" if _ready_button.button_pressed else "Ready") + "  [R]"
	_start.visible = multiplayer.is_server()
	_start.disabled = not briefing.all_ready()
	_start.tooltip_text = "Start the deployment for everyone (G)" if waiting.is_empty() else "Waiting for: %s (G)" % ", ".join(waiting)


## The 3D look's button says what pressing it does now.
func _relief_text() -> void:
	var screen := get_parent() as MapScreen
	var on := screen != null and screen.map_3d != null
	_relief.text = ("Back to the 2D map" if on else "Look at the plan in 3D") + "  [V]"


## What the last plan would change on `briefing` now: {"drop", "approach", "supports"} for each
## that differs (only what still applies: the drop and approach on a helicopter insertion, the
## supports this job allows).
static func last_plan_differs(briefing: Briefing) -> Dictionary:
	var out := {}
	if briefing == null:
		return out
	var heli := String(briefing.insertion().get("method", "foot")) == Briefing.HELI
	var drop := String(GameSettings.get_value("mission_ui", "briefing_drop"))
	if heli and drop in Briefing.DROPS and drop != briefing.drop:
		out["drop"] = drop
	var side := int(GameSettings.get_value("mission_ui", "briefing_approach"))
	if heli and side >= -1 and side != briefing.approach:
		out["approach"] = side
	var allowed := briefing.available_supports()
	var want: Array = (GameSettings.get_value("mission_ui", "briefing_supports") as Array).filter(func(id: Variant) -> bool: return String(id) in allowed)
	var have: Array = briefing.supports.duplicate()
	want.sort()
	have.sort()
	if not want.is_empty() and want != have:
		out["supports"] = want
	return out


## Asks the host for the last plan's drop, approach and supports (one click, "L").
func use_last_plan() -> void:
	if _briefing == null:
		return
	var diff := last_plan_differs(_briefing)
	if diff.has("drop"):
		_briefing.request_drop(String(diff.drop))
	if diff.has("approach"):
		_briefing.request_approach(int(diff.approach))
	if diff.has("supports"):
		for id: String in _briefing.available_supports():
			var on: bool = id in diff.supports
			if on != (id in _briefing.supports):
				_briefing.request_support(id, on)


static func _remember(key: String, value: Variant) -> void:
	if GameSettings.get_value("mission_ui", key) != value:
		GameSettings.set_value("mission_ui", key, value)


## A wrapping line of text in label style `variation` ("" for body text).
func _add_label(text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # (the panel's width, less the theme's padding)
	if variation != &"":
		label.theme_type_variation = variation
	_box.add_child(label)
	return label


## A section's head: small, in the accent colour.
func _add_head(text: String) -> Label:
	var label := _add_label(text, &"HintLabel")
	label.add_theme_color_override(&"font_color", UiKit.ACCENT)
	return label


## A button that never widens the panel: a long text is cut short with "...".
static func _fit_button(button: Button) -> void:
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
