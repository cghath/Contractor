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
	&"crouch": [KEY_CTRL, KEY_C],
	&"interact": [KEY_E],
	&"reload": [KEY_R],
	&"use_medical": [KEY_H],
	&"give_up": [KEY_F],
	&"grenade": [KEY_G],  # throw; Shift+G switches type, Alt+G drops
	&"inventory": [KEY_TAB],
	&"weapon_primary": [KEY_1],
	&"weapon_sidearm": [KEY_2],
	&"pause": [KEY_ESCAPE],
	&"quick_save": [KEY_HOME],  # F-keys are the squad command menu
	&"debug_hurt": [KEY_K],  # debug builds only: hurt yourself to test going down and dying
}
const MOUSE := {
	&"fire": MOUSE_BUTTON_LEFT,
	&"aim": MOUSE_BUTTON_RIGHT,
}


func _enter_tree() -> void:
	for action: StringName in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action: StringName in MOUSE:
		_ensure(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE[action]
		InputMap.action_add_event(action, event)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
