class_name SoldierMovement
extends Node
## How a Soldier body moves and stands: walking with momentum, sprinting and stamina,
## jumping, stances (three standing heights, three crouching, prone,
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
## Load tiers, directional speeds, the sprint ramp, arm stamina, holding the breath and ADS
## time (movement phase 1) take their numbers from MovementRules, with their sources.

enum Stance { PRONE, CROUCH_LOW, CROUCH_MID, CROUCH_HIGH, STAND_LOW, STAND_MID, STAND_HIGH }

const WALK_SPEED := 4.0      # a jog: the normal standing pace
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const PRONE_SPEED := 0.8     # crawling
const CRAWL_SPEED := 0.6     # a body moving while down (nothing moves one now; kept for the speed table)
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
## What a standing (or crouching, or prone) body's capsule meets: the world, other soldiers,
## bodies lying as ragdolls and vehicles' hulls (wave 5: Vehicle.LAYER).
const UP_MASK := WORLD_MASK | Soldier.BODY_LAYER | Ragdoll.LAYER | Vehicle.LAYER
## Proposed: a lying body (or a pile) up to this high above the feet is stepped over, rising
## at this speed (m/s).
const BODY_STEP_M := 0.75
const BODY_CLIMB_SPEED := 2.4
## Proposed: a step up onto a body clears the contact by this much, and moves on at least
## this far (so a slow walk still gets its feet past the edge).
const BODY_STEP_MARGIN := 0.04
const BODY_STEP_AHEAD_M := 0.05
## A step of the world (a stair's, a kerb) up to this high is stepped up the same way, from the
## floor: the capsule's round bottom met a 0.2 m stair step as a wall (F-01: nobody got upstairs).
## Under the capsule's radius, so a wall's foot (met at the radius) never counts.
const WORLD_STEP_M := 0.27

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
## (or from a sprint) in about STOP_TIME; drift across the way it now wants to go (the old
## heading after a turn) is shed in GRIP_TIME. A full load adds HEAVY_TIME_MULT times as
## much to all three (roughly doubles them).
const ACCEL_TIME := 0.3
const STOP_TIME := 0.2
const GRIP_TIME := 0.1
## AI soldiers keep the older, looser momentum (a plain ease towards the wanted velocity, braking
## over AI_STOP_TIME): their path following leans on sliding round corners, and the tight grip
## left them stuck on door frames. The grip is for the player's feel.
const AI_STOP_TIME := 0.3
const HEAVY_TIME_MULT := 1.0
const AIR_CONTROL := 0.3
## Settle sway after a stop: speed lost (m/s) builds it up to 1, then it fades.
const SETTLE_GAIN := 0.25
const SETTLE_DECAY := 1.4           # per second
const SETTLE_SPREAD := 0.6          # spread x1.6 right after a hard stop
const SETTLE_SWAY_RAD := 0.035      # view-model sway at full settle

## Stamina (0..1): seconds of sprint from full, unloaded (a load drains it faster by its
## tier: MovementRules.TIER_DRAIN), and seconds to refill from empty standing still (half
## speed on the move, faster crouched or prone: MovementRules.REGEN_*), scaled by
## Vitals.stamina_mult(). Once empty, no sprint or jump until it is back to STAMINA_RESUME.
const SPRINT_STAMINA_S := 15.0
const STAMINA_REGEN_S := 10.0
const STAMINA_REGEN_MOVING := 0.5
const STAMINA_RESUME := 0.2
## Moving with load_fraction() at or over this counts as exertion (surgery kit reopening).
const EXTREME_LOAD := 0.9
## A height change this big in one physics step is the game moving the body, not a fall.
const TELEPORT_M := 2.0

## Weapon mount (C): a surface ahead at weapon height, or just under the muzzle (a sill,
## a wall top, the ground when prone). Halves sway and recoil (proposed).
const MOUNT_SWAY_MULT := 0.5
const MOUNT_RECOIL_MULT := 0.5
const WEAPON_BELOW_EYE := 0.12
const MOUNT_REACH := 0.75
const MOUNT_REST_AHEAD := 0.45
const MOUNT_REST_DROP := 0.3
const MOUNT_MAX_SPEED := 0.4

## Mantle (Captain, 2026-10-16: "now is a good time to put mantle in the game"): the jump key,
## facing a ledge, climbs up and over it instead of jumping. A ledge is a wall ahead within
## MANTLE_REACH_M whose top (a walkable surface: the world or a vehicle's hull, never a soldier)
## is MANTLE_MIN_M..the load's limit above the feet, with room for the body on top. Under
## MANTLE_MIN_M the step-ups and a jump do it. Heavier loads reach lower (MANTLE_MAX_M light or
## burdened, MANTLE_MAX_OVERLOADED_M overloaded, none critical, as jumping), and it costs leg
## stamina by height (a jump's cost x MANTLE_STAMINA_PER_M x the height). Up straight, then
## onto the top, crouched (it stands up after if there's room); the weapon lowers and nothing
## fires on the way. Proposed numbers.
const MANTLE_MIN_M := 0.45
const MANTLE_MAX_M := 1.9
const MANTLE_MAX_OVERLOADED_M := 1.2
const MANTLE_REACH_M := 0.75
const MANTLE_ONTO_M := 0.45
const MANTLE_BASE_S := 0.35
const MANTLE_PER_M_S := 0.4
const MANTLE_STAMINA_PER_M := 1.2
## On the move (Captain, 2026-10-17: "matle needs to be more fluid, not just when youre standing
## still"): the ledge is looked for along the way it runs (when that's within MANTLE_RUN_DOT of
## its facing), MANTLE_LOOK_S of its speed further out; it can start up to MANTLE_COYOTE_S after
## leaving the ground (a jump into a wall), down to MANTLE_AIR_MIN_M above the feet then; the jump
## key counts for MANTLE_BUFFER_S (pressed a step early); the climb is quicker the faster it came
## (down to MANTLE_FAST of the time at MANTLE_FAST_MS), one curve rather than up-then-over, and it
## carries MANTLE_CARRY of its speed on over the top.
const MANTLE_RUN_DOT := 0.3
const MANTLE_LOOK_S := 0.2
const MANTLE_LOOK_MAX_M := 0.9
const MANTLE_COYOTE_S := 0.35
const MANTLE_AIR_MIN_M := 0.2
const MANTLE_BUFFER_S := 0.3
const MANTLE_FAST := 0.6
const MANTLE_FAST_MS := 6.0
const MANTLE_CARRY := 0.75
## The LX-3's leap (Captain, 2026-10-17: "make it so its a jump up there like i originally
## intended", "onto rooves to then clear down buildings, ergo we jump over the compound walls,
## not on top of them"): with a working exo frame the jump key at a ledge throws the body up in
## one arc, LEAP_BASE_S + LEAP_PER_M_S a metre, peaking LEAP_APEX_M over the top, instead of the
## climb. A wide top (a roof) it lands on; a wall (ground LEAP_DROP_M or more below the top
## within LEAP_OVER_M past its face) it clears, landing on the far side. Same reach, cost and
## checks as the mantle (find_ledge, can_mantle).
const LEAP_BASE_S := 0.3
const LEAP_PER_M_S := 0.06
const LEAP_OVER_S := 0.15
const LEAP_APEX_M := 0.6
const LEAP_OVER_M := 0.9
const LEAP_DROP_M := 0.9
const LEAP_LAND_M := 0.45
const MANTLE_MASK := WORLD_MASK | Vehicle.LAYER

@onready var body: Soldier = get_parent()

## Replicated (owner-driven). One of Stance.
var stance: int = Stance.STAND_HIGH
## Replicated: -1 side stance left, 0 none, 1 right.
var side := 0
## Replicated: -1 (full lean left) to 1 (right), eased and kept off walls by the owner.
var lean := 0.0
## Replicated: weapon rested on a surface.
var mounted := false
## Owner-side: 0..1, drained by sprinting and jumping (the legs).
var stamina := 1.0
var is_sprinting := false
## Owner-side: 0..1 of the way from a jog to full sprint speed (MovementRules.SPRINT_RAMP_S).
var sprint_ramp := 0.0
## Owner-side: 0..1, drained by holding a weapon up aimed, by its mass (MovementRules: arms).
var arm_stamina := 1.0
## Owner-side: holding the breath (the hold_breath key while aiming), steadying the aim.
var breath_held := false
## Owner-side: the breathing cycle (radians), quicker out of breath (Soldier.aim_sway).
var breath_phase := 0.0
var _breath_left := 0.0   # seconds of held breath left
var _gasp_left := 0.0     # seconds of gasping after a hold: no hold, more sway
var _hold_spent := false  # a hold ended with the key still down: let go before the next one
## Owner-side: 0..1, weapon sway left over from stopping.
var settle := 0.0

var _winded := false
var _exerting := false    # sprinting, jumping or moving under an extreme load (report_exertion)
var _air_top := -INF      # highest point since leaving the ground (_track_fall)
var _last_y := 0.0
var _slid_at := Vector3.ZERO  # where the last move_and_slide left the body (_slide)
var _before_prone: int = Stance.STAND_HIGH
var _lean_held := 0       # the lean key held now
var _lean_latched := 0    # double-tapped: stays leaned
var _lean_last_tap := {-1: -10.0, 1: -10.0}
## Owner-side: held this step because nothing is under the body (no_ground_below).
var holding := false
## Whether the last mantle was an LX-3 leap over a wall (landing on its far side).
var last_over := false
## Owner-side: climbing a ledge now (mantle): the step moves the body along the climb.
var mantling := false
var _mantle := {}  # "from", "up", "to", "t", "s", "stance", "carry", "dir"
var _floor_at := -1000.0  # when it was last on the ground (a mantle just after leaving it)
var _jump_buffer_until := -1000.0  # the jump key, pressed this long ago, still asks for a mantle
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _shape_key := -99


func _ready() -> void:
	_collision = body.get_node(^"Collision")
	_capsule = _collision.shape.duplicate()  # every body resizes its own
	_collision.shape = _capsule


## Whether nothing at all is under the body to land on (GroundGuard.floor_below), the body's
## own capsule aside. Only asked while it is off the floor.
func no_ground_below() -> bool:
	if not body.is_inside_tree():
		return false
	return not GroundGuard.floor_below(body.get_world_3d(), body.global_position, [body.get_rid()])


## One physics step for the body's owner (the human's peer, or the host for AI).
func step(delta: float) -> void:
	if not body.is_on_floor():
		if no_ground_below():
			# Captain, 2026-10-14 (falling out of the world): nothing under the body yet (a spawn,
			# respawn or level switch ahead of the ground under it, or past its edge): it waits
			# where it is, not falling, until there is (GroundGuard puts one past the edge back).
			body.velocity = Vector3.ZERO
			holding = true
			return
		body.velocity += body.get_gravity() * delta
	holding = false
	if body.is_on_floor():
		_floor_at = Soldier._now()
	var down := not body.vitals.is_up()
	if mantling:
		_mantle_step(delta, down)
		update_pose(delta)
		return
	if not down and not body.vitals.can_stand() and stance != Stance.PRONE:
		set_stance(Stance.PRONE)  # a broken pelvis: no standing, crawl (or be carried)
	var jumped := false
	var burdened := body.inventory.hands != &"" or body.carry_speed_mult() < 1.0  # carry_mode reaches the owner; carrying is host-only
	var input := Vector2.ZERO
	var sprint := false
	var hold := false
	if down:
		_lean_held = 0
		_lean_latched = 0
		mounted = false
		# Down means unconscious (Vitals): no moving at all until someone treats, drags or carries
		# them, or they come round (Captain, 2026-10-11: no crawling while down).
	elif body.is_ai():
		var want: int = body.want_stance if body.want_stance >= 0 else (Stance.CROUCH_MID if body.want_crouch else Stance.STAND_HIGH)
		if want != stance:
			set_stance(want)
		input = body.move_input.limit_length(1.0)
		sprint = body.want_sprint
		if body.want_mantle:  # SquadAI's climb order: the jump key's mantle
			body.want_mantle = false
			if try_mantle():
				update_pose(delta)
				return
	elif _captured():
		var adjusting := Input.is_action_pressed(&"stance_adjust")
		_read_keys(adjusting)
		if not adjusting:  # Caps Lock + WASD changes stance instead of moving
			input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if body.carry_mode == Soldier.DRAG:
			# Dragging, the view faces the casualty behind the body: keys move relative to the
			# view, and only away from the casualty (back) or to the sides, never onto it.
			input = Vector2(-input.x, minf(-input.y, 0.0))
		sprint = Input.is_action_pressed(&"sprint")
		hold = Input.is_action_pressed(&"hold_breath")
		if Input.is_action_just_pressed(&"jump"):
			_jump_buffer_until = Soldier._now() + MANTLE_BUFFER_S
			if try_mantle():
				update_pose(delta)
				return
			if can_jump():
				jump()
				jumped = true
		elif Soldier._now() < _jump_buffer_until and try_mantle():  # pressed a step early, or a jump into the wall
			_jump_buffer_until = -1000.0
			update_pose(delta)
			return
	else:
		_lean_held = 0  # keys released while the mouse was free
	# Sprint: forward only (MovementRules.SPRINT_ARC_DEG), never aimed (the sprint key aimed is
	# holding the breath by default), within the load tier (can_sprint).
	is_sprinting = sprint and MovementRules.sprint_direction_ok(input) and not body.is_aiming and not down and not burdened \
		and is_standing() and can_sprint()
	if is_sprinting and (stance != Stance.STAND_HIGH or side != 0):
		side = 0
		# Sprinting needs full height: no sprint (speed or stamina) where there's no room to
		# stand up (audit L4-02: under a low roof it used to sprint from a low stance).
		is_sprinting = set_stance(Stance.STAND_HIGH)
	var exerting := is_sprinting or jumped or (input != Vector2.ZERO and load_fraction() >= EXTREME_LOAD)
	if exerting and not _exerting:
		body.report_exertion()  # a surgically closed chest wound may reopen
	_exerting = exerting
	update_stamina(delta, is_sprinting, input != Vector2.ZERO)
	update_arms(delta, body.is_aiming and not down, hold and not down)
	sprint_ramp = minf(sprint_ramp + delta / MovementRules.SPRINT_RAMP_S, 1.0) if is_sprinting else 0.0
	var target := (body.global_basis * Vector3(input.x, 0.0, input.y)).normalized() * top_speed(is_sprinting, down, input)
	var before := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var after := next_velocity(before, target, delta, body.is_on_floor(), not body.is_ai())
	body.velocity.x = after.x
	body.velocity.z = after.z
	_slide()
	if not down and target != Vector3.ZERO:
		_climb_bodies(Vector3(after.x, 0.0, after.z), delta)
	_track_fall()
	if target.length() < before.length():
		settle = minf(settle + maxf(before.length() - after.length(), 0.0) * SETTLE_GAIN, 1.0)
	settle = move_toward(settle, 0.0, delta * SETTLE_DECAY)
	if mounted and (input != Vector2.ZERO or after.length() > MOUNT_MAX_SPEED or not body.is_on_floor() or not _has_weapon_up()):
		mounted = false
	update_pose(delta)


## move_and_slide, without the floor it stood on when the game has moved the body since its
## last step (placed, respawned, out of a seat, put back on the ground: more than TELEPORT_M).
## The body keeps that floor as its platform and move_and_slide takes the platform's velocity
## at the body's new spot: its spin times the distance moved, which a ragdoll's limb still
## turning a little turns into a launch (CI run 38666966001: the loop's player, stood on a
## dead guard's forearm, put at a landing zone 1 km off, went up at 1360 m/s, 1420 m high a
## moment later). For that one step no platform counts (platform layers 0): no carry, no
## velocity added on leaving it; the step finds the floor under the new spot.
func _slide() -> void:
	var moved := body.global_position.distance_to(_slid_at) > TELEPORT_M
	var floor_layers := body.platform_floor_layers
	var wall_layers := body.platform_wall_layers
	if moved:
		body.platform_floor_layers = 0
		body.platform_wall_layers = 0
	body.move_and_slide()
	if moved:
		body.platform_floor_layers = floor_layers
		body.platform_wall_layers = wall_layers
	_slid_at = body.global_position


## Owner-side: the highest point since leaving the ground; on landing, a drop of
## WoundModel.FALL_SAFE_M or more goes to the host (Soldier.report_fall).
func _track_fall() -> void:
	var y := body.global_position.y
	if absf(y - _last_y) > TELEPORT_M:
		_air_top = -INF  # moved by the game (respawn, placed), not by falling
	_last_y = y
	if not body.is_on_floor():
		_air_top = y if is_inf(_air_top) else maxf(_air_top, y)
		return
	var drop := (_air_top - y) * fall_scale() if not is_inf(_air_top) else 0.0
	if drop >= WoundModel.FALL_SAFE_M:
		body.report_fall(drop)
	_air_top = -INF


## How much worse a drop lands than its height: overloaded, a 1.75 m drop counts as the safe
## 3 m (MovementRules.OVERLOADED_FALL_SAFE_M).
func fall_scale() -> float:
	if body.load_tier() >= MovementRules.Tier.OVERLOADED:
		return WoundModel.FALL_SAFE_M / MovementRules.OVERLOADED_FALL_SAFE_M
	return 1.0


## Owner-side: eases the lean and moves the camera (head) to the stance's eye point.
func update_pose(delta: float) -> void:
	update_lean(delta)
	_update_head(delta, not body.vitals.is_up())


## Walking into a body lying on the ground (a ragdoll part, Ragdoll) low enough to step on:
## up and over it, as over a pile, instead of stopping or passing through. A stair step: up
## by the contact's height, then on by this step's move, when both are clear. (Only lifting
## the velocity, as before, stuck soldiers at a pile's edge: the bump had stopped them and in
## the air they had AIR_CONTROL to get going again, so they hopped in place; R0142.)
## A step of the world up to WORLD_STEP_M (a stair's) the same way, from the floor.
## `motion`: the horizontal velocity this step wanted, over `delta` seconds.
func _climb_bodies(motion: Vector3, delta: float) -> void:
	var feet := body.global_position.y
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var rise := hit.get_position().y - feet
		var lying := Ragdoll.body_of(hit.get_collider()) != null
		if not lying and (rise >= WORLD_STEP_M or rise < 0.02 or not body.is_on_floor() or not _is_world(hit.get_collider())):
			continue  # not a body, and no stair step either
		if rise >= BODY_STEP_M or hit.get_normal().y >= 0.7:
			continue
		var up := Vector3(0.0, minf(rise + BODY_STEP_MARGIN, BODY_STEP_M), 0.0)
		var ahead := motion * delta
		if ahead.length() < BODY_STEP_AHEAD_M:
			ahead = motion.normalized() * BODY_STEP_AHEAD_M
		var from := body.global_transform
		if not body.test_move(from, up) and not body.test_move(from.translated(up), ahead):
			body.global_position += up + ahead
			body.velocity.x = motion.x  # the bump doesn't cost the walk its speed
			body.velocity.z = motion.z
			body.velocity.y = maxf(body.velocity.y, 0.0)
		elif lying:
			body.velocity.y = maxf(body.velocity.y, BODY_CLIMB_SPEED)  # no room: try a hop
		else:
			continue  # no room over that step: another contact may still be one
		return


## Whether `collider` is the world standing still (voxels, the ground, a static body), not a
## soldier or a vehicle.
static func _is_world(collider: Object) -> bool:
	return collider != null and (not collider is PhysicsBody3D or collider is StaticBody3D)


## Every peer, every frame (from the body): the model, hitbox pose and capsule follow the
## replicated stance.
func apply_pose() -> void:
	# Seated in a vehicle the seat poses the body (Vehicle._place_occupants); the stance still
	# sets the eye and the capsule.
	var seated := not body.seat_pose.is_empty() and is_instance_valid(body.vehicle)
	body.model.pose = body.seat_pose if seated else pose_for(stance, side, lean)
	var key := -1 if not body.vitals.is_up() else stance
	if key == _shape_key:
		return
	_shape_key = key
	# A downed or dead body's capsule only meets the world: other bodies can't shove it (its
	# own move_and_slide pushed it out of anyone who walked into it); lying bodies meet each
	# other as ragdolls (Ragdoll). The living meet bodies lying there too, and step over them.
	body.collision_mask = WORLD_MASK if key == -1 else UP_MASK
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


## Jumping only from a standing stance, on the ground, hands free, not down, not critically
## loaded (MovementRules.can_jump_at), with the legs for it (jump_cost).
func can_jump() -> bool:
	return is_standing() and body.is_on_floor() and body.vitals.is_up() \
		and body.inventory.hands == &"" and body.carry_speed_mult() >= 1.0 \
		and MovementRules.can_jump_at(body.load_tier()) and not _winded and stamina >= jump_cost()


## Legs stamina a jump takes at this load (MovementRules.JUMP_STAMINA x TIER_DRAIN).
func jump_cost() -> float:
	return MovementRules.JUMP_STAMINA * MovementRules.TIER_DRAIN[body.load_tier()]


## Jumps (check can_jump first): up, unmounted, paying jump_cost.
func jump() -> void:
	body.velocity.y = JUMP_VELOCITY
	mounted = false
	stamina -= jump_cost()
	_settle_winded()


# --- Mantle ------------------------------------------------------------------------------

## The highest ledge this body can climb now (m above the feet): by load, 0 when it can't. A
## working exo frame's legs reach higher (ExoFrame.climb_assist_m; Captain, 2026-10-16: over
## compound walls and onto roofs, "especially exo-equipped soldiers").
func mantle_reach() -> float:
	var tier := body.load_tier()
	if not MovementRules.can_jump_at(tier):
		return 0.0
	var reach := MANTLE_MAX_OVERLOADED_M if tier >= MovementRules.Tier.OVERLOADED else MANTLE_MAX_M
	return reach + ExoFrame.climb_assist_m(body.inventory)


## Whether it can start a mantle now: on its feet (standing or crouched), on the ground, up,
## hands free, not winded, not riding.
func can_mantle() -> bool:
	return body.vitals.is_up() and (body.is_on_floor() or Soldier._now() - _floor_at < MANTLE_COYOTE_S) and stance != Stance.PRONE and not is_instance_valid(body.vehicle) \
		and body.inventory.hands == &"" and body.carry_speed_mult() >= 1.0 and not _winded and mantle_reach() > 0.0


## The ledge ahead to climb: {"top": the point on top to end on (world), "h": its height over
## the feet, "stance": the stance it ends in (STAND_HIGH, or CROUCH_HIGH under a low roof)}, or {}.
func find_ledge() -> Dictionary:
	if not body.is_inside_tree():
		return {}
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var fwd := -body.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return {}
	fwd = fwd.normalized()
	var run := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if run.length() > 1.5 and run.normalized().dot(fwd) > MANTLE_RUN_DOT:
		fwd = run.normalized()  # along the way it runs
	var look := minf(run.length() * MANTLE_LOOK_S, MANTLE_LOOK_MAX_M)
	var airborne := not body.is_on_floor()
	var reach := mantle_reach()
	var exclude: Array[RID] = [body.get_rid()]
	# A wall ahead: something not walkable within reach, low down (so the top is a ledge).
	var wall_d := INF
	for h: float in [MANTLE_MIN_M - 0.15, 0.7, 1.0, 1.4]:
		if h > reach:
			break
		var from := feet + Vector3.UP * h
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * (CAPSULE_RADIUS + MANTLE_REACH_M + look), MANTLE_MASK, exclude))
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.7:
			wall_d = minf(wall_d, from.distance_to(hit.position))
	if is_inf(wall_d):
		return {}
	# Its top, just past the face, looking down from over the highest reach.
	var over := feet + fwd * (wall_d + 0.2) + Vector3.UP * (reach + 0.4)
	var top_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (reach + 0.4 - MANTLE_MIN_M + 0.05), MANTLE_MASK, exclude))
	if top_hit.is_empty() or (top_hit.normal as Vector3).y < 0.7:
		return {}
	var top: Vector3 = top_hit.position
	var height := top.y - feet.y
	if height < (MANTLE_AIR_MIN_M if airborne else MANTLE_MIN_M) or height > reach:
		return {}
	if ExoFrame.working(body.inventory):
		var vault := _leap_over(top, fwd, exclude)
		if not vault.is_empty():
			vault.h = height
			return vault
	# Room to rise straight up beside the face (crouched), then on top to crouch at least.
	var land := top + fwd * maxf(MANTLE_ONTO_M - 0.2, 0.1)
	if not _capsule_fits(Vector3(feet.x, top.y + 0.05, feet.z), STANCE_CAPSULE[Stance.CROUCH_HIGH], exclude):
		return {}
	if not _capsule_fits(land + Vector3.UP * 0.05, STANCE_CAPSULE[Stance.CROUCH_HIGH], exclude):
		return {}
	var ends := Stance.STAND_HIGH if _capsule_fits(land + Vector3.UP * 0.05, STANCE_CAPSULE[Stance.STAND_HIGH], exclude) else Stance.CROUCH_HIGH
	return {"top": land, "h": height, "stance": ends}


## A leap over the wall whose top is at `top`: the far side's ground (LEAP_DROP_M or more below the
## top within LEAP_OVER_M past the face), landing LEAP_LAND_M beyond it with room to stand or
## crouch, and room to pass over the top; {} for a wide top (a roof: land on it) or no landing.
func _leap_over(top: Vector3, fwd: Vector3, exclude: Array[RID]) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	for d: float in [0.45, LEAP_OVER_M]:
		var from := top + fwd * d + Vector3.UP * 0.3
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, MANTLE_MASK, exclude))
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		if ground.y > top.y - LEAP_DROP_M:
			return {}  # the top goes on: a roof, landed on
		var land := ground + fwd * LEAP_LAND_M
		var probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(land + Vector3.UP * 1.0, land + Vector3.DOWN * 1.5, MANTLE_MASK, exclude))
		if not probe.is_empty():
			land = probe.position
		if not _capsule_fits(top + Vector3.UP * 0.1, STANCE_CAPSULE[Stance.CROUCH_HIGH], exclude):
			return {}  # no room over the top
		if not _capsule_fits(land + Vector3.UP * 0.05, STANCE_CAPSULE[Stance.CROUCH_HIGH], exclude):
			return {}
		var ends := Stance.STAND_HIGH if _capsule_fits(land + Vector3.UP * 0.05, STANCE_CAPSULE[Stance.STAND_HIGH], exclude) else Stance.CROUCH_HIGH
		return {"top": land, "edge": top, "over": true, "stance": ends}
	return {}


## Whether a capsule `height` tall (a hair under the body's radius), its bottom at `at`, meets
## nothing solid (the world, vehicles, other soldiers).
func _capsule_fits(at: Vector3, height: float, exclude: Array[RID]) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS - 0.02
	cap.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), at + Vector3.UP * (height * 0.5))
	q.collision_mask = MANTLE_MASK | Soldier.BODY_LAYER
	q.exclude = exclude
	return body.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## The leg stamina a mantle of `height` metres costs at this load (a working exo frame's
## legs do the climb past what bare legs reach).
func mantle_cost(height: float) -> float:
	var own := minf(height, MANTLE_MAX_M) if ExoFrame.working(body.inventory) else height
	return jump_cost() * MANTLE_STAMINA_PER_M * maxf(own, MANTLE_MIN_M)


## Jump key, owner-side: climbs the ledge ahead if there is one it can (find_ledge), paying
## for it. Returns whether it started.
func try_mantle() -> bool:
	if not can_mantle():
		return false
	var ledge := find_ledge()
	if ledge.is_empty():
		return false
	var cost := mantle_cost(float(ledge.h))
	if stamina < cost:
		return false
	var feet := body.global_position
	var top: Vector3 = ledge.top
	set_stance(Stance.CROUCH_HIGH)
	mounted = false
	mantling = true
	var leap := ExoFrame.working(body.inventory)
	last_over = leap and ledge.get("over", false)
	var seconds := MANTLE_BASE_S + MANTLE_PER_M_S * float(ledge.h)
	var run := Vector3(body.velocity.x, 0.0, body.velocity.z)
	seconds *= lerpf(1.0, MANTLE_FAST, clampf(run.length() / MANTLE_FAST_MS, 0.0, 1.0))
	if leap:
		seconds = LEAP_BASE_S + LEAP_PER_M_S * float(ledge.h) + (LEAP_OVER_S if ledge.get("over", false) else 0.0)
	_mantle = {"from": feet, "up": Vector3(feet.x, top.y + 0.05, feet.z), "to": top + Vector3.UP * 0.02, "t": 0.0,
		"s": seconds, "stance": int(ledge.stance), "leap": leap, "edge": ledge.get("edge", top),
		"carry": run.length(), "dir": Vector3(top.x - feet.x, 0.0, top.z - feet.z).normalized()}
	stamina -= cost
	_settle_winded()
	body.report_exertion()
	body.velocity = Vector3.ZERO
	return true


## One step of a mantle: up beside the face for the first 60%, then onto the top.
func _mantle_step(delta: float, down: bool) -> void:
	body.velocity = Vector3.ZERO
	if down:
		mantling = false  # knocked down on the way: it drops where it is
		return
	var t := minf(float(_mantle.t) + delta / float(_mantle.s), 1.0)
	_mantle.t = t
	var from: Vector3 = _mantle.from
	var up: Vector3 = _mantle.up
	var to: Vector3 = _mantle.to
	if _mantle.get("leap", false):
		# One arc (a curve through a high control point): onto a roof it's pulled up over the
		# take-off spot, so the body rises first and then carries over the edge; over a wall it's
		# over the wall, high enough that the arc's middle clears the top by LEAP_APEX_M.
		var edge: Vector3 = _mantle.edge
		var peak := Vector3(from.x, to.y + LEAP_APEX_M * 2.0, from.z)
		if to.y < edge.y - 0.1:
			peak = Vector3(edge.x, 2.0 * (edge.y + LEAP_APEX_M) - 0.5 * (from.y + to.y), edge.z)
		var u := 1.0 - t
		body.global_position = from * (u * u) + peak * (2.0 * u * t) + to * (t * t)
	elif float(_mantle.get("carry", 0.0)) > 1.5:
		# On the move: one curve up and over (a control point over the take-off, a little above
		# the top), eased, rather than straight up and then across.
		var ctrl := Vector3(lerpf(from.x, to.x, 0.25), up.y + 0.15, lerpf(from.z, to.z, 0.25))
		var e := smoothstep(0.0, 1.0, t)
		var u := 1.0 - e
		body.global_position = from * (u * u) + ctrl * (2.0 * u * e) + to * (e * e)
	elif t < 0.6:
		body.global_position = from.lerp(up, smoothstep(0.0, 1.0, t / 0.6))
	else:
		body.global_position = up.lerp(to, smoothstep(0.0, 1.0, (t - 0.6) / 0.4))
	_slid_at = body.global_position
	_air_top = -INF  # a climb, not a fall
	_last_y = body.global_position.y
	if t >= 1.0:
		mantling = false
		set_stance(int(_mantle.stance))
		# Over the top still going: most of the speed it came with, on the way it climbed.
		body.velocity = (_mantle.get("dir", Vector3.ZERO) as Vector3) * float(_mantle.get("carry", 0.0)) * MANTLE_CARRY


## Changes stance if there's room (a taller stance needs headroom). Unmounts the weapon.
## Returns whether the body is now in that stance.
func set_stance(new_stance: int) -> bool:
	new_stance = clampi(new_stance, Stance.PRONE, Stance.STAND_HIGH)
	if body.vitals != null and not body.vitals.can_stand():
		new_stance = Stance.PRONE
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
		if body.carry_mode == Soldier.DRAG and stance != Stance.PRONE:
			target = CharacterModel.DRAG_EYE  # bent over the casualty, head up
		target.y -= CharacterModel.KNEEL_EYE_DROP * body.model.carry_kneel()  # down on a knee to lift or lay them
		roll = pose.roll * CAMERA_ROLL if not pose.prone else pose.prone_roll * CAMERA_PRONE_ROLL - lean * 0.1
	# The eye is drawn at the body's scale (CharacterModel.body_scale): a female soldier's 1.53 m,
	# not the male 1.65 m near the top of her 1.68 m head (docs/animation.md, "World scale").
	target *= body.model.body_scale()
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

## Top speed right now, before momentum, moving along `input` (Input.get_vector: forward by
## default): slower sideways and backwards (MovementRules.direction_mult); a sprint builds from a
## jog over the sprint ramp and loses some of its edge under load (MovementRules.sprint_left).
func top_speed(sprinting: bool, down: bool, input := Vector2(0, -1)) -> float:
	var speed := STANCE_SPEED[stance]
	if side != 0:
		speed *= SIDE_SPEED_MULT
	if sprinting:
		var full := WALK_SPEED + (SPRINT_SPEED - WALK_SPEED) * MovementRules.sprint_left(body.load_kg)
		speed = lerpf(STANCE_SPEED[Stance.STAND_HIGH], full, sprint_ramp)
	speed *= MovementRules.direction_mult(input, body.load_kg)
	if body.is_aiming:
		var weapon := body.active_weapon()
		speed = minf(speed, WALK_SPEED) * ADS_SPEED_MULT * body.vitals.aim_mult(weapon != null and weapon.tags.has("rifle"))
	if down:
		speed = CRAWL_SPEED
	return speed * body.load_mult * body.vitals.speed_mult() * body.carry_speed_mult()


## 0 (light) to 1 (a full load, a bulky item or a body on your shoulder counts too).
func load_fraction() -> float:
	return clampf((1.0 - body.load_mult * body.carry_speed_mult()) / (1.0 - Soldier.MIN_LOAD_MULT), 0.0, 1.0)


## Horizontal velocity after one step towards `target` (all longer under load, much longer
## in the air). Speed along the wanted direction builds over ACCEL_TIME and brakes over
## STOP_TIME from any speed; speed across it (the old heading after a turn, or after the
## view swings round) is shed over GRIP_TIME. So momentum carries a short way into stops,
## turns and stance changes, without sliding. With `grip` off (AI), the older plain ease.
func next_velocity(current: Vector3, target: Vector3, delta: float, on_floor := true, grip := true) -> Vector3:
	var weight := (1.0 + HEAVY_TIME_MULT * load_fraction()) / (1.0 if on_floor else AIR_CONTROL)
	if not grip:
		var time := ACCEL_TIME if target.length() >= current.length() - 0.001 else AI_STOP_TIME
		return current.move_toward(target, WALK_SPEED / (time * weight) * delta)
	var brake := maxf(current.length(), WALK_SPEED) / (STOP_TIME * weight) * delta
	var speed := target.length()
	if speed < 0.001:
		return current.move_toward(Vector3.ZERO, brake)
	var dir := target / speed
	var along := current.dot(dir)
	var across := current - dir * along
	if along < 0.0:  # turning back: brake the old way first
		along = minf(along + brake, 0.0)
	elif along > speed:
		along = maxf(along - brake, speed)
	else:
		along = minf(along + WALK_SPEED / (ACCEL_TIME * weight) * delta, speed)
	return dir * along + across.move_toward(Vector3.ZERO, WALK_SPEED / (GRIP_TIME * weight) * delta)


## Sprinting needs legs stamina, sound legs and a load under OVERLOADED (MovementRules).
func can_sprint() -> bool:
	return not _winded and stamina > 0.0 and body.vitals.can_sprint() and MovementRules.can_sprint_at(body.load_tier())


## Sprinting drains stamina (faster by load tier); otherwise it comes back (faster crouched or
## prone).
func update_stamina(delta: float, sprinting: bool, moving: bool) -> void:
	if sprinting:
		stamina -= delta / SPRINT_STAMINA_S * MovementRules.TIER_DRAIN[body.load_tier()]
	else:
		var posture := MovementRules.REGEN_PRONE_MULT if is_prone() else (MovementRules.REGEN_CROUCH_MULT if is_crouched() else 1.0)
		stamina += delta / STAMINA_REGEN_S * body.vitals.stamina_mult() * (STAMINA_REGEN_MOVING if moving else 1.0) * posture
	_settle_winded()


func _settle_winded() -> void:
	stamina = clampf(stamina, 0.0, 1.0)
	if stamina <= 0.0:
		_winded = true
	elif stamina >= STAMINA_RESUME:
		_winded = false


## Out of breath: legs stamina ran out and hasn't come back to STAMINA_RESUME.
func is_winded() -> bool:
	return _winded


## The arms (MovementRules: arm stamina) and the breath, each step. Holding the weapon up
## `aiming` drains the arms by its mass and the stance (empty arms drain the legs instead);
## lowered, they refill. `hold`: the hold-breath key is down.
func update_arms(delta: float, aiming: bool, hold: bool) -> void:
	var kg := held_weapon_mass()
	var tired := 1.0 - stamina
	breath_phase = fmod(breath_phase + delta * TAU * lerpf(MovementRules.BREATH_HZ, MovementRules.BREATH_HZ_WINDED, tired), TAU * 64.0)
	_gasp_left = maxf(_gasp_left - delta, 0.0)
	if not hold:
		_hold_spent = false
	if breath_held and (not hold or not aiming):
		breath_held = false  # let go early: a shorter gasp
		_gasp_left = MovementRules.BREATH_RECOVER_S * clampf(1.0 - _breath_left / maxf(_hold_limit(), 0.01), 0.0, 1.0)
	elif not breath_held and hold and aiming and _gasp_left <= 0.0 and not _hold_spent:
		breath_held = true
		_breath_left = _hold_limit()
	if breath_held:
		_breath_left -= delta
		if _breath_left <= 0.0:
			breath_held = false
			_hold_spent = true
			_gasp_left = MovementRules.BREATH_RECOVER_S
	if aiming and kg > 0.0:
		var drain := MovementRules.arm_drain(kg) * _arm_posture() * (MovementRules.BREATH_HOLD_ARM_MULT if breath_held else 1.0) * delta
		if arm_stamina > 0.0:
			arm_stamina = maxf(arm_stamina - drain, 0.0)
		else:
			stamina -= drain * MovementRules.ARMS_EMPTY_LEG_SHARE  # arms gone: the legs and lungs pay
			_settle_winded()
	else:
		arm_stamina = minf(arm_stamina + delta / MovementRules.ARM_REGEN_S * body.vitals.stamina_mult(), 1.0)


## Seconds a breath can be held now: shorter out of breath or with spent arms.
func _hold_limit() -> float:
	return lerpf(MovementRules.BREATH_HOLD_MIN_S, MovementRules.BREATH_HOLD_S, minf(stamina, maxf(arm_stamina, 0.5)))


## How much the arms pay for holding up the weapon in this stance (rested: little).
func _arm_posture() -> float:
	if mounted:
		return MovementRules.ARM_MOUNTED_MULT
	if is_prone():
		return MovementRules.ARM_PRONE_MULT
	return MovementRules.ARM_CROUCH_MULT if is_crouched() else 1.0


## Mass (kg) of the active weapon with its optic, 0 without one.
func held_weapon_mass() -> float:
	var weapon := body.active_weapon()
	if weapon == null or body.inventory.hands != &"":
		return 0.0
	return MovementRules.weapon_mass(weapon, body.inventory.state_of(body.active_slot))


## Seconds to bring the active weapon to the eye now (PlayerInput._update_aim).
func ads_seconds() -> float:
	return MovementRules.ads_seconds(held_weapon_mass(), arm_stamina)


## Aimed sway multiplier from the breath: steady while held, worse while gasping after.
func breath_sway_mult() -> float:
	if breath_held:
		return MovementRules.BREATH_HOLD_SWAY
	return MovementRules.BREATH_GASP_SWAY if _gasp_left > 0.0 else 1.0


## Seconds of gasping left after a held breath (0: none).
func gasp_left() -> float:
	return _gasp_left


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
