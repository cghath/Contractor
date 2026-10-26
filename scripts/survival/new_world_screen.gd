class_name NewWorldScreen
extends Control
## The Survival section's New world screen (docs/survival.md calls 7, 17, 49): a name, a seed,
## the world's goal (Reach the evac, Sandbox, Clear the map), the four world options (the dead's
## density and speed, loot scarcity, needs and medical harshness, the living world's intensity:
## Low, Normal, High) and the survivor (a blank slate in phase A; backgrounds and flaws come with
## the RPG layer, phase B). Start calls back with {"name", "seed", "options"}.

const GOALS := [["evac", "Reach the evac"], ["sandbox", "Sandbox"], ["clear", "Clear the map"]]
const LEVELS := [["low", "Low"], ["normal", "Normal"], ["high", "High"]]
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
var _picks := {}


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
	_seed = LineEdit.new()
	_seed.text = str(randi() % 1000000)
	_seed.custom_minimum_size = Vector2(160, 0)
	box.add_child(UiKit.row("Seed", _seed))
	_goal = OptionButton.new()
	for g: Array in GOALS:
		_goal.add_item(String(g[1]))
	_goal.selected = 0
	box.add_child(UiKit.row("Goal", _goal))
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
	who.add_child(UiKit.hint("A blank slate: no background, no flaws, nothing learned yet. Backgrounds and flaws come with the skills.", false))
	box.add_child(UiKit.button_row([UiKit.accent_button("Start", _start, "Wake at the farm"), UiKit.button("Back", queue_free, "Back to the menu")], true))


func choices() -> Dictionary:
	var options := {"goal": String(GOALS[_goal.selected][0])}
	for key: String in _picks:
		options[key] = String(LEVELS[(_picks[key] as OptionButton).selected][0])
	return options


func _start() -> void:
	var seed_text := _seed.text.strip_edges()
	var world_seed := seed_text.to_int() if seed_text.is_valid_int() else hash(seed_text)
	if on_start.is_valid():
		on_start.call(_name.text, world_seed, choices())
	queue_free()
