extends Node
## Co-op session over ENet. Listen-server model: one player hosts and is authoritative,
## up to three others join.

signal hosted
signal joined
signal join_failed
signal peer_joined(id: int)
signal peer_left(id: int)
signal session_ended

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 3
## While connecting, give up on an unanswered host after about this long (ENet's default is
## 5-30 s), so the menu can retry quickly. Normal timeouts are restored once connected.
const CONNECT_TIMEOUT_MS := 2500
## Once connected, both ends (limit, min ms, max ms). ENet's defaults (32, 5000, 30000) dropped a
## peer whose main thread was busy for ~5 s: a joining client generating its zone, a host
## switching levels, on a slow PC or CI (map and lhd_home: the client's first session ended and it
## joined again as a new peer). Proposed.
const ENET_TIMEOUT := [32, 20000, 60000]


func _ready() -> void:
	hosted.connect(func() -> void: print("[net] hosting on port %d" % Net.port()))
	joined.connect(func() -> void: print("[net] joined as peer %d" % multiplayer.get_unique_id()))
	peer_joined.connect(func(id: int) -> void: print("[net] peer %d connected" % id))
	peer_left.connect(func(id: int) -> void: print("[net] peer %d left" % id))
	join_failed.connect(func() -> void: print("[net] could not connect"))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## The port to host and join on: DEFAULT_PORT, or CONTRACTOR_PORT from the environment
## (parallel test runs use different ports).
static func port() -> int:
	var env := OS.get_environment("CONTRACTOR_PORT")
	return env.to_int() if env.is_valid_int() else DEFAULT_PORT


func host(on_port := -1) -> Error:
	var port := on_port if on_port >= 0 else Net.port()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	hosted.emit()
	return OK


func join(address: String, on_port := -1) -> Error:
	var port := on_port if on_port >= 0 else Net.port()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_server_peer(peer).set_timeout(ENET_TIMEOUT[0], CONNECT_TIMEOUT_MS / 2, CONNECT_TIMEOUT_MS)
	return OK


func is_hosting() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()


func leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _server_peer(peer: ENetMultiplayerPeer) -> ENetPacketPeer:
	return peer.get_peer(MultiplayerPeer.TARGET_PEER_SERVER)


func _on_connected() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer:
		_server_peer(peer).set_timeout(ENET_TIMEOUT[0], ENET_TIMEOUT[1], ENET_TIMEOUT[2])
	joined.emit()


## Host: a joined client's link gets the connected timeouts too (the client sets its own in
## _on_connected).
func _on_peer_connected(id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer and multiplayer.is_server():
		var link := peer.get_peer(id)
		if link:
			link.set_timeout(ENET_TIMEOUT[0], ENET_TIMEOUT[1], ENET_TIMEOUT[2])
	peer_joined.emit(id)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit()
