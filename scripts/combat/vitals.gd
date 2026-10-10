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
## Consciousness follows the body; there is no revive. Unconscious (downed) while any cause
## holds (why_unconscious): SpO2 under 85%, pain held at the knockout threshold for 3 s, 40% of
## blood lost, cardiac arrest, a concussion knockout, morphine sedation, or total trauma over its
## limit. Once every cause has stayed gone for a short time (10 to 20 s, wake_eta) the
## casualty comes round on their own. Cardiac arrest at 50% lost (or after SpO2 stays very
## low) starts a 10-minute window and ends in death: until wave 3 (IV, CPR, defib) nothing
## restarts a heart. There is no giving up.
##
## Treatment (the "Treatment interface" section) is the design doc's kit: tourniquets,
## bandages, gauze, vented chest seals, splints, morphine and NPAs, each applied by
## server_apply_treatment. care_needed() lists what still needs doing in the casualty-care
## order. Soldier._server_treat is the timed request that players and AI send. Treatment
## wakes casualties by removing causes: a tourniquet stops the slide toward 40% lost,
## morphine eases pain, an NPA clears an obstructed airway so SpO2 recovers.

signal changed
signal went_down
## Came round on their own (every cause of unconsciousness gone for long enough).
signal woke
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
## Host-side dice for the treatment rules: airway obstruction.
var care_rng: RandomNumberGenerator:
	get:
		return _model.care_rng

var _model := WoundModel.new()
var _last_hit_at := -1000.0   # host: when a round or impact last landed (Time seconds)
var _net_dirty := false       # clients: net_state not yet applied to _model
var _sim_left := 0.0          # host: time not yet simulated
var _published := {}          # host: last published state without countdowns
var _published_at := -1000.0
var _publish_pending := false  # host: a routine change held back by the rate limit
var _shown_second := -1        # whole seconds of the arrest countdown last signalled
var _died_sent := false


## A body part in words: "upper_arm_l" -> "left upper arm", TORSO -> "torso".
static func part_name(part: StringName) -> String:
	var text := String(part)
	var side := ""
	if text.ends_with("_l"):
		side = "left "
	elif text.ends_with("_r"):
		side = "right "
	if side != "":
		text = text.left(-2)
	return side + text.replace("_", " ")


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


## Someone (this unit or another) is applying a treatment to this unit right now.
func is_healing() -> bool:
	return _m().is_healing()


## Up and able to act (not down, not dead).
func is_up() -> bool:
	return not downed and not is_dead()


# --- Wound-model interface ----------------------------------------------------------------
# Queries work on every peer (they read replicated state); server_* calls are host only.

## Unconscious or in cardiac arrest: can't act; can be treated, dragged and carried.
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
## to decide when to treat itself. Blood loss counts a little; the rest is what the kit can
## still fix (bleeding it can stop, an unsealed chest wound, pain morphine can take off), so
## splinted fractures and lost blood don't make AI burn through its kit.
func injury() -> float:
	return _m().injury() if is_up() else 1.0


## Up, with something left on care_needed().
func needs_treatment() -> bool:
	return is_up() and not care_needed().is_empty()


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


## Oxygen saturation in percent (normal about 98). Hidden from players: they get laboured
## breathing and greying vision (vision), a medic the cues in signs(). Under 85% you're out;
## long enough under 70% stops the heart.
func spo2() -> float:
	return _m().spo2


## Morphine in the blood, in doses (one autoinjector is 1 once it has gone in over 30 s);
## it halves about every 12 minutes. Pain relief follows it; from 2.5 the casualty is
## sedated (out), past 3 breathing slows.
func morphine_level() -> float:
	return _m().morphine_level


## How badly hurt the body is overall: the wounds' severity added up (less for wounds dealt
## with), fading slowly once they're treated. At 1 or more the casualty stays out.
func trauma_level() -> float:
	return _m().trauma_level


## Why this unit is unconscious: the causes that hold now, most serious first, from
## &"arrest", &"blood" (40% lost), &"spo2", &"pain", &"trauma", &"morphine" (sedation) and
## &"knockout" (concussion). Empty when none holds (awake, or coming round: wake_eta).
func why_unconscious() -> Array[StringName]:
	if not downed:
		var none: Array[StringName] = []
		return none
	return _m().unconscious_causes()


## Seconds until an unconscious unit comes round, if nothing changes; -1 when awake or while
## something still keeps them out.
func wake_eta() -> float:
	var m := _m()
	return m.wake_left if downed and m.wake_left > 0.0 else -1.0


## Laboured breathing: SpO2 low, or an open chest wound or tension pneumothorax.
func breathing_laboured() -> bool:
	return _m().breathing_laboured()


## Plain cues someone checking this unit could see (no numbers): "Unresponsive",
## "Breathing laboured", "Blue lips", "Pinpoint pupils (morphine)". `on_self` gives what you
## notice checking yourself: laboured breathing, and drowsiness from morphine.
func signs(on_self := false) -> PackedStringArray:
	var m := _m()
	var out := PackedStringArray()
	if m.dead:
		return out
	if downed and not on_self:
		out.append("Unresponsive")
	if m.breathing_laboured():
		out.append("Breathing laboured")
	if not on_self and not m.arrest and m.spo2 < WoundModel.SPO2_BLUE_LIPS:
		out.append("Blue lips")
	if m.morphine_level >= WoundModel.MORPHINE_PUPILS_LEVEL:
		out.append("Drowsy (morphine)" if on_self else "Pinpoint pupils (morphine)")
	return out


## The wounds this unit has, for self-interaction and treatment menus: one Dictionary per
## wound with "part" (a body part), "kind" ("arterial", "junctional", "internal", "venous",
## "muscle", "graze", "fracture", "chest", "heart", "rib"), "bleeding" (bleeding now, so not
## under a good tourniquet) and "treated" (bandaged, packed, sealed, splinted; a rib after
## morphine), "rate" (L/min at full blood) and "name" (the vessel or bone, or empty). Also:
## "limb" (the limb segment a tourniquet for it goes on: its own part, or empty off the
## limbs), "tourniquet" (a tourniquet above or on it holds some of its bleeding),
## "packed" (gauze in it) and "tension" (a chest wound's tension pneumothorax has started).
func wound_list() -> Array[Dictionary]:
	var m := _m()
	var list: Array[Dictionary] = []
	for w in m.wounds:
		list.append({"part": w.part, "kind": w.kind, "bleeding": m.rate_now(w) > 0.0,
			"treated": w.treated, "rate": w.rate, "name": w.name,
			"limb": w.part if WoundModel.LIMB_BELOW.has(w.part) else &"",
			"tourniquet": m.tourniquet_factor(w.part) < 1.0, "packed": w.get("packed", false), "tension": w.get("tension", false)})
	return list


# --- Treatment interface (wave 2) -------------------------------------------------------
# The design doc's kit ("The kit", "Tourniquet", "Fractures", "Chest"); the rules and numbers
# are WoundModel's. Soldier._server_treat is the timed host request that uses an item up
# and calls server_apply_treatment; AI casualty care and the interaction menus use the same
# calls. Queries work on every peer.

## Wound kinds, as care_needed() reports them, mapped to the item that treats them.
const TREATS := {
	"arterial": &"tourniquet", "junctional": &"hemostatic_gauze", "venous": &"pressure_bandage",
	"muscle": &"pressure_bandage", "graze": &"pressure_bandage", "chest": &"chest_seal",
	"fracture": &"splint", "airway": &"npa", "pain": &"morphine",
}
## Casualty-care order: massive bleeding, airway, chest, other bleeding, fractures, pain.
const CARE_ORDER := ["arterial", "junctional", "airway", "chest", "venous", "muscle", "graze", "fracture", "pain"]


## What still needs doing for this unit, most urgent first, in the casualty-care order: one
## Dictionary per task with "part", "kind" and "item" (the item id that treats it). A
## tourniquet per limb segment with arterial bleeding (a second one beside a rushed one),
## gauze per junctional bleed, an NPA (kind "airway", part HEAD) for an unconscious casualty,
## a vented seal per open chest wound, a bandage per venous, muscle or graze wound, a splint
## per fracture, morphine (kind "pain", part TORSO) for pain still left once the morphine
## already given has gone in, or a cracked rib. Wounds already handled are left out, and so
## is anything no field item fixes (internal bleeding, a tension pneumothorax already under
## way) and another morphine dose once the blood holds about one (a second one in would
## risk sedation).
func care_needed() -> Array[Dictionary]:
	return _m().care_tasks()


## Why one `item_id` on `part` wouldn't help this unit right now ("" if it would), for menus
## and the host's checks: "Put a tourniquet on first", "No fracture there"...
func treatment_problem(item_id: StringName, part: StringName) -> String:
	return _m().treatment_problem(item_id, part)


## Host only. Applies one use of `item_id` to `part`; returns whether it did anything.
## - tourniquet (a limb segment): stops all bleeding on it and below, adds pain; on a leg, a
##   limp (walk only, no sprint). `rushed` (placed in under 2 s or under fire) lets 30%
##   through until a second tourniquet goes on beside it.
## - pressure_bandage: a venous, muscle or graze wound. hemostatic_gauze: packs a junctional
##   bleed, or an arterial one under a tourniquet so the tourniquet can come off.
## - chest_seal (vented): closes an open chest wound, so no tension pneumothorax starts (one
##   already under way runs on: the needle is wave 3).
## - splint: walking and jogging back on a broken leg, a steadier arm and normal reloads, a
##   lower pain floor; still no sprint until a respawn.
## - morphine: one dose into the blood over 30 s (morphine_level); relief follows the level
##   (0.5 off per dose, at most 0.8) and fades as it wears off (half-life about 12 min).
##   Too much sedates (out from 2.5 doses in the blood) and past 3 slows breathing (SpO2).
##   It also eases a cracked rib's pain.
## - npa: an unconscious casualty's airway can't obstruct (and an obstructed one clears, so
##   SpO2 recovers).
func server_apply_treatment(item_id: StringName, part: StringName, rushed := false) -> bool:
	if not _model.apply_item(item_id, part, rushed):
		return false
	_after_change(true)
	return true


## Why the tourniquets on `part` can't come off yet ("Pack the wound first"), or "".
func removal_problem(part: StringName) -> String:
	return _m().removal_problem(part)


## Host only. Takes the tourniquets off `part` once its arterial bleeding is packed. Returns
## how many came off.
func server_remove_tourniquets(part: StringName) -> int:
	var count := _model.remove_tourniquets(part)
	if count > 0:
		_after_change(true)
	return count


## Tourniquets on, as {part: {"count", "rushed"}}.
func tourniquets() -> Dictionary:
	return _m().tourniquets.duplicate(true)


func has_npa() -> bool:
	return _m().npa


## An unconscious casualty's airway is obstructed (an NPA clears it).
func airway_blocked() -> bool:
	return _m().airway_blocked


## Host only. Someone started applying a treatment that takes `seconds` (is_healing, replicated).
func server_begin_treatment(seconds: float) -> void:
	_model.treating_left = maxf(seconds, 0.0)
	_publish(true)


## Host only. The treatment in progress ended (done or interrupted).
func server_end_treatment() -> void:
	_model.treating_left = 0.0
	_publish(true)


## Host only. Seconds since a round or a stopped round's impact last landed on this unit.
func seconds_since_hit() -> float:
	return Time.get_ticks_msec() / 1000.0 - _last_hit_at


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


## What blood loss, low oxygen, concussion and unconsciousness do to the view, for the local
## player's HUD: "fade" (colour fading: 15-30% lost, or SpO2 falling under 94%), "tunnel"
## (grey edges closing in: 30-40% lost, or SpO2 nearing 85%), "blur" (concussion) and
## "black" (out), each 0 to 1.
func vision() -> Dictionary:
	var m := _m()
	var lost := m.lost()
	var hypoxia := clampf((WoundModel.SPO2_LABOURED - m.spo2) / (WoundModel.SPO2_LABOURED - WoundModel.SPO2_UNCONSCIOUS), 0.0, 1.0)
	return {
		"fade": maxf(clampf((lost - WoundModel.EFFECTS_FROM_LOST) / (WoundModel.NO_SPRINT_LOST - WoundModel.EFFECTS_FROM_LOST), 0.0, 1.0), hypoxia),
		"tunnel": maxf(clampf((lost - WoundModel.NO_SPRINT_LOST) / (WoundModel.UNCONSCIOUS_LOST - WoundModel.NO_SPRINT_LOST), 0.0, 1.0),
			clampf(hypoxia * 2.0 - 1.0, 0.0, 1.0)),
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
	_last_hit_at = Time.get_ticks_msec() / 1000.0
	_model.add_hit(part, channel, round_class)
	_after_change()


## Host only. A round that armor stopped still lands on `part` (impact: pain, stagger,
## winded, concussion, cracked ribs by range, a fatal head injury only where it would be
## real). Head and face are helmet stops; anything else is a plate or vest. `energy_j` is
## the round's energy on arrival (Ballistics), or -1 if unknown.
func server_impact(part: StringName, round_class: StringName, distance: float, energy_j := -1.0) -> void:
	_last_hit_at = Time.get_ticks_msec() / 1000.0
	_model.add_impact(part, round_class, distance, energy_j)
	_after_change()


## Host only. Legacy damage (the debug K key and some tests): generic trauma that adds
## amount/100 pain and loses amount * 0.6% of blood volume at once.
func server_damage(amount: float) -> void:
	_model.add_trauma(amount * TRAUMA_PAIN_PER_DAMAGE, amount * TRAUMA_BLOOD_PER_DAMAGE)
	_after_change()


## Host only. Dead at once, without a wound: the body a player leaves behind when they
## respawn, or a body restored from a zone save (Soldier.server_leave_body).
func server_kill() -> void:
	if _model.dead:
		return
	_model.kill()
	_after_change(true)


## Host only. Back to full health (respawns, dummies getting back up, tests setting up).
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
			woke.emit()
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
