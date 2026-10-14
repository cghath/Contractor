class_name InventoryScreen
extends Control
## Tab inventory in the style of Star Citizen's personal inventory: the soldier in the middle
## (a live 3D preview of your loadout in a SubViewport, drag to turn him) with the equipment
## slots down both sides, containers on the left (carrier pouches, vest, pockets, backpack,
## hands, and what's on the ground nearby) as grids of item tiles with preview images
## (ItemIcons), and the selected item's details and actions on the right. The MOLLE view
## (click the carrier twice, or the MOLLE button) closes in on the carrier and lays its attach
## points down the sides, each with a line to where it sits, like SC's equipment attachment
## view.
##
## Drag a tile onto a container, a slot, an attach point, the soldier (equip or attach) or
## the ground panel (drop); right-click a tile for its actions, double-click for the first.
## Every action is a request to the host (Soldier._server_inventory_action and friends); the
## screen redraws when the replicated inventory changes, so it always shows the host's truth.

const SLOT_NAMES := {
	&"primary": "Primary", &"sidearm": "Sidearm", &"helmet": "Helmet", &"vest": "Carrier",
	&"backpack": "Backpack", &"plate_front": "Front plate", &"plate_back": "Back plate",
	&"plate_left": "Left plate", &"plate_right": "Right plate", &"launcher": "Launcher",
}
## Slots down each side of the soldier: every slot in Inventory.SLOTS has a tile (audit A2-06:
## the launcher had none). The launcher sits under the pack it's slung beside.
const LEFT_SLOTS: Array[StringName] = [&"helmet", &"vest", &"backpack", &"launcher", &"plate_left"]
const RIGHT_SLOTS: Array[StringName] = [&"primary", &"sidearm", &"plate_front", &"plate_back", &"plate_right"]
## How far the ground panel looks for items (metres): about the interaction reach.
const NEARBY_M := Soldier.INTERACT_RANGE + 0.8
const TILE := Vector2(96, 112)
const WIDE_TILE := Vector2(178, 58)
const ICON := 64
const WIDE_ICON := 44

const COL_BG := Color(0.03, 0.06, 0.08, 0.93)
const COL_PANEL := Color(0.06, 0.11, 0.14, 0.95)
const COL_TILE := Color(0.08, 0.14, 0.18, 1.0)
const COL_EDGE := Color(0.17, 0.32, 0.38)
const COL_ACCENT := Color(0.33, 0.85, 0.95)
const COL_TEXT := Color(0.82, 0.9, 0.92)
const COL_MUTED := Color(0.5, 0.62, 0.67)
## Attach points while a pouch is selected or dragged: the free ones it fits, and the rest.
const FITS_TINT := Color(0.6, 1.0, 0.65)
const DIMMED_ALPHA := 0.35
const COL_WARN := Color(0.95, 0.7, 0.3)

enum View { LOADOUT, MOLLE }

var player: Soldier
var view := View.LOADOUT
## What's selected: a tile source ({"kind": "entry" | "slot" | "point" | "nearby" | "hands", ...}).
var selected: Dictionary = {}

var _mass_label: Label
var _mass_bar: ProgressBar
var _containers_box: VBoxContainer
var _quick_box: HFlowContainer
var _left_slots: VBoxContainer
var _right_slots: VBoxContainer
var _doll_area: Control
var _doll_view: SubViewportContainer
var _doll_camera: Camera3D
var _doll_pivot: Node3D
var _doll_model: CharacterModel
var _overlay: Control
var _detail_box: VBoxContainer
var _view_buttons: Dictionary = {}  # View -> Button
var _menu: PopupMenu
var _menu_actions: Array = []
var _menu_src: Dictionary = {}  # the tile the open menu is for, to check it's still there
## Tiles on screen with their sources, so a click can restyle the selection without
## rebuilding them (rebuilding frees the pressed tile, and a drag can never start).
var _tiles: Array = []  # [tile, src, empty]
var _point_tiles: Dictionary = {}   # point id -> its tile (MOLLE view lines)
var _yaw := 0.0
var _turning := false
var _nearby_key := ""
var _nearby_clock := 0.0
var _redraw_queued := false


func _init(p_player: Soldier) -> void:
	player = p_player


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)
	root.add_child(_build_header())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 14)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_centre())
	body.add_child(_build_right())
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	player.inventory.changed.connect(_queue_redraw)
	visibility_changed.connect(_on_visibility)
	_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_nearby_clock -= delta
	if _nearby_clock <= 0.0:
		_nearby_clock = 0.5
		if _nearby_signature() != _nearby_key:
			_redraw()
	if _doll_pivot:
		_doll_pivot.rotation.y = _yaw
		_place_camera(delta)
	if _overlay and view == View.MOLLE:
		_overlay.queue_redraw()


func _on_visibility() -> void:
	if visible:
		_ensure_doll()
		_redraw()
	else:
		_turning = false


func _queue_redraw() -> void:
	if _redraw_queued:
		return
	_redraw_queued = true
	_deferred_redraw.call_deferred()


func _deferred_redraw() -> void:
	_redraw_queued = false
	_redraw()


# --- Layout ---------------------------------------------------------------------------------

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	header.add_child(_label("PERSONAL INVENTORY", 22, COL_ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	_mass_label = _label("", 15, COL_TEXT)
	header.add_child(_mass_label)
	_mass_bar = ProgressBar.new()
	_mass_bar.custom_minimum_size = Vector2(180, 14)
	_mass_bar.show_percentage = false
	_mass_bar.max_value = 45.0
	_mass_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mass_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	_mass_bar.add_theme_stylebox_override(&"fill", fill)
	_mass_bar.add_theme_stylebox_override(&"background", _box(COL_TILE, COL_EDGE, 1))
	header.add_child(_mass_bar)
	header.add_child(_label("TAB / ESC  CLOSE", 13, COL_MUTED))
	return header


func _build_left() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 330
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 0.9
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_label("CONTAINERS", 15, COL_ACCENT))
	_quick_box = HFlowContainer.new()
	column.add_child(_quick_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_containers_box = VBoxContainer.new()
	_containers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_containers_box.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_containers_box)
	return column


func _build_centre() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.25
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	for v: View in [View.LOADOUT, View.MOLLE]:
		var b := _button("LOADOUT" if v == View.LOADOUT else "MOLLE", _set_view.bind(v))
		b.toggle_mode = true
		b.tooltip_text = "Equipment slots" if v == View.LOADOUT else "The carrier's attach points: drag pouches, a knife or a radio pouch onto them"
		buttons.add_child(b)
		_view_buttons[v] = b
	column.add_child(buttons)
	_doll_area = Control.new()
	_doll_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_doll_area.clip_contents = true
	_doll_area.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_doll_area)
	_doll_area.set_drag_forwarding(Callable(), _can_drop.bind({"kind": "doll"}), _drop.bind({"kind": "doll"}))
	_doll_area.gui_input.connect(_doll_input)
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override(&"panel", _box(Color(0.04, 0.08, 0.1, 0.6), COL_EDGE, 1))
	_doll_area.add_child(frame)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_doll_area.add_child(_overlay)
	var sides := HBoxContainer.new()
	sides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sides.offset_left = 8
	sides.offset_right = -8
	sides.offset_top = 8
	sides.offset_bottom = -8
	sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll_area.add_child(sides)
	_left_slots = VBoxContainer.new()
	_left_slots.add_theme_constant_override(&"separation", 6)
	_left_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_left_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.add_child(_left_slots)
	var middle := Control.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.add_child(middle)
	_right_slots = VBoxContainer.new()
	_right_slots.add_theme_constant_override(&"separation", 6)
	_right_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_right_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.add_child(_right_slots)
	var hint := _label("Drag items between slots, pouches and containers; onto the soldier to equip, onto the ground to drop. Right-click for actions. Drag the soldier to turn him.", 12, COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	return column


func _build_right() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 300
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 0.8
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_label("DETAILS", 15, COL_ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_detail_box)
	return column


# --- 3D preview -----------------------------------------------------------------------------

## The soldier preview: the player's own body model and gear (a CharacterModel and a GearRig
## on the replicated inventory, so it shows pouches too) in a SubViewport with its own world.
## Made the first time the screen opens; not in headless runs, where nothing renders.
func _ensure_doll() -> void:
	if _doll_view or not ItemIcons.can_render() or not is_inside_tree():
		return
	_doll_view = SubViewportContainer.new()
	_doll_view.stretch = true
	_doll_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_doll_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll_area.add_child(_doll_view)
	_doll_area.move_child(_doll_view, 1)  # over the frame, under the lines and tiles
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	_doll_view.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.8, 0.88)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(160), 0)
	key.light_energy = 1.2
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(-20), 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.9, 1.0)
	viewport.add_child(rim)
	_doll_pivot = Node3D.new()
	viewport.add_child(_doll_pivot)
	_doll_model = CharacterModel.new()
	_doll_model.name = "Model"
	_doll_model.variant = player.model.variant if player.model else "multicam"
	_doll_pivot.add_child(_doll_model)
	var rig := GearRig.new()
	rig.name = "Gear"
	rig.inventory = player.inventory
	rig.model = _doll_model
	_doll_pivot.add_child(rig)
	_doll_camera = Camera3D.new()
	_doll_camera.fov = 30.0
	viewport.add_child(_doll_camera)
	_doll_camera.current = true
	_place_camera(1.0)


## The camera in front of the soldier: whole body (loadout), or close on the carrier (MOLLE).
func _place_camera(delta: float) -> void:
	if _doll_camera == null:
		return
	var focus := Vector3(0, 0.92, 0) if view == View.LOADOUT else Vector3(0, 1.22, 0)
	var distance := 4.6 if view == View.LOADOUT else 2.3
	var want := Transform3D(Basis(Vector3.UP, PI), focus + Vector3(0, 0.05, -distance))
	_doll_camera.transform = _doll_camera.transform.interpolate_with(want, minf(delta * 8.0, 1.0))


func _doll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_turning = event.pressed
	elif event is InputEventMouseMotion and _turning:
		_yaw += (event as InputEventMouseMotion).relative.x * 0.01


## Where attach point `p` is in the preview (doll-area coordinates), or null without one.
func _point_on_screen(p: Dictionary) -> Variant:
	if _doll_model == null or _doll_camera == null or _doll_model.torso == null:
		return null
	var at: Array = p.get("at", [0, 0.3, -0.18])
	var world := _doll_model.torso.global_transform * Vector3(float(at[0]), float(at[1]), float(at[2]))
	if _doll_camera.is_position_behind(world):
		return null
	return _doll_camera.unproject_position(world)


## MOLLE view: a line from each attach point's tile to where the point is on the carrier.
func _draw_overlay() -> void:
	if view != View.MOLLE:
		return
	var inv := player.inventory
	var origin := _overlay.get_global_rect().position
	for p: Dictionary in inv.attach_points():
		var tile: Control = _point_tiles.get(String(p.id))
		if tile == null or not is_instance_valid(tile) or not tile.is_inside_tree():
			continue
		var on_screen: Variant = _point_on_screen(p)
		if on_screen == null:
			continue
		var target: Vector2 = on_screen
		var rect := tile.get_global_rect()
		rect.position -= origin
		var from := Vector2(rect.end.x if rect.get_center().x < target.x else rect.position.x, rect.get_center().y)
		var colour := COL_ACCENT if not inv.attachment(StringName(p.id)).is_empty() else COL_MUTED
		if _is_selected({"kind": "point", "point": StringName(p.id)}):
			colour = COL_WARN
		_overlay.draw_line(from, target, Color(colour, 0.7), 1.5, true)
		_overlay.draw_circle(target, 4.0, colour)


func _set_view(v: View) -> void:
	view = v
	_redraw()


# --- Redraw ---------------------------------------------------------------------------------

func _redraw() -> void:
	if not visible or _containers_box == null:
		return
	var inv := player.inventory
	if inv.attach_points().is_empty() and view == View.MOLLE:
		view = View.LOADOUT
	_validate_selection()
	_tiles.clear()
	var mass := inv.total_mass()
	_mass_label.text = "MASS  %.1f kg" % mass
	_mass_bar.value = mass
	for v: View in _view_buttons:
		_view_buttons[v].set_pressed_no_signal(v == view)
	_view_buttons[View.MOLLE].disabled = inv.attach_points().is_empty()  # a carrier's or a pack's points
	_clear(_quick_box)
	for id: StringName in _loose_round_ids():
		if inv.loadable_rounds(id) > 0:
			var b := _button("Load magazines", load_magazines.bind(id))
			b.tooltip_text = "Load the %s magazines you carry from your loose %s" % [Inventory.calibre_of(ItemDB.get_item(id)), ItemDB.get_item(id).name]
			_quick_box.add_child(b)
	_redraw_containers()
	_redraw_doll_tiles()
	_redraw_details()
	if _overlay:
		_overlay.queue_redraw()


func _redraw_containers() -> void:
	var inv := player.inventory
	_clear(_containers_box)
	var pouches := inv.pouch_containers()
	if not pouches.is_empty():
		var panel := _section("POUCHES", "%d attached" % (inv.attachment_count() + inv.attachment_count(&"backpack")), {})
		var body: VBoxContainer = panel.get_meta(&"body")
		for c in pouches:
			var point := inv.attach_point(Inventory.point_of(c))
			var pouch := inv.pouch_item(c)
			body.add_child(_label("%s  ·  %s point  ·  %s" % [pouch.name, Inventory.POINT_TYPES.get(point.get("type", ""), ""), _fill_text(c)], 12, COL_MUTED))
			body.add_child(_entry_grid(c, true))
		_containers_box.add_child(panel)
	for c in Inventory.CONTAINERS:
		if inv.capacity(c) <= 0.0:
			continue
		var panel := _section(String(c).to_upper(), "%.1f / %.1f L" % [inv.used(c), inv.capacity(c)], {"kind": "container", "container": c})
		panel.get_meta(&"body").add_child(_entry_grid(c, false))
		_containers_box.add_child(panel)
	if inv.hands != &"":
		var panel := _section("HANDS", "", {})
		var grid := _grid()
		var item := ItemDB.get_item(inv.hands)
		grid.add_child(_tile({"kind": "hands", "id": inv.hands}, item.name, "%.1f kg" % item.mass_kg, inv.hands))
		panel.get_meta(&"body").add_child(grid)
		_containers_box.add_child(panel)
	var nearby := _nearby_items()
	_nearby_key = _nearby_signature()
	var ground := _section("NEARBY (GROUND)", "drop here", {"kind": "nearby"})
	var grid := _grid()
	for node: WorldItem in nearby:
		var item := ItemDB.get_item(node.item_id)
		var src := {"kind": "nearby", "path": node.get_path(), "id": node.item_id}
		grid.add_child(_tile(src, item.name, "x%d" % node.count if node.count > 1 else _condition(item, node.state), node.item_id))
	if nearby.is_empty():
		grid.add_child(_label("Nothing within reach", 12, COL_MUTED))
	ground.get_meta(&"body").add_child(grid)
	_containers_box.add_child(ground)


func _entry_grid(container: StringName, compact: bool) -> HFlowContainer:
	var inv := player.inventory
	var grid := _grid()
	var dst := {"kind": "container", "container": container}
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.set_drag_forwarding(Callable(), _can_drop.bind(dst), _drop.bind(dst))
	var entries: Array = inv.containers.get(container, [])
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var src := {"kind": "entry", "container": container, "index": i, "id": entry.id}
		grid.add_child(_tile(src, ItemDB.get_item(entry.id).name, _entry_readout(entry), entry.id))
	if entries.is_empty():
		grid.add_child(_label("empty" if compact else "(empty)  drag items here", 12, COL_MUTED))
		grid.custom_minimum_size.y = 26
	return grid


func _redraw_doll_tiles() -> void:
	var inv := player.inventory
	_clear(_left_slots)
	_clear(_right_slots)
	_point_tiles.clear()
	if view == View.LOADOUT:
		for slot: StringName in LEFT_SLOTS + RIGHT_SLOTS:
			if slot in Inventory.PLATE_SLOTS and not slot in inv.carrier_plate_slots():
				continue  # the carrier has no pocket for it
			(_left_slots if slot in LEFT_SLOTS else _right_slots).add_child(_slot_tile(slot))
		return
	# MOLLE: the attach points down the side of the screen they're on (the soldier faces us,
	# so his right is on our left), top to bottom.
	var left: Array = []
	var right: Array = []
	for p: Dictionary in inv.attach_points():
		var at: Array = p.get("at", [0, 0, 0])
		var ours_left := float(at[0]) > 0.0 or (float(at[0]) == 0.0 and String(p.get("face", "")) == "back" and float(at[1]) > 0.3)
		(left if ours_left else right).append(p)
	var by_height := func(a: Dictionary, b: Dictionary) -> bool: return float(a.at[1]) > float(b.at[1])
	left.sort_custom(by_height)
	right.sort_custom(by_height)
	for p: Dictionary in left:
		var tile := _point_tile(p)
		_point_tiles[String(p.id)] = tile
		_left_slots.add_child(tile)
	for p: Dictionary in right:
		var tile := _point_tile(p)
		_point_tiles[String(p.id)] = tile
		_right_slots.add_child(tile)
	_mark_points(StringName(selected.get("id", &"")))


## While a pouch (or knife) is selected or dragged, the free points it fits light up and the
## rest dim; anything else, all plain. (Captain's playtest P0164: four tries at Chest points
## nothing he held fitted.)
func _mark_points(id: StringName) -> void:
	var item := ItemDB.get_item(id) if id != &"" else null
	var attachable := Inventory.is_attachable(item)
	var inv := player.inventory
	for p: Dictionary in inv.attach_points():
		var tile: Control = _point_tiles.get(String(p.id))
		if tile == null or not is_instance_valid(tile):
			continue
		if not attachable:
			tile.modulate = Color.WHITE
		elif Inventory.point_types(p).any(func(t: String) -> bool: return t in item.stats.attach) and inv.attachment(StringName(p.id)).is_empty():
			tile.modulate = FITS_TINT
		else:
			tile.modulate = Color(1, 1, 1, DIMMED_ALPHA)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and visible:
		_mark_points(StringName(selected.get("id", &"")))  # back to what the selection shows


func _slot_tile(slot: StringName) -> Control:
	var inv := player.inventory
	var id: StringName = inv.slots[slot]
	var src := {"kind": "slot", "slot": slot, "id": id}
	if id == &"":
		return _tile(src, "empty", "", &"", SLOT_NAMES[slot].to_upper(), SLOT_NAMES[slot], true)
	var item := ItemDB.get_item(id)
	var readout := _condition(item, inv.state_of(slot))
	if slot == &"vest":
		readout = "%d / %d attached" % [inv.attachment_count(), inv.attach_points().size()]
	return _tile(src, item.name, readout if readout != "" else "%.1f kg" % item.mass_kg, id, "", SLOT_NAMES[slot], true)


func _point_tile(p: Dictionary) -> Control:
	var inv := player.inventory
	var point := StringName(p.id)
	var att := inv.attachment(point)
	var type_name: String = Inventory.types_text(Inventory.point_types(p), "/")  # a shared spot: "Utility/Radio"
	var caption := "%s · %s" % [type_name, p.get("face", "")]
	var src := {"kind": "point", "point": point, "id": StringName(att.get("id", ""))}
	if att.is_empty():
		return _tile(src, "empty", "", &"", type_name.to_upper(), caption, true)
	var item := ItemDB.get_item(StringName(att.id))
	var readout := _fill_text(Inventory.pouch_container(point)) if Inventory.is_pouch(item) else "%.2f kg" % item.mass_kg
	return _tile(src, item.name, readout, item.id, "", caption, true)


func _redraw_details() -> void:
	_clear(_detail_box)
	var inv := player.inventory
	if selected.is_empty():
		_detail_box.add_child(_wrapped("Select an item to see it here.", COL_MUTED))
		_detail_box.add_child(_wrapped("Carrying %.1f kg. Pockets %.1f / %.1f L." % [inv.total_mass(), inv.used(&"pockets"), Inventory.POCKETS_L], COL_TEXT))
		if view == View.MOLLE:
			_detail_box.add_child(_wrapped("MOLLE: drag a pouch, a knife or a radio pouch from your containers onto a free point that fits it, then drag magazines and gear into the pouch. Reloads pull from mag pouches first.", COL_MUTED))
		return
	var id: StringName = selected.get("id", &"")
	var item := ItemDB.get_item(id) if id != &"" else null
	if item == null:
		if selected.kind == "point":
			var p := inv.attach_point(selected.point)
			_detail_box.add_child(_label("Empty %s point" % Inventory.POINT_TYPES.get(p.get("type", ""), ""), 18, COL_TEXT))
			_detail_box.add_child(_wrapped("Fits: %s." % ", ".join(_fits_point(Inventory.point_types(p))), COL_MUTED))
		else:
			_detail_box.add_child(_label("Empty %s" % SLOT_NAMES.get(selected.get("slot", &""), "slot"), 18, COL_TEXT))
		return
	var big := _icon(id, 150)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_box.add_child(big)
	var title := _label(item.name, 18, COL_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(title)
	var state := _selected_state()
	var count := int(_selected_entry().get("count", 1))
	var lines := PackedStringArray()
	lines.append("%s%s" % [item.type.capitalize(), "  ·  %s slot" % SLOT_NAMES.get(item.slot, String(item.slot)) if item.slot != &"" else ""])
	lines.append("Mass %.2f kg   Volume %.2f L%s" % [Inventory.entry_mass({"id": id, "count": count, "state": state}), item.volume_l * count, "   x%d" % count if count > 1 else ""])
	if item.capacity_l > 0.0:
		lines.append("Adds %.1f L of storage" % item.capacity_l)
	var condition := _condition(item, state)
	if condition != "":
		lines.append(condition)
	if Inventory.is_attachable(item):
		lines.append("Attaches to: %s points" % ", ".join(PackedStringArray(item.stats.attach.map(func(t: String) -> String: return Inventory.POINT_TYPES.get(t, t)))))
	if Inventory.is_pouch(item):
		lines.append("Holds: %s" % _holds_text(item))
	if item.stats.has("molle"):
		lines.append("%d MOLLE attach points" % item.stats.molle.size())
	for line in lines:
		_detail_box.add_child(_wrapped(line, COL_MUTED))
	var actions := _actions_for(selected)
	if not actions.is_empty():
		var flow := HFlowContainer.new()
		for action: Array in actions:
			flow.add_child(_button(action[0], action[1]))
		_detail_box.add_child(flow)
	if selected.kind == "point" and Inventory.is_pouch(item):
		# A pouch on the carrier: what's in it, and a place to drop more.
		var c := Inventory.pouch_container(selected.point)
		_detail_box.add_child(_label("CONTENTS  %s" % _fill_text(c), 14, COL_ACCENT))
		_detail_box.add_child(_entry_grid(c, false))
	elif not state.get("molle", {}).is_empty():
		_detail_box.add_child(_label("ATTACHED", 14, COL_ACCENT))
		for point: String in state.molle:
			var att: Dictionary = state.molle[point]
			var held: Array = att.get("held", [])
			var att_item := ItemDB.get_item(StringName(att.get("id", "")))
			_detail_box.add_child(_label("%s: %s%s" % [point, att_item.name if att_item else "?", "  (%d inside)" % held.size() if not held.is_empty() else ""], 12, COL_MUTED))


# --- Actions --------------------------------------------------------------------------------

## The actions for a tile, as [label, Callable] pairs; the first is the double-click one.
func _actions_for(src: Dictionary) -> Array:
	var inv := player.inventory
	var out := []
	match String(src.get("kind", "")):
		"entry":
			var list: Array = inv.containers.get(src.container, [])
			if src.index >= list.size():
				return out
			var item := ItemDB.get_item(list[src.index].id)
			var c: StringName = src.container
			var i: int = src.index
			if item.slot != &"":
				out.append(["Equip", _action.bind("equip_entry", c, i, &"", &"")])
			if Inventory.is_attachable(item) and not inv.attach_points().is_empty():
				out.append(["Attach", _action.bind("attach", c, i, &"", &"")])
			for gun: StringName in [&"primary", &"sidearm"]:  # an optic onto a gun's rail (P0362)
				if Optics.is_optic(item) and Optics.mount_problem(inv, c, i, gun) == "":
					out.append(["Mount on " + ItemDB.get_item(inv.slots[gun]).name, _action.bind("mount_optic", c, i, gun, &"")])
			var use := _medical_use(item)
			if use.is_valid():
				out.append(["Use", use])
			if Inventory.is_loose_rounds(item) and inv.loadable_rounds(item.id) > 0:
				out.append(["Load magazines", load_magazines.bind(item.id)])
			if Inventory.is_pack(item):
				var rolled: bool = list[i].get("state", {}).get("rolled", false)
				out.append(["Unroll" if rolled else "Roll up", _action.bind("unroll_entry" if rolled else "roll_entry", c, i, &"", &"")])
			for other in inv.search_containers():
				if other != c and inv.room_for(other, item, list[i].get("state", {})) > 0:
					out.append(["> " + player.container_name(other), _action.bind("move_entry", c, i, &"", other)])
			out.append(["Drop", _action.bind("drop_entry", c, i, &"", &"")])
		"slot":
			var slot: StringName = src.slot
			if inv.slots[slot] == &"":
				return out
			if slot == &"vest":
				out.append(["MOLLE view", _set_view.bind(View.MOLLE)])
			if slot != &"vest" and slot != &"backpack":
				out.append(["Stow", _action.bind("stow_slot", &"", -1, slot, &"")])
			if Optics.on_slot(inv, slot) != null:  # P0362
				out.append(["Remove " + Optics.on_slot(inv, slot).name, _action.bind("remove_optic", &"", -1, slot, &"")])
			var gear := ItemDB.get_item(inv.slots[slot])
			if Inventory.is_attachable(gear) and inv.free_point_for(gear) != &"":  # a disposable launcher onto the pack's top
				out.append(["Pack on top", _action.bind("attach_slot", &"", -1, slot, &"")])
			out.append(["Drop", _action.bind("drop_slot", &"", -1, slot, &"")])
		"point":
			if inv.attachment(src.point).is_empty():
				return out
			var on_point := ItemDB.get_item(StringName(inv.attachment(src.point).id))
			if on_point and on_point.slot != &"":  # a launcher packed on top of the pack
				out.append(["Equip", _action.bind("equip_attachment", &"", -1, src.point, &"")])
			out.append(["Detach", _action.bind("detach", &"", -1, src.point, &"")])
			out.append(["Drop", _action.bind("drop_attachment", &"", -1, src.point, &"")])
		"nearby":
			out.append(["Pick up", _pick_up.bind(src.path)])
		"hands":
			out.append(["Drop", _drop_held])
	return out


func _action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	player._server_inventory_action.rpc_id(1, action, container, index, slot, target)


func _pick_up(path: NodePath) -> void:
	player._server_interact.rpc_id(1, path)


func _pick_up_into(path: NodePath, container: StringName) -> void:
	player._server_pick_up_into.rpc_id(1, path, container)


func _drop_held() -> void:
	player._server_drop.rpc_id(1, &"")


## Use for a medical entry, or an empty Callable: a kit treats your next need (like H); a
## loose kit item goes on the first of your wounds it's needed for.
func _medical_use(item: ItemData) -> Callable:
	if Inventory.is_kit(item):
		return func() -> void: player._server_use_medical.rpc_id(1)
	if not item.stats.has("treat_s") or Vitals.needs_other_hands(item.id):
		return Callable()
	for task in player.vitals.care_needed():
		if item.id in Vitals.task_items(task):
			return func() -> void: player._server_treat.rpc_id(1, player.get_path(), item.id, task.part, false)
	return Callable()


## "Load magazines" on a stack of loose rounds: the host fills the magazines of that
## calibre, fullest first, as a timed action (Soldier._server_load_mags).
func load_magazines(rounds_id: StringName) -> void:
	player._server_load_mags.rpc_id(1, rounds_id)


# --- Drag and drop --------------------------------------------------------------------------

func _get_drag(_at: Vector2, src: Dictionary, tile: Control) -> Variant:
	if StringName(src.get("id", &"")) == &"":
		return null
	var preview := _icon(src.id, 56)
	preview.modulate.a = 0.85
	tile.set_drag_preview(preview)
	_mark_points(StringName(src.id))
	return {"inventory_drag": src}


func _can_drop(_at: Vector2, data: Variant, dst: Dictionary) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("inventory_drag") and drop_action(data.inventory_drag, dst).is_valid()


func _drop(_at: Vector2, data: Variant, dst: Dictionary) -> void:
	var action := drop_action(data.inventory_drag, dst)
	if action.is_valid():
		action.call()


## What dropping the tile `src` on `dst` asks the host for, or an empty Callable if nothing.
## `dst`: {"kind": "container", "container"}, {"kind": "slot", "slot"}, {"kind": "point",
## "point"}, {"kind": "nearby"} (the ground) or {"kind": "doll"} (the soldier).
func drop_action(src: Dictionary, dst: Dictionary) -> Callable:
	var inv := player.inventory
	var id := StringName(src.get("id", &""))
	var item := ItemDB.get_item(id) if id != &"" else null
	if item == null:
		return Callable()
	var kind := String(dst.get("kind", ""))
	match String(src.kind):
		"entry":
			var c: StringName = src.container
			var i: int = src.index
			match kind:
				"container":
					if dst.container != c:
						return _action.bind("move_entry", c, i, &"", dst.container)
				"slot", "doll":
					if item.slot != &"":
						return _action.bind("equip_entry", c, i, &"", &"")
					if Inventory.is_attachable(item) and not inv.attach_points().is_empty():
						return _action.bind("attach", c, i, &"", &"")
				"point":
					if Inventory.is_attachable(item):
						return _action.bind("attach", c, i, &"", dst.point)
					var pc := Inventory.pouch_container(dst.point)
					if inv.containers.has(pc) and pc != c:
						return _action.bind("move_entry", c, i, &"", pc)
				"nearby":
					return _action.bind("drop_entry", c, i, &"", &"")
		"slot":
			match kind:
				"container":
					if not Inventory.is_pouch_container(dst.container):
						return _action.bind("stow_slot", &"", -1, src.slot, dst.container)
				"point":
					if Inventory.is_attachable(item):  # the launcher off the shoulder, onto the pack's top
						return _action.bind("attach_slot", &"", -1, src.slot, dst.point)
				"slot":
					if dst.slot == &"backpack" and src.slot != &"backpack" and Inventory.is_attachable(item):  # onto the pack: packed on top
						return _action.bind("attach_slot", &"", -1, src.slot, &"")
				"nearby":
					return _action.bind("drop_slot", &"", -1, src.slot, &"")
		"point":
			match kind:
				"point":
					if dst.point != src.point:
						return _action.bind("move_attachment", &"", -1, src.point, dst.point)
				"slot", "doll":
					if item.slot != &"":  # a packed launcher onto the shoulder
						return _action.bind("equip_attachment", &"", -1, src.point, &"")
				"container":
					if not Inventory.is_pouch_container(dst.container):
						return _action.bind("detach", &"", -1, src.point, dst.container)
				"nearby":
					return _action.bind("drop_attachment", &"", -1, src.point, &"")
		"nearby":
			# Into the container (or pouch) it was dragged onto; onto the body (a slot, the
			# soldier) it's picked up as a click would: a pack swaps for the worn one there only.
			# A two-handed load always goes into the hands, as a click takes it.
			if item.two_handed and kind in ["container", "slot", "point", "doll"]:
				return _pick_up.bind(src.path)
			if kind == "container":
				return _pick_up_into.bind(src.path, dst.container)
			if kind == "point" and not Inventory.is_attachable(item) and inv.containers.has(Inventory.pouch_container(dst.point)):
				return _pick_up_into.bind(src.path, Inventory.pouch_container(dst.point))
			if kind in ["slot", "point", "doll"]:
				return _pick_up.bind(src.path)
		"hands":
			if kind == "nearby":
				return _drop_held
	return Callable()


# --- Tiles ----------------------------------------------------------------------------------

## An item tile: preview image, name and a readout (`placeholder` text instead of an image
## for an empty slot or point; `caption` above, `wide` for the slots round the soldier).
## Click selects, double-click does its first action, right-click lists them; it drags, and
## takes drops where it stands (its slot, its point, its container, the ground).
func _tile(src: Dictionary, title: String, readout: String, id: StringName, placeholder := "", caption := "", wide := false) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = WIDE_TILE if wide else TILE
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := id == &""
	_style_tile(tile, _is_selected(src), empty)
	_tiles.append([tile, src, empty])
	var box: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6 if wide else 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override(&"separation", 0)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_px := WIDE_ICON if wide else ICON
	var picture: Control
	if empty:
		picture = CenterContainer.new()
		picture.custom_minimum_size = Vector2(edge_px, edge_px)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(_label(placeholder.left(6) if wide else placeholder, 9, COL_MUTED))
	else:
		picture = _icon(id, edge_px)
		picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if caption != "":
		(text_box if wide else box).add_child(_label(caption.to_upper(), 9, COL_ACCENT))
	box.add_child(picture)
	if wide:
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text_box)
	var name_label := _label(title, 11, COL_TEXT if not empty else COL_MUTED)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = (WIDE_TILE.x - WIDE_ICON - 24) if wide else (TILE.x - 12)
	(text_box if wide else box).add_child(name_label)
	if readout != "":
		var readout_label := _label(readout, 10, COL_MUTED)
		readout_label.clip_text = true
		readout_label.custom_minimum_size.x = name_label.custom_minimum_size.x
		(text_box if wide else box).add_child(readout_label)
	tile.tooltip_text = title + ("\n" + readout if readout != "" else "")
	var dst := _drop_target_of(src)
	tile.set_drag_forwarding(_get_drag.bind(src, tile), _can_drop.bind(dst), _drop.bind(dst))
	tile.gui_input.connect(_tile_input.bind(src, tile))
	return tile


## Where a drop on a tile goes: its slot, its attach point, its container, or the ground.
static func _drop_target_of(src: Dictionary) -> Dictionary:
	match String(src.kind):
		"slot": return {"kind": "slot", "slot": src.slot}
		"point": return {"kind": "point", "point": src.point}
		"entry": return {"kind": "container", "container": src.container}
		"nearby": return {"kind": "nearby"}
	return {"kind": "none"}


func _tile_input(event: InputEvent, src: Dictionary, tile: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			selected = src
			var actions := _actions_for(src)
			if not actions.is_empty():
				actions[0][1].call()
		elif src.kind == "slot" and src.slot == &"vest" and player.inventory.slots[&"vest"] != &"" and _is_selected(src):
			_set_view(View.MOLLE)  # a second click on the carrier: its attach points
			return
		else:
			selected = src
			_restyle_tiles()
			_redraw_details()
			tile.accept_event()
			return
		_redraw()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		selected = src
		_redraw_details()
		_menu_src = src.duplicate()
		_open_menu(_actions_for(src))
	tile.accept_event()


func _open_menu(actions: Array) -> void:
	if actions.is_empty():
		return
	_menu.clear()
	_menu_actions = actions
	for i in actions.size():
		_menu.add_item(actions[i][0], i)
	var at := Vector2i(get_viewport().get_mouse_position())
	if not get_viewport().gui_embed_subwindows:
		at = DisplayServer.mouse_get_position()
	_menu.reset_size()
	_menu.popup(Rect2i(at, Vector2i.ZERO))


func _on_menu(id: int) -> void:
	if not _still_there(_menu_src):
		_redraw()  # it moved or went while the menu was open: don't act on what's there now
		return
	if id >= 0 and id < _menu_actions.size():
		_menu_actions[id][1].call()


## The preview image of item `id` (ItemIcons), or a coloured tile with its short name until
## (or unless) one is rendered.
func _icon(id: StringName, edge: int) -> Control:
	var texture := ItemIcons.get_icon(id)
	if texture:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.custom_minimum_size = Vector2(edge, edge)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	if ItemIcons.can_render() and not ItemIcons._cache.has(id):
		var icons := ItemIcons.instance()
		if icons and not icons.icon_ready.is_connected(_on_icon_ready):
			icons.icon_ready.connect(_on_icon_ready)
	var item := ItemDB.get_item(id)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(edge, edge)
	swatch.color = WorldItem.color_for(item).darkened(0.25) if item else COL_TILE
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := Label.new()
	text.text = String(item.stats.get("short", item.name.get_slice(" ", 0))) if item else "?"
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override(&"font_size", 10 if edge < 100 else 18)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_child(text)
	return swatch


func _on_icon_ready(_id: StringName) -> void:
	_queue_redraw()


# --- Helpers --------------------------------------------------------------------------------

func _section(title: String, info: String, dst: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _box(COL_PANEL, COL_EDGE, 1))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if not dst.is_empty() else Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_label(title, 14, COL_ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	head.add_child(_label(info, 12, COL_MUTED))
	box.add_child(head)
	panel.set_meta(&"body", box)
	if not dst.is_empty():
		panel.set_drag_forwarding(Callable(), _can_drop.bind(dst), _drop.bind(dst))
	return panel


func _grid() -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	return grid


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _wrapped(text: String, colour: Color) -> Label:
	var label := _label(text, 12, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 260
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


static func _box(bg: Color, edge: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(2)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


func _style_tile(tile: PanelContainer, chosen: bool, empty: bool) -> void:
	var edge := COL_WARN if chosen else (COL_EDGE if not empty else Color(COL_EDGE, 0.6))
	tile.add_theme_stylebox_override(&"panel", _box(COL_TILE if not empty else Color(COL_TILE, 0.5), edge, 2 if chosen else 1))


func _restyle_tiles() -> void:
	for t: Array in _tiles:
		if is_instance_valid(t[0]):
			_style_tile(t[0], _is_selected(t[1]), t[2])
	if _overlay:
		_overlay.queue_redraw()  # the MOLLE view's line to the selected point


## Whether what tile source `src` pointed at is still there (same item, same place).
func _still_there(src: Dictionary) -> bool:
	if src.is_empty():
		return false
	var inv := player.inventory
	match String(src.kind):
		"entry":
			var list: Array = inv.containers.get(src.container, [])
			return src.index < list.size() and list[src.index].id == src.get("id")
		"slot":
			return inv.slots.get(src.slot, &"") == src.get("id", inv.slots.get(src.slot, &""))
		"point":
			return StringName(inv.attachment(src.point).get("id", "")) == src.get("id", StringName(inv.attachment(src.point).get("id", "")))
		"nearby":
			return get_node_or_null(src.path) != null
		"hands":
			return inv.hands != &""
	return true


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _is_selected(src: Dictionary) -> bool:
	if selected.is_empty() or selected.kind != src.get("kind"):
		return false
	match String(src.kind):
		"entry": return selected.container == src.container and selected.index == src.index
		"slot": return selected.slot == src.slot
		"point": return selected.point == src.point
		"nearby": return selected.path == src.path
		"hands": return true
	return false


## Drops the selection when what it pointed at has gone (or changed), and keeps its id current.
func _validate_selection() -> void:
	if selected.is_empty():
		return
	var inv := player.inventory
	match String(selected.kind):
		"entry":
			var list: Array = inv.containers.get(selected.container, [])
			if selected.index >= list.size() or list[selected.index].id != selected.id:
				selected = {}
		"slot":
			selected.id = inv.slots.get(selected.slot, &"")
		"point":
			if inv.attach_point(selected.point).is_empty():
				selected = {}
			else:
				selected.id = StringName(inv.attachment(selected.point).get("id", ""))
		"nearby":
			if get_node_or_null(selected.path) == null:
				selected = {}
		"hands":
			if inv.hands == &"":
				selected = {}


func _selected_entry() -> Dictionary:
	match String(selected.get("kind", "")):
		"entry":
			var list: Array = player.inventory.containers.get(selected.container, [])
			if selected.index < list.size():
				return list[selected.index]
		"nearby":
			var node := get_node_or_null(selected.path) as WorldItem
			if node:
				return {"id": node.item_id, "count": node.count, "state": node.state}
	return {}


func _selected_state() -> Dictionary:
	match String(selected.get("kind", "")):
		"slot":
			return player.inventory.state_of(selected.slot)
		"point":
			var att := player.inventory.attachment(selected.point)
			return {"held": att.held} if att.has("held") else {}
	return _selected_entry().get("state", {})


func _entry_readout(entry: Dictionary) -> String:
	var item := ItemDB.get_item(entry.id)
	var parts := PackedStringArray()
	if int(entry.count) > 1:
		parts.append("x%d" % int(entry.count))
	var condition := _condition(item, entry.get("state", {}))
	parts.append(condition if condition != "" else "%.1f kg" % Inventory.entry_mass(entry))
	return "  ".join(parts)


## A short condition readout: rounds, what's left in a kit, armor damage, what's in a pouch,
## a carrier's attachments.
static func _condition(item: ItemData, state: Dictionary) -> String:
	if item == null:
		return ""
	var detail := _detail(item, state).strip_edges()
	if detail.begins_with("[") and detail.ends_with("]"):
		detail = detail.substr(1, detail.length() - 2)
	if detail == "" and item.magazine_rounds() > 0 and not Inventory.is_loose_rounds(item) and item.type == "ammo":
		detail = "%d/%d rds" % [int(state.get("rounds", item.magazine_rounds())), item.magazine_rounds()]
	if detail == "" and not state.get("held", []).is_empty():
		detail = "%d inside" % state.held.reduce(func(a: int, e: Dictionary) -> int: return a + int(e.count), 0)
	if detail == "" and not state.get("molle", {}).is_empty():
		detail = "%d attached" % state.molle.size()
	return detail


static func _detail(item: ItemData, state: Dictionary) -> String:
	if Inventory.is_kit(item):
		return "  [%s]" % Inventory.kit_text(item, state)  # what's left in the kit
	if state.has("rounds") and item.type == "weapon":
		var optic := Optics.label(item, state)  # what's on its rail (P0362)
		return "  [%d loaded%s]" % [int(state.rounds), ", " + optic if optic != "" else ""]
	if Launchers.is_launcher(item):  # loaded with what, or empty (a fired disposable is gone)
		var w := Launchers.loaded_warhead(item, state)
		return "  [%s loaded]" % String(w).replace("_", " ").to_upper() if w != &"" else "  [empty]"
	if state.get("rolled", false):
		return "  [rolled]"
	if state.has("rounds") and int(state.rounds) < item.magazine_rounds():
		return "  [%d/%d rds]" % [int(state.rounds), item.magazine_rounds()]
	if item.is_voxel_armor():
		var damage := ArmorRules.state_text(item, state)  # "3 cracks, 46%", "shattered"...
		return "  [%s]" % damage if damage != "" else ""
	return ""


## "1/2" for a pouch counted in units, "0.4/1.2 L" for one counted in litres.
func _fill_text(container: StringName) -> String:
	var inv := player.inventory
	var pouch := inv.pouch_item(container)
	if pouch == null:
		return ""
	var max_units := int(pouch.stats.get("max_units", 0))
	if max_units > 0:
		return "%d/%d" % [inv.units_in(container), max_units]
	return "%.1f/%.1f L" % [inv.used(container), inv.capacity(container)]


static func _holds_text(pouch: ItemData) -> String:
	var what := PackedStringArray()
	for rule: String in pouch.stats.get("accepts", []):
		if rule.begins_with("type:"):
			what.append(rule.substr(5))
		elif rule.begins_with("tag:"):
			what.append(rule.substr(4) + "s")
		elif ItemDB.has_item(StringName(rule)):
			what.append(ItemDB.get_item(StringName(rule)).name)
	var text := ", ".join(what) if not what.is_empty() else "anything small"
	if pouch.stats.has("max_units"):
		text += " (%d)" % int(pouch.stats.max_units)
	if pouch.stats.has("capacity_l"):
		text += " (%.1f L)" % float(pouch.stats.capacity_l)
	return text


## Names of the attachables that fit any of a point's types, for an empty point's details.
static func _fits_point(kinds: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if Inventory.is_attachable(item) and kinds.any(func(k: String) -> bool: return k in item.stats.attach):
			out.append(item.name)
	out.sort()
	return out


func _loose_round_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c in player.inventory.search_containers():
		for entry: Dictionary in player.inventory.containers[c]:
			var item := ItemDB.get_item(entry.id)
			if Inventory.is_loose_rounds(item) and not item.id in out:
				out.append(item.id)
	return out


func _nearby_items() -> Array:
	var out := []
	if not player.is_inside_tree() or not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item and not item.is_queued_for_deletion() and item.global_position.distance_to(player.global_position) <= NEARBY_M:
			out.append(item)
	out.sort_custom(func(a: WorldItem, b: WorldItem) -> bool: return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	return out.slice(0, 24)


func _nearby_signature() -> String:
	var parts := PackedStringArray()
	for item: WorldItem in _nearby_items():
		parts.append("%s:%d" % [item.name, item.count])
	return ",".join(parts)
