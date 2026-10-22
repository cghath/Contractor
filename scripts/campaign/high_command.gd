class_name HighCommand
extends Node
## High command (docs/high_command.md, adopted by docs/combined_arms.md section 5): hero-led
## squads beside the player squad, each a Squad of its own with an hc_id, and the allied
## elements the company calls in, all ordered through one HcOrder path with a lifecycle and
## reports on the company net.
##
## One node per level ("HighCommand", MapNodes.install), the same path on every peer.
##  Host: the registry (groups), order intake and validation (HcOrder.clean), each hero squad's
##  SquadOrders, the company net (radio) with its rate limits, contact sharing between squads
##  (after NET_DELAY_S, as intel markers too), the commander token, and at the deployment's
##  start the company's detachments (BaseHub.server_spawn_detachment).
##  Clients: the replicated view (2 Hz), the orders and the net log; they never run SquadOrders.
## Phase 1 is C2; Phase 2 (C3): the Phase 2 verbs (SquadOrders), go codes (server_go), requests
## to the commander with a timeout (server_request, hc_approve / hc_deny), going dark.

signal changed
signal net_line(line: Dictionary)

const NODE_NAME := "HighCommand"
## Phase 2 verbs (C3) accepted.
const PHASE2 := true
## A request to the commander (break contact) waits this long, then the hero decides (4.2).
const REQUEST_S := 20.0
const THINK_S := 0.5
const VIEW_S := 0.5
## The net (high_command.md 6): one line a squad every NET_GAP_S, a queue of NET_QUEUE, the last
## NET_LOG lines kept. Priorities: casualty > request > unable > contact > set > the rest.
const NET_GAP_S := 3.0
const NET_QUEUE := 4
const NET_LOG := 50
const PRIORITY := {"casualty": 6, "succession": 6, "request": 5, "unable": 4, "held_up": 4, "contact": 3, "set": 2, "done": 2}
## Shared contacts reach the other squads this long after a report (5.1). Proposed.
const NET_DELAY_S := 3.0
## At most this many orders a second from one peer.
const MAX_ORDERS_PER_S := 4
## Hero squads start this far to either side of the insertion (3.1: 80-150 m). Proposed.
const INSERT_OFFSET_M := 100.0
## A hero squad's men stand this far apart when they spawn.
const SPAWN_SPACING_M := 2.5
## A hero squad of four (high_command.md 8, Phase 1): leader, autorifleman, medic, rifleman.
const TEAM_ROLES: Array[StringName] = [&"team_leader", &"autorifleman", &"medic", &"rifleman"]
## AlliedTroops' orders for each HcOrder verb.
const ALLIED_VERBS := {"move": "move", "hold": "hold", "defend": "defend", "follow": "follow", "support": "follow",
	"regroup": "regroup", "extract": "move", "attack": "assault", "fall_back": "fall_back", "bound": "flank", "sbf": "hold"}

## Host: id -> {"id", "kind": "hero"|"allied", "squad": Squad, "orders": SquadOrders or null,
## "callsign", "did", "slot" (allied), "order": {} (allied), "watch": ProgressWatch (allied)}.
var groups := {}
## Who holds the commander token (a peer id); the host by default.
var commander := 1
## Every peer: the status view, the orders by id and the net log.
var view: Array = []
var orders := {}
var net_log: Array = []
## Host: every line the squads said, before rate limiting (the session log, tests).
var said: Array = []
## Last refusal or message for this peer (tests, the panel).
var last_message := ""

var _think := 0.0
var _view_left := 0.0
var _net_next := {}  # squad id -> when it may speak again
var _net_queue: Array = []  # [{"prio", "line"}]
var _shares: Array = []  # [{"at", "from": id, "cluster"}]
var _rate := {}  # peer -> [times]
var _dispatching := false
## Host: pending requests: id -> {"id", "squad", "kind", "text", "until", "answer": Callable, "default": bool}.
var _requests := {}
var _request_id := 1
## Every peer: the pending requests [{"id", "squad", "callsign", "text", "left"}] (the HUD and the panel).
var requests: Array = []


static func of(from: Node) -> HighCommand:
	var level := MapNodes.level_of(from)
	return level.get_node_or_null(NodePath(NODE_NAME)) as HighCommand if level else null


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	if multiplayer.is_server():
		Supports.register("hc_dev_spawn", _cmd_dev_spawn)  # dev tools: a test squad (high_command.md 11, Phase 0)
		var b := MapNodes.briefing(self)
		if b:
			b.deployment_started.connect(_on_deployment_started)


# --- Spawning ------------------------------------------------------------------------------------

## Host: a friendly Squad `def.id` (hc_id) with `def.callsign`, its men spawned round `at` and
## its first man its hero and leader. def: {"id": "hawk2", "callsign": "Hawk 2", "size": 4,
## "members": [{spawn data overrides per man}] (optional), "combat", "discipline"}. Returns the
## Squad, or null off a level that can spawn. Registers it when the level has a HighCommand.
static func server_spawn_squad(level: Node, def: Dictionary, at: Vector3) -> Squad:
	if level == null or not level.has_method(&"spawn_soldier"):
		return null
	var id := StringName(def.get("id", "hc"))
	var sq := Squad.new()
	sq.name = "HC_%s" % String(id)
	sq.faction = &"friendly"
	sq.hc_id = id
	sq.callsign = String(def.get("callsign", String(id).capitalize()))
	level.add_child(sq)
	var members: Array = def.get("members", [])
	var size := int(def.get("size", maxi(members.size(), TEAM_ROLES.size())))
	var across := Vector3.RIGHT
	for i in size:
		var pos: Vector3 = at + across * SPAWN_SPACING_M * (i - (size - 1) / 2.0)
		if level.has_method(&"ground_point"):
			pos = level.call(&"ground_point", pos)
		var data := {"name": "%s_%d" % [String(id).to_upper(), i + 1], "faction": "friendly", "hc_id": String(id),
			"variant": Soldier.COMPANY_VARIANT, "pos": pos, "loadout": [], "role": String(TEAM_ROLES[i % TEAM_ROLES.size()]),
			"team": 0, "slot": -1, "combat": float(def.get("combat", 0.6)), "discipline": float(def.get("discipline", 0.65)),
			"guard": false, "mode": "aware"}
		if i < members.size():
			data.merge(members[i], true)
		var s: Soldier = level.call(&"spawn_soldier", data)
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = sq  # G7: on its own squad (_make_soldier already did, by hc_id)
	var men := sq.members()
	if not men.is_empty():
		sq.hero = men[0]
		sq.leader = men[0]
	for i in men.size():  # buddies in pairs
		men[i].buddy = men[i ^ 1] if (i ^ 1) < men.size() else null
	var hc := level.get_node_or_null(NodePath(NODE_NAME)) as HighCommand
	if hc:
		hc.server_register(sq, String(def.get("did", "")))
	return sq


## Host: puts a hero squad on the books (its SquadOrders made).
func server_register(sq: Squad, did := "") -> void:
	var id := String(sq.hc_id)
	groups[id] = {"id": id, "kind": "hero", "squad": sq, "orders": SquadOrders.new(sq, self), "callsign": sq.callsign, "did": did}
	_view_left = 0.0
	radio_group(id, "set", "%s up on the net, %d men" % [sq.callsign, sq.members().size()])


## Host, the briefing's start: the deployment's detachments come in beside the insertion.
func _on_deployment_started(plan: Dictionary) -> void:
	server_go.call_deferred("hhour")  # H-hour orders start with the deployment
	if not BaseHub.campaign_running or not BaseHub.deployment_running():
		return
	var dep := RosterDeployment.active(BaseHub.roster())
	var dets: Array = dep.get("detachments", [])
	if dets.is_empty():
		return
	var p: Array = plan.get("insertion", {}).get("pos", [])
	var at := Vector3(float(p[0]), 0.0, float(p[1])) if p.size() >= 2 else Vector3.ZERO
	var obj: Array = plan.get("insertion", {}).get("objective", [])
	var fwd := (Vector3(float(obj[0]), 0.0, float(obj[1])) - at).normalized() if obj.size() >= 2 else Vector3.FORWARD
	if not fwd.is_finite() or fwd.length() < 0.5:
		fwd = Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	for i in dets.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := at + right * side * INSERT_OFFSET_M * (1 + i / 2) - fwd * 20.0
		spot = _inside(spot)
		BaseHub.server_spawn_detachment(MapNodes.level_of(self), String(dets[i]), spot)


## Host, dev tools only: a hero squad of 4 (not roster members) 30 m beside `who`.
func _cmd_dev_spawn(who: Node, _arg: String, point: Vector3, _names: PackedStringArray) -> String:
	if not DevTools.on():
		return "Dev tools are off"
	var n := groups.size() + 1
	var at := (who as Node3D).global_position + Vector3(30, 0, 0) if who is Node3D else point
	var sq := server_spawn_squad(MapNodes.level_of(self), {"id": "dev%d" % n, "callsign": "Test %d" % n}, at)
	return "" if sq else "Couldn't spawn here"


# --- Orders --------------------------------------------------------------------------------------

## Any peer: asks the host to give `order` (an HcOrder dict). `append`: queue it.
func request_order(order: Dictionary, append := false) -> void:
	_server_order.rpc_id(1, order, append)


func request_cancel(squad_id: String, id := 0) -> void:
	_server_cancel.rpc_id(1, squad_id, id)


func request_command() -> void:
	_server_take_command.rpc_id(1)


func request_go(code: String) -> void:
	_server_go.rpc_id(1, code)


## Any peer (Ctrl+Z on the map): undo the last order given to `squad_id` (SquadOrders.undo).
func request_undo(squad_id: String) -> void:
	_server_undo.rpc_id(1, squad_id)


@rpc("any_peer", "call_local", "reliable")
func _server_undo(squad_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var why := server_undo(squad_id, peer if peer != 0 else 1)
	if why != "" and peer != 0:
		_client_refused.rpc_id(peer, 0, why)


## Host: undoes `squad_id`'s last order for `peer` (the commander). Returns "" or why not.
func server_undo(squad_id: String, peer := 1) -> String:
	if peer != commander:
		return _refuse("you don't have command")
	var g: Dictionary = groups.get(squad_id, {})
	if g.is_empty() or g.orders == null:
		return _refuse("Nothing to undo")
	var why: String = (g.orders as SquadOrders).undo()
	if why == "":
		radio_group(squad_id, "copy", "copy, belay that")
	return _refuse(why) if why != "" else ""


func request_answer(id: int, yes: bool) -> void:
	_server_answer.rpc_id(1, id, yes)


@rpc("any_peer", "call_local", "reliable")
func _server_go(code: String) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		if (peer if peer != 0 else 1) == commander:
			server_go(code)


@rpc("any_peer", "call_local", "reliable")
func _server_answer(id: int, yes: bool) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		if (peer if peer != 0 else 1) == commander:
			server_answer(id, yes)


## Host: go code `code` (alpha, bravo, charlie, hhour): every squad waiting on it goes. Returns how many.
func server_go(code: String) -> int:
	var n := 0
	for id: String in groups:
		var so: SquadOrders = groups[id].orders
		if so and so.go(code):
			n += 1
	radio_group("", "set", "%s, go: %d squad%s" % [code.capitalize(), n, "" if n == 1 else "s"])
	return n


## Host: how many orders wait on each go code {code: n} (the panel's go buttons).
func waiting_counts() -> Dictionary:
	var out := {}
	for id: String in groups:
		var so: SquadOrders = groups[id].orders
		if so and not so.order.is_empty() and String(so.order.get("go", "")) != "" and String(so.order.state) in ["waiting", "set"]:
			out[String(so.order.go)] = int(out.get(String(so.order.go), 0)) + 1
	return out


## Host (SquadOrders): `so`'s hero asks the commander `text` (kind "break_contact"); `answer`
## gets yes or no, from the commander or, after REQUEST_S, `default_yes` (the hero decides).
func server_request(so: SquadOrders, kind: String, text: String, answer: Callable, default_yes: bool) -> int:
	var id := _request_id
	_request_id += 1
	var sid := String(so.squad.hc_id)
	_requests[id] = {"id": id, "squad": sid, "kind": kind, "text": text, "until": Soldier._now() + REQUEST_S, "answer": answer, "default": default_yes}
	so.radio("request", text)
	_send_requests()
	return id


## Host: answers request `id`. Returns whether it was still pending.
func server_answer(id: int, yes: bool, by_timeout := false) -> bool:
	var r: Dictionary = _requests.get(id, {})
	if r.is_empty():
		return false
	_requests.erase(id)
	if by_timeout:
		radio_group(String(r.squad), "request", "no answer, %s" % ("breaking contact" if bool(r.default) else "holding on"))
	else:
		radio_group(String(r.squad), "copy", "copy, %s" % ("approved" if yes else "denied"))
	(r.answer as Callable).call(yes)
	_send_requests()
	return true


func _tick_requests(now: float) -> void:
	for id: int in _requests.keys():
		if now >= float(_requests[id].until):
			server_answer(id, bool(_requests[id].default), true)


func _send_requests() -> void:
	var out: Array = []
	for r: Dictionary in _requests.values():
		out.append({"id": r.id, "squad": r.squad, "callsign": String(groups.get(String(r.squad), {}).get("callsign", r.squad)), "text": r.text, "until_in": float(r.until) - Soldier._now()})
	if multiplayer.has_multiplayer_peer():
		_client_requests.rpc(out)


@rpc("authority", "call_local", "reliable")
func _client_requests(list: Array) -> void:
	requests = list
	for r: Dictionary in requests:
		r["until"] = Soldier._now() + float(r.until_in)
	changed.emit()


@rpc("any_peer", "call_local", "reliable")
func _server_order(order: Dictionary, append: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var why := server_order(order, append, peer if peer != 0 else 1)
	if why != "" and peer != 0:
		_client_refused.rpc_id(peer, int(order.get("id", 0)), why)


@rpc("any_peer", "call_local", "reliable")
func _server_cancel(squad_id: String, id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	server_cancel(squad_id, id, peer if peer != 0 else 1)


@rpc("any_peer", "call_local", "reliable")
func _server_take_command() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	server_set_commander(peer if peer != 0 else 1)


## Host: who may give orders (the commander token, high_command.md 7).
func server_set_commander(peer: int) -> void:
	if _player(peer) == null:
		return
	commander = peer
	radio_group("", "set", "Player %d has command" % peer)
	_view_left = 0.0


## Host: validates and gives `order` from `peer`. Returns "" or why not.
func server_order(order: Dictionary, append := false, peer := 1) -> String:
	var me := _player(peer)
	if me == null or not me.vitals.is_up():
		return _refuse("You need to be up to give orders")
	var now := Soldier._now()
	var times: Array = _rate.get(peer, [])
	times = times.filter(func(t: float) -> bool: return now - t < 1.0)
	if times.size() >= MAX_ORDERS_PER_S:
		return _refuse("Too many orders at once")
	times.append(now)
	_rate[peer] = times
	var sid := String(order.get("squad", ""))
	var g: Dictionary = groups.get(sid, {})
	var live := {}
	for id: String in groups:
		if _group_alive(groups[id]):
			live[id] = true
	var queued := 0
	if not g.is_empty() and g.orders:
		queued = (g.orders as SquadOrders).queue.size()
	var res := HcOrder.clean(order, {"area": MapNodes.area_of(self), "squads": live, "commander": peer == commander,
		"queued": queued, "append": append, "phase2": PHASE2})
	if not bool(res.ok):
		return _refuse(String(res.why))
	var o: Dictionary = res.order
	o.id = HcOrder.next_id() if int(o.get("id", 0)) <= 0 or orders.has(int(o.id)) else int(o.id)
	o.by = peer
	o.at = now
	if String(o.verb) in ["follow", "support"] and String((o.get("target", {}) as Dictionary).get("ref", "")) == "":
		o.target = {"kind": "player", "ref": str(peer)}
	if String(g.kind) == "allied":
		return _allied_order(g, o, me)
	(g.orders as SquadOrders).give(o, append)
	SessionLog.note("[hc] %s: %s from player %d (%s)" % [g.callsign, o.verb, peer, "queued" if append else "now"])
	return ""


## Host: cancels group `squad_id`'s order `id` (0: its current one).
func server_cancel(squad_id: String, id := 0, peer := 1) -> bool:
	if peer != commander:
		return false
	var g: Dictionary = groups.get(squad_id, {})
	if g.is_empty():
		return false
	if g.orders:
		return (g.orders as SquadOrders).cancel(id)
	var o: Dictionary = g.get("order", {})
	if o.is_empty() or HcOrder.ended(o):
		return false
	o.state = "cancelled"
	order_changed(o)
	return true


## SquadOrders: an order changed state; every peer mirrors it.
func order_changed(o: Dictionary) -> void:
	orders[int(o.id)] = o.duplicate(true)
	_client_order.rpc(o)
	_view_left = 0.0


# --- Allied elements onto HcOrder (combined_arms.md 5.1) -----------------------------------------

## Host: AlliedTroops gave element `e` order `verb` at `point` (its own menu or map path): the
## order goes on the books with a lifecycle, so it reports like a hero squad's.
func note_allied_order(e: Dictionary, verb: String, point: Vector3, by: Soldier) -> void:
	if _dispatching:
		return
	var g := _allied_group(e)
	var hv: String = verb if verb in HcOrder.VERBS_1 + HcOrder.VERBS_2 else {"assault": "attack", "flank": "bound"}.get(verb, verb)
	var o := HcOrder.make(String(g.id), hv, [[point.x, point.z]] if point.is_finite() else [])
	o.id = HcOrder.next_id()
	o.by = by.name.to_int() if by else 1
	o.at = Soldier._now()
	_track_allied(g, o)


func _allied_order(g: Dictionary, o: Dictionary, me: Soldier) -> String:
	var at := HcOrder.point(o)
	var point := Vector3(at.x, 0.0, at.y) if at.is_finite() else me.global_position
	var allied := _allied()
	if allied == null:
		return _refuse("No allied troops here")
	_dispatching = true
	var why: String = allied.server_order(me, String(ALLIED_VERBS.get(String(o.verb), "move")), point, str(int(g.slot)))
	_dispatching = false
	if why != "":
		return _refuse(why)
	_track_allied(g, o)
	return ""


func _track_allied(g: Dictionary, o: Dictionary) -> void:
	var old: Dictionary = g.get("order", {})
	if not old.is_empty() and not HcOrder.ended(old):
		old.state = "cancelled"
		old.why = "replaced"
		order_changed(old)
	o.state = "set" if String(o.verb) == "hold" else "active"
	g["order"] = o
	g["watch"] = ProgressWatch.new()
	(g.watch as ProgressWatch).reset(Soldier._now())
	order_changed(o)
	radio_group(String(g.id), "copy", "copy, %s%s" % [HcOrder.verb_text(String(o.verb)),
		" to %s" % MapGrid.grid_ref(HcOrder.point(o), MapNodes.area_of(self), 6) if HcOrder.point(o).is_finite() else ""])


func _allied_group(e: Dictionary) -> Dictionary:
	var id := "allied%d" % int(e.id)
	if not groups.has(id) or groups[id].squad != e.squad:
		var sq: Squad = e.squad
		groups[id] = {"id": id, "kind": "allied", "squad": sq, "orders": null, "callsign": sq.callsign if sq.callsign != "" else "Allied %d" % int(e.id),
			"slot": int(e.id), "order": {}, "watch": ProgressWatch.new()}
	return groups[id]


func _tick_allied(now: float) -> void:
	var allied := _allied()
	if allied:
		for e: Dictionary in allied.out():
			_allied_group(e)
	for id: String in groups.keys():
		var g: Dictionary = groups[id]
		if String(g.kind) != "allied":
			continue
		if not _group_alive(g):
			groups.erase(id)
			continue
		var o: Dictionary = g.order
		if o.is_empty() or HcOrder.ended(o) or String(o.state) == "set":
			continue
		var p := HcOrder.point(o)
		if not p.is_finite():
			continue
		var goal := Vector3(p.x, 0.0, p.y)
		var c := _centre(g.squad)
		if Vector2(c.x - goal.x, c.z - goal.z).length() <= 12.0:
			o.state = "set" if String(o.verb) in ["defend", "hold"] else "done"
			order_changed(o)
			radio_group(id, "done", "set at %s" % MapGrid.grid_ref_3d(c, MapNodes.area_of(self), 6))
			continue
		if String(o.verb) in ["move", "defend", "regroup", "extract"]:
			var w: ProgressWatch = g.watch
			var st := w.feed(c, goal, now)
			if st == ProgressWatch.UNABLE:
				o.state = "failed"
				o.why = "no route"
				order_changed(o)
				radio_group(id, "unable", "unable: no route to %s. Holding" % MapGrid.grid_ref(p, MapNodes.area_of(self), 6))


func _allied() -> AlliedTroops:
	var level := MapNodes.level_of(self)
	return level.get_node_or_null(NodePath(AlliedTroops.NODE_NAME)) as AlliedTroops if level else null


# --- The company net (high_command.md 6) -------------------------------------------------------

## Host (SquadOrders): `so`'s squad says `text` on the net.
func radio(so: SquadOrders, kind: String, text: String, pos: Variant = null) -> void:
	radio_group(String(so.squad.hc_id), kind, text, pos)


## Host: a net line from group `id` ("" for the company itself), rate limited per squad.
func radio_group(id: String, kind: String, text: String, pos: Variant = null) -> void:
	var g: Dictionary = groups.get(id, {})
	var callsign := String(g.get("callsign", "Command")) if id != "" else "Command"
	var line := {"t": Soldier._now(), "squad": id, "callsign": callsign, "kind": kind, "text": "%s, %s" % [callsign, text]}
	if pos is Vector3:
		line["pos"] = [(pos as Vector3).x, (pos as Vector3).z]
	SessionLog.note("[hc] %s" % line.text)
	said.append(line)  # (host: every line, before the rate limit drops any)
	if said.size() > NET_LOG:
		said.pop_front()
	var now := Soldier._now()
	if now < float(_net_next.get(id, -INF)) and kind not in ["copy", "casualty", "succession"]:
		_net_queue.append({"prio": int(PRIORITY.get(kind, 1)), "line": line})
		_net_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.prio) > int(b.prio))
		if _net_queue.size() > NET_QUEUE:
			_net_queue.resize(NET_QUEUE)
		return
	_net_next[id] = now + NET_GAP_S
	_send_line(line)


func _send_line(line: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer():
		_client_net.rpc(line)
	else:
		_client_net(line)


func _flush_net(now: float) -> void:
	for i in range(_net_queue.size() - 1, -1, -1):
		var q: Dictionary = _net_queue[i]
		var id := String(q.line.squad)
		if now >= float(_net_next.get(id, -INF)):
			_net_queue.remove_at(i)
			_net_next[id] = now + NET_GAP_S
			_send_line(q.line)


## Host (SquadOrders): a fresh contact `cluster` from `so`'s squad: an intel marker now, and the
## other squads hear of it after NET_DELAY_S (unless the reporting squad has gone dark).
func share_contact(so: SquadOrders, cluster: Dictionary) -> void:
	var marks := MapNodes.markers(self)
	if marks:
		marks.server_report_enemy(cluster.centre, "%s: %dx" % [so.squad.callsign, int(cluster.count)])
	_shares.append({"at": Soldier._now() + NET_DELAY_S, "from": String(so.squad.hc_id), "who": (cluster.who as Array).duplicate(),
		"pos": cluster.centre})


func _tick_shares(now: float) -> void:
	for i in range(_shares.size() - 1, -1, -1):
		var s: Dictionary = _shares[i]
		if now < float(s.at):
			continue
		_shares.remove_at(i)
		var targets: Array = []
		for id: String in groups:
			if id != String(s.from) and _group_alive(groups[id]):
				targets.append(groups[id].squad)
		var level := MapNodes.level_of(self) as CompoundLevel
		if level:
			targets.append(level.squad_for(&"friendly"))
		for sq: Variant in targets:
			for who: Variant in s.who:
				if who is Soldier and is_instance_valid(who):
					(sq as Squad).note_enemy(who, s.pos, true)  # heard of over the net: a rough fix


# --- Ticking and the view ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_think -= delta
	if _think <= 0.0:
		_think = THINK_S
		var now := Soldier._now()
		for id: String in groups.keys():
			var g: Dictionary = groups[id]
			if g.orders and is_instance_valid(g.squad):
				(g.orders as SquadOrders).tick(now)
		_tick_allied(now)
		_tick_shares(now)
		_tick_requests(now)
		_flush_net(now)
	_view_left -= delta
	if _view_left <= 0.0:
		_view_left = VIEW_S
		var v := build_view()
		if v != view:
			_client_view.rpc(v, commander)


## Host: the compact status of every group (high_command.md 7): ~200 B a squad.
func build_view() -> Array:
	var out: Array = []
	var ids := groups.keys()
	ids.sort()
	for id: String in ids:
		var g: Dictionary = groups[id]
		if not _group_alive(g):
			continue
		var sq: Squad = g.squad
		var men := sq.members()
		var up := men.filter(func(s: Soldier) -> bool: return s.vitals.is_up()).size()
		var so: SquadOrders = g.orders
		var o: Dictionary = so.order if so else g.get("order", {})
		var lead: Soldier = sq.hero if sq.hero and is_instance_valid(sq.hero) else (men[0] if not men.is_empty() else null)
		var dark := so != null and so.is_dark()
		var at := lead.global_position if lead else _centre(sq)
		var ce := so.ce() if so else 1.0
		out.append({"id": id, "kind": g.kind, "callsign": g.callsign, "hero": lead.person_name if lead and lead.person_name != "" else "",
			"up": up, "total": men.size(), "ce": snappedf(ce, 0.01), "band": SquadOrders.ce_band(ce), "pos": [snappedf(at.x, 0.1), snappedf(at.z, 0.1)],
			"heading": snappedf(lead.rotation.y, 0.01) if lead else 0.0, "contact": sq.is_engaged(), "dark": dark,
			"order": {"id": int(o.get("id", 0)), "verb": String(o.get("verb", "")), "points": o.get("points", []), "state": String(o.get("state", "")),
				"go": String(o.get("go", "")), "why": String(o.get("why", ""))} if not o.is_empty() else {},
			"queue": so.queue.size() if so else 0, "last": so.last_verb if so else "", "men": men.map(func(s: Soldier) -> Array: return [snappedf(s.global_position.x, 0.1), snappedf(s.global_position.z, 0.1)])})
	return out


@rpc("authority", "call_local", "unreliable_ordered")
func _client_view(v: Array, cmd: int) -> void:
	view = v
	commander = cmd
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_order(o: Dictionary) -> void:
	orders[int(o.id)] = o
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_refused(id: int, why: String) -> void:
	last_message = why
	if orders.has(id):
		orders[id].state = "failed"
		orders[id].why = why
	MapNodes.flash_local(self, "Order refused: %s" % why)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_net(line: Dictionary) -> void:
	net_log.append(line)
	if net_log.size() > NET_LOG:
		net_log.pop_front()
	# Net lines show with the callouts' subtitles, the speaker marked "(net)" (high_command.md 6).
	var level := MapNodes.level_of(self)
	var callouts: Callouts = level.get(&"callouts") if level else null
	if callouts:
		callouts.shown.append({"speaker": "%s (net)" % String(line.get("callsign", "")), "id": &"", "text": String(line.text), "time": Soldier._now()})
		callouts.line_shown.emit("%s (net)" % String(line.get("callsign", "")), String(line.text))
	net_line.emit(line)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_snapshot(v: Array, all_orders: Dictionary, lines: Array, cmd: int) -> void:
	view = v
	orders = all_orders
	net_log = lines
	commander = cmd
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_client_snapshot.rpc_id(id, build_view(), orders, net_log, commander)


# --- Helpers -------------------------------------------------------------------------------------

## Every peer: the view entry for group `id`, or {}.
func status(id: String) -> Dictionary:
	for e: Dictionary in view:
		if String(e.id) == id:
			return e
	return {}


## Every peer: whether this peer holds the commander token.
func is_commander() -> bool:
	return multiplayer.get_unique_id() == commander


func _player(peer: int) -> Soldier:
	for p: Soldier in MapNodes.players(self):
		if p.name.to_int() == peer:
			return p
	return null


static func _group_alive(g: Dictionary) -> bool:
	var v: Variant = g.get("squad")
	if v == null or not is_instance_valid(v):
		return false  # (a freed squad: assigning it to a typed Squad would error)
	return (v as Squad).members().any(func(s: Soldier) -> bool: return s.vitals.is_up())


static func _centre(sq: Squad) -> Vector3:
	var men := sq.members() if sq and is_instance_valid(sq) else ([] as Array[Soldier])
	if men.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for s in men:
		c += s.global_position
	return c / men.size()


func _inside(p: Vector3) -> Vector3:
	var area := MapNodes.area_of(self).grow(-HcOrder.EDGE_M)
	if area.size.x <= 0.0:
		return p
	return Vector3(clampf(p.x, area.position.x, area.end.x), p.y, clampf(p.z, area.position.y, area.end.y))


func _refuse(why: String) -> String:
	last_message = why
	return why
