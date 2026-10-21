class_name WoundMarks
extends Node3D
## The body's wounds drawn where they are, in voxels: an entry hole (dark core, red rim)
## where a round went in and a bigger, ragged exit where it came out, on the bone of the part
## that was hit, so they move with the limb. While a wound bleeds, blood soaks out round the
## hole and runs down the skin with gravity (1 cm voxels laid on the 0.5 cm body shape,
## BodyVolume.surface), drips off the lowest point and pools on the ground. Treated or
## held by a tourniquet, it stops; the stain dries darker and what treated it covers the spot:
## a pressure bandage (cream elastic wrap, its pressure bar over the hole), packed gauze (white,
## bulging, its tail loose), a chest seal (a square patch, dark border and valve) or a plain
## dressing. A casualty bleeding while dragged or crawling smears a trail on the ground
## (SMEAR_*), and whoever works on a bleeding wound gets blood on their hands (HAND_*).
## Devices on the body (tourniquets, splints, lines and bags...) are BodyDevices', and what
## shows in the skin (burns, pallor, blue lips, shivering) BodyCondition's; both are made here.
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
const MAX_STUCK_HOLDERS := 24
const MAX_STUCK_CELLS := 48
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
var _bone_meshes: Dictionary = {}  # bone -> MultiMeshInstance3D
var _dirty := false
var _drips: Array[Dictionary] = []  # {"pos", "vel", "floor"} in world space
var _drip_timer := 0.0
var _drip_mesh: MultiMeshInstance3D
var _pool: Dictionary = {}  # Vector2i -> {"y", "amount"}
var _pool_mesh: MultiMeshInstance3D
var _pool_centre: Variant = null  # the cell the first drip landed in: the pool spreads out from it
var _pool_dirty := false
var _chunks: Array[Dictionary] = []  # brain on the ground: {"pos", "size", "colour", "until"}
var _chunk_mesh: MultiMeshInstance3D
var _stuck: Dictionary = {}  # holder instance id -> {"inst" (a MultiMeshInstance3D on the holder), "count"}
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
			spot.treated = false
			spot.look = &""
		if w.treated:
			spot.treated = true
		var look := _look_of(w)
		if look != &"" and (spot.look == &"" or LOOKS.find(look) < LOOKS.find(spot.look)):
			spot.look = look
		if String(w.kind) in EXTERNAL_KINDS and not w.treated and not w.packed and not w.clamped:
			spot.flow += float(w.rate) * (0.1 if w.tourniquet else 1.0)
	for spot_key: String in _spots.keys():
		if not seen.has(spot_key):
			_spots.erase(spot_key)  # healed or reset: the stain goes too
	for spot: Dictionary in _spots.values():
		if spot.treated:
			spot.flow = 0.0
	_dirty = true
	_redraw()
	_update_processing()


## A new wound spot: its holes (entry, and exit if it went through), each with the outward
## direction of the skin there and a blood trail that starts at the hole.
func _new_spot(part: StringName, at: Vector3, out: Variant) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s%s" % [part, at])
	var holes: Array[Dictionary] = [_new_hole(part, at, false, rng)]
	if out is Vector3:
		holes.append(_new_hole(part, out, true, rng))
	return {"part": part, "holes": holes, "flow": 0.0, "lost": 0.0, "treated": false, "look": &"", "made": 0, "rng": rng}


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
	var skin: Variant = BodyVolume.surface(part, at, n, 0.05, body)
	var p: Vector3 = skin if skin is Vector3 else at
	var hole := {"at": p, "n": n, "exit": exit, "head": p, "trail": 0, "done": false,
		"marks": [], "blood": []}
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
		out.append(Vector3(cell.x * POOL_CELL, float(_pool[cell].y), cell.y * POOL_CELL))
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
		_grow(spot)
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
	# From the lowest trail head in the world (where it runs off).
	var from := Vector3.ZERO
	var lowest := INF
	for hole: Dictionary in spot.holes:
		var p: Vector3 = bone.global_transform * (Vector3(hole.head) + _outward(spot.part, hole.head) * 0.006 - BodyVolume.pivot_at(spot.part, body))
		if p.y < lowest:
			lowest = p.y
			from = p
	var floor_y := _floor_below(from) if is_inside_tree() else from.y - 2.5
	_drips.append({"pos": from, "vel": Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05)), "floor": floor_y})


## A round that went through throws a spray out of the exit: drops that fly on along the
## round's line and land on the ground behind.
func _spatter(spot: Dictionary) -> void:
	var bone := model.part_node(spot.part)
	if bone == null or spot.holes.size() < 2 or not is_inside_tree():
		return
	var entry: Dictionary = spot.holes[0]
	var exit: Dictionary = spot.holes[1]
	var pivot := BodyVolume.pivot_at(spot.part, body)
	var from: Vector3 = bone.global_transform * (Vector3(exit.at) - pivot)
	var dir: Vector3 = (bone.global_basis * (Vector3(exit.at) - Vector3(entry.at))).normalized()
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
	for d: Dictionary in _drips:
		var was: Vector3 = d.pos
		if d.get("slide", false):
			d.vel = Vector3.DOWN * SLIDE_MPS  # running down a wall, not falling
		else:
			d.vel += Vector3.DOWN * 9.8 * delta
		d.pos += d.vel * delta
		var hit := _surface_between(space, was, d.pos) if space else {}
		if not hit.is_empty() or d.pos.y <= d.floor:
			landed.append([d, hit])
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
		if d.get("brain", false):
			_add_chunk(Vector3(d.pos.x, hit.position.y if not hit.is_empty() else d.floor, d.pos.z), float(d.size))
			continue
		if rider:
			_stick(rider, hit.position, d.get("speck", false))
		else:
			_add_pool(Vector3(d.pos.x, hit.position.y if not hit.is_empty() else d.floor, d.pos.z), d.get("speck", false))
	if _drip_mesh == null:
		_drip_mesh = _world_multimesh("Drips", MAX_DRIPS + BRAIN_DROPS)
	var mm := _drip_mesh.multimesh
	while _drips.size() > mm.instance_count:
		_drips.pop_front()  # never past the mesh (P2017: 64 drips, 52 slots)
	for i in _drips.size():
		var brain: bool = _drips[i].get("brain", false)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(_drips[i].size) if brain else Vector3(1, 1.6, 1) * DRIP_SIZE), _drips[i].pos))
		mm.set_instance_color(i, BRAIN_COLOUR if brain else FRESH_COLOUR)
	mm.visible_instance_count = _drips.size()


## The first thing a drop moving from `from` to `to` hits ({} for none): the world, another
## person (a hitbox or a body), an item or armour. Never this body.
func _surface_between(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, LAND_MASK, _own_rids())
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


## A drop landing on something that moves (a person, an item, later a vehicle) stays on it, in
## its own space (on a person, on the nearest part), so it goes wherever that goes.
func _stick(rider: Node3D, at: Vector3, speck: bool) -> void:
	var holder := rider
	var soldier := rider as Soldier if rider is Soldier else Ragdoll.body_of(rider)
	if soldier == null and rider.get_parent() is Soldier:
		soldier = rider.get_parent() as Soldier
	if soldier and soldier.model:
		var best := INF
		for part: StringName in BodyMap.PART_BOXES:
			var bone := soldier.model.part_node(part)
			if bone and bone.global_position.distance_squared_to(at) < best:
				best = bone.global_position.distance_squared_to(at)
				holder = bone
	var key := holder.get_instance_id()
	var mark: Dictionary = _stuck.get(key, {})
	if mark.is_empty() or not is_instance_valid(mark.inst):
		if _stuck.size() >= MAX_STUCK_HOLDERS:
			return
		var inst := _multimesh_instance(MAX_STUCK_CELLS)
		inst.name = "BloodOn"
		holder.add_child(inst, true)
		mark = {"inst": inst, "count": 0}
		_stuck[key] = mark
	var i: int = mark.count
	if i >= MAX_STUCK_CELLS:
		return
	var local: Vector3 = (mark.inst as Node3D).global_transform.affine_inverse() * at
	var size := POOL_CELL * (0.45 if speck else 0.8)
	var mm: MultiMesh = (mark.inst as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, POOL_HEIGHT, size)), local))
	mm.set_instance_color(i, FRESH_COLOUR if speck else BLOOD_COLOUR)
	mark.count = i + 1
	mm.visible_instance_count = mark.count


## The ground (the world only) under pool cell `cell` within POOL_STEP of height `y`, or null
## (past an edge or up a wall).
func _ground_at(cell: Vector2i, y: float) -> Variant:
	if not is_inside_tree():
		return y
	var x := cell.x * POOL_CELL
	var z := cell.y * POOL_CELL
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, y + POOL_STEP, z), Vector3(x, y - POOL_STEP, z), WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else null


## A drop landing on the ground. A drip adds to the pool cell there, and a full cell spills
## on outward (away from where the first drip landed), so the pool spreads out from under
## the body and shows past it. A drop of spatter only leaves a speck.
func _add_pool(at: Vector3, speck := false) -> void:
	var cell := Vector2i(roundi(at.x / POOL_CELL), roundi(at.z / POOL_CELL))
	if not speck and _pool_centre == null:
		_pool_centre = cell
	for i in (1 if speck else 16):
		if not _pool.has(cell):
			if _pool.size() >= MAX_POOL:
				return
			# A spilled cell lies on its own ground; past an edge the spill stops rather than
			# hang in the air.
			var ground: Variant = at.y if i == 0 else _ground_at(cell, at.y)
			if ground == null:
				return
			var life: Vector2 = SPECK_LIFE_S if speck else POOL_LIFE_S
			_pool[cell] = {"y": float(ground), "amount": 0, "until": _now() + randf_range(life.x, life.y)}
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
		var pos := Vector3(cell.x * POOL_CELL, c.y + h * 0.5, cell.y * POOL_CELL)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, h, w)), pos))
		mm.set_instance_color(i, BLOOD_COLOUR if c.amount > 1 else FRESH_COLOUR)
		i += 1
	mm.visible_instance_count = i


## Everything on the body: holes, blood and dressings, one MultiMesh per bone.
## BodyDeform cut a part through: its marks past the cut go (_redraw).
func on_reshaped() -> void:
	if is_instance_valid(model):
		_redraw()


func _redraw() -> void:
	_dirty = false
	var per_bone := {}  # bone -> Array of [local position, size, colour]
	var deform := model.get_node_or_null(^"BodyDeform") as BodyDeform
	for spot: Dictionary in _spots.values():
		var bone := model.part_node(spot.part)
		if bone == null:
			continue
		var pivot := BodyVolume.pivot_at(spot.part, body)
		var cells: Array = per_bone.get(bone, [])
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
				cells.append_array(hole.dressing)
			else:
				for m: Array in hole.marks:
					cells.append([m[0] - pivot, m[1], m[2]])
		per_bone[bone] = cells
	for bone: Node3D in _bone_meshes.keys():
		if not per_bone.has(bone) and is_instance_valid(_bone_meshes[bone]):
			_bone_meshes[bone].multimesh.visible_instance_count = 0
	for bone: Node3D in per_bone:
		var cells: Array = per_bone[bone]
		var inst: MultiMeshInstance3D = _bone_meshes.get(bone)
		if inst == null or not is_instance_valid(inst) or inst.multimesh.instance_count < cells.size():
			if inst and is_instance_valid(inst):
				inst.name = "WoundMarkOld"  # (the new one takes its name now, not next frame)
				inst.queue_free()
			inst = _multimesh_instance(maxi(64, cells.size() * 2))
			inst.name = "WoundMark"
			inst.layers = model.render_layers
			bone.add_child(inst, true)
			_bone_meshes[bone] = inst
		var mm := inst.multimesh
		for i in cells.size():
			var basis: Basis = cells[i][3] if cells[i].size() > 3 else Basis.IDENTITY
			mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(cells[i][1]), cells[i][0]))
			mm.set_instance_color(i, cells[i][2])
		mm.visible_instance_count = cells.size()


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
			return cells
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
	if limb:
		var centre: Vector3 = BodyMap.PART_BOXES[part][0][0]
		var mid := Vector3(centre.x, at.y, centre.z)
		var lo := mid
		var hi := mid
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			var s: Variant = BodyVolume.surface(part, mid + dir * 0.12, dir, 0.12, body)
			if s is Vector3:
				lo = lo.min(s)
				hi = hi.max(s)
		var size := Vector3(hi.x - lo.x + 0.012, 0.06, hi.z - lo.z + 0.012)
		return [[(lo + hi) * 0.5 - pivot, size, DRESSING_COLOUR]]
	var size := Vector3(0.08, 0.08, 0.08) - n.abs() * 0.07
	return [[at + n * 0.005 - pivot, size, DRESSING_COLOUR]]


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
func _add_chunk(at: Vector3, size: float) -> void:
	if _chunks.size() >= MAX_CHUNKS:
		_chunks.pop_front()
	_chunks.append({"pos": at + Vector3.UP * size * 0.3, "size": size, "colour": BRAIN_COLOUR if randf() < 0.65 else BRAIN_DARK,
		"until": _now() + randf_range(CHUNK_LIFE_S.x, CHUNK_LIFE_S.y)})
	_redraw_chunks()


func _redraw_chunks() -> void:
	if _chunk_mesh == null:
		_chunk_mesh = _world_multimesh("Brain", MAX_CHUNKS)
	var mm := _chunk_mesh.multimesh
	for i in _chunks.size():
		var c: Dictionary = _chunks[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0) * float(c.size)), c.pos))
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
			var p: Vector3 = bone.global_transform * (Vector3(hole.head) - BodyVolume.pivot_at(spot.part, body))
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
	_smear.append({"pos": Vector3(low.x, floor_y, low.z) - move * 0.5, "dir": move / moved, "length": moved + 0.015,
		"width": clampf(0.025 + total * 0.03, 0.025, 0.06), "colour": FRESH_COLOUR if randf() < 0.5 else BLOOD_COLOUR,
		"until": _now() + randf_range(POOL_LIFE_S.x, POOL_LIFE_S.y)})
	_redraw_smear()


func _redraw_smear() -> void:
	if _smear_mesh == null:
		_smear_mesh = _world_multimesh("Smear", MAX_SMEAR)
	var mm := _smear_mesh.multimesh
	for i in _smear.size():
		var c: Dictionary = _smear[i]
		var d: Vector3 = c.dir
		var basis := Basis(Vector3.UP.cross(d).normalized(), Vector3.UP, d)
		mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(float(c.width), POOL_HEIGHT * 0.6, float(c.length))),
			Vector3(c.pos) + Vector3.UP * POOL_HEIGHT * 0.3))
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
			if (bone.global_transform * (Vector3(hole.at) - BodyVolume.pivot_at(spot.part, body))).distance_to(p) <= reach:
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
		var tries := 0
		while cells.size() < target and tries < 30:
			tries += 1
			var a := rng.randf() * TAU
			var dir := Vector3(sin(a), 0.0, -cos(a))
			var y := bottom + rng.randf_range(0.005, 0.09)
			var s: Variant = BodyVolume.surface(part, Vector3(box[0].x, y, box[0].z), dir, 0.15, body)
			if s is Vector3:
				cells.append([Vector3(s) + dir * 0.002, Vector3.ONE * CELL * rng.randf_range(0.5, 1.0)])
	_redraw_hands()


func _redraw_hands() -> void:
	var wet := _now() < _hand_wet_until
	for i in 2:
		var bone := model.part_node(Vitals.FOREARM_R if i == 0 else Vitals.FOREARM_L)
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
		var pivot := BodyVolume.pivot_at(Vitals.FOREARM_R if i == 0 else Vitals.FOREARM_L, body)
		var mm := inst.multimesh
		for j in cells.size():
			mm.set_instance_transform(j, Transform3D(Basis.from_scale(cells[j][1]), Vector3(cells[j][0]) - pivot))
			mm.set_instance_color(j, (FRESH_COLOUR if j % 3 else BLOOD_COLOUR) if wet else DRIED_COLOUR)
		mm.visible_instance_count = cells.size()
