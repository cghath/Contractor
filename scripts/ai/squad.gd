class_name Squad
extends Node
## Host-side orders for one faction's AI. Friendly squadmates follow a lead player (the
## host by default); any player can give an order, which also makes them the lead, and the
## most recent order wins. Hostile squads use the same node for their patrol route.

enum Order { FOLLOW, HOLD, MOVE }

const ORDER_NAMES := {Order.FOLLOW: "Follow", Order.HOLD: "Hold", Order.MOVE: "Move"}
## Follow positions in the leader's space (x right, +z behind): two loose files, one per fire team.
const FORMATION: Array[Vector3] = [
	Vector3(-1.8, 0, 2.2), Vector3(1.8, 0, 2.6), Vector3(-2.6, 0, 4.6), Vector3(2.6, 0, 5.0),
	Vector3(-1.8, 0, 7.0), Vector3(1.8, 0, 7.4), Vector3(0, 0, 9.4)]

@export var faction := &"friendly"

var leader: Soldier
var order := Order.FOLLOW
var order_point := Vector3.ZERO
## Hostile squads: points to walk between when nothing is happening.
var patrol: Array[Vector3] = []


func members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_ai() and s.faction == faction and not s.is_queued_for_deletion():
			out.append(s)
	return out


func give_order(from: Soldier, new_order: Order, point: Vector3) -> void:
	leader = from
	order = new_order
	order_point = point
	for s in members():
		var ai := SquadAI.of(s)
		if ai:
			ai.on_order(new_order, point)


## Where `member` stands when following: its slot in the wedge behind the leader.
func follow_point(member: Soldier) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		return member.global_position
	var ordered := members()
	ordered.sort_custom(func(a: Soldier, b: Soldier) -> bool: return String(a.name) < String(b.name))
	var i := ordered.find(member)
	return leader.global_transform * FORMATION[maxi(i, 0) % FORMATION.size()]
