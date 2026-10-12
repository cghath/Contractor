class_name PauseMenu
extends CanvasLayer
## The Escape menu (Captain, 2026-10-12: there was no way back to the menu): Resume, Return to
## Base (revert) (the host, during a campaign deployment: back to just before it deployed,
## BaseHub.server_revert_deployment; confirmed first), Return to main menu and Quit game (the
## host saves first). The game keeps running behind it: it's co-op, nothing pauses. PlayerInput
## opens it on Escape.

var _panel: PanelContainer
var _base_button: Button
var _confirm: Control
var _status: Label


func _init() -> void:
	name = "PauseMenu"
	layer = 20
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_panel = PanelContainer.new()
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Paused (the game keeps running)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if SessionLog.session_id != "":  # playtests: which session log to send with a report
		var session := Label.new()
		session.text = "Session %s (logged); Insert: bug report" % SessionLog.session_id
		session.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		session.modulate = Color(1, 1, 1, 0.6)
		box.add_child(session)
	box.add_child(_button("Resume", close))
	_base_button = _button("Return to Base (revert)", _ask_return_to_base)
	box.add_child(_base_button)
	box.add_child(_button("Return to main menu", _to_main_menu))
	box.add_child(_button("Quit game", _quit))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	_confirm = VBoxContainer.new()
	_confirm.visible = false
	var ask := Label.new()
	ask.text = "Revert to just before you deployed? Everything from this deployment is undone: cash, the squad and their gear, contracts and the stash go back to how they were, and everyone is at the base."
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD
	_confirm.add_child(ask)
	var row := HBoxContainer.new()
	row.add_child(_button("Yes, revert to base", _return_to_base))
	row.add_child(_button("Cancel", func() -> void: _confirm.visible = false))
	_confirm.add_child(row)
	box.add_child(_confirm)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_confirm.visible = false
	_status.text = ""
	_base_button.visible = can_return_to_base()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


## Whether "Return to base" applies: the host, in a campaign, out on a deployment.
func can_return_to_base() -> bool:
	return multiplayer.is_server() and BaseHub.campaign_running and not BaseHub.in_base() \
		and RosterDeployment.is_running(BaseHub.roster())


func _ask_return_to_base() -> void:
	_confirm.visible = true


func _return_to_base() -> void:
	var why := BaseHub.server_revert_deployment() if can_return_to_base() else "Only the host can do that, during a deployment."
	if why != "":
		_status.text = why
		return
	close()


func _to_main_menu() -> void:
	_save()
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	BaseHub.cancel_session()  # this machine is out of the campaign session (the save stays)
	get_tree().reload_current_scene()


func _quit() -> void:
	_save()
	get_tree().quit()


## The host saves the zone, and the campaign when one is running, before leaving.
func _save() -> void:
	if not Net.is_hosting():
		return
	GameState.save_zone()
	if BaseHub.campaign_running:
		BaseHub.server_save()


func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(pressed)
	return b
