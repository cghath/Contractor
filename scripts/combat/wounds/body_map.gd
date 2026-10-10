class_name BodyMap
extends RefCounted
## Where things are inside a soldier: hitbox volumes, the simulated arteries and big veins,
## the organs (brain, heart, lungs) and the long bones, all in the body's rest pose.
##
## Rest pose is CharacterModel's: feet at the origin, facing -Z, the body's right at +X,
## standing with the arms hanging. Each hitbox Area3D sits at the body origin with an
## identity transform at rest and carries its shapes at these offsets, so a point in a
## hitbox's own space is a point in the rest pose. Code that poses hitboxes (lying down,
## crouching, prone) moves the Area3D, never its shapes, and wound channels keep working.
##
## trace() follows a round's wound channel through the body and says what it passed:
## vessels by how close (direct, inside the temporary cavity, or not at all), organs and
## bones. WoundModel turns that into wounds.

## How far the temporary wound cavity reaches past the channel, by round class (proposed).
const CAVITY_REACH_M := {
	&"pistol": 0.02, &"intermediate": 0.05, &"full_power": 0.07, &"fragment": 0.01,
}
## A vessel this close to the channel's centre line (beyond its own radius) is hit directly.
const DIRECT_HIT_M := 0.004
## Inside the cavity a vessel bleeds this share of its full rate at most, falling off as
## (1 - t)^CAVITY_FALLOFF_EXP with t = how far into the cavity reach it sits (0 to 1).
const CAVITY_MAX_SHARE := 0.6
const CAVITY_FALLOFF_EXP := 2.0
## Shares below this count as a miss (a plain muscle wound).
const MIN_VESSEL_SHARE := 0.05
## Organs and bones are hit within their radius plus this share of the cavity reach.
const ORGAN_CAVITY_SHARE := 0.5
const BONE_CAVITY_SHARE := 0.5
## Channels shorter than this inside the body are grazes.
const GRAZE_DEPTH_M := 0.025
## Longest channel followed for a bullet, and the depth range of a fragment.
const CHANNEL_MAX_M := 0.45
const FRAGMENT_DEPTH_M := Vector2(0.03, 0.10)
## A channel through the chest deeper than this opens the chest cavity.
const CHEST_WALL_M := 0.03

## Hitbox volumes: part -> list of [centre, size] boxes (rest pose). The scenes' hitbox
## shapes match these (wounds_test checks).
const PART_BOXES := {
	&"head": [[Vector3(0, 1.70, 0), Vector3(0.22, 0.12, 0.24)], [Vector3(0, 1.58, 0.05), Vector3(0.22, 0.12, 0.14)]],
	&"face": [[Vector3(0, 1.58, -0.07), Vector3(0.22, 0.12, 0.10)]],
	&"neck": [[Vector3(0, 1.48, 0), Vector3(0.14, 0.08, 0.14)]],
	&"chest": [[Vector3(0, 1.31, 0), Vector3(0.36, 0.26, 0.22)]],
	&"abdomen": [[Vector3(0, 1.09, 0), Vector3(0.36, 0.18, 0.22)]],
	&"pelvis": [[Vector3(0, 0.93, 0), Vector3(0.36, 0.14, 0.22)]],
	&"upper_arm_l": [[Vector3(-0.25, 1.26, 0), Vector3(0.12, 0.32, 0.12)]],
	&"upper_arm_r": [[Vector3(0.25, 1.26, 0), Vector3(0.12, 0.32, 0.12)]],
	&"forearm_l": [[Vector3(-0.25, 0.94, 0), Vector3(0.11, 0.32, 0.11)]],
	&"forearm_r": [[Vector3(0.25, 0.94, 0), Vector3(0.11, 0.32, 0.11)]],
	&"thigh_l": [[Vector3(-0.075, 0.665, -0.01), Vector3(0.152, 0.39, 0.18)]],
	&"thigh_r": [[Vector3(0.075, 0.665, -0.01), Vector3(0.152, 0.39, 0.18)]],
	&"shin_l": [[Vector3(-0.075, 0.235, -0.01), Vector3(0.152, 0.47, 0.18)]],
	&"shin_r": [[Vector3(0.075, 0.235, -0.01), Vector3(0.152, 0.47, 0.18)]],
}
## A channel runs through a whole segment (a face shot can reach the brain stem), not
## just the hitbox it entered. Segment -> its box [centre, size].
const SEGMENTS := {
	&"head": [Vector3(0, 1.60, 0), Vector3(0.22, 0.32, 0.24)],
	&"torso": [Vector3(0, 1.15, 0), Vector3(0.36, 0.58, 0.22)],
}
const SEGMENT_OF := {
	&"head": &"head", &"face": &"head", &"neck": &"head",
	&"chest": &"torso", &"abdomen": &"torso", &"pelvis": &"torso", &"torso": &"torso",
}

## Wound kinds by where the vessel is and what fixes it (design doc).
const ARTERIAL := "arterial"      # limb artery: tourniquet
const JUNCTIONAL := "junctional"  # neck, armpit, groin: packing and pressure
const INTERNAL := "internal"      # inside the torso: surgery kit, IV to buy time
const VENOUS := "venous"          # limb vein: pressure bandage

## Simulated vessels: [name, kind, full rate in L/min at full blood, radius m, from, to].
## A vessel may have several segments under one name. Full rates for arterial (1.2) and
## junctional (0.8) are the design doc's; the others are proposed.
const VESSELS: Array = [
	[&"common_carotid_l", JUNCTIONAL, 0.8, 0.004, Vector3(-0.025, 1.42, -0.02), Vector3(-0.03, 1.58, -0.01)],
	[&"common_carotid_r", JUNCTIONAL, 0.8, 0.004, Vector3(0.025, 1.42, -0.02), Vector3(0.03, 1.58, -0.01)],
	[&"jugular_l", JUNCTIONAL, 0.5, 0.006, Vector3(-0.045, 1.43, -0.01), Vector3(-0.05, 1.58, 0.0)],
	[&"jugular_r", JUNCTIONAL, 0.5, 0.006, Vector3(0.045, 1.43, -0.01), Vector3(0.05, 1.58, 0.0)],
	[&"subclavian_l", JUNCTIONAL, 0.8, 0.005, Vector3(-0.02, 1.40, 0.0), Vector3(-0.18, 1.41, -0.01)],
	[&"subclavian_r", JUNCTIONAL, 0.8, 0.005, Vector3(0.03, 1.42, -0.01), Vector3(0.18, 1.41, -0.01)],
	[&"subclavian_vein_l", JUNCTIONAL, 0.5, 0.006, Vector3(-0.03, 1.39, -0.03), Vector3(-0.18, 1.40, -0.03)],
	[&"subclavian_vein_r", JUNCTIONAL, 0.5, 0.006, Vector3(0.03, 1.39, -0.03), Vector3(0.18, 1.40, -0.03)],
	[&"brachiocephalic_trunk", INTERNAL, 1.5, 0.006, Vector3(0.0, 1.36, 0.0), Vector3(0.03, 1.42, -0.01)],
	[&"aorta", INTERNAL, 2.5, 0.012, Vector3(-0.01, 1.28, -0.01), Vector3(-0.02, 1.37, 0.03)],
	[&"aorta", INTERNAL, 2.5, 0.012, Vector3(-0.02, 1.37, 0.03), Vector3(-0.015, 0.99, 0.05)],
	[&"vena_cava", INTERNAL, 1.5, 0.011, Vector3(0.025, 1.42, 0.0), Vector3(0.025, 1.28, 0.0)],
	[&"vena_cava", INTERNAL, 1.5, 0.011, Vector3(0.02, 1.25, 0.04), Vector3(0.025, 0.99, 0.05)],
	[&"pulmonary_l", INTERNAL, 1.5, 0.008, Vector3(-0.01, 1.31, -0.01), Vector3(-0.07, 1.33, 0.01)],
	[&"pulmonary_r", INTERNAL, 1.5, 0.008, Vector3(-0.01, 1.31, -0.01), Vector3(0.06, 1.33, 0.01)],
	[&"renal_l", INTERNAL, 0.8, 0.003, Vector3(-0.015, 1.10, 0.05), Vector3(-0.08, 1.10, 0.07)],
	[&"renal_r", INTERNAL, 0.8, 0.003, Vector3(-0.015, 1.10, 0.05), Vector3(0.08, 1.10, 0.07)],
	[&"common_iliac_l", JUNCTIONAL, 0.8, 0.006, Vector3(-0.015, 0.99, 0.05), Vector3(-0.06, 0.88, -0.02)],
	[&"common_iliac_r", JUNCTIONAL, 0.8, 0.006, Vector3(-0.015, 0.99, 0.05), Vector3(0.06, 0.88, -0.02)],
	[&"femoral_l", ARTERIAL, 1.2, 0.005, Vector3(-0.055, 0.88, -0.04), Vector3(-0.06, 0.56, 0.0)],
	[&"femoral_r", ARTERIAL, 1.2, 0.005, Vector3(0.055, 0.88, -0.04), Vector3(0.06, 0.56, 0.0)],
	[&"femoral_vein_l", VENOUS, 0.4, 0.006, Vector3(-0.04, 0.88, -0.03), Vector3(-0.05, 0.56, 0.01)],
	[&"femoral_vein_r", VENOUS, 0.4, 0.006, Vector3(0.04, 0.88, -0.03), Vector3(0.05, 0.56, 0.01)],
	[&"popliteal_l", ARTERIAL, 1.0, 0.004, Vector3(-0.07, 0.56, 0.02), Vector3(-0.075, 0.38, 0.04)],
	[&"popliteal_r", ARTERIAL, 1.0, 0.004, Vector3(0.07, 0.56, 0.02), Vector3(0.075, 0.38, 0.04)],
	[&"brachial_l", ARTERIAL, 1.2, 0.004, Vector3(-0.215, 1.40, 0.0), Vector3(-0.225, 1.11, -0.01)],
	[&"brachial_r", ARTERIAL, 1.2, 0.004, Vector3(0.215, 1.40, 0.0), Vector3(0.225, 1.11, -0.01)],
	[&"radial_l", ARTERIAL, 0.5, 0.0025, Vector3(-0.27, 1.08, -0.02), Vector3(-0.27, 0.84, -0.02)],
	[&"radial_r", ARTERIAL, 0.5, 0.0025, Vector3(0.27, 1.08, -0.02), Vector3(0.27, 0.84, -0.02)],
	[&"ulnar_l", ARTERIAL, 0.5, 0.0025, Vector3(-0.23, 1.08, -0.01), Vector3(-0.23, 0.84, -0.02)],
	[&"ulnar_r", ARTERIAL, 0.5, 0.0025, Vector3(0.23, 1.08, -0.01), Vector3(0.23, 0.84, -0.02)],
]

## Organs as capsules: name -> [from, to, radius].
const ORGANS := {
	&"brain": [Vector3(0, 1.63, 0.01), Vector3(0, 1.70, 0.01), 0.065],
	&"heart": [Vector3(-0.02, 1.25, -0.03), Vector3(-0.01, 1.33, -0.02), 0.045],
	&"lung_l": [Vector3(-0.09, 1.22, 0.0), Vector3(-0.09, 1.38, 0.0), 0.065],
	&"lung_r": [Vector3(0.09, 1.22, 0.0), Vector3(0.09, 1.38, 0.0), 0.065],
}

## Long bones: name -> [from, to, radius, part]. Legs: femur, tibia; arms: humerus, forearm.
const BONES := {
	&"femur_l": [Vector3(-0.075, 0.86, -0.01), Vector3(-0.075, 0.49, -0.01), 0.015, &"thigh_l"],
	&"femur_r": [Vector3(0.075, 0.86, -0.01), Vector3(0.075, 0.49, -0.01), 0.015, &"thigh_r"],
	&"tibia_l": [Vector3(-0.075, 0.46, -0.02), Vector3(-0.075, 0.06, -0.02), 0.013, &"shin_l"],
	&"tibia_r": [Vector3(0.075, 0.46, -0.02), Vector3(0.075, 0.06, -0.02), 0.013, &"shin_r"],
	&"humerus_l": [Vector3(-0.25, 1.40, 0.0), Vector3(-0.25, 1.11, 0.0), 0.012, &"upper_arm_l"],
	&"humerus_r": [Vector3(0.25, 1.40, 0.0), Vector3(0.25, 1.11, 0.0), 0.012, &"upper_arm_r"],
	&"forearm_bones_l": [Vector3(-0.25, 1.08, 0.0), Vector3(-0.25, 0.86, 0.0), 0.012, &"forearm_l"],
	&"forearm_bones_r": [Vector3(0.25, 1.08, 0.0), Vector3(0.25, 0.86, 0.0), 0.012, &"forearm_r"],
}
const LEG_BONES: Array[StringName] = [&"femur_l", &"femur_r", &"tibia_l", &"tibia_r"]
const ARM_BONES: Array[StringName] = [&"humerus_l", &"humerus_r", &"forearm_bones_l", &"forearm_bones_r"]


## The segment (head, torso) a part belongs to, or the part itself for a limb.
static func segment_of(part: StringName) -> StringName:
	return SEGMENT_OF.get(part, part)


## The box a channel entering `part` runs through: [centre, size].
static func segment_box(part: StringName) -> Array:
	var segment := segment_of(part)
	if SEGMENTS.has(segment):
		return SEGMENTS[segment]
	return PART_BOXES.get(part, SEGMENTS[&"torso"])[0]


## The part whose hitbox contains a rest-pose point (nearest box if none does).
static func part_at(point: Vector3) -> StringName:
	var best: StringName = &"chest"
	var best_d := INF
	for part: StringName in PART_BOXES:
		for box: Array in PART_BOXES[part]:
			var aabb := AABB(box[0] - box[1] * 0.5, box[1])
			var d := (aabb.get_center() - point).length() if not aabb.has_point(point) else 0.0
			if d < best_d:
				best_d = d
				best = part
	return best


## A random channel into `part` for hits with no position (old callers, tests): enters a
## random point on the front of its first box and runs straight back.
static func random_channel(part: StringName, rng: RandomNumberGenerator) -> Array:
	var box: Array = PART_BOXES.get(part, PART_BOXES[&"chest"])[0]
	var c: Vector3 = box[0]
	var s: Vector3 = box[1]
	var entry := Vector3(c.x + rng.randf_range(-0.4, 0.4) * s.x, c.y + rng.randf_range(-0.4, 0.4) * s.y, c.z - s.z * 0.5)
	return [entry, Vector3.BACK]


## Follows a wound channel that enters `part` at `entry` heading `direction` (rest pose)
## and reports what it passes. Returns {"depth": m inside the segment, "graze": bool,
## "from", "to" (the channel), "vessels": [{name, kind, rate, share, direct}],
## "organs": [names], "bones": [names]}. `max_depth` caps the channel (fragments).
static func trace(part: StringName, entry: Vector3, direction: Vector3, round_class: StringName, max_depth := CHANNEL_MAX_M) -> Dictionary:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.BACK
	var box: Array = segment_box(part)
	var depth := minf(_exit_distance(box[0], box[1], entry, dir), max_depth)
	var to := entry + dir * depth
	var reach := float(CAVITY_REACH_M.get(round_class, 0.05))
	var result := {"depth": depth, "graze": depth < GRAZE_DEPTH_M, "from": entry, "to": to,
		"vessels": [], "organs": [], "bones": []}
	if result.graze:
		return result  # skims the surface: nothing deep is reached
	var segment := segment_of(part)
	var by_name := {}
	for v: Array in VESSELS:
		if not _in_segment(v[4], v[5], segment, part):
			continue
		var d := _segment_distance(entry, to, v[4], v[5]) - float(v[3])
		var share := 0.0
		var direct := d <= DIRECT_HIT_M
		if direct:
			share = 1.0
		else:
			var t := (d - DIRECT_HIT_M) / reach
			if t < 1.0:
				share = CAVITY_MAX_SHARE * pow(1.0 - t, CAVITY_FALLOFF_EXP)
		if share < MIN_VESSEL_SHARE:
			continue
		if by_name.has(v[0]) and by_name[v[0]].share >= share:
			continue
		by_name[v[0]] = {"name": v[0], "kind": v[1], "rate": float(v[2]), "share": share, "direct": direct}
	result.vessels = by_name.values()
	for organ: StringName in ORGANS:
		var o: Array = ORGANS[organ]
		if _segment_distance(entry, to, o[0], o[1]) <= float(o[2]) + reach * ORGAN_CAVITY_SHARE:
			result.organs.append(organ)
	for bone: StringName in BONES:
		var b: Array = BONES[bone]
		if b[3] != part:
			continue
		if _segment_distance(entry, to, b[0], b[1]) <= float(b[2]) + reach * BONE_CAVITY_SHARE:
			result.bones.append(bone)
	return result


## Whether a vessel can be reached from a channel in `segment`: torso and head vessels from
## anywhere in their segment, limb vessels only from their own limb part.
static func _in_segment(a: Vector3, b: Vector3, segment: StringName, part: StringName) -> bool:
	var mid := (a + b) * 0.5
	if SEGMENTS.has(segment):
		var box: Array = SEGMENTS[segment]
		return AABB(box[0] - box[1] * 0.5, box[1]).grow(0.01).has_point(mid)
	for box: Array in PART_BOXES.get(part, []):
		if AABB(box[0] - box[1] * 0.5, box[1]).grow(0.01).has_point(mid):
			return true
	return false


static func _segment_distance(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	var points := Geometry3D.get_closest_points_between_segments(p1, p2, q1, q2)
	return points[0].distance_to(points[1])


## How far a ray from `origin` along `dir` travels before leaving the box (0 if it starts
## outside heading away). Slab method.
static func _exit_distance(centre: Vector3, size: Vector3, origin: Vector3, dir: Vector3) -> float:
	var lo := centre - size * 0.5
	var hi := centre + size * 0.5
	var t_exit := INF
	for axis in 3:
		if absf(dir[axis]) < 0.00001:
			continue
		var t := ((hi[axis] if dir[axis] > 0.0 else lo[axis]) - origin[axis]) / dir[axis]
		t_exit = minf(t_exit, t)
	return clampf(t_exit, 0.0, CHANNEL_MAX_M) if t_exit != INF else 0.0
