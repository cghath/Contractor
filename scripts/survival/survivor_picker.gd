class_name SurvivorPicker
extends VBoxContainer
## The survivor part of the New world screen (docs/survival_rpg.md section 3, calls 17, 84): a
## blank slate by default, or a background (+3 one line, +1 another) and flaws (1-3 points each)
## whose points buy line levels (Backgrounds). choice() is the Backgrounds choice dictionary; the
## points left show as they're spent, and valid_changed says whether Start may go (no overspend).
## Headless-safe: built in _init, read by tests through choice() and summary().

signal valid_changed(ok: bool)

var background := ""
var flaws: Array = []
var buys := {}
var _points: Label
var _bg_line: Label
var _flaw_boxes := {}
var _spins := {}


func _init() -> void:
	name = "SurvivorPicker"
	var options := [["", "Blank slate (nothing learned, no flaws)"]]
	for id: String in Backgrounds.ALL:
		var bg: Dictionary = Backgrounds.ALL[id]
		options.append([id, "%s (%s)" % [String(bg.name), _lines_text(bg.get("lines", {}))]])
	add_child(UiKit.row("Background", UiKit.picker(options, func(v: Variant) -> void: set_background(String(v)), "Who they were: a line +3, another +1")))
	_bg_line = UiKit.hint("A blank slate: every line at 0. Take flaws for points and spend them on lines below.", false)
	add_child(_bg_line)
	add_child(UiKit.heading("Flaws (points)"))
	var flow := HFlowContainer.new()
	for id: String in Backgrounds.FLAWS:
		var f: Dictionary = Backgrounds.FLAWS[id]
		var box := CheckBox.new()
		box.text = "%s (%d)" % [String(f.name), int(f.points)]
		box.tooltip_text = String(f.text) + (" (its effect comes later)" if bool(f.get("later", false)) else "")
		box.toggled.connect(func(on: bool) -> void: set_flaw(id, on))
		_flaw_boxes[id] = box
		flow.add_child(box)
	add_child(flow)
	add_child(UiKit.heading("Lines bought (1 point a level)"))
	var grid := HFlowContainer.new()
	for line: String in RpgLines.LINES:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = Backgrounds.BUY_CAP
		spin.step = 1
		spin.value_changed.connect(func(v: float) -> void: set_buy(line, int(v)))
		_spins[line] = spin
		var r := HBoxContainer.new()
		var l := Label.new()
		l.text = line.capitalize()
		l.custom_minimum_size = Vector2(90, 0)
		r.add_child(l)
		r.add_child(spin)
		grid.add_child(r)
	add_child(grid)
	_points = UiKit.text("")
	add_child(_points)
	_refresh()


static func _lines_text(lines: Dictionary) -> String:
	var parts := PackedStringArray()
	for line: String in lines:
		parts.append("%s %+d" % [line, int(lines[line])])
	return ", ".join(parts)


func set_background(id: String) -> void:
	background = id if Backgrounds.ALL.has(id) else ""
	_refresh()


func set_flaw(id: String, on: bool) -> void:
	if on and not id in flaws:
		flaws.append(id)
	elif not on:
		flaws.erase(id)
	_refresh()


func set_buy(line: String, n: int) -> void:
	if n <= 0:
		buys.erase(line)
	else:
		buys[line] = n
	_refresh()


func choice() -> Dictionary:
	return {"background": background, "flaws": flaws.duplicate(), "buys": buys.duplicate()}


func points_left() -> int:
	return Backgrounds.points(flaws) - Backgrounds.cost(buys)


## The plain text of the choice (tests, the hint line): who, the flaws, the start lines, the points.
func summary() -> String:
	var bg: Dictionary = Backgrounds.ALL.get(background, {})
	var start := Backgrounds.start_levels(choice())
	var lines := PackedStringArray()
	for line: String in RpgLines.LINES:
		if int(start.get(line, 0)) > 0:
			lines.append("%s %d" % [line, int(start[line])])
	return "%s; flaws: %s; starts with %s; %d points left" % [String(bg.get("name", "Blank slate")),
		", ".join(PackedStringArray(flaws.map(func(f: String) -> String: return String(Backgrounds.FLAWS[f].name)))) if not flaws.is_empty() else "none",
		", ".join(lines) if not lines.is_empty() else "nothing learned", points_left()]


func _refresh() -> void:
	var bg: Dictionary = Backgrounds.ALL.get(background, {})
	_bg_line.text = String(bg.get("line", "A blank slate: every line at 0. Take flaws for points and spend them on lines below."))
	var left := points_left()
	_points.text = summary() + ("" if left >= 0 else " (too many bought)")
	valid_changed.emit(Backgrounds.problem(choice()) == "")
