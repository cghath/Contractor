class_name OpBase
extends Node
## What the operation types' own mechanics share (docs/combined_arms.md 6.4; phases D4 and D5,
## cg_brief queue item 3.3). Each type's mechanic (OpInvasion, OpThrust, OpLanding, OpCrossing,
## OpTown) and the support every type has (OpSupport: attached armour, allied fires, the
## logistics) is one of these, a child of the zone's Operations node on every peer (OpTypes.install),
## so the same path answers RPCs everywhere. Operations calls it through the type's hooks
## (OpTypes.register_all): start, tick, phase_begun, phase_done, task, h_hour, view.
##
## - `state`: what every peer shows of it (the host's truth): sent to every peer by publish(),
##   asked for by a late joiner (_ask_state), in Operations' view as "extra".
## - mine(): its own record on the contract's run ("op_run" "mech"), so a save keeps it.
## - note(): a line for the debrief (the run's "notes"; Operations.summary_lines prints them).
## - The groups it leads itself (a wave going in, the engineers on their firing point): each a
##   SquadOrders of its own with this node as its commander (the hc interface: order_changed, radio,
##   share_contact, server_request), so they take the same HcOrder verbs B2 and high command give.
## - Waves of the enemy (add_wave, send_waves): OOB entries waiting where the type puts them, out by
##   the front's own rules (Operations: 600-2,600 m from a player, out of sight), then sent at their
##   objective from the axis the hostile side picks from its picture (pick_axis).

signal state_changed

## Host: the last tick's cost (µs) and the worst so far (the budgets check), leaving out a tick that
## put something new in the world (`heavy`: a vehicle and its crew spawned, as Operations' own
## spawner costs, outside the mechanic's budget).
var cost_us := 0.0
var worst_us := 0.0
var heavy := false
## Host: the worst tick's cost by part (a mechanic that times its parts), for the budgets check.
var worst_what := ""
## Every peer.
var state := {}
var ops: Operations

var _orders := {}  # host: squad instance id -> {"squad", "so"}
var _orders_left := 0.0
var _said_at := {}


func _ready() -> void:
	ops = get_parent() as Operations
	if not _host():
		_ask.call_deferred()


func _host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func op_type() -> String:
	return String(ops.def.get("op_type", "")) if ops else ""


## The type's data (data/operations.json "types"), its section `key` ({} for none).
func cfg(key := "") -> Dictionary:
	var t := Operations.type_def(op_type())
	return t if key == "" else (t.get(key, {}) as Dictionary)


func num(section: String, key: String, fallback := 0.0) -> float:
	return float(cfg(section).get(key, fallback))


func contract() -> Dictionary:
	return ops.contract() if ops else {}


func run() -> Dictionary:
	var c := contract()
	return Operations.run_of(c) if not c.is_empty() else {}


## This mechanic's record on the run (saved with the contract).
func mine() -> Dictionary:
	var r := run()
	if r.is_empty():
		return {}
	if not r.has("mech") or not r.mech is Dictionary:
		r["mech"] = {}
	var m: Dictionary = r.mech
	if not m.has(String(name)) or not m[String(name)] is Dictionary:
		m[String(name)] = {}
	return m[String(name)]


## A line for the debrief (once each).
func note(text: String) -> void:
	var r := run()
	if r.is_empty():
		return
	if not r.has("notes") or not r.notes is Array:
		r["notes"] = []
	if not text in (r.notes as Array):
		(r.notes as Array).append(text)
	SessionLog.note("operation %s: %s" % [ops.cid, text])


func say(text: String) -> void:
	if ops:
		ops._say(text)


## Says `text` at most every `gap_s` under `key`.
func say_once(key: String, text: String, gap_s := 60.0) -> void:
	var t := Soldier._now()
	if t - float(_said_at.get(key, -INF)) < gap_s:
		return
	_said_at[key] = t
	say(text)


func clock() -> float:
	return float(run().get("clock_s", 0.0))


func phase() -> int:
	return int(run().get("phase", 0))


func level() -> Node:
	return ops._level if ops else null


func ground(p: Vector3) -> Vector3:
	return ops._ground(p) if ops else p


func v3(p: Variant) -> Vector3:
	return ops._v3(p) if ops else Vector3.ZERO


func grid_ref(p: Vector3) -> String:
	return ops._grid_ref(p) if ops else ""


# --- What the hooks call (host; the types override them) -------------------------------------------

func start() -> void:
	pass


## A loaded save's run picks up (Operations' "resume" hook): start() again, which keeps what mine() has.
func resume() -> void:
	start()


func tick(_dt: float) -> void:
	pass


func phase_begun(_k: int) -> void:
	pass


func phase_done(_k: int) -> void:
	pass


## A company task of a kind of the type's own: "" (no change) or a state.
func task(_o: Dictionary, _dt: float) -> String:
	return ""


## The beach landing's dawn: whether H-hour has come.
func h_hour() -> bool:
	return true


## What the strip and the debrief carry of it (the view's "extra" under this node's name).
func view() -> Dictionary:
	return state


## Its line on the operation strip ("" for none): host, from its state.
func strip_line() -> String:
	return ""


# --- Every peer: the state ------------------------------------------------------------------------

func publish() -> void:
	if not _host():
		return
	state_changed.emit()
	if ops and ops._online():
		_client_state.rpc(state)


func _ask() -> void:
	if is_inside_tree() and ops and ops._online():
		_ask_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_state() -> void:
	if multiplayer.is_server():
		_client_state.rpc_id(multiplayer.get_remote_sender_id(), state)


@rpc("authority", "call_remote", "reliable")
func _client_state(s: Dictionary) -> void:
	state = s
	_on_state()
	state_changed.emit()


## Every peer, a client once the host's state has come: rebuild what it shows.
func _on_state() -> void:
	pass


# --- Groups it leads itself (host) ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _host() or _orders.is_empty():
		return
	_orders_left -= delta
	if _orders_left > 0.0:
		return
	_orders_left = SquadOrders.THINK_S
	var now := Soldier._now()
	for key: Variant in _orders.keys():
		var e: Dictionary = _orders[key]
		var squad := e.squad as Squad
		if squad == null or not is_instance_valid(squad) or squad.is_queued_for_deletion():
			_orders.erase(key)
			continue
		if not _hero(squad):
			continue
		(e.so as SquadOrders).tick(now)


func _hero(squad: Squad) -> bool:
	if squad.hero and is_instance_valid(squad.hero) and squad.hero.vitals.is_up():
		return true
	for s: Soldier in squad.members():
		if s.vitals.is_up():
			squad.hero = s
			if not is_instance_valid(squad.leader) or not squad.leader.vitals.is_up():
				squad.leader = s
			return true
	return false


static func squad_key(squad: Squad) -> String:
	return String(squad.hc_id) if String(squad.hc_id) != "" else GroupBoard.group_id(squad)


## Host: `squad` (out of any commander's hands) takes HcOrder `verb` along `points` ([[x, z]]).
func give(squad: Squad, verb: String, points: Array, extra := {}) -> bool:
	if squad == null or not is_instance_valid(squad) or not _hero(squad):
		return false
	var key := squad.get_instance_id()
	if not _orders.has(key):
		if String(squad.hc_id) == "":
			squad.hc_id = StringName(GroupBoard.group_id(squad))
		_orders[key] = {"squad": squad, "so": SquadOrders.new(squad, self)}
	var so := _orders[key].so as SquadOrders
	var id := squad_key(squad)
	var ctx := {"commander": true, "squads": {id: true}, "phase2": true, "queued": so.queue.size()}
	var lvl := level()
	if lvl and lvl.has_method(&"map_area"):
		ctx["area"] = lvl.call(&"map_area")
	var c := HcOrder.clean(HcOrder.make(id, verb, points, extra), ctx)
	if not bool(c.ok):
		SessionLog.note("operation %s: %s's %s refused: %s" % [ops.cid if ops else "", squad.callsign, verb, c.why])
		return false
	var order: Dictionary = c.order
	order.id = HcOrder.next_id()
	order.at = Soldier._now()
	so.give(order)
	return true


func led(squad: Squad) -> bool:
	return squad != null and _orders.has(squad.get_instance_id())


## The hc interface SquadOrders talks to.
func order_changed(_o: Dictionary) -> void:
	pass


func radio(so: SquadOrders, kind: String, text: String, _pos: Variant = null) -> void:
	if kind in ["casualty", "unable"] and so and so.squad:
		SessionLog.note("operation %s: %s: %s" % [ops.cid if ops else "", so.squad.callsign, text])


func share_contact(_so: SquadOrders, _cluster: Dictionary) -> void:
	pass


func server_request(_so: SquadOrders, _kind: String, _text: String, answer: Callable, default_yes: bool) -> int:
	if answer.is_valid():
		answer.call(default_yes)
	return 0


# --- Waves of the enemy (host) --------------------------------------------------------------------

## Host: a wave of the enemy waiting at `at` (x, z): `groups` groups of `men` (each with
## `vehicles`, `crew` a vehicle), as OOB entries that come out by the front's rules. Their ids.
func add_wave(callsign: String, groups: int, men: int, at: Vector2, vehicles: Array = [], crew := 0, kit := "rifles") -> Array:
	var r := run()
	var ids: Array = []
	if r.is_empty():
		return ids
	for g in groups:
		var off := Vector2(-40.0 + 80.0 * g, 30.0 * (g % 2))
		var id := "h%d" % ((r.oob as Array).size() + 1)
		(r.oob as Array).append({"id": id, "side": "hostile", "kind": "light_armour" if not vehicles.is_empty() else "rifle_squad",
			"callsign": "%s %d" % [callsign, g + 1], "men": men, "crew": crew, "vehicles": vehicles.duplicate(), "kit": kit,
			"pos": [snappedf(at.x + off.x, 1.0), snappedf(at.y + off.y, 1.0)], "reserve": false, "wave_s": 0.0, "state": Operations.PENDING,
			"wave": callsign})
		ids.append(id)
	return ids


## Host: every entry of `ids` that's out and not yet sent goes for `target`: an attack there.
func send_waves(ids: Array, target: Vector3) -> int:
	var n := 0
	var r := run()
	for e: Dictionary in r.get("oob", []):
		if not String(e.id) in ids or String(e.state) != "live" or bool(e.get("sent", false)):
			continue
		var rec: Dictionary = ops.records.get(String(e.id), {})
		var squad := rec.get("squad") as Squad
		if squad == null or not is_instance_valid(squad):
			continue
		_release(squad)
		var vs: Array = (rec.get("vehicles", []) as Array).filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Vehicle).wrecked)
		var drivers := SquadDrivers.of(self)
		if not vs.is_empty() and drivers:
			for v: Vehicle in vs:
				drivers.go(v, target + (v.global_position - target).normalized() * 120.0, true)  # in with their guns, short of the centre
		heavy = true
		if give(squad, "attack", [[target.x, target.z]], {"target": {"kind": "point", "pos": [target.x, target.z]}, "posture": {"mode": "combat"}}):
			e["sent"] = true
			n += 1
	return n


## Host: a group the type leads now: out of the hostile commander's hands (it would task it elsewhere).
func _release(squad: Squad) -> void:
	if ops and ops.hostile and is_instance_valid(ops.hostile):
		ops.hostile.server_unregister(GroupBoard.group_id(squad))


## Host: the men up of entries `ids` (live, a profile's, or still to come).
func wave_up(ids: Array) -> int:
	var n := 0
	for e: Dictionary in run().get("oob", []):
		if not String(e.id) in ids:
			continue
		match String(e.state):
			Operations.PENDING, "spawning":
				n += int(e.men) + int(e.crew) * (e.vehicles as Array).size()
			"live":
				var rec: Dictionary = ops.records.get(String(e.id), {})
				n += Virtualizer.up(rec) if not rec.is_empty() else 0
	return n


## Host, each tick of a phase with a counterattack (the type's `section` "counter": [{"at_s" (after
## the phase began), "groups", "men", "vehicles", "crew", "callsign", "mortar": rounds first}]):
## each wave due is made at the assembly point the enemy picks (pick_axis from `from_dir`, with
## `seen`: the defence it knows of), its mortar first; then every wave that's out goes for `target`.
func counter_step(section: String, target: Vector3, from_dir: Vector2, seen: Array) -> void:
	var m := mine()
	var k := phase()
	var recs: Array = run().get("phases", [])
	if k >= recs.size():
		return
	var since := clock() - float((recs[k] as Dictionary).get("started_s", clock()))
	var waves: Dictionary = m.get("waves", {})
	m["waves"] = waves
	var plan: Array = cfg(section).get("counter", [])
	for i in plan.size():
		var w: Dictionary = plan[i]
		var key := "%d:%d" % [k, i]
		if waves.has(key) or since < float(w.get("at_s", 0.0)):
			continue
		var axis := pick_axis(target, from_dir, seen, int(cfg(section).get("axes", 3)), float(cfg(section).get("assembly_m", 900.0)),
			float(cfg(section).get("spread_deg", 50.0)))
		var ids := add_wave(String(w.get("callsign", "Wave %d" % (i + 1))), int(w.get("groups", 1)), int(w.get("men", 6)), axis.pos,
			w.get("vehicles", []), int(w.get("crew", 0)))
		for e: Dictionary in run().oob:
			if String(e.id) in ids:
				e["start_men"] = int(e.men) + int(e.crew) * (e.vehicles as Array).size()
		waves[key] = {"ids": ids, "axis": int(axis.index), "at": clock(), "score": float(axis.score)}
		heavy = true
		var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
		if int(w.get("mortar", 0)) > 0 and sup:
			var aim := target
			for p: Variant in seen:
				aim = p if p is Vector3 else target  # (on what it has seen of the defence, else the objective)
				break
			sup.server_enemy_mortar(aim, int(w.mortar), "before the counterattack's wave %d" % (i + 1))
		SessionLog.note("operation %s: counterattack wave %d (%d groups) assembling at %s, axis %d of %d (score %.1f)" % [ops.cid, i + 1,
			ids.size(), grid_ref(v3([axis.pos.x, axis.pos.y])), int(axis.index) + 1, int(cfg(section).get("axes", 3)), float(axis.score)])
		say("Citadel: the enemy is coming back. Wave %d on its way to %s." % [i + 1, grid_ref(target)])
	for key: String in waves:
		if key.begins_with("%d:" % k):
			send_waves(waves[key].ids, target)


## Host: whether phase `k`'s counterattack in `section` is all out and beaten (each wave down to
## "beaten_share" of its men).
func counter_beaten(section: String, k: int) -> bool:
	var plan: Array = cfg(section).get("counter", [])
	var waves: Dictionary = mine().get("waves", {})
	var share := float(cfg(section).get("beaten_share", 0.25))
	for i in plan.size():
		var key := "%d:%d" % [k, i]
		if not waves.has(key):
			return false
		var ids: Array = waves[key].ids
		if wave_up(ids) > ceili(wave_start(ids) * share):
			return false
	return true


## Host: the operation stalls (Operations.server_stall: its save and broadcast are Operations'
## cost, not the tick's).
func stall(why: String) -> void:
	heavy = true
	if ops:
		ops.server_stall(why)


## Host: ours (the company, the allies, players) standing within `radius` of `pos`.
func ours_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction in [&"friendly", &"player"] and not s.is_queued_for_deletion() and s.vitals.is_up() and not Person.is_person(s) \
				and Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() <= radius:
			n += 1
	return n


## Host (6.4.5's "as defend_hold"): the enemy holds `pos` (one of theirs within `radius`, none of
## ours) for `hold_s` in all, counted by `key` over ticks of `dt`. True once it has.
func held_by_enemy(key: String, pos: Vector3, radius: float, dt: float, hold_s: float) -> bool:
	var m := mine()
	var held: Dictionary = m.get("enemy_held", {})
	m["enemy_held"] = held
	if ops._hostiles_near(pos, radius, "") > 0 and ours_near(pos, radius) == 0:
		held[key] = float(held.get(key, 0.0)) + dt
	else:
		held[key] = 0.0
	return float(held[key]) >= hold_s


func wave_start(ids: Array) -> int:
	var n := 0
	for e: Dictionary in run().get("oob", []):
		if String(e.id) in ids:
			n += int(e.get("start_men", int(e.men) + int(e.crew) * (e.vehicles as Array).size()))
	return n


## Host (doc 6.4.5): the axis the enemy comes in by, from its picture: `n` candidate assembly
## points `dist_m` out from `centre` round the bearing `from_dir` (its side), spread `spread_deg`;
## each scored by what it knows lies across that approach (`seen`: points of the defence it has seen,
## and its picture's contacts within the approach's cone), the clearest chosen. Returns the
## assembly point (x, z) on ground it holds, else the bearing's own.
func pick_axis(centre: Vector3, from_dir: Vector2, seen: Array, n := 3, dist_m := 900.0, spread_deg := 50.0, cone_deg := 35.0) -> Dictionary:
	var pic: SidePicture = ops.hostile.picture() if ops and ops.hostile and is_instance_valid(ops.hostile) else null
	var c2 := Vector2(centre.x, centre.z)
	var half := float(ops.def.get("size_m", 8192.0)) * 0.5 - 250.0 if ops else 3800.0
	var best := {}
	for k in n:
		var ang := deg_to_rad(spread_deg) * (float(k) - (n - 1) / 2.0)
		var dir := from_dir.normalized().rotated(ang)
		var at := (c2 + dir * dist_m).clamp(Vector2(-half, -half), Vector2(half, half))
		var score := 0.0
		for p: Variant in seen:
			var q: Vector2 = p if p is Vector2 else Vector2((p as Vector3).x, (p as Vector3).z)
			var to := q - c2
			if to.length() < 1.0 or absf(rad_to_deg(dir.angle_to(to))) <= cone_deg:
				score += 1.0
		if pic:
			for e: Dictionary in pic.entries_near(Vector3(at.x, 0.0, at.y).lerp(centre, 0.5), dist_m * 0.6):
				var q := Vector2((e.pos as Vector3).x, (e.pos as Vector3).z) - c2
				if absf(rad_to_deg(dir.angle_to(q))) <= cone_deg:
					score += 0.5 * maxf(float(e.get("count", 1)), 1.0)
		if ops and ops.grid.owner_at(at) != FrontGrid.HOSTILE:
			score += 2.0  # (ground it doesn't hold: it would have to fight through to assemble)
		if best.is_empty() or score < float(best.score):
			best = {"pos": at, "score": score, "dir": dir, "index": k}
	return best
