class_name Extraction
extends Node
## Getting out (design doc: "ends at extraction"; supports: "Helicopter extraction"). Until
## wave 5's helicopter, an extraction point is a marked zone on the map with a short
## countdown. Points come from the zone's preset LZs, from a grid reference a player picks on
## the map, or from a thrown purple smoke (SmokeCloud, the colour extraction looks for).
##
## The deployment ends when the squad is inside one point and the host confirms: every
## living player (downed ones carried in) and every AI squadmate the players chose to bring.
## Squadmates the players chose to leave stay behind and are reported (the base's MIA rule
## uses that). Then a countdown runs (COUNTDOWN_S); anyone needed stepping out stops it.
## At the end the host builds the report of who and what got out and hands it to the
## economy (END_GROUP) and to deployment_ended. State replicates to every peer and late
## joiners.
##
## The report (Dictionary, JSON-safe):
##   "contract_id", "zone_id", "point" ({"name", "pos": [x, z], "source"}), "duration_s",
##   "players": [soldier], "squad": [soldier] (AI squadmates who got out),
##   "left_behind": [{"name", "role", "slot", "alive", "downed", "chosen", "pos": [x, y, z]}],
##   "bodies": [{"uid", "label", "faction", "role", "items"}] (bodies brought out),
##   "bodies_left": [{"uid", "label", "faction", "role"}] (squad and player bodies not brought),
##   "hvts": [{"name", "alive", "faction", ...hvt_record()}], "deposited": [item] (items set
##   down inside the point, which wave 5's helicopter lifts), "items": {item id: count} (all
##   of it together: carried, on bodies, deposited, and what's on a carrier's MOLLE points and
##   in its pouches), "objectives": [map objectives at the end].
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
const COUNTDOWN_S := 10.0
const SMOKE_COLOUR := "purple"
const SMOKE_CHECK_S := 0.5
## Sources of a point. One "grid" and one "smoke" point at a time: the newest replaces the
## last, as a helicopter goes to the latest call; the zone's presets all stay.
const SOURCES: Array[String] = ["zone", "grid", "smoke"]

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

var _plan: Dictionary = {}
var _started_msec := 0
var _next_id := 1
var _seen_smoke := {}  # host: instance ids of purple clouds already handled
var _smoke_check := 0.0
var _last_whole := -1


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


## Only the host's confirmation counts.
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
	for cloud in SmokeCloud.clouds_of(SMOKE_COLOUR):
		_seen_smoke[cloud.get_instance_id()] = true  # smoke from before the deployment doesn't count
	for preset: Dictionary in plan.get("zone", {}).get("extraction_points", []):
		var p: Array = preset.get("pos", [])
		if p.size() >= 2:
			_add_point(Vector2(float(p[0]), float(p[1])), "zone", String(preset.get("name", "")), float(preset.get("radius", RADIUS_M)))
	_broadcast()


## Host only. Ends extraction without a report (the deployment was called off).
func server_cancel() -> void:
	if multiplayer.is_server():
		state = State.IDLE
		points = []
		_broadcast()


## Host only. Adds an extraction point at a ground point (x, z) ("grid" or "smoke"); returns
## its id (0 when no deployment is on).
func server_add_point(pos: Vector2, source := "grid", point_name := "", radius := RADIUS_M) -> int:
	if not multiplayer.is_server() or not is_active() or not pos.is_finite() or source not in SOURCES:
		return 0
	var id := _add_point(pos, source, point_name, radius)
	_broadcast()
	_client_message.rpc("Extraction point: %s (%s)" % [MapGrid.grid_ref(pos, MapNodes.area_of(self)), _source_text(source)])
	return id


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


## Host only. Everyone who must be at the point: {"players": [Soldier], "ai": [Soldier]}.
func required() -> Dictionary:
	var ai := MapNodes.squad_ai(self).filter(func(s: Soldier) -> bool: return not leave.has(String(s.name)))
	return {"players": MapNodes.players(self), "ai": ai}


## Names of those required who aren't inside `point`.
func missing_at(point: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var need := required()
	for s: Soldier in need.players + need.ai:
		if not inside(point, s.global_position):
			missing.append(_soldier_name(s))
	return missing


## The first point with the whole squad inside, or {}.
func point_with_squad() -> Dictionary:
	for point: Dictionary in points:
		if missing_at(point).is_empty():
			return point
	return {}


static func inside(point: Dictionary, pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(point.pos) <= float(point.get("radius", RADIUS_M))


## Host only. The host confirms the extraction: with the squad inside a point the countdown
## starts. Returns "" when it started, or why it didn't.
func server_confirm() -> String:
	if not multiplayer.is_server() or state != State.ACTIVE:
		return "No extraction to confirm"
	if points.is_empty():
		return "No extraction point: pick one on the map or throw a purple smoke"
	var point := point_with_squad()
	if point.is_empty():
		var nearest := _nearest_point()
		var why := "Not everyone is at the extraction point. Waiting for: %s" % ", ".join(missing_at(nearest))
		_client_message.rpc(why)
		return why
	state = State.COUNTDOWN
	countdown_point = int(point.id)
	countdown_left = countdown_s
	_last_whole = -1
	_broadcast()
	_client_message.rpc("Extracting from %s in %d s: stay inside" % [point.name, ceili(countdown_s)])
	return ""


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_smoke_check -= delta
	if _smoke_check <= 0.0:
		_smoke_check = SMOKE_CHECK_S
		_check_smoke()
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
			server_add_point(Vector2(p.x, p.z), "smoke")


func _run_countdown(delta: float) -> void:
	var point := point_by_id(countdown_point)
	var missing := missing_at(point) if not point.is_empty() else PackedStringArray(["the point"])
	if not missing.is_empty():
		state = State.ACTIVE
		countdown_point = -1
		_broadcast()
		_client_message.rpc("Extraction stopped: %s left the extraction point" % ", ".join(missing))
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
	state = State.ENDED
	countdown_left = 0.0
	var report := build_report(point)
	last_report = report
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
	var out_soldiers: Array[Soldier] = []
	var players: Array = []
	var squad: Array = []
	for s: Soldier in need.players:
		players.append(_soldier_record(s))
		out_soldiers.append(s)
	for s: Soldier in need.ai:
		squad.append(_soldier_record(s))
		out_soldiers.append(s)
	var left: Array = []
	for s: Soldier in MapNodes.squad_ai(self):
		if s not in need.ai:
			var p := s.global_position
			left.append({"name": String(s.name), "role": String(s.role), "slot": s.squad_slot, "alive": true,
				"downed": not s.vitals.is_up(), "chosen": leave.has(String(s.name)), "pos": [p.x, p.y, p.z]})
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
		if carried.has(body) or inside(point, body.global_position):
			record["items"] = items_of(body.inventory)
			bodies.append(record)
		elif body.faction == &"friendly":
			bodies_left.append(record)
	var hvts: Array = []
	for node in get_tree().get_nodes_in_group(HVT_GROUP):
		var n := node as Node3D
		if n == null or not (carried.has(n) or inside(point, n.global_position)):
			continue
		var record := {"name": String(n.name), "alive": true, "faction": String(n.get(&"faction")) if n.get(&"faction") != null else ""}
		var vitals := n.get_node_or_null(^"Vitals") as Vitals
		if vitals:
			record["alive"] = not vitals.is_dead()
		if n.has_method(&"hvt_record"):
			record.merge(n.call(&"hvt_record"), true)
		hvts.append(record)
	var deposited: Array = []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item and not item.is_queued_for_deletion() and inside(point, item.global_position):
			var entry := {"id": String(item.item_id), "count": item.count, "where": "deposited", "uid": item.uid}
			if not item.state.is_empty():
				entry["state"] = item.state.duplicate(true)
			deposited.append(entry)
	var totals := {}
	for group: Array in [players, squad, bodies]:
		for record: Dictionary in group:
			_add_totals(totals, record.items)
	_add_totals(totals, deposited)
	var objectives: Array = []
	for o: Dictionary in MapView.objectives_in(self):
		objectives.append({"id": o.get("id", ""), "title": o.get("title", ""), "state": o.get("state", "")})
	var pos: Vector2 = point.get("pos", Vector2.ZERO)
	return {"contract_id": String(_plan.get("contract", {}).get("id", "")), "zone_id": GameState.zone_id,
		"point": {"name": String(point.get("name", "")), "pos": [pos.x, pos.y], "source": String(point.get("source", ""))},
		"duration_s": (Time.get_ticks_msec() - _started_msec) / 1000.0,
		"players": players, "squad": squad, "left_behind": left, "bodies": bodies, "bodies_left": bodies_left,
		"hvts": hvts, "deposited": deposited, "items": totals, "objectives": objectives}


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


func _nearest_point() -> Dictionary:
	var me := MapNodes.players(self)
	var from := Vector2(me[0].global_position.x, me[0].global_position.z) if not me.is_empty() else Vector2.ZERO
	var best: Dictionary = points[0]
	for p: Dictionary in points:
		if from.distance_to(p.pos) < from.distance_to(best.pos):
			best = p
	return best


func _add_point(pos: Vector2, source: String, point_name: String, radius: float) -> int:
	if source != "zone":
		points = points.filter(func(p: Dictionary) -> bool: return p.source != source)
	var id := _next_id
	_next_id += 1
	if point_name == "":
		point_name = {"grid": "Grid LZ", "smoke": "Purple smoke"}.get(source, "LZ %d" % id)
	points.append({"id": id, "name": point_name, "pos": pos, "radius": radius, "source": source})
	return id


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


@rpc("any_peer", "call_local", "reliable")
func _server_confirm() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and (sender == 0 or sender == 1):
		server_confirm()


func _state() -> Dictionary:
	return {"state": state, "points": points, "leave": leave.keys(), "countdown": countdown_left, "point": countdown_point}


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
