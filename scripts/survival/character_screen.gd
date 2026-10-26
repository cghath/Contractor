class_name CharacterScreen
extends PanelContainer
## The character screen, first form (docs/survival_rpg.md section 7): this peer's own survivor's
## twelve lines as bars with the next unlock named, the survivor level, the perks (and a pick
## when one is owed), the background and the flaws, from Rpg's copy (Rpg.net().my). TOGGLE_KEY
## shows and hides it, in survival only; the mouse is free while it's up (for the pick). The
## figure and the journal's tally come later. Headless-safe; text() is what tests read.

## Proposed: ] (right bracket), beside the body readout's backslash; every letter on foot is taken
## (controls.gd).
const TOGGLE_KEY := KEY_BRACKETRIGHT

var _box: VBoxContainer
var _view := {}


func _init() -> void:
	name = "CharacterScreen"
	visible = false
	_box = VBoxContainer.new()
	add_child(_box)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	position.x -= 24.0


func _ready() -> void:
	var n := Rpg.net()
	if n:
		n.changed.connect(func() -> void:
			if visible:
				refresh())


func toggle() -> void:
	visible = not visible and SurvivalLevel.of(self) != null
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Rebuilds from `view` (default: this peer's own copy).
func refresh(view: Dictionary = {}) -> void:
	if view.is_empty():
		var n := Rpg.net()
		view = n.my if n else {}
	_view = view
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(UiKit.heading("%s, survivor level %d" % [String(view.get("name", "You")), int(view.get("survivor_level", 0))]))
	var levels: Dictionary = view.get("levels", {})
	var lines: Dictionary = view.get("lines", {})
	for line: String in RpgLines.LINES:
		var lv := int(levels.get(line, 0))
		var next := RpgLines.next_unlock(line, lv)
		var caption := "%s %d%s" % [line.capitalize(), lv, ("  next: %s at %d" % [String(next[1]), int(next[0])]) if not next.is_empty() else ""]
		var bar := UiKit.budget_bar(RpgLines.progress(float(lines.get(line, 0.0))), 1.0, caption)
		bar.custom_minimum_size = Vector2(420, 20)
		_box.add_child(bar)
	var perks: Array = (view.get("perks", []) as Array) + (view.get("granted", []) as Array)
	_box.add_child(UiKit.text("Perks: %s" % (", ".join(PackedStringArray(perks.map(func(p: String) -> String: return String(Perks.info(p).get("name", p))))) if not perks.is_empty() else "none yet")))
	var owed := maxi(0, int(view.get("survivor_level", 0)) - (view.get("perks", []) as Array).size())
	if owed > 0:
		var options := []
		for id: String in Perks.ALL:
			if not id in perks and Perks.allowed(id, levels):
				options.append([id, "%s: %s" % [String(Perks.ALL[id].name), String(Perks.ALL[id].text)]])
		var chosen := [options[0][0] if not options.is_empty() else ""]
		_box.add_child(UiKit.row("A perk to pick (%d)" % owed, UiKit.picker(options, func(v: Variant) -> void: chosen[0] = String(v), "One per survivor level, for good")))
		var take := func() -> void:
			if Rpg.net() and String(chosen[0]) != "":
				Rpg.net().request_pick(String(chosen[0]))
		_box.add_child(UiKit.button("Take it", take, "Take the perk picked above"))
	var bg: Dictionary = Backgrounds.ALL.get(String(view.get("background", "")), {})
	_box.add_child(UiKit.text("Background: %s" % String(bg.get("name", "blank slate"))))
	var flaws: Array = view.get("flaws", [])
	_box.add_child(UiKit.text("Flaws: %s" % (", ".join(PackedStringArray(flaws.map(func(f: String) -> String: return String(Backgrounds.FLAWS.get(f, {}).get("name", f))))) if not flaws.is_empty() else "none")))


## The screen's words, top to bottom (tests).
func text() -> String:
	var out := PackedStringArray()
	for c in _box.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(_text_of(c))
	return "\n".join(out)


static func _text_of(c: Node) -> String:
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	var parts := PackedStringArray()
	for k in c.get_children():
		var t := _text_of(k)
		if t != "":
			parts.append(t)
	return " ".join(parts)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == TOGGLE_KEY and SurvivalLevel.of(self) != null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and SurvivalLevel.of(self) == null:
		visible = false
