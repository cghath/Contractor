class_name Hud
extends CanvasLayer
## Minimal local HUD: crosshair, interact prompt, messages, and the Tab inventory screen.
##
## HUD zones (Captain, 2026-10-14: "all the UIs need a pass"; docs/ui_audit.md item 4, P1-9 to
## P1-11, P2-22): each part of the screen holds one kind of thing, so nothing stacks on anything
## else at any window size or UI scale (tests/ui_test.gd hosts a level and checks):
##   top-right: the objectives panel, the objective hint under it (and the dev hot-zone readout)
##   left: the command menu (centre-left) over the squad list (bottom-left), one column
##   bottom-right: the weapon (AmmoReadout)
##   bottom-centre: the radio feed and subtitles over the vehicle readout (in parts)
##   centre: crosshair, prompt, and the downed or killed text; top-centre: flash messages
## Every HUD line uses the theme's one outlined style (HudLabel and its variations, UiKit.hud_label).

## The gap kept from the window's edge.
const MARGIN := 16.0
## The top-right zone's group (HotZoneDebug, on its own layer, sits under it).
const TOP_RIGHT_GROUP := &"hud_top_right"
## Widths (logical px) of the centre lines; each is cut to the window less UiKit.EDGE a side.
const PROMPT_WIDTH := 640.0
const CENTRE_WIDTH := 760.0
## Below this logical window height (1280x720 at a 1.5 Menu and HUD size and up) the centre
## column's lines (prompt, the downed text's detail, the radio and the vehicle readout) drop to
## the small HUD size, as the squad list does under an open command menu: at the HUD's 20 px
## (ui-modern) they didn't fit between the middle and the bottom.
const COMPACT_HEIGHT := 600.0

## Set by the owning Soldier before the HUD enters the tree.
var player: Soldier
var inventory_screen: InventoryScreen
var loot_window: LootWindow
var command_menu: CommandMenu
var voice_order: VoiceOrder
## The map (M) and briefing (MapScreen).
var map_screen: MapScreen
## The "what to do now" line and the objective markers (ObjectiveHelper).
var objective_helper: ObjectiveHelper
## The magazines and their rough fill (AmmoReadout).
var ammo_readout: AmmoReadout
var armor_readout: ArmorReadout
## The bearing strip across the top of the screen (Compass).
var compass: Compass
## The zones (see the top): the right column, the left column, and the bottom-centre stack.
var zone_top_right: VBoxContainer
var zone_left: VBoxContainer
var zone_bottom_centre: VBoxContainer
var _crosshair: Label
var _prompt: Label
var _status: Label
## The downed or killed title (HudAlertLabel) and the lines under it, which wrap.
var _downed_box: VBoxContainer
var _downed: Label
var _downed_detail: Label
var _message: Label
var _subtitles: Label
## The vehicle readout: one label per part (Vehicle.readout_parts), flowing onto more lines.
var _vehicle: HFlowContainer
var _vehicle_parts: Array = []
var _vehicle_left := 0.0  # seconds until it hides unless its vehicle shows it again
## The squad list's lines (update_status); _fit_status shows as many as the left column has room for.
var _status_lines := PackedStringArray()
## The centre column's lines: [control, y from the middle (or the top), grow direction], kept
## snug to their text every frame (_snug), as a wrapping label never shrinks back on its own.
var _centred: Array = []
## The left column's height (logical px), from _layout.
var _left_height := 0.0
## Whether the window is short enough for the small centre lines (COMPACT_HEIGHT), from _layout.
var compact := false
## The HUD layout setting (HudLayout) as last applied: its change counter.
var _layout_changes := -1
var _message_time := 0.0
var _white: ColorRect
var _white_left := 0.0  # seconds of whiteout remaining
## Blood loss, concussion and unconsciousness drawn over the view (Vitals.vision).
var _vision: ColorRect
## The wound silhouette (top left).
var _bleed: Control
var _vision_material: ShaderMaterial


## Fades colour, greys and closes in the edges, blurs and blacks out the screen.
const VISION_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float fade = 0.0;    // 15-30% blood lost: colour fades slightly
uniform float tunnel = 0.0;  // 30-40%: grey edges close in
uniform float blur = 0.0;    // concussion
uniform float black = 0.0;   // unconscious
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, blur * 2.5).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), 0.35 * fade + 0.45 * tunnel);
	float r = mix(0.75, 0.35, tunnel);
	float edge = 1.0 - smoothstep(r - 0.25, r, distance(UV, vec2(0.5)));
	c = mix(vec3(grey * 0.35), c, mix(1.0, edge, tunnel));
	COLOR = vec4(mix(c, vec3(0.0), black), 1.0);
}
"""


func _ready() -> void:
	_vision = ColorRect.new()
	_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vision_material = ShaderMaterial.new()
	_vision_material.shader = Shader.new()
	_vision_material.shader.code = VISION_SHADER
	_vision.material = _vision_material
	_vision.visible = false
	add_child(_vision)
	_vision.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair = _add(UiKit.hud_label("+")) as Label
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_box = VBoxContainer.new()
	_downed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	_add(_downed_box)
	_downed = _wrapping(UiKit.hud_label("", &"HudAlertLabel"))
	_downed_box.add_child(_downed)
	_downed_detail = _wrapping(UiKit.hud_label())
	_downed_box.add_child(_downed_detail)
	_prompt = _add(_wrapping(UiKit.hud_label())) as Label
	inventory_screen = InventoryScreen.new(player)
	inventory_screen.visible = false
	add_child(inventory_screen)
	loot_window = LootWindow.new(player)
	add_child(loot_window)
	# Left column: the command menu in the middle of the room left above the squad list.
	zone_left = _zone("LeftZone")
	zone_left.add_child(_spacer())
	command_menu = CommandMenu.new(player)
	zone_left.add_child(command_menu)
	zone_left.add_child(_spacer())
	voice_order = VoiceOrder.new(command_menu)
	add_child(voice_order)
	_status = UiKit.hud_label()
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long line cuts with "...", never runs under the radio
	zone_left.add_child(_status)
	# Bottom-centre: the radio feed and subtitles over the vehicle readout.
	zone_bottom_centre = _zone("BottomCentreZone")
	zone_bottom_centre.alignment = BoxContainer.ALIGNMENT_END
	_subtitles = _wrapping(Callouts.Subtitles.new())  # squadmates' callouts
	zone_bottom_centre.add_child(_subtitles)
	_vehicle = HFlowContainer.new()
	_vehicle.name = "VehicleReadout"
	_vehicle.alignment = FlowContainer.ALIGNMENT_CENTER
	_vehicle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vehicle.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
	_vehicle.add_theme_constant_override(&"v_separation", UiKit.SPACE_XS)
	_vehicle.visible = false
	zone_bottom_centre.add_child(_vehicle)
	# Top-right: the objectives, then the hint under them (ObjectiveHelper puts it here).
	zone_top_right = _zone("TopRightZone")
	zone_top_right.add_to_group(TOP_RIGHT_GROUP)
	zone_top_right.add_child(ObjectivesPanel.new())  # the deployment's objectives (wave 4, Contracts)
	zone_top_right.add_child(HcStrip.new())  # high command: the squads' line and the latest request (high_command.md 10)
	objective_helper = ObjectiveHelper.new(player)  # what to do now, and small markers on its target
	add_child(objective_helper)
	ammo_readout = AmmoReadout.new(player)  # mags and roughly how full, not a count
	add_child(ammo_readout)
	armor_readout = ArmorReadout.new(player)  # plates and helmet: what's left of each
	add_child(armor_readout)
	compass = Compass.new(player)  # the bearing strip, top-centre
	add_child(compass)
	_message = _add(_wrapping(UiKit.hud_label())) as Label
	# The map (M) and the briefing, over everything else (W13).
	_bleed = BleedSilhouette.new(player)
	add_child(_bleed)
	map_screen = MapScreen.new(player)
	add_child(map_screen)
	move_child(_message, -1)  # messages stay readable over the map
	get_viewport().size_changed.connect(_layout)
	_layout()


## The HUD from any node under it (or null).
static func of(node: Node) -> Hud:
	while node != null and not node is Hud:
		node = node.get_parent()
	return node as Hud


## Places the zones and the centre lines for the window's visible size (logical px, so the
## Menu and HUD size setting counts): runs at the start and on every resize.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	_layout_changes = HudLayout.changes()
	var s_squad := HudLayout.scale_of("squad")
	var s_right := HudLayout.scale_of("objectives")
	var s_weapon := HudLayout.scale_of("weapon")
	var s_wounds := HudLayout.scale_of("wounds")
	var side := clampf(view.x * 0.28, 220.0, 400.0)
	var right := clampf(view.x * 0.3, 240.0, ObjectivesPanel.WIDTH)
	var left_top := MARGIN + MedicalMenu.FIGURE_SIZE.y * BleedSilhouette.SCALE * s_wounds + UiKit.SPACE_S  # under the bleed silhouette
	# A part made bigger (HudLayout) is laid out in its zone's room over its scale, then scaled
	# up from its corner: it fills the same part of the screen, with bigger contents.
	_left_height = (view.y - left_top - MARGIN) / s_squad
	_set_rect(zone_left, Vector4(0, 0, 0, 0), Vector4(MARGIN, left_top, MARGIN + side / s_squad, left_top + _left_height))
	zone_left.scale = Vector2.ONE * s_squad
	# The command menu's path wraps inside the left column, so the open menu stays in it.
	command_menu.title_width = minf(CommandMenu.TITLE_W, side / s_squad - command_menu.get_theme_stylebox(&"panel").get_minimum_size().x)
	_set_rect(zone_top_right, Vector4(1, 0, 1, 0), Vector4(-MARGIN - right, MARGIN, -MARGIN - right + right / s_right, MARGIN))
	zone_top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zone_top_right.scale = Vector2.ONE * s_right
	# Top-centre: the bearing strip, clear of the squad list and objectives on either side.
	var compass_w := clampf(view.x * 0.22, 240.0, 420.0)
	_set_rect(compass, Vector4(0.5, 0, 0.5, 0), Vector4(-compass_w * 0.5, MARGIN, compass_w * 0.5, MARGIN + Compass.HEIGHT))
	compass.pivot_offset = Vector2(compass_w * 0.5, 0.0)
	compass.scale = Vector2.ONE * HudLayout.scale_of("compass")
	# The weapon and armour readouts grow from the bottom-right corner together.
	ammo_readout.pivot_offset = Vector2(AmmoReadout.WIDTH, AmmoReadout.HEIGHT)
	ammo_readout.scale = Vector2.ONE * s_weapon
	armor_readout.pivot_offset = Vector2(ArmorReadout.WIDTH, ArmorReadout.ROW * ArmorReadout.MAX_ROWS + 8.0 + AmmoReadout.HEIGHT)
	armor_readout.scale = Vector2.ONE * s_weapon
	_bleed.scale = Vector2.ONE * s_wounds
	for pair: Array in [[zone_top_right, "objectives"], [compass, "compass"], [zone_left, "squad"], [zone_bottom_centre, "radio"],
			[ammo_readout, "weapon"], [armor_readout, "weapon"], [_bleed, "wounds"], [objective_helper, "markers"]]:
		(pair[0] as CanvasItem).modulate.a = HudLayout.opacity_of(pair[1])
	var was_compact := compact
	compact = view.y < COMPACT_HEIGHT and not _headless_size()
	for label: Label in [_prompt, _downed_detail, _subtitles]:
		label.theme_type_variation = &"HudSmallLabel" if compact else &"HudLabel"
	if compact != was_compact:
		_subtitles._shown = ""  # refit again in the new size
	# Three columns: left, centre and right. The centre one (prompt, downed text, messages,
	# radio, vehicle) is what the side columns leave, so nothing in it runs under them.
	var centre := minf(CENTRE_WIDTH, view.x - 2.0 * (maxf(maxf(side, right), AmmoReadout.WIDTH * s_weapon) + MARGIN + UiKit.SPACE_M))
	var s_radio := HudLayout.scale_of("radio")
	_set_rect(zone_bottom_centre, Vector4(0.5, 1, 0.5, 1), Vector4(-centre * 0.5 / s_radio, -MARGIN, centre * 0.5 / s_radio, -MARGIN))
	zone_bottom_centre.scale = Vector2.ONE * s_radio
	zone_bottom_centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	zone_bottom_centre.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Top to bottom: [control, width, y (from the top for the message, else from the middle), grow].
	_centred = [[_message, centre, 60.0, Control.GROW_DIRECTION_END], [_downed_box, centre, -60.0, Control.GROW_DIRECTION_BOTH],
		[_crosshair, 0.0, 0.0, Control.GROW_DIRECTION_BOTH], [_prompt, minf(PROMPT_WIDTH, centre), 40.0, Control.GROW_DIRECTION_END]]
	for c: Array in _centred:
		_centre(c[0], c[1], c[2], c[3])
	_message.anchor_top = 0.0
	_message.anchor_bottom = 0.0
	_snug()


## Fits each centre line's height to its text (a wrapping label grows as its text gets longer
## but never shrinks back by itself), and stacks them down the centre column without running
## into each other: the flash message from the top, the downed or killed text over the middle
## (pushed under the message), the crosshair in the middle, the prompt under it (or under the
## downed text).
func _snug() -> void:
	var mid := get_viewport().get_visible_rect().size.y * 0.5
	var below := 0.0  # the lowest edge so far, from the top
	for c: Array in _centred:
		var control: Control = c[0]
		var h := control.get_combined_minimum_size().y
		var y: float = c[2]
		var top := y
		if control != _message:
			top = mid + (y - h * 0.5 if c[3] == Control.GROW_DIRECTION_BOTH else y)
			if control != _crosshair:
				top = maxf(top, below)
		var label := control as Label
		if control != _crosshair and control.visible and h > 0.0 and (label == null or label.text != ""):
			below = top + h + UiKit.SPACE_S
		var origin := 0.0 if control == _message else mid
		control.offset_top = top - origin
		control.offset_bottom = top - origin + h


## Whether the window is far smaller than any the HUD is laid out for (GameSettings.MIN_UI_SIZE):
## a headless test's 64x64 root. Nothing is cut to fit then, so tests still read every line.
func _headless_size() -> bool:
	var view := get_viewport().get_visible_rect().size
	return view.x < GameSettings.MIN_UI_SIZE.x * 0.75 or view.y < GameSettings.MIN_UI_SIZE.y * 0.75


## The squad list in the room the left column has under the command menu (P1-10: at 720 px tall
## the list and the menu ran into each other): what doesn't fit is cut, and says so.
## Review of ui/hud-pass, 2026-10-14: never silently, and never the units being picked. When the
## menu is open and short of room the list drops to the small HUD size; what is kept is the
## selected members first, then what you carry and spawn protection, then the header, then the
## rest (shown in their usual order, with "+n more"); with no line to spare at all the menu's
## title says how many squad lines are hidden. Hidden under the inventory and map, as the
## weapon and objective hint are (it drew over the inventory's bottom-left).
func _fit_status() -> void:
	var covered := is_inventory_open() or (map_screen != null and map_screen.visible)
	var variation := &"HudLabel"
	var room := 1.0e9 if _headless_size() else _left_height - UiKit.SPACE_S * 3.0 - (command_menu.get_combined_minimum_size().y if command_menu.visible else 0.0)
	var fit := _status_fit(room, variation)
	if _status_lines.size() > fit and command_menu.visible:
		variation = &"HudSmallLabel"
		fit = _status_fit(room, variation)
	var lines := status_cut(_status_lines, fit)
	var hidden := _status_lines.size() if lines.is_empty() else 0
	command_menu.note = "+%d squad lines below" % hidden if hidden > 0 and not covered else ""
	var text := "
".join(lines)
	if _status.theme_type_variation != variation:
		_status.theme_type_variation = variation
	if _status.text != text:
		_status.text = text
	_status.visible = text != "" and not covered


## How many lines of the HUD label style `variation` fit in `room` px.
func _status_fit(room: float, variation: StringName) -> int:
	var spacing := float(UiKit.THEME.get_constant(&"line_spacing", variation)) if UiKit.THEME.has_constant(&"line_spacing", variation) 		else float(_status.get_theme_constant(&"line_spacing"))
	var font := UiKit.THEME.get_font(&"font", variation) if UiKit.THEME.has_font(&"font", variation) else _status.get_theme_font(&"font")
	var size := UiKit.THEME.get_font_size(&"font_size", variation) if UiKit.THEME.has_font_size(&"font_size", variation) else _status.get_theme_font_size(&"font_size")
	var line := font.get_height(size) + spacing
	return maxi(floori((room + spacing) / maxf(line, 1.0)), 0)


## The squad list's `lines` cut to `fit` lines: all of them if they fit; else the most needed
## (selected members, marked ">", then what you carry and spawn protection, then the SQUAD
## header, then the rest) in their usual order, with a last "+n more" line. Empty if none fit.
static func status_cut(lines: PackedStringArray, fit: int) -> PackedStringArray:
	if lines.size() <= fit:
		return lines
	if fit <= 0:
		return PackedStringArray()
	var order: Array[int] = []
	order.assign(range(lines.size()))
	var rank := func(i: int) -> int:
		var l := lines[i]
		if l.begins_with(">"):
			return 0
		if l.begins_with("Carrying") or l.begins_with("Spawn protection"):
			return 1
		return 2 if l.begins_with("SQUAD") else 3
	order.sort_custom(func(a: int, b: int) -> bool: return rank.call(a) < rank.call(b) or (rank.call(a) == rank.call(b) and a < b))
	var keep: Array[int] = order.slice(0, fit - 1)
	keep.sort()
	var out := PackedStringArray()
	for i in keep:
		out.append(lines[i])
	out.append("+%d more" % (lines.size() - keep.size()))
	return out


## The bottom-centre zone in the room under the centre lines (prompt, downed text): the
## vehicle readout first (on a short window its key hints go, then its plainer parts; the
## vehicle, the seat and any warning stay), then the newest radio lines that still fit.
func _fit_bottom_centre() -> void:
	var view := get_viewport().get_visible_rect().size
	var top := view.y * 0.5 + 40.0
	for c: Control in [_prompt, _downed_box]:
		if c.visible and c.get_combined_minimum_size().y > 0.0:
			top = maxf(top, c.get_global_rect().end.y)
	var room := 1.0e9 if _headless_size() else (view.y - MARGIN - top - UiKit.SPACE_M) / zone_bottom_centre.scale.y
	# Scaled from its bottom middle (HudLayout), whatever its height now.
	zone_bottom_centre.pivot_offset = Vector2(zone_bottom_centre.size.x * 0.5, zone_bottom_centre.size.y)
	_vehicle.visible = _vehicle_left > 0.0 and not _vehicle_parts.is_empty()
	if _vehicle.visible:
		room -= _fit_vehicle(room, zone_bottom_centre.size.x) + UiKit.SPACE_S
	_subtitles.room = room
	_subtitles.refit(zone_bottom_centre.size.x)


## Shows the vehicle's parts, as many as fit `room` px tall in rows `width` wide; returns the
## height they take.
func _fit_vehicle(room: float, width: float) -> float:
	while _vehicle.get_child_count() < _vehicle_parts.size():
		_vehicle.add_child(UiKit.hud_label())
	var keys: Array = []  # what goes first when there's no room: key hints, then plain parts
	var plain: Array = []
	for i in _vehicle.get_child_count():
		var label := _vehicle.get_child(i) as Label
		label.visible = i < _vehicle_parts.size()
		if label.visible:
			var part: Dictionary = _vehicle_parts[i]
			label.text = String(part.text)
			var style := StringName(part.get("style", &""))
			if style == &"warn":
				label.theme_type_variation = &"HudSmallWarnLabel" if compact else &"HudWarnLabel"
			else:
				label.theme_type_variation = &"HudSmallLabel" if style == &"key" or compact else &"HudLabel"
			if style == &"key":
				keys.append(i)
			elif style != &"warn" and i > 0:
				plain.push_front(i)  # the last first
	var order: Array = keys + plain
	var height := _flow_height(width)
	while height > room and not order.is_empty():
		(_vehicle.get_child(order.pop_front()) as Label).visible = false
		height = _flow_height(width)
	return height


## How tall the vehicle readout's shown parts are when they flow in rows `width` wide.
func _flow_height(width: float) -> float:
	var sep := float(_vehicle.get_theme_constant(&"h_separation"))
	var row_h := 0.0
	var rows := 0
	var x := 0.0
	for label: Label in _vehicle.get_children():
		if not label.visible:
			continue
		var m := label.get_combined_minimum_size()
		row_h = maxf(row_h, m.y)
		if rows == 0 or x + sep + m.x > width:
			rows += 1
			x = m.x
		else:
			x += sep + m.x
	return rows * row_h + maxi(rows - 1, 0) * float(_vehicle.get_theme_constant(&"v_separation"))


static func _set_rect(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


## `c` centred across the window, `width` wide (0: as wide as its text), `y` from the middle,
## growing both ways sideways (a longer line stays centred, P1-11) and down (or both).
static func _centre(c: Control, width: float, y: float, grow: Control.GrowDirection) -> void:
	_set_rect(c, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-width * 0.5, y, width * 0.5, y))
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = grow


func _add(c: Control) -> Control:
	add_child(c)
	return c


static func _wrapping(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _zone(zone_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = zone_name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	add_child(box)
	return box


static func _spacer() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## The vehicle readout for the seat the local player sits in (Vehicle._local_controls, every
## frame): `parts` are {"text", "style": &"" | &"warn" | &"key"} (Vehicle.readout_parts), one
## label each, flowing onto another line instead of one run-on line (P1-9). It hides itself
## when its vehicle stops showing it.
func show_vehicle(parts: Array) -> void:
	_vehicle_left = 0.5
	_vehicle_parts = parts
	_fit_bottom_centre()


func hide_vehicle() -> void:
	_vehicle_left = 0.0
	_vehicle_parts = []
	_vehicle.visible = false


## The vehicle readout as shown ("" when hidden; tests read it).
func vehicle_text() -> String:
	if not _vehicle.visible:
		return ""
	var parts := PackedStringArray()
	for label: Label in _vehicle.get_children():
		if label.visible:
			parts.append(label.text)
	return "  |  ".join(parts)


## A small body silhouette in the top-left corner while the local player has an untreated bleed,
## an unsplinted fracture or a tourniquet on: those parts coloured, hidden when nothing to show.
class BleedSilhouette extends Control:
	## ui-modern (2026-10-20): 0.22 made it about 48 x 88 px, hard to read at a glance.
	const SCALE := 0.3
	var player: Soldier
	var parts: Array[StringName] = []

	func _init(p: Soldier = null) -> void:
		player = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2(16, 16)
		size = MedicalMenu.FIGURE_SIZE * SCALE
		visible = false

	func _process(_delta: float) -> void:
		var was := parts
		parts = MedicalMenu.hud_parts(player.vitals) if player != null and player.vitals.is_up() else ([] as Array[StringName])
		visible = not parts.is_empty()
		if parts != was:
			queue_redraw()

	func _draw() -> void:
		if player != null:
			MedicalMenu.draw_diagram(self, player.vitals, Vector2.ZERO, SCALE, &"", parts)


func _process(delta: float) -> void:
	if HudLayout.changes() != _layout_changes:
		_layout()  # the HUD layout setting changed
	_message_time -= delta
	_message.visible = _message_time > 0.0
	_vehicle_left -= delta
	_fit_status()
	_snug()
	_fit_bottom_centre()
	_white_left = maxf(_white_left - delta, 0.0)
	_white.color.a = clampf(_white_left / 1.5, 0.0, 1.0)
	_update_vision()


## Draws what blood loss, concussion and being out do to the local player's view.
func _update_vision() -> void:
	if player == null:
		return
	var vision := player.vitals.vision()
	var any := false
	for key: String in vision:
		_vision_material.set_shader_parameter(key, vision[key])
		any = any or vision[key] > 0.0
	_vision.visible = any


## Flashbang: `amount` 0..1 sets how long the screen stays white (up to about 5 s).
func whiteout(amount: float) -> void:
	_white_left = maxf(_white_left, 0.5 + 4.5 * amount)


func set_prompt(text: String) -> void:
	_prompt.text = text


## The inspect panel (ItemInfo) for item `id` over the middle of the view: a ground item's
## description, uses and numbers (PlayerInput.toggle_inspect). Mouse stays captured.
func show_item_info(id: StringName) -> void:
	var box := ItemInfo.show_inspect(self, id, "%s again or look away to close" % OS.get_keycode_string(GameSettings.key_for(&"inspect")))
	box.position.x += 260.0  # right of the crosshair, clear of the prompt


func hide_item_info() -> void:
	ItemInfo.hide_inspect(self)


## The item the inspect panel shows, or &"".
func inspected() -> StringName:
	return ItemInfo.inspected(self)


func flash(text: String) -> void:
	_message.text = text
	_message_time = 2.5


func is_inventory_open() -> bool:
	return inventory_screen.visible or loot_window.is_open()


## Opens the loot window on a body or a vehicle's hold: asks the host to start the search.
func open_loot(target: Node) -> void:
	if target == null or loot_window.is_open():
		return
	inventory_screen.visible = false
	loot_window.open(target)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.rpc_id(1, &"_server_loot_open", target.get_path())


func release_mouse_if_clear() -> void:
	if not is_inventory_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_detail() -> void:
	if loot_window.is_open():
		loot_window.close()
		release_mouse_if_clear()
		return
	inventory_screen.visible = not inventory_screen.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_screen.visible else Input.MOUSE_MODE_CAPTURED


## Minimal HUD, as in Arma with ACE: no health bar, round counter or load readout. Weight,
## litres, exact rounds loaded and armor damage are on the inventory screen (Tab); the HUD
## only says roughly how full the magazine is and how many are left (AmmoReadout).
func update_status(player: Soldier) -> void:
	# What you carry and spawn protection first: if the column is short, the squad's last lines go.
	var lines := PackedStringArray()
	if player.inventory.hands != &"":
		lines.append("Carrying %s (Alt+G to drop)" % ItemDB.get_item(player.inventory.hands).name)
	if player.respawn_state == Soldier.RESPAWN_PROTECTED:
		lines.append("Spawn protection%s - firing ends it" % (" %d s" % ceili(player.protect_eta - Soldier._now()) if player.protect_eta > Soldier._now() else ""))
	var squad := _squad_lines(player).strip_edges(false, true)
	if squad != "":
		lines.append_array(squad.split("\n"))
	_status_lines = lines
	_crosshair.visible = not player.is_aiming and player.vitals.is_up() and player.respawn_state != Soldier.RESPAWN_WAITING
	var held: float = player.player_input.give_up_held if player.player_input else 0.0
	var down := respawn_text(player) if player.respawn_state == Soldier.RESPAWN_WAITING \
		else downed_text(player.vitals) + give_up_text(player, held)
	# The title alone in the big alert style, the rest under it, wrapping (P1-11: the 28 px
	# "Your team can treat you..." line was wider than a 1280 window at UI scale 1.5).
	_downed.text = down.get_slice("\n", 0)
	_downed_detail.text = down.substr(_downed.text.length() + 1).strip_edges() if down.contains("\n") else ""
	_downed.visible = _downed.text != ""
	_downed_detail.visible = _downed_detail.text != ""


## The countdown while a dead player waits to respawn (Soldier.RESPAWN_WAITING).
static func respawn_text(player: Soldier) -> String:
	var left := ceili(maxf(player.respawn_eta - Soldier._now(), 0.0))
	return "KILLED\nRespawning in %d s" % left if player.respawn_eta >= 0.0 else "KILLED\nRespawning..."


## The give-up prompt under the downed text (Soldier.can_give_up): hold the key (rebindable,
## Controls "give_up") GIVE_UP_HOLD_S; until it's open, how long until it is. `held`: seconds held.
static func give_up_text(player: Soldier, held: float) -> String:
	if player.vitals.is_up() or player.vitals.is_dead() or player.is_ai():
		return ""
	var key := OS.get_keycode_string(GameSettings.key_for(&"give_up"))
	if player.can_give_up():
		if held > 0.0:
			return "\n\nGiving up... %d%%" % clampi(roundi(held / Soldier.GIVE_UP_HOLD_S * 100.0), 0, 100)
		return "\n\nHold [%s] to give up and respawn" % key
	var wait := ceili(maxf(Soldier.GIVE_UP_AFTER_S - player.seconds_down(), 0.0))
	return "\n\nGive up ([%s], hold) in %d s" % [key, wait]


## The text over a downed player's black screen: no health, just what is happening. You
## come round on your own once your body lets you (treatment helps); there is no revive.
static func downed_text(vitals: Vitals) -> String:
	if not vitals.downed:
		return ""
	if vitals.in_cardiac_arrest():
		var s := ceili(maxf(vitals.seconds_to_death(), 0.0))
		return "CARDIAC ARREST - %d:%02d\nYour heart has stopped" % [floori(s / 60.0), s % 60]
	if vitals.wake_eta() > 0.0:
		return "UNCONSCIOUS\nComing round..."
	return "UNCONSCIOUS\nYour team can treat you; you'll come round when your body recovers"


## The squad by F-key number, with each member's fire team and role (and colour team), and
## what each squadmate is doing. A ">" marks units selected in the command menu. No health:
## the handoff's HUD has no health readout.
func _squad_lines(player: Soldier) -> String:
	var units := command_menu.roster()
	if units.size() <= 1:
		return ""
	var lines := PackedStringArray()
	for i in units.size():
		var s := units[i]
		var mark := ">" if String(s.name) in command_menu.selected and command_menu.is_open() else " "
		var tag := CommandMenu.unit_tag(s)
		tag = " [%s]" % tag if tag != "" else ""
		if s.is_ai():
			lines.append("%s F%d %s%s: %s" % [mark, i + 1, s.display_name(), tag, s.ai_status])
		else:
			lines.append("  F%d %s%s" % [i + 1, "You" if s == player else "Player %s" % s.name, tag])
	return "SQUAD  [F-keys] select  [~] all  [T] voice order/ask\n" + "\n".join(lines) + "\n"
