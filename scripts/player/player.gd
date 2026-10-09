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
const INTERACT_RANGE := 2.2
## Carried mass below this costs no speed; at MAX_LOAD_KG you are at the slowest.
const FREE_LOAD_KG := 15.0
const MAX_LOAD_KG := 60.0
const MIN_LOAD_MULT := 0.55
const BULKY_SPEED_MULT := 0.7
const ITEM_MASK := 1 << 2
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1
## Camo variants for players, picked from the peer id so every peer agrees.
const PLAYER_VARIANTS: Array[String] = ["multicam", "woodland", "desert", "urban"]

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
var load_mult := 1.0
var _focus: WorldItem
var _view_model_id: StringName = &""
var _hud: Hud
var _next_shot := 0.0         # owner-side fire-rate gate
var _busy_until := 0.0        # owner-side: reloading or using a medkit
var _server_next_shot := 0.0  # host-side check
var _server_busy_until := 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	# Health, armor and inventory stay host-owned even though the owner drives the body.
	$ServerSync.set_multiplayer_authority(1)
	$Model.variant = PLAYER_VARIANTS[absi(name.to_int() - 1) % PLAYER_VARIANTS.size()]  # host gets the first


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)
	vitals.died.connect(_on_died)
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


func _process(_delta: float) -> void:
	# Runs on every peer: active_slot, inventory and head rotation are replicated.
	model.look_pitch = head.rotation.x
	model.reloading = is_reloading
	if inventory.hands != &"" or (active_weapon() != null and active_slot == &"primary"):
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
	_try_fire()
	view_model.rotation.x = move_toward(view_model.rotation.x, -0.7 if is_reloading else 0.0, delta * 6.0)
	_hud.update_status(self)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var crouching := captured and Input.is_action_pressed(&"crouch")
	var carrying := inventory.hands != &""
	if captured and Input.is_action_just_pressed(&"jump") and is_on_floor() and not carrying and not crouching:
		velocity.y = JUMP_VELOCITY
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif captured and Input.is_action_pressed(&"sprint") and not carrying:
		speed = SPRINT_SPEED
	speed *= load_mult
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if captured else Vector2.ZERO
	var target := (global_basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	move_and_slide()
	head.position.y = move_toward(head.position.y, CROUCH_HEAD_Y if crouching else STAND_HEAD_Y, 4.0 * delta)


func _update_focus() -> void:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * INTERACT_RANGE, ITEM_MASK | 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_focus = hit.get("collider") as WorldItem
	_hud.set_prompt(_focus.describe() if _focus else "")


func _try_fire() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or inventory.hands != &"":
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
	_server_fire.rpc_id(1, camera.global_position, -camera.global_basis.z, active_slot)


func _try_reload() -> void:
	var weapon := active_weapon()
	if weapon == null or weapon.type != "weapon" or _now() < _busy_until or inventory.hands != &"":
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
	if not _from_owner() or vitals.health <= 0.0 or inventory.hands != &"":
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
func _server_reload(slot: StringName) -> void:
	if not _from_owner() or _now() < _server_busy_until - 0.1:
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
	if not _from_owner() or vitals.health <= 0.0 or _now() < _server_busy_until - 0.1:
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
	if not _from_owner():
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
	if not _from_owner():
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


@rpc("any_peer", "call_local", "reliable")
func _client_message(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _hud:
		_hud.flash(text)
