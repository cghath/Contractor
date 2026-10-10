class_name PlayerInput
extends Node
## The human driver of a Soldier, active only on the player's own machine: mouse look and
## action keys, the first-person camera and weapon view model, what's under the crosshair
## (pickups, downed bodies), and the HUD. Movement keys are read by SoldierMovement.
## Everything it does to shared state goes through the body's host-side requests.

const MOUSE_SENSITIVITY := 0.0025
const BASE_FOV := 80.0
## View model position (camera-local) at the hip; aiming puts the weapon's sight point
## (VoxelArt.sight_point) here instead.
const HIP_VIEW := Vector3(0.14, -0.16, -0.38)
const ADS_EYE := Vector3(0.0, -0.012, -0.24)
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1
## Throwables in the order Shift+G cycles them.
const THROWABLES: Array[StringName] = [&"frag_grenade", &"flashbang", &"smoke_grenade"]

@onready var body: Soldier = get_parent()

var hud: Hud
## The ACE-style interaction menu (hold Left Ctrl; Left Ctrl + Left Alt for yourself).
var interaction: InteractionMenu
## The grenade type G throws.
var throwable: StringName = &"frag_grenade"
var _focus: Node3D  # an item or downed body under the crosshair, for the prompt
var _view_model_id: StringName = &""
var _shake := 0.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	if not body.is_node_ready():
		await body.ready  # children are ready before their parent
	if not body.is_local():
		return
	body.camera.current = true
	body.camera.cull_mask &= ~LOCAL_ONLY_LAYER
	body.model.render_layers = LOCAL_ONLY_LAYER
	body.gear.render_layers = LOCAL_ONLY_LAYER
	hud = Hud.new()
	hud.player = body
	body.add_child(hud)
	interaction = InteractionMenu.new(body)
	hud.add_child(interaction)
	body.loadout_changed.connect(_update_view_model)
	_update_view_model()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	var captured := _captured()
	if event is InputEventMouseMotion and captured and interaction.is_open():
		interaction.move_cursor(event.relative)  # the menu has the mouse, not the view
	elif event is InputEventMouseMotion and captured:
		var turn := MOUSE_SENSITIVITY * body.vitals.turn_mult()  # concussion slows turning
		body.rotate_y(-event.relative.x * turn)
		body.head.rotate_x(-event.relative.y * turn)
		body.head.rotation.x = clampf(body.head.rotation.x, -1.5, 1.5)
	elif event.is_action_pressed(&"inventory") or (event.is_action_pressed(&"pause") and hud.is_inventory_open()):
		hud.toggle_detail()
	elif hud.is_inventory_open():
		return  # the inventory screen has the mouse
	elif body.vitals.is_up() and hud.command_menu.handle_input(event):
		return  # F-keys, and 1-9 / wheel / middle click while the command menu is open
	elif event.is_action_pressed(&"debug_hurt") and OS.is_debug_build():
		body._server_debug_hurt.rpc_id(1, 40.0)
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not body.vitals.is_up():
		return  # downed: no giving up (handoff); wait for a revive or bleed out
	elif interaction.is_open() and event is InputEventMouseButton:
		return  # clicks don't fire through the interaction menu
	elif event.is_action_pressed(&"grenade"):
		# G throws, Shift+G switches grenade type, Alt+G drops what you're holding.
		if event is InputEventKey and event.alt_pressed:
			body._server_drop.rpc_id(1, body.active_slot)
		elif event is InputEventKey and event.shift_pressed:
			throwable = THROWABLES[(THROWABLES.find(throwable) + 1) % THROWABLES.size()]
			hud.flash("%s (%d)" % [ItemDB.get_item(throwable).name, body.inventory.count_of(throwable)])
		else:
			_try_throw()
	elif event.is_action_pressed(&"reload"):
		_try_reload()
	elif event.is_action_pressed(&"use_medical"):
		body._server_use_medical.rpc_id(1)
	elif event.is_action_pressed(&"weapon_primary"):
		body.select_weapon(&"primary")
	elif event.is_action_pressed(&"weapon_sidearm"):
		body.select_weapon(&"sidearm")


func _process(delta: float) -> void:
	_update_interaction(delta)
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	body.camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	body.camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08


## Runs after the body has moved this frame (children process after their parent).
func _physics_process(delta: float) -> void:
	_update_focus()
	_update_aim(delta)
	_try_fire()
	body.view_model.rotation.x = move_toward(body.view_model.rotation.x, -0.7 if body.is_reloading else 0.0, delta * 6.0)
	# Settle sway after a stop (W3, SoldierMovement.weapon_sway).
	var sway := body.movement.weapon_sway()
	body.view_model.rotation.y = sway.x
	body.view_model.rotation.z = sway.y
	hud.update_status(body)


## Where the crosshair meets the world (up to 150 m), or null.
func crosshair_ground() -> Variant:
	var from := body.camera.global_position
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from - body.camera.global_basis.z * 150.0, 1, [body.get_rid()]))
	return null if hit.is_empty() else hit.position


func flash(text: String) -> void:
	if hud:
		hud.flash(text)


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
		hud.set_prompt("[Ctrl] %s" % (collider as WorldItem).describe())
	else:
		hud.set_prompt("")


## Hold Left Ctrl for the interaction menu, Left Ctrl + Left Alt for yourself; letting go
## performs the highlighted action. Going down or opening the inventory cancels it.
func _update_interaction(delta: float) -> void:
	var allowed := _captured() and body.vitals.is_up() and not hud.is_inventory_open()
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


func _try_fire() -> void:
	if not _captured() or body.inventory.hands != &"" or not body.vitals.is_up() or interaction.is_open() \
			or body.carry_mode == Soldier.CARRY:  # both hands on the casualty
		return
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon":
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
			hud.flash("Empty - R to reload" if body.inventory.spare_rounds(Soldier._ammo_of(weapon)) > 0 else "Out of ammo")
		return
	body._next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600))
	body._server_fire.rpc_id(1, body.camera.global_position, body._spread_direction(weapon), body.active_slot)
	body._kick(weapon)


func _update_aim(delta: float) -> void:
	var weapon := body.active_weapon()
	body.is_aiming = _captured() and body.vitals.is_up() and weapon != null and weapon.type == "weapon" \
		and body.inventory.hands == &"" and not body.is_reloading and Input.is_action_pressed(&"aim")
	var fov := float(weapon.stats.get("ads_fov", 55)) if body.is_aiming else BASE_FOV
	body.camera.fov = lerpf(body.camera.fov, fov, minf(delta * 12.0, 1.0))
	var ads_view := ADS_EYE - VoxelArt.sight_point(VoxelArt.model_for(weapon)) if weapon else HIP_VIEW
	body.view_model.position = body.view_model.position.lerp(ads_view if body.is_aiming else HIP_VIEW, minf(delta * 14.0, 1.0))


func _try_reload() -> void:
	var weapon := body.active_weapon()
	var now := Soldier._now()
	if weapon == null or weapon.type != "weapon" or now < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	var ammo := Soldier._ammo_of(weapon)
	var full := ItemDB.get_item(ammo).magazine_rounds() if ItemDB.has_item(ammo) else 0
	if body.inventory.rounds_in(body.active_slot) >= full:
		return
	if body.inventory.spare_rounds(ammo) <= 0:
		hud.flash("No spare magazines")
		return
	body._busy_until = now + body.reload_seconds(weapon)
	body.is_reloading = true
	body._server_reload.rpc_id(1, body.active_slot)


func _try_throw() -> void:
	if Soldier._now() < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	if body.inventory.count_of(throwable) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(throwable).name)
		return
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	body._server_throw.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z, throwable)


## First-person weapon: the same voxel model others see, parented to the camera.
func _update_view_model() -> void:
	var weapon := body.active_weapon()
	var id: StringName = weapon.id if weapon and body.inventory.hands == &"" else &""
	if id == _view_model_id:
		return
	_view_model_id = id
	for child in body.view_model.get_children():
		child.queue_free()
	if id != &"":
		body.view_model.add_child(VoxelArt.instance(VoxelArt.model_for(weapon), body.model.variant))
