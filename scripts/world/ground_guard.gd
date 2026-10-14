class_name GroundGuard
extends Node
## The safety net under the world (Captain, 2026-10-14: "falling out of the world"). Bodies fell
## to y -120 .. -1809 in soaks and benches: placed below a zone's terrain (B-05, the compound's
## fixed people in a procedural zone), past the edge of the ground (the base's 160 m pad, a
## zone's edge walls), or teleported into a level whose ground wasn't under them yet. Movement
## holds a body with nothing under it (SoldierMovement.step, no_ground_below); this node puts
## back on the ground nearby anything already lost: below the ground with nothing under it, or
## past the ground's edge with nothing under it. Each one is logged once.
##
## Who moves what: the host its AI, bodies, ragdolls, items and vehicles; each peer its own
## player (the player's own machine drives its position; the host's copy follows the sync).
## A child of every CompoundLevel (and so of every ZoneLevel and BaseLevel), on every peer.

## How often everything is checked (s).
const CHECK_S := 0.5
## This far below the ground, with nothing under it, a body is lost. Below this much a body
## is never in a cellar: the zones' modules stand on the terrain.
const BELOW_M := 3.0
## Past the ground's edge by this much, with nothing under it, a body is lost.
const OUT_M := 1.0
## A player further than this past the edge with nothing under them is somewhere the level
## hasn't got yet (teleported ahead of a level switch, S0793): they are held where they are
## (no_ground_below), not pulled to this level's edge, since their own peer sends that position.
const OUT_FAR_M := 40.0
## Put back this far inside the ground's edge, and this high above the ground.
const INSET_M := 3.0
const LIFT_M := 0.3
## How far down a ray looks for something to stand on (m).
const RAY_M := 2500.0

var level: CompoundLevel
var _left := CHECK_S
var _logged := {}
## Tests: how many were put back so far (on this peer).
var rescued := 0


func _init() -> void:
	name = "GroundGuard"


func _ready() -> void:
	level = get_parent() as CompoundLevel


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = CHECK_S
	check_now()


## Checks everything this peer moves now; returns how many it put back.
func check_now() -> int:
	if level == null or not level.is_inside_tree():
		return 0
	var host := multiplayer.is_server()
	var n := 0
	for group in [&"combatants", Soldier.DEAD_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var s := node as Soldier
			if s == null or s.is_queued_for_deletion() or is_instance_valid(s.vehicle):
				continue
			if host and is_instance_valid(s.ragdoll) and s.ragdoll.simulated:
				n += int(_check_ragdoll(s))
			if (s.is_ai() and host) or s.is_local():
				n += int(_check_soldier(s))
	if host:
		for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
			var item := node as WorldItem
			if item and not item.is_queued_for_deletion() and lost(item.global_position, [item.get_rid()]):
				var at := level.put_on_ground(item.global_position)
				item.global_position = at
				item.linear_velocity = Vector3.ZERO
				item.angular_velocity = Vector3.ZERO
				n += 1
				_log(item, "item %s" % item.item_id, at)
		for node in get_tree().get_nodes_in_group(Vehicle.GROUP):
			var v := node as Vehicle
			# Below the ground only: a helicopter may fly past the edge.
			if v and not v.is_queued_for_deletion() and _below(v.global_position) and not _floor_under(v.global_position, [v.get_rid()]):
				var at := level.put_on_ground(v.global_position) + Vector3.UP * 1.0
				v.global_position = at
				v.linear_velocity = Vector3.ZERO
				v.angular_velocity = Vector3.ZERO
				n += 1
				_log(v, "vehicle %s" % v.name, at)
	rescued += n
	return n


## Lost: below the ground or past its edge, with nothing under it to land on.
func lost(pos: Vector3, exclude: Array = [], out_limit := INF) -> bool:
	if not pos.is_finite():
		return true
	var out := _out_by(pos)
	if not _below(pos) and (out <= OUT_M or out > out_limit):
		return false
	return not _floor_under(pos, exclude)


func _below(pos: Vector3) -> bool:
	return pos.y < level.ground_height(pos.x, pos.z) - BELOW_M


## How far `pos` is past the ground's edge (0 inside).
func _out_by(pos: Vector3) -> float:
	var area := level.ground_area()
	var p := Vector2(pos.x, pos.z)
	return p.distance_to(p.clamp(area.position, area.end))


func _floor_under(pos: Vector3, exclude: Array) -> bool:
	return GroundGuard.floor_below(level.get_world_3d(), pos, exclude)


## Whether a ray from just above `pos` straight down finds anything solid (layer 1: the
## ground, structures, proxies) within RAY_M.
static func floor_below(world: World3D, pos: Vector3, exclude: Array = []) -> bool:
	if world == null or not pos.is_finite():
		return false
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * RAY_M, 1, exclude)
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _check_soldier(s: Soldier) -> bool:
	# A player far past the edge waits where they are (OUT_FAR_M); an AI is the host's own.
	if not lost(s.global_position, [s.get_rid()], INF if s.is_ai() else OUT_FAR_M):
		return false
	var at := level.put_on_ground(s.global_position) + Vector3.UP * LIFT_M
	s.global_position = at  # a ragdoll's parts come along (Ragdoll._carry_along)
	s.velocity = Vector3.ZERO
	_log(s, s.log_name(), at)
	return true


## Host: a ragdoll whose torso is lost (the capsule can be fine while the parts fell): the body
## moves, and its parts with it.
func _check_ragdoll(s: Soldier) -> bool:
	var torso := s.ragdoll.parts.get("torso") as RigidBody3D
	if torso == null:
		return false
	var exclude: Array = [s.get_rid()]
	for p: RigidBody3D in s.ragdoll.parts.values():
		exclude.append(p.get_rid())
	if not lost(torso.global_position, exclude):
		return false
	var at := level.put_on_ground(torso.global_position) + Vector3.UP * LIFT_M
	s.global_position += at - torso.global_position
	s.ragdoll.rest_spot()  # carries the parts along now (Ragdoll._carry_along)
	for p: RigidBody3D in s.ragdoll.parts.values():
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	_log(s, "%s (ragdoll)" % s.log_name(), at)
	return true


func _log(what: Node, who: String, at: Vector3) -> void:
	var key := what.get_instance_id()
	if _logged.has(key):
		return
	_logged[key] = true
	SessionLog.note("[ground] %s was below or past the ground: put back at (%.0f, %.1f, %.0f)" % [who, at.x, at.y, at.z])
