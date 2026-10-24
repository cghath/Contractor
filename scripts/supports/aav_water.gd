class_name AavWater
extends RefCounted
## Vehicles in water (wave 5b, V4): the sea on a coastal zone (ZoneTerrain.water_height). Host
## physics, called from Vehicle._drive_step each physics step while the hull's floor is under
## water (depth > 0):
## - Buoyancy: the hull is a box (its collision boxes' bounds) sampled at SAMPLE_X x SAMPLE_Z
##   points on its floor; each point pushes up with the weight of the water above it, at that
##   point, so the hull floats level and rights itself. An amphibious hull (data/vehicles.json
##   "amphibious") is sealed and floats; any other floods and sinks (NON_AMPHIBIOUS_BUOYANCY),
##   and its engine stalls deeper than "ford_m" (FORD_M by default).
## - Drag: water slows the hull along, across (far more) and up and down, and damps its roll and
##   pitch, more the deeper it sits. A6: the drag is against its way through the water, which moves
##   with a river (ZoneWater.flow_at), so a swimming hull crabs and drifts with the current; one held
##   to the bed (not afloat) takes the current's push on its immersed side (current_force). Its
##   waterjets push by their modules' health (jet_share); a holed or flooded hull loses buoyancy
##   (VehicleDrive).
## - Waterjets (amphibious only): throttle drives it along at up to "swim_kmh", the brake
##   reverses them to stop, steering turns it at "swim_turn_deg_s". Tracks or wheels that reach
##   the bottom still drive (Vehicle._wheel_forces), so it climbs out onto a beach by itself.
## Clients see the result through the vehicle's replicated pose. Numbers are Proposed.

const WATER_DENSITY := 1000.0
const SAMPLE_X := 3
const SAMPLE_Z := 5
## An unsealed hull keeps this share of its buoyancy (it floods and sinks).
const NON_AMPHIBIOUS_BUOYANCY := 0.25
## A6: a flooded hull (VehicleDrive) keeps only this share.
const FLOODED_BUOYANCY := 0.05
## Non-amphibious vehicles: the engine stalls with the water deeper than this over the hull's floor.
const FORD_M := 0.8
## Drag (1/s, times the hull's mass): along (non-amphibious; an amphibious hull's is set by its
## jets and swim speed), across, heave, roll and pitch. Full at DRAG_FULL_DEPTH_M and deeper.
const DRAG_LONG := 0.5
const DRAG_LAT := 2.5
const DRAG_HEAVE := 3.0
const DRAG_TURN := 2.0
const DRAG_FULL_DEPTH_M := 1.0
## Waterjets: their push (m/s2 at full throttle), the default swim speed and turn rate, how long
## the turn takes to answer (s), and astern thrust as a share of ahead.
const JET_ACCEL := 0.8
const SWIM_KMH := 13.0
const SWIM_TURN_DEG_S := 18.0
const JET_TURN_TIME_S := 0.8
const ASTERN_SHARE := 0.5
## Deeper than this (m over the hull's floor), an amphibious hull is afloat: nobody gets out.
const AFLOAT_M := 0.7


## The water's surface at (x, z) in `v`'s level, -INF where there's none.
static func water_height(v: Node3D, x: float, z: float) -> float:
	var lvl: Node = v.call(&"level") if v.has_method(&"level") else null
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if terrain is ZoneTerrain and ((terrain as ZoneTerrain).has_coast() or (terrain as ZoneTerrain).water != null):
		return (terrain as ZoneTerrain).water_height(x, z)  # the sea, and rivers and lakes (ZoneWater: a deep one floods a truck)
	return -INF


## How deep the hull's floor is under water (m; 0 when dry). Helicopters never swim.
static func depth(v: Vehicle) -> float:
	if v == null or not v.is_inside_tree() or v.kind == Vehicle.HELICOPTER:
		return 0.0
	var p := v.global_position
	var water := water_height(v, p.x, p.z)
	if water == -INF:
		return 0.0
	var floor_y := (v.global_transform * Vector3(0.0, hull_box(v).position.y, 0.0)).y
	return maxf(water - floor_y, 0.0)


## Whether `v` swims (data/vehicles.json "amphibious").
static func amphibious(v: Vehicle) -> bool:
	return v != null and v.spec.get("amphibious", null) is Dictionary


## An amphibious hull afloat in deep water (nobody gets out, AI won't dismount).
static func afloat(v: Vehicle) -> bool:
	return amphibious(v) and depth(v) > AFLOAT_M


## The throttle that drives the wheels: none for a non-amphibious vehicle drowned past its
## fording depth (A6: the water over the ground under it against the model's "ford_m",
## VehicleDrive.ford_depth; its engine then stalls, VehicleDrive).
static func throttle(v: Vehicle, wet: float, throttle_in: float) -> float:
	if wet <= 0.0 or amphibious(v):
		return throttle_in
	return 0.0 if VehicleDrive.ford_depth(v) > float(v.spec.get("ford_m", FORD_M)) else throttle_in


## A6: the waterjets' share of their push (an amphibious hull with A2's waterjet modules: the mean of
## their health; one out pushes from the other side, yaw_bias), and their turning bias (-1..1).
static func jet_share(v: Vehicle) -> Vector2:
	var m := v.modules
	if m == null or not m.authored or m.index_of("waterjet_l") < 0 or m.index_of("waterjet_r") < 0:
		return Vector2(1.0, 0.0)
	var l := m.health_of("waterjet_l")
	var r := m.health_of("waterjet_r")
	return Vector2((l + r) * 0.5, (l - r) * 0.5)


## The swim speed (m/s) of an amphibious vehicle.
static func swim_ms(v: Vehicle) -> float:
	var a: Dictionary = v.spec.get("amphibious", {}) if v.spec.get("amphibious", null) is Dictionary else {}
	return float(a.get("swim_kmh", SWIM_KMH)) / 3.6


## The body's own linear damping (1/s): its linear_damp, plus the project's default when combined.
static func body_damping(v: RigidBody3D) -> float:
	var own := v.linear_damp
	if v.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE:
		own += float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	return own


## The hull as one box in the vehicle's frame: its collision boxes' bounds (cached).
static func hull_box(v: Vehicle) -> AABB:
	if v.has_meta(&"water_hull"):
		return v.get_meta(&"water_hull")
	var box := AABB()
	var first := true
	for b: Array in v.spec.get("boxes", []):
		var a := VehicleSpecs.box(b)
		box = a if first else box.merge(a)
		first = false
	if first:
		var size := VehicleArt.size_m(v.model)
		box = AABB(Vector3(-size.x * 0.5, 0.3, -size.z * 0.5), Vector3(size.x, maxf(size.y - 0.3, 0.5), size.z))
	v.set_meta(&"water_hull", box)
	return box


## Host: one physics step of `v` in water `wet` metres deep over its floor (Vehicle._drive_step).
static func step(v: Vehicle, delta: float, wet: float, throttle_in: float, steer: float, brake: bool) -> void:
	if wet <= 0.0 or delta <= 0.0:
		return
	var box := hull_box(v)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var amph := amphibious(v)
	var share := 1.0 if amph else NON_AMPHIBIOUS_BUOYANCY
	var drive := VehicleDrive.of(v)
	if amph and drive:
		share = lerpf(1.0, NON_AMPHIBIOUS_BUOYANCY, drive.flood_share())  # A6: holed and filling, it sinks
	elif drive and drive.is_flooded():
		share = FLOODED_BUOYANCY  # A6: water through the cab: it goes down
	var cell := box.size.x * box.size.z / float(SAMPLE_X * SAMPLE_Z)
	var water := water_height(v, v.global_position.x, v.global_position.z)
	if water == -INF:
		return
	for ix in SAMPLE_X:
		for iz in SAMPLE_Z:
			var local := Vector3(lerpf(box.position.x, box.end.x, (ix + 0.5) / SAMPLE_X), box.position.y,
				lerpf(box.position.z, box.end.z, (iz + 0.5) / SAMPLE_Z))
			var at := v.global_transform * local
			var d := clampf(water - at.y, 0.0, box.size.y)
			if d > 0.0:
				v.apply_force(Vector3.UP * (WATER_DENSITY * g * cell * d * share), at - v.global_position)
	var k := clampf(wet / DRAG_FULL_DEPTH_M, 0.0, 1.0)
	var basis := v.global_basis
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var side := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var vel := v.linear_velocity - flow_of(v)  # A6: through the water, which moves with the river
	var v_long := vel.dot(fwd)
	var swim := swim_ms(v)
	var drag_long := JET_ACCEL / maxf(swim, 0.5) if amph else DRAG_LONG
	var force := -fwd * v_long * drag_long - side * vel.dot(side) * DRAG_LAT - Vector3.UP * vel.y * DRAG_HEAVE
	var jets := Vector3.ZERO
	var jet := jet_share(v)
	if amph and k > 0.3:
		# Waterjets: ahead or astern on the throttle; the brake reverses them to stop. They also
		# make up for the body's own damping (Godot's), so full ahead is swim speed. (A6: by the
		# waterjet modules' health.)
		var push := clampf(throttle_in, -1.0, 1.0)
		if push < 0.0:
			push *= ASTERN_SHARE
		if brake and absf(v_long) > 0.2:
			push = -signf(v_long) * ASTERN_SHARE
		push *= jet.x
		force += fwd * push * JET_ACCEL
		jets = fwd * push * swim * body_damping(v)
	v.apply_central_force((force * k + jets) * v.mass)
	if not afloat(v):
		v.apply_central_force(current_force(v, box, water))  # A6: the river's push on a hull held to its bed
	# Roll and pitch damped; yaw steered by the jets (amphibious) or damped.
	var size := box.size
	var inertia := v.mass * (size.x * size.x + size.z * size.z) / 12.0
	var ang := v.angular_velocity
	var up := basis.y
	var yaw_rate := ang.dot(up)
	var tilt := ang - up * yaw_rate
	var torque := -tilt * inertia * DRAG_TURN
	if amph and k > 0.3 and jet.x > 0.0:
		var a: Dictionary = v.spec.amphibious
		var turn := deg_to_rad(float(a.get("swim_turn_deg_s", SWIM_TURN_DEG_S)))
		var target := (-steer * jet.x + jet.y * absf(clampf(throttle_in, -1.0, 1.0)) * 0.5) * turn  # one jet out: it pulls round
		torque += up * (target - yaw_rate) * inertia / JET_TURN_TIME_S
	else:
		torque += -up * yaw_rate * inertia * DRAG_TURN * 0.5
	v.apply_torque(torque * k)


## A6: the river's current at `v` (m/s; zero with none).
static func flow_of(v: Vehicle) -> Vector3:
	var lvl: Node = v.level()
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if not (terrain is ZoneTerrain) or (terrain as ZoneTerrain).water == null:
		return Vector3.ZERO
	return (terrain as ZoneTerrain).water.flow_at(v.global_position.x, v.global_position.z)


## A6 (2.8.4): the river's push on the hull in it (N): 0.5 x rho x cd x A x |v_rel| v_rel along the
## flow (ZoneWater.flow_at) relative to the hull, A the immersed side the current meets. Swimming
## hulls crab; a light truck in a fast ford is pushed off its line.
static func current_force(v: Vehicle, box: AABB, water: float) -> Vector3:
	var lvl: Node = v.level()
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if not (terrain is ZoneTerrain) or (terrain as ZoneTerrain).water == null:
		return Vector3.ZERO
	var p := v.global_position
	var flow := (terrain as ZoneTerrain).water.flow_at(p.x, p.z)
	if flow.length_squared() < 0.0001:
		return Vector3.ZERO
	var rel := flow - Vector3(v.linear_velocity.x, 0.0, v.linear_velocity.z)
	var speed := rel.length()
	if speed < 0.01:
		return Vector3.ZERO
	var dir := rel / speed
	var basis := v.global_basis
	var floor_y := (v.global_transform * Vector3(0.0, box.position.y, 0.0)).y
	var deep := clampf(water - floor_y, 0.0, box.size.y)
	var area := deep * (absf(dir.dot(basis.x)) * box.size.z + absf(dir.dot(basis.z)) * box.size.x)
	var cd := VehicleDrive.num("current", "cd", 1.0)
	var rho := VehicleDrive.num("current", "rho", WATER_DENSITY)
	return dir * (0.5 * rho * cd * area * speed * speed)
