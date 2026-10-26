class_name Intel
extends Node
## The intel layer of Contractor: Fallen (docs/survival_world.md section 10; calls 37, 45, 54, 95):
## a child of the Survival autoload ("Intel", the same path on every peer). It keeps what the
## players have been told and met in Survival.state()["intel"] and turns the world sim's events
## into what the players know:
## - rumours asked in the talk menu (server_ask: WorldSim.rumours_for, by topic): each told one a
##   journal entry and, when it names a place, a map mark ("told", with the teller); true,
##   half-true or a lie as the sim says, and the record never says which;
## - companions reporting what they noticed on the road (an hourly line from events_near);
## - the radio's broadcasts (FallenRadio, ticked from here);
## - the RPCs of the barter screen (TradeScreen) and the journal screen (JournalScreen).
## The section: {"met": {person id: {"day", "zone", "name", "asked": [topics]}}, "told": {person id:
## [event ids]}, "reported": last event id a companion reported, "seen_groups": {group id: {"zone",
## "t", "how"}}, "radio": FallenRadio's}.
## Journal entries are Survival's ({"day", "hour", "text"}) plus "kind" ("told", "radio", "report",
## "trade") and "by" (who told it).

const NODE_NAME := "Intel"
const KEY := "intel"
## Proposed: how often the host looks at the clock (real s); companions report at most once a
## world hour.
const TICK_S := 2.0
const REPORT_HOURS := 1.0
const JOURNAL_CAP := 200
## The talk menu's "Ask about..." topics: [id, label].
const TOPICS: Array = [["here", "What happened here?"], ["places", "Other places"], ["groups", "The groups out there"], ["enclave", "The enclave"]]
## Event kinds that are about groups (the "groups" topic) and about the enclave.
const GROUP_KINDS: Array[String] = ["fight", "raid", "trade", "settled", "formed", "split", "group_gone", "capture", "demand", "hunt", "rescue", "arrived", "death", "supply_taken", "convoy_ambushed"]
const ENCLAVE_KINDS: Array[String] = ["broadcast", "supply_drop", "evac", "convoy", "heli_down", "heli_recovered", "convoy_robbed"]

var _tick := 0.0


func _init() -> void:
	name = NODE_NAME


static func get_intel() -> Intel:
	return Survival.get_node_or_null(NodePath(NODE_NAME)) as Intel


## The intel section (made on first use).
static func section() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	var d: Dictionary = st[KEY]
	for k: String in ["met", "told", "seen_groups", "radio"]:
		if not d.get(k) is Dictionary:
			d[k] = {}
	if not d.has("reported"):
		d["reported"] = 0
	return d


static func now() -> float:
	return Survival.day() + Survival.hour() / 24.0


## Host: a journal entry (Survival's journal list), with its kind and teller.
static func journal(text: String, kind := "", by := "", extra := {}) -> Dictionary:
	var j: Array = Survival.state().get("journal", [])
	var e := {"day": Survival.day(), "hour": snappedf(Survival.hour(), 0.1), "text": text}
	if kind != "":
		e["kind"] = kind
	if by != "":
		e["by"] = by
	e.merge(extra, false)
	j.append(e)
	Survival.state()["journal"] = j.slice(-JOURNAL_CAP)
	return e


## Host: an event in the world's pool made here (a trade, a cheat): through WorldSim.mutate so a far
## step out on the worker keeps it; event_added is emitted. Returns the event.
static func server_event(zone_id: String, kind: String, gids: Array, text: String, place := "") -> Dictionary:
	var out := {}
	var fn := func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		out.clear()
		out.merge(m.event(zone_id, kind, gids, text, place), true)
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
		sim.event_added.emit(out)
	else:
		fn.call(WorldSim.section())
	return out


static func event_by_id(id: int) -> Dictionary:
	if id == 0:
		return {}
	for e: Dictionary in WorldSim.section().get("events", []):
		if int(e.id) == id:
			return e
	return {}


## Host: `rec` was met (talked to) here: the journal's People tab.
static func server_met(rec: Dictionary, topic := "") -> void:
	var met: Dictionary = section().met
	var pid := String(rec.get("id", ""))
	if pid == "":
		return
	var m: Dictionary = met.get(pid, {"asked": []})
	m["day"] = now()
	m["zone"] = String(Survival.state().get("zone", rec.get("zone", "")))
	m["name"] = String(rec.get("name", "someone"))
	if topic != "" and not topic in (m.asked as Array):
		(m.asked as Array).append(topic)
	met[pid] = m


# --- Rumours (section 10, call 54) ---------------------------------------------------------------

## The rumours `pid` can tell on `topic` (TOPICS) not told yet. `here` is the zone the talk is in.
static func rumours_on(pid: String, topic: String, here: String) -> Array:
	var told: Array = (section().told as Dictionary).get(pid, [])
	var fresh: Array = []
	for r: Dictionary in WorldSim.rumours_for(pid, 20):
		var key := int(r.event) if int(r.event) != 0 else -1
		if key in told:
			continue
		if _on_topic(r, topic, here):
			fresh.append(r)
	return fresh


static func _on_topic(r: Dictionary, topic: String, here: String) -> bool:
	var kind := String(r.get("kind", ""))
	var e := event_by_id(int(r.get("event", 0)))
	match topic:
		"here":
			return String(r.zone) == here and here != ""
		"places":
			return String(r.zone) != here or kind == "outside"
		"groups":
			return kind in GROUP_KINDS
		"enclave":
			if kind in ENCLAVE_KINDS:
				return true
			for gid: String in e.get("groups", []):
				if String(WorldSim.group(gid).get("kind", "")) == "enclave":
					return true
			return false
	return true


## Host: `rec` is asked about `topic` (TOPICS) in zone `here`: the first untold rumour on it is
## told (record_rumour); {"text": what they say ("" nothing), "rumour": the rumour or {}}.
static func server_ask(rec: Dictionary, topic: String, here: String) -> Dictionary:
	server_met(rec, "ask_" + topic)
	var pid := String(rec.get("id", ""))
	var list := rumours_on(pid, topic, here)
	if list.is_empty():
		if topic == "enclave":
			var st := WorldSim.goal_state()
			var told: Array = (section().told as Dictionary).get(pid, [])
			if bool(st.get("evac", false)) and String(st.get("evac_zone", "")) != "" and not -2 in told:
				var r := {"text": "They say the enclave flies people out from %s. For a price." % RegionMap.zone_name(String(st.evac_zone)),
					"truth": "true", "event": 0, "zone": String(st.evac_zone), "kind": "enclave"}
				record_rumour(r, rec, -2)
				return {"text": String(r.text), "rumour": r}
		return {"text": "", "rumour": {}}
	var r: Dictionary = list[0]
	record_rumour(r, rec)
	return {"text": String(r.text), "rumour": r}


## Host: a rumour `r` told by `rec`: a journal entry ("told", by the teller) and, when it names a
## zone on the map, the zone known ("told") and a mark there (kind "told", the teller) at the
## event's place. The truth isn't kept on either (the players don't know which it was). Returns
## {"journal", "mark"}.
static func record_rumour(r: Dictionary, rec: Dictionary, key := 0) -> Dictionary:
	var pid := String(rec.get("id", ""))
	var teller := String(rec.get("name", "someone"))
	var told: Dictionary = section().told
	if not told.get(pid) is Array:
		told[pid] = []
	if key == 0:
		key = int(r.get("event", 0)) if int(r.get("event", 0)) != 0 else -1
	(told[pid] as Array).append(key)
	var j := journal("%s told me: %s" % [teller, String(r.text)], "told", teller, {"event": int(r.get("event", 0))})
	var mark := {}
	var zone := String(r.get("zone", ""))
	if zone != "" and RegionMap.layout().has(zone):
		SurvivalMap.server_know(zone, "told")
		mark = SurvivalMap.server_add_mark(zone, place_pos(zone, int(r.get("event", 0))), _short(String(r.text)), "told")
		mark["teller"] = teller
		_server_map_changed()
	var e := event_by_id(int(r.get("event", 0)))
	for gid: String in e.get("groups", []):
		if gid != "player":
			(section().seen_groups as Dictionary)[gid] = {"zone": String(e.zone), "t": float(e.get("t", e.day)), "how": "told"}
	return {"journal": j, "mark": mark}


## Where on its zone an event happened (its place, else the zone's middle), [x, z].
static func place_pos(zone_id: String, event_id: int) -> Array:
	var e := event_by_id(event_id)
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone_id, {})
	if not e.is_empty() and String(e.get("place", "")) != "":
		var p: Dictionary = WorldRegions.place(zd, String(e.place))
		if not p.is_empty():
			return [float(p.pos[0]), float(p.pos[1])]
	return [0.0, 0.0]


static func _short(text: String) -> String:
	var t := text.strip_edges()
	return t if t.length() <= 72 else t.left(69) + "..."


static func _server_map_changed() -> void:
	var level := CompoundLevel.current(Survival)
	var node: SurvivalMap = SurvivalMap.of(level) if level else null
	if node:
		node.server_changed()


# --- Companions on the road ----------------------------------------------------------------------

## Host: once a world hour, a companion with the players tells the newest event near them nobody
## reported yet (a journal line, "report", and said aloud when they have a body). Returns the line.
static func server_report_tick(level: Node = null) -> String:
	var d := section()
	if now() - float(d.get("report_t", -100.0)) < REPORT_HOURS / 24.0:
		return ""
	var who: Dictionary = {}
	for rec: Dictionary in WorldSim.people().values():
		if String(rec.get("status", "")) == "companion":
			who = rec
			break
	if who.is_empty():
		return ""
	var last := int(d.get("reported", 0))
	var best: Dictionary = {}
	for e: Dictionary in WorldSim.events_near(maxi(0, Survival.day() - 1)):
		if int(e.id) > last and String(e.kind) in WorldSim.JOURNAL_KINDS and not "player" in (e.groups as Array):
			best = e
	if best.is_empty():
		return ""
	d["reported"] = int(best.id)
	d["report_t"] = now()
	var line := "On the road I noticed: %s." % String(best.text)
	journal("%s: %s" % [String(who.get("name", "A companion")), line], "report", String(who.get("name", "")))
	var layer: SurvivorsLayer = SurvivorsLayer.find(level) if level else null
	var body: Soldier = layer.body_of(String(who.id)) if layer else null
	if body:
		layer.say(body, line)
	return line


# --- The host's clock ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not Survival.running or not multiplayer.is_server():
		return
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = 0.0
	var level := CompoundLevel.current(self)
	if not level is SurvivalLevel:
		return
	server_report_tick(level)
	FallenRadio.server_tick(level)


# --- Trade (TradeScreen <-> host) ----------------------------------------------------------------

## Host: show `actor`'s owner the barter screen with `deal` (Barter.deal).
func server_send_deal(actor: Soldier, deal: Dictionary) -> void:
	var peer := actor.owner_peer()
	if peer == multiplayer.get_unique_id():
		_client_deal(deal)
	elif peer in multiplayer.get_peers():
		_client_deal.rpc_id(peer, deal)


@rpc("authority", "call_remote", "reliable")
func _client_deal(deal: Dictionary) -> void:
	var ts := TradeScreen.current()
	if ts:
		ts.open(deal)


## Any peer: swap `give` ({item id: n} of yours) for `take` ({item id: n} of theirs) with `trader`.
func request_trade(trader: String, give: Dictionary, take: Dictionary) -> void:
	if multiplayer.is_server():
		_server_trade(trader, give, take, multiplayer.get_unique_id())
	else:
		_rpc_trade.rpc_id(1, trader, give, take)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade(trader: String, give: Dictionary, take: Dictionary) -> void:
	if multiplayer.is_server():
		_server_trade(trader, give, take, multiplayer.get_remote_sender_id())


func _server_trade(trader: String, give: Dictionary, take: Dictionary, peer: int) -> void:
	var level := CompoundLevel.current(self)
	var actor: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	var rec: Dictionary = WorldSim.people().get(trader, {})
	if actor == null or rec.is_empty():
		return
	var result := Barter.server_trade(actor, rec, give, take)
	var deal := Barter.deal(actor, rec)
	deal["result"] = String(result.get("why", ""))
	deal["said"] = String(result.get("said", ""))
	server_send_deal(actor, deal)


# --- The journal and the radio (any peer -> host) -------------------------------------------------

## Any peer: the journal's view (JournalScreen.view) for this peer.
func request_journal() -> void:
	if multiplayer.is_server():
		_client_journal(JournalScreen.view())
	else:
		_rpc_journal.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_journal() -> void:
	if multiplayer.is_server():
		_client_journal.rpc_id(multiplayer.get_remote_sender_id(), JournalScreen.view())


@rpc("authority", "call_remote", "reliable")
func _client_journal(view: Dictionary) -> void:
	var js := JournalScreen.current()
	if js:
		js.show_view(view)


## Any peer: the radio: "repair", "on" or "off" (FallenRadio), answered as a message.
func request_radio(action: String) -> void:
	if multiplayer.is_server():
		_server_radio(action, multiplayer.get_unique_id())
	else:
		_rpc_radio.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_radio(action: String) -> void:
	if multiplayer.is_server():
		_server_radio(action, multiplayer.get_remote_sender_id())


func _server_radio(action: String, peer: int) -> void:
	var level := CompoundLevel.current(self)
	var actor: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	if actor == null:
		return
	var why := ""
	match action:
		"repair":
			why = FallenRadio.server_repair(actor)
			if why == "":
				why = "The radio works again."
		"on", "off":
			why = FallenRadio.server_set_on(actor, action == "on")
			if why == "":
				why = "Radio %s." % action
	Survival._tell(actor, why)
	if peer == multiplayer.get_unique_id():
		_client_journal(JournalScreen.view())
	else:
		_client_journal.rpc_id(peer, JournalScreen.view())


## Any peer: "Write a letter" (the journal screen; Letters, call 130): `text` kept on his survivor.
func request_letter(text: String) -> void:
	if multiplayer.is_server():
		_server_letter(text, multiplayer.get_unique_id())
	else:
		_rpc_letter.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_letter(text: String) -> void:
	if multiplayer.is_server():
		_server_letter(text, multiplayer.get_remote_sender_id())


func _server_letter(text: String, peer: int) -> void:
	var level := CompoundLevel.current(self)
	var actor: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	if actor == null:
		return
	var why := Letters.server_write(actor, text.substr(0, Letters.MAX_CHARS))
	if why != "":
		Survival._tell(actor, why)
	if peer == multiplayer.get_unique_id():
		_client_journal(JournalScreen.view())
	else:
		_client_journal.rpc_id(peer, JournalScreen.view())
