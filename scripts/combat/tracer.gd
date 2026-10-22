class_name Tracer
extends Node3D
## A visible tracer streak for a shot, spawned on every peer (CompoundLevel.show_tracer).
## Captain, 2026-10-16: "we dont have tracers or bullets that can be seen in game yet". Purely
## visual (hitscan is instant; Ballistics/Sfx already resolve the shot) — a thin unshaded streak
## runs from the muzzle to the impact point at DRAW_MPS, holds, then fades over FADE_S and frees
## itself. It runs along the round's real path (Ballistics.flight_path: Captain, 2026-10-21, the
## "flight paths and ballistic arcs ... still wonky depending on terrain"), the same arc and drop
## the host traced, not a straight line to the hit: up off the barrel and down onto a slope, a
## wall or a man 800 m out, ending exactly at the impact, on every peer.

const WIDTH := 0.025
const DRAW_MPS := 260.0  # stylised, not the round's real velocity: fast but readable
const MIN_DRAW_S := 0.03
const HOLD_S := 0.03
const FADE_S := 0.12
## Kinds (Captain, 2026-10-16: "red tracers for us, green for the enemy, and not every round is a
## tracer but every round can be heard felt seen"): a tracer round burns red (our side) or green
## (the enemy's); a ball round still shows as a faint, thin streak (BALL), so every round is seen.
enum Kind { BALL, RED, GREEN }
const COLOURS := {Kind.BALL: Color(0.92, 0.9, 0.85, 0.16), Kind.RED: Color(1.0, 0.22, 0.12), Kind.GREEN: Color(0.35, 1.0, 0.3)}
const BALL_WIDTH := 0.012
## A suppressed shot's streak keeps this share of its alpha.
const SUPPRESSED_ALPHA := 0.35

## A peer that draws the shooter a moment behind (Soldier._smooth_remote) starts the streak at the
## gun it sees, `lead` off the real muzzle, and brings it onto the real path over this many metres.
const LEAD_BLEND_M := 12.0

var _points := PackedVector3Array()  # the path, muzzle to impact (Ballistics.flight_path)
var _along := PackedFloat32Array()  # metres along the path to each point
var _length := 0.0
var _lead := Vector3.ZERO
var _mesh: MeshInstance3D
var _width := WIDTH
## Perf pass (2026-10-22): every streak draws one unit box (scaled to its width and length) in one
## of a few shared materials (by kind and dimness), fading by its own transparency, where each
## shot used to make its own BoxMesh and StandardMaterial3D (and resize the box, which rebuilds
## it, every frame). The streak looks the same.
static var _unit_box: BoxMesh
static var _materials := {}  # [kind, dim] -> StandardMaterial3D
## Tests: the latest tracer's path, as drawn (lead included), on this peer.
static var last_path := PackedVector3Array()


## Spawns a straight tracer from `origin` to `end` under `parent` (the level). `dim` (suppressed
## shots): a fainter streak, since a subsonic round gives little away.
static func spawn(parent: Node, origin: Vector3, end: Vector3, dim := false, kind: int = Kind.RED) -> void:
	spawn_path(parent, PackedVector3Array([origin, end]), dim, kind)


## Spawns a tracer along `points` (Ballistics.flight_path: muzzle first, impact last) under
## `parent`, its start `lead` off the first point (LEAD_BLEND_M).
static func spawn_path(parent: Node, points: PackedVector3Array, dim := false, kind: int = Kind.RED, lead := Vector3.ZERO) -> Tracer:
	var t := Tracer.new()
	parent.add_child(t)
	t._start(points, dim, kind, lead)
	return t


func _start(points: PackedVector3Array, dim: bool, kind: int, lead: Vector3) -> void:
	_points = points
	_lead = lead if lead.is_finite() else Vector3.ZERO
	last_path = points
	if points.size() < 2:
		queue_free()
		return
	_along.resize(points.size())
	for i in points.size():
		_length += points[i].distance_to(points[i - 1]) if i > 0 else 0.0
		_along[i] = _length
	last_path = PackedVector3Array()
	for i in points.size():
		last_path.append(point_at(_along[i]))
	if _length < 0.05:
		queue_free()
		return
	top_level = true
	global_transform = Transform3D.IDENTITY  # the streak's placed in world space (_set_drawn)
	_width = BALL_WIDTH if kind == Kind.BALL else WIDTH
	_mesh = MeshInstance3D.new()
	_mesh.mesh = unit_box()
	_mesh.material_override = material(kind, dim)
	add_child(_mesh)
	_set_drawn(0.0)
	var draw_s := maxf(_length / DRAW_MPS, MIN_DRAW_S)
	var tween := create_tween()
	tween.tween_method(_set_drawn, 0.0, _length, draw_s)
	tween.tween_interval(HOLD_S)
	tween.tween_property(_mesh, "transparency", 1.0, FADE_S)
	tween.tween_callback(queue_free)


## The box every streak draws (a 1 m cube, scaled by its transform).
static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


## The shared material of a streak of `kind` (`dim`: a suppressed shot's).
static func material(kind: int, dim: bool) -> StandardMaterial3D:
	var key := [kind, dim]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var colour: Color = COLOURS.get(kind, COLOURS[Kind.RED])
		if dim:
			colour.a *= SUPPRESSED_ALPHA
		m.albedo_color = colour
		_materials[key] = m
	return _materials[key]


## Where the round was `s` metres along its path (the lead blended out over LEAD_BLEND_M).
func point_at(s: float) -> Vector3:
	var i := 1
	while i < _points.size() - 1 and _along[i] < s:
		i += 1
	var seg := _along[i] - _along[i - 1]
	var p := _points[i - 1].lerp(_points[i], clampf((s - _along[i - 1]) / seg, 0.0, 1.0)) if seg > 0.0 else _points[i]
	return p + _lead * maxf(1.0 - s / LEAD_BLEND_M, 0.0)


## The streak `drawn` metres along the path: its head at the round's current reach, its tail
## TAIL_M behind (or the muzzle, whichever is closer), a straight piece of the arc between.
const TAIL_M := 4.0
func _set_drawn(drawn: float) -> void:
	var head := point_at(drawn)
	var tail := point_at(maxf(drawn - TAIL_M, 0.0))
	var span := head - tail
	if span.length_squared() < 0.000001:
		_mesh.visible = false
		return
	_mesh.visible = true
	var basis := Basis.looking_at(span, Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT)
	_mesh.transform = Transform3D(basis.scaled_local(Vector3(_width, _width, maxf(span.length(), 0.001))), (head + tail) * 0.5)


## The streak's head and tail now (tests).
func streak() -> Array[Vector3]:
	var half := _mesh.basis.z * 0.5  # (the unit box scaled to the streak's length)
	return [_mesh.position - half, _mesh.position + half]  # looking_at points -Z at the head
