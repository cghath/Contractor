class_name SoldierMovement
extends Node
## How a Soldier body moves and stands: walking with momentum, sprinting and stamina,
## jumping, crawling while down, stances (three standing heights, three crouching, prone,
## each with side stances), leaning, mounting the weapon on a surface, the settle sway after
## a stop, and the speed costs of load, aiming and carrying.
##
## Humans steer it with the keyboard (read here, on the owning peer); AI through the body's
## intent fields (move_input, want_sprint, want_crouch, want_stance), written by SquadAI on
## the host. `stance`, `side`, `lean` and `mounted` replicate through the body's Sync, so
## every peer poses the model, the hitboxes and the movement capsule the same way
## (apply_pose, called by the body every frame).
##
## Values marked "proposed" in the design doc are the constants below; tune them freely.

enum Stance { PRONE, CROUCH_LOW, CROUCH_MID, CROUCH_HIGH, STAND_LOW, STAND_MID, STAND_HIGH }

const WALK_SPEED := 4.0      # a jog: the normal standing pace
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const PRONE_SPEED := 0.8     # crawling
const CRAWL_SPEED := 0.6     # downed
const JUMP_VELOCITY := 4.2
const STAND_HEAD_Y := 1.65
const CROUCH_HEAD_Y := 1.0
const DOWNED_HEAD_Y := 0.35
const ADS_SPEED_MULT := 0.6

## Per stance, indexed by Stance (proposed values):
## eye height in metres (prone takes its height from the lying pose instead),
const STANCE_EYE: Array[float] = [0.3, 0.85, CROUCH_HEAD_Y, 1.15, 1.35, 1.5, STAND_HEAD_Y]
## upper-body lean in radians (negative leans forward; prone: chest raised),
const STANCE_PITCH: Array[float] = [0.2, -0.55, -0.4, -0.3, -0.3, -0.15, 0.0]
## top speed in m/s,
const STANCE_SPEED: Array[float] = [PRONE_SPEED, 1.6, CROUCH_SPEED, 2.4, 3.0, 3.5, WALK_SPEED]
## movement capsule height in metres (prone uses a capsule lying down),
const STANCE_CAPSULE: Array[float] = [0.0, 1.1, 1.25, 1.4, 1.55, 1.7, 1.8]
## and weapon spread (sway) and recoil multipliers.
const STANCE_SPREAD: Array[float] = [0.5, 0.65, 0.7, 0.75, 0.9, 0.95, 1.0]
const STANCE_RECOIL: Array[float] = [0.7, 0.85, 0.85, 0.9, 1.0, 1.0, 1.0]
const CAPSULE_RADIUS := 0.3
## Lying capsule (prone and downed): radius, length, and centre along the body (z).
const LYING_RADIUS := 0.25
const LYING_LENGTH := 1.6
const PRONE_CAPSULE_Z := 0.05
const DOWNED_CAPSULE_Z := -0.85     # a downed body lies forward of its feet
## Headroom check before standing taller: shrink the test capsule by this much.
const ROOM_MARGIN := 0.05
const WORLD_MASK := 1

## Side stances (Caps Lock + A/D): hips shift and the upper body tilts out; prone rolls
## onto a side. Slower to move in.
const SIDE_HIP_SHIFT := 0.12
const SIDE_ROLL := 0.3
const PRONE_SIDE_ROLL := 1.0
const SIDE_SPEED_MULT := 0.75
## Lean (Q/E): upper-body tilt at full lean (about 0.3 m of head offset standing); prone
## leans swing the shoulders sideways instead.
const LEAN_ROLL := 0.41
const PRONE_LEAN_ROLL := 0.3
const LEAN_RATE := 5.0              # full lean in 0.2 s
const LEAN_MARGIN := 0.15           # keep the head this far off walls
const DOUBLE_TAP_S := 0.3
## The camera rolls this fraction of the upper body's tilt.
const CAMERA_ROLL := 0.5
const CAMERA_PRONE_ROLL := 0.25
const HEAD_SPEED := 4.0             # m/s the camera moves between stances
const ROLL_SPEED := 2.0             # rad/s
## Crouched, the hips go back so the eyes stay at most this far ahead of the body's centre
## (keeps the camera inside the capsule, out of walls).
const EYE_FORWARD := 0.1

## Momentum (proposed): an unloaded soldier reaches a jog in ACCEL_TIME and stops from one
## in STOP_TIME; a full load adds HEAVY_TIME_MULT times as much (roughly doubles both).
const ACCEL_TIME := 0.3
const STOP_TIME := 0.3
const HEAVY_TIME_MULT := 1.0
const AIR_CONTROL := 0.3
## Settle sway after a stop: speed lost (m/s) builds it up to 1, then it fades.
const SETTLE_GAIN := 0.25
const SETTLE_DECAY := 1.4           # per second
const SETTLE_SPREAD := 0.6          # spread x1.6 right after a hard stop
const SETTLE_SWAY_RAD := 0.035      # view-model sway at full settle

## Stamina (0..1): seconds of sprint from full, unloaded (a full load drains it
## HEAVY_STAMINA_MULT times faster again), and seconds to refill from empty standing still
## (half speed on the move), scaled by Vitals.stamina_mult(). Once empty, no sprint until
## it is back to STAMINA_RESUME.
const SPRINT_STAMINA_S := 15.0
const HEAVY_STAMINA_MULT := 1.0
const STAMINA_REGEN_S := 10.0
const STAMINA_REGEN_MOVING := 0.5
const STAMINA_RESUME := 0.2

## Weapon mount (C): a surface ahead at weapon height, or just under the muzzle (a sill,
## a wall top, the ground when prone). Halves sway and recoil (proposed).
const MOUNT_SWAY_MULT := 0.5
const MOUNT_RECOIL_MULT := 0.5
const WEAPON_BELOW_EYE := 0.12
const MOUNT_REACH := 0.75
const MOUNT_REST_AHEAD := 0.45
const MOUNT_REST_DROP := 0.3
const MOUNT_MAX_SPEED := 0.4

@onready var body: Soldier = get_parent()

## Replicated (owner-driven). One of Stance.
var stance: int = Stance.STAND_HIGH
## Replicated: -1 side stance left, 0 none, 1 right.
var side := 0
## Replicated: -1 (full lean left) to 1 (right), eased and kept off walls by the owner.
var lean := 0.0
## Replicated: weapon rested on a surface.
var mounted := false
## Owner-side: 0..1, drained by sprinting.
var stamina := 1.0
var is_sprinting := false
## Owner-side: 0..1, weapon sway left over from stopping.
var settle := 0.0

var _winded := false
var _before_prone: int = Stance.STAND_HIGH
var _lean_held := 0       # the lean key held now
var _lean_latched := 0    # double-tapped: stays leaned
var _lean_last_tap := {-1: -10.0, 1: -10.0}
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _shape_key := -99


func _ready() -> void:
	_collision = body.get_node(^"Collision")
	_capsule = _collision.shape.duplicate()  # every body resizes its own
	_collision.shape = _capsule


## One physics step for the body's owner (the human's peer, or the host for AI).
func step(delta: float) -> void:
	if not body.is_on_floor():
		body.velocity += body.get_gravity() * delta
	var down := not body.vitals.is_up()
	var burdened := body.inventory.hands != &"" or body.carry_speed_mult() < 1.0  # carry_mode reaches the owner; carrying is host-only
	var input := Vector2.ZERO
	var sprint := false
	if down:
		_lean_held = 0
		_lean_latched = 0
		mounted = false
		if not body.is_ai() and _captured():
			input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	elif body.is_ai():
		var want: int = body.want_stance if body.want_stance >= 0 else (Stance.CROUCH_MID if body.want_crouch else Stance.STAND_HIGH)
		if want != stance:
			set_stance(want)
		input = body.move_input.limit_length(1.0)
		sprint = body.want_sprint
	elif _captured():
		var adjusting := Input.is_action_pressed(&"stance_adjust")
		_read_keys(adjusting)
		if not adjusting:  # Caps Lock + WASD changes stance instead of moving
			input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		sprint = Input.is_action_pressed(&"sprint")
		if Input.is_action_just_pressed(&"jump") and can_jump():
			body.velocity.y = JUMP_VELOCITY
			mounted = false
	else:
		_lean_held = 0  # keys released while the mouse was free
	is_sprinting = sprint and input != Vector2.ZERO and not down and not burdened and is_standing() and can_sprint()
	if is_sprinting and (stance != Stance.STAND_HIGH or side != 0):
		side = 0
		set_stance(Stance.STAND_HIGH)
	update_stamina(delta, is_sprinting, input != Vector2.ZERO)
	var target := (body.global_basis * Vector3(input.x, 0.0, input.y)).normalized() * top_speed(is_sprinting, down)
	var before := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var after := next_velocity(before, target, delta, body.is_on_floor())
	body.velocity.x = after.x
	body.velocity.z = after.z
	body.move_and_slide()
	if target.length() < before.length():
		settle = minf(settle + maxf(before.length() - after.length(), 0.0) * SETTLE_GAIN, 1.0)
	settle = move_toward(settle, 0.0, delta * SETTLE_DECAY)
	if mounted and (input != Vector2.ZERO or after.length() > MOUNT_MAX_SPEED or not body.is_on_floor() or not _has_weapon_up()):
		mounted = false
	update_pose(delta)


## Owner-side: eases the lean and moves the camera (head) to the stance's eye point.
func update_pose(delta: float) -> void:
	update_lean(delta)
	_update_head(delta, not body.vitals.is_up())


## Every peer, every frame (from the body): the model, hitbox pose and capsule follow the
## replicated stance.
func apply_pose() -> void:
	body.model.pose = pose_for(stance, side, lean)
	var key := -1 if not body.vitals.is_up() else stance
	if key == _shape_key:
		return
	_shape_key = key
	if key == -1 or key == Stance.PRONE:
		_capsule.radius = LYING_RADIUS
		_capsule.height = LYING_LENGTH
		_collision.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2),
			Vector3(0, LYING_RADIUS, DOWNED_CAPSULE_Z if key == -1 else PRONE_CAPSULE_Z))
	else:
		_capsule.radius = CAPSULE_RADIUS
		_capsule.height = STANCE_CAPSULE[key]
		_collision.transform = Transform3D(Basis(), Vector3(0, STANCE_CAPSULE[key] * 0.5, 0))


## The body pose (CharacterModel.REST_POSE keys) for a stance, side stance and lean.
static func pose_for(for_stance: int, for_side: int, for_lean: float) -> Dictionary:
	var pitch := STANCE_PITCH[for_stance]
	if for_stance == Stance.PRONE:
		return {"hip": CharacterModel.LEG_LENGTH, "hip_x": 0.0, "hip_z": 0.0, "pitch": pitch,
			"roll": -for_lean * PRONE_LEAN_ROLL, "prone": true, "prone_roll": -for_side * PRONE_SIDE_ROLL}
	var eye_up := CharacterModel.EYE.y
	return {"hip": STANCE_EYE[for_stance] - eye_up * cos(pitch), "hip_x": for_side * SIDE_HIP_SHIFT,
		"hip_z": maxf(eye_up * sin(-pitch) - EYE_FORWARD, 0.0), "pitch": pitch,
		"roll": -for_side * SIDE_ROLL - for_lean * LEAN_ROLL, "prone": false, "prone_roll": 0.0}


# --- Stance ------------------------------------------------------------------------------

## Crouched or prone (low enough to aim lower at, and steadier).
func is_crouching() -> bool:
	return stance <= Stance.CROUCH_HIGH


func is_crouched() -> bool:
	return stance >= Stance.CROUCH_LOW and stance <= Stance.CROUCH_HIGH


func is_standing() -> bool:
	return stance >= Stance.STAND_LOW


func is_prone() -> bool:
	return stance == Stance.PRONE


## Jumping only from a standing stance, on the ground, hands free and not down.
func can_jump() -> bool:
	return is_standing() and body.is_on_floor() and body.vitals.is_up() \
		and body.inventory.hands == &"" and body.carry_speed_mult() >= 1.0


## Changes stance if there's room (a taller stance needs headroom). Unmounts the weapon.
## Returns whether the body is now in that stance.
func set_stance(new_stance: int) -> bool:
	new_stance = clampi(new_stance, Stance.PRONE, Stance.STAND_HIGH)
	if new_stance == stance:
		return true
	if new_stance > stance and not has_room(new_stance):
		return false
	if new_stance == Stance.PRONE:
		_before_prone = stance
	stance = new_stance
	mounted = false
	return true


## X: crouch, or stand up from a crouch.
func toggle_crouch() -> bool:
	return set_stance(Stance.STAND_HIGH if is_crouched() else Stance.CROUCH_MID)


## Z: go prone, or back to the stance you went prone from.
func toggle_prone() -> bool:
	return set_stance(_before_prone if is_prone() else Stance.PRONE)


## Caps Lock + W/S: one step up or down (prone, three crouching, three standing heights).
func step_stance(direction: int) -> bool:
	return set_stance(stance + direction)


## Caps Lock + A/D: move the side stance one step left (-1) or right (1).
func shift_side(direction: int) -> void:
	var new_side := clampi(side + direction, -1, 1)
	if new_side != side:
		side = new_side
		mounted = false


## Whether a standing or crouching capsule for `for_stance` fits here (world only).
func has_room(for_stance: int) -> bool:
	if for_stance == Stance.PRONE or not body.is_inside_tree():
		return true
	var height: float = STANCE_CAPSULE[for_stance] - ROOM_MARGIN * 2.0
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS - ROOM_MARGIN
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = body.global_transform * Transform3D(Basis(), Vector3(0, ROOM_MARGIN * 2.0 + height * 0.5, 0))
	query.collision_mask = WORLD_MASK
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Lean --------------------------------------------------------------------------------

## A lean key went down (-1 left, 1 right): lean while held; a double-tap stays leaned,
## and another tap returns.
func press_lean(direction: int) -> void:
	var now := Soldier._now()
	if _lean_latched == direction:
		_lean_latched = 0
		_lean_last_tap[direction] = -10.0
		return
	_lean_latched = 0
	if now - float(_lean_last_tap[direction]) <= DOUBLE_TAP_S:
		_lean_latched = direction
	_lean_last_tap[direction] = now
	_lean_held = direction


## A lean key came up: stop the held lean (a latched one stays).
func release_lean(direction: int) -> void:
	if _lean_held == direction:
		_lean_held = 0


## The way the body is trying to lean: -1, 0 or 1.
func lean_target() -> int:
	return _lean_held if _lean_held != 0 else _lean_latched


## Owner-side: eases `lean` towards the held or latched lean, as far as walls allow.
func update_lean(delta: float) -> void:
	var target := 0.0
	if body.vitals.is_up() and not is_sprinting and lean_target() != 0:
		target = lean_target() * _lean_room(lean_target())
	lean = move_toward(lean, target, delta * LEAN_RATE)


## Fraction of a full lean that fits before the head would meet a wall.
func _lean_room(direction: int) -> float:
	if not body.is_inside_tree():
		return 1.0
	var from := body.global_transform * CharacterModel.eye_position(pose_for(stance, side, 0.0))
	var to := body.global_transform * CharacterModel.eye_position(pose_for(stance, side, direction))
	var reach := from.distance_to(to)
	if reach < 0.01:
		return 1.0
	var dir := (to - from) / reach
	var query := PhysicsRayQueryParameters3D.create(from, to + dir * LEAN_MARGIN, WORLD_MASK, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return clampf((from.distance_to(hit.position) - LEAN_MARGIN) / reach, 0.0, 1.0)


func _update_head(delta: float, down: bool) -> void:
	var target := Vector3(0, DOWNED_HEAD_Y, 0)
	var roll := 0.0
	if not down:
		var pose := pose_for(stance, side, lean)
		target = CharacterModel.eye_position(pose)
		roll = pose.roll * CAMERA_ROLL if not pose.prone else pose.prone_roll * CAMERA_PRONE_ROLL - lean * 0.1
	body.head.position = body.head.position.move_toward(target, HEAD_SPEED * delta)
	body.head.rotation.z = move_toward(body.head.rotation.z, roll, ROLL_SPEED * delta)


# --- Mount -------------------------------------------------------------------------------

## C: rest the weapon on a surface in front, or take it off. Returns whether it's mounted.
func toggle_mount() -> bool:
	mounted = false if mounted else can_mount()
	return mounted


func can_mount() -> bool:
	if not _has_weapon_up() or Vector2(body.velocity.x, body.velocity.z).length() > MOUNT_MAX_SPEED:
		return false
	return has_mount_surface()


## A surface ahead at weapon height, or just under the muzzle.
func has_mount_surface() -> bool:
	var space := body.get_world_3d().direct_space_state
	var forward := -body.global_basis.z
	var from := body.head.global_position + Vector3.DOWN * WEAPON_BELOW_EYE
	var ahead := PhysicsRayQueryParameters3D.create(from, from + forward * MOUNT_REACH, WORLD_MASK, [body.get_rid()])
	if not space.intersect_ray(ahead).is_empty():
		return true
	var over := from + forward * MOUNT_REST_AHEAD
	var below := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * MOUNT_REST_DROP, WORLD_MASK, [body.get_rid()])
	return not space.intersect_ray(below).is_empty()


func _has_weapon_up() -> bool:
	var weapon := body.active_weapon()
	return body.vitals.is_up() and weapon != null and weapon.type == "weapon" and body.inventory.hands == &""


# --- Speed, momentum, stamina, sway ------------------------------------------------------

## Top speed right now, before momentum.
func top_speed(sprinting: bool, down: bool) -> float:
	var speed := STANCE_SPEED[stance]
	if side != 0:
		speed *= SIDE_SPEED_MULT
	if sprinting:
		speed = SPRINT_SPEED
	if body.is_aiming:
		speed = minf(speed, WALK_SPEED) * ADS_SPEED_MULT
	if down:
		speed = CRAWL_SPEED
	return speed * body.load_mult * body.vitals.speed_mult() * body.carry_speed_mult()


## 0 (light) to 1 (a full load, a bulky item or a body on your shoulder counts too).
func load_fraction() -> float:
	return clampf((1.0 - body.load_mult * body.carry_speed_mult()) / (1.0 - Soldier.MIN_LOAD_MULT), 0.0, 1.0)


## Horizontal velocity after one step towards `target`: the body speeds up and slows down
## over ACCEL_TIME / STOP_TIME (longer under load), so momentum carries into turns and
## stance changes.
func next_velocity(current: Vector3, target: Vector3, delta: float, on_floor := true) -> Vector3:
	var time := ACCEL_TIME if target.length() >= current.length() - 0.001 else STOP_TIME
	var rate := WALK_SPEED / (time * (1.0 + HEAVY_TIME_MULT * load_fraction()))
	if not on_floor:
		rate *= AIR_CONTROL
	return current.move_toward(target, rate * delta)


func can_sprint() -> bool:
	return not _winded and stamina > 0.0 and body.vitals.can_sprint()


## Sprinting drains stamina (faster under load); otherwise it comes back.
func update_stamina(delta: float, sprinting: bool, moving: bool) -> void:
	if sprinting:
		stamina -= delta / SPRINT_STAMINA_S * (1.0 + HEAVY_STAMINA_MULT * load_fraction())
		if stamina <= 0.0:
			_winded = true
	else:
		stamina += delta / STAMINA_REGEN_S * body.vitals.stamina_mult() * (STAMINA_REGEN_MOVING if moving else 1.0)
		if stamina >= STAMINA_RESUME:
			_winded = false
	stamina = clampf(stamina, 0.0, 1.0)


## Weapon spread multiplier (the game's sway): stance, mount, and the settle after a stop.
func spread_mult() -> float:
	return STANCE_SPREAD[stance] * (MOUNT_SWAY_MULT if mounted else 1.0) * (1.0 + SETTLE_SPREAD * settle)


func recoil_mult() -> float:
	return STANCE_RECOIL[stance] * (MOUNT_RECOIL_MULT if mounted else 1.0)


## View-model sway (yaw, roll in radians) left over from stopping.
func weapon_sway() -> Vector2:
	var t := Soldier._now()
	return Vector2(sin(t * 7.0), sin(t * 5.3 + 1.0)) * settle * SETTLE_SWAY_RAD * (MOUNT_SWAY_MULT if mounted else 1.0)


# --- Keys (human owner) ------------------------------------------------------------------

func _read_keys(adjusting: bool) -> void:
	if Input.is_action_just_pressed(&"crouch"):
		toggle_crouch()
	if Input.is_action_just_pressed(&"prone"):
		toggle_prone()
	if adjusting:
		if Input.is_action_just_pressed(&"move_forward"):
			step_stance(1)
		if Input.is_action_just_pressed(&"move_back"):
			step_stance(-1)
		if Input.is_action_just_pressed(&"move_left"):
			shift_side(-1)
		if Input.is_action_just_pressed(&"move_right"):
			shift_side(1)
	for direction: int in [-1, 1]:
		var action := &"lean_left" if direction < 0 else &"lean_right"
		if Input.is_action_just_pressed(action):
			press_lean(direction)
		elif not Input.is_action_pressed(action):
			release_lean(direction)
	if Input.is_action_just_pressed(&"mount"):
		var was_mounted := mounted
		if toggle_mount():
			body.player_input.flash("Weapon rested")
		elif not was_mounted and _has_weapon_up():
			body.player_input.flash("Nothing to rest the weapon on")


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
