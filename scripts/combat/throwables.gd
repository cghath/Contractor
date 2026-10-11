class_name Throwables
extends RefCounted
## Host-side grenade effects. Every peer simulates the flying grenade (see Grenade) for looks;
## only the host's copy detonates, and the effects reach everyone through CompoundLevel RPCs.
##
## - Frag: overpressure within 5 m (10 m indoors: deafness, a concussion check, maybe blast
##   lung; burns within 2 m), then 3 to 8 small fragment wounds (fewer chances further out)
##   spread over the body parts each combatant has exposed to the blast (walls, other bodies
##   and armor shield), plus a crater in voxel walls.
## - Flashbang: blinds players by how close it is and whether they were looking at it,
##   stuns AI soldiers, and deafens everyone close for 3 to 6 s.
## Electronic ear protection (carried) stops flashbang and gunfire deafness and halves a blast's.
## - Smoke: a cloud that blocks AI line of sight (SmokeCloud.blocks) and the view, in the
##   grenade's colour (white, green, yellow, blue, purple) on every peer.

const FRAG_RADIUS := 8.0
## Fragment wounds on a body the blast reaches: from FRAG_MIN_WOUNDS at the edge of the
## radius to FRAG_MAX_WOUNDS up close (design doc: 3 to 8). Beyond FRAG_SURE_SHARE of the
## radius a body may be missed altogether, more likely the further out (proposed).
const FRAG_MIN_WOUNDS := 3
const FRAG_MAX_WOUNDS := 8
const FRAG_SURE_SHARE := 0.5
## Of a blast's fragments on one body, only this many go deep enough to reach vessels,
## organs or the chest cavity; the rest are superficial muscle wounds (they may still break
## a bone). So a blast only sometimes makes one arterial or chest wound (design doc).
const FRAG_DEEP_PER_BODY := 1
## What fragments can hit: world, hitboxes, armor.
const FRAG_MASK := (1 << 0) | (1 << 1) | (1 << 3)
const FRAG_CARVE_M := 0.45
const FLASH_RADIUS := 15.0
const SHAKE_RADIUS := 30.0
const WORLD_MASK := 1
## Overpressure reaches WoundModel.BLAST_RADIUS, BLAST_INDOOR_MULT times that indoors (a
## ceiling within INDOOR_CEILING_M overhead). A flashbang deafens for FLASH_DEAF_S by closeness.
const BLAST_INDOOR_MULT := 2.0
const INDOOR_CEILING_M := 4.0
const FLASH_DEAF_S := Vector2(3.0, 6.0)
## Gunfire indoors: everyone within GUNFIRE_NOISE_M of the shooter, indoors too, hears it.
const GUNFIRE_NOISE_M := 8.0
const EAR_PROTECTION := &"ear_protection"


## Under a roof: something solid within INDOOR_CEILING_M straight overhead.
static func indoors(world: World3D, pos: Vector3) -> bool:
	return not clear_line(world, pos + Vector3.UP * 0.3, pos + Vector3.UP * INDOOR_CEILING_M)


## Carries electronic ear protection (it works from the kit: no slot for it yet).
static func has_ear_pro(body: Node) -> bool:
	var inventory: Inventory = body.get(&"inventory") as Inventory
	return inventory != null and inventory.count_of(EAR_PROTECTION) > 0


## Host only. `shooter` fired a shot: indoors, everyone close by (indoors too) hears it in a
## closed room (Vitals.server_noise; sustained fire muffles hearing).
static func server_gunfire(shooter: Node3D) -> void:
	var world := shooter.get_world_3d()
	if not indoors(world, shooter.global_position):
		return
	for n in combatants(shooter.get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.is_dead() or body.global_position.distance_to(shooter.global_position) > GUNFIRE_NOISE_M:
			continue
		if body == shooter or indoors(world, body.global_position):
			vitals.server_noise(1.0, has_ear_pro(body))


## Everything a grenade can affect: players, dummies and AI soldiers.
static func combatants(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(&"combatants")


## Rough centre of mass of a combatant, lower when they're down.
static func body_point(n: Node3D) -> Vector3:
	var vitals := n.get_node_or_null(^"Vitals") as Vitals
	return n.global_position + Vector3.UP * (0.3 if vitals and not vitals.is_up() else 1.0)


## Launch velocity that lands a throw on `to`; flight time grows with distance.
static func lob_velocity(from: Vector3, to: Vector3) -> Vector3:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var t := clampf(from.distance_to(to) / 12.0, 0.6, 1.6)
	return (to - from) / t + Vector3.UP * 0.5 * gravity * t


static func clear_line(world: World3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return world.direct_space_state.intersect_ray(query).is_empty()


## Host only. `item_id` is the grenade's item: a smoke grenade's cloud takes its
## "smoke_colour" (white without one).
static func server_detonate(level: CompoundLevel, kind: String, pos: Vector3, item_id: StringName = &"") -> void:
	match kind:
		"frag":
			_frag(level, pos)
		"flash":
			_flash(level, pos)
		"smoke":
			level.spawn_smoke.rpc(pos, SmokeCloud.colour_of(item_id))


static func _frag(level: CompoundLevel, pos: Vector3) -> void:
	var centre := pos + Vector3.UP * 0.25
	var blast_radius := WoundModel.BLAST_RADIUS * (BLAST_INDOOR_MULT if indoors(level.get_world_3d(), centre) else 1.0)
	for n in combatants(level.get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.is_dead():
			continue
		var d := centre.distance_to(body_point(body))
		if d <= blast_radius:
			vitals.server_blast(d, blast_radius, has_ear_pro(body))  # overpressure (and burns up close)
		if d > FRAG_RADIUS or vitals.is_dead():
			continue
		frag_body(body, vitals, centre, d)
		if body.has_method(&"suppress"):
			body.suppress(0.8, pos)
	level.voxel_world.server_blast(pos, FRAG_CARVE_M)  # by material: concrete only chips
	level.show_explosion.rpc(pos)
	_shake_players(level, pos)


## Host only. Fragments from a blast at `centre`, `distance` metres from `body`: 3 to 8
## small wounds over the hitboxes with a clear line to the blast, only one of them deep. Anything in the way (a
## wall, another body, a plate or helmet, the vest's aramid) stops them. Returns how many
## wounds it made.
static func frag_body(body: Node3D, vitals: Vitals, centre: Vector3, distance: float) -> int:
	var closeness := clampf(1.0 - distance / FRAG_RADIUS, 0.0, 1.0)
	if closeness < 1.0 - FRAG_SURE_SHARE and randf() > closeness / (1.0 - FRAG_SURE_SHARE):
		return 0  # far out: the fragments missed
	var space := body.get_world_3d().direct_space_state
	var exposed: Array[Area3D] = []
	for child in body.get_children():
		var hitbox := child as Area3D
		if hitbox and hitbox.has_meta(&"body_part") and _first_hit(space, centre, _hitbox_point(hitbox, Vector3.ZERO)).get("collider") == hitbox:
			exposed.append(hitbox)
	if exposed.is_empty():
		return 0
	var count := clampi(roundi(lerpf(FRAG_MIN_WOUNDS, FRAG_MAX_WOUNDS, closeness)) + randi_range(-1, 1), FRAG_MIN_WOUNDS, FRAG_MAX_WOUNDS)
	var wounds := 0
	var deep_left := FRAG_DEEP_PER_BODY
	for i in count:
		var hitbox := exposed[randi() % exposed.size()]
		var part: StringName = hitbox.get_meta(&"body_part")
		var target := _hitbox_point(hitbox, Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)))
		var direction := (target - centre).normalized()
		var hit := _first_hit(space, centre, target + direction * 0.05)
		if hit.get("collider") != hitbox:
			continue  # this one met armor or something else on the way
		if VoxelArmor.soft_armor_stops(body, part, Ballistics.LEVELS[0], Vitals.FRAGMENT, distance, direction):
			continue
		# The deep one is whichever lands first: fragments arrive in random order.
		Harm.note_hit(body, Harm.blast_source)  # whose grenade it was (people: civilian casualties)
		vitals.server_hit(part, {"round_class": Vitals.FRAGMENT, "position": hit.position,
			"direction": direction, "hitbox": hitbox, "distance": distance, "superficial": deep_left <= 0})
		deep_left -= 1
		wounds += 1
	return wounds


static func _first_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, FRAG_MASK)
	query.collide_with_areas = true
	return space.intersect_ray(query)


## A point in a hitbox's first box shape: its centre plus `jitter` (fractions of its size).
static func _hitbox_point(hitbox: Area3D, jitter: Vector3) -> Vector3:
	for child in hitbox.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			return shape.global_transform * ((shape.shape as BoxShape3D).size * jitter)
	return hitbox.global_position


static func _flash(level: CompoundLevel, pos: Vector3) -> void:
	var world := level.get_world_3d()
	var centre := pos + Vector3.UP * 0.25
	for n in combatants(level.get_tree()):
		var body := n as Node3D
		var eye := body.global_position + Vector3.UP * 1.6
		var d := centre.distance_to(eye)
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals and d <= FLASH_RADIUS:  # the bang deafens with or without a line of sight
			vitals.server_deafen(lerpf(FLASH_DEAF_S.x, FLASH_DEAF_S.y, 1.0 - d / FLASH_RADIUS), has_ear_pro(body))
		if d > FLASH_RADIUS or not clear_line(world, centre, eye):
			continue
		var amount := 1.0 - d / FLASH_RADIUS
		if body is Soldier and not body.is_ai():
			body._client_flashed.rpc_id(body.owner_peer(), pos, amount)
		elif body.has_method(&"stun"):
			body.stun(1.5 + 3.5 * amount, pos)
	level.show_flash.rpc(pos)


static func _shake_players(level: CompoundLevel, pos: Vector3) -> void:
	for player in level.players.get_children():
		var d := (player as Node3D).global_position.distance_to(pos)
		if d < SHAKE_RADIUS:
			player._client_shake.rpc_id(player.name.to_int(), 1.0 - d / SHAKE_RADIUS)
