class_name Vitals
extends Node
## Host-owned health. The owner's ServerSync replicates health, downed and bleed-out time
## to every peer, including late joiners. (Armor damage is item state, in Inventory.)
##
## Reaching 0 HP puts you down, not dead: you bleed out over BLEED_OUT_S unless someone
## revives you (server_revive). Taking another hit while down, giving up, or bleeding out
## kills you (`died`).

signal changed
signal went_down
signal revived
signal died

const BLEED_OUT_S := 60.0

@export var max_health := 100.0
## False skips the downed state and dies straight away.
@export var can_go_down := true

var health := 100.0:
	set(value):
		health = value
		changed.emit()
var downed := false:
	set(value):
		downed = value
		changed.emit()
## Whole seconds left before bleeding out (replicated; changes once a second).
var bleed_seconds := 0:
	set(value):
		bleed_seconds = value
		changed.emit()

var _bleed_left := 0.0     # host only
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


## Up and able to act (not down, not dead).
func is_up() -> bool:
	return health > 0.0 and not downed


func server_damage(amount: float) -> void:
	if downed:
		_die()  # finished off
		return
	if health <= 0.0:
		return  # already dead, waiting to respawn
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		return
	_heal_left = 0.0
	if can_go_down:
		_bleed_left = BLEED_OUT_S
		bleed_seconds = ceili(_bleed_left)
		downed = true
		went_down.emit()
	else:
		died.emit()


## Brings a downed body back up with `hp` health.
func server_revive(hp: float) -> void:
	if not downed:
		return
	downed = false
	bleed_seconds = 0
	health = clampf(hp, 1.0, max_health)
	revived.emit()


func server_give_up() -> void:
	if downed:
		_die()


## Restores `amount` health spread over `seconds`. A new heal replaces one in progress.
func server_heal_over_time(amount: float, seconds: float) -> void:
	_heal_left = amount
	_heal_rate = amount / maxf(seconds, 0.01)


func server_reset_health() -> void:
	downed = false
	bleed_seconds = 0
	health = max_health
	_heal_left = 0.0


func _die() -> void:
	downed = false
	bleed_seconds = 0
	health = 0.0
	died.emit()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if downed:
		_bleed_left -= delta
		if ceili(maxf(_bleed_left, 0.0)) != bleed_seconds:
			bleed_seconds = ceili(maxf(_bleed_left, 0.0))
		if _bleed_left <= 0.0:
			_die()
		return
	if _heal_left <= 0.0 or health <= 0.0:
		return
	var step := minf(_heal_rate * delta, _heal_left)
	_heal_left -= step
	health = minf(health + step, max_health)
	if health >= max_health:
		_heal_left = 0.0
