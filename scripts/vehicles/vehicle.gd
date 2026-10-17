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
## Vehicle kinds (data/vehicles.json "kind").
const WHEELED := "wheeled"
const TRACKED := "tracked"
const HELICOPTER := "helicopter"

## Suspension (Proposed): static sag under the vehicle's weight, travel above the wheel's rest
## height, droop below it, and the damping ratio.
const SAG_WHEELED := 0.12
const SAG_TRACKED := 0.07
const TRAVEL := 0.22
const DROOP := 0.18
const DAMPING_RATIO := 0.5
## Tyre and track grip (Proposed): friction coefficient, and how much of a wheel's sideways slip
## is taken out each physics step; tracks slip sideways while turning on the spot.
const GRIP := 0.95
const LATERAL_RESPONSE := 0.45
const TRACK_TURN_LATERAL := 0.15
## Steering falls off with speed (wheeled): full lock below this speed (m/s), half at twice it.
const STEER_FALLOFF_MS := 8.0
## Rolling resistance and engine braking with the throttle off (m/s2).
const ROLL_DECEL := 0.3
const ENGINE_BRAKE := 0.5
## The steepest grade the drive holds on top of its acceleration (degrees, Proposed, wave 5b).
const CLIMB_DEG := 35.0
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
var _gun_next := {}          # host: gun seat -> when it may fire next
var _run_over_at := {}          # soldier instance id -> time last run over
var _pushed_at := {}             # host: player soldier instance id -> time last sent a push
var _blocked_s := 0.0            # host: driven but held still against a body
var _ridden := {}                # host: ragdoll part -> time its collision exception ends
var _jobs := {}              # actor instance id -> timed job
var _last_pos := Vector3.ZERO
var _seen := {}              # every peer: instance id -> Soldier seated last frame
var _snaps: Array = []       # clients: [host time, position, rotation]
var _clock := INF            # clients: local time minus host time
var _fire_fx: Node3D
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
	fuel = float(spec.get("fuel_l", 100.0))
	for z in ZONES:
		_zones[z] = 1.0
	_seat_nodes.resize((spec.get("seats", []) as Array).size())
	_seat_nodes.fill(null)
	for seat: Dictionary in spec.get("seats", []):
		var eye := Vehicle.seat_eye(String(seat.get("stance", "sit")))
		_seat_local.append(Transform3D(Basis(), VehicleSpecs.vec(seat.at) - Vector3(0, eye, 0)))
		_seat_poses.append(_seated_pose_for(seat, eye))
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
	for path: NodePath in [^".:net_state", ^".:net_carves", ^"Cargo:net_state"]:
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
		if wrecked:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
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
	return SoldierMovement.Stance.STAND_LOW if stance == "stand" else SoldierMovement.Stance.CROUCH_MID


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


## A seat's eye point in the world (the gunner's turns with the turret).
func seat_eye_point(index: int) -> Vector3:
	var at := VehicleSpecs.vec(spec.seats[index].at)
	return global_transform * (turret.carry(at) if index == _gun_seat else at)


## The seated pose (CharacterModel.seated_pose) for a seat whose eye is `eye` above its body's
## origin, or {} for a standing one (a hatch or a pickup bed: the stance poses him). The hips
## go on the seat's cushion (VehicleInteriors.cushion_top) and the feet on the cabin floor
## (VehicleInteriors.FLOORS; an open seat's isn't drawn there: CharacterModel.SEAT_HEIGHT under
## the hips). Captain, 2026-10-14: the UH-60M's riders were posed standing in their seats.
func _seated_pose_for(seat: Dictionary, eye: float) -> Dictionary:
	if String(seat.get("stance", "sit")) == "stand":
		return {}
	var eye_y := VehicleSpecs.vec(seat.at).y
	var origin_y := eye_y - eye
	var floor_y := NAN if bool(seat.get("open", false)) else VehicleInteriors.floor_of(model)
	var hip := VehicleInteriors.cushion_top(eye_y, floor_y) + CharacterModel.SEAT_HIP_UP - origin_y
	var floor_rel := hip - CharacterModel.SEAT_HEIGHT if is_nan(floor_y) else floor_y - origin_y
	return CharacterModel.seated_pose(hip, floor_rel, StringName(seat.get("kind", "")) in [DRIVER, PILOT, GUNNER])


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
	var t := _seat_local[index]
	if index == _gun_seat:
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
	return not wrecked and kind != HELICOPTER and zone_health(ZONE_ENGINE) > 0.0 and fuel_litres() > 0.0 \
		and (battery_ok if multiplayer.is_server() else bool(net_state.get("battery", true))) \
		and not (kind == TRACKED and zone_health(ZONE_WHEELS) <= 0.0)


## Top speed now (m/s): the model's, cut by engine and wheel damage.
func top_speed(reverse := false) -> float:
	var top := float(spec.get("reverse_kmh" if reverse else "top_speed_kmh", 0.0)) * VehicleSpecs.KMH
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
	if index < 0:
		index = _first_free_passenger() if body else _first_free_for(s)
	if index < 0 or index >= _seat_nodes.size() or occupant(index) != null:
		return false
	var k := seat_kind(index)
	if body and k != PASSENGER:
		return false
	if k == PILOT and not s.is_ai():
		return false  # aircraft are AI-flown only (Captain)
	var other := Vehicle.ride_of(s)
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
	_publish_state(true)
	seats_changed.emit()
	if not Person.is_person(s) and s.vitals.is_up() and s.faction == &"friendly":
		_board_followers(s)
	return true


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
		if occupant(i) == null and seat_kind(i) == PASSENGER:
			return i
	return -1


func _first_free_for(s: Soldier) -> int:
	var order: Array[StringName] = [PASSENGER, GUNNER, DRIVER, PILOT]
	for k in order:
		for i in _seat_nodes.size():
			if occupant(i) == null and seat_kind(i) == k and (k != PILOT or s.is_ai()):
				return i
	return -1


## Host: take `soldier` out of the vehicle to a safe free spot beside it (by their seat's
## door first, then round the vehicle).
func server_exit(soldier: Node) -> void:
	var s := soldier as Soldier
	var index := seat_of(s)
	if not multiplayer.is_server() or index < 0:
		return
	var spot := exit_spot(index, s)
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


## Host: move `soldier` to seat `index` of this vehicle (they must be in it already).
func server_switch(soldier: Node, index: int) -> bool:
	var s := soldier as Soldier
	var from := seat_of(s)
	if from < 0 or index < 0 or index >= _seat_nodes.size() or occupant(index) != null or index == from:
		return false
	if seat_kind(index) == PILOT and not s.is_ai():
		return false
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
	return bool((defs[index] as Dictionary).get("open", false)) or (bay != null and bay.ffv_active(index))


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
		if hit.collider == self:
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
		var seat_def: Dictionary = defs[i]
		var t := global_transform * _seat_at(i)
		s.vehicle = self
		var f := -global_basis.z
		var veh_yaw := atan2(-f.x, -f.z)
		## "face": which way the seat faces, degrees from the vehicle's front (positive to the
		## left; a bench facing aft or outboard). Riders face it; the drawn body does even while
		## a player looks round (the seat pose turns it back by the difference).
		var face := deg_to_rad(float(seat_def.get("face", 0.0)))
		s.global_position = t.origin
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
			if s.has_meta(&"seat_veh_yaw") and not s.is_ai():
				rel = wrapf(s.rotation.y - float(s.get_meta(&"seat_veh_yaw")), -PI, PI)
				if StringName(seat_def.kind) != GUNNER:
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
				s.head.position.y = SoldierMovement.STANCE_EYE[stance]
		var seated: Dictionary = _seat_poses[i] if i < _seat_poses.size() else {}
		if not seated.is_empty():
			# Every peer, from the synced turn; the gun's seat turns with its gunner (and the gun).
			seated["yaw"] = 0.0 if i == _gun_seat else wrapf(veh_yaw + face - s.rotation.y, -PI, PI)
		s.seat_pose = seated
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
	_place_occupants()
	if hull:
		hull.pose_turret()
	_local_controls(delta)
	_update_fire_fx()


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
	var throttle := clampf(float(input.throttle), -1.0, 1.0) if can_drive() else 0.0
	var steer := clampf(float(input.steer), -1.0, 1.0)
	var brake := bool(input.brake) or not can_drive()
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
	var drive := 0.0
	if throttle != 0.0:
		var top := top_speed(throttle < 0.0)
		var curve := sqrt(clampf(1.0 - absf(v_fwd) / maxf(top, 0.1), 0.0, 1.0))
		drive = throttle * mass * float(spec.get("accel_ms2", 2.0)) * curve
		# Wave 5b: uphill the engine gears down and holds the grade (up to CLIMB_DEG; the tyres'
		# or tracks' grip still limits it), so a hill doesn't stall it at accel_ms2's slope.
		var grade := clampf(forward.y * signf(throttle), 0.0, sin(deg_to_rad(CLIMB_DEG)))
		drive += signf(throttle) * mass * g * grade * minf(absf(throttle) * 1.5, 1.0)
	var brake_force := mass * float(spec.get("brake_ms2", 6.0)) if brake else 0.0
	var wheels_ok := zone_health(ZONE_WHEELS)
	var grip := GRIP * (lerpf(0.55, 1.0, wheels_ok) if wheels_ok > 0.0 else 0.4)
	var steer_angle := 0.0
	if not tracked:
		steer_angle = -steer * deg_to_rad(float(spec.get("steer_deg", 30.0))) / (1.0 + absf(v_fwd) / STEER_FALLOFF_MS)
	var coast := ROLL_DECEL + (ENGINE_BRAKE if throttle == 0.0 else 0.0)
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
		var f_long := drive / n
		if brake_force > 0.0:
			f_long += clampf(-v_long * share / delta, -brake_force / n, brake_force / n)
		else:
			f_long += clampf(-v_long * share / delta, -coast * share, coast * share)
		var traction := f_dir * f_long + s_dir * f_lat
		var limit := normal_force * grip
		if traction.length() > limit:
			traction = traction.normalized() * limit
		apply_force(up * normal_force + traction, point - global_position)
	if tracked and grounded > 0:
		# Skid steering: the hull turns at the commanded rate, on the spot or on the move.
		var size := VehicleArt.size_m(model)
		var inertia := mass * (size.x * size.x + size.z * size.z) / 12.0
		var target := -steer * deg_to_rad(float(spec.get("turn_deg_s", 40.0))) * (lerpf(0.4, 1.0, zone_health(ZONE_ENGINE)) if can_drive() else 0.0)
		var yaw_rate := angular_velocity.dot(up)
		var torque := clampf((target - yaw_rate) * inertia / TRACK_TURN_TIME_S, -mass * g * size.z * 0.25, mass * g * size.z * 0.25)
		apply_torque(up * torque * (float(grounded) / n))


## Host: wakes settled ragdolls just ahead of the hull while it moves or is driven (a body it
## has stopped against too), and runs over soldiers in its path.
func _wake_bodies_ahead() -> void:
	var speed := linear_velocity.length()
	var pushing := can_drive() and absf(float(_current_input().throttle)) > 0.0
	_ride_over(speed, pushing)
	if speed < 0.5 and not pushing:
		return
	var size := VehicleArt.size_m(model)
	var ahead := speed * RAGDOLL_LOOKAHEAD_S + RAGDOLL_MARGIN_M
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + RAGDOLL_MARGIN_M * 2.0, maxf(size.y, 1.0), size.z + ahead * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
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
	var used := moved / 1000.0 * float(spec.get("fuel_l_per_km", 0.5))
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
		"wrecked": wrecked, "battery": battery_ok, "salvaged": salvaged, "lost": _lost, "bay": bay != null and bay.open,
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
	var res := VehicleDamage.resolve(hit, zone, ldir)
	out.zone = zone.zone
	out.penetrated = res.penetrated
	out.stopped = res.stopped
	out.energy_left = res.energy_left
	out.lost_j = maxf(float(hit.get("energy_j", 0.0)) - float(res.energy_left), 0.0)
	if not on_part:
		_carve_for(hit_kind, res, local, hit)
	if not wrecked:
		_apply_damage(zone, res, out.position, hit)
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
	var dmg := float(res.damage_kj)
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
		var size := VehicleArt.size_m(model)
		var spot := Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(0.3, 0.9) * size.y, randf_range(-0.4, 0.4) * size.z)
		_add_carves([[spot.x, spot.y, spot.z, 0.5, VehicleHull.SCORCH]])
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

func _update_fire_fx() -> void:
	var on := is_burning()
	if on and _fire_fx == null:
		_fire_fx = Node3D.new()
		_fire_fx.name = "Fire"
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.15)
		light.omni_range = 9.0
		light.light_energy = 3.0
		_fire_fx.add_child(light)
		var flame := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
		sphere.material = mat
		flame.mesh = sphere
		_fire_fx.add_child(flame)
		_fire_fx.position = Vector3(0, VehicleArt.size_m(model).y * 0.7, 0)
		add_child(_fire_fx)
	elif not on and _fire_fx:
		_fire_fx.queue_free()
		_fire_fx = null
	if _fire_fx:
		var flicker := 0.75 + 0.25 * sin(Soldier._now() * 17.0) * sin(Soldier._now() * 7.3)
		(_fire_fx.get_child(0) as OmniLight3D).light_energy = 3.0 * flicker
		_fire_fx.scale = Vector3.ONE * (0.9 + 0.2 * flicker)


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
	return maxf(float(job.get("until", 0.0)) - Soldier._now(), 0.0)


## Host (V2, tests): sets a zone's health directly (0 to 1).
func server_set_zone(zone: StringName, health: float) -> void:
	_zones[zone] = clampf(health, 0.0, 1.0)
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
	if zone == ZONE_FUEL:
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
	if turret and direction.length_squared() > 0.000001:
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
	if multiplayer.is_server() and turret and actor and actor.vitals.is_up() and gunner() == actor and is_finite(p_yaw) and is_finite(p_pitch):
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
	var w := global_basis * turret.barrel_local()
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
	if info.is_empty() or wrecked:
		return {}
	var main := seat == _main_gun_seat()
	if not main and not door_arc_ok(seat, direction):
		return {}
	var now := Soldier._now()
	var next := float(_gun_next.get(seat, 0.0))
	if now < next:
		return {}
	var item := VehicleSpecs.gun_item(info.id)
	_gun_next[seat] = maxf(next, now - GUN_BUNCH_S) + 60.0 / float(info.rpm)
	if not cargo_hold.take_feed(info.feed):
		_tell(shooter, "%s: no ammunition in the %s" % [info.name, display_name()])
		return {}
	var origin := gun_origin(seat)
	var spread := deg_to_rad(float(item.stats.get("spread_deg", 0.3)))
	# A turret's rounds go where its barrel points (the gunner turns it: request_aim, server_aim).
	var dir := barrel_direction() if turret and main else direction.normalized()
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
	var lift := side.cross(dir).normalized()
	dir = (dir + side * randf_range(-1, 1) * tan(spread) + lift * randf_range(-1, 1) * tan(spread)).normalized()
	if shooter:
		shooter.server_end_spawn_protection()  # firing ends spawn protection (Soldier)
	var result := Ballistics.fire(shooter, origin, dir, item)
	## Captain, 2026-10-15 (v0.4.3): the .50 cal made no sound: mounted guns never called Sfx.
	## Every peer hears each shot (the gun's "sound": "hmg" for the heavy guns, else a rifle's).
	var round_end: Variant = result.get("position")
	Sfx.server_shot(origin, round_end if round_end is Vector3 else origin + dir * 400.0, String(info.sound))
	var lvl := level()
	if lvl:
		PeopleLayer.server_noise(shooter, origin)
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
	elif k == GUNNER and free and Input.is_action_pressed(&"fire"):
		var info := gun_info(seat)
		if not info.is_empty() and Soldier._now() >= _gun_local_next:
			_gun_local_next = Soldier._now() + 60.0 / float(info.rpm)
			request_gun.rpc_id(1, gun_direction(me))
	_hud = me.player_input.hud
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
	parts.append({"text": "Fuel %d L" % roundi(fuel_litres()), "style": &""})
	for z: StringName in [ZONE_ENGINE, ZONE_WHEELS, ZONE_HULL]:
		var h := zone_health(z)
		if h < 0.999:
			parts.append({"text": "%s %d%%" % [VehicleService.zone_name(z, kind).capitalize(), roundi(h * 100.0)], "style": &"warn" if h < 0.35 else &""})
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
func to_save() -> Dictionary:
	var p := global_position if is_inside_tree() else _spawn_xform.origin
	var q := (global_basis if is_inside_tree() else _spawn_xform.basis).get_rotation_quaternion()
	var zones_out := {}
	for z: StringName in _zones:
		zones_out[String(z)] = float(_zones[z])
	return {"id": vehicle_id, "model": model, "scheme": scheme, "faction": String(faction), "wrecked": wrecked,
		"pos": [p.x, p.y, p.z], "rot": [q.x, q.y, q.z, q.w], "zones": zones_out, "fuel": fuel, "burning": burning_s,
		"battery": battery_ok, "salvaged": salvaged, "leak": _leak, "carves": net_carves.duplicate(true),
		"cargo": cargo_hold.net_state.duplicate(true) if cargo_hold else {}, "bodies": _body_uids()}


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
