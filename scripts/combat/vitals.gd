class_name Vitals
extends Node
## Host-owned condition of a body: the ACE3/KAT-style wound model from the design doc
## ("Damage and medical"). There are no hitpoints: hits make wounds on body parts, wounds
## drain 6 L of blood at a rate scaled by the heart's output, and blood loss and pain decide
## when a soldier slows, goes unconscious (downed), arrests or dies. The rules and numbers
## live in WoundModel; where vessels, organs and bones sit is BodyMap.
##
## Everything outside this file uses only the "wound-model interface" section below (plus
## the signals, is_up, downed and find_on). The host simulates at about 10 Hz and publishes
## net_state (a fresh Dictionary on change, at most about 2 Hz, at once when consciousness,
## arrest or death change); ServerSync replicates it and `downed` to every peer, including
## late joiners, and every query works on every peer from that state. (Armor damage is
## item state, in Inventory.)
##
## Unconscious (downed) at 40% blood lost or when pain passes the knockout threshold;
## cardiac arrest at 50% lost, which starts a 10-minute window and ends in death unless
## the heart restarts. Until wave 3 (IV, CPR, defib) only the stopgap revive (server_revive,
## an IFAK or trauma kit) does that. There is no giving up.

signal changed
signal went_down
signal revived
signal died

## Round classes for hits and impacts, as the design doc groups them.
const PISTOL := &"pistol"
const INTERMEDIATE := &"intermediate"
const FULL_POWER := &"full_power"
const FRAGMENT := &"fragment"
## Body parts that hitboxes name in their "body_part" meta (BodyMap.PART_BOXES has their
## volumes). Armor (spall, soft armor) and treatment use the same names.
const HEAD := &"head"            # cranium: brain
const FACE := &"face"
const NECK := &"neck"
const TORSO := &"torso"          # whole-torso fallback for hits with no finer part
const CHEST := &"chest"          # heart, lungs, upper torso vessels
const ABDOMEN := &"abdomen"
const PELVIS := &"pelvis"
const UPPER_ARM_L := &"upper_arm_l"
const UPPER_ARM_R := &"upper_arm_r"
const FOREARM_L := &"forearm_l"
const FOREARM_R := &"forearm_r"
const THIGH_L := &"thigh_l"
const THIGH_R := &"thigh_r"
const SHIN_L := &"shin_l"
const SHIN_R := &"shin_r"
const BODY_PARTS: Array[StringName] = [HEAD, FACE, NECK, CHEST, ABDOMEN, PELVIS, UPPER_ARM_L,
	UPPER_ARM_R, FOREARM_L, FOREARM_R, THIGH_L, THIGH_R, SHIN_L, SHIN_R]
const TORSO_PARTS: Array[StringName] = [CHEST, ABDOMEN, PELVIS]

## Seconds of cardiac arrest before death.
const ARREST_WINDOW_S := WoundModel.ARREST_WINDOW_S
## Host simulation step and the shortest gap between routine net_state updates.
const SIM_STEP_S := 0.1
const NET_INTERVAL_S := 0.5
## Stopgap revive (IFAK or trauma kit) until IV in wave 3: blood back up to at least this
## share and pain capped at this.
const REVIVE_BLOOD := 0.62
const REVIVE_PAIN_CAP := 0.5
## Legacy damage (debug K key, old tests) as generic trauma: per point of damage, this much
## pain and this share of blood volume lost at once (K twice at 40 knocks you out).
const TRAUMA_PAIN_PER_DAMAGE := 0.01
const TRAUMA_BLOOD_PER_DAMAGE := 0.006

## False skips the downed state and dies straight away.
@export var can_go_down := true

## Unconscious or in cardiac arrest (replicated at once).
var downed := false:
	set(value):
		downed = value
		changed.emit()

## Replicated wound-model state (host assigns a fresh Dictionary on change; see WoundModel.to_net).
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_net_dirty = true
		changed.emit()

## Host-side dice for wounds, fractures and wake rolls (tests may seed it).
var rng: RandomNumberGenerator:
	get:
		return _model.rng

var _model := WoundModel.new()
var _net_dirty := false       # clients: net_state not yet applied to _model
var _sim_left := 0.0          # host: time not yet simulated
var _published := {}          # host: last published state without countdowns
var _published_at := -1000.0
var _publish_pending := false  # host: a routine change held back by the rate limit
var _shown_second := -1        # whole seconds of the arrest countdown last signalled
var _died_sent := false


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


## A stopgap treatment (server_heal_over_time) is in progress.
func is_healing() -> bool:
	return _m().is_healing()


## Up and able to act (not down, not dead).
func is_up() -> bool:
	return not downed and not is_dead()


# --- Wound-model interface ----------------------------------------------------------------
# Queries work on every peer (they read replicated state); server_* calls are host only.

## Unconscious or in cardiac arrest: can't act; can be treated, revived, dragged and carried.
func is_unconscious() -> bool:
	return downed


func in_cardiac_arrest() -> bool:
	return _m().arrest


func is_dead() -> bool:
	return _m().dead


## Share of blood volume left, 0 to 1.
func blood_fraction() -> float:
	return _m().blood


## Pain, 0 to 1.
func pain() -> float:
	return _m().pain()


## How hurt a conscious unit is, 0 (fine) to 1 (as bad as it gets while still up). AI uses it
## to decide when to treat itself; the medical screen will show the details. Blood loss
## counts a little; the rest is what a stopgap kit can still fix (untreated bleeding and
## pain it can take off), so fractures and lost blood don't make AI burn through its kits.
func injury() -> float:
	return _m().injury() if is_up() else 1.0


## Whether using a stopgap kit (IFAK, trauma kit) on this unit would still do something:
## untreated bleeding, an unsealed chest wound, or pain a kit can take off.
func needs_treatment() -> bool:
	return is_up() and _m().kit_would_help()


## Seconds until this unit dies without help (what's left of the cardiac-arrest window), or
## -1 if it isn't dying.
func seconds_to_death() -> float:
	var m := _m()
	return m.arrest_left if m.arrest and not m.dead else -1.0


## Multipliers from wounds, blood loss and pain, applied by movement and aiming.
func speed_mult() -> float:
	return _m().speed_mult()


func sway_mult() -> float:
	return _m().sway_mult()


## Stamina recovery multiplier (0 while winded).
func stamina_mult() -> float:
	return _m().stamina_mult()


## False with a broken leg (even splinted), from 30% blood lost, or while winded.
func can_sprint() -> bool:
	return _m().can_sprint()


## Reload time multiplier (a broken arm slows reloads).
func reload_mult() -> float:
	return _m().reload_mult()


## Mouse-look multiplier (a concussion slows turning).
func turn_mult() -> float:
	return _m().turn_mult()


## Blood actually leaving the body, in L/min.
func bleed_rate() -> float:
	return _m().bleed_rate()


## The wounds this unit has, for self-interaction and treatment menus: one Dictionary per
## wound with "part" (a body part), "kind" ("arterial", "junctional", "internal", "venous",
## "muscle", "graze", "fracture", "chest", "heart", "rib"), "bleeding" and "treated" (bools),
## "rate" (L/min at full blood) and "name" (the vessel or bone, or empty).
func wound_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for w in _m().wounds:
		list.append({"part": w.part, "kind": w.kind, "bleeding": WoundModel.is_bleeding(w),
			"treated": w.treated, "rate": w.rate, "name": w.name})
	return list


## A few words for squad reports and labels: "OK", "Wounded", "Bleeding", "Unconscious",
## "Cardiac arrest 7:42", "Dead".
func condition_text() -> String:
	var m := _m()
	if m.dead:
		return "Dead"
	if m.arrest:
		var s := ceili(maxf(m.arrest_left, 0.0))
		return "Cardiac arrest %d:%02d" % [floori(s / 60.0), s % 60]
	if downed:
		return "Unconscious"
	if m.wound_bleed_rate() > 0.0:
		return "Bleeding"
	if not m.wounds.is_empty() or m.pain() >= 0.05 or m.lost() >= 0.05:
		return "Wounded"
	return "OK"


## What blood loss, concussion and unconsciousness do to the view, for the local player's
## HUD: "fade" (colour fading, 15-30% lost), "tunnel" (grey edges closing in, 30-40%),
## "blur" (concussion) and "black" (out), each 0 to 1.
func vision() -> Dictionary:
	var m := _m()
	var lost := m.lost()
	return {
		"fade": clampf((lost - WoundModel.EFFECTS_FROM_LOST) / (WoundModel.NO_SPRINT_LOST - WoundModel.EFFECTS_FROM_LOST), 0.0, 1.0),
		"tunnel": clampf((lost - WoundModel.NO_SPRINT_LOST) / (WoundModel.UNCONSCIOUS_LOST - WoundModel.NO_SPRINT_LOST), 0.0, 1.0),
		"blur": clampf(m.concussion_left / 20.0, 0.0, 1.0) if m.concussion_left > 0.0 else 0.0,
		"black": 1.0 if downed or m.dead else 0.0,
	}


## Host only. A round or fragment that got past armor reaches `part` (a hitbox's
## "body_part" meta). `hit` keys: "round_class", "position" and "direction" (world space,
## for the wound channel), "hitbox" (the Area3D it entered, so the channel follows a posed
## or lying body), "distance" (metres from the shooter), "superficial" (a fragment that
## stops short of vessels and organs: a small muscle wound, maybe a fracture). Without a
## position the channel goes in at a random spot on the part. ("damage" is ignored: the
## wound model has none.)
func server_hit(part: StringName, hit: Dictionary) -> void:
	if _m().dead:
		return
	var round_class := StringName(hit.get("round_class", INTERMEDIATE))
	var channel_in := _rest_channel(part, hit)
	var entry: Vector3 = channel_in[0]
	if part == TORSO or not BodyMap.PART_BOXES.has(part):
		part = BodyMap.part_at(entry) if hit.has("position") else TORSO_PARTS[_model.rng.randi() % TORSO_PARTS.size()]
		if not hit.has("position"):
			channel_in = BodyMap.random_channel(part, _model.rng)
	var depth := BodyMap.CHANNEL_MAX_M
	if round_class == FRAGMENT:
		depth = _model.rng.randf_range(BodyMap.FRAGMENT_DEPTH_M.x, BodyMap.FRAGMENT_DEPTH_M.y)
	var channel := BodyMap.trace(part, channel_in[0], channel_in[1], round_class, depth)
	if hit.get("superficial", false):
		channel.vessels = []
		channel.organs = []
	_model.add_hit(part, channel, round_class)
	_after_change()


## Host only. A round that armor stopped still lands on `part` (impact: pain, stagger,
## winded, concussion, cracked ribs by range, a fatal head injury only where it would be
## real). Head and face are helmet stops; anything else is a plate or vest. `energy_j` is
## the round's energy on arrival (Ballistics), or -1 if unknown.
func server_impact(part: StringName, round_class: StringName, distance: float, energy_j := -1.0) -> void:
	_model.add_impact(part, round_class, distance, energy_j)
	_after_change()


## Host only. Legacy damage (the debug K key and some tests): generic trauma that adds
## amount/100 pain and loses amount * 0.6% of blood volume at once.
func server_damage(amount: float) -> void:
	_model.add_trauma(amount * TRAUMA_PAIN_PER_DAMAGE, amount * TRAUMA_BLOOD_PER_DAMAGE)
	_after_change()


## Host only. Stopgap revive with an IFAK or trauma kit until the wave 2 kit and wave 3 IV:
## stops all bleeding, tops blood up to REVIVE_BLOOD, ends cardiac arrest, caps pain and
## wakes the casualty. (The kit's revive_hp no longer matters.)
func server_revive(_hp: float) -> void:
	if not downed or _model.dead:
		return
	_model.revive(REVIVE_BLOOD, REVIVE_PAIN_CAP)
	_after_change(true)


## Host only. Stopgap treatment with an IFAK or trauma kit: stops bleeding wound by wound
## over `seconds` and takes amount/100 off pain. A new one replaces one in progress; going
## unconscious stops it.
func server_heal_over_time(amount: float, seconds: float) -> void:
	if not is_up():
		return
	_model.start_treatment(amount * TRAUMA_PAIN_PER_DAMAGE, seconds)
	_after_change(true)


## Host only. Back to full health (respawns, dummies getting back up).
func server_reset_health() -> void:
	_model.reset()
	_died_sent = false
	_sim_left = 0.0
	if downed:
		downed = false
	_publish(true)


## Host only. Fast-forwards the simulation by `seconds` (tests).
func server_advance(seconds: float) -> void:
	while seconds > 0.0 and not _model.dead:
		var step := minf(seconds, SIM_STEP_S)
		seconds -= step
		_model.advance(step)
		_after_change()
	_publish(true)


# --- Host simulation and replication --------------------------------------------------

func _process(delta: float) -> void:
	_signal_countdown()
	if not _is_host():
		_m().tick_display(delta)
		return
	if _publish_pending and Time.get_ticks_msec() / 1000.0 - _published_at >= NET_INTERVAL_S:
		_publish(false)
	_sim_left += delta
	if _sim_left < SIM_STEP_S:
		return
	var step := _sim_left
	_sim_left = 0.0
	if _model.dead:
		return
	_model.advance(step)
	_after_change()


## Turns model changes into signals and replication.
func _after_change(force := false) -> void:
	if _model.dead:
		if _died_sent:
			return
		_died_sent = true
		if downed:
			downed = false
		_publish(true)
		died.emit()  # may reset us (a player respawns)
		return
	if _model.unconscious and not can_go_down:
		_model.kill()
		_after_change(true)
		return
	if _model.unconscious != downed:
		downed = _model.unconscious
		_publish(true)
		if downed:
			went_down.emit()
		else:
			revived.emit()
		return
	_publish(force)


## Publishes net_state when it changed: at once when forced or when consciousness, arrest or
## death flags changed, otherwise at most every NET_INTERVAL_S. Countdowns alone don't count
## as a change (clients run them down themselves).
func _publish(force: bool) -> void:
	var state := _model.to_net()
	var key := state.duplicate()
	key.erase("t")
	if key == _published and not force:
		_publish_pending = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and key.get("f") == _published.get("f") and now - _published_at < NET_INTERVAL_S:
		_publish_pending = true  # sent from _process once the interval has passed
		return
	_publish_pending = false
	_published = key
	_published_at = now
	net_state = state
	_net_dirty = false


## Emits `changed` each time the arrest countdown passes a whole second, so labels that
## redraw on `changed` (condition_text) keep counting between net_state updates.
func _signal_countdown() -> void:
	var left := seconds_to_death()
	var second := ceili(left) if left >= 0.0 else -1
	if second != _shown_second:
		_shown_second = second
		changed.emit()


## The model to read: the host's own, or on a client the copy rebuilt from net_state.
func _m() -> WoundModel:
	if _net_dirty and not _is_host():
		_net_dirty = false
		_model.apply_net(net_state)
	return _model


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


## The wound channel's entry point and direction in the rest pose (see BodyMap): through the
## hitbox it entered, or the body, or at random when the hit has no position.
func _rest_channel(part: StringName, hit: Dictionary) -> Array:
	if not hit.has("position"):
		return BodyMap.random_channel(part, _model.rng)
	var space := hit.get("hitbox") as Node3D
	if space == null or not space.is_inside_tree():
		space = get_parent() as Node3D
	var to_rest := Transform3D.IDENTITY
	if space and space.is_inside_tree():
		to_rest = space.global_transform.affine_inverse()
	var direction: Vector3 = hit.get("direction", Vector3.BACK)
	return [to_rest * Vector3(hit.position), (to_rest.basis * direction).normalized()]
