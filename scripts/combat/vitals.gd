class_name Vitals
extends Node
## Host-owned health. The owner's ServerSync replicates it to every peer, including late
## joiners. (Armor damage is item state, in Inventory.)

signal changed
signal died

@export var max_health := 100.0

var health := 100.0:
	set(value):
		health = value
		changed.emit()

var _heal_left := 0.0      # host only: health still to restore
var _heal_rate := 0.0      # per second


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


func is_healing() -> bool:
	return _heal_left > 0.0


func server_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_heal_left = 0.0
		died.emit()


## Restores `amount` health spread over `seconds`. A new heal replaces one in progress.
func server_heal_over_time(amount: float, seconds: float) -> void:
	_heal_left = amount
	_heal_rate = amount / maxf(seconds, 0.01)


func server_reset_health() -> void:
	health = max_health
	_heal_left = 0.0


func _process(delta: float) -> void:
	if _heal_left <= 0.0 or health <= 0.0 or not multiplayer.is_server():
		return
	var step := minf(_heal_rate * delta, _heal_left)
	_heal_left -= step
	health = minf(health + step, max_health)
	if health >= max_health:
		_heal_left = 0.0
