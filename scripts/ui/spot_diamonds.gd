class_name SpotDiamonds
extends Control
## The side's spot reports in the world (docs/combined_arms.md 4.4, B1): a small diamond over each
## spot marker (MapMarkers kind "spot": the friendly SidePicture, nothing else) within the
## setting's range (hud "spot_diamond_range_m", 800 m; "spot_diamonds" off hides them all), that
## the player can't see himself: one in his view within see_self_m with a clear line to it is his
## own sighting and gets none. Red for a player's tag once EnemyTags' own mark over the man has
## gone, amber for everyone else's reports; fading as it ages (fresh, aged, stale). Drawn on the
## HUD (Hud._ready), every peer. Numbers in data/side_picture.json "world", Proposed.

const SIZE_PX := 6.0
const ALPHA := {"fresh": 0.95, "aged": 0.6, "stale": 0.3}
const AMBER := Color(1.0, 0.7, 0.15)

var player: Soldier
## Spot marker ids the player sees for himself now (no diamond).
var own_sight := {}
## What the last draw put on screen: [{"id", "at": Vector2, "colour"}] (tests).
var drawn: Array[Dictionary] = []
var _check := 0.0


func _init(p_player: Soldier = null) -> void:
	player = p_player
	name = "SpotDiamonds"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0 / maxf(float((SidePicture.data().get("world", {}) as Dictionary).get("check_hz", 4.0)), 0.5)
		_check_sight()
	queue_redraw()


## The spots the player could see from here: shown, within see_self_m, a clear line from the eye.
func _check_sight() -> void:
	own_sight.clear()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var markers := MapNodes.markers(player) if player and player.is_inside_tree() else null
	if cam == null or markers == null:
		return
	var near := float((SidePicture.data().get("world", {}) as Dictionary).get("see_self_m", 150.0))
	var space := cam.get_world_3d().direct_space_state
	for marker: Dictionary in markers.list("intel"):
		if marker.kind != "spot":
			continue
		var at := _world(marker)
		if cam.global_position.distance_to(at) > near or not cam.is_position_in_frustum(at):
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, at)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(at) <= 2.5:
			own_sight[int(marker.id)] = true


static func _world(marker: Dictionary) -> Vector3:
	var p: Vector2 = marker.points[0]
	return Vector3(p.x, float(marker.spot.get("y", 0.0)) + 1.0, p.y)


func _draw() -> void:
	drawn.clear()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for d: Dictionary in shown(cam):
		var s: Vector2 = cam.unproject_position(d.at)
		var colour: Color = d.colour
		var r := SIZE_PX
		var pts := PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)])
		draw_colored_polygon(pts, colour)
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, colour.a * 0.8), 1.0)
		drawn.append({"id": d.id, "at": s, "colour": colour})


## The diamonds to draw from `cam`: [{"id" (spot marker), "at" (world), "colour"}]. None with the
## setting off.
func shown(cam: Camera3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cam == null or player == null or not player.is_inside_tree() or not bool(GameSettings.get_value("hud", "spot_diamonds")):
		return out
	var markers := MapNodes.markers(player)
	if markers == null:
		return out
	var reach := float(GameSettings.get_value("hud", "spot_diamond_range_m"))
	var tags := EnemyTags.of(player)
	for marker: Dictionary in markers.list("intel"):
		if marker.kind != "spot" or own_sight.has(int(marker.id)):
			continue
		var at := _world(marker)
		if cam.global_position.distance_to(at) > reach or cam.is_position_behind(at):
			continue
		var spot: Dictionary = marker.spot
		if tags and (spot.get("tag_names", []) as Array).any(func(n: Variant) -> bool: return tags.tags.has(String(n))):
			continue  # EnemyTags still marks the man himself
		var colour: Color = EnemyTags.MARK_COLOUR if bool(spot.get("tag", false)) else AMBER
		colour.a = float(ALPHA.get(MapMarkers.spot_band(marker), 0.3))
		out.append({"id": int(marker.id), "at": at, "colour": colour})
	return out
