class_name WoundMarks
extends Node3D
## The body's wounds drawn where they are. Up close (WoundSkin, within WoundSkin.RANGE_M) they are
## painted into the body's own 0.5 cm voxels: each hole's dark core (a bigger, ragged one at an
## exit), torn cloth or a raw rim round it, the blood that ran down the skin with gravity and
## the soak spreading through the uniform with the blood lost there, wet while it bleeds and
## drying brown after; bruises where armour stopped a round (gore records "b", BRUISE_*) and over
## closed breaks. Further off, coarse 1 cm voxels of the same holes and blood stand in ("WoundMark"
## on the part's bone, laid on the 0.5 cm body shape, BodyVolume.surface). Blood drips off the
## lowest point and pools on the ground. Treated or held by a tourniquet, it stops; what treated it
## covers the spot ("WoundDressing", laid on the skin): a pressure bandage (cream elastic wrap, its
## pressure bar over the hole), packed gauze (white, bulging, its tail loose), a chest seal (a
## square patch, dark border and valve) or a plain dressing. A casualty bleeding while dragged or
## crawling smears a trail on the ground (SMEAR_*), and whoever works on a bleeding wound gets
## blood on their hands (HAND_*). Blood that lands on someone else or on gear stains it
## (BloodStain). Devices on the body (tourniquets, splints, lines and bags...) are BodyDevices',
## and what shows in the skin (burns, pallor, blue lips, shivering) BodyCondition's; both are
## made here.
##
## Never floating (Captain, 2026-10-26: "blood to stop floating"): everything on the body is drawn
## on its part's bone through the part's build (fit_of: a broad or slim build widens the mesh, and
## the marks with it); what lands on the ground lies on the ground under each cell, tilted to it,
## re-seated when the ground under it changes (_settle), and drops fall on until they meet it.
##
## Positions come from the wounds' "at" and "out" (rest pose, Vitals.wound_list,
## replicated), and the flow from their replicated rates, so every peer draws the same
## wounds; the blood itself is cosmetic and local (no network traffic).

const HOLE_COLOUR := Color("1c0504")
const RIM_COLOUR := Color("6b1510")
const FRESH_COLOUR := Color("7d130f")
const BLOOD_COLOUR := Color("5a0c09")
const DRIED_COLOUR := Color("320806")
const DRESSING_COLOUR := Color("d8d0b8")
const ENTRY_SIZE := 0.014
const EXIT_SIZE := 0.024
## Blood voxels on the skin, and how many a litre lost at one spot makes (a femoral wound
## runs the length of the thigh in about 20 s, a muscle wound in about a minute).
const CELL := 0.01
const CELLS_PER_L := 240.0
const MAX_CELLS := 70
const MAX_TRAIL := 30
## Wound kinds that bleed out of the skin (internal and fracture bleeding stays inside).
const EXTERNAL_KINDS := ["arterial", "junctional", "venous", "muscle", "graze"]
## Drips per second per L/min, the most in the air at once, and the ground pool's voxels.
const DRIPS_PER_L_MIN := 10.0
const MAX_DRIPS := 40
const DRIP_SIZE := 0.008
const POOL_CELL := 0.025
const POOL_HEIGHT := 0.006
const MAX_POOL := 400
## Drops thrown out of an exit wound when the round goes through.
const SPATTER_DROPS := 14
## Brain matter thrown out of a head exit (Captain, 2026-10-16: "also brains from headshots"):
## pinkish-grey chunks that fly with the spatter and lie where they land.
const BRAIN_DROPS := 12
const BRAIN_SIZE := 0.018
const BRAIN_COLOUR := Color("b8908b")
const BRAIN_DARK := Color("7e5552")
const MAX_CHUNKS := 60
## How long what lands on the ground stays (Captain, 2026-10-16: "3-4 minutes for most small blood
## and 7-9 mins for pools", "~6-7 minutes ... for most things"), seconds; checked every EXPIRE_TICK_S.
const SPECK_LIFE_S := Vector2(180.0, 240.0)
const POOL_LIFE_S := Vector2(420.0, 540.0)
const CHUNK_LIFE_S := Vector2(360.0, 420.0)
const EXPIRE_TICK_S := 10.0
## What a drop can land on: the world, hitboxes, items, armour and bodies. On anything but the
## world it sticks to that (Charges.rider_of) and rides along. A pool spills only over ground
## within POOL_STEP of its cell.
const LAND_MASK := (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | Ragdoll.LAYER
const WORLD_MASK := 1
## How far above a drop's start the floor is looked for again when nothing is below it
## (_floor_below: a drop starting just under the floor's surface).
const FLOOR_LOOK_UP_M := 0.3
const POOL_STEP := 0.15
## Things blood has stained (BloodStain), at most.
const MAX_STAINED := 24
## The coarse blood voxels draw from WoundSkin.RANGE_M (the painted skin nearer) to FAR_M.
const FAR_M := 80.0
## Ground blood re-seated each EXPIRE_TICK_S (_settle): at most SETTLE_RAYS cells a tick, in turn;
## a cell whose ground moved more than SETTLE_SLACK falls to the new ground within SETTLE_DROP, or
## goes (the ground blown away under it).
const SETTLE_RAYS := 48
const SETTLE_SLACK := 0.01
const SETTLE_DROP := 1.0
## A drop that falls further than this splashes: a few specks round where it landed.
const SPLASH_FALL_M := 0.6
const SPLASH_SPECKS := 3
## Bruises: armour stops (gore "b": WoundSkin paints them on bare skin) and closed breaks; they
## turn from red-purple to bluer over BRUISE_AGE_S.
const BRUISE_AGE_S := 600.0
const BRUISE_STOP_R := 0.045
const BRUISE_BREAK_R := 0.06
## The painted skin while it bleeds: repainted at most every SKIN_TICK_S.
const SKIN_TICK_S := 0.3
## Realism (Captain, 2026-10-27: "it needs to be more realistic in how it works"):
## - Runs follow the way down as the body is now: when that turns more than RUN_TURN_DEG from the
##   run in progress (he falls, is laid down, carried) a new run starts from the hole; the old one
##   stays where it ran. MAX_RUNS a hole (the first and the latest kept).
## - Arterial and junctional bleeds spurt with the heartbeat: SPURT_DROPS drops a beat, as fast
##   as SPURT_MPS at full pressure (blood fraction PRESSURE_FROM down to PRESSURE_GONE: none).
## - Drips leave from where the blood ends up: the lowest of the hole, the ends of its runs and the
##   low edge of its soak.
## - A dressing over a wound still bleeding under it reddens from the middle (SEEP_*), and one put
##   on a bloody wound picks up blood at its edges (EDGE_*).
const RUN_TURN_DEG := 35.0
const MAX_RUNS := 3
const SPURT_DROPS := 3
const SPURT_MPS := 2.2
const PRESSURE_FROM := 0.85
const PRESSURE_GONE := 0.4
const ARTERIAL_KINDS := ["arterial", "junctional"]
const SEEP_BASE_M := 0.012
const SEEP_PER_SQRT_L := 0.25
const SEEP_MAX_M := 0.07
const EDGE_FROM_L := 0.03
const EDGE_SHARE := 0.35
## Dressing looks: a pressure bandage (Israeli style), packed gauze, a vented chest seal.
const BANDAGE_COLOUR := Color("e3dcc4")
const BANDAGE_WEAVE := Color("cfc6aa")
const PRESSURE_BAR := Color("6f736f")
const GAUZE_COLOUR := Color("f3f1ea")
const GAUZE_SHADE := Color("dcd8cc")
const SEAL_COLOUR := Color("b7c0c6")
const SEAL_BORDER := Color("262626")
const SEAL_VALVE := Color("e6e6e0")
## Which dressing a treated spot shows, best first (from the kinds of wound treated there).
const LOOKS: Array[StringName] = [&"seal", &"gauze", &"bandage", &"dressing"]
## The smear a bleeding casualty leaves when dragged or crawling: a cell every SMEAR_STEP moved
## while the bleeding spot is within SMEAR_REACH of the ground, at most MAX_SMEAR (the oldest
## goes first); it lies as long as a pool.
const SMEAR_STEP := 0.04
const SMEAR_REACH := 0.35
const MAX_SMEAR := 160
## Blood on the hands of someone treating a wound that bleeds or has bled, while the treat clip
## plays (_check_hands): up to HAND_CELLS a hand, drying after HAND_DRY_S, gone after
## HAND_LIFE_S. Checked every HAND_TICK_S.
const HAND_REACH := 0.45
const HAND_CELLS := 22
const HAND_DRY_S := 60.0
const HAND_LIFE_S := 420.0
const HAND_TICK_S := 0.5
const HAND_PATIENT_M := 2.5  # how far from the hands' point the patient's body can be

var model: CharacterModel
var vitals: Vitals
var body := ""  # the body type (BodyVolume.body_of): blood lies on that body's shape
var _key := ""
var _spots: Dictionary = {}  # spot key -> spot state (see _new_spot)
var _bone_meshes: Dictionary = {}  # bone -> MultiMeshInstance3D (the coarse holes and blood)
var _dress_meshes: Dictionary = {}  # bone -> MultiMeshInstance3D (dressings)
var _dirty := false
var _drips: Array[Dictionary] = []  # {"pos", "vel", "floor"} in world space
var _drip_timer := 0.0
var _drip_mesh: MultiMeshInstance3D
var _pool: Dictionary = {}  # Vector2i -> {"y", "n" (the ground's normal), "amount", "until"}
var _pool_mesh: MultiMeshInstance3D
var _pool_centre: Variant = null  # the cell the first drip landed in: the pool spreads out from it
var _pool_dirty := false
var _chunks: Array[Dictionary] = []  # brain on the ground: {"pos", "size", "colour", "until"}
var _chunk_mesh: MultiMeshInstance3D
var _stained: Array[BloodStain] = []  # what this body's blood has stained
var skin: WoundSkin
var _skin_next := 0.0
var _bruise_seen: Dictionary = {}  # bruise key -> when first seen here (its age)
var _settle_at := 0  # the next ground cell _settle looks at
var _own_rids_cache: Array[RID] = []
var _own_rids_children := -1
var devices: BodyDevices
var condition: BodyCondition
var _smear: Array[Dictionary] = []  # {"pos", "dir", "length", "width", "colour", "until"} (world)
var _smear_mesh: MultiMeshInstance3D
var _smear_last: Variant = null  # where the trunk was when the last smear cell went down
var _hand_blood := 0.0  # seconds of work in blood
var _hand_cells: Array = [[], []]  # right, left: [rest point, size] each
var _hand_until := 0.0
var _hand_wet_until := 0.0
var _hand_meshes: Array = [null, null]
static var _material: StandardMaterial3D


func setup(p_model: CharacterModel, p_vitals: Vitals) -> void:
	model = p_model
	vitals = p_vitals
	body = BodyVolume.body_of(p_model)
	add_to_group(&"wound_marks")
	skin = WoundSkin.new(p_model, body)
	vitals.changed.connect(_rebuild)
	var expire := Timer.new()
	expire.wait_time = EXPIRE_TICK_S
	expire.autostart = true
	expire.timeout.connect(_expire)
	add_child(expire)
	var hands := Timer.new()
	hands.name = "Hands"
	hands.wait_time = HAND_TICK_S
	hands.autostart = true
	hands.timeout.connect(_check_hands)
	add_child(hands)
	devices = BodyDevices.new()
	devices.name = "BodyDevices"
	add_child(devices)
	devices.setup(p_model, p_vitals, body)
	condition = BodyCondition.new()
	condition.name = "BodyCondition"
	add_child(condition)
	condition.setup(p_model, p_vitals, body)
	set_process(false)
	_rebuild()


func _rebuild() -> void:
	var wounds := vitals.wound_list() if is_instance_valid(vitals) else []
	var key := ""
	for w: Dictionary in wounds:
		if w.get("at") is Vector3:
			key += "%s%s%s%s%s%s%s|" % [w.part, w.at, w.get("out"), w.treated, w.packed, w.clamped, w.tourniquet]
		elif w.kind in ["fracture", "rib"] and not w.get("open", false):
			key += "%s%s|" % [w.part, w.name]  # a closed break: a bruise over it
	for g: Dictionary in bruise_records():
		key += "b%s%s%s|" % [g.get("p"), g.get("a"), g.get("s")]
	if key == _key:
		return
	_key = key
	# One spot per hole pair: several wounds from one round (vessel, bone, muscle) share it.
	var seen := {}
	for w: Dictionary in wounds:
		var at: Variant = w.get("at")
		if not at is Vector3:
			continue
		var spot_key := "%s%s" % [w.part, at]
		if not _spots.has(spot_key):
			_spots[spot_key] = _new_spot(w.part, at, w.get("out"))
			if w.get("out") is Vector3:
				_spatter(_spots[spot_key])
		var spot: Dictionary = _spots[spot_key]
		if not seen.has(spot_key):
			seen[spot_key] = true
			spot.flow = 0.0
			spot.arterial = 0.0
			spot.treated = false
			spot.look = &""
		if w.treated:
			spot.treated = true
		var look := _look_of(w)
		if look != &"" and (spot.look == &"" or LOOKS.find(look) < LOOKS.find(spot.look)):
			spot.look = look
		if String(w.kind) in EXTERNAL_KINDS and not w.treated and not w.packed and not w.clamped:
			spot.flow += float(w.rate) * (0.1 if w.tourniquet else 1.0)
			if String(w.kind) in ARTERIAL_KINDS and not w.tourniquet:
				spot.arterial += float(w.rate)
	for spot_key: String in _spots.keys():
		if not seen.has(spot_key):
			_spots.erase(spot_key)  # healed or reset: the stain goes too
	for spot: Dictionary in _spots.values():
		# (A dressing over a wound that still bleeds under it keeps bleeding: it seeps through.)
		if spot.treated and float(spot.dressed_lost) < 0.0:
			spot.dressed_lost = spot.lost  # how bloody it was when it was dressed
		if spot.flow > 0.0:
			spot.stopped = INF
		elif float(spot.stopped) == INF:
			spot.stopped = _now()  # stopped now: it starts to dry
	_dirty = true
	_redraw()
	paint_skin()
	_update_processing()


## The armour stops recorded on this body (Vitals.server_impact: gore "b" records).
func bruise_records() -> Array:
	if not is_instance_valid(vitals):
		return []
	return vitals.gore_list().filter(func(g: Dictionary) -> bool: return String(g.get("k", "")) == "b")


## Paints the wounds into the body's voxels (WoundSkin): every spot, how far it has soaked and
## run and how wet it is now, and the bruises.
func paint_skin() -> void:
	if skin == null:
		return
	_skin_next = _now() + SKIN_TICK_S
	var spots: Array = []
	var bruises: Array = []
	var now := _now()
	var alive := is_instance_valid(vitals) and not vitals.is_dead()
	for spot: Dictionary in _spots.values():
		var lost := float(spot.lost)
		var flowing: bool = spot.flow > 0.0 and alive
		var wet := 1.0 if flowing or float(spot.stopped) == INF else clampf(1.0 - (now - float(spot.stopped)) / WoundSkin.DRY_S, 0.0, 1.0)
		var soak := WoundSkin.SOAK_BASE_M + WoundSkin.SOAK_PER_L * pow(lost, WoundSkin.SOAK_POWER)
		for hole: Dictionary in spot.holes:
			var salt := float(hash(hole.at) % 997) / 9.7
			var runs: Array = hole.runs
			# The hole and its soak, sagging the way down is now, with the run in progress (the latest).
			var latest: Dictionary = runs[-1] if not runs.is_empty() else {}
			spots.append({"part": spot.part, "at": hole.at, "n": hole.n, "down": spot.down if latest.is_empty() else latest.dir,
				"exit": hole.exit, "core": (EXIT_SIZE if hole.exit else ENTRY_SIZE) * 0.5, "soak": soak,
				"trail": _run_length(latest, lost), "wet": wet, "salt": salt})
			for i in runs.size() - 1:  # runs from before he moved: where they ran then
				spots.append({"part": spot.part, "at": hole.at, "n": hole.n, "down": runs[i].dir, "exit": false, "core": 0.0,
					"soak": 0.0, "trail": _run_length(runs[i], lost), "wet": wet, "salt": salt + 3.1 * (i + 1)})
			# The skin right round a hole bruises a little (bare skin only).
			bruises.append({"at": hole.at, "r": (EXIT_SIZE if hole.exit else ENTRY_SIZE) + 0.012, "s": 0.3, "age": 0.0})
	for g: Dictionary in bruise_records():
		var at: Variant = BlastGore.to_vec(g.get("a"))
		if at is Vector3:
			bruises.append({"at": at, "r": BRUISE_STOP_R * (0.8 + 0.4 * float(g.get("s", 0.5))), "s": clampf(0.4 + float(g.get("s", 0.5)) * 0.6, 0.0, 1.0),
				"age": _bruise_age("b%s" % [g.get("a")])})
	for w: Dictionary in (vitals.wound_list() if is_instance_valid(vitals) else []):
		if w.kind in ["fracture", "rib"] and not w.get("open", false) and BodyMap.PART_BOXES.has(w.part):
			var at: Variant = _break_spot(w)
			if at is Vector3:
				bruises.append({"at": at, "r": BRUISE_BREAK_R, "s": 0.55, "age": _bruise_age("f%s%s" % [w.part, w.name])})
	skin.paint(spots, bruises, BodyDeform.gore_level() == "full")


## How far a run has got (m) from the blood lost while it ran (`lost` now, for the run in progress).
static func _run_length(run: Dictionary, lost: float) -> float:
	if run.is_empty():
		return 0.0
	var ran := (float(run.to) if float(run.to) >= 0.0 else lost) - float(run.from)
	return 0.0 if ran <= 0.0 else minf(WoundSkin.TRAIL_BASE_M + WoundSkin.TRAIL_PER_L * sqrt(ran), WoundSkin.TRAIL_MAX_M)


## Where `spot`'s blood gets to lowest in the world now (where it drips from): its holes, the ends
## of their runs and the low edge of its soak, each on the skin of the part it reaches.
func _lowest_point(spot: Dictionary) -> Variant:
	var soak := WoundSkin.SOAK_BASE_M + WoundSkin.SOAK_PER_L * pow(float(spot.lost), WoundSkin.SOAK_POWER)
	var best: Variant = null
	for hole: Dictionary in spot.holes:
		var ends: Array[Vector3] = [Vector3(hole.at)]
		for run: Dictionary in hole.runs:
			ends.append(Vector3(hole.at) + Vector3(run.dir) * _run_length(run, float(spot.lost)))
		ends.append(Vector3(hole.at) + Vector3(spot.down) * soak * WoundSkin.STRETCH_DOWN * 0.8)
		for p: Vector3 in ends:
			var part: StringName = spot.part if WoundSkin.rest_box(spot.part).has_point(p) else BodyMap.part_at(p)
			if WoundSkin.bone_part(part) != WoundSkin.bone_part(spot.part) and WoundSkin.bone_part(part) not in WoundSkin.JOINED.get(WoundSkin.bone_part(spot.part), []):
				part = spot.part
			var on: Variant = BodyVolume.surface(part, p, _outward(part, p), 0.06, body)
			if not on is Vector3:
				continue
			var w := to_world(part, Vector3(on) + _outward(part, on) * 0.004)
			if best == null or w.y < (best as Vector3).y:
				best = w
	return best


## An arterial bleed's heartbeat: each beat a spurt of drops out of its holes, as hard as his
## blood pressure (blood left) drives it; none once the heart stops.
func _beat(spot: Dictionary, delta: float) -> void:
	var rate := vitals.heart_rate() if is_instance_valid(vitals) else 0.0
	if rate <= 0.0 or vitals._m().arrest:
		return
	spot.beat = float(spot.beat) - delta
	if float(spot.beat) > 0.0:
		return
	spot.beat = 60.0 / rate
	var pressure := clampf((vitals.blood_fraction() - PRESSURE_GONE) / (PRESSURE_FROM - PRESSURE_GONE), 0.0, 1.0)
	if pressure <= 0.0 or not is_inside_tree():
		return
	var strength := pressure * clampf(float(spot.arterial) / 1.2, 0.3, 1.0)
	for hole: Dictionary in spot.holes:
		var from := to_world(spot.part, Vector3(hole.at) + Vector3(hole.n) * 0.008)
		var out := (to_world(spot.part, Vector3(hole.at) + Vector3(hole.n)) - to_world(spot.part, hole.at)).normalized()
		var floor_y := _floor_below(from)
		for i in SPURT_DROPS:
			if _drips.size() >= MAX_DRIPS:
				return
			var spread := Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.25), randf_range(-0.2, 0.2))
			_drips.append({"pos": from, "vel": (out + spread).normalized() * SPURT_MPS * strength * randf_range(0.6, 1.0),
				"floor": floor_y, "speck": true, "y0": from.y})


## How far a bruise first seen under `key` has turned (0 fresh .. 1).
func _bruise_age(key: String) -> float:
	if not _bruise_seen.has(key):
		_bruise_seen[key] = _now()
	return clampf((_now() - float(_bruise_seen[key])) / BRUISE_AGE_S, 0.0, 1.0)


## The skin over a closed break: its wound's point, else the front of the part's box (a rib: the
## side of the chest).
func _break_spot(w: Dictionary) -> Variant:
	if w.get("at") is Vector3:
		return w.at
	var box: Array = BodyMap.PART_BOXES[w.part][0]
	var dir := Vector3.FORWARD
	if w.kind == "rib":
		dir = Vector3.RIGHT if String(w.name).ends_with("_r") else Vector3.LEFT
	return BodyVolume.surface(w.part, Vector3(box[0]), dir, 0.25, body)


## A new wound spot: its holes (entry, and exit if it went through), each with the outward
## direction of the skin there and a blood trail that starts at the hole.
func _new_spot(part: StringName, at: Vector3, out: Variant) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s%s" % [part, at])
	var holes: Array[Dictionary] = [_new_hole(part, at, false, rng)]
	if out is Vector3:
		holes.append(_new_hole(part, out, true, rng))
	return {"part": part, "holes": holes, "flow": 0.0, "lost": 0.0, "treated": false, "look": &"", "made": 0, "rng": rng,
		"down": Vector3.DOWN, "downed": false, "stopped": _now(), "arterial": 0.0, "beat": 0.0, "seep": 0.0, "dressed_lost": -1.0}  # stopped: when it stopped bleeding (INF while it bleeds)


## The dressing a treated wound shows (LOOKS), or &"" for none (a splinted bone, a rib).
static func _look_of(w: Dictionary) -> StringName:
	if not (w.treated or w.get("packed", false) or w.get("clamped", false)):
		return &""
	if w.kind == "chest":
		return &"seal"
	if w.get("packed", false):
		return &"gauze"
	if w.kind in ["venous", "muscle", "graze"]:
		return &"bandage"
	if w.kind in ["arterial", "junctional", "internal", "heart"] or w.get("clamped", false):
		return &"dressing"
	return &""


## What covers the spot on `part` (LOOKS), &"" for none (tests).
func dressing_on(part: StringName) -> StringName:
	for spot: Dictionary in _spots.values():
		if spot.part == part and spot.treated and spot.look != &"":
			return spot.look
	return &""


func _new_hole(part: StringName, at: Vector3, exit: bool, rng: RandomNumberGenerator) -> Dictionary:
	var n := _outward(part, at)
	var on_skin: Variant = BodyVolume.surface(part, at, n, 0.05, body)
	var p: Vector3 = on_skin if on_skin is Vector3 else at
	var hole := {"at": p, "n": n, "exit": exit, "head": p, "trail": 0, "done": false,
		"marks": [], "blood": [], "runs": []}  # runs: {"dir" (rest), "from", "to" (L lost; to -1 while it runs)}
	# The hole: a dark core and a rim of torn, bloodied cloth (ragged and bigger at an exit).
	var core := EXIT_SIZE if exit else ENTRY_SIZE
	hole.marks.append([p + n * 0.004, Vector3.ONE * core, HOLE_COLOUR])
	for i in (9 if exit else 5):
		var r := core * (0.55 + rng.randf() * (0.9 if exit else 0.35))
		var q: Variant = _on_skin(part, p, n, r, rng.randf() * TAU)
		if q is Vector3:
			hole.marks.append([q + n * 0.002, Vector3.ONE * CELL * rng.randf_range(0.9, 1.3), RIM_COLOUR])
	return hole


## The skin `radius` from `p` at angle `angle` round the outward direction `n`, or null.
func _on_skin(part: StringName, p: Vector3, n: Vector3, radius: float, angle: float) -> Variant:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var q := p + (u * cos(angle) + v * sin(angle)) * radius
	return BodyVolume.surface(part, q, _outward(part, q), 0.05, body)


## Outward from the middle of the part's segment (limbs round their axis, the trunk round
## its middle), level in the rest pose.
static func _outward(part: StringName, p: Vector3) -> Vector3:
	var segment := BodyMap.segment_of(part)
	var centre: Vector3 = BodyMap.SEGMENTS[segment][0] if BodyMap.SEGMENTS.has(segment) else BodyMap.PART_BOXES[part][0][0]
	var n := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
	return n.normalized() if n.length() > 0.005 else Vector3.FORWARD


## How the part's mesh on `bone` is widened for the build now (CharacterModel._apply_girth keeps
## its rest scale in the "base" meta): the marks on that bone widen with it, so none stand off a
## slim body or sink into a broad one.
static func fit_of(bone: Node3D) -> Basis:
	var mi := WoundSkin.mesh_of(bone) if bone else null
	if mi == null or not mi.has_meta(&"base"):
		return Basis.IDENTITY
	var base_scale: Vector3 = (mi.get_meta(&"base") as Array)[1]
	return Basis.from_scale(mi.scale / base_scale)


## Rest-pose point `p` on `part`, in the world as the body is drawn now (posed, its build).
func to_world(part: StringName, p: Vector3) -> Vector3:
	var bone := model.part_node(part)
	if bone == null:
		return p
	return bone.global_transform * (fit_of(bone) * (p - BodyVolume.pivot_at(part, body)))


## Holes drawn on `part` (an entry, plus an exit for a round that went through), and the
## voxels of blood on it so far.
func holes_on(part: StringName) -> int:
	var n := 0
	for spot: Dictionary in _spots.values():
		if spot.part == part:
			n += spot.holes.size()
	return n


func blood_on(part: StringName) -> int:
	var n := 0
	for spot: Dictionary in _spots.values():
		if spot.part == part:
			for hole: Dictionary in spot.holes:
				n += hole.blood.size()
	return n


func pool_size() -> int:
	return _pool.size()


## Where each pool cell lies (world), and how many drops are still in the air (tests).
func pool_cells() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cell: Vector2i in _pool:
		out.append(Vector3(_pool[cell].pos))
	return out


func drops_in_air() -> int:
	return _drips.size()


func _update_processing() -> void:
	var bleeding := _spots.values().any(func(s: Dictionary) -> bool: return s.flow > 0.0)
	set_process(bleeding or not _drips.is_empty())


func _process(delta: float) -> void:
	var alive := is_instance_valid(vitals) and not vitals.is_dead()
	var total := 0.0
	for spot: Dictionary in _spots.values():
		if spot.flow <= 0.0 or not alive:
			continue
		total += spot.flow
		spot.lost += spot.flow * delta / 60.0
		if spot.treated:
			spot.seep += spot.flow * delta / 60.0
			_dirty = _dirty or Engine.get_process_frames() % 15 == 0  # the dressing reddening
		_grow(spot)
		if float(spot.arterial) > 0.0:
			_beat(spot, delta)
	if total > 0.0:
		_drip_timer -= delta
		if _drip_timer <= 0.0:
			_drip_timer = randf_range(0.6, 1.4) / (total * DRIPS_PER_L_MIN)
			_spawn_drip()
		_smear_step()
	else:
		_smear_last = null
	_move_drips(delta)
	if _dirty:
		_redraw()
	if _pool_dirty:
		_redraw_pool()
	if total > 0.0 and _now() >= _skin_next:
		paint_skin()  # the soak spreading
	if total <= 0.0 and _drips.is_empty():
		set_process(false)


## Lays the blood this spot has lost so far: alternately a cell further down the trail
## from each hole and one in the soaked patch round it.
func _grow(spot: Dictionary) -> void:
	var target := mini(MAX_CELLS, 4 + int(spot.lost * CELLS_PER_L))
	var rng: RandomNumberGenerator = spot.rng
	var bone := model.part_node(spot.part)
	if bone == null:
		return
	var down: Vector3 = (bone.global_basis.inverse() * Vector3.DOWN).normalized()
	# The soak sags the way down is now; each hole's run follows it, a new run when it turns.
	spot.down = down if not spot.downed else Vector3(spot.down).lerp(down, 0.1).normalized()
	spot.downed = true
	for hole: Dictionary in spot.holes:
		var runs: Array = hole.runs
		if runs.is_empty() or rad_to_deg(Vector3(runs[-1].dir).angle_to(down)) > RUN_TURN_DEG:
			if not runs.is_empty():
				runs[-1].to = spot.lost
			runs.append({"dir": down, "from": spot.lost, "to": -1.0})
			if runs.size() > MAX_RUNS:
				runs.remove_at(1)
	var tries := 0
	while spot.made < target and tries < 8:
		tries += 1
		var hole: Dictionary = spot.holes[spot.made % spot.holes.size()]
		var placed: Variant = null
		if not hole.done and spot.made % 3 != 2:
			placed = _extend_trail(spot.part, hole, down, rng)
		if placed == null:
			var soak := 0.012 + 0.03 * minf(1.0, spot.lost / 0.15)
			placed = _on_skin(spot.part, hole.at, hole.n, soak * sqrt(rng.randf()), rng.randf() * TAU)
		if placed is Vector3:
			var colour := FRESH_COLOUR if rng.randf() < 0.4 else BLOOD_COLOUR
			hole.blood.append([placed + _outward(spot.part, placed) * 0.002, Vector3.ONE * CELL * rng.randf_range(0.9, 1.2), colour])
			spot.made += 1
			_dirty = true


## One cell down the skin from the trail's head, the way gravity runs along the skin here
## (down a standing leg, across a body lying on its side); null when the skin ends.
func _extend_trail(part: StringName, hole: Dictionary, down: Vector3, rng: RandomNumberGenerator) -> Variant:
	if hole.trail >= MAX_TRAIL:
		hole.done = true
		return null
	var head: Vector3 = hole.head
	var n := _outward(part, head)
	var along := down - n * down.dot(n)
	if along.length() < 0.3:  # gravity straight into or out of the skin: it soaks instead
		return null
	along = along.normalized()
	var side := along.cross(n)
	var next: Variant = BodyVolume.surface(part, head + along * CELL + side * CELL * rng.randf_range(-0.5, 0.5), n, 0.05, body)
	if not next is Vector3:
		hole.done = true  # off the end of the part: it drips from here
		return null
	hole.head = next
	hole.trail += 1
	return next


func _spawn_drip() -> void:
	if _drips.size() >= MAX_DRIPS:
		return
	var bleeding := _spots.values().filter(func(s: Dictionary) -> bool: return s.flow > 0.0)
	if bleeding.is_empty():
		return
	var spot: Dictionary = bleeding[randi() % bleeding.size()]
	var bone := model.part_node(spot.part)
	if bone == null:
		return
	# From where its blood gets to lowest (fingertips, a boot heel, under a body lying down).
	var low: Variant = _lowest_point(spot)
	if not low is Vector3:
		return
	var from: Vector3 = low
	var floor_y := _floor_below(from) if is_inside_tree() else from.y - 2.5
	_drips.append({"pos": from, "vel": Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05)), "floor": floor_y, "y0": from.y})


## A round that went through throws a spray out of the exit: drops that fly on along the
## round's line and land on the ground behind.
func _spatter(spot: Dictionary) -> void:
	var bone := model.part_node(spot.part)
	if bone == null or spot.holes.size() < 2 or not is_inside_tree():
		return
	var entry: Dictionary = spot.holes[0]
	var exit: Dictionary = spot.holes[1]
	var from := to_world(spot.part, exit.at)
	var dir: Vector3 = (to_world(spot.part, exit.at) - to_world(spot.part, entry.at)).normalized()
	var floor_y := _floor_below(from)
	var rng: RandomNumberGenerator = spot.rng
	for i in SPATTER_DROPS:
		if _drips.size() >= MAX_DRIPS:
			break
		var spread := Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.2, 0.35), rng.randf_range(-0.35, 0.35))
		var speed := rng.randf_range(0.8, 2.6)
		_drips.append({"pos": from, "vel": (dir + spread).normalized() * speed, "floor": floor_y, "speck": true})
	if spot.part in [Vitals.HEAD, Vitals.FACE]:
		for i in BRAIN_DROPS:
			if _drips.size() >= MAX_DRIPS + BRAIN_DROPS:
				break  # (two head shots close together: the drip mesh holds this many, P2017)
			var spread := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.25, 0.45), rng.randf_range(-0.5, 0.5))
			_drips.append({"pos": from, "vel": (dir + spread).normalized() * rng.randf_range(1.0, 3.2), "floor": floor_y, "speck": true,
				"brain": true, "size": BRAIN_SIZE * rng.randf_range(0.6, 1.4)})
	set_process(true)


## The ground under world point `from` (2.5 m down at most): the world only (WORLD_MASK), never
## this body. Captain, 2026-10-14 ("floating blood"): it met anything but this body's capsule, so
## its own plates and pack, its ragdoll's parts and other bodies too, and a drop that fell that
## far "landed" there as a pool cell left hanging in the air once the body fell or moved
## (0.45-0.9 m up, R0950-R0953). What a drop really meets on the way down (a person, an item, a
## vehicle) is _surface_between's, and it rides on that.
## A drop that starts a little under the floor's surface (the lowest skin of a body lying on
## it, pressed in by the ragdoll's contact) is looked up again from FLOOR_LOOK_UP_M above: a ray
## starting inside the ground meets nothing, and those drops fell the whole 2.5 m and lay as
## pool cells under the yard (CI, interaction "his blood is on the ground": off it -2.50).
func _floor_below(from: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.5, WORLD_MASK, _own_rids())
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		query.from = from + Vector3.UP * FLOOR_LOOK_UP_M
		hit = space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else from.y - 2.5


func _move_drips(delta: float) -> void:
	if _drips.is_empty():
		if _drip_mesh and _drip_mesh.multimesh.visible_instance_count != 0:
			_drip_mesh.multimesh.visible_instance_count = 0
		return
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var landed: Array = []  # [drop, hit] (hit empty: it reached its floor)
	var lost: Array = []  # drops that found no ground at all: gone, never left hanging
	for d: Dictionary in _drips:
		var was: Vector3 = d.pos
		if d.get("slide", false):
			d.vel = Vector3.DOWN * SLIDE_MPS  # running down a wall, not falling
		else:
			d.vel += Vector3.DOWN * 9.8 * delta
		d.pos += d.vel * delta
		var hit := _surface_between(space, was, d.pos, d.get("skip", [])) if space else {}
		if hit.is_empty() and d.pos.y <= d.floor and space:
			# Its floor was found under where it started; where it is now the ground can be lower
			# (it flew off a ledge, a roof, a truck bed): it falls on to that, or goes if there's none.
			var ground := _ground_hit(Vector3(d.pos.x, float(d.floor) + FLOOR_LOOK_UP_M, d.pos.z))
			if ground.is_empty():
				lost.append(d)
				continue
			if float(ground.position.y) < float(d.floor) - 0.02:
				d.floor = float(ground.position.y)
				continue
			hit = ground
		if not hit.is_empty() or d.pos.y <= d.floor:
			landed.append([d, hit])
	for d: Dictionary in lost:
		_drips.erase(d)
	for pair: Array in landed:
		var d: Dictionary = pair[0]
		var hit: Dictionary = pair[1]
		_drips.erase(d)
		var rider: Node3D = Charges.rider_of(hit.collider) if not hit.is_empty() and hit.collider is Node else null
		if rider == null and not hit.is_empty() and absf((hit.normal as Vector3).y) < WALL_NORMAL_Y and not d.get("slide", false):
			# A wall (Captain, 2026-10-16: "chunks and stuff slide down walls if they hit"): a stain
			# where it struck, then it runs down the wall to the ground and lands there.
			_add_stain(hit.position, hit.normal, float(d.get("size", DRIP_SIZE)) * (1.6 if d.get("brain", false) else 1.0), d.get("brain", false))
			var slid := d.duplicate()
			slid["pos"] = (hit.position as Vector3) + (hit.normal as Vector3) * 0.01
			slid["slide"] = true
			_drips.append(slid)
			continue
		var at := Vector3(d.pos.x, hit.position.y if not hit.is_empty() else d.floor, d.pos.z)
		var normal: Vector3 = hit.normal if not hit.is_empty() else Vector3.UP
		if d.get("brain", false):
			if rider:
				_stain(rider, hit.position, d.vel, true)
			else:
				_add_chunk(at, float(d.size), normal)
			continue
		if rider:
			if not _stain(rider, hit.position, d.vel, not d.get("speck", false)):
				_fall_past(d, hit)  # nothing there takes a stain: it falls on past
			continue
		_add_pool(at, d.get("speck", false))
		if not d.get("speck", false) and float(d.get("y0", at.y)) - at.y > SPLASH_FALL_M:
			_splash(at)
	if _drip_mesh == null:
		_drip_mesh = _world_multimesh("Drips", MAX_DRIPS + BRAIN_DROPS)
	var mm := _drip_mesh.multimesh
	while _drips.size() > mm.instance_count:
		_drips.pop_front()  # never past the mesh (P2017: 64 drips, 52 slots)
	for i in _drips.size():
		var brain: bool = _drips[i].get("brain", false)
		# A falling drop drawn out along its fall (a bead, then a streak).
		var stretch := 1.0 if brain else clampf(1.2 + absf(float(_drips[i].vel.y)) * 0.25, 1.2, 2.6)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(_drips[i].size) if brain else Vector3(1, stretch, 1) * DRIP_SIZE), _drips[i].pos))
		mm.set_instance_color(i, BRAIN_COLOUR if brain else FRESH_COLOUR)
	mm.visible_instance_count = _drips.size()


## The world's ground straight under `from` (2.5 m at most): {"position", "normal"} or {}.
func _ground_hit(from: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.5, WORLD_MASK, _own_rids())
	return get_world_3d().direct_space_state.intersect_ray(query)


## A drop that met something that takes no stain (no mesh near where it struck) falls on past it,
## that thing left out of its way.
func _fall_past(d: Dictionary, hit: Dictionary) -> void:
	if int(d.get("past", 0)) >= 2:
		return
	var next := d.duplicate()
	next["past"] = int(d.get("past", 0)) + 1
	next["pos"] = (hit.position as Vector3) + Vector3.DOWN * 0.01
	var skip: Array = next.get("skip", [])
	skip = skip.duplicate()
	skip.append((hit.collider as CollisionObject3D).get_rid() if hit.collider is CollisionObject3D else RID())
	next["skip"] = skip
	_drips.append(next)


## A drop falling far splashes: a few specks round where it landed.
func _splash(at: Vector3) -> void:
	for i in SPLASH_SPECKS:
		var a := randf() * TAU
		var r := randf_range(0.03, 0.07)
		var p := at + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var ground: Variant = _ground_at(Vector2i(roundi(p.x / POOL_CELL), roundi(p.z / POOL_CELL)), at.y)
		if ground != null:
			_add_pool(Vector3(p.x, float(ground), p.z), true)


## The first thing a drop moving from `from` to `to` hits ({} for none): the world, another
## person (a hitbox or a body), an item or armour. Never this body.
func _surface_between(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, skip: Array = []) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var exclude := _own_rids()
	if not skip.is_empty():
		exclude = exclude.duplicate()
		for rid: RID in skip:
			exclude.append(rid)
	var query := PhysicsRayQueryParameters3D.create(from, to, LAND_MASK, exclude)
	query.collide_with_areas = true
	return space.intersect_ray(query)


## This body's own collision (its capsule, hitboxes and armour): blood never lands on it.
func _own_rids() -> Array[RID]:
	var own := model.get_parent() as CollisionObject3D
	if own == null:
		return []
	if _own_rids_cache.is_empty() or _own_rids_children != own.get_child_count():
		_own_rids_cache = [own.get_rid()]
		for n: Node in own.find_children("*", "CollisionObject3D", true, false):
			_own_rids_cache.append((n as CollisionObject3D).get_rid())
		_own_rids_children = own.get_child_count()
	return _own_rids_cache


## A drop landing on something that moves (a person, their helmet or pack, an item, a vehicle)
## stains it (Captain, 2026-10-26: blood "stains those items" instead of floating or stacking on
## them): the mesh of it nearest where it struck takes a BloodStain, painted into its own voxels,
## going wherever it goes. On a person, their nearest part or the gear on it. False when there's
## no mesh there to stain (the drop falls on past it).
func _stain(rider: Node3D, at: Vector3, fall: Vector3, big: bool) -> bool:
	var holder: Node = rider
	var soldier := rider as Soldier if rider is Soldier else Ragdoll.body_of(rider)
	if soldier == null and rider.get_parent() is Soldier:
		soldier = rider.get_parent() as Soldier
	if soldier and soldier.model:
		holder = soldier.model  # its parts and the gear hung on them, not its hitboxes
	var mi := BloodStain.mesh_near(holder, at)
	if mi == null:
		return false
	var stain := mi.get_node_or_null(^"BloodStain") as BloodStain
	if stain == null:
		_stained = stained()
		if _stained.size() >= MAX_STAINED:
			return true  # (the budget: the drop goes)
		stain = BloodStain.on(mi)
		if stain == null:
			return false
		_stained.append(stain)
	stain.add(at, fall, big)
	return true


## What this body's blood has stained (tests).
func stained() -> Array[BloodStain]:
	var out: Array[BloodStain] = []
	for x: Variant in _stained:
		if is_instance_valid(x):
			out.append(x)
	return out


## The ground (the world only) under pool cell `cell` within POOL_STEP of height `y`, or null
## (past an edge or up a wall).
func _ground_at(cell: Vector2i, y: float) -> Variant:
	var g := _ground_under(Vector3(cell.x * POOL_CELL, y, cell.y * POOL_CELL), POOL_STEP)
	return g.position.y if not g.is_empty() else (y if not is_inside_tree() else null)


## The world's ground under `p` within `step` above or below it: {"position", "normal"}, or {}.
func _ground_under(p: Vector3, step: float) -> Dictionary:
	if not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * step, p + Vector3.DOWN * step, WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query)


## A drop landing on the ground. A drip adds to the pool cell there, and a full cell spills
## on outward (away from where the first drip landed), so the pool spreads out from under
## the body and shows past it. A drop of spatter only leaves a speck. Each cell lies on its own
## ground, tilted to it (a slope, a step): where the ground under the cell's middle is, else where
## the drop landed (a cell over an edge).
func _add_pool(at: Vector3, speck := false) -> void:
	var cell := Vector2i(roundi(at.x / POOL_CELL), roundi(at.z / POOL_CELL))
	if not speck and _pool_centre == null:
		_pool_centre = cell
	for i in (1 if speck else 16):
		if not _pool.has(cell):
			if _pool.size() >= MAX_POOL:
				return
			var g := _ground_under(Vector3(cell.x * POOL_CELL, at.y, cell.y * POOL_CELL), POOL_STEP)
			var pos := Vector3(cell.x * POOL_CELL, at.y, cell.y * POOL_CELL)
			var n := Vector3.UP
			if not g.is_empty():
				pos = g.position
				n = g.normal
			elif i == 0 and is_inside_tree():
				var here := _ground_under(at, POOL_STEP)  # its middle over an edge: where it landed
				if here.is_empty():
					return
				pos = here.position
				n = here.normal
			elif is_inside_tree():
				return  # a spill past an edge stops rather than hang in the air
			var life: Vector2 = SPECK_LIFE_S if speck else POOL_LIFE_S
			_pool[cell] = {"y": pos.y, "pos": pos, "n": n, "amount": 0, "until": _now() + randf_range(life.x, life.y)}
		if _pool[cell].amount < (1 if speck else 2):
			_pool[cell].amount += 1
			if not speck:
				_pool[cell].until = maxf(float(_pool[cell].until), _now() + POOL_LIFE_S.x)  # a pool now, not a speck
			_pool_dirty = true
			return
		if speck:
			return
		var centre: Vector2i = _pool_centre
		var outward: Array[Vector2i] = []
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if Vector2(cell + step - centre).length() >= Vector2(cell - centre).length():
				outward.append(step)
		cell += outward[randi() % outward.size()]


## Flat on ground whose normal is `n`.
static func _on_ground(n: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.UP, n.normalized())) if n.normalized().dot(Vector3.UP) < 0.9999 else Basis.IDENTITY


func _redraw_pool() -> void:
	_pool_dirty = false
	if _pool_mesh == null:
		_pool_mesh = _world_multimesh("Pool", MAX_POOL)
	var mm := _pool_mesh.multimesh
	var i := 0
	for cell: Vector2i in _pool:
		var c: Dictionary = _pool[cell]
		# A lone drop is a speck; a cell that keeps getting blood fills out into the pool.
		var h: float = POOL_HEIGHT * (0.5 + 0.4 * c.amount)
		var w: float = POOL_CELL * [0.0, 0.45, 1.0][mini(c.amount, 2)]
		var n: Vector3 = c.get("n", Vector3.UP)
		var pos: Vector3 = Vector3(c.pos) + n * h * 0.5
		mm.set_instance_transform(i, Transform3D(_on_ground(n) * Basis.from_scale(Vector3(w * 1.02, h, w * 1.02)), pos))
		mm.set_instance_color(i, BLOOD_COLOUR if c.amount > 1 else FRESH_COLOUR)
		i += 1
	mm.visible_instance_count = i


## Ground blood whose ground went or moved (a crater blown in it, a crate or door gone from under
## it): each tick SETTLE_RAYS cells looked at again, in turn. One whose ground is still there stays;
## moved, it lies on the new ground (within SETTLE_DROP under it); gone, it goes.
func _settle() -> void:
	if not is_inside_tree():
		return
	var cells: Array = []
	for cell: Vector2i in _pool:
		cells.append(["pool", cell])
	for c: Dictionary in _smear:
		cells.append(["smear", c])
	for c: Dictionary in _chunks:
		cells.append(["chunk", c])
	if cells.is_empty():
		return
	var moved := {"pool": false, "smear": false, "chunk": false}
	var gone: Array = []
	for k in mini(SETTLE_RAYS, cells.size()):
		var entry: Array = cells[(_settle_at + k) % cells.size()]
		var rec: Dictionary = _pool[entry[1]] if entry[0] == "pool" else entry[1]
		var key := "ground" if entry[0] != "pool" else "pos"
		var at: Vector3 = rec.get(key, rec.get("pos"))
		var still := _ground_under(at, SETTLE_SLACK)
		if not still.is_empty():
			continue
		var lower := _ground_hit(at + Vector3.UP * SETTLE_SLACK)
		if lower.is_empty() or at.y - float(lower.position.y) > SETTLE_DROP:
			gone.append(entry)
			continue
		var delta: Vector3 = Vector3(lower.position) - at
		if entry[0] == "pool":
			rec.pos = lower.position
			rec.y = float(lower.position.y)
			rec.n = lower.normal
		else:
			rec.pos = Vector3(rec.pos) + delta
			rec.ground = lower.position
			rec.n = lower.normal
		moved[entry[0]] = true
	_settle_at = (_settle_at + SETTLE_RAYS) % maxi(cells.size(), 1)
	for entry: Array in gone:
		if entry[0] == "pool":
			_pool.erase(entry[1])
		elif entry[0] == "smear":
			_smear.erase(entry[1])
		else:
			_chunks.erase(entry[1])
		moved[entry[0]] = true
	if moved.pool:
		_redraw_pool()
	if moved.smear:
		_redraw_smear()
	if moved.chunk:
		_redraw_chunks()


## Everything on the body: holes, blood and dressings, one MultiMesh per bone.
## BodyDeform cut a part through: its marks past the cut go (_redraw).
func on_reshaped() -> void:
	if is_instance_valid(model):
		_redraw()


func _redraw() -> void:
	_dirty = false
	var per_bone := {}  # bone -> Array of [local position, size, colour(, basis)]: the coarse holes and blood
	var dressed := {}  # bone -> the same, for dressings
	var deform := model.get_node_or_null(^"BodyDeform") as BodyDeform
	for spot: Dictionary in _spots.values():
		var bone := model.part_node(spot.part)
		if bone == null:
			continue
		var pivot := BodyVolume.pivot_at(spot.part, body)
		var cells: Array = per_bone.get(bone, [])
		var dress: Array = dressed.get(bone, [])
		# A part cut through: only the marks on what's left of it (none hang in the air where
		# the limb was).
		var left: Variant = deform.cut_bounds(BodyDeform._bone_part(spot.part)) if deform else null
		if left is AABB:
			var kept: Array[Dictionary] = []
			for hole: Dictionary in spot.holes:
				if (left as AABB).has_point(Vector3(hole.at) - pivot):
					kept.append(hole)
			if kept.is_empty():
				per_bone[bone] = cells
				dressed[bone] = dress
				continue
			spot = spot.duplicate()
			spot.holes = kept
		for hole: Dictionary in spot.holes:
			for b: Array in hole.blood:
				if left is AABB and not (left as AABB).has_point(b[0] - pivot):
					continue  # a trail run on past the cut
				cells.append([b[0] - pivot, b[1], DRIED_COLOUR if spot.flow <= 0.0 and spot.treated else b[2]])
			if spot.treated and spot.look != &"":
				if hole.get("dressed_as") != spot.look:  # built once: a redraw comes with each new blood cell
					hole["dressed_as"] = spot.look
					hole["dressing"] = _dressing(spot.part, hole, pivot, spot.look)
				dress.append_array(_bloodied(spot, hole, pivot))
			else:
				for m: Array in hole.marks:
					cells.append([m[0] - pivot, m[1], m[2]])
		per_bone[bone] = cells
		dressed[bone] = dress
	_draw_on_bones(_bone_meshes, per_bone, "WoundMark", true)
	_draw_on_bones(_dress_meshes, dressed, "WoundDressing", false)


## Draws `per_bone` (bone -> cells) on each bone, in `meshes` (bone -> its MultiMeshInstance3D,
## named `node_name`), widened with the part's build (fit_of). `far`: drawn only past the painted
## skin's range (WoundSkin.RANGE_M), up to FAR_M.
func _draw_on_bones(meshes: Dictionary, per_bone: Dictionary, node_name: String, far: bool) -> void:
	for bone: Node3D in meshes.keys():
		if not per_bone.has(bone) and is_instance_valid(meshes[bone]):
			meshes[bone].multimesh.visible_instance_count = 0
	for bone: Node3D in per_bone:
		var cells: Array = per_bone[bone]
		var inst: MultiMeshInstance3D = meshes.get(bone)
		if cells.is_empty() and inst == null:
			continue
		if inst == null or not is_instance_valid(inst) or inst.multimesh.instance_count < cells.size():
			if inst and is_instance_valid(inst):
				inst.name = node_name + "Old"  # (the new one takes its name now, not next frame)
				inst.queue_free()
			inst = _multimesh_instance(maxi(64, cells.size() * 2))
			inst.name = node_name
			inst.layers = model.render_layers
			if far:
				inst.visibility_range_begin = WoundSkin.RANGE_M
				inst.visibility_range_end = FAR_M
			bone.add_child(inst, true)
			meshes[bone] = inst
		inst.transform = Transform3D(fit_of(bone), Vector3.ZERO)
		var mm := inst.multimesh
		var at := PackedVector3Array()
		for i in cells.size():
			var basis: Basis = cells[i][3] if cells[i].size() > 3 else Basis.IDENTITY
			mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(cells[i][1]), cells[i][0]))
			mm.set_instance_color(i, cells[i][2])
			at.append(cells[i][0])
		mm.visible_instance_count = cells.size()
		inst.set_meta(&"cells", at)  # where each is (drawn_cells: a headless renderer keeps no transforms)


## Keeps what's drawn on the bones on the body as it's drawn now: the build's width (set after the
## marks, or changed), the hand's pose, a carved part's mesh.
func _refit() -> void:
	for meshes: Dictionary in [_bone_meshes, _dress_meshes]:
		for bone: Node3D in meshes:
			if is_instance_valid(bone) and is_instance_valid(meshes[bone]):
				(meshes[bone] as Node3D).transform = Transform3D(fit_of(bone), Vector3.ZERO)
	if devices:
		devices.refit()
	if skin and skin.sync():
		paint_skin()


## The dressing over `hole` as bloodied now: from the middle out as far as the blood still coming
## under it has seeped (SEEP_*), wet while it comes; and, put on a wound that had bled, blood at
## its edges (EDGE_*), dry.
func _bloodied(spot: Dictionary, hole: Dictionary, pivot: Vector3) -> Array:
	var cells: Array = hole.dressing
	var seep := float(spot.seep)
	var edged := float(spot.dressed_lost) >= EDGE_FROM_L
	if seep <= 0.0 and not edged:
		return cells
	var reach := minf(SEEP_BASE_M + SEEP_PER_SQRT_L * sqrt(seep), SEEP_MAX_M) if seep > 0.0 else 0.0
	var at: Vector3 = Vector3(hole.at) - pivot
	var far := 0.0
	for c: Array in cells:
		far = maxf(far, Vector3(c[0]).distance_to(at))
	var out: Array = []
	var wet: bool = spot.flow > 0.0
	for c: Array in cells:
		var d := Vector3(c[0]).distance_to(at)
		var salt := float(hash(c[0]) % 1000) / 1000.0
		var colour: Color = c[2]
		if d < reach * (0.75 + 0.5 * salt):
			colour = (FRESH_COLOUR if salt < 0.5 else BLOOD_COLOUR) if wet else DRIED_COLOUR
		elif edged and d > far * 0.7 and salt < EDGE_SHARE:
			colour = Color(c[2]).lerp(DRIED_COLOUR, 0.75)
		else:
			out.append(c)
			continue
		var cell := c.duplicate()
		cell[2] = colour
		out.append(cell)
	return out


## What covers a treated hole (`look`, LOOKS): on a limb a wrap round it, on the trunk or head
## a pad. A pressure bandage: a cream elastic wrap, its weave in bands, the pressure bar over the
## hole. Gauze: white, packed so it bulges out of the hole, a loose tail. A chest seal: a square
## clear patch with a dark border and its valve. A plain dressing otherwise.
func _dressing(part: StringName, hole: Dictionary, pivot: Vector3, look: StringName) -> Array:
	var at: Vector3 = hole.at
	var n: Vector3 = hole.n
	var basis := BodyDevices._facing(n)
	var limb := BodyMap.segment_of(part) == part
	match look:
		&"seal":
			var cells: Array = []
			var p := at + n * 0.004 - pivot
			for gx in range(-10, 11):  # 10.5 cm square, the border 1 cm wide
				for gy in range(-10, 11):
					var edge := absi(gx) > 8 or absi(gy) > 8
					if not edge and (gx % 2 != 0 or gy % 2 != 0):
						continue  # (the clear middle is laid in 1 cm cells)
					var size := Vector3(0.005, 0.005, 0.004) if edge else Vector3(0.0105, 0.0105, 0.003)
					cells.append([p + basis.x * gx * 0.005 + Vector3.UP * gy * 0.005, size, SEAL_BORDER if edge else SEAL_COLOUR, basis])
			cells.append([p + n * 0.005 + basis.x * 0.02, Vector3(0.015, 0.015, 0.008), SEAL_VALVE, basis])  # the vent
			cells.append([p + n * 0.009 + basis.x * 0.02, Vector3(0.005, 0.005, 0.004), SEAL_BORDER, basis])
			return _conform(part, cells, at, n, pivot)
		&"bandage", &"gauze":
			var bandage := look == &"bandage"
			var cells: Array = []
			if limb:
				var rows := 16 if bandage else 12  # 8 or 6 cm wide
				for row in rows:
					var y := at.y + (row - rows * 0.5 + 0.5) * 0.005
					var shade := (BANDAGE_WEAVE if row % 4 == 0 else BANDAGE_COLOUR) if bandage else (GAUZE_SHADE if row % 3 == 0 else GAUZE_COLOUR)
					for r: Array in devices._ring(part, y, 0.01):
						var m: Vector3 = r[1]
						cells.append([Vector3(r[0]) + m * 0.006 - pivot, Vector3(0.0105, 0.005, 0.005), shade, BodyDevices._facing(m)])
			else:
				var half := 9 if bandage else 7
				for gx in range(-half, half + 1, 2):
					for gy in range(-half, half + 1, 2):
						var shade := (BANDAGE_WEAVE if gy % 4 == 0 else BANDAGE_COLOUR) if bandage else (GAUZE_SHADE if (gx + gy) % 4 == 0 else GAUZE_COLOUR)
						cells.append([at + n * 0.006 + basis.x * gx * 0.005 + Vector3.UP * gy * 0.005 - pivot, Vector3(0.0105, 0.0105, 0.005), shade, basis])
			if not limb:
				cells = _conform(part, cells, at, n, pivot)
			if bandage:  # the pressure bar over the hole, and the closure bar beside it
				cells.append([at + n * 0.011 - pivot, Vector3(0.03, 0.012, 0.006), PRESSURE_BAR, basis])
				cells.append([at + n * 0.011 + basis.x * 0.03 - pivot, Vector3(0.008, 0.02, 0.005), PRESSURE_BAR.darkened(0.2), basis])
			else:  # packed: it bulges out of the hole, a tail hanging loose
				for i in 5:
					cells.append([at + n * (0.011 + (i % 2) * 0.004) + basis.x * ((i - 2) * 0.005) + Vector3.UP * ((i % 3) - 1) * 0.005 - pivot,
						Vector3(0.006, 0.006, 0.006), GAUZE_COLOUR, basis])
				for i in 4:
					cells.append([at + n * 0.01 + basis.x * 0.01 - Vector3.UP * (0.02 + i * 0.006) - pivot, Vector3(0.01, 0.006, 0.004), GAUZE_SHADE, basis])
			return cells
	if limb:  # a plain dressing wrapped round the limb, on the skin all round (a box stood off it)
		var cells: Array = []
		for row in 12:
			var y := at.y + (row - 5.5) * 0.005
			for r: Array in devices._ring(part, y, 0.01):
				var m: Vector3 = r[1]
				cells.append([Vector3(r[0]) + m * 0.004 - pivot, Vector3(0.0105, 0.005, 0.004), DRESSING_COLOUR if row % 5 else BANDAGE_WEAVE, BodyDevices._facing(m)])
		return cells
	var pad: Array = []
	for gx in range(-7, 8, 2):
		for gy in range(-7, 8, 2):
			pad.append([at + n * 0.004 + basis.x * gx * 0.005 + Vector3.UP * gy * 0.005 - pivot, Vector3(0.0105, 0.0105, 0.004), DRESSING_COLOUR, basis])
	return _conform(part, pad, at, n, pivot)


## A flat patch of `cells` (bone space) laid over the hole at `at` facing `n`, each cell moved onto
## the skin under it, as far off it as it was off the hole's plane: a pad or seal on the curve of
## the chest or a shoulder follows it instead of standing off at its edges. Cells past the body's
## edge go.
func _conform(part: StringName, cells: Array, at: Vector3, n: Vector3, pivot: Vector3) -> Array:
	var out: Array = []
	for c: Array in cells:
		var q: Vector3 = Vector3(c[0]) + pivot
		var off := (q - at).dot(n)
		var s: Variant = BodyVolume.surface(part, q - n * off, n, 0.08, body)
		if not s is Vector3:
			continue
		var moved := c.duplicate()
		moved[0] = Vector3(s) + n * off - pivot
		out.append(moved)
	return out


func _world_multimesh(node_name: String, count: int) -> MultiMeshInstance3D:
	var inst := _multimesh_instance(count)
	inst.name = node_name
	inst.top_level = true
	add_child(inst)
	inst.global_transform = Transform3D.IDENTITY
	return inst


static func _multimesh_instance(count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = count
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.45
	inst.material_override = _material
	return inst


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Brain matter landed at `at` (BRAIN_DROPS): lies there CHUNK_LIFE_S.
func _add_chunk(at: Vector3, size: float, normal := Vector3.UP) -> void:
	if _chunks.size() >= MAX_CHUNKS:
		_chunks.pop_front()
	_chunks.append({"pos": at + normal * size * 0.3, "ground": at, "n": normal, "size": size, "colour": BRAIN_COLOUR if randf() < 0.65 else BRAIN_DARK,
		"until": _now() + randf_range(CHUNK_LIFE_S.x, CHUNK_LIFE_S.y)})
	_redraw_chunks()


func _redraw_chunks() -> void:
	if _chunk_mesh == null:
		_chunk_mesh = _world_multimesh("Brain", MAX_CHUNKS)
	var mm := _chunk_mesh.multimesh
	for i in _chunks.size():
		var c: Dictionary = _chunks[i]
		mm.set_instance_transform(i, Transform3D(_on_ground(c.get("n", Vector3.UP)) * Basis.from_scale(Vector3(1.0, 0.6, 1.0) * float(c.size)), c.pos))
		mm.set_instance_color(i, c.colour)
	mm.visible_instance_count = _chunks.size()


## What lay on the ground long enough goes: specks, pools, brain (the *_LIFE_S lifetimes).
func _expire() -> void:
	var now := _now()
	var gone := false
	for cell: Vector2i in _pool.keys():
		if float(_pool[cell].get("until", INF)) <= now:
			_pool.erase(cell)
			gone = true
	if gone:
		if _pool.is_empty():
			_pool_centre = null
		_redraw_pool()
	var before := _chunks.size()
	_chunks = _chunks.filter(func(c: Dictionary) -> bool: return float(c.until) > now)
	if _chunks.size() != before:
		_redraw_chunks()
	var smears_before := _smear.size()
	_smear = _smear.filter(func(c: Dictionary) -> bool: return float(c.until) > now)
	if _smear.size() != smears_before:
		_redraw_smear()
	if _hand_blood > 0.0 and now >= _hand_until:
		_hand_blood = 0.0
		_hand_cells = [[], []]
		_redraw_hands()
	elif _hand_blood > 0.0 and now >= _hand_wet_until and now - EXPIRE_TICK_S < _hand_wet_until:
		_redraw_hands()  # dried
	_settle()
	if not _spots.is_empty() or not bruise_records().is_empty():
		paint_skin()  # drying, bruises turning
	var stains_before := _stains.size()
	_stains = _stains.filter(func(st: Dictionary) -> bool: return float(st.until) > now)
	if _stains.size() != stains_before:
		_redraw_stains()


## Wall stains (where a drop or chunk struck a wall before running down it), lying
## SPECK_LIFE_S like the small blood: {"pos", "normal", "size", "colour", "until"}.
const WALL_NORMAL_Y := 0.5   # a surface steeper than this is a wall
const SLIDE_MPS := 0.5
const MAX_STAINS := 60
var _stains: Array[Dictionary] = []
var _stain_mesh: MultiMeshInstance3D


func _add_stain(at: Vector3, normal: Vector3, size: float, brain: bool) -> void:
	if _stains.size() >= MAX_STAINS:
		_stains.pop_front()
	_stains.append({"pos": at + normal * 0.004, "normal": normal, "size": maxf(size * 2.2, CELL),
		"colour": BRAIN_DARK if brain else FRESH_COLOUR, "until": _now() + randf_range(SPECK_LIFE_S.x, SPECK_LIFE_S.y)})
	_redraw_stains()


func _redraw_stains() -> void:
	if _stain_mesh == null:
		_stain_mesh = _world_multimesh("WallStains", MAX_STAINS)
	var mm := _stain_mesh.multimesh
	for i in _stains.size():
		var st: Dictionary = _stains[i]
		var n: Vector3 = st.normal
		var basis := Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)  # flat on the wall
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(float(st.size), float(st.size) * 1.4, 0.003)), st.pos))
		mm.set_instance_color(i, st.colour)
	mm.visible_instance_count = _stains.size()


# --- Drag smear ---------------------------------------------------------------------------

## The smear cells on the ground now (tests).
func smear_size() -> int:
	return _smear.size()


## Lying (dragged, or crawling) and bleeding: each SMEAR_STEP the body travels, a streak of
## blood on the ground under the lowest bleeding hole, drawn out along the way it went. Travel is
## the dragger's (or, crawling, the body's own), never the pose's sway.
func _smear_step() -> void:
	var torso := model.part_node(Vitals.CHEST)
	if torso == null or not is_inside_tree():
		return
	var carry := model.carry_shown()
	var dragged: bool = carry.get("mode", &"") == CharacterModel.DRAGGED
	var mover: Node3D = carry.get("body") if dragged and carry.get("body") is Node3D else model.get_parent() as Node3D
	if mover == null:
		return
	var pos := mover.global_position
	if _smear_last == null:
		_smear_last = pos
		return
	var move := pos - Vector3(_smear_last)
	move.y = 0.0
	var moved := move.length()
	if moved < SMEAR_STEP:
		return
	_smear_last = pos
	if moved > 1.0 or not (dragged or torso.global_basis.y.normalized().dot(Vector3.UP) < 0.5):
		return
	var low := Vector3.INF
	for spot: Dictionary in _spots.values():
		if spot.flow <= 0.0:
			continue
		var bone := model.part_node(spot.part)
		if bone == null:
			continue
		for hole: Dictionary in spot.holes:
			var p := to_world(spot.part, hole.head)
			if p.y < low.y:
				low = p
	if low == Vector3.INF:
		return
	var floor_y := _floor_below(low)
	if low.y - floor_y > SMEAR_REACH:
		return
	if _smear.size() >= MAX_SMEAR:
		_smear.pop_front()
	var total := 0.0
	for spot: Dictionary in _spots.values():
		total += spot.flow
	# On the ground under the streak's middle, tilted to it (a slope, a kerb).
	var mid := Vector3(low.x, floor_y, low.z) - move * 0.5
	var g := _ground_under(mid, SMEAR_REACH)
	if g.is_empty():
		return
	_smear.append({"pos": g.position, "ground": g.position, "n": g.normal, "dir": move / moved, "length": moved + 0.015,
		"width": clampf(0.025 + total * 0.03, 0.025, 0.06), "colour": FRESH_COLOUR if randf() < 0.5 else BLOOD_COLOUR,
		"until": _now() + randf_range(POOL_LIFE_S.x, POOL_LIFE_S.y)})
	_redraw_smear()


func _redraw_smear() -> void:
	if _smear_mesh == null:
		_smear_mesh = _world_multimesh("Smear", MAX_SMEAR)
	var mm := _smear_mesh.multimesh
	for i in _smear.size():
		var c: Dictionary = _smear[i]
		var n: Vector3 = c.get("n", Vector3.UP)
		var d: Vector3 = Vector3(c.dir) - n * Vector3(c.dir).dot(n)  # along the ground
		d = d.normalized() if d.length() > 0.001 else n.cross(Vector3.RIGHT).normalized()
		var basis := Basis(n.cross(d).normalized(), n, d)
		mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(float(c.width), POOL_HEIGHT * 0.6, float(c.length))),
			Vector3(c.pos) + n * POOL_HEIGHT * 0.3))
		mm.set_instance_color(i, c.colour)
	mm.visible_instance_count = _smear.size()


# --- Blood on the hands -------------------------------------------------------------------

## Blood voxels on the right or left hand now (tests).
func hand_blood(right: bool) -> int:
	return (_hand_cells[0 if right else 1] as Array).size()


## While this body's treat clip plays (replicated action_net, so on every peer) on a wound that
## is bleeding or has bled, blood builds up on its hands. On yourself ("kneel" off), a wound of
## your own within HAND_REACH of where the hands work; on someone else, the body nearest that
## point (the hands' point is held within arm's reach, so it can fall short of the wound).
func _check_hands() -> void:
	if is_instance_valid(model):
		_refit()
		if _hand_drawn_models != _hand_models():
			_redraw_hands()  # the hands' pose changed: the blood goes on the hands as drawn now
	if not is_instance_valid(model) or model.action_shown() != CharacterModel.TREAT or not is_inside_tree():
		return
	var at: Variant = model.action_net.get("at")
	if not at is Vector3:
		return
	var work := model.to_global(at)
	var bloody := false
	if not model.action_net.get("kneel", false):
		bloody = bloody_near(work, HAND_REACH)
	else:
		var nearest: WoundMarks = null
		var best := HAND_PATIENT_M
		for marks: Node in get_tree().get_nodes_in_group(&"wound_marks"):
			if marks == self or not marks is WoundMarks or not is_instance_valid((marks as WoundMarks).model):
				continue
			var d := (marks as WoundMarks).model.global_position.distance_to(work)
			if d < best:
				best = d
				nearest = marks
		bloody = nearest != null and nearest.bloody_near(work, INF)
	if bloody:
		_hand_blood += HAND_TICK_S
		_hand_until = _now() + HAND_LIFE_S
		_hand_wet_until = _now() + HAND_DRY_S
		_grow_hands()


## A wound that bleeds now, or has bled onto the skin, within `reach` of world point `p`.
func bloody_near(p: Vector3, reach: float) -> bool:
	for spot: Dictionary in _spots.values():
		var bloody: bool = spot.flow > 0.0 or spot.holes.any(func(h: Dictionary) -> bool: return not (h.blood as Array).is_empty())
		if not bloody:
			continue
		var bone := model.part_node(spot.part)
		if bone == null:
			continue
		for hole: Dictionary in spot.holes:
			if to_world(spot.part, hole.at).distance_to(p) <= reach:
				return true
	return false


func _grow_hands() -> void:
	var target := mini(HAND_CELLS, 3 + int(_hand_blood * 3.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_instance_id()) + int(_hand_blood * 10.0)
	for i in 2:
		var part := Vitals.FOREARM_R if i == 0 else Vitals.FOREARM_L
		var box: Array = BodyMap.PART_BOXES[part][0]
		var bottom: float = box[0].y - box[1].y * 0.5
		var cells: Array = _hand_cells[i]
		while cells.size() < target:
			var a := rng.randf() * TAU
			# Where on the hand (a way round it and a height), laid on the hand as it's drawn.
			cells.append([Vector3(sin(a), 0.0, -cos(a)), bottom + rng.randf_range(0.005, 0.09), CELL * rng.randf_range(0.5, 1.0)])
	_redraw_hands()


## The voxel model each forearm is drawn with now (its hand's pose): right, left.
func _hand_models() -> Array:
	var out := []
	for part: StringName in [Vitals.FOREARM_R, Vitals.FOREARM_L]:
		var bone := model.part_node(part)
		out.append(String(bone.get_meta(&"voxel_model", "")) if bone else "")
	return out


var _hand_drawn_models: Array = ["", ""]


func _redraw_hands() -> void:
	var wet := _now() < _hand_wet_until
	_hand_drawn_models = _hand_models()
	for i in 2:
		var part := Vitals.FOREARM_R if i == 0 else Vitals.FOREARM_L
		var bone := model.part_node(part)
		if bone == null:
			continue
		var inst: MultiMeshInstance3D = _hand_meshes[i]
		var cells: Array = _hand_cells[i]
		if inst == null or not is_instance_valid(inst):
			if cells.is_empty():
				continue
			inst = _multimesh_instance(HAND_CELLS)
			inst.name = "HandBlood"
			inst.layers = model.render_layers
			bone.add_child(inst, true)
			_hand_meshes[i] = inst
		inst.transform = Transform3D(fit_of(bone), Vector3.ZERO)
		var pivot := BodyVolume.pivot_at(part, body)
		var drawn := String(_hand_drawn_models[i])
		var mm := inst.multimesh
		var at := PackedVector3Array()
		var n := 0
		for j in cells.size():
			var dir: Vector3 = cells[j][0]
			var mid: Variant = BodyVolume.slab_centre(part, float(cells[j][1]), body, drawn)
			if not mid is Vector3:
				continue
			var s: Variant = BodyVolume.surface(part, mid, dir, 0.08, body, drawn)
			if not s is Vector3:
				continue  # (that bit of hand isn't there in this pose)
			var size: float = cells[j][2]
			# A flat smear on the skin (0.4 cm thick), not a cube standing off it.
			mm.set_instance_transform(n, Transform3D(BodyDevices._facing(dir) * Basis.from_scale(Vector3(size, size, 0.004)), Vector3(s) + dir * 0.002 - pivot))
			mm.set_instance_color(n, (FRESH_COLOUR if j % 3 else BLOOD_COLOUR) if wet else DRIED_COLOUR)
			at.append(Vector3(s) + dir * 0.002 - pivot)
			n += 1
		mm.visible_instance_count = n
		inst.set_meta(&"cells", at)


## Where the hand blood is now, world (tests).
func hand_blood_points(right: bool) -> Array[Vector3]:
	return drawn_cells(_hand_meshes[0 if right else 1])


## Where the cells `inst` draws are now, world: their centres (tests; a headless renderer keeps
## no MultiMesh transforms, so the drawing code keeps them in the "cells" meta).
static func drawn_cells(inst: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_instance_valid(inst) or not (inst as Node).has_meta(&"cells"):
		return out
	var node := inst as Node3D
	for p: Vector3 in node.get_meta(&"cells") as PackedVector3Array:
		out.append(node.global_transform * p)
	return out
