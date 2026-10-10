class_name Ballistics
extends RefCounted
## Host-side hit resolution for hitscan weapons. The ray walks through armor (plates and
## helmets): a piece either stops the round (and chips) or the round passes through a hole
## and carries on to whatever is behind it. A hitbox names its body part in a "body_part"
## meta (Vitals.HEAD, Vitals.TORSO...), and the hit goes to Vitals.server_hit.

const RANGE := 300.0
const MASK := (1 << 0) | (1 << 1) | (1 << 3)  # world, hitboxes, armor
const MAX_PENETRATIONS := 4
## Rounds passing this close to an AI soldier suppress it.
const SUPPRESS_RADIUS := 2.5


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
	for i in MAX_PENETRATIONS:
		var query := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.collider
		if collider is VoxelArmor:
			if collider.server_try_stop(hit.position, direction, weapon):
				return _result("plate", hit)
			exclude.append(collider.get_rid())
			from = hit.position
			continue
		var vitals := Vitals.find_on(collider)
		if vitals:
			var part: StringName = collider.get_meta(&"body_part", Vitals.TORSO) if collider is Node else Vitals.TORSO
			var distance := origin.distance_to(hit.position)
			# Soft armor (the vest's aramid) can stop a round where no plate covers the body.
			if VoxelArmor.soft_armor_stops(vitals.get_parent(), part, weapon, distance):
				return _result("plate", hit)
			vitals.server_hit(part, {
				"damage": float(weapon.stats.get("damage", 10.0)),
				"round_class": round_class(weapon),
				"position": hit.position,
				"direction": direction,
				"distance": distance,
			})
			return _result("body", hit)
		var world := VoxelWorld.find_on(collider)
		if world:
			world.server_carve(hit.position - hit.normal * 0.05, float(weapon.stats.get("wall_carve_m", 0.12)))
		return _result("world", hit)
	return {"result": "none", "position": to, "normal": Vector3.ZERO}


## The weapon's round class for wounds and impacts (Vitals.PISTOL...): its "round_class"
## stat if it has one, otherwise guessed from its ammunition.
static func round_class(weapon: ItemData) -> StringName:
	if weapon.stats.has("round_class"):
		return StringName(weapon.stats.round_class)
	match String(weapon.stats.get("ammo", "")):
		"mag_9mm":
			return Vitals.PISTOL
		"mag_762":
			return Vitals.FULL_POWER
	return Vitals.INTERMEDIATE


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
