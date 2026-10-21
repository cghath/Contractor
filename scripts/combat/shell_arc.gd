class_name ShellArc
extends Node3D
## A mortar or artillery round seen in flight (Captain, 2026-10-21: "i wanna see the mortar streak
## down or up depending on weather conditions etc"), on every peer (CompoundLevel.show_shell). The
## host's round still lands by its time of flight (MortarFire, FireSupport); this flies the same
## time along the real arc, from the tube (or the guns off the map) up and over and down onto the
## burst: gravity, and the weather's wind (DayNight.wind) pushing the shell all the way. The crew
## lays the tube for the wind (a met message), so the round still lands where it was going to; the
## wind bends the arc on the way, a gentle lean in a breeze and a long curve in a storm. Purely
## visual: a dark shell with a pale streak behind it, thick enough to be seen far off, and hidden
## by fog as anything else is. It frees itself as it lands (the burst: show_explosion).

## The wind's push on a shell: its acceleration is the wind's velocity times this (1/s), the drag
## pulling it toward the air's own speed. Proposed: a storm's 14 m/s bends a 30 s flight about
## 30 m at the top of the arc.
const WIND_PUSH := 0.02
## The streak behind the shell (m), its width close to (m), and how wide it looks at any range
## (its width in metres per metre away: about a pixel and a half).
const TAIL_M := 14.0
const WIDTH := 0.1
const WIDTH_PER_M := 0.0016
const STREAK := Color(0.85, 0.83, 0.78, 0.5)
const SHELL := Color(0.16, 0.17, 0.15)

## Tests: the latest shell's flight on this peer {"from", "launch", "accel", "flight"}.
static var last := {}

var from := Vector3.ZERO
var launch := Vector3.ZERO
var accel := Vector3.ZERO
var flight := 0.0
var age := 0.0
var _streak: MeshInstance3D
var _box: BoxMesh
var _shell: MeshInstance3D


## The wind's acceleration on a shell (WIND_PUSH).
static func wind_accel(wind: Vector3) -> Vector3:
	return Vector3(wind.x, 0.0, wind.z) * WIND_PUSH


## The velocity a round must leave `start` with to be at `end` `t` seconds later under gravity
## and `push` (wind_accel): the crew's laying, met corrections and all.
static func launch_for(start: Vector3, end: Vector3, t: float, push: Vector3) -> Vector3:
	t = maxf(t, 0.05)
	return (end - start - 0.5 * (Ballistics.GRAVITY + push) * t * t) / t


## Where a round from `start` at `v` under `push` is `t` seconds out.
static func point_at(start: Vector3, v: Vector3, push: Vector3, t: float) -> Vector3:
	return start + v * t + 0.5 * (Ballistics.GRAVITY + push) * t * t


## Spawns a shell under `parent` (the level) flying `t` seconds from `start` at `v` under `push`.
static func spawn(parent: Node, start: Vector3, v: Vector3, push: Vector3, t: float) -> ShellArc:
	last = {"from": start, "launch": v, "accel": push, "flight": t}
	var s := ShellArc.new()
	s.from = start
	s.launch = v
	s.accel = push
	s.flight = t
	parent.add_child(s)
	return s


## Where this shell is `t` seconds into its flight.
func at(t: float) -> Vector3:
	return point_at(from, launch, accel, clampf(t, 0.0, flight))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY  # the streak's placed in world space (_place)
	_box = BoxMesh.new()
	_box.size = Vector3(WIDTH, WIDTH, 0.001)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = STREAK
	_box.material = m
	_streak = MeshInstance3D.new()
	_streak.mesh = _box
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_streak)
	var body := CapsuleMesh.new()
	body.radius = 0.045
	body.height = 0.5
	var bm := StandardMaterial3D.new()
	bm.albedo_color = SHELL
	body.material = bm
	_shell = MeshInstance3D.new()
	_shell.mesh = body
	add_child(_shell)
	_place()


func _process(delta: float) -> void:
	age += delta
	if age >= flight:
		queue_free()
		return
	_place()


## The shell where it is now, nose along its flight, the streak TAIL_M behind it.
func _place() -> void:
	var head := at(age)
	var v := launch + (Ballistics.GRAVITY + accel) * age
	var speed := maxf(v.length(), 1.0)
	var tail := at(age - TAIL_M / speed)
	var span := head - tail
	var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
	_shell.transform = Transform3D(Basis.looking_at(v, up) * Basis(Vector3.RIGHT, PI * 0.5), head)  # (a capsule's long axis is Y)
	if span.length_squared() < 0.0001:
		_streak.visible = false
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var width := maxf(WIDTH, camera.global_position.distance_to(head) * WIDTH_PER_M) if camera else WIDTH
	_box.size = Vector3(width, width, span.length())
	_streak.visible = true
	_streak.transform = Transform3D(Basis.looking_at(span, up), (head + tail) * 0.5)
