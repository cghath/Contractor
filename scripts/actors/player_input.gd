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
## Proposed: where each first-person forearm's elbow sits from its hand, in view space (a
## right-handed shooter's; x mirrors for a left-handed one): the firing elbow low and out
## behind the grip, the support elbow under and behind the handguard.
const VIEW_FIRING_ELBOW := Vector3(0.09, -0.12, 0.2)
const VIEW_SUPPORT_ELBOW := Vector3(-0.07, -0.15, 0.2)
## Render layer for your own body and gear; your camera skips it.
const LOCAL_ONLY_LAYER := 1 << 1
## Throwables in the order Shift+G cycles them (next_throwable): frag and flashbang always,
## then each smoke colour you carry, then the breaching charge if you carry one (G with it
## picked places it: Charges).
const THROWABLES: Array[StringName] = [&"frag_grenade", &"flashbang", &"smoke_grenade", &"smoke_green", &"smoke_yellow", &"smoke_blue", &"smoke_purple", Charges.ITEM]
## Always in the Shift+G cycle, carried or not (smokes only show up while you have one).
const ALWAYS_CYCLED: Array[StringName] = [&"frag_grenade", &"flashbang"]

@onready var body: Soldier = get_parent()

var hud: Hud
## The ACE-style interaction menu (hold Left Ctrl; Left Ctrl + Left Alt for yourself).
var interaction: InteractionMenu
## The medical menu (H: MedicalMenu); Shift+H quick-treats yourself.
var medical_menu: MedicalMenu
## The grenade type G throws.
var throwable: StringName = &"frag_grenade"
var _focus: Node3D  # an item or downed body under the crosshair, for the prompt
var _view_model_id: StringName = &""
## The casualty on this player's shoulder, kept out of their own first-person view (it would
## fill it): drawn on LOCAL_ONLY_LAYER like their own body, so everyone else still sees it.
var _shouldered: Soldier = null
var _shake := 0.0
var _deaf := false
## Placing a breaching charge (Charges): the ghost follows the view until Fire commits it.
var placing := false
## The Escape menu (PauseMenu), on the local player only.
var pause_menu: PauseMenu
## The bug-report note panel (Insert), on the local player only.
var bug_report: BugReport
var _ghost: Node3D
## Muffled hearing: everything through a low-pass this low, and quieter.
const DEAF_CUTOFF_HZ := 600.0
const DEAF_VOLUME_DB := -12.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	if not body.is_node_ready():
		await body.ready  # children are ready before their parent
	if not body.is_local():
		return
	set_muffled(false)  # a new local player starts hearing normally, whatever came before
	body.camera.current = true
	body.camera.cull_mask &= ~LOCAL_ONLY_LAYER
	body.model.render_layers = LOCAL_ONLY_LAYER
	body.gear.render_layers = LOCAL_ONLY_LAYER
	hud = Hud.new()
	hud.player = body
	body.add_child(hud)
	pause_menu = PauseMenu.new()
	body.add_child(pause_menu)
	bug_report = BugReport.new()
	body.add_child(bug_report)
	if DevTools.on() and multiplayer.is_server():
		body.add_child(AiOverlay.new())
	interaction = InteractionMenu.new(body)
	hud.add_child(interaction)
	medical_menu = MedicalMenu.new(body)
	hud.add_child(medical_menu)
	hud.add_child(LauncherSight.new(body))  # anti-armour launchers: sight, lock, fire (wave 5)
	body.loadout_changed.connect(_update_view_model)
	_update_view_model()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


var _view_yaw := 0.0  # Soldier.view_yaw last applied


func _unhandled_input(event: InputEvent) -> void:
	var captured := _captured()
	if pause_menu.is_open() or bug_report.is_open():
		return  # the Escape menu has the mouse (it closes itself on Escape)
	elif medical_menu.is_open():
		return  # the medical menu has the mouse and the keys (it closes itself on H or Escape)
	elif event is InputEventMouseMotion and captured and interaction.is_open():
		interaction.move_cursor(event.relative)  # the menu has the mouse, not the view
	elif event is InputEventMouseMotion and captured:
		# The settings' sensitivity (and aiming sensitivity down sights); concussion slows turning.
		var turn := GameSettings.mouse_turn(MOUSE_SENSITIVITY, body.is_aiming) * body.vitals.turn_mult()
		body.rotate_y(-event.relative.x * turn)
		body.set_pitch(body.head.rotation.x - event.relative.y * turn * (-1.0 if GameSettings.invert_y() else 1.0))
	elif hud.map_screen and hud.map_screen.is_open():
		return  # the map (M) has the mouse and the keys: no reloading or throwing behind it
	elif event.is_action_pressed(&"inventory") or (event.is_action_pressed(&"pause") and hud.is_inventory_open()):
		hud.toggle_detail()
	elif hud.is_inventory_open():
		return  # the inventory screen has the mouse
	elif body.vitals.is_up() and hud.command_menu.handle_input(event):
		return  # F-keys, and 1-9 / wheel / middle click while the command menu is open
	elif event.is_action_pressed(&"debug_hurt") and DevTools.on():
		body._server_debug_hurt.rpc_id(1, 40.0)
	elif event.is_action_pressed(&"pause"):
		pause_menu.open()  # Escape: resume, return to base, main menu, quit
	elif event.is_action_pressed(&"fire") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not body.vitals.is_up():
		return  # downed: no giving up (handoff); you come round on your own, or the arrest window runs out
	elif event.is_action_pressed(ControlOptions.GET_OUT_ACTION) and ControlOptions.get_out_key() and Vehicle.ride_of(body) != null:
		Vehicle.ride_of(body).request_exit.rpc_id(1)  # the get-out key (an option; the seat's menu then has no Get out)
	elif interaction.is_open() and event is InputEventMouseButton:
		return  # clicks don't fire through the interaction menu
	elif placing and event.is_action_pressed(&"fire"):
		_commit_charge()  # Fire puts the charge where the ghost sits
	elif placing and (event.is_action_pressed(&"aim") or (event.is_action_pressed(&"grenade") and not (event is InputEventKey and (event.shift_pressed or event.alt_pressed)))):
		_stop_placing("Charge put away")
	elif event.is_action_pressed(&"grenade") and body.carry_mode != &"":
		# Hands full with a casualty: G lets go of them (Release / Put down) instead of throwing.
		body._server_release_body.rpc_id(1)
		flash("Let go" if body.carry_mode == Soldier.DRAG else "Put down")
	elif event.is_action_pressed(&"grenade"):
		# G throws, Shift+G switches grenade type, Alt+G drops what you're holding.
		if event is InputEventKey and event.alt_pressed:
			body._server_drop.rpc_id(1, body.active_slot)
		elif event is InputEventKey and event.shift_pressed:
			throwable = next_throwable(throwable, body.inventory)
			hud.flash("%s (%d)" % [ItemDB.get_item(throwable).name, body.inventory.count_of(throwable)])
		elif throwable == Charges.ITEM:
			_start_placing()
		else:
			_try_throw()
	elif event.is_action_pressed(&"reload"):
		_try_reload()
	elif event.is_action_pressed(&"quick_treat"):  # before H: H alone also matches with Shift held
		body._server_use_medical.rpc_id(1)
	elif event.is_action_pressed(&"medical_menu"):
		medical_menu.open(MedicalMenu.looked_at(body, body.camera))
	elif event.is_action_pressed(&"weapon_primary"):
		body.select_weapon(&"primary")
	elif event.is_action_pressed(&"weapon_sidearm"):
		body.select_weapon(&"sidearm")
	elif event.is_action_pressed(&"weapon_launcher") and body.inventory.slots.get(Launchers.SLOT, &"") != &"":
		body.select_weapon(Launchers.SLOT)


func _process(delta: float) -> void:
	_update_interaction(delta)
	if placing:
		_update_ghost()
	if body.view_yaw() != _view_yaw:
		# Taking hold of a casualty to drag (or letting go): the body turns round under the
		# view, so you keep looking where you were, at the casualty.
		_view_yaw = body.view_yaw()
		body.rotate_y(PI)
		body.set_pitch(body.head.rotation.x)
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	body.camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	body.camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	_update_hearing()


## Muffled hearing (blasts, flashbangs, indoor gunfire): a low-pass on the master bus while
## Vitals.deaf_left() runs, and a note when it starts.
func _update_hearing() -> void:
	if not body.is_local():
		return
	var deaf := body.vitals.deaf_left() > 0.0
	if deaf == _deaf:
		return
	_deaf = deaf
	set_muffled(deaf)
	if deaf:
		flash("Ears ringing")


## The Master bus volume from before hearing was muffled (put back when it clears).
static var _volume_before := 0.0


## Muffles the Master bus (a low-pass, quieter) or clears it, putting back the volume from
## before; already so, it does nothing. The bus is global and outlives the player: whoever
## muffles it clears it again (audit A2-04: deaf when leaving, the menu and the next session
## stayed muffled).
static func set_muffled(on: bool) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	var has_filter := AudioServer.get_bus_effect_count(bus) > 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLowPassFilter
	if on == (has_filter and AudioServer.is_bus_effect_enabled(bus, 0)):
		return
	if on:
		if not has_filter:
			var filter := AudioEffectLowPassFilter.new()
			filter.cutoff_hz = DEAF_CUTOFF_HZ
			AudioServer.add_bus_effect(bus, filter, 0)
		_volume_before = AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_effect_enabled(bus, 0, on)
	AudioServer.set_bus_volume_db(bus, DEAF_VOLUME_DB if on else _volume_before)


## Leaving (the session ends, the level changes, the body goes): hearing comes back with it.
func _exit_tree() -> void:
	if _deaf:
		_deaf = false
		set_muffled(false)


## Runs after the body has moved this frame (children process after their parent).
func _physics_process(delta: float) -> void:
	_update_focus()
	_update_aim(delta)
	_try_fire()
	var tilt := minf(-0.7 if body.is_reloading else 0.0, -CharacterModel.VIEW_LOWER_PITCH * body.model.view_lower())
	body.view_model.rotation.x = move_toward(body.view_model.rotation.x, tilt, delta * 6.0)
	body.view_model.visible = body.carry_mode == &""  # both hands on the casualty: no weapon in view
	_hide_shouldered()
	# Settle sway after a stop (W3, SoldierMovement.weapon_sway).
	var sway := body.movement.weapon_sway()
	body.view_model.rotation.y = sway.x
	body.view_model.rotation.z = sway.y
	hud.update_status(body)


## Keeps the casualty this player has up on the shoulder out of their own camera (they still see
## it lifted off the ground and laid back down).
func _hide_shouldered() -> void:
	var shown := body.model.carry_shown()
	var on: Soldier = null
	if shown.get("mode", &"") == CharacterModel.CARRY:
		var ph := body.model.carry_phase()
		var up: bool = ph.is_empty() or (ph.phase == &"lift" and ph.u > 0.8) or (ph.phase == &"lower" and ph.u < 0.2)
		on = shown.get("body") as Soldier if up else null
	if on == _shouldered:
		return
	if is_instance_valid(_shouldered):
		_shouldered.model.render_layers = 1
		_shouldered.gear.render_layers = 1
	_shouldered = on
	if on:
		on.model.render_layers = LOCAL_ONLY_LAYER
		on.gear.render_layers = LOCAL_ONLY_LAYER


## Where the crosshair meets the world (up to 150 m), or null.
func crosshair_ground() -> Variant:
	var from := body.camera.global_position
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from - body.camera.global_basis.z * 150.0, 1, [body.get_rid()]))
	return null if hit.is_empty() else hit.position


func flash(text: String) -> void:
	if hud:
		SessionLog.note("shown to the player: " + text)
		hud.flash(text)
	elif body and body.is_ai():  # an AI's own messages (what it's treating, why it can't): no screen, but worth a line
		SessionLog.note("%s (AI): %s" % [body.log_name(), text])


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
	if not _captured() or placing or body.inventory.hands != &"" or not body.vitals.is_up() or interaction.is_open() \
			or body.carry_mode != &"" or is_instance_valid(body.vehicle):  # both hands on the casualty; or riding (the seat's gun fires: Vehicle)
		return
	var weapon := body.active_weapon()
	if Launchers.is_launcher(weapon):
		LauncherSight.of(body).try_fire()  # its own fire path (wave 5)
		return
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
	body.is_aiming = _captured() and body.vitals.is_up() and weapon != null and (weapon.type == "weapon" or Launchers.is_launcher(weapon)) \
		and body.inventory.hands == &"" and not body.is_reloading and Input.is_action_pressed(&"aim")
	var fov := float(weapon.stats.get("ads_fov", 55)) if body.is_aiming else GameSettings.fov()
	body.camera.fov = lerpf(body.camera.fov, fov, minf(delta * 12.0, 1.0))
	var hip_view := HIP_VIEW * Vector3(-1.0 if body.left_handed else 1.0, 1, 1)  # off the firing shoulder
	var ads_view := ADS_EYE - VoxelArt.sight_point(VoxelArt.model_for(weapon)) if weapon and not Launchers.is_launcher(weapon) else hip_view
	var lowered := CharacterModel.VIEW_LOWER_OFFSET * body.model.view_lower()  # ducks while the hands are busy
	body.view_model.position = body.view_model.position.lerp((ads_view if body.is_aiming else hip_view) + lowered, minf(delta * 14.0, 1.0))


func _try_reload() -> void:
	var weapon := body.active_weapon()
	var now := Soldier._now()
	if Launchers.is_launcher(weapon):
		LauncherSight.of(body).try_reload()  # load or swap its round (wave 5)
		return
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


## The grenade type after `current` in the Shift+G cycle: THROWABLES order, skipping smoke
## colours `inventory` doesn't carry.
static func next_throwable(current: StringName, inventory: Inventory) -> StringName:
	var start := maxi(THROWABLES.find(current), 0)
	for step in range(1, THROWABLES.size() + 1):
		var id := THROWABLES[(start + step) % THROWABLES.size()]
		if id in ALWAYS_CYCLED or inventory.count_of(id) > 0:
			return id
	return current


func _try_throw() -> void:
	if Soldier._now() < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	if body.inventory.count_of(throwable) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(throwable).name)
		return
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	body._server_throw.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z, throwable)


## First-person weapon: the same voxel model others see, parented to the camera, with the
## player's own forearms and hands on it (the body itself is hidden from its own camera): the
## firing hand on the grip, the other on the support point, mirrored for a left-handed shooter.
func _update_view_model() -> void:
	var weapon := body.active_weapon()
	var id: StringName = weapon.id if weapon and body.inventory.hands == &"" else &""
	var key := StringName("%s|%s|%s|%s" % [id, body.left_handed, body.model.variant, body.model.body])
	if key == _view_model_id:
		return
	_view_model_id = key
	for child in body.view_model.get_children():
		child.queue_free()
	if id == &"":
		return
	if Launchers.is_launcher(weapon):
		body.view_model.add_child(LauncherSight.view_node(weapon))  # placeholder launcher (wave 5)
		return
	var model := VoxelArt.model_for(weapon)
	body.view_model.add_child(VoxelArt.instance(model, body.model.variant))
	var points := VoxelArt.hand_points(model)
	if points.is_empty():
		return
	var side := -1.0 if body.left_handed else 1.0  # the firing hand's side
	for hand: Array in [[points.grip, VIEW_FIRING_ELBOW], [points.support, VIEW_SUPPORT_ELBOW]]:
		var palm: Vector3 = hand[0]
		var elbow: Vector3 = palm + (hand[1] as Vector3) * Vector3(side, 1, 1)
		var forearm := VoxelArt.instance(VoxelArt.body_part("forearm", body.model.body), body.model.variant)
		forearm.name = "ViewForearm"
		# The forearm's pivot is the elbow and its palm FOREARM down its -y: point -y at the palm.
		var up := (elbow - palm).normalized()
		var across := up.cross(Vector3.BACK).normalized() if absf(up.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
		var basis := Basis(across, up, across.cross(up)).orthonormalized()
		forearm.transform = Transform3D(basis.scaled(Vector3.ONE * palm.distance_to(elbow) / CharacterModel.FOREARM), elbow)
		body.view_model.add_child(forearm)


# --- Placing a charge (Charges: like Arma Reforger's explosives) --------------------------

func _start_placing() -> void:
	if Soldier._now() < body._busy_until or body.inventory.hands != &"" or body.carry_mode != &"":
		return
	if body.inventory.count_of(Charges.ITEM) <= 0:
		hud.flash("No %s left" % ItemDB.get_item(Charges.ITEM).name)
		return
	placing = true
	_ghost = Charges.make_visual(true)
	_ghost.name = "ChargeGhost"
	body.get_parent().add_child(_ghost)
	_update_ghost()
	hud.flash("Place the charge: Fire to set it, G to put it away")


func _stop_placing(note := "") -> void:
	placing = false
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if note != "":
		hud.flash(note)


## The ghost sits where the charge would go, lined up with the surface: green where it can
## go, red (in front of you) where it can't.
func _update_ghost() -> void:
	if not body.vitals.is_up() or body.inventory.count_of(Charges.ITEM) <= 0 or body.inventory.hands != &"" or body.carry_mode != &"":
		_stop_placing()
		return
	var dir := -body.camera.global_basis.z
	var spot := Charges.placement(body, body.camera.global_position, dir)
	_ghost.global_transform = Charges.surface_transform(spot.pos, spot.normal, dir)
	var block := _ghost.get_node(^"Block") as MeshInstance3D
	var material := (block.mesh as BoxMesh).material as StandardMaterial3D
	material.albedo_color = Color(0.4, 1.0, 0.4, 0.45) if spot.ok else Color(1.0, 0.3, 0.3, 0.35)


func _commit_charge() -> void:
	var dir := -body.camera.global_basis.z
	if not Charges.placement(body, body.camera.global_position, dir).ok:
		hud.flash("Nothing to place it on here")
		return
	var charges := Charges.of(body)
	if charges:
		charges.request_place.rpc_id(1, body.camera.global_position, dir)
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	_stop_placing()
