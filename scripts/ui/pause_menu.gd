class_name PauseMenu
extends CanvasLayer
## The Escape menu (Captain, 2026-10-12: there was no way back to the menu): Resume, Return to
## Base (revert) (the host, during a campaign deployment: back to just before it deployed,
## BaseHub.server_revert_deployment; confirmed first), Return to main menu and Quit game (the
## host saves first). The game keeps running behind it: it's co-op, nothing pauses. PlayerInput
## opens it on Escape. It also has the get-out key option (ControlOptions), as on the main menu.

var _panel: PanelContainer
var _base_button: Button
## The get-out key option (ControlOptions), the same as the main menu's.
var get_out_toggle: CheckBox
var _confirm: Control
var _status: Label
## The settings screen (GameSettings): the pause panel hides while it's open.
var settings_menu: SettingsMenu
var _hits_button: Button


func _init() -> void:
	name = "PauseMenu"
	layer = 20
	visible = false


func _ready() -> void:
	# The shared look (UiKit; Captain, 2026-10-14: "all of the UIs need a pass"): a themed panel
	# that scrolls rather than running off a small window at a big Menu and HUD size.
	add_child(UiKit.dim(0.45))
	var box := UiKit.screen(self, 380.0)
	_panel = box.get_parent() as PanelContainer
	box.add_child(UiKit.header("Paused", "The game keeps running behind this menu: it's co-op, nothing pauses.",
		PackedStringArray(["Resume goes back to the game. Settings has video, sound, controls, keys and the HUD layout.",
			"Return to Base (revert) is the host's, during a campaign deployment: everything from this deployment is undone and everyone is back at the base (it asks first).",
			"Return to main menu and Quit game save first when you're the host."]),
		[["Esc", "Resume"], ["Tab / arrows", "Move"], ["Enter", "Press"]]))
	var resume := UiKit.accent_button("Resume", close, "Back to the game (Esc)")
	box.add_child(resume)
	box.add_child(UiKit.button("Settings", _open_settings, "Video, sound, controls, keys and the HUD layout"))
	_hits_button = UiKit.button("Last hits (x-ray)", _open_hits, "The last hits on armour this game, in the x-ray (combined arms A5)")
	box.add_child(_hits_button)
	get_out_toggle = ControlOptions.get_out_toggle()  # changeable mid-game
	box.add_child(get_out_toggle)
	var leave := UiKit.section("Leave", box)
	_base_button = UiKit.danger_button("Return to Base (revert)", _ask_return_to_base,
		"Undo this deployment and take everyone back to the base (the host only; asks first)")
	leave.add_child(_base_button)
	leave.add_child(UiKit.button("Return to main menu", _to_main_menu, "Leave the session (the host saves first)"))
	leave.add_child(UiKit.button("Quit game", _quit, "Close the game (the host saves first)"))
	_status = UiKit.text("")
	box.add_child(_status)
	_confirm = VBoxContainer.new()
	_confirm.visible = false
	_confirm.add_child(UiKit.warn("Revert to just before you deployed? Everything from this deployment is undone: cash, the squad and their gear, contracts and the stash go back to how they were, and everyone is at the base."))
	var row := UiKit.button_row([UiKit.danger_button("Yes, revert to base", _return_to_base, "Undo this deployment"),
		UiKit.button("Cancel", func() -> void: _confirm.visible = false, "Keep playing the deployment")])
	_confirm.add_child(row)
	box.add_child(_confirm)
	if SessionLog.session_id != "":  # playtests: which session log to send with a report
		var logs := UiKit.section("Playtest logs", box)
		logs.add_child(UiKit.hint("Session %s (logged). Insert: bug report." % SessionLog.session_id))
		# Where the logs are, so a friend can send them (P0331 triage: nobody knew where to look).
		logs.add_child(UiKit.hint("Session logs (send the %s folder):" % SessionLog.session_id))
		var path := LineEdit.new()
		path.name = "SessionLogFolder"
		path.text = SessionLog.logs_folder()
		path.editable = false  # still selectable, to copy
		path.tooltip_text = path.text
		logs.add_child(path)
		logs.add_child(_button("Open the log folder", func() -> void: OS.shell_open(SessionLog.logs_folder())))
	box.add_child(UiKit.key_hint("Esc", "Resume"))


func is_open() -> bool:
	return visible


## The local player's x-ray (VehicleXray), or null.
func _xray() -> VehicleXray:
	return get_tree().get_first_node_in_group(VehicleXray.GROUP) as VehicleXray if is_inside_tree() else null


## The last hits in the x-ray: the pause menu shuts and the x-ray opens on the latest.
func _open_hits() -> void:
	var x := _xray()
	close()
	if x:
		x.open_latest()


func _open_settings() -> void:
	if settings_menu == null:
		settings_menu = SettingsMenu.new()
		add_child(settings_menu)
		settings_menu.closed.connect(func() -> void:
			_panel.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	_panel.visible = false
	settings_menu.open()


func open() -> void:
	visible = true
	_confirm.visible = false
	_status.text = ""
	_base_button.visible = can_return_to_base()
	get_out_toggle.set_pressed_no_signal(ControlOptions.get_out_key())
	_hits_button.visible = _xray() != null and not _xray().reports.is_empty()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.focus_first(_panel)  # keyboard: Tab/arrows and Enter work at once


func close() -> void:
	if settings_menu and settings_menu.is_open():
		settings_menu.close()
	_panel.visible = true
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
	return UiKit.button(text, pressed)
