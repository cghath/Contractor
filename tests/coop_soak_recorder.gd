extends Node
## Co-op soak (tests/coop_soak.gd): what one peer writes while the soak runs, into its folder.
##   snapshots.jsonl  every SNAP_S of wall-clock time (all peers on the same 5 s marks, so the
##                    harness can line them up): every soldier's position, condition, ammo and
##                    an inventory hash, the world items, objectives, zone, extraction, vehicle
##                    seats. tools/coop_soak_report.py compares each client's against the host's.
##   metrics.jsonl    on the same marks: frame time (average, worst), fps, memory, node count,
##                    ENet totals since the last mark (bytes and packets in and out) and each
##                    connection's round trip and packet loss as ENet sees it.
##   replay.jsonl     REPLAY_HZ frames: every soldier's transform, view pitch, condition flags and
##                    blood; events (shots on the host, hits, going down, coming round, dying,
##                    objective changes, phase changes); every second the world items and
##                    vehicles. tests/coop_replay.gd plays it back (and renders it to a video).
## Reads only: nothing here changes the game.

const SNAP_S := 5
const REPLAY_HZ := 15.0
## Replay flag bits (tests/coop_replay.gd reads the same).
const F_UP := 1
const F_DOWNED := 2
const F_DEAD := 4
const F_AIM := 8
const F_RELOAD := 16
const F_PLAYER := 32
const F_HOSTILE := 64
const F_VEHICLE := 128
const F_LIFTED := 256

var out_dir := ""
## The phase the soak is in (the bot sets it), written with each snapshot and replay change.
var phase := ""
var bot := 0

var _snap_file: FileAccess
var _metric_file: FileAccess
var _replay_file: FileAccess
var _last_key := -1
var _replay_left := 0.0
var _items_left := 0.0
var _frames := 0
var _frame_sum := 0.0
var _frame_worst := 0.0
var _prev := {}  # soldier key -> [flags, blood, last_shot_at]
var _prev_objectives := {}
var _prev_phase := ""
var _prev_level := ""
var _events: Array = []
## Inventory replication (the baseline for net/ammo-delta): each soldier's inventory net_state is
## replaced whole on every change (a shot, a reload, a pickup) and ServerSync sends it whole. Every
## frame this peer counts the replacements it sees and their encoded size (var_to_bytes, about
## what goes over the wire per peer, before ENet's headers).
var _inv_refs := {}  # soldier key -> [the replicated gear Dictionary, net_ammo] last seen
var _inv_changes := 0
var _inv_bytes := 0
## The same for Vitals.net_state (the next big one after the inventory: a fresh Dictionary on
## each change, up to about 2 Hz per soldier, more while hurt).
var _vit_refs := {}
var _vit_changes := 0
var _vit_bytes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	_snap_file = FileAccess.open(out_dir.path_join("snapshots.jsonl"), FileAccess.WRITE)
	_metric_file = FileAccess.open(out_dir.path_join("metrics.jsonl"), FileAccess.WRITE)
	_replay_file = FileAccess.open(out_dir.path_join("replay.jsonl"), FileAccess.WRITE)
	_replay_file.store_line(JSON.stringify({"header": true, "bot": bot, "hz": REPLAY_HZ, "flags": {"up": F_UP, "downed": F_DOWNED,
		"dead": F_DEAD, "aim": F_AIM, "reload": F_RELOAD, "player": F_PLAYER, "hostile": F_HOSTILE, "vehicle": F_VEHICLE, "lifted": F_LIFTED}}))


func close() -> void:
	for f: FileAccess in [_snap_file, _metric_file, _replay_file]:
		if f:
			f.flush()
	_snap_file = null
	_metric_file = null
	_replay_file = null


static func now() -> float:
	return Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	_frames += 1
	_frame_sum += delta
	_frame_worst = maxf(_frame_worst, delta)
	_count_inventory()
	var t := now()
	var key := int(floor(t / SNAP_S))
	if key != _last_key:
		if _last_key >= 0:
			_write_snapshot(key, t)
			_write_metrics(key, t)
		_last_key = key
	_replay_left -= delta
	if _replay_left <= 0.0:
		_replay_left += 1.0 / REPLAY_HZ
		if _replay_left < 0.0:
			_replay_left = 0.0
		_write_replay_frame(t, delta)


# --- What the level holds ---------------------------------------------------------------------

func _level() -> CompoundLevel:
	return CompoundLevel.current(self)


func _level_kind() -> String:
	var lvl := _level()
	return String(lvl.level_info().get("level", "?")) if lvl else "none"


## Soldiers in the level by a key every peer shares: "Players/2", "AI/Hostile3", "Bodies/x".
func _soldiers() -> Dictionary:
	var out := {}
	var lvl := _level()
	if lvl == null:
		return out
	for group_name: String in ["Players", "AI", "Bodies"]:
		var holder := lvl.get_node_or_null(group_name)
		if holder == null:
			continue
		for child in holder.get_children():
			if child is Soldier and not child.is_queued_for_deletion() and child.is_node_ready():
				out["%s/%s" % [group_name, child.name]] = child
	return out


static func _r(v: float, places := 2) -> float:
	var m := pow(10.0, places)
	return roundf(v * m) / m


static func _v3(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func inv_hash(s: Soldier) -> String:
	return JSON.stringify(s.inventory.net_state, "", true).md5_text().left(10)


func _flags(s: Soldier) -> int:
	var f := 0
	if s.vitals.is_up():
		f |= F_UP
	if s.vitals.downed:
		f |= F_DOWNED
	if s.vitals.is_dead():
		f |= F_DEAD
	if s.is_aiming:
		f |= F_AIM
	if s.is_reloading:
		f |= F_RELOAD
	if not s.is_ai():
		f |= F_PLAYER
	if s.faction == &"hostile":
		f |= F_HOSTILE
	if is_instance_valid(s.vehicle):
		f |= F_VEHICLE
	if StringName(s.model.carry_net.get("mode", &"")) in [CharacterModel.CARRIED, CharacterModel.DRAGGED]:
		f |= F_LIFTED
	return f


func _vehicles() -> Array:
	var out: Array = []
	for v in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if not v is Vehicle or v.is_queued_for_deletion():
			continue
		var seats: Array = []
		for o in (v as Vehicle).occupants():
			seats.append(String(o.name) if o is Node else "")
		out.append({"id": String(v.name), "kind": String((v as Vehicle).vehicle_id), "p": _v3(v.global_position),
			"yaw": _r(v.global_rotation.y, 3), "seats": seats, "wrecked": (v as Vehicle).wrecked})
	return out


func _items() -> Array:
	var out: Array = []
	for item in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if item is WorldItem and not item.is_queued_for_deletion() and item.is_inside_tree():
			out.append([String(item.item_id), int(item.count), _r(item.global_position.x, 1), _r(item.global_position.z, 1)])
	out.sort()
	return out


func _objectives() -> Array:
	var out: Array = []
	for o: Dictionary in Contracts.objectives.list:
		out.append([String(o.get("oid", "")), String(o.get("state", ""))])
	return out


func _count_inventory() -> void:
	var seen := {}
	var seen_vit := {}
	var all := _soldiers()
	for k: String in all:
		var s: Soldier = all[k]
		# With net/ammo-delta (integrate/oct14 on) what goes over the wire is net_gear (whole
		# snapshot, on real gear changes) and net_ammo (rounds per slot); before it, net_state.
		var wire: Variant = s.inventory.get(&"net_gear") if &"net_gear" in s.inventory else s.inventory.net_state
		var ammo: Variant = s.inventory.get(&"net_ammo") if &"net_ammo" in s.inventory else null
		var state: Array = [wire, ammo]
		seen[k] = state
		if _inv_refs.has(k):
			var before: Array = _inv_refs[k]
			if not is_same(before[0], wire):
				_inv_changes += 1
				_inv_bytes += var_to_bytes(wire).size()
			if ammo != null and before[1] != ammo:
				_inv_changes += 1
				_inv_bytes += var_to_bytes(ammo).size()
		var vit: Dictionary = s.vitals.net_state
		seen_vit[k] = vit
		if _vit_refs.has(k) and not is_same(_vit_refs[k], vit):
			_vit_changes += 1
			_vit_bytes += var_to_bytes(vit).size()
	_inv_refs = seen
	_vit_refs = seen_vit


# --- Snapshots (every SNAP_S, on wall-clock marks) --------------------------------------------

func _write_snapshot(key: int, t: float) -> void:
	if _snap_file == null:
		return
	var soldiers := {}
	var all := _soldiers()
	for k: String in all:
		var s: Soldier = all[k]
		var row := {"p": _v3(s.global_position), "bp": _v3(s.body_point()), "f": _flags(s), "blood": _r(s.vitals.blood_fraction(), 3),
			"fac": String(s.faction), "role": String(s.role)}
		if not s.is_ai():
			row["rounds"] = s.inventory.rounds_in(&"primary")
			row["mags"] = s.inventory.count_of(&"mag_556")
			row["inv"] = inv_hash(s)
		elif k.begins_with("AI/") and s.faction == &"friendly":
			row["inv"] = inv_hash(s)
		soldiers[k] = row
	var items := _items()
	var extraction := MapNodes.extraction(_level()) if _level() else null
	var deployment := Contracts.deployment()
	var snap := {"k": key, "t": _r(t, 3), "bot": bot, "peer": multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0,
		"online": _online(), "phase": phase, "level": _level_kind(), "zone": String(deployment.get("zone_id", "")),
		"deployed": Contracts.is_deployed(), "held": Contracts.held().size(), "objectives": _objectives(),
		"extraction": {"state": extraction.state if extraction else -1, "points": extraction.points.size() if extraction else 0},
		"soldiers": soldiers, "items_n": items.size(), "items_hash": JSON.stringify(items).md5_text().left(10),
		"items": items if items.size() <= 400 else [], "vehicles": _vehicles(), "debriefs": int(Contracts.last_debrief().get("serial", 0))}
	_snap_file.store_line(JSON.stringify(snap))
	_snap_file.flush()


func _online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
		and (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _write_metrics(key: int, t: float) -> void:
	if _metric_file == null:
		return
	var m := {"k": key, "t": _r(t, 3), "bot": bot, "phase": phase, "level": _level_kind(), "online": _online(),
		"frames": _frames, "frame_avg_ms": _r(_frame_sum / maxf(_frames, 1) * 1000.0), "frame_max_ms": _r(_frame_worst * 1000.0),
		"fps": Engine.get_frames_per_second(), "mem_static_mb": _r(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"soldiers": _soldiers().size(), "inv_changes": _inv_changes, "inv_bytes": _inv_bytes,
		"vit_changes": _vit_changes, "vit_bytes": _vit_bytes}
	_inv_changes = 0
	_inv_bytes = 0
	_vit_changes = 0
	_vit_bytes = 0
	_frames = 0
	_frame_sum = 0.0
	_frame_worst = 0.0
	if _online():
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var host := enet.host
		if host:
			m["sent_bytes"] = host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
			m["recv_bytes"] = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			m["sent_packets"] = host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
			m["recv_packets"] = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
		var peers := {}
		# A client's only ENet connection is the host's (other clients reach it through the host).
		for id in (multiplayer.get_peers() if multiplayer.is_server() else PackedInt32Array([1])):
			var p := enet.get_peer(id)
			if p:
				peers[str(id)] = {"rtt_ms": p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
					"rtt_var_ms": p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
					"loss": _r(p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE), 4)}
		m["peers"] = peers
	_metric_file.store_line(JSON.stringify(m))
	_metric_file.flush()


# --- The replay stream (REPLAY_HZ) ------------------------------------------------------------

## A replay frame: {"t", "L" (level kind), "ph" (phase, when it changed), "s": [[key, x, y, z,
## yaw, pitch, flags, blood, name, role]], "e": [events], every second "i" (items) and "v"
## (vehicles), and "info" (the level's level_info) whenever the level changed.
func _write_replay_frame(t: float, _delta: float) -> void:
	if _replay_file == null:
		return
	var frame := {"t": _r(t, 3)}
	var kind := _level_kind()
	frame["L"] = kind
	var lvl := _level()
	var info_key := JSON.stringify(lvl.level_info()) if lvl else ""
	if info_key != _prev_level:
		_prev_level = info_key
		frame["info"] = lvl.level_info() if lvl else {}
		frame["zone"] = String(Contracts.deployment().get("zone_id", ""))
		_prev.clear()
	if phase != _prev_phase:
		_prev_phase = phase
		frame["ph"] = phase
		_events.append(["phase", phase])
	var rows: Array = []
	var all := _soldiers()
	var server := multiplayer.is_server()
	for k: String in all:
		var s: Soldier = all[k]
		var f := _flags(s)
		var blood := _r(s.vitals.blood_fraction(), 3)
		var pos := s.body_point() if not s.vitals.is_up() else s.global_position
		rows.append([k, _r(pos.x), _r(pos.y), _r(pos.z), _r(s.global_rotation.y, 3), _r(s.head.rotation.x, 3), f, blood,
			s.display_name(), String(s.role)])
		var before: Array = _prev.get(k, [])
		if not before.is_empty():
			if blood < float(before[1]) - 0.004:
				_events.append(["hit", k, _r(float(before[1]) - blood, 3)])
			if (f & F_DOWNED) and not (int(before[0]) & F_DOWNED) and not (f & F_DEAD):
				_events.append(["down", k])
			if (f & F_UP) and not (int(before[0]) & F_UP) and not (int(before[0]) & F_DEAD):
				_events.append(["up", k])
			if (f & F_DEAD) and not (int(before[0]) & F_DEAD):
				_events.append(["dead", k])
		var shot := s.last_shot_at if server else -1000.0
		if server and not before.is_empty() and shot > float(before[2]):
			var dir := -s.head.global_basis.z if s.is_ai() else -s.camera.global_basis.z
			_events.append(["fire", k, _r(dir.x, 3), _r(dir.y, 3), _r(dir.z, 3)])
		_prev[k] = [f, blood, shot]
	frame["s"] = rows
	var objectives := {}
	for o: Array in _objectives():
		objectives[o[0]] = o[1]
		if _prev_objectives.get(o[0], "") != o[1]:
			_events.append(["obj", o[0], o[1]])
	_prev_objectives = objectives
	_items_left -= 1.0 / REPLAY_HZ
	if _items_left <= 0.0:
		_items_left = 1.0
		frame["i"] = _items()
		frame["v"] = _vehicles()
		var extraction := MapNodes.extraction(lvl) if lvl else null
		if extraction:
			var points: Array = []
			for p: Dictionary in extraction.points:
				points.append([_r((p.pos as Vector2).x), _r((p.pos as Vector2).y), float(p.get("radius", 20.0))])
			frame["x"] = {"state": extraction.state, "points": points}
	if not _events.is_empty():
		frame["e"] = _events
		_events = []
	_replay_file.store_line(JSON.stringify(frame))


## An event the bot wants in the replay (["note", text], a disconnect, ...).
func event(e: Array) -> void:
	_events.append(e)
