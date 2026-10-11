class_name ObjectivesPanel
extends PanelContainer
## The deployment's objectives in the HUD's top-right corner (wave 4, W10): one line each,
## [ ] active, [x] done, [-] failed, from the replicated Contracts.objectives. Hidden when
## there's no deployment. Contract messages (signed, voided, civilian casualties) flash on
## the HUD while it's up.

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -380.0
	offset_right = -16.0
	offset_top = 16.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.05, 0.6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override(&"panel", style)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override(&"font_size", 15)
	add_child(_label)
	Contracts.objectives.changed.connect(refresh)
	Contracts.notice.connect(_on_notice)
	refresh()


func refresh() -> void:
	var lines: Array = Contracts.objectives.list.map(func(o: Dictionary) -> String: return Objectives.line(o))
	visible = not lines.is_empty()
	var dep := Contracts.deployment()
	var civilians := int(dep.get("civilians", 0))
	_label.text = "OBJECTIVES%s\n%s%s" % [" - " + String(dep.zone_name) if dep.has("zone_name") else "", "\n".join(lines),
		"\nCivilian casualties: %d of %d" % [civilians, MissionRegistry.setting_i("civilian_void_at", 8)] if civilians > 0 else ""]


## What the panel shows (tests read it).
func text() -> String:
	return _label.text if visible else ""


func _on_notice(text: String) -> void:
	var hud := get_parent() as Hud
	if hud and visible:
		hud.flash(text)
