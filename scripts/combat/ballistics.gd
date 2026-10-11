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
## come from that data. Hitscan: no bullet drop or flight time yet.

const RANGE := 300.0
const MASK := (1 << 0) | (1 << 1) | (1 << 3)  # world, hitboxes, armor
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
	var from := origin
	var to := origin + direction * RANGE
	var lost_j := 0.0  # energy lost in walls on the way
	for i in MAX_PENETRATIONS:
		var query := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.collider
		var distance := origin.distance_to(hit.position)
		if collider is VoxelArmor:
			if collider.server_try_stop(hit.position, direction, weapon, equivalent_distance(weapon, distance, lost_j)):
				return _result("plate", hit)
			exclude.append(collider.get_rid())
			from = hit.position
			continue
		var vitals := Vitals.find_on(collider)
		if vitals:
			var part: StringName = collider.get_meta(&"body_part", Vitals.TORSO) if collider is Node else Vitals.TORSO
			var armor_distance := equivalent_distance(weapon, distance, lost_j)
			var energy := energy_at(weapon, distance)
			if energy >= 0.0 and lost_j > 0.0:
				energy = maxf(energy - lost_j, 0.0)
			# Soft armor (the vest's aramid) can stop a round where no plate covers the body.
			if VoxelArmor.soft_armor_stops(vitals.get_parent(), part, threat_level_at(weapon, armor_distance), round_class(weapon), armor_distance, direction, hit.position, energy):
				return _result("plate", hit)
			var hit_info := {
				"round_class": round_class(weapon),
				"position": hit.position,
				"direction": direction,
				"hitbox": collider,  # the wound channel follows the hitbox's pose
				"distance": distance,
			}
			if lost_j > 0.0:
				_spend(hit_info, world_energy(weapon, distance) - lost_j)
			vitals.server_hit(part, hit_info)
			return _result("body", hit)
		var world := VoxelWorld.find_on(collider)
		if world == null:
			return _result("world", hit)  # the ground
		var through := world.trace_round(hit.position, direction, world_energy(weapon, distance) - lost_j)
		if through.stopped:
			world.server_mark(hit.position, hit.normal, int(through.material))
			return _result("world", hit)
		world.server_shot(hit.position, hit.normal, through.exit, through.exit_normal, calibre_m(weapon), through.voxels, int(through.material))
		lost_j += float(through.lost_j)
		from = (through.exit as Vector3) + direction * 0.01
	return {"result": "none", "position": to, "normal": Vector3.ZERO}


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
