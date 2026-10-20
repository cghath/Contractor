class_name MortarPanel
extends CanvasLayer
## Laying and firing a mortar by hand (G-25 part d; the Captain, 2026-10-19: player mortar aiming
## by manual tables, no worked-out solution). The player reads the range and bearing off the map,
## looks up the elevation for a charge in the firing table here (worked out the way the round
## really flies, MortarTable), sets bearing, charge and elevation, and fires: one round from the
## mortar's hold or his own kit (the mortar's round item). Opened from the mortar's ring (Lay and
## fire); Esc closes it. What it fires goes to the host (Vehicle.request_mortar_fire).

const WIDTH := 460.0

var gun: Vehicle
var start_bearing := 0.0
var _bearing: SpinBox
var _charge: OptionButton
var _elevation: SpinBox
var _table: Label
var _shows: Label
var _mouse_before := Input.MOUSE_MODE_VISIBLE


static func open(p_gun: Vehicle, look_yaw_deg: float) -> MortarPanel:
	var p := MortarPanel.new()
	p.gun = p_gun
	p.start_bearing = wrapf(look_yaw_deg, 0.0, 360.0)  # laid the way he looks, to start with
	p_gun.get_tree().root.add_child(p)
	return p


func _ready() -> void:
	layer = 10
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := UiKit.screen(self, WIDTH)
	var m := MortarFire.spec_of(gun)
	box.add_child(UiKit.title("%s: lay and fire" % String(StaticWeapons.KITS.get(gun.model, {}).get("name", "Mortar"))))
	box.add_child(UiKit.hint("Read the range and the bearing to the target off the map. Pick a charge, find the elevation for that range in the table, set them, fire. The table is for a target level with the tube."))
	_bearing = SpinBox.new()
	_bearing.min_value = 0.0
	_bearing.max_value = 359.0
	_bearing.step = 1.0
	_bearing.suffix = "deg"
	_bearing.value = roundf(start_bearing)
	_bearing.value_changed.connect(func(_v: float) -> void: _update())
	box.add_child(UiKit.row("Bearing (from north)", _bearing))
	_charge = OptionButton.new()
	for c in MortarTable.charges(m):
		_charge.add_item("Charge %d" % c, c)
	_charge.item_selected.connect(func(_i: int) -> void: _update())
	box.add_child(UiKit.row("Charge", _charge))
	_elevation = SpinBox.new()
	_elevation.min_value = MortarTable.ELEVATION_MILS.x
	_elevation.max_value = MortarTable.ELEVATION_MILS.y
	_elevation.step = 10.0
	_elevation.value = 1100.0
	_elevation.suffix = "mils"
	_elevation.value_changed.connect(func(_v: float) -> void: _update())
	box.add_child(UiKit.row("Elevation", _elevation))
	_shows = UiKit.text("")
	box.add_child(_shows)
	box.add_child(UiKit.heading("Firing table"))
	_table = UiKit.text("")
	_table.add_theme_font_override(&"font", ThemeDB.fallback_font)
	box.add_child(_table)
	box.add_child(UiKit.button_row([
		UiKit.button("Fire", func() -> void: gun.request_mortar_fire.rpc_id(1, _bearing.value, _charge.get_selected_id(), _elevation.value)),
		UiKit.button("Close", close)], true))
	_update()


func _update() -> void:
	var m := MortarFire.spec_of(gun)
	if m.is_empty() or _charge == null:
		return
	var charge := _charge.get_selected_id()
	var rows := PackedStringArray(["Elev (mils)   Range (m)"])
	var e := MortarTable.ELEVATION_MILS.y
	while e >= MortarTable.ELEVATION_MILS.x:
		rows.append("%10d   %9d" % [int(e), roundi(MortarTable.range_m(m, charge, e))])
		e -= 50.0
	_table.text = "\n".join(rows)
	var r := MortarTable.range_m(m, charge, _elevation.value)
	var ok := r >= float(m.min_m) and r <= float(m.max_m)
	_shows.text = "Laid for about %d m on %d deg%s" % [roundi(r), int(_bearing.value), "" if ok else " (out of its range: it won't fire)"]


func close() -> void:
	Input.mouse_mode = _mouse_before
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
