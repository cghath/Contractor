class_name Alert
extends Node
## A hot zone's alert (4B part 3, Captain 2026-10-12: "somewhat more realistic"): the enemy only
## knows what its own people see, hear and report, and news travels by radio, with delays.
##
## - Local first: a hostile who hears a shot or a blast, or sees one of the squad, reacts at
##   once (his area stands to); the rest of the zone only learns when he radios it in, after
##   REPORT_DELAY_S (by his discipline; longer under fire; COMMS_DOWN_MULT slower once the comms
##   site's mast is down). Killed or downed before then, the report dies with him.
## - Sound: an unsuppressed shot is heard to SHOT_HEARD_M, a suppressed one to
##   SUPPRESSED_HEARD_M, a blast to BLAST_HEARD_M. Hearing gives a rough direction, not who.
## - Check-ins: each garrisoned site radios in every CHECK_IN_S; a site with nobody left to
##   answer is missed, and the HQ hears of it CHECK_IN_CALL_S later.
## - Bodies: a hostile who comes within BODY_SPOT_M of a fallen comrade (in sight) reports it.
## - The enemy works from a last known position (lkp) whose uncertainty grows with time.
## - States, per area (a site, or the open ground) and for the zone: NORMAL (routine), SUSPICIOUS
##   (stand-to), ALERTED (posts manned, QRF on standby), ENGAGED (the QRF launches: stage 3).
##   Cooldown is slow: ENGAGED to ALERTED after ENGAGED_COOL_S without contact, ALERTED to
##   SUSPICIOUS after ALERTED_COOL_S; once alerted, a zone doesn't relax below SUSPICIOUS.
## - Hostiles' combat modes follow their area's state (SAFE, AWARE, COMBAT).
## No meter on screen (Captain): players read it from behaviour and, later, looted radio chatter
## (`reported`). Host only; one node per hot zone ("Alert", ZoneLevel). All numbers Proposed.

enum State { NORMAL, SUSPICIOUS, ALERTED, ENGAGED }
const STATE_NAMES: Array[String] = ["normal", "suspicious", "alerted", "engaged"]
const SHOT := &"shot"
const BLAST := &"blast"
## Report kinds and the state each raises its area to (the zone follows its worst area).
const RAISES := {&"shot": State.SUSPICIOUS, &"blast": State.ALERTED, &"contact": State.ENGAGED,
	&"body": State.ALERTED, &"missed_checkin": State.ALERTED}

const SHOT_HEARD_M := 600.0
## A contact report counts the squad within this of what was seen (EnemyCommand's fog).
const SEEN_GROUP_M := 25.0
const SUPPRESSED_HEARD_M := 80.0
const BLAST_HEARD_M := 1200.0
## Seconds from hearing or seeing to the report arriving: lerp by discipline (high is quick).
const REPORT_DELAY_S := Vector2(60.0, 15.0)
const REPORT_UNDER_FIRE_MULT := 1.5
const COMMS_DOWN_MULT := 3.0
## How long one man waits before he'll report the same kind of thing again.
const REPORT_GAP_S := 30.0
const CHECK_IN_S := Vector2(900.0, 1200.0)
const CHECK_IN_CALL_S := 60.0
const BODY_SPOT_M := 25.0
const ENGAGED_COOL_S := 1200.0
const ALERTED_COOL_S := 5400.0
## The last known position's uncertainty: grows this fast (m/s) up to LKP_MAX_M.
const LKP_GROWTH_MPS := 1.5
const LKP_MAX_M := 600.0
## A point further than this from every site is "field".
const AREA_REACH_M := 400.0
const FIELD := "field"
## How often the slow checks run (bodies, check-ins, cooldown, the comms mast).
const SCAN_S := 2.0
const COMMS_DOWN_SHARE := 0.5

## Host: update the commander's intelligence before report-driven reactions run.
signal report_received(report: Dictionary)
## Host: a report reached the enemy's radio net: {"kind", "pos", "area", "by", "time"}.
signal reported(report: Dictionary)
## Host: an area's state (or "zone"'s) changed.
signal state_changed(area: String, state: int)
## Host: a shot or a blast went off at `pos`, heard or not (Pressure counts the squad's blasts).
signal noise(kind: StringName, pos: Vector3, source: Node)

var zone_state := State.NORMAL
var areas := {}           # area id -> {"state", "contact" (last contact time), "since"}
var lkp := {}             # {"pos": Vector3, "time": float}, or {} before any report
var reports: Array = []   # every report received, oldest first
var comms_down := false
var level: Node3D
var _pending: Array = []  # {"by": Soldier, "report": Dictionary, "due": float}
var _overdue: Array = []  # wiped patrols' missed check-ins: {"report", "due"}
var _last_report := {}    # "<name>|<kind>" -> time
var _check_ins := {}      # module id -> next check-in time
var _seen_bodies := {}    # body instance id -> true
var _scan := 0.0
var _now_offset := 0.0    # tests: skips time forward (advance())


func _init() -> void:
	name = "Alert"


func _ready() -> void:
	level = get_parent() as Node3D


## The alert of the level `from` is in (null outside a hot zone).
static func of(from: Node) -> Alert:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"Alert") as Alert if lvl else null


func now() -> float:
	return Soldier._now() + _now_offset


## Tests: moves this alert's clock `seconds` forward (reports come due, cooldowns run).
func advance(seconds: float) -> void:
	_now_offset += seconds
	_tick(true)


# --- What the enemy perceives (host) ---------------------------------------------------------

## A shot or a blast at `pos` (`kind` SHOT or BLAST); `suppressed` shots carry less far. Every
## hostile who hears it stands to and will report it. `source` (the shooter) never hears himself.
static func server_noise(source: Node, pos: Vector3, kind: StringName, suppressed := false) -> void:
	var alert := of(source)
	if alert == null or not alert.multiplayer.is_server():
		return
	alert.noise.emit(kind, pos, source)
	var heard := BLAST_HEARD_M if kind == BLAST else (SUPPRESSED_HEARD_M if suppressed else SHOT_HEARD_M)
	for s: Soldier in alert._hostiles():
		if s != source and s.global_position.distance_to(pos) <= heard:
			alert._perceive(s, kind, pos)


## `observer` (a hostile) sees one of the squad at `pos`.
static func server_sighting(observer: Soldier, pos: Vector3) -> void:
	var alert := of(observer)
	if alert and alert.multiplayer.is_server() and observer.faction == &"hostile":
		alert._perceive(observer, &"contact", pos)


## `s` perceived `kind` at `pos`: his own area stands to at once (at least SUSPICIOUS, ENGAGED
## for contact), and he'll radio it in unless he's already reporting the same.
func _perceive(s: Soldier, kind: StringName, pos: Vector3) -> void:
	var area := area_of(s.global_position)
	_raise(area, State.ENGAGED if kind == &"contact" else State.SUSPICIOUS, kind == &"contact", false)  # local: the zone hears of it later
	var key := "%s|%s" % [s.name, kind]
	if now() - float(_last_report.get(key, -INF)) < REPORT_GAP_S:
		return
	_last_report[key] = now()
	var ai := SquadAI.of(s)
	var discipline := float(ai.discipline) if ai else 0.5
	var delay := lerpf(REPORT_DELAY_S.x, REPORT_DELAY_S.y, clampf(discipline, 0.0, 1.0))
	if ai and ai.in_contact():
		delay *= REPORT_UNDER_FIRE_MULT
	if comms_down:
		delay *= COMMS_DOWN_MULT
	var report := {"kind": kind, "pos": pos, "area": area, "by": String(s.name)}
	if kind == &"contact":
		report.merge(_seen_at(pos))
	_pending.append({"by": s, "due": now() + delay, "report": report})


## What a contact report says it saw at `pos` (EnemyCommand's fog): how many of the squad
## (players and squad AI) up within SEEN_GROUP_M, and how many of those in a working exo frame.
func _seen_at(pos: Vector3) -> Dictionary:
	var men := 0
	var exo := 0
	var squad := MapNodes.players(self)
	squad.append_array(MapNodes.squad_ai(self))
	for p: Soldier in squad:
		if p.vitals.is_up() and p.global_position.distance_to(pos) <= SEEN_GROUP_M:
			men += 1
			if ExoFrame.working(p.inventory):
				exo += 1
	return {"seen": maxi(men, 1), "exo": exo}


# --- The radio net (host) ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if multiplayer.is_server():
		_tick(false)


func _tick(force_scan: bool) -> void:
	var t := now()
	for p: Dictionary in _pending.duplicate():
		var by: Soldier = p.by if is_instance_valid(p.by) else null
		if by == null or not by.vitals.is_up():
			_pending.erase(p)  # he never got it out
		elif t >= float(p.due):
			_pending.erase(p)
			_receive(p.report)
	for o: Dictionary in _overdue.duplicate():
		if t >= float(o.due):
			_overdue.erase(o)
			_receive(o.report)
	_scan -= get_process_delta_time()
	if _scan > 0.0 and not force_scan:
		return
	_scan = SCAN_S
	_scan_bodies()
	_check_in()
	_cool_down(t)
	_check_comms()


## A report reached the net: the last known position moves there and its area (and so the
## zone) rises.
func _receive(report: Dictionary) -> void:
	var r := report.duplicate()
	r["time"] = now()
	reports.append(r)
	if r.kind in [&"contact", &"shot", &"blast", &"body"]:
		lkp = {"pos": r.pos, "time": r.time}
	# Record the commander's picture before listeners react to this report. A first
	# sighting must already be confirmed when the response asks permission to launch.
	report_received.emit(r)
	_raise(String(r.area), int(RAISES.get(r.kind, State.SUSPICIOUS)), r.kind == &"contact", true)
	reported.emit(r)


## `area` rises to `to` (and its hostiles take up the mode); with `on_net` (a report that reached
## the radio net) the zone follows its worst area.
func _raise(area: String, to: int, contact := false, on_net := true) -> void:
	var a: Dictionary = areas.get(area, {"state": State.NORMAL, "contact": -INF, "since": now()})
	if contact or to == State.ENGAGED:
		a.contact = now()
	if to > int(a.state):
		a.state = to
		a.since = now()
		areas[area] = a
		state_changed.emit(area, to)
		_apply_modes(area)
	areas[area] = a
	if not on_net:
		return
	var worst := State.NORMAL
	for k: String in areas:
		worst = maxi(worst, int(areas[k].state))
	if worst > zone_state:
		zone_state = worst
		state_changed.emit("zone", zone_state)
		_apply_modes("")


## Slow cooldown: ENGAGED to ALERTED, ALERTED to SUSPICIOUS; never below SUSPICIOUS once raised.
func _cool_down(t: float) -> void:
	var changed := false
	for k: String in areas:
		var a: Dictionary = areas[k]
		var quiet := t - maxf(float(a.contact), float(a.since))
		var was := int(a.state)
		if was == State.ENGAGED and t - float(a.contact) >= ENGAGED_COOL_S:
			a.state = State.ALERTED
			a.since = t
		elif was == State.ALERTED and quiet >= ALERTED_COOL_S:
			a.state = State.SUSPICIOUS
			a.since = t
		if int(a.state) != was:
			changed = true
			state_changed.emit(k, int(a.state))
	if changed:
		var worst := State.NORMAL
		for k: String in areas:
			worst = maxi(worst, int(areas[k].state))
		if worst < zone_state and maxi(worst, State.SUSPICIOUS) != zone_state:
			zone_state = maxi(worst, State.SUSPICIOUS)  # cooling only lowers: the zone rises by reports alone
			state_changed.emit("zone", zone_state)
		_apply_modes("")


## Fallen hostiles found by their own: anyone up within BODY_SPOT_M, in sight, reports it once.
func _scan_bodies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var watchers := _hostiles()
	for n in tree.get_nodes_in_group(Soldier.DEAD_GROUP):
		var body := n as Soldier
		if body == null or body.faction != &"hostile" or _seen_bodies.has(body.get_instance_id()):
			continue
		for s: Soldier in watchers:
			if s.global_position.distance_to(body.global_position) <= BODY_SPOT_M \
					and Throwables.clear_line(s.get_world_3d(), s.global_position + Vector3.UP * 1.6, body.global_position + Vector3.UP * 0.3):
				_seen_bodies[body.get_instance_id()] = true
				_perceive(s, &"body", body.global_position)
				break


## Check-ins: each site with a garrison answers every CHECK_IN_S; one with nobody left to answer
## is missed, and the net learns of it CHECK_IN_CALL_S later (no one to blame: no "by").
func _check_in() -> void:
	if not level or not level.has_method(&"modules"):
		return
	var t := now()
	for m: ZoneModule in level.call(&"modules"):
		if not _check_ins.has(m.module_id):
			_check_ins[m.module_id] = t + randf_range(CHECK_IN_S.x, CHECK_IN_S.y)
			continue
		if t < float(_check_ins[m.module_id]):
			continue
		_check_ins[m.module_id] = t + randf_range(CHECK_IN_S.x, CHECK_IN_S.y)
		var prefix := ("%s_H" % m.module_id).validate_node_name()  # not outpost_10's men for outpost_1
		var garrison := _hostiles().filter(func(s: Soldier) -> bool: return String(s.name).begins_with(prefix))
		var had := level.get(&"_garrisoned") as Dictionary
		var coming := int(level.call(&"garrison_pending", m.module_id)) if level.has_method(&"garrison_pending") else 0
		if garrison.is_empty() and had != null and int(had.get(m.module_id, 0)) > 0 and coming == 0:  # not while it's still coming out
			var pos: Vector3 = m.global_position
			get_tree().create_timer(CHECK_IN_CALL_S).timeout.connect(func() -> void:
				_receive({"kind": &"missed_checkin", "pos": pos, "area": m.module_id, "by": ""}))


## The comms site's mast: under COMMS_DOWN_SHARE of it left, reports slow (COMMS_DOWN_MULT).
func _check_comms() -> void:
	if comms_down or not level or not level.has_method(&"modules"):
		return
	for m: ZoneModule in level.call(&"modules"):
		if m.type != "comms" or m.voxel_world == null:
			continue
		var site := MissionRegistry.site("comms", "cache")
		var box: Array = site.get("box", [])
		if box.size() != 2:
			continue
		var lo := m.to_global(Vector3(box[0][0], box[0][1], box[0][2]))
		var hi := m.to_global(Vector3(box[1][0], box[1][1], box[1][2]))
		var left := Objectives.solid_count(m.voxel_world, AABB(lo.min(hi), (hi - lo).abs()))
		var full := ZoneModules.solid_voxels_in("comms", AABB(Vector3(box[0][0], box[0][1], box[0][2]),
			(Vector3(box[1][0], box[1][1], box[1][2]) - Vector3(box[0][0], box[0][1], box[0][2])).abs()))
		if left >= 0 and full > 0 and float(left) / full < COMMS_DOWN_SHARE:
			comms_down = true


## Host: `area` goes to at least ALERTED without the zone hearing of it (checkpoints closed
## under pressure: EnemyResponse): its hostiles man their posts in combat mode.
func server_stand_to(area: String) -> void:
	if state_of(area) < State.ALERTED:
		_raise(area, State.ALERTED, false, false)


## Host: a roaming patrol last seen at `pos` stopped answering (wiped out): it misses its next
## check-in, `after_s` from now, and the net hears of it CHECK_IN_CALL_S after that.
## On this alert's clock (advance() brings it due).
func server_overdue(pos: Vector3, after_s: float) -> void:
	_overdue.append({"due": now() + after_s + CHECK_IN_CALL_S,
		"report": {"kind": &"missed_checkin", "pos": pos, "area": area_of(pos), "by": "", "patrol": true}})


# --- Queries ------------------------------------------------------------------------------------

## The area `pos` is in: the nearest site within AREA_REACH_M, else FIELD.
func area_of(pos: Vector3) -> String:
	var best := AREA_REACH_M
	var out := FIELD
	if level and level.has_method(&"modules"):
		for m: ZoneModule in level.call(&"modules"):
			var d := Vector2(m.global_position.x - pos.x, m.global_position.z - pos.z).length()
			if d < best:
				best = d
				out = m.module_id
	return out


func state_of(area: String) -> int:
	return int((areas.get(area, {}) as Dictionary).get("state", State.NORMAL))


## The state a hostile at `pos` acts on: his area's, or the zone's if that's higher than
## SUSPICIOUS (a zone on alert has everyone stood to).
func state_at(pos: Vector3) -> int:
	return maxi(state_of(area_of(pos)), mini(zone_state, State.SUSPICIOUS))


## The combat mode name (Squad.COMBAT_MODES) for a hostile at `pos`.
func mode_at(pos: Vector3) -> String:
	match state_at(pos):
		State.NORMAL:
			return "safe"
		State.SUSPICIOUS:
			return "aware"
	return "combat"


## The last known position and how uncertain it is now (m), or {} before any report.
func last_known() -> Dictionary:
	if lkp.is_empty():
		return {}
	return {"pos": lkp.pos, "radius": minf((now() - float(lkp.time)) * LKP_GROWTH_MPS, LKP_MAX_M)}


func _hostiles() -> Array[Soldier]:
	var out: Array[Soldier] = []
	var lvl := level as CompoundLevel
	if lvl == null:
		return out
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_in_group(Soldier.DEAD_GROUP):
			out.append(s)
	return out


## Every hostile in `area` ("" for all) takes up the mode its state calls for.
func _apply_modes(area: String) -> void:
	for s: Soldier in _hostiles():
		if area != "" and area_of(s.global_position) != area:
			continue
		var ai := SquadAI.of(s)
		if ai:
			ai.combat_mode = Squad.COMBAT_MODES[mode_at(s.global_position)]
