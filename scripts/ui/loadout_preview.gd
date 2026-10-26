class_name LoadoutPreview
extends SubViewportContainer
## The 3D soldier in the loadout editor (claude/loadout-3d; Captain, 2026-10-22: "we never made
## it 3d like i told you to"). His own model (CharacterModel: camo, face, build) wearing a kit
## through the game's own GearRig, so what shows is what he'll wear in the field, voxel for
## voxel, in a world of its own (a SubViewport) under a studio light.
##
## Drag to turn him, wheel to zoom, focus() a body region. The slots you can click are marked
## on him (anchors(): the helmet and its NVG mount, the carrier, the plate pockets, every MOLLE
## point, the pack, the guns, their rails and muzzle); a click says which (slot_clicked), the
## one picked is drawn lit (selected).

signal slot_clicked(key: String)

## Regions you can focus: [label, look-at height (m), camera distance (m), marker filter].
const REGIONS := {
	"all": ["Whole body", 1.0, 3.1],
	"head": ["Head", 1.62, 1.1],
	"torso": ["Torso", 1.25, 1.55],
	"legs": ["Legs", 0.55, 1.9],
	"weapon": ["Weapons", 1.15, 1.35],
}
const ZOOM_MIN := 0.55
const ZOOM_MAX := 4.5
## Turn per pixel dragged (radians).
const TURN_PER_PX := 0.01
## A marker's size on screen (logical px) and how far a click may be from one.
const MARK_R := 9.0
const PICK_R := 18.0
## A press that moved less than this is a click, not a drag.
const CLICK_PX := 5.0

var viewport: SubViewport
var camera: Camera3D
var mannequin: Node3D
var model: CharacterModel
var inventory: Inventory
var gear: GearRig
var overlay: Control
var region := "all"
## Survival's gear editor (LoadoutGear): the clothing slots are markers too (call 132).
var clothing := false
var selected := ""
var hovered := ""
## Marker keys left out of the view (the editor's filter: "" none).
var yaw := 0.0
var _distance := 3.1
var _look_y := 1.0
var _want_distance := 3.1
var _want_look_y := 1.0
var _press_at := Vector2.ZERO
var _pressed := false
var _dragged := false
var _anchors: Array = []
var _anchors_dirty := true


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(200, 110)
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.6)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()  # the key light, high and to the front left
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()  # a cooler rim from behind, so the back and pack read
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.45
	rim.light_color = Color(0.75, 0.82, 1.0)
	viewport.add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.02
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.15)
	disc.material = floor_mat
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.01
	viewport.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.05
	viewport.add_child(camera)
	camera.current = true
	_place_camera()
	overlay = Control.new()
	overlay.name = "Markers"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_markers)
	add_child(overlay)
	set_look({})


## Puts the look of a person on the model: {"variant", "body", "face", "left_handed",
## "name_tape"} (any missing: the company's look). Rebuilds the model.
func set_look(look: Dictionary) -> void:
	var kept: Dictionary = Roster.json_safe(inventory.net_state) if inventory else {}
	if mannequin:
		mannequin.queue_free()
	mannequin = Node3D.new()
	mannequin.name = "Mannequin"
	inventory = Inventory.new()
	inventory.name = "Inventory"
	mannequin.add_child(inventory)
	model = CharacterModel.new()
	model.name = "Model"
	model.variant = String(look.get("variant", Soldier.COMPANY_VARIANT))
	model.body = String(look.get("body", VoxelArt.MALE))
	if String(look.get("face", "")) != "":
		model.face = String(look.face)
	model.left_handed = bool(look.get("left_handed", false))
	model.name_tape = String(look.get("name_tape", ""))
	model.iff = GearRig.iff_of(&"friendly", &"", model.variant)
	model.lod = false
	mannequin.add_child(model)
	gear = GearRig.new()
	gear.name = "Gear"
	gear.inventory = inventory
	gear.model = model
	mannequin.add_child(gear)
	viewport.add_child(mannequin)
	mannequin.rotation.y = yaw
	if not kept.is_empty():
		show_gear(kept)


## Dresses the model in `gear_state` (an Inventory.net_state, JSON-safe).
func show_gear(gear_state: Dictionary) -> void:
	inventory.net_state = GameState.from_json(gear_state.duplicate(true))
	model.hold = CharacterModel.Hold.NONE  # arms down: the chest, sides and guns show
	_anchors_dirty = true
	overlay.queue_redraw()


func focus(which: String) -> void:
	if not REGIONS.has(which):
		return
	region = which
	_want_look_y = float(REGIONS[which][1])
	_want_distance = float(REGIONS[which][2])
	if which == "weapon" and gear and gear._gear.has(&"primary"):  # the slung rifle hangs at the front
		yaw = 0.35 if not model.left_handed else -0.35
	_anchors_dirty = true
	overlay.queue_redraw()


func zoom(by: float) -> void:
	_want_distance = clampf(_want_distance * by, ZOOM_MIN, ZOOM_MAX)


func turn(radians: float) -> void:
	yaw = wrapf(yaw + radians, -PI, PI)
	if mannequin:
		mannequin.rotation.y = yaw
	overlay.queue_redraw()


func _process(delta: float) -> void:
	var k := minf(1.0, delta * 8.0)
	var moved := absf(_distance - _want_distance) > 0.001 or absf(_look_y - _want_look_y) > 0.001
	_distance = lerpf(_distance, _want_distance, k)
	_look_y = lerpf(_look_y, _want_look_y, k)
	_place_camera()
	if moved or _anchors_dirty:
		overlay.queue_redraw()


func _place_camera() -> void:
	if camera:
		camera.position = Vector3(0, _look_y + 0.08, -_distance)  # he faces -Z: the camera stands in front
		camera.look_at(Vector3(0, _look_y, 0), Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom(0.9)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom(1.1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragged = false
				_press_at = mb.position
			else:
				if _pressed and not _dragged:
					var key := key_at(mb.position)
					if key != "":
						slot_clicked.emit(key)
				_pressed = false
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if mm.position.distance_to(_press_at) > CLICK_PX:
				_dragged = true
			if _dragged:
				turn(mm.relative.x * TURN_PER_PX)
		var h := key_at(mm.position)
		if h != hovered:
			hovered = h
			tooltip_text = label_of(h)
			overlay.queue_redraw()


# --- Markers --------------------------------------------------------------------------------

## The clickable places on the model for the current region: [{"key", "label", "at" (world),
## "region"}]. Keys: "slot:<slot>", "mount:<slot>:<mount>", "point:<attach point id>".
func anchors() -> Array:
	if not _anchors_dirty:
		return _anchors
	_anchors_dirty = false
	_anchors = []
	if model == null or model.torso == null:
		return _anchors
	var torso := model.torso.global_transform
	var head := model.head.global_transform
	_add(head * Vector3(0, 0.27, 0), "slot:helmet", "Helmet", "head")
	if inventory.slots.get(&"helmet", &"") != &"":
		_add(head * Vector3(0, 0.2, -0.13), "mount:helmet:nvg", "Helmet mount: NVG", "head")
	_add(torso * Vector3(0, 0.36, -0.2), "slot:vest", "Carrier", "torso")
	if inventory.slots.get(&"vest", &"") != &"":
		_add(torso * Vector3(0.07, 0.42, -0.2), "slot:plate_front", "Front plate", "torso")
		_add(torso * Vector3(0, 0.36, 0.2), "slot:plate_back", "Back plate", "torso")
		var carrier := ItemDB.get_item(inventory.slots[&"vest"])
		if &"plate_left" in (carrier.stats.get("plate_slots", []) as Array).map(func(v: Variant) -> StringName: return StringName(String(v))) \
				or String(carrier.stats.get("tier", "")) == "heavy":
			_add(torso * Vector3(-0.2, 0.3, 0), "slot:plate_left", "Left side plate", "torso")
			_add(torso * Vector3(0.2, 0.3, 0), "slot:plate_right", "Right side plate", "torso")
	_add(torso * Vector3(0, 0.3, 0.3), "slot:backpack", "Pack", "torso")
	var point_spots := {}  # attach point id -> where its marker is (its pouch's box sits beside it)
	for p: Dictionary in inventory.attach_points():
		var on_pack := inventory.point_slot(StringName(p.id)) == &"backpack"
		var face := String(p.get("face", "front"))
		var fit := gear.carrier_fit("back" if on_pack else face) if gear else Transform3D.IDENTITY
		var spot := torso * fit * GearRig.point_transform(p, Vector3(0.06, 0.08, 0.04))
		var att := inventory.attachment(StringName(p.id))
		var what := ItemDB.get_item(StringName(att.id)).name if not att.is_empty() else "empty"
		_add(spot.origin, "point:" + String(p.id), "%s point (%s): %s" % [Inventory.POINT_TYPES.get(String(p.get("type", "")), "MOLLE"),
			"pack" if on_pack else face, what], "torso")
		point_spots[String(p.id)] = spot.origin
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var node: Node3D = (gear._gear.get(slot, [&"", null])[1] if gear else null)
		var at: Vector3
		if node and is_instance_valid(node) and node.is_inside_tree():
			at = node.global_position
		else:
			at = torso * {&"primary": Vector3(0.05, 0.2, -0.26), &"sidearm": Vector3(0.24, 0.0, 0.0), &"launcher": Vector3(-0.1, 0.4, 0.3)}[slot]
		_add(at, "slot:" + String(slot), String(Loadouts.SLOT_NAMES[slot]), "weapon")
		var gun_id: StringName = inventory.slots.get(slot, &"")
		if gun_id == &"" or node == null or not is_instance_valid(node):
			continue
		var gun := ItemDB.get_item(gun_id)
		var size: Array = gun.stats.get("size_m", [0.07, 0.25, 0.8])
		var b := node.global_transform.basis.orthonormalized()
		var length := float(size[2])
		var mounts: Array[String] = []
		if Optics.has_rail(gun):
			mounts.append("optic")
		mounts.append_array(GearMounts.mounts_for(gun))
		for m: String in mounts:
			var local: Vector3 = {"optic": Vector3(0, 0.07, 0.0), "muzzle": Vector3(0, 0.02, -length * 0.5),
				"underbarrel": Vector3(0, -0.05, -length * 0.22), "side": Vector3(0.05, 0.02, -length * 0.3),
				"choke": Vector3(0, 0.0, -length * 0.48)}.get(m, Vector3.ZERO)
			_add(at + b * local, "mount:%s:%s" % [slot, m], "%s: %s" % [Loadouts.SLOT_NAMES[slot], GearMounts.NAMES.get(m, m)], "weapon")
	_add(model.global_transform * Vector3(0.12, 0.62, -0.06), "pockets", "Pockets", "legs")
	# Call 134: the containers things go INTO, each a small hotspot beside its slot ("box:<container>":
	# a pouch's beside its point, the carrier's, the pack's, the pockets'), labelled with its fill.
	for c: StringName in inventory.search_containers():
		if inventory.capacity(c) <= 0.0:
			continue
		var at := Vector3.ZERO
		var where := "torso"
		if Inventory.is_pouch_container(c):
			var point := String(Inventory.point_of(c))
			if not point_spots.has(point):
				continue
			at = point_spots[point] + torso.basis * Vector3(0.0, -0.045, -0.03)
		elif c == &"vest":
			at = torso * Vector3(-0.12, 0.22, -0.22)
		elif c == &"backpack":
			at = torso * Vector3(0.12, 0.18, 0.33)
		else:
			at = model.global_transform * Vector3(-0.13, 0.6, -0.07)
			where = "legs"
		_add(at, "box:" + String(c), "%s: %s" % [inventory.container_label(c), box_fill(inventory, c)], where)
	if clothing:
		var spots := {&"head": [head * Vector3(0.06, 0.24, -0.06), "head"], &"face": [head * Vector3(0, 0.07, -0.13), "head"],
			&"torso_base": [torso * Vector3(-0.16, 0.12, -0.13), "torso"], &"torso_mid": [torso * Vector3(-0.19, 0.22, -0.12), "torso"],
			&"torso_outer": [torso * Vector3(-0.22, 0.32, -0.1), "torso"], &"hands": [torso * Vector3(0.3, -0.05, -0.05), "torso"],
			&"legs": [model.global_transform * Vector3(-0.12, 0.5, -0.06), "legs"], &"feet": [model.global_transform * Vector3(0.1, 0.06, -0.08), "legs"]}
		for slot: StringName in Inventory.CLOTHING_SLOTS:
			var id := StringName(inventory.slots.get(slot, &""))
			_add(spots[slot][0], "slot:" + String(slot), "%s: %s" % [Clothing.NAMES.get(slot, String(slot)), ItemDB.get_item(id).name if id != &"" else "nothing"], String(spots[slot][1]))
	return _anchors


## How full container `c` of `inv` is: "2 of 3" (a pouch counting units) or "1.5 of 6.0 L".
static func box_fill(inv: Inventory, c: StringName) -> String:
	var pouch: ItemData = inv.pouch_item(c) if Inventory.is_pouch_container(c) else null
	var units := int(pouch.stats.get("max_units", 0)) if pouch else 0
	return "%d of %d" % [inv.units_in(c), units] if units > 0 else "%.1f of %.1f L" % [inv.used(c), inv.capacity(c)]


func _add(at: Vector3, key: String, label: String, where: String) -> void:
	_anchors.append({"key": key, "label": label, "at": at, "region": where})


## Whether a marker shows now: in the whole-body view only the main slots; zoomed into a
## region, that region's.
func shown(a: Dictionary) -> bool:
	if region == "all":
		if clothing and String(a.key) in ["slot:head", "slot:torso_outer", "slot:legs", "slot:feet"]:
			return true
		return String(a.key) in ["slot:helmet", "slot:vest", "slot:backpack", "slot:primary", "slot:sidearm", "slot:launcher", "pockets"]
	return String(a.region) == region or String(a.key) == selected


## Where world point `at` is on this control (logical px), or null behind the camera.
func screen_of(at: Vector3) -> Variant:
	if camera == null or camera.is_position_behind(at):
		return null
	var p := camera.unproject_position(at)
	var scale_by := size / Vector2(viewport.size) if viewport.size.x > 0 and viewport.size.y > 0 else Vector2.ONE
	return p * scale_by


## The marker nearest `pos` (control px) within PICK_R, or "".
func key_at(pos: Vector2) -> String:
	var best := ""
	var best_d := PICK_R
	for a: Dictionary in anchors():
		if not shown(a):
			continue
		var p: Variant = screen_of(a.at)
		if p == null:
			continue
		var d := (p as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best = String(a.key)
	return best


func label_of(key: String) -> String:
	for a: Dictionary in anchors():
		if String(a.key) == key:
			return String(a.label)
	return ""


func _draw_markers() -> void:
	var font := UiKit.FONT_STRONG if UiKit.FONT_STRONG else overlay.get_theme_default_font()
	for a: Dictionary in anchors():
		if not shown(a):
			continue
		var p: Variant = screen_of(a.at)
		if p == null:
			continue
		var at := p as Vector2
		var lit := String(a.key) == selected
		var hot := String(a.key) == hovered
		var r := MARK_R * (1.35 if lit or hot else 1.0)
		var fill := UiKit.ACCENT if lit else (UiKit.ACCENT_HOT if hot else Color(UiKit.TEXT_BRIGHT, 0.85))
		if String(a.key).begins_with("box:"):  # a container: a small square, not a ring (call 134)
			var h := r * 0.75
			overlay.draw_rect(Rect2(at - Vector2(h + 2.0, h + 2.0), Vector2(h + 2.0, h + 2.0) * 2.0), UiKit.OUTLINE)
			overlay.draw_rect(Rect2(at - Vector2(h, h), Vector2(h, h) * 2.0), fill)
			overlay.draw_rect(Rect2(at - Vector2(h, h) * 0.4, Vector2(h, h) * 0.8), UiKit.INK)
		else:
			overlay.draw_circle(at, r + 2.0, UiKit.OUTLINE)
			overlay.draw_circle(at, r, fill)
			overlay.draw_circle(at, r * 0.45, UiKit.INK)
		if (lit or hot) and font:
			var text := String(a.label)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL).x
			var x := clampf(at.x + r + 6.0, 4.0, maxf(4.0, size.x - w - 4.0))
			var box := Rect2(Vector2(x - 4.0, at.y - 12.0), Vector2(w + 8.0, 22.0))
			overlay.draw_rect(box, UiKit.PANEL_BG)
			overlay.draw_string(font, Vector2(x, at.y + 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_SMALL, UiKit.TEXT_BRIGHT)
