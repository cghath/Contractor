class_name HandPose
extends RefCounted
## Hands with real fingers (Captain, 2026-10-20: more realistic character models): a palm, four
## fingers and a thumb in 0.5 cm voxels, built into the forearm (VoxelArt "forearm:<pose>:<flags>")
## as a small set of posed meshes the model swaps by state. A soldier's hands are two meshes he
## already had, so fingers cost no extra nodes or draw calls; each pose is rasterised once per
## colour scheme (warmed on a worker thread, VoxelArt.uniform) and shared by every body.
##
## The hand is written in its own frame, in centimetres: the origin at the wrist joint, the
## fingers down its -y, the palm facing -x and the thumb on the -z side (a right hand hanging
## at rest, palm to the thigh). The left hand is the mirror (x flipped). Each finger is three
## bevelled boxes (VoxelArt obox) on a chain bent at its knuckle, middle and end joints; the
## thumb is three more from its base by the wrist. The palm is cupped: a thick heel of the thumb
## and a pad under the little finger with a hollow between them.
##
## Poses: what the hand does, chosen by CharacterModel (hand_pose_for) from what it holds:
## the firing grip (GRIP: the index straight along the frame; TRIGGER: on the trigger; PRESS:
## the trigger squeezed, a shot), the SUPPORT grip on a handguard or foregrip, MAG (a magazine
## taken from the pouch and seated), HOLD (round an object: a bandage, a handle, a strap), PINCH
## (a syringe, a needle, a charging handle), and OPEN, RELAXED, POINT and FIST.

const RELAXED := &"relaxed"
const OPEN := &"open"
const FIST := &"fist"
const POINT := &"point"
const GRIP := &"grip"
const TRIGGER := &"trigger"
const PRESS := &"press"
const SUPPORT := &"support"
const MAG := &"mag"
const HOLD := &"hold"
const PINCH := &"pinch"
const POSES: Array[StringName] = [RELAXED, OPEN, FIST, POINT, GRIP, TRIGGER, PRESS, SUPPORT, MAG, HOLD, PINCH]

## Where the wrist joint is in the forearm model (VoxelArt _forearm: cm, the frame's corner at 0):
## centred across the arm, 19 cm below the elbow (the pivot, y 42), so the palm's centre comes
## out CharacterModel.FOREARM (0.25 m) from the elbow.
const WRIST := Vector3(9, 23, 9)
## A woman's hand is drawn this much smaller about the wrist (her whole body is also drawn at
## CharacterModel.FEMALE_SCALE), with slimmer fingers.
const FEMALE_SIZE := 0.94
const FEMALE_SLIM := 0.9
## A glove adds this to every finger's and the palm's half-thickness (cm).
const GLOVE_PAD := 0.15

## Each finger, index to little: [knuckle (MCP) point in the hand frame, half-thickness and
## half-width (bare, cm), lengths of its three bones (cm)]. After adult male averages: a 19 cm
## hand, the palm 10.5 cm. The knuckles 2 cm apart and the fingers 1.6 cm wide leave a 0.5 cm
## voxel's groove between them.
const FINGERS := [
	[Vector3(0.2, -10.5, -3.0), 0.9, 0.78, [4.3, 2.5, 2.0]],
	[Vector3(0.2, -10.7, -1.0), 0.95, 0.8, [4.8, 2.9, 2.2]],
	[Vector3(0.2, -10.4, 1.0), 0.88, 0.76, [4.5, 2.8, 2.1]],
	[Vector3(0.2, -9.8, 2.95), 0.78, 0.68, [3.6, 2.1, 1.9]],
]
## The thumb: its base (the CMC joint, by the wrist on the palm side), half-thickness of each bone
## and their lengths.
const THUMB_BASE := Vector3(-0.4, -1.4, -2.2)
const THUMB_R := [1.15, 1.0, 0.92]
const THUMB_LEN := [4.4, 3.1, 2.6]

## The poses. "wrist": [flex toward the palm, bend toward the little finger] (degrees);
## "fingers": index to little, [knuckle, middle, end joint flex, spread toward the little finger]
## (degrees); "thumb": its three bones' directions in the hand frame; "grasp": where a held
## object's centre is (the hand frame, cm) and "axis" the way it runs (CharacterModel.hand_anchor).
const TABLE := {
	RELAXED: {"wrist": [8.0, 0.0], "fingers": [[14, 22, 10, -4], [17, 26, 12, 0], [21, 30, 14, 3], [25, 34, 16, 7]],
		"thumb": [Vector3(-0.45, -1, -0.55), Vector3(-0.4, -1, -0.25), Vector3(-0.3, -1, -0.05)],
		"grasp": Vector3(-2.0, -6.0, 0.0), "axis": Vector3(0, 0, 1)},
	OPEN: {"wrist": [-6.0, 0.0], "fingers": [[0, 3, 0, -8], [0, 2, 0, -2], [0, 3, 0, 4], [2, 4, 0, 10]],
		"thumb": [Vector3(-0.35, -1, -0.7), Vector3(-0.25, -1, -0.75), Vector3(-0.15, -1, -0.7)],
		"grasp": Vector3(-1.5, -6.0, 0.0), "axis": Vector3(0, 0, 1)},
	FIST: {"wrist": [0.0, 0.0], "fingers": [[88, 100, 62, -2], [90, 100, 62, 0], [90, 100, 62, 2], [92, 100, 62, 4]],
		"thumb": [Vector3(-0.8, -1.25, -0.3), Vector3(-0.55, -0.45, 1), Vector3(-0.15, -0.2, 1)],
		"grasp": Vector3(-2.6, -8.6, 0.0), "axis": Vector3(0, 0, 1)},
	POINT: {"wrist": [0.0, 0.0], "fingers": [[2, 3, 0, -3], [90, 100, 62, 0], [90, 100, 62, 2], [92, 100, 62, 4]],
		"thumb": [Vector3(-0.8, -1.25, -0.2), Vector3(-0.55, -0.45, 1), Vector3(-0.15, -0.2, 1)],
		"grasp": Vector3(-1.5, -6.0, 0.0), "axis": Vector3(0, 0, 1)},
	# The firing grip, round a pistol grip about 3 cm across and 5 cm fore and aft (its axis the
	# hand's z: the thumb up over the top of it, the little finger at its foot).
	GRIP: {"wrist": [-12.0, 0.0], "fingers": [[6, 4, 0, -8], [64, 100, 52, -1], [66, 100, 52, 2], [68, 100, 52, 5]],
		"thumb": [Vector3(-0.75, -1, -0.35), Vector3(-1, -0.75, 0.1), Vector3(-0.6, -0.6, 0.45)],
		"grasp": Vector3(-2.7, -9.2, 0.2), "axis": Vector3(0, 0, 1)},
	TRIGGER: {"wrist": [-12.0, 0.0], "fingers": [[34, 52, 22, -5], [64, 100, 52, -1], [66, 100, 52, 2], [68, 100, 52, 5]],
		"thumb": [Vector3(-0.75, -1, -0.35), Vector3(-1, -0.75, 0.1), Vector3(-0.6, -0.6, 0.45)],
		"grasp": Vector3(-2.7, -9.2, 0.2), "axis": Vector3(0, 0, 1)},
	PRESS: {"wrist": [-12.0, 0.0], "fingers": [[44, 68, 30, -5], [64, 100, 52, -1], [66, 100, 52, 2], [68, 100, 52, 5]],
		"thumb": [Vector3(-0.75, -1, -0.35), Vector3(-1, -0.75, 0.1), Vector3(-0.6, -0.6, 0.45)],
		"grasp": Vector3(-2.7, -9.2, 0.2), "axis": Vector3(0, 0, 1)},
	# Under a handguard about 4.5 cm round, the fingers up its far side, the thumb along the near.
	SUPPORT: {"wrist": [-8.0, 8.0], "fingers": [[48, 62, 30, -4], [50, 64, 30, 0], [52, 66, 30, 3], [55, 68, 30, 6]],
		"thumb": [Vector3(-0.7, -1, -0.5), Vector3(-0.75, -1, -0.15), Vector3(-0.6, -1, 0.05)],
		"grasp": Vector3(-3.6, -8.4, 0.0), "axis": Vector3(0, -0.5, 1)},
	# A magazine (about 3 cm thick, 7 cm wide) taken by its body: fingers round its front, the
	# thumb on its back.
	MAG: {"wrist": [0.0, 0.0], "fingers": [[38, 58, 22, -3], [40, 60, 22, 0], [42, 62, 22, 3], [46, 64, 22, 6]],
		"thumb": [Vector3(-0.85, -1, -0.2), Vector3(-0.8, -1, 0.15), Vector3(-0.5, -1, 0.25)],
		"grasp": Vector3(-2.8, -9.4, 0.0), "axis": Vector3(0, -1, 0)},
	# Round something about 3.5 cm across: a bandage roll, a tourniquet, a handle, a strap.
	HOLD: {"wrist": [0.0, 0.0], "fingers": [[58, 88, 46, -2], [60, 90, 46, 0], [62, 90, 46, 2], [64, 90, 46, 5]],
		"thumb": [Vector3(-0.8, -1, -0.3), Vector3(-0.95, -0.7, 0.3), Vector3(-0.5, -0.5, 0.6)],
		"grasp": Vector3(-2.6, -9.0, 0.0), "axis": Vector3(0, 0, 1)},
	# Thumb and index tips together (a syringe, a needle, tape, a charging handle); the other
	# fingers curled out of the way.
	PINCH: {"wrist": [5.0, 0.0], "fingers": [[42, 48, 22, -2], [62, 80, 40, 1], [70, 88, 46, 3], [76, 92, 50, 6]],
		"thumb": [Vector3(-0.9, -1, -0.15), Vector3(-0.75, -1, 0.3), Vector3(-0.45, -1, 0.35)],
		"grasp": Vector3(-3.4, -13.2, -1.9), "axis": Vector3(0, 0, 1)},
}


## The forearm model drawn for pose `pose` (POSES) on a `body` (VoxelArt.BODIES) soldier's
## right or left hand, gloved or bare (VoxelArt.hands_bare): "forearm:<pose>:<flags>" ("l" left,
## "b" bare). Plain "forearm" is the relaxed right hand in a glove (hit shapes, BodyVolume).
static func model(pose: StringName, left: bool, bare: bool, body := VoxelArt.MALE) -> String:
	var flags := ("l" if left else "") + ("b" if bare else "")
	return "%s:%s:%s" % [VoxelArt.body_part("forearm", body), pose, flags]


## The pose a forearm model shows (model()), RELAXED for a plain one.
static func pose_of(model_name: String) -> StringName:
	var p := StringName(model_name.get_slice(":", 1)) if model_name.contains(":") else RELAXED
	return p if TABLE.has(p) else RELAXED


## The hand frame -> forearm model voxels (cm, the frame's corner at 0) for `pose`, mirrored for a
## left hand by mirror_x afterwards: the wrist turned by the pose's flex and bend, and a woman's
## hand drawn FEMALE_SIZE about it.
static func hand_frame(pose: StringName, female: bool) -> Transform3D:
	var w: Array = TABLE.get(pose, TABLE[RELAXED]).wrist
	var basis := Basis(Vector3.BACK, -deg_to_rad(w[0])) * Basis(Vector3.RIGHT, -deg_to_rad(w[1]))
	return Transform3D(basis.scaled(Vector3.ONE * (FEMALE_SIZE if female else 1.0)), WRIST)


## The hand's parts for `pose` (VoxelArt lofts' cousins: obox dicts), right hand, in forearm model
## voxels. `bare`: skin, nails and creases; else a glove with a knuckle guard and a palm patch.
static func parts(pose: StringName, female: bool, bare: bool) -> Array:
	var t := hand_frame(pose, female)
	var def: Dictionary = TABLE.get(pose, TABLE[RELAXED])
	var slim := FEMALE_SLIM if female else 1.0
	var pad := 0.0 if bare else GLOVE_PAD
	var skin: int = VoxelArt.C.SKIN if bare else VoxelArt.C.GLOVE
	var shade: int = VoxelArt.C.SKIN_SHADE if bare else VoxelArt.C.GLOVE_PAD
	var out: Array = []
	var box := func(o: Vector3, b: Basis, h: Vector3, colour: int, bevel := 0.5, taper := 0.0, paint := false) -> void:
		out.append(VoxelArt.obox(t * o, t.basis.orthonormalized() * b, h, colour, bevel, taper, paint))
	# The palm: the back of the hand (its bones) a flat slab, wider at the knuckles; the heel of the
	# thumb and the pad under the little finger on the palm side, a hollow between (cupped).
	box.call(Vector3(0.35, -3.0, 0.0), Basis.IDENTITY, Vector3(1.3 * slim + pad, 2.8, 3.0 * slim + pad), skin, 0.55)
	box.call(Vector3(0.35, -7.6, 0.05), Basis.IDENTITY, Vector3(1.2 * slim + pad, 2.9, 3.85 * slim + pad), skin, 0.5)
	box.call(Vector3(-0.8, -3.4, -1.7), Basis(Vector3.RIGHT, -0.35), Vector3(1.0 * slim + pad, 2.7, 1.5 * slim), skin, 0.6)  # heel of the thumb
	box.call(Vector3(-0.65, -5.0, 2.4), Basis.IDENTITY, Vector3(0.75 * slim + pad, 3.6, 1.1 * slim), skin, 0.6)  # under the little finger
	box.call(Vector3(-0.7, -9.6, 0.05), Basis.IDENTITY, Vector3(0.6 * slim + pad, 0.9, 3.75 * slim), skin, 0.6)  # pads at the fingers' roots
	box.call(Vector3(0.1, -0.2, 0.0), Basis.IDENTITY, Vector3(1.9 * slim + pad, 1.4, 2.8 * slim + pad), skin, 0.6)  # the wrist
	if bare:
		box.call(Vector3(-1.3, -6.0, 0.4), Basis(Vector3.RIGHT, 0.5), Vector3(0.3, 3.0, 0.3), shade, 0.0, 0.0, true)  # the palm's crease
	else:
		box.call(Vector3(-1.2, -6.5, 0.6), Basis.IDENTITY, Vector3(0.5, 3.0, 3.0), shade, 0.0, 0.0, true)  # palm patch
		box.call(Vector3(1.6, -10.0, 0.05), Basis.IDENTITY, Vector3(0.45, 1.15, 3.9 * slim + pad), shade, 0.6)  # knuckle guard
		box.call(Vector3(0.1, 0.6, 0.0), Basis.IDENTITY, Vector3(2.1 * slim + pad, 0.6, 3.0 * slim + pad), shade, 0.6, 0.0, true)  # cuff strap
	var flex: Array = def.fingers
	for i in 4:
		var f: Array = FINGERS[i]
		var r: float = float(f[1]) * slim + pad
		var wide: float = float(f[2]) * slim + pad * 0.3
		var p: Vector3 = f[0]
		var ang: Array = flex[i]
		var spread := Basis(Vector3.RIGHT, deg_to_rad(float(ang[3])))
		var bent := 0.0
		for j in 3:
			bent += deg_to_rad(float(ang[j]))
			var b := spread * Basis(Vector3.BACK, -bent)  # bones bend toward the palm (-x)
			var length: float = f[3][j]
			var dir := b * Vector3.DOWN
			var rr := r * (1.0 - 0.07 * j)
			var ww := wide * (1.0 - 0.06 * j)
			box.call(p + dir * length * 0.5, b, Vector3(rr, length * 0.5 + rr * 0.45, ww), skin, 0.5, rr * 0.9 if j == 2 else 0.0)
			if j == 0 and bare:
				box.call(p + b * Vector3(r * 0.9, 0.2, 0), b, Vector3(0.35, 0.6, r * 0.8), shade, 0.5, 0.0, true)  # the knuckle
			if j == 2 and bare:
				box.call(p + dir * length * 0.6 + b * Vector3(rr * 0.75, 0, 0), b, Vector3(rr * 0.4, length * 0.34, ww * 0.75), VoxelArt.C.NAIL, 0.4, 0.0, true)
			p += dir * length
	# The thumb, its bones along the pose's directions.
	var tp: Vector3 = THUMB_BASE * Vector3(1, 1, slim)
	for j in 3:
		var dir: Vector3 = (def.thumb[j] as Vector3).normalized()
		var b := _along(dir)
		var length: float = THUMB_LEN[j]
		var rr: float = float(THUMB_R[j]) * slim + pad
		box.call(tp + dir * length * 0.5, b, Vector3(rr, length * 0.5 + rr * 0.4, rr * 1.05), skin, 0.5, rr * 0.9 if j == 2 else 0.0)
		if j == 2 and bare:
			box.call(tp + dir * length * 0.62 + b * Vector3(rr * 0.75, 0, 0), b, Vector3(rr * 0.4, length * 0.32, rr * 0.75), VoxelArt.C.NAIL, 0.4, 0.0, true)
		tp += dir * length
	return out


## A bone's basis: -y along `dir`, +x (its back: nails, knuckles) as near the hand's back (+x) as
## it can be.
static func _along(dir: Vector3) -> Basis:
	var y := -dir.normalized()
	var x := Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	if x.length_squared() < 0.0001:
		x = Vector3.BACK - y * Vector3.BACK.dot(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## Where a held object sits in pose `pose`, in the forearm's own space (metres from the elbow,
## as the forearm node's children see it): origin the grasp centre, +y along the object's axis,
## +z out of the palm. Mirrored for a left hand.
static func grasp(pose: StringName, left: bool, female: bool) -> Transform3D:
	var def: Dictionary = TABLE.get(pose, TABLE[RELAXED])
	var t := hand_frame(pose, female)
	var o: Vector3 = t * (def.grasp as Vector3)
	var y := (t.basis * (def.axis as Vector3)).normalized()
	var z := (t.basis * Vector3.LEFT).normalized()  # out of the palm
	var pivot := Vector3(9, 42, 9)
	o = (o - pivot) * VoxelArt.BODY_VOXEL
	if left:
		var m := Vector3(-1, 1, 1)
		o *= m
		y *= m
		z *= m
	z = (z - y * z.dot(y)).normalized()
	var b := Basis(y.cross(z), y, z)
	return Transform3D(b, o)


## Which way the palm faces in the forearm's own space (unit): -x on a right hand, +x on a left.
static func palm_normal(left: bool) -> Vector3:
	return Vector3.RIGHT if left else Vector3.LEFT


## The turn (radians) about a forearm's own long axis (its y) that brings its palm round to face
## `want` (in the forearm's own space) as nearly as it can: how a real forearm rolls (pronation,
## supination) to put the hand on a grip. 0 if `want` runs along the arm.
static func roll_to(want: Vector3, left: bool) -> float:
	var flat := Vector2(want.x, want.z)
	if flat.length_squared() < 1e-6:
		return 0.0
	var n := palm_normal(left)
	return _angle_about_y(Vector2(n.x, n.z), flat)


## The angle (about +y, right-handed) from (x, z) direction `a` to `b`.
static func _angle_about_y(a: Vector2, b: Vector2) -> float:
	# A turn about +y by t takes (x, z) to (x cos t + z sin t, -x sin t + z cos t).
	return atan2(a.y * b.x - a.x * b.y, a.x * b.x + a.y * b.y)


## Poses that close on something: the IK puts their grasp centre (grasp()) on the goal. The rest
## (RELAXED, OPEN, POINT) put the palm's centre there, as before.
const GRASPING: Array[StringName] = [FIST, GRIP, TRIGGER, PRESS, SUPPORT, MAG, HOLD, PINCH]
## The firing grip's poses (the index straight, on the trigger, squeezing it).
const FIRING: Array[StringName] = [GRIP, TRIGGER, PRESS]

## What a hand does for each of CharacterModel's arm goals (its goal keys; "held:..." goals are
## the weapon's, chosen there). Treatment keys here are only the defaults: whoever draws the
## props (CharacterModel.set_hand_pose) can say otherwise.
const GOAL_POSES := {
	"swing": RELAXED, "limp": RELAXED, "plant": OPEN, "push": OPEN, "lift": OPEN, "carry": OPEN,
	"drag": HOLD, "grip": HOLD, "draw": HOLD, "item": OPEN, "from": HOLD, "to": HOLD, "stow": HOLD,
	"work": OPEN, "radio": HOLD, "release": PINCH, "mech": FIST,
	"wrap": HOLD, "hold": PINCH, "pack": POINT, "press": OPEN, "strap": HOLD, "windlass": PINCH, "clip": PINCH,
	"steady": OPEN, "splint": OPEN, "peel": PINCH, "seal": OPEN, "needle": PINCH, "ready": HOLD, "jab": HOLD,
	"away": HOLD, "rest": OPEN, "iv_aim": PINCH, "iv_in": PINCH, "skin": OPEN, "tape": PINCH, "io": HOLD,
	"cpr": OPEN, "pad": OPEN, "clear": OPEN, "clamp": PINCH, "bag": HOLD, "line": PINCH, "blanket": OPEN,
	"npa": PINCH, "tilt": OPEN,
}
## A reload's support hand, by the anchor it's at (Reloads): the handguard, a magazine, the top of
## an internal magazine (a stripper clip), a catch, a charging or bolt handle, a feed cover.
const RELOAD_POSES := {&"rest": SUPPORT, &"mag": MAG, &"pouch": MAG, &"well": PINCH, &"catch": POINT,
	&"bolt": PINCH, &"cover": OPEN}


## The point of the hand an arm's IK puts on its goal, in the forearm's own space (metres from
## the elbow): a grasping pose's grasp centre, else the palm's centre (CharacterModel.FOREARM).
static func reach_point(pose: StringName, left: bool, female: bool) -> Vector3:
	if GRASPING.has(pose):
		return grasp(pose, left, female).origin
	return Vector3(0, -CharacterModel.FOREARM, 0)
