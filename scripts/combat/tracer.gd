class_name Tracer
extends Node3D
## A visible tracer streak for a shot, spawned on every peer (CompoundLevel.show_tracer).
## Captain, 2026-10-16: "we dont have tracers or bullets that can be seen in game yet". Purely
## visual (hitscan is instant; Ballistics/Sfx already resolve the shot) — a chain of thin
## unshaded boxes along the round's real gravity-curved path (Ballistics.fire's "path"), growing
## from the muzzle to the impact point over DRAW_S (scaled by distance so a long shot doesn't
## snap into place), holding, then fading over FADE_S and freeing itself.
##
## Captain, 2026-10-17: "shooting uphill...rounds drop more aggressively, aiming over the hill
## they go further and past it on a normal trajectory" - before this, the streak was one
## straight box from the muzzle to the final hit, laid down before the arc-and-drag trajectory
## (Ballistics._path_step) existed; it never got updated, so a shot that held well above the
## target to reach it, or well below going downhill, visibly snapped to a straight line that
## didn't look like the curve the round (and its actual impact point) really flew.

const WIDTH := 0.025
const DRAW_MPS := 260.0  # stylised, not the round's real velocity: fast but readable
const MIN_DRAW_S := 0.03
const HOLD_S := 0.03
const FADE_S := 0.12
## A streak never shows more segments than this (a long shot's ballistic samples are collapsed
## to this many, first and last point always kept): plenty to read the curve, not one box per
## 20 m sample out to Ballistics.RANGE.
const MAX_SEGMENTS := 8
## Kinds (Captain, 2026-10-16: "red tracers for us, green for the enemy, and not every round is a
## tracer but every round can be heard felt seen"): a tracer round burns red (our side) or green
## (the enemy's); a ball round still shows as a faint, thin streak (BALL), so every round is seen.
enum Kind { BALL, RED, GREEN }
const COLOURS := {Kind.BALL: Color(0.92, 0.9, 0.85, 0.16), Kind.RED: Color(1.0, 0.22, 0.12), Kind.GREEN: Color(0.35, 1.0, 0.3)}
const BALL_WIDTH := 0.012
## A suppressed shot's streak keeps this share of its alpha.
const SUPPRESSED_ALPHA := 0.35

var _points: PackedVector3Array = PackedVector3Array()
var _cum: Array[float] = []  # cumulative length up to each point
var _length := 0.0
var _segs: Array[MeshInstance3D] = []
var _boxes: Array[BoxMesh] = []
var _material: StandardMaterial3D


## Spawns a tracer along `points` (the muzzle, then the round's real path to its stop) under
## `parent` (the level). `dim` (suppressed shots): a fainter streak, since a subsonic round gives
## little away.
static func spawn(parent: Node, points: PackedVector3Array, dim := false, kind: int = Kind.RED) -> void:
	var t := Tracer.new()
	parent.add_child(t)
	if not points.is_empty():
		t.global_position = points[0]
	t._start(points, dim, kind)


func _start(points: PackedVector3Array, dim: bool, kind: int = Kind.RED) -> void:
	_points = _simplified(points)
	if _points.size() < 2:
		queue_free()
		return
	_cum = [0.0]
	for i in range(1, _points.size()):
		_cum.append(_cum[-1] + _points[i - 1].distance_to(_points[i]))
	_length = _cum[-1]
	if _length < 0.05:
		queue_free()
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var colour: Color = COLOURS.get(kind, COLOURS[Kind.RED])
	if dim:
		colour.a *= SUPPRESSED_ALPHA
	_material.albedo_color = colour
	var width := BALL_WIDTH if kind == Kind.BALL else WIDTH
	for i in range(1, _points.size()):
		var box := BoxMesh.new()
		box.size = Vector3(width, width, 0.001)
		box.material = _material
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.visible = false
		add_child(mesh)
		_segs.append(mesh)
		_boxes.append(box)
	var draw_s := maxf(_length / DRAW_MPS, MIN_DRAW_S)
	var tween := create_tween()
	tween.tween_method(_set_drawn, 0.0, _length, draw_s)
	tween.tween_interval(HOLD_S)
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_S)
	tween.tween_callback(queue_free)


## Collapses `points` to at most MAX_SEGMENTS + 1 samples (always keeps the first and last), so
## a long, many-sampled shot still draws as a handful of boxes along its real curve.
static func _simplified(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() <= MAX_SEGMENTS + 1:
		return points
	var out := PackedVector3Array()
	for i in range(MAX_SEGMENTS + 1):
		var f := float(i) / float(MAX_SEGMENTS)
		out.append(points[int(roundf(f * float(points.size() - 1)))])
	return out


## Grows the streak from the muzzle along the real curve: `drawn` metres of it, its far end at
## the round's current reach, its near end trailing TAIL_M behind (or the muzzle, whichever is
## closer).
const TAIL_M := 4.0
func _set_drawn(drawn: float) -> void:
	var tail := maxf(drawn - TAIL_M, 0.0)
	for i in range(_segs.size()):
		var seg_start: float = _cum[i]
		var seg_end: float = _cum[i + 1]
		var lo := clampf(tail, seg_start, seg_end)
		var hi := clampf(drawn, seg_start, seg_end)
		var mesh := _segs[i]
		if hi <= lo:
			mesh.visible = false
			continue
		mesh.visible = true
		var dir := (_points[i + 1] - _points[i]).normalized()
		var box: BoxMesh = _boxes[i]
		box.size.z = hi - lo
		mesh.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		mesh.global_position = _points[i] + dir * ((lo + hi) * 0.5 - seg_start)
