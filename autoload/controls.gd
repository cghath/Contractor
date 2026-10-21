extends Node
## Registers input actions in code so project.godot stays readable and diff-friendly.
## Rebinding UI can later overwrite these from a user settings file.

const KEYS := {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	# Hold the breath while aiming (SoldierMovement.update_arms; movement phase 1). Shift is
	# sprint too, on purpose: there is no sprint while aiming, so the two never meet
	# (GameSettings.SHARED lets them keep one key). Clear of B (vehicle view), J, F (fire mode,
	# command menu), V and the side mouse buttons (optic zoom).
	&"hold_breath": [KEY_SHIFT],
	# Movement and weapon handling (design doc "Controls and feel", keys agreed since).
	&"crouch": [KEY_X],  # toggle
	&"prone": [KEY_Z],  # toggle
	&"stance_adjust": [KEY_CAPSLOCK],  # hold: W/S step stance up/down, A/D side stance
	&"lean_left": [KEY_Q],  # hold to lean, double-tap to stay, tap to return
	&"lean_right": [KEY_E],
	&"mount": [KEY_C],  # rest the weapon on a surface in front
	&"fire_mode": [KEY_F],
	&"reload": [KEY_R],
	&"medical_menu": [KEY_H],  # the medical menu (MedicalMenu); Shift+H quick-treats yourself (SHIFT_KEYS)
	&"grenade": [KEY_G],  # takes the grenade in hand (Fire throws, Aim lobs, G again puts it away); Shift+G switches type, Alt+G drops; carrying or dragging a body, lets go
	&"inventory": [KEY_TAB],
	&"map": [KEY_M],  # the map (MapScreen): grid, markers, squad, extraction
	# The objectives panel (ObjectivesPanel; Captain, 2026-10-15: "compress that big ahh mission
	# list and choose an obj"): O collapses/expands it, N picks the next active objective.
	&"objectives_toggle": [KEY_O],
	&"objectives_next": [KEY_N],
	&"weapon_primary": [KEY_1],
	&"weapon_sidearm": [KEY_2],
	&"weapon_launcher": [KEY_3],  # the anti-armour launcher (wave 5, Launchers)
	# The trigger onto the M320 under the rifle and back (Underbarrel; Captain's list for cghath,
	# 2026-10-20). Proposed key.
	&"weapon_underbarrel": [KEY_4],
	&"pause": [KEY_ESCAPE],
	&"quick_save": [KEY_HOME],  # F-keys are the squad command menu
	# Get out of the vehicle you sit in, when that option is on (ControlOptions; Captain, P0164
	# queue 8). V is free on foot and in a seat (proposed).
	&"get_out": [KEY_V],
	# Seated: switch the view between the chase camera and first person (VehicleCamera; Captain,
	# 2026-10-13: "1st person + 3rd toggle"). B is free on foot and in a seat (proposed).
	&"vehicle_view": [KEY_B],
	# Downed: hold to give up and respawn (Soldier.can_give_up; Captain, P0362). Proposed key.
	&"give_up": [KEY_J],
	# Look at an item on the ground and press it: what it is and how to use it (ItemInfo; Captain,
	# 2026-10-14: "item descriptions plus uses also needed"). I is free on foot (proposed).
	&"inspect": [KEY_I],
	&"debug_hurt": [KEY_K],  # dev tools only (DevTools.on): hurt yourself to test going down and dying
	&"voice_order": [KEY_T],  # hold: push-to-talk a squad order (VoiceOrder, voice_commands.gd)
	# Flip the NVG on your helmet down or up (Nvg; wave 7, S2). N is the next objective, so U
	# (proposed); with none mounted, it mounts the first NVG you carry.
	&"nvg_toggle": [KEY_U],
	# The light or laser on the gun in hand, on or off (GunAttachments; wave 7 S3). Proposed key.
	&"weapon_light": [KEY_L],
	# Tag the enemy you look at for the squad, by radio (EnemyTags; Captain, 2026-10-16: GR
	# Wildlands-style tagging). Y is free on foot and in a seat (proposed).
	&"tag_enemy": [KEY_Y],
	# Raise or lower your binoculars (BinocularView; Captain, 2026-10-20). B on foot: seated, B is
	# the vehicle view (GameSettings.SHARED lets them share it).
	&"binoculars": [KEY_B],
	# Auto-walk (Captain, 2026-10-20): toggles walking forward on its own (SoldierMovement.auto_walk).
	&"auto_walk": [KEY_EQUAL],
	# Walk or jog (a toggle; Captain, 2026-10-20: there was no walk, only the jog): SoldierMovement.walk_pace.
	&"walk": [KEY_P],
}
## Keys pressed with Shift held. An action without Shift still matches with it held, so
## PlayerInput checks these first.
const SHIFT_KEYS := {
	&"quick_treat": KEY_H,  # treat yourself with the next item you carry (Soldier._server_use_medical)
}
const MOUSE := {
	&"fire": MOUSE_BUTTON_LEFT,
	&"aim": MOUSE_BUTTON_RIGHT,
}
## Rebindable actions on mouse buttons by default (GameSettings.BINDABLE; Captain, P0362): an
## optic's zoom on the side buttons, forward (Mouse 5) in and back (Mouse 4) out; a
## holographic sight's magnifier flips up on zoom in and down on zoom out (GunSight.zoom_step).
const BUTTONS := {
	&"zoom_in": MOUSE_BUTTON_XBUTTON2,
	&"zoom_out": MOUSE_BUTTON_XBUTTON1,
}
## Keys that only count on the left of the keyboard: [action, key, needs Ctrl held].
## Hold Left Ctrl for the interaction menu (InteractionMenu); add Left Alt while holding it
## for self-interaction. (The design doc's Left Windows opens the Start menu.)
const LEFT_KEYS := [
	[&"interact", KEY_CTRL, false],
	[&"self_interact", KEY_ALT, true],
]
## The gamepad layout (wave 7, S4; Xbox names), beside the keys and never in their place:
## every on-foot and seated control is a button, a trigger or a stick here, or a slice of the
## pad wheel (hold View: PadWheel, the right stick picks, letting go does it). The settings'
## Keys list rebinds only keys; these stay as they are.
const JOY_BUTTONS := {
	&"jump": [JOY_BUTTON_A],  # also the brake, driving
	&"crouch": [JOY_BUTTON_B],
	&"reload": [JOY_BUTTON_X],
	&"interact": [JOY_BUTTON_Y],  # hold: the interaction menu, the right stick picks
	&"give_up": [JOY_BUTTON_Y],  # downed, hold Y (the interaction menu is shut while down)
	&"self_interact": [JOY_BUTTON_RIGHT_STICK],  # Y held, click the right stick: yourself
	&"lean_left": [JOY_BUTTON_LEFT_SHOULDER],
	&"lean_right": [JOY_BUTTON_RIGHT_SHOULDER],
	&"sprint": [JOY_BUTTON_LEFT_STICK],
	&"hold_breath": [JOY_BUTTON_LEFT_STICK],  # aiming (no sprint while aiming)
	&"weapon_primary": [JOY_BUTTON_DPAD_UP],
	&"weapon_sidearm": [JOY_BUTTON_DPAD_RIGHT],
	&"grenade": [JOY_BUTTON_DPAD_LEFT],
	&"prone": [JOY_BUTTON_DPAD_DOWN],
	&"pause": [JOY_BUTTON_START],
	&"pad_wheel": [JOY_BUTTON_BACK],  # hold: the pad wheel (PadWheel)
}
## Stick and trigger directions: [axis, +1 or -1]. Look's deadzone and curve are the
## settings' (GameSettings.stick_look), so its actions keep almost none of their own.
const JOY_AXES := {
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	&"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	&"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}
const LOOK_ACTIONS: Array[StringName] = [&"look_left", &"look_right", &"look_up", &"look_down"]
## The pad wheel's slices (PadWheel), clockwise from the top: [action, label]. The rest of the
## keyboard's controls, each pressed for a moment when picked.
const PAD_WHEEL := [
	[&"inventory", "Inventory"], [&"map", "Map"], [&"medical_menu", "Medical"], [&"quick_treat", "Quick treat"],
	[&"fire_mode", "Fire mode"], [&"weapon_launcher", "Launcher"], [&"mount", "Rest weapon"], [&"inspect", "Inspect"],
	[&"zoom_in", "Zoom in"], [&"zoom_out", "Zoom out"], [&"objectives_next", "Next objective"], [&"objectives_toggle", "Objectives list"],
	[&"vehicle_view", "Vehicle view"], [&"get_out", "Get out"], [&"quick_save", "Quick save"],
	[&"nvg_toggle", "NVG up/down"], [&"weapon_light", "Weapon light"], [&"tag_enemy", "Tag enemy"],
	[&"binoculars", "Binoculars"], [&"auto_walk", "Auto-walk"], [&"walk", "Walk / jog"],
	[&"weapon_underbarrel", "Underbarrel launcher"],
]
## Not on the pad (keyboard only): the dev key, and the held keyboard modes with no pad
## equivalent yet (stance adjust holds W/S/A/D; push-to-talk orders are typed or spoken).
const PAD_EXEMPT: Array[StringName] = [&"debug_hurt", &"stance_adjust", &"voice_order"]


func _enter_tree() -> void:
	for action: StringName in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action: StringName in SHIFT_KEYS:
		_ensure(action)
		var shifted := InputEventKey.new()
		shifted.physical_keycode = SHIFT_KEYS[action]
		shifted.shift_pressed = true
		InputMap.action_add_event(action, shifted)
	for binding: Array in LEFT_KEYS:
		_ensure(binding[0])
		var event := InputEventKey.new()
		event.physical_keycode = binding[1]
		event.location = KEY_LOCATION_LEFT
		event.ctrl_pressed = binding[2]
		InputMap.action_add_event(binding[0], event)
	for action: StringName in MOUSE:
		_ensure(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE[action]
		InputMap.action_add_event(action, event)
	for action: StringName in BUTTONS:
		_ensure(action)
		var button := InputEventMouseButton.new()
		button.button_index = BUTTONS[action]
		InputMap.action_add_event(action, button)
	for action: StringName in JOY_BUTTONS:
		_ensure(action)
		for pad_button: JoyButton in JOY_BUTTONS[action]:
			var pad := InputEventJoypadButton.new()
			pad.button_index = pad_button
			InputMap.action_add_event(action, pad)
	for action: StringName in JOY_AXES:
		_ensure(action)
		var motion := InputEventJoypadMotion.new()
		motion.axis = JOY_AXES[action][0]
		motion.axis_value = JOY_AXES[action][1]
		InputMap.action_add_event(action, motion)
	for action: StringName in LOOK_ACTIONS:
		InputMap.action_set_deadzone(action, 0.01)  # the look deadzone is the setting's


## Whether `action` can be done from a gamepad: a button or stick of its own, or a pad wheel slice.
static func on_pad(action: StringName) -> bool:
	if PAD_WHEEL.any(func(slice: Array) -> bool: return slice[0] == action):
		return true
	if not InputMap.has_action(action):
		return false
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton or e is InputEventJoypadMotion)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
