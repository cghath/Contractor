class_name Pressure
extends Node
## A hot zone's pressure (4B part 3, Captain 2026-10-12): how hard the enemy pushes back, long
## term, from what the squad does there, not from the clock. Points (GAINS):
## - a firefight +2 (contact after FIREFIGHT_GAP_S without), +1 more per FIREFIGHT_LONG_S it lasts;
## - a hostile killed +0.5; an explosion of ours +1;
## - a patrol wiped out, or a site that stops reporting (a missed check-in) +3 (a site already
##   counted as destroyed, below, isn't counted again: in practice the comms site and villages);
## - an objective done +5; an outpost, checkpoint, QRF base or the HQ taken out (its garrison
##   gone: ZoneLevel.site_down) +8; an alarm raised (the zone reaching ALERTED) +3;
## - quiet: -1 per QUIET_S without a gain; time alone: +1 per TIME_S;
## - staying (Captain 2026-10-15: "pressure rises the longer the squad stays"): quiet never
##   takes the points below stay_floor(), STAY_FLOOR for every STAY_FLOOR_S in the zone, and
##   they rise to it ("stay") when under it: about tier 1 after 2 hours, tier 2 after 4, quiet
##   or not. Staying pays more too (HotZoneOps' hazard pay).
## A destroyed comms site (Alert.comms_down) halves every gain. Tiers at TIERS (10, 20, 35, 50):
## what each brings is EnemyResponse's. No meter on screen. Host only; one node per hot zone
## ("Pressure", ZoneLevel). It runs on the Alert's clock (tests jump it with Alert.advance and
## then server_tick). All numbers Proposed.

## Host: points changed (`why`: a GAINS key, "quiet").
signal changed(points: float, why: String)
## Host: the tier (0 to TIERS.size()) changed.
signal tier_changed(tier: int)

const GAINS := {"firefight": 2.0, "firefight_long": 1.0, "kill": 0.5, "explosion": 1.0, "patrol_lost": 3.0,
	"not_reporting": 3.0, "objective": 5.0, "site_destroyed": 8.0, "alarm": 3.0, "time": 1.0}
const TIERS: Array[float] = [10.0, 20.0, 35.0, 50.0]
## Contact after this long without starts a new firefight.
const FIREFIGHT_GAP_S := 90.0
const FIREFIGHT_LONG_S := 180.0
const QUIET_S := 600.0
const QUIET_LOSS := 1.0
const STAY_FLOOR_S := 1800.0
const STAY_FLOOR := 2.5
const TIME_S := 1800.0
const COMMS_DOWN_GAIN := 0.5
## Sites whose loss counts as one destroyed.
const SITE_TYPES: Array[String] = ["outpost", "checkpoint", "qrf_base", "hq"]
const SCAN_S := 2.0

var points := 0.0
## Every change: {"why", "gain", "time"}.
var history: Array = []
var alert: Alert
var level: Node3D
var _tier := 0
var _start := 0.0
var _times_paid := 0
var _last_gain := 0.0
var _last_quiet := 0.0
var _contact_since := -INF
var _contact_last := -INF
var _long_paid := 0
var _counted_dead := {}   # instance id -> true
var _done := {}           # objective oid -> true
var _down := {}           # module id -> true
var _zone_state := Alert.State.NORMAL
var _scan := 0.0


func _init() -> void:
	name = "Pressure"


func _ready() -> void:
	level = get_parent() as Node3D
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	if alert:
		alert.reported.connect(_on_reported)
		alert.state_changed.connect(_on_state_changed)
		alert.noise.connect(_on_noise)
	Contracts.objectives.changed.connect(_on_objectives)
	_start = now()
	_last_gain = _start
	_last_quiet = _start
	for o: Dictionary in Contracts.objectives.list:
		if o.state == Objectives.DONE:
			_done[String(o.oid)] = true  # done before this zone: not ours to count


func _exit_tree() -> void:
	if Contracts.objectives.changed.is_connected(_on_objectives):
		Contracts.objectives.changed.disconnect(_on_objectives)


## The pressure of the level `from` is in (null outside a hot zone).
static func of(from: Node) -> Pressure:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"Pressure") as Pressure if lvl else null


func now() -> float:
	return alert.now() if alert else Soldier._now()


## 0 below TIERS[0], 1 from 10, ... 4 from 50.
func tier() -> int:
	var t := 0
	for at in TIERS:
		if points >= at:
			t += 1
	return t


## Host: `why` (a GAINS key) happened `times` times. Gains are halved with the comms site down.
func server_add(why: String, times := 1.0) -> void:
	var gain := float(GAINS.get(why, 0.0)) * times
	if gain <= 0.0:
		return
	_heat(why, times)
	if alert and alert.comms_down:
		gain *= COMMS_DOWN_GAIN
	if why != "time":
		_last_gain = now()
		_last_quiet = _last_gain
	_change(gain, why)


func _change(gain: float, why: String) -> void:
	var was := points
	points = maxf(points + gain, 0.0)
	if points == was:
		return
	history.append({"why": why, "gain": points - was, "time": now()})
	changed.emit(points, why)
	var t := tier()
	if t != _tier:
		_tier = t
		print("[pressure] %.1f (%s): tier %d" % [points, why, t])
		tier_changed.emit(t)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		server_tick()


## Host: the slow checks (contact, the fallen, sites taken, quiet and time). Every SCAN_S.
func server_tick() -> void:
	var t := now()
	note_contact(_any_contact(), t)
	_count_dead()
	_count_sites()
	while t - _last_quiet >= QUIET_S:
		_last_quiet += QUIET_S
		_change(-minf(QUIET_LOSS, maxf(points - stay_floor(), 0.0)), "quiet")
	var due := floori((t - _start) / TIME_S)
	if due > _times_paid:
		server_add("time", due - _times_paid)
		_times_paid = due
	if points < stay_floor():
		_change(stay_floor() - points, "stay")


## The least pressure the squad has after this long in the zone: STAY_FLOOR per STAY_FLOOR_S.
func stay_floor() -> float:
	return floorf(maxf(now() - _start, 0.0) / STAY_FLOOR_S) * STAY_FLOOR


## Contact (`contact`: any hostile fighting the squad at `t`): a new firefight, or a long one.
func note_contact(contact: bool, t: float) -> void:
	if not contact:
		return
	if t - _contact_last > FIREFIGHT_GAP_S:
		_contact_since = t
		_long_paid = 0
		server_add("firefight")
	# Absolute clocks can lose a fraction of a microsecond when subtracted at the boundary.
	var long := floori((t - _contact_since + 0.000001) / FIREFIGHT_LONG_S)
	if long > _long_paid:
		server_add("firefight_long", long - _long_paid)
		_long_paid = long
	_contact_last = t


func _any_contact() -> bool:
	var lvl := level as CompoundLevel
	if lvl == null:
		return false
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up():
			var ai := SquadAI.of(s)
			if ai and ai.in_contact():
				return true
	return false


func _count_dead() -> void:
	var lvl := level as CompoundLevel
	if lvl == null:
		return
	var fallen := 0
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_dead() and not _counted_dead.has(s.get_instance_id()):
			_counted_dead[s.get_instance_id()] = true
			var by := Harm.last(s)
			if by.is_empty() or Harm.by_company(by):
				fallen += 1  # (only the company's kills, or unknown: never a rival team's or an ally's)
	if fallen > 0:
		server_add("kill", fallen)


func _count_sites() -> void:
	if level == null or not level.has_method(&"site_down"):
		return
	for m: ZoneModule in level.call(&"modules"):
		if ZoneModules.base(m.type) in SITE_TYPES and not _down.has(m.module_id) and level.call(&"site_down", m.module_id):
			_down[m.module_id] = true
			server_add("site_destroyed")


func _on_reported(report: Dictionary) -> void:
	if report.kind != &"missed_checkin" or report.get("patrol", false):
		return  # a wiped patrol was counted when it fell (EnemyResponse)
	_count_sites()
	if not _down.has(String(report.area)):
		server_add("not_reporting")


func _on_state_changed(area: String, state: int) -> void:
	if area != "zone":
		return
	if state >= Alert.State.ALERTED and _zone_state < Alert.State.ALERTED:
		server_add("alarm")
	_zone_state = state


## Our blasts count (a grenade an enemy threw doesn't); shots are counted as firefights.
func _on_noise(kind: StringName, _pos: Vector3, source: Node) -> void:
	if kind != Alert.BLAST:
		return
	var by: Variant = source.get(&"thrower") if is_instance_valid(source) else null
	var thrower := by as Soldier if by is Object and is_instance_valid(by) else null
	if thrower and thrower.faction == &"hostile":
		return
	server_add("explosion")


func _on_objectives() -> void:
	if not multiplayer.is_server():
		return
	for o: Dictionary in Contracts.objectives.list:
		var oid := String(o.oid)
		if o.state == Objectives.DONE and not _done.has(oid):
			_done[oid] = true
			server_add("objective")


## Wave 6d: the zone's enemy faction (EnemyResponse.enemy_faction) takes the squad's kills and
## sites taken out as heat (Economy.add_heat; factions.json "heat_kill", "heat_site").
func _heat(why: String, times: float) -> void:
	if why != "kill" and why != "site_destroyed":
		return
	var response := level.get_node_or_null(^"EnemyResponse") if level else null
	var faction := String(response.get(&"enemy_faction")) if response else "black_ridge"
	var rules := MissionRegistry.reputation_rules()
	Economy.add_heat(faction, float(rules.get("heat_kill" if why == "kill" else "heat_site", 0.0)) * times)
