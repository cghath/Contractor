extends Node3D
## A soldier's weapon light and laser (GunAttachments.rig): a SpotLight3D and a thin beam under
## the camera, along the aim, shown while the gun in hand has a light or laser switched on in
## its item state (GunAttachments.side_on). It reads the replicated state each frame, so every
## peer draws the same. Placeholder look (no model on the gun yet: Captain's art side): the
## light is a plain spot cone, the laser a thin unshaded red box out to what it hits. An IR
## laser draws only while ir_seen (below) is on (the NVG work's hook).

## Where the light and the laser leave the gun, camera-local (right, down, ahead of the eye).
const FROM := Vector3(0.1, -0.12, -0.55)
const LASER_MAX_M := 150.0
const LASER_WIDTH_M := 0.004
const LIGHT_RANGE_M := 45.0
const LIGHT_ANGLE_DEG := 22.0
const LIGHT_ENERGY := 6.0

## The local view sees IR beams (set by night vision when it's on; nothing sets it yet).
static var ir_seen := false

var soldier: Soldier
var light: SpotLight3D
var laser: MeshInstance3D
var _laser_mat: StandardMaterial3D


func _ready() -> void:
	var n := get_parent()
	while n != null and not n is Soldier:
		n = n.get_parent()
	soldier = n as Soldier
	position = FROM
	light = SpotLight3D.new()
	light.name = "WeaponLight"
	light.spot_range = LIGHT_RANGE_M
	light.spot_angle = LIGHT_ANGLE_DEG
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	laser = MeshInstance3D.new()
	laser.name = "LaserBeam"
	var box := BoxMesh.new()
	box.size = Vector3(LASER_WIDTH_M, LASER_WIDTH_M, 1.0)
	laser.mesh = box
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.albedo_color = Color(1.0, 0.1, 0.1)
	laser.material_override = _laser_mat
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.visible = false
	add_child(laser)


func _process(_delta: float) -> void:
	if soldier == null or soldier.inventory == null:
		return
	var weapon := soldier.active_weapon()
	var state := soldier.inventory.state_of(soldier.active_slot)
	if not state.get(GunAttachments.ON_KEY, false):  # nothing switched on: the cheap, common case
		light.visible = false
		laser.visible = false
		return
	var up :=soldier.vitals.is_up() and weapon != null
	light.visible = up and GunAttachments.light_on(weapon, state)
	var beam := GunAttachments.laser_beam(weapon, state) if up else ""
	laser.visible = beam == "visible" or (beam == "ir" and ir_seen)
	if laser.visible:
		_laser_mat.albedo_color = Color(1.0, 0.1, 0.1) if beam == "visible" else Color(0.85, 1.0, 0.85)
		var length := _laser_length()
		laser.scale = Vector3(1.0, 1.0, length)
		laser.position = Vector3(0.0, 0.0, -length * 0.5)


## Metres from the gun to the first thing along the aim (LASER_MAX_M if nothing).
func _laser_length() -> float:
	if not is_inside_tree():
		return LASER_MAX_M
	var from := global_position
	var to := from - global_basis.z * LASER_MAX_M
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [soldier.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(from.distance_to(hit.position), 0.05) if not hit.is_empty() else LASER_MAX_M
