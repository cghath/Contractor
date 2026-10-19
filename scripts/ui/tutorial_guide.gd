class_name TutorialGuide
extends CanvasLayer
## The tutorial (Captain, 2026-10-14: "he needs a tutorial in the game at some point soon"; for
## cghath first): a solo session on the compound (Menu "Tutorial") with a panel down the left that
## walks a new player through the controls one step at a time. Each step says what to do and on
## which key (read from the live bindings, so a rebind shows), and ticks itself off when it's done:
## most on the action's press, some on what the player's body does (moved, stance, a tag on the
## target). Page Down skips a step. The player gets a radio, grenades and a med kit to try things
## with, and a stand-in enemy (TARGET, hold fire, not moving) stands across the yard. Local only:
## nothing here is sent anywhere. Proposed steps; text is the game's plain voice.

const NODE_NAME := "TutorialGuide"
const TARGET := "TutorialTarget"
const KIT: Array[StringName] = [&"radio", &"frag_grenade", &"smoke_grenade", &"ifak", &"tourniquet"]
const MOVE_M := 4.0
const SKIP_KEY := KEY_PAGEDOWN
const TICK_S := 0.2

## The steps in order: "text" (what to do), "keys" (actions whose keys are shown), and how it
## completes: "on" (any of these actions pressed), "raw" (any of these keycodes), or "check" (a
## method name on this node returning true once done).
const STEPS := [
	{"text": "Walk around: look with the mouse, move with", "keys": [&"move_forward", &"move_left", &"move_back", &"move_right"], "check": "_moved"},
	{"text": "Sprint: hold", "keys": [&"sprint"], "on": [&"sprint"]},
	{"text": "Crouch (a toggle)", "keys": [&"crouch"], "on": [&"crouch"]},
	{"text": "Go prone (a toggle; again to get up)", "keys": [&"prone"], "on": [&"prone"]},
	{"text": "Lean round a corner: hold", "keys": [&"lean_left", &"lean_right"], "on": [&"lean_left", &"lean_right"]},
	{"text": "Aim down the sights: hold the right mouse button", "keys": [], "on": [&"aim"]},
	{"text": "Fire: the left mouse button (the target across the yard won't shoot back)", "keys": [], "on": [&"fire"]},
	{"text": "Reload", "keys": [&"reload"], "on": [&"reload"]},
	{"text": "Switch the fire mode (single, burst, auto)", "keys": [&"fire_mode"], "on": [&"fire_mode"]},
	{"text": "Rest the weapon on a wall or a sandbag in front of you", "keys": [&"mount"], "on": [&"mount"]},
	{"text": "Take a grenade in hand (Fire throws, Aim lobs, the same key again puts it away)", "keys": [&"grenade"], "on": [&"grenade"]},
	{"text": "Open your inventory: gear, pouches, the backpack", "keys": [&"inventory"], "on": [&"inventory"]},
	{"text": "Hold Left Ctrl and look at a crate, a door or a person: the interaction menu", "keys": [], "on": [&"interact"]},
	{"text": "The medical menu: treat yourself or a squadmate (Shift + it treats yourself fast)", "keys": [&"medical_menu"], "on": [&"medical_menu"]},
	{"text": "The map: double-click to place a marker, right-click for orders", "keys": [&"map"], "on": [&"map"]},
	{"text": "Squad orders: ` (backquote) opens the command menu for everyone, F1-F8 picks a squadmate", "keys": [], "raw": [KEY_QUOTELEFT, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8]},
	{"text": "Tag the enemy across the yard for the squad: look at him and press (you need the radio you carry)", "keys": [&"tag_enemy"], "check": "_tagged"},
	{"text": "Night vision: flip it down or up (on a helmet with NVGs)", "keys": [&"nvg_toggle"], "on": [&"nvg_toggle"]},
]

var step := 0
var done := 0
var _panel: PanelContainer
var _title: Label
var _text: Label
var _keys: Label
var _list: Label
var _start := Vector3.INF
var _tick := 0.0


## Opens the tutorial in the level `from` is in (host, after it's up): the guide, the kit and the
## target. Returns the guide.
static func start(from: Node) -> TutorialGuide:
	var lvl := CompoundLevel.current(from)
	if lvl == null:
		return null
	var old := lvl.get_node_or_null(NODE_NAME)
	if old:
		old.free()
	var g := TutorialGuide.new()
	g.name = NODE_NAME
	lvl.add_child(g)
	return g


func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.PANEL_BG
	style.set_corner_radius_all(6)
	style.set_content_margin_all(UiKit.SPACE_M)
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.position = Vector2(UiKit.EDGE, 180)
	_panel.custom_minimum_size = Vector2(380, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	_panel.add_child(box)
	_title = _label(UiKit.FONT_HEADING, UiKit.ACCENT)
	_text = _label(UiKit.FONT_BODY, UiKit.TEXT)
	_keys = _label(UiKit.FONT_HEADING, UiKit.GOOD)
	_list = _label(UiKit.FONT_SMALL, UiKit.TEXT_DIM)
	for l in [_title, _text, _keys, _list]:
		box.add_child(l)
	_set_up_session.call_deferred()
	_show()


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(356, 0)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	return l


## Host: the kit to try things with, and the target across the yard.
func _set_up_session() -> void:
	var lvl := CompoundLevel.current(self)
	var me := MapNodes.local_player(self)
	if lvl == null or not multiplayer.is_server():
		return
	if me:
		for id in KIT:
			if me.inventory.count_of(id) == 0:
				me.inventory.take(id)
		_start = me.global_position
	if lvl.ai.get_node_or_null(NodePath(TARGET)) == null and lvl.has_method(&"spawn_soldier"):
		var at: Vector3 = (me.global_position if me else Vector3.ZERO) + Vector3(0, 0, -30)
		var target: Soldier = lvl.call(&"spawn_soldier", {"name": TARGET, "faction": "hostile", "variant": "urban", "pos": at,
			"loadout": ["plate_carrier", "helmet"], "combat": 0.1, "discipline": 1.0, "guard": true, "mode": "calm"})
		if target:
			var brain := SquadAI.of(target)
			if brain:
				brain.process_mode = Node.PROCESS_MODE_DISABLED  # a stand-in: it doesn't move or shoot


## The keys of `actions`, as the player has them bound now ("W / A / S / D").
static func keys_text(actions: Array) -> String:
	var out := PackedStringArray()
	for a: StringName in actions:
		for e in InputMap.action_get_events(a) if InputMap.has_action(a) else []:
			var k := e as InputEventKey
			if k:
				out.append(OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode))
				break
	return " / ".join(out)


func _show() -> void:
	if step >= STEPS.size():
		_title.text = "Tutorial: done (%d of %d)" % [done, STEPS.size()]
		_text.text = "That's the basics. Esc and Main menu to leave; host the campaign from there to start a company. The shooting range at the base and the vehicle range (Test zones) are good places to practise."
		_keys.text = ""
		_list.text = ""
		return
	var s: Dictionary = STEPS[step]
	_title.text = "Tutorial %d of %d" % [step + 1, STEPS.size()]
	_text.text = String(s.text)
	_keys.text = keys_text(s.get("keys", []))
	_list.text = "Page Down skips a step."


## Every peer, this player only: a step's action pressed.
func _input(event: InputEvent) -> void:
	if step >= STEPS.size() or event.is_echo():
		return
	var key := event as InputEventKey
	if key and key.pressed and key.physical_keycode == SKIP_KEY:
		_next(false)
		return
	var s: Dictionary = STEPS[step]
	for a: StringName in s.get("on", []):
		if InputMap.has_action(a) and event.is_action_pressed(a):
			_next(true)
			return
	if key and key.pressed and (key.physical_keycode in s.get("raw", []) or key.keycode in s.get("raw", [])):
		_next(true)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or step >= STEPS.size():
		return
	_tick = TICK_S
	var check := String((STEPS[step] as Dictionary).get("check", ""))
	if check != "" and bool(call(check)):
		_next(true)


## Marks the current step done (or skipped) and shows the next.
func _next(did: bool) -> void:
	if did:
		done += 1
	step += 1
	_show()


func _moved() -> bool:
	var me := MapNodes.local_player(self)
	if me == null:
		return false
	if not _start.is_finite():
		_start = me.global_position
	return Vector2(me.global_position.x - _start.x, me.global_position.z - _start.z).length() >= MOVE_M


func _tagged() -> bool:
	var tags := EnemyTags.of(self)
	return tags != null and tags.tags.has(TARGET)
