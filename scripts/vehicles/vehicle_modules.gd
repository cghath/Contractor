class_name VehicleModules
extends Node
## The inside of a vehicle (combined arms A2, cg_brief queue item 2.1; docs/combined_arms.md
## 2.2 and 2.3.5): named module boxes (engine, transmission, tracks or wheels, fuel tanks, ammo
## stowage, breech and barrel, sights, fire control, turret ring and elevation, radio, crew
## stations, compartments, the structure), each with its own health, what it eats of a passing
## round, and what its damage does; and the kill states that follow from them and the crew.
##
## Layout (data/vehicle_modules.json, merged into the spec by VehicleSpecs): a model with
## "modules" takes its damage here; one without (technicals, aircraft, static weapons) keeps
## its old hit zones, and layout() builds its modules from them so every model reads the same.
## Crew modules are the seats: a round or a spall fragment crossing one hits the man sitting
## there through his real hitboxes and Vitals, so the wound model works inside as outside.
##
## After a plate is defeated (ArmourModel.vehicle_hit calls plan()) the round, or a shaped
## charge's jet, goes on along its line through the module boxes in order: each one takes
## module_dmg x residual / residual at entry and eats its absorb_mm (a jet 1.5 x after the
## first) until nothing is left; a spall cone of rays (count and width by what beat the plate,
## cut by a spall liner) hits the modules and crew it meets; an HE filling that gets in bursts
## inside (modules within 1.5 x kg^(1/3) m, the crew by Warheads' blast, lethal zone and
## fragments); a near-penetration bulges the backface (15% to the module behind, bruising to a
## man against that wall). A mine or IED under the hull (belly blast) reaches the crew floor by
## the same sum the STANAG 4569 mine ratings are proven with (ArmourStandards.floor_kg) and turns
## into injuries by how far it is over what the floor holds: a hull rated for that level leaves
## the crew able to fight.
##
## Module states: working (above DAMAGED_SHARE of its hp), damaged, destroyed. Effects (2.2.2):
## speed and mobility (engine, transmission, tracks, wheels), leaks, emptied tanks and fires
## (fuel, engine), rounds lost and detonation rolls (ammo: blow-out vents, cook-offs, catastrophic
## kills), guns that won't fire, jam or scatter (breech, barrel, sights, external guns), turret
## drives slowed or manual, the radio dark (meta "radio_down", SideIntel's BFT). Kill states
## (2.2.5): mobility, firepower, crew, knocked out (and whether it's repairable), catastrophic.
## The old hit zones (Vehicle.zone_health) are answered from the modules, so DriveContact,
## VehicleService and MotorPool read what they always did.
##
## Host authoritative: the host applies hits and rolls from the hit's seed; net_state (module
## health in bytes, racks, kill bits, flags) rides the vehicle's StateSync to every peer and late
## joiner, every resolved hit goes out as a compact HitEvent (the last EVENTS_KEPT kept on every
## peer for the x-ray, phase A5), and the zone save keeps it all (to_save). Every number is
## Proposed.

const PATH := "res://data/vehicle_modules.json"

## Module states.
const WORKING := 0
const DAMAGED := 1
const DESTROYED := 2
## At or below this share of its hp a module is damaged (2.2.2: working above 50%).
const DAMAGED_SHARE := 0.5

## Kill-state bits (2.2.5).
const MOBILITY := 1
const FIREPOWER := 2
const CREW := 4
const KNOCKED_OUT := 8
const CATASTROPHIC := 16
const REPAIRABLE := 32
const KILL_NAMES := {MOBILITY: "mobility", FIREPOWER: "firepower", CREW: "crew", KNOCKED_OUT: "knocked out", CATASTROPHIC: "catastrophic", REPAIRABLE: "repairable"}

## The path (2.3.5): how far it is followed, where it starts (just outside the plate's back),
## and a jet's absorb after the first module that absorbs.
const PATH_MAX_M := 9.0
const PATH_BACKSTEP_M := 0.05
const CE_ABSORB_MULT := 1.5
## The spall cone: rays this long; count x clamp(residual / SPALL_RESIDUAL_MM, SPALL_SCALE);
## the cone x (1 + t_eff / pen), at most SPALL_CONE_MAX_DEG; a fragment does SPALL_MODULE_SHARE
## of module_dmg to the module it stops in; a spall liner keeps LINER_COUNT of the fragments in
## LINER_CONE of the cone.
const SPALL_RAY_M := 2.5
const SPALL_RESIDUAL_MM := 100.0
const SPALL_SCALE := Vector2(0.3, 1.5)
const SPALL_CONE_MAX_DEG := 75.0
const SPALL_MODULE_SHARE := 0.04
const LINER_COUNT := 0.4
const LINER_CONE := 0.6
## A partial (2.3.4): the module within PARTIAL_BEHIND_M behind the plate takes PARTIAL_SHARE of
## module_dmg; a man within PARTIAL_TOUCH_M of the bulge is bruised (no wound).
const PARTIAL_SHARE := 0.15
const PARTIAL_BEHIND_M := 0.6
const PARTIAL_TOUCH_M := 0.45
## HE inside: it bursts this far past the plate; modules within HE_INSIDE_R x kg^(1/3) m take
## HE_INSIDE_KJ_PER_KG x kg, less with distance.
const HE_INSIDE_DELAY_M := 0.3
const HE_INSIDE_R := 1.5
const HE_INSIDE_KJ_PER_KG := 120.0
## HE or a stopped shaped charge bursting on the outside: external modules within
## HE_OUTSIDE_R x kg^(1/3) m take module_dmg x their spot's blast share, less with distance.
const HE_OUTSIDE_R := 1.5
## Fragment wounds a man inside takes from a burst in his compartment when the round's data has
## none ([fewest, most]).
const INSIDE_FRAG_WOUNDS := Vector2i(2, 6)
## The structure (the old hull hp) takes this share of what goes into any other module.
const HULL_SHARE := 0.5
## Ammo racks: a hit that damages one loses this share of its rounds.
const RACK_LOSS := 0.1
## Guns: a damaged gun module jams every JAM_EVERY rounds for JAM_S; a damaged barrel scatters
## BARREL_SPREAD x.
const JAM_EVERY := 8
const JAM_S := 3.0
const BARREL_SPREAD := 3.0
## Turret drives: damaged x DAMAGED_RATE; destroyed by hand (2.2.2).
const DAMAGED_RATE := 0.5
const MANUAL_TRAVERSE_DPS := 6.0
const MANUAL_ELEVATION_DPS := 3.0
## Speed (2.2.2): the engine as before (lerp by its health), a damaged transmission x0.6, each
## damaged track x0.85, each damaged wheel x0.9, each destroyed wheel x0.75 on its run-flat (at
## most RUN_FLATS; one more and it's immobile).
const ENGINE_SPEED := Vector2(0.35, 1.0)
const TRANSMISSION_DAMAGED_SPEED := 0.6
const TRACK_DAMAGED_SPEED := 0.85
const WHEEL_DAMAGED_SPEED := 0.9
const WHEEL_RUN_FLAT_SPEED := 0.75
const RUN_FLATS := 2
## Fuel and fire (Vehicle's leak maths), and a catastrophic kill's burn: it goes up at once.
const DETONATE_BURN_S := 0.1
## The belly (2.3.6): an HE burst below BELLY_ABOVE_M over the belly plate's top going up
## (dir.y > BELLY_UP) is under the hull; under a wheel (WHEEL_STATION_M from it) or a track
## (outboard of the track's inner edge, TRACK_INNER_M in from the road wheels' line) it's that
## station's, else the belly's. A charge of STATION_KILL_KG or more always destroys the wheel or
## track station over it. Modules within BELLY_MODULE_UP_M of the floor and BELLY_MODULE_REACH_M
## across take HE_INSIDE_KJ_PER_KG x the floor's kg.
const BELLY_ABOVE_M := 0.15
const BELLY_UP := 0.5
const WHEEL_STATION_M := 0.7
const TRACK_INNER_M := 0.4
const STATION_KILL_KG := 2.0
const BELLY_MODULE_UP_M := 0.6
const BELLY_MODULE_REACH_M := 1.6
## Crew injuries from the floor: up to what it holds (ArmourStandards' floor_kg) ringing ears
## for BELLY_DEAF_S (more the closer to it), nothing worse (STANAG 4569: the crew fights on);
## over it, a blast this close (share of WoundModel.BLAST_RADIUS) and BELLY_BLAST_PER_OVER more
## for each floor's worth over, and the legs and spine take it like a fall from FALL_SAFE_M plus
## BELLY_FALL_M_PER_OVER for each floor's worth over (WoundModel.add_fall: fractures, then death).
const BELLY_DEAF_S := Vector2(5.0, 20.0)
const BELLY_BLAST_OVER := 0.15
const BELLY_BLAST_PER_OVER := 0.2
const BELLY_FALL_M_PER_OVER := 3.0
## Host: the crew's state is checked this often between hits (bleeding out, the downed).
const CREW_CHECK_S := 0.5
## HitEvents kept on each peer (the x-ray's last hits, 2.11).
const EVENTS_KEPT := 10
## Spall rays a HitEvent carries for the x-ray (A5; the rest are only counted). Proposed.
const EVENT_SPALL := 12
## Roll salts on the hit's seed (ArmourModel.roll), apart from ArmourModel's own.
const ROLL_SPALL := 1000
const ROLL_FIRE := 3000
const ROLL_DETONATE := 3100
const ROLL_BATTERY := 3200
const ROLL_FRAGS := 3300
## Kinds that are a gun (destroyed: its seat can't fire; damaged: jams), and sights.
const GUN_KINDS: Array[String] = ["breech", "barrel", "ext_gun", "ugws"]
const SIGHT_KINDS: Array[String] = ["gunner_sight", "aux_sight"]

## Emitted on every peer when the kill states change (bits above): the AI (A9) and objectives read it.
signal kill_changed(bits: int)
## Emitted on every peer for each HitEvent.
signal hit_event(event: Dictionary)

static var _kinds: Dictionary = {}
static var _layouts: Dictionary = {}  # model -> layout()

var vehicle: Vehicle
## Whether this model has authored modules (its damage goes through them).
var authored := false
## The layout (layout()): each {"id", "kind", "i", "box" (AABB or null), "hp", "absorb", "zone",
## "fire", "external", "seat", "troop", "gun_seat", "rounds", "detonate", "on_detonate"}.
var mods: Array = []
## Health of each module, 1 (whole) to 0 (destroyed); every peer (clients from net_state).
var health := PackedFloat32Array()
## Rounds left in each ammo rack (module index -> count).
var rounds := {}
## Host: a crewman was taken out (down, dead) since the vehicle last had an able crew.
var crew_lost := false
## "cook_off", "vented", "detonated": what its ammo did (A7 draws them).
var flags := {}
## The kill-state bits now.
var kill := 0
## The last HitEvents (every peer).
var events: Array = []
## When each of `events` arrived on this peer (Soldier._now()), and how many ever have (A5's x-ray
## card watches the count).
var event_times: Array = []
var events_seen := 0
## Replicated (host -> every peer, the vehicle's StateSync): "h" health bytes, "r" rack rounds,
## "k" kill bits, "f" flags, "cl" crew lost.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if not _is_host():
			_apply_net()
var _check_left := 0.0
var _crew_seen := {}  # host: crew seat -> instance id of the able man seen there last check
var _shots := {}      # host: gun seat -> rounds fired since its last jam
var _by_kind := {}    # kind -> [module index]
var _structure := -1
var _base_rates := Vector2(-1.0, -1.0)
# Looked up once (the hot paths: can_drive and top_speed every physics step, each hit's apply).
var _crew: Array[int] = []      # crew seats
var _radio := -1
var _traverse := -1
var _elevation := -1
var _main_seat := -1
var _gun_seats := {}            # gun seat -> {"guns", "sights": module indices}, seats with armament modules
var _zoned: Array = []          # [index, zone, is a wheel] for the modules answering for a zone
var _immobile := false          # from the health now (_refresh)
var _speed := 1.0
var _guns_out := {}             # gun seat -> its armament out (_refresh)
var _changed := {}              # host: modules a hit changed (server_apply's HitEvent)
## The turret drives by hand whatever their modules say (A3: the engine out past its batteries,
## VehicleWeapons.BATTERY_TURRET_S). Set through set_turret_manual.
var turret_manual := false


func _init(p_vehicle: Vehicle = null) -> void:
	name = "Modules"
	vehicle = p_vehicle
	if vehicle == null:
		return
	authored = vehicle.spec.has("modules")
	mods = layout_of(vehicle.model, vehicle.spec)
	health.resize(mods.size())
	health.fill(1.0)
	for m: Dictionary in mods:
		var i := int(m.i)
		var kind := String(m.kind)
		(_by_kind.get_or_add(kind, []) as Array).append(i)
		match kind:
			"structure":
				_structure = i
			"ammo_rack":
				rounds[i] = int(m.rounds)
			"crew":
				if not bool(m.troop):
					_crew.append(int(m.seat))
			"radio":
				_radio = i
			"traverse":
				_traverse = i
			"elevation":
				_elevation = i
		if int(m.gun_seat) >= 0:
			var parts: Dictionary = _gun_seats.get_or_add(int(m.gun_seat), {"guns": [], "sights": []})
			if kind in GUN_KINDS:
				(parts.guns as Array).append(i)
			elif kind in SIGHT_KINDS:
				(parts.sights as Array).append(i)
		var z := Vehicle.ZONE_HULL if kind == "structure" else StringName(m.zone)
		if z != &"" and (float(m.hp) > 0.0 or kind == "structure"):
			_zoned.append([i, z, kind == "wheel"])
	_main_seat = int((vehicle.spec.get("gun", {}) as Dictionary).get("seat", -1))
	_refresh()
	_publish()


func _ready() -> void:
	set_physics_process(_is_host())
	if _is_host():
		_update_kill()
	else:
		_apply_net()


func _physics_process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CREW_CHECK_S
	_update_kill()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


# --- Layout (pure) ------------------------------------------------------------------------------

static func _kind_data() -> Dictionary:
	if _kinds.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("VehicleModules: %s is missing or not valid JSON" % PATH)
			_kinds = {"_": {}}
		else:
			_kinds = (parsed as Dictionary).get("kinds", {"_": {}})
	return _kinds


## The layout of `model` (cached), from its merged `spec`.
static func layout_of(model: String, spec: Dictionary) -> Array:
	if not _layouts.has(model):
		_layouts[model] = layout(spec)
	return _layouts[model]


## A model's modules from its merged spec: its authored "modules" (2.2.3), else built from its
## old hit zones (2.2.1's migration: engine to engine, wheels to tracks or wheels, fuel to a fuel
## tank, crew and cargo to compartments, the hull's hp to the structure). Every seat not named
## by a crew module gets one (a rider's); a structure is added if none is named.
static func layout(spec: Dictionary) -> Array:
	var out: Array = []
	var crewed := {}
	var raw: Array = spec.get("modules", []) if spec.has("modules") else _from_zones(spec)
	for m: Dictionary in raw:
		out.append(_norm(m, spec, out.size()))
		if String(m.get("kind", "")) == "crew":
			crewed[int(m.get("seat", -1))] = true
	for i in (spec.get("seats", []) as Array).size():
		if not crewed.has(i):
			out.append(_norm({"id": "seat_%d" % i, "kind": "crew", "seat": i, "troop": true}, spec, out.size()))
	if not out.any(func(m: Dictionary) -> bool: return String(m.kind) == "structure"):
		out.append(_norm({"id": "structure", "kind": "structure"}, spec, out.size()))
	return out


static func _from_zones(spec: Dictionary) -> Array:
	var out: Array = []
	var tracked := String(spec.get("kind", "")) == Vehicle.TRACKED
	var kinds := {"engine": "engine", "wheels": "track" if tracked else "wheel", "fuel": "fuel_tank", "crew": "compartment",
		"cargo": "compartment", "rotor": "rotor", "hull": "structure"}
	var n := {}
	for z: Dictionary in spec.get("zones", []):
		var zone := String(z.get("zone", "hull"))
		n[zone] = int(n.get(zone, 0)) + 1
		out.append({"id": "%s_%d" % [zone, n[zone]], "kind": String(kinds.get(zone, "compartment")), "box": z.box,
			"hp": float(z.get("hp_kj", 50.0)), "zone": zone})
	return out


static func _norm(m: Dictionary, spec: Dictionary, index: int) -> Dictionary:
	var kind := String(m.get("kind", "structure"))
	var k: Dictionary = _kind_data().get(kind, {})
	var box: Variant = null
	if m.has("box"):
		box = VehicleSpecs.box(m.box)
	elif kind == "crew" and int(m.get("seat", -1)) >= 0:
		box = seat_box(spec, int(m.seat))
	var hp_default := float((spec.get("hp", {}) as Dictionary).get("hull", 100.0)) if kind == "structure" else 50.0
	var fire: Array = m.get("fire", k.get("fire", [0.0, 0.0]))
	return {"id": String(m.get("id", "%s_%d" % [kind, index])), "kind": kind, "i": index, "box": box,
		"hp": float(m.get("hp", k.get("hp", hp_default))), "absorb": float(m.get("absorb_mm", k.get("absorb_mm", 0.0))),
		"zone": StringName(String(m.get("zone", k.get("zone", "")))), "fire": Vector2(float(fire[0]), float(fire[1])),
		"external": bool(m.get("external", k.get("external", false))), "seat": int(m.get("seat", -1)), "troop": bool(m.get("troop", false)),
		"gun_seat": int(m.get("gun_seat", -1)), "rounds": int(m.get("rounds", 0)), "detonate": m.get("detonate", [0.0, 0.0, 0.0]),
		"on_detonate": String(m.get("on_detonate", "catastrophic")), "doors": bool(m.get("doors", false)),
		# For the hot loops (trace, spall_rays): on a path at all, a crew station, air to a fragment.
		"on_path": box != null and kind != "structure", "crew": kind == "crew", "air": kind in ["compartment", "structure"]}


## A seated body's box at seat `seat` of `spec` (vehicle frame): from its feet (the body's origin,
## the seat's eye less the stance's eye height) to over its head, its legs out in front.
static func seat_box(spec: Dictionary, seat: int) -> AABB:
	var s: Dictionary = (spec.get("seats", []) as Array)[seat]
	var at := VehicleSpecs.vec(s.get("at"))
	var eye := Vehicle.seat_eye(String(s.get("stance", "sit")))
	return AABB(Vector3(at.x - 0.3, at.y - eye - 0.05, at.z - 0.65), Vector3(0.6, eye + 0.25, 1.0))


## The state of a module at `frac` of its health.
static func state_of(frac: float) -> int:
	if frac <= 0.0001:
		return DESTROYED
	return DAMAGED if frac <= DAMAGED_SHARE + 0.0001 else WORKING


## Whether `spec` with fitted `packages` has a spall liner (its own, or a package's).
static func has_liner(spec: Dictionary, packages: Array = []) -> bool:
	if bool(spec.get("spall_liner", false)):
		return true
	var defs: Dictionary = spec.get("packages", {})
	for id: String in ArmourModel.fitted_packages(spec, packages):
		if bool((defs.get(id, {}) as Dictionary).get("spall_liner", false)):
			return true
	return false


# --- After the plate (pure) ---------------------------------------------------------------------

## The path (2.3.5) from `from` (vehicle frame, where the round came through) along `ldir`:
## {"path": [{"i" module, "t0", "t1" (metres along it, in and out), "dmg", "r" (residual met with)}],
## "left": the residual left past the last module}. `crew_on_path` false: crew modules are left to
## the caller (a bullet Ballistics carries on into the hitboxes itself).
static func trace(mods: Array, from: Vector3, ldir: Vector3, residual: float, module_dmg: float, column: String, crew_on_path := true) -> Dictionary:
	var start := from - ldir * PATH_BACKSTEP_M
	var to := from + ldir * PATH_MAX_M
	var hits: Array = []
	for m: Dictionary in mods:
		if not m.on_path or (m.crew and not crew_on_path):
			continue
		var box: AABB = m.box
		var p: Variant = box.intersects_segment(start, to)
		if p == null:
			continue
		var q: Variant = box.intersects_segment(to, start)
		hits.append([start.distance_to(p), start.distance_to(q) if q != null else start.distance_to(p), int(m.i)])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var r := residual
	var out: Array = []
	var absorbed := false
	for h: Array in hits:
		if r <= 0.0:
			break
		var m: Dictionary = mods[int(h[2])]
		out.append({"i": int(h[2]), "t0": float(h[0]) - PATH_BACKSTEP_M, "t1": float(h[1]) - PATH_BACKSTEP_M,
			"dmg": module_dmg * r / residual if residual > 0.0 else 0.0, "r": r})
		var absorb := float(m.absorb)
		if column == "ce" and absorbed:
			absorb *= CE_ABSORB_MULT
		if absorb > 0.0:
			absorbed = true
		r -= absorb
	return {"path": out, "left": maxf(r, 0.0)}


## The spall cone (2.3.5) of a penetration `res` (ArmourModel's HitResult) by `shell` at `from`
## along `ldir`, seeded: [{"d": direction, "x": [[t in, t out, module index], ...] by distance}],
## one per fragment. Compartments and the structure aren't in "x" (fragments fly through air).
static func spall_rays(mods: Array, from: Vector3, ldir: Vector3, shell: Dictionary, res: Dictionary, liner: bool, seed: int) -> Array:
	var sp: Variant = shell.get("spall")
	if typeof(sp) != TYPE_DICTIONARY or float((sp as Dictionary).get("count", 0.0)) <= 0.0:
		return []
	var n := spall_count(shell, res, liner)
	var cone := spall_cone(shell, res, liner)
	var start := from + ldir * 0.02
	var reach := AABB(start - Vector3.ONE * SPALL_RAY_M, Vector3.ONE * SPALL_RAY_M * 2.0)
	var z := ldir.normalized()
	var cone_rad := deg_to_rad(cone)
	var boxes: Array[AABB] = []
	var crew: Array[bool] = []
	var index := PackedInt32Array()
	for m: Dictionary in mods:
		if m.air or m.box == null:
			continue
		var box: AABB = m.box
		if not reach.intersects(box):
			continue
		var c := box.get_center() - start
		var dist := c.length()
		var rad := box.size.length() * 0.5
		if dist > rad and c.angle_to(z) - asin(minf(rad / dist, 1.0)) > cone_rad:
			continue  # wholly outside the cone: no fragment can meet it
		boxes.append(box)
		crew.append(bool(m.crew))
		index.append(int(m.i))
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := x.cross(z)
	var cos_c := cos(deg_to_rad(cone))
	var out: Array = []
	for k in n:
		var ct := lerpf(1.0, cos_c, ArmourModel.roll(seed, ROLL_SPALL + k * 2))
		var st := sqrt(maxf(1.0 - ct * ct, 0.0))
		var ph := TAU * ArmourModel.roll(seed, ROLL_SPALL + k * 2 + 1)
		var d := (z * ct + x * st * cos(ph) + y * st * sin(ph)).normalized()
		var to := start + d * SPALL_RAY_M
		var xs: Array = []
		for j in boxes.size():
			var p: Variant = boxes[j].intersects_segment(start, to)
			if p == null:
				continue
			var t0 := start.distance_to(p)
			var t1 := t0
			if crew[j]:
				var q: Variant = boxes[j].intersects_segment(to, start)
				t1 = start.distance_to(q) if q != null else t0
			xs.append([t0, t1, index[j]])
		if xs.size() > 1:
			xs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		out.append({"d": d, "x": xs})
	return out


## How many spall fragments a penetration `res` by `shell` throws (2.3.5).
static func spall_count(shell: Dictionary, res: Dictionary, liner: bool) -> int:
	var sp: Dictionary = shell.get("spall", {}) if typeof(shell.get("spall")) == TYPE_DICTIONARY else {}
	var n := float(sp.get("count", 0.0)) * clampf(float(res.get("residual", 0.0)) / SPALL_RESIDUAL_MM, SPALL_SCALE.x, SPALL_SCALE.y)
	return roundi(n * (LINER_COUNT if liner else 1.0))


## The spall cone's half-angle in degrees (2.3.5): wider when the plate was thick for the round.
static func spall_cone(shell: Dictionary, res: Dictionary, liner: bool) -> float:
	var sp: Dictionary = shell.get("spall", {}) if typeof(shell.get("spall")) == TYPE_DICTIONARY else {}
	var cone := float(sp.get("cone_deg", 20.0)) * (1.0 + float(res.get("t_eff", 0.0)) / maxf(float(res.get("pen", 0.0)), 0.001))
	return minf(cone * (LINER_CONE if liner else 1.0), SPALL_CONE_MAX_DEG)


## An HE filling of `he_kg` bursting at `burst` inside: [[module index, kJ], ...] for the modules
## (not crew, not the structure) within HE_INSIDE_R x kg^(1/3) m.
static func he_inside(mods: Array, burst: Vector3, he_kg: float) -> Array:
	var r := HE_INSIDE_R * pow(maxf(he_kg, 0.0), 1.0 / 3.0)
	var out: Array = []
	if r <= 0.0:
		return out
	for m: Dictionary in mods:
		if m.box == null or String(m.kind) in ["crew", "structure"] or float(m.hp) <= 0.0:
			continue
		var box: AABB = m.box
		var d := burst.distance_to(burst.clamp(box.position, box.end))
		if d < r:
			out.append([int(m.i), HE_INSIDE_KJ_PER_KG * he_kg * (1.0 - d / r)])
	return out


## An HE filling of `he_kg` (or a shaped charge's, stopped) bursting on the outside at `at`:
## [[module index, kJ], ...] for the external modules within HE_OUTSIDE_R x kg^(1/3) m, each by
## `module_dmg` x the blast share of the armour where it sits (2.3.6).
static func he_outside(mods: Array, spec: Dictionary, at: Vector3, he_kg: float, module_dmg: float) -> Array:
	var r := HE_OUTSIDE_R * pow(maxf(he_kg, 0.0), 1.0 / 3.0)
	var out: Array = []
	if r <= 0.0 or module_dmg <= 0.0:
		return out
	for m: Dictionary in mods:
		if m.box == null or not bool(m.external) or float(m.hp) <= 0.0:
			continue
		var box: AABB = m.box
		var d := at.distance_to(at.clamp(box.position, box.end))
		if d < r:
			var blast := float(VehicleSpecs.armour(String(VehicleDamage.zone_at(spec, box.get_center()).armour)).get("blast", 1.0))
			out.append([int(m.i), module_dmg * blast * (1.0 - d / r)])
	return out


## A near-penetration's bulge at `from` along `ldir` (2.3.4): {"i": the module just behind
## (-1 for none), "dmg", "seats": seats whose man is against that wall}.
static func partial(mods: Array, from: Vector3, ldir: Vector3, module_dmg: float) -> Dictionary:
	var out := {"i": -1, "dmg": PARTIAL_SHARE * module_dmg, "seats": []}
	var start := from - ldir * PATH_BACKSTEP_M
	var to := from + ldir * PARTIAL_BEHIND_M
	var best := INF
	for m: Dictionary in mods:
		if m.box == null:
			continue
		var box: AABB = m.box
		if bool(m.crew):
			if box.grow(PARTIAL_TOUCH_M).has_point(from):
				(out.seats as Array).append(int(m.seat))
			continue
		if String(m.kind) in ["compartment", "structure"] or float(m.hp) <= 0.0:
			continue
		var p: Variant = box.intersects_segment(start, to)
		if p != null and start.distance_to(p) < best:
			best = start.distance_to(p)
			out.i = int(m.i)
	return out


## Plans what a penetration does inside (called by ArmourModel.vehicle_hit on a model with
## modules): adds to the damage dictionary `d` (ArmourModel.damage's, its HitResult under
## "armour") "path" (trace), "spall_rays", "burst" (where an HE filling goes off inside, local) and
## "partial", "entry" and "ldir" (local), "traced" true; a bullet Ballistics carries on keeps
## the energy its path through the modules leaves it ("energy_left"), and the old 2.5 m spall
## ("spall") is off: the cone replaces it.
static func plan(mods: Array, d: Dictionary, shell: Dictionary, local: Vector3, ldir: Vector3, hit: Dictionary, liner: bool) -> void:
	var res: Dictionary = d.get("armour", {})
	d["entry"] = local
	d["ldir"] = ldir
	d["traced"] = true
	d["shell_row"] = shell
	d["spall"] = false
	var module_dmg := float(shell.get("module_dmg", 0.0))
	if res.get("outcome") != ArmourModel.PEN:
		if bool(res.get("partial", false)):
			d["partial"] = partial(mods, local, ldir, module_dmg)
		d["traced"] = false
		return
	var column := String(res.get("column", "ke"))
	var continuing := hit.has("energy_j") and float(d.get("energy_left", 0.0)) > 0.0
	if String(res.get("burst", "")) == "inside":
		# An HE filling that got in: it hits the first thing behind the plate, then bursts.
		var first := trace(mods, local, ldir, maxf(float(res.get("residual", 0.0)), 1.0), module_dmg, "he", true)
		d["path"] = (first.path as Array).slice(0, 1) if not (first.path as Array).is_empty() else []
		d["burst"] = local + ldir * HE_INSIDE_DELAY_M
	else:
		var t := trace(mods, local, ldir, float(res.get("residual", 0.0)), module_dmg, column, not continuing)
		d["path"] = t.path
		if continuing:
			d["energy_left"] = float(hit.get("energy_j", 0.0)) * clampf(float(t.left) / maxf(float(res.get("pen", 0.0)), 0.001), 0.0, 1.0)
			d["stopped"] = float(d.energy_left) <= 0.0
	d["spall_rays"] = spall_rays(mods, local, ldir, shell, res, liner, int(res.get("seed", 0)))


# --- Kill states, speed (pure) ------------------------------------------------------------------

## Whether the modules in `health` leave it immobile (2.2.2, 2.2.5): its engine or transmission
## destroyed, a track thrown (it can only pivot), more than RUN_FLATS wheels gone.
static func immobile(mods: Array, health: PackedFloat32Array, kind: String) -> bool:
	var wheels_gone := 0
	for m: Dictionary in mods:
		var gone := health[int(m.i)] <= 0.0001
		match String(m.kind):
			"engine", "transmission":
				if gone:
					return true
			"track":
				if gone:
					return true
			"wheel":
				if gone:
					wheels_gone += 1
	return kind == Vehicle.WHEELED and wheels_gone > RUN_FLATS


## Top speed share from the modules (2.2.2): 0 when immobile.
static func speed_mult(mods: Array, health: PackedFloat32Array, kind: String) -> float:
	if immobile(mods, health, kind):
		return 0.0
	var mult := 1.0
	var engine := 1.0
	var run_flats := 0
	for m: Dictionary in mods:
		var h := health[int(m.i)]
		match String(m.kind):
			"engine":
				engine = minf(engine, h)
			"transmission":
				if state_of(h) == DAMAGED:
					mult *= TRANSMISSION_DAMAGED_SPEED
			"track":
				if state_of(h) == DAMAGED:
					mult *= TRACK_DAMAGED_SPEED
			"wheel":
				match state_of(h):
					DAMAGED:
						mult *= WHEEL_DAMAGED_SPEED
					DESTROYED:
						run_flats += 1
	return mult * lerpf(ENGINE_SPEED.x, ENGINE_SPEED.y, engine) * pow(WHEEL_RUN_FLAT_SPEED, run_flats)


## Whether the armament of gun seat `seat` is out (2.2.5 firepower): a gun module of it
## destroyed, or every sight it has destroyed. False for a seat with no armament modules.
static func gun_out(mods: Array, health: PackedFloat32Array, seat: int) -> bool:
	var sights := 0
	var sights_gone := 0
	for m: Dictionary in mods:
		if int(m.gun_seat) != seat or seat < 0:
			continue
		var gone := health[int(m.i)] <= 0.0001
		if String(m.kind) in GUN_KINDS and gone:
			return true
		if String(m.kind) in SIGHT_KINDS:
			sights += 1
			sights_gone += 1 if gone else 0
	return sights > 0 and sights_gone == sights


## Whether gun seat `seat` has armament modules.
static func armed(mods: Array, seat: int) -> bool:
	return seat >= 0 and mods.any(func(m: Dictionary) -> bool: return int(m.gun_seat) == seat)


## The kill-state bits (2.2.5) of modules at `health` on a vehicle of `kind` whose main gun is
## seat `main_seat`, with its crew {"able": someone in a crew seat can act, "unable": a man in a
## crew seat can't, "lost": a crewman was taken out since it last had an able crew}, `wrecked`
## (it burned out or went up: catastrophic) and `burning` (lost, not yet a wreck). Knocked out:
## catastrophic, burning, a crew kill, or a mobility kill with the guns out too (or no guns).
## Repairable: knocked out but not burnt, burning or with its structure gone.
static func kill_bits(mods: Array, health: PackedFloat32Array, kind: String, main_seat: int, crew: Dictionary, wrecked: bool, burning: bool) -> int:
	var bits := 0
	if immobile(mods, health, kind):
		bits |= MOBILITY
	if gun_out(mods, health, main_seat):
		bits |= FIREPOWER
	if not bool(crew.get("able", false)) and (bool(crew.get("unable", false)) or bool(crew.get("lost", false))):
		bits |= CREW
	if wrecked:
		bits |= CATASTROPHIC
	var guns_out := (bits & FIREPOWER) != 0 or not armed(mods, main_seat)
	if wrecked or burning or (bits & CREW) != 0 or ((bits & MOBILITY) != 0 and guns_out):
		bits |= KNOCKED_OUT
	var structure := 1.0
	for m: Dictionary in mods:
		if String(m.kind) == "structure":
			structure = health[int(m.i)]
	if (bits & KNOCKED_OUT) != 0 and not wrecked and not burning and structure > 0.0:
		bits |= REPAIRABLE
	return bits


## The bits as words ("mobility, knocked out, repairable"), "" for none.
static func kill_text(bits: int) -> String:
	var parts: PackedStringArray = []
	for b: int in KILL_NAMES:
		if (bits & b) != 0:
			parts.append(KILL_NAMES[b])
	return ", ".join(parts)


# --- The belly (pure) ---------------------------------------------------------------------------

## Whether an HE burst at `local` going along `ldir` (vehicle frame) is under the hull of `spec`.
static func under_belly(spec: Dictionary, local: Vector3, ldir: Vector3) -> bool:
	if not spec.has("belly") or ldir.y < BELLY_UP:
		return false
	return local.y <= belly_top(spec) + BELLY_ABOVE_M


## The top of `spec`'s belly plate (vehicle frame, m): the crew floor.
static func belly_top(spec: Dictionary) -> float:
	for p: Dictionary in spec.get("plates", []):
		if String(p.get("id", "")) == "belly":
			return VehicleSpecs.box(p.box).end.y
	return 0.6


## The station a charge at `local` under `spec` goes off under: "wheel", "track" or "belly"
## (ArmourStandards' mine stations; a tracked vehicle's wheel station is its track).
static func belly_station(spec: Dictionary, local: Vector3) -> String:
	var wheels: Array = spec.get("wheels", [])
	var tracked := String(spec.get("kind", "")) == Vehicle.TRACKED
	if tracked:
		var x := 0.0
		for w: Array in wheels:
			x = maxf(x, absf(float(w[0])))
		return "track" if x > 0.0 and absf(local.x) >= x - TRACK_INNER_M else "belly"
	for w: Array in wheels:
		if Vector2(local.x - float(w[0]), local.z - float(w[1])).length() <= WHEEL_STATION_M:
			return "wheel"
	return "belly"


## What a belly blast that puts `floor_kg` (ArmourStandards.floor_kg) on the crew floor does to
## each man aboard: {"held": the floor holds it (STANAG: the crew able to fight on), "over": how
## many floors' worth it is (1 = just what it holds), "deaf_s": ringing ears (held), "blast": a
## blast this close (share of the radius; over), "fall_m": the legs and spine take it like a fall
## from this high (0: not at all)}.
static func belly_injury(floor_kg: float) -> Dictionary:
	var limit := ArmourStandards.floor_limit_kg()
	var over := floor_kg / maxf(limit, 0.0001)
	var held := floor_kg <= limit + 0.000001
	return {"held": held, "over": over, "deaf_s": lerpf(BELLY_DEAF_S.x, BELLY_DEAF_S.y, clampf(over, 0.0, 1.0)) if held else 0.0,
		"blast": 0.0 if held else clampf(BELLY_BLAST_OVER + BELLY_BLAST_PER_OVER * (over - 1.0), 0.0, 1.0),
		"fall_m": 0.0 if held else WoundModel.FALL_SAFE_M + BELLY_FALL_M_PER_OVER * (over - 1.0)}


## Host (and armour_test on a lone Vitals): puts belly_injury `injury` on `vitals`.
static func injure_belly(vitals: Vitals, injury: Dictionary) -> void:
	if vitals == null or vitals.is_dead():
		return
	if float(injury.get("deaf_s", 0.0)) > 0.0:
		vitals.server_deafen(float(injury.deaf_s))
	var blast := float(injury.get("blast", 0.0))
	if blast > 0.0:
		vitals.server_blast(WoundModel.BLAST_RADIUS * (1.0 - blast), WoundModel.BLAST_RADIUS)
	var fall := float(injury.get("fall_m", 0.0))
	if fall > 0.0:
		vitals.server_fall(fall)


# --- Queries (every peer) -------------------------------------------------------------------------

## A module's index by id (-1 for none).
func index_of(id: String) -> int:
	for m: Dictionary in mods:
		if String(m.id) == id:
			return int(m.i)
	return -1


## A module's health, 1 to 0, by id (1 for none).
func health_of(id: String) -> float:
	var i := index_of(id)
	return health[i] if i >= 0 else 1.0


## A module's state by id (WORKING for none).
func state(id: String) -> int:
	return state_of(health_of(id))


## The kill states as a dictionary: {"mobility", "firepower", "crew", "knocked_out",
## "catastrophic", "repairable"} (every peer).
func kill_state() -> Dictionary:
	return {"mobility": (kill & MOBILITY) != 0, "firepower": (kill & FIREPOWER) != 0, "crew": (kill & CREW) != 0,
		"knocked_out": (kill & KNOCKED_OUT) != 0, "catastrophic": (kill & CATASTROPHIC) != 0, "repairable": (kill & REPAIRABLE) != 0}


## Whether its modules leave it immobile (every peer; false for a model without modules).
func mobility_killed() -> bool:
	return authored and _immobile


func knocked_out() -> bool:
	return (kill & KNOCKED_OUT) != 0


## Top speed share from the modules (Vehicle.top_speed on a model with modules).
func speed_share() -> float:
	return _speed


## Host: whether gun seat `seat` can fire (its armament modules not out).
func gun_ok(seat: int) -> bool:
	return not authored or not bool(_guns_out.get(seat, false))


## Host: after gun seat `seat` fired a round, the extra wait a damaged gun's jam adds (0 most rounds).
func gun_jam_s(seat: int) -> float:
	if not authored:
		return 0.0
	for m: Dictionary in mods:
		if int(m.gun_seat) == seat and String(m.kind) in ["breech", "ext_gun", "ugws"] and state_of(health[int(m.i)]) == DAMAGED:
			_shots[seat] = int(_shots.get(seat, 0)) + 1
			if int(_shots[seat]) >= JAM_EVERY:
				_shots[seat] = 0
				return JAM_S
			return 0.0
	return 0.0


## Host: gun seat `seat`'s spread multiplier (a bent barrel scatters).
func gun_spread_mult(seat: int) -> float:
	if not authored:
		return 1.0
	for m: Dictionary in mods:
		if int(m.gun_seat) == seat and String(m.kind) == "barrel" and state_of(health[int(m.i)]) == DAMAGED:
			return BARREL_SPREAD
	return 1.0


## The crew seats (crew modules not marked troop).
func crew_seats() -> Array[int]:
	return _crew


## What the health now gives (every peer, after any change): immobile, the speed share, which
## guns are out (the pure immobile, speed_mult and gun_out, kept so the drive step and the gun
## don't walk the modules each tick).
func _refresh() -> void:
	if vehicle == null:
		return
	var stop := false
	var mult := 1.0
	var engine := 1.0
	var run_flats := 0
	for i: int in _by_kind.get("engine", []):
		engine = minf(engine, health[i])
		stop = stop or health[i] <= 0.0001
	for kind: String in ["transmission", "track"]:
		for i: int in _by_kind.get(kind, []):
			match state_of(health[i]):
				DESTROYED:
					stop = true
				DAMAGED:
					mult *= TRANSMISSION_DAMAGED_SPEED if kind == "transmission" else TRACK_DAMAGED_SPEED
	for i: int in _by_kind.get("wheel", []):
		match state_of(health[i]):
			DESTROYED:
				run_flats += 1
			DAMAGED:
				mult *= WHEEL_DAMAGED_SPEED
	if vehicle.kind == Vehicle.WHEELED and run_flats > RUN_FLATS:
		stop = true
	_immobile = stop
	_speed = 0.0 if stop else mult * lerpf(ENGINE_SPEED.x, ENGINE_SPEED.y, engine) * pow(WHEEL_RUN_FLAT_SPEED, run_flats)
	for seat: int in _gun_seats:
		var parts: Dictionary = _gun_seats[seat]
		var out := false
		for i: int in parts.guns:
			out = out or health[i] <= 0.0001
		var gone := 0
		for i: int in parts.sights:
			gone += 1 if health[i] <= 0.0001 else 0
		_guns_out[seat] = out or ((parts.sights as Array).size() > 0 and gone == (parts.sights as Array).size())


static func able(s: Soldier) -> bool:
	return s != null and is_instance_valid(s) and s.vitals.is_up() and not s.vitals.is_dying()


# --- Hits (host) ----------------------------------------------------------------------------------

## Host: a hit's damage dictionary `res` (ArmourModel.vehicle_hit's with plan()'s keys, or
## VehicleDamage.resolve's) at `at` (world) in hit zone `zone` (`hit`: Vehicle.server_take_hit's)
## on a model with modules. Vehicle._apply_damage's hook.
func server_apply(zone: Dictionary, res: Dictionary, at: Vector3, hit: Dictionary) -> void:
	var v := vehicle
	var armour: Dictionary = res.get("armour", {})
	var shell: Dictionary = res.shell_row if res.has("shell_row") else (ArmourModel.shell_of(hit) if not armour.is_empty() else {})
	var seed := int(armour.get("seed", hash([at, Engine.get_physics_frames()])))
	var local: Vector3 = res.get("entry", v.to_local(at))
	var dir: Vector3 = hit.get("direction", Vector3.ZERO)
	var ldir: Vector3 = res.get("ldir", (v.global_basis.inverse() * dir).normalized() if dir.length_squared() > 0.0001 else Vector3.DOWN)
	var shooter: Node = hit.get("shooter") as Node if is_instance_valid(hit.get("shooter")) else null
	var mult := v.damage_mult
	var ev := {"o": String(armour.get("outcome", "")), "p": [snappedf(local.x, 0.01), snappedf(local.y, 0.01), snappedf(local.z, 0.01)],
		"pl": String(armour.get("plate", "")), "sh": String(armour.get("shell", hit.get("warhead", hit.get("round", "")))),
		"t": roundi(float(armour.get("t_eff", 0.0))), "pen": roundi(float(armour.get("pen", 0.0))), "s": seed, "m": [], "c": []}
	_event_path(ev, res, ldir, armour, shooter)  # A5: what the x-ray draws (HitReport)
	_changed.clear()
	var seated := _seated()
	var column := String(armour.get("column", ""))
	var cause := 2 if res.has("burst") else (0 if column == "ke" else 1)  # detonation table column
	var penetrated := bool(res.get("penetrated", false))
	# Along the path: modules take their share; crewmen on it are struck by the rod or jet.
	var path: Array = res.get("path", [])
	for p: Dictionary in path:
		var m: Dictionary = mods[int(p.i)]
		if bool(m.crew):
			var s: Soldier = seated.get(int(m.seat))
			if s and _strike(s, local + ldir * float(p.t0), local + ldir * float(p.t1), ldir, shooter):
				(ev.c as Array).append(int(m.seat))
			continue
		_hurt(int(p.i), float(p.dmg) * mult, cause, seed)
		_fire_roll(m, column, shell, seed)
	if penetrated and not path.is_empty() and _structure >= 0:
		_hurt(_structure, float(shell.get("module_dmg", res.get("damage_kj", 0.0))) * HULL_SHARE * mult, cause, seed)
	# The spall cone: each fragment stops in the first module or man it meets.
	var frags := {}  # seat -> fragments taken
	for ray: Dictionary in res.get("spall_rays", []):
		var start: Vector3 = local + ldir * 0.02
		for x: Array in ray.x:
			var m: Dictionary = mods[int(x[2])]
			if bool(m.crew):
				var s: Soldier = seated.get(int(m.seat))
				if s and _fragment(s, start + (ray.d as Vector3) * float(x[0]), start + (ray.d as Vector3) * float(x[1]), ray.d, shooter, int(frags.get(int(m.seat), 0)) == 0):
					frags[int(m.seat)] = int(frags.get(int(m.seat), 0)) + 1
					break
				continue
			if float(m.hp) > 0.0:
				_hurt(int(x[2]), float(shell.get("module_dmg", 0.0)) * SPALL_MODULE_SHARE * mult, cause, seed)
				break
	for seat: int in frags:
		if not seat in ev.c:
			(ev.c as Array).append(seat)
	# An HE filling inside: overpressure on the modules near it, blast and fragments on the crew.
	if res.has("burst"):
		var burst: Vector3 = res.burst
		var kg := float(shell.get("he_kg", hit.get("blast_kg", 0.0)))
		for e: Array in he_inside(mods, burst, kg):
			_hurt(int(e[0]), float(e[1]) * mult, 2, seed)
		for seat: int in seated:
			if _burst_on(seated[seat], v.to_global(burst), kg, shell, shooter, seed + seat) and not seat in ev.c:
				(ev.c as Array).append(seat)
	# A near-penetration: the backface bulges into what's behind it.
	var part: Dictionary = res.get("partial", {})
	if not part.is_empty():
		if int(part.i) >= 0:
			_hurt(int(part.i), float(part.dmg) * mult, 0, seed)
		for seat: int in part.seats:
			var s: Soldier = seated.get(seat)
			if s and not s.vitals.is_dead():
				Harm.note_hit(s, shooter)
				s.vitals.server_impact(Vitals.CHEST, Vitals.INTERMEDIATE, 100.0)
	# No path (a rifle round, a charge, a stopped burst, fire support): the module at the hit
	# takes it as its zone did, the structure its share; an outside burst reaches the external
	# modules near it.
	if path.is_empty() and res.get("partial", {}).is_empty():
		var dmg := float(res.get("damage_kj", 0.0)) * mult
		if dmg > 0.0:
			var i := module_at(local)
			_hurt(i, dmg, cause, seed)
			if i != _structure and _structure >= 0:
				_hurt(_structure, dmg * HULL_SHARE, cause, seed)
			if penetrated:
				_fire_roll(mods[i], "ce" if column != "ke" else "ke", shell, seed, float(res.get("fire_chance", 0.0)))
	if not penetrated and not armour.is_empty() and column != "ke":
		for e: Array in he_outside(mods, v.spec, local - ldir * 0.1, float(shell.get("he_kg", 0.0)), float(shell.get("module_dmg", 0.0))):
			_hurt(int(e[0]), float(e[1]) * mult, 2, seed)
	# Under the hull: the belly blast.
	var kind := StringName(hit.get("kind", Vehicle.KINETIC))
	if kind in [Vehicle.HE, Vehicle.HEDP, Vehicle.THERMOBARIC] and float(hit.get("blast_kg", 0.0)) > 0.0 and under_belly(v.spec, local, ldir):
		ev["b"] = _belly(local, float(hit.blast_kg), seated, shooter, seed)
		if ev.o == "":
			ev.o = "belly"
	# Thermobaric overpressure through hatches and vision blocks (as before).
	if float(res.get("crew_blast", 0.0)) > 0.0:
		for s: Soldier in v.occupants():
			s.vitals.server_blast(lerpf(WoundModel.BLAST_RADIUS, 0.5, float(res.crew_blast)), WoundModel.BLAST_RADIUS)
	for i: int in _changed:
		(ev.m as Array).append(i * 4 + state_of(health[i]))
	_sync_zones()
	_effects()
	if _structure >= 0 and health[_structure] <= 0.0:
		v._destroy()
	_update_kill(false)
	ev["k"] = kill
	v._publish_state(true)
	_publish()
	if not armour.is_empty() or ev.has("b"):
		_send_event(ev)


## A5 (cg_brief queue item 2.4; 2.11): the parts of a hit the x-ray draws, added to its HitEvent
## (so every peer reads the host's own trace, never a recomputed one): "d" the round's direction
## (vehicle frame), "th" its angle to the plate, "r" the range flown, "by" the shooter's node name,
## "x" the path through the modules in order ([module index, from m, to m]), "sp" up to
## EVENT_SPALL of the spall rays ([dx, dy, dz, m to where each stopped]). A few hundred bytes.
func _event_path(ev: Dictionary, res: Dictionary, ldir: Vector3, armour: Dictionary, shooter: Node) -> void:
	ev["d"] = [snappedf(ldir.x, 0.01), snappedf(ldir.y, 0.01), snappedf(ldir.z, 0.01)]
	ev["th"] = roundi(float(armour.get("theta_deg", 0.0)))
	ev["r"] = roundi(float(armour.get("range_m", 0.0)))
	ev["by"] = String(shooter.name) if shooter else ""
	var x: Array = []
	for p: Dictionary in res.get("path", []):
		x.append([int(p.i), snappedf(float(p.t0), 0.01), snappedf(float(p.t1), 0.01)])
	ev["x"] = x
	var sp: Array = []
	for ray: Dictionary in res.get("spall_rays", []):
		if sp.size() >= EVENT_SPALL:
			break
		var d: Vector3 = ray.d
		var stop := SPALL_RAY_M
		for hit: Array in ray.x:
			var m: Dictionary = mods[int(hit[2])]
			if bool(m.crew) or float(m.hp) > 0.0:
				stop = float(hit[0])
				break
		sp.append([snappedf(d.x, 0.01), snappedf(d.y, 0.01), snappedf(d.z, 0.01), snappedf(stop, 0.01)])
	ev["sp"] = sp


## The module a hit at `local` lands in (not a crew station; the structure when none holds it).
func module_at(local: Vector3) -> int:
	for m: Dictionary in mods:
		if m.box != null and not String(m.kind) in ["crew", "structure"] and float(m.hp) > 0.0 and (m.box as AABB).grow(0.05).has_point(local):
			return int(m.i)
	return _structure


## Host: `kj` into module `i` (`cause`: 0 KE, 1 CE, 2 HE inside: the ammo detonation table's
## column). Ammo loses rounds when damaged and rolls to go off when destroyed; a fuel tank leaks
## when damaged and empties when destroyed.
func _hurt(i: int, kj: float, cause: int, seed: int) -> void:
	if i < 0 or i >= mods.size() or kj <= 0.0:
		return
	var m: Dictionary = mods[i]
	var hp := float(m.hp)
	if hp <= 0.0:
		return
	var was := health[i]
	if was <= 0.0:
		return
	health[i] = maxf(was - kj / hp, 0.0)
	_changed[i] = true
	var now_state := state_of(health[i])
	match String(m.kind):
		"ammo_rack":
			if rounds.has(i):
				rounds[i] = int(floor(int(rounds[i]) * (1.0 - RACK_LOSS)))
				if now_state == DESTROYED and int(rounds[i]) > 0:
					_detonation_roll(m, cause, seed)
		"fuel_tank":
			vehicle._leak += Vehicle.LEAK_LPS * clampf(kj / hp, 0.05, 1.0)
			if now_state == DESTROYED and state_of(was) != DESTROYED:
				var tanks := (_by_kind.get("fuel_tank", [1]) as Array).size()
				vehicle.fuel = maxf(vehicle.fuel - float(vehicle.spec.get("fuel_l", 0.0)) / float(maxi(tanks, 1)), 0.0)
		"engine":
			if now_state == DESTROYED and vehicle.battery_ok and ArmourModel.roll(seed, ROLL_BATTERY) < Vehicle.BATTERY_KILL_CHANCE:
				vehicle.battery_ok = false


## Host: whether a round of `column` through module `m` sets it alight (its "fire" chances;
## incendiary KE twice; `chance` overrides).
func _fire_roll(m: Dictionary, column: String, shell: Dictionary, seed: int, chance := -1.0) -> void:
	if not Vehicle.fire_rolls or vehicle.is_burning():
		return
	var fire: Vector2 = m.fire
	var c := chance if chance >= 0.0 else (fire.x * (2.0 if bool(shell.get("incendiary", false)) else 1.0) if column == "ke" else fire.y)
	if c > 0.0 and ArmourModel.roll(seed, ROLL_FIRE + int(m.i)) < c:
		vehicle.server_start_fire()


## Host: an ammo rack destroyed with rounds in it rolls to go off (2.10.2): vent through its
## blow-out panels (rounds gone, the crew unhurt), cook off (a fire: A7 draws the pops), or go up
## (a catastrophic kill: everyone aboard dies, a wreck at once). A rack with blast doors
## ("doors") vents only while they're shut: the loader opens them to pull a round (A3,
## VehicleWeapons.doors_open), and a hit then is catastrophic.
func _detonation_roll(m: Dictionary, cause: int, seed: int) -> void:
	var chances: Array = m.detonate
	var chance := float(chances[clampi(cause, 0, chances.size() - 1)]) if not chances.is_empty() else 0.0
	var go: bool = bool(vehicle.get_meta(&"force_detonate")) if vehicle.has_meta(&"force_detonate") else (Vehicle.fire_rolls and ArmourModel.roll(seed, ROLL_DETONATE + int(m.i)) < chance)
	if not go:
		return
	var how := String(m.on_detonate)
	if how == "vent" and bool(m.doors) and vehicle.weapons and vehicle.weapons.doors_open(String(m.id)):
		how = "catastrophic"  # A3: the loader had the blast doors open: nothing to vent it (2.10.2)
		flags["doors_open"] = true
	match how:
		"vent":
			rounds[int(m.i)] = 0
			flags["vented"] = true
		"cook_off":
			flags["cook_off"] = true
			vehicle.server_start_fire()
		_:
			flags["detonated"] = true
			vehicle.server_start_fire(DETONATE_BURN_S)


## Host: a rod, bullet or jet along `a` to `b` (vehicle frame) through `s`'s seat: through him
## if it meets one of his hitboxes (Warheads' direct hit: lethal, torn by it). Whether it did.
func _strike(s: Soldier, a: Vector3, b: Vector3, ldir: Vector3, shooter: Node) -> bool:
	var hb := _hitbox_on(s, vehicle.to_global(a), vehicle.to_global(b))
	if hb.is_empty():
		return false
	Warheads._direct_hit(s, hb.area, hb.pos, (vehicle.global_basis * ldir).normalized(), shooter)
	return true


## Host: a spall fragment along `a` to `b` (vehicle frame) through `s`'s seat: a fragment wound
## where it meets his hitboxes (only the first deep), unless his soft armour stops it. Whether it
## struck him (a stopped one struck too: it went no further).
func _fragment(s: Soldier, a: Vector3, b: Vector3, d: Vector3, shooter: Node, deep: bool) -> bool:
	var hb := _hitbox_on(s, vehicle.to_global(a), vehicle.to_global(b))
	if hb.is_empty():
		return false
	if s.vitals.is_dead():
		return true
	var part: StringName = hb.area.get_meta(&"body_part", Vitals.CHEST)
	var wdir := (vehicle.global_basis * d).normalized()
	if VoxelArmor.soft_armor_stops(s, part, Ballistics.LEVELS[0], Vitals.FRAGMENT, 1.0, wdir):
		return true
	Harm.note_hit(s, shooter)
	s.vitals.server_hit(part, {"round_class": Vitals.FRAGMENT, "position": hb.pos, "direction": wdir, "hitbox": hb.area, "distance": 1.0,
		"superficial": not deep})
	return true


## Host: an HE filling of `kg` bursting at `burst` (world) inside, on `s`: Warheads' blast
## (doubled in an enclosed space), lethal zone and fragments. Whether it reached him.
func _burst_on(s: Soldier, burst: Vector3, kg: float, shell: Dictionary, shooter: Node, seed: int) -> bool:
	if s == null or s.vitals.is_dead() or kg <= 0.0:
		return false
	var point := Throwables.body_point(s)
	var dist := burst.distance_to(point)
	var radius := Warheads.blast_radius(kg) * Throwables.BLAST_INDOOR_MULT
	if dist > radius:
		return false
	Harm.note_hit(s, shooter)
	s.vitals.server_blast(dist, radius, Throwables.has_ear_pro(s))
	var lethal := Warheads.LETHAL_M_PER_KG3 * pow(kg, 1.0 / 3.0) * Throwables.BLAST_INDOOR_MULT
	if dist <= lethal:
		s.vitals.server_damage(lerpf(Warheads.LETHAL_DAMAGE.x, Warheads.LETHAL_DAMAGE.y, 1.0 - dist / maxf(lethal, 0.01)))
	var w: Array = shell.get("frag_wounds", [INSIDE_FRAG_WOUNDS.x, INSIDE_FRAG_WOUNDS.y])
	var closeness := clampf(1.0 - dist / radius, 0.0, 1.0)
	var n := roundi(lerpf(float(w[0]), float(w[1]), closeness))
	var boxes := _hitboxes(s)
	for k in n:
		if s.vitals.is_dead() or boxes.is_empty():
			break
		var area: Area3D = boxes[int(ArmourModel.roll(seed, ROLL_FRAGS + k) * boxes.size()) % boxes.size()]
		var at := Warheads.hitbox_point(area, Vector3.ZERO)
		var part: StringName = area.get_meta(&"body_part", Vitals.CHEST)
		var wdir := (at - burst).normalized()
		if VoxelArmor.soft_armor_stops(s, part, Ballistics.LEVELS[0], Vitals.FRAGMENT, dist, wdir):
			continue
		s.vitals.server_hit(part, {"round_class": Vitals.FRAGMENT, "position": at, "direction": wdir, "hitbox": area, "distance": dist, "superficial": k > 0})
	return true


## Host: a belly blast of `kg` TNT at `local` (2.3.6): the station over it, the modules by the
## floor, and every man aboard by what reaches the floor (belly_injury). Returns {"st": station,
## "kg": floor kg, "held"} for the HitEvent.
func _belly(local: Vector3, kg: float, seated: Dictionary, shooter: Node, seed: int) -> Dictionary:
	var spec := vehicle.spec
	var packages: Array = vehicle.get_meta(ArmourModel.META_PACKAGES, [])
	var station := belly_station(spec, local)
	var floor_kg := ArmourStandards.floor_kg(spec, kg, station, packages)
	if station != "belly" and kg >= STATION_KILL_KG:
		var best := -1
		var best_d := INF
		for m: Dictionary in mods:
			if String(m.kind) in ["wheel", "track"] and m.box != null:
				var d := Vector2(local.x, local.z).distance_to(Vector2((m.box as AABB).get_center().x, (m.box as AABB).get_center().z))
				if d < best_d:
					best_d = d
					best = int(m.i)
		if best >= 0:
			_hurt(best, float(mods[best].hp) * 2.0, 2, seed)
	var floor_y := belly_top(spec)
	for m: Dictionary in mods:
		if m.box == null or String(m.kind) in ["crew", "structure", "compartment", "wheel", "track"] or float(m.hp) <= 0.0:
			continue
		var box: AABB = m.box
		if box.position.y > floor_y + BELLY_MODULE_UP_M:
			continue
		var d := Vector2(local.x, local.z).distance_to(Vector2(clampf(local.x, box.position.x, box.end.x), clampf(local.z, box.position.z, box.end.z)))
		if d < BELLY_MODULE_REACH_M:
			_hurt(int(m.i), HE_INSIDE_KJ_PER_KG * floor_kg * (1.0 - d / BELLY_MODULE_REACH_M), 2, seed)
	var injury := belly_injury(floor_kg)
	for seat: int in seated:
		var s: Soldier = seated[seat]
		if s.vitals.is_dead():
			continue
		Harm.note_hit(s, shooter)
		injure_belly(s.vitals, injury)
	return {"st": station, "kg": snappedf(floor_kg, 0.001), "held": bool(injury.held)}


## Host: the hitbox of `s` a segment `a` to `b` (world) meets first: {"area", "pos"}, {} for none.
func _hitbox_on(s: Soldier, a: Vector3, b: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for area: Area3D in _hitboxes(s):
		for child in area.get_children():
			var shape := child as CollisionShape3D
			if shape == null or not shape.shape is BoxShape3D:
				continue
			var size := (shape.shape as BoxShape3D).size
			var inv := shape.global_transform.affine_inverse()
			var la := inv * a
			var lb := inv * b
			var p: Variant = AABB(-size * 0.5, size).intersects_segment(la, lb)
			if p == null:
				continue
			var t := la.distance_to(p)
			if t < best_t:
				best_t = t
				best = {"area": area, "pos": shape.global_transform * (p as Vector3)}
	return best


static func _hitboxes(s: Node) -> Array:
	var out: Array = []
	for child in s.get_children():
		if child is Area3D and child.has_meta(&"body_part"):
			out.append(child)
	return out


## Host: who sits where now ({seat: Soldier}).
func _seated() -> Dictionary:
	var out := {}
	for i in vehicle.seat_count():
		var s := vehicle.occupant(i)
		if s:
			out[i] = s
	return out


# --- State (host) ---------------------------------------------------------------------------------

## Host (V2, tests, the motor pool): sets every module answering for `zone` to `h` (Vehicle.server_set_zone).
func server_set_zone(zone: StringName, h: float) -> void:
	if not authored:
		return
	for m: Dictionary in mods:
		if _answers(m, zone):
			health[int(m.i)] = clampf(h, 0.0, 1.0)
	_after_set()


## Host: a field repair of `zone` (VehicleService): its modules at least `to`, or `add` more.
func server_repair(zone: StringName, to: float, add := 0.0) -> void:
	if not authored:
		return
	for m: Dictionary in mods:
		if _answers(m, zone):
			health[int(m.i)] = clampf(maxf(health[int(m.i)] + add, to), 0.0, 1.0)
	_after_set()


## Host (tests, a workshop): every module whole and every rack full again.
func server_reset() -> void:
	health.fill(1.0)
	for m: Dictionary in mods:
		if String(m.kind) == "ammo_rack":
			rounds[int(m.i)] = int(m.rounds)
	flags.clear()
	crew_lost = false
	_after_set()


## Every peer (A3: VehicleWeapons): the turret's drives by hand (true) or by their modules.
func set_turret_manual(on: bool) -> void:
	if turret_manual != on:
		turret_manual = on
		_effects()


## Host (A3: VehicleWeapons keeps which rounds a rack holds, this its total): rack `id`'s rounds
## set to `n` (at least 0), published.
func server_set_rounds(id: String, n: int) -> void:
	var i := index_of(id)
	if i < 0 or not rounds.has(i) or int(rounds[i]) == maxi(n, 0):
		return
	rounds[i] = maxi(n, 0)
	_publish()


## Host: module `id` set to `h` directly (tests; phase A8's workshop).
func server_set(id: String, h: float) -> void:
	var i := index_of(id)
	if i < 0:
		return
	health[i] = clampf(h, 0.0, 1.0)
	_after_set()


## Host: the crew got out under fire (A7's fire, A9's bail-out): a crew kill until it's crewed again.
func server_bail_out() -> void:
	crew_lost = true
	_update_kill()


## Host: it burned out or went up: every module is gone with it.
func server_wrecked() -> void:
	health.fill(0.0)
	for i: int in rounds:
		rounds[i] = 0
	_after_set()


func _answers(m: Dictionary, zone: StringName) -> bool:
	if zone == Vehicle.ZONE_HULL:
		return String(m.kind) == "structure"
	return StringName(m.zone) == zone and float(m.hp) > 0.0


func _after_set() -> void:
	_sync_zones()
	_effects()
	_update_kill(false)
	_publish()
	if vehicle and (not vehicle.is_inside_tree() or _is_host()):
		vehicle._publish_state(true)


## The old hit zones from the modules (authored models): the hull is the structure, the engine
## the worse of engine and transmission, the wheels the worse track (tracked) or the wheels'
## mean (none left past RUN_FLATS gone), fuel the worst tank, crew and cargo their compartments.
func zone_values() -> Dictionary:
	var out := {}
	var wheels := 0
	var sum := 0.0
	var gone := 0
	for e: Array in _zoned:
		var h := health[int(e[0])]
		if bool(e[2]):
			wheels += 1
			sum += h
			gone += 1 if h <= 0.0001 else 0
			continue
		out[e[1]] = minf(float(out.get(e[1], 1.0)), h)
	if wheels > 0:
		out[Vehicle.ZONE_WHEELS] = 0.0 if gone > RUN_FLATS else sum / float(wheels)
	return out


func _sync_zones() -> void:
	_refresh()
	if not authored or vehicle == null:
		return
	var z := zone_values()
	for k: StringName in z:
		vehicle._zones[k] = float(z[k])


## Effects that live outside the modules: the radio's meta (SideIntel's BFT), the turret's drives.
func _effects() -> void:
	if not authored or vehicle == null:
		return
	_radio_meta()
	var t := vehicle.turret
	if t == null:
		return
	if _base_rates.x < 0.0:
		_base_rates = Vector2(t.yaw_rate, t.pitch_rate)
	var tr := _traverse
	var el := _elevation
	if tr >= 0:
		t.yaw_rate = _drive_rate(health[tr], _base_rates.x, MANUAL_TRAVERSE_DPS)
	if el >= 0:
		t.pitch_rate = _drive_rate(health[el], _base_rates.y, MANUAL_ELEVATION_DPS)
	if turret_manual:
		t.yaw_rate = minf(t.yaw_rate, deg_to_rad(MANUAL_TRAVERSE_DPS))
		t.pitch_rate = minf(t.pitch_rate, deg_to_rad(MANUAL_ELEVATION_DPS))


func _radio_meta() -> void:
	if _radio >= 0:
		if health[_radio] <= 0.0:
			vehicle.set_meta(&"radio_down", true)
		elif vehicle.has_meta(&"radio_down"):
			vehicle.remove_meta(&"radio_down")


static func _drive_rate(h: float, base: float, manual_dps: float) -> float:
	match state_of(h):
		DESTROYED:
			return minf(base, deg_to_rad(manual_dps))
		DAMAGED:
			return base * DAMAGED_RATE
	return base


## Host: the crew's state and the kill states now (publishes and signals a change unless `publish` false).
func _update_kill(publish := true) -> void:
	if vehicle == null or not vehicle.is_inside_tree():
		return  # (restored from a save before it's in the tree: it's worked out once it is)
	var crew := {"able": false, "unable": false, "lost": crew_lost}
	if _is_host():
		for seat in crew_seats():
			var s := vehicle.occupant(seat)
			var prev: Variant = instance_from_id(int(_crew_seen.get(seat, 0))) if _crew_seen.has(seat) else null
			if able(s):
				crew.able = true
				_crew_seen[seat] = s.get_instance_id()
				continue
			if s != null:
				crew.unable = true
			if prev is Soldier and not able(prev as Soldier):
				crew_lost = true
			_crew_seen.erase(seat)
		if crew.able:
			crew_lost = false
		crew.lost = crew_lost
	var bits := _bits(crew) if authored else _zone_bits(crew)
	if bits != kill:
		kill = bits
		kill_changed.emit(kill)
		if publish:
			_publish()


## kill_bits() from what _refresh keeps (the same rules, without walking the modules).
func _bits(crew: Dictionary) -> int:
	var wrecked := vehicle.wrecked
	var burning := vehicle.is_burning()
	var bits := MOBILITY if _immobile else 0
	var firepower := bool(_guns_out.get(_main_seat, false))
	if firepower:
		bits |= FIREPOWER
	if not bool(crew.get("able", false)) and (bool(crew.get("unable", false)) or bool(crew.get("lost", false))):
		bits |= CREW
	if wrecked:
		bits |= CATASTROPHIC
	var guns_out := firepower or not _gun_seats.has(_main_seat)
	if wrecked or burning or (bits & CREW) != 0 or (_immobile and guns_out):
		bits |= KNOCKED_OUT
	var structure := health[_structure] if _structure >= 0 else 1.0
	if (bits & KNOCKED_OUT) != 0 and not wrecked and not burning and structure > 0.0:
		bits |= REPAIRABLE
	return bits


## The kill states of a model without modules, from its old zones: mobility as can_drive reads
## it (an engine gone, a tracked vehicle's tracks), the crew and the wreck as above.
func _zone_bits(crew: Dictionary) -> int:
	var v := vehicle
	var bits := 0
	if v.zone_health(Vehicle.ZONE_ENGINE) <= 0.0 or (v.kind == Vehicle.TRACKED and v.zone_health(Vehicle.ZONE_WHEELS) <= 0.0):
		bits |= MOBILITY
	if not bool(crew.able) and (bool(crew.unable) or bool(crew.lost)):
		bits |= CREW
	if v.wrecked:
		bits |= CATASTROPHIC
	if v.wrecked or v.is_burning() or (bits & (CREW | MOBILITY)) != 0:
		bits |= KNOCKED_OUT
	if (bits & KNOCKED_OUT) != 0 and not v.wrecked and not v.is_burning() and v.zone_health(Vehicle.ZONE_HULL) > 0.0:
		bits |= REPAIRABLE
	return bits


# --- Net, events, saving -------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	var bytes := PackedByteArray()
	bytes.resize(health.size())
	for i in health.size():
		bytes[i] = clampi(roundi(health[i] * 255.0), 0, 255) if health[i] > 0.0 else 0
		if health[i] > 0.0 and bytes[i] == 0:
			bytes[i] = 1  # a sliver left is not destroyed
	var racks := []
	for i: int in rounds:
		racks.append([i, int(rounds[i])])
	net_state = {"h": bytes, "r": racks, "k": kill, "f": flags.duplicate(), "cl": crew_lost}


func _apply_net() -> void:
	var bytes: PackedByteArray = net_state.get("h", PackedByteArray())
	for i in mini(bytes.size(), health.size()):
		health[i] = float(bytes[i]) / 255.0
	for r: Array in net_state.get("r", []):
		rounds[int(r[0])] = int(r[1])
	flags = (net_state.get("f", {}) as Dictionary).duplicate()
	crew_lost = bool(net_state.get("cl", false))
	_refresh()
	var k := int(net_state.get("k", 0))
	_effects_client()
	if k != kill:
		kill = k
		kill_changed.emit(kill)


func _effects_client() -> void:
	if vehicle == null or not authored:
		return
	if vehicle.turret == null:
		_radio_meta()  # (A5: the radio's meta on every peer, for the HUD's NO RADIO and the sights' BFT)
		return
	_effects()


func _send_event(ev: Dictionary) -> void:
	_keep_event(ev)
	if is_inside_tree() and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_client_hit_event.rpc(ev)


@rpc("authority", "call_remote", "reliable")
func _client_hit_event(ev: Dictionary) -> void:
	_keep_event(ev)


func _keep_event(ev: Dictionary) -> void:
	events.append(ev)
	event_times.append(Soldier._now())
	events_seen += 1
	if events.size() > EVENTS_KEPT:
		events.pop_front()
		event_times.pop_front()
	hit_event.emit(ev)


## One line for a HitEvent ("pen side_rear_r: engine destroyed, transmission damaged; seats 1, 2 hit"),
## for logs and tests (the x-ray's card is phase A5).
func describe(ev: Dictionary) -> String:
	var parts: PackedStringArray = []
	for code: int in ev.get("m", []):
		var i := code / 4
		if i < mods.size() and String(mods[i].kind) != "structure":
			parts.append("%s %s" % [mods[i].id, ["hit", "damaged", "destroyed"][code % 4]])
	var crew: Array = ev.get("c", [])
	var line := "%s %s" % [String(ev.get("o", "")), String(ev.get("pl", ""))]
	if not parts.is_empty():
		line += ": " + ", ".join(parts)
	if not crew.is_empty():
		line += "; seats %s hit" % ", ".join(PackedStringArray(crew.map(func(c: int) -> String: return str(c))))
	if ev.has("b"):
		line += "; belly %s %.2f kg on the floor (%s)" % [ev.b.st, float(ev.b.kg), "held" if ev.b.held else "over"]
	var k := int(ev.get("k", 0))
	if k:
		line += " [%s]" % kill_text(k)
	return line


## JSON-safe state for the zone save and the motor pool: health by module id, rounds by rack,
## crew_lost, flags.
func to_save() -> Dictionary:
	var hp := {}
	var racks := {}
	for m: Dictionary in mods:
		if health[int(m.i)] < 0.9999:
			hp[String(m.id)] = snappedf(health[int(m.i)], 0.0001)
		if rounds.has(int(m.i)):
			racks[String(m.id)] = int(rounds[int(m.i)])
	return {"hp": hp, "rounds": racks, "crew_lost": crew_lost, "flags": flags.duplicate()}


## Puts a to_save() back; `zones` (the old saves' zone health) fills a model with modules when
## its save has no "modules" yet.
func from_save(data: Dictionary, zones: Dictionary = {}) -> void:
	if data.is_empty():
		if authored:
			for z: Variant in zones:
				for m: Dictionary in mods:
					if _answers(m, StringName(String(z))):
						health[int(m.i)] = clampf(float(zones[z]), 0.0, 1.0)
	else:
		health.fill(1.0)
		var hp: Dictionary = data.get("hp", {})
		var racks: Dictionary = data.get("rounds", {})
		for m: Dictionary in mods:
			if hp.has(String(m.id)):
				health[int(m.i)] = clampf(float(hp[String(m.id)]), 0.0, 1.0)
			if racks.has(String(m.id)):
				rounds[int(m.i)] = maxi(int(racks[String(m.id)]), 0)
		crew_lost = bool(data.get("crew_lost", false))
		flags = (data.get("flags", {}) as Dictionary).duplicate()
	if vehicle and vehicle.wrecked:
		health.fill(0.0)
	_sync_zones()
	_effects()
	_update_kill(false)
	_publish()
