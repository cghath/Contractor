class_name LevelSwitch
extends Node
## Which level a session plays, and the handshake that gets a joining client onto the same
## one before anything replicates. Lives under Main (main.gd adds it).
##
## Uses SceneMultiplayer's authentication step: when a client connects, the host sends its
## level's level_info() ({"level": "compound"} or {"level": "zone", "def": ...}); the client
## swaps its level for that one (generating the zone from the definition) and only then
## completes the connection, so the spawners and RPCs that follow find the same nodes.

const LEVEL_SCENES := {
	"compound": "res://scenes/levels/compound.tscn",
	"zone": "res://scenes/levels/zone.tscn",
}
## Long enough for a client to generate a zone (about a second) while connecting.
const AUTH_TIMEOUT_S := 30.0


func _ready() -> void:
	var mp := multiplayer as SceneMultiplayer
	if mp == null:
		return
	mp.auth_callback = _on_auth_data
	mp.auth_timeout = AUTH_TIMEOUT_S
	mp.peer_authenticating.connect(_on_peer_authenticating)


## The host tells each connecting client which level to load, then lets it in once the client
## says it has.
func _on_peer_authenticating(id: int) -> void:
	if not multiplayer.is_server():
		return  # a client waits for the host's level (_on_auth_data)
	var level := CompoundLevel.current(self)
	var info := level.level_info() if level else {"level": "compound"}
	var mp := multiplayer as SceneMultiplayer
	mp.send_auth(id, var_to_bytes(info))
	mp.complete_auth(id)


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return  # clients send nothing
	var info: Variant = bytes_to_var(data)
	# Generating a zone holds up this frame: past the short connecting timeout (Net.join) the
	# host would drop us, so the normal timeouts apply from here.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(MultiplayerPeer.TARGET_PEER_SERVER):
		enet.get_peer(MultiplayerPeer.TARGET_PEER_SERVER).set_timeout(Net.ENET_TIMEOUT[0], Net.ENET_TIMEOUT[1], Net.ENET_TIMEOUT[2])
	if typeof(info) == TYPE_DICTIONARY:
		load_level(get_parent(), info)
	(multiplayer as SceneMultiplayer).complete_auth(id)


## Makes `main`'s level the one `info` names (level_info()), replacing the one there unless it
## is already that level. Returns the level.
static func load_level(main: Node, info: Dictionary) -> CompoundLevel:
	var current: CompoundLevel = null
	for child in main.get_children():
		if child is CompoundLevel and not child.is_queued_for_deletion():
			current = child
	if current and current.level_info().hash() == info.hash():
		return current
	var kind := String(info.get("level", "compound"))
	var scene: PackedScene = load(LEVEL_SCENES.get(kind, LEVEL_SCENES.compound))
	var level := scene.instantiate() as CompoundLevel
	if level is ZoneLevel:
		(level as ZoneLevel).configure(info.get("def", {}))
	var index := 0
	if current:
		index = current.get_index()
		main.remove_child(current)
		current.free()  # now: queued, it would still answer Net.hosted and the rest this frame
	main.add_child(level)
	main.move_child(level, index)
	print("[level] now playing %s" % kind)
	return level
