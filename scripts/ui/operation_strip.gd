class_name OperationStrip
extends PanelContainer
## The operation strip (docs/combined_arms.md 6.3; phase D3, cg_brief queue item 3.2): at the top of
## the HUD's top-right zone, over the objectives, while an operation runs in the zone. Four short
## lines in the HUD's small outlined style, so it reads at every ui_test size:
##   OP GREY LANCE  PH2/4 BRASS  12:40 / 25:00
##   [x] COPPER  [>] BRASS  [ ] IRON  [ ] STEEL
##   Task: Seize the bridge on the MSR at 041 052
##   Front 3.1 km in, 34% ours  |  Saber 1 assault, Hammer 1 SBF
## From the level's Operations view (every peer: the host's, replicated; late joiners ask for it).
## Refreshed every data/operations.json "hud" refresh_s.

var _label: Label
var _refresh := 0.0
## The last refresh's cost (µs: the budget's check).
var cost_us := 0.0
## A test stand-in for the view (ui_test fits a full strip without an operation).
var preview := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply(self)
	theme_type_variation = &"HudPanel"
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.theme_type_variation = &"HudSmallLabel"
	add_child(_label)
	visible = false


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = Operations.knob("hud", "refresh_s", 0.5)
	refresh()


func refresh() -> void:
	var started := Time.get_ticks_usec()
	var v := preview
	var clock := float(preview.get("clock_s", 0.0))
	if v.is_empty():
		var ops := Operations.of(self)
		if ops:
			v = ops.view
			clock = ops.clock_now()
	visible = not v.is_empty()
	if visible:
		var text := strip_text(v, clock)
		if _label.text != text:
			_label.text = text
	cost_us = float(Time.get_ticks_usec() - started)


## The strip's lines from an Operations view at `clock_s` (pure: tests and every peer).
static func strip_text(v: Dictionary, clock_s: float) -> String:
	var phases: Array = v.get("phases", [])
	var k := int(v.get("phase", 0))
	var state := String(v.get("state", ""))
	var head := "OP %s" % String(v.get("codename", v.get("name", "")))
	match state:
		Operations.WAITING:
			head += "  waiting for H-hour"
		Operations.DONE:
			head += "  every phase done: extract"
		Operations.STALLED:
			head += "  STALLED: extract"
		_:
			if k < phases.size():
				var p: Dictionary = phases[k]
				var elapsed := clock_s - float(p.get("started_s", clock_s))
				head += "  PH%d/%d %s  %s / %s" % [k + 1, phases.size(), String(p.name).trim_prefix("PL "), Operations.clock_text(elapsed),
					Operations.clock_text(float(p.get("limit_s", 0.0)))]
				if elapsed > float(p.get("limit_s", INF)):
					head += " LATE"
	var marks := PackedStringArray()
	for p: Dictionary in phases:
		var mark: String = {Operations.DONE: "[x]", Operations.RUNNING: "[>]", Operations.FAILED: "[-]"}.get(String(p.get("state", "")), "[ ]")
		marks.append("%s %s" % [mark, String(p.get("name", "")).trim_prefix("PL ")])
	var lines := PackedStringArray([head, "  ".join(marks)])
	var tasks: Array = v.get("task", [])
	if not tasks.is_empty():
		lines.append("Task: %s" % "; ".join(PackedStringArray(tasks)))
	var front := "Front %.1f km in, %d%% ours" % [float(v.get("front_m", 0.0)) / 1000.0, roundi(float(v.get("share", 0.0)) * 100.0)]
	if String(v.get("allied", "")) != "":
		front += "  |  %s" % String(v.allied)
	lines.append(front)
	return "\n".join(lines)
