class_name VehicleInteriors
extends RefCounted
## Cabin interiors and see-through windows for the vehicles players ride in (Captain,
## 2026-10-13: "simple, readable vehicle interiors and windows"). Seated in first person you see
## a cabin: seats, a dash with a steering wheel (an instrument panel and stick in a cockpit),
## and windows you can see out of, instead of the inside of a solid hull.
##
## Drawn into the canvas's `look` only (VehicleArt.Canvas.look), at the models' 5 cm voxels:
## the voxels rounds and fragments meet (`buffer`, VehicleHull.first_solid) stay exactly as they
## were, so hit volumes and protection don't change. A window is P.GLASS where rounds meet it
## (stops what the hull's armour stops) and P.WINDOW in the look, glazed through the whole wall
## so it's see-through from the seat. The few visual-only changes (the M-ATV's cab back wall,
## gunners' hatches cut in the roof, the AAV driver's vision slit) are noted where they're drawn.
##
## Per model: the cabin is hollowed (if the model was drawn solid), the windows glazed, then a
## seat is put under each enclosed seat's eye (data/vehicles.json "seats", "at" is the eye in the
## vehicle's frame) and a dash or instrument panel before each driver's or pilot's. Furniture
## only goes into empty voxels inside the hull, so it never pokes out of a wall. Models with no
## interior here (Bradley, Abrams, AH-1Z: nothing spawns them yet) keep their solid look.

const P := VehicleArt.P

## How far below the eye a seat's cushion top sits (seated).
const CUSHION_DROP := 0.72
## Each body's cabin floor (metres up in the vehicle's frame): the seats stand on it, and a seated
## rider's feet rest on it (Vehicle: CharacterModel.seated_pose, Captain, 2026-10-14).
const FLOORS := {"matv": 1.0, "maxxpro": 1.2, "hilux": 0.75, "lc79": 0.85, "aav7": 1.0, "uh60": 0.62, "vtol_petrel": 0.6, "vtol_razorback": 1.0}

static var _seats := {}  # model -> Array of seat dictionaries (vehicles.json, "base" merged)
static var _mutex := Mutex.new()


## Gives `c` its look: a copy of its voxels with `model`'s interior drawn in. Runs on worker
## threads too (VehicleHull.prewarm): touches only `c` and this class's own seat table.
static func furnish(model: String, c: VehicleArt.Canvas) -> void:
	var body := _body_of(model)
	if not body in ["matv", "maxxpro", "hilux", "lc79", "aav7", "uh60", "vtol_petrel", "vtol_razorback"]:
		return
	var hit := c.buffer
	var look := VoxelBuffer.new()
	look.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	look.create(hit.get_size().x, hit.get_size().y, hit.get_size().z)
	look.copy_channel_from(hit, VoxelBuffer.CHANNEL_COLOR)
	# The Canvas helpers draw into `buffer`: point it at the look while drawing.
	c.buffer = look
	var cab := Cab.new(c, model)
	match body:
		"matv": _matv(cab)
		"maxxpro": _maxxpro(cab)
		"hilux", "lc79": _pickup(cab, body == "lc79")
		"aav7": _aav7(cab)
		"uh60": _uh60(cab)
		"vtol_petrel": _vtol_petrel(cab)
		"vtol_razorback": _vtol_razorback(cab)
	c.buffer = hit
	c.look = look


## Which body a model is drawn on: technicals are pickups ("hilux" or "lc79", as
## VehicleArt._technical picks).
static func _body_of(model: String) -> String:
	if model == "technical":
		return "hilux"
	if model.begins_with("technical_"):
		return "lc79" if model.trim_prefix("technical_") in ["zu23", "rockets", "zpu"] else "hilux"
	return model


# --- Drawing ------------------------------------------------------------------------------

## A cabin being drawn: the canvas (its `buffer` is the look while drawing), metres <-> voxels,
## and the drawing helpers. Canvas metres: x centred, y up, z back from the nose; the game's
## frame is the same with z from the footprint's middle (front -Z).
class Cab:
	var c: VehicleArt.Canvas
	var model := ""
	var half_z := 0.0
	var _rows := {}  # y * 65536 + z -> Vector2i(min x, max x) of solid look voxels

	func _init(p_c: VehicleArt.Canvas, p_model: String) -> void:
		c = p_c
		model = p_model
		half_z = c.size.z * c.vs * 0.5

	## A seat's eye from vehicles.json (vehicle frame) in canvas metres.
	func eye(seat: Dictionary) -> Vector3:
		var at: Array = seat.get("at", [0, 0, 0])
		return Vector3(float(at[0]), float(at[1]), float(at[2]) + half_z)

	func vx(x: float) -> int:
		return floori(x / c.vs + c.size.x * 0.5)

	func v(m: float) -> int:
		return floori(m / c.vs)

	## Hollows a box (metres): every voxel in it goes.
	func carve(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
		c.box(vx(x0), v(y0), v(z0), vx(x1), v(y1), v(z1), P.EMPTY)
		_rows.clear()

	## Hollows z0..z1 slice by slice: x0..x1 and y0..top(z) (metres).
	func carve_under(x0: float, y0: float, z0: float, x1: float, z1: float, top: Callable) -> void:
		for zi in range(v(z0), v(z1)):
			var t: float = top.call((zi + 0.5) * c.vs)
			if t > y0:
				c.box(vx(x0), v(y0), zi, vx(x1), v(t), zi + 1, P.EMPTY)
		_rows.clear()

	## Hollows a round section (VehicleArt.Section) from z0 to z1, leaving a wall `wall` thick
	## and the floor and roof bands: the inside of an aircraft's shell, cleared of whatever else
	## was drawn into it.
	func carve_section(s: VehicleArt.Section, z0: float, z1: float, y0: float, y1: float, wall: float) -> void:
		for yi in range(v(y0), v(y1)):
			var w := s.half_width_at((yi + 0.5) * c.vs) - wall
			if w > 0.0:
				c.box(vx(s.cx - w) + 1, yi, v(z0), vx(s.cx + w), yi + 1, v(z1), P.EMPTY)
		_rows.clear()

	## Fills each row between the hull's walls across z0..z1, y0..y1 (a bulkhead).
	func bulkhead(z0: float, z1: float, y0: float, y1: float, colour: int) -> void:
		for zi in range(v(z0), v(z1)):
			for yi in range(v(y0), v(y1)):
				var r := _row(yi, zi)
				if r.x < r.y:
					c.box(r.x, yi, zi, r.y + 1, yi + 1, zi + 1, colour)
		_rows.clear()

	## Makes the windows in a box see-through: looking along `axis` (0 x, 1 y, 2 z) from the box's
	## low side (`from_low`) or high side, each line's first voxel, if it's glass, and the wall's
	## voxels behind it (up to the first gap) become P.WINDOW. Posts and frames (anything that
	## isn't glass on the outside) stay.
	func glaze(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, axis: int, from_low: bool) -> void:
		var lo := Vector3i(vx(minf(x0, x1)), v(y0), v(z0))
		var hi := Vector3i(vx(maxf(x0, x1)), v(y1), v(z1))
		var a := axis
		var b := (axis + 1) % 3
		var d := (axis + 2) % 3
		for i in range(lo[b], hi[b]):
			for j in range(lo[d], hi[d]):
				var p := Vector3i.ZERO
				p[b] = i
				p[d] = j
				var started := false
				var steps := range(lo[a], hi[a]) if from_low else range(hi[a] - 1, lo[a] - 1, -1)
				for k: int in steps:
					p[a] = k
					var at := c.get_at(p.x, p.y, p.z)
					if not started:
						if at == P.EMPTY:
							continue
						if at != P.GLASS:
							break
						started = true
					elif at == P.EMPTY:
						break
					c.put(p.x, p.y, p.z, P.WINDOW)

	## Makes every voxel of `colours` in a box see-through (P.WINDOW), whatever side it faces: a
	## turret's armoured windows and vision blocks, drawn dark on thick or angled plates where
	## glaze()'s straight lines don't reach every voxel.
	func see_through(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colours: Array) -> void:
		for xi in range(vx(minf(x0, x1)), vx(maxf(x0, x1))):
			for yi in range(v(y0), v(y1)):
				for zi in range(v(minf(z0, z1)), v(maxf(z0, z1))):
					if c.get_at(xi, yi, zi) in colours:
						c.put(xi, yi, zi, P.WINDOW)

	## Glazes a box from both sides along x (a cabin's side windows, both sides at once when
	## the box spans the hull).
	func glaze_sides(x_out: float, x_in: float, y0: float, z0: float, y1: float, z1: float) -> void:
		glaze(-x_out, y0, z0, -x_in, y1, z1, 0, true)
		glaze(x_in, y0, z0, x_out, y1, z1, 0, false)

	## Glazes a ring of glass (a cupola's vision blocks) from all four sides.
	func glaze_ring(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
		for from_low in [true, false]:
			glaze(x0, y0, z0, x1, y1, z1, 0, from_low)
			glaze(x0, y0, z0, x1, y1, z1, 2, from_low)

	## Solid look voxels' x extent on a row (cached), Vector2i(1, 0) for none.
	func _row(yi: int, zi: int) -> Vector2i:
		var key := yi * 65536 + zi
		if _rows.has(key):
			return _rows[key]
		var r := Vector2i(1, 0)
		for xi in c.size.x:
			if c.get_at(xi, yi, zi) != P.EMPTY:
				r = Vector2i(xi, xi)
				break
		if r.x <= r.y:
			for xi in range(c.size.x - 1, -1, -1):
				if c.get_at(xi, yi, zi) != P.EMPTY:
					r.y = xi
					break
		_rows[key] = r
		return r

	## Furniture: fills the empty voxels of a box (metres) that lie between the hull's walls.
	func fit(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, colour: int) -> void:
		for zi in range(v(z0), maxi(v(z1), v(z0) + 1)):
			for yi in range(v(y0), maxi(v(y1), v(y0) + 1)):
				var r := _row(yi, zi)
				for xi in range(maxi(vx(x0), r.x + 1), mini(maxi(vx(x1), vx(x0) + 1), r.y)):
					if c.get_at(xi, yi, zi) == P.EMPTY:
						c.put(xi, yi, zi, colour)

	## A seat under `e` (the eye): cushion, backrest and a pedestal down to the floor.
	## `floor_y`: the cabin floor, so a low eye's cushion still sits on it.
	func seat(e: Vector3, floor_y: float, wide := 0.22) -> void:
		var top := VehicleInteriors.cushion_top(e.y, floor_y)
		fit(e.x - wide, top - 0.1, e.z - 0.25, e.x + wide, top, e.z + 0.2, P.SEAT)
		fit(e.x - wide, top, e.z + 0.2, e.x + wide, e.y - 0.12, e.z + 0.3, P.SEAT)
		fit(e.x - 0.12, floor_y, e.z - 0.12, e.x + 0.12, top - 0.1, e.z + 0.12, P.PAINT_DARK)

	## A driver's place: the dash across the cab (x0..x1) standing out from the front wall
	## before the eye, with the instrument cluster, the radio stack and a steering wheel on its
	## column (nearer than arm's length where the windscreen is close, as in the MaxxPro).
	func dash(e: Vector3, x0: float, x1: float) -> void:
		var top := e.y - 0.42
		var front := _front(e, top - 0.05)
		var back := minf(front + 0.22, e.z - 0.32)
		fit(x0, top - 0.3, front - 0.6, x1, top, back, P.PAINT_DARK)
		fit(e.x - 0.18, top - 0.08, front - 0.6, e.x + 0.18, top + 0.04, back - 0.02, P.BLACK)  # cluster hood
		fit(-0.1, top - 0.28, front - 0.6, 0.1, top - 0.06, back + 0.04, P.METAL)  # radio stack
		var w := Vector3(e.x, e.y - 0.4, maxf(e.z - 0.45, back + 0.06))  # wheel centre
		var n := Vector3(0, 0.5, 1).normalized()  # facing the driver, tilted back
		var u := Vector3.RIGHT
		var t := n.cross(u)
		for k in 40:
			var a := TAU * k / 40.0
			var p := w + (u * cos(a) + t * sin(a)) * 0.17
			fit(p.x - 0.025, p.y - 0.025, p.z - 0.025, p.x + 0.025, p.y + 0.025, p.z + 0.025, P.BLACK)
		for a: float in [0.0, PI, PI * 1.5]:  # spokes
			_bar(w, w + (u * cos(a) + t * sin(a)) * 0.17, P.BLACK)
		_bar(w, w - n * 0.35 + Vector3(0, -0.1, 0), P.BLACK)  # column

	## A pilot's place: the instrument panel under its glare shield across x0..x1, the cyclic
	## between the knees and the collective at the left hand.
	func cockpit(e: Vector3, x0: float, x1: float, floor_y: float) -> void:
		var top := e.y - 0.45
		fit(x0, top - 0.32, e.z - 0.9, x1, top, e.z - 0.72, P.BLACK)
		fit(x0, top, e.z - 0.95, x1, top + 0.06, e.z - 0.62, P.PAINT_DARK)  # glare shield
		for gx: float in [-0.12, 0.0, 0.12]:  # displays
			fit(e.x + gx - 0.05, top - 0.22, e.z - 0.74, e.x + gx + 0.05, top - 0.1, e.z - 0.7, P.LIGHT_GREEN)
		_bar(Vector3(e.x, floor_y, e.z - 0.35), Vector3(e.x, e.y - 0.62, e.z - 0.42), P.BLACK)
		_bar(Vector3(e.x - 0.3, floor_y + 0.25, e.z + 0.1), Vector3(e.x - 0.3, floor_y + 0.45, e.z - 0.3), P.BLACK)

	## Where the cabin ends in front of the eye at height `y`: the back face (metres) of the
	## first solid voxel straight ahead, at most 1.5 m out.
	func _front(e: Vector3, y: float) -> float:
		var xi := vx(e.x)
		var yi := v(y)
		var zi := v(e.z)
		var last := maxi(v(e.z - 1.5), 0)
		while zi > last and c.get_at(xi, yi, zi) == P.EMPTY:
			zi -= 1
		return (zi + 1) * c.vs

	func _bar(a: Vector3, b: Vector3, colour: int) -> void:
		var steps := maxi(ceili(a.distance_to(b) / (c.vs * 0.5)), 1)
		for i in steps + 1:
			var p := a.lerp(b, float(i) / steps)
			fit(p.x - 0.025, p.y - 0.025, p.z - 0.025, p.x + 0.025, p.y + 0.025, p.z + 0.025, colour)

	## Seats for every enclosed seat (not "open", not standing), dashes for drivers and panels
	## for pilots.
	func seats(floor_y: float, dash_x0: float, dash_x1: float) -> void:
		for s: Dictionary in VehicleInteriors.seats_of(model):
			if bool(s.get("open", false)) or String(s.get("stance", "sit")) == "stand":
				continue
			var e := eye(s)
			match String(s.get("kind", "passenger")):
				"driver":
					dash(e, dash_x0, dash_x1)
				"pilot":
					cockpit(e, dash_x0, dash_x1, floor_y)
			seat(e, floor_y)


# --- Seat data ------------------------------------------------------------------------------

## `model`'s cabin floor (FLOORS), or NAN for a model with no cabin drawn here.
static func floor_of(model: String) -> float:
	return float(FLOORS.get(_body_of(model), NAN))


## The top of the cushion under a seated eye at `eye_y` (vehicle frame), on a floor at
## `floor_y` (NAN: not known): CUSHION_DROP below the eye, but on a low seat's pedestal.
static func cushion_top(eye_y: float, floor_y: float) -> float:
	return eye_y - CUSHION_DROP if is_nan(floor_y) else maxf(eye_y - CUSHION_DROP, floor_y + 0.12)


## A model's seats from data/vehicles.json ("base" merged), read here rather than through
## VehicleSpecs so building a canvas on a worker thread touches no shared tables.
static func seats_of(model: String) -> Array:
	_mutex.lock()
	if _seats.is_empty():
		var models := {}
		var file := FileAccess.open(VehicleSpecs.PATH, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				models = (parsed as Dictionary).get("models", {})
		for m: String in models:
			var spec: Dictionary = models[m]
			var depth := 0
			while not spec.has("seats") and spec.has("base") and depth < 4:
				spec = models.get(String(spec.base), {})
				depth += 1
			_seats[m] = spec.get("seats", [])
		_seats[""] = []  # loaded (even with nothing in it)
	var out: Array = _seats.get(model, [])
	_mutex.unlock()
	return out


# --- The cabins ---------------------------------------------------------------------------

## M-ATV: the cab was drawn as a hollow shell (VehicleArt._matv), open at the back. A back wall
## with a small window closes it off from the bed (visual only: rounds still pass there as
## before), the gunner's hatch is cut through the roof under the turret ring (visual only), and
## the windscreen and door windows are glazed, and the turret's shield windows (_ogpk; they turn
## with it: VehicleTurret.split carries the look).
static func _matv(k: Cab) -> void:
	k.bulkhead(4.3, 4.4, 0.95, 2.45, P.PAINT)
	k.c.mbox(-0.45, 1.85, 4.3, 0.45, 2.2, 4.4, P.WINDOW)
	k.c.mdisc(0.0, 3.3, 0.3, 2.3, 2.65, P.EMPTY)  # through the turret's floor plate too
	k.glaze(-0.95, 1.8, 1.9, 0.95, 2.42, 2.7, 2, true)
	k.glaze_sides(1.3, 0.6, 1.75, 2.6, 2.3, 4.1)
	_ogpk(k, 0.0, 2.48, 3.3, 0.88)
	k.seats(FLOORS.matv, -0.95, 0.95)


## The O-GPK gun shield's armoured windows (VehicleArt._turret, same numbers): the front window,
## the gun port under it and the window in each angled wing, see-through right through the
## plate (they were dark blocks from the gunner's place). Visual only.
static func _ogpk(k: Cab, x: float, roof: float, z: float, half: float) -> void:
	var front := z - half
	var clear := [P.GLASS, P.BLACK, P.PAINT, P.PAINT_DARK]
	k.see_through(x - 0.22, roof + 0.42, front - 0.02, x + 0.22, roof + 0.66, front + 0.07, clear)
	k.see_through(x - 0.07, roof + 0.25, front - 0.02, x + 0.07, roof + 0.38, front + 0.07, [P.BLACK])
	for side: float in [-1.0, 1.0]:
		var wx := x + side * half * 0.7
		k.see_through(wx - 0.1, roof + 0.4, front - 0.02, wx + 0.1, roof + 0.6, front + half * 0.3 + 0.05, clear)


## The AAV-7's weapon station: vision blocks all round its wall at the gunner's eye (the real
## UGWS has a ring of them), besides the three in front (VehicleArt._aav7); posts between them.
## Visual only.
static func _ugws_ring(k: Cab, ux: float, uz: float) -> void:
	var lo := Vector3i(k.vx(ux - 0.7), k.v(2.95), k.v(uz - 0.7))
	var hi := Vector3i(k.vx(ux + 0.7), k.v(3.08), k.v(uz + 0.7))
	for xi in range(lo.x, hi.x + 1):
		for yi in range(lo.y, hi.y):
			for zi in range(lo.z, hi.z + 1):
				if not k.c.get_at(xi, yi, zi) in [P.PAINT, P.GLASS]:
					continue
				var dx := (xi + 0.5 - k.c.size.x * 0.5) * k.c.vs - ux
				var dz := (zi + 0.5) * k.c.vs - uz
				var a := rad_to_deg(atan2(dx, dz))  # 0 back, +-180 front
				var nearest := roundf(a / 45.0) * 45.0
				if absf(a - nearest) <= 13.0 and absf(nearest) < 160.0:  # the front's are drawn already
					k.c.put(xi, yi, zi, P.WINDOW)

## MaxxPro: the armoured box was drawn solid. Hollowed (behind the raked windscreen, floor and
## walls 10-15 cm), the gunner's hatch cut under the turret (visual only), windscreen, door, troop
## and rear door windows glazed.
static func _maxxpro(k: Cab) -> void:
	var top := func(z: float) -> float:
		if z < 1.85:
			return lerpf(1.95, 2.85, clampf((z - 1.45) / 0.4, 0.0, 1.0)) - 0.2
		return 2.75
	k.carve_under(-1.02, 1.2, 1.5, 1.02, 6.3, top)
	k.c.mdisc(0.0, 3.0, 0.28, 2.7, 3.02, P.EMPTY)  # through the turret's floor plate too
	k.glaze(-1.0, 2.0, 1.4, 1.0, 2.75, 2.1, 2, true)
	k.glaze_sides(1.4, 0.9, 1.95, 2.0, 2.55, 6.1)
	k.glaze(-0.3, 2.05, 6.0, 0.3, 2.4, 6.5, 2, false)
	_ogpk(k, 0.0, 2.85, 3.0, 0.95)
	k.seats(FLOORS.maxxpro, -1.0, 1.0)


## A technical's pickup cab (Hilux or Land Cruiser 79, VehicleArt._pickup), drawn solid:
## hollowed under the windscreen and roof, windscreen, door and rear windows glazed.
static func _pickup(k: Cab, lc: bool) -> void:
	var hood_end := 1.95 if lc else 1.7
	var cab_end := 3.25 if lc else 3.0
	var roof := 1.95 if lc else 1.68
	var hood_top := 1.25 if lc else 1.05
	var rake := 0.18 if lc else 0.5
	var floor_y: float = FLOORS.lc79 if lc else FLOORS.hilux
	var top := func(z: float) -> float:
		var t := clampf((z - hood_end) / rake, 0.0, 1.0)
		return lerpf(hood_top, roof, t) - (0.2 if t < 1.0 else 0.08)
	k.carve_under(-0.72, floor_y, hood_end + 0.05, 0.72, cab_end - 0.08, top)
	k.glaze(-0.78, hood_top + 0.04, hood_end - 0.1, 0.78, roof - 0.07, hood_end + rake + 0.3, 2, true)
	k.glaze_sides(1.0, 0.6, hood_top + 0.08, hood_end + rake, roof - 0.09, cab_end - 0.1)
	k.glaze(-0.55, hood_top + 0.12, cab_end - 0.3, 0.55, roof - 0.14, cab_end + 0.15, 2, false)
	k.seats(floor_y, -0.72, 0.72)


## AAV-7: the hull was drawn solid. Hollowed: the driver's and commander's places down the left
## (the engine bay stays solid on the right, as in the real thing), the gunner's basket under the
## weapon station and the troop compartment behind; the cupolas' vision blocks, the weapon
## station's and the ramp door's windows glazed. The driver also gets a vision slit in the bow
## in front of his eye (visual only: the bow is as solid as before).
static func _aav7(k: Cab) -> void:
	var bow := func(z: float) -> float:
		return minf(lerpf(1.5, 2.62, clampf(z / 1.75, 0.0, 1.0)) - 0.14, 2.52)
	k.carve_under(-1.5, 1.0, 1.15, -0.3, 3.7, bow)
	k.carve(-1.5, 1.0, 3.4, 1.5, 2.52, 7.83)
	k.c.mdisc(0.82, 2.15, 0.45, 2.3, 3.1, P.EMPTY)  # gunner's basket in the weapon station
	k.c.mdisc(-0.95, 2.05, 0.27, 2.4, 2.8, P.EMPTY)  # driver's cupola
	k.c.mdisc(-0.95, 3.1, 0.3, 2.4, 2.92, P.EMPTY)  # commander's cupola
	k.c.mskin(-1.3, 2.12, 0.9, -0.6, 2.45, 1.75, P.GLASS)
	k.glaze(-1.3, 2.12, 0.9, -0.6, 2.45, 1.75, 2, true)
	k.glaze_ring(-1.35, 2.7, 1.6, -0.55, 2.8, 2.5)
	k.glaze_ring(-1.4, 2.82, 2.65, -0.5, 2.94, 3.55)
	for gx: float in [-0.35, 0.0, 0.35]:
		k.glaze(0.82 + gx - 0.1, 2.95, 1.3, 0.82 + gx + 0.1, 3.08, 2.2, 2, true)
	_ugws_ring(k, 0.82, 2.15)
	k.glaze(-0.2, 1.65, 7.6, 0.2, 1.95, 8.1, 2, false)
	# The troop compartment's vision blocks along the roof edges: glass (visual only).
	for side: float in [-1.0, 1.0]:
		for vz: float in [4.0, 5.2, 6.4]:
			k.c.mbox(minf(side * 1.3, side * 1.55), 2.62, vz, maxf(side * 1.3, side * 1.55), 2.7, vz + 0.3, P.WINDOW)
	k.seats(FLOORS.aav7, -1.5, -0.35)


## UH-60: the fuselage was drawn as a shell, but the upper deck's floor runs through the cabin's
## ceiling. Cleared back to the shell from the cockpit's back to the aft cabin, then the
## windscreen, overhead, cockpit door, gunner's and cabin door windows glazed. The door guns
## stay solid (Captain, 2026-10-14: "clear guns on the blackhawk").
static func _uh60(k: Cab) -> void:
	var cabin := VehicleArt.Section.new(0.5, 2.22, 1.18, 0.94, 0.3, 0.45)
	k.carve_section(cabin, 2.45, 7.95, 0.62, 2.1, 0.13)
	k.glaze(-1.0, 1.6, 0.9, 1.0, 2.18, 2.2, 2, true)
	k.glaze(-0.55, 2.0, 2.1, 0.55, 2.4, 2.45, 1, false)
	k.glaze_sides(1.45, 0.75, 0.78, 1.3, 2.14, 6.3)
	# Each gunner's window (the fuselage narrows there, past the side glazing's reach):
	# see-through within the window (visual only; it still stops rounds). Not the M240H, its mount
	# and its ammo bag across it: Captain, 2026-10-14, "clear guns on the blackhawk" (they drew
	# in the window's tinted glass, the gunner and the ground showing through the gun).
	for side: float in [-1.0, 1.0]:
		k.see_through(side * 0.75, 1.45, 2.95, side * 1.5, 2.08, 3.55, [P.GLASS, P.PAINT])
	k.seats(FLOORS.uh60, -0.85, 0.85)


## VT-14 Petrel (docs/near_future_hardware.md): the same shell-then-glaze approach as the UH-60,
## matched to VehicleArt._vtol_petrel's flatter, lower cross-section (near-sharp corners) and
## PETREL_NOSE_OFFSET. Cleared from behind the cockpit canopy back to the aft cabin, short of the
## tapering tail so the ramp end stays a solid bulkhead for this first pass (the open-ramp look is
## a follow-up, not required for the model to fly and carry passengers).
static func _vtol_petrel(k: Cab) -> void:
	var o: float = VehicleArt.PETREL_NOSE_OFFSET
	var cabin := VehicleArt.Section.new(0.5, 2.9, 1.45, 1.0, 0.04, 0.03)
	# Runs only between the nose and tail tapers (data z -4.6..4.4): this full-width section carved
	# past them cut through the narrowing walls (ragged flanks, a loose frame left at the tail).
	k.carve_section(cabin, o - 4.6, o + 4.4, 0.6, 2.8, 0.12)
	k.glaze(-1.3, 1.7, o - 7.0, 1.3, 2.95, o - 4.5, 2, true)  # the big canopy
	k.glaze(-1.3, 2.3, o - 6.6, 1.3, 2.95, o - 4.6, 1, false)
	k.glaze_sides(1.55, 0.95, 1.7, o - 4.0, 2.2, o - 2.7)  # gunner windows
	k.glaze_sides(1.55, 0.95, 1.6, o - 2.2, 2.2, o - 1.2)  # door windows
	for wz: float in [o + 1.1, o + 2.6]:  # cabin windows
		k.glaze_sides(1.55, 0.95, 1.6, wz - 0.1, 2.1, wz + 1.0)
	k.seats(FLOORS.vtol_petrel, -0.85, 0.85)


## Razorback VTOL (VehicleArt._vtol_razorback): the big troop bay cleared from behind the
## cockpit to where the tail sweeps up, the many-paned nose glazed from inside, cabin windows.
static func _vtol_razorback(k: Cab) -> void:
	var o: float = VehicleArt.RAZORBACK_NOSE_OFFSET
	var cabin := VehicleArt.Section.new(0.95, 4.0, 2.2, 1.85, 0.35, 0.3)
	k.carve_section(cabin, o - 7.0, o + 5.0, 1.0, 3.9, 0.16)
	k.glaze(-2.2, 2.2, o - 11.0, 2.2, 3.95, o - 7.4, 2, true)
	k.glaze_sides(2.4, 1.6, 2.9, o - 6.7, 3.6, o - 5.1)  # crew windows
	for wz: float in [o + 0.5, o + 2.2, o + 3.9]:  # cabin windows
		k.glaze_sides(2.4, 1.6, 3.0, wz - 0.1, 3.55, wz + 0.9)
	k.seats(FLOORS.vtol_razorback, -1.6, 1.6)
