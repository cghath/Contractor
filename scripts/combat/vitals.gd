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
## arrest or death change), and every query works on every peer from that state. (Armor
## damage is item state, in Inventory.)
##
## Replication (the same split as Inventory's net_gear/net_ammo): net_state itself isn't sent.
## ServerSync replicates `downed` and two parts of it to every peer, late joiners included
## (spawn): `net_vitals`, the structure that changes only on real events (wounds, tourniquets,
## the line and bag, the triage card; STRUCT_KEYS) with a revision, sent only when it changes;
## and `net_pulse`, the fast scalars (blood, pain, SpO2, heart rate, drugs, lungs, flags,
## countdowns) quantised into a few dozen bytes (_encode_pulse), sent when a quantised value
## changes, at most every NET_INTERVAL_S (at once when the flags change). A peer rebuilds
## net_state from the two (merge_net) and reads it as before.
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
## Moving slower than this (m/s) counts as lying still, for hypothermia.
const STILL_SPEED := 0.3
## Legacy damage (debug K key, old tests) as generic trauma: per point of damage, this much
## pain and this share of blood volume lost at once (K twice at 40 knocks you out).
const TRAUMA_PAIN_PER_DAMAGE := 0.01
const TRAUMA_BLOOD_PER_DAMAGE := 0.006

## False skips the downed state and dies straight away.
@export var can_go_down := true

## Triage card (a carer sets it on a casualty; replicated in net_state under "tg").
const TRIAGE_NONE := &"none"
const TRIAGE_MINIMAL := &"minimal"      # green
const TRIAGE_DELAYED := &"delayed"      # yellow
const TRIAGE_IMMEDIATE := &"immediate"  # red
const TRIAGE_EXPECTANT := &"expectant"  # black
const TRIAGE_CARDS: Array[StringName] = [TRIAGE_NONE, TRIAGE_MINIMAL, TRIAGE_DELAYED, TRIAGE_IMMEDIATE, TRIAGE_EXPECTANT]
const TRIAGE_TEXT := {TRIAGE_NONE: "No card", TRIAGE_MINIMAL: "Minimal (green)", TRIAGE_DELAYED: "Delayed (yellow)",
	TRIAGE_IMMEDIATE: "Immediate (red)", TRIAGE_EXPECTANT: "Expectant (black)"}
const TRIAGE_COLORS := {TRIAGE_NONE: Color(0.55, 0.57, 0.6), TRIAGE_MINIMAL: Color(0.3, 0.75, 0.35), TRIAGE_DELAYED: Color(0.95, 0.85, 0.2),
	TRIAGE_IMMEDIATE: Color(0.9, 0.2, 0.15), TRIAGE_EXPECTANT: Color(0.05, 0.05, 0.05)}
var _triage: StringName = TRIAGE_NONE
## The shared triage log (cghath's list, 2026-10-20, "Medical"): who did what to this casualty,
## and when, the same for everyone treating him (the medical menu shows it). Host-owned, kept
## here on the casualty so it goes wherever he does (carried, dragged, across a crossing: it's
## in server_snapshot), replicated in net_state under "tl" (part of the structure: it changes
## only on events), late joiners included. Each entry is [when (the zone's clock, "14:05"), who,
## what]. The oldest go past CARE_LOG_KEEP.
const CARE_LOG_KEEP := 24
var _care_log: Array = []

## Unconscious or in cardiac arrest (replicated at once).
var downed := false:
	set(value):
		downed = value
		changed.emit()

## Wound-model state (see WoundModel.to_net, plus "tg" the triage card and "tl" the shared
## triage log, care_log). The host assigns a
## fresh Dictionary on each publish; a peer rebuilds it from net_vitals and net_pulse. Not
## replicated itself.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_net_dirty = true
		changed.emit()

## Keys of net_state that make up the structure (net_vitals): they change only on real events.
## "v" (the bag) goes here as [item, mL]; the mL left goes in the pulse.
const STRUCT_KEYS: Array[String] = ["w", "q", "a", "v", "tg", "tl"]
## Replicated (ServerSync): the structure of net_state (STRUCT_KEYS) plus "r", its revision.
## The host sets it only when the structure changes.
var net_vitals: Dictionary = {}:
	set(value):
		net_vitals = value
		if not _publishing:
			_receive(false)

## Replicated (ServerSync): the fast-changing scalars, quantised (_encode_pulse), starting with
## the revision of the structure they go with.
var net_pulse: PackedByteArray = PackedByteArray():
	set(value):
		net_pulse = value
		if not _publishing:
			_receive(true)

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
## Host: what last hurt this body ({"cause", "part", "distance"}), for the session log (SessionLog) and nothing else.
var last_cause := {}
var _net_dirty := false       # clients: net_state not yet applied to _model
var _last_pos := Vector3.INF  # host: where the body was last step (_track_stillness)
var _sim_left := 0.0          # host: time not yet simulated
var _published := {}          # host: last published state without countdowns
var _published_at := -1000.0
var _publish_pending := false  # host: a routine change held back by the rate limit
var _shown_second := -1        # whole seconds of the arrest countdown last signalled
var _died_sent := false
var _struct_rev := 0           # host: revision of the last structure sent; peer: of the one held
var _sent_struct := {}         # host: the structure last sent (without "r")
var _sent_pulse := PackedByteArray()  # host: the last pulse sent, without revision and countdowns
var _publishing := false       # host: setting net_vitals/net_pulse to send them
var _timers_fresh := false     # peer: a pulse (with its countdowns) came since _m() last rebuilt
## Host only: spawn protection (Soldier.respawn_state, after a respawn or while waiting for one):
## rounds, impacts, blasts, falls, burns and trauma do nothing.
var shielded := false


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


## `rifle`: a shouldered weapon in hand (a broken collarbone only hurts then).
func sway_mult(rifle := false) -> float:
	return _m().sway_mult(rifle)


## How fast aiming down sights moves (a broken collarbone, rifles only).
func aim_mult(rifle := false) -> float:
	return _m().aim_mult(rifle)


## False with a broken pelvis: no standing or walking, crawl or be carried (a binder only
## stops the bleeding).
func can_stand() -> bool:
	return _m().can_stand()


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


## Both lungs' efficiency averaged, 0 (none) to 1 (healthy): collapse (pneumothorax), blood in
## them (hemothorax) and the push from a tension pneumothorax on the other side.
func lung_efficiency() -> float:
	return _m().lung_efficiency()


## One lung (&"lung_l", &"lung_r"): {"collapse", "fluid", "efficiency"}, each 0 to 1.
func lung(which: StringName) -> Dictionary:
	var m := _m()
	return {"collapse": float(m.lung_collapse[which]), "fluid": float(m.lung_fluid[which]),
		"efficiency": m.lung_efficiency_of(which)}


## Breaths per minute (hidden; faster as the lungs or the blood fail, slow on too much
## morphine, none in arrest).
func respiratory_rate() -> float:
	return _m().respiratory_rate()


## A tension pneumothorax is running (the decompression needle relieves it).
func has_tension() -> bool:
	return _m().has_tension()


## Beats per minute (hidden; a medic feels it as a pulse, a pulse oximeter shows it); 0 in
## cardiac arrest.
func heart_rate() -> float:
	return _m().heart_rate


## A drug in the blood plus what's still going in, in doses: &"epinephrine", &"atropine",
## &"adenosine" (morphine: morphine_level).
func drug_total(id: StringName) -> float:
	return _m().drug_total(id)


## Blood is back far enough (60%) for CPR or the defibrillator to restart the heart.
func can_restart_heart() -> bool:
	return _m().can_restart()


## Seconds of muffled hearing left (blasts, flashbangs, indoor gunfire); 0 when fine.
func deaf_left() -> float:
	return _m().deaf_left


## Share of the body burned, 0 to 1.
func burn_share() -> float:
	return _m().burn


## Lying still after heavy blood loss with no blanket: bleeding faster.
func hypothermic() -> bool:
	return _m().hypothermic()


## Blast lung: both lungs slowly fill (no field fix; needs evacuation).
func has_blast_lung() -> bool:
	return _m().blast_lung


## A chest wound closed by surgery could reopen if the unit exerts themselves.
func has_closed_chest() -> bool:
	return _m().wounds.any(func(w: Dictionary) -> bool: return w.kind == "chest" and w.get("closed", false))


## Host only. The unit exerted themselves (sprint, jump, moving under an extreme load): a
## surgically closed chest wound may reopen. Returns whether one did.
func server_exert() -> bool:
	if _model.exert() <= 0:
		return false
	_after_change(true)
	return true


## Host only. A blast `distance` metres away (radius already doubled indoors); see
## WoundModel.add_blast.
func server_blast(distance: float, radius: float, ear_pro := false) -> void:
	if shielded:
		return
	_model.add_blast(distance, radius, ear_pro)
	_last_hit_at = Time.get_ticks_msec() / 1000.0
	last_cause = {"cause": "blast", "distance": distance}
	_after_change(true)


## Host only. A fall from `height` metres (see WoundModel.add_fall).
func server_fall(height: float) -> void:
	if shielded:
		return
	_model.add_fall(height)
	last_cause = {"cause": "fall (%.1f m)" % height}
	_after_change(true)


## Host only. Burns over `share` of the body.
func server_burn(share: float) -> void:
	if shielded:
		return
	_model.add_burn(share)
	last_cause = {"cause": "burn"}
	_after_change(true)


## Host only. A shot fired indoors close by (see WoundModel.add_noise).
func server_noise(amount: float, ear_pro := false) -> void:
	_model.add_noise(amount, ear_pro)
	_publish(true)


## Host only. A flashbang's ringing ears for `seconds` (none with ear protection).
func server_deafen(seconds: float, ear_pro := false) -> void:
	_model.deafen(seconds, ear_pro)
	_publish(true)


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
	if m.blast_lung:
		out.append("Coughing blood")
	if m.hypothermic():
		out.append("Shivering, skin cold")
	elif m.blanket:
		out.append("Wrapped in a blanket")
	if m.burn > 0.0:
		var dressed := " (%d dressed)" % m.burn_dressings if m.burn_dressings > 0 else ""
		out.append("Burns over about %d%% of the body%s" % [roundi(m.burn * 100.0 / 5.0) * 5, dressed])
	if on_self and m.deaf_left > 0.0:
		out.append("Ears ringing")
	var rate := m.respiratory_rate()
	if not m.arrest and rate > WoundModel.RESP_FAST:
		out.append("Breathing fast")
	elif not m.arrest and rate < WoundModel.RESP_SLOW:
		out.append("Breathing slow")
	if not on_self and not m.arrest and m.spo2 < WoundModel.SPO2_BLUE_LIPS:
		out.append("Blue lips")
	if not on_self:
		for which in WoundModel.LUNGS:
			if float(m.lung_collapse[which]) >= 0.5:
				out.append("No breath sounds on the %s" % ("left" if which == WoundModel.LUNGS[0] else "right"))
		if m.has_tension():
			out.append("Trachea shifted, neck veins bulging")
		if m.arrest:
			out.append("No pulse")
		elif m.heart_rate > WoundModel.HR_RACING:
			out.append("Pulse racing")
		elif m.heart_rate > 110.0:
			out.append("Pulse fast and weak" if m.shock() > 0.3 else "Pulse fast")
		elif m.heart_rate < WoundModel.HR_SLOW:
			out.append("Pulse slow")
	elif m.heart_rate > 120.0:
		out.append("Heart pounding")
	if m.morphine_level >= WoundModel.MORPHINE_PUPILS_LEVEL:
		out.append("Drowsy (morphine)" if on_self else "Pinpoint pupils (morphine)")
	if not m.access.is_empty():
		var line := "IO line, sternum" if m.access.kind == "io" else "IV %dG, %s" % [int(m.access.gauge), part_name(m.access.part)]
		out.append(line + (" (pressure bag)" if m.access.pressure else ""))
	if not m.infusion.is_empty():
		var item := ItemDB.get_item(m.infusion.item) if ItemDB.has_item(m.infusion.item) else null
		out.append("%s running, %d mL left" % [item.name if item else "Bag", ceili(float(m.infusion.left))])
	return out


## The wounds this unit has, for self-interaction and treatment menus: one Dictionary per
## wound with "part" (a body part), "kind" ("arterial", "junctional", "internal", "venous",
## "muscle", "graze", "fracture", "chest", "heart", "rib", "brain"), "bleeding" (bleeding now, so not
## under a good tourniquet) and "treated" (bandaged, packed, sealed, splinted; a rib after
## morphine), "rate" (L/min at full blood) and "name" (the vessel or bone, or empty). Also:
## "limb" (the limb segment a tourniquet for it goes on: its own part, or empty off the
## limbs), "tourniquet" (a tourniquet above or on it holds some of its bleeding),
## "packed" (gauze in it), "tension" (a chest wound's tension pneumothorax has started),
## "clamped" (a surgical clamp holds it) and "closed" (a chest wound closed by surgery). "at" and
## "out": where the round went in and came out (rest pose; null if unknown or it stayed in).
func wound_list() -> Array[Dictionary]:
	var m := _m()
	var list: Array[Dictionary] = []
	for w in m.wounds:
		list.append({"part": w.part, "kind": w.kind, "bleeding": m.rate_now(w) > 0.0,
			"treated": w.treated, "rate": w.rate, "name": w.name,
			"limb": w.part if WoundModel.LIMB_BELOW.has(w.part) else &"",
			"tourniquet": m.tourniquet_factor(w.part) < 1.0, "packed": w.get("packed", false), "tension": w.get("tension", false),
			"clamped": w.get("clamped", false), "closed": w.get("closed", false), "pneumo": w.get("pneumo", false),
			"open": w.get("open", false), "bandaged": m.open_bandaged(w),
			"at": w.get("at"), "out": w.get("out"), "round_class": w.get("rc", &""), "dmg": float(w.get("dmg", 0.0))})
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
	"fracture": &"splint", "pelvis": &"pelvic_binder", "airway": &"npa", "pain": &"morphine", "tension": &"decompression_needle",
	"access": &"iv_18", "fluids": &"saline_500", "pressure": &"pressure_bag",  # the usual picks; see care_needed "items"
	"epinephrine": &"epinephrine", "defib": &"defibrillator", "cpr": &"cpr", "racing": &"adenosine",
	"slow_heart": &"atropine", "wake": &"epinephrine", "internal": &"surgical_clamp", "hypothermia": &"hypothermia_blanket",
	"burn": &"burn_dressing",
}
## Casualty-care order: massive bleeding (internal bleeding under a surgical clamp), airway,
## tension (the needle), chest, other bleeding, circulation (line, bag, pressure bag),
## hypothermia (a blanket), restarting a heart (epinephrine, shocks, CPR), the heart rate
## (adenosine, atropine), fractures, burns, pain, then epinephrine's wake-up roll.
const CARE_ORDER := ["arterial", "junctional", "internal", "pelvis", "airway", "tension", "chest", "venous", "muscle", "graze", "access", "fluids",
	"pressure", "hypothermia", "epinephrine", "defib", "cpr", "racing", "slow_heart", "fracture", "burn", "pain", "wake"]


## What still needs doing for this unit, most urgent first, in the casualty-care order: one
## Dictionary per task with "part", "kind" and "item" (the item id that treats it). A
## tourniquet per limb segment with arterial bleeding (a second one beside a rushed one),
## gauze per junctional bleed, an NPA (kind "airway", part HEAD) for an unconscious casualty,
## a vented seal per open chest wound, a bandage per venous, muscle or graze wound, a splint
## per fracture, morphine (kind "pain", part TORSO) for pain still left once the morphine
## already given has gone in, or a cracked rib. From 15% blood lost: IV or IO access (kind
## "access", on the forearm the IV goes in), then a bag (kind "fluids"), and a pressure bag
## once veins collapse (kind "pressure"); "access" and "fluids" tasks list every item that
## would do in "items", best pick first (pick_item). Wounds already handled are left out, and so
## is anything no field item fixes (internal bleeding, a tension pneumothorax already under
## way) and another morphine dose once the blood holds about one (a second one in would
## risk sedation).
func care_needed() -> Array[Dictionary]:
	return _m().care_tasks()


## The item to use for `task` (a care_needed() entry) from what `inventory` holds, loose or in
## a kit: the first of its "items" carried, or its "item"; &"" if none is carried.
static func pick_item(task: Dictionary, inventory: Inventory) -> StringName:
	for id: StringName in task_items(task):
		if has_item(inventory, id):
			return id
	return &""


## `inventory` holds `id` (loose or in a kit), or `id` needs no item (CPR: stats.no_item).
static func has_item(inventory: Inventory, id: StringName) -> bool:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	return (item != null and item.stats.get("no_item", false)) or inventory.medical_count(id) > 0


## Every item that would do for `task`, best pick first.
static func task_items(task: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(task.get("items", [task.item]))
	return out


## Items a treater can't use on themselves: an IV or IO, CPR and the defibrillator need
## someone else's hands.
static func needs_other_hands(item_id: StringName) -> bool:
	return item_id == WoundModel.IO_KIT or WoundModel.IV_GAUGES.has(item_id) or item_id == WoundModel.CPR \
		or item_id == WoundModel.DEFIBRILLATOR


## How many times its usual time `item_id` takes on this unit now (an IV in shock is slower).
func treat_time_mult(item_id: StringName) -> float:
	return _m().treat_time_mult(item_id)


## The IV or IO line: {} for none, else "kind" ("iv" or "io"), "gauge" (an IV's), "part" and
## "pressure" (under a pressure bag).
func access() -> Dictionary:
	return _m().access.duplicate()


## An IV can go in `site` (WoundModel.IV_SITES: both forearms, both lower legs): no
## tourniquet on or above it.
func iv_site_ok(site: StringName) -> bool:
	return _m().iv_site_ok(site)


## The bag running on the line: {} for none, else "item", "ml" and "left" (mL), plus "rate"
## (mL per second going in now).
func infusion() -> Dictionary:
	var m := _m()
	if m.infusion.is_empty():
		return {}
	var out := m.infusion.duplicate()
	out.rate = m.infusion_rate()
	return out


## Host: what the last treatment has to tell the treater ("Missed the vein"), or "".
func care_note() -> String:
	return _model.care_note


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
##   already under way runs on until the decompression needle).
## - splint: walking and jogging back on a broken leg, a steadier arm and normal reloads, a
##   lower pain floor; still no sprint until a respawn.
## - morphine: one dose into the blood over 30 s (morphine_level); relief follows the level
##   (0.5 off per dose, at most 0.8) and fades as it wears off (half-life about 12 min).
##   Too much sedates (out from 2.5 doses in the blood) and past 3 slows breathing (SpO2).
##   It also eases a cracked rib's pain.
## - npa: an unconscious casualty's airway can't obstruct (and an obstructed one clears, so
##   SpO2 recovers).
## - iv_10 to iv_20: an IV line in a forearm; bigger bores flow faster and hurt more. In shock
##   it can miss (the catheter is used up; care_note says so). io_kit: an IO line in the
##   sternum, always. One line at a time.
## - saline_* / blood_* (250, 500, 1000 mL): a bag on the line, going in over minutes; the
##   only way blood comes back. pressure_bag: on the line, faster flow (and needed once
##   veins collapse at 37% lost).
## - decompression_needle: relieves a tension pneumothorax (and the arrest it was heading for).
## - epinephrine, atropine, adenosine: a dose into the blood (heart rate up, up, down);
##   epinephrine also helps CPR and shocks restart a heart, and has a wake-up roll for
##   someone out with nothing but a concussion knockout keeping them out.
## - cpr (hands only, a 10 s cycle) and defibrillator (a 5 s shock; not used up): a chance to
##   restart a heart in arrest, once blood is back to 60%; care_note says whether it worked.
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
## A round arriving with this much energy or more kills whatever it hits (.50 BMG class; a .338
## at ~6.7 kJ doesn't). Captain, 2026-10-16.
const LETHAL_J := 9000.0
## Joules that score one point of BodyDeform damage (a 5.56 at fighting range ~1).
const DAMAGE_J := 1650.0


## A round's BodyDeform damage: its energy over DAMAGE_J (7.62x51 ~2, 7.62x54R ~2, .338 ~4, .50
## ~10), or by class when the energy isn't known.
static func round_damage(round_class: StringName, energy_j: float) -> float:
	if energy_j > 0.0:
		return snappedf(energy_j / DAMAGE_J, 0.1)
	return {PISTOL: 0.5, INTERMEDIATE: 1.0, FULL_POWER: 2.0, FRAGMENT: 0.6}.get(round_class, 1.0)

## Host: the last hit that landed ({"position", "direction" (world), "round_class", "time"}): the
## ragdoll takes its push when this one drops the body (Ragdoll.start).
var last_hit := {}


func server_hit(part: StringName, hit: Dictionary) -> void:
	if shielded:
		return
	if hit.has("position") and hit.has("direction"):
		last_hit = {"position": hit.position, "direction": hit.direction, "round_class": StringName(hit.get("round_class", INTERMEDIATE)),
			"time": Time.get_ticks_msec() / 1000.0}
	var was_dead := _m().dead  # a corpse still takes holes (BodyDeform), nothing else
	var round_class := StringName(hit.get("round_class", INTERMEDIATE))
	var channel_in := _rest_channel(part, hit)
	var entry: Vector3 = channel_in[0]
	if part == TORSO or not BodyMap.PART_BOXES.has(part):
		part = BodyMap.part_at(entry) if hit.has("position") else TORSO_PARTS[_model.rng.randi() % TORSO_PARTS.size()]
		if not hit.has("position"):
			channel_in = BodyMap.random_channel(part, _model.rng)
	var depth := minf(BodyMap.CHANNEL_MAX_M, float(hit.get("channel_depth", BodyMap.CHANNEL_MAX_M)))
	if round_class == FRAGMENT:
		depth = _model.rng.randf_range(BodyMap.FRAGMENT_DEPTH_M.x, BodyMap.FRAGMENT_DEPTH_M.y)
	var channel := BodyMap.trace(part, channel_in[0], channel_in[1], round_class, depth)
	if hit.get("superficial", false):
		channel.vessels = []
		channel.organs = []
	_last_hit_at = Time.get_ticks_msec() / 1000.0
	var added: Array = []
	if was_dead:
		if not hit.has("position"):
			return
		var mark := {"part": part, "kind": "postmortem", "rate": 0.0, "treated": false, "name": &"postmortem", "tension_in": -1.0, "arrest_in": -1.0}
		_model.wounds.append(mark)
		added = [mark]
	else:
		added = _model.add_hit(part, channel, round_class)
	if not was_dead:
		last_cause = {"cause": "fragment" if round_class == FRAGMENT else "round (%s)" % round_class, "part": part, "distance": float(hit.get("distance", -1.0))}
	if hit.has("position"):
		# Where it went in, and out if it went through (the body ended before the channel
		# did), in the rest pose: the wound marks on the model (CharacterModel) show them.
		var exits: bool = round_class != FRAGMENT and hit.has("channel_depth") and not hit.get("stays_in", false) and depth < BodyMap.CHANNEL_MAX_M - 0.001 and not channel.graze
		for w: Dictionary in added:
			w["rc"] = round_class  # what made it (BodyDeform: a .308 tears more than a 5.56)
			w["dmg"] = round_damage(round_class, float(hit.get("energy_j", -1.0)))
			w["at"] = channel.from
			if exits:
				w["out"] = channel.to
	if was_dead:
		_publish(true)  # _after_change goes quiet once he's dead: the corpse's new holes still go out
		return
	if not was_dead:
		_check_amputation(part)
	if not was_dead and float(hit.get("energy_j", -1.0)) >= LETHAL_J and round_class != FRAGMENT:
		server_kill()  # a .50 hit (Captain, 2026-10-16: ".50 cal is insta death")
		return
	_after_change()
	if not was_dead and get_parent() is Soldier:
		(get_parent() as Soldier).server_hit_reaction(part)  # a weapon knocked out of his hands (G-23)



## Host only. A limb torn off while he lives (Captain, 2026-10-16: "make it so surviving losing arms
## or legs is possible with a good medic"): once a limb part has a broken bone and
## BodyDeform.SEVER_ALIVE points of rounds in it, it comes off: an "amputation" wound, a heavy
## arterial bleed at the stump (AMPUTATION_RATE). It's an arterial limb bleed like any other, so a
## tourniquet above it stops it; quick hands and fluids and he lives. BodyDeform cuts the limb
## where the replicated wound says.
const AMPUTATION := &"amputation"
const AMPUTATION_RATE := {"leg": 1.4, "arm": 0.9}  # L/min


func _check_amputation(part: StringName) -> void:
	if not part in BodyDeform.LIMBS:
		return
	var broken := false
	var score := 0.0
	var rounds := {}
	for w: Dictionary in _model.wounds:
		if w.part != part:
			continue
		if w.get("name") == AMPUTATION:
			return  # gone already
		if String(w.kind) == "fracture":
			broken = true
		var at: Variant = w.get("at")
		if at is Vector3 and not rounds.has(at):
			rounds[at] = true
			score += BodyDeform._points(w, StringName(w.get("rc", &"")))
	if not broken or score < BodyDeform.SEVER_ALIVE:
		return
	var leg := part in [THIGH_L, THIGH_R, SHIN_L, SHIN_R]
	_model._add_wound(part, "arterial", float(AMPUTATION_RATE["leg" if leg else "arm"]), AMPUTATION)

## Host only. A round that armor stopped still lands on `part` (impact: pain, stagger,
## winded, concussion, cracked ribs by range, a fatal head injury only where it would be
## real). Head and face are helmet stops; anything else is a plate or vest. `energy_j` is
## the round's energy on arrival (Ballistics), or -1 if unknown.
func server_impact(part: StringName, round_class: StringName, distance: float, energy_j := -1.0) -> void:
	if shielded:
		return
	_last_hit_at = Time.get_ticks_msec() / 1000.0
	_model.add_impact(part, round_class, distance, energy_j)
	last_cause = {"cause": "round stopped by armor (%s)" % round_class, "part": part, "distance": distance}
	_after_change()


## Host only. Legacy damage (the debug K key and some tests): generic trauma that adds
## amount/100 pain and loses amount * 0.6% of blood volume at once.
func server_damage(amount: float) -> void:
	if shielded:
		return
	_model.add_trauma(amount * TRAUMA_PAIN_PER_DAMAGE, amount * TRAUMA_BLOOD_PER_DAMAGE)
	last_cause = {"cause": "trauma (%.0f damage)" % amount}
	_after_change()


## Host only. One wound of `kind` on `part` bleeding `rate` L/min and nothing else: no hit, pain
## or shock (the tutorial's graze to treat: TutorialGuide). Returns it.
func server_add_wound(part: StringName, kind: String, rate: float) -> Dictionary:
	var w := _model._add_wound(part, kind, rate)
	_model.update_state(0.0)
	_after_change(true)
	return w


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
	_triage = TRIAGE_NONE
	_care_log = []  # a fresh body (a respawn): nobody has treated it yet
	_died_sent = false
	_sim_left = 0.0
	if downed:
		downed = false
	_publish(true)


## The triage card on this casualty (TRIAGE_*), on every peer.
func triage() -> StringName:
	if _is_host():
		return _triage
	return StringName(net_state.get("tg", TRIAGE_NONE))


## Host only. Puts `card` (a TRIAGE_* id) on this casualty.
func server_set_triage(card: StringName) -> void:
	if not TRIAGE_CARDS.has(card) or _model.dead:
		return
	_triage = card
	_publish(true)
	changed.emit()


## The shared triage log on this casualty, oldest first: [{"t" (when, the zone's clock),
## "who", "what"}], on every peer (the host's own, or what it replicated).
func care_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in (_care_log if _is_host() else net_state.get("tl", [])):
		if e is Array and (e as Array).size() >= 3:
			out.append({"t": String(e[0]), "who": String(e[1]), "what": String(e[2])})
	return out


## Host only. Adds "`who`: `what`" to the shared triage log, stamped with the zone's clock (the
## day-night cycle's hour; the host's clock where a level has none), the same text for every peer.
func server_log_care(who: String, what: String) -> void:
	if not _is_host() or what == "":
		return
	_care_log.append([care_time(), who, what])
	while _care_log.size() > CARE_LOG_KEEP:
		_care_log.pop_front()
	_publish(true)
	changed.emit()


## When a care log entry is made: the zone's hour ("14:05"), else the host's clock ("14:05:31").
static func care_time() -> String:
	var dn := DayNight.current()
	if dn != null:
		var h := fposmod(dn.hour, 24.0)
		return "%02d:%02d" % [floori(h), floori(fposmod(h * 60.0, 60.0))]
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


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
	_track_stillness(step)
	_model.advance(step)
	_after_change()


## Host: how long the body has lain or stood still (hypothermia), from how far it moved.
func _track_stillness(step: float) -> void:
	var body := get_parent() as Node3D
	if body == null or not body.is_inside_tree():
		return
	var pos := body.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	_model.still_s = _model.still_s + step if moved < STILL_SPEED * step else 0.0
	if not downed and moved / step < 10.0:  # a carried body, or a teleport, isn't moving on its own leg
		_model.add_leg_strain(moved, moved / step)  # moving on a broken leg can open the break


## Turns model changes into signals and replication.
func _after_change(force := false) -> void:
	_log_open_breaks()
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


## Host: a session-log line for each break that went open, under the body's log name
## (SessionLog.who: a target dummy as one, not "someone"). SessionLog does nothing without a session.
func _log_open_breaks() -> void:
	for line: String in _model.take_open_events():
		if SessionLog.session_id != "":
			SessionLog.note("%s: %s" % [SessionLog.who(get_parent()), line])


## Publishes net_state when it changed: at once when forced or when consciousness, arrest or
## death flags changed, otherwise at most every NET_INTERVAL_S. Countdowns alone don't count
## as a change (clients run them down themselves).
## Host: this body's whole condition (the wound model, downed, the triage card and the shared
## triage log), to carry into the next zone (LZ-2 crossings) and into a save (a resumed
## deployment's, people, checkpoints); server_restore puts it on a fresh body there.
func server_snapshot() -> Dictionary:
	return {"model": _model.snapshot(), "downed": downed, "triage": _triage, "care_log": _care_log.duplicate(true)}


func server_restore(snap: Dictionary) -> void:
	if not multiplayer.is_server() or snap.is_empty():
		return
	_model.restore(snap.get("model", {}))
	_triage = snap.get("triage", _triage)
	_care_log = []
	for e: Variant in snap.get("care_log", []):  # (older saves: none)
		if e is Array and (e as Array).size() >= 3:
			_care_log.append([String(e[0]), String(e[1]), String(e[2])])
	downed = bool(snap.get("downed", false))
	_publish(true)


func _publish(force: bool) -> void:
	var state := _model.to_net()
	state["tg"] = String(_triage)
	state["tl"] = _care_log.duplicate(true)
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
	_send(state, force)


## Host: sends what changed of `state` (a net_state just published): the structure only when it
## changed, under a new revision, and the pulse when a quantised value changed (or along with a
## new structure, so the two arrive together). `force` (a forced publish: a treatment started
## or ended, a wake countdown began) also sends countdowns that changed on their own; routine
## publishes leave those to the clients, which run them down themselves.
func _send(state: Dictionary, force: bool) -> void:
	var parts := split_net(state)
	var structure: Dictionary = parts[0]
	var pulse_key := _encode_pulse(parts[1], 0, false)
	var struct_changed := structure != _sent_struct or net_vitals.is_empty()
	var pulse := _encode_pulse(parts[1], (_struct_rev + 1) % 65536 if struct_changed else _struct_rev, true)
	if not struct_changed and (pulse == net_pulse if force else pulse_key == _sent_pulse):
		return
	_publishing = true
	if struct_changed:
		_struct_rev = (_struct_rev + 1) % 65536
		_sent_struct = structure
		var sent := structure.duplicate()
		sent["r"] = _struct_rev
		net_vitals = sent
	_sent_pulse = pulse_key
	net_pulse = pulse
	_publishing = false


## net_state split in two: [the structure (STRUCT_KEYS), the scalars (everything else, with
## the bag's mL left as "vl")].
static func split_net(state: Dictionary) -> Array[Dictionary]:
	var structure := {}
	var scalars := {}
	for key: String in state:
		if key == "v":
			var bag: Array = state.v
			structure["v"] = bag.slice(0, 2)
			scalars["vl"] = float(bag[2]) if bag.size() > 2 else 0.0
		elif key in STRUCT_KEYS:
			structure[key] = state[key]
		else:
			scalars[key] = state[key]
	return [structure, scalars]


## A net_state from a structure (net_vitals) and a pulse (net_pulse): what the host published,
## to the pulse's quantisation.
static func merge_net(structure: Dictionary, pulse: PackedByteArray) -> Dictionary:
	var state := structure.duplicate()
	state.erase("r")
	var scalars := decode_pulse(pulse)
	var left: float = scalars.get("vl", 0.0)
	scalars.erase("vl")
	state.merge(scalars, true)
	var bag: Array = state.get("v", [])
	if bag.size() >= 2:
		state["v"] = [bag[0], bag[1], left]
	return state


## The pulse's scalars, each sent as a whole number of steps: [net_state key, index in its
## array value (-1: a plain number), step, bytes]. The steps are net_state's own rounding.
const PULSE_FIELDS := [["b", -1, 0.001, 2], ["p", -1, 0.01, 2], ["i", -1, 0.01, 2], ["o", -1, 0.5, 1],
	["m", -1, 0.01, 2], ["d", -1, 0.01, 2], ["x", -1, 0.01, 2], ["h", -1, 1.0, 1],
	["l", 0, 0.01, 1], ["l", 1, 0.01, 1], ["l", 2, 0.01, 1], ["l", 3, 0.01, 1],
	["u", 0, 0.01, 1], ["u", 1, 1.0, 1], ["u", 2, 0.01, 2], ["vl", -1, 1.0, 2]]


## The scalars of a net_state (split_net) as bytes: the structure revision (u16), the flags
## (u16), PULSE_FIELDS, the drugs in the blood (a count, then [index in WoundModel.DRUGS,
## level, depot] each) and, with `timers`, the countdowns running (a count, then [index in
## WoundModel.TIMERS, tenths of a second] each). About 30 to 40 bytes.
static func _encode_pulse(scalars: Dictionary, rev: int, timers: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u16(0, rev)
	out.encode_u16(2, clampi(int(scalars.get("f", 0)), 0, 65535))
	for field: Array in PULSE_FIELDS:
		var value: Variant = scalars.get(field[0], 0.0)
		if int(field[1]) >= 0:
			var list: Array = value if value is Array else []
			value = list[field[1]] if list.size() > int(field[1]) else 0.0
		_put(out, float(value) / float(field[2]), int(field[3]))
	var drugs: Dictionary = scalars.get("g", {})
	out.append(drugs.size())
	for id: String in drugs:
		out.append(WoundModel.DRUGS.keys().find(StringName(id)))
		_put(out, float(drugs[id][0]) / 0.01, 2)
		_put(out, float(drugs[id][1]) / 0.01, 2)
	if timers:
		var running: Dictionary = scalars.get("t", {})
		out.append(running.size())
		for key: String in running:
			out.append(WoundModel.TIMERS.find(key))
			_put(out, float(running[key]) / 0.1, 2)
	return out


static func _put(out: PackedByteArray, steps: float, size: int) -> void:
	var at := out.size()
	out.resize(at + size)
	if size == 1:
		out.encode_u8(at, clampi(roundi(steps), 0, 255))
	else:
		out.encode_u16(at, clampi(roundi(steps), 0, 65535))


## A pulse (_encode_pulse) back as net_state's scalar keys (plus "vl", the bag's mL left).
static func decode_pulse(pulse: PackedByteArray) -> Dictionary:
	var out := {}
	if pulse.size() < 4:
		return out
	out["f"] = pulse.decode_u16(2)
	var at := 4
	for field: Array in PULSE_FIELDS:
		var size := int(field[3])
		if at + size > pulse.size():
			return out
		var value := float(pulse.decode_u8(at) if size == 1 else pulse.decode_u16(at)) * float(field[2])
		at += size
		if int(field[1]) < 0:
			out[field[0]] = value
		else:
			var list: Array = out.get(field[0], [])
			list.append(value)
			out[field[0]] = list
	out["u"][1] = int(out["u"][1])
	var drugs := {}
	var count := pulse.decode_u8(at) if at < pulse.size() else 0
	at += 1
	for i in count:
		if at + 5 > pulse.size():
			break
		var index := pulse.decode_u8(at)
		if index < WoundModel.DRUGS.size():
			drugs[String(WoundModel.DRUGS.keys()[index])] = [pulse.decode_u16(at + 1) * 0.01, pulse.decode_u16(at + 3) * 0.01]
		at += 5
	out["g"] = drugs
	var running := {}
	count = pulse.decode_u8(at) if at < pulse.size() else 0
	at += 1
	for i in count:
		if at + 3 > pulse.size():
			break
		var index := pulse.decode_u8(at)
		if index < WoundModel.TIMERS.size():
			running[WoundModel.TIMERS[index]] = pulse.decode_u16(at + 1) * 0.1
		at += 3
	out["t"] = running
	return out


## Peer: a structure or a pulse arrived (spawn state can land before the body is in the tree,
## so this doesn't ask whether it's the host: only replication sets these outside _send);
## net_state is rebuilt from both. A pulse built on an
## older structure than the one held is stale and dropped. (Both come on one reliable sync,
## the structure first, so that shouldn't happen.)
func _receive(pulse: bool) -> void:
	if pulse:
		if net_pulse.size() < 4:
			return
		var behind := (_struct_rev - net_pulse.decode_u16(0) + 65536) % 65536
		if not net_vitals.is_empty() and behind > 0 and behind < 32768:
			return
		_timers_fresh = true
	else:
		_struct_rev = int(net_vitals.get("r", 0))
	net_state = merge_net(net_vitals, net_pulse)


## Emits `changed` each time the arrest countdown passes a whole second, so labels that
## redraw on `changed` (condition_text) keep counting between net_state updates.
func _signal_countdown() -> void:
	var left := seconds_to_death()
	var second := ceili(left) if left >= 0.0 else -1
	if second != _shown_second:
		_shown_second = second
		changed.emit()


## The model to read: the host's own, or on a client the copy rebuilt from net_state. A
## structure that came without a new pulse keeps the countdowns the client has been running
## down (the held pulse's are as old as that pulse).
func _m() -> WoundModel:
	if _net_dirty and not _is_host():
		_net_dirty = false
		var keep := {}
		if not _timers_fresh:
			for key: String in WoundModel.TIMERS:
				keep[key] = _model.get(key)
		_timers_fresh = false
		_model.apply_net(net_state)
		for key: String in keep:
			_model.set(key, keep[key])
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
