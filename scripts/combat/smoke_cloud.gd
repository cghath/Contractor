class_name SmokeCloud
extends Node3D
## A smoke screen, spawned on every peer. It's opaque to the eye, and the host's copy is
## what AI line of sight checks against (blocks()).

const MAX_RADIUS := 5.0
const GROW_S := 3.0
const DURATION_S := 30.0
const FADE_S := 5.0
const PUFFS := 18

static var active: Array[SmokeCloud] = []

var radius := 0.5
var _age := 0.0
var _material := StandardMaterial3D.new()
var _puffs: Array[MeshInstance3D] = []
var _offsets: Array[Vector3] = []


## True when the sight line between the two points passes through any cloud.
static func blocks(from: Vector3, to: Vector3) -> bool:
	for cloud in active:
		if is_instance_valid(cloud) and cloud.radius > 1.0:
			var centre := cloud.global_position + Vector3.UP * cloud.radius * 0.45
			var closest := Geometry3D.get_closest_point_to_segment(centre, from, to)
			if closest.distance_to(centre) < cloud.radius * 0.8:
				return true
	return false


func _ready() -> void:
	active.append(self)
	_material.albedo_color = Color(0.8, 0.82, 0.82, 0.92)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _material
	for i in PUFFS:
		var puff := MeshInstance3D.new()
		puff.mesh = mesh
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		_puffs.append(puff)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1)).normalized()
		_offsets.append(dir * randf_range(0.2, 0.7))


func _exit_tree() -> void:
	active.erase(self)


func _process(delta: float) -> void:
	_age += delta
	radius = MAX_RADIUS * clampf(_age / GROW_S, 0.1, 1.0)
	_material.albedo_color.a = 0.92 * clampf((DURATION_S - _age) / FADE_S, 0.0, 1.0)
	for i in _puffs.size():
		_puffs[i].position = _offsets[i] * radius + Vector3.UP * radius * 0.35
		_puffs[i].scale = Vector3.ONE * radius * 1.1
	if _age > DURATION_S:
		queue_free()
