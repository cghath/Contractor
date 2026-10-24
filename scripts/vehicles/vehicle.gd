class_name Vehicle
extends RigidBody3D
## A vehicle (wave 5): ground vehicles players or AI drive, and the helicopters V3 flies.
##
## Built from its model's numbers in data/vehicles.json (VehicleSpecs) and Captain's look
## (VehicleArt, through VehicleHull). One RigidBody3D on Jolt with simple boxes for collision
## and its own raycast suspension, not VehicleBody3D: one model of wheels serves wheeled
## vehicles (steered front wheels, tyre grip) and tracked ones (skid steering, a turn-rate
## controller on the hull) alike, its numbers stay ours to tune, and it behaves the same with
## 4 wheels or 14 road wheels. (VehicleBody3D has no skid steering, and its wheels slip and
## jitter on a 25 t hull.)
##
## Host authoritative like everything shared: the host simulates the body, decides hits, seats,
## cargo, fuel and fire; the driver (a player anywhere, or the AI on the host) only sends
## throttle, steer and brake (request_drive). Every peer sees:
## - net_pose: the host's transform 30 times a second; clients hold a frozen (kinematic) copy
##   that follows it INTERP_DELAY_S behind, interpolated, so it moves smoothly;
## - net_state: seats (who sits where), zone health, fuel, fire, wreck;
## - net_carves: the voxel damage (VehicleHull);
## - the cargo (VehicleCargo.net_state).
## All of them go with the spawn too, so a late joiner gets the vehicle as it is.
##
## Seats: whoever sits rides with the vehicle on every peer (_place_occupants): at the seat,
## crouched for a seat, standing for a gunner's hatch or a pickup bed, hidden inside an enclosed
## vehicle, with their hitboxes (so a round that gets through the hull finds them). A player's
## first-person view is their own head at the seat. Getting in, out, switching seats and loading bodies go
## through the Left Ctrl menu (VehicleActionPoint); AI squadmates are ordered in and out from the
## command menu (VehicleLayer.server_order_mount). A seated player sees out through the chase
## camera (VehicleCamera: third person, B switches to first person at the seat's eye).
##
## Damage: server_take_hit (Ballistics' rounds; V2's launchers) finds the 5 cm voxel the hit
## really meets, its hit zone and armour (VehicleDamage), wears the zone and the hull, carves the
## hull (VehicleHull) and may start a fire. Engine damage slows then stops it, wheel or track
## damage cripples it, a fuel hit leaks and may catch; with the hull at 0 it's destroyed. A
## burning vehicle burns FIRE_S, hurting everyone still aboard (the wound model's burns), then
## kills them, destroys its cargo and is a wreck: blackened, immobile, lootable for parts, saved
## with the zone (GameState.vehicles).
##
## The mounted gun: a turret or pintle that turns (VehicleTurret: the M-ATV's and MaxxPro's
## O-GPK, the AAV-7's weapon station, a technical's DShK). The host owns where it points: the
## gunner's peer sends where it wants it (request_aim; the local gunner's own peer turns it
## ahead of the host, so their view never waits on the network), an AI gunner aims through
## server_aim, and it turns there at the mount's speeds, within its limits. Its pose rides in
## net_pose (every peer draws it interpolated, like the hull). The gunner's seat turns with the
## ring; in first person the gunner's view is the gun's (the mouse turns the turret, the view
## follows it), in the chase view the turret turns to the camera's crosshair. Rounds leave the
## gun's muzzle along its barrel.
##
## Armour's guns (combined arms A3): a model with "weapons" (the Abrams, the Bradley) has a
## VehicleWeapons child ("Weapons") with its mounts: the main gun and its loader, the dual feed,
## the TOW, the commander's and loader's guns. The vehicle's own "gun" stays its coax (fired here,
## by its own sights), the turret's seats turn with it (turns_with_turret), the commander and
## loader are crew seats (COMMANDER, LOADER), and seat moves take time (switch_time).
##
## Gunnery (combined arms A4): a model with "optics" has a VehicleGunnery child ("Gunnery": the
## sights, the laser, fire control, the stabiliser, the commander's viewer and hand-off), one with
## "hatches" a VehicleHatches ("Hatches": turned out or buttoned up). Their hooks here: a hatch
## seat's spot, stance and openness (_seat_at, seat_eye_point, seat_open, _place_occupants), the
## gunner's view along the sight's line (_gunner_look), aims waiting while a hand-off slews
## (server_aim, request_aim), the keys, the readout, the save.
##
## Helicopters are this class with kind "helicopter": seats, cargo, damage and saving work; the
## ground drive does nothing for them. V3 flies them by overriding _drive_step (or a subclass).
## Numbers marked Proposed are tunable.

## Layer 7 ("vehicles"): hulls. Rounds (Ballistics.MASK), fragments, charges and the living
## (SoldierMovement.UP_MASK) meet it. A vehicle meets the world, other vehicles and ragdolls
## (layer 6: it unfreezes a settled body before it reaches it, so the body is pushed, not driven
## into like a wall). Not the living (layer 5): a soldier's capsule is kinematic, so a 12 t
## truck would stop dead against it; a shape query ahead of the hull finds soldiers in the way
## instead: pushed aside at any speed (_push_aside), run over at speed (_run_over).
const LAYER := 1 << 6
const MASK := 1 | Ragdoll.LAYER | LAYER  # world, ragdolls, vehicles
const GROUP := &"vehicles"

## Hit kinds a `server_take_hit` dictionary names in "kind". Small arms come from Ballistics
## ("kinetic", with the round's id and energy); V2's launchers send the rest.
const KINETIC := &"kinetic"            # bullets: armour class decides bounce or penetrate
const HEAT := &"heat"                  # shaped charge: penetrates by "penetration_mm"
const TANDEM_HEAT := &"tandem_heat"    # defeats reactive armour first
const HE := &"he"                      # blast and fragments: light vehicles, crews outside
const HEDP := &"hedp"                  # both, weaker at each
const THERMOBARIC := &"thermobaric"    # overpressure: crews and structures, little armour
const TOP_ATTACK := &"top_attack"      # Javelin, NLAW overfly: hits the roof's armour

## Hit zones (names, so other code can ask about them; zone_health()).
const ZONE_HULL := &"hull"
const ZONE_ENGINE := &"engine"
const ZONE_WHEELS := &"wheels"   # or tracks
const ZONE_CREW := &"crew"
const ZONE_CARGO := &"cargo"
const ZONE_ROTOR := &"rotor"     # helicopters
const ZONE_FUEL := &"fuel"
const ZONES: Array[StringName] = [ZONE_HULL, ZONE_ENGINE, ZONE_WHEELS, ZONE_CREW, ZONE_CARGO, ZONE_FUEL, ZONE_ROTOR]

## Seat kinds.
const DRIVER := &"driver"
const GUNNER := &"gunner"
const PASSENGER := &"passenger"
const PILOT := &"pilot"  # helicopters: AI only (Captain: aircraft are AI-flown)
## Combined arms A3 (docs/combined_arms.md 2.5.1): a tank's or IFV's commander and loader, crew
## seats in the turret (VehicleWeapons gives them their jobs). Boarding and loading casualties
## treat them as riders' seats did (rider_like).
const COMMANDER := &"commander"
const LOADER := &"loader"
## Vehicle kinds (data/vehicles.json "kind").
const WHEELED := "wheeled"
const TRACKED := "tracked"
const HELICOPTER := "helicopter"
## A crew-served weapon on the ground (G-25, docs/static_weapons.md): no wheels or engine, frozen
## where it was set up, one gunner seat; it packs into loads to move.
const STATIC := "static"

## Suspension (Proposed): static sag under the vehicle's weight, travel above the wheel's rest
## height, droop below it, and the damping ratio.
const SAG_WHEELED := 0.12
const SAG_TRACKED := 0.07
const TRAVEL := 0.22
const DROOP := 0.18
const DAMPING_RATIO := 0.5
## Tyre and track grip (Proposed): friction coefficient on asphalt (A6: times the ground's traction,
## VehicleDrive), and how much of a wheel's sideways slip is taken out each physics step; tracks
## slip sideways while turning on the spot.
const GRIP := 0.95
const LATERAL_RESPONSE := 0.45
const TRACK_TURN_LATERAL := 0.15
## Steering falls off with speed (wheeled): full lock below this speed (m/s), half at twice it.
const STEER_FALLOFF_MS := 8.0
## Rolling resistance (m/s2; A6: the ground's, VehicleDrive, on every ground vehicle) and engine
## braking with the throttle off.
const ROLL_DECEL := 0.3
const ENGINE_BRAKE := 0.5
## Tracked turn controller: reaches the commanded turn rate in about this long (s).
const TRACK_TURN_TIME_S := 0.35
## Rolling the other way while still moving faster than this (m/s) brakes first.
const REVERSE_BRAKE_MS := 0.6
## Sleep: a parked vehicle (no input, slower than this for SLEEP_S) stops simulating its wheels.
const SLEEP_SPEED := 0.04
const SLEEP_S := 1.0
## Ground the wheels stand on: the world and other vehicles.
const GROUND_MASK := 1 | LAYER
## Collision boxes starting below SLED_BELOW_M (the chassis) get their bottom front and back
## edges bevelled this much (hull_shape).
const SLED_BELOW_M := 0.7
const SLED_BEVEL_M := 0.3

## Driving input older than this (s) counts as released (a driver who dropped out).
const INPUT_TIMEOUT_S := 0.5
## Replication (Proposed): poses per second, and how far behind the host clients draw.
const POSE_HZ := 30.0
const INTERP_DELAY_S := 0.1
const EXTRAPOLATE_MAX_S := 0.25
## net_state goes out at most this often while only fuel or fire time changes.
const STATE_MIN_S := 0.25

## Fuel (Proposed: data per model): litres per km and per hour idling; a fuel-zone hit leaks
## LEAK_LPS per unit of damage.
const LEAK_LPS := 0.6
## Fire (Proposed): how long a vehicle burns before it is a wreck; every FIRE_TICK_S everyone
## still aboard gets FIRE_BURN_SHARE more of their body burned and FIRE_TRAUMA (Vitals
## server_damage) of heat and smoke; whoever is still aboard at the end dies.
const FIRE_S := 45.0
const FIRE_TICK_S := 1.0
const FIRE_BURN_SHARE := 0.06
const FIRE_TRAUMA := 4.0
## A burning hull blackens a spot of FIRE_SCORCH_M every FIRE_SCORCH_EVERY ticks (combined arms
## A7, Proposed: VehicleFx draws the fire now, and a 0.5 m scorch every second cost a burning
## vehicle's host ~60-150 ms a second in VehicleHull's carving, F-241).
const FIRE_SCORCH_EVERY := 4
const FIRE_SCORCH_M := 0.35
## Chance a penetrating engine hit kills the battery (Proposed).
const BATTERY_KILL_CHANCE := 0.1
## Run-overs (Proposed): faster than RUN_OVER_MIN_MS a soldier in the vehicle's path takes
## blunt trauma: RUN_OVER_TRAUMA per m/s over the minimum (Vitals.server_damage), and the
## fall model's injuries for a drop of v^2 / 2g times RUN_OVER_FALL_MULT. Once per
## RUN_OVER_COOLDOWN_S each.
const RUN_OVER_MIN_MS := 2.5
const RUN_OVER_TRAUMA := 6.0
const RUN_OVER_FALL_MULT := 1.5
const RUN_OVER_COOLDOWN_S := 1.5
## Soldiers standing in the way (Proposed): at any speed a soldier the hull is about to drive
## into or is overlapping is pushed out sideways, at PUSH_MIN_MS or the vehicle's speed times
## PUSH_SPEED_MULT, whichever is more, to PUSH_CLEAR_M beyond the hull's side. A player's own
## peer moves them (Soldier positions are their owners'); the host sends the push at most every
## PUSH_SEND_S.
const PUSH_MIN_MS := 1.5
const PUSH_SPEED_MULT := 1.5
const PUSH_CLEAR_M := 0.45
const PUSH_SEND_S := 0.1
## How far ahead of the hull (s of travel, plus a margin) a settled ragdoll is woken.
const RAGDOLL_LOOKAHEAD_S := 0.2
const RAGDOLL_MARGIN_M := 0.4
## A body wedged under the chassis that stops a driven vehicle for RIDE_OVER_AFTER_S is
## driven over: its parts stop meeting this hull for at least RIDE_OVER_S, until they're clear
## of it (as wheels would roll over it).
const RIDE_OVER_AFTER_S := 0.4
const RIDE_OVER_S := 3.0
## Hood ornaments (Captain, 2026-10-16: "running over soldiers shouldnt stop vehicles", "i want to
## be able to acquire some hood ornaments instead of feeling like im nailing a tree every time"):
## a soldier knocked down by a moving vehicle is flung with it (FLING_FORWARD x its speed, FLING_UP
## x that upward), and at RUN_OVER_MIN_MS or more any part of a body lying below BUMPER_M (vehicle
## space, the origin on the ground) is driven over at once instead of holding the vehicle up; what
## lands higher, on the hood or roof, rides there until it slides off.
const FLING_FORWARD := 1.05
const FLING_UP := 0.35
const BUMPER_M := 0.7
## Rounds: how far past a collision box's face the hull's voxels are looked for.
const PROBE_M := 0.4
## Most damage operations one vehicle keeps (net_carves).
const MAX_CARVES := 500
## Exits: how far out from the hull a soldier is put, and the space they need.
const EXIT_GAP_M := 0.7
const EXIT_GRACE_S := 0.6
## Boarding (CharacterModel.BOARD; Captain, 2026-10-17: "that get anim is poor, it just floats
## up"): someone getting into a walk-in bay's seat (a "bay" with "steps", the UH-60's cabin) from
## within BOARD_FROM_M of its step steps up onto the sill with a hand on the grab handle by the
## doorway, walks in to the seat at BOARD_WALK_MS and sits. Further off (put in by a mission, or
## swapping seats) he's just seated. The host starts it (server_enter); every peer draws it from
## the clip's clock (_board_pose).
const BOARD_FROM_M := 5.0
const BOARD_WALK_MS := 1.3
## Where he stands at the foot of the step (m out from the sill, on the ground), where he stands
## once up (m in from it), and how far in front of the seat he turns to sit down.
const BOARD_OUT_M := 0.5
const BOARD_IN_M := 0.35
const BOARD_STAND_OFF_M := 0.3
## The grab handle by the doorway, from the sill: in, up, and towards the front (m).
const BOARD_HANDLE := Vector3(0.1, 1.2, 0.45)
## An "edge" seat (Captain, 2026-10-17: the UH-60's door riders sit on the cabin floor facing
## out, legs hanging off the edge): the hips this far up off the floor, the feet this far below it.
const EDGE_HIP_UP := 0.07
const EDGE_HANG_M := 0.84  # Captain, 2026-10-17: legs hanging down towards the ground, not out
const EDGE_FOOT_M := 0.22  # the feet this far out past the hips (knees just bent)
## A worn pack sits a rider off a seat's canvas back by its depth, but no further than this.
const SEAT_PACK_MAX_M := 0.2
var _door_guns := {}  # seat index -> DoorGun (seats with "door_gun")
var _crew: Array[Node3D] = []  # a helicopter's pilots, drawn (_build_crew)
## Host: the fast-ropes are out (Helicopter insertions, HeliCall); every peer draws them (net_state "ropes").
var ropes_out := false
var _ropes: Array[MeshInstance3D] = []
var _running_out := {}  # host: instance id -> [soldier, when he's out, the step's foot (vehicle frame)]
## Captain, 2026-10-17: in an FFV seat with the doors shut a rider crouches behind the door,
## facing out, and sits as it opens (VehicleBay.open_fraction): hips this high off the cabin
## floor, this far back from the seat (an edge seat's: inboard of the sill), eye this high.
const FFV_CROUCH_HIP := 0.5
## Kneeling (Captain, 2026-10-17: "lefties ... left knee up, left foot on the ground, right knee in
## the dirt; righties kneel right knee up, left knee in the dirt"): the hips this high off the
## floor, the up foot this far ahead of them (its shin upright), the down foot this far behind
## (the knee on the floor, the shin flat).
const KNEEL_HIP := 0.5
const KNEEL_UP_FOOT := 0.42
const KNEEL_DOWN_FOOT := 0.45
## Running out (Captain, 2026-10-17: AI "should run out instead of spawning out of the helis"):
## up off the seat, a run to the door at RUN_OUT_MS, down off the sill, out at the step's foot.
## Fast-roping (Captain, 2026-10-17: modern hot drops): from the seat to the door in
## ROPE_TO_DOOR_S, then down the rope at ROPE_SLIDE_MS to the ground under the door.
const ROPE_TO_DOOR_S := 0.6
const ROPE_SLIDE_MS := 5.0
## The ropes hang from this far out from the door's sill, from this high over the floor.
const ROPE_OUT_M := 0.45
const ROPE_TOP_M := 1.7
const RUN_OUT_MS := 3.0
const RUN_OUT_SIT_S := 0.4
const RUN_OUT_STEP_S := 0.45
const FFV_CROUCH_BACK := 0.8  # an edge seat's: the hips this far in off the sill, the rifle inside the door
const FFV_CROUCH_BACK_SEATED := 0.45  # a door seat's (the VTOLs'): this far in from it, turned to the door
const FFV_CROUCH_EYE := 1.0
## Mounted guns: shots may arrive bunched up this much (network jitter) and still count.
const GUN_BUNCH_S := 0.15
## A door gun's arc (door_arc_ok): how far outwards a shot must point (its dot with the side:
## 0.15, within about 80 degrees of square out) and how far up at most (sine: 30 degrees).
const DOOR_ARC_OUT := 0.15
const DOOR_ARC_UP := 0.5
## Interaction: how near a door or other point someone must be to use it (m).
const USE_REACH_M := 4.0
## A wreck yields this when salvaged (Proposed).
const SALVAGE_S := 20.0
## A service job stops when its worker or the vehicle moves this far from where it began (m).
const JOB_MOVE_M := 1.5

## Read the local occupant's keys and mouse (tests that drive by request turn it off).
static var local_input := true
## Hits roll for fires (VehicleDamage.FIRE_CHANCE); tests that need a vehicle to stay whole turn it off.
static var fire_rolls := true
## Where spall fragments land (_spall), picked by spall_rng (random; a test seeds it for a
## repeatable pass: the first, deep fragment through the face can reach the brain and kill).
const SPALL_PARTS: Array[StringName] = [Vitals.CHEST, Vitals.ABDOMEN, Vitals.THIGH_L, Vitals.THIGH_R, Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FACE, Vitals.NECK]
static var spall_rng := _random_rng()

signal seats_changed
signal damaged(zone: StringName, hit: Dictionary)
## Host: hits on it do this much damage (HeliCall sets it from an air wing upgrade, HeliUpgrades).
var damage_mult := 1.0
## The vehicle is lost: destroyed, or on fire (a fire always ends in a wreck). Once.
signal destroyed(vehicle: Vehicle)
## The fire burned out and it is a wreck now.
signal became_wreck(vehicle: Vehicle)

## Which VehicleArt model and paint scheme (set before the vehicle enters the tree).
@export var model := "matv"
@export var scheme := ""
## Owning side (the same faction names soldiers use), for AI and supports.
@export var faction := &"player"
## Stable id within a zone: saves, wrecks and the motor pool find a vehicle by it.
var vehicle_id := ""
## True once destroyed: it stays as a wreck (saved with the zone).
var wrecked := false

## Replicated (host -> every peer): see the class notes.
var net_pose := PackedFloat32Array():
	set(value):
		net_pose = value
		if is_inside_tree() and not multiplayer.is_server():
			_push_snapshot(value)
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if is_inside_tree() and not multiplayer.is_server():
			_apply_state()
var net_carves: Array = []:
	set(value):
		net_carves = value
		if hull:
			hull.apply_ops(value)

## The model's numbers (VehicleSpecs.spec).
var spec: Dictionary = {}
var kind := WHEELED
var hull: VehicleHull
var cargo_hold: VehicleCargo
## A walk-in troop bay (VehicleBay: doors, ramp, walkable cabin, FFV seats), or null.
var bay: VehicleBay
## Host: the AI driver, made by server_drive_to / server_follow_path.
var ai: VehicleAI
## Combined arms A2: its modules and kill states (VehicleModules; replicated, saved).
var modules: VehicleModules
## Combined arms A3: the mounts its crew fights with (the main gun and its loader, the dual feed,
## the TOW, the commander's and loader's guns), on models with "weapons"; null on the rest.
var weapons: VehicleWeapons
## Combined arms A4: sights, the laser, fire control, the stabiliser, the commander's viewer, on
## models with "optics"; hatches turned out or buttoned up on models with "hatches"; null on the rest.
var gunnery: VehicleGunnery
var hatches: VehicleHatches
## Combined arms A7 (cg_brief queue item 2.5; docs/combined_arms.md 2.10): the fire's stages, the
## ammunition's vent, cook-off or detonation and the bail-out (host state, "FireState"); their looks
## and the guns' on every peer ("Fx"); the smoke dischargers on models that have them ("Smoke").
var fire_state: VehicleFire
var fx: VehicleFx
var smoke: VehicleSmoke
## Combined arms A8 (cg_brief queue item 2.6): rounds as items, rearming, field repairs by module,
## the tow, fuel pallets, armour packages and their weight, the extinguisher bottles
## (VehicleLogistics, "Logistics": its state in the StateSync and the save). Ground vehicles only.
var logistics: VehicleLogistics
## Combined arms A6: the driving physics and terrain (VehicleDrive, "Drive": the ground, power and
## traction, rollovers and righting, fording, flooding, bogging, thrown tracks). Ground vehicles.
var drive: VehicleDrive

## Host: fuel (litres), fire time left, battery, salvaged.
var fuel := 0.0
var burning_s := 0.0
var battery_ok := true
var salvaged := false
var _zones := {}             # zone -> health 0..1
var _seat_nodes: Array = []  # every peer: Soldier or null per seat
var _seat_local: Array[Transform3D] = []  # each seat's body origin in the vehicle's frame
var _seat_poses: Array[Dictionary] = []   # each seat's CharacterModel.seated_pose ({} standing)
var _lost := false
var _input := {"throttle": 0.0, "steer": 0.0, "brake": true, "at": -100.0}
var _ai_input := {"throttle": 0.0, "steer": 0.0, "brake": true}
var _still_s := 0.0
var _pose_left := 0.0
var _state_left := 0.0
var _state_dirty := false
var _leak := 0.0             # litres a second
var _fire_tick := 0.0
var _fire_ticks := 0
var _gun_next := {}          # host: gun seat -> when it may fire next
var _gun_rounds := 0  # host: rounds the guns have fired (every tracer_every-th a tracer, as Soldier's)
var _run_over_at := {}          # soldier instance id -> time last run over
var _pushed_at := {}             # host: player soldier instance id -> time last sent a push
var _blocked_s := 0.0            # host: driven but held still against a body
var _ridden := {}                # host: ragdoll part -> time its collision exception ends
var _jobs := {}              # actor instance id -> timed job
var _last_pos := Vector3.ZERO
var _seen := {}              # every peer: instance id -> Soldier seated last frame
var _snaps: Array = []       # clients: [host time, position, rotation]
var _clock := INF            # clients: local time minus host time
var _hud: Hud                # the local occupant's HUD, while it shows this vehicle's readout
var _send_left := 0.0
var _last_sent := {}
var _gun_local_next := 0.0
var _spawn_xform := Transform3D.IDENTITY
var _died_calls := {}        # host: occupant instance id -> its bound died callable
var _bodies := {}            # host: instance ids of bodies loaded into seats (down or dead): they ride on if they die
var _saved_bodies := {}      # host: seat index -> body uid from the zone save, seated again once the bodies are back
## The mounted gun's turret, or null (VehicleTurret).
var turret: VehicleTurret
var _gun_seat := -1
var _aim_send_left := 0.0
var _aim_sent := Vector2(INF, INF)
var _moving := {}  # host: soldier instance id -> {"to": seat, "at": when he's there} (A3: timed seat moves)


## A new vehicle of `model` (VehicleArt.MODELS, with numbers in data/vehicles.json), ready
## to add to the tree (VehicleLayer.server_spawn does, through its spawner).
static func create(p_model: String, p_scheme := "", p_faction := &"player", id := "") -> Vehicle:
	var v := Vehicle.new()
	v.setup(p_model, p_scheme, p_faction, id)
	return v


## Builds the body for `p_model`: collision boxes, look, cargo, action points and the
## synchronizers. Call before it enters the tree.
func setup(p_model: String, p_scheme := "", p_faction := &"player", id := "") -> void:
	model = p_model
	scheme = p_scheme if p_scheme != "" else String(VehicleArt.MODELS.get(p_model, ["od"])[0])
	faction = p_faction
	vehicle_id = id
	if id != "":
		name = id.validate_node_name()
	spec = VehicleSpecs.spec(model)
	kind = String(spec.get("kind", WHEELED))
	mass = float(spec.get("mass_kg", 5000.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = VehicleSpecs.vec(spec.get("com"), Vector3(0, 1, 0))
	angular_damp = 0.6
	linear_damp = 0.02
	continuous_cd = true
	for i in (spec.get("boxes", []) as Array).size():
		var aabb := VehicleSpecs.box(spec.boxes[i])
		var col := CollisionShape3D.new()
		col.name = "Box%d" % i
		col.shape = Vehicle.hull_shape(aabb)
		col.position = aabb.get_center()
		add_child(col)
	if spec.has("bay"):
		bay = VehicleBay.new(self)
		bay.build()
		add_child(bay)
	hull = VehicleHull.new(model, scheme)
	turret = VehicleTurret.of(spec)
	hull.turret = turret
	_gun_seat = int((spec.get("gun", {}) as Dictionary).get("seat", -1)) if turret else -1
	add_child(hull)
	cargo_hold = VehicleCargo.new(float(spec.get("cargo_l", 0.0)), float(spec.get("cargo_kg", 0.0)))
	add_child(cargo_hold)
	modules = VehicleModules.new(self)
	add_child(modules)
	if spec.has("weapons"):
		weapons = VehicleWeapons.new(self)  # A3: "Weapons", its state in the StateSync
		add_child(weapons)
	if spec.has("optics"):
		gunnery = VehicleGunnery.new(self)  # A4: "Gunnery"
		add_child(gunnery)
	if spec.has("hatches"):
		hatches = VehicleHatches.new(self)  # A4: "Hatches"
		add_child(hatches)
	fire_state = VehicleFire.new(self)  # A7: "FireState", its state in the StateSync
	add_child(fire_state)
	fx = VehicleFx.new(self)  # A7: "Fx", every peer's fire, destruction and gun effects
	add_child(fx)
	if VehicleSmoke.has_dischargers(spec):
		smoke = VehicleSmoke.new(self)  # A7: "Smoke", the M250 / M257 dischargers
		add_child(smoke)
	if VehicleLogistics.wanted(spec):
		logistics = VehicleLogistics.new(self)  # A8: "Logistics"
		add_child(logistics)
	if VehicleDrive.wanted(spec):
		drive = VehicleDrive.new(self)  # A6: "Drive"
		add_child(drive)
		# A6: air drag (VehicleDrive.aero_force) in place of the engine's default linear damping,
		# which held every ground vehicle near 50 km/h whatever its engine (0.12 x v, 1/s).
		linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		linear_damp = 0.0
	fuel = float(spec.get("fuel_l", 100.0))
	for z in ZONES:
		_zones[z] = 1.0
	_seat_nodes.resize((spec.get("seats", []) as Array).size())
	_seat_nodes.fill(null)
	for seat: Dictionary in spec.get("seats", []):
		var eye := Vehicle.seat_eye(String(seat.get("stance", "sit")))
		_seat_local.append(Transform3D(Basis(), VehicleSpecs.vec(seat.at) - Vector3(0, eye, 0)))
		_seat_poses.append(_seated_pose_for(seat, eye))
		if bool(seat.get("door_gun", false)):
			var at := VehicleSpecs.vec(seat.get("gun_at", seat.at))
			var gun := DoorGun.build(signf(at.x), Color(VehicleArt.SCHEMES.get(scheme, VehicleArt.SCHEMES["od"]).paint).darkened(0.3))
			gun.position = at
			add_child(gun)
			_door_guns[_seat_poses.size() - 1] = gun
	if kind == HELICOPTER:
		_build_crew()
	for i in (spec.get("points", []) as Array).size():
		var p: Dictionary = spec.points[i]
		add_child(VehicleActionPoint.new(self, String(p.kind), VehicleSpecs.vec(p.at), p.get("seats", []), -1, "Point%d" % i))
	for i in _seat_local.size():
		add_child(VehicleActionPoint.new(self, VehicleActionPoint.SEAT, Vector3.ZERO, [i], i, "Seat%d" % i))
	_add_sync()
	_publish_state()


func _add_sync() -> void:
	var pose := SceneReplicationConfig.new()
	pose.add_property(^".:net_pose")
	pose.property_set_replication_mode(^".:net_pose", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	pose.property_set_spawn(^".:net_pose", true)
	var pose_sync := MultiplayerSynchronizer.new()
	pose_sync.name = "PoseSync"
	pose_sync.replication_config = pose
	pose_sync.replication_interval = 1.0 / POSE_HZ
	add_child(pose_sync)
	var state := SceneReplicationConfig.new()
	var paths: Array[NodePath] = [^".:net_state", ^".:net_carves", ^"Cargo:net_state", ^"Modules:net_state"]
	if weapons:
		paths.append(^"Weapons:net_state")
	if gunnery:
		paths.append(^"Gunnery:net_state")
	if hatches:
		paths.append(^"Hatches:net_state")
	paths.append(^"FireState:net_state")  # A7
	if smoke:
		paths.append(^"Smoke:net_state")
	if logistics:
		paths.append(^"Logistics:net_state")  # A8
	if drive:
		paths.append(^"Drive:net_state")  # A6
	for path: NodePath in paths:
		state.add_property(path)
		state.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		state.property_set_spawn(path, true)
	var state_sync := MultiplayerSynchronizer.new()
	state_sync.name = "StateSync"
	state_sync.replication_config = state
	state_sync.delta_interval = 0.05
	add_child(state_sync)


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER
	collision_mask = MASK
	if spec.is_empty():
		setup(model, scheme, faction, vehicle_id)
	if multiplayer.is_server():
		contact_monitor = true
		max_contacts_reported = 6
		body_entered.connect(_on_body_entered)
		## Captain, 2026-10-15 (v0.4.3 co-op): an AI squadmate in the M-ATV's gun seat (or a
		## Black Hawk's door gun) never fired: only the support AAV and the QRF technical had an
		## AI gunner. Every armed vehicle has one; it does nothing while no AI mans a gun.
		if not gun_seats().is_empty():
			AavGunner.attach(self)
		if bay:
			FfvGunner.attach(self)  # AI in its fire-from-vehicle seats fight out of the open bay
		if wrecked or kind == STATIC:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true  # (a static weapon stays where it was set up: no drive step, no physics)
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		if not net_pose.is_empty():
			_push_snapshot(net_pose)
		_apply_state()
	hull.apply_ops(net_carves)
	hull.set_wrecked(wrecked)
	_last_pos = global_position


# --- Queries ------------------------------------------------------------------------------

## A collision box for the hull (centred on `aabb`'s centre). A low box (the chassis) has its
## bottom front and back edges bevelled like a sled's, so a body lying in the way is ridden
## over or pushed under instead of stopping the vehicle like a kerb.
static func hull_shape(aabb: AABB) -> Shape3D:
	var h := aabb.size * 0.5
	var bevel := minf(SLED_BEVEL_M, aabb.size.y * 0.6)
	if aabb.position.y > SLED_BELOW_M or bevel <= 0.01:
		var box := BoxShape3D.new()
		box.size = aabb.size
		return box
	var points := PackedVector3Array()
	for x: float in [-h.x, h.x]:
		for z: float in [-h.z, h.z]:
			points.append(Vector3(x, h.y, z))  # the top, square
			points.append(Vector3(x, -h.y + bevel, z))  # the ends, down to the bevel
			points.append(Vector3(x, -h.y, z - signf(z) * bevel))  # the bottom, short of the ends
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


## The vehicle a collider belongs to (a hull, a hit-zone shape or a child of one), or null.
static func find_on(node: Object) -> Vehicle:
	var n := node as Node
	for i in 6:
		if n == null:
			return null
		if n is Vehicle:
			return n
		n = n.get_parent()
	return null


## The vehicle `soldier` rides in (every peer), or null.
static func ride_of(soldier: Node) -> Vehicle:
	var v: Variant = soldier.get(&"vehicle") if soldier else null
	return v as Vehicle if is_instance_valid(v) else null


## Height of the eye above a seated body's origin for a seat stance ("sit": crouched, "stand").
static func seat_eye(stance: String) -> float:
	return SoldierMovement.STANCE_EYE[Vehicle.seat_stance(stance)]


static func seat_stance(stance: String) -> int:
	match stance:
		"stand":
			return SoldierMovement.Stance.STAND_LOW
		"upright":  # a standing spot in a cabin (Captain, 2026-10-17: "an actual standing pose")
			return SoldierMovement.Stance.STAND_HIGH
		"kneel":  # a spot on a cabin's open floor (the UH-60's: Captain, 2026-10-17)
			return SoldierMovement.Stance.CROUCH_LOW
	return SoldierMovement.Stance.CROUCH_MID


## The model's display name ("M-ATV").
func display_name() -> String:
	return String(spec.get("name", model))


## The display name's first word ("UH-60M" for "UH-60M Black Hawk"): the squad HUD's.
func short_name() -> String:
	return display_name().get_slice(" ", 0)


## The seats: an Array of {"name", "kind" ("driver"|"gunner"|"passenger"|"pilot"),
## "occupant": Soldier or null, "open" (seen from outside)}.
func seats() -> Array:
	var out: Array = []
	var defs: Array = spec.get("seats", [])
	for i in defs.size():
		out.append({"name": String(defs[i].name), "kind": StringName(defs[i].kind), "occupant": occupant(i), "open": seat_open(i)})
	return out


func seat_count() -> int:
	return _seat_nodes.size()


func seat_kind(index: int) -> StringName:
	var defs: Array = spec.get("seats", [])
	return StringName(defs[index].kind) if index >= 0 and index < defs.size() else &""


func seat_name(index: int) -> String:
	var defs: Array = spec.get("seats", [])
	return String(defs[index].name) if index >= 0 and index < defs.size() else ""


## Who sits in seat `index` (every peer), or null.
func occupant(index: int) -> Soldier:
	if index < 0 or index >= _seat_nodes.size():
		return null
	var s: Variant = _seat_nodes[index]
	return s as Soldier if is_instance_valid(s) and not (s as Node).is_queued_for_deletion() else null


## The soldiers aboard.
func occupants() -> Array:
	var out: Array = []
	for i in _seat_nodes.size():
		var s := occupant(i)
		if s:
			out.append(s)
	return out


## The seat `soldier` sits in, or -1.
func seat_of(soldier: Node) -> int:
	if soldier == null:
		return -1
	for i in _seat_nodes.size():
		if _seat_nodes[i] == soldier and is_instance_valid(soldier):
			return i
	return -1


func driver() -> Soldier:
	return occupant(_first_seat(DRIVER))


## The driver's seat's index (-1 for none).
func driver_seat() -> int:
	return _first_seat(DRIVER)


## Whether its engine runs (Sfx's engine sound, every peer): someone drives. Helicopter: its rotors turn.
func engine_running() -> bool:
	return driver() != null


func gunner() -> Soldier:
	var g: Dictionary = spec.get("gun", {})
	return occupant(int(g.get("seat", -1))) if not g.is_empty() and g.has("weapon") else null


func _first_seat(seat_kind_: StringName) -> int:
	var defs: Array = spec.get("seats", [])
	for i in defs.size():
		if StringName(defs[i].kind) == seat_kind_:
			return i
	return -1


## The cargo stash (an Inventory: VehicleCargo) or null when the vehicle carries none.
func cargo() -> Node:
	return cargo_hold if cargo_hold and cargo_hold.capacity_l > 0.0 else null


## Where seat `seat` (its name, or its index as text) puts its occupant's body now, in the
## world (People's hook: PeopleLayer.server_seat_in_vehicle).
func seat_transform(seat: String) -> Transform3D:
	var index := seat.to_int() if seat.is_valid_int() else -1
	if index < 0:
		var defs: Array = spec.get("seats", [])
		for i in defs.size():
			if String(defs[i].name) == seat:
				index = i
		if index < 0:
			index = _first_free_passenger()
	index = clampi(index, 0, maxi(_seat_local.size() - 1, 0))
	return global_transform * _seat_at(index) if not _seat_local.is_empty() else global_transform


## A seat's eye point in the world (the gunner's turns with the turret, and a turret seat's).
func seat_eye_point(index: int) -> Vector3:
	var out: Variant = hatches.eye_local(index) if hatches else null  # A4: turned out
	var at: Vector3 = out if out is Vector3 else VehicleSpecs.vec(spec.seats[index].at)
	return global_transform * (turret.carry(at) if turns_with_turret(index) else at)


## Whether seat `index` goes round with the turret: the gunner's, and a seat marked "turret" (A3:
## the Abrams' commander and loader, the Bradley's commander).
func turns_with_turret(index: int) -> bool:
	if turret == null or _gun_remote():
		return false
	return index == _gun_seat or (index >= 0 and index < (spec.get("seats", []) as Array).size() and bool(spec.seats[index].get("turret", false)))


## Whether seat `index` is a rider's (a passenger: troops, cab and bed riders), not a crew job (A3).
func is_rider(index: int) -> bool:
	return seat_kind(index) == PASSENGER


## Seat kinds boarding and casualty loading treat as riders' seats did before A3 (a passenger's,
## and a tank's commander and loader, which were passenger seats).
static func rider_like(k: StringName) -> bool:
	return k == PASSENGER or k == COMMANDER or k == LOADER


## The gun is worked from a seat that doesn't turn with it ("gun" "remote": the Petrel's belly
## turret, from the co-pilot's seat).
func _gun_remote() -> bool:
	return bool((spec.get("gun", {}) as Dictionary).get("remote", false))


## The seated pose (CharacterModel.seated_pose) for a seat whose eye is `eye` above its body's
## origin, or {} for a standing one (a hatch or a pickup bed: the stance poses him). The hips
## go on the seat's cushion (VehicleInteriors.cushion_top) and the feet on the cabin floor
## (VehicleInteriors.FLOORS; an open seat's isn't drawn there: CharacterModel.SEAT_HEIGHT under
## the hips). Captain, 2026-10-14: the UH-60M's riders were posed standing in their seats.
func _seated_pose_for(seat: Dictionary, eye: float) -> Dictionary:
	if String(seat.get("stance", "sit")) in ["stand", "upright"]:
		return {}
	if String(seat.get("stance", "sit")) == "kneel":
		## A kneeling spot on a cabin's floor: one knee up and one down (_kneel_feet, by hand).
		var kdeck := VehicleSpecs.vec(seat.at).y - eye
		kdeck = VehicleInteriors.floor_of(model) - kdeck if not is_nan(VehicleInteriors.floor_of(model)) else 0.0
		return {"board": true, "kneel": true, "hip": kdeck + KNEEL_HIP, "hip_z": 0.0, "pitch": -0.08, "yaw": 0.0,
			"floor": kdeck, "deck": kdeck}
	var eye_y := VehicleSpecs.vec(seat.at).y
	var origin_y := eye_y - eye
	var floor_y := NAN if bool(seat.get("open", false)) else VehicleInteriors.floor_of(model)
	var hip := VehicleInteriors.cushion_top(eye_y, floor_y) + CharacterModel.SEAT_HIP_UP - origin_y
	var floor_rel := hip - CharacterModel.SEAT_HEIGHT if is_nan(floor_y) else floor_y - origin_y
	var edge_foot := 0.0
	## "edge": sitting on the cabin floor itself at a door, facing out ("face"), the legs over the
	## sill and hanging (the feet EDGE_HANG_M under the floor, not on it).
	if bool(seat.get("edge", false)) and not is_nan(floor_y):
		hip = floor_y + EDGE_HIP_UP - origin_y
		floor_rel = floor_y - EDGE_HANG_M - origin_y
		edge_foot = EDGE_FOOT_M
	var pose := CharacterModel.seated_pose(hip, floor_rel, StringName(seat.get("kind", "")) in [DRIVER, PILOT, GUNNER])
	if edge_foot > 0.0:
		pose["foot"] = edge_foot
	pose["ffv"] = String(seat.get("ffv", "")) != ""  # a fire-from-vehicle seat: the rifle in the hands, not between the knees
	pose["deck"] = floor_rel if is_nan(floor_y) else floor_y - origin_y  # the cabin floor (an edge seat's feet hang under it)
	pose["edge"] = bool(seat.get("edge", false))
	## FFV: how far round from the seat's facing to face out of its door (the crouch behind it).
	match String(seat.get("ffv", "")):
		"left":
			pose["out_turn"] = wrapf(PI / 2.0 - deg_to_rad(float(seat.get("face", 0.0))), -PI, PI)
		"right":
			pose["out_turn"] = wrapf(-PI / 2.0 - deg_to_rad(float(seat.get("face", 0.0))), -PI, PI)
	## "back": a canvas back this far behind the seat's point (m): he sits back against it,
	## nearly upright (CharacterModel.SEAT_BACKED_PITCH), his pack between (_place_occupants).
	if seat.has("back"):
		pose["back"] = float(seat.back)
		pose["pitch"] = CharacterModel.SEAT_BACKED_PITCH
		pose["hip_z"] = float(seat.back) - CharacterModel.SEAT_BACK_OUT
	return pose


## Where seat `index`'s cushion is (the seated hips' spot), in the vehicle's frame, or null for
## a standing seat.
func seat_cushion(index: int) -> Variant:
	if index < 0 or index >= _seat_poses.size() or _seat_poses[index].is_empty():
		return null
	var origin := _seat_at(index).origin
	return origin + Vector3(0, float(_seat_poses[index].hip) - CharacterModel.SEAT_HIP_UP, 0)


## Where seat `index`'s floor is (under the feet), metres up in the vehicle's frame, or NAN for a
## standing seat.
func seat_floor(index: int) -> float:
	if index < 0 or index >= _seat_poses.size() or _seat_poses[index].is_empty():
		return NAN
	return _seat_at(index).origin.y + float(_seat_poses[index].floor)


## Where seat `index` puts its occupant's body, in the vehicle's frame: the turret's seat goes
## round with the ring.
func _seat_at(index: int) -> Transform3D:
	var t := hatches.seat_local(index, _seat_local[index]) if hatches else _seat_local[index]  # A4: out of a hatch
	if turns_with_turret(index):
		t.origin = turret.carry(t.origin)
	return t


## Health of a hit zone, 1 (whole) to 0 (wrecked).
func zone_health(zone: StringName) -> float:
	if not multiplayer.is_server() and net_state.has("zones"):
		return float((net_state.zones as Dictionary).get(String(zone), 1.0))
	return float(_zones.get(zone, 1.0))


## Speed along the vehicle's forward direction (m/s), on every peer.
func forward_speed() -> float:
	if multiplayer.is_server():
		return linear_velocity.dot(-global_basis.z)
	return float(net_state.get("speed", 0.0))


func fuel_litres() -> float:
	return fuel if multiplayer.is_server() else float(net_state.get("fuel", 0.0))


func is_burning() -> bool:
	return (burning_s if multiplayer.is_server() else float(net_state.get("burning", 0.0))) > 0.0


## Whether it can drive now: an engine, fuel, a battery, wheels or tracks, not a wreck.
func can_drive() -> bool:
	return not wrecked and kind != HELICOPTER and kind != STATIC and zone_health(ZONE_ENGINE) > 0.0 and fuel_litres() > 0.0 \
		and (battery_ok if multiplayer.is_server() else bool(net_state.get("battery", true))) \
		and not (kind == TRACKED and zone_health(ZONE_WHEELS) <= 0.0) and not (modules and modules.mobility_killed()) 		and not (drive and drive.blocked() != "")  # A6: rolled over, flooded, stalled in deep water, bogged


## Top speed now (m/s): the model's, cut by engine and wheel damage.
func top_speed(reverse := false) -> float:
	var top := float(spec.get("reverse_kmh" if reverse else "top_speed_kmh", 0.0)) * VehicleSpecs.KMH
	if logistics:
		top = minf(top * logistics.speed_mult(), logistics.tow_top())  # A8: the packages' weight, a tow
	if drive:
		top = minf(top, drive.speed_cap_now())  # A6: wheels on sand and mud
	if modules and modules.authored:
		return top * modules.speed_share()  # A2: engine, transmission, tracks, wheels and run-flats
	var engine := zone_health(ZONE_ENGINE)
	var wheels := zone_health(ZONE_WHEELS)
	var mult := lerpf(0.35, 1.0, engine) * (lerpf(0.5, 1.0, wheels) if wheels > 0.0 else 0.15)
	return top * mult


## The level this vehicle is in (its layer's parent).
func level() -> CompoundLevel:
	var layer := get_parent()
	return layer.get_parent() as CompoundLevel if layer else null


# --- Seats (host) ---------------------------------------------------------------------------

## Host: put `soldier` in seat `index` (-1: the first free one, a passenger seat first). Bodies
## (down or dead) go only into passenger seats and ride there (dead too) until they're pulled
## out, the vehicle burns out, or it's left with them aboard (the zone save keeps them seated);
## pilot seats take AI only. Returns whether it worked.
func server_enter(soldier: Node, index := -1) -> bool:
	var s := soldier as Soldier
	if not multiplayer.is_server() or s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or wrecked or is_burning():
		return false
	var body := not s.vitals.is_up()
	if not body and ExoMech.piloting(s.inventory):
		return false  # a heavy exo doesn't fit a seat: climb out first (ExoMech)
	if drive and drive.is_flooded():
		return false  # A6: its crew compartment is under water
	if index < 0:
		index = _first_free_passenger() if body else _first_free_for(s)
	if index < 0 or index >= _seat_nodes.size() or occupant(index) != null:
		return false
	var k := seat_kind(index)
	if body and not rider_like(k):
		return false
	if k == PILOT and not s.is_ai():
		return false  # aircraft are AI-flown only (Captain)
	var other := Vehicle.ride_of(s)
	var from_outside := other == null
	if other and other != self:
		other.server_exit(s)
	elif other == self:
		_seat_nodes[seat_of(s)] = null
	if is_instance_valid(s.carried_by):
		s.carried_by.release_carried()
	s.release_carried()
	_seat_nodes[index] = s
	if body:
		_bodies[s.get_instance_id()] = true  # a casualty or the dead, carried home: stays seated if they die
	s.vehicle = self
	s.velocity = Vector3.ZERO
	s.collision_layer = 0
	add_collision_exception_with(s)
	var brain := SquadAI.of(s)
	if brain:
		brain.drop_care()  # off while seated, it could neither finish nor hand on a casualty (A2-12)
		brain.process_mode = Node.PROCESS_MODE_DISABLED
		## Captain, 2026-10-14: its brain is off while seated, so the squad HUD kept what it said
		## before ("Waiting (briefing)" on the insertion helicopter): it says where it rides.
		if s.vitals.is_up():
			s.ai_status = "Aboard (%s)" % short_name()
	if not _died_calls.has(s.get_instance_id()):
		_died_calls[s.get_instance_id()] = _on_occupant_died.bind(s)
		s.vitals.died.connect(_died_calls[s.get_instance_id()])
	if Person.is_person(s):
		var people := PeopleLayer.find(s)
		if people:
			people.server_seat_in_vehicle(s, self, str(index))
	if from_outside and not body:
		_server_board(s, index)
	_publish_state(true)
	seats_changed.emit()
	if not Person.is_person(s) and s.vitals.is_up() and s.faction == &"friendly":
		_board_followers(s)
	return true


## Host: `s` just took seat `index` from outside: if it's a walk-in bay's seat and he's at its
## step, play the boarding clip for every peer (BOARD_FROM_M).
func _server_board(s: Soldier, index: int) -> void:
	var step := _board_step(index)
	if step < 0:
		return
	var st: Dictionary = spec.bay.steps[step]
	var foot := global_transform * _board_foot(st)
	var flat := Vector2(s.global_position.x - foot.x, s.global_position.z - foot.z)
	if flat.length() > BOARD_FROM_M:
		return
	server_set_bay(true)  # he slides the cabin door open on his way up
	var path := _board_path(st, index)
	var walk := (path[1] as Vector3).distance_to(path[2]) / BOARD_WALK_MS
	var total := CharacterModel.BOARD_STEP_S + walk + (0.0 if _seat_poses[index].is_empty() else CharacterModel.BOARD_SIT_S)
	s.model.server_play(CharacterModel.BOARD, total)
	var net := s.model.action_net.duplicate()
	net["step"] = step
	net["walk"] = walk
	net["grip"] = CharacterModel.BOARD_STEP_S
	s.model.action_net = net


## The bay step seat `index` is boarded by: the one nearest the door point that lists it (or
## nearest the seat), -1 with none.
func _board_step(index: int) -> int:
	var steps: Array = (spec.get("bay", {}) as Dictionary).get("steps", [])
	if steps.is_empty() or not seat_kind(index) in [PASSENGER, GUNNER]:
		return -1
	var near := VehicleSpecs.vec(spec.seats[index].at)
	for p: Dictionary in spec.get("points", []):
		if String(p.get("kind", "")) == "door" and (p.get("seats", []) as Array).has(index):
			near = VehicleSpecs.vec(p.at)
			break
	var best := -1
	var best_d := INF
	for k in steps.size():
		var d := VehicleSpecs.vec(steps[k].from).distance_to(near)
		if d < best_d:
			best_d = d
			best = k
	return best


## Where a boarder stands at the foot of bay step `st` (vehicle frame, on the ground).
func _board_foot(st: Dictionary) -> Vector3:
	var sill := VehicleSpecs.vec(st.from)
	var ground := VehicleSpecs.vec(st.to)
	var out := Vector3(ground.x - sill.x, 0, ground.z - sill.z).normalized()
	return Vector3(sill.x, ground.y, sill.z) + out * BOARD_OUT_M


## Boarding by step `st` into seat `index`, vehicle frame: [foot of the step, standing on the
## sill, standing in front of the seat (on the floor), the way in (flat, unit)].
func _board_path(st: Dictionary, index: int) -> Array:
	var sill := VehicleSpecs.vec(st.from)
	var foot := _board_foot(st)
	var inward := Vector3(sill.x - foot.x, 0, sill.z - foot.z).normalized()
	var up := sill + inward * BOARD_IN_M
	var seat := _seat_at(index).origin
	var face := Basis(Vector3.UP, deg_to_rad(float(spec.seats[index].get("face", 0.0)))) * Vector3.FORWARD
	## A standing or kneeling spot: walk onto the spot itself (its origin is on the floor).
	var stand_spot := _seat_poses[index].is_empty()
	var front := seat if stand_spot else seat + face * BOARD_STAND_OFF_M
	if not stand_spot:
		front.y = seat_floor(index)
	return [foot, up, front, inward]


## Every peer: `s` boarding seat `index` (action_net BOARD): where his body goes (world) and the
## pose to draw it in, {"origin", "pose", "eye"}, or {} if he isn't boarding (or it's done).
## `seat_t`: the seat's world transform; `seat_yaw`: the way it faces (world yaw).
func _board_pose(s: Soldier, index: int, seat_t: Transform3D, seat_yaw: float) -> Dictionary:
	var net := s.model.action_net
	if StringName(net.get("id", &"")) != CharacterModel.BOARD or not net.has("step") or not s.vitals.is_up():
		return {}
	var t := s.model.action_seconds()
	var steps: Array = (spec.get("bay", {}) as Dictionary).get("steps", [])
	var k := int(net.step)
	if t < 0.0 or k < 0 or k >= steps.size():
		return {}
	var path := _board_path(steps[k], index)
	var foot: Vector3 = global_transform * (path[0] as Vector3)
	var up: Vector3 = global_transform * (path[1] as Vector3)
	var front: Vector3 = global_transform * (path[2] as Vector3)
	var local_in: Vector3 = path[3]
	var inward: Vector3 = global_basis * local_in
	var in_yaw := atan2(-inward.x, -inward.z)
	var sill: Vector3 = global_transform * VehicleSpecs.vec(steps[k].from)
	var step_s := CharacterModel.BOARD_STEP_S
	var walk := float(net.get("walk", 0.0))
	var sit_s := CharacterModel.BOARD_SIT_S
	var stand_eye: float = SoldierMovement.STANCE_EYE[SoldierMovement.Stance.STAND_HIGH]
	var pose := {"board": true, "hip": CharacterModel.LEG_LENGTH, "hip_z": 0.0, "pitch": 0.0, "yaw": 0.0}
	## In through the left door (heading +x) the cabin's front is on his left: the left hand.
	s.model.board_left = local_in.x > 0.0
	s.model.board_grip = global_transform * (VehicleSpecs.vec(steps[k].from) 		+ Vector3(BOARD_HANDLE.x * signf(local_in.x), BOARD_HANDLE.y, -BOARD_HANDLE.z))
	var origin: Vector3
	var heading := in_yaw
	var eye := stand_eye
	if bool(net.get("rope", false)):
		return _rope_pose(s, index, seat_t, t, pose, steps[k])
	if bool(net.get("out", false)):
		return _run_out_pose(s, index, seat_t, seat_yaw, t, pose, path, sill)
	if t < step_s:
		## Up the step: the lead foot onto the sill, the push (leaning in, on the handle), the
		## trailing foot up after it.
		var u := t / step_s
		origin = foot.lerp(up, smoothstep(0.25, 1.0, u))
		var lead_at := sill + inward * 0.12
		var lead := foot.lerp(lead_at, smoothstep(0.0, 0.35, u)) + Vector3.UP * 0.15 * sin(PI * clampf(u / 0.35, 0.0, 1.0))
		var trail := foot.lerp(up, smoothstep(0.55, 0.95, u)) + Vector3.UP * 0.12 * sin(PI * clampf((u - 0.55) / 0.4, 0.0, 1.0))
		pose["foot_r"] = _board_foot_at(lead, origin, inward)
		pose["foot_l"] = _board_foot_at(trail, origin, inward)
		pose["pitch"] = CharacterModel.BOARD_LEAN * smoothstep(0.15, 0.45, u) * (1.0 - smoothstep(0.65, 1.0, u))
	elif t < step_s + walk:
		## In to the seat, turning to sit as he gets there.
		var u := (t - step_s) / maxf(walk, 0.01)
		origin = up.lerp(front, u)
		var stride := up.distance_to(front) * u / 0.55
		var swing := 0.16 * sin(PI * stride)
		pose["foot_l"] = Vector2(swing, 0.05 * maxf(sin(PI * stride), 0.0))
		pose["foot_r"] = Vector2(-swing, 0.05 * maxf(-sin(PI * stride), 0.0))
		heading = lerp_angle(in_yaw, seat_yaw, smoothstep(0.35, 1.0, u))
	elif t < step_s + walk + sit_s and not _seat_poses[index].is_empty():
		## Sitting down: drawn from the seat's own origin, from standing in front of it.
		var u := (t - step_s - walk) / sit_s
		origin = seat_t.origin
		var seated: Dictionary = _seat_poses[index].duplicate()
		seated["yaw"] = 0.0
		var floor_rel := float(seated.floor)
		pose["foot_l"] = Vector2(BOARD_STAND_OFF_M, floor_rel)
		pose["foot_r"] = Vector2(BOARD_STAND_OFF_M, floor_rel)
		pose["hip"] = floor_rel + CharacterModel.LEG_LENGTH
		pose["hip_z"] = -BOARD_STAND_OFF_M
		pose["sit"] = smoothstep(0.0, 1.0, u)
		pose["into"] = seated
		heading = seat_yaw
		eye = lerpf(floor_rel + stand_eye, Vehicle.seat_eye("sit"), smoothstep(0.0, 1.0, u))
	else:
		return {}
	pose["yaw"] = wrapf(heading - s.rotation.y, -PI, PI)
	return {"origin": origin, "pose": pose, "eye": eye}


## An FFV rider with the doors shut (FFV_CROUCH_*): crouched on the cabin floor behind the door,
## facing out, drawn `open` (0..1, the doors' travel) of the way into his seated pose `seated`
## (CharacterModel._boarding_bones' "into").
static func _ffv_crouch(seated: Dictionary, open: float, lefty: bool) -> Dictionary:
	var deck := float(seated.get("deck", seated.floor))
	var back := FFV_CROUCH_BACK if bool(seated.get("edge", false)) else FFV_CROUCH_BACK_SEATED
	## Kneeling, turned to face the door (an edge seat already does), easing round to the seat's
	## way as he sits.
	var pose := {"board": true, "hip": deck + KNEEL_HIP, "hip_z": back, "pitch": -0.12, "yaw": float(seated.yaw) + float(seated.get("out_turn", 0.0)),
		"sit": smoothstep(0.0, 1.0, open), "into": seated}
	_kneel_feet(pose, deck, back, lefty)
	return pose


## A kneeling pose's feet (`pose`'s "foot_l"/"foot_r", CharacterModel._boarding_bones): the
## shooting side's knee up (its foot planted KNEEL_UP_FOOT ahead of the hips), the other knee on
## the floor (its foot KNEEL_DOWN_FOOT behind). `deck`: the floor, `back`: how far the hips sit
## back from the body's origin.
static func _kneel_feet(pose: Dictionary, deck: float, back: float, lefty: bool) -> void:
	var up := Vector2(-back + KNEEL_UP_FOOT, deck)
	var down := Vector2(-back - KNEEL_DOWN_FOOT, deck + 0.04)
	pose["foot_l"] = up if lefty else down
	pose["foot_r"] = down if lefty else up


## Every peer: `s` running out of seat `index` (action_net BOARD with "out"), `t` s in: up off
## the seat, the run to the door turning to face out, down off the sill; held at the step's foot
## until the host lets him out.
func _run_out_pose(s: Soldier, index: int, seat_t: Transform3D, seat_yaw: float, t: float, pose: Dictionary, path: Array, sill: Vector3) -> Dictionary:
	var foot: Vector3 = global_transform * (path[0] as Vector3)
	var up: Vector3 = global_transform * (path[1] as Vector3)
	var front: Vector3 = global_transform * (path[2] as Vector3)
	var outward: Vector3 = -(global_basis * (path[3] as Vector3))
	var out_yaw := atan2(-outward.x, -outward.z)
	var stand_eye: float = SoldierMovement.STANCE_EYE[SoldierMovement.Stance.STAND_HIGH]
	var sit_s := 0.0 if _seat_poses[index].is_empty() else RUN_OUT_SIT_S
	var run := float(s.model.action_net.get("walk", 0.0))
	var origin := foot
	var heading := out_yaw
	var eye := stand_eye
	pose["foot_l"] = Vector2.ZERO
	pose["foot_r"] = Vector2.ZERO
	if t < sit_s:
		var u := t / sit_s
		origin = seat_t.origin
		var seated: Dictionary = _seat_poses[index].duplicate()
		seated["yaw"] = 0.0
		var floor_rel := float(seated.floor)
		pose["foot_l"] = Vector2(BOARD_STAND_OFF_M, floor_rel)
		pose["foot_r"] = Vector2(BOARD_STAND_OFF_M, floor_rel)
		pose["hip"] = floor_rel + CharacterModel.LEG_LENGTH
		pose["hip_z"] = -BOARD_STAND_OFF_M
		pose["sit"] = 1.0 - smoothstep(0.0, 1.0, u)
		pose["into"] = seated
		heading = seat_yaw
		eye = lerpf(Vehicle.seat_eye("sit"), floor_rel + stand_eye, smoothstep(0.0, 1.0, u))
	elif t < sit_s + run:
		var u := (t - sit_s) / maxf(run, 0.01)
		origin = front.lerp(up, u)
		var stride := front.distance_to(up) * u / 0.8
		var swing := 0.22 * sin(PI * stride)
		pose["foot_l"] = Vector2(swing, 0.08 * maxf(sin(PI * stride), 0.0))
		pose["foot_r"] = Vector2(-swing, 0.08 * maxf(-sin(PI * stride), 0.0))
		pose["pitch"] = -0.18
		heading = lerp_angle(seat_yaw, out_yaw, smoothstep(0.0, 0.35, u))
	elif t < sit_s + run + RUN_OUT_STEP_S:
		## Down off the sill: the lead foot to the ground, the body after it, the trailing foot last.
		var u := (t - sit_s - run) / RUN_OUT_STEP_S
		origin = up.lerp(foot, smoothstep(0.15, 0.85, u))
		var lead := (sill + outward * 0.1).lerp(foot + outward * 0.25, smoothstep(0.0, 0.5, u)) + Vector3.UP * 0.12 * sin(PI * clampf(u / 0.5, 0.0, 1.0))
		var trail := up.lerp(foot, smoothstep(0.45, 1.0, u)) + Vector3.UP * 0.1 * sin(PI * clampf((u - 0.45) / 0.55, 0.0, 1.0))
		pose["foot_r"] = _board_foot_at(lead, origin, outward)
		pose["foot_l"] = _board_foot_at(trail, origin, outward)
		pose["pitch"] = -0.2
	pose["yaw"] = wrapf(heading - s.rotation.y, -PI, PI)
	return {"origin": origin, "pose": pose, "eye": eye}


## Every peer: a helicopter's pilots, seen at the controls (Captain, 2026-10-17: "make sure it has
## pilots"). The flying stays the helicopter's own (Helicopter: aircraft are AI-flown; nobody
## takes the pilot seats), so they're drawn, not soldiers: a figure in flight kit seated at each
## pilot seat, hands on the controls, gone with a wreck (HeliCall's crash survivors are the crew).
func _build_crew() -> void:
	for i in _seat_local.size():
		if seat_kind(i) != PILOT or _seat_poses[i].is_empty():
			continue
		var pivot := Node3D.new()
		pivot.name = "Crew%d" % i
		pivot.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec.seats[i].get("face", 0.0)))), _seat_local[i].origin)
		add_child(pivot)
		var inv := Inventory.new()
		inv.name = "Inventory"
		pivot.add_child(inv)
		inv.take(&"helmet")
		var model := CharacterModel.new()
		model.name = "Model"
		model.variant = "multicam"
		model.face = SoldierLook.make(SoldierLook.seed_of([name, "crew", i]), "US", VoxelArt.MALE)  # its own crewman
		pivot.add_child(model)
		var rig := GearRig.new()
		rig.name = "Gear"
		rig.inventory = inv
		rig.model = model
		pivot.add_child(rig)
		var pose: Dictionary = _seat_poses[i].duplicate()
		pose["yaw"] = 0.0
		model.pose = pose
		_crew.append(pivot)


## Every peer: door gun `i`'s gunner `s` swings it to where he looks (his synced turn, less the
## vehicle's; his look pitch), and his hands take its grips (`seated`'s "grip_l"/"grip_r").
func _man_door_gun(i: int, s: Soldier, seated: Dictionary, veh_yaw: float) -> void:
	var gun: DoorGun = _door_guns[i]
	if not s.vitals.is_up():
		gun.stow()
		seated.erase("grip_l")
		seated.erase("grip_r")
		return
	var out := PI / 2.0 if gun.side < 0.0 else -PI / 2.0
	gun.aim(wrapf(s.rotation.y - veh_yaw - out, -PI, PI), s.model.look_pitch)
	seated["grip_r"] = gun.grip(true)
	seated["grip_l"] = gun.grip(false)


## Every peer: `s` going down the fast-rope from bay step `st` (action_net BOARD with "rope"),
## `t` s in: up from the seat to the door, facing in on the rope; then the slide, hands on the
## rope over his head, legs together and a little bent, down to the ground.
func _rope_pose(s: Soldier, index: int, seat_t: Transform3D, t: float, pose: Dictionary, st: Dictionary) -> Dictionary:
	var top: Vector3 = global_transform * _rope_top(st)
	var sill := VehicleSpecs.vec(st.from)
	var door: Vector3 = global_transform * (sill + Vector3(signf(sill.x) * 0.15, 0.0, 0.0))
	var inward: Vector3 = global_basis * Vector3(-signf(sill.x), 0.0, 0.0)
	var drop := float(s.model.action_net.get("drop", 5.0))
	var hang := Vector3(top.x, 0.0, top.z) - inward * 0.25  # where he hangs, the rope at his face
	var origin: Vector3
	if t < ROPE_TO_DOOR_S:
		var u := smoothstep(0.0, 1.0, t / ROPE_TO_DOOR_S)
		var from := Vector3(seat_t.origin.x, door.y, seat_t.origin.z)
		origin = from.lerp(Vector3(hang.x, door.y, hang.z), u)
	else:
		var u := clampf((t - ROPE_TO_DOOR_S) * ROPE_SLIDE_MS / maxf(drop, 0.01), 0.0, 1.0)
		origin = Vector3(hang.x, lerpf(door.y, door.y - drop - (door.y - (top.y - ROPE_TOP_M)) , u), hang.z)
	pose["foot_l"] = Vector2(0.05, 0.0)
	pose["foot_r"] = Vector2(-0.05, 0.0)
	pose["hip"] = CharacterModel.LEG_LENGTH - 0.08
	pose["pitch"] = 0.05
	s.model.board_grip = Vector3(top.x, origin.y + 2.0, top.z)
	var heading := atan2(-inward.x, -inward.z)
	pose["yaw"] = wrapf(heading - s.rotation.y, -PI, PI)
	return {"origin": origin, "pose": pose, "eye": SoldierMovement.STANCE_EYE[SoldierMovement.Stance.STAND_HIGH]}


## A foot at `at` (world) as CharacterModel's boarding foot: Vector2(forward of, up from) the
## body's `origin`, forward being `inward`.
static func _board_foot_at(at: Vector3, origin: Vector3, inward: Vector3) -> Vector2:
	var d := at - origin
	return Vector2(Vector2(d.x, d.z).dot(Vector2(inward.x, inward.z)), d.y)


## How far a worn pack stands off a seated rider's back (m, at most SEAT_PACK_MAX_M), cached per
## pack (GearRig.pack_depth sizes its model).
static func _pack_off(s: Soldier) -> float:
	var pack := String(s.inventory.slots.get(&"backpack", &"")) + "|" + String(s.inventory.slots.get(ExoFrame.SLOT, &""))
	var cached: Array = s.get_meta(&"seat_pack", ["", 0.0])
	if cached[0] != pack:
		cached = [pack, minf(GearRig.pack_depth(s.inventory), SEAT_PACK_MAX_M)]
		s.set_meta(&"seat_pack", cached)
	return float(cached[1])


## Captain, 2026-10-15 (v0.4.11: HVTs and hostages wouldn't get into AAVs or M-ATVs): the people
## `leader` leads (Follow me) or escorts (Squad.order_escort), up and within FOLLOWER_BOARD_M,
## get in with him, into free passenger seats, and remember who they rode with so they get out
## when he does (_dismount_followers). Host only (server_enter).
const FOLLOWER_BOARD_M := 12.0

func _board_followers(leader: Soldier) -> void:
	var people := PeopleLayer.find(leader)
	if people == null:
		return
	var key := people.key_of(leader)
	var brain := SquadAI.of(leader)
	var escorted: Soldier = brain.escorting if brain and brain.escort_valid() else null
	for p: Soldier in people.people():
		if p == leader or not is_instance_valid(p) or p.is_queued_for_deletion() or not p.vitals.is_up() 				or Vehicle.ride_of(p) != null or is_instance_valid(p.carried_by):
			continue
		var st := people.state_of(p)
		if bool(st.get("delivered", false)):
			continue
		var led := String(st.get("led_by", "")) == key
		if not led and p != escorted:
			continue
		if p.global_position.distance_to(leader.global_position) > FOLLOWER_BOARD_M:
			continue
		var seat := _first_free_passenger()
		if seat < 0:
			_tell(leader, "No seat for %s" % p.display_name())
			return
		if server_enter(p, seat):
			people.server_set_state(p, {"rode_with": key, "rode_led": led})


## Host: `leader` got out: the people who got in with him (_board_followers) get out too, and
## those he led follow him again.
func _dismount_followers(leader: Soldier) -> void:
	var people := PeopleLayer.find(leader)
	if people == null:
		return
	var key := people.key_of(leader)
	for p: Soldier in occupants():
		if not Person.is_person(p) or not p.vitals.is_up():
			continue
		var st := people.state_of(p)
		if String(st.get("rode_with", "")) != key:
			continue
		var led := bool(st.get("rode_led", false))
		server_exit(p)
		people.server_set_state(p, {"rode_with": "", "rode_led": false})
		if led:
			people.server_set_state(p, {"led_by": key, "order": "follow"})


func _first_free_passenger() -> int:
	for i in _seat_nodes.size():
		if occupant(i) == null and rider_like(seat_kind(i)) and not exo_seat(i):
			return i
	return -1


## Whether seat `index` is a heavy exo's standing spot (seat "exo": the Razorback's aft bay,
## Captain 2026-10-17: room for two heavy exos standing or kneeling). Nobody else is put there
## by default; an HX-1 pilot rides only there (_first_free_exo).
func exo_seat(index: int) -> bool:
	return index >= 0 and index < (spec.get("seats", []) as Array).size() and bool(spec.seats[index].get("exo", false))


## The first free heavy-exo spot, or -1.
func _first_free_exo() -> int:
	for i in _seat_nodes.size():
		if occupant(i) == null and exo_seat(i):
			return i
	return -1


## The first free fire-from-vehicle passenger seat (seat "ffv"), or -1.
func _first_free_ffv() -> int:
	for i in _seat_nodes.size():
		if occupant(i) == null and seat_kind(i) == PASSENGER and String(spec.seats[i].get("ffv", "")) != "":
			return i
	return -1


func _first_free_for(s: Soldier) -> int:
	## Captain, 2026-10-17: AI fill a helicopter's fire-from-vehicle door seats (seat "ffv") first,
	## so the doors are manned before anyone sits back in the cabin.
	if s.is_ai() and not Person.is_person(s) and _first_free_ffv() >= 0:
		return _first_free_ffv()
	var order: Array[StringName] = [PASSENGER, GUNNER, DRIVER, PILOT]
	for k in order:
		for i in _seat_nodes.size():
			# (A3: a tank's commander and loader seats fill with the riders' seats, as when they were passenger seats)
			var match_k := rider_like(seat_kind(i)) if k == PASSENGER else seat_kind(i) == k
			if occupant(i) == null and match_k and (k != PILOT or s.is_ai()) and not exo_seat(i):
				return i
	return -1


## Host: take `soldier` out of the vehicle to a safe free spot beside it (by their seat's
## door first, then round the vehicle).
func server_exit(soldier: Node, at: Variant = null) -> void:
	var s := soldier as Soldier
	var index := seat_of(s)
	if not multiplayer.is_server() or index < 0:
		return
	_running_out.erase(s.get_instance_id())
	var spot: Vector3 = at if at is Vector3 else exit_spot(index, s)
	if StringName(s.model.action_net.get("id", &"")) == CharacterModel.BOARD:
		s.model.action_net = {}  # out before he'd sat down
	_seat_nodes[index] = null
	_bodies.erase(s.get_instance_id())
	_release(s)
	_forget_death(s)
	if Person.is_person(s):
		var people := PeopleLayer.find(s)
		if people:
			people.server_unseat(s)
	if s.is_ai() or s.owner_peer() == multiplayer.get_unique_id():
		_put_out(s, spot)
	else:
		_client_exit.rpc_id(s.owner_peer(), level().get_path_to(s), spot)
	_publish_state(true)
	seats_changed.emit()
	if not Person.is_person(s) and s.vitals.is_up() and s.faction == &"friendly":
		_dismount_followers(s)


## Host: AI `s` gets out by running out (RUN_OUT_*): from a walk-in bay's seat on the ground,
## he plays the boarding move the other way (up, to the door, down off the sill) and is out at
## the step's foot when it ends (_step_run_outs). Anyone else, anywhere else: server_exit.
func server_run_out(s: Soldier) -> void:
	var index := seat_of(s)
	if index < 0 or not multiplayer.is_server():
		return
	var step := _board_step(index)
	var flying: bool = has_method("is_airborne") and call("is_airborne")
	if not s.is_ai() or not s.vitals.is_up() or step < 0 or wrecked or flying or is_instance_valid(s.carried_by):
		server_exit(s)
		return
	if _running_out.has(s.get_instance_id()):
		return
	var path := _board_path(spec.bay.steps[step], index)
	var run := (path[1] as Vector3).distance_to(path[2]) / RUN_OUT_MS
	var total := (0.0 if _seat_poses[index].is_empty() else RUN_OUT_SIT_S) + run + RUN_OUT_STEP_S
	server_set_bay(true)
	s.model.server_play(CharacterModel.BOARD, total)
	var net := s.model.action_net.duplicate()
	net["step"] = step
	net["walk"] = run
	net["out"] = true
	s.model.action_net = net
	_running_out[s.get_instance_id()] = [s, Soldier._now() + total, path[0]]


## Host: `s` goes down a fast-rope from the door on `side` (-1 left, 1 right: the bay step on
## that side) to the ground below it: to the door, then the slide (action_net BOARD with
## "rope"), out at the rope's foot when it ends (_step_run_outs). Without a bay step there: out.
func server_fast_rope(s: Soldier, side: float) -> void:
	var index := seat_of(s)
	if index < 0 or not multiplayer.is_server() or _running_out.has(s.get_instance_id()):
		return
	var steps: Array = (spec.get("bay", {}) as Dictionary).get("steps", [])
	var step := -1
	for k in steps.size():
		if signf(VehicleSpecs.vec(steps[k].from).x) == signf(side):
			step = k
	if step < 0:
		server_exit(s)
		return
	server_set_bay(true)
	var top := _rope_top(steps[step])
	var ground := _rope_ground(global_transform * top)
	var drop := maxf((global_transform * top).y - ground - 1.7, 0.5)
	var total := ROPE_TO_DOOR_S + drop / ROPE_SLIDE_MS
	s.model.server_play(CharacterModel.BOARD, total)
	var net := s.model.action_net.duplicate()
	net["step"] = step
	net["rope"] = true
	net["drop"] = drop
	s.model.action_net = net
	var foot := global_transform.affine_inverse() * Vector3((global_transform * top).x, ground, (global_transform * top).z)
	_running_out[s.get_instance_id()] = [s, Soldier._now() + total, foot, step]


## The ground (or a roof) under a rope hanging from `at` (world): looked for straight down from
## the rope's top, under the rotor (a probe from higher met the rotor disc), its own hull aside.
func _rope_ground(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 80.0, SoldierMovement.WORLD_MASK, [get_rid()]))
		if not hit.is_empty():
			return (hit.position as Vector3).y
	var lvl := level()
	return lvl.ground_point(Vector3(at.x, 0.0, at.z)).y if lvl else at.y - 15.0


## Where bay step `st`'s rope hangs from (the vehicle's frame): out past the sill, up the door.
func _rope_top(st: Dictionary) -> Vector3:
	var sill := VehicleSpecs.vec(st.from)
	return sill + Vector3(signf(sill.x) * ROPE_OUT_M, ROPE_TOP_M, 0.0)


## Every peer: the fast-ropes hang from each door to the ground while they're out.
func _update_ropes() -> void:
	var out := ropes_out if multiplayer.is_server() else bool(net_state.get("ropes", false))
	if not out:
		for r in _ropes:
			r.visible = false
		return
	var steps: Array = (spec.get("bay", {}) as Dictionary).get("steps", [])
	if _ropes.is_empty():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("3b3428")
		mat.roughness = 1.0
		for k in steps.size():
			var r := MeshInstance3D.new()
			r.name = "Rope%d" % k
			var m := BoxMesh.new()
			m.size = Vector3(0.045, 1.0, 0.045)
			r.mesh = m
			r.material_override = mat
			add_child(r)
			_ropes.append(r)
	for k in mini(steps.size(), _ropes.size()):
		var top := global_transform * _rope_top(steps[k])
		var ground := _rope_ground(top)
		var length := maxf(top.y - ground, 0.5)
		_ropes[k].visible = true
		_ropes[k].global_transform = Transform3D(Basis.from_scale(Vector3(1.0, length, 1.0)), Vector3(top.x, top.y - length * 0.5, top.z))


## Whether anyone is still running out.
func running_out() -> bool:
	return not _running_out.is_empty()


## Host: the runners whose run is over (or cut short) get out at the step's foot. A fast-roper
## (a 4th entry: his bay step) gets out on the ground under the rope as it hangs NOW: the foot
## worked out when he set off moved with the hovering aircraft, so any bob or drift let him go
## metres up (2026-10-18: ~4.9 m on the range, R1745).
func _step_run_outs() -> void:
	for id: int in _running_out.keys():
		var e: Array = _running_out[id]
		var s: Soldier = e[0] if is_instance_valid(e[0]) else null
		if s == null or seat_of(s) < 0:
			_running_out.erase(id)
		elif Soldier._now() >= float(e[1]) or wrecked or not s.vitals.is_up():
			_running_out.erase(id)
			var at: Vector3 = global_transform * (e[2] as Vector3)
			var steps: Array = (spec.get("bay", {}) as Dictionary).get("steps", [])
			if e.size() > 3 and int(e[3]) < steps.size():
				var top := global_transform * _rope_top(steps[int(e[3])])
				at = Vector3(top.x, _rope_ground(top), top.z)
			server_exit(s, at + Vector3.UP * 0.05)


## Host: move `soldier` to seat `index` of this vehicle (they must be in it already). On a model
## with "switch_s" (A3, docs/combined_arms.md 2.5.3: the Abrams, the Bradley) the move takes
## time (switch_time): he stays where he is, at no job (moving_seat), until it's done (_step_moves);
## turret to driver on the Abrams needs the turret near the front. Elsewhere it's at once.
func server_switch(soldier: Node, index: int) -> bool:
	var s := soldier as Soldier
	var from := seat_of(s)
	if from < 0 or index < 0 or index >= _seat_nodes.size() or occupant(index) != null or index == from:
		return false
	if seat_kind(index) == PILOT and not s.is_ai():
		return false
	var wait := switch_time(from, index)
	if wait < 0.0:
		_tell(s, "Traverse the turret to the front first")
		return false
	if wait > 0.0:
		_moving[s.get_instance_id()] = {"to": index, "at": Soldier._now() + wait}
		return true
	_moving.erase(s.get_instance_id())
	return _switch_now(s, from, index)


## How long a move from seat `from` to `to` takes (A3, 2.5.3; "switch_s" in the model's data):
## 0 at once (no "switch_s", or rider to rider), -1 not now (the Abrams' turret off the front for
## the driver's hatch).
func switch_time(from: int, to: int) -> float:
	var t: Dictionary = spec.get("switch_s", {})
	if t.is_empty():
		return 0.0
	var a := _move_group(from)
	var b := _move_group(to)
	if a == "troop" and b == "troop":
		return 0.0
	if a == "troop" or b == "troop":
		return float(t.get("troop", t.get("turret", 0.0)))
	if a == b:
		return float(t.get("turret", 0.0)) if a == "turret" else 0.0
	var front := float(t.get("front_deg", 0.0))
	if front > 0.0 and turret and absf(rad_to_deg(wrapf(turret.yaw, -PI, PI))) > front:
		return -1.0
	return float(t.get("driver", 0.0))


func _move_group(index: int) -> String:
	if seat_kind(index) == DRIVER:
		return "driver"
	return "turret" if seat_kind(index) in [GUNNER, COMMANDER, LOADER] or turns_with_turret(index) else "troop"


## Whether `s` is moving between seats here (A3): he does no job until he's in the new one.
func moving_seat(s: Node) -> bool:
	return s != null and _moving.has(s.get_instance_id())


## The seat `s` is moving to (-1: none) and the seconds left.
func move_of(s: Node) -> Vector2:
	if not moving_seat(s):
		return Vector2(-1, 0)
	var m: Dictionary = _moving[s.get_instance_id()]
	return Vector2(int(m.to), maxf(float(m.at) - Soldier._now(), 0.0))


## Host: the timed seat moves that are done happen (the seat still free and he still aboard and
## up); the rest wait.
func _step_moves() -> void:
	var now := Soldier._now()
	for id: int in _moving.keys():
		var m: Dictionary = _moving[id]
		var s := instance_from_id(id) as Soldier
		var from := seat_of(s) if is_instance_valid(s) else -1
		if from < 0 or not s.vitals.is_up() or occupant(int(m.to)) != null:
			_moving.erase(id)  # out, down, or someone took the seat first
			continue
		if now >= float(m.at):
			_moving.erase(id)
			_switch_now(s, from, int(m.to))


func _switch_now(s: Soldier, from: int, index: int) -> bool:
	_seat_nodes[from] = null
	_seat_nodes[index] = s
	s.remove_meta(&"seat_veh_yaw")
	_publish_state(true)
	seats_changed.emit()
	return true


## Where seat `index`'s occupant gets out: a spot by their door with room to stand, on the
## ground (the first clear one round the vehicle if that's blocked). With a walk-in bay open
## and landed, a bay seat's occupant stands up in the aisle beside it instead (VehicleBay).
func exit_spot(index: int, s: Soldier = null) -> Vector3:
	var aisle: Variant = _bay_aisle(index, s)
	if aisle != null:
		return aisle
	var size := VehicleArt.size_m(model)
	var defs: Array = spec.get("seats", [])
	var seat_at := VehicleSpecs.vec(defs[index].at) if index >= 0 and index < defs.size() else Vector3.ZERO
	var side := String(defs[index].get("exit", "left")) if index >= 0 and index < defs.size() else "left"
	## Captain, 2026-10-14: a helicopter landed with a threat abeam (HeliCall._land) puts everyone
	## out of the door on the far side, the fuselage between them and it.
	if has_meta(&"exit_away") and (side == "left" or side == "right"):
		side = "left" if to_local(get_meta(&"exit_away") as Vector3).x > 0.0 else "right"
	var hx := size.x * 0.5 + EXIT_GAP_M
	var hz := size.z * 0.5 + EXIT_GAP_M
	var candidates: Array[Vector3] = []
	var by_side := {"left": Vector3(-hx, 0, seat_at.z), "right": Vector3(hx, 0, seat_at.z), "rear": Vector3(clampf(seat_at.x, -0.8, 0.8), 0, hz), "front": Vector3(seat_at.x, 0, -hz)}
	candidates.append(by_side.get(side, by_side.left))
	for step: float in [0.0, -1.2, 1.2, -2.4, 2.4]:
		candidates.append(Vector3(-hx, 0, seat_at.z + step))
		candidates.append(Vector3(hx, 0, seat_at.z + step))
	candidates.append(by_side.rear)
	candidates.append(by_side.front)
	candidates.append(Vector3(0, 0, hz + 1.0))
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	var exclude: Array[RID] = [get_rid()]
	if s:
		exclude.append(s.get_rid())
	for c in candidates:
		var flat := global_transform * c
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(flat + Vector3.UP * 3.0, flat + Vector3.DOWN * 6.0, 1, exclude))
		var ground: Vector3 = down.position if not down.is_empty() else Vector3(flat.x, global_position.y, flat.z)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis(), ground + Vector3.UP * 0.95)
		q.collision_mask = 1 | Soldier.BODY_LAYER | LAYER
		q.exclude = exclude
		if space.intersect_shape(q, 1).is_empty():
			return ground + Vector3.UP * 0.05
	var fallback := global_transform * candidates[0]
	return Vector3(fallback.x, global_position.y + 0.05, fallback.z)


## The aisle spot by bay seat `index` (world), or null: no bay, shut, flying, not a bay seat, or
## an AI (they walk the navmesh, which doesn't run inside a vehicle: out by the door for them).
func _bay_aisle(index: int, s: Soldier) -> Variant:
	if bay == null or not bay.open or not bay.has_cabin() or s == null or s.is_ai():
		return null
	var heli := self as Node as Helicopter
	if heli and (heli.is_airborne() or heli.height_agl() > VehicleBay.LIFT_M):
		return null
	var defs: Array = spec.get("seats", [])
	if index < 0 or index >= defs.size() or seat_kind(index) == PILOT:
		return null
	var at := VehicleSpecs.vec(defs[index].at)
	var spot: Variant = bay.aisle_by(at)
	if spot == null:
		return null
	return global_transform * (spot as Vector3)


## Host: `s`, standing, put out by the nearest door (VehicleBay: nobody stays on their feet in
## a bay that lifts off with no seat free).
func server_put_out(s: Soldier) -> void:
	var spot := exit_spot(-1, s)
	if s.is_ai() or s.owner_peer() == multiplayer.get_unique_id():
		_put_out(s, spot)
	else:
		_client_exit.rpc_id(s.owner_peer(), level().get_path_to(s), spot)


## Whether seat `index`'s occupant is out in the open (seen and hit from outside): an "open"
## seat, or a fire-from-vehicle seat with the bay open.
func seat_open(index: int) -> bool:
	var defs: Array = spec.get("seats", [])
	if index < 0 or index >= defs.size():
		return false
	return bool((defs[index] as Dictionary).get("open", false)) or (bay != null and bay.ffv_active(index)) or (hatches != null and hatches.exposed(index))


## Whether `s` may fire their own weapon from their seat along `direction` (world): a fire-
## from-vehicle seat, the bay open, the line out of its door, and clear of this aircraft.
## Captain, 2026-10-16: "make sure safety checks ensure they dont shoot our helo". Ballistics
## leaves the vehicle you ride out of a round's path, so this is the check: a ray from the eye
## along the shot, FFV_CLEAR_M out, against this vehicle's own collision (the bay walls round
## the door, wings, nacelles, rotor and sponson boxes) must meet none of it.
const FFV_CLEAR_M := 16.0
func ffv_ok(s: Soldier, direction: Vector3, origin: Variant = null) -> bool:
	if bay == null or s == null or not bay.ffv_arc_ok(seat_of(s), direction):
		return false
	var from: Vector3 = origin if origin != null else s.camera.global_position
	return ffv_clear(from, direction)


## Whether a line from `from` along `direction` stays off this vehicle's own collision for
## FFV_CLEAR_M: its boxes and the bay's shell (the walls either side of the door: the eye sits
## in the hollow cabin, so they count).
func ffv_clear(from: Vector3, direction: Vector3) -> bool:
	if not is_inside_tree() or direction.length_squared() < 0.000001:
		return false
	var space := get_world_3d().direct_space_state
	var to := from + direction.normalized() * FFV_CLEAR_M
	var exclude: Array[RID] = []
	for _i in 4:  # other vehicles first in line don't hide our own hull behind them
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider == self or (bay != null and hit.collider == bay.deck):
			return false
		exclude.append((hit.collider as CollisionObject3D).get_rid())
	return true


## Whether `s` sits in a fire-from-vehicle seat that's live now (their weapon up, in hand).
func ffv_seat(s: Soldier) -> bool:
	return bay != null and bay.ffv_active(seat_of(s))


## Host: opens or shuts the bay (doors and ramp).
func server_set_bay(value: bool) -> void:
	if bay == null or wrecked or bay.open == value:
		return
	bay.set_open(value)
	Sfx.server_play(&"reload", global_position + Vector3.UP)  # a panel's clunk (no own sound yet)
	_publish_state(true)


## Anyone aboard, in the bay or by a door: open or shut the bay.
@rpc("any_peer", "call_local", "reliable")
func request_bay(value: bool) -> void:
	var actor := _sender()
	if multiplayer.is_server() and actor and actor.vitals.is_up() and (seat_of(actor) >= 0 or in_reach(actor)):
		server_set_bay(value)


## Every peer: the body this peer drives (the local player, the host's AI) goes to `spot`.
func _put_out(s: Soldier, spot: Vector3) -> void:
	s.set_meta(&"vehicle_left_at", Soldier._now())
	_release(s)
	s.global_position = spot
	s.velocity = Vector3.ZERO


## The owner of a player who got out moves their own body (their position is theirs to send).
@rpc("authority", "call_local", "reliable")
func _client_exit(path: NodePath, spot: Vector3) -> void:
	var lvl := level()
	var s := lvl.get_node_or_null(path) as Soldier if lvl else null
	if s and s.is_multiplayer_authority():
		_put_out(s, spot)


## Every peer: `s` no longer sits here: visible, solid, standing, its AI back on.
func _release(s: Soldier) -> void:
	if not is_instance_valid(s):
		return
	_seen.erase(s.get_instance_id())
	remove_collision_exception_with(s)
	if s.vehicle == self:
		s.vehicle = null
	s.remove_meta(&"turret_set")
	s.model.visible = true
	s.gear.visible = true
	s.seat_pose = {}
	s.remove_meta(&"seat_veh_yaw")
	if s.vitals.is_up() and s.collision_layer == 0 and not is_instance_valid(s.ragdoll) and not is_instance_valid(s.carried_by):
		s.collision_layer = Soldier.BODY_LAYER
	if s.is_multiplayer_authority() and s.vitals.is_up():
		s.movement.stance = SoldierMovement.Stance.STAND_HIGH
		s.head.position.y = SoldierMovement.STAND_HEAD_Y
	if multiplayer.is_server():
		var brain := SquadAI.of(s)
		if brain and not s.vitals.is_dead():
			brain.process_mode = Node.PROCESS_MODE_INHERIT


## Leaving the scene with people still seated (a support helicopter gone off the map with a door
## rider aboard, a test clearing up): they're let go, not left marked aboard with their AI off
## (2026-10-17: an extraction's squadmate stranded that way, supports R1723).
func _exit_tree() -> void:
	for i in _seat_nodes.size():
		var s := occupant(i)
		if s != null and is_instance_valid(s) and not s.is_queued_for_deletion():
			_seat_nodes[i] = null
			_release(s)


func _forget_death(s: Soldier) -> void:
	var call: Variant = _died_calls.get(s.get_instance_id())
	_died_calls.erase(s.get_instance_id())
	if call != null and s.vitals.died.is_connected(call):
		s.vitals.died.disconnect(call)


## Host: an occupant died. A casualty loaded as a body rides on, dead (their comrades are taking
## them home). Anyone else who dies in a seat is put out: an AI's body beside the vehicle; a
## player's body (left where they died, inside) goes out beside it too and the player (who
## respawns) leaves the seat.
func _on_occupant_died(s: Soldier) -> void:
	if not multiplayer.is_server() or seat_of(s) < 0:
		return
	var index := seat_of(s)
	if s.is_ai() and _bodies.has(s.get_instance_id()):
		_publish_state(true)
		return
	if s.is_ai():
		server_exit(s)
		return
	var seat_pos := (global_transform * _seat_at(index)).origin
	var spot := exit_spot(index, s)
	_seat_nodes[index] = null
	_bodies.erase(s.get_instance_id())
	_release(s)
	_forget_death(s)
	var lvl := level()
	if lvl:
		for b in lvl.bodies.get_children():
			if b is Soldier and (b as Soldier).global_position.distance_to(seat_pos) < 1.0:
				(b as Soldier).global_position = spot
	_publish_state(true)
	seats_changed.emit()


# --- Every peer: occupants ride along --------------------------------------------------------

func _place_occupants() -> void:
	var now_seen := {}
	var defs: Array = spec.get("seats", [])
	for i in _seat_nodes.size():
		var s := occupant(i)
		if s == null:
			continue
		if s.has_meta(&"vehicle_left_at") and Soldier._now() - float(s.get_meta(&"vehicle_left_at")) < EXIT_GRACE_S:
			continue
		now_seen[s.get_instance_id()] = s
		if not _seen.has(s.get_instance_id()):
			add_collision_exception_with(s)  # its capsule sits inside the hull: never pushes it
		var seat_def: Dictionary = hatches.seat_def(i, defs[i]) if hatches else defs[i]  # A4: turned out, standing in the hatch
		var t := global_transform * _seat_at(i)
		s.vehicle = self
		var f := -global_basis.z
		var veh_yaw := atan2(-f.x, -f.z)
		## "face": which way the seat faces, degrees from the vehicle's front (positive to the
		## left; a bench facing aft or outboard). Riders face it; the drawn body does even while
		## a player looks round (the seat pose turns it back by the difference).
		var face := deg_to_rad(float(seat_def.get("face", 0.0)))
		var boarding := _board_pose(s, i, t, veh_yaw + face)
		s.global_position = t.origin if boarding.is_empty() else boarding.origin
		s.velocity = Vector3.ZERO
		if s.collision_layer != 0:
			s.collision_layer = 0
		## "shown": inside the hull but in sight (a helicopter's open cabin: Captain, 2026-10-14,
		## the UH-60M's squad didn't show, only the cabin seats did).
		var open := bool(seat_def.get("open", false)) or bool(seat_def.get("shown", false))
		if s.model.visible != open:
			s.model.visible = open
			s.gear.visible = open
		if s.is_multiplayer_authority():
			# This peer drives the body: it faces the way it looks, turning with the vehicle.
			var rel := face
			if s.has_meta(&"seat_veh_yaw") and (not s.is_ai() or _door_guns.has(i)):
				rel = wrapf(s.rotation.y - float(s.get_meta(&"seat_veh_yaw")), -PI, PI)
				if StringName(seat_def.kind) != GUNNER and not (gunnery and gunnery.free_look(i)):  # (A4: the commander's viewer looks all round)
					rel = clampf(rel, -2.2, 2.2)
			if i == _gun_seat:
				rel = _gunner_look(s, rel, veh_yaw)
			s.rotation = Vector3(0, veh_yaw + rel, 0)
			s.set_meta(&"seat_veh_yaw", veh_yaw)
			var stance := Vehicle.seat_stance(String(seat_def.get("stance", "sit")))
			if s.movement.stance != stance and s.vitals.is_up():
				s.movement.stance = stance
				s.movement.mounted = false
			if s.vitals.is_up():
				s.head.position.y = SoldierMovement.STANCE_EYE[stance] if boarding.is_empty() else float(boarding.eye)
		if not boarding.is_empty():
			s.seat_pose = boarding.pose
			continue
		var seated: Dictionary = _seat_poses[i] if i < _seat_poses.size() and not (hatches and hatches.overrides(i)) else {}
		if not seated.is_empty():
			# Every peer, from the synced turn; the gun's seat turns with its gunner (and the gun).
			seated["yaw"] = 0.0 if i == _gun_seat and not _gun_remote() else wrapf(veh_yaw + face - s.rotation.y, -PI, PI)
			if seated.has("back"):
				seated["hip_z"] = float(seated.back) - CharacterModel.SEAT_BACK_OUT - _pack_off(s)
			if bool(seated.get("kneel", false)):
				_kneel_feet(seated, float(seated.deck), 0.0, s.model.left_handed)
			if _door_guns.has(i):
				_man_door_gun(i, s, seated, veh_yaw)
			if bool(seated.get("ffv", false)) and bay and s.vitals.is_up() and bay.open_fraction() < 1.0:
				var crouch := _ffv_crouch(seated, bay.open_fraction(), s.model.left_handed)
				s.seat_pose = crouch
				if s.is_multiplayer_authority():
					s.head.position.y = lerpf(float(seated.deck) + FFV_CROUCH_EYE, Vehicle.seat_eye("sit"), float(crouch.sit))
				continue
		s.seat_pose = seated
	for i: int in _door_guns:
		if occupant(i) == null or not occupant(i).vitals.is_up():
			(_door_guns[i] as DoorGun).stow()
	for id: int in _seen.keys():
		if not now_seen.has(id):
			var gone: Variant = _seen.get(id)
			if is_instance_valid(gone):
				_release(gone as Soldier)
	_seen = now_seen


# --- Physics --------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_step(delta)
		if not _running_out.is_empty():
			_step_run_outs()
	else:
		_client_follow()
		_client_turret(delta)
	_place_occupants()
	if hull:
		hull.pose_turret()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		_resolve_seats()
		_client_follow()
	_update_ropes()
	if wrecked and not _crew.is_empty() and _crew[0].visible:
		for c in _crew:
			c.visible = false
	_place_occupants()
	if hull:
		hull.pose_turret()
	_local_controls(delta)


func _server_step(delta: float) -> void:
	for i in _seat_nodes.size():
		var s := occupant(i)
		if s == null and _seat_nodes[i] != null:
			_seat_nodes[i] = null  # gone (left the session)
			_publish_state(true)
		elif s and s.is_ai() and s.vitals.is_dead() and not _bodies.has(s.get_instance_id()):
			server_exit(s)  # died aboard unseen by _on_occupant_died; loaded bodies ride on
	if not freeze:
		_drive_step(delta)
		_wake_bodies_ahead()
	_use_fuel(delta)
	if burning_s > 0.0:
		_fire_step(delta)
	_job_step()
	if not _moving.is_empty():
		_step_moves()  # A3: timed seat moves
	if bay:
		bay.server_step(delta)
	if turret and not wrecked:
		turret.step(delta)
	_pose_left -= delta
	if _pose_left <= 0.0:
		_pose_left = 1.0 / POSE_HZ
		var p := global_position
		var q := global_basis.get_rotation_quaternion()
		var v := linear_velocity
		net_pose = PackedFloat32Array([Soldier._now(), p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z,
			turret.yaw if turret else 0.0, turret.pitch if turret else 0.0])
	_state_left -= delta
	if _state_dirty and _state_left <= 0.0:
		_publish_state(true)


## The driving input in force: a player driver's latest (request_drive), else the AI
## driver's; released when nobody drives or it can't.
func _current_input() -> Dictionary:
	var d := driver()
	if d and not d.is_ai() and d.vitals.is_up():
		if Soldier._now() - float(_input.at) > INPUT_TIMEOUT_S:
			return {"throttle": 0.0, "steer": 0.0, "brake": true}
		return _input
	if is_instance_valid(ai) and ai.active and (d == null or (d.is_ai() and d.vitals.is_up())):
		return _ai_input
	return {"throttle": 0.0, "steer": 0.0, "brake": true}


## One physics step of the drive (host). Ground vehicles: suspension, tyres or tracks, engine
## and brakes. Helicopters: just their landing gear (V3 overrides this to fly).
func _drive_step(delta: float) -> void:
	var input := _current_input()
	if drive:
		if is_same(input, _ai_input):
			input = drive.ai_guard(input, delta)  # A6: the AI keeps off what would tip, sink or stop it
		drive.server_step(delta, float(input.throttle), float(input.steer))
	var throttle := clampf(float(input.throttle), -1.0, 1.0) if can_drive() else 0.0
	var steer := clampf(float(input.steer), -1.0, 1.0)
	var brake := bool(input.brake) or not can_drive()
	if logistics and logistics.towed():
		brake = false  # A8: under tow, it rolls free behind the tow bar
	if kind == HELICOPTER:
		throttle = 0.0
		brake = true
	var wet := AavWater.depth(self)  # wave 5b: in the sea on a coastal zone (V4)
	throttle = AavWater.throttle(self, wet, throttle)
	var still := linear_velocity.length() < SLEEP_SPEED and angular_velocity.length() < SLEEP_SPEED and throttle == 0.0
	_still_s = _still_s + delta if still else 0.0
	if _still_s > SLEEP_S and brake and wet <= 0.0:
		if not sleeping:
			sleeping = true
		return
	if sleeping:
		if throttle == 0.0 and steer == 0.0 and brake:
			return
		sleeping = false
	_wheel_forces(delta, throttle, steer, brake)
	if drive:
		apply_central_force(drive.aero_force())  # A6: air drag
	if wet > 0.0:
		AavWater.step(self, delta, wet, throttle, steer, brake)  # buoyancy, drag, waterjets


## Suspension, grip, drive and brakes at each wheel (host).
func _wheel_forces(delta: float, throttle: float, steer: float, brake: bool) -> void:
	var wheels: Array = spec.get("wheels", [])
	if wheels.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var up := global_basis.y
	var forward := -global_basis.z
	var com := global_transform * center_of_mass
	var n := float(wheels.size())
	var tracked := kind == TRACKED
	var sag := SAG_TRACKED if tracked else SAG_WHEELED
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var share := mass / n
	var k := share * g / sag
	var c := 2.0 * DAMPING_RATIO * sqrt(k * share)
	var v_fwd := linear_velocity.dot(forward)
	# Rolling against the motion brakes first, then reverses.
	if throttle != 0.0 and signf(throttle) != signf(v_fwd) and absf(v_fwd) > REVERSE_BRAKE_MS:
		brake = true
		throttle = 0.0
	# A6 (2.8.1-2.8.2): the ground's traction and rolling resistance; the engine's power over the
	# speed pulls, no more than accel_ms2 net (the old CLIMB_DEG grade hold is gone: power and
	# traction decide whether it climbs), the governor easing it off at top speed.
	var mu := drive.traction_now() if drive else 1.0
	var rr := drive.rolling_now() if drive else ROLL_DECEL / g
	var pull := 0.0
	if throttle != 0.0:
		var top := top_speed(throttle < 0.0)
		var curve := sqrt(clampf(1.0 - absf(v_fwd) / maxf(top, 0.1), 0.0, 1.0))
		var accel_mult := logistics.accel_mult() if logistics else 1.0  # A8: the packages' weight
		var power := drive.power_now() if drive else VehicleDrive.power_w(spec)
		var train := mass + (logistics.towing.mass if logistics and logistics.towing_one() else 0.0)  # (and what it tows: it holds the grade for both)
		pull = signf(throttle) * curve * accel_mult * VehicleDrive.drive_force(power, train, v_fwd, rr, forward.y * signf(throttle), float(spec.get("accel_ms2", 2.0)), throttle)
	var brake_force := mass * float(spec.get("brake_ms2", 6.0)) if brake else 0.0
	var wheels_ok := zone_health(ZONE_WHEELS)
	var grip := GRIP * mu * (lerpf(0.55, 1.0, wheels_ok) if wheels_ok > 0.0 else 0.4)
	var steer_angle := 0.0
	if not tracked:
		steer_angle = -steer * deg_to_rad(float(spec.get("steer_deg", 30.0))) / (1.0 + absf(v_fwd) / STEER_FALLOFF_MS)
	var engine_brake := ENGINE_BRAKE if throttle == 0.0 else 0.0
	var grounded := 0
	for w: Array in wheels:
		var r := float(w[2])
		var top_point := global_transform * Vector3(float(w[0]), r + TRAVEL, float(w[1]))
		var reach := TRAVEL + r + sag + DROOP
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top_point, top_point - up * reach, GROUND_MASK, [get_rid()]))
		if hit.is_empty():
			continue
		grounded += 1
		var point: Vector3 = hit.position
		var compression := (TRAVEL + r + sag) - top_point.distance_to(point)
		var v_point := linear_velocity + angular_velocity.cross(point - com)
		var normal_force := maxf(k * compression - c * v_point.dot(up), 0.0)
		var f_dir := forward
		if bool(w[3]) and steer_angle != 0.0:
			f_dir = forward.rotated(up, steer_angle)
		var s_dir := up.cross(f_dir).normalized()
		var v_long := v_point.dot(f_dir)
		var v_lat := v_point.dot(s_dir)
		var f_lat := -v_lat * share / delta * LATERAL_RESPONSE
		if tracked and absf(steer) > 0.05:
			f_lat *= TRACK_TURN_LATERAL
		var f_long := pull / n
		if brake_force > 0.0:
			f_long += clampf(-v_long * share / delta, -brake_force / n, brake_force / n)
		elif engine_brake > 0.0:
			f_long += clampf(-v_long * share / delta, -engine_brake * share, engine_brake * share)
		var traction := f_dir * f_long + s_dir * f_lat
		var limit := normal_force * grip
		if traction.length() > limit:
			traction = traction.normalized() * limit
		# A6: the ground's rolling resistance (the tyres or tracks sinking in, not their grip: it
		# comes on top of what the grip allows, so soft ground can hold a vehicle that grips).
		var rolling := -clampf(v_long * share / delta, -rr * normal_force, rr * normal_force)
		apply_force(up * normal_force + traction + f_dir * rolling, point - global_position)
	if tracked and grounded > 0 and not (logistics and logistics.towed()):
		# Skid steering: the hull turns at the commanded rate, on the spot or on the move. (A6, 2.8.3:
		# neutral steer at a standstill, falling to half by half_rate_kmh, by the ground's traction.)
		var size := VehicleArt.size_m(model)
		var turn_share := VehicleDrive.turn_share(drive.ground()) if drive else 1.0
		var inertia := mass * (size.x * size.x + size.z * size.z) / 12.0
		var fall := 1.0 + absf(v_fwd) / (VehicleDrive.num("tracked", "half_rate_kmh", 30.0) * VehicleSpecs.KMH) if drive else 1.0
		var target := -steer * deg_to_rad(float(spec.get("turn_deg_s", 40.0))) * (lerpf(0.4, 1.0, zone_health(ZONE_ENGINE)) if can_drive() else 0.0) * turn_share / fall
		var yaw_rate := angular_velocity.dot(up)
		var torque := clampf((target - yaw_rate) * inertia / TRACK_TURN_TIME_S, -mass * g * size.z * 0.25 * turn_share, mass * g * size.z * 0.25 * turn_share)
		apply_torque(up * torque * (float(grounded) / n))


## Host: wakes settled ragdolls just ahead of the hull while it moves or is driven (a body it
## has stopped against too), and runs over soldiers in its path.
var _wake_query: PhysicsShapeQueryParameters3D


func _wake_bodies_ahead() -> void:
	var speed := linear_velocity.length()
	var pushing := can_drive() and absf(float(_current_input().throttle)) > 0.0
	_ride_over(speed, pushing)
	if speed < 0.5 and not pushing:
		return
	var size := VehicleArt.size_m(model)
	var ahead := speed * RAGDOLL_LOOKAHEAD_S + RAGDOLL_MARGIN_M
	if _wake_query == null:  # (perf pass: one shape and query a vehicle, not a new pair every tick)
		_wake_query = PhysicsShapeQueryParameters3D.new()
		_wake_query.shape = BoxShape3D.new()
	var box := _wake_query.shape as BoxShape3D
	box.size = Vector3(size.x + RAGDOLL_MARGIN_M * 2.0, maxf(size.y, 1.0), size.z + ahead * 2.0)
	var q := _wake_query
	q.shape = box
	q.transform = Transform3D(global_basis, global_transform * Vector3(0, size.y * 0.5, 0))
	q.collision_mask = Ragdoll.LAYER | Soldier.BODY_LAYER
	var exclude: Array[RID] = [get_rid()]
	q.exclude = exclude
	var dir := linear_velocity.normalized() if speed >= 0.5 else -global_basis.z * signf(float(_current_input().throttle))
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var collider: Object = hit.get("collider")
		var lying := Ragdoll.body_of(collider)
		if lying:
			if is_instance_valid(lying.ragdoll) and lying.ragdoll.frozen:
				lying.ragdoll.unfreeze()
			continue
		var s := collider as Soldier
		if s == null or seat_of(s) >= 0 or Vehicle.ride_of(s) != null or not s.vitals.is_up():
			continue
		var local := to_local(s.global_position)
		if local.y > size.y - 0.3:
			continue  # standing on the roof or the deck: it carries them
		var along := (s.global_position - global_position).dot(dir)
		if along >= size.z * 0.3:
			_run_over(s, speed)  # in its path: hit at speed
		if s.vitals.is_up() and along > -size.z * 0.5:  # not one it's pulling away from
			_push_aside(s, local, size, maxf(speed, 0.5))


## Host: `s` (at `local` in the vehicle's frame) is in the hull's way or inside its footprint:
## pushed out sideways (toward the side it's nearer) until clear of the hull, at a walk or the
## vehicle's speed. Slow vehicles shove soldiers aside instead of driving through them.
func _push_aside(s: Soldier, local: Vector3, size: Vector3, speed: float) -> void:
	var half_x := size.x * 0.5 + PUSH_CLEAR_M
	var half_z := size.z * 0.5 + PUSH_CLEAR_M
	if absf(local.x) >= half_x or absf(local.z) >= half_z + speed * RAGDOLL_LOOKAHEAD_S:
		return  # clear of it
	var side := signf(local.x) if absf(local.x) > 0.05 else (1.0 if s.get_instance_id() % 2 == 0 else -1.0)
	var need := half_x - absf(local.x)
	var rate := maxf(PUSH_MIN_MS, speed * PUSH_SPEED_MULT)
	var axis := global_basis.x * side
	axis = Vector3(axis.x, 0.0, axis.z).normalized()
	if s.is_ai():
		Vehicle.shove(s, axis * minf(need, rate * get_physics_process_delta_time()))
		return
	var now := Soldier._now()
	if now - float(_pushed_at.get(s.get_instance_id(), -100.0)) < PUSH_SEND_S:
		return
	_pushed_at[s.get_instance_id()] = now
	var lvl := level()
	if lvl:
		_client_push.rpc_id(s.owner_peer(), lvl.get_path_to(s), axis * minf(need, rate * PUSH_SEND_S))


## The owner of a player in a vehicle's way moves them aside by `offset` (their position is
## theirs to send).
@rpc("authority", "call_local", "unreliable_ordered")
func _client_push(path: NodePath, offset: Vector3) -> void:
	var lvl := level()
	var s := lvl.get_node_or_null(path) as Soldier if lvl else null
	if s and s.is_multiplayer_authority() and not is_instance_valid(s.vehicle):
		Vehicle.shove(s, offset)


## Moves `s` by `offset` unless a wall (the world) is in the way.
static func shove(s: Soldier, offset: Vector3) -> void:
	var from := s.global_position + Vector3.UP * 0.9
	var reach := offset.length() + 0.35
	if reach <= 0.35:
		return
	var q := PhysicsRayQueryParameters3D.create(from, from + offset.normalized() * reach, 1, [s.get_rid()])
	if s.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		s.global_position += offset


## Host: `s` was hit by the vehicle at `speed` m/s: blunt trauma through the wound model.
func _run_over(s: Soldier, speed: float) -> void:
	if speed < RUN_OVER_MIN_MS:
		return
	var now := Soldier._now()
	if now - float(_run_over_at.get(s.get_instance_id(), -100.0)) < RUN_OVER_COOLDOWN_S:
		return
	_run_over_at[s.get_instance_id()] = now
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	Harm.note_hit(s, driver())
	s.vitals.server_damage((speed - RUN_OVER_MIN_MS) * RUN_OVER_TRAUMA)
	s.vitals.server_fall(speed * speed / (2.0 * g) * RUN_OVER_FALL_MULT)
	BlastGore.server_vehicle_hit(s, global_position, speed)  # hit hard: the side it hit torn
	if s.is_ai() and s.vitals.is_up():
		var side := global_basis.x * signf((s.global_position - global_position).dot(global_basis.x) + 0.001)
		s.global_position += side * 0.8  # thrown aside
	if not s.vitals.is_up():
		Vehicle._fling(s, linear_velocity, speed, 6)  # down: thrown with the vehicle (its ragdoll may start next frame)


## Host: a body wedged under the chassis that holds a driven vehicle still is driven over (its
## parts stop meeting the hull for a while), and those exceptions end once it's clear.
func _ride_over(speed: float, pushing: bool) -> void:
	var now := Soldier._now()
	var half := VehicleArt.size_m(model) * 0.5 + Vector3.ONE * 0.6
	for part: Variant in _ridden.keys():
		if not is_instance_valid(part):
			_ridden.erase(part)
			continue
		var at := to_local((part as Node3D).global_position)
		if now > float(_ridden[part]) and (absf(at.x) > half.x or absf(at.z) > half.z):  # clear of the hull: it meets it again
			remove_collision_exception_with(part as Node)
			_ridden.erase(part)
	var wedged: Array = []
	if pushing and speed < 0.3:
		for b in get_colliding_bodies():
			if Ragdoll.body_of(b) != null:
				wedged.append(b)
	if speed >= RUN_OVER_MIN_MS:
		for b in get_colliding_bodies():
			if Ragdoll.body_of(b) != null and not _ridden.has(b) and to_local((b as Node3D).global_position).y < BUMPER_M:
				add_collision_exception_with(b)  # under the bumper at speed: over it, not stopped by it
				_ridden[b] = now + RIDE_OVER_S
				BlastGore.server_crush(Ragdoll.body_of(b), String((b as Node).name), mass, speed)  # crushed where it rolls over
	_blocked_s = _blocked_s + get_physics_process_delta_time() if not wedged.is_empty() else 0.0
	if _blocked_s < RIDE_OVER_AFTER_S:
		return
	_blocked_s = 0.0
	for b: Node in wedged:
		var lying := Ragdoll.body_of(b)
		if lying and is_instance_valid(lying.ragdoll):
			for part: Node in lying.ragdoll.parts.values():
				add_collision_exception_with(part)
				_ridden[part] = now + RIDE_OVER_S


## A downed or dead `s` thrown by a vehicle moving at `velocity`: every ragdoll part gets the
## vehicle's velocity (a bit more) and a lift. The ragdoll may not have started yet: it tries
## again a few times a moment apart.
static func _fling(s: Soldier, velocity: Vector3, speed: float, tries: int) -> void:
	if not is_instance_valid(s) or not s.is_inside_tree():
		return
	if not is_instance_valid(s.ragdoll):
		if tries > 0:
			s.get_tree().create_timer(0.05).timeout.connect(Vehicle._fling.bind(s, velocity, speed, tries - 1))
		return
	if s.ragdoll.frozen:
		s.ragdoll.unfreeze()
	for part: Variant in s.ragdoll.parts.values():
		var rb := part as RigidBody3D
		if rb:
			rb.linear_velocity = velocity * FLING_FORWARD + Vector3.UP * speed * FLING_UP + Vector3(randf() - 0.5, randf() * 0.3, randf() - 0.5) * 0.6

func _on_body_entered(body: Node) -> void:
	var lying := Ragdoll.body_of(body)
	if lying and is_instance_valid(lying.ragdoll) and lying.ragdoll.frozen:
		lying.ragdoll.unfreeze()


## Host: fuel burned by distance driven and by an engine idling with a driver aboard, and a
## leaking tank.
func _use_fuel(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	if fuel <= 0.0:
		return
	var used := moved / 1000.0 * float(spec.get("fuel_l_per_km", 0.5)) * (logistics.fuel_mult() if logistics else 1.0)  # A8: the packages' weight
	if driver() != null or (is_instance_valid(ai) and ai.active):
		used += float(spec.get("idle_l_per_h", 1.0)) / 3600.0 * delta
	used += _leak * delta
	if used > 0.0:
		fuel = maxf(fuel - used, 0.0)
		_state_dirty = true


# --- Clients: following the host --------------------------------------------------------------

func _push_snapshot(pose: PackedFloat32Array) -> void:
	if pose.size() < 11:
		return
	var now := Soldier._now()
	var t := pose[0]
	var offset := now - t
	_clock = offset if offset < _clock else lerpf(_clock, offset, 0.02)
	if not _snaps.is_empty() and t <= float(_snaps[-1][0]):
		return
	_snaps.append([t, Vector3(pose[1], pose[2], pose[3]), Quaternion(pose[4], pose[5], pose[6], pose[7]).normalized(), Vector3(pose[8], pose[9], pose[10]),
		Vector2(pose[11], pose[12]) if pose.size() >= 13 else Vector2.ZERO])
	while _snaps.size() > 30:
		_snaps.pop_front()


func _client_follow() -> void:
	if _snaps.is_empty():
		return
	var render_t := Soldier._now() - _clock - INTERP_DELAY_S
	var p: Vector3
	var q: Quaternion
	var aim: Vector2  # the turret's (yaw, pitch)
	if render_t <= float(_snaps[0][0]):
		p = _snaps[0][1]
		q = _snaps[0][2]
		aim = _snaps[0][4]
	else:
		var last: Array = _snaps[-1]
		if render_t >= float(last[0]):
			var ahead := minf(render_t - float(last[0]), EXTRAPOLATE_MAX_S)
			p = (last[1] as Vector3) + (last[3] as Vector3) * ahead
			q = last[2]
			aim = last[4]
		else:
			for i in range(_snaps.size() - 1):
				var a: Array = _snaps[i]
				var b: Array = _snaps[i + 1]
				if render_t >= float(a[0]) and render_t <= float(b[0]):
					var w := (render_t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
					p = (a[1] as Vector3).lerp(b[1], w)
					q = (a[2] as Quaternion).slerp(b[2], w)
					var ya: Vector2 = a[4]
					var yb: Vector2 = b[4]
					aim = Vector2(lerp_angle(ya.x, yb.x, w), lerpf(ya.y, yb.y, w))
					break
	global_transform = Transform3D(Basis(q), p)
	if turret and _local_gunner() == null:
		turret.yaw = aim.x  # someone else's gun (or nobody's): as the host has it
		turret.pitch = aim.y
		turret.target_yaw = aim.x
		turret.target_pitch = aim.y


## Clients: the local gunner's own turret turns here at once (towards what they ask the host
## for; the host turns its own the same way a moment later), and their aim goes to the host.
func _client_turret(delta: float) -> void:
	if turret == null or wrecked or _local_gunner() == null:
		return
	turret.step(delta)
	_aim_send_left -= delta
	var want := Vector2(turret.target_yaw, turret.target_pitch)
	if want != _aim_sent or _aim_send_left <= 0.0:
		_aim_sent = want
		_aim_send_left = 0.1
		request_aim.rpc_id(1, want.x, want.y)


## Clients: the replicated state applied (seats, wreck, fire).
func _apply_state() -> void:
	var seats_in: Array = net_state.get("seats", [])
	var lvl := level() if is_inside_tree() else null
	for i in _seat_nodes.size():
		var path := String(seats_in[i]) if i < seats_in.size() else ""
		_seat_nodes[i] = lvl.get_node_or_null(NodePath(path)) if lvl and path != "" else null
	if bay:
		bay.set_open(bool(net_state.get("bay", false)))
	var was := wrecked
	wrecked = bool(net_state.get("wrecked", false))
	if hull and wrecked != was:
		hull.set_wrecked(wrecked)
	seats_changed.emit()


func _resolve_seats() -> void:
	if multiplayer.is_server():
		return
	var seats_in: Array = net_state.get("seats", [])
	var lvl := level()
	if lvl == null:
		return
	for i in mini(_seat_nodes.size(), seats_in.size()):
		if String(seats_in[i]) != "" and not is_instance_valid(_seat_nodes[i]):
			_seat_nodes[i] = lvl.get_node_or_null(NodePath(String(seats_in[i])))


## Host: everything shared goes out (seats always; fuel and fire time at most every STATE_MIN_S).
func _publish_state(now := false) -> void:
	if not now:
		_state_dirty = true
		return
	_state_dirty = false
	_state_left = STATE_MIN_S
	var seats_out: Array = []
	var lvl := level() if is_inside_tree() else null
	for i in _seat_nodes.size():
		var s := occupant(i)
		seats_out.append(String(lvl.get_path_to(s)) if s and lvl else "")
	var zones_out := {}
	for z: StringName in _zones:
		zones_out[String(z)] = snappedf(float(_zones[z]), 0.001)
	net_state = {"seats": seats_out, "zones": zones_out, "fuel": snappedf(fuel, 0.1), "burning": snappedf(burning_s, 0.1),
		"wrecked": wrecked, "battery": battery_ok, "salvaged": salvaged, "lost": _lost, "bay": bay != null and bay.open, "ropes": ropes_out,
		"speed": snappedf(linear_velocity.dot(-global_basis.z), 0.1) if is_inside_tree() else 0.0}


# --- Damage (host) ----------------------------------------------------------------------------

## Host: a hit on this vehicle. `hit` holds at least "kind" (one of the kinds above),
## "position" and "direction" (world space), and "shooter" (a node or null); kinetic hits add
## "round" (the rounds.json id), "energy_j" and "level" (Ballistics.LEVELS); launcher hits
## add "penetration_mm" and "blast_kg" (TNT equivalent). Optional "probe_m": how far past
## "position" to look for the hull's voxels (PROBE_M).
## Returns {"stopped": bool, "zone": StringName, "penetrated": bool} plus "missed" (a round or
## jet that met only the collision box, not the hull's voxels: the caller carries on through),
## "position" (where it met the hull), "energy_left" (a kinetic round's, if it goes on) and
## "lost_j". A round that isn't stopped flies on into the cabin (the caller carries on with it,
## e.g. into the crew's hitboxes).
func server_take_hit(hit: Dictionary) -> Dictionary:
	var pos: Vector3 = hit.get("position", global_position)
	var out := {"stopped": true, "zone": ZONE_HULL, "penetrated": false, "missed": false, "position": pos, "energy_left": 0.0, "lost_j": 0.0}
	if not multiplayer.is_server():
		return out
	var hit_kind := StringName(hit.get("kind", KINETIC))
	var dir: Vector3 = hit.get("direction", Vector3.ZERO)
	if dir.length_squared() < 0.0001:
		dir = (global_transform * center_of_mass - pos).normalized() if not pos.is_equal_approx(global_position) else Vector3.DOWN
	var local := to_local(pos)
	var ldir := (global_basis.inverse() * dir.normalized()).normalized()
	var on_part := false  # met the turret or its gun (they turn: no marks drawn on them)
	if hit_kind == KINETIC or hit_kind in VehicleDamage.KINDS_HEAT:
		# Rounds and jets meet the hull's voxels, not just its boxes: through an open pickup bed,
		# over a door's window frame, past a turret's open back.
		var found := hull.first_solid(local, ldir, float(hit.get("probe_m", PROBE_M)))
		if not found.hit:
			out.stopped = false
			out.missed = true
			out.energy_left = float(hit.get("energy_j", 0.0))
			return out
		local = found.local
		on_part = String(found.get("part", "")) != ""
		out.position = to_global(local)
	var zone := VehicleDamage.zone_at(spec, local)
	# Combined arms A1: a model with armour plates resolves rounds that have vehicle numbers
	# through ArmourModel (angle, plate, tiles, fuze); the rest as before (VehicleDamage).
	var res := ArmourModel.vehicle_hit(self, hit, zone, local, ldir) if spec.has("plates") else VehicleDamage.resolve(hit, zone, ldir)
	if res.has("armour"):
		out.armour = res.armour  # the HitResult (the x-ray's, phase A5)
	out.zone = zone.zone
	out.penetrated = res.penetrated
	out.stopped = res.stopped
	out.energy_left = res.energy_left
	out.lost_j = maxf(float(hit.get("energy_j", 0.0)) - float(res.energy_left), 0.0)
	out.traced = bool(res.get("traced", false))  # A2: the modules took the jet's path (Warheads skips its own)
	if not on_part:
		_carve_for(hit_kind, res, local, hit)
	if not wrecked:
		_apply_damage(zone, res, out.position, hit)
	if drive:
		drive.server_hit(out)  # A6: holed under an amphibious hull's waterline
	damaged.emit(zone.zone, hit)
	return out


## Whether a fragment (Throwables) that met this vehicle's collision box at `at`, flying on to
## `to`, meets the hull's voxels on the way: an open pickup bed or a gunner's hatch lets it by,
## as it does a round (server_take_hit's probe).
func blocks_fragment(at: Vector3, to: Vector3) -> bool:
	var dir := to - at
	if dir.length_squared() < 0.000001:
		return true
	var reach := minf(dir.length(), VehicleArt.size_m(model).length())
	return bool(hull.first_solid(to_local(at), (global_basis.inverse() * dir.normalized()).normalized(), reach).hit)


## Host: a charge that rode this vehicle went off at `pos` (Charges' hook): a 2 kg block's blast.
func server_explosion(pos: Vector3, _kind: String = "") -> void:
	server_take_hit({"kind": HE, "position": pos, "direction": (global_transform * center_of_mass - pos).normalized(), "blast_kg": 2.0, "shooter": null})


func _carve_for(hit_kind: StringName, res: Dictionary, local: Vector3, hit: Dictionary) -> void:
	var ops: Array = []
	match hit_kind:
		KINETIC:
			if res.penetrated:
				ops.append([local.x, local.y, local.z, 0.0, VehicleHull.HOLE])
			else:
				ops.append([local.x, local.y, local.z, 0.0, VehicleHull.SCUFF])
		HEAT, TANDEM_HEAT, TOP_ATTACK:
			ops.append([local.x, local.y, local.z, 0.3, VehicleHull.SCORCH])
			if res.penetrated:
				ops.append([local.x, local.y, local.z, 0.06, VehicleHull.HOLE])
		_:
			var r := clampf(0.2 + float(hit.get("blast_kg", 0.5)) * 0.15, 0.2, 0.9)
			ops.append([local.x, local.y, local.z, r, VehicleHull.SCORCH])
			if res.penetrated:
				ops.append([local.x, local.y, local.z, 0.05, VehicleHull.HOLE])
	_add_carves(ops)


func _add_carves(ops: Array) -> void:
	if ops.is_empty() or net_carves.size() >= MAX_CARVES:
		return
	var rounded: Array = []
	for op: Array in ops:
		rounded.append([snappedf(op[0], 0.001), snappedf(op[1], 0.001), snappedf(op[2], 0.001), op[3], op[4]])
	net_carves = net_carves + rounded


func _apply_damage(zone: Dictionary, res: Dictionary, at: Vector3, hit: Dictionary) -> void:
	if modules and modules.authored:
		modules.server_apply(zone, res, at, hit)  # A2: modules, spall cone, crew, kill states
		return
	var dmg := float(res.damage_kj) * damage_mult
	if dmg > 0.0:
		var z: StringName = zone.zone
		_zones[z] = maxf(float(_zones.get(z, 1.0)) - dmg / maxf(float(zone.hp_kj), 0.1), 0.0)
		if z != ZONE_HULL:
			var hull_hp := float(spec.get("hp", {}).get("hull", 100.0))
			_zones[ZONE_HULL] = maxf(float(_zones[ZONE_HULL]) - dmg * VehicleDamage.HULL_SHARE / hull_hp, 0.0)
		if z == ZONE_ENGINE and res.penetrated and randf() < BATTERY_KILL_CHANCE:
			battery_ok = false
		if z == ZONE_FUEL and res.penetrated:
			_leak += LEAK_LPS * clampf(dmg / maxf(float(zone.hp_kj), 0.1), 0.05, 1.0)
		if Vehicle.fire_rolls and float(res.fire_chance) > 0.0 and randf() < float(res.fire_chance):
			server_start_fire()
	if res.spall:
		_spall(at, hit.get("shooter"))
	if float(res.crew_blast) > 0.0:
		for s: Soldier in occupants():
			s.vitals.server_blast(lerpf(WoundModel.BLAST_RADIUS, 0.5, float(res.crew_blast)), WoundModel.BLAST_RADIUS)
	if float(_zones[ZONE_HULL]) <= 0.0:
		_destroy()
	_publish_state(true)


static func _random_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


## Host: a jet through the armour throws spall at everyone near its hole inside: fragment
## wounds through the wound model (3 to 6 each, closer more).
func _spall(at: Vector3, shooter: Variant) -> void:
	for s: Soldier in occupants():
		var d := at.distance_to(s.global_position + Vector3.UP * 0.9)
		if d > VehicleDamage.SPALL_RADIUS_M or s.vitals.is_dead():
			continue
		var n := clampi(roundi(lerpf(6.0, 3.0, d / VehicleDamage.SPALL_RADIUS_M)), 3, 6)
		Harm.note_hit(s, shooter as Node if is_instance_valid(shooter) else null)
		for i in n:
			var part: StringName = SPALL_PARTS[spall_rng.randi() % SPALL_PARTS.size()]
			s.vitals.server_hit(part, {"round_class": Vitals.FRAGMENT, "superficial": i > 0})


func _destroy() -> void:
	if _lost and burning_s > 0.0:
		return
	server_start_fire()


## Host: sets it on fire (a fuel hit, a destroyed hull, a test). It burns FIRE_S, then it's a
## wreck. The vehicle counts as lost from now (destroyed).
func server_start_fire(seconds := FIRE_S) -> void:
	if not multiplayer.is_server() or wrecked or burning_s > 0.0:
		return
	burning_s = seconds
	_fire_tick = 0.0
	if not _lost:
		_lost = true
		destroyed.emit(self)
	_add_carves([[0.0, VehicleArt.size_m(model).y * 0.5, 0.0, 0.6, VehicleHull.SCORCH]])
	_publish_state(true)


func _fire_step(delta: float) -> void:
	burning_s = maxf(burning_s - delta, 0.0)
	_fire_tick -= delta
	_state_dirty = true
	if _fire_tick <= 0.0:
		_fire_tick = FIRE_TICK_S
		for s: Soldier in occupants():
			if s.vitals.is_dead():
				continue
			s.vitals.server_burn(FIRE_BURN_SHARE)
			s.vitals.server_damage(FIRE_TRAUMA)
		_fire_ticks += 1
		if _fire_ticks % FIRE_SCORCH_EVERY == 1:
			var size := VehicleArt.size_m(model)
			var spot := Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(0.3, 0.9) * size.y, randf_range(-0.4, 0.4) * size.z)
			_add_carves([[spot.x, spot.y, spot.z, FIRE_SCORCH_M, VehicleHull.SCORCH]])
	if burning_s <= 0.0:
		_become_wreck()


## Host: the fire burned out. Whoever is still aboard dies, the cargo is gone, and it's a
## blackened, immobile wreck (saved with the zone, lootable for parts).
func _become_wreck() -> void:
	burning_s = 0.0
	wrecked = true
	_leak = 0.0
	for s: Soldier in occupants():
		if not s.vitals.is_dead():
			Harm.note_hit(s, null)
			s.vitals.server_kill()
	for s: Soldier in occupants():
		if seat_of(s) >= 0:
			server_exit(s)
	if cargo_hold:
		cargo_hold.clear_all()
	for z: StringName in _zones:
		_zones[z] = 0.0
	modules.server_wrecked()
	if is_instance_valid(ai):
		ai.stop()
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	hull.set_wrecked(true)
	var size := VehicleArt.size_m(model)
	_add_carves([[0.0, size.y * 0.6, -size.z * 0.25, 0.9, VehicleHull.SCORCH], [0.0, size.y * 0.6, size.z * 0.25, 0.9, VehicleHull.SCORCH]])
	_publish_state(true)
	became_wreck.emit(self)


# --- Fire on every peer -------------------------------------------------------------------------
# The fire's look is VehicleFx's (A7: the stages, the column, the flames, the burning wreck), from
# VehicleFire's state; it replaced the one light and orange sphere that were drawn here.


# --- AI driving (host) --------------------------------------------------------------------------

## Host: the AI drives to `point` (a navmesh path where there is one, else straight), stops
## there and avoids obvious obstacles. A player in the driver's seat keeps control.
## `speed_kmh` -1: its usual cruise (VehicleAI.CRUISE_SHARE of top speed).
func server_drive_to(point: Vector3, speed_kmh := -1.0) -> void:
	_ensure_ai()
	ai.drive_to(point, speed_kmh / 3.6 if speed_kmh > 0.0 else -1.0)


## Host: the AI follows `points` in order and stops at the last (`speed_kmh` as above).
func server_follow_path(points: PackedVector3Array, speed_kmh := -1.0) -> void:
	_ensure_ai()
	ai.follow(points, speed_kmh / 3.6 if speed_kmh > 0.0 else -1.0)


## Host: the AI stops and holds the brakes.
func server_stop() -> void:
	if is_instance_valid(ai):
		ai.stop()


func _ensure_ai() -> void:
	if not is_instance_valid(ai):
		ai = VehicleAI.new(self)
		add_child(ai)


## Host: VehicleAI's controls for this step.
func set_ai_input(throttle: float, steer: float, brake: bool) -> void:
	_ai_input = {"throttle": throttle, "steer": steer, "brake": brake}


# --- Requests from players (any peer -> host) ---------------------------------------------------

## The player who sent the RPC being handled (the host's own for a local call), or null.
func _sender() -> Soldier:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	var lvl := level()
	return lvl.players.get_node_or_null(str(id)) as Soldier if lvl else null


## Whether `actor` is close enough to one of this vehicle's action points to use it.
func in_reach(actor: Node3D) -> bool:
	if actor == null:
		return false
	if bay and bay.inside(actor):
		return true  # standing in the bay: every seat is in reach
	for p in get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind != VehicleActionPoint.SEAT \
				and actor.global_position.distance_to((p as Node3D).global_position) <= USE_REACH_M:
			return true
	return false


## The driver's controls (sent every few frames while they change, and as a keep-alive).
@rpc("any_peer", "call_local", "unreliable_ordered")
func request_drive(throttle: float, steer: float, brake: bool) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor == null or driver() != actor or not actor.vitals.is_up() or not is_finite(throttle) or not is_finite(steer):
		return
	_input = {"throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "brake": brake, "at": Soldier._now()}
	if (throttle != 0.0 or steer != 0.0) and sleeping:
		sleeping = false


@rpc("any_peer", "call_local", "reliable")
func request_enter(index: int) -> void:
	var actor := _sender()
	if multiplayer.is_server() and actor and actor.vitals.is_up() and in_reach(actor) and Vehicle.ride_of(actor) == null:
		if not server_enter(actor, index):
			_tell(actor, "Can't get in there")


## A mortar laid and fired by hand (G-25 part d, MortarPanel): bearing (degrees from north),
## charge and elevation (mils) give where the round lands (MortarTable, the panel's numbers); one
## round from the hold or the actor's kit.
@rpc("any_peer", "call_local", "reliable")
func request_mortar_fire(bearing_deg: float, charge: int, mils: float) -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not actor.vitals.is_up() or not in_reach(actor):
		return
	var m := MortarFire.spec_of(self)
	if m.is_empty():
		return
	var r := MortarTable.range_m(m, charge, clampf(mils, MortarTable.ELEVATION_MILS.x, MortarTable.ELEVATION_MILS.y))
	var at := global_position + MortarTable.bearing_dir(bearing_deg) * r
	if not MortarFire.in_range(self, at):
		_tell(actor, "Out of its range at that charge and elevation (%d m)" % roundi(r))
		return
	var round_id := StringName(m.get("round", ""))
	var from_hold := cargo_hold != null and cargo_hold.feed_rounds(round_id) > 0
	if not from_hold and actor.inventory.count_of(round_id) <= 0:
		_tell(actor, "No rounds: load %s into the mortar or carry them" % ItemDB.get_item(round_id).name)
		return
	var mf := MortarFire.of(self)
	if mf == null or mf.server_fire(self, at, 0.0, actor) < 0.0:
		return
	if from_hold:
		cargo_hold.take_feed(round_id)
	else:
		actor.inventory.remove_one(round_id)


## A static weapon's "Pack up the gun" (G-25, StaticWeapons): the host starts it.
@rpc("any_peer", "call_local", "reliable")
func request_pack() -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not in_reach(actor):
		return
	var sw := StaticWeapons.of(self)
	var why := sw.server_start_pack(actor, self) if sw else "Not here"
	if why != "":
		_tell(actor, why)


@rpc("any_peer", "call_local", "reliable")
func request_exit() -> void:
	var actor := _sender()
	if multiplayer.is_server() and actor and seat_of(actor) >= 0:
		if AavWater.afloat(self) and not is_burning():
			_tell(actor, "Not in open water")  # wave 5b: an AAV swimming
			return
		server_exit(actor)


@rpc("any_peer", "call_local", "reliable")
func request_switch(index: int) -> void:
	var actor := _sender()
	if multiplayer.is_server() and actor and actor.vitals.is_up() and seat_of(actor) >= 0:
		if not server_switch(actor, index):
			_tell(actor, "That seat is taken")


## A player carrying or dragging a body loads it into seat `index` (-1: any passenger seat).
@rpc("any_peer", "call_local", "reliable")
func request_load_body(index: int) -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not actor.vitals.is_up() or not in_reach(actor):
		return
	var body := actor.carrying
	if body == null:
		return
	actor.release_carried()
	if not server_enter(body, index):
		_tell(actor, "No free seat")


## A player pulls a body (down or dead) out of seat `index`.
@rpc("any_peer", "call_local", "reliable")
func request_pull_out(index: int) -> void:
	var actor := _sender()
	var s := occupant(index)
	if multiplayer.is_server() and actor and actor.vitals.is_up() and in_reach(actor) and s and not s.vitals.is_up():
		server_exit(s)


## A player puts one stowed entry (their container, index, the item id the host checks) in the
## hold; with `container` &"" the two-handed item in their hands.
@rpc("any_peer", "call_local", "reliable")
func request_cargo_load(container: StringName, index: int, id: StringName) -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not actor.vitals.is_up() or not in_reach(actor) or cargo() == null or wrecked:
		return
	_tell(actor, server_load(actor, container, index, id))


## Host: moves one of `actor`'s entries into the hold. Returns what to tell them.
func server_load(actor: Soldier, container: StringName, index: int, id: StringName) -> String:
	var inv := actor.inventory
	if container == &"":
		if inv.hands != id or id == &"":
			return ""
		if cargo_hold.take(id) <= 0:
			return "No room in the %s" % display_name()
		inv.release_hands()
		return "Loaded %s" % ItemDB.get_item(id).name
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size() or list[index].id != id:
		return ""
	var entry: Dictionary = list[index]
	var item := ItemDB.get_item(id)
	var n := mini(cargo_hold.room_for(VehicleCargo.HOLD, item, entry.get("state", {})), int(entry.count))
	if n <= 0:
		return "No room in the %s (%.0f of %.0f L, %.0f of %.0f kg)" % [display_name(), cargo_hold.used_litres(), cargo_hold.capacity_l, cargo_hold.total_mass(), cargo_hold.max_kg]
	var moved := inv.remove_entry(container, index, n)
	cargo_hold.take(moved.id, int(moved.count), moved.get("state", {}))
	return "Loaded %s%s" % [item.name, " x%d" % n if n > 1 else ""]


## A player takes one entry out of the hold (its index and the item id the host checks): into
## their kit if it fits, their hands for a two-handed one, else on the ground by the cargo point.
@rpc("any_peer", "call_local", "reliable")
func request_cargo_take(index: int, id: StringName) -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not actor.vitals.is_up() or not in_reach(actor) or cargo() == null:
		return
	_tell(actor, server_unload(actor, index, id))


## Host: moves a hold entry to `actor`. Returns what to tell them.
func server_unload(actor: Soldier, index: int, id: StringName) -> String:
	var list := cargo_hold.entries()
	if index < 0 or index >= list.size() or list[index].id != id:
		return ""
	var entry: Dictionary = list[index]
	var item := ItemDB.get_item(id)
	var taken := 0
	if item.two_handed:
		taken = actor.inventory.take(id, 1, entry.get("state", {}))
	else:
		taken = actor.inventory.take(id, int(entry.count), entry.get("state", {}))
	if taken > 0:
		cargo_hold.remove_entry(VehicleCargo.HOLD, index, taken)
		return "Took %s%s" % [item.name, " x%d" % taken if taken > 1 else ""]
	var out := cargo_hold.remove_entry(VehicleCargo.HOLD, index, int(entry.count))
	level().server_spawn_dropped(out.id, int(out.count), _cargo_point() + Vector3.UP * 0.3, out.get("state", {}))
	return "No room on you: %s put down by the vehicle" % item.name


func _cargo_point() -> Vector3:
	for p in get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == VehicleActionPoint.CARGO:
			var at := (p as Node3D).global_position
			return Vector3(at.x, global_position.y, at.z)
	return global_position


## A service job: "repair" (a zone and the part to use), "refuel" (a jerrycan), "salvage" (a
## wreck). Timed: the player stands by until it's done (_job_step).
@rpc("any_peer", "call_local", "reliable")
func request_service(action: String, zone: StringName, item: StringName) -> void:
	var actor := _sender()
	if not multiplayer.is_server() or actor == null or not actor.vitals.is_up() or not in_reach(actor):
		return
	var why := server_start_job(actor, action, zone, item)
	if why != "":
		_tell(actor, why)


## Host: starts a timed service job for `actor`. Returns "" or why it can't.
func server_start_job(actor: Soldier, action: String, zone: StringName, item: StringName) -> String:
	if _jobs.has(actor.get_instance_id()):
		return "Already working on it"
	if logistics and action in VehicleLogistics.ACTIONS:
		return logistics.server_start_job(actor, action, String(zone), item)  # A8: modules, rearming, the tow, fuel pallets
	var seconds := 0.0
	var label := ""
	match action:
		"repair":
			var why := VehicleService.repair_problem(self, actor, zone, item)
			if why != "":
				return why
			seconds = float(ItemDB.get_item(item).stats.get("repair_s", 30.0))
			label = "%s: %s" % [ItemDB.get_item(item).name, VehicleService.zone_name(zone, kind)]
		"refuel":
			if VehicleService.jerrycan_fuel(actor) <= 0.0:
				return "No fuel in your jerrycans"
			if fuel >= float(spec.get("fuel_l", 0.0)) - 0.5:
				return "The tank is full"
			seconds = float(ItemDB.get_item(VehicleService.JERRYCAN).stats.get("refuel_s", 8.0))
			label = "Refuelling"
		"salvage":
			if not wrecked or salvaged:
				return "Nothing left to salvage"
			seconds = SALVAGE_S
			label = "Salvaging parts"
		_:
			return ""
	_jobs[actor.get_instance_id()] = {"actor": actor, "action": action, "zone": zone, "item": item, "until": Soldier._now() + seconds,
		"at": actor.global_position, "vehicle_at": global_position}
	if not actor.is_ai():
		actor._client_busy.rpc_id(actor.owner_peer(), seconds, "%s (%.0f s)" % [label, seconds])
	return ""


## Host: runs the service jobs. Each stops when its worker goes down or walks off, or when
## the vehicle drives (or is pushed) away from them, checked every step and so right before
## it would finish: work on a vehicle that has gone does nothing to it.
func _job_step() -> void:
	if _jobs.is_empty():
		return
	var now := Soldier._now()
	for id: int in _jobs.keys():
		var job: Dictionary = _jobs[id]
		var actor: Soldier = job.actor if is_instance_valid(job.actor) else null
		var stopped := actor == null or not actor.vitals.is_up() or actor.global_position.distance_to(job.at) > JOB_MOVE_M
		var gone := not stopped and (global_position.distance_to(job.get("vehicle_at", global_position)) > JOB_MOVE_M or not in_reach(actor))
		if stopped or gone:
			_jobs.erase(id)
			if actor:
				_tell(actor, "Stopped working on the %s%s" % [display_name(), ": it moved away" if gone else ""])
			continue
		if now < float(job.until):
			continue
		_jobs.erase(id)
		_tell(actor, VehicleService.finish(self, actor, String(job.action), StringName(job.zone), StringName(job.item)))


## Host: the seconds left on `actor`'s job (0 for none).
func job_left(actor: Node) -> float:
	var job: Dictionary = _jobs.get(actor.get_instance_id(), {})
	return maxf(maxf(float(job.get("until", 0.0)) - Soldier._now(), 0.0), logistics.job_left(actor) if logistics else 0.0)


## Host (V2, tests): sets a zone's health directly (0 to 1).
func server_set_zone(zone: StringName, health: float) -> void:
	_zones[zone] = clampf(health, 0.0, 1.0)
	modules.server_set_zone(zone, health)  # A2: the modules under it (the zone then answers from them)
	if zone == ZONE_HULL and health <= 0.0:
		_destroy()
	_publish_state(true)


## Host: fuel in, up to the tank. Returns the litres taken.
func server_refuel(litres: float) -> float:
	var room := maxf(float(spec.get("fuel_l", 0.0)) - fuel, 0.0)
	var taken := minf(room, maxf(litres, 0.0))
	fuel += taken
	_publish_state(true)
	return taken


## Host: the fuel tank set (tests, the motor pool).
func server_set_fuel(litres: float) -> void:
	fuel = clampf(litres, 0.0, float(spec.get("fuel_l", 0.0)))
	_publish_state(true)


## Host: repairs after a service job (VehicleService).
func server_repair(zone: StringName, to_health: float, add := 0.0) -> void:
	var h := float(_zones.get(zone, 1.0))
	_zones[zone] = clampf(maxf(h + add, to_health), 0.0, 1.0)
	modules.server_repair(zone, to_health, add)
	if zone == ZONE_FUEL:
		_leak = 0.0
	_publish_state(true)


## Host (A8: a patched fuel tank): the leak stops once no fuel tank is still holed.
func server_stop_leak() -> void:
	if modules and modules.authored:
		for m: Dictionary in modules.mods:
			if String(m.kind) == "fuel_tank" and modules.health[int(m.i)] <= VehicleModules.DAMAGED_SHARE:
				return
	_leak = 0.0
	_publish_state(true)


func server_set_battery(ok: bool) -> void:
	battery_ok = ok
	_publish_state(true)


func server_set_salvaged() -> void:
	salvaged = true
	_publish_state(true)


func _tell(actor: Soldier, text: String) -> void:
	if text == "" or actor == null or actor.is_ai():
		return
	actor._client_message.rpc_id(actor.owner_peer(), text)


# --- Mounted gun ----------------------------------------------------------------------------------

## The seats that fire a gun: the main gun's ("gun" "seat") and any seat with its own "weapon"
## (Captain, 2026-10-15: the UH-60M's crew chief and door gunner man M240H door guns).
func gun_seats() -> Array[int]:
	var out: Array[int] = []
	var main := _main_gun_seat()
	if main >= 0:
		out.append(main)
	var defs: Array = spec.get("seats", [])
	for i in defs.size():
		if (defs[i] as Dictionary).has("weapon") and not i in out:
			out.append(i)
	return out


## The weapon id seat `seat` fires ("" if none).
func seat_gun(seat: int) -> String:
	if seat >= 0 and seat == _main_gun_seat():
		return String((spec.gun as Dictionary).weapon)
	var defs: Array = spec.get("seats", [])
	return String((defs[seat] as Dictionary).get("weapon", "")) if seat >= 0 and seat < defs.size() else ""


## The main gun's seat, or -1.
func _main_gun_seat() -> int:
	var g: Dictionary = spec.get("gun", {})
	return int(g.get("seat", -1)) if g.has("weapon") else -1


## A gun seat's weapon (the main gun's when `seat` is -1): {"id", "name", "feed", "seat",
## "rounds" (in the hold), "rpm", "sound"} or {} if none fires.
func gun_info(seat := -1) -> Dictionary:
	if seat < 0:
		seat = _main_gun_seat()
	var id := seat_gun(seat)
	var data := VehicleSpecs.gun(id) if id != "" else {}
	if data.is_empty():
		return {}
	return {"id": id, "name": String(data.name), "feed": StringName(data.feed), "seat": seat,
		"rounds": cargo_hold.feed_rounds(StringName(data.feed)) if cargo_hold else 0, "rpm": float(data.get("rpm", 600)),
		"sound": String(data.get("sound", "rifle"))}


## Host: the mounted gun's feed in the hold topped up to its "load" (data/vehicles.json "guns":
## full belts, or loose rounds); spent and part-used belts go for full ones, extra full ones stay.
## Captain, 2026-10-14: the pool M-ATV came out with its M2 on 0 rounds (a new pool vehicle's
## record has no cargo, and nothing refilled one): MotorPool rearms a vehicle as it deploys and
## as it comes home. Returns the gun's rounds in the hold now.
## Every gun's feed is topped up (two door guns on one feed: both loads).
func server_rearm() -> int:
	var wants := {}
	for seat in gun_seats():
		var g := gun_info(seat)
		if not g.is_empty():
			wants[g.feed] = int(wants.get(g.feed, 0)) + int(VehicleSpecs.gun(String(g.id)).get("load", 0))
	if weapons:  # A3: the main guns' racks, the TOW, and the cupola and pintle guns' belts (A8: to the motor pool's load-out)
		for f: Array in weapons.server_rearm(VehicleLogistics.loadout_racks(spec, logistics.loadout, logistics.packages) if logistics else {}):
			wants[f[0]] = int(wants.get(f[0], 0)) + int(f[1])
	if smoke:
		smoke.server_restock()  # A7: the smoke grenades (A8: the stowage is smoke_salvo items; MotorPool prices them)
	if cargo_hold:
		for feed: StringName in wants:
			_rearm_feed(feed, int(wants[feed]))
	return int(gun_info().get("rounds", 0))


func _rearm_feed(feed: StringName, want: int) -> void:
	var item := ItemDB.get_item(feed)
	if item == null or want <= 0:
		return
	var per := item.magazine_rounds()
	if per > 0:
		var full := 0
		var list := cargo_hold.entries()
		for i in range(list.size() - 1, -1, -1):
			var e: Dictionary = list[i]
			if e.id != feed:
				continue
			if int(e.get("state", {}).get("rounds", per)) >= per:
				full += int(e.count)
			else:
				cargo_hold.remove_entry(VehicleCargo.HOLD, i, int(e.count))
		if full < want:
			cargo_hold.take(feed, want - full)
	elif cargo_hold.count_of(feed) < want:
		cargo_hold.take(feed, want - cargo_hold.count_of(feed))


## Where the gun's rounds start (world): its muzzle ("gun" "at"), where the turret has it now;
## a door gun's at its seat's "gun_at".
func gun_origin(seat := -1) -> Vector3:
	if seat >= 0 and seat != _main_gun_seat():
		var def: Dictionary = spec.seats[seat]
		return global_transform * VehicleSpecs.vec(def.get("gun_at", def.at))
	if turret:
		return global_transform * turret.muzzle_local()
	return global_transform * VehicleSpecs.vec((spec.get("gun", {}) as Dictionary).get("at"), Vector3(0, 2, 0))


## The way the gun's barrel points (world): along the turret's gun, or forward on a fixed gun.
func barrel_direction() -> Vector3:
	return (global_basis * (turret.barrel_local() if turret else Vector3.FORWARD)).normalized()


## Host: points the turret towards `direction` (world), within its limits (an AI gunner; it
## turns there at the mount's speeds).
func server_aim(direction: Vector3) -> void:
	if turret and direction.length_squared() > 0.000001 and not (gunnery and gunnery.slewing()):  # (A4: a hand-off's slew first)
		turret.aim_local(global_basis.inverse() * direction)


## Whether the barrel points within `within_deg` of `direction` (world); true on a fixed gun;
## a door gun: whether `direction` is in its arc (door_arc_ok).
func gun_on(direction: Vector3, within_deg := VehicleTurret.ON_TARGET_DEG, seat := -1) -> bool:
	if seat >= 0 and seat != _main_gun_seat():
		return door_arc_ok(seat, direction)
	return turret == null or turret.on_target(global_basis.inverse() * direction, within_deg)


## A door gun fires out of its own side only (outwards from its seat's "gun_at" side, never
## back through the cabin), and from well below level to a little above it.
func door_arc_ok(seat: int, direction: Vector3) -> bool:
	if direction.length_squared() < 0.000001:
		return false
	var def: Dictionary = spec.seats[seat]
	var side := signf(VehicleSpecs.vec(def.get("gun_at", def.at)).x)
	var local := (global_basis.inverse() * direction).normalized()
	return local.x * side >= DOOR_ARC_OUT and local.y <= DOOR_ARC_UP


## The gunner's peer: where it wants the turret (the vehicle's frame, radians).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_aim(p_yaw: float, p_pitch: float) -> void:
	var actor := _sender()
	if multiplayer.is_server() and turret and actor and actor.vitals.is_up() and gunner() == actor and is_finite(p_yaw) and is_finite(p_pitch) \
			and not (gunnery and gunnery.slewing()):
		turret.aim(p_yaw, p_pitch)


## The local player on this peer, if they man this vehicle's turret.
func _local_gunner() -> Soldier:
	if _gun_seat < 0:
		return null
	var s := occupant(_gun_seat)
	return s if s and not s.is_ai() and s.is_local() else null


## The turret's gunner turning it (every peer, for the body it drives; returns the body's turn
## from the vehicle's heading). An AI gunner faces where the gun points (AavGunner aims it). A
## player in first person: the mouse turns the turret, not the view (what the mouse turned since
## last frame goes to where the turret's going) and the view is the gun's; in the chase view
## the view is free and the turret turns to the camera's crosshair (gun_direction).
func _gunner_look(s: Soldier, rel: float, veh_yaw: float) -> float:
	if turret == null:
		return rel
	if s.is_ai():
		return turret.yaw
	if not s.is_local():
		return rel
	if VehicleCamera.chase:
		var cam := VehicleCamera.of(s)
		if cam and cam.active and s.vitals.is_up():
			turret.aim_local(global_basis.inverse() * gun_direction(s))
		s.remove_meta(&"turret_set")
		return rel
	# What we set last frame (turn, pitch, when): only a fresh one counts (not one left from an
	# earlier turn at the gun, or from the chase view).
	var was: Vector3 = s.get_meta(&"turret_set", Vector3(0, 0, -INF))
	if s.vitals.is_up() and Soldier._now() - was.z < 0.25:
		turret.aim(turret.target_yaw + wrapf(rel - was.x, -PI, PI), turret.target_pitch + (s.head.rotation.x - was.y))
	var w := global_basis * turret.sight_local()  # (A4: the sight's line; the gun sits off it by the solution's lay)
	var out := wrapf(atan2(-w.x, -w.z) - veh_yaw, -PI, PI)
	s.set_pitch(asin(clampf(w.y, -1.0, 1.0)))
	s.set_meta(&"turret_set", Vector3(out, s.head.rotation.x, Soldier._now()))
	return out


## The way the local gunner `viewer` aims: along their view in first person; in the chase view
## (VehicleCamera) from the gun to what the camera's crosshair is on, so the gun points where
## the camera looks (Arma's third-person gunner).
func gun_direction(viewer: Soldier) -> Vector3:
	var cam := VehicleCamera.of(viewer)
	if cam == null or not cam.active:
		return -viewer.camera.global_basis.z
	var fwd := -cam.global_basis.z
	var to := cam.aim_point() - gun_origin(seat_of(viewer))
	if to.length() < 1.0 or to.normalized().dot(fwd) < 0.2:
		return fwd  # the crosshair on something at the gun itself, or behind it: along the view
	return to.normalized()


## The gunner fires along `direction` (from their view).
@rpc("any_peer", "call_local", "reliable")
func request_gun(direction: Vector3) -> void:
	var actor := _sender()
	if multiplayer.is_server() and actor and actor.vitals.is_up() and seat_of(actor) in gun_seats() and Soldier.usable_direction(direction):
		server_fire_gun(actor, direction)


## Host: one shot of the mounted gun by `shooter` along `direction` (its rate kept, a round
## drawn from the hold); a turret's along its barrel, whatever `direction` says. Returns
## Ballistics' result, or {} if it didn't fire.
## The shooter's own gun seat fires (a door gun: along `direction`, within its arc); someone
## not in a gun seat (tests, scripted fire) fires the main gun.
func server_fire_gun(shooter: Soldier, direction: Vector3) -> Dictionary:
	var seat := seat_of(shooter)
	if not seat in gun_seats():
		seat = _main_gun_seat()
	var info := gun_info(seat)
	if info.is_empty() or wrecked or not _gun_seat_ok(seat, shooter):  # A2: its breech, barrel or sights out (A3: its own)
		return {}
	var main := seat == _main_gun_seat()
	if not main and not door_arc_ok(seat, direction):
		return {}
	var now := Soldier._now()
	var next := float(_gun_next.get(seat, 0.0))
	if now < next:
		return {}
	var item := VehicleSpecs.gun_item(info.id)
	_gun_next[seat] = maxf(next, now - GUN_BUNCH_S) + 60.0 / float(info.rpm) + (weapons.legacy_jam_s(seat) if weapons else modules.gun_jam_s(seat))
	if not cargo_hold.take_feed(info.feed):
		_tell(shooter, "%s: no ammunition in the %s" % [info.name, display_name()])
		return {}
	var origin := gun_origin(seat)
	var spread := deg_to_rad(float(item.stats.get("spread_deg", 0.3))) * (weapons.legacy_spread_mult(seat) if weapons else modules.gun_spread_mult(seat))
	# A turret's rounds go where its barrel points (the gunner turns it: request_aim, server_aim).
	var dir := barrel_direction() if turret and main else direction.normalized()
	return fire_mg_round(shooter, item, String(info.sound), origin, dir, spread)


## Host: whether gun seat `seat`'s own gun may fire for `shooter`: A2's armament modules of the
## seat; on a model with VehicleWeapons (A3) the legacy gun's own (the coax by its sights, not
## the main gun's breech), its man at the job (not moving seats, not loading short-crewed).
func _gun_seat_ok(seat: int, shooter: Soldier) -> bool:
	if weapons:
		return weapons.legacy_ok(seat, shooter)
	return modules.gun_ok(seat)


## Host: one round of a machine gun `item` (VehicleSpecs.gun_item) from `origin` along `dir`
## scattered by `spread` (radians) through Ballistics, with its sound (`sound`: the gun's Sfx
## kind), noise and tracer on every peer. Returns Ballistics' result. The vehicle's own gun
## (server_fire_gun) and VehicleWeapons' cupola and pintle guns (A3) fire through it.
func fire_mg_round(shooter: Soldier, item: ItemData, sound: String, origin: Vector3, dir: Vector3, spread: float) -> Dictionary:
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
	var lift := side.cross(dir).normalized()
	dir = (dir + side * randf_range(-1, 1) * tan(spread) + lift * randf_range(-1, 1) * tan(spread)).normalized()
	if shooter:
		shooter.server_end_spawn_protection()  # firing ends spawn protection (Soldier)
	var result := Ballistics.fire(shooter, origin, dir, item)
	## Captain, 2026-10-15 (v0.4.3): the .50 cal made no sound: mounted guns never called Sfx.
	## Every peer hears each shot (the gun's "sound": "hmg" for the heavy guns, else a rifle's).
	var round_end: Variant = result.get("position")
	Sfx.server_shot(origin, round_end if round_end is Vector3 else origin + dir * 400.0, sound)
	var lvl := level()
	if lvl:
		PeopleLayer.server_noise(shooter, origin)
		# Every round is seen too (Tracer, as a soldier's: Soldier._server_fire), along the path it
		# flew (Ballistics.flight_path; Captain, 2026-10-21).
		_gun_rounds += 1
		var every := int(item.stats.get("tracer_every", Soldier.TRACER_EVERY))
		var hostile := shooter != null and shooter.faction == &"hostile"
		var kind: int = (Tracer.Kind.GREEN if hostile else Tracer.Kind.RED) if every > 0 and _gun_rounds % every == 0 else Tracer.Kind.BALL
		var launch: Variant = result.get("launch")
		lvl.show_tracer.rpc(origin, launch if launch is Vector3 and round_end is Vector3 else Vector3.ZERO, Ballistics.round_id(item),
			round_end if round_end is Vector3 else origin + dir * 400.0, false, kind, false)
		if result.result != "none":
			lvl.show_impact.rpc(result.position, result.normal, result.result)
	return result


# --- The local occupant's controls and readout ------------------------------------------------------

## The local player, if they sit in this vehicle: their driving and gun go to the host, and a
## line on their HUD says where they sit and how the vehicle is.
func _local_controls(delta: float) -> void:
	var lvl := level()
	var me := lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if lvl and is_inside_tree() else null
	var seat := seat_of(me) if me else -1
	if seat < 0 or not Vehicle.local_input or not me.is_local() or me.player_input == null or me.player_input.hud == null:
		if _hud:
			if is_instance_valid(_hud):
				_hud.hide_vehicle()
			_hud = null
		return
	var free := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and me.vitals.is_up() and not me.player_input.interaction.is_open() \
		and not me.player_input.hud.is_inventory_open() and not me.player_input.hud.command_menu.is_open() \
		and not (me.player_input.hud.map_screen and me.player_input.hud.map_screen.is_open())
	var k := seat_kind(seat)
	if k == DRIVER:
		var throttle := (Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back")) if free else 0.0
		var steer := (Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")) if free else 0.0
		var brake := (Input.is_action_pressed(&"jump") if free else true) or (throttle == 0.0 and absf(forward_speed()) < 0.5)
		var now := {"throttle": throttle, "steer": steer, "brake": brake}
		_send_left -= delta
		if now != _last_sent or _send_left <= 0.0:
			_last_sent = now
			_send_left = 0.1
			request_drive.rpc_id(1, throttle, steer, brake)
	if gunnery:
		gunnery.local_controls(me, seat, free)  # A4: the sight, the laser, the hand-off, the fuze
	if hatches and free and hatches.has_hatch(seat) and Input.is_action_just_pressed(&"hatch"):
		hatches.request_toggle.rpc_id(1)  # A4: turn out or button up
	if k == DRIVER:
		pass
	elif weapons and weapons.local_controls(me, seat, free):
		pass  # A3: the seat's mounts (main gun, TOW, the loader's cycle, the commander's gun) took the keys
	elif k == GUNNER and free and Input.is_action_pressed(&"fire"):
		var info := gun_info(seat)
		if not info.is_empty() and Soldier._now() >= _gun_local_next:
			_gun_local_next = Soldier._now() + 60.0 / float(info.rpm)
			request_gun.rpc_id(1, gun_direction(me))
	_hud = me.player_input.hud
	if not VehicleHud.local_step(self, me, seat, free):  # A5: armour's HUDs, vision blocks, muffled hearing
		_hud.show_vehicle(readout_parts(seat))


## The HUD's readout in parts (Hud.show_vehicle lays them out in its bottom-centre zone, each
## its own label, flowing onto another line; docs/ui_audit.md P1-9: one run-on line of up to 8
## parts, 800 to 900 px wide, with no outline): the vehicle and seat, speed, fuel, damage, the
## gun's rounds, a warning (style "warn"), the view key (VehicleCamera: the view it switches to)
## and the get-out key when it's on (ControlOptions: the seat's menu has no Get out then; both
## style "key"). Each is {"text", "style"}.
func readout_parts(seat: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [{"text": "%s, %s" % [display_name(), seat_name(seat)], "style": &""}]
	if seat_kind(seat) == DRIVER:
		parts.append({"text": "%d km/h" % roundi(absf(forward_speed()) * 3.6), "style": &""})
	if kind != STATIC:
		parts.append({"text": "Fuel %d L" % roundi(fuel_litres()), "style": &""})
	for z: StringName in ([ZONE_HULL] if kind == STATIC else [ZONE_ENGINE, ZONE_WHEELS, ZONE_HULL]):
		var h := zone_health(z)
		if h < 0.999:
			parts.append({"text": "%s %d%%" % [VehicleService.zone_name(z, kind).capitalize(), roundi(h * 100.0)], "style": &"warn" if h < 0.35 else &""})
	if weapons:
		parts.append_array(weapons.readout_parts(seat))  # A3: main gun, loader, feeds, TOW, seat moves
	if gunnery:
		parts.append_array(gunnery.readout_parts(seat))  # A4: the lase, the stabiliser, a sight's fallback
	if hatches:
		parts.append_array(hatches.readout_parts(seat))  # A4: turned out or buttoned up
	if smoke:
		parts.append_array(smoke.readout_parts(seat))  # A7: the dischargers' salvos
	if logistics:
		parts.append_array(logistics.readout_parts(seat))  # A8: work under way, a tow
	if drive:
		parts.append_array(drive.readout_parts(seat))  # A6: rolled over, flooded, stalled, bogged
	if seat_kind(seat) == GUNNER:
		var info := gun_info(seat)
		if not info.is_empty():
			parts.append({"text": "%s: %d rounds" % [info.name, int(info.rounds)], "style": &""})
	if is_burning():
		parts.append({"text": "ON FIRE: GET OUT", "style": &"warn"})
	elif not can_drive() and seat_kind(seat) == DRIVER:
		parts.append({"text": "Won't drive", "style": &"warn"})
	parts.append({"text": "%s: %s" % [OS.get_keycode_string(GameSettings.key_for(VehicleCamera.ACTION)), "1st person" if VehicleCamera.chase else "3rd person"],
		"style": &"key"})
	if ControlOptions.get_out_key():
		parts.append({"text": "%s: get out" % ControlOptions.get_out_key_name(), "style": &"key"})
	return parts


## The readout as one line (tests and logs read it): the parts joined with " | ".
func readout(seat: int) -> String:
	return "  |  ".join(PackedStringArray(readout_parts(seat).map(func(p: Dictionary) -> String: return String(p.text))))


# --- Saving ------------------------------------------------------------------------------------

## JSON-safe state for the zone save and the motor pool (model, scheme, transform, damage,
## cargo, wrecked); from_save restores it.
## The airframe's condition, without where it is or who's in it (LZ-3: a support helicopter keeps
## it between calls and zones, Airframes): damage zones, fuel, a fuel leak, the holes in it.
func condition() -> Dictionary:
	var zones_out := {}
	for z: StringName in _zones:
		zones_out[String(z)] = float(_zones[z])
	var out := {"zones": zones_out, "fuel": fuel, "leak": _leak, "carves": net_carves.duplicate(true), "modules": modules.to_save()}
	if weapons:
		out["weapons"] = weapons.to_save()  # A3: which rounds where, what's loaded
	return out


## Host: puts a saved condition() back on this vehicle.
func apply_condition(c: Dictionary) -> void:
	if c.is_empty():
		return
	var zones_in: Dictionary = c.get("zones", {})
	for z: Variant in zones_in:
		_zones[StringName(String(z))] = clampf(float(zones_in[z]), 0.0, 1.0)
	fuel = clampf(float(c.get("fuel", fuel)), 0.0, float(spec.get("fuel_l", fuel)))
	_leak = maxf(float(c.get("leak", 0.0)), 0.0)
	if c.has("carves"):
		net_carves = (c.carves as Array).duplicate(true)
	modules.from_save(c.get("modules", {}), zones_in)
	if weapons and c.get("weapons") is Dictionary:
		weapons.from_save(c.weapons)


func to_save() -> Dictionary:
	var p := global_position if is_inside_tree() else _spawn_xform.origin
	var q := (global_basis if is_inside_tree() else _spawn_xform.basis).get_rotation_quaternion()
	var zones_out := {}
	for z: StringName in _zones:
		zones_out[String(z)] = float(_zones[z])
	var out := {"id": vehicle_id, "model": model, "scheme": scheme, "faction": String(faction), "wrecked": wrecked,
		"pos": [p.x, p.y, p.z], "rot": [q.x, q.y, q.z, q.w], "zones": zones_out, "fuel": fuel, "burning": burning_s,
		"battery": battery_ok, "salvaged": salvaged, "leak": _leak, "carves": net_carves.duplicate(true),
		"cargo": cargo_hold.net_state.duplicate(true) if cargo_hold else {}, "bodies": _body_uids(), "modules": modules.to_save()}
	if weapons:
		out["weapons"] = weapons.to_save()  # A3
	if gunnery:
		out["gunnery"] = gunnery.to_save()  # A4
	if hatches:
		out["hatches"] = hatches.to_save()
	if fire_state:
		var f := fire_state.to_save()
		if not f.is_empty():
			out["fire"] = f  # A7: the fire's stage, the thrown turret and the debris
	if smoke:
		out["smoke"] = smoke.to_save()
	if logistics:
		out["logistics"] = logistics.to_save()  # A8: packages, the load-out, bottles, repair progress, fired tiles
	if drive:
		var d := drive.to_save()
		if not d.is_empty():
			out["drive"] = d  # A6: rolled over, flooded, bogged, water aboard
	return out


## Host: the dead riding in seats, by seat (as text), by their body uid (Soldier.body_record:
## the zone save keeps the bodies themselves; from_save and server_seat_saved_bodies put them back).
func _body_uids() -> Dictionary:
	var out := {}
	for i in _seat_nodes.size():
		var s := occupant(i)
		if s and s.vitals.is_dead() and s.is_in_group(Soldier.DEAD_GROUP) and s.body_uid != "":
			out[str(i)] = s.body_uid
	for i: int in _saved_bodies:
		if occupant(i) == null:
			out[str(i)] = _saved_bodies[i]  # not back in their seat yet: still theirs
	return out


## Host: the bodies the zone save had riding in this vehicle go back to their seats (once the
## zone's bodies are restored: VehicleLayer.server_restore). One not found is forgotten.
func server_seat_saved_bodies() -> void:
	if not multiplayer.is_server() or _saved_bodies.is_empty():
		return
	var by_uid := {}
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var b := n as Soldier
		if b and not b.is_queued_for_deletion() and b.body_uid != "" and Vehicle.ride_of(b) == null:
			by_uid[b.body_uid] = b
	var wanted := _saved_bodies.duplicate()
	_saved_bodies.clear()
	for i: int in wanted:
		var b: Soldier = by_uid.get(String(wanted[i]))
		if b and not wrecked:
			server_enter(b, i)


func from_save(data: Dictionary) -> void:
	vehicle_id = String(data.get("id", vehicle_id))
	model = String(data.get("model", model))
	scheme = String(data.get("scheme", scheme))
	faction = StringName(data.get("faction", faction))
	wrecked = bool(data.get("wrecked", false))
	if spec.is_empty():
		setup(model, scheme, faction, vehicle_id)
	var p: Array = data.get("pos", [])
	var q: Array = data.get("rot", [])
	if p.size() == 3:
		_spawn_xform.origin = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if q.size() == 4:
		_spawn_xform.basis = Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized())
	transform = _spawn_xform
	var zones_in: Dictionary = data.get("zones", {})
	for z: Variant in zones_in:
		_zones[StringName(String(z))] = clampf(float(zones_in[z]), 0.0, 1.0)
	fuel = clampf(float(data.get("fuel", fuel)), 0.0, float(spec.get("fuel_l", fuel)))
	burning_s = maxf(float(data.get("burning", 0.0)), 0.0)
	battery_ok = bool(data.get("battery", true))
	salvaged = bool(data.get("salvaged", false))
	_leak = maxf(float(data.get("leak", 0.0)), 0.0)
	_lost = wrecked or burning_s > 0.0
	net_carves = (GameState.from_json(data.get("carves", [])) as Array) if data.has("carves") else []
	modules.from_save(data.get("modules", {}) if data.get("modules") is Dictionary else {}, zones_in)  # A2 (an older save: from its zones)
	if weapons:
		weapons.from_save(data.get("weapons", {}) if data.get("weapons") is Dictionary else {})  # A3 (an older save: the racks' default mix)
	if gunnery and data.get("gunnery") is Dictionary:
		gunnery.from_save(data.gunnery)  # A4
	if hatches and data.get("hatches") is Dictionary:
		hatches.from_save(data.hatches)
	if fire_state:
		fire_state.from_save(data.get("fire", {}) if data.get("fire") is Dictionary else {})  # A7 (an older wreck: a smoulder)
	if smoke and data.get("smoke") is Dictionary:
		smoke.from_save(data.smoke)
	if logistics:
		logistics.from_save(data.get("logistics", {}) if data.get("logistics") is Dictionary else {})  # A8 (an older save: no packages)
	if drive:
		drive.from_save(data.get("drive", {}) if data.get("drive") is Dictionary else {})  # A6 (an older save: on its wheels, dry)
	if cargo_hold and data.get("cargo") is Dictionary and not (data.cargo as Dictionary).is_empty():
		cargo_hold.net_state = GameState.from_json(data.cargo)
	_saved_bodies.clear()
	var bodies_in: Variant = data.get("bodies", {})
	if bodies_in is Dictionary:
		for k: Variant in bodies_in:
			if String(k).is_valid_int() and int(String(k)) >= 0 and int(String(k)) < _seat_nodes.size():
				_saved_bodies[int(String(k))] = String(bodies_in[k])
	if hull:
		hull.set_wrecked(wrecked)
	_publish_state(true)
