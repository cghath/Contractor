class_name HcStrip
extends VBoxContainer
## The HUD's high command strip (docs/high_command.md 10): one line while hero squads are out,
## "HAWK 2 ● green Set | VIPER 3 ● amber Contact", and under it the latest request with its keys
## ("Viper 3: request to break contact  [Shift+Y] approve  [Shift+N] deny  14 s"). Shown only
## while a high command group is out; the keys answer it (HighCommand.request_answer) for the
## commander. In the HUD's outlined style (UiKit).

var _line: Label
var _ask: Label
var _hc: HighCommand
var _refresh := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = UiKit.hint("")
	_ask = UiKit.hint("")
	_ask.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.3))
	add_child(_line)
	add_child(_ask)
	visible = false


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	if _hc == null or not is_instance_valid(_hc):
		_hc = HighCommand.of(self)
	if _hc == null or _hc.view.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "hero").is_empty():
		visible = false
		return
	visible = true
	_line.text = strip_text(_hc.view)
	var r: Dictionary = _hc.requests.back() if not _hc.requests.is_empty() else {}
	_ask.visible = not r.is_empty() and _hc.is_commander()
	if _ask.visible:
		_ask.text = "%s: %s   [Shift+Y] approve   [Shift+N] deny   %d s" % [r.callsign, r.text, maxi(ceili(float(r.get("until", 0.0)) - Soldier._now()), 0)]


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _hc == null or _hc.requests.is_empty() or not _hc.is_commander():
		return
	if event.is_action_pressed(&"hc_approve") or event.is_action_pressed(&"hc_deny"):
		_hc.request_answer(int(_hc.requests.back().id), event.is_action_pressed(&"hc_approve"))
		get_viewport().set_input_as_handled()


## "HAWK 2 ● green Set | VIPER 3 ● amber Contact" from the view. Pure.
static func strip_text(view: Array) -> String:
	var parts := PackedStringArray()
	for e: Dictionary in view:
		if String(e.get("kind", "")) != "hero":
			continue
		var o: Dictionary = e.get("order", {})
		var doing := "Contact" if bool(e.get("contact", false)) else (String(o.get("state", "")).capitalize() if not o.is_empty() and String(o.get("state", "")) not in ["done", "cancelled", ""] else "Idle")
		if bool(e.get("dark", false)):
			doing = "No comms"
		parts.append("%s ● %s %s" % [String(e.callsign).to_upper(), String(e.get("band", "green")), doing])
	return " | ".join(parts)
