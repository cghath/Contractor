extends RefCounted
## Screenshot scripts (tests/*_shots.gd) need a real window, but it mustn't get in the way of
## whoever is at the machine: the window never takes focus (so the game can't lock the cursor
## in it or take the keyboard), and the mouse is let go every frame in case anything captures it.


## Call first thing in the shot script's _ready.
static func stay_out_of_the_way(node: Node) -> void:
	var window := node.get_window()
	window.unfocusable = true
	window.always_on_top = false
	node.get_tree().process_frame.connect(func() -> void:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
