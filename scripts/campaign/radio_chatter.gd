class_name RadioChatter
extends Node
## Looted enemy radio chatter (4B part 3, Captain 2026-10-12): there is no alert meter, so a
## squad that takes an enemy handheld radio ("enemy_radio", one per RADIO_EVERY men of a
## garrison: ZoneLevel) off a body hears the enemy's net: the reports that reach it (Alert's
## `reported`), the zone standing to or standing down (`state_changed` for "zone") and, now and
## then (QRF_HEAR_CHANCE), a QRF wave setting out (Reinforcements' `wave_spawned`).
##
## - Taken: a player or a squad AI who is not dead carries one (loose, in a pouch or a pack).
##   The squad listens while it holds more radios than have gone stale.
## - The switch: once the net has a body found or a missed check-in reported after the squad
##   took its radio, the enemy changes frequency FREQ_SWITCH_S later. Every radio the squad
##   holds then goes stale and chatter stops. Another radio taken after that (one more held
##   than are stale) listens in again, and the clock starts over.
## - Lines are vague, like real chatter: a callsign (CALLSIGNS by site type, numbered in the
##   zone's module order), what happened and a compass word ("Outpost 2: shots heard, to the
##   north."), never a position. North is -Z.
## - Delivery: the host decides and sends each line through Callouts (its `_show` RPC) to the
##   players on the carrier's side, as a subtitle from SPEAKER, at most one per LINE_GAP_S
##   (QUEUE_MAX waiting, the oldest dropped). A line the squad doesn't catch (HEAR_CHANCE) is
##   lost in the static.
## Host only; one node per hot zone ("RadioChatter", ZoneLevel). It runs on the Alert's clock.
## All numbers Proposed.

## Host: a line went out to the squad.
signal line_sent(text: String)
## Host: the squad started or stopped hearing the enemy's net.
signal tuned_changed(tuned: bool)

const ENEMY_TAG := "enemy_radio"
## The squad's own field radio: tagged "radio" but not ENEMY_TAG (Contracts' radio contracts).
const FIELD_TAG := "radio"
## Seconds from the enemy's first suspicion (a body or a missed check-in) to the switch.
const FREQ_SWITCH_S := Vector2(300.0, 600.0)
const HEAR_CHANCE := 0.85
const QRF_HEAR_CHANCE := 0.6
const LINE_GAP_S := 5.0
const QUEUE_MAX := 3
## Closer than this to its own site, a report has no direction ("at our position").
const NEAR_M := 60.0
## How often the squad's radios are counted.
const SCAN_S := 1.0
const SPEAKER := "Enemy radio"
const LINE_ID := &"enemy_chatter"
const COMPASS: Array[String] = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
## Site callsigns by module type; others take their type's name.
const CALLSIGNS := {"outpost": "Outpost", "checkpoint": "Checkpoint", "hq": "Command", "qrf_base": "Reserve",
	"comms": "Relay", "village": "Village", "compound": "Compound", "town": "Town"}
const FIELD_CALLSIGN := "Patrol"
const NET_CALLSIGN := "Command"

## Whether the squad hears the net now.
var tuned := false
## Every line sent, oldest first: {"text", "time"}.
var lines: Array[Dictionary] = []
var alert: Alert
var level: Node3D
var _held := 0                # enemy radios the squad held at the last count
var _stale := 0               # how many of them are on the old frequency
var _taken_at := -INF         # when the squad started listening
var _switch_at := INF         # when the enemy changes frequency, once it suspects
var _queue: Array[String] = []
var _next_line := -INF
var _scan := 0.0
var _zone_state := Alert.State.NORMAL
var _callsigns := {}          # module id -> callsign
var _reinforcements: Reinforcements


func _init() -> void:
	name = "RadioChatter"


func _ready() -> void:
	level = get_parent() as Node3D
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	if alert:
		alert.reported.connect(_on_reported)
		alert.state_changed.connect(_on_state_changed)
		_zone_state = alert.zone_state
	var er := level.get_node_or_null(^"EnemyResponse") as EnemyResponse if level else null
	if er:
		er.look_sent.connect(_on_look_sent)
		er.checkpoints_changed.connect(_on_checkpoints)


## The radio chatter of the level `from` is in (null outside a hot zone).
static func of(from: Node) -> RadioChatter:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"RadioChatter") as RadioChatter if lvl else null


func now() -> float:
	return alert.now() if alert else Soldier._now()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		server_tick(delta)


## Host: counts the squad's radios every SCAN_S (or at once with `delta` < 0), changes
## frequency when due and sends the next waiting line. Tests call it after Alert.advance.
func server_tick(delta := -1.0) -> void:
	_scan -= delta
	if delta < 0.0 or _scan <= 0.0:
		_scan = SCAN_S
		_hook_reinforcements()
		_count_radios()
	if _switch_at != INF and now() >= _switch_at:
		_switch()
	_flush()


# --- The squad's radios -------------------------------------------------------------------------

## Units of items tagged `tag` (and not `without`) that `s` carries: worn, in hand or stowed.
static func carried(s: Soldier, tag: String, without := "") -> int:
	if s == null or not is_instance_valid(s) or s.inventory == null:
		return 0
	var inv := s.inventory
	var count := 0
	var ids: Array = inv.slots.values()
	ids.append(inv.hands)
	for id: StringName in ids:
		count += 1 if _tagged(id, tag, without) else 0
	for container: StringName in inv.search_containers():
		for entry: Dictionary in inv.containers.get(container, []):
			if _tagged(StringName(entry.id), tag, without):
				count += int(entry.get("count", 1))
	return count


## The squad: every player and squad AI not dead.
static func squad(from: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s: Soldier in MapNodes.players(from):
		if not s.vitals.is_dead():
			out.append(s)
	out.append_array(MapNodes.squad_ai(from))
	return out


## Units of items tagged `tag` (not `without`) the whole squad carries.
static func squad_count(from: Node, tag: String, without := "") -> int:
	var count := 0
	for s: Soldier in squad(from):
		count += carried(s, tag, without)
	return count


## The first of the squad carrying an item tagged `tag` (not `without`), or null.
static func carrier(from: Node, tag: String, without := "") -> Soldier:
	for s: Soldier in squad(from):
		if carried(s, tag, without) > 0:
			return s
	return null


## The squad has its own field radio (radio contracts: Contracts.radio_contract_problem).
static func has_field_radio(from: Node) -> bool:
	return carrier(from, FIELD_TAG, ENEMY_TAG) != null


static func _tagged(id: StringName, tag: String, without: String) -> bool:
	if id == &"" or not ItemDB.has_item(id):
		return false
	var tags := ItemDB.get_item(id).tags
	return tags.has(tag) and (without == "" or not tags.has(without))


## A radio more than are stale tunes the squad in (and the switch clock starts over); none
## left that works, it stops listening.
func _count_radios() -> void:
	var held := squad_count(self, ENEMY_TAG)
	if held < _held:
		_stale = mini(_stale, held)
	_held = held
	var was := tuned
	tuned = held > _stale
	if tuned == was:
		return
	if tuned:
		_taken_at = now()
		_switch_at = INF
		_say("%s: all stations, radio check, over." % NET_CALLSIGN)
	else:
		_switch_at = INF
		_queue.clear()
	tuned_changed.emit(tuned)


## The enemy changes frequency: one last line, then the squad's radios are stale.
func _switch() -> void:
	_switch_at = INF
	_say("%s: all stations, go to alternate. Out." % NET_CALLSIGN)
	_stale = _held
	if tuned:
		tuned = false
		tuned_changed.emit(false)


# --- What the net carries -----------------------------------------------------------------------

func _on_reported(r: Dictionary) -> void:
	if not tuned:
		return
	if r.kind in [&"body", &"missed_checkin"] and float(r.get("time", now())) >= _taken_at and _switch_at == INF:
		_switch_at = now() + randf_range(FREQ_SWITCH_S.x, FREQ_SWITCH_S.y)
	if randf() < HEAR_CHANCE:
		_say(report_line(r))


func _on_state_changed(area: String, state: int) -> void:
	if area != "zone":
		return
	var up := state > _zone_state
	_zone_state = state
	if not tuned:
		return
	var line := ""
	match state:
		Alert.State.SUSPICIOUS:
			line = "all stations, stay sharp." if up else "all stations, stand down. Stay alert."
		Alert.State.ALERTED:
			line = "all stations, stand to. Man your posts." if up else "all stations, contact lost. Hold your posts."
		Alert.State.ENGAGED:
			line = "all stations, contact reported. QRF, stand by to move."
	if line != "":
		_say.call_deferred("%s: %s" % [NET_CALLSIGN, line])  # after the report that raised it


func _on_wave(_index: int, soldiers: Array) -> void:
	if not tuned or randf() >= QRF_HEAR_CHANCE:
		return
	for s in soldiers:
		if is_instance_valid(s):
			_say("%s: QRF moving out, %s side." % [_callsign_at((s as Node3D).global_position, true), compass(Vector3.ZERO, (s as Node3D).global_position)])
			return


## A patrol sent to look: the order goes out on the net (design: chatter sometimes gives away
## patrol moves).
func _on_look_sent(pos: Vector3) -> void:
	if tuned and randf() < HEAR_CHANCE:
		_say("%s: %s, go and check it out, %s side." % [NET_CALLSIGN, FIELD_CALLSIGN.to_lower(), compass(Vector3.ZERO, pos)])


func _on_checkpoints(closed: bool) -> void:
	if tuned:
		_say("%s: all checkpoints, %s." % [NET_CALLSIGN, "close the roads. Nobody passes" if closed else "open the roads"])


func _hook_reinforcements() -> void:
	if _reinforcements and is_instance_valid(_reinforcements):
		return
	_reinforcements = MapNodes.reinforcements(self)
	if _reinforcements and not _reinforcements.wave_spawned.is_connected(_on_wave):
		_reinforcements.wave_spawned.connect(_on_wave)


## Host: an order of the enemy's high command (EnemyCommand) goes out on the net, from
## `speaker`: heard while tuned (HEAR_CHANCE).
func order(text: String, speaker := NET_CALLSIGN) -> void:
	if tuned and randf() < HEAR_CHANCE:
		_say("%s: %s" % [speaker, text])


## A report as the squad hears it: "Outpost 2: shots heard, to the north."
func report_line(r: Dictionary) -> String:
	var area := String(r.get("area", Alert.FIELD))
	var cs := _callsign(area)
	var pos: Vector3 = r.get("pos", Vector3.ZERO)
	if r.kind == &"missed_checkin":
		if r.get("patrol", false):
			return "%s: %s, radio check, over... nothing." % [NET_CALLSIGN, FIELD_CALLSIGN.to_lower()]
		return "%s: %s, radio check, over... %s, respond." % [NET_CALLSIGN, cs, cs]
	var where := _where(area, pos)
	match r.kind:
		&"shot":
			return "%s: shots heard, %s." % [cs, where]
		&"blast":
			return "%s: explosion, %s." % [cs, where]
		&"contact":
			return "%s: contact, %s! Engaging." % [cs, where]
		&"body":
			return "%s: one of ours down, %s." % [cs, where]
	return "%s: report, over." % cs


## "to the north" from the area's site, "at our position" close to it; in the open ground
## ("north side") from the zone's centre.
func _where(area: String, pos: Vector3) -> String:
	var site := _site(area)
	if site == null:
		return "%s side" % compass(Vector3.ZERO, pos)
	var from := site.global_position
	if Vector2(pos.x - from.x, pos.z - from.z).length() < NEAR_M:
		return "at our position"
	return "to the %s" % compass(from, pos)


## The 8-point compass word for `to` seen from `from` (north is -Z).
static func compass(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var angle := rad_to_deg(atan2(d.x, -d.y))  # 0 north, 90 east
	return COMPASS[posmod(roundi(angle / 45.0), COMPASS.size())]


## A site's callsign: its type's (CALLSIGNS) and its number among that type in the zone
## ("Outpost 2"); FIELD_CALLSIGN for the open ground.
func _callsign(area: String) -> String:
	if _callsigns.is_empty() and level and level.has_method(&"modules"):
		var seen := {}
		for m: ZoneModule in level.call(&"modules"):
			var type := ZoneModules.base(m.type)
			seen[type] = int(seen.get(type, 0)) + 1
			var base := String(CALLSIGNS.get(type, MissionRegistry.module_name(type).capitalize()))
			_callsigns[m.module_id] = "%s %d" % [base, seen[type]] if type != "hq" else base
	return String(_callsigns.get(area, FIELD_CALLSIGN))


## The callsign of the site nearest `pos` (with `qrf`: the nearest QRF base), else NET_CALLSIGN.
func _callsign_at(pos: Vector3, qrf := false) -> String:
	var best: ZoneModule = null
	if level and level.has_method(&"modules"):
		for m: ZoneModule in level.call(&"modules"):
			if (not qrf or m.type == "qrf_base") and (best == null or m.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
				best = m
	return _callsign(best.module_id) if best else NET_CALLSIGN


func _site(area: String) -> ZoneModule:
	if area == Alert.FIELD or level == null or not level.has_method(&"get_module"):
		return null
	return level.call(&"get_module", area) as ZoneModule


# --- Delivery -----------------------------------------------------------------------------------

func _say(text: String) -> void:
	_queue.append(text)
	while _queue.size() > QUEUE_MAX:
		_queue.pop_front()


## Sends the next waiting line, one per LINE_GAP_S, from whoever carries an enemy radio.
func _flush() -> void:
	if _queue.is_empty() or now() < _next_line:
		return
	var text: String = _queue.pop_front()
	_next_line = now() + LINE_GAP_S
	lines.append({"text": text, "time": now()})
	line_sent.emit(text)
	var callouts := Callouts.of(self)
	var by := carrier(self, ENEMY_TAG)
	if callouts == null or by == null:
		return
	for peer in callouts.recipients(by):
		callouts._show.rpc_id(peer, by.get_path(), SPEAKER, String(LINE_ID), text)
