class_name Soldier
extends CharacterBody3D
## A soldier body, driven either by a human or by AI.
##
## Human: the node is named after its peer id; that peer simulates movement (replicated by
## Sync) and its PlayerInput child reads mouse and keys. AI: the node has a non-numeric
## name, is owned by the host, and a SquadAI child fills in the intent fields below.
## Either way, anything that changes shared state (pickups, shots, drops, treatments) is a
## request to the host, which validates it and lets ServerSync carry the result back.
##
## The body is split across child nodes so separate work doesn't collide:
## - Movement (SoldierMovement): walking, stances, lean, weapon mount, stamina, speed costs.
## - PlayerInput: the human driver (input, camera, view model, crosshair target, HUD).
## - This file: shared state, weapon spread and recoil, carrying, death, and every
##   host-side request (the `_server_*` functions that players and AI both call).

const REVIVE_RANGE := 2.5
const HITBOX_MASK := 1 << 1
const INTERACT_RANGE := 2.2
## Furthest the view tilts up or down (about 83 degrees): stopping short of straight up
## keeps the head's Euler angles unique, so the view can't flip over behind you.
const MAX_PITCH := 1.45
## Carried mass below this costs no speed; at MAX_LOAD_KG you are at the slowest. The load
## tiers between (burdened, overloaded, critical) and their sources are in MovementRules.
const FREE_LOAD_KG := MovementRules.BURDENED_KG
const MAX_LOAD_KG := MovementRules.MAX_LOAD_KG
const MIN_LOAD_MULT := MovementRules.MIN_LOAD_MULT
## The AI's cone (ai_spread_direction): aimed, it is this fraction of the weapon's
## "ai_spread_deg"; moving and jumping widen it (the AI's accuracy as it was before P0362).
const ADS_SPREAD_MULT := 0.12
## A player's shots (_spread_direction, Captain, P0362: "the spread is bad for the ranges and
## unrealistic"): the weapon's own "spread_deg" is its mechanical cone (about 1-2 MOA for a
## rifle), and the shooter adds the rest, in degrees of half-angle: from the hip, aimed (the
## trigger press; sway is seen, not random: aim_sway), at walking pace and faster (up to 1.5x
## walk), in the air, and per unit of recoil heat (recent shots, x the weapon's recoil_deg).
## Stance, a rested weapon, the settle after a stop and wounds scale the shooter's part only.
const SHOOTER_HIP_DEG := 2.0
const SHOOTER_AIMED_DEG := 0.01
const SHOOTER_MOVE_AIMED_DEG := 0.8
const SHOOTER_MOVE_HIP_DEG := 1.5
const SHOOTER_AIR_DEG := 3.0
const SHOOTER_HEAT_DEG := 0.25
## Recoil heat: +1 a shot, falling off this fast (per second, exponential): gone in about a
## second, so deliberate aimed shots stay tight and auto fire blooms.
const RECOIL_HEAT_DECAY := 4.0
## Recoil (Captain, P0362): the view kicks up by the full kick and this share of it settles
## back (PlayerInput._settle_recoil), so follow-up shots and auto fire climb by the rest.
const RECOIL_SETTLE := 0.6
## Weapon sway when aimed (aim_sway): a slow drift of the aim point, degrees at its widest,
## standing still and fresh; stance and a rest scale it (SoldierMovement.spread_mult), moving
## adds up to SWAY_MOVE_MULT x walk pace more, an empty stamina bar SWAY_TIRED_MULT more, and
## wounds (Vitals.sway_mult).
const SWAY_DEG := 0.06
const SWAY_MOVE_MULT := 3.0
const SWAY_TIRED_MULT := 1.5
const BULKY_SPEED_MULT := 0.7
const ITEM_MASK := 1 << 2
## Camo variants for players, picked from the peer id so every peer agrees.
const PLAYER_VARIANTS: Array[String] = ["multicam", "woodland", "desert", "urban"]
## What a player respawns with (handoff): an M4 (loaded) and 2 spare magazines plus 90 loose
## rounds (Captain confirmed they're loose), a smoke and a frag.
const DEFAULT_KIT: Array = [[&"m4a1", 1], [&"mag_556", 2], [&"rounds_556", 90], [&"smoke_grenade", 1], [&"frag_grenade", 1]]
## Loading magazines from loose rounds (_server_load_mags): seconds per round (proposed:
## 1 s per 5 rounds), and how far you can move before it stops.
const LOAD_ROUND_S := 0.2
const LOAD_MOVE_M := 0.5
const THROW_SPEED := 15.0
## Physics layer of soldier bodies ("movers").
const BODY_LAYER := 1 << 4
const THROW_BUSY_S := 0.7
## Host: how far fire requests may arrive bunched together (network delay and jitter) and
## still count, with the weapon's rate kept over time (audit L10-01: a fixed 30 ms tolerance
## dropped correctly paced shots under 150 ms jitter). After a pause, at most
## 1 + FIRE_BUNCH_S x rate shots land at once (2 at 750 rpm).
const FIRE_BUNCH_S := 0.15
## Dead bodies (AI and players alike) stay in the world in this group (host only), lying,
## gear and all: lootable, carriable, saved with the zone. See "Death and bodies".
const DEAD_GROUP := &"dead_bodies"
## Proposed: at most this many dead bodies per zone; past it the oldest one goes (its gear
## drops where it lay).
const MAX_BODIES := 12

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var view_model: Node3D = $Head/Camera/ViewModel
@onready var model: CharacterModel = $Model
@onready var inventory: Inventory = $Inventory
@onready var vitals: Vitals = $Vitals
@onready var gear: GearRig = $Gear
@onready var movement: SoldierMovement = $Movement
@onready var player_input: PlayerInput = $PlayerInput

var active_slot: StringName = &"primary"
## Owner-driven, replicated so others see the reload pose.
var is_reloading := false
## Owner-driven (players: the aim key; AI: SquadAI), replicated so everyone sees the rifle
## shouldered.
var is_aiming := false
## Speed multiplier from the load (MovementRules.load_speed_mult) and a bulky item in the hands.
var load_mult := 1.0
## Kg carried (Inventory.total_mass), on every peer from the replicated inventory: sets the load
## tier (load_tier).
var load_kg := 0.0
## The local player's HUD (null for everyone else). Lives on PlayerInput.
var _hud: Hud:
	get:
		return player_input.hud if player_input else null
var _next_shot := 0.0         # owner-side fire-rate gate
## Recoil heat (shots, decaying at RECOIL_HEAT_DECAY) as of _heat_at; the player's, owner side.
var recoil_heat := 0.0
var _heat_at := 0.0
## View pitch (radians) still to settle back after recoil (PlayerInput._settle_recoil).
var recoil_return := 0.0
var _busy_until := 0.0        # owner-side: reloading or using a medkit
var _server_next_shot := 0.0  # host-side check
var _server_busy_until := 0.0
var _reload_n := 0  # host: counts reloads and deaths; a reload finishes only if it's still the latest (audit L3-02)
## Host only: loading magazines from loose rounds (_server_load_mags). Bumping _load_run
## stops the one in progress.
var loading_mags := false
var _load_run := 0
## Host: when this body last fired (Soldier._now()), and whether through a suppressor (Spotting:
## a muzzle flash gives a shooter away).
var last_shot_at := -1000.0
var last_shot_suppressed := false

## "friendly" (players and their squad) or "hostile". Set before the body enters the tree.
@export var faction := &"friendly"
## Camo for AI bodies (players get theirs from the peer id). Set before entering the tree.
@export var variant := ""
## Body type for this soldier's model (VoxelArt.BODIES; "" is male). Set before entering the tree.
@export var body := ""
## AI intent, written by SquadAI on the host each physics frame. move_input is like
## Input.get_vector: x strafes right, y < 0 moves forward, in the body's own frame.
var move_input := Vector2.ZERO
var want_sprint := false
var want_crouch := false
var want_aim := false
## AI stance intent: a SoldierMovement.Stance, or -1 to follow want_crouch.
var want_stance := -1
## Owner-side: fire-selector position per weapon, keyed "slot:item id" ("semi", "auto").
var _fire_modes := {}
## Host only: who is dragging or carrying this body while it is down.
var carried_by: Soldier
## Host only: the downed body this one is dragging or carrying.
var carrying: Soldier
## Every peer: this body's ragdoll while it lies as one (_update_ragdoll), else null.
var ragdoll: Ragdoll
## Host only (AI): seconds left blinded by a flashbang.
var stunned_s := 0.0
## Host only (AI): 0..1, how pinned down rounds landing close have made this soldier.
var suppression := 0.0
## Host only (AI): where incoming fire last came from, and when.
var threat_pos := Vector3.ZERO
var threat_time := -1000.0
## Host only. An AI soldier bled out or was killed (permadeath: it never gets up again). Its
## body stays in the world (DEAD_GROUP), gear and all, until the body cap removes it.
signal died_for_good(soldier: Soldier)
## The active weapon or the carried load changed (the view model follows it).
signal loadout_changed

## Owner-side (human): position the host sent while someone drags or carries us.
var carried_by_pos: Variant = null
## Host only: the squadmate who has claimed this body while it is down.
var care_by: Soldier
## Host only: the AI going through this dead body's gear (SquadAI's SCAVENGE), one at a time.
var scavenged_by: Soldier
## Host only: battle buddy. Buddies look after each other first and never bound at the same time.
var buddy: Soldier
## AI: what it's doing, in a few words (replicated for the squad HUD).
var ai_status := ""
## Squad structure, set by the host (CompoundLevel.rebalance_squad, Squad) and replicated by
## ServerSync: role id (Roles), fire team (0 = A, 1 = B, -1 none), slot in the 8-slot squad
## (-1 none) and Arma-style colour team ("" = white).
var role: StringName = &""
var fire_team := -1
var squad_slot := -1
var color_team := ""
## Shoots from the left shoulder (Handedness). Set by the host (a player's pick, an AI's roll)
## and replicated by ServerSync; the model mirrors the weapon holds.
var left_handed := false
## An AI soldier's surname and nationality (Names), set by the host when it spawns and
## replicated by ServerSync. display_name() shows the name; the node keeps its callsign.
var person_name := ""
var nation := ""
## Where the host put this body when it spawned (the level's _add_player), sent with the spawn
## by ServerSync. A client's own player is placed there as it spawns: its position is the
## owner's to replicate, so the host's spawn doesn't carry it and it would start at the
## level's origin (and the host would see it jump there).
var spawn_position := Vector3.ZERO
## Host only: when this body died (Soldier._now()), for the body cap; -1 while alive.
var died_at := -1.0
## Host only (tests may lower it): the body cap in force.
static var body_cap := MAX_BODIES
## Host only. People (wave 4, PeopleLayer): a cuffed captive can be carried while conscious.
var carriable_while_up := false
## Every peer: the vehicle this soldier rides in (wave 5: Vehicle sets it from its replicated
## seats), or null. While riding, the seat moves the body: no walking, no ragdoll.
var vehicle: Vehicle = null


func _enter_tree() -> void:
	set_multiplayer_authority(owner_peer())
	# Health, armor and inventory stay host-owned even though the owner drives the body.
	$ServerSync.set_multiplayer_authority(1)
	if is_ai():
		$Model.variant = variant if variant != "" else "woodland"
	else:
		$Model.variant = PLAYER_VARIANTS[absi(name.to_int() - 1) % PLAYER_VARIANTS.size()]  # host gets the first
	$Model.body = body if body != "" else VoxelArt.MALE


## Human bodies are named after their peer id; AI bodies have any other name.
func is_ai() -> bool:
	return not String(name).is_valid_int()


## The peer that drives this body: its player, or the host for AI.
func owner_peer() -> int:
	return 1 if is_ai() else name.to_int()


## Host only. Rounds landing close (or a blast) make AI keep its head down; also tells it
## roughly where the fire is coming from.
func suppress(amount: float, from: Vector3) -> void:
	suppression = minf(suppression + amount, 1.0)
	threat_pos = from
	threat_time = _now()


## Host only. A flashbang went off in sight.
func stun(seconds: float, from: Vector3) -> void:
	stunned_s = maxf(stunned_s, seconds)
	threat_pos = from
	threat_time = _now()


func _ready() -> void:
	add_to_group(&"combatants")
	if is_local() and not multiplayer.is_server() and spawn_position != Vector3.ZERO:
		position = spawn_position  # see spawn_position
	inventory.changed.connect(_on_inventory_changed)
	vitals.died.connect(_on_died)
	vitals.went_down.connect(_on_went_down)
	_add_voxel_viewer()
	_on_inventory_changed()
	print("[%s] %s spawned on peer %d (local: %s)" % ["ai" if is_ai() else "player", name, multiplayer.get_unique_id(), is_local()])


## True for the human player on their own machine.
func is_local() -> bool:
	return is_multiplayer_authority() and not is_ai()


func active_weapon() -> ItemData:
	var id: StringName = inventory.slots.get(active_slot, &"")
	return ItemDB.get_item(id) if id != &"" else null


## The fire modes a weapon's selector has, from its "fire_modes" stat ("semi", "auto").
static func fire_modes_of(weapon: ItemData) -> PackedStringArray:
	if weapon == null or weapon.type != "weapon":
		return PackedStringArray()
	if weapon.stats.has("fire_modes"):
		return PackedStringArray(weapon.stats.fire_modes)
	return PackedStringArray(["auto" if weapon.stats.get("auto", false) else "semi"])


## Owner-side: the active weapon's fire mode (its first listed mode until changed).
func fire_mode() -> String:
	var weapon := active_weapon()
	var modes := fire_modes_of(weapon)
	if modes.is_empty():
		return ""
	var mode: String = _fire_modes.get("%s:%s" % [active_slot, weapon.id], modes[0])
	return mode if mode in modes else modes[0]


## Owner-side (F): moves the active weapon's selector to its next mode and returns it.
func cycle_fire_mode() -> String:
	var weapon := active_weapon()
	var modes := fire_modes_of(weapon)
	if modes.is_empty():
		return ""
	var mode := modes[(modes.find(fire_mode()) + 1) % modes.size()]
	_fire_modes["%s:%s" % [active_slot, weapon.id]] = mode
	return mode


## Whether the trigger sends a shot this frame: auto fires while held, semi once per pull.
static func trigger_fires(mode: String, held: bool, just_pressed: bool) -> bool:
	return held if mode == "auto" else just_pressed


func _add_voxel_viewer() -> void:
	# Local player loads visuals and collision; the host also needs collision around
	# remote players and AI for movement checks and ballistics.
	if not is_local() and not multiplayer.is_server():
		return
	var viewer := VoxelViewer.new()
	viewer.view_distance = VoxelWorld.VIEW_DISTANCE
	viewer.requires_visuals = is_local()
	viewer.requires_collisions = true
	add_child(viewer)


## Where the crosshair meets the world (up to 150 m), or null. Local player only.
func crosshair_ground() -> Variant:
	return player_input.crosshair_ground()


## Switches the active weapon slot (owner-side; active_slot is replicated).
func select_weapon(slot: StringName) -> void:
	active_slot = slot
	_on_inventory_changed()


func _process(_delta: float) -> void:
	# Runs on every peer: active_slot, inventory and head rotation are replicated.
	model.look_pitch = head.rotation.x
	model.reloading = is_reloading
	model.aiming = is_aiming
	model.left_handed = left_handed
	model.name_tape = person_name.to_upper()
	movement.apply_pose()  # model pose, hitbox pose and capsule from the replicated stance
	if is_local() or (is_ai() and multiplayer.is_server()):
		# Breathing quickens and deepens as the legs tire (stamina is the owner's, so other peers
		# see the resting breath).
		var tired := 1.0 - movement.stamina
		model.breath_rate = lerpf(1.0, MovementRules.ANIM_BREATH_RATE_WINDED, tired)
		model.breath_depth = lerpf(1.0, MovementRules.ANIM_BREATH_DEPTH_WINDED, tired)
	_update_ragdoll()
	if vitals.is_up() or vitals.is_dead():
		_down_since = -1.0
	elif _down_since < 0.0:
		_down_since = _now()  # the give-up clock (can_give_up)
	if not is_ai():
		_apply_respawn_state()
	CharacterModel.lay_down(self, model, not vitals.is_up())
	if collision_layer != 0 and is_ai() and vitals.is_dead():
		collision_layer = 0  # a dead body lies where it fell and doesn't block anyone
	if collision_layer != 0 and not multiplayer.is_server() \
			and StringName(model.carry_net.get("mode", &"")) in [CharacterModel.CARRIED, CharacterModel.DRAGGED]:
		# Carried or dragged, from the replicated state: a player who joined after the lift
		# missed the _client_lifted event and would see a solid body (audit L2-02).
		collision_layer = 0
	if not vitals.is_up():
		model.hold = CharacterModel.Hold.NONE
	elif inventory.hands == &"" and active_slot == Launchers.SLOT and active_weapon() != null:
		model.hold = CharacterModel.Hold.NONE  # the launcher on the shoulder is LauncherRig's (wave 5)
	elif inventory.hands != &"" or (active_weapon() != null and active_slot == &"primary"):
		model.hold = CharacterModel.Hold.BOTH
	elif active_weapon() != null:
		model.hold = CharacterModel.Hold.RIGHT
	else:
		model.hold = CharacterModel.Hold.NONE


func _physics_process(delta: float) -> void:
	if is_ai():
		if multiplayer.is_server():
			_ai_physics(delta)
		return
	if multiplayer.is_server():
		_update_carried(delta)  # a player carrying or dragging someone: the host moves the casualty
	if not is_local():
		return
	if not vitals.is_up() and carried_by_pos != null:
		# Being dragged or carried: the host tells us where we are.
		global_position = carried_by_pos
		velocity = Vector3.ZERO
		carried_by_pos = null
		return
	if is_instance_valid(vehicle):
		velocity = Vector3.ZERO
		return  # riding: the seat moves the body (Vehicle)
	if respawn_state == RESPAWN_WAITING:
		velocity = Vector3.ZERO
		return  # dead, waiting to respawn: no moving (the host puts us back in)
	movement.step(delta)
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	# PlayerInput's own physics step follows: aim, fire, crosshair target, HUD.


func is_crouching() -> bool:
	return movement.is_crouching()


## Every peer: a body that's down (unconscious) or dead and not carried or dragged lies as a
## ragdoll (Ragdoll): the host simulates it, the others follow its replicated pose with colliders of
## their own. Its capsule stands aside meanwhile (layer 0); back up, carried or dragged, the
## ragdoll goes.
func _update_ragdoll() -> void:
	var want: bool
	if multiplayer.is_server():
		var lifted := is_instance_valid(carried_by) \
			or StringName(model.carry_net.get("mode", &"")) in [CharacterModel.CARRIED, CharacterModel.DRAGGED]
		want = Ragdoll.enabled and not vitals.is_up() and not lifted and not is_instance_valid(vehicle)  # no ragdoll in a seat
	else:
		want = model.ragdolled() and not vitals.is_up()
	if want and not is_instance_valid(ragdoll):
		ragdoll = Ragdoll.start(self) if multiplayer.is_server() else Ragdoll.follow(self)
		collision_layer = 0
	elif not want and is_instance_valid(ragdoll):
		# Not right after a respawn: the player is at the spawn point, not getting up where they lay.
		var spot: Variant = ragdoll.rest_spot() if (is_ai() or is_multiplayer_authority()) and _now() >= _respawned_until else null
		ragdoll.stop()
		ragdoll = null
		_stand_where_ragdoll_lay(spot)
		if vitals.is_up() or (not vitals.is_dead() and not is_instance_valid(carried_by) \
				and not StringName(model.carry_net.get("mode", &"")) in [CharacterModel.CARRIED, CharacterModel.DRAGGED]):
			collision_layer = BODY_LAYER


## The ragdoll gone (back up, or lifted), the body is where it lay, not where it fell (it can
## slide or roll metres from the capsule): `spot` is Ragdoll.rest_spot, null to stay put (no safe
## ground near, or not ours to move). Whoever owns the body's position moves it: the host an AI's,
## a player's own machine theirs (the host's copy follows the sync). Other peers move an AI at
## once too, from the same pose, so it doesn't stand up where it fell until the host's position
## arrives. A player keeps their own view's facing; an AI faces the way it got up.
func _stand_where_ragdoll_lay(spot: Variant) -> void:
	if spot == null:
		return
	var t: Transform3D = spot
	global_position = t.origin
	velocity = Vector3.ZERO
	if is_ai():
		rotation = Vector3(0.0, t.basis.get_euler().y, 0.0)



## Host only: an AI body moves from its intent, and a downed one follows whoever carries it.
func _ai_physics(delta: float) -> void:
	stunned_s = maxf(stunned_s - delta, 0.0)
	suppression = move_toward(suppression, 0.0, delta * 0.25)
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	if (not vitals.is_up() or carriable_while_up) and is_instance_valid(carried_by):
		if carried_by.carry_holds():
			global_transform = carried_by.carry_transform()
		velocity = Vector3.ZERO
		return
	if is_instance_valid(ragdoll):
		velocity = Vector3.ZERO
		return  # the ragdoll holds the body: the capsule stays where it fell until it goes (_update_ragdoll)
	if is_instance_valid(vehicle):
		velocity = Vector3.ZERO
		return  # riding: the seat moves the body (Vehicle)
	is_aiming = want_aim and vitals.is_up() and not is_reloading and inventory.hands == &"" and carrying == null
	movement.step(delta)
	_update_carried(delta)


## Speed multiplier for moving a downed body (1 when not carrying or dragging). Reads
## carry_mode, so it works on the owner's machine too.
func carry_speed_mult() -> float:
	if carry_mode != &"" and _now() < carry_busy_until:
		return 0.0  # picking them up or putting them down
	match carry_mode:
		CARRY:
			return CARRY_SPEED_MULT
		DRAG:
			return DRAG_SPEED_MULT
	return 1.0


## Where a body this soldier moves goes: over the shoulder when carried, on the ground
## behind when dragged.
func carry_transform() -> Transform3D:
	if carry_mode == DRAG:
		return global_transform * Transform3D(Basis(Vector3.UP, PI), DRAG_OFFSET)
	return global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.55, 0.15))


## Host: whether the body this soldier moves is in the hold (on the shoulder, or dragged), so
## it goes where they go; not while it's still being picked up or taken hold of, nor while
## it's being put down.
func carry_holds() -> bool:
	return _carry_phase == &""


## Host only. Keeps a carried body (AI or human) with this soldier, and ends a pick-up or
## put-down when its time is up.
func _update_carried(delta: float) -> void:
	if carrying == null:
		return
	if not is_instance_valid(carrying) or not _movable(carrying) or carrying.carried_by != self or not vitals.is_up():
		release_carried()
		return
	_carry_phase_left -= delta  # game time, like the animation it ends
	if _carry_phase != &"" and _carry_phase_left <= 0.0:
		if _carry_phase == &"lower":
			release_carried()
			return
		_carry_phase = &""  # up on the shoulder, or got hold: from here they come along
		CharacterModel.server_carry(self, carrying, carry_mode)  # a plain hold (late joiners don't replay the lift)
	if carry_holds() and not carrying.is_ai():
		carrying._client_carried.rpc_id(carrying.owner_peer(), carry_transform().origin)


## Host only. Picks up (CARRY) or takes hold of (DRAG) a downed body within `reach`.
## Dead bodies can be carried and dragged too.
func server_pick_up_body(other: Soldier, mode := CARRY, reach := REVIVE_RANGE) -> bool:
	if other == null or other == self or other.is_queued_for_deletion() or not _movable(other):
		return false
	if carrying != null or inventory.hands != &"" or not vitals.is_up():
		return false
	if other.body_point().distance_to(global_position) > reach:
		return false
	if is_instance_valid(other.carried_by) and other.carried_by != self:
		return false
	other.carried_by = self
	other._client_lifted.rpc(true)  # a moved body mustn't shove its carrier around
	carrying = other
	_set_carry_mode(mode, &"lift" if mode == CARRY else &"grab")
	return true


## A body that can be carried or dragged: down or dead, or a cuffed captive (People).
static func _movable(other: Soldier) -> bool:
	return not other.vitals.is_up() or other.carriable_while_up


## Host only. Puts down whoever this soldier carries, the way a squadmate would: off the
## shoulder onto the ground in front over CARRY_LOWER_S, standing still (the body already lies
## where it's going, so nothing waits on the animation), then lets go. A dragged body is let go
## at once. For anything that can't wait (the carrier hit, a vehicle, a teleport) use
## release_carried.
func server_put_down() -> void:
	if carrying == null or _carry_phase == &"lower":
		return
	if carry_mode != CARRY or not is_instance_valid(carrying):
		release_carried()
		return
	var spot := _put_down_spot()
	if carrying.is_ai():
		carrying.global_position = spot
		carrying.rotation = Vector3(0, rotation.y, 0)
	else:
		carrying._client_carried.rpc_id(carrying.owner_peer(), spot)
	_set_carry_mode(CARRY, &"lower")


## Where a body put down off the shoulder lies: in front of the carrier.
func _put_down_spot() -> Vector3:
	return global_position - global_basis.z * 0.8


## Host only. Lets go of whoever this soldier carries or drags, at once.
func release_carried() -> void:
	if is_instance_valid(carrying) and carrying.carried_by == self:
		carrying.carried_by = null
		carrying._client_lifted.rpc(false)
		CharacterModel.server_carry(null, carrying, &"")  # the casualty's pose, for every peer
		if carrying.is_ai():
			if carry_mode != DRAG and _carry_phase != &"lower":  # a dragged or lowered body is already on the ground
				carrying.global_position = _put_down_spot()
			carrying.rotation = Vector3(0, rotation.y, 0)
	carrying = null
	_set_carry_mode(&"")


## The AI's weapon cone in degrees: "ai_spread_deg", else "spread_deg".
static func ai_spread_deg(weapon: ItemData) -> float:
	return float(weapon.stats.get("ai_spread_deg", weapon.stats.get("spread_deg", 1.0)))


## A player's shot direction (Captain, P0362), worked out on the shooter's machine (co-op: the
## host trusts it): inside the half-angle spread_deg_now(), uniform over the cone's disc.
func _spread_direction(weapon: ItemData) -> Vector3:
	var spread := deg_to_rad(spread_deg_now(weapon))
	var forward := -camera.global_basis.z
	var angle := randf() * TAU
	var amount := sqrt(randf()) * spread
	var offset := camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle)
	return (forward + offset * tan(amount)).normalized()


## A player's cone right now, degrees of half-angle: the weapon's mechanical spread_deg plus
## the shooter's part (SHOOTER_*): hip or aimed, moving, airborne and recoil heat, scaled by
## stance, a rest, the settle after a stop and wounds.
func spread_deg_now(weapon: ItemData) -> float:
	var shooter := SHOOTER_AIMED_DEG if is_aiming else SHOOTER_HIP_DEG
	var horizontal := Vector2(velocity.x, velocity.z).length()
	shooter += (SHOOTER_MOVE_AIMED_DEG if is_aiming else SHOOTER_MOVE_HIP_DEG) * clampf(horizontal / SoldierMovement.WALK_SPEED, 0.0, 1.5)
	shooter += heat_now() * float(weapon.stats.get("recoil_deg", 0.6)) * SHOOTER_HEAT_DEG
	if not is_on_floor():
		shooter += SHOOTER_AIR_DEG
	else:
		shooter *= movement.spread_mult()  # stance, mounted weapon, settle after a stop
	shooter *= vitals.sway_mult(weapon.tags.has("rifle"))  # wounds, blood loss and pain (a broken collarbone: rifles only)
	return float(weapon.stats.get("spread_deg", 0.05)) + shooter


## Recoil heat now (shots, decayed since the last one).
func heat_now() -> float:
	return recoil_heat * exp(-RECOIL_HEAT_DECAY * maxf(_now() - _heat_at, 0.0))


## Aimed weapon sway (Captain, P0362): how far the aim point drifts, degrees at its widest
## (SWAY_*). None from the hip: the hip cone is wide enough.
func aim_sway_deg(weapon: ItemData) -> float:
	if not is_aiming or weapon == null:
		return 0.0
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / SoldierMovement.WALK_SPEED, 0.0, 1.5)
	var tired := 1.0 - clampf(minf(movement.stamina, movement.arm_stamina), 0.0, 1.0)  # out of breath, or tired arms
	return SWAY_DEG * movement.spread_mult() * (1.0 + SWAY_MOVE_MULT * moving) * (1.0 + SWAY_TIRED_MULT * tired) \
		* vitals.sway_mult(weapon.tags.has("rifle"))


## Breathing in the aim (MovementRules.BREATH_*), degrees at its widest: bigger with tired arms
## and out of breath, scaled by stance, a rest and wounds like the sway. 0 unaimed.
func breath_sway_deg(weapon: ItemData) -> float:
	if not is_aiming or weapon == null:
		return 0.0
	return MovementRules.BREATH_SWAY_DEG * movement.spread_mult() * vitals.sway_mult(weapon.tags.has("rifle")) 		* (1.0 + MovementRules.BREATH_ARMS_GAIN * (1.0 - movement.arm_stamina) + MovementRules.BREATH_LEGS_GAIN * (1.0 - movement.stamina))


## The sway's offset (pitch, yaw in radians) at time `t` seconds: a slow, wandering figure of
## eight, at most aim_sway_deg() across, plus the breath rising and falling
## (SoldierMovement.breath_phase); holding the breath steadies both, gasping after makes them
## worse (SoldierMovement.breath_sway_mult).
func aim_sway(weapon: ItemData, t: float) -> Vector2:
	var amp := deg_to_rad(aim_sway_deg(weapon))
	var drift := Vector2(sin(t * 1.3) * 0.8 + sin(t * 0.55 + 1.7) * 0.2, sin(t * 0.7 + 0.4) * 0.8 + sin(t * 1.9) * 0.2) * amp
	var breath := Vector2(sin(movement.breath_phase), sin(movement.breath_phase * 0.5) * 0.25) * deg_to_rad(breath_sway_deg(weapon))
	return (drift + breath) * movement.breath_sway_mult()


## The AI's shot direction (SquadAI._shoot): the weapon's "ai_spread_deg" cone, tighter aimed,
## wider moving or airborne: the numbers the AI used before the player's spread was made
## realistic (Captain, P0362), so its accuracy is unchanged (its aim error comes on top).
func ai_spread_direction(weapon: ItemData) -> Vector3:
	var spread := deg_to_rad(ai_spread_deg(weapon))
	if is_aiming:
		spread *= ADS_SPREAD_MULT
	var horizontal := Vector2(velocity.x, velocity.z).length()
	spread *= 1.0 + clampf(horizontal / SoldierMovement.WALK_SPEED, 0.0, 1.5)
	spread *= vitals.sway_mult(weapon.tags.has("rifle"))  # wounds, blood loss and pain (a broken collarbone: rifles only)
	if not is_on_floor():
		spread *= 2.5
	else:
		spread *= movement.spread_mult()  # stance, mounted weapon, settle after a stop
	var forward := -camera.global_basis.z
	var angle := randf() * TAU
	var amount := sqrt(randf()) * spread  # uniform over the cone's disc
	var offset := camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle)
	return (forward + offset * tan(amount)).normalized()


## Sets the view's up/down tilt, clamped to MAX_PITCH. The head only pitches and rolls
## (lean); yaw belongs to the body (but see view_yaw), so the rotation is rebuilt rather than
## rotated, which would let lean roll leak into yaw until the view swung round behind the body.
func set_pitch(pitch: float) -> void:
	head.rotation = Vector3(clampf(pitch, -MAX_PITCH, MAX_PITCH), view_yaw(), head.rotation.z)


## The view's turn from the body's facing: dragging, the body walks away from the casualty
## while the view (and the drawn dragger, CharacterModel.DRAG_POSE) faces it, Arma-style.
func view_yaw() -> float:
	return PI if carry_mode == DRAG else 0.0


## Recoil: the view kicks up and a little sideways; aiming halves it. RECOIL_SETTLE of the
## climb settles back (PlayerInput._settle_recoil), and the shot adds recoil heat (P0362).
func _kick(weapon: ItemData) -> void:
	var kick := deg_to_rad(float(weapon.stats.get("recoil_deg", 0.6))) * (0.5 if is_aiming else 1.0)
	kick *= movement.recoil_mult()  # stance and mounted weapon
	set_pitch(head.rotation.x + kick)
	rotate_y(randf_range(-0.35, 0.35) * kick)
	recoil_return += kick * RECOIL_SETTLE
	recoil_heat = heat_now() + 1.0
	_heat_at = _now()


## How long reloading `weapon` takes this body: the weapon's time, slowed by wounds
## (a broken arm).
func reload_seconds(weapon: ItemData) -> float:
	return float(weapon.stats.get("reload_s", 2.0)) * vitals.reload_mult()


## aim_point's chest shape, found once and kept while it's still this body's (every AI scan asks).
var _chest_shape: CollisionShape3D


## Where to aim at this body: the middle of its chest hitbox, wherever its stance put it.
func aim_point() -> Vector3:
	if not is_instance_valid(_chest_shape) or _chest_shape.get_parent() == null or _chest_shape.get_parent().get_parent() != self:
		_chest_shape = null
		for child in get_children():
			if child is Area3D and child.get_meta(&"body_part", &"") == Vitals.CHEST:
				for shape in child.get_children():
					if shape is CollisionShape3D:
						_chest_shape = shape
						break
				if _chest_shape:
					break
	if _chest_shape:
		return _chest_shape.global_position
	return global_position + Vector3.UP * (1.0 if is_crouching() else 1.3)


## Where this soldier is, for reach checks: while it lies as a ragdoll, the ragdoll's chest
## (it can slide or roll metres from the capsule, which stays where it fell), else its origin.
func body_point() -> Vector3:
	return aim_point() if is_instance_valid(ragdoll) else global_position


static func _ammo_of(weapon: ItemData) -> StringName:
	return StringName(weapon.stats.get("ammo", ""))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## MovementRules.Tier for the load carried: what it may still do (sprint, jump) and how fast
## it tires.
func load_tier() -> int:
	return MovementRules.tier_of(load_kg)


func _on_inventory_changed() -> void:
	load_kg = inventory.total_mass()
	load_mult = MovementRules.load_speed_mult(load_kg) * (BULKY_SPEED_MULT if inventory.hands != &"" else 1.0)
	if active_weapon() == null:
		for slot: StringName in [&"primary", &"sidearm"]:
			if inventory.slots[slot] != &"":
				active_slot = slot
				break
	loadout_changed.emit()


# --- Host-side requests ---------------------------------------------------------------

func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == owner_peer()


## Whether a point a client sent can be used: finite (audit L6-01: a NaN origin made broken
## objects on every peer). A direction must also have a length.
static func usable_point(p: Vector3) -> bool:
	return p.is_finite()


static func usable_direction(d: Vector3) -> bool:
	return d.is_finite() and d.length_squared() > 0.000001


@rpc("any_peer", "call_local", "reliable")
func _server_fire(origin: Vector3, direction: Vector3, slot: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or inventory.hands != &"" or is_instance_valid(vehicle):  # riding: the seat's gun instead (Vehicle)
		return
	if not usable_point(origin) or not usable_direction(direction) or respawn_state == RESPAWN_WAITING:
		return
	var id: StringName = inventory.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	if weapon == null or weapon.type != "weapon":
		return
	var now := _now()
	if now < _server_next_shot or now < _server_busy_until - 0.1:
		return
	if not inventory.consume_round(slot):
		return
	server_end_spawn_protection()  # firing ends spawn protection
	stop_loading_mags("Stopped loading magazines")  # firing needs your hands
	# The weapon's rate holds over time, but shots the network delivered bunched up (paced
	# right when sent) still count: the schedule may run up to FIRE_BUNCH_S behind now.
	_server_next_shot = maxf(_server_next_shot, now - FIRE_BUNCH_S) + 60.0 / float(weapon.stats.get("rpm", 600))
	if origin.distance_to(camera.global_position) > 1.0:
		origin = camera.global_position  # don't trust a far-off muzzle
	var result := Ballistics.fire(self, origin, direction.normalized(), weapon)
	var suppressed := bool(weapon.stats.get("suppressed", false))
	last_shot_at = now
	last_shot_suppressed = suppressed
	var round_end: Variant = result.get("position")
	Sfx.server_shot(origin, round_end if round_end is Vector3 else origin + direction.normalized() * 400.0,
		"suppressed" if suppressed else ("pistol" if weapon.slot == &"sidearm" else "rifle"))  # every peer hears it (Sfx)
	PeopleLayer.server_noise(self, origin)  # people nearby hear it (wave 4)
	if faction != &"hostile":
		Alert.server_noise(self, origin, Alert.SHOT, suppressed)  # hot zones: the enemy hears it (4B part 3)
	SquadAI.server_heard_shot(self, origin, suppressed)  # the other side hears it (and half finds the shooter: Spotting)
	if result.result != "none":
		CompoundLevel.current(self).show_impact.rpc(result.position, result.normal, result.result)
	Throwables.server_gunfire(self)  # indoors, sustained fire muffles hearing


## A command from the command menu (CommandMenu) for the named squadmates (all if empty).
## Any player can command the friendly squad; that makes them its lead. Why it couldn't be
## given goes back to the player, and the squadmates answer it (SquadComms: "Copy, holding",
## "Can't, carrying Miller's body"; Captain, 2026-10-14).
@rpc("any_peer", "call_local", "reliable")
func _server_squad_command(cmd: String, point: Vector3, names: PackedStringArray) -> void:
	if not _from_owner() or is_ai() or not vitals.is_up() or not usable_point(point):
		return
	var squad := CompoundLevel.current(self).squad_for(faction)
	if squad == null:
		return
	var why := _squad_command(squad, cmd, point, names)
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
	SquadComms.heard(squad, self, cmd, names, why)


## Host: carries out squad command `cmd`; returns why it couldn't be given ("" if it was).
## "report" (Status > Report status) gives no order: the squadmates answer it (SquadComms).
func _squad_command(squad: Squad, cmd: String, point: Vector3, names: PackedStringArray) -> String:
	if cmd == "report":
		return ""
	var ordered_why := squad.order_command(self, cmd, point, names)  # the command menu's orders (queue 12)
	if ordered_why != "?":
		return ordered_why
	match cmd:
		"follow":
			squad.give_order(self, Squad.Order.FOLLOW, point, names)
		"hold":
			squad.give_order(self, Squad.Order.HOLD, point, names)
		"move":
			squad.give_order(self, Squad.Order.MOVE, point, names)
		"open_fire", "hold_fire":
			squad.set_hold_fire(self, cmd == "hold_fire", names)
		"throw_smoke", "throw_frag":
			if squad.order_throw(self, &"smoke_grenade" if cmd == "throw_smoke" else &"frag_grenade", point, names) == "":
				return "Nobody selected has one"
		"scavenge":
			return squad.order_scavenge(self, point, names)
		"scavenge_on", "scavenge_off":
			squad.set_scavenge(self, cmd == "scavenge_on", names)
		"mount", "dismount":  # wave 5: vehicles (VehicleLayer)
			var layer := VehicleLayer.of(self)
			return "No vehicles here" if layer == null else (layer.server_order_mount(self, point, names) if cmd == "mount" else layer.server_order_dismount(self, names))
		"fire_launcher":  # wave 5: a squadmate with a launcher fires at the vehicle there, or the spot
			if LauncherAI.order_squad(squad, self, point, names) == "":
				return "Nobody selected has a loaded launcher or rounds"
		_ when cmd.begins_with("support:"):  # wave 5b: helicopter supports and AAVs (Supports)
			return Supports.server_command(self, cmd, point, names)
		_:
			if not squad.command(self, cmd, point, names):  # formation, target, combat mode, team
				return "Can't target that" if cmd.begins_with("target:") else ("Can't escort that" if cmd.begins_with("escort:") else "Order not given")
	return ""


@rpc("any_peer", "call_local", "reliable")
func _server_throw(origin: Vector3, direction: Vector3, id: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or inventory.hands != &"" or _now() < _server_busy_until - 0.1 \
			or not usable_point(origin) or not usable_direction(direction) or respawn_state == RESPAWN_WAITING:
		return
	var item := ItemDB.get_item(id)
	if item == null or not item.stats.has("throwable") or not inventory.remove_one(id):
		return
	server_end_spawn_protection()  # throwing ends spawn protection too
	_server_busy_until = _now() + THROW_BUSY_S
	Sfx.server_play(&"throw", global_position + Vector3.UP * 1.4)
	if origin.distance_to(camera.global_position) > 1.0:
		origin = camera.global_position
	var dir := direction.normalized()
	var carried := velocity if velocity.is_finite() else Vector3.ZERO  # the owner replicates its own velocity
	CompoundLevel.current(self).server_throw(id, origin + dir * 0.5, carried + dir * THROW_SPEED + Vector3.UP * 2.0, self)


@rpc("any_peer", "call_local", "reliable")
func _server_reload(slot: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or _now() < _server_busy_until - 0.1:
		return
	var id: StringName = inventory.slots.get(slot, &"")
	if id == &"":
		return
	var seconds := reload_seconds(ItemDB.get_item(id))
	_server_busy_until = _now() + seconds
	Sfx.server_play(&"reload", global_position + Vector3.UP)
	_reload_n += 1
	var n := _reload_n
	var rev := inventory.slot_revision(slot)
	# The new magazine goes in when the reload finishes, if the same weapon is still there and
	# the soldier hasn't died since (a respawn's new rifle isn't the one being reloaded). The
	# same weapon, not just the same model: one dropped and another M4 picked up meanwhile has
	# a new slot revision (audit A2-02).
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree() and n == _reload_n and vitals.is_up() and inventory.slots.get(slot, &"") == id \
			and inventory.slot_revision(slot) == rev:
		inventory.reload(slot)


## Loads the carried part-used and empty magazines of the same calibre from loose
## `rounds_id` (inventory screen), fullest first: LOAD_ROUND_S per round, each round going
## in as its time comes. Moving more than LOAD_MOVE_M, firing or going down stops it;
## whatever went in so far stays loaded.
@rpc("any_peer", "call_local", "reliable")
func _server_load_mags(rounds_id: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or loading_mags or _now() < _server_busy_until - 0.1:
		return
	var item := ItemDB.get_item(rounds_id)
	if not Inventory.is_loose_rounds(item) or inventory.count_of(rounds_id) <= 0:
		_client_message.rpc_id(owner_peer(), "No loose rounds to load")
		return
	var total := inventory.loadable_rounds(rounds_id)
	if total <= 0:
		_client_message.rpc_id(owner_peer(), "No %s magazines to load" % Inventory.calibre_of(item))
		return
	_load_run += 1
	var run := _load_run
	loading_mags = true
	var start := global_position
	var started := _now()
	var loaded := 0
	_client_message.rpc_id(owner_peer(), "Loading magazines: %d rounds, %.0f s (moving or firing stops)" % [total, total * LOAD_ROUND_S])
	while true:
		await get_tree().create_timer(LOAD_ROUND_S).timeout
		if not is_inside_tree() or run != _load_run:
			return  # stopped: stop_loading_mags told the player why
		if not vitals.is_up():
			break
		if Vector2(global_position.x - start.x, global_position.z - start.z).length() > LOAD_MOVE_M:
			stop_loading_mags("Stopped loading magazines: you moved")
			return
		var due := mini(int((_now() - started) / LOAD_ROUND_S + 0.001), total) - loaded
		if due > 0:
			var n := inventory.load_rounds(rounds_id, due)
			loaded += n
			if n < due:
				break  # out of rounds or magazines
		if loaded >= total:
			break
	loading_mags = false
	_client_message.rpc_id(owner_peer(), "Loaded %d rounds" % loaded)


## Host only. Stops loading magazines, if this body is, and tells the player why.
func stop_loading_mags(why: String) -> void:
	if not loading_mags:
		return
	loading_mags = false
	_load_run += 1
	if why != "":
		_client_message.rpc_id(owner_peer(), why)


## The highest fall the host believes from a client (anything higher is still fatal).
const MAX_REPORTED_FALL_M := 60.0


## Owner side (SoldierMovement): landed after dropping `height` metres. The host applies it
## (Vitals.server_fall: nothing under 3 m).
func report_fall(height: float) -> void:
	if multiplayer.is_server():
		vitals.server_fall(height)
	else:
		_server_fell.rpc_id(1, height)


@rpc("any_peer", "call_local", "reliable")
func _server_fell(height: float) -> void:
	if _from_owner():
		vitals.server_fall(clampf(height, 0.0, MAX_REPORTED_FALL_M))


## Owner side (SoldierMovement): started to sprint, jumped, or set off under an extreme load.
## Only matters (and is only sent) while a chest wound is closed by surgery (it may reopen)
## or with blast lung (it strains, and a lung may give way).
func report_exertion() -> void:
	if not vitals.has_closed_chest() and not vitals.has_blast_lung():
		return
	if multiplayer.is_server():
		vitals.server_exert()
	else:
		_server_exert.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _server_exert() -> void:
	if _from_owner():
		vitals.server_exert()


## Shift+H (quick-treat): treats yourself with the next item you carry from your own care_needed() (a
## tourniquet before a bandage, and so on), through the same timed treatment as _server_treat.
@rpc("any_peer", "call_local", "reliable")
func _server_use_medical() -> void:
	if not _from_owner() or not vitals.is_up() or _is_busy():
		return
	var tasks := vitals.care_needed()
	if tasks.is_empty():
		_client_message.rpc_id(owner_peer(), "Nothing to treat")
		return
	var task := next_self_treatment()
	if task.is_empty():
		var first := ItemDB.get_item(tasks[0].item)
		if Vitals.needs_other_hands(first.id):
			_client_message.rpc_id(owner_peer(), "You need someone to place a line")
		else:
			_client_message.rpc_id(owner_peer(), "You have no %s" % first.name)
		return
	_treat(self, task.item, task.part, false)


## Inventory screen actions. `container`/`index` name a stowed entry; `slot` an equipped one.
@rpc("any_peer", "call_local", "reliable")
func _server_inventory_action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	model.server_inventory_action(inventory, action, container, index, slot, target)  # the hand's way
	match action:
		"drop_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				_client_message.rpc_id(owner_peer(), "Empty it first")
			else:
				_server_spawn_in_front(removed.id, 1, removed.state)
		"drop_entry":
			var list: Array = inventory.containers.get(container, [])
			if index >= 0 and index < list.size():
				var entry := inventory.remove_entry(container, index, list[index].count)
				_server_spawn_in_front(entry.id, entry.count, entry.get("state", {}))
		"move_entry":
			# As much of the stack as fits goes (a mag pouch takes two of a stack of five).
			var list: Array = inventory.containers.get(container, [])
			if index < 0 or index >= list.size() or target == container or not inventory.containers.has(target):
				return
			var item := ItemDB.get_item(list[index].id)
			var moving_state: Dictionary = list[index].get("state", {})
			var n := mini(int(list[index].count), inventory.room_for(target, item, moving_state))
			if n <= 0:
				_refuse(inventory.refusal(item, moving_state, target), item.id, moving_state)  # why, and where it fits (S2)
				return
			var entry := inventory.remove_entry(container, index, n)
			if not inventory.insert_entry(target, entry):
				inventory.insert_entry(container, entry)  # put it back
				_refuse(inventory.refusal(item, moving_state, target), item.id, moving_state)
		"equip_entry":
			var list: Array = inventory.containers.get(container, [])
			if index >= 0 and index < list.size() and Inventory.is_pack(ItemDB.get_item(list[index].id)) and inventory.slots[&"backpack"] != &"":
				_server_swap_pack(inventory.remove_entry(container, index))  # Captain: packs swap on equip
				return
			var problem := inventory.entry_fit_problem(container, index)  # before equip_entry moves it
			if not inventory.equip_entry(container, index):
				_client_message.rpc_id(owner_peer(), problem if problem != "" else "No free slot for that")
		"stow_slot":
			# Into `target` if one is named (dragged onto a container), else the first with room.
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				return
			var order: Array[StringName] = []
			if target != &"":
				order.append(target)
			order.append_array(Inventory.CONTAINERS)
			for c in order:
				if inventory.insert_entry(c, {"id": removed.id, "count": 1, "state": removed.state}):
					return
			inventory.take(removed.id, 1, removed.state)  # no room: straight back on
			var why := inventory.pack_problem(target if target != &"" else &"backpack", ItemDB.get_item(removed.id), removed.state)
			if why != "":
				_client_message.rpc_id(owner_peer(), why)
			else:
				_refuse(inventory.refusal(ItemDB.get_item(removed.id), removed.state, target), removed.id, removed.state)  # S2
		"roll_entry", "unroll_entry":
			var rolled := action == "roll_entry"
			var problem := inventory.roll_problem(container, index, rolled)
			if problem != "" or not inventory.set_rolled(container, index, rolled):
				_client_message.rpc_id(owner_peer(), problem if problem != "" else "Can't do that")
		# Optics (P0362): the optic entry at `container`/`index` onto the weapon in `slot` (the
		# one it had goes into your containers), or the weapon in `slot`'s optic off (into
		# `target` if named).
		"mount_optic":
			var problem := Optics.server_mount(inventory, container, index, slot)
			if problem != "":
				_client_message.rpc_id(owner_peer(), problem)
		"remove_optic":
			var problem := Optics.server_remove(inventory, slot, target)
			if problem != "":
				_client_message.rpc_id(owner_peer(), problem)
		# MOLLE: `target` (attach) and `slot` (detach, move, drop) name attach points of the
		# worn carrier; a pouch's contents go with it.
		"attach":
			var list: Array = inventory.containers.get(container, [])
			if index < 0 or index >= list.size():
				return
			var item := ItemDB.get_item(list[index].id)
			var point := target if target != &"" else inventory.free_point_for(item)
			var problem := inventory.attach_problem(item, point) if point != &"" else inventory.no_point_problem(item)
			if problem != "":
				_refuse(problem + inventory.where_else(item, list[index].get("state", {}), container), item.id, list[index].get("state", {}))  # S2: and where it fits
			elif not inventory.attach_entry(container, index, point):
				_client_message.rpc_id(owner_peer(), "Can't attach that")
		"detach":
			var entry := inventory.detach(slot)
			if entry.is_empty():
				return
			var order: Array[StringName] = []
			if target != &"" and not Inventory.is_pouch_container(target):
				order.append(target)
			order.append_array(Inventory.CONTAINERS)
			for c in order:
				if inventory.insert_entry(c, entry):
					return
			inventory.attach(slot, entry)  # no room: back on the carrier
			var detached := ItemDB.get_item(StringName(entry.id))
			_refuse(inventory.refusal(detached, entry.get("state", {}), order[0] if target != &"" and not Inventory.is_pouch_container(target) else &""),
				detached.id, entry.get("state", {}))  # S2
		"equip_attachment":  # a disposable launcher off the top of the pack, onto the shoulder
			var on_point := inventory.attachment(slot)
			if on_point.is_empty():
				return
			var gear := ItemDB.get_item(StringName(on_point.id))
			if inventory.equip_attachment(slot):
				return
			# One already on the shoulder that packs on that point too: they swap places.
			var worn := ItemDB.get_item(inventory.slots.get(gear.slot, &"")) if gear and gear.slot != &"" and inventory.slots.get(gear.slot, &"") != &"" else null
			if worn and Inventory.point_types(inventory.attach_point(slot)).any(func(t: String) -> bool: return t in worn.stats.get("attach", [])):
				var packed := inventory.detach(slot)
				var off := inventory.unequip(gear.slot)
				inventory.attach(slot, {"id": off.id, "state": off.state})
				inventory.take(packed.id, 1, packed.get("state", {}))
				return
			_client_message.rpc_id(owner_peer(), "Already carrying a %s" % InventoryScreen.SLOT_NAMES.get(gear.slot, String(gear.slot)).to_lower() if gear and gear.slot != &"" else "Can't equip that")
		"attach_slot":  # the launcher off the shoulder, packed on top of the pack (`target`, or the first free point it fits)
			var gear := ItemDB.get_item(inventory.slots.get(slot, &"")) if inventory.slots.get(slot, &"") != &"" else null
			if gear == null or not Inventory.is_attachable(gear):
				return
			var point := target if target != &"" else inventory.free_point_for(gear)
			var problem := inventory.attach_problem(gear, point) if point != &"" else inventory.no_point_problem(gear)
			if problem != "":
				_client_message.rpc_id(owner_peer(), problem)
				return
			var off := inventory.unequip(slot)
			inventory.attach(point, {"id": off.id, "state": off.state})
		"move_attachment":
			var att := inventory.attachment(slot)
			if att.is_empty():
				return
			var problem := inventory.attach_problem(ItemDB.get_item(StringName(att.id)), target)
			if problem != "" or not inventory.move_attachment(slot, target):
				_client_message.rpc_id(owner_peer(), problem if problem != "" else "Can't move that there")
		"drop_attachment":
			var entry := inventory.detach(slot)
			if not entry.is_empty():
				_server_spawn_in_front(entry.id, 1, entry.get("state", {}))


## A container's name for messages and the inventory screen: "Vest", "Backpack", or a
## pouch's ("Double M4 Mag Pouch").
func container_name(container: StringName) -> String:
	if Inventory.is_pouch_container(container):
		var pouch := inventory.pouch_item(container)
		return pouch.name if pouch else "that pouch"
	return String(container).capitalize()


@rpc("any_peer", "call_local", "reliable")
func _server_interact(path: NodePath) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var item := get_node_or_null(path) as WorldItem
	if item == null or item.is_queued_for_deletion():
		return
	if item.global_position.distance_to(global_position) > INTERACT_RANGE + 1.5:
		return
	if Inventory.is_pack(ItemDB.get_item(item.item_id)) and inventory.slots[&"backpack"] != &"":
		# Captain (P0164): picking up a pack swaps it for the one worn (dragging it into the
		# pack in the inventory screen stows it instead).
		var entry := {"id": item.item_id, "count": 1, "state": item.state.duplicate(true)}
		model.server_pick_up(item.global_position, item.item_id)
		GameState.item_taken(item.uid)
		item.queue_free()
		_server_swap_pack(entry)
		return
	var taken := inventory.take(item.item_id, item.count, item.state)
	if taken == 0:
		_refuse(inventory.refusal(ItemDB.get_item(item.item_id), item.state), item.item_id, item.state)  # S2: why, and the room there is
		return
	_server_took(item, taken)


## Inventory screen: the nearby item at `path` dragged onto container `into` (a pouch too)
## goes in there, not on the body: a pack dragged into the worn pack is stowed (empty, rolled
## if it's as big), never swapped for it (audit A2-07). The same reach as picking it up. A
## two-handed load (an objective case, a crate) is never stowed: it's picked up as a click
## does, into the hands.
@rpc("any_peer", "call_local", "reliable")
func _server_pick_up_into(path: NodePath, into: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var item := get_node_or_null(path) as WorldItem
	if item == null or item.is_queued_for_deletion() or not inventory.containers.has(into):
		return
	if item.global_position.distance_to(global_position) > INTERACT_RANGE + 1.5:
		return
	var data := ItemDB.get_item(item.item_id)
	if data == null:
		return
	if data.two_handed:
		_server_interact(path)
		return
	var taken := mini(item.count, inventory.room_for(into, data, item.state))
	if taken <= 0 or not inventory.insert_entry(into, {"id": item.item_id, "count": taken, "state": item.state.duplicate(true)}):
		var why := inventory.pack_problem(into, data, item.state)
		if why != "":
			_client_message.rpc_id(owner_peer(), why)
		else:
			_refuse(inventory.refusal(data, item.state, into), data.id, item.state)  # S2: why, and where it fits
		return
	_server_took(item, taken)


## Host: `taken` of the world item `item` went into this soldier's gear: the pickup
## animation, and the item leaves the world (or what's left of the stack stays).
func _server_took(item: WorldItem, taken: int) -> void:
	model.server_pick_up(item.global_position, item.item_id)  # the pickup animation
	if taken >= item.count:
		GameState.item_taken(item.uid)
		item.queue_free()
	else:
		item.count -= taken
		if item.uid != "" and not GameState.dropped.has(item.uid):
			# A level-placed stack, partly taken: from now on it saves like a dropped one, with
			# what's left, so a reload doesn't bring back the full stack (audit L1-01).
			GameState.item_taken(item.uid)
			GameState.item_dropped(item.uid, item.item_id, item.count, item.global_position, item.state.duplicate(true))
		_client_message.rpc_id(owner_peer(), "Took %d, no room for the rest" % taken)


@rpc("any_peer", "call_local", "reliable")
func _server_drop(slot: StringName) -> void:
	if not _from_owner():
		return
	var held := inventory.release_hands()
	if held != &"":
		_server_spawn_in_front(held)
	elif slot in Inventory.WEAPON_SLOTS:
		var removed := inventory.unequip(slot)
		if not removed.is_empty():
			_server_spawn_in_front(removed.id, 1, removed.state)


## Host: puts on the pack `entry` ({"id", "state"?}, already out of the world or the
## inventory) and drops the worn one in front, still loaded.
func _server_swap_pack(entry: Dictionary) -> void:
	var old := inventory.unequip(&"backpack")
	inventory.take(entry.id, 1, entry.get("state", {}))
	if not old.is_empty():
		_server_spawn_in_front(old.id, 1, old.state)
		_client_message.rpc_id(owner_peer(), "Swapped packs: dropped the %s" % ItemDB.get_item(old.id).name)


func _server_spawn_in_front(id: StringName, count := 1, state := {}) -> void:
	var pos := global_position - global_basis.z * 0.9 + Vector3.UP * 1.0
	CompoundLevel.current(self).server_spawn_dropped(id, count, pos, state)


# --- Medical requests -------------------------------------------------------------------
# The design doc's kit (Vitals "Treatment interface"). Every treatment is timed on the host:
# the treater is busy, and it's interrupted if the treater goes down or moves away, or the
# casualty is moved or goes out of reach. The item is used up (loose first, then out of a
# kit) only when it has done something. Players (H, the interaction menus) and AI send the
# same requests.

## Reach for treatment, body to body: the interaction menu's reach plus slack for lag.
const TREAT_REACH := INTERACT_REACH + INTERACT_SLACK
## Moving this far (the treater, or the casualty) interrupts a treatment (proposed).
const TREAT_MOVE_M := 1.0
## How often a treatment in progress checks for interruptions.
const TREAT_CHECK_S := 0.1
## Hit, or pinned by close fire (AI), this recently: under fire, so a tourniquet goes on
## rushed (proposed).
const UNDER_FIRE_S := 3.0
const UNDER_FIRE_SUPPRESSION := 0.3
## What the session log calls taking a tourniquet off (_log_care's item; it has no item of its own).
const LOG_TOURNIQUET_OFF := &"tourniquet removal"

var _treat_serial := 0  # host: bumps with each timed treatment


## The first task on this body's own care_needed() that it carries an item for (loose or in
## a kit; Vitals.pick_item, which becomes the task's "item") and can use on itself (not an IV
## or IO), or {}. H (_server_use_medical) applies it; AI uses it to know it can treat itself.
func next_self_treatment() -> Dictionary:
	for task in vitals.care_needed():
		var id := Vitals.pick_item(task, inventory)
		if id != &"" and not Vitals.needs_other_hands(id):
			var mine := task.duplicate()
			mine.item = id
			return mine
	return {}


## How long one `item` takes this soldier on `target`: the item's treat_s, times its
## self_mult on yourself (a tourniquet: 4 s, 6 s on yourself) and the casualty's
## treat_time_mult (an IV in shock takes longer); a rushed tourniquet rushed_s.
func treat_seconds(target: Node, item: ItemData, rushed := false) -> float:
	if rushed and item.stats.has("rushed_s"):
		return float(item.stats.rushed_s)
	var seconds := float(item.stats.get("treat_s", 4.0))
	if target == self:
		seconds *= float(item.stats.get("self_mult", 1.0))
	var other := Vitals.find_on(target) if target else null
	if other:
		seconds *= other.treat_time_mult(item.id)
	return seconds


## Host only. Hit, or pinned down by close fire (AI), within the last UNDER_FIRE_S.
func under_fire() -> bool:
	return vitals.seconds_since_hit() < UNDER_FIRE_S \
		or (_now() - threat_time < UNDER_FIRE_S and suppression >= UNDER_FIRE_SUPPRESSION)


## Treats `path` (this body or another within reach) with one `item_id` on `part` (the
## Vitals treatment interface): checks it would help and that you carry the item, takes the
## item's time (longer on yourself for a tourniquet; `rushed` only for a tourniquet:
## quicker, but it lets 30% through), then applies it and uses the item up. A tourniquet
## placed while you're under fire goes on rushed whatever you asked for. `their_kit`: the item
## comes out of the casualty's own kit when they carry one (_kit_for), else out of yours.
@rpc("any_peer", "call_local", "reliable")
func _server_treat(path: NodePath, item_id: StringName, part: StringName, rushed := false, their_kit := false) -> void:
	if not _from_owner() or not vitals.is_up() or _is_busy():
		return
	_treat(get_node_or_null(path) as Node3D, item_id, part, rushed, their_kit)


## Puts a triage card (Vitals.TRIAGE_*) on `path` (a casualty within reach, or yourself).
@rpc("any_peer", "call_local", "reliable")
func _server_set_triage(path: NodePath, card: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var target := get_node_or_null(path) as Node3D
	var other := Vitals.find_on(target) if target else null
	if other == null or other.is_dead() or not Vitals.TRIAGE_CARDS.has(card):
		return
	if not _in_treat_reach(target):
		_client_message.rpc_id(owner_peer(), "Too far away")
		return
	other.server_set_triage(card)


## Takes the tourniquets off `part` of `path` once its arterial bleeding is packed (timed,
## the tourniquet's remove_s). They go back in your kit if there's room, else on the ground.
@rpc("any_peer", "call_local", "reliable")
func _server_remove_tourniquet(path: NodePath, part: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or _is_busy():
		return
	var target := get_node_or_null(path) as Node3D
	var other := Vitals.find_on(target) if target else null
	if other == null or other.is_dead():
		return
	if not _in_treat_reach(target):
		_log_care(target, LOG_TOURNIQUET_OFF, part, "refused: Too far away")
		_client_message.rpc_id(owner_peer(), "Too far away")
		return
	var why := other.removal_problem(part)
	if why != "":
		_log_care(target, LOG_TOURNIQUET_OFF, part, "refused: " + why)
		_client_message.rpc_id(owner_peer(), why)
		return
	var item := ItemDB.get_item(WoundModel.TOURNIQUET)
	var label := "Removing tourniquet, %s..." % Vitals.part_name(part)
	if not await _timed_care(target, other, float(item.stats.get("remove_s", 3.0)), label, part, &"", LOG_TOURNIQUET_OFF):
		return
	var count := other.server_remove_tourniquets(part)
	if count <= 0:
		_log_care(target, LOG_TOURNIQUET_OFF, part, "refused: " + other.removal_problem(part))
		_client_message.rpc_id(owner_peer(), other.removal_problem(part))
		return
	var kept := inventory.take(WoundModel.TOURNIQUET, count)
	if kept < count:
		_server_spawn_in_front(WoundModel.TOURNIQUET, count - kept)
	_log_care(target, LOG_TOURNIQUET_OFF, part, "done")
	_client_message.rpc_id(owner_peer(), "Tourniquet off, %s" % Vitals.part_name(part))


## Host: a line in the session log for a treatment (SessionLog): who treats whom (log names:
## same-named hostiles apart, a target dummy as one), with what, on which part, how far the
## casualty is (_treat_distance; not on yourself), and how it went (`outcome`: "started (4.0 s)",
## "done", "interrupted: why", "refused: why") (Captain, P0164 queue 7).
func _log_care(target: Node, item_id: StringName, part: StringName, outcome: String) -> void:
	if SessionLog.session_id == "":
		return
	var at := ""
	if target != self and is_instance_valid(target) and target is Node3D:
		at = " at %.1f m" % _treat_distance(target)
	SessionLog.note("%s treats %s: %s%s%s, %s" % [log_name(), "themself" if target == self else SessionLog.who(target),
		String(item_id) if item_id != &"" else "care", (" on " + Vitals.part_name(part)) if part != &"" else "", at, outcome])


## Whose kit treating `target` with `item_id` uses up: with `their_kit`, the casualty's own
## while they carry one (squad AI uses a casualty's own kit first and keeps its own for the
## next casualty: Captain, P0164 queue 17), otherwise this soldier's.
func _kit_for(target: Node3D, item_id: StringName, their_kit: bool) -> Inventory:
	var casualty := target as Soldier
	if their_kit and casualty and casualty != self and Vitals.has_item(casualty.inventory, item_id):
		return casualty.inventory
	return inventory


## Host side of a treatment (_server_treat, _server_use_medical).
func _treat(target: Node3D, item_id: StringName, part: StringName, rushed: bool, their_kit := false) -> void:
	var other := Vitals.find_on(target) if target else null
	if other == null or other.is_dead():
		return
	var item := ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	var why := ""
	if not _in_treat_reach(target):
		why = "Too far away"
	elif item == null or not item.stats.has("treat_s"):
		why = "That doesn't treat anything"
	elif not Vitals.has_item(_kit_for(target, item_id, their_kit), item_id):
		why = "You have no %s" % item.name
	elif target == self and Vitals.needs_other_hands(item_id):
		why = "Someone else has to place that"
	elif is_ai() and item.stats.get("medic_only", false) and role != Roles.MEDIC:
		why = "Only a medic does that"
	else:
		why = other.treatment_problem(item_id, part)
	if why != "":
		_log_care(target, item_id, part, "refused: " + why)
		_client_message.rpc_id(owner_peer(), why)
		return
	var tourniquet := item_id == WoundModel.TOURNIQUET
	rushed = rushed and tourniquet
	var hurried := tourniquet and under_fire()
	var label := "%s%s, %s..." % [item.name, " (rushed)" if rushed else "", Vitals.part_name(part)]
	if not await _timed_care(target, other, treat_seconds(target, item, rushed), label, part, item_id):
		return
	var kit := _kit_for(target, item_id, their_kit)  # (theirs may have run out meanwhile)
	if not Vitals.has_item(kit, item_id):
		_log_care(target, item_id, part, "refused: no longer carrying it")
		_client_message.rpc_id(owner_peer(), "You no longer have a %s" % item.name)
		return
	rushed = rushed or (tourniquet and (hurried or under_fire()))
	if not other.server_apply_treatment(item_id, part, rushed):
		_log_care(target, item_id, part, "refused: does nothing there now")
		_client_message.rpc_id(owner_peer(), "%s does nothing there now" % item.name)
		return
	if not item.stats.get("no_item", false) and not item.stats.get("reusable", false):
		kit.take_medical(item_id)
	_log_care(target, item_id, part, "done")
	var note := other.care_note()
	if note != "":
		_client_message.rpc_id(owner_peer(), note)
	if rushed:
		_client_message.rpc_id(owner_peer(), "Tourniquet on in a hurry: it may still bleed (a second one fixes it)")


## Host only. Runs a timed treatment on `target`: this soldier is busy for `seconds` and the
## casualty shows as being treated. Returns false (and tells the treater) if it's
## interrupted: the treater went down or moved away, the casualty was moved, died or is out
## of reach. True once the time is up. `part` is where the hands work and `item` what with
## (the animation's technique: CharacterModel.TECHNIQUES); `logged` is what the session log
## calls it when that isn't `item` (LOG_TOURNIQUET_OFF). The log gets a line when it starts
## and when it's interrupted, with how far and why (who moved the casualty: _who_moved).
func _timed_care(target: Node3D, other: Vitals, seconds: float, label: String, part := &"", item := &"", logged := &"") -> bool:
	_treat_serial += 1
	var serial := _treat_serial
	var my_start := global_position
	var their_start := target.global_position
	var carrier := _carrier_id(target)
	var had_them: Soldier = (target as Soldier).carried_by if carrier != 0 else null
	var what := logged if logged != &"" else item
	_server_busy_until = _now() + seconds
	other.server_begin_treatment(seconds)
	_client_busy.rpc_id(owner_peer(), seconds, label)
	_log_care(target, what, part, "started (%.1f s)" % seconds)
	var anim := model.server_treat(target, part, seconds, item)  # kneeling at the wound, with the item's technique, for every peer
	var end := _now() + seconds
	while _now() < end:
		await get_tree().create_timer(clampf(end - _now(), 0.01, TREAT_CHECK_S)).timeout
		if not is_inside_tree():
			return false
		var why := ""
		var detail := ""  # the session log's more (the player's message keeps it short)
		if serial != _treat_serial:
			why = "something else came first"
		elif not vitals.is_up():
			why = "you went down"
		elif not is_instance_valid(target) or not is_instance_valid(other) or other.is_dead():
			why = "the casualty is gone"
		elif global_position.distance_to(my_start) > TREAT_MOVE_M:
			why = "you moved"
			detail = " %.1f m" % global_position.distance_to(my_start)
		elif target != self and _carrier_id(target) != carrier:
			why = "they were moved"
			detail = ": " + _who_moved(target, had_them, their_start)
		elif target != self and carrier != get_instance_id() and target.global_position.distance_to(their_start) > TREAT_MOVE_M:
			why = "they were moved"  # (a body you carry yourself moves with you: that's "you moved")
			detail = ": " + _who_moved(target, had_them, their_start)
		elif not _in_treat_reach(target):
			why = "out of reach"
		if why != "":
			if is_instance_valid(other):
				other.server_end_treatment()
			_log_care(target, what, part, "interrupted: " + why + detail)
			model.server_stop(anim)
			_server_busy_until = _now()
			_client_busy.rpc_id(owner_peer(), 0.0, "Treatment interrupted: %s" % why)
			return false
	other.server_end_treatment()
	model.server_stop(anim)
	return true


func _in_treat_reach(target: Node3D) -> bool:
	return target == self or ((target as Soldier).body_point() if target is Soldier else target.global_position).distance_to(global_position) <= TREAT_REACH


## How far `target` is for the session log's treatment lines (_log_care), measured as
## _in_treat_reach measures it: to its body_point (a ragdoll's chest), not its capsule.
func _treat_distance(target: Node3D) -> float:
	return ((target as Soldier).body_point() if target is Soldier else target.global_position).distance_to(global_position)


## Host: who moved `target` during a treatment, for the session log (Captain, P0164 queue 7):
## whoever carries or drags them now ("dragged by Rahimi [Bravo]"), else whoever had them
## when it started and put them down (`had_them`), else that nobody had them (they got up, or
## something shoved the body), with how far they went from `start`.
func _who_moved(target: Node3D, had_them: Soldier, start: Vector3) -> String:
	var moved := "%.1f m" % target.global_position.distance_to(start)
	var s := target as Soldier
	if s and is_instance_valid(s.carried_by):
		return "%s by %s (%s)" % ["dragged" if s.carried_by.carry_mode == DRAG else "carried", s.carried_by.log_name(), moved]
	if is_instance_valid(had_them):
		return "put down by %s (%s)" % [had_them.log_name(), moved]
	return "nobody carried them (%s, %s)" % [moved, s.vitals.condition_text() if s else "not a soldier"]


## Who carries or drags `target` (an instance id, 0 for nobody), to notice it being moved.
static func _carrier_id(target: Node) -> int:
	if target is Soldier and is_instance_valid((target as Soldier).carried_by):
		return (target as Soldier).carried_by.get_instance_id()
	return 0


func _is_busy() -> bool:
	return _now() < _server_busy_until - 0.1


## Debug builds only: hurts this body, to test going down and dying without an enemy.
@rpc("any_peer", "call_local", "reliable")
func _server_debug_hurt(amount: float) -> void:
	if _from_owner() and DevTools.on():
		vitals.server_damage(amount)


# --- Interaction requests --------------------------------------------------------------
# Sent by the interaction menu (InteractionMenu, hold Left Ctrl). Pick up reuses
# _server_interact above; treatment is _server_treat.

## What this soldier is doing with a downed body: carrying it over the shoulder or dragging
## it behind (empty for neither).
const CARRY := &"carry"
const DRAG := &"drag"
## Speed while moving a downed body (proposed; Soldier.carry_speed_mult).
const CARRY_SPEED_MULT := 0.55
const DRAG_SPEED_MULT := 0.35
## Where a dragged body lies, in the dragger's frame (+z is behind).
const DRAG_OFFSET := Vector3(0.0, 0.0, 1.0)
## Seconds to get a body up onto the shoulder, to take hold of a drag handle, and to lower a
## carried body to the ground. The carrier stands still meanwhile (carry_speed_mult) and
## CharacterModel plays them on every peer (server_carry's phase).
const CARRY_LIFT_S := 1.6
const DRAG_GRAB_S := 0.7
const CARRY_LOWER_S := 1.3
## How far (body to body) the host accepts an interaction: the menu's reach plus slack for lag.
const INTERACT_REACH := 3.0
const INTERACT_SLACK := 1.0

## CARRY, DRAG or empty. Set by the host; the owner learns it through _client_carry_mode
## (movement reads it for speed), so it's right on the host and the owner's machine.
var carry_mode: StringName = &""
## Host: the carry phase playing (&"lift", &"grab", &"lower"; &"" just holding) and how long it has left.
var _carry_phase := &""
var _carry_phase_left := 0.0  # seconds of it to go
## Host and owner: the carrier stands still until then (a pick-up, take-hold or put-down).
var carry_busy_until := 0.0


## "Player 1" for a player, the callsign for an AI squadmate, or a body's label (a dead
## player's body is still "Player 1").
func display_name() -> String:
	if body_label != "":
		return body_label
	if is_ai():
		return person_name if person_name != "" else String(name)
	return "Player %s" % name


## The name in the session log (SessionLog.who): display_name(), and for an AI its node's
## callsign in brackets when that differs ("Rahimi [Hostile3]"), so hostiles who share a
## surname read apart (Captain, P0164 queue 9). A body spawned as one (a player's left
## behind, one restored from the zone save) gets a short tag from its uid instead, the same
## across saves ("Player 1 [body 3fa2]"), so it reads apart from the player who respawned.
func log_name() -> String:
	var shown := display_name()
	if body_label != "":
		return "%s [body %04x]" % [shown, hash(body_uid) & 0xffff]
	if not is_ai() or String(name) == shown:
		return shown
	return "%s [%s]" % [shown, name]


@rpc("any_peer", "call_local", "reliable")
func _server_carry_body(path: NodePath) -> void:
	_server_move_body(path, CARRY)


@rpc("any_peer", "call_local", "reliable")
func _server_drag_body(path: NodePath) -> void:
	_server_move_body(path, DRAG)


## This player radios the employer on his field radio for a new contract (hot zones, 4B part 3:
## Contracts.server_radio_contract); he's told what came in, or why nothing can.
@rpc("any_peer", "call_local", "reliable")
func _server_radio_contract() -> void:
	if not multiplayer.is_server() or not _from_owner() or not vitals.is_up():
		return
	var why := Contracts.radio_contract_problem()
	var cid := Contracts.server_radio_contract() if why == "" else ""
	var text := why
	if why == "":
		text = "New contract: %s" % String(Contracts.contract(cid).get("title", cid)) if cid != "" else "Nothing came in"
	_client_message.rpc_id(owner_peer(), text)


## Puts down the body this soldier carries or drags.
@rpc("any_peer", "call_local", "reliable")
func _server_release_body() -> void:
	if not _from_owner() or carrying == null:
		return
	if is_instance_valid(carrying) and carrying.care_by == self:
		carrying.care_by = null
	server_put_down()


## Hands one unit of a stowed entry to a standing squadmate, if it fits on them.
@rpc("any_peer", "call_local", "reliable")
func _server_give_item(path: NodePath, container: StringName, index: int) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var other := get_node_or_null(path) as Soldier
	if other == null or other == self or other.faction != faction or not other.vitals.is_up():
		return
	if other.global_position.distance_to(global_position) > INTERACT_REACH + INTERACT_SLACK:
		_client_message.rpc_id(owner_peer(), "Too far away")
		return
	var list: Array = inventory.containers.get(container, [])
	if index < 0 or index >= list.size():
		return
	var entry := inventory.remove_entry(container, index, 1)
	var item := ItemDB.get_item(entry.id)
	if other.inventory.take(entry.id, 1, entry.get("state", {})) == 0:
		inventory.insert_entry(container, entry)  # put it back
		_client_message.rpc_id(owner_peer(), "%s has no room for %s" % [other.display_name(), item.name])
		return
	_client_message.rpc_id(owner_peer(), "Gave %s to %s" % [item.name, other.display_name()])
	if not other.is_ai():
		other._client_message.rpc_id(other.owner_peer(), "%s gave you %s" % [display_name(), item.name])


## Host side of carry and drag. Asking for the other mode on the body you already hold
## switches between them.
func _server_move_body(path: NodePath, mode: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var other := get_node_or_null(path) as Soldier
	if other == null or other == self or not _movable(other):
		return  # a downed or a dead body (or a cuffed captive)
	if carrying == other:
		if mode != carry_mode and _carry_phase != &"lower":
			_set_carry_mode(mode, &"lift" if mode == CARRY else &"grab")
		return
	var why := ""
	if carrying != null:
		why = "You're already moving someone"
	elif inventory.hands != &"":
		why = "Your hands are full"
	elif is_instance_valid(other.carried_by):
		why = "Someone else has them"
	elif other.body_point().distance_to(global_position) > INTERACT_REACH + INTERACT_SLACK:
		why = "Too far away"
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
		return
	if server_pick_up_body(other, mode, INTERACT_REACH + INTERACT_SLACK):
		other.care_by = self  # squadmates leave this casualty to you
		_client_message.rpc_id(owner_peer(), "%s %s (Ctrl+Alt: put down)" % ["Carrying" if mode == CARRY else "Dragging", other.display_name()])


## Host only. Sets carry_mode and tells the owning player.
## Host: carrying, dragging or neither (`mode`), starting `phase` (&"lift", &"grab" or &"lower",
## timed by CARRY_LIFT_S, DRAG_GRAB_S, CARRY_LOWER_S; the carrier stands still through it).
func _set_carry_mode(mode: StringName, phase := &"") -> void:
	if carry_mode == mode and (phase == &"" or phase == _carry_phase):
		return  # already so (a phase playing plays on)
	var seconds: float = {&"lift": CARRY_LIFT_S, &"grab": DRAG_GRAB_S, &"lower": CARRY_LOWER_S}.get(phase, 0.0)
	if mode == &"":
		phase = &""
		seconds = 0.0
	carry_mode = mode
	_carry_phase = phase
	_carry_phase_left = seconds
	carry_busy_until = _now() + seconds
	CharacterModel.server_carry(self, carrying, mode, phase, seconds)  # both bodies' poses, for every peer
	if not is_ai() and owner_peer() != multiplayer.get_unique_id():
		_client_carry_mode.rpc_id(owner_peer(), mode, seconds)


@rpc("any_peer", "call_local", "reliable")
func _client_carry_mode(mode: StringName, busy_s := 0.0) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		carry_mode = mode
		carry_busy_until = _now() + busy_s


## Every peer: a carried or dragged body stops colliding, so it doesn't shove whoever moves it.
@rpc("any_peer", "call_local", "reliable")
func _client_lifted(lifted: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		collision_layer = 0 if lifted or vitals.is_dead() else BODY_LAYER


## Host: a line in the session log when this soldier goes down or dies (`what`): who, why (what
## last hurt them, or bleed-out / arrest when nothing recent did), where on the body, and who
## did it (Harm.last) from how far, both by their log_name (Captain, P0164 queue 9: same-named
## hostiles apart). Does nothing without a session (SessionLog), nor for a body spawned as one
## (body_label: a player's left behind, one restored from the zone save), whose death was
## logged when it happened (it was logged a second time as a bleed-out).
func _log_casualty(what: String) -> void:
	if SessionLog.session_id == "" or body_label != "":
		return
	var c: Dictionary = vitals.last_cause
	var recent := not c.is_empty() and vitals.seconds_since_hit() < 3.0
	var cause := String(c.get("cause", "")) if recent else ("cardiac arrest" if vitals.in_cardiac_arrest() else "bleed-out")
	if not recent and what == "went down":
		cause = "out: " + ", ".join(vitals.why_unconscious())
	if what == "died" and _gave_up:
		cause = "gave up after %.0f s down" % (_now() - _down_since) if _down_since >= 0.0 else "gave up"
	var line := "%s %s (%s): %s" % [log_name(), what, faction, cause]
	if recent and c.has("part"):
		line += ", " + String(c.part)
	var by := Harm.last(self)
	if String(by.get("name", "")) != "" and _now() - float(by.get("at", -1000.0)) < 900.0:
		var who := get_node_or_null(NodePath(String(by.get("path", "")))) as Node3D
		line += ", %s %s (%s)" % ["by" if recent else "last hit by", SessionLog.who(who) if who != null else by.name, by.faction]
		var dist := float(c.get("distance", -1.0)) if recent else -1.0
		if dist < 0.0 and who != null:
			dist = global_position.distance_to(who.global_position)
		if dist >= 0.0:
			line += " at %.0f m" % dist
	SessionLog.note(line)


func _on_went_down() -> void:
	if not multiplayer.is_server():
		return
	_log_casualty("went down")
	_drop_held()  # you drop what you were carrying in your hands
	release_carried()  # ...and whoever you were carrying


# --- Death and bodies -------------------------------------------------------------------
# Everyone who dies leaves a body where they fell: lying, not blocking anyone, with
# everything they carried still on it (worn gear, weapons in their slots, backpack and
# pouches). Only a two-handed carry drops. Bodies are Soldiers in DEAD_GROUP on the host:
# lootable item by item or all at once (interaction menu), carriable and draggable, saved
# with the zone (GameState.bodies) and kept until the body cap removes the oldest, whose gear
# then drops where it lay.

## The order "Loot all" hands worn gear over in (gear_entries): carrier and pack first, so
## what goes in them can follow, then plates, helmet and weapons.
const LOOT_SLOT_ORDER: Array[StringName] = [&"vest", &"backpack", &"plate_front", &"plate_back", &"plate_left",
	&"plate_right", &"helmet", &"primary", &"sidearm"]

## A body's name in menus, callouts and its gear marker ("Player 2") when it isn't the
## node's own (a dead player's body, a body restored from a save). Set before entering the tree.
var body_label := ""
## Host: a body's stable id in the zone save. Set when it dies (or is restored).
var body_uid := ""
## A dead player's body carries a GearMarker (CompoundLevel.server_spawn_body).
var has_gear_marker := false
## A player's respawn (_client_respawn) puts them at a spawn point; until this time the ragdoll
## going doesn't stand them up where it lay (Captain, 2026-10-12: respawned where he'd died).
var _respawned_until := -1.0
## How long after a respawn the ragdoll's spot is ignored (the vitals reset and the respawn can
## reach a client in either order).
const RESPAWN_HOLD_S := 2.0

# Respawning (Captain, playtest P0362, 2026-10-13: a dead player came back at once at the same
# spot, the killer stood on it, and the shared respawn pool burned 3 -> 1 in 30 s). A dead
# player's body and gear stay where they fell and they're back in the default kit at once, as
# before, but they wait respawn_delay_s out of the fight (RESPAWN_WAITING: unseen, untouchable,
# no input, a countdown on their screen), then come back at the level's safest respawn point
# (CompoundLevel.respawn_point: the briefing's insertion if no enemy is near it or can see it,
# else another insertion or extraction point, else the FOB, else the least dangerous one) with
# spawn_protect_s of spawn protection (RESPAWN_PROTECTED: no harm; firing or throwing ends it).
const RESPAWN_NONE := 0
const RESPAWN_WAITING := 1
const RESPAWN_PROTECTED := 2
## Proposed (Captain asked for 5-10 s and 3-5 s). Tests that don't test the wait set them to 0.
static var respawn_delay_s := 8.0
static var spawn_protect_s := 4.0
## Every peer (host-owned, replicated): RESPAWN_NONE, RESPAWN_WAITING or RESPAWN_PROTECTED.
var respawn_state := RESPAWN_NONE
## Owner: when the wait or the protection ends (Soldier._now(), this peer's clock), for the HUD.
var respawn_eta := -1.0
var protect_eta := -1.0
var _respawn_serial := 0  # host: a newer death or respawn cancels an older one's timer
var _hidden_for_respawn := false  # every peer: respawn_state's look applied

# Giving up (Captain, P0362: down with the squad wiped, stuck until the session ended). A downed
# player can hold the give-up key (Controls "give_up") GIVE_UP_HOLD_S once they've been down
# GIVE_UP_AFTER_S, or at once with no conscious friendly (player or AI squadmate) within
# GIVE_UP_ALONE_M. It's a death like any other: the body stays, the respawn pool counts it.
const GIVE_UP_HOLD_S := 2.0
const GIVE_UP_AFTER_S := 15.0
const GIVE_UP_ALONE_M := 50.0
## The host's leeway on GIVE_UP_AFTER_S (each peer starts the clock when it sees the fall).
const GIVE_UP_SLACK_S := 1.0
## Every peer: when this soldier went down (Soldier._now(), this peer's clock), -1 while up.
var _down_since := -1.0
var _gave_up := false  # host: this death was a give-up (the session log says so)


## AI dies for good (permadeath) and its own node stays as the body, on the shoulder of
## whoever carries it if anyone does. A player leaves a body with all their gear where they
## fell (server_leave_body, with a gear marker) and respawns in the default kit (handoff).
func _on_died() -> void:
	if not multiplayer.is_server():
		return
	_log_casualty("died")
	_reload_n += 1  # a reload in progress dies with them
	release_carried()
	_drop_held()
	if is_ai():
		_server_become_body()
		died_for_good.emit(self)
		return
	var level := CompoundLevel.current(self)
	server_leave_body()
	inventory.strip()  # it's all on the body now
	vitals.server_reset_health()
	if CompoundLevel.player_role_kits and role != &"":
		Roles.apply_kit(inventory, role)  # the clean test sessions: back in your role's kit
	else:
		for kit: Array in DEFAULT_KIT:
			inventory.take(kit[0], kit[1])
	_gave_up = false
	_server_respawn_after(level, respawn_delay_s)


## Host only. A dead player waits `delay` seconds out of the fight (RESPAWN_WAITING), then
## respawns (_server_respawn_now); with no delay, at once.
func _server_respawn_after(level: CompoundLevel, delay: float) -> void:
	_respawn_serial += 1
	var serial := _respawn_serial
	if delay <= 0.0:
		_server_respawn_now(level)
		return
	respawn_state = RESPAWN_WAITING
	vitals.shielded = true
	SessionLog.note("%s waits %.1f s to respawn" % [log_name(), delay])
	_client_respawn_wait.rpc_id(owner_peer(), delay)
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if serial == _respawn_serial and respawn_state == RESPAWN_WAITING and is_instance_valid(level) and not level.is_queued_for_deletion():
			_server_respawn_now(level))


## Host only. Back in the fight at the level's respawn point (CompoundLevel.respawn_point), with
## spawn protection for spawn_protect_s.
func _server_respawn_now(level: CompoundLevel) -> void:
	_respawn_serial += 1
	var serial := _respawn_serial
	var pos := level.respawn_point(self)
	var protect := spawn_protect_s
	SessionLog.note("%s respawns at (%.0f, %.0f) in %s; the body and its gear stay where they fell" % [log_name(), pos.x, pos.z,
		"their role's kit" if CompoundLevel.player_role_kits and role != &"" else "the default kit"])
	respawn_state = RESPAWN_PROTECTED if protect > 0.0 else RESPAWN_NONE
	vitals.shielded = protect > 0.0
	_client_respawn.rpc_id(owner_peer(), pos, protect)
	if protect > 0.0:
		get_tree().create_timer(protect, false).timeout.connect(func() -> void:
			if serial == _respawn_serial:
				server_end_spawn_protection())


## Host only. Spawn protection ends (its time is up, or this player fired or threw something).
func server_end_spawn_protection() -> void:
	if respawn_state != RESPAWN_PROTECTED:
		return
	respawn_state = RESPAWN_NONE
	vitals.shielded = false


## Every peer, every frame: a player waiting to respawn is out of the fight: not drawn, no
## collision or hitboxes, and not among the "combatants" (no AI sees, hears or targets them).
func _apply_respawn_state() -> void:
	var hide := respawn_state == RESPAWN_WAITING
	if hide:
		collision_layer = 0  # whatever else set it (the ragdoll going)
	if hide == _hidden_for_respawn:
		return
	_hidden_for_respawn = hide
	model.visible = not hide
	gear.visible = not hide
	for child in get_children():
		var area := child as Area3D
		if area == null or not area.has_meta(&"body_part"):
			continue
		if hide:
			area.set_meta(&"respawn_layer", area.collision_layer)
			area.collision_layer = 0
		elif area.has_meta(&"respawn_layer"):
			area.collision_layer = int(area.get_meta(&"respawn_layer"))
			area.remove_meta(&"respawn_layer")
	if hide:
		remove_from_group(&"combatants")
	else:
		add_to_group(&"combatants")
		if vitals.is_up():
			collision_layer = BODY_LAYER


## Every peer: how long this soldier has been down (0 while up or dead).
func seconds_down() -> float:
	return _now() - _down_since if _down_since >= 0.0 else 0.0


## Whether a conscious friendly (a player or an AI squadmate, not one waiting to respawn) is
## within GIVE_UP_ALONE_M of this body. Every peer (positions and vitals replicate).
func help_near() -> bool:
	var at := body_point()
	for group: Array[Soldier] in [MapNodes.players(self), MapNodes.squad_ai(self)]:
		for s: Soldier in group:
			if s != self and s.faction == faction and s.vitals.is_up() and s.respawn_state != RESPAWN_WAITING \
					and s.body_point().distance_to(at) <= GIVE_UP_ALONE_M:
				return true
	return false


## Whether this player may give up now: down (not dead), and down GIVE_UP_AFTER_S already or
## with nobody to help (help_near). Every peer; the host checks with `slack` seconds' leeway.
func can_give_up(slack := 0.0) -> bool:
	if is_ai() or vitals.is_up() or vitals.is_dead() or respawn_state != RESPAWN_NONE or _down_since < 0.0:
		return false
	return seconds_down() >= GIVE_UP_AFTER_S - slack or not help_near()


## Owner -> host: the give-up key was held GIVE_UP_HOLD_S. A death (the respawn pool counts it).
@rpc("any_peer", "call_local", "reliable")
func _server_give_up() -> void:
	if not _from_owner() or not can_give_up(GIVE_UP_SLACK_S):
		return
	_gave_up = true
	SessionLog.note("%s gives up after %.0f s down%s" % [log_name(), seconds_down(), "" if help_near() else " (nobody near to help)"])
	vitals.server_kill()


## Host only. Leaves this player's body where it lies as a dead body node
## (CompoundLevel.server_spawn_body) with everything this player carries and a gear marker. A
## player who was carrying or dragging them goes on carrying the body. For a player who died,
## or who leaves the session while down. Returns the body (null if there's no level).
func server_leave_body() -> Soldier:
	var carrier: Soldier = carried_by if is_instance_valid(carried_by) and carried_by.carrying == self else null
	var mode := carrier.carry_mode if carrier else &""
	if is_instance_valid(carried_by):
		carried_by.release_carried()
	var level := CompoundLevel.current(self)
	if level == null:
		return null
	var record := body_record()
	record["marker"] = true
	var corpse := level.server_spawn_body(record)
	if corpse and carrier and not carrier.is_ai() and carrier.vitals.is_up():
		carrier.server_pick_up_body(corpse, mode, INF)
	return corpse


## Host only. What this body is, for CompoundLevel.server_spawn_body and the zone save:
## "uid", "label" (whose it was), "faction", "variant", "person_name", "nation" and "left" (the
## name tape, nationality and hand, so the body is the same person after a reload), "role",
## "pos" ([x, y, z]), "rot_y",
## "age_s" (seconds dead), "marker" (a dead player's: shows a GearMarker), "ragdoll" (its ragdoll pose,
## CharacterModel.ragdoll_net, or empty) and "gear" (an
## Inventory.net_state: everything on it).
func body_record() -> Dictionary:
	var p := global_position
	return {"uid": body_uid if body_uid != "" else GameState.new_uid(), "label": display_name(), "faction": String(faction),
		"variant": model.variant, "body": model.body, "person_name": person_name, "nation": nation, "left": left_handed,
		"role": String(role), "pos": [p.x, p.y, p.z], "rot_y": rotation.y,
		"age_s": maxf(_now() - died_at, 0.0) if died_at >= 0.0 else 0.0, "marker": has_gear_marker,
		"gear": inventory.net_state.duplicate(true), "ragdoll": Array(model.ragdoll_net)}


## Host only. A dead soldier becomes a body (DEAD_GROUP), gear and all. Past the body cap the
## oldest body goes.
func _server_become_body() -> void:
	care_by = null
	died_at = _now()
	if body_uid == "":
		body_uid = GameState.new_uid()
	collision_layer = 0
	add_to_group(DEAD_GROUP)
	server_enforce_body_cap(get_tree())


## Host only. Drops whatever is in the hands (a two-handed carry) in front of the body.
func _drop_held() -> void:
	var held := inventory.release_hands()
	if held != &"":
		_server_spawn_in_front(held)


## Whether anything is left on this body (worn, in a slot, stowed or in the hands). Works on
## every peer (it reads the replicated inventory).
func has_gear() -> bool:
	if inventory.hands != &"":
		return true
	for slot in Inventory.SLOTS:
		if inventory.slots[slot] != &"":
			return true
	for container in Inventory.CONTAINERS:
		if not inventory.containers[container].is_empty():
			return true
	return false


## Host only. Removes the oldest dead bodies past `body_cap` (bodies someone is carrying are
## kept). A removed body's gear drops where it lay, so nothing is lost.
static func server_enforce_body_cap(tree: SceneTree) -> void:
	var bodies: Array = tree.get_nodes_in_group(DEAD_GROUP).filter(func(n: Node) -> bool: return n is Soldier and not n.is_queued_for_deletion())
	bodies.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.died_at < b.died_at)
	var extra := bodies.size() - body_cap
	for b: Soldier in bodies:
		if extra <= 0:
			break
		if is_instance_valid(b.carried_by):
			continue
		b.server_remove_body()
		extra -= 1


## Host only. Takes a dead body out of the world (the body cap); its gear drops where it lay.
func server_remove_body() -> void:
	if is_instance_valid(carried_by):
		carried_by.release_carried()
	_server_drop_everything()
	remove_from_group(DEAD_GROUP)
	queue_free()


## Interaction menu "Loot all": everything on a dead body that fits goes into your own gear.
## Worn gear goes first (a carrier or pack you lack is put on, so what was in it follows it),
## then plates, weapons and the rest, then what was stowed. What doesn't fit stays on the
## body; nothing goes on the ground.
@rpc("any_peer", "call_local", "reliable")
func _server_loot_body(path: NodePath) -> void:
	var other := _lootable(path)
	if other == null:
		return
	model.server_loot(other, true)  # kneeling at the body
	if not other.has_gear():
		_client_message.rpc_id(owner_peer(), "Nothing left on %s" % other.display_name())
		return
	var mine := inventory.net_state.duplicate(true)
	var theirs := other.inventory.net_state.duplicate(true)
	var entries := other.gear_entries()
	var moved := _loot_all_at_once(other, entries)
	if moved < 0:
		# Something left behind no longer fits on the body (its carrier or pack came over
		# without all that was in it): undo, and go item by item, which never strands anything.
		inventory.net_state = mine
		other.inventory.net_state = theirs
		moved = 0
		var progress := true
		while progress:  # again while something moves (a pack emptied can come off next time)
			progress = false
			for where_index: Array in _loot_order(other):
				if int(_loot_one(other, where_index[0], where_index[1]).moved) > 0:
					moved += 1
					progress = true
	if not other.has_gear():
		_client_message.rpc_id(owner_peer(), "Took everything from %s" % other.display_name())
	elif moved > 0:
		_client_message.rpc_id(owner_peer(), "Took what fits from %s (no room for the rest)" % other.display_name())
	else:
		_client_message.rpc_id(owner_peer(), "No room for anything on %s" % other.display_name())


## Host only. Loot all in one go: everything on `other` (its gear_entries) goes into this
## soldier's gear and what doesn't fit goes back on the body, in the same order (carriers
## before what goes in them). Returns how many entries came over, or -1 if something couldn't
## go back on the body (the caller undoes it all).
func _loot_all_at_once(other: Soldier, entries: Array[Dictionary]) -> int:
	other.inventory.strip()
	var left: Array[Dictionary] = []
	for entry in entries:
		var taken := inventory.take(entry.id, int(entry.count), entry.get("state", {}))
		if taken < int(entry.count):
			var rest := entry.duplicate(true)
			rest.count = int(entry.count) - taken
			left.append(rest)
	for entry in left:
		if other.inventory.take(entry.id, int(entry.count), entry.get("state", {})) < int(entry.count):
			return -1
	return entries.size() - left.size()


## Where everything on `other` is, as [slot or container, index] pairs (-1 for a slot or an
## attachment), in the order to take it piece by piece: what's stowed first, pouches
## included (last entries first, so the indices stay good), then the emptied pouches and
## whatever else is on the carrier's MOLLE, then weapons, helmet and plates, and carrier and
## pack last (they only come off empty).
static func _loot_order(other: Soldier) -> Array:
	var out := []
	var inv := other.inventory
	for container in inv.search_containers():
		for i in range(inv.containers[container].size() - 1, -1, -1):
			out.append([container, i])
	for p: Dictionary in inv.attach_points():
		if not inv.attachment(StringName(p.id)).is_empty():
			out.append([Inventory.pouch_container(StringName(p.id)), -1])
	var slots := LOOT_SLOT_ORDER.duplicate()
	slots.reverse()
	for slot: StringName in slots:
		if other.inventory.slots[slot] != &"":
			out.append([slot, -1])
	return out


## Everything on this body as entries ({"id", "count", "state"?}), in the order to hand it
## over: worn gear in LOOT_SLOT_ORDER (carrier and pack first, then plates, helmet and
## weapons), then what's stowed, pouches first. The carrier comes with its pouches on but
## empty, and what was in them follows as entries of their own, so a looter who already
## wears a carrier gets the magazines in his own pouches instead of buried in a spare
## carrier, and one who puts this carrier on gets them back in its pouches. The same goes for
## the pack's attachments (an aid bag): each thing is handed over once, never both inside its
## pouch and as an entry of its own (audit A2-01: loot-all doubled an aid bag's bandages).
func gear_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in LOOT_SLOT_ORDER:
		if inventory.slots[slot] != &"":
			var entry := {"id": inventory.slots[slot], "count": 1}
			if not inventory.state_of(slot).is_empty():
				entry.state = inventory.state_of(slot).duplicate(true)
				if slot in Inventory.ATTACH_SLOTS:
					for att: Dictionary in entry.state.get("molle", {}).values():
						if att.has("held"):
							att.held = []
			out.append(entry)
	for container in inventory.pouch_containers():
		for entry: Dictionary in inventory.containers[container]:
			out.append(entry.duplicate(true))
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inventory.containers[container]:
			out.append(entry.duplicate(true))
	if inventory.hands != &"":
		out.append({"id": inventory.hands, "count": 1})
	return out


## Interaction menu "Loot" > one item: takes one thing off a dead body into your own gear:
## what's in slot `where` (index -1), or the whole stowed entry `index` of container `where`
## (as much of the stack as fits; the rest stays on the body). `id` is the item the looter
## picked: if someone else took it first and something else is there now, nothing moves.
@rpc("any_peer", "call_local", "reliable")
func _server_loot_item(path: NodePath, where: StringName, index: int, id: StringName) -> void:
	var other := _lootable(path)
	if other == null:
		return
	model.server_loot(other)  # kneeling at the body
	if _loot_id_at(other, where, index) != id:
		_client_message.rpc_id(owner_peer(), "Nothing there any more")
		return
	var result := _loot_one(other, where, index)
	if result.why != "":
		_client_message.rpc_id(owner_peer(), result.why)
	elif int(result.moved) > 0:
		_client_message.rpc_id(owner_peer(), "Took %s%s" % [result.name, " x%d" % result.moved if int(result.moved) > 1 else ""])


## The item in slot `where` (index < 0) or stowed entry `index` of container `where` on
## `other`, or &"" if there's nothing there.
static func _loot_id_at(other: Soldier, where: StringName, index: int) -> StringName:
	if index < 0 and Inventory.is_pouch_container(where):
		return StringName(other.inventory.attachment(Inventory.point_of(where)).get("id", ""))
	if index < 0:
		return other.inventory.slots.get(where, &"")
	var list: Array = other.inventory.containers.get(where, [])
	return list[index].id if index < list.size() else &""


## The dead body at `path` if this player may loot it now (up, the body in reach), else null.
func _lootable(path: NodePath) -> Soldier:
	if not _from_owner() or not vitals.is_up():
		return null
	var other := get_node_or_null(path) as Soldier
	if other == null or other == self or other.is_queued_for_deletion() or not other.vitals.is_dead():
		return null
	if other.body_point().distance_to(global_position) > INTERACT_REACH + INTERACT_SLACK:
		_client_message.rpc_id(owner_peer(), "Too far away")
		return null
	return other


## Host only. Moves one thing from `other`'s inventory into this soldier's: the item in slot
## `where` (index < 0), what's on the attach point of pouch container `where` (index < 0; a
## pouch comes with what's in it), or stowed entry `index` of container `where` (pouches
## too). Whatever doesn't fit goes straight back where it was. Returns {"moved" (units),
## "name", "why" ("" when it all moved, otherwise the reason)}.
func _loot_one(other: Soldier, where: StringName, index: int) -> Dictionary:
	var inv := other.inventory
	if index < 0 and Inventory.is_pouch_container(where):
		var point := Inventory.point_of(where)
		var detached := inv.detach(point)
		if detached.is_empty():
			return {"moved": 0, "name": "", "why": "Nothing there any more"}
		var att_name := ItemDB.get_item(detached.id).name
		if inventory.take(detached.id, 1, detached.get("state", {})) == 1:
			return {"moved": 1, "name": att_name, "why": ""}
		inv.attach(point, detached)  # no room: back on the carrier
		return {"moved": 0, "name": att_name, "why": "No room for %s" % att_name}
	if index < 0:
		var id: StringName = inv.slots.get(where, &"")
		if id == &"":
			return {"moved": 0, "name": "", "why": "Nothing there any more"}
		var item_name := ItemDB.get_item(id).name
		var removed := inv.unequip(where)
		if removed.is_empty():
			return {"moved": 0, "name": item_name, "why": "Take what's in the %s first" % item_name}
		if inventory.take(removed.id, 1, removed.state) == 1:
			return {"moved": 1, "name": item_name, "why": ""}
		inv.take(removed.id, 1, removed.state)  # no room: back on the body
		var loaded_pack: bool = Inventory.is_pack(ItemDB.get_item(removed.id)) and not removed.state.get("held", []).is_empty()
		return {"moved": 0, "name": item_name, "why": "You're already wearing a pack" if loaded_pack else "No room for %s" % item_name}
	var list: Array = inv.containers.get(where, [])
	if index >= list.size():
		return {"moved": 0, "name": "", "why": "Nothing there any more"}
	var entry := inv.remove_entry(where, index, int(list[index].count))
	var entry_name := ItemDB.get_item(entry.id).name
	var moved := inventory.take(entry.id, int(entry.count), entry.get("state", {}))
	if moved < int(entry.count):
		var rest := entry.duplicate(true)
		rest.count = int(entry.count) - moved
		inv.insert_entry(where, rest)  # it was just there, so it fits
		var why := "No room for %s" % entry_name if moved == 0 else "Took %d %s, no room for the rest" % [moved, entry_name]
		return {"moved": moved, "name": entry_name, "why": why}
	return {"moved": moved, "name": entry_name, "why": ""}


## Host only. Empties the inventory onto the ground around this body, item state and all
## (only for a body the body cap removes).
func _server_drop_everything() -> void:
	var level := CompoundLevel.current(self)
	var entries := inventory.strip()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		level.server_spawn_dropped(entry.id, entry.count, _drop_spot(i), entry.get("state", {}))


func _drop_spot(i: int) -> Vector3:
	var angle := i * 2.4
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * (0.4 + 0.08 * i) + Vector3.UP * 0.5


## Owner-side (human): the host moves us while someone carries us.
@rpc("any_peer", "call_local", "unreliable_ordered")
func _client_carried(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		carried_by_pos = pos


## Owner: you died and wait `seconds` to respawn (the HUD counts down).
@rpc("any_peer", "call_local", "reliable")
func _client_respawn_wait(seconds: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	respawn_eta = _now() + seconds
	velocity = Vector3.ZERO
	player_input.flash("You were killed. Respawning in %d s" % ceili(seconds))


## Owner: back in the fight at `pos`, with `protect_s` of spawn protection.
@rpc("any_peer", "call_local", "reliable")
func _client_respawn(pos: Vector3, protect_s: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_respawned_until = _now() + RESPAWN_HOLD_S
	var text := "Respawned" if respawn_eta >= 0.0 else "You were killed. Respawned"  # no wait: one message
	respawn_eta = -1.0
	protect_eta = _now() + protect_s if protect_s > 0.0 else -1.0
	global_position = pos
	velocity = Vector3.ZERO
	player_input.flash(text + (" (spawn protection %d s; firing ends it)" % ceili(protect_s) if protect_s > 0.0 else ""))


@rpc("any_peer", "call_local", "reliable")
func _client_busy(seconds: float, text: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_busy_until = _now() + seconds
	player_input.flash(text)


## A flashbang went off in sight: the whiteout is strongest when you were looking at it.
@rpc("any_peer", "call_local", "reliable")
func _client_flashed(pos: Vector3, amount: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		player_input.flashed(pos, amount)


@rpc("any_peer", "call_local", "reliable")
func _client_shake(amount: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		player_input.shake(amount)


@rpc("any_peer", "call_local", "reliable")
func _client_message(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		player_input.flash(text)


## Host: tells the owner an item was refused (S2): `text` says why and where it fits, and the
## inventory screen lights up the places that would take `id` (with `state`).
func _refuse(text: String, id: StringName, state := {}) -> void:
	_client_refused.rpc_id(owner_peer(), text, id, state)


@rpc("any_peer", "call_local", "reliable")
func _client_refused(text: String, id: StringName, state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if player_input:
		player_input.flash(text)
	if _hud and is_instance_valid(_hud.inventory_screen):
		_hud.inventory_screen.show_refusal(text, id, state)
