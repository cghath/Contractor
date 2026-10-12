class_name HotZoneDebug
extends CanvasLayer
## Dev tools only (DevTools.on: debug builds, or a build started with --dev), on the host, in a
## hot zone (4B part 3): a readout of what the enemy knows and how hard it's pushing, for
## playtests. A normal build shows nothing (Captain: no meter on screen). Page Up shows or hides
## it; Page Down skips the enemy's clock SKIP_S forward (reports come due, check-ins, cooldowns,
## pressure's quiet and time, the QRF's turnout).

const SKIP_S := 300.0
const REFRESH_S := 0.5

var _label: Label
var _refresh := 0.0


func _init() -> void:
	name = "HotZoneDebug"
	layer = 50


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 120)
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	_label.visible = false
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not multiplayer.is_server():
		return
	if key.keycode == KEY_PAGEUP:
		_label.visible = not _label.visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_PAGEDOWN:
		skip(SKIP_S)
		get_viewport().set_input_as_handled()


## Runs the enemy's clock `seconds` forward and lets everything that runs on it catch up.
func skip(seconds: float) -> void:
	var alert := Alert.of(self)
	if alert == null:
		return
	alert.advance(seconds)
	var pressure := Pressure.of(self)
	if pressure:
		pressure.server_tick()
	var response := EnemyResponse.of(self)
	if response:
		response.server_tick()
	print("[debug] enemy clock skipped %.0f s" % seconds)


func _process(delta: float) -> void:
	if not _label.visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_S
	_label.text = text()


## The readout: zone and area states, the last known position, pressure, the enemy's moves.
func text() -> String:
	var alert := Alert.of(self)
	if alert == null:
		return ""
	var lines: Array[String] = ["HOT ZONE (debug; PgUp hide, PgDn +%d min)" % int(SKIP_S / 60.0)]
	lines.append("Zone: %s%s" % [Alert.STATE_NAMES[alert.zone_state], "  (comms down)" if alert.comms_down else ""])
	var raised: Array[String] = []
	for area: String in alert.areas:
		if alert.state_of(area) > Alert.State.NORMAL:
			raised.append("%s %s" % [area, Alert.STATE_NAMES[alert.state_of(area)]])
	lines.append("Areas: %s" % (", ".join(raised) if not raised.is_empty() else "all normal"))
	var lk := alert.last_known()
	lines.append("Last known: %s" % ("none" if lk.is_empty() else "(%.0f, %.0f) +/- %.0f m" % [lk.pos.x, lk.pos.z, lk.radius]))
	lines.append("Reports: %d heard, %d on the way" % [alert.reports.size(), alert._pending.size()])
	var pressure := Pressure.of(self)
	if pressure:
		var last: Dictionary = pressure.history.back() if not pressure.history.is_empty() else {}
		lines.append("Pressure: %.1f (tier %d)%s" % [pressure.points, pressure.tier(),
			"  last: %s %+.1f" % [last.why, last.gain] if not last.is_empty() else ""])
	var response := EnemyResponse.of(self)
	if response:
		var out := response.patrols.filter(func(r: Dictionary) -> bool: return not r.pending and not r.lost).size()
		var looking := response.patrols.filter(func(r: Dictionary) -> bool: return float(r.looking_until) > response.now()).size()
		var turnout := "" if response._qrf_due == INF else "  (QRF turning out: %.0f s)" % (response._qrf_due - response.now())
		lines.append("Patrols out: %d (%d looking)  checkpoints %s" % [out, looking, "closed" if response.checkpoints_closed else "open"])
		lines.append("QRF launches: %d%s  hunter teams: %d  HQ pairs: %d  coordination %.1f" % [response.qrf_launches.size(), turnout,
			response.hunters.size(), response.reinforcement_pairs.size(), response.coordination()])
	var chatter := level_node(&"RadioChatter")
	if chatter:
		lines.append("Enemy radio: %s" % ("listening" if chatter.get(&"tuned") else "not tuned in"))
	return "\n".join(lines)


func level_node(node_name: StringName) -> Node:
	var lvl := CompoundLevel.current(self)
	return lvl.get_node_or_null(NodePath(node_name)) if lvl else null
