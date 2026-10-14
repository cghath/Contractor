extends Node
## Network load probe (not a suite): a host and one client over real ENet, a squad-vs-garrison
## firefight for FIGHT_S seconds, and how many bytes a second the host sends that client.
##   <voxel godot exe> --headless --path . res://tests/net_load.tscn
## The host starts its own client process (like people_test), runs the fight, prints
## NETLOAD lines and writes them to user://net_load<tag>.txt. Exits 0 when the client joined
## and the fight was measured.
##
## Two numbers, side by side:
## - ENet's own count of what the host's socket sent (ENetConnection HOST_TOTAL_SENT_DATA),
##   headers, acks and all: the real bytes on the wire to the one client.
## - A model of the replication payload, per synchronised property: every frame each
##   MultiplayerSynchronizer property is hashed as the engine does; an on-change property that
##   changed adds its encoded size (var_to_bytes), an always property adds it every frame.
##   This splits the total by what it carries (the inventory's share, vitals, positions).
## The host runs at 60 frames a second (Engine.max_fps), as a vsynced game would; synchronisers
## send every frame (interval 0).

const FIGHT_S := 60.0
## Alive at once on each side: one that goes down is replaced (hostiles at the far end,
## friendly reinforcements behind the squad's line), so the fight goes on for the whole minute.
const HOSTILES_UP := 20
const FRIENDLIES_UP := 8
const HOSTILE_BAND := {"x": [-18.0, 18.0], "z": [-34.0, -22.0]}
const SQUAD_BAND := {"x": [-12.0, 12.0], "z": [10.0, 16.0]}

var level: CompoundLevel
var _client_pid := -1
var _client_ready := false
var _spawned := 0
var _reinforced := 0
var _rng := RandomNumberGenerator.new()
## Property key ("Inventory:net_state") -> [bytes, changes].
var _bytes := {}
## Synchroniser instance id -> {prop key -> last hash}.
var _last := {}
## Soldier instance id -> {slot -> [weapon id, rounds]}.
var _rounds := {}
var _shots := 0
var _frames_n := 0


func _ready() -> void:
	_rng.seed = 4242
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_netload" + tag
	if "--netload-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	Engine.max_fps = 60
	get_tree().create_timer(FIGHT_S + 200.0).timeout.connect(func() -> void:
		print("NETLOAD FAILED (timed out)")
		_end(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	var me := level.players.get_node(^"1") as Soldier
	me.set_physics_process(false)
	me.global_position = Vector3(0, 0.1, 40)  # out of the way, behind the squad
	var log_path := OS.get_user_data_dir().path_join("net_load_client%s.log" % tag)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/net_load.tscn",
		"--", "--netload-join"]
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	print("NETLOAD client process %d, log %s" % [_client_pid, log_path])
	var deadline := Time.get_ticks_msec() + 150000
	while not _client_ready and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _client_ready:
		print("NETLOAD FAILED (the client never joined)")
		_end(1)
		return
	# Stage the fight: the squad in a line facing the garrison's end, the hostiles topped up to
	# HOSTILES_UP across the far end, both sides told where the other is.
	var i := 0
	for s: Soldier in _side(&"friendly"):
		s.global_position = Vector3(lerpf(SQUAD_BAND.x[0], SQUAD_BAND.x[1], float(i) / 7.0), 0.1, _rng.randf_range(SQUAD_BAND.z[0], SQUAD_BAND.z[1]))
		i += 1
	_top_up_hostiles()
	await get_tree().create_timer(1.0).timeout
	_tell_both_sides()
	await get_tree().create_timer(2.0).timeout
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)  # from here on
	enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	_bytes.clear()
	_last.clear()
	_rounds.clear()
	_scan(false)  # baseline hashes and rounds
	var start := Time.get_ticks_msec()
	var next_top_up := 0.0
	while Time.get_ticks_msec() - start < int(FIGHT_S * 1000):
		await get_tree().process_frame
		_frames_n += 1
		_scan(true)
		var t := (Time.get_ticks_msec() - start) / 1000.0
		if t >= next_top_up:
			next_top_up = t + 2.0
			_top_up_hostiles()
			_tell_both_sides()
		if _frames_n % 600 == 0:
			print("NETLOAD   ... %.0f s: %d shots so far, %d friendly and %d hostile up" % [t, _shots, _side(&"friendly").size(), _side(&"hostile").size()])
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	var sent := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var packets := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var received := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var lines := PackedStringArray()
	lines.append("NETLOAD commit %s, %.1f s, %d frames (%.0f fps), %d shots (%.1f/s), %d hostiles and %d friendly reinforcements spawned, %d friendly and %d hostile up at the end" % [
		OS.get_environment("NETLOAD_SHA"), secs, _frames_n, _frames_n / secs, _shots, _shots / secs, _spawned, _reinforced,
		_side(&"friendly").size(), _side(&"hostile").size()])
	lines.append("NETLOAD enet host->client: %d bytes/s (%.1f KB/s), %d packets/s; client->host %d bytes/s" % [
		int(sent / secs), sent / secs / 1024.0, int(packets / secs), int(received / secs)])
	var total := 0
	for key: String in _bytes:
		total += int(_bytes[key][0])
	var keys := _bytes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_bytes[a][0]) > int(_bytes[b][0]))
	lines.append("NETLOAD replication payload (model): %d bytes/s in all" % int(total / secs))
	var inv := 0
	for key: String in keys:
		if key.begins_with("Inventory:"):
			inv += int(_bytes[key][0])
	lines.append("NETLOAD inventory share: %d bytes/s, %.1f%% of the payload, %.1f%% of what ENet sent; %.0f bytes per shot" % [
		int(inv / secs), 100.0 * inv / maxf(total, 1.0), 100.0 * inv / maxf(sent, 1.0), inv / maxf(_shots, 1.0)])
	var vit := 0
	for key: String in keys:
		if key.begins_with("Vitals:"):
			vit += int(_bytes[key][0])
	lines.append("NETLOAD vitals share: %d bytes/s, %.1f%% of the payload" % [int(vit / secs), 100.0 * vit / maxf(total, 1.0)])
	for key: String in keys:
		lines.append("NETLOAD   %-28s %8d bytes/s  %6d changes  (%.0f bytes each)" % [key, int(_bytes[key][0] / secs), int(_bytes[key][1]),
			float(_bytes[key][0]) / maxf(float(_bytes[key][1]), 1.0)])
	for line in lines:
		print(line)
	var out := FileAccess.open("user://net_load%s.txt" % OS.get_environment("CONTRACTOR_TEST_TAG"), FileAccess.WRITE)
	if out:
		out.store_string("\n".join(lines) + "\n")
		out.close()
	print("NETLOAD DONE")
	_end(0)


func _end(code: int) -> void:
	if multiplayer.multiplayer_peer and multiplayer.is_server() and _client_ready:
		_client_quit.rpc()
		await get_tree().create_timer(1.0).timeout
	if _client_pid > 0 and OS.is_process_running(_client_pid):
		OS.kill(_client_pid)
	GameState.delete_save()
	get_tree().quit(code)


func _side(faction: StringName) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in level.ai.get_children():
		if n is Soldier and (n as Soldier).faction == faction and (n as Soldier).vitals.is_up() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _top_up_hostiles() -> void:
	var up := _side(&"hostile").size()
	while up < HOSTILES_UP:
		_spawned += 1
		var pos := Vector3(_rng.randf_range(HOSTILE_BAND.x[0], HOSTILE_BAND.x[1]), 0.1, _rng.randf_range(HOSTILE_BAND.z[0], HOSTILE_BAND.z[1]))
		level.spawn_soldier({"name": "LoadHostile%d" % _spawned, "faction": "hostile", "variant": "urban", "pos": pos,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": false, "mode": "aware"})
		up += 1
	up = _side(&"friendly").size()
	while up < FRIENDLIES_UP:
		_reinforced += 1
		var pos := Vector3(_rng.randf_range(SQUAD_BAND.x[0], SQUAD_BAND.x[1]), 0.1, _rng.randf_range(SQUAD_BAND.z[0], SQUAD_BAND.z[1]) + 4.0)
		level.spawn_soldier({"name": "LoadFriend%d" % _reinforced, "faction": "friendly", "variant": "multicam", "pos": pos,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.6, "discipline": 0.6, "guard": false})
		up += 1


func _tell_both_sides() -> void:
	var friends := level.squad_for(&"friendly")
	var foes := level.squad_for(&"hostile")
	for h: Soldier in _side(&"hostile"):
		if friends:
			friends.note_enemy(h, h.global_position)
	for f: Soldier in _side(&"friendly"):
		if foes:
			foes.note_enemy(f, f.global_position)


## Every synchroniser in the tree: hash each property, count what would be sent; and count
## the rounds each soldier's weapons lost since the last frame (shots).
func _scan(count: bool) -> void:
	for sync: Node in get_tree().root.find_children("*", "MultiplayerSynchronizer", true, false):
		var ms := sync as MultiplayerSynchronizer
		var cfg := ms.replication_config
		var root := ms.get_node_or_null(ms.root_path)
		if cfg == null or root == null:
			continue
		var seen: Dictionary = _last.get(ms.get_instance_id(), {})
		for p: NodePath in cfg.get_properties():
			var mode := cfg.property_get_replication_mode(p)
			var node := root.get_node_or_null(NodePath(p.get_concatenated_names())) if p.get_name_count() > 0 else root
			if node == null:
				continue
			var key := "%s:%s" % [p.get_concatenated_names(), p.get_concatenated_subnames()]
			var v: Variant = node.get(StringName(p.get_concatenated_subnames()))
			var h := hash(v)
			var changed := not seen.has(key) or int(seen[key]) != h
			seen[key] = h
			if count and (mode == SceneReplicationConfig.REPLICATION_MODE_ALWAYS or (mode == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE and changed)):
				var entry: Array = _bytes.get(key, [0, 0])
				entry[0] += var_to_bytes(v).size()
				entry[1] += 1
				_bytes[key] = entry
		_last[ms.get_instance_id()] = seen
	for n in level.ai.get_children() + level.players.get_children():
		if not n is Soldier:
			continue
		var s := n as Soldier
		var had: Dictionary = _rounds.get(s.get_instance_id(), {})
		var now := {}
		for slot: StringName in Inventory.WEAPON_SLOTS:
			now[slot] = [s.inventory.slots.get(slot, &""), s.inventory.rounds_in(slot)]
			if count and had.has(slot) and had[slot][0] == now[slot][0] and int(had[slot][1]) > int(now[slot][1]):
				_shots += int(had[slot][1]) - int(now[slot][1])
		_rounds[s.get_instance_id()] = now


@rpc("authority", "call_remote", "reliable")
func _client_quit() -> void:
	print("NETLOAD client: the host is done")
	Net.leave()
	get_tree().quit(0)


@rpc("any_peer", "call_remote", "reliable")
func _client_joined() -> void:
	_client_ready = true


func _run_client() -> void:
	get_tree().create_timer(FIGHT_S + 180.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 120000
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join("127.0.0.1")
		await get_tree().create_timer(2.0).timeout
	if not (joined[0] or 1 in multiplayer.get_peers()):
		print("NETLOAD client: could not join")
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.0).timeout  # let the spawns arrive
	_client_joined.rpc_id(1)
