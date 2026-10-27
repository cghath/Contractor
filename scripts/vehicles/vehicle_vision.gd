class_name VehicleVision
extends Camera3D
## Looking out of a buttoned-up hatch seat (combined arms A5, cg_brief queue item 2.4;
## docs/combined_arms.md 2.6, 2.12.2, F-252): the vision blocks and periscopes. Turned out, a man
## sees all round from his hatch (his own eye, as before); buttoned up in first person he sees
## only through his blocks: fixed slices round the hatch (data/vehicle_weapons.json's hatch
## "vision": [[yaw_deg, width_deg], ...]; the Abrams commander's six round the cupola, the
## loader's one, the driver's arc), at 1x (the player's own field of view), each a narrow slit of
## glass with nothing round it. The player's look picks the block nearest it (the camera sits at
## the seat's eye along that block's middle, his pitch kept within VISION_PITCH_DEG); the seat's
## sight (the aim key) takes over while it's up, the chase view (B) is never cut.
## - The driver's arc is split into periscopes (DRIVER_PERISCOPE_DEG each: the Abrams' 100
##   degrees is three) and has an image-intensified night channel (the sight channel key: day /
##   night; NvgView's tube look over the glass, the rest of the HUD dimmed). His driver_vision
##   module damaged loses the night channel; destroyed, the periscopes are out and he must turn
##   out to see (2.2.2).
## - VehicleHud draws the slit's mask and frame, the driver's readouts and the turret's arrow
##   from mode() and blocks(); this is only the view. Local player only: nothing replicated.

const NODE_NAME := &"VehicleVision"
## Proposed: the driver's arc is split into periscopes about this wide; a block's glass is this
## tall (degrees of the view); the look may tilt this far up or down within it.
const DRIVER_PERISCOPE_DEG := 35.0
const GLASS_TALL_DEG := 14.0
const VISION_PITCH_DEG := 8.0

var body: Soldier
var vehicle: Vehicle
var seat := -1
var up := false
## "day" or "night" (the driver's periscope only).
var channel := "day"
## The block looked through now (index into blocks()).
var block := 0
var _blocks: Array = []


func _init(p_body: Soldier = null) -> void:
	body = p_body
	name = NODE_NAME
	top_level = true
	process_priority = 101  # after VehicleCamera (100), as VehicleSight
	near = VehicleSight.NEAR_M * 0.5


## The vision view of local player `s`, or null.
static func of(s: Node) -> VehicleVision:
	return s.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleVision if is_instance_valid(s) else null


## Whether local player `s` is looking out through his blocks now.
static func up_for(s: Node) -> bool:
	var v := VehicleVision.of(s)
	return v != null and v.up


## Whether seat `seat` of `v` looks out through blocks now: a hatch seat with vision blocks,
## buttoned up, in first person, its sight not up.
static func wants(v: Vehicle, s: Soldier, p_seat: int) -> bool:
	if v == null or v.hatches == null or not v.hatches.has_hatch(p_seat) or v.hatches.is_out(p_seat) or VehicleCamera.chase:
		return false
	if ((v.hatches.defs[p_seat] as Dictionary).get("vision", []) as Array).is_empty():
		return false
	return s != null and s.vitals.is_up() and not VehicleSight.up_for(s)


## The blocks of seat `seat` of `v`: [[yaw_deg (its middle, from the hull's or turret's front,
## left positive, the seat's "face" added, as VehicleHatches.spot_x reads them), width_deg], ...];
## a driver's wide arc as periscopes.
static func blocks_of(v: Vehicle, p_seat: int) -> Array:
	var out: Array = []
	var vision: Array = (v.hatches.defs.get(p_seat, {}) as Dictionary).get("vision", []) if v and v.hatches else []
	var driver := v != null and v.seat_kind(p_seat) == Vehicle.DRIVER
	var face := float((v.spec.seats[p_seat] as Dictionary).get("face", 0.0)) if v else 0.0  # (as VehicleHatches.spot_x)
	for b: Array in vision:
		var yaw := float(b[0]) + face
		var width := float(b[1])
		var n := maxi(ceili(width / DRIVER_PERISCOPE_DEG - 0.01), 1) if driver else 1
		for i in n:
			out.append([yaw - width * 0.5 + width * (i + 0.5) / n, width / n])
	return out


## Every frame from VehicleHud.local_step: up or down for `v`'s seat `p_seat`, and the channel
## key for a driver.
static func local_step(v: Vehicle, s: Soldier, p_seat: int, free: bool) -> VehicleVision:
	var want := wants(v, s, p_seat)
	var vv := VehicleVision.of(s)
	if not want:
		if vv:
			vv.close()
		return vv
	if vv == null:
		vv = VehicleVision.new(s)
		s.add_child(vv)
	vv.open(v, p_seat)
	if free and v.seat_kind(p_seat) == Vehicle.DRIVER and Input.is_action_just_pressed(&"sight_channel"):
		var told := vv.cycle_channel()
		if s.player_input and s.player_input.hud:
			s.player_input.hud.flash(told)
	return vv


func open(v: Vehicle, p_seat: int) -> void:
	if vehicle != v or seat != p_seat:
		vehicle = v
		seat = p_seat
		_blocks = blocks_of(v, p_seat)
		block = clampi(block, 0, maxi(_blocks.size() - 1, 0))
	cull_mask = body.camera.cull_mask & ~PlayerInput.LOCAL_BODY_LAYER  # (not your own body in the view)
	up = true
	place()
	if not current and not VehicleSight.up_for(body):
		current = true


func close() -> void:
	if not up:
		return
	up = false
	channel = "day"
	if not current:
		return
	var chase := VehicleCamera.of(body)
	if chase and chase.active:
		chase.current = true
	elif VehicleSight.up_for(body):
		VehicleSight.of(body).current = true
	elif body and body.camera:
		body.camera.current = true


func blocks() -> Array:
	return _blocks


## "day", "night", or "out" (the driver's periscopes destroyed: he must turn out).
func mode() -> String:
	if vehicle == null or vehicle.seat_kind(seat) != Vehicle.DRIVER:
		return "day"
	match vehicle.modules.state("driver_vision") if vehicle.modules and vehicle.modules.index_of("driver_vision") >= 0 else VehicleModules.WORKING:
		VehicleModules.DESTROYED:
			return "out"
		VehicleModules.DAMAGED:
			return "day"
	return channel


## Whether the night channel can be had: a driver's periscope with its module working.
func night_ok() -> bool:
	return vehicle != null and vehicle.seat_kind(seat) == Vehicle.DRIVER and \
		(vehicle.modules == null or vehicle.modules.index_of("driver_vision") < 0 or vehicle.modules.state("driver_vision") == VehicleModules.WORKING)


## Day <-> night on a driver's periscope; what to flash.
func cycle_channel() -> String:
	if mode() == "out":
		return "Periscopes out: turn out to drive"
	if not night_ok():
		channel = "day"
		return "Night channel lost (periscope damaged)"
	channel = "night" if channel == "day" else "day"
	return "Periscope: night (image intensifier)" if channel == "night" else "Periscope: day"


## The frame the blocks are fixed in: the turret's for a seat that turns with it, else the hull's.
func frame() -> Basis:
	var b := vehicle.global_basis.orthonormalized()
	if vehicle.turret and vehicle.turns_with_turret(seat):
		b = b * Basis(Vector3.UP, vehicle.turret.yaw)
	return b


func _exit_tree() -> void:
	up = false


func _process(_delta: float) -> void:
	if not up:
		return
	if body == null or not is_instance_valid(vehicle) or vehicle.seat_of(body) != seat or not wants(vehicle, body, seat):
		close()
		return
	place()
	if not current and not VehicleSight.up_for(body):
		current = true


## At the seat's eye, along the block nearest the player's look, at his own field of view.
func place() -> void:
	if vehicle == null or _blocks.is_empty():
		return
	var f := frame()
	var look := f.inverse() * -body.camera.global_basis.z
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	var best := 1.0e9
	for i in _blocks.size():
		var d := absf(wrapf(yaw - float(_blocks[i][0]), -180.0, 180.0))
		if d < best:
			best = d
			block = i
	var pitch := clampf(rad_to_deg(asin(clampf(look.y, -1.0, 1.0))), -VISION_PITCH_DEG, VISION_PITCH_DEG)
	var basis := f * Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(float(_blocks[block][0])), 0.0))
	global_transform = Transform3D(basis, vehicle.seat_eye_point(seat))
	fov = body.camera.fov
	far = body.camera.far
