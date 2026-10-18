class_name DoorGun
extends Node3D
## A helicopter's door gun on its pintle in an open gun port (Captain, 2026-10-17: "remove the
## window by the guns and make it an open port that the gunner grips his weapon from"): an
## M240H with its two spade grips, swung to where its gunner looks (a player) or aims (an AI:
## AavGunner turns him), within its arc out of its own side; stowed pointing forward with nobody
## on it. The gunner's hands take the grips (CharacterModel._seat_hands, pose "grip_l"/"grip_r").
## Drawn on every peer from the gunner's synced turn and look (Vehicle._place_occupants); rounds
## still leave from the seat's "gun_at" (Vehicle.gun_origin), the pintle this turns about.

## How far round from square out it swings (radians, each way), and how far down and up.
const ARC_YAW := deg_to_rad(80.0)
const PITCH_MIN := deg_to_rad(-45.0)
const PITCH_MAX := deg_to_rad(20.0)
## The spade grips, from the pintle (gun frame: -z is the muzzle's way): behind the receiver.
const GRIP := Vector3(0.07, 0.03, 0.34)

## -1: out of the left side, 1: the right.
var side := 1.0


static func build(p_side: float, colour: Color) -> DoorGun:
	var g := DoorGun.new()
	g.name = "DoorGun_%s" % ("left" if p_side < 0.0 else "right")
	g.side = p_side
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color("232523")
	gun.roughness = 0.5
	gun.metallic = 0.5
	var drab := StandardMaterial3D.new()
	drab.albedo_color = colour
	drab.roughness = 0.9
	g._box(Vector3(0.1, 0.13, 0.62), Vector3(0, 0.02, 0.0), gun)           # receiver
	g._box(Vector3(0.12, 0.05, 0.4), Vector3(0, 0.1, 0.02), gun)           # feed cover
	g._box(Vector3(0.05, 0.05, 0.78), Vector3(0, 0.03, -0.69), gun)        # barrel
	g._box(Vector3(0.07, 0.07, 0.1), Vector3(0, 0.03, -1.1), gun)          # flash hider
	g._box(Vector3(0.09, 0.03, 0.06), Vector3(0, 0.13, -0.45), gun)        # front sight post
	g._box(Vector3(0.18, 0.03, 0.04), Vector3(0, 0.02, 0.33), gun)         # spade grip yoke
	for x: float in [-GRIP.x, GRIP.x]:
		g._box(Vector3(0.035, 0.12, 0.035), Vector3(x, GRIP.y, GRIP.z), gun)  # the grips
	g._box(Vector3(0.12, 0.16, 0.24), Vector3(0.12 * -p_side, -0.06, 0.02), drab)  # ammo bag, inboard
	g._box(Vector3(0.05, 0.12, 0.05), Vector3(0, -0.1, 0.0), gun)          # pintle
	return g


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = at
	add_child(m)


## Points it `yaw` round from square out of its side (radians, + towards the nose... clamped to
## the arc) and `pitch` up (clamped).
func aim(yaw: float, pitch: float) -> void:
	var out := PI / 2.0 if side < 0.0 else -PI / 2.0  # the barrel (-z) turned to point out
	rotation = Vector3(clampf(pitch, PITCH_MIN, PITCH_MAX), out + clampf(yaw, -ARC_YAW, ARC_YAW), 0.0)


## Nobody on it: swung forward along the hull, barrel level.
func stow() -> void:
	rotation = Vector3.ZERO


## Where the gunner's `right` (or left) hand takes hold (world).
func grip(right: bool) -> Vector3:
	return to_global(Vector3(GRIP.x if right else -GRIP.x, GRIP.y + 0.04, GRIP.z))
