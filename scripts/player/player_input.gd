class_name PlayerInput
extends Node
## Human driver for a Soldier: mouse and keyboard, the first-person camera and weapon view
## model, the crosshair target (pickups and revives) and the HUD. Only active on the peer
## that owns the body.

const MOUSE_SENSITIVITY := 0.0025
const BASE_FOV := 80.0
## View model position (camera-local) at the hip; aiming puts the weapon's sight point
## (VoxelArt.sight_point) here instead.
const HIP_VIEW := Vector3(0.14, -0.16, -0.38)
const ADS_EYE := Vector3(0.0, -0.012, -0.24)
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1

@onready var soldier: Soldier = get_parent()
@onready var camera: Camera3D = $"../Head/Camera"
@onready var view_model: Node3D = $"../Head/Camera/ViewModel"

var hud: Hud
## The pickup or downed body under the crosshair.
var focus: WorldItem
var revive_target: Node3D
var _view_model_id: StringName = &""


func _ready() -> void:
	process_physics_priority = -1  # set the soldier's controls before it moves
	set_physics_process(false)
	set_process_unhandled_input(false)
	if not soldier.is_node_ready():
		await soldier.ready  # children are ready before their parent
	if not soldier.is_multiplayer_authority():
		return
	camera.current = true
	camera.cull_mask &= ~LOCAL_ONLY_LAYER
	soldier.model.render_layers = LOCAL_ONLY_LAYER
	soldier.gear.render_layers = LOCAL_ONLY_LAYER
	if soldier.voxel_viewer:
		soldier.voxel_viewer.requires_visuals = true
	hud = Hud.new()
	hud.player = soldier
	soldier.add_child(hud)
	soldier.message.connect(hud.flash)
	soldier.busy.connect(func(_seconds: float, text: String) -> void: hud.flash(text))
	soldier.respawned.connect(func() -> void: hud.flash("You were killed. Respawned."))
	soldier.loadout_changed.connect(_update_view_model)
	_update_view_model()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_physics_process(true)
	set_process_unhandled_input(true)


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := _captured()
	if event is InputEventMouseMotion and captured:
		soldier.look(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"inventory") or (event.is_action_pressed(&"pause") and hud.is_inventory_open()):
		hud.toggle_detail()
	elif hud.is_inventory_open():
		return  # the inventory screen has the mouse
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not soldier.vitals.is_up():
		if event.is_action_pressed(&"give_up"):
			soldier.give_up()
	elif event.is_action_pressed(&"interact") and revive_target:
		soldier.revive(revive_target)
	elif event.is_action_pressed(&"interact") and focus:
		soldier.interact(focus)
	elif event.is_action_pressed(&"drop"):
		soldier.drop()
	elif event.is_action_pressed(&"reload"):
		soldier.reload()
	elif event.is_action_pressed(&"use_medical"):
		soldier.use_medical()
	elif event.is_action_pressed(&"weapon_primary"):
		soldier.select_weapon(&"primary")
	elif event.is_action_pressed(&"weapon_sidearm"):
		soldier.select_weapon(&"sidearm")


func _physics_process(delta: float) -> void:
	var captured := _captured()
	soldier.move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if captured else Vector2.ZERO
	soldier.want_sprint = captured and Input.is_action_pressed(&"sprint")
	soldier.want_crouch = captured and Input.is_action_pressed(&"crouch")
	soldier.want_aim = captured and Input.is_action_pressed(&"aim")
	if captured and Input.is_action_just_pressed(&"jump"):
		soldier.jump()
	if captured:
		soldier.trigger(Input.is_action_pressed(&"fire"), Input.is_action_just_pressed(&"fire"))
	_update_focus()
	_update_view(delta)
	hud.update_status(soldier)


func _update_focus() -> void:
	focus = null
	revive_target = null
	if not soldier.vitals.is_up():
		hud.set_prompt("")
		return
	var from := camera.global_position
	var exclude: Array[RID] = [soldier.get_rid()]
	for child in soldier.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var mask := Soldier.ITEM_MASK | Soldier.HITBOX_MASK | 1
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * Soldier.REVIVE_RANGE, mask, exclude)
	query.collide_with_areas = true
	var hit := soldier.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	var other := Vitals.find_on(collider) if collider is Area3D else null
	if other and other.downed:
		revive_target = other.get_parent()
		var kit := soldier.best_revive_kit()
		hud.set_prompt("[E] Revive (%s, %.0f s)" % [kit.name, kit.stats.revive_s] if kit else "Downed - you need an IFAK or trauma kit to revive")
		return
	if collider is WorldItem and from.distance_to(hit.position) <= Soldier.INTERACT_RANGE:
		focus = collider
	hud.set_prompt(focus.describe() if focus else "")


## Zoom, the view model sliding between hip and sights, and the reload tilt.
func _update_view(delta: float) -> void:
	var weapon := soldier.active_weapon()
	var fov := float(weapon.stats.get("ads_fov", 55)) if soldier.is_aiming else BASE_FOV
	camera.fov = lerpf(camera.fov, fov, minf(delta * 12.0, 1.0))
	var ads_view := ADS_EYE - VoxelArt.sight_point(VoxelArt.model_for(weapon)) if weapon else HIP_VIEW
	view_model.position = view_model.position.lerp(ads_view if soldier.is_aiming else HIP_VIEW, minf(delta * 14.0, 1.0))
	view_model.rotation.x = move_toward(view_model.rotation.x, -0.7 if soldier.is_reloading else 0.0, delta * 6.0)


## First-person weapon: the same voxel model others see, parented to the camera.
func _update_view_model() -> void:
	var weapon := soldier.active_weapon()
	var id: StringName = weapon.id if weapon and soldier.inventory.hands == &"" else &""
	if id == _view_model_id:
		return
	_view_model_id = id
	for child in view_model.get_children():
		child.queue_free()
	if id != &"":
		view_model.add_child(VoxelArt.instance(VoxelArt.model_for(weapon), soldier.model.variant))
