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
var load_mult := 1.0
var _focus: WorldItem
var _view_model_id: StringName = &""
var _hud: Hud
var _next_shot := 0.0         # owner-side fire-rate gate
var _server_next_shot := 0.0  # host-side check


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
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"interact") and _focus:
		_server_interact.rpc_id(1, _focus.get_path())
	elif event.is_action_pressed(&"drop"):
		_server_drop.rpc_id(1, active_slot)
	elif event.is_action_pressed(&"inventory"):
		_hud.toggle_detail()
	elif event.is_action_pressed(&"weapon_primary"):
		active_slot = &"primary"
		_on_inventory_changed()
	elif event.is_action_pressed(&"weapon_sidearm"):
		active_slot = &"sidearm"
		_on_inventory_changed()


func _process(_delta: float) -> void:
	# Runs on every peer: active_slot, inventory and head rotation are replicated.
	model.look_pitch = head.rotation.x
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
	_try_fire()
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
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_shot:
		return
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	_server_fire.rpc_id(1, camera.global_position, -camera.global_basis.z, active_slot)


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
	var now := Time.get_ticks_msec() / 1000.0
	if now < _server_next_shot - 0.03:  # tolerate network jitter
		return
	_server_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	if origin.distance_to(camera.global_position) > 1.0:
		origin = camera.global_position  # don't trust a far-off muzzle
	var result := Ballistics.fire(self, origin, direction.normalized(), weapon)
	if result.result != "none":
		CompoundLevel.current(self).show_impact.rpc(result.position, result.normal, result.result)


@rpc("any_peer", "call_local", "reliable")
func _server_interact(path: NodePath) -> void:
	if not _from_owner():
		return
	var item := get_node_or_null(path) as WorldItem
	if item == null or item.is_queued_for_deletion():
		return
	if item.global_position.distance_to(global_position) > INTERACT_RANGE + 1.5:
		return
	var taken := inventory.take(item.item_id, item.count)
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
	var id := inventory.release_hands()
	if id == &"" and slot in [&"primary", &"sidearm"]:
		id = inventory.unequip(slot)
	if id != &"":
		_server_spawn_in_front(id)


func _server_spawn_in_front(id: StringName) -> void:
	var pos := global_position - global_basis.z * 0.9 + Vector3.UP * 1.0
	CompoundLevel.current(self).server_spawn_dropped(id, 1, pos)


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
func _client_message(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _hud:
		_hud.flash(text)
