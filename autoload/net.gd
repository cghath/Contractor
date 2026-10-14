extends Node
## Co-op session over ENet. Listen-server model: one player hosts and is authoritative,
## up to three others join.

signal hosted
signal joined
signal join_failed
signal peer_joined(id: int)
signal peer_left(id: int)
signal session_ended
## The host turned this player away: another build (the reason, for the menu).
signal refused(reason: String)
## The join's build check could not be made (the other side is an older build): a warning.
signal version_warning(text: String)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 3
## While connecting, give up on an unanswered host after about this long (ENet's default is
## 5-30 s), so the menu can retry quickly. Normal timeouts are restored once connected.
const CONNECT_TIMEOUT_MS := 2500
const ENET_TIMEOUT := [32, 5000, 30000]  # ENet defaults: limit, min ms, max ms
## The build check on join (BuildInfo): a client says its commit right after connecting; the
## host welcomes it, or refuses it when both commits are known and differ (the game code would
## not match: RPCs and replication would break in odd ways). No answer within this long means
## the other side has no check (an older build): a warning only.
const HELLO_WAIT_S := 6.0

var _welcomed := false
var _said_hello := {}  # host: peer id -> true once it sent its build


func _ready() -> void:
	print("[build] %s" % BuildInfo.label())
	hosted.connect(func() -> void: print("[net] hosting on port %d" % Net.port()))
	joined.connect(func() -> void: print("[net] joined as peer %d" % multiplayer.get_unique_id()))
	peer_joined.connect(func(id: int) -> void: print("[net] peer %d connected" % id))
	peer_left.connect(func(id: int) -> void: print("[net] peer %d left" % id))
	join_failed.connect(func() -> void: print("[net] could not connect"))
	multiplayer.peer_connected.connect(func(id: int) -> void:
		peer_joined.emit(id)
		if multiplayer.is_server():
			_expect_hello(id))
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
	_welcomed = false
	_hello.rpc_id(1, BuildInfo.commit(), BuildInfo.label(), OS.get_environment("CONTRACTOR_SESSION_TOKEN"))
	get_tree().create_timer(HELLO_WAIT_S).timeout.connect(func() -> void:
		if not _welcomed and multiplayer.multiplayer_peer is ENetMultiplayerPeer and not multiplayer.is_server():
			_warn("The host did not answer the build check: it may be an older build than yours (%s). If things act oddly, play the same build." % BuildInfo.label()))


func _warn(text: String) -> void:
	print("[net] WARNING: " + text)
	push_warning(text)
	version_warning.emit(text)


## Host: a peer that never says its build within HELLO_WAIT_S is an older build (a warning).
func _expect_hello(id: int) -> void:
	_said_hello.erase(id)
	get_tree().create_timer(HELLO_WAIT_S).timeout.connect(func() -> void:
		if not _said_hello.has(id) and id in multiplayer.get_peers():
			if OS.get_environment("CONTRACTOR_SESSION_TOKEN") != "":
				print("[net] dropped peer %d: no hello in a private test session" % id)
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
				return
			_warn("Player %d did not say which build they run (an older build?); this host is %s" % [id, BuildInfo.label()]))


## Client -> host, right after connecting: this player's build.
@rpc("any_peer", "reliable")
func _hello(commit: String, label: String, token := "") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_said_hello[id] = true
	var mine := BuildInfo.commit()
	# A private session (tools: CONTRACTOR_SESSION_TOKEN, e.g. a co-op soak's bots) takes only
	# joiners with its token: a test from another run that hit its port by chance is turned away.
	var my_token := OS.get_environment("CONTRACTOR_SESSION_TOKEN")
	var why := ""
	if my_token != "" and token != my_token:
		why = "This is a private test session."
	elif commit != "" and mine != "" and commit != mine:
		why = "This session runs %s; you are on %s. Play the same build to join." % [BuildInfo.label(), label]
	if why != "":
		print("[net] refused peer %d: on %s, this host %s" % [id, label, BuildInfo.label()])
		_refuse.rpc_id(id, why)
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet and id in multiplayer.get_peers():
				enet.disconnect_peer(id))
		return
	print("[net] peer %d runs %s" % [id, label])
	_welcome.rpc_id(id, BuildInfo.label())


## Host -> client: same build (or one side can't tell), welcome.
@rpc("authority", "reliable")
func _welcome(host_label: String) -> void:
	_welcomed = true
	print("[net] host runs %s" % host_label)


## Host -> client: another build; the host drops the connection a moment later.
@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	_welcomed = true
	print("[net] refused: " + reason)
	push_warning(reason)
	refused.emit(reason)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit()
