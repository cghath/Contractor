class_name Player
extends CharacterBody3D
## First-person co-op player. The owning peer simulates movement (replicated by Sync).
## Anything that changes shared state (pickups, shots, drops) is a request to the host,
## which validates it and lets ServerSync carry the result back to everyone.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const ACCELERATION := 30.0
const JUMP_VELOCITY := 4.2
const MOUSE_SENSITIVITY := 0.0025
const STAND_HEAD_Y := 1.65
const CROUCH_HEAD_Y := 1.05
const DOWNED_HEAD_Y := 0.35
const CRAWL_SPEED := 0.6
const REVIVE_RANGE := 2.5
const HITBOX_MASK := 1 << 1
const INTERACT_RANGE := 2.2
## Carried mass below this costs no speed; at MAX_LOAD_KG you are at the slowest.
const FREE_LOAD_KG := 15.0
const MAX_LOAD_KG := 60.0
const MIN_LOAD_MULT := 0.55
const BASE_FOV := 80.0
## Aimed spread is this fraction of hip-fire spread; moving and jumping widen it.
const ADS_SPREAD_MULT := 0.12
const ADS_SPEED_MULT := 0.6
## View model position (camera-local) at the hip; aiming puts the weapon's sight point
## (VoxelArt.sight_point) here instead.
const HIP_VIEW := Vector3(0.14, -0.16, -0.38)
const ADS_EYE := Vector3(0.0, -0.012, -0.24)
const BULKY_SPEED_MULT := 0.7
const ITEM_MASK := 1 << 2
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1
## Camo variants for players, picked from the peer id so every peer agrees.
const PLAYER_VARIANTS: Array[String] = ["multicam", "woodland", "desert", "urban"]
## Throwables in the order the next-throwable key cycles them.
const THROWABLES: Array[StringName] = [&"frag_grenade", &"flashbang", &"smoke_grenade"]
const THROW_SPEED := 15.0
const THROW_BUSY_S := 0.7

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var view_model: Node3D = $Head/Camera/ViewModel
@onready var model: CharacterModel = $Model
@onready var inventory: Inventory = $Inventory
@onready var vitals: Vitals = $Vitals
@onready var gear: GearRig = $Gear

var active_slot: StringName = &"primary"
## Owner-driven, replicated so others see the reload pose.
var is_reloading := false
var is_aiming := false
var load_mult := 1.0
var _focus: WorldItem
var _revive_target: Node3D  # a downed body under the crosshair
var _view_model_id: StringName = &""
var _hud: Hud
var _next_shot := 0.0         # owner-side fire-rate gate
var _busy_until := 0.0        # owner-side: reloading or using a medkit
var _server_next_shot := 0.0  # host-side check
var _server_busy_until := 0.0
## Owner-side: the grenade type the throw key uses.
var throwable: StringName = &"frag_grenade"
var _shake := 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	# Health, armor and inventory stay host-owned even though the owner drives the body.
	$ServerSync.set_multiplayer_authority(1)
	$Model.variant = PLAYER_VARIANTS[absi(name.to_int() - 1) % PLAYER_VARIANTS.size()]  # host gets the first


func _ready() -> void:
	add_to_group(&"combatants")
	inventory.changed.connect(_on_inventory_changed)
	vitals.died.connect(_on_died)
	vitals.went_down.connect(_on_went_down)
	_add_voxel_viewer()
	if is_multiplayer_authority():
		camera.current = true
		camera.cull_mask &= ~LOCAL_ONLY_LAYER
		model.render_layers = LOCAL_ONLY_LAYER
		gear.render_layers = LOCAL_ONLY_LAYER
		_hud = Hud.new()
		_hud.player = self
		add_child(_hud)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_on_inventory_changed()
	print("[player] %s spawned on peer %d (local: %s)" % [name, multiplayer.get_unique_id(), is_local()])


func is_local() -> bool:
	return is_multiplayer_authority()


func active_weapon() -> ItemData:
	var id: StringName = inventory.slots.get(active_slot, &"")
	return ItemDB.get_item(id) if id != &"" else null


func _add_voxel_viewer() -> void:
	# Local player loads visuals and collision; the host also needs collision around
	# remote players for movement checks and ballistics.
	if not is_local() and not multiplayer.is_server():
		return
	var viewer := VoxelViewer.new()
	viewer.view_distance = VoxelWorld.VIEW_DISTANCE
	viewer.requires_visuals = is_local()
	viewer.requires_collisions = true
	add_child(viewer)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, -1.5, 1.5)
	elif event.is_action_pressed(&"inventory") or (event.is_action_pressed(&"pause") and _hud.is_inventory_open()):
		_hud.toggle_detail()
	elif _hud.is_inventory_open():
		return  # the inventory screen has the mouse
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not vitals.is_up():
		if event.is_action_pressed(&"give_up"):
			_server_give_up.rpc_id(1)
	elif event.is_action_pressed(&"interact") and _revive_target:
		_server_revive.rpc_id(1, _revive_target.get_path())
	elif event.is_action_pressed(&"interact") and _focus:
		_server_interact.rpc_id(1, _focus.get_path())
	elif event.is_action_pressed(&"drop"):
		_server_drop.rpc_id(1, active_slot)
	elif event.is_action_pressed(&"reload"):
		_try_reload()
	elif event.is_action_pressed(&"use_medical"):
		_server_use_medical.rpc_id(1)
	elif event.is_action_pressed(&"weapon_primary"):
		active_slot = &"primary"
		_on_inventory_changed()
	elif event.is_action_pressed(&"weapon_sidearm"):
		active_slot = &"sidearm"
		_on_inventory_changed()
	elif event.is_action_pressed(&"next_throwable"):
		throwable = THROWABLES[(THROWABLES.find(throwable) + 1) % THROWABLES.size()]
		_hud.flash("%s (%d)" % [ItemDB.get_item(throwable).name, inventory.count_of(throwable)])
	elif event.is_action_pressed(&"throw"):
		_try_throw()


func _process(delta: float) -> void:
	if is_local():
		_shake = move_toward(_shake, 0.0, delta * 1.5)
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08
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
	if not is_local():
		return
	_move(delta)
	_update_focus()
	if is_reloading and _now() >= _busy_until:
		is_reloading = false
	_update_aim(delta)
	_try_fire()
	view_model.rotation.x = move_toward(view_model.rotation.x, -0.7 if is_reloading else 0.0, delta * 6.0)
	_hud.update_status(self)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var down := not vitals.is_up()
	var crouching := captured and Input.is_action_pressed(&"crouch") and not down
	var carrying := inventory.hands != &""
	if captured and Input.is_action_just_pressed(&"jump") and is_on_floor() and not carrying and not crouching and not down:
		velocity.y = JUMP_VELOCITY
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif captured and Input.is_action_pressed(&"sprint") and not carrying:
		speed = SPRINT_SPEED
	if is_aiming:
		speed = minf(speed, WALK_SPEED) * ADS_SPEED_MULT
	if down:
		speed = CRAWL_SPEED
	speed *= load_mult
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if captured else Vector2.ZERO
	var target := (global_basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	move_and_slide()
	var head_y := DOWNED_HEAD_Y if down else (CROUCH_HEAD_Y if crouching else STAND_HEAD_Y)
	head.position.y = move_toward(head.position.y, head_y, 4.0 * delta)


func _update_focus() -> void:
	_focus = null
	_revive_target = null
	if not vitals.is_up():
		_hud.set_prompt("")
		return
	var from := camera.global_position
	var exclude: Array[RID] = [get_rid()]
	for child in get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REVIVE_RANGE, ITEM_MASK | HITBOX_MASK | 1, exclude)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	var other := Vitals.find_on(collider) if collider is Area3D else null
	if other and other.downed:
		_revive_target = other.get_parent()
		var kit := _best_revive_kit()
		_hud.set_prompt("[E] Revive (%s, %.0f s)" % [kit.name, kit.stats.revive_s] if kit else "Downed - you need an IFAK or trauma kit to revive")
		return
	if collider is WorldItem and from.distance_to(hit.position) <= INTERACT_RANGE:
		_focus = collider
	_hud.set_prompt(_focus.describe() if _focus else "")


## The revive kit this player would use: the fastest one carried.
func _best_revive_kit() -> ItemData:
	var best: ItemData = null
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inventory.containers[container]:
			var item := ItemDB.get_item(entry.id)
			if item.stats.has("revive_hp") and (best == null or item.stats.revive_s < best.stats.revive_s):
				best = item
	return best


func _try_fire() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or inventory.hands != &"" or not vitals.is_up():
		return
	var weapon := active_weapon()
	if weapon == null or weapon.type != "weapon":
		return
	var auto: bool = weapon.stats.get("auto", false)
	if not (Input.is_action_pressed(&"fire") if auto else Input.is_action_just_pressed(&"fire")):
		return
	var now := _now()
	if now < _next_shot or now < _busy_until:
		return
	if inventory.rounds_in(active_slot) <= 0:
		if Input.is_action_just_pressed(&"fire"):
			_hud.flash("Empty - R to reload" if inventory.spare_rounds(_ammo_of(weapon)) > 0 else "Out of ammo")
		return
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	_server_fire.rpc_id(1, camera.global_position, _spread_direction(weapon), active_slot)
	_kick(weapon)


func _update_aim(delta: float) -> void:
	var weapon := active_weapon()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	is_aiming = captured and vitals.is_up() and weapon != null and weapon.type == "weapon" and inventory.hands == &"" \
		and not is_reloading and Input.is_action_pressed(&"aim")
	var fov := float(weapon.stats.get("ads_fov", 55)) if is_aiming else BASE_FOV
	camera.fov = lerpf(camera.fov, fov, minf(delta * 12.0, 1.0))
	var ads_view := ADS_EYE - VoxelArt.sight_point(VoxelArt.model_for(weapon)) if weapon else HIP_VIEW
	view_model.position = view_model.position.lerp(ads_view if is_aiming else HIP_VIEW, minf(delta * 14.0, 1.0))


## Shot direction inside the weapon's cone. Spread is computed on the shooter's machine
## (co-op: the host trusts it) and widens when moving or airborne.
func _spread_direction(weapon: ItemData) -> Vector3:
	var spread := deg_to_rad(float(weapon.stats.get("spread_deg", 1.0)))
	if is_aiming:
		spread *= ADS_SPREAD_MULT
	var horizontal := Vector2(velocity.x, velocity.z).length()
	spread *= 1.0 + clampf(horizontal / WALK_SPEED, 0.0, 1.5)
	if not is_on_floor():
		spread *= 2.5
	elif Input.is_action_pressed(&"crouch"):
		spread *= 0.7
	var forward := -camera.global_basis.z
	var angle := randf() * TAU
	var amount := sqrt(randf()) * spread  # uniform over the cone's disc
	var offset := camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle)
	return (forward + offset * tan(amount)).normalized()


## Recoil: the view kicks up and a little sideways; aiming halves it.
func _kick(weapon: ItemData) -> void:
	var kick := deg_to_rad(float(weapon.stats.get("recoil_deg", 0.6))) * (0.5 if is_aiming else 1.0)
	head.rotation.x = clampf(head.rotation.x + kick, -1.5, 1.5)
	rotate_y(randf_range(-0.35, 0.35) * kick)


func _try_reload() -> void:
	var weapon := active_weapon()
	if weapon == null or weapon.type != "weapon" or _now() < _busy_until or inventory.hands != &"" or not vitals.is_up():
		return
	var full := ItemDB.get_item(_ammo_of(weapon)).magazine_rounds() if ItemDB.has_item(_ammo_of(weapon)) else 0
	if inventory.rounds_in(active_slot) >= full:
		return
	if inventory.spare_rounds(_ammo_of(weapon)) <= 0:
		_hud.flash("No spare magazines")
		return
	_busy_until = _now() + float(weapon.stats.get("reload_s", 2.0))
	is_reloading = true
	_server_reload.rpc_id(1, active_slot)


func _try_throw() -> void:
	if _now() < _busy_until or inventory.hands != &"" or not vitals.is_up():
		return
	if inventory.count_of(throwable) <= 0:
		_hud.flash("No %s left" % ItemDB.get_item(throwable).name)
		return
	_busy_until = _now() + THROW_BUSY_S
	_server_throw.rpc_id(1, camera.global_position, -camera.global_basis.z, throwable)


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
	_update_view_model()


## First-person weapon: the same voxel model others see, parented to the camera.
func _update_view_model() -> void:
	var weapon := active_weapon()
	var id: StringName = weapon.id if is_local() and weapon and inventory.hands == &"" else &""
	if id == _view_model_id:
		return
	_view_model_id = id
	for child in view_model.get_children():
		child.queue_free()
	if id != &"":
		view_model.add_child(VoxelArt.instance(VoxelArt.model_for(weapon), model.variant))


# --- Host-side requests ---------------------------------------------------------------

func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == name.to_int()


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
		_client_message.rpc_id(name.to_int(), "Not injured")
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
		_client_message.rpc_id(name.to_int(), "No medical supplies")
		return
	inventory.remove_entry(best.container, best.index)
	var item: ItemData = best.item
	_server_busy_until = _now() + float(item.stats.get("use_s", 2.0))
	vitals.server_heal_over_time(best.heal, float(item.stats.get("heal_s", 4.0)))
	_client_busy.rpc_id(name.to_int(), float(item.stats.get("use_s", 2.0)), "Using %s" % item.name)


## Inventory screen actions. `container`/`index` name a stowed entry; `slot` an equipped one.
@rpc("any_peer", "call_local", "reliable")
func _server_inventory_action(action: String, container: StringName, index: int, slot: StringName, target: StringName) -> void:
	if not _from_owner() or not vitals.is_up():
		return
	match action:
		"drop_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				_client_message.rpc_id(name.to_int(), "Empty it first")
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
				_client_message.rpc_id(name.to_int(), "Not enough room in %s" % target)
		"equip_entry":
			if not inventory.equip_entry(container, index):
				_client_message.rpc_id(name.to_int(), "No free slot for that")
		"stow_slot":
			var removed := inventory.unequip(slot)
			if removed.is_empty():
				return
			for c in Inventory.CONTAINERS:
				if inventory.insert_entry(c, {"id": removed.id, "count": 1, "state": removed.state}):
					return
			inventory.take(removed.id, 1, removed.state)  # no room: straight back on
			_client_message.rpc_id(name.to_int(), "No room to stow that")


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
		_client_message.rpc_id(name.to_int(), "No room for %s" % ItemDB.get_item(item.item_id).name)
	elif taken >= item.count:
		GameState.item_taken(item.uid)
		item.queue_free()
	else:
		item.count -= taken
		_client_message.rpc_id(name.to_int(), "Took %d, no room for the rest" % taken)


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

## Revives a downed body (a teammate, later a squadmate) with the fastest kit carried. The
## kit is used up when the revive completes, if both are still there and in range.
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
	var kit := _best_revive_kit()
	if kit == null:
		_client_message.rpc_id(name.to_int(), "You need an IFAK or trauma kit")
		return
	var seconds := float(kit.stats.revive_s)
	_server_busy_until = _now() + seconds
	_client_busy.rpc_id(name.to_int(), seconds, "Reviving...")
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree() or not is_instance_valid(target) or not other.downed or not vitals.is_up():
		return
	if target.global_position.distance_to(global_position) > REVIVE_RANGE + 1.0:
		_client_message.rpc_id(name.to_int(), "Revive interrupted")
		return
	for container in Inventory.CONTAINERS:
		var list: Array = inventory.containers[container]
		for i in list.size():
			if list[i].id == kit.id:
				inventory.remove_entry(container, i)
				other.server_revive(float(kit.stats.revive_hp))
				return


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


func _on_died() -> void:
	if not multiplayer.is_server():
		return
	var held := inventory.release_hands()
	if held != &"":
		_server_spawn_in_front(held)
	vitals.server_reset_health()
	_client_respawn.rpc_id(name.to_int(), CompoundLevel.current(self).next_spawn_point())


@rpc("any_peer", "call_local", "reliable")
func _client_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
	_hud.flash("You were killed. Respawned.")


@rpc("any_peer", "call_local", "reliable")
func _client_busy(seconds: float, text: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_busy_until = _now() + seconds
	if _hud:
		_hud.flash(text)


## A flashbang went off in sight: the whiteout is strongest when you were looking at it.
@rpc("any_peer", "call_local", "reliable")
func _client_flashed(pos: Vector3, amount: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _hud == null:
		return
	var facing := (-camera.global_basis.z).dot((pos - camera.global_position).normalized())
	_hud.whiteout(amount * (1.0 if facing > 0.3 else 0.35))


@rpc("any_peer", "call_local", "reliable")
func _client_shake(amount: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_shake = maxf(_shake, amount)


@rpc("any_peer", "call_local", "reliable")
func _client_message(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _hud:
		_hud.flash(text)
