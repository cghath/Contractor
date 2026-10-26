class_name ObjectivesPanel
extends PanelContainer
## The deployment's objectives in the HUD's top-right corner (wave 4, W10): one line each,
## [ ] active, [x] done, [-] failed, from the replicated Contracts.objectives. Hidden when
## there's no deployment. Contract messages (signed, voided, civilian casualties) flash on
## the HUD while it's up.
## claude/mission-ui: the heading counts the required ones done ("3/5 done"); a live objective
## says which way and how far it is from you ("NW, 340 m"); a bonus or optional one says so; and
## within a contract the live ones come first, then the done, then the failed. What to do next
## is the helper's line under the panel (ObjectiveHelper).

## Its width (logical px); the Hud's top-right zone is this wide, or less on a narrow window.
const WIDTH := 364.0

var _label: Label
var _poll := 0.0
## A test stand-in for the whole text (ui_test fits long lists without a deployment).
var preview := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Placed by the Hud's top-right zone; these anchors only count on its own (ui_test).
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -16.0 - WIDTH
	offset_right = -16.0
	offset_top = 16.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# The theme's translucent HUD panel and body text (docs/ui_audit.md P2-19: its own StyleBox
	# and 15 px text before).
	UiKit.apply(self)
	theme_type_variation = &"HudPanel"
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## ui-modern: the HUD's outlined small style (a shadowed 16 px label read badly over bright sky).
	_label.theme_type_variation = &"HudSmallLabel"
	add_child(_label)
	Contracts.objectives.changed.connect(refresh)
	get_viewport().size_changed.connect(refresh)
	Contracts.notice.connect(_on_notice)
	refresh()


func refresh() -> void:
	if preview != "":
		_label.text = preview
		_fit_height()
		return
	var list: Array = Contracts.objectives.list
	visible = not list.is_empty()
	var dep := Contracts.deployment()
	var civilians := int(dep.get("civilians", 0))
	var active := active_oid()
	var required := list.filter(func(o: Dictionary) -> bool: return not bool(o.get("optional", false)))
	var done := required.filter(func(o: Dictionary) -> bool: return String(o.get("state", "")) == Objectives.DONE).size()
	var head := "OBJECTIVES %d/%d done%s" % [done, required.size(), (" - " + String(dep.zone_name) if dep.has("zone_name") else "")]
	var from: Variant = _player_pos()
	var keys := "[%s] %s" % [_key("objectives_toggle"), "list" if compact() else "compact"]
	var pickable := ObjectiveHelper.pickable(list)
	if pickable.size() > 1:
		keys += "  [%s] next" % _key("objectives_next")
	var body := PackedStringArray()
	if compact():
		var shown: Dictionary = {}
		for o: Dictionary in list:
			if String(o.get("oid", "")) == active:
				shown = o
		if shown.is_empty() and not list.is_empty():
			shown = pickable[0] if not pickable.is_empty() else list[0]
		if not shown.is_empty():
			body.append("> " + entry(shown, from))
		var more := list.size() - (1 if not shown.is_empty() else 0)
		if more > 0:
			body.append("+%d more" % more)
	else:
		var cids: Array = []
		for o: Dictionary in list:
			if not String(o.get("cid", "")) in cids:
				cids.append(String(o.get("cid", "")))
		for cid: String in cids:
			if cids.size() > 1:
				var c := Contracts.contract(cid)
				body.append("-- %s --" % String(c.get("title", c.get("zone_name", cid))))
			for o: Dictionary in ordered(list.filter(func(x: Dictionary) -> bool: return String(x.get("cid", "")) == cid)):
				body.append(("> " if String(o.get("oid", "")) == active else "") + entry(o, from))
	if civilians > 0 and not compact():
		body.append("Civilian casualties: %d of %d" % [civilians, MissionRegistry.setting_i("civilian_void_at", 8)])
	_label.text = "%s  (%s)
%s" % [head, keys, "
".join(body)]
	_fit_height()


## The full list never grows past the window: lines past what fits are cut (the active
## objective's line stays: it's moved first), the panel says so on its last line.
func _fit_height() -> void:
	var view := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)
	var font := _label.get_theme_font(&"font")
	var fs := _label.get_theme_font_size(&"font_size")
	var width := clampf(view.x * 0.3, 240.0, WIDTH) - get_theme_stylebox(&"panel").get_minimum_size().x
	var room := maxf(view.y - 150.0 - _above(), 200.0)  # the hint line and the corner margin below and above, and what's over it (the operation strip)
	var lines := _label.text.split("
")
	var used := 0.0
	var keep := 0
	for line: String in lines:
		var h := font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, width, fs).y
		if used + h > room - (font.get_height(fs) if keep < lines.size() - 1 else 0.0):
			break
		used += h
		keep += 1
	if keep < lines.size():
		keep = maxi(keep, 2)
		_label.text = "
".join(lines.slice(0, keep)) + "
+%d more (%s: next)" % [lines.size() - keep, _key("objectives_next")]


## The height of what shows over the panel in its zone (the operation strip, D3).
func _above() -> float:
	var parent := get_parent()
	if parent == null:
		return 0.0
	var h := 0.0
	for n in parent.get_children():
		if n == self:
			break
		if n is Control and (n as Control).visible:
			h += (n as Control).get_combined_minimum_size().y
			if parent is BoxContainer:
				h += float((parent as BoxContainer).get_theme_constant(&"separation"))
	return h


## One objective's line: its state and text (Objectives.line), "(bonus)" or "(optional)" when it
## isn't required and doesn't say so, and, still live and placed, which way and how far from
## `from` (null: not known).
static func entry(o: Dictionary, from: Variant) -> String:
	var out := Objectives.line(o)
	if bool(o.get("optional", false)) and not String(o.get("text", "")).to_lower().begins_with("bonus"):
		out += " (bonus)" if float(o.get("bonus_share", 0.0)) > 0.0 else " (optional)"
	if from is Vector3 and String(o.get("state", "")) == Objectives.ACTIVE:
		var at := ObjectiveHelper.target_pos(o, {})
		if at != Vector3.ZERO:
			out += "  " + ObjectiveHelper.where_text(from, at)
	return out


## A contract's objectives in the order the panel lists them: live required ones, live optional
## ones, then done, then failed (each group in its own order).
static func ordered(objectives: Array) -> Array:
	var rank := func(o: Dictionary) -> int:
		match String(o.get("state", "")):
			Objectives.DONE:
				return 2
			Objectives.FAILED:
				return 3
		return 1 if bool(o.get("optional", false)) else 0
	var out: Array = []
	for r in 4:
		out.append_array(objectives.filter(func(o: Dictionary) -> bool: return rank.call(o) == r))
	return out


## Where this peer's player stands (null without one).
func _player_pos() -> Variant:
	var helper := get_tree().get_first_node_in_group(ObjectiveHelper.GROUP) as ObjectiveHelper if is_inside_tree() else null
	if helper and is_instance_valid(helper.player) and helper.player.is_inside_tree():
		return helper.player.global_position
	return null


## Compact mode: only the active objective, and how many more there are.
func compact() -> bool:
	return not bool(GameSettings.get_value("hud", "objectives_expanded"))


## The oid the HUD hint is working on: the player's pick, else the helper's nearest.
func active_oid() -> String:
	var helper := get_tree().get_first_node_in_group(ObjectiveHelper.GROUP) as ObjectiveHelper if is_inside_tree() else null
	if helper:
		var oid := String(helper.current.get("oid", ""))
		if oid != "":
			return oid
	return Objectives.chosen_oid


## Flips compact / full (the O key), saved in settings.
func toggle_compact() -> void:
	GameSettings.set_value("hud", "objectives_expanded", compact())
	refresh()


## Picks the next active objective (the N key): drives the hint and marker.
func cycle() -> void:
	var helper := get_tree().get_first_node_in_group(ObjectiveHelper.GROUP) as ObjectiveHelper
	if helper:
		helper.cycle_choice()
	refresh()


func _key(action: StringName) -> String:
	return GameSettings.binding_name(GameSettings.key_for(action))


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0 and visible:
		_poll = 0.25
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var hud := Hud.of(self)
	if hud and (hud.is_inventory_open() or (hud.map_screen and hud.map_screen.visible)):
		return
	if event.is_action_pressed(&"objectives_toggle"):
		toggle_compact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"objectives_next"):
		cycle()
		get_viewport().set_input_as_handled()


## What the panel shows (tests read it).
func text() -> String:
	return _label.text if visible else ""


func _on_notice(text: String) -> void:
	var hud := Hud.of(self)
	if hud and visible:
		hud.flash(text)
