class_name PlayerInput
extends Node
## The human driver of a Soldier, active only on the player's own machine: mouse look and
## action keys, the first-person camera and weapon view model, what's under the crosshair
## (pickups, downed bodies), and the HUD. Movement keys are read by SoldierMovement.
## Everything it does to shared state goes through the body's host-side requests.

const MOUSE_SENSITIVITY := 0.0025
const BASE_FOV := 80.0
## View model position (camera-local) at the hip; aiming puts the weapon's sight point
## (VoxelArt.sight_point) on the eye's line instead (ads_view), this far in front of it: a
## rifle's optic close to the eye so you look through the tube, a pistol out at arm's length
## (Captain, P0362: a sight picture you can use). ADS_EYE back out from 16 to 19 cm (Captain,
## 2026-10-14: aimed, the red dot still looked big; a little further from the eye).
const HIP_VIEW := Vector3(0.14, -0.16, -0.38)
## First person on the move (docs/animation.md), in step with the drawn legs (CharacterModel's
## gait): the view rides the drawn head itself (_place_eye: its bob and sway are the body's;
## GameSettings.camera_motion scales it, 0 a steady view); the
## weapon bobs WEAPON_BOB (m: across, down) at a sprint, and sprinting comes down and across
## by SPRINT_VIEW (m) and SPRINT_TILT (radians: muzzle down, turned in, canted).
## Weight in the view (Captain, 2026-10-20: movement "floaty / slidey", the camera feel): a dip
## on each footfall (FOOT_DIP m at a sprint, less slower: a quick drop, a slower rise); a dip
## on landing, LAND_DIP_PER_MPS for each m/s he came down at (up to LAND_DIP_MAX), sprung back
## (LAND_SPRING, LAND_DAMP); the view nods with the body's pace changes along it, down braking
## and up setting off (ACCEL_PITCH rad per m/s^2, up to ACCEL_PITCH_MAX); the view widens
## SPRINT_FOV degrees at a sprint; the weapon trails the mouse (LOOK_LAG rad per pixel, up to
## LOOK_LAG_MAX, coming back at LOOK_LAG_RETURN per second; LOOK_LAG_AIMED of that aimed).
const FOOT_DIP := 0.014
const FOOT_DIP_SHARP := 8.0
const LAND_DIP_PER_MPS := 0.016
const LAND_DIP_MAX := 0.12
const LAND_SPRING := 140.0
const LAND_DAMP := 0.75
## Stairs (Captain, 2026-10-20: "stairs also arent smooth walking up"): a step up lifts the body
## in one frame (SoldierMovement._climb_bodies, up to WORLD_STEP_M); the view keeps the height it
## had and eases up after it (STEP_SMOOTH per second), so a flight of stairs is one smooth climb,
## not a jolt a step. A jump up of more than STEP_SMOOTH_MAX_M (a mantle's end, a teleport) isn't
## smoothed.
const STEP_SMOOTH := 14.0
const STEP_SMOOTH_MAX_M := 0.4
var _step_y := 0.0  # the view's lag behind the body after a step up (m, down)
var _step_last_y := INF
## Only a fall of at least this long (s) dips the view: not a step down, a stair's lip or the
## settle at a spawn (a jump is about 0.7 s in the air).
const LAND_MIN_AIR_S := 0.25
const ACCEL_PITCH := 0.0035
const ACCEL_PITCH_MAX := 0.035
const SPRINT_FOV := 2.0
const LOOK_LAG := 0.0008
const LOOK_LAG_MAX := 0.05
const LOOK_LAG_RETURN := 10.0
const LOOK_LAG_AIMED := 0.15
var _land_y := 0.0
var _land_v := 0.0
var _was_floor := true
var _air_vy := 0.0
var _air_t := 0.0
var _feel_pitch := 0.0
var _last_fwd_speed := 0.0
var _look_lag := Vector2.ZERO
var _view_lag := Vector2.ZERO  # the lag the body's gun has now (x yaw, y pitch: radians)
var _sprint_fov_w := 0.0
const WEAPON_BOB := Vector2(0.012, 0.012)
const SPRINT_VIEW := Vector3(-0.03, -0.05, 0.05)
const SPRINT_TILT := Vector3(-0.5, 0.35, 0.25)
## The Captain's Star Citizen reference (2026-10-18, B:/Contractor-refs/captures/2026-10-18):
## not aiming or firing for LOW_READY_AFTER_S, the weapon eases down to a low ready (LOW_READY_VIEW
## down and in, LOW_READY_TILT: muzzle down, turned in) and comes straight back up to fire or aim;
## jogging it takes JOG_CARRY of the sprint carry. Reloading plays its family's keys (Reloads:
## the weapon tipped in and pulled close, the support hand taking the magazine out, the new one
## in with a look, seated and tugged, the bolt worked on an empty reload), the magazine a part of
## its own that the hand carries (VoxelArt.MAG).
const LOW_READY_AFTER_S := 1.5
const LOW_READY_VIEW := Vector3(-0.03, -0.05, 0.02)
const LOW_READY_TILT := Vector2(-0.28, 0.06)
const JOG_CARRY := 0.45
## A reload's "pouch" anchor (Reloads): low by the belt, out of view, from the hand's rest.
const RELOAD_POUCH := Vector3(-0.12, -0.38, 0.12)
## A magazine falling free (an empty reload) drops this fast (m/s²) and tumbles (rad/s).
const MAG_FALL := 9.8
const MAG_TUMBLE := 3.0
## Each shot (Soldier.recoil_return growing) the view model kicks back VIEW_KICK_BACK (m) and its
## muzzle up VIEW_KICK_PITCH (radians) x the weapon's recoil against a rifle's, settling at
## VIEW_KICK_DECAY a second (aimed, a third of it: the stock's in the shoulder).
const VIEW_KICK_BACK := 0.035
const VIEW_KICK_PITCH := 0.09
const VIEW_KICK_DECAY := 10.0
const ADS_EYE := Vector3(0.0, 0.0, -0.19)
const ADS_EYE_PISTOL := Vector3(0.0, 0.0, -0.5)
## Recoil settling back (Soldier.RECOIL_SETTLE), per second: most of it within a quarter second.
const RECOIL_SETTLE_RATE := 12.0
## Proposed: where each first-person forearm's elbow sits from its hand, in view space (a
## right-handed shooter's; x mirrors for a left-handed one): the firing elbow low and out
## behind the grip, the support elbow under and behind the handguard.
const VIEW_FIRING_ELBOW := Vector3(0.09, -0.12, 0.2)
const VIEW_SUPPORT_ELBOW := Vector3(-0.07, -0.15, 0.2)
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1
## Render layer for the first-person weapon and arms (the view model, still on your own
## camera's mask): a tube optic's scope picture is a separate camera (GunSight PIP) that skips
## it, so the gun you're looking past doesn't show up huge and in the way of the magnified glass.
const VIEW_MODEL_LAYER := 1 << 2
## Full-body first person (Captain, 2026-10-26: "a true first-person full body ... the camera in
## the head of the same model everyone sees", Star Citizen): your own body and kit draw on
## LOCAL_BODY_LAYER, which your camera shows (looking down: legs, boots, the carrier and its
## pouches, your arms and the gun in them), and your head and what's on it (face, hair, helmet,
## ear pro) on LOCAL_ONLY_LAYER, which it doesn't (_hide_own_head). The weapon in your hands is
## the body's own (the view model only shows a thrown grenade, _view_model_shown). Optics' scope
## pictures and vehicle sights skip your body (GunSight, VehicleSight, VehicleVision).
const LOCAL_BODY_LAYER := 1 << 3
## The camera rides the drawn head's eyes (EYE_IN_HEAD, head-local: CharacterModel.EYE's height
## over its HEAD_PIVOT, 7 cm forward of the neck where the eyes are, so the shoulders and collar
## don't crowd the view), mixed (Captain: "head, stabilised" and "head, raw", "mixed well") as EYE_RAW_SHARE
## of the raw head and the rest the head steadied over EYE_STEADY_S (the inner ear), at most
## EYE_REACH_M off the body's own eye point (Soldier.head, which the shot origin and hits keep
## using), all times GameSettings.camera_motion. Aiming a gun, the eye goes behind its sight on
## the body's own gun (ADS_EYE back along the barrel), easing in at ADS_EASE.
const EYE_IN_HEAD := Vector3(0, 0.19, -0.07)
const EYE_RAW_SHARE := 0.4
const EYE_STEADY_S := 0.12
const EYE_REACH_M := 0.3
const ADS_EASE := 9.0
var _eye_slow := Vector3.ZERO  # the head's eye off the body's eye point, steadied (body space, m)
var _cam_base := Vector3.ZERO  # the camera's place from the steps, landings and the medic's kneel
var _ads_w := 0.0              # how far the eye has come behind the sight
var _head_hide_t := 0.0
## Throwables in the order Shift+G cycles them (next_throwable): frag and flashbang always,
## then each smoke colour you carry, then the breaching charge if you carry one (G with it
## picked places it: Charges), then the demolitions you carry (Demolitions: G with a block,
## thermite, a claymore or a mine places it, R picks how it's armed; chem lights are thrown; G
## with a clacker or remote fires what you armed on a detonator).
const THROWABLES: Array[StringName] = [&"frag_grenade", &"flashbang", &"smoke_grenade", &"smoke_green", &"smoke_yellow", &"smoke_blue", &"smoke_purple", Charges.ITEM,
	&"demo_block", &"thermite", &"claymore", &"ap_mine", &"chemlight_green", &"chemlight_red", &"chemlight_blue", &"chemlight_ir", &"clacker", &"remote_detonator"]
## Always in the Shift+G cycle, carried or not (smokes only show up while you have one).
const ALWAYS_CYCLED: Array[StringName] = [&"frag_grenade", &"flashbang"]

@onready var body: Soldier = get_parent()

var hud: Hud
## The ACE-style interaction menu (hold Left Ctrl; Left Ctrl + Left Alt for yourself).
var interaction: InteractionMenu
## The medical menu (H: MedicalMenu); Shift+H quick-treats yourself.
var medical_menu: MedicalMenu
## The grenade type G equips and Shift+G cycles.
var throwable: StringName = &"frag_grenade"
## A grenade is up in your hand (G): the weapon is lowered, Fire throws, Aim lobs, G / the wheel /
## the weapon keys put it away with nothing thrown. Nothing throws until it is up.
var nade_up := false
## Binoculars (Captain, 2026-10-20): up on the binoculars key when he carries a pair (BINOS);
## the view zooms by its magnification, the frame shows (BinocularView), the weapon is lowered
## and doesn't fire; sprinting, a weapon key, going down or getting in a vehicle lowers them.
const BINOS := &"binoculars"
var _binos_view: BinocularView
var _nade_label: Label
## An underhand lob goes at this fraction of the throw speed (and a bit less up).
const LOB_POWER := 0.45
var _focus: Node3D  # an item or downed body under the crosshair, for the prompt
var _view_model_id: StringName = &""
## The casualty on this player's shoulder, kept out of their own first-person view (it would
## fill it): drawn on LOCAL_ONLY_LAYER like their own body, so everyone else still sees it.
var _shouldered: Soldier = null
var _shake := 0.0
var _vm_base := HIP_VIEW   # the view model's place before its bob
var _bob_w := 0.0          # 0..1: how much the steps move the view (not aiming, on the ground)
var _sprint_w := 0.0       # 0..1: the weapon in its sprint carry
var _low_w := 0.0          # 0..1: the weapon down at the low ready
## How low the weapon was when it last came up to the eye (0 at the ready, 1 fully low: the sprint
## carry, the low ready, a climb), which makes the ADS slower (MovementRules.ADS_FROM_LOW_MULT).
var _ads_low := 0.0
## The wheel's pace (wheel_pace): one step each PACE_WHEEL_GAP_S at most (a free-spinning or
## high-resolution wheel sends many notches at once), and when the last went.
const PACE_WHEEL_GAP_S := 0.08
var _pace_wheel_at := -100.0
## The view's gaze held on a point GAZE_FOCUS_M ahead (feel round 2, Captain 2026-10-20; learned
## from Star Citizen's head camera): as the steps move the eye (the bob, the sway, the footfall
## and landing dips), it turns a little the other way, so the world ahead stays put while the
## body moves under it. Applied on top of the camera's eased sway (_cam_turn).
const GAZE_FOCUS_M := 10.0
var _cam_turn := Vector2.ZERO
## First-person medic view (Captain, 2026-10-20: medical animations on par with Arma Reforger and
## beyond): treating anyone, yourself too, the weapon is gone from view and your own forearms,
## hands and what they hold are on the camera (CharacterModel.set_view_hands), the eye goes down
## with the drawn body's kneel and bend (CharacterModel.treat_view_offset, _medic_eye, head space),
## and for MEDIC_LOOK_S at the start the view turns to the work (Proposed) unless it's already
## within MEDIC_LOOK_SLACK of it (treating yourself it only looks down: the body doesn't turn);
## then the mouse is yours again.
const MEDIC_LOOK_S := 0.5
const MEDIC_LOOK_RATE := 7.0
const MEDIC_LOOK_SLACK := 0.25
var _medic_eye := Vector3.ZERO
var _medic_n := -1
var _medic_look := 0.0
var _view_kick := 0.0      # 0..2: a shot's kick, settling
var _vm_pitch := 0.0       # the view model's eased pitch, before the kick
var _last_recoil := 0.0
var _ready_hold := 0.0     # seconds before it eases down to the low ready
var _reload_w := 0.0       # 0..1: the weapon rolled in to reload
var _reload_from := 0.0    # Soldier._now() the reload started (its length: _reload_len)
var _reload_len := 1.0
var _support_arm: Node3D   # the support hand's view forearm, and where it rests
var _support_rest := Transform3D.IDENTITY
var _support_palm := Vector3.ZERO  # view-model space: the support palm at rest
## The view forearms' hands (HandPose, fingers pass 2026-10-20): [firing, support] forearms, the
## pose each is drawn in, and the trigger's squeeze after a shot (CharacterModel.PRESS_S).
var _view_arms: Array[Node3D] = []
var _view_poses: Array[StringName] = [&"", &""]
var _view_press_t := 0.0
var _view_shot_t := 99.0
var _view_pistol := false
var _melee: MeleeInput  # the melee controls (survival: MeleeInput), made on first use
var _reload_points := {}  # VoxelArt.reload_points of the weapon in view
var _reload_keys: Array = []  # Reloads.keys of the reload under way
var _reload_pos := Vector3.ZERO  # its weapon offset and turn this frame (Reloads)
var _reload_rot := Vector3.ZERO
var _mag_old: Node3D  # the magazine in the weapon (VoxelArt.MAG), and the fresh one in hand
var _mag_new: Node3D
var _bolt_part: Node3D  # the weapon's sliding action (VoxelArt.BOLT) and feed cover (COVER), drawn apart
var _cover_part: Node3D
var _part_motion := {}  # VoxelArt.part_motion of the weapon in view
var _reload_parts := {}  # Reloads.parts of the reload under way
var _deaf := false
## Placing a breaching charge (Charges) or a demolitions item (Demolitions): the ghost follows
## the view until Fire commits it. `_placing_item` is what's being placed, `_arm_index` which of
## its Demolitions.arm_modes R has picked.
var placing := false
var _placing_item: StringName = &""
var _arm_index := 0
## The Escape menu (PauseMenu), on the local player only.
var pause_menu: PauseMenu
## The bug-report note panel (Insert), on the local player only.
var bug_report: BugReport
## The third-person view while seated in a vehicle (VehicleCamera; B switches it), on the local
## player only.
var vehicle_camera: VehicleCamera
var _ghost: Node3D
## Muffled hearing: everything through a low-pass this low, and this much quieter than the
## Master volume it had (relative, so a player with Master turned well down isn't made louder:
## -12 dB flat was 28 dB up from a Master at 1%, R0911/R0913).
const DEAF_CUTOFF_HZ := 600.0
const DEAF_VOLUME_DB := -12.0
## The gamepad (wave 7, S4): the hold-View wheel (PadWheel), the right stick's last raw
## deflection (x right, y down), the stick's speed moving the interaction menu's cursor (px a
## second at full deflection), and the assists' HUD line (Assists: wound hints), this far below
## the middle of the screen.
var pad_wheel: PadWheel
var stick := Vector2.ZERO
const PAD_CURSOR_SPEED := 600.0
var assist_line: Label
const ASSIST_LINE_Y := 150.0
var _hint_left := 0.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	if not body.is_node_ready():
		await body.ready  # children are ready before their parent
	if not body.is_local():
		return
	set_muffled(false)  # a new local player starts hearing normally, whatever came before
	body.camera.current = true
	body.camera.cull_mask &= ~LOCAL_ONLY_LAYER
	body.camera.cull_mask |= LOCAL_BODY_LAYER
	body.model.render_layers = LOCAL_BODY_LAYER  # your own body, seen (its head hidden: _hide_own_head)
	body.gear.render_layers = LOCAL_BODY_LAYER
	_hide_own_head()
	RenderingServer.frame_pre_draw.connect(_place_eye)
	hud = Hud.new()
	hud.player = body
	body.add_child(hud)
	pause_menu = PauseMenu.new()
	body.add_child(pause_menu)
	bug_report = BugReport.new()
	body.add_child(bug_report)
	vehicle_camera = VehicleCamera.new(body)
	body.add_child(vehicle_camera)
	if DevTools.on() and multiplayer.is_server():
		body.add_child(AiOverlay.new())
	interaction = InteractionMenu.new(body)
	hud.add_child(interaction)
	medical_menu = MedicalMenu.new(body)
	hud.add_child(medical_menu)
	hud.add_child(LauncherSight.new(body))  # anti-armour launchers: sight, lock, fire (wave 5)
	hud.add_child(GunSight.new(body))  # rifle and pistol sights (P0362)
	body.add_child(NvgView.new(body))  # the view through lowered NVGs (wave 7, S2)
	_binos_view = BinocularView.new()
	body.add_child(_binos_view)
	pad_wheel = PadWheel.new()
	hud.add_child(pad_wheel)
	assist_line = UiKit.hud_label("", &"HudSmallLabel")
	assist_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	assist_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assist_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	assist_line.position.y += ASSIST_LINE_Y
	hud.add_child(assist_line)
	body.loadout_changed.connect(_update_view_model)
	_update_view_model()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


var _view_yaw := 0.0  # Soldier.view_yaw last applied
## The turn cap under load (MovementRules.MAX_YAW_RATE): mouse yaw (radians) still to play out,
## and what this frame may still turn.
var _pending_yaw := 0.0
var _turn_budget := 0.0
## 0..1: how far a wall close ahead has pushed the weapon back (MovementRules.WALL_PULL_*).
var wall_pull := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if HcCamera.of(body) != null:
		return  # the 3D high command camera has the mouse and the keys
	var captured := _captured()
	if pause_menu.is_open() or bug_report.is_open():
		return  # the Escape menu has the mouse (it closes itself on Escape)
	elif medical_menu.is_open():
		return  # the medical menu has the mouse and the keys (it closes itself on H or Escape)
	elif event is InputEventMouseMotion and captured and interaction.is_open():
		interaction.move_cursor(event.relative)  # the menu has the mouse, not the view
	elif event is InputEventMouseMotion and captured:
		# The settings' sensitivity (and aiming sensitivity down sights); concussion slows turning.
		var turn := GameSettings.mouse_turn(MOUSE_SENSITIVITY, body.is_aiming) * body.vitals.turn_mult()
		turn *= GunSight.zoom_turn(body)  # through a scope: slower with the zoom (P0362)
		turn *= VehicleSight.zoom_turn(body)  # through a vehicle's sight, the same (combined arms A4)
		if body.movement.is_sprinting:  # sprinting under load, the view comes round slower
			turn *= lerpf(1.0, MovementRules.SPRINT_TURN_LOADED, MovementRules.load_fraction(body.load_kg))
		turn_view(-event.relative.x * turn)
		body.set_pitch(body.head.rotation.x - event.relative.y * turn * (-1.0 if GameSettings.invert_y() else 1.0))
		_look_lag = (_look_lag + Vector2(event.relative.x, event.relative.y * (-1.0 if GameSettings.invert_y() else 1.0)) * LOOK_LAG).limit_length(LOOK_LAG_MAX)
	elif hud.map_screen and hud.map_screen.is_open():
		return  # the map (M) has the mouse and the keys: no reloading or throwing behind it
	elif hud.voice_order.listening and event.is_action_pressed(&"pause"):
		hud.voice_order.cancel()  # Esc cancels the voice order box instead of opening the pause menu
	elif hud.voice_order.listening:
		return  # the voice order box has the keys (not the mouse: you can still aim a pointed order)
	elif event.is_action_pressed(HcCamera.ACTION):  # before M: M alone also matches with Shift held
		if body.vitals.is_up() and HighCommand.of(body) and not HighCommand.of(body).view.is_empty():
			HcCamera.toggle(body)
		else:
			hud.flash("No high command squads out")
	elif event.is_action_pressed(&"inventory") or (event.is_action_pressed(&"pause") and hud.is_inventory_open()):
		hud.toggle_detail()
	elif hud.is_inventory_open():
		return  # the inventory screen has the mouse
	elif body.vitals.is_up() and body.respawn_state != Soldier.RESPAWN_WAITING and hud.command_menu.handle_input(event):
		return  # F-keys, and 1-9 / wheel / middle click while the command menu is open (not while dead, waiting to respawn)
	elif body.vitals.is_up() and hud.context_menu and hud.context_menu.handle(event):
		return  # the contextual order: tap or hold the middle button (ContextMenu)
	elif event.is_action_pressed(&"debug_hurt") and DevTools.on():
		body._server_debug_hurt.rpc_id(1, 40.0)
	elif event.is_action_pressed(&"zoom_in") or event.is_action_pressed(&"zoom_out"):
		# Side mouse buttons (P0362): a variable optic's power, a holographic sight's magnifier.
		var told := GunSight.zoom_step(body, 1 if event.is_action_pressed(&"zoom_in") else -1)
		if told != "":
			hud.flash(told)
	elif event.is_action_pressed(&"weapon_light") and body.vitals.is_up():
		# The light or laser on the gun in hand (GunAttachments; wave 7 S3): the host switches it.
		body._server_inventory_action.rpc_id(1, "toggle_attachment", &"", -1, body.active_slot, &"")
	elif event.is_action_pressed(&"pause"):
		pause_menu.open()  # Escape: resume, return to base, main menu, quit
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(VehicleCamera.ACTION) and Vehicle.ride_of(body) != null:
		hud.flash(VehicleCamera.toggle())  # seated: chase view <-> first person, for the session
	elif not body.vitals.is_up():
		return  # downed: you come round on your own, the arrest window runs out, or you give up (_update_give_up)
	elif body.respawn_state == Soldier.RESPAWN_WAITING:
		return  # dead, waiting to respawn: nothing to do but wait
	elif BuildMode.handle(body, event):
		return  # survival: the build key, and build mode's keys while it's on (BuildMode)
	elif event.is_action_pressed(ControlOptions.GET_OUT_ACTION) and ControlOptions.get_out_key() and Vehicle.ride_of(body) != null:
		Vehicle.ride_of(body).request_exit.rpc_id(1)  # the get-out key (an option; the seat's menu then has no Get out)
	elif interaction.is_open() and event is InputEventMouseButton:
		# The wheel scrolls a submenu longer than the window (a full body's Loot list; P0-3,
		# docs/ui_audit.md); clicks don't fire through the interaction menu.
		if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			interaction.scroll_submenu(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	elif nade_up and event.is_action_pressed(&"fire"):
		_try_throw(1.0)  # overhand
	elif nade_up and event.is_action_pressed(&"aim"):
		_try_throw(LOB_POWER)  # underhand lob
	elif nade_up and event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		put_nade_away("Grenade put away")  # scroll: nothing thrown
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		wheel_pace(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)  # on foot: the pace
	elif event.is_action_pressed(&"inspect"):
		toggle_inspect()  # the item under the crosshair: what it is and how to use it (ItemInfo)
	elif placing and event.is_action_pressed(&"fire"):
		_commit_charge()  # Fire puts the charge where the ghost sits
	elif placing and (event.is_action_pressed(&"aim") or (event.is_action_pressed(&"grenade") and not (event is InputEventKey and (event.shift_pressed or event.alt_pressed)))):
		_stop_placing("Charge put away")
	elif placing and event.is_action_pressed(&"reload"):
		_cycle_arm()  # R: how it's armed (Demolitions.arm_modes)
	elif event.is_action_pressed(&"grenade") and body.carry_mode != &"":
		# Hands full with a casualty: G lets go of them (Release / Put down) instead of throwing.
		body._server_release_body.rpc_id(1)
		flash("Let go" if body.carry_mode == Soldier.DRAG else "Put down")
	elif event.is_action_pressed(&"grenade"):
		# G throws, Shift+G switches grenade type, Alt+G drops what you're holding.
		if event is InputEventKey and event.alt_pressed:
			body._server_drop.rpc_id(1, body.active_slot)
		elif event is InputEventKey and event.shift_pressed:
			throwable = next_throwable(throwable, body.inventory)
			var places := throwable == Charges.ITEM or Demolitions.is_placeable(throwable)
			if placing:
				_stop_placing()
				if places:
					_start_placing()
				else:
					hud.flash("%s (%d)" % [ItemDB.get_item(throwable).name, body.inventory.count_of(throwable)])
			elif nade_up and places:
				put_nade_away()
				_start_placing()
			elif nade_up and not Demolitions.is_detonator(throwable):
				_show_nade()
				_update_view_model()
			else:
				put_nade_away()
				hud.flash("%s (%d)" % [ItemDB.get_item(throwable).name, body.inventory.count_of(throwable)])
		elif nade_up:
			put_nade_away("Grenade put away")  # G again: nothing thrown
		elif throwable == Charges.ITEM or Demolitions.is_placeable(throwable):
			_start_placing()
		elif Demolitions.is_detonator(throwable):
			_fire_detonator()
		else:
			equip_nade()
	elif event.is_action_pressed(&"walk") and not is_instance_valid(body.vehicle):
		body.movement.walk_pace = not body.movement.walk_pace  # the jog, or back to the last slower pace
		hud.flash("Pace: %s" % SoldierMovement.PACE_NAMES[body.movement.pace])
	elif event.is_action_pressed(&"auto_walk") and not is_instance_valid(body.vehicle):
		body.movement.auto_walk = not body.movement.auto_walk and body.vitals.is_up()
		hud.flash("Auto-walk on (W or S to stop)" if body.movement.auto_walk else "Auto-walk off")
	elif event.is_action_pressed(VehicleCamera.ACTION) and VehicleCamera.foot_key(body, event is InputEventWithModifiers and (event as InputEventWithModifiers).shift_pressed):
		hud.flash(VehicleCamera.toggle_foot())  # survival on foot: third person over the shoulder <-> first (call 135)
	elif event.is_action_pressed(&"binoculars") and not is_instance_valid(body.vehicle):
		_set_binoculars(not body.binoculars_up)
	elif event.is_action_pressed(&"nvg_toggle"):
		body._server_toggle_nvg.rpc_id(1)  # the helmet's NVG down or up (wave 7, S2; Nvg)
	elif event.is_action_pressed(&"tag_enemy"):
		_tag_enemy()
	elif event.is_action_pressed(&"reload"):
		_try_reload()
	elif event.is_action_pressed(&"quick_treat"):  # before H: H alone also matches with Shift held
		body._server_use_medical.rpc_id(1)
	elif event.is_action_pressed(&"medical_menu"):
		medical_menu.open(MedicalMenu.looked_at(body, body.camera))
	elif event.is_action_pressed(&"weapon_primary"):
		_set_binoculars(false)
		put_nade_away()
		body.select_weapon(&"primary")
	elif event.is_action_pressed(&"weapon_sidearm"):
		put_nade_away()
		body.select_weapon(&"sidearm")
	elif event.is_action_pressed(&"weapon_launcher") and body.inventory.slots.get(Launchers.SLOT, &"") != &"":
		put_nade_away()
		body.select_weapon(Launchers.SLOT)
	elif event.is_action_pressed(&"weapon_underbarrel"):
		toggle_underbarrel()


## The underbarrel key (4): the trigger onto the M320 under the rifle in hand and back
## (Underbarrel); with a shotgun in hand, the next shell kind R loads (Shotguns.next_pick).
func toggle_underbarrel() -> void:
	var weapon := body.active_weapon()
	if Shotguns.is_tube(weapon):
		var current := body.shell_pick if body.shell_pick != &"" else Shotguns.load_choice(weapon, body.inventory)
		body.shell_pick = Shotguns.next_pick(weapon, current, body.inventory)
		if body.shell_pick != &"":
			hud.flash("R loads: %s (%d)" % [ItemDB.get_item(body.shell_pick).name, body.inventory.count_of(body.shell_pick)])
		return
	var key := Shotguns.key_of(body)
	if Underbarrel.on_gun(body) == null and key == null:
		body.underbarrel_up = false
		hud.flash("No grenade launcher or Skeleton Key on this gun")
		return
	put_nade_away()
	body.underbarrel_up = not body.underbarrel_up
	if body.underbarrel_up and key:
		var n := Shotguns.key_list(key, body.inventory.state_of(body.active_slot)).size()
		hud.flash("%s: %s" % [key.name, "%d in the tube" % n if n > 0 else "empty - R to load"])
		return
	var w := Underbarrel.loaded_of(body)
	if body.underbarrel_up:
		hud.flash("%s: %s" % [Underbarrel.on_gun(body).stats.get("short", "Launcher"), Launchers.warhead_name(w) if w != &"" else "empty - R to load"])
	else:
		hud.flash(weapon.name)


## Turns the body (yaw, radians) as fast as its load lets it (MovementRules.MAX_YAW_RATE): light,
## at once; loaded, up to this frame's share of the cap now and the rest over the next frames
## (advance_turn), so a flick swings round slower but nothing is lost.
func turn_view(yaw: float) -> void:
	if is_inf(max_yaw_rate()):
		_pending_yaw = 0.0
		body.rotate_y(yaw)
		return
	_pending_yaw += yaw
	_spend_turn()


## The turn cap now (degrees a second): by load tier.
func max_yaw_rate() -> float:
	return MovementRules.MAX_YAW_RATE[body.load_tier()]


## Each frame: a fresh share of the turn cap, spent on any turn still pending.
func advance_turn(delta: float) -> void:
	var rate := max_yaw_rate()
	_turn_budget = INF if is_inf(rate) else deg_to_rad(rate) * delta
	if not body.vitals.is_up():
		_pending_yaw = 0.0
	_spend_turn()


func _spend_turn() -> void:
	if _pending_yaw == 0.0:
		return
	var step := clampf(_pending_yaw, -_turn_budget, _turn_budget)
	body.rotate_y(step)
	_pending_yaw -= step
	_turn_budget -= absf(step)


func _process(delta: float) -> void:
	advance_turn(delta)
	if _captured():
		update_pad(delta)
	_update_assist_line(delta)
	_check_nade()
	_update_interaction(delta)
	_update_voice()
	_update_give_up(delta)
	if placing:
		_update_ghost()
	if body.view_yaw() != _view_yaw:
		# Taking hold of a casualty to drag (or letting go): the body turns round under the
		# view, so you keep looking where you were, at the casualty.
		_view_yaw = body.view_yaw()
		body.rotate_y(PI)
		body.set_pitch(body.head.rotation.x)
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	body.camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	body.camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	_update_hearing()
	_update_bob(delta)
	_update_melee()


func _melee_input() -> MeleeInput:
	if _melee == null:
		_melee = MeleeInput.new(body)
	return _melee


## The melee controls that work with anything up (MeleeInput): the dodge double-tap, the quick
## melee key (V: a shove with the butt of a gun), the silent kill behind an unaware zombie with a
## blade (the interact key); and the block let go when the melee weapon goes down.
func _update_melee() -> void:
	if not _captured() or not body.vitals.is_up() or is_instance_valid(body.vehicle) or body.respawn_state == Soldier.RESPAWN_WAITING \
			or hud.is_inventory_open() or interaction.is_open() or body.inventory.hands != &"" or body.carry_mode != &"":
		if _melee:
			_melee.drop()
		return
	var weapon := body.active_weapon()
	if not MeleeWeapons.is_melee(weapon):
		if _melee:
			_melee.drop()
		_melee_input()._update_dodge(Soldier._now())
		if Input.is_action_just_pressed(&"quick_melee") and weapon != null and not nade_up and not placing 				and not Input.is_action_pressed(&"interact"):  # (on a pad R3 is self-interact while Y is held)
			body._server_melee.rpc_id(1, "quick")
	if _melee_input().try_silent_kill():
		hud.flash("Silent kill")


## The gamepad's right stick each frame (while the game has the mouse): with View held it picks
## a pad wheel slice; with the interaction menu open it moves the menu's cursor (the stick
## picks a slice of its ring); otherwise it turns the view like the mouse does, through the
## look settings (GameSettings.stick_look: deadzone, curve, invert), the same slowdowns
## (concussion, a scope's zoom, sprinting loaded) and the aim slowdown assist (Assists).
func update_pad(delta: float) -> void:
	stick = Vector2(Input.get_action_raw_strength(&"look_right") - Input.get_action_raw_strength(&"look_left"),
		Input.get_action_raw_strength(&"look_down") - Input.get_action_raw_strength(&"look_up"))
	if pause_menu.is_open() or bug_report.is_open() or medical_menu.is_open() or hud.is_inventory_open() \
			or (hud.map_screen != null and hud.map_screen.is_open()):
		pad_wheel.update(false, Vector2.ZERO)
		return
	if pad_wheel.update(Input.is_action_pressed(&"pad_wheel") and not interaction.is_open(), stick):
		return
	var look := GameSettings.stick_look(stick)
	if look == Vector2.ZERO:
		return
	if interaction.is_open():
		interaction.move_cursor(look * PAD_CURSOR_SPEED * delta)
		return
	var mult := body.vitals.turn_mult() * GunSight.zoom_turn(body) * Assists.aim_slowdown_mult(body, body.camera)
	if body.movement.is_sprinting:
		mult *= lerpf(1.0, MovementRules.SPRINT_TURN_LOADED, MovementRules.load_fraction(body.load_kg))
	var turn := GameSettings.stick_turn(look, body.is_aiming, delta, mult)
	turn_view(-turn.x)
	body.set_pitch(body.head.rotation.x - turn.y)


## The assists' HUD line (Assists.wound_hint), refreshed a few times a second.
func _update_assist_line(delta: float) -> void:
	_hint_left -= delta
	if _hint_left > 0.0:
		return
	_hint_left = 0.5
	assist_line.text = Assists.wound_hint(body) if body.respawn_state != Soldier.RESPAWN_WAITING else ""
	assist_line.visible = assist_line.text != ""


## The view and weapon move with the steps (footfall dips; the head's own bob: _place_eye; WEAPON_BOB), the weapon comes down to
## carry at a sprint (SPRINT_VIEW, SPRINT_TILT); none of it aimed.
func _update_bob(delta: float) -> void:
	var walking := body.is_on_floor() and body.vitals.is_up() and not is_instance_valid(body.vehicle) and body.carry_mode == &""
	var w := body.model.gait_weight() if walking and not body.is_aiming else 0.0
	_bob_w = move_toward(_bob_w, w, delta * 4.0)
	var jogging := walking and not body.is_aiming and body.model.gait() == CharacterModel.JOG
	_sprint_w = move_toward(_sprint_w, 1.0 if body.movement.is_sprinting and walking else (JOG_CARRY if jogging else 0.0), delta * 5.0)
	_sprint_fov_w = move_toward(_sprint_fov_w, 1.0 if body.movement.is_sprinting and walking else 0.0, delta * 3.0)
	var pace := clampf(body.model.gait_speed() / SoldierMovement.SPRINT_SPEED, 0.0, 1.0) * _bob_w
	_update_landing(minf(delta, 0.05))
	_update_step_smooth(delta)
	var motion := GameSettings.camera_motion()
	if motion > 0.0:
		# The gait's bob and sway are the drawn head's own now (_place_eye); the footfalls' dip and
		# the landing stay the view's.
		var d := fposmod(body.model.gait_phase() * 2.0, 1.0) * FOOT_DIP_SHARP  # a footfall twice a stride
		var dip := -FOOT_DIP * pace * d * exp(1.0 - d)
		body.camera.position = Vector3(0.0, (dip + _land_y) * motion + _step_y, 0.0)
	else:
		body.camera.position = Vector3(0.0, _step_y, 0.0)  # (steps are smoothed with head bob off too)
	_medic_eye = body.head.basis.orthonormalized().inverse() * (body.model.treat_view_offset() * body.model.body_scale())
	body.camera.position += _medic_eye  # down on a knee at the casualty, bent over the work
	_cam_base = body.camera.position
	_head_hide_t -= delta
	if _head_hide_t <= 0.0:
		_head_hide_t = 0.25
		_hide_own_head()


## Your own head and all on it out of your own view (LOCAL_ONLY_LAYER): face, hair, the helmet
## and its kit, ear pro, wound marks; whatever is added there later is caught within a quarter
## second.
func _hide_own_head() -> void:
	if body.model.head == null:
		return
	for v: Node in body.model.head.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = LOCAL_ONLY_LAYER


## The camera in the drawn head's eyes and, aimed, behind the body's own sight (EYE_*, ADS_*):
## after the frame's animation (RenderingServer.frame_pre_draw), on top of _cam_base.
func _place_eye() -> void:
	if not is_instance_valid(body) or not body.camera.current or body.model.head == null:
		return
	var delta := get_process_delta_time()
	var on_foot := body.vitals.is_up() and not is_instance_valid(body.vehicle) and body.carry_mode == &"" \
		and body.respawn_state != Soldier.RESPAWN_WAITING
	var raw := Vector3.ZERO
	if on_foot:
		var drawn := body.model.head.global_transform * EYE_IN_HEAD
		raw = body.global_basis.inverse() * (drawn - body.head.global_position)
		raw -= body.model.treat_view_offset() * body.model.body_scale()  # (the medic's kneel: _cam_base has it)
		raw = raw.limit_length(EYE_REACH_M)
	_eye_slow = _eye_slow.lerp(raw, 1.0 - exp(-delta / EYE_STEADY_S))
	var eye := _eye_slow.lerp(raw, EYE_RAW_SHARE) * GameSettings.camera_motion()
	var pos := _cam_base + body.head.basis.orthonormalized().inverse() * eye
	# Aimed: the eye behind the sight of the gun in the body's own hands.
	var sight := _sight_eye()
	_ads_w = move_toward(_ads_w, 1.0 if sight.is_finite() and body.is_aiming and on_foot else 0.0, delta * ADS_EASE)
	if _ads_w > 0.0 and sight.is_finite():
		pos = pos.lerp(body.head.global_transform.affine_inverse() * sight, smoothstep(0.0, 1.0, _ads_w))
	body.camera.position = pos


## Where the eye goes aimed (world): ADS_EYE back along the barrel from the sight of the gun in
## the body's hands; INF with none.
func _sight_eye() -> Vector3:
	var held: Node3D = body.model.get(&"_held")
	if not is_instance_valid(held) or not held.has_meta(&"voxel_model") or not body.model.get(&"_held_weapon"):
		return Vector3.INF
	var model := String(held.get_meta(&"voxel_model"))
	if not (model.begins_with("rifle") or model.begins_with("pistol")):
		return Vector3.INF
	var eye := ADS_EYE_PISTOL if model.begins_with("pistol") else ADS_EYE
	return held.global_transform * (VoxelArt.sight_point(model) - eye)


## Whether the view model shows: only what the body doesn't draw in your hands (a thrown grenade);
## the gun and arms you see are the body's own.
func _view_model_shown() -> bool:
	return body.view_model.get_node_or_null(^"HeldGrenade") != null


## The step-up smoothing (STEP_SMOOTH): a sudden small rise on the floor is taken back off the view
## and eased away.
func _update_step_smooth(delta: float) -> void:
	var y := body.global_position.y
	if _step_last_y != INF:
		var rise := y - _step_last_y
		var walking := Vector2(body.velocity.x, body.velocity.z).length() > 0.5  # (a step needs a walk: not the settle at a spawn)
		if walking and rise > 0.03 and rise <= STEP_SMOOTH_MAX_M and body.is_on_floor() and not is_instance_valid(body.vehicle) and not body.movement.mantling:
			_step_y = maxf(_step_y - rise, -STEP_SMOOTH_MAX_M)
	_step_last_y = y
	_step_y = lerpf(_step_y, 0.0, 1.0 - exp(-STEP_SMOOTH * delta))
	if absf(_step_y) < 0.0005:
		_step_y = 0.0


## Going down dying (Vitals.is_dying): told once, what to do.
var _was_dying := false


func _note_dying() -> void:
	var dying := body.vitals.is_dying()
	if dying and not _was_dying:
		flash("You're going down. Treat yourself (Medical menu) or call a medic (Command > Status > Medic!).")
	_was_dying = dying


## The landing dip (LAND_*): the fall's speed, taken on touching down, kicks a damped spring.
func _update_landing(delta: float) -> void:
	var on_floor := body.is_on_floor() and not is_instance_valid(body.vehicle)
	if not on_floor:
		_air_vy = minf(_air_vy, body.velocity.y)
		_air_t += delta
	elif not _was_floor:
		if _air_t >= LAND_MIN_AIR_S:
			var dip := minf(-_air_vy * LAND_DIP_PER_MPS, LAND_DIP_MAX)
			_land_v -= dip * sqrt(LAND_SPRING) * 1.8  # (peaks near `dip` at this damping)
		_air_vy = 0.0
		_air_t = 0.0
	_was_floor = on_floor
	_land_v += (-LAND_SPRING * _land_y - 2.0 * LAND_DAMP * sqrt(LAND_SPRING) * _land_v) * delta
	_land_y += _land_v * delta
	if absf(_land_y) < 0.0005 and absf(_land_v) < 0.005:
		_land_y = 0.0  # settled: the view stands still again
		_land_v = 0.0


## The view's nod with pace changes along it (ACCEL_PITCH), eased; none in a vehicle or down.
func _update_feel_pitch(delta: float) -> void:
	var fwd := -body.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	var fwd_speed := Vector2(body.velocity.x, body.velocity.z).dot(flat.normalized()) if flat.length() > 0.01 else 0.0
	var accel := (fwd_speed - _last_fwd_speed) / maxf(delta, 0.001)
	_last_fwd_speed = fwd_speed
	var target := 0.0
	if body.is_on_floor() and body.vitals.is_up() and not is_instance_valid(body.vehicle) and GameSettings.head_bob():
		target = clampf(accel * ACCEL_PITCH, -ACCEL_PITCH_MAX, ACCEL_PITCH_MAX) * (0.3 if body.is_aiming else 1.0)
	_feel_pitch = lerpf(_feel_pitch, target, 1.0 - exp(-10.0 * delta))


## The weapon's bob this frame (camera-local), on top of where it sits.
func weapon_bob() -> Vector3:
	var pace := clampf(body.model.gait_speed() / SoldierMovement.SPRINT_SPEED, 0.0, 1.0) * _bob_w
	var phase := TAU * body.model.gait_phase()
	var side := -1.0 if body.left_handed else 1.0
	return Vector3(sin(phase) * WEAPON_BOB.x * pace, -absf(cos(phase)) * WEAPON_BOB.y * pace, 0.0) \
		+ SPRINT_VIEW * Vector3(side, 1, 1) * _sprint_w


## Muffled hearing (blasts, flashbangs, indoor gunfire): a low-pass on the master bus while
## Vitals.deaf_left() runs, and a note when it starts.
func _update_hearing() -> void:
	if not body.is_local():
		return
	var deaf := body.vitals.deaf_left() > 0.0
	if deaf == _deaf:
		return
	_deaf = deaf
	set_muffled(deaf)
	if deaf:
		flash("Ears ringing")


## The Master bus volume from before hearing was muffled (put back when it clears).
static var _volume_before := 0.0


## Muffles the Master bus (a low-pass, quieter) or clears it, putting back the volume from
## before; already so, it does nothing. The bus is global and outlives the player: whoever
## muffles it clears it again (audit A2-04: deaf when leaving, the menu and the next session
## stayed muffled).
static func set_muffled(on: bool) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	var has_filter := AudioServer.get_bus_effect_count(bus) > 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLowPassFilter
	if on == (has_filter and AudioServer.is_bus_effect_enabled(bus, 0)):
		return
	if on:
		if not has_filter:
			var filter := AudioEffectLowPassFilter.new()
			filter.cutoff_hz = DEAF_CUTOFF_HZ
			AudioServer.add_bus_effect(bus, filter, 0)
		_volume_before = AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_effect_enabled(bus, 0, on)
	AudioServer.set_bus_volume_db(bus, _volume_before + DEAF_VOLUME_DB if on else _volume_before)


## Leaving (the session ends, the level changes, the body goes): hearing comes back with it.
func _exit_tree() -> void:
	if _deaf:
		_deaf = false
		set_muffled(false)


## Runs after the body has moved this frame (children process after their parent).
func _physics_process(delta: float) -> void:
	var waiting := body.respawn_state == Soldier.RESPAWN_WAITING  # dead, waiting to respawn: no aiming or firing
	if waiting:
		body.is_aiming = false
	else:
		_update_focus()
		_update_aim(delta)
		_try_fire()
	_update_reload_hand()
	var treating := body.model.action_shown() == CharacterModel.TREAT and not waiting
	body.model.set_view_hands(treating)
	_update_view_hands(delta)
	_update_medic_look(delta, treating)
	var tilt := minf(minf(-0.7 if body.movement.mantling else 0.0, -CharacterModel.VIEW_LOWER_PITCH * body.model.view_lower()), SPRINT_TILT.x * _sprint_w)  # mantling: weapon down
	tilt = lerpf(minf(tilt, LOW_READY_TILT.x * _low_w), _reload_rot.x, _reload_w)
	_vm_pitch = move_toward(_vm_pitch, tilt, delta * 6.0)
	body.view_model.rotation.x = _vm_pitch
	if body.recoil_return > _last_recoil + 0.0001:  # a shot: the weapon kicks
		_view_press_t = CharacterModel.PRESS_S  # and the trigger finger squeezes
		_view_shot_t = 0.0
		var w := body.active_weapon()
		_view_kick = clampf(_view_kick + (clampf(float(w.stats.get("recoil_deg", 0.7)) / 0.7, 0.4, 2.0) if w else 1.0), 0.0, 2.0)
	_last_recoil = body.recoil_return
	_view_kick = move_toward(_view_kick, 0.0, delta * VIEW_KICK_DECAY)
	var kick_k := _view_kick * (0.35 if body.is_aiming else 1.0)
	body.view_model.rotation.x += VIEW_KICK_PITCH * kick_k
	# Both hands on the casualty: no weapon in view; nor seated in a vehicle (no firing your own
	# from a seat, and in first person it hid the cabin and poked through the dash), unless it's a
	# fire-from-vehicle seat (VehicleBay: your own weapon up); nor dead, waiting to respawn.
	# Through a scope the gun still shows peripherally (P0362 PIP rework: the magnified glass is
	# GunSight's own SubViewport, which skips it on VIEW_MODEL_LAYER instead); with PiP off the
	# whole view is the glass, as before PiP, and the gun goes.
	body.view_model.visible = body.carry_mode == &"" and not waiting and not treating \
		and (not is_instance_valid(body.vehicle) or body.vehicle.ffv_seat(body)) \
		and (GunSight.pip_on(body) or not GunSight.scoped(body)) and _view_model_shown()
	_settle_recoil(delta)
	_update_feel_pitch(delta)
	_update_sway(delta)
	_hide_shouldered()
	# Settle sway after a stop (W3, SoldierMovement.weapon_sway).
	var sway := body.movement.weapon_sway()
	var side := -1.0 if body.left_handed else 1.0
	_look_lag = _look_lag.lerp(Vector2.ZERO, 1.0 - exp(-LOOK_LAG_RETURN * delta))
	var lag := _look_lag * (LOOK_LAG_AIMED if body.is_aiming else 1.0)  # the weapon trails the mouse
	# Real (Captain, 2026-10-26: inertia changes where rounds go): the body's own gun trails it, and
	# the round leaves where it points. Aimed, the view rides the gun (_update_sway), so only the
	# lag the camera doesn't show yet goes on the shot (Soldier.shot_lag).
	body.model.aim_lag = lag
	body.shot_lag = lag * (1.0 - smoothstep(0.0, 1.0, _ads_w))
	_view_lag = lag
	body.view_model.rotation.x += lag.y
	body.view_model.rotation.y = sway.x + SPRINT_TILT.y * side * _sprint_w + LOW_READY_TILT.y * side * _low_w + _reload_rot.y * side * _reload_w + lag.x
	body.view_model.rotation.z = sway.y + SPRINT_TILT.z * side * _sprint_w + _reload_rot.z * side * _reload_w - lag.x * 0.5
	hud.update_status(body)


## How long the give-up key has been held (0 when it isn't, or giving up isn't open): the HUD's prompt.
var give_up_held := 0.0
var _give_up_sent := false


## Downed: holding the give-up key (Controls "give_up") for Soldier.GIVE_UP_HOLD_S, while
## Soldier.can_give_up(), asks the host to let this player die and respawn (Captain, P0362).
func _update_give_up(delta: float) -> void:
	var menus := pause_menu.is_open() or bug_report.is_open() or medical_menu.is_open() or hud.is_inventory_open() \
		or (hud.map_screen != null and hud.map_screen.is_open())
	if not body.can_give_up() or menus or not Input.is_action_pressed(&"give_up"):
		give_up_held = 0.0
		_give_up_sent = false
		return
	give_up_held += delta
	if give_up_held >= Soldier.GIVE_UP_HOLD_S and not _give_up_sent:
		_give_up_sent = true
		body._server_give_up.rpc_id(1)


## The first-person medic view's turn to the work (MEDIC_LOOK_*): a new treatment starts it.
func _update_medic_look(delta: float, treating: bool) -> void:
	if not treating:
		_medic_look = 0.0
		return
	var n := int(body.model.action_net.get("n", -1))
	if n != _medic_n:
		_medic_n = n
		_medic_look = MEDIC_LOOK_S
	if _medic_look <= 0.0:
		return
	_medic_look -= delta
	var site := body.model.treat_site()
	var aim: Vector3 = site.p if not site.is_empty() else (body.model.hand_position(true) + body.model.hand_position(false)) * 0.5
	var to := aim - body.camera.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var k := 1.0 - exp(-MEDIC_LOOK_RATE * delta)
	var mine := not bool(body.model.action_net.get("kneel", false))  # yourself: the work turns with you
	if flat.length() > 0.2 and not mine:
		var ahead := -body.camera.global_basis.z
		ahead.y = 0.0
		var turn := ahead.signed_angle_to(flat, Vector3.UP) if ahead.length() > 0.01 else 0.0
		if absf(turn) > MEDIC_LOOK_SLACK:
			body.rotate_y(turn * k)
	var pitch := atan2(to.y, maxf(flat.length(), 0.01))
	var now := body.head.rotation.x
	if absf(pitch - now) > MEDIC_LOOK_SLACK:
		body.set_pitch(now + (pitch - now) * k)


## Keeps the casualty this player has up on the shoulder out of their own camera (they still see
## it lifted off the ground and laid back down).
func _hide_shouldered() -> void:
	var shown := body.model.carry_shown()
	var on: Soldier = null
	if shown.get("mode", &"") == CharacterModel.CARRY:
		var ph := body.model.carry_phase()
		var up: bool = ph.is_empty() or (ph.phase == &"lift" and ph.u > 0.8) or (ph.phase == &"lower" and ph.u < 0.2)
		on = shown.get("body") as Soldier if up else null
	if on == _shouldered:
		return
	if is_instance_valid(_shouldered):
		_shouldered.model.render_layers = 1
		_shouldered.gear.render_layers = 1
	_shouldered = on
	if on:
		on.model.render_layers = LOCAL_ONLY_LAYER
		on.gear.render_layers = LOCAL_ONLY_LAYER


## Where the crosshair meets the world (up to 150 m), or null.
## Tags the enemy under the crosshair for the squad (EnemyTags; the host checks the radio, the
## range and that he can be seen).
func _tag_enemy() -> void:
	var from := body.camera.global_position
	var exclude: Array[RID] = [body.get_rid()]
	for child in body.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, from - body.camera.global_basis.z * EnemyTags.TAG_RANGE_M, 0xFFFFFFFF, exclude)
	q.collide_with_areas = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	var node: Node = hit.get("collider") if not hit.is_empty() else null
	while node and not node is Soldier:
		node = node.get_parent()
	if node == null:
		hud.flash("Look at an enemy to tag him")
		return
	body._server_tag_enemy.rpc_id(1, (node as Soldier).name)


## How far the crosshair reaches for an order's point or target (Captain, 2026-10-20: "increase
## the range the player can give squad ai orders"; was 150 m for a point, 300 m for a target).
const ORDER_RANGE_M := 800.0


func crosshair_ground() -> Variant:
	var from := body.camera.global_position
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from - body.camera.global_basis.z * ORDER_RANGE_M, 1, [body.get_rid()]))
	return null if hit.is_empty() else hit.position


func flash(text: String) -> void:
	if hud:
		SessionLog.note("shown to the player: " + text)
		hud.flash(text)
	elif body and body.is_ai():  # an AI's own messages (what it's treating, why it can't): no screen, but worth a line
		SessionLog.note("%s (AI): %s" % [body.log_name(), text])


## A flashbang went off in sight: the whiteout is strongest when you were looking at it.
func flashed(pos: Vector3, amount: float) -> void:
	if hud == null:
		return
	var camera := body.camera
	var facing := (-camera.global_basis.z).dot((pos - camera.global_position).normalized())
	hud.whiteout(amount * (1.0 if facing > 0.3 else 0.35))


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The prompt for what's under the crosshair: an item, or a downed body. Everything you can
## do with them is in the interaction menu (hold Left Ctrl).
func _update_focus() -> void:
	_focus = null
	if not body.vitals.is_up() or interaction.is_open():
		hud.set_prompt("")
		hud.hide_item_info()
		return
	var camera := body.camera
	var from := camera.global_position
	var exclude: Array[RID] = [body.get_rid()]
	for child in body.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var mask := Soldier.ITEM_MASK | Soldier.HITBOX_MASK | 1
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * InteractionMenu.REACH, mask, exclude)
	query.collide_with_areas = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	var other := Vitals.find_on(collider) if collider is Area3D else null
	if other and other.downed:
		_focus = other.get_parent()
		hud.set_prompt("[Ctrl] %s (down)" % InteractionMenu.display_name(_focus))
	elif collider is WorldItem:
		_focus = collider
		hud.set_prompt("[Ctrl] %s    [%s] Inspect" % [(collider as WorldItem).describe(), OS.get_keycode_string(GameSettings.key_for(&"inspect"))])
	else:
		hud.set_prompt("")
	# The inspect panel goes once the crosshair leaves its item.
	if hud.inspected() != &"" and not (_focus is WorldItem and (_focus as WorldItem).item_id == hud.inspected()):
		hud.hide_item_info()


## The inspect key (I; Captain, 2026-10-14: "item descriptions plus uses also needed"): shows
## the item under the crosshair's description, uses and numbers (ItemInfo) in the middle of the
## HUD, or takes it away again. Looking away from the item takes it away too (_update_focus).
func toggle_inspect() -> void:
	if hud.inspected() != &"":
		hud.hide_item_info()
	elif _focus is WorldItem:
		hud.show_item_info((_focus as WorldItem).item_id)


## Hold Left Ctrl for the interaction menu, Left Ctrl + Left Alt for yourself; letting go
## performs the highlighted action. Going down or opening the inventory cancels it.
func _update_interaction(delta: float) -> void:
	var allowed := _captured() and body.vitals.is_up() and body.respawn_state != Soldier.RESPAWN_WAITING and not hud.is_inventory_open()
	if not allowed:
		if interaction.is_open():
			interaction.close()
		return
	if interaction.update_keys(Input.is_action_pressed(&"interact"), Input.is_action_pressed(&"self_interact"), delta):
		var text := InteractionMenu.perform(body, interaction.chosen)
		if text != "":
			hud.flash(text)
		return
	match interaction.mode:
		InteractionMenu.Mode.OBJECT:
			interaction.set_points(InteractionMenu.collect_points(body, body.camera))
		InteractionMenu.Mode.SELF:
			interaction.refresh_self()


## Hold T (`voice_order`) for a push-to-talk squad order; see VoiceOrder. Blocked while down,
## respawning, with the inventory open, or the mouse isn't captured.
func _update_voice() -> void:
	var allowed := _captured() and body.vitals.is_up() and body.respawn_state != Soldier.RESPAWN_WAITING \
		and not hud.is_inventory_open() and not interaction.is_open()
	hud.voice_order.update_key(allowed and Input.is_action_pressed(&"voice_order"))


func _try_fire() -> void:
	if BuildMode.is_on(body):
		return  # building: Fire places and works blocks (BuildMode)
	if body.binoculars_up or body.vitals.is_dying():
		return  # glassing, or dying on the ground: no shooting
	if not _captured() or placing or nade_up or body.inventory.hands != &"" or not body.vitals.is_up() or interaction.is_open() \
			or body.carry_mode != &"" or body.movement.mantling:  # both hands on the casualty, or on the ledge
		return
	if is_instance_valid(body.vehicle):
		if not body.vehicle.ffv_seat(body):
			return  # riding: the seat's gun fires (Vehicle)
		if not body.vehicle.ffv_ok(body, -body.camera.global_basis.z):
			if Input.is_action_just_pressed(&"fire"):
				hud.flash("No line out of the door")
			return
	var weapon := body.active_weapon()
	if Launchers.is_launcher(weapon):
		LauncherSight.of(body).try_fire()  # its own fire path (wave 5)
		return
	if weapon == null or weapon.type != "weapon":
		return
	if MeleeWeapons.is_melee(weapon):
		_melee_input().update(hud)  # swings, the block, the dodge (MeleeInput)
		return
	if body.underbarrel_up and Shotguns.key_of(body) != null:
		if Input.is_action_just_pressed(&"fire"):
			_fire_key(weapon)  # the Skeleton Key under it (4 switched to it)
		return
	if body.underbarrel_up and Underbarrel.on_gun(body) != null:
		if Input.is_action_just_pressed(&"fire"):
			_fire_underbarrel(weapon)  # the M320 under it (4 switched to it)
		return
	# Fire mode (W3): F moves the selector; the trigger follows the mode.
	if Input.is_action_just_pressed(&"fire_mode") and Soldier.fire_modes_of(weapon).size() > 1:
		hud.flash(body.cycle_fire_mode().capitalize())
	if not Soldier.trigger_fires(body.fire_mode(), Input.is_action_pressed(&"fire"), Input.is_action_just_pressed(&"fire")):
		return
	var now := Soldier._now()
	if now < body._next_shot or now < body._busy_until:
		return
	if body.inventory.rounds_in(body.active_slot) <= 0:
		if Input.is_action_just_pressed(&"fire"):
			var spare := body.inventory.spare_rounds(Soldier._ammo_of(weapon), weapon) > 0
			hud.flash("Empty - R to reload" if spare else "Out of ammo")
		return
	body._next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	var kick := Shotguns.recoil_of(weapon, body.inventory.state_of(body.active_slot))  # (the shell about to go: hi-brass kicks harder)
	body._server_fire.rpc_id(1, body.camera.global_position, body._spread_direction(weapon), body.active_slot)
	body._kick(weapon, kick)


## Fire with the trigger on the Skeleton Key: the host fires its next shell (Shotguns.server_fire_key).
func _fire_key(weapon: ItemData) -> void:
	var now := Soldier._now()
	var key := Shotguns.key_of(body)
	if now < body._busy_until or now < body._next_shot:
		return
	var state := body.inventory.state_of(body.active_slot)
	var tube := Shotguns.key_list(key, state)
	if tube.is_empty():
		hud.flash("Empty - R to load" if Shotguns.spare_shells(body.inventory, key) > 0 else "No shells for the Skeleton Key")
		return
	body._next_shot = now + 60.0 / float(key.stats.get("rpm", 50))
	var kick := float((ItemDB.get_item(StringName(String(tube.back()))).stats if ItemDB.has_item(StringName(String(tube.back()))) else {}).get("recoil_mult", 1.0))
	body._server_fire_key.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z)
	body._kick(key, kick)


## Fire with the trigger on the M320: the host lobs the grenade (Launchers.request_fire_underbarrel).
func _fire_underbarrel(weapon: ItemData) -> void:
	var now := Soldier._now()
	var launchers := Launchers.of(body)
	if launchers == null or now < body._busy_until:
		return
	if Underbarrel.loaded_of(body) == &"":
		hud.flash("Empty - R to load" if not Underbarrel.carried_rounds(body).is_empty() else "No 40 mm grenades")
		return
	body._busy_until = now + Underbarrel.FIRE_BUSY_S
	launchers.request_fire_underbarrel.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z)
	body._kick(weapon)
	body._kick(weapon)  # (a 40 mm grenade kicks harder than the rifle's round)


## Recoil settles: Soldier.RECOIL_SETTLE of each kick comes back down (Captain, P0362), so
## the view kicks and settles and auto fire climbs by the rest.
func _settle_recoil(delta: float) -> void:
	if body.recoil_return <= 0.0:
		return
	var step := minf(body.recoil_return, body.recoil_return * RECOIL_SETTLE_RATE * delta + 0.0002)
	body.recoil_return -= step
	body.set_pitch(body.head.rotation.x - step)


## Aimed sway (Soldier.aim_sway, P0362): the camera itself drifts, so the sight shows where the
## shot goes. Eases in and out as you aim and lower.
func _update_sway(delta: float) -> void:
	var weapon := body.active_weapon()
	var sway := body.aim_sway(weapon, Soldier._now()) if weapon and weapon.type == "weapon" and not Launchers.is_launcher(weapon) else Vector2.ZERO
	var k := minf(delta * 8.0, 1.0)
	_cam_turn = _cam_turn.lerp(Vector2(sway.x + _feel_pitch, sway.y), k)
	var gaze := gaze_turn(body.camera.position - _medic_eye)  # (the steps' moves, not the kneel)
	var ads := smoothstep(0.0, 1.0, _ads_w)  # aimed: the view looks along the gun, lag and all
	body.camera.rotation.x = _cam_turn.x + gaze.x + _view_lag.y * ads
	body.camera.rotation.y = _cam_turn.y + gaze.y + _view_lag.x * ads


## The turn (pitch, yaw: radians) that keeps the eye, moved `offset` (m, head space) by the steps,
## looking at the point GAZE_FOCUS_M straight ahead: up a little, it looks down a little.
static func gaze_turn(offset: Vector3) -> Vector2:
	return Vector2(-atan2(offset.y, GAZE_FOCUS_M), atan2(offset.x, GAZE_FOCUS_M))


## The mouse wheel's pace on foot (feel round 2, Captain 2026-10-20): each notch a pace faster
## (`steps` 1, up) or slower (-1, down) through SoldierMovement.Pace, shown on the HUD. Not
## aiming (nor glassing), not aboard a vehicle, not down; the command menu, the interaction
## menu and a grenade in hand take the wheel before this. Whether it stepped.
func wheel_pace(steps: int) -> bool:
	if is_instance_valid(body.vehicle) and body.vehicle is Mount and not Input.is_action_pressed(&"aim"):
		return (body.vehicle as Mount).local_wheel(steps, hud)  # riding: the gait (walk, trot)
	if body.is_aiming or Input.is_action_pressed(&"aim") or body.binoculars_up or is_instance_valid(body.vehicle) \
			or not body.vitals.is_up() or body.respawn_state == Soldier.RESPAWN_WAITING:
		return false
	var now := Soldier._now()
	if now - _pace_wheel_at < PACE_WHEEL_GAP_S:
		return false
	_pace_wheel_at = now
	body.movement.step_pace(steps)
	hud.flash("Pace: %s" % SoldierMovement.PACE_NAMES[body.movement.pace])
	return true


## Where the view model goes aimed with `weapon` (camera-local), its item state `state`
## naming its optic: its sight point on the eye's line, ADS_EYE in front (ADS_EYE_PISTOL for a
## pistol).
static func ads_view(weapon: ItemData, state := {}) -> Vector3:
	var model := VoxelArt.model_for(weapon, state)
	var eye := ADS_EYE_PISTOL if model.begins_with("pistol") else ADS_EYE
	return eye - VoxelArt.sight_point(model)


## Raises or lowers the binoculars (BINOS): raising needs a pair carried, hands free and up.
func _set_binoculars(up: bool) -> void:
	if up and (body.inventory.count_of(BINOS) <= 0 or body.inventory.hands != &"" or not body.vitals.is_up() or nade_up or placing):
		if up and body.inventory.count_of(BINOS) <= 0:
			hud.flash("No binoculars")
		return
	body.binoculars_up = up
	if _binos_view:
		_binos_view.show_frame(up)
	if body.view_model:
		body.view_model.visible = not up  # the weapon's down while he's glassing


## The binoculars' field of view: the view narrowed by their magnification (relative to the view,
## as optics are).
func _binos_fov() -> float:
	var item := ItemDB.get_item(BINOS)
	var x := float(item.stats.get("magnification", 7.0)) if item else 7.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(GameSettings.view_fov()) * 0.5) / maxf(x, 1.0)))


func _update_aim(delta: float) -> void:
	_note_dying()
	if body.vitals.is_dying():
		body.is_aiming = false
	if body.binoculars_up and (not body.vitals.is_up() or is_instance_valid(body.vehicle) or Input.is_action_pressed(&"sprint") \
			or body.inventory.count_of(BINOS) <= 0 or body.inventory.hands != &""):
		_set_binoculars(false)  # sprinting, down, aboard, or the pair's gone
	if body.binoculars_up:
		body.is_aiming = false
		body.camera.fov = lerpf(body.camera.fov, _binos_fov(), minf(delta * 10.0, 1.0))
		return
	var weapon := body.active_weapon()
	var was_aiming := body.is_aiming
	body.is_aiming = _captured() and not nade_up and body.vitals.is_up() and weapon != null and (weapon.type == "weapon" and not MeleeWeapons.is_melee(weapon) or Launchers.is_launcher(weapon)) \
		and body.inventory.hands == &"" and not body.is_reloading and not body.movement.mantling and Input.is_action_pressed(&"aim")
	if body.is_aiming and not was_aiming:
		# Up from low (the sprint carry, the low ready) takes longer than from the ready.
		_ads_low = clampf(maxf(_sprint_w, _low_w), 0.0, 1.0)
	var fov := GunSight.aimed_fov_of(body, weapon, GameSettings.view_fov()) if body.is_aiming else GameSettings.view_fov() + SPRINT_FOV * _sprint_fov_w
	# Up to the eye in the weapon's ADS time (its mass with optic, slower on tired arms:
	# MovementRules.ads_seconds); lowering stays quick.
	var rate := MovementRules.ADS_EASE_K / body.movement.ads_seconds(_ads_low) if body.is_aiming else 14.0
	var fov_k := minf(delta * (rate if body.is_aiming else 12.0), 1.0)
	# `fov` is what the sight shows: its own eased "glass" field of view (GunSight.ease_glass),
	# which drives SCOPE_IN (scoped) and the scope's SubViewport camera. The player's real camera
	# only follows it for irons and open optics (the whole screen zooms, as before); behind a tube
	# optic's glass (or a flipped-up magnifier) it eases back to the peripheral view instead — a
	# real PIP (GunSight), not the whole screen narrowing, so the gun's surroundings stay visible
	# around the scope picture (Captain: "better scopes and PIP"). With PiP off (the setting, or
	# headless: GunSight.pip_on) the whole view zooms behind the ring, as before PiP.
	GunSight.ease_glass(body, fov, fov_k)
	var peripheral := GameSettings.view_fov() if GunSight.pip_on(body) else fov
	body.camera.fov = lerpf(body.camera.fov, peripheral, fov_k)
	var hip_view := HIP_VIEW * Vector3(-1.0 if body.left_handed else 1.0, 1, 1)  # off the firing shoulder
	var aimed_view := ads_view(weapon, body.inventory.state_of(body.active_slot)) if weapon and not Launchers.is_launcher(weapon) else hip_view
	var lowered := CharacterModel.VIEW_LOWER_OFFSET * body.model.view_lower()  # ducks while the hands are busy
	wall_pull = move_toward(wall_pull, wall_pull_at(), delta * 6.0)
	var pulled := MovementRules.WALL_PULL_BACK * Vector3(-1.0 if body.left_handed else 1.0, 1, 1) * wall_pull  # a wall ahead: weapon back
	if body.is_aiming or Input.is_action_pressed(&"fire") or body.is_reloading or nade_up:
		_ready_hold = LOW_READY_AFTER_S
	else:
		_ready_hold = maxf(_ready_hold - delta, 0.0)
	var low := _ready_hold <= 0.0 and _sprint_w < 0.2
	_low_w = move_toward(_low_w, 1.0 if low else 0.0, delta * (2.5 if low else 10.0))  # down slowly, up at once
	_reload_w = move_toward(_reload_w, 1.0 if body.is_reloading else 0.0, delta * 12.0)  # (the keys ease it in and out)
	var side_v := Vector3(-1.0 if body.left_handed else 1.0, 1, 1)
	var settle := LOW_READY_VIEW * side_v * _low_w + Vector3(-_reload_pos.x, _reload_pos.y, _reload_pos.z) * side_v * _reload_w
	_vm_base = _vm_base.lerp((aimed_view if body.is_aiming else hip_view) + lowered + pulled + settle, minf(delta * rate, 1.0))
	body.view_model.position = _vm_base + weapon_bob() + Vector3(0.0, 0.0, VIEW_KICK_BACK * _view_kick * (0.35 if body.is_aiming else 1.0))


## How far a wall ahead pushes the weapon back now: 0 clear (past WALL_PULL_REACH_M from the eye)
## to 1 (at WALL_PULL_MIN_M or closer).
func wall_pull_at() -> float:
	if not body.is_inside_tree():
		return 0.0
	var from := body.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - body.camera.global_basis.z * MovementRules.WALL_PULL_REACH_M, 1, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	var d := from.distance_to(hit.position)
	return clampf((MovementRules.WALL_PULL_REACH_M - d) / (MovementRules.WALL_PULL_REACH_M - MovementRules.WALL_PULL_MIN_M), 0.0, 1.0)


func _try_reload() -> void:
	var weapon := body.active_weapon()
	var now := Soldier._now()
	if Launchers.is_launcher(weapon):
		LauncherSight.of(body).try_reload()  # load or swap its round (wave 5)
		return
	if nade_up or weapon == null or weapon.type != "weapon" or now < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	if body.underbarrel_up and Shotguns.key_of(body) != null:
		_load_shells(Shotguns.key_of(body), true)  # the Skeleton Key, shell by shell
		return
	if body.underbarrel_up and Underbarrel.on_gun(body) != null:
		_load_underbarrel()  # the M320, by hand
		return
	if Shotguns.is_tube(weapon):
		_load_shells(weapon)  # a shotgun's tube, shell by shell
		return
	var ammo := Soldier._ammo_of(weapon)
	var full := ItemDB.get_item(ammo).magazine_rounds() if ItemDB.has_item(ammo) else 0
	if body.inventory.rounds_in(body.active_slot) >= full:
		return
	if body.inventory.spare_rounds(ammo) <= 0:
		hud.flash("No spare magazines")
		return
	var empty := body.inventory.rounds_in(body.active_slot) <= 0
	body._busy_until = now + body.reload_seconds(weapon, empty)
	_reload_from = now
	_reload_len = maxf(body.reload_seconds(weapon, empty), 0.1)
	_reload_keys = Reloads.keys(Reloads.family(weapon), empty)
	_reload_parts = Reloads.parts(Reloads.family(weapon), empty)
	body.begin_reload_local(weapon.id, empty, _reload_len)  # its sounds, on the keys' beats, heard now
	body.is_reloading = true
	body._server_reload.rpc_id(1, body.active_slot)


## R with the trigger on the M320: a grenade in by hand (Underbarrel.server_reload).
func _load_underbarrel() -> void:
	var launchers := Launchers.of(body)
	var choice := Underbarrel.next_round(body)
	if launchers == null or choice == &"":
		hud.flash("No 40 mm grenades" if Underbarrel.carried_rounds(body).is_empty() else "Already loaded")
		return
	body._busy_until = Soldier._now() + float(Underbarrel.on_gun(body).stats.get("reload_s", 3.0)) * body.vitals.reload_mult()
	hud.flash("Loading %s" % ItemDB.get_item(choice).name)
	launchers.request_reload_underbarrel.rpc_id(1, choice)


## R with a shotgun (with `key`, the Skeleton Key under the gun): a speed loader in one push, or
## shells into the tube one by one, the picked kind first (Shotguns.server_load). Breaching rounds
## a gun won't take say so (Shotguns.why_not).
func _load_shells(weapon: ItemData, key := false) -> void:
	var state := body.inventory.state_of(body.active_slot)
	var have := Shotguns.key_list(weapon, state).size() if key else body.inventory.rounds_in(body.active_slot)
	if have >= Shotguns.capacity(weapon):
		return
	var loader := not key and Shotguns.capacity(weapon) - have >= Shotguns.LOADER_MIN_ROOM and not Shotguns._loader_for(body.inventory, weapon).is_empty()
	var shell := Shotguns.load_choice(weapon, body.inventory, body.shell_pick if not key else &"")
	if shell == &"" and not loader:
		var refused := body.inventory.count_of(Shotguns.BREACHING) > 0 and not Shotguns.takes(weapon, Shotguns.BREACHING)
		hud.flash(Shotguns.why_not(weapon, Shotguns.BREACHING) if refused else "No shells for it")
		return
	hud.flash("Speed loader in" if loader else "Loading %s" % ItemDB.get_item(shell).name)
	body._server_load_shells.rpc_id(1, body.active_slot, shell, key)


## The grenade type after `current` in the Shift+G cycle: THROWABLES order, skipping smoke
## colours `inventory` doesn't carry.
static func next_throwable(current: StringName, inventory: Inventory) -> StringName:
	var start := maxi(THROWABLES.find(current), 0)
	for step in range(1, THROWABLES.size() + 1):
		var id := THROWABLES[(start + step) % THROWABLES.size()]
		if id in ALWAYS_CYCLED or inventory.count_of(id) > 0:
			return id
	return current


## G: takes the selected grenade in hand (the weapon lowers); nothing is thrown.
func equip_nade() -> void:
	if nade_up or Soldier._now() < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up() or body.carry_mode != &"" \
			or body.is_reloading or is_instance_valid(body.vehicle):
		return
	if body.inventory.count_of(throwable) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(throwable).name)
		return
	nade_up = true
	body.is_aiming = false
	_show_nade()
	_update_view_model()


## Puts the grenade away (nothing thrown) and brings the weapon back.
func put_nade_away(note := "") -> void:
	if not nade_up:
		return
	nade_up = false
	if is_instance_valid(_nade_label):
		_nade_label.visible = false
	_update_view_model()
	if note != "" and hud:
		hud.flash(note)


func _show_nade() -> void:
	var text := "%s (%d) - Fire throws, Aim lobs, Shift+G type, G puts away" % [ItemDB.get_item(throwable).name, body.inventory.count_of(throwable)]
	if not is_instance_valid(_nade_label):
		_nade_label = UiKit.hud_label()
		_nade_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_nade_label.offset_top = -150.0
		_nade_label.offset_bottom = -120.0
		_nade_label.offset_left = -300.0
		_nade_label.offset_right = 300.0
		_nade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_nade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_nade_label)
	_nade_label.text = text
	_nade_label.visible = true


## Each frame: the grenade goes back in the pouch when you can't hold it any more.
func _check_nade() -> void:
	if nade_up and (not body.vitals.is_up() or body.carry_mode != &"" or body.inventory.hands != &"" or is_instance_valid(body.vehicle) or body.inventory.count_of(throwable) <= 0):
		put_nade_away()


## Throws the held grenade (Fire: power 1, overhand; Aim: LOB_POWER, underhand). Host-checked.
func _try_throw(power := 1.0) -> void:
	if not nade_up or Soldier._now() < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	if body.inventory.count_of(throwable) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(throwable).name)
		put_nade_away()
		return
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	body._server_throw.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z, throwable, power)
	# The next one stays up (the count shows), or the weapon comes back when that was the last.
	_after_throw.call_deferred()


func _after_throw() -> void:
	if nade_up:
		_check_nade()  # the last one: the weapon comes back
		if nade_up:
			_show_nade()


## First-person weapon: the same voxel model others see, parented to the camera, with the
## player's own forearms and hands on it (the body itself is hidden from its own camera): the
## firing hand on the grip, the other on the support point, mirrored for a left-handed shooter.
func _update_view_model() -> void:
	var weapon := body.active_weapon()
	var id: StringName = weapon.id if weapon and body.inventory.hands == &"" and not nade_up else &""
	var art := VoxelArt.model_for(weapon, body.inventory.state_of(body.active_slot)) if id != &"" else ""  # its optic (P0362)
	var frame := ExoFrame.worn(body.inventory)  # its forearm armour shows in first person too
	var key := StringName("%s|%s|%s|%s|%s|%s|%s" % [id, art, body.left_handed, body.model.variant, body.model.body, throwable if nade_up else &"", frame.id if frame else &""])
	if key == _view_model_id:
		return
	_view_model_id = key
	for child in body.view_model.get_children():
		child.queue_free()
	_mag_old = null
	_mag_new = null
	_bolt_part = null
	_cover_part = null
	_reload_points = {}
	_view_arms.clear()
	_view_poses = [&"", &""]
	if nade_up:
		_build_nade_view()
		return
	if id == &"":
		return
	if Launchers.is_launcher(weapon):
		body.view_model.add_child(LauncherSight.view_node(weapon))  # placeholder launcher (wave 5)
		return
	var model := art
	var moving := VoxelArt.moving_parts(model)
	if VoxelArt.has_magazine(model) or not moving.is_empty():
		# The weapon in its parts (weapon detail pass, 2026-10-20): what stays put, and what a reload
		# moves on its own: the magazine, the action (charging handle, carrier, bolt, slide), the
		# feed cover. Each part keeps the weapon's pivot, so at rest they sit as one.
		body.view_model.add_child(VoxelArt.instance(VoxelArt.FIXED + model, body.model.variant, VIEW_MODEL_LAYER))
		if moving.has(VoxelArt.BOLT_TAG):
			_bolt_part = VoxelArt.instance(VoxelArt.BOLT + model, body.model.variant, VIEW_MODEL_LAYER)
			_bolt_part.name = "ViewBolt"
			body.view_model.add_child(_bolt_part)
		if moving.has(VoxelArt.COVER_TAG):
			_cover_part = VoxelArt.instance(VoxelArt.COVER + model, body.model.variant, VIEW_MODEL_LAYER)
			_cover_part.name = "ViewFeedCover"
			body.view_model.add_child(_cover_part)
		_part_motion = VoxelArt.part_motion(model)
	if VoxelArt.has_magazine(model):
		_mag_old = VoxelArt.instance(VoxelArt.MAG + model, body.model.variant, VIEW_MODEL_LAYER)
		_mag_old.name = "ViewMagazine"
		_mag_new = VoxelArt.instance(VoxelArt.MAG + model, body.model.variant, VIEW_MODEL_LAYER)
		_mag_new.name = "ViewMagazineNew"
		_mag_new.visible = false
		body.view_model.add_child(_mag_old)
		body.view_model.add_child(_mag_new)
	elif moving.is_empty():
		body.view_model.add_child(VoxelArt.instance(model, body.model.variant, VIEW_MODEL_LAYER))
	_reload_points = VoxelArt.reload_points(model)
	var points := VoxelArt.hand_points(model)
	if points.is_empty():
		return
	var side := -1.0 if body.left_handed else 1.0  # the firing hand's side
	_view_pistol = model.begins_with("pistol")
	for hand: Array in [[points.grip, VIEW_FIRING_ELBOW], [points.support, VIEW_SUPPORT_ELBOW]]:
		var palm: Vector3 = hand[0]
		var elbow: Vector3 = palm + (hand[1] as Vector3) * Vector3(side, 1, 1)
		var firing: bool = hand[1] == VIEW_FIRING_ELBOW
		var pose := _view_pose(firing)
		var forearm := VoxelArt.instance(HandPose.model(pose, firing == body.left_handed, VoxelArt.hands_bare(body.model.variant), body.model.body), body.model.variant, VIEW_MODEL_LAYER)
		forearm.name = "ViewForearm"
		forearm.set_meta(&"hand_pose", pose)
		forearm.transform = _view_arm_transform(palm, elbow, firing, pose)
		ExoFrame.dress_view_forearm(forearm, frame, firing != body.left_handed, GearRig.armor_color_for(body.model.variant))
		body.view_model.add_child(forearm)
		_view_arms.append(forearm)
		_view_poses[_view_arms.size() - 1] = pose
		if hand[1] == VIEW_SUPPORT_ELBOW:
			_support_arm = forearm
			_support_rest = forearm.transform
			_support_palm = palm


## A view forearm's place: its elbow at `elbow` and its -y down the arm to the hand, rolled about
## its own axis so the palm faces the weapon (in from the firing hand's side, up and in under the
## handguard: as CharacterModel._palm_want), and moved so pose `pose`'s grasp centre
## (HandPose.reach_point) is on the hand point `palm`. Scaled to the arm's length.
func _view_arm_transform(palm: Vector3, elbow: Vector3, firing: bool, pose: StringName) -> Transform3D:
	var left := firing == body.left_handed  # the mirrored (left) hand's mesh
	var up := (elbow - palm).normalized()
	var across := up.cross(Vector3.BACK).normalized() if absf(up.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
	var basis := Basis(across, up, across.cross(up)).orthonormalized()
	var inward := Vector3(1.0 if left else -1.0, 0, 0)
	var want := inward if firing or _view_pistol else Vector3.UP + inward * 0.6
	basis = basis * Basis(Vector3.UP, clampf(HandPose.roll_to(basis.inverse() * want, left), -CharacterModel.ROLL_MAX, CharacterModel.ROLL_MAX))
	var scaled := basis.scaled(Vector3.ONE * palm.distance_to(elbow) / CharacterModel.FOREARM)
	var reach := scaled * HandPose.reach_point(pose, left, body.model.body == VoxelArt.FEMALE)
	return Transform3D(scaled, palm - reach)


## The pose a view hand is in now: the firing hand's grip (TRIGGER aimed or just after a shot, PRESS
## as one goes, else the index along the frame), the support hand's (a reload's by its anchor:
## HandPose.RELOAD_POSES; cupping the firing hand on a pistol).
func _view_pose(firing: bool) -> StringName:
	if firing:
		if _view_press_t > 0.0:
			return HandPose.PRESS
		return HandPose.TRIGGER if body.is_aiming or _view_shot_t < CharacterModel.TRIGGER_HOLD_S else HandPose.GRIP
	if body.is_reloading:
		var ks: Array = _reload_keys if not _reload_keys.is_empty() else Reloads.keys(Reloads.AR, false)
		var at := Reloads.sample(ks, clampf((Soldier._now() - _reload_from) / _reload_len, 0.0, 1.0))
		return HandPose.RELOAD_POSES.get(at.anchor_a if float(at.w) < 0.5 else at.anchor_b, HandPose.MAG)
	return HandPose.HOLD if _view_pistol else HandPose.SUPPORT


## Each frame: the view hands' poses, their meshes swapped when one changes (the support forearm's
## rest moved so the new pose's grasp centre stays on the hand point).
func _update_view_hands(delta: float) -> void:
	_view_press_t -= delta
	_view_shot_t += delta
	for i in _view_arms.size():
		var arm := _view_arms[i]
		if not is_instance_valid(arm):
			continue
		var firing := i == 0
		var pose := _view_pose(firing)
		if pose == _view_poses[i]:
			continue
		_view_poses[i] = pose
		var left := firing == body.left_handed
		var mi := arm.get_child(0) as MeshInstance3D
		var model := HandPose.model(pose, left, VoxelArt.hands_bare(body.model.variant), body.model.body)
		mi.mesh = VoxelArt.mesh(model, body.model.variant)
		var was: StringName = arm.get_meta(&"hand_pose")
		var shift := arm.transform.basis * (HandPose.reach_point(was, left, body.model.body == VoxelArt.FEMALE) - HandPose.reach_point(pose, left, body.model.body == VoxelArt.FEMALE))
		arm.set_meta(&"hand_pose", pose)
		if arm == _support_arm:
			_support_rest.origin += shift
		else:
			arm.position += shift


## Tests: the first-person hands' poses now, [firing, support] (HandPose.POSES; empty with none).
func view_hand_poses() -> Array[StringName]:
	var out: Array[StringName] = []
	for i in _view_arms.size():
		out.append(_view_poses[i])
	return out


## Reloading in first person (Reloads): the reload's keys at its share so far move the support
## hand between anchors on the weapon, set the weapon's offset and turn (_reload_pos, _rot) and
## carry, drop or hide the magazines.
func _update_reload_hand() -> void:
	if not is_instance_valid(_support_arm):
		return
	var hand := Vector3.ZERO
	var old_state := &"in"
	var new_state := &"out"
	var tip := 0.0
	var dropped := 0.0
	if body.is_reloading:
		var u := clampf((Soldier._now() - _reload_from) / _reload_len, 0.0, 1.0)
		var ks: Array = _reload_keys if not _reload_keys.is_empty() else Reloads.keys(Reloads.AR, false)
		var at := Reloads.sample(ks, u)
		hand = (_reload_anchor(at.anchor_a) + (at.hand_a as Vector3)).lerp(_reload_anchor(at.anchor_b) + (at.hand_b as Vector3), at.w)
		_reload_pos = at.pos
		_reload_rot = at.rot
		old_state = at.old
		new_state = at.new
		tip = at.tip
		dropped = maxf(u - float(at.since), 0.0) * _reload_len
		_pose_parts(u)
	else:
		_pose_parts(-1.0)
	_support_arm.transform = Transform3D(_support_rest.basis, _support_rest.origin + hand)
	# The magazines: in the weapon, carried (where the hand holds it), falling free, or gone.
	var held := hand - _reload_anchor(&"mag")
	if is_instance_valid(_mag_old):
		_mag_old.visible = old_state != &"out"
		match old_state:
			&"hand":
				_mag_old.transform = Transform3D(Basis(Vector3.RIGHT, tip), held)
			&"drop":
				_mag_old.transform = Transform3D(Basis(Vector3.RIGHT, -MAG_TUMBLE * dropped), Vector3(0.0, -0.5 * MAG_FALL * dropped * dropped, 0.03 * dropped))
			_:
				_mag_old.transform = Transform3D.IDENTITY
	if is_instance_valid(_mag_new):
		_mag_new.visible = new_state != &"out"
		_mag_new.transform = Transform3D(Basis(Vector3.RIGHT, tip), held) if new_state == &"hand" else Transform3D.IDENTITY
		if new_state == &"in" and is_instance_valid(_mag_old):
			_mag_old.visible = false  # the fresh one's in its place


## The weapon's moving parts at share `u` of the reload under way (Reloads.parts; below 0, none:
## all home): the action slid back along the bore (and a bolt-action's handle turned up round
## it), the feed cover turned up on its front hinge.
func _pose_parts(u: float) -> void:
	if not is_instance_valid(_bolt_part) and not is_instance_valid(_cover_part):
		return
	var parts := Reloads.part_transforms(_reload_parts, _part_motion, u)
	if is_instance_valid(_bolt_part):
		_bolt_part.transform = parts.bolt
	if is_instance_valid(_cover_part):
		_cover_part.transform = parts.cover


## Tests: the action's travel back (m) and the feed cover's angle (rad) in first person now.
func view_parts() -> Dictionary:
	return {"bolt": _bolt_part.position.z if is_instance_valid(_bolt_part) else -1.0,
		"cover": -_cover_part.transform.basis.get_euler().x if is_instance_valid(_cover_part) else -1.0}


## Where reload anchor `anchor` (Reloads) puts the support forearm, from its rest: a point on the
## weapon (VoxelArt.reload_points) less where the palm rests, the pouch, or rest itself.
func _reload_anchor(anchor: StringName) -> Vector3:
	match anchor:
		&"rest":
			return Vector3.ZERO
		&"pouch":
			return RELOAD_POUCH * Vector3(-1.0 if body.left_handed else 1.0, 1, 1)
	var point: Variant = _reload_points.get(String(anchor), _reload_points.get("mag", null))
	return (point as Vector3) - _support_palm if point != null else RELOAD_POUCH * 0.3


## Tests: the first-person carry weights now {"low", "reload", "sprint", "kick"} and the support hand's offset from rest.
func view_carry() -> Dictionary:
	return {"low": _low_w, "reload": _reload_w, "sprint": _sprint_w, "kick": _view_kick, "ads_low": _ads_low,
		"hand": _support_arm.transform.origin - _support_rest.origin if is_instance_valid(_support_arm) else Vector3.ZERO}


## The held grenade in first person: the throwables' own voxel art and a forearm and hand
## holding it, low in the firing hand's corner of the view.
func _build_nade_view() -> void:
	var side := -1.0 if body.left_handed else 1.0
	var item := ItemDB.get_item(throwable)
	var palm := Vector3(0.0, -0.02, -0.1)
	var nade := ItemArt.ground_node(item)
	nade.name = "HeldGrenade"
	nade.position = palm + Vector3(0.0, 0.03, 0.0)
	body.view_model.add_child(nade)
	var elbow := palm + Vector3(0.09 * side, -0.12, 0.2)
	var forearm := VoxelArt.instance(HandPose.model(HandPose.HOLD, body.left_handed, VoxelArt.hands_bare(body.model.variant), body.model.body), body.model.variant)
	forearm.name = "ViewForearm"
	_view_pistol = true  # (the palm in round the grenade, as on a grip)
	forearm.transform = _view_arm_transform(palm + Vector3(0.0, 0.03, 0.0), elbow, true, HandPose.HOLD)
	ExoFrame.dress_view_forearm(forearm, ExoFrame.worn(body.inventory), not body.left_handed, GearRig.armor_color_for(body.model.variant))
	body.view_model.add_child(forearm)


# --- Placing a charge (Charges: like Arma Reforger's explosives) --------------------------

func _start_placing() -> void:
	if Soldier._now() < body._busy_until or body.inventory.hands != &"" or body.carry_mode != &"":
		return
	var item := throwable if Demolitions.is_placeable(throwable) else Charges.ITEM
	if body.inventory.count_of(item) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(item).name)
		return
	placing = true
	_placing_item = item
	_ghost = Charges.make_visual(true) if item == Charges.ITEM else Demolitions.make_visual(item, true)
	_ghost.name = "ChargeGhost"
	body.get_parent().add_child(_ghost)
	_update_ghost()
	if item == Charges.ITEM:
		hud.flash("Place the charge: Fire to set it, G to put it away")
		return
	var modes := Demolitions.arm_modes(item)
	_arm_index = clampi(_arm_index, 0, modes.size() - 1)
	hud.flash("Place the %s: Fire to set it%s, G to put it away" % [ItemDB.get_item(item).name,
		", R to arm (%s)" % Demolitions.arm_label(modes[_arm_index]) if modes.size() > 1 else (" (%s)" % Demolitions.arm_label(modes[0]) if modes[0] != "" else "")])


## R while placing: the next way to arm it (Demolitions.arm_modes).
func _cycle_arm() -> void:
	if _placing_item == Charges.ITEM:
		return
	var modes := Demolitions.arm_modes(_placing_item)
	_arm_index = (_arm_index + 1) % modes.size()
	hud.flash("Armed: %s" % Demolitions.arm_label(modes[_arm_index]))


## G with a clacker or radio remote picked: fires what you armed on a detonator (Demolitions).
func _fire_detonator() -> void:
	if not body.vitals.is_up() or body.inventory.count_of(throwable) <= 0:
		hud.flash("No %s" % ItemDB.get_item(throwable).name)
		return
	var demolitions := Demolitions.of(body)
	if demolitions:
		demolitions.request_fire.rpc_id(1, String(throwable))


func _stop_placing(note := "") -> void:
	placing = false
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if note != "":
		hud.flash(note)


## The ghost sits where the charge would go, lined up with the surface: green where it can
## go, red (in front of you) where it can't.
func _update_ghost() -> void:
	if not body.vitals.is_up() or body.inventory.count_of(_placing_item) <= 0 or body.inventory.hands != &"" or body.carry_mode != &"":
		_stop_placing()
		return
	var dir := -body.camera.global_basis.z
	if _placing_item != Charges.ITEM:
		var where := Demolitions.placement(body, body.camera.global_position, dir, _placing_item)
		_ghost.global_transform = Demolitions.place_transform(_placing_item, where, dir)
		Demolitions.tint_ghost(_ghost, where.ok)
		return
	var spot := Charges.placement(body, body.camera.global_position, dir)
	_ghost.global_transform = Charges.surface_transform(spot.pos, spot.normal, dir)
	var block := _ghost.get_node(^"Block") as MeshInstance3D
	var material := (block.mesh as BoxMesh).material as StandardMaterial3D
	material.albedo_color = Color(0.4, 1.0, 0.4, 0.45) if spot.ok else Color(1.0, 0.3, 0.3, 0.35)


func _commit_charge() -> void:
	var dir := -body.camera.global_basis.z
	if _placing_item != Charges.ITEM:
		var where := Demolitions.placement(body, body.camera.global_position, dir, _placing_item)
		if not where.ok:
			hud.flash(String(where.why) if String(where.why) != "" else "Nothing to place it on here")
			return
		var demolitions := Demolitions.of(body)
		var modes := Demolitions.arm_modes(_placing_item)
		if demolitions:
			demolitions.request_place.rpc_id(1, String(_placing_item), body.camera.global_position, dir, modes[clampi(_arm_index, 0, modes.size() - 1)])
		body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
		_stop_placing()
		return
	if not Charges.placement(body, body.camera.global_position, dir).ok:
		hud.flash("Nothing to place it on here")
		return
	var charges := Charges.of(body)
	if charges:
		charges.request_place.rpc_id(1, body.camera.global_position, dir)
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	_stop_placing()
