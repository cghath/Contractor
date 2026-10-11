class_name MapMarkers
extends Node
## Markers and lines on the map, shared by every player like Arma's global channel: anyone
## can place, move and delete them, on the map (M) or on the briefing's map. The host keeps
## the list and decides every change; each change goes to every peer, and a player who joins
## gets the whole list (late joiners see everything placed before).
##
## A marker is a Dictionary:
##   "id" (int), "kind" ("point", "enemy" or "line"), "points" (PackedVector2Array of ground
##   points (x, z) in metres: one for a point or enemy, 2 or more for a line), "text",
##   "colour" (a name in COLOURS), "channel" ("field" for markers placed in play, "plan" for
##   the briefing's plan marks, "intel" for enemy positions known from intel or reported) and
##   "author" (the peer that placed it; 0 for the game itself).
## Other parts report enemy positions with server_report_enemy (intel, radio reports).

signal changed

const KINDS: Array[String] = ["point", "enemy", "line"]
const CHANNELS: Array[String] = ["field", "plan", "intel"]
## Marker colours by name, as on an Arma map.
const COLOURS := {
	"black": Color(0.08, 0.08, 0.08),
	"red": Color(0.85, 0.15, 0.12),
	"blue": Color(0.15, 0.35, 0.9),
	"green": Color(0.15, 0.6, 0.2),
	"orange": Color(0.95, 0.55, 0.1),
	"purple": Color(0.6, 0.3, 0.75),
	"white": Color(0.95, 0.95, 0.95),
}
const MAX_TEXT := 48
## Proposed: limits that keep the list small enough to send whole to a late joiner.
const MAX_MARKERS := 300
const MAX_LINE_POINTS := 64

## Every peer: the markers by id (the host's copy is the real one).
var markers: Dictionary = {}
var _next_id := 1


func _init() -> void:
	name = "MapMarkers"


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)


## The colour for a colour name (black if unknown).
static func colour_value(colour_name: String) -> Color:
	return COLOURS.get(colour_name, COLOURS["black"])


## Markers sorted by id, optionally only one channel's.
func list(channel := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := markers.keys()
	ids.sort()
	for id: int in ids:
		if channel == "" or markers[id].channel == channel:
			out.append(markers[id])
	return out


# --- Requests (any peer) --------------------------------------------------------

## Asks the host to place a marker (see the class doc for the fields).
func request_add(kind: String, points: PackedVector2Array, text := "", colour := "black", channel := "field") -> void:
	_server_add.rpc_id(1, kind, points, text, colour, channel)


## Asks the host to move marker `id` so its first point is at `to` (a line moves whole).
func request_move(id: int, to: Vector2) -> void:
	_server_move.rpc_id(1, id, to)


func request_remove(id: int) -> void:
	_server_remove.rpc_id(1, id)


# --- Host -----------------------------------------------------------------------

## Host only. Adds a marker from `data` (kind, points, text, colour, channel, author);
## returns its id, or 0 if it isn't valid.
func server_add(data: Dictionary) -> int:
	if not multiplayer.is_server() or markers.size() >= MAX_MARKERS:
		return 0
	var clean := _clean(data)
	if clean.is_empty():
		return 0
	var id := _next_id
	_next_id += 1
	clean["id"] = id
	_client_set.rpc(id, clean)
	return id


## Host only. Marks an enemy position known from intel or reported (`pos` on the ground,
## Vector3 or Vector2 (x, z)). Returns the marker id.
func server_report_enemy(pos: Variant, text := "", channel := "intel") -> int:
	var p := Vector2(pos.x, pos.z) if pos is Vector3 else pos as Vector2
	return server_add({"kind": "enemy", "points": PackedVector2Array([p]), "text": text, "colour": "red", "channel": channel, "author": 0})


## Host only.
func server_move(id: int, to: Vector2) -> bool:
	if not multiplayer.is_server() or not markers.has(id) or not to.is_finite():
		return false
	var marker: Dictionary = markers[id].duplicate(true)
	var points: PackedVector2Array = marker.points
	var shift := to - points[0]
	for i in points.size():
		points[i] += shift
	marker.points = points
	_client_set.rpc(id, marker)
	return true


## Host only.
func server_remove(id: int) -> bool:
	if not multiplayer.is_server() or not markers.has(id):
		return false
	_client_remove.rpc(id)
	return true


## Host only. Removes every marker (on one channel, or all for "").
func server_clear(channel := "") -> void:
	for marker: Dictionary in list(channel):
		server_remove(marker.id)


@rpc("any_peer", "call_local", "reliable")
func _server_add(kind: String, points: PackedVector2Array, text: String, colour: String, channel: String) -> void:
	if multiplayer.is_server() and channel != "intel" and _finite(points):  # intel comes from the game, not from players
		server_add({"kind": kind, "points": points, "text": text, "colour": colour, "channel": channel, "author": _sender()})


@rpc("any_peer", "call_local", "reliable")
func _server_move(id: int, to: Vector2) -> void:
	if multiplayer.is_server() and to.is_finite():
		server_move(id, to)


## Whether every point a player sent is finite (audit L6-01).
static func _finite(points: PackedVector2Array) -> bool:
	for p in points:
		if not p.is_finite():
			return false
	return true


@rpc("any_peer", "call_local", "reliable")
func _server_remove(id: int) -> void:
	if multiplayer.is_server():
		server_remove(id)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## A valid copy of a marker's fields, or {} if it isn't one.
func _clean(data: Dictionary) -> Dictionary:
	var kind := String(data.get("kind", "point"))
	var raw: Variant = data.get("points", PackedVector2Array())
	var points := PackedVector2Array(raw) if raw is PackedVector2Array or raw is Array else PackedVector2Array()
	if kind not in KINDS or points.is_empty():
		return {}
	if kind == "line":
		if points.size() < 2:
			return {}
		if points.size() > MAX_LINE_POINTS:
			points = _thin(points, MAX_LINE_POINTS)
	else:
		points = PackedVector2Array([points[0]])
	for p in points:
		if not p.is_finite():
			return {}
	var colour := String(data.get("colour", "black"))
	var channel := String(data.get("channel", "field"))
	return {"kind": kind, "points": points, "text": String(data.get("text", "")).strip_edges().left(MAX_TEXT),
		"colour": colour if COLOURS.has(colour) else "black", "channel": channel if channel in CHANNELS else "field",
		"author": int(data.get("author", 0))}


## Every n-th point of a long line, keeping both ends.
static func _thin(points: PackedVector2Array, most: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := float(points.size() - 1) / float(most - 1)
	for i in most:
		out.append(points[mini(roundi(i * step), points.size() - 1)])
	return out


# --- Every peer -----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _client_set(id: int, marker: Dictionary) -> void:
	markers[id] = marker
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_remove(id: int) -> void:
	markers.erase(id)
	changed.emit()


## A late joiner gets every marker at once.
@rpc("authority", "call_remote", "reliable")
func _client_snapshot(all: Array) -> void:
	markers.clear()
	for marker: Dictionary in all:
		markers[int(marker.id)] = marker
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_client_snapshot.rpc_id(id, markers.values())
