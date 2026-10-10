class_name WoundModel
extends RefCounted
## The ACE3/KAT-style wound model behind Vitals (design doc, "Damage and medical"): 6 L of
## blood, wounds per body part that bleed at a rate scaled by the heart's output, pain
## from 0 to 1, fractures, chest wounds, concussion and impact. Blood loss, pain and
## breathing decide when a soldier slows, goes unconscious, arrests or dies.
##
## Consciousness follows the body (there is no revive): a casualty is out while any cause in
## unconscious_causes() holds (low SpO2, pain held at the knockout threshold for a few
## seconds, 40% of blood lost, cardiac arrest, a concussion knockout, morphine sedation, total
## trauma over its limit) and comes round on their own once every cause has stayed gone for a
## short time (WAKE_S).
## Treatment helps by removing causes: a tourniquet stops the slide, morphine eases pain, an
## NPA clears the airway so SpO2 recovers.
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
## Proposed (user's call, until IV in wave 3): with every bleed stopped (internal ones too)
## and the heart beating, the body makes back this share of blood volume per minute, so a
## patched-up casualty past 40% lost comes round in time instead of staying out for good.
const BLOOD_RECOVER_PER_MIN := 0.015

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

## Pain added per hit, as [min, max]. Captain's playtest call (overrides the design doc's
## 0.6-0.9 for a rifle or arterial wound): one rifle round through a limb hurts but doesn't
## knock a healthy soldier out, so a single severe wound stays well under the 0.9 threshold
## at full blood and only knocks out with real blood loss (about 25% lost and more) or a
## second serious wound. Graze 0.1-0.2 is the design doc's; pistol and fragment proposed.
const PAIN_SEVERE := Vector2(0.45, 0.65)
const PAIN_PISTOL := Vector2(0.25, 0.4)
const PAIN_FRAGMENT := Vector2(0.1, 0.25)
const PAIN_GRAZE := Vector2(0.1, 0.2)
## Spall from a steel plate (round class SPALL, ArmorRules.server_spall): a scratch that
## doesn't bleed, or with SPALL_LIGHT_CHANCE a light muscle wound. Never deeper: no vessels,
## organs or bones.
const SPALL := &"spall"
const SPALL_LIGHT_CHANCE := 0.2
const SPALL_LIGHT_RATE := 0.05
const PAIN_SPALL_SCRATCH := Vector2(0.02, 0.05)
const PAIN_SPALL_LIGHT := Vector2(0.08, 0.15)
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
## 30% lost; at 40% lost you're out regardless. Captain's playtest call: pain has to stay
## at or over the threshold for PAIN_KNOCKOUT_S before it knocks anyone out (no instant
## spike); dropping under it starts the count over.
const KNOCKOUT_PAIN_FULL := 0.9
const KNOCKOUT_PAIN_LOW := 0.6
const KNOCKOUT_PAIN_LOW_AT := 0.30
const PAIN_KNOCKOUT_S := 3.0
## Waking (proposed): once every cause of unconsciousness is gone, the casualty comes round
## after it has stayed gone this long, by the worst cause of this spell out (milder causes
## are quicker). No dice.
const WAKE_S := {&"knockout": 10.0, &"pain": 10.0, &"morphine": 15.0, &"spo2": 15.0, &"trauma": 20.0,
	&"blood": 20.0, &"arrest": 20.0}

## --- Breathing: SpO2 (hidden from players; a basic version until wave 3's per-lung model) ---
## Percent saturation. Proposed: out under SPO2_UNCONSCIOUS; cardiac arrest after
## SPO2_ARREST_S spent under SPO2_ARREST. The cues: laboured breathing and greying vision
## under SPO2_LABOURED, blue lips under SPO2_BLUE_LIPS.
const SPO2_NORMAL := 98.0
const SPO2_LABOURED := 94.0
const SPO2_BLUE_LIPS := 88.0
const SPO2_UNCONSCIOUS := 85.0
const SPO2_ARREST := 70.0
const SPO2_ARREST_S := 120.0
## What pulls SpO2 down (proposed), as the level it heads for: points off per share of blood
## lost past EFFECTS_FROM_LOST (less blood to carry oxygen: 90% at 40% lost), per open chest
## wound without a seal, for a tension pneumothorax (sealed or not, until wave 3's needle),
## and per dose of morphine in the blood past MORPHINE_DEPRESSION_LEVEL (slowed breathing).
## An obstructed airway heads for SPO2_OBSTRUCTED; cardiac arrest for 0.
const SPO2_BLOOD_DROP := 32.0
const SPO2_OPEN_CHEST := 5.0
const SPO2_TENSION := 24.0
const SPO2_PER_MORPHINE := 12.0
const SPO2_OBSTRUCTED := 40.0
## How fast SpO2 moves toward that level, in points per second (proposed).
const SPO2_FALL_PER_S := 0.5
const SPO2_RISE_PER_S := 1.0

## --- Total trauma (proposed): how badly hurt the body is overall ---
## Each wound counts its kind's severity, scaled down for a partial bleed (its rate against
## the reference rate, at least TRAUMA_MIN_SCALE). A wound that's been dealt with (bandaged,
## packed, sealed, splinted, held by a good tourniquet) counts TRAUMA_HANDLED_SHARE of it. A
## tension pneumothorax and a running concussion add their own. The level jumps up with new
## injuries and fades toward the current sum at TRAUMA_FADE_PER_S. At TRAUMA_UNCONSCIOUS or
## over the casualty stays out: one serious wound (an arterial thigh hit with a broken femur
## is about 0.5, 0.6 with the vein) doesn't do it, two or three do.
const TRAUMA_SEVERITY := {"arterial": 0.3, "junctional": 0.3, "internal": 0.3, "heart": 0.6, "chest": 0.25,
	"fracture": 0.2, "venous": 0.12, "muscle": 0.12, "graze": 0.03, "rib": 0.05}
const TRAUMA_REF_RATE := {"arterial": 1.2, "junctional": 0.8, "internal": 1.0, "venous": 0.4, "muscle": 0.25, "graze": 0.03}
const TRAUMA_MIN_SCALE := 0.3
const TRAUMA_HANDLED_SHARE := 0.4
const TRAUMA_TENSION := 0.25
const TRAUMA_CONCUSSION := 0.2
const TRAUMA_UNCONSCIOUS := 1.0
const TRAUMA_FADE_PER_S := 1.0 / 600.0

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
## Morphine is a level in the blood, in doses (proposed values). A dose goes in over
## MORPHINE_ABSORB_S and the level halves every MORPHINE_HALF_LIFE_S. Pain relief follows
## the level: MORPHINE_RELIEF off per dose in the blood (design doc: 0.5 off over 30 s), at
## most MORPHINE_RELIEF_MAX. Pupils shrink from MORPHINE_PUPILS_LEVEL; from
## MORPHINE_SEDATION_LEVEL the casualty is sedated (out); past MORPHINE_DEPRESSION_LEVEL
## breathing slows and SpO2 falls (SPO2_PER_MORPHINE), which can end in cardiac arrest.
## Wave 3 adds heart-rate effects.
const MORPHINE_ABSORB_S := 30.0
const MORPHINE_HALF_LIFE_S := 720.0
const MORPHINE_RELIEF := 0.5
const MORPHINE_RELIEF_MAX := 0.8
const MORPHINE_PUPILS_LEVEL := 0.5
const MORPHINE_SEDATION_LEVEL := 2.5
const MORPHINE_DEPRESSION_LEVEL := 3.0
## care_tasks() asks for morphine from this much pain still to ease once what's in the body
## has worked (proposed), or for a cracked rib (morphine is its only fix), and only while
## the blood holds at most MORPHINE_ASK_MAX_LEVEL doses (so one more stays under sedation).
const MORPHINE_FROM_PAIN := 0.4
const MORPHINE_ASK_MAX_LEVEL := 1.05
## Airway (proposed): an unconscious casualty without an NPA obstructs with this chance per
## minute; SpO2 then falls toward SPO2_OBSTRUCTED until an NPA goes in. Someone out for
## less than AIRWAY_SELF_CLEAR_S (a short knockout, a brief faint from pain) stirs and clears
## it themselves once the obstruction is all that keeps them out; out longer, only an NPA does.
const AIRWAY_BLOCK_PER_MIN := 0.1
const AIRWAY_SELF_CLEAR_S := 45.0
## Bleeding the field kit can control. Internal (torso) bleeding waits for wave 3's surgery
## kit, so care_tasks() never asks for an item for it.
const FIXABLE_BLEEDS: Array[String] = ["arterial", "junctional", "venous", "muscle", "graze"]
const BANDAGED_KINDS: Array[String] = ["venous", "muscle", "graze"]
## Countdowns that clients run down between updates (to_net "t").
const TIMERS: Array[String] = ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left",
	"treating_left", "wake_left"]

## Impact (shock) from rounds armor stopped. Helmet values are the design doc's table. Plate
## (torso) values are Captain's playtest calls: one or two stops are a bruise, but a burst
## stacks up (six 5.56 stops reach the cap), and plate stops with their cracked ribs raise
## impact up to PLATE_IMPACT_MAX. That plus a cracked rib's floor stays just under the
## knockout threshold at full blood, so plates alone never knock a healthy soldier out, but
## a wounded one who has lost blood can go down. Stagger and being winded come with every stop.
const PLATE_IMPACT_PAIN := {&"pistol": 0.05, &"intermediate": 0.12, &"full_power": 0.22}
const PLATE_IMPACT_MAX := 0.7
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
## Cracked rib from a plate stop, only within these ranges (design doc). The odds are these
## at point-blank range and fall linearly to nothing at the range's end (proposed, retuned
## after Captain's playtest: a 5.56 stop at 50 m cracks a rib about one time in ten).
## A crack adds RIB_PAIN of impact (inside PLATE_IMPACT_MAX) and keeps PAIN_FLOOR_RIB.
const RIB_RANGE_M := {&"pistol": 30.0, &"intermediate": 100.0, &"full_power": 200.0}
const RIB_CRACK_CHANCE := {&"pistol": 0.1, &"intermediate": 0.2, &"full_power": 0.4}
const RIB_PAIN := 0.05
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
## Morphine in the blood and still going in (doses).
var morphine_level := 0.0
var morphine_depot := 0.0
## Oxygen saturation, percent.
var spo2 := SPO2_NORMAL
## Total trauma (see TRAUMA_SEVERITY).
var trauma_level := 0.0
## Unconscious with every cause gone: seconds until they come round (0 while a cause holds).
var wake_left := 0.0
## Dice for the treatment rules (airway), apart from rng so the wound dice repeat.
var care_rng := RandomNumberGenerator.new()

var _time := 0.0
var _last_concussion := -INF
var _heart_arrest_in := -1.0
var _spell_wake_s := 0.0        # how long the worst cause of this spell out takes to wake from
var _low_spo2_s := 0.0          # time spent under SPO2_ARREST
var _out_s := 0.0               # how long this spell out has lasted (host only)
var _pain_over_s := 0.0         # how long pain has stayed at or over the knockout threshold


# --- Queries --------------------------------------------------------------------------

func lost() -> float:
	return 1.0 - blood


## Blood-loss effect strength: 0 up to 15% lost, 1 at 40%.
func shock() -> float:
	return clampf((lost() - EFFECTS_FROM_LOST) / (UNCONSCIOUS_LOST - EFFECTS_FROM_LOST), 0.0, 1.0)


## Wound and impact pain less what the morphine in the blood eases, at least the floor that
## fractures and an untreated cracked rib keep, plus what tourniquets add while they're on.
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
	var eased := maxf(reducible_pain() - morphine_relief(), 0.0)
	return clampf(maxf(eased, floor_pain) + TOURNIQUET_PAIN * tourniquets.size(), 0.0, 1.0)


func knockout_threshold() -> float:
	return lerpf(KNOCKOUT_PAIN_FULL, KNOCKOUT_PAIN_LOW, clampf(lost() / KNOCKOUT_PAIN_LOW_AT, 0.0, 1.0))


## Pain is at or over the knockout threshold and has stayed there for PAIN_KNOCKOUT_S.
func pain_knocks_out() -> bool:
	return pain() >= knockout_threshold() and _pain_over_s >= PAIN_KNOCKOUT_S - 0.001


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


## Why the body is (or would be) unconscious right now, most serious first: &"arrest",
## &"blood" (40% lost), &"spo2", &"pain" (held over the threshold: pain_knocks_out),
## &"trauma", &"morphine" (sedation), &"knockout".
## Empty means nothing keeps it out (if it's still out, it's coming round: wake_left).
func unconscious_causes() -> Array[StringName]:
	var causes: Array[StringName] = []
	if dead:
		return causes
	if arrest:
		causes.append(&"arrest")
	if lost() >= UNCONSCIOUS_LOST:
		causes.append(&"blood")
	if spo2 < SPO2_UNCONSCIOUS:
		causes.append(&"spo2")
	if pain_knocks_out():
		causes.append(&"pain")
	if trauma_level >= TRAUMA_UNCONSCIOUS:
		causes.append(&"trauma")
	if morphine_level >= MORPHINE_SEDATION_LEVEL:
		causes.append(&"morphine")
	if knockout_left > 0.0:
		causes.append(&"knockout")
	return causes


## The SpO2 the body heads for now (see SPO2_BLOOD_DROP).
func spo2_target() -> float:
	if arrest or dead:
		return 0.0
	if airway_blocked:
		return SPO2_OBSTRUCTED
	var target := SPO2_NORMAL - SPO2_BLOOD_DROP * maxf(lost() - EFFECTS_FROM_LOST, 0.0)
	for w in wounds:
		if w.kind != "chest":
			continue
		if w.get("tension", false):
			target -= SPO2_TENSION
		elif not w.treated:
			target -= SPO2_OPEN_CHEST
	target -= SPO2_PER_MORPHINE * maxf(morphine_level - MORPHINE_DEPRESSION_LEVEL, 0.0)
	return clampf(target, 0.0, SPO2_NORMAL)


## Pain the morphine in the blood takes off now.
func morphine_relief() -> float:
	return minf(MORPHINE_RELIEF * morphine_level, MORPHINE_RELIEF_MAX)


## Morphine in the blood plus what's still going in (doses).
func morphine_total() -> float:
	return morphine_level + morphine_depot


## Wound and impact pain still left once all the morphine given so far has gone in.
func pain_to_ease() -> float:
	return maxf(reducible_pain() - minf(MORPHINE_RELIEF * morphine_total(), MORPHINE_RELIEF_MAX), 0.0)


## Another morphine dose is worth giving: the blood holds at most MORPHINE_ASK_MAX_LEVEL.
func morphine_room() -> bool:
	return morphine_total() <= MORPHINE_ASK_MAX_LEVEL


## Breathing is laboured: SpO2 low, an open chest wound or a tension pneumothorax.
func breathing_laboured() -> bool:
	if dead or arrest:
		return false
	if spo2 < SPO2_LABOURED:
		return true
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == "chest" and (not w.treated or w.get("tension", false)))


## What the wounds add up to now (see TRAUMA_SEVERITY); trauma_level heads for it.
func trauma_target() -> float:
	var total := 0.0
	for w in wounds:
		var kind := String(w.kind)
		var severity := float(TRAUMA_SEVERITY.get(kind, 0.0))
		var ref := float(TRAUMA_REF_RATE.get(kind, 0.0))
		if ref > 0.0:
			severity *= clampf(float(w.rate) / ref, TRAUMA_MIN_SCALE, 1.0)
		var handled: bool = w.treated or (ref > 0.0 and float(w.rate) > 0.0 and rate_now(w) <= 0.0)
		if handled:
			severity *= TRAUMA_HANDLED_SHARE
		total += severity
		if w.get("tension", false):
			total += TRAUMA_TENSION
	if concussion_left > 0.0:
		total += TRAUMA_CONCUSSION
	return total


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
## chest wound counts as some) and pain another morphine dose could take off (none while
## the blood already holds enough: morphine_room).
func treatable() -> float:
	var bleed := fixable_bleed_rate()
	for w in wounds:
		if w.kind == "chest" and not w.treated:
			bleed += CHEST_RATE
	var pain_term := pain_to_ease() if morphine_room() else 0.0
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
## for wave 3, and morphine only for pain still left once what's given has worked, while the
## blood has room for a dose (morphine_room). In cardiac arrest neither an NPA nor morphine
## does anything until the heart restarts.
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
	if not arrest and morphine_room() and (pain_to_ease() >= MORPHINE_FROM_PAIN or _untreated_rib()):
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
			return "" if pain_to_ease() > 0.0 or _untreated_rib() else "No pain morphine would ease"
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
			morphine_depot += 1.0  # one dose, going in over MORPHINE_ABSORB_S
			for w in wounds:
				if w.kind == "rib":
					w.treated = true
		NPA:
			npa = true
			airway_blocked = false
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
## Steel spall (round class SPALL) ignores the channel: a scratch or a light wound (add_spall).
func add_hit(part: StringName, channel: Dictionary, round_class: StringName) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if dead:
		return added
	if round_class == SPALL:
		added.append(add_spall(part))
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


## Spall off a steel plate reaches `part`: usually a scratch that doesn't bleed, with
## SPALL_LIGHT_CHANCE a light muscle wound (a bandage fixes it). Returns the wound.
func add_spall(part: StringName) -> Dictionary:
	var w: Dictionary
	var pain_range := PAIN_SPALL_SCRATCH
	if rng.randf() < SPALL_LIGHT_CHANCE:
		w = _add_wound(part, "muscle", SPALL_LIGHT_RATE)
		pain_range = PAIN_SPALL_LIGHT
	else:
		w = _add_wound(part, "graze", 0.0)
	pain_wounds = minf(pain_wounds + rng.randf_range(pain_range.x, pain_range.y), 1.0)
	update_state(0.0)
	return w


## A round armor stopped still lands on `part` (impact table above). Plate (torso) stops add
## their impact only up to PLATE_IMPACT_MAX, a cracked rib's included; helmet stops add theirs
## in full and can concuss (or, from a full-power round close enough, kill).
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
		var added := float(PLATE_IMPACT_PAIN.get(round_class, 0.0))
		if round_class == &"intermediate":
			stagger_left = maxf(stagger_left, STAGGER_S)
		elif round_class == &"full_power":
			stagger_left = maxf(stagger_left, STAGGER_S)
			winded_left = maxf(winded_left, WINDED_S)
		var rib_chance := rib_crack_chance(round_class, distance)
		if rib_chance > 0.0 and rng.randf() < rib_chance:
			if not has_kind("rib"):
				_add_wound(&"chest", "rib", 0.0, &"rib")
			added += RIB_PAIN
		impact = maxf(impact, minf(impact + added, PLATE_IMPACT_MAX))
	impact = minf(impact, 1.0)
	update_state(0.0)


## Chance that a plate stop of `round_class` from `distance` metres cracks a rib: the
## point-blank odds falling linearly to 0 at the end of the class's range.
static func rib_crack_chance(round_class: StringName, distance: float) -> float:
	var reach := float(RIB_RANGE_M.get(round_class, 0.0))
	if reach <= 0.0 or distance > reach:
		return 0.0
	return float(RIB_CRACK_CHANCE.get(round_class, 0.0)) * clampf(1.0 - distance / reach, 0.0, 1.0)


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
	tourniquets.clear()
	npa = false
	airway_blocked = false
	treating_left = 0.0
	morphine_level = 0.0
	morphine_depot = 0.0
	spo2 = SPO2_NORMAL
	trauma_level = 0.0
	wake_left = 0.0
	_spell_wake_s = 0.0
	_low_spo2_s = 0.0
	_out_s = 0.0
	_pain_over_s = 0.0


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
	pain_wounds = maxf(pain_wounds - PAIN_FADE_PER_S * dt, 0.0)
	impact = maxf(impact - IMPACT_FADE_PER_S * dt, 0.0)
	_advance_morphine(dt)
	# Bleeding, scaled by what the heart still pushes out.
	blood = maxf(blood - bleed_rate() / 60.0 * dt / BLOOD_L, 0.0)
	if blood < 1.0 and not arrest and wound_bleed_rate() <= 0.0:
		blood = minf(blood + BLOOD_RECOVER_PER_MIN / 60.0 * dt, 1.0)  # slow recovery once nothing bleeds
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
	_update_airway(dt)
	_advance_spo2(dt)
	_advance_trauma(dt)
	update_state(dt)


## Re-evaluates consciousness and arrest from the current state. Out while any cause holds;
## once none does, the casualty comes round after WAKE_S of the worst cause this spell (the
## countdown starts over if a cause comes back). `dt` runs that countdown, and the time pain
## has stayed at or over the knockout threshold (pain_knocks_out).
func update_state(dt: float) -> void:
	if dead:
		return
	if not arrest and lost() >= ARREST_LOST:
		_start_arrest()
	trauma_level = maxf(trauma_level, trauma_target())  # new injuries count at once
	_pain_over_s = _pain_over_s + dt if pain() >= knockout_threshold() else 0.0
	var causes := unconscious_causes()
	if not causes.is_empty():
		unconscious = true
		wake_left = 0.0
		for cause in causes:
			_spell_wake_s = maxf(_spell_wake_s, float(WAKE_S[cause]))
		return
	if not unconscious:
		return
	if wake_left <= 0.0:
		wake_left = maxf(_spell_wake_s, 0.01)  # every cause just went: start coming round
		return
	wake_left -= dt
	if wake_left <= 0.0:
		_wake()


# --- Replication ----------------------------------------------------------------------

## Compact state for Vitals.net_state. "t" holds countdowns, which clients run down locally.
## Wounds are [part, kind, rate, treated, name, flags (1 packed, 2 tension)]; "q" holds the
## tourniquets as {part: [count, rushed]}; "o" is SpO2, "m" and "d" morphine in the blood and
## still going in, "x" total trauma. Flag 64 (coming round) only makes the start of the wake
## countdown go out at once; clients read the countdown itself from "t". Flag 128: pain has
## been held over the knockout threshold long enough (pain_knocks_out).
func to_net() -> Dictionary:
	var list: Array = []
	for w in wounds:
		var wound_flags := (1 if w.get("packed", false) else 0) | (2 if w.get("tension", false) else 0)
		list.append([String(w.part), w.kind, snappedf(float(w.rate), 0.001), 1 if w.treated else 0, String(w.name), wound_flags])
	var flags := (1 if unconscious else 0) | (2 if arrest else 0) | (4 if dead else 0) | (16 if npa else 0) | (32 if airway_blocked else 0) \
		| (64 if wake_left > 0.0 else 0) | (128 if _pain_over_s >= PAIN_KNOCKOUT_S - 0.001 else 0)
	var timers := {}
	for key: String in TIMERS:
		if float(get(key)) > 0.0:
			timers[key] = snappedf(float(get(key)), 0.1)
	var tq := {}
	for part: StringName in tourniquets:
		tq[String(part)] = [int(tourniquets[part].count), int(tourniquets[part].rushed)]
	return {"b": snappedf(blood, 0.001), "p": snappedf(pain_wounds, 0.01), "i": snappedf(impact, 0.01),
		"f": flags, "w": list, "q": tq, "t": timers, "o": snappedf(spo2, 0.5), "m": snappedf(morphine_level, 0.01),
		"d": snappedf(morphine_depot, 0.01), "x": snappedf(trauma_level, 0.01)}


## Rebuilds this copy from a peer's net_state (clients).
func apply_net(state: Dictionary) -> void:
	blood = float(state.get("b", 1.0))
	pain_wounds = float(state.get("p", 0.0))
	impact = float(state.get("i", 0.0))
	spo2 = float(state.get("o", SPO2_NORMAL))
	morphine_level = float(state.get("m", 0.0))
	morphine_depot = float(state.get("d", 0.0))
	trauma_level = float(state.get("x", 0.0))
	var flags := int(state.get("f", 0))
	unconscious = flags & 1 != 0
	arrest = flags & 2 != 0
	dead = flags & 4 != 0
	npa = flags & 16 != 0
	airway_blocked = flags & 32 != 0
	_pain_over_s = PAIN_KNOCKOUT_S if flags & 128 != 0 else 0.0
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


## An unconscious casualty without an NPA can obstruct; then SpO2 falls (spo2_target) until
## an NPA goes in, and low for long enough it stops the heart. Waking clears it, and so does
## a casualty out only briefly (AIRWAY_SELF_CLEAR_S) once nothing but the obstruction holds.
func _update_airway(dt: float) -> void:
	if not unconscious:
		airway_blocked = false
		_out_s = 0.0
		return
	_out_s += dt
	if arrest or npa:
		return
	if airway_blocked:
		var causes := unconscious_causes()
		if _out_s < AIRWAY_SELF_CLEAR_S and causes.size() <= 1 and (causes.is_empty() or causes[0] == &"spo2"):
			airway_blocked = false  # coming up, they cough and turn: SpO2 recovers, then they wake
		return
	if care_rng.randf() < 1.0 - pow(1.0 - AIRWAY_BLOCK_PER_MIN, dt / 60.0):
		airway_blocked = true


## Morphine goes in from the depot (a dose per MORPHINE_ABSORB_S) and the blood level halves
## every MORPHINE_HALF_LIFE_S.
func _advance_morphine(dt: float) -> void:
	morphine_level *= pow(0.5, dt / MORPHINE_HALF_LIFE_S)
	if morphine_depot > 0.0:
		var step := minf(morphine_depot, dt / MORPHINE_ABSORB_S)
		morphine_depot -= step
		morphine_level += step
	if morphine_level < 0.001 and morphine_depot <= 0.0:
		morphine_level = 0.0


## SpO2 moves toward spo2_target(); SPO2_ARREST_S under SPO2_ARREST stops the heart.
func _advance_spo2(dt: float) -> void:
	var target := spo2_target()
	spo2 = move_toward(spo2, target, (SPO2_FALL_PER_S if target < spo2 else SPO2_RISE_PER_S) * dt)
	if spo2 >= SPO2_ARREST or arrest:
		_low_spo2_s = 0.0
		return
	_low_spo2_s += dt
	if _low_spo2_s >= SPO2_ARREST_S:
		_start_arrest()


## Total trauma fades toward what the wounds add up to now (update_state raises it at once).
func _advance_trauma(dt: float) -> void:
	trauma_level = move_toward(trauma_level, trauma_target(), TRAUMA_FADE_PER_S * dt)


func _wake() -> void:
	unconscious = false
	wake_left = 0.0
	_spell_wake_s = 0.0
	airway_blocked = false
	_out_s = 0.0


func _start_arrest() -> void:
	if arrest or dead:
		return
	arrest = true
	arrest_left = ARREST_WINDOW_S
	_heart_arrest_in = -1.0
	_low_spo2_s = 0.0


func _concuss() -> void:
	var mult := 2.0 if _time - _last_concussion < SAME_FIGHT_S else 1.0
	_last_concussion = _time
	var knockout := 0.0
	if rng.randf() < CONCUSSION_KO_CHANCE:
		knockout = rng.randf_range(CONCUSSION_KO_S.x, CONCUSSION_KO_S.y) * mult
		knockout_left = maxf(knockout_left, knockout)
	concussion_left = maxf(concussion_left, knockout + CONCUSSION_S * mult)
