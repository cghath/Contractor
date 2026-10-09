class_name Throwables
extends RefCounted
## Host-side grenade effects. Every peer simulates the flying grenade (see Grenade) for looks;
## only the host's copy detonates, and the effects reach everyone through CompoundLevel RPCs.
##
## - Frag: damage with falloff to anything with Vitals in the open (walls shield), plus a
##   crater in voxel walls.
## - Flashbang: blinds players by how close it is and whether they were looking at it,
##   and stuns AI soldiers.
## - Smoke: a cloud that blocks AI line of sight (SmokeCloud.blocks) and the view.

const FRAG_RADIUS := 8.0
const FRAG_DAMAGE := 180.0
const FRAG_CARVE_M := 0.45
const FLASH_RADIUS := 15.0
const SHAKE_RADIUS := 30.0
const WORLD_MASK := 1


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


## Host only.
static func server_detonate(level: CompoundLevel, kind: String, pos: Vector3) -> void:
	match kind:
		"frag":
			_frag(level, pos)
		"flash":
			_flash(level, pos)
		"smoke":
			level.spawn_smoke.rpc(pos)


static func _frag(level: CompoundLevel, pos: Vector3) -> void:
	var world := level.get_world_3d()
	var centre := pos + Vector3.UP * 0.25
	for n in combatants(level.get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.health <= 0.0:
			continue
		var target := body_point(body)
		var d := centre.distance_to(target)
		if d > FRAG_RADIUS or not clear_line(world, centre, target):
			continue
		var amount := FRAG_DAMAGE * pow(1.0 - d / FRAG_RADIUS, 1.5)
		if amount >= 1.0:
			vitals.server_damage(amount)
		if body.has_method(&"suppress"):
			body.suppress(0.8, pos)
	level.voxel_world.server_carve(pos, FRAG_CARVE_M)
	level.show_explosion.rpc(pos)
	_shake_players(level, pos)


static func _flash(level: CompoundLevel, pos: Vector3) -> void:
	var world := level.get_world_3d()
	var centre := pos + Vector3.UP * 0.25
	for n in combatants(level.get_tree()):
		var body := n as Node3D
		var eye := body.global_position + Vector3.UP * 1.6
		var d := centre.distance_to(eye)
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
