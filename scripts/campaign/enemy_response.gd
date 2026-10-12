class_name EnemyResponse
extends Node
## A hot zone's answer to the squad (4B part 3, Captain 2026-10-12): what the enemy does with
## what its Alert knows and how much Pressure the squad has put on it.
##
## - Roaming patrols: a buddy pair (PATROL_SIZE) walks each of the zone's patrol routes
##   (ZoneDef "patrols"), from site to site, keeping GATE_M outside each footprint. They set
##   out out of sight: at the first route point SPAWN_UNSEEN_M from every player (else later).
##   A patrol wiped out (nobody left standing) costs Pressure "patrol_lost" and misses its next
##   check-in (Alert).
## - A report of shots, a blast, a body or a missed check-in: the nearest patrol goes to look
##   (LOOK_S round the spot), then back to its route.
## - Alerted zone, or tier 1 (10): patrols go in pairs (a second team walks each route the
##   other way round).
## - Alerted zone, or tier 2 (20): checkpoints closed (their posts stand to). An alerted zone
##   also has its QRF on standby.
## - Engaged zone: a report launches the QRF (Reinforcements, driven) from the nearest living
##   QRF base to the last known position, at most once per QRF_RELAUNCH_S. On standby it goes
##   at once; caught cold (the zone went straight to engaged) it turns out QRF_TURNOUT_S later.
##   Tier 1 makes it a pair bigger; tier 2 sends a second one from the next base (the HQ if
##   only one base is left). A destroyed QRF base removes its waves: none at all with every
##   base gone.
## - Nothing spawns where the squad would see it (_unseen): a QRF, hunters or HQ pair whose
##   every gate is in sight waits. Living EnemyResponse spawns are capped at MAX_ALIVE.
## - Tier 3 (35): hunter teams (4 to 6 good troops) from the HQ go to the last known position:
##   they flank, track (retargeted every HUNTER_RETARGET_S), search round it and throw smoke.
##   Tier 4 (50): two teams at once, and the HQ sends a pair to each of its sites without one
##   every REINFORCE_GAP_S (named under the site, "<site>_HR<k>_<i>", so they count as its
##   garrison).
## - Officers (OFFICER_POSTS) killed make the hunters less coordinated (coordination()): fewer
##   flanks, slower tracking, less smoke, worse discipline.
## Generic hunters only (named ones come with wave 6); everyone on foot until wave 5's vehicles.
## Host only; one node per hot zone ("EnemyResponse", ZoneLevel). Runs on the Alert's clock
## (tests jump it with Alert.advance and then server_tick). All numbers Proposed.

const PATROL_SIZE := 2
## Route points sit this far outside a site's footprint (its HALF's length out from the middle).
const GATE_M := 8.0
## Nobody spawns closer than this to any player.
const SPAWN_UNSEEN_M := 250.0
const TICK_S := 2.0
const QRF_RELAUNCH_S := 300.0
## A QRF not on standby (the zone wasn't alerted before it was engaged) turns out this much later.
const QRF_TURNOUT_S := 180.0
## A patrol sent to look searches LOOK_POINTS round the spot, LOOK_RING_M out, for LOOK_S.
const LOOK_S := 600.0
const LOOK_POINTS := 2
const LOOK_RING_M := 30.0
const LOOK_KINDS: Array[StringName] = [&"shot", &"blast", &"body", &"missed_checkin"]
## Living soldiers this node has spawned (patrols, hunters, HQ pairs) never go past this; QRF
## waves have Reinforcements' own cap.
const MAX_ALIVE := 40
const HUNTER_GAP_S := 600.0
const HUNTER_SIZE := Vector2i(4, 6)
const HUNTER_COMBAT := 0.7
const HUNTER_DISCIPLINE := 0.75
const HUNTER_SMOKES := 2
## Hunters retarget to the last known position this often, divided by coordination.
const HUNTER_RETARGET_S := 30.0
const SEARCH_POINTS := 4
const SEARCH_MIN_M := 15.0
const SEARCH_SHARE := 0.6
## A flank goes this far to one side of the straight line: radius * FLANK_SHARE + FLANK_M.
const FLANK_SHARE := 0.5
const FLANK_M := 60.0
## ... and this share of that distance short of the last known position.
const FLANK_SHORT := 0.5
## A hunter throws smoke this share of the way to his threat.
const SMOKE_SHARE := 0.4
const SMOKE := &"smoke_grenade"
## Garrison posts (callsign index from 0) that hold an officer, by site type.
const OFFICER_POSTS := {"hq": [0, 1], "outpost": [0], "qrf_base": [0]}
const OFFICER_LOSS := 0.2
const MIN_COORDINATION := 0.2
const REINFORCE_GAP_S := 1200.0
const REINFORCE_MAX := 4
const REINFORCE_TYPES: Array[String] = ["outpost", "checkpoint"]
const TEAM_SPACING_M := 1.6

var level: Node3D
var alert: Alert
var pressure: Pressure
var reinforcements: Reinforcements
## Roaming patrols: {"k", "route" (Array[Vector3]), "squad", "soldiers", "pending", "second",
## "doubled", "lost", "last_pos"}.
var patrols: Array[Dictionary] = []
var checkpoints_closed := false
## Every QRF launched: {"from" (module id), "at", "soldiers"}.
var qrf_launches: Array[Dictionary] = []
## Hunter teams: {"k", "squad", "soldiers", "at", "retarget_at", "smoked"}.
var hunters: Array[Dictionary] = []
## HQ reinforcement pairs: {"k", "to" (module id), "squad", "soldiers", "at"}.
var reinforcement_pairs: Array[Dictionary] = []
var _officers_dead := {}   # soldier name -> true
var _last_qrf := -INF
var _qrf_due := INF      # a cold QRF's turnout time
var _turnout := false    # the zone just went straight to engaged
var _zone_was := Alert.State.NORMAL
var _last_hunter := -INF
var _last_reinforce := -INF
var _hunter_teams := 0
var _reinforce_rounds := 0
var _tick := 0.0
var _started := false


func _init() -> void:
	name = "EnemyResponse"


func _ready() -> void:
	level = get_parent() as Node3D
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	pressure = level.get_node_or_null(^"Pressure") as Pressure if level else null
	reinforcements = level.get_node_or_null(^"Reinforcements") as Reinforcements if level else null  # MapNodes.install's
	if reinforcements:
		reinforcements.driven = true
		reinforcements.aim = _aim
	if alert:
		alert.state_changed.connect(_on_state_changed)
		alert.reported.connect(_on_reported)
	if pressure:
		pressure.tier_changed.connect(_on_tier_changed)


## The enemy response of the level `from` is in (null outside a hot zone).
static func of(from: Node) -> EnemyResponse:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"EnemyResponse") as EnemyResponse if lvl else null


func now() -> float:
	return alert.now() if alert else Soldier._now()


## Where the QRF waves head: the last known position, or Vector3.INF (keep their route).
func _aim() -> Vector3:
	if alert == null:
		return Vector3.INF
	var lk := alert.last_known()
	return lk.pos if not lk.is_empty() else Vector3.INF


## 1 with every officer alive, OFFICER_LOSS less for each one dead, never under MIN_COORDINATION.
func coordination() -> float:
	return maxf(1.0 - OFFICER_LOSS * _officers_dead.size(), MIN_COORDINATION)


func _tier() -> int:
	return pressure.tier() if pressure else 0


func _zone_state() -> int:
	return alert.zone_state if alert else Alert.State.NORMAL


# --- Start (host) -------------------------------------------------------------------------------

## Host (ZoneLevel._spawn_ai): the roaming patrols set out, one per route in the zone's
## definition (any that would be seen spawning wait for the tick).
func server_start() -> void:
	if not multiplayer.is_server() or _started:
		return
	_started = true
	var routes: Array = (level.get(&"def") as Dictionary).get("patrols", []) if level else []
	for r: Array in routes:
		var route := _patrol_route(r)
		if route.size() < 2:
			continue
		var record := {"k": patrols.size() + 1, "route": route, "squad": null, "soldiers": [], "pending": true,
			"second": false, "doubled": false, "lost": false, "last_pos": route[0], "walk": route, "looking_until": -INF}
		patrols.append(record)
		_try_patrol(record)


## A ZoneDef route ([[x, z], ...]) as ground points, each site's moved out to its footprint's
## edge (GATE_M past it) toward the previous point, so nobody stands inside an unstreamed building.
func _patrol_route(r: Array) -> Array[Vector3]:
	var raw: Array[Vector3] = []
	for p: Array in r:
		raw.append(_ground(Vector3(float(p[0]), 0.0, float(p[1]))))
	var out: Array[Vector3] = []
	for j in raw.size():
		var at := raw[j]
		var m := level.call(&"module_at", at) as ZoneModule
		out.append(_gate(m, raw[(j - 1 + raw.size()) % raw.size()]) if m else at)
	return out


## Module `m`'s gate toward `toward`: GATE_M outside its footprint, on the ground.
func _gate(m: ZoneModule, toward: Vector3) -> Vector3:
	var half: Vector2 = ZoneModules.HALF.get(m.type, Vector2(20, 20))
	var dir := Vector3(toward.x - m.global_position.x, 0.0, toward.z - m.global_position.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	return _ground(m.global_position + dir * (half.length() + GATE_M))


## A patrol record's team sets out from its first unseen route point (its route turned to start
## there). False (still pending) if every point is in sight of a player.
func _try_patrol(record: Dictionary) -> bool:
	var route: Array[Vector3] = record.route
	if _alive_spawned() + PATROL_SIZE > MAX_ALIVE:
		return false
	for j in route.size():
		if not _unseen(route[j]):
			continue
		var turned: Array[Vector3] = []
		turned.append_array(route.slice(j))
		turned.append_array(route.slice(0, j))
		var callsign := ("P%dB" if record.second else "P%d") % int(record.k)
		var squad := _new_squad(callsign)
		squad.patrol = turned
		var stats: Dictionary = ZoneLevel.GARRISON_STATS
		record.soldiers = _spawn_team(squad, callsign, PATROL_SIZE, turned[0], turned[1 % turned.size()],
			CompoundLevel.HOSTILE_LOADOUT, float(stats.combat), float(stats.discipline), alert.mode_at(turned[0]) if alert else "aware")
		record.squad = squad
		record.walk = turned
		record.pending = false
		record.last_pos = turned[0]
		return true
	return false


# --- The tick (host) ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not _started:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()


## Host: patrols (pending, lost, doubled), checkpoints, officers, hunters and the HQ's
## reinforcements. Every TICK_S.
func server_tick() -> void:
	if not multiplayer.is_server() or level == null:
		return
	var tier := _tier()
	var alerted := _zone_state() >= Alert.State.ALERTED
	_count_officers()
	if now() >= _qrf_due:
		_qrf_due = INF
		_launch_qrf()  # turned out
	_tick_patrols(alerted or tier >= 1)
	checkpoints_closed = alerted or tier >= 2
	if checkpoints_closed and alert:
		for m: ZoneModule in level.call(&"modules"):
			if m.type == "checkpoint":
				alert.server_stand_to(m.module_id)
	_tick_hunters(tier)
	if tier >= 4:
		_reinforce_sites()


func _tick_patrols(doubled: bool) -> void:
	for record: Dictionary in patrols.duplicate():
		if record.pending:
			_try_patrol(record)
			continue
		var living := _living(record.soldiers)
		if not living.is_empty():
			record.last_pos = (living[0] as Soldier).global_position
			if now() >= float(record.looking_until) and record.looking_until > -INF:
				record.looking_until = -INF  # had a look: back to the route
				_set_route(record.squad, living, record.walk)
		elif not record.lost:
			record.lost = true  # nobody left to answer the radio
			if pressure:
				pressure.server_add("patrol_lost")
			if alert:
				alert.server_overdue(record.last_pos, randf_range(Alert.CHECK_IN_S.x, Alert.CHECK_IN_S.y))
			continue
		if doubled and not record.second and not record.doubled and not living.is_empty():
			var route: Array[Vector3] = record.route.duplicate()
			route.reverse()
			var twin := {"k": record.k, "route": route, "squad": null, "soldiers": [], "pending": true,
				"second": true, "doubled": true, "lost": false, "last_pos": route[0], "walk": route, "looking_until": -INF}
			# Reversed, the route starts at its last point (it only moves on if that one is seen).
			if _try_patrol(twin):
				record.doubled = true
				patrols.append(twin)


## Officers (OFFICER_POSTS) found dead among the AI: each lowers coordination once.
func _count_officers() -> void:
	var lvl := level as CompoundLevel
	if lvl == null:
		return
	var officers := {}
	for m: ZoneModule in level.call(&"modules"):
		for i: int in OFFICER_POSTS.get(m.type, []):
			officers[("%s_H%d" % [m.module_id, i + 1]).validate_node_name()] = true
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and officers.has(String(s.name)) and s.vitals.is_dead():
			_officers_dead[String(s.name)] = true


# --- The QRF (host) -----------------------------------------------------------------------------

## The zone straight from below ALERTED to ENGAGED: its QRF wasn't on standby.
func _on_state_changed(area: String, state: int) -> void:
	if area != "zone":
		return
	if state == Alert.State.ENGAGED and _zone_was < Alert.State.ENGAGED:
		_turnout = _zone_was < Alert.State.ALERTED
	_zone_was = state


## A report reached the net: a patrol goes to look at shots, a blast, a body or a silent post;
## an engaged zone launches its QRF at the last known position (once per QRF_RELAUNCH_S), at
## once if it was on standby, else after QRF_TURNOUT_S.
func _on_reported(report: Dictionary) -> void:
	if not multiplayer.is_server() or alert == null:
		return
	if report.kind in LOOK_KINDS:
		_send_look(report.pos)
	if reinforcements == null or alert.zone_state != Alert.State.ENGAGED or now() - _last_qrf < QRF_RELAUNCH_S or _qrf_due < INF:
		return
	if _turnout:
		_turnout = false
		_qrf_due = now() + QRF_TURNOUT_S  # caught cold: the QRF has to turn out first
		return
	_launch_qrf()


## The QRF goes: one wave from the nearest living QRF base, a second at tier 2 (the next base,
## or the HQ when only one base is left); none with every base gone. A base whose every gate is
## in sight sends nothing this time.
func _launch_qrf() -> void:
	var lk := alert.last_known() if alert else {}
	if lk.is_empty() or reinforcements == null:
		return
	var lkp: Vector3 = lk.pos
	var tier := _tier()
	var bases := _living_sites("qrf_base", lkp)
	if bases.is_empty():
		return  # a destroyed QRF base sends no waves
	var from: Array[ZoneModule] = [bases[0]]
	if tier >= 2:
		var hq := _hq()
		if bases.size() >= 2:
			from.append(bases[1])
		elif hq:
			from.append(hq)
	for m in from:
		var gate := _unseen_gate(m, lkp)
		if not gate.is_finite():
			continue
		var soldiers := reinforcements.server_send(gate, 1 if tier >= 1 else 0)
		qrf_launches.append({"from": m.module_id, "at": now(), "soldiers": soldiers})
		_last_qrf = now()


## The nearest patrol out (not already looking) goes to look round `pos` for LOOK_S.
func _send_look(pos: Vector3) -> void:
	var best: Dictionary = {}
	var best_d := INF
	var best_living: Array = []
	for record: Dictionary in patrols:
		if record.pending or record.lost or now() < float(record.looking_until):
			continue
		var living := _living(record.soldiers)
		if living.is_empty():
			continue
		var d := (living[0] as Soldier).global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = record
			best_living = living
	if best.is_empty():
		return
	best.looking_until = now() + LOOK_S
	var route: Array[Vector3] = [_ground(pos)]
	var start := randf() * TAU
	for k in LOOK_POINTS:
		var a := start + TAU * k / LOOK_POINTS
		route.append(_ground(pos + Vector3(cos(a), 0.0, sin(a)) * LOOK_RING_M))
	_set_route(best.squad, best_living, route)


func _on_tier_changed(_tier_now: int) -> void:
	if multiplayer.is_server() and _started:
		server_tick()


# --- Hunters (host) -----------------------------------------------------------------------------

func _tick_hunters(tier: int) -> void:
	var c := coordination()
	var lk := alert.last_known() if alert else {}
	var teams := 0
	for team: Dictionary in hunters:
		var living := _living(team.soldiers)
		if living.is_empty():
			continue
		teams += 1
		if not lk.is_empty() and now() >= float(team.retarget_at):
			team.retarget_at = now() + HUNTER_RETARGET_S / c
			var route: Array[Vector3] = [_ground(lk.pos)]
			route.append_array(_search_ring(lk.pos, float(lk.radius)))
			_set_route(team.squad, living, route)
		if not team.smoked:
			for s: Soldier in living:
				var brain := SquadAI.of(s)
				if brain and brain.in_contact() and Vitals.has_item(s.inventory, SMOKE) and randf() < c \
						and brain.order_throw(SMOKE, s.global_position.lerp(s.threat_pos, SMOKE_SHARE)):
					team.smoked = true
					break
	if tier < 3 or lk.is_empty() or teams >= (2 if tier >= 4 else 1) or now() - _last_hunter < HUNTER_GAP_S \
			or _alive_spawned() + HUNTER_SIZE.y > MAX_ALIVE:
		return
	_send_hunters(lk.pos, float(lk.radius))


## A hunter team from the HQ (else the nearest QRF base, else the zone's edge) to `lkp`: a flank
## first if it's coordinated enough, then the position and a search round it. Waits (tries again
## next tick) while every way out is in sight.
func _send_hunters(lkp: Vector3, radius: float) -> void:
	var c := coordination()
	var origin := _hunter_origin(lkp)
	if not origin.is_finite():
		return
	_hunter_teams += 1
	_last_hunter = now()
	var route: Array[Vector3] = []
	if randf() < c:
		var dir := Vector3(lkp.x - origin.x, 0.0, lkp.z - origin.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		var off := radius * FLANK_SHARE + FLANK_M
		route.append(_ground(lkp - dir * off * FLANK_SHORT + side * off))
	route.append(_ground(lkp))
	route.append_array(_search_ring(lkp, radius))
	var callsign := "HT%d" % _hunter_teams
	var squad := _new_squad(callsign)
	squad.patrol = route
	var loadout: Array = CompoundLevel.HOSTILE_LOADOUT.duplicate()
	for i in HUNTER_SMOKES:
		loadout.append(String(SMOKE))
	var soldiers := _spawn_team(squad, callsign, randi_range(HUNTER_SIZE.x, HUNTER_SIZE.y), origin, route[0], loadout,
		HUNTER_COMBAT, HUNTER_DISCIPLINE * c, "combat")
	hunters.append({"k": _hunter_teams, "squad": squad, "soldiers": soldiers, "at": now(),
		"retarget_at": now() + HUNTER_RETARGET_S / c, "smoked": false})
	print("[response] hunters %s: %d from (%.0f, %.0f), coordination %.1f" % [callsign, soldiers.size(), origin.x, origin.z, c])


## Where hunters set out: an unseen gate of the HQ, else of the nearest QRF base, else the
## zone's edge out of sight; Vector3.INF if all of those are seen.
func _hunter_origin(lkp: Vector3) -> Vector3:
	var sites: Array[ZoneModule] = []
	var hq := _hq()
	if hq:
		sites.append(hq)
	sites.append_array(_living_sites("qrf_base", lkp))
	for m in sites:
		var gate := _unseen_gate(m, lkp)
		if gate.is_finite():
			return gate
	var at: Array[Vector2] = []
	for p: Soldier in _watchers():
		at.append(Vector2(p.global_position.x, p.global_position.z))
	var edge: Vector3 = level.call(&"reinforcement_edge", at)
	return edge if _unseen(edge) else Vector3.INF


## SEARCH_POINTS round `centre`, max(radius * SEARCH_SHARE, SEARCH_MIN_M) out.
func _search_ring(centre: Vector3, radius: float) -> Array[Vector3]:
	var r := maxf(radius * SEARCH_SHARE, SEARCH_MIN_M)
	var start := randf() * TAU
	var out: Array[Vector3] = []
	for k in SEARCH_POINTS:
		var a := start + TAU * k / SEARCH_POINTS
		out.append(_ground(centre + Vector3(cos(a), 0.0, sin(a)) * r))
	return out


## `squad` walks `route` from its first point (its living members start over).
func _set_route(squad: Squad, living: Array, route: Array[Vector3]) -> void:
	if not is_instance_valid(squad):
		return
	squad.patrol = route
	for s: Soldier in living:
		var brain := SquadAI.of(s)
		if brain:
			brain._patrol_index = 0


# --- The HQ reinforces its sites (host) ---------------------------------------------------------

## Every REINFORCE_GAP_S (the first at once): a pair from the HQ to each garrisoned outpost and
## checkpoint still up that has no living pair of the HQ's yet, REINFORCE_MAX at most a round,
## never past MAX_ALIVE. The pair is named under the site ("<site>_HR<k>_<i>"): it counts as
## its garrison (ZoneLevel.garrison_alive, Alert's check-ins).
func _reinforce_sites() -> void:
	var hq := _hq()
	if hq == null or now() - _last_reinforce < REINFORCE_GAP_S:
		return
	_last_reinforce = now()
	_reinforce_rounds += 1
	var had := level.get(&"_garrisoned") as Dictionary
	var sent := 0
	var stats: Dictionary = ZoneLevel.GARRISON_STATS
	for m: ZoneModule in level.call(&"modules"):
		if sent >= REINFORCE_MAX or _alive_spawned() + 2 > MAX_ALIVE:
			break
		if not (m.type in REINFORCE_TYPES) or had == null or int(had.get(m.module_id, 0)) <= 0 or level.call(&"site_down", m.module_id):
			continue
		if reinforcement_pairs.any(func(p: Dictionary) -> bool: return p.to == m.module_id and not _living(p.soldiers).is_empty()):
			continue  # already has one
		var from := _unseen_gate(hq, m.global_position)
		if not from.is_finite():
			break  # the HQ is watched: no one leaves it this round
		sent += 1
		var k := reinforcement_pairs.size() + 1
		var callsign := ("%s_HR%d" % [m.module_id, k]).validate_node_name()
		var squad := _new_squad(callsign)
		var to := _gate(m, hq.global_position)
		var to_route: Array[Vector3] = [to]
		squad.patrol = to_route
		var soldiers := _spawn_team(squad, callsign, 2, from, to, CompoundLevel.HOSTILE_LOADOUT,
			float(stats.combat), float(stats.discipline), alert.mode_at(from) if alert else "aware")
		reinforcement_pairs.append({"k": k, "to": m.module_id, "squad": squad, "soldiers": soldiers, "at": now()})


# --- Helpers ------------------------------------------------------------------------------------

## The HQ, unless it's been taken out (or there is none).
func _hq() -> ZoneModule:
	for m: ZoneModule in level.call(&"modules"):
		if m.type == "hq" and not level.call(&"site_down", m.module_id):
			return m
	return null


## Sites of `type` not taken out, nearest `pos` first.
func _living_sites(type: String, pos: Vector3) -> Array[ZoneModule]:
	var out: Array[ZoneModule] = []
	for m: ZoneModule in level.call(&"modules"):
		if m.type == type and not level.call(&"site_down", m.module_id):
			out.append(m)
	out.sort_custom(func(a: ZoneModule, b: ZoneModule) -> bool:
		return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	return out


## Nobody of the squad (players and squad AI) within SPAWN_UNSEEN_M of `pos` (flat).
func _unseen(pos: Vector3) -> bool:
	for p: Soldier in _watchers():
		if Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < SPAWN_UNSEEN_M:
			return false
	return true


func _watchers() -> Array[Soldier]:
	var out := MapNodes.players(self)
	out.append_array(MapNodes.squad_ai(self))
	return out


## Module `m`'s gate toward `toward` if no one of the squad would see it, else its far side,
## else either flank; Vector3.INF if every one is in sight.
func _unseen_gate(m: ZoneModule, toward: Vector3) -> Vector3:
	var c := m.global_position
	var dir := Vector3(toward.x - c.x, 0.0, toward.z - c.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP)
	for d: Vector3 in [dir, -dir, side, -side]:
		var gate := _gate(m, c + d * 10.0)
		if _unseen(gate):
			return gate
	return Vector3.INF


func _ground(pos: Vector3) -> Vector3:
	return level.call(&"ground_point", pos)


## Those of `soldiers` still standing (downed counts as out).
func _living(soldiers: Array) -> Array:
	return soldiers.filter(func(s: Variant) -> bool:
		return is_instance_valid(s) and (s as Soldier).vitals.is_up() and not (s as Soldier).is_in_group(Soldier.DEAD_GROUP))


## Living soldiers this node spawned (patrols, hunters, HQ pairs).
func _alive_spawned() -> int:
	var count := 0
	for list: Array in [patrols, hunters, reinforcement_pairs]:
		for record: Dictionary in list:
			count += _living(record.soldiers).size()
	return count


func _new_squad(callsign: String) -> Squad:
	var squad := Squad.new()
	squad.name = callsign
	squad.faction = &"hostile"
	add_child(squad)
	return squad


## `size` hostiles ("<callsign>_<i>") in a line across the way from `at` to `toward`, in buddy
## pairs, walking `squad`'s patrol.
func _spawn_team(squad: Squad, callsign: String, size: int, at: Vector3, toward: Vector3, loadout: Array,
		combat: float, discipline: float, mode: String) -> Array:
	var dir := Vector3(toward.x - at.x, 0.0, toward.z - at.z)
	var across := (dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD).cross(Vector3.UP)
	var soldiers: Array = []
	for i in size:
		var pos := _ground(at + across * TEAM_SPACING_M * (i - (size - 1) / 2.0))
		var s: Soldier = level.call(&"spawn_soldier", {"name": "%s_%d" % [callsign, i + 1], "faction": "hostile",
			"variant": "urban", "pos": pos, "loadout": loadout, "combat": combat, "discipline": discipline,
			"guard": false, "mode": mode})
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = squad
		soldiers.append(s)
	for i in range(0, soldiers.size() - 1, 2):
		soldiers[i].buddy = soldiers[i + 1]
		soldiers[i + 1].buddy = soldiers[i]
	return soldiers
