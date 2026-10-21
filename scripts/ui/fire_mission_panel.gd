class_name FireMissionPanel
extends CanvasLayer
## The fire mission panel (FireSupport; the Captain's list, 2026-10-20): calling, correcting and
## firing a mission by hand, the way the command menu's Support > Fire support entries do but with
## any correction typed ("add 50, left 25"), any number of rounds, HE or smoke, and a typed grid.
## It shows the unit's mission as the host sends it (FireSupport.shown): the target and aim grids,
## the caller's line to the aim (for "add" and "drop"), rounds fired and in the air, danger close
## waiting for confirmation, the rounds left and the cooldown. Every button sends the same
## "support:fire:..." command the menu does. Opened from Support > Fire support > Fire mission
## panel (FireSupport.local_command); Esc closes it.

const WIDTH := 520.0
const REFRESH_S := 0.5

var player: Soldier
var _unit: OptionButton
var _status: Label
var _grid: LineEdit
var _correction: LineEdit
var _shell: OptionButton
var _rounds: SpinBox
var _refresh := 0.0
var _mouse_before := Input.MOUSE_MODE_VISIBLE


static func open(p: Soldier) -> FireMissionPanel:
	var old := p.get_tree().root.get_node_or_null(^"FireMissionPanel")
	if old:
		old.queue_free()
	var panel := FireMissionPanel.new()
	panel.player = p
	p.get_tree().root.add_child(panel)
	return panel


func _init() -> void:
	name = "FireMissionPanel"


func _ready() -> void:
	layer = 10
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := UiKit.screen(self, WIDTH)
	box.add_child(UiKit.header("Fire mission", "Call the mortars or the battery onto a point, walk the rounds onto the target, then fire for effect.",
		PackedStringArray([
			"Call: the first adjusting round goes where you called (a map marker, where you look, or a grid). Through binoculars the point is lased: closer to start with.",
			"Watch where it lands, then correct from the burst along your line to the target: add (further) or drop (nearer), left or right, in metres.",
			"On target: fire for effect, HE or smoke. Every round is paid as it's fired; after a fire for effect the unit needs time before the next mission.",
			"Danger close: with friendlies near the aim the guns wait until you confirm."])))
	_unit = OptionButton.new()
	for id: String in FireMission.units():
		_unit.add_item(String(FireMission.unit(id).get("name", id)))
		_unit.set_item_metadata(_unit.item_count - 1, id)
	_unit.item_selected.connect(func(_i: int) -> void: _update())
	box.add_child(UiKit.row("Firing unit", _unit))
	_status = UiKit.text("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(UiKit.heading("Call"))
	box.add_child(UiKit.button_row([
		UiKit.button("My map marker", func() -> void: _send("call:%s:marker" % unit_id()), "Fire mission on your newest map marker (M, double-click to place one)"),
		UiKit.button("Where I look", _call_here, "Fire mission where your crosshair is (lased through binoculars: further, and closer to start with)")]))
	_grid = LineEdit.new()
	_grid.placeholder_text = "grid, e.g. 0412 0688"
	_grid.text_submitted.connect(func(_t: String) -> void: _call_grid())
	var grid_row := UiKit.row("Or a grid", _grid)
	grid_row.add_child(UiKit.button("Call", _call_grid, "Fire mission on the grid typed"))
	box.add_child(grid_row)
	box.add_child(UiKit.heading("Adjust"))
	_correction = LineEdit.new()
	_correction.placeholder_text = "add 50, left 25"
	_correction.text_submitted.connect(func(_t: String) -> void: _adjust())
	var adjust_row := UiKit.row("Correction", _correction)
	adjust_row.add_child(UiKit.button("Adjust", _adjust, "Move the aim by the correction and fire another adjusting round"))
	box.add_child(adjust_row)
	box.add_child(UiKit.button_row([UiKit.button("Repeat", func() -> void: _send("repeat:%s" % unit_id()), "Another adjusting round on the same aim")]))
	box.add_child(UiKit.heading("Fire for effect"))
	_shell = OptionButton.new()
	_shell.add_item("HE")
	_shell.add_item("Smoke")
	box.add_child(UiKit.row("Shell", _shell))
	_rounds = SpinBox.new()
	_rounds.min_value = 1
	_rounds.max_value = 8
	_rounds.value = 3
	box.add_child(UiKit.row("Rounds", _rounds))
	box.add_child(UiKit.button_row([
		UiKit.accent_button("Fire for effect", func() -> void: _send("ffe:%s:%s:%d" % [unit_id(), "he" if _shell.selected == 0 else "smoke", int(_rounds.value)]),
			"Fire the rounds set above on the aim; the mission ends when they've landed"),
		UiKit.danger_button("Confirm danger close", func() -> void: _send("confirm:%s" % unit_id()), "Let the guns fire with friendlies near the aim"),
		UiKit.button("End mission", func() -> void: _send("end:%s" % unit_id()), "End the mission (no cooldown unless it fired for effect)"),
		UiKit.button("Close", close, "Close the panel (Esc)")], true))
	_update()


## The firing unit picked ("mortar", "artillery").
func unit_id() -> String:
	return String(_unit.get_item_metadata(_unit.selected)) if _unit and _unit.item_count > 0 else "mortar"


func _call_here() -> void:
	if not is_instance_valid(player):
		return
	var lased := player.binoculars_up
	var hit: Variant = FireSupport.lase_point(player) if lased else player.crosshair_ground()
	if hit == null:
		player._hud.flash("Look at a spot on the ground")
		return
	_send("call:%s:here%s" % [unit_id(), ":lased" if lased else ""], hit)


func _call_grid() -> void:
	if _grid.text.strip_edges() != "":
		_send("call:%s:grid:%s" % [unit_id(), _grid.text.strip_edges()])


func _adjust() -> void:
	var said := FireMission.parse(_correction.text)
	if said.has("why"):
		_status.text = String(said.why)
		return
	_send("adjust:%s:%s" % [unit_id(), _correction.text.strip_edges()])
	_correction.text = ""


## Sends "support:fire:<arg>" to the host, as the command menu does.
func _send(arg: String, point: Variant = null) -> void:
	if not is_instance_valid(player) or not player.multiplayer.has_multiplayer_peer():
		return
	var at: Vector3 = point if point is Vector3 else player.global_position
	player._server_squad_command.rpc_id(1, "support:fire:" + arg, at, PackedStringArray())


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_update()


func _update() -> void:
	if _status == null:
		return
	var id := unit_id()
	var u := FireMission.unit(id)
	_rounds.max_value = int(u.get("max_rounds", 8))
	var fs := FireSupport.of(player) if is_instance_valid(player) and player.is_inside_tree() else null
	var e: Dictionary = fs.shown.get(id, {}) if fs else {}
	var price := "$%s a round" % DebriefCalc.money(Prices.support_price(String(u.get("price", ""))))
	if e.is_empty():
		_status.text = "%s (%s): %s. %d to %d m from its guns off the map." % [String(u.get("name", id)), String(u.get("callsign", "")), price, int(u.get("min_m", 0)), int(u.get("max_m", 0))]
		return
	var lines := PackedStringArray()
	if String(e.get("why", "")) != "":
		lines.append(String(e.why))
	if bool(e.get("open", false)):
		lines.append("Mission on grid %s, aiming at %s. Your line to the aim: %d deg, %d m. %d fired, %d in the air.%s" % [e.target, e.aim,
			int(e.bearing), int(e.distance), int(e.fired), int(e.in_flight), " DANGER CLOSE: confirm to fire." if bool(e.held) else ""])
	elif int(e.get("cooldown", 0)) > 0:
		lines.append("Ready for another mission in %d s." % int(e.cooldown))
	else:
		lines.append("Ready: call a mission.")
	lines.append("%s. Left this deployment: %d HE, %d smoke." % [price, int(e.get("he", 0)), int(e.get("smoke", 0))])
	_status.text = "\n".join(lines)


func close() -> void:
	Input.mouse_mode = _mouse_before
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
