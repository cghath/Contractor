class_name Ballistics
extends RefCounted
## Host-side hit resolution for hitscan weapons. The ray walks through armor (plates and
## helmets): a piece either stops the round (and chips) or the round passes through it (a
## hole, or armor rated below the round) and carries on to whatever is behind it. A hitbox
## names its body part in a "body_part" meta (Vitals.HEAD, Vitals.TORSO...), and the hit goes
## to Vitals.server_hit unless the vest's soft armor stops it there. Voxel structures go by
## material (VoxelWorld.MATERIALS): wood and sheet metal let a round through with less
## energy, concrete stops it with a small mark.
##
## Rounds come from res://data/rounds.json: threat level, round class and ACE3-style ballistic
## values (muzzle velocity, ballistic coefficient against G1 or G7 drag, bullet mass). A
## weapon fires the round its magazine names, so velocity_at() and energy_at() at any range
## come from that data. Trajectories (Captain, 2026-10-16: "if we can ballistics pleaseeee"): the
## round flies a curved path, PATH_STEP_M at a time, slowing by the drag model and falling by
## gravity, out to RANGE; the sights are zeroed at ZERO_M (a weapon's "zero_m" stat overrides), so
## close in it lands where you aim and far out it drops (the optics' BDC holds are for that). No
## flight time yet: the whole path is traced at once.

const RANGE := 1200.0
const PATH_STEP_M := 20.0
## Past PATH_FAR_M the steps lengthen (fewer ray casts on a long shot; the curve is gentle there).
const PATH_FAR_M := 300.0
const PATH_STEP_FAR_M := 50.0
const ZERO_M := 100.0
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const MASK := (1 << 0) | (1 << 1) | (1 << 3) | Vehicle.LAYER  # world, hitboxes, armor, vehicles (wave 5)
## How many things (armor pieces, walls) one round can pass through.
const MAX_PENETRATIONS := 8
## The world: a round that meets a voxel structure walks through it (VoxelWorld.trace_round,
## by material): through wood and sheet metal it leaves calibre-sized bullet holes and carries on with less
## energy; concrete, steel or too much of anything stops it with a small surface mark.
## Rounds without data in rounds.json count with this energy by class (J).
const FALLBACK_ENERGY_J := {&"pistol": 550.0, &"intermediate": 1650.0, &"full_power": 3350.0}
## A round slowed by walls wounds like a smaller one: below SPENT_PISTOL_J a rifle round makes
## a pistol round's wound, and below SPENT_SUPERFICIAL_J any round only a superficial one.
## Armor meets it as the same round from further out (equivalent_distance).
const SPENT_PISTOL_J := 700.0
const SPENT_SUPERFICIAL_J := 120.0
## equivalent_distance looks no further out than this.
const EQUIVALENT_MAX_M := 2000.0
## Rounds passing this close to an AI soldier suppress it.
const SUPPRESS_RADIUS := 2.5
## The game's armor and threat ladder, weakest first (NIJ names in the game's own order).
## FRAGMENT is below everything: any aramid layer stops it. ABOVE_IV defeats all body armor.
const LEVELS: Array[StringName] = [&"FRAGMENT", &"IIA", &"II", &"IIIA", &"III", &"III+", &"III++", &"IV", &"ABOVE_IV"]
const ROUNDS_PATH := "res://data/rounds.json"
## Air at sea level, 15 C.
const AIR_DENSITY := 1.225
const SPEED_OF_SOUND := 340.0
## 1 lb/in^2 in kg/m^2 (ballistic coefficients are quoted in lb/in^2).
const BC_TO_SI := 703.07
## Integration step for the drag model, metres.
const DRAG_STEP_M := 5.0
## Standard drag curves: [Mach, drag coefficient] (G1 flat-base and G7 boat-tail projectiles).
const DRAG_G1: Array[Vector2] = [Vector2(0.0, 0.263), Vector2(0.5, 0.203), Vector2(0.7, 0.217),
	Vector2(0.8, 0.255), Vector2(0.9, 0.342), Vector2(1.0, 0.481), Vector2(1.1, 0.590), Vector2(1.2, 0.630),
	Vector2(1.35, 0.660), Vector2(1.5, 0.655), Vector2(2.0, 0.600), Vector2(2.5, 0.550), Vector2(3.0, 0.515), Vector2(4.0, 0.480)]
const DRAG_G7: Array[Vector2] = [Vector2(0.0, 0.120), Vector2(0.7, 0.120), Vector2(0.8, 0.121),
	Vector2(0.9, 0.129), Vector2(0.95, 0.146), Vector2(1.0, 0.380), Vector2(1.05, 0.404), Vector2(1.1, 0.401),
	Vector2(1.2, 0.396), Vector2(1.5, 0.361), Vector2(2.0, 0.298), Vector2(2.5, 0.267), Vector2(3.0, 0.243), Vector2(4.0, 0.209)]

static var _rounds: Dictionary = {}  # round id -> entry of rounds.json


## Returns {"result": "none"|"plate"|"body"|"world", "position", "normal"} for effects.
static func _trace(shooter: CollisionObject3D, origin: Vector3, direction: Vector3, weapon: ItemData) -> Dictionary:
	var space := shooter.get_world_3d().direct_space_state
	var exclude: Array[RID] = [shooter.get_rid()]
	for child in shooter.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())  # never shoot your own hitboxes
	var gear := shooter.get_node_or_null(^"Gear") as GearRig
	if gear:
		exclude.append_array(gear.armor_rids())  # ...or your own armor
	var ride := Vehicle.ride_of(shooter)
	if ride:
		exclude.append(ride.get_rid())  # ...or the vehicle you ride in (a mounted gun)
	direction = zeroed(direction, weapon)
	var from := origin
	var path := 0.0  # metres flown to the start of this step
	var seg_start := origin
	var velocity := direction * _speed_at(weapon, 0.0)
	var step := _path_step(seg_start, velocity, weapon, path)
	var to: Vector3 = step[0]
	var lost_j := 0.0  # energy lost in walls on the way
	var passed: Dictionary = {}  # the first body it went through (the shooter's result from then on)
	var hits := 0
	while hits < MAX_PENETRATIONS:
		var query := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			path += seg_start.distance_to(to)
			if path >= RANGE:
				break
			velocity = step[1]
			seg_start = to
			from = to
			direction = velocity.normalized()  # falling a little more each step
			step = _path_step(seg_start, velocity, weapon, path)
			to = step[0]
			continue
		hits += 1
		var collider: Object = hit.collider
		var distance := origin.distance_to(hit.position)
		if collider is VoxelArmor:
			if collider.server_try_stop(hit.position, direction, weapon, equivalent_distance(weapon, distance, lost_j)):
				return passed if not passed.is_empty() else _result("plate", hit)
			exclude.append(collider.get_rid())
			# On from a hair before where it met this piece's box, not on its surface: a piece
			# whose box starts at that very spot (a heavy exo's split leg plates, ExoMech) would
			# not be met by a ray starting on its face.
			from = hit.position - direction * 0.002
			continue
		var vehicle := Vehicle.find_on(collider)
		if vehicle:
			# Vehicles (wave 5): the hull's armour decides (Vehicle.server_take_hit). A round that
			# only met a collision box flies on; one that goes through carries on into the cabin
			# with what it has left (the crew's hitboxes are in there).
			var took := vehicle.server_take_hit({"kind": Vehicle.KINETIC, "round": StringName(round_data(weapon).get("id", "")),
				"energy_j": world_energy(weapon, distance) - lost_j, "level": threat_level_at(weapon, equivalent_distance(weapon, distance, lost_j)),
				"position": hit.position, "direction": direction, "shooter": shooter})
			if took.get("missed", false):
				from = hit.position + direction * 0.01  # inside the box now: the ray carries on past it
				continue
			if took.stopped:
				return passed if not passed.is_empty() else {"result": "vehicle", "position": took.position, "normal": hit.normal}
			lost_j += float(took.get("lost_j", 0.0))
			# On from inside the box (where it met the hull, never short of the box's face).
			from = hit.position + direction * maxf((took.position - hit.position).dot(direction), 0.0) + direction * 0.01
			continue
		var vitals := Vitals.find_on(collider)
		if vitals:
			var part: StringName = collider.get_meta(&"body_part", Vitals.TORSO) if collider is Node else Vitals.TORSO
			# The box is only the first test: the round must meet the body inside it (BodyVolume).
			var body_hit := BodyVolume.entry(collider as Node3D, part, hit.position, direction, BodyVolume.body_of(collider))
			if body_hit.is_empty():
				exclude.append(collider.get_rid())  # through the box, past the body: it flies on
				from = hit.position
				continue
			var armor_distance := equivalent_distance(weapon, distance, lost_j)
			var energy := energy_at(weapon, distance)
			if energy >= 0.0 and lost_j > 0.0:
				energy = maxf(energy - lost_j, 0.0)
			# Soft armor (the vest's aramid) can stop a round where no plate covers the body.
			if VoxelArmor.soft_armor_stops(vitals.get_parent(), part, threat_level_at(weapon, armor_distance), round_class(weapon), armor_distance, direction, body_hit.position, energy):
				return passed if not passed.is_empty() else _result("plate", hit)
			var hit_info := {
				"round_class": round_class(weapon),
				"position": body_hit.position,
				"direction": direction,
				"hitbox": collider,  # the wound channel follows the hitbox's pose
				"channel_depth": body_hit.depth,  # how much body the round crosses
				"distance": distance,
				"energy_j": energy,  # on arrival, after any plate (BodyDeform scores a round by it; .50 kills)
			}
			if lost_j > 0.0:
				_spend(hit_info, world_energy(weapon, distance) - lost_j)
			# Through and out, or in to stay (Captain, 2026-10-16: rounds through the front armour
			# "can also pass through the backside or hit the backside if they pass all the way
			# through the body", "rounds dont always have to pass through either"): the round can
			# cross tissue_reach of body; less body than that and it comes out the far side with
			# what it has left and flies on, into the back plate or helmet (which may stop it), the
			# wall behind or whoever is there.
			var arriving := energy if energy >= 0.0 else world_energy(weapon, distance) - lost_j
			var reach := tissue_reach(weapon, arriving)
			var crosses: bool = round_class(weapon) != Vitals.FRAGMENT and not hit_info.get("superficial", false) and body_hit.depth < reach
			if not crosses:
				hit_info["channel_depth"] = minf(body_hit.depth, reach)
				hit_info["stays_in"] = true
			Harm.note_hit(vitals.get_parent(), shooter)  # who hit whom (people: civilian casualties)
			ExoFrame.server_round(vitals.get_parent(), part, hit_info)  # a strut in the way takes some of it (light exo)
			vitals.server_hit(part, hit_info)
			if not crosses:
				return passed if not passed.is_empty() else _result("body", hit)
			if passed.is_empty():
				passed = _result("body", hit)  # what the shooter sees: he hit someone
			lost_j += arriving * clampf(body_hit.depth / reach, TISSUE_LOSS.x, TISSUE_LOSS.y)
			for box in vitals.get_parent().get_children():
				if box is Area3D:
					exclude.append(box.get_rid())  # out of this body: it doesn't hit him twice
			from = body_hit.position + direction * (body_hit.depth + 0.01)
			continue
		var world := VoxelWorld.find_on(collider)
		if world == null:
			return passed if not passed.is_empty() else _result("world", hit)  # the ground
		var through := world.trace_round(hit.position, direction, world_energy(weapon, distance) - lost_j)
		if through.stopped:
			world.server_mark(hit.position, hit.normal, int(through.material))
			return passed if not passed.is_empty() else _result("world", hit)
		world.server_shot(hit.position, hit.normal, through.exit, through.exit_normal, calibre_m(weapon), through.voxels, int(through.material))
		lost_j += float(through.lost_j)
		from = (through.exit as Vector3) + direction * 0.01
	return passed if not passed.is_empty() else {"result": "none", "position": to, "normal": Vector3.ZERO}


## `direction` (the line of sight) tilted up so the path crosses it again at the weapon's zero
## (stat "zero_m", else ZERO_M): the drop by then over that distance.
static func zeroed(direction: Vector3, weapon: ItemData) -> Vector3:
	var zero := float(weapon.stats.get("zero_m", ZERO_M)) if weapon else ZERO_M
	var axis := direction.cross(Vector3.UP)
	if zero <= 0.0 or axis.length_squared() < 0.0001:
		return direction
	var t := zero / maxf(_speed_at(weapon, zero * 0.5), 50.0)
	return direction.rotated(axis.normalized(), atan2(0.5 * -GRAVITY.y * t * t, zero))


## The round's speed `distance` metres out (velocity_at), or its class's usual without data.
static func _speed_at(weapon: ItemData, distance: float) -> float:
	var v := velocity_at(weapon, distance) if weapon else -1.0
	if v > 0.0:
		return v
	return {Vitals.PISTOL: 370.0, Vitals.INTERMEDIATE: 880.0, Vitals.FULL_POWER: 820.0}.get(round_class(weapon) if weapon else Vitals.INTERMEDIATE, 850.0)


## One PATH_STEP_M of flight from `from` at `velocity`, `path` metres out: [where it gets to,
## its velocity there] (gravity bends it; drag slows it to _speed_at).
static func _path_step(from: Vector3, velocity: Vector3, weapon: ItemData, path: float) -> Array:
	var length := PATH_STEP_M if path < PATH_FAR_M else PATH_STEP_FAR_M
	var speed := maxf(velocity.length(), 50.0)
	var dt := length / speed
	var end := from + velocity * dt + 0.5 * GRAVITY * dt * dt
	var slowed := velocity_after(weapon, speed, length) if weapon else speed
	var next := (velocity + GRAVITY * dt).normalized() * maxf(slowed, 50.0)
	return [end, next]


## Speed `v` slowed by drag over `distance` metres (velocity_at's integration, from where it is
## rather than from the muzzle). Unchanged without drag data.
static func velocity_after(round_or_weapon: Variant, v: float, distance: float) -> float:
	var data := round_data(round_or_weapon)
	var bc := float(data.get("bc", 0.0)) * BC_TO_SI
	if v <= 0.0 or bc <= 0.0:
		return v
	var curve: Array[Vector2] = DRAG_G1 if String(data.get("drag", "G7")) == "G1" else DRAG_G7
	var travelled := 0.0
	while travelled < distance - 0.001 and v > 1.0:
		var step := minf(DRAG_STEP_M * 2.0, distance - travelled)
		var half := v - _deceleration(v, bc, curve) * step * 0.5
		v = maxf(v - _deceleration(half, bc, curve) * step, 0.0)
		travelled += step
	return v

## Metres of body a round crosses before it stops in it, by class (a random spread: yaw,
## fragmenting, bone), longer with more energy than the class's usual (sqrt, 0.6..1.5x).
const TISSUE_REACH_M := {Vitals.PISTOL: Vector2(0.15, 0.40), Vitals.INTERMEDIATE: Vector2(0.28, 0.62), Vitals.FULL_POWER: Vector2(0.50, 0.95)}
## A round that crosses the body loses this share of its energy (by how much of its reach it used).
const TISSUE_LOSS := Vector2(0.3, 0.9)


static func tissue_reach(weapon: ItemData, energy_j: float) -> float:
	var rc := round_class(weapon)
	var span: Vector2 = TISSUE_REACH_M.get(rc, TISSUE_REACH_M[Vitals.INTERMEDIATE])
	var usual := float(FALLBACK_ENERGY_J.get(rc, 1650.0))
	var scale := clampf(sqrt(maxf(energy_j, 1.0) / usual), 0.6, 1.5)
	return randf_range(span.x, span.y) * scale

## The round's energy (J) `distance` metres out for the world (energy_at, or by round class
## from FALLBACK_ENERGY_J when the round has no data).
static func world_energy(weapon: ItemData, distance: float) -> float:
	var energy := energy_at(weapon, distance)
	return energy if energy >= 0.0 else float(FALLBACK_ENERGY_J.get(round_class(weapon), 1650.0))


## A round arriving with `energy_j` left after walls wounds like a smaller one.
static func _spend(hit_info: Dictionary, energy_j: float) -> void:
	if energy_j < SPENT_SUPERFICIAL_J:
		hit_info["superficial"] = true
	if energy_j < SPENT_PISTOL_J and hit_info.round_class in [Vitals.INTERMEDIATE, Vitals.FULL_POWER]:
		hit_info["round_class"] = Vitals.PISTOL


## How far out the same round, untouched, would arrive as slow as this one after losing
## `lost_j` in walls `distance` metres out: what armor meets (threat level, impact). Just
## `distance` when nothing was lost or the round has no data.
static func equivalent_distance(weapon: ItemData, distance: float, lost_j: float) -> float:
	if lost_j <= 0.0:
		return distance
	var mass := float(round_data(weapon).get("mass_g", 0.0)) / 1000.0
	var energy := energy_at(weapon, distance)
	if mass <= 0.0 or energy < 0.0:
		return distance
	var target := sqrt(2.0 * maxf(energy - lost_j, 0.0) / mass)
	var data := round_data(weapon)
	var v := muzzle_velocity(weapon)
	var bc := float(data.get("bc", 0.0)) * BC_TO_SI
	if bc <= 0.0:
		return distance
	var curve: Array[Vector2] = DRAG_G1 if String(data.get("drag", "G7")) == "G1" else DRAG_G7
	var travelled := 0.0
	while v > target and travelled < EQUIVALENT_MAX_M:
		var half := v - _deceleration(v, bc, curve) * DRAG_STEP_M * 0.5
		v = maxf(v - _deceleration(half, bc, curve) * DRAG_STEP_M, 0.0)
		travelled += DRAG_STEP_M
	return maxf(travelled, distance)


## The weapon's round class for wounds and impacts (Vitals.PISTOL...): the loaded round's
## class (see round_data), or a "round_class" stat on the weapon that overrides it.
static func round_class(weapon: ItemData) -> StringName:
	if weapon.stats.has("round_class"):
		return StringName(weapon.stats.round_class)
	return StringName(round_data(weapon).get("class", Vitals.INTERMEDIATE))


## The round's threat level at the muzzle on the game's NIJ-named ladder (Ballistics.LEVELS).
## Armor rated at or above it stops it. A "threat" stat on the weapon overrides the round's.
static func threat_level(weapon: ItemData) -> StringName:
	if weapon.stats.has("threat"):
		return StringName(weapon.stats.threat)
	return StringName(round_data(weapon).get("level", "III"))


## The threat level `distance` metres out. A round whose data has "level_drop_mps" counts as
## "level_drop_to" (default one ladder step lower) once it has slowed below that velocity (a
## steel penetrator needs its speed).
static func threat_level_at(weapon: ItemData, distance: float) -> StringName:
	var level := threat_level(weapon)
	var data := round_data(weapon)
	if weapon.stats.has("threat") or not data.has("level_drop_mps"):
		return level
	if velocity_at(weapon, distance) < float(data.level_drop_mps):
		if data.has("level_drop_to"):
			return StringName(data.level_drop_to)
		return LEVELS[maxi(level_index(level) - 1, 0)]
	return level


## Position of `level` on LEVELS (0 = FRAGMENT), or -1 for an unknown name.
static func level_index(level: StringName) -> int:
	return LEVELS.find(level)


## The round data (an entry of data/rounds.json, with its "id") for a weapon (the round its
## "round" stat names, else its magazine's round), a magazine item, a round id, or a round
## Dictionary. {} if there is none.
static func round_data(round_or_weapon: Variant) -> Dictionary:
	_load_rounds()
	if round_or_weapon is Dictionary:
		return round_or_weapon
	if round_or_weapon is String or round_or_weapon is StringName:
		return _rounds.get(StringName(round_or_weapon), {})
	var item := round_or_weapon as ItemData
	if item == null:
		return {}
	if item.stats.has("round"):
		return _rounds.get(StringName(item.stats.round), {})
	var ammo := StringName(item.stats.get("ammo", ""))
	if ItemDB.has_item(ammo):
		return _rounds.get(StringName(ItemDB.get_item(ammo).stats.get("round", "")), {})
	return {}


## The bullet's diameter in metres (rounds.json "calibre_mm"; 5.56 mm without data).
static func calibre_m(round_or_weapon: Variant) -> float:
	return float(round_data(round_or_weapon).get("calibre_mm", 5.7)) / 1000.0


## Every round id in data/rounds.json.
static func round_ids() -> Array:
	_load_rounds()
	return _rounds.keys()


## Muzzle velocity in m/s: a weapon's "muzzle_velocity_mps" (its barrel), else the round's.
## 0 if unknown.
static func muzzle_velocity(round_or_weapon: Variant) -> float:
	var item := round_or_weapon as ItemData if round_or_weapon is ItemData else null
	if item and item.stats.has("muzzle_velocity_mps"):
		return float(item.stats.muzzle_velocity_mps)
	return float(round_data(round_or_weapon).get("muzzle_mps", 0.0))


## Velocity in m/s after `distance` metres of flight, from the round's ballistic coefficient
## against its standard drag curve: dv/dx = -rho * v * Cd(Mach) * pi / (8 * BC). 0 if unknown.
static func velocity_at(round_or_weapon: Variant, distance: float) -> float:
	var data := round_data(round_or_weapon)
	var v := muzzle_velocity(round_or_weapon)
	var bc := float(data.get("bc", 0.0)) * BC_TO_SI
	if v <= 0.0 or bc <= 0.0:
		return v
	var curve: Array[Vector2] = DRAG_G1 if String(data.get("drag", "G7")) == "G1" else DRAG_G7
	var travelled := 0.0
	while travelled < distance - 0.001 and v > 1.0:
		var step := minf(DRAG_STEP_M, distance - travelled)
		var half := v - _deceleration(v, bc, curve) * step * 0.5  # midpoint (RK2) step
		v = maxf(v - _deceleration(half, bc, curve) * step, 0.0)
		travelled += step
	return v


## Kinetic energy in joules on arrival `distance` metres out (0.5 m v^2), or -1 if unknown.
static func energy_at(round_or_weapon: Variant, distance: float) -> float:
	var mass := float(round_data(round_or_weapon).get("mass_g", 0.0)) / 1000.0
	if mass <= 0.0:
		return -1.0
	var v := velocity_at(round_or_weapon, distance)
	return 0.5 * mass * v * v


## Velocity lost per metre travelled at speed `v` (m/s per m).
static func _deceleration(v: float, bc_si: float, curve: Array[Vector2]) -> float:
	return AIR_DENSITY * v * _drag_coefficient(v / SPEED_OF_SOUND, curve) * PI / (8.0 * bc_si)


static func _drag_coefficient(mach: float, curve: Array[Vector2]) -> float:
	if mach <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if mach <= curve[i].x:
			var a := curve[i - 1]
			var b := curve[i]
			return lerpf(a.y, b.y, (mach - a.x) / (b.x - a.x))
	return curve[curve.size() - 1].y


static func _load_rounds() -> void:
	if not _rounds.is_empty():
		return
	var file := FileAccess.open(ROUNDS_PATH, FileAccess.READ)
	if file == null:
		push_error("Ballistics: cannot open %s" % ROUNDS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("rounds"):
		push_error("Ballistics: %s is not a valid round file" % ROUNDS_PATH)
		return
	for entry: Dictionary in parsed.rounds:
		_rounds[StringName(entry.id)] = entry


static func _result(kind: String, hit: Dictionary) -> Dictionary:
	return {"result": kind, "position": hit.position, "normal": hit.normal}


## Returns {"result": "none"|"plate"|"body"|"world", "position", "normal"} for effects.
## Rounds that pass close to AI soldiers on the other side suppress them.
static func fire(shooter: CollisionObject3D, origin: Vector3, direction: Vector3, weapon: ItemData) -> Dictionary:
	var result := _trace(shooter, origin, direction, weapon)
	report_near_misses(shooter, origin, result.position)
	return result


static func report_near_misses(shooter: Node, from: Vector3, to: Vector3) -> void:
	var faction: StringName = shooter.faction if shooter is Soldier else &""
	for n in shooter.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == shooter or not s.is_ai() or s.faction == faction or not s.vitals.is_up():
			continue
		var chest := s.global_position + Vector3.UP * 1.2
		var d := Geometry3D.get_closest_point_to_segment(chest, from, to).distance_to(chest)
		if d < SUPPRESS_RADIUS:
			s.suppress(0.12 + (SUPPRESS_RADIUS - d) * 0.08, from)
