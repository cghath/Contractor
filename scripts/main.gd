extends Node
## Boots the session: host/join menu, command-line shortcuts, saving on exit.
##
## Command-line (after `--`): `--host` hosts immediately, `--join [address]` joins.
## Handy with Debug > Customize Run Instances to test co-op with one click.

@onready var menu: Menu = $Menu


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	Net.session_ended.connect(_on_session_ended)
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		menu.host()
	elif "--join" in args:
		var i := args.find("--join")
		menu.join(args[i + 1] if i + 1 < args.size() else "127.0.0.1")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quick_save") and Net.is_hosting():
		GameState.save_zone()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Net.is_hosting():
			GameState.save_zone()
		get_tree().quit()


func _on_session_ended() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()
