class_name CharacterModel
extends Node3D
## Procedural voxel soldier (see VoxelArt): rigid body parts on joint pivots, animated in
## code. Legs swing with movement speed and the head follows the look pitch. Arms have
## elbows: with nothing held they swing; when GearRig hands them something (set_held),
## two-bone IK puts the right hand on its grip point and the left on its support point.
## Gear mounts on `torso`, `head`, or `hands_anchor` (which pitches with aim).
##
## Stance comes in as a `pose` (see REST_POSE; SoldierMovement fills it in): the model
## eases towards it, and pose_hitboxes / lay_down snap the body's hitboxes to the same pose
## so shots land where the body is drawn.
##
## Actions (see "Actions" below) are drawn from replicated state, so every peer, late
## joiners included, sees the same thing: `carry_net` (carrying or dragging a casualty, and
## the casualty's side of it: draped over the shoulders, or dragged on their back) and
## `action_net` (picking up, equipping and stowing, looting, treating), both set on the host
## by the server_* functions and carried by the body's ServerSync. Weapon draws follow the
## replicated active weapon (GearRig calls start_draw). Hitboxes follow these poses too.

## Joint positions in body space (feet at the origin, facing -Z).
const TORSO_PIVOT := Vector3(0, 0.9, 0)
const HEAD_PIVOT := Vector3(0, 0.56, 0)          # relative to torso
const SHOULDER := Vector3(0.25, 0.52, 0)         # relative to torso, mirrored for the left
const HIP := Vector3(0.075, 0.9, 0)              # mirrored for the left
## Held weapons pivot here (torso-local) when aiming up or down: about shoulder height.
const HANDS_ANCHOR := Vector3(0, 0.5, 0)
const UPPER_ARM := 0.32                           # shoulder to elbow
const FOREARM := 0.25                             # elbow to palm centre
## Elbows bend towards these (torso-local, before normalising): out, down and back.
const POLE_RIGHT := Vector3(0.7, -1.0, 0.35)
const MAX_SPEED := 6.5
## Hip joint to sole: legs are one rigid part, so a lower stance splays them.
const LEG_LENGTH := 0.9
## The eyes, torso-local: hips to eye level (the camera follows this point).
const EYE := Vector3(0, 0.75, 0)
## Lowered hips: the front (left) leg reaches forward to the ground; the back (right) leg
## kneels, angled back this fraction as far (its shin sinks into the ground like a knee).
const BACK_LEG := 0.55
## Prone: lifted by half the torso depth, and shifted back so the body lies centred on the
## origin (feet behind, head in front) instead of tipping over the feet like a downed body.
const PRONE_LIFT := 0.12
const PRONE_SIDE_LIFT := 0.08                    # extra lift when rolled onto a side
const PRONE_SHIFT := 1.0
const PRONE_LEG_SPREAD := 0.12
## Downed bodies tip over around the feet onto the chest (lay_down).
const DOWNED_LIFT := 0.12
## How fast the drawn body eases into a new pose (per second).
const POSE_EASE := 8.0

## A standing pose. hip: hips above the feet (lower bends the legs); hip_x, hip_z: hips shifted
## sideways and back; pitch: upper body lean (negative leans forward); roll: upper body tilt
## (positive leans left); prone: lying face down; prone_roll: rolled onto a side while
## prone (positive rolls onto the left side). Optional: yaw, the whole body turned (radians,
## positive turns left), used by actions.
const REST_POSE := {"hip": 0.9, "hip_x": 0.0, "hip_z": 0.0, "pitch": 0.0, "roll": 0.0, "prone": false, "prone_roll": 0.0}

enum Hold { NONE, BOTH, RIGHT }

# --- Actions ---------------------------------------------------------------------------

## carry_net modes: the carrier's side (the same values as Soldier.CARRY and Soldier.DRAG)
## and the casualty's.
const CARRY := &"carry"
const DRAG := &"drag"
const CARRIED := &"carried"
const DRAGGED := &"dragged"
## action_net ids, and how long each clip takes (treating takes the treatment's time).
const PICK_UP := &"pick_up"
const EQUIP := &"equip"
const LOOT := &"loot"
const TREAT := &"treat"
const PICK_UP_S := 0.6
const EQUIP_S := 0.8
const LOOT_S := 1.0
const LOOT_ALL_S := 1.6
## Picking up: the hand is at the item until this fraction of the clip, then stows it.
const PICK_REACH_END := 0.55
## Equipping: the hand is at the `from` mount until EQUIP_FROM_END, at `to` until EQUIP_TO_END.
const EQUIP_FROM_END := 0.4
const EQUIP_TO_END := 0.8
## Looting: both hands at the body until LOOT_WORK_END, then the right hand stows.
const LOOT_WORK_END := 0.6
## Pose ramps (seconds) for the reaching clips: into the bend or kneel, and back out.
const REACH_RISE_S := 0.22
const REACH_FALL_S := 0.2
## Weapon draws (GearRig, on every peer): the right hand reaches the weapon on its sling or
## in its holster at DRAW_GRAB of DRAW_S, then brings it up.
const DRAW_S := 0.45
const DRAW_GRAB := 0.5
## Hands blend from one target to the next over this long.
const HAND_BLEND_S := 0.12
## A casualty moves onto (or off) its carrier over this long.
const ATTACH_S := 0.35
## How far a hand reaches from its shoulder (a little short of the straight arm).
const ARM_REACH := UPPER_ARM + FOREARM - 0.03
## Hands reach for an item, a body or a wound at most this far out from the feet
## (horizontally); a target further away is reached towards.
const HAND_REACH := 0.62
## Both hands at work (treating, looting) sit this far either side of the target.
const HAND_SPREAD := 0.07
## Pose easing while acting (faster than stance changes, so a 0.6 s pickup reads).
const ACTION_EASE := 14.0
## Kneeling (treating, looting): hips this high. Reaching goes no lower than REACH_MIN_HIP.
const KNEEL_HIP := 0.48
const REACH_MIN_HIP := 0.4
## Reaching turns the body towards a target at least this far out (horizontally).
const REACH_TURN_MIN := 0.25
## Bending forward pushes the hips back by this much of the bend.
const REACH_HIP_BACK := 0.15
## Torso-local points the right hand goes to for each mount (equipping, stowing, picking up):
## the rifle slung on the chest (GearRig.MOUNTS), the pistol holster, the carrier's plate
## pockets, vest pouches, a trouser pocket, over the shoulder to the pack or the back, the
## head (helmet), and down in front (dropping).
const MOUNT_POINTS := {
	&"chest": Vector3(0.16, 0.28, -0.24),
	&"holster": Vector3(0.27, 0.04, -0.06),
	&"carrier": Vector3(0.02, 0.34, -0.24),
	&"pouch": Vector3(0.13, 0.1, -0.2),
	&"pocket": Vector3(0.25, -0.1, -0.08),
	&"pack": Vector3(0.18, 0.62, 0.2),
	&"back": Vector3(0.2, 0.6, 0.16),
	&"head": Vector3(0.07, 0.8, -0.05),
	&"ground": Vector3(0.12, -0.35, -0.45),
}
## Which mount an equipment slot or a container is.
const SLOT_MOUNTS := {
	&"primary": &"chest", &"sidearm": &"holster", &"helmet": &"head", &"vest": &"chest", &"backpack": &"back",
	&"plate_front": &"carrier", &"plate_back": &"carrier", &"plate_left": &"carrier", &"plate_right": &"carrier",
}
const CONTAINER_MOUNTS := {&"vest": &"pouch", &"pockets": &"pocket", &"backpack": &"pack"}
## Fireman's carry, in the carrier's torso space (torso pivot at the hips): the casualty lies
## belly down across the back of the shoulders, its hips here (behind the head, so the
## carrier's camera stays clear), head and arms hanging down the carrier's left side and legs
## down the right. Droops are how far its upper body, head and legs hang (radians).
const CARRY_HIPS := Vector3(0.0, 0.68, 0.36)
const CARRY_TORSO_DROOP := 0.85
const CARRY_HEAD_DROOP := 0.6
const CARRY_LEG_DROOP := 0.7
## The carrier leans forward a little under the weight, an arm round the casualty's legs
## over the right shoulder and a hand holding its arm on the left (torso-local).
const CARRY_LEAN := -0.1
const CARRY_HANDS: Array[Vector3] = [Vector3(0.28, 0.64, 0.16), Vector3(-0.3, 0.52, 0.16)]
## Drag, in the dragger's body space: the casualty lies on its back behind the dragger
## (+Z), head towards them, its upper body lifted by the collar; its hips here, its upper
## body raised this much (radians) and its head lolling back.
const DRAG_HIPS := Vector3(0.0, 0.13, 1.25)
const DRAG_LIFT := 0.45
const DRAG_HEAD_LOLL := 0.4
const DRAG_LEG_SPLAY := 0.12
## The dragger turns to face the casualty (yaw PI: it walks backwards), crouched and bent
## at the hips, both hands on the casualty's carrier shoulder straps (casualty torso-local,
## right strap first: the dragger's right hand takes the casualty's right strap).
const DRAG_POSE := {"hip": 0.5, "hip_x": 0.0, "hip_z": 0.12, "pitch": -1.15, "roll": 0.0, "prone": false, "prone_roll": 0.0, "yaw": PI}
const STRAP_POINTS: Array[Vector3] = [Vector3(0.12, 0.5, -0.08), Vector3(-0.12, 0.5, -0.08)]
## First person: the local player's view model drops by this much (camera-local metres)
## and pitches down this far (radians) while the hands are busy (PlayerInput).
const VIEW_LOWER_OFFSET := Vector3(0.02, -0.2, 0.06)
const VIEW_LOWER_PITCH := 0.9

## Colour scheme from VoxelArt.VARIANTS. Set before the node enters the tree.
@export var variant := "multicam"
@export_flags_3d_render var render_layers := 1:
	set(value):
		render_layers = value
		if is_node_ready():
			for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
				mesh.layers = value

## What the owner wants the arms doing. GearRig reads it to decide what goes in the hands.
var hold := Hold.NONE
## Head pitch in radians (positive looks up), set by the owner each frame.
var look_pitch := 0.0
## While true the left hand works the magazine well instead of the support point.
var reloading := false
## Lying face down, head forward (see lay_down). Overrides `pose`.
var downed := false
## The stance to show (keys as in REST_POSE). Set every frame by the body that owns it.
var pose: Dictionary = REST_POSE.duplicate()
## Replicated (the body's ServerSync; set on the host by server_carry): {"mode": CARRY,
## DRAG, CARRIED or DRAGGED, "with": the other body's node path}, or {} for neither.
var carry_net: Dictionary = {}
## Replicated (the body's ServerSync; set on the host by server_play, server_stop): the
## hand action now, {} for none: "id" (PICK_UP, EQUIP, LOOT, TREAT), "n" (bumps with each
## action, which restarts the clip on every peer), "s" (seconds), "at" (body-space point the
## hands work at), "from" and "to" (MOUNT_POINTS keys the right hand goes to in turn) and
## "kneel". The host clears a finished clip, so late joiners don't replay it.
var action_net: Dictionary = {}

var torso: Node3D
var head: Node3D
var hands_anchor: Node3D
var _root: Node3D
var _upper: Array[Node3D] = []    # [right, left]
var _forearm: Array[Node3D] = []  # [right, left]
var _leg_left: Node3D
var _leg_right: Node3D
var _held: Node3D
var _grip := Vector3.ZERO     # right hand, in _held's local space
var _support := Vector3.ZERO  # left hand, in _held's local space
var _last_position: Vector3
var _speed := 0.0
var _phase := 0.0
var _time := 0.0
var _shown: Dictionary = {}   # bone -> Transform3D, easing towards the pose
var _yaw_shown := 0.0         # the drawn body's turn (pose "yaw"), eased with the bones
var _last_pose: Dictionary = {}  # the stance pose last aimed for, with its action applied
var _action_n := -1           # action_net["n"] last seen
var _action_t := 0.0          # seconds since that action started (local clock)
var _reaching: Dictionary = {}   # the reaching pose for the current action ({} for none)
var _server_n := 0            # host: action serials handed out
var _draw_point := Vector3.ZERO  # torso-local: where the weapon being drawn sits
var _draw_t := -1.0           # seconds into a weapon draw (< 0: none)
var _attach := 0.0            # 0..1: how far the drawn casualty has moved onto its carrier
var _attached := Transform3D.IDENTITY  # where its carrier holds it (world space)
var _hand_source: Array[String] = ["", ""]
var _hand_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_blend: Array[float] = [1.0, 1.0]
var _arms_posed := false


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	torso = _part("torso", _root, TORSO_PIVOT)
	head = _part("head", torso, HEAD_PIVOT)
	hands_anchor = Node3D.new()
	hands_anchor.position = HANDS_ANCHOR
	torso.add_child(hands_anchor)
	for side in [1.0, -1.0]:
		var upper := _part("upper_arm", torso, SHOULDER * Vector3(side, 1, 1))
		_upper.append(upper)
		_forearm.append(_part("forearm", upper, Vector3(0, -UPPER_ARM, 0)))
	_leg_left = _part("leg", _root, HIP * Vector3(-1, 1, 1))
	_leg_right = _part("leg", _root, HIP)
	_last_position = global_position
	_shown = pose_bones(REST_POSE, false)
	var body := get_parent()
	if body:
		for area in _posable_hitboxes(body):
			_rest_of(area)  # recorded before anything moves them


## Puts a body's model and its hitboxes in or out of the downed pose, so shots hit where
## the body is lying. Hitboxes are the body's direct Area3D children with a "body_part"
## meta; when not downed they follow the model's `pose` (crouch, prone, lean) and actions.
static func lay_down(body: Node3D, model: CharacterModel, is_downed: bool) -> void:
	model.downed = is_downed
	model.pose_hitboxes(body)


## Snaps the body's hitboxes to the pose this model is heading for (stance, action, downed,
## or carried and dragged): each follows the bone it belongs to (upper body, head, pelvis,
## left or right leg), from its rest transform.
func pose_hitboxes(body: Node3D) -> void:
	var bones := _target_bones(_carry_state())
	var rest := rest_bones()
	var deltas := {}
	for key: String in ["torso", "head", "pelvis", "leg_l", "leg_r"]:
		deltas[key] = transform * (bones.root as Transform3D) * (bones[key] as Transform3D) * (rest[key] as Transform3D).affine_inverse()
	for area in _posable_hitboxes(body):
		var target: Transform3D = deltas[_bone_of(area)] * _rest_of(area)
		if not area.transform.is_equal_approx(target):
			area.transform = target


## Model-space transforms for a pose: "root" (whole body), and root-local "torso", "head"
## (kept level with the ground, like the drawn head), "pelvis", "leg_l" and "leg_r" (joint pivots).
static func pose_bones(p: Dictionary, is_downed: bool) -> Dictionary:
	if is_downed:
		var rest := rest_bones()
		rest["root"] = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, DOWNED_LIFT, 0))
		return rest
	var hip: float = p.get("hip", HIP.y)
	var hip_x: float = p.get("hip_x", 0.0)
	var hip_z: float = p.get("hip_z", 0.0)
	var yaw: float = p.get("yaw", 0.0)
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var spread := 0.0
	if p.get("prone", false):
		var roll: float = p.get("prone_roll", 0.0)
		var lying := Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, -PI / 2)
		root = root * Transform3D(lying, Vector3(0, PRONE_LIFT + PRONE_SIDE_LIFT * absf(sin(roll)), PRONE_SHIFT))
		spread = PRONE_LEG_SPREAD
	var bend := acos(clampf(hip / LEG_LENGTH, 0.0, 1.0))
	var roll_by: float = p.get("roll", 0.0)
	var pitch_by: float = p.get("pitch", 0.0)
	var torso_basis := Basis(Vector3.BACK, roll_by) * Basis(Vector3.RIGHT, pitch_by)
	var torso := Transform3D(torso_basis, Vector3(hip_x, hip, hip_z))
	return {
		"root": root,
		"torso": torso,
		"head": torso * Transform3D(Basis(Vector3.RIGHT, -_upper_body_pitch(root.basis * torso_basis, yaw)), HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), Vector3(hip_x, hip, hip_z)),
		"leg_l": Transform3D(Basis(Vector3.BACK, -spread) * Basis(Vector3.RIGHT, bend), Vector3(hip_x - HIP.x, hip, hip_z)),
		"leg_r": Transform3D(Basis(Vector3.BACK, spread) * Basis(Vector3.RIGHT, -bend * BACK_LEG), Vector3(hip_x + HIP.x, hip, hip_z)),
	}


## The bones of a casualty being carried (CARRIED: "root" in the carrier's torso space) or
## dragged (DRAGGED: "root" in the dragger's body space): limp, the upper body and legs
## hanging or lying as the carry leaves them. Same keys as pose_bones.
static func casualty_bones(mode: StringName) -> Dictionary:
	var place: Basis
	var hips: Vector3
	var torso_pitch: float
	var head_pitch: float
	var legs: float
	var splay: float
	if mode == CARRIED:
		# Belly down (its front faces the carrier's -Y), head towards the carrier's left (-X).
		place = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
		hips = CARRY_HIPS
		torso_pitch = -CARRY_TORSO_DROOP
		head_pitch = -CARRY_HEAD_DROOP
		legs = CARRY_LEG_DROOP
		splay = 0.05
	else:
		# On its back (its front faces up), head towards the dragger (-Z).
		place = Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
		hips = DRAG_HIPS
		torso_pitch = -DRAG_LIFT
		head_pitch = DRAG_HEAD_LOLL
		legs = 0.0
		splay = DRAG_LEG_SPLAY
	var torso := Transform3D(Basis(Vector3.RIGHT, torso_pitch), TORSO_PIVOT)
	return {
		"root": Transform3D(place, hips - place * TORSO_PIVOT),
		"torso": torso,
		"head": torso * Transform3D(Basis(Vector3.RIGHT, head_pitch), HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), TORSO_PIVOT),
		"leg_l": Transform3D(Basis(Vector3.BACK, -splay) * Basis(Vector3.RIGHT, legs), HIP * Vector3(-1, 1, 1)),
		"leg_r": Transform3D(Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, legs * 1.15), HIP),
	}


## Where the dragger's hands hold a dragged casualty (its STRAP_POINTS), in the dragger's
## body space: [right, left].
static func drag_hand_points() -> Array[Vector3]:
	var bones := casualty_bones(DRAGGED)
	var torso_xform: Transform3D = (bones.root as Transform3D) * (bones.torso as Transform3D)
	return [torso_xform * STRAP_POINTS[0], torso_xform * STRAP_POINTS[1]]


## The bones standing at rest (root-local, root at the origin).
static func rest_bones() -> Dictionary:
	return {
		"root": Transform3D.IDENTITY,
		"torso": Transform3D(Basis(), TORSO_PIVOT),
		"head": Transform3D(Basis(), TORSO_PIVOT + HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), TORSO_PIVOT),
		"leg_l": Transform3D(Basis(), HIP * Vector3(-1, 1, 1)),
		"leg_r": Transform3D(Basis(), HIP),
	}


## How far an upper body with this (model-space) basis leans forward (negative) or back,
## for a body turned by `yaw`.
static func _upper_body_pitch(torso_basis: Basis, yaw := 0.0) -> float:
	var up := torso_basis * Vector3.UP
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return atan2(-up.dot(forward), up.y)


## Where the eyes are for a pose, in body space (the camera goes here).
static func eye_position(p: Dictionary) -> Vector3:
	var bones := pose_bones(p, false)
	return bones.root * bones.torso * EYE


## The pose for reaching both hands to `point` (body space) from stance `base`: turned to
## face it, bent at the hips, and the hips lowered (kneeling with `kneel`) only as far as it
## takes. Prone stays prone (the hands just reach).
static func reach_pose(base: Dictionary, point: Vector3, kneel: bool) -> Dictionary:
	if base.get("prone", false):
		return {}
	var flat := Vector2(point.x, point.z)
	var turned := flat.length() > REACH_TURN_MIN
	var yaw := atan2(-point.x, -point.z) if turned else 0.0
	var ahead := flat.length() if turned else -point.z  # how far in front, once turned
	var top: float = KNEEL_HIP if kneel else maxf(float(base.get("hip", HIP.y)), REACH_MIN_HIP)
	var best := {}
	var best_gap := INF
	var hip := top
	while hip >= REACH_MIN_HIP - 0.001:
		for step in 27:
			var bend := step * 0.05
			var back := REACH_HIP_BACK * sin(bend)
			var shoulder_up := hip + SHOULDER.y * cos(bend)
			var shoulder_ahead := SHOULDER.y * sin(bend) - back
			var lateral := SHOULDER.x - HAND_SPREAD
			var gap := Vector3(lateral, point.y - shoulder_up, ahead - shoulder_ahead).length() - ARM_REACH
			if gap < best_gap:
				best_gap = gap
				best = {"hip": hip, "hip_x": 0.0, "hip_z": back, "pitch": -bend, "roll": 0.0, "prone": false, "prone_roll": 0.0, "yaw": yaw}
			if gap <= 0.0:
				return best
		hip -= 0.04
	return best


## `a` eased towards `b` by `w` (0..1); prone and its roll stay `a`'s.
static func blend_pose(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := a.duplicate()
	for key: String in ["hip", "hip_x", "hip_z", "pitch", "roll"]:
		out[key] = lerpf(float(a.get(key, REST_POSE.get(key, 0.0))), float(b.get(key, a.get(key, 0.0))), w)
	out["yaw"] = lerp_angle(float(a.get("yaw", 0.0)), float(b.get("yaw", 0.0)), w)
	return out


## A reach target (body space) brought within HAND_REACH of the feet, horizontally, and kept
## off the floor.
static func reach_point(point: Vector3) -> Vector3:
	var flat := Vector2(point.x, point.z).limit_length(HAND_REACH)
	return Vector3(flat.x, clampf(point.y, 0.05, 1.7), flat.y)


## Which mount (MOUNT_POINTS) an item goes to when it's put away: its equipment slot's, or a
## pouch.
static func mount_for_item(item: ItemData) -> StringName:
	if item == null:
		return &"pouch"
	if item.is_plate():
		return &"carrier"
	return SLOT_MOUNTS.get(item.slot, &"pouch")


## Hands go to `grip` (right) and `support` (left), given in `node`'s local space.
func set_held(node: Node3D, grip: Vector3, support: Vector3) -> void:
	_held = node
	_grip = grip
	_support = support


func clear_held() -> void:
	_held = null


## Global position of a palm (for tests and tools).
func hand_position(right: bool) -> Vector3:
	return _forearm[0 if right else 1].to_global(Vector3(0, -FOREARM, 0))


## Largest palm-to-target distance in metres while holding something; -1 if nothing is held.
func hand_error() -> float:
	if not is_instance_valid(_held):
		return -1.0
	return maxf(hand_position(true).distance_to(_held.to_global(_grip)),
		hand_position(false).distance_to(_held.to_global(_support)))


# --- Actions: what peers see ------------------------------------------------------------

## The carry this model shows now: {"mode", "body" (the other body), "model" (its
## CharacterModel)}, or {} for none. A casualty's side only shows while it's down.
func carry_shown() -> Dictionary:
	return _carry_state()


## The hand action playing now (an action_net id), or &"" for none.
func action_shown() -> StringName:
	return StringName(action_net.get("id", &"")) if _action_active() else &""


## The hands are on something other than a weapon: a casualty, or an action. GearRig slings
## or holsters the weapon meanwhile.
func hands_busy() -> bool:
	var mode: StringName = carry_net.get("mode", &"")
	return mode == CARRY or mode == DRAG or _action_active()


## A weapon draw (GearRig): the right hand goes to `point` (torso-local, the weapon on its
## sling or in its holster) and brings it up.
func start_draw(point: Vector3) -> void:
	_draw_point = point
	_draw_t = 0.0


## 0..1: how far the first-person view model should be lowered (PlayerInput): carrying or
## dragging, treating and looting, and a duck during pickups, equipping and draws.
func view_lower() -> float:
	var mode: StringName = carry_net.get("mode", &"")
	if mode == CARRY or mode == DRAG:
		return 1.0
	var w := 0.0
	if _action_active():
		var s := float(action_net.get("s", 0.0))
		match StringName(action_net.get("id", &"")):
			TREAT, LOOT:
				w = _envelope(_action_t, s, 0.15, 0.2)
			_:
				w = sin(PI * clampf(_action_t / maxf(s, 0.01), 0.0, 1.0))
	if _draw_t >= 0.0:
		w = maxf(w, sin(PI * clampf(_draw_t / DRAW_S, 0.0, 1.0)))
	return w


# --- Actions: set on the host -------------------------------------------------------------

## Host only. `carrier` carries or drags (`mode`: CARRY, DRAG) `casualty`, or stopped (mode
## &""): sets both sides' carry_net for every peer. Either body may be null (only the other
## side is set).
static func server_carry(carrier: Node, casualty: Node, mode: StringName) -> void:
	var carrier_model := _model_of(carrier)
	var casualty_model := _model_of(casualty)
	if carrier_model:
		carrier_model.carry_net = {} if mode == &"" else {"mode": mode, "with": String(casualty.get_path()) if casualty else ""}
	if casualty_model:
		casualty_model.carry_net = {} if mode == &"" else {"mode": DRAGGED if mode == DRAG else CARRIED,
			"with": String(carrier.get_path()) if carrier else ""}


## Host only. Starts hand action `id` for every peer (see action_net); returns its serial
## (for server_stop). `at` is a body-space point (reach_point keeps it within reach).
func server_play(id: StringName, seconds: float, at := Vector3.ZERO, from := &"", to := &"", kneel := false) -> int:
	_server_n += 1
	action_net = {"id": id, "n": _server_n, "s": seconds, "at": reach_point(at), "from": from, "to": to, "kneel": kneel}
	return _server_n


## Host only. Ends action `serial` early (a treatment done or interrupted), unless another
## one has started since.
func server_stop(serial: int) -> void:
	if int(action_net.get("n", -1)) == serial:
		action_net = {}


## Host only. Picking up the item at `world_pos`: bend or kneel to it, then put it away
## where `id` goes (a bulky one stays in the hands).
func server_pick_up(world_pos: Vector3, id: StringName) -> void:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	server_play(PICK_UP, PICK_UP_S, to_local(world_pos), &"", &"" if item and item.two_handed else mount_for_item(item))


## Host only. An inventory action (Soldier._server_inventory_action, called before it runs):
## the right hand goes from where the item is to where it goes.
func server_inventory_action(inventory: Inventory, action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	var from := &""
	var to := &""
	match action:
		"drop_slot":
			from = SLOT_MOUNTS.get(slot, &"pouch")
			to = &"ground"
		"drop_entry":
			from = CONTAINER_MOUNTS.get(container, &"pouch")
			to = &"ground"
		"move_entry":
			from = CONTAINER_MOUNTS.get(container, &"pouch")
			to = CONTAINER_MOUNTS.get(target, &"pouch")
		"equip_entry":
			var list: Array = inventory.containers.get(container, [])
			if index < 0 or index >= list.size():
				return
			from = CONTAINER_MOUNTS.get(container, &"pouch")
			to = mount_for_item(ItemDB.get_item(list[index].id))
		"stow_slot":
			from = SLOT_MOUNTS.get(slot, &"pouch")
			to = &"pack" if inventory.slots.get(&"backpack", &"") != &"" and inventory.slots.get(&"vest", &"") == &"" else &"pouch"
		_:
			return
	server_play(EQUIP, EQUIP_S, Vector3.ZERO, from, to)


## Host only. Looting `body` (one item, or everything with `all`): kneel at it, hands on it,
## then into a pouch.
func server_loot(body: Node3D, all := false) -> void:
	var point: Vector3 = body.call(&"aim_point") if body.has_method(&"aim_point") else body.global_position + Vector3.UP * 0.2
	server_play(LOOT, LOOT_ALL_S if all else LOOT_S, to_local(point), &"", &"pouch", true)


## Host only. Treating `part` of `target` (this body or another) for `seconds`: kneeling
## beside another (not yourself), hands working at the wound. Returns the serial to stop it with.
func server_treat(target: Node3D, part: StringName, seconds: float) -> int:
	return server_play(TREAT, seconds, to_local(part_position(target, part)), &"", &"", target != get_parent())


## Where body part `part` of `body` is now (world space): its hitbox, else the chest, else
## a little above its origin.
static func part_position(body: Node3D, part: StringName) -> Vector3:
	for area in _posable_hitboxes(body):
		if area.get_meta(&"body_part", &"") == part:
			for shape in area.get_children():
				if shape is CollisionShape3D:
					return (shape as CollisionShape3D).global_position
	if body.has_method(&"aim_point"):
		return body.call(&"aim_point")
	return body.global_position + Vector3.UP * 0.3


static func _model_of(body: Node) -> CharacterModel:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(^"Model") as CharacterModel


func _part(model: String, parent: Node3D, pivot: Vector3) -> Node3D:
	var node := VoxelArt.instance(model, variant, render_layers)
	node.position = pivot
	parent.add_child(node)
	return node


static func _posable_hitboxes(body: Node) -> Array[Area3D]:
	var areas: Array[Area3D] = []
	for child in body.get_children():
		if child is Area3D and child.has_meta(&"body_part"):
			areas.append(child)
	return areas


## A hitbox's transform with the body standing, recorded the first time it is seen.
static func _rest_of(area: Area3D) -> Transform3D:
	if not area.has_meta(&"pose_rest"):
		area.set_meta(&"pose_rest", area.transform)
	return area.get_meta(&"pose_rest")


## Which bone a hitbox follows: by its body part, or for parts this doesn't know, by where
## it sits at rest (above the neck: head; above the hips: upper body; below: the leg on its
## side, or the pelvis on the centre line).
static func _bone_of(area: Area3D) -> String:
	if area.has_meta(&"pose_bone"):
		return area.get_meta(&"pose_bone")
	var part: StringName = area.get_meta(&"body_part", Vitals.TORSO)
	var bone := "torso"
	if part in [Vitals.HEAD, Vitals.FACE]:
		bone = "head"
	elif part == Vitals.PELVIS:
		bone = "pelvis"
	elif part in [Vitals.THIGH_L, Vitals.SHIN_L]:
		bone = "leg_l"
	elif part in [Vitals.THIGH_R, Vitals.SHIN_R]:
		bone = "leg_r"
	elif not part in [Vitals.NECK, Vitals.TORSO, Vitals.CHEST, Vitals.ABDOMEN,
			Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]:
		var centre := Vector3.ZERO
		var shapes := 0
		for child in area.get_children():
			if child is CollisionShape3D:
				centre += child.position
				shapes += 1
		centre = _rest_of(area) * (centre / maxf(shapes, 1))
		if centre.y < HIP.y - 0.05:
			bone = "pelvis" if absf(centre.x) < 0.03 else ("leg_l" if centre.x < 0.0 else "leg_r")
		elif centre.y > TORSO_PIVOT.y + HEAD_PIVOT.y + 0.05:
			bone = "head"
	area.set_meta(&"pose_bone", bone)
	return bone


func _process(delta: float) -> void:
	# Speed from position change works the same for local, remote and AI bodies.
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var speed := minf(moved.length() / maxf(delta, 0.0001), MAX_SPEED)
	_speed = lerpf(_speed, speed, minf(delta * 10.0, 1.0))
	_time += delta
	_phase += delta * (2.0 + _speed * 1.6)
	_update_action(delta)
	if _draw_t >= 0.0:
		_draw_t += delta
		if _draw_t > DRAW_S:
			_draw_t = -1.0
	var carry := _carry_state()
	var mode: StringName = carry.get("mode", &"")
	var casualty := mode == CARRIED or mode == DRAGGED
	_update_attachment(delta, carry)

	var target := _target_bones(carry)
	var acting := mode != &"" or _action_active()
	var blend := minf(delta * (ACTION_EASE if acting else POSE_EASE), 1.0)
	for key: String in target:
		_shown[key] = (_shown[key] as Transform3D).interpolate_with(target[key], blend)
	var target_yaw := 0.0 if casualty or downed else float(_last_pose.get("yaw", 0.0))
	_yaw_shown = lerp_angle(_yaw_shown, target_yaw, blend)
	var prone: bool = pose.get("prone", false)
	var stride := clampf(_speed / 4.0, 0.0, 1.0) * (0.55 + 0.25 * clampf((_speed - 4.0) / 2.5, 0.0, 1.0))
	if downed or casualty:
		stride = 0.0
	elif prone:
		stride *= 0.35  # crawling: small leg movements
	var swing := sin(_phase) * stride
	_root.transform = (_shown.root as Transform3D).translated(Vector3(0, absf(sin(_phase)) * 0.03 * stride, 0))
	_leg_left.transform = (_shown.leg_l as Transform3D) * Transform3D(Basis(Vector3.RIGHT, swing), Vector3.ZERO)
	_leg_right.transform = (_shown.leg_r as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -swing), Vector3.ZERO)
	torso.transform = (_shown.torso as Transform3D).translated_local(Vector3(0, sin(_time * 2.0) * 0.003, 0))  # breathing
	if casualty:
		# Limp: the head hangs (carried) or lolls back (dragged) with the body.
		head.rotation.x = -CARRY_HEAD_DROOP if mode == CARRIED else DRAG_HEAD_LOLL
		hands_anchor.rotation.x = 0.0
	else:
		# Head and weapon keep facing where the owner looks, whatever the upper body's lean.
		var lean := 0.0 if downed else _upper_body_pitch((_shown.root as Transform3D).basis * (_shown.torso as Transform3D).basis, _yaw_shown)
		head.rotation.x = clampf(look_pitch, -0.7, 0.7) * 0.8 - lean
		hands_anchor.rotation.x = clampf(look_pitch, -0.8, 0.8) * 0.8 - lean
	_update_arms(delta, carry, swing)


## The bones the drawn body is heading for: a casualty's, lying down, or the stance with
## whatever the hands are doing applied.
func _target_bones(carry: Dictionary) -> Dictionary:
	var mode: StringName = carry.get("mode", &"")
	if mode == CARRIED or mode == DRAGGED:
		return casualty_bones(mode)
	if downed:
		return pose_bones(pose, true)
	_last_pose = _action_pose(mode)
	return pose_bones(_last_pose, false)


## The stance pose with the current action applied: the drag crouch (facing the
## casualty), the carry lean, or bending or kneeling to reach.
func _action_pose(mode: StringName) -> Dictionary:
	var prone: bool = pose.get("prone", false)
	if mode == DRAG and not prone:
		return DRAG_POSE
	if mode == CARRY:
		if prone:
			return pose
		var leaning := pose.duplicate()
		leaning["pitch"] = float(pose.get("pitch", 0.0)) + CARRY_LEAN
		return leaning
	if _reaching.is_empty() or not _action_active():
		return pose
	var s := float(action_net.get("s", 0.0))
	var w := 0.0
	match StringName(action_net.get("id", &"")):
		PICK_UP:
			w = _envelope(_action_t, s * PICK_REACH_END + REACH_FALL_S, REACH_RISE_S, REACH_FALL_S)
		LOOT:
			w = _envelope(_action_t, s, REACH_RISE_S, REACH_FALL_S)
		TREAT:
			w = _envelope(_action_t, 0.0, REACH_RISE_S, REACH_FALL_S)  # until it's stopped
	return blend_pose(pose, _reaching, w) if w > 0.0 else pose


## 0..1 over a clip `length` long (0: no end): up over `rise` seconds, down over the last `fall`.
static func _envelope(t: float, length: float, rise: float, fall: float) -> float:
	var up := smoothstep(0.0, rise, t)
	if length <= 0.0:
		return up
	return minf(up, 1.0 - smoothstep(length - fall, length, t))


## Follows action_net: a new serial restarts the clip (and its reaching pose). The host
## clears a finished clip.
func _update_action(delta: float) -> void:
	var n := int(action_net.get("n", -1))
	if n != _action_n:
		_action_n = n
		_action_t = 0.0
		_reaching = {}
		if StringName(action_net.get("id", &"")) in [PICK_UP, LOOT, TREAT]:
			_reaching = reach_pose(pose, action_net.get("at", Vector3.ZERO), bool(action_net.get("kneel", false)))
		return
	_action_t += delta
	var s := float(action_net.get("s", 0.0))
	if s > 0.0 and _action_t > s + 0.25 and not action_net.is_empty() and is_inside_tree() and multiplayer.is_server():
		action_net = {}


func _action_active() -> bool:
	if downed or action_net.is_empty() or StringName(action_net.get("id", &"")) == &"":
		return false
	var s := float(action_net.get("s", 0.0))
	return s <= 0.0 or _action_t < s


## carry_net resolved: {"mode", "body", "model"}, or {} when there's nothing to show (a
## casualty that's up, or whose carrier isn't here).
func _carry_state() -> Dictionary:
	var mode: StringName = carry_net.get("mode", &"")
	if mode == &"":
		return {}
	var path := String(carry_net.get("with", ""))
	var other: Node = get_node_or_null(NodePath(path)) if path != "" and is_inside_tree() else null
	var other_model := _model_of(other)
	if mode == CARRIED or mode == DRAGGED:
		if not downed or other_model == null:
			return {}
	return {"mode": mode, "body": other, "model": other_model}


## A carried or dragged casualty is drawn in its carrier's frame (the carrier's torso, or
## its body for a drag) whatever its own body's transform, so every peer sees it in their
## hands; it eases on and off over ATTACH_S.
func _update_attachment(delta: float, carry: Dictionary) -> void:
	var mode: StringName = carry.get("mode", &"")
	var on := mode == CARRIED or mode == DRAGGED
	var parent := get_parent_node_3d()
	if on:
		var other: CharacterModel = carry.model
		var frame: Transform3D = other.torso.global_transform if mode == CARRIED else other.global_transform
		_attached = frame.orthonormalized()
	_attach = move_toward(_attach, 1.0 if on else 0.0, delta / ATTACH_S)
	if _attach <= 0.0 or parent == null:
		if transform != Transform3D.IDENTITY:
			transform = Transform3D.IDENTITY
		return
	var held := parent.global_transform.affine_inverse() * _attached
	transform = Transform3D.IDENTITY.interpolate_with(held, smoothstep(0.0, 1.0, _attach))


## Arms: each hand goes to its goal (blending from where it was when the goal changes), or
## swings free.
func _update_arms(delta: float, carry: Dictionary, swing: float) -> void:
	var goals := _arm_goals(carry)
	for i in 2:
		var key: String = goals[i][0]
		var point: Variant = goals[i][1]
		if key != _hand_source[i]:
			_hand_source[i] = key
			_hand_from[i] = torso.to_local(hand_position(i == 0))
			_hand_blend[i] = 0.0 if _arms_posed else 1.0
		_hand_blend[i] = minf(_hand_blend[i] + delta / HAND_BLEND_S, 1.0)
		var w := smoothstep(0.0, 1.0, _hand_blend[i])
		if point == null:
			# Free arms swing opposite the legs; forearms bend more on the forward swing.
			var arm_swing := swing * 0.8 * (1.0 if i == 0 else -1.0)
			var upper := Basis.from_euler(Vector3(arm_swing, 0, 0.05 * (1.0 if i == 0 else -1.0)))
			var fore := Basis.from_euler(Vector3(0.15 + maxf(arm_swing, 0.0) * 0.6, 0, 0))
			if w >= 1.0:
				_upper[i].transform.basis = upper
				_forearm[i].transform.basis = fore
				continue
			point = _upper[i].position + upper * (Vector3(0, -UPPER_ARM, 0) + fore * Vector3(0, -FOREARM, 0))
		_reach(i, _hand_from[i].lerp(point, w))
	_arms_posed = true


## [[goal key, torso-local point or null to swing], ...] for the right and left hand.
func _arm_goals(carry: Dictionary) -> Array:
	var mode: StringName = carry.get("mode", &"")
	if mode == CARRIED or mode == DRAGGED:
		return [["limp", _limp_point(0, mode)], ["limp", _limp_point(1, mode)]]
	if downed:
		return [["swing", null], ["swing", null]]
	if mode == CARRY:
		return [["carry", CARRY_HANDS[0]], ["carry", CARRY_HANDS[1]]]
	if mode == DRAG:
		var straps := drag_hand_points()
		return [["drag", _torso_point(straps[0])], ["drag", _torso_point(straps[1])]]
	var held := _held_goals()
	if _action_active():
		var acting := _action_goals(held)
		if not acting.is_empty():
			return acting
	if _draw_t >= 0.0 and _draw_t < DRAW_S * DRAW_GRAB:
		return [["draw", _draw_point], held[1]]
	return held


func _held_goals() -> Array:
	if not is_instance_valid(_held):
		return [["swing", null], ["swing", null]]
	var key := "held:%d" % _held.get_instance_id()
	var support := _support
	if reloading:
		# Hand drops under the receiver and works the magazine.
		support = _grip.lerp(_support, 0.35) + Vector3(0, -0.11 + sin(_time * 9.0) * 0.025, 0)
	return [[key, torso.to_local(_held.to_global(_grip))], [key, torso.to_local(_held.to_global(support))]]


## The hands for the current action, by phase; [] once its hand work is done.
func _action_goals(held: Array) -> Array:
	var s := float(action_net.get("s", 0.0))
	var t := _action_t
	var at := _torso_point(action_net.get("at", Vector3.ZERO))
	var to: Variant = MOUNT_POINTS.get(action_net.get("to", &""))
	var from: Variant = MOUNT_POINTS.get(action_net.get("from", &""))
	var spread := Vector3(HAND_SPREAD, 0, 0)
	match StringName(action_net.get("id", &"")):
		PICK_UP:
			if t < s * PICK_REACH_END:
				return [["item", at], held[1]]
			if to != null:
				return [["stow", to], held[1]]
		EQUIP:
			if t < s * EQUIP_FROM_END and from != null:
				return [["from", from], held[1]]
			if t < s * EQUIP_TO_END and to != null:
				return [["to", to], held[1]]
		LOOT:
			if t < s * LOOT_WORK_END:
				return [["work", at + spread], ["work", at - spread]]
			if to != null:
				return [["stow", to], ["work", at - spread]]
		TREAT:
			var busy := Vector3(sin(_time * 7.0) * 0.025, sin(_time * 5.3) * 0.02, cos(_time * 6.1) * 0.02)
			return [["work", at + spread + busy], ["work", at - spread - busy * 0.7]]
	return []


## A limp arm of a casualty: hanging straight down (carried), or trailing on the ground
## towards its feet (dragged).
func _limp_point(i: int, mode: StringName) -> Vector3:
	var side := 1.0 if i == 0 else -1.0
	var hang: Vector3
	if mode == CARRIED:
		hang = Vector3(sin(_time * 1.3 + i) * 0.08, -1.0, 0.0)
	else:
		hang = _root.global_basis * Vector3(0.5 * side, -1.0, 0.45)  # out, towards the feet, down
	var local := (torso.global_basis.orthonormalized().inverse() * hang).normalized()
	return _upper[i].position + local * ARM_REACH


## A body-space (model-local) point in torso space.
func _torso_point(model_point: Vector3) -> Vector3:
	return torso.to_local(to_global(model_point))


## Two-bone IK in torso space: put arm `i`'s palm on `target`.
func _reach(i: int, target: Vector3) -> void:
	var shoulder := _upper[i].position
	var to := target - shoulder
	var dist := clampf(to.length(), 0.05, UPPER_ARM + FOREARM - 0.001)
	var dir := to.normalized()
	# Law of cosines: how far along `dir` the elbow sits, and how far off the line.
	var along := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + dist * dist) / (2.0 * dist)
	var off := sqrt(maxf(UPPER_ARM * UPPER_ARM - along * along, 0.0))
	var pole := POLE_RIGHT * Vector3(1.0 if i == 0 else -1.0, 1, 1)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * along + bend * off
	var hand := shoulder + dir * dist
	var upper_basis := _segment_basis(elbow - shoulder)
	_upper[i].transform.basis = upper_basis
	_forearm[i].transform.basis = upper_basis.inverse() * _segment_basis(hand - elbow)


## Basis whose -Y points along `v` (limbs hang along -Y), with as little twist as possible.
static func _segment_basis(v: Vector3) -> Basis:
	var y := -v.normalized()
	var x := Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	if x.length_squared() < 0.0001:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))
