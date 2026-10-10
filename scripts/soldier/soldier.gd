class_name Soldier
extends CharacterBody3D
## A body that walks, carries gear and fights: a player's, and later a squadmate's or an
## enemy's. A driver child node steers it: PlayerInput for a human, the squad AI for a bot.
## Drivers set the control fields below and call the action methods on the owning peer.
## Anything that changes shared state (pickups, shots, drops) is a request to the host,
## which validates it and lets ServerSync carry the result back to everyone.
##
## Ownership comes from the node name: a player's body is named after its peer id and is
## simulated by that peer; a body named "AI..." belongs to the host.

## Feedback for the driver on the owning peer ("Out of ammo", "No room for ...").
signal message(text: String)
## The host started a timed action for this body (using a medkit, reviving).
signal busy(seconds: float, text: String)
## The host respawned this body after it died.
signal respawned
## The active weapon or the carried load changed.
signal loadout_changed

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const ACCELERATION := 30.0
const JUMP_VELOCITY := 4.2
const STAND_HEAD_Y := 1.65
const CROUCH_HEAD_Y := 1.05
const DOWNED_HEAD_Y := 0.35
const CRAWL_SPEED := 0.6
const REVIVE_RANGE := 2.5
const INTERACT_RANGE := 2.2
const HITBOX_MASK := 1 << 1
const ITEM_MASK := 1 << 2
## Carried mass below this costs no speed; at MAX_LOAD_KG you are at the slowest.
const FREE_LOAD_KG := 15.0
const MAX_LOAD_KG := 60.0
const MIN_LOAD_MULT := 0.55
const BULKY_SPEED_MULT := 0.7
## Aimed spread is this fraction of hip-fire spread; moving and jumping widen it.
const ADS_SPREAD_MULT := 0.12
const ADS_SPEED_MULT := 0.6
const MAX_PITCH := 1.5
## Name prefix for host-owned (AI-driven) bodies.
const AI_PREFIX := "AI"
## What a player respawns with (handoff): an M4 and 2 spare magazines, a smoke and a frag.
## The handoff also lists 90 rounds; that waits on a loose-ammo item and on confirming
## whether they're loose (an open item in the handoff).
const DEFAULT_KIT: Array = [[&"m4a1", 1], [&"mag_556", 2], [&"smoke_grenade", 1], [&"frag_grenade", 1]]
## Camo variants for players, picked from the peer id so every peer agrees.
const PLAYER_VARIANTS: Array[String] = ["multicam", "woodland", "desert", "urban"]

@onready var head: Node3D = $Head
@onready var model: CharacterModel = $Model
@onready var inventory: Inventory = $Inventory
@onready var vitals: Vitals = $Vitals
@onready var gear: GearRig = $Gear

var active_slot: StringName = &"primary"
## Owner-driven, replicated so others see the reload pose.
var is_reloading := false
var is_aiming := false
var is_crouching := false
var load_mult := 1.0
var voxel_viewer: VoxelViewer

# Driver controls, read by the owner every physics frame. Drivers run first
# (process_physics_priority -1), so a control set this frame takes effect this frame.
## Movement relative to facing: x is right, y is back (as Input.get_vector returns it).
var move_input := Vector2.ZERO
var want_sprint := false
var want_crouch := false
var want_aim := false
var _want_jump := false

var _next_shot := 0.0         # owner-side fire-rate gate
var _busy_until := 0.0        # owner-side: reloading or using a medkit
var _server_next_shot := 0.0  # host-side check
var _server_busy_until := 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(owner_peer())
	# Health, armor and inventory stay host-owned even though the owner drives the body.
	$ServerSync.set_multiplayer_authority(1)
	if not is_ai():
		$Model.variant = PLAYER_VARIANTS[absi(name.to_int() - 1) % PLAYER_VARIANTS.size()]  # host gets the first


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)
	vitals.died.connect(_on_died)
	vitals.went_down.connect(_on_went_down)
	_add_voxel_viewer()
	_on_inventory_changed()
	print("[soldier] %s spawned on peer %d (owned here: %s)" % [name, multiplayer.get_unique_id(), is_multiplayer_authority()])


## The peer that simulates this body: its player, or the host for AI.
func owner_peer() -> int:
	return 1 if is_ai() else name.to_int()


func is_ai() -> bool:
	return name.begins_with(AI_PREFIX)


func active_weapon() -> ItemData:
	var id: StringName = inventory.slots.get(active_slot, &"")
	return ItemDB.get_item(id) if id != &"" else null


## Where shots and interaction rays start, and which way they go.
func eye() -> Vector3:
	return head.global_position


func aim_forward() -> Vector3:
	return -head.global_basis.z


func _add_voxel_viewer() -> void:
	# The host needs collision around every body for movement checks and ballistics, and
	# the owner around its own. A human driver turns visuals on for itself.
	if not is_multiplayer_authority() and not multiplayer.is_server():
		return
	voxel_viewer = VoxelViewer.new()
	voxel_viewer.view_distance = VoxelWorld.VIEW_DISTANCE
	voxel_viewer.requires_visuals = false
	voxel_viewer.requires_collisions = true
	add_child(voxel_viewer)


func _process(_delta: float) -> void:
	# Runs on every peer: active_slot, inventory and head rotation are replicated.
	model.look_pitch = head.rotation.x
	model.reloading = is_reloading
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
	if not is_multiplayer_authority():
		return
	_move(delta)
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	var weapon := active_weapon()
	is_aiming = want_aim and vitals.is_up() and weapon != null and weapon.type == "weapon" \
		and inventory.hands == &"" and not is_reloading


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var down := not vitals.is_up()
	is_crouching = want_crouch and not down
	var carrying := inventory.hands != &""
	if _want_jump and is_on_floor() and not carrying and not is_crouching and not down:
		velocity.y = JUMP_VELOCITY
	_want_jump = false
	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif want_sprint and not carrying:
		speed = SPRINT_SPEED
	if is_aiming:
		speed = minf(speed, WALK_SPEED) * ADS_SPEED_MULT
	if down:
		speed = CRAWL_SPEED
	speed *= load_mult
	var input := move_input.limit_length(1.0)
	var target := (global_basis * Vector3(input.x, 0.0, input.y)).normalized() * speed * input.length()
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	move_and_slide()
	var head_y := DOWNED_HEAD_Y if down else (CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y)
	head.position.y = move_toward(head.position.y, head_y, 4.0 * delta)


# --- Driver API (call on the owning peer) ----------------------------------------------

## Turns the body (yaw) and the head (pitch), in radians.
func look(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	head.rotation.x = clampf(head.rotation.x + pitch, -MAX_PITCH, MAX_PITCH)


func jump() -> void:
	_want_jump = true


func select_weapon(slot: StringName) -> void:
	active_slot = slot
	_on_inventory_changed()


## Pulls the trigger. `held` is the trigger state; `just_pressed` is true on the press
## itself (semi-auto weapons fire only then).
func trigger(held: bool, just_pressed: bool) -> void:
	if inventory.hands != &"" or not vitals.is_up():
		return
	var weapon := active_weapon()
	if weapon == null or weapon.type != "weapon":
		return
	var auto: bool = weapon.stats.get("auto", false)
	if not (held if auto else just_pressed):
		return
	var now := _now()
	if now < _next_shot or now < _busy_until:
		return
	if inventory.rounds_in(active_slot) <= 0:
		if just_pressed:
			message.emit("Empty - R to reload" if inventory.spare_rounds(_ammo_of(weapon)) > 0 else "Out of ammo")
		return
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	_server_fire.rpc_id(1, eye(), spread_direction(weapon), active_slot)
	_kick(weapon)


func reload() -> void:
	var weapon := active_weapon()
	if weapon == null or weapon.type != "weapon" or _now() < _busy_until or inventory.hands != &"" or not vitals.is_up():
		return
	var full := ItemDB.get_item(_ammo_of(weapon)).magazine_rounds() if ItemDB.has_item(_ammo_of(weapon)) else 0
	if inventory.rounds_in(active_slot) >= full:
		return
	if inventory.spare_rounds(_ammo_of(weapon)) <= 0:
		message.emit("No spare magazines")
		return
	_busy_until = _now() + float(weapon.stats.get("reload_s", 2.0))
	is_reloading = true
	_server_reload.rpc_id(1, active_slot)


func use_medical() -> void:
	_server_use_medical.rpc_id(1)


func interact(item: WorldItem) -> void:
	_server_interact.rpc_id(1, item.get_path())


func revive(target: Node3D) -> void:
	_server_revive.rpc_id(1, target.get_path())


## Drops what's carried in both hands, otherwise the active weapon.
func drop() -> void:
	_server_drop.rpc_id(1, active_slot)


func give_up() -> void:
	_server_give_up.rpc_id(1)


## Debug builds only: hurts this body, to test going down and dying without an enemy.
func debug_hurt(amount: float) -> void:
	_server_debug_hurt.rpc_id(1, amount)


func is_busy() -> bool:
	return _now() < _busy_until


## Shot direction inside the weapon's cone, around where the head points. Spread is computed
## on the shooter's machine (co-op: the host trusts it) and widens when moving or airborne.
func spread_direction(weapon: ItemData) -> Vector3:
	var spread := deg_to_rad(float(weapon.stats.get("spread_deg", 1.0)))
	if is_aiming:
		spread *= ADS_SPREAD_MULT
	var horizontal := Vector2(velocity.x, velocity.z).length()
	spread *= 1.0 + clampf(horizontal / WALK_SPEED, 0.0, 1.5)
	if not is_on_floor():
		spread *= 2.5
	elif is_crouching:
		spread *= 0.7
	var view := head.global_basis
	var angle := randf() * TAU
	var amount := sqrt(randf()) * spread  # uniform over the cone's disc
	var offset := view.x * cos(angle) + view.y * sin(angle)
	return (-view.z + offset * tan(amount)).normalized()


## The revive kit this body would use: the fastest one carried.
func best_revive_kit() -> ItemData:
	var best: ItemData = null
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inventory.containers[container]:
			var item := ItemDB.get_item(entry.id)
			if item.stats.has("revive_hp") and (best == null or item.stats.revive_s < best.stats.revive_s):
				best = item
	return best


## Recoil: the view kicks up and a little sideways; aiming halves it.
func _kick(weapon: ItemData) -> void:
	var kick := deg_to_rad(float(weapon.stats.get("recoil_deg", 0.6))) * (0.5 if is_aiming else 1.0)
	look(randf_range(-0.35, 0.35) * kick, kick)


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


func _tell_owner(text: String) -> void:
	_client_message.rpc_id(owner_peer(), text)


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
	if origin.distance_to(eye()) > 1.0:
		origin = eye()  # don't trust a far-off muzzle
	var result := Ballistics.fire(self, origin, direction.normalized(), weapon)
	if result.result != "none":
		CompoundLevel.current(self).show_impact.rpc(result.position, result.normal, result.result)


@rpc("any_peer", "call_local", "reliable")
func _server_reload(slot: StringName) -> void:
	if not _from_owner() or not vitals.is_up() or _now() < _server_busy_until - 0.1:
		return
	var id: StringName = inventory.slots.get(slot, &"")
	if id == &"":
		return
	var seconds := float(ItemDB.get_item(id).stats.get("reload_s", 2.0))
	_server_busy_until = _now() + seconds
	# The new magazine goes in when the reload finishes, if the same weapon is still there.
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree() and inventory.slots.get(slot, &"") == id:
		inventory.reload(slot)


@rpc("any_peer", "call_local", "reliable")
func _server_use_medical() -> void:
	if not _from_owner() or not vitals.is_up() or _now() < _server_busy_until - 0.1:
		return
	if vitals.health >= vitals.max_health:
		_tell_owner("Not injured")
		return
	# Smallest kit that covers the damage; otherwise the biggest one carried.
	var missing := vitals.max_health - vitals.health
	var best := {}
	for container in Inventory.CONTAINERS:
		var list: Array = inventory.containers[container]
		for i in list.size():
			var item := ItemDB.get_item(list[i].id)
			var heal := float(item.stats.get("heal", 0.0))
			if heal <= 0.0:
				continue
			var better: bool = best.is_empty() or (heal >= missing and (best.heal < missing or heal < best.heal)) or (best.heal < missing and heal > best.heal)
			if better:
				best = {"container": container, "index": i, "heal": heal, "item": item}
	if best.is_empty():
		_tell_owner("No medical supplies")
		return
	inventory.remove_entry(best.container, best.index)
	var item: ItemData = best.item
	_server_busy_until = _now() + float(item.stats.get("use_s", 2.0))
	vitals.server_heal_over_time(best.heal, float(item.stats.get("heal_s", 4.0)))
	_client_busy.rpc_id(owner_peer(), float(item.stats.get("use_s", 2.0)), "Using %s" % item.name)


## Inventory screen actions. `container`/`index` name a stowed entry; `slot` an equipped one.
@rpc("any_peer", "call_local", "reliable")
func _server_inventory_action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	match action:
		"drop_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				_tell_owner("Empty it first")
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
				_tell_owner("Not enough room in %s" % target)
		"equip_entry":
			if not inventory.equip_entry(container, index):
				_tell_owner("No free slot for that")
		"stow_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				return
			for c in Inventory.CONTAINERS:
				if inventory.insert_entry(c, {"id": removed.id, "count": 1, "state": removed.state}):
					return
			inventory.take(removed.id, 1, removed.state)  # no room: straight back on
			_tell_owner("No room to stow that")


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
		_tell_owner("No room for %s" % ItemDB.get_item(item.item_id).name)
	elif taken >= item.count:
		GameState.item_taken(item.uid)
		item.queue_free()
	else:
		item.count -= taken
		_tell_owner("Took %d, no room for the rest" % taken)


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


## Revives a downed body (a teammate or a squadmate) with the fastest kit carried. The kit
## is used up when the revive completes, if both are still there and in range.
@rpc("any_peer", "call_local", "reliable")
func _server_revive(path: NodePath) -> void:
	if not _from_owner() or not vitals.is_up() or _now() < _server_busy_until - 0.1:
		return
	var target := get_node_or_null(path) as Node3D
	var other := target.get_node_or_null(^"Vitals") as Vitals if target else null
	if other == null or not other.downed or target == self:
		return
	if target.global_position.distance_to(global_position) > REVIVE_RANGE + 1.0:
		return
	var kit := best_revive_kit()
	if kit == null:
		_tell_owner("You need an IFAK or trauma kit")
		return
	var seconds := float(kit.stats.revive_s)
	_server_busy_until = _now() + seconds
	_client_busy.rpc_id(owner_peer(), seconds, "Reviving...")
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree() or not is_instance_valid(target) or not other.downed or not vitals.is_up():
		return
	if target.global_position.distance_to(global_position) > REVIVE_RANGE + 1.0:
		_tell_owner("Revive interrupted")
		return
	for container in Inventory.CONTAINERS:
		var list: Array = inventory.containers[container]
		for i in list.size():
			if list[i].id == kit.id:
				inventory.remove_entry(container, i)
				other.server_revive(float(kit.stats.revive_hp))
				return


@rpc("any_peer", "call_local", "reliable")
func _server_debug_hurt(amount: float) -> void:
	if _from_owner() and OS.is_debug_build():
		vitals.server_damage(amount)


@rpc("any_peer", "call_local", "reliable")
func _server_give_up() -> void:
	if _from_owner():
		vitals.server_give_up()


func _on_went_down() -> void:
	if not multiplayer.is_server():
		return
	var held := inventory.release_hands()  # you drop what you were carrying
	if held != &"":
		_server_spawn_in_front(held)


## Host only. A player's gear stays where they died, with a marker, and they respawn in the
## default kit. An AI soldier's death is permanent; its gear stays too.
func _on_died() -> void:
	if not multiplayer.is_server():
		return
	var spot := global_position
	_server_leave_gear(spot)
	if is_ai():
		queue_free()  # TODO(squad): keep the body so the squad can carry it to exfil
		return
	vitals.server_reset_health()
	for kit: Array in DEFAULT_KIT:
		inventory.take(kit[0], kit[1])
	var level := CompoundLevel.current(self)
	level.show_gear_marker.rpc(spot, "Player %s's gear" % name)
	_client_respawn.rpc_id(owner_peer(), level.next_spawn_point())


## Host only. Lays everything this body carried on the ground around `spot`, in a loose
## grid so the items don't spawn inside each other.
func _server_leave_gear(spot: Vector3) -> void:
	var level := CompoundLevel.current(self)
	var entries := inventory.strip()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var offset := Vector3((i % 4) * 0.4 - 0.6, 0.4 + (i / 12) * 0.45, ((i / 4) % 3) * 0.4 - 0.4)
		level.server_spawn_dropped(entry.id, entry.count, spot + offset, entry.get("state", {}))


@rpc("any_peer", "call_local", "reliable")
func _client_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
	respawned.emit()


@rpc("any_peer", "call_local", "reliable")
func _client_busy(seconds: float, text: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_busy_until = _now() + seconds
	busy.emit(seconds, text)


@rpc("any_peer", "call_local", "reliable")
func _client_message(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		message.emit(text)
