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
## The readout's width when there's no HUD zone to follow.
const WIDTH := 364.0


func _init() -> void:
	name = "HotZoneDebug"
	layer = 50


func _ready() -> void:
	# The HUD's small outlined style, wrapping, under the HUD's top-right zone (docs/ui_audit.md
	# P2-22: it was 13 px at (12,120), over the command menu and the squad list).
	_label = UiKit.hud_label("", &"HudSmallLabel")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	place()


## Puts the readout under the HUD's top-right zone (objectives and hint), as wide as it.
func place() -> void:
	var zone := get_tree().get_first_node_in_group(Hud.TOP_RIGHT_GROUP) as Control
	var view := get_viewport().get_visible_rect().size
	var width := zone.size.x if zone and zone.size.x > 0.0 else WIDTH
	var top := (zone.get_global_rect().end.y + UiKit.SPACE_M) if zone else Hud.MARGIN
	_label.max_lines_visible = -1
	for i in 2:  # twice: a wrapping label works its height out from the width it had
		_label.size = Vector2(width, 0.0)
	_label.position = Vector2(view.x - Hud.MARGIN - width, top)
	# Only as many lines as there's room for above the weapon readout (it's a dev readout).
	var room := view.y - Hud.MARGIN - AmmoReadout.HEIGHT - UiKit.SPACE_M - top
	var spacing := float(_label.get_theme_constant(&"line_spacing"))
	var fit := maxi(floori((room + spacing) / maxf(float(_label.get_line_height()) + spacing, 1.0)), 1)
	if _label.get_line_count() > fit:
		_label.max_lines_visible = fit
		_label.size = Vector2(width, 0.0)


## The readout: zone and area states, the last known position, pressure, the enemy's moves.
func text() -> String:
	return readout(self)


## The readout for the level `from` is in ("" outside a hot zone), for this overlay and the
## session log's dumps (SessionLog.state_text), whether or not the dev tools are on.
static func readout(from: Node) -> String:
	var alert := Alert.of(from)
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
	var pressure := Pressure.of(from)
	if pressure:
		var last: Dictionary = pressure.history.back() if not pressure.history.is_empty() else {}
		lines.append("Pressure: %.1f (tier %d)%s" % [pressure.points, pressure.tier(),
			"  last: %s %+.1f" % [last.why, last.gain] if not last.is_empty() else ""])
	var response := EnemyResponse.of(from)
	if response:
		var out := response.patrols.filter(func(r: Dictionary) -> bool: return not r.pending and not r.lost).size()
		var looking := response.patrols.filter(func(r: Dictionary) -> bool: return float(r.looking_until) > response.now()).size()
		var turnout := "" if response._qrf_due == INF else "  (QRF turning out: %.0f s)" % (response._qrf_due - response.now())
		lines.append("Patrols out: %d (%d looking)  checkpoints %s" % [out, looking, "closed" if response.checkpoints_closed else "open"])
		lines.append("QRF launches: %d%s  hunter teams: %d  HQ pairs: %d  coordination %.1f" % [response.qrf_launches.size(), turnout,
			response.hunters.size(), response.reinforcement_pairs.size(), response.coordination()])
	var lvl := CompoundLevel.current(from) if from.is_inside_tree() else null
	var command := lvl.get_node_or_null(^"EnemyCommand") as EnemyCommand if lvl else null
	if command:
		var active := command.operations.filter(func(o: Dictionary) -> bool:
			return o.state in ["assembling", "attacking", "approved", "moving", "looking", "containing"])
		lines.append("Command: %s%s  caution %+.2f  reserves %.1f  threat %.1f (seen %.1f, losses %d)  ops %d/%d" % [command.commander_state,
			"  CONSOLIDATED" if command.consolidated else "", command.caution, command.reserves, command.threat_cp(), command.seen_now(),
			command.recent_losses(), active.size(), command.max_ops()])
		for o: Dictionary in active.slice(-4):
			lines.append("  %s %s: %s" % [o.kind, o.state, o.get("why", "")])
	var chatter := lvl.get_node_or_null(^"RadioChatter") if lvl else null
	if chatter:
		lines.append("Enemy radio: %s" % ("listening" if chatter.get(&"tuned") else "not tuned in"))
	return "\n".join(lines)


func level_node(node_name: StringName) -> Node:
	var lvl := CompoundLevel.current(self)
	return lvl.get_node_or_null(NodePath(node_name)) if lvl else null
