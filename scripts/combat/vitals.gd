class_name Vitals
extends Node
## Host-owned health. The owner's ServerSync replicates health, downed, bleed-out time and
## net_state to every peer, including late joiners. (Armor damage is item state, in
## Inventory.)
##
## Everything outside this file uses only the "wound-model interface" section below (plus
## the signals, is_up, downed and find_on). The ACE3/KAT-style wound model from the design
## doc (blood, wounds per body part, pain, unconsciousness, cardiac arrest) replaces the HP
## behind that interface without changing its callers. Until then it's backed by HP:
##
## Reaching 0 HP puts you down, not dead: you bleed out over BLEED_OUT_S unless someone
## revives you (server_revive). Taking another hit while down or bleeding out kills you
## (`died`). There is no giving up.

signal changed
signal went_down
signal revived
signal died

const BLEED_OUT_S := 60.0
## Round classes for hits and impacts, as the design doc groups them.
const PISTOL := &"pistol"
const INTERMEDIATE := &"intermediate"
const FULL_POWER := &"full_power"
const FRAGMENT := &"fragment"
## Body parts that hitboxes name in their "body_part" meta. The wound model adds more.
const HEAD := &"head"
const TORSO := &"torso"
## HP stand-in for where a hit lands.
const PART_DAMAGE_MULT := {HEAD: 3.0}

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

## Replicated extra state for the wound model (host assigns a fresh Dictionary on change).
var net_state: Dictionary = {}:
	set(value):
		net_state = value
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


# --- Wound-model interface ----------------------------------------------------------------
# Queries work on every peer (they read replicated state); server_* calls are host only.

## Unconscious or in cardiac arrest: can't act; can be treated, revived, dragged and carried.
func is_unconscious() -> bool:
	return downed


func in_cardiac_arrest() -> bool:
	return false


func is_dead() -> bool:
	return health <= 0.0 and not downed


## Share of blood volume left, 0 to 1.
func blood_fraction() -> float:
	return 1.0


## Pain, 0 to 1.
func pain() -> float:
	return 0.0


## How hurt a conscious unit is, 0 (fine) to 1 (as bad as it gets while still up). AI uses it
## to decide when to treat itself; the medical screen will show the details.
func injury() -> float:
	return clampf(1.0 - health / max_health, 0.0, 1.0) if is_up() else 1.0


## Seconds until this unit dies without help, or -1 if it isn't dying.
func seconds_to_death() -> float:
	return float(bleed_seconds) if downed else -1.0


## Multipliers from wounds, blood loss and pain, applied by movement and aiming.
func speed_mult() -> float:
	return 1.0


func sway_mult() -> float:
	return 1.0


func stamina_mult() -> float:
	return 1.0


## A few words for squad reports and labels, e.g. "Unconscious, 45 s".
func condition_text() -> String:
	if is_dead():
		return "Dead"
	if downed:
		return "Down, %d s" % bleed_seconds
	return "Injured" if injury() > 0.0 else "OK"


## Host only. A round or fragment that got past armor reaches `part` (a hitbox's
## "body_part" meta). `hit` keys: "damage" (the weapon's damage stat), "round_class",
## "position" and "direction" (for the wound channel), "distance" (metres from the shooter).
func server_hit(part: StringName, hit: Dictionary) -> void:
	server_damage(float(hit.get("damage", 10.0)) * float(PART_DAMAGE_MULT.get(part, 1.0)))


## Host only. A round that armor stopped still lands on `part` (impact: pain, stagger,
## concussion, cracked ribs by range). Nothing yet; the wound model adds it.
func server_impact(_part: StringName, _round_class: StringName, _distance: float) -> void:
	pass


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
