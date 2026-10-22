class_name SideIntel
extends Node
## The friendly side's picture and group board, kept on the host, and what the players see of
## it (docs/combined_arms.md 3.2, 3.3 and 4.4, phase B1). B2's SideCommand takes these over; until
## then this node owns them. The hostile side's picture is EnemyCommand's (picture_of()).
##
## Feeds (host, every feed_s):
## - Each friendly group's Squad.clusters(): a report the first time a cluster is fresh and every
##   report_every_s while it stays fresh, one per vehicle seen and one for the men on foot (kind by
##   what they carry: SidePicture kinds). It goes over the group's radio after its delay
##   (SidePicture.delay_s by the reporting leader's skill), and dies with the radio man if he's
##   down before it's due. A group with no radio (none in its kit on a side without issued sets,
##   meta "no_radio", or its radio men down) holds its reports until one of its men is within
##   shout_m of another group or a player with a radio, who passes them on.
## - Players: tags (EnemyTags), "Report enemy position" (PeopleLayer.server_report), lookouts and
##   the UAV (EnemyTags.server_tag_reported) and lased targets (server_report_lase: A4 calls it).
## - Blue Force Tracker: the side's vehicles with a working radio at their true positions (grey
##   and frozen once it's out: meta "radio_down", A2's radio module), its groups by their sitrep.
## - Comms: server_set_comms() (a jammer, the operation HQ's relay): reports x3 slower.
## What players see: each entry as a "spot" marker on MapMarkers' intel channel (the map draws it,
## SpotDiamonds puts a diamond over it in the world), re-sent only when it changes; nothing else.
## One node, "SideIntel", in every level (install); host authoritative. Numbers Proposed.

const NODE_NAME := "SideIntel"
## Faction names counted as the friendly side's (vehicles and soldiers).
const FRIENDLY: Array[StringName] = [&"friendly", &"player", &"allied"]

var picture := SidePicture.new(&"friendly")
var board := GroupBoard.new(&"friendly")
var _feed := 0.0
var _offset := 0.0       # tests: advance()
var _sent := {}          # group id -> [{"pos", "kind", "at"}]: its last reports
var _held := {}          # group id -> [reports]: a group with no radio, waiting to pass them on
var _marker_of := {}     # entry id -> MapMarkers id
var _marker_rev := {}    # entry id -> the entry's rev last sent
var _synced := -1


static func install(level: Node) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	var n := SideIntel.new()
	n.name = NODE_NAME
	level.add_child(n)


static func of(from: Node) -> SideIntel:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as SideIntel if lvl else null


## A side's picture in the level `from` is in: "friendly" here, "hostile" EnemyCommand's (a hot
## zone's), null for none.
static func picture_of(from: Node, side: StringName) -> SidePicture:
	if side == &"hostile":
		var command := EnemyCommand.of(from)
		return command.picture if command else null
	var intel := of(from)
	return intel.picture if intel else null


func now() -> float:
	return Soldier._now() + _offset


## Tests: moves this side's clock `seconds` on and runs a feed.
func advance(seconds: float) -> void:
	_offset += seconds
	server_feed()


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_feed -= delta
	if _feed <= 0.0:
		_feed = SidePicture.num("feed_s", 1.0)
		server_feed()


## Host: one feed (see the header): reports from the groups, BFT, relays, the picture's step and
## the markers.
func server_feed() -> void:
	var t := now()
	var squads := GroupBoard.squads_of(get_tree(), &"friendly")
	board.refresh(squads, t, _board_meta(squads))
	for squad: Squad in squads:
		_report_clusters(squad, t)
	_relay_held(squads, t)
	_track(t)
	picture.step(t)
	_sync_markers(t)


## The company's groups aren't the commander's to task (3.4.4).
func _board_meta(squads: Array[Squad]) -> Dictionary:
	var lvl := CompoundLevel.current(self)
	var company := lvl.squad_for(&"friendly") if lvl else null
	var allied := AlliedTroops.current(self)
	var out := {}
	for squad: Squad in squads:
		if squad == company:
			out[GroupBoard.group_id(squad)] = {"taskable": false, "kind": "company", "callsign": "Company"}
		elif allied:
			for e: Variant in allied.elements:
				if e != null and (e as Dictionary).get("squad") == squad:
					out[GroupBoard.group_id(squad)] = {"taskable": false, "callsign": "Element %d" % int(e.id)}
	return out


# --- Reports from the groups ---------------------------------------------------------------------

func _report_clusters(squad: Squad, t: float) -> void:
	var id := GroupBoard.group_id(squad)
	var every := SidePicture.num("report_every_s", 30.0)
	var sent: Array = (_sent.get(id, []) as Array).filter(func(r: Dictionary) -> bool: return t - float(r.at) < every)
	for c: Dictionary in squad.clusters():
		if float(c.age) >= Squad.FRESH_S:
			continue
		for r: Dictionary in _cluster_reports(squad, c, t):
			var near := sent.any(func(s: Dictionary) -> bool:
				return s.kind == r.kind and SidePicture._flat(s.pos, r.pos) <= SidePicture.merge_m(String(r.kind)))
			if near:
				continue
			sent.append({"pos": r.pos, "kind": r.kind, "at": t})
			_send(squad, r, t)
	_sent[id] = sent


## A fresh cluster as reports: one per vehicle its men are in, one for the rest on foot.
func _cluster_reports(squad: Squad, c: Dictionary, t: float) -> Array[Dictionary]:
	var on_foot: Array[Soldier] = []
	var vehicles := {}
	var vel := Vector3.ZERO
	var heard := true
	for w: Variant in c.who:
		var s := w as Soldier
		if s == null or not is_instance_valid(s):
			continue
		var known: Dictionary = squad.known.get(s.get_instance_id(), {})
		vel += known.get("vel", Vector3.ZERO)
		heard = heard and bool(known.get("heard", false))
		if s.vehicle and is_instance_valid(s.vehicle) and not s.vehicle.wrecked:
			vehicles[s.vehicle] = known.get("pos", c.centre)
		else:
			on_foot.append(s)
	vel /= maxf(float((c.who as Array).size()), 1.0)
	var base := {"seen_at": t - float(c.age), "by": _callsign(squad), "source": "squad", "confidence": 0.5 if heard else 1.0,
		"unc0": SidePicture.base_uncertainty("heard" if heard else "seen"), "heading": _heading(vel), "speed": Vector2(vel.x, vel.z).length()}
	var out: Array[Dictionary] = []
	for v: Vehicle in vehicles:
		var r := base.duplicate()
		r.merge({"kind": GroupBoard.vehicle_kind(v.model), "count": 1, "pos": vehicles[v]})
		out.append(r)
	if not on_foot.is_empty():
		var kinds := {}
		for s in on_foot:
			var k := GroupBoard.soldier_kind(s)
			kinds[k] = int(kinds.get(k, 0)) + 1
		var kind := "inf"
		for k: String in ["at", "mg", "sniper"]:  # the most dangerous thing seen names the group
			if kinds.has(k):
				kind = k
				break
		var r := base.duplicate()
		r.merge({"kind": kind, "count": on_foot.size(), "pos": c.centre})
		out.append(r)
	return out


## Sends `r` over `squad`'s radio, or holds it (no radio).
func _send(squad: Squad, r: Dictionary, t: float) -> void:
	var radio := radio_man(squad)
	if radio == null:
		var id := GroupBoard.group_id(squad)
		if not _held.has(id):
			_held[id] = []
		(_held[id] as Array).append(r)
		return
	var brain := SquadAI.of(radio)
	var skill := _leader_skill(squad)
	var under_fire := brain != null and brain.in_contact()
	picture.submit(r, t, picture.delay_for(skill, under_fire), _up_check(radio))


## Held reports go out when one of the group is within shout_m of another group's man, or a
## player, with a radio.
func _relay_held(squads: Array[Squad], t: float) -> void:
	if _held.is_empty():
		return
	var shout := SidePicture.num("shout_m", 80.0)
	for id: String in _held.keys():
		var squad: Squad = null
		for s in squads:
			if GroupBoard.group_id(s) == id:
				squad = s
		if squad == null:
			_held.erase(id)  # gone: its reports with it
			continue
		var relay: Soldier = radio_man(squad)  # its own radio is back (picked one up)
		if relay == null:
			relay = _radio_near(squad, squads, shout)
		if relay == null:
			continue
		var skill := float(SquadAI.of(relay).combat) if SquadAI.of(relay) else 1.0
		for r: Dictionary in _held[id]:
			r["relayed_by"] = _who(relay)
			picture.submit(r, t, picture.delay_for(skill), _up_check(relay))
		_held.erase(id)


func _radio_near(squad: Squad, squads: Array[Squad], shout: float) -> Soldier:
	var ours := squad.members().filter(func(s: Soldier) -> bool: return s.vitals.is_up())
	var others: Array[Soldier] = []
	for other in squads:
		if other != squad:
			var man := radio_man(other)
			if man:
				others.append(man)
	for p: Soldier in MapNodes.players(self):
		if p.vitals.is_up() and EnemyTags.has_radio(p):
			others.append(p)
	for a: Soldier in ours:
		for b: Soldier in others:
			if a.global_position.distance_to(b.global_position) <= shout:
				return b
	return null


## The live friendly Squad with board id `id`, or null.
func squad_of(id: String) -> Squad:
	for squad: Squad in GroupBoard.squads_of(get_tree(), &"friendly"):
		if GroupBoard.group_id(squad) == id:
			return squad
	return null


## The man up who carries `squad`'s radio: one with a radio in his kit, else (a side with issued
## sets, and not meta "no_radio") its leader or first man up; null for none.
func radio_man(squad: Squad) -> Soldier:
	if squad == null or bool(squad.get_meta(&"no_radio", false)):
		return null
	var up := squad.members().filter(func(s: Soldier) -> bool: return s.vitals.is_up() and not s.is_in_group(Soldier.DEAD_GROUP))
	for s: Soldier in up:
		if EnemyTags.has_radio(s):
			return s
	if up.is_empty() or not SidePicture.issued_radio(SidePicture.profile_of(squad.faction)):
		return null
	if squad.leader and is_instance_valid(squad.leader) and squad.leader in up:
		return squad.leader
	return up[0]


func _leader_skill(squad: Squad) -> float:
	var lead: Soldier = squad.leader if is_instance_valid(squad.leader) else null
	if lead and not lead.is_ai():
		return 1.0  # a player leads: as quick as anyone on the net
	if lead == null:
		var men := squad.members()
		lead = men[0] if not men.is_empty() else null
	var brain := SquadAI.of(lead) if lead else null
	return float(brain.combat) if brain else 0.6


static func _up_check(s: Soldier) -> Callable:
	var ref: WeakRef = weakref(s)
	return func() -> bool:
		var who := ref.get_ref() as Soldier
		return who != null and who.vitals.is_up()


static func _heading(v: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0) if Vector2(v.x, v.z).length() > 0.1 else 0.0


func _callsign(squad: Squad) -> String:
	var meta: Dictionary = board.rows.get(GroupBoard.group_id(squad), {})
	return String(meta.get("callsign", squad.get_meta(&"callsign", squad.name)))


static func _who(s: Soldier) -> String:
	return s.display_name()


# --- Reports from players ------------------------------------------------------------------------

## Host (EnemyTags.server_tag): `by` tagged `target` on his radio: a player's report.
func server_report_tag(by: Soldier, target: Soldier) -> void:
	if not multiplayer.is_server() or target == null:
		return
	var kind := GroupBoard.vehicle_kind(target.vehicle.model) if target.vehicle and is_instance_valid(target.vehicle) else GroupBoard.soldier_kind(target)
	var r := {"kind": kind, "count": 1, "pos": target.global_position, "by": _who(by) if by else "Lookout", "source": "tag" if by else "lookout",
		"unc0": SidePicture.base_uncertainty("tag"), "tag_names": [String(target.name)] if by else []}
	var delay := SidePicture.delay_s("player", 1.0, false, picture.comms_down) if by else picture.delay_for(0.5)
	picture.submit(r, now(), delay, _up_check(by) if by else Callable())


## Host (PeopleLayer.server_report): `reporter` reported `group` at `centre`.
func server_report_position(reporter: Soldier, centre: Vector3, group: Array) -> void:
	if not multiplayer.is_server() or reporter == null:
		return
	var kinds := {}
	for s: Variant in group:
		kinds[GroupBoard.soldier_kind(s as Soldier)] = true
	var kind := "inf"
	for k: String in ["at", "mg", "sniper"]:
		if kinds.has(k):
			kind = k
			break
	picture.submit({"kind": kind, "count": group.size(), "pos": centre, "by": _who(reporter), "source": "report",
		"unc0": SidePicture.base_uncertainty("report")}, now(), SidePicture.delay_s("player", 1.0, false, picture.comms_down), _up_check(reporter))


## Host (A4's vehicle commander, a laser designator): `by` lased `kind` at `pos`.
func server_report_lase(by: Soldier, pos: Vector3, kind: String, count := 1) -> void:
	if not multiplayer.is_server():
		return
	picture.submit({"kind": kind, "count": count, "pos": pos, "by": _who(by) if by else "", "source": "lase",
		"unc0": SidePicture.base_uncertainty("lase")}, now(), SidePicture.delay_s("player", 1.0, false, picture.comms_down))


## Host: the friendly net goes down (a jammer, the HQ's relay hit) or comes back.
func server_set_comms(down: bool, why := "") -> void:
	picture.comms_down = down
	picture.comms_why = why
	SessionLog.note("[picture] friendly comms %s%s" % ["down" if down else "back", (": " + why) if why != "" else ""])


# --- Blue Force Tracker --------------------------------------------------------------------------

func _track(t: float) -> void:
	var keep := {}
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked or not (v.faction in FRIENDLY):
			continue
		var key := "v:" + (v.vehicle_id if v.vehicle_id != "" else String(v.name))
		keep[key] = true
		picture.bft_vehicle(key, v.global_position, String(v.spec.get("name", v.model)), radio_ok(v), t)
	for id: String in board.rows:
		var row: Dictionary = board.rows[id]
		if (row.pos as Vector3).is_finite():
			keep["g:" + id] = true
			var b: Dictionary = picture.bft.get("g:" + id, {})
			if b.is_empty() or float(b.at) != float(row.sitrep_at):
				picture.bft_group("g:" + id, row.pos, String(row.callsign), float(row.sitrep_at))
	picture.bft_keep(keep)


## Whether vehicle `v`'s radio works (A2's radio module sets meta "radio_down").
static func radio_ok(v: Vehicle) -> bool:
	return not v.wrecked and v.battery_ok and not bool(v.get_meta(&"radio_down", false))


# --- What players see ----------------------------------------------------------------------------

## Each entry as a spot marker; changed ones re-sent; dropped ones removed.
func _sync_markers(t: float) -> void:
	if picture.revision == _synced:
		return
	_synced = picture.revision
	var markers := MapNodes.markers(self)
	if markers == null:
		return
	var live := {}
	for e: Dictionary in picture.entries:
		var eid := int(e.id)
		live[eid] = true
		if _marker_rev.get(eid, -1) == int(e.rev) and markers.markers.has(int(_marker_of.get(eid, 0))):
			continue
		var spot := spot_of(e, t)
		if _marker_of.has(eid) and markers.markers.has(int(_marker_of[eid])):
			markers.server_spot_update(int(_marker_of[eid]), spot)
		else:
			var mid := markers.server_spot(spot)
			if mid == 0:
				continue
			_marker_of[eid] = mid
		_marker_rev[eid] = int(e.rev)
	for eid: int in _marker_of.keys():
		if not live.has(eid):
			markers.server_remove(int(_marker_of[eid]))
			_marker_of.erase(eid)
			_marker_rev.erase(eid)


## What a player's map and HUD get of entry `e` at `t` (ages from now; the uncertainty and its
## growth so a peer can age it itself).
func spot_of(e: Dictionary, t: float) -> Dictionary:
	return {"entry": int(e.id), "side": String(picture.side), "what": String(e.kind), "count": int(e.count), "pos": Vector2(e.pos.x, e.pos.z),
		"y": float(e.pos.y), "age": t - float(e.seen_at), "reported_age": t - float(e.reported_at), "unc": picture.uncertainty(e, t),
		"by": String(e.by), "tag": bool(e.tag), "tag_names": (e.tag_names as Array).duplicate(), "reports": (e.reports as Array).duplicate()}
