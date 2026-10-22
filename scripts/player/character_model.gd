class_name CharacterModel
extends Node3D
## Procedural voxel soldier (see VoxelArt): rigid body parts on joint pivots, animated in
## code. Legs have knees and swing with movement speed; the head follows the look pitch. Arms have
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
## A female soldier (body "female"), loosely after real averages (US adults: men about 175 cm,
## women about 162 cm): drawn at this scale, about 1.68 m to the male model's 1.80 m, with her
## own shoulder joints (torso-local, before scaling, mirrored for the left): in to 0.20 m (the
## male 0.25), where her arms hang against her ribcage without passing into it, and 1.5 cm
## lower, so her shoulder line slopes down from the neck instead of the male square shelf.
const FEMALE_SCALE := 0.93
const FEMALE_SHOULDER := Vector3(0.20, 0.505, 0)
const HIP := Vector3(0.075, 0.9, 0)              # mirrored for the left
## Held weapons pivot here (torso-local) when aiming up or down: about shoulder height.
const HANDS_ANCHOR := Vector3(0, 0.5, 0)
const UPPER_ARM := 0.32                           # shoulder to elbow
const FOREARM := 0.25                             # elbow to palm centre
## Elbows bend towards these (torso-local, before normalising): out, down and back.
const POLE_RIGHT := Vector3(0.7, -1.0, 0.35)
## Holding a rifle two-handed (at the ready or aiming), the upper body blades: it turns this
## far (radians) about its own up axis, support shoulder forward, as a shooter stands. The head
## and the weapon (hands_anchor) turn back by as much, so they keep facing where the soldier
## looks. See _bladed.
const BLADE := 0.4
## Holding a weapon, the support shoulder also comes this far forward and in (torso-local,
## for the left shoulder of a right-handed shooter; mirrored), within the deltoid, so the
## support hand reaches the handguard.
const SUPPORT_REACH := Vector3(0.04, -0.01, -0.06)
## Shouldering a rifle, the head dips this much (radians) to bring the eye down to the optic.
const AIM_HEAD_DIP := 0.14
const MAX_SPEED := 6.5
## Hip joint to sole. Legs have knees (THIGH above, the rest below): a lower stance bends
## them, two-bone, with the feet placed under the hips (see _leg_angles).
const LEG_LENGTH := 0.9
const THIGH := 0.45
## Lowered hips: how far forward the front (left) foot and back the back (right) foot sit,
## per metre the hips have dropped. The back knee comes down to the ground in a kneel.
const FRONT_FOOT := 0.55
const BACK_FOOT := 0.85
## The eyes, torso-local: hips to eye level (the camera follows this point).
const EYE := Vector3(0, 0.75, 0)
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

## Locomotion (docs/animation.md). The legs walk a gait cycle set by ground speed (model space,
## m/s): GAIT_SPEED's anchors, each column a cycle (idle, walk, jog, run at WALK_SPEED, sprint)
## and between them blended. GAIT_HZ: cycles (two steps) a second; GAIT_DUTY: the share of
## a cycle each foot is on the ground; GAIT_DROP: how far the hips sink from the stance's
## height (soft knees, more for a run); GAIT_LIFT: how high a swinging foot comes up;
## GAIT_LEAN: the upper body's lean into the pace (radians); GAIT_ARM: free arms' swing.
## A planted foot moves back under the body at exactly the ground speed (it covers
## duty * speed / hz while down), so it stays where it landed; where the legs can't reach that
## far at GAIT_HZ the cadence goes up instead (gait_hz), so feet never slide.
const GAIT_SPEED: Array[float] = [0.0, 1.4, 2.5, 4.0, 6.5]
const GAIT_HZ: Array[float] = [0.9, 1.0, 1.25, 1.42, 1.6]
const GAIT_DUTY: Array[float] = [0.55, 0.5, 0.36, 0.26, 0.2]
const GAIT_DROP: Array[float] = [0.0, 0.06, 0.07, 0.08, 0.1]
const GAIT_LIFT: Array[float] = [0.06, 0.1, 0.16, 0.24, 0.32]
const GAIT_LEAN: Array[float] = [0.0, 0.03, 0.06, 0.1, 0.2]
const GAIT_ARM: Array[float] = [0.15, 0.3, 0.45, 0.6, 0.85]
## The hips bob this much (m) per step at a stroll, plus GAIT_BOB_RUN at a sprint: up over a
## planted leg walking, down onto it running.
const GAIT_BOB := 0.012
const GAIT_BOB_RUN := 0.02
## Strafing, the legs turn this share of the way towards the way they move (the upper body
## keeps facing the aim), so a sidestep is a run at an angle, not a splits.
const GAIT_HIP_TURN := 0.5
## How fast the measured ground velocity settles (per second), and the speeds the cycle fades
## in over (below it the stance pose stands).
const GAIT_EASE := 10.0
const GAIT_IN := Vector2(0.1, 0.5)
## Speed is measured over the time since the body last moved, up to this long (s): bodies move
## on physics ticks (60 Hz) but the model draws every frame, so above 60 fps most frames see no
## move and the next sees a whole tick's worth. Per frame, a jog read as standing still on the
## empty frames and as a teleport (over MAX_SPEED * 1.5, zeroed) on the others, and AI jogged
## with their legs still (Captain, 2026-10-20, 157 fps: "sliding, legs still").
const MOVE_WINDOW_S := 0.1
## Hips this low or lower (m, body space) walk as a crouch-walk: no extra hip drop, less lift.
const CROUCH_GAIT_HIP := 0.65
## Prone crawl: the body moves this far a cycle, a knee drawn up and out each half.
const CRAWL_STRIDE := 0.55
const CRAWL_KNEE := 1.3
const CRAWL_THIGH := 0.6
const CRAWL_SPLAY := 0.5
## The cycles, by name (gait()).
const IDLE := &"idle"
const WALK := &"walk"
const JOG := &"jog"
const SPRINT := &"sprint"
const CROUCH_WALK := &"crouch_walk"
const CRAWL := &"crawl"
## Ground speeds (m/s) between the named cycles: walk below JOG_AT, sprint from SPRINT_AT.
const JOG_AT := 2.0
const SPRINT_AT := 5.0
## Level of detail: past these distances (m) from the view, or behind it past LOD_NEAR_M, the
## body is drawn every LOD_* frames (with the time since, so cycles keep their pace).
const LOD_NEAR_M := 30.0
const LOD_FAR_M := 70.0
const LOD_MID := 2
const LOD_FAR := 4

## A standing pose. hip: hips above the feet (lower bends the legs); hip_x, hip_z: hips shifted
## sideways and back; pitch: upper body lean (negative leans forward); roll: upper body tilt
## (positive leans left); prone: lying face down; prone_roll: rolled onto a side while
## prone (positive rolls onto the left side). Optional: yaw, the whole body turned (radians,
## positive turns left), used by actions; twist, the upper body turned about its own up axis
## (radians, positive turns left), for the bladed rifle stance (_bladed).
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
## Keying the radio (EnemyTags: a tag passed on): the left hand up to the radio on the carrier's
## left front for the clip, the right staying on the weapon.
const RADIO := &"radio"
const RADIO_S := 1.0
const RADIO_AT := Vector3(-0.12, 0.38, -0.22)
const EQUIP_S := 0.8
const LOOT_S := 1.0
const LOOT_ALL_S := 1.6
## Climbing into a heavy exo from behind (ExoMech.server_enter), opening it and stepping back
## out of it (server_exit): standing behind it, the right hand hits the release on its back
## (MECH_RELEASE, at the clip's "at"); in it, the knees settle and the arms push forward into its
## sleeves (MECH_GRAB, torso-local) while its back zips shut round him (or unzips); out of it,
## he steps back down from where it stands to where he's put (MECH_STEP, MECH_STEP_UP).
const MECH_RELEASE := &"mech_release"
const MECH_IN := &"mech_in"
## Into a suit lying face down (ExoMech.RISE_S): the body drawn lying on its front, open round
## him, zipping shut, then the whole suit pushes itself up (base_transform): a push-up, not a
## sit-up, so it comes up onto its knees first (arms pushing off the ground, hip dipped to a
## kneeling height, MECH_KNEEL_PITCH) and only then stands the rest of the way up.
const MECH_RISE := &"mech_rise"
const MECH_PUSH: Array[Vector3] = [Vector3(0.3, 0.42, -0.5), Vector3(-0.3, 0.42, -0.5)]
## The pause point on the way up (base_transform's pitch): propped on its knees, not yet
## standing (Captain, 2026-10-17: knees-first, not pivoting straight up at the feet).
const MECH_KNEEL_PITCH := -PI / 5.0
const MECH_OPEN := &"mech_open"
const MECH_OUT := &"mech_out"
const MECH_GRAB: Array[Vector3] = [Vector3(0.21, 0.28, -0.38), Vector3(-0.21, 0.28, -0.38)]

const MECH_DIP := 0.16
## The step back out (model space): the body starts this far forward, inside the suit and up
## on its step (MECH_STEP_UP), and walks back down and out to where it's put, behind it.
const MECH_STEP := 0.7
const MECH_STEP_UP := 0.14
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
## Treatment technique per item (action_net "tech"; _treat_goals plays it): how the hands
## work for that treatment, on someone else or (where allowed) yourself. Anything else: WORK.
const WORK := &"work"
const TECHNIQUES := {
	&"pressure_bandage": &"wrap", &"burn_dressing": &"wrap", &"pelvic_binder": &"wrap", &"hemostatic_gauze": &"pack",
	&"tourniquet": &"tourniquet", &"splint": &"splint", &"chest_seal": &"seal", &"decompression_needle": &"needle",
	&"morphine": &"inject", &"epinephrine": &"inject", &"atropine": &"inject", &"adenosine": &"inject",
	&"iv_10": &"iv", &"iv_12": &"iv", &"iv_14": &"iv", &"iv_16": &"iv", &"iv_18": &"iv", &"iv_20": &"iv",
	&"io_kit": &"io", &"cpr": &"cpr", &"defibrillator": &"defib", &"surgical_clamp": &"clamp",
	&"saline_250": &"fluids", &"saline_500": &"fluids", &"saline_1000": &"fluids",
	&"blood_250": &"fluids", &"blood_500": &"fluids", &"blood_1000": &"fluids", &"pressure_bag": &"fluids",
	&"hypothermia_blanket": &"blanket", &"npa": &"npa",
}
## Technique numbers (proposed): a bandage wraps round the limb WRAP_RADIUS out at WRAP_HZ
## turns a second; a tourniquet goes on TOURNIQUET_HIGH m above the wound (high and tight)
## and its windlass turns at WINDLASS_HZ; a needle goes in NEEDLE_HIGH m up the chest (second
## intercostal space); CPR compresses COMPRESSION_M deep at CPR_HZ (about 110 a minute).
const WRAP_RADIUS := 0.06
const WRAP_HZ := 1.1
const TOURNIQUET_HIGH := 0.12
const WINDLASS_HZ := 1.6
const NEEDLE_HIGH := 0.1
const COMPRESSION_M := 0.05
const CPR_HZ := 1.85
## Technique phases (Proposed; shares of the clip unless in seconds), shared by the hands here and
## the props in them (TreatProps): a tourniquet's strap goes round until STRAP_END, then the
## windlass turns, its last turn landing CLIP_S before the end, when the rod goes into its clip and
## the treatment takes (the bleeding stops: Soldier._treat applies it as the clip ends); gauze is
## packed until PACK_END, then pressure held; a chest seal's backing comes off until SEAL_PEEL; a
## needle is all the way in at NEEDLE_IN and its stylet comes out from NEEDLE_OUT; an injector's
## cap comes off by INJECT_CAP, it goes in at INJECT_JAB and away at INJECT_AWAY; an IV is aimed
## until IV_AIM and taped from IV_TAPE; defib pads are on by DEFIB_PADS and the shock goes at
## DEFIB_SHOCK; a splint is shaped until SPLINT_SHAPE.
const STRAP_END := 0.3
const CLIP_S := 0.25
const PACK_END := 0.7
const SEAL_PEEL := 0.3
const NEEDLE_IN := 0.6
const NEEDLE_OUT := 0.85
const INJECT_CAP := 0.15
const INJECT_JAB := 0.3
const INJECT_AWAY := 0.9
const IV_AIM := 0.2
const IV_TAPE := 0.7
const DEFIB_PADS := 0.45
const DEFIB_SHOCK := 0.75
const SPLINT_SHAPE := 0.3
## A palm at work on the skin sits this far off it (half the gloved hand's thickness).
const HAND_OFF := 0.025
## Held props (held_anchor): each hand's anchor, forearm-local: the palm centre.
const HELD_AT := Vector3(0, -FOREARM, 0)
## First person while treating (set_view_hands): the forearms and props go on the view model's
## layer (PlayerInput.VIEW_MODEL_LAYER) as well, so your own camera sees them.
const VIEW_HANDS_LAYER := 1 << 2
## Treating your own arm (one-handed, Proposed): the hurt arm held out in front, its hand here
## (torso-local, for the right arm; mirrored), the upper body turned SELF_ARM_TWIST towards it so
## the other hand reaches across. Your own leg: down on a knee, leaning SELF_LEG_PITCH over it.
const PRESENT := Vector3(0.2, 0.18, -0.3)
const SELF_ARM_TWIST := 0.35
const SELF_LEG_PITCH := -0.45
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
## belly down over the right shoulder, its hips here (beside and just behind the carrier's
## head, clear of the camera), folded at the waist: upper body, head and arms hanging down the
## carrier's back on the left, legs down the front on the right (CARRY_YAW turns the fold that
## way, so the carrier sees the legs in first person). Droops are how far its upper body, head
## and legs hang (radians); the knees bend with the legs.
const CARRY_HIPS := Vector3(0.18, 0.7, 0.1)
const CARRY_YAW := 0.85
const CARRY_TORSO_DROOP := 1.05
const CARRY_HEAD_DROOP := 0.5
const CARRY_LEG_DROOP := 1.2
## The carrier leans forward under the weight, both arms hugging the casualty's thighs in front
## of the right shoulder (torso-local).
const CARRY_LEAN := -0.18
const CARRY_HANDS: Array[Vector3] = [Vector3(0.28, 0.42, -0.1), Vector3(0.14, 0.42, -0.2)]
## Picking up, taking hold and putting down (Soldier.CARRY_LIFT_S, DRAG_GRAB_S, CARRY_LOWER_S),
## as fractions of the phase: the carrier kneels to the body over KNEEL.x and stands back up
## from KNEEL.y; a lifted body leaves the ground over LIFT_RISE (a lowered one reaches it over
## LOWER_FALL); a dragged one's shoulders come up over GRAB_RISE.
const KNEEL := Vector2(0.25, 0.68)
const LIFT_RISE := Vector2(0.3, 0.75)
const LOWER_FALL := Vector2(0.25, 0.7)
const GRAB_RISE := Vector2(0.45, 1.0)
## Drag, in the dragger's body space: the casualty lies on its back behind the dragger
## (+Z), head towards them, its upper body lifted by the collar; its hips here, its upper
## body raised this much (radians) and its head lolling back.
const DRAG_HIPS := Vector3(0.0, 0.13, 1.0)
const DRAG_LIFT := 0.75
const DRAG_HEAD_LOLL := 0.4
const DRAG_LEG_SPLAY := 0.12
## The dragger turns to face the casualty (yaw PI: it walks backwards), in a crouch bent
## forward at the hips (not squatting over them), both hands on the casualty's carrier shoulder straps (casualty torso-local,
## right strap first: the dragger's right hand takes the casualty's right strap).
const DRAG_POSE := {"hip": 0.6, "hip_x": 0.0, "hip_z": 0.05, "pitch": -0.95, "roll": 0.0, "prone": false, "prone_roll": 0.0, "yaw": PI}
const STRAP_POINTS: Array[Vector3] = [Vector3(0.12, 0.5, -0.08), Vector3(-0.12, 0.5, -0.08)]
## First person while dragging: the eye (body space, towards the casualty), head held up over the
## bent back rather than right over the casualty's face, so the view looks down along them.
const DRAG_EYE := Vector3(0, 1.22, 0.22)
## First person: how far the eye drops at the bottom of a pick-up or put-down (carry_kneel).
const KNEEL_EYE_DROP := 0.6
## First person: the local player's view model drops by this much (camera-local metres)
## and pitches down this far (radians) while the hands are busy (PlayerInput).
const VIEW_LOWER_OFFSET := Vector3(0.02, -0.2, 0.06)
const VIEW_LOWER_PITCH := 0.9

## Seated in a vehicle (seated_pose; Vehicle._place_occupants hands every peer the seat's,
## Captain, 2026-10-14: the UH-60M's squad rode in standing poses, through each other and the
## seats). Hips on the cushion, thighs forward, feet on the floor, the upper body a little
## forward; a rider holds his rifle muzzle down between his knees (GearRig.seated_transform),
## a driver, pilot or gunner has his hands forward on the controls. All Proposed:
## the hip joint this far above the cushion (half a thigh's depth: the thigh lies on it),
const SEAT_HIP_UP := 0.07
## and this far back over it (the backside on the seat, not its front edge),
const SEAT_HIP_BACK := 0.05
## hips this high above the floor where the floor isn't known (an open bed seat),
const SEAT_HEIGHT := 0.5
## the feet this far forward of the hips and SEAT_SOLE_UP above the floor,
const SEAT_FOOT := 0.45  # Captain, 2026-10-17 (his photo): thighs level, shins straight down to the feet
const SEAT_SOLE_UP := 0.01
## the knees turned out this far (radians, each side) so the rifle stands between them,
const SEAT_KNEE_SPLAY := 0.14
## the upper body leaning this far forward (radians; negative leans forward),
const SEAT_PITCH := -0.2
## slumped this far, with the head hanging, if he's down or dead in the seat,
const SEAT_SLUMP := -0.6
const SEAT_HEAD_DROOP := 0.6
## and the hands (root-local, from the hips; the right hand, mirrored for the left): on the
## thighs riding, forward on the wheel or stick at a station.
const SEAT_LAP := Vector3(0.13, 0.1, -0.3)
const SEAT_CONTROLS := Vector3(0.2, 0.3, -0.42)
## A troop seat with a canvas back (vehicles.json "back"; Captain, 2026-10-17: riders sitting
## naturally on the seats, packs on): sitting back against it, nearly upright, the hip joint
## SEAT_BACK_OUT in front of the canvas (the carrier's back on it; a worn pack sits him forward
## by its depth: Vehicle._place_occupants).
const SEAT_BACKED_PITCH := -0.07
const SEAT_BACK_OUT := 0.17

## Boarding (Captain, 2026-10-17: "that get anim is poor, it just floats up"): action_net BOARD,
## played by Vehicle (_board_pose) on every peer from the clip's clock. Walk to the door, then
## BOARD_STEP_S stepping up onto the sill, a hand on the grab handle by the doorway; walk in to
## the seat, turning to sit (Vehicle times it by the distance), and BOARD_SIT_S sitting down.
const BOARD := &"board"
const BOARD_STEP_S := 0.75
const BOARD_SIT_S := 0.6
## Stepping up, the upper body leans this far forward (radians, at the push).
const BOARD_LEAN := -0.35
## A standing body's hips sit this much under the straight leg (so a raised foot still reaches).
const BOARD_HIP_SAG := 0.03
## Where the grab handle is (world), and which hand takes it: set by Vehicle while boarding.
var board_grip := Vector3.ZERO
var board_left := false

## Colour scheme from VoxelArt.VARIANTS. Set before the node enters the tree.
@export var variant := "multicam"
## Who this is to look at (a SoldierLook code: face, hair, eyes, build, height; Captain,
## 2026-10-20: a different person in every uniform). Set before the node enters the tree, or
## later with set_face. "" draws SoldierLook.DEFAULT. The uniform stays `variant`'s.
var face := "":
	set(value):
		face = value
		_height = SoldierLook.height_of(value)  # (body_scale is asked many times a frame)
		_girth = SoldierLook.girth_of(value)
var _height := 1.0
var _girth := 1.0
## The face at work (FaceRig): his own head, eyes, mouth and brows.
var face_rig: FaceRig
## Long hair tucked in under a helmet with ear covers or a nape guard (GearRig: set_hair_tucked).
var hair_tucked := false
## Until when (Soldier._now) he's calling out, mouth open (shout; Callouts.play).
var _shout_until := -1.0
## Body type (VoxelArt.BODIES): "male" or "female". A female soldier is drawn FEMALE_SCALE of
## the male's size (joints, gear and hitboxes scale with her) with her shoulder joints at
## FEMALE_SHOULDER, under her own deltoids. Set before the node enters the tree.
@export_enum("male", "female") var body := "male"
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
## Shouldering the weapon (Soldier.is_aiming, replicated): GearRig raises it from the ready.
var aiming := false
## Shoots from the left shoulder (Soldier.left_handed): the hands and the weapon holds mirror.
var left_handed := false
## Friend-or-foe marks GearRig draws (armbands, helmet marks): [armband, helmet] colours, or
## [] for none (civilians). Soldier sets it from his side (GearRig.iff_of).
var iff: Array = []
## Text on the carrier's name tape (an AI's surname, upper case; "" for none). GearRig draws it.
var name_tape := ""
## While true the left hand works the magazine well instead of the support point.
var reloading := false
## The reload under way, from Soldier (weapon detail pass, 2026-10-20: the host tells every peer
## when one begins, so the hand and the magazine follow the same keys as first person): its
## Reloads.keys, its share so far (-1: none known, the hand just works the magazine) and its
## length (s).
var reload_keys: Array = []
var reload_u := -1.0
var reload_len := 1.0
## The reload's moving-part tracks (Reloads.parts: the bolt worked, a feed cover opened), from
## Soldier (feel round 2): near the view, the held weapon's action and cover move on them too.
var reload_parts: Dictionary = {}
## Third person reloads as first person does (feel round 2, Captain 2026-10-20): the weapon
## turns and moves on the keys' own pose (Reloads.POSE, LOOK, BUMP and the rest; GearRig), this
## much more than in first person so it reads from across a street.
const RELOAD_POSE_GAIN := 1.25
## Climbing a ledge (Soldier, from SoldierMovement.mantling, replicated): the weapon low for it,
## as at a run (feel round 2: carry states).
var climbing := false
## Reloading in third person, the support hand's pouch: below and behind its place on the
## handguard (in the held weapon's space), like first person's (PlayerInput.RELOAD_POUCH).
const RELOAD_POUCH := Vector3(-0.1, -0.3, 0.2)
## Lying face down, head forward (see lay_down). Overrides `pose`.
var downed := false
var _flinch := 0.0      # a hit's jolt, decaying (flinch)
var _was_downed := false
var _downed_t := 99.0   # seconds since the body went down or got up (the slump)
## Going down: over SLUMP_S the pose eases at SLUMP_EASE (slow) instead of POSE_EASE.
const SLUMP_S := 1.1
const SLUMP_EASE := 2.6
var _flinch_side := 1.0
## The stance to show (keys as in REST_POSE). Set every frame by the body that owns it.
var pose: Dictionary = REST_POSE.duplicate()

## Captain, 2026-10-18 (his Star Citizen reference, B:/Contractor-refs/captures/2026-10-18): stance
## changes as moves, not pose snaps. Going prone the hands go out to the floor ahead and take the
## weight (a dive); getting up they push off it. STANCE_MOVE_S long, the hands on the floor over
## the STANCE_PLANT_* share of it, HANDS_AHEAD in front of the hips and HANDS_APART across.
const STANCE_MOVE_S := 0.7
const STANCE_PLANT_DOWN := Vector2(0.05, 0.75)
const STANCE_PLANT_UP := Vector2(0.0, 0.6)
const HANDS_AHEAD := 0.5
const HANDS_APART := 0.22
## Hands go to the floor only while the shoulders are this low over it (m): higher, the arms
## couldn't reach (getting up, the body rises out of the push).
const PLANT_REACH := 0.8
## Getting up goes through a kneel (RISE_KNEEL, hands on the floor) for the first RISE_KNEEL_SHARE
## of the move, then stands: easing straight from prone to standing pivoted him up like a plank.
const RISE_KNEEL := {"hip": 0.42, "hip_x": 0.0, "hip_z": 0.12, "pitch": -0.75, "roll": 0.0, "prone": false, "prone_roll": 0.0}
const RISE_KNEEL_SHARE := 0.45
var _was_prone := false
var _stance_move := &""   # &"down" (going prone), &"up" (getting up), &"" none
var _stance_t := 99.0
## The rifle's carry on the move (the same reference): jogging or sprinting, not aiming, it drops
## muzzle-down along the body, both hands still on it (GearRig.held_transform's `run`; Captain,
## 2026-10-18, v0.4.43: a one-handed carry looked wrong on the AI). Eased 0..1.
const RUN_CARRY_EASE := 4.0
var _run_carry := 0.0
## A shot's kick (CharacterModel.kick, from every peer's tracer: CompoundLevel.show_tracer): the
## held weapon jumps back and up by GearRig.KICK_* and settles over 1 / KICK_DECAY seconds.
const KICK_DECAY := 9.0
var _kick := 0.0
## Reloading: how far the weapon is rolled and brought in to work the magazine (GearRig), eased 0..1.
const RELOAD_EASE := 7.0
var _reload_w := 0.0
## Replicated (the body's ServerSync; set on the host by server_carry): {"mode": CARRY,
## DRAG, CARRIED or DRAGGED, "with": the other body's node path}, or {} for neither.
var carry_net: Dictionary = {}
## Replicated (the body's ServerSync; set on the host by server_play, server_stop): the
## hand action now, {} for none: "id" (PICK_UP, EQUIP, LOOT, TREAT), "n" (bumps with each
## action, which restarts the clip on every peer), "s" (seconds), "at" (body-space point the
## hands work at), "from" and "to" (MOUNT_POINTS keys the right hand goes to in turn),
## "kneel" and, treating, "tech" (TECHNIQUES). The host clears a finished clip, so late
## joiners don't replay it.
var action_net: Dictionary = {}
## Replicated (the body's ServerSync; set on the host by Ragdoll): a downed or dead AI body's
## ragdoll pose, RAGDOLL_BONES in order, each its origin and rotation (a quaternion) in model
## space, or empty for none. While set, the lying body is drawn (and its hitboxes posed) from
## it instead of the fixed downed pose.
var ragdoll_net := PackedFloat32Array()

var torso: Node3D
var head: Node3D
var hands_anchor: Node3D
var _root: Node3D
var _upper: Array[Node3D] = []    # [right, left]
var _forearm: Array[Node3D] = []  # [right, left]
var _leg_left: Node3D
var _leg_right: Node3D
var _shin_left: Node3D
var _shin_right: Node3D
## Feet (Feet, 2026-10-21): a foot on each ankle, [left, right], pitched each drawn frame to the
## ground: flat when planted, the heel striking with the toes up and the heel lifting off the
## bent toes walking; the toes tucked under where the foot can't lie flat (kneeling on that knee,
## prone); relaxed when down. FOOT_EASE: how fast it follows (per second).
const FOOT_EASE := 22.0
var _feet: Array[Node3D] = []
var _foot_style := Feet.BOOTS
var _ankle: Array[float] = [0.0, 0.0]
var _toes: Array[bool] = [false, false]
var _foot_meshes: Dictionary = {}  # the foot meshes this model put on (a carved or copied one isn't)
var _held: Node3D
var _grip := Vector3.ZERO     # right hand, in _held's local space
var _support := Vector3.ZERO  # left hand, in _held's local space
## Reloading, the support hand works the held weapon's magazine here (VoxelArt.reload_points'
## "mag", in _held's local space: behind the grip on the L85), found once per weapon.
var _reload_mag := Vector3.ZERO
var _reload_mag_of := 0
var _reload_pts := {}  # all the held weapon's VoxelArt.reload_points
## While a reload's keys play, the held weapon is drawn without its magazine and the magazines are
## parts of their own (VoxelArt.MAG): the weapon so drawn, its own mesh to put back, the old
## magazine and the new.
var _split_held: MeshInstance3D
var _split_whole: Mesh
var _mag_parts: Array[Node3D] = []
## Near the view (LOD every frame), a reload that works the action or a feed cover draws the
## weapon with none of its moving parts (VoxelArt.FIXED) and those parts of their own: the
## action (VoxelArt.BOLT), the feed cover (COVER), and how they move (VoxelArt.part_motion).
var _bolt_part: Node3D
var _cover_part: Node3D
var _part_motion: Dictionary = {}
var _lod_shown_every := 1  # the level of detail's frames between draws, as last found
var _last_position: Vector3
var _move_dt := 0.0  # time since the body last moved (MOVE_WINDOW_S)
var _speed := 0.0
## Breathing (the torso's rise and fall): rate and depth multipliers, 1 at rest; the body's
## owner raises them as the legs tire (Soldier._process, MovementRules.ANIM_BREATH_*).
var breath_rate := 1.0
var breath_depth := 1.0
var _breath_t := 0.0
var _time := 0.0
var _shown: Dictionary = {}   # bone -> Transform3D, easing towards the pose
var _yaw_shown := 0.0         # the drawn body's turn (pose "yaw"), eased with the bones
var _twist_shown := 0.0       # the drawn upper body's twist (pose "twist"), eased with the bones
var _last_pose: Dictionary = {}  # the stance pose last aimed for, with its action applied
var _action_n := -1           # action_net["n"] last seen
var _action_t := 0.0          # seconds since that action started (local clock)
var _reaching: Dictionary = {}   # the reaching pose for the current action ({} for none)
var _server_n := 0            # host: action serials handed out
var _props: TreatProps        # what's in the hands while treating (made on the first treatment)
var _treat_rest: Dictionary = {}  # action_net "site" plus its "bone" and "patient" (CharacterModel)
var _treat_self := 0          # treating your own arm one-handed: 1 the right is hurt, -1 the left
var _site_t: Dictionary = {}  # _treat_goals: the live site in torso space while the hands resolve
var _treat_eye_w := 0.0       # first person: how much of the kneel and bend the eye follows, eased
var _view_hands := false      # first person: forearms and props on the view's layer
var _draw_point := Vector3.ZERO  # torso-local: where the weapon being drawn sits
var _draw_t := -1.0           # seconds into a weapon draw (< 0: none)
var _held_weapon := false     # what's held is a weapon (set_held)
var _aim_w := 0.0             # 0 at the ready .. 1 shouldered, eased
var _attach := 0.0            # 0..1: how far the drawn casualty has moved onto its carrier
var _carry_key := ""          # carry_net's mode, phase and serial last seen
var _carry_t := 0.0           # seconds since that changed (local clock)
var _carry_reach: Dictionary = {}  # the kneeling pose for this pick-up or put-down
var _attached := Transform3D.IDENTITY  # where its carrier holds it (world space)
var _hand_source: Array[String] = ["", ""]
var _hand_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_blend: Array[float] = [1.0, 1.0]
var _arms_posed := false
var _carrier_worn := false
var _gait_phase := 0.0          # 0..1 through the cycle: the left foot lands at 0, the right at 0.5
var _move := Vector3.ZERO       # ground velocity in the model's space (m/s), eased
var _gait_w := 0.0              # how much the cycle shows over the stance pose, 0..1
var _gait := &"idle"
var _gait_lean := 0.0
var _gait_bob := 0.0            # the hips' bob this frame (m)
## Fingers (HandPose, 2026-10-20): each forearm's mesh is its hand in a pose, swapped as the hand's
## work changes (the firing grip on a weapon, the support grip, a magazine in a reload, a held
## object, open, relaxed, pointing, a fist). The forearm rolls about its own axis so the palm faces
## what it holds, and the IK puts the pose's grasp centre on the goal. A shot squeezes the trigger
## for PRESS_S; the index stays on the trigger while aiming or TRIGGER_HOLD_S after a shot, and
## lies straight along the frame otherwise. Far off (LOD_FAR) the squeeze isn't drawn.
const PRESS_S := 0.09
const TRIGGER_HOLD_S := 1.2
## How fast the forearm rolls round to its grip (per second, eased), and how far it can (radians
## either way: a forearm turns about a quarter turn each way from palm-in).
const ROLL_EASE := 14.0
const ROLL_MAX := 1.75
var _hand_shown: Array[StringName] = [HandPose.RELAXED, HandPose.RELAXED]
var _hand_override: Array[StringName] = [&"", &""]
var _hand_mesh: Array[Mesh] = [null, null]  # the forearm meshes this model last put on
var _hand_meshes: Dictionary = {}  # every pose mesh it has put on (a carved one is BodyDeform's)
var _hand_anchor: Array[Node3D] = []
var _hands_bare := false
var _roll: Array[float] = [0.0, 0.0]
var _press_t := 0.0
var _shot_t := 99.0
## Level of detail on (tests drawing a body by hand turn it off).
var lod := true
var _lod_n := 0
var _lod_dt := 0.0
var _boxes_downed := false  # the downed state the hitboxes were last posed in (pose_hitboxes)


## A heavy exo's size (ExoMech.size; GearRig sets it): the whole body, its gear, plates and
## hitboxes drawn this big while it's piloted, 0 for its own.
var suit_size := 0.0


## How big this body is drawn: a heavy exo's size, else FEMALE_SCALE for a female soldier (1 a
## male), times his own height (SoldierLook.height_of). Joints, gear and hitboxes scale with it.
func body_scale() -> float:
	if suit_size > 0.0:
		return suit_size
	return (FEMALE_SCALE if body == VoxelArt.FEMALE else 1.0) * _height


## How broad the part `part` (a VoxelArt body part: "torso", "upper_arm", ...) is drawn for his
## build (SoldierLook.girth_of): the trunk by the build's girth, the upper limbs half as much
## and the lower a third (bone doesn't thicken), the head not at all. Only the part's mesh is
## widened and deepened about its own axis: the joints stay put, so poses, IK and hitboxes are
## the same for every build (BodyVolume widens the trunk's hit shape to match, GIRTH_META).
func girth(part: String) -> float:
	var g := _girth
	match part.get_slice(":", 0).trim_suffix(VoxelArt.FEMALE_SUFFIX):  # ("forearm:grip:", "shin:boots": posed and styled parts)
		"torso", "torso_fc":
			return g
		"upper_arm", "thigh":
			return 1.0 + (g - 1.0) * 0.5
		"forearm", "shin":
			return 1.0 + (g - 1.0) * 0.33
	return 1.0


## The hitbox meta BodyVolume reads for a trunk this much broader (x, z) than the model's.
const GIRTH_META := &"girth"


## Gives this body the look `code` (a SoldierLook code): his own head and face, his height and
## build. Works before or after the body is built (Soldier hands it on as it replicates).
func set_face(code: String) -> void:
	face = code
	if not is_node_ready():
		return
	transform = base_transform()
	if variant == "dummy":  # a target dummy: a mannequin's plain head, no face at work
		(head.get_child(0) as MeshInstance3D).mesh = VoxelArt.mesh(VoxelArt.body_part("head", body), variant)
		return
	if face_rig == null:
		face_rig = FaceRig.new()
		face_rig.name = "FaceRig"
		add_child(face_rig)
	face_rig.setup(self, face if face != "" else SoldierLook.DEFAULT)
	_apply_girth()


## A helmet whose ear covers or nape guard come down over long hair is on (or off): the head's
## hair goes flat under it (FaceArt.tucked), and back as it was without.
func set_hair_tucked(on: bool) -> void:
	if on == hair_tucked:
		return
	hair_tucked = on
	if face_rig and is_node_ready():
		face_rig.setup(self, face if face != "" else SoldierLook.DEFAULT)


## Widens each body part's mesh for the build (girth), and tells the trunk's hitboxes.
func _apply_girth() -> void:
	var parts: Array[Node3D] = [torso, _leg_left, _leg_right, _shin_left, _shin_right]
	parts.append_array(_upper)
	parts.append_array(_forearm)
	for pivot in parts:
		if pivot == null:
			continue
		var mi := pivot.get_child(0) as MeshInstance3D
		var model_name := String(pivot.get_meta(&"voxel_model", ""))
		if mi == null or model_name == "":
			continue
		var g := girth(model_name)
		if not mi.has_meta(&"base"):
			mi.set_meta(&"base", [mi.position, mi.scale])
		var base: Array = mi.get_meta(&"base")
		var wide := Vector3(g, 1.0, g)
		mi.position = (base[0] as Vector3) * wide
		mi.scale = (base[1] as Vector3) * wide
	var body_node := get_parent()
	if body_node:
		var g := girth("torso")
		for area in _posable_hitboxes(body_node):
			if area.get_meta(&"body_part", &"") in [Vitals.CHEST, Vitals.ABDOMEN, Vitals.PELVIS, Vitals.TORSO]:
				area.set_meta(GIRTH_META, Vector3(g, 1.0, g))


## He calls out (a callout, an order, a scream): mouth open, brows down, for `seconds`.
func shout(seconds := 1.2) -> void:
	_shout_until = maxf(_shout_until, Soldier._now() + seconds)


## Whether he's calling out now (shout).
func shouting() -> bool:
	return Soldier._now() < _shout_until


## Another player's body drawn smoothed between network updates (Soldier._smooth_remote,
## RemoteSmoother): where the model sits off the body, body-local. Identity otherwise.
var net_offset := Transform3D.IDENTITY


## The model's own transform when nothing moves it: its size (body_scale), moved by net_offset,
## and, pushing up out of lying face down in a heavy exo (MECH_RISE), turned onto its front.
func base_transform() -> Transform3D:
	if action_shown() == MECH_RISE:
		var u := action_progress()
		var to_knees := smoothstep(0.45, 0.65, u)   # flat on its front -> propped on its knees
		var to_stand := smoothstep(0.78, 0.95, u)   # holds on its knees, then finishes standing
		var pitch := lerpf(lerpf(-PI / 2.0, MECH_KNEEL_PITCH, to_knees), 0.0, to_stand)
		var lift := ExoMech.LIE_LIFT * clampf(-pitch / (PI / 2.0), 0.0, 1.0)
		var turn := Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.UP * lift)
		return net_offset * turn * Transform3D(Basis.from_scale(Vector3.ONE * body_scale()), Vector3.ZERO)
	return net_offset * Transform3D(Basis.from_scale(Vector3.ONE * body_scale()), Vector3.ZERO)


## A plate carrier is on (or off) this body: a woman's torso is then the one held flat by it
## ("torso_fc", her bust pressed flat and out to the sides, as a real carrier does) or her own.
func set_carrier_worn(worn: bool) -> void:
	if body != VoxelArt.FEMALE or torso == null or _carrier_worn == worn:
		return
	_carrier_worn = worn
	var mesh := torso.get_child(0) as MeshInstance3D  # VoxelArt.instance's mesh, its first child
	if mesh:
		mesh.mesh = VoxelArt.mesh("torso_fc" if worn else VoxelArt.body_part("torso", body), variant)


## The right shoulder joint, torso-local (mirrored for the left), for this body.
func shoulder() -> Vector3:
	return shoulder_of(body)


## The right shoulder joint, torso-local, for body type `body_type`: SHOULDER, or for a female
## soldier FEMALE_SHOULDER.
static func shoulder_of(body_type: String) -> Vector3:
	return FEMALE_SHOULDER if body_type == VoxelArt.FEMALE else SHOULDER


func _ready() -> void:
	transform = base_transform()
	_root = Node3D.new()
	add_child(_root)
	torso = _part("torso", _root, TORSO_PIVOT)
	head = VoxelArt.instance(SoldierLook.head_model(face, body), variant, render_layers, false)  # FaceRig builds its mesh
	head.position = HEAD_PIVOT
	torso.add_child(head)
	hands_anchor = Node3D.new()
	hands_anchor.position = HANDS_ANCHOR
	torso.add_child(hands_anchor)
	_hands_bare = VoxelArt.hands_bare(variant)
	for side in [1.0, -1.0]:
		var upper := _part("upper_arm", torso, shoulder() * Vector3(side, 1, 1))
		_upper.append(upper)
		var left: bool = side < 0.0
		var fore := VoxelArt.instance(HandPose.model(HandPose.RELAXED, left, _hands_bare, body), variant, render_layers)
		fore.position = Vector3(0, -UPPER_ARM, 0)
		upper.add_child(fore)
		_forearm.append(fore)
		var mi := fore.get_child(0) as MeshInstance3D
		_hand_mesh[_forearm.size() - 1] = mi.mesh
		_hand_meshes[mi.mesh] = true
		var anchor := Node3D.new()  # a held prop's place in the hand (hand_anchor)
		anchor.name = "HandAnchor"
		anchor.transform = HandPose.grasp(HandPose.RELAXED, left, body == VoxelArt.FEMALE)
		fore.add_child(anchor)
		_hand_anchor.append(anchor)
	_leg_left = _part("thigh", _root, HIP * Vector3(-1, 1, 1))
	_leg_right = _part("thigh", _root, HIP)
	_foot_style = Feet.style_of(variant)
	_shin_left = _shin_part(_leg_left, true)
	_shin_right = _shin_part(_leg_right, false)
	_last_position = global_position
	_shown = pose_bones(REST_POSE, false)
	set_face(face)
	var body := get_parent()
	if body:
		for area in _posable_hitboxes(body):
			_rest_of(area)  # recorded before anything moves them
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals:
			var marks := WoundMarks.new()
			marks.name = "WoundMarks"
			add_child(marks)
			marks.setup(self, vitals)
			var deform := BodyDeform.new()  # holes carved out of the parts themselves
			deform.name = "BodyDeform"
			add_child(deform)
			deform.setup(self, vitals)


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
	# Perf pass (2026-10-22): drawn every few frames (far off or behind the view, _lod_every), the
	# hitboxes follow on the frames it's drawn, as its arms do; going down or up poses them at once.
	if lod and _lod_shown_every > 1 and _lod_n != 0 and downed == _boxes_downed:
		return
	_boxes_downed = downed
	var bones := with_shins(_target_bones(_carry_state()))
	var rest := with_shins(rest_bones())
	var deltas := {}
	for key: String in ["torso", "head", "pelvis", "leg_l", "leg_r", "shin_l", "shin_r"]:
		deltas[key] = transform * (bones.root as Transform3D) * (bones[key] as Transform3D) * (rest[key] as Transform3D).affine_inverse()
	for area in _posable_hitboxes(body):
		var bone := _bone_of(area)
		var target: Transform3D
		if deltas.has(bone):
			target = deltas[bone] * _rest_of(area)
		else:
			target = _arm_delta(area, bone) * _rest_of(area)
		if not area.transform.is_equal_approx(target):
			area.transform = target


## The arms' hitboxes follow the arms as drawn (Captain, 2026-10-21: "fingers and arms cant be hit"):
## the IK on a weapon's grip and handguard, a reload, a carry, a ragdoll. Before, they hung at the
## sides in the rest pose with the chest's turn, wherever the arms were, so a round at the drawn
## arm met no arm box and one where it hung met an arm that wasn't there. The forearm's box also
## carries the hand's pose model ("part_model": BodyVolume marches the drawn hand). On a woman the
## boxes, drawn for the male shoulder, sit on her own (FEMALE_SHOULDER).
const ARM_BONES := {&"upper_arm_l": "arm_l", &"upper_arm_r": "arm_r", &"forearm_l": "fore_l", &"forearm_r": "fore_r"}


func _arm_delta(area: Area3D, bone: String) -> Transform3D:
	var i := 0 if bone.ends_with("_r") else 1
	var fore := bone.begins_with("fore")
	if _upper.size() < 2 or _forearm.size() < 2 or not is_inside_tree():
		return transform
	var node: Node3D = _forearm[i] if fore else _upper[i]
	var side := Vector3(1.0 if i == 0 else -1.0, 1, 1)
	var down := Vector3(0, UPPER_ARM, 0) if fore else Vector3.ZERO
	var pivot := TORSO_PIVOT + shoulder() * side - down
	if not area.has_meta(&"arm_fit"):
		area.set_meta(&"arm_fit", true)
		var shift := (shoulder() - SHOULDER) * side  # her shoulder in from his
		if not shift.is_zero_approx():
			for child in area.get_children():
				if child is CollisionShape3D:
					(child as CollisionShape3D).position += shift
	if fore:
		var m := String(node.get_meta(&"voxel_model", ""))
		if String(area.get_meta(&"part_model", "")) != m:
			area.set_meta(&"part_model", m)
	var drawn := global_transform.affine_inverse() * node.global_transform  # model space, unscaled
	return transform * drawn * Transform3D(Basis(), pivot).affine_inverse()


## `bones` plus "shin_l" and "shin_r": each shin's pivot (the knee), root-local.
static func with_shins(bones: Dictionary) -> Dictionary:
	var out := bones.duplicate()
	out["shin_l"] = (bones.leg_l as Transform3D) * (bones.knee_l as Transform3D)
	out["shin_r"] = (bones.leg_r as Transform3D) * (bones.knee_r as Transform3D)
	return out


## Thigh swing (radians forward from straight down) and knee bend for a leg whose hip is
## `hip` above the ground with the foot `foot` metres forward of it (negative: behind).
## Two bones of equal length; the knee points forward.
static func _leg_angles(hip: float, foot: float) -> Vector2:
	var reach := minf(Vector2(foot, hip).length(), LEG_LENGTH - 0.0001)
	var fold := acos(clampf(reach / LEG_LENGTH, 0.0, 1.0))
	return Vector2(atan2(foot, hip) + fold, 2.0 * fold)


## A knee bone: the shin's pivot THIGH down the thigh, folded back by `bend` radians.
static func _knee(bend: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -bend), Vector3(0, -THIGH, 0))


## Model-space transforms for a pose: "root" (whole body), and root-local "torso", "head"
## (kept level with the ground, like the drawn head), "pelvis", "leg_l" and "leg_r" (joint pivots), and
## "knee_l" and "knee_r" (each shin's pivot in its thigh's space).
static func pose_bones(p: Dictionary, is_downed: bool) -> Dictionary:
	if is_downed:
		var rest := rest_bones()
		rest["root"] = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, DOWNED_LIFT, 0))
		return rest
	if p.get("board", false):
		return _boarding_bones(p)
	if p.get("seated", false):
		return _seated_bones(p)
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
	var drop := maxf(LEG_LENGTH - hip, 0.0)
	var front := _leg_angles(hip, drop * FRONT_FOOT) if spread == 0.0 else Vector2.ZERO
	var back := _leg_angles(hip, -drop * BACK_FOOT) if spread == 0.0 else Vector2.ZERO
	var roll_by: float = p.get("roll", 0.0)
	var pitch_by: float = p.get("pitch", 0.0)
	var twist: float = p.get("twist", 0.0)
	var torso_basis := Basis(Vector3.BACK, roll_by) * Basis(Vector3.RIGHT, pitch_by) * Basis(Vector3.UP, twist)
	var torso := Transform3D(torso_basis, Vector3(hip_x, hip, hip_z))
	# The head turns back against the twist, so it faces the way the body does.
	var head_basis := Basis(Vector3.UP, -twist) * Basis(Vector3.RIGHT, -_upper_body_pitch(root.basis * torso_basis, yaw))
	return {
		"root": root,
		"torso": torso,
		"head": torso * Transform3D(head_basis, HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), Vector3(hip_x, hip, hip_z)),
		"leg_l": Transform3D(Basis(Vector3.BACK, -spread) * Basis(Vector3.RIGHT, front.x), Vector3(hip_x - HIP.x, hip, hip_z)),
		"leg_r": Transform3D(Basis(Vector3.BACK, spread) * Basis(Vector3.RIGHT, back.x), Vector3(hip_x + HIP.x, hip, hip_z)),
		"knee_l": _knee(front.y),
		"knee_r": _knee(back.y),
	}


## A seated pose (SEAT_*): the hip joint `hip` above the body's origin and the floor `floor_y`
## (both body space, metres); `station`: a driver's, pilot's or gunner's seat (hands on the
## controls, no rifle in them). Its "yaw" turns the drawn body to face the seat
## (Vehicle._place_occupants keeps it up to date).
static func seated_pose(hip: float, floor_y: float, station: bool) -> Dictionary:
	return {"seated": true, "station": station, "hip": hip, "floor": floor_y, "hip_x": 0.0, "hip_z": SEAT_HIP_BACK,
		"pitch": SEAT_PITCH, "roll": 0.0, "prone": false, "prone_roll": 0.0, "yaw": 0.0}


## pose_bones for a seated pose: the thighs forward off the cushion and the shins down to the
## floor (two-bone, knees forward and turned out a little), the upper body leaning on its pitch.
static func _seated_bones(p: Dictionary) -> Dictionary:
	var hip: float = p.get("hip", SEAT_HEIGHT)
	var hip_z: float = p.get("hip_z", SEAT_HIP_BACK)
	var floor_y: float = p.get("floor", hip - SEAT_HEIGHT)
	var yaw: float = p.get("yaw", 0.0)
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var leg := _leg_angles(maxf(hip - floor_y - SEAT_SOLE_UP, 0.05), float(p.get("foot", SEAT_FOOT)))  # "foot": a sill rider's hang (Vehicle)
	var torso_basis := Basis(Vector3.RIGHT, float(p.get("pitch", SEAT_PITCH)))
	var torso := Transform3D(torso_basis, Vector3(0, hip, hip_z))
	var head_basis := Basis(Vector3.RIGHT, -_upper_body_pitch(root.basis * torso_basis, yaw))
	return {
		"root": root,
		"torso": torso,
		"head": torso * Transform3D(head_basis, HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), Vector3(0, hip, hip_z)),
		"leg_l": Transform3D(Basis(Vector3.UP, SEAT_KNEE_SPLAY) * Basis(Vector3.RIGHT, leg.x), Vector3(-HIP.x, hip, hip_z)),
		"leg_r": Transform3D(Basis(Vector3.UP, -SEAT_KNEE_SPLAY) * Basis(Vector3.RIGHT, leg.x), Vector3(HIP.x, hip, hip_z)),
		"knee_l": _knee(leg.y),
		"knee_r": _knee(leg.y),
	}


## pose_bones for a boarding pose (Vehicle._board_pose): standing on two feet placed anywhere
## ("foot_l" and "foot_r": Vector2(forward of, and up from, the body's origin) of each sole),
## the hips "hip" up (no higher than both legs reach), leaning on "pitch", turned "yaw", and
## "sit" of the way into the seated pose "into" (both from the same origin).
static func _boarding_bones(p: Dictionary) -> Dictionary:
	var yaw: float = p.get("yaw", 0.0)
	var feet: Array[Vector2] = [p.get("foot_l", Vector2.ZERO), p.get("foot_r", Vector2.ZERO)]
	var hip: float = p.get("hip", LEG_LENGTH)
	var hip_z: float = p.get("hip_z", 0.0)
	for f in feet:
		var reach := f.x + hip_z
		hip = minf(hip, f.y + sqrt(maxf(LEG_LENGTH * LEG_LENGTH - reach * reach, 0.0)) - BOARD_HIP_SAG)
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var torso_basis := Basis(Vector3.RIGHT, float(p.get("pitch", 0.0)))
	var torso := Transform3D(torso_basis, Vector3(0, hip, hip_z))
	var head_basis := Basis(Vector3.RIGHT, -_upper_body_pitch(root.basis * torso_basis, yaw))
	var left := _leg_angles(maxf(hip - feet[0].y, 0.05), feet[0].x + hip_z)
	var right := _leg_angles(maxf(hip - feet[1].y, 0.05), feet[1].x + hip_z)
	var out := {
		"root": root,
		"torso": torso,
		"head": torso * Transform3D(head_basis, HEAD_PIVOT),
		"pelvis": Transform3D(Basis(), Vector3(0, hip, hip_z)),
		"leg_l": Transform3D(Basis(Vector3.RIGHT, left.x), Vector3(-HIP.x, hip, hip_z)),
		"leg_r": Transform3D(Basis(Vector3.RIGHT, right.x), Vector3(HIP.x, hip, hip_z)),
		"knee_l": _knee(left.y),
		"knee_r": _knee(right.y),
	}
	var sit: float = p.get("sit", 0.0)
	if sit > 0.0 and p.has("into"):
		var seated := pose_bones(p.into, false)  # a seat, or a kneeling spot (another of these)
		for key: String in out:
			out[key] = (out[key] as Transform3D).interpolate_with(seated[key], sit)
	return out


## Being placed by a vehicle's boarding clip (Vehicle._board_pose): drawn from its pose as is,
## not eased, the legs where it puts them.
func is_boarding() -> bool:
	return bool(pose.get("board", false))


## Seconds into the action playing now, or -1 with none.
func action_seconds() -> float:
	return _action_t if _action_active() else -1.0


## Whether the body is drawn seated (in a vehicle's seat).
func is_seated() -> bool:
	return bool(pose.get("seated", false))


## Seated in a fire-from-vehicle seat (Vehicle._seated_pose_for "ffv"; Captain, 2026-10-17:
## "characters sit in the ffv seats like this", "scopes dont work in ffv"): the weapon is held
## and aimed as standing (head, hands and sights follow the look), only the legs sit.
func is_ffv() -> bool:
	return is_seated() and bool(pose.get("ffv", false))


## Seated: how far the hip joint is above the floor (GearRig keeps a rifle's muzzle off it).
func seat_room() -> float:
	return float(pose.get("hip", SEAT_HEIGHT)) - float(pose.get("floor", 0.0))


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
		place = Basis(Vector3.UP, CARRY_YAW) * Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
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
		"knee_l": _knee(legs * 0.7),
		"knee_r": _knee(legs * 0.6 + 0.05),
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
		"knee_l": _knee(0.0),
		"knee_r": _knee(0.0),
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
## takes. Prone stays prone (the hands just reach). With `turn` false (treating yourself:
## the point is on your own body) it doesn't turn.
static func reach_pose(base: Dictionary, point: Vector3, kneel: bool, turn := true, body_type := "") -> Dictionary:
	var sh := shoulder_of(body_type)
	if base.get("prone", false):
		return {}
	var flat := Vector2(point.x, point.z)
	var turned := turn and flat.length() > REACH_TURN_MIN
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
			var shoulder_up := hip + sh.y * cos(bend)
			var shoulder_ahead := sh.y * sin(bend) - back
			var lateral := sh.x - HAND_SPREAD
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
	if b.has("twist"):  # (treating your own arm turns the upper body to it)
		out["twist"] = lerpf(float(a.get("twist", 0.0)), float(b.twist), w)
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


## The firing hand goes to `grip` and the other to `support`, given in `node`'s local space
## (the right hand fires, or the left for a left-handed shooter). `weapon`: a weapon, held
## shouldered or at the ready, so the support shoulder comes forward (SUPPORT_REACH); false
## for a bulky item carried in both arms.
func set_held(node: Node3D, grip: Vector3, support: Vector3, weapon := true) -> void:
	_held = node
	_grip = grip
	_support = support
	_held_weapon = weapon
	if is_instance_valid(node) and node.get_instance_id() != _reload_mag_of:
		_reload_mag_of = node.get_instance_id()
		var points := VoxelArt.reload_points(String(node.get_meta(&"voxel_model", ""))) if node.has_meta(&"voxel_model") else {}
		_reload_mag = points.get("mag", grip.lerp(support, 0.35) + Vector3(0, -0.07, 0))
		_reload_pts = points


func clear_held() -> void:
	_held = null


## Global position of a hand (for tests and tools): where it holds what it holds (its pose's grasp
## centre, HandPose.reach_point), or its palm's centre when open or empty.
func hand_position(right: bool) -> Vector3:
	var i := 0 if right else 1
	return _forearm[i].to_global(HandPose.reach_point(_hand_shown[i], i == 1, body == VoxelArt.FEMALE))


## The pose hand `hand` (0 the right, 1 the left) is drawn in now (HandPose.POSES).
func hand_pose(hand: int) -> StringName:
	return _hand_shown[hand]


## Holds hand `hand` (0 right, 1 left) in pose `pose` (HandPose.POSES) whatever it's doing, until
## called again with &"" (its own pose by what it's doing, again). For whoever puts something in
## the hand (a treatment's prop): parent it to hand_anchor().
func set_hand_pose(hand: int, pose_name: StringName) -> void:
	_hand_override[hand] = pose_name if HandPose.TABLE.has(pose_name) else &""


## A node in hand `hand` (0 right, 1 left), at its pose's grasp centre: +y along what it holds,
## +z out of the palm (HandPose.grasp). A held prop parented to it follows the hand.
func hand_anchor(hand: int) -> Node3D:
	return _hand_anchor[hand]


## Largest palm-to-target distance in metres while holding something; -1 if nothing is held.
func hand_error() -> float:
	if not is_instance_valid(_held):
		return -1.0
	var lefty := left_handed and _held_weapon
	return maxf(hand_position(not lefty).distance_to(_held.to_global(_grip)),
		hand_position(lefty).distance_to(_held.to_global(_support)))


# --- Actions: what peers see ------------------------------------------------------------

## The carry this model shows now: {"mode", "body" (the other body), "model" (its
## CharacterModel)}, or {} for none. A casualty's side only shows while it's down.
func carry_shown() -> Dictionary:
	return _carry_state()


## The hand action playing now (an action_net id), or &"" for none.
func action_shown() -> StringName:
	return StringName(action_net.get("id", &"")) if _action_active() else &""


## How far through the action playing now (0..1), or -1 with none.
func action_progress() -> float:
	if not _action_active():
		return -1.0
	var s := float(action_net.get("s", 0.0))
	return clampf(_action_t / s, 0.0, 1.0) if s > 0.0 else 0.0


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
## `phase` (&"lift", &"grab", &"lower" or &"" for holding) plays over `seconds` on both bodies
## (each from when it hears of it: carry_phase).
static func server_carry(carrier: Node, casualty: Node, mode: StringName, phase := &"", seconds := 0.0) -> void:
	var carrier_model := _model_of(carrier)
	var casualty_model := _model_of(casualty)
	_carry_serial += 1
	var timing := {"phase": phase, "s": seconds, "n": _carry_serial} if phase != &"" else {}
	if carrier_model:
		carrier_model.carry_net = {} if mode == &"" else \
			{"mode": mode, "with": String(casualty.get_path()) if casualty else ""}.merged(timing)
	if casualty_model:
		casualty_model.carry_net = {} if mode == &"" else {"mode": DRAGGED if mode == DRAG else CARRIED,
			"with": String(carrier.get_path()) if carrier else ""}.merged(timing)


static var _carry_serial := 0


## The pick-up, take-hold or put-down playing now: {"phase", "u" (0..1 through it)}, or {}
## while just holding (or nothing).
func carry_phase() -> Dictionary:
	var phase := StringName(carry_net.get("phase", &""))
	var s := float(carry_net.get("s", 0.0))
	if phase == &"" or s <= 0.0:
		return {}
	return {"phase": phase, "u": clampf(_carry_t / s, 0.0, 1.0)}


## 0..1: how far down on one knee the carrier is, picking a body up or putting it down (the
## first-person camera dips with it: SoldierMovement).
func carry_kneel() -> float:
	var ph := carry_phase()
	if ph.is_empty() or StringName(carry_net.get("mode", &"")) != CARRY:
		return 0.0
	var u: float = ph.u
	return smoothstep(0.0, KNEEL.x, u) * (1.0 - smoothstep(KNEEL.y, 1.0, u))


## 0..1: how far a carried or dragged casualty is drawn in its carrier's hold (0: lying where
## its own body is), from the phase playing.
static func _hold_weight(phase: StringName, u: float) -> float:
	match phase:
		&"lift":
			return smoothstep(LIFT_RISE.x, LIFT_RISE.y, u)
		&"lower":
			return 1.0 - smoothstep(LOWER_FALL.x, LOWER_FALL.y, u)
		&"grab":
			return smoothstep(GRAB_RISE.x, GRAB_RISE.y, u)
	return 1.0


## Host only. Starts hand action `id` for every peer (see action_net); returns its serial
## (for server_stop). `at` is a body-space point (reach_point keeps it within reach).
func server_play(id: StringName, seconds: float, at := Vector3.ZERO, from := &"", to := &"", kneel := false, tech := &"") -> int:
	_server_n += 1
	action_net = {"id": id, "n": _server_n, "s": seconds, "at": reach_point(at), "from": from, "to": to, "kneel": kneel, "tech": tech}
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
		"attach", "move_attachment":
			from = CONTAINER_MOUNTS.get(container, &"pouch")
			to = &"carrier"
		"detach":
			from = &"carrier"
			to = CONTAINER_MOUNTS.get(target, &"pouch")
		"drop_attachment":
			from = &"carrier"
			to = &"ground"
		"attach_slot":  # the launcher off the shoulder, onto the top of the pack
			from = SLOT_MOUNTS.get(slot, &"pouch")
			to = &"pack"
		"equip_attachment":  # a packed launcher off the top of the pack, onto the shoulder
			var att := inventory.attachment(slot)
			if att.is_empty():
				return
			from = &"pack"
			to = mount_for_item(ItemDB.get_item(StringName(att.id)))
		_:
			return
	server_play(EQUIP, EQUIP_S, Vector3.ZERO, from, to)


## Host only. Looting `body` (one item, or everything with `all`): kneel at it, hands on it,
## then into a pouch.
func server_loot(body: Node3D, all := false) -> void:
	var point: Vector3 = body.call(&"aim_point") if body.has_method(&"aim_point") else body.global_position + Vector3.UP * 0.2
	server_play(LOOT, LOOT_ALL_S if all else LOOT_S, to_local(point), &"", &"pouch", true)


## Host only. Treating `part` of `target` (this body or another) for `seconds` with `item`:
## kneeling beside another (not yourself), hands working at the wound with that item's
## technique (TECHNIQUES): a tourniquet high and tight above the wound, a needle up at the
## second intercostal space. Returns the serial to stop it with.
func server_treat(target: Node3D, part: StringName, seconds: float, item := &"") -> int:
	var tech: StringName = TECHNIQUES.get(item, WORK)
	# Where on the casualty (TreatProps.rest_site: the wound's own skin, or the technique's spot),
	# sent with the clip so every peer works on the same place, followed live on the casualty's bone.
	var site := TreatProps.rest_site(target, part, tech, get_parent())
	var at := part_position(target, part)
	if not site.is_empty():
		at = TreatProps.site_world(site, _model_of(target))
	elif tech == &"tourniquet":
		at += (part_position(target, &"chest") - at).normalized() * TOURNIQUET_HIGH  # towards the trunk
	elif tech == &"needle":
		at += (part_position(target, &"head") - at).normalized() * NEEDLE_HIGH
	if target == get_parent() and _part_bone(target, part) == "torso":
		at = _unbladed(at)  # the hands leave the rifle, so the upper body squares up first
	var serial := server_play(TREAT, seconds, to_local(at), &"", &"", target != get_parent(), tech)
	action_net = action_net.merged({"target": String(target.get_path()), "part": part, "item": item, "site": site})
	return serial


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


## The model's node (bone) for body part `part`, its origin at the part's joint
## (BodyVolume.pivot_at in the rest pose), or null.
func part_node(part: StringName) -> Node3D:
	match part:
		Vitals.HEAD, Vitals.FACE, Vitals.NECK:
			return head
		Vitals.CHEST, Vitals.ABDOMEN, Vitals.PELVIS, Vitals.TORSO:
			return torso
		Vitals.UPPER_ARM_R:
			return _upper[0]
		Vitals.UPPER_ARM_L:
			return _upper[1]
		Vitals.FOREARM_R:
			return _forearm[0]
		Vitals.FOREARM_L:
			return _forearm[1]
		Vitals.THIGH_L:
			return _leg_left
		Vitals.THIGH_R:
			return _leg_right
		Vitals.SHIN_L:
			return _shin_left
		Vitals.SHIN_R:
			return _shin_right
	return null


## Which bone (see _bone_of) body part `part` of `body` follows; "torso" if it has no hitbox.
static func _part_bone(body: Node3D, part: StringName) -> String:
	for area in _posable_hitboxes(body):
		if area.get_meta(&"body_part", &"") == part:
			return _bone_of(area)
	return "torso"


## A point on this body's upper body (world space, as posed now) where it will be once the
## bladed stance lets go (the upper body turned square again).
func _unbladed(world: Vector3) -> Vector3:
	if float(_last_pose.get("twist", 0.0)) == 0.0:
		return world
	var square := _last_pose.duplicate()
	square.erase("twist")
	var from := pose_bones(_last_pose, false)
	var to := pose_bones(square, false)
	var move := ((to.root as Transform3D) * (to.torso as Transform3D)) * ((from.root as Transform3D) * (from.torso as Transform3D)).affine_inverse()
	return to_global(move * to_local(world))


static func _model_of(body: Node) -> CharacterModel:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(^"Model") as CharacterModel


## A shin drawn for this body's footwear (Feet.shin_model) under the knee, and its foot on the
## ankle (Feet.ANKLE).
func _shin_part(thigh: Node3D, left: bool) -> Node3D:
	var shin := VoxelArt.instance(Feet.shin_model(_foot_style, body), variant, render_layers)
	shin.position = Vector3(0, -THIGH, 0)
	thigh.add_child(shin)
	var foot := VoxelArt.instance(Feet.model(_foot_style, left, false, body), variant, render_layers)
	foot.name = "Foot"
	foot.position = Feet.ANKLE
	shin.add_child(foot)
	_feet.append(foot)
	_foot_meshes[(foot.get_child(0) as MeshInstance3D).mesh] = true
	return shin


func _part(model: String, parent: Node3D, pivot: Vector3) -> Node3D:
	var node := VoxelArt.instance(VoxelArt.body_part(model, body), variant, render_layers)
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
	elif part == Vitals.THIGH_L:
		bone = "leg_l"
	elif part == Vitals.THIGH_R:
		bone = "leg_r"
	elif part == Vitals.SHIN_L:
		bone = "shin_l"
	elif part == Vitals.SHIN_R:
		bone = "shin_r"
	elif ARM_BONES.has(part):
		bone = ARM_BONES[part]
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


func _process(frame_delta: float) -> void:
	# Level of detail: far off or behind the view, drawn every few frames.
	_lod_dt += frame_delta
	_lod_n += 1
	_lod_shown_every = _lod_every() if lod else 1
	if _lod_n < _lod_shown_every:
		return
	_lod_n = 0
	var delta := _lod_dt
	_lod_dt = 0.0
	# Speed from position change works the same for local, remote and AI bodies; measured in
	# the model's own space (its turn and scale), so strides match what the model is drawn at.
	var moved := global_position - _last_position
	moved.y = 0.0
	_move_dt += delta
	if moved.length_squared() > 1e-8 or _move_dt >= MOVE_WINDOW_S:
		_last_position = global_position
		var vel := global_transform.basis.inverse() * (moved / maxf(_move_dt, 0.0001))
		vel.y = 0.0
		if vel.length() > MAX_SPEED * 1.5:
			vel = Vector3.ZERO  # placed, not walked
		_move = _move.lerp(vel, minf(_move_dt * GAIT_EASE, 1.0))
		_speed = _move.length()
		_move_dt = 0.0
	_time += delta
	_pose_reload_mags()
	var carry_key := "%s/%s/%s" % [carry_net.get("mode", ""), carry_net.get("phase", ""), carry_net.get("n", 0)]
	if carry_key != _carry_key:
		_carry_key = carry_key
		_carry_t = 0.0
		_carry_reach = {}
	else:
		_carry_t += delta
	_update_action(delta)
	_update_stance_move(delta)
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
	var limp := downed and not casualty and ragdolled()  # the physics moves it: no easing
	## Seated: no easing either. The seat turns the drawn body against the body's own turn
	## (a rider looking round), and eased the two would swing it about the seat.
	var seated := (is_seated() or is_boarding()) and not casualty
	var blend := 1.0 if limp or seated else minf(delta * (ACTION_EASE if acting else POSE_EASE), 1.0)
	if downed != _was_downed:
		_was_downed = downed
		_downed_t = 0.0
	_downed_t += delta
	if downed and not casualty and not limp and _downed_t < SLUMP_S:
		blend = minf(delta * SLUMP_EASE, 1.0)  # sinking down (Captain: wounded/dying anims), not a snap
	for key: String in target:
		_shown[key] = (_shown[key] as Transform3D).interpolate_with(target[key], blend)
	var target_yaw := 0.0 if casualty or downed else float(_last_pose.get("yaw", 0.0))
	_yaw_shown = lerp_angle(_yaw_shown, target_yaw, blend)
	var target_twist := 0.0 if casualty or downed else float(_last_pose.get("twist", 0.0))
	_twist_shown = lerpf(_twist_shown, target_twist, blend)
	var prone: bool = pose.get("prone", false)
	# seated: the vehicle moves him, the legs don't walk (Captain, 2026-10-14)
	var still := downed or casualty or seated
	var swing := 0.0
	if still:
		_gait = IDLE
		_gait_w = 0.0
		_gait_lean = 0.0
		_gait_bob = 0.0
		_root.transform = _shown.root
		_leg_left.transform = _shown.leg_l
		_leg_right.transform = _shown.leg_r
		_shin_left.transform = _shown.knee_l
		_shin_right.transform = _shown.knee_r
	elif prone:
		swing = _crawl(delta)
	else:
		swing = _walk(delta)
	_breath_t = fmod(_breath_t + delta * 2.0 * breath_rate, TAU * 64.0)
	var torso_t := (_shown.torso as Transform3D).translated_local(Vector3(0, sin(_breath_t) * 0.003 * breath_depth, 0))  # breathing
	if _gait_lean != 0.0 or swing != 0.0:
		# Leaning into the pace, the shoulders turning a little against the stride.
		torso_t.basis = torso_t.basis * Basis(Vector3.RIGHT, -_gait_lean) * Basis(Vector3.UP, -swing * 0.12)
	torso.transform = torso_t
	if casualty:
		# Limp: the head hangs (carried) or lolls back (dragged) with the body.
		head.rotation = Vector3(-CARRY_HEAD_DROOP if mode == CARRIED else DRAG_HEAD_LOLL, 0, 0)
		hands_anchor.rotation = Vector3.ZERO
	elif limp:
		head.transform = (_shown.torso as Transform3D).affine_inverse() * (_shown.head as Transform3D)
		hands_anchor.rotation = Vector3.ZERO
	else:
		# Head and weapon keep facing where the owner looks, whatever the upper body's lean
		# and twist (rotation.y, applied outside the pitch: the turn the torso's twist undoes).
		# Back on its pivot with no roll: a ragdoll (limp, above) set the whole transform, and
		# only pitch and yaw are set here (Captain, 2026-10-17: "woke up from being down, head
		# sideways").
		head.position = HEAD_PIVOT
		head.rotation.z = 0.0
		head.rotation.y = -_twist_shown
		hands_anchor.rotation.y = -_twist_shown
		var lean := 0.0 if downed else _upper_body_pitch((_shown.root as Transform3D).basis * (_shown.torso as Transform3D).basis, _yaw_shown) - _gait_lean
		_aim_w = move_toward(_aim_w, 1.0 if aiming and _held_weapon and is_instance_valid(_held) else 0.0, delta * 6.0)
		head.rotation.x = clampf(look_pitch, -0.7, 0.7) * 0.8 - lean - AIM_HEAD_DIP * smoothstep(0.0, 1.0, _aim_w)
		hands_anchor.rotation.x = clampf(look_pitch, -0.8, 0.8) * 0.8 - lean
		if seated and not is_ffv():
			# The rifle stands between the knees whichever way he looks; slumped, the head hangs.
			hands_anchor.rotation.x = 0.0
			if downed:
				head.rotation.x = -SEAT_HEAD_DROOP
	_update_arms(delta, carry, swing)
	_wounded_extras(delta)
	_update_feet(delta, casualty or limp or downed)
	_treat_reactions(delta)
	if is_instance_valid(_props):
		_props.update(delta)  # what's in the hands, now the arms are where they are this frame


## Locomotion: the gait cycle at ground speed (see GAIT_*), blended over the stance pose by
## how fast the body moves. Returns the free arms' swing (radians, the right arm forward).
func _walk(delta: float) -> float:
	var v := _speed
	var w := smoothstep(GAIT_IN.x, GAIT_IN.y, v)
	_gait_w = w
	var leg_l: Transform3D = _shown.leg_l
	var leg_r: Transform3D = _shown.leg_r
	var hip0 := leg_l.origin.y
	var high := clampf((hip0 - CROUCH_GAIT_HIP) / 0.25, 0.0, 1.0)  # 0 crouched .. 1 standing
	var duty := _gait_at(GAIT_DUTY, v)
	var lift := _gait_at(GAIT_LIFT, v) * (0.5 + 0.5 * high)
	var bob := (GAIT_BOB + GAIT_BOB_RUN * clampf(v / GAIT_SPEED[4], 0.0, 1.0)) * high
	var drop := _gait_at(GAIT_DROP, v) * high
	var hz := gait_hz(v, hip0 - drop * w + bob * w, duty)
	var half := duty * v / hz * 0.5
	_gait_phase = fposmod(_gait_phase + delta * hz, 1.0)
	if w <= 0.0:
		_gait = IDLE
	elif high < 0.5:
		_gait = CROUCH_WALK
	else:
		_gait = WALK if v < JOG_AT else (JOG if v < SPRINT_AT else SPRINT)
	# Hips: up over the planted leg walking, down onto it running (twice a cycle).
	var run := smoothstep(1.5, 2.5, v)
	_gait_bob = bob * lerpf(1.0, -1.0, run) * cos(TAU * 2.0 * (_gait_phase - duty * 0.5)) * w
	var dy := _gait_bob - drop * w
	_gait_lean = _gait_at(GAIT_LEAN, v) * w * high
	var root: Transform3D = _shown.root
	_root.transform = root.translated(Vector3(0, dy, 0))
	if w <= 0.0:
		_leg_left.transform = leg_l
		_leg_right.transform = leg_r
		_shin_left.transform = _shown.knee_l
		_shin_right.transform = _shown.knee_r
		return 0.0
	# The way it moves, in the root's space (an action may turn the drawn body).
	var dir := root.basis.inverse() * _move
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	# Strafing: the legs turn part way towards the movement (backwards: towards its reverse).
	var turn := atan2(-dir.x, -dir.z)
	if turn > PI * 0.5:
		turn -= PI
	elif turn < -PI * 0.5:
		turn += PI
	var yaw_b := Basis(Vector3.UP, turn * GAIT_HIP_TURN * w)
	var centre := Vector3((leg_l.origin.x + leg_r.origin.x) * 0.5, 0.0, (leg_l.origin.z + leg_r.origin.z) * 0.5)
	for i in 2:
		var base: Transform3D = leg_l if i == 0 else leg_r
		var q := fposmod(_gait_phase - 0.5 * i, 1.0)
		var along := 0.0
		var up := 0.0
		if q < duty:
			along = half * (1.0 - 2.0 * q / duty)  # planted: moving back at ground speed
		else:
			var s := (q - duty) / (1.0 - duty)
			along = -half + 2.0 * half * (0.5 - 0.5 * cos(PI * s))
			up = lift * sin(PI * s)
		var pivot := base.origin - centre
		pivot.y = 0.0
		pivot = centre + yaw_b * pivot
		pivot.y = base.origin.y
		# Hip to foot (root space, the ground `dy` below the root): the foot on the ground under
		# the hip, `along` the way it moves.
		var to_foot := Vector3(dir.x * along, up - pivot.y - dy, dir.z * along)
		var d := yaw_b.inverse() * to_foot
		var roll := atan2(d.x, -d.y)
		var a := _leg_angles(Vector2(d.x, d.y).length(), -d.z)
		var gait_leg := Transform3D(yaw_b * Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, a.x), pivot)
		var knee := _knee(a.y)
		if i == 0:
			_leg_left.transform = base.interpolate_with(gait_leg, w)
			_shin_left.transform = (_shown.knee_l as Transform3D).interpolate_with(knee, w)
		else:
			_leg_right.transform = base.interpolate_with(gait_leg, w)
			_shin_right.transform = (_shown.knee_r as Transform3D).interpolate_with(knee, w)
	# Arms swing against the legs: the right forward as the left foot lands.
	return cos(TAU * _gait_phase) * _gait_at(GAIT_ARM, v) * w


## Prone: a crawl, one knee drawn up and out each half cycle (CRAWL_*). Returns the free
## arms' swing.
func _crawl(delta: float) -> float:
	var v := _speed
	var w := smoothstep(0.05, 0.3, v)
	_gait_w = w
	_gait = CRAWL if w > 0.0 else IDLE
	_gait_lean = 0.0
	_gait_bob = 0.0
	_gait_phase = fposmod(_gait_phase + delta * v / CRAWL_STRIDE, 1.0)
	_root.transform = _shown.root
	var draw := sin(TAU * _gait_phase) * w
	var left := maxf(draw, 0.0)
	var right := maxf(-draw, 0.0)
	_leg_left.transform = (_shown.leg_l as Transform3D) * Transform3D(Basis(Vector3.BACK, -CRAWL_SPLAY * left) * Basis(Vector3.RIGHT, CRAWL_THIGH * left), Vector3.ZERO)
	_leg_right.transform = (_shown.leg_r as Transform3D) * Transform3D(Basis(Vector3.BACK, CRAWL_SPLAY * right) * Basis(Vector3.RIGHT, CRAWL_THIGH * right), Vector3.ZERO)
	_shin_left.transform = (_shown.knee_l as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -CRAWL_KNEE * left), Vector3.ZERO)
	_shin_right.transform = (_shown.knee_r as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -CRAWL_KNEE * right), Vector3.ZERO)
	return draw * 0.6


## Cycles a second at ground speed `v` for hips `hip` above the ground (at their highest) and
## a foot down `duty` of the cycle: GAIT_HZ, or faster where a planted foot would otherwise
## have to reach further than the leg does.
static func gait_hz(v: float, hip: float, duty: float) -> float:
	var reach := LEG_LENGTH * 0.995
	var half_max := sqrt(maxf(reach * reach - hip * hip, 0.0004))
	return maxf(_gait_at(GAIT_HZ, v), duty * v / (2.0 * half_max))


## `table` (one value per GAIT_SPEED anchor) at speed `v`, straight between anchors.
static func _gait_at(table: Array[float], v: float) -> float:
	var last := GAIT_SPEED.size() - 1
	for i in last:
		if v < GAIT_SPEED[i + 1]:
			return lerpf(table[i], table[i + 1], (maxf(v, 0.0) - GAIT_SPEED[i]) / (GAIT_SPEED[i + 1] - GAIT_SPEED[i]))
	return table[last]


## The cycle the legs show: IDLE, WALK, JOG, SPRINT, CROUCH_WALK or CRAWL.
func gait() -> StringName:
	return _gait


## 0..1 through the gait cycle (the left foot lands at 0, the right at 0.5).
func gait_phase() -> float:
	return _gait_phase


## How much the cycle shows (0 standing still .. 1 at pace).
func gait_weight() -> float:
	return _gait_w


## The hips' bob this frame (m, up), the view's to follow.
func gait_bob() -> float:
	return _gait_bob


## The ground speed the legs are walking at (m/s, the model's space).
func gait_speed() -> float:
	return _speed


## Each foot's pitch on its ankle (_feet): the ground-relative pitch it wants (walking: by the
## gait's phase; else flat), turned into the ankle's angle under its shin's own pitch; where the
## ankle can't flatten it (the shin laid back: kneeling on that knee, prone), the toes tucked
## under and the foot up on them. `limp`: down, dead or carried: relaxed, the toes pointing a little.
func _update_feet(delta: float, limp: bool) -> void:
	var up := global_basis.orthonormalized()
	var duty := _gait_at(GAIT_DUTY, _speed)
	for i in 2:
		var shin := _shin_left if i == 0 else _shin_right
		var want := 0.0
		var toes := false
		var ankle := -0.3
		if not limp:
			var walking := _gait_w > 0.0 and _gait != CRAWL and _gait != IDLE
			if walking:
				want = _gait_foot(fposmod(_gait_phase - 0.5 * i, 1.0), duty) * _gait_w
			var f := up.inverse() * (shin.global_basis.orthonormalized() * Vector3.FORWARD)
			var shin_pitch := atan2(f.y, Vector2(f.x, f.z).length())  # its own forward's tilt to the ground
			if want - shin_pitch > Feet.ANKLE_MAX + 0.25:
				want = Feet.TUCK_PITCH  # can't lie flat: up on the tucked toes
				toes = true
			elif walking and want < -0.2 and fposmod(_gait_phase - 0.5 * i, 1.0) < duty:
				toes = true  # the heel off the ground, the foot rolling over its toes
			ankle = Feet.ankle_for(want, shin_pitch)
		_ankle[i] = lerpf(_ankle[i], ankle, minf(delta * FOOT_EASE, 1.0))
		_feet[i].transform.basis = Basis(Vector3.RIGHT, _ankle[i])
		_show_toes(i, toes)


## The foot's pitch to the ground (radians, + the toes up) at `q` through its own gait cycle (0:
## the heel strikes) with it on the ground `duty` of it: the toes up as the heel lands, flat,
## the heel rising onto the toes to push off, the toes down as it leaves and coming up to land.
static func _gait_foot(q: float, duty: float) -> float:
	if q < duty:
		var s := q / maxf(duty, 0.01)
		if s < Feet.STRIKE_SHARE:
			return lerpf(Feet.STRIKE_PITCH, 0.0, s / Feet.STRIKE_SHARE)
		if s > Feet.ROLL_FROM:
			return lerpf(0.0, Feet.PUSH_PITCH, (s - Feet.ROLL_FROM) / (1.0 - Feet.ROLL_FROM))
		return 0.0
	var w := (q - duty) / maxf(1.0 - duty, 0.01)
	if w < 0.35:
		return lerpf(Feet.PUSH_PITCH, Feet.SWING_PITCH, w / 0.35)
	return lerpf(Feet.SWING_PITCH, Feet.STRIKE_PITCH, (w - 0.35) / 0.65)


## Foot `i`'s mesh with its toes bent up or not (Feet.model "t"), unless it's no longer one of
## this model's own (carved, or gone with a severed leg).
func _show_toes(i: int, toes: bool) -> void:
	if toes == _toes[i]:
		return
	var mi := _feet[i].get_child(0) as MeshInstance3D if _feet[i].get_child_count() > 0 else null
	if mi == null or not _foot_meshes.has(mi.mesh):
		return
	var m := Feet.model(_foot_style, i == 0, toes, body)
	mi.mesh = VoxelArt.mesh(m, variant)
	_foot_meshes[mi.mesh] = true
	_feet[i].set_meta(&"voxel_model", m)
	_toes[i] = toes


## Tests: foot `left`'s node, its pitch to the ground now (radians, + the toes up, in the body's
## own upright frame) and whether its toes are bent.
func foot_node(left: bool) -> Node3D:
	return _feet[0 if left else 1]


func foot_pitch(left: bool) -> float:
	var f := global_basis.orthonormalized().inverse() * (foot_node(left).global_basis.orthonormalized() * Vector3.FORWARD)
	return atan2(f.y, Vector2(f.x, f.z).length())


func foot_toes(left: bool) -> bool:
	return _toes[0 if left else 1]


## The sole of a foot (world space): the bottom of its shin.
func foot_position(left: bool) -> Vector3:
	var shin := _shin_left if left else _shin_right
	return shin.global_transform * Vector3(0, -(LEG_LENGTH - THIGH), 0)


## Frames between draws for this body (level of detail): every frame near the view, fewer far
## off or behind it; every frame with no 3D view.
func _lod_every() -> int:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if camera == null:
		return 1
	var to := global_position - camera.global_position
	var d2 := to.length_squared()
	if d2 < LOD_NEAR_M * LOD_NEAR_M:
		return 1
	if d2 > LOD_FAR_M * LOD_FAR_M or to.dot(-camera.global_basis.z) < 0.0:
		return LOD_FAR
	return LOD_MID


## The parts a ragdoll pose holds, in order: the bones it stands in for (the pelvis rides the
## torso), then the arms (upper arm and forearm, right first, like _upper and _forearm).
const RAGDOLL_BONES: Array[String] = ["torso", "head", "leg_l", "leg_r", "shin_l", "shin_r",
	"arm_r", "arm_l", "fore_r", "fore_l"]


## Whether the body lies as a ragdoll (ragdoll_net holds a pose).
func ragdolled() -> bool:
	return ragdoll_net.size() == RAGDOLL_BONES.size() * 7


## Each ragdoll part's model-space transform (RAGDOLL_BONES keys), from ragdoll_net.
func ragdoll_parts() -> Dictionary:
	var t := {}
	for i in RAGDOLL_BONES.size():
		var o := i * 7
		var q := Quaternion(ragdoll_net[o + 3], ragdoll_net[o + 4], ragdoll_net[o + 5], ragdoll_net[o + 6]).normalized()
		t[RAGDOLL_BONES[i]] = Transform3D(Basis(q), Vector3(ragdoll_net[o], ragdoll_net[o + 1], ragdoll_net[o + 2]))
	return t


## Model-space bone transforms (keys as pose_bones) from ragdoll_net.
func ragdoll_bones() -> Dictionary:
	var t := ragdoll_parts()
	return {"root": Transform3D.IDENTITY, "torso": t.torso, "head": t.head, "pelvis": t.torso,
		"leg_l": t.leg_l, "leg_r": t.leg_r,
		"knee_l": (t.leg_l as Transform3D).affine_inverse() * t.shin_l,
		"knee_r": (t.leg_r as Transform3D).affine_inverse() * t.shin_r}


## Packs model-space bone transforms (RAGDOLL_BONES keys) into ragdoll_net's layout.
static func pack_ragdoll(bones: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for key in RAGDOLL_BONES:
		var t: Transform3D = bones[key]
		var q := t.basis.orthonormalized().get_rotation_quaternion()
		out.append_array(PackedFloat32Array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]))
	return out


## The bones the drawn body is heading for: a casualty's, lying down, or the stance with
## whatever the hands are doing applied.
func _target_bones(carry: Dictionary) -> Dictionary:
	var mode: StringName = carry.get("mode", &"")
	if mode == CARRIED or mode == DRAGGED:
		var ph := carry_phase()
		if ph.is_empty() or _hold_weight(ph.phase, ph.u) > 0.05:
			return casualty_bones(mode)
		# Still on the ground (not yet lifted, or already put down): lying as it fell.
	if downed and is_seated():
		var slumped := pose.duplicate()  # down or dead in a seat: slumped in it, not lying across it
		slumped["pitch"] = SEAT_SLUMP
		return pose_bones(slumped, false)
	if downed and ragdolled():
		return ragdoll_bones()
	if downed:
		return pose_bones(pose, true)
	_last_pose = _bladed(_action_pose(mode), mode)
	return pose_bones(_last_pose, false)


## `p` with the bladed stance (twist, BLADE) while a rifle is held two-handed, at the ready or
## aiming: standing or crouched, the hands free of carries and actions.
func _bladed(p: Dictionary, mode: StringName) -> Dictionary:
	if hold != Hold.BOTH or not _held_weapon or not is_instance_valid(_held) or downed \
			or p.get("prone", false) or p.get("seated", false) or mode != &"" or _action_active():
		return p
	var out := p.duplicate()
	out["twist"] = blade_twist(left_handed)
	return out


## The bladed stance's twist (radians about the torso's up axis): the support shoulder
## forward, so a right-handed shooter (left shoulder forward) turns right (negative).
static func blade_twist(left: bool) -> float:
	return BLADE if left else -BLADE


## The drawn upper body's twist now (eased; 0 unless bladed). GearRig keeps the rifle butt
## on the chest with it.
func twist_shown() -> float:
	return _twist_shown


## The stance pose with the current action applied: the drag crouch (facing the
## casualty), the carry lean, or bending or kneeling to reach.
func _action_pose(mode: StringName) -> Dictionary:
	var prone: bool = pose.get("prone", false)
	var ph := carry_phase()
	if mode == DRAG and not prone:
		if not ph.is_empty() and ph.phase == &"grab":
			return blend_pose(pose, DRAG_POSE, smoothstep(0.0, 0.6, ph.u))
		return DRAG_POSE
	if mode == CARRY:
		if prone:
			return pose
		var leaning := pose.duplicate()
		leaning["pitch"] = float(pose.get("pitch", 0.0)) + CARRY_LEAN
		var k := carry_kneel()
		if k <= 0.0:
			return leaning
		if _carry_reach.is_empty():
			# Down on one knee by the body (where it lies, or where it's going), facing it.
			var other := _carry_state().get("body") as Node3D
			var at := to_local(other.global_position) if other else Vector3(0, 0, -0.8)
			_carry_reach = reach_pose(pose, at + Vector3(0, 0.25, 0), true, true, body)
		return blend_pose(leaning, _carry_reach, k) if not _carry_reach.is_empty() else leaning
	var clip := action_shown()
	if clip == MECH_IN or clip == MECH_OUT:
		# A step up into the suit (or down out of it): a dip at the knees, then up again, while
		# the body walks back into it (or forward out of it).
		var u := action_progress()
		var stepping := pose.duplicate()
		var hip := float(pose.get("hip", REST_POSE.hip)) - sin(clampf((u - 0.05) / 0.4, 0.0, 1.0) * PI) * MECH_DIP
		if clip == MECH_OUT:  # (in, the suit hangs on these same bones: it never walks)
			stepping["hip_z"] = float(pose.get("hip_z", 0.0)) - MECH_STEP * (1.0 - smoothstep(0.1, 0.8, u))
			hip += MECH_STEP_UP * (1.0 - smoothstep(0.25, 0.65, u))
		stepping["hip"] = hip
		return stepping
	if clip == MECH_RISE:
		# Knees-first (base_transform's pitch): the hip sits low, as if kneeling, once it's up
		# off the ground, then rises back to standing height as it finishes getting up.
		var u := action_progress()
		var up_on_knees := smoothstep(0.45, 0.65, u)
		var to_stand := smoothstep(0.78, 0.95, u)
		var rising := pose.duplicate()
		var rest_hip := float(pose.get("hip", REST_POSE.hip))
		rising["hip"] = lerpf(rest_hip, lerpf(rest_hip * 0.5, rest_hip, to_stand), up_on_knees)
		return rising
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
		MECH_RELEASE:
			w = _envelope(_action_t, s, REACH_RISE_S, REACH_FALL_S)
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
		var id := StringName(action_net.get("id", &""))
		if id == TREAT:
			_begin_treat()
		if id in [PICK_UP, LOOT, TREAT, MECH_RELEASE]:
			var kneel := bool(action_net.get("kneel", false))
			# Treating without a kneel is treating yourself (server_treat): no turning to it.
			_reaching = reach_pose(pose, action_net.get("at", Vector3.ZERO), kneel, id != TREAT or kneel, body)
			if id == TREAT and not kneel:
				_reaching = _self_treat_pose(_reaching)
		return
	_action_t += delta
	_treat_eye_w = move_toward(_treat_eye_w, 1.0 if action_shown() == TREAT else 0.0, delta / 0.25)
	if action_shown() == TREAT and bool(action_net.get("kneel", false)):
		# Kneeling to someone else: turned and bent to where the wound is now (they may shift, or
		# you turn while you work), not where it was when you started.
		var live := treat_site()
		if not live.is_empty():
			_reaching = reach_pose(pose, reach_point(to_local(live.p)), true, true, body)
	var s := float(action_net.get("s", 0.0))
	if s > 0.0 and _action_t > s + 0.25 and not action_net.is_empty() and is_inside_tree() and multiplayer.is_server():
		action_net = {}


## A treatment starting (every peer, from action_net): where on whom (the site on the patient's
## bone), whether it's your own arm (one-handed), and the props' node.
func _begin_treat() -> void:
	_treat_rest = {}
	_treat_self = 0
	var target := _treat_target()
	var patient := _model_of(target)
	var site: Dictionary = action_net.get("site", {})
	if patient and not site.is_empty():
		var bone := patient.part_node(StringName(site.get("part", &"")))
		if bone:
			_treat_rest = site.merged({"bone": bone, "patient": patient})
	var part := String(action_net.get("part", ""))
	if target == get_parent() and (part.begins_with("upper_arm") or part.begins_with("forearm")):
		_treat_self = -1 if part.ends_with("_l") else 1
	if not is_instance_valid(_props):
		_props = TreatProps.new()
		_props.name = "TreatProps"
		_props.model = self
		add_child(_props)


## Treating yourself: your own arm, the upper body turned to the hurt arm held out in front (the
## other hand works one-handed: _action_goals); your own leg (anything but an injector, which goes
## into the thigh standing), down on a knee bent over it. Otherwise `reaching` as it is.
func _self_treat_pose(reaching: Dictionary) -> Dictionary:
	if bool(pose.get("prone", false)):
		return reaching
	if _treat_self != 0:
		var turned := pose.duplicate()
		turned["twist"] = -_treat_self * SELF_ARM_TWIST
		turned["pitch"] = float(pose.get("pitch", 0.0)) - 0.1
		return turned
	var part := String(action_net.get("part", ""))
	if (part.begins_with("thigh") or part.begins_with("shin")) and StringName(action_net.get("tech", WORK)) != &"inject":
		var kneel := reach_pose(pose, action_net.get("at", Vector3.ZERO), true, false, body)
		if not kneel.is_empty():
			kneel["pitch"] = minf(float(kneel.pitch), SELF_LEG_PITCH)
			return kneel
	return reaching


## The body being treated (this one, or another), or null.
func _treat_target() -> Node3D:
	var path := String(action_net.get("target", ""))
	return get_node_or_null(NodePath(path)) as Node3D if path != "" and is_inside_tree() else null


## Where the treatment is now (world space), or {} without one: "p" the point on the skin, "n" out
## of it, "a" along the limb towards the trunk (up the body off the limbs), "r" the limb's radius
## there (0 off the limbs), "part" the body part, "x" more spots ([point, normal]: defib pads). It
## follows the patient's bone as drawn (the CPR push taken back out: treat_react).
func treat_site() -> Dictionary:
	if _treat_rest.is_empty() or action_shown() != TREAT:
		return {}
	var bone: Variant = _treat_rest.get("bone")
	var patient: Variant = _treat_rest.get("patient")
	if not is_instance_valid(bone) or not is_instance_valid(patient):
		return {}
	var g := (bone as Node3D).global_transform
	var shift: Vector3 = (patient as CharacterModel)._react_shift
	var extra: Array = []
	for spot: Array in _treat_rest.get("x", []):
		extra.append([g * Vector3(spot[0]) - shift, (g.basis * Vector3(spot[1])).normalized()])
	return {"p": g * Vector3(_treat_rest.p) - shift, "n": (g.basis * Vector3(_treat_rest.n)).normalized(),
		"a": (g.basis * Vector3.UP).normalized(), "r": float(_treat_rest.get("r", 0.0)) * g.basis.get_scale().x,
		"part": StringName(_treat_rest.get("part", &"")), "x": extra}


## The treatment playing now, for TreatProps: "tech", "item", "t" (seconds in), "s" (its length),
## "u" (0..1), "n" (its serial), "site" (treat_site), "patient" (CharacterModel or null), "work"
## and "help" (the hands: 0 right, 1 left; help -1 one-handed). {} when not treating.
func treat_state() -> Dictionary:
	if action_shown() != TREAT:
		return {}
	var patient: Variant = _treat_rest.get("patient")
	return {"tech": StringName(action_net.get("tech", WORK)), "item": StringName(action_net.get("item", &"")),
		"t": _action_t, "s": float(action_net.get("s", 0.0)), "u": action_progress(), "n": int(action_net.get("n", -1)),
		"site": treat_site(), "patient": patient if is_instance_valid(patient) else null,
		"work": 1 if _treat_self == 1 else 0, "help": -1 if _treat_self != 0 else 1}


## The tourniquet's windlass over a clip `s` long: the seconds it turns between (after the strap,
## until CLIP_S before the end), how many whole turns it takes (about WINDLASS_HZ), and how far
## it has turned `t` seconds in (radians; a last quarter turn lays the rod into its clip).
static func windlass_span(s: float) -> Vector2:
	return Vector2(s * STRAP_END, maxf(s - CLIP_S, s * STRAP_END + 0.1))


static func windlass_turns(s: float) -> int:
	var span := windlass_span(s)
	return maxi(1, roundi((span.y - span.x) * WINDLASS_HZ))


static func windlass_angle(t: float, s: float) -> float:
	var span := windlass_span(s)
	var turning := clampf((t - span.x) / (span.y - span.x), 0.0, 1.0)
	return TAU * windlass_turns(s) * turning + PI * 0.5 * smoothstep(span.y, maxf(s, span.y + 0.01), t)


## The windlass rod at the site (point `p` on the skin, `n` out of it, `a` up the limb), turned
## `angle`: {"c": its centre, on the band's base plate, "d": along it}.
static func windlass_rod(p: Vector3, n: Vector3, a: Vector3, angle: float) -> Dictionary:
	var across := a.cross(n)
	across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
	return {"c": p + n * 0.02, "d": across.rotated(n.normalized(), angle)}


## CPR, `t` seconds in: how far the chest is pushed in now (0..COMPRESSION_M), about 110 a minute.
static func cpr_compression(t: float) -> float:
	return COMPRESSION_M * (0.5 - 0.5 * sin(TAU * CPR_HZ * t))


## Held props (TreatProps): the fingers' grasp centre (hand_anchor) where the fingers exist, else a
## node at each palm (HELD_AT, on the forearm), with the forearm's axes: -y along the fingers, +z out of the palm (the working
## side: facing down when the hand reaches out to work), x across the knuckles (the thumb at -x on
## the right hand, +x on the left).
func held_anchor(right: bool) -> Node3D:
	if has_method(&"hand_anchor"):  # the fingers' grasp centre (+y along what's held), where it exists
		var grasp: Variant = call(&"hand_anchor", 0 if right else 1)
		if grasp is Node3D:
			return grasp
	var arm := _forearm[0 if right else 1]
	var anchor := arm.get_node_or_null(^"HeldProp") as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = "HeldProp"
		anchor.position = HELD_AT
		arm.add_child(anchor)
	return anchor


## What hand `right` (or the left) holds now (a TreatProps prop), or null. Its "grip" meta is how
## far the fingers close round it (m from the grip's middle).
func held_prop(right: bool) -> Node3D:
	for child in held_anchor(right).get_children():
		if child is Node3D and (child as Node3D).visible and not child.is_queued_for_deletion():
			return child
	return null


## First person (PlayerInput, the local player only): while `on`, the forearms and what they hold
## go on the view's layer too (VIEW_HANDS_LAYER), so your own hands show working on the wound.
func set_view_hands(on: bool) -> void:
	_view_hands = on
	for arm in _forearm:
		var mesh := arm.get_child(0) as MeshInstance3D if arm.get_child_count() > 0 else null
		var want := render_layers | (VIEW_HANDS_LAYER if on else 0)
		if mesh and mesh.layers != want:
			mesh.layers = want
	if is_instance_valid(_props):
		_props.view_hands = on


func view_hands_shown() -> bool:
	return _view_hands


## First person while treating (PlayerInput): how far the eye moves (body space, before the body's
## scale) with the drawn body's kneel and bend, so you look down at your hands from where the head is.
func treat_view_offset() -> Vector3:
	if _treat_eye_w <= 0.0 or not _shown.has("torso"):
		return Vector3.ZERO
	var drawn: Transform3D = (_shown.root as Transform3D) * (_shown.torso as Transform3D)
	return (drawn * EYE - eye_position(pose)) * smoothstep(0.0, 1.0, _treat_eye_w)


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
	var ph := carry_phase() if on else {}
	var w: float
	if ph.is_empty():
		_attach = move_toward(_attach, 1.0 if on else 0.0, delta / ATTACH_S)
		w = smoothstep(0.0, 1.0, _attach)
	else:
		w = _hold_weight(ph.phase, ph.u)  # timed with the carrier kneeling and standing
		_attach = w
	if w <= 0.0 or parent == null:
		if transform != base_transform():
			transform = base_transform()
		return
	var held := parent.global_transform.affine_inverse() * _attached
	transform = base_transform().interpolate_with(held * Transform3D(Basis.from_scale(Vector3.ONE * body_scale()), Vector3.ZERO), w)


## Arms: each hand goes to its goal (blending from where it was when the goal changes), or
## swings free.
var _arms_ragdolled := false  # _update_arms: the ragdoll had the arms last frame


func _update_arms(delta: float, carry: Dictionary, swing: float) -> void:
	var mode: StringName = carry.get("mode", &"")
	if downed and ragdolled() and mode != CARRIED and mode != DRAGGED:
		# Lying as a ragdoll: the arms are its parts (in model space; the torso's root is identity).
		var parts := ragdoll_parts()
		var torso_t := torso.transform
		for i in 2:
			var side := "r" if i == 0 else "l"
			var arm: Transform3D = parts["arm_" + side]
			_upper[i].transform = torso_t.affine_inverse() * arm
			_forearm[i].transform = arm.affine_inverse() * (parts["fore_" + side] as Transform3D)
			_show_hand(i, HandPose.RELAXED)
		_arms_ragdolled = true
		return
	if _arms_ragdolled:
		# Out of the ragdoll: its parts set the arms' whole transforms; back on their joints at
		# once (the rest below only turns them, and the shoulders would ease back for seconds).
		_arms_ragdolled = false
		for i in 2:
			_upper[i].position = shoulder() * Vector3(1.0 if i == 0 else -1.0, 1, 1)
			_forearm[i].position = Vector3(0, -UPPER_ARM, 0)
	var goals := _arm_goals(carry)
	_place_shoulders(delta)
	_press_t -= delta
	_shot_t += delta
	for i in 2:
		var key: String = goals[i][0]
		var point: Variant = goals[i][1]
		_show_hand(i, _hand_override[i] if _hand_override[i] != &"" else _goal_pose(i, key))
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
				_roll[i] = lerpf(_roll[i], 0.0, minf(delta * ROLL_EASE, 1.0))
				_upper[i].transform.basis = upper
				_forearm[i].transform.basis = fore * Basis(Vector3.UP, _roll[i])
				continue
			point = _upper[i].position + upper * (Vector3(0, -UPPER_ARM, 0) + fore * Vector3(0, -FOREARM, 0))
		_reach_hand(i, _hand_from[i].lerp(point, w), _palm_want(i, key), delta)
	_arms_posed = true


## The pose for hand `i` at arm goal `key` (_arm_goals): on a weapon, the firing grip (GRIP, TRIGGER
## while aiming or just after a shot, PRESS as one goes) or the support grip (SUPPORT; in a reload,
## by the anchor the hand is at: HandPose.RELOAD_POSES); holding anything else, HOLD; else by the
## goal (HandPose.GOAL_POSES).
func _goal_pose(i: int, key: String) -> StringName:
	if not key.begins_with("held:"):
		if key == "seat" and not (pose.has("grip_r") or pose.get("station", false)):
			return HandPose.RELAXED  # riding, the hands on the thighs
		return HandPose.GOAL_POSES.get(key, HandPose.HOLD if key == "seat" else HandPose.RELAXED)
	if not _held_weapon:
		return HandPose.HOLD
	var firing := 1 if left_handed else 0
	if i == firing:
		if _press_t > 0.0 and _lod_shown_every < LOD_FAR:
			return HandPose.PRESS
		return HandPose.TRIGGER if aiming or _shot_t < TRIGGER_HOLD_S else HandPose.GRIP
	if reloading:
		if reload_u >= 0.0 and not reload_keys.is_empty():
			var at := Reloads.sample(reload_keys, reload_u)
			return HandPose.RELOAD_POSES.get(at.anchor_a if float(at.w) < 0.5 else at.anchor_b, HandPose.MAG)
		return HandPose.MAG
	if is_instance_valid(_held) and String(_held.get_meta(&"voxel_model", "")).begins_with("pistol"):
		return HandPose.HOLD  # cupping the firing hand
	if is_seated() and not is_ffv():
		return HandPose.HOLD  # over the firing hand on the rifle stood up
	return HandPose.SUPPORT


## Which way hand `i`'s palm should face (torso space) at arm goal `key`, or null to leave the
## forearm unrolled: on a weapon in towards its middle from the hand's side (the grip, a magazine),
## up and in under a handguard.
func _palm_want(i: int, key: String) -> Variant:
	if not key.begins_with("held:") or not is_instance_valid(_held):
		return null
	var b := (torso.global_basis.inverse() * _held.global_basis).orthonormalized()
	var inward := b.x * (1.0 if i == 1 else -1.0)
	match _hand_shown[i]:
		HandPose.SUPPORT:
			return b.y + inward * 0.6
		HandPose.GRIP, HandPose.TRIGGER, HandPose.PRESS, HandPose.MAG, HandPose.HOLD, HandPose.PINCH:
			return inward
	return null


## Puts hand `i` on `target` (torso space): the arm's IK, the forearm rolled so the palm faces
## `want` (or back to palm-in), and the pose's grasp centre (HandPose.reach_point), not the palm's
## centre, on the target: solved once, then again from where that left the hand.
func _reach_hand(i: int, target: Vector3, want: Variant, delta: float) -> void:
	_reach(i, target)
	var fore := _forearm[i]
	var roll := 0.0
	if want != null:
		var arm := (_upper[i].transform.basis * fore.transform.basis).orthonormalized()
		roll = clampf(HandPose.roll_to(arm.inverse() * (want as Vector3), i == 1), -ROLL_MAX, ROLL_MAX)
	_roll[i] = lerp_angle(_roll[i], roll, minf(delta * ROLL_EASE, 1.0)) if _arms_posed else roll
	var turn := Basis(Vector3.UP, _roll[i])
	fore.transform.basis = fore.transform.basis * turn
	var off := HandPose.reach_point(_hand_shown[i], i == 1, body == VoxelArt.FEMALE) - Vector3(0, -FOREARM, 0)
	if off.length_squared() < 1e-8:
		return
	_reach(i, target - _upper[i].transform.basis * (fore.transform.basis * off))
	fore.transform.basis = fore.transform.basis * turn


## Draws hand `i` in pose `hand_pose_now`: its forearm's mesh swapped for that pose's (VoxelArt,
## shared by every body in this colour scheme), unless hits have carved the forearm a mesh of its
## own (BodyDeform), which stays as it is.
func _show_hand(i: int, hand_pose_now: StringName) -> void:
	var fore := _forearm[i]
	var mi := fore.get_child(0) as MeshInstance3D if fore.get_child_count() > 0 else null
	if mi == null or (hand_pose_now == _hand_shown[i] and mi.mesh == _hand_mesh[i]):
		return
	if not _hand_meshes.has(mi.mesh):
		return  # carved
	var model := HandPose.model(hand_pose_now, i == 1, _hands_bare, body)
	var mesh := VoxelArt.mesh(model, variant)
	mi.mesh = mesh
	_hand_mesh[i] = mesh
	_hand_meshes[mesh] = true
	fore.set_meta(&"voxel_model", model)
	_hand_shown[i] = hand_pose_now
	_hand_anchor[i].transform = HandPose.grasp(hand_pose_now, i == 1, body == VoxelArt.FEMALE)


## Shoulders: at SHOULDER, except that the support shoulder comes forward (SUPPORT_REACH)
## while a weapon is in the hands. Eased, so the reach grows and settles with the draw.
func _place_shoulders(delta: float) -> void:
	var support := 0 if left_handed else 1
	var reaching := is_instance_valid(_held) and _held_weapon and not downed
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var goal := shoulder() * Vector3(side, 1, 1)
		if reaching and i == support:
			goal += SUPPORT_REACH * Vector3(-side, 1, 1)
		_upper[i].position = _upper[i].position.move_toward(goal, delta * 0.8)


## The stance move (STANCE_MOVE_S) on a prone change, and the eased carry and reload weights.
func _update_stance_move(delta: float) -> void:
	var prone := bool(pose.get("prone", false))
	if prone != _was_prone:
		_was_prone = prone
		_stance_move = &"down" if prone else &"up"
		_stance_t = 0.0
		if downed or is_seated():
			_stance_move = &""  # a casualty falling, or a seat: not a move of his own
	else:
		_stance_t += delta
	var m := stance_move()
	if not m.is_empty() and m.kind == &"up" and float(m.u) < RISE_KNEEL_SHARE:
		var kneel := RISE_KNEEL.duplicate()
		kneel["yaw"] = pose.get("yaw", 0.0)
		pose = kneel  # (the body sets `pose` again every frame: this only holds while it lasts)
	var running := ((_gait == JOG or _gait == SPRINT) and not aiming and not reloading or climbing) and not downed and not is_seated()
	_run_carry = move_toward(_run_carry, 1.0 if running else 0.0, delta * RUN_CARRY_EASE)
	_reload_w = move_toward(_reload_w, 1.0 if reloading else 0.0, delta * RELOAD_EASE)
	_kick = move_toward(_kick, 0.0, delta * KICK_DECAY)


## A shot fired: the held weapon kicks (`strength` 0..2, the weapon's recoil against a rifle's).
func kick(strength := 1.0) -> void:
	_kick = clampf(maxf(_kick, 0.0) + strength, 0.0, 2.0)
	_press_t = PRESS_S  # the trigger finger squeezes (HandPose.PRESS)
	_shot_t = 0.0


## 0..2: the weapon's kick now (GearRig).
func kick_shown() -> float:
	return _kick


## 0..1: the rifle's muzzle-down carry on the move (GearRig).
func run_carry() -> float:
	return _run_carry


## 0..1: the weapon rolled in to work the magazine (GearRig).
func reload_roll() -> float:
	return _reload_w


## The weapon's offset and turn on the reload's keys now (Reloads.sample's "pos" and "rot", times
## RELOAD_POSE_GAIN), or [] when the keys aren't known (GearRig then rolls it in by RELOAD_ROLL).
func reload_pose() -> Array:
	if not reloading or reload_u < 0.0 or reload_keys.is_empty():
		return []
	var at := Reloads.sample(reload_keys, reload_u)
	return [(at.pos as Vector3) * RELOAD_POSE_GAIN, (at.rot as Vector3) * RELOAD_POSE_GAIN]


## The stance move under way: {"kind": &"down"/&"up", "u": 0..1}, or {} for none.
func stance_move() -> Dictionary:
	if _stance_move == &"" or _stance_t >= STANCE_MOVE_S:
		return {}
	return {"kind": _stance_move, "u": _stance_t / STANCE_MOVE_S}


## The hands on the floor for a stance move ([right, left] goals), or [] when they aren't.
func _stance_hands() -> Array:
	var m := stance_move()
	if m.is_empty():
		return []
	var window: Vector2 = STANCE_PLANT_DOWN if m.kind == &"down" else STANCE_PLANT_UP
	if float(m.u) < window.x or float(m.u) > window.y:
		return []
	if torso.to_global(shoulder()).y - global_position.y > PLANT_REACH * global_basis.get_scale().y:
		return []  # the shoulders too high over the floor to put the hands down
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var across := fwd.cross(Vector3.UP).normalized()
	var floor_at := global_position + fwd * HANDS_AHEAD * global_basis.get_scale().x
	var out: Array = []
	for side: float in [1.0, -1.0]:
		var p := floor_at + across * HANDS_APART * side
		p.y = global_position.y + 0.04
		out.append(["plant", torso.to_local(p)])
	return out


## [[goal key, torso-local point or null to swing], ...] for the right and left hand.
func _arm_goals(carry: Dictionary) -> Array:
	var mode: StringName = carry.get("mode", &"")
	if mode == CARRIED or mode == DRAGGED:
		return [["limp", _limp_point(0, mode)], ["limp", _limp_point(1, mode)]]
	if downed:
		return [["swing", null], ["swing", null]]
	if mode == CARRY:
		var ph := carry_phase()
		var other: CharacterModel = carry.get("model")
		if not ph.is_empty() and other and ph.u < (0.7 if ph.phase == &"lift" else 0.85) and (ph.phase == &"lift" or ph.u > 0.15):
			# Hands under the body, at its waist and chest, while it comes up (or goes down).
			var at := other.torso.global_position
			var along := other.torso.global_basis.y.normalized() * 0.18
			return [["lift", torso.to_local(at - along)], ["lift", torso.to_local(at + along)]]
		return [["carry", CARRY_HANDS[0]], ["carry", CARRY_HANDS[1]]]
	if mode == DRAG:
		var straps := drag_hand_points()
		# The casualty is drawn at its own size in this body's frame (_update_attachment): a
		# taller or shorter one's straps are that much further or nearer (each soldier's height).
		var other: CharacterModel = carry.get("model")
		var k := other.body_scale() / body_scale() if other and is_instance_valid(other) else 1.0
		return [["drag", _torso_point(straps[0] * k)], ["drag", _torso_point(straps[1] * k)]]
	var held := _held_goals()
	var planted := _stance_hands()
	if not planted.is_empty():
		return planted
	if _action_active():
		var acting := _action_goals(held)
		if not acting.is_empty():
			return acting
	if _draw_t >= 0.0 and _draw_t < DRAW_S * DRAW_GRAB:
		# The firing hand fetches the weapon from its sling or holster.
		return [held[0], ["draw", _draw_point]] if left_handed else [["draw", _draw_point], held[1]]
	return held


func _held_goals() -> Array:
	if not is_instance_valid(_held):
		return _seat_hands() if is_seated() else [["swing", null], ["swing", null]]
	var key := "held:%d" % _held.get_instance_id()
	var support := _support
	if is_seated() and not is_ffv() and _held_weapon:
		support = _grip + Vector3(0, 0.03, 0.11)  # the rifle stood up: the support hand over the firing hand
	if reloading and reload_u >= 0.0 and not reload_keys.is_empty() and _held_weapon:
		# The reload's keys, as in first person: the hand between the weapon's parts and the pouch.
		var at := Reloads.sample(reload_keys, reload_u)
		support = (_reload_anchor(at.anchor_a) + (at.hand_a as Vector3)).lerp(_reload_anchor(at.anchor_b) + (at.hand_b as Vector3), at.w)
	elif reloading:
		# The hand goes to the magazine and works it: out, down to the pouch and back up.
		support = _reload_mag + Vector3(0, -0.06 + sin(_time * 4.0) * 0.06, 0)
	var firing := [key, torso.to_local(_held.to_global(_grip))]
	var other := [key, torso.to_local(_held.to_global(support))]
	return [other, firing] if left_handed and _held_weapon else [firing, other]


## Where reload anchor `anchor` (Reloads) is in the held weapon's space: its rest on the
## handguard, the pouch, or a part of the weapon (VoxelArt.reload_points).
func _reload_anchor(anchor: StringName) -> Vector3:
	match anchor:
		&"rest":
			return _support
		&"pouch":
			return _support + RELOAD_POUCH
	return _reload_pts.get(String(anchor), _reload_mag)


## The magazines in third person, while a reload's keys play: the held weapon drawn without its
## magazine, the old one in it, in the hand, falling free or gone, the new one in the hand or in
## (as PlayerInput does in first person). Near the view, a reload that works the action or opens
## a feed cover draws those apart and moves them on its tracks too (_split_parts). Not on a
## weapon whose mesh is its own (carved by hits).
func _pose_reload_mags() -> void:
	var on := reloading and reload_u >= 0.0 and not reload_keys.is_empty() and _held_weapon and is_instance_valid(_held) and _held.has_meta(&"voxel_model")
	var mesh_node: MeshInstance3D = _held.get_child(0) as MeshInstance3D if on and _held.get_child_count() > 0 else null
	if mesh_node != _split_held:
		_end_split()
	if mesh_node == null:
		return
	var model := String(_held.get_meta(&"voxel_model"))
	var variant := String(_held.get_meta(&"voxel_variant", ""))
	if _split_held == null:
		var has_mag := VoxelArt.has_magazine(model)
		var moving: Array[String] = []
		if not reload_parts.is_empty() and _lod_shown_every <= 1:
			moving = VoxelArt.moving_parts(model)  # (typed: a bare [] here threw every reload frame)
		if (not has_mag and moving.is_empty()) or mesh_node.mesh != VoxelArt.mesh(model, variant):
			return
		_split_held = mesh_node
		_split_whole = mesh_node.mesh
		mesh_node.mesh = VoxelArt.mesh((VoxelArt.FIXED if not moving.is_empty() else VoxelArt.WITHOUT_MAG) + model, variant)
		if not moving.is_empty():
			_split_parts(model, variant, moving, mesh_node)
		if has_mag:
			for i in 2:
				var mag := VoxelArt.instance(VoxelArt.MAG + model, variant, mesh_node.layers)
				mag.name = "ReloadMagazine" if i == 0 else "ReloadMagazineNew"  # (the old one, the new: names of their own)
				(mag.get_child(0) as MeshInstance3D).cast_shadow = mesh_node.cast_shadow
				_held.add_child(mag)
				_mag_parts.append(mag)
	if is_instance_valid(_bolt_part) or is_instance_valid(_cover_part):
		var parts := Reloads.part_transforms(reload_parts, _part_motion, reload_u)
		if is_instance_valid(_bolt_part):
			_bolt_part.transform = parts.bolt
		if is_instance_valid(_cover_part):
			_cover_part.transform = parts.cover
	if _mag_parts.size() < 2:
		return
	var at := Reloads.sample(reload_keys, reload_u)
	var support: Vector3 = (_reload_anchor(at.anchor_a) + (at.hand_a as Vector3)).lerp(_reload_anchor(at.anchor_b) + (at.hand_b as Vector3), at.w)
	var held := support - _reload_mag  # the magazine where the hand holds it
	var dropped := maxf(reload_u - float(at.since), 0.0) * reload_len
	var old: Node3D = _mag_parts[0]
	var new: Node3D = _mag_parts[1]
	old.visible = at.old != &"out" and at.new != &"in"
	match at.old:
		&"hand": old.transform = Transform3D(Basis(Vector3.RIGHT, float(at.tip)), held)
		&"drop": old.transform = Transform3D(Basis(Vector3.RIGHT, -3.0 * dropped), Vector3(0.0, -4.9 * dropped * dropped, 0.03 * dropped))
		_: old.transform = Transform3D.IDENTITY
	new.visible = at.new != &"out"
	new.transform = Transform3D(Basis(Vector3.RIGHT, float(at.tip)), held) if at.new == &"hand" else Transform3D.IDENTITY


## The held weapon's action and feed cover as parts of their own (VoxelArt.BOLT, COVER: `moving`
## names which it has), each on the weapon's pivot so at rest they sit as one.
func _split_parts(model: String, variant: String, moving: Array, mesh_node: MeshInstance3D) -> void:
	_part_motion = VoxelArt.part_motion(model)
	for tag: String in moving:
		var part := VoxelArt.instance((VoxelArt.BOLT if tag == VoxelArt.BOLT_TAG else VoxelArt.COVER) + model, variant, mesh_node.layers)
		part.name = "ReloadBolt" if tag == VoxelArt.BOLT_TAG else "ReloadFeedCover"
		(part.get_child(0) as MeshInstance3D).cast_shadow = mesh_node.cast_shadow
		_held.add_child(part)
		if tag == VoxelArt.BOLT_TAG:
			_bolt_part = part
		else:
			_cover_part = part


## Tests: the third-person action's travel back (m) and feed cover's angle (rad) now, -1 for a
## part not drawn apart.
func reload_parts_shown() -> Dictionary:
	return {"bolt": _bolt_part.position.z if is_instance_valid(_bolt_part) else -1.0,
		"cover": -_cover_part.transform.basis.get_euler().x if is_instance_valid(_cover_part) else -1.0}


## The held weapon whole again, its magazine and moving parts gone (a reload ended, or the
## weapon changed).
func _end_split() -> void:
	if is_instance_valid(_split_held) and _split_whole != null:
		_split_held.mesh = _split_whole
	var parts: Array = [_bolt_part, _cover_part]
	parts.append_array(_mag_parts)
	for part: Variant in parts:
		if is_instance_valid(part):
			(part as Node).queue_free()
	_bolt_part = null
	_cover_part = null
	_mag_parts.clear()
	_split_held = null
	_split_whole = null


## Seated with nothing in the hands: on the thighs, or forward on the controls at a station
## (SEAT_LAP, SEAT_CONTROLS).
func _seat_hands() -> Array:
	if pose.has("grip_r") and pose.has("grip_l"):  # a door gunner on his gun's spade grips (DoorGun)
		return [["seat", torso.to_local(pose.grip_r)], ["seat", torso.to_local(pose.grip_l)]]
	var at: Vector3 = SEAT_CONTROLS if pose.get("station", false) else SEAT_LAP
	var hips := Vector3(0, float(pose.get("hip", SEAT_HEIGHT)), float(pose.get("hip_z", SEAT_HIP_BACK)))
	var root: Transform3D = _shown.root
	return [["seat", _torso_point(root * (hips + at))], ["seat", _torso_point(root * (hips + at * Vector3(-1, 1, 1)))]]


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
			var site := treat_site()
			if not site.is_empty():
				var inv := torso.global_basis.inverse()
				var pads: Array = []
				for spot: Array in site.x:
					pads.append([torso.to_local(spot[0]), (inv * Vector3(spot[1])).normalized()])
				_site_t = {"p": torso.to_local(site.p), "n": (inv * Vector3(site.n)).normalized(), "a": (inv * Vector3(site.a)).normalized(),
					"r": float(site.r) / body_scale(), "x": pads}
				at = _site_t.p
			var goals := _treat_goals(StringName(action_net.get("tech", WORK)), at, t, s)
			_site_t = {}
			if _treat_self != 0:  # your own arm: held out, the other hand does the work
				var present := ["present", PRESENT * Vector3(_treat_self, 1, 1)]
				return [present, goals[0]] if _treat_self == 1 else [goals[0], present]
			return goals
		RADIO:
			if t < s * 0.85:
				return [held[0], ["radio", RADIO_AT]]
		MECH_RELEASE:
			if t < s * 0.75:
				return [["release", at], held[1]]  # the manual release on its back
		MECH_IN:
			if t < s * 0.9:
				return [["mech", MECH_GRAB[0]], ["mech", MECH_GRAB[1]]]  # arms pushed into its sleeves
		MECH_OPEN:
			return [["mech", MECH_GRAB[0]], ["mech", MECH_GRAB[1]]]
		MECH_RISE:
			if t < s * 0.45:
				return [["mech", MECH_GRAB[0]], ["mech", MECH_GRAB[1]]]  # arms pushed into its sleeves
			if t < s * 0.85:
				return [["push", MECH_PUSH[0]], ["push", MECH_PUSH[1]]]  # pushing off the ground
		MECH_OUT:
			if t < s * 0.35:
				return [["mech", MECH_GRAB[0]], ["mech", MECH_GRAB[1]]]  # drawing the arms back out
		BOARD:
			if bool(action_net.get("rope", false)) and board_grip != Vector3.ZERO:  # both hands on the fast-rope
				return [["grip", torso.to_local(board_grip)], ["grip", torso.to_local(board_grip + Vector3.DOWN * 0.28)]]
			if t < float(action_net.get("grip", 0.0)) and board_grip != Vector3.ZERO:
				var grip := ["grip", torso.to_local(board_grip)]
				return [held[0], grip] if board_left else [grip, held[1]]
	return []


## The hands for treating with technique `tech` at `at` (torso space), `t` seconds into a
## clip `s` long: [[key, point], [key, point]] for the right and left hand. The key changes
## between phases so the hand blends to the next point. While a live site is known (_site_t,
## from treat_site: the skin, its outward normal, the limb's axis and radius) the hands work on
## the skin round it (a palm HAND_OFF off it), round the limb for wraps and straps, on the
## windlass rod TreatProps draws; without one (tests calling this directly) round `at` itself.
func _treat_goals(tech: StringName, at: Vector3, t: float, s: float) -> Array:
	var phase := clampf(t / maxf(s, 0.01), 0.0, 1.0)
	# Axes at the wound: in towards it (`out`, from the treater's chest), and two across it (`u`, `v`).
	var out := (at - HANDS_ANCHOR).normalized()
	var u := out.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = out.cross(Vector3.FORWARD)
	u = u.normalized()
	var v := out.cross(u).normalized()
	var sited := not _site_t.is_empty()
	var skin := at
	var n := -out
	var a := v
	var r := 0.0
	if sited:  # in is into the skin, across the limb and along it (down it, distal: v)
		n = _site_t.n
		a = _site_t.a
		r = _site_t.r
		out = -n
		u = a.cross(n).normalized() if a.cross(n).length() > 0.01 else u
		v = -a
		at = skin + n * HAND_OFF
	var spread := Vector3(HAND_SPREAD, 0, 0)
	var axis := skin - n * r  # the limb's axis under the site
	match tech:
		&"wrap":  # the right hand takes the bandage round and round the limb; the left holds the end
			var turn := TAU * WRAP_HZ * t
			if sited and r > 0.0:
				return [["wrap", axis + (n * cos(turn) + u * sin(turn)) * (r + 0.05)], ["hold", at - v * 0.03]]
			return [["wrap", at + (u * cos(turn) + v * sin(turn)) * WRAP_RADIUS], ["hold", at - u * 0.04]]
		&"pack":
			if sited and phase >= PACK_END:  # then pressure: both hands on it, one over the other
				return [["press", at], ["press", at + n * 0.035]]
			var push := 0.02 + 0.03 * absf(sin(t * 6.0))  # gauze stuffed in, finger by finger, the other hand pressing beside it
			return [["pack", at + out * push], ["press", at - u * 0.05]]
		&"tourniquet":
			var span := windlass_span(s)
			if t < span.x:  # strap round the limb, high and tight, and pulled snug
				var lap := TAU * t / span.x
				if sited and r > 0.0:
					return [["strap", axis + (n * cos(lap) + u * sin(lap)) * (r + 0.05)], ["strap", at - u * 0.05]]
				return [["strap", at + (u * cos(lap) + v * sin(lap)) * 0.07], ["strap", at - u * 0.05]]
			if sited:  # on the windlass rod's end as it turns (and as it's laid in the clip)
				var rod := windlass_rod(skin, n, a, windlass_angle(t, s))
				var key := "windlass" if t < span.y else "clip"
				return [[key, rod.c + (rod.d as Vector3) * 0.035 + n * 0.02], ["steady", at - a * 0.05]]
			if t < span.y:  # windlass turns, the other hand steadying the strap
				var turn := TAU * WINDLASS_HZ * t
				return [["windlass", at + u * 0.05 + (u * cos(turn) + v * sin(turn)) * 0.035], ["steady", at - u * 0.04]]
			return [["clip", at + v * 0.05], ["steady", at - u * 0.04]]  # into the clip
		&"splint":
			if sited and phase < SPLINT_SHAPE:  # shaped into a U between the hands, in front of you
				var mid := (HANDS_ANCHOR + Vector3(0, -0.2, -0.3)).lerp(at, 0.35)
				return [["shape", mid + Vector3(0.06, 0, 0)], ["shape", mid - Vector3(0.06, 0, 0)]]
			if sited and r > 0.0:  # on along the limb, the wrap going round it down the splint
				var k := (phase - SPLINT_SHAPE) / (1.0 - SPLINT_SHAPE)
				var turn := TAU * WRAP_HZ * t
				return [["splint", axis + a * lerpf(0.12, -0.12, k) + (n * cos(turn) + u * sin(turn)) * (r + 0.06)], ["hold", at + a * 0.1]]
			var slide := sin(t * 2.0) * 0.1  # the splint along the limb, both hands working down it
			return [["splint", at + v * slide + u * 0.03], ["splint", at - v * slide - u * 0.03]]
		&"seal":
			if phase < SEAL_PEEL:  # peel the backing in front of you, the hands coming apart
				var mid := HANDS_ANCHOR + Vector3(0, -0.15, -0.3)
				var apart := spread * (1.0 + 1.5 * phase / SEAL_PEEL)
				return [["peel", mid + apart], ["peel", mid - apart]]
			var smooth := 0.02 + 0.06 * (phase - SEAL_PEEL) / (1.0 - SEAL_PEEL)  # on, smoothed out from the middle
			return [["seal", at + u * smooth], ["seal", at - u * smooth]]
		&"needle":  # straight in at the second intercostal space, slowly, the other hand steadying
			if sited and phase >= NEEDLE_OUT:  # the stylet back out, the catheter left in
				return [["stylet", at - out * 0.1], ["steady", at - v * 0.06]]
			var depth := clampf(phase / NEEDLE_IN, 0.0, 1.0)
			return [["needle", at - out * lerpf(0.15, 0.01, depth)], ["steady", at - v * 0.06]]  # (from outside the skin in)
		&"inject":  # wind up (the other hand pulls the safety cap), jab, hold, away
			if phase < INJECT_JAB:
				var ready := at + out * -0.2
				if phase < INJECT_CAP:
					return [["ready", ready], ["cap", ready - out * 0.1]]
				return [["ready", ready], ["rest", at - u * 0.08]]
			if phase < INJECT_AWAY:
				return [["jab", at - out * 0.05 if sited else at], ["rest", at - u * 0.08]]
			return [["away", at + out * -0.15], ["rest", at - u * 0.08]]
		&"iv":  # one hand stretches the skin; the catheter slides in along the vein, then taped
			if phase < IV_AIM:
				return [["iv_aim", at + out * -0.08 + v * 0.04], ["skin", at + v * 0.08]]
			if phase < IV_TAPE:
				var slide := (phase - IV_AIM) / (IV_TAPE - IV_AIM)
				return [["iv_in", at + out * lerpf(-0.04, 0.0, slide) + v * lerpf(0.04, -0.01, slide)], ["skin", at + v * 0.08]]
			var dab := sin(t * 9.0) * 0.01
			return [["tape", at + u * (0.03 + dab)], ["tape", at - u * (0.03 - dab)]]
		&"io":  # the driver pressed hard onto the sternum, the other hand steadying
			return [["io", at + out * (0.02 + 0.01 * sin(t * 20.0)) - out * (0.06 if sited else 0.0)], ["steady", at - v * 0.07]]
		&"cpr":  # heel of the hand on the sternum, the other on top, about 110 a minute
			if sited:  # riding the chest down as it goes in (treat_react moves it the same)
				var press := at + out * cpr_compression(t)
				return [["cpr", press], ["cpr", press - out * 0.03]]
			var depth := COMPRESSION_M * (0.5 + 0.5 * sin(TAU * CPR_HZ * t))
			var press := at + out * (0.03 + COMPRESSION_M - depth)
			return [["cpr", press], ["cpr", press + out * 0.03]]
		&"defib":
			if phase < DEFIB_PADS:  # pads on: upper right chest, lower left ribs
				var pads: Array = _site_t.get("x", [])
				if pads.size() >= 2:
					return [["pad", pads[0][0] + pads[0][1] * HAND_OFF], ["pad", pads[1][0] + pads[1][1] * HAND_OFF]]
				return [["pad", at + v * 0.1 + u * 0.08], ["pad", at - v * 0.1 - u * 0.1]]
			var clear := HANDS_ANCHOR + Vector3(0, 0.05, -0.15)  # hands off and clear for the shock
			return [["clear", clear + spread], ["clear", clear - spread]]
		&"clamp":  # fine work close together
			var fine := Vector3(sin(_time * 11.0), cos(_time * 9.0), sin(_time * 13.0)) * 0.008
			return [["clamp", at + u * 0.025 + fine + n * 0.06 * float(sited)], ["clamp", at - u * 0.025 - fine + n * 0.06 * float(sited)]]
		&"fluids":  # the bag held up high, the other hand at the line
			return [["bag", HANDS_ANCHOR + Vector3(0.2, 0.45, -0.3)], ["line", at]]
		&"blanket":  # wide sweeps tucking it round the body
			var sweep := sin(t * 2.5) * 0.25
			return [["blanket", at + u * (0.15 + sweep)], ["blanket", at - u * (0.15 - sweep)]]
		&"npa":  # into the nostril, the other hand tilting the head
			var depth := clampf(phase / 0.7, 0.0, 1.0)
			return [["npa", at + out * lerpf(0.08, 0.01, depth) - out * (0.03 if sited else 0.0)], ["tilt", at - v * 0.07]]
	var busy := Vector3(sin(_time * 7.0) * 0.025, sin(_time * 5.3) * 0.02, cos(_time * 6.1) * 0.02)
	return [["work", at + spread + busy], ["work", at - spread - busy * 0.7]]


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


## Hit and hurt (Captain, 2026-10-16: "anims for wounded/dying that arent unconscious ... goes with
## hit anims"): drawn over whatever pose the frame built (each frame starts from the pose again,
## so nothing piles up).
## - flinch(): a hit jolts the upper body and head (FLINCH_*), gone in about FLINCH_DECAY_S.
## - Downed but awake (not ragdolled, not unconscious): a slow writhe (WRITHE_*): arms and legs
##   shift, the head rolls, the right hand pulled in over the body as if pressing a wound.
const FLINCH_PITCH := 0.32
const FLINCH_TWIST := 0.22
const FLINCH_DECAY_S := 0.35
const WRITHE_HZ := 0.45
const WRITHE_ARM := 0.28
const WRITHE_LEG := 0.16
const WRITHE_HEAD := 0.25
const PRESS_ARM := 0.9
## Wounded but up (Captain, 2026-10-20: "they dont really do wounded things"): pain hunches the
## shoulders forward and drops the head (HUNCH_PITCH at full pain, eased in and out), less while
## aiming (he straightens to shoot).
const HUNCH_PITCH := 0.32
const HUNCH_EASE := 3.0
var _hunch := 0.0


## A hit (every peer: Callouts._vocal calls it with the cry). `strength` 0..1.
func flinch(strength := 1.0) -> void:
	_flinch = maxf(_flinch, clampf(strength, 0.0, 1.0))
	_flinch_side = -1.0 if randf() < 0.5 else 1.0


func _wounded_extras(delta: float) -> void:
	if _flinch > 0.0:
		var k := _flinch * _flinch
		torso.rotation.x -= FLINCH_PITCH * k
		torso.rotation.y += FLINCH_TWIST * k * _flinch_side
		head.rotation.x += FLINCH_PITCH * 0.6 * k
		_flinch = maxf(_flinch - delta / FLINCH_DECAY_S, 0.0)
	if not downed and _gait_w > 0.1:
		_limp(delta)
	var body := get_parent()
	var vitals: Vitals = body.get_node_or_null(^"Vitals") if body else null
	if not downed:
		var want := 0.0
		if vitals != null and vitals.is_up():
			want = clampf((vitals.pain() - 0.2) / 0.6, 0.0, 1.0) * (0.35 if aiming else 1.0)
		_hunch = move_toward(_hunch, want, delta * HUNCH_EASE)
		if _hunch > 0.001:
			torso.rotation.x -= HUNCH_PITCH * _hunch
			head.rotation.x += HUNCH_PITCH * 0.6 * _hunch  # (the head comes back up to look ahead, partly)
	if not downed or ragdolled():
		return
	if vitals == null or vitals.is_dead() or vitals.is_unconscious():
		return
	# Dying (Captain: "the wounded and such ... they do when dying"): as the blood goes the writhe
	# slows and weakens (strength), the head lolls, and now and then the free hand reaches out.
	var strength := clampf((vitals.blood_fraction() - 0.35) / 0.4, 0.15, 1.0) * (1.0 - 0.7 * _calm)  # morphine settles it
	var t := _time * TAU * WRITHE_HZ * lerpf(0.45, 1.0, strength)
	var phase := float(absi(hash(String(body.name))) % 100) * 0.1  # not everyone in step
	_upper[0].rotation.z += PRESS_ARM * strength + sin(t + phase) * WRITHE_ARM * 0.4 * strength  # right hand in over the wound
	_upper[0].rotation.x += 0.4 * strength
	var reach := maxf(sin(_time * 0.35 + phase), 0.0) * (1.0 - strength)  # the weaker, the more he reaches
	_upper[1].rotation.z += sin(t * 0.8 + phase) * WRITHE_ARM * strength - reach * 1.1
	_upper[1].rotation.x += reach * 0.9
	_leg_left.rotation.x += sin(t * 0.7 + phase) * WRITHE_LEG * strength
	_leg_right.rotation.x += sin(t * 0.6 + phase + 1.7) * WRITHE_LEG * strength
	head.rotation.y += sin(t * 0.5 + phase) * WRITHE_HEAD * strength + (1.0 - strength) * 0.5  # lolling to the side
	head.rotation.x += (1.0 - strength) * 0.3


## Being treated (treat_react: the treater's TreatProps asks, on every peer, from its own clip):
## - "wince": while asked (strength 0..1), the upper body curls and the head turns away, a tremor,
##   the treated limb jerks; gone WINCE_FADE_S after the last ask. Awake casualties only; on
##   yourself only the head (the upper body carries your own working hands).
## - "relax" (morphine): over RELAX_IN_S the head sinks back and the writhe settles (also as the
##   casualty's own morphine level rises: Vitals.morphine_level), held RELAX_HOLD_S after.
## - "gasp" (a needle decompression): once, over GASP_S, the chest lifts and the head goes back.
## - "cpr" (strength: metres): the chest pushed in that far along -dir (the skin's normal) while
##   asked; treat_site takes it back out (_react_shift) so the hands ride it down.
## - "spasm" (the defib's shock): once, over SPASM_S, the whole body jolts.
const WINCE_FADE_S := 0.35
const RELAX_IN_S := 2.5
const RELAX_HOLD_S := 8.0
const GASP_S := 1.1
const SPASM_S := 0.5
var _react: Dictionary = {}  # kind -> {"w", "age" (s since it began), "since" (s since last asked), "part", "dir", "k" (shown)}
var _react_shift := Vector3.ZERO  # world: how far the CPR push moves the chest this frame
var _calm := 0.0


func treat_react(kind: StringName, w := 1.0, part := &"", dir := Vector3.ZERO) -> void:
	var r: Dictionary = _react.get(kind, {})
	if r.is_empty() or kind == &"gasp" or kind == &"spasm":
		if not r.is_empty() and (kind == &"gasp" or kind == &"spasm") and float(r.age) < 0.2:
			return  # (one shock, one gasp)
		r = {"age": 0.0}
	r["w"] = w
	r["since"] = 0.0
	r["part"] = part
	r["dir"] = dir
	r["k"] = float(r.get("k", 0.0))
	_react[kind] = r


## Tests: the reactions showing now, kind -> how strongly (cpr: metres).
func reaction_shown() -> Dictionary:
	var out := {}
	for kind: StringName in _react:
		out[kind] = float(_react[kind].get("k", 0.0))
	return out


func _treat_reactions(delta: float) -> void:
	_react_shift = Vector3.ZERO
	if _react.is_empty() and not downed:
		_calm = 0.0
		return
	var vitals: Vitals = get_parent().get_node_or_null(^"Vitals") as Vitals if get_parent() else null
	_calm = clampf(vitals.morphine_level(), 0.0, 1.0) * 0.8 if vitals else 0.0  # (the writhe next frame)
	if _react.is_empty():
		return
	var awake := vitals == null or not (vitals.is_dead() or vitals.is_unconscious())
	var alive := vitals == null or not vitals.is_dead()
	var mine := false  # treating yourself: only the head reacts
	if action_shown() == TREAT:
		mine = _treat_target() == get_parent()
	for kind: StringName in _react.keys():
		var r: Dictionary = _react[kind]
		r.age = float(r.age) + delta
		r.since = float(r.since) + delta
		var k := 0.0
		var done := false
		match kind:
			&"wince":
				k = float(r.w) * (1.0 - smoothstep(0.0, WINCE_FADE_S, r.since)) if awake else 0.0
				done = r.since > WINCE_FADE_S
			&"relax":
				k = float(r.w) * smoothstep(0.0, RELAX_IN_S, r.age) * (1.0 - smoothstep(RELAX_HOLD_S, RELAX_HOLD_S + 2.0, r.since))
				done = r.since > RELAX_HOLD_S + 2.0
			&"gasp":
				k = sin(PI * clampf(r.age / GASP_S, 0.0, 1.0)) if alive else 0.0
				done = r.age > GASP_S
			&"spasm":
				var left := 1.0 - clampf(r.age / SPASM_S, 0.0, 1.0)
				k = float(r.w) * left * left
				done = r.age > SPASM_S
			&"cpr":
				k = float(r.w) if r.since < 0.15 else 0.0
				done = r.since > 0.2
		r.k = k
		if done:
			_react.erase(kind)
			continue
		if k <= 0.0:
			continue
		var side := 1.0 if hash(String(get_parent().name if get_parent() else name)) % 2 == 0 else -1.0
		match kind:
			&"wince":
				head.rotation.y += 0.4 * k * side
				head.rotation.x -= 0.12 * k
				if not mine:
					torso.rotation.x -= 0.16 * k
					torso.rotation.z += sin(_time * 31.0) * 0.03 * k
					var limb := part_node(StringName(r.part))
					if limb and limb != torso and limb != head:
						limb.rotation.x += 0.18 * k * sin(_time * 17.0)
			&"relax":
				_calm = maxf(_calm, k)
				head.rotation.x += 0.12 * k
			&"gasp":
				torso.rotation.x += 0.22 * k
				torso.position += torso.basis.y.normalized() * 0.015 * k
				head.rotation.x += 0.3 * k
				for i in 2:
					_upper[i].rotation.z += 0.15 * k * (1.0 if i == 0 else -1.0)
			&"spasm":
				torso.rotation.x += 0.35 * k
				head.rotation.x += 0.4 * k
				for i in 2:
					_upper[i].rotation.z += 0.6 * k * (1.0 if i == 0 else -1.0)
					_upper[i].rotation.x += 0.4 * k
				_leg_left.rotation.x += 0.3 * k
				_leg_right.rotation.x += 0.3 * k
				_root.position.y += 0.03 * k
			&"cpr":
				var dir: Vector3 = r.dir
				if dir.length() > 0.01:
					_react_shift = -dir.normalized() * k
					torso.global_position += _react_shift
					head.rotation.x += 0.1 * k / COMPRESSION_M


## A limp on a wounded leg: on that foot's step the body dips and leans over it (LIMP_*), by how
## much of the walk cycle shows. Which leg (a wound on a thigh or shin, worse with a break) is
## looked up every LIMP_CHECK_S.
const LIMP_DIP := 0.045
const LIMP_LEAN := 0.12
const LIMP_CHECK_S := 0.5
var _limp_leg := 0.0     # -1 left, 1 right, 0 none; times 1.6 with a break
var _limp_check := 0.0


func _limp(delta: float) -> void:
	_limp_check -= delta
	if _limp_check <= 0.0:
		_limp_check = LIMP_CHECK_S
		_limp_leg = 0.0
		var vitals: Vitals = get_parent().get_node_or_null(^"Vitals") if get_parent() else null
		if vitals:
			for w: Dictionary in vitals.wound_list():
				var side := -1.0 if w.part in [Vitals.THIGH_L, Vitals.SHIN_L] else (1.0 if w.part in [Vitals.THIGH_R, Vitals.SHIN_R] else 0.0)
				if side != 0.0 and not w.treated:
					_limp_leg = side * (1.6 if String(w.kind) == "fracture" else 1.0)
	if _limp_leg == 0.0:
		return
	var land := 0.0 if _limp_leg < 0.0 else 0.5  # the bad foot's stance starts here in the cycle
	var into := fposmod(_gait_phase - land, 1.0)
	if into > 0.5:
		return
	var k := sin(into / 0.5 * PI) * _gait_w * absf(_limp_leg)
	_root.position.y -= LIMP_DIP * k
	torso.rotation.z += LIMP_LEAN * k * signf(_limp_leg)
