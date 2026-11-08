class_name VehicleArtFoes
extends RefCounted
## Combined arms D6a (cg_brief queue item 4.1; docs/combined_arms.md 7.2): the opposing side's
## armour and the trucks, built like every other VehicleArt model: voxel canvases drawn in
## metres from the real vehicle's dimensions (x centred, y up from the ground, z back from the
## nose of the canvas; in the game front is -Z and the origin is the middle of the footprint).
## T-72B3, BMP-2, BTR-82A, MT-LB, the HEMTT in three bodies (M977 cargo, M978 tanker, the
## ammunition truck), the Kestrel rhino truck, the armoured SUV and the captured MaxxPro.
##
## VehicleArt.MODELS and VehicleArt._shape_for name them; VehicleTurret.split lifts the turrets
## and guns out by the numbers in data/vehicle_weapons.json and data/vehicles.json. Every tile
## group in data/vehicle_armour.json (the Kontakt-5 and Kontakt-1 bricks, the slat) is drawn inside
## its data box. The colours are VehicleArt.P's and the paint comes from VehicleArt.SCHEMES.

const P = VehicleArt.P
const Canvas = VehicleArt.Canvas
const Section = VehicleArt.Section


## The canvas of `model`, or null for one this file doesn't draw.
static func shape(model: String) -> Canvas:
	match model:
		"t72b3": return _t72b3()
		"bmp2": return _bmp2()
		"btr82a": return _btr82a()
		"mtlb": return _mtlb()
		"hemtt_cargo": return _hemtt("cargo")
		"m978": return _hemtt("tanker")
		"hemtt_ammo": return _hemtt("ammo")
		"kestrel_rhino": return _rhino()
		"armoured_suv": return _suv()
		"maxxpro_captured": return _captured_maxxpro()
	return null


# --- Shared bits ---------------------------------------------------------------------------

## A rank of Soviet-pattern smoke dischargers (902B): `n` tubes side by side on a bracket.
static func _smoke_rank(c: Canvas, x: float, y: float, z: float, n: int, dir: float) -> void:
	c.mbox(x - 0.1 * n * 0.5, y - 0.05, z, x + 0.1 * n * 0.5, y + 0.14, z + 0.08, P.PAINT_DARK)
	for k in n:
		var tx := x + (k - (n - 1) * 0.5) * 0.1
		c.mbar(Vector3(tx, y + 0.04, z), Vector3(tx + dir * 0.02, y + 0.12, z - 0.22), 0.07, P.PAINT_DARK)
		c.mbox(tx - 0.025, y + 0.1, z - 0.25, tx + 0.025, y + 0.15, z - 0.22, P.BLACK)


## A small explosive brick: a body with a darker edge along its top and a bolt on its face.
static func _brick(c: Canvas, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
	c.mbox(x0, y0, z0, x1, y1, z1, P.PAINT_LIGHT)
	c.mskin(x0, y1 - 0.05, z0, x1, y1 + 0.01, z1, P.PAINT_DARK, P.PAINT_LIGHT)


## Road wheel spacers and a skirt panel along one side of a tracked hull.
static func _skirt(c: Canvas, side: float, x: float, thick: float, y0: float, y1: float, z0: float, z1: float, colour: int) -> void:
	c.mbox(minf(side * x, side * (x + thick)), y0, z0, maxf(side * x, side * (x + thick)), y1, z1, colour)


## A truck cab's mirror on its arm.
static func _mirror(c: Canvas, side: float, x: float, y: float, z: float) -> void:
	c.mbar(Vector3(side * x, y, z + 0.05), Vector3(side * (x + 0.3), y + 0.05, z - 0.1), 0.04, P.METAL)
	c.mbox(minf(side * (x + 0.26), side * (x + 0.36)), y - 0.25, z - 0.2, maxf(side * (x + 0.26), side * (x + 0.36)), y + 0.3, z - 0.05, P.BLACK)


# --- T-72B3 --------------------------------------------------------------------------------

## T-72B3: 6.86 m hull (9.53 m gun forward) on six road wheels a side with the sprocket at the
## back and three return rollers, a long shallow glacis with the V splash plate, the driver
## centred under the gun; the rounded cast turret low on its ring, the 2A46M-5 with its bore
## evacuator; Kontakt-5 wedges in a horseshoe round the front of the turret and on the glacis
## (the "k5_*" tile groups), Kontakt-1 bricks on the skirts' front half ("k1_skirt_*"), the
## Sosna-U sight head, the commander's cupola with its 12.7 mm, smoke dischargers, stowage bins
## and the unditching log and fuel drums on the back.
static func _t72b3() -> Canvas:
	var c := Canvas.new(Vector3i(78, 64, 192), 0.05)
	var hz := 2.68  # the hull starts here; the gun reaches the front of the canvas
	VehicleArt._mtracks(c, 1.1, 1.69, hz + 0.1, hz + 6.75, 6, 0.375, false, 3)
	var z := 0.0
	while z < 6.86:
		var top := 1.35 if z > 1.85 else lerpf(0.9, 1.35, z / 1.85)
		var bottom := 0.47 if z > 0.55 else lerpf(0.9, 0.47, z / 0.55)
		if z > 6.5:
			bottom = lerpf(0.47, 0.85, (z - 6.5) / 0.36)
		c.mbox(-1.08, bottom, hz + z, 1.08, minf(top, 0.98), hz + z + c.vs, P.PAINT)
		c.mbox(-1.62, maxf(bottom, 0.95), hz + z, 1.62, maxf(top, 0.96), hz + z + c.vs, P.PAINT)
		z += c.vs
	# Glacis: the V splash plate, the driver's hatch and periscope, tow hooks, headlights.
	for i in 11:
		var along := i * 0.06
		c.mbox(-0.9 + along, 1.14 + i * 0.02, hz + 1.25 - along * 0.55, -0.72 + along, 1.2 + i * 0.02, hz + 1.3 - along * 0.55, P.PAINT_DARK)
		c.mbox(0.72 - along, 1.14 + i * 0.02, hz + 1.25 - along * 0.55, 0.9 - along, 1.2 + i * 0.02, hz + 1.3 - along * 0.55, P.PAINT_DARK)
	c.mdisc(0.0, hz + 1.72, 0.3, 1.26, 1.36, P.PAINT_DARK)
	c.mskin(-0.14, 1.26, hz + 1.38, 0.14, 1.35, hz + 1.5, P.GLASS)
	c.mskin(-1.62, 0.92, hz, 1.62, 1.0, hz + 0.08, P.PAINT_DARK, P.PAINT)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 0.95 - 0.08, 0.55, hz + 0.28, side * 0.95 + 0.08, 0.72, hz + 0.42, P.METAL)  # tow hook
		c.mbox(side * 1.28 - 0.1, 1.08, hz + 0.3, side * 1.28 + 0.1, 1.2, hz + 0.42, P.PAINT_DARK)  # headlight
		c.mskin(side * 1.28 - 0.08, 1.1, hz + 0.28, side * 1.28 + 0.08, 1.18, hz + 0.33, P.PAINT_LIGHT)
		# Fenders over the tracks, the rubber skirt under them, Kontakt-1 on its front half.
		c.mbox(minf(side * 1.6, side * 1.8), 1.02, hz + 0.08, maxf(side * 1.6, side * 1.8), 1.08, hz + 6.8, P.PAINT)
		_skirt(c, side, 1.74, 0.04, 0.6, 1.04, hz + 0.4, hz + 6.6, P.PAINT_DARK)
		var bz := 0.5
		while bz < 3.4:
			_brick(c, minf(side * 1.78, side * 1.88), 0.66, hz + bz, maxf(side * 1.78, side * 1.88), 1.0, hz + bz + 0.34)
			bz += 0.42
		# Stowage bins on the fender (right) and the jettisonable drums at the back.
		c.mbox(minf(side * 1.2, side * 1.66), 1.08, hz + 3.0, maxf(side * 1.2, side * 1.66), 1.34, hz + 4.4, P.PAINT_DARK)
		c.mskin(minf(side * 1.2, side * 1.66), 1.3, hz + 3.0, maxf(side * 1.2, side * 1.66), 1.35, hz + 3.05, P.BLACK, P.PAINT_DARK)
		c.mbox(minf(side * 1.2, side * 1.66), 1.08, hz + 4.6, maxf(side * 1.2, side * 1.66), 1.3, hz + 5.8, P.PAINT)
		c.mbox(side * 1.45 - 0.1, 1.0, hz + 6.86, side * 1.45 + 0.1, 1.15, hz + 6.9, P.LIGHT_RED)
	# Engine deck: the raised grille, the exhaust on the left, the log across the back.
	c.mbox(-1.3, 1.33, hz + 4.6, 1.3, 1.36, hz + 6.6, P.PAINT_DARK)
	var gx := -1.25
	while gx < 1.25:
		c.mbox(gx, 1.35, hz + 4.7, gx + 0.05, 1.36, hz + 6.5, P.BLACK)
		gx += 0.14
	c.mbox(-1.66, 0.98, hz + 4.0, -1.5, 1.2, hz + 4.3, P.BLACK)
	for lx: float in [-1.55, 1.45]:
		c.mbox(lx, 1.2, hz + 6.45, lx + 0.1, 1.4, hz + 6.75, P.METAL)
	c.mbox(-1.5, 1.4, hz + 6.5, 1.5, 1.6, hz + 6.72, P.RUST)
	for dx: float in [-0.75, 0.0, 0.75]:
		var drum := func(_z: float) -> Vector4: return Vector4(dx, 1.0, 0.27, 0.27)
		c.mloft(hz + 6.75, hz + 6.86, drum, P.PAINT_DARK, 2.0)
	# The cast turret: low and rounded, widest at the ring.
	var tz := hz + 2.75
	var y := 1.36
	while y < 2.1:
		var t := (y - 1.36) / 0.74
		var r := lerpf(1.16, 0.74, t * t)
		c.mdisc(0.0, tz + 0.08, r, y, y + c.vs, P.PAINT)
		y += c.vs
	c.mskin(-1.2, 1.36, tz - 1.2, 1.2, 1.42, tz + 1.3, P.PAINT_DARK, P.PAINT)
	# Mantlet and the coax's port on the right of the gun.
	c.mbox(-0.3, 1.58, tz - 1.2, 0.3, 2.04, tz - 0.9, P.PAINT_DARK)
	c.mbox(0.28, 1.78, tz - 1.21, 0.36, 1.86, tz - 1.18, P.BLACK)
	# 125 mm 2A46M-5: muzzle, tube with thermal shroud bands, bore evacuator.
	var tube := func(gz: float) -> Vector4:
		var rr := 0.095
		if gz < 0.25:
			rr = 0.11
		elif gz > 1.75 and gz < 2.5:
			rr = 0.155
		return Vector4(0.0, 1.82, rr, rr)
	c.mloft(0.0, tz - 1.15, tube, P.PAINT, 2.0)
	for band: float in [0.6, 1.2, 2.9, 3.4]:
		var ring := func(_z: float) -> Vector4: return Vector4(0.0, 1.82, 0.105, 0.105)
		c.mloft(band, band + 0.05, ring, P.PAINT_DARK, 2.0)
	# Kontakt-5: the wedges round the front of the turret either side of the gun.
	for a: float in [-52.0, -41.0, -30.0, -19.0, 19.0, 30.0, 41.0, 52.0]:
		var ax := sin(deg_to_rad(a)) * 1.24
		var az := tz + 0.08 - cos(deg_to_rad(a)) * 1.24
		_brick(c, ax - 0.13, 1.5, az - 0.13, ax + 0.13, 2.02, az + 0.17)
		_brick(c, ax - 0.13, 2.02, az + 0.14, ax + 0.13, 2.14, az + 0.5)  # the roof row
	# Kontakt-5 on the glacis: two rows of slabs.
	for row in 2:
		for i in 6:
			var bx := -1.3 + i * 0.44 + (0.22 if i >= 3 else 0.0) - 0.11
			var ly := 1.0 + row * 0.17
			var lz := hz + 0.42 + row * 0.62
			_brick(c, bx, ly, lz, bx + 0.38, ly + 0.12, lz + 0.52)
	# Roof: the gunner's Sosna-U head, the commander's cupola on the right with its 12.7 mm, the
	# gunner's hatch, smoke dischargers, the wind sensor and the antenna.
	c.mbox(-0.72, 2.02, tz - 0.68, -0.3, 2.34, tz - 0.3, P.PAINT)
	c.mskin(-0.66, 2.08, tz - 0.71, -0.36, 2.28, tz - 0.62, P.GLASS)
	c.mdisc(-0.5, tz + 0.55, 0.34, 2.06, 2.14, P.PAINT_DARK)
	c.mdisc(0.5, tz + 0.48, 0.42, 2.06, 2.24, P.PAINT)
	c.mdisc(0.5, tz + 0.48, 0.3, 2.24, 2.3, P.PAINT_DARK)
	c.mskin(0.2, 2.1, tz + 0.05, 0.8, 2.22, tz + 0.12, P.GLASS)
	c.mbar(Vector3(0.5, 2.3, tz + 0.5), Vector3(0.5, 2.5, tz + 0.5), 0.08, P.METAL)
	c.mbox(0.42, 2.46, tz - 0.1, 0.58, 2.6, tz + 0.52, P.GUN)  # NSVT receiver
	c.mbox(0.47, 2.5, tz - 0.95, 0.53, 2.56, tz - 0.1, P.GUN)  # barrel
	c.mbox(0.45, 2.48, tz - 1.0, 0.55, 2.58, tz - 0.92, P.GUN)  # muzzle brake
	c.mbox(0.58, 2.42, tz + 0.05, 0.76, 2.58, tz + 0.35, P.SEAT)  # ammo can
	c.mbar(Vector3(-0.15, 2.1, tz + 0.7), Vector3(-0.15, 2.7, tz + 0.7), 0.03, P.METAL)
	c.mbar(Vector3(0.0, 2.1, tz + 0.75), Vector3(0.0, 3.05, tz + 0.75), 0.025, P.METAL)
	for side: float in [-1.0, 1.0]:
		_smoke_rank(c, side * 0.98, 1.72, tz - 0.3, 4, side)
		# Stowage on the turret's flanks and a tarpaulin roll behind it.
		c.mbox(minf(side * 0.94, side * 1.24), 1.6, tz + 0.65, maxf(side * 0.94, side * 1.24), 1.95, tz + 1.15, P.PAINT_DARK)
	c.mbox(-0.8, 1.5, tz + 1.1, 0.8, 1.85, tz + 1.42, P.SEAT)
	return c


# --- BMP-2 ---------------------------------------------------------------------------------

## BMP-2: 6.73 m low hull with the ribbed bow rising to the driver's hatch front left and the
## engine front right, six small road wheels a side on the front-sprocket track, the conical
## two-man turret mid-hull with the long thin 2A42 and the Konkurs-M tube on its roof, the roof
## hatches over the troops, firing ports, and the two rear doors that hold the fuel.
static func _bmp2() -> Canvas:
	var c := Canvas.new(Vector3i(66, 60, 150), 0.05)
	var hz := 0.7
	VehicleArt._mtracks(c, 1.13, 1.42, hz + 0.1, hz + 6.6, 6, 0.3, true, 3)
	var z := 0.0
	while z < 6.73:
		var top := 1.72 if z > 1.75 else lerpf(0.86, 1.72, z / 1.75)
		var bottom := 0.42 if z > 0.45 else lerpf(0.85, 0.42, z / 0.45)
		if z > 6.45:
			bottom = lerpf(0.42, 0.7, (z - 6.45) / 0.28)
		c.mbox(-1.1, bottom, hz + z, 1.1, minf(top, 0.9), hz + z + c.vs, P.PAINT)
		c.mbox(-1.5, maxf(bottom, 0.86), hz + z, 1.5, maxf(top, 0.88), hz + z + c.vs, P.PAINT)
		z += c.vs
	# The ribbed bow, driver's hatch and periscopes on the left, the engine grille on the right.
	for r: float in [0.25, 0.55, 0.85]:
		var ry := lerpf(0.86, 1.72, r / 1.75) + 0.02
		c.mbox(-1.45, ry, hz + r, 1.45, ry + 0.07, hz + r + 0.08, P.PAINT_DARK)
	c.mbox(0.3, 1.4, hz + 1.25, 1.42, 1.72, hz + 1.95, P.PAINT_DARK)
	var gx := 0.35
	while gx < 1.4:
		c.mskin(gx, 1.5, hz + 1.25, gx + 0.05, 1.74, hz + 1.95, P.BLACK, P.PAINT_DARK)
		gx += 0.15
	c.mdisc(-0.75, hz + 1.8, 0.3, 1.68, 1.72, P.PAINT_DARK)
	c.mskin(-1.02, 1.5, hz + 1.42, -0.48, 1.66, hz + 1.5, P.GLASS)
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 1.1 - 0.07, 0.65, hz + 0.25, side * 1.1 + 0.07, 0.8, hz + 0.35, P.METAL)
		c.mbox(side * 1.3 - 0.09, 1.1, hz + 0.75, side * 1.3 + 0.09, 1.2, hz + 0.85, P.PAINT_DARK)  # headlight
		c.mskin(side * 1.3 - 0.07, 1.12, hz + 0.72, side * 1.3 + 0.07, 1.18, hz + 0.77, P.PAINT_LIGHT)
		# Fender, thin skirt, troop firing ports along the side.
		c.mbox(minf(side * 1.46, side * 1.56), 0.84, hz + 0.25, maxf(side * 1.46, side * 1.56), 0.9, hz + 6.6, P.PAINT)
		_skirt(c, side, 1.54, 0.03, 0.56, 0.86, hz + 0.45, hz + 6.2, P.PAINT_DARK)
		for pz: float in [3.0, 3.75, 4.5, 5.25]:
			c.mbox(minf(side * 1.48, side * 1.54), 1.2, hz + pz, maxf(side * 1.48, side * 1.54), 1.42, hz + pz + 0.22, P.PAINT_DARK)
			c.mskin(minf(side * 1.5, side * 1.54), 1.25, hz + pz + 0.05, maxf(side * 1.5, side * 1.54), 1.37, hz + pz + 0.16, P.BLACK)
		c.mbox(side * 1.2 - 0.07, 1.4, hz + 6.72, side * 1.2 + 0.07, 1.5, hz + 6.76, P.LIGHT_RED)
		# Roof hatches over the troops (two a side).
		c.mskin(minf(side * 0.3, side * 1.2), 1.7, hz + 3.95, maxf(side * 0.3, side * 1.2), 1.74, hz + 4.7, P.PAINT_DARK, P.PAINT)
		c.mskin(minf(side * 0.3, side * 1.2), 1.7, hz + 4.85, maxf(side * 0.3, side * 1.2), 1.74, hz + 5.6, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 0.2, side * 1.1), 1.72, hz + 4.05, maxf(side * 0.2, side * 1.1), 1.76, hz + 4.6, P.PAINT)
		c.mbox(minf(side * 0.2, side * 1.1), 1.72, hz + 4.95, maxf(side * 0.2, side * 1.1), 1.76, hz + 5.5, P.PAINT)
		# The rear door, its fuel bulge and its window port.
		c.mbox(minf(side * 0.06, side * 0.9), 0.62, hz + 6.73, maxf(side * 0.06, side * 0.9), 1.6, hz + 6.85, P.PAINT)
		c.mskin(minf(side * 0.3, side * 0.7), 1.3, hz + 6.8, maxf(side * 0.3, side * 0.7), 1.45, hz + 6.87, P.GLASS)
		c.mbox(minf(side * 0.74, side * 0.82), 1.05, hz + 6.84, maxf(side * 0.74, side * 0.82), 1.2, hz + 6.9, P.METAL)
	c.mskin(-0.06, 0.62, hz + 6.72, 0.06, 1.6, hz + 6.87, P.PAINT_DARK)
	# The conical turret: gunner left, commander right, the 2A42 in its mantlet.
	var tz := hz + 2.7
	var y := 1.72
	while y < 2.32:
		var t := (y - 1.72) / 0.6
		c.mdisc(0.0, tz, lerpf(0.96, 0.62, t), y, y + c.vs, P.PAINT)
		y += c.vs
	c.mbox(-0.22, 1.88, tz - 0.98, 0.22, 2.18, tz - 0.68, P.PAINT_DARK)
	# The barrel: a thin 30 mm tube, the double-baffle muzzle, the recoil sleeve at the mantlet.
	var tube := func(gz: float) -> Vector4:
		var rr := 0.038
		if gz < 0.28:
			rr = 0.062
		elif gz > tz - 1.65:
			rr = 0.08
		return Vector4(0.0, 2.05, rr, rr)
	c.mloft(0.0, tz - 0.9, tube, P.GUN, 2.0)
	c.mbox(0.18, 1.98, tz - 1.03, 0.24, 2.04, tz - 0.95, P.BLACK)  # the coax's port
	# Roof: gunner's BPK sight, commander's cupola, the Konkurs-M on its rail, smoke, antenna.
	c.mbox(-0.48, 2.3, tz - 0.42, -0.1, 2.5, tz - 0.05, P.PAINT)
	c.mskin(-0.44, 2.34, tz - 0.45, -0.14, 2.46, tz - 0.38, P.GLASS)
	c.mdisc(0.38, tz + 0.2, 0.3, 2.3, 2.42, P.PAINT_DARK)
	c.mskin(0.15, 2.32, tz - 0.12, 0.6, 2.42, tz - 0.05, P.GLASS)
	c.mbox(-0.1, 2.32, tz - 0.3, 0.1, 2.42, tz + 0.1, P.METAL)
	var pod := func(_z: float) -> Vector4: return Vector4(0.0, 2.52, 0.085, 0.085)
	c.mloft(tz - 0.6, tz + 0.65, pod, P.PAINT_DARK, 2.0)
	c.mbox(-0.09, 2.44, tz + 0.6, 0.09, 2.6, tz + 0.66, P.BLACK)
	c.mbar(Vector3(-0.62, 2.32, tz + 0.55), Vector3(-0.62, 3.0, tz + 0.55), 0.025, P.METAL)
	for side: float in [-1.0, 1.0]:
		_smoke_rank(c, side * 0.6, 2.0, tz - 0.32, 3, side)
	return c


# --- BTR-82A -------------------------------------------------------------------------------

## BTR-82A: 7.65 m eight-wheeled boat hull, lower sides leaning out and upper sides leaning in
## under the wide deck, the sharp bow with the driver's and commander's armoured screens, the
## one-man turret with the 2A72 and its long recoil sleeve, the side doors between the second
## and third axles, roof hatches, the engine deck and water-jet flap at the back.
static func _btr82a() -> Canvas:
	var c := Canvas.new(Vector3i(62, 62, 168), 0.05)
	var hz := 0.7
	var lower := func(z: float) -> Section:
		var t := z - hz
		var nose := clampf(t / 1.1, 0.0, 1.0)
		var tail := clampf((7.65 - t) / 0.5, 0.0, 1.0)
		var half := lerpf(0.42, 1.0, minf(nose, tail))
		return Section.new(lerpf(0.9, 0.48, nose), 1.32, half, lerpf(0.75, 1.44, minf(nose, tail)), 0.05, 0.0)
	c.mhull(hz, hz + 7.65, lower, P.PAINT)
	var upper := func(z: float) -> Section:
		var t := z - hz
		var deck := 1.95 if t > 1.6 else lerpf(1.4, 1.95, clampf((t - 0.3) / 1.3, 0.0, 1.0))
		var nose := clampf(t / 1.1, 0.0, 1.0)
		var tail := clampf((7.65 - t) / 0.5, 0.0, 1.0)
		return Section.new(1.3, deck, lerpf(0.75, 1.44, minf(nose, tail)), lerpf(0.62, 1.04, minf(nose, tail)), 0.0, 0.05)
	c.mhull(hz + 0.15, hz + 7.65, upper, P.PAINT)
	# Eight wheels on the outside of the lower hull, their arches and the suspension arms.
	for side: float in [-1.0, 1.0]:
		for wz: float in [1.3, 2.65, 4.175, 5.525]:
			var cz := hz + wz
			c.mbox(minf(side * 0.9, side * 1.3), 1.0, cz - 0.62, maxf(side * 0.9, side * 1.3), 1.24, cz + 0.62, P.PAINT_DARK)
			c.mbar(Vector3(side * 0.7, 0.72, cz), Vector3(side * 1.05, 0.58, cz), 0.1, P.METAL)
			VehicleArt._mtire(c, side, minf(side * 1.03, side * 1.38), maxf(side * 1.03, side * 1.38), 0.55, cz, 0.55)
		# Side door between the second and third axles, its step, firing ports, mirrors of plate.
		var ox := minf(side * 1.1, side * 1.5)
		var ix := maxf(side * 1.1, side * 1.5)
		c.mskin(ox, 0.72, hz + 3.1, ix, 1.8, hz + 3.75, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 1.2, side * 1.44), 0.5, hz + 3.15, maxf(side * 1.2, side * 1.44), 0.56, hz + 3.7, P.METAL)
		for pz: float in [2.0, 2.65, 4.4, 5.1, 5.8]:
			c.mskin(ox, 1.52, hz + pz, ix, 1.66, hz + pz + 0.16, P.BLACK, P.PAINT)
		c.mbox(minf(side * 0.9, side * 1.48), 1.25, hz + 7.4, maxf(side * 0.9, side * 1.48), 1.32, hz + 7.5, P.PAINT_DARK)
		c.mbox(side * 0.95 - 0.1, 1.55, hz + 7.62, side * 0.95 + 0.1, 1.65, hz + 7.66, P.LIGHT_RED)
		# Headlights behind their guards on the bow, the crew's roof hatches.
		c.mbox(side * 0.7 - 0.1, 1.3, hz + 0.65, side * 0.7 + 0.1, 1.42, hz + 0.75, P.PAINT_DARK)
		c.mskin(side * 0.7 - 0.08, 1.32, hz + 0.62, side * 0.7 + 0.08, 1.4, hz + 0.67, P.PAINT_LIGHT)
		c.mdisc(side * 0.5, hz + 1.95, 0.28, 1.9, 1.95, P.PAINT_DARK)
		c.mskin(minf(side * 0.15, side * 0.85), 1.45, hz + 1.25, maxf(side * 0.15, side * 0.85), 1.8, hz + 1.5, P.GLASS)
		c.mskin(minf(side * 0.15, side * 0.85), 1.72, hz + 1.25, maxf(side * 0.15, side * 0.85), 1.82, hz + 1.5, P.PAINT_DARK)
		c.mskin(minf(side * 0.3, side * 0.95), 1.93, hz + 3.6, maxf(side * 0.3, side * 0.95), 1.97, hz + 4.4, P.PAINT_DARK, P.PAINT)
	# The nose's tow eye and splash board; the engine deck's grilles; the water-jet flap.
	c.mbox(-0.4, 1.02, hz + 0.25, 0.4, 1.1, hz + 0.35, P.PAINT_DARK)
	c.mbox(-0.08, 0.72, hz + 0.1, 0.08, 0.86, hz + 0.25, P.METAL)
	c.mbox(-0.85, 1.93, hz + 5.5, 0.85, 1.96, hz + 7.3, P.PAINT_DARK)
	var gz := hz + 5.6
	while gz < hz + 7.2:
		c.mbox(-0.8, 1.95, gz, 0.8, 1.97, gz + 0.05, P.BLACK)
		gz += 0.13
	c.mbox(-0.26, 0.7, hz + 7.6, 0.26, 1.15, hz + 7.68, P.PAINT_DARK)
	# The one-man turret: squat cone, the 2A72 on its long sleeve, the coax, sight, smoke, antennas.
	var tz := hz + 2.5
	var y := 1.95
	while y < 2.48:
		var t := (y - 1.95) / 0.53
		c.mdisc(0.0, tz, lerpf(0.76, 0.52, t), y, y + c.vs, P.PAINT)
		y += c.vs
	c.mbox(-0.2, 2.12, tz - 0.78, 0.2, 2.42, tz - 0.5, P.PAINT_DARK)
	var tube := func(bz: float) -> Vector4:
		var rr := 0.04
		if bz < 0.25:
			rr = 0.06
		elif bz > tz - 1.65:
			rr = 0.075
		return Vector4(0.0, 2.28, rr, rr)
	c.mloft(0.0, tz - 0.7, tube, P.GUN, 2.0)
	c.mbox(0.18, 2.22, tz - 0.83, 0.24, 2.28, tz - 0.75, P.BLACK)
	c.mbox(-0.42, 2.48, tz - 0.32, -0.12, 2.68, tz - 0.05, P.PAINT)
	c.mskin(-0.38, 2.52, tz - 0.35, -0.16, 2.64, tz - 0.28, P.GLASS)
	c.mdisc(0.25, tz + 0.2, 0.22, 2.48, 2.56, P.PAINT_DARK)
	c.mbar(Vector3(-0.45, 2.48, tz + 0.3), Vector3(-0.45, 3.0, tz + 0.3), 0.025, P.METAL)
	for side: float in [-1.0, 1.0]:
		_smoke_rank(c, side * 0.62, 2.14, tz - 0.22, 3, side)
		c.mbar(Vector3(side * 0.8, 1.95, hz + 6.9), Vector3(side * 0.8, 2.85, hz + 6.95), 0.025, P.METAL)
	return c


# --- MT-LB ---------------------------------------------------------------------------------

## MT-LB: 6.45 m low flat-topped box on six large road wheels a side with no return rollers and
## the sprocket at the front, the crew cab across the front with its windows and the small
## PKT turret front right, the engine bay behind the driver, four roof hatches over the troops
## and the two big rear doors.
static func _mtlb() -> Canvas:
	var c := Canvas.new(Vector3i(60, 60, 132), 0.05)
	var hz := 0.08
	VehicleArt._mtracks(c, 1.07, 1.42, hz + 0.05, hz + 6.35, 6, 0.31, true, 0)
	var z := 0.0
	while z < 6.45:
		var top := 1.6 if z > 0.75 else lerpf(0.92, 1.6, z / 0.75)
		var bottom := 0.4 if z > 0.35 else lerpf(0.85, 0.4, z / 0.35)
		c.mbox(-1.05, bottom, hz + z, 1.05, minf(top, 0.92), hz + z + c.vs, P.PAINT)
		c.mbox(-1.4, maxf(bottom, 0.88), hz + z, 1.4, maxf(top, 0.9), hz + z + c.vs, P.PAINT)
		z += c.vs
	# Cab front: two glazed hatches with armoured shutters over them, tow hook, headlights.
	for side: float in [-1.0, 1.0]:
		c.mskin(minf(side * 0.25, side * 1.2), 1.2, hz + 0.38, maxf(side * 0.25, side * 1.2), 1.46, hz + 0.72, P.GLASS)
		c.mskin(minf(side * 0.25, side * 1.2), 1.46, hz + 0.6, maxf(side * 0.25, side * 1.2), 1.54, hz + 0.76, P.PAINT_DARK, P.PAINT)
		c.mbox(side * 0.9 - 0.08, 0.6, hz + 0.2, side * 0.9 + 0.08, 0.76, hz + 0.3, P.METAL)
		c.mbox(side * 1.18 - 0.09, 1.05, hz + 0.28, side * 1.18 + 0.09, 1.16, hz + 0.38, P.PAINT_DARK)
		c.mskin(side * 1.18 - 0.07, 1.07, hz + 0.25, side * 1.18 + 0.07, 1.14, hz + 0.3, P.PAINT_LIGHT)
		# Fenders and the thin skirt, stowage.
		c.mbox(minf(side * 1.38, side * 1.44), 0.84, hz + 0.2, maxf(side * 1.38, side * 1.44), 0.9, hz + 6.3, P.PAINT)
		c.mbox(minf(side * 0.7, side * 1.3), 1.6, hz + 4.2, maxf(side * 0.7, side * 1.3), 1.74, hz + 5.5, P.PAINT_DARK)
		# Roof hatches over the troops, rear door with its port and the tail light.
		c.mskin(minf(side * 0.2, side * 1.15), 1.58, hz + 2.6, maxf(side * 0.2, side * 1.15), 1.62, hz + 3.7, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 0.15, side * 1.1), 1.6, hz + 2.7, maxf(side * 0.15, side * 1.1), 1.63, hz + 3.6, P.PAINT)
		c.mbox(minf(side * 0.06, side * 1.0), 0.5, hz + 6.45, maxf(side * 0.06, side * 1.0), 1.5, hz + 6.5, P.PAINT)
		c.mskin(minf(side * 0.35, side * 0.7), 1.1, hz + 6.46, maxf(side * 0.35, side * 0.7), 1.3, hz + 6.52, P.BLACK)
		c.mbox(side * 1.2 - 0.07, 1.35, hz + 6.45, side * 1.2 + 0.07, 1.45, hz + 6.5, P.LIGHT_RED)
		for pz: float in [2.4, 3.3, 4.2, 5.1]:  # firing ports
			c.mskin(minf(side * 1.38, side * 1.42), 1.25, hz + pz, maxf(side * 1.38, side * 1.42), 1.4, hz + pz + 0.18, P.BLACK)
	# Engine bay's grille beside the driver, the driver's cupola.
	c.mbox(-0.7, 1.55, hz + 1.5, 0.7, 1.6, hz + 2.3, P.PAINT_DARK)
	var gx := -0.65
	while gx < 0.65:
		c.mbox(gx, 1.57, hz + 1.55, gx + 0.05, 1.6, hz + 2.25, P.BLACK)
		gx += 0.14
	c.mdisc(-0.65, hz + 0.95, 0.3, 1.6, 1.72, P.PAINT_DARK)
	c.mskin(-0.9, 1.62, hz + 0.65, -0.4, 1.72, hz + 0.72, P.GLASS)
	# PKT turret front right: a small rounded cone with the gun through its face.
	var tx := 0.65
	var tz := hz + 1.05
	var y := 1.6
	while y < 1.92:
		c.mdisc(tx, tz, lerpf(0.42, 0.28, (y - 1.6) / 0.32), y, y + c.vs, P.PAINT)
		y += c.vs
	c.mbox(tx - 0.03, 1.76, tz - 0.92, tx + 0.03, 1.82, tz - 0.3, P.GUN)
	c.mbox(tx - 0.05, 1.74, tz - 0.96, tx + 0.05, 1.84, tz - 0.88, P.GUN)
	c.mbox(tx - 0.12, 1.7, tz - 0.42, tx + 0.12, 1.88, tz - 0.28, P.PAINT_DARK)
	c.mbar(Vector3(-1.0, 1.6, hz + 6.1), Vector3(-1.0, 2.9, hz + 6.15), 0.025, P.METAL)
	return c


# --- HEMTT ---------------------------------------------------------------------------------

## The HEMTT (M977 series): 10.16 m 8x8, the short two-man cab forward over the first axle, the
## tandem front axles, a frame carrying the body, the tandem rear axles. `body`: "cargo" (the M977's
## dropside bed and crane), "tanker" (the M978's 9,500 L tank and its pump pack), or "ammo" (a
## flat bed of ammunition pallets under a load-handling crane).
static func _hemtt(body: String) -> Canvas:
	var c := Canvas.new(Vector3i(62, 72, 208), 0.05)  # (wide enough for the mirrors)
	var hz := 0.12
	# Frame rails and bumper.
	for side: float in [-1.0, 1.0]:
		c.mbox(minf(side * 0.4, side * 0.55), 0.95, hz, maxf(side * 0.4, side * 0.55), 1.2, hz + 9.9, P.BLACK)
	c.mbox(-1.15, 0.8, hz, 1.15, 1.1, hz + 0.2, P.PAINT_DARK)
	c.mbox(-0.42, 1.0, hz + 2.3, 0.42, 1.2, hz + 9.6, P.PAINT_DARK)
	# Eight wheels.
	for side: float in [-1.0, 1.0]:
		for wz: float in [1.35, 2.8, 7.0, 8.45]:
			var cz := hz + wz
			c.mbar(Vector3(side * 0.45, 1.0, cz), Vector3(side * 0.85, 0.65, cz), 0.12, P.METAL)
			VehicleArt._mtire(c, side, minf(side * 0.88, side * 1.22), maxf(side * 0.88, side * 1.22), 0.62, cz, 0.62)
	# The cab: slab sides, big flat screen, roof with its hatch.
	var cab := func(z: float) -> Section:
		var t := z - hz
		var roof := lerpf(2.1, 2.84, clampf((t - 0.15) / 0.6, 0.0, 1.0))
		return Section.new(1.05, roof, 1.14, 1.08, 0.08, 0.1)
	c.mhull(hz + 0.15, hz + 2.3, cab, P.PAINT, 0.08)
	c.mbox(-1.1, 1.05, hz + 0.15, 1.1, 2.12, hz + 0.25, P.PAINT)  # (the shell is open at its ends: close them)
	c.mbox(-1.08, 1.05, hz + 2.22, 1.08, 2.84, hz + 2.3, P.PAINT)
	c.mskin(-1.0, 1.95, hz + 0.1, -0.05, 2.68, hz + 0.7, P.GLASS)
	c.mskin(0.05, 1.95, hz + 0.1, 1.0, 2.68, hz + 0.7, P.GLASS)
	c.mskin(-1.05, 1.3, hz + 0.1, 1.05, 1.7, hz + 0.3, P.BLACK)
	var gx := -1.0
	while gx < 1.0:
		c.mskin(gx, 1.3, hz + 0.1, gx + 0.05, 1.7, hz + 0.3, P.PAINT_DARK, P.BLACK)
		gx += 0.14
	c.mdisc(0.0, hz + 1.5, 0.3, 2.8, 2.88, P.PAINT_DARK)
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 1.0, side * 1.2)
		var ix := maxf(side * 1.0, side * 1.2)
		c.mskin(ox, 1.9, hz + 0.75, ix, 2.5, hz + 1.5, P.GLASS)
		c.mskin(ox, 1.05, hz + 0.68, ix, 2.7, hz + 0.72, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 1.05, hz + 1.68, ix, 2.7, hz + 1.72, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 1.0, side * 1.28), 0.75, hz + 0.9, maxf(side * 1.0, side * 1.28), 0.8, hz + 1.5, P.METAL)  # step
		c.mbox(minf(side * 1.0, side * 1.28), 1.0, hz + 0.9, maxf(side * 1.0, side * 1.28), 1.05, hz + 1.5, P.METAL)
		_mirror(c, side, 1.1, 2.4, hz + 0.75)
		c.mbox(side * 0.88 - 0.1, 1.4, hz + 0.2, side * 0.88 + 0.1, 1.52, hz + 0.24, P.PAINT_LIGHT)  # headlight
		c.mbox(side * 0.8 - 0.06, 1.05, hz + 9.9, side * 0.8 + 0.06, 1.2, hz + 9.94, P.LIGHT_RED)
	# Behind the cab: the exhaust stack, the air intake and the fuel tank on the left of the frame.
	c.mbar(Vector3(0.75, 2.2, hz + 2.32), Vector3(0.75, 3.1, hz + 2.32), 0.09, P.METAL)
	c.mbox(-1.1, 1.25, hz + 2.35, -0.55, 2.3, hz + 3.05, P.PAINT)
	c.mskin(-1.1, 1.3, hz + 2.33, -0.55, 2.25, hz + 2.37, P.PAINT_DARK, P.PAINT)
	var drum := func(_z: float) -> Vector4: return Vector4(0.86, 1.3, 0.3, 0.3)
	c.mloft(hz + 3.2, hz + 4.6, drum, P.PAINT_DARK, 2.0)
	match body:
		"cargo":
			_hemtt_bed(c, hz, true)
			# The folded crane behind the cab, a tarpaulined load.
			c.mbox(-0.2, 1.15, hz + 2.45, 0.2, 2.2, hz + 2.95, P.PAINT_DARK)
			c.mbar(Vector3(0.0, 2.2, hz + 2.7), Vector3(0.0, 2.5, hz + 3.0), 0.16, P.PAINT)
			c.mbar(Vector3(0.0, 2.5, hz + 3.0), Vector3(0.0, 2.3, hz + 6.0), 0.12, P.PAINT)
			c.mbox(-1.0, 1.32, hz + 4.4, 1.0, 2.1, hz + 9.1, P.SEAT)
			c.mskin(-1.02, 2.0, hz + 4.4, 1.02, 2.12, hz + 9.1, P.PAINT_DARK, P.SEAT)
		"tanker":
			c.mbox(-1.05, 1.22, hz + 3.5, 1.05, 1.32, hz + 9.85, P.PAINT_DARK)
			var cistern := func(z: float) -> Vector4:
				var t := z - hz
				var taper := minf(clampf((t - 3.5) / 0.3, 0.0, 1.0), clampf((9.0 - t) / 0.3, 0.0, 1.0))
				return Vector4(0.0, 2.1, lerpf(0.9, 1.15, taper), lerpf(0.65, 0.82, taper))
			c.mloft(hz + 3.5, hz + 9.0, cistern, P.PAINT, 3.2)
			for saddle: float in [3.9, 5.5, 7.1, 8.6]:
				c.mbox(-0.85, 1.3, hz + saddle, 0.85, 1.6, hz + saddle + 0.14, P.PAINT_DARK)
			for ring: float in [4.8, 6.25, 7.7]:
				var hoop := func(_z: float) -> Vector4: return Vector4(0.0, 2.1, 1.17, 0.84)
				c.mloft(hz + ring, hz + ring + 0.08, hoop, P.PAINT_DARK, 3.2)
			c.mdisc(0.0, hz + 5.2, 0.28, 2.88, 3.02, P.PAINT_DARK)
			c.mdisc(0.0, hz + 7.2, 0.28, 2.88, 3.02, P.PAINT_DARK)
			c.mbox(-0.58, 2.88, hz + 3.7, -0.52, 2.98, hz + 8.8, P.METAL)  # catwalk rail
			c.mbox(0.52, 2.88, hz + 3.7, 0.58, 2.98, hz + 8.8, P.METAL)
			# The pump pack at the back: its bay, the reels and the hose.
			c.mbox(-1.12, 1.25, hz + 9.0, 1.12, 2.5, hz + 9.9, P.PAINT)
			c.mskin(-0.9, 1.4, hz + 9.88, 0.9, 2.4, hz + 9.92, P.BLACK)
			for rx: float in [-0.55, 0.55]:
				c.mwheel(rx - 0.18, rx + 0.18, 1.9, hz + 9.45, 0.36, P.TIRE, P.METAL)
				c.mbox(rx - 0.12, 1.5, hz + 9.84, rx + 0.12, 1.6, hz + 9.96, P.METAL)
		"ammo":
			_hemtt_bed(c, hz, false)
			# The crane, and two rows of palletised shell crates chained down.
			c.mbox(-0.22, 1.15, hz + 2.45, 0.22, 2.4, hz + 3.0, P.PAINT_DARK)
			c.mbar(Vector3(0.0, 2.4, hz + 2.7), Vector3(0.0, 3.1, hz + 3.0), 0.18, P.PAINT)
			c.mbar(Vector3(0.0, 3.1, hz + 3.0), Vector3(0.0, 2.6, hz + 6.3), 0.14, P.PAINT)
			c.mbar(Vector3(0.0, 2.6, hz + 6.3), Vector3(0.0, 2.2, hz + 6.3), 0.03, P.METAL)
			var pz := 3.9
			while pz < 9.1:
				for side: float in [-1.0, 1.0]:
					var cx0 := minf(side * 0.08, side * 1.02)
					var cx1 := maxf(side * 0.08, side * 1.02)
					c.mbox(cx0, 1.32, hz + pz, cx1, 1.4, hz + pz + 1.2, P.METAL)  # the pallet
					c.mbox(cx0 + 0.05, 1.4, hz + pz + 0.05, cx1 - 0.05, 2.05, hz + pz + 1.15, P.PAINT_DARK)
					c.mskin(cx0 + 0.05, 1.6, hz + pz + 0.05, cx1 - 0.05, 1.65, hz + pz + 1.15, P.BLACK, P.PAINT_DARK)
					c.mskin(cx0 + 0.05, 1.85, hz + pz + 0.05, cx1 - 0.05, 1.9, hz + pz + 1.15, P.MARKING, P.PAINT_DARK)
				pz += 1.3
	return c


## The flat bed behind the cab; `dropsides`: the M977's folding side and tail boards.
static func _hemtt_bed(c: Canvas, hz: float, dropsides: bool) -> void:
	c.mbox(-1.2, 1.2, hz + 3.5, 1.2, 1.32, hz + 9.9, P.PAINT)
	c.mskin(-1.2, 1.2, hz + 3.5, 1.2, 1.32, hz + 3.55, P.PAINT_DARK, P.PAINT)
	if not dropsides:
		return
	for side: float in [-1.0, 1.0]:
		c.mbox(minf(side * 1.15, side * 1.22), 1.32, hz + 3.5, maxf(side * 1.15, side * 1.22), 2.05, hz + 9.9, P.PAINT)
		var pz := 4.1
		while pz < 9.8:
			c.mskin(minf(side * 1.15, side * 1.23), 1.32, hz + pz, maxf(side * 1.15, side * 1.23), 2.05, hz + pz + 0.05, P.PAINT_DARK, P.PAINT)
			pz += 0.9
	c.mbox(-1.2, 1.32, hz + 9.82, 1.2, 2.05, hz + 9.9, P.PAINT)
	c.mbox(-1.2, 1.32, hz + 3.5, 1.2, 2.05, hz + 3.57, P.PAINT)


# --- Rhino truck ---------------------------------------------------------------------------

## The Kestrel rhino truck: a heavy 6x6 truck with a welded steel wedge over the bonnet, the box
## of scrap and boiler plate along its back with six firing ports a side (three shooters a side
## get one each), narrow slit windows behind armour glass, plated wheel guards and a plated roof
## turret with its M2. Original: no real vehicle's marks.
static func _rhino() -> Canvas:
	var c := Canvas.new(Vector3i(58, 78, 168), 0.05)
	var hz := 0.15
	c.mbox(-0.5, 0.75, hz + 0.3, 0.5, 1.05, hz + 7.9, P.BLACK)
	for side: float in [-1.0, 1.0]:
		for wz: float in [1.5, 5.35, 6.75]:
			var cz := hz + wz
			VehicleArt._mtire(c, side, minf(side * 0.86, side * 1.2), maxf(side * 0.86, side * 1.2), 0.58, cz, 0.58)
		# Plate hung over the tyres, ragged along the bottom.
		for gz: float in [0.8, 4.65, 6.1]:
			c.mbox(minf(side * 1.12, side * 1.22), 0.72, hz + gz, maxf(side * 1.12, side * 1.22), 1.5, hz + gz + 1.3, P.RUST)
			c.mskin(minf(side * 1.12, side * 1.24), 0.72, hz + gz, maxf(side * 1.12, side * 1.24), 0.78, hz + gz + 1.3, P.PAINT_DARK, P.RUST)
	# The wedge over the engine: plates sloping up to the cab, a ram across the front.
	var wedge := func(z: float) -> Section:
		var t := z - hz
		return Section.new(0.8, lerpf(1.25, 2.6, clampf((t - 0.1) / 2.0, 0.0, 1.0)), lerpf(0.82, 1.2, clampf(t / 0.6, 0.0, 1.0)), lerpf(0.5, 1.08, clampf(t / 2.1, 0.0, 1.0)), 0.0, 0.03)
	c.mhull(hz + 0.1, hz + 2.2, wedge, P.PAINT)
	c.mbox(-1.28, 0.62, hz, 1.28, 1.0, hz + 0.22, P.METAL)
	for bx: float in [-0.9, -0.3, 0.3, 0.9]:  # welded ram spikes
		c.mbar(Vector3(bx, 0.85, hz + 0.05), Vector3(bx, 0.85, hz - 0.12), 0.1, P.RUST)
	# The slit screens, bolted-on plates across the wedge, seams and rust patches.
	c.mskin(-0.95, 2.16, hz + 1.62, -0.1, 2.32, hz + 1.86, P.GLASS)
	c.mskin(0.1, 2.16, hz + 1.62, 0.95, 2.32, hz + 1.86, P.GLASS)
	for ry: float in [1.2, 1.55, 1.9]:
		c.mskin(-1.2, ry, hz + 0.1, 1.2, ry + 0.04, hz + 2.2, P.PAINT_DARK, P.PAINT)
	c.mskin(-0.8, 1.3, hz + 0.3, -0.2, 1.7, hz + 1.1, P.RUST, P.PAINT)
	c.mskin(0.3, 1.55, hz + 0.9, 0.95, 2.0, hz + 1.5, P.RUST, P.PAINT)
	# The fighting box: one welded slab over the bed.
	var box := func(_z: float) -> Section:
		return Section.new(1.0, 3.05, 1.2, 1.1, 0.0, 0.04)
	c.mhull(hz + 2.15, hz + 8.0, box, P.PAINT, 0.12)
	c.mbox(-1.1, 2.95, hz + 2.15, 1.1, 3.1, hz + 8.0, P.PAINT)
	c.mbox(-1.1, 1.0, hz + 7.9, 1.1, 3.05, hz + 8.0, P.PAINT)
	c.mskin(-1.26, 1.0, hz + 7.9, 1.26, 3.1, hz + 8.04, P.PAINT_DARK, P.PAINT)
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 1.02, side * 1.3)
		var ix := maxf(side * 1.02, side * 1.3)
		# Six ports a side with their cover plates, the door behind the cab, seam lines.
		var pz := 2.9
		for k in 6:
			c.mskin(ox, 2.05, hz + pz, ix, 2.3, hz + pz + 0.22, P.BLACK)
			c.mskin(ox, 2.3, hz + pz - 0.03, ix, 2.38, hz + pz + 0.25, P.PAINT_DARK, P.PAINT)
			pz += 0.82
		c.mskin(ox, 1.05, hz + 2.4, ix, 2.9, hz + 2.45, P.PAINT_DARK, P.PAINT)
		c.mskin(ox, 1.05, hz + 3.05, ix, 2.9, hz + 3.1, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 1.0, side * 1.28), 0.8, hz + 2.45, maxf(side * 1.0, side * 1.28), 1.02, hz + 3.05, P.METAL)
		c.mskin(ox, 1.4, hz + 3.5, ix, 1.9, hz + 4.6, P.RUST, P.PAINT)
		c.mskin(ox, 2.5, hz + 5.8, ix, 2.85, hz + 7.1, P.RUST, P.PAINT)
		c.mbox(side * 1.0 - 0.06, 1.0, hz + 8.0, side * 1.0 + 0.06, 1.15, hz + 8.04, P.LIGHT_RED)
	# Rear door with its slit, a ladder, the exhaust pipes.
	c.mskin(-0.55, 1.1, hz + 7.98, 0.55, 2.8, hz + 8.04, P.PAINT_DARK, P.PAINT)
	c.mbox(-0.5, 1.15, hz + 8.0, 0.5, 2.75, hz + 8.02, P.PAINT)
	c.mskin(-0.25, 2.3, hz + 7.98, 0.25, 2.45, hz + 8.04, P.GLASS)
	for ly: float in [1.2, 1.6, 2.0, 2.4]:
		c.mbox(0.65, ly, hz + 8.02, 1.05, ly + 0.05, hz + 8.08, P.METAL)
	c.mbar(Vector3(-1.05, 3.1, hz + 7.8), Vector3(-1.05, 4.0, hz + 7.85), 0.03, P.METAL)
	# The plated turret: a hoop of plate with a slit and the M2 through its gap.
	var tz := hz + 4.6
	var y := 3.1
	while y < 3.72:
		c.mdisc(0.0, tz, 0.72, y, y + c.vs, P.PAINT)
		c.mdisc(0.0, tz, 0.64, y, y + c.vs, P.EMPTY)
		y += c.vs
	c.mdisc(0.0, tz, 0.66, 3.1, 3.2, P.PAINT_DARK)
	c.mbox(-0.16, 3.2, tz - 0.76, 0.16, 3.6, tz - 0.6, P.EMPTY)
	c.mskin(-0.32, 3.48, tz - 0.74, -0.2, 3.6, tz - 0.62, P.GLASS)
	c.mskin(0.2, 3.48, tz - 0.74, 0.32, 3.6, tz - 0.62, P.GLASS)
	c.mbar(Vector3(0.0, 3.2, tz - 0.2), Vector3(0.0, 3.4, tz - 0.2), 0.06, P.METAL)
	c.mbox(-0.07, 3.38, tz - 0.55, 0.07, 3.52, tz + 0.1, P.GUN)
	c.mbox(-0.03, 3.43, tz - 1.65, 0.03, 3.48, tz - 0.55, P.GUN)
	c.mbox(-0.05, 3.41, tz - 1.7, 0.05, 3.5, tz - 1.6, P.GUN)
	c.mbox(0.07, 3.32, tz - 0.45, 0.22, 3.5, tz - 0.15, P.SEAT)
	return c


# --- Armoured SUV --------------------------------------------------------------------------

## The armoured SUV (the Saltline Syndicate's, the Kestrels', Vantage's in black): a civilian
## full-size five-door on thick run-flat tyres, the armoured glass tinted dark, reinforced
## door seams and a roof hatch with a pintle MG. Original: no real marks.
static func _suv() -> Canvas:
	var c := Canvas.new(Vector3i(46, 46, 110), 0.05)
	var hz := 0.15
	var body := func(z: float) -> Section:
		var t := z - hz
		var bonnet := clampf(t / 0.5, 0.0, 1.0)
		var top := lerpf(0.95, 1.18, bonnet)
		if t > 1.55:
			top = lerpf(1.18, 1.86, clampf((t - 1.55) / 0.55, 0.0, 1.0))
		if t > 4.75:
			top = lerpf(1.86, 1.72, (t - 4.75) / 0.45)
		return Section.new(0.48, top, lerpf(0.92, 0.98, bonnet), lerpf(0.86, 0.9, clampf(t / 2.2, 0.0, 1.0)), 0.04, 0.14)
	c.mhull(hz, hz + 5.2, body, P.PAINT, 0.08)
	c.mbox(-0.92, 0.48, hz, 0.92, 0.96, hz + 0.08, P.PAINT)  # (the shell is open at its ends: close them)
	c.mbox(-0.86, 0.5, hz + 5.12, 0.86, 1.72, hz + 5.2, P.PAINT)
	# Bumpers, grille, lights.
	c.mbox(-1.0, 0.42, hz - 0.02, 1.0, 0.72, hz + 0.25, P.BLACK)
	c.mskin(-0.72, 0.78, hz, 0.72, 1.02, hz + 0.08, P.BLACK)
	for bx: float in [-0.6, -0.36, -0.12, 0.12, 0.36, 0.6]:
		c.mskin(bx, 0.78, hz, bx + 0.05, 1.02, hz + 0.08, P.METAL, P.BLACK)
	c.mbox(-1.0, 0.45, hz + 5.05, 1.0, 0.68, hz + 5.25, P.BLACK)
	# Glass, all of it tinted: the windscreen, the sides, the tailgate.
	c.mskin(-0.82, 1.27, hz + 1.52, 0.82, 1.78, hz + 2.1, P.GLASS)
	c.mskin(-0.74, 1.3, hz + 5.05, 0.74, 1.66, hz + 5.2, P.GLASS)
	for side: float in [-1.0, 1.0]:
		var ox := minf(side * 0.74, side * 0.98)
		var ix := maxf(side * 0.74, side * 0.98)
		c.mskin(ox, 1.3, hz + 2.1, ix, 1.74, hz + 2.95, P.GLASS)
		c.mskin(ox, 1.3, hz + 3.05, ix, 1.74, hz + 3.85, P.GLASS)
		c.mskin(ox, 1.3, hz + 3.95, ix, 1.7, hz + 4.8, P.GLASS)
		for dz: float in [2.0, 2.98, 3.9]:
			c.mskin(ox, 0.52, hz + dz, ix, 1.76, hz + dz + 0.05, P.PAINT_DARK, P.PAINT)
		c.mbox(minf(side * 0.92, side * 1.0), 1.0, hz + 2.75, maxf(side * 0.92, side * 1.0), 1.06, hz + 2.92, P.METAL)
		c.mbox(minf(side * 0.92, side * 1.0), 1.0, hz + 3.7, maxf(side * 0.92, side * 1.0), 1.06, hz + 3.87, P.METAL)
		c.mbox(minf(side * 0.9, side * 1.02), 0.55, hz + 2.1, maxf(side * 0.9, side * 1.02), 0.6, hz + 3.9, P.METAL)  # running board
		_mirror(c, side, 0.88, 1.4, hz + 1.85)
		c.mbox(side * 0.72 - 0.15, 0.86, hz + 0.02, side * 0.72 + 0.15, 1.02, hz + 0.08, P.PAINT_LIGHT)  # headlight
		c.mbox(side * 0.78 - 0.08, 1.05, hz + 5.15, side * 0.78 + 0.08, 1.3, hz + 5.22, P.LIGHT_RED)
		c.mskin(minf(side * 0.74, side * 1.0), 0.45, hz + 0.0, maxf(side * 0.74, side * 1.0), 1.25, hz + 5.2, P.PAINT_DARK, P.TIRE)
		for wz: float in [1.05, 4.2]:
			VehicleArt._mtire(c, side, minf(side * 0.72, side * 1.02), maxf(side * 0.72, side * 1.02), 0.4, hz + wz, 0.4)
	# Roof: the rails, the hatch and its ring, the pintle gun.
	for side: float in [-1.0, 1.0]:
		c.mbox(side * 0.72 - 0.03, 1.84, hz + 2.3, side * 0.72 + 0.03, 1.9, hz + 4.6, P.METAL)
	var tz := hz + 3.2
	c.mdisc(0.0, tz, 0.42, 1.8, 1.92, P.PAINT_DARK)
	c.mbar(Vector3(0.0, 1.9, tz - 0.25), Vector3(0.0, 2.1, tz - 0.25), 0.05, P.METAL)
	c.mbox(-0.05, 2.1, tz - 0.42, 0.05, 2.2, tz + 0.1, P.GUN)
	c.mbox(-0.02, 2.13, tz - 1.15, 0.02, 2.17, tz - 0.42, P.GUN)
	c.mbox(-0.035, 2.11, tz - 1.2, 0.035, 2.19, tz - 1.12, P.GUN)
	c.mbox(0.05, 2.02, tz - 0.3, 0.2, 2.15, tz - 0.05, P.SEAT)
	return c


# --- Captured MaxxPro -----------------------------------------------------------------------

## The Ashen Banner's captured MaxxPro: the MaxxPro as built, kept with its slat cage ("maxxpro_slat"'s
## boxes in data/vehicle_armour.json) and the DShK swapped onto the turret, with stencilled banner
## bands on the slat frames (the Banner's paint is its "banner" scheme, VehicleArt.SCHEMES).
static func _captured_maxxpro() -> Canvas:
	var c := VehicleArt._maxxpro(68)  # wider, for the slat's standoff
	var half_z := c.size.z * c.vs * 0.5
	for side: float in [-1.0, 1.0]:
		var x0 := minf(side * 1.5, side * 1.56)
		var x1 := maxf(side * 1.5, side * 1.56)
		# The vertical bars of the cage and its three rails, on brackets off the side.
		var z := half_z - 1.8
		while z < half_z + 3.15:
			c.mbox(x0, 0.75, z, x1, 2.95, z + 0.05, P.METAL)
			z += 0.22
		for ry: float in [0.75, 1.85, 2.92]:
			c.mbox(x0, ry, half_z - 1.85, x1, ry + 0.06, half_z + 3.2, P.METAL)
		for bz: float in [-1.5, 0.0, 1.5, 3.0]:
			c.mbar(Vector3(side * 1.3, 1.85, half_z + bz), Vector3(side * 1.52, 1.85, half_z + bz), 0.05, P.METAL)
			c.mbar(Vector3(side * 1.3, 0.8, half_z + bz), Vector3(side * 1.52, 0.8, half_z + bz), 0.05, P.METAL)
		c.mskin(x0, 1.4, half_z - 1.8, x1, 1.6, half_z + 3.2, P.MARKING, P.METAL)
	var rx := -1.3
	while rx < 1.3:
		c.mbox(rx, 0.7, half_z + 3.45, rx + 0.05, 2.95, half_z + 3.5, P.METAL)
		rx += 0.22
	for ry: float in [0.7, 2.92]:
		c.mbox(-1.3, ry, half_z + 3.45, 1.3, ry + 0.05, half_z + 3.5, P.METAL)
	for bx: float in [-1.1, 1.1]:
		c.mbar(Vector3(bx, 2.6, half_z + 3.3), Vector3(bx, 2.6, half_z + 3.48), 0.05, P.METAL)
	c.mskin(-1.3, 1.4, half_z + 3.45, 1.3, 1.6, half_z + 3.5, P.MARKING, P.METAL)
	# Banner stripes across the bonnet and the doors over the old paint.
	c.mskin(-0.95, 1.7, 0.45, 0.95, 1.85, 1.35, P.MARKING, P.PAINT)
	c.mskin(-1.3, 1.4, 2.0, 1.3, 1.5, 6.2, P.MARKING, P.PAINT)
	return c
