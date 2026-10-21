class_name SeveredPiece
extends RigidBody3D
## A part cut off a body (BodyDeform), loose in the world: a limb, a head. Every peer flies it
## from the same launch (its gore "s" entry: BlastGore), but physics runs apart on each machine,
## so only the host's landing counts: once the host's has lain still SETTLE_S (or SETTLE_MAX_S
## after it was cut) it freezes there and says where (settled), BodyDeform records the pose in the
## entry ("q"), and every other peer moves its own there over SNAP_S and freezes it. A late joiner,
## or a body back from a zone save, puts it straight there (settle_to with `instant`).
## Its collider is fitted to its voxels (BodyDeform._fit_collider). It meets the world and the
## ragdolls (it can land on a body), not the living.

signal settled(pose: Array)

const GROUP := &"severed_pieces"
const SETTLE_SPEED := 0.06
const SETTLE_S := 0.5
const SETTLE_MAX_S := 6.0
## A peer that never hears where the host's landed freezes its own after this.
const CLIENT_MAX_S := 20.0
const SNAP_S := 0.25
const MASS_KG := 4.0

var part: StringName
var host := false
var is_settled := false
var _still := 0.0
var _age := 0.0
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _snap := -1.0  # seconds into the move to the host's pose, -1 when not moving


func _init() -> void:
	collision_layer = Ragdoll.LAYER
	collision_mask = 1 | Ragdoll.LAYER
	mass = MASS_KG
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.rough = true
	mat.bounce = 0.05
	physics_material_override = mat
	add_to_group(GROUP)


## Sets it flying (world velocity and spin).
func launch(velocity: Vector3, spin: Vector3) -> void:
	linear_velocity = velocity
	angular_velocity = spin


## Where it lies, for the record: [x, y, z, quaternion x, y, z, w].
func pose() -> Array:
	var q := global_basis.orthonormalized().get_rotation_quaternion()
	var p := global_position
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001), snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]


static func pose_transform(q: Array) -> Transform3D:
	var rot := Quaternion(float(q[3]), float(q[4]), float(q[5]), float(q[6]))
	rot = rot.normalized() if rot.length_squared() > 0.0001 else Quaternion.IDENTITY
	return Transform3D(Basis(rot), Vector3(float(q[0]), float(q[1]), float(q[2])))


## Not the host's: put it where the host's came to rest (`q`, pose()), moved there over SNAP_S
## (at once with `instant`, or from far off), and held.
## The host's own takes it only `instant` (a body back from a save: it lay there already).
func settle_to(q: Array, instant := false) -> void:
	if q.size() != 7 or (host and not instant):
		return
	var target := pose_transform(q)
	is_settled = true
	freeze = true
	if instant or not is_inside_tree() or global_position.distance_to(target.origin) > 3.0:
		global_transform = target
		_snap = -1.0
		return
	_from = global_transform
	_to = target
	_snap = 0.0


func _physics_process(delta: float) -> void:
	if _snap >= 0.0:
		_snap += delta
		var t := clampf(_snap / SNAP_S, 0.0, 1.0)
		global_transform = Transform3D(Basis(_from.basis.get_rotation_quaternion().slerp(_to.basis.get_rotation_quaternion(), t)), _from.origin.lerp(_to.origin, t))
		if t >= 1.0:
			_snap = -1.0
		return
	if is_settled:
		return
	_age += delta
	if not host:
		if _age >= CLIENT_MAX_S:
			is_settled = true
			freeze = true
		return
	var still := linear_velocity.length() < SETTLE_SPEED and angular_velocity.length() < SETTLE_SPEED * 3.0
	_still = _still + delta if still else 0.0
	if _still >= SETTLE_S or _age >= SETTLE_MAX_S or sleeping:
		is_settled = true
		freeze = true
		settled.emit(pose())
