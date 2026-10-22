class_name RequestBroker
extends Node
## Requests between players and friendly units (docs/combined_arms.md 4.1-4.3; phase B4, the
## skeleton that doesn't need B2). The rule: a friendly unit answers the way a real unit would,
## yes with an ETA or no with the reason, and does what it said; nothing happens silently.
##
## A request: {"id", "kind" (data/requests.json kinds), "by" (peer), "by_name", "from_pos",
##  "target": {"pos", "ref", "radius"}, "to" (a group named, or ""), "group" (who answers),
##  "callsign", "state" (STATES), "eta_s", "why", "counter" ({"eta_s"} or {}), "at", "answer_at",
##  "until", "merged", "text"}.
## - Ask: server_request(). Three open per player; the same kind at the same spot merges; a
##   group that declined a kind won't be asked it again for decline_cooldown_s unless its sitrep
##   changed (it moved, got ammo).
## - The answerer: the group named, else every friendly group on the side's board (SideIntel's
##   GroupBoard: not the company) with the capability, a radio (or within shout_m of the asker),
##   nearest by ETA first.
## - Its answer comes after its radio delay (answer_s, slower in contact): accepted with an ETA,
##   declined with the reason (decide()), or a counter-offer when the ETA is long (the player
##   accepts or cancels it). `can_spare` is B2's SideCommand.can_spare (4.2.10); until then every
##   group may be spared.
## - Then en_route, on_station and done as the job goes. The job is B2's: `executor` (SideCommand)
##   gets each accepted request and moves its group through server_progress(); a job with a duty
##   (suppress 60 s) is done when the duty runs out. A sitrep is answered at once from the board
##   and the side's picture.
## - Allied groups ask players back (4.3): contact support (in contact, AMBER or worse, a player
##   within 600 m, nobody else near to help) and ammo (red on ammo, a player within 300 m). One card
##   a player at a time, asks_answer_s to answer; accepting counts toward his cooperation; the ask
##   is done when the group is out of trouble.
## Every line goes out on the coordination net (Callouts, every player on the side) and RadioVoice
## plays its clips. Records replicate to every peer (RequestCards draws a player's own). One node,
## "RequestBroker", in every level (MapNodes.install); host authoritative. Numbers Proposed.

signal changed

const NODE_NAME := "RequestBroker"
const PATH := "res://data/requests.json"
const STATES: Array[String] = ["sent", "acked", "declined", "countered", "en_route", "on_station", "done", "cancelled", "failed"]
const OPEN: Array[String] = ["sent", "acked", "countered", "en_route", "on_station"]
const ASK_STATES: Array[String] = ["asked", "accepted", "declined", "expired", "done"]
const TICK_S := 0.5
const ASK_SCAN_S := 5.0

static var _data := {}

## Every peer: the requests (and asks: "ask": true) by id.
var requests := {}
## Host: B2's SideCommand.can_spare(row, request) -> {"ok": bool, "why", "delay_s"}; unset: yes.
var can_spare := Callable()
## Host: B2's executor, given each accepted request (it orders the group and calls server_progress);
## it returns false for a group it doesn't command, which the broker then runs itself (_direct).
var executor := Callable()
## Host: jobs the broker runs itself on groups no commander has: request id -> {"kind", "squad",
## "lead", "phase", "until", "who"}.
var direct := {}
## Host: answered asks per peer (4.3: what the employer's reputation and the bonus count).
var cooperation := {}
## Host: the lines said on the net, oldest first: {"callsign", "text", "at"} (tests).
var lines: Array[Dictionary] = []
var _next_id := 1
var _offset := 0.0
var _tick := 0.0
var _ask_scan := 0.0
var _declined := {}   # "group|kind|peer" -> {"at", "sitrep_at"}
var _asked := {}      # "group|kind" -> when last asked
var _callsigns := {}  # group id -> callsign
var _numbers := {}    # callsign base -> how many given


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)


static func of(from: Node) -> RequestBroker:
	var lvl := MapNodes.level_of(from)
	return lvl.get_node_or_null(NODE_NAME) as RequestBroker if lvl else null


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"_missing": true}
	return _data


static func num(key: String, fallback := 0.0) -> float:
	return float(data().get(key, fallback))


static func spec(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


func now() -> float:
	return Soldier._now() + _offset


## Tests: moves the broker's clock on and runs its tick.
func advance(seconds: float) -> void:
	_offset += seconds
	server_tick()


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()


# --- Asking ---------------------------------------------------------------------------------------

## Host: peer `by` (standing at `from_pos`) asks for `kind` at `target_pos` (`to`: a group id he
## named, "" for the nearest that can; `ref`: what he looked at). Returns the request (a merge
## returns the one already open), or {"why"} when it can't be asked.
func server_request(by: int, kind: String, target_pos: Vector3, from_pos: Vector3, to := "", ref := "") -> Dictionary:
	if not multiplayer.is_server():
		return {"why": "Not the host"}
	var sp := spec(kind)
	if sp.is_empty():
		return {"why": "No such request"}
	if bool(sp.get("named_only", false)) and to == "":
		return {"why": "Look at a unit to ask it for %s" % sp.get("label", kind)}
	if kind == "check_fire":  # every friendly gun into 100 m of it stops for 30 s (4.5): no answerer
		Deconfliction.server_check_fire(target_pos, &"friendly", _peer_name(by))
		_say("Citadel", "All stations, check fire, check fire at %s." % _grid(target_pos))
		var cf := {"id": _next_id, "kind": kind, "by": by, "by_name": _peer_name(by), "from_pos": from_pos, "target": {"pos": target_pos, "ref": ref, "radius": 100.0},
			"to": "", "group": "", "callsign": "Citadel", "state": "done", "eta_s": 0.0, "why": "", "counter": {}, "at": now(), "answer_at": now(),
			"until": now() + Deconfliction.CHECK_FIRE_S, "merged": 0, "text": ""}
		_next_id += 1
		requests[cf.id] = cf
		_send()
		return cf
	var open := 0
	for r: Dictionary in requests.values():
		if r.get("ask", false) or int(r.by) != by or not (String(r.state) in OPEN):
			continue
		if String(r.kind) == kind and (r.target.pos as Vector3).distance_to(target_pos) <= num("merge_m", 30.0) and (to == "" or String(r.to) == to):
			r.merged = int(r.get("merged", 0)) + 1
			return r
		open += 1
	if open >= int(num("open_per_player", 3)):
		return {"why": "Three requests open: cancel one first"}
	var r := {"id": _next_id, "kind": kind, "by": by, "by_name": _peer_name(by), "from_pos": from_pos,
		"target": {"pos": target_pos, "ref": ref, "radius": 0.0}, "to": to, "group": "", "callsign": "", "state": "sent",
		"eta_s": -1.0, "why": "", "counter": {}, "at": now(), "answer_at": INF, "until": now() + num("until_s", 600.0), "merged": 0, "text": ""}
	_next_id += 1
	var pick := _pick(r)
	if pick.is_empty():
		r.answer_at = now() + float((data().get("answer_s", [2.0, 6.0]) as Array)[0])
		r["nobody"] = true
	else:
		r.group = String(pick.id)
		r.callsign = callsign_of(pick)
		r.answer_at = now() + _answer_delay(pick)
	requests[r.id] = r
	_send()
	return r


## Host: peer `by` cancels request `id` ("cancel", or right-click the card).
func server_cancel(by: int, id: int) -> bool:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or int(r.get("by", -1)) != by or not (String(r.state) in OPEN):
		return false
	_set_state(r, "cancelled", "Cancelled")
	if r.callsign != "":
		_say(r.callsign, "%s, copy, cancelling. Out." % r.callsign)
	return true


## Host: peer `by` takes a counter-offer (one key on the card).
func server_accept_counter(by: int, id: int) -> bool:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or int(r.by) != by or r.state != "countered":
		return false
	r.eta_s = float(r.counter.get("eta_s", r.eta_s))
	_accept(r)
	return true


## Host (B2's executor): request `id` moves on: "en_route", "on_station", "done" or "failed"
## (`why` says what happened: "Iron 2: lost the target").
func server_progress(id: int, state: String, why := "") -> bool:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or not (String(r.state) in OPEN) or not (state in ["en_route", "on_station", "done", "failed"]):
		return false
	if state == "on_station":
		var duty := float(spec(r.kind).get("duty_s", 0.0))
		if duty > 0.0:
			r.until = now() + duty
	_set_state(r, state, why)
	if state == "failed" and why != "":
		_say(String(r.callsign), why)
	return true


# --- Picking and answering -------------------------------------------------------------------------

## The group that should answer `r`: the one named, else the nearest by ETA with the capability
## and a way to hear it (a radio, or within shout_m of the asker). {} for none.
func _pick(r: Dictionary) -> Dictionary:
	var board := _board()
	if board == null:
		return {}
	var best: Dictionary = {}
	var best_eta := INF
	for row: Dictionary in board.rows.values():
		if row.kind == "company" or (r.to != "" and String(row.id) != r.to):
			continue
		if r.to == "" and not capable(row, String(r.kind)):
			continue
		if _cooling(row, r):
			continue
		if not _hears(row, r.from_pos):
			continue
		var eta := eta_of(row, r)
		if eta < best_eta:
			best = row
			best_eta = eta
	return best


## Whether board row `row` has what request `kind` needs (data "who": any of them).
static func capable(row: Dictionary, kind: String) -> bool:
	for need: String in spec(kind).get("who", []):
		match need:
			"any":
				return true
			"mgs", "medics", "smoke", "launchers":
				if int(row.get(need, 0)) > 0:
					return true
			"ifv", "mbt", "light_armour", "soft_vehicle":
				if (row.get("vehicle_kinds", []) as Array).has(need):
					return true
			_:
				if String(row.get("kind", "")) == need:
					return true
	return false


## Seconds until `row` can do `r`: a few if it's already in place, else its move (mounted if it
## has vehicles).
static func eta_of(row: Dictionary, r: Dictionary) -> float:
	var sp := spec(String(r.kind))
	var at: Vector3 = row.get("pos", Vector3.INF)
	if not at.is_finite():
		return INF
	var d := Vector2(at.x - r.target.pos.x, at.z - r.target.pos.z).length()
	if d <= float(sp.get("in_place_m", 0.0)):
		return num("in_place_s", 8.0)
	var mps := num("mounted_mps", 8.0) if not (row.get("mounted_in", []) as Array).is_empty() else num("foot_mps", 1.8)
	return d / mps


## What `row` answers to `r` (4.2's refusals, in the order a unit would give them):
## {"state": "acked" | "declined" | "countered", "why", "eta_s", "counter"}. `spare`: B2's
## can_spare answer ({} when there's no commander yet).
static func decide(row: Dictionary, r: Dictionary, spare := {}) -> Dictionary:
	var kind := String(r.kind)
	var sp := spec(kind)
	var at: Vector3 = row.get("pos", Vector3.INF)
	var d := Vector2(at.x - r.target.pos.x, at.z - r.target.pos.z).length() if at.is_finite() else INF
	if String(row.get("role", "")) == "assault":
		return {"state": "declined", "why": "Committed to an assault"}
	if bool(row.get("in_contact", false)) and String(row.get("ce_band", "green")) == "red":
		return {"state": "declined", "why": "We're pinned"}
	if kind == "ammo" and String(row.get("ammo_band", "green")) != "green":
		return {"state": "declined", "why": "We're %s ourselves" % row.ammo_band}
	if bool(sp.get("ammo", false)) and String(row.get("ammo_band", "green")) == "red":
		return {"state": "declined", "why": "Ammo black"}
	if kind == "medic" and int(row.get("medics", 0)) <= 0:
		return {"state": "declined", "why": "No medic free"}
	if kind == "smoke" and int(row.get("smoke", 0)) <= 0 and row.get("kind") != "mortar_section":
		return {"state": "declined", "why": "No smoke left"}
	if not capable(row, kind):
		return {"state": "declined", "why": "We've nothing for that"}
	if d > float(sp.get("reach_m", INF)):
		return {"state": "declined", "why": "Out of range"}
	if not spare.is_empty() and not bool(spare.get("ok", true)):
		if float(spare.get("delay_s", 0.0)) > 0.0:
			var later := float(spare.delay_s) + eta_of(row, r)
			return {"state": "countered", "why": String(spare.get("why", "Our orders come first")), "eta_s": later, "counter": {"eta_s": later}}
		return {"state": "declined", "why": String(spare.get("why", "Committed"))}
	var eta := eta_of(row, r)
	if eta > num("counter_eta_s", 120.0):
		return {"state": "countered", "why": "We can be there in %s" % _time_words(eta), "eta_s": eta, "counter": {"eta_s": eta}}
	return {"state": "acked", "why": "", "eta_s": eta, "counter": {}}


func _answer(r: Dictionary) -> void:
	if r.get("nobody", false):
		_set_state(r, "declined", "No unit can give %s" % spec(r.kind).get("label", r.kind))
		_say("Citadel", "Citadel, unable, no unit can give %s there." % spec(r.kind).get("label", r.kind))
		return
	var board := _board()
	var row: Dictionary = board.rows.get(r.group, {}) if board else {}
	if row.is_empty():
		_set_state(r, "failed", "No answer")
		return
	if r.kind == "sitrep":
		r.text = sitrep(row)
		_set_state(r, "done", "")
		_say(r.callsign, r.text)
		return
	var spare: Dictionary = can_spare.call(row, r) if can_spare.is_valid() else {}
	var a := decide(row, r, spare)
	r.eta_s = float(a.get("eta_s", -1.0))
	r.counter = a.get("counter", {})
	match String(a.state):
		"declined":
			_declined["%s|%s|%d" % [r.group, r.kind, int(r.by)]] = {"at": now(), "sitrep_at": float(row.sitrep_at)}
			_set_state(r, "declined", String(a.why))
			_say(r.callsign, "%s, unable. %s." % [r.callsign, a.why])
		"countered":
			_set_state(r, "countered", String(a.why))
			_say(r.callsign, "%s. %s, say if you want it." % [r.callsign, a.why])
		_:
			_accept(r)


func _accept(r: Dictionary) -> void:
	_set_state(r, "acked", "")
	var grid := _grid(r.target.pos)
	var eta := float(r.eta_s)
	_say(r.callsign, "%s, copy, %s at %s, %s." % [r.callsign, spec(r.kind).get("label", r.kind), grid,
		"on it now" if eta <= num("in_place_s", 8.0) else "on in " + _time_words(eta)])
	var handled := executor.is_valid() and bool(executor.call(r))
	if not handled and not _direct_start(r):
		_set_state(r, "failed", "Can't do that without our orders")
		_say(String(r.callsign), "%s, unable, we can't do that without our orders." % r.callsign)


# --- Jobs on groups no commander has (B4) --------------------------------------------------------

## Suppress, cover, hold, smoke, ammo and a medic on the squad's own orders, from its own leader;
## vehicle jobs (CASEVAC, armour, a pick-up) only a commander can give. False if it can't start.
func _direct_start(r: Dictionary) -> bool:
	var intel := SideIntel.of(self)
	var squad := intel.squad_of(String(r.group)) if intel else null
	var lead := _lead_of(squad)
	if lead == null or not (String(r.kind) in ["suppress", "cover", "hold", "smoke", "ammo", "medic"]):
		return false
	var job := {"kind": String(r.kind), "squad": squad, "phase": "", "until": now() + num("until_s", 600.0)}
	direct[int(r.id)] = job
	_direct_step(int(r.id), r, job)
	return true


static func _lead_of(squad: Squad) -> Soldier:
	if squad == null:
		return null
	if is_instance_valid(squad.leader) and squad.leader.is_ai() and squad.leader.vitals.is_up():
		return squad.leader
	for s: Soldier in squad.members():
		if s.vitals.is_up():
			return s
	return null


func _direct_tick() -> void:
	for rid: int in direct.keys():
		var r: Dictionary = requests.get(rid, {})
		if r.is_empty() or not (String(r.state) in OPEN):
			direct.erase(rid)
			continue
		_direct_step(rid, r, direct[rid])


func _direct_step(rid: int, r: Dictionary, job: Dictionary) -> void:
	var squad := job.squad as Squad
	var lead := _lead_of(squad)
	if lead == null:
		server_progress(rid, "failed", "%s: nobody left to do it" % r.callsign)
		return
	var tp: Vector3 = r.target.pos
	var reach := float(spec(String(r.kind)).get("in_place_m", 0.0))
	match String(r.kind):
		"suppress", "cover", "smoke":
			if lead.global_position.distance_to(tp) > reach + 5.0:
				if job.phase != "moving":  # into range first
					job.phase = "moving"
					var dir := (tp - lead.global_position)
					dir.y = 0.0
					squad.give_order(lead, Squad.Order.MOVE, tp - dir.normalized() * reach * 0.8)
					server_progress(rid, "en_route")
				return
			if job.phase == "firing":
				return
			job.phase = "firing"
			var why := ""
			if r.kind == "smoke":
				why = "No smoke left"
				for id: StringName in GroupBoard.SMOKE_ITEMS:
					if squad.order_throw(lead, id, tp) != "":
						why = ""
						break
			else:
				why = squad.order_suppress(lead, tp)
			if why != "":
				server_progress(rid, "failed", "%s: %s" % [r.callsign, why])
			else:
				server_progress(rid, "on_station")
				_say(String(r.callsign), "%s, %s." % [r.callsign, "smoke out" if r.kind == "smoke" else "suppressing"])
		"hold":
			squad.give_order(lead, Squad.Order.HOLD, lead.global_position)
			server_progress(rid, "done")
		"ammo":
			var me := _player_of(int(r.by))
			if job.phase == "":
				job.phase = "bringing"
				var why := squad.order_give_ammo(me, PackedStringArray()) if me else "No one to bring it to"
				if why != "":
					server_progress(rid, "failed", "%s: %s" % [r.callsign, why])
					return
				server_progress(rid, "en_route")
				_say(String(r.callsign), "%s, ammo coming." % r.callsign)
				job.until = now() + 90.0
			elif now() >= float(job.until):
				server_progress(rid, "done")
		"medic":
			var who := _casualty_near(tp)
			if job.phase == "":
				if who == null:
					server_progress(rid, "failed", "%s: nobody hurt there" % r.callsign)
					return
				job.phase = "treating"
				job.who = who
				var why := squad.order_treat(lead, String(who.name), PackedStringArray())
				if why != "":
					server_progress(rid, "failed", "%s: %s" % [r.callsign, why])
					return
				server_progress(rid, "en_route")
				_say(String(r.callsign), "%s, medic moving to you." % r.callsign)
			elif not is_instance_valid(job.who) or not SquadAI.needs_help(job.who):
				server_progress(rid, "done")


## The friendly casualty (down, or needing help) nearest `at`, within 15 m.
func _casualty_near(at: Vector3) -> Soldier:
	var best: Soldier = null
	var best_d := 15.0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction in Deconfliction.FRIENDLY and not s.vitals.is_dead() and SquadAI.needs_help(s) and s.global_position.distance_to(at) < best_d:
			best_d = s.global_position.distance_to(at)
			best = s
	return best


## A group's sitrep line (4.2.9): "Saber 2: green, 7 up, ammo good, holding at 041 053, two enemy
## 200 m north."
func sitrep(row: Dictionary) -> String:
	var at: Vector3 = row.pos
	var parts: Array[String] = ["%s: %s, %d up, ammo %s" % [callsign_of(row), row.ce_band, int(row.up),
		{"green": "good", "amber": "low", "red": "black"}.get(String(row.ammo_band), "good")]]
	parts.append(("in contact at %s" if bool(row.get("in_contact", false)) else "holding at %s") % _grid(at))
	var picture := SideIntel.picture_of(self, &"friendly")
	if picture:
		var near: Dictionary = {}
		var best := 600.0
		for e: Dictionary in picture.entries:
			var d := Vector2(e.pos.x - at.x, e.pos.z - at.z).length()
			if d < best:
				best = d
				near = e
		if not near.is_empty():
			parts.append("%d enemy %s metres %s" % [int(near.count), Callouts.round_distance(best),
				RadioChatter.compass(at, near.pos)])
	return ", ".join(parts) + "."


# --- Allies asking players (4.3) ------------------------------------------------------------------

func _scan_asks() -> void:
	var board := _board()
	if board == null:
		return
	var asks: Dictionary = data().get("asks", {})
	var players := MapNodes.players(self)
	for row: Dictionary in board.rows.values():
		if row.kind == "company":
			continue
		var at: Vector3 = row.pos
		if not at.is_finite():
			continue
		if bool(row.get("in_contact", false)) and String(row.ce_band) != "green" and not _helper_near(board, row, float(asks.get("contact_support_m", 600.0))):
			_raise(row, "ask_support", players, float(asks.get("contact_support_m", 600.0)),
				"Any station, %s, contact, need support at %s." % [callsign_of(row), _grid(at)])
		elif String(row.ammo_band) == "red":
			_raise(row, "ask_ammo", players, float(asks.get("ammo_m", 300.0)), "%s, black on ammo, anyone close?" % callsign_of(row))


## Another friendly group near `row` that isn't in contact itself could help instead.
func _helper_near(board: GroupBoard, row: Dictionary, reach: float) -> bool:
	for other: Dictionary in board.rows.values():
		if other.id == row.id or other.kind == "company" or bool(other.get("in_contact", false)):
			continue
		if (other.pos as Vector3).is_finite() and (other.pos as Vector3).distance_to(row.pos) <= reach:
			return true
	return false


func _raise(row: Dictionary, kind: String, players: Array[Soldier], reach: float, text: String) -> void:
	var key := "%s|%s" % [row.id, kind]
	if now() - float(_asked.get(key, -INF)) < float((data().get("asks", {}) as Dictionary).get("again_s", 300.0)):
		return
	var nearest: Soldier = null
	var best := reach
	for p: Soldier in players:
		if p.vitals.is_up() and p.global_position.distance_to(row.pos) <= best:
			best = p.global_position.distance_to(row.pos)
			nearest = p
	if nearest == null:
		return
	_asked[key] = now()
	var peer := nearest.owner_peer()
	var ask := {"id": _next_id, "ask": true, "kind": kind, "group": String(row.id), "callsign": callsign_of(row), "to_peer": peer,
		"pos": row.pos, "state": "asked", "text": text, "at": now(), "until": INF, "why": ""}
	_next_id += 1
	requests[ask.id] = ask
	_say(ask.callsign, text)
	_queue_cards()


## Host (SideCommand, B3): group `group` asks the nearest player within contact_support_m of
## `at` for `kind` ("ask_clear_at": an AT team its armour can't hit), saying `text`.
func server_ask_players(group: String, kind: String, at: Vector3, text: String) -> void:
	var board := _board()
	var row: Dictionary = board.rows.get(group, {}) if board else {}
	if row.is_empty():
		row = {"id": group, "pos": at, "kind": "armour_section"}
	_raise(row, kind, MapNodes.players(self), float((data().get("asks", {}) as Dictionary).get("contact_support_m", 600.0)), text)


## One card a player at a time: the oldest ask waiting gets its 30 s once nothing else is up.
func _queue_cards() -> void:
	var showing := {}
	for r: Dictionary in requests.values():
		if r.get("ask", false) and r.state == "asked" and float(r.until) < INF:
			showing[int(r.to_peer)] = true
	var ids := requests.keys()
	ids.sort()
	for id: int in ids:
		var r: Dictionary = requests[id]
		if r.get("ask", false) and r.state == "asked" and float(r.until) == INF and not showing.has(int(r.to_peer)):
			r.until = now() + float((data().get("asks", {}) as Dictionary).get("answer_s", 30.0))
			showing[int(r.to_peer)] = true
	_send()


## Host: peer `by` answers ask `id` (Y / N on the card).
func server_answer_ask(by: int, id: int, yes: bool) -> bool:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or not r.get("ask", false) or int(r.to_peer) != by or r.state != "asked" or float(r.until) == INF:
		return false
	r.state = "accepted" if yes else "declined"
	if yes:
		var asks: Dictionary = data().get("asks", {})
		cooperation[by] = mini(int(cooperation.get(by, 0)) + int(asks.get("rep_per_answer", 1)), int(asks.get("rep_max_per_operation", 5)))
		_say(String(r.callsign), "%s, copy, waiting on you." % r.callsign)
	_queue_cards()
	return true


## An AT-team ask is done once the side has no AT team reported within 400 m of the armour.
func _at_cleared(r: Dictionary) -> bool:
	var pic := SideIntel.picture_of(self, &"friendly")
	if pic == null:
		return true
	return not pic.entries_near(r.pos, 400.0).any(func(e: Dictionary) -> bool: return String(e.kind) == "at")


func _check_asks() -> void:
	var board := _board()
	for r: Dictionary in requests.values():
		if not r.get("ask", false):
			continue
		if r.state == "asked" and now() > float(r.until):
			r.state = "expired"
			_queue_cards()
		elif r.state == "accepted":
			var row: Dictionary = board.rows.get(r.group, {}) if board else {}
			var out_of_it: bool = row.is_empty() or (r.kind == "ask_support" and (not bool(row.get("in_contact", false)) or row.ce_band == "green")) \
				or (r.kind == "ask_ammo" and row.ammo_band != "red") or (r.kind == "ask_clear_at" and _at_cleared(r))
			if out_of_it:
				r.state = "done"
				_send()


# --- The tick, the net, replication ---------------------------------------------------------------

func server_tick() -> void:
	var t := now()
	for r: Dictionary in requests.values():
		if r.get("ask", false):
			continue
		if r.state == "sent" and t >= float(r.answer_at):
			_answer(r)
		elif String(r.state) in OPEN and t > float(r.until):
			if r.state == "on_station":
				_set_state(r, "done", "")
				_say(String(r.callsign), "%s, %s complete. Out." % [r.callsign, spec(r.kind).get("label", r.kind)])
			else:
				_set_state(r, "failed", "Timed out")
	_direct_tick()
	_ask_scan -= TICK_S
	if _ask_scan <= 0.0:
		_ask_scan = ASK_SCAN_S
		_scan_asks()
	_check_asks()


func _set_state(r: Dictionary, state: String, why: String) -> void:
	r.state = state
	r.why = why
	if state in ["en_route", "acked"] and float(r.eta_s) >= 0.0:
		r["eta_at"] = now() + float(r.eta_s)
	_send()


## The side's board (SideIntel's; B2's SideCommand later).
func _board() -> GroupBoard:
	var intel := SideIntel.of(self)
	return intel.board if intel else null


func _answer_delay(row: Dictionary) -> float:
	var band: Array = data().get("answer_s", [2.0, 6.0])
	var skill := clampf(float(row.get("ce", 0.6)), 0.0, 1.0)
	var d := lerpf(float(band[1]), float(band[0]), skill)
	return d * (num("answer_in_contact_mult", 1.5) if bool(row.get("in_contact", false)) else 1.0)


func _cooling(row: Dictionary, r: Dictionary) -> bool:
	var was: Dictionary = _declined.get("%s|%s|%d" % [row.id, r.kind, int(r.by)], {})
	return not was.is_empty() and now() - float(was.at) < num("decline_cooldown_s", 30.0) and float(was.sitrep_at) == float(row.sitrep_at)


## Whether `row` hears a request from `from`: its radio works, or it's within shouting distance.
func _hears(row: Dictionary, from: Vector3) -> bool:
	var intel := SideIntel.of(self)
	var squad := intel.squad_of(String(row.id)) if intel else null
	if squad == null or intel.radio_man(squad) != null:
		return true
	return (row.pos as Vector3).distance_to(from) <= num("shout_m", 80.0)


## A group's callsign on the net (4.6): its own if it has one, else its kind's and a number
## ("Saber 2"), kept for the deployment.
func callsign_of(row: Dictionary) -> String:
	var id := String(row.id)
	if String(row.get("callsign", id)) != id:
		return String(row.callsign)
	if not _callsigns.has(id):
		var base := String((data().get("callsigns", {}) as Dictionary).get(String(row.get("kind", "")), "Saber"))
		_numbers[base] = int(_numbers.get(base, 0)) + 1
		_callsigns[id] = "%s %d" % [base, int(_numbers[base])]
	return String(_callsigns[id])


func _grid(pos: Vector3) -> String:
	var lvl := MapNodes.level_of(self)
	return MapGrid.grid_ref_3d(pos, lvl.call(&"map_area")) if lvl else "%.0f %.0f" % [pos.x, pos.z]


static func _time_words(seconds: float) -> String:
	if seconds < 90.0:
		return "%d seconds" % (maxi(roundi(seconds / 10.0), 1) * 10)
	return "%d minutes" % roundi(seconds / 60.0)


func _peer_name(peer: int) -> String:
	for p: Soldier in MapNodes.players(self):
		if p.owner_peer() == peer:
			return p.display_name()
	return "Player %d" % peer


## A line on the coordination net: a subtitle for every player on the side, and its radio clips.
func _say(callsign: String, text: String) -> void:
	lines.append({"callsign": callsign, "text": text, "at": now()})
	if lines.size() > 64:
		lines.pop_front()
	var callouts := Callouts.of(self)
	if callouts == null or not multiplayer.has_multiplayer_peer():
		return
	for p: Soldier in MapNodes.players(self):
		var peer := p.owner_peer()
		if peer == multiplayer.get_unique_id() or peer in multiplayer.get_peers():
			callouts._show.rpc_id(peer, p.get_path(), callsign, "", text)
			_client_voice.rpc_id(peer, text)


@rpc("authority", "call_local", "reliable")
func _client_voice(text: String) -> void:
	RadioVoice.say(self, text)


## Host: every request to every peer (and here).
func _send() -> void:
	changed.emit()
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_client_requests.rpc(_wire())
	_trim()


## What goes to peers: open requests and the last few closed ones.
func _wire() -> Array:
	var out: Array = []
	for r: Dictionary in requests.values():
		out.append(r)
	return out


## Closed requests older than 2 minutes go (the cards have shown them).
func _trim() -> void:
	for id: int in requests.keys():
		var r: Dictionary = requests[id]
		var closed: bool = not (String(r.state) in OPEN) and r.state != "asked" and r.state != "accepted"
		if closed and now() - float(r.at) > 120.0 and now() - float(r.get("until", 0.0)) > 0.0:
			requests.erase(id)


@rpc("authority", "call_remote", "reliable")
func _client_requests(list: Array) -> void:
	requests.clear()
	for r: Dictionary in list:
		requests[int(r.id)] = r
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and not requests.is_empty():
		_client_requests.rpc_id(id, _wire())


# --- Requests from peers --------------------------------------------------------------------------

## Any peer: asks the host for `kind` at `target_pos` (see server_request).
func request(kind: String, target_pos: Vector3, to := "", ref := "") -> void:
	_server_request.rpc_id(1, kind, target_pos, to, ref)


func request_cancel(id: int) -> void:
	_server_cancel.rpc_id(1, id)


func request_accept_counter(id: int) -> void:
	_server_accept.rpc_id(1, id)


func request_answer_ask(id: int, yes: bool) -> void:
	_server_answer.rpc_id(1, id, yes)


@rpc("any_peer", "call_local", "reliable")
func _server_request(kind: String, target_pos: Vector3, to: String, ref: String) -> void:
	if not multiplayer.is_server() or not target_pos.is_finite():
		return
	var peer := _sender()
	var me := _player_of(peer)
	if me:
		server_request(peer, kind, target_pos, me.global_position, to, ref)


@rpc("any_peer", "call_local", "reliable")
func _server_cancel(id: int) -> void:
	if multiplayer.is_server():
		server_cancel(_sender(), id)


@rpc("any_peer", "call_local", "reliable")
func _server_accept(id: int) -> void:
	if multiplayer.is_server():
		server_accept_counter(_sender(), id)


@rpc("any_peer", "call_local", "reliable")
func _server_answer(id: int, yes: bool) -> void:
	if multiplayer.is_server():
		server_answer_ask(_sender(), id, yes)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _player_of(peer: int) -> Soldier:
	for p: Soldier in MapNodes.players(self):
		if p.owner_peer() == peer:
			return p
	return null
