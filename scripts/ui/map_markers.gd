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
##
## Spot reports (docs/combined_arms.md 4.4, B1): kind "spot", channel "intel", placed and kept by
## the host from the friendly side's picture (SideIntel) and nobody else; players can't move or
## delete them. Its "spot" holds what's drawn: {"entry", "what" (SidePicture kind), "count",
## "age" and "reported_age" (s, when sent), "unc" (m, when sent), "by", "tag", "tag_names",
## "reports" (the report ids it traces to)}; every peer ages it from "recv" (its own clock when
## it arrived). Drawn by draw_spot (MapView) and SpotDiamonds (the HUD).

signal changed

const KINDS: Array[String] = ["point", "enemy", "line", "spot"]
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


## Host only (SideIntel): a spot report (see the class doc) at spot.pos. Returns the marker id.
func server_spot(spot: Dictionary) -> int:
	return server_add({"kind": "spot", "points": PackedVector2Array([spot.pos]), "text": "", "colour": spot_colour(spot),
		"channel": "intel", "author": 0, "spot": spot})


## Host only (SideIntel): spot marker `id` changed (merged, moved).
func server_spot_update(id: int, spot: Dictionary) -> bool:
	if not multiplayer.is_server() or not markers.has(id) or markers[id].kind != "spot":
		return false
	var clean := _clean({"kind": "spot", "points": PackedVector2Array([spot.pos]), "text": "", "colour": spot_colour(spot),
		"channel": "intel", "author": 0, "spot": spot})
	if clean.is_empty():
		return false
	clean["id"] = id
	_client_set.rpc(id, clean)
	return true


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
	if multiplayer.is_server() and to.is_finite() and not _fixed(id):
		server_move(id, to)


## Whether every point a player sent is finite (audit L6-01).
static func _finite(points: PackedVector2Array) -> bool:
	for p in points:
		if not p.is_finite():
			return false
	return true


@rpc("any_peer", "call_local", "reliable")
func _server_remove(id: int) -> void:
	if multiplayer.is_server() and not _fixed(id):
		server_remove(id)


## Spot reports are the side's, not a player's to move or delete.
func _fixed(id: int) -> bool:
	return markers.has(id) and markers[id].kind == "spot"


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
	var out := {"kind": kind, "points": points, "text": String(data.get("text", "")).strip_edges().left(MAX_TEXT),
		"colour": colour if COLOURS.has(colour) else "black", "channel": channel if channel in CHANNELS else "field",
		"author": int(data.get("author", 0))}
	if kind == "spot":
		if not (data.get("spot") is Dictionary):
			return {}
		out["spot"] = (data.spot as Dictionary).duplicate(true)
		out.channel = "intel"
	return out


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
	if marker.get("kind") == "spot":
		marker["recv"] = Soldier._now()
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
		if marker.get("kind") == "spot":
			marker["recv"] = Soldier._now()
		markers[int(marker.id)] = marker
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		var all: Array = []
		for marker: Dictionary in markers.values():
			if marker.kind == "spot":  # aged to now: the joiner's clock starts here
				var aged := marker.duplicate(true)
				var since := Soldier._now() - float(marker.get("recv", Soldier._now()))
				aged.spot.age = float(marker.spot.age) + since
				aged.spot.reported_age = float(marker.spot.reported_age) + since
				aged.spot.unc = spot_unc(marker)
				all.append(aged)
			else:
				all.append(marker)
		_client_snapshot.rpc_id(id, all)


# --- Spot reports (4.4) --------------------------------------------------------------------------

## The short name of a picture kind on the map.
const SPOT_NAMES := {"inf": "INF", "mg": "MG", "at": "AT", "sniper": "SNIPER", "soft_vehicle": "VEH", "light_armour": "LT ARMOR",
	"ifv": "IFV", "mbt": "TANK", "static_gun": "GUN", "mortar": "MORTAR", "air": "AIR"}


## Red for a player's tag, amber for everyone else's reports.
static func spot_colour(spot: Dictionary) -> String:
	return "red" if bool(spot.get("tag", false)) else "orange"


## Seconds since spot marker `marker` was seen, on this peer's clock.
static func spot_age(marker: Dictionary) -> float:
	return float(marker.spot.age) + Soldier._now() - float(marker.get("recv", Soldier._now()))


## Its uncertainty now (m).
static func spot_unc(marker: Dictionary) -> float:
	var since := Soldier._now() - float(marker.get("recv", Soldier._now()))
	return SidePicture.uncertainty_after(String(marker.spot.what), float(marker.spot.unc), since)


## "fresh", "aged" or "stale".
static func spot_band(marker: Dictionary) -> String:
	return SidePicture.band_of(spot_age(marker))


## "40 s", "2 min".
static func age_text(seconds: float) -> String:
	return "%d s" % roundi(seconds) if seconds < 90.0 else "%d min" % roundi(seconds / 60.0)


## Draws spot marker `marker` on `view` (a MapView) at screen point `s`, APP-6-inspired: a frame
## by kind (the infantry cross in a diamond, armour an oval in a box, MG, AT, mortar marks), the
## count and age, the uncertainty circle; fresh solid, aged dashed, stale only the dashed circle
## labelled "last seen"; the reporter while hovered ("Iron 2, 40 s ago").
static func draw_spot(view: MapView, marker: Dictionary, s: Vector2, hover: bool) -> void:
	var spot: Dictionary = marker.spot
	var band := spot_band(marker)
	var colour := colour_value(String(marker.colour))
	var r := maxf(spot_unc(marker) * view.zoom, 4.0)
	if band == "fresh":
		view.draw_arc(s, r, 0.0, TAU, 48, Color(colour, 0.7), 1.5)
	else:
		var dashes := 24
		for i in range(0, dashes, 2):
			view.draw_arc(s, r, TAU * i / dashes, TAU * (i + 1) / dashes, 4, Color(colour, 0.6 if band == "aged" else 0.4), 1.5)
	var what := String(spot.what)
	var label := "%s x%d, %s" % [SPOT_NAMES.get(what, what.to_upper()), int(spot.count), age_text(spot_age(marker))]
	if band == "stale":
		label = "last seen: " + label
	if hover:
		var heard := float(spot.reported_age) + Soldier._now() - float(marker.get("recv", Soldier._now()))
		label += " (%s, %s ago)" % [String(spot.by), age_text(heard)]
	if band != "stale":
		_spot_symbol(view, what, s, Color(colour, 1.0 if band == "fresh" else 0.7), hover)
	view._label(s, label, colour, "intel")


static func _spot_symbol(view: MapView, what: String, s: Vector2, frame: Color, hover: bool) -> void:
	if SidePicture.is_vehicle_kind(what):
		var box := Rect2(s - Vector2(10, 7), Vector2(20, 14))
		view.draw_rect(box, Color(0.08, 0.08, 0.08, 0.6))
		view.draw_rect(box, frame, false, 2.0)
		match what:
			"light_armour", "ifv", "mbt":  # armour: the oval
				var pts := PackedVector2Array()
				for i in 17:
					var a := TAU * i / 16.0
					pts.append(s + Vector2(cos(a) * 7.0, sin(a) * 3.5))
				view.draw_polyline(pts, frame, 1.5, true)
			"mortar":
				view.draw_line(s + Vector2(0, 5), s + Vector2(0, -5), frame, 1.5)
				view.draw_circle(s + Vector2(0, 5), 1.5, frame)
			_:  # wheels: a soft vehicle, a gun, an aircraft
				view.draw_line(s + Vector2(-6, 3), s + Vector2(6, 3), frame, 1.5)
		return
	var d := 9.0 if hover else 8.0
	var pts := PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)])
	view.draw_colored_polygon(pts, Color(0.08, 0.08, 0.08, 0.6))
	pts.append(pts[0])
	view.draw_polyline(pts, frame, 2.0, true)
	match what:
		"mg":
			view.draw_line(s + Vector2(0, -5), s + Vector2(0, 5), frame, 1.5)
			view.draw_line(s + Vector2(-3, -3), s + Vector2(3, -3), frame, 1.5)
		"at":
			view.draw_line(s + Vector2(-4, 4), s + Vector2(0, -4), frame, 1.5)
			view.draw_line(s + Vector2(4, 4), s + Vector2(0, -4), frame, 1.5)
		"sniper":
			view.draw_arc(s, 3.0, 0.0, TAU, 12, frame, 1.5)
		_:  # the infantry cross
			view.draw_line(s + Vector2(-4, -4), s + Vector2(4, 4), frame, 1.5)
			view.draw_line(s + Vector2(-4, 4), s + Vector2(4, -4), frame, 1.5)
