class_name BugReport
extends CanvasLayer
## The bug-report key (docs/debugging.md, "Planned" 1): Insert opens a small note panel (Enter
## saves, Esc cancels; the mouse is released so the game ignores the keys meanwhile, as in the
## pause menu). Saving writes report-<n>.txt into the session's folder (the note, the time,
## SessionLog.state_text, the player's inventory and wounds, zone and seed) and, with a screen,
## report-<n>.png, a screenshot taken before the panel showed. Any build, any peer.

const KEY := KEY_INSERT

var _panel: PanelContainer
var _edit: LineEdit
var _shot: Image


func _init() -> void:
	name = "BugReport"
	layer = 21
	visible = false


func _ready() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_panel = PanelContainer.new()
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Bug report: what went wrong? (Enter saves, Esc cancels)"
	box.add_child(title)
	_edit = LineEdit.new()
	_edit.placeholder_text = "a short note"
	_edit.text_submitted.connect(func(text: String) -> void: _submit(text))
	_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close())
	box.add_child(_edit)


func is_open() -> bool:
	return visible


func open() -> void:
	_shot = _screenshot()  # before the panel shows
	visible = true
	_edit.text = ""
	_edit.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	_shot = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY and not visible:
		get_viewport().set_input_as_handled()
		open()


func _submit(text: String) -> void:
	var n := save(text, self, _shot)
	var player := get_parent() as Soldier
	if player and player.player_input:
		player.player_input.flash("Bug report %d saved" % n if n > 0 else "Bug report not saved")
	close()


## Writes the next report-<n>.txt (and .png when `shot` is given) into the session folder (a
## session is started if none is open); returns n, or 0 if it couldn't be written.
static func save(note: String, from: Node, shot: Image = null) -> int:
	if SessionLog.session_id == "":
		SessionLog.start(SessionLog._find_parent())
	if SessionLog.session_id == "":
		return 0
	var folder := SessionLog.folder
	var n := 1
	while FileAccess.file_exists(folder.path_join("report-%d.txt" % n)):
		n += 1
	var text := PackedStringArray()
	text.append("Bug report %d (session %s)" % [n, SessionLog.session_id])
	text.append("Note: %s" % note)
	var now := Time.get_datetime_dict_from_system()
	text.append("Time: %04d-%02d-%02d %02d:%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second])
	text.append("Zone: %s; seed %s" % [GameState.zone_id, _seed_text(from)])
	text.append("")
	text.append(SessionLog.state_text("bug report: %s" % note))
	var f := FileAccess.open(folder.path_join("report-%d.txt" % n), FileAccess.WRITE)
	if f == null:
		return 0
	f.store_string("\n".join(text))
	f.close()
	if shot:
		shot.save_png(folder.path_join("report-%d.png" % n))
	SessionLog.note("bug report %d: %s" % [n, note])
	return n


static func _seed_text(from: Node) -> String:
	var level := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	if level and "def" in level and level.def is Dictionary and level.def.has("seed"):
		return str(level.def.seed)
	return "n/a"


func _screenshot() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture := get_viewport().get_texture()
	return texture.get_image() if texture else null
