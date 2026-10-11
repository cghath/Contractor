class_name MapNodes
extends RefCounted
## The map and mission-flow nodes a level carries (wave 4, W13): shared map markers
## (MapMarkers), the briefing (Briefing), extraction (Extraction) and the reinforcement timer
## (Reinforcements). A level adds them in its _ready with install(self), on every peer, so
## their RPCs find the same node paths everywhere; any level with map_area() can.
##
## The finders below take any node in the session and find the current level's node.

const LEVEL_GROUP := &"level"


## Adds the nodes to `level` (once). Call from the level's _ready, on every peer.
static func install(level: Node) -> void:
	for node: Node in [MapMarkers.new(), Briefing.new(), Extraction.new(), Reinforcements.new()]:
		if level.get_node_or_null(NodePath(node.name)) == null:
			level.add_child(node)
		else:
			node.free()


## The current level (the node in the "level" group with map_area()), or null.
static func level_of(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var level := from.get_tree().get_first_node_in_group(LEVEL_GROUP)
	return level if level and level.has_method(&"map_area") else null


static func markers(from: Node) -> MapMarkers:
	var level := level_of(from)
	return level.get_node_or_null(^"MapMarkers") as MapMarkers if level else null


static func briefing(from: Node) -> Briefing:
	var level := level_of(from)
	return level.get_node_or_null(^"Briefing") as Briefing if level else null


static func extraction(from: Node) -> Extraction:
	var level := level_of(from)
	return level.get_node_or_null(^"Extraction") as Extraction if level else null


static func reinforcements(from: Node) -> Reinforcements:
	var level := level_of(from)
	return level.get_node_or_null(^"Reinforcements") as Reinforcements if level else null


## The level's map area (Rect2, metres on the ground), or an empty Rect2 with no level.
static func area_of(from: Node) -> Rect2:
	var level := level_of(from)
	return level.call(&"map_area") if level else Rect2()


## The local player's body (the Soldier named after this peer's id), or null.
static func local_player(from: Node) -> Soldier:
	var level := level_of(from)
	if level == null or not from.multiplayer.has_multiplayer_peer():
		return null
	var players := level.get_node_or_null(^"Players")
	return players.get_node_or_null(str(from.multiplayer.get_unique_id())) as Soldier if players else null


## The players' bodies in the session (any peer), by peer id order.
static func players(from: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	var level := level_of(from)
	var node := level.get_node_or_null(^"Players") if level else null
	if node == null:
		return out
	for child in node.get_children():
		if child is Soldier and not child.is_queued_for_deletion():
			out.append(child)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.name.to_int() < b.name.to_int())
	return out


## Living friendly AI squadmates (any peer): in a squad slot, not dead, by slot. (A friendly
## AI without a slot, such as an escorted HVT, is no squadmate.)
static func squad_ai(from: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	var level := level_of(from)
	var node := level.get_node_or_null(^"AI") if level else null
	if node == null:
		return out
	for child in node.get_children():
		var s := child as Soldier
		if s and s.faction == &"friendly" and s.squad_slot >= 0 and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			out.append(s)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool:
		return (a.squad_slot if a.squad_slot >= 0 else 99) < (b.squad_slot if b.squad_slot >= 0 else 99))
	return out


## Shows a message on this peer's HUD (if it has a local player).
static func flash_local(from: Node, text: String) -> void:
	var me := local_player(from)
	if me and me.player_input:
		me.player_input.flash(text)
