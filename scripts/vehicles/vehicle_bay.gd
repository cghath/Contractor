class_name VehicleBay
extends Node3D
## A walk-in troop bay (Captain, 2026-10-16: the VTOLs' bay doors toggle, the door seats fire
## out, and players walk in and out on their own feet, "if not the Petrel the Razorback for
## sure"; walking is for a landed aircraft only, for now). A child of the Vehicle, built from
## its vehicles.json "bay" entry on every peer:
## - "walls": boxes [x0, y0, z0, x1, y1, z1] that stand in for the solid cabin boxes, a hollow
##   shell (floor, walls with the door gaps, roof) players walk inside;
## - "doors": {"name", "box", "slide"}: a panel over each door gap, solid while shut; open, it
##   slides by "slide" (m, the vehicle's frame) and stops blocking. Optional (Captain,
##   2026-10-17: the UH-60's door "sits flush to the hull then pops out slightly past the hull
##   1-2 cm and slides back", windows in it; the VTOLs' doors the same, after their own design):
##   "roll_deg" tilts the panel about the vehicle's length to lie on a leaning flank, "pop" (m)
##   is the step out it makes before the slide (POP_PART of the travel), and "windows"
##   ([y0, z0, y1, z1], the vehicle's frame) are glass panes set in it;
## - "ramp": {"hinge": [y, z], "length", "half_width", "thick", "closed_deg", "open_deg"}: a
##   panel hinged across the vehicle at the floor's aft edge, up with the doors shut, down to
##   the ground with them open (degrees below level: negative is up);
## - "steps": {"from", "to", "half_width"}: a boarding ramp under each door (Captain, 2026-10-16:
##   part of the hull, "it shoots out from under the doors then angles down towards the ground"):
##   stowed flat in a slot under the sill; landed with the bay open it slides straight out, then
##   swings down from the sill ("from") to the ground ("to", run a little into it so a vehicle
##   sitting tilted leaves no lip). One smooth surface to walk, grip strips drawn on it only.
##   Stowed again in the air, so an open bay in flight (FFV) has nothing hanging out;
## - "cabin": one box, the walkable inside (who is in the bay: at liftoff they're seated; it
##   may reach down over a ramp), and "floor_y", the cabin floor's height;
## Seats with "ffv": "left" or "right" are fire-from-vehicle seats: with the bay open their
## occupant fires their own weapon out of that side (Vehicle.ffv_ok; FfvGunner for the AI).
## The open state is the host's and goes out in Vehicle.net_state ("bay").
## The shell's shapes are the vehicle body's own (the living walk on vehicles: SoldierMovement.
## UP_MASK), standing in for the solid cabin boxes a vehicle without a bay has, so rounds and
## blasts meet the bay's walls as the hull. The ramps that reach the ground (the boarding ramps,
## the rear ramp) are on `deck` instead: a body on the vehicles' layer that meets nothing itself,
## so soldiers walk it and rounds hit it, but resting on (or a little into) the ground it never
## lifts the vehicle, which shapes of the vehicle's own body there did (it rose 0.85 m).

const PANEL_S := 0.8  ## doors slide and the ramp swings over this long
const POP_PART := 0.2  ## a door's "pop" out takes this much of its travel, the slide the rest
const STEP_S := 1.1  ## a boarding ramp slides out and angles down over this long (half each)
const STEP_SLOT_DROP_M := 0.1  ## stowed, a boarding ramp sits this far under its sill
const STEP_GRIP_EVERY_M := 0.3
## Deploying, the ramps find the ground under their tips (how high a vehicle sits on its gear
## varies, and so does the ground) and angle down to meet it, sunk this far in so there's no
## lip (and to cover a ground ray meeting the terrain a little above where feet stand), no steeper than MAX_RAMP_DEG (past that the data's angle stands).
const GROUND_SINK_M := 0.3
const MAX_RAMP_DEG := 40.0
## Above this height over the ground (m), a helicopter counts as off the ground whatever its
## flight mode says (its origin sits up to ~0.5 m over the ground on its gear when parked).
const LIFT_M := 1.2
const SEAT_CHECK_S := 0.2

var vehicle: Vehicle
var spec := {}
## The ground-reaching ramps' body (see above).
var deck: AnimatableBody3D

var open := false
var _doors: Array = []  ## [{"shape", "mesh", "closed": Vector3, "slide": Vector3, "pop": Vector3}]
var _ramp_shape: CollisionShape3D
var _ramp_mesh: MeshInstance3D
var _ramp_angle := 0.0
var _cabin := AABB()
var _blend := 0.0  ## 0 shut .. 1 open, eased towards `open`
var _steps: Array = []  ## [{"shape", "mesh", "a", "b"}]
var _ramp_blend := 0.0  ## the rear ramp: 0 up .. 1 down; down only with the bay open on the ground
var _deploy := 0.0  ## boarding ramps: 0 stowed .. 0.5 slid out .. 1 down on the ground
var _ramp_open_deg := NAN  ## the rear ramp's open angle, fitted to the ground (_fit_to_ground)
var _check_left := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	vehicle = p_vehicle
	name = "Bay"
	if vehicle:
		spec = vehicle.spec.get("bay", {})


## Builds the shapes (children of the vehicle body, so they collide as part of it) and the
## panels. Called from Vehicle.setup before it enters the tree.
func build() -> void:
	deck = AnimatableBody3D.new()
	deck.name = "BayDeck"
	deck.collision_layer = Vehicle.LAYER
	deck.collision_mask = 0
	deck.sync_to_physics = false
	vehicle.add_child(deck)
	var colour := Color(VehicleArt.SCHEMES.get(vehicle.scheme, VehicleArt.SCHEMES["od"]).paint).darkened(0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	var walls: Array = spec.get("walls", [])
	for i in walls.size():
		_add_box("BayWall%d" % i, VehicleSpecs.box(walls[i]))
	var step_mat := StandardMaterial3D.new()
	step_mat.albedo_color = Color("5b5d58")
	step_mat.roughness = 0.6
	step_mat.metallic = 0.4
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color("2b2c2a")
	var glass_mat := StandardMaterial3D.new()  # the doors' windows, like the hull's glass
	glass_mat.albedo_color = Color("27343c")  # VehicleArt's P.GLASS
	glass_mat.roughness = 0.15
	glass_mat.metallic = 0.3
	var steps: Array = spec.get("steps", [])
	for i in steps.size():
		var st: Dictionary = steps[i]
		var col := CollisionShape3D.new()
		col.name = "BayStep%d" % i
		var a := VehicleSpecs.vec(st.from)
		var b := VehicleSpecs.vec(st.to)
		var size := Vector3(float(st.get("half_width", 0.5)) * 2.0, 0.12, maxf(a.distance_to(b), 0.05))
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		deck.add_child(col)
		var mesh := MeshInstance3D.new()
		mesh.name = "BayStepPanel%d" % i
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		mesh.material_override = step_mat
		var z := -size.z * 0.5 + STEP_GRIP_EVERY_M * 0.5
		while z < size.z * 0.5:
			var strip := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(size.x * 0.9, 0.015, 0.05)
			strip.mesh = sm
			strip.material_override = grip_mat
			strip.position = Vector3(0, size.y * 0.5 + 0.007, z)
			mesh.add_child(strip)
			z += STEP_GRIP_EVERY_M
		add_child(mesh)
		_steps.append({"shape": col, "mesh": mesh, "a": a, "b": b, "b_spec": b})
	for d: Dictionary in spec.get("doors", []):
		var aabb := VehicleSpecs.box(d.box)
		var shape := _add_box("BayDoor_%s" % String(d.get("name", "door")), aabb)
		var mesh := MeshInstance3D.new()
		mesh.name = "BayDoorPanel_%s" % String(d.get("name", "door"))
		var bm := BoxMesh.new()
		bm.size = aabb.size
		mesh.mesh = bm
		mesh.material_override = mat
		mesh.position = aabb.get_center()
		mesh.rotation.z = deg_to_rad(float(d.get("roll_deg", 0.0)))
		for w: Array in d.get("windows", []):
			var pane := MeshInstance3D.new()
			pane.name = "Window"
			var pm := BoxMesh.new()
			pm.size = Vector3(aabb.size.x + 0.008, absf(float(w[2]) - float(w[0])), absf(float(w[3]) - float(w[1])))
			pane.mesh = pm
			pane.material_override = glass_mat
			pane.position = Vector3(0.0, (float(w[0]) + float(w[2])) * 0.5, (float(w[1]) + float(w[3])) * 0.5) - Vector3(0.0, aabb.get_center().y, aabb.get_center().z)
			mesh.add_child(pane)
		add_child(mesh)
		_doors.append({"shape": shape, "mesh": mesh, "closed": aabb.get_center(), "slide": VehicleSpecs.vec(d.get("slide"), Vector3.ZERO),
			"pop": VehicleSpecs.vec(d.get("pop"), Vector3.ZERO)})
	var ramp: Dictionary = spec.get("ramp", {})
	if not ramp.is_empty():
		var length := float(ramp.get("length", 3.0))
		var size := Vector3(float(ramp.get("half_width", 1.2)) * 2.0, float(ramp.get("thick", 0.12)), length)
		var box := BoxShape3D.new()
		box.size = size
		_ramp_shape = CollisionShape3D.new()
		_ramp_shape.name = "BayRamp"
		_ramp_shape.shape = box
		deck.add_child(_ramp_shape)
		_ramp_mesh = MeshInstance3D.new()
		_ramp_mesh.name = "BayRampPanel"
		var bm := BoxMesh.new()
		bm.size = size
		_ramp_mesh.mesh = bm
		_ramp_mesh.material_override = mat
		add_child(_ramp_mesh)
	if spec.has("cabin"):
		_cabin = VehicleSpecs.box(spec.cabin)
	_pose_panels()
	_pose_steps()


func _add_box(n: String, aabb: AABB) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	col.name = n
	var box := BoxShape3D.new()
	box.size = aabb.size
	col.shape = box
	col.position = aabb.get_center()
	vehicle.add_child(col)
	return col


## A slab's transform: centred between `a` and `b`, its length (z) along a->b, level across.
static func _slab(a: Vector3, b: Vector3) -> Transform3D:
	var along := (b - a).normalized()
	if along.length_squared() < 0.0001:
		return Transform3D(Basis(), a)
	var across := Vector3.UP.cross(along)
	if across.length_squared() < 0.0001:
		across = Vector3.RIGHT
	across = across.normalized()
	var up := along.cross(across).normalized()
	return Transform3D(Basis(across, up, along), (a + b) * 0.5)


## Every peer: open or shut (the host's word, from Vehicle.net_state).
func set_open(value: bool) -> void:
	if value == open:
		return
	open = value
	set_process(true)


func _ready() -> void:
	vehicle.add_collision_exception_with(deck)  # its own deck never shoves the hull
	set_process(true)  # the boarding ramps follow landed-or-not on every peer (Helicopter.flight_mode)


func _process(delta: float) -> void:
	var want := 1.0 if open else 0.0
	if _blend != want:
		if open and _blend == 0.0:
			_fit_to_ground()
		_blend = move_toward(_blend, want, delta / PANEL_S)
		_pose_panels()
	## Captain, 2026-10-17: doors opened in flight (to fire from them) leave the ramp up.
	var ramp_want := 1.0 if open and landed() else 0.0
	if _ramp_shape and _ramp_blend != ramp_want:
		_ramp_blend = move_toward(_ramp_blend, ramp_want, delta / PANEL_S)
		_pose_panels()
	var deploy := 1.0 if open and landed() else 0.0
	if _deploy != deploy and not _steps.is_empty():
		if deploy > 0.0 and _deploy == 0.0:
			_fit_to_ground()
		_deploy = move_toward(_deploy, deploy, delta / STEP_S)
		_pose_steps()


## The ground's height under the vehicle-frame point `at` (the vehicle's frame), or NAN.
func _ground_local(at: Vector3) -> float:
	if not vehicle.is_inside_tree():
		return NAN
	var top := vehicle.global_transform * (at + Vector3.UP * 2.0)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 8.0, 1, [vehicle.get_rid(), deck.get_rid()])
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if hit.is_empty() else (vehicle.global_transform.affine_inverse() * (hit.position as Vector3)).y


## Fits the boarding ramps' tips and the rear ramp's open angle to the ground under them.
func _fit_to_ground() -> void:
	var steep := sin(deg_to_rad(MAX_RAMP_DEG))
	for st: Dictionary in _steps:
		var a: Vector3 = st.a
		var b: Vector3 = st.b_spec
		var g := _ground_local(b)
		if is_nan(g):
			continue
		var length := a.distance_to(b)
		var drop := clampf(maxf(a.y - (g - GROUND_SINK_M), a.y - b.y), 0.0, length * steep)  # never shallower than the data's
		var run := sqrt(maxf(length * length - drop * drop, 0.0))
		var out := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		st.b = a + out * run + Vector3.DOWN * drop
	var ramp: Dictionary = spec.get("ramp", {})
	if not ramp.is_empty():
		var hinge: Array = ramp.get("hinge", [1.0, 5.0])
		var length := float(ramp.get("length", 3.0))
		var deg := deg_to_rad(float(ramp.get("open_deg", 19.0)))
		var g := _ground_local(Vector3(0.0, float(hinge[0]), float(hinge[1]) + length * cos(deg)))
		if not is_nan(g):
			var drop := clampf(float(hinge[0]) - (g - GROUND_SINK_M), 0.0, length * steep)
			_ramp_open_deg = maxf(rad_to_deg(asin(drop / length)), rad_to_deg(deg))  # never shallower than the data's


## Whether the vehicle sits on the ground (a helicopter: not flying, not lifted off).
func landed() -> bool:
	var heli := vehicle as Node as Helicopter
	return heli == null or (not heli.is_airborne() and heli.height_agl() < LIFT_M)


## The boarding ramps at _deploy: out from the slot under the sill, then down from it.
func _pose_steps() -> void:
	for st: Dictionary in _steps:
		var a: Vector3 = st.a
		var b: Vector3 = st.b
		var length := a.distance_to(b)
		var out := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var down := (b - a) / length
		var slot := Vector3(0.0, -STEP_SLOT_DROP_M, 0.0)
		var xf: Transform3D
		if _deploy < 0.5:
			var t := smoothstep(0.0, 1.0, _deploy / 0.5)
			var inner := a + slot - out * length * (1.0 - t)
			xf = _slab(inner, inner + out * length)
		else:
			var t := smoothstep(0.0, 1.0, (_deploy - 0.5) / 0.5)
			var hinge := a + slot * (1.0 - t)
			xf = _slab(hinge, hinge + out.slerp(down, t) * length)
		(st.shape as CollisionShape3D).transform = xf
		(st.shape as CollisionShape3D).disabled = _deploy < 0.98  # walkable once it's down
		(st.mesh as MeshInstance3D).transform = xf
		(st.mesh as MeshInstance3D).visible = _deploy > 0.01


func _pose_panels() -> void:
	var t := smoothstep(0.0, 1.0, _blend)
	var popped := smoothstep(0.0, 1.0, clampf(_blend / POP_PART, 0.0, 1.0))
	var slid := smoothstep(0.0, 1.0, clampf((_blend - POP_PART) / (1.0 - POP_PART), 0.0, 1.0))
	for d: Dictionary in _doors:
		## Out "pop" first, then back along the rail; shutting, the other way round.
		var pop: Vector3 = d.pop
		(d.mesh as MeshInstance3D).position = (d.closed as Vector3) + pop * popped + (d.slide as Vector3) * (slid if pop != Vector3.ZERO else t)
		(d.shape as CollisionShape3D).disabled = _blend > 0.05  # past the gap, it stops blocking
	var ramp: Dictionary = spec.get("ramp", {})
	if _ramp_shape:
		var hinge: Array = ramp.get("hinge", [1.0, 5.0])
		var length := float(ramp.get("length", 3.0))
		var open_deg := _ramp_open_deg if not is_nan(_ramp_open_deg) else float(ramp.get("open_deg", 19.0))
		_ramp_angle = deg_to_rad(lerpf(float(ramp.get("closed_deg", -17.0)), open_deg, smoothstep(0.0, 1.0, _ramp_blend)))
		var h := Vector3(0.0, float(hinge[0]), float(hinge[1]))
		var dir := Vector3(0.0, -sin(_ramp_angle), cos(_ramp_angle))  # aft from the hinge, down by the angle
		var xf := _slab(h, h + dir * length)
		_ramp_shape.transform = xf
		_ramp_mesh.transform = xf


func has_cabin() -> bool:
	return _cabin.has_volume()


## Where someone getting up from the seat at `seat_at` (the vehicle's frame) stands: on the bay
## floor just ahead of it, pulled in from the wall; null when that's outside the cabin.
func aisle_by(seat_at: Vector3) -> Variant:
	var spot := Vector3(seat_at.x * 0.5, float(spec.get("floor_y", _cabin.position.y)) + 0.05, seat_at.z - 0.5)
	return spot if _cabin.grow(0.05).has_point(spot + Vector3.UP * 0.1) else null


## Whether `s` stands inside the bay (not in a seat). `below`: metres under the floor that still
## count (lifting off, the floor rises out from under someone on their feet).
const LIFT_BELOW_M := 1.5
func inside(s: Node3D, below := 0.0) -> bool:
	if s == null or not _cabin.has_volume() or Vehicle.ride_of(s) != null:
		return false
	var local := vehicle.global_transform.affine_inverse() * s.global_position
	var box := _cabin.grow(0.15)
	box.position.y -= below
	box.size.y += below
	return box.has_point(local + Vector3.UP * 0.1)


## Host: once a helicopter lifts off, anyone standing in the bay sits in the nearest free seat
## (walking is for a landed aircraft only, Captain 2026-10-16); with none free they're put out.
func server_step(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or not _cabin.has_volume():
		return
	_check_left = SEAT_CHECK_S
	var heli := vehicle as Helicopter
	if heli == null or (not heli.is_airborne() and heli.height_agl() < LIFT_M):
		return
	var lvl := vehicle.level()
	if lvl == null:
		return
	for holder: Node in [lvl.players, lvl.ai]:
		for n in holder.get_children():
			var s := n as Soldier
			if s == null or s.is_queued_for_deletion() or not inside(s, LIFT_BELOW_M):
				continue
			var seat := nearest_free_seat(s.global_position)
			if seat < 0 or not vehicle.server_enter(s, seat):
				vehicle.server_put_out(s)


## The free non-pilot seat nearest `at` (world), or -1.
func nearest_free_seat(at: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in vehicle.seat_count():
		if vehicle.occupant(i) != null or vehicle.seat_kind(i) == Vehicle.PILOT:
			continue
		var d := at.distance_squared_to(vehicle.global_transform * VehicleSpecs.vec(vehicle.spec.seats[i].at))
		if d < best_d:
			best_d = d
			best = i
	return best


## How far open the doors are now, 0 shut to 1 open (eased, every peer): the FFV riders move
## from crouched behind the door to sitting with it (Vehicle._ffv_crouch).
func open_fraction() -> float:
	return _blend


## Which side seat `seat` fires out of (-1 left, 1 right), or 0 when it isn't a fire-from-vehicle
## seat.
func ffv_side(seat: int) -> float:
	var seats: Array = vehicle.spec.get("seats", [])
	if seat < 0 or seat >= seats.size():
		return 0.0
	match String((seats[seat] as Dictionary).get("ffv", "")):
		"left":
			return -1.0
		"right":
			return 1.0
	return 0.0


## Whether seat `seat` fires out now: an FFV seat with the bay open.
func ffv_active(seat: int) -> bool:
	return open and ffv_side(seat) != 0.0


## Whether a round from FFV seat `seat` along `direction` (world) goes out its door: outboard of
## the side by FFV_ARC_OUT, not steeply up or back into the hull.
const FFV_ARC_OUT := 0.25
const FFV_ARC_UP := 0.6
func ffv_arc_ok(seat: int, direction: Vector3) -> bool:
	if not ffv_active(seat) or direction.length_squared() < 0.000001:
		return false
	var local := (vehicle.global_basis.inverse() * direction).normalized()
	return local.x * ffv_side(seat) >= FFV_ARC_OUT and local.y <= FFV_ARC_UP
