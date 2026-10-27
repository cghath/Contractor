class_name Feet
extends RefCounted
## Feet and footwear (Captain, 2026-10-21: "better feet"), in 0.5 cm voxels like the rest of the
## body. Each foot is a part of its own on an ankle joint at the bottom of its shin
## (CharacterModel), so it pitches as a real foot does: it plants flat, strikes with the heel
## and rolls off the toes walking, tucks its toes kneeling and prone. Its model is
## "foot:<style>:<flags>" ("foot_f" for a woman; flags "l" the left foot, "t" the toes bent up at
## the ball); the shin above it is drawn for the same style ("shin:<style>": a boot's shaft and
## laces round the leg, a trouser hem over a low shoe, a bare ankle over a sandal). Plain "shin"
## is still the old shin and boot in one, the leg's hit shape (BodyVolume).
##
## Styles (style_of: by the colour scheme, VoxelArt.VARIANTS "feet", a plain-clothes scheme's
## sixth field, or picked for plain clothes): combat BOOTS (a lugged sole with a heel, a toe box,
## laces up to a padded ankle cuff, speed hooks), SNEAKERS (a thick light sole, low, white laces),
## SHOES (leather, a thin sole and a low heel), SANDALS (a flat sole, straps, bare toes) and
## BARE feet.
##
## The foot frame, in cm: the ankle joint at PIVOT, the sole's bottom at y 0 (9 cm under the
## ankle), the toes toward z 0 (front is -z), the heel at the back. The left foot is the mirror.

const BOOTS := &"boots"
const SNEAKERS := &"sneakers"
const SHOES := &"shoes"
const SANDALS := &"sandals"
const BARE := &"bare"
const STYLES: Array[StringName] = [BOOTS, SNEAKERS, SHOES, SANDALS, BARE]
## Plain clothes with no footwear named: what they're likely to wear (a pick by the scheme's hash).
const PLAIN_PICKS: Array[StringName] = [SNEAKERS, SNEAKERS, SNEAKERS, SHOES, SHOES, SANDALS, SANDALS]
## Plain clothes in these shoes' colour wear boots (PersonLook: a commander in the field).
const BOOT_SHOES := "3a3027"

const SIZE := Vector3i(16, 22, 36)
const PIVOT := Vector3(8, 9, 26)
## The ankle joint in the shin model (cm, VoxelArt _shin's frame: the sole at y 0, the knee at
## the pivot, y 46), and the same in metres from the knee (where the foot node sits).
const SHIN_ANKLE_Y := 9.0
const ANKLE := Vector3(0, -(46.0 - SHIN_ANKLE_Y) * VoxelArt.BODY_VOXEL, 0)
## The ball of the foot: where the toes bend up (foot frame, cm from the ankle: under it at the
## sole, this far forward), and how far ("t").
const BALL_Z := -15.5
const TOE_BEND := 0.6
## A woman's foot is drawn this much smaller about the ankle (her body is also drawn at
## CharacterModel.FEMALE_SCALE), and this much narrower.
const FEMALE_SIZE := 0.95
const FEMALE_SLIM := 0.92


## The footwear soldiers or people in colour scheme `variant` wear (STYLES).
static func style_of(variant: String) -> StringName:
	if VoxelArt.VARIANTS.has(variant):
		return StringName(String(VoxelArt.VARIANTS[variant].get("feet", BOOTS)))
	if variant.begins_with(VoxelArt.CIV_PREFIX):
		var f := variant.split(":")
		if f.size() >= 6 and STYLES.has(StringName(f[5])):
			return StringName(f[5])
		if f.size() >= 5 and f[4] == BOOT_SHOES:
			return BOOTS
		return PLAIN_PICKS[absi(hash(variant)) % PLAIN_PICKS.size()]
	return BOOTS


## The foot model for `style` on a `body` (VoxelArt.BODIES) soldier's left or right foot, the
## toes bent up (`toes`) or not.
static func model(style: StringName, left: bool, toes: bool, body := VoxelArt.MALE) -> String:
	return "%s:%s:%s" % [VoxelArt.body_part("foot", body), style, ("l" if left else "") + ("t" if toes else "")]


## The shin model drawn above `style` (the boot's shaft, a trouser hem, a bare ankle).
static func shin_model(style: StringName, body := VoxelArt.MALE) -> String:
	return "%s:%s" % [VoxelArt.body_part("shin", body), style]


## A foot model's spec (VoxelArt._spec: "foot:..." and "foot_f:...").
static func foot_spec(model_name: String, female: bool) -> Dictionary:
	var style := StringName(model_name.get_slice(":", 1)) if model_name.get_slice_count(":") > 1 else BOOTS
	var flags := model_name.get_slice(":", 2) if model_name.get_slice_count(":") > 2 else ""
	var spec := {"size": SIZE, "pivot": PIVOT, "voxel": VoxelArt.BODY_VOXEL, "sub": VoxelArt.BODY_SUB,
		"boxes": _foot_parts(style, flags.contains("t"), female)}
	return VoxelArt._mirror_x(spec) if flags.contains("l") else spec


## A shin model's spec for footwear `style` ("shin:<style>"): the leg, the knee pad, and what the
## style shows above the ankle.
static func shin_spec(style: StringName, female: bool) -> Dictionary:
	return {"size": Vector3i(14, 46, 18), "pivot": Vector3(7, 46, 10), "voxel": VoxelArt.BODY_VOXEL, "sub": VoxelArt.BODY_SUB,
		"boxes": _shin_parts(style, female)}


static func _shin_parts(style: StringName, female: bool) -> Array:
	var C := VoxelArt.C
	var k := 0.93 if female else 1.0  # her calf and ankle, slimmer
	var out: Array = []
	# The calf behind the shin, and a knee pad shaped over the knee (model realism pass, 2026-10-26:
	# a rounded cap, not a flat block) held on by a strap round the leg (VoxelArt.knee_pad).
	out.append(VoxelArt.calf(female))
	var knee_pad: Array = VoxelArt.knee_pad(female)
	match style:
		BOOTS:
			# Trousers bloused over the boot's top, then the shaft round the lower leg up to a padded
			# cuff, laced up the front with speed hooks either side, a pull loop at the back.
			out.append(VoxelArt._loft(7, 10, [[16, 5.2 * k, 5.6 * k], [19, 5.6 * k, 5.9 * k], [22, 4.7 * k, 5.2 * k], [32, 5.4 * k, 6.0 * k], [46, 5.0 * k, 5.5 * k]], C.CAMO, 0.55))
			out.append(VoxelArt._loft(7, 10, [[5, 4.3 * k, 4.7 * k], [12, 4.3 * k, 4.6 * k], [18, 4.7 * k, 4.9 * k], [19.5, 5.0 * k, 5.2 * k]], C.BOOT, 0.45))
			out.append(VoxelArt._fp(0, 17.5, 0, 14, 19.5, 18, C.PAD))  # the padded cuff
			for i in 5:  # lace rungs up the front
				var y := 9.5 + 1.7 * i
				out.append(VoxelArt._fp(5.2, y, 0, 8.8, y + 0.6, 7.5, C.LACE))
			for side: float in [-1.0, 1.0]:
				for y: float in [11.5, 14.0, 16.5]:
					out.append(VoxelArt.obox(Vector3(7 + 2.3 * side, y, 10 - 4.75 * k), Basis.IDENTITY, Vector3(0.35, 0.35, 0.4), C.METAL))
			out.append(VoxelArt.obox(Vector3(7, 19.5, 10 + 5.0 * k), Basis.IDENTITY, Vector3(0.9, 1.1, 0.3), C.PAD))  # pull loop
		SNEAKERS, SHOES:
			# The trousers down to the shoe, the hem a little wider.
			out.append(VoxelArt._loft(7, 10, [[7.5, 4.6 * k, 5.1 * k], [10, 4.3 * k, 4.8 * k], [14, 4.1 * k, 4.6 * k], [32, 5.4 * k, 6.0 * k], [46, 5.0 * k, 5.5 * k]], C.CAMO, 0.55))
			out.append(VoxelArt._fp(0, 7.5, 0, 14, 8.5, 18, C.CAMO_A))  # the hem
		_:  # sandals, bare: trousers to above the ankle, the ankle bare
			out.append(VoxelArt._loft(7, 10, [[12, 4.7 * k, 5.1 * k], [15, 4.3 * k, 4.7 * k], [32, 5.4 * k, 6.0 * k], [46, 5.0 * k, 5.5 * k]], C.CAMO, 0.55))
			out.append(VoxelArt._fp(0, 12, 0, 14, 13, 18, C.CAMO_A))
			out.append(VoxelArt._loft(7, 10, [[5.5, 2.9 * k, 3.3 * k], [9, 2.9 * k, 3.4 * k], [13, 3.6 * k, 4.0 * k]], C.SKIN, 0.6))
	out.append_array(knee_pad)
	return out


## The foot's parts, right foot, in its frame (cm).
static func _foot_parts(style: StringName, toes: bool, female: bool) -> Array:
	var C := VoxelArt.C
	var size := FEMALE_SIZE if female else 1.0
	var slim := FEMALE_SLIM if female else 1.0
	var out: Array = []
	# Everything is written from the ankle (cm: +y up, -z forward); `fore` parts (ahead of the
	# ball) turn up about it with the toes bent.
	var ball := Vector3(0, -9.0, BALL_Z)
	var bend := Basis(Vector3.RIGHT, TOE_BEND if toes else 0.0)
	var box := func(o: Vector3, b: Basis, h: Vector3, colour: int, bevel := 0.5, taper := 0.0, paint := false, fore := false) -> void:
		if fore:
			o = ball + bend * (o - ball)
			b = bend * b
		var at := PIVOT + Vector3(o.x * size * slim, o.y * size, o.z * size)
		var half := Vector3(h.x * size * slim, h.y * size, h.z * size)
		out.append(VoxelArt.obox(at, b, half, colour, bevel, taper, paint))
	var ahead := Basis(Vector3.RIGHT, PI / 2)  # a box's local -y forward (its taper at the toe)
	match style:
		BOOTS:
			# Outsole: a deep heel block, a narrower shank under the arch, the forefoot with a
			# little toe spring, lugs round the edge.
			box.call(Vector3(0, -7.8, 4.0), Basis.IDENTITY, Vector3(4.5, 1.2, 4.0), C.SOLE, 0.45)
			box.call(Vector3(0, -7.9, -4.5), Basis.IDENTITY, Vector3(4.3, 0.9, 4.7), C.SOLE, 0.45)
			box.call(Vector3(0, -8.2, -12.8), ahead, Vector3(5.3, 3.8, 0.8), C.SOLE, 0.5, 0.0, false, false)
			box.call(Vector3(0, -8.0, -20.0), ahead * Basis(Vector3.RIGHT, -0.12), Vector3(5.2, 4.0, 0.85), C.SOLE, 0.55, 3.2, false, true)
			for z: float in [6.5, 4.0, 1.5, -1.0, -11.0, -13.5, -16.0, -18.5, -21.0]:
				var w := _sole_half(z) + 0.15
				for side: float in [-1.0, 1.0]:
					box.call(Vector3(w * side, -8.4, z), Basis.IDENTITY, Vector3(0.35, 0.5, 0.55), C.SOLE, 0.3, 0.0, false, z < BALL_Z)
			# The upper: a rounded heel counter, the quarters up round the ankle, the instep
			# sloping down to a firm toe box with a darker toe cap.
			box.call(Vector3(0, -3.6, 4.5), Basis.IDENTITY, Vector3(4.2, 3.4, 3.4), C.BOOT, 0.75)
			box.call(Vector3(0, 0.6, 1.8), Basis.IDENTITY, Vector3(4.3, 3.6, 4.3), C.BOOT, 0.7)
			box.call(Vector3(0, -3.6, -6.8), Basis(Vector3.RIGHT, -0.32), Vector3(4.5, 3.0, 6.2), C.BOOT, 0.7)
			box.call(Vector3(0, -4.6, -1.8), Basis.IDENTITY, Vector3(4.35, 2.9, 4.8), C.BOOT, 0.7)  # the midfoot
			box.call(Vector3(0, -5.9, -17.8), ahead, Vector3(4.9, 6.0, 2.3), C.BOOT, 0.7, 2.8, false, true)
			box.call(Vector3(0, -6.4, -21.6), Basis.IDENTITY, Vector3(5.4, 1.9, 2.4), C.SOLE, 0.0, 0.0, true, true)  # toe cap
			box.call(Vector3(0, -4.2, 7.4), Basis.IDENTITY, Vector3(4.5, 3.0, 0.8), C.PAD, 0.0, 0.0, true)  # heel counter
			_laces(box, C.LACE, true)
		SNEAKERS, SHOES:
			var sneaker := style == SNEAKERS
			var sole_c: int = C.SOLE_LIGHT if sneaker else C.SOLE
			var t := 1.15 if sneaker else 0.7  # the sole's half-thickness
			box.call(Vector3(0, -9.0 + t + (0.3 if not sneaker else 0.0), 3.8), Basis.IDENTITY, Vector3(4.3, t + (0.3 if not sneaker else 0.0), 3.9), sole_c, 0.5)
			box.call(Vector3(0, -9.0 + t, -5.0), Basis.IDENTITY, Vector3(4.2, t, 5.2), sole_c, 0.5)
			box.call(Vector3(0, -9.0 + t, -18.5), ahead * Basis(Vector3.RIGHT, -0.1), Vector3(5.0, 5.4, t), sole_c, 0.55, 3.5, false, true)
			if sneaker:  # a stripe round the midsole
				box.call(Vector3(0, -7.6, -5.0), Basis.IDENTITY, Vector3(5.4, 0.3, 13.5), C.BOOT, 0.0, 0.0, true)
			var top := -1.5 if sneaker else -2.2  # low: the collar under the ankle bone
			box.call(Vector3(0, (-9.0 + 2.0 * t + top) * 0.5, 3.8), Basis.IDENTITY, Vector3(4.0, (top + 9.0 - 2.0 * t) * 0.5, 3.4), C.BOOT, 0.75)
			box.call(Vector3(0, -4.3, -6.5), Basis(Vector3.RIGHT, -0.3), Vector3(4.3, 2.6, 6.0), C.BOOT, 0.7)
			box.call(Vector3(0, -5.0, -1.2), Basis.IDENTITY, Vector3(4.1, 2.4, 4.4), C.BOOT, 0.7)  # the midfoot
			box.call(Vector3(0, -6.4, -17.5), ahead, Vector3(4.6, 5.5, 2.0 if sneaker else 1.7), C.BOOT, 0.75, 3.0, false, true)
			_laces(box, C.SOLE_LIGHT if sneaker else C.LACE, false)
		_:
			# A bare foot (on a sandal's sole): heel, the instep, the ball, five toes.
			var sandal := style == SANDALS
			var lift := 1.2 if sandal else 0.0
			if sandal:
				box.call(Vector3(0, -8.4, 3.6), Basis.IDENTITY, Vector3(3.9, 0.6, 4.0), C.SOLE, 0.45)
				box.call(Vector3(0, -8.4, -6.0), Basis.IDENTITY, Vector3(4.2, 0.6, 6.0), C.SOLE, 0.45)
				box.call(Vector3(0, -8.4, -18.0), ahead, Vector3(4.8, 6.4, 0.6), C.SOLE, 0.5, 3.5, false, true)
			box.call(Vector3(0, -5.8 + lift * 0.5, 3.8), Basis.IDENTITY, Vector3(3.2, 3.0 - lift * 0.5, 3.0), C.SKIN, 0.8)
			box.call(Vector3(0, -2.6, 0.6), Basis.IDENTITY, Vector3(3.0, 3.4, 3.0), C.SKIN, 0.7)
			box.call(Vector3(0.2, -5.0 + lift * 0.4, -6.8), Basis(Vector3.RIGHT, -0.26), Vector3(3.8, 2.4 - lift * 0.3, 5.4), C.SKIN, 0.6)
			box.call(Vector3(0, -7.2 + lift * 0.6, -13.4), Basis.IDENTITY, Vector3(4.5, 1.6 - lift * 0.3, 2.6), C.SKIN, 0.6)
			box.call(Vector3(1.3, -7.5 + lift * 0.6, -4.8), Basis.IDENTITY, Vector3(2.9, 1.5 - lift * 0.3, 6.2), C.SKIN, 0.6)  # the outer edge on the ground (the arch is inside)
			# Toes, the big toe on the inside (-x on the right foot), each a little shorter outward.
			var toes_at := [[-3.0, 1.15, 4.6, -15.6], [-0.9, 0.72, 3.7, -15.9], [0.85, 0.68, 3.3, -15.6], [2.45, 0.64, 2.9, -15.0], [3.85, 0.6, 2.4, -14.2]]
			for t: Array in toes_at:
				var r: float = t[1]
				var length: float = t[2]
				var o := Vector3(float(t[0]), -9.0 + lift + r * 0.95, float(t[3]) - length * 0.5)
				box.call(o, ahead, Vector3(r * 0.85, length * 0.5 + r * 0.3, r * 0.95), C.SKIN, 0.55, r * 1.1, false, true)  # a groove between toes
				box.call(o + Vector3(0, r * 0.75, -length * 0.3), Basis.IDENTITY, Vector3(r * 0.7, 0.3, length * 0.2), C.NAIL, 0.3, 0.0, true, true)
			if sandal:  # straps: over the toes' roots, across the instep, round the heel
				box.call(Vector3(0, -6.6, -13.6), Basis.IDENTITY, Vector3(4.8, 1.3, 0.9), C.BOOT, 0.5, 0.0, false, false)
				box.call(Vector3(0, -3.8, -5.0), Basis(Vector3.RIGHT, -0.5), Vector3(4.2, 0.6, 1.0), C.BOOT, 0.5)
				box.call(Vector3(0, -5.2, 4.2), Basis.IDENTITY, Vector3(3.5, 0.6, 3.3), C.BOOT, 0.5)
	return out


## The outsole's half-width at `z` (cm from the ankle, -z forward): the heel, the arch, the
## ball and the toe.
static func _sole_half(z: float) -> float:
	if z > -1.0:
		return 4.4
	if z > -9.0:
		return 4.2
	return lerpf(5.2, 4.2, clampf((-z - 15.0) / 8.0, 0.0, 1.0))


## Laces across the instep (rungs), with metal eyelets either side on a boot.
static func _laces(box: Callable, colour: int, eyelets: bool) -> void:
	for i in 5:
		var z := -10.5 + 2.1 * i
		var y := -0.9 + 0.29 * z  # the instep's top, sloping down to the toes
		box.call(Vector3(0, y - 0.3, z), Basis.IDENTITY, Vector3(1.9, 2.0, 0.35), colour, 0.0, 0.0, true)
		if eyelets:
			for side: float in [-1.0, 1.0]:
				box.call(Vector3(2.3 * side, y + 0.15, z), Basis.IDENTITY, Vector3(0.3, 0.3, 0.3), VoxelArt.C.METAL, 0.3)


## The foot's pitch to the ground through a step (radians, + the toes up; CharacterModel._gait_foot):
## the toes up as the heel strikes (STRIKE_PITCH, easing flat over the first STRIKE_SHARE of the
## stance), the heel rising from ROLL_FROM of it to PUSH_PITCH as it pushes off the toes, then
## SWING_PITCH early in the swing and back up to land. TUCK_PITCH: up on the tucked toes, kneeling
## or prone.
const STRIKE_PITCH := 0.3
const STRIKE_SHARE := 0.15
const ROLL_FROM := 0.6
const PUSH_PITCH := -0.6
const SWING_PITCH := -0.15
const TUCK_PITCH := -1.05


## The ankle's turn (radians about the shin's own x: + lifts the toes) that gives a foot under a
## shin pitched `shin_pitch` (radians: its own forward's tilt above the ground) the pitch `want`
## to the ground, within the joint's reach (ANKLE_MIN..ANKLE_MAX).
const ANKLE_MIN := -0.9
const ANKLE_MAX := 0.55
static func ankle_for(want: float, shin_pitch: float) -> float:
	return clampf(want - shin_pitch, ANKLE_MIN, ANKLE_MAX)
