class_name ArmoryRoom
extends Control
## The 3D armory (claude/loadout-3d; Captain, 2026-10-22: the loadout and armory "3d like i told
## you to"). A room at the base, the FOB or on the LHD (wherever the base screen is) with the
## company's gear on shelves by kind: weapons, optics, armour, packs, pouches, ammo, medical,
## grenades and the rest, each item as its own voxel model (ItemArt, the plates and helmets as
## their VoxelArmor pieces). It is a view over the existing data, not a second shop: the stash
## (BaseHub.view), the shop's and quartermasters' prices (BaseEconomy.item_price, Quartermaster)
## and the base's buy request (BaseHub "buy").
##
## Point at an item: it lights up and the panel on the right shows its price, what it is and
## does, and how many the company has. Buy it there (B; five at a time for ammo and medical), or
## Fit on me (F) or drag it onto your soldier standing in the room: the 3D loadout editor opens
## with it fitted as a draft. Drag (empty space) or A/D turn the view, the wheel zooms, the
## kind buttons (or 1-9) walk to that shelf, and the search finds an item and points at it.

signal closed

## The shelves: [group, metres from the room centre, facing (degrees)]; a ring round the soldier.
const SHELF_RING_M := 4.2
## Items a shelf shows at most (owned first, then the cheapest); the search reaches them all.
const PER_SHELF := 40
const SHELF_W := 2.4
const SHELF_LEVELS := [0.35, 0.95, 1.55, 2.15]
const ITEM_GAP := 0.06
## How big a shelf item may be drawn (metres, the longest side); bigger models are scaled down.
const MAX_ITEM_M := 0.9
const TURN_PER_PX := 0.006
## Where your soldier stands from the camera (ahead, to the right), the drop target in view.
const SOLDIER_AHEAD_M := 1.7
const SOLDIER_RIGHT_M := 1.25
const ZOOM_MIN := 1.9
const CLICK_PX := 5.0
const HELP := [
	"The company's gear on shelves by kind. Point at an item for its price, stats and how many the company has.",
	"Buy it from the panel (B), or Fit on me (F): the 3D loadout editor opens with it on your soldier. You can also drag an item onto the soldier in the middle of the room.",
	"Drag empty space or use A and D to look round, the wheel to zoom, 1-9 or the kind buttons to walk to a shelf, and the search to find anything.",
]
const KEYS := [["Point", "Item info"], ["B", "Buy"], ["F", "Fit on me"], ["Drag", "Look / drag to soldier"], ["1-9", "Shelf"], ["Esc", "Close"]]

var viewport: SubViewport
var camera: Camera3D
var view_box: SubViewportContainer
var info_box: VBoxContainer
var status: Label
var marker: MeshInstance3D
var soldier: Node3D
## Every item on the shelves: [{"id", "node", "aabb" (world)}].
var items: Array = []
var hovered := ""
var picked := ""
var yaw := 0.0
var _want_yaw := 0.0
var _distance := 2.6
var _press_at := Vector2.ZERO
var _pressed := false
var _dragging := false
var _drag_item := ""
var _query := ""
var _stash_hash := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.apply(self)
	var panel := UiKit.panel(true)
	panel.name = "Panel"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	var head := UiKit.header("Armory", "The company's gear on the shelves: point at anything for its price and stats, buy it, or fit it on your soldier.",
		PackedStringArray(HELP), KEYS, false)
	var close_button := UiKit.button("Close [Esc]", close, "Close the armory (Esc)")
	close_button.name = "Close"
	(head.get_child(0) as HBoxContainer).add_child(close_button)
	root.add_child(head)
	var kinds: Array = []
	for i in Loadouts.GROUPS.size():
		var g := Loadouts.GROUPS[i]
		var b := UiKit.button("%s [%d]" % [Loadouts.GROUP_NAMES[g], i + 1], walk_to.bind(g), "Walk to the %s shelf (%d)" % [String(Loadouts.GROUP_NAMES[g]).to_lower(), i + 1])
		b.name = "Kind_" + g
		kinds.append(b)
	var search := UiKit.search_field("Find an item...", func(t: String) -> void:
		_query = t.strip_edges().to_lower()
		find_item(_query))
	search.name = "Search"
	kinds.append(search)
	root.add_child(UiKit.button_row(kinds))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(body)
	view_box = SubViewportContainer.new()
	view_box.name = "Room"
	view_box.stretch = true
	view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_box.size_flags_stretch_ratio = 2.0
	view_box.custom_minimum_size = Vector2(200, 110)
	view_box.mouse_filter = Control.MOUSE_FILTER_STOP
	view_box.gui_input.connect(_room_input)
	body.add_child(view_box)
	var side := ScrollContainer.new()
	side.name = "Side"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side)
	info_box = VBoxContainer.new()
	info_box.name = "Info"
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	side.add_child(info_box)
	status = UiKit.text("")
	status.name = "Status"
	root.add_child(status)
	_build_room()
	BaseHub.view_changed.connect(_on_view)
	BaseHub.note.connect(_on_note)
	_show_info()
	walk_to(Loadouts.GROUPS[0])


func _exit_tree() -> void:
	if BaseHub.view_changed.is_connected(_on_view):
		BaseHub.view_changed.disconnect(_on_view)
	if BaseHub.note.is_connected(_on_note):
		BaseHub.note.disconnect(_on_note)


func close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


# --- The room ---------------------------------------------------------------------------------

func _build_room() -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	view_box.add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.075, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.68)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	var lamp := OmniLight3D.new()  # the strip light over the middle
	lamp.position = Vector3(0, 3.2, 0)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.6
	lamp.shadow_enabled = true
	viewport.add_child(lamp)
	_box(Vector3(0, -0.05, 0), Vector3(12, 0.1, 12), Color(0.2, 0.21, 0.2))  # the deck
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.05
	viewport.add_child(camera)
	camera.current = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(UiKit.ACCENT, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	marker = MeshInstance3D.new()
	marker.name = "Pointed"
	var bm := BoxMesh.new()
	bm.material = mat
	marker.mesh = bm
	marker.visible = false
	viewport.add_child(marker)
	_build_soldier()
	_fill_shelves()


## Your soldier in the middle of the room, in what you wear (the drop target for a dragged item).
func _build_soldier() -> void:
	soldier = Node3D.new()
	soldier.name = "You"
	var inv := Inventory.new()
	soldier.add_child(inv)
	var model := CharacterModel.new()
	model.variant = Soldier.COMPANY_VARIANT
	model.lod = false
	soldier.add_child(model)
	var rig := GearRig.new()
	rig.inventory = inv
	rig.model = model
	soldier.add_child(rig)
	viewport.add_child(soldier)
	inv.net_state = GameState.from_json(_my_gear().duplicate(true))
	soldier.set_meta(&"inventory", inv)


func _my_gear() -> Dictionary:
	var lvl := CompoundLevel.current(self)
	var body := lvl.players.get_node_or_null(NodePath(str(multiplayer.get_unique_id()))) as Soldier if lvl and lvl.players else null
	if body and body.inventory:
		return Roster.json_safe(body.inventory.net_state)
	return BaseHub.view.get("roster", {}).get("players", {}).get(BaseHub.player_key(multiplayer.get_unique_id()), {}).get("gear", {})


## Which ids each shelf shows: owned or for sale, owned first, then the cheapest.
static func shelf_items(group: String, stash: Array) -> Array:
	var have := Loadouts.units(stash, [])
	var out: Array = []
	for id: StringName in ItemDB.all_ids():
		var item := ItemDB.get_item(id)
		if Loadouts.group_of(item) != group:
			continue
		if int(have.get(String(id), 0)) > 0 or BaseEconomy.item_price(id) > 0:
			out.append(String(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(have.get(a, 0)) > 0
		var ob := int(have.get(b, 0)) > 0
		return BaseEconomy.item_price(StringName(a)) < BaseEconomy.item_price(StringName(b)) if oa == ob else oa)
	return out.slice(0, PER_SHELF)


## The shelf of `group`: where it stands and which way it faces (into the room).
static func shelf_transform(group: String) -> Transform3D:
	var i := Loadouts.GROUPS.find(group)
	var angle := TAU * float(i) / float(Loadouts.GROUPS.size())
	var at := Vector3(sin(angle), 0, cos(angle)) * SHELF_RING_M
	return Transform3D(Basis(Vector3.UP, angle + PI), at)


func _fill_shelves() -> void:
	for it: Dictionary in items:
		if is_instance_valid(it.node):
			it.node.queue_free()
	items.clear()
	var stash: Array = BaseHub.view.get("stash", [])
	_stash_hash = hash(stash)
	for group: String in Loadouts.GROUPS:
		var frame := shelf_transform(group)
		var unit := Node3D.new()
		unit.name = "Shelf_" + group
		unit.transform = frame
		viewport.add_child(unit)
		var steel := Color(0.3, 0.32, 0.3)
		for y: float in SHELF_LEVELS:
			_box(Vector3(0, y - 0.03, 0), Vector3(SHELF_W, 0.03, 0.5), steel, unit)
		for x: float in [-SHELF_W * 0.5, SHELF_W * 0.5]:
			_box(Vector3(x, 1.25, 0), Vector3(0.04, 2.5, 0.5), steel, unit)
		_box(Vector3(0, 1.25, -0.26), Vector3(SHELF_W, 2.5, 0.02), Color(0.24, 0.25, 0.23), unit)  # the back panel (local +Z faces the room)
		var sign := Label3D.new()
		sign.text = String(Loadouts.GROUP_NAMES[group]).to_upper()
		sign.font = UiKit.FONT_BOLD
		sign.font_size = 64
		sign.pixel_size = 0.0035
		sign.position = Vector3(0, 2.55, 0.05)
		sign.modulate = UiKit.ACCENT
		unit.add_child(sign)
		var level := 0
		var x := -SHELF_W * 0.5 + 0.08
		for id: String in shelf_items(group, stash):
			var item := ItemDB.get_item(StringName(id))
			var node := _item_node(item)
			var size := _node_size(node, item)
			var s := minf(1.0, MAX_ITEM_M / maxf(0.01, maxf(size.x, maxf(size.y, size.z))))
			var w := size.x * s
			if x + w > SHELF_W * 0.5 - 0.06:
				level += 1
				x = -SHELF_W * 0.5 + 0.08
			if level >= SHELF_LEVELS.size():
				node.free()
				break
			node.scale = Vector3.ONE * s
			node.position = Vector3(x + w * 0.5, SHELF_LEVELS[level] + size.y * s * 0.5, 0.0)
			unit.add_child(node)
			x += w + ITEM_GAP
			items.append({"id": id, "node": node, "size": size * s})


func _item_node(item: ItemData) -> Node3D:
	if item.type == "armor" and item.slot == &"helmet" or item.type == "plate":
		var holder := Node3D.new()
		var piece := VoxelArmor.new()
		holder.add_child(piece)
		piece.setup(item, &"", null, 1)
		piece.position = -VoxelArmor.center_offset(item)
		return holder
	return ItemArt.ground_node(item)


static func _node_size(_node: Node3D, item: ItemData) -> Vector3:
	if item.type == "armor" and item.slot == &"helmet" or item.type == "plate":
		return VoxelArmor.size_m(item)
	return ItemArt.ground_size(item)


func _box(at: Vector3, size: Vector3, colour: Color, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	bm.material = m
	mi.mesh = bm
	mi.position = at
	(parent if parent else viewport).add_child(mi)
	return mi


# --- Looking round ----------------------------------------------------------------------------

## Turns to face the shelf of `group`.
func walk_to(group: String) -> void:
	var i := Loadouts.GROUPS.find(group)
	if i < 0:
		return
	_want_yaw = TAU * float(i) / float(Loadouts.GROUPS.size())
	_say("%s shelf" % Loadouts.GROUP_NAMES[group])


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	yaw = lerp_angle(yaw, _want_yaw, minf(1.0, delta * 6.0))
	if camera:
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := dir.cross(Vector3.UP).normalized()
		camera.position = dir * (SHELF_RING_M - _distance) + Vector3(0, 1.45, 0)
		camera.look_at(dir * SHELF_RING_M + Vector3(0, 1.2, 0), Vector3.UP)
		if soldier:  # you stand to the right of the view, clear of the shelf: the drop target
			soldier.position = dir * (SHELF_RING_M - _distance + SOLDIER_AHEAD_M) + right * SOLDIER_RIGHT_M
			soldier.rotation.y = yaw + PI * 0.8
	if marker and marker.visible:
		_place_marker(picked if hovered == "" else hovered)


func _room_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.25, ZOOM_MIN, SHELF_RING_M + 1.5)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.25, ZOOM_MIN, SHELF_RING_M + 1.5)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_at = mb.position
				_drag_item = item_at(mb.position)
			else:
				if _pressed and not _dragging:
					var id := item_at(mb.position)
					if id != "":
						point_at(id)
				elif _dragging and _drag_item != "" and over_soldier(mb.position):
					fit_on_me(_drag_item)
				_pressed = false
				_dragging = false
				_drag_item = ""
				view_box.mouse_default_cursor_shape = Control.CURSOR_ARROW
		view_box.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and mm.position.distance_to(_press_at) > CLICK_PX:
			_dragging = true
		if _dragging and _drag_item == "":
			_want_yaw = wrapf(_want_yaw - mm.relative.x * TURN_PER_PX, -PI, PI)
			yaw = _want_yaw
		elif _dragging:
			view_box.mouse_default_cursor_shape = Control.CURSOR_DRAG
			_say("Drop %s on your soldier to fit it" % _name(_drag_item) if over_soldier(mm.position) else "Dragging %s: drop it on your soldier in the middle of the room" % _name(_drag_item))
		else:
			var h := item_at(mm.position)
			if h != hovered:
				hovered = h
				_show_info()


## The item drawn at `pos` (the room view's px), nearest the camera, or "".
func item_at(pos: Vector2) -> String:
	if camera == null:
		return ""
	var best := ""
	var best_d := INF
	var scale_by := view_box.size / Vector2(viewport.size) if viewport.size.x > 0 else Vector2.ONE
	for it: Dictionary in items:
		var node: Node3D = it.node
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var c := node.global_position
		if camera.is_position_behind(c):
			continue
		var r := Rect2(camera.unproject_position(c) * scale_by, Vector2.ZERO)
		var half: Vector3 = it.size * 0.5
		for corner: Vector3 in [Vector3(-1, -1, -1), Vector3(1, 1, 1), Vector3(-1, 1, -1), Vector3(1, -1, 1)]:
			var p := c + node.global_transform.basis.orthonormalized() * (half * corner)
			if not camera.is_position_behind(p):
				r = r.expand(camera.unproject_position(p) * scale_by)
		if r.grow(2.0).has_point(pos):
			var d := camera.global_position.distance_to(c)
			if d < best_d:
				best_d = d
				best = String(it.id)
	return best


## Whether `pos` (the room view's px) is on your soldier.
func over_soldier(pos: Vector2) -> bool:
	if camera == null or soldier == null:
		return false
	var scale_by := view_box.size / Vector2(viewport.size) if viewport.size.x > 0 else Vector2.ONE
	var r := Rect2(camera.unproject_position(soldier.global_position) * scale_by, Vector2.ZERO)
	for y: float in [0.0, 1.85]:
		for x: float in [-0.35, 0.35]:
			var p := soldier.global_position + Vector3(x, y, 0)
			if not camera.is_position_behind(p):
				r = r.expand(camera.unproject_position(p) * scale_by)
	return r.has_point(pos)


## Points at `id`: lit on its shelf, its panel shown.
func point_at(id: String) -> void:
	picked = id
	hovered = ""
	_show_info()


func find_item(query: String) -> void:
	if query == "":
		return
	for it: Dictionary in items:
		if UiKit.matches(_name(String(it.id)), query):
			walk_to(Loadouts.group_of(ItemDB.get_item(StringName(String(it.id)))))
			point_at(String(it.id))
			return
	var ids := ItemDB.all_ids().filter(func(i: StringName) -> bool: return UiKit.matches(ItemDB.get_item(i).name, query))
	if not ids.is_empty():
		point_at(String(ids[0]))  # not on a shelf (past PER_SHELF): the panel still shows it
		_say("%s isn't on the shelves, but here it is" % _name(String(ids[0])))
	else:
		_say("Nothing called \"%s\"" % query)


func _place_marker(id: String) -> void:
	for it: Dictionary in items:
		if String(it.id) == id and is_instance_valid(it.node):
			marker.global_transform = Transform3D((it.node as Node3D).global_transform.basis.orthonormalized(), (it.node as Node3D).global_position)
			(marker.mesh as BoxMesh).size = (it.size as Vector3) + Vector3.ONE * 0.04
			marker.visible = true
			return
	marker.visible = false


# --- The panel --------------------------------------------------------------------------------

func _show_info() -> void:
	if info_box == null:
		return
	for c: Node in info_box.get_children():
		c.queue_free()
	var id := hovered if hovered != "" else picked
	marker.visible = id != ""
	if id != "":
		_place_marker(id)
	if id == "":
		info_box.add_child(UiKit.heading("Point at an item"))
		info_box.add_child(UiKit.hint("Its price, what it does and how many the company has show here."))
		info_box.add_child(UiKit.key_hints([["B", "Buy"], ["F", "Fit on me"], ["Drag", "Onto your soldier"]]))
		return
	var item := ItemDB.get_item(StringName(id))
	var have := int(Loadouts.units(BaseHub.view.get("stash", []), []).get(id, 0))
	var price := BaseEconomy.item_price(StringName(id))
	var funds := int(BaseHub.view.get("funds", 0))
	var title := UiKit.heading(item.name)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(title)
	var seller := Quartermaster.seller_text(StringName(id))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", UiKit.SPACE_M)
	info_box.add_child(grid)
	var rows := [
		["Price", ("$%d" % price if price > 0 else "not for sale") + ((" (%s)" % seller) if seller != "" else "")],
		["Owned", "%d in the stash" % have if have > 0 else "none: not owned"],
		["Cash", "$%d" % funds],
		["Kind", "%s, %s" % [Loadouts.GROUP_NAMES[Loadouts.group_of(item)], String(item.stats.get("rarity", "common"))]],
		["Weight", "%.2f kg, %.1f L" % [item.mass_kg, item.volume_l]],
	]
	var rating := String(ArmorRules.rating(item)) if item.type in ["armor", "plate"] else ""
	if rating != "":
		rows.append(["Protection", "NIJ %s" % rating])
	if item.type == "weapon":
		rows.append(["Fire", "%d rpm, %s" % [int(item.stats.get("rpm", 0)), ", ".join(PackedStringArray(item.stats.get("fire_modes", ["semi"])))]])
		var mag := String(item.stats.get("ammo", ""))
		if mag != "" and ItemDB.has_item(StringName(mag)):
			rows.append(["Ammo", ItemDB.get_item(StringName(mag)).name])
	if float(item.capacity_l) > 0.0:
		rows.append(["Holds", "%.0f L" % item.capacity_l])
	for r: Array in rows:
		var k := UiKit.cell(String(r[0]))
		k.add_theme_color_override(&"font_color", UiKit.TEXT_DIM)
		grid.add_child(k)
		var v := UiKit.cell(String(r[1]))
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(v)
	var desc := UiKit.text(item.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(desc)
	for u: Variant in item.uses:
		var line := UiKit.hint("- " + String(u))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(line)
	var buttons: Array = []
	var buy_button := UiKit.accent_button("Buy: $%d [B]" % price, buy.bind(id, 1), "Buy one into the company stash (B)")
	buy_button.name = "Buy"
	buy_button.disabled = price <= 0 or funds < price
	if price > 0 and funds < price:
		buy_button.tooltip_text = "Not enough cash: $%d of $%d" % [funds, price]
	buttons.append(buy_button)
	if item.type in ["ammo", "medical"] or "throwable" in item.tags:
		var five := UiKit.button("Buy 5: $%d" % (price * 5), buy.bind(id, 5), "Buy five")
		five.name = "Buy5"
		five.disabled = price <= 0 or funds < price * 5
		buttons.append(five)
	var fit := UiKit.button("Fit on me [F]", fit_on_me.bind(id), "Open the 3D loadout editor with this on your soldier (F), or drag it onto him")
	fit.name = "Fit"
	buttons.append(fit)
	info_box.add_child(UiKit.button_row(buttons))


func buy(id: String, count: int) -> void:
	BaseHub.request("buy", [id, count])
	_say("Buying %d %s for $%d..." % [count, _name(id), BaseEconomy.item_price(StringName(id)) * count])


## Opens the 3D loadout editor with `id` fitted on your soldier as a draft; the armory closes
## (the editor's Close brings you back to the base screen).
func fit_on_me(id: String) -> void:
	var editor := BaseHub.open_loadout_3d(id)
	if editor:
		close()


func _on_view() -> void:
	if hash(BaseHub.view.get("stash", [])) != _stash_hash:
		_fill_shelves()
	if soldier:
		(soldier.get_meta(&"inventory") as Inventory).net_state = GameState.from_json(_my_gear().duplicate(true))
	_show_info()


func _on_note(text: String) -> void:
	if text != "":
		_say(text)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	if not event is InputEventKey or not event.pressed or event.echo or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var k := event as InputEventKey
	var id := hovered if hovered != "" else picked
	if k.keycode == KEY_B and id != "":
		buy(id, 1)
	elif k.keycode == KEY_F and id != "":
		fit_on_me(id)
	elif k.keycode == KEY_A or k.keycode == KEY_LEFT:
		_want_yaw = wrapf(_want_yaw + 0.25, -PI, PI)
	elif k.keycode == KEY_D or k.keycode == KEY_RIGHT:
		_want_yaw = wrapf(_want_yaw - 0.25, -PI, PI)
	elif k.keycode >= KEY_1 and k.keycode <= KEY_9 and k.keycode - KEY_1 < Loadouts.GROUPS.size():
		walk_to(Loadouts.GROUPS[k.keycode - KEY_1])
	else:
		return
	get_viewport().set_input_as_handled()


func _say(text: String) -> void:
	if status:
		status.text = text


static func _name(id: String) -> String:
	var item := ItemDB.get_item(StringName(id)) if id != "" and ItemDB.has_item(StringName(id)) else null
	return item.name if item else id
