class_name FaceArt
extends RefCounted
## Heads and faces on the voxel body (VoxelArt "head", "head_f"), built at 0.5 cm like the rest
## of it (Captain, 2026-10-20: realism from detail at that scale, not meshes or textures).
##
## The head keeps the old frame and pivot (the base of the neck), so every helmet, NVG and IFF
## mark still fits (GearRig.HELMET_POSITION: the helmet's rim at head y 0.20 m), but it now has
## real proportions: a skull, a brow ridge over eye sockets, a nose with a bridge and a tip,
## cheekbones, a jaw and chin, ears, and hair and beards with volume. Measurements below are
## head-local centimetres (VoxelArt.BODY_VOXEL), x across (11 the middle), y up from the neck's
## base, z from the front (0) back.
##
## The face is a height field: for each 0.5 cm column across it, how far back its surface is
## (front_z), carved in front and filled behind. The skull, neck and hair round it are lofts.
##
## What moves is apart, as small meshes of their own swapped in whole (FaceRig): each eye (eye
## models: open looking nine ways, half shut, shut), the mouth (mouth models: EXPRESSIONS) and
## each brow (brow models). Their slots in the head are carved out to fit them.
##
## Shapes come from SoldierLook's digits: hair style, beard, jaw, chin, nose, brow ridge,
## cheekbones and ears.

## Expressions (FaceRig.expression): the mouth and brows each have one of these.
const NEUTRAL := 0
const STRAIN := 1   # wounded, carrying: lips pressed, teeth set, brows knit
const SHOUT := 2    # a callout or a scream: mouth open, brows down hard
const SLACK := 3    # unconscious or dead, and gasping for breath: jaw dropped, face loose
const EXPRESSIONS: Array[int] = [NEUTRAL, STRAIN, SHOUT, SLACK]

## Eye slots: the middles of the two eyes (x), their row (EYE_Y up to EYE_Y + EYE_H), width and
## depth: the eye model fills EYE_Z to EYE_BACK, the head is carved to EYE_BACK.
const EYE_X: Array[float] = [7.25, 14.75]
const EYE_Y := 17.0
const EYE_W := 3.5
const EYE_H := 1.5
const EYE_Z := 3.0
const EYE_BACK := 4.0
## Eye models, in 0.5 cm voxels: EYE_COLS x EYE_ROWS x 2 (the lid layer in front, the eyeball
## behind). An open eye's iris is IRIS_COLS wide with its pupil in the middle.
const EYE_COLS := 7
const EYE_ROWS := 3
const IRIS_COLS := 3
## The mouth's slot (x from, x to, y from, y to, the model's front, the carve's back).
const MOUTH_X := Vector2(8.5, 13.5)
const MOUTH_Y := Vector2(8.5, 12.0)
const MOUTH_Z := 1.5
const MOUTH_BACK := 3.5
## Brows: each BROW_COLS 0.5 cm voxels wide round its eye's middle, BROW_ROWS high from BROW_Y,
## on the brow ridge's surface (front_z).
const BROW_Y := 19.0
const BROW_COLS := 10
const BROW_ROWS := 4
## The mesh frame: its size (cm) and pivot.
const SIZE := Vector3i(22, 32, 26)
const SIZE_F := Vector3i(22, 32, 31)
const PIVOT := Vector3(11, 0, 12)


## The shape digits (SoldierLook.SHAPE_KEYS) as numbers, by name.
static func shape_of(digits: String, female: bool) -> Dictionary:
	if digits.length() != SoldierLook.SHAPE_KEYS.size() or not digits.is_valid_int():
		digits = SoldierLook.DEFAULT_FEMALE_SHAPE if female else SoldierLook.DEFAULT_SHAPE
	var p := {"female": female}
	var top := [3 if female else 5, 5, 2, 2, 3, 1, 1, 1]  # each digit's highest (a bad code can't reach past the tables)
	for i in SoldierLook.SHAPE_KEYS.size():
		p[SoldierLook.SHAPE_KEYS[i]] = clampi(digits.substr(i, 1).to_int(), 0, top[i])
	if female:
		p.beard = SoldierLook.CLEAN
		p.brow = 0
	return p


# --- The face's surface ---------------------------------------------------------------------

## Piecewise-linear through `keys` ([[at, value], ...], `at` rising).
static func _lerp_keys(keys: Array, at: float) -> float:
	if at <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if at <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(float(a[1]), float(b[1]), (at - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(keys[keys.size() - 1][1])


## A smooth bump: 1 at `centre`, 0 from `half` away.
static func _bell(v: float, centre: float, half: float) -> float:
	var t := clampf(absf(v - centre) / half, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## The face's half-width (cm) at height `y`: 0 below the chin.
static func half_width(y: float, p: Dictionary) -> float:
	var w := _lerp_keys([[5.75, 0.0], [6.0, 2.6], [6.5, 3.3], [7.5, 4.5], [8.5, 5.7], [9.5, 6.7], [10.5, 7.5], [12.0, 8.2],
		[14.0, 8.8], [15.5, 9.3], [18.0, 9.3], [21.0, 9.4], [25.0, 9.2], [27.5, 8.4], [28.0, 0.0]], y)
	var jaw := [0.86, 1.0, 1.12][int(p.jaw)] as float
	var low := 1.0 - smoothstep(10.0, 13.0, y)  # how much of the jaw's width this height is
	if int(p.jaw) == 2 and y < 7.5:
		w = maxf(w, _lerp_keys([[5.75, 0.0], [6.0, 3.4], [7.5, 4.9]], y))  # a square chin
	w *= lerpf(1.0, jaw, low)
	if p.female:
		w *= lerpf(0.97, 0.88, low)
	return w


## How far back (cm from the frame's front) the middle of the face is at height `y`, before
## the nose: chin, lips, cheeks, eyes, brow ridge, forehead.
static func centre_z(y: float, p: Dictionary) -> float:
	var z := _lerp_keys([[5.75, 4.2], [6.25, 3.0], [7.0, 2.5], [8.0, 2.3], [8.75, 2.8], [9.5, 2.4], [10.5, 2.3], [11.5, 2.3],
		[12.5, 2.6], [13.5, 2.8], [15.5, 3.0], [17.5, 3.2], [18.75, 2.8], [19.5, 1.9], [20.75, 1.8], [22.0, 2.1],
		[24.0, 2.6], [26.0, 3.4], [27.75, 4.6]], y)
	var chin := 1.0 - smoothstep(8.5, 9.5, y)
	z += [0.7, 0.0, -0.4][int(p.chin)] * chin
	if int(p.brow) == 1:
		z -= 0.4 * _bell(y, 20.0, 1.4)
	if p.female:
		z += 0.3 * _bell(y, 20.0, 1.6)  # a softer brow
	return z


## How far the face's sides fall back from its middle at height `y` (at its half-width).
static func side_back(y: float) -> float:
	return _lerp_keys([[6.0, 3.0], [8.0, 4.5], [10.0, 6.5], [12.0, 6.5], [14.0, 5.0], [16.0, 4.6], [18.0, 5.2], [20.0, 5.6], [24.0, 6.0], [27.5, 6.0]], y)


## The nose's ridge (cm back from the front) at height `y`, or INF where there's none.
static func nose_z(y: float, p: Dictionary) -> float:
	if y < 12.75 or y > 19.25:
		return INF
	var tip := [0.8, 0.3, 0.0, 1.0][int(p.nose)] as float
	var bridge := [2.2, 2.1, 1.9, 2.5][int(p.nose)] as float
	var hump := 0.45 if int(p.nose) == 2 else 0.0
	var z := _lerp_keys([[12.75, 2.2], [13.25, tip + 0.9], [13.75, tip], [14.75, tip + 0.4], [16.0, lerpf(tip, bridge, 0.55) - hump],
		[18.0, bridge], [19.25, 2.5]], y)
	if p.female:
		z += 0.25
	return z


## The nose's half-width at height `y`.
static func nose_half(y: float, p: Dictionary) -> float:
	var alae := [1.25, 1.5, 1.75, 2.25][int(p.nose)] as float
	var bridge := [0.7, 0.8, 0.9, 1.0][int(p.nose)] as float
	return _lerp_keys([[12.75, alae - 0.5], [13.25, alae], [14.25, alae], [15.0, bridge + 0.3], [16.0, bridge], [19.25, bridge + 0.2]], y)


## The face's surface: how far back (cm) the skin is at (`x`, `y`) (column middles), or INF
## outside the face. No hair or beard on it (head() adds those).
static func front_z(x: float, y: float, p: Dictionary) -> float:
	var hw := half_width(y, p)
	var d := absf(x - 11.0)
	if hw <= 0.0 or d > hw:
		return INF
	var z := centre_z(y, p) + side_back(y) * pow(d / hw, 2.2)
	# Cheekbones: forward under the outer eye, more when high.
	z -= ([0.4, 0.8][int(p.cheek)] as float) * _bell(d, 6.0, 2.2) * _bell(y, 15.25, 1.4)
	# The brow ridge runs out over the eyes before the temples fall away.
	z -= 0.5 * _bell(y, 20.0, 0.9) * _bell(d, 4.0, 3.0)
	# Eye sockets: deepest round the eye, easing out to the brow, the cheek and the nose.
	for ex in EYE_X:
		var q := pow((x - ex) / 2.7, 2.0) + pow((y - 17.75) / 1.8, 2.0)
		if q < 1.0:
			z = maxf(z, lerpf(EYE_Z + 0.6, z, q * q))
	var nz := nose_z(y, p)
	if nz < INF:
		var nh := nose_half(y, p)
		if d < nh:
			z = minf(z, nz + pow(d / nh, 1.6) * maxf(z - nz, 0.0))
	# The lips sit a little forward of the skin round them (the mouth model draws them).
	return z


## The beard's region (beard digit `beard`) at (`x`, `y`): 0 none, 1 stubble shadow, 2 hair.
static func beard_at(x: float, y: float, z: float, beard: int) -> int:
	var d := absf(x - 11.0)
	if beard == SoldierLook.CLEAN or y > 16.0:
		return 0
	var lip := y >= 11.25 and y < 12.75 and d < 3.25    # over the upper lip
	var corners := y >= 9.75 and y < 11.25 and d >= 2.5 and d < 3.25  # down past the mouth's corners
	var chin := y < 9.5 and d < 3.5
	# The cheek line: from the mouth's corner up and out to the sideburn's foot by the ear.
	var top := 10.25 + maxf(d - 2.5, 0.0) * 0.95
	var jaw := y < top and d >= 2.5
	var cheek := jaw and d > 6.0
	match beard:
		SoldierLook.STUBBLE:
			return 1 if lip or chin or jaw or cheek else 0
		SoldierLook.MOUSTACHE:
			return 2 if lip or corners else (1 if (chin or jaw) and y < 10.0 else 0)
		SoldierLook.GOATEE:
			return 2 if lip or corners or (chin and d < 2.6) else 0
		SoldierLook.SHORT_BEARD, SoldierLook.FULL_BEARD:
			return 2 if lip or chin or jaw or cheek else 0
	return 0


## How far a beard stands off the skin (cm) at height `y`.
static func beard_depth(beard: int, y: float) -> float:
	match beard:
		SoldierLook.SHORT_BEARD:
			return 0.5
		SoldierLook.FULL_BEARD:
			return 1.5 if y < 8.0 else 1.0
		SoldierLook.GOATEE:
			return 0.5 if y < 9.0 else 0.0
	return 0.0


## Where the front hairline is (y, cm) `d` cm out from the middle, for hair style `style`.
static func hairline(d: float, style: int, female: bool) -> float:
	if female:
		return 25.0 + 0.6 * smoothstep(3.0, 7.5, d)
	match style:
		SoldierLook.RECEDING, SoldierLook.SHAVED:  # (receding: the hair starts back on the crown, off the face)
			return 99.0
	return 25.5 + 0.7 * smoothstep(4.0, 7.5, d) - (0.6 if style == SoldierLook.LONG_TOP else 0.0)


# --- Models ---------------------------------------------------------------------------------

## The skull (and the hair round it, `grow` cm bigger), on its centre (11, 13).
static func _skull_keys(grow: float, top_grow := -1.0, female := false) -> Array:
	var top := grow if top_grow < 0.0 else top_grow
	var keys := [[8.0, 5.5, 7.0], [10.0, 7.6, 9.0], [13.0, 8.8, 10.2], [17.0, 9.4, 10.8], [22.0, 9.6, 11.0], [25.0, 9.3, 10.8],
		[27.5, 8.2, 9.8], [29.5, 5.8, 7.5], [30.0, 4.0, 5.5]]
	var out := []
	for k: Array in keys:
		var w := float(k[1]) * (0.96 if female else 1.0)
		var g := lerpf(grow, top, smoothstep(22.0, 27.0, float(k[0])))
		out.append([float(k[0]) + (g if float(k[0]) >= 29.5 else 0.0), w + g, float(k[2]) + g])
	return out


## A head: `digits` the shape (SoldierLook), `female` the female head (the same frame, with a
## longer neck line, a softer jaw and brow, and her hair kept short of the helmet's rim).
static func head(digits: String, female: bool) -> Dictionary:
	var p := shape_of(digits, female)
	var C := VoxelArt.C
	var boxes := []
	var style: int = p.hair
	var hair := C.HAIR
	# Hair on the skull: a shell grown round it, cut back from the face, the ears and the nape.
	if female or style != SoldierLook.SHAVED:
		if not female and style == SoldierLook.CREW:
			boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.5), C.STUBBLE, 0.55))
			boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.0, 1.0).slice(4), C.HAIR, 0.55))
		elif not female and style == SoldierLook.BUZZ:
			boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.5), C.HAIR, 0.55))
		elif not female and style == SoldierLook.RECEDING:
			boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.5, 0.5), C.HAIR, 0.55))
		else:
			var top := 2.0 if style == SoldierLook.LONG_TOP and not female else 1.0
			boxes.append(VoxelArt._loft(11, 13, _skull_keys(1.0, top, female), C.HAIR, 0.55))
		var nape := 9.5 if female else 11.5
		boxes.append(VoxelArt._fb(0, 0, 0, 22, 25.0, 8.5, C.EMPTY))           # the temples, in front of the sideburns
		boxes.append(VoxelArt._fb(0, 0, 8.5, 22, 18.5, 15.5, C.EMPTY))        # below the sideburns, round the ears
		boxes.append(VoxelArt._fb(0, 0, 15.5, 22, nape, SIZE_F.z, C.EMPTY))   # below the nape
		if not female and style == SoldierLook.RECEDING:
			boxes.append(VoxelArt._fb(0, 25.0, 0, 22, 32, 6.0, C.EMPTY))     # the crown's front, thinning
	else:
		boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.5), C.STUBBLE, 0.55))  # shaved: a shadow of it
		boxes.append(VoxelArt._fb(0, 0, 0, 22, 25.5, 8.5, C.EMPTY))
		boxes.append(VoxelArt._fb(0, 0, 8.5, 22, 18.5, 15.5, C.EMPTY))
		boxes.append(VoxelArt._fb(0, 0, 15.5, 22, 11.5, SIZE_F.z, C.EMPTY))
	# The skull and neck.
	var neck := 4.6 if female else 5.6
	boxes.append(VoxelArt._loft(11, 13.5, [[0, neck, neck], [9, neck + 0.2, neck]], C.SKIN, 0.75))
	if not female:
		boxes.append(VoxelArt._fb(10.5, 3.0, 7.5, 11.5, 5.0, 8.5, C.SKIN))  # Adam's apple
	boxes.append(VoxelArt._loft(11, 13, _skull_keys(0.0, 0.0, female), C.SKIN, 0.55))
	boxes.append_array(_face_columns(p))
	# Ears: a helix, a lobe and the hollow inside, standing out from the skull's sides.
	var out := 1.5 if int(p.ears) == 1 else 0.75
	var scale := 0.88 if female else 1.0
	for side: float in [-1.0, 1.0]:
		var skin_x := 11.0 + side * (9.2 if not female else 8.8)
		var x0 := skin_x - (out if side < 0.0 else 0.0)
		var x1 := skin_x + (out if side > 0.0 else 0.0)
		var y0 := 13.5
		var h := 6.0 * scale
		boxes.append(VoxelArt._fb(x0, y0 + 1.0, 11.5, x1, y0 + h - 0.5, 15.0, C.SKIN))       # the helix
		boxes.append(VoxelArt._fb(x0, y0, 12.0, x1, y0 + 1.0, 14.0, C.SKIN))                 # the lobe
		boxes.append(VoxelArt._fb(x0, y0 + h - 0.5, 12.0, x1, y0 + h, 14.5, C.SKIN))        # the top
		var face_x := x0 if side < 0.0 else x1 - 0.5
		boxes.append(VoxelArt._fbp(face_x, y0 + 1.5, 12.5, face_x + 0.5, y0 + h - 1.5, 14.0, C.SKIN_SHADE))  # the hollow
	# The slots the eyes and mouth fill (FaceRig).
	for ex in EYE_X:
		boxes.append(VoxelArt._fb(ex - EYE_W * 0.5, EYE_Y, 0, ex + EYE_W * 0.5, EYE_Y + EYE_H, EYE_BACK, C.EMPTY))
	boxes.append(VoxelArt._fb(MOUTH_X.x, MOUTH_Y.x, 0, MOUTH_X.y, MOUTH_Y.y, MOUTH_BACK, C.EMPTY))
	if female:
		boxes.append_array(_female_hair(style))
	return {"size": SIZE_F if female else SIZE, "pivot": PIVOT, "voxel": VoxelArt.BODY_VOXEL, "sub": VoxelArt.BODY_SUB, "boxes": boxes}


## The face's 0.5 cm columns: carved to its surface (front_z), with hair over the forehead above
## the hairline and the beard on the jaw, filled back to where the skull takes over.
static func _face_columns(p: Dictionary) -> Array:
	var C := VoxelArt.C
	var out := []
	var style: int = p.hair
	var beard: int = p.beard
	var bald: bool = not p.female and style == SoldierLook.SHAVED
	var thick := 2.0 if style == SoldierLook.LONG_TOP and not p.female else (0.5 if style in [SoldierLook.BUZZ, SoldierLook.CREW, SoldierLook.RECEDING] and not p.female else 1.0)
	for xi in range(4, 40):
		var x := xi * 0.5
		var xc := x + 0.25
		var d := absf(xc - 11.0)
		for yi in range(11, 56):
			var y := yi * 0.5
			var yc := y + 0.25
			var z := front_z(xc, yc, p)
			if z == INF:
				continue
			var colour := C.SKIN
			if yc >= hairline(d, style, p.female):
				colour = C.STUBBLE if bald else C.HAIR
				if not bald:
					z -= thick * smoothstep(0.0, 1.0, (yc - hairline(d, style, p.female)) / 1.0)
			var b := beard_at(xc, yc, z, beard)
			if b == 2:
				colour = C.HAIR
				z -= beard_depth(beard, yc)
			elif b == 1:
				colour = C.STUBBLE
			# Light shading in the creases: beside the nostrils down to the mouth's corners, and
			# the nostrils themselves.
			if colour == C.SKIN:
				var fold := 2.1 + (13.0 - yc) * 0.35
				if yc > 10.25 and yc < 13.0 and absf(d - fold) < 0.3:
					colour = C.SKIN_SHADE
				if yc > 12.75 and yc < 13.25 and d > 0.5 and d < nose_half(13.0, p) - 0.25:
					colour = C.MOUTH
			var back := 9.5
			if yc < 10.0:  # the jaw's underside runs back and up to its angle under the ear
				back = minf(back, _lerp_keys([[5.75, 3.5], [6.5, 5.5], [7.5, 8.0], [8.5, 9.5]], yc) + (1.0 if beard == SoldierLook.FULL_BEARD else 0.0))
			z = roundf(z * 2.0) * 0.5
			if z >= back:
				continue
			if z > 0.0:
				out.append(VoxelArt._fb(x, y, 0, x + 0.5, y + 0.5, z, C.EMPTY))
			out.append(VoxelArt._fb(x, y, z, x + 0.5, y + 0.5, back, colour))
	# A full beard hangs below the chin.
	if beard == SoldierLook.FULL_BEARD:
		out.append(VoxelArt._loft(11, 4.5, [[4.5, 2.5, 2.0], [6.0, 4.0, 2.8]], C.HAIR, 0.6))
	return out


## A woman's hair behind the head (`style`: SoldierLook.BUN, BRAID, PONYTAIL, PIXIE), below the
## helmet's rim (head y 20) so every helmet still fits over it.
static func _female_hair(style: int) -> Array:
	var C := VoxelArt.C
	match style:
		SoldierLook.BUN:
			return [VoxelArt._loft(11, 25, [[11, 2.5, 2.0], [13, 3.5, 3.0], [17, 3.5, 3.0], [19, 2.5, 2.0]], C.HAIR, 0.6),
				VoxelArt._fb(8, 14.5, 23.5, 14, 15.5, 25.0, C.PAD)]  # the tie
		SoldierLook.BRAID:
			var out := []
			for i in 6:  # plaits down the back of the neck, overlapping, each a little narrower
				var y := 17.0 - i * 2.0
				out.append(VoxelArt._loft(11, 24.0 - i * 0.3, [[y - 2.5, 1.2 - i * 0.08, 1.0], [y - 1.25, 1.7 - i * 0.08, 1.4], [y, 1.3 - i * 0.08, 1.0]], C.HAIR, 0.6))
			out.append(VoxelArt._fb(10.0, 4.0, 21.75, 12.0, 5.0, 23.5, C.PAD))  # the tie, round the last plait
			return out
		SoldierLook.PONYTAIL:
			return [VoxelArt._loft(11, 24.5, [[3.0, 1.0, 1.0], [8.0, 2.2, 2.0], [14.0, 2.2, 2.2], [16.0, 1.6, 1.6]], C.HAIR, 0.6),
				VoxelArt._fb(9.5, 15.0, 22.5, 12.5, 16.0, 26.0, C.PAD)]
	return []  # a pixie cut: the shell alone


## An eye (EYE_COLS x EYE_ROWS x 2 voxels of 0.5 cm, front at EYE_Z): `state` "c" shut, "h" half
## shut, or two digits, the gaze across (0 left, 1 ahead, 2 right; as the soldier sees) and up
## (0 down, 1 level, 2 up). `female`: lashes at the lids' outer corners.
static func eye(state: String, female: bool) -> Dictionary:
	var C := VoxelArt.C
	var boxes := []
	var w := EYE_COLS
	var h := EYE_ROWS
	if state == "c":
		boxes.append(VoxelArt._b(0, 0, 0, w, h, 2, C.SKIN_SHADE))  # the lid
		boxes.append(VoxelArt._b(0, 0, 0, w, 1, 1, C.LASH))         # the lashes along its edge
		boxes.append(VoxelArt._b(0, 1, 0, w, h, 1, C.SKIN))
		return {"size": Vector3i(w, h, 2), "voxel": VoxelArt.FINE_VOXEL, "boxes": boxes}
	boxes.append(VoxelArt._b(0, 0, 1, w, h, 2, C.EYE_WHITE))
	var gx := 1
	var gy := 1
	if state.length() == 2:
		gx = clampi(state.substr(0, 1).to_int(), 0, 2)
		gy = clampi(state.substr(1, 1).to_int(), 0, 2)
	var ix := 2 + (gx - 1)  # the iris's first column
	var iy0 := 0 if gy == 0 else (1 if gy == 2 else 0)
	var iy1 := 2 if gy == 0 else 3
	boxes.append(VoxelArt._b(ix, iy0, 1, ix + IRIS_COLS, iy1, 2, C.IRIS))
	boxes.append(VoxelArt._b(ix + 1, 1, 1, ix + 2, 2, 2, C.PUPIL))
	# The upper lid's edge over the top row (looking down it comes down further), the corners'
	# shadow, and a woman's lashes standing out at the outer corners.
	boxes.append(VoxelArt._b(0, h - 1, 0, w, h, 1, C.SKIN_SHADE))
	boxes.append(VoxelArt._b(1, h - 1, 0, w - 1, h, 1, C.LASH))
	if state == "h" or gy == 0:
		boxes.append(VoxelArt._b(0, h - 2, 0, w, h - 1, 1, C.SKIN_SHADE))
	if state == "h":
		boxes.append(VoxelArt._b(0, 0, 0, w, 1, 1, C.SKIN_SHADE))
	boxes.append(VoxelArt._b(0, 0, 1, 1, h, 2, C.SKIN_SHADE))
	boxes.append(VoxelArt._b(w - 1, 0, 1, w, h, 2, C.SKIN_SHADE))
	if female:
		boxes.append(VoxelArt._b(0, h - 1, 0, 2, h, 1, C.LASH))
		boxes.append(VoxelArt._b(w - 2, h - 1, 0, w, h, 1, C.LASH))
	return {"size": Vector3i(w, h, 2), "voxel": VoxelArt.FINE_VOXEL, "boxes": boxes}


## The mouth in its slot (MOUTH_X, MOUTH_Y; 0.5 cm voxels from MOUTH_Z back to MOUTH_BACK) for
## `expression` (EXPRESSIONS), on the face `digits` describes: the skin round the lips follows
## the face's surface (front_z) and the beard on it, so the slot's edges don't show.
static func mouth(expression: int, digits: String, female: bool) -> Dictionary:
	var p := shape_of(digits, female)
	var C := VoxelArt.C
	var cols := int((MOUTH_X.y - MOUTH_X.x) * 2.0)
	var rows := int((MOUTH_Y.y - MOUTH_Y.x) * 2.0)
	var depth := int((MOUTH_BACK - MOUTH_Z) * 2.0)
	var boxes := []
	# The lips' rows (0 at the slot's bottom), by expression: [lower lip from, to; the parting
	# from, to (open mouth: dark, the teeth's rows at its top); upper lip from, to], and how far
	# in from each side the lips reach (half columns of the slot's 10).
	var lips: Dictionary = {
		NEUTRAL: {"lower": [3, 4], "gap": [4, 5], "upper": [5, 6], "in": 2},
		STRAIN: {"lower": [3, 4], "gap": [4, 5], "upper": [5, 6], "in": 1, "teeth": [4, 5]},
		SHOUT: {"lower": [0, 1], "gap": [1, 5], "upper": [5, 6], "in": 2, "teeth": [4, 5]},
		SLACK: {"lower": [2, 3], "gap": [3, 5], "upper": [5, 6], "in": 2},
	}[expression]
	if female:
		lips.lower = [maxi(int(lips.lower[0]) - 1, 0), lips.lower[1]]  # fuller lips
	for cx in cols:
		for cy in rows:
			var xc := MOUTH_X.x + cx * 0.5 + 0.25
			var yc := MOUTH_Y.x + cy * 0.5 + 0.25
			var z := front_z(xc, yc, p)
			var colour := C.SKIN
			var b := beard_at(xc, yc, z, int(p.beard))
			if b == 2:
				colour = C.HAIR
				z -= beard_depth(int(p.beard), yc)
			elif b == 1:
				colour = C.STUBBLE
			var edge := mini(cx, cols - 1 - cx)  # columns in from the slot's side
			var inner: int = lips.in
			var corner := edge == inner
			if edge >= inner:
				if cy >= int(lips.lower[0]) and cy < int(lips.lower[1]):
					colour = C.LIP_SHADE if corner else C.LIP
					z = 2.0 if not corner else 2.5
				elif cy >= int(lips.gap[0]) and cy < int(lips.gap[1]):
					var open := int(lips.gap[1]) - int(lips.gap[0]) > 1
					colour = C.MOUTH if open or expression != NEUTRAL else C.LIP_SHADE
					z = 3.0 if open else 2.5
					if lips.has("teeth") and cy >= int(lips.teeth[0]) and cy < int(lips.teeth[1]) and not corner:
						colour = C.TEETH
				elif cy >= int(lips.upper[0]) and cy < int(lips.upper[1]):
					colour = C.LIP if cy == int(lips.upper[0]) and not corner else C.LIP_SHADE
					z = 2.0 if not corner else 2.5
					if b == 2:  # a moustache over the upper lip
						colour = C.HAIR
						z = minf(z, front_z(xc, yc, p) - beard_depth(int(p.beard), yc))
			z = clampf(roundf(z * 2.0) * 0.5, MOUTH_Z, MOUTH_BACK - 0.5)
			var z0 := int((z - MOUTH_Z) * 2.0)
			boxes.append(VoxelArt._b(cx, cy, z0, cx + 1, cy + 1, depth, colour))
	return {"size": Vector3i(cols, rows, depth), "voxel": VoxelArt.FINE_VOXEL, "boxes": boxes}


## A brow (`side` 0 the soldier's right, on the left as you face him; 1 the other) for
## `expression`, `thick` 0 thin, 1 middling, 2 bushy, on the face `digits` describes: each
## voxel 0.5 cm in front of the brow ridge's surface (front_z), so it lies on it. Its frame is
## BROW_COLS x BROW_ROWS round its eye (EYE_X), from BROW_Y, BROW_DEPTH deep from brow_front().
static func brow(expression: int, thick: int, side: int, digits: String, female: bool) -> Dictionary:
	var p := shape_of(digits, female)
	var C := VoxelArt.C
	var ex: float = EYE_X[side]
	var front := brow_front(digits, female)
	var boxes := []
	for cx in BROW_COLS:
		var xc := ex - BROW_COLS * 0.25 + cx * 0.5 + 0.25
		var inner := (cx if side == 1 else BROW_COLS - 1 - cx) / float(BROW_COLS - 1)  # 0 at the nose end, 1 outer
		# The brow's bottom edge (rows up from BROW_Y, in halves): an arch, lifted or knit.
		var lift := 1.0 + 0.6 * sin(inner * PI * 0.85)
		match expression:
			STRAIN:
				lift -= 0.8 * (1.0 - inner)
			SHOUT:
				lift -= 1.2 * (1.0 - inner) - 0.3 * inner
			SLACK:
				lift -= 0.3 * inner
		if female:
			lift += 0.4
		var rows: int = ([1, 2, 2][thick] as int) - (1 if inner > 0.85 else 0)
		if female:
			rows = 1
		var y0 := clampi(roundi(lift), 0, BROW_ROWS - 1)
		for cy in range(y0, mini(y0 + maxi(rows, 1), BROW_ROWS)):
			var yc := BROW_Y + cy * 0.5 + 0.25
			var z := front_z(xc, yc, p)
			if z == INF:
				continue
			var at := int(roundf((z - 0.5 - front) * 2.0))
			if at < 0 or at >= BROW_DEPTH:
				continue
			boxes.append(VoxelArt._b(cx, cy, at, cx + 1, cy + 1, at + 1, C.HAIR))
	return {"size": Vector3i(BROW_COLS, BROW_ROWS, BROW_DEPTH), "voxel": VoxelArt.FINE_VOXEL, "boxes": boxes}


## Brow models reach this many 0.5 cm voxels back from brow_front.
const BROW_DEPTH := 12


## How far back (cm) a brow model's front is on the face `digits` describes: just in front of
## the brow ridge's foremost point.
static func brow_front(digits: String, female: bool) -> float:
	var p := shape_of(digits, female)
	var z := INF
	for ex in EYE_X:
		for dx in [-1.0, 0.0, 1.0]:
			z = minf(z, front_z(ex + dx, BROW_Y + 0.75, p))
	return roundf((z - 0.5) * 2.0) * 0.5


## Where each moving part's model sits in the head's mesh (built 0.5 cm voxels from the head
## frame's corner, as VoxelArt meshes it): "eye_l", "eye_r" (EYE_X[0], [1]), "mouth", "brow_l",
## "brow_r".
static func feature_origins(digits: String, female: bool) -> Dictionary:
	var front := brow_front(digits, female)
	var out := {"mouth": Vector3(MOUTH_X.x, MOUTH_Y.x, MOUTH_Z) * 2.0}
	for i in 2:
		var ex: float = EYE_X[i]
		var tag := "_l" if i == 0 else "_r"
		out["eye" + tag] = Vector3(ex - EYE_W * 0.5, EYE_Y, EYE_Z) * 2.0
		out["brow" + tag] = Vector3(ex - BROW_COLS * 0.25, BROW_Y, front) * 2.0
	return out


## The feature models for a face (FaceRig swaps among them): the eye in `eye_state` (eye()),
## the mouth and brows in `expression`, brows `thick`.
static func feature_models(digits: String, female: bool, eye_state: String, expression: int, thick: int) -> Dictionary:
	var f := "f" if female else "m"
	return {"eye_l": "eye:%s:%s" % [eye_state, f], "eye_r": "eye:%s:%s" % [eye_state, f],
		"mouth": "mouth:%d:%s:%s" % [expression, digits, f],
		"brow_l": "brow:%d:%d:0:%s:%s" % [expression, thick, digits, f],
		"brow_r": "brow:%d:%d:1:%s:%s" % [expression, thick, digits, f]}
