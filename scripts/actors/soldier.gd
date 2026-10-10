class_name Soldier
extends CharacterBody3D
## A soldier body, driven either by a human or by AI.
##
## Human: the node is named after its peer id; that peer simulates movement (replicated by
## Sync) and its PlayerInput child reads mouse and keys. AI: the node has a non-numeric
## name, is owned by the host, and a SquadAI child fills in the intent fields below.
## Either way, anything that changes shared state (pickups, shots, drops, revives) is a
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
## Carried mass below this costs no speed; at MAX_LOAD_KG you are at the slowest.
const FREE_LOAD_KG := 15.0
const MAX_LOAD_KG := 60.0
const MIN_LOAD_MULT := 0.55
## Aimed spread is this fraction of hip-fire spread; moving and jumping widen it.
const ADS_SPREAD_MULT := 0.12
const BULKY_SPEED_MULT := 0.7
const ITEM_MASK := 1 << 2
## Camo variants for players, picked from the peer id so every peer agrees.
const PLAYER_VARIANTS: Array[String] = ["multicam", "woodland", "desert", "urban"]
## What a player respawns with (handoff): an M4 and 2 spare magazines, a smoke and a frag.
## The handoff also lists 90 rounds; that waits on a loose-ammo item and on confirming
## whether they're loose (an open item in the handoff).
const DEFAULT_KIT: Array = [[&"m4a1", 1], [&"mag_556", 2], [&"smoke_grenade", 1], [&"frag_grenade", 1]]
const THROW_SPEED := 15.0
## Physics layer of soldier bodies ("movers").
const BODY_LAYER := 1 << 4
const THROW_BUSY_S := 0.7

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
var is_aiming := false
var load_mult := 1.0
## The local player's HUD (null for everyone else). Lives on PlayerInput.
var _hud: Hud:
	get:
		return player_input.hud if player_input else null
var _next_shot := 0.0         # owner-side fire-rate gate
var _busy_until := 0.0        # owner-side: reloading or using a medkit
var _server_next_shot := 0.0  # host-side check
var _server_busy_until := 0.0

## "friendly" (players and their squad) or "hostile". Set before the body enters the tree.
@export var faction := &"friendly"
## Camo for AI bodies (players get theirs from the peer id). Set before entering the tree.
@export var variant := ""
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
## Host only (AI): seconds left blinded by a flashbang.
var stunned_s := 0.0
## Host only (AI): 0..1, how pinned down rounds landing close have made this soldier.
var suppression := 0.0
## Host only (AI): where incoming fire last came from, and when.
var threat_pos := Vector3.ZERO
var threat_time := -1000.0
## Host only. An AI soldier bled out or was killed; it's freed right after.
signal died_for_good(soldier: Soldier)
## The active weapon or the carried load changed (the view model follows it).
signal loadout_changed

## Owner-side (human): position the host sent while someone drags or carries us.
var carried_by_pos: Variant = null
## Host only: the squadmate who has claimed this body while it is down.
var care_by: Soldier
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


func _enter_tree() -> void:
	set_multiplayer_authority(owner_peer())
	# Health, armor and inventory stay host-owned even though the owner drives the body.
	$ServerSync.set_multiplayer_authority(1)
	if is_ai():
		$Model.variant = variant if variant != "" else "woodland"
	else:
		$Model.variant = PLAYER_VARIANTS[absi(name.to_int() - 1) % PLAYER_VARIANTS.size()]  # host gets the first


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
	movement.apply_pose()  # model pose, hitbox pose and capsule from the replicated stance
	CharacterModel.lay_down(self, model, not vitals.is_up())
	if not vitals.is_up():
		model.hold = CharacterModel.Hold.NONE
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
		_update_carried()  # a player carrying or dragging someone: the host moves the casualty
	if not is_local():
		return
	if not vitals.is_up() and carried_by_pos != null:
		# Being dragged or carried: the host tells us where we are.
		global_position = carried_by_pos
		velocity = Vector3.ZERO
		carried_by_pos = null
		return
	movement.step(delta)
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	# PlayerInput's own physics step follows: aim, fire, crosshair target, HUD.


func is_crouching() -> bool:
	return movement.is_crouching()


## Host only: an AI body moves from its intent, and a downed one follows whoever carries it.
func _ai_physics(delta: float) -> void:
	stunned_s = maxf(stunned_s - delta, 0.0)
	suppression = move_toward(suppression, 0.0, delta * 0.25)
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	if not vitals.is_up() and is_instance_valid(carried_by):
		global_transform = carried_by.carry_transform()
		velocity = Vector3.ZERO
		return
	is_aiming = want_aim and vitals.is_up() and not is_reloading and inventory.hands == &"" and carrying == null
	movement.step(delta)
	_update_carried()


## Speed multiplier for moving a downed body (1 when not carrying or dragging). Reads
## carry_mode, so it works on the owner's machine too.
func carry_speed_mult() -> float:
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


## Host only. Keeps a carried body (AI or human) with this soldier.
func _update_carried() -> void:
	if carrying == null:
		return
	if not is_instance_valid(carrying) or carrying.vitals.is_up() or carrying.carried_by != self or not vitals.is_up():
		release_carried()
		return
	if not carrying.is_ai():
		carrying._client_carried.rpc_id(carrying.owner_peer(), carry_transform().origin)


## Host only. Picks up (CARRY) or takes hold of (DRAG) a downed body within `reach`.
func server_pick_up_body(other: Soldier, mode := CARRY, reach := REVIVE_RANGE) -> bool:
	if other == null or other == self or other.vitals.is_up() or not other.vitals.downed:
		return false
	if carrying != null or inventory.hands != &"" or not vitals.is_up():
		return false
	if other.global_position.distance_to(global_position) > reach:
		return false
	if is_instance_valid(other.carried_by) and other.carried_by != self:
		return false
	other.carried_by = self
	other._client_lifted.rpc(true)  # a moved body mustn't shove its carrier around
	carrying = other
	_set_carry_mode(mode)
	return true


## Host only. Puts down whoever this soldier carries or drags.
func release_carried() -> void:
	if is_instance_valid(carrying) and carrying.carried_by == self:
		carrying.carried_by = null
		carrying._client_lifted.rpc(false)
		if carrying.is_ai():
			if carry_mode != DRAG:  # a dragged body is already on the ground behind
				carrying.global_position = global_position - global_basis.z * 0.8
			carrying.rotation = Vector3(0, rotation.y, 0)
	carrying = null
	_set_carry_mode(&"")


## The kit this soldier would do the stopgap revive with: one that still has a revive (the
## trauma kit), or null.
func _best_revive_kit() -> ItemData:
	return inventory.revive_kit()


## Shot direction inside the weapon's cone. Spread is computed on the shooter's machine
## (co-op: the host trusts it) and widens when moving or airborne.
func _spread_direction(weapon: ItemData) -> Vector3:
	var spread := deg_to_rad(float(weapon.stats.get("spread_deg", 1.0)))
	if is_aiming:
		spread *= ADS_SPREAD_MULT
	var horizontal := Vector2(velocity.x, velocity.z).length()
	spread *= 1.0 + clampf(horizontal / SoldierMovement.WALK_SPEED, 0.0, 1.5)
	spread *= vitals.sway_mult()  # wounds, blood loss and pain
	if not is_on_floor():
		spread *= 2.5
	else:
		spread *= movement.spread_mult()  # stance, mounted weapon, settle after a stop
	var forward := -camera.global_basis.z
	var angle := randf() * TAU
	var amount := sqrt(randf()) * spread  # uniform over the cone's disc
	var offset := camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle)
	return (forward + offset * tan(amount)).normalized()


## Recoil: the view kicks up and a little sideways; aiming halves it.
func _kick(weapon: ItemData) -> void:
	var kick := deg_to_rad(float(weapon.stats.get("recoil_deg", 0.6))) * (0.5 if is_aiming else 1.0)
	kick *= movement.recoil_mult()  # stance and mounted weapon
	head.rotation.x = clampf(head.rotation.x + kick, -1.5, 1.5)
	rotate_y(randf_range(-0.35, 0.35) * kick)


## How long reloading `weapon` takes this body: the weapon's time, slowed by wounds
## (a broken arm).
func reload_seconds(weapon: ItemData) -> float:
	return float(weapon.stats.get("reload_s", 2.0)) * vitals.reload_mult()


## Where to aim at this body: the middle of its chest hitbox, wherever its stance put it.
func aim_point() -> Vector3:
	for child in get_children():
		if child is Area3D and child.get_meta(&"body_part", &"") == Vitals.CHEST:
			for shape in child.get_children():
				if shape is CollisionShape3D:
					return (shape as CollisionShape3D).global_position
	return global_position + Vector3.UP * (1.0 if is_crouching() else 1.3)


static func _ammo_of(weapon: ItemData) -> StringName:
	return StringName(weapon.stats.get("ammo", ""))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_inventory_changed() -> void:
	var mass := inventory.total_mass()
	var over := clampf((mass - FREE_LOAD_KG) / (MAX_LOAD_KG - FREE_LOAD_KG), 0.0, 1.0)
	load_mult = lerpf(1.0, MIN_LOAD_MULT, over) * (BULKY_SPEED_MULT if inventory.hands != &"" else 1.0)
	if active_weapon() == null:
		for slot: StringName in [&"primary", &"sidearm"]:
			if inventory.slots[slot] != &"":
				active_slot = slot
				break
	loadout_changed.emit()


# --- Host-side requests ---------------------------------------------------------------

func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == owner_peer()


@rpc("any_peer", "call_local", "reliable")
func _server_fire(origin: Vector3, direction: Vector3, slot: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or inventory.hands != &"":
		return
	var id: StringName = inventory.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	if weapon == null or weapon.type != "weapon":
		return
	var now := _now()
	if now < _server_next_shot - 0.03 or now < _server_busy_until - 0.1:  # tolerate jitter
		return
	if not inventory.consume_round(slot):
		return
	_server_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	if origin.distance_to(camera.global_position) > 1.0:
		origin = camera.global_position  # don't trust a far-off muzzle
	var result := Ballistics.fire(self, origin, direction.normalized(), weapon)
	if result.result != "none":
		CompoundLevel.current(self).show_impact.rpc(result.position, result.normal, result.result)


## A command from the command menu (CommandMenu) for the named squadmates (all if empty).
## Any player can command the friendly squad; that makes them its lead.
@rpc("any_peer", "call_local", "reliable")
func _server_squad_command(cmd: String, point: Vector3, names: PackedStringArray) -> void:
	if not _from_owner() or is_ai() or not vitals.is_up():
		return
	var squad := CompoundLevel.current(self).squad_for(faction)
	if squad == null:
		return
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
			var who := squad.order_throw(self, &"smoke_grenade" if cmd == "throw_smoke" else &"frag_grenade", point, names)
			if who == "":
				_client_message.rpc_id(owner_peer(), "Nobody selected has one")
		_:
			if not squad.command(self, cmd, point, names):  # formation, target, combat mode, team
				_client_message.rpc_id(owner_peer(), "Can't target that" if cmd.begins_with("target:") else "Order not given")


@rpc("any_peer", "call_local", "reliable")
func _server_throw(origin: Vector3, direction: Vector3, id: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or inventory.hands != &"" or _now() < _server_busy_until - 0.1:
		return
	var item := ItemDB.get_item(id)
	if item == null or not item.stats.has("throwable") or not inventory.remove_one(id):
		return
	_server_busy_until = _now() + THROW_BUSY_S
	if origin.distance_to(camera.global_position) > 1.0:
		origin = camera.global_position
	var dir := direction.normalized()
	CompoundLevel.current(self).server_throw(id, origin + dir * 0.5, velocity + dir * THROW_SPEED + Vector3.UP * 2.0)


@rpc("any_peer", "call_local", "reliable")
func _server_reload(slot: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or _now() < _server_busy_until - 0.1:
		return
	var id: StringName = inventory.slots.get(slot, &"")
	if id == &"":
		return
	var seconds := reload_seconds(ItemDB.get_item(id))
	_server_busy_until = _now() + seconds
	# The new magazine goes in when the reload finishes, if the same weapon is still there.
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree() and inventory.slots.get(slot, &"") == id:
		inventory.reload(slot)


## H: treats yourself with the next item you carry from your own care_needed() (a
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
		_client_message.rpc_id(owner_peer(), "You have no %s" % ItemDB.get_item(tasks[0].item).name)
		return
	_treat(self, task.item, task.part, false)


## Inventory screen actions. `container`/`index` name a stowed entry; `slot` an equipped one.
@rpc("any_peer", "call_local", "reliable")
func _server_inventory_action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
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
			var list: Array = inventory.containers.get(container, [])
			if index < 0 or index >= list.size() or target == container:
				return
			var entry := inventory.remove_entry(container, index, list[index].count)
			if not inventory.insert_entry(target, entry):
				inventory.insert_entry(container, entry)  # put it back
				_client_message.rpc_id(owner_peer(), "Not enough room in %s" % target)
		"equip_entry":
			var problem := inventory.entry_fit_problem(container, index)  # before equip_entry moves it
			if not inventory.equip_entry(container, index):
				_client_message.rpc_id(owner_peer(), problem if problem != "" else "No free slot for that")
		"stow_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				return
			for c in Inventory.CONTAINERS:
				if inventory.insert_entry(c, {"id": removed.id, "count": 1, "state": removed.state}):
					return
			inventory.take(removed.id, 1, removed.state)  # no room: straight back on
			_client_message.rpc_id(owner_peer(), "No room to stow that")


@rpc("any_peer", "call_local", "reliable")
func _server_interact(path: NodePath) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	var item := get_node_or_null(path) as WorldItem
	if item == null or item.is_queued_for_deletion():
		return
	if item.global_position.distance_to(global_position) > INTERACT_RANGE + 1.5:
		return
	var taken := inventory.take(item.item_id, item.count, item.state)
	if taken == 0:
		_client_message.rpc_id(owner_peer(), "No room for %s" % ItemDB.get_item(item.item_id).name)
	elif taken >= item.count:
		GameState.item_taken(item.uid)
		item.queue_free()
	else:
		item.count -= taken
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

var _treat_serial := 0  # host: bumps with each timed treatment


## The first task on this body's own care_needed() that it carries the item for (loose or in
## a kit), or {}. H (_server_use_medical) applies it; AI uses it to know it can treat itself.
func next_self_treatment() -> Dictionary:
	for task in vitals.care_needed():
		if inventory.medical_count(task.item) > 0:
			return task
	return {}


## How long one `item` takes this soldier on `target`: the item's treat_s, times its
## self_mult on yourself (a tourniquet: 4 s, 6 s on yourself); a rushed tourniquet rushed_s.
func treat_seconds(target: Node, item: ItemData, rushed := false) -> float:
	if rushed and item.stats.has("rushed_s"):
		return float(item.stats.rushed_s)
	var seconds := float(item.stats.get("treat_s", 4.0))
	if target == self:
		seconds *= float(item.stats.get("self_mult", 1.0))
	return seconds


## Host only. Hit, or pinned down by close fire (AI), within the last UNDER_FIRE_S.
func under_fire() -> bool:
	return vitals.seconds_since_hit() < UNDER_FIRE_S \
		or (_now() - threat_time < UNDER_FIRE_S and suppression >= UNDER_FIRE_SUPPRESSION)


## Revives a downed body with the stopgap (blood back to 62%, heart restarted) until IV in
## wave 3: needs a trauma kit with its revive left, and the casualty's bleeding controlled.
## Timed like a treatment; the kit's revive is used up when it's done (the kit and the rest
## of its contents stay).
@rpc("any_peer", "call_local", "reliable")
func _server_revive(path: NodePath) -> void:
	if not _from_owner() or not vitals.is_up() or _is_busy():
		return
	var target := get_node_or_null(path) as Node3D
	var other := target.get_node_or_null(^"Vitals") as Vitals if target else null
	if other == null or not other.downed or target == self:
		return
	if not _in_treat_reach(target):
		_client_message.rpc_id(owner_peer(), "Too far away")
		return
	var kit := _best_revive_kit()
	if kit == null:
		_client_message.rpc_id(owner_peer(), "You need a trauma kit")
		return
	var why := other.revive_problem()
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
		return
	if not await _timed_care(target, other, float(kit.stats.get("revive_s", 3.0)), "Reviving (stopgap)..."):
		return
	why = other.revive_problem()
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
	elif inventory.take_kit_revive():
		other.server_revive(0.0)
	else:
		_client_message.rpc_id(owner_peer(), "You need a trauma kit")


## Treats `path` (this body or another within reach) with one `item_id` on `part` (the
## Vitals treatment interface): checks it would help and that you carry the item, takes the
## item's time (longer on yourself for a tourniquet; `rushed` only for a tourniquet:
## quicker, but it lets 30% through), then applies it and uses the item up. A tourniquet
## placed while you're under fire goes on rushed whatever you asked for.
@rpc("any_peer", "call_local", "reliable")
func _server_treat(path: NodePath, item_id: StringName, part: StringName, rushed := false) -> void:
	if not _from_owner() or not vitals.is_up() or _is_busy():
		return
	_treat(get_node_or_null(path) as Node3D, item_id, part, rushed)


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
		_client_message.rpc_id(owner_peer(), "Too far away")
		return
	var why := other.removal_problem(part)
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
		return
	var item := ItemDB.get_item(WoundModel.TOURNIQUET)
	var label := "Removing tourniquet, %s..." % Vitals.part_name(part)
	if not await _timed_care(target, other, float(item.stats.get("remove_s", 3.0)), label):
		return
	var count := other.server_remove_tourniquets(part)
	if count <= 0:
		_client_message.rpc_id(owner_peer(), other.removal_problem(part))
		return
	var kept := inventory.take(WoundModel.TOURNIQUET, count)
	if kept < count:
		_server_spawn_in_front(WoundModel.TOURNIQUET, count - kept)
	_client_message.rpc_id(owner_peer(), "Tourniquet off, %s" % Vitals.part_name(part))


## Host side of a treatment (_server_treat, _server_use_medical).
func _treat(target: Node3D, item_id: StringName, part: StringName, rushed: bool) -> void:
	var other := Vitals.find_on(target) if target else null
	if other == null or other.is_dead():
		return
	var item := ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	var why := ""
	if not _in_treat_reach(target):
		why = "Too far away"
	elif item == null or not item.stats.has("treat_s"):
		why = "That doesn't treat anything"
	elif inventory.medical_count(item_id) <= 0:
		why = "You have no %s" % item.name
	else:
		why = other.treatment_problem(item_id, part)
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
		return
	var tourniquet := item_id == WoundModel.TOURNIQUET
	rushed = rushed and tourniquet
	var hurried := tourniquet and under_fire()
	var label := "%s%s, %s..." % [item.name, " (rushed)" if rushed else "", Vitals.part_name(part)]
	if not await _timed_care(target, other, treat_seconds(target, item, rushed), label):
		return
	if inventory.medical_count(item_id) <= 0:
		_client_message.rpc_id(owner_peer(), "You no longer have a %s" % item.name)
		return
	rushed = rushed or (tourniquet and (hurried or under_fire()))
	if not other.server_apply_treatment(item_id, part, rushed):
		_client_message.rpc_id(owner_peer(), "%s does nothing there now" % item.name)
		return
	inventory.take_medical(item_id)
	if rushed:
		_client_message.rpc_id(owner_peer(), "Tourniquet on in a hurry: it may still bleed (a second one fixes it)")


## Host only. Runs a timed treatment on `target`: this soldier is busy for `seconds` and the
## casualty shows as being treated. Returns false (and tells the treater) if it's
## interrupted: the treater went down or moved away, the casualty was moved, died or is out
## of reach. True once the time is up.
func _timed_care(target: Node3D, other: Vitals, seconds: float, label: String) -> bool:
	_treat_serial += 1
	var serial := _treat_serial
	var my_start := global_position
	var their_start := target.global_position
	var carrier := _carrier_id(target)
	_server_busy_until = _now() + seconds
	other.server_begin_treatment(seconds)
	_client_busy.rpc_id(owner_peer(), seconds, label)
	var end := _now() + seconds
	while _now() < end:
		await get_tree().create_timer(clampf(end - _now(), 0.01, TREAT_CHECK_S)).timeout
		if not is_inside_tree():
			return false
		var why := ""
		if serial != _treat_serial:
			why = "something else came first"
		elif not vitals.is_up():
			why = "you went down"
		elif not is_instance_valid(target) or not is_instance_valid(other) or other.is_dead():
			why = "the casualty is gone"
		elif global_position.distance_to(my_start) > TREAT_MOVE_M:
			why = "you moved"
		elif target != self and _carrier_id(target) != carrier:
			why = "they were moved"
		elif target != self and carrier != get_instance_id() and target.global_position.distance_to(their_start) > TREAT_MOVE_M:
			why = "they were moved"  # (a body you carry yourself moves with you: that's "you moved")
		elif not _in_treat_reach(target):
			why = "out of reach"
		if why != "":
			if is_instance_valid(other):
				other.server_end_treatment()
			_server_busy_until = _now()
			_client_busy.rpc_id(owner_peer(), 0.0, "Treatment interrupted: %s" % why)
			return false
	other.server_end_treatment()
	return true


func _in_treat_reach(target: Node3D) -> bool:
	return target == self or target.global_position.distance_to(global_position) <= TREAT_REACH


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
	if _from_owner() and OS.is_debug_build():
		vitals.server_damage(amount)


# --- Interaction requests --------------------------------------------------------------
# Sent by the interaction menu (InteractionMenu, hold Left Ctrl). Pick up and revive reuse
# _server_interact and _server_revive above.

## What this soldier is doing with a downed body: carrying it over the shoulder or dragging
## it behind (empty for neither).
const CARRY := &"carry"
const DRAG := &"drag"
## Speed while moving a downed body (proposed; Soldier.carry_speed_mult).
const CARRY_SPEED_MULT := 0.55
const DRAG_SPEED_MULT := 0.35
## Where a dragged body lies, in the dragger's frame (+z is behind).
const DRAG_OFFSET := Vector3(0.0, 0.0, 1.1)
## How far (body to body) the host accepts an interaction: the menu's reach plus slack for lag.
const INTERACT_REACH := 3.0
const INTERACT_SLACK := 1.0

## CARRY, DRAG or empty. Set by the host; the owner learns it through _client_carry_mode
## (movement reads it for speed), so it's right on the host and the owner's machine.
var carry_mode: StringName = &""


## "Player 1" for a player, the callsign for an AI squadmate.
func display_name() -> String:
	return String(name) if is_ai() else "Player %s" % name


@rpc("any_peer", "call_local", "reliable")
func _server_carry_body(path: NodePath) -> void:
	_server_move_body(path, CARRY)


@rpc("any_peer", "call_local", "reliable")
func _server_drag_body(path: NodePath) -> void:
	_server_move_body(path, DRAG)


## Puts down the body this soldier carries or drags.
@rpc("any_peer", "call_local", "reliable")
func _server_release_body() -> void:
	if not _from_owner() or carrying == null:
		return
	if is_instance_valid(carrying) and carrying.care_by == self:
		carrying.care_by = null
	release_carried()


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
	if other == null or other == self or not other.vitals.downed:
		return
	if carrying == other:
		_set_carry_mode(mode)
		return
	var why := ""
	if carrying != null:
		why = "You're already moving someone"
	elif inventory.hands != &"":
		why = "Your hands are full"
	elif is_instance_valid(other.carried_by):
		why = "Someone else has them"
	elif other.global_position.distance_to(global_position) > INTERACT_REACH + INTERACT_SLACK:
		why = "Too far away"
	if why != "":
		_client_message.rpc_id(owner_peer(), why)
		return
	if server_pick_up_body(other, mode, INTERACT_REACH + INTERACT_SLACK):
		other.care_by = self  # squadmates leave this casualty to you
		_client_message.rpc_id(owner_peer(), "%s %s (Ctrl+Alt: put down)" % ["Carrying" if mode == CARRY else "Dragging", other.display_name()])


## Host only. Sets carry_mode and tells the owning player.
func _set_carry_mode(mode: StringName) -> void:
	if carry_mode == mode:
		return
	carry_mode = mode
	if not is_ai() and owner_peer() != multiplayer.get_unique_id():
		_client_carry_mode.rpc_id(owner_peer(), mode)


@rpc("any_peer", "call_local", "reliable")
func _client_carry_mode(mode: StringName) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		carry_mode = mode


## Every peer: a carried or dragged body stops colliding, so it doesn't shove whoever moves it.
@rpc("any_peer", "call_local", "reliable")
func _client_lifted(lifted: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		collision_layer = 0 if lifted else BODY_LAYER


func _on_went_down() -> void:
	if not multiplayer.is_server():
		return
	var held := inventory.release_hands()  # you drop what you were carrying
	if held != &"":
		_server_spawn_in_front(held)
	release_carried()  # ...and whoever you were carrying


## Everything the body carried stays where it fell, lootable. AI is gone for good. A player
## respawns in the default kit, and a marker shows where their old gear lies (handoff).
func _on_died() -> void:
	if not multiplayer.is_server():
		return
	release_carried()
	if is_instance_valid(carried_by):
		carried_by.release_carried()
	var spot := global_position
	_server_drop_everything()
	if is_ai():
		died_for_good.emit(self)
		queue_free()
		return
	vitals.server_reset_health()
	for kit: Array in DEFAULT_KIT:
		inventory.take(kit[0], kit[1])
	var level := CompoundLevel.current(self)
	level.show_gear_marker.rpc(spot, "Player %s's gear" % name)
	_client_respawn.rpc_id(owner_peer(), level.next_spawn_point())


## Host only. Empties the inventory onto the ground around this body, item state and all.
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


@rpc("any_peer", "call_local", "reliable")
func _client_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
	player_input.flash("You were killed. Respawned.")


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
