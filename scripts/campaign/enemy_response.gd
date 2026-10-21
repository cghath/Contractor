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
##   every gate is in sight waits. Everything spawned (QRF waves too) shares SPAWN_BUDGET[tier].
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
const LOOK_KINDS: Array[StringName] = [&"shot", &"blast", &"body", &"missed_checkin", &"signal"]
## Trackers (Captain, 2026-10-18, inspired by S.O.G. Prairie Fire's): a hunter team, or a patrol
## out on a look, that comes within TRACK_PICKUP_M of the squad's trail (SquadTrail) no older than
## TRACK_COLD_S picks it up, fires TRACK_SIGNAL_SHOTS into the air (a "signal" report on the net:
## a patrol comes to look) and follows it mark by mark, a step every TRACK_STEP_S. Where it turns
## harder than TRACK_TURN_DEG they stop TRACK_TURN_PAUSE_S first (a dog-leg is where ambushes
## are). A broken mark (a road, water) or a cold one loses the trail: back to searching.
const TRACK_PICKUP_M := 40.0
const TRACK_COLD_S := 600.0
const TRACK_STEP_S := 4.0
const TRACK_NEAR_M := 10.0
const TRACK_TURN_DEG := 70.0
const TRACK_TURN_PAUSE_S := 10.0
const TRACK_SIGNAL_SHOTS := 3
## Named hunter squads (wave 6d): this much better than a hunter team the first time, this much
## more each time they come back, at most NEMESIS_SKILL_MAX; always a full HUNTER_SIZE.y. Proposed.
const NEMESIS_SKILL := 0.1
const NEMESIS_SKILL_PER_MEETING := 0.05
const NEMESIS_SKILL_MAX := 0.95
## One contact, one coordinated look (Captain, 2026-10-18: "enemies are getting swarmy ... they
## need better coordination"). Every shot of a firefight used to pull the next-nearest patrol in
## on its own, so pair after pair trickled at the squad from every side. Now a report within
## LOOK_MERGE_M of a look already out feeds that look (its spot moves to the newest report);
## with the zone alerted the look grows by one patrol at most every LOOK_ESCALATE_S, to LOOK_MAX
## patrols (LOOK_MAX_HIGH from tier 2). Two or more on one look meet first at rally points
## LOOK_RALLY_M short of the spot, LOOK_SPLIT_DEG apart round it and out of the squad's sight
## where one can be found, and go in together once every one is there (LOOK_RALLIED_M) or
## LOOK_RALLY_S has passed: a pincer at one moment, not a trickle.
const LOOK_MERGE_M := 150.0
const LOOK_ESCALATE_S := 60.0
const LOOK_MAX := 2
const LOOK_MAX_HIGH := 3
const LOOK_RALLY_M := 110.0
const LOOK_RALLY_S := 90.0
const LOOK_RALLIED_M := 20.0
const LOOK_SPLIT_DEG := 70.0
## Pushes (Captain, 2026-10-18: "add the changes to the hotzone ai"): a hot zone's QRF waves and
## hunter teams sent at one contact (within PUSH_MERGE_M) go in as one push. With two or more
## groups on it, each that isn't already in close waits at its own rally point PUSH_RALLY_M short
## of the spot (spread LOOK_SPLIT_DEG apart, out of sight where it can be), and all go in together
## once every one is there (PUSH_RALLIED_M) or PUSH_RALLY_S has passed. Proposed.
const PUSH_MERGE_M := 200.0
const PUSH_RALLY_M := 150.0
const PUSH_RALLY_S := 120.0
const PUSH_RALLIED_M := 30.0
## One shared budget (Captain, 2026-10-16: "too many ai in hot zones spawning and coming for the
## player"): every living soldier the zone's answer has spawned (patrols, hunters, HQ pairs AND
## the QRF waves, which used to have a separate cap of their own, so up to 40 + 20 on top of the
## garrisons) stays within SPAWN_BUDGET[tier]. Every spawn path checks it (_room); a QRF wave is
## cut down to what's left. Garrisons don't count (they come with their sites).
const SPAWN_BUDGET: Array[int] = [20, 24, 28, 32, 36]
## A QRF wave hunts the last known position for this long after it set out, then holds round the
## last spot it was sent to (Reinforcements.hunt_s) instead of every wave converging forever.
const WAVE_HUNT_S := 600.0
## Escalation over a long stay (Captain, 2026-10-16: "the whole map doesnt come after me at the
## same time, just a steady patrol or two that escalates", "suitable for an hour or two of
## play"): the budget starts at RAMP_START and eases up to the tier's SPAWN_BUDGET over
## ESCALATE_S of the zone's clock (smoothstep: slow at first, slow at the top). Pressure tier
## still caps it, so a quiet squad stays light however long it stays.
## Raised from 4 (a patrol or two) to 8 (four pairs): playtest B1399 on Red Mesa found the open
## ground too quiet in the first few minutes ("contacts come too slowly at mission start").
const RAMP_START := 8
const ESCALATE_S := 5400.0
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
## A team this big brings a medic (its TEAM_MEDIC_INDEX'th man; Captain 2026-10-17: more enemy medics).
const TEAM_MEDIC_MIN := 4
const TEAM_MEDIC_INDEX := 2

## A hot zone's standing force on its patrol routes (AI virtualization, docs/virtualization.md;
## brief 2026-10-20: "raise how many enemies a hot zone can hold, for example 2-3 times today's"):
## ROAM_TEAMS teams of ROAM_SIZE walk each route, spread along it. Like the garrisons they are the
## zone's own men: outside SPAWN_BUDGET (which still paces everything sent at the squad), never sent
## to look, and far from the squad they are profiles (Virtualizer) that cost next to nothing. A
## team wiped out stays gone. Proposed.
const ROAM_TEAMS := 2
const ROAM_SIZE := 4

## Host: a patrol was sent to look round `pos` (RadioChatter: the order on the net).
signal look_sent(pos: Vector3)
## Host: the checkpoints closed (or opened again).
signal checkpoints_changed(closed: bool)

var level: Node3D
var alert: Alert
var pressure: Pressure
var reinforcements: Reinforcements
## Which hostile faction this zone's patrols, hunters and QRF waves field (CLAUDE.md
## squad-roles-pmc bundle): CompoundLevel.HOSTILE_LOADOUT's Black Ridge AKs by default, or
## CompoundLevel.PMC_FACTION for the Vantage Group rival PMC's M4/SCAR-H/M240B mix. A zone sets
## this (zone_level.gd's _on_contract_live reads the live contract's "target") rather than every
## spawn site guessing at it.
var enemy_faction: StringName = &"black_ridge"
## The live contract's true_rating (1-5, ZoneLevel._on_contract_live), for Vantage's exo gear
## (CompoundLevel.PMC_LX3_DIFFICULTY/PMC_HX1_DIFFICULTY): 1 (no exo) unless a hard contract sets it.
var difficulty: int = 1
## The deployment's difficulty scale (ZoneLevel.difficulty_scale): hunter teams are this share.
var scale := 1.0
## Roaming patrols: {"k", "route" (Array[Vector3]), "squad", "soldiers", "pending", "second",
## "doubled", "lost", "last_pos"}.
var patrols: Array[Dictionary] = []
## Looks out: {"pos", "patrols" (patrol records), "added_at", "go_at"}; a record on its way to a
## rally point has "look_rally" (the point).
var looks: Array[Dictionary] = []
## Pushes (hot zones' QRF waves and hunter teams on one contact): {"pos", "groups", "go_at"};
## a group is {"kind": "wave" | "hunters", "ref" (the Reinforcements wave or the hunter team)}.
var pushes: Array[Dictionary] = []
var checkpoints_closed := false
## Every QRF launched: {"from" (module id), "at", "soldiers"}.
var qrf_launches: Array[Dictionary] = []
## A hot zone's roaming teams (ROAM_TEAMS a route): {"k" (the route's patrol), "j", "route", "squad",
## "soldiers", "pending", "lost"}.
var roamers: Array[Dictionary] = []
## Hunter teams: {"k", "squad", "soldiers", "at", "retarget_at", "smoked"}.
var hunters: Array[Dictionary] = []
## HQ reinforcement pairs: {"k", "to" (module id), "squad", "soldiers", "at"}.
var reinforcement_pairs: Array[Dictionary] = []
var _officers_dead := {}   # soldier name -> true
var _look_credit := 0.0    # officers dead: only coordination()'s share of looks gets ordered
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
var _started_at := 0.0  # the zone's clock when the response started (the escalation ramp)


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
		reinforcements.clock = now
		reinforcements.hunt_s = WAVE_HUNT_S
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
	_started_at = now()
	var routes: Array = (level.get(&"def") as Dictionary).get("patrols", []) if level else []
	var virtualizer := Virtualizer.of(self)
	for r: Array in routes:
		var route := _patrol_route(r)
		if route.size() < 2:
			continue
		var record := {"k": patrols.size() + 1, "route": route, "squad": null, "soldiers": [], "pending": true,
			"second": false, "doubled": false, "lost": false, "last_pos": route[0], "walk": route, "looking_until": -INF}
		patrols.append(record)
		if not _take_saved(record, virtualizer):
			_try_patrol(record)
	for record: Dictionary in patrols.duplicate():
		var back: Array[Vector3] = record.route.duplicate()
		back.reverse()
		var twin := {"k": record.k, "route": back, "squad": null, "soldiers": [], "pending": true,
			"second": true, "doubled": true, "lost": false, "last_pos": back[0], "walk": back, "looking_until": -INF}
		if _take_saved(twin, virtualizer):
			record.doubled = true
			patrols.append(twin)
	if String((level.get(&"def") as Dictionary).get("kind", "")) == "hot":
		for record: Dictionary in patrols.duplicate():
			if record.second:
				continue
			for j in ROAM_TEAMS:
				var roam := {"k": record.k, "j": j, "route": record.route, "squad": null, "soldiers": [], "pending": true, "lost": false}
				roamers.append(roam)
				var saved: Dictionary = virtualizer.take_saved("roam", {"k": record.k, "j": j}) if virtualizer else {}
				if not saved.is_empty():
					_adopt(roam, saved, "RM%d_%d" % [int(record.k), j + 1], "roam", virtualizer)
				# (the rest set out one a tick: _tick_roamers, no hitch as the zone starts)


## A patrol record takes back its saved profile (Virtualizer.take_patrol: the zone was saved with it
## out): its team walks on from where it had got to, virtual until a player comes near. False if
## the save had none for it.
func _take_saved(record: Dictionary, virtualizer: Virtualizer) -> bool:
	var saved: Dictionary = virtualizer.take_saved("patrol", {"k": int(record.k), "second": bool(record.second)}) if virtualizer else {}
	if saved.is_empty():
		return false
	_adopt(record, saved, ("P%dB" if record.second else "P%d") % int(record.k), "patrol", virtualizer)
	record.last_pos = saved.pos
	return true


## `record` (a patrol's, a roaming team's) takes saved profile `saved`: a squad `callsign` walking
## its saved route from where it had got to.
func _adopt(record: Dictionary, saved: Dictionary, callsign: String, kind: String, virtualizer: Virtualizer) -> void:
	var squad := _new_squad(callsign)
	var walk: Array[Vector3] = []
	walk.assign(saved.route if not (saved.route as Array).is_empty() else record.route)
	squad.patrol = walk
	record.squad = squad
	record.walk = walk
	record.pending = false
	virtualizer.adopt(record, saved, kind)


## A roaming team sets out (ROAM_TEAMS): from the route point its number puts it at (spread along
## the route) or the next one no player would see it at; the route turned to start there. False
## (still pending) if every point is in sight.
func _try_roam(record: Dictionary) -> bool:
	var route: Array[Vector3] = record.route
	var from := int(route.size() * (int(record.j) + 1) / float(ROAM_TEAMS + 1))
	for step in route.size():
		var i := (from + step) % route.size()
		if not _unseen(route[i]):
			continue
		var turned: Array[Vector3] = []
		turned.append_array(route.slice(i))
		turned.append_array(route.slice(0, i))
		var callsign := "RM%d_%d" % [int(record.k), int(record.j) + 1]
		var squad := _new_squad(callsign)
		squad.patrol = turned
		var stats: Dictionary = ZoneLevel.GARRISON_STATS
		record.soldiers = _spawn_team(squad, callsign, ROAM_SIZE, turned[0], turned[1 % turned.size()],
			CompoundLevel.HOSTILE_LOADOUT, float(stats.combat), float(stats.discipline), alert.mode_at(turned[0]) if alert else "aware")
		record.squad = squad
		record.pending = false
		_virtualize(record, "roam")
		return true
	return false


## Every tick: one roaming team still to set out tries (a team a tick: spawning is a hitch, and far
## from the squad it goes virtual at once); one with nobody left is lost.
func _tick_roamers() -> void:
	var tried := false
	for record: Dictionary in roamers:
		if record.pending:
			if not tried:
				tried = true
				_try_roam(record)
		elif not record.lost and Virtualizer.up(record) == 0:
			record.lost = true


## Host: `record` may go virtual far from the squad (Virtualizer.track): its owner's decisions don't
## change, it only counts and moves as a profile meanwhile.
func _virtualize(record: Dictionary, kind: String) -> void:
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		virtualizer.track(record, kind)


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
	if PATROL_SIZE > _room():
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
		_maybe_ride(record, turned)
		_virtualize(record, "patrol")
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
	_tick_roamers()
	var closed := alerted or tier >= 2
	if closed != checkpoints_closed:
		checkpoints_changed.emit(closed)
	checkpoints_closed = closed
	if checkpoints_closed and alert:
		for m: ZoneModule in level.call(&"modules"):
			if m.type == "checkpoint":
				alert.server_stand_to(m.module_id)
	_tick_hunters(tier)
	_tick_pushes()
	if tier >= 4:
		_reinforce_sites()


func _tick_patrols(doubled: bool) -> void:
	_tick_looks()
	for record: Dictionary in patrols.duplicate():
		if record.pending:
			_try_patrol(record)
			continue
		var living := _living(record.soldiers)
		var up := Virtualizer.up(record)  # a virtual patrol is still out (docs/virtualization.md)
		if up > 0:
			record.last_pos = Virtualizer.lead(record)
			if now() >= float(record.looking_until) and record.looking_until > -INF:
				record.looking_until = -INF  # had a look: back to the route
				record.erase("look_rally")
				record.erase("trail_mark")
				_set_route(record.squad, living, record.walk)
			elif now() < float(record.looking_until) and not record.has("look_rally"):
				_track(record, living)  # a patrol out looking can pick up the squad's trail
		elif not record.lost:
			record.lost = true  # nobody left to answer the radio
			if pressure:
				pressure.server_add("patrol_lost")
			if alert:
				alert.server_overdue(record.last_pos, randf_range(Alert.CHECK_IN_S.x, Alert.CHECK_IN_S.y))
			continue
		if doubled and not record.second and not record.doubled and up > 0:
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
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		for who: String in virtualizer.deaths:  # killed off-screen (Virtualizer's fights)
			if officers.has(who):
				_officers_dead[who] = true


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
	var command := EnemyCommand.of(self)
	var from: Array[ZoneModule] = [bases[0]]
	if tier >= 2:
		var hq := _hq()
		if bases.size() >= 2:
			from.append(bases[1])
		elif hq:
			from.append(hq)
	var approved := false  # the commander says yes once per launch: one operation, one "move out"
	for m in from:
		var gate := _unseen_gate(m, lkp)
		if not gate.is_finite():
			continue
		var room := _room()
		if room < 2:
			break  # the zone's answer is out in full already (SPAWN_BUDGET)
		var extra := 1 if tier >= 1 else 0
		var wanted := reinforcements.next_wave_size(extra, room)
		if wanted < 2:
			break  # the reinforcements' own cap (max_alive)
		var planned := reinforcements.next_wave_size(extra, mini(room, floori(command.available_cp()))) if command else wanted
		if command and not approved:
			# Asked even with the reserves short of a pair (for the wave it wanted): the denial is
			# on record and an unconfirmed target still gets its probe.
			if not command.approve("qrf", lkp, planned if planned >= 2 else wanted):
				_last_qrf = now()  # turned down: asked again after QRF_RELAUNCH_S, not every report
				break
			approved = true
		elif command and (planned < 2 or not command.reserve_men(planned)):
			break  # this launch's later wave: paid quietly from what's left, or not sent
		var soldiers := reinforcements.server_send(gate, extra, planned)
		if command:
			command.refund_men(planned - soldiers.size())
		VehicleQrf.server_mount(level, m, gate, lkp, soldiers)  # wave 5b (V4): some QRFs ride in a technical
		qrf_launches.append({"from": m.module_id, "at": now(), "soldiers": soldiers})
		if not soldiers.is_empty() and not reinforcements.waves.is_empty():
			_join_push("wave", reinforcements.waves.back(), lkp)
		_last_qrf = now()


## Host: extraction starting at `pos` draws attention — at least the nearest patrol's, more if
## the zone has earned it by then (Captain, 2026-10-16: exfil was risk-free once the squad
## reached the point; then "potentially larger forces depending on factors?"). A quiet, never-
## spotted run gets one patrol's look (a heli landing or a squad leaving still isn't silent); a
## zone that's alerted or under pressure by extraction time gets a second patrol too; past
## engaged, an actual QRF wave converges (no-ops with no living QRF base — mostly a hot-zone
## thing, same as the rest of EnemyResponse). Skips _send_look's coordination trickle (meant for
## noise reports competing for attention): the first look is guaranteed, not a maybe.
func server_alert_extraction(pos: Vector3) -> void:
	_look_credit = maxf(_look_credit, 1.0)
	_send_look(pos)
	var state := _zone_state()
	var tier := _tier()
	if state >= Alert.State.ALERTED or tier >= 1:
		_look_credit = maxf(_look_credit, 1.0)
		_send_look(pos, true)  # the next-nearest free patrol joins the look: they rally, then go in together
	if state >= Alert.State.ENGAGED or tier >= 2:
		if now() - _last_qrf >= QRF_RELAUNCH_S:
			_launch_qrf()  # still one QRF per QRF_RELAUNCH_S: reaching the LZ doesn't skip the gap


## The nearest patrol out (not already looking) goes to look round `pos` for LOOK_S, unless a
## look is already out near it (LOOK_MERGE_M): that look takes the report and grows by a patrol
## only as the LOOK_* rules allow (`more`: now, within its cap; extraction). With officers dead
## the net is less coordinated (design: killed officers make patrols less coordinated): only
## coordination()'s share of the looks gets ordered (every one at full, one in five at the
## floor), evenly, not by chance.
func _send_look(pos: Vector3, more := false) -> void:
	var look := _look_near(pos)
	if not look.is_empty():
		look.pos = pos  # the newest report
		if (look.patrols as Array).size() >= _look_max():
			return
		if not more and (_zone_state() < Alert.State.ALERTED or now() - float(look.added_at) < LOOK_ESCALATE_S):
			return
	_look_credit += coordination()
	if _look_credit < 1.0 - 1e-6:
		return
	_look_credit -= 1.0
	var best: Dictionary = {}
	var best_d := INF
	var best_living: Array = []
	for record: Dictionary in patrols:
		if record.pending or record.lost or now() < float(record.looking_until):
			continue
		if Virtualizer.up(record) == 0:
			continue
		var d := Virtualizer.lead(record).distance_to(pos)
		if d < best_d:
			best_d = d
			best = record
			best_living = _living(record.soldiers)
	if best.is_empty():
		return
	best.looking_until = now() + LOOK_S
	if look.is_empty():
		look = {"pos": pos, "patrols": [], "added_at": now(), "go_at": INF}
		looks.append(look)
	(look.patrols as Array).append(best)
	look.added_at = now()
	if (look.patrols as Array).size() == 1:
		_look_in(best, best_living, pos)  # one patrol: straight there
	else:
		_rally_look(look)
	look_sent.emit(pos)


func _look_max() -> int:
	return LOOK_MAX_HIGH if _tier() >= 2 else LOOK_MAX


## The look out within LOOK_MERGE_M of `pos` with a patrol still on it, or {} (finished ones go).
func _look_near(pos: Vector3) -> Dictionary:
	for look: Dictionary in looks.duplicate():
		look.patrols = (look.patrols as Array).filter(func(r: Dictionary) -> bool:
			return not r.lost and now() < float(r.looking_until) and Virtualizer.up(r) > 0)
		if (look.patrols as Array).is_empty():
			looks.erase(look)
	var near: Dictionary = {}
	var near_d := LOOK_MERGE_M
	for look: Dictionary in looks:
		var d := Vector2(pos.x - look.pos.x, pos.z - look.pos.z).length()
		if d <= near_d:
			near_d = d
			near = look
	return near


## Patrol `record` searches round `pos`: the spot, then LOOK_POINTS round it LOOK_RING_M out.
func _look_in(record: Dictionary, living: Array, pos: Vector3) -> void:
	record.erase("look_rally")
	var route: Array[Vector3] = [_ground(pos)]
	var start := randf() * TAU
	for k in LOOK_POINTS:
		var a := start + TAU * k / LOOK_POINTS
		route.append(_ground(pos + Vector3(cos(a), 0.0, sin(a)) * LOOK_RING_M))
	_set_route(record.squad, living, route)


## A look with two or more patrols: each one not already in close (inside LOOK_RALLY_M of the
## spot) goes to its own rally point first, the points LOOK_SPLIT_DEG apart round the spot on the
## side each comes from, out of sight of the squad where a nearby bearing allows.
func _rally_look(look: Dictionary) -> void:
	var pos: Vector3 = look.pos
	var taken: Array[float] = []
	for record: Dictionary in look.patrols:
		var living := _living(record.soldiers)
		if Virtualizer.up(record) == 0:
			continue
		var at := Virtualizer.lead(record)
		if Vector2(at.x - pos.x, at.z - pos.z).length() <= LOOK_RALLY_M and not record.has("look_rally"):
			continue  # already in close: it carries on
		var a := atan2(at.z - pos.z, at.x - pos.x)
		for b: float in taken:
			var off := wrapf(a - b, -PI, PI)
			if absf(off) < deg_to_rad(LOOK_SPLIT_DEG):
				a = b + (1.0 if off >= 0.0 else -1.0) * deg_to_rad(LOOK_SPLIT_DEG)
		var rally := _rally_point(pos, a)
		taken.append(atan2(rally.z - pos.z, rally.x - pos.x))
		record.look_rally = rally
		var route: Array[Vector3] = [rally]
		_set_route(record.squad, living, route)
	look.go_at = now() + LOOK_RALLY_S


## A rally point LOOK_RALLY_M from `pos` on bearing `a` (radians, from +x toward +z), turned up
## to 40 degrees either way to one no player or squadmate has a clear line to.
func _rally_point(pos: Vector3, a: float, dist := LOOK_RALLY_M) -> Vector3:
	var first := Vector3.INF
	for step: float in [0.0, 20.0, -20.0, 40.0, -40.0]:
		var b := a + deg_to_rad(step)
		var p := _ground(pos + Vector3(cos(b), 0.0, sin(b)) * dist)
		if not first.is_finite():
			first = p
		if _hidden(p):
			return p
	return first


## No player or squadmate within SPAWN_UNSEEN_M has a clear line (world geometry) to `p`.
func _hidden(p: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var world := level.get_world_3d()
	for w: Soldier in _watchers():
		if w.global_position.distance_to(p) > SPAWN_UNSEEN_M:
			continue
		if Throwables.clear_line(world, w.global_position + Vector3.UP * 1.6, p + Vector3.UP * 1.4):
			return false
	return true


## Every patrol tick: a look whose rallying patrols are all at their points (or out of time)
## sends them in together.
func _tick_looks() -> void:
	for look: Dictionary in looks:
		var rallying := (look.patrols as Array).filter(func(r: Dictionary) -> bool:
			return r.has("look_rally") and not r.lost and now() < float(r.looking_until))
		if rallying.is_empty():
			continue
		var there := rallying.all(func(r: Dictionary) -> bool:
			var at := Virtualizer.lead(r)
			return not at.is_finite() or at.distance_to(r.look_rally) <= LOOK_RALLIED_M)
		if there or now() >= float(look.go_at):
			for r: Dictionary in rallying:
				r.looking_until = maxf(float(r.looking_until), now() + LOOK_S * 0.5)  # time to look once in
				_look_in(r, _living(r.soldiers), look.pos)


func _on_tier_changed(_tier_now: int) -> void:
	if multiplayer.is_server() and _started:
		server_tick()


# --- Trackers (host) ---------------------------------------------------------------------------

## `group` (a hunter team or a patrol record: "squad", "soldiers") on the squad's trail: picks it
## up near its lead, follows it; true while it's on it (its route set here), false otherwise.
func _track(group: Dictionary, living: Array) -> bool:
	var trail := SquadTrail.of(self)
	if trail == null or living.is_empty() or group.get("recalled", false) or group.has("rally"):
		return false
	var lead: Soldier = living[0]
	if not group.has("trail_mark"):
		var i := trail.nearest(lead.global_position, TRACK_PICKUP_M, TRACK_COLD_S)
		if i < 0:
			return false
		group["trail_mark"] = trail.marks[i]
		group["track_next"] = 0.0
		_signal(living, lead.global_position)
		print("[response] %s picks up the squad's trail at (%.0f, %.0f)" % [String((group.squad as Node).name) if is_instance_valid(group.squad) else "?", lead.global_position.x, lead.global_position.z])
	var idx := trail.marks.find(group.trail_mark)
	if idx < 0:
		group.erase("trail_mark")  # gone cold off the end of the record
		return false
	if now() < float(group.get("track_next", 0.0)):
		return true
	group.track_next = now() + TRACK_STEP_S
	var mark: Dictionary = trail.marks[idx]
	if Vector2(lead.global_position.x - mark.pos.x, lead.global_position.z - mark.pos.z).length() <= TRACK_NEAR_M:
		var nxt := trail.lead(idx)
		if nxt < 0:
			group.erase("trail_mark")  # the trail ends here: the squad is close
			return false
		var m2: Dictionary = trail.marks[nxt]
		if bool(m2.broken) or Soldier._now() - float(m2.t) > TRACK_COLD_S:  # (marks are on the game clock, not the alert's)
			group.erase("trail_mark")  # a road, water, or gone cold: lost it
			group["retarget_at"] = now()
			var search: Array[Vector3] = _search_ring(m2.pos, LOOK_RING_M)
			_set_route(group.squad, living, search)
			return false
		if trail.turn_at(nxt) > TRACK_TURN_DEG:
			group.track_next = now() + TRACK_TURN_PAUSE_S  # a hard turn: careful, it's where they'd wait
		group.trail_mark = m2
		mark = m2
	var route: Array[Vector3] = [_ground(mark.pos)]
	_set_route(group.squad, living, route)
	return true


## A named hunter squad's leader down: it's finished (Economy.server_nemesis_event), once.
func _check_nemesis(team: Dictionary) -> void:
	if not team.has("nemesis") or team.get("nemesis_done", false) or (team.soldiers as Array).is_empty():
		return
	var leader: Variant = team.soldiers[0]
	if not is_instance_valid(leader) or (leader as Soldier).vitals.is_dead():
		team["nemesis_done"] = true
		Economy.server_nemesis_event(String(team.nemesis), 0, true)
		var who := String((team.squad as Node).name) if is_instance_valid(team.squad) else "hunter squad"
		Contracts._notify_all("Word on the net: the %s lost their leader." % who)


## Signal shots: one of `living` fires TRACK_SIGNAL_SHOTS into the air and the net hears of the
## trail at `pos` (a "signal" report: a patrol comes to look).
func _signal(living: Array, pos: Vector3) -> void:
	var shooter: Soldier = living[0]
	for k in TRACK_SIGNAL_SHOTS:
		get_tree().create_timer(0.35 * k).timeout.connect(func() -> void:
			if is_instance_valid(shooter) and shooter.vitals.is_up():
				shooter._server_fire(shooter.global_position + Vector3.UP * 1.7, Vector3(0.05, 1.0, 0.0).normalized(), shooter.active_slot))
	if alert:
		alert._receive({"kind": &"signal", "pos": pos, "area": alert.area_of(pos), "by": ""})


# --- Pushes (host) ------------------------------------------------------------------------------

## `kind` "wave" (a Reinforcements wave record) or "hunters" (a hunter team) sent at `pos` joins
## the push on it (a new one if none is within PUSH_MERGE_M); two or more on it rally first.
func _join_push(kind: String, ref: Dictionary, pos: Vector3) -> void:
	var push: Dictionary = {}
	for p: Dictionary in pushes:
		if Vector2(pos.x - p.pos.x, pos.z - p.pos.z).length() <= PUSH_MERGE_M:
			push = p
			break
	if push.is_empty():
		push = {"pos": pos, "groups": [], "go_at": INF}
		pushes.append(push)
	(push.groups as Array).append({"kind": kind, "ref": ref})
	if (push.groups as Array).size() >= 2:
		_rally_push(push)


## Every group of `push` not already in close (inside PUSH_RALLY_M of the spot, not rallying)
## waits at its own rally point; the push goes in by PUSH_RALLY_S from now at the latest.
func _rally_push(push: Dictionary) -> void:
	var pos: Vector3 = push.pos
	var taken: Array[float] = []
	for g: Dictionary in push.groups:
		var ref: Dictionary = g.ref
		var living := _living(ref.get("soldiers", []))
		if Virtualizer.up(ref) == 0:
			continue
		var at := Virtualizer.lead(ref)
		if Vector2(at.x - pos.x, at.z - pos.z).length() <= PUSH_RALLY_M and not ref.has("rally"):
			continue  # already in close: it carries on
		var a := atan2(at.z - pos.z, at.x - pos.x)
		for b: float in taken:
			var off := wrapf(a - b, -PI, PI)
			if absf(off) < deg_to_rad(LOOK_SPLIT_DEG):
				a = b + (1.0 if off >= 0.0 else -1.0) * deg_to_rad(LOOK_SPLIT_DEG)
		var rally := _rally_point(pos, a, PUSH_RALLY_M)
		taken.append(atan2(rally.z - pos.z, rally.x - pos.x))
		if g.kind == "wave" and reinforcements:
			reinforcements.server_hold_at(ref, rally)
		else:
			ref["rally"] = rally
			var route: Array[Vector3] = [rally]
			_set_route(ref.squad, living, route)
	push.go_at = now() + PUSH_RALLY_S


## Every tick: a push whose rallying groups are all at their points (or out of time) goes in
## together; pushes with nobody left standing are dropped.
func _tick_pushes() -> void:
	for push: Dictionary in pushes.duplicate():
		var alive := (push.groups as Array).filter(func(g: Dictionary) -> bool: return Virtualizer.up(g.ref) > 0)
		if alive.is_empty():
			pushes.erase(push)
			continue
		var rallying := alive.filter(func(g: Dictionary) -> bool: return (g.ref as Dictionary).has("rally"))
		if rallying.is_empty():
			continue
		var there := rallying.all(func(g: Dictionary) -> bool:
			return Virtualizer.points(g.ref).any(func(at: Vector3) -> bool: return at.distance_to(g.ref.rally) <= PUSH_RALLIED_M))
		if there or now() >= float(push.go_at):
			for g: Dictionary in rallying:
				if g.kind == "wave" and reinforcements:
					reinforcements.server_release(g.ref)
				else:
					g.ref.erase("rally")
					g.ref["retarget_at"] = now()  # straight back onto the last known position
			print("[response] push on (%.0f, %.0f): %d groups go in together" % [push.pos.x, push.pos.z, rallying.size()])


# --- Hunters (host) -----------------------------------------------------------------------------

func _tick_hunters(tier: int) -> void:
	var c := coordination()
	var lk := alert.last_known() if alert else {}
	var teams := 0
	for team: Dictionary in hunters:
		var living := _living(team.soldiers)
		if Virtualizer.up(team) == 0:
			continue
		teams += 1
		_check_nemesis(team)
		if _track(team, living):
			pass  # on the squad's trail
		elif not lk.is_empty() and now() >= float(team.retarget_at) and not team.get("recalled", false) and not team.has("rally"):  # EnemyCommand called it home; a push holds it at its rally point
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
	# Wave 6d: a faction with heat (Economy.hunting) sends its hunters from tier 1, in any zone it holds.
	var hunted := tier >= 1 and Economy.hunting(String(enemy_faction))
	if (tier < 3 and not hunted) or lk.is_empty() or teams >= (2 if tier >= 4 else 1) or now() - _last_hunter < HUNTER_GAP_S \
			or HUNTER_SIZE.y > _room():
		return
	_send_hunters(lk.pos, float(lk.radius))


## A hunter team from the HQ (else the nearest QRF base, else the zone's edge) to `lkp`: a flank
## first if it's coordinated enough, then the position and a search round it. Waits (tries again
## next tick) while every way out is in sight.
func _send_hunters(lkp: Vector3, radius: float) -> void:
	var command := EnemyCommand.of(self)
	var c := coordination()
	var origin := _hunter_origin(lkp)
	if not origin.is_finite():
		return
	# Wave 6d: past "heat_named" the faction's named hunter squad comes, at full strength. Known
	# before the team is sized, so the reserves approved and spent (audit E-03) are what it fields.
	var named := Economy.heat(String(enemy_faction)) >= float(MissionRegistry.reputation_rules().get("heat_named", INF))
	var count := mini(HUNTER_SIZE.y if named else randi_range(HUNTER_SIZE.x, HUNTER_SIZE.y), _room())
	count = maxi(roundi(count * scale), mini(count, 2))  # by difficulty (ZoneLevel.difficulty_scale)
	if command:
		count = mini(count, floori(command.available_cp()))
		# Asked even with the reserves short of a team (for the smallest one): the denial is on
		# record and a stale LKP still gets its probe.
		if not command.approve("hunters", lkp, maxi(count, HUNTER_SIZE.x)):
			_last_hunter = now()  # turned down: asked again after HUNTER_GAP_S
			return
	if count < HUNTER_SIZE.x:
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
	# The named squad (raised only once the team is approved), better every time it comes.
	var nem: Dictionary = Economy.server_raise_nemesis(String(enemy_faction)) if named else {}
	var callsign := String(nem.name).replace(" ", "") if not nem.is_empty() else "HT%d" % _hunter_teams
	var combat := minf(HUNTER_COMBAT + NEMESIS_SKILL + NEMESIS_SKILL_PER_MEETING * int(nem.encounters), NEMESIS_SKILL_MAX) if not nem.is_empty() else HUNTER_COMBAT
	var discipline := minf(HUNTER_DISCIPLINE + NEMESIS_SKILL, 1.0) if not nem.is_empty() else HUNTER_DISCIPLINE
	var squad := _new_squad(callsign)
	squad.patrol = route
	var loadout: Array = (CompoundLevel.PMC_LOADOUT if enemy_faction == CompoundLevel.PMC_FACTION else CompoundLevel.HOSTILE_LOADOUT).duplicate()
	for i in HUNTER_SMOKES:
		loadout.append(String(SMOKE))
	var soldiers := _spawn_team(squad, callsign, count, origin, route[0], loadout,
		combat, discipline * c, "combat")
	if command:
		command.refund_men(count - soldiers.size())
	hunters.append({"k": _hunter_teams, "squad": squad, "soldiers": soldiers, "at": now(),
		"retarget_at": now() + HUNTER_RETARGET_S / c, "smoked": false})
	if not nem.is_empty() and not soldiers.is_empty():
		hunters.back()["nemesis"] = String(nem.id)
		(soldiers[0] as Soldier).person_name = String(nem.leader)
		(soldiers[0] as Soldier).set_meta(&"nemesis_leader", String(nem.id))
		# Kill attribution (6d's open item): every man in the named squad carries its id, so a
		# friendly it kills counts against it (Soldier._note_nemesis_kill, Economy.server_nemesis_event).
		for s: Soldier in soldiers:
			s.set_meta(&"nemesis", String(nem.id))
		Economy.server_nemesis_met(String(nem.id))
		Contracts._notify_all("Word on the net: the %s are hunting you%s." % [nem.name, " again" if int(nem.encounters) > 0 else ""])
	_virtualize(hunters.back(), "hunters")
	_join_push("hunters", hunters.back(), lkp)
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
## never past SPAWN_BUDGET. The pair is named under the site ("<site>_HR<k>_<i>"): it counts as
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
		if sent >= REINFORCE_MAX or 2 > _room():
			break
		if not (ZoneModules.base(m.type) in REINFORCE_TYPES) or had == null or int(had.get(m.module_id, 0)) <= 0 or level.call(&"site_down", m.module_id):
			continue
		if reinforcement_pairs.any(func(p: Dictionary) -> bool: return p.to == m.module_id and Virtualizer.up(p) > 0):
			continue  # already has one
		var from := _unseen_gate(hq, m.global_position)
		if not from.is_finite():
			break  # the HQ is watched: no one leaves it this round
		var command := EnemyCommand.of(self)
		if command and not command.request_men(2, "pair to %s" % m.module_id):
			break  # the commander says no (reserves, consolidating, or nobody in command)
		sent += 1
		var k := reinforcement_pairs.size() + 1
		var callsign := ("%s_HR%d" % [m.module_id, k]).validate_node_name()
		var squad := _new_squad(callsign)
		var to := _gate(m, hq.global_position)
		var to_route: Array[Vector3] = [to]
		squad.patrol = to_route
		var soldiers := _spawn_team(squad, callsign, 2, from, to, CompoundLevel.HOSTILE_LOADOUT,
			float(stats.combat), float(stats.discipline), alert.mode_at(from) if alert else "aware")
		if command:
			command.refund_men(2 - soldiers.size())
		reinforcement_pairs.append({"k": k, "to": m.module_id, "squad": squad, "soldiers": soldiers, "at": now()})
		_virtualize(reinforcement_pairs.back(), "pair")


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


## Living soldiers the zone's answer has out: this node's (_alive_spawned) and the QRF waves'.
func alive_total() -> int:
	return _alive_spawned() + (reinforcements.capped_alive() if reinforcements else 0)


## The budget now: SPAWN_BUDGET at the current tier, eased in from RAMP_START over ESCALATE_S.
func spawn_budget() -> int:
	var cap := SPAWN_BUDGET[clampi(_tier(), 0, SPAWN_BUDGET.size() - 1)]
	return mini(cap, RAMP_START + int(round((SPAWN_BUDGET.back() - RAMP_START) * escalation())))


## How far into the escalation ramp the zone is, 0 to 1 (smoothstep over ESCALATE_S).
func escalation() -> float:
	return smoothstep(0.0, ESCALATE_S, now() - _started_at) if _started else 0.0


## How many more may spawn now (0 at or over the budget).
func _room() -> int:
	return maxi(spawn_budget() - alive_total(), 0)


## Living soldiers this node spawned (patrols, hunters, HQ pairs), live or virtual.
func _alive_spawned() -> int:
	var count := 0
	for list: Array in [patrols, hunters, reinforcement_pairs]:
		for record: Dictionary in list:
			count += Virtualizer.up(record)
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
		var kit := loadout
		var mix_i := callsign.hash() + i  # where in the mix this soldier starts
		var role := "medic" if size >= TEAM_MEDIC_MIN and i == TEAM_MEDIC_INDEX else ""
		if loadout.size() >= CompoundLevel.HOSTILE_LOADOUT.size() and loadout.slice(0, CompoundLevel.HOSTILE_LOADOUT.size()) == CompoundLevel.HOSTILE_LOADOUT:
			# OPFOR: this team's mix of AKs, gunner and marksman (callsign picks where in the mix it starts)
			kit = CompoundLevel.hostile_loadout(mix_i) + loadout.slice(CompoundLevel.HOSTILE_LOADOUT.size())
			role = CompoundLevel.hostile_role(mix_i) if role == "" else role
		var exo := ""
		var variant := "urban"
		var fid := String(enemy_faction)  # who he fights for (his doctrine, the war's tally)
		var kit_id := Kits.kit_of(enemy_faction)
		if Kits.is_data(kit_id) and loadout.size() >= CompoundLevel.HOSTILE_LOADOUT.size() and loadout.slice(0, CompoundLevel.HOSTILE_LOADOUT.size()) == CompoundLevel.HOSTILE_LOADOUT:
			# Wave 6b: a faction with a data kit (a regional army) fields its own gear and camo.
			kit = Kits.loadout(kit_id, mix_i, difficulty) + loadout.slice(CompoundLevel.HOSTILE_LOADOUT.size())
			role = Kits.role(kit_id, mix_i) if role == "" else role
			variant = Kits.variant(kit_id, mix_i)
		elif loadout.size() >= CompoundLevel.PMC_LOADOUT.size() and loadout.slice(0, CompoundLevel.PMC_LOADOUT.size()) == CompoundLevel.PMC_LOADOUT:
			# Vantage Group: M4s, SCAR-Hs, and the M240B/ammo bearer pair (same mix idea as OPFOR above)
			kit = CompoundLevel.rival_pmc_loadout(mix_i, difficulty) + loadout.slice(CompoundLevel.PMC_LOADOUT.size())
			role = CompoundLevel.rival_pmc_role(mix_i) if role == "" else role
			exo = CompoundLevel.rival_pmc_exo_at(mix_i, difficulty)
			variant = "black"  # Captain, 2026-10-17: "black for enemy pmc"
			fid = String(CompoundLevel.PMC_FACTION)  # Vantage's men are Vantage's (its own doctrine), whoever holds the zone
		var spawn := {"name": "%s_%d" % [callsign, i + 1], "faction": "hostile",
			"variant": variant, "pos": pos, "loadout": kit, "combat": combat, "discipline": discipline,
			"guard": false, "mode": mode, "role": role, "exo": exo, "faction_id": fid,
			"iff": "militia" if MissionRegistry.faction_side(fid) == "militia" else ""}  # (terror groups: orange marks for a militia)
		var s: Soldier = level.call(&"spawn_soldier", spawn)
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


## Enemy vehicles beyond the QRFs (Captain's queue, 2026-10-15): a patrol with a long way to go
## (PATROL_RIDE_MIN_M of route) rides a technical PATROL_RIDE_SHARE of the time (by the zone's
## patrol number, so a zone plays the same): it drives toward the far end of its route, gets out
## and walks the rest (VehicleQrf.server_mount, no base: parked by its first point).
const PATROL_RIDE_MIN_M := 400.0
const PATROL_RIDE_SHARE := 0.3


func _maybe_ride(record: Dictionary, route: Array[Vector3]) -> void:
	if route.size() < 2 or record.get("second", false):
		return
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i - 1].distance_to(route[i])
	var roll := float(absi(hash("%s|patrol%d" % [level.name, int(record.k)])) % 1000) / 1000.0
	if length < PATROL_RIDE_MIN_M or roll >= PATROL_RIDE_SHARE:
		return
	var far: Vector3 = route[0]
	for p: Vector3 in route:
		if p.distance_to(route[0]) > far.distance_to(route[0]):
			far = p
	VehicleQrf.server_mount(level, null, route[0], far, record.soldiers)
