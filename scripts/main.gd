extends Node
## Boots the session: host/join menu, command-line shortcuts, saving on exit.
##
## Command-line (after `--`): `--host` hosts immediately, `--join [address]` joins,
## `--zone [id]` hosts a zone (data/zones.json, "test" by default) instead of the compound.
## Handy with Debug > Customize Run Instances to test co-op with one click.

@onready var menu: Menu = $Menu


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	Net.session_ended.connect(_on_session_ended)
	var switch := LevelSwitch.new()  # joining clients load the host's level (a zone, say)
	switch.name = "LevelSwitch"
	add_child(switch)
	var args := OS.get_cmdline_user_args()
	if "--zone" in args:
		var i := args.find("--zone")
		var id := args[i + 1] if i + 1 < args.size() and not args[i + 1].begins_with("--") else "test"
		GameState.zone_id = "zone_%s" % id
		host_zone(ZoneDef.get_def(id))
	elif "--new-campaign" in args or "--campaign" in args:
		# Host the campaign at the base (FOB), as the menu's "Campaign: host" does; with
		# --new-campaign the current campaign is archived first (moved, never deleted).
		if "--new-campaign" in args:
			BaseHub.archive_campaign()
		menu._campaign_host()
	elif "--host" in args:
		menu.host()
	elif "--join" in args:
		var i := args.find("--join")
		menu.join(args[i + 1] if i + 1 < args.size() else "127.0.0.1")


## Hosts a zone (a ZoneDef definition) in place of the compound. The caller sets
## GameState.zone_id (the zone's save) first.
func host_zone(def: Dictionary) -> void:
	LevelSwitch.load_level(self, {"level": "zone", "def": ZoneDef.normalize(def)})
	menu.host()


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
