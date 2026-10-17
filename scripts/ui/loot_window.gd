class_name LootWindow
extends Control
## The loot window (Captain, 2026-10-15: "a loot menu that opens, kind of like Tarkov"): a
## two-pane window, inspired by Tarkov's, for a body (the dead, a downed or captured enemy) or
## a vehicle's hold. Left: what's there (worn gear, pouches, the carrier, the pack, pockets);
## right: you. Click a tile or drag it across to move it; "Take all ammo" and "Take all meds"
## sweep the stowed entries. Contents show after a search time (Soldier.loot_search_seconds);
## the window closes when you walk out of reach, are hit, or the target is gone. It only asks:
## every move is a host request (Soldier._server_loot_move / _server_loot_put /
## _server_loot_take_class) checked against the current state, so two players at one body never
## duplicate anything. docs/loot_window.md.

const TILE_W := 170.0
const TILE_H := 48.0
const ICON := 36
const PANEL_W := 1100.0
const PANE_H := 460.0
const OPEN_WAIT_S := 2.0

var player: Soldier
var source: Node  # a body (Soldier) or a Vehicle with a hold
## Host-given search time and when it ends (ticks); contents stay hidden until then.
var search_s := 0.0
var _search_end_ms := 0
var _awaiting := false
var _wait_s := 0.0
var _pain := 0.0  # your pain and wound count when it opened: a rise means you were hit
var _wounds := 0
var _queued := false

var _title: Label
var _status: Label
var _bar: ProgressBar
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _left_title: Label
var _right_title: Label
var _buttons: HFlowContainer


class LootTile extends Button:
	var data := {}
	var window: LootWindow

	func _get_drag_data(_at: Vector2) -> Variant:
		if window == null or disabled or data.is_empty():
			return null
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
		return {"loot": data}

	func _can_drop_data(_at: Vector2, d: Variant) -> bool:
		return window != null and window.can_drop(d, StringName(data.get("side", "")))

	func _drop_data(_at: Vector2, d: Variant) -> void:
		window.drop(d, StringName(data.get("side", "")))


func _init(p_player: Soldier) -> void:
	player = p_player


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.apply(self)
	visible = false
	add_child(UiKit.dim(0.7))
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := UiKit.panel(true)
	centre.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	UiKit.fit_width(root, PANEL_W)
	_title = UiKit.heading("")
	root.add_child(_title)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	root.add_child(_bar)
	_status = UiKit.hint("")
	root.add_child(_status)
	var panes := HBoxContainer.new()
	panes.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(panes)
	var left := _pane(&"src", panes)
	_left_title = left[0]
	_left_box = left[1]
	var right := _pane(&"me", panes)
	_right_title = right[0]
	_right_box = right[1]
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override(&"h_separation", UiKit.SPACE_S)
	root.add_child(_buttons)
	root.add_child(UiKit.hint("Click an item or drag it across to move it. Esc or Tab closes; walking away or being hit closes it too."))


## One pane (title, scrolling sections) that takes drops for `side`.
func _pane(side: StringName, parent: Control) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = 200.0
	parent.add_child(box)
	var title := UiKit.heading("")
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiKit.fit_height(scroll, PANE_H, 170.0)
	scroll.set_drag_forwarding(Callable(),
		func(_at: Vector2, d: Variant) -> bool: return can_drop(d, side),
		func(_at: Vector2, d: Variant) -> void: drop(d, side))
	box.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	scroll.add_child(sections)
	return [title, sections]


# --- Opening and closing ----------------------------------------------------------------

## Shows the window for `target` and waits for the host's search time (begin_search).
func open(target: Node) -> void:
	_disconnect()
	source = target
	_awaiting = true
	_wait_s = OPEN_WAIT_S
	search_s = 0.0
	_search_end_ms = 0
	_pain = player.vitals.pain()
	_wounds = player.vitals.wound_list().size()
	player.inventory.changed.connect(_queue_redraw)
	var inv := inventory_of(target)
	if inv and not inv.changed.is_connected(_queue_redraw):
		inv.changed.connect(_queue_redraw)
	visible = true
	_redraw()


## The host answered: the search takes `seconds` (0 for a place already searched).
func begin_search(seconds: float) -> void:
	_awaiting = false
	search_s = seconds
	_search_end_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_redraw()


func close(told := "") -> void:
	if not visible and source == null:
		return
	_disconnect()
	source = null
	_awaiting = false
	visible = false
	if player and player.multiplayer.has_multiplayer_peer():
		player.rpc_id(1, &"_server_loot_close")
	if told != "" and player and player.player_input:
		player.player_input.flash(told)


func _disconnect() -> void:
	if player and player.inventory.changed.is_connected(_queue_redraw):
		player.inventory.changed.disconnect(_queue_redraw)
	if source and is_instance_valid(source):
		var inv := inventory_of(source)
		if inv and inv.changed.is_connected(_queue_redraw):
			inv.changed.disconnect(_queue_redraw)


func is_open() -> bool:
	return visible and source != null


func searching() -> bool:
	return _awaiting or Time.get_ticks_msec() < _search_end_ms


## The inventory a loot target holds: a body's, a vehicle's hold, or a world cache's.
static func inventory_of(target: Node) -> Inventory:
	if target is Soldier:
		return (target as Soldier).inventory
	if target is Vehicle:
		return (target as Vehicle).cargo() as Inventory
	if target is WorldCache:
		return (target as WorldCache).cargo() as Inventory
	return null


## Why the window should close now ("" to stay): the target is gone, you are out of reach,
## down, or were hit.
func why_close() -> String:
	if source == null or not is_instance_valid(source) or source.is_queued_for_deletion():
		return "Gone"
	if not player.vitals.is_up():
		return "You can't loot now"
	var pain := player.vitals.pain()
	var wounds := player.vitals.wound_list().size()
	var hurt := pain > _pain + 0.01 or wounds > _wounds  # (the host alone knows when a round landed)
	_pain = minf(pain, _pain) if not hurt else pain
	_wounds = mini(wounds, _wounds) if not hurt else wounds
	if hurt:
		return "Hit, stopped looting"
	if source is Soldier:
		var body := source as Soldier
		if not body.lootable_by(player) and not body.vitals.is_dead():
			return "Can't loot them now"
		if body.body_point().distance_to(player.global_position) > Soldier.INTERACT_REACH + Soldier.INTERACT_SLACK:
			return "Moved away"
	elif source is Vehicle and not (source as Vehicle).in_reach(player):
		return "Moved away"
	elif source is WorldCache and not (source as WorldCache).in_reach(player):
		return "Moved away"
	return ""


func _process(delta: float) -> void:
	if not visible or source == null:
		return
	var why := why_close()
	if why != "":
		close(why)
		return
	if _awaiting:
		_wait_s -= delta
		if _wait_s <= 0.0:
			close("Can't open that")
		return
	if _search_end_ms > 0:
		var left := _search_end_ms - Time.get_ticks_msec()
		_bar.visible = left > 0
		_bar.value = 1.0 - clampf(float(left) / maxf(search_s * 1000.0, 1.0), 0.0, 1.0)
		if left <= 0:
			_search_end_ms = 0
			_redraw()


## Tab and Esc close the window before the GUI sees them.
func _input(event: InputEvent) -> void:
	if visible and source != null and (event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()
		if player._hud:
			player._hud.release_mouse_if_clear()


# --- Drawing -----------------------------------------------------------------------------

func _queue_redraw() -> void:
	if _queued:
		return
	_queued = true
	_deferred_redraw.call_deferred()


func _deferred_redraw() -> void:
	_queued = false
	if visible:
		_redraw()


func _redraw() -> void:
	if source == null or not is_instance_valid(source):
		return
	var who := source_name()
	_title.text = "Searching %s..." % who if searching() else who
	_status.text = "" if not searching() else "Contents show when the search is done."
	_bar.visible = searching() and not _awaiting
	_left_title.text = who
	_right_title.text = "You  (%.1f kg)" % player.load_kg if "load_kg" in player else "You"
	for box: VBoxContainer in [_left_box, _right_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	if searching():
		_left_box.add_child(UiKit.hint("Searching..."))
	else:
		_fill(_left_box, source, &"src")
	_fill(_right_box, player, &"me")
	_rebuild_buttons()


func source_name() -> String:
	if source is Soldier:
		return (source as Soldier).display_name()
	if source is Vehicle:
		return "%s (hold)" % (source as Vehicle).display_name()
	if source is WorldCache:
		return (source as WorldCache).display_name()
	return "Container"


## The sections of `owner`'s inventory: worn gear first (a body's; yours shown but not
## movable), then each container's entries.
func _fill(box: VBoxContainer, owner: Node, side: StringName) -> void:
	var inv := inventory_of(owner)
	if inv == null:
		return
	if owner is Vehicle or owner is WorldCache:
		var cargo := owner.call(&"cargo") as VehicleCargo
		var tiles: Array = []
		for i in cargo.entries().size():
			tiles.append(_entry_tile(side, VehicleCargo.HOLD, i, cargo.entries()[i]))
		_section(box, "Hold  (%.0f / %.0f L)" % [cargo.used_litres(), cargo.capacity_l], tiles)
		return
	var worn: Array = []
	for slot in Inventory.SLOTS:
		var id: StringName = inv.slots.get(slot, &"")
		if id != &"":
			var tile := _tile(side, slot, -1, id, "%s: %s%s" % [InventoryScreen.SLOT_NAMES.get(slot, String(slot)), ItemDB.get_item(id).name, InteractionMenu._rounds_text(inv.state_of(slot))])
			tile.disabled = side == &"me"
			worn.append(tile)
	for p: Dictionary in inv.attach_points():
		var att := inv.attachment(StringName(p.id))
		if not att.is_empty():
			var aid := StringName(att.id)
			var tile := _tile(side, Inventory.pouch_container(StringName(p.id)), -1, aid, ItemDB.get_item(aid).name)
			tile.disabled = side == &"me"
			worn.append(tile)
	if not worn.is_empty():
		_section(box, "Worn", worn)
	if owner == player and inv.hands != &"" and (source is Vehicle or source is WorldCache):
		_section(box, "Hands", [_tile(side, &"", 0, inv.hands, ItemDB.get_item(inv.hands).name)])
	for container in inv.search_containers():
		var tiles: Array = []
		var list: Array = inv.containers[container]
		for i in list.size():
			tiles.append(_entry_tile(side, container, i, list[i]))
		var note := ""
		if not Inventory.is_pouch_container(container):
			note = "  (%.1f / %.1f L)" % [inv.used(container), inv.capacity(container)]
		_section(box, inv.container_label(container) + note, tiles)


func _section(box: VBoxContainer, heading: String, tiles: Array) -> void:
	box.add_child(UiKit.hint(heading))
	if tiles.is_empty():
		box.add_child(UiKit.hint("(empty)"))
		return
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for t: Control in tiles:
		grid.add_child(t)


func _entry_tile(side: StringName, container: StringName, index: int, entry: Dictionary) -> Control:
	var item := ItemDB.get_item(entry.id)
	var count := " x%d" % int(entry.count) if int(entry.count) > 1 else ""
	return _tile(side, container, index, entry.id, "%s%s%s" % [item.name, count, InteractionMenu._rounds_text(entry.get("state", {}))])


func _tile(side: StringName, where: StringName, index: int, id: StringName, label: String) -> LootTile:
	var tile := LootTile.new()
	tile.window = self
	tile.data = {"side": side, "where": where, "index": index, "id": id}
	tile.text = label
	tile.clip_text = true
	tile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	tile.add_theme_constant_override(&"icon_max_width", ICON)
	var texture := ItemIcons.get_icon(id)
	if texture:
		tile.icon = texture
		tile.expand_icon = true
	ItemInfo.apply(tile, id)
	tile.pressed.connect(func() -> void: move(tile.data))
	return tile


func _rebuild_buttons() -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var can := not searching()
	var ammo := UiKit.button("Take all ammo", func() -> void: take_class(&"ammo"))
	var meds := UiKit.button("Take all meds", func() -> void: take_class(&"medical"))
	var everything := UiKit.button("Take everything", take_everything)
	for b: Button in [ammo, meds, everything]:
		b.disabled = not can
		_buttons.add_child(b)
	_buttons.add_child(UiKit.button("Close", close))


# --- Doing it (every one a host request) -------------------------------------------------

func can_drop(d: Variant, side: StringName) -> bool:
	return d is Dictionary and d.has("loot") and StringName(d.loot.get("side", "")) != side and not searching()


func drop(d: Variant, side: StringName) -> void:
	if can_drop(d, side):
		move(d.loot)


## Moves one tile across: theirs to you, or yours into the container.
func move(tile: Dictionary) -> void:
	if source == null or searching():
		return
	var path := source.get_path()
	if StringName(tile.side) == &"src":
		player.rpc_id(1, &"_server_loot_move", path, tile.where, tile.index, tile.id)
	elif int(tile.index) >= 0:
		player.rpc_id(1, &"_server_loot_put", path, tile.where, tile.index, tile.id)


func take_class(kind: StringName) -> void:
	if source != null and not searching():
		player.rpc_id(1, &"_server_loot_take_class", source.get_path(), kind)


func take_everything() -> void:
	if source == null or searching():
		return
	if source is Soldier:
		player.rpc_id(1, &"_server_loot_body", source.get_path())
	else:
		take_class(&"all")
