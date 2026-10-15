class_name ObjectivesPanel
extends PanelContainer
## The deployment's objectives in the HUD's top-right corner (wave 4, W10): one line each,
## [ ] active, [x] done, [-] failed, from the replicated Contracts.objectives. Hidden when
## there's no deployment. Contract messages (signed, voided, civilian casualties) flash on
## the HUD while it's up.

## Its width (logical px); the Hud's top-right zone is this wide, or less on a narrow window.
const WIDTH := 364.0

var _label: Label


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
	var hud := Hud.of(self)
	if hud and visible:
		hud.flash(text)
