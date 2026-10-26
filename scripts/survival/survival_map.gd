class_name SurvivalMap
extends Node
## What the survivors know of the world (docs/survival.md calls 37 and 45, phase A step 7;
## survival_world.md section 10): a static API over Survival.state()'s "map" section, plus the
## level's node (one per SurvivalLevel, "SurvivalMap", the same path on every peer) that records
## exploration on the host and sends the section to the peers.
##
## The "map" section (host, saved with the world):
## - "explored": zone id -> {"cx,cz": 1}: the CELL_M cells the survivors have been within SEE_M of;
## - "known": zone id -> {"how": "visited"|"told", "day": world day}: the zones drawn on the map;
## - "marks": [{"zone", "pos": [x, y, z], "text", "kind", "day_added", "day_seen"}] (world days as
##   floats; "day_seen" may be missing: day_added stands in). A mark's age is the days since it
##   was last seen; past FADE_DAYS it's "faded" (drawn faint: a camp seen three days ago may be
##   gone). The safehouse (the start zone's insertion point) is a mark from the start.
## Peers draw from `view()`: the host's section, or the copy the host last sent (on join and on
## every change).

signal changed

const NODE_NAME := "SurvivalMap"
const KEY := "map"
## Proposed: the cell size (the same as the dead's thinning cells) and how near a survivor must
## come for a cell to count as explored.
const CELL_M := 64.0
const SEE_M := 120.0
## Proposed: marks older than this (world days since last seen) are faded.
const FADE_DAYS := 3.0
## Proposed: a survivor within this of a mark sees it again (its age starts over).
const MARK_SEEN_M := 30.0
## Proposed: the host's tick, and how often the peers hear the world's day.
const TICK_S := 1.0
const NOW_S := 30.0
## Proposed: the safehouse never fades (it's yours).
const NO_FADE_KINDS := ["safehouse", "grave"]  # (a grave: Legacy, call 130)

## Peer: the host's map section as last sent, and the world day with it.
static var _client := {}
static var _client_now := 1.0
static var _client_zone := ""

var _tick := 0.0
var _now_t := 0.0


# --- The static API ------------------------------------------------------------------------

## The host's map section (made on first use), in Survival.state().
static func section() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	var m: Dictionary = st[KEY]
	if not m.get("explored") is Dictionary:
		m["explored"] = {}
	if not m.get("known") is Dictionary:
		m["known"] = {}
	if not m.get("marks") is Array:
		m["marks"] = []
	return m


## What this peer draws: the host's section, or the copy the host sent.
static func view() -> Dictionary:
	if Survival.running:
		return section()
	return _client


## The world's time now in days (day + hour / 24): the host's clock, or the last the host sent.
static func now() -> float:
	if Survival.running:
		return Survival.day() + Survival.hour() / 24.0
	return _client_now


## The zone being played: the host's, or the one the host last named.
static func current_zone() -> String:
	if Survival.running:
		return String(Survival.state().get("zone", ""))
	return _client_zone


static func cell_key(pos: Vector3) -> String:
	return "%d,%d" % [floori(pos.x / CELL_M), floori(pos.z / CELL_M)]


## Whether the cell at `pos` of `zone_id` has been explored.
static func is_explored(zone_id: String, pos: Vector3) -> bool:
	var cells: Variant = (view().get("explored", {}) as Dictionary).get(zone_id)
	return cells is Dictionary and (cells as Dictionary).has(cell_key(pos))


## The explored cells of `zone_id` ({"cx,cz": 1}).
static func explored(zone_id: String) -> Dictionary:
	var cells: Variant = (view().get("explored", {}) as Dictionary).get(zone_id)
	return cells if cells is Dictionary else {}


## Host: the cells within SEE_M of `pos` in `zone_id` become explored; returns the new ones.
static func server_explore(zone_id: String, pos: Vector3) -> Array:
	var all: Dictionary = section().explored
	if not all.get(zone_id) is Dictionary:
		all[zone_id] = {}
	var cells: Dictionary = all[zone_id]
	var fresh: Array = []
	var r := ceili(SEE_M / CELL_M)
	var cx := floori(pos.x / CELL_M)
	var cz := floori(pos.z / CELL_M)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var centre := Vector2((cx + dx + 0.5) * CELL_M, (cz + dz + 0.5) * CELL_M)
			if centre.distance_to(Vector2(pos.x, pos.z)) > SEE_M:
				continue
			var key := "%d,%d" % [cx + dx, cz + dz]
			if not cells.has(key):
				cells[key] = 1
				fresh.append(key)
	return fresh


## The zones on the map (visited or told): zone id -> {"how", "day"}.
static func known() -> Dictionary:
	return view().get("known", {})


static func is_known(zone_id: String) -> bool:
	return known().has(zone_id)


## Host: `zone_id` goes on the map (`how` "visited" or "told"; visited wins).
static func server_know(zone_id: String, how := "visited") -> bool:
	var k: Dictionary = section().known
	if k.has(zone_id) and (String((k[zone_id] as Dictionary).get("how", "")) == "visited" or how == "told"):
		return false
	k[zone_id] = {"how": how, "day": Survival.day() + Survival.hour() / 24.0}
	return true


## The marks in `zone_id` ("" all of them).
static func marks(zone_id := "") -> Array:
	var all: Variant = view().get("marks", [])
	if not all is Array:
		return []
	if zone_id == "":
		return all
	return (all as Array).filter(func(m: Variant) -> bool: return m is Dictionary and String((m as Dictionary).get("zone", "")) == zone_id)


## Host: a mark at `pos` (Vector3, or [x, y, z] / [x, z]) in `zone_id`; returns it.
static func server_add_mark(zone_id: String, pos: Variant, text: String, kind := "note") -> Dictionary:
	var t := Survival.day() + Survival.hour() / 24.0
	var m := {"zone": zone_id, "pos": _pos_array(pos), "text": text.strip_edges().left(80), "kind": kind, "day_added": t, "day_seen": t}
	(section().marks as Array).append(m)
	return m


## Host: removes the mark `index` (in marks("")); returns whether it was there.
static func server_remove_mark(index: int) -> bool:
	var all: Array = section().marks
	if index < 0 or index >= all.size():
		return false
	all.remove_at(index)
	return true


## A mark's position on its zone's ground (x, z).
static func mark_pos(m: Dictionary) -> Vector2:
	var p: Variant = m.get("pos", [0, 0])
	if p is Vector3:
		return Vector2(p.x, p.z)
	if p is Vector2:
		return p
	var a: Array = p if p is Array else []
	if a.size() >= 3:
		return Vector2(float(a[0]), float(a[2]))
	if a.size() == 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


## How old a mark is in world days: since it was last seen (or added).
static func age_days(m: Dictionary) -> float:
	var seen := float(m.get("day_seen", m.get("day_added", now())))
	return maxf(now() - seen, 0.0)


## Whether a mark is past the fade line (FADE_DAYS; never the safehouse).
static func is_faded(m: Dictionary) -> bool:
	return not String(m.get("kind", "")) in NO_FADE_KINDS and age_days(m) >= FADE_DAYS


## A mark's age as the map writes it ("today", "1 day", "4 days").
static func age_text(m: Dictionary) -> String:
	var d := floori(age_days(m))
	return "today" if d < 1 else ("1 day" if d == 1 else "%d days" % d)


## The safehouse mark, or {}.
static func safehouse() -> Dictionary:
	for m: Variant in marks(""):
		if m is Dictionary and String((m as Dictionary).get("kind", "")) == "safehouse":
			return m
	return {}


static func _pos_array(pos: Variant) -> Array:
	if pos is Vector3:
		return [pos.x, pos.y, pos.z]
	if pos is Vector2:
		return [pos.x, 0.0, pos.y]
	if pos is Array and (pos as Array).size() == 2:
		return [float(pos[0]), 0.0, float(pos[1])]
	return (pos as Array).duplicate() if pos is Array else [0.0, 0.0, 0.0]


## The node of `level` (or of the level `from` is in), if it's a survival zone.
static func of(from: Node) -> SurvivalMap:
	if from == null:
		return null
	var level := SurvivalLevel.of(from)
	return level.get_node_or_null(NODE_NAME) as SurvivalMap if level else null


# --- The level's node ----------------------------------------------------------------------

func _ready() -> void:
	name = NODE_NAME
	if multiplayer.is_server():
		_server_start.call_deferred()
	elif multiplayer.has_multiplayer_peer():
		_server_request.rpc_id(1)


## Host: the zone being played is visited; a new world's start zone gets the safehouse.
func _server_start() -> void:
	if not Survival.running:
		return
	var zone := String(Survival.state().get("zone", ""))
	var dirty := server_know(zone, "visited")
	if safehouse().is_empty() and zone == String(Survival.state().get("start_zone", "")):
		var level := get_parent() as ZoneLevel
		var points: Array[Vector3] = []
		if level:
			points = level.insertion_points()
		if not points.is_empty():
			var home := server_add_mark(zone, points[0], "Safehouse", "safehouse")
			home["auto"] = true  # (gives way to the cold open's own)
			dirty = true
	if dirty:
		server_changed()


## Host: tell everyone the map changed (the whole section: small; the cells go as they come).
func server_changed() -> void:
	changed.emit()
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_client_map.rpc(section(), now(), current_zone())


func _process(delta: float) -> void:
	if not Survival.running or not multiplayer.is_server():
		return
	_tick += delta
	_now_t += delta
	if _tick >= TICK_S:
		_tick = 0.0
		server_tick()
	if _now_t >= NOW_S:
		_now_t = 0.0
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
			_client_day.rpc(now())


## Host: one look about: every survivor's cells, and the marks he's beside seen again.
func server_tick() -> void:
	var level := get_parent()
	var zone := String(Survival.state().get("zone", ""))
	if level == null or zone == "":
		return
	var fresh: Array = []
	var seen := false
	var t := now()
	for s: Soldier in MapNodes.players(level):
		if not s.vitals.is_up():
			continue
		for key: String in server_explore(zone, s.global_position):
			if not key in fresh:
				fresh.append(key)
		var at := Vector2(s.global_position.x, s.global_position.z)
		for m: Dictionary in marks(zone):
			if mark_pos(m).distance_to(at) <= MARK_SEEN_M and t - float(m.get("day_seen", m.get("day_added", t))) > 0.01:
				m["day_seen"] = t
				seen = true
	if _drop_auto_safehouse():
		seen = true
	if seen:
		server_changed()
	elif not fresh.is_empty():
		changed.emit()
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
			_client_cells.rpc(zone, PackedStringArray(fresh))


## Host: the cold open writes its own safehouse ("The farm") straight into the section; if it
## came after ours, ours goes. Returns whether one went.
func _drop_auto_safehouse() -> bool:
	var all: Array = section().marks
	var safe := all.filter(func(m: Variant) -> bool: return m is Dictionary and String((m as Dictionary).get("kind", "")) == "safehouse")
	if safe.size() < 2:
		return false
	for m: Dictionary in safe:
		if m.get("auto", false):
			all.erase(m)
			return true
	return false


## Any peer: asks for a mark (the host adds it and tells everyone).
func request_add_mark(zone_id: String, pos: Vector2, text: String) -> void:
	if multiplayer.is_server():
		_do_add_mark(zone_id, pos, text)
	else:
		_server_add_mark.rpc_id(1, zone_id, pos, text)


## Any peer: asks for mark `index` (in marks("")) to go.
func request_remove_mark(index: int) -> void:
	if multiplayer.is_server():
		if server_remove_mark(index):
			server_changed()
	else:
		_server_remove_mark.rpc_id(1, index)


func _do_add_mark(zone_id: String, pos: Vector2, text: String) -> void:
	if not RegionMap.layout().has(zone_id) or text.strip_edges() == "":
		return
	var y := 0.0
	var level := get_parent() as ZoneLevel
	if level and zone_id == String(Survival.state().get("zone", "")):
		y = level.ground_point(Vector3(pos.x, 0.0, pos.y)).y
	server_add_mark(zone_id, Vector3(pos.x, y, pos.y), text, "note")
	server_changed()


@rpc("any_peer", "call_remote", "reliable")
func _server_request() -> void:
	if multiplayer.is_server():
		_client_map.rpc_id(multiplayer.get_remote_sender_id(), section(), now(), current_zone())


@rpc("any_peer", "call_remote", "reliable")
func _server_add_mark(zone_id: String, pos: Vector2, text: String) -> void:
	if multiplayer.is_server():
		_do_add_mark(zone_id, pos, text)


@rpc("any_peer", "call_remote", "reliable")
func _server_remove_mark(index: int) -> void:
	if multiplayer.is_server() and server_remove_mark(index):
		server_changed()


@rpc("authority", "call_remote", "reliable")
func _client_map(data: Dictionary, day_now: float, zone_id: String) -> void:
	_client = data
	_client_now = day_now
	_client_zone = zone_id
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _client_cells(zone_id: String, keys: PackedStringArray) -> void:
	if not _client.get("explored") is Dictionary:
		_client["explored"] = {}
	var all: Dictionary = _client.explored
	if not all.get(zone_id) is Dictionary:
		all[zone_id] = {}
	for k in keys:
		(all[zone_id] as Dictionary)[k] = 1
	changed.emit()


@rpc("authority", "call_remote", "unreliable")
func _client_day(day_now: float) -> void:
	_client_now = day_now
