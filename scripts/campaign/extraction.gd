class_name Extraction
extends Node
## Getting out (design doc: "ends at extraction"; supports: "Helicopter extraction"). Until
## wave 5's helicopter, an extraction point is a marked zone on the map with a short
## countdown. Points come from the zone's preset LZs, from a grid reference a player picks on
## the map, or from a thrown purple smoke (SmokeCloud, the colour extraction looks for).
##
## The deployment ends when the squad is inside one point and a player inside it confirms:
## every living player (downed ones carried in) and every AI squadmate the players chose to
## bring. Squadmates the players chose to leave stay behind and are reported (the base's MIA
## rule uses that). Captain, 2026-10-14 (co-op): any player standing inside a point can
## confirm, not only the host; and players down or dead (waiting to respawn) outside the point,
## and AI squadmates away from it, don't block: the first confirm warns who'd be left behind
## (server_confirm), a second one within LEAVE_CONFIRM_S extracts without them and they're
## reported left behind (MIA) like a squadmate left by choice. A player who is up and simply
## elsewhere still blocks: they can walk there. Then a countdown runs (COUNTDOWN_S); anyone
## needed stepping out stops it.
## At the end the host builds the report of who and what got out and hands it to the
## economy (END_GROUP) and to deployment_ended. State replicates to every peer and late
## joiners. Wave 5b: a called extraction helicopter (HeliCall) lands at a point and, with the
## squad aboard, ends the deployment by lifting off (server_ride_out): what's aboard is out.
## Captain, 2026-10-14: "on foot exfils should only be possible at the edge zones. otherwise it
## should be vehicle or helicopter infils/exfils". A point within edge_reach of the level's
## edge is a foot point ("foot": true): the countdown runs there. Any other (interior presets,
## grids and smokes away from the edge) is a helicopter LZ only, named "... (helicopter)": a
## foot confirm there is refused (HELI_ONLY_TEXT). The squad aboard ground vehicles at the
## edge (within VEHICLE_OUT_M of it, or seated inside a foot point) drives out: that ends the
## deployment like the helicopter's ride out (server_drive_out), with the leave-behind rule,
## once that vehicle has carried them further in than the edge (_driven_in).
##
## The report (Dictionary, JSON-safe):
##   "contract_id", "zone_id", "point" ({"name", "pos": [x, z], "source"}), "duration_s",
##   "players": [soldier], "squad": [soldier] (AI squadmates who got out),
##   "left_behind": [{"name", "role", "slot", "alive", "downed", "chosen", "pos": [x, y, z]}],
##   "bodies": [{"uid", "label", "faction", "role", "items"}] (bodies brought out),
##   "bodies_left": [{"uid", "label", "faction", "role"}] (squad and player bodies not brought),
##   "hvts": [{"name", "alive", "faction", ...hvt_record()}], "deposited": [item] (items set
##   down inside the point, which wave 5's helicopter lifts), "driven_out": [item] (B-18: in
##   the holds of motor-pool vehicles going home with the squad; it stays in them),
##   "items": {item id: count} (all of it together: carried, on bodies, deposited, driven out,
##   and what's on a carrier's MOLLE points and in its pouches), "objectives": [map objectives
##   at the end], "vehicles": [[x, z]] (where the vehicles driven out were; point "source"
##   "vehicle").
##   A soldier is {"name", "node", "peer" (players; 0 for AI), "role", "slot", "downed",
##   "condition", "items"}; an item is {"id", "count", "where", "state"?}. A carrier's pouches
##   and their contents stay in its state ("molle"), as the inventory keeps them, so the vest
##   entry is the whole rig; "items" counts them too (totals_of).

signal changed
## Host only: the deployment ended at extraction (see the class doc for the report).
signal deployment_ended(report: Dictionary)

enum State { IDLE, ACTIVE, COUNTDOWN, ENDED }

## Nodes in this group get end_deployment(report) on the host when a deployment ends (the
## economy's debrief: pay, salvage, reputation; the base's roster and MIA).
const END_GROUP := &"deployment_end_handlers"
## HVTs (people agent): nodes in this group count as brought out when inside the point or
## carried by someone who is; an optional hvt_record() -> Dictionary adds to the report.
const HVT_GROUP := &"hvt"
## Proposed: an extraction point's radius (m) and the countdown once the host confirms.
const RADIUS_M := 20.0
## Exfil takes time (Captain, 2026-10-16: "exfil heli isnt instant, it takes time, as any support"):
## the ride is this long out once it's called. Was 10 s.
const COUNTDOWN_S := 90.0
## A crossing's countdown (docs/linked_zones.md call 18): walking on into the next zone (LZ-2).
const CROSSING_COUNTDOWN_S := 20.0
const SMOKE_COLOUR := "purple"
## Captain, 2026-10-14: how long a "Leaving behind" warning stands; a second confirm within it
## extracts without those named.
const LEAVE_CONFIRM_S := 10.0
const SMOKE_CHECK_S := 0.5
## Sources of a point. One "grid" and one "smoke" point at a time: the newest replaces the
## last, as a helicopter goes to the latest call; the zone's presets all stay. While a
## helicopter extraction has its LZ (heli_point), a newer one doesn't take the LZ away: it's
## kept for after the call, when the newest of each source stands again (_keep_newest).
const SOURCES: Array[String] = ["zone", "grid", "smoke"]
## Captain, 2026-10-14 (foot exfil only at the edge). Proposed: a point is a foot point within
## EDGE_EXFIL_M of the level's map area's boundary; on a small level (the compound's stand-in,
## 108 m) at most EDGE_SHARE of its narrower side, so its middle (inside the walls) isn't edge.
const EDGE_EXFIL_M := 75.0
const EDGE_SHARE := 0.25
## Proposed: vehicles carrying the squad are out when within VEHICLE_OUT_M of the boundary (the
## zone's walls stand just past it), checked every VEHICLE_CHECK_S.
const VEHICLE_OUT_M := 25.0
const VEHICLE_CHECK_S := 0.5
const HELI_ONLY_TEXT := "Too far from the zone edge to walk out: call the helicopter or drive out"
const HELI_SUFFIX := " (helicopter)"
## The warning key (_warned_point) of a drive out (points' ids start at 1).
const DRIVE_OUT_KEY := 0

var state := State.IDLE
## Every peer: [{"id", "name", "pos": Vector2 (x, z), "radius", "source"}].
var points: Array = []
## AI squadmates (node names) the players chose to leave behind.
var leave: Dictionary = {}
## Every peer: seconds left on the countdown (while COUNTDOWN).
var countdown_left := 0.0
## Host: the countdown's length (tests shorten it).
var countdown_s := COUNTDOWN_S
## The point the countdown runs for (its id), or -1.
var countdown_point := -1
## The last deployment's report (every peer once it ends).
var last_report: Dictionary = {}
## Host (wave 5b): the helicopter the squad rides out in (HeliCall: server_ride_out). Whoever
## and whatever is aboard counts as out, and its cargo is the deposited items it lifted.
var ride: Node = null
## Host (Captain, 2026-10-14): the ground vehicles the squad drove out in (server_drive_out).
## Like `ride`: who and what is aboard them counts as out.
var rides: Array = []
## Every peer (Captain, 2026-10-14: "when heli extract is selected make sure it's the only one
## shown"): -1, no helicopter extraction called; 0, one is called and its LZ isn't set yet; else
## the id of its point (HeliCall.point_id). While it's 0 or more only the helicopter's point is
## shown or used (shown_points): the zone's presets and older marks stay in `points`, back when
## the call is over without a ride out (cancelled, shot down). HeliSupports keeps it current.
var heli_point := -1
## Host (Captain, 2026-10-14): who the squad extracts without after a confirmed "Leaving behind"
## warning (players down or dead outside the point, AI squadmates away from it), by
## _soldier_name: {name: true}. Cleared when the countdown stops or a deployment begins.
var left_at_call: Dictionary = {}

var _plan: Dictionary = {}
var _started_msec := 0
var _next_id := 1
var _seen_smoke := {}  # host: instance ids of purple clouds already handled
var _smoke_points := {}  # host: purple cloud instance id -> the point it set
var _smoke_check := 0.0
var _last_whole := -1
var _warned := PackedStringArray()  # host: who the last "Leaving behind" warning named
var _warned_point := -1  # host: and at which point
var _warned_msec := -1  # host: and when (Time.get_ticks_msec)
var _vehicle_check := 0.0
var _vehicle_notice := ""  # host: the last "drive out without them" notice, said once
## Host: instance ids of vehicles that carried any of the squad further in than edge_reach this
## deployment. Only those drive out: the motor pool's arrive beside the insertion point at the
## edge, and getting in there to drive into the zone mustn't end it.
var _driven_in := {}


func _init() -> void:
	name = "Extraction"


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)


func is_active() -> bool:
	return state == State.ACTIVE or state == State.COUNTDOWN


func point_by_id(id: int) -> Dictionary:
	for p: Dictionary in points:
		if int(p.id) == id:
			return p
	return {}


# --- Requests (any peer) --------------------------------------------------------

## Asks the host to set an extraction point at a ground point (x, z) picked on the map.
func request_point_at(pos: Vector2) -> void:
	_server_point_at.rpc_id(1, pos)


## Asks the host to bring (or leave behind) the AI squadmate named `mate`.
func request_bring(mate: String, bring: bool) -> void:
	_server_bring.rpc_id(1, mate, bring)


## Asks the host to confirm the extraction; it counts when this peer's player stands inside a
## point (Captain, 2026-10-14: any player there, not only the host).
func request_confirm() -> void:
	_server_confirm.rpc_id(1)


# --- Host -----------------------------------------------------------------------

## Host only. A deployment begins (Briefing.server_start with auto_flow, or the loop wiring):
## extraction is open, with the zone's preset points (plan.zone.extraction_points).
func server_begin(plan: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_plan = plan.duplicate(true)
	_started_msec = Time.get_ticks_msec()
	state = State.ACTIVE
	points = []
	leave = {}
	last_report = {}
	countdown_point = -1
	ride = null
	rides = []
	_vehicle_notice = ""
	_driven_in = {}
	heli_point = -1
	_smoke_points = {}
	_clear_left()
	for cloud in SmokeCloud.clouds_of(SMOKE_COLOUR):
		_seen_smoke[cloud.get_instance_id()] = true  # smoke from before the deployment doesn't count
	for preset: Dictionary in plan.get("zone", {}).get("extraction_points", []):
		var p: Array = preset.get("pos", [])
		if p.size() >= 2:
			_add_point(Vector2(float(p[0]), float(p[1])), "zone", String(preset.get("name", "")), float(preset.get("radius", RADIUS_M)))
	_add_crossings()
	SessionLog.note("extraction open: contract %s, %d preset points" % [String(plan.get("contract", {}).get("id", "none")), points.size()])
	_broadcast()


## Host: the level's crossings into the neighbouring zones (docs/linked_zones.md LZ-2: its def's
## "crossings", RegionMap) as points ("crossing" source, "to" the zone it leads to), always foot
## points: the squad stands in one and confirms, as at an extraction point, and walks on into
## that zone (_finish: from the base a deployment starts there; into the base it ends).
func _add_crossings() -> void:
	var level := get_parent()
	var def: Variant = level.get(&"def") if level else null
	if not def is Dictionary:
		return
	for c: Dictionary in (def as Dictionary).get("crossings", []):
		var id := _add_point(Vector2(float(c.pos[0]), float(c.pos[1])), "crossing", String(c.name), float(c.get("radius", RegionMap.RADIUS_M)))
		var point: Dictionary = points[-1]
		point["name"] = String(c.name)  # never "(helicopter)": a crossing is walked (or driven)
		point["foot"] = true
		point["to"] = String(c.to)
		point["crossing"] = String(c.id)
		point["to_crossing"] = String(c.to_crossing)
		assert(int(point.id) == id)


## Host, the base zone (no deployment): its crossings open, so the squad can walk out into the
## neighbouring zones (LZ-2).
func server_open_crossings() -> void:
	if not multiplayer.is_server() or is_active():
		return
	server_begin({})


## Host only. Ends extraction without a report (the deployment was called off).
func server_cancel() -> void:
	if multiplayer.is_server():
		state = State.IDLE
		points = []
		_broadcast()


## Host only. Adds an extraction point at a ground point (x, z) ("grid" or "smoke"); returns
## its id (0 when no deployment is on). With a helicopter extraction called, its LZ stays the
## point in use: this one is kept for after the call (see SOURCES).
func server_add_point(pos: Vector2, source := "grid", point_name := "", radius := RADIUS_M) -> int:
	return _server_add_point(pos, source, point_name, radius, false)


## Host. server_add_point; `for_heli`: the extraction helicopter's own point (server_place_point),
## which replaces the last of its source as any newest point does.
func _server_add_point(pos: Vector2, source: String, point_name: String, radius: float, for_heli: bool) -> int:
	if not multiplayer.is_server() or not is_active() or not pos.is_finite() or source not in SOURCES:
		return 0
	# Reviewer finding, 2026-10-14: a grid picked on the map or a purple smoke thrown while the
	# helicopter had its LZ replaced that LZ (same source), so no point was shown or usable and
	# the helicopter stopped loading items. The helicopter's LZ is kept; the new point waits.
	var keep := heli_point if not for_heli and heli_point > 0 and not point_by_id(heli_point).is_empty() else -1
	var id := _add_point(pos, source, point_name, radius, keep)
	_broadcast()
	var at := "%s (%s)" % [MapGrid.grid_ref(pos, MapNodes.area_of(self)), _source_text(source)]
	if not point_by_id(id).get("foot", true):  # Captain, 2026-10-14: away from the edge, a helicopter LZ only
		at += ", a helicopter LZ: too far from the zone edge to walk out"
	if keep > 0:
		_client_message.rpc("Extraction point %s kept for after the helicopter call: its LZ stays the one in use" % at)
	elif not for_heli and heli_point == 0 and source == "grid":
		_client_message.rpc("Extraction point %s kept for after the helicopter call: give the helicopter a grid (Support) or pop purple smoke" % at)
	else:
		_client_message.rpc("Extraction point: %s" % at)
	return id


## Host only (wave 5b, the extraction helicopter): point `id` moves to `pos` (x, z) as `source`
## (the one "grid" or "smoke" point: another of that source goes), or a new point is added
## when `id` is gone. Returns the point's id (0 when no deployment is on).
func server_place_point(id: int, pos: Vector2, source := "grid", point_name := "") -> int:
	var point := point_by_id(id)
	if point.is_empty() or point.source == "zone":
		return _server_add_point(pos, source, point_name, RADIUS_M, true)
	if not multiplayer.is_server() or not is_active() or not pos.is_finite() or source not in SOURCES:
		return 0
	var moved: bool = (point.pos as Vector2).distance_to(pos) > 1.0 or point.source != source
	points = points.filter(func(p: Dictionary) -> bool: return p.id == id or p.source != source)
	point.pos = pos
	point.source = source
	point.foot = is_edge(pos)
	point.name = _named(point_name if point_name != "" else String(point.name), point.foot)
	if moved:
		_broadcast()
		_client_message.rpc("Extraction point moved: %s (%s)" % [MapGrid.grid_ref(pos, MapNodes.area_of(self)), _source_text(source)])
	return id


## Host only (wave 5b): the extraction helicopter takes purple smoke `cloud`; it's handled
## (no point of its own from now on). Returns the id of the point this cloud already set, or 0.
func server_take_smoke(cloud: Node) -> int:
	if cloud == null:
		return 0
	var key := cloud.get_instance_id()
	_seen_smoke[key] = true
	var id := int(_smoke_points.get(key, 0))
	return id if not point_by_id(id).is_empty() else 0


## Host only. An extraction point at the centre of a grid square ("0123 0456"); 0 if the
## reference isn't valid.
func server_add_point_at_grid(ref: String) -> int:
	var at: Variant = MapGrid.parse(ref, MapNodes.area_of(self))
	return server_add_point(at, "grid") if at != null else 0


## Host only. Whether the AI squadmate `mate` comes along (true) or is left behind.
func server_set_bring(mate: String, bring: bool) -> void:
	if not multiplayer.is_server():
		return
	if bring:
		leave.erase(mate)
	else:
		leave[mate] = true
	_broadcast()


## Host only. Everyone who must be at the point: {"players": [Soldier], "ai": [Soldier]}
## (not those left at the call: left_at_call).
func required() -> Dictionary:
	var ai := MapNodes.squad_ai(self).filter(func(s: Soldier) -> bool:
		return not leave.has(String(s.name)) and not left_at_call.has(_soldier_name(s)))
	if BaseHub.in_base():
		ai = []  # at the base (a crossing out, LZ-2) the muster line isn't the squad: it deploys with them
	var players := MapNodes.players(self).filter(func(s: Soldier) -> bool: return not left_at_call.has(_soldier_name(s)))
	return {"players": players, "ai": ai}


## Captain, 2026-10-14: whether the squad may extract without `s` (after a warning): an AI
## squadmate, or a player who is down, or dead and waiting to respawn. A player who is up can
## walk to the point, so they're waited for.
## Whether `point` is a crossing on into another zone during a deployment (not home to the base).
func crossing_on(point: Dictionary) -> bool:
	return String(point.get("source", "")) == "crossing" and String(point.get("to", "")) != RegionMap.BASE \
		and BaseHub.deployment_running() and not BaseHub.in_base()


static func can_leave_behind(s: Soldier) -> bool:
	return s.is_ai() or not s.vitals.is_up() or s.respawn_state == Soldier.RESPAWN_WAITING


## The point player `s` can confirm at (up, not waiting to respawn, standing inside it), or {};
## a foot point before a helicopter LZ where they overlap.
func point_of_player(s: Soldier) -> Dictionary:
	if s == null or not s.vitals.is_up() or s.respawn_state == Soldier.RESPAWN_WAITING:
		return {}
	var found := {}
	for point: Dictionary in shown_points():
		if inside(point, s.global_position):
			if point.get("foot", true):
				return point
			if found.is_empty():
				found = point
	return found


## Captain, 2026-10-14: how far in from `area`'s edge the foot points reach (EDGE_EXFIL_M, at
## most EDGE_SHARE of its narrower side).
static func edge_reach(area: Rect2) -> float:
	return minf(EDGE_EXFIL_M, minf(area.size.x, area.size.y) * EDGE_SHARE)


## How far (x, z) `pos` is inside `area`'s boundary (0 or less: on it or past it).
static func edge_distance(area: Rect2, pos: Vector2) -> float:
	return minf(minf(pos.x - area.position.x, area.end.x - pos.x), minf(pos.y - area.position.y, area.end.y - pos.y))


## Whether (x, z) `pos` is at `area`'s edge, where the squad can walk in or out (no area, no
## level: anywhere).
static func at_edge(area: Rect2, pos: Vector2) -> bool:
	return not area.has_area() or edge_distance(area, pos) <= edge_reach(area)


## Whether (x, z) `pos` is at the current level's edge (at_edge).
func is_edge(pos: Vector2) -> bool:
	return at_edge(MapNodes.area_of(self), pos)


## A point's name: a helicopter LZ only (not `foot`) says so ("LZ 2 (helicopter)").
static func _named(base: String, foot: bool) -> String:
	base = base.trim_suffix(HELI_SUFFIX)
	return base if foot else base + HELI_SUFFIX


## Names of those required who aren't inside `point`.
func missing_at(point: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var need := required()
	for s: Soldier in need.players + need.ai:
		if not inside(point, s.body_point()):  # a downed one lying as a ragdoll: where it lies
			missing.append(_soldier_name(s))
	return missing


## The first point with the whole squad inside (a foot point first), or {}.
func point_with_squad() -> Dictionary:
	var found := {}
	for point: Dictionary in shown_points():
		if missing_at(point).is_empty():
			if point.get("foot", true):
				return point
			if found.is_empty():
				found = point
	return found


static func inside(point: Dictionary, pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(point.pos) <= float(point.get("radius", RADIUS_M))


## Host only. Confirms the extraction: with the squad inside a point the countdown starts.
## `by_peer` is the player who confirmed (0: the host's own call, as tests make it); they must
## stand inside a point (Captain, 2026-10-14: any player there can confirm), else they're told
## so. With only those who can be left behind missing (can_leave_behind), the first confirm
## warns everyone who'd be left; a second within LEAVE_CONFIRM_S, from anyone inside, starts
## the countdown without them (left_at_call). A player who is up and elsewhere blocks, and at
## least one player must be inside. Returns "" when it started, or why it didn't.
func server_confirm(by_peer := 0) -> String:
	if not multiplayer.is_server() or state != State.ACTIVE:
		return "No extraction to confirm"
	# Captain, 2026-10-14: a player aboard a vehicle at the zone edge confirms driving out (the
	# leave-behind warning, then out); without a confirmer, when nobody's in a point but players
	# are aboard at the edge.
	var me := _player_of(by_peer) if by_peer > 0 else null
	if (me and aboard_at_edge(me)) or (by_peer <= 0 and point_with_squad().is_empty()
			and MapNodes.players(self).any(func(s: Soldier) -> bool: return aboard_at_edge(s))):
		return _confirm_drive_out()
	if shown_points().is_empty():
		if heli_point == 0:
			return "The helicopter has no LZ yet: give it a grid or pop purple smoke"
		return "No extraction point: pick one on the map or throw a purple smoke"
	var point := {}
	if by_peer > 0:
		point = point_of_player(_player_of(by_peer))
		if point.is_empty():
			var refused := "Only a player standing inside an extraction point can confirm it"
			_client_message.rpc_id(by_peer, refused)
			SessionLog.note("extraction: player %d's confirm refused (not inside a point)" % by_peer)
			return refused
	else:
		point = point_with_squad()
		if point.is_empty():
			point = _point_for_call()
	if not point.get("foot", true):  # Captain, 2026-10-14: walk out only at the zone's edge
		if by_peer > 0:
			_client_message.rpc_id(by_peer, HELI_ONLY_TEXT)
		else:
			_client_message.rpc(HELI_ONLY_TEXT)
		SessionLog.note("extraction: confirm at %s refused (a helicopter LZ, not at the zone edge)" % point.name)
		return HELI_ONLY_TEXT
	if not missing_at(point).is_empty():
		return _confirm_without(point)
	return _start_countdown(point)


## Host. Not everyone needed is inside `point`. Players who are up and elsewhere block; the
## rest (can_leave_behind) are warned about, then left at a second confirm. Returns "" when the
## countdown started, or why it didn't.
func _confirm_without(point: Dictionary) -> String:
	var need := required()
	var blockers := PackedStringArray()
	var leaving := PackedStringArray()
	var players_in := 0
	for s: Soldier in need.players + need.ai:
		if inside(point, s.body_point()):
			players_in += 0 if s.is_ai() else 1
		elif can_leave_behind(s) and not (s.is_ai() and crossing_on(point)):  # (squadmates cross together, LZ-2)
			leaving.append(_soldier_name(s))
		else:
			blockers.append(_soldier_name(s))
	var why := ""
	if not blockers.is_empty():
		why = "Not everyone is at the %s. Waiting for: %s" % ["crossing" if String(point.get("source", "")) == "crossing" else "extraction point", ", ".join(blockers)]
	elif players_in == 0:
		why = "Nobody is at the extraction point"
	if why != "":
		_client_message.rpc(why)
		return why
	why = _leave_or_warn(leaving, int(point.id), String(point.name))
	return why if why != "" else _start_countdown(point)


## Host. Those named in `leaving` can be left behind: the first confirm (at `key`, a point's id
## or DRIVE_OUT_KEY) warns everyone and returns the warning; a second within LEAVE_CONFIRM_S
## leaves them (left_at_call) and returns "".
func _leave_or_warn(leaving: PackedStringArray, key: int, where: String) -> String:
	var again := _warned == leaving and _warned_point == key and _warned_msec >= 0 \
		and Time.get_ticks_msec() - _warned_msec <= int(LEAVE_CONFIRM_S * 1000.0)
	if not again:
		_warned = leaving
		_warned_point = key
		_warned_msec = Time.get_ticks_msec()
		var why := "Leaving behind: %s. Confirm again to extract without them" % ", ".join(leaving)
		_client_message.rpc(why)
		SessionLog.note("extraction at %s: warned, leaving behind %s" % [where, ", ".join(leaving)])
		return why
	for who in leaving:
		left_at_call[who] = true
	SessionLog.note("extraction at %s: confirmed again, leaving behind %s" % [where, ", ".join(leaving)])
	return ""


# --- Driving out (Captain, 2026-10-14) ------------------------------------------------------------

## Whether ground vehicle `v` can drive the squad out: not a helicopter (HeliCall's ride out),
## not a wreck or burning, driven into the zone this deployment (_driven_in), and ours (the
## company's or friendly) or driven by one of the squad.
func can_drive_out(v: Vehicle) -> bool:
	if v == null or v.is_queued_for_deletion() or v.kind == Vehicle.HELICOPTER or v.wrecked or v.is_burning() \
			or not _driven_in.has(v.get_instance_id()):
		return false
	if v.faction == &"player" or v.faction == &"friendly":
		return true
	var d := v.driver()
	return d != null and (d in MapNodes.players(self) or d in MapNodes.squad_ai(self))


## Whether vehicle `v` is at the zone's edge for driving out: within VEHICLE_OUT_M of the
## boundary, or inside a foot point.
func vehicle_at_edge(v: Vehicle) -> bool:
	var at := Vector2(v.global_position.x, v.global_position.z)
	var area := MapNodes.area_of(self)
	if area.has_area() and edge_distance(area, at) <= VEHICLE_OUT_M:
		return true
	for point: Dictionary in shown_points():
		if point.get("foot", true) and inside(point, v.global_position):
			return true
	return false


## Whether soldier `s` sits in a vehicle that can drive out and is at the edge.
func aboard_at_edge(s: Soldier) -> bool:
	var v := Vehicle.ride_of(s) if s else null
	return v != null and can_drive_out(v) and vehicle_at_edge(v)


## Host. Who's needed and not aboard at the edge: {"blockers": [name] (players up: they can get
## in), "leaving": [name] (can_leave_behind), "vehicles": [Vehicle] (those carrying anyone needed),
## "players_aboard": int}.
func _drive_out_state() -> Dictionary:
	var need := required()
	var out := {"blockers": PackedStringArray(), "leaving": PackedStringArray(), "vehicles": [], "players_aboard": 0}
	for s: Soldier in need.players + need.ai:
		if aboard_at_edge(s):
			var v := Vehicle.ride_of(s)
			if v not in out.vehicles:
				out.vehicles.append(v)
			out.players_aboard += 0 if s.is_ai() else 1
		elif can_leave_behind(s):
			out.leaving.append(_soldier_name(s))
		else:
			out.blockers.append(_soldier_name(s))
	return out


## Host. A confirm aboard a vehicle at the edge: out with everyone needed aboard, else the
## leave-behind rule (_leave_or_warn). Returns "" when the squad drove out, or why not.
func _confirm_drive_out() -> String:
	var st := _drive_out_state()
	var why := ""
	if not (st.blockers as PackedStringArray).is_empty():
		why = "Not everyone is aboard at the zone edge. Waiting for: %s" % ", ".join(st.blockers)
	elif int(st.players_aboard) == 0:
		why = "Nobody is aboard at the zone edge"
	if why != "":
		_client_message.rpc(why)
		return why
	if not (st.leaving as PackedStringArray).is_empty():
		why = _leave_or_warn(st.leaving, DRIVE_OUT_KEY, "the zone edge (driving out)")
		if why != "":
			return why
	server_drive_out(st.vehicles)
	return ""


## Host. Every VEHICLE_CHECK_S: with everyone needed aboard vehicles at the edge, the squad
## drives out; with only those who could be left behind missing, it says once how to go without
## them (a confirm: _confirm_drive_out).
func _check_drive_out() -> void:
	if state != State.ACTIVE or MapNodes.players(self).is_empty():
		return
	var area := MapNodes.area_of(self)
	var need := required()
	for s: Soldier in need.players + need.ai:
		var v := Vehicle.ride_of(s)
		if v and not _driven_in.has(v.get_instance_id()) and area.has_area() \
				and edge_distance(area, Vector2(v.global_position.x, v.global_position.z)) > edge_reach(area):
			_driven_in[v.get_instance_id()] = true
	var st := _drive_out_state()
	if not (st.blockers as PackedStringArray).is_empty() or int(st.players_aboard) == 0:
		_vehicle_notice = ""
		return
	if (st.leaving as PackedStringArray).is_empty():
		server_drive_out(st.vehicles)
		return
	var notice := "Aboard at the zone edge. %s not aboard: Extract to drive out without them" % ", ".join(st.leaving)
	if notice != _vehicle_notice:
		_vehicle_notice = notice
		_client_message.rpc(notice)


## Host only (Captain, 2026-10-14): the squad drives out of the zone aboard `vehicles` (ground
## vehicles at the edge): the deployment ends as at the helicopter's ride out (_finish), with
## what's aboard them counted out. Returns whether it ended.
func server_drive_out(vehicles: Array) -> bool:
	if not multiplayer.is_server() or not is_active() or vehicles.is_empty():
		return false
	rides = vehicles.duplicate()
	var at := Vector2.ZERO
	var names := PackedStringArray()
	for v: Vehicle in rides:
		at += Vector2(v.global_position.x, v.global_position.z)
		names.append(v.display_name())
	at /= rides.size()
	countdown_point = -1
	_finish({"id": DRIVE_OUT_KEY, "name": "Driven out (%s)" % ", ".join(names), "pos": at, "radius": RADIUS_M, "source": "vehicle", "foot": false})
	return true


## Host: the point a call without a confirmer is about: the one with the most of the squad
## inside, else the nearest to the first player.
func _point_for_call() -> Dictionary:
	var need := required()
	var best := {}
	var best_n := 0
	for point: Dictionary in shown_points():
		var n := 0
		for s: Soldier in need.players + need.ai:
			n += 1 if inside(point, s.body_point()) else 0
		if n > best_n:
			best = point
			best_n = n
	return best if not best.is_empty() else _nearest_point()


func _player_of(peer: int) -> Soldier:
	for s: Soldier in MapNodes.players(self):
		if s.name.to_int() == peer:
			return s
	return null


func _clear_left() -> void:
	left_at_call = {}
	_warned = PackedStringArray()
	_warned_point = -1
	_warned_msec = -1


## Host. Everyone needed is inside `point`: the countdown starts. Returns "".
func _start_countdown(point: Dictionary) -> String:
	SessionLog.note("extraction called at %s: %.0f s countdown" % [point.name, countdown_s])
	state = State.COUNTDOWN
	countdown_point = int(point.id)
	var crossing := String(point.get("source", "")) == "crossing"
	countdown_left = minf(countdown_s, CROSSING_COUNTDOWN_S) if crossing else countdown_s
	_last_whole = -1
	_broadcast()
	if crossing:
		_client_message.rpc("Moving %s in %d s: stay inside the crossing" % [String(point.name).to_lower(), ceili(countdown_left)])
		return ""
	_client_message.rpc("Exfil inbound to %s, ETA %d s: hold inside the point" % [point.name, ceili(countdown_s)])
	# get_parent(), not EnemyResponse.of(self)/CompoundLevel.current(self): those find the level
	# by "first node in the level group", which can grab a stale or wrong one during a rapid
	# zone transition (replaying the same zone id for a recovery deployment, R1357). Extraction
	# is always a direct child of its own level (MapNodes.install), so this is unambiguous.
	var response := get_parent().get_node_or_null(^"EnemyResponse") as EnemyResponse
	if response:
		response.server_alert_extraction(Vector3(point.pos.x, 0.0, point.pos.y))  # not quiet
	return ""


## Host only (wave 5b, the extraction helicopter): the squad is aboard `p_ride` (a Vehicle) at
## point `point_id` and it lifts off: the deployment ends the way the countdown's does
## (_finish), with what's aboard counted out (build_report). Returns whether it ended.
func server_ride_out(point_id: int, p_ride: Node) -> bool:
	var point := point_by_id(point_id)
	if not multiplayer.is_server() or not is_active() or point.is_empty():
		return false
	ride = p_ride
	countdown_point = point_id
	_finish(point)
	return true


## Whether `node` gets out at `point`: inside it, or, with a ride (server_ride_out), aboard it
## only (what's left on the ground when the helicopter lifts doesn't come out: loot only
## counts if it comes out). A body counts where it lies (Soldier.body_point: a ragdoll can rest
## metres from the capsule, which stays where it fell), so the corpse players see in the point
## is the one banked.
func _out_at(point: Dictionary, node: Node3D) -> bool:
	if is_instance_valid(ride) and ride is Vehicle:
		return Vehicle.ride_of(node) == ride
	if not rides.is_empty():  # driven out (server_drive_out): aboard one of them
		return Vehicle.ride_of(node) in rides
	var at := (node as Soldier).body_point() if node is Soldier else node.global_position
	return inside(point, at)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_smoke_check -= delta
	if _smoke_check <= 0.0:
		_smoke_check = SMOKE_CHECK_S
		_check_smoke()
	_vehicle_check -= delta
	if _vehicle_check <= 0.0:
		_vehicle_check = VEHICLE_CHECK_S
		_check_drive_out()
	if state == State.COUNTDOWN:
		_run_countdown(delta)


## Host. A purple smoke thrown during a deployment sets an extraction point where it is.
func _check_smoke() -> void:
	for cloud in SmokeCloud.clouds_of(SMOKE_COLOUR):
		var key := cloud.get_instance_id()
		if _seen_smoke.has(key):
			continue
		_seen_smoke[key] = true
		if is_active():
			var p := cloud.global_position
			_smoke_points[key] = server_add_point(Vector2(p.x, p.z), "smoke")


func _run_countdown(delta: float) -> void:
	var point := point_by_id(countdown_point)
	var missing := missing_at(point) if not point.is_empty() else PackedStringArray(["the point"])
	if not missing.is_empty():
		state = State.ACTIVE
		countdown_point = -1
		_clear_left()  # who's left behind is asked again at the next confirm
		_broadcast()
		_client_message.rpc("Extraction stopped: %s left the extraction point" % ", ".join(missing))
		SessionLog.note("extraction stopped: %s left %s" % [", ".join(missing), point.get("name", "the point")])
		return
	countdown_left -= delta
	var whole := ceili(countdown_left)
	if whole != _last_whole and whole > 0 and (whole <= 5 or whole % 5 == 0):
		_last_whole = whole
		_client_countdown.rpc(countdown_left)
	if countdown_left <= 0.0:
		_finish(point)


## Host. The squad is out: the report goes to the economy and everyone hears it.
func _finish(point: Dictionary) -> void:
	if String(point.get("source", "")) == "crossing" and BaseHub.in_base():
		# From the base (LZ-2): out through the crossing, a deployment into the zone it leads to.
		state = State.ACTIVE
		countdown_point = -1
		countdown_left = 0.0
		_broadcast()
		var why := BaseHub.server_cross_from_base(String(point.to), String(point.to_crossing))
		if why != "":
			SessionLog.note("crossing out of the base refused: %s" % why)
			print("[crossing] out of the base refused: %s" % why)
			_client_message.rpc(why)
		return
	if crossing_on(point):
		# On into the next zone mid-deployment (LZ-2): everyone at the crossing, as they are.
		state = State.ENDED
		countdown_left = 0.0
		_broadcast()
		var why := BaseHub.server_cross_on(String(point.to), String(point.to_crossing), self)
		if why != "":
			state = State.ACTIVE
			countdown_point = -1
			_broadcast()
			_client_message.rpc(why)
		return
	if String(point.get("source", "")) == "crossing":
		BaseHub.set_arrival(String(point.to_crossing))  # home at the matching crossing
	state = State.ENDED
	countdown_left = 0.0
	var report := build_report(point)
	last_report = report
	SessionLog.note("extraction complete at %s (%s) after %d s: %s" % [point.get("name", "?"),
		"aboard %s" % ride.name if is_instance_valid(ride) else "driven out" if not rides.is_empty() else "countdown", int(report.get("duration_s", 0)), summary(report)])
	var reinforcements := MapNodes.reinforcements(self)
	if reinforcements:
		reinforcements.server_stop()
	_broadcast()
	_client_ended.rpc(report)
	deployment_ended.emit(report)
	for handler in get_tree().get_nodes_in_group(END_GROUP):
		if handler.has_method(&"end_deployment"):
			handler.call(&"end_deployment", report)


## Host only. Who and what is getting out at `point` (see the class doc).
func build_report(point: Dictionary) -> Dictionary:
	var need := required()
	var out_players: Array = need.players.duplicate()
	var out_ai: Array = need.ai.duplicate()
	# Left at the call but inside (or aboard) at the end after all: they got out.
	for s: Soldier in MapNodes.players(self):
		if left_at_call.has(_soldier_name(s)) and s.respawn_state != Soldier.RESPAWN_WAITING and _out_at(point, s):
			out_players.append(s)
	for s: Soldier in MapNodes.squad_ai(self):
		if left_at_call.has(_soldier_name(s)) and not leave.has(String(s.name)) and _out_at(point, s):
			out_ai.append(s)
	var out_soldiers: Array[Soldier] = []
	var players: Array = []
	var squad: Array = []
	for s: Soldier in out_players:
		players.append(_soldier_record(s))
		out_soldiers.append(s)
	for s: Soldier in out_ai:
		squad.append(_soldier_record(s))
		out_soldiers.append(s)
	var left: Array = []
	for s: Soldier in MapNodes.squad_ai(self):
		if s not in out_ai:
			var p := s.global_position
			left.append({"name": String(s.name), "role": String(s.role), "slot": s.squad_slot, "alive": true,
				"downed": not s.vitals.is_up(), "chosen": leave.has(String(s.name)), "pos": [p.x, p.y, p.z]})
	# Captain, 2026-10-14: players down or dead outside the point, left at the call, are left
	# behind (MIA) like a squadmate ("player", "peer"; "alive" false while waiting to respawn).
	for s: Soldier in MapNodes.players(self):
		if s not in out_players:
			var p := s.body_point()
			left.append({"name": _soldier_name(s), "player": true, "peer": s.name.to_int(), "node": String(s.name), "role": String(s.role),
				"slot": s.squad_slot, "alive": not s.vitals.is_dead() and s.respawn_state != Soldier.RESPAWN_WAITING,
				"downed": not s.vitals.is_up(), "chosen": false, "pos": [p.x, p.y, p.z]})
	var carried := {}
	for s: Soldier in out_soldiers:
		if is_instance_valid(s.carrying):
			carried[s.carrying] = true
	var bodies: Array = []
	var bodies_left: Array = []
	for node in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var body := node as Soldier
		if body == null or body.is_queued_for_deletion():
			continue
		var record := {"uid": body.body_uid, "label": body.display_name(), "faction": String(body.faction), "role": String(body.role)}
		if carried.has(body) or _out_at(point, body):
			record["items"] = items_of(body.inventory)
			bodies.append(record)
		elif body.faction == &"friendly":
			bodies_left.append(record)
	var hvts: Array = []
	for node in get_tree().get_nodes_in_group(HVT_GROUP):
		var n := node as Node3D
		if n == null or not (carried.has(n) or _out_at(point, n)):
			continue
		var record := {"name": String(n.name), "alive": true, "faction": String(n.get(&"faction")) if n.get(&"faction") != null else ""}
		var vitals := n.get_node_or_null(^"Vitals") as Vitals
		if vitals:
			record["alive"] = not vitals.is_dead()
		if n.has_method(&"hvt_record"):
			record.merge(n.call(&"hvt_record"), true)
		hvts.append(record)
	for v: Vehicle in _rides():  # wave 5b: HVTs and hostages aboard the helicopter (or the vehicles driven out)
		for s: Soldier in v.occupants():
			if Person.is_hvt(s):
				hvts.append({"name": String(s.name), "hvt": String(Person.state(s).get("hvt_id", s.name)), "alive": not s.vitals.is_dead(),
					"faction": String(s.faction), "aboard": true})
	var deposited: Array = []
	var pool := MotorPoolNode.of(self)
	# Wave 5b: with a ride, what's deposited is what it lifted (its hold, below), not what was
	# left in the point. Captain, 2026-10-14: driven out, the holds of the vehicles that aren't
	# the motor pool's (those go home with what's in them: driven_out, below).
	var holds: Array[VehicleCargo] = []
	for v: Vehicle in _rides():
		var h := v.cargo() as VehicleCargo
		if h and (v == ride or MotorPool.pool_id(v) == ""):
			holds.append(h)
	var left_in_point: Array[Node] = get_tree().get_nodes_in_group(WorldItem.GROUP) if _rides().is_empty() else ([] as Array[Node])
	for node in left_in_point:
		var item := node as WorldItem
		if item and not item.is_queued_for_deletion() and inside(point, item.global_position):
			var entry := {"id": String(item.item_id), "count": item.count, "where": "deposited", "uid": item.uid}
			if not item.state.is_empty():
				entry["state"] = item.state.duplicate(true)
			deposited.append(entry)
	for hold in holds:  # wave 5b: what the helicopter lifted from the point (or the vehicles drove out)
		for e: Dictionary in hold.entries():
			var entry := {"id": String(e.id), "count": int(e.get("count", 1)), "where": "deposited"}
			if not e.get("state", {}).is_empty():
				entry["state"] = (e.state as Dictionary).duplicate(true)
			deposited.append(entry)
	# B-18: the holds of motor-pool vehicles going home with the squad (MotorPoolNode.server_settle)
	# came out too, though what's in them stays in the vehicle, not deposited (not banked).
	var at: Vector2 = point.get("pos", Vector2.ZERO)
	var home_points: Array = [Vector3(at.x, 0.0, at.y)]
	var vehicles: Array = []
	for v: Vehicle in rides:  # driven out: each vehicle's own place counts (MotorPoolNode settles by "vehicles")
		home_points.append(Vector3(v.global_position.x, 0.0, v.global_position.z))
		vehicles.append([v.global_position.x, v.global_position.z])
	var driven: Array = pool.cargo_going_home(home_points, ride) if pool else []
	for entry: Dictionary in driven:
		entry["where"] = "vehicle"
	var totals := {}
	for group: Array in [players, squad, bodies]:
		for record: Dictionary in group:
			_add_totals(totals, record.items)
	_add_totals(totals, deposited)
	_add_totals(totals, driven)
	var objectives: Array = []
	for o: Dictionary in MapView.objectives_in(self):
		objectives.append({"id": o.get("id", ""), "title": o.get("title", ""), "state": o.get("state", "")})
	var pos: Vector2 = point.get("pos", Vector2.ZERO)
	return {"contract_id": String(_plan.get("contract", {}).get("id", "")), "zone_id": GameState.zone_id,
		"point": {"name": String(point.get("name", "")), "pos": [pos.x, pos.y], "source": String(point.get("source", ""))},
		"duration_s": (Time.get_ticks_msec() - _started_msec) / 1000.0,
		"players": players, "squad": squad, "left_behind": left, "bodies": bodies, "bodies_left": bodies_left,
		"hvts": hvts, "deposited": deposited, "driven_out": driven, "items": totals, "objectives": objectives, "vehicles": vehicles}


## Everything an inventory holds, one entry per slot, stack and the hands:
## [{"id", "count", "where" (slot, container or "hands"), "state"?}].
static func items_of(inventory: Inventory) -> Array:
	var out: Array = []
	for slot in Inventory.SLOTS:
		var id: StringName = inventory.slots.get(slot, &"")
		if id != &"":
			var entry := {"id": String(id), "count": 1, "where": String(slot)}
			var state: Dictionary = inventory.slot_state.get(slot, {})
			if not state.is_empty():
				entry["state"] = state.duplicate(true)
			out.append(entry)
	for container in Inventory.CONTAINERS:
		for e: Dictionary in inventory.containers.get(container, []):
			var entry := {"id": String(e.id), "count": int(e.get("count", 1)), "where": String(container)}
			if not e.get("state", {}).is_empty():
				entry["state"] = (e.state as Dictionary).duplicate(true)
			out.append(entry)
	if inventory.hands != &"":
		out.append({"id": String(inventory.hands), "count": 1, "where": "hands"})
	return out


## Item counts in a list of item entries ({item id: count}), with what a carrier has on its
## MOLLE points and in its pouches (a worn or stowed vest's "molle" state, a loose pouch's
## "held").
static func totals_of(items: Array) -> Dictionary:
	var totals := {}
	_add_totals(totals, items)
	return totals


static func _add_totals(totals: Dictionary, items: Array) -> void:
	for entry: Dictionary in items:
		var id := String(entry.get("id", ""))
		if id != "":
			totals[id] = int(totals.get(id, 0)) + int(entry.get("count", 1))
		var state: Dictionary = entry.get("state", {})
		var molle: Dictionary = state.get("molle", {})
		for point: Variant in molle:
			var att: Dictionary = molle[point]
			_add_totals(totals, [{"id": att.get("id", ""), "count": 1}])
			_add_totals(totals, att.get("held", []))
		_add_totals(totals, state.get("held", []))


func _soldier_record(s: Soldier) -> Dictionary:
	return {"name": _soldier_name(s), "node": String(s.name), "peer": 0 if s.is_ai() else s.name.to_int(),
		"role": String(s.role), "slot": s.squad_slot, "downed": not s.vitals.is_up(),
		"condition": s.vitals.condition_text(), "items": items_of(s.inventory)}


static func _soldier_name(s: Soldier) -> String:
	return String(s.name) if s.is_ai() else "Player %s" % s.name


## The vehicles the squad left in: the helicopter (server_ride_out) or those driven out.
func _rides() -> Array:
	if is_instance_valid(ride) and ride is Vehicle:
		return [ride]
	return rides.filter(func(v: Variant) -> bool: return is_instance_valid(v))


## The points shown and used now: all of them, or with a helicopter extraction called only its
## LZ (none while it has no LZ yet). See heli_point.
func shown_points() -> Array:
	if heli_point < 0:
		return points
	return points.filter(func(p: Dictionary) -> bool: return int(p.id) == heli_point)


## Host only (HeliSupports): the helicopter extraction's point (heli_point: -1 none, 0 called
## with no LZ yet, else its point id).
func server_set_heli_point(id: int) -> void:
	if not multiplayer.is_server() or id == heli_point:
		return
	heli_point = id
	if id < 0:
		_keep_newest()
	SessionLog.note("extraction: %s" % ("every point shown again (no helicopter extraction)" if id < 0
		else "helicopter extraction called, its LZ not set yet: no point shown" if id == 0 else "only the helicopter's LZ shown (point %d)" % id))
	_broadcast()


func _nearest_point() -> Dictionary:
	var me := MapNodes.players(self)
	var from := Vector2(me[0].global_position.x, me[0].global_position.z) if not me.is_empty() else Vector2.ZERO
	var shown := shown_points()
	var best: Dictionary = shown[0]
	for p: Dictionary in shown:
		if from.distance_to(p.pos) < from.distance_to(best.pos):
			best = p
	return best


## Host. A new point; one of `source` ("grid", "smoke") replaces the last of it, except point
## `keep` (the helicopter's LZ: see SOURCES).
func _add_point(pos: Vector2, source: String, point_name: String, radius: float, keep := -1) -> int:
	if source != "zone" and source != "crossing":
		points = points.filter(func(p: Dictionary) -> bool: return p.source != source or (keep > 0 and int(p.id) == keep))
	var id := _next_id
	_next_id += 1
	if point_name == "":
		point_name = {"grid": "Grid LZ", "smoke": "Purple smoke"}.get(source, "LZ %d" % id)
	var foot := is_edge(pos)  # Captain, 2026-10-14: away from the edge, a helicopter LZ only
	points.append({"id": id, "name": _named(point_name, foot), "pos": pos, "radius": radius, "source": source, "foot": foot})
	return id


## Host. The helicopter extraction's over: one "grid" and one "smoke" point again, the newest
## of each (its LZ was kept beside newer ones while it stood: _add_point). The point a
## countdown runs at stays.
func _keep_newest() -> void:
	var newest := {}
	for p: Dictionary in points:
		if p.source != "zone" and p.source != "crossing":
			newest[p.source] = maxi(int(newest.get(p.source, 0)), int(p.id))
	var before := points.size()
	points = points.filter(func(p: Dictionary) -> bool:
		return p.source == "zone" or p.source == "crossing" or int(p.id) == int(newest[p.source]) or int(p.id) == countdown_point)
	if points.size() != before:
		SessionLog.note("extraction: %d older point(s) dropped after the helicopter call" % (before - points.size()))


static func _source_text(source: String) -> String:
	return {"grid": "grid", "smoke": "purple smoke", "zone": "preset"}.get(source, source)


@rpc("any_peer", "call_local", "reliable")
func _server_point_at(pos: Vector2) -> void:
	if multiplayer.is_server() and pos.is_finite():  # audit L6-01
		server_add_point(pos, "grid")


@rpc("any_peer", "call_local", "reliable")
func _server_bring(mate: String, bring: bool) -> void:
	if multiplayer.is_server():
		server_set_bring(mate, bring)


## Captain, 2026-10-14: any player inside a point may confirm, the host's clients too (only the
## host's used to count, so a client's confirm went nowhere).
@rpc("any_peer", "call_local", "reliable")
func _server_confirm() -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		server_confirm(sender if sender > 0 else multiplayer.get_unique_id())


func _state() -> Dictionary:
	return {"state": state, "points": points, "leave": leave.keys(), "countdown": countdown_left, "point": countdown_point, "heli": heli_point}


func _broadcast() -> void:
	_client_state.rpc(_state())
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_client_state.rpc_id(id, _state())
		if not last_report.is_empty():
			_client_report.rpc_id(id, last_report)


# --- Every peer -----------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _client_state(s: Dictionary) -> void:
	state = int(s.get("state", State.IDLE)) as State
	points = s.get("points", [])
	leave = {}
	for mate: String in s.get("leave", []):
		leave[mate] = true
	countdown_left = float(s.get("countdown", 0.0))
	countdown_point = int(s.get("point", -1))
	heli_point = int(s.get("heli", -1))
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_message(text: String) -> void:
	MapNodes.flash_local(self, text)


@rpc("authority", "call_local", "reliable")
func _client_countdown(left: float) -> void:
	countdown_left = left
	MapNodes.flash_local(self, "Extraction in %d s" % ceili(left))


@rpc("authority", "call_local", "reliable")
func _client_ended(report: Dictionary) -> void:
	last_report = report
	changed.emit()
	MapNodes.flash_local(self, summary(report))


@rpc("authority", "call_remote", "reliable")
func _client_report(report: Dictionary) -> void:
	last_report = report
	changed.emit()


## One line for the HUD: who got out and who didn't.
static func summary(report: Dictionary) -> String:
	var out: int = report.get("players", []).size() + report.get("squad", []).size()
	var left: int = report.get("left_behind", []).size()
	var text := "Extracted: %d soldiers out" % out
	if not report.get("hvts", []).is_empty():
		text += ", %d HVT" % report.hvts.size()
	if not report.get("bodies", []).is_empty():
		text += ", %d bodies" % report.bodies.size()
	if left > 0:
		text += ". Left behind: %s" % ", ".join(report.left_behind.map(func(e: Dictionary) -> String: return e.name))
	return text
