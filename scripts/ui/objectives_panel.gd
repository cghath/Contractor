class_name ObjectivesPanel
extends PanelContainer
## The deployment's objectives in the HUD's top-right corner (wave 4, W10): one line each,
## [ ] active, [x] done, [-] failed, from the replicated Contracts.objectives. Hidden when
## there's no deployment. Contract messages (signed, voided, civilian casualties) flash on
## the HUD while it's up.

## Its width (logical px); the Hud's top-right zone is this wide, or less on a narrow window.
const WIDTH := 364.0

var _label: Label
var _poll := 0.0


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
	add_child(_label)
	Contracts.objectives.changed.connect(refresh)
	Contracts.notice.connect(_on_notice)
	refresh()


func refresh() -> void:
	var list: Array = Contracts.objectives.list
	visible = not list.is_empty()
	var dep := Contracts.deployment()
	var civilians := int(dep.get("civilians", 0))
	var active := active_oid()
	var head := "OBJECTIVES%s" % (" - " + String(dep.zone_name) if dep.has("zone_name") else "")
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
			body.append("> " + Objectives.line(shown))
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
			for o: Dictionary in list:
				if String(o.get("cid", "")) == cid:
					body.append(("> " if String(o.get("oid", "")) == active else "") + Objectives.line(o))
	if civilians > 0 and not compact():
		body.append("Civilian casualties: %d of %d" % [civilians, MissionRegistry.setting_i("civilian_void_at", 8)])
	_label.text = "%s  (%s)
%s" % [head, keys, "
".join(body)]


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
