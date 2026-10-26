class_name LevelSwitch
extends Node
## Which level a session plays, and the one mechanism that changes it. Lives under Main
## (main.gd adds it).
##
## A level is named by its level_info() (CompoundLevel and subclasses): {"level": "compound"},
## {"level": "base"} (the campaign's hub, BaseLevel) or {"level": "zone", "def": ...} (ZoneLevel,
## generated from the definition). load_level() makes a parent's level the one an info names;
## everything that swaps levels goes through it: the main menu (main.host_zone, BaseHub's
## prepare_session/cancel_session), a joining client (below) and BaseHub's switches for the
## whole session (deploying from the base and coming back).
##
## Joining uses SceneMultiplayer's authentication step, the only handler of it: when a client
## connects, the host sends its level's level_info() and whether a campaign is running (after a
## level switch in progress, if any: BaseHub.switch_pending); the client swaps its level for
## that one (generating a zone from its definition) and follows the campaign mode
## (BaseHub.follow_host), and only then completes the connection, so the spawners and RPCs
## that follow find the same nodes. Plain sessions, test zones, the campaign's base and a
## deployment all join the same way, at the start or late.

const LEVEL_SCENES := {
	"compound": "res://scenes/levels/compound.tscn",
	"zone": "res://scenes/levels/zone.tscn",
	"base": "res://scenes/levels/base_fob.tscn",
	"base_zone": "res://scenes/levels/base_zone.tscn",  # the base as a zone (BaseZoneLevel, LZ-1)
	"lhd": "res://scenes/levels/lhd.tscn",  # the company's LHD, home until a zone is the FOB (LhdLevel, docs/lhd_home.md)
	"range": "res://scenes/levels/vehicle_range.tscn",  # wave 5: the vehicle range (VehicleRange)
}
## Long enough for a client to generate a zone (about a second) while connecting.
const AUTH_TIMEOUT_S := 30.0
## An 8 km operation zone (BigZoneStreaming.streams) holds a joining client's frames up for 10-60 s
## while it makes the zone: its authentication may take LOAD_TIMEOUT's max, and both ends give
## each other LOAD_TIMEOUT (ENet limit, min ms, max ms) until it's in and LOAD_SETTLE_S more, then
## Net.ENET_TIMEOUT again (D3, cg_brief 3.2). Proposed.
const LOAD_TIMEOUT := [32, 120000, 180000]
const LOAD_SETTLE_S := 15.0


func _ready() -> void:
	var mp := multiplayer as SceneMultiplayer
	if mp == null:
		return
	mp.auth_callback = _on_auth_data
	mp.auth_timeout = AUTH_TIMEOUT_S
	mp.peer_authenticating.connect(_on_peer_authenticating)


## The level_info() of a level scene (BaseHub's deployments name theirs by scene path); a zone
## scene without a definition is the "test" zone.
static func info_for_scene(scene_path: String) -> Dictionary:
	for kind: String in LEVEL_SCENES:
		if LEVEL_SCENES[kind] == scene_path:
			return {"level": kind} if kind != "zone" else {"level": "zone", "def": ZoneDef.normalize(ZoneDef.get_def("test"))}
	return {"level": "compound"}


## The scene that plays `info`'s level.
static func scene_for(info: Dictionary) -> String:
	return LEVEL_SCENES.get(String(info.get("level", "compound")), LEVEL_SCENES.compound)


## The host tells each connecting client which level to load and whether it's a campaign, then
## lets it in once the client says it has. A level switch under way finishes first.
func _on_peer_authenticating(id: int) -> void:
	if not multiplayer.is_server():
		return  # a client waits for the host's level (_on_auth_data)
	if BaseHub.switch_pending():
		await BaseHub.level_switched
	var mp := multiplayer as SceneMultiplayer
	if not id in mp.get_authenticating_peers():
		return  # gone meanwhile
	var level := CompoundLevel.current(self)
	var hello := {"info": level.level_info() if level else {"level": "compound"}, "campaign": BaseHub.campaign_running}
	mp.auth_timeout = float(LOAD_TIMEOUT[2]) / 1000.0 if _big(hello.info) else AUTH_TIMEOUT_S
	if _big(hello.info):
		_load_timeout(id)
	if mp.send_auth(id, var_to_bytes(hello)) == OK:
		mp.complete_auth(id)


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return  # clients send nothing but their completion
	# The host answered. Generating a zone holds up this frame: past the short connecting
	# timeout (Net.join) the host would drop us, so the normal timeouts apply from here.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(MultiplayerPeer.TARGET_PEER_SERVER):
		enet.get_peer(MultiplayerPeer.TARGET_PEER_SERVER).set_timeout(Net.ENET_TIMEOUT[0], Net.ENET_TIMEOUT[1], Net.ENET_TIMEOUT[2])
	var hello: Variant = bytes_to_var(data)
	if hello is Dictionary and hello.get("info") is Dictionary:
		if _big(hello.info):
			_load_timeout(MultiplayerPeer.TARGET_PEER_SERVER)
		BaseHub.follow_host(bool(hello.get("campaign", false)))
		load_level(get_parent(), hello.info)
	(multiplayer as SceneMultiplayer).complete_auth(id)


## Whether level `info` is one a client takes long to make (an 8 km operation zone).
static func _big(info: Dictionary) -> bool:
	return String(info.get("level", "")) == "zone" and BigZoneStreaming.streams(float((info.get("def", {}) as Dictionary).get("size_m", 0.0)))


## Peer `id`'s ENet timeouts at LOAD_TIMEOUT while the zone loads; back at Net.ENET_TIMEOUT once
## the other end is in (or the wait is over) and LOAD_SETTLE_S more.
func _load_timeout(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_peer(id) == null:
		return
	enet.get_peer(id).set_timeout(LOAD_TIMEOUT[0], LOAD_TIMEOUT[1], LOAD_TIMEOUT[2])
	var until := Time.get_ticks_msec() + int(LOAD_TIMEOUT[2])
	while is_inside_tree() and Time.get_ticks_msec() < until and multiplayer.multiplayer_peer == enet and not id in multiplayer.get_peers():
		await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		await get_tree().create_timer(LOAD_SETTLE_S).timeout
	if multiplayer.multiplayer_peer == enet and enet.get_peer(id):
		enet.get_peer(id).set_timeout(Net.ENET_TIMEOUT[0], Net.ENET_TIMEOUT[1], Net.ENET_TIMEOUT[2])


## Makes `parent`'s level the one `info` names (level_info()), replacing the one there unless
## it is already that level (or always, with `fresh`). Returns the level.
##
## The old level stays in the tree to the end of the frame (a voxel world wants its world
## while it shuts down), but it stops being the level at once: it leaves the "level" group
## (CompoundLevel.current), gives up its name (the new one takes it, for RPC and replication
## paths), stops processing, and it and everything in it let go of Net's signals (hosting
## right after a swap would start it too). On a host with clients, its replicated nodes go
## at once (despawn_replicated).
static func load_level(parent: Node, info: Dictionary, fresh := false) -> CompoundLevel:
	var current: CompoundLevel = null
	for child in parent.get_children():
		if child is CompoundLevel and child.is_in_group(&"level") and not child.is_queued_for_deletion():
			current = child
	if current and not fresh and current.level_info().hash() == info.hash():
		return current
	var kind := String(info.get("level", "compound"))
	var level := (load(scene_for(info)) as PackedScene).instantiate() as CompoundLevel
	if level is ZoneLevel:
		(level as ZoneLevel).configure(info.get("def", {}))  # (BaseZoneLevel too)
	var index := 0
	if current:
		index = current.get_index()
		_retire(current)
	parent.add_child(level)
	parent.move_child(level, index)
	print("[level] now playing %s" % kind)
	return level


static func _retire(old: CompoundLevel) -> void:
	for sig: Signal in [Net.hosted, Net.joined, Net.peer_joined, Net.peer_left, Net.session_ended]:
		for c: Dictionary in sig.get_connections():
			var target := (c.callable as Callable).get_object() as Node
			if target and (target == old or old.is_ancestor_of(target)):
				sig.disconnect(c.callable)
	old.remove_from_group(&"level")
	old.name = "%s_old_%d" % [old.name, old.get_instance_id()]
	old.process_mode = Node.PROCESS_MODE_DISABLED
	if old.multiplayer.is_server() and not old.multiplayer.get_peers().is_empty():
		despawn_replicated(old)
		_despawn_now(old)
	old.queue_free()


## Host, a level being retired with clients connected (B-04): everything its spawners put on
## the clients goes now, so each client gets the despawns while it still has those nodes.
## Left to the end of the frame, the despawns went out after the switch's RPC; a client that
## had already swapped and freed its old level (the RPC and the despawns can arrive in
## different frames on a slow link) logged a burst of "on_despawn_receive ... ERR_UNAUTHORIZED",
## one per node. Taking the nodes out of the tree sends the despawns (MultiplayerSpawner drops
## a node that leaves the tree), in order, ahead of the RPC on the same reliable channel; the
## rest of the old level (nothing replicated left in it) stays to the end of the frame as
## before. Returns how many nodes went.
static func despawn_replicated(old: Node) -> int:
	var count := 0
	for spawner: MultiplayerSpawner in old.find_children("*", "MultiplayerSpawner", true, false):
		var at := spawner.get_node_or_null(spawner.spawn_path)
		if at == null or not at.is_inside_tree():
			continue  # inside something already taken out
		for child in at.get_children():
			if child is MultiplayerSpawner:
				continue
			at.remove_child(child)
			child.queue_free()
			count += 1
	return count


## Then the old level's spawners and the host's own synchronizers leave the tree too (B-04,
## fix/b04-despawn-rejoin; merged with despawn_replicated above, which takes the replicated
## nodes first): a switch run from an RPC (_server_switch_ready) is inside the network poll, which
## sends deltas right after it, and each delta for a node just despawned logged 'Ignoring delta
## for non-authority or invalid synchronizer' (5-6 per client per switch, S0830).
static func _despawn_now(old: CompoundLevel) -> void:
	for spawner: Node in old.find_children("*", "MultiplayerSpawner", true, false):
		spawner.get_parent().remove_child(spawner)
		spawner.queue_free()
	for sync: Node in old.find_children("*", "MultiplayerSynchronizer", true, false):
		if sync.is_multiplayer_authority():
			sync.get_parent().remove_child(sync)
			sync.queue_free()
