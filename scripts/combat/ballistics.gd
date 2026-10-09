class_name Ballistics
extends RefCounted
## Host-side hit resolution for hitscan weapons. The ray walks through armor (plates and
## helmets): a piece either stops the round (and chips) or the round passes through a hole
## and carries on to whatever is behind it. Hitboxes can carry a "damage_mult" meta
## (the head hitbox does).

const RANGE := 300.0
const MASK := (1 << 0) | (1 << 1) | (1 << 3)  # world, hitboxes, armor
const MAX_PENETRATIONS := 4


## Returns {"result": "none"|"plate"|"body"|"world", "position", "normal"} for effects.
static func fire(shooter: CollisionObject3D, origin: Vector3, direction: Vector3, weapon: ItemData) -> Dictionary:
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
			var mult := float(collider.get_meta(&"damage_mult", 1.0)) if collider is Node else 1.0
			vitals.server_damage(float(weapon.stats.get("damage", 10.0)) * mult)
			return _result("body", hit)
		var world := VoxelWorld.find_on(collider)
		if world:
			world.server_carve(hit.position - hit.normal * 0.05, float(weapon.stats.get("wall_carve_m", 0.12)))
		return _result("world", hit)
	return {"result": "none", "position": to, "normal": Vector3.ZERO}


static func _result(kind: String, hit: Dictionary) -> Dictionary:
	return {"result": kind, "position": hit.position, "normal": hit.normal}
