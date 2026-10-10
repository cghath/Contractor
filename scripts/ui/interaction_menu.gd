class_name InteractionMenu
extends Control
## ACE3-style interaction menu, local to the player (design doc "ACE-style interaction").
##
## Hold Left Ctrl (`interact`) and look at something within REACH: action points appear on
## items, downed bodies and standing squadmates. Move the cursor onto one to open its radial
## menu of actions, and let go of Left Ctrl to perform the highlighted one; letting go over
## nothing cancels. Left Ctrl + Left Alt (`self_interact`) opens the same kind of menu on
## your own body and gear. While the menu is open the mouse moves a cursor, not the view.
##
## What each kind of target offers is data (ACTIONS) read by the pure actions_for, so later
## work (treatments) adds entries rather than code paths. Anything that changes shared state
## is one of the body's host-side requests (Soldier._server_*); checks only read replicated
## state and show it locally.

enum Mode { CLOSED, OBJECT, SELF }

## How far from your eyes an action point can be (proposed, about ACE's reach).
const REACH := 3.0
## Left Ctrl must be held this long before the object menu shows, so pressing Ctrl then Alt
## goes straight to self-interaction without flashing the object menu.
const OPEN_DELAY_S := 0.15
## Action points show only for things within this angle of where you look.
const VIEW_CONE_DEG := 40.0
## The cursor opens an action point's menu within this many pixels of it.
const POINT_HOVER_PX := 28.0
const RING_RADIUS_PX := 120.0
const ENTRY_SIZE := Vector2(180.0, 26.0)
const SUB_GAP_PX := 8.0
## Most stowed entries the Give item submenu lists.
const MAX_GIVE_ENTRIES := 12
## Height of an action point above a body's origin: standing, and lying down.
const STANDING_POINT_Y := 1.3
const DOWNED_POINT_Y := 0.3

## Target kinds, the keys of ACTIONS.
const ITEM := &"item"
const DOWNED := &"downed"
const DEAD := &"dead"
const SQUADMATE := &"squadmate"
const SELF := &"self"

## Actions per target kind, in menu order. Keys:
## - id, label: what it is and what the menu shows (some labels get details, see _label).
## - needs: a condition (see _check) that hides the entry or greys it out with a reason.
## - request + with: the Soldier host-side request to send and its arguments: "target"
##   (the target's path), "none", "slot" (your active slot), "target_entry" (target path,
##   container, index; used by submenu entries).
## - show: a local readout instead of a request ("condition" or "wounds").
## - submenu: a list built at runtime ("stowed_items") whose entries take the parent's
##   request.
const ACTIONS := {
	ITEM: [
		{"id": &"pick_up", "label": "Pick up", "request": &"_server_interact", "with": &"target"},
	],
	DOWNED: [
		{"id": &"revive", "label": "Revive", "needs": &"revive_kit", "request": &"_server_revive", "with": &"target"},
		{"id": &"carry", "label": "Carry", "needs": &"can_move_body", "request": &"_server_carry_body", "with": &"target"},
		{"id": &"drag", "label": "Drag", "needs": &"can_move_body", "request": &"_server_drag_body", "with": &"target"},
		{"id": &"check_condition", "label": "Check condition", "show": &"condition"},
	],
	DEAD: [
		{"id": &"loot", "label": "Loot", "request": &"_server_loot_body", "with": &"target"},
		{"id": &"carry", "label": "Carry", "needs": &"can_move_body", "request": &"_server_carry_body", "with": &"target"},
		{"id": &"drag", "label": "Drag", "needs": &"can_move_body", "request": &"_server_drag_body", "with": &"target"},
	],
	SQUADMATE: [
		{"id": &"give_item", "label": "Give item", "submenu": &"stowed_items", "request": &"_server_give_item", "with": &"target_entry"},
	],
	SELF: [
		{"id": &"check_wounds", "label": "Check wounds", "show": &"wounds"},
		{"id": &"use_medical", "label": "Use medical", "needs": &"medical", "request": &"_server_use_medical", "with": &"none"},
		{"id": &"put_down", "label": "Put down", "needs": &"moving_body", "request": &"_server_release_body", "with": &"none"},
		{"id": &"drop_held", "label": "Drop held item", "needs": &"held_item", "request": &"_server_drop", "with": &"slot"},
	],
}
const _HIDE := "-"

const COLOUR_BG := Color(0.05, 0.07, 0.05, 0.82)
const COLOUR_TEXT := Color(1, 1, 1)
const COLOUR_HIGHLIGHT := Color("ffd35a")
const COLOUR_DISABLED := Color(0.55, 0.55, 0.55)
const COLOUR_POINT := Color("c8d6a0")

var player: Soldier
var mode := Mode.CLOSED
## The virtual cursor, in screen pixels.
var cursor := Vector2.ZERO
## Action points on screen: {"target": Node, "screen": Vector2, "actions": Array}.
var points: Array[Dictionary] = []
## Set when update_keys reports the keys let go: the action to perform ({} for none).
var chosen: Dictionary = {}
var _open_target: Node        # whose actions are showing
var _expanded := -1           # the ring entry whose submenu is showing
var _held_s := -1.0           # how long Left Ctrl has been held (< 0: not held)


func _init(p_player: Soldier = null) -> void:
	player = p_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- What a target offers (pure) ---------------------------------------------------------

## The kind of target `target` is for `actor` (a key of ACTIONS), or &"" for nothing.
static func target_kind(actor: Soldier, target: Node) -> StringName:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return &""
	if target == actor:
		return SELF
	if target is WorldItem:
		return ITEM
	var vitals := target.get_node_or_null(^"Vitals") as Vitals
	if vitals == null:
		return &""
	if vitals.downed:
		return DOWNED
	if vitals.is_dead() and target is Soldier:
		return DEAD
	if target is Soldier and vitals.is_up() and (target as Soldier).faction == actor.faction:
		return SQUADMATE
	return &""


## The actions `actor` can take on `target` right now, in menu order. Each is a copy of its
## ACTIONS entry plus "target", a final "label", "disabled" (a reason, or "") and, for a
## submenu, "items" (its entries, built the same way).
static func actions_for(actor: Soldier, target: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind := target_kind(actor, target)
	if kind == &"":
		return out
	for def: Dictionary in ACTIONS[kind]:
		var why := _check(def.get("needs", &""), actor, target)
		if why == _HIDE:
			continue
		var action := def.duplicate()
		action["target"] = target
		action["label"] = _label(def, actor, target)
		action["disabled"] = why
		if def.has("submenu"):
			action["items"] = _submenu(def, actor, target)
			if action.items.is_empty() and why == "":
				action["disabled"] = "Nothing stowed to give"
		out.append(action)
	return out


## "" if the condition is met, _HIDE to leave the entry out, or why it's greyed out.
static func _check(need: StringName, actor: Soldier, target: Node) -> String:
	match need:
		&"revive_kit":
			if target is Soldier and (target as Soldier).faction != actor.faction:
				return _HIDE  # no reviving the enemy
			return "" if actor._best_revive_kit() != null else "Needs an IFAK or trauma kit"
		&"can_move_body":
			if not target is Soldier:
				return _HIDE  # dummies stay on their stands
			if actor.carry_mode != &"":
				return "You're already moving someone"
			return "" if actor.inventory.hands == &"" else "Your hands are full"
		&"medical":
			return "" if _has_medical(actor) else "No medical supplies"
		&"moving_body":
			return "" if actor.carry_mode != &"" else _HIDE
		&"held_item":
			return "" if actor.inventory.hands != &"" or actor.active_weapon() != null else _HIDE
	return ""


static func _label(def: Dictionary, actor: Soldier, _target: Node) -> String:
	match def.id:
		&"revive":
			var kit := actor._best_revive_kit()
			return "Revive (%s, %.0f s)" % [kit.name, float(kit.stats.revive_s)] if kit else "Revive"
		&"put_down":
			return "Put down" if actor.carry_mode == Soldier.CARRY else "Let go"
		&"drop_held":
			var id := actor.inventory.hands
			if id == &"" and actor.active_weapon() != null:
				id = actor.active_weapon().id
			return "Drop %s" % ItemDB.get_item(id).name if id != &"" else String(def.label)
	return String(def.label)


static func _submenu(def: Dictionary, actor: Soldier, target: Node) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	match def.submenu:
		&"stowed_items":
			for container in Inventory.CONTAINERS:
				var list: Array = actor.inventory.containers[container]
				for i in list.size():
					if items.size() >= MAX_GIVE_ENTRIES:
						return items
					var entry: Dictionary = list[i]
					var item := ItemDB.get_item(entry.id)
					var detail := " (%d rds)" % int(entry.state.rounds) if entry.has("state") and entry.state.has("rounds") else ""
					items.append({"id": def.id, "label": item.name + detail, "request": def.request, "with": def.with,
						"target": target, "container": container, "index": i, "disabled": ""})
	return items


static func _has_medical(actor: Soldier) -> bool:
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in actor.inventory.containers[container]:
			if ItemDB.get_item(entry.id).stats.has("heal"):
				return true
	return false


# --- Doing it ------------------------------------------------------------------------------

## Performs `action` for `actor`: sends its host request, or reads out a check. Returns text
## to show the player ("" for none). An empty action, a submenu or a target that's gone does
## nothing.
static func perform(actor: Soldier, action: Dictionary) -> String:
	if action.is_empty() or action.has("items"):
		return ""
	if String(action.get("disabled", "")) != "":
		return action.disabled
	var target: Node = action.get("target")
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return ""
	match action.get("show", &""):
		&"condition":
			return condition_report(target)
		&"wounds":
			return wound_report(actor.vitals)
	var request: StringName = action.get("request", &"")
	if request == &"":
		return ""
	match action.get("with", &"none"):
		&"target":
			actor.rpc_id(1, request, target.get_path())
		&"slot":
			actor.rpc_id(1, request, actor.active_slot)
		&"target_entry":
			actor.rpc_id(1, request, target.get_path(), action.container, action.index)
		_:
			actor.rpc_id(1, request)
	return ""


## "Alpha: Down, 42 s" plus the wounds found, for Check condition.
static func condition_report(target: Node) -> String:
	var vitals := target.get_node_or_null(^"Vitals") as Vitals
	if vitals == null:
		return ""
	return "%s: %s\n%s" % [display_name(target), vitals.condition_text(), wound_report(vitals)]


## One line per wound ("Left thigh: arterial, bleeding"), or "No wounds found".
static func wound_report(vitals: Vitals) -> String:
	var wounds := vitals.wound_list()
	if wounds.is_empty():
		return "No wounds found" if vitals.injury() <= 0.0 or not vitals.is_up() else "Hurt, no open wounds found"
	var lines := PackedStringArray()
	for wound in wounds:
		lines.append("%s: %s%s" % [part_name(wound.get("part", &"")), wound.get("kind", "wound"),
			", bleeding" if wound.get("bleeding", false) else ""])
	return "\n".join(lines)


## "upper_arm_l" -> "Left upper arm".
static func part_name(part: StringName) -> String:
	var text := String(part)
	var side := ""
	if text.ends_with("_l"):
		side = "left "
	elif text.ends_with("_r"):
		side = "right "
	if side != "":
		text = text.left(-2)
	var words := side + text.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


static func display_name(target: Node) -> String:
	if target is Soldier:
		return (target as Soldier).display_name()
	if target is WorldItem:
		return ItemDB.get_item((target as WorldItem).item_id).name
	return String(target.name)


# --- Finding action points ---------------------------------------------------------------

## Action points `actor` can see through `camera`: everything within REACH, in front, in
## sight and with at least one action.
static func collect_points(actor: Soldier, camera: Camera3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var tree := actor.get_tree()
	var candidates: Array = tree.get_nodes_in_group(WorldItem.GROUP) + tree.get_nodes_in_group(&"combatants")
	for node: Node in candidates:
		if node == actor or not node is Node3D or node.is_queued_for_deletion():
			continue
		if node is Soldier and is_instance_valid((node as Soldier).carried_by):
			continue  # on someone's shoulder or being dragged
		var at := action_point(node as Node3D)
		var to := at - eye
		if to.length() > REACH or forward.angle_to(to) > deg_to_rad(VIEW_CONE_DEG) or camera.is_position_behind(at):
			continue
		if not _in_sight(actor, eye, at):
			continue
		var actions := actions_for(actor, node)
		if actions.is_empty():
			continue
		out.append({"target": node, "screen": camera.unproject_position(at), "actions": actions})
	return out


## Where `node`'s action point sits in the world.
static func action_point(node: Node3D) -> Vector3:
	if node is WorldItem:
		return node.global_position
	var vitals := node.get_node_or_null(^"Vitals") as Vitals
	var lying := vitals != null and not vitals.is_up()
	return node.global_position + Vector3.UP * (DOWNED_POINT_Y if lying else STANDING_POINT_Y)


## No wall between the eye and the point.
static func _in_sight(actor: Soldier, eye: Vector3, at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye, at, 1, [actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- The menu itself ---------------------------------------------------------------------

func is_open() -> bool:
	return mode != Mode.CLOSED


## Feeds the key state once a frame: `interact` is Left Ctrl held (and allowed), `self_held`
## Left Alt with it. Returns true on the frame the keys are let go with the menu open;
## `chosen` then holds the highlighted action ({} if the cursor was over nothing).
func update_keys(interact: bool, self_held: bool, delta: float) -> bool:
	if not interact:
		_held_s = -1.0
		if not is_open():
			return false
		chosen = release()
		return true
	_held_s = maxf(_held_s, 0.0) + delta
	if self_held and mode != Mode.SELF:
		open_self()
	elif mode == Mode.CLOSED and _held_s >= OPEN_DELAY_S:
		open_object()
	return false


## Opens the menu on the things around you; set_points fills in the action points.
func open_object() -> void:
	mode = Mode.OBJECT
	cursor = _centre()
	points = []
	_open_target = null
	_expanded = -1
	queue_redraw()


## Opens the menu on your own body and gear, already showing its actions.
func open_self() -> void:
	mode = Mode.SELF
	cursor = _centre()
	_open_target = player
	_expanded = -1
	refresh_self()


## Rebuilds the self actions (what you carry can change while the menu is open).
func refresh_self() -> void:
	points = [{"target": player, "screen": _centre(), "actions": actions_for(player, player)}]
	queue_redraw()


## Replaces the action points (object mode, once a frame), keeping the open one if it's still there.
func set_points(new_points: Array[Dictionary]) -> void:
	points = new_points.duplicate()  # never share the caller's array
	if _open_point().is_empty():
		_open_target = null
		_expanded = -1
	_update_hover()
	queue_redraw()


func move_cursor(relative: Vector2) -> void:
	set_cursor(cursor + relative)


func set_cursor(pos: Vector2) -> void:
	var size := _screen_size()
	cursor = Vector2(clampf(pos.x, 0.0, size.x), clampf(pos.y, 0.0, size.y))
	_update_hover()
	queue_redraw()


## Closes the menu and returns the highlighted action ({} if none, or a submenu parent).
func release() -> Dictionary:
	var action := highlighted()
	close()
	return {} if action.has("items") else action


func close() -> void:
	mode = Mode.CLOSED
	points = []
	_open_target = null
	_expanded = -1
	queue_redraw()


## The action under the cursor: a submenu entry, a ring entry, or {} for nothing.
func highlighted() -> Dictionary:
	var point := _open_point()
	if point.is_empty():
		return {}
	var actions: Array = point.actions
	if _expanded >= 0 and _expanded < actions.size():
		var sub: Array = actions[_expanded].get("items", [])
		var sub_rects := _sub_rects(point, _expanded)
		for j in sub_rects.size():
			if sub_rects[j].has_point(cursor):
				return sub[j]
	var rects := _ring_rects(point)
	for i in rects.size():
		if rects[i].has_point(cursor):
			return actions[i]
	return {}


## Screen rects of the open point's actions, around it in a ring.
func entry_rects() -> Array[Rect2]:
	return _ring_rects(_open_point())


## Screen rects of a ring entry's submenu.
func submenu_rects(index: int) -> Array[Rect2]:
	return _sub_rects(_open_point(), index)


func _open_point() -> Dictionary:
	if _open_target == null:
		return {}
	for p in points:
		if p.target == _open_target:
			return p
	return {}


func _update_hover() -> void:
	var point := _open_point()
	if not point.is_empty():
		var actions: Array = point.actions
		if _expanded >= 0 and _expanded < actions.size():
			for r in _sub_rects(point, _expanded):
				if r.has_point(cursor):
					return  # inside the open submenu
		var rects := _ring_rects(point)
		for i in rects.size():
			if rects[i].has_point(cursor):
				_expanded = i if actions[i].has("items") and not actions[i].items.is_empty() else -1
				return
	# Over an action point: open it (the nearest one wins).
	var best: Node = null
	var best_d := POINT_HOVER_PX
	for p in points:
		var screen: Vector2 = p.screen
		var d := screen.distance_to(cursor)
		if d <= best_d:
			best = p.target
			best_d = d
	if best != null and best != _open_target:
		_open_target = best
		_expanded = -1


func _ring_rects(point: Dictionary) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if point.is_empty():
		return rects
	var n: int = point.actions.size()
	for i in n:
		var angle := -PI * 0.5 + TAU * i / n if n > 1 else 0.0
		var centre: Vector2 = point.screen + Vector2.from_angle(angle) * RING_RADIUS_PX
		rects.append(Rect2(centre - ENTRY_SIZE * 0.5, ENTRY_SIZE))
	return rects


func _sub_rects(point: Dictionary, index: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if point.is_empty() or index < 0 or index >= point.actions.size():
		return rects
	var sub: Array = point.actions[index].get("items", [])
	var parent := _ring_rects(point)[index]
	var screen: Vector2 = point.screen
	var right := parent.get_center().x >= screen.x
	var x := parent.end.x + SUB_GAP_PX if right else parent.position.x - SUB_GAP_PX - ENTRY_SIZE.x
	var top := parent.get_center().y - (ENTRY_SIZE.y + 2.0) * sub.size() * 0.5
	for j in sub.size():
		rects.append(Rect2(Vector2(x, top + (ENTRY_SIZE.y + 2.0) * j), ENTRY_SIZE))
	return rects


func _centre() -> Vector2:
	return _screen_size() * 0.5


func _screen_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1152, 648)


func _draw() -> void:
	if not is_open():
		return
	var font := get_theme_default_font()
	var font_size := 15
	var lit := highlighted()
	for p in points:
		var open: bool = p.target == _open_target
		draw_circle(p.screen, 6.0 if open else 4.5, COLOUR_HIGHLIGHT if open else COLOUR_POINT)
		draw_arc(p.screen, 9.0, 0.0, TAU, 20, Color(0, 0, 0, 0.6), 1.5)
	var point := _open_point()
	if not point.is_empty():
		var actions: Array = point.actions
		var rects := _ring_rects(point)
		for i in rects.size():
			_draw_entry(font, font_size, rects[i], actions[i], lit, i == _expanded)
			draw_line(point.screen, rects[i].get_center(), Color(1, 1, 1, 0.15), 1.0)
		if _expanded >= 0 and _expanded < actions.size():
			var sub: Array = actions[_expanded].get("items", [])
			var sub_rects := _sub_rects(point, _expanded)
			for j in sub_rects.size():
				_draw_entry(font, font_size, sub_rects[j], sub[j], lit, false)
	draw_circle(cursor, 3.0, Color.WHITE)
	draw_arc(cursor, 5.0, 0.0, TAU, 16, Color.BLACK, 1.0)


func _draw_entry(font: Font, font_size: int, rect: Rect2, action: Dictionary, lit: Dictionary, expanded: bool) -> void:
	var disabled := String(action.get("disabled", "")) != ""
	var on := action == lit or expanded
	draw_rect(rect, COLOUR_BG)
	if on:
		draw_rect(rect, COLOUR_HIGHLIGHT, false, 1.5)
	var colour := COLOUR_DISABLED if disabled else (COLOUR_HIGHLIGHT if on else COLOUR_TEXT)
	var text := String(action.label) + ("  >" if action.has("items") and not action.items.is_empty() else "")
	var baseline := rect.position + Vector2(0.0, (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, colour)
