class_name SoloPause
extends RefCounted
## Solo pause, co-op never (docs/survival.md call 138): a survival world hosted with nobody joined
## stops while the pause menu is open (SceneTree.paused, the menu itself PROCESS_MODE_ALWAYS so it
## still takes Escape and its buttons); with anyone joined (Net's peers) it never does, and a
## player joining while it's paused starts it again. PauseMenu calls on_open and on_close.

## Tests: the peer count to use instead of the real one (-1: the real one).
static var force_peers := -1
static var _paused_by_us := false
static var _hooked := false


## Whether the world `from` is in may pause now: survival running, this peer the host, nobody
## else joined.
static func allowed(from: Node) -> bool:
	if from == null or not from.is_inside_tree() or not Survival.running:
		return false
	var mp := from.multiplayer
	if mp.has_multiplayer_peer() and not mp.is_server():
		return false
	var peers := force_peers if force_peers >= 0 else (mp.get_peers().size() if mp.has_multiplayer_peer() else 0)
	return peers == 0


## The pause menu `menu` opened: pauses when allowed. Returns whether it paused.
static func on_open(menu: Node) -> bool:
	if not allowed(menu):
		return false
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.get_tree().paused = true
	_paused_by_us = true
	if not _hooked:
		_hooked = true
		Net.peer_joined.connect(func(id: int) -> void: SoloPause._on_peer_joined(id))
	return true


## The pause menu closed (or left): the world goes on if we paused it.
static func on_close(menu: Node) -> void:
	if _paused_by_us and menu and menu.is_inside_tree():
		menu.get_tree().paused = false
	_paused_by_us = false


## Someone joined: co-op never pauses.
static func _on_peer_joined(_id: int) -> void:
	if not _paused_by_us:
		return
	_paused_by_us = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.paused = false
