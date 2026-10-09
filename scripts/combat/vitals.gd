class_name Vitals
extends Node
## Host-owned health and armor damage. The owner's ServerSync replicates both properties to
## every peer, including late joiners, so plates look the same for everyone.

signal changed
signal died

@export var max_health := 100.0

var health := 100.0:
	set(value):
		health = value
		changed.emit()
## Plate slot -> Array of chips [x, y, radius] in plate voxel coords, in hit order.
## Plates rebuild by replaying this list.
var plate_damage: Dictionary = {}:
	set(value):
		plate_damage = value
		changed.emit()


## The Vitals of whatever owns `node` (a body, or a hitbox/plate under it).
static func find_on(node: Object) -> Vitals:
	var n := node as Node
	for i in 4:
		if n == null:
			return null
		var vitals := n.get_node_or_null(^"Vitals") as Vitals
		if vitals:
			return vitals
		n = n.get_parent()
	return null


func server_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		died.emit()


func server_add_chip(slot: StringName, chip: Array) -> void:
	var damage := plate_damage.duplicate(true)
	var chips: Array = damage.get(slot, [])
	chips.append(chip)
	damage[slot] = chips
	plate_damage = damage


func server_clear_plate(slot: StringName) -> void:
	if plate_damage.has(slot):
		var damage := plate_damage.duplicate(true)
		damage.erase(slot)
		plate_damage = damage


func server_reset_health() -> void:
	health = max_health
