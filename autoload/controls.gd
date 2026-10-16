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
	&"weapon_primary": [KEY_1],
	&"weapon_sidearm": [KEY_2],
	&"weapon_launcher": [KEY_3],  # the anti-armour launcher (wave 5, Launchers)
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


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
