class_name Briefing
extends Node
## The Arma-style briefing and planning before a deployment (design doc, "Missions"): on
## the map, every player sees the contract's objectives and the enemy positions known from
## intel, draws plan marks (MapMarkers, "plan" channel), picks the insertion point from the
## zone's candidates and the supports to bring (a list only until wave 5 builds them), then
## readies up; the host starts the deployment once everyone is ready.
##
## The loop wiring calls server_open(contract, zone) on the host and listens for
## deployment_started(plan). With auto_flow on (the default), starting also moves the squad
## to the insertion point, begins extraction (Extraction.server_begin) and starts the
## reinforcement timer (Reinforcements.server_start), so the briefing works on its own; the
## wiring can turn it off and do those itself. All state replicates to every peer and to late
## joiners (one snapshot, _client_state).
##
## contract (Dictionary, JSON-safe; only "title" is needed):
##   "id", "title", "type" (a mission type id), "employer", "summary", "difficulty" (1-5),
##   "objectives": [{"id", "title", "text", "pos": [x, z] (optional), "radius" (m)}],
##   "known_enemies": [{"pos": [x, z], "text"}], "supports": [support ids] (optional),
##   "reinforcements": {Reinforcements tuning} (optional).
## zone (Dictionary): "id", "name", "kind" ("contract" or "hot"), "insertion_points":
##   [{"id", "name", "pos": [x, z], "method" ("foot", "helicopter"...)}], "extraction_points":
##   [{"name", "pos": [x, z], "radius"}] (optional, preset LZs), "supports" (optional).

signal changed
## Host and every peer: the deployment started. `plan`: "contract", "zone", "insertion"
## (the chosen insertion point), "supports" (picked ids), "plan_marks" (MapMarkers),
## "players" (peer ids), "started_msec".
signal deployment_started(plan: Dictionary)

enum Phase { IDLE, BRIEFING, DEPLOYED }

## Player-faction supports (design doc). Transport and AAVs are hot zones only.
const SUPPORTS := {
	"resupply": {"name": "Helicopter resupply", "hot_only": false},
	"extraction": {"name": "Helicopter extraction", "hot_only": false},
	"transport": {"name": "Helicopter transport", "hot_only": true},
	"aav": {"name": "AAV", "hot_only": true},
}
## Proposed: players arriving at an insertion point stand this far apart.
const INSERT_SPACING_M := 2.0
## An insertion point's method when a Black Hawk flies the squad in (wave 5b, hot zones).
const HELI := "heli"

## The compound's stand-in contract and zone, for the debug path (Menu: briefing test).
const DEBUG_CONTRACT := {
	"id": "debug_compound", "title": "Clear the compound", "type": "clear_compound", "employer": "meridian",
	"summary": "Hostiles hold the walled compound. Clear it, recover the HVT case from the main building and extract.",
	"difficulty": 2,
	"objectives": [
		{"id": "clear", "title": "Clear the compound", "text": "Kill or drive off the hostiles inside the walls.", "pos": [0.0, 0.0], "radius": 20.0},
		{"id": "case", "title": "Recover the HVT case", "text": "It's in the main building. Carry it out (two hands).", "pos": [0.0, -10.0], "radius": 4.0},
	],
	"known_enemies": [
		{"pos": [0.0, -8.0], "text": "2x guards, main building"},
		{"pos": [-11.0, -2.0], "text": "Patrol, west yard"},
	],
	"reinforcements": {"first_wave_s": 240.0},
}
const DEBUG_ZONE := {
	"id": "compound_01", "name": "Compound", "kind": "contract",
	"insertion_points": [
		{"id": "south_road", "name": "South road", "pos": [0.0, 30.0], "method": "foot"},
		{"id": "east_field", "name": "East field", "pos": [32.0, 4.0], "method": "foot"},
		{"id": "west_field", "name": "West field", "pos": [-32.0, 4.0], "method": "foot"},
	],
	"extraction_points": [{"name": "LZ South", "pos": [0.0, 34.0], "radius": 20.0}],
}

var phase := Phase.IDLE
var contract: Dictionary = {}
var zone: Dictionary = {}
## Peer id -> true for each player who is ready.
var ready_peers: Dictionary = {}
var insertion_id := ""
## Picked support ids.
var supports: Array = []
## The last started deployment's plan (every peer).
var plan: Dictionary = {}
## Host: on start, also move the squad in, begin extraction and start the reinforcements.
var auto_flow := true
var _peers: Array = [1]  # clients: the host's session_peers()


func _init() -> void:
	name = "Briefing"


func _ready() -> void:
	add_to_group(MapView.OBJECTIVE_GROUP)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


## Host, debug path: opens the compound's stand-in briefing (DEBUG_CONTRACT in DEBUG_ZONE).
static func debug_open(from: Node) -> void:
	var briefing := MapNodes.briefing(from)
	if briefing:
		briefing.server_open(DEBUG_CONTRACT, DEBUG_ZONE)


func is_open() -> bool:
	return phase == Phase.BRIEFING


func is_deployed() -> bool:
	return phase == Phase.DEPLOYED


## The zone's insertion candidates ([{"id", "name", "pos": [x, z], "method"}]).
func insertion_points() -> Array:
	return zone.get("insertion_points", [])


## The chosen insertion point ({} if the zone has none).
func insertion() -> Dictionary:
	for point: Dictionary in insertion_points():
		if String(point.get("id", "")) == insertion_id:
			return point
	return {}


## Support ids this deployment can pick: the contract's list, else the zone's, else all;
## transport and AAVs only in a hot zone.
func available_supports() -> Array:
	var ids: Array = contract.get("supports", zone.get("supports", SUPPORTS.keys()))
	var hot := String(zone.get("kind", "contract")) == "hot"
	return ids.filter(func(id: Variant) -> bool:
		return SUPPORTS.has(String(id)) and (hot or not SUPPORTS[String(id)].hot_only))


## Peer ids of everyone in the session (the host and every client; clients read the host's list).
func session_peers() -> Array:
	if not multiplayer.is_server():
		return _peers.duplicate()
	var peers: Array = [1]
	if multiplayer.has_multiplayer_peer():
		for id in multiplayer.get_peers():
			if id != 1:
				peers.append(id)
	peers.sort()
	return peers


func all_ready() -> bool:
	return session_peers().all(func(id: int) -> bool: return ready_peers.has(id))


## Objective interface for the map (MapView.OBJECTIVE_GROUP): the contract's objectives that
## have a position, while a briefing or deployment is on, unless another part (the economy's
## objective tracker) provides live ones.
func map_objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == Phase.IDLE:
		return out
	if phase == Phase.DEPLOYED and get_tree().get_nodes_in_group(MapView.OBJECTIVE_GROUP).size() > 1:
		return out
	for o: Dictionary in contract.get("objectives", []):
		var p: Variant = o.get("pos")
		if p is Array and (p as Array).size() >= 2:
			out.append({"id": String(o.get("id", "")), "title": String(o.get("title", "Objective")),
				"pos": Vector2(float(p[0]), float(p[1])), "radius": float(o.get("radius", 0.0)), "state": "open"})
	return out


# --- Requests (any peer) --------------------------------------------------------

func request_set_ready(is_ready: bool) -> void:
	_server_ready.rpc_id(1, is_ready)


func request_insertion(id: String) -> void:
	_server_insertion.rpc_id(1, id)


func request_support(id: String, picked: bool) -> void:
	_server_support.rpc_id(1, id, picked)


## Only the host's request counts (the host starts the deployment).
func request_start() -> void:
	_server_start.rpc_id(1)


# --- Host -----------------------------------------------------------------------

## Host only. Opens the briefing on every peer for `p_contract` in `p_zone` (see the class
## doc): known enemies go on the map as intel markers, old plan marks are cleared, nobody is
## ready and the first insertion candidate is picked.
func server_open(p_contract: Dictionary, p_zone: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	contract = p_contract.duplicate(true)
	zone = Briefing.with_heli_insertion(p_zone)
	phase = Phase.BRIEFING
	ready_peers = {}
	supports = []
	plan = {}
	var points := insertion_points()
	insertion_id = String(points[0].get("id", "")) if not points.is_empty() else ""
	var markers := MapNodes.markers(self)
	if markers:
		markers.server_clear("intel")
		markers.server_clear("plan")
		for enemy: Dictionary in contract.get("known_enemies", []):
			var p: Array = enemy.get("pos", [])
			if p.size() >= 2:
				markers.server_report_enemy(Vector2(float(p[0]), float(p[1])), String(enemy.get("text", "")))
	_broadcast()


## Host only. Closes the briefing without starting (back to no deployment).
func server_close() -> void:
	if multiplayer.is_server():
		phase = Phase.IDLE
		_broadcast()


func server_set_ready(peer: int, is_ready: bool) -> void:
	if not multiplayer.is_server() or phase != Phase.BRIEFING:
		return
	if is_ready:
		ready_peers[peer] = true
	else:
		ready_peers.erase(peer)
	_broadcast()


func server_set_insertion(id: String) -> bool:
	if not multiplayer.is_server() or phase != Phase.BRIEFING:
		return false
	if not insertion_points().any(func(p: Dictionary) -> bool: return String(p.get("id", "")) == id):
		return false
	insertion_id = id
	_broadcast()
	return true


func server_set_support(id: String, picked: bool) -> bool:
	if not multiplayer.is_server() or phase != Phase.BRIEFING or id not in available_supports():
		return false
	if picked and id not in supports:
		supports.append(id)
	elif not picked:
		supports.erase(id)
	_broadcast()
	return true


## Host only. Starts the deployment when everyone is ready (or `force`): every peer gets the
## plan (deployment_started), and with auto_flow the squad moves in, extraction begins and the
## reinforcement timer starts. Returns whether it started.
func server_start(force := false) -> bool:
	if not multiplayer.is_server() or phase != Phase.BRIEFING or not (force or all_ready()):
		return false
	var markers := MapNodes.markers(self)
	plan = {"contract": contract.duplicate(true), "zone": zone.duplicate(true), "insertion": insertion().duplicate(true),
		"supports": supports.duplicate(), "plan_marks": markers.list("plan") if markers else [],
		"players": session_peers(), "started_msec": Time.get_ticks_msec()}
	phase = Phase.DEPLOYED
	_broadcast()
	_client_started.rpc(plan)
	if auto_flow:
		_default_flow()
	return true


## A copy of `p_zone` where a hot zone's insertion points can also be reached by helicopter
## (wave 5b: a "heli" point beside each one on foot; HeliSupports.server_insert flies the squad in).
static func with_heli_insertion(p_zone: Dictionary) -> Dictionary:
	var out := p_zone.duplicate(true)
	if String(out.get("kind", "contract")) != "hot":
		return out
	var points: Array = []
	for point: Dictionary in out.get("insertion_points", []):
		points.append(point)
		if String(point.get("method", "foot")) == "foot":
			points.append(point.merged({"id": "%s_heli" % point.get("id", ""), "name": "%s by helicopter" % point.get("name", ""), "method": HELI}, true))
	out["insertion_points"] = points
	return out


## The briefing's own flow (auto_flow): squad to the insertion point (flown in for a "heli"
## one), extraction, reinforcements.
func _default_flow() -> void:
	var point := insertion()
	var p: Array = point.get("pos", [])
	if p.size() >= 2:
		var at := Vector2(float(p[0]), float(p[1]))
		if String(point.get("method", "foot")) != HELI or not HeliSupports.server_insert(self, at):
			server_move_squad_to(at)
	var extraction := MapNodes.extraction(self)
	if extraction:
		extraction.server_begin(plan)
	var reinforcements := MapNodes.reinforcements(self)
	if reinforcements:
		reinforcements.server_start(contract.get("reinforcements", {}))


## Host only. Puts the players and their AI squadmates at a ground point (x, z): players in a
## row (each player's own machine moves its body), AI behind them.
func server_move_squad_to(at: Vector2) -> void:
	var i := 0
	for player: Soldier in MapNodes.players(self):
		var pos := ground_point(self, at + Vector2((i - 1.5) * INSERT_SPACING_M, 0.0))
		_client_insert.rpc_id(player.name.to_int(), pos)
		i += 1
	var j := 0
	for mate: Soldier in MapNodes.squad_ai(self):
		var pos := ground_point(self, at + Vector2((j % 4 - 1.5) * INSERT_SPACING_M, 3.0 + 2.0 * floorf(j / 4.0)))
		mate.global_position = pos
		mate.velocity = Vector3.ZERO
		j += 1


## A point on the ground (or on whatever is under it) at (x, z), a little above it.
static func ground_point(from: Node, at: Vector2) -> Vector3:
	var space := from.get_viewport().find_world_3d().direct_space_state if from.is_inside_tree() else null
	if space:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 200.0, at.y), Vector3(at.x, -50.0, at.y), 1))
		if not hit.is_empty():
			return hit.position + Vector3.UP * 0.1
	return Vector3(at.x, 0.1, at.y)


@rpc("any_peer", "call_local", "reliable")
func _server_ready(is_ready: bool) -> void:
	if multiplayer.is_server():
		server_set_ready(_sender(), is_ready)


@rpc("any_peer", "call_local", "reliable")
func _server_insertion(id: String) -> void:
	if multiplayer.is_server():
		server_set_insertion(id)


@rpc("any_peer", "call_local", "reliable")
func _server_support(id: String, picked: bool) -> void:
	if multiplayer.is_server():
		server_set_support(id, picked)


@rpc("any_peer", "call_local", "reliable")
func _server_start() -> void:
	if multiplayer.is_server() and _sender() == 1:
		server_start()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _state() -> Dictionary:
	return {"phase": phase, "contract": contract, "zone": zone, "ready": ready_peers.keys(), "insertion": insertion_id,
		"supports": supports, "plan": plan, "peers": session_peers()}


func _broadcast() -> void:
	_client_state.rpc(_state())


func _on_peer_joined(_id: int) -> void:
	if multiplayer.is_server():
		_broadcast()  # the joiner gets everything; the others, the new player list


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		ready_peers.erase(id)
		_broadcast.call_deferred()  # once the peer is gone from the list


# --- Every peer -----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _client_state(state: Dictionary) -> void:
	phase = int(state.get("phase", Phase.IDLE)) as Phase
	contract = state.get("contract", {})
	zone = state.get("zone", {})
	ready_peers = {}
	for id: int in state.get("ready", []):
		ready_peers[id] = true
	insertion_id = String(state.get("insertion", ""))
	supports = state.get("supports", [])
	plan = state.get("plan", {})
	_peers = state.get("peers", [1])
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_started(p_plan: Dictionary) -> void:
	plan = p_plan
	deployment_started.emit(p_plan)


## This player's own machine moves its body (owners simulate their movement).
@rpc("authority", "call_local", "reliable")
func _client_insert(pos: Vector3) -> void:
	var me := MapNodes.local_player(self)
	if me:
		me.global_position = pos
		me.velocity = Vector3.ZERO
		me.player_input.flash("Inserted at %s" % MapGrid.grid_ref_3d(pos, MapNodes.area_of(self)))
