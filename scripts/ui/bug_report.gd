class_name BugReport
extends CanvasLayer
## The bug-report key (docs/debugging.md, "Planned" 1): Insert opens a small note panel (Enter
## saves, Esc cancels; the mouse is released so the game ignores the keys meanwhile, as in the
## pause menu). Saving writes report-<n>.txt into the session's folder (the note, the time,
## SessionLog.state_text, the player's inventory and wounds, zone and seed) and, with a screen,
## report-<n>.png, a screenshot taken before the panel showed. Any build, any peer.

const KEY := KEY_INSERT
## The panel's width (logical px; narrower on a small window or a big UI scale).
const WIDTH := 460.0

var _panel: PanelContainer
var _edit: LineEdit
var _shot: Image


func _init() -> void:
	name = "BugReport"
	layer = 21
	visible = false


func _ready() -> void:
	## The shared look (Captain, 2026-10-14: "all the UIs need a pass"; docs/ui_audit.md P2-21):
	## a kit screen (themed, fitted to the window, scrolling if it must) with a wrapping title and
	## key hints, instead of a default-theme box whose 440 px title ran past its 420 px panel.
	var box := UiKit.screen(self, WIDTH)
	_panel = box.get_parent() as PanelContainer
	box.add_child(UiKit.header("Bug report", "Say what went wrong. It's saved with the session log for the developers."))
	box.add_child(UiKit.hint("What went wrong? The note, a screenshot and the game's state are saved in this session's folder."))
	_edit = LineEdit.new()
	_edit.placeholder_text = "a short note"
	_edit.text_submitted.connect(func(text: String) -> void: _submit(text))
	_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close())
	box.add_child(_edit)
	var keys := HFlowContainer.new()
	keys.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
	keys.add_child(UiKit.key_hint("Enter", "Save"))
	keys.add_child(UiKit.key_hint("Esc", "Cancel"))
	box.add_child(keys)


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
