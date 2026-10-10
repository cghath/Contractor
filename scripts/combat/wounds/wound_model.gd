class_name WoundModel
extends RefCounted
## The ACE3/KAT-style wound model behind Vitals (design doc, "Damage and medical"): 6 L of
## blood, wounds per body part that bleed at a rate scaled by the heart's output, pain
## from 0 to 1, fractures, chest wounds, concussion and impact. Blood loss, pain and
## breathing decide when a soldier slows, goes unconscious, arrests or dies.
##
## The host owns the real state and steps it (advance). Every other peer holds a copy
## rebuilt from to_net()/apply_net(), so every query works everywhere. Pure data: no nodes,
## no signals (Vitals turns state changes into its signals). Values the design doc marks as
## proposed are constants here, for Captain's playtests.

const BLOOD_L := 6.0
## Shares of blood volume lost (design doc).
const UNCONSCIOUS_LOST := 0.40
const ARREST_LOST := 0.50
const EFFECTS_FROM_LOST := 0.15   # blood-loss effects start here and reach full strength at 40%
const NO_SPRINT_LOST := 0.30
## Cardiac arrest: the unit dies when this window runs out with no heart rate.
const ARREST_WINDOW_S := 600.0

## Blood-loss effects at full strength (s = 1 at 40% lost; linear from 15%). These give the
## design doc's table: +60% sway, 64% stamina recovery and 88% speed at 30% lost.
const BLOOD_SWAY := 1.0
const BLOOD_STAMINA := 0.6
const BLOOD_SPEED := 0.2

## Bleed rates in L/min at full blood for a fully hit wound (design doc). Vessel rates are
## in BodyMap.VESSELS.
const MUSCLE_RATE := 0.25
const GRAZE_RATE := 0.03
const FEMUR_RATE := 0.05    # broken femur, internal, until splinted
const CHEST_RATE := 0.15    # proposed: blood into the chest cavity from a lung or chest wall
const HEART_RATE := 2.0     # proposed
## Muscle wound size by round class (proposed): fragments make small wounds.
const MUSCLE_CLASS_MULT := {&"pistol": 0.7, &"intermediate": 1.0, &"full_power": 1.2, &"fragment": 0.4}
## Fracture chance when a bone is hit (design doc).
const FRACTURE_CHANCE := {&"pistol": 0.25, &"intermediate": 0.70, &"full_power": 0.95, &"fragment": 0.20}

## Pain added per hit, as [min, max] (design doc: arterial or rifle 0.6-0.9, graze 0.1-0.2;
## pistol and fragment proposed).
const PAIN_SEVERE := Vector2(0.6, 0.9)
const PAIN_PISTOL := Vector2(0.3, 0.5)
const PAIN_FRAGMENT := Vector2(0.1, 0.25)
const PAIN_GRAZE := Vector2(0.1, 0.2)
## Untreated fractures keep pain at least this high (a broken leg is heavy pain); a fracture
## adds nothing on top of the hit's own pain, so a limb hit alone stays under the knockout
## threshold at full blood. A cracked rib keeps its floor until morphine; its stamina penalty
## lasts until a respawn.
const PAIN_FLOOR_LEG := 0.35
const PAIN_FLOOR_ARM := 0.2
const PAIN_FLOOR_RIB := 0.15
## Pain fades over about 15 minutes, impact over about 5.
const PAIN_FADE_PER_S := 1.0 / 900.0
const IMPACT_FADE_PER_S := 1.0 / 300.0
## Knockout: pain at or over the threshold, 0.9 at full blood falling linearly to 0.6 at
## 30% lost; at 40% lost you're out regardless.
const KNOCKOUT_PAIN_FULL := 0.9
const KNOCKOUT_PAIN_LOW := 0.6
const KNOCKOUT_PAIN_LOW_AT := 0.30
## Once stable, an unconscious casualty rolls to wake every 15 s at 15%.
const WAKE_ROLL_S := 15.0
const WAKE_CHANCE := 0.15
## Stable means not in arrest, under 40% lost and bleeding less than this (L/min).
const STABLE_BLEED_L_MIN := 0.05

## Heart hit: cardiac arrest within seconds. Chest: without a seal, a 50% chance of tension
## pneumothorax 60-120 s later, then cardiac arrest about 90 s after.
const HEART_ARREST_S := Vector2(2.0, 6.0)
const TENSION_CHANCE := 0.5
const TENSION_DELAY_S := Vector2(60.0, 120.0)
const TENSION_ARREST_S := 90.0

## Extra sway (added to 1.0) from pain at 1.0, a broken arm, concussion and a stagger.
const PAIN_SWAY := 0.6
const BROKEN_ARM_SWAY := 1.0
const CONCUSSION_SWAY := 0.8
const STAGGER_SWAY := 1.0
const BROKEN_LEG_SPEED := 0.6     # walk only
const STAGGER_SPEED := 0.5
const BROKEN_ARM_RELOAD := 1.6
const CONCUSSION_TURN := 0.6
const RIB_STAMINA := 0.7
## Share of injury() that blood loss makes up (see injury).
const INJURY_BLOOD_WEIGHT := 0.3
## Untreated bleeding (L/min) that counts as the worst for injury().
const INJURY_FULL_BLEED := 0.5

## --- Treatment (design doc "The kit", "Tourniquet", "Fractures", "Chest") ---
## Kit item ids (data/items.json) the model knows how to apply.
const TOURNIQUET := &"tourniquet"
const PRESSURE_BANDAGE := &"pressure_bandage"
const HEMOSTATIC_GAUZE := &"hemostatic_gauze"
const CHEST_SEAL := &"chest_seal"
const SPLINT := &"splint"
const MORPHINE := &"morphine"
const NPA := &"npa"
## A tourniquet on a limb segment stops the bleeding on it and on every segment below it.
const LIMB_BELOW := {
	&"thigh_l": [&"thigh_l", &"shin_l"], &"shin_l": [&"shin_l"],
	&"thigh_r": [&"thigh_r", &"shin_r"], &"shin_r": [&"shin_r"],
	&"upper_arm_l": [&"upper_arm_l", &"forearm_l"], &"forearm_l": [&"forearm_l"],
	&"upper_arm_r": [&"upper_arm_r", &"forearm_r"], &"forearm_r": [&"forearm_r"],
}
const LEG_PARTS: Array[StringName] = [&"thigh_l", &"thigh_r", &"shin_l", &"shin_r"]
## A rushed tourniquet (under 2 s, or under fire) lets this share through (cuts bleeding by
## only 70%, design doc); a second tourniquet beside it fixes that.
const RUSHED_TOURNIQUET_LEAK := 0.3
const MAX_TOURNIQUETS := 2
## Pain a tourniquet adds while it's on, per limb segment that has one (proposed).
const TOURNIQUET_PAIN := 0.1
## A leg tourniquet forces a limp: no faster than this share of a jog, and no sprint
## (proposed: the same walking pace as a broken leg).
const TOURNIQUET_LEG_SPEED := 0.6
## A splint eases a fracture's pain floor to these and leaves a splinted arm this much extra
## sway (proposed). Walking and jogging come back; sprinting doesn't (can_sprint).
const PAIN_FLOOR_SPLINTED_LEG := 0.15
const PAIN_FLOOR_SPLINTED_ARM := 0.1
const SPLINTED_ARM_SWAY := 0.3
## Morphine takes this much off pain over MORPHINE_S (design doc). A second dose within
## OVERDOSE_WINDOW_S risks an overdose (proposed: this chance of being knocked out for this
## long; wave 3 adds heart-rate effects).
const MORPHINE_RELIEF := 0.5
const MORPHINE_S := 30.0
const OVERDOSE_WINDOW_S := 600.0
const OVERDOSE_CHANCE := 0.4
const OVERDOSE_KO_S := Vector2(120.0, 300.0)
## care_tasks() asks for morphine from this much pain it can take off (proposed), or for a
## cracked rib (morphine is its only fix).
const MORPHINE_FROM_PAIN := 0.4
## Airway (proposed): an unconscious casualty without an NPA obstructs with this chance per
## minute, then goes into cardiac arrest this long after unless an NPA goes in.
const AIRWAY_BLOCK_PER_MIN := 0.1
const AIRWAY_ARREST_S := 180.0
## Bleeding the field kit can control. Internal (torso) bleeding waits for wave 3's surgery
## kit, so care_tasks() never asks for an item for it.
const FIXABLE_BLEEDS: Array[String] = ["arterial", "junctional", "venous", "muscle", "graze"]
const BANDAGED_KINDS: Array[String] = ["venous", "muscle", "graze"]
## The stopgap revive needs the bleeding controlled: less than this (L/min) the kit could
## still stop.
const REVIVE_MAX_BLEED := 0.05
## Countdowns that clients run down between updates (to_net "t").
const TIMERS: Array[String] = ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left",
	"treating_left", "morphine_left", "overdose_window_left"]

## Impact (shock) from rounds armor stopped (design doc table).
const PLATE_IMPACT_PAIN := {&"pistol": 0.05, &"intermediate": 0.15, &"full_power": 0.3}
const HELMET_IMPACT_PAIN := {&"pistol": 0.15, &"intermediate": 0.3, &"full_power": 0.45}
const CONCUSSION_CHANCE := {&"pistol": 0.1, &"intermediate": 0.4, &"full_power": 0.8}
const STAGGER_S := 0.8            # intermediate plate stop: brief stagger
const WINDED_S := 4.0             # full-power plate stop: stamina emptied for a few seconds
## Concussion: possible knockout for 5-20 s, then 60 s of blur, sway and slow turning; a
## second one in the same fight lasts twice as long.
const CONCUSSION_KO_CHANCE := 0.5
const CONCUSSION_KO_S := Vector2(5.0, 20.0)
const CONCUSSION_S := 60.0
const SAME_FIGHT_S := 600.0
## Cracked rib from a plate stop, only within these ranges (design doc), at these odds (proposed).
const RIB_RANGE_M := {&"pistol": 30.0, &"intermediate": 100.0, &"full_power": 200.0}
const RIB_CRACK_CHANCE := {&"pistol": 0.3, &"intermediate": 0.5, &"full_power": 0.7}
const RIB_PAIN := 0.1
## A helmet stop is fatal only where it would be in real life: a full-power rifle round
## arriving with at least this energy (or, energy unknown, within this range), at these odds.
const HELMET_FATAL_ENERGY_J := 2400.0
const HELMET_FATAL_RANGE_M := 200.0
const HELMET_FATAL_CHANCE := 0.35

## Share of blood, 0 to 1.
var blood := 1.0
## Pain from wounds and trauma (fades over ~15 min) and from impact (fades over ~5 min).
var pain_wounds := 0.0
var impact := 0.0
## One Dictionary per wound: part, kind, rate (L/min at full blood), treated, name (vessel
## or bone), packed (an arterial or junctional bleed packed with gauze), tension (a chest
## wound's tension pneumothorax has started), and for chest wounds tension_in / arrest_in
## (seconds, -1 when not pending; host only).
var wounds: Array[Dictionary] = []
var unconscious := false
var arrest := false
var dead := false
var arrest_left := 0.0
var concussion_left := 0.0
var knockout_left := 0.0
var winded_left := 0.0
var stagger_left := 0.0
var rng := RandomNumberGenerator.new()
## Tourniquets on limb segments: part -> {"count": n, "rushed": how many of them were rushed}.
var tourniquets: Dictionary = {}
## An NPA is in; an unconscious casualty's airway is obstructed.
var npa := false
var airway_blocked := false
## Someone is applying a treatment to this body (seconds left).
var treating_left := 0.0
## Morphine relief still to come (seconds), and how long a new dose still risks an overdose.
var morphine_left := 0.0
var overdose_window_left := 0.0
## Dice for the treatment rules (airway, overdose), apart from rng so the wound dice repeat.
var care_rng := RandomNumberGenerator.new()

var _time := 0.0
var _last_concussion := -INF
var _heart_arrest_in := -1.0
var _wake_roll_in := WAKE_ROLL_S
var _knockout_only := false     # out only because of a knockout (concussion, overdose)
var _airway_arrest_in := -1.0   # obstructed airway: seconds to cardiac arrest


# --- Queries --------------------------------------------------------------------------

func lost() -> float:
	return 1.0 - blood


## Blood-loss effect strength: 0 up to 15% lost, 1 at 40%.
func shock() -> float:
	return clampf((lost() - EFFECTS_FROM_LOST) / (UNCONSCIOUS_LOST - EFFECTS_FROM_LOST), 0.0, 1.0)


## Wound and impact pain, at least the floor that fractures and an untreated cracked rib
## keep, plus what tourniquets add while they're on.
func pain() -> float:
	var floor_pain := 0.0
	for w in wounds:
		if w.kind == "fracture":
			var leg: bool = w.name in BodyMap.LEG_BONES
			if w.treated:
				floor_pain = maxf(floor_pain, PAIN_FLOOR_SPLINTED_LEG if leg else PAIN_FLOOR_SPLINTED_ARM)
			else:
				floor_pain = maxf(floor_pain, PAIN_FLOOR_LEG if leg else PAIN_FLOOR_ARM)
		elif w.kind == "rib" and not w.treated:
			floor_pain = maxf(floor_pain, PAIN_FLOOR_RIB)
	return clampf(maxf(pain_wounds + impact, floor_pain) + TOURNIQUET_PAIN * tourniquets.size(), 0.0, 1.0)


func knockout_threshold() -> float:
	return lerpf(KNOCKOUT_PAIN_FULL, KNOCKOUT_PAIN_LOW, clampf(lost() / KNOCKOUT_PAIN_LOW_AT, 0.0, 1.0))


## Untreated and with a bleed rate (tourniquets aside: see rate_now).
static func is_bleeding(w: Dictionary) -> bool:
	return float(w.rate) > 0.0 and not w.treated


## Share of bleeding that gets past the tourniquets above or on `part`: 1 with none, 0 under
## a good one (or two rushed ones), RUSHED_TOURNIQUET_LEAK under a single rushed one.
func tourniquet_factor(part: StringName, skip_segment: StringName = &"") -> float:
	var factor := 1.0
	for segment: StringName in tourniquets:
		if segment != skip_segment and part in LIMB_BELOW.get(segment, []):
			factor = minf(factor, _segment_factor(segment))
	return factor


## L/min at full blood this wound bleeds now: 0 once treated or under a good tourniquet.
func rate_now(w: Dictionary) -> float:
	return float(w.rate) * tourniquet_factor(w.part) if is_bleeding(w) else 0.0


## Bleeding in L/min at full blood (the wounds' own rates, less what tourniquets hold back).
func wound_bleed_rate() -> float:
	var rate := 0.0
	for w in wounds:
		rate += rate_now(w)
	return rate


## Bleeding the field kit could still stop (L/min at full blood).
func fixable_bleed_rate() -> float:
	var rate := 0.0
	for w in wounds:
		if String(w.kind) in FIXABLE_BLEEDS:
			rate += rate_now(w)
	return rate


## Bleeding is under control for the stopgap revive: what the kit could still stop is under
## REVIVE_MAX_BLEED. (Internal bleeding can't be controlled in the field.)
func bleeding_controlled() -> bool:
	return fixable_bleed_rate() < REVIVE_MAX_BLEED


func has_leg_tourniquet() -> bool:
	return LEG_PARTS.any(func(p: StringName) -> bool: return tourniquets.has(p))


## The heart's output, 0 to 1: proportional to the blood left, nothing in arrest.
func cardiac_output() -> float:
	return 0.0 if arrest or dead else blood


## Blood actually leaving the body now, in L/min.
func bleed_rate() -> float:
	return wound_bleed_rate() * cardiac_output()


func has_fracture(bones: Array, untreated_only: bool) -> bool:
	for w in wounds:
		if w.kind == "fracture" and w.name in bones and not (untreated_only and w.treated):
			return true
	return false


func has_kind(kind: String) -> bool:
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == kind)


## Someone is applying a treatment to this body.
func is_healing() -> bool:
	return treating_left > 0.0


## Not in arrest, under 40% lost, barely bleeding and breathing (an obstructed airway isn't).
func is_stable() -> bool:
	return not arrest and not dead and lost() < UNCONSCIOUS_LOST and bleed_rate() < STABLE_BLEED_L_MIN and not airway_blocked


func sway_mult() -> float:
	var sway := 1.0 + BLOOD_SWAY * shock() + PAIN_SWAY * pain()
	if has_fracture(BodyMap.ARM_BONES, true):
		sway += BROKEN_ARM_SWAY
	elif has_fracture(BodyMap.ARM_BONES, false):
		sway += SPLINTED_ARM_SWAY
	if concussion_left > 0.0:
		sway += CONCUSSION_SWAY
	if stagger_left > 0.0:
		sway += STAGGER_SWAY
	return sway


func speed_mult() -> float:
	var speed := 1.0 - BLOOD_SPEED * shock()
	var leg := 1.0  # a broken leg or a leg tourniquet: walk only (they don't stack)
	if has_fracture(BodyMap.LEG_BONES, true):
		leg = minf(leg, BROKEN_LEG_SPEED)
	if has_leg_tourniquet():
		leg = minf(leg, TOURNIQUET_LEG_SPEED)
	speed *= leg
	if stagger_left > 0.0:
		speed *= STAGGER_SPEED
	return speed


func stamina_mult() -> float:
	if winded_left > 0.0:
		return 0.0
	var stamina := 1.0 - BLOOD_STAMINA * shock()
	if has_kind("rib"):
		stamina *= RIB_STAMINA
	return stamina


## A splinted leg still can't sprint until the mission ends (design doc), nor a leg with a
## tourniquet on.
func can_sprint() -> bool:
	return not unconscious and not dead and lost() < NO_SPRINT_LOST and winded_left <= 0.0 \
		and not has_fracture(BodyMap.LEG_BONES, false) and not has_leg_tourniquet()


func reload_mult() -> float:
	return BROKEN_ARM_RELOAD if has_fracture(BodyMap.ARM_BONES, true) else 1.0


func turn_mult() -> float:
	return CONCUSSION_TURN if concussion_left > 0.0 else 1.0


## Pain morphine can take off: wound and impact pain, not the floors that fractures keep
## (or what tourniquets add).
func reducible_pain() -> float:
	return clampf(pain_wounds + impact, 0.0, 1.0)


## What the kit can still fix, 0 to 1: the worse of bleeding it could stop (an unsealed
## chest wound counts as some) and pain morphine could take off (none while a dose would
## risk an overdose).
func treatable() -> float:
	var bleed := fixable_bleed_rate()
	for w in wounds:
		if w.kind == "chest" and not w.treated:
			bleed += CHEST_RATE
	var pain_term := reducible_pain() if overdose_window_left <= 0.0 else 0.0
	return maxf(pain_term, clampf(bleed / INJURY_FULL_BLEED, 0.0, 1.0))


## 0 (fine) to 1: blood loss counts for up to INJURY_BLOOD_WEIGHT, what the kit can still fix
## (treatable) for the rest. Splinted fractures, lost blood and internal bleeding stay out of
## the kit term: the field kit fixes none of them, and AI that counted them would use up
## everything it carries. Blood loss alone stays under the 0.45 at which AI treats itself.
func injury() -> float:
	var blood_term := clampf(lost() / UNCONSCIOUS_LOST, 0.0, 1.0)
	return clampf(INJURY_BLOOD_WEIGHT * blood_term + (1.0 - INJURY_BLOOD_WEIGHT) * treatable(), 0.0, 1.0)


# --- Treatment ------------------------------------------------------------------------

## What still needs doing, most urgent first, in the casualty-care order: massive bleeding
## (a tourniquet per limb segment, gauze for junctional bleeds), airway (an NPA for an
## unconscious casualty), chest (a seal per open chest wound), other bleeding (bandages),
## fractures (splints), pain (morphine, also for a cracked rib). One {"part", "kind", "item"}
## per task. Only items that would help: wounds already handled (treated, under a good
## tourniquet) are skipped, internal bleeding and a tension pneumothorax under a seal wait
## for wave 3, and no second morphine dose is asked for while it would risk an overdose. In
## cardiac arrest neither an NPA nor morphine does anything until the heart restarts.
func care_tasks() -> Array[Dictionary]:
	var tasks: Array[Dictionary] = []
	var by_rate := wounds.duplicate()
	by_rate.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rate) > float(b.rate))
	var tourniquet_parts := {}
	for w: Dictionary in by_rate:
		if rate_now(w) <= 0.0:
			continue
		if w.kind == "arterial" and LIMB_BELOW.has(w.part):
			if not tourniquet_parts.has(w.part):
				tourniquet_parts[w.part] = true
				tasks.append(_task(w.part, "arterial", TOURNIQUET))
		elif w.kind == "junctional" or w.kind == "arterial":
			tasks.append(_task(w.part, w.kind, HEMOSTATIC_GAUZE))
	if unconscious and not arrest and not npa:
		tasks.append(_task(&"head", "airway", NPA))
	for w: Dictionary in by_rate:
		if w.kind == "chest" and not w.treated:
			tasks.append(_task(w.part, "chest", CHEST_SEAL))
	for w: Dictionary in by_rate:
		if String(w.kind) in BANDAGED_KINDS and rate_now(w) > 0.0:
			tasks.append(_task(w.part, w.kind, PRESSURE_BANDAGE))
	for w: Dictionary in by_rate:
		if w.kind == "fracture" and not w.treated:
			tasks.append(_task(w.part, "fracture", SPLINT))
	if not arrest and overdose_window_left <= 0.0 and (reducible_pain() >= MORPHINE_FROM_PAIN or _untreated_rib()):
		tasks.append(_task(&"torso", "pain", MORPHINE))
	return tasks


## Why one `item` on `part` wouldn't help right now, or "" if it would.
func treatment_problem(item: StringName, part: StringName) -> String:
	if dead:
		return "Too late"
	match item:
		TOURNIQUET:
			if not LIMB_BELOW.has(part):
				return "Tourniquets go on arms and legs"
			if int(tourniquets.get(part, {}).get("count", 0)) >= MAX_TOURNIQUETS:
				return "Already two tourniquets there"
			for w in wounds:
				if w.part in LIMB_BELOW[part] and rate_now(w) > 0.0:
					return ""
			return "Nothing bleeding there"
		MORPHINE:
			return "" if reducible_pain() > 0.0 or _untreated_rib() else "No pain morphine would ease"
		NPA:
			if not unconscious:
				return "Only for an unconscious casualty"
			return "Already has an NPA" if npa else ""
		HEMOSTATIC_GAUZE:
			if not _target_wound(item, part).is_empty():
				return ""
			for w in wounds:
				if w.part == part and w.kind == "arterial" and is_bleeding(w):
					return "Put a tourniquet on first"
			return "Nothing to pack there"
		PRESSURE_BANDAGE, CHEST_SEAL, SPLINT:
			if not _target_wound(item, part).is_empty():
				return ""
			return {PRESSURE_BANDAGE: "Nothing a bandage fixes there", CHEST_SEAL: "No open chest wound there",
				SPLINT: "No fracture there"}[item]
	return "That doesn't treat anything"


## Host only. One use of `item` on `part` (see treatment_problem); `rushed` is for a
## tourniquet placed in a hurry or under fire. Returns whether it did anything.
func apply_item(item: StringName, part: StringName, rushed := false) -> bool:
	if treatment_problem(item, part) != "":
		return false
	match item:
		TOURNIQUET:
			var t: Dictionary = tourniquets.get(part, {"count": 0, "rushed": 0})
			tourniquets[part] = {"count": int(t.count) + 1, "rushed": int(t.rushed) + (1 if rushed else 0)}
		MORPHINE:
			if overdose_window_left > 0.0 and care_rng.randf() < OVERDOSE_CHANCE:
				knockout_left = maxf(knockout_left, care_rng.randf_range(OVERDOSE_KO_S.x, OVERDOSE_KO_S.y))
			morphine_left += MORPHINE_S
			overdose_window_left = OVERDOSE_WINDOW_S
			for w in wounds:
				if w.kind == "rib":
					w.treated = true
		NPA:
			npa = true
			airway_blocked = false
			_airway_arrest_in = -1.0
		_:
			var w := _target_wound(item, part)
			w.treated = true
			if item == HEMOSTATIC_GAUZE:
				w.packed = true
			elif item == CHEST_SEAL:
				w.tension_in = -1.0  # sealed in time: no tension pneumothorax starts (one under way runs on)
	update_state(0.0)
	return true


## Why the tourniquets on `part` can't come off yet, or "" if they can: every arterial bleed
## under them has to be packed first (or held by another good tourniquet).
func removal_problem(part: StringName) -> String:
	if not tourniquets.has(part):
		return "No tourniquet there"
	for w in wounds:
		if w.kind == "arterial" and is_bleeding(w) and w.part in LIMB_BELOW[part] and tourniquet_factor(w.part, part) > 0.0:
			return "Pack the wound first"
	return ""


## Host only. Takes the tourniquets off `part`; returns how many came off (0 if they can't).
func remove_tourniquets(part: StringName) -> int:
	if removal_problem(part) != "":
		return 0
	var count := int(tourniquets[part].count)
	tourniquets.erase(part)
	update_state(0.0)
	return count


func _task(part: StringName, kind: String, item: StringName) -> Dictionary:
	return {"part": part, "kind": kind, "item": item}


## The wound one bandage, gauze, seal or splint on `part` would treat (the worst), or {}.
## Gauze packs a junctional bleed, or an arterial one under a tourniquet (so it can come off).
func _target_wound(item: StringName, part: StringName) -> Dictionary:
	var best := {}
	for w in wounds:
		if w.part != part or w.treated:
			continue
		var fits := false
		match item:
			PRESSURE_BANDAGE:
				fits = String(w.kind) in BANDAGED_KINDS and is_bleeding(w)
			HEMOSTATIC_GAUZE:
				fits = is_bleeding(w) and (w.kind == "junctional" or (w.kind == "arterial" \
					and (not LIMB_BELOW.has(part) or tourniquet_factor(part) < 1.0)))
			CHEST_SEAL:
				fits = w.kind == "chest"
			SPLINT:
				fits = w.kind == "fracture"
		if fits and (best.is_empty() or rate_now(w) > rate_now(best) or (rate_now(w) == rate_now(best) and float(w.rate) > float(best.rate))):
			best = w
	return best


func _untreated_rib() -> bool:
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == "rib" and not w.treated)


func _segment_factor(segment: StringName) -> float:
	var t: Dictionary = tourniquets[segment]
	return 0.0 if int(t.count) >= MAX_TOURNIQUETS or int(t.count) > int(t.rushed) else RUSHED_TOURNIQUET_LEAK


# --- Host-side changes ----------------------------------------------------------------

## A round or fragment reached `part` along `channel` (BodyMap.trace). Returns the new wounds.
func add_hit(part: StringName, channel: Dictionary, round_class: StringName) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if dead:
		return added
	var rifle := round_class == &"intermediate" or round_class == &"full_power"
	if part == &"head" and round_class != &"fragment":
		kill()  # an unprotected head hit past the helmet is fatal
		return added
	if &"brain" in channel.organs:
		kill()
		return added
	var hit_pain := 0.0
	if channel.graze:
		added.append(_add_wound(part, "graze", GRAZE_RATE))
		hit_pain = rng.randf_range(PAIN_GRAZE.x, PAIN_GRAZE.y)
	else:
		var pain_range := PAIN_SEVERE if rifle else (PAIN_PISTOL if round_class == &"pistol" else PAIN_FRAGMENT)
		for v: Dictionary in channel.vessels:
			added.append(_add_wound(part, v.kind, float(v.rate) * float(v.share), v.name))
			if v.kind != BodyMap.VENOUS and float(v.share) >= 0.5:
				pain_range = PAIN_SEVERE  # an arterial wound hurts like a rifle wound
		if channel.vessels.is_empty():
			added.append(_add_wound(part, "muscle", MUSCLE_RATE * float(MUSCLE_CLASS_MULT.get(round_class, 1.0))))
		hit_pain = rng.randf_range(pain_range.x, pain_range.y)
		if &"heart" in channel.organs:
			added.append(_add_wound(part, "heart", HEART_RATE, &"heart"))
			if _heart_arrest_in < 0.0 and not arrest:
				_heart_arrest_in = rng.randf_range(HEART_ARREST_S.x, HEART_ARREST_S.y)
		var lung: bool = &"lung_l" in channel.organs or &"lung_r" in channel.organs
		# A bullet through the chest wall opens the cavity; a fragment has to reach a lung.
		if lung or (part == &"chest" and round_class != &"fragment" and float(channel.depth) >= BodyMap.CHEST_WALL_M):
			var chest := _add_wound(&"chest", "chest", CHEST_RATE, &"lung_l" if &"lung_l" in channel.organs else &"lung_r")
			if rng.randf() < TENSION_CHANCE:
				chest.tension_in = rng.randf_range(TENSION_DELAY_S.x, TENSION_DELAY_S.y)
			added.append(chest)
		for bone: StringName in channel.bones:
			if has_fracture([bone], false) or rng.randf() >= float(FRACTURE_CHANCE.get(round_class, 0.5)):
				continue
			added.append(_add_wound(part, "fracture", FEMUR_RATE if bone.begins_with("femur") else 0.0, bone))
	pain_wounds = minf(pain_wounds + hit_pain, 1.0)
	update_state(0.0)
	return added


## A round armor stopped still lands on `part` (design doc impact table).
func add_impact(part: StringName, round_class: StringName, distance: float, energy_j: float) -> void:
	if dead:
		return
	if part == &"head" or part == &"face":
		impact += float(HELMET_IMPACT_PAIN.get(round_class, 0.0))
		if round_class == &"full_power":
			var lethal := energy_j >= HELMET_FATAL_ENERGY_J if energy_j >= 0.0 else distance <= HELMET_FATAL_RANGE_M
			if lethal and rng.randf() < HELMET_FATAL_CHANCE:
				kill()
				return
		if rng.randf() < float(CONCUSSION_CHANCE.get(round_class, 0.0)):
			_concuss()
	else:
		impact += float(PLATE_IMPACT_PAIN.get(round_class, 0.0))
		if round_class == &"intermediate":
			stagger_left = maxf(stagger_left, STAGGER_S)
		elif round_class == &"full_power":
			stagger_left = maxf(stagger_left, STAGGER_S)
			winded_left = maxf(winded_left, WINDED_S)
		if distance <= float(RIB_RANGE_M.get(round_class, -1.0)) and rng.randf() < float(RIB_CRACK_CHANCE.get(round_class, 0.0)):
			if not has_kind("rib"):
				_add_wound(&"chest", "rib", 0.0, &"rib")
			impact += RIB_PAIN
	impact = minf(impact, 1.0)
	update_state(0.0)


## Generic trauma (the legacy damage call): pain and an immediate share of blood lost.
func add_trauma(pain_amount: float, blood_share: float) -> void:
	if dead:
		return
	pain_wounds = minf(pain_wounds + pain_amount, 1.0)
	blood = maxf(blood - blood_share, 0.0)
	update_state(0.0)


func kill() -> void:
	dead = true
	arrest = false
	unconscious = false
	treating_left = 0.0


## Stopgap revive (trauma kit, until IV in wave 3; callers check bleeding_controlled first):
## tops blood up to `min_blood`, restarts the heart, caps pain at `pain_cap` and wakes the
## casualty. It stops no bleeding: that's the kit's job.
func revive(min_blood: float, pain_cap: float) -> void:
	if dead:
		return
	blood = maxf(blood, min_blood)
	arrest = false
	arrest_left = 0.0
	_heart_arrest_in = -1.0
	knockout_left = 0.0
	airway_blocked = false
	_airway_arrest_in = -1.0
	var total := pain_wounds + impact
	if total > pain_cap:
		pain_wounds *= pain_cap / total
		impact *= pain_cap / total
	unconscious = false
	_knockout_only = false


func reset() -> void:
	blood = 1.0
	pain_wounds = 0.0
	impact = 0.0
	wounds.clear()
	unconscious = false
	arrest = false
	dead = false
	arrest_left = 0.0
	concussion_left = 0.0
	knockout_left = 0.0
	winded_left = 0.0
	stagger_left = 0.0
	_last_concussion = -INF
	_heart_arrest_in = -1.0
	_wake_roll_in = WAKE_ROLL_S
	_knockout_only = false
	tourniquets.clear()
	npa = false
	airway_blocked = false
	_airway_arrest_in = -1.0
	treating_left = 0.0
	morphine_left = 0.0
	overdose_window_left = 0.0


## Host only: steps the simulation by `dt` seconds.
func advance(dt: float) -> void:
	if dead:
		return
	_time += dt
	concussion_left = maxf(concussion_left - dt, 0.0)
	knockout_left = maxf(knockout_left - dt, 0.0)
	winded_left = maxf(winded_left - dt, 0.0)
	stagger_left = maxf(stagger_left - dt, 0.0)
	treating_left = maxf(treating_left - dt, 0.0)
	overdose_window_left = maxf(overdose_window_left - dt, 0.0)
	pain_wounds = maxf(pain_wounds - PAIN_FADE_PER_S * dt, 0.0)
	impact = maxf(impact - IMPACT_FADE_PER_S * dt, 0.0)
	if morphine_left > 0.0:
		var step := minf(dt, morphine_left)
		morphine_left -= step
		var relief := MORPHINE_RELIEF / MORPHINE_S * step
		var from_wounds := minf(relief, pain_wounds)
		pain_wounds -= from_wounds
		impact = maxf(impact - (relief - from_wounds), 0.0)
	# Bleeding, scaled by what the heart still pushes out.
	blood = maxf(blood - bleed_rate() / 60.0 * dt / BLOOD_L, 0.0)
	if _heart_arrest_in >= 0.0:
		_heart_arrest_in -= dt
		if _heart_arrest_in <= 0.0:
			_heart_arrest_in = -1.0
			_start_arrest()
	for w in wounds:
		if w.kind != "chest":
			continue
		if not w.treated and float(w.tension_in) >= 0.0:  # a seal stops this countdown...
			w.tension_in = float(w.tension_in) - dt
			if w.tension_in <= 0.0:
				w.tension_in = -1.0
				w.tension = true
				w.arrest_in = TENSION_ARREST_S  # tension pneumothorax
		elif float(w.arrest_in) >= 0.0:  # ...but not this one (the needle is wave 3)
			w.arrest_in = float(w.arrest_in) - dt
			if w.arrest_in <= 0.0:
				w.arrest_in = -1.0
				_start_arrest()
	if arrest:
		arrest_left -= dt
		if arrest_left <= 0.0:
			kill()  # no heart rate when the window ran out
			return
	update_state(dt)
	_update_airway(dt)


## Re-evaluates consciousness and arrest from the current state; `dt` drives wake rolls.
func update_state(dt: float) -> void:
	if dead:
		return
	if not arrest and lost() >= ARREST_LOST:
		_start_arrest()
	var other_cause := arrest or lost() >= UNCONSCIOUS_LOST or pain() >= knockout_threshold()
	var out := other_cause or knockout_left > 0.0
	if out:
		if not unconscious:
			unconscious = true
			_knockout_only = not other_cause
		elif other_cause:
			_knockout_only = false
		_wake_roll_in = WAKE_ROLL_S
		return
	if not unconscious:
		return
	if _knockout_only:
		_wake()  # the knockout (concussion, overdose) passed
		return
	if not is_stable():
		_wake_roll_in = WAKE_ROLL_S
		return
	_wake_roll_in -= dt
	if _wake_roll_in <= 0.0:
		_wake_roll_in = WAKE_ROLL_S
		if rng.randf() < WAKE_CHANCE:
			_wake()


# --- Replication ----------------------------------------------------------------------

## Compact state for Vitals.net_state. "t" holds countdowns, which clients run down locally.
## Wounds are [part, kind, rate, treated, name, flags (1 packed, 2 tension)]; "q" holds the
## tourniquets as {part: [count, rushed]}.
func to_net() -> Dictionary:
	var list: Array = []
	for w in wounds:
		var wound_flags := (1 if w.get("packed", false) else 0) | (2 if w.get("tension", false) else 0)
		list.append([String(w.part), w.kind, snappedf(float(w.rate), 0.001), 1 if w.treated else 0, String(w.name), wound_flags])
	var flags := (1 if unconscious else 0) | (2 if arrest else 0) | (4 if dead else 0) | (16 if npa else 0) | (32 if airway_blocked else 0)
	var timers := {}
	for key: String in TIMERS:
		if float(get(key)) > 0.0:
			timers[key] = snappedf(float(get(key)), 0.1)
	var tq := {}
	for part: StringName in tourniquets:
		tq[String(part)] = [int(tourniquets[part].count), int(tourniquets[part].rushed)]
	return {"b": snappedf(blood, 0.001), "p": snappedf(pain_wounds, 0.01), "i": snappedf(impact, 0.01),
		"f": flags, "w": list, "q": tq, "t": timers}


## Rebuilds this copy from a peer's net_state (clients).
func apply_net(state: Dictionary) -> void:
	blood = float(state.get("b", 1.0))
	pain_wounds = float(state.get("p", 0.0))
	impact = float(state.get("i", 0.0))
	var flags := int(state.get("f", 0))
	unconscious = flags & 1 != 0
	arrest = flags & 2 != 0
	dead = flags & 4 != 0
	npa = flags & 16 != 0
	airway_blocked = flags & 32 != 0
	wounds.clear()
	for entry: Array in state.get("w", []):
		var wound_flags := int(entry[5]) if entry.size() > 5 else 0
		wounds.append({"part": StringName(entry[0]), "kind": String(entry[1]), "rate": float(entry[2]),
			"treated": int(entry[3]) != 0, "name": StringName(entry[4]), "packed": wound_flags & 1 != 0,
			"tension": wound_flags & 2 != 0, "tension_in": -1.0, "arrest_in": -1.0})
	tourniquets.clear()
	var tq: Dictionary = state.get("q", {})
	for part: String in tq:
		tourniquets[StringName(part)] = {"count": int(tq[part][0]), "rushed": int(tq[part][1])}
	var timers: Dictionary = state.get("t", {})
	for key: String in TIMERS:
		set(key, float(timers.get(key, 0.0)))


## Clients: runs the replicated countdowns down between updates.
func tick_display(dt: float) -> void:
	for key: String in TIMERS:
		set(key, maxf(float(get(key)) - dt, 0.0))


# --- Internals ------------------------------------------------------------------------

func _add_wound(part: StringName, kind: String, rate: float, name: StringName = &"") -> Dictionary:
	var w := {"part": part, "kind": kind, "rate": rate, "treated": false, "name": name,
		"packed": false, "tension": false, "tension_in": -1.0, "arrest_in": -1.0}
	wounds.append(w)
	return w


## An unconscious casualty without an NPA can obstruct; an obstructed airway stops the heart
## AIRWAY_ARREST_S later unless an NPA goes in. Waking (or a restarted heart) clears it.
func _update_airway(dt: float) -> void:
	if not unconscious:
		airway_blocked = false
		_airway_arrest_in = -1.0
		return
	if arrest or npa:
		return
	if not airway_blocked:
		if care_rng.randf() < 1.0 - pow(1.0 - AIRWAY_BLOCK_PER_MIN, dt / 60.0):
			airway_blocked = true
			_airway_arrest_in = AIRWAY_ARREST_S
		return
	_airway_arrest_in -= dt
	if _airway_arrest_in <= 0.0:
		_airway_arrest_in = -1.0
		_start_arrest()


func _wake() -> void:
	unconscious = false
	_knockout_only = false
	airway_blocked = false
	_airway_arrest_in = -1.0


func _start_arrest() -> void:
	if arrest or dead:
		return
	arrest = true
	arrest_left = ARREST_WINDOW_S
	_heart_arrest_in = -1.0
	_airway_arrest_in = -1.0


func _concuss() -> void:
	var mult := 2.0 if _time - _last_concussion < SAME_FIGHT_S else 1.0
	_last_concussion = _time
	var knockout := 0.0
	if rng.randf() < CONCUSSION_KO_CHANCE:
		knockout = rng.randf_range(CONCUSSION_KO_S.x, CONCUSSION_KO_S.y) * mult
		knockout_left = maxf(knockout_left, knockout)
	concussion_left = maxf(concussion_left, knockout + CONCUSSION_S * mult)
