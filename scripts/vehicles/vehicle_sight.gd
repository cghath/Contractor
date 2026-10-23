class_name VehicleSight
extends Camera3D
## Looking through a vehicle's sight (combined arms A4, cg_brief queue item 2.3;
## docs/combined_arms.md 2.7.4, call 19): full screen, not picture-in-picture. A Camera3D at the
## sight's glass on the turret (VehicleGunnery.sight_from), along its line (the gunner's: the
## turret's sight line, stabilised or not as the gun is; the commander's viewer: wherever he
## looks), switched to with the aim key from a seat with a sight (buttoned up). The local player's
## only: nothing here is replicated.
##
## - Magnification is relative to the player's own view: the sight's field of view is his base
##   view's narrowed by the power (the tangent over it); zoom in and out step through the
##   channel's powers, and the mouse turns slower to match (zoom_turn, PlayerInput's hook).
## - Channels: day and thermal (white-hot, black-hot), as the sight has them (a damaged primary
##   is day only); the sight channel key steps through them. Thermal is ThermalView, on only
##   while this sight is up on a thermal channel.
## - VehicleSightOverlay draws the reticle and the readouts over it.
## The pieces A5 restyles: the overlay's look; this keeps the view.

const NODE_NAME := &"VehicleSight"
## Proposed: the near plane (m): the glass sits on the turret's roof, the roof's voxels inside it.
const NEAR_M := 0.6

var body: Soldier
var gunnery: VehicleGunnery
var vehicle: Vehicle
var seat := -1
var up := false
## "day" or "thermal".
var channel := "day"
var polarity := ThermalView.WHITE_HOT
var _mag_i := {}  # "optic:channel" -> index into its powers
var overlay: VehicleSightOverlay


func _init(p_body: Soldier = null) -> void:
	body = p_body
	name = NODE_NAME
	top_level = true
	process_priority = 101  # after VehicleCamera (100): this one is current while it's up
	near = NEAR_M


## The sight of local player `s`, or null.
static func of(s: Node) -> VehicleSight:
	return s.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleSight if is_instance_valid(s) else null


## Whether local player `s` is looking through a vehicle's sight now.
static func up_for(s: Node) -> bool:
	var v := VehicleSight.of(s)
	return v != null and v.up


## Opens `g`'s sight at seat `seat` for local player `me` (made the first time).
static func open_for(me: Soldier, g: VehicleGunnery, p_seat: int) -> VehicleSight:
	var v := VehicleSight.of(me)
	if v == null:
		v = VehicleSight.new(me)
		me.add_child(v)
	v.open(g, p_seat)
	return v


## The mouse's turn while the sight is up: the sight's tangent over the base view's (1 otherwise).
static func zoom_turn(s: Node) -> float:
	var v := VehicleSight.of(s)
	if v == null or not v.up or v.body == null:
		return 1.0
	return minf(tan(deg_to_rad(v.fov * 0.5)) / tan(deg_to_rad(v.body.camera.fov * 0.5)), 1.0)


func open(g: VehicleGunnery, p_seat: int) -> void:
	gunnery = g
	vehicle = g.vehicle
	seat = p_seat
	up = true
	var s := g.sight_for(seat)
	if channel == "thermal" and (s.get("thermal", []) as Array).is_empty():
		channel = "day"
	if channel == "day" and (s.get("day", []) as Array).is_empty():
		channel = "thermal"
	cull_mask = body.camera.cull_mask
	if overlay == null and body.player_input and body.player_input.hud:
		overlay = VehicleSightOverlay.new()
		body.player_input.hud.add_child(overlay)
		body.player_input.hud.move_child(overlay, 0)  # under the rest of the HUD
	if overlay:
		overlay.visible = true
	place()
	current = true


func close() -> void:
	if not up:
		return
	up = false
	ThermalView.set_mode(ThermalView.OFF)
	if overlay:
		overlay.visible = false
	var chase := VehicleCamera.of(body)
	if chase and chase.active:
		chase.current = true
	elif body and body.camera:
		body.camera.current = true


## The sight's powers on the channel now.
func powers() -> Array:
	if gunnery == null:
		return [1.0]
	var list: Array = gunnery.sight_for(seat).get(channel, [])
	return list if not list.is_empty() else [1.0]


func _key() -> String:
	return "%s:%s" % [String((gunnery.sight_for(seat).get("o", {}) as Dictionary).get("id", "")) if gunnery else "", channel]


## The power now (x).
func mag() -> float:
	var p := powers()
	return float(p[clampi(int(_mag_i.get(_key(), 0)), 0, p.size() - 1)])


## Steps the power up (+1) or down (-1).
func step_mag(steps: int) -> void:
	var p := powers()
	_mag_i[_key()] = clampi(int(_mag_i.get(_key(), 0)) + steps, 0, p.size() - 1)


## The next channel: day, thermal white-hot, thermal black-hot (those the sight has). Its name.
func cycle_channel() -> String:
	var s := gunnery.sight_for(seat) if gunnery else {}
	var ways: Array = []
	if not (s.get("day", []) as Array).is_empty():
		ways.append(["day", ThermalView.WHITE_HOT])
	if not (s.get("thermal", []) as Array).is_empty():
		ways.append(["thermal", ThermalView.WHITE_HOT])
		ways.append(["thermal", ThermalView.BLACK_HOT])
	if ways.size() < 2:
		return "%s: day only" % String((s.get("o", {}) as Dictionary).get("name", "Sight")) if not ways.is_empty() else ""
	var at := 0
	for i in ways.size():
		if ways[i][0] == channel and (channel == "day" or ways[i][1] == polarity):
			at = i
	var next: Array = ways[(at + 1) % ways.size()]
	channel = String(next[0])
	polarity = int(next[1])
	return "Day" if channel == "day" else "Thermal, %s" % ("white-hot" if polarity == ThermalView.WHITE_HOT else "black-hot")


func _process(_delta: float) -> void:
	if not up:
		return
	if body == null or not is_instance_valid(vehicle) or vehicle.seat_of(body) != seat or not body.vitals.is_up() or gunnery.sight_for(seat).is_empty():
		close()
		return
	if channel == "thermal" and (gunnery.sight_for(seat).get("thermal", []) as Array).is_empty():
		channel = "day"  # the primary damaged: thermal lost
	place()
	if not current:
		current = true


## The camera at the glass along the line, at the power; thermal on or off; the overlay's readout.
func place() -> void:
	if gunnery == null:
		return
	var from := gunnery.sight_from(seat)
	var dir := gunnery.sight_dir(seat)
	if dir.length_squared() < 0.0001:
		return
	var up_v := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.BACK
	global_transform = Transform3D(Basis.looking_at(dir, up_v), from)
	var base := body.camera.fov
	fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / maxf(mag(), 1.0)))
	far = body.camera.far
	if channel == "thermal":
		ThermalView.ambient = lerpf(0.4, 0.2, DayNight.darkness_at(from))
		ThermalView.set_mode(polarity)
		ThermalView.update(get_tree(), from)
	else:
		ThermalView.set_mode(ThermalView.OFF)
	if overlay:
		overlay.show_info(gunnery.sight_info(seat), self)
