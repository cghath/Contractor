class_name Tracer
extends Node3D
## A visible tracer streak for a shot, spawned on every peer (CompoundLevel.show_tracer).
## Captain, 2026-10-16: "we dont have tracers or bullets that can be seen in game yet". Purely
## visual (hitscan is instant; Ballistics/Sfx already resolve the shot) — a thin unshaded box
## grows from the muzzle to the impact point over DRAW_S (scaled by distance so a long shot
## doesn't snap into place), holds, then fades over FADE_S and frees itself.

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

var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD
var _length := 0.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _box: BoxMesh


## Spawns a tracer from `origin` to `end` under `parent` (the level). `dim` (suppressed shots):
## a fainter streak, since a subsonic round gives little away.
static func spawn(parent: Node, origin: Vector3, end: Vector3, dim := false, kind: int = Kind.RED) -> void:
	var t := Tracer.new()
	parent.add_child(t)
	t.global_position = origin
	t._start(origin, end, dim, kind)


func _start(origin: Vector3, end: Vector3, dim: bool, kind: int = Kind.RED) -> void:
	_origin = origin
	var to_end := end - origin
	_length = to_end.length()
	if _length < 0.05:
		queue_free()
		return
	_dir = to_end / _length
	_box = BoxMesh.new()
	var width := BALL_WIDTH if kind == Kind.BALL else WIDTH
	_box.size = Vector3(width, width, 0.001)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var colour: Color = COLOURS.get(kind, COLOURS[Kind.RED])
	if dim:
		colour.a *= SUPPRESSED_ALPHA
	_material.albedo_color = colour
	_box.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _box
	add_child(_mesh)
	global_basis = Basis.looking_at(_dir, Vector3.UP if absf(_dir.y) < 0.99 else Vector3.RIGHT)
	var draw_s := maxf(_length / DRAW_MPS, MIN_DRAW_S)
	var tween := create_tween()
	tween.tween_method(_set_drawn, 0.0, _length, draw_s)
	tween.tween_interval(HOLD_S)
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_S)
	tween.tween_callback(queue_free)


## Grows the streak from the muzzle: `drawn` metres long, its far end at the round's current
## reach, its near end trailing TAIL_M behind (or the muzzle, whichever is closer).
const TAIL_M := 4.0
func _set_drawn(drawn: float) -> void:
	var tail := maxf(drawn - TAIL_M, 0.0)
	var mid := (tail + drawn) * 0.5
	_box.size.z = drawn - tail
	_mesh.position = Vector3(0.0, 0.0, -mid)  # looking_at points -Z at _dir
