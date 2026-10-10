class_name Squad
extends Node
## Host-side command state for one faction's AI. Friendly squadmates follow a lead player
## (the host by default). Any player can give orders from the command menu, which also makes
## them the lead; orders go to the units they selected. Hostile squads use the same node for
## their patrol route.

enum Order { FOLLOW, HOLD, MOVE }

## Follow positions in the leader's space (x right, +z behind), per formation.
const FORMATIONS := {
	"wedge": [Vector3(-1.8, 0, 2.2), Vector3(1.8, 0, 2.6), Vector3(-3.4, 0, 4.4), Vector3(3.4, 0, 4.8),
		Vector3(-5.0, 0, 6.6), Vector3(5.0, 0, 7.0), Vector3(0, 0, 6.0)],
	"file": [Vector3(0, 0, 2.5), Vector3(0, 0, 5.0), Vector3(0, 0, 7.5), Vector3(0, 0, 10.0),
		Vector3(0, 0, 12.5), Vector3(0, 0, 15.0), Vector3(0, 0, 17.5)],
	"line": [Vector3(-2.5, 0, 0.5), Vector3(2.5, 0, 0.5), Vector3(-5.0, 0, 0.5), Vector3(5.0, 0, 0.5),
		Vector3(-7.5, 0, 0.5), Vector3(7.5, 0, 0.5), Vector3(-10.0, 0, 0.5)],
	"staggered column": [Vector3(-1.5, 0, 2.5), Vector3(1.5, 0, 5.0), Vector3(-1.5, 0, 7.5), Vector3(1.5, 0, 10.0),
		Vector3(-1.5, 0, 12.5), Vector3(1.5, 0, 15.0), Vector3(-1.5, 0, 17.5)],
}

@export var faction := &"friendly"

var leader: Soldier
var formation := "wedge"
## Hostile squads: points to walk between when nothing is happening.
var patrol: Array[Vector3] = []


func members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_ai() and s.faction == faction and not s.is_queued_for_deletion():
			out.append(s)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return String(a.name) < String(b.name))
	return out


## Members by name, or all of them for an empty list.
func pick(names: PackedStringArray) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in members():
		if names.is_empty() or String(s.name) in names:
			out.append(s)
	return out


## A movement order (follow, hold, move to `point`) for the named units.
func give_order(from: Soldier, order: Order, point: Vector3, names := PackedStringArray()) -> void:
	leader = from
	var units := pick(names)
	for i in units.size():
		var ai := SquadAI.of(units[i])
		if ai:
			ai.on_order(order, point, i, units.size())


## Command menu: hold fire / open fire for the named units.
func set_hold_fire(from: Soldier, hold: bool, names := PackedStringArray()) -> void:
	leader = from
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai:
			ai.hold_fire = hold


## Command menu: the first named unit that has one throws a grenade at `point`.
## Returns the thrower's name, or "" if nobody could.
func order_throw(from: Soldier, id: StringName, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var units := pick(names)
	units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	for s in units:
		var ai := SquadAI.of(s)
		if ai and s.inventory.count_of(id) > 0 and ai.order_throw(id, point):
			return String(s.name)
	return ""


## Where `member` stands when following: its slot in the formation behind the leader.
func follow_point(member: Soldier) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		return member.global_position
	var slots: Array = FORMATIONS.get(formation, FORMATIONS["wedge"])
	var i := members().find(member)
	return leader.global_transform * (slots[maxi(i, 0) % slots.size()] as Vector3)
