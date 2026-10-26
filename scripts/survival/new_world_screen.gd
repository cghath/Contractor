class_name NewWorldScreen
extends Control
## The Survival section's New world screen (docs/survival.md calls 7, 17, 49): a name, a seed,
## the world's goal (Reach the evac, Sandbox, Clear the map), the four world options (the dead's
## density and speed, loot scarcity, needs and medical harshness, the living world's intensity:
## Low, Normal, High) and the survivor (a blank slate in phase A; backgrounds and flaws come with
## the RPG layer, phase B). Start calls back with {"name", "seed", "options"}.

const GOALS := [["evac", "Reach the evac"], ["sandbox", "Sandbox"], ["clear", "Clear the map"]]
const LEVELS := [["low", "Low"], ["normal", "Normal"], ["high", "High"]]
## The season you wake in (call 137; Seasons): spring by default.
const SEASONS := [["spring", "Spring"], ["summer", "Summer"], ["autumn", "Autumn"], ["winter", "Winter"]]
## Where a friend joining the running world comes in (call 126; CoopFallen): the farm by default.
const JOINS := [["farm", "At the farm"], ["host", "Beside the host"]]
const OPTIONS := [
	["dead", "The dead", "How many of the dead a place holds, how fast they move at night, the share of runners and specials."],
	["loot", "Loot", "How often containers hold something and how fast they refill; ammo's weight in the tables."],
	["needs", "Needs and medicine", "How fast hunger, thirst, cold and the fever run; how rare the serum is."],
	["world", "The living world", "How many groups there are, how hard raiders push, how fast settlements rise and fall."],
]

var on_start: Callable
var _name: LineEdit
var _seed: LineEdit
var _goal: OptionButton
var _season: OptionButton
var _join: OptionButton
var _card_note: Label
var _picks := {}
var survivor: SurvivorPicker
var _start_button: Button
## Call 139: a warning under the name when a saved world has it already (Start would replace it).
var name_warning: Label


func _init(start: Callable) -> void:
	on_start = start
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var box := UiKit.screen(self, 620.0, true)
	box.add_child(UiKit.header("New world", "Contractor: Fallen. An open world, persistent, overrun.",
		PackedStringArray(["One world for every goal: the evac is at the far side, the sandbox has no end, clearing the map is the hardest.",
			"The options scale the world; Normal is how it's meant to be played."]), [["Tab / arrows", "Move"], ["Enter", "Press"]]))
	_name = LineEdit.new()
	_name.text = "world %s" % Time.get_datetime_string_from_system().replace(":", "").replace("T", " ")
	_name.custom_minimum_size = Vector2(320, 0)
	box.add_child(UiKit.row("Name", _name))
	name_warning = UiKit.warn("")
	name_warning.name = "NameWarning"
	box.add_child(name_warning)
	_name.text_changed.connect(func(_t: String) -> void: check_name())
	check_name()
	_seed = LineEdit.new()
	_seed.text = str(randi() % 1000000)
	_seed.custom_minimum_size = Vector2(160, 0)
	box.add_child(UiKit.row("Seed", _seed))
	_goal = OptionButton.new()
	for g: Array in GOALS:
		_goal.add_item(String(g[1]))
	_goal.selected = 0
	box.add_child(UiKit.row("Goal", _goal))
	_season = OptionButton.new()
	for s: Array in SEASONS:
		_season.add_item(String(s[1]))
	_season.selected = 0
	_season.tooltip_text = "The season you wake in: a year is four seasons of about ten world days; winter freezes crops, water and the dead."
	box.add_child(UiKit.row("Season", _season))
	_join = OptionButton.new()
	for j: Array in JOINS:
		_join.add_item(String(j[1]))
	_join.selected = 0
	_join.tooltip_text = "Where a friend who joins the running world wakes: at the farm, or beside you."
	box.add_child(UiKit.row("Friends join", _join))
	var options := UiKit.section("World options", box)
	for o: Array in OPTIONS:
		var pick := OptionButton.new()
		for l: Array in LEVELS:
			pick.add_item(String(l[1]))
		pick.selected = 1
		pick.tooltip_text = String(o[2])
		_picks[String(o[0])] = pick
		options.add_child(UiKit.row(String(o[1]), pick))
	var who := UiKit.section("Your survivor", box)
	survivor = SurvivorPicker.new()  # blank slate, or a background and flaws for points (the RPG layer)
	who.add_child(survivor)
	_start_button = UiKit.accent_button("Start", _start, "Wake at the farm")
	survivor.valid_changed.connect(func(ok: bool) -> void: _start_button.disabled = not ok)
	_card_note = Label.new()
	box.add_child(_card_note)
	var import_button := UiKit.button("Import card", _import, "A world card's seed and options (the clipboard, else the newest in user://world_cards)")
	box.add_child(UiKit.button_row([_start_button, import_button, UiKit.button("Back", queue_free, "Back to the menu")], true))


## A world card (ModKit.import_card) onto the screen: its name, seed and options. Returns why not ("" done).
func apply_card(text: String) -> String:
	var c := ModKit.import_card(text)
	if c.has("error"):
		return String(c.error)
	_name.text = String(c.name)
	check_name()
	_seed.text = str(int(c.seed))
	var opts: Dictionary = c.options
	for i in GOALS.size():
		if String(GOALS[i][0]) == String(opts.get("goal", "")):
			_goal.selected = i
	for i in SEASONS.size():
		if String(SEASONS[i][0]) == String(opts.get("season", "")):
			_season.selected = i
	for i in JOINS.size():
		if String(JOINS[i][0]) == String(opts.get("join", "")):
			_join.selected = i
	for key: String in _picks:
		for i in LEVELS.size():
			if String(LEVELS[i][0]) == String(opts.get(key, "")):
				(_picks[key] as OptionButton).selected = i
	var missing: Array = c.get("missing_mods", [])
	return "" if missing.is_empty() else "Imported; made with mods not on here: %s" % ", ".join(PackedStringArray(missing.map(func(m: Variant) -> String: return String(m))))


## Shows the duplicate-name warning when a saved world is called this already. Returns it.
func check_name() -> String:
	var text := ""
	if _name and Survival.world_exists(_name.text):
		text = "A saved world is called that already: Start would start it over. Pick another name, or Continue that one."
	if name_warning:
		name_warning.text = text
		name_warning.visible = text != ""
	return text


func set_world_name(text: String) -> void:
	_name.text = text
	check_name()


func _import() -> void:
	var text := DisplayServer.clipboard_get() if DisplayServer.get_name() != "headless" else ""
	if not text.strip_edges().begins_with("{"):
		text = ModKit.newest_card_text()
	var why := apply_card(text) if text != "" else "No world card found (copy one, or put it in user://world_cards)"
	if _card_note:
		_card_note.text = why if why != "" else "World card imported."


func choices() -> Dictionary:
	var options := {"goal": String(GOALS[_goal.selected][0]), "season": String(SEASONS[maxi(_season.selected, 0)][0]) if _season else "spring"}
	if _join:
		options["join"] = String(JOINS[maxi(_join.selected, 0)][0])
	for key: String in _picks:
		options[key] = String(LEVELS[(_picks[key] as OptionButton).selected][0])
	if survivor:
		options["survivor"] = survivor.choice()  # (Rpg applies it on the first join)
	return options


func _start() -> void:
	var seed_text := _seed.text.strip_edges()
	var world_seed := seed_text.to_int() if seed_text.is_valid_int() else hash(seed_text)
	if on_start.is_valid():
		on_start.call(_name.text, world_seed, choices())
	queue_free()
