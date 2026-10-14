class_name VehicleCamera
extends Camera3D
## The third-person chase view for the local player while they sit in a vehicle (Captain,
## 2026-10-13: vehicles were unusable, a seated player's eye is inside the solid hull; he chose
## "1st person + 3rd toggle", the chase view first). Any seat: driver, gunner, passenger, the
## helicopter's and the AAV's too. The vehicle view key (Controls "vehicle_view", B) switches
## between it and first person (the soldier's own camera at the seat's eye, as before); the
## choice holds for the rest of the session (`chase`, not saved). Getting out puts the on-foot
## camera back.
##
## The view is the soldier's own look (the mouse turns the body and tilts the head as always, so
## the seat's limits, what others see and the menus' rays stay as they were): the camera hangs
## behind the vehicle's middle along that look, its distance from the vehicle's size, its
## height clamped (MIN/MAX_ELEVATION), and pulls in in front of terrain, voxel buildings and
## other vehicles (a sphere cast, like a spring arm) and eases back out. It follows the vehicle
## smoothly (FOLLOW_RATE) and ignores its pitch and roll. The local body and the vehicle are
## drawn (your own body's layer, LOCAL_ONLY_LAYER, is in this camera's mask; the first-person
## weapon is hidden while it's on). A gunner's rounds go where its crosshair is (aim_point,
## Vehicle.gun_direction), as Arma's third-person gunner. Client side only: nothing new is
## replicated.
##
## For the interiors (first-person seat views): FIRST_PERSON_DEFAULT makes first person the
## session's starting view once the hulls are hollow; `chase` is what PlayerInput reads.
## Numbers marked Proposed are tunable.

## The input action that switches the view while seated (Controls.KEYS, GameSettings.BINDABLE).
const ACTION := &"vehicle_view"
## Proposed: whether a session starts in first person. False until the vehicles have hollow
## interiors and windows to see out of (the chase view is the only usable one till then).
const FIRST_PERSON_DEFAULT := false
## Proposed: the arm's length, times the hull's diagonal (VehicleSpecs boxes), and its limits (m).
const DISTANCE_SCALE := 0.8
const DISTANCE_MIN := 5.0
const DISTANCE_MAX := 32.0
## Proposed: the pivot sits this far above the hull's top, plus this share of the arm's length.
const PIVOT_ABOVE_M := 0.6
const PIVOT_ARM_SHARE := 0.1
## Proposed: the arm's elevation follows the look's pitch within these (radians; negative: the
## camera above, looking down). Looking further up or down only tilts the camera.
const MIN_ELEVATION := -1.15
const MAX_ELEVATION := 0.3
## Proposed: how fast the pivot catches up with the vehicle (1/s), and how fast the arm eases
## back out after something pulled it in (m/s; it pulls in at once).
const FOLLOW_RATE := 14.0
const ARM_OUT_SPEED := 8.0
## Snap instead of following when the vehicle is this far from the pivot (a teleport, a respawn).
const SNAP_M := 25.0
## The camera stays this far off whatever the arm meets (the sphere cast's radius).
const ARM_RADIUS := 0.35
## What pulls the arm in: the world (terrain, voxel buildings) and other vehicles.
const ARM_MASK := 1 | Vehicle.LAYER
## How far the gunner's crosshair ray looks for something to aim at (m).
const AIM_RANGE := 1500.0
const AIM_MASK := 1 | Vehicle.LAYER | Soldier.BODY_LAYER
const NODE_NAME := &"VehicleCamera"

## The seated view this session: true the chase view, false first person (the vehicle view
## key flips it; it holds across seats, vehicles and levels until the game closes).
static var chase := not FIRST_PERSON_DEFAULT

var body: Soldier
## Whether this camera is the view now (seated with the chase view on).
var active := false
var _vehicle: Vehicle
var _pivot := Vector3.ZERO
var _arm := -1.0  # current arm length; -1: not placed yet (snap)
var _sphere := SphereShape3D.new()


func _init(p_body: Soldier = null) -> void:
	body = p_body
	name = NODE_NAME
	top_level = true
	process_priority = 100  # after the vehicles have moved this frame (and their occupants)
	_sphere.radius = ARM_RADIUS


## The chase camera of `s` (a local player), or null.
static func of(s: Node) -> VehicleCamera:
	return s.get_node_or_null(NodePath(NODE_NAME)) as VehicleCamera if is_instance_valid(s) else null


## The camera `s` sees through now: the chase camera when it's on, else their own.
static func view_of(s: Soldier) -> Camera3D:
	var cam := VehicleCamera.of(s)
	return cam if cam and cam.active else s.camera


## Flips the seated view for the session; returns the new one's name for the HUD.
static func toggle() -> String:
	chase = not chase
	return "Third person" if chase else "First person"


func _process(delta: float) -> void:
	follow(delta)


## Puts the camera where it belongs this frame and makes it (or the soldier's own) the view.
func follow(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_local():
		return
	var v := Vehicle.ride_of(body)
	var want := v != null and chase
	if not want:
		if active:
			active = false
			if current:
				body.camera.current = true
		_vehicle = null
		_arm = -1.0
		return
	if v != _vehicle:
		_vehicle = v
		_arm = -1.0
	place(delta)
	if not active:
		active = true
		current = true


## The vehicle's hull in its own frame: the union of its collision boxes (VehicleSpecs).
static func hull_box(v: Vehicle) -> AABB:
	var boxes: Array = v.spec.get("boxes", [])
	if boxes.is_empty():
		return AABB(Vector3(-1, 0, -2), Vector3(2, 2, 4))
	var out := VehicleSpecs.box(boxes[0])
	for b: Array in boxes:
		out = out.merge(VehicleSpecs.box(b))
	return out


## How far the camera hangs behind the vehicle's middle, unobstructed (m).
static func arm_length(v: Vehicle) -> float:
	return clampf(hull_box(v).size.length() * DISTANCE_SCALE, DISTANCE_MIN, DISTANCE_MAX)


## Where the arm hangs from: above the hull's middle (world).
static func pivot_of(v: Vehicle) -> Vector3:
	var box := hull_box(v)
	var top := box.get_center() + Vector3(0, box.size.y * 0.5, 0)
	var lift := PIVOT_ABOVE_M + arm_length(v) * PIVOT_ARM_SHARE
	return v.global_transform * Vector3(top.x, top.y, top.z) + Vector3.UP * lift


## The look the camera follows: the soldier's own view (yaw, pitch).
func look_angles() -> Vector2:
	var f := -body.camera.global_basis.z
	return Vector2(atan2(-f.x, -f.z), asin(clampf(f.y, -1.0, 1.0)))


func place(delta: float) -> void:
	var v := _vehicle
	var target := pivot_of(v)
	# Under a roof, a bridge or an overhang: the pivot comes down below it, so the arm never
	# starts inside something.
	var base := v.global_transform * hull_box(v).get_center()
	target = base + (target - base) * _clear_share(base, target - base, v)
	if _arm < 0.0 or _pivot.distance_to(target) > SNAP_M:
		_pivot = target
	else:
		_pivot = _pivot.lerp(target, 1.0 - exp(-FOLLOW_RATE * delta))
	var look := look_angles()
	var elevation := clampf(look.y, MIN_ELEVATION, MAX_ELEVATION)
	var back := Basis.from_euler(Vector3(elevation, look.x, 0.0)) * Vector3.BACK
	var full := arm_length(v)
	var free := full * _clear_share(_pivot, back * full, v)
	if _arm < 0.0 or free < _arm:
		_arm = free  # something in the way: pull in at once
	else:
		_arm = move_toward(_arm, free, ARM_OUT_SPEED * delta)
	global_transform = Transform3D(Basis.from_euler(Vector3(look.y, look.x, 0.0)), _pivot + back * _arm)
	fov = body.camera.fov  # aiming zooms here too
	far = body.camera.far


## How much of `motion` from `from` a sphere travels before it meets terrain, a building or
## another vehicle (0..1).
func _clear_share(from: Vector3, motion: Vector3, v: Vehicle) -> float:
	var space := v.get_world_3d().direct_space_state if v.is_inside_tree() else null
	if space == null:
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis(), from)
	q.motion = motion
	q.collision_mask = ARM_MASK
	var exclude: Array[RID] = [v.get_rid(), body.get_rid()]
	q.exclude = exclude
	var r := space.cast_motion(q)
	return r[0] if r.size() > 0 else 1.0


## Where this camera's crosshair falls: the first thing ahead past the vehicle's middle (the
## world, a vehicle, a body), or AIM_RANGE out.
func aim_point() -> Vector3:
	var fwd := -global_basis.z
	var from := global_position + fwd * maxf(0.0, (_pivot - global_position).dot(fwd))
	var to := from + fwd * AIM_RANGE
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return to
	var exclude: Array[RID] = [body.get_rid()]
	if _vehicle:
		exclude.append(_vehicle.get_rid())
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, AIM_MASK, exclude))
	return hit.position if not hit.is_empty() else to
