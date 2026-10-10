class_name CommandMenu
extends PanelContainer
## Arma 3-style squad command menu, local to the player who opens it.
##
## F1-F8 select squadmates by their slot in the squad (fire team A is F1-F4, B is F5-F8;
## players can't be ordered), Shift adds to the selection, ` (tilde) selects them all, and
## Team > Select picks a fire team or colour team; selecting opens the menu. In the menu,
## 1-9 and 0 pick an entry, or scroll the
## mouse wheel to highlight one and click the middle mouse button. Backspace goes back a
## level and Esc closes. Orders go to the host as Soldier._server_squad_command.
##
## Entries with "cmd" are orders ("point": at the spot under the crosshair, "aim": at the
## enemy under it); entries with "select" change the selection (fire team or colour team)
## and keep the menu open.

const MENU := {
	"title": "Command",
	"items": [
		{"key": "1", "label": "Move", "items": [
			{"key": "1", "label": "Return to formation", "cmd": "follow"},
			{"key": "2", "label": "Move there", "cmd": "move", "point": true},
			{"key": "3", "label": "Stop", "cmd": "hold"},
		]},
		{"key": "2", "label": "Target", "items": [
			{"key": "1", "label": "Target that enemy", "cmd": "target", "aim": true},
			{"key": "2", "label": "No target", "cmd": "target:"},
		]},
		{"key": "3", "label": "Engage", "items": [
			{"key": "1", "label": "Open fire", "cmd": "open_fire"},
			{"key": "2", "label": "Hold fire", "cmd": "hold_fire"},
		]},
		{"key": "4", "label": "Mount", "items": []},
		{"key": "5", "label": "Status", "items": [
			{"key": "1", "label": "Report status", "cmd": "report"},
		]},
		{"key": "6", "label": "Action", "items": [
			{"key": "1", "label": "Throw smoke there", "cmd": "throw_smoke", "point": true},
			{"key": "2", "label": "Throw frag there", "cmd": "throw_frag", "point": true},
		]},
		{"key": "7", "label": "Combat mode", "items": [
			{"key": "1", "label": "Safe", "cmd": "mode:safe"},
			{"key": "2", "label": "Aware", "cmd": "mode:aware"},
			{"key": "3", "label": "Combat", "cmd": "mode:combat"},
			{"key": "4", "label": "Stealth", "cmd": "mode:stealth"},
		]},
		{"key": "8", "label": "Formation", "items": [
			{"key": "1", "label": "Wedge", "cmd": "formation:wedge"},
			{"key": "2", "label": "File", "cmd": "formation:file"},
			{"key": "3", "label": "Line", "cmd": "formation:line"},
			{"key": "4", "label": "Staggered column", "cmd": "formation:staggered column"},
		]},
		{"key": "9", "label": "Team", "items": [
			{"key": "1", "label": "Select fire team A", "select": "fire:0"},
			{"key": "2", "label": "Select fire team B", "select": "fire:1"},
			{"key": "3", "label": "Assign to team", "items": [
				{"key": "1", "label": "Red", "cmd": "team:red"},
				{"key": "2", "label": "Green", "cmd": "team:green"},
				{"key": "3", "label": "Blue", "cmd": "team:blue"},
				{"key": "4", "label": "Yellow", "cmd": "team:yellow"},
				{"key": "5", "label": "White (no team)", "cmd": "team:white"},
			]},
			{"key": "4", "label": "Select team", "items": [
				{"key": "1", "label": "Red", "select": "color:red"},
				{"key": "2", "label": "Green", "select": "color:green"},
				{"key": "3", "label": "Blue", "select": "color:blue"},
				{"key": "4", "label": "Yellow", "select": "color:yellow"},
			]},
		]},
		{"key": "0", "label": "Support", "items": [
			{"key": "1", "label": "Helicopter transport", "cmd": ""},
			{"key": "2", "label": "Resupply drop", "cmd": ""},
			{"key": "3", "label": "Fire support", "cmd": ""},
		]},
	],
}
const NUMBER_KEYS := {KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4", KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9", KEY_0: "0"}
const F_KEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]
## How far "Target that enemy" looks under the crosshair.
const AIM_RANGE := 300.0

var player: Soldier
## Names of the selected squadmates.
var selected := PackedStringArray()
var _stack: Array = []  # menu levels from the root down
var _highlight := 0
var _title: Label
var _rows: VBoxContainer


func _init(p_player: Soldier) -> void:
	player = p_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.05, 0.78)
	style.set_content_margin_all(10)
	add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_color_override(&"font_color", Color("c8d6a0"))
	box.add_child(_title)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position.x += 16
	visible = false


func is_open() -> bool:
	return visible


## The squad as numbered in the menu: by squad slot (fire team A, then B), so F1 is the
## first slot. Anyone without a slot yet comes last, players first.
func roster() -> Array[Soldier]:
	var out: Array[Soldier] = []
	var level := CompoundLevel.current(player)
	if level == null:
		return out
	for h in level.players.get_children():
		if h is Soldier and not h.is_queued_for_deletion():
			out.append(h as Soldier)
	for s in level.ai.get_children():
		if s is Soldier and s.faction == player.faction and not s.is_queued_for_deletion():
			out.append(s as Soldier)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return _roster_key(a) < _roster_key(b))
	return out


static func _roster_key(s: Soldier) -> String:
	if s.squad_slot >= 0:
		return "0%02d" % s.squad_slot
	return ("1%06d" % s.name.to_int()) if not s.is_ai() else "2" + String(s.name)


## "A, Team Leader" (plus the colour team if any): a squad member's place in the squad.
static func unit_tag(s: Soldier) -> String:
	var parts := PackedStringArray()
	if s.fire_team >= 0 and s.fire_team < Roles.TEAMS.size():
		parts.append(Roles.TEAMS[s.fire_team])
	if s.role != &"":
		parts.append(Roles.display_name(s.role))
	if s.color_team != "":
		parts.append(s.color_team.capitalize())
	return ", ".join(parts)


## Returns true if the event was a command-menu input.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key in F_KEYS:
			_select_number(F_KEYS.find(key) + 1, event.shift_pressed or event.ctrl_pressed)
			return true
		if key == KEY_QUOTELEFT:
			_select_all()
			return true
		if not visible:
			return false
		if NUMBER_KEYS.has(key):
			_pick_key(NUMBER_KEYS[key])
			return true
		if key == KEY_BACKSPACE:
			_back()
			return true
		if key == KEY_ESCAPE:
			close()
			return true
	if visible and event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_highlight = posmod(_highlight - 1, _level_items().size())
				_redraw()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_highlight = posmod(_highlight + 1, _level_items().size())
				_redraw()
				return true
			MOUSE_BUTTON_MIDDLE:
				_pick(_highlight)
				return true
	return false


func open() -> void:
	_stack = [MENU]
	_highlight = 0
	visible = true
	_redraw()


func close() -> void:
	visible = false
	_stack.clear()


func _select_number(n: int, add: bool) -> void:
	var units := roster()
	if n > units.size():
		return
	var unit := units[n - 1]
	if not unit.is_ai():
		player._hud.flash("%d is %s: you can't order players" % [n, "you" if unit == player else "a player"])
		return
	var callsign := String(unit.name)
	if not add and not visible:
		selected = PackedStringArray()
	if callsign in selected:
		selected.remove_at(selected.find(callsign))
	else:
		selected.append(callsign)
	if selected.is_empty():
		close()
	elif not visible:
		open()
	else:
		_redraw()


func _select_all() -> void:
	var all := PackedStringArray()
	for s in roster():
		if s.is_ai():
			all.append(String(s.name))
	if visible and selected.size() == all.size():
		selected = PackedStringArray()
		close()
		return
	selected = all
	open()


func _level_items() -> Array:
	return _stack[-1]["items"] if not _stack.is_empty() else []


func _pick_key(key: String) -> void:
	var items := _level_items()
	for i in items.size():
		if items[i]["key"] == key:
			_pick(i)
			return


func _pick(i: int) -> void:
	var items := _level_items()
	if i < 0 or i >= items.size():
		return
	var item: Dictionary = items[i]
	if item.has("items"):
		if (item["items"] as Array).is_empty():
			player._hud.flash("%s isn't in this build yet" % item["label"])
			return
		_stack.append(item)
		_highlight = 0
		_redraw()
		return
	if item.has("select"):
		_select_group(item["select"], item["label"])
		return
	var cmd: String = item.get("cmd", "")
	if cmd == "":
		player._hud.flash("%s isn't in this build yet" % item["label"])
		return
	if cmd == "report":
		_report()
		close()
		return
	var point := player.global_position
	if item.get("point", false):
		var hit: Variant = player.crosshair_ground()
		if hit == null:
			player._hud.flash("Look at a spot on the ground")
			return
		point = hit
	if item.get("aim", false):
		var enemy := enemy_under_crosshair()
		if enemy == null:
			player._hud.flash("Look at an enemy")
			return
		cmd = "%s:%s" % [cmd, enemy.name]
	player._server_squad_command.rpc_id(1, cmd, point, selected)
	player._hud.flash("%s: %s" % [_names(), item["label"]])
	close()


## The living enemy under the crosshair (hitbox or body, up to AIM_RANGE), or null.
func enemy_under_crosshair() -> Soldier:
	var camera := player.camera
	var from := camera.global_position
	var exclude: Array[RID] = [player.get_rid()]
	for child in player.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * AIM_RANGE,
		1 | Soldier.HITBOX_MASK | Soldier.BODY_LAYER, exclude)
	query.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	var enemy: Soldier = collider as Soldier
	if enemy == null and collider is Area3D:
		var vitals := Vitals.find_on(collider)
		enemy = vitals.get_parent() as Soldier if vitals else null
	if enemy == null or enemy.faction == player.faction or not enemy.vitals.is_up():
		return null
	return enemy


## Team menu: selects fire team "fire:<0|1>" or colour team "color:<colour>" (AI only).
func _select_group(spec: String, label: String) -> void:
	var parts := spec.split(":")
	var names := PackedStringArray()
	for s in roster():
		if not s.is_ai():
			continue
		if (parts[0] == "fire" and s.fire_team == parts[1].to_int()) or (parts[0] == "color" and s.color_team == parts[1]):
			names.append(String(s.name))
	if names.is_empty():
		player._hud.flash("Nobody to select: %s" % label)
		return
	selected = names
	_stack = [MENU]
	_highlight = 0
	_redraw()
	player._hud.flash("%s: %s" % [label.trim_prefix("Select "), ", ".join(names)])


func _back() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_highlight = 0
		_redraw()
	else:
		close()


func _report() -> void:
	var lines := PackedStringArray()
	for s in roster():
		if String(s.name) in selected:
			lines.append("%s [%s]: %s (%s)" % [s.name, unit_tag(s), s.ai_status, s.vitals.condition_text()])
	player._hud.flash("\n".join(lines))


func _names() -> String:
	var all := 0
	for s in roster():
		if s.is_ai():
			all += 1
	return "All" if selected.size() == all else ", ".join(selected)


func _redraw() -> void:
	var path := PackedStringArray([_names()])
	for i in range(1, _stack.size()):
		path.append(_stack[i]["label"])
	_title.text = "  >  ".join(path)
	for child in _rows.get_children():
		child.queue_free()
	var items := _level_items()
	for i in items.size():
		var item: Dictionary = items[i]
		var row := Label.new()
		var disabled: bool = (item.has("items") and (item["items"] as Array).is_empty()) or (item.has("cmd") and item["cmd"] == "")
		row.text = "%s  %s%s" % [item["key"], item["label"], "  >" if item.has("items") and not disabled else ""]
		var colour := Color(1, 1, 1) if not disabled else Color(0.55, 0.55, 0.55)
		if i == _highlight:
			colour = Color("ffd35a") if not disabled else Color(0.75, 0.68, 0.45)
		row.add_theme_color_override(&"font_color", colour)
		_rows.add_child(row)
