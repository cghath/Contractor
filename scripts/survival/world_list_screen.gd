class_name WorldListScreen
extends Control
## The Survival section's Continue (call 139; docs/survival_polish.md): every saved world, newest
## first, with its name, day and season, the survivor (name and generation) and when it was last
## played. Pick one to carry it on; Put away moves it into an archive folder (never deleted, as
## the campaign's reset: Survival.archive_world), after a confirm. Ironman is not taken (call 139):
## the save rules stay as they are.

var on_pick: Callable
var list_box: VBoxContainer
var status: Label
var _worlds: Array[Dictionary] = []


func _init(pick: Callable = Callable()) -> void:
	on_pick = pick
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var box := UiKit.screen(self, 680.0, true)
	box.add_child(UiKit.header("Continue", "Contractor: Fallen. Pick a world to carry on where it was left.",
		PackedStringArray(["Each world keeps its own survivor, settlement and dead. Put away moves a world's saves into an archive folder; nothing is deleted.",
			"Ironman isn't a thing here: worlds autosave as you play."]), [["Tab / arrows", "Move"], ["Enter", "Press"], ["Esc", "Back"]]))
	list_box = VBoxContainer.new()
	list_box.name = "Worlds"
	list_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	box.add_child(list_box)
	status = UiKit.hint("")
	status.name = "Status"
	box.add_child(status)
	var back := UiKit.button("Back", queue_free, "Back to the menu (Esc)")
	back.name = "Back"
	box.add_child(UiKit.button_row([back], true))
	refresh()


## The list again from the saves on disk.
func refresh() -> void:
	_worlds = Survival.worlds()
	for c: Node in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	if _worlds.is_empty():
		list_box.add_child(UiKit.hint("No saved worlds. Start one with Survival: new world."))
		return
	for w: Dictionary in _worlds:
		var id := String(w.id)
		var play := UiKit.accent_button("Continue", pick.bind(id), "Carry on %s" % String(w.name))
		play.name = "Play_" + id
		var away := UiKit.button("Put away", ask_archive.bind(id), "Move this world's saves into an archive folder (nothing is deleted)")
		away.name = "Archive_" + id
		list_box.add_child(UiKit.action_row(line_of(w), [play, away]))


## A world's line: "Riverside: day 12, summer. Ann Hale (generation 2). Last played 2026-10-26 14:02".
static func line_of(w: Dictionary) -> String:
	var who := "%s (generation %d)" % [String(w.survivor), int(w.generation)] if String(w.get("survivor", "")) != "" else "no survivor yet"
	return "%s: day %d, %s. %s. Last played %s" % [String(w.name), int(w.day), String(w.season), who, String(w.get("played_text", "?"))]


## The worlds listed now (ids, newest first).
func ids() -> Array[String]:
	var out: Array[String] = []
	for w: Dictionary in _worlds:
		out.append(String(w.id))
	return out


func pick(id: String) -> void:
	if on_pick.is_valid():
		on_pick.call(id)
	queue_free()


func ask_archive(id: String) -> void:
	var name := id
	for w: Dictionary in _worlds:
		if String(w.id) == id:
			name = String(w.name)
	UiKit.confirm(self, "Put %s away? Its saves move into an archive folder under the saves; nothing is deleted." % name, "Put away", archive.bind(id))


## Puts world `id` away (Survival.archive_world) and lists the rest.
func archive(id: String, into := "") -> void:
	var res := Survival.archive_world(id, into)
	status.text = "Put away in %s." % String(res.dir) if not (res.moved as Array).is_empty() else "Couldn't put it away."
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		queue_free()
