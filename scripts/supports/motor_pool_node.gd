class_name MotorPoolNode
extends Node
## The motor pool in a level (wave 5b, V4): one node, "MotorPool", in every level on every peer
## (AavSupport.install), so its RPCs land at the same path everywhere.
## - Deployments (host): the briefing's picked supports "pool:<id>" (Briefing.available_supports
##   offers each vehicle the pool can send) arrive at the insertion point when it starts
##   (MotorPool.server_bring); when the squad extracts, each pool vehicle within "return_reach_m"
##   of the extraction point goes home with its state (MotorPool.server_return), and one
##   destroyed or left further out is gone from the pool (it stays in the zone, saved with it).
##   The debug extraction (BaseHub, Shift+End) counts the same, by the players' positions.
## - Every peer: the pool as the screens show it (pool: MotorPool.view()), sent to every
##   client whenever it changes and to a late joiner; repairs requested from the base's motor
##   pool terminal (request_repair: the host checks the sender and that they're at the
##   terminal, which only the base has).

const NODE_NAME := "MotorPool"
## How far (flat, feet to the terminal's foot) the host accepts a repair request from: the
## interaction menu's reach plus the slack the host allows other interactions for lag, and the
## desk's half depth.
const REPAIR_REACH_M := Soldier.INTERACT_REACH + Soldier.INTERACT_SLACK + 0.5

## Every peer: MotorPool.view() as the host last sent it.
var pool: Array = []
var _handled := false  # host: this deployment's vehicles were settled


func _init() -> void:
	name = NODE_NAME


## The level's motor pool node (or null).
static func of(from: Node) -> MotorPoolNode:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as MotorPoolNode if lvl else null


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	Campaign.changed.connect(_on_campaign_changed)
	var lvl := get_parent()
	var briefing := lvl.get_node_or_null(^"Briefing") as Briefing
	if briefing:
		briefing.deployment_started.connect(_on_deployment_started)
	var extraction := lvl.get_node_or_null(^"Extraction") as Extraction
	if extraction:
		extraction.deployment_ended.connect(_on_extracted)
	BaseHub.deployment_ended.connect(_on_base_deployment_ended)
	Economy.day_advanced.connect(_on_day_advanced)
	if multiplayer.is_server():
		MotorPool.server_reconcile(get_parent())  # nothing of this level's is out yet
		if MotorPool.in_use():
			pool = MotorPool.view()


# --- Deployments (host) ----------------------------------------------------------------------------

## Host: the briefing's start: each picked pool vehicle comes to the insertion point.
func _on_deployment_started(plan: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_handled = false
	var p: Array = plan.get("insertion", {}).get("pos", [])
	if p.size() < 2:
		return
	var at := Vector3(float(p[0]), 0.0, float(p[1]))
	var i := 0
	for id: Variant in plan.get("supports", []):
		if String(id).begins_with(Briefing.POOL_PREFIX):
			if server_bring_near(String(id).trim_prefix(Briefing.POOL_PREFIX), at, i) != null:
				i += 1


## Host: pool vehicle `id` arrives `bring_offset_m` behind `at` (away from the zone's middle),
## the `index`th side by side, facing in. Returns it or null.
func server_bring_near(id: String, at: Vector3, index := 0) -> Vehicle:
	var lvl := get_parent()
	var inward := -Vector3(at.x, 0.0, at.z).normalized() if Vector2(at.x, at.z).length() > 1.0 else Vector3.FORWARD
	var across := inward.cross(Vector3.UP)
	var offset := float(AavSupport.data().get("motor_pool", {}).get("bring_offset_m", 14.0))
	var spot := at - inward * offset + across * float((index + 1) / 2) * 7.0 * (1.0 if index % 2 == 0 else -1.0)
	if lvl.has_method(&"ground_point"):
		spot = lvl.call(&"ground_point", spot)
	return MotorPool.server_bring(id, lvl, Transform3D(Basis.looking_at(inward, Vector3.UP), spot + Vector3.UP * 0.2))


## Host: the squad extracted at `report.point`: pool vehicles near it go home, and (Captain,
## 2026-10-14: driving out at the zone's edge) those near each vehicle they drove out in
## (report "vehicles": [[x, z]]).
func _on_extracted(report: Dictionary) -> void:
	var at: Array = []
	for p: Array in [report.get("point", {}).get("pos", [])] + report.get("vehicles", []):
		if p.size() >= 2:
			at.append(Vector3(float(p[0]), 0.0, float(p[1])))
	if not at.is_empty():
		server_settle(at)


## Host: the debug extraction (BaseHub) ends a deployment without Extraction: what's near a
## player goes home. BaseHub has saved the zone and the campaign by now, so they're saved again
## when anything changed: a vehicle left behind stays in the zone, and the pool's record.
func _on_base_deployment_ended(_report: Dictionary) -> void:
	if not multiplayer.is_server() or _handled or not is_inside_tree() or CompoundLevel.current(self) != get_parent():
		return
	var at: Array[Vector3] = []
	for s: Soldier in MapNodes.players(self):
		at.append(s.global_position)
	var layer := VehicleLayer.of(self)
	var brought := 0
	for v in (layer.vehicles() if layer else []):
		if MotorPool.pool_id(v) != "":
			brought += 1
	var home := server_settle(at)
	if brought > home:
		GameState.save_zone()
	if brought > 0 and BaseHub.campaign_running:
		Campaign.save_campaign()


## Host: each pool vehicle in this level within return_reach_m of any of `points` goes home;
## the rest (destroyed, or left behind) leave the pool. Returns how many went home.
func server_settle(points: Array) -> int:
	if not multiplayer.is_server():
		return 0
	_handled = true
	var layer := VehicleLayer.of(self)
	var home := 0
	if layer == null:
		return 0
	for v in layer.vehicles():
		var id := MotorPool.pool_id(v)
		if id == "":
			continue
		if in_reach(v, points) and MotorPool.server_return(v):
			home += 1
		else:
			MotorPool.remove(id)
			v.remove_meta(&"no_save")  # it stays where it was left: the zone keeps it
			v.remove_meta(&"pool_id")
	return home


## Whether vehicle `v` is within return_reach_m (flat) of one of `points`: a pool vehicle that
## is goes home when the squad extracts there (server_settle).
static func in_reach(v: Vehicle, points: Array) -> bool:
	var reach := float(AavSupport.data().get("motor_pool", {}).get("return_reach_m", 60.0))
	for q: Vector3 in points:
		if Vector2(v.global_position.x - q.x, v.global_position.z - q.z).length() <= reach:
			return true
	return false


## Host. What's in the holds of the pool vehicles in this level that go home with the squad
## extracting at `points` (server_settle: in reach, still in the pool, and neither a wreck nor
## burning, which MotorPool.server_return loses), one entry per stack ({"id", "count", "state"?,
## "vehicle"}), leaving out `skip` (a helicopter the squad rides out in: Extraction lists its
## own hold). B-18: that left the zone with the squad, so it counts as carried out, though it
## stays in the vehicle (its record keeps the cargo): a hard case driven out in the M-ATV
## debriefed "failed".
func cargo_going_home(points: Array, skip: Node = null) -> Array:
	var out: Array = []
	var layer := VehicleLayer.of(self)
	for v in (layer.vehicles() if layer else []):
		var id := MotorPool.pool_id(v)
		if v == skip or v.is_queued_for_deletion() or id == "" or MotorPool.entry(id).is_empty() or v.wrecked or v.is_burning() \
				or not in_reach(v, points):
			continue
		var hold := v.cargo() as VehicleCargo
		for e: Dictionary in (hold.entries() if hold else []):
			var entry := {"id": String(e.id), "count": int(e.get("count", 1)), "vehicle": v.display_name()}
			if not (e.get("state", {}) as Dictionary).is_empty():
				entry["state"] = (e.state as Dictionary).duplicate(true)
			out.append(entry)
	return out


# --- The pool on every peer ------------------------------------------------------------------------

func _on_campaign_changed(section_name: StringName) -> void:
	if section_name == MotorPool.SECTION and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and is_inside_tree():
		_send.call_deferred()


## A day passing can bring a vehicle out of the workshop (MotorPool.problem reads the day).
func _on_day_advanced(_day: int, _days: int) -> void:
	_on_campaign_changed(MotorPool.SECTION)


func _send() -> void:
	if not is_inside_tree() or not multiplayer.is_server() or CompoundLevel.current(self) != get_parent():
		return
	MotorPool.server_reconcile(get_parent())  # (a campaign loaded mid-deployment: what's out isn't)
	if not MotorPool.in_use():
		return  # no pool started: don't start one (view() would)
	pool = MotorPool.view()
	_client_pool.rpc(pool)


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and is_inside_tree() and MotorPool.in_use():
		_client_pool.rpc_id(id, MotorPool.view())


@rpc("authority", "call_remote", "reliable")
func _client_pool(view: Array) -> void:
	pool = view


## Asks the host to service pool vehicle `id` (the base's motor pool terminal).
func request_repair(id: String) -> void:
	_server_repair.rpc_id(1, id)


## The motor pool terminal (BaseTerminal, kind motor_pool: the base has one) in this level within
## `who`'s reach (the interaction menu's, plus slack for lag), or null.
func terminal_near(who: Soldier) -> BaseTerminal:
	for n in get_tree().get_nodes_in_group(BaseTerminal.GROUP):
		var t := n as BaseTerminal
		if t and t.kind == &"motor_pool" and get_parent().is_ancestor_of(t) \
				and Vector2(t.global_position.x - who.global_position.x, t.global_position.z - who.global_position.z).length() <= REPAIR_REACH_M:
			return t
	return null


@rpc("any_peer", "call_local", "reliable")
func _server_repair(id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var lvl := get_parent() as CompoundLevel
	var who := lvl.players.get_node_or_null(str(sender)) as Soldier if lvl else null
	if who == null or not who.vitals.is_up() or MotorPool.entry(id).is_empty():
		return
	var terminal := terminal_near(who)
	var why := "Repairs are done at the base's motor pool" if terminal == null else MotorPool.server_repair(id)
	var e := MotorPool.entry(id)
	var reply := why if why != "" else "%s: in the workshop until day %d" % [String(e.name), int(e.ready_day)]
	## The answer goes to the base screen's status line too (review of ui/base-hub, audit P2-23):
	## Service is pressed on BaseUI's page, whose panel (layer 20) covers the HUD flash.
	BaseHub._client_note.rpc_id(sender, reply)
	who._client_message.rpc_id(sender, reply)


## Asks the host to fit (or remove) armour package `pkg` on pool vehicle `id` (A8; at the motor
## pool's terminal, as a service).
func request_package(id: String, pkg: String, fit: bool) -> void:
	_server_package.rpc_id(1, id, pkg, fit)


## Asks the host to set pool vehicle `id`'s FOB load-out (A8).
func request_loadout(id: String, loadout: String) -> void:
	_server_loadout.rpc_id(1, id, loadout)


@rpc("any_peer", "call_local", "reliable")
func _server_package(id: String, pkg: String, fit: bool) -> void:
	var who := _asker()
	if who == null or MotorPool.entry(id).is_empty():
		return
	var why := "Packages are fitted at the base's motor pool" if terminal_near(who) == null else MotorPool.server_package(id, pkg, fit)
	var e := MotorPool.entry(id)
	var reply := why if why != "" else "%s: %s %s, in the workshop until day %d" % [String(e.name), pkg, "fitted" if fit else "removed", int(e.ready_day)]
	_reply(who, reply)
	_send()


@rpc("any_peer", "call_local", "reliable")
func _server_loadout(id: String, loadout: String) -> void:
	var who := _asker()
	if who == null or MotorPool.entry(id).is_empty():
		return
	var why := MotorPool.server_set_loadout(id, loadout)
	_reply(who, why if why != "" else "%s: rearms to the %s load-out" % [String(MotorPool.entry(id).name), loadout.replace("_", " ")])
	_send()


## Host: the player who sent the RPC being handled, up (or null).
func _asker() -> Soldier:
	if not multiplayer.is_server():
		return null
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var lvl := get_parent() as CompoundLevel
	var who := lvl.players.get_node_or_null(str(sender)) as Soldier if lvl else null
	return who if who and who.vitals.is_up() else null


func _reply(who: Soldier, text: String) -> void:
	var peer := who.owner_peer()
	BaseHub._client_note.rpc_id(peer, text)
	who._client_message.rpc_id(peer, text)


## Client: the local player is within reach of the base's motor pool terminal, the host's check
## for Service (review of ui/base-hub: the page is a tab on every terminal's screen, and from
## the ops desk the host only ever refused).
func local_at_terminal() -> bool:
	var lvl := get_parent() as CompoundLevel
	var me := lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if lvl else null
	return me != null and terminal_near(me) != null
